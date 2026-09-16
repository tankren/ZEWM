# ZDIFHU — EWM RF Logical Transaction 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 交付 abapGit 风格源码包，实现 EWM RF 逻辑事务 `ZDIFHU`（HU 盘点差异过账，**3 屏流程**）。

**Architecture:** 包 `ZEWM` + 函数组 `ZFG_RF_ZDIFHU`（屏幕 9000/9001/9002 + **6 个** PBO/PAI FM）+ 4 个 DDIC 对象（结构 `ZSDIFHU_SCR`、`ZSDIFHU_ITEM`、`ZSDIFHU_PROD` + 表类型 `ZSDIFHU_ITEM_TT`）。RF 框架通过 Application Parameter（`CS_ZDIFHU_S_SCR` / `CT_ZDIFHU_T_ITEMS` / `CS_ZDIFHU_PROD`）按名匹配 FM 的 CHANGING 参数传数据；差异过账用 `/SCWM/CL_WM_PACKING=>POST_DIFFERENCE`（**实例方法**：`CREATE OBJECT` + `->`）+ `SAVE` + `COMMIT WORK AND WAIT`。

> ⚠️ **本文档是历史实施计划**：Task 1–11 的代码块记录的是**初版两屏设计**（跑通后被多轮修订）。
> 最终实现以 **README**、本文档 §2 Customizing / §3 Plan B，以及文末「执行后修订 1–5」为准。

**Tech Stack:** SAP S/4HANA embedded EWM（ABAP 7.50+）、abapGit 文件格式。

**Spec:** `docs/superpowers/specs/2026-08-29-zdifhu-rf-transaction-design.md`

---

## 执行环境说明（先读）

1. **本地无法编译/运行 ABAP。** 本计划的"验证" = 文件内容核对 + XML 良构性检查（python3）；最终功能验证在 SAP 系统 abapGit import 后按 README 验收清单执行。
2. **XML 良构检查命令**（每个含 XML 的步骤后用）：

```bash
python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1]); print('OK', sys.argv[1])" <文件>
```

3. **UTF-8 BOM**：abapGit 序列化器输出的 XML 带 BOM；手写文件不带 BOM 也能正常 import（BOM 只影响 git diff 显示"M"），本计划**不强制 BOM**。若要求与 abapGit 字节级一致，可在目标系统首次 pull 后以其输出为准。
4. **非 git 仓库**：不执行 git commit。如需版本管理，执行者可自行 `git init`。
5. **⚠️ 系统校准点**（import 后在 SAP 系统核对，见各任务备注）：
   - 数据元素 `/SCWM/DE_HUIDENT` `/SCWM/DE_QUANTITY` `/SCWM/DE_BASE_UOM` `/SCWM/GUID_HU` `/LIME/GUID_STOCK` 存在性（SE11）
   - `/SCWM/CL_RF_BLL_SRVC=>GET_FCODE` / `SET_FCODE` 静态签名（SE24）
   - 异常码组合 `DIFD`+`PPT`+`16`（SPRO，spec §5.2）
   - 屏幕 9001 的 step-loop XML 若 import 报错 → 按 README "Plan B" 用 SE51 手建

---

## 文件结构（交付清单）

```
zdifhu/
├── .abapgit.xml
├── README.md
├── README.zh.md
├── docs/
└── src/
    ├── package.devc.xml
    ├── zsdifhu_scr.tabl.xml
    ├── zsdifhu_item.tabl.xml
    ├── zsdifhu_item_tt.ttyp.xml
    ├── zsdifhu_prod.tabl.xml
    ├── zewm_rf_msg.msag.xml
    ├── zfg_rf_zdifhu.fugr.xml
    ├── zfg_rf_zdifhu.fugr.saplzfg_rf_zdifhu.abap / .xml
    ├── zfg_rf_zdifhu.fugr.lzfg_rf_zdifhutop.abap / .xml
    ├── zfg_rf_zdifhu.fugr.z_rf_zdifhu_9000_pbo.abap / _pai.abap
    ├── zfg_rf_zdifhu.fugr.z_rf_zdifhu_9001_pbo.abap / _pai.abap
    ├── zfg_rf_zdifhu.fugr.z_rf_zdifhu_9002_pbo.abap / _pai.abap
    ├── zfg_rf_zdifhu.fugr.z_rf_zdifhu_9004_pbo.abap / _pai.abap
    ├── zfg_rf_zdifhu.fugr.screen_9000.abap / screen_9001.abap / screen_9002.abap / screen_9004.abap
    ├── zfg_rf_zdifhu.fugr.i18n.de.po / .cs.po / .fr.po / .zh.po
    └── zewm_rf_msg.msag.i18n.de.po / .cs.po / .fr.po / .zh.po
```

（上表是**最终交付状态**，共 **31 个文件**；Task 1–11 只创建了最初的 15 个文件，后续修订新增了屏幕 9002、
`ZSDIFHU_PROD`、消息类 `ZEWM_RF_MSG`、8 个 LXE 翻译文件，以及屏幕 9004 + `Z_RF_ZDIFHU_9004_PBO/_PAI`。）

命名依据（已与 abapGit 官方测试仓库 `abapGit-tests/FUGR`、`abapGit-tests/FUGR_dynp_template` 核对）：
- FUGR 文件名全小写；include 文件名 = `<fg>.fugr.<include小写名>.abap/.xml`
- FM 源文件 = `<fg>.fugr.<fm小写名>.abap`（参数同时写在 `fugr.xml` 和 FM 文件注释头）
- 屏幕 flow logic = `<fg>.fugr.screen_<4位屏号>.abap`；屏幕定义（HEADER/CONTAINERS/FIELDS）在 `fugr.xml` 的 `<DYNPROS>` 内
- **不需要** `L...UXX`/`L...U01` include 文件（官方测试仓库均无，abapGit import 时系统自动生成）

---

### Task 1: 项目骨架

**Files:**
- Create: `/home/tankren/opencode/zdifhu/.abapgit.xml`
- Create: `/home/tankren/opencode/zdifhu/src/package.devc.xml`
- Create: `/home/tankren/opencode/zdifhu/README.md`（最小版，Task 11 补全）

- [ ] **Step 1: 写 `.abapgit.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<asx:abap xmlns:asx="http://www.sap.com/abapxml" version="1.0">
 <asx:values>
  <DATA>
   <MASTER_LANGUAGE>E</MASTER_LANGUAGE>
   <STARTING_FOLDER>/src/</STARTING_FOLDER>
   <FOLDER_LOGIC>PREFIX</FOLDER_LOGIC>
  </DATA>
 </asx:values>
</asx:abap>
```

- [ ] **Step 2: 写 `src/package.devc.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<abapGit version="v1.0.0" serializer="LCL_OBJECT_DEVC" serializer_version="v1.0.0">
 <asx:abap xmlns:asx="http://www.sap.com/abapxml" version="1.0">
  <asx:values>
   <DEVC>
    <CTEXT>RF ZDIFHU - HU difference posting</CTEXT>
   </DEVC>
  </asx:values>
 </asx:abap>
</abapGit>
```

- [ ] **Step 3: 写最小 `README.md`**

```markdown
# ZDIFHU — EWM RF HU 差异过账

abapGit 交付：RF 逻辑事务 `ZDIFHU`（2 屏 HU 盘点差异过账）。
安装与配置步骤见本文档后续章节（实施完成后补全）。
```

- [ ] **Step 4: 验证**

```bash
cd /home/tankren/opencode/zdifhu && for f in .abapgit.xml src/package.devc.xml; do python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1]); print('OK', sys.argv[1])" "$f"; done
```

预期：两行 `OK ...`。

---

### Task 2: DDIC 结构 ZSDIFHU_ITEM + 表类型 ZSDIFHU_ITEM_TT

**Files:**
- Create: `/home/tankren/opencode/zdifhu/src/zsdifhu_item.tabl.xml`
- Create: `/home/tankren/opencode/zdifhu/src/zsdifhu_item_tt.ttyp.xml`

结构字段（7 个，全部引用数据元素，COMPTYPE=E）：

| POSITION | FIELDNAME | ROLLNAME | 用途 |
|---|---|---|---|
| 0001 | MATNR | MATNR | 物料号 |
| 0002 | MAKTX | MAKTX | 物料描述 |
| 0003 | QUAN | /SCWM/DE_QUANTITY | 当前系统数量 |
| 0004 | MEINS | /SCWM/DE_BASE_UOM | 单位 |
| 0005 | DIFF_QUAN | /SCWM/DE_QUANTITY | 实盘数量（用户输入列） |
| 0006 | GUID_STOCK | /LIME/GUID_STOCK | 库存 GUID（过账定位） |
| 0007 | GUID_HU | /SCWM/GUID_HU | HU GUID（过账定位） |

⚠️ 若某 `/SCWM/DE_*` 数据元素在目标系统不存在（SE11 核对），把该字段改为内建类型：QUAN→`DATATYPE=QUAN LENG=000013 DECIMALS=000003`、MEINS→`DATATYPE=UNIT LENG=000003`、GUID→`DATATYPE=CHAR LENG=000032`，并加 `<MASK>` 同 DATATYPE 值、`COMPTYPE=D`、去掉 ROLLNAME。

- [ ] **Step 1: 写 `zsdifhu_item.tabl.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<abapGit version="v1.0.0" serializer="LCL_OBJECT_TABL" serializer_version="v1.0.0">
 <asx:abap xmlns:asx="http://www.sap.com/abapxml" version="1.0">
  <asx:values>
   <DD02V>
    <TABNAME>ZSDIFHU_ITEM</TABNAME>
    <DDLANGUAGE>E</DDLANGUAGE>
    <TABCLASS>INTTAB</TABCLASS>
    <DDTEXT>RF ZDIFHU HU item line</DDTEXT>
    <EXCLASS>1</EXCLASS>
   </DD02V>
   <DD03P_TABLE>
    <DD03P>
     <TABNAME>ZSDIFHU_ITEM</TABNAME>
     <FIELDNAME>MATNR</FIELDNAME>
     <POSITION>0001</POSITION>
     <ROLLNAME>MATNR</ROLLNAME>
     <ADMINFIELD>0</ADMINFIELD>
     <COMPTYPE>E</COMPTYPE>
    </DD03P>
    <DD03P>
     <TABNAME>ZSDIFHU_ITEM</TABNAME>
     <FIELDNAME>MAKTX</FIELDNAME>
     <POSITION>0002</POSITION>
     <ROLLNAME>MAKTX</ROLLNAME>
     <ADMINFIELD>0</ADMINFIELD>
     <COMPTYPE>E</COMPTYPE>
    </DD03P>
    <DD03P>
     <TABNAME>ZSDIFHU_ITEM</TABNAME>
     <FIELDNAME>QUAN</FIELDNAME>
     <POSITION>0003</POSITION>
     <ROLLNAME>/SCWM/DE_QUANTITY</ROLLNAME>
     <ADMINFIELD>0</ADMINFIELD>
     <COMPTYPE>E</COMPTYPE>
    </DD03P>
    <DD03P>
     <TABNAME>ZSDIFHU_ITEM</TABNAME>
     <FIELDNAME>MEINS</FIELDNAME>
     <POSITION>0004</POSITION>
     <ROLLNAME>/SCWM/DE_BASE_UOM</ROLLNAME>
     <ADMINFIELD>0</ADMINFIELD>
     <COMPTYPE>E</COMPTYPE>
    </DD03P>
    <DD03P>
     <TABNAME>ZSDIFHU_ITEM</TABNAME>
     <FIELDNAME>DIFF_QUAN</FIELDNAME>
     <POSITION>0005</POSITION>
     <ROLLNAME>/SCWM/DE_QUANTITY</ROLLNAME>
     <ADMINFIELD>0</ADMINFIELD>
     <COMPTYPE>E</COMPTYPE>
    </DD03P>
    <DD03P>
     <TABNAME>ZSDIFHU_ITEM</TABNAME>
     <FIELDNAME>GUID_STOCK</FIELDNAME>
     <POSITION>0006</POSITION>
     <ROLLNAME>/LIME/GUID_STOCK</ROLLNAME>
     <ADMINFIELD>0</ADMINFIELD>
     <COMPTYPE>E</COMPTYPE>
    </DD03P>
    <DD03P>
     <TABNAME>ZSDIFHU_ITEM</TABNAME>
     <FIELDNAME>GUID_HU</FIELDNAME>
     <POSITION>0007</POSITION>
     <ROLLNAME>/SCWM/GUID_HU</ROLLNAME>
     <ADMINFIELD>0</ADMINFIELD>
     <COMPTYPE>E</COMPTYPE>
    </DD03P>
   </DD03P_TABLE>
  </asx:values>
 </asx:abap>
</abapGit>
```

- [ ] **Step 2: 写 `zsdifhu_item_tt.ttyp.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<abapGit version="v1.0.0" serializer="LCL_OBJECT_TTYP" serializer_version="v1.0.0">
 <asx:abap xmlns:asx="http://www.sap.com/abapxml" version="1.0">
  <asx:values>
   <DD40V>
    <TYPENAME>ZSDIFHU_ITEM_TT</TYPENAME>
    <DDLANGUAGE>E</DDLANGUAGE>
    <ROWTYPE>ZSDIFHU_ITEM</ROWTYPE>
    <ROWKIND>S</ROWKIND>
    <DATATYPE>STRU</DATATYPE>
    <ACCESSMODE>T</ACCESSMODE>
    <KEYDEF>D</KEYDEF>
    <KEYKIND>N</KEYKIND>
    <DDTEXT>RF ZDIFHU item table</DDTEXT>
   </DD40V>
  </asx:values>
 </asx:abap>
</abapGit>
```

- [ ] **Step 3: 验证**

```bash
cd /home/tankren/opencode/zdifhu && for f in src/zsdifhu_item.tabl.xml src/zsdifhu_item_tt.ttyp.xml; do python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1]); print('OK', sys.argv[1])" "$f"; done
```

预期：两行 `OK ...`；并目视核对 7 个字段 POSITION 连续、ROLLNAME 与上表一致。

---

### Task 3: DDIC 结构 ZSDIFHU_SCR

**Files:**
- Create: `/home/tankren/opencode/zdifhu/src/zsdifhu_scr.tabl.xml`

字段：HUIDENT（/SCWM/DE_HUIDENT，HU 号）、MATNR_SCAN（MATNR，屏幕 2 扫描框）。

- [ ] **Step 1: 写 `zsdifhu_scr.tabl.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<abapGit version="v1.0.0" serializer="LCL_OBJECT_TABL" serializer_version="v1.0.0">
 <asx:abap xmlns:asx="http://www.sap.com/abapxml" version="1.0">
  <asx:values>
   <DD02V>
    <TABNAME>ZSDIFHU_SCR</TABNAME>
    <DDLANGUAGE>E</DDLANGUAGE>
    <TABCLASS>INTTAB</TABCLASS>
    <DDTEXT>RF ZDIFHU screen fields</DDTEXT>
    <EXCLASS>1</EXCLASS>
   </DD02V>
   <DD03P_TABLE>
    <DD03P>
     <TABNAME>ZSDIFHU_SCR</TABNAME>
     <FIELDNAME>HUIDENT</FIELDNAME>
     <POSITION>0001</POSITION>
     <ROLLNAME>/SCWM/DE_HUIDENT</ROLLNAME>
     <ADMINFIELD>0</ADMINFIELD>
     <COMPTYPE>E</COMPTYPE>
    </DD03P>
    <DD03P>
     <TABNAME>ZSDIFHU_SCR</TABNAME>
     <FIELDNAME>MATNR_SCAN</FIELDNAME>
     <POSITION>0002</POSITION>
     <ROLLNAME>MATNR</ROLLNAME>
     <ADMINFIELD>0</ADMINFIELD>
     <COMPTYPE>E</COMPTYPE>
    </DD03P>
   </DD03P_TABLE>
  </asx:values>
 </asx:abap>
</abapGit>
```

- [ ] **Step 2: 验证**

```bash
python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('/home/tankren/opencode/zdifhu/src/zsdifhu_scr.tabl.xml'); print('OK')"
```

预期：`OK`。

---

### Task 4: Function Group 骨架（含 4 个 FM 接口定义）

**Files:**
- Create: `/home/tankren/opencode/zdifhu/src/zfg_rf_zdifhu.fugr.xml`
- Create: `/home/tankren/opencode/zdifhu/src/zfg_rf_zdifhu.fugr.saplzfg_rf_zdifhu.abap`
- Create: `/home/tankren/opencode/zdifhu/src/zfg_rf_zdifhu.fugr.saplzfg_rf_zdifhu.xml`
- Create: `/home/tankren/opencode/zdifhu/src/zfg_rf_zdifhu.fugr.lzfg_rf_zdifhutop.abap`
- Create: `/home/tankren/opencode/zdifhu/src/zfg_rf_zdifhu.fugr.lzfg_rf_zdifhutop.xml`

4 个 FM 接口完全一致（spec §3.0）：`IMPORTING iv_lgnum TYPE /scwm/lgnum`（VALUE 参数）+ `CHANGING cs_zdifhu_s_scr TYPE zsdifhu_scr / ct_zdifhu_t_items TYPE zdifhu_item_tt`。CHANGING 参数名与 Application Parameter 同名（框架按名匹配）。每个参数在 `<DOCUMENTATION>` 中有一条 `<RSFDO>`（KIND=P），省略会导致 abapGit 永久显示 modified。`<DYNPROS>` 在 Task 9/10 追加。

- [ ] **Step 1: 写 `zfg_rf_zdifhu.fugr.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<abapGit version="v1.0.0" serializer="LCL_OBJECT_FUGR" serializer_version="v1.0.0">
 <asx:abap xmlns:asx="http://www.sap.com/abapxml" version="1.0">
  <asx:values>
   <AREAT>RF ZDIFHU - HU difference posting</AREAT>
   <INCLUDES>
    <SOBJ_NAME>LZFG_RF_ZDIFHUTOP</SOBJ_NAME>
    <SOBJ_NAME>SAPLZFG_RF_ZDIFHU</SOBJ_NAME>
   </INCLUDES>
   <FUNCTIONS>
    <item>
     <FUNCNAME>Z_RF_ZDIFHU_9000_PBO</FUNCNAME>
     <SHORT_TEXT>RF ZDIFHU screen 9000 PBO</SHORT_TEXT>
     <IMPORT>
      <RSIMP>
       <PARAMETER>IV_LGNUM</PARAMETER>
       <TYP>/SCWM/LGNUM</TYP>
      </RSIMP>
     </IMPORT>
     <CHANGING>
      <RSCHA>
       <PARAMETER>CS_ZDIFHU_S_SCR</PARAMETER>
       <TYP>ZSDIFHU_SCR</TYP>
      </RSCHA>
      <RSCHA>
       <PARAMETER>CT_ZDIFHU_T_ITEMS</PARAMETER>
       <TYP>ZSDIFHU_ITEM_TT</TYP>
      </RSCHA>
     </CHANGING>
     <DOCUMENTATION>
      <RSFDO>
       <PARAMETER>IV_LGNUM</PARAMETER>
       <KIND>P</KIND>
      </RSFDO>
      <RSFDO>
       <PARAMETER>CS_ZDIFHU_S_SCR</PARAMETER>
       <KIND>P</KIND>
      </RSFDO>
      <RSFDO>
       <PARAMETER>CT_ZDIFHU_T_ITEMS</PARAMETER>
       <KIND>P</KIND>
      </RSFDO>
     </DOCUMENTATION>
    </item>
    <item>
     <FUNCNAME>Z_RF_ZDIFHU_9000_PAI</FUNCNAME>
     <SHORT_TEXT>RF ZDIFHU screen 9000 PAI</SHORT_TEXT>
     <IMPORT>
      <RSIMP>
       <PARAMETER>IV_LGNUM</PARAMETER>
       <TYP>/SCWM/LGNUM</TYP>
      </RSIMP>
     </IMPORT>
     <CHANGING>
      <RSCHA>
       <PARAMETER>CS_ZDIFHU_S_SCR</PARAMETER>
       <TYP>ZSDIFHU_SCR</TYP>
      </RSCHA>
      <RSCHA>
       <PARAMETER>CT_ZDIFHU_T_ITEMS</PARAMETER>
       <TYP>ZSDIFHU_ITEM_TT</TYP>
      </RSCHA>
     </CHANGING>
     <DOCUMENTATION>
      <RSFDO>
       <PARAMETER>IV_LGNUM</PARAMETER>
       <KIND>P</KIND>
      </RSFDO>
      <RSFDO>
       <PARAMETER>CS_ZDIFHU_S_SCR</PARAMETER>
       <KIND>P</KIND>
      </RSFDO>
      <RSFDO>
       <PARAMETER>CT_ZDIFHU_T_ITEMS</PARAMETER>
       <KIND>P</KIND>
      </RSFDO>
     </DOCUMENTATION>
    </item>
    <item>
     <FUNCNAME>Z_RF_ZDIFHU_9001_PBO</FUNCNAME>
     <SHORT_TEXT>RF ZDIFHU screen 9001 PBO</SHORT_TEXT>
     <IMPORT>
      <RSIMP>
       <PARAMETER>IV_LGNUM</PARAMETER>
       <TYP>/SCWM/LGNUM</TYP>
      </RSIMP>
     </IMPORT>
     <CHANGING>
      <RSCHA>
       <PARAMETER>CS_ZDIFHU_S_SCR</PARAMETER>
       <TYP>ZSDIFHU_SCR</TYP>
      </RSCHA>
      <RSCHA>
       <PARAMETER>CT_ZDIFHU_T_ITEMS</PARAMETER>
       <TYP>ZSDIFHU_ITEM_TT</TYP>
      </RSCHA>
     </CHANGING>
     <DOCUMENTATION>
      <RSFDO>
       <PARAMETER>IV_LGNUM</PARAMETER>
       <KIND>P</KIND>
      </RSFDO>
      <RSFDO>
       <PARAMETER>CS_ZDIFHU_S_SCR</PARAMETER>
       <KIND>P</KIND>
      </RSFDO>
      <RSFDO>
       <PARAMETER>CT_ZDIFHU_T_ITEMS</PARAMETER>
       <KIND>P</KIND>
      </RSFDO>
     </DOCUMENTATION>
    </item>
    <item>
     <FUNCNAME>Z_RF_ZDIFHU_9001_PAI</FUNCNAME>
     <SHORT_TEXT>RF ZDIFHU screen 9001 PAI</SHORT_TEXT>
     <IMPORT>
      <RSIMP>
       <PARAMETER>IV_LGNUM</PARAMETER>
       <TYP>/SCWM/LGNUM</TYP>
      </RSIMP>
     </IMPORT>
     <CHANGING>
      <RSCHA>
       <PARAMETER>CS_ZDIFHU_S_SCR</PARAMETER>
       <TYP>ZSDIFHU_SCR</TYP>
      </RSCHA>
      <RSCHA>
       <PARAMETER>CT_ZDIFHU_T_ITEMS</PARAMETER>
       <TYP>ZSDIFHU_ITEM_TT</TYP>
      </RSCHA>
     </CHANGING>
     <DOCUMENTATION>
      <RSFDO>
       <PARAMETER>IV_LGNUM</PARAMETER>
       <KIND>P</KIND>
      </RSFDO>
      <RSFDO>
       <PARAMETER>CS_ZDIFHU_S_SCR</PARAMETER>
       <KIND>P</KIND>
      </RSFDO>
      <RSFDO>
       <PARAMETER>CT_ZDIFHU_T_ITEMS</PARAMETER>
       <KIND>P</KIND>
      </RSFDO>
     </DOCUMENTATION>
    </item>
   </FUNCTIONS>
  </asx:values>
 </asx:abap>
</abapGit>
```

- [ ] **Step 2: 写 `zfg_rf_zdifhu.fugr.saplzfg_rf_zdifhu.abap`（主程序，固定模板）**

```abap
*******************************************************************
*   System-defined Include-files.                                 *
*******************************************************************
  INCLUDE LZFG_RF_ZDIFHUTOP.               " Global Declarations
  INCLUDE LZFG_RF_ZDIFHUUXX.               " Function Modules

*******************************************************************
*   User-defined Include-files (if necessary).                    *
*******************************************************************
* INCLUDE LZFG_RF_ZDIFHUF...               " Subroutines
* INCLUDE LZFG_RF_ZDIFHUO...               " PBO-Modules
* INCLUDE LZFG_RF_ZDIFHUI...               " PAI-Modules
* INCLUDE LZFG_RF_ZDIFHUE...               " Events
* INCLUDE LZFG_RF_ZDIFHUP...               " Local class implement.
```

- [ ] **Step 3: 写 `zfg_rf_zdifhu.fugr.saplzfg_rf_zdifhu.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<abapGit version="v1.0.0">
 <asx:abap xmlns:asx="http://www.sap.com/abapxml" version="1.0">
  <asx:values>
   <PROGDIR>
    <NAME>SAPLZFG_RF_ZDIFHU</NAME>
    <SUBC>F</SUBC>
    <RLOAD>E</RLOAD>
    <FIXPT>X</FIXPT>
    <UCCHECK>X</UCCHECK>
   </PROGDIR>
  </asx:values>
 </asx:abap>
</abapGit>
```

- [ ] **Step 4: 写 `zfg_rf_zdifhu.fugr.lzfg_rf_zdifhutop.abap`（TOP：全局声明）**

```abap
FUNCTION-POOL zfg_rf_zdifhu.             "MESSAGE-ID ..

* 屏幕字段工作区（TABLES 使屏幕字段可绑 ZSDIFHU_SCR-* / ZSDIFHU_ITEM-*）
TABLES: zsdifhu_scr,
        zsdifhu_item.

* 列表内表（屏幕 step-loop 数据源；PBO 时由 App.Param ZDIFHU_T_ITEMS 同步）
DATA: gt_zdifhu_items TYPE zsdifhu_item_tt.

* OK 码与 step-loop 翻页游标
DATA: ok_code   TYPE sy-ucomm,
      gv_cursor TYPE i VALUE 1.

*----------------------------------------------------------------------*
* 重读 HU，按 GUID_STOCK 刷新单行的当前数量（过账后调用）
*----------------------------------------------------------------------*
FORM refresh_item USING    iv_lgnum      TYPE /scwm/lgnum
                           iv_huident    TYPE /scwm/de_huident
                           iv_guid_stock TYPE /lime/guid_stock
                  CHANGING cs_item       TYPE zsdifhu_item.

  DATA: lt_huident TYPE /scwm/tt_huident,
        ls_huident TYPE /scwm/s_huident,
        lt_huitm   TYPE /scwm/tt_huitm.

  FIELD-SYMBOLS: <ls_huitm> TYPE /scwm/s_huitm.

  ls_huident-huident = iv_huident.
  APPEND ls_huident TO lt_huident.

  CALL FUNCTION '/SCWM/HU_READ_MULT'
    EXPORTING
      it_huident   = lt_huident
      iv_lgnum     = iv_lgnum
    IMPORTING
      et_huitm     = lt_huitm
    EXCEPTIONS
      not_possible = 1
      OTHERS       = 2.
  IF sy-subrc <> 0.
    RETURN.
  ENDIF.

  LOOP AT lt_huitm ASSIGNING <ls_huitm> WHERE guid_stock = iv_guid_stock.
    cs_item-quan  = <ls_huitm>-quan.
    cs_item-meins = <ls_huitm>-meins.
    EXIT.
  ENDLOOP.

ENDFORM.
```

- [ ] **Step 5: 写 `zfg_rf_zdifhu.fugr.lzfg_rf_zdifhutop.xml`**

```xml
<?xml version="1.0" encoding="utf-8"?>
<abapGit version="v1.0.0">
 <asx:abap xmlns:asx="http://www.sap.com/abapxml" version="1.0">
  <asx:values>
   <PROGDIR>
    <NAME>LZFG_RF_ZDIFHUTOP</NAME>
    <SUBC>I</SUBC>
    <FIXPT>X</FIXPT>
    <UCCHECK>X</UCCHECK>
   </PROGDIR>
  </asx:values>
 </asx:abap>
</abapGit>
```

- [ ] **Step 6: 验证**

```bash
cd /home/tankren/opencode/zdifhu/src && for f in zfg_rf_zdifhu.fugr.xml zfg_rf_zdifhu.fugr.saplzfg_rf_zdifhu.xml zfg_rf_zdifhu.fugr.lzfg_rf_zdifhutop.xml; do python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1]); print('OK', sys.argv[1])" "$f"; done
```

预期：三行 `OK ...`；目视核对 fugr.xml 含 4 个 `<item>`、每个含 1×RSIMP + 2×RSCHA + 3×RSFDO。

---

### Task 5: FM Z_RF_ZDIFHU_9000_PBO

**Files:**
- Create: `/home/tankren/opencode/zdifhu/src/zfg_rf_zdifhu.fugr.z_rf_zdifhu_9000_pbo.abap`

PBO 只做一件事：初始化 TM 全局上下文（packing 类依赖）。数据清理由 BACK 流程回到本屏时由用户重新输入覆盖，不在 PBO 清（保留重显）。

- [ ] **Step 1: 写 FM 文件**

```abap
FUNCTION z_rf_zdifhu_9000_pbo.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_LGNUM) TYPE  /SCWM/LGNUM
*"  CHANGING
*"     REFERENCE(CS_ZDIFHU_S_SCR) TYPE  ZSDIFHU_SCR
*"     REFERENCE(CT_ZDIFHU_T_ITEMS) TYPE  ZSDIFHU_ITEM_TT
*"----------------------------------------------------------------------

  /scwm/cl_tm=>set_lgnum( iv_lgnum ).

ENDFUNCTION.
```

- [ ] **Step 2: 验证**

目视核对：注释头参数与 fugr.xml 中 `Z_RF_ZDIFHU_9000_PBO` 的 RSIMP/RSCHA 完全一致（名字、类型、VALUE/REFERENCE）。

---

### Task 6: FM Z_RF_ZDIFHU_9000_PAI（HU 校验 + 库存读取）

**Files:**
- Create: `/home/tankren/opencode/zdifhu/src/zfg_rf_zdifhu.fugr.z_rf_zdifhu_9000_pai.abap`

逻辑（spec §3.1）：HU 号大写 → `/SCWM/HU_READ_MULT`（combined read）→ 只取直接项目（`guid_parent = huhdr-guid_hu`，不支持嵌套）→ MATID→MATNR（`/SCWM/MATERIAL_READ_SINGLE`）→ MAKT 描述 → 填 `ct_zdifhu_t_items`。失败时 `SET_FCODE( 'INIT' )` 回本屏 + `MESSAGE e001(00)` 报错（标准 RF FM 同款写法，框架捕获显示在 RF 屏底）。

⚠️ 系统校准：`SET_FCODE` 签名以 SE24 `/SCWM/CL_RF_BLL_SRVC` 为准（静态方法，单参 IV_FCODE）。

- [ ] **Step 1: 写 FM 文件**

```abap
FUNCTION z_rf_zdifhu_9000_pai.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_LGNUM) TYPE  /SCWM/LGNUM
*"  CHANGING
*"     REFERENCE(CS_ZDIFHU_S_SCR) TYPE  ZSDIFHU_SCR
*"     REFERENCE(CT_ZDIFHU_T_ITEMS) TYPE  ZSDIFHU_ITEM_TT
*"----------------------------------------------------------------------

  DATA: lt_huident    TYPE /scwm/tt_huident,
        ls_huident    TYPE /scwm/s_huident,
        lt_huhdr      TYPE /scwm/tt_huhdr,
        ls_huhdr      TYPE /scwm/s_huhdr,
        lt_huitm      TYPE /scwm/tt_huitm,
        ls_huitm      TYPE /scwm/s_huitm,
        ls_mat_global TYPE /scwm/s_mat_global,
        ls_item       TYPE zsdifhu_item.

  /scwm/cl_tm=>set_lgnum( iv_lgnum ).

* HU 号大写（扫描枪/手工输入统一）
  TRANSLATE cs_zdifhu_s_scr-huident TO UPPER CASE.

* 空 HU：提示并停留本屏
  IF cs_zdifhu_s_scr-huident IS INITIAL.
    /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
    MESSAGE e001(00) WITH 'Please enter HU number'(001).
  ENDIF.

  ls_huident-huident = cs_zdifhu_s_scr-huident.
  APPEND ls_huident TO lt_huident.

* HU 读取（combined read：先 buffer 再 DB，拿最新数据）
  CALL FUNCTION '/SCWM/HU_READ_MULT'
    EXPORTING
      it_huident   = lt_huident
      iv_lgnum     = iv_lgnum
    IMPORTING
      et_huhdr     = lt_huhdr
      et_huitm     = lt_huitm
    EXCEPTIONS
      not_possible = 1
      OTHERS       = 2.
  IF sy-subrc <> 0 OR lt_huhdr IS INITIAL.
    /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
    MESSAGE e001(00) WITH 'HU not found'(002).
  ENDIF.

  READ TABLE lt_huhdr INTO ls_huhdr INDEX 1.

* 只取 HU 直接项目（不支持嵌套包装）
  CLEAR ct_zdifhu_t_items.
  LOOP AT lt_huitm INTO ls_huitm WHERE guid_parent = ls_huhdr-guid_hu.
    CLEAR ls_item.

*   MATID → MATNR
    CALL FUNCTION '/SCWM/MATERIAL_READ_SINGLE'
      EXPORTING
        iv_matid      = ls_huitm-matid
        iv_langu      = sy-langu
      IMPORTING
        es_mat_global = ls_mat_global
      EXCEPTIONS
        OTHERS        = 1.
    IF sy-subrc <> 0.
      CONTINUE.
    ENDIF.

    ls_item-matnr      = ls_mat_global-matnr.
    ls_item-quan       = ls_huitm-quan.
    ls_item-meins      = ls_huitm-meins.
    ls_item-guid_stock = ls_huitm-guid_stock.
    ls_item-guid_hu    = ls_huhdr-guid_hu.

*   物料描述
    SELECT SINGLE maktx FROM makt INTO ls_item-maktx
      WHERE matnr = ls_item-matnr
        AND spras = sy-langu.

    APPEND ls_item TO ct_zdifhu_t_items.
  ENDLOOP.

  IF ct_zdifhu_t_items IS INITIAL.
    /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
    MESSAGE e001(00) WITH 'No material items in HU'(003).
  ENDIF.

* 新 HU 装载成功：重置翻页游标
  gv_cursor = 1.

* 成功：无需操作，step flow ENTER → ZDIF2 自动跳屏幕 2

ENDFUNCTION.
```

- [ ] **Step 2: 验证**

目视核对：接口注释头与 fugr.xml 一致；3 处错误分支均为先 `SET_FCODE( 'INIT' )` 后 `MESSAGE`（顺序不能反，MESSAGE E 会终止 FM）；消息文本 `(001)`-`(003)` 为文本符号占位写法——ABAP 中文本符号不存在时会原样显示字面文本，无需额外创建，保持。

---

### Task 7: FM Z_RF_ZDIFHU_9001_PBO（列表三件套）

**Files:**
- Create: `/home/tankren/opencode/zdifhu/src/zfg_rf_zdifhu.fugr.z_rf_zdifhu_9001_pbo.abap`

逻辑（spec §3.2）：三件套（init_screen_param / set_screen_param / set_scr_tabname）必需，否则 RF 框架无法把内表传到屏幕 step-loop；App.Param → FG 屏幕内表；光标定位扫描框。

- [ ] **Step 1: 写 FM 文件**

```abap
FUNCTION z_rf_zdifhu_9001_pbo.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_LGNUM) TYPE  /SCWM/LGNUM
*"  CHANGING
*"     REFERENCE(CS_ZDIFHU_S_SCR) TYPE  ZSDIFHU_SCR
*"     REFERENCE(CT_ZDIFHU_T_ITEMS) TYPE  ZSDIFHU_ITEM_TT
*"----------------------------------------------------------------------

  /scwm/cl_tm=>set_lgnum( iv_lgnum ).

* RF 列表三件套（必需）
  /scwm/cl_rf_bll_srvc=>init_screen_param( ).
  /scwm/cl_rf_bll_srvc=>set_screen_param( 'ZDIFHU_T_ITEMS' ).
  /scwm/cl_rf_bll_srvc=>set_scr_tabname( 'ZSDIFHU_ITEM_TT' ).

* App.Param → 屏幕内表（step-loop 数据源）
  gt_zdifhu_items[] = ct_zdifhu_t_items[].

* 光标回扫描框
  SET CURSOR FIELD 'ZSDIFHU_SCR-MATNR_SCAN'.

ENDFUNCTION.
```

- [ ] **Step 2: 验证**

目视核对：`set_screen_param` 参数值 `'ZDIFHU_T_ITEMS'` 与 Application Parameter 名一致（spec §2）；`set_scr_tabname` 值与 DDIC 表类型名一致。

---

### Task 8: FM Z_RF_ZDIFHU_9001_PAI（防呆 + 差异计算 + 过账）

**Files:**
- Create: `/home/tankren/opencode/zdifhu/src/zfg_rf_zdifhu.fugr.z_rf_zdifhu_9001_pai.abap`

逻辑（spec §3.3 + §3.5）：屏幕内表回写 App.Param → 按 FCODE 分支（DOWN 翻页 / BACK 不动 / 其余=ENTER 走防呆过账）。过账三步：`POST_DIFFERENCE`（DIFD/PPT/16）→ `SAVE(iv_commit=space)` → `COMMIT WORK AND WAIT`（失败 ROLLBACK）→ `CL_TM=>CLEANUP`；成功后 `PERFORM refresh_item` 刷新该行数量、清 diff_quan 和扫描框、`SET_FCODE('INIT')` 回本屏重显。

⚠️ 系统校准：`GET_FCODE` 静态签名以 SE24 为准；异常码三件套以 SPRO 配置为准（spec §5.2）。

- [ ] **Step 1: 写 FM 文件**

```abap
FUNCTION z_rf_zdifhu_9001_pai.
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(IV_LGNUM) TYPE  /SCWM/LGNUM
*"  CHANGING
*"     REFERENCE(CS_ZDIFHU_S_SCR) TYPE  ZSDIFHU_SCR
*"     REFERENCE(CT_ZDIFHU_T_ITEMS) TYPE  ZSDIFHU_ITEM_TT
*"----------------------------------------------------------------------

  DATA: ls_item  TYPE zsdifhu_item,
        lv_tabix TYPE sy-tabix,
        lv_diff  TYPE /scwm/de_quantity,
        ls_quan  TYPE /scwm/s_quan,
        lv_fcode TYPE /scwm/de_fcode,
        lv_max   TYPE i.

  /scwm/cl_tm=>set_lgnum( iv_lgnum ).

* 屏幕内表 → App.Param（回写用户输入的实盘数量）
  ct_zdifhu_t_items[] = gt_zdifhu_items[].

  lv_fcode = /scwm/cl_rf_bll_srvc=>get_fcode( ).

  CASE lv_fcode.
    WHEN 'DOWN'.
*     翻页（5 行可见）
      lv_max = lines( ct_zdifhu_t_items ) - 4.
      IF lv_max < 1.
        lv_max = 1.
      ENDIF.
      gv_cursor = gv_cursor + 5.
      IF gv_cursor > lv_max.
        gv_cursor = lv_max.
      ENDIF.

    WHEN 'BACK'.
*     无操作：step flow BACK → ZDIF1 自动处理

    WHEN OTHERS.
*     ENTER：防呆 + 差异计算 + 过账
      TRANSLATE cs_zdifhu_s_scr-matnr_scan TO UPPER CASE.

      IF cs_zdifhu_s_scr-matnr_scan IS INITIAL.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e001(00) WITH 'Please scan material'(004).
      ENDIF.

*     1. 防呆：物料必须在列表内
      READ TABLE ct_zdifhu_t_items INTO ls_item
           WITH KEY matnr = cs_zdifhu_s_scr-matnr_scan.
      IF sy-subrc <> 0.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e001(00) WITH 'Material not in this HU'(005).
      ENDIF.
      lv_tabix = sy-tabix.

*     2. 差异计算（实盘 − 当前）
      lv_diff = ls_item-diff_quan - ls_item-quan.
      IF lv_diff = 0.
        CLEAR cs_zdifhu_s_scr-matnr_scan.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        RETURN.
      ENDIF.

      ls_quan-quan = lv_diff.
      ls_quan-unit = ls_item-meins.

*     3. 过账（签名已确认；异常码三件套按客户系统配置）
      CALL METHOD /scwm/cl_wm_packing=>post_difference
        EXPORTING
          iv_guid_hu    = ls_item-guid_hu
          iv_guid_stock = ls_item-guid_stock
          is_quan       = ls_quan
          iv_exccode    = 'DIFD'
          iv_buscon     = 'PPT'
          iv_exec_step  = '16'
        EXCEPTIONS
          error         = 1
          OTHERS        = 2.
      IF sy-subrc <> 0.
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e001(00) WITH 'Difference posting failed'(006).
      ENDIF.

*     4. 落库：save 不带 commit，外层显式 COMMIT
      CALL METHOD /scwm/cl_wm_packing=>save
        EXPORTING
          iv_commit = space
          iv_wait   = space
        EXCEPTIONS
          OTHERS    = 99.
      IF sy-subrc <> 0.
        ROLLBACK WORK.
        /scwm/cl_tm=>cleanup( ).
        /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
        MESSAGE e001(00) WITH 'Save failed, rolled back'(007).
      ENDIF.
      COMMIT WORK AND WAIT.
      /scwm/cl_tm=>cleanup( ).

*     5. 刷新该行数量，清实盘与扫描框，回本屏重显
      PERFORM refresh_item USING    iv_lgnum
                                    cs_zdifhu_s_scr-huident
                                    ls_item-guid_stock
                           CHANGING ls_item.
      CLEAR ls_item-diff_quan.
      MODIFY ct_zdifhu_t_items FROM ls_item INDEX lv_tabix.
      CLEAR cs_zdifhu_s_scr-matnr_scan.
      /scwm/cl_rf_bll_srvc=>set_fcode( 'INIT' ).
  ENDCASE.

ENDFUNCTION.
```

- [ ] **Step 2: 验证**

目视核对：错误分支（004-007）均先 `SET_FCODE` 后 `MESSAGE`；ROLLBACK 分支在 MESSAGE 前有 `CLEANUP`；成功路径无 MESSAGE（直接 SET_FCODE('INIT') 重显）；`refresh_item` 参数顺序与 TOP include 中 FORM 定义一致（lgnum, huident, guid_stock）。

---

### Task 9: 屏幕 9000（HU 输入）

**Files:**
- Modify: `/home/tankren/opencode/zdifhu/src/zfg_rf_zdifhu.fugr.xml`（`<asx:values>` 内、`</FUNCTIONS>` 后追加 `<DYNPROS>` 段）
- Create: `/home/tankren/opencode/zdifhu/src/zfg_rf_zdifhu.fugr.screen_9000.abap`

屏幕属性：子屏幕（TYPE=S），8 行 × 40 列（RF 8x40 屏）。字段：DDIC 文本标签 + HUIDENT 输入框 + OKCODE。RF 子屏幕无 CUA（GUI status 由 RF 框架管理），不写 `<CUA>` 段。

- [ ] **Step 1: 修改 fugr.xml — 在 `</FUNCTIONS>` 之后、`</asx:values>` 之前插入**

```xml
   <DYNPROS>
    <item>
     <HEADER>
      <PROGRAM>SAPLZFG_RF_ZDIFHU</PROGRAM>
      <SCREEN>9000</SCREEN>
      <LANGUAGE>E</LANGUAGE>
      <DESCRIPT>ZDIFHU HU input</DESCRIPT>
      <TYPE>S</TYPE>
      <NEXTSCREEN>9000</NEXTSCREEN>
      <LINES>008</LINES>
      <COLUMNS>040</COLUMNS>
     </HEADER>
     <CONTAINERS>
      <RPY_DYCATT>
       <TYPE>SCREEN</TYPE>
       <NAME>SCREEN</NAME>
      </RPY_DYCATT>
     </CONTAINERS>
     <FIELDS>
      <RPY_DYFATC>
       <CONT_TYPE>SCREEN</CONT_TYPE>
       <CONT_NAME>SCREEN</CONT_NAME>
       <TYPE>TEXT</TYPE>
       <NAME>ZSDIFHU_SCR-HUIDENT</NAME>
       <LINE>001</LINE>
       <COLUMN>001</COLUMN>
       <LENGTH>010</LENGTH>
       <VISLENGTH>010</VISLENGTH>
       <HEIGHT>001</HEIGHT>
       <FORMAT>CHAR</FORMAT>
       <FROM_DICT>X</FROM_DICT>
       <MODIFIC>2</MODIFIC>
       <REQU_ENTRY>N</REQU_ENTRY>
       <LABELLEFT>X</LABELLEFT>
      </RPY_DYFATC>
      <RPY_DYFATC>
       <CONT_TYPE>SCREEN</CONT_TYPE>
       <CONT_NAME>SCREEN</CONT_NAME>
       <TYPE>TEMPLATE</TYPE>
       <NAME>ZSDIFHU_SCR-HUIDENT</NAME>
       <LINE>001</LINE>
       <COLUMN>013</COLUMN>
       <LENGTH>020</LENGTH>
       <VISLENGTH>020</VISLENGTH>
       <HEIGHT>001</HEIGHT>
       <FORMAT>CHAR</FORMAT>
       <FROM_DICT>X</FROM_DICT>
       <UP_LOWER>X</UP_LOWER>
       <INPUT_FLD>X</INPUT_FLD>
       <OUTPUT_FLD>X</OUTPUT_FLD>
      </RPY_DYFATC>
      <RPY_DYFATC>
       <CONT_TYPE>SCREEN</CONT_TYPE>
       <CONT_NAME>SCREEN</CONT_NAME>
       <TYPE>OKCODE</TYPE>
       <NAME>OK_CODE</NAME>
       <TEXT>____________________</TEXT>
       <LENGTH>020</LENGTH>
       <VISLENGTH>020</VISLENGTH>
       <HEIGHT>001</HEIGHT>
       <FORMAT>CHAR</FORMAT>
       <INPUT_FLD>X</INPUT_FLD>
      </RPY_DYFATC>
     </FIELDS>
    </item>
   </DYNPROS>
```

- [ ] **Step 2: 写 `screen_9000.abap`（RF 框架调 FM，屏幕 flow logic 为空壳）**

```abap
PROCESS BEFORE OUTPUT.
*
PROCESS AFTER INPUT.
```

- [ ] **Step 3: 验证**

```bash
python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('/home/tankren/opencode/zdifhu/src/zfg_rf_zdifhu.fugr.xml'); print('OK')"
```

预期：`OK`；目视核对 DYNPROS 在 FUNCTIONS 之后、CUA 不存在。

---

### Task 10: 屏幕 9001（扫描框 + 物料列表 step-loop）

**Files:**
- Modify: `/home/tankren/opencode/zdifhu/src/zfg_rf_zdifhu.fugr.xml`（`<DYNPROS>` 内追加第二个 `<item>`）
- Create: `/home/tankren/opencode/zdifhu/src/zfg_rf_zdifhu.fugr.screen_9001.abap`

布局（8 行 × 40 列）：
- 行 1：扫描框标签 + `ZSDIFHU_SCR-MATNR_SCAN` 输入框
- 行 2：`HU:` 文本 + `ZSDIFHU_SCR-HUIDENT` 只显
- 行 4-8：固定 step-loop（容器 TYPE=LOOP，5 行可见），行内 5 列：MATNR（只显）/ MAKTX（只显）/ QUAN（只显）/ MEINS（只显）/ DIFF_QUAN（可输入）

⚠️ step-loop 的 LOOP 容器 XML 无官方样本可核对，import 若报 `RPY_DYNPRO_INSERT` 错误 → 按 README "Plan B" 用 SE51 手建屏幕 9001（10 分钟），其余对象不受影响。

- [ ] **Step 1: 修改 fugr.xml — 在 `<DYNPROS>` 内第一个 `</item>` 之后插入**

```xml
    <item>
     <HEADER>
      <PROGRAM>SAPLZFG_RF_ZDIFHU</PROGRAM>
      <SCREEN>9001</SCREEN>
      <LANGUAGE>E</LANGUAGE>
      <DESCRIPT>ZDIFHU item list</DESCRIPT>
      <TYPE>S</TYPE>
      <NEXTSCREEN>9001</NEXTSCREEN>
      <LINES>008</LINES>
      <COLUMNS>040</COLUMNS>
     </HEADER>
     <CONTAINERS>
      <RPY_DYCATT>
       <TYPE>SCREEN</TYPE>
       <NAME>SCREEN</NAME>
      </RPY_DYCATT>
      <RPY_DYCATT>
       <TYPE>LOOP</TYPE>
       <NAME>LP_ITEMS</NAME>
       <LINE>004</LINE>
       <COLUMN>001</COLUMN>
       <LENGTH>039</LENGTH>
       <HEIGHT>005</HEIGHT>
      </RPY_DYCATT>
     </CONTAINERS>
     <FIELDS>
      <RPY_DYFATC>
       <CONT_TYPE>SCREEN</CONT_TYPE>
       <CONT_NAME>SCREEN</CONT_NAME>
       <TYPE>TEXT</TYPE>
       <NAME>ZSDIFHU_SCR-MATNR_SCAN</NAME>
       <LINE>001</LINE>
       <COLUMN>001</COLUMN>
       <LENGTH>008</LENGTH>
       <VISLENGTH>008</VISLENGTH>
       <HEIGHT>001</HEIGHT>
       <FORMAT>CHAR</FORMAT>
       <FROM_DICT>X</FROM_DICT>
       <MODIFIC>2</MODIFIC>
       <REQU_ENTRY>N</REQU_ENTRY>
       <LABELLEFT>X</LABELLEFT>
      </RPY_DYFATC>
      <RPY_DYFATC>
       <CONT_TYPE>SCREEN</CONT_TYPE>
       <CONT_NAME>SCREEN</CONT_NAME>
       <TYPE>TEMPLATE</TYPE>
       <NAME>ZSDIFHU_SCR-MATNR_SCAN</NAME>
       <LINE>001</LINE>
       <COLUMN>010</COLUMN>
       <LENGTH>018</LENGTH>
       <VISLENGTH>018</VISLENGTH>
       <HEIGHT>001</HEIGHT>
       <FORMAT>CHAR</FORMAT>
       <FROM_DICT>X</FROM_DICT>
       <UP_LOWER>X</UP_LOWER>
       <INPUT_FLD>X</INPUT_FLD>
       <OUTPUT_FLD>X</OUTPUT_FLD>
      </RPY_DYFATC>
      <RPY_DYFATC>
       <CONT_TYPE>SCREEN</CONT_TYPE>
       <CONT_NAME>SCREEN</CONT_NAME>
       <TYPE>TEXT</TYPE>
       <NAME>TXT_HU</NAME>
       <LINE>002</LINE>
       <COLUMN>001</COLUMN>
       <LENGTH>003</LENGTH>
       <VISLENGTH>003</VISLENGTH>
       <HEIGHT>001</HEIGHT>
       <FORMAT>CHAR</FORMAT>
       <TEXT>HU:</TEXT>
      </RPY_DYFATC>
      <RPY_DYFATC>
       <CONT_TYPE>SCREEN</CONT_TYPE>
       <CONT_NAME>SCREEN</CONT_NAME>
       <TYPE>TEMPLATE</TYPE>
       <NAME>ZSDIFHU_SCR-HUIDENT</NAME>
       <LINE>002</LINE>
       <COLUMN>005</COLUMN>
       <LENGTH>020</LENGTH>
       <VISLENGTH>020</VISLENGTH>
       <HEIGHT>001</HEIGHT>
       <FORMAT>CHAR</FORMAT>
       <FROM_DICT>X</FROM_DICT>
       <OUTPUT_FLD>X</OUTPUT_FLD>
       <OUTPUTONLY>X</OUTPUTONLY>
       <REQU_ENTRY>N</REQU_ENTRY>
      </RPY_DYFATC>
      <RPY_DYFATC>
       <CONT_TYPE>LOOP</CONT_TYPE>
       <CONT_NAME>LP_ITEMS</CONT_NAME>
       <TYPE>TEMPLATE</TYPE>
       <NAME>ZSDIFHU_ITEM-MATNR</NAME>
       <LINE>001</LINE>
       <COLUMN>001</COLUMN>
       <LENGTH>010</LENGTH>
       <VISLENGTH>010</VISLENGTH>
       <HEIGHT>001</HEIGHT>
       <FORMAT>CHAR</FORMAT>
       <FROM_DICT>X</FROM_DICT>
       <OUTPUT_FLD>X</OUTPUT_FLD>
       <OUTPUTONLY>X</OUTPUTONLY>
       <REQU_ENTRY>N</REQU_ENTRY>
      </RPY_DYFATC>
      <RPY_DYFATC>
       <CONT_TYPE>LOOP</CONT_TYPE>
       <CONT_NAME>LP_ITEMS</CONT_NAME>
       <TYPE>TEMPLATE</TYPE>
       <NAME>ZSDIFHU_ITEM-MAKTX</NAME>
       <LINE>001</LINE>
       <COLUMN>012</COLUMN>
       <LENGTH>010</LENGTH>
       <VISLENGTH>010</VISLENGTH>
       <HEIGHT>001</HEIGHT>
       <FORMAT>CHAR</FORMAT>
       <FROM_DICT>X</FROM_DICT>
       <OUTPUT_FLD>X</OUTPUT_FLD>
       <OUTPUTONLY>X</OUTPUTONLY>
       <REQU_ENTRY>N</REQU_ENTRY>
      </RPY_DYFATC>
      <RPY_DYFATC>
       <CONT_TYPE>LOOP</CONT_TYPE>
       <CONT_NAME>LP_ITEMS</CONT_NAME>
       <TYPE>TEMPLATE</TYPE>
       <NAME>ZSDIFHU_ITEM-QUAN</NAME>
       <LINE>001</LINE>
       <COLUMN>023</COLUMN>
       <LENGTH>007</LENGTH>
       <VISLENGTH>007</VISLENGTH>
       <HEIGHT>001</HEIGHT>
       <FORMAT>QUAN</FORMAT>
       <FROM_DICT>X</FROM_DICT>
       <OUTPUT_FLD>X</OUTPUT_FLD>
       <OUTPUTONLY>X</OUTPUTONLY>
       <REQU_ENTRY>N</REQU_ENTRY>
      </RPY_DYFATC>
      <RPY_DYFATC>
       <CONT_TYPE>LOOP</CONT_TYPE>
       <CONT_NAME>LP_ITEMS</CONT_NAME>
       <TYPE>TEMPLATE</TYPE>
       <NAME>ZSDIFHU_ITEM-MEINS</NAME>
       <LINE>001</LINE>
       <COLUMN>031</COLUMN>
       <LENGTH>003</LENGTH>
       <VISLENGTH>003</VISLENGTH>
       <HEIGHT>001</HEIGHT>
       <FORMAT>UNIT</FORMAT>
       <FROM_DICT>X</FROM_DICT>
       <OUTPUT_FLD>X</OUTPUT_FLD>
       <OUTPUTONLY>X</OUTPUTONLY>
       <REQU_ENTRY>N</REQU_ENTRY>
      </RPY_DYFATC>
      <RPY_DYFATC>
       <CONT_TYPE>LOOP</CONT_TYPE>
       <CONT_NAME>LP_ITEMS</CONT_NAME>
       <TYPE>TEMPLATE</TYPE>
       <NAME>ZSDIFHU_ITEM-DIFF_QUAN</NAME>
       <LINE>001</LINE>
       <COLUMN>035</COLUMN>
       <LENGTH>005</LENGTH>
       <VISLENGTH>005</VISLENGTH>
       <HEIGHT>001</HEIGHT>
       <FORMAT>QUAN</FORMAT>
       <FROM_DICT>X</FROM_DICT>
       <INPUT_FLD>X</INPUT_FLD>
       <OUTPUT_FLD>X</OUTPUT_FLD>
       <REQU_ENTRY>N</REQU_ENTRY>
      </RPY_DYFATC>
      <RPY_DYFATC>
       <CONT_TYPE>SCREEN</CONT_TYPE>
       <CONT_NAME>SCREEN</CONT_NAME>
       <TYPE>OKCODE</TYPE>
       <NAME>OK_CODE</NAME>
       <TEXT>____________________</TEXT>
       <LENGTH>020</LENGTH>
       <VISLENGTH>020</VISLENGTH>
       <HEIGHT>001</HEIGHT>
       <FORMAT>CHAR</FORMAT>
       <INPUT_FLD>X</INPUT_FLD>
      </RPY_DYFATC>
     </FIELDS>
    </item>
```

- [ ] **Step 2: 写 `screen_9001.abap`（step-loop 循环，无 MODULE）**

```abap
PROCESS BEFORE OUTPUT.
  LOOP AT gt_zdifhu_items INTO zsdifhu_item CURSOR gv_cursor.
  ENDLOOP.
*
PROCESS AFTER INPUT.
  LOOP AT gt_zdifhu_items INTO zsdifhu_item.
  ENDLOOP.
```

- [ ] **Step 3: 验证**

```bash
python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('/home/tankren/opencode/zdifhu/src/zfg_rf_zdifhu.fugr.xml'); print('OK')"
```

预期：`OK`；目视核对 DYNPROS 含 2 个 `<item>`（9000、9001），9001 的 LOOP 容器含 5 个字段且 LINE 均为 001（行内坐标，循环重复由容器 HEIGHT=005 控制）。

---

### Task 11: README 完整版（安装 + Customizing + Plan B + 验收）

**Files:**
- Modify: `/home/tankren/opencode/zdifhu/README.md`（整体替换）

- [ ] **Step 1: 写 README**

````markdown
# ZDIFHU — EWM RF HU 差异过账

RF 逻辑事务 `ZDIFHU`：屏幕 1 输/扫 HU 号 → 屏幕 2 显示 HU 物料列表，
扫物料号定位行、输入实盘数量，ENTER 立即过账差异（实盘 − 当前）。
过账 API：`/SCWM/CL_WM_PACKING=>POST_DIFFERENCE`。

## 1. 安装（abapGit）

1. abapGit → New Offline（或 New Online 推送到内部 Git）→ 导入本仓库 zip
2. 包：`ZZDIFHU`（不存在则让 abapGit 创建）
3. Pull → 激活全部对象
4. 激活后核对（SE11）：`/SCWM/DE_HUIDENT`、`/SCWM/DE_QUANTITY`、`/SCWM/DE_BASE_UOM`、
   `/SCWM/GUID_HU`、`/LIME/GUID_STOCK` 存在；若 `ZSDIFHU*` 激活报错，
   按 `src/*.tabl.xml` 头部注释改用内建类型

## 2. Customizing（SPRO → EWM → Mobile Data Entry，按顺序）

> **执行后修订（2026-09-14）**：屏幕 2 按用户要求改为「列表屏 → 明细屏」两步（照搬标准
> `/SCWM/RF_XDIFHU` 模式）：列表屏 9001 加序号列 + 序号输入框；新增 step `ZDIF3` +
> 屏幕 9002（实盘数量录入 + 过账）。下表为跑通的最终 step flow。
>
> - **规则 A（跳步）**：**跨步骤跳转行必须 `PRMOD=1` + `FCODE_BCKG=INIT`**（原表把跨步骤行
>   写成 PRMOD=2 且无 FCODE_BCKG，是屏幕 2 `GETWA_NOT_ASSIGNED` dump 的根因）。
> - **规则 B（过账后返回）**：`ZDIF3/ENTER` 行**不换步**（`SSTEP=ZDIF3`、`PRMOD=0`），返回由
>   `9002_PAI` 结尾的 `set_prmod('1') + set_fcode('UPDBCK')` 完成（`UPDBCK` = 回上一步 +
>   同步内部调用栈 + 刷新目标步 PBO）。若该行自己换步，调用栈残留 ZDIF3 → 在列表屏按 BACK
>   会被弹回明细屏。`BACK` 本身由框架弹内部调用栈处理（不读 step flow 行的 SSTEP）。
> - `DOWN` 行已删除（翻页用框架 PGUP/PGDN）。

1. **Define Application Parameters**（视图 `/SCWM/RF_CUSTOM`，SM30）：
   - APPLIC=`01`(WME) / `CS_ZDIFHU_S_SCR` / Parameter Type=`ZSDIFHU_SCR`
   - APPLIC=`01`(WME) / `CS_ZDIFHU_PROD` / Parameter Type=`ZSDIFHU_PROD`
   - APPLIC=`01`(WME) / `CT_ZDIFHU_T_ITEMS` / Parameter Type=`ZSDIFHU_ITEM_TT`
   - APPLIC=`01`(WME) / `CS_ZDIFHU_HU` / Parameter Type=`/SCWM/S_RF_INQ_HU`（HU 明细屏 9004，标准结构）
2. **Define Steps in Logical Transaction**：`ZDIFHU` → `ZDIF1`、`ZDIF2`、`ZDIF3`、`ZDIF4`
3. **Define Step Flow**（`/SCWM/TSTEP_FLOW`）：

   | LTRANS | STEP | FCODE | FMODUL | SSTEP | PRMOD | FCODE_BCKG |
   |---|---|---|---|---|---|---|
   | ZDIFHU | ZDIF1 | INIT | Z_RF_ZDIFHU_9000_PBO | ZDIF1 | 2 | |
   | ZDIFHU | ZDIF1 | ENTER | Z_RF_ZDIFHU_9000_PAI | ZDIF2 | 1 | INIT |
   | ZDIFHU | ZDIF1 | BACK | Z_RF_ZDIFHU_9000_PAI | ZDIF1 | 2 | |
   | ZDIFHU | ZDIF2 | INIT | Z_RF_ZDIFHU_9001_PBO | ZDIF2 | 2 | |
   | ZDIFHU | ZDIF2 | ENTER | Z_RF_ZDIFHU_9001_PAI | ZDIF3 | 1 | INIT |
   | ZDIFHU | ZDIF2 | BACK | Z_RF_ZDIFHU_9001_PAI | ZDIF1 | 1 | INIT |
   | ZDIFHU | ZDIF2 | HUINFO | Z_RF_ZDIFHU_9001_PAI | ZDIF4 | 1 | INIT |
   | ZDIFHU | ZDIF3 | INIT | Z_RF_ZDIFHU_9002_PBO | ZDIF3 | 2 | |
   | ZDIFHU | ZDIF3 | ENTER | Z_RF_ZDIFHU_9002_PAI | ZDIF3 | 0 | |
   | ZDIFHU | ZDIF3 | BACK | Z_RF_ZDIFHU_9002_PAI | ZDIF2 | 1 | INIT |
   | ZDIFHU | ZDIF4 | INIT | Z_RF_ZDIFHU_9004_PBO | ZDIF4 | 2 | |
   | ZDIFHU | ZDIF4 | BACK | Z_RF_ZDIFHU_9004_PAI | ZDIF2 | 1 | INIT |

4. **Define Function Code Profile**（`/SCWM/TFCOD_PRF`）：INIT / ENTER / BACK / CLEAR；**`ZDIF2` 加
   `HUINFO`（`PUSHB=PB1`，或 `FNKEY=F1` + `SHORTCUT=01`）**；`ZDIF4` 加 BACK。`HUINFO` 必须在
   `/SCWM/TFCOD_CAT`（APPLIC=`01`）里存在（翻页 PGUP/PGDN 为框架预定义）
5. **Map Logical Transaction Step to Subscreen**：
   - `ZDIFHU`/`ZDIF1` → `SAPLZFG_RF_ZDIFHU` `9000`
   - `ZDIFHU`/`ZDIF2` → `SAPLZFG_RF_ZDIFHU` `9001`
   - `ZDIFHU`/`ZDIF3` → `SAPLZFG_RF_ZDIFHU` `9002`
   - `ZDIFHU`/`ZDIF4` → `SAPLZFG_RF_ZDIFHU` `9004`
6. **Presentation / Personalization Profile**：复用现有 `**` 或按需新建
7. **RF Menu Manager**：菜单挂载（测试期可用 RF Test Environment 直调）
8. **Exception Codes**（SPRO → EWM → Cross-Process Settings → Exception Codes）：
   确认 `DIFD` + 业务上下文 `PPT` + 执行步骤 `16` 存在；不存在则维护或改代码
   （`z_rf_zdifhu_9002_pai.abap` 中 `iv_exccode/iv_buscon/iv_exec_step` 三处常量）

## 3. Plan B：屏幕 9001 / 9002 / 9004 手工重建（仅当 import 屏幕报错时）

abapGit import 若报 `RPY_DYNPRO_INSERT` 错误（step-loop XML 兼容性），
删除 fugr.xml 中对应屏幕的 `<item>` 重新 import，然后 SE51 手建：

1. SE51 → 程序 `SAPLZFG_RF_ZDIFHU` → 屏幕 `9001`，属性：子屏幕，7 行 × 40 列
2. 布局（列表屏）：
   - 行 1：文本 `No.`(c1，长 3) + `ZSDIFHU_SCR-SELNO`(c5，可输入，NUMC，长 3 —— 序号框故意只给 3 位，不占满整行)
   - 行 2：文本 `HU:`(c1，长 3) + `ZSDIFHU_SCR-HUIDENT`(c5，只显，长 22)
   - 行 3 起：框选 5 个 DDIC 字段做 Step Loop，**每行块 3 行**（LOOP_BLOCK=3、重复 1 次、
     HEIGHT=3，一屏 1 个物料）：
     - 行块第 1 行：`ZSDIFHU_ITEM-SEQNO`(c1，长 3)、`ZSDIFHU_ITEM-MATNR`(c5，长 22)（均只显）
     - 行块第 2 行：`ZSDIFHU_ITEM-MAKTX`(c1，长 26)
     - 行块第 3 行：`ZSDIFHU_ITEM-QUAN`(c5，长 18)、`ZSDIFHU_ITEM-MEINS`(c24，长 3)
   - 只读字段属性**只用 `OUTPUT_FLD`**（不要加 `OUTPUTONLY`，加了是平面文字而非标准只读框；
     标准 `/SCWM/RF_INQUIRY_PM` 里 `OUTPUTONLY` 出现 0 次）；可输入字段只用 `INPUT_FLD + OUTPUT_FLD`
     且**绝不能带 `REQU_ENTRY`**（带了就输不进去）；同一个屏幕**不允许两个同名字段**；
     多行行块必须满足 `HEIGHT = LOOP_BLOCK × LOOP_DISP`
 3. 屏幕 `9002`（明细屏，子屏幕 7 行 × 40 列）：行1 `-MATNR`(c1，长 26) / 行2 `-MAKTX`(c1，长 26) /
    行3 `-QUAN`(c1，长 22) + `-MEINS`(c24，长 3) 均只显（无标签）；行4 文本 `Actual Qty`(c1，长 26)；
    行5 `-QUAN_COUNT`(c1，长 22) 可输入（实盘数量）+ `-MEINS_DSP`(c24，长 3)（只显单位）。
    注意：`-MEINS_DSP` 是结构里专供显示的第二个单位字段——同一个 dynpro 屏幕**不允许两个同名字段**
    （标准 RF 里的同名都是「TEXT 标签字段 + TEMPLATE 字段」的组合）
4. Flow logic（与 `src/zfg_rf_zdifhu.fugr.screen_9001.abap` / `screen_9002.abap` 相同）：

   ```abap
   * 屏幕 9001（列表）
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

5. 激活

## 4. 验收清单

- [ ] `/SCWM/RFUI`（或 RF Test Environment）调用 `ZDIFHU`，屏幕 1 显示 HU 输入框
- [ ] 输入存在的 HU → ENTER → 屏幕 2 显示物料列表（**序号 + 物料号/描述分行 + 数量 + 单位**）
- [ ] 屏幕 2 输入不存在的序号 → 报错 "Item does not exist"（防呆生效）
- [ ] 输入存在的序号 → ENTER → 屏幕 3 显示该物料（物料号/描述/当前数量/单位）
- [ ] 屏幕 3 输入实盘数量 → ENTER → 过账成功，回列表且当前数量已刷新
- [ ] 屏幕 3 输入与当前相同数量 → 报错 "Counted quantity equals current quantity"，不过账
- [ ] 屏幕 3 BACK → 回列表；屏幕 2 BACK → 回屏幕 1；屏幕 1 BACK → 结束事务回菜单
- [ ] 列表超 1 个物料 → 翻页（PGUP/PGDN）正常
- [ ] 差异 = 当前 − 实盘（盘亏为正 → 减库存，盘盈为负 → 加库存）；过账后 `/SCWM/MON` 库存正确

## 5. 对象清单

| 对象 | 名称 | 说明 |
|---|---|---|
| 包 | ZEWM | |
| Function Group | ZFG_RF_ZDIFHU | 屏幕 9000/9001/9002 + 6 FM（含 INCLUDE /SCWM/IRF_SSCR） |
| 结构 | ZSDIFHU_SCR | 屏幕单值（HUIDENT + SELNO 序号输入） |
| 结构 | ZSDIFHU_ITEM | 列表行（SEQNO + MATNR + MAKTX + QUAN + MEINS + GUID_*） |
| 结构 | ZSDIFHU_PROD | 明细屏（含 QUAN_COUNT 实盘数量） |
| 表类型 | ZSDIFHU_ITEM_TT | 列表内表 |
| App. Parameter | CS_ZDIFHU_S_SCR / CS_ZDIFHU_PROD / CT_ZDIFHU_T_ITEMS | 全局数据容器（Customizing） |
| 消息类 | ZEWM_RF_MSG | FM 全部报错消息（`MESSAGE eNNN(zewm_rf_msg)`） |
| 翻译 | `*.i18n.<语言>.po` | DE / CS / FR / ZH（abapGit LXE，Pull 时写回系统） |
````

- [ ] **Step 2: 全量验证**

```bash
cd /home/tankren/opencode/zdifhu && find . -type f \( -name "*.xml" -o -name "*.abap" -o -name "*.md" \) | sort && for f in $(find . -name "*.xml"); do python3 -c "import xml.dom.minidom,sys; xml.dom.minidom.parse(sys.argv[1])" "$f" || echo "FAIL $f"; done && echo "ALL XML OK"
```

预期：15 个文件清单（对照计划头部"文件结构"）；`ALL XML OK` 且无 `FAIL`。

---

## 自审记录

- **Spec 覆盖**：spec §2 对象表（Task 1-4）、Step Flow/Customizing（Task 11 README §2）、§3.0 接口（Task 4）、§3.1（Task 6）、§3.2（Task 7）、§3.3（Task 8）、§3.4（各 FM 首行 set_lgnum）、§3.5（Task 8 DOWN 分支 + Task 10 flow logic）、§4 布局（Task 9/10）、§5 风险（执行环境说明 §5 + 各任务 ⚠️ 备注）、§6 验收（README §4）。✅
- **占位符**：无 TBD/TODO；所有代码完整。✅
- **类型一致性**：FM 参数名/类型在 fugr.xml、FM 注释头、spec §3.0 三处一致；`refresh_item` FORM（TOP）与 9001_PAI 调用参数一致；屏幕字段名（ZSDIFHU_SCR-*/ZSDIFHU_ITEM-*）与 DDIC 结构、TOP 的 TABLES 声明一致；`gv_cursor`/`gt_zdifhu_items`/`zsdifhu_item`（TABLES 工作区）在 TOP 声明、PBO/PAI、flow logic 三处一致。✅

## 执行后修订（final code review 修复，已同步交付物）

1. **[Critical] step-loop 数据路径**：原稿 TOP 用 `DATA gs_zdifhu_item` 而屏幕字段名为 `ZSDIFHU_ITEM-*`（dynpro 按名绑定全局，二者不匹配 → 列表空白 + PAI 输入不回写 → 零差异守卫失效会误过账全量负差异）。修复：TOP 改 `TABLES: zsdifhu_scr, zsdifhu_item`（删 `gs_zdifhu_item`），screen_9001 两处 LOOP 改 `INTO zsdifhu_item`（PAI 带 INTO 才有行回写），README Plan B 同步。本文档 Task 4/10/11 代码块已更新为修复后版本。
2. **[Important] `gv_cursor` 跨 HU 不重置**：换 HU 后旧游标可能使屏幕 2 空白。修复：9000_PAI 成功路径加 `gv_cursor = 1.`（Task 6 代码块已更新）。

## 执行后修订 2（2026-09-14：屏幕 2 改「列表 → 明细」两步 + dump 根因）

1. **[Critical] 屏幕 2 误过账**：原 9001_PAI 只要 ENTER 且扫到物料就立即 `post_difference`（数量栏输不进 → diff 为 0 → 按 −当前数量过账，库存被清）。修复：改为**序号驱动**——列表屏只选行，过账移到新增的明细屏 9002。
2. **[Bug] 数量栏无法输入 / 显示不全**：列表改为**每物料三行块**（行 1 序号+物料号，行 2 描述，行 3 数量+单位），输入移到明细屏。
3. **[Critical] `GETWA_NOT_ASSIGNED` dump（`LRF_SSCRO02` 第 50 行）根因**：step flow 跨步骤跳转行写了 `PRMOD=2` 且 `FCODE_BCKG` 为空 → 目标步 PBO 模块从不执行 → 表 data container 未注册 → `READ TABLE <gt_scr>` dump。修复：跨步骤行一律 `PRMOD=1` + `FCODE_BCKG=INIT`（见上文修订后的 step flow 表）。
4. **新增对象**：结构 `ZSDIFHU_PROD`、屏幕 9002、FM `Z_RF_ZDIFHU_9002_PBO/_PAI`、App.Parameter `CS_ZDIFHU_PROD`；`ZSDIFHU_SCR` 加 `SELNO`（/SCWM/DE_RF_SEQNO），`ZSDIFHU_ITEM` 加 `SEQNO` 并删 `DIFF_QUAN`。
5. **其他**：`set_scr_tabname` 传 **CHANGING 参数名**（不是表类型名）；`set_line` 传字符 `'1'`；4 个 FM 去掉 `IMPORTING iv_lgnum`（框架不传字段参数），改用 `/scwm/cl_rf_bll_srvc=>get_lgnum( )`。
6. **待验证**：`fugr.xml` 的 RSCHA 缺 `<REFERENCE>X</REFERENCE>`（CHANGING 传值 vs 标准传引用），过账测试若出现「PAI 改了值但屏幕/表没更新」再修。

## 执行后修订 3（2026-09-15：BACK 导航 / 输入属性 / 差异符号 —— 均已系统实测通过）

1. **[Critical] 列表屏按 BACK 被弹回明细屏**：明细屏 `ZDIF3/ENTER` 行若自己换步（`SSTEP=ZDIF2` + `PRMOD=1`），框架走普通导航、内部调用栈仍残留 ZDIF3 → 在列表屏按 BACK 会弹回明细屏。修复：`ZDIF3/ENTER` 行改为 **`SSTEP=ZDIF3` + `PRMOD=0`**（对齐标准 `/SCWM/RF_XDIFHU` 的 `XDDIPR ENTER`），返回由 `9002_PAI` 结尾的 `set_prmod('1') + set_fcode('UPDBCK')` 完成（`UPDBCK` = 回上一步 + 同步调用栈 + 刷新目标步 PBO）。**框架的 `BACK` 是弹内部调用栈，不读 step flow 行的 SSTEP。**
2. **[Critical] 输入框输不进去**：`ZSDIFHU_PROD-QUAN_COUNT` 的 dynpro 属性多了 `<REQU_ENTRY>N</REQU_ENTRY>`。标准 RF 的输入字段从不带 REQU_ENTRY（对照 `/SCWM/RF_INQUIRY_PM`：`INPUT_FLD=X` 36 个、`REQU_ENTRY=N` 356 个，**交集 0**）。修复：删该元素 + 在 PBO 里显式 `set_screlm_input_on( 'ZSDIFHU_PROD-QUAN_COUNT' )` / `set_screlm_input_on( 'ZSDIFHU_SCR-SELNO' )`。
3. **[Critical] 差异符号反了**（实测 96 → 输入 48 → 变 144）：`post_difference` 的 `is_quan-quan` **正数 = 发货（库存减少）、负数 = 收货（库存增加）**（内部按正负选 `wmegc_lime_post_outbound` / `wmegc_lime_post_inbound`）。修复：`lv_diff = cs_zdifhu_prod-quan - cs_zdifhu_prod-quan_count.`（盘亏为正 → 减库存）。
4. **[Bug] 过账后返回列表时序号没清空**：`9002_PAI` 过账成功分支加 `CLEAR cs_zdifhu_prod-quan_count.` + `CLEAR cs_zdifhu_s_scr-selno.`。
5. **[配置] 漏配数据容器 → ENTER 直接 dump**：`/SCWM/TPARAM_CAT` 缺 `CS_ZDIFHU_PROD → ZSDIFHU_PROD` 时，框架拼参数表失败 → `CALL_FUNCTION_PARM_MISSING`（FM 体根本没执行）。三行必须齐：`CS_ZDIFHU_S_SCR` / `CT_ZDIFHU_T_ITEMS` / `CS_ZDIFHU_PROD`。
6. ~~**遗留**：早期误过账（库存 96→144）已落库，需人工做更正凭证。~~ **已关闭**：这是开发系统，
   过账数据本身无所谓，无需更正凭证（用户 2026-09-15 确认）。

## 执行后修订 4（2026-09-15：消息类 ZEWM_RF_MSG + 多语言 LXE —— 已系统实测通过）

1. **报错消息改用消息类**：原来 9 处 `MESSAGE e001(00) WITH '…'(nnn)`（文本符号写法）全部改为
   `MESSAGE eNNN(zewm_rf_msg)`；消息类 `ZEWM_RF_MSG` 由 `src/zewm_rf_msg.msag.xml` 交付（Pull 时导入，
   无需单独激活）。消息号沿用原编号：001/002/003（`9000_pai`）、008/009（`9001_pai`）、
   010/011/006/007（`9002_pai`）。
2. **多语言（DE/CS/FR/ZH）走 abapGit LXE**：新增 8 个 gettext PO 文件 ——
   `zfg_rf_zdifhu.fugr.i18n.<语言>.po`（4 个屏幕标签 + 3 个屏幕描述）与
   `zewm_rf_msg.msag.i18n.<语言>.po`（9 条消息）；仓库根 `.abapgit.xml` 增加 `<I18N_LANGUAGES>`
   （CS/DE/FR/ZH）+ `<USE_LXE>X</USE_LXE>`。Pull 时 abapGit 按**英文源文本**匹配 PO 的 `msgid`，
   把 `msgstr` 经 FM `LXE_OBJ_TEXT_PAIR_WRITE` 写回系统 —— **不需要任何 SE63 操作**
   （用户实测中文 OK）。
3. **注意**：PO 按源文本匹配，英文原文（大小写 / 尾部空格）不一致的条目会被静默跳过；屏幕标签不能
   超过字段宽度（`HU`=2 / `No.`=3 / `HU:`=3 / `Actual Qty`=10）。
4. **「执行后修订 2」第 6 条（RSCHA 缺 `REFERENCE`）已关闭**：CHANGING 参数传值/传引用在本流程中
   未造成问题（跨步骤容器传递、过账、列表刷新均实测正常），不再改动。
5. **消息类改名 `ZEWM_MSG` → `ZEWM_RF_MSG`**：用户在 SE91 直接重命名（消息号、译文、传输记录随对象走，
   不需要建新删旧）。仓库侧同步：`src/zewm_rf_msg.msag.xml`（含 T100A/T100 的 ARBGB）+ 4 个
   `zewm_rf_msg.msag.i18n.<语言>.po` 改名（PO 内容只有 msgid/msgstr，不含对象名）+ 3 个 FM 里
   9 处 `MESSAGE eNNN(zewm_rf_msg)` + 文档。**PO 文件名必须与消息类名一致**，否则 abapGit 找不到对象；
   Pull 时对象已存在（新名字）→ 直接更新，不会留下旧对象。


## 执行后修订 5（2026-09-16：HUINFO 按钮 + 屏幕 9004 HU 明细屏 —— 已系统实测通过）

1. **需求**：在列表屏（屏幕 2 / 步 ZDIF2）加一个按钮，照抄标准 RF 查询事务 `INHUOV` 的 **HUINFO** 按钮，
   进入一个显示 HU 抬头明细的新屏幕。
2. **为什么不复用标准 FM**：标准 `/SCWM/RF_INQ_INHULT_PAI` 的 `HUINFO` 分支读的是它自己的容器
   `CS_INQ_HU-HUIDENT`，我们的流程里该字段为空 → 复用会报 `e300`（HU is empty）。改为**在自己 PAI 里抄
   标准逻辑**：`9001_PAI` 新增 `WHEN 'HUINFO'` 分支（清 selno / 清 `cs_zdifhu_hu` / HU 号空 → `e001` /
   `CONVERSION_EXIT_ALPHA_INPUT` / `/SCWM/HU_READ` → `ls_huhdr` / 空 → `e002` / `MOVE-CORRESPONDING` 填
   `cs_zdifhu_hu` / 库位回退链 `lgpla → rsrc → tu_num → wsbin` / 包装物料 `pmat = ls_huhdr-pmat_guid`（RAW16，
   屏幕字段带 `CONV_EXIT=MDLPD` 自动显示物料号）/ `huident = cs_zdifhu_s_scr-huident`）。**分支只填容器，
   不 `set_fcode` 跳屏** —— 跳屏由 step flow 的 `ZDIF2/HUINFO` 行完成。
3. **新增对象**：屏幕 `9004`（**标准屏 `/SCWM/SAPLRF_INQUIRY_PM` 0202 的逐字节克隆**：13×27、38 个字段，
   只改 PROGRAM / SCREEN / NEXTSCREEN / DESCRIPT；含之前漏掉的 `MAX_WEIGHT` / `MAX_VOLUME` / `HAZMAT_IND`）、
   FM `Z_RF_ZDIFHU_9004_PBO`（只 `init_screen_param( ) + set_screen_param( 'CS_ZDIFHU_HU' )`）/
   `Z_RF_ZDIFHU_9004_PAI`（只有 BACK 空处理）、App.Parameter `CS_ZDIFHU_HU → /SCWM/S_RF_INQ_HU`（**复用标准
   结构，不新建 DDIC 对象**）、TOP include 加 `TABLES /scwm/s_rf_inq_hu.`。交付文件 28 → **31 个**。
4. **注意（踩过的坑）**：
   - 手搭的 7×40 屏幕会被 `RPY_DYNPRO_INSERT` 拒掉（整个 FUGR 反序列化失败 → 看不到屏幕 9004）→
     **直接克隆标准屏幕**才稳。
   - 同一个 dynpro 屏幕**不允许两个同名字段**；标准屏里的“同名”都是「`TEXT` 标签字段 + `TEMPLATE`
     字段」配对（9004 里 14 组），不是错误。
   - 新容器必须先配 `/SCWM/TPARAM_CAT` 行，否则按任何键都 `CALL_FUNCTION_PARM_MISSING`
     （dump 里报 `CS_ZDIFHU_HU`）；`/SCWM/TSTEP_SCR` 里 ZDIF4 若指向标准程序 `/SCWM/SAPLRF_INQUIRY_PM`
     屏幕 `202`，要改成 `SAPLZFG_RF_ZDIFHU` / `9004`。
5. **系统最终配置（已实测）**：`/SCWM/TSTEP_FLOW` 12 行（新增 `ZDIF2/HUINFO → 9001_PAI, SSTEP=ZDIF4,
   PRMOD=1, FCODE_BCKG=INIT`；`ZDIF4/INIT → 9004_PBO, PRMOD=2`；`ZDIF4/BACK → 9004_PAI, SSTEP=ZDIF2,
   PRMOD=1, FCODE_BCKG=INIT`）；`/SCWM/TSTEP_SCR` ZDIF4 → `SAPLZFG_RF_ZDIFHU`/`9004`；`/SCWM/TFCOD_PRF`
   `ZDIF2/HUINFO`（PUSHB=PB1 / FNKEY=F1 / SHORTCUT=01）+ `ZDIF4/BACK`；`/SCWM/TPARAM_CAT` 4 行。
