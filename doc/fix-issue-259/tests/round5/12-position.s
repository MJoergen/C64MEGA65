; 12-position: raster-synchronized 256-byte incrementing REU verify without
; autoload. After the transfer the REC registers tell at which byte the verify
; stopped, a CIA timer tells how many cycles it took. Issue #259, round 3.
;
; Load address $0C00, behind the BASIC driver. Interface:
;   $0C00  JMP entry            SYS 3072
;   $0C03  runs (input, 1..20)  POKE 3075,n
;   $0C04  raster line (input)  POKE 3076,l   (0..255, MSB of the raster must be 0)
;   $0C05  status of the verify with the display off (output: bit 5 clear; a 1764
;          reads 80 = end of block + size bit, a 1700 reads 64)
;   $0E00  result table, 16 bytes per run:
;          0 status  1 $DF02  2 $DF03  3 $DF04  4 $DF05  5 $DF07  6 $DF08
;          7 timer lo  8 timer hi (timer started 6 cycles before the command write and
;            stopped 14 cycles after the CPU resumed: transfer = 65535 - timer - 20)
;          9 $D012 right after the transfer  10 $D011 right after the transfer
.setcpu "6502"
.org $0c00
        jmp entry
runs:    .byte 10
line:    .byte 50
chk:     .byte 0
linem1:  .byte 0
run_idx: .byte 0
tlo:     .byte 0
thi:     .byte 0
        .res 5
entry:
        php
        sei
        ldx #0
l1:     txa
        sta $4000,x             ; data 0..255
        inx
        bne l1
        lda line
        sec
        sbc #1
        sta linem1
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
        lda $d011
        ora #$10
        sta $d011               ; display on
        jsr frame
        jsr frame
        lda #0
        sta run_idx
        lda #<table
        sta $fb
        lda #>table
        sta $fb+1
runloop:
        jsr setregs             ; no autoload: fresh registers every run
        lda #$ff
        sta $dd04
        sta $dd05               ; timer A latch $FFFF
        lda #0
        sta $dd0e               ; timer A stopped
w0:     lda $d011
        bmi w0                  ; raster MSB must be 0
        lda $d012
        cmp linem1
        bne w0                  ; now in the line before
w1:     lda $d012
        cmp line
        bne w1                  ; start of the line, jitter below 11 cycles
        lda #$11
        sta $dd0e               ; timer A: force load, start, continuous
        lda #$93
        sta $df01               ; verify, no autoload, execute now
        ; --- the CPU is halted here until the REC releases the bus ---
        ldx $d012               ; raster at the end, read first
        ldy $d011
        lda #0
        sta $dd0e               ; stop the timer: 14 cycles after the CPU resumed
        stx tlo                 ; (tlo/thi reused as scratch for the raster)
        sty thi
        ldy #0
        lda $df00
        sta ($fb),y
        iny
        lda $df02
        sta ($fb),y
        iny
        lda $df03
        sta ($fb),y
        iny
        lda $df04
        sta ($fb),y
        iny
        lda $df05
        sta ($fb),y
        iny
        lda $df07
        sta ($fb),y
        iny
        lda $df08
        sta ($fb),y
        iny
        lda $dd04
        sta ($fb),y
        iny
        lda $dd05
        sta ($fb),y
        iny
        lda tlo
        sta ($fb),y             ; $D012 at the end
        iny
        lda thi
        sta ($fb),y             ; $D011 at the end
        lda $fb
        clc
        adc #16
        sta $fb
        bcc nc
        inc $fb+1
nc:     inc run_idx
        lda run_idx
        cmp runs
        bcs finish
        jmp runloop
finish: plp
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

; wait for a frame boundary: line 100, then $D012 = 10 (that is raster line 266, which is
; fine: no badlines there either)
frame:  lda $d012
        cmp #100
        bne frame
f2:     lda $d012
        cmp #10
        bne f2
        rts

        .res $0e00 - *
table:  .res 16*20
