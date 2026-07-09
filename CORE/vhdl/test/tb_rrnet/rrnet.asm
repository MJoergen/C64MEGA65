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
        jsr eth+driver::init
        bcc :+

        ; Invaild instruction signals a failure
        .byte $02

:
        ; Infinite loop signals a success
ok:     jmp ok

.segment "VECTORS"

.addr 0
.addr cpu_reset
.byte $32, $43

