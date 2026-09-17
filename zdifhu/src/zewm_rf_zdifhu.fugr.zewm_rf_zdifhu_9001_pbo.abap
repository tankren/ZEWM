FUNCTION zewm_rf_zdifhu_9001_pbo.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  CHANGING
*"     REFERENCE(CS_ZDIFHU_S_SCR) TYPE  ZEWM_ZDIFHU_SCR_1S
*"     REFERENCE(CT_ZDIFHU_T_ITEMS) TYPE  ZEWM_ZDIFHU_ITEM_1TT
*"----------------------------------------------------------------------

  DATA(lv_lgnum) = /scwm/cl_rf_bll_srvc=>get_lgnum( ).
  /scwm/cl_tm=>set_lgnum( lv_lgnum ).

* 注册结构 + 表 data container（框架按名把数据送到屏幕 step-loop）
  /scwm/cl_rf_bll_srvc=>init_screen_param( ).
  /scwm/cl_rf_bll_srvc=>set_screen_param( 'CS_ZDIFHU_S_SCR' ).
  /scwm/cl_rf_bll_srvc=>set_screen_param( 'CT_ZDIFHU_T_ITEMS' ).
  /scwm/cl_rf_bll_srvc=>set_scr_tabname( 'CT_ZDIFHU_T_ITEMS' ).
  /scwm/cl_rf_bll_srvc=>set_line( '1' ).

* 序号输入框：显式打开输入属性
  /scwm/cl_rf_bll_srvc=>set_screlm_input_on( 'ZEWM_ZDIFHU_SCR_1S-SELNO' ).

* 光标定位到序号输入框
  /scwm/cl_rf_bll_srvc=>set_field( 'ZEWM_ZDIFHU_SCR_1S-SELNO' ).

ENDFUNCTION.
