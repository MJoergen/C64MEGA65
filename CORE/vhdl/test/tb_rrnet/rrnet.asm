; This is a short assembly program to test the functionality of the
; RR-NET emulation
;
; The test program starts at the label _reset0.

.org $F800

isq      = $DE00
packetpp = $DE02
ppdata   = $DE04
rxtxreg  = $DE08
txcmd    = $DE0C
txlen    = $DE0E

; The initialization routing is copied from https://github.com/cc65/ip65/blob/main/drivers/cs8900a.s
init:
        ; Activate C64 RR clockport in order to operate RR-Net
        ; (RR config register overlays unused CS8900A ISQ register)
        lda isq+1
        ora #$01                ; Set clockport bit
        sta isq+1

        ; Check EISA registration number of Crystal Semiconductor
        ; PACKETPP = $0000, PPDATA == $630E ?
        lda #$00
        tax
        jsr packetpp_ax         ; PP pointer = $0000  (write $DE02/$DE03)
        lda #$63^$0E
        eor ppdata              ; read $DE04 (low  = $0E)
        eor ppdata+1            ; read $DE05 (high = $63)
        beq :+                  ; $630E present -> chip found
        sec                     ; else "no card"
        rts

:       clc
        rts

;---------------------------------------------------------------------

packetpp_a1:
        ldx #$01
packetpp_ax:
        sta packetpp
        stx packetpp+1
        rts

ppdata_ax:
        sta ppdata
        stx ppdata+1
        rts


.segment "VECTORS"

.addr 0
.addr init
.byte $32, $43

