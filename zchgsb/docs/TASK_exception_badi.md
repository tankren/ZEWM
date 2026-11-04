# 任务：ZCHGSB 改用标准 Exception 流程 + BAdI 过滤候选 quant

> 给 opencode 的任务书。开工前请先读 `docs/STATUS.md` 了解背景。
> 目标读者：全新会话，没有任何上下文。

## 1. 背景

正在开发 EWM RF 拣货增强：在 **PIMTTO** 屏幕给一个 **CHGSB（Change Source Bin）** 按钮，
拣货时扫码更换源货位并重建 WT。

当前已建好并激活的对象（包 `ZEWM`，传输 `S4HK902806`）：

| 对象 | 名称 |
|---|---|
| 函数组 | `ZFG_RF_CHGSB` |
| TOP include | `LZFG_RF_CHGSBTOP`（声明 `gs_chgsb_scr`） |
| FM PBO | `Z_RF_CHGSB_0100_PBO` |
| FM PAI | `Z_RF_CHGSB_0100_PAI` |
| 屏幕 | `SAPLZFG_RF_CHGSB` 屏幕 `9100` |
| 消息 | `ZEWM_RF_MSG` 012–017（中/英/德/法/捷） |
| SM34 | `/SCWM/RF_CUSTOM` 七张表已配好（见 STATUS.md 第四节） |

本地源码：`zchgsb/src/zfg_rf_chgsb.fugr.z_rf_chgsb_0100_{pbo,pai}.abap`

## 2. 问题（实测结果）

RF 实测：扫新货位 → 回车后 **WT 被「带数量」确认了，新 WT 也没建出来**。

根因分析：现有 PAI 是「手搓标准确认」，即

```abap
ordim_confirm-ndifa = vsola.
ordim_confirm-nista = 0.
CALL FUNCTION '/SCWM/RF_PICK_ORDIM_CONFIRM'
COMMIT WORK AND WAIT.
CALL FUNCTION '/SCWM/TO_CREATE' ...
```

`RF_PICK_ORDIM_CONFIRM` 内部走 `CL_RF_CONFIRM_PICKING->CONFIRM`，确认数量并不采信我们赋的
`ndifa/nista`（大概率取自屏幕上屏的实拣数量或其它字段），所以确认成了全量，数量没释放，
后面 `TO_CREATE` 自然也没意义。

## 3. 决策方案

**放弃「手搓确认 + 自建 WT」，改用标准 exception code 链路**：

| 步骤 | 由谁负责 |
|---|---|
| 扫码、存新货位 | 我们的 PAI |
| 0 数量确认 + 记录差异 | **标准 exception code** |
| 拒绝原货位（bin denial） | **标准** |
| 重新确定货位 | 标准 `REM_BIN_DET` + **我们的 BAdI 过滤** |
| 建新 WT（含 ODO 参考 / WHO / 波次） | **标准** |

### 3.1 关键 BAdI

- BAdI 定义：**`/SCWM/EX4_CORE_RMS_DETERMINE`**
- 接口：**`/SCWM/IF_EX_CORE_RMS_DETERMINE`**
- 现有默认实现类：`/SCWM/CL_EI_CORE_RMS_DETERMINE`

接口签名（原文）：

```abap
interface /SCWM/IF_EX_CORE_RMS_DETERMINE
  public .
  interfaces IF_BADI_INTERFACE .

  methods DETERMINE
    importing
      value(IV_CALL) type /SCWM/DE_RBDCALL
      value(IV_ANFML) type /SCWM/DE_QUANTITY
      value(IV_VORGA) type /SCWM/LTAP_VORGA
      !IS_LTAP type /SCWM/LTAP
      !IS_MAT_GLOBAL type /SCWM/S_MATERIAL_GLOBAL
      !IS_MAT_LGNUM type /SCWM/S_MATERIAL_LGNUM
      !IS_MAT_HAZARD type /SCWM/S_MATERIAL_HAZARD
      !IT_MAT_UOM type /SCWM/TT_MATERIAL_UOM
      !IS_T331 type /SCWM/T331
      !IS_T333 type /SCWM/T333
      !IT_QMAT type /SCWM/TT_AQUA_INT
      !IT_QMAT_STD type /SCWM/TT_AQUA_INT
      value(IV_REM_RULE) type /SCWM/DE_REM_RULE optional
      !IO_LOG type ref to /SCWM/CL_LOG optional
      !IV_ROW type BAPI_LINE optional
    exporting
      !ET_QMAT_CUS type /SCWM/TT_AQUA_INT
      !EV_SET type XFELD
    changing
      !CS_ORDIM_CUST type /SCWM/INCL_EEW_S_ORDIM
      !CS_ORDIM_CUST_S4 type /SCWM/INCL_EEW_S_ORDIM_PS optional .
endinterface.
```

- `IT_QMAT` = 系统算出的候选 quant（每条带 `lgnum/lgtyp/lgpla`）
- `ET_QMAT_CUS` = 我们返回的候选
- `EV_SET = 'X'` 表示「用我的，别用标准的」

`/SCWM/REM_BIN_DET` 的调用方式（第 259 行起）：

```abap
SORT lt_stckscore BY score DESCENDING.
LOOP AT lt_stckscore ASSIGNING <stckscore>.
  PERFORM rem_bin_det_call ...   " 内部会触发上面的 BAdI
  IF NOT ls_ltap-vlpla IS INITIAL.  EXIT.  ENDIF.
```

## 4. 具体任务

### 任务 A：改造 `Z_RF_CHGSB_0100_PAI`

文件：`zchgsb/src/zfg_rf_chgsb.fugr.z_rf_chgsb_0100_pai.abap`

1. **保留**：
   - 前置校验（`e012`/`e013`/`e014`）
   - `/SCWM/BIN_EXIST_CHECK` 货位校验（**注意：不是 `RF_PICK_BIN_CHECK`，那个已废弃**）
2. **删除**：
   - `ordim_confirm-ndifa/nista` 赋值
   - `CALL FUNCTION '/SCWM/RF_PICK_ORDIM_CONFIRM'` 及其 COMMIT
   - `CALL FUNCTION '/SCWM/TO_CREATE'` 整段
   - 相关局部变量（`lt_create`、`ls_create`、`et_ltap_vb` 等）
3. **新增**：把扫描的新货位写进内存（按 TANUM 键，避免多会话串）

```abap
DATA: BEGIN OF ls_ctx,
        tanum TYPE /scwm/tanum,
        bin   TYPE /scwm/de_lgpla,
      END OF ls_ctx.

ls_ctx-tanum = ordim_confirm-tanum.
ls_ctx-bin   = gs_chgsb_scr-newlgpla.
EXPORT ls_ctx TO MEMORY ID 'ZCHGSB_BIN'.
```

4. **改为触发标准 exception 链路**，用**自建异常码 `ZCSB`**（不要直接用 `BIDF`）：

   | 组成 | 值 |
   |---|---|---|
   | `EXCODE`（异常代码） | **`ZCSB`** ← 新建，自定义 |
   | 内部流程代码（Process Code） | **`BIDF`** |
   | 业务上下文 | **`TPI`** |
   | 执行步骤 | **`05`** |

   设计意图：`ZCSB` 内部沿用标准 `BIDF` 处理逻辑（货位差异 → 拒绝原货位 → 剩余数量重新确定），
   但**异常码本身是自定义的**，这样标准 `BIDF` 的其它业务场景不受影响，
   而 `ZCSB` 可以作为「BAdI 是否生效」的开关（只有 `ZCSB` 链路才设内存、才过滤 bin）。

    前置：先在 SPRO → EWM → Cross-Process Settings → Exception Codes 里建 `ZCSB`，
   内部流程代码指定 `BIDF`。表名不要猜，用 MCP/TADIR 核实后再写入。

   然后参照 `/SCWM/RF_PICK_EXCEPTION` 的签名与 `/SCWM/RF_PICK_PIMTTO_PAI` 里 `EXCEPT`
   分支的调用方式触发，**不要自行发明其它 code**。

5. 处理完记得 `FREE MEMORY ID 'ZCHGSB_BIN'.`

### 任务 B：新建 BAdI 实现

1. 为 BAdI 定义 `/SCWM/EX4_CORE_RMS_DETERMINE` 创建实现（包 `ZEWM`，传输 `S4HK902806`）
2. 实现 `DETERMINE`：

```abap
METHOD /scwm/if_ex_core_rms_determine~determine.

  DATA: BEGIN OF ls_ctx,
          tanum TYPE /scwm/tanum,
          bin   TYPE /scwm/de_lgpla,
        END OF ls_ctx.

* 默认：一律走标准，绝不干扰其它业务
  ev_set = space.

  IMPORT ls_ctx FROM MEMORY ID 'ZCHGSB_BIN'.
  IF sy-subrc <> 0 OR ls_ctx-bin IS INITIAL.
    RETURN.
  ENDIF.

* 只对本次换货位的 WT 生效
  IF is_ltap-tanum <> ls_ctx-tanum.
    RETURN.
  ENDIF.

  et_qmat_cus = VALUE #( FOR q IN it_qmat
                         WHERE ( lgpla = ls_ctx-bin ) ( q ) ).

  IF et_qmat_cus IS NOT INITIAL.
    ev_set = 'X'.
  ENDIF.

ENDMETHOD.
```

> ⚠️ **这是系统级 BAdI，影响所有剩余货位确定**。`ev_set = space` 的默认分支绝对不能少，
> 不匹配时必须原样交还标准逻辑。

## 4.5 执行方式（重要：分两轮跑）

单个 `opencode run` 的轮次预算有限，**不要一次做完 A+B**，实测会在调研阶段耗尽。

- **第 1 轮 = 任务 B（BAdI）**：接口签名已给全，代码已写好，照抄 + 建对象 + 激活即可
- **第 2 轮 = 任务 A（PAI）**：先读源码，再改；exception code 已定 `BIDF/TPI/05`，不需要再探索

### 任务 C：屏幕 9100 调成 26 列宽

**问题**：RF 设备可视宽度只有 **26 列**，当前屏幕值从第 016 列开始，`TXT` 长度 040，
大量内容超出 26 列显示范围。需要把标签/值之间的空隙压缩，并把屏幕宽度改成 26。

**目标布局**（标签第 001 列，值统一从第 012 列起，宽 14，最长到第 025 列）：

| 行 | 列 | 类型 | 长度 | 字段 / 文本 |
|---|---|---|---|---|
| 002 | 001 | TEXT | 010 | `Source bin` |
| 002 | 012 | TEMPLATE（输出） | 014 | `GS_CHGSB_SCR-VLPLA` |
| 003 | 001 | TEXT | 008 | `Bin type` |
| 003 | 012 | TEMPLATE（输出） | 014 | `GS_CHGSB_SCR-VLTYP` |
| 004 | 001 | TEXT | 008 | `Quantity` |
| 004 | 012 | TEMPLATE（输出） | 014 | `GS_CHGSB_SCR-VSOLA` |
| 005 | 001 | TEXT | 002 | `HU` |
| 005 | 012 | TEMPLATE（输出） | 014 | `GS_CHGSB_SCR-HUIDENT` |
| 006 | 001 | TEXT | 007 | `Product` |
| 006 | 012 | TEMPLATE（输出） | 014 | `GS_CHGSB_SCR-MATNR` |
| 007 | 001 | TEXT | 005 | `Batch` |
| 007 | 012 | TEMPLATE（输出） | 014 | `GS_CHGSB_SCR-CHARG` |
| 009 | 001 | TEXT | 007 | `New bin` |
| 009 | 012 | TEMPLATE（输入） | 014 | `GS_CHGSB_SCR-NEWLGPLA` |
| 011 | 001 | TEMPLATE（输出） | 026 | `GS_CHGSB_SCR-TXT` |

屏幕头改成 `BZBR = 26`（行数不变）。

**注意**：
- 屏幕在系统里，本地仓库没有 `.screen` 文件；先确认 MCP/ADT 能不能改 dynpro
- 改不了就用 `RPY_DYNPRO_INSERT` 重建（注意 `header-type = 'S'`，流程逻辑只有两行，
  且必须重建后核对 `D020S`：`TYPE='S'`、`BZBR=26`）
- 若只能手工 SE51 改，**不要擅自改系统**，直接把需要改的行/列/长度清单输出到报告里
- `NEWLGPLA` **不要**设 `REQU_ENTRY`（RF 里会变成不可输入），仍由 PBO `set_screlm_input_on` 打开

## 4.6 执行顺序（按这个来）

1. **本轮先做任务 A（改 PAI）+ 任务 C（屏幕 26 列）**
2. 改完先验证标准行为：WT 是否被 0 数量确认、是否自动建出新 WT
3. **任务 B（BAdI）晚点再做**，等标准行为跑通、`ZCSB` 配置就位后再上

## 5. 红线与约束

- 只动 `ZEWM` 包下我们自己的对象；**不修改任何 SAP 标准对象**
- 传输统一用 **`S4HK902806`**
- 改完必须激活并做语法检查；有报错先修再报完成
- 字段名/函数名**必须核实存在**，不许按名字推断（有 MCP 可以直接查）
- 数据库里 `RDOCID/RITMID` 是 32 位 GUID 且互不相同；`QDOC` 组常为空 —— 这些细节见 STATUS.md 第六节
- 完成后更新 `docs/STATUS.md`（已完成 / 下一步 / 踩坑）

## 6. 验收标准

RF 实测（S4H client 100）：

1. PIMTTO 屏幕按 `F11`（或第二屏 `PB2`）能进 9100
2. 扫一个有效新货位、回车
3. 原 WT 以 **0 数量 / 差异** 确认，数量释放
4. 系统自动生成新 WT，源货位 = 扫的那个，且 ODO 参考（RDOCCAT/RDOCID/RITMID）完整
5. 其它不相关的 WT 行为不受影响（BAdI 默认分支生效）

---

## 8. 修订记录

- 2026-11-04：exception code 确定为 `BIDF / TPI / 05`；明确分两轮执行（先 BAdI 后 PAI）
- 2026-11-04（二次）：改为自建异常码 **`ZCSB`**（内部流程代码 `BIDF`，`TPI` / `05`），
  `ZCSB` 兼作 BAdI 开关；新增任务 C（屏幕 9100 改 26 列）；
  执行顺序改为 **先 A+C（PAI+屏幕）、验证标准行为，BAdI 晚点再做**

## 7. 参考

- `zchgsb/docs/STATUS.md` —— 对象清单、SM34 实际配置值、消息号、函数签名、18 条踩坑
- `zchgsb/AGENTS.md` —— 项目规则
