CLASS zcl_zewm_rms_det_chgsb DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS c_call_bin_denial TYPE /scwm/de_rbdcall VALUE 'C'.

    INTERFACES /scwm/if_ex_core_rms_determine.

ENDCLASS.


CLASS zcl_zewm_rms_det_chgsb IMPLEMENTATION.

  METHOD /scwm/if_ex_core_rms_determine~determine.
*----------------------------------------------------------------------*
* CHGSB: force the scanned source bin during bin denial.
*
* The standard bin-denial path (/SCWM/TO_CREATE_BIN_DENIAL) builds
* /SCWM/S_REMREQ and clears VLPLA/TANUM before calling
* /SCWM/REM_BIN_DET.  Therefore IS_LTAP has neither TANUM nor the old
* bin.  Match on LGNUM + MATID (+ BATCHID when both are filled) and
* filter the candidate quants to the bin exported by the RF PAI.
*----------------------------------------------------------------------*
    DATA: ls_ctx   TYPE /scwm/ltap,
          lv_matid TYPE /scwm/de_matid.

    FIELD-SYMBOLS <ls_qmat> TYPE /scwm/s_aqua_int.

    CLEAR: et_qmat_cus, ev_set.

*   Only take over the bin-denial call.  All other calls keep the
*   standard behaviour (EV_SET stays initial).
    IF iv_call <> c_call_bin_denial.
      RETURN.
    ENDIF.

    IMPORT ctx = ls_ctx FROM MEMORY ID 'ZCHGSB_CTX'.
    IF sy-subrc <> 0 OR ls_ctx-nlpla IS INITIAL.
      RETURN.
    ENDIF.

    IF is_ltap-lgnum <> ls_ctx-lgnum.
      RETURN.
    ENDIF.

    lv_matid = is_ltap-matid.
    IF lv_matid IS INITIAL.
      lv_matid = is_mat_global-matid.
    ENDIF.
    IF lv_matid IS INITIAL OR lv_matid <> ls_ctx-matid.
      RETURN.
    ENDIF.

*   Batch is not always filled in IS_LTAP; only compare when both sides
*   have a value.
    IF is_ltap-batchid IS NOT INITIAL
       AND ls_ctx-batchid IS NOT INITIAL
       AND is_ltap-batchid <> ls_ctx-batchid.
      RETURN.
    ENDIF.

*   Keep only quants that are physically in the scanned bin.
    LOOP AT it_qmat ASSIGNING <ls_qmat> WHERE lgpla = ls_ctx-nlpla.
      IF <ls_qmat>-quan > 0.
        APPEND <ls_qmat> TO et_qmat_cus.
      ENDIF.
    ENDLOOP.

    IF et_qmat_cus IS NOT INITIAL.
      ev_set = abap_true.
*     Force the scanned bin only once; subsequent splits of the same
*     bin denial fall back to standard determination.
      FREE MEMORY ID 'ZCHGSB_CTX'.
    ENDIF.

  ENDMETHOD.

ENDCLASS.
