FUNCTION zewm_rf_zchgsb_9100_pai.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  CHANGING
*"     REFERENCE(ORDIM_CONFIRM) TYPE  /SCWM/S_RF_ORDIM_CONFIRM
*"     REFERENCE(TT_ORDIM_CONFIRM) TYPE  /SCWM/TT_RF_ORDIM_CONFIRM
*"     REFERENCE(TT_NESTED_HU) TYPE  /SCWM/TT_RF_NESTED_HU
*"     REFERENCE(WME_VERIF) TYPE  /SCWM/S_WME_VERIF
*"     REFERENCE(RESOURCE) TYPE  /SCWM/S_RSRC
*"     REFERENCE(T_RF_PICK_HUS) TYPE  /SCWM/TT_RF_PICK_HUS
*"     REFERENCE(WHO) TYPE  /SCWM/S_WHO_INT
*"----------------------------------------------------------------------
TYPE-POOLS: wmegc.
*----------------------------------------------------------------------*
* CHGSB 主逻辑：扫码换源货位
*   1. 前置校验：当前 WT 未确认 / 未部分确认
*   2. 新货位校验：必输、同库存类型、货位存在未冻结
*   3. 把扫描货位写进内存（供 BAdI /SCWM/EX_CORE_RMS_DETERMINE 过滤）
*   4. 设快捷码 ZCSB 并跳标准 exception 链路（FM /SCWM/RF_PICK_EXCEPTION）
*      -> 标准 BIDU 流程负责：0 数量确认 + bin denial + 重定货位建 WT
*----------------------------------------------------------------------*

* 内存上下文：使用 /SCWM/LTAP，PAI 与 BAdI 共享同一类型，避免结构不兼容。
* 标准 bin denial 会在调用 REM_BIN_DET 前清空 VLPLA/TANUM，
* 所以 BAdI 只能按 LGNUM + MATID (+ BATCHID) 匹配。
  DATA: ls_ctx TYPE /scwm/ltap.

  DATA: lv_fcode    TYPE /scwm/de_fcode,
        lv_lgnum    TYPE /scwm/lgnum,
        lt_bapiret  TYPE bapirettab,
        lt_lgpla    TYPE /scwm/tt_lgpla,
        ls_lagp     TYPE /scwm/lagp,
        ls_lagp_int TYPE /scwm/s_lagp_int,
        lv_severity TYPE bapi_mtype,
        lv_allowed  TYPE xfeld,
        lv_objnr    TYPE /lime/guid_loc,
        lt_huitm    TYPE /scwm/tt_stock_select,
        ls_huitm    TYPE /scwm/s_stock_select,
        ls_sel      TYPE rsdsselopt,
        lr_lgpla    TYPE rseloption,
        lr_matnr    TYPE rseloption,
        lr_charg    TYPE rseloption,
        lr_cat      TYPE rseloption,
        lr_usage    TYPE rseloption,
        lr_owner    TYPE rseloption,
        lr_entitled TYPE rseloption,
        lv_avail_alt  TYPE /scwm/de_quantity,
        lv_target_uom TYPE meins.

  lv_fcode = /scwm/cl_rf_bll_srvc=>get_fcode( ).
  lv_lgnum = ordim_confirm-lgnum.
  IF lv_lgnum IS INITIAL.
    lv_lgnum = resource-lgnum.
  ENDIF.
  IF lv_lgnum IS INITIAL.
    lv_lgnum = who-lgnum.
  ENDIF.
  IF lv_lgnum IS INITIAL.
    lv_lgnum = /scwm/cl_rf_bll_srvc=>get_lgnum( ).
  ENDIF.
  /scwm/cl_tm=>set_lgnum( lv_lgnum ).
  /scwm/cl_rf_bll_srvc=>set_lgnum( lv_lgnum ).

  CASE lv_fcode.
    WHEN 'BACK'.
*     框架按 step flow 弹栈回 PIMTTO
      FREE MEMORY ID 'ZCHGSB_CTX'.
      CLEAR zcl_zewm_rms_det_chgsb=>gv_ctx_set.
      /scwm/cl_rf_bll_srvc=>clear_shortcut( ).
      RETURN.

    WHEN OTHERS.   " ENTER
*--------------------------------------------------------------------*
* 1. 前置校验：当前行必须可改
*--------------------------------------------------------------------*
      IF ordim_confirm-tanum IS INITIAL.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e012(zewm_rf_msg).        " 诊断：tanum 为空
        RETURN.
      ENDIF.

      IF gs_chgsb_scr-newlgpla IS INITIAL.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e013(zewm_rf_msg).        " 请输入/扫描新货位
        RETURN.
      ENDIF.

*--------------------------------------------------------------------*
* 2. 新货位校验
*--------------------------------------------------------------------*
      TRANSLATE gs_chgsb_scr-newlgpla TO UPPER CASE.
      CONDENSE gs_chgsb_scr-newlgpla.

* 与源货位相同 -> 无需处理
      IF gs_chgsb_scr-newlgpla = ordim_confirm-vlpla.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e014(zewm_rf_msg).        " 新旧货位相同
        RETURN.
      ENDIF.

* 2.1 货位存在性：标准 FM，能处理子货位/动态货位
      CLEAR: lt_lgpla, lt_bapiret.
      APPEND gs_chgsb_scr-newlgpla TO lt_lgpla.

      CALL FUNCTION '/SCWM/BIN_EXIST_CHECK'
        EXPORTING
          it_lgpla      = lt_lgpla
          iv_lgnum      = lv_lgnum
        IMPORTING
          et_bapiret    = lt_bapiret
          e_rc_severity = lv_severity.

      IF lv_severity <> 'S'.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e017(zewm_rf_msg).        " 货位不存在或无效
        RETURN.
      ENDIF.

* 2.2 货位主数据：必须存在，且与源行同一库存类型
      CLEAR ls_lagp.
      SELECT SINGLE * FROM /scwm/lagp
        INTO ls_lagp
        WHERE lgnum = lv_lgnum
          AND lgpla = gs_chgsb_scr-newlgpla.

      IF sy-subrc <> 0 OR ls_lagp-lgtyp <> ordim_confirm-vltyp.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e017(zewm_rf_msg).
        RETURN.
      ENDIF.

* 2.3 冻结标识：SKZUA = 出库冻结（不允许 removal）
      IF ls_lagp-skzua = 'X'.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e017(zewm_rf_msg).
        RETURN.
      ENDIF.

* 2.4 货位用户状态：检查“拣货/出库”活动是否允许
      IF ls_lagp-guid_loc IS NOT INITIAL.
        CLEAR lv_objnr.
        SELECT SINGLE objnr FROM /scwm/binstobj
          INTO lv_objnr
          WHERE objnr = ls_lagp-guid_loc.
        IF sy-subrc = 0.
          CLEAR: ls_lagp_int, lv_allowed.
          MOVE-CORRESPONDING ls_lagp TO ls_lagp_int.
          CALL FUNCTION '/SCWM/BIN_ACT_CHECK'
            EXPORTING
              iv_activity = wmegc_binact_pick
              is_lagp     = ls_lagp_int
            IMPORTING
              ev_allowed  = lv_allowed.
          IF lv_allowed IS INITIAL.
            /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
            MESSAGE e017(zewm_rf_msg).
            RETURN.
          ENDIF.
        ENDIF.
      ENDIF.

* 2.5 可用库存校验：扫描货位中当前物料/批次的可用量必须 >= VSOLA
      IF ordim_confirm-vsola > 0.
        CLEAR: lt_huitm, lr_lgpla, lr_matnr, lr_charg,
               lr_cat, lr_usage, lr_owner, lr_entitled.

        CLEAR ls_sel.
        ls_sel-sign   = 'I'.
        ls_sel-option = 'EQ'.

        ls_sel-low = gs_chgsb_scr-newlgpla.
        APPEND ls_sel TO lr_lgpla.

        IF ordim_confirm-matnr IS NOT INITIAL.
          ls_sel-low = ordim_confirm-matnr.
          APPEND ls_sel TO lr_matnr.
        ENDIF.

        IF ordim_confirm-batch IS NOT INITIAL.
          ls_sel-low = ordim_confirm-batch.
          APPEND ls_sel TO lr_charg.
        ENDIF.

        IF ordim_confirm-cat IS NOT INITIAL.
          ls_sel-low = ordim_confirm-cat.
          APPEND ls_sel TO lr_cat.
        ENDIF.
        IF ordim_confirm-stock_usage IS NOT INITIAL.
          ls_sel-low = ordim_confirm-stock_usage.
          APPEND ls_sel TO lr_usage.
        ENDIF.
        IF ordim_confirm-owner IS NOT INITIAL.
          ls_sel-low = ordim_confirm-owner.
          APPEND ls_sel TO lr_owner.
        ENDIF.
        IF ordim_confirm-entitled IS NOT INITIAL.
          ls_sel-low = ordim_confirm-entitled.
          APPEND ls_sel TO lr_entitled.
        ENDIF.

        CALL FUNCTION '/SCWM/SELECT_STOCK'
          EXPORTING
            iv_lgnum       = lv_lgnum
            ir_lgpla       = lr_lgpla
            ir_matnr       = lr_matnr
            ir_charg       = lr_charg
            ir_cat         = lr_cat
            ir_stock_usage = lr_usage
            ir_owner       = lr_owner
            ir_entitled    = lr_entitled
          IMPORTING
            et_huitm       = lt_huitm
          EXCEPTIONS
            error          = 1
            OTHERS         = 2.

        lv_target_uom = ordim_confirm-altme.
        IF lv_target_uom IS INITIAL.
          lv_target_uom = ordim_confirm-meins.
        ENDIF.

        CLEAR lv_avail_alt.
        IF sy-subrc = 0.
          LOOP AT lt_huitm INTO ls_huitm.
            IF ls_huitm-altme = lv_target_uom.
              lv_avail_alt = lv_avail_alt + ls_huitm-quana.
            ELSEIF ls_huitm-meins = lv_target_uom.
              lv_avail_alt = lv_avail_alt + ls_huitm-quan.
            ENDIF.
          ENDLOOP.
        ENDIF.

        IF sy-subrc <> 0 OR lv_avail_alt < ordim_confirm-vsola.
          /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
          MESSAGE e036(/scwm/ui_adma).
          RETURN.
        ENDIF.
      ENDIF.

* 2.6 记下新货位库存类型（已校验与源行一致）
      gs_chgsb_scr-newlgtyp = ls_lagp-lgtyp.

*--------------------------------------------------------------------*
* 3. 扫描货位写入内存，供 BAdI 过滤候选 quant
*    标准 bin denial 已清空原货位/TANUM，故 BAdI 按
*    LGNUM + MATID (+ BATCHID) 匹配本次拣货行。
*--------------------------------------------------------------------*
      FREE MEMORY ID 'ZCHGSB_CTX'.
      CLEAR ls_ctx.
      ls_ctx-lgnum   = lv_lgnum.
      ls_ctx-tanum   = ordim_confirm-tanum.
      ls_ctx-vlpla   = ordim_confirm-vlpla.
      ls_ctx-matid   = ordim_confirm-matid.
      ls_ctx-batchid = ordim_confirm-batchid.
      ls_ctx-matnr   = ordim_confirm-matnr.
      ls_ctx-charg   = ordim_confirm-batch.
      ls_ctx-vsola   = ordim_confirm-vsola.
      ls_ctx-altme   = ordim_confirm-altme.
      ls_ctx-nlpla   = gs_chgsb_scr-newlgpla.
      EXPORT ctx = ls_ctx TO MEMORY ID 'ZCHGSB_CTX'.
      zcl_zewm_rms_det_chgsb=>gs_ctx = ls_ctx.
      zcl_zewm_rms_det_chgsb=>gv_ctx_set = abap_true.

*--------------------------------------------------------------------*
* 4. 跳标准 exception 链路
*    快捷码 ZCSB（内部流程代码 BIDU）-> /SCWM/RF_PICK_EXCEPTION
*    由 TSTEP_FLOW：STEP=CHGSB / FCODE=EXCEPT -> RF_PICK_EXCEPTION / PIMTTO
*    标准逻辑会做：ndifa = vsola、nista = 0、bind = 'X'，
*    再由标准 CREATE_BIN_DENIAL 重定货位并建新 WT
*--------------------------------------------------------------------*
      /scwm/cl_rf_bll_srvc=>set_shortcut( 'ZCSB' ).
      /scwm/cl_rf_bll_srvc=>set_prmod( '1' ).
      /scwm/cl_rf_bll_srvc=>set_fcode( 'EXCEPT' ).
  ENDCASE.
ENDFUNCTION.
