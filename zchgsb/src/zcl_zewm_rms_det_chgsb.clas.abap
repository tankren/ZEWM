CLASS zcl_zewm_rms_det_chgsb DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS c_call_bin_denial TYPE /scwm/de_rbdcall VALUE 'C'.

*   Fallback when ABAP memory is not visible in the BAdI session.
*   PAI fills this before triggering the exception.
    CLASS-DATA: gs_ctx     TYPE /scwm/ltap,
                gv_ctx_set TYPE abap_bool.

    INTERFACES /scwm/if_ex_core_rms_determine.

ENDCLASS.


CLASS zcl_zewm_rms_det_chgsb IMPLEMENTATION.

  METHOD /scwm/if_ex_core_rms_determine~determine.
*----------------------------------------------------------------------*
* CHGSB: force the scanned source bin during bin denial.
*
* Follow the same pattern as /SCWM/CL_EI_CORE_RMS_ODO_UOM:
*   - build ET_QMAT_CUS from IT_QMAT
*   - set EV_SET only when a matching quant was found
*   - otherwise leave the standard result untouched
*----------------------------------------------------------------------*
    DATA ls_ctx TYPE /scwm/ltap.

    FIELD-SYMBOLS <ls_qmat> LIKE LINE OF it_qmat.

    CLEAR: et_qmat_cus, ev_set.

*   Only the bin-denial call.  Normal WT creation must not be touched.
    IF iv_call <> c_call_bin_denial.
      RETURN.
    ENDIF.

*   Primary channel: ABAP memory.
    IMPORT ctx = ls_ctx FROM MEMORY ID 'ZCHGSB_CTX'.
    IF sy-subrc <> 0.
*     Fallback for an internal-session change: static context.
      IF gv_ctx_set IS INITIAL.
        RETURN.
      ENDIF.
      ls_ctx = gs_ctx.
    ENDIF.

    IF ls_ctx-nlpla IS INITIAL.
      RETURN.
    ENDIF.

    IF ls_ctx-lgnum IS NOT INITIAL
       AND is_ltap-lgnum <> ls_ctx-lgnum.
      RETURN.
    ENDIF.

*   Keep every quant of the scanned bin.  Do not compare MATID/MATNR
*   here: the REMREQ-built LTAP does not always carry them.
    LOOP AT it_qmat ASSIGNING <ls_qmat>
         WHERE lgpla = ls_ctx-nlpla.
      APPEND <ls_qmat> TO et_qmat_cus.
    ENDLOOP.

    IF et_qmat_cus IS NOT INITIAL.
      ev_set = abap_true.
*     Force the scanned bin only once.
      FREE MEMORY ID 'ZCHGSB_CTX'.
      CLEAR gv_ctx_set.
    ENDIF.

  ENDMETHOD.

ENDCLASS.
