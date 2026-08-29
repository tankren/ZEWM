FUNCTION z_rf_zdifhu_9000_pbo.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_LGNUM) TYPE  /SCWM/LGNUM
*"  CHANGING
*"     REFERENCE(CS_ZDIFHU_S_SCR) TYPE  ZSDIFHU_SCR
*"     REFERENCE(CT_ZDIFHU_T_ITEMS) TYPE  ZSDIFHU_ITEM_TT
*"----------------------------------------------------------------------

  /scwm/cl_tm=>set_lgnum( iv_lgnum ).

ENDFUNCTION.
