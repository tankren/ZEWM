# ZDIFHU — EWM RF HU 差异过账

RF 逻辑事务 `ZDIFHU`：屏幕 1 输/扫 HU 号 → 屏幕 2 显示 HU 物料列表，
扫物料号定位行、输入实盘数量，ENTER 立即过账差异（实盘 − 当前）。
过账 API：`/SCWM/CL_WM_PACKING=>POST_DIFFERENCE`。

## 1. 安装（abapGit）

1. abapGit → New Offline（或 New Online 推送到内部 Git）→ 导入本仓库 zip
2. 包：`ZEWM`（abapGit 创建 repo 时填的 Package）
3. Pull → 激活全部对象
4. 激活后核对（SE11）：`/SCWM/DE_HUIDENT`、`/SCWM/DE_QUAN`、`/SCWM/DE_MEINS`、
   `/SCWM/DE_GUID_HU`、`/SCWM/DE_GUID_STOCK` 存在；若某个不存在导致 `ZSDIFHU*`
   激活报错，SE11 把对应字段从数据元素引用改为内建类型：
   HUIDENT→CHAR 20；QUAN/DIFF_QUAN→QUAN 长 13 小数 3；MEINS→UNIT 3；GUID_*→CHAR 32

## 2. Customizing（SPRO → EWM → Mobile Data Entry → RF Framework，按顺序）

1. **Define Application Parameters**（`/SCWM/TPARAM_CAT`，视图 `/SCWM/RF_CUSTOM`，SM30）：
   - APPLIC=`WME` / `CS_ZDIFHU_S_SCR` / Parameter Type=`ZSDIFHU_SCR`
   - APPLIC=`WME` / `CT_ZDIFHU_T_ITEMS` / Parameter Type=`ZSDIFHU_ITEM_TT`
   （PARAM_NAME 必须与 4 个 FM 的 CHANGING 参数名**完全一致**，带 CS_/CT_ 前缀）
2. **Define Steps in Logical Transaction**：`ZDIFHU` → `ZDIF1`、`ZDIF2`
3. **Define Step Flow**（`/SCWM/TSTEP_FLOW`）：

   | LTRANS | STEP | FCODE | FMODUL | SSTEP | PRMOD |
   |---|---|---|---|---|---|
   | ZDIFHU | ZDIF1 | INIT | Z_RF_ZDIFHU_9000_PBO | ZDIF1 | 2 |
   | ZDIFHU | ZDIF1 | ENTER | Z_RF_ZDIFHU_9000_PAI | ZDIF2 | 2 |
   | ZDIFHU | ZDIF1 | BACK | Z_RF_ZDIFHU_9000_PAI | ZDIF1 | 2 |
   | ZDIFHU | ZDIF2 | INIT | Z_RF_ZDIFHU_9001_PBO | ZDIF2 | 2 |
   | ZDIFHU | ZDIF2 | ENTER | Z_RF_ZDIFHU_9001_PAI | ZDIF2 | 2 |
   | ZDIFHU | ZDIF2 | BACK | Z_RF_ZDIFHU_9001_PAI | ZDIF1 | 2 |

   - ZDIF1/BACK 行：9000_PAI 内部 `set_fcode(c_fcode_compl_ltrans)` 结束事务
     （默认导航表 `/SCWM/TTRNS_NAV`）
   - 翻页（列表超一屏）由框架预定义 fcode **PGUP/PGDN** 自动处理，**不需**自定义 DOWN 行
4. **Define Function Code Profile**：含 INIT / ENTER / BACK
   （翻页 PGUP/PGDN 是框架预定义 fcode，通过模板 pushbutton 自动可用）
5. **Map Logical Transaction Step to Subscreen**：
   - `ZDIFHU`/`ZDIF1` → `SAPLZFG_RF_ZDIFHU` `9000`
   - `ZDIFHU`/`ZDIF2` → `SAPLZFG_RF_ZDIFHU` `9001`
6. **Presentation / Personalization Profile**：复用现有 `**` 或按需新建
7. **RF Menu Manager**：菜单挂载（测试期可用 RF Test Environment 直调）
8. **Exception Codes**（SPRO → EWM → Cross-Process Settings → Exception Codes）：
   确认 `DIFD` + 业务上下文 `PPT` + 执行步骤 `16` 存在；不存在则维护或改代码
   （`z_rf_zdifhu_9001_pai.abap` 中 `iv_exccode/iv_buscon/iv_exec_step` 三处常量）

## 3. Plan B：屏幕 9001 手工重建（仅当 import 屏幕报错时）

abapGit import 若报 `RPY_DYNPRO_INSERT` 错误（step-loop XML 兼容性），
删除 fugr.xml 中屏幕 9001 的 `<item>` 重新 import，然后 SE51 手建：

1. SE51 → 程序 `SAPLZFG_RF_ZDIFHU` → 屏幕 `9001`，属性：子屏幕，7 行 × 40 列
2. 布局：
   - 行 1：文本 `Scan:` + 输入框 `ZSDIFHU_SCR-MATNR_SCAN`（从 DDIC 拖入，可输入）
   - 行 2：文本 `HU:` + `ZSDIFHU_SCR-HUIDENT`（只显）
   - 行 3 起：框选 5 个 DDIC 字段（`ZSDIFHU_ITEM-MATNR/MAKTX/QUAN/MEINS/DIFF_QUAN`），
     Edit → Grouping → Step Loop → Define，重复 5 行；前 4 列设只显，`DIFF_QUAN` 可输入
3. Flow logic（与 `src/zfg_rf_zdifhu.fugr.screen_9001.abap` 相同）：

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

4. 激活

## 4. 验收清单

- [ ] `/SCWM/RFUI`（或 RF Test Environment）调用 `ZDIFHU`，屏幕 1 显示 HU 输入框
- [ ] 输入存在的 HU → ENTER → 屏幕 2 显示物料列表（物料号/描述/数量/单位正确）
- [ ] 屏幕 2 扫不存在物料 → 报错 "Material not in this HU"（防呆生效）
- [ ] 扫存在物料 → 输入实盘数量 → ENTER → 过账成功，当前数量刷新
- [ ] 列表超 5 行 → 翻页（PGUP/PGDN）正常
- [ ] 差异 = 实盘 − 当前；过账后 `/SCWM/MON` 库存正确
- [ ] 屏幕 1 按 BACK → 事务正常结束回到菜单

## 5. 故障排查（Pull 后跑不起来/报错，按顺序查）

1. **激活报语法错误**（`... is not a key field` 或 `method ... not found`）：
   SE24 查 `/SCWM/CL_RF_BLL_SRVC`，确认 `GET_FCODE` / `SET_FCODE` / `SET_PRMOD` /
   `SET_LINE` / `SET_FIELD` / `SET_SCR_TABNAME` / `INIT_SCREEN_PARAM` / `SET_SCREEN_PARAM`
   均为静态方法、签名匹配；不符则按系统内标准 `/SCWM/RF_*` FM 校准写法。

2. **运行时 dump**（DYNPRO/RF 调用链 short dump）：标准 RF 框架会捕获 E 型消息
   显示在屏底，不应 dump；若异常 dump，把 4 个 FM 里的 `MESSAGE e001(00) WITH '...'`
   改为标准 RF 消息类 `MESSAGE eXXX(zmsg)`。

3. **import 屏幕 9001 报 `RPY_DYNPRO_INSERT`**：走上文 §3 Plan B。

4. **激活报数据元素不存在**：走 §1 第 4 步改内建类型。

5. **过账报异常码错**：走 §2 第 8 步确认 `DIFD/PPT/16`。

6. **列表空白 / 数据传不进**：核对 §2 第 1 步 PARAM_NAME 是否与 FM CHANGING 参数名
   完全一致（`CS_ZDIFHU_S_SCR` / `CT_ZDIFHU_T_ITEMS`）。

## 6. 对象清单

| 对象 | 名称 | 说明 |
|---|---|---|
| 包 | ZEWM | |
| Function Group | ZFG_RF_ZDIFHU | 屏幕 9000/9001 + 4 FM（含 INCLUDE /SCWM/IRF_SSCR） |
| 结构 | ZSDIFHU_SCR / ZSDIFHU_ITEM | 屏幕单值 / 列表行 |
| 表类型 | ZSDIFHU_ITEM_TT | 列表内表 |
| App. Parameter | CS_ZDIFHU_S_SCR / CT_ZDIFHU_T_ITEMS | 全局数据容器（Customizing） |
