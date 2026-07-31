; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Dependent menu entries ("smart dependencies") for the Options Menu
;
; A menu line can be tagged in config.vhd with OPTM_DEP(mother, item) or
; OPTM_DEP2(mother, item_a, item_b) so that it is only visible while one of
; the items in a 4-bit item MASK of a specific "mother" group is selected
; (dependency format 2, config.vhd magic 0x2DEF). This is a pure visibility
; layer: dependent lines keep their own osm_control bit, their saved
; config-file byte and their default state; the VHDL side multiplexes the
; active variant explicitly. See doc/path-to-OSM-dependencies.md for the
; complete design.
;
; This file is part of the self-contained menu component (menu.asm,
; menu_vars.asm, menu_struct.asm, optm_deps.asm) and is included at the end of
; menu.asm. The routines that operate on plain arrays (OPTM_DEPS_RESOLVE,
; OPTM_DEPS_VAL) are pure and directly testable in the QNICE emulator, see
; optm_deps_test.asm. OPTM_DEP_OK and OPTM_DEPS_AFFECTS additionally read the
; menu initialization record via OPTM_DATA (the single source of truth for the
; resolved dependency array and the live selected-state array).
;
; The raw per-line dependency word as served by SEL_OPTM_DEPS (config.vhd):
;   bit 12    : OPTM_G_DEPENDENT flag (1 = this line is dependent)
;   bits 11-8 : mother item mask (bit k = visible while member k is selected;
;               for a single-select mother: bit 0 = visible while it is off,
;               bit 1 = visible while it is on)
;   bits  7-0 : mother group id (1..254)
; The resolved per-line dependency word (produced by OPTM_DEPS_RESOLVE):
;   bit 15    : valid (1 = this line is dependent)
;   bits 11-8 : mother item mask (copied through from the raw word)
;   bits  7-0 : flat index of the FIRST member of the mother group
;
; done by sy2002 in 2026 and licensed under GPL v3
; ****************************************************************************

; ----------------------------------------------------------------------------
; OPTM_DEP_OK: Runtime visibility predicate for one menu line
;
; Reads the resolved dependency array, the (masked) groups array and the live
; selected-state array from the menu initialization record (OPTM_DATA). When
; the dependency feature is off (no record, or OPTM_IR_DEPS is 0) or the line
; carries no dependency, the line is always visible. Otherwise: for a
; single-select mother the line is visible iff mask bit <state of the mother
; line> is set; for a radio mother the members of the mother group are scanned
; from its first member on, the ordinal k of the currently selected member is
; determined, and the line is visible iff mask bit k is set (no selected
; member, or a selected member beyond bit 3: hidden).
;
; Input:
;   R8: flat index of the menu line to test
;
; Output:
;   C=1: the line is visible (dependency satisfied or no dependency)
;   C=0: the line is hidden by an unsatisfied dependency
;
;   All registers (including R8) are preserved.
; ----------------------------------------------------------------------------

OPTM_DEP_OK     INCRB

                MOVE    OPTM_DATA, R0
                MOVE    @R0, R0                 ; R0: init record (0 = none)
                RBRA    _ODO_VIS, Z             ; no record: always visible
                MOVE    R0, R1
                ADD     OPTM_IR_DEPS, R1
                MOVE    @R1, R1                 ; R1: resolved DEPS array base
                RBRA    _ODO_VIS, Z             ; feature off: always visible
                ADD     R8, R1                  ; R1: &DEPS[R8]
                MOVE    @R1, R1                 ; R1: resolved dependency word
                MOVE    R1, R2
                AND     0x8000, R2              ; is this line dependent?
                RBRA    _ODO_VIS, Z             ; no: always visible

                MOVE    R0, R3                  ; R3: live selected-state array
                ADD     OPTM_IR_STDSEL, R3
                MOVE    @R3, R3
                MOVE    R0, R4                  ; R4: (masked) groups array
                ADD     OPTM_IR_GROUPS, R4
                MOVE    @R4, R4
                MOVE    R0, R5                  ; R5: amount of menu items (N)
                ADD     OPTM_IR_SIZE, R5
                MOVE    @R5, R5

                MOVE    R1, R6                  ; R6: first member of the mother
                AND     0x00FF, R6
                MOVE    R1, R7                  ; R7: item mask (bits 3..0)
                SHR     8, R7
                AND     0x000F, R7

                MOVE    R4, R2                  ; R2: GROUPS[first member]
                ADD     R6, R2
                MOVE    @R2, R2
                MOVE    R2, R0                  ; single-select mother?
                AND     0x8000, R0
                RBRA    _ODO_RADIO, Z           ; no: radio mother

                MOVE    R3, R0                  ; single-select: k = state (0/1)
                ADD     R6, R0
                MOVE    @R0, R0                 ; R0: state of the mother line
                RBRA    _ODO_TSTB0, Z           ; state 0: test mask bit 0
                SHR     1, R7                   ; state 1: test mask bit 1
_ODO_TSTB0      AND     1, R7
                RBRA    _ODO_HID, Z
                RBRA    _ODO_VIS, 1

_ODO_RADIO      AND     0x00FF, R2              ; R2: mother group id
                XOR     R1, R1                  ; R1: member ordinal k
_ODO_RSCAN      CMP     R5, R6                  ; end of the menu reached?
                RBRA    _ODO_HID, Z             ; no selected member: hidden
                MOVE    R4, R0                  ; GROUPS[j] group id
                ADD     R6, R0
                MOVE    @R0, R0
                AND     0x00FF, R0
                CMP     R2, R0                  ; member of the mother group?
                RBRA    _ODO_RNEXT, !Z          ; no
                MOVE    R3, R0                  ; member selected?
                ADD     R6, R0
                MOVE    @R0, R0
                CMP     0, R0
                RBRA    _ODO_RSEL, !Z           ; yes: k is its ordinal
                ADD     1, R1                   ; no: next ordinal
                CMP     4, R1                   ; ordinal beyond the 4-bit mask
                RBRA    _ODO_HID, Z             ; window can never match: hidden
_ODO_RNEXT      ADD     1, R6
                RBRA    _ODO_RSCAN, 1

_ODO_RSEL       CMP     0, R1                   ; visible iff mask bit k is set
                RBRA    _ODO_RTST, Z
_ODO_RSH        SHR     1, R7
                SUB     1, R1
                RBRA    _ODO_RSH, !Z
_ODO_RTST       AND     1, R7
                RBRA    _ODO_HID, Z

_ODO_VIS        OR      0x0004, SR              ; set Carry: visible
                DECRB
                RET
_ODO_HID        AND     0xFFFB, SR              ; clear Carry: hidden
                DECRB
                RET

; ----------------------------------------------------------------------------
; OPTM_DEPS_AFFECTS: Does a selectable group control any dependent line?
;
; Called after a selection change (a radio flip or a single-select toggle) to
; decide whether the visible menu structure may have changed and therefore
; needs a real-time redraw. Returns true if the group whose state just changed
; is the "mother" of at least one dependent line. Identifying the group by its
; (masked) group word is sufficient: members of one group share the same word,
; and group words are unique per group id.
;
; Input:
;   R8: the masked group word of the line whose state just changed
;
; Output:
;   C=1: the group controls at least one dependent line (redraw needed)
;   C=0: the group controls nothing (no dependents, or feature off)
;
;   All registers (including R8) are preserved.
; ----------------------------------------------------------------------------

OPTM_DEPS_AFFECTS INCRB

                MOVE    OPTM_DATA, R0
                MOVE    @R0, R0                 ; R0: init record (0 = none)
                RBRA    _ODA_NO, Z
                MOVE    R0, R1
                ADD     OPTM_IR_DEPS, R1
                MOVE    @R1, R1                 ; R1: resolved DEPS array base
                RBRA    _ODA_NO, Z              ; feature off
                MOVE    R0, R2
                ADD     OPTM_IR_GROUPS, R2
                MOVE    @R2, R2                 ; R2: groups array base
                MOVE    R0, R3
                ADD     OPTM_IR_SIZE, R3
                MOVE    @R3, R3                 ; R3: amount of menu items (N)
                XOR     R4, R4                  ; R4: loop index

_ODA_LOOP       CMP     R3, R4                  ; all lines scanned?
                RBRA    _ODA_NO, Z
                MOVE    R1, R5                  ; R5: resolved DEPS[R4]
                ADD     R4, R5
                MOVE    @R5, R5
                MOVE    R5, R6
                AND     0x8000, R6              ; is line R4 dependent?
                RBRA    _ODA_NEXT, Z            ; no
                AND     0x00FF, R5              ; R5: its controlling line index
                MOVE    R2, R6                  ; R6: GROUPS[controlling line]
                ADD     R5, R6
                CMP     @R6, R8                 ; same group as the change?
                RBRA    _ODA_YES, Z             ; yes: this group is a mother
_ODA_NEXT       ADD     1, R4
                RBRA    _ODA_LOOP, 1

_ODA_YES        OR      0x0004, SR              ; set Carry: affects structure
                DECRB
                RET
_ODA_NO         AND     0xFFFB, SR              ; clear Carry: no effect
                DECRB
                RET

; ----------------------------------------------------------------------------
; OPTM_DEPS_RESOLVE: Resolve the raw dependency array in place
;
; Run once per menu open (see HELP_MENU). Rewrites every raw dependency word
; into the resolved form expected by OPTM_DEP_OK: the item mask is copied
; through (bits 11-8) and the controlling-line field (bits 7-0) receives the
; flat index of the FIRST member of the mother group -- for both mother types;
; OPTM_DEP_OK branches on the single-select flag of that line at runtime.
; Lines that carry no dependency become 0. Assumes the structure was validated
; at boot by OPTM_DEPS_VAL; a mother with no members is defensively treated as
; not dependent.
;
; Input:
;   R8: pointer to the raw dependency array (N words, rewritten in place)
;   R9: pointer to the (masked) groups array (N words)
;  R10: amount of menu items (N)
;
; Output:
;   R8 is unchanged; the dependency array now holds resolved words.
;   All other registers are preserved.
; ----------------------------------------------------------------------------

OPTM_DEPS_RESOLVE INCRB

                MOVE    R9, @--SP               ; preserve the caller globals
                MOVE    R10, @--SP              ; that this routine reuses
                MOVE    R11, @--SP
                MOVE    R12, @--SP
                MOVE    R8, R0                  ; R0: dependency array base
                MOVE    R9, R1                  ; R1: groups array base
                MOVE    R10, R2                 ; R2: amount of menu items (N)
                XOR     R3, R3                  ; R3: outer line index i

_RES_LOOP       CMP     R2, R3                  ; all lines done?
                RBRA    _RES_DONE, Z
                MOVE    R0, R10                 ; R10: &DEPS[i]
                ADD     R3, R10
                MOVE    @R10, R8                ; R8: raw dependency word
                MOVE    R8, R9
                AND     0x1000, R9              ; OPTM_G_DEPENDENT flag set?
                RBRA    _RES_DEP, !Z            ; yes: resolve
                MOVE    0, @R10                 ; no: clear to 0
                RBRA    _RES_NEXT, 1

_RES_DEP        MOVE    R8, R4                  ; R4: mother group id
                AND     0x00FF, R4
                MOVE    R8, R5                  ; R5: item mask, kept in place
                AND     0x0F00, R5              ; (bits 11-8, as in the raw word)

                XOR     R6, R6                  ; R6: inner index j
                XOR     R7, R7                  ; R7: member count
                XOR     R11, R11                ; R11: first member index

_RES_SCAN       CMP     R2, R6                  ; inner scan over all groups
                RBRA    _RES_SCANE, Z
                MOVE    R1, R8                  ; R8: GROUPS[j] group id
                ADD     R6, R8
                MOVE    @R8, R8
                AND     0x00FF, R8
                CMP     R4, R8                  ; member of the mother group?
                RBRA    _RES_SCANN, !Z          ; no
                CMP     0, R7                   ; first member?
                RBRA    _RES_NF, !Z
                MOVE    R6, R11                 ; remember first member
_RES_NF         ADD     1, R7                   ; one more member
_RES_SCANN      ADD     1, R6
                RBRA    _RES_SCAN, 1

_RES_SCANE      CMP     0, R7                   ; mother has no members?
                RBRA    _RES_ZERO, Z            ; defensively: not dependent
                MOVE    R5, R8                  ; resolved word: item mask ...
                OR      0x8000, R8              ; ... valid bit ...
                OR      R11, R8                 ; ... first-member flat index
                MOVE    R0, R10                 ; write resolved word back
                ADD     R3, R10
                MOVE    R8, @R10
                RBRA    _RES_NEXT, 1

_RES_ZERO       MOVE    R0, R10
                ADD     R3, R10
                MOVE    0, @R10

_RES_NEXT       ADD     1, R3
                RBRA    _RES_LOOP, 1

_RES_DONE       MOVE    R0, R8                  ; restore R8 (array base)
                MOVE    @SP++, R12              ; restore the caller globals
                MOVE    @SP++, R11
                MOVE    @SP++, R10
                MOVE    @SP++, R9
                DECRB
                RET

; ----------------------------------------------------------------------------
; OPTM_DEPS_VAL: Validate the dependency declarations at boot time
;
; Run once at boot (see HELP_MENU_INIT). All failures are authoring errors in
; config.vhd, hence fatals. The step-1 restrictions checked here are:
;
;   class 0  ERR_F_DEPMOTHER  : mother group id is 0 or 255, or has no members
;   class 1  ERR_F_DEPIDX     : item mask is empty, or contains a bit at or
;                               beyond the member count (radio mother) / beyond
;                               bit 1 (single-select mother)
;   class 2  ERR_F_DEPMIX     : members of one group carry differing
;                               dependency words (incl. some-tagged/some-not)
;   class 3  ERR_F_DEPCHAIN   : a line of a mother group is itself dependent
;   class 4  ERR_F_DEPSPECIAL : a dependent line is a submenu opener/closer or
;                               is flagged LOAD_ROM / HELP (since dependency
;                               format 2, MOUNT_DRV and START lines MAY be
;                               dependent: the mount lines of C64MEGA65 issue
;                               #93 rely on it)
;
; SUBMENU and CLOSE lines are recognized from the groups array (bit 14); the
; remaining special flags (LOAD_ROM, HELP) are stripped from the masked groups
; window and are therefore supplied by the caller in a separate
; one-word-per-line array (nonzero = special line).
;
; Input:
;   R8: pointer to the (masked) groups array (N words)
;   R9: amount of menu items (N)
;  R10: pointer to the raw dependency array (N words)
;  R11: pointer to the special-line array (N words; nonzero = special)
;
; Output:
;   C=0: success, all registers preserved
;   C=1: error
;        R9:  error class (0..4, see above)
;        R10: flat index of the offending line
;
;   R8 is unchanged; on the success path all registers are preserved.
; ----------------------------------------------------------------------------

OPTM_DEPS_VAL   INCRB

                MOVE    R8, @--SP               ; preserve the caller globals so
                MOVE    R9, @--SP               ; the contract holds: R8 unchanged,
                MOVE    R10, @--SP              ; R9/R10 carry outputs only on the
                MOVE    R11, @--SP              ; error path
                MOVE    R12, @--SP
                MOVE    R8, R0                  ; R0: groups array base
                MOVE    R9, R1                  ; R1: amount of menu items (N)
                MOVE    R10, R2                 ; R2: dependency array base
                MOVE    R11, R3                 ; R3: special-line array base
                XOR     R4, R4                  ; R4: line index i

                ; --------------------------------------------------------
                ; pass A: per-dependent-line checks (special, mother,
                ; index, chain) in flat order
                ; --------------------------------------------------------
_VAL_A          CMP     R1, R4                  ; all lines checked?
                RBRA    _VAL_B_INIT, Z
                MOVE    R2, R5                  ; R5: raw DEPS[i]
                ADD     R4, R5
                MOVE    @R5, R5
                MOVE    R5, R6
                AND     0x1000, R6              ; is line i dependent?
                RBRA    _VAL_A_NEXT, Z          ; no: skip

                ; class 4: dependent special line (submenu opener/closer,
                ; bare close, load_rom or help; mount-drive and cursor-start
                ; lines MAY be dependent since dependency format 2)
                MOVE    R0, R6                  ; GROUPS[i]
                ADD     R4, R6
                MOVE    @R6, R6
                MOVE    R6, R7                  ; submenu opener or closer?
                AND     0x4000, R7
                RBRA    _VAL_E_SPEC, !Z
                AND     0x00FF, R6              ; a bare OPTM_G_CLOSE line (group
                CMP     R6, 255                 ; id 255) is special too, even
                RBRA    _VAL_E_SPEC, Z          ; without the submenu marker bit
                MOVE    R3, R6                  ; special-line flag set?
                ADD     R4, R6
                MOVE    @R6, R6
                RBRA    _VAL_E_SPEC, !Z

                MOVE    R5, R7                  ; R7: mother group id
                AND     0x00FF, R7
                MOVE    R5, R8                  ; R8: mother item index
                SHR     8, R8
                AND     0x000F, R8

                ; class 0: mother id 0 or 255
                CMP     0, R7
                RBRA    _VAL_E_MOTH, Z
                CMP     255, R7
                RBRA    _VAL_E_MOTH, Z

                ; scan the mother group: count members, single-select flag,
                ; and whether any member is itself dependent (chain)
                XOR     R9, R9                  ; R9: member count
                XOR     R10, R10                ; R10: single-select flag
                XOR     R11, R11                ; R11: chain flag
                XOR     R12, R12                ; R12: inner index j
_VAL_MSCAN      CMP     R1, R12
                RBRA    _VAL_MSCANE, Z
                MOVE    R0, R6                  ; GROUPS[j] group id
                ADD     R12, R6
                MOVE    @R6, R6
                MOVE    R6, R8                  ; (keep masked word in R6)
                AND     0x00FF, R8
                CMP     R7, R8                  ; member of the mother group?
                RBRA    _VAL_MSCANN, !Z
                MOVE    R6, R8                  ; member single-select?
                AND     0x8000, R8
                RBRA    _VAL_MNS, Z
                MOVE    1, R10                  ; remember single-select mother
_VAL_MNS        MOVE    R2, R8                  ; is this member dependent?
                ADD     R12, R8
                MOVE    @R8, R8
                AND     0x1000, R8
                RBRA    _VAL_MNC, Z
                MOVE    1, R11                  ; remember chain
_VAL_MNC        ADD     1, R9                   ; one more member
_VAL_MSCANN     ADD     1, R12
                RBRA    _VAL_MSCAN, 1

_VAL_MSCANE     CMP     0, R9                   ; class 0: mother has no members
                RBRA    _VAL_E_MOTH, Z
                CMP     0, R11                  ; class 3: dependency chain
                RBRA    _VAL_E_CHAIN, !Z

                ; class 1: item mask empty or out of range
                MOVE    R5, R8                  ; recompute item mask
                SHR     8, R8
                AND     0x000F, R8
                CMP     0, R8                   ; empty mask: error
                RBRA    _VAL_E_IDX, Z
                CMP     0, R10                  ; single-select mother?
                RBRA    _VAL_IDX_R, Z           ; no: radio mother
                MOVE    R8, R12                 ; single: only bits 0/1 allowed
                AND     0x000C, R12
                RBRA    _VAL_E_IDX, !Z
                RBRA    _VAL_A_NEXT, 1
_VAL_IDX_R      MOVE    R9, R12                 ; radio: a mask bit at or beyond
                CMP     4, R12                  ; the member count is an error;
                RBRA    _VAL_A_NEXT, !N         ; >= 4 members: nothing to check
_VAL_IDX_SH     SHR     1, R8                   ; drop the in-range positions
                SUB     1, R12
                RBRA    _VAL_IDX_SH, !Z
                CMP     0, R8                   ; anything left is out of range
                RBRA    _VAL_E_IDX, !Z

_VAL_A_NEXT     ADD     1, R4
                RBRA    _VAL_A, 1

                ; --------------------------------------------------------
                ; pass B: uniformity of dependency words within each group
                ; (each member must match the first member of its group)
                ; --------------------------------------------------------
_VAL_B_INIT     XOR     R4, R4
_VAL_B          CMP     R1, R4
                RBRA    _VAL_OK, Z
                MOVE    R0, R5                  ; R5: GROUPS[i] group id
                ADD     R4, R5
                MOVE    @R5, R5
                AND     0x00FF, R5
                CMP     0, R5                   ; group 0 (text/line/etc.)?
                RBRA    _VAL_B_NEXT, Z          ; not a selectable group: skip
                CMP     255, R5                 ; close line?
                RBRA    _VAL_B_NEXT, Z
                MOVE    R0, R6                  ; submenu opener/closer?
                ADD     R4, R6
                MOVE    @R6, R6
                AND     0x4000, R6
                RBRA    _VAL_B_NEXT, !Z         ; skip submenu lines

                ; find first member of this group (lowest index)
                XOR     R6, R6                  ; R6: inner index j
_VAL_BF         MOVE    R0, R7                  ; GROUPS[j] group id
                ADD     R6, R7
                MOVE    @R7, R7
                AND     0x00FF, R7
                CMP     R5, R7                  ; first member of group R5?
                RBRA    _VAL_BF_OK, Z
                ADD     1, R6
                RBRA    _VAL_BF, 1
_VAL_BF_OK      CMP     R6, R4                  ; is i itself the first member?
                RBRA    _VAL_B_NEXT, Z          ; yes: nothing to compare
                MOVE    R2, R7                  ; DEPS[first member]
                ADD     R6, R7
                MOVE    @R7, R7
                MOVE    R2, R8                  ; DEPS[i]
                ADD     R4, R8
                MOVE    @R8, R8
                CMP     R7, R8                  ; identical dependency words?
                RBRA    _VAL_E_MIX, !Z          ; no: mixed group
_VAL_B_NEXT     ADD     1, R4
                RBRA    _VAL_B, 1

_VAL_OK         MOVE    @SP++, R12              ; restore the caller globals
                MOVE    @SP++, R11
                MOVE    @SP++, R10
                MOVE    @SP++, R9
                MOVE    @SP++, R8
                AND     0xFFFB, SR              ; clear Carry: success
                DECRB
                RET

                ; error classes are stashed in the banked R5/R6 so they
                ; survive restoring the caller globals R9..R12 below
_VAL_E_MOTH     XOR     R5, R5                  ; class 0
                RBRA    _VAL_ERR, 1
_VAL_E_IDX      MOVE    1, R5                   ; class 1
                RBRA    _VAL_ERR, 1
_VAL_E_MIX      MOVE    2, R5                   ; class 2
                RBRA    _VAL_ERR, 1
_VAL_E_CHAIN    MOVE    3, R5                   ; class 3
                RBRA    _VAL_ERR, 1
_VAL_E_SPEC     MOVE    4, R5                   ; class 4
_VAL_ERR        MOVE    R4, R6                  ; R6: offending line index
                MOVE    @SP++, R12              ; restore the caller globals
                MOVE    @SP++, R11
                MOVE    @SP++, R10
                MOVE    @SP++, R9
                MOVE    @SP++, R8
                MOVE    R5, R9                  ; R9: error class
                MOVE    R6, R10                 ; R10: offending line index
                OR      0x0004, SR              ; set Carry: error
                DECRB
                RET

; ----------------------------------------------------------------------------
; OPTM_DEPS_MINHID: Guaranteed-hidden line count for the height check
;
; Since dependency format 2, dependent lines can be mutually exclusive (e.g.
; the per-drive mount/status twins of C64MEGA65 issue #93: per drive, at most
; one of the two is ever visible). The structural menu height therefore
; over-counts the height a view can actually reach. This routine computes,
; summed over all mother groups that control at least one dependent line, the
; MINIMUM number of dependent lines of that mother that are hidden in ANY
; selectable state of the mother (radio: item 0..count-1, capped at the 4-bit
; mask width; single-select: off/on). Subtracting the sum from the structural
; height yields a dependency-aware height bound. The sum is global over all
; views, so the bound is a safe under-approximation when one mother controls
; lines in several views; the exact per-view maximum is enforced at authoring
; time by menu_test.py verify.
;
; Input:
;   R8: pointer to the (masked) groups array (N words)
;   R9: pointer to the raw dependency array (N words)
;  R10: amount of menu items (N)
;
; Output:
;   R8: sum of the per-mother minima (0 when there are no dependent lines)
;   All other registers are preserved.
; ----------------------------------------------------------------------------

OPTM_DEPS_MINHID INCRB

                MOVE    R9, @--SP               ; preserve the caller globals
                MOVE    R10, @--SP
                MOVE    R11, @--SP
                MOVE    R12, @--SP
                MOVE    R8, R0                  ; R0: groups array base
                MOVE    R9, R1                  ; R1: dependency array base
                MOVE    R10, R2                 ; R2: amount of menu items (N)
                XOR     R3, R3                  ; R3: outer line index i
                XOR     R4, R4                  ; R4: sum of the minima

_DMH_OUTER      CMP     R2, R3                  ; all lines done?
                RBRA    _DMH_DONE, Z
                MOVE    R1, R5                  ; R5: raw DEPS[i]
                ADD     R3, R5
                MOVE    @R5, R5
                MOVE    R5, R6
                AND     0x1000, R6              ; is line i dependent?
                RBRA    _DMH_NEXT, Z            ; no: skip
                AND     0x00FF, R5              ; R5: mother group id

                ; only handle the FIRST dependent line of each mother
                XOR     R6, R6                  ; R6: scan index j
_DMH_SEEN       CMP     R3, R6                  ; reached i?
                RBRA    _DMH_FIRST, Z           ; yes: first occurrence
                MOVE    R1, R7                  ; DEPS[j]
                ADD     R6, R7
                MOVE    @R7, R7
                MOVE    R7, R8
                AND     0x1000, R8              ; dependent?
                RBRA    _DMH_SEENN, Z
                AND     0x00FF, R7
                CMP     R5, R7                  ; same mother?
                RBRA    _DMH_NEXT, Z            ; yes: already counted
_DMH_SEENN      ADD     1, R6
                RBRA    _DMH_SEEN, 1

                ; count the members of the mother group, note single-select
_DMH_FIRST      XOR     R6, R6                  ; R6: scan index j
                XOR     R7, R7                  ; R7: member count
                XOR     R11, R11                ; R11: single-select flag
_DMH_MSCAN      CMP     R2, R6
                RBRA    _DMH_MSCANE, Z
                MOVE    R0, R8                  ; GROUPS[j]
                ADD     R6, R8
                MOVE    @R8, R8
                MOVE    R8, R9
                AND     0x00FF, R9
                CMP     R5, R9                  ; member of the mother group?
                RBRA    _DMH_MSCANN, !Z
                ADD     1, R7                   ; one more member
                AND     0x8000, R8              ; single-select?
                RBRA    _DMH_MSCANN, Z
                MOVE    1, R11
_DMH_MSCANN     ADD     1, R6
                RBRA    _DMH_MSCAN, 1

                ; states to test: single-select: 2; radio: min(count, 4),
                ; because states beyond the 4-bit mask width hide MORE lines
                ; than any state within it and can never lower the minimum
_DMH_MSCANE     CMP     0, R7                   ; no members: defensively skip
                RBRA    _DMH_NEXT, Z            ; (boot-validated: cannot happen)
                CMP     0, R11
                RBRA    _DMH_RADIO, Z
                MOVE    2, R7                   ; single-select: states 0 and 1
                RBRA    _DMH_STATES, 1
_DMH_RADIO      CMP     4, R7                   ; radio: cap at 4
                RBRA    _DMH_STATES, N
                MOVE    4, R7
_DMH_STATES     XOR     R6, R6                  ; R6: state s
                MOVE    0x7FFF, R12             ; R12: minimum hidden so far

_DMH_SLOOP      CMP     R7, R6                  ; all states tested?
                RBRA    _DMH_SDONE, Z
                XOR     R9, R9                  ; R9: scan index j
                XOR     R10, R10                ; R10: hidden count in state s
_DMH_HSCAN      CMP     R2, R9
                RBRA    _DMH_HSCANE, Z
                MOVE    R1, R8                  ; DEPS[j]
                ADD     R9, R8
                MOVE    @R8, R8
                MOVE    R8, R11
                AND     0x1000, R11             ; dependent?
                RBRA    _DMH_HSCANN, Z
                MOVE    R8, R11
                AND     0x00FF, R11
                CMP     R5, R11                 ; line of THIS mother?
                RBRA    _DMH_HSCANN, !Z
                SHR     8, R8                   ; R8: its item mask
                AND     0x000F, R8
                MOVE    R6, R11                 ; test mask bit s
_DMH_HSH        CMP     0, R11
                RBRA    _DMH_HTST, Z
                SHR     1, R8
                SUB     1, R11
                RBRA    _DMH_HSH, 1
_DMH_HTST       AND     1, R8
                RBRA    _DMH_HSCANN, !Z         ; bit set: visible in state s
                ADD     1, R10                  ; hidden in state s
_DMH_HSCANN     ADD     1, R9
                RBRA    _DMH_HSCAN, 1
_DMH_HSCANE     CMP     R12, R10                ; new minimum?
                RBRA    _DMH_SNEXT, !N          ; no: R10 >= R12
                MOVE    R10, R12
_DMH_SNEXT      ADD     1, R6
                RBRA    _DMH_SLOOP, 1

_DMH_SDONE      ADD     R12, R4                 ; sum += minimum of this mother

_DMH_NEXT       ADD     1, R3
                RBRA    _DMH_OUTER, 1

_DMH_DONE       MOVE    R4, R8                  ; R8: the sum
                MOVE    @SP++, R12              ; restore the caller globals
                MOVE    @SP++, R11
                MOVE    @SP++, R10
                MOVE    @SP++, R9
                DECRB
                RET

; OPTM_DEPS_PROBE (the config.vhd feature probe) lives in options.asm, next to
; its callers HELP_MENU / HELP_MENU_INIT, because it touches the QNICE config
; device registers (M2M$CFG_OPTM_DEPS etc.). Keeping it out of this file lets
; the routines above stay pure and emulator-testable in isolation.
