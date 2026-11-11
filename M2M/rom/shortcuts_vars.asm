; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Variables for the keyboard shortcuts (shortcuts.asm): Need to be located in
; RAM. See also OPTM_DIRECT in shell_vars.asm.
;
; done by sy2002 in 2026 and licensed under GPL v3
; ****************************************************************************

; SC$INIT clears these first four variables in one go: keep them together
SC_REP_KEY      .BLOCK 1                        ; key repeat: M2M$KEY_* of the
                                                ; held key (0 = no repeat)
SC_TOAST_ON     .BLOCK 1                        ; 1: the message is visible
SC_SAVE_PEND    .BLOCK 1                        ; 1: settings need to be saved
ROSM_FORCE      .BLOCK 1                        ; 1: ROSM_SAVE saves even if
                                                ; ROSM_CHANGES sees no change;
                                                ; ROSM_SAVE sets 2 if a dirty
                                                ; write cache blocked saving

; Invisible menu session (SC$SESSION and SC$PRESS)
SC_S_ROUTINE    .BLOCK 1                        ; routine to run in the session
SC_S_ARG        .BLOCK 1                        ; its input (R8)
SC_S_RESULT     .BLOCK 1                        ; its output (R8)
SC_P_TARGET     .BLOCK 1                        ; flat index of the menu line
                                                ; that SC$PRESS selects
SC_P_STEP       .BLOCK 1                        ; step of the scripted keys
SC_P_DONE       .BLOCK 1                        ; 1: Return hit the target line

; Key repeat for actions that the core marks as repeatable (e.g. volume)
SC_REP_FKEY     .BLOCK 1                        ; function key index 0..5
SC_REP_T        .BLOCK 1                        ; IO$CYC_MID of the last trigger
SC_REP_DLY      .BLOCK 1                        ; ticks until the next repeat

; One-line on-screen message ("toast")
SC_TOAST_T      .BLOCK 1                        ; IO$CYC_MID when it was shown
SC_TOAST_BUF    .BLOCK 48                       ; zero terminated message text
                                                ; (SC_TOAST_LEN + 1 words)
SC_DIGITS       .BLOCK 4                        ; digits of a number in a message

; Deferred saving of settings that shortcuts changed while the OSM was closed
SC_SAVE_T       .BLOCK 1                        ; IO$CYC_MID of the last change
OPTM_DIRECT     .BLOCK 1                        ; TEMP142: defined by mh_142_nextdisk
