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
        lda #<txbuf
        ldx #>txbuf
        sta eth+driver::bufaddr
        stx eth+driver::bufaddr+1
        lda #<txlen
        ldx #>txlen
        jsr eth+driver::send

        ; TBD
:       nop
        jmp :-

        ; Infinite loop signals a success
ok:     jmp ok

.segment "RODATA"
txbuf:  .byte $FF, $FF, $FF, $FF, $FF, $FF ; Destination MAC address
        .byte $11, $22, $33, $44, $55, $66 ; Source MAC address
        .byte $08, $00                     ; Type
        .asciiz "This is a test packet"
txlen = * - txbuf

.segment "VECTORS"

.addr 0
.addr cpu_reset
.byte $32, $43

