FUNCTION z_rf_zdifhu_9001_pai.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  CHANGING
*"     REFERENCE(CS_ZDIFHU_S_SCR) TYPE  ZSDIFHU_SCR
*"     REFERENCE(CS_ZDIFHU_PROD) TYPE  ZSDIFHU_PROD
*"     REFERENCE(CT_ZDIFHU_T_ITEMS) TYPE  ZSDIFHU_ITEM_TT
*"----------------------------------------------------------------------

  DATA: ls_item  TYPE zsdifhu_item,
        lv_lgnum TYPE /scwm/lgnum.

  lv_lgnum = /scwm/cl_rf_bll_srvc=>get_lgnum( ).
  /scwm/cl_tm=>set_lgnum( lv_lgnum ).

  CASE /scwm/cl_rf_bll_srvc=>get_fcode( ).
    WHEN 'BACK'.
*     回上一屏（HU 输入屏 9000）：交给框架调用栈的 BACK 弹栈处理
*     （step flow 里 ZDIF2/BACK → SSTEP=ZDIF1 已配好；事务退出由第一屏 9000 的 BACK 负责）
      CLEAR cs_zdifhu_s_scr-selno.

    WHEN OTHERS.
*     ENTER：按序号选中物料行 → 跳明细屏
*     （导航由 step flow 处理：ZDIF2/ENTER → SSTEP=ZDIF3 + FCODE_BCKG=INIT）

*     未输序号：提示并停留本屏
      IF cs_zdifhu_s_scr-selno IS INITIAL.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e008(zewm_rf_msg).
      ENDIF.

*     序号不存在：提示并停留本屏
      READ TABLE ct_zdifhu_t_items INTO ls_item
           WITH KEY seqno = cs_zdifhu_s_scr-selno.
      IF sy-subrc <> 0.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e009(zewm_rf_msg).
      ENDIF.

*     选中成功：清明细容器，明细屏 PBO 会按序号重新填充
      CLEAR cs_zdifhu_prod.
  ENDCASE.

ENDFUNCTION.
