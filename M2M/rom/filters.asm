; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; MiSTer filter management
;
; The file filter.asm needs the environment of shell.asm.
;
; done by sy2002 in 2022 and licensed under GPL v3
; ****************************************************************************

; more details: see ../vhdl/av_pipeline/video_filters/README.md
#include "../video_filters/lanczos2_12.asm"
#include "../video_filters/Scan_Br_110_80.asm"

; currently, we only support filters with 4 signed 10-bit integers per line,
; 64 lines, i.e. 256 data points
ASCAL_FILTER_LEN    .EQU 0x0100


; LOAD_ASCAL_FLT  Framework default polyphase load.
;                 Loads the V1 "CRT emulation" filter pair (Lanczos2_12
;                 horizontal + Scan_Br_110_80 vertical) into the ascal
;                 polyphase RAM. Called once from ASCAL_INIT at boot.
;
;                 A core that wants a different default, multiple selectable
;                 pairs, or runtime swapping should call M2M$LOAD_POLYPHASE
;                 directly from its own PREP_START / OSM_SEL_POST callbacks.
;                 See M2M/video_filters/README.md for the full pattern.

LOAD_ASCAL_FLT  SYSCALL(enter, 1)
                MOVE    LANCZOS2_12,    R8
                MOVE    SCAN_BR_110_80, R9
                RSUB    M2M$LOAD_POLYPHASE, 1
                SYSCALL(leave, 1)
                RET
