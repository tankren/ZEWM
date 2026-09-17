# ZDIFHU — EWM RF HU 差异过账

[English](README.md) | **中文**

> **状态**：已在 S/4HANA embedded EWM（client 100）端到端实测通过 —— 三步流程 + HU 明细屏（9004，从列表屏
> 的 HUINFO 按钮进入）、过账（盘盈/盘亏两个方向）、BACK 返回链路、输入框属性、DE/CS/FR/ZH 多语言均在系统里
> 验证过。交付：abapGit 仓库 `tankren/ZEWM` 的 `zdifhu/` 子目录（30 个文件）。验收清单见 §4。

RF 逻辑事务 `ZDIFHU`，三步四屏（屏幕 9004 是 HU 明细，从屏幕 2 的 **HUINFO** 按钮进入）：

1. **屏幕 1（9000）**：输/扫 HU 号 → ENTER
2. **屏幕 2（9001）**：显示该 HU 内所有物料（**序号 + 物料号 / 描述 / 数量 + 单位**，
   每个物料占三行）；顶部有**序号输入框**，输入序号 → ENTER
3. **屏幕 3（9002）**：显示选中物料的物料号/描述/当前数量/单位 + **实盘数量输入框**，
   输入实盘数量 → ENTER 立即过账差异（**差异 = 当前 − 实盘**，符号约定见 §4），随后回到列表并刷新数量
   （序号自动清空）
4. **屏幕 4（9004）**：在屏幕 2 按 **HUINFO** 按钮（PB1 / F1）→ 显示 HU 抬头数据（HU 号、HU 类型、
   包装物料、毛重/净重、毛体积/净体积、长宽高、库位等）；`BACK`（F7）返回列表。该屏幕是**标准 HU 明细屏**
   `/SCWM/SAPLRF_INQUIRY_PM` **0202** 的克隆（13 × 27），数据容器复用**标准结构** `/SCWM/S_RF_INQ_HU`
   —— **没有新增 DDIC 对象**

过账 API：`/SCWM/CL_WM_PACKING->POST_DIFFERENCE`（实例方法）。

## 1. 安装（abapGit）

1. abapGit → New Offline（或 New Online 推送到内部 Git）→ 导入本仓库 zip
2. 包：`ZEWM_RFUI`（abapGit 创建 repo 时填的 Package）
3. Pull → 激活全部对象（先 DDIC：`ZEWM_ZDIFHU_SCR_1S` → `ZEWM_ZDIFHU_ITEM_1S` → `ZEWM_ZDIFHU_ITEM_1TT`
   → `ZEWM_ZDIFHU_PROD_1S`，再函数组 `ZEWM_RF_ZDIFHU` 整体激活）
4. 激活后核对（SE11）：`/SCWM/DE_HUIDENT`、`/SCWM/DE_RF_SEQNO`、`/SCWM/DE_QUANTITY`、
   `/SCWM/DE_BASE_UOM`、`/SCWM/GUID_HU`、`/LIME/GUID_STOCK` 存在；若某个不存在导致
   `ZSDIFHU*` 激活报错，SE11 把对应字段从数据元素引用改为内建类型：
   HUIDENT→CHAR 20；SEQNO→NUMC 3；QUAN/QUAN_COUNT→QUAN 长 13 小数 3；
   MEINS→UNIT 3；GUID_*→CHAR 32
5. **多语言（DE / CS / FR / ZH）**：翻译以 abapGit LXE 文件（`*.i18n.<语言>.po`）交付，**Pull 时自动
   写回系统，不需要做任何 SE63**。语言列表已写在仓库的 `.abapgit.xml` 里（`<I18N_LANGUAGES>` +
   `<USE_LXE>`）；若译文没生效，检查 abapGit 仓库设置 → *Serialize Translations (experimental LXE
   approach)*，语言填 `DE,CS,FR,ZH`
6. **所有报错消息**来自消息类 `ZEWM_MSG_RF`（`src/zewm_msg_rf.msag.xml`，Pull 时一起导入，无需单独激活）

## 2. Customizing（SPRO → EWM → Mobile Data Entry → RF Framework，按顺序）

1. **Define Application Parameters**（`/SCWM/TPARAM_CAT`，视图 `/SCWM/RF_CUSTOM`，SM30）：
   - APPLIC=`01`（WME） / `CS_ZDIFHU_S_SCR` / Parameter Type=`ZEWM_ZDIFHU_SCR_1S`
   - APPLIC=`01`（WME） / `CS_ZDIFHU_PROD` / Parameter Type=`ZEWM_ZDIFHU_PROD_1S`
   - APPLIC=`01`（WME） / `CT_ZDIFHU_T_ITEMS` / Parameter Type=`ZEWM_ZDIFHU_ITEM_1TT`
   - APPLIC=`01`（WME） / `CS_ZDIFHU_HU` / Parameter Type=`/SCWM/S_RF_INQ_HU`
     （HU 明细屏 9004 用——复用**标准结构**，不需要建 Z 对象）
   （PARAM_NAME 必须与 FM 的 CHANGING 参数名**完全一致**，带 CS_/CT_ 前缀）
2. **Define Steps in Logical Transaction**：`ZDIFHU` → `ZDIF1`、`ZDIF2`、`ZDIF3`、`ZDIF4`
3. **Define Step Flow**（`/SCWM/TSTEP_FLOW`）：

   | LTRANS | STEP | FCODE | FMODUL | SSTEP | PRMOD | FCODE_BCKG |
   |---|---|---|---|---|---|---|
   | ZDIFHU | ZDIF1 | INIT | ZEWM_RF_ZDIFHU_9000_PBO | ZDIF1 | 2 | |
   | ZDIFHU | ZDIF1 | ENTER | ZEWM_RF_ZDIFHU_9000_PAI | ZDIF2 | 1 | INIT |
   | ZDIFHU | ZDIF1 | BACK | ZEWM_RF_ZDIFHU_9000_PAI | ZDIF1 | 2 | |
   | ZDIFHU | ZDIF2 | INIT | ZEWM_RF_ZDIFHU_9001_PBO | ZDIF2 | 2 | |
   | ZDIFHU | ZDIF2 | ENTER | ZEWM_RF_ZDIFHU_9001_PAI | ZDIF3 | 1 | INIT |
   | ZDIFHU | ZDIF2 | BACK | ZEWM_RF_ZDIFHU_9001_PAI | ZDIF1 | 1 | INIT |
   | ZDIFHU | ZDIF2 | HUINFO | ZEWM_RF_ZDIFHU_9001_PAI | ZDIF4 | 1 | INIT |
   | ZDIFHU | ZDIF3 | INIT | ZEWM_RF_ZDIFHU_9002_PBO | ZDIF3 | 2 | |
   | ZDIFHU | ZDIF3 | ENTER | ZEWM_RF_ZDIFHU_9002_PAI | ZDIF3 | 0 | |
   | ZDIFHU | ZDIF3 | BACK | ZEWM_RF_ZDIFHU_9002_PAI | ZDIF2 | 1 | INIT |
   | ZDIFHU | ZDIF4 | INIT | ZEWM_RF_ZDIFHU_9004_PBO | ZDIF4 | 2 | |
   | ZDIFHU | ZDIF4 | BACK | ZEWM_RF_ZDIFHU_9004_PAI | ZDIF2 | 1 | INIT |

   > **规则 A —— 跳步（踩过的坑）**：**凡是「A 步 → B 步」的跳转行，必须 `PRMOD=1` 且
   > `FCODE_BCKG` 填目标步 PBO 的触发码（这里是 `INIT`）**；`PRMOD=2` 只能用于
   > **同一步骤重显示**（如 INIT → 本步 PBO）。填错会让目标步的 PBO 模块根本不被调用
   > → 表数据容器没注册 → 屏幕 2 报 `GETWA_NOT_ASSIGNED` dump（`LRF_SSCRO02` 第 50 行
   > `READ TABLE <gt_scr>`）。
   >
   > **规则 B —— 过账后返回（踩过的坑）**：明细屏（ZDIF3）的 `ENTER` 行**不能换步**
   > （`SSTEP` 填**本步 ZDIF3**、`PRMOD=0`），返回由 `9002_PAI` 结尾的
   > `set_prmod('1') + set_fcode('UPDBCK')` 完成 —— 框架的 `UPDBCK` = **回上一步 +
   > 同步内部调用栈 + 刷新目标步 PBO**。若这一行自己换步（`SSTEP=ZDIF2, PRMOD=1`），
   > 框架只做普通导航、调用栈里仍留着 ZDIF3，之后在列表屏按 `BACK` 会被弹回明细屏。
   >
   > **关于 `BACK`**：框架的 `BACK` 是**弹内部调用栈**（`ZDIF2/BACK` 这类行的 `SSTEP`
   > 实际被忽略）。保留这些行只是为了 `BACK` 也能触发对应屏幕的 PAI（清输入框等）。
   > 「回上一屏」永远靠 `UPDBCK` / 弹栈，不靠 step flow 行。
   - ZDIF1/BACK 行：9000_PAI 内部 `set_fcode(c_fcode_compl_ltrans)` 结束事务
     （默认导航表 `/SCWM/TTRNS_NAV`）——**事务退出只在第一屏做**
   - 翻页（列表超一屏）由框架预定义 fcode **PGUP/PGDN** 自动处理，**不需**自定义 DOWN 行
4. **Define Function Code Profile**（`/SCWM/TFCOD_PRF`）：三个工作步的 INIT / ENTER / BACK（及 CLEAR），
   再加 **`ZDIF2` 的 `HUINFO`（`PUSHB=PB1`，或 `FNKEY=F1` + `SHORTCUT=01`）** 才能在列表屏看到按钮，
   `ZDIF4` 加 BACK。`HUINFO` 本身必须在 `/SCWM/TFCOD_CAT`（APPLIC=`01`）里存在
   （翻页 PGUP/PGDN 是框架预定义 fcode，通过模板 pushbutton 自动可用）
5. **Map Logical Transaction Step to Subscreen**：
   - `ZDIFHU`/`ZDIF1` → `SAPLZEWM_RF_ZDIFHU` `9000`
   - `ZDIFHU`/`ZDIF2` → `SAPLZEWM_RF_ZDIFHU` `9001`
   - `ZDIFHU`/`ZDIF3` → `SAPLZEWM_RF_ZDIFHU` `9002`
   - `ZDIFHU`/`ZDIF4` → `SAPLZEWM_RF_ZDIFHU` `9004`
6. **Presentation / Personalization Profile**：复用现有 `**` 或按需新建
7. **RF Menu Manager**：菜单挂载（测试期可用 RF Test Environment 直调）
8. **Exception Codes**（SPRO → EWM → Cross-Process Settings → Exception Codes）：
   确认 `DIFD` + 业务上下文 `PPT` + 执行步骤 `16` 存在；不存在则维护或改代码
   （`zewm_rf_zdifhu_9002_pai.abap` 中 `iv_exccode/iv_buscon/iv_exec_step` 三处常量）

## 3. Plan B：屏幕 9001 / 9002 手工重建（仅当 import 屏幕报错时）

abapGit import 若报 `RPY_DYNPRO_INSERT` 错误（step-loop XML 兼容性），
删除 fugr.xml 中对应屏幕的 `<item>` 重新 import，然后 SE51 手建：

**屏幕 9001（列表）**：子屏幕，7 行 × 40 列

- 行 1：文本 `No.`（列 1，长 3）+ `ZEWM_ZDIFHU_SCR_1S-SELNO`（列 5，**可输入**，NUMC，长 3 ——
  序号框故意只给 3 位，不占满整行）
- 行 2：文本 `HU:`（列 1，长 3）+ `ZEWM_ZDIFHU_SCR_1S-HUIDENT`（列 5，只显，长 22）
- 行 3 起：框选 5 个 DDIC 字段做 Step Loop，**每行块 3 行**（`LOOP_BLOCK=3`、
  `LOOP_DISP=1`、`HEIGHT=3`；一个物料占 3 行，一屏显示 1 个完整物料）：
  - 行块第 1 行：`ZEWM_ZDIFHU_ITEM_1S-SEQNO`（列 1，只显，长 3）、`ZEWM_ZDIFHU_ITEM_1S-MATNR`（列 5，只显，长 22）
  - 行块第 2 行：`ZEWM_ZDIFHU_ITEM_1S-MAKTX`（列 1，只显，长 26）
  - 行块第 3 行：`ZEWM_ZDIFHU_ITEM_1S-QUAN`（列 5，只显，长 18）、`ZEWM_ZDIFHU_ITEM_1S-MEINS`（列 24，只显，长 3）
- 只读字段**只用 `OUTPUT_FLD=X`** —— **不要加 `OUTPUTONLY`**：加了就变成平面文字，不是标准那种
  带边框的只读框（SAP 标准 RF 屏幕里 `OUTPUTONLY` 用了 0 次）；
  **可输入字段只用 `INPUT_FLD=X + OUTPUT_FLD=X`，绝不能带 `REQU_ENTRY`**（见 §5 第 8 条）
- 同一个 dynpro 屏幕**不允许两个同名字段** —— 两处都要显示单位时用两个 DDIC 字段（`MEINS` + `MEINS_DSP`）
- 多行行块必须满足 **`HEIGHT = LOOP_BLOCK × LOOP_DISP`**（标准程序全部如此，
  如 `/SCWM/RF_INQUIRY_PM` 屏 0204：`LOOP_BLOCK=4 × LOOP_DISP=2 = HEIGHT=8`）
- Flow logic（与 `src/zewm_rf_zdifhu.fugr.screen_9001.abap` 相同）：

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

**屏幕 9002（明细）**：子屏幕，7 行 × 40 列

- 行 1：`ZEWM_ZDIFHU_PROD_1S-MATNR`（列 1，只显，无标签，长 26）
- 行 2：`ZEWM_ZDIFHU_PROD_1S-MAKTX`（列 1，只显，无标签，长 26）
- 行 3：`ZEWM_ZDIFHU_PROD_1S-QUAN`（列 1，只显，长 22）+ `ZEWM_ZDIFHU_PROD_1S-MEINS`（列 24，只显，长 3）
- 行 4：文本 `Actual Qty`（列 1，长 26 —— 屏上唯一保留的标签）
- 行 5：`ZEWM_ZDIFHU_PROD_1S-QUAN_COUNT`（列 1，**可输入**，长 22）+ `ZEWM_ZDIFHU_PROD_1S-MEINS_DSP`（列 24，只显，长 3）
  （`MEINS_DSP` 是结构里专供显示的第二个单位字段——同一个 dynpro 屏幕**不允许两个同名字段**；
  标准 RF 屏幕里看到的同名都是「TEXT 标签字段 + TEMPLATE 字段」的组合，从来不是两个 TEMPLATE）
- Flow logic（与 `src/zewm_rf_zdifhu.fugr.screen_9002.abap` 相同）：

  ```abap
  PROCESS BEFORE OUTPUT.
    MODULE STATUS_SSCR.
  *
  PROCESS AFTER INPUT.
    MODULE USER_COMMAND_SSCR.
  ```

**屏幕 9004（HU 明细）**：直接复制标准屏幕 `/SCWM/SAPLRF_INQUIRY_PM` 的 **0202**（13 行 × 27 列、38 个字段
—— 每个属性一个 `TEXT` 标签字段 + 一个 `TEMPLATE` 字段，标准屏本身就是这种同名组合），只改程序名/屏号
（`SAPLZEWM_RF_ZDIFHU` / `9004`）。数据容器复用**标准结构** `/SCWM/S_RF_INQ_HU`，所以 TOP include 要有
`TABLES /scwm/s_rf_inq_hu.`，容器 `CS_ZDIFHU_HU` 由 `9001_PAI` 的 `HUINFO` 分支填好。Flow logic：

  ```abap
  PROCESS BEFORE OUTPUT.
    MODULE STATUS_SSCR.
  *
  PROCESS AFTER INPUT.
    MODULE USER_COMMAND_SSCR.
  ```

激活。

## 4. 验收清单

- [ ] `/SCWM/RFUI`（或 RF Test Environment）调用 `ZDIFHU`，屏幕 1 显示 HU 输入框
- [ ] 输入存在的 HU → ENTER → 屏幕 2 显示物料列表（**序号 + 物料号/描述分行 + 数量 + 单位**）
- [ ] 屏幕 2 输入不存在的序号 → 报错 "Item does not exist"（防呆生效）
- [ ] 输入存在的序号 → ENTER → 屏幕 3 显示该物料（物料号/描述/当前数量/单位）
- [ ] 屏幕 3 输入实盘数量 → ENTER → 过账成功，回到列表（当前数量已刷新、序号已清空）
- [ ] 屏幕 3 输入 0 / 负数 / 留空 → 报错 "Counted quantity must be greater than zero"，不过账
- [ ] 屏幕 3 输入与当前相同的数量 → 报错 "Counted quantity equals current quantity"，不过账
- [ ] 屏幕 3 按 BACK → 回列表；屏幕 2 按 BACK → 回屏幕 1；屏幕 1 按 BACK → 结束事务回菜单
  （屏幕 2 的 BACK 只有在 step flow 的 `ZDIF3/ENTER` 行填 `SSTEP=ZDIF3 + PRMOD=0` 时才正确）
- [ ] 差异 = 当前 − 实盘（盘亏为正 → 减库存，盘盈为负 → 加库存）；过账后 `/SCWM/MON` 库存正确
- [ ] 列表超 1 个物料 → 翻页（PGUP/PGDN）正常（一屏 1 个物料，每个物料 3 行）
- [ ] 屏幕 2 按 **HUINFO** 按钮（PB1/F1）→ 屏幕 4 显示 HU 抬头数据（HU 类型/包装物料/重量体积/长宽高/库位）；
      `BACK`（F7）返回列表
- [ ] 用语言 DE / CS / FR / ZH 登录 → 屏幕标签（`HU`、`No.`、`HU:`、`Actual Qty`）与报错消息均为译文

> **过账符号约定（实现细节，改代码时别弄反）**：`/SCWM/CL_WM_PACKING->POST_DIFFERENCE`
> 的 `is_quan-quan` **正数 = 发货（库存减少）、负数 = 收货（库存增加）**
> （内部按正负取 `wmegc_lime_post_outbound` / `wmegc_lime_post_inbound`）。
> 因此 `9002_PAI` 传的是 **`当前数量 − 实盘数量`**：盘亏（实盘 < 当前）为正 → 减库存；
> 盘盈（实盘 > 当前）为负 → 加库存。

## 5. 故障排查（Pull 后跑不起来/报错，按顺序查）

1. **屏幕 2 列表空白 / `GETWA_NOT_ASSIGNED` dump（`LRF_SSCRO02` 第 50 行 `<gt_scr>` 未分配）**：
   **查 `/SCWM/TSTEP_FLOW` 的跨步骤跳转行是否 `PRMOD=1` + `FCODE_BCKG=INIT`**。
   若某步的 PBO 模块从未被执行（可查 ST22 dump 里 `ST_SCR_PARAM` 只有上一步注册的值），
   就是这里填错——`PRMOD=2` 表示「同步骤重显示」，不会触发目标步的 PBO。

2. **激活报语法错误**（`... is not a key field` 或 `method ... not found`）：
   SE24 查 `/SCWM/CL_RF_BLL_SRVC`，确认 `GET_FCODE` / `SET_FCODE` / `SET_PRMOD` /
   `SET_LINE` / `SET_FIELD` / `SET_SCR_TABNAME` / `INIT_SCREEN_PARAM` / `SET_SCREEN_PARAM`
   均为静态方法、签名匹配；不符则按系统内标准 `/SCWM/RF_*` FM 校准写法。

3. **运行时 dump**（DYNPRO/RF 调用链 short dump）：标准 RF 框架会捕获 E 型消息
   显示在屏底，不应 dump。所有报错消息都来自消息类 `ZEWM_MSG_RF`
   （`MESSAGE eNNN(zewm_msg_rf)`，如 `MESSAGE e001(zewm_msg_rf)`）；新增消息时要同时写进
   `src/zewm_msg_rf.msag.xml` **和**四个 `zewm_msg_rf.msag.i18n.<语言>.po`。

4. **import 屏幕报 `RPY_DYNPRO_INSERT`**：走上文 §3 Plan B。

5. **激活报数据元素不存在**：走 §1 第 4 步改内建类型。

6. **过账报异常码错**：走 §2 第 8 步确认 `DIFD/PPT/16`。

7. **列表空白 / 数据传不进**：核对 §2 第 1 步 PARAM_NAME 是否与 FM CHANGING 参数名
   完全一致（`CS_ZDIFHU_S_SCR` / `CS_ZDIFHU_PROD` / `CT_ZDIFHU_T_ITEMS`）。

8. **输入框输不进去（数量框 / 序号框）**：查该屏幕字段的 XML 里是否带了
   `<REQU_ENTRY>N</REQU_ENTRY>` —— **标准 RF 的输入字段从不带 `REQU_ENTRY`**
   （对照 `/SCWM/RF_INQUIRY_PM`：`INPUT_FLD=X` 的字段 36 个、`REQU_ENTRY=N` 的字段
   356 个，**两者交集为 0**）。带 `REQU_ENTRY=N` 会让字段在 RF 里变成不可输入。
   修复：删掉该 `<REQU_ENTRY>` 元素，并在该屏 PBO 里显式打开输入属性
   （`/scwm/cl_rf_bll_srvc=>set_screlm_input_on( 'ZEWM_ZDIFHU_PROD_1S-QUAN_COUNT' )`，
   见 `zewm_rf_zdifhu_9001_pbo.abap` / `_9002_pbo.abap`）。

9. **按 ENTER 直接 dump `CALL_FUNCTION_PARM_MISSING`（`CX_SY_DYN_CALL_PARAM_MISSING`，
   提示缺 `CS_ZDIFHU_PROD` / `CS_ZDIFHU_HU` 之类的参数）**：不是代码问题，是 `/SCWM/TPARAM_CAT`
   （视图 `/SCWM/RF_CUSTOM`）**少了对应的数据容器行** → 框架拼不出参数表、在调 FM 之前
   就报错（FM 函数体根本没执行）。核对 §2 第 1 步的 **4 行**是否都在 —— dump 里报的参数名就是缺的那一行。

10. **在列表屏按 BACK 又回到明细屏**：`/SCWM/TSTEP_FLOW` 里 `ZDIF3/ENTER` 行填成了
    `SSTEP=ZDIF2 + PRMOD=1`。改成 **`SSTEP=ZDIF3 + PRMOD=0`**（见 §2 第 3 步规则 B）。

11. **译文不生效（DE/CS/FR/ZH）**：LXE 的 PO 文件是**按英文源文本匹配**的 —— 若系统里的英文原文
    与 PO 里的不完全一致（大小写、尾部空格），该条会被静默跳过；标签比字段宽度长会被截断。
    另检查仓库设置：*Serialize Translations (experimental LXE approach)* 要勾上、语言填
    `DE,CS,FR,ZH`（仓库 `.abapgit.xml` 里已经带了）。标签字段宽度：`HU`=2（屏 9000）、
    `No.`=3、`HU:`=3（屏 9001）、`Actual Qty`=10（屏 9002）。

12. **列表屏看不到 HUINFO 按钮**：需要 function code profile 行 —— `/SCWM/TFCOD_PRF`，
    `APPLIC=01` / `LTRANS=ZDIFHU` / `STEP=ZDIF2` / `FCODE=HUINFO`，`PUSHB=PB1`（或 `FNKEY=F1`），
    且 `HUINFO` 要在 `/SCWM/TFCOD_CAT`（APPLIC=`01`）里存在（见 §2 第 4 步）。

13. **HUINFO 跳到标准 HU 屏幕（或 dump）**：`/SCWM/TSTEP_SCR` 里 `ZDIF4` 指向的是标准程序
    `/SCWM/SAPLRF_INQUIRY_PM` 的屏幕 `202`。把 `ZDIF4` 的两行改成 `SAPLZEWM_RF_ZDIFHU` / `9004`
    （见 §2 第 5 步）。

## 6. 对象清单

| 对象 | 名称 | 说明 |
|---|---|---|
| 包 | ZEWM_RFUI | |
| Function Group | ZEWM_RF_ZDIFHU | 屏幕 9000/9001/9002/9004 + 8 FM（含 INCLUDE /SCWM/IRF_SSCR） |
| 结构 | ZEWM_ZDIFHU_SCR_1S | 屏幕单值（HUIDENT + SELNO 序号输入） |
| 结构 | ZEWM_ZDIFHU_ITEM_1S | 列表行（SEQNO + MATNR + MAKTX + QUAN + MEINS + GUID_*） |
| 结构 | ZEWM_ZDIFHU_PROD_1S | 明细屏（SEQNO + MATNR + MAKTX + QUAN 当前 + MEINS + QUAN_COUNT 实盘 + MEINS_DSP + GUID_*） |
| 表类型 | ZEWM_ZDIFHU_ITEM_1TT | 列表内表 |
| App. Parameter | CS_ZDIFHU_S_SCR / CS_ZDIFHU_PROD / CT_ZDIFHU_T_ITEMS / CS_ZDIFHU_HU | 全局数据容器（Customizing）；`CS_ZDIFHU_HU` 指向**标准结构** `/SCWM/S_RF_INQ_HU`，供 HU 明细屏 9004 使用 |
| 消息类 | ZEWM_MSG_RF | 8 个 FM 的全部报错消息（`MESSAGE eNNN(zewm_msg_rf)`，001–011） |
| 翻译 | `zewm_rf_zdifhu.fugr.i18n.<语言>.po` + `zewm_msg_rf.msag.i18n.<语言>.po` | DE / CS / FR / ZH：7 条屏幕文本 + 9 条消息，由 abapGit LXE 写回系统 |
