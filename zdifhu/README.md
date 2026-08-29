# ZDIFHU — EWM RF HU 差异过账

RF 逻辑事务 `ZDIFHU`：屏幕 1 输/扫 HU 号 → 屏幕 2 显示 HU 物料列表，
扫物料号定位行、输入实盘数量，ENTER 立即过账差异（实盘 − 当前）。
过账 API：`/SCWM/CL_WM_PACKING=>POST_DIFFERENCE`。

## 1. 安装（abapGit）

1. abapGit → New Offline（或 New Online 推送到内部 Git）→ 导入本仓库 zip
2. 包：`ZZDIFHU`（不存在则让 abapGit 创建）
3. Pull → 激活全部对象
4. 激活后核对（SE11）：`/SCWM/DE_HUIDENT`、`/SCWM/DE_QUAN`、`/SCWM/DE_MEINS`、
   `/SCWM/DE_GUID_HU`、`/SCWM/DE_GUID_STOCK` 存在；若某个不存在导致 `ZSDIFHU*`
   激活报错，SE11 把对应字段从数据元素引用改为内建类型：
   HUIDENT→CHAR 20；QUAN/DIFF_QUAN→QUAN 长 13 小数 3；MEINS→UNIT 3；GUID_*→CHAR 32

## 2. Customizing（SPRO → EWM → Mobile Data Entry，按顺序）

1. **Define Application Parameters**（视图 `/SCWM/RF_CUSTOM`，SM30）：
   - APPLIC=`WME` / `ZDIFHU_S_SCR` / Parameter Type=`ZSDIFHU_SCR`
   - APPLIC=`WME` / `ZDIFHU_T_ITEMS` / Parameter Type=`ZSDIFHU_ITEM_TT`
2. **Define Steps in Logical Transaction**：`ZDIFHU` → `ZDIF1`、`ZDIF2`
3. **Define Step Flow**（`/SCWM/TSTEP_FLOW`）：

   | LTRANS | STEP | FCODE | FMODUL | SSTEP | PRMOD |
   |---|---|---|---|---|---|
   | ZDIFHU | ZDIF1 | INIT | Z_RF_ZDIFHU_9000_PBO | ZDIF1 | 2 |
   | ZDIFHU | ZDIF1 | ENTER | Z_RF_ZDIFHU_9000_PAI | ZDIF2 | 2 |
   | ZDIFHU | ZDIF2 | INIT | Z_RF_ZDIFHU_9001_PBO | ZDIF2 | 2 |
   | ZDIFHU | ZDIF2 | ENTER | Z_RF_ZDIFHU_9001_PAI | ZDIF2 | 2 |
   | ZDIFHU | ZDIF2 | BACK | Z_RF_ZDIFHU_9001_PAI | ZDIF1 | 2 |
   | ZDIFHU | ZDIF2 | DOWN | Z_RF_ZDIFHU_9001_PAI | ZDIF2 | 2 |

4. **Define Function Code Profile**：含 INIT / ENTER / BACK / DOWN（下箭头绑 DOWN）
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

1. SE51 → 程序 `SAPLZFG_RF_ZDIFHU` → 屏幕 `9001`，属性：子屏幕，8 行 × 40 列
2. 布局：
   - 行 1：文本 `Scan:` + 输入框 `ZSDIFHU_SCR-MATNR_SCAN`（从 DDIC 拖入，可输入）
   - 行 2：文本 `HU:` + `ZSDIFHU_SCR-HUIDENT`（只显）
   - 行 4 起：框选 5 个 DDIC 字段（`ZSDIFHU_ITEM-MATNR/MAKTX/QUAN/MEINS/DIFF_QUAN`），
     Edit → Grouping → Step Loop → Define，重复 5 行；前 4 列设只显，`DIFF_QUAN` 可输入
3. Flow logic（与 `src/zfg_rf_zdifhu.fugr.screen_9001.abap` 相同）：

   ```abap
   PROCESS BEFORE OUTPUT.
     LOOP AT gt_zdifhu_items INTO zsdifhu_item CURSOR gv_cursor.
     ENDLOOP.
   *
   PROCESS AFTER INPUT.
     LOOP AT gt_zdifhu_items INTO zsdifhu_item.
     ENDLOOP.
   ```

4. 激活

## 4. 验收清单

- [ ] `/SCWM/RFUI`（或 RF Test Environment）调用 `ZDIFHU`，屏幕 1 显示 HU 输入框
- [ ] 输入存在的 HU → ENTER → 屏幕 2 显示物料列表（物料号/描述/数量/单位正确）
- [ ] 屏幕 2 扫不存在物料 → 报错 "Material not in this HU"（防呆生效）
- [ ] 扫存在物料 → 输入实盘数量 → ENTER → 过账成功，当前数量刷新
- [ ] 列表超 5 行 → 下箭头翻页
- [ ] 差异 = 实盘 − 当前；过账后 `/SCWM/MON` 库存正确

## 5. 对象清单

| 对象 | 名称 | 说明 |
|---|---|---|
| 包 | ZZDIFHU | |
| Function Group | ZFG_RF_ZDIFHU | 屏幕 9000/9001 + 4 FM |
| 结构 | ZSDIFHU_SCR / ZSDIFHU_ITEM | 屏幕单值 / 列表行 |
| 表类型 | ZSDIFHU_ITEM_TT | 列表内表 |
| App. Parameter | ZDIFHU_S_SCR / ZDIFHU_T_ITEMS | 全局数据容器（Customizing） |
