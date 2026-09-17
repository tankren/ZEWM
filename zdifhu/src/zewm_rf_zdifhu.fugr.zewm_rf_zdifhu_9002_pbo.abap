FUNCTION zewm_rf_zdifhu_9002_pbo.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  CHANGING
*"     REFERENCE(CS_ZDIFHU_S_SCR) TYPE  ZEWM_ZDIFHU_SCR_1S
*"     REFERENCE(CS_ZDIFHU_PROD) TYPE  ZEWM_ZDIFHU_PROD_1S
*"     REFERENCE(CT_ZDIFHU_T_ITEMS) TYPE  ZEWM_ZDIFHU_ITEM_1TT
*"----------------------------------------------------------------------

  DATA: ls_item  TYPE zewm_zdifhu_item_1s,
        lv_lgnum TYPE /scwm/lgnum.

  lv_lgnum = /scwm/cl_rf_bll_srvc=>get_lgnum( ).
  /scwm/cl_tm=>set_lgnum( lv_lgnum ).

* 按列表屏输入的序号取选中行，填明细容器（QUAN_COUNT 是输入框，不动它）
  READ TABLE ct_zdifhu_t_items INTO ls_item
       WITH KEY seqno = cs_zdifhu_s_scr-selno.
  IF sy-subrc = 0.
    cs_zdifhu_prod-seqno      = ls_item-seqno.
    cs_zdifhu_prod-matnr      = ls_item-matnr.
    cs_zdifhu_prod-maktx      = ls_item-maktx.
    cs_zdifhu_prod-quan       = ls_item-quan.
    cs_zdifhu_prod-meins      = ls_item-meins.
    cs_zdifhu_prod-meins_dsp  = ls_item-meins.
    cs_zdifhu_prod-guid_stock = ls_item-guid_stock.
    cs_zdifhu_prod-guid_hu    = ls_item-guid_hu.
  ENDIF.

* 注册明细 data container
  /scwm/cl_rf_bll_srvc=>init_screen_param( ).
  /scwm/cl_rf_bll_srvc=>set_screen_param( 'CS_ZDIFHU_PROD' ).

* 实盘数量框：显式打开输入属性（框架默认可能关闭）
  /scwm/cl_rf_bll_srvc=>set_screlm_input_on( 'ZEWM_ZDIFHU_PROD_1S-QUAN_COUNT' ).

* 光标定位到实盘数量输入框
  /scwm/cl_rf_bll_srvc=>set_field( 'ZEWM_ZDIFHU_PROD_1S-QUAN_COUNT' ).

ENDFUNCTION.
