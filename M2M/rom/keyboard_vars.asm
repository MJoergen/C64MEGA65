; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Variables for Keyboard Controller (keyboard.asm): Need to be located in RAM
;
; originally made for gbc4mega65 by sy2002 in 2021
; adpoted for MiSTer2MEGA65 by sy2002 in 2021 and licensed under GPL v3
; ****************************************************************************

; each key represented by one bit in these two words
KEYB_PRESSED    .BLOCK 1                        ; currently pressed
KEYB_NEWKEYS    .BLOCK 1                        ; newly pressed since last..
                                                ; ..call of KEYB_GETKEY

; typematic repeat of the cursor keys, two words per key: the time
; (IO$CYC_MID) of the press or of the last repeat, followed by the state:
; 0 = not pressed, 1 = pressed and waiting for the delay, 2 = repeating;
; expected to be a consecutive block of KEYB_TYPEM_WORDS words starting with
; KEYB_CDN_TIME
KEYB_CDN_TIME   .BLOCK 1
KEYB_CDN_STATE  .BLOCK 1
KEYB_CUP_TIME   .BLOCK 1
KEYB_CUP_STATE  .BLOCK 1
KEYB_CLF_TIME   .BLOCK 1
KEYB_CLF_STATE  .BLOCK 1
KEYB_CRT_TIME   .BLOCK 1
KEYB_CRT_STATE  .BLOCK 1
KEYB_TYPEM_WORDS .EQU 8
