PROCESS BEFORE OUTPUT.
  LOOP AT gt_zdifhu_items INTO zsdifhu_item CURSOR gv_cursor.
  ENDLOOP.
*
PROCESS AFTER INPUT.
  LOOP AT gt_zdifhu_items INTO zsdifhu_item.
  ENDLOOP.
