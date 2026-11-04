; 11-bitfill: the CMD REUTEST "Bit Fill" chain (SYS ML+15 of REUTEST, $33F4),
; replayed in machine code for one bank and one pattern, with one element of
; the chain removed per variant. Issue #259, round 3.
;
; Load address $0C00, behind the BASIC driver. Interface:
;   $0C00  JMP entry             SYS 3072
;   $0C03  variant (input)       POKE 3075,v
;   $0C04  faults, fixed-REU verifies   PEEK(3076)  0..4
;   $0C05  CPU check faults             PEEK(3077)
;   $0C06  faults, fixed-C64 verifies   PEEK(3078)  0..4
;   $0C07  first fault                  PEEK(3079)  0 = none, else quarter*2 + 1 (fixed REU) or + 2 (fixed C64)
;
; Variants:
;   0  exact chain, cycle-exact copy of REUTEST $3426..$3470 up to the first fault: SEI,
;      $FF00, 8 sprites, per quarter: stash(fixed C64), swap, stash, fetch, CPU check of
;      $5000, verify(fixed REU), verify(fixed C64). REUTEST stops at the first fault, the
;      replay goes on and counts.
;   1  no swap          2  no sprites       3  CLI instead of SEI
;   4  no $FF00 writes  5  no fetch (and no CPU check)
;   6  stash(fixed C64) + verify(fixed C64) only       (CBR Refresh a, 16 KB)
;   7  stash(fixed C64) + verify(fixed REU) + verify(fixed C64)   (7-CHAIN c)
;   8  exact chain, but after every fetch the CPU writes $55 into $7000: the fixed-REU
;      verify must then fault at byte $2000 of every quarter if it compares at all
;   9  the same as 8 with the display switched off (no VIC stalls): the positive control
; $5000..$8FFF is filled with $AA by the CPU at entry, so the fixed-REU verify has valid
; data in every variant (REUTEST gets it from its swap and fetch).
.setcpu "6502"
.org $0c00
        jmp entry
variant:  .byte 0
faults_r: .byte 0
cpufail:  .byte 0
faults_c: .byte 0
first:    .byte 0
quarter:  .byte 0
        .res 8
entry:
        php
        sei
        lda #0
        sta faults_r
        sta cpufail
        sta faults_c
        sta first
        sta quarter
        ; C64 buffer $5000..$8FFF := $AA
        lda #$50
        sta $fc
        lda #0
        sta $fb
        tay
        lda #$aa
fill:   sta ($fb),y
        iny
        bne fill
        inc $fc
        ldx $fc
        cpx #$90
        bne fill
        lda variant
        cmp #3
        bne v_sei
        cli
v_sei:  lda variant
        cmp #4
        beq v_noff00a
        lda #$0e
        sta $ff00
v_noff00a:
        lda variant
        cmp #2
        beq v_nosprites
        jsr sprites_on
v_nosprites:
        ; REC registers exactly like REUTEST $3400..$3423
        lda #0
        sta $df09
        sta $df02
        sta $df04
        sta $df05
        sta $df06
        lda #$50
        sta $df03
        lda #$40
        sta $df08
        lda #0
        sta $df07
        lda variant
        beq exact
        cmp #8
        beq planted
        cmp #9
        beq planted_off
        jsr generic
        jmp done
exact:  jsr exact_chain
        jmp done
planted:
        jsr exact_plant
        jmp done
planted_off:
        lda $d011
        and #$ef
        sta $d011               ; display off, wait for the badlines to stop
        jsr frame
        jsr frame
        jsr exact_plant
        lda $d011
        ora #$10
        sta $d011
done:   lda #0
        sta $d015
        lda variant
        cmp #4
        beq done2
        lda #0
        sta $ff00
done2:  plp
        rts

; ---- variant 0: REUTEST $3426..$3470 verbatim, BNE to the error exits replaced by
;      BNE to the counters (not taken while everything passes: same cycle count)
exact_chain:
e_q:    lda #$80
        sta $df0a
        lda #$aa                ; REUTEST: LDA $FA (3 cycles); LDA # is 2, the only difference
        sta $5000
        lda #$b0
        sta $df01               ; stash, fixed C64
        lda #$00
        sta $df0a
        lda #$b2
        sta $df01               ; swap
        lda #$b0
        sta $df01               ; stash
        lda #$b1
        sta $df01               ; fetch
        lda $5000
        cmp #$aa                ; REUTEST: CMP $FA (3 cycles)
        bne e_cpu
e_vr:   lda #$40
        sta $df0a
        lda #$b3
        sta $df01               ; verify, fixed REU
        lda #$20
        bit $df00
        bne e_fr
e_vc:   lda #$80
        sta $df0a
        lda #$b3
        sta $df01               ; verify, fixed C64
        lda #$20
        bit $df00
        bne e_fc
e_next: lda #$40
        clc
        adc $df05
        sta $df05
        beq e_done
        inc quarter
        jmp e_q
e_done: rts
e_cpu:  inc cpufail
        jmp e_vr
e_fr:   inc faults_r
        lda first
        bne e_vc
        lda quarter
        asl a
        clc
        adc #1
        sta first
        jmp e_vc
e_fc:   inc faults_c
        lda first
        bne e_next
        lda quarter
        asl a
        clc
        adc #2
        sta first
        jmp e_next

; ---- variants 8 and 9: the exact chain, plus a planted mismatch after the fetch
exact_plant:
p_q:    lda #$80
        sta $df0a
        lda #$aa
        sta $5000
        lda #$b0
        sta $df01               ; stash, fixed C64
        lda #$00
        sta $df0a
        lda #$b2
        sta $df01               ; swap
        lda #$b0
        sta $df01               ; stash
        lda #$b1
        sta $df01               ; fetch
        lda $5000
        cmp #$aa
        bne p_cpu
p_pl:   lda #$55
        sta $7000               ; the planted mismatch, byte $2000 of the C64 buffer
p_vr:   lda #$40
        sta $df0a
        lda #$b3
        sta $df01               ; verify, fixed REU
        lda #$20
        bit $df00
        bne p_fr
p_vc:   lda #$80
        sta $df0a
        lda #$b3
        sta $df01               ; verify, fixed C64
        lda #$20
        bit $df00
        bne p_fc
p_next: lda #$40
        clc
        adc $df05
        sta $df05
        beq p_done
        inc quarter
        jmp p_q
p_done: rts
p_cpu:  inc cpufail
        jmp p_pl
p_fr:   inc faults_r
        lda first
        bne p_vc
        lda quarter
        asl a
        clc
        adc #1
        sta first
        jmp p_vc
p_fc:   inc faults_c
        lda first
        bne p_next
        lda quarter
        asl a
        clc
        adc #2
        sta first
        jmp p_next

; wait for a frame boundary: $D012 = 100, then $D012 = 10
frame:  lda $d012
        cmp #100
        bne frame
f2:     lda $d012
        cmp #10
        bne f2
        rts

; ---- variants 1..7: the chain with one element left out
generic:
g_q:    lda #$80
        sta $df0a               ; fixed C64 address
        lda #$aa
        sta $5000
        lda #$b0
        sta $df01               ; stash: 16 KB of $AA
        lda variant
        cmp #6
        beq g_vc
        lda #0
        sta $df0a               ; both addresses incrementing
        lda variant
        cmp #7
        beq g_vr
        cmp #1
        beq g_noswap
        lda #$b2
        sta $df01               ; swap
g_noswap:
        lda #$b0
        sta $df01               ; stash
        lda variant
        cmp #5
        beq g_vr
        lda #$b1
        sta $df01               ; fetch
        lda $5000
        cmp #$aa
        beq g_vr
        inc cpufail
g_vr:   lda #$40
        sta $df0a               ; fixed REU address
        lda #$b3
        sta $df01               ; verify
        lda #$20
        bit $df00
        beq g_vc
        inc faults_r
        lda first
        bne g_vc
        lda quarter
        asl a
        clc
        adc #1
        sta first
g_vc:   lda #$80
        sta $df0a               ; fixed C64 address
        lda #$b3
        sta $df01               ; verify
        lda #$20
        bit $df00
        beq g_next
        inc faults_c
        lda first
        bne g_next
        lda quarter
        asl a
        clc
        adc #2
        sta first
g_next: lda #$40
        clc
        adc $df05
        sta $df05               ; next 16 KB quarter of bank 0
        beq g_done
        inc quarter
        jmp g_q
g_done: rts

; Sprite setup like REUTEST $3072..$30B5: pointers 255 (shape at $3FC0, all
; bits set), Y = $E0, X from the table, colors 0..7, no expansion
sprites_on:
        ldx #$f8
        lda #$ff
s1:     sta $0700,x
        inx
        bne s1
        ldx #$c0
s2:     sta $3f00,x
        inx
        bne s2
        ldx #0
        ldy #0
s3:     txa
        sta $d027,x
        lda #$e0
        sta $d001,y
        lda xtab,x
        sta $d000,y
        iny
        iny
        inx
        cpx #8
        bcc s3
        lda #$c0
        sta $d010
        lda #0
        sta $d017
        sta $d01d
        sta $d01b
        sta $d026
        lda #$ff
        sta $d025
        sta $d015
        rts
xtab:   .byte $26,$4c,$72,$98,$be,$e4,$0a,$30
