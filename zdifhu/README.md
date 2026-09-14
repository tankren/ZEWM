# ZDIFHU — EWM RF HU 差异过账

RF 逻辑事务 `ZDIFHU`，三步两屏：

1. **屏幕 1（9000）**：输/扫 HU 号 → ENTER
2. **屏幕 2（9001）**：显示该 HU 内所有物料（**序号 + 物料号 / 描述 + 数量 + 单位**，
   每个物料占两行）；顶部有**序号输入框**，输入序号 → ENTER
3. **屏幕 3（9002）**：显示选中物料的物料号/描述/当前数量/单位 + **实盘数量输入框**，
   输入实盘数量 → ENTER 立即过账差异（实盘 − 当前），随后回到列表并刷新数量

过账 API：`/SCWM/CL_WM_PACKING->POST_DIFFERENCE`（实例方法）。

## 1. 安装（abapGit）

1. abapGit → New Offline（或 New Online 推送到内部 Git）→ 导入本仓库 zip
2. 包：`ZEWM`（abapGit 创建 repo 时填的 Package）
3. Pull → 激活全部对象（先 DDIC：`ZSDIFHU_SCR` → `ZSDIFHU_ITEM` → `ZSDIFHU_ITEM_TT`
   → `ZSDIFHU_PROD`，再函数组 `ZFG_RF_ZDIFHU` 整体激活）
4. 激活后核对（SE11）：`/SCWM/DE_HUIDENT`、`/SCWM/DE_RF_SEQNO`、`/SCWM/DE_QUANTITY`、
   `/SCWM/DE_BASE_UOM`、`/SCWM/GUID_HU`、`/LIME/GUID_STOCK` 存在；若某个不存在导致
   `ZSDIFHU*` 激活报错，SE11 把对应字段从数据元素引用改为内建类型：
   HUIDENT→CHAR 20；SEQNO→NUMC 3；QUAN/QUAN_COUNT→QUAN 长 13 小数 3；
   MEINS→UNIT 3；GUID_*→CHAR 32

## 2. Customizing（SPRO → EWM → Mobile Data Entry → RF Framework，按顺序）

1. **Define Application Parameters**（`/SCWM/TPARAM_CAT`，视图 `/SCWM/RF_CUSTOM`，SM30）：
   - APPLIC=`01`（WME） / `CS_ZDIFHU_S_SCR` / Parameter Type=`ZSDIFHU_SCR`
   - APPLIC=`01`（WME） / `CS_ZDIFHU_PROD` / Parameter Type=`ZSDIFHU_PROD`
   - APPLIC=`01`（WME） / `CT_ZDIFHU_T_ITEMS` / Parameter Type=`ZSDIFHU_ITEM_TT`
   （PARAM_NAME 必须与 FM 的 CHANGING 参数名**完全一致**，带 CS_/CT_ 前缀）
2. **Define Steps in Logical Transaction**：`ZDIFHU` → `ZDIF1`、`ZDIF2`、`ZDIF3`
3. **Define Step Flow**（`/SCWM/TSTEP_FLOW`）：

   | LTRANS | STEP | FCODE | FMODUL | SSTEP | PRMOD | FCODE_BCKG |
   |---|---|---|---|---|---|---|
   | ZDIFHU | ZDIF1 | INIT | Z_RF_ZDIFHU_9000_PBO | ZDIF1 | 2 | |
   | ZDIFHU | ZDIF1 | ENTER | Z_RF_ZDIFHU_9000_PAI | ZDIF2 | 1 | INIT |
   | ZDIFHU | ZDIF1 | BACK | Z_RF_ZDIFHU_9000_PAI | ZDIF1 | 2 | |
   | ZDIFHU | ZDIF2 | INIT | Z_RF_ZDIFHU_9001_PBO | ZDIF2 | 2 | |
   | ZDIFHU | ZDIF2 | ENTER | Z_RF_ZDIFHU_9001_PAI | ZDIF3 | 1 | INIT |
   | ZDIFHU | ZDIF2 | BACK | Z_RF_ZDIFHU_9001_PAI | ZDIF1 | 1 | INIT |
   | ZDIFHU | ZDIF3 | INIT | Z_RF_ZDIFHU_9002_PBO | ZDIF3 | 2 | |
   | ZDIFHU | ZDIF3 | ENTER | Z_RF_ZDIFHU_9002_PAI | ZDIF2 | 1 | INIT |
   | ZDIFHU | ZDIF3 | BACK | Z_RF_ZDIFHU_9002_PAI | ZDIF2 | 1 | INIT |

   > **关键规则（踩过的坑）**：**凡是「A 步 → B 步」的跳转行，必须 `PRMOD=1` 且
   > `FCODE_BCKG` 填目标步 PBO 的触发码（这里是 `INIT`）**；`PRMOD=2` 只能用于
   > **同一步骤重显示**（如 INIT → 本步 PBO）。填错会让目标步的 PBO 模块根本不被调用
   > → 表数据容器没注册 → 屏幕 2 报 `GETWA_NOT_ASSIGNED` dump（`LRF_SSCRO02` 第 50 行
   > `READ TABLE <gt_scr>`）。
   - ZDIF1/BACK 行：9000_PAI 内部 `set_fcode(c_fcode_compl_ltrans)` 结束事务
     （默认导航表 `/SCWM/TTRNS_NAV`）
   - 翻页（列表超一屏）由框架预定义 fcode **PGUP/PGDN** 自动处理，**不需**自定义 DOWN 行
4. **Define Function Code Profile**：含 INIT / ENTER / BACK
   （翻页 PGUP/PGDN 是框架预定义 fcode，通过模板 pushbutton 自动可用）
5. **Map Logical Transaction Step to Subscreen**：
   - `ZDIFHU`/`ZDIF1` → `SAPLZFG_RF_ZDIFHU` `9000`
   - `ZDIFHU`/`ZDIF2` → `SAPLZFG_RF_ZDIFHU` `9001`
   - `ZDIFHU`/`ZDIF3` → `SAPLZFG_RF_ZDIFHU` `9002`
6. **Presentation / Personalization Profile**：复用现有 `**` 或按需新建
7. **RF Menu Manager**：菜单挂载（测试期可用 RF Test Environment 直调）
8. **Exception Codes**（SPRO → EWM → Cross-Process Settings → Exception Codes）：
   确认 `DIFD` + 业务上下文 `PPT` + 执行步骤 `16` 存在；不存在则维护或改代码
   （`z_rf_zdifhu_9002_pai.abap` 中 `iv_exccode/iv_buscon/iv_exec_step` 三处常量）

## 3. Plan B：屏幕 9001 / 9002 手工重建（仅当 import 屏幕报错时）

abapGit import 若报 `RPY_DYNPRO_INSERT` 错误（step-loop XML 兼容性），
删除 fugr.xml 中对应屏幕的 `<item>` 重新 import，然后 SE51 手建：

**屏幕 9001（列表）**：子屏幕，7 行 × 40 列

- 行 1：文本 `No.` + `ZSDIFHU_SCR-SELNO`（可输入，NUMC 3）；
  文本 `HU:` + `ZSDIFHU_SCR-HUIDENT`（只显）
- 行 2 起：框选 5 个 DDIC 字段做 Step Loop，**每行块 2 行**（`LOOP_BLOCK=2`，
  重复 3 次，共 6 行）：
  - 行块第 1 行：`ZSDIFHU_ITEM-SEQNO`（只显）、`ZSDIFHU_ITEM-MATNR`（只显）
  - 行块第 2 行：`ZSDIFHU_ITEM-MAKTX`、`ZSDIFHU_ITEM-QUAN`、`ZSDIFHU_ITEM-MEINS`（均只显）
- Flow logic（与 `src/zfg_rf_zdifhu.fugr.screen_9001.abap` 相同）：

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

- 行 1：文本 `Material:` + `ZSDIFHU_PROD-MATNR`（只显）
- 行 2：文本 `Descript.:` + `ZSDIFHU_PROD-MAKTX`（只显）
- 行 3：文本 `Current` + `ZSDIFHU_PROD-QUAN`（只显）+ `ZSDIFHU_PROD-MEINS`（只显）
- 行 4：文本 `Counted` + `ZSDIFHU_PROD-QUAN_COUNT`（**可输入**）
- Flow logic（与 `src/zfg_rf_zdifhu.fugr.screen_9002.abap` 相同）：

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
- [ ] 屏幕 3 输入实盘数量 → ENTER → 过账成功，回到列表且当前数量已刷新
- [ ] 屏幕 3 输入与当前相同的数量 → 报错 "Counted quantity equals current quantity"，不过账
- [ ] 屏幕 3 按 BACK → 回列表；屏幕 2 按 BACK → 回屏幕 1；屏幕 1 按 BACK → 结束事务回菜单
- [ ] 差异 = 实盘 − 当前；过账后 `/SCWM/MON` 库存正确
- [ ] 列表超 3 个物料 → 翻页（PGUP/PGDN）正常

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
   显示在屏底，不应 dump；若异常 dump，把 FM 里的 `MESSAGE e001(00) WITH '...'`
   改为标准 RF 消息类 `MESSAGE eXXX(zmsg)`。

4. **import 屏幕报 `RPY_DYNPRO_INSERT`**：走上文 §3 Plan B。

5. **激活报数据元素不存在**：走 §1 第 4 步改内建类型。

6. **过账报异常码错**：走 §2 第 8 步确认 `DIFD/PPT/16`。

7. **列表空白 / 数据传不进**：核对 §2 第 1 步 PARAM_NAME 是否与 FM CHANGING 参数名
   完全一致（`CS_ZDIFHU_S_SCR` / `CS_ZDIFHU_PROD` / `CT_ZDIFHU_T_ITEMS`）。

8. **数量输入框输不进去**：把该字段的 DDIC 类型从 `QUAN` 改为标准的字符型
   （`/SCWM/DE_RF_CH_NISTA`，域 `/SCWM/DO_QTY_CHAR`）+ 转换出口，再在 FM 里转成数量。

## 6. 对象清单

| 对象 | 名称 | 说明 |
|---|---|---|
| 包 | ZEWM | |
| Function Group | ZFG_RF_ZDIFHU | 屏幕 9000/9001/9002 + 6 FM（含 INCLUDE /SCWM/IRF_SSCR） |
| 结构 | ZSDIFHU_SCR | 屏幕单值（HUIDENT + SELNO 序号输入） |
| 结构 | ZSDIFHU_ITEM | 列表行（SEQNO + MATNR + MAKTX + QUAN + MEINS + GUID_*） |
| 结构 | ZSDIFHU_PROD | 明细屏（SEQNO + MATNR + MAKTX + QUAN 当前 + MEINS + QUAN_COUNT 实盘 + GUID_*） |
| 表类型 | ZSDIFHU_ITEM_TT | 列表内表 |
| App. Parameter | CS_ZDIFHU_S_SCR / CS_ZDIFHU_PROD / CT_ZDIFHU_T_ITEMS | 全局数据容器（Customizing） |
