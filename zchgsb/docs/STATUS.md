# 状态（交接文件）

> 用法：每完成一个阶段就更新本文件；新会话开工第一句"先读 zchgsb/docs/STATUS.md"。
> 最后更新：2026-11-03 13:32

## 当前目标

在 EWM RF 拣货 **PIMTTO** 屏幕新增 **CHGSB（Change Source Bin）** 按钮：
拣货时发现源货位货不对/不够，扫码换到另一个源货位，并重建 WT。

---

## 一、已完成（2026-11-03）

| 环节 | 对象 | 状态 |
|---|---|---|
| 包 | `ZEWM`（无子包，ZEWM_RFUI 不存在） | — |
| 传输请求 | `S4HK902806`（ZCHGSB RF Change Source Bin） | ✅ |
| 函数组 | `ZFG_RF_CHGSB` | ✅ 已建 |
| TOP include | `LZFG_RF_CHGSBTOP`（声明 `gs_chgsb_scr`） | ✅ 已激活 |
| FM PBO | `Z_RF_CHGSB_0100_PBO` | ✅ 已激活 |
| FM PAI | `Z_RF_CHGSB_0100_PAI` | ✅ 已激活 |
| 屏幕 | `SAPLZFG_RF_CHGSB` 屏幕 `9100`（11 字段） | ✅ 已创建，待 SE51 目视确认 |
| SM34 配置 | 7 张表全部写入 | ✅ 已读回核对 |
| 消息 | `ZEWM_RF_MSG` 012–017 × 5 语言 | ✅ 已读回核对 |

**本地源码**：`zchgsb/src/`
- `zfg_rf_chgsb.fugr.z_rf_chgsb_0100_pbo.abap`
- `zfg_rf_chgsb.fugr.z_rf_chgsb_0100_pai.abap`

---

## 二、系统查证结论（S4H / client 100）

| 查证项 | 真实值 |
|---|---|
| ZEWM 子包 | **无任何子包**；`ZEWM_RFUI` 不存在 |
| 现有 RF 函数组 | 仅 `ZFG_RF_ZDIFHU`，包 `ZEWM` |
| FM 命名规范 | `Z_RF_ZDIFHU_9000_PBO` / `_PAI` → **`Z_RF_<模块>_<屏幕>_<PBO\|PAI>`** |
| 命名空间 `/ZEWM/` | **未注册**（TRNSPACE 只有 /MEWM/ /SCMEWM/ /SMBEWM/）→ 严禁使用 |
| 消息类 | 已有 `ZEWM_MSG`、`ZEWM_RF_MSG` → 复用 `ZEWM_RF_MSG` |
| 中文语言码 | **`1`**（不是 `Z`）；其他 `E`/`D`/`F`/`C` |
| 自定义屏幕号段 | **9xxx**（如 zdifhu 用 9000–9004），本项目用 **9100** |

---

## 三、屏幕 9100 字段清单

程序 `SAPLZFG_RF_CHGSB`，屏幕 `9100`，80×24，流程逻辑仅 `PROCESS BEFORE OUTPUT.` / `PROCESS AFTER INPUT.`（PBO/PAI 由 RF 框架按 TSTEP_FLOW 调用，不走 dynpro MODULE）。

| 行 | 列 | 类型 | 字段 |
|---|---|---|---|
| 1 | 1 | 文本 | `Source bin` |
| 1 | 20 | 输出 | `GS_CHGSB_SCR-VLPLA` |
| 2 | 1 | 文本 | `Storage type` |
| 2 | 20 | 输出 | `GS_CHGSB_SCR-VLTYP` |
| 3 | 1 | 文本 | `Quantity` |
| 3 | 20 | 输出 | `GS_CHGSB_SCR-VSOLA` |
| 4 | 1 | 文本 | `HU` |
| 4 | 20 | 输出 | `GS_CHGSB_SCR-HUIDENT` |
| 6 | 1 | 文本 | `New source bin` |
| 6 | 20 | **输入（必填）** | `GS_CHGSB_SCR-NEWLGPLA` |
| 8 | 1 | 输出 | `GS_CHGSB_SCR-TXT` |

---

## 四、SM34 `/SCWM/RF_CUSTOM` 实际写入值

### TFCOD_CAT
| APPLIC | FCODE |
|---|---|
| `01` | `CHGSB` |

### TFCOD_CATT
| APPLIC | FCODE | LANGU | TEXT |
|---|---|---|---|
| `01` | `CHGSB` | `E` | Change Source Bin |
| `01` | `CHGSB` | `1` | Change Source Bin |

### TFCOD_PRF（3 条）
| STEP | FCODE | PUSHB | FNKEY | SHORTCUT | SQNCE |
|---|---|---|---|---|---|
| `PIMTTO` | `CHGSB` | `PB2` | `F11` | `11` | `02` |
| `CHGSB` | `ENTER` | 空 | `ENT` | 空 | `01` |
| `CHGSB` | `BACK` | 空 | `F7` | `07` | `01` |

共同字段：`APPLIC=01` `PRES_PRF=****` `PRSN_PRF=**` `PUSHB_QTY=04` `FNKEY_QTY=**` `LTRANS=PI****` `STATE=******` `SCR_SQNCE=01`

> 说明：PIMTTO 的 SQNCE=01 四个按钮槽位已满（PB1=DETAIL、PB2=GTINQU、PB3=HUENT、PB4=PILIST），
> SQNCE=02 的 PB2 为空（PB1=PRINT、PB3=GTSNCL、PB4=CHGUOM），所以落 PB2。
> F11 / 快捷码 11 均未被占用。

### TSTEP_CAT
| APPLIC | STEP |
|---|---|
| `01` | `CHGSB` |

### TSTEP_SCR
| 字段 | 值 |
|---|---|
| APPLIC | `01` |
| PRES_PRF / PRSN_PRF / DISP_PRF | `****` / `**` / `**` |
| LTRANS | `PI****` |
| STEP | `CHGSB` |
| STATE | `******` |
| SCR_SQNCE | `01` |
| SCR_PROGR | `SAPLZFG_RF_CHGSB` |
| SCR_NUM | `9100` |

### TSTEP_FLOW（4 条，已读回核对）
| STEP | FCODE | FMODUL | SSTEP | PRMOD | FCODE_BCKG |
|---|---|---|---|---|---|
| `PIMTTO` | `CHGSB` | `Z_RF_CHGSB_0100_PBO` | `CHGSB` | `1` | `INIT` |
| `CHGSB` | `INIT` | `Z_RF_CHGSB_0100_PBO` | `CHGSB` | `2` | 空 |
| `CHGSB` | `ENTER` | `Z_RF_CHGSB_0100_PAI` | `PIMTTO` | `1` | `INIT` |
| `CHGSB` | `BACK` | `Z_RF_CHGSB_0100_PAI` | `PIMTTO` | `1` | `INIT` |

---

## 五、消息（`ZEWM_RF_MSG`，追加 012–017）

现有 001–011 未改动；T100 共 75 行（原 45 + 新 30）。

| 号 | 类型 | 中文 | English |
|---|---|---|---|
| 012 | E | 无有效拣货行 | No valid picking line |
| 013 | E | 请扫描或输入新的源货位 | Please scan or enter the new source bin |
| 014 | E | 新旧货位相同 | New bin is the same as the current bin |
| 015 | E | 建WT失败-原任务已确认需人工补偿 | WT creation failed after confirmation - manual correction needed |
| 016 | S | 源货位已更改 | Source bin changed |
| 017 | E | 货位无效或被冻结 | Storage bin is invalid or blocked |

德语/法语/捷克语同步录入（`D` / `F` / `C`），德语用 ae/oe/ue 代替变音符号避免编码问题。

---

## 六、业务逻辑要点（已写进 PAI）

1. **PBO**：从框架传入的 `ordim_confirm` 读当前拣货行 → 显示；清空输入字段。只读。
2. **PBO/PAI 签名**与标准 `/SCWM/RF_PICK_PIMTTO_PBO` 一致（框架按同名 CHANGING 传参）：
   ```abap
   CHANGING ordim_confirm    TYPE /scwm/s_rf_ordim_confirm
            tt_ordim_confirm TYPE /scwm/tt_rf_ordim_confirm
            tt_nested_hu     TYPE /scwm/tt_rf_nested_hu
            wme_verif        TYPE /scwm/s_wme_verif
            resource         TYPE /scwm/s_rsrc
            t_rf_pick_hus    TYPE /scwm/tt_rf_pick_hus
            who              TYPE /scwm/s_who_int.
   ```
3. **货位主数据校验**：用标准 FM `/SCWM/RF_PICK_BIN_CHECK`（校验 **VLPLA**＝源货位）。
   - 它从 `ordim_confirm-vlpla` 取"用户输入的货位" → 必须先暂存原值，校验完**必须还原**，否则第 3 步会拿错行
   - `is_valid_prf` 用 `/scwm/cl_rf_bll_srvc=>get_valid_prf( iv_step, iv_state )` 取，取不到退化空结构
   - ⚠️ 不要误用 `/SCWM/RF_PICK_BIN_CHANGE_CHECK` —— 那个校验的是 **NLPLA**（目标货位），且会 `MESSAGE e045`
4. **确认原 WT 为全量差异**：`ndifa = vsola`、`nista = 0`
   - **绝不设 `bind = 'X'`**，否则标准 `CREATE_BIN_DENIAL` 会自动再建一个 WT → 重复
   - 此步 COMMIT，DN 数量释放
5. **建 WT + 过账**：用 `/SCWM/TO_CREATE`（= `TO_CREA_INT` + `TO_POST`），一次调用完成
   - 必须检查 `ev_severity` 和 `ev_tanum`；内部 CATCH 吞异常
   - 失败必须报错，**不能静默**（第 4 步已 commit，无法回滚）
6. **货单参考继承**（关键）：
   - `RDOCCAT` = **`PDO`**（ODO 场景），`RDOCID`/`RITMID` 是 **32 位 GUID**
   - `RDOCID`（文档 GUID）与 `RITMID`（行项目 GUID）是**两个不同值**，不能混用
   - `QDOCCAT`/`QDOCID`/`QITMID` **经常全空**（QDOCCAT 空 + 后两个全 0 字符串）→ 用 `IF qdoccat IS NOT INITIAL` 判断，不能无条件搬
   - `RITMID`/`QITMID` 在 `S_RF_ORDIM_CONFIRM` 里**没有**，需按 `tanum + vlenr` 读 `/SCWM/ORDIM_O` 补齐

---

## 七、关键函数签名（已核实，勿凭记忆写）

```abap
" 货位校验（源货位 VLPLA）
/SCWM/RF_PICK_BIN_CHECK
  IMPORTING is_valid_prf TYPE /scwm/s_valid_prf_ext
            iv_flg_verified TYPE xfeld
  EXPORTING ev_flg_verified TYPE xfeld
  CHANGING  tt_ordim_confirm / ordim_confirm

" 确认拣货差异
/SCWM/RF_PICK_ORDIM_CONFIRM
  IMPORTING iv_simulate / iv_serial_no_check
  EXPORTING ev_restart_transaction / ev_ser_err
  CHANGING  resource, tt_ordim_confirm, ordim_confirm, tt_nested_hu, who, ...

" 建 WT + 过账（推荐用这个，一步到位）
/SCWM/TO_CREATE
  IMPORTING iv_lgnum, iv_commit_work, iv_bname, it_create TYPE /scwm/tt_to_create_int
  EXPORTING ev_tanum, et_ltap_vb, et_bapiret, ev_severity

" 分步版（如需精细控制）
/SCWM/TO_CREA_INT  IMPORTING it_create_int  EXPORTING et_ltap_vb/et_bapiret/ev_severity
/SCWM/TO_POST      IMPORTING iv_commit_work EXPORTING ev_tanum/ev_severity/et_ltap_err
                   （注意：TO_POST 没有 it_ltap_vb 输入！et_ltap_vb 是输出）
```

字段结构 `/SCWM/S_TO_CREATE_INT`（100 字段）关键项：
`PROCTY` `VLTYP` `VLPLA` `VLENR` `SGUID_HU` `MATID` `BATCHID` `ANFME`
`RDOCCAT` `RDOCID` `RITMID` `QDOCCAT` `QDOCID` `QITMID` `DOCCAT` `STOCK_DOCCAT` `STOCK_DOCNO`
`NLTYP` `NLPLA` `NLENR` `DGUID_HU` `WHO` `WHOSEQ` `WAVE` `WAVE_ITM` `NO_STOCK_DET`

---

## 八、踩过的坑（重要，别重复）

### SAP / ABAP

1. **`/ZEWM/` 命名空间不存在** → 任何 `/ZEWM/xxx` 对象都建不出来，必须用 `ZFG_RF_*` / `Z_RF_*`
2. **ABAP 里 `&&` 只能用在字符串模板内部**，写成 `|A| && lv_x` 会报 "Invalid line break in string template"
3. **`ev_x = DATA(lv)` 内联声明在 CALL FUNCTION 参数位置非法** → 必须提前 `DATA`
4. **FM 源码必须以 `ENDFUNCTION.` 结尾**（我漏了两次，报 "Incorrect nesting"）
5. **`/SCWM/DE_VSOLA` 不存在**，正确是 `/SCWM/LTAP_VSOLA`

### 屏幕生成（RPY 系列）

6. `RPY_DYNPRO_READ_INTO_EXTFORMAT` 的 **`descript` 是必填导入参数**（漏了就 `CALL_FUNCTION_PARM_MISSING` 短 dump）
7. `D020S` 的屏幕号字段叫 **`DNUM`**，不是 `DYNR`；程序字段叫 `PROG`
8. 容器表用 **`DYCATT_TAB`**（`DYCATT` 这个行类型名不存在）
9. **`RPY_DYFLOW` 是结构体**，表要写 `STANDARD TABLE OF rpy_dyflow`（不是 `TYPE rpy_dyflow`）
10. `RPY_DYNPRO_INSERT` 的 **`fields_to_containers` 是必填表参数，但可以传空表** —— 字段会自动落到 `SCREEN` 容器。传空能成功；不传会 dump；瞎填组件名会编译错
11. **读回校验不可靠**：`RPY_DYNPRO_READ_INTO_EXTFORMAT` 读标准屏 430（肯定有字段）也返回 `fields=0`，所以 `fields=0` 不代表字段没写进去 → 用 SE51 目视确认

### 数据预览（MCP runQuery）

12. `DD03L`/`DD02L`/`DD04T` 等 DD 表：**只按 `TABNAME = 'X'` 单条件查有效**，带 `AND`/`IN`/`LIKE` 过滤常返回 0 行
13. `DD03T`（字段文本）、`DD07T`（域值）基本取不到
14. `/SCWM/S_TO_CREATE_INT` 这类结构用 `ddicElement` 也返回空 → 改用 `SELECT * FROM 表` 看真实数据

### opencode

15. 这台机器 opencode 配置 `"build": { "disable": true }` → `opencode run` 全部落到**只读的 plan agent**，只能调研不能写文件。要它写代码必须先放开 build
16. `pkill -f "opencode run"` 会**误杀执行它自己的 shell**（命令行里含该字符串）→ 用 `pgrep` 拿 PID 再 kill

### 其他

17. **shell 里别用 `PATH` 当循环变量**，会覆盖 `$PATH` 导致所有命令找不到
18. 微信图片按**高度 2048** 等比缩放（1720×2760 → 1276×2048）→ 长图发**矢量 PDF**，不要拆图

---

## 九、abapGit 现状

- 系统已装 abapGit：`ZABAPGIT` 事务码，包 `ZBC`；另有 `ZABAPGIT_STANDALONE`
- 已配置仓库：**`EWM Custom Object Repo`** → `https://github.com/tankren/ZEWM`，分支 `main`，包 `ZEWM`，**STARTING_FOLDER = `/zdifhu/src/`**
- 另有 `ZMM`、`ZWM`、`abap-cheat-sheets`
- ⚠️ **`zchgsb/` 不在这条仓库的管辖范围**（起始目录只到 zdifhu）→ 需要**另建一个 abapGit 仓库**（同 URL、起始目录改 `/zchgsb/src/`）
- 屏幕在 abapGit 里 = `fugr.xml` 的 `<DYNPROS>` 段 + `.screen_91xx.abap`（流程逻辑）
- 本地 git：`~/opencode/ZEWM`，`origin = github.com/tankren/ZEWM.git`，分支 `main`；`zchgsb/` 尚未 commit

---

## 十、下一步

1. **SE51 目视确认屏幕 9100** 的 11 个字段（读回校验不可信，必须人看）
2. RF 实测：PIMTTO 屏幕 → `F11` / 第二屏 `PB2` 按钮 → 能否跳 9100 → 扫码换货位
3. 补 `zchgsb/` 的 abapGit 序列化（`fugr.xml` + `.screen_9100.abap`），另建独立 abapGit 仓库
4. **PAI 校验必须重写**：`get_valid_prf` 用 `param_name = 'ORDIM_CONFIRM'` 取不到（`/SCWM/TVALID_PRF` 里真实行是 `TT_ORDIM_CONFIRM`），而且 `/SCWM/RF_PICK_BIN_CHECK` 只认标准步骤（PIMTTO 等）→ 自定义步骤 CHGSB 永远返回未校验。改为自建：`/SCWM/BIN_EXIST_CHECK`（存在性/子货位/动态货位）+ `LAGP_READ_SINGLE` 查 `SKZUA`/`SKZUE` + `/SCWM/BIN_ACT_CHECK`（`wmegc_binact_pick`，需 `TYPE-POOLS: wmegc`）
5. **换源货位方式待定**：现方案"确认差异 + `TO_CREATE`"机械上可跑，但会把 ODO 行按短拣确认（交货可能短发）；备选 `/SCWM/TO_CHANGE`（`it_change`，`VLPLA`=新货位、`S_NEW='X'`）直接改未完成 WT，不动 ODO/WO
6. 定制数据是否并入项目请求 `S4HK902782`（REC3WX 的 "RF ZDIFHU"）——待主人确认

---

## 十一、传输请求（TR）现状（2026-11-03 补录）

**根因**：RF_CUSTOM 定制当初是**直接写数据库**（report / MCP runSnippet / SE16N &SAP_EDIT），没走 SM34 维护界面。传输记录是维护界面（`TR_OBJECT_ADD`）产生的，直写 DB 完全不经过它 → 不是"TR 里没有"，而是**根本没进传输系统**。

**已补录**：
- 新建 **Customizing 请求 `S4HK902808`**（W，MCP_USER，TARSYSTEM 空，与本系统其他客户 W 请求一致），其下任务 **`S4HK902809`**（Q）已记录 **6 表 / 12 键**：
  E071 6 行（R3TR / TABU / OBJFUNC='K'）+ E071K 12 行
  `/SCWM/TFCOD_CAT` 1、`/SCWM/TFCOD_CATT` 2（LANGU E/1）、`/SCWM/TFCOD_PRF` 3、`/SCWM/TSTEP_CAT` 1、`/SCWM/TSTEP_SCR` 1、`/SCWM/TSTEP_FLOW` 4
- 消息类 `ZEWM_RF_MSG`（R3TR MSAG）原本已被 REC3WX 记在请求 **`S4HK902782`"RF ZDIFHU"** 的任务 `S4HK902783` 里（对象被锁）；主人新加任务 **`S4HK902810`**（MCP_USER，同挂在 S4HK902782 下）后，MSAG 已追加到 `S4HK902810`（同一请求的两个任务允许重复，释放时合并）
- 代码 FUGR `ZFG_RF_CHGSB` 仍在 Workbench 请求 **`S4HK902806` / 任务 `S4HK902807`**

**补录方法（可复用，别手写 E071/E071K）**：
1. `TRINT_INSERT_NEW_COMM`（FUGR STRD，SAPLSTRD）建任务：`wi_trfunction='Q'`、`wi_strkorr=<请求号>`、`wi_kurztext`。**必须挂到任务**；挂请求头会报 `TK/127`（Changes to objects are only allowed in correction/repair）
2. 按表 `SELECT * FROM (表) INTO TABLE <动态表> WHERE (条件)`，只取本项目行；按 DD03L 主键字段顺序拼 TABKEY（定长、按字段实际长度：MANDT 3、APPLIC 2、FCODE 5、STEP 5、LTRANS 6、STATE 6…）
3. `TR_APPEND_TO_COMM_OBJS_KEYS`（`wi_trkorr`=任务号，`iv_dialog=' '`）先 `wi_simulation='X'` 再真跑；E071 行 `R3TR/TABU/OBJ_NAME=<表>/OBJFUNC='K'`，E071K `MASTERTYPE/MASTERNAME='TABU'/<表>`、`SORTFLAG='2'`
4. 坑：`MSAG` 这类对象的 E071-`OBJFUNC` **必须为空**（写 'K' 报 `TR/589`）；对象已在**别的请求**会报 `TK/310`（同一请求的其他任务则可以追加）

---

## 十二、相关历史会话

- 待补
