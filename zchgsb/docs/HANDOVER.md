# ZCHGSB 交接文档（2026-11-04 13:10）

> 给下一个会话/下一个人的入口。系统：S4H client 100（唯一系统，不碰 ER1）。

## 一、今天做完的事

### 1. 方案转向（关键决策）

**旧方案（已废弃）**：手搓 `ndifa = vsola` / `nista = 0` + `RF_PICK_ORDIM_CONFIRM` + `/SCWM/TO_CREATE`。

实测症状：WT 被**带数量**确认，新 WT 没建出来。

**根因**（已从标准源码确认）：`/SCWM/RF_PICK_EXCEPTION` 里的 `bind_check_and_initiate` 对 `BIDF` 做的正是

```abap
cs_ordim_confirm-ndifa = vsola.
cs_ordim_confirm-nista = 0.
```

确认数量不采信我们直接赋的值，必须走 exception 框架（`exc_tab` + `bind = 'X'`）才会生效。

**新方案（当前）**：标准 exception 链路 + BAdI 限定货位。

| 步骤 | 由谁负责 |
|---|---|
| 扫码、校验新货位 | 我们的 PAI |
| 0 数量确认 + 记录差异 | **标准 exception** |
| 拒绝原货位（bin denial） | **标准** |
| 重新确定货位 | 标准 `REM_BIN_DET` + **我们的 BAdI**（待做） |
| 建新 WT + 文档参考 + WHO/波次 | **标准** |

### 2. 新建异常码 ZCSB（已完成，可传输）

设计意图：`ZCSB` 内部沿用标准 `BIDF`，但异常码本身是自定义的 → 标准 `BIDF` 的其它场景不受影响，`ZCSB` 兼作「BAdI 是否生效」的开关。

已写入（传输任务 `S4HK902809`，请求 `S4HK902808`）：

`/SCWM/TEXCEXEH`（异常码主配置）

| 字段 | 值 |
|---|---|
| `MANDT` | `100` |
| `LGNUM` | `0001` |
| `EXCCODE` | `ZCSB` |
| `BUSCON` | `TPI` |
| `PRMODE` | `05` |
| `IPRCODE` | `BIDF` |
| `DIFTY` | `1` |

`/SCWM/TEXCEPT`（描述）

| SPRAS | LGNUM | EXCCODE | DESCR |
|---|---|---|---|
| `1` | `0001` | `ZCSB` | 换源货位 |
| `E` | `0001` | `ZCSB` | Change Source Bin |

`/SCWM/TSTEP_FLOW`（路由，`CHGSB` 步骤按 `EXCEPT` 跳标准异常处理）

| 字段 | 值 |
|---|---|
| `APPLIC` | `01` |
| `PRES_PRF` | `****` |
| `LTRANS` | `PI****` |
| `STEP` | `CHGSB` |
| `FCODE` | `EXCEPT` |
| `FMODUL` | `/SCWM/RF_PICK_EXCEPTION` |
| `SSTEP` | `PIMTTO` |
| `PRMOD` | `1` |

`/SCWM/TEXCOIE` **不需要动**（标准 `BIDF` 本来就没行，说明不是必经配置）。

### 3. PAI 重写（已写入并激活）

文件：`zchgsb/src/zfg_rf_chgsb.fugr.z_rf_chgsb_0100_pai.abap`（163 行）

改动：

- **删除**：手搓 `ndifa/nista`、`RF_PICK_ORDIM_CONFIRM`、`COMMIT`、整段 `TO_CREATE`、相关局部变量
- **保留**：`e012/e013/e014` 前置校验、`/SCWM/BIN_EXIST_CHECK`、`LAGP` 读取与库存类型/出库冻结/`BIN_ACT_CHECK` 校验
- **新增**：

```abap
DATA: BEGIN OF ls_ctx,
        tanum TYPE /scwm/tanum,
        bin   TYPE /scwm/de_lgpla,
      END OF ls_ctx.
ls_ctx-tanum = ordim_confirm-tanum.
ls_ctx-bin   = gs_chgsb_scr-newlgpla.
EXPORT ls_ctx TO MEMORY ID 'ZCHGSB_BIN'.

/scwm/cl_rf_bll_srvc=>set_shortcut( 'ZCSB' ).
/scwm/cl_rf_bll_srvc=>set_fcode( 'EXCEPT' ).
```

`BACK` 分支会 `FREE MEMORY ID 'ZCHGSB_BIN'` + `clear_shortcut( )`。

## 二、下一步（按顺序）

### 1. RF 实测（先做这个）

进入 PIMTTO → `F11`（第二屏 `PB2`）→ 扫新货位 → 回车。观察：

- 是否不报错、直接回 PIMTTO
- 原 WT 是否被 **0 数量 / 差异** 确认
- 是否自动生成新 WT（此时货位由**系统策略**定，因为是 BAdI 之前）
- `ST22` 是否有 dump（重点看 `RF_PICK_EXCEPTION` / `bind_check_and_initiate`）

### 2. 建 BAdI 实现（让 WT 落在扫描的货位上）

- BAdI 定义：**`/SCWM/EX4_CORE_RMS_DETERMINE`**
- 接口：**`/SCWM/IF_EX_CORE_RMS_DETERMINE`**
- 包 `ZEWM`，传输工作站请求 `S4HK902806`

```abap
METHOD /scwm/if_ex_core_rms_determine~determine.
  DATA: BEGIN OF ls_ctx,
          tanum TYPE /scwm/tanum,
          bin   TYPE /scwm/de_lgpla,
        END OF ls_ctx.

  ev_set = space.            " 默认一律走标准，绝不干扰其它业务

  IMPORT ls_ctx FROM MEMORY ID 'ZCHGSB_BIN'.
  IF sy-subrc <> 0 OR ls_ctx-bin IS INITIAL.
    RETURN.
  ENDIF.
  IF is_ltap-tanum <> ls_ctx-tanum.
    RETURN.
  ENDIF.

  et_qmat_cus = VALUE #( FOR q IN it_qmat WHERE ( lgpla = ls_ctx-bin ) ( q ) ).
  IF et_qmat_cus IS NOT INITIAL.
    ev_set = 'X'.
  ENDIF.
ENDMETHOD.
```

> ⚠️ 系统级 BAdI，`ev_set = space` 默认分支绝对不能少，否则全仓库 bin denial 被改。

### 3. 屏幕 9100 改 26 列（未做）

RF 可视宽度只有 **26 列**，当前值从第 016 列起、`TXT` 长 040，超出显示范围。

目标布局：标签第 001 列，值统一从第 012 列起、宽 014，`TXT` 缩到 026，屏幕头 `BZBR = 26`。

| 行 | 标签 | 值字段 |
|---|---|---|
| 002 | `Source bin` | `VLPLA` |
| 003 | `Bin type` | `VLTYP` |
| 004 | `Quantity` | `VSOLA` |
| 005 | `HU` | `HUIDENT` |
| 006 | `Product` | `MATNR` |
| 007 | `Batch` | `CHARG` |
| 009 | `New bin` | `NEWLGPLA`（输入） |
| 011 | — | `TXT`（长 026） |

`NEWLGPLA` **不要**设 `REQU_ENTRY`（RF 里会变成不可输入），仍由 PBO `set_screlm_input_on` 打开。

**2026-11-04 尝试结果（别再重复踩）**：

- `RPY_DYNPRO_READ_INTO_EXTFORMAT` 在 classrun（`runSnippet`）里**必 dump**，连标准屏
  `/SCWM/SAPLRF_PICKING` `0430` 也一样 → 读不到现有布局，不能"读出改坐标再插回"
- `RPY_DYNPRO_INSERT` 用 `CONTAINERS`（`dycatt_tab`，`type='TEXT'/'TEMPLATE'` + `line/column/length`）
  会返回 `subrc=5`（ILLEGAL_FIELD_VALUE），说明 `CONT-TYPE` 的字面值不是 `TEXT`/`TEMPLATE`
- `D021S` / `D020T` 用 `tableContents` 查是 0 行（数据预览不让看这些系统表）
- 以上尝试均**未破坏**现有屏幕（`D020S` 仍是旧值 `type=I / lines=11 / cols=40`）
- 结论：布局改动要么在 **SE51** 手工改（2 分钟，见上表），要么拿到 `RPYTY_DYNP_CTYPE`
  的合法常量值后再试一次 `RPY_DYNPRO_INSERT`

### 4. zchgsb 独立 abapGit 仓库（未做）

现有仓库 `github.com/tankren/ZEWM` 起始目录 `/zdifhu/src/`，只管辖 zdifhu。zchgsb 需另建仓库、起始目录 `/zchgsb/src/`。

## 三、已验证的事实（别重复查）

### 标准对象

- `/SCWM/REM_BIN_DET`（FG `/SCWM/L03B`）入参只有 `it_lagp_excl` / `it_hu_excl`（**排除**），**不能限定单一货位**；内部按 `STCKDET_GET_SCORE_TAB` 评分降序遍历，`PERFORM rem_bin_det_call` 拿到第一个可行货位就 `EXIT`
- `objectEnhancements` 对 `REM_BIN_DET` / `STCKDET_GET_SCORE_TAB` 均返回 0 个增强点
- `/SCWM/RF_PICK_EXCEPTION`：`get_shortcut( )` 有值就用，否则按 fcode `SKFD`/`EXCEPT` 查 `/SCWM/TEXCOIE` 得外部码；然后 `verify_exception_code` 校验，按 `iprcode` 分支；`BIDF` → `bind_check_and_initiate`
- `/SCWM/BIN_EXIST_CHECK` 是当前用的货位校验（`RF_PICK_BIN_CHECK` 已废弃不用）
- `/SCWM/RF_PICK_PIMTTO_PAI` 里**没有** `EXCEPT` 分支，异常处理是 `TSTEP_FLOW` 配置驱动
- `/scwm/cl_rf_bll_srvc=>set_shortcut( )` / `get_shortcut( )` / `clear_shortcut( )` 均存在

### 传输登记（踩过的坑）

- `E071K` 主键是 `TRKORR + PGMID + OBJECT + OBJNAME + AS4POS`，**`TABKEY` 不是主键**。用 `MODIFY` 不设 `AS4POS` 会覆盖同一条记录
- `TABKEY` 拼接：所有键字段按 DDIC 顺序直接连，**HANA 上尾部空格会被去掉**（所以 `CHGSB` + `EXCEPT` 是 `CHGSBEXCEPT`，中间没有空格）
- 现有 CUST 传输：请求 `S4HK902808`（`W`）/ 任务 `S4HK902809`（`Q`），描述 “RF customizing CHGSB: /SCWM/RF_CUSTOM entries”
- 工作站传输：请求 `S4HK902806`（`K`）/ 任务 `S4HK902807`（`S`）
- MCP 的 `userTransports` 对 `MCP_USER` 返回空，要用 `tableContents` 查 `E070`（注意 `E070` 没有 `AS4TEXT`，描述在 `E07T`）

### 消息

`ZEWM_RF_MSG` 已占用 001–003、006–011；本项目用 **012–017**，不动现有消息。走 SE91，需中/英/德/法/捷 5 语言。

### 工具

- 直连 MCP（不经 opencode）：`node /tmp/mcp_call.js <toolName> '<jsonArgs>'` 或 `@file.json`
- 写表 + 记 TR：`runSnippet`（临时类走 `$TMP`，可 `MODIFY` 表 + 写 `E071K` + `COMMIT`）
- `pkill -f 'opencode run'` **会杀掉自己**（命令行含该串），要按 PID 杀或用 python 遍历 `/proc`
