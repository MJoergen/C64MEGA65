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


packetpp        := $DE02
ppdata          := $DE04

err_init:
        ; Invalid instruction signals a failure
        .byte $02

packetpp_a1:
        ldx #$01
        sta packetpp
        stx packetpp+1
        rts

cpu_reset:
        sei
        ldx #$FF
        txs

        ; Check reset values of Control and Configuration Bits
        ; $0100 to $011E
        lda #$00
        jsr packetpp_a1
        lda ppdata
        ldx ppdata+1
        cmp #$01
        bne err_init
        cpx #$00
        bne err_init

        lda #$02
        jsr packetpp_a1
        lda ppdata
        ldx ppdata+1
        cmp #$03
        bne err_init
        cpx #$00
        bne err_init

        lda #$04
        jsr packetpp_a1
        lda ppdata
        ldx ppdata+1
        cmp #$05
        bne err_init
        cpx #$00
        bne err_init

        ; Check reset values of Status and Event Bits
        ; $0120 to $013E
        lda #$20
        jsr packetpp_a1
        lda ppdata
        ldx ppdata+1
        cmp #$00
        bne err_init
        cpx #$00
        bne err_init

        lda #$22
        jsr packetpp_a1
        lda ppdata
        ldx ppdata+1
        cmp #$02
        bne err_init
        cpx #$00
        bne err_init

        lda #$24
        jsr packetpp_a1
        lda ppdata
        ldx ppdata+1
        cmp #$04
        bne err_init
        cpx #$00
        bne err_init

        ; Initialize driver
        jsr eth+driver::init
        bcc :+

        ; Invalid instruction signals a failure
        .byte $02

:
        ; ----------------------------------------------------
        ; TEST 1 : Send one frame, receive one frame, verify
        ; ----------------------------------------------------
        ;
        ; Testbench: Block loopback fifo
        lda #$00
        sta $DF00

        ; Send first packet
        lda #<txbuf1
        ldx #>txbuf1
        sta eth+driver::bufaddr
        stx eth+driver::bufaddr+1
        lda #<txlen1
        ldx #>txlen1
        jsr eth+driver::send

        ; Wait until frame is transmitted
        ldx #$00
:       dex
        bne :-
        ; Testbench: Enable loopback fifo
        lda #$01
        sta $DF00

        lda #<rxbuf
        ldx #>rxbuf
        sta eth+driver::bufaddr
        stx eth+driver::bufaddr+1
        lda #<rxlen
        ldx #>rxlen
        sta eth+driver::bufsize
        stx eth+driver::bufsize+1
:       jsr eth+driver::poll
        bcs :-

        ; Verify packet length
        cmp #<txlen1
        beq :+
        ; Invalid instruction signals a failure
err1:   .byte $02
:       cpx #>txlen1
        bne err1
        ; Verify packet data
        ldy #0
:       lda rxbuf,y
        cmp txbuf1,y
        bne err1
        iny
        cpy #<txlen1
        bne :-


        ; ----------------------------------------------------
        ; TEST 2 : Send two frames, receive only first frame, verify
        ; ----------------------------------------------------
        ;
        ; Testbench: Block loopback fifo
        lda #$00
        sta $DF00

        ; Send first packet
        lda #<txbuf2
        ldx #>txbuf2
        sta eth+driver::bufaddr
        stx eth+driver::bufaddr+1
        lda #<txlen2
        ldx #>txlen2
        jsr eth+driver::send

        ; Wait until frame is transmitted
        ldx #$00
:       dex
        bne :-

        ; Send second packet
        lda #<txbuf3
        ldx #>txbuf3
        sta eth+driver::bufaddr
        stx eth+driver::bufaddr+1
        lda #<txlen3
        ldx #>txlen3
        jsr eth+driver::send

        ; Wait until frame is transmitted
        ldx #$00
:       dex
        bne :-

        ; Testbench: Enable loopback fifo
        lda #$01
        sta $DF00

        ; Wait until frames are received
        ldx #$00
:       dex
        bne :-

        lda #<rxbuf
        ldx #>rxbuf
        sta eth+driver::bufaddr
        stx eth+driver::bufaddr+1
        lda #<rxlen
        ldx #>rxlen
        sta eth+driver::bufsize
        stx eth+driver::bufsize+1
:       jsr eth+driver::poll
        bcs :-

        ; Verify packet length
        cmp #<txlen2
        beq :+
        ; Invalid instruction signals a failure
err2:   .byte $02
:       cpx #>txlen2
        bne err2
        ; Verify packet data
        ldy #0
:       lda rxbuf,y
        cmp txbuf2,y
        bne err2
        iny
        cpy #<txlen2
        bne :-

        ; No more packets
        jsr eth+driver::poll
        bcc err2

        ; Finished
        ; Infinite loop signals a success
ok:     jmp ok


.segment "RODATA"
txbuf1: .byte $FF, $FF, $FF, $FF, $FF, $FF ; Destination MAC address
        .byte $11, $22, $33, $44, $55, $66 ; Source MAC address
        .byte $08, $00                     ; Type
        .repeat 50
          .byte $55, $66, $99, $AA         ; Random packet data
        .endrep
        .byte $11                          ; Specific last byte
txlen1 = * - txbuf1

txbuf2: .byte $FF, $FF, $FF, $FF, $FF, $FF ; Destination MAC address
        .byte $99, $88, $77, $66, $55, $44 ; Source MAC address
        .byte $08, $00                     ; Type
        .repeat 50
          .byte $23, $34, $45, $56         ; Random packet data
        .endrep
        .byte $DD, $EE                     ; Specific last bytes
txlen2 = * - txbuf2

txbuf3: .byte $FF, $FF, $FF, $FF, $FF, $FF ; Destination MAC address
        .byte $91, $82, $73, $64, $55, $46 ; Source MAC address
        .byte $08, $00                     ; Type
        .repeat 50
          .byte $31, $42, $53, $64         ; Random packet data
        .endrep
        .byte $CC                          ; Specific last byte
txlen3 = * - txbuf3


.segment "BSS"
rxlen = 2000
rxbuf: .res rxlen


; CPU initialization vectors - placed at $FFFA
.segment "VECTORS"

.addr 0
.addr cpu_reset
.addr 0

