FUNCTION z_rf_zdifhu_9001_pbo.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_LGNUM) TYPE  /SCWM/LGNUM
*"  CHANGING
*"     REFERENCE(CS_ZDIFHU_S_SCR) TYPE  ZSDIFHU_SCR
*"     REFERENCE(CT_ZDIFHU_T_ITEMS) TYPE  ZSDIFHU_ITEM_TT
*"----------------------------------------------------------------------

  /scwm/cl_tm=>set_lgnum( iv_lgnum ).

* RF 列表三件套（必需）
  /scwm/cl_rf_bll_srvc=>init_screen_param( ).
  /scwm/cl_rf_bll_srvc=>set_screen_param( 'ZDIFHU_T_ITEMS' ).
  /scwm/cl_rf_bll_srvc=>set_scr_tabname( 'ZSDIFHU_ITEM_TT' ).

* App.Param → 屏幕内表（step-loop 数据源）
  gt_zdifhu_items[] = ct_zdifhu_t_items[].

* 光标回扫描框
  SET CURSOR FIELD 'ZSDIFHU_SCR-MATNR_SCAN'.

ENDFUNCTION.
