FUNCTION z_rf_zdifhu_9001_pbo.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  CHANGING
*"     REFERENCE(CS_ZDIFHU_S_SCR) TYPE  ZSDIFHU_SCR
*"     REFERENCE(CT_ZDIFHU_T_ITEMS) TYPE  ZSDIFHU_ITEM_TT
*"----------------------------------------------------------------------

  DATA(lv_lgnum) = /scwm/cl_rf_bll_srvc=>get_lgnum( ).
  /scwm/cl_tm=>set_lgnum( lv_lgnum ).

* 注册结构 + 表 data container（框架按名传数据到屏幕 step-loop）
  /scwm/cl_rf_bll_srvc=>init_screen_param( ).
  /scwm/cl_rf_bll_srvc=>set_screen_param( 'CS_ZDIFHU_S_SCR' ).
  /scwm/cl_rf_bll_srvc=>set_screen_param( 'CT_ZDIFHU_T_ITEMS' ).
  /scwm/cl_rf_bll_srvc=>set_scr_tabname( 'CT_ZDIFHU_T_ITEMS' ).
  /scwm/cl_rf_bll_srvc=>set_line( '1' ).

* 光标回扫描框
  /scwm/cl_rf_bll_srvc=>set_field( 'ZSDIFHU_SCR-MATNR_SCAN' ).

ENDFUNCTION.
