; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Variables for Directory Browser (dirbrowse.asm): Need to be located in RAM
;
; done by sy2002 in 2022 and licensed under GPL v3
; ****************************************************************************

_DIRBR_FILTERFN .BLOCK  1                       ; pointer to filter function
_DIRBR_NAMEBUF  .BLOCK  1                       ; name buffer (DIRBR$GETNAME)
_DIRBR_NWIN     .BLOCK  1                       ; name store: current window
_DIRBR_NOFS     .BLOCK  1                       ; name store: next free offset

_DIRBR_FH       .BLOCK  FAT32$FDH_STRUCT_SIZE   ; file handle
_DIRBR_ENTRY    .BLOCK  FAT32$DE_STRUCT_SIZE    ; directory entry

_SLL_TAIL       .BLOCK  1                       ; current tail of the list
                                                ; under construction
