; 14-ffff: 256-byte incrementing REU verify of uniform data D with the KERNAL
; banked out, started at raster line 50 (badline at 51, like 12-position), with
; a chosen byte F at RAM $FFFF and in every RAM range a drifting address bus
; from $20xx could land in ($2100-$3FFF, $6000-$7FFF, $A000-$BFFF, $E000-$FFFF).
; Tells a floating data bus (the REC compares $FF: faults iff D <> $FF) from a
; floating address bus (the FPGA serves F: faults iff D <> F). Issue #259, round 4.
;
; Load address $0C00, behind the BASIC driver. Interface:
;   $0C00  JMP entry             SYS 3072
;   $0C03  data byte D (input)   POKE 3075,d
;   $0C04  byte F (input)        POKE 3076,f
;   $0C05  runs (input)          POKE 3077,n
;   $0C06  faults (output)       PEEK(3078)
;   $0C07  status of the verify with the display off (output: bit 5 must be clear)
;   $0C08  $DF02 after the first fault (output; byte index = $DF02/03 - $2001)
;   $0C09  $DF03 after the first fault
.setcpu "6502"
.org $0c00
        jmp entry
dval:   .byte $ff
fval:   .byte 0
runs:   .byte 10
faults: .byte 0
chk:    .byte 0
flo:    .byte 0
fhi:    .byte 0
save01: .byte 0
        .res 5
entry:
        php
        sei
        lda dval
        ldx #0
l1:     sta $2000,x             ; uniform data at $2000..$20FF
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
        sta $01                 ; BASIC and KERNAL out, I/O in: $A000-$BFFF and $E000-$FFFF are RAM
        ldx #$21                ; F into every page a drifting $20xx address could reach
        ldy #$40
        jsr fillf               ; $2100-$3FFF
        ldx #$60
        ldy #$80
        jsr fillf               ; $6000-$7FFF
        ldx #$a0
        ldy #$c0
        jsr fillf               ; $A000-$BFFF
        ldx #$e0
        ldy #$00
        jsr fillf               ; $E000-$FFFF (Y = 0 wraps: stop after page $FF)
        lda #<nmi
        sta $fffa
        lda #>nmi
        sta $fffb               ; RESTORE while the KERNAL is out: RTI
        lda $d011
        ora #$10
        sta $d011               ; display on
        jsr frame
        jsr frame
        lda #0
        sta faults
        sta flo
        sta fhi
runloop:
        jsr setregs             ; no autoload: fresh registers every run
w0:     lda $d011
        bmi w0                  ; raster MSB must be 0
        lda $d012
        cmp #49
        bne w0                  ; now in line 49
w1:     lda $d012
        cmp #50
        bne w1                  ; start of line 50, jitter below 11 cycles
        lda #$93
        sta $df01               ; verify, no autoload, execute now (badline at 51)
        lda $df00
        and #$20
        beq ok
        lda faults
        bne f1
        lda $df02
        sta flo
        lda $df03
        sta fhi                 ; registers after the first fault
f1:     inc faults
ok:     dec runs
        bne runloop
        lda save01
        sta $01
        plp
        rts
nmi:    rti

; fill pages X .. Y-1 with F (Y = 0: up to and including page $FF)
fillf:  stx $fc
        lda #0
        sta $fb
        lda fval
fp:     ldx #0
fb:     sta ($fb,x)
        inc $fb
        bne fb
        inc $fc
        cpy $fc
        bne fp
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
        lda #$20
        sta $df03               ; C64 address $2000
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
