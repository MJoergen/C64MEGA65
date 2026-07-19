; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Variables for Options Menu (menu.asm): Need to be located in RAM
;
; done by sy2002 in 2023 and licensed under GPL v3
; ****************************************************************************

; screen coordinates
OPTM_X          .BLOCK 1
OPTM_Y          .BLOCK 1
OPTM_DX         .BLOCK 1
OPTM_DY         .BLOCK 1

; currently active (sub)menu level; 0 means main menu
OPTM_MENULEVEL  .BLOCK 1

; leave bookkeeping, written by _OPTM_STRUCT on every structure build:
; region id of the parent of the current menu level (0 = main menu) and
; flat index of the opener line of the current menu level. _OPTM_RUN_SM_L
; uses them to pop exactly one menu level with the cursor landing on the
; label of the (sub)menu the user came from.
OPTM_LVL_PARENT .BLOCK 1
OPTM_LVL_OPENER .BLOCK 1

; currently selected menu item (real-time)
OPTM_CUR_SEL    .BLOCK 1

; pointer to initialization record (see menu.asm for more details)
OPTM_DATA       .BLOCK 1

; single-select vs multi-select item flag
OPTM_SSMS       .BLOCK 1

; ptr to the _OPTM_STRUCT menu struct. (only valid while OPTM_RUN is running)
OPTM_STRUCT     .BLOCK 1

; 1 while the options menu owns the visible surface and background updates may
; paint it directly; 0 while the menu is closed or a selection callback may be
; showing a browser, help page or another temporary surface
OPTM_FOREGROUND .BLOCK 1

; temporary variable
OPTM_TEMP       .BLOCK 1
