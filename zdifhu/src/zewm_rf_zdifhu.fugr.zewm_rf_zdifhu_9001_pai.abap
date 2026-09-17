FUNCTION zewm_rf_zdifhu_9001_pai.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  CHANGING
*"     REFERENCE(CS_ZDIFHU_S_SCR) TYPE  ZEWM_ZDIFHU_SCR_1S
*"     REFERENCE(CS_ZDIFHU_PROD) TYPE  ZEWM_ZDIFHU_PROD_1S
*"     REFERENCE(CT_ZDIFHU_T_ITEMS) TYPE  ZEWM_ZDIFHU_ITEM_1TT
*"     REFERENCE(CS_ZDIFHU_HU) TYPE  /SCWM/S_RF_INQ_HU
*"----------------------------------------------------------------------

  DATA: ls_item    TYPE zewm_zdifhu_item_1s,
        ls_huhdr   TYPE /scwm/s_huhdr_int,
        lv_lgnum   TYPE /scwm/lgnum,
        lv_huident TYPE /scwm/de_huident.

  lv_lgnum = /scwm/cl_rf_bll_srvc=>get_lgnum( ).
  /scwm/cl_tm=>set_lgnum( lv_lgnum ).

  CASE /scwm/cl_rf_bll_srvc=>get_fcode( ).
    WHEN 'BACK'.
*     回上一屏（HU 输入屏 9000）：交给框架调用栈的 BACK 弹栈处理
*     （step flow 里 ZDIF2/BACK → SSTEP=ZDIF1 已配好；事务退出由第一屏 9000 的 BACK 负责）
      CLEAR cs_zdifhu_s_scr-selno.

    WHEN 'HUINFO'.
*     HU 明细：抄标准 /SCWM/RF_INQ_INHULT_PAI 的 HUINFO 分支
*     （读 HU 头 → 填 CS_ZDIFHU_HU，屏幕 9004 显示）
*     跳屏由 step flow 处理：ZDIF2/HUINFO → SSTEP=ZDIF4 + PRMOD=1 + FCODE_BCKG=INIT
      CLEAR cs_zdifhu_s_scr-selno.
      CLEAR cs_zdifhu_hu.

      lv_huident = cs_zdifhu_s_scr-huident.
      IF lv_huident IS INITIAL.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e001(zewm_msg_rf).
      ENDIF.

      CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
        EXPORTING
          input  = lv_huident
        IMPORTING
          output = lv_huident.

*     读 HU 头（包装物料、重量、体积、尺寸、库位等）
      CALL FUNCTION '/SCWM/HU_READ'
        EXPORTING
          iv_lgnum   = lv_lgnum
          iv_huident = lv_huident
        IMPORTING
          es_huhdr   = ls_huhdr.
      IF ls_huhdr-huident IS INITIAL.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e002(zewm_msg_rf).
      ENDIF.

      MOVE-CORRESPONDING ls_huhdr TO cs_zdifhu_hu.

*     库位/资源（照抄标准：lgpla → rsrc → tu_num → wsbin 依次回退）
      IF ls_huhdr-lgpla IS NOT INITIAL.
        cs_zdifhu_hu-wsbin = ls_huhdr-lgpla.
        cs_zdifhu_hu-wstyp = ls_huhdr-lgtyp.
      ELSEIF ls_huhdr-rsrc IS NOT INITIAL.
        cs_zdifhu_hu-wsbin = ls_huhdr-rsrc.
        cs_zdifhu_hu-wstyp = ls_huhdr-lgtyp.
      ELSEIF ls_huhdr-tu_num IS NOT INITIAL.
        cs_zdifhu_hu-wsbin = ls_huhdr-tu_num.
        cs_zdifhu_hu-wstyp = ls_huhdr-lgtyp.
      ELSE.
        cs_zdifhu_hu-wsbin = ls_huhdr-wsbin.
        cs_zdifhu_hu-wstyp = ls_huhdr-wstyp.
      ENDIF.

*     包装物料：/SCWM/S_RF_INQ_HU-PMAT 就是 MATID（RAW16），直接取 HU 头的 PMAT_GUID；
*     屏幕字段带转换出口 MDLPD，显示时会转成物料号
      cs_zdifhu_hu-pmat = ls_huhdr-pmat_guid.

*     HU 号（标准屏 0202 不显示，我们加上便于确认）
      cs_zdifhu_hu-huident = cs_zdifhu_s_scr-huident.

    WHEN OTHERS.
*     ENTER：按序号选中物料行 → 跳明细屏
*     （导航由 step flow 处理：ZDIF2/ENTER → SSTEP=ZDIF3 + FCODE_BCKG=INIT）

*     未输序号：提示并停留本屏
      IF cs_zdifhu_s_scr-selno IS INITIAL.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e008(zewm_msg_rf).
      ENDIF.

*     序号不存在：提示并停留本屏
      READ TABLE ct_zdifhu_t_items INTO ls_item
           WITH KEY seqno = cs_zdifhu_s_scr-selno.
      IF sy-subrc <> 0.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e009(zewm_msg_rf).
      ENDIF.

*     选中成功：清明细容器，明细屏 PBO 会按序号重新填充
      CLEAR cs_zdifhu_prod.
  ENDCASE.

ENDFUNCTION.
