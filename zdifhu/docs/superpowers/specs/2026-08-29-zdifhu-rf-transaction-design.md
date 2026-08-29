# ZDIFHU — EWM RF Logical Transaction 设计文档

- 日期：2026-08-29
- 系统：SAP S/4HANA embedded EWM
- 交付格式：abapGit 风格（参考 ZMM 项目：`src/package.devc.xml` + 源码 + README）

---

## 1. 需求概述

新建 RF logical transaction `ZDIFHU`，两屏流程：

- **屏幕 1 (9000)**：输入/扫描 HU 号，ENTER 后跳转到屏幕 2
- **屏幕 2 (9001)**：显示 HU 内库存列表（物料号、物料描述、当前数量、单位），
  顶部有**扫描框**（防呆），扫描物料号后光标定位到该行，输入**实盘数量**（可编辑），
  ENTER 立即过账差异，回到扫描框处理下一个物料
- 一屏放不下时，用下箭头**翻页**（标准 RF 表格处理）
- 过账 API：`/SCWM/CL_WM_PACKING=>POST_DIFFERENCE`
- 差异计算：差异 = 实盘数量 − 当前系统数量（代码自己算）

## 2. 架构与对象

| 对象 | 名称 | 说明 |
|---|---|---|
| 开发包 | `ZZDIFHU` | 客户命名空间 |
| Function Group | `ZFG_RF_ZDIFHU` | RF 屏幕函数组 |
| 屏幕 1 | `9000` | HU 号输入（子屏幕） |
| 屏幕 2 | `9001` | 物料列表 + 扫描框 + 实盘数量列（子屏幕，step-loop 表格） |
| 全局结构（单值） | `ZSDIFHU_SCR` | 屏幕字段容器：huident、matnr_scan（扫描框）、当前行等 |
| 全局结构（行） | `ZSDIFHU_ITEM` | 列表行：matnr, maktx, quan, meins, guid_stock, guid_hu, diff_quan（用户输入） |
| 表类型 | `ZSDIFHU_ITEM_TT` | 列表内表 |
| App. Parameter 1 | `ZDIFHU_S_SCR` | PARAM_TYPE=`ZSDIFHU_SCR`（视图 `/SCWM/RF_CUSTOM`，表 `/SCWM/TPARAM_CAT`，APPLIC=`WME`） |
| App. Parameter 2 | `ZDIFHU_T_ITEMS` | PARAM_TYPE=`ZSDIFHU_ITEM_TT`（同上） |
| FM PBO/PAI | `Z_RF_ZDIFHU_9000_PBO` / `_PAI` | 屏幕 1 |
| FM PBO/PAI | `Z_RF_ZDIFHU_9001_PBO` / `_PAI` | 屏幕 2 |

### Step Flow（/SCWM/TSTEP_FLOW）

```
ZDIFHU / ZDIF1 / INIT  → Z_RF_ZDIFHU_9000_PBO  → ZDIF1  (PRMOD 2 前台)
ZDIFHU / ZDIF1 / ENTER → Z_RF_ZDIFHU_9000_PAI  → ZDIF2  (PRMOD 2 前台)
ZDIFHU / ZDIF2 / INIT  → Z_RF_ZDIFHU_9001_PBO  → ZDIF2  (PRMOD 2 前台)
ZDIFHU / ZDIF2 / ENTER → Z_RF_ZDIFHU_9001_PAI  → ZDIF2  (PRMOD 2 前台，过账后回列表)
ZDIFHU / ZDIF2 / BACK  → Z_RF_ZDIFHU_9001_PAI  → ZDIF1  (PRMOD 2 前台)
ZDIFHU / ZDIF2 / DOWN  → Z_RF_ZDIFHU_9001_PAI  → ZDIF2  (翻页)
```

### Customizing（SPRO → EWM → Mobile Data Entry → RF Framework）

1. **Define Application Parameters**（SM30 视图 `/SCWM/RF_CUSTOM`，底层表 `/SCWM/TPARAM_CAT`；
   IMG 位于 "Define Steps in Logical Transactions" 活动下的子结构）：
   - APPLIC=`WME`，`ZDIFHU_S_SCR` → Parameter Type `ZSDIFHU_SCR`
   - APPLIC=`WME`，`ZDIFHU_T_ITEMS` → Parameter Type `ZSDIFHU_ITEM_TT`
   - 这两个参数是跨步骤/跨 PBO-PAI 的全局数据容器，**必须同时作为 CHANGING 参数写进
     4 个 FM 的接口**（框架按参数名匹配传入），且先于 step/flow 配置
2. Define Steps in Logical Transaction：`ZDIFHU` → steps `ZDIF1`、`ZDIF2`
3. Define Step Flow：上表条目
4. Define Function Code Profile：INIT / ENTER / BACK / DOWN（翻页）
5. Map Logical Transaction Step to Subscreen：
   - `ZDIFHU/ZDIF1` → `SAPLZFG_RF_ZDIFHU 9000`
   - `ZDIFHU/ZDIF2` → `SAPLZFG_RF_ZDIFHU 9001`
6. Presentation / Personalization Profile 分配（复用现有 `**`，或按需要新建）
7. RF Menu Manager：菜单挂载（可选，测试期可直接用 RF Test Environment 调用）
8. Define Exception Codes（SPRO → EWM → Cross-Process Settings → Exception Codes）：
   确认 `DIFD` + 业务上下文 `PPT` + 执行步骤 `16` 组合存在（差异过账必传）

## 3. 数据流与关键实现

### 3.0 FM 接口约定（4 个 FM 统一）

```abap
FUNCTION z_rf_zdifhu_9000_pbo.   " 其余 3 个 FM 同构
*"  IMPORTING
*"     VALUE(IV_LGNUM) TYPE /SCWM/LGNUM
*"  CHANGING
*"     REFERENCE(CS_ZDIFHU_S_SCR)   TYPE ZSDIFHU_SCR      " = App.Param ZDIFHU_S_SCR
*"     REFERENCE(CT_ZDIFHU_T_ITEMS) TYPE ZSDIFHU_ITEM_TT  " = App.Param ZDIFHU_T_ITEMS
```
CHANGING 参数名与 Application Parameter 同名，RF 框架按名匹配动态传入。

### 3.1 屏幕 1 PAI（HU 校验 + 库存读取）

```abap
" 1. HU 读取（combined read：先 buffer 再 DB，保证拿到刚过完账的最新数据）
CALL FUNCTION '/SCWM/HU_READ_MULT'
  EXPORTING
    it_huident = lt_huident      " 直接按 HU 号读
    iv_lgnum   = iv_lgnum
  IMPORTING
    et_huhdr   = lt_huhdr
    et_huitm   = lt_huitm        " 物料项：QUAN/MEINS/MATID/BATCHID/GUID_STOCK/GUID_PARENT
  EXCEPTIONS
    not_possible = 1 OTHERS = 2.
" HU 不存在 → 报错，停留本屏

" 2. 只取直接项目（不支持嵌套包装）
LOOP AT lt_huitm INTO ls_huitm WHERE guid_parent = lt_huhdr[ 1 ]-guid_hu.
  " MATID → MATNR
  CALL FUNCTION '/SCWM/MATERIAL_READ_SINGLE'
    EXPORTING iv_matid = ls_huitm-matid iv_langu = sy-langu
    IMPORTING es_mat_global = ls_mat_global
    EXCEPTIONS OTHERS = 1.    " /scwm/cx_md
  " 描述
  SELECT SINGLE maktx FROM makt INTO ls_item-maktx
    WHERE matnr = ls_mat_global-matnr AND spras = sy-langu.
  " 组装 ZSDIFHU_ITEM 行：matnr/maktx/quan(当前)/meins/guid_stock
ENDLOOP.
```

### 3.2 屏幕 2 PBO（列表三件套，必需）

```abap
/scwm/cl_rf_bll_srvc=>init_screen_param( ).
/scwm/cl_rf_bll_srvc=>set_screen_param( 'ZDIFHU_T_ITEMS' ).  " App.Param/FM 参数名
/scwm/cl_rf_bll_srvc=>set_scr_tabname( 'ZSDIFHU_ITEM_TT' )." 表类型名
```

### 3.3 屏幕 2 PAI（防呆 + 差异计算 + 过账）

```abap
" 1. 扫描框防呆：物料必须在列表内
READ TABLE ct_zdifhu_t_items INTO ls_item WITH KEY matnr = cs_zdifhu_s_scr-matnr_scan.
IF sy-subrc <> 0.
  MESSAGE ... " 物料不在该 HU 内
ENDIF.

" 2. 差异计算
lv_diff = ls_item-diff_quan - ls_item-quan.   " 实盘 − 当前
CHECK lv_diff <> 0.                            " 无差异不过账

" 3. 过账（✅ 签名已确认，取自系统标准代码样本）
/scwm/cl_tm=>set_lgnum( iv_lgnum ).

ls_quan-quan = lv_diff.                " 差异数量（实盘 − 当前，带符号）
ls_quan-unit = ls_item-meins.          " HU_READ_MULT 内部单位，直接用

CALL METHOD /scwm/cl_wm_packing=>post_difference
  EXPORTING
    iv_guid_hu    = ls_item-guid_hu
    iv_guid_stock = ls_item-guid_stock
    is_quan       = ls_quan
    iv_exccode    = 'DIFD'             " ⚠️ 三件套按客户系统配置（§5.2）
    iv_buscon     = 'PPT'
    iv_exec_step  = '16'
  EXCEPTIONS
    error         = 1
    OTHERS        = 2.

IF sy-subrc <> 0.
  " 报错（RF 标准：/scwm/cl_rf_dynpro_srvc=>display_message），停留本屏
ELSE.
  " 4. 落库：save 不带 commit，外层显式 COMMIT
  CALL METHOD /scwm/cl_wm_packing=>save
    EXPORTING iv_commit = space iv_wait = space
    EXCEPTIONS OTHERS = 99.
  IF sy-subrc <> 0.
    ROLLBACK WORK.
    " 报错
  ELSE.
    COMMIT WORK AND WAIT.
  ENDIF.
ENDIF.
/scwm/cl_tm=>cleanup( ).

" 5. 过账后：刷新该行数据（重读 HU 更新当前数量），清扫描框，光标回扫描框
```

### 3.4 LGNUM 获取

- FM 接口声明 `IMPORTING iv_lgnum TYPE /scwm/lgnum`（RF framework 自动传入登录仓库号）
- FM 内首行调 `/SCWM/CL_TM=>SET_LGNUM( iv_lgnum )` 初始化全局上下文（packing 类需要）

### 3.5 翻页

- 下箭头 → FCODE `DOWN` → PAI 里移动列表起始行偏移，PRMOD 回显本屏
- 标准 RF 列表处理，参考 step-loop 屏幕

## 4. 屏幕布局

```
┌─ 屏幕 9000 ──────────────┐  ┌─ 屏幕 9001 ──────────────────────┐
│ HU 号: [____________]    │  │ 扫描物料: [________]  HU: xxx     │
└──────────────────────────┘  │ # │物料号  │描述   │当前│单位│实盘│
                               │ 1 │MAT001 │XXX   │ 10│ PC │[ ] │
                               │ 2 │MAT002 │YYY   │  5│ PC │[ ] │
                               │ ↓ 下箭头翻页                       │
                               └──────────────────────────────────┘
```

## 5. 风险与待确认

1. ~~**`POST_DIFFERENCE` 签名**~~ **已确认**（来自系统标准代码样本，2026-08-29）：静态方法，
   参数 `iv_guid_hu / iv_guid_stock / is_quan(差异数量+单位) / iv_exccode / iv_buscon / iv_exec_step`，
   EXCEPTIONS `error`。调用后须 `SAVE` + `COMMIT WORK AND WAIT` 落库，结尾 `/scwm/cl_tm=>cleanup( )`。
2. **异常码**：签名要求显式传入三件套（EXCCODE/BUSCON/EXEC_STEP）。样本代码用 `DIFD/PPT/16`；
   标准 RF "Post HU Differences" 用 `DIFW/TIM/A2`（SAP Note 3601355）。
   **部署前在 SPRO Exception Codes 配置中确认所选组合存在**，二选一或按客户习惯。
3. **批次**：同物料多批次按 guid_stock 分行显示，过账按 guid_stock 精确定位。
4. **嵌套包装**：不支持（只显示直接项目）。如需后续支持，按 et_hutree 递归展开（本次不做）。
5. **FM 接口匹配规则**：Application Parameter 与 FM CHANGING 参数的名字匹配细节，
   以系统内标准 FM（`/SCWM/RF_*`）为模板最终校准（公开资料对接口签名描述不一致）。

## 6. 验收标准

- [ ] `/SCWM/RFUI` → 菜单/测试环境调用 `ZDIFHU`，屏幕 1 显示 HU 输入框
- [ ] 输入存在的 HU → ENTER → 屏幕 2 显示该 HU 物料列表（物料号/描述/数量/单位正确）
- [ ] 屏幕 2 扫描不存在的物料 → 报错（防呆生效）
- [ ] 扫描存在物料 → 光标定位 → 输入实盘数量 → ENTER → 差异过账成功，当前数量更新
- [ ] 列表超出一屏 → 下箭头可翻页
- [ ] 差异 = 实盘 − 当前，过账后库存正确
