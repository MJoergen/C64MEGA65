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

.segment "CODE0_LO"

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

.byte "CHIP"
.byte $00, $00, $40, $10   ; chip length
.byte $00, $00             ; chip type (0 = ROM)
.byte $00, $00             ; bank number
.byte $80, $00             ; load address
.byte $40, $00             ; rom size

; Here starts the ROM0 data

.org $8000

.addr _start0
.addr _start0
.byte $c3, $c2, $cd, "80"

_prog_400:
  LDA $DE00
  CMP #$11
  BNE _error0

  LDA $DE01
  CMP #$22
  BNE _error0

  LDA $DE02
  CMP #$33
  BNE _error0

  LDA $DE03
  CMP #$44
  BNE _error0

  LDA $DEFC
  CMP #$FF
  BNE _error0

  LDA $DEFD
  CMP #$EE
  BNE _error0

  LDA $DEFE
  CMP #$DD
  BNE _error0

  LDA $DEFF
  CMP #$CC
  BNE _error0

_success0:
  JMP _success0

_error0:
  jmp _error0
  BRK

prog_400_len = * - _prog_400

.org $9E00
.byte $11, $22, $33, $44

.org $9EFC
.byte $FF, $EE, $DD, $CC

.segment "CODE0_HI"

.org $E000

_start0:

_reset0:
  LDX #prog_400_len
: LDA _prog_400-1, X
  STA $03FF, X
  DEX
  BNE :-
  jmp $0400

.segment "VECTORS0"

.addr 0
.addr _reset0
.addr 0


.segment "CODE1_LO"

; All values are in big-endian.

.byte "CHIP"
.byte $00, $00, $40, $10   ; chip length
.byte $00, $00             ; chip type (0 = ROM)
.byte $00, $01             ; bank number
.byte $80, $00             ; load address
.byte $40, $00             ; rom size

; Here starts the ROM1 data

.org $8000

.addr _start1
.addr _start1
.byte $c3, $c2, $cd, "80"

.segment "CODE1_HI"

.org $E000

_start1:

_reset1:
  jmp _reset1

.segment "VECTORS1"

.addr 0
.addr _reset1
.addr 0

