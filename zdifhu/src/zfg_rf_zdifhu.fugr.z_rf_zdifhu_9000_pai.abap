FUNCTION z_rf_zdifhu_9000_pai.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_LGNUM) TYPE  /SCWM/LGNUM
*"  CHANGING
*"     REFERENCE(CS_ZDIFHU_S_SCR) TYPE  ZSDIFHU_SCR
*"     REFERENCE(CT_ZDIFHU_T_ITEMS) TYPE  ZSDIFHU_ITEM_TT
*"----------------------------------------------------------------------

  DATA: lt_huident    TYPE /scwm/tt_huident,
        ls_huident    TYPE /scwm/s_huident,
        lt_huhdr      TYPE /scwm/tt_huhdr,
        ls_huhdr      TYPE /scwm/s_huhdr,
        lt_huitm      TYPE /scwm/tt_huitm,
        ls_huitm      TYPE /scwm/s_huitm,
        ls_mat_global TYPE /scwm/s_mat_global,
        ls_item       TYPE zsdifhu_item.

  /scwm/cl_tm=>set_lgnum( iv_lgnum ).

* HU 号大写（扫描枪/手工输入统一）
  TRANSLATE cs_zdifhu_s_scr-huident TO UPPER CASE.

* 空 HU：提示并停留本屏
  IF cs_zdifhu_s_scr-huident IS INITIAL.
    /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
    MESSAGE e001(00) WITH 'Please enter HU number'(001).
  ENDIF.

  ls_huident-huident = cs_zdifhu_s_scr-huident.
  APPEND ls_huident TO lt_huident.

* HU 读取（combined read：先 buffer 再 DB，拿最新数据）
  CALL FUNCTION '/SCWM/HU_READ_MULT'
    EXPORTING
      it_huident   = lt_huident
      iv_lgnum     = iv_lgnum
    IMPORTING
      et_huhdr     = lt_huhdr
      et_huitm     = lt_huitm
    EXCEPTIONS
      not_possible = 1
      OTHERS       = 2.
  IF sy-subrc <> 0 OR lt_huhdr IS INITIAL.
    /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
    MESSAGE e001(00) WITH 'HU not found'(002).
  ENDIF.

  READ TABLE lt_huhdr INTO ls_huhdr INDEX 1.

* 只取 HU 直接项目（不支持嵌套包装）
  CLEAR ct_zdifhu_t_items.
  LOOP AT lt_huitm INTO ls_huitm WHERE guid_parent = ls_huhdr-guid_hu.
    CLEAR ls_item.

*   MATID → MATNR
    CALL FUNCTION '/SCWM/MATERIAL_READ_SINGLE'
      EXPORTING
        iv_matid      = ls_huitm-matid
        iv_langu      = sy-langu
      IMPORTING
        es_mat_global = ls_mat_global
      EXCEPTIONS
        OTHERS        = 1.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

    ls_item-matnr      = ls_mat_global-matnr.
    ls_item-quan       = ls_huitm-quan.
    ls_item-meins      = ls_huitm-meins.
    ls_item-guid_stock = ls_huitm-guid_stock.
    ls_item-guid_hu    = ls_huhdr-guid_hu.

*   物料描述
    SELECT SINGLE maktx FROM makt INTO ls_item-maktx
      WHERE matnr = ls_item-matnr
        AND spras = sy-langu.

    APPEND ls_item TO ct_zdifhu_t_items.
  ENDLOOP.

  IF ct_zdifhu_t_items IS INITIAL.
    /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
    MESSAGE e001(00) WITH 'No material items in HU'(003).
  ENDIF.

* 新 HU 装载成功：重置翻页游标
  gv_cursor = 1.

* 成功：无需操作，step flow ENTER → ZDIF2 自动跳屏幕 2

ENDFUNCTION.
