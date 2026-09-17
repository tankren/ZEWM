FUNCTION zewm_rf_zdifhu_9004_pai.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  CHANGING
*"     REFERENCE(CS_ZDIFHU_HU) TYPE  /SCWM/S_RF_INQ_HU
*"----------------------------------------------------------------------

  DATA(lv_lgnum) = /scwm/cl_rf_bll_srvc=>get_lgnum( ).
  /scwm/cl_tm=>set_lgnum( lv_lgnum ).

  CASE /scwm/cl_rf_bll_srvc=>get_fcode( ).
    WHEN 'BACK'.
*     回列表屏 9001
*     （导航由 step flow 处理：ZDIF4/BACK → SSTEP=ZDIF2 + PRMOD=1 + FCODE_BCKG=INIT）

    WHEN OTHERS.
*     明细屏无输入字段，ENTER 不做事
  ENDCASE.

ENDFUNCTION.
