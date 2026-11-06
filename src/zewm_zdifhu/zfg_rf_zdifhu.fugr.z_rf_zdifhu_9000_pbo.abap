FUNCTION z_rf_zdifhu_9000_pbo.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  CHANGING
*"     REFERENCE(CS_ZDIFHU_S_SCR) TYPE  ZSDIFHU_SCR
*"     REFERENCE(CT_ZDIFHU_T_ITEMS) TYPE  ZSDIFHU_ITEM_TT
*"----------------------------------------------------------------------

  DATA(lv_lgnum) = /scwm/cl_rf_bll_srvc=>get_lgnum( ).
  /scwm/cl_tm=>set_lgnum( lv_lgnum ).

* 注册结构 data container（屏幕字段载体，框架按名传入）
  /scwm/cl_rf_bll_srvc=>init_screen_param( ).
  /scwm/cl_rf_bll_srvc=>set_screen_param( 'CS_ZDIFHU_S_SCR' ).

ENDFUNCTION.
