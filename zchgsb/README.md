# ZCHGSB — EWM RF Change Source Bin

**English** | [中文](README.zh.md)

> **Status:** implemented and verified on S/4HANA (client 100, warehouse `1710`).
> The RF picking screen `PIMTTO` gets a `ZCHGSB` function key (F11). The user scans a
> new source bin; the original warehouse task is confirmed at quantity `0`, a bin
> denial is created, and a new warehouse task is created in the scanned bin.
> Package: `ZEWM`. Code transport: `S4HK902806`. BAdI transport: `S4HK902812`.
> Customizing: `S4HK902808` (manual). Messages: `S4HK902782`.
> See [Acceptance checklist](#5-acceptance-checklist).

## 1. Design

### 1.1 Problem

During RF picking, SAP normally chooses the destination/source bin by the warehouse
strategy. If the picker discovers that the stock is actually in a different bin, the
standard RF flow has no direct "change source bin" action. Releasing and recreating the
warehouse task manually is slow and error-prone.

`ZCHGSB` adds a controlled exception to the standard picking flow:

1. The picker presses **F11** on `PIMTTO`.
2. A custom screen shows the current pick line and asks for the new source bin.
3. After validation, the standard RF exception chain confirms the original WT at
   quantity `0` and creates a **bin denial**.
4. EWM redetermines a bin and creates a new WT. A BAdI forces the redetermination to
   use the **scanned bin**.

### 1.2 Why the standard exception chain

The implementation does **not** confirm the WT or create the new WT itself. It hands
over to the standard RF exception flow:

```text
PIMTTO F11
  -> screen 9100 (PBO)
  -> scan new source bin + Enter
  -> PAI: validate bin, check stock, export context
  -> set_shortcut( 'ZCSB' ), set_prmod( '1' ), set_fcode( 'EXCEPT' )
  -> /SCWM/RF_PICK_EXCEPTION
  -> TEXCEXEH: ZCSB / BIDU
  -> standard 0-qty confirmation + bin denial
  -> /SCWM/TO_CREATE_BIN_DENIAL
  -> /SCWM/REM_BIN_DET
  -> BAdI /SCWM/EX_CORE_RMS_DETERMINE
  -> filter candidate quants by the scanned bin
  -> new WT in the scanned bin
```

This keeps standard confirmation, HU handling, stock movement, and error handling in
SAP code. The custom code only supplies the screen, validation, and the bin choice.

### 1.3 Why a BAdI is required

Without the BAdI, EWM redetermines a bin with the normal strategy and may choose a
different bin. The BAdI is the supported extension point inside
`/SCWM/REM_BIN_DET`; it can replace the candidate quant set used for bin determination.

**Critical:** the correct BAdI is

- enhancement spot `/SCWM/ES_CORE_RMS`
- BAdI definition `/SCWM/EX_CORE_RMS_DETERMINE`
- interface `/SCWM/IF_EX_CORE_RMS_DETERMINE`
- single-use

The similarly named `/SCWM/EX4_CORE_RMS_DETERMINE` is **not used** and has no
references. Do not implement that one.

### 1.4 Why the context is passed through memory

The bin-denial path builds its requirement from the original WT and then **clears**
`VLPLA`, `VLENR`, and `TANUM` before calling `/SCWM/REM_BIN_DET`
(`/SCWM/TO_CREATE_BIN_DENIAL`). `/SCWM/S_REMREQ` has no `TANUM` field at all.

Therefore, at BAdI time:

- `IS_LTAP-TANUM` is empty.
- `IS_LTAP-VLPLA` is empty.
- `IS_LTAP-VLENR` is empty.

The BAdI cannot identify the RF session from `IS_LTAP`. Instead, the PAI exports a
small context to ABAP memory ID `ZCHGSB_CTX` (type `/SCWM/LTAP`), and the BAdI imports
it. The context contains the warehouse, original WT, old bin, material, batch, target
quantity, unit, and the scanned new bin (`NLPLA`).

A static fallback in the implementation class (`GS_CTX` / `GV_CTX_SET`) covers the
case where the memory ID is not visible in the BAdI call.

### 1.5 Why `BIDU`, not `BIDF`

In `/SCWM/TEXCEXEH`, exception code `ZCSB` must use `IPRCODE = BIDU` for the active
warehouse (`1710`, `BUSCON = TPI`, `PRMODE = 05`).

With `BIDF`, `/SCWM/RF_PICK_EXCEPTION` only changes the RF memory and returns silently
to `PIMTTO`; no confirmation, no bin denial, no new WT. This was verified during
implementation. `BIDU` executes the real bin-denial chain.

### 1.6 Stock precheck

Before handing over to the exception chain, the PAI checks that the scanned bin has
enough available stock for the current pick quantity (`VSOLA`). This prevents a
successful bin change into a bin that cannot satisfy the WT.

The check uses `/SCWM/SELECT_STOCK` and sums:

- `QUANA` when the stock row's alternative unit (`ALTME`) equals the target unit;
- `QUAN` when the stock row's base unit (`MEINS`) equals the target unit.

The target unit is `ORDIM_CONFIRM-ALTME`; if that is empty, it is
`ORDIM_CONFIRM-MEINS`.

## 2. End-to-end flow

1. The picker is on `PIMTTO` with a valid pick line.
2. **F11** (`ZCHGSB`, PB2) routes through `/SCWM/TSTEP_FLOW`:
   `PIMTTO/ZCHGSB -> ZEWM_RF_ZCHGSB_9100_PBO -> step ZCHGSB`, PRMOD `1`,
   `FCODE_BCKG = INIT`.
3. PBO 9100 reads the current line from `TT_ORDIM_CONFIRM`, fills `GS_CHGSB_SCR`,
   converts quantity and unit for display, clears the new-bin fields, and makes
   `NEWLGPLA` ready for input.
4. The picker scans the new source bin and presses **Enter**.
5. PAI 9100 validates:
   - a pick line exists (`TANUM`);
   - a new bin was entered;
   - the new bin is not the current bin;
   - the bin exists and is not frozen;
   - the bin type matches the pick line's source type;
   - the bin is allowed for picking (bin activity check, if the bin has a location);
   - enough available stock exists for `VSOLA`.
6. On success, PAI exports `ZCHGSB_CTX`, sets shortcut `ZCSB`, PRMOD `1`, and
   FCODE `EXCEPT`.
7. `/SCWM/TSTEP_FLOW` routes `ZCHGSB/EXCEPT` to `/SCWM/RF_PICK_EXCEPTION` (step
   `PIMTTO`, PRMOD `1`).
8. `/SCWM/TEXCEXEH` resolves `ZCSB` to `BIDU`. The standard flow confirms the original
   WT at quantity `0`, writes the difference, and creates the bin denial.
9. `/SCWM/TO_CREATE_BIN_DENIAL` builds the requirement, clears the old bin/WT fields,
   and calls `/SCWM/REM_BIN_DET`.
10. The BAdI implementation `ZCL_ZEWM_RMS_DET_CHGSB` imports `ZCHGSB_CTX`, filters
    `IT_QMAT` by `LGPLA = scanned bin`, fills `ET_QMAT_CUS`, and sets `EV_SET = 'X'`.
11. EWM creates the new WT in the scanned bin. The RF returns to `PIMTTO`.
12. On the next successful determination the context is freed; further split
    determinations, if any, use the standard strategy.

## 3. Implementation

### 3.1 Objects

| Object | Name | Purpose |
|---|---|---|
| Function group | `ZEWM_FG_RF_ZCHGSB` | RF screen and function modules |
| Main program | `SAPLZEWM_FG_RF_ZCHGSB` | Function-group main program |
| TOP include | `LZEWM_FG_RF_ZCHGSBTOP` | Global structure `GS_CHGSB_SCR` |
| PBO FM | `ZEWM_RF_ZCHGSB_9100_PBO` | Fill screen 9100 |
| PAI FM | `ZEWM_RF_ZCHGSB_9100_PAI` | Validate, precheck, export context |
| Screen | `9100` | New-source-bin screen (15 x 26) |
| BAdI class | `ZCL_ZEWM_RMS_DET_CHGSB` | Filter RMS candidate quants |
| BAdI implementation | `ZEWM_ZCHGSB_RMS_DET` | ENHO in `/SCWM/ES_CORE_RMS` |
| Message class | `ZEWM_RF_MSG` | Messages 012–017 |

Package: `ZEWM`.
Code transport: `S4HK902806` (task `S4HK902807`).
BAdI transport: `S4HK902812`.
Message transport: `S4HK902782` (task `S4HK902810`, shared with ZDIFHU).

### 3.2 Screen 9100

Verified `D020S`:

- program `SAPLZEWM_FG_RF_ZCHGSB`, dynpro `9100`
- type `I`
- `BZMX = 9`, `BZBR = 26`
- `NOLI = 15`, `NOCO = 26` (15 rows x 26 columns)

Layout: labels in column 1, values starting at column 12, width 14.

| Row | Content | Field / text |
|---|---|---|
| 1 | Product | label + `GS_CHGSB_SCR-MATNR` |
| 2 | Material description | `GS_CHGSB_SCR-MAKTX` (C1, N26, no label) |
| 3 | Src Bin | label + `GS_CHGSB_SCR-VLPLA` |
| 4 | Srce Type | label + `GS_CHGSB_SCR-VLTYP` |
| 5 | TgtQtyA | label + `GS_CHGSB_SCR-VSOLA_CHR` (C12, N7) + `GS_CHGSB_SCR-ALTME` (C21, N5) |
| 6 | HU | label + `GS_CHGSB_SCR-HUIDENT` |
| 7 | Batch | label + `GS_CHGSB_SCR-CHARG` |
| 8 | Static text | `Scan New Storage Bin` (C1, N21) |
| 9 | Bin | label + `GS_CHGSB_SCR-NEWLGPLA` input, no `REQU_ENTRY` |

Do **not** set `REQU_ENTRY` on `NEWLGPLA`; the PAI handles the empty check and shows
message 013. The PBO enables the field with:

```abap
set_screlm_input_on( 'GS_CHGSB_SCR-NEWLGPLA' ).
```

The field order in `GS_CHGSB_SCR` is:

```abap
vltyp
vlpla
vsola_chr  TYPE /scwm/de_rf_qty_char
altme      TYPE meins
huident
matnr
maktx
charg
tanum
vlenr
newlgpla   TYPE /scwm/de_lgpla
newlgtyp
txt        TYPE char80
```

Only the types that are explicitly known are shown. Verify the remaining field types in
the active TOP include before changing the structure.

### 3.3 PBO `ZEWM_RF_ZCHGSB_9100_PBO`

1. Read the current RF line:
   `GET_LINE( )`; if `0`, use line `1`.
   `READ TABLE TT_ORDIM_CONFIRM INDEX LV_LINE INTO ORDIM_CONFIRM`; fall back to
   index `1` if needed.
2. Determine `LGNUM` with the usual RF fallback:
   `ORDIM_CONFIRM-LGNUM -> RESOURCE -> WHO -> GET_LGNUM( )`; call `SET_LGNUM` on
   `/SCWM/CL_TM` and `/SCWM/CL_RF_BLL_SRVC`.
3. Clear `GS_CHGSB_SCR` and fill:
   - `VLTYP`, `VLPLA`, `HUIDENT`, `MATNR`, `TANUM`, `VLENR`
   - `VSOLA_CHR` with `CONVERSION_EXIT_QTYCH_OUTPUT`
   - `ALTME` with `CONVERSION_EXIT_CUNIT_OUTPUT`
   - `MAKTX` from `ORDIM_CONFIRM-MAKTX`, otherwise `MAKT`
   - `CHARG` from `ORDIM_CONFIRM-BATCH`
4. Clear `NEWLGPLA` and `NEWLGTYP`, enable the input, set the status text
   `Scan new source bin` (message 001).

The UoM conversion is required. Without it, the screen shows the internal unit (`ST`,
`KAR`) instead of the external unit (`PC`, `CAR`). Standard SAP uses the `CUNIT`
conversion exit for `MEINS`.

### 3.4 PAI `ZEWM_RF_ZCHGSB_9100_PAI`

The PAI keeps the standard `PIMTTO` CHANGING signature (`ORDIM_CONFIRM`,
`TT_ORDIM_CONFIRM`, `TT_NESTED_HU`, `WME_VERIF`, `RESOURCE`, `T_RF_PICK_HUS`, `WHO`).

#### Validation order

| # | Check | On failure |
|---|---|---|
| 1 | `ORDIM_CONFIRM-TANUM` is not empty | `set_fcode('INIT')`, `e012`, `RETURN` |
| 2 | `GS_CHGSB_SCR-NEWLGPLA` is not empty | `set_fcode('INIT')`, `e013`, `RETURN` |
| 3 | `TRANSLATE ... TO UPPER CASE`, `CONDENSE` | — |
| 4 | New bin is not `ORDIM_CONFIRM-VLPLA` | `set_fcode('INIT')`, `e014`, `RETURN` |
| 5 | `/SCWM/BIN_EXIST_CHECK` returns severity `S` | `e017`, `RETURN` |
| 6 | `/SCWM/LAGP` row exists and `LGTYP = ORDIM_CONFIRM-VLTYP` | `e017`, `RETURN` |
| 7 | `LAGP-SKZUA` is not `X` (not frozen for removal) | `e017`, `RETURN` |
| 8 | If `GUID_LOC` is set, `/SCWM/BIN_ACT_CHECK` with `WMEGC_BINACT_PICK` allows picking | `e017`, `RETURN` |
| 9 | Enough available stock for `VSOLA` (only when `VSOLA > 0`) | `e036(/scwm/ui_adma)`, `RETURN` |
| 10 | Set `GS_CHGSB_SCR-NEWLGTYP`, export context, set shortcut/PRMOD/FCODE | — |

Every error branch must `RETURN`. Without the `RETURN`, the next check overwrites the
message: for example a fake bin would show `e036` instead of `e017`.

#### Bin checks in detail

- `/SCWM/BIN_EXIST_CHECK` is called with the scanned bin and `LGNUM`; the severity must
  be `S`.
- The `/SCWM/LAGP` check verifies the bin exists and its storage type equals the pick
  line's source storage type (`ORDIM_CONFIRM-VLTYP`).
- `SKZUA = 'X'` means the bin is frozen for removal; reject it.
- The bin activity check is only relevant when the bin has a location object:
  `GUID_LOC` non-empty and a row in `/SCWM/BINSTOBJ`. The implementation uses
  `MOVE-CORRESPONDING LAGP TO LAGP_INT` and calls `/SCWM/BIN_ACT_CHECK` with
  `IV_ACTIVITY = WMEGC_BINACT_PICK`; `EV_ALLOWED` must be `X`.

Do **not** use `/SCWM/RF_PICK_BIN_CHANGE_CHECK` for this check; it validates a
different field (`NLPLA`) and is not the right check for the scanned source bin.

#### Stock precheck

Only runs when `ORDIM_CONFIRM-VSOLA > 0`.

```abap
CALL FUNCTION '/SCWM/SELECT_STOCK'
  EXPORTING
    iv_lgnum       = lv_lgnum
    ir_lgpla       = lr_lgpla      " scanned bin
    ir_matnr       = lr_matnr      " current material
    ir_charg       = lr_charg      " current batch
    ir_cat         = lr_cat        " only if ORDIM_CONFIRM-CAT is not initial
    ir_stock_usage = lr_usage      " only if ORDIM_CONFIRM-STOCK_USAGE is not initial
    ir_owner       = lr_owner      " only if ORDIM_CONFIRM-OWNER is not initial
    ir_entitled    = lr_entitled   " only if ORDIM_CONFIRM-ENTITLED is not initial
  IMPORTING
    et_huitm       = lt_huitm
  EXCEPTIONS
    error          = 1
    OTHERS         = 2.
```

The optional ranges are deliberately added only when the RF field is non-initial.
Adding an empty range would filter out valid stock.

Quantity summation:

```abap
lv_target_uom = ordim_confirm-altme.
IF lv_target_uom IS INITIAL.
  lv_target_uom = ordim_confirm-meins.
ENDIF.

LOOP AT lt_huitm INTO ls_huitm.
  IF ls_huitm-altme = lv_target_uom.
    lv_avail_alt = lv_avail_alt + ls_huitm-quana.
  ELSEIF ls_huitm-meins = lv_target_uom.
    lv_avail_alt = lv_avail_alt + ls_huitm-quan.
  ENDIF.
ENDLOOP.

IF sy-subrc <> 0 OR lv_avail_alt < ordim_confirm-vsola.
  set_fcode( 'INIT' ).
  MESSAGE e036(/scwm/ui_adma).
  RETURN.
ENDIF.
```

`QUANA` is the stock quantity in the alternative unit; `QUAN` is the quantity in the
base unit. If the target unit is neither `ALTME` nor `MEINS`, the current
implementation does not convert; in the RF picking flow the target is always one of
these two.

#### Context and handover

```abap
FREE MEMORY ID 'ZCHGSB_CTX'.
CLEAR ls_ctx.                         " TYPE /scwm/ltap

ls_ctx-lgnum   = lv_lgnum.
ls_ctx-tanum   = ordim_confirm-tanum.
ls_ctx-vlpla   = ordim_confirm-vlpla.
ls_ctx-matid   = ordim_confirm-matid.
ls_ctx-batchid = ordim_confirm-batchid.
ls_ctx-matnr   = ordim_confirm-matnr.
ls_ctx-charg   = ordim_confirm-batch.
ls_ctx-vsola   = ordim_confirm-vsola.
ls_ctx-altme   = ordim_confirm-altme.
ls_ctx-nlpla   = gs_chgsb_scr-newlgpla.

EXPORT ctx = ls_ctx TO MEMORY ID 'ZCHGSB_CTX'.

zcl_zewm_rms_det_chgsb=>gs_ctx     = ls_ctx.
zcl_zewm_rms_det_chgsb=>gv_ctx_set = abap_true.
```

Then, in this order:

```abap
set_shortcut( 'ZCSB' ).
set_prmod( '1' ).        " 1 = background; mandatory for the exception flow
set_fcode( 'EXCEPT' ).
```

`BACK` frees `ZCHGSB_CTX`, clears `GV_CTX_SET`, calls `CLEAR_SHORTCUT`, and returns.

### 3.5 BAdI implementation

```abap
METHOD /scwm/if_ex_core_rms_determine~determine.
  CLEAR: et_qmat_cus, ev_set.

  IF iv_call <> c_call_bin_denial.    " c_call_bin_denial = 'C'
    RETURN.
  ENDIF.

  IMPORT ctx = ls_ctx FROM MEMORY ID 'ZCHGSB_CTX'.
  IF sy-subrc <> 0.
    IF gv_ctx_set = abap_true.
      ls_ctx = gs_ctx.
    ELSE.
      RETURN.
    ENDIF.
  ENDIF.

  IF ls_ctx-nlpla IS INITIAL.
    RETURN.
  ENDIF.

  IF ls_ctx-lgnum IS NOT INITIAL AND is_ltap-lgnum <> ls_ctx-lgnum.
    RETURN.
  ENDIF.

  LOOP AT it_qmat ASSIGNING <ls_qmat> WHERE lgpla = ls_ctx-nlpla.
    APPEND <ls_qmat> TO et_qmat_cus.
  ENDLOOP.

  IF et_qmat_cus IS NOT INITIAL.
    ev_set = abap_true.
    FREE MEMORY ID 'ZCHGSB_CTX'.
    CLEAR gv_ctx_set.
  ENDIF.
ENDMETHOD.
```

Key points:

- `IV_CALL` must be `C` (`WMEGC_CALL_BIN_DENIAL`). All other RMS calls keep the
  standard behavior because `EV_SET` stays initial.
- The context is imported from memory, with a static fallback.
- The filter is **only** `LGNUM` + `LGPLA = scanned bin`.
  The implementation deliberately does **not** compare `MATID`, `MATNR`, or `BATCHID`:
  the REMREQ-derived `IS_LTAP` often has these empty in the bin-denial path, and
  `IT_QMAT` is already the candidate set for the current requirement.
- The implementation deliberately does **not** filter `QUAN > 0`; standard RMS logic
  handles quantity and availability.
- `ET_QMAT_CUS` is filled before `EV_SET` is set. If no candidate quant exists in the
  scanned bin, `EV_SET` stays initial and the standard strategy continues.
- On the first successful determination the memory is freed and the static flag is
  cleared, so later split determinations use the standard strategy.

The BAdI definition is `/SCWM/EX_CORE_RMS_DETERMINE` in enhancement spot
`/SCWM/ES_CORE_RMS`; the implementation is `ZEWM_ZCHGSB_RMS_DET` and points to class
`ZCL_ZEWM_RMS_DET_CHGSB`. It is single-use and has no filter. It is called from
`CL_BADI_CORE_RMS~FILTER_SORT_STOCK` in `FORM src_bin_det`
(`/SCWM/LREM_BIN_DETF12`) inside `/SCWM/REM_BIN_DET`.

> Older comments in the PAI mention matching `LGNUM + MATID (+ BATCHID)`. The active
> class does not do that; the bin filter is the effective and tested logic.

### 3.6 Main data structures

| Structure / table | Use |
|---|---|
| `/SCWM/S_RF_ORDIM_CONFIRM` | Current RF pick line (`TANUM`, `VLPLA`, `VLTYP`, `MATNR`, `BATCH`, `VSOLA`, `ALTME`, `MEINS`, `HUIDENT`, `VLENR`) |
| `/SCWM/LTAP` | Context in `ZCHGSB_CTX` (`LGNUM`, `TANUM`, `VLPLA`, `MATID`, `BATCHID`, `MATNR`, `CHARG`, `VSOLA`, `ALTME`, `NLPLA`) |
| `/SCWM/S_AQUA_INT` | One candidate quant in `IT_QMAT` (`LGNUM`, `LGTYP`, `LGPLA`, `MATID`, `CHARG`, `GUID_STOCK`) |
| `/SCWM/TT_AQUA_INT` | Table of candidate quants (`IT_QMAT`, `ET_QMAT_CUS`) |
| `/SCWM/S_STOCK_SELECT` | One row from `/SCWM/SELECT_STOCK` (`ALTME`, `QUANA`, `MEINS`, `QUAN`) |

## 4. Configuration

All configuration below is for application `01`, RF area `PI****`, warehouse `1710`
where applicable. Customizing transport `S4HK902808` is a manual configuration
reference; the user confirmed that the customizing can be rebuilt manually.

### 4.1 `/SCWM/TSTEP_SCR`

| Field | Value |
|---|---|
| `APPLIC` | `01` |
| `LTRANS` | `PI****` |
| `STEP` | `ZCHGSB` |
| `STATE` | `******` |
| `SCR_SQNCE` | `01` |
| `SCR_PROGR` | `SAPLZEWM_FG_RF_ZCHGSB` |
| `SCR_NUM` | `9100` |

### 4.2 `/SCWM/TSTEP_FLOW`

| STEP | FCODE | Function module | SSTEP | PRMOD | FCODE_BCKG |
|---|---|---|---|---|---|
| `PIMTTO` | `ZCHGSB` | `ZEWM_RF_ZCHGSB_9100_PBO` | `ZCHGSB` | `1` | `INIT` |
| `ZCHGSB` | `BACK` | `ZEWM_RF_ZCHGSB_9100_PAI` | `PIMTTO` | `1` | `INIT` |
| `ZCHGSB` | `INIT` | `ZEWM_RF_ZCHGSB_9100_PBO` | `ZCHGSB` | `2` | (blank) |
| `ZCHGSB` | `ENTER` | `ZEWM_RF_ZCHGSB_9100_PAI` | `PIMTTO` | `0` | (blank) |
| `ZCHGSB` | `EXCEPT` | `/SCWM/RF_PICK_EXCEPTION` | `PIMTTO` | `1` | (blank) |

`PRMOD` is `NUMC`. Empty values are stored as `0` and treated as initial, so the
function module's `SET_PRMOD` wins. `PRMOD 1` is background, `PRMOD 2` is foreground.
The `ZCHGSB/EXCEPT` row must have `PRMOD = 1`; otherwise the framework may clear the
FCODE set by the function module.

### 4.3 `/SCWM/TFCOD_PRF`

| STEP | FCODE | PUSHB | FNKEY | SHORTCUT |
|---|---|---|---|---|
| `PIMTTO` | `ZCHGSB` | `PB2` | `F11` | `11` |
| `ZCHGSB` | `BACK` | — | `F7` | `07` |
| `ZCHGSB` | `ENTER` | — | `ENT` | — |

The custom key is a normal function key that calls the step transition. The actual
exception FCODE `EXCEPT` is set by the PAI, not by a standard exception flag.

### 4.4 `/SCWM/TFCOD_CAT`, `/SCWM/TSTEP_CAT`, `/SCWM/TOBJ_TXT`

| Table | Key | Value |
|---|---|---|
| `/SCWM/TFCOD_CAT` | `APPLIC = 01` | `FCODE = ZCHGSB` |
| `/SCWM/TSTEP_CAT` | `APPLIC = 01` | `STEP = ZCHGSB` |
| `/SCWM/TOBJ_TXT` | `APPLIC = 01`, `OBJ_TYPE = 01`, `OBJ_ID = ZCHGSB` | `OBJ_SIZE = 8`; EN `ChgSBin`; ZH `换源货位` |

### 4.5 `/SCWM/TEXCEXEH`

Active row:

| LGNUM | EXCCODE | BUSCON | PRMODE | IPRCODE | DIFTY |
|---|---|---|---|---|---|
| `1710` | `ZCSB` | `TPI` | `05` | `BIDU` | `1` |

Stale rows currently exist:

| LGNUM | EXCCODE | BUSCON | PRMODE | IPRCODE | Status |
|---|---|---|---|---|---|
| `0001` | `ZCSB` | `TPI` | `05` | `BIDF` | stale, not used for 1710 |
| `1710` | `ZCSB` | `TIM` | `05` | `BIDF` | stale, do not use |

`BIDU` is required. `BIDF` only updates memory and returns to `PIMTTO` without creating
the new WT. Keep the `1710 / TPI / 05 / BIDU` row.

### 4.6 `/SCWM/TEXCEPT` description

`ZCSB` has descriptions in many languages. `0001/E` and `1710/E` are
`Change Source Bin`; `0001/1` is `换源货位`.

> **Known cleanup:** the current `1710/1` text is `拒绝全部提货`, which is inherited
> from the standard "reject complete picking" text. If the RF status line or
> exception list should show the correct description, change the `1710`/`ZCSB` text to
> `Change Source Bin` / `换源货位`.

### 4.7 No `/SCWM/TEXCOIE` and no `/SCWM/TPARAM_CAT`

The PAI directly calls `SET_SHORTCUT( 'ZCSB' )`, so no `/SCWM/TEXCOIE` entry is
needed.

The screen fields use the function-group global structure `GS_CHGSB_SCR` from the TOP
include. The PBO/PAI keep the standard `PIMTTO` CHANGING signature. No custom
application-parameter container is registered in `/SCWM/TPARAM_CAT`.

### 4.8 Transport and deployment

| Content | Transport | Notes |
|---|---|---|
| Code (`ZEWM_FG_RF_ZCHGSB`, screen 9100, class `ZCL_ZEWM_RMS_DET_CHGSB`) | `S4HK902806` | task `S4HK902807` |
| BAdI implementation `ZEWM_ZCHGSB_RMS_DET` | `S4HK902812` | owner `REC3WX` |
| Customizing (`TSTEP_SCR`, `TSTEP_FLOW`, `TFCOD_PRF`, `TEXCEXEH`, …) | `S4HK902808` | manual per this section |
| Message class `ZEWM_RF_MSG` 012–017 | `S4HK902782` | task `S4HK902810`, shared with ZDIFHU |

Recommended import order for a fresh offline system:

1. Messages `S4HK902782` (or create 012–017 manually if the message class is not
   already present).
2. Code `S4HK902806`.
3. BAdI `S4HK902812`.
4. Customizing `S4HK902808` manually.

If `ZEWM_RF_MSG` already exists from ZDIFHU, the message transport is not required.

**abapGit:** use abapGit only for the final unified source export/archive. It does not
replace the customizing tables, message class, screen 9100, or BAdI ENHO as a
deployment mechanism. Import the transports for a working system.

After import, verify:

- `ZEWM_ZCHGSB_RMS_DET` is active in `SE19`, enhancement spot
  `/SCWM/ES_CORE_RMS`, BAdI `/SCWM/EX_CORE_RMS_DETERMINE`, class
  `ZCL_ZEWM_RMS_DET_CHGSB`.
- screen `9100` exists in `SAPLZEWM_FG_RF_ZCHGSB`.
- `/SCWM/TSTEP_FLOW` has the five rows above.
- `/SCWM/TEXCEXEH` has the `1710 / TPI / 05 / BIDU` row.
- `ZEWM_RF_MSG` has 012–017 in the required languages.
- If the target warehouse is not `1710`, adapt the `TEXCEXEH` `LGNUM`.

## 5. Acceptance checklist

- [ ] F11 on `PIMTTO` opens screen 9100 with the current pick line.
- [ ] Product, description, source bin, source type, target quantity, HU, and batch are
      displayed correctly.
- [ ] The target quantity unit is displayed as external UoM (`ST -> PC`,
      `KAR -> CAR`).
- [ ] Empty new bin + Enter shows message 013 and stays on 9100.
- [ ] Same bin as the current bin shows message 014.
- [ ] Nonexistent bin, wrong storage type, frozen bin, or picking-blocked bin shows
      message 017 and does **not** show `e036`.
- [ ] A valid bin with enough stock proceeds; no message.
- [ ] A valid bin with insufficient stock shows `e036` and does not create a new WT.
- [ ] BACK returns to `PIMTTO` and clears the context; no new WT is created.
- [ ] A successful run confirms the original WT at quantity `0`, creates a bin denial,
      creates a new WT, and the new WT bin is the scanned bin.
- [ ] The new WT does not use the old bin or a strategy-selected different bin.
- [ ] The BAdI is active and points to `/SCWM/EX_CORE_RMS_DETERMINE` and
      `ZCL_ZEWM_RMS_DET_CHGSB`.
- [ ] A second run in the same RF session does not show the "only one difference
      exception" error after exiting to the RF main menu and re-entering.

## 6. Troubleshooting

1. **New WT is created in a different bin.**
   - Check the BAdI implementation `ZEWM_ZCHGSB_RMS_DET` is active and assigned to
     `/SCWM/EX_CORE_RMS_DETERMINE` (not `EX4`).
   - Check the class is `ZCL_ZEWM_RMS_DET_CHGSB`.
   - Check `IV_CALL = 'C'`; the BAdI returns for all other calls.
   - Check `ZCHGSB_CTX` is exported by the PAI and not already consumed.
   - Check `LGNUM` matches; check `IT_QMAT` contains a row with
     `LGPLA = scanned bin`.
   - Check the BAdI does not have a filter that excludes the WT type.

2. **No new WT; RF returns silently to PIMTTO.**
   - Check `/SCWM/TEXCEXEH`: the `1710 / TPI / 05` row must have `IPRCODE = BIDU`.
   - `BIDF` only changes memory. This is the most common configuration error.

3. **Fake bin shows `e036` ("Could not determine available stock") instead of
   `e017`.**
   - The PAI is missing `RETURN` after the `e017` branches. Every `MESSAGE` in the
     validation chain must be followed by `RETURN`.
   - The stock check must be the last check.

4. **"Only one difference exception is allowed" (`e090`).**
   - The RF session still has a difference exception in memory. Exit RF to the main
     menu and re-enter; do not retry in the same session.

5. **UoM shows `ST` or `KAR` instead of `PC` or `CAR`.**
   - The PBO must use `CONVERSION_EXIT_CUNIT_OUTPUT` for `ALTME`.
   - `T006A`: `KAR -> CAR`, `ST -> PC`.

6. **Stock precheck rejects a bin that visibly has stock.**
   - Check the optional ranges: `CAT`, `STOCK_USAGE`, `OWNER`, `ENTITLED` are added
     only when the RF field is non-initial. An empty range must not be added.
   - Check the target unit: `ALTME` first, then `MEINS`.
   - Check the summation: `QUANA` for `ALTME`, `QUAN` for `MEINS`.
   - Check the material/batch on the RF line.

7. **The new-bin field is not editable.**
   - The PBO must call `SET_SCRELM_INPUT_ON( 'GS_CHGSB_SCR-NEWLGPLA' )`.
   - Do not set `REQU_ENTRY`; the PAI handles the empty check.

8. **Screen layout is wrong after a manual rebuild.**
   - Screen 9100 is type `I`, 15 rows x 26 columns, 9 used rows.
   - Labels in column 1; values at column 12, width 14.
   - Row 2 is `MAKTX` at C1/N26; row 8 is the static text at C1/N21.
   - Every `TEXT` must have `NAME`; template text must be `space`.
   - Verify with `RPY_DYNPRO_READ` and `D020S`.

9. **Message 012 on a valid pick line.**
   - `ORDIM_CONFIRM-TANUM` is empty because PBO did not read the current line.
   - Check `GET_LINE( )` and the `READ TABLE TT_ORDIM_CONFIRM` fallback.

10. **The `1710` exception description is wrong.**
    - Correct `TEXCEPT` `1710 / ZCSB` text to `Change Source Bin` / `换源货位`.
    - `0001` already has the correct text.

## 7. Plan B — manual screen 9100 rebuild

Only needed if the screen cannot be imported. Create screen `9100` in function group
`ZEWM_FG_RF_ZCHGSB` with:

- type `I`, 15 lines x 26 columns;
- labels in column 1, values at column 12, length 14;
- the fields from the table in section 3.2;
- `NEWLGPLA` as an input field, no `REQU_ENTRY`;
- static text `Scan New Storage Bin` at row 8.

After saving, verify `D020S`: `TYPE = 'I'`, `BZMX = 9`, `BZBR = 26`, `NOLI = 15`,
`NOCO = 26`. Then verify the PBO enables `NEWLGPLA` and the PAI reads
`GS_CHGSB_SCR-NEWLGPLA`.

## 8. Object list

| Object | Name | Description |
|---|---|---|
| Function group | `ZEWM_FG_RF_ZCHGSB` | RF function group |
| Main program | `SAPLZEWM_FG_RF_ZCHGSB` | Main program |
| TOP include | `LZEWM_FG_RF_ZCHGSBTOP` | `GS_CHGSB_SCR` |
| PBO FM | `ZEWM_RF_ZCHGSB_9100_PBO` | Fill screen 9100 |
| PAI FM | `ZEWM_RF_ZCHGSB_9100_PAI` | Validate, precheck, export context |
| Screen | `9100` | New-source-bin screen |
| BAdI class | `ZCL_ZEWM_RMS_DET_CHGSB` | RMS bin filter |
| BAdI implementation | `ZEWM_ZCHGSB_RMS_DET` | ENHO in `/SCWM/ES_CORE_RMS` |
| BAdI definition | `/SCWM/EX_CORE_RMS_DETERMINE` | SAP enhancement spot `/SCWM/ES_CORE_RMS` |
| BAdI interface | `/SCWM/IF_EX_CORE_RMS_DETERMINE` | SAP interface |
| Message class | `ZEWM_RF_MSG` | Messages 012–017 |
| Exception code | `ZCSB` | RF exception |
| Function code | `ZCHGSB` | F11 key on `PIMTTO` |
| Customizing | `/SCWM/TSTEP_SCR` | Screen assignment |
| Customizing | `/SCWM/TSTEP_FLOW` | Step flow |
| Customizing | `/SCWM/TFCOD_PRF` | Function keys |
| Customizing | `/SCWM/TFCOD_CAT` | Function code catalog |
| Customizing | `/SCWM/TSTEP_CAT` | Step catalog |
| Customizing | `/SCWM/TEXCEXEH` | Exception control |
| Customizing | `/SCWM/TEXCEPT` | Exception code texts |
| Customizing | `/SCWM/TOBJ_TXT` | RF object texts |
