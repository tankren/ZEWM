FUNCTION z_rf_zdifhu_9002_pai.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  CHANGING
*"     REFERENCE(CS_ZDIFHU_S_SCR) TYPE  ZSDIFHU_SCR
*"     REFERENCE(CS_ZDIFHU_PROD) TYPE  ZSDIFHU_PROD
*"     REFERENCE(CT_ZDIFHU_T_ITEMS) TYPE  ZSDIFHU_ITEM_TT
*"----------------------------------------------------------------------

  DATA: ls_item    TYPE zsdifhu_item,
        lv_tabix   TYPE sy-tabix,
        lv_diff    TYPE /scwm/de_quantity,
        ls_quan    TYPE /scwm/s_quan,
        lv_lgnum   TYPE /scwm/lgnum,
        go_packing TYPE REF TO /scwm/cl_wm_packing.

  lv_lgnum = /scwm/cl_rf_bll_srvc=>get_lgnum( ).
  /scwm/cl_tm=>set_lgnum( lv_lgnum ).

  CASE /scwm/cl_rf_bll_srvc=>get_fcode( ).
    WHEN 'BACK'.
*     取消返回列表（导航由 step flow 处理：ZDIF3/BACK → SSTEP=ZDIF2 + FCODE_BCKG=INIT）
      CLEAR cs_zdifhu_prod-quan_count.

    WHEN OTHERS.
*     ENTER：实盘数量校验 + 差异过账

*     1. 实盘数量必填
      IF cs_zdifhu_prod-quan_count IS INITIAL.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e001(00) WITH 'Please enter counted quantity'(010).
      ENDIF.

*     2. 差异计算（实盘 − 当前）
      lv_diff = cs_zdifhu_prod-quan_count - cs_zdifhu_prod-quan.
      IF lv_diff = 0.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e001(00) WITH 'Counted quantity equals current quantity'(011).
      ENDIF.

      ls_quan-quan = lv_diff.
      ls_quan-unit = cs_zdifhu_prod-meins.

*     3. 过账（异常码三件套按客户系统配置）
      CREATE OBJECT go_packing.
      CALL METHOD go_packing->post_difference
        EXPORTING
          iv_guid_hu    = cs_zdifhu_prod-guid_hu
          iv_guid_stock = cs_zdifhu_prod-guid_stock
          is_quan       = ls_quan
          iv_exccode    = 'DIFD'
          iv_buscon     = 'PPT'
          iv_exec_step  = '16'
        EXCEPTIONS
          error         = 1
          OTHERS        = 2.
      IF sy-subrc <> 0.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e001(00) WITH 'Difference posting failed'(006).
      ENDIF.

*     4. 落库：save 不带 commit，外层显式 COMMIT
      CALL METHOD go_packing->save
        EXPORTING
          iv_commit = space
          iv_wait   = space
        EXCEPTIONS
          OTHERS    = 99.
      IF sy-subrc <> 0.
        ROLLBACK WORK.
        /scwm/cl_tm=>cleanup( ).
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e001(00) WITH 'Save failed, rolled back'(007).
      ENDIF.
      COMMIT WORK AND WAIT.
      /scwm/cl_tm=>cleanup( ).

*     5. 刷新列表该行的当前数量
      READ TABLE ct_zdifhu_t_items INTO ls_item
           WITH KEY seqno = cs_zdifhu_prod-seqno.
      IF sy-subrc = 0.
        lv_tabix = sy-tabix.
        PERFORM refresh_item USING    lv_lgnum
                                      cs_zdifhu_s_scr-huident
                                      ls_item-guid_stock
                             CHANGING ls_item.
        MODIFY ct_zdifhu_t_items FROM ls_item INDEX lv_tabix.
      ENDIF.

*     6. 清实盘，回列表重显（导航由 step flow 处理：ZDIF3/ENTER → SSTEP=ZDIF2 + FCODE_BCKG=INIT）
      CLEAR cs_zdifhu_prod-quan_count.
  ENDCASE.

ENDFUNCTION.
