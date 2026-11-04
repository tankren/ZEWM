FUNCTION-POOL zewm_fg_rf_zchgsb.

*----------------------------------------------------------------------*
* Change Source Bin (CHGSB) - PIMTTO custom screen 9100
*----------------------------------------------------------------------*
DATA: BEGIN OF gs_chgsb_scr,
        vltyp    TYPE /scwm/ltap_vltyp,
        vlpla    TYPE /scwm/de_rf_vlpla,
        vsola_chr TYPE /scwm/de_rf_qty_char,
        altme    TYPE /scwm/de_rf_altme,
        huident  TYPE /scwm/de_huident,
        matnr    TYPE /scwm/de_rf_matnr,
        maktx    TYPE maktx,
        charg    TYPE /scwm/de_rf_charg,
        tanum    TYPE /scwm/de_rf_tanum,
        vlenr    TYPE /scwm/de_rf_vlenr,
        newlgpla TYPE /scwm/de_lgpla,
        newlgtyp TYPE /scwm/ltap_vltyp,
        txt      TYPE char80,
      END OF gs_chgsb_scr.