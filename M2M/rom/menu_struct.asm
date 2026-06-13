; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Menu structure algorithms for the Options Menu (menu.asm)
;
; This file is part of the self-contained menu component (menu.asm,
; menu_vars.asm, menu_struct.asm) and is included at the end of menu.asm.
;
; All three routines in this file are pure functions over plain arrays in
; memory: they do not touch any M2M device registers and do not depend on
; the Shell. This makes them directly testable in the QNICE emulator, see
; menu_struct_test.asm, menu_equiv_test.asm and menu_nav_test.asm.
;
; Background: Since M2M V2.1.0 submenus can be nested to an arbitrary depth.
; A submenu ("region") is a bracketed range inside OPTM_GROUPS: it starts
; with an "opener" line (OPTM_SUBMENU flag set, low byte 0x00) and ends with
; a "closer" line (OPTM_SUBMENU flag set, low byte nonzero, by convention
; OPTM_CLOSE). A nested submenu is a complete opener/closer block inside
; another region. Region ids are assigned 1, 2, 3, ... in the order in which
; the openers appear; the main menu is region 0.
;
; done by sy2002 in 2026 and licensed under GPL v3
; ****************************************************************************

; ----------------------------------------------------------------------------
; OPTM_STRUCT_BUILD: Build the menu structure array for one menu level
;
; Single forward pass over the groups array. The CPU stack doubles as the
; transient region-parse stack: push the current region id on each opener,
; pop it on each closer. The stack usage is bounded by the maximum nesting
; depth (at most one word per level) and is always fully unwound on return,
; also on the error path.
;
; Visibility rules implemented here (L = level that is being built):
;   * plain line in region R (innermost):  visible <=> L == R
;   * opener of region R with parent P:    visible <=> L == P
;     (the opener doubles as the label of the submenu in the parent view)
;   * closer of region R:                  visible <=> L == R
;
; As a byproduct, the routine records the parent region id of L and the flat
; index of the opener of L. These two values are all that the leave path
; (_OPTM_RUN_SM_L in menu.asm) needs to pop exactly one menu level; there is
; deliberately no persistent level stack, so arbitrary nesting depth comes
; at no extra RAM cost and the bookkeeping can never go stale.
;
; Input:
;   R8: pointer to the output array (R9 plus 1 words, reserved by the caller)
;   R9: amount of menu items (N)
;  R10: pointer to the groups array (N words, see OPTM_IR_GROUPS)
;  R11: menu level to build for (0 = main menu)
;
; Output:
;   C=0: success
;        R8:  unchanged (pointer to the output array)
;             array word 0 = N; array word 1+i = region id of line i in bits
;             0..14, bit 15 = line i is visible at level R11
;        R9:  amount of visible lines at level R11
;        R10: region id of the parent of level R11 (0 if R11 is 0)
;        R11: flat index of the opener of level R11 (0 if R11 is 0)
;   C=1: error: the brackets in the groups array are unbalanced
;        R8:  unchanged
;        R10: flat index of the offending line: the closer that has no
;             matching opener, or the last opener if a region is not closed
;
;   R12 is destroyed.
; ----------------------------------------------------------------------------

OPTM_STRUCT_BUILD INCRB

                MOVE    R8, R0                  ; R0: output cursor
                MOVE    R9, @R0++               ; array word 0 = N
                MOVE    R9, R1                  ; R1: loop counter
                MOVE    R10, R2                 ; R2: groups cursor
                XOR     R3, R3                  ; R3: current region id
                MOVE    1, R4                   ; R4: next region id
                XOR     R5, R5                  ; R5: nesting depth
                XOR     R6, R6                  ; R6: visible line counter
                XOR     R9, R9                  ; R9: byproduct: parent of L
                XOR     R10, R10                ; R10: byproduct: opener of L
                XOR     R12, R12                ; R12: last opener seen

                CMP     0, R1                   ; empty menu? (defensive,
                RBRA    _OSB_DONE, Z            ; the Shell validates earlier)

_OSB_LOOP       MOVE    @R2, R7                 ; R7: current group word
                AND     OPTM_SUBMENU, R7        ; submenu marker?
                RBRA    _OSB_PLAIN, Z           ; no: plain line
                MOVE    @R2, R7
                AND     0x00FF, R7              ; low byte 0x00 = opener
                RBRA    _OSB_OPEN, Z

                ; closer of the current region
                CMP     0, R5                   ; closer without any opener?
                RBRA    _OSB_ERR_CLS, Z         ; yes: unbalanced
                MOVE    R3, R7                  ; entry: id = current region
                CMP     R3, R11                 ; visible <=> L == region
                RBRA    _OSB_CLS_1, !Z
                OR      0x8000, R7
                ADD     1, R6
_OSB_CLS_1      MOVE    R7, @R0++               ; store entry
                MOVE    @SP++, R3               ; current id = pop parent
                SUB     1, R5                   ; depth - 1
                RBRA    _OSB_NEXT, 1

                ; opener of a new region
_OSB_OPEN       MOVE    R0, R7                  ; R7: flat index of this line:
                SUB     R8, R7                  ; output cursor minus array
                SUB     1, R7                   ; base minus the size word
                MOVE    R7, R12                 ; remember last opener seen
                CMP     R4, R11                 ; is the new region level L?
                RBRA    _OSB_OPN_1, !Z          ; no
                MOVE    R3, R9                  ; byproduct: parent of L
                MOVE    R7, R10                 ; byproduct: opener of L
_OSB_OPN_1      MOVE    R3, @--SP               ; push parent region id
                ADD     1, R5                   ; depth + 1
                MOVE    R4, R7                  ; entry: id = new region
                CMP     R3, R11                 ; visible <=> L == parent
                RBRA    _OSB_OPN_2, !Z
                OR      0x8000, R7
                ADD     1, R6
_OSB_OPN_2      MOVE    R7, @R0++               ; store entry
                MOVE    R4, R3                  ; current id = new region
                ADD     1, R4                   ; next region id + 1
                RBRA    _OSB_NEXT, 1

                ; plain line (including headlines, separator lines, etc.)
_OSB_PLAIN      MOVE    R3, R7                  ; entry: id = current region
                CMP     R3, R11                 ; visible <=> L == region
                RBRA    _OSB_PLN_1, !Z          ; not at this level: hidden
                ; the line is at this level; a dependency may still hide it.
                ; only plain lines can be dependent (openers and closers never
                ; are, see optm_deps.asm), so this is the only place the
                ; dependency predicate enters the builder
                MOVE    R8, @--SP               ; save the output array base
                MOVE    R0, R8                  ; flat index of this line:
                SUB     @SP, R8                 ;   output cursor - base - 1
                SUB     1, R8
                RSUB    OPTM_DEP_OK, 1          ; visible? (C=1 = yes)
                MOVE    @SP++, R8               ; restore the output array base
                RBRA    _OSB_PLN_1, !C          ; a dependency hides this line
                OR      0x8000, R7              ; visible: set bit 15
                ADD     1, R6                   ; and count it
_OSB_PLN_1      MOVE    R7, @R0++               ; store entry

_OSB_NEXT       ADD     1, R2                   ; next group word
                SUB     1, R1                   ; more menu items?
                RBRA    _OSB_LOOP, !Z           ; yes: loop

                CMP     0, R5                   ; all regions closed?
                RBRA    _OSB_ERR_OPN, !Z        ; no: unbalanced

_OSB_DONE       MOVE    R10, R11                ; return opener of L
                MOVE    R9, R10                 ; return parent of L
                MOVE    R6, R9                  ; return visible line count
                AND     0xFFFB, SR              ; clear Carry: success
                DECRB
                RET

                ; error: closer without opener: offending index = current line
_OSB_ERR_CLS    MOVE    R0, R10
                SUB     R8, R10
                SUB     1, R10
                RBRA    _OSB_ERR, 1

                ; error: region never closed: offending index = last opener
_OSB_ERR_OPN    MOVE    R12, R10

_OSB_ERR        ADD     R5, SP                  ; unwind the region stack
                OR      0x0004, SR              ; set Carry: error
                DECRB
                RET

; ----------------------------------------------------------------------------
; OPTM_STRUCT_VAL: Validate the bracket structure of a groups array
;
; Meant to be run once at boot time (see _HLP_S3 in options.asm). Checks:
;
; 1. The opener/closer brackets balance and never close more regions than
;    have been opened. This is strictly stronger than the pre-V2.1.0 parity
;    check: every sequence that it newly rejects was already broken at
;    runtime before (scrambled menus or a guaranteed-reachable QNICE halt).
; 2. The OPTM_G_START line is visible in the main menu: it is either a line
;    outside of all regions or it is an opener at nesting depth 1. A start
;    cursor on a line that is invisible at the main level would halt QNICE
;    with OPTM_F_MENUIDX on the very first OPTM_RUN.
;
; Additionally the routine computes the number of regions (which equals the
; number of openers and is needed for the %s replacement string slots, see
; OPTM_SCOUNT) and the height of the largest menu view in lines, so that the
; caller can warn when a view does not fit the configured window height.
;
; Uses the CPU stack as the transient parse stack (one word per nesting
; level: the suspended line counter of the enclosing view); always fully
; unwound on return.
;
; Input:
;   R8: pointer to the groups array (N words)
;   R9: amount of menu items (N)
;  R10: flat index of the OPTM_G_START line (0xFFFF: skip the start check)
;
; Output:
;   C=0: success
;        R9:  amount of regions (= amount of openers = amount of submenus)
;        R10: height of the largest view in lines (including the main menu)
;   C=1: error
;        R9:  error class: 0 = closer without opener
;                          1 = opener without closer
;                          2 = OPTM_G_START on a line that is invisible in
;                              the main menu
;        R10: flat index of the offending line
;
;   R8 is unchanged; R11 and R12 are destroyed.
; ----------------------------------------------------------------------------

OPTM_STRUCT_VAL INCRB

                MOVE    R10, R11                ; R11: OPTM_G_START index
                MOVE    R8, R0                  ; R0: groups cursor
                MOVE    R9, R1                  ; R1: loop counter
                XOR     R2, R2                  ; R2: nesting depth
                XOR     R3, R3                  ; R3: current view height
                XOR     R4, R4                  ; R4: amount of openers
                XOR     R5, R5                  ; R5: largest view height
                XOR     R6, R6                  ; R6: flat index of cur. line
                XOR     R12, R12                ; R12: last opener seen

                CMP     0, R1                   ; empty menu? (defensive)
                RBRA    _OSV_DONE, Z

_OSV_LOOP       MOVE    @R0++, R10              ; R10: current group word
                MOVE    R10, R7
                AND     OPTM_SUBMENU, R7        ; submenu marker?
                RBRA    _OSV_PLAIN, Z           ; no: plain line
                AND     0x00FF, R10             ; low byte 0x00 = opener
                RBRA    _OSV_OPEN, Z

                ; closer of the current region
                CMP     0, R2                   ; closer without any opener?
                RBRA    _OSV_ERR_CLS, Z         ; yes: unbalanced
                CMP     R6, R11                 ; OPTM_G_START on a closer?
                RBRA    _OSV_ERR_STRT, Z        ; never visible at main level
                ADD     1, R3                   ; closer shows in its own view
                CMP     R3, R5                  ; new largest view?
                RBRA    _OSV_CLS_1, !N          ; no
                MOVE    R3, R5                  ; yes: remember
_OSV_CLS_1      MOVE    @SP++, R3               ; resume enclosing view height
                SUB     1, R2                   ; depth - 1
                RBRA    _OSV_NEXT, 1

                ; opener of a new region
_OSV_OPEN       CMP     R6, R11                 ; OPTM_G_START on this opener?
                RBRA    _OSV_OPN_1, !Z          ; no
                CMP     0, R2                   ; valid only at depth 0, i.e.
                RBRA    _OSV_ERR_STRT, !Z       ; on a label the main menu shows
_OSV_OPN_1      MOVE    R6, R12                 ; remember last opener seen
                ADD     1, R3                   ; label shows in parent view
                MOVE    R3, @--SP               ; suspend parent view height
                XOR     R3, R3                  ; new view starts empty
                ADD     1, R2                   ; depth + 1
                ADD     1, R4                   ; one more region
                RBRA    _OSV_NEXT, 1

                ; plain line
_OSV_PLAIN      ADD     1, R3                   ; line shows in current view
                CMP     R6, R11                 ; OPTM_G_START on this line?
                RBRA    _OSV_NEXT, !Z           ; no
                CMP     0, R2                   ; visible at main level?
                RBRA    _OSV_ERR_STRT, !Z       ; no: inside a region

_OSV_NEXT       ADD     1, R6                   ; next flat index
                SUB     1, R1                   ; more menu items?
                RBRA    _OSV_LOOP, !Z           ; yes: loop

                CMP     0, R2                   ; all regions closed?
                RBRA    _OSV_ERR_OPN, !Z        ; no: unbalanced

_OSV_DONE       CMP     R3, R5                  ; main menu = largest view?
                RBRA    _OSV_DONE_1, !N         ; no
                MOVE    R3, R5                  ; yes: remember
_OSV_DONE_1     MOVE    R4, R9                  ; return amount of regions
                MOVE    R5, R10                 ; return largest view height
                AND     0xFFFB, SR              ; clear Carry: success
                DECRB
                RET

                ; error: closer without opener (class 0)
_OSV_ERR_CLS    MOVE    R6, R10                 ; offending index
                XOR     R9, R9                  ; class 0
                RBRA    _OSV_ERR, 1

                ; error: opener without closer (class 1)
_OSV_ERR_OPN    MOVE    R12, R10                ; offending index: last opener
                MOVE    1, R9                   ; class 1
                RBRA    _OSV_ERR, 1

                ; error: OPTM_G_START invisible at main level (class 2)
_OSV_ERR_STRT   MOVE    R6, R10                 ; offending index = this line
                MOVE    2, R9                   ; class 2

_OSV_ERR        ADD     R2, SP                  ; unwind the parse stack
                OR      0x0004, SR              ; set Carry: error
                DECRB
                RET

; ----------------------------------------------------------------------------
; OPTM_SUMM_SCAN: Find the menu item that summarizes a submenu
;
; Default semantics of the %s replacement in a submenu opener line: walk
; forward from the opener and return the first line that belongs to a plain
; multi-select group (a "radio button" group) of this very region, that is
; currently selected and that is not hidden by a dependency (see
; OPTM_DEP_OK / optm_deps.asm; the dependency test is a no-op when the
; feature is off). Lines of nested child regions are skipped: on a
; child opener the walk starts skipping, on the matching child closer it
; stops skipping (a depth counter, no stack needed). Reaching the closer of
; the region itself means the region has no radio group of its own.
;
; Input:
;   R8: pointer to the group word of the opener (inside the groups array)
;   R9: end-of-menu sentinel: pointer to one word behind the last group word
;  R10: pointer to the selected-state array (see OPTM_IR_STDSEL); must be
;       indexed identically to the groups array
;  R11: pointer to the first word of the groups array (used for indexing)
;
; Output:
;   C=1: found
;        R8: pointer to the group word of the found line
;   C=0: not found
;        R8: 0 = reached the end of the whole menu (broken structure)
;            1 = reached the closer of the region (no radio group inside)
;
;   R9 is unchanged; R10, R11 and R12 are destroyed.
; ----------------------------------------------------------------------------

OPTM_SUMM_SCAN  INCRB

                MOVE    R8, R0                  ; R0: walk cursor
                MOVE    R9, R2                  ; R2: end-of-menu sentinel
                MOVE    R10, R3                 ; R3: selected-state array
                MOVE    R11, R4                 ; R4: groups array base
                XOR     R1, R1                  ; R1: child region depth

_OSS_LOOP       ADD     1, R0                   ; next line
                CMP     R2, R0                  ; end of the whole menu?
                RBRA    _OSS_ERR_END, Z         ; yes: broken structure
                MOVE    @R0, R7
                AND     OPTM_SUBMENU, R7        ; submenu marker?
                RBRA    _OSS_PLAIN, Z           ; no: plain line
                MOVE    @R0, R7
                AND     0x00FF, R7              ; low byte 0x00 = opener
                RBRA    _OSS_CHILD_O, Z
                CMP     0, R1                   ; closer: inside a child?
                RBRA    _OSS_ERR_CLS, Z         ; no: our own region ends
                SUB     1, R1                   ; yes: child region ends
                RBRA    _OSS_LOOP, 1

_OSS_CHILD_O    ADD     1, R1                   ; child region starts
                RBRA    _OSS_LOOP, 1

_OSS_PLAIN      CMP     0, R1                   ; inside a child region?
                RBRA    _OSS_LOOP, !Z           ; yes: skip the line

                MOVE    @R0, R8                 ; plain multi-select group
                MOVE    1, R9                   ; member? group word needs to
                MOVE    255, R10                ; be within 1 .. 254: single
                SYSCALL(in_range_u, 1)          ; selects, headlines etc. fall
                RBRA    _OSS_LOOP, !C           ; outside: skip the line

                MOVE    R0, R8                  ; hidden by a dependency? then
                SUB     R4, R8                  ; this radio member does not
                RSUB    OPTM_DEP_OK, 1          ; count for the summary either
                RBRA    _OSS_LOOP, !C           ; (no-op when deps are off)

                MOVE    R0, R8                  ; selected? look up the same
                SUB     R4, R8                  ; index in the selected-state
                ADD     R3, R8                  ; array
                MOVE    @R8, R8
                RBRA    _OSS_LOOP, Z            ; not selected: skip the line

                MOVE    R0, R8                  ; found: return the pointer
                MOVE    R2, R9                  ; restore R9 (sentinel)
                OR      0x0004, SR              ; set Carry: found
                DECRB
                RET

_OSS_ERR_END    XOR     R8, R8                  ; 0 = end of menu reached
                RBRA    _OSS_ERR, 1
_OSS_ERR_CLS    MOVE    1, R8                   ; 1 = own closer reached
_OSS_ERR        MOVE    R2, R9                  ; restore R9 (sentinel)
                AND     0xFFFB, SR              ; clear Carry: not found
                DECRB
                RET
