; This is a short assembly program to test the functionality of the
; Super Snapshot V5 cartridge emulator.
;
; It works by generating a CRT file with the SS5 cartridge ID (20).
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
;
; My interpretation is that the SuperSnapshot cartridge can operate in two different modes:
; * RAM-mode (default) where it uses Ultimax mode (GAME=0, EXROM=1)
; * ROM-mode, where it uses 16k mode (GAME=0, EXROM=0)
; The mode is controlled by bit 1 in $DE00.
;
; In the RAM-mode, the memory map is as follows:
; $8000 - $9FFF : Cartridge RAM (accessed by ROML)
; $A000 - $BFFF : C64 RAM
; $E000 - $FFFF : Cartridge ROM (accessed by ROMH)
;
; In the ROM-mode, the memory map is as follows:
; $8000 - $9FFF : Cartridge ROM (accessed by ROML)
; $A000 - $BFFF : Cartridge ROM (accessed by ROMH)
; $E000 - $FFFF : C64 Kernal ROM
;
; Furthermore, reading from $DE00 mirrors cartridge ROML.

; The test program starts at the label _reset0.

.segment "CRT_HEADER"

; Here is the global cartridge header
; All values are in big-endian.

.byte "C64 CARTRIDGE   "   ; cartridge signature (padded with spaces)
.dbyt $0000, $0040         ; file header length
.byte 1, 0                 ; cartridge version
.dbyt 20                   ; cartridge type (20 = Super Snapshot 5)
.byte 1                    ; EXROM
.byte 0                    ; GAME
.res  6                    ; reserved
.byte "Super Snapshot V5"  ; cartridge name
.res  15                   ; padding

; Here is the first CHIP header (for ROM0)
; All values are in big-endian.

.segment "ROM0_HEADER"

.byte "CHIP"
.dbyt $0000, $4010         ; chip length
.dbyt 0                    ; chip type (0 = ROM)
.dbyt 0                    ; bank number (0)
.dbyt $8000                ; load address
.dbyt $4000                ; rom size

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Here starts the ROM0 data

.segment "ROM0_8000"

; empty for now

.segment "ROM0_9E00"

; specific values to look for
.byte $11, $22
.res  256-4, 10
.byte $DD, $CC

.segment "ROM0_E000"

; This part of the test program is copied to $0400+
_prog_400:
.org $0400

; Disable RAM overlay
  LDA #$02
  STA $DE00
  JSR _test0
  BNE _error

; Set bank 1 (no RAM overlay)
  LDA #$06
  STA $DE00
  JSR _test1
  BNE _error

; Enable RAM overlay (bank 0)
  LDA #$00
  STA $DE00
  JSR _test2
  BNE _error

; Enable RAM overlay (bank 1)
  LDA #$04
  STA $DE00
  JSR _test3
  BNE _error

; We're done!
  LDA #$00
: JMP :-
_error:
  LDA #$FF
: JMP :-



_test0:
; Test 0: (no RAM overlay) test that reading from $9Exx and $DExx and $BFxx from bank 0 gives the correct values
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

  LDA $BFFE
  CMP #$33
  BNE :+

  LDA $BFFF
  CMP #$44
  BNE :+

: RTS

_test1:
; Test 1: (no RAM overlay) test that reading from $9Exx and $DExx and $BFxx from bank 1 gives the correct values
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

  LDA $BFFE
  CMP #$32
  BNE :+

  LDA $BFFF
  CMP #$43
  BNE :+

: RTS

_test2:
; Test 2: test RAM enable (bank 0)
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

_test3:
; Test 3: test RAM enable (bank 1)
  LDA $8000
  CMP #$31
  BEQ :++
  LDA $9E00
  CMP #$42
  BEQ :++
  LDA #$51
  STA $8000
  LDA #$62
  STA $9E00
  LDA $8000
  CMP #$51
  BNE :+
  LDA $9E00
  CMP #$62
  BNE :+

: RTS

: LDA #$01
  RTS

.reloc

prog_400_len = * - _prog_400

_reset0:
  LDX #<prog_400_len
: LDA _prog_400-1+$100, X
  STA $04FF, X
  DEX
  BNE :-
: LDA _prog_400, X
  STA $0400, X
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
.dbyt $0000, $4010         ; chip length
.dbyt 0                    ; chip type (0 = ROM)
.dbyt 1                    ; bank number (1)
.dbyt $8000                ; load address
.dbyt $4000                ; rom size

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Here starts the ROM1 data

.segment "ROM1_8000"

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
  LDA #$EE
: JMP :-

.segment "ROM1_VECTORS"

.addr 0
.addr _reset1
.byte $32, $43

