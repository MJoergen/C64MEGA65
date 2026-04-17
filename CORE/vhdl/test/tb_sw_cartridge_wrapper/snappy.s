; This is a short assembly program to test the functionality of the
; Super Snapshot V5 cartridge
;
; It works by generating a CRT file with the SS5 cartridge ID.
;
;          -- Following comment copied from VICE:
;          -- - 64K ROM,8*8K Banks (4*16k)
;          -- - 32K RAM,4*8K Banks (8k stock, 32k optional)
;          --
;          -- note: apparently the hardware supports 128k ROMs too, but no such dump exists.
;          --
;          -- io1: (read)
;          --     cart ROM mirror from current 9e00-9eff page. RAM can NOT be mirrored here!
;          --
;          -- io1 (write)
;          --
;          -- there is one register mirrored from de00-deff (the software uses de00/de01)
;          --
;          -- bit 6-7  not connected
;          -- bit 5    rom/ram bank bit2 (address line 16) (unused, for 128k ROM)
;          -- bit 4    rom/ram bank bit1 (address line 15)
;          -- bit 3    !rom enable (0: enabled, 1: disabled)
;          --          note: disabling ROM also disables this register
;          -- bit 2    rom/ram bank bit0 (address line 14)
;          -- bit 1    !ram enable (0: enabled, 1: disabled), !EXROM (0: high, 1: low)
;          -- bit 0    GAME (0: low, 1: high)

.segment "CRT_HEADER"

; Here is the global cartridge header
; All values are in big-endian.

.byte "C64 CARTRIDGE   "   ; cartridge signature
.byte $00, $00, $00, $40   ; file header length
.byte $01, $00             ; cartridge version
.byte 0, 20                ; cartridge type (20 = Super Snapshot 5)
.byte $01                  ; EXROM
.byte $00                  ; GAME
.byte 0,0,0,0,0,0          ; reserved
.byte "Super Snapshot V5"  ; cartridge name
.byte 0,0,0,0,0,0,0        ; padding
.byte 0,0,0,0,0,0,0,0      ; padding

; Here is the first CHIP header (for ROM0)
; All values are in big-endian.

.segment "ROM0_HEADER"

.byte "CHIP"
.byte $00, $00, $40, $10   ; chip length
.byte $00, $00             ; chip type (0 = ROM)
.byte $00, $00             ; bank number (0)
.byte $80, $00             ; load address
.byte $40, $00             ; rom size

; Here starts the ROM0 data

.segment "ROM0_8000"

.segment "ROM0_9E00"

.byte $11, $22
.res  256-4, 10

.byte $DD, $CC

.segment "ROM0_E000"

; The main part of the test program is copied to $0400+
_prog_400:
.org $0400

; Disable RAM overlay
  LDA #$02
  STA $DE00
  JSR _test0
  BNE _error

; Set bank 1
  LDA #$06
  STA $DE00
  JSR _test1
  BNE _error

; Enable RAM overlay
  LDA #$00
  STA $DE00
  JSR _test2
  BNE _error

; We're done!
  LDA #$00
: JMP :-
_error:
  LDA #$FF
: JMP :-



_test0:
; Test 0: test that reading from $9Exx and $DExx and $FFxx from bank 0 gives the correct values
  LDA $9E00
  CMP #$11
  BNE :+

  LDA $9E01
  CMP #$22
  BNE :+

  LDA $9EFE
  CMP #$DD
  BNE :+

  LDA $9EFF
  CMP #$CC
  BNE :+

  LDA $DE00
  CMP #$11
  BNE :+

  LDA $DE01
  CMP #$22
  BNE :+

  LDA $DEFE
  CMP #$DD
  BNE :+

  LDA $DEFF
  CMP #$CC
  BNE :+

;  LDA $FFFE
;  CMP #$33
;  BNE :+

;  LDA $FFFF
;  CMP #$44
;  BNE :+

: RTS

_test1:
; Test 1: test that reading from $9Exx and $DExx from bank 1 gives the correct values
  LDA $9E00
  CMP #$12
  BNE :+

  LDA $9E01
  CMP #$23
  BNE :+

  LDA $9EFE
  CMP #$DC
  BNE :+

  LDA $9EFF
  CMP #$CB
  BNE :+

  LDA $DE00
  CMP #$12
  BNE :+

  LDA $DE01
  CMP #$23
  BNE :+

  LDA $DEFE
  CMP #$DC
  BNE :+

  LDA $DEFF
  CMP #$CB
  BNE :+

;  LDA $FFFE
;  CMP #$32
;  BNE :+

;  LDA $FFFF
;  CMP #$43
;  BNE :+

: RTS

_test2:
; Test 2: test RAM enable
  LDA #$31
  STA $8000
  LDA #$42
  STA $9E00
  LDA $8000
  CMP #$31
  BNE :+
  LDA $9E00
  CMP #$42
  BNE :+

  LDA $DE00
  CMP #$11
  BNE :+

  LDA $DE01
  CMP #$22
  BNE :+

  LDA $DEFE
  CMP #$DD
  BNE :+

  LDA $DEFF
  CMP #$CC
  BNE :+

  LDA $FFFE
  CMP #$33
  BNE :+

  LDA $FFFF
  CMP #$44
  BNE :+

: RTS

.reloc

prog_400_len = * - _prog_400

_reset0:
  LDX #prog_400_len
: LDA _prog_400-1, X
  STA $03FF, X
  DEX
  BNE :-
  jmp $0400

.segment "ROM0_VECTORS"

.addr 0
.addr _reset0
.byte $33, $44


.segment "ROM1_HEADER"

; All values are in big-endian.

.byte "CHIP"
.byte $00, $00, $40, $10   ; chip length
.byte $00, $00             ; chip type (0 = ROM)
.byte $00, $01             ; bank number(1)
.byte $80, $00             ; load address
.byte $40, $00             ; rom size

.segment "ROM1_8000"

; Here starts the ROM1 data

.addr _start1
.addr _start1
.byte $c3, $c2, $cd, "80"

.segment "ROM1_9E00"

.byte $12, $23
.res  256-4, 10

.byte $DC, $CB

.segment "ROM1_E000"

_start1:

_reset1:
  jmp _reset1

.segment "ROM1_VECTORS"

.addr 0
.addr _reset1
.byte $32, $43

