# ZDIFHU — EWM RF HU Difference Posting

**English** | [中文](README.zh.md)

RF logical transaction `ZDIFHU`, three steps / three screens:

1. **Screen 1 (9000)**: enter or scan the HU number → ENTER
2. **Screen 2 (9001)**: lists every material inside that HU (**sequence no. + material no. / description /
   quantity + unit**, three lines per material). A **sequence number input field** sits at the top:
   type the number → ENTER
3. **Screen 3 (9002)**: shows the selected material (material no. / description / current quantity / unit)
   plus a **counted quantity input field**. Type the counted quantity → ENTER posts the difference
   immediately (**difference = current − counted**, sign convention see §4), then returns to the list and
   refreshes the quantity (the sequence number is cleared automatically)

Posting API: `/SCWM/CL_WM_PACKING->POST_DIFFERENCE` (instance method).

## 1. Installation (abapGit)

1. abapGit → New Offline (or New Online to push to an internal Git) → import the zip of this repository
2. Package: `ZEWM` (the Package you enter when creating the abapGit repo)
3. Pull → activate all objects (DDIC first: `ZSDIFHU_SCR` → `ZSDIFHU_ITEM` → `ZSDIFHU_ITEM_TT`
   → `ZSDIFHU_PROD`, then activate the function group `ZFG_RF_ZDIFHU` as a whole)
4. After activation, verify in SE11 that `/SCWM/DE_HUIDENT`, `/SCWM/DE_RF_SEQNO`, `/SCWM/DE_QUANTITY`,
   `/SCWM/DE_BASE_UOM`, `/SCWM/GUID_HU`, `/LIME/GUID_STOCK` exist. If one of them is missing and
   `ZSDIFHU*` fails to activate, change the affected field in SE11 from the data element reference to a
   built-in type:
   HUIDENT→CHAR 20; SEQNO→NUMC 3; QUAN/QUAN_COUNT→QUAN, length 13, 3 decimals;
   MEINS→UNIT 3; GUID_*→CHAR 32

## 2. Customizing (SPRO → EWM → Mobile Data Entry → RF Framework, in this order)

1. **Define Application Parameters** (`/SCWM/TPARAM_CAT`, view `/SCWM/RF_CUSTOM`, SM30):
   - APPLIC=`01` (WME) / `CS_ZDIFHU_S_SCR` / Parameter Type=`ZSDIFHU_SCR`
   - APPLIC=`01` (WME) / `CS_ZDIFHU_PROD` / Parameter Type=`ZSDIFHU_PROD`
   - APPLIC=`01` (WME) / `CT_ZDIFHU_T_ITEMS` / Parameter Type=`ZSDIFHU_ITEM_TT`

   (PARAM_NAME must match the CHANGING parameter names of the function modules **exactly**, including the
   CS_/CT_ prefix)
2. **Define Steps in Logical Transaction**: `ZDIFHU` → `ZDIF1`, `ZDIF2`, `ZDIF3`
3. **Define Step Flow** (`/SCWM/TSTEP_FLOW`):

   | LTRANS | STEP | FCODE | FMODUL | SSTEP | PRMOD | FCODE_BCKG |
   |---|---|---|---|---|---|---|
   | ZDIFHU | ZDIF1 | INIT | Z_RF_ZDIFHU_9000_PBO | ZDIF1 | 2 | |
   | ZDIFHU | ZDIF1 | ENTER | Z_RF_ZDIFHU_9000_PAI | ZDIF2 | 1 | INIT |
   | ZDIFHU | ZDIF1 | BACK | Z_RF_ZDIFHU_9000_PAI | ZDIF1 | 2 | |
   | ZDIFHU | ZDIF2 | INIT | Z_RF_ZDIFHU_9001_PBO | ZDIF2 | 2 | |
   | ZDIFHU | ZDIF2 | ENTER | Z_RF_ZDIFHU_9001_PAI | ZDIF3 | 1 | INIT |
   | ZDIFHU | ZDIF2 | BACK | Z_RF_ZDIFHU_9001_PAI | ZDIF1 | 1 | INIT |
   | ZDIFHU | ZDIF3 | INIT | Z_RF_ZDIFHU_9002_PBO | ZDIF3 | 2 | |
   | ZDIFHU | ZDIF3 | ENTER | Z_RF_ZDIFHU_9002_PAI | ZDIF3 | 0 | |
   | ZDIFHU | ZDIF3 | BACK | Z_RF_ZDIFHU_9002_PAI | ZDIF2 | 1 | INIT |

   > **Rule A — step changes (a pit we fell into)**: every row that jumps from step A to step B must use
   > `PRMOD=1` with `FCODE_BCKG` set to the PBO trigger code of the target step (`INIT` here). `PRMOD=2`
   > is only for **re-displaying the same step** (e.g. INIT → that step's PBO). Get it wrong and the target
   > step's PBO module is never called → its table data container is never registered → screen 2 raises a
   > `GETWA_NOT_ASSIGNED` dump (`LRF_SSCRO02` line 50, `READ TABLE <gt_scr>`).
   >
   > **Rule B — returning after posting (a pit we fell into)**: the `ENTER` row of the detail screen
   > (ZDIF3) must **not change the step** (`SSTEP` = **ZDIF3 itself**, `PRMOD=0`); the return is performed
   > by `set_prmod('1') + set_fcode('UPDBCK')` at the end of `9002_PAI` — the framework's `UPDBCK` means
   > **go back one step + synchronise the internal call stack + refresh the target step's PBO**. If that
   > row changes the step itself (`SSTEP=ZDIF2, PRMOD=1`), the framework performs a plain navigation,
   > ZDIF3 stays on the call stack, and pressing `BACK` on the list screen later bounces you back to the
   > detail screen.
   >
   > **About `BACK`**: the framework's `BACK` **pops the internal call stack** (the `SSTEP` of rows such as
   > `ZDIF2/BACK` is effectively ignored). Those rows are kept only so that `BACK` also triggers the PAI of
   > the corresponding screen (clearing input fields, etc.). Going back always relies on `UPDBCK` / the
   > stack pop, never on a step flow row.
   - ZDIF1/BACK row: `9000_PAI` calls `set_fcode(c_fcode_compl_ltrans)` internally to end the transaction
     (default navigation table `/SCWM/TTRNS_NAV`) — **the transaction is exited from the first screen only**
   - Paging (when the list exceeds one screen) is handled automatically by the framework's predefined
     fcodes **PGUP/PGDN**; **no** custom DOWN row is needed
4. **Define Function Code Profile**: include INIT / ENTER / BACK
   (PGUP/PGDN are framework-predefined fcodes, available automatically through the template pushbuttons)
5. **Map Logical Transaction Step to Subscreen**:
   - `ZDIFHU`/`ZDIF1` → `SAPLZFG_RF_ZDIFHU` `9000`
   - `ZDIFHU`/`ZDIF2` → `SAPLZFG_RF_ZDIFHU` `9001`
   - `ZDIFHU`/`ZDIF3` → `SAPLZFG_RF_ZDIFHU` `9002`
6. **Presentation / Personalization Profile**: reuse the existing `**` or create new ones as needed
7. **RF Menu Manager**: attach the transaction to a menu (while testing you can call it directly from the
   RF Test Environment)
8. **Exception Codes** (SPRO → EWM → Cross-Process Settings → Exception Codes): confirm that `DIFD` +
   business context `PPT` + execution step `16` exist; if not, maintain them or change the code (the three
   constants `iv_exccode` / `iv_buscon` / `iv_exec_step` in `z_rf_zdifhu_9002_pai.abap`)

## 3. Plan B: rebuilding screens 9001 / 9002 manually (only if the screen import fails)

If the abapGit import reports an `RPY_DYNPRO_INSERT` error (step-loop XML compatibility), delete the
`<item>` of the affected screen from `fugr.xml`, import again, then rebuild the screen in SE51:

**Screen 9001 (list)**: subscreen, 7 lines × 40 columns

- Line 1: text `No.` (col 1) + `ZSDIFHU_SCR-SELNO` (col 6, **input**, NUMC 3)
- Line 2: text `HU:` (col 1) + `ZSDIFHU_SCR-HUIDENT` (col 6, display only)
- From line 3: select the 5 DDIC fields as a Step Loop, **3 lines per block** (`LOOP_BLOCK=3`,
  `LOOP_DISP=1`, `HEIGHT=3`; one material takes 3 lines, so one complete material fits on the screen):
  - block line 1: `ZSDIFHU_ITEM-SEQNO` (col 1, display only), `ZSDIFHU_ITEM-MATNR` (col 5, display only)
  - block line 2: `ZSDIFHU_ITEM-MAKTX` (col 1, display only, length 30)
  - block line 3: `ZSDIFHU_ITEM-QUAN` (col 1, display only, length 13), `ZSDIFHU_ITEM-MEINS`
    (col 15, display only)
- Read-only fields use **`OUTPUT_FLD=X` only** — do **not** add `OUTPUTONLY`, which renders the value as
  flat text instead of the standard read-only box (SAP's own RF screens use `OUTPUTONLY` 0 times);
  **input fields use only `INPUT_FLD=X + OUTPUT_FLD=X` and must never carry `REQU_ENTRY`** (see §5 item 8)
- A dynpro screen may not contain two fields with the same name — two display fields that both need the
  unit use two DDIC fields (`MEINS` + `MEINS_DSP`)
- A multi-line block must satisfy **`HEIGHT = LOOP_BLOCK × LOOP_DISP`** (all standard screens do, e.g.
  `/SCWM/RF_INQUIRY_PM` screen 0204: `LOOP_BLOCK=4 × LOOP_DISP=2 = HEIGHT=8`)
- Flow logic (identical to `src/zfg_rf_zdifhu.fugr.screen_9001.abap`):

  ```abap
  PROCESS BEFORE OUTPUT.
    MODULE status_sscr_loop.
    LOOP.
      MODULE loop_output.
    ENDLOOP.
    MODULE loop_scrolling_set.
  *
  PROCESS AFTER INPUT.
    LOOP.
      MODULE loop_input.
    ENDLOOP.
    MODULE user_command_sscr.
  ```

**Screen 9002 (detail)**: subscreen, 7 lines × 40 columns

- Line 1: `ZSDIFHU_PROD-MATNR` (display only, no label)
- Line 2: `ZSDIFHU_PROD-MAKTX` (display only, no label)
- Line 3: `ZSDIFHU_PROD-QUAN` (display only) + `ZSDIFHU_PROD-MEINS` (display only)
- Line 4: text `Actual Qty` (the only label kept on the screen)
- Line 5: `ZSDIFHU_PROD-QUAN_COUNT` (**input**) + `ZSDIFHU_PROD-MEINS_DSP` (display only)
  (`MEINS_DSP` is a second unit field kept in the structure for display only — a dynpro screen may not
  contain two fields with the same name. The duplicate names you see in SAP's own RF screens are always
  "TEXT label + TEMPLATE field" pairs, never two TEMPLATE fields.)
- Flow logic (identical to `src/zfg_rf_zdifhu.fugr.screen_9002.abap`):

  ```abap
  PROCESS BEFORE OUTPUT.
    MODULE STATUS_SSCR.
  *
  PROCESS AFTER INPUT.
    MODULE USER_COMMAND_SSCR.
  ```

Activate.

## 4. Acceptance checklist

- [ ] Call `ZDIFHU` from `/SCWM/RFUI` (or the RF Test Environment); screen 1 shows the HU input field
- [ ] Enter an existing HU → ENTER → screen 2 shows the material list
      (**sequence no. + material no. / description on separate lines + quantity + unit**)
- [ ] On screen 2, enter a non-existing sequence number → error "Item does not exist" (validation works)
- [ ] Enter an existing sequence number → ENTER → screen 3 shows that material
      (material no. / description / current quantity / unit)
- [ ] On screen 3, enter the counted quantity → ENTER → posting succeeds and returns to the list
      (quantity refreshed, sequence number cleared)
- [ ] On screen 3, enter 0 / a negative quantity / nothing → error
      "Counted quantity must be greater than zero", nothing is posted
- [ ] On screen 3, enter the same quantity as the current one → error
      "Counted quantity equals current quantity", nothing is posted
- [ ] Screen 3 BACK → back to the list; screen 2 BACK → back to screen 1; screen 1 BACK → leave the
      transaction and return to the menu
      (screen 2's BACK works only when the `ZDIF3/ENTER` row in the step flow uses
      `SSTEP=ZDIF3 + PRMOD=0`)
- [ ] Difference = current − counted (shortage positive → stock decreases, surplus negative → stock
      increases); verify the stock afterwards in `/SCWM/MON`
- [ ] More than 1 material in the list → paging (PGUP/PGDN) works (one material per screen, 3 lines each)

> **Posting sign convention (implementation detail — do not get it backwards when changing code)**: in
> `/SCWM/CL_WM_PACKING->POST_DIFFERENCE`, `is_quan-quan` **positive = goods issue (stock decreases),
> negative = goods receipt (stock increases)** (internally it picks `wmegc_lime_post_outbound` /
> `wmegc_lime_post_inbound` from the sign). `9002_PAI` therefore passes
> **`current quantity − counted quantity`**: a shortage (counted < current) is positive → stock decreases;
> a surplus (counted > current) is negative → stock increases.

## 5. Troubleshooting (after Pull, if it will not run / throws errors — check in this order)

1. **Screen 2 list empty / `GETWA_NOT_ASSIGNED` dump (`LRF_SSCRO02` line 50, `<gt_scr>` not assigned)**:
   check whether the cross-step jump rows in `/SCWM/TSTEP_FLOW` use `PRMOD=1` + `FCODE_BCKG=INIT`.
   If a step's PBO module never runs (in ST22 you can see `ST_SCR_PARAM` holding only the values
   registered by the previous step), this is the culprit — `PRMOD=2` means "re-display the same step"
   and does not trigger the target step's PBO.

2. **Activation reports a syntax error** (`... is not a key field` or `method ... not found`):
   check `/SCWM/CL_RF_BLL_SRVC` in SE24 and confirm that `GET_FCODE` / `SET_FCODE` / `SET_PRMOD` /
   `SET_LINE` / `SET_FIELD` / `SET_SCR_TABNAME` / `INIT_SCREEN_PARAM` / `SET_SCREEN_PARAM` are all static
   methods with matching signatures; if not, align the code with the standard `/SCWM/RF_*` function
   modules in your system.

3. **Runtime dump** (short dump in the DYNPRO/RF call chain): the standard RF framework catches E-type
   messages and shows them at the bottom of the screen, so it should not dump. If it does, replace the
   `MESSAGE e001(00) WITH '...'` in the FM with a standard RF message class `MESSAGE eXXX(zmsg)`.

4. **Import reports `RPY_DYNPRO_INSERT`**: follow §3 Plan B.

5. **Activation reports a missing data element**: follow §1 step 4 and switch to built-in types.

6. **Posting reports a wrong exception code**: confirm `DIFD/PPT/16` as described in §2 step 8.

7. **List empty / data does not reach the screen**: verify that the PARAM_NAMEs in §2 step 1 match the FM
   CHANGING parameter names exactly (`CS_ZDIFHU_S_SCR` / `CS_ZDIFHU_PROD` / `CT_ZDIFHU_T_ITEMS`).

8. **An input field cannot be typed into (quantity box / sequence box)**: check whether that screen field
   carries `<REQU_ENTRY>N</REQU_ENTRY>` in the XML — **standard RF input fields never carry `REQU_ENTRY`**
   (compare `/SCWM/RF_INQUIRY_PM`: 36 fields with `INPUT_FLD=X`, 356 fields with `REQU_ENTRY=N`,
   **intersection = 0**). With `REQU_ENTRY=N` the field becomes non-enterable in RF.
   Fix: remove the `<REQU_ENTRY>` element and switch the input attribute on explicitly in that screen's PBO
   (`/scwm/cl_rf_bll_srvc=>set_screlm_input_on( 'ZSDIFHU_PROD-QUAN_COUNT' )`, see
   `z_rf_zdifhu_9001_pbo.abap` / `_9002_pbo.abap`).

9. **Pressing ENTER dumps immediately with `CALL_FUNCTION_PARM_MISSING` (`CX_SY_DYN_CALL_PARAM_MISSING`,
   complaining about a missing parameter such as `CS_ZDIFHU_PROD`)**: this is not a code problem —
   `/SCWM/TPARAM_CAT` (view `/SCWM/RF_CUSTOM`) is **missing the corresponding data container row**, so the
   framework cannot build the parameter table and fails before calling the FM (the FM body never executes).
   Verify that all three rows from §2 step 1 exist.

10. **Pressing BACK on the list screen returns to the detail screen**: the `ZDIF3/ENTER` row in
    `/SCWM/TSTEP_FLOW` is set to `SSTEP=ZDIF2 + PRMOD=1`. Change it to **`SSTEP=ZDIF3 + PRMOD=0`**
    (see §2 step 3, rule B).

## 6. Object list

| Object | Name | Description |
|---|---|---|
| Package | ZEWM | |
| Function Group | ZFG_RF_ZDIFHU | Screens 9000/9001/9002 + 6 function modules (includes INCLUDE /SCWM/IRF_SSCR) |
| Structure | ZSDIFHU_SCR | Screen single values (HUIDENT + SELNO sequence input) |
| Structure | ZSDIFHU_ITEM | List row (SEQNO + MATNR + MAKTX + QUAN + MEINS + GUID_*) |
| Structure | ZSDIFHU_PROD | Detail screen (SEQNO + MATNR + MAKTX + QUAN current + MEINS + QUAN_COUNT counted + MEINS_DSP + GUID_*) |
| Table type | ZSDIFHU_ITEM_TT | List internal table |
| App. Parameter | CS_ZDIFHU_S_SCR / CS_ZDIFHU_PROD / CT_ZDIFHU_T_ITEMS | Global data containers (Customizing) |
