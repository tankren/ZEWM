FUNCTION-POOL zfg_rf_zdifhu.             "MESSAGE-ID ..

* 屏幕字段工作区（TABLES 使屏幕字段可绑 ZSDIFHU_SCR-* / ZSDIFHU_ITEM-* / ZSDIFHU_PROD-*）
TABLES: zsdifhu_scr,
        zsdifhu_item,
        zsdifhu_prod.

*----------------------------------------------------------------------*
* 屏幕字段只读显示：保留输入框外观（灰底框），但禁止编辑
* 只作用于本项目的 ZSDIFHU* 字段，两个真正的输入框保持可编辑
*----------------------------------------------------------------------*
MODULE set_display_only OUTPUT.
  LOOP AT SCREEN.
    CHECK screen-name CP 'ZSDIFHU*'.
    CHECK screen-name <> 'ZSDIFHU_SCR-SELNO'.
    CHECK screen-name <> 'ZSDIFHU_PROD-QUAN_COUNT'.
    screen-input = 0.
    MODIFY SCREEN.
  ENDLOOP.
ENDMODULE.

*----------------------------------------------------------------------*
* 重读 HU，按 GUID_STOCK 刷新单行的当前数量（过账后调用）
*----------------------------------------------------------------------*
FORM refresh_item USING    iv_lgnum      TYPE /scwm/lgnum
                           iv_huident    TYPE /scwm/de_huident
                           iv_guid_stock TYPE /lime/guid_stock
                  CHANGING cs_item       TYPE zsdifhu_item.

  DATA: lt_huident TYPE /scwm/tt_huident,
        ls_huident TYPE /scwm/s_huident,
        lt_huitm   TYPE /scwm/tt_huitm_int.

  FIELD-SYMBOLS: <ls_huitm> TYPE /scwm/s_huitm_int.

  ls_huident-huident = iv_huident.
  APPEND ls_huident TO lt_huident.

  CALL FUNCTION '/SCWM/HU_READ_MULT'
    EXPORTING
      it_huident   = lt_huident
      iv_lgnum     = iv_lgnum
    IMPORTING
      et_huitm     = lt_huitm
    EXCEPTIONS
      wrong_input    = 1
      not_possible   = 2
      OTHERS         = 3.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  LOOP AT lt_huitm ASSIGNING <ls_huitm> WHERE guid_stock = iv_guid_stock.
    cs_item-quan  = <ls_huitm>-quan.
    cs_item-meins = <ls_huitm>-meins.
    EXIT.
  ENDLOOP.

ENDFORM.
