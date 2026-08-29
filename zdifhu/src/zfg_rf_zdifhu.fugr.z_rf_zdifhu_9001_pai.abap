FUNCTION z_rf_zdifhu_9001_pai.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_LGNUM) TYPE  /SCWM/LGNUM
*"  CHANGING
*"     REFERENCE(CS_ZDIFHU_S_SCR) TYPE  ZSDIFHU_SCR
*"     REFERENCE(CT_ZDIFHU_T_ITEMS) TYPE  ZSDIFHU_ITEM_TT
*"----------------------------------------------------------------------

  DATA: ls_item  TYPE zsdifhu_item,
        lv_tabix TYPE sy-tabix,
        lv_diff  TYPE /scwm/de_quantity,
        ls_quan  TYPE /scwm/s_quan.

  /scwm/cl_tm=>set_lgnum( iv_lgnum ).

* 用户输入的实盘数量已由 loop_input 模块自动回写到 CT（无需手动同步）

  CASE /scwm/cl_rf_bll_srvc=>get_fcode( ).
    WHEN 'BACK'.
*     无操作：step flow BACK → ZDIF1 自动处理

    WHEN OTHERS.
*     ENTER：防呆 + 差异计算 + 过账
      TRANSLATE cs_zdifhu_s_scr-matnr_scan TO UPPER CASE.

      IF cs_zdifhu_s_scr-matnr_scan IS INITIAL.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e001(00) WITH 'Please scan material'(004).
      ENDIF.

*     1. 防呆：物料必须在列表内
      READ TABLE ct_zdifhu_t_items INTO ls_item
           WITH KEY matnr = cs_zdifhu_s_scr-matnr_scan.
      IF sy-subrc <> 0.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e001(00) WITH 'Material not in this HU'(005).
      ENDIF.
      lv_tabix = sy-tabix.

*     2. 差异计算（实盘 − 当前）
      lv_diff = ls_item-diff_quan - ls_item-quan.
      IF lv_diff = 0.
        CLEAR cs_zdifhu_s_scr-matnr_scan.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        RETURN.
      ENDIF.

      ls_quan-quan = lv_diff.
      ls_quan-unit = ls_item-meins.

*     3. 过账（异常码三件套按客户系统配置）
      CALL METHOD /scwm/cl_wm_packing=>post_difference
        EXPORTING
          iv_guid_hu    = ls_item-guid_hu
          iv_guid_stock = ls_item-guid_stock
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
      CALL METHOD /scwm/cl_wm_packing=>save
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

*     5. 刷新该行数量，清实盘与扫描框，回本屏重显
      PERFORM refresh_item USING    iv_lgnum
                                    cs_zdifhu_s_scr-huident
                                    ls_item-guid_stock
                           CHANGING ls_item.
      CLEAR ls_item-diff_quan.
      MODIFY ct_zdifhu_t_items FROM ls_item INDEX lv_tabix.
      CLEAR cs_zdifhu_s_scr-matnr_scan.
      /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
  ENDCASE.

ENDFUNCTION.
