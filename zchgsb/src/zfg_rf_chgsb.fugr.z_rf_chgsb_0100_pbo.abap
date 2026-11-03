FUNCTION z_rf_chgsb_0100_pbo
  CHANGING
    ordim_confirm    TYPE /scwm/s_rf_ordim_confirm
    tt_ordim_confirm TYPE /scwm/tt_rf_ordim_confirm
    tt_nested_hu     TYPE /scwm/tt_rf_nested_hu
    wme_verif        TYPE /scwm/s_wme_verif
    resource         TYPE /scwm/s_rsrc
    t_rf_pick_hus    TYPE /scwm/tt_rf_pick_hus
    who              TYPE /scwm/s_who_int.
*----------------------------------------------------------------------*
* PIMTTO 屏幕按 CHGSB → 本屏（换源货位）
* PBO 职责：把框架已装入 ORDIM_CONFIRM 的当前拣货行显示到屏幕，
*           并清空「新货位」输入字段，等用户扫码。只读，不写库。
* 签名与 /SCWM/RF_PICK_PIMTTO_PBO 一致，框架按同名 CHANGING 传参。
*----------------------------------------------------------------------*

  DATA: lv_lgnum    TYPE /scwm/lgnum,
        lt_matid    TYPE /scwm/tt_matid,
        lt_matnr    TYPE /scwm/tt_matid_matnr,
        lt_batch_sr TYPE /scwm/t_batch_sr.

  lv_lgnum = /scwm/cl_rf_bll_srvc=>get_lgnum( ).
  /scwm/cl_tm=>set_lgnum( lv_lgnum ).

*----------------------------------------------------------------------*
* 1. 原拣货行 → 屏幕展示
*----------------------------------------------------------------------*
  CLEAR gs_chgsb_scr.

  gs_chgsb_scr-vltyp   = ordim_confirm-vltyp.     " 源库存类型
  gs_chgsb_scr-vlpla   = ordim_confirm-vlpla.     " 原货位
  gs_chgsb_scr-vsola   = ordim_confirm-vsola.     " 应拣数量
  gs_chgsb_scr-huident = ordim_confirm-huident.   " 处理单元
  gs_chgsb_scr-tanum   = ordim_confirm-tanum.     " WT 号
  gs_chgsb_scr-vlenr   = ordim_confirm-vlenr.     " WT 行号

* 物料 GUID → 物料号（可读）
  IF ordim_confirm-matid IS NOT INITIAL.
    APPEND ordim_confirm-matid TO lt_matid.
    TRY.
        CALL FUNCTION '/SCWM/MATID_TO_MATNR_MULTIPLE'
          EXPORTING
            it_matid       = lt_matid
          IMPORTING
            et_matid_matnr = lt_matnr.
        READ TABLE lt_matnr INTO DATA(ls_matnr_line) INDEX 1.
        IF sy-subrc = 0.
          gs_chgsb_scr-matnr = ls_matnr_line-matnr.
        ENDIF.
      CATCH cx_root.
        CLEAR gs_chgsb_scr-matnr.
    ENDTRY.
  ENDIF.

* 批次 GUID → 批号（可读）：先取该物料全部批次，再按 BATCHID 匹配
  IF ordim_confirm-matid IS NOT INITIAL
     AND ordim_confirm-batchid IS NOT INITIAL.
    TRY.
        CALL FUNCTION '/SCWM/BATCH_SEARCH2'
          EXPORTING
            iv_matid    = ordim_confirm-matid
            iv_lgnum    = lv_lgnum
          IMPORTING
            et_batch_sr = lt_batch_sr.
        READ TABLE lt_batch_sr INTO DATA(ls_batch_line)
             WITH KEY batchid = ordim_confirm-batchid.
        IF sy-subrc = 0.
          gs_chgsb_scr-charg = ls_batch_line-charg.
        ENDIF.
      CATCH cx_root.
        CLEAR gs_chgsb_scr-charg.
    ENDTRY.
  ENDIF.

* 每次进屏清空输入字段，避免上一轮残留
  CLEAR: gs_chgsb_scr-newlgpla,
         gs_chgsb_scr-newlgtyp.

* 显式打开输入字段属性
* （zdifhu 踩坑：dynpro 字段若带 REQU_ENTRY，在 RF 里会变成不可输入，
*   必须由 PBO 调 set_screlm_input_on 打开）
  /scwm/cl_rf_bll_srvc=>set_screlm_input_on( 'GS_CHGSB_SCR-NEWLGPLA' ).

*----------------------------------------------------------------------*
* 2. 状态行
*----------------------------------------------------------------------*
  gs_chgsb_scr-txt = 'Scan new source bin'(001).
ENDFUNCTION.
