# ZDIFHU — EWM RF HU Difference Posting

**English** | [中文](README.zh.md)

> **Status:** implemented and verified end-to-end on S/4HANA embedded EWM (client 100) — the three-step
> flow plus the HU-detail screen (9004, opened from the list via the HUINFO pushbutton), posting in both
> directions, the BACK navigation chain, the input-field attributes and the DE/CS/FR/ZH translations were
> all tested in the system. Delivery: abapGit repository `tankren/ZEWM`, subfolder `zdifhu/` (31 files).
> Acceptance checklist: §4.

RF logical transaction `ZDIFHU`, three steps / four screens (screen 9004 is the HU detail, opened
from screen 2 with the **HUINFO** pushbutton):

1. **Screen 1 (9000)**: enter or scan the HU number → ENTER
2. **Screen 2 (9001)**: lists every material inside that HU (**sequence no. + material no. / description /
   quantity + unit**, three lines per material). A **sequence number input field** sits at the top:
   type the number → ENTER
3. **Screen 3 (9002)**: shows the selected material (material no. / description / current quantity / unit)
   plus a **counted quantity input field**. Type the counted quantity → ENTER posts the difference
   immediately (**difference = current − counted**, sign convention see §4), then returns to the list and
   refreshes the quantity (the sequence number is cleared automatically)
4. **Screen 4 (9004)**: on screen 2 press the **HUINFO** pushbutton (PB1 / F1) → the HU header data is
   displayed (HU number, HU type, packaging material, gross/tare weight, gross/tare volume, dimensions,
   bin, ...); `BACK` (F7) returns to the list. The screen is a **copy of the standard HU-detail screen**
   `/SCWM/SAPLRF_INQUIRY_PM` 0202 (13 × 27) and reuses the **standard** structure `/SCWM/S_RF_INQ_HU` as
   its data container — no new DDIC object was added for it

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
5. **Translations (DE / CS / FR / ZH)** are delivered as abapGit LXE files (`*.i18n.<lang>.po`) and are
   written back into the system by the Pull itself — **no SE63 work needed**. The language list is already
   in the repository's `.abapgit.xml` (`<I18N_LANGUAGES>` + `<USE_LXE>`); if the translated texts do not
   show up, check the abapGit repo settings → *Serialize Translations (experimental LXE approach)* and
   enter `DE,CS,FR,ZH`
6. All error messages come from the message class `ZEWM_RF_MSG` (`src/zewm_rf_msg.msag.xml`, imported by the
   Pull; nothing to activate)

## 2. Customizing (SPRO → EWM → Mobile Data Entry → RF Framework, in this order)

1. **Define Application Parameters** (`/SCWM/TPARAM_CAT`, view `/SCWM/RF_CUSTOM`, SM30):
   - APPLIC=`01` (WME) / `CS_ZDIFHU_S_SCR` / Parameter Type=`ZSDIFHU_SCR`
   - APPLIC=`01` (WME) / `CS_ZDIFHU_PROD` / Parameter Type=`ZSDIFHU_PROD`
   - APPLIC=`01` (WME) / `CT_ZDIFHU_T_ITEMS` / Parameter Type=`ZSDIFHU_ITEM_TT`
   - APPLIC=`01` (WME) / `CS_ZDIFHU_HU` / Parameter Type=`/SCWM/S_RF_INQ_HU`
     (HU-detail screen 9004 — the **standard** structure is reused, no Z object needed)

   (PARAM_NAME must match the CHANGING parameter names of the function modules **exactly**, including the
   CS_/CT_ prefix)
2. **Define Steps in Logical Transaction**: `ZDIFHU` → `ZDIF1`, `ZDIF2`, `ZDIF3`, `ZDIF4`
3. **Define Step Flow** (`/SCWM/TSTEP_FLOW`):

   | LTRANS | STEP | FCODE | FMODUL | SSTEP | PRMOD | FCODE_BCKG |
   |---|---|---|---|---|---|---|
   | ZDIFHU | ZDIF1 | INIT | Z_RF_ZDIFHU_9000_PBO | ZDIF1 | 2 | |
   | ZDIFHU | ZDIF1 | ENTER | Z_RF_ZDIFHU_9000_PAI | ZDIF2 | 1 | INIT |
   | ZDIFHU | ZDIF1 | BACK | Z_RF_ZDIFHU_9000_PAI | ZDIF1 | 2 | |
   | ZDIFHU | ZDIF2 | INIT | Z_RF_ZDIFHU_9001_PBO | ZDIF2 | 2 | |
   | ZDIFHU | ZDIF2 | ENTER | Z_RF_ZDIFHU_9001_PAI | ZDIF3 | 1 | INIT |
   | ZDIFHU | ZDIF2 | BACK | Z_RF_ZDIFHU_9001_PAI | ZDIF1 | 1 | INIT |
   | ZDIFHU | ZDIF2 | HUINFO | Z_RF_ZDIFHU_9001_PAI | ZDIF4 | 1 | INIT |
   | ZDIFHU | ZDIF3 | INIT | Z_RF_ZDIFHU_9002_PBO | ZDIF3 | 2 | |
   | ZDIFHU | ZDIF3 | ENTER | Z_RF_ZDIFHU_9002_PAI | ZDIF3 | 0 | |
   | ZDIFHU | ZDIF3 | BACK | Z_RF_ZDIFHU_9002_PAI | ZDIF2 | 1 | INIT |
   | ZDIFHU | ZDIF4 | INIT | Z_RF_ZDIFHU_9004_PBO | ZDIF4 | 2 | |
   | ZDIFHU | ZDIF4 | BACK | Z_RF_ZDIFHU_9004_PAI | ZDIF2 | 1 | INIT |

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
4. **Define Function Code Profile** (`/SCWM/TFCOD_PRF`): INIT / ENTER / BACK (and CLEAR) for the three
   working steps, plus **`HUINFO` on `ZDIF2` with `PUSHB=PB1`** (or `FNKEY=F1` / `SHORTCUT=01`) so the
   button appears on the list screen, and BACK on `ZDIF4`. `HUINFO` itself must exist in
   `/SCWM/TFCOD_CAT` for `APPLIC=01`
   (PGUP/PGDN are framework-predefined fcodes, available automatically through the template pushbuttons)
5. **Map Logical Transaction Step to Subscreen**:
   - `ZDIFHU`/`ZDIF1` → `SAPLZFG_RF_ZDIFHU` `9000`
   - `ZDIFHU`/`ZDIF2` → `SAPLZFG_RF_ZDIFHU` `9001`
   - `ZDIFHU`/`ZDIF3` → `SAPLZFG_RF_ZDIFHU` `9002`
   - `ZDIFHU`/`ZDIF4` → `SAPLZFG_RF_ZDIFHU` `9004`
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

**Screen 9004 (HU detail)**: copy the standard screen `/SCWM/SAPLRF_INQUIRY_PM` **0202** (13 lines × 27
columns, 38 fields — one `TEXT` label + one `TEMPLATE` field per attribute; that duplicate-name pattern
is exactly what SAP's own screens look like) and change only the program name / screen number
(`SAPLZFG_RF_ZDIFHU` / `9004`). It reuses the **standard** structure `/SCWM/S_RF_INQ_HU`, so the TOP
include needs `TABLES /scwm/s_rf_inq_hu.` and the container `CS_ZDIFHU_HU` is filled by the `HUINFO`
branch of `9001_PAI`. Flow logic:

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
- [ ] On screen 2 press the **HUINFO** pushbutton (PB1 / F1) → screen 4 shows the HU header data
      (HU type, packaging material, weights/volumes, dimensions, bin); `BACK` (F7) returns to the list
- [ ] Log on with language DE / CS / FR / ZH → the screen labels (`HU`, `No.`, `HU:`, `Actual Qty`) and the
      error messages appear translated

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
   messages and shows them at the bottom of the screen, so it should not dump. All error messages are
   raised from the message class `ZEWM_RF_MSG` (`MESSAGE eNNN(zewm_rf_msg)`, e.g. `MESSAGE e001(zewm_rf_msg)`);
   when you add a message, put it into `src/zewm_rf_msg.msag.xml` **and** into the four
   `zewm_rf_msg.msag.i18n.<lang>.po` files.

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
   complaining about a missing parameter such as `CS_ZDIFHU_PROD` or `CS_ZDIFHU_HU`)**: this is not a
   code problem —
   `/SCWM/TPARAM_CAT` (view `/SCWM/RF_CUSTOM`) is **missing the corresponding data container row**, so the
   framework cannot build the parameter table and fails before calling the FM (the FM body never executes).
   Verify that all **four** rows from §2 step 1 exist — the parameter named in the dump tells you which
   one is missing.

10. **Pressing BACK on the list screen returns to the detail screen**: the `ZDIF3/ENTER` row in
    `/SCWM/TSTEP_FLOW` is set to `SSTEP=ZDIF2 + PRMOD=1`. Change it to **`SSTEP=ZDIF3 + PRMOD=0`**
    (see §2 step 3, rule B).

11. **Translated texts do not show up (DE/CS/FR/ZH)**: the LXE PO files are matched by the **English
    source text** — if the English original in the system differs (case, trailing blanks) that entry is
    skipped silently; a screen label longer than its field is truncated. Also check the repo settings:
    *Serialize Translations (experimental LXE approach)* on, language list `DE,CS,FR,ZH` (the repository's
    `.abapgit.xml` already carries it). Field widths of the labels: `HU` = 2 (screen 9000), `No.` = 3,
    `HU:` = 3 (screen 9001), `Actual Qty` = 10 (screen 9002).

12. **The HUINFO pushbutton does not appear on screen 2**: the fcode needs a function code profile row —
    `/SCWM/TFCOD_PRF`, `APPLIC=01` / `LTRANS=ZDIFHU` / `STEP=ZDIF2` / `FCODE=HUINFO` with `PUSHB=PB1`
    (or `FNKEY=F1`), and `HUINFO` must exist in `/SCWM/TFCOD_CAT` for `APPLIC=01` (see §2 step 4).

13. **HUINFO jumps to the standard HU screen (or dumps)**: `/SCWM/TSTEP_SCR` maps `ZDIF4` to the standard
    program `/SCWM/SAPLRF_INQUIRY_PM` screen `202`. Change both `ZDIF4` rows to `SAPLZFG_RF_ZDIFHU` /
    `9004` (see §2 step 5).

## 6. Object list

| Object | Name | Description |
|---|---|---|
| Package | ZEWM | |
| Function Group | ZFG_RF_ZDIFHU | Screens 9000/9001/9002/9004 + 8 function modules (includes INCLUDE /SCWM/IRF_SSCR) |
| Structure | ZSDIFHU_SCR | Screen single values (HUIDENT + SELNO sequence input) |
| Structure | ZSDIFHU_ITEM | List row (SEQNO + MATNR + MAKTX + QUAN + MEINS + GUID_*) |
| Structure | ZSDIFHU_PROD | Detail screen (SEQNO + MATNR + MAKTX + QUAN current + MEINS + QUAN_COUNT counted + MEINS_DSP + GUID_*) |
| Table type | ZSDIFHU_ITEM_TT | List internal table |
| App. Parameter | CS_ZDIFHU_S_SCR / CS_ZDIFHU_PROD / CT_ZDIFHU_T_ITEMS / CS_ZDIFHU_HU | Global data containers (Customizing). `CS_ZDIFHU_HU` points to the **standard** structure `/SCWM/S_RF_INQ_HU`, reused by the HU-detail screen 9004 |
| Message class | ZEWM_RF_MSG | All error messages of the FMs (`MESSAGE eNNN(zewm_rf_msg)`, 001–011) |
| Translations | `zfg_rf_zdifhu.fugr.i18n.<lang>.po` + `zewm_rf_msg.msag.i18n.<lang>.po` | DE / CS / FR / ZH: 7 screen texts + 9 messages, written back by abapGit LXE |
