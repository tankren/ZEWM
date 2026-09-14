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
