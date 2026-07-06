; This is a short assembly program to test the functionality of the
; RR-NET emulation
;
; The test program starts at the label cpu_reset

.segment "CODE"

jmp_init=$F80E
jmp_poll=$F811
jmp_send=$F814

cpu_reset:
        sei
        ldx #$FF
        txs
        jsr jmp_init
        bcc ok

        ; Invaild instruction signals a failure
        .byte $02

            ; Infinite loop signals a success
ok:     jmp ok

.segment "VECTORS"

.addr 0
.addr cpu_reset
.byte $32, $43

