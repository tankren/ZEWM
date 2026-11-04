FUNCTION zewm_rf_zchgsb_9100_pbo
  CHANGING
    ordim_confirm TYPE /scwm/s_rf_ordim_confirm
    tt_ordim_confirm TYPE /scwm/tt_rf_ordim_confirm
    tt_nested_hu TYPE /scwm/tt_rf_nested_hu
    wme_verif TYPE /scwm/s_wme_verif
    resource TYPE /scwm/s_rsrc
    t_rf_pick_hus TYPE /scwm/tt_rf_pick_hus
    who TYPE /scwm/s_who_int.



*----------------------------------------------------------------------*
* PIMTTO 屏幕按 CHGSB → 本屏（换源货位）
* PBO 职责：把框架已装入 TT_ORDIM_CONFIRM 的当前拣货行显示到屏幕，
*           并清空「新货位」输入字段，等用户扫码。只读，不写库。
* 签名与 /SCWM/RF_PICK_PIMTTO_PBO 一致，框架按同名 CHANGING 传参。
*----------------------------------------------------------------------*

  DATA: lv_line  TYPE i,
        lv_lgnum TYPE /scwm/lgnum.

*----------------------------------------------------------------------*
* 0. 取当前拣货行装入 ORDIM_CONFIRM（与标准 PIMTTO_PBO 同做法）
*----------------------------------------------------------------------*
  lv_line = /scwm/cl_rf_bll_srvc=>get_line( ).
  IF lv_line = 0.
    lv_line = 1.
    /scwm/cl_rf_bll_srvc=>set_line( 1 ).
  ENDIF.
  READ TABLE tt_ordim_confirm INDEX lv_line INTO ordim_confirm.
  IF sy-subrc <> 0.
    READ TABLE tt_ordim_confirm INDEX 1 INTO ordim_confirm.
  ENDIF.

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

*----------------------------------------------------------------------*
* 1. 原拣货行 → 屏幕展示
*----------------------------------------------------------------------*
  CLEAR gs_chgsb_scr.

  gs_chgsb_scr-vltyp   = ordim_confirm-vltyp.     " 源库存类型
  gs_chgsb_scr-vlpla   = ordim_confirm-vlpla.     " 原货位
  CALL FUNCTION 'CONVERSION_EXIT_QTYCH_OUTPUT'
    EXPORTING
      input  = ordim_confirm-vsola
    IMPORTING
      output = gs_chgsb_scr-vsola_chr.       " 应拣数量
  CALL FUNCTION 'CONVERSION_EXIT_CUNIT_OUTPUT'
    EXPORTING
      input  = ordim_confirm-altme
    IMPORTING
      output = gs_chgsb_scr-altme.        " 数量单位（外部显示，KAR -> CAR）
  gs_chgsb_scr-huident = ordim_confirm-huident.   " 处理单元
  gs_chgsb_scr-matnr   = ordim_confirm-matnr.     " 产品
  gs_chgsb_scr-tanum   = ordim_confirm-tanum.     " WT 号
  gs_chgsb_scr-vlenr   = ordim_confirm-vlenr.     " WT 行号

* 产品描述：优先取框架已装入的文本，否则按产品号读 MAKT
  gs_chgsb_scr-maktx = ordim_confirm-maktx.
  IF gs_chgsb_scr-maktx IS INITIAL
     AND gs_chgsb_scr-matnr IS NOT INITIAL.
    SELECT SINGLE maktx FROM makt INTO gs_chgsb_scr-maktx
      WHERE matnr = gs_chgsb_scr-matnr
        AND spras = sy-langu.
  ENDIF.

  gs_chgsb_scr-charg = ordim_confirm-batch.      " 批次（可直接读）

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
