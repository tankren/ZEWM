FUNCTION-POOL zfg_rf_zdifhu.             "MESSAGE-ID ..

* 屏幕字段工作区（TABLES 使屏幕字段可绑 ZSDIFHU_SCR-* / ZSDIFHU_ITEM-*）
TABLES: zsdifhu_scr,
        zsdifhu_item.

* 列表内表（屏幕 step-loop 数据源；PBO 时由 App.Param ZDIFHU_T_ITEMS 同步）
DATA: gt_zdifhu_items TYPE zsdifhu_item_tt.

* OK 码与 step-loop 翻页游标
DATA: ok_code   TYPE sy-ucomm,
      gv_cursor TYPE i VALUE 1.

*----------------------------------------------------------------------*
* 重读 HU，按 GUID_STOCK 刷新单行的当前数量（过账后调用）
*----------------------------------------------------------------------*
FORM refresh_item USING    iv_lgnum      TYPE /scwm/lgnum
                           iv_huident    TYPE /scwm/de_huident
                           iv_guid_stock TYPE /scwm/de_guid_stock
                  CHANGING cs_item       TYPE zsdifhu_item.

  DATA: lt_huident TYPE /scwm/tt_huident,
        ls_huident TYPE /scwm/s_huident,
        lt_huitm   TYPE /scwm/tt_huitm.

  FIELD-SYMBOLS: <ls_huitm> TYPE /scwm/s_huitm.

  ls_huident-huident = iv_huident.
  APPEND ls_huident TO lt_huident.

  CALL FUNCTION '/SCWM/HU_READ_MULT'
    EXPORTING
      it_huident   = lt_huident
      iv_lgnum     = iv_lgnum
    IMPORTING
      et_huitm     = lt_huitm
    EXCEPTIONS
      not_possible = 1
      OTHERS       = 2.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  READ TABLE lt_huitm ASSIGNING <ls_huitm> WITH KEY guid_stock = iv_guid_stock.
  IF sy-subrc = 0.
    cs_item-quan  = <ls_huitm>-quan.
    cs_item-meins = <ls_huitm>-meins.
  ENDIF.

ENDFORM.
