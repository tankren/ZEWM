# ZEWM

ABAP repository for the EWM RF enhancements in system `S4H` (client `100`), serialized with abapGit.
All objects live under `src/`, one folder per package.

| Package | Folder | Documentation |
|---|---|---|
| `ZEWM_ZCHGSB` | [`src/zewm_zchgsb/`](src/zewm_zchgsb/) | [English](src/zewm_zchgsb/README.md) · [中文](src/zewm_zchgsb/README.zh.md) |
| `ZEWM_ZDIFHU` | [`src/zewm_zdifhu/`](src/zewm_zdifhu/) | [English](src/zewm_zdifhu/README.md) · [中文](src/zewm_zdifhu/README.zh.md) |
| `ZEWM_MSG` | [`src/zewm_msg/`](src/zewm_msg/) | message class `ZEWM_RF_MSG` (5 languages) |
| `ZEWM_ITPLUS` | [`src/zewm_itplus/`](src/zewm_itplus/) | RF screens (SCP1) |

## Import

1. In the target system: **abapGit → New Online Repository**, URL `https://github.com/tankren/ZEWM.git`,
   package for the first folder (`.abapgit.xml` has `STARTING_FOLDER = /src/`, `FOLDER_LOGIC = FULL`).
2. Make sure the repo settings carry **Serialize Translations (experimental LXE approach)** = on and
   languages `DE,CS,FR,ZH` — otherwise the `.i18n.*.po` files are skipped.
3. **Pull**. Code objects activate automatically; Customizing (exception codes, step flow, RF function
   keys) is **not** part of the repo and has to be maintained manually — see the package README.

Language of the master texts is `E`; translated texts are shipped as `.po` files next to each object.
