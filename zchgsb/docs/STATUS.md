# 状态（交接文件）

> 用法：开工第一句"先读 zchgsb/docs/STATUS.md"。阶段性工作结束必须回来更新。
> 最后更新：2026-11-05（README 完成；BAdI 已落地）

## 当前目标

EWM RF 拣货 **PIMTTO** 屏幕新增 **CHGSB / Change Source Bin** 功能键：
拣货时发现源货位货不对/不够 → 按 F11 进入自定义屏 9100 → 扫新源货位 → 原 WT 以 0 数量确认 + bin denial + 自动建新 WT；新 WT 的货位由 BAdI 限定为扫描货位。

---

## 一、当前进度（2026-11-05）

**主链路已跑通**：F11 → 屏 9100 → 扫货位 → 0 数量确认 + 生成新 WT，且新 WT 货位 = 扫描货位 ✅

关键突破：`/SCWM/TEXCEXEH` 里自定义异常码 **ZCSB 的 IPRCODE 用 `BIDU` 才能跑通**。
用 `BIDF` 时 `RF_PICK_EXCEPTION` 只改内存（`ndifa/nista/bind`）+ `set_fcode(ENTER)` 后静默回 PIMTTO，
后续 `PIMTTO/ENTER` 链不执行；改成 `BIDU` 后同样的链立刻完成 0 数量确认并建新 WT。
（原因未深究；BIDF/BIDU 在 `bind_check_and_initiate` 里是同一分支，差异应在更上游的 verify/process_exception。先记录现象。）

### 已完成

| 环节 | 对象 | 状态 |
|---|---|---|
| 函数组 | `ZEWM_FG_RF_ZCHGSB`（主程序 `SAPLZEWM_FG_RF_ZCHGSB`） | ✅ 已激活，旧 `ZFG_RF_CHGSB` 已删 |
| TOP | `LZEWM_FG_RF_ZCHGSBTOP`（结构 `gs_chgsb_scr`） | ✅ |
| FM PBO | `ZEWM_RF_ZCHGSB_9100_PBO` | ✅ |
| FM PAI | `ZEWM_RF_ZCHGSB_9100_PAI` | ✅ |
| 屏幕 | `SAPLZEWM_FG_RF_ZCHGSB` 9100（15 行 × 26 列） | ✅ |
| SM34 功能键 | `ZCHGSB`（PB2 / F11 / shortcut 11），旧 `CHGSB` 全部清除 | ✅ |
| SM34 异常码 | `ZCSB` → iprcode **BIDU**（1710 用户手工改；0001 需核对） | ✅ 生效 |
| 消息 | `ZEWM_RF_MSG` 012–017 × 5 语言 | ✅ |
| BAdI 实现类 | `ZCL_ZEWM_RMS_DET_CHGSB`（TR `S4HK902806`） | ✅ 已激活 |
| BAdI ENHO | `ZEWM_ZCHGSB_RMS_DET`（spot `/SCWM/ES_CORE_RMS`，TR `S4HK902812`） | ✅ 已激活，新 WT 货位=扫描货位 |

### BAdI 实施现状（2026-11-05）

- **EX4 是死对象**：`/SCWM/EX4_CORE_RMS_DETERMINE` 在 `WBCROSSGT` 中零引用；实际调用点是
  `CL_BADI_CORE_RMS~FILTER_SORT_STOCK` → `/SCWM/EX_CORE_RMS_DETERMINE`（Single-use，spot `/SCWM/ES_CORE_RMS`，
  接口 `/SCWM/IF_EX_CORE_RMS_DETERMINE`）。
- **TANUM/旧货位不可用**：`/SCWM/TO_CREATE_BIN_DENIAL` 在调 `REM_BIN_DET` 前清空 `VLPLA/VLENR/TANUM`
  （`/SCWM/S_REMREQ` 本身没有 TANUM），`IS_LTAP` 里没有这些键。PAI 改为把上下文导出到内存 ID
  `ZCHGSB_CTX`（lgnum/tanum/vlpla/matid/batchid/matnr/charg/vsola/altme/nlpla），BAdI 用
  `IV_CALL='C'` + `LGNUM` + `LGPLA=扫描货位` 接管。
- 实现类 `ZCL_ZEWM_RMS_DET_CHGSB`（包 `ZEWM`，TR `S4HK902806` / task `S4HK902807`）：
  - 只处理 `IV_CALL='C'`（`wmegc_call_bin_denial`）；其他调用 `ev_set` 保持空，走标准。
  - `IMPORT ctx = ls_ctx FROM MEMORY ID 'ZCHGSB_CTX'`；读不到时用静态兜底 `gs_ctx/gv_ctx_set`；
    `ls_ctx-nlpla` 为空直接 RETURN。
  - `ls_ctx-lgnum` 非空且 `is_ltap-lgnum` 不同则 RETURN。
  - `LOOP AT it_qmat WHERE lgpla = ls_ctx-nlpla`，全部 APPEND 到 `et_qmat_cus`；有数据才
    `ev_set='X'`，并 `FREE MEMORY ID 'ZCHGSB_CTX'` + 清 `gv_ctx_set`。
  - **不比较 MATID/MATNR/BATCHID，也不过滤 `QUAN > 0`**：bin denial 的 REMREQ 派生 LTAP 经常没有这些字段；
    `IT_QMAT` 已是当前需求的候选 quant，按扫描货位过滤即可。
- ENHO `ZEWM_ZCHGSB_RMS_DET`（TR `S4HK902812`，owner `REC3WX`）已在 SE19 创建并激活，指向 spot
  `/SCWM/ES_CORE_RMS`、BAdI `/SCWM/EX_CORE_RMS_DETERMINE`、类 `ZCL_ZEWM_RMS_DET_CHGSB`；未设 filter
  （代码内按 `IV_CALL` + `LGNUM` 限定）。
- 已用 1710 验证：F11 → 扫货位 → 新 WT 源货位 = 扫描货位。

### 9100 ENTER 可用库存 precheck（2026-11-05）

- PAI 2.5 新增：调用 `/SCWM/SELECT_STOCK`（lgnum + 扫描货位 + matnr + charg；
  cat/stock_usage/owner/entitled 仅当 RF 行有值时过滤），按目标 UoM 汇总：
  `ALTME` 用 `QUANA`，`MEINS` 用 `QUAN`；与 `VSOLA` 比较；不再手工调 `MATERIAL_QUAN_CONVERT`。
- 不足或无可用库存：`set_fcode('INIT')` + `MESSAGE e036(/scwm/ui_adma)`。
- 9100 PBO 的 `ALTME` 已改为 `CONVERSION_EXIT_CUNIT_OUTPUT`（内部 KAR/ST → 外部 CAR/PC），
  与标准 SAP 的 `MEINS` conversion exit 一致。
- **库存校验修正**：`QUANA` 只适用于 `ET_HUITM-ALTME = 目标 UoM`；若
  `lv_target_uom = ls_huitm-meins`（目标就是库存 BUoM），改为汇总 `ls_huitm-quan`
  （BUoM），不再用 `QUANA`。已实现并激活。
- 目标 UoM 只会是 `ALTME` 或 `MEINS`；“既不是 ALTME 也不是 MEINS”的情况不会出现，不再做通用换算。
- 所有错误分支 `MESSAGE` 后都加了 `RETURN`；库存校验放在最后，假货位会先报 e017，不会被 e036 覆盖。
- 暂未新增 `ZEWM_RF_MSG` 018：该消息类已在 zdifhu 的 `S4HK902810` 里，避免跨 TR；
  需要自定义文案时再单独加。

---

## 二、系统对象现状

### 代码（TR `S4HK902806` / 任务 `S4HK902807`，包 `ZEWM`）

- FUGR `ZEWM_FG_RF_ZCHGSB`，主程序 `SAPLZEWM_FG_RF_ZCHGSB`
  （include：`LZEWM_FG_RF_ZCHGSBTOP` + `LZEWM_FG_RF_ZCHGSBUXX`）
- 名字风格对齐 ZDIFHU：`ZEWM_RF_<项目>_<屏幕>_PBO|PAI`，项目名是 **ZCHGSB**。

**TOP 结构 `gs_chgsb_scr`（字段顺序）**
```
vltyp, vlpla, vsola_chr, altme, huident, matnr, maktx,
charg, tanum, vlenr, newlgpla, newlgtyp, txt TYPE char80
```
- `vsola_chr` 类型 `/SCWM/DE_RF_QTY_CHAR`（显示用，已格式化，无尾零）
- `newlgpla` 类型 `/SCWM/DE_LGPLA`

**PBO `ZEWM_RF_ZCHGSB_9100_PBO`**（约 91 行）
1. `lv_line = /scwm/cl_rf_bll_srvc=>get_line( )`；0 → 1 + `set_line( 1 )`；
   **`READ TABLE tt_ordim_confirm INDEX lv_line INTO ordim_confirm`**（失败取 INDEX 1）——
   这一步不能省，框架传进来的 `ordim_confirm` 是空的，否则数量/HU/批次全空。
2. lgnum 兜底：ordim → resource → who → `get_lgnum( )`，再 `set_lgnum`（`/scwm/cl_tm=>` + `/scwm/cl_rf_bll_srvc=>`）。
3. 赋值 `vltyp / vlpla / huident / tanum / vlenr / matnr / maktx / charg`
   - `matnr = ordim_confirm-matnr`（**不要**再走 MATID_TO_MATNR）
   - `charg = ordim_confirm-batch`（`/SCWM/S_RF_ORDIM_CONFIRM-BATCH`，**不要**走 BATCH_SEARCH2）
   - `maktx` 空时 `SELECT SINGLE maktx FROM makt WHERE matnr = ... AND spras = sy-langu`
4. 数量：`CALL FUNCTION 'CONVERSION_EXIT_QTYCH_OUTPUT' EXPORTING input = ordim_confirm-vsola IMPORTING output = gs_chgsb_scr-vsola_chr`
   （FG `/SCWM/SAPLRF_GENERAL_EN`，EWM RF 专用，去尾零）
5. `CLEAR newlgpla/newlgtyp`；`set_screlm_input_on( 'GS_CHGSB_SCR-NEWLGPLA' )`；`txt` 状态文本。

**PAI `ZEWM_RF_ZCHGSB_9100_PAI`**（约 275 行）
- 前置检查顺序：`tanum` 空 → e012；`newlgpla` 空 → e013；`TRANSLATE/CONDENSE`；同货位 → e014；
  货位校验链 → e017。
- 货位校验链：`/SCWM/BIN_EXIST_CHECK`（`e_rc_severity` 必须 `S`）
  → `SELECT /scwm/lagp`（存在且 `lgtyp = ordim_confirm-vltyp`）
  → `skzua = 'X'` 冻结 → `guid_loc` 非空且 `/scwm/binstobj` 有行时 `/SCWM/BIN_ACT_CHECK`
  （`iv_activity = wmegc_binact_pick`，需 `TYPE-POOLS wmegc`，`ev_allowed` 必须 `X`）。
  不要用 `/SCWM/RF_PICK_BIN_CHANGE_CHECK`（那是校验 NLPLA）。
- 2.5 库存 precheck（最后做）：`ordim_confirm-vsola > 0` 时调 `/SCWM/SELECT_STOCK`
  （lgnum + 扫描货位 + matnr + charg；cat/usage/owner/entitled 仅当 RF 行有值时过滤）；
  按目标 UoM 汇总 `QUANA`（ALTME）或 `QUAN`（MEINS），不足/无库存报 `e036(/scwm/ui_adma)`。
  每个错误 `MESSAGE` 后都有 `RETURN`。
- 成功尾部（**顺序不能变**）：
  ```abap
  " ls_ctx TYPE /SCWM/LTAP，填：
  " lgnum/tanum/vlpla/matid/batchid/matnr/charg/vsola/altme/nlpla
  FREE MEMORY ID 'ZCHGSB_CTX'.
  EXPORT ctx = ls_ctx TO MEMORY ID 'ZCHGSB_CTX'.    " 给 BAdI 用
  zcl_zewm_rms_det_chgsb=>gs_ctx = ls_ctx.
  zcl_zewm_rms_det_chgsb=>gv_ctx_set = abap_true.
  /scwm/cl_rf_bll_srvc=>set_shortcut( 'ZCSB' ).
  /scwm/cl_rf_bll_srvc=>set_prmod( '1' ).           " 1 = background，必须有
  /scwm/cl_rf_bll_srvc=>set_fcode( 'EXCEPT' ).
  ```
- BACK 分支：`FREE MEMORY ID 'ZCHGSB_CTX'` + `CLEAR zcl_zewm_rms_det_chgsb=>gv_ctx_set` + `clear_shortcut( )`。

### 屏幕 9100（15 行 × 26 列，`D020S TYPE='I'`，`BZBR=26`）

RF 模板 `/SCWM/SAPLRF_TMPL` 0021 = 15×26，与 display profile 一致；标签列 1，值列 12，值宽 14。

| 行 | 内容 |
|---|---|
| 1 | TEXT `Product` + TEMPLATE `GS_CHGSB_SCR-MATNR` |
| 2 | TEMPLATE `GS_CHGSB_SCR-MAKTX`（C1 N26，产品描述，无标签） |
| 3 | TEXT `Src Bin` + `GS_CHGSB_SCR-VLPLA` |
| 4 | TEXT `Srce Type` + `GS_CHGSB_SCR-VLTYP` |
| 5 | TEXT `TgtQtyA` + `GS_CHGSB_SCR-VSOLA_CHR`(C12 N7) + `GS_CHGSB_SCR-ALTME`(C21 N5) |
| 6 | TEXT `HU` + `GS_CHGSB_SCR-HUIDENT` |
| 7 | TEXT `Batch` + `GS_CHGSB_SCR-CHARG` |
| 8 | TEXT `Scan New Storage Bin`（C1 N21，静态） |
| 9 | TEXT `Bin` + `GS_CHGSB_SCR-NEWLGPLA`（`INPUT_FLD='X'`，**不设** REQU_ENTRY） |

OKCODE 由 OK_FIELD 自动生成（L0 C0 N20），不要手传。

### Customizing（TR `S4HK902808` / 任务 `S4HK902809`）

| 表 | 内容 |
|---|---|
| `/SCWM/TSTEP_SCR` | `ZCHGSB` → `SAPLZEWM_FG_RF_ZCHGSB` / `9100` |
| `/SCWM/TSTEP_FLOW` | 见下 |
| `/SCWM/TFCOD_PRF` | (PIMTTO, ZCHGSB) PB2/F11/11/SQNCE 02；`ZCHGSB/ENTER`（FNKEY='ENT'）；`ZCHGSB/BACK` F7/07 |
| `/SCWM/TFCOD_CAT` + `TFCOD_CATT` | 只剩 `ZCHGSB`（E=ChgSBin, 1=换源货位） |
| `/SCWM/TSTEP_CAT` + `TSTEP_CATT` | 只剩 `ZCHGSB` |
| `/SCWM/TOBJ_TXT` | `APPLIC=01, OBJ_TYPE=01, OBJ_ID=ZCHGSB, OBJ_SIZE=8` |
| `/SCWM/TEXCEXEH` | `LGNUM=1710, EXCCODE=ZCSB, BUSCON=TPI, PRMODE=05, IPRCODE=BIDU, DIFTY=1`；0001 和 1710/TIM 的 BIDF 行是历史残留，不要用 |
| `/SCWM/TEXCEPT` | `ZCSB`：E=Change Source Bin，1=换源货位；⚠️ 当前 1710/1 文本是“拒绝全部提货”（标准残留），需改成“换源货位” |
| `/SCWM/TEXCOIE` | 不参与（PAI 直接 `set_shortcut`，不走 fcode→shortcut 映射） |

**TSTEP_FLOW 现状**（`APPLIC=01, LTRANS=PI****`）

| STEP | FCODE | FMODUL | SSTEP | PRMOD | FCODE_BCKG |
|---|---|---|---|---|---|
| PIMTTO | ZCHGSB | `ZEWM_RF_ZCHGSB_9100_PBO` | ZCHGSB | 1 | INIT |
| ZCHGSB | ENTER | `ZEWM_RF_ZCHGSB_9100_PAI` | PIMTTO | 0 | （空） |
| ZCHGSB | BACK | `ZEWM_RF_ZCHGSB_9100_PAI` | PIMTTO | 1 | INIT |
| ZCHGSB | INIT | `ZEWM_RF_ZCHGSB_9100_PBO` | ZCHGSB | 2 | （空） |
| ZCHGSB | EXCEPT | `/SCWM/RF_PICK_EXCEPTION` | PIMTTO | 1 | （空） |

> PRMOD 是 NUMC：写 `''` 存成 `'0'`，框架 `IS INITIAL` 判定为真，会采用 FM 里 `set_prmod` 的值。
> `ZCHGSB/EXCEPT` 必须是 PRMOD=1（background），否则 FM 里 `set_fcode` 被框架 `CLEAR`。

### 消息（`ZEWM_RF_MSG`）

012 无有效拣货行 / 013 请扫描或输入新的源货位 / 014 新旧货位相同 /
015 建 WT 失败-原任务已确认需人工补偿 / 016 源货位已更改 / 017 货位无效或被冻结。
运行时还会用标准 `e036(/scwm/ui_adma)` 报“无法确定可用库存”。

---

## 三、下一步（按顺序）

### 1. BAdI（已完成，2026-11-05）

- 实际 BAdI 是 `/SCWM/EX_CORE_RMS_DETERMINE`（`/SCWM/EX4_...` 是死对象）。
- 类 `ZCL_ZEWM_RMS_DET_CHGSB` + ENHO `ZEWM_ZCHGSB_RMS_DET`（TR `S4HK902812`）已激活。
- 1710 已验证：F11 → 扫货位 → 新 WT 源货位 = 扫描货位。
- 系统级默认分支必须保持 `ev_set = space` + `RETURN`，只接管 `IV_CALL='C'`。

### 2. 本地同步与 abapGit

- 系统 PAI 已在每个 `MESSAGE` 后加 `RETURN`；本地 PAI 已按系统导出同步（274 行，含 `RETURN` / static fallback）。
- `zchgsb/src/` 文件名已改为：
  `zewm_fg_rf_zchgsb.fugr.zewm_rf_zchgsb_9100_pbo.abap` / `..._pai.abap`；已补 TOP / UXx include，类文件已同步。
- 屏幕 9100 的布局在 FUGR XML 的 `<DYNPROS>` 里；当前 MCP 导出不含 FUGR XML，需在 SAP 里跑一次 abapGit 全量导出才能补 `zewm_fg_rf_zchgsb.fugr.xml`。
- zchgsb 需要独立 abapGit 仓库，起始目录 `/zchgsb/src/`（现有仓库起始目录是 `/zdifhu/src/`）；导入前先 `git commit`。

### 3. 文档

- 已新增中英 README：`README.md` / `README.zh.md`（设计 / 流程 / 实现 / 配置 / 消息 / 验收 / 排障 / 对象清单）。
- 本文件已同步；`docs/HANDOVER.md`、`docs/TASK_exception_badi.md` 的旧方案已过期，以本文件为准。

### 4. 部署

- 收集/释放 TR：代码 `S4HK902806`、BAdI `S4HK902812`、消息 `S4HK902782`；配置 `S4HK902808` 手工。

---

## 四、关键坑（都是踩过的）

### RF 框架

1. **PRMOD / FCODE_BCKG**：FM 要动态决定下一步时，`TSTEP_FLOW` 行的 PRMOD 和 FCODE_BCKG 必须留空，由 FM 里 `set_prmod` / `set_fcode` 决定。
   `CALL_FLOW_PROCESS` 里：`prmod = 2`（background）才把 FM 设的 fcode 带出去，否则 `CLEAR ss_rf_dynamic-fcode`。
   - cookbook 3.21.5：PRMOD **1 = background**，2 = foreground；步骤屏上的行不要写死 PRMOD。
   - `SET_PRMOD` 有可选参数 `iv_ovr_cust`，非空时会把 `ss_rf_dynamic-prmod` 清零。
2. **STOP 在 `RF_PICK_EXCEPTION` 里的 e090**（"Only one difference exception is allowed"，源码第 308 行）：
   它检查 `ordim_confirm-exc_tab` 里**已有**条目，而 append 在第 358 行、之后只 `MODIFY tt_ordim_confirm`（纯内存，无 COMMIT）。
   → 同一 RF 会话里重试必然 e090。**测试前必须退出 RF 到主菜单再重进**。
3. `/SCWM/RF_PICK_EXCEPTION` 的 BIDF 分支只改内存，真正落地在 `PIMTTO/ENTER → RF_PICK_HU_CLOSE_CHECK → ENTERF → RF_PICK_PIMTTO_PAI`。链一断就是"回 PIMTTO 什么都没发生"。
4. `set_shortcut/get_shortcut/clear_shortcut/set_prmod/set_fcode` 都在 `/SCWM/CL_RF_BLL_SRVC`；`set_fcode` 只写 `ss_content_navigation-fcode`。
5. 标准"异常功能键"机制：`TFCOD_PRF` 某键行 `FLG_EXCEPTION='X'` + `SHORTCUT='****'`，框架会把该键当 background 并保留 shortcut。
   SKWO/LIST/NEXT 都是这么触发（`TEXCEXEH` 决定 iprcode），没有各自的 TSTEP_FLOW 行，统一走 `(PIMTTO, EXCEPT) → /SCWM/RF_PICK_EXCEPTION`。
6. SKWO 分支是"自己 post + COMMIT + CLEAR 缓冲 + 重启事务"；BIDF/BIDU 是"只置标志，靠确认链"。换源货位属于后者。

### 屏幕（RPY_DYNPRO_INSERT）

7. 元素**紧邻也算触碰**（37/315）：标签最长到第 10 列，值列从 12 起。
8. 每个 `TEXT` 必须给 `NAME`（与 TEMPLATE 同字段名），否则 Personas `CL_DYNP_CONTAINER~PROCESS_TEXT` 用 `lbl[0]` 重名 → `ITAB_DUPLICATE_KEY` dump。
9. `TEMPLATE` 的 `text` 必须传 `space`（传 'X' 会无消息失败）；宏参数不能传 `''`。
10. `dycatt_tab` / `dyfatc_tab` 是**表类型**用 `DATA lt TYPE dyfatc_tab` + `TYPE LINE OF`；`RPY_DYFLOW` 是**结构**，flow_logic 要 `STANDARD TABLE OF rpy_dyflow`。
11. HEADER：`type='I'`、`lines`、`columns`、`descript`；已存在时靠 `suppress_exist_checks='X'` 覆盖；`corrnum='S4HK902806'`。
12. 验证用 `RPY_DYNPRO_READ` + `SELECT D020S`（`D020S` 有行才算建成）。`D021S/D022S/D023S` 是 INTTAB，SELECT 不了。
13. D020S `BZMX/BZBR` 是已用行/列，`NOLI/NOCO` 是屏尺寸；`TYPE='I'` 与标准 RF 屏一致。
14. 改 TOP 结构 + FM 必须用 `activateObjects` **一起激活**，单独激活会循环报错。

### 命名 / 传输 / 环境

15. FM / FG 必须 `ZEWM` 开头；FG = `ZEWM_FG_RF_ZCHGSB`，FM = `ZEWM_RF_ZCHGSB_9100_PBO|PAI`。
16. 命名空间 `/ZEWM/` 未注册，禁用；屏幕号段自定义 9xxx，本项目 9100。
17. E071 组件是 `OBJ_NAME`，E071K 是 `OBJNAME`；E071K 主键含 `AS4POS`；TABKEY 按 DDIC 顺序直连、HANA 去尾零/空格。
18. `TR_APPEND_TO_COMM_OBJS_KEYS` 没有 `IV_SIMULATION` 参数；MSAG 的 E071 `OBJFUNC` 必须空。
19. MCP 会话整体 400/500 时调 `login(destination='S4H')` 恢复。
20. `runSnippet` 单行 < 255 字符；`runQuery` 不支持 JOIN、表名不能加双引号。
21. 命名空间对象 URL 必须编码（`%2fscwm%2f...`）；FUGR include 读源码用 `grepPackage`（`getObjectSource` 只返回 XML）。
22. Personas dump 的堆栈：`/SCWM/RF_UI_START → CL_RF_BLL_SRVC~RUN → DISPLAY_STEP → CL_RF_DYNPRO_SRVC~DISPLAY_SCREEN`。

### 业务/字段

23. 拣货行的 LGNUM 是 **1710**（不是 0001），异常码配置必须配在 1710。
24. `/SCWM/S_RF_ORDIM_CONFIRM` 有 `BATCH`（=批号）、`VSOLA`、`ALTME`、`MAKTX`，**没有 CHARG**；`VSOLA_CHR` 只用于数量校验，不是显示字段。
25. `ORDIM_O` 没有 `NISTA/NDIFA/TAPOS`；`/SCWM/DE_VSOLA` 不存在，用 `/SCWM/LTAP_VSOLA`。
26. DD04T 字段是 `DDTEXT/SCRTEXT_S/SCRTEXT_M/SCRTEXT_L`（没有 AS4TEXT）；只查 `DDLANGUAGE='E'`。
27. 标签必须用 DDIC 官方文本、首字母大写：`Src Bin`(VLPLA) / `Srce Type`(VLTYP) / `TgtQtyA`(VSOLA) / `HU`(HUIDENT) / `Product`(MATNR) / `Batch`(CHARG) / `Bin`(LGPLA)。

---

## 五、本地文件

```
zchgsb/
├── README.md                # 英文说明（2026-11-05 新增）
├── README.zh.md             # 中文说明
├── src/                     # abapGit 序列化（文件名待改成 zewm_fg_rf_zchgsb.*）
├── docs/
│   ├── STATUS.md            # ← 本文件，唯一权威
│   ├── HANDOVER.md          # 2026-11-04 交接（部分过期）
│   └── TASK_exception_badi.md  # 任务书（BAdI 接口全文在 3.x 节）
└── AGENTS.md
```

- 唯一系统：**S4H client 100**；ER1 无关，不要连。
- 本地 git 是唯一真源；MCP 默认只读，要写系统必须先得到同意。
