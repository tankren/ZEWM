FUNCTION-POOL zewm_rf_zdifhu.             "MESSAGE-ID ..

* 屏幕字段工作区（TABLES 使屏幕字段可绑 ZEWM_ZDIFHU_SCR_1S-* / ZEWM_ZDIFHU_ITEM_1S-* / ZEWM_ZDIFHU_PROD_1S-*）
TABLES: zewm_zdifhu_scr_1s,
        zewm_zdifhu_item_1s,
        zewm_zdifhu_prod_1s.

* HU 明细屏 9004 的屏幕字段工作区
* （容器 CS_ZDIFHU_HU 的类型就是 /SCWM/S_RF_INQ_HU，框架按此名 ASSIGN，屏幕字段名 /SCWM/S_RF_INQ_HU-*）
TABLES /scwm/s_rf_inq_hu.

*----------------------------------------------------------------------*
* 重读 HU，按 GUID_STOCK 刷新单行的当前数量（过账后调用）
*----------------------------------------------------------------------*
FORM refresh_item USING    iv_lgnum      TYPE /scwm/lgnum
                           iv_huident    TYPE /scwm/de_huident
                           iv_guid_stock TYPE /lime/guid_stock
                  CHANGING cs_item       TYPE zewm_zdifhu_item_1s.

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
