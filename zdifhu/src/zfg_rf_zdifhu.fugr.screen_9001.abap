PROCESS BEFORE OUTPUT.
  MODULE status_sscr_loop.
  LOOP.
    MODULE loop_output.
  ENDLOOP.
  MODULE loop_scrolling_set.
  MODULE set_display_only.
*
PROCESS AFTER INPUT.
  LOOP.
    MODULE loop_input.
  ENDLOOP.
  MODULE user_command_sscr.
