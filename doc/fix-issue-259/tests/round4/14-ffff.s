; 14-ffff: 256-byte incrementing REU verify of uniform data with the KERNAL
; banked out and a chosen byte at RAM $FFFF, display on. Tells a floating data
; bus (the REC compares $FF) from a floating address bus (the FPGA serves the
; byte at $FFFF). Issue #259, round 4.
;
; Load address $0C00, behind the BASIC driver. Interface:
;   $0C00  JMP entry            SYS 3072
;   $0C03  data byte D (input)  POKE 3075,d
;   $0C04  byte for $FFFF F     POKE 3076,f
;   $0C05  runs (input)         POKE 3077,n
;   $0C06  faults (output)      PEEK(3078)
;   $0C07  status of the verify with the display off (output: bit 5 must be clear)
.setcpu "6502"
.org $0c00
        jmp entry
dval:   .byte $ff
fval:   .byte 0
runs:   .byte 50
faults: .byte 0
chk:    .byte 0
save01: .byte 0
        .res 4
entry:
        php
        sei
        lda dval
        ldx #0
l1:     sta $4000,x             ; uniform data
        inx
        bne l1
        lda $d011
        and #$ef
        sta $d011               ; display off
        jsr frame
        jsr setregs
        lda #$b0
        sta $df01               ; stash 256 bytes (autoload)
        lda #$b3
        sta $df01               ; verify with the display off (autoload)
        lda $df00
        sta chk
        lda $01
        sta save01
        lda #$35
        sta $01                 ; BASIC and KERNAL out, I/O in: $FFFF is RAM
        lda fval
        sta $ffff               ; what a drifting address bus would hit
        lda $d011
        ora #$10
        sta $d011               ; display on
        jsr frame
        jsr frame
        lda #0
        sta faults
        ldx runs
rl:     lda #$b3
        sta $df01               ; verify (autoload restores the registers)
        lda $df00
        and #$20
        beq ok
        inc faults
ok:     dex
        bne rl
        lda save01
        sta $01
        plp
        rts

setregs:
        lda #0
        sta $df09
        sta $df0a               ; both addresses incrementing
        sta $df02
        sta $df04
        sta $df05
        sta $df06
        sta $df07
        lda #$40
        sta $df03               ; C64 address $4000
        lda #1
        sta $df08               ; length 256
        rts

; wait for a frame boundary: line 100, then $D012 = 10
frame:  lda $d012
        cmp #100
        bne frame
f2:     lda $d012
        cmp #10
        bne f2
        rts
