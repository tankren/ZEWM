FUNCTION zewm_rf_zdifhu_9004_pbo.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  CHANGING
*"     REFERENCE(CS_ZDIFHU_HU) TYPE  /SCWM/S_RF_INQ_HU
*"----------------------------------------------------------------------

  DATA(lv_lgnum) = /scwm/cl_rf_bll_srvc=>get_lgnum( ).
  /scwm/cl_tm=>set_lgnum( lv_lgnum ).

* HU 明细屏：注册数据容器（屏幕字段名 /SCWM/S_RF_INQ_HU-*，见 TOP include 的 TABLES）
* 数据由 9001_PAI 的 HUINFO 分支填好，这里只负责传给屏幕
  /scwm/cl_rf_bll_srvc=>init_screen_param( ).
  /scwm/cl_rf_bll_srvc=>set_screen_param( 'CS_ZDIFHU_HU' ).

ENDFUNCTION.
