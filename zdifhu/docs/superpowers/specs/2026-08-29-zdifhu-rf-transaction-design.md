# ZDIFHU — EWM RF Logical Transaction 设计文档

- 日期：2026-08-29
- 系统：SAP S/4HANA embedded EWM
- 交付格式：abapGit 风格（参考 ZMM 项目：`src/package.devc.xml` + 源码 + README）
- 状态：**已实现并在系统实测通过**（三步四屏 / HU 明细屏 9004 / 过账两个方向 / BACK 返回链路 / 输入属性 / 多语言）
- 实现过程中的关键修订（与本文档初版的差异）见 plan 的「执行后修订 1–5」

---

## 1. 需求概述

新建 RF logical transaction `ZDIFHU`，三步四屏流程：

**业务背景**：GR 收货后、上架前的 **shortage 识别与纠正** —— 实盘数量必须 **> 0**
（0 无业务含义：没有货就不构成 shortage；负数、空都不允许）。

- **屏幕 1 (9000)**：输入/扫描 HU 号，ENTER 后跳转到屏幕 2
- **屏幕 2 (9001)**：显示 HU 内库存列表（每物料占 3 行：序号 + 物料号 / 描述 / 数量 + 单位），
  顶部有**序号输入框**；输入序号 + ENTER → 进入屏幕 3
- **屏幕 3 (9002)**：显示选中物料的明细（物料号 / 描述 / 当前数量 / 单位），
  输入**实盘数量** + ENTER → 立即过账差异 → 返回列表（序号自动清空）
- **屏幕 4 (9004)**：在屏幕 2 上按 **HUINFO** 按钮（PB1/F1）→ 显示 HU 抬头信息（HU 类型、包装物料、
  毛重/净重、毛体积/净体积、长宽高、库位、危险品标识等）；`BACK`(F7) 返回列表。该屏幕**直接复用标准屏幕**
  `/SCWM/SAPLRF_INQUIRY_PM` 的 0202（13×27），数据容器复用**标准结构** `/SCWM/S_RF_INQ_HU`（不新增 DDIC 对象）
- 一屏放不下时，用框架预定义的 **PGUP/PGDN** 翻页（模板上的翻页按钮）
- 过账 API：`/SCWM/CL_WM_PACKING->POST_DIFFERENCE`（实例方法）
- 差异计算：差异 = 当前系统数量 − 实盘数量（代码自己算，符号约定见 §3.3）

## 2. 架构与对象

| 对象 | 名称 | 说明 |
|---|---|---|
| 开发包 | `ZEWM` | abapGit repo 的 Package |
| Function Group | `ZFG_RF_ZDIFHU` | RF 屏幕函数组（主程序含 `INCLUDE /SCWM/IRF_SSCR`） |
| 屏幕 1 | `9000` | HU 号输入（子屏幕） |
| 屏幕 2 | `9001` | 物料列表：序号 + 物料号/描述/数量/单位（每物料 3 行）+ 序号输入框 |
| 屏幕 3 | `9002` | 明细 + 实盘数量输入 + 差异过账（子屏幕） |
| 屏幕 4 | `9004` | HU 抬头明细（从屏幕 2 的 HUINFO 按钮进入；复用标准屏 0202 与标准结构 `/SCWM/S_RF_INQ_HU`） |
| 全局结构（单值） | `ZSDIFHU_SCR` | 屏幕字段容器：huident、selno（序号输入） |
| 全局结构（行） | `ZSDIFHU_ITEM` | 列表行：seqno, matnr, maktx, quan, meins, guid_stock, guid_hu |
| 全局结构（明细） | `ZSDIFHU_PROD` | 明细屏：seqno, matnr, maktx, quan(当前), meins, quan_count(实盘), guid_* |
| 表类型 | `ZSDIFHU_ITEM_TT` | 列表内表 |
| App. Parameter 1 | `CS_ZDIFHU_S_SCR` | PARAM_TYPE=`ZSDIFHU_SCR`（视图 `/SCWM/RF_CUSTOM`，表 `/SCWM/TPARAM_CAT`，APPLIC=`01`） |
| App. Parameter 2 | `CT_ZDIFHU_T_ITEMS` | PARAM_TYPE=`ZSDIFHU_ITEM_TT`（同上） |
| App. Parameter 3 | `CS_ZDIFHU_PROD` | PARAM_TYPE=`ZSDIFHU_PROD`（同上） |
| App. Parameter 4 | `CS_ZDIFHU_HU` | PARAM_TYPE=`/SCWM/S_RF_INQ_HU`（**标准结构**，HU 明细屏 9004 用） |
| FM PBO/PAI | `Z_RF_ZDIFHU_9000_PBO` / `_PAI` | 屏幕 1：读 HU、填列表 |
| FM PBO/PAI | `Z_RF_ZDIFHU_9001_PBO` / `_PAI` | 屏幕 2：列表 + 序号选择 |
| FM PBO/PAI | `Z_RF_ZDIFHU_9002_PBO` / `_PAI` | 屏幕 3：明细 + 差异过账 |
| FM PBO/PAI | `Z_RF_ZDIFHU_9004_PBO` / `_PAI` | 屏幕 4：HU 明细（PBO 只注册容器 `CS_ZDIFHU_HU`；PAI 只有 BACK） |
| 消息类 | `ZEWM_RF_MSG` | 8 个 FM 的全部报错消息（`MESSAGE eNNN(zewm_rf_msg)`，001–011） |
| 翻译 | `*.i18n.<语言>.po`（abapGit LXE） | DE / CS / FR / ZH：7 条屏幕文本 + 9 条消息；Pull 时自动写回系统 |

### Step Flow（/SCWM/TSTEP_FLOW）

> **执行后修订（2026-09-14）**：下表是实际跑通的最终配置。
>
> - **规则 A（跳步）**：**凡「A 步 → B 步」的跳转行必须 `PRMOD=1` 且 `FCODE_BCKG` 填目标步
>   PBO 的触发码（INIT）**；`PRMOD=2` 只用于同一步骤重显示。原设计把跨步骤行写成
>   `PRMOD=2` 且无 `FCODE_BCKG`，导致目标步 PBO 模块从不执行 → 表数据容器未注册 →
>   屏幕 2 `GETWA_NOT_ASSIGNED` dump（`LRF_SSCRO02` 第 50 行）。原 `ZDIF2/DOWN` 行已删除
>   （翻页由框架预定义 fcode PGUP/PGDN 自动处理）。
> - **规则 B（过账后返回）**：明细屏 `ZDIF3/ENTER` 行**不换步**（`SSTEP=ZDIF3`、`PRMOD=0`），
>   返回由 `9002_PAI` 结尾的 `set_prmod('1') + set_fcode('UPDBCK')` 完成（`UPDBCK` =
>   回上一步 + 同步内部调用栈 + 刷新目标步 PBO）。若该行自己换步（`SSTEP=ZDIF2, PRMOD=1`），
>   框架只做普通导航、调用栈里仍残留 ZDIF3 → 在列表屏按 `BACK` 会被弹回明细屏。
> - **`BACK` 由框架弹内部调用栈处理**（不读 step flow 行的 `SSTEP`），保留 BACK 行只是为了
>   让 BACK 也能触发对应屏幕的 PAI。
> - **HUINFO 按钮（屏幕 2 → 屏幕 4）走同一条规则 A**：`ZDIF2/HUINFO → SSTEP=ZDIF4 + PRMOD=1 +
>   FCODE_BCKG=INIT`；`HUINFO` 分支只填容器 `CS_ZDIFHU_HU`，不自己 `set_fcode` 跳屏。

```
ZDIFHU / ZDIF1 / INIT  → Z_RF_ZDIFHU_9000_PBO  → ZDIF1  (PRMOD 2, 同步骤重显示)
ZDIFHU / ZDIF1 / ENTER → Z_RF_ZDIFHU_9000_PAI  → ZDIF2  (PRMOD 1, FCODE_BCKG=INIT)
ZDIFHU / ZDIF1 / BACK  → Z_RF_ZDIFHU_9000_PAI  → ZDIF1  (PRMOD 2, 同步骤重显示)
ZDIFHU / ZDIF2 / INIT  → Z_RF_ZDIFHU_9001_PBO  → ZDIF2  (PRMOD 2, 同步骤重显示)
ZDIFHU / ZDIF2 / ENTER → Z_RF_ZDIFHU_9001_PAI  → ZDIF3  (PRMOD 1, FCODE_BCKG=INIT)
ZDIFHU / ZDIF2 / BACK  → Z_RF_ZDIFHU_9001_PAI  → ZDIF1  (PRMOD 1, FCODE_BCKG=INIT)
ZDIFHU / ZDIF3 / INIT  → Z_RF_ZDIFHU_9002_PBO  → ZDIF3  (PRMOD 2, 同步骤重显示)
ZDIFHU / ZDIF3 / ENTER → Z_RF_ZDIFHU_9002_PAI  → ZDIF3  (PRMOD 0, 不换步；返回靠 PAI 的 UPDBCK)
ZDIFHU / ZDIF3 / BACK  → Z_RF_ZDIFHU_9002_PAI  → ZDIF2  (PRMOD 1, FCODE_BCKG=INIT)
ZDIFHU / ZDIF2 / HUINFO → Z_RF_ZDIFHU_9001_PAI → ZDIF4  (PRMOD 1, FCODE_BCKG=INIT)
ZDIFHU / ZDIF4 / INIT  → Z_RF_ZDIFHU_9004_PBO  → ZDIF4  (PRMOD 2, 同步骤重显示)
ZDIFHU / ZDIF4 / BACK  → Z_RF_ZDIFHU_9004_PAI  → ZDIF2  (PRMOD 1, FCODE_BCKG=INIT)
```

### Customizing（SPRO → EWM → Mobile Data Entry → RF Framework）

1. **Define Application Parameters**（SM30 视图 `/SCWM/RF_CUSTOM`，底层表 `/SCWM/TPARAM_CAT`；
   IMG 位于 "Define Steps in Logical Transactions" 活动下的子结构）：
   - APPLIC=`01`（WME），`CS_ZDIFHU_S_SCR` → Parameter Type `ZSDIFHU_SCR`
   - APPLIC=`01`（WME），`CT_ZDIFHU_T_ITEMS` → Parameter Type `ZSDIFHU_ITEM_TT`
   - APPLIC=`01`（WME），`CS_ZDIFHU_PROD` → Parameter Type `ZSDIFHU_PROD`
   - APPLIC=`01`（WME），`CS_ZDIFHU_HU` → Parameter Type `/SCWM/S_RF_INQ_HU`（标准结构，HU 明细屏 9004）
   - 这些参数是跨步骤/跨 PBO-PAI 的全局数据容器，**必须同时作为 CHANGING 参数写进
     8 个 FM 的接口**（框架按参数名匹配传入），且先于 step/flow 配置；漏配任何一行，
     框架调 FM 时会直接 `CALL_FUNCTION_PARM_MISSING`
2. Define Steps in Logical Transaction：`ZDIFHU` → steps `ZDIF1`、`ZDIF2`、`ZDIF3`、`ZDIF4`
3. Define Step Flow：上表条目
4. Define Function Code Profile（`/SCWM/TFCOD_PRF`）：三个工作步的 INIT / ENTER / BACK（及 CLEAR）；
   **`ZDIF2` 加 `HUINFO`（`PUSHB=PB1`，或 `FNKEY=F1` + `SHORTCUT=01`）** 列表屏才有按钮；`ZDIF4` 加 BACK。
   `HUINFO` 必须在 `/SCWM/TFCOD_CAT`（APPLIC=`01`）里存在（翻页 PGUP/PGDN 为框架预定义）
5. Map Logical Transaction Step to Subscreen：
   - `ZDIFHU/ZDIF1` → `SAPLZFG_RF_ZDIFHU 9000`
   - `ZDIFHU/ZDIF2` → `SAPLZFG_RF_ZDIFHU 9001`
   - `ZDIFHU/ZDIF3` → `SAPLZFG_RF_ZDIFHU 9002`
   - `ZDIFHU/ZDIF4` → `SAPLZFG_RF_ZDIFHU 9004`
6. Presentation / Personalization Profile 分配（复用现有 `**`，或按需要新建）
7. RF Menu Manager：菜单挂载（可选，测试期可直接用 RF Test Environment 调用）
8. Define Exception Codes（SPRO → EWM → Cross-Process Settings → Exception Codes）：
   确认 `DIFD` + 业务上下文 `PPT` + 执行步骤 `16` 组合存在（差异过账必传）

## 3. 数据流与关键实现

### 3.0 FM 接口约定（8 个 FM 统一）

```abap
FUNCTION z_rf_zdifhu_9000_pbo.   " 其余 7 个 FM 同构（只声明本步用到的容器）
*"  CHANGING
*"     REFERENCE(CS_ZDIFHU_S_SCR)   TYPE ZSDIFHU_SCR      " = App.Param CS_ZDIFHU_S_SCR
*"     REFERENCE(CT_ZDIFHU_T_ITEMS) TYPE ZSDIFHU_ITEM_TT  " = App.Param CT_ZDIFHU_T_ITEMS
*"     REFERENCE(CS_ZDIFHU_PROD)    TYPE ZSDIFHU_PROD     " = App.Param CS_ZDIFHU_PROD
*"     REFERENCE(CS_ZDIFHU_HU)      TYPE /SCWM/S_RF_INQ_HU " = App.Param CS_ZDIFHU_HU（屏幕 4，标准结构）
```
- **不能有 `IMPORTING` 字段参数**（框架只传 CHANGING 参数表，见 §3.4）。
- CHANGING 参数名与 Application Parameter 同名（带 `CS_`/`CT_` 前缀），框架按名匹配动态传入。
  某步用不到的容器可以不写进该 FM 接口，但必须已在 `/SCWM/TPARAM_CAT` 里定义 —— 否则框架
  调该步 FM 时会 `CALL_FUNCTION_PARM_MISSING`。

### 3.1 屏幕 1 PAI（HU 校验 + 库存读取 → 填列表容器）

```abap
DATA: lt_huident   TYPE /scwm/tt_huident,
      lt_huhdr     TYPE /scwm/tt_huhdr_int,
      lt_huitm     TYPE /scwm/tt_huitm_int,
      ls_mat_global TYPE /scwm/s_material_global.

lv_lgnum = /scwm/cl_rf_bll_srvc=>get_lgnum( ).   " 框架不传 IMPORTING，FM 内自己取
/scwm/cl_tm=>set_lgnum( lv_lgnum ).

" 1. HU 读取（combined read：先 buffer 再 DB，保证拿到刚过完账的最新数据）
APPEND cs_zdifhu_s_scr-huident TO lt_huident.
CALL FUNCTION '/SCWM/HU_READ_MULT'
  EXPORTING it_huident = lt_huident  iv_lgnum = lv_lgnum
  IMPORTING et_huhdr   = lt_huhdr    et_huitm = lt_huitm
  EXCEPTIONS wrong_input = 1 not_possible = 2 OTHERS = 3.
" HU 不存在 / 读失败 → set_fcode('INIT') + MESSAGE e002(zewm_rf_msg)（停留本屏）

" 2. 只取直接项目（不支持嵌套包装）
CLEAR ct_zdifhu_t_items.
LOOP AT lt_huitm INTO ls_huitm WHERE guid_parent = lt_huhdr[ 1 ]-guid_hu.
  " MATID → MATNR（抛 class-based exception，不是 EXCEPTIONS 参数）
  TRY.
      CALL FUNCTION '/SCWM/MATERIAL_READ_SINGLE'
        EXPORTING iv_matid = ls_huitm-matid iv_langu = sy-langu
        IMPORTING es_mat_global = ls_mat_global.
    CATCH /scwm/cx_md.
      CONTINUE.
  ENDTRY.
  " 描述
  SELECT SINGLE maktx FROM makt INTO ls_item-maktx
    WHERE matnr = ls_mat_global-matnr AND spras = sy-langu.
  " 组装 ZSDIFHU_ITEM 行：seqno（序号，自增）/ matnr / maktx / quan(当前) / meins / guid_stock / guid_hu
  APPEND ls_item TO ct_zdifhu_t_items.
ENDLOOP.
" 列表为空 → MESSAGE e003(zewm_rf_msg)（该 HU 无物料）
```

### 3.2 屏幕 2 PBO（列表三件套 + 输入属性，必需）

```abap
/scwm/cl_rf_bll_srvc=>init_screen_param( ).
/scwm/cl_rf_bll_srvc=>set_screen_param( 'CS_ZDIFHU_S_SCR' ).    " 单值容器
/scwm/cl_rf_bll_srvc=>set_screen_param( 'CT_ZDIFHU_T_ITEMS' ).  " 表容器（FM CHANGING 参数名）
/scwm/cl_rf_bll_srvc=>set_scr_tabname( 'CT_ZDIFHU_T_ITEMS' ).   " ← 传【参数名】
/scwm/cl_rf_bll_srvc=>set_line( '1' ).
/scwm/cl_rf_bll_srvc=>set_screlm_input_on( 'ZSDIFHU_SCR-SELNO' ).  " 序号框可输入
/scwm/cl_rf_bll_srvc=>set_field( 'ZSDIFHU_SCR-SELNO' ).
```
- `set_scr_tabname` 传**参数名**：与系统内标准 `/SCWM/RF_XDIFHU_DISP_HU_PBO` 一致
  （它传 `'CT_XDIFHU_LOOP'`）。cookbook 文字写的是「传表类型名」，与本系统标准程序不一致，
  **以标准程序为准**。
- 屏幕字段名 = 容器结构名-字段名（`ZSDIFHU_ITEM-MATNR` / `ZSDIFHU_SCR-SELNO` …），
  且 TOP include 必须有 `TABLES: zsdifhu_scr, zsdifhu_item, zsdifhu_prod.`
- 可输入字段的 dynpro 属性只用 `INPUT_FLD + OUTPUT_FLD`，**不能带 `REQU_ENTRY`**，
  并在 PBO 里用 `set_screlm_input_on` 显式打开（见 README §5 第 8 条）。
- 只读字段**只用 `OUTPUT_FLD`**（不加 `OUTPUTONLY`，否则是平面文字而非标准只读框；标准程序
  `/SCWM/RF_INQUIRY_PM` 里 `OUTPUTONLY` 出现 0 次）。
- 同一个 dynpro 屏幕**不允许两个同名字段**（两处都显示单位 → 用 `MEINS` + `MEINS_DSP` 两个字段）。

### 3.3 屏幕 2 PAI（序号选择）与屏幕 3 PAI（差异过账）

**9001_PAI（列表屏，序号驱动）**：

```abap
CASE /scwm/cl_rf_bll_srvc=>get_fcode( ).
  WHEN 'BACK'.
    CLEAR cs_zdifhu_s_scr-selno.          " 回屏 1 由框架弹调用栈处理
  WHEN OTHERS.                            " ENTER
    IF cs_zdifhu_s_scr-selno IS INITIAL.  " 防呆 1：必须输序号
      set_fcode('INIT') + MESSAGE e008(zewm_rf_msg).
    ENDIF.
    READ TABLE ct_zdifhu_t_items INTO ls_item WITH KEY seqno = cs_zdifhu_s_scr-selno.
    IF sy-subrc <> 0.                     " 防呆 2：序号必须存在
      set_fcode('INIT') + MESSAGE e009(zewm_rf_msg).
    ENDIF.
    CLEAR cs_zdifhu_prod.                 " 明细由 9002_PBO 按 selno 填
  WHEN 'HUINFO'.                            " 抄标准 /SCWM/RF_INQ_INHULT_PAI 的 HUINFO 分支
    CLEAR cs_zdifhu_s_scr-selno.  CLEAR cs_zdifhu_hu.
    lv_huident = cs_zdifhu_s_scr-huident.
    IF lv_huident IS INITIAL.               " HU 号为空
      set_fcode('INIT') + MESSAGE e001(zewm_rf_msg).
    ENDIF.
    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT' ... " 前导零补齐
    CALL FUNCTION '/SCWM/HU_READ'            " 标准 FM（无 EXCEPTIONS 子句）
      EXPORTING iv_lgnum = lv_lgnum  iv_huident = lv_huident
      IMPORTING es_huhdr = ls_huhdr.
    IF ls_huhdr-huident IS INITIAL.          " 查不到
      set_fcode('INIT') + MESSAGE e002(zewm_rf_msg).
    ENDIF.
    MOVE-CORRESPONDING ls_huhdr TO cs_zdifhu_hu.
    " 库位回退链 lgpla → rsrc → tu_num → wsbin；包装物料 PMAT = pmat_guid（RAW16，
    " 屏幕字段带 CONV_EXIT=MDLPD，自动显示成物料号）
    cs_zdifhu_hu-pmat = ls_huhdr-pmat_guid.
    cs_zdifhu_hu-huident = cs_zdifhu_s_scr-huident.
ENDCASE.
```
（`HUINFO` 分支只填容器、**不自己 `set_fcode` 跳屏** —— 跳屏由 step flow 的 `ZDIF2/HUINFO` 行完成；
屏幕 4 的 `9004_PBO` 只做 `init_screen_param( ) + set_screen_param( 'CS_ZDIFHU_HU' )`，`9004_PAI` 只有
`BACK` 空处理。）

**9002_PAI（明细屏，过账）**：

```abap
WHEN 'BACK'.                              " 取消：清实盘数量，导航交给弹栈
  CLEAR cs_zdifhu_prod-quan_count.

WHEN OTHERS.                              " ENTER
  " 1. 实盘必须 > 0（空 / 0 / 负数都拒绝）；2. 差异 = 当前 − 实盘（⚠️ 符号见下）
  IF cs_zdifhu_prod-quan_count <= 0.
    MESSAGE e010(zewm_rf_msg).
  ENDIF.
  lv_diff = cs_zdifhu_prod-quan - cs_zdifhu_prod-quan_count.
  IF lv_diff = 0.
    MESSAGE e011(zewm_rf_msg).
  ENDIF.

  " 3. 过账（实例方法，必须先 CREATE OBJECT）
  ls_quan-quan = lv_diff.  ls_quan-unit = cs_zdifhu_prod-meins.
  CREATE OBJECT go_packing.
  CALL METHOD go_packing->post_difference
    EXPORTING iv_guid_hu = cs_zdifhu_prod-guid_hu  iv_guid_stock = cs_zdifhu_prod-guid_stock
              is_quan = ls_quan  iv_exccode = 'DIFD'  iv_buscon = 'PPT'  iv_exec_step = '16'
    EXCEPTIONS error = 1 OTHERS = 2.

  " 4. 落库：save 不带 commit，外层显式 COMMIT；失败 ROLLBACK + cleanup
  go_packing->save( iv_commit = space iv_wait = space ).
  COMMIT WORK AND WAIT.  /scwm/cl_tm=>cleanup( ).

  " 5. 刷新列表该行当前数量（重读 HU）+ 清输入 + UPDBCK 回列表（同步调用栈）
  PERFORM refresh_item USING lv_lgnum cs_zdifhu_s_scr-huident ls_item-guid_stock CHANGING ls_item.
  MODIFY ct_zdifhu_t_items FROM ls_item INDEX lv_tabix.
  CLEAR cs_zdifhu_prod-quan_count.  CLEAR cs_zdifhu_s_scr-selno.
  set_prmod('1').  set_fcode('UPDBCK').
```

> **过账符号（踩过的坑）**：`post_difference` 的 `is_quan-quan` **正数 = 发货（库存减少）、
> 负数 = 收货（库存增加）**（内部按正负选 `wmegc_lime_post_outbound` /
> `wmegc_lime_post_inbound`）。所以要传 **`当前 − 实盘`**：盘亏（实盘 < 当前）为正 → 减库存；
> 盘盈为负 → 加库存。写成 `实盘 − 当前` 会把盘亏当收货，库存不减反增。

### 3.4 LGNUM 获取

- **FM 接口不能声明 `IMPORTING` 字段参数**：RF 框架调 content provider FM 时只按名传
  CHANGING 参数表（见 `/SCWM/IRF_SSCR` 的 `CALL_FLOW_PROCESS` → `CALL FUNCTION ... PARAMETER-TABLE`）。
  原设计的 `IMPORTING iv_lgnum` 运行时抛 `CALL_FUNCTION_PARM_MISSING`
  （`CX_SY_DYN_CALL_PARAM_MISSING`）。
- 正确做法：FM 内自己取 —— `DATA(lv_lgnum) = /scwm/cl_rf_bll_srvc=>get_lgnum( ).`，
  再 `/scwm/cl_tm=>set_lgnum( lv_lgnum ).` 初始化全局上下文（packing 类需要）。

### 3.5 列表导航 / 翻页

- 列表屏用**序号选择**（照搬标准 `/SCWM/RF_XDIFHU` 模式）：顶部 `SELNO` 输入框 → ENTER →
  `9001_PAI` 校验（空序号 / 序号超行数 / 序号不存在，均 MESSAGE 并留屏）→ 命中后填明细结构
  → `set_prmod('1') + set_fcode('...')` 进入明细步（列表→明细两步，不做行内编辑）。
- 列表超一屏的翻页由框架预定义 fcode **PGUP/PGDN** 自动处理（模板 pushbutton），
  **不需要**自定义 `DOWN` 行、也不需要手动维护起始行变量。

### 3.6 消息类与多语言（abapGit LXE）

- **消息类 `ZEWM_RF_MSG`**（`src/zewm_rf_msg.msag.xml`）集中管理全部报错消息，FM 里一律用
  `MESSAGE eNNN(zewm_rf_msg)`（如 `MESSAGE e001(zewm_rf_msg)`），不再用文本符号写法
  `MESSAGE e001(00) WITH '...'(nnn)`。消息号：001 HU 未输入 / 002 HU 查不到 / 003 HU 无物料 /
  006 过账失败 / 007 保存失败 / 008 序号未输入 / 009 序号不存在 / 010 实盘 ≤ 0 / 011 实盘 = 当前。
- **翻译（DE / CS / FR / ZH）走 abapGit 的 LXE 机制**：每个语言一个 gettext PO 文件
  （`zfg_rf_zdifhu.fugr.i18n.<语言>.po` 放屏幕文本、`zewm_rf_msg.msag.i18n.<语言>.po` 放消息文本），
  仓库根 `.abapgit.xml` 里声明 `<I18N_LANGUAGES>`（CS/DE/FR/ZH）+ `<USE_LXE>X</USE_LXE>`。
  Pull 时 abapGit 按 **英文源文本** 匹配 PO 的 `msgid`，把 `msgstr` 通过
  `LXE_OBJ_TEXT_PAIR_WRITE` 写回系统 —— **不需要任何 SE63 操作**（已实测中文生效）。
- 注意：源文本必须与系统里的英文原文完全一致（大小写 / 尾部空格），否则该条静默跳过；
  屏幕标签不能超过字段宽度（`HU`=2 / `No.`=3 / `HU:`=3 / `Actual Qty`=10）。

## 4. 屏幕布局

```
┌─ 屏幕 9000（HU 输入）──┐   ┌─ 屏幕 9001（物料列表）────────────┐
│ HU: [______________]   │   │ No. [___]                         │
└────────────────────────┘   │ HU: xxxxxxxxxxxxxxxxxxxx          │
                             │ ┌───────────────────────────────┐ │
                             │ │ 1 MAT001                      │ │
                             │ │   Material description        │ │
                             │ │   96 PC                       │ │
                             │ └───────────────────────────────┘ │
                             └───────────────────────────────────┘
                                 （一屏 1 个物料块，每物料 3 行；PGUP/PGDN 翻页）

┌─ 屏幕 9002（明细 + 实盘录入）──────────────┐
│ MAT001                                     │
│ Material description                       │
│ 96 PC                                      │
│ Actual Qty                                 │
│ [__________] PC   ← 唯一可输入框           │
└────────────────────────────────────────────┘

┌─ 屏幕 9004（HU 抬头明细，从屏幕 2 的 HUINFO 按钮进入）───────────┐
│ 标准屏 /SCWM/SAPLRF_INQUIRY_PM 0202 的克隆：13 行 × 27 列、38 字段 │
│ HU 号 / HU 类型 / 包装物料 / 毛重·净重 / 毛体积·净体积 / 长×宽×高 / │
│ 库位 / 存储类型 / 危险品标识 / 顶·底标识 / 物理状态 …              │
│ （全部只读；F7 = BACK 返回列表）                                  │
└──────────────────────────────────────────────────────────────────┘
```

## 5. 风险与待确认

1. ~~**`POST_DIFFERENCE` 签名**~~ **已确认并跑通**：**实例方法**（`CREATE OBJECT go_packing.` +
   `go_packing->post_difference`），参数 `iv_guid_hu / iv_guid_stock / is_quan(差异数量+单位) /
   iv_exccode / iv_buscon / iv_exec_step`，EXCEPTIONS `error`。调用后须 `save( )` +
   `COMMIT WORK AND WAIT` 落库，结尾 `/scwm/cl_tm=>cleanup( )`。**`is_quan-quan` 的符号见 §3.3。**
2. **异常码**：签名要求显式传入三件套（EXCCODE/BUSCON/EXEC_STEP）。样本代码用 `DIFD/PPT/16`；
   标准 RF "Post HU Differences" 用 `DIFW/TIM/A2`（SAP Note 3601355）。
   **部署前在 SPRO Exception Codes 配置中确认所选组合存在**，二选一或按客户习惯。
3. **批次**：同物料多批次按 guid_stock 分行显示，过账按 guid_stock 精确定位。
4. **嵌套包装**：不支持（只显示直接项目）。如需后续支持，按 et_hutree 递归展开（本次不做）。
5. ~~**FM 接口匹配规则**~~ **已确认**：框架按 **CHANGING 参数名 = Application Parameter 名**
   匹配，`set_scr_tabname` 也传参数名（与标准 `/SCWM/RF_XDIFHU_*` 一致）；**不能有 IMPORTING
   字段参数**。漏配 `/SCWM/TPARAM_CAT` 行会在运行时 `CALL_FUNCTION_PARM_MISSING`。

## 6. 验收标准

- [ ] `/SCWM/RFUI` → 菜单/测试环境调用 `ZDIFHU`，屏幕 1 显示 HU 输入框
- [ ] 输入存在的 HU → ENTER → 屏幕 2 显示该 HU 物料列表（序号 + 物料号/描述/数量/单位，每物料 3 行）
- [ ] 屏幕 2 输入不存在的序号 → 报错 "Item does not exist"（防呆生效）
- [ ] 输入存在的序号 → ENTER → 屏幕 3 显示该物料（物料号/描述/当前数量/单位）
- [ ] 屏幕 3 输入实盘数量 → ENTER → 过账成功、回到列表（当前数量已刷新、序号已清空）
- [ ] 屏幕 3 输入 0 / 负数 / 留空 → 报错 "Counted quantity must be greater than zero"，不过账
- [ ] 屏幕 3 按 BACK → 回列表；屏幕 2 按 BACK → 回屏幕 1；屏幕 1 按 BACK → 结束事务
- [ ] 列表超 1 个物料 → 翻页（PGUP/PGDN）正常
- [ ] 屏幕 2 按 **HUINFO** 按钮（PB1/F1）→ 屏幕 4 显示 HU 抬头数据；`BACK`(F7) 返回列表
- [ ] 差异 = 当前 − 实盘（盘亏为正 → 减库存），过账后 `/SCWM/MON` 库存正确
- [ ] 用 DE / CS / FR / ZH 登录 → 屏幕标签与报错消息为译文
