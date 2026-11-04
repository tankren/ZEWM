# ZCHGSB — EWM RF 换源货位

[English](README.md) | **中文**

> **状态：** 已在 S/4HANA（客户端 100，仓库 `1710`）实现并验证。
> RF 拣货屏幕 `PIMTTO` 增加 `ZCHGSB` 功能键（F11）。用户扫描新的源货位后，
> 原仓库任务按数量 `0` 确认，生成货位拒绝，并在扫描的货位中创建新的仓库任务。
> 包：`ZEWM`。代码传输：`S4HK902806`。BAdI 传输：`S4HK902812`。
> 配置：`S4HK902808`（手工）。消息：`S4HK902782`。
> 参见[验收清单](#5-验收清单)。

## 1. 设计

### 1.1 问题

RF 拣货时，SAP 通常按仓库策略选择源货位。如果拣货员发现库存实际在另一个货位，
标准 RF 流程没有直接的“换源货位”操作。手工释放并重建仓库任务既慢又容易出错。

`ZCHGSB` 在标准拣货流程中增加一个受控异常：

1. 拣货员在 `PIMTTO` 按 **F11**。
2. 自定义屏幕显示当前拣货行，并要求输入新的源货位。
3. 校验通过后，标准 RF 异常链把原 WT 按数量 `0` 确认，并生成**货位拒绝**。
4. EWM 重新确定货位并创建新 WT。BAdI 强制重新确定时使用**扫描的货位**。

### 1.2 为什么使用标准异常链

本实现**不**自己确认 WT，也不自己创建新 WT。它把后续工作交给标准 RF 异常流程：

```text
PIMTTO F11
  -> 屏幕 9100（PBO）
  -> 扫描新源货位 + 回车
  -> PAI：校验货位、检查库存、导出上下文
  -> set_shortcut( 'ZCSB' ), set_prmod( '1' ), set_fcode( 'EXCEPT' )
  -> /SCWM/RF_PICK_EXCEPTION
  -> TEXCEXEH：ZCSB / BIDU
  -> 标准 0 数量确认 + 货位拒绝
  -> /SCWM/TO_CREATE_BIN_DENIAL
  -> /SCWM/REM_BIN_DET
  -> BAdI /SCWM/EX_CORE_RMS_DETERMINE
  -> 按扫描货位过滤候选 quant
  -> 在扫描货位创建新 WT
```

这样，确认、HU 处理、库存移动和错误处理都留在 SAP 标准代码中。自定义代码只负责
屏幕、校验和货位选择。

### 1.3 为什么需要 BAdI

如果没有 BAdI，EWM 会按正常策略重新确定货位，可能选到别的货位。BAdI 是
`/SCWM/REM_BIN_DET` 内部支持的扩展点，可以替换货位确定所用的候选 quant 集合。

**关键：**正确的 BAdI 是

- 增强点 `/SCWM/ES_CORE_RMS`
- BAdI 定义 `/SCWM/EX_CORE_RMS_DETERMINE`
- 接口 `/SCWM/IF_EX_CORE_RMS_DETERMINE`
- 单次使用（single-use）

名称相似的 `/SCWM/EX4_CORE_RMS_DETERMINE` **没有使用**，也没有引用。不要实现它。

### 1.4 为什么通过内存传上下文

货位拒绝路径会从原 WT 构建需求，然后在调用 `/SCWM/REM_BIN_DET` 之前**清空**
`VLPLA`、`VLENR` 和 `TANUM`（`/SCWM/TO_CREATE_BIN_DENIAL`）。
`/SCWM/S_REMREQ` 本身也没有 `TANUM` 字段。

因此在 BAdI 执行时：

- `IS_LTAP-TANUM` 为空。
- `IS_LTAP-VLPLA` 为空。
- `IS_LTAP-VLENR` 为空。

BAdI 无法从 `IS_LTAP` 识别 RF 会话。为此，PAI 把少量上下文导出到 ABAP 内存 ID
`ZCHGSB_CTX`（类型 `/SCWM/LTAP`），BAdI 再导入。上下文包含仓库、原 WT、旧货位、
物料、批次、目标数量和单位，以及扫描的新货位（`NLPLA`）。

实现类中还有静态兜底（`GS_CTX` / `GV_CTX_SET`），用于内存 ID 在 BAdI 调用中不可见
的情况。

### 1.5 为什么用 `BIDU`，不用 `BIDF`

在 `/SCWM/TEXCEXEH` 中，活动仓库（`1710`、`BUSCON = TPI`、`PRMODE = 05`）的异常代码
`ZCSB` 必须使用 `IPRCODE = BIDU`。

使用 `BIDF` 时，`/SCWM/RF_PICK_EXCEPTION` 只修改 RF 内存，然后静默返回 `PIMTTO`；
不会确认、不会生成货位拒绝、不会创建新 WT。这是实现过程中验证过的。
`BIDU` 才会执行真正的货位拒绝链。

### 1.6 库存预检查

在交给异常链之前，PAI 会检查扫描货位中是否有足够的可用库存满足当前拣货数量
（`VSOLA`）。这样可以避免换到一个无法满足 WT 的货位。

检查使用 `/SCWM/SELECT_STOCK`，并按以下规则汇总：

- 库存行的替代单位（`ALTME`）等于目标单位时，累加 `QUANA`；
- 库存行的基本单位（`MEINS`）等于目标单位时，累加 `QUAN`。

目标单位取 `ORDIM_CONFIRM-ALTME`；如果为空，取 `ORDIM_CONFIRM-MEINS`。

## 2. 端到端流程

1. 拣货员在 `PIMTTO`，当前有有效拣货行。
2. 按 **F11**（`ZCHGSB`，PB2），通过 `/SCWM/TSTEP_FLOW` 路由：
   `PIMTTO/ZCHGSB -> ZEWM_RF_ZCHGSB_9100_PBO -> step ZCHGSB`，PRMOD `1`，
   `FCODE_BCKG = INIT`。
3. PBO 9100 从 `TT_ORDIM_CONFIRM` 读取当前行，填充 `GS_CHGSB_SCR`，
   转换数量和单位用于显示，清空新货位字段，并使 `NEWLGPLA` 可输入。
4. 拣货员扫描新源货位并按 **回车**。
5. PAI 9100 依次校验：
   - 存在拣货行（`TANUM`）；
   - 输入了新货位；
   - 新货位不等于当前货位；
   - 货位存在且未冻结；
   - 货位类型与拣货行的源存储类型一致；
   - 货位允许拣货（如果货位有位置对象，则做货位活动检查）；
   - 扫描货位中有足够的 `VSOLA` 可用库存。
6. 成功后，PAI 导出 `ZCHGSB_CTX`，设置 shortcut `ZCSB`、PRMOD `1`、FCODE `EXCEPT`。
7. `/SCWM/TSTEP_FLOW` 把 `ZCHGSB/EXCEPT` 路由到 `/SCWM/RF_PICK_EXCEPTION`
   （步骤 `PIMTTO`，PRMOD `1`）。
8. `/SCWM/TEXCEXEH` 把 `ZCSB` 解析为 `BIDU`。标准流程把原 WT 按数量 `0` 确认，
   写入差异，并生成货位拒绝。
9. `/SCWM/TO_CREATE_BIN_DENIAL` 构建需求，清空旧货位/WT 字段，调用
   `/SCWM/REM_BIN_DET`。
10. BAdI 实现 `ZCL_ZEWM_RMS_DET_CHGSB` 导入 `ZCHGSB_CTX`，按
    `LGPLA = 扫描货位` 过滤 `IT_QMAT`，填充 `ET_QMAT_CUS`，并设置 `EV_SET = 'X'`。
11. EWM 在扫描货位创建新 WT，RF 返回 `PIMTTO`。
12. 第一次成功确定后，上下文被释放；如果后续还有拆分确定，则使用标准策略。

## 3. 实现

### 3.1 对象

| 对象 | 名称 | 用途 |
|---|---|---|
| 函数组 | `ZEWM_FG_RF_ZCHGSB` | RF 屏幕和函数模块 |
| 主程序 | `SAPLZEWM_FG_RF_ZCHGSB` | 函数组主程序 |
| TOP include | `LZEWM_FG_RF_ZCHGSBTOP` | 全局结构 `GS_CHGSB_SCR` |
| PBO FM | `ZEWM_RF_ZCHGSB_9100_PBO` | 填充屏幕 9100 |
| PAI FM | `ZEWM_RF_ZCHGSB_9100_PAI` | 校验、预检查、导出上下文 |
| 屏幕 | `9100` | 新源货位屏幕（15 x 26） |
| BAdI 类 | `ZCL_ZEWM_RMS_DET_CHGSB` | 过滤 RMS 候选 quant |
| BAdI 实现 | `ZEWM_ZCHGSB_RMS_DET` | `/SCWM/ES_CORE_RMS` 中的 ENHO |
| 消息类 | `ZEWM_RF_MSG` | 消息 012–017 |

包：`ZEWM`。
代码传输：`S4HK902806`（任务 `S4HK902807`）。
BAdI 传输：`S4HK902812`。
消息传输：`S4HK902782`（任务 `S4HK902810`，与 ZDIFHU 共用）。

### 3.2 屏幕 9100

已验证的 `D020S`：

- 程序 `SAPLZEWM_FG_RF_ZCHGSB`， dynpro `9100`
- 类型 `I`
- `BZMX = 9`，`BZBR = 26`
- `NOLI = 15`，`NOCO = 26`（15 行 x 26 列）

布局：标签在第 1 列，值从第 12 列开始，宽度 14。

| 行 | 内容 | 字段 / 文本 |
|---|---|---|
| 1 | Product | 标签 + `GS_CHGSB_SCR-MATNR` |
| 2 | 物料描述 | `GS_CHGSB_SCR-MAKTX`（C1，N26，无标签） |
| 3 | Src Bin | 标签 + `GS_CHGSB_SCR-VLPLA` |
| 4 | Srce Type | 标签 + `GS_CHGSB_SCR-VLTYP` |
| 5 | TgtQtyA | 标签 + `GS_CHGSB_SCR-VSOLA_CHR`（C12，N7）+ `GS_CHGSB_SCR-ALTME`（C21，N5） |
| 6 | HU | 标签 + `GS_CHGSB_SCR-HUIDENT` |
| 7 | Batch | 标签 + `GS_CHGSB_SCR-CHARG` |
| 8 | 静态文本 | `Scan New Storage Bin`（C1，N21） |
| 9 | Bin | 标签 + `GS_CHGSB_SCR-NEWLGPLA` 输入，无 `REQU_ENTRY` |

不要在 `NEWLGPLA` 上设置 `REQU_ENTRY`；空值由 PAI 检查并显示消息 013。
PBO 通过以下语句启用输入：

```abap
set_screlm_input_on( 'GS_CHGSB_SCR-NEWLGPLA' ).
```

`GS_CHGSB_SCR` 的字段顺序：

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

这里只列出明确已知的类型；改结构前请在活动 TOP include 中核对其余字段类型。

### 3.3 PBO `ZEWM_RF_ZCHGSB_9100_PBO`

1. 读取当前 RF 行：
   `GET_LINE( )`；如果为 `0`，使用行 `1`。
   `READ TABLE TT_ORDIM_CONFIRM INDEX LV_LINE INTO ORDIM_CONFIRM`；必要时回退到
   索引 `1`。
2. 按 RF 常规回退链确定 `LGNUM`：
   `ORDIM_CONFIRM-LGNUM -> RESOURCE -> WHO -> GET_LGNUM( )`；在
   `/SCWM/CL_TM` 和 `/SCWM/CL_RF_BLL_SRVC` 上调用 `SET_LGNUM`。
3. 清空 `GS_CHGSB_SCR` 并填充：
   - `VLTYP`、`VLPLA`、`HUIDENT`、`MATNR`、`TANUM`、`VLENR`
   - `VSOLA_CHR` 用 `CONVERSION_EXIT_QTYCH_OUTPUT`
   - `ALTME` 用 `CONVERSION_EXIT_CUNIT_OUTPUT`
   - `MAKTX` 取 `ORDIM_CONFIRM-MAKTX`，否则查 `MAKT`
   - `CHARG` 取 `ORDIM_CONFIRM-BATCH`
4. 清空 `NEWLGPLA` 和 `NEWLGTYP`，启用输入，设置状态文本
   `Scan new source bin`（消息 001）。

单位转换是必需的。没有转换时，屏幕会显示内部单位（`ST`、`KAR`），而不是外部单位
（`PC`、`CAR`）。标准 SAP 对 `MEINS` 使用 `CUNIT` 转换例程。

### 3.4 PAI `ZEWM_RF_ZCHGSB_9100_PAI`

PAI 保持标准 `PIMTTO` 的 CHANGING 签名（`ORDIM_CONFIRM`、`TT_ORDIM_CONFIRM`、
`TT_NESTED_HU`、`WME_VERIF`、`RESOURCE`、`T_RF_PICK_HUS`、`WHO`）。

#### 校验顺序

| # | 检查 | 失败处理 |
|---|---|---|
| 1 | `ORDIM_CONFIRM-TANUM` 非空 | `set_fcode('INIT')`、`e012`、`RETURN` |
| 2 | `GS_CHGSB_SCR-NEWLGPLA` 非空 | `set_fcode('INIT')`、`e013`、`RETURN` |
| 3 | `TRANSLATE ... TO UPPER CASE`、`CONDENSE` | — |
| 4 | 新货位不等于 `ORDIM_CONFIRM-VLPLA` | `set_fcode('INIT')`、`e014`、`RETURN` |
| 5 | `/SCWM/BIN_EXIST_CHECK` 返回严重级别 `S` | `e017`、`RETURN` |
| 6 | `/SCWM/LAGP` 行存在且 `LGTYP = ORDIM_CONFIRM-VLTYP` | `e017`、`RETURN` |
| 7 | `LAGP-SKZUA` 不为 `X`（未冻结出库） | `e017`、`RETURN` |
| 8 | 如果 `GUID_LOC` 非空，`/SCWM/BIN_ACT_CHECK` 使用 `WMEGC_BINACT_PICK` 允许拣货 | `e017`、`RETURN` |
| 9 | `VSOLA` 有足够可用库存（仅当 `VSOLA > 0`） | `e036(/scwm/ui_adma)`、`RETURN` |
| 10 | 设置 `GS_CHGSB_SCR-NEWLGTYP`、导出上下文、设置 shortcut/PRMOD/FCODE | — |

每个错误分支都必须 `RETURN`。没有 `RETURN` 时，下一个检查会覆盖消息：例如输入一个
假货位，最终会显示 `e036` 而不是 `e017`。

#### 货位检查细节

- `/SCWM/BIN_EXIST_CHECK` 用扫描货位和 `LGNUM` 调用；严重级别必须是 `S`。
- `/SCWM/LAGP` 检查确认货位存在，并且存储类型等于拣货行的源存储类型
  （`ORDIM_CONFIRM-VLTYP`）。
- `SKZUA = 'X'` 表示货位冻结出库，必须拒绝。
- 货位活动检查只在货位有位置对象时相关：`GUID_LOC` 非空，且
  `/SCWM/BINSTOBJ` 中有行。实现使用 `MOVE-CORRESPONDING LAGP TO LAGP_INT`，
  调用 `/SCWM/BIN_ACT_CHECK`，`IV_ACTIVITY = WMEGC_BINACT_PICK`；
  `EV_ALLOWED` 必须为 `X`。

不要用 `/SCWM/RF_PICK_BIN_CHANGE_CHECK` 做这个检查；它校验的是另一个字段
（`NLPLA`），不适合扫描源货位的场景。

#### 库存预检查

仅当 `ORDIM_CONFIRM-VSOLA > 0` 时执行。

```abap
CALL FUNCTION '/SCWM/SELECT_STOCK'
  EXPORTING
    iv_lgnum       = lv_lgnum
    ir_lgpla       = lr_lgpla      " 扫描货位
    ir_matnr       = lr_matnr      " 当前物料
    ir_charg       = lr_charg      " 当前批次
    ir_cat         = lr_cat        " 仅当 ORDIM_CONFIRM-CAT 非空
    ir_stock_usage = lr_usage      " 仅当 ORDIM_CONFIRM-STOCK_USAGE 非空
    ir_owner       = lr_owner      " 仅当 ORDIM_CONFIRM-OWNER 非空
    ir_entitled    = lr_entitled   " 仅当 ORDIM_CONFIRM-ENTITLED 非空
  IMPORTING
    et_huitm       = lt_huitm
  EXCEPTIONS
    error          = 1
    OTHERS         = 2.
```

可选范围只在 RF 字段非空时添加。添加空范围会把有效库存过滤掉。

数量汇总：

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

`QUANA` 是替代单位的库存数量；`QUAN` 是基本单位的数量。如果目标单位既不是 `ALTME`
也不是 `MEINS`，当前实现不做转换；在 RF 拣货流程中目标单位只会是这两种之一。

#### 上下文与交接

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

然后按以下顺序执行：

```abap
set_shortcut( 'ZCSB' ).
set_prmod( '1' ).        " 1 = 后台；异常流必须
set_fcode( 'EXCEPT' ).
```

`BACK` 会释放 `ZCHGSB_CTX`，清除 `GV_CTX_SET`，调用 `CLEAR_SHORTCUT`，然后返回。

### 3.5 BAdI 实现

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

要点：

- `IV_CALL` 必须是 `C`（`WMEGC_CALL_BIN_DENIAL`）。其他 RMS 调用因为 `EV_SET`
  保持初始值，继续走标准逻辑。
- 上下文从内存导入，并有静态兜底。
- 过滤条件**只有** `LGNUM` + `LGPLA = 扫描货位`。
  实现有意**不**比较 `MATID`、`MATNR` 或 `BATCHID`：在货位拒绝路径中，
  由 REMREQ 构建的 `IS_LTAP` 经常这些字段为空；而 `IT_QMAT` 已经是当前需求的
  候选集合。
- 实现有意**不**过滤 `QUAN > 0`；数量和可用性由标准 RMS 逻辑处理。
- 先填充 `ET_QMAT_CUS`，再设置 `EV_SET`。如果扫描货位中没有候选 quant，
  `EV_SET` 保持初始值，标准策略继续。
- 第一次成功确定后释放内存并清除静态标志，因此后续拆分确定使用标准策略。

BAdI 定义是增强点 `/SCWM/ES_CORE_RMS` 中的 `/SCWM/EX_CORE_RMS_DETERMINE`；
实现是 `ZEWM_ZCHGSB_RMS_DET`，指向类 `ZCL_ZEWM_RMS_DET_CHGSB`。它是单次使用，
没有过滤器。它由 `/SCWM/REM_BIN_DET` 内的 `FORM src_bin_det`
（`/SCWM/LREM_BIN_DETF12`）通过 `CL_BADI_CORE_RMS~FILTER_SORT_STOCK` 调用。

> PAI 中的旧注释提到按 `LGNUM + MATID (+ BATCHID)` 匹配。活动类没有这样做；
> 有效且已验证的逻辑是按货位过滤。

### 3.6 主要数据结构

| 结构 / 表 | 用途 |
|---|---|
| `/SCWM/S_RF_ORDIM_CONFIRM` | 当前 RF 拣货行（`TANUM`、`VLPLA`、`VLTYP`、`MATNR`、`BATCH`、`VSOLA`、`ALTME`、`MEINS`、`HUIDENT`、`VLENR`） |
| `/SCWM/LTAP` | `ZCHGSB_CTX` 的上下文（`LGNUM`、`TANUM`、`VLPLA`、`MATID`、`BATCHID`、`MATNR`、`CHARG`、`VSOLA`、`ALTME`、`NLPLA`） |
| `/SCWM/S_AQUA_INT` | `IT_QMAT` 中的一条候选 quant（`LGNUM`、`LGTYP`、`LGPLA`、`MATID`、`CHARG`、`GUID_STOCK`） |
| `/SCWM/TT_AQUA_INT` | 候选 quant 表（`IT_QMAT`、`ET_QMAT_CUS`） |
| `/SCWM/S_STOCK_SELECT` | `/SCWM/SELECT_STOCK` 返回的一行（`ALTME`、`QUANA`、`MEINS`、`QUAN`） |

## 4. 配置

以下配置适用于应用 `01`、RF 区域 `PI****`，适用时仓库为 `1710`。
配置传输 `S4HK902808` 是手工配置参考；用户已确认配置可以手工重建。

### 4.1 `/SCWM/TSTEP_SCR`

| 字段 | 值 |
|---|---|
| `APPLIC` | `01` |
| `LTRANS` | `PI****` |
| `STEP` | `ZCHGSB` |
| `STATE` | `******` |
| `SCR_SQNCE` | `01` |
| `SCR_PROGR` | `SAPLZEWM_FG_RF_ZCHGSB` |
| `SCR_NUM` | `9100` |

### 4.2 `/SCWM/TSTEP_FLOW`

| STEP | FCODE | 函数模块 | SSTEP | PRMOD | FCODE_BCKG |
|---|---|---|---|---|---|
| `PIMTTO` | `ZCHGSB` | `ZEWM_RF_ZCHGSB_9100_PBO` | `ZCHGSB` | `1` | `INIT` |
| `ZCHGSB` | `BACK` | `ZEWM_RF_ZCHGSB_9100_PAI` | `PIMTTO` | `1` | `INIT` |
| `ZCHGSB` | `INIT` | `ZEWM_RF_ZCHGSB_9100_PBO` | `ZCHGSB` | `2` | （空） |
| `ZCHGSB` | `ENTER` | `ZEWM_RF_ZCHGSB_9100_PAI` | `PIMTTO` | `0` | （空） |
| `ZCHGSB` | `EXCEPT` | `/SCWM/RF_PICK_EXCEPTION` | `PIMTTO` | `1` | （空） |

`PRMOD` 是 `NUMC`。空值存为 `0` 并按初始值处理，因此函数模块的 `SET_PRMOD` 会生效。
`PRMOD 1` 是后台，`PRMOD 2` 是前台。`ZCHGSB/EXCEPT` 行必须是 `PRMOD = 1`；
否则框架可能清除函数模块设置的 FCODE。

### 4.3 `/SCWM/TFCOD_PRF`

| STEP | FCODE | PUSHB | FNKEY | SHORTCUT |
|---|---|---|---|---|
| `PIMTTO` | `ZCHGSB` | `PB2` | `F11` | `11` |
| `ZCHGSB` | `BACK` | — | `F7` | `07` |
| `ZCHGSB` | `ENTER` | — | `ENT` | — |

自定义键是普通功能键，只负责步骤跳转。真正的异常 FCODE `EXCEPT` 由 PAI 设置，
不是通过标准异常标志设置。

### 4.4 `/SCWM/TFCOD_CAT`、`/SCWM/TSTEP_CAT`、`/SCWM/TOBJ_TXT`

| 表 | 键 | 值 |
|---|---|---|
| `/SCWM/TFCOD_CAT` | `APPLIC = 01` | `FCODE = ZCHGSB` |
| `/SCWM/TSTEP_CAT` | `APPLIC = 01` | `STEP = ZCHGSB` |
| `/SCWM/TOBJ_TXT` | `APPLIC = 01`、`OBJ_TYPE = 01`、`OBJ_ID = ZCHGSB` | `OBJ_SIZE = 8`；EN `ChgSBin`；ZH `换源货位` |

### 4.5 `/SCWM/TEXCEXEH`

活动行：

| LGNUM | EXCCODE | BUSCON | PRMODE | IPRCODE | DIFTY |
|---|---|---|---|---|---|
| `1710` | `ZCSB` | `TPI` | `05` | `BIDU` | `1` |

当前还存在过期行：

| LGNUM | EXCCODE | BUSCON | PRMODE | IPRCODE | 状态 |
|---|---|---|---|---|---|
| `0001` | `ZCSB` | `TPI` | `05` | `BIDF` | 过期，1710 不使用 |
| `1710` | `ZCSB` | `TIM` | `05` | `BIDF` | 过期，不要使用 |

必须使用 `BIDU`。`BIDF` 只更新内存并返回 `PIMTTO`，不会创建新 WT。
保留 `1710 / TPI / 05 / BIDU` 行。

### 4.6 `/SCWM/TEXCEPT` 描述

`ZCSB` 有多种语言的描述。`0001/E` 和 `1710/E` 是 `Change Source Bin`；
`0001/1` 是 `换源货位`。

> **已知清理项：** 当前 `1710/1` 文本是 `拒绝全部提货`，这是从标准
> “拒绝全部拣货”文本继承来的。如果 RF 状态栏或异常清单需要显示正确描述，
> 请把 `1710`/`ZCSB` 文本改为 `Change Source Bin` / `换源货位`。

### 4.7 不需要 `/SCWM/TEXCOIE` 和 `/SCWM/TPARAM_CAT`

PAI 直接调用 `SET_SHORTCUT( 'ZCSB' )`，因此不需要 `/SCWM/TEXCOIE` 条目。

屏幕字段使用 TOP include 中的函数组全局结构 `GS_CHGSB_SCR`。PBO/PAI 保持标准
`PIMTTO` 的 CHANGING 签名。没有在 `/SCWM/TPARAM_CAT` 中注册自定义应用参数容器。

### 4.8 传输与部署

| 内容 | 传输 | 说明 |
|---|---|---|
| 代码（`ZEWM_FG_RF_ZCHGSB`、屏幕 9100、类 `ZCL_ZEWM_RMS_DET_CHGSB`） | `S4HK902806` | 任务 `S4HK902807` |
| BAdI 实现 `ZEWM_ZCHGSB_RMS_DET` | `S4HK902812` | 所有者 `REC3WX` |
| 配置（`TSTEP_SCR`、`TSTEP_FLOW`、`TFCOD_PRF`、`TEXCEXEH` 等） | `S4HK902808` | 按本节手工配置 |
| 消息类 `ZEWM_RF_MSG` 012–017 | `S4HK902782` | 任务 `S4HK902810`，与 ZDIFHU 共用 |

新离线系统的推荐导入顺序：

1. 消息 `S4HK902782`（如果消息类还不存在，也可以手工创建 012–017）。
2. 代码 `S4HK902806`。
3. BAdI `S4HK902812`。
4. 按本节手工配置 `S4HK902808`。

如果 `ZEWM_RF_MSG` 已经由 ZDIFHU 导入，则不需要再导入消息传输。

**abapGit：**abapGit 只用于最终统一导出/归档源码。它不能替代配置表、消息类、
屏幕 9100 或 BAdI ENHO 的部署机制。要让系统真正可运行，请导入传输请求。

导入后验证：

- `SE19` 中 `ZEWM_ZCHGSB_RMS_DET` 处于活动状态，增强点
  `/SCWM/ES_CORE_RMS`，BAdI `/SCWM/EX_CORE_RMS_DETERMINE`，类
  `ZCL_ZEWM_RMS_DET_CHGSB`。
- `SAPLZEWM_FG_RF_ZCHGSB` 中存在屏幕 `9100`。
- `/SCWM/TSTEP_FLOW` 有上述五行。
- `/SCWM/TEXCEXEH` 有 `1710 / TPI / 05 / BIDU` 行。
- `ZEWM_RF_MSG` 有 012–017 及所需语言。
- 如果目标仓库不是 `1710`，调整 `TEXCEXEH` 的 `LGNUM`。

## 5. 验收清单

- [ ] 在 `PIMTTO` 按 F11 能打开屏幕 9100，并显示当前拣货行。
- [ ] 物料、描述、源货位、源类型、目标数量、HU、批次显示正确。
- [ ] 目标数量单位显示为外部单位（`ST -> PC`、`KAR -> CAR`）。
- [ ] 新货位为空时回车显示消息 013，并停留在 9100。
- [ ] 新货位与当前货位相同时显示消息 014。
- [ ] 货位不存在、存储类型错误、冻结或拣货被阻止时显示消息 017，
      并且**不**显示 `e036`。
- [ ] 有效且库存足够的货位能继续，无消息。
- [ ] 有效但库存不足的货位显示 `e036`，不创建新 WT。
- [ ] BACK 返回 `PIMTTO`，清除上下文，不创建新 WT。
- [ ] 成功执行后，原 WT 按数量 `0` 确认，生成货位拒绝，创建新 WT，
      新 WT 的货位是扫描货位。
- [ ] 新 WT 不使用旧货位，也不使用策略选择的其他货位。
- [ ] BAdI 处于活动状态，指向 `/SCWM/EX_CORE_RMS_DETERMINE` 和
      `ZCL_ZEWM_RMS_DET_CHGSB`。
- [ ] 同一 RF 会话第二次执行时，退出到 RF 主菜单再重新进入，不会出现
      “只允许一个差异异常”的错误。

## 6. 故障排查

1. **新 WT 建到了别的货位。**
   - 检查 BAdI 实现 `ZEWM_ZCHGSB_RMS_DET` 是否活动，是否分配给
     `/SCWM/EX_CORE_RMS_DETERMINE`（不是 `EX4`）。
   - 检查类是否为 `ZCL_ZEWM_RMS_DET_CHGSB`。
   - 检查 `IV_CALL = 'C'`；其他调用会直接返回。
   - 检查 PAI 是否导出了 `ZCHGSB_CTX`，以及上下文是否已被提前消费。
   - 检查 `LGNUM` 是否匹配；检查 `IT_QMAT` 中是否有
     `LGPLA = 扫描货位` 的行。
   - 检查 BAdI 是否有过滤器排除了该 WT 类型。

2. **没有新 WT，RF 静默返回 `PIMTTO`。**
   - 检查 `/SCWM/TEXCEXEH`：`1710 / TPI / 05` 行的 `IPRCODE` 必须是 `BIDU`。
   - `BIDF` 只改内存。这是最常见的配置错误。

3. **假货位显示 `e036`（“无法确定可用库存”），而不是 `e017`。**
   - PAI 在 `e017` 分支后缺少 `RETURN`。校验链中每个 `MESSAGE` 后都必须
     `RETURN`。
   - 库存检查必须是最后一个检查。

4. **报“只允许一个差异异常”（`e090`）。**
   - RF 会话内存中还有差异异常。退出 RF 到主菜单再重新进入；不要在同一会话重试。

5. **单位显示 `ST` 或 `KAR`，不是 `PC` 或 `CAR`。**
   - PBO 必须对 `ALTME` 使用 `CONVERSION_EXIT_CUNIT_OUTPUT`。
   - `T006A`：`KAR -> CAR`，`ST -> PC`。

6. **库存预检查拒绝了明显有库存的货位。**
   - 检查可选范围：`CAT`、`STOCK_USAGE`、`OWNER`、`ENTITLED` 只在 RF 字段非空时
     添加。空范围不能加。
   - 检查目标单位：先 `ALTME`，再 `MEINS`。
   - 检查汇总：`ALTME` 用 `QUANA`，`MEINS` 用 `QUAN`。
   - 检查 RF 行上的物料/批次。

7. **新货位字段不可输入。**
   - PBO 必须调用 `SET_SCRELM_INPUT_ON( 'GS_CHGSB_SCR-NEWLGPLA' )`。
   - 不要设置 `REQU_ENTRY`；空值由 PAI 检查。

8. **手工重建后屏幕布局不对。**
   - 屏幕 9100 是类型 `I`，15 行 x 26 列，使用 9 行。
   - 标签在第 1 列；值在第 12 列，宽度 14。
   - 第 2 行是 `MAKTX`，C1/N26；第 8 行是静态文本，C1/N21。
   - 每个 `TEXT` 必须有 `NAME`；模板文本必须是 `space`。
   - 用 `RPY_DYNPRO_READ` 和 `D020S` 验证。

9. **有效拣货行却报消息 012。**
   - `ORDIM_CONFIRM-TANUM` 为空，说明 PBO 没有读到当前行。
   - 检查 `GET_LINE( )` 和 `READ TABLE TT_ORDIM_CONFIRM` 的回退。

10. **`1710` 的异常描述不对。**
    - 把 `TEXCEPT` 的 `1710 / ZCSB` 文本改为 `Change Source Bin` / `换源货位`。
    - `0001` 已经是正确文本。

## 7. 方案 B — 手工重建屏幕 9100

只有在屏幕无法导入时才需要。在函数组 `ZEWM_FG_RF_ZCHGSB` 中创建屏幕 `9100`：

- 类型 `I`，15 行 x 26 列；
- 标签在第 1 列，值在第 12 列，长度 14；
- 字段按 3.2 节的表；
- `NEWLGPLA` 作为输入字段，不设置 `REQU_ENTRY`；
- 第 8 行静态文本 `Scan New Storage Bin`。

保存后验证 `D020S`：`TYPE = 'I'`，`BZMX = 9`，`BZBR = 26`，`NOLI = 15`，
`NOCO = 26`。然后验证 PBO 启用了 `NEWLGPLA`，PAI 读取
`GS_CHGSB_SCR-NEWLGPLA`。

## 8. 对象清单

| 对象 | 名称 | 描述 |
|---|---|---|
| 函数组 | `ZEWM_FG_RF_ZCHGSB` | RF 函数组 |
| 主程序 | `SAPLZEWM_FG_RF_ZCHGSB` | 主程序 |
| TOP include | `LZEWM_FG_RF_ZCHGSBTOP` | `GS_CHGSB_SCR` |
| PBO FM | `ZEWM_RF_ZCHGSB_9100_PBO` | 填充屏幕 9100 |
| PAI FM | `ZEWM_RF_ZCHGSB_9100_PAI` | 校验、预检查、导出上下文 |
| 屏幕 | `9100` | 新源货位屏幕 |
| BAdI 类 | `ZCL_ZEWM_RMS_DET_CHGSB` | RMS 货位过滤 |
| BAdI 实现 | `ZEWM_ZCHGSB_RMS_DET` | `/SCWM/ES_CORE_RMS` 中的 ENHO |
| BAdI 定义 | `/SCWM/EX_CORE_RMS_DETERMINE` | SAP 增强点 `/SCWM/ES_CORE_RMS` |
| BAdI 接口 | `/SCWM/IF_EX_CORE_RMS_DETERMINE` | SAP 接口 |
| 消息类 | `ZEWM_RF_MSG` | 消息 012–017 |
| 异常代码 | `ZCSB` | RF 异常 |
| 功能码 | `ZCHGSB` | `PIMTTO` 上的 F11 键 |
| 配置 | `/SCWM/TSTEP_SCR` | 屏幕分配 |
| 配置 | `/SCWM/TSTEP_FLOW` | 步骤流 |
| 配置 | `/SCWM/TFCOD_PRF` | 功能键 |
| 配置 | `/SCWM/TFCOD_CAT` | 功能码目录 |
| 配置 | `/SCWM/TSTEP_CAT` | 步骤目录 |
| 配置 | `/SCWM/TEXCEXEH` | 异常控制 |
| 配置 | `/SCWM/TEXCEPT` | 异常代码文本 |
| 配置 | `/SCWM/TOBJ_TXT` | RF 对象文本 |
