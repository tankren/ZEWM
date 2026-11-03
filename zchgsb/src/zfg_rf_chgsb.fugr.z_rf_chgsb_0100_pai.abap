FUNCTION z_rf_chgsb_0100_pai
  CHANGING
    ordim_confirm    TYPE /scwm/s_rf_ordim_confirm
    tt_ordim_confirm TYPE /scwm/tt_rf_ordim_confirm
    tt_nested_hu     TYPE /scwm/tt_rf_nested_hu
    wme_verif        TYPE /scwm/s_wme_verif
    resource         TYPE /scwm/s_rsrc
    t_rf_pick_hus    TYPE /scwm/tt_rf_pick_hus
    who              TYPE /scwm/s_who_int.

TYPE-POOLS: wmegc.
*----------------------------------------------------------------------*
* CHGSB 主逻辑：扫码换源货位
*   1. 前置校验：当前 WT 未确认 / 未部分确认
*   2. 新货位校验：必输、同库存类型、货位存在未冻结
*   3. 确认原 WT 为全量差异（ndifa = vsola, nista = 0）→ COMMIT 释放数量
*   4. 用新货位建 WT（/SCWM/TO_CREA_INT）→ 检查返回
*   5. TO_POST 补过账，COMMIT
*   6. 任一失败：报错 + 不静默（第 3 步已提交，无法回滚）
*----------------------------------------------------------------------*

  DATA: lv_fcode    TYPE /scwm/de_fcode,
        lv_lgnum    TYPE /scwm/lgnum,
        lv_ndifa    TYPE /scwm/ltap_vsola,
        lt_create   TYPE /scwm/tt_to_create_int,
        ls_create   TYPE /scwm/s_to_create_int,
        et_ltap_vb  TYPE /scwm/tt_ltap_vb,
        et_bapiret  TYPE bapirettab,
        ev_severity TYPE bapi_mtype,
        lt_bapiret  TYPE bapirettab,
        ls_ordim_o  TYPE /scwm/ordim_o,
        lv_new_tanum TYPE /scwm/tanum,
        lv_restart  TYPE xfeld,
        lv_ser_err  TYPE xfeld,
        lt_lgpla    TYPE /scwm/tt_lgpla,
        ls_lagp     TYPE /scwm/lagp,
        ls_lagp_int TYPE /scwm/s_lagp_int,
        lv_severity TYPE bapi_mtype,
        lv_allowed  TYPE xfeld,
        lv_objnr    TYPE /lime/guid_loc.

  lv_fcode = /scwm/cl_rf_bll_srvc=>get_fcode( ).
  lv_lgnum = /scwm/cl_rf_bll_srvc=>get_lgnum( ).
  /scwm/cl_tm=>set_lgnum( lv_lgnum ).

  CASE lv_fcode.
    WHEN 'BACK'.
*     框架按 step flow 弹栈回 PIMTTO，这里不用做事
      RETURN.

    WHEN OTHERS.   " ENTER
*--------------------------------------------------------------------*
* 1. 前置校验：当前行必须可改
*--------------------------------------------------------------------*
      IF ordim_confirm-tanum IS INITIAL OR ordim_confirm-vlenr IS INITIAL.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e012(zewm_rf_msg).        " 无有效拣货行
      ENDIF.

      IF gs_chgsb_scr-newlgpla IS INITIAL.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e013(zewm_rf_msg).        " 请输入/扫描新货位
      ENDIF.

*--------------------------------------------------------------------*
* 2. 新货位校验
*--------------------------------------------------------------------*
      TRANSLATE gs_chgsb_scr-newlgpla TO UPPER CASE.
      CONDENSE gs_chgsb_scr-newlgpla.

* 与源货位相同 → 无需处理
      IF gs_chgsb_scr-newlgpla = ordim_confirm-vlpla.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e014(zewm_rf_msg).        " 新旧货位相同
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
      ENDIF.

* 2.2 货位主数据：必须存在，且与源行同一库存类型
*     （跨库存类型拣货不合法，直接拒绝）
      CLEAR ls_lagp.
      SELECT SINGLE * FROM /scwm/lagp
        INTO ls_lagp
        WHERE lgnum = lv_lgnum
          AND lgpla = gs_chgsb_scr-newlgpla.

      IF sy-subrc <> 0 OR ls_lagp-lgtyp <> ordim_confirm-vltyp.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e017(zewm_rf_msg).
      ENDIF.

* 2.3 冻结标识：SKZUA = 出库冻结（不允许 removal）
      IF ls_lagp-skzua = 'X'.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e017(zewm_rf_msg).
      ENDIF.

* 2.4 货位用户状态：检查“拣货/出库”活动是否允许
*     标准 BIN_STAT_CHANGE 用同一常量维护 LAGP-SKZUA，两者结果一致；
*     货位没有状态对象时跳过，避免 FM 内部 MESSAGE e132 干扰操作员
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
          ENDIF.
        ENDIF.
      ENDIF.

* 2.5 记下新货位库存类型（已校验与源行一致，供后续建 WT 使用）
      gs_chgsb_scr-newlgtyp = ls_lagp-lgtyp.

* TODO HU / 批次一致性校验（若带 HU）：
*   - HU 的批次 = DN 需求批次
*   - HU 未被其他 WT 占用
* 需先确认 t_rf_pick_hus / tt_nested_hu 的实际字段。

*--------------------------------------------------------------------*
* 3. 把当前 WT 确认为「全量差异」
*    ndifa = vsola（差异数 = 应拣数），nista = 0
*    绝不设 bind = 'X'，否则标准 CREATE_BIN_DENIAL 会自动再建一个 WT
*--------------------------------------------------------------------*
      lv_ndifa = ordim_confirm-vsola.

      ordim_confirm-ndifa = lv_ndifa.
      ordim_confirm-nista = 0.

      CALL FUNCTION '/SCWM/RF_PICK_ORDIM_CONFIRM'
        EXPORTING
          iv_simulate       = space
          iv_serial_no_check = space
        IMPORTING
          ev_restart_transaction = lv_restart
          ev_ser_err             = lv_ser_err
        CHANGING
          resource         = resource
          tt_ordim_confirm = tt_ordim_confirm
          ordim_confirm    = ordim_confirm
          tt_nested_hu     = tt_nested_hu
          who              = who
          t_rf_pick_hus    = t_rf_pick_hus.

*     确认后数量已释放，必须落库
      COMMIT WORK AND WAIT.

*--------------------------------------------------------------------*
* 4. 建 WT + 过账：/SCWM/TO_CREATE（= TO_CREA_INT + TO_POST）
*    关键：必须继承原行的货单参考（RDOCCAT/RDOCID/QDOCCAT/QDOCID），
*    否则建出来的 WT 不带 ODO 参考，后续拣配/发货回收不到。
*--------------------------------------------------------------------*
      CLEAR: ls_create, lt_create.

      ls_create-procty  = ordim_confirm-procty.        " 流程类型（与源行一致）
      ls_create-vltyp   = ordim_confirm-vltyp.         " 同库存类型
      ls_create-vlpla   = gs_chgsb_scr-newlgpla.       " 新货位
      ls_create-matid   = ordim_confirm-matid.
      ls_create-batchid = ordim_confirm-batchid.
      ls_create-anfme   = lv_ndifa.                    " 数量 = 差异数
      ls_create-sguid_hu = ordim_confirm-sguid_hu.     " 带 HU 就带上

*     仓库请求 / ODO 参考：从原 WT 行继承（RDOCCAT='PDO'，RDOCID/RITMID 为 32 位 GUID）
*     注意：RDOCID（文档 GUID）与 RITMID（行项目 GUID）是两个不同值，不能混用
      ls_create-rdoccat = ordim_confirm-rdoccat.
      ls_create-rdocid  = ordim_confirm-rdocid.

*     QDOC 这组场景上经常为空（QDOCCAT 空、QDOCID 全 0），有值才继承
      IF ordim_confirm-qdoccat IS NOT INITIAL.
        ls_create-qdoccat = ordim_confirm-qdoccat.
        ls_create-qdocid  = ordim_confirm-qdocid.
      ENDIF.

      ls_create-doccat  = ordim_confirm-doccat.

*     库存所属单据：从原行继承，保证库存归属不变
      ls_create-stock_doccat = ordim_confirm-stock_doccat.
      ls_create-stock_docno  = ordim_confirm-stock_docno.

*     不重复做库存校验：数量已在第 3 步释放并确认过
      ls_create-no_stock_det = 'X'.

*     WO / 波次：从原行继承（若为空，由系统按仓管策略重定）
      ls_create-who     = ordim_confirm-who.
      ls_create-wave    = ordim_confirm-wave.

*     RITMID / QITMID：S_RF_ORDIM_CONFIRM 里没有，读原 WT 行补齐
      SELECT SINGLE * FROM /scwm/ordim_o
        INTO ls_ordim_o
        WHERE tanum = ordim_confirm-tanum
          AND vlenr = ordim_confirm-vlenr.
      IF sy-subrc = 0.
        ls_create-ritmid = ls_ordim_o-ritmid.
        IF ls_ordim_o-qdoccat IS NOT INITIAL.
          ls_create-qitmid = ls_ordim_o-qitmid.
        ENDIF.
*       原行参考优先用 ORDIM_O 的真实值
        IF ls_ordim_o-rdoccat IS NOT INITIAL.
          ls_create-rdoccat = ls_ordim_o-rdoccat.
          ls_create-rdocid  = ls_ordim_o-rdocid.
        ENDIF.
      ENDIF.

      APPEND ls_create TO lt_create.

      CALL FUNCTION '/SCWM/TO_CREATE'
        EXPORTING
          iv_lgnum        = lv_lgnum
          iv_commit_work  = 'X'
          iv_bname        = sy-uname
          it_create       = lt_create
        IMPORTING
          ev_tanum        = lv_new_tanum
          et_ltap_vb      = et_ltap_vb
          et_bapiret      = et_bapiret
          ev_severity     = ev_severity.

*     内部 CATCH 吞异常，必须自己判断返回
      IF ev_severity = 'E' OR ev_severity = 'A'
         OR lv_new_tanum IS INITIAL.
*       第 3 步已 COMMIT，此处必须显式报错 + 落补偿标记，不允许静默
        MESSAGE e015(zewm_rf_msg).      " 建 WT 失败：原任务已确认，需人工补偿
      ENDIF.

*--------------------------------------------------------------------*
* 5. 完成，回 PIMTTO
*--------------------------------------------------------------------*
      /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
      MESSAGE s016(zewm_rf_msg).        " 源货位已更改
  ENDCASE.
ENDFUNCTION.
