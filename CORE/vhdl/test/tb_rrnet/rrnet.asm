; This is a short assembly program to test the functionality of the
; RR-NET emulation
;
; The test program starts at the label cpu_reset

.segment "CODE"

; Driver is placed at a fixed address (see "HEADER" segment in ld.cfg).
eth = $f800

.struct driver
  drvtype .byte 3
  apiver  .byte
  mac     .byte 6
  bufaddr .addr
  bufsize .word
  init    .byte 3
  poll    .byte 3
  send    .byte 3
  exit    .byte 3
.endstruct


cpu_reset:
        sei
        ldx #$FF
        txs
        ; Initialize driver
        jsr eth+driver::init
        bcc :+

        ; Invalid instruction signals a failure
        .byte $02

:
        ; Send a packet
        lda #<txbuf1
        ldx #>txbuf1
        sta eth+driver::bufaddr
        stx eth+driver::bufaddr+1
        lda #<txlen1
        ldx #>txlen1
        jsr eth+driver::send

;        ; Send abother packet
;        lda #<txbuf2
;        ldx #>txbuf2
;        sta eth+driver::bufaddr
;        stx eth+driver::bufaddr+1
;        lda #<txlen2
;        ldx #>txlen2
;        jsr eth+driver::send

        lda #<rxbuf1
        ldx #>rxbuf1
        sta eth+driver::bufaddr
        stx eth+driver::bufaddr+1
        lda #<rxlen1
        ldx #>rxlen1
        sta eth+driver::bufsize
        stx eth+driver::bufsize+1
:       jsr eth+driver::poll
        bcs :-

        ; Finished
:       jmp :-

        ; Infinite loop signals a success
ok:     jmp ok

.segment "RODATA"
txbuf1: .byte $FF, $FF, $FF, $FF, $FF, $FF ; Destination MAC address
        .byte $11, $22, $33, $44, $55, $66 ; Source MAC address
        .byte $08, $00                     ; Type
        .repeat 200
          .byte $55, $AA
        .endrep
        .asciiz "This is a test packet"
txlen1 = * - txbuf1

txbuf2: .byte $FF, $FF, $FF, $FF, $FF, $FF ; Destination MAC address
        .byte $99, $88, $77, $66, $55, $44 ; Source MAC address
        .byte $08, $00                     ; Type
        .repeat 200
          .byte $66, $99
        .endrep
        .asciiz "Here is another packet with an odd length."
txlen2 = * - txbuf2

.segment "BSS"
rxlen1 = 2000
rxbuf1: .res rxlen1

.segment "VECTORS"

.addr 0
.addr cpu_reset
.byte $32, $43

