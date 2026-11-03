FUNCTION z_rf_chgsb_0100_pbo
  CHANGING
    ordim_confirm    TYPE /scwm/s_rf_ordim_confirm
    tt_ordim_confirm TYPE /scwm/tt_rf_ordim_confirm
    tt_nested_hu     TYPE /scwm/tt_rf_nested_hu
    wme_verif        TYPE /scwm/s_wme_verif
    resource         TYPE /scwm/s_rsrc
    t_rf_pick_hus    TYPE /scwm/tt_rf_pick_hus
    who              TYPE /scwm/s_who_int.
*----------------------------------------------------------------------*
* PIMTTO 屏幕按 CHGSB → 本屏（换源货位）
* PBO 职责：把框架已装入 ORDIM_CONFIRM 的当前拣货行显示到屏幕，
*           并清空「新货位」输入字段，等用户扫码。只读，不写库。
* 签名与 /SCWM/RF_PICK_PIMTTO_PBO 一致，框架按同名 CHANGING 传参。
*----------------------------------------------------------------------*

  DATA: lv_lgnum TYPE /scwm/lgnum.

  lv_lgnum = /scwm/cl_rf_bll_srvc=>get_lgnum( ).
  /scwm/cl_tm=>set_lgnum( lv_lgnum ).

*----------------------------------------------------------------------*
* 1. 原拣货行 → 屏幕展示
*----------------------------------------------------------------------*
  CLEAR gs_chgsb_scr.

  gs_chgsb_scr-vltyp   = ordim_confirm-vltyp.     " 源库存类型
  gs_chgsb_scr-vlpla   = ordim_confirm-vlpla.     " 原货位
  gs_chgsb_scr-vsola   = ordim_confirm-vsola.     " 应拣数量
  gs_chgsb_scr-huident = ordim_confirm-huident.   " 处理单元
  gs_chgsb_scr-tanum   = ordim_confirm-tanum.     " WT 号
  gs_chgsb_scr-vlenr   = ordim_confirm-vlenr.     " WT 行号

* TODO 物料号 / 批号转换（GUID → 可读值）待接：
*   MATID   → /SCWM/MATID_TO_MATNR_MULTIPLE
*   BATCHID → /SCWM/GET_BATCHID_MULTIPLE
* 这两个函数已核实存在，参数结构待读源码后补。
* 屏幕字段先用 GUID，等结构确认后替换。
  gs_chgsb_scr-matid   = ordim_confirm-matid.
  gs_chgsb_scr-batchid = ordim_confirm-batchid.

* 每次进屏清空输入字段，避免上一轮残留
  CLEAR: gs_chgsb_scr-newlgpla,
         gs_chgsb_scr-newlgtyp.

* 显式打开输入字段属性
* （zdifhu 踩坑：dynpro 字段若带 REQU_ENTRY，在 RF 里会变成不可输入，
*   必须由 PBO 调 set_screlm_input_on 打开）
  /scwm/cl_rf_bll_srvc=>set_screlm_input_on( 'GS_CHGSB_SCR-NEWLGPLA' ).

*----------------------------------------------------------------------*
* 2. 状态行
*----------------------------------------------------------------------*
  gs_chgsb_scr-txt = 'Scan new source bin'(001).
ENDFUNCTION.
