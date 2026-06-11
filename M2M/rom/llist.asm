; ****************************************************************************
; MiSTer2MEGA65 (M2M) QNICE ROM
;
; Simple Linked List
;
; The list is doubly linked (NEXT + PREV) but its overhead is intentionally
; kept very small: a node header is just three words (NEXT/PREV/DATA_SIZE).
;
; Building a sorted list is a two-step pattern: first append nodes in input
; order with the O(1) SLL$APPEND, then run the explicit O(N log N) sort
; with SLL$SORT.  The previous O(N^2) "sorted insert" SLL$S_INSERT has been
; retired in favour of this build-then-sort pattern, which is dramatically
; faster for large lists (see MJoergen/C64MEGA65 issues #134 and #228).
;
; The sort is a bottom-up iterative mergesort that walks SLL$NEXT only; a
; single forward pass at the end of the sort rebuilds the SLL$PREV chain.
; Algorithm: Knuth TAOCP Vol 3 section 5.2.4 / Simon Tatham's classic
; write-up at
; https://www.chiark.greenend.org.uk/~sgtatham/algorithms/listsort.html .
;
; done by sy2002 in 2022 and 2026 and licensed under GPL v3
; ****************************************************************************


; Simple Linked List: Record Layout

SLL$NEXT        .EQU    0x0000                  ; pointer: next element
SLL$PREV        .EQU    0x0001                  ; pointer: previous element
SLL$DATA_SIZE   .EQU    0x0002                  ; amount of data (words)
SLL$DATA        .EQU    0x0003                  ; pointer: data

SLL$OVRHD_SIZE  .EQU    0x0003                  ; size of the structural
                                                ; overhead other than data

; ----------------------------------------------------------------------------
; Find n elements after or before the given point in the list
; Input:
;   R8: Pointer to any element of the linked list
;   R9: -1: iterate backward  1: iterate forward
;  R10: Amount of elements to iterate
; Output:
;  R11: Target element (result of iteration) or 0, if we iterated too far
;  R12: Signed amount of iterated elements
; ----------------------------------------------------------------------------

SLL$ITERATE     INCRB

                XOR     R12, R12

                ; if either the pointer is zero or the iteration mode is
                ; invalid or the iteration amount is zero, return
                CMP     0, R8                   ; input ptr zero?
                RBRA    _SLLIT_RETORG, Z        ; yes: return original (zero)
                CMP     0, R9                   ; iteration amount zero?
                RBRA    _SLLIT_RETORG, Z        ; yes: return original
                CMP     0, R10                  ; nothing to iterate?
                RBRA    _SLLIT_RETORG, Z        ; yes: return original
                CMP     -1, R9                  ; valid R9 (-1)?
                RBRA    _SLLIT_PREV, Z          ; yes: remember and start
                CMP     1, R9                   ; another valid R9 (1)?
                RBRA    _SLLIT_NEXT, Z          ; yes: remember and start
                RBRA    _SLLIT_RET0, 1          ; no: return 0

                ; R7: depending on if we are iterating forward or backward:
                ; contains the address to be added to the SLL element to
                ; extract either the NEXT or the PREV pointer
_SLLIT_PREV     MOVE    SLL$PREV, R7            ; -1: iterate backward
                RBRA    _SLLIT_START, 1
_SLLIT_NEXT     MOVE    SLL$NEXT, R7            ; +1: iterate forward

                ; iterate through the list by the given amount
                ; return 0 in case we cross boundaries
_SLLIT_START    MOVE    R8, R0                  ; R0: iteration pointer
                MOVE    R10, R1                 ; R1: amount of iterations

_SLLIT_ITERATE  ADD     R9, R12                 ; count one more iteration
                ADD     R7, R0                  ; ptr. to next/prev element
                MOVE    @R0, R0                 ; try to go to next element
                RBRA    _SLLIT_RET0, Z          ; no next element? return 0!
                SUB     1, R1                   ; one less iteration
                RBRA    _SLLIT_ITERATE, !Z

                MOVE    R0, R11                 ; return target element
                RBRA    _SLLIT_RET, 1

_SLLIT_RETORG   MOVE    R8, R11                 ; return the original R8
                RBRA    _SLLIT_RET, 1
_SLLIT_RET0     XOR     R11, R11                ; return zero
_SLLIT_RET      DECRB
                RET

; ----------------------------------------------------------------------------
; Find last element and count the amount of elements
; Input:
;   R8: Pointer to head of linked list
; Output:
;   R9: Pointer to last element
;  R10: Amount of elements
; ----------------------------------------------------------------------------

SLL$LASTNCOUNT  INCRB

                MOVE    R8, R9                  ; R9: pointer to last element
                XOR     R10, R10                ; R10: amount of elements

                CMP     0, R8                   ; head is null
                RBRA    _SLLLNC_RET, Z

_SLLLNC_LOOP    ADD     1, R10                  ; one more element
                MOVE    R9, R0                  ; remember element
                ADD     SLL$NEXT, R9            ; next element available?
                MOVE    @R9, R9
                RBRA    _SLLLNC_RETELM, Z       ; no: return
                RBRA    _SLLLNC_LOOP, 1         ; yes: next element

_SLLLNC_RETELM  MOVE    R0, R9                  ; return last element
_SLLLNC_RET     DECRB
                RET

; ----------------------------------------------------------------------------
; Append: O(1) tail append.  Builds the list in input order; pair with
; SLL$SORT to obtain a sorted list.
;
; Tail tracking uses the internal variable _SLL_TAIL (see end of this file).
; Only one list may be under construction at any time.  The static is
; reset implicitly by the first SLL$APPEND call of each new build: if R8
; (head) == 0, the new node becomes both head and tail and _SLL_TAIL is
; overwritten -- the caller does not need to clean anything up between two
; unrelated builds, as long as it starts the new one with head = 0.
; SLL$SORT also clears _SLL_TAIL when it completes.
;
; Input
;   R8: Pointer to head of linked list, zero if this is the first element
;   R9: Pointer to new element
;  R10: Pointer to an optional FILTER function that returns 0, if the current
;       element is OK and shall be inserted and 1, if the current element
;       shall be filtered, i.e. not inserted. R8 contains the element-pointer
;       and R8 is also used as return value, i.e. R8 is overwritten.
;       Zero if no filter is to be applied.
;
; Output:
;   R8: (New) head of linked list
;
; Notes:
;  - The new element's NEXT pointer is set to zero by SLL$APPEND.  PREV is
;    NOT maintained during append -- SLL$SORT will rebuild the complete PREV
;    chain in its final fix-up pass.  Iterating the list with SLL$ITERATE
;    in backward direction (R9 = -1) is therefore only valid after SLL$SORT
;    has run.
; ----------------------------------------------------------------------------

SLL$APPEND      INCRB
                MOVE    R9, R0                  ; preserve caller's R9
                MOVE    R10, R1                 ; preserve caller's R10
                MOVE    R11, R2                 ; preserve caller's R11
                INCRB

                MOVE    R8, R0                  ; R0: current head
                MOVE    R9, R1                  ; R1: new element
                MOVE    R10, R2                 ; R2: filter func. or 0

                ; apply filter if one was supplied
                CMP     0, R2                   ; filter function provided?
                RBRA    _SLLAP_NOFILT, Z        ; no: continue
                MOVE    R1, R8                  ; R8: element ptr (filter API)
                ASUB    R2, 1                   ; call filter
                CMP     1, R8                   ; filter rejected?
                RBRA    _SLLAP_REJECT, Z        ; yes: do not append

                ; the new node will become the new tail; clear its NEXT
_SLLAP_NOFILT   MOVE    R1, R3                  ; R3: &new.NEXT
                ADD     SLL$NEXT, R3
                MOVE    0, @R3

                ; first element of a new list?  (head == 0)
                CMP     0, R0
                RBRA    _SLLAP_FIRST, Z

                ; subsequent append: hook onto the current tail
                MOVE    _SLL_TAIL, R3           ; R3: &_SLL_TAIL
                MOVE    @R3, R4                 ; R4: current tail
                ADD     SLL$NEXT, R4            ; R4: &tail.NEXT
                MOVE    R1, @R4                 ; tail.NEXT = new
                MOVE    R1, @R3                 ; _SLL_TAIL = new
                MOVE    R0, R8                  ; return unchanged head
                RBRA    _SLLAP_RET, 1

                ; first element: new node is both head and tail
_SLLAP_FIRST    MOVE    R1, R8                  ; new head
                MOVE    _SLL_TAIL, R3
                MOVE    R1, @R3                 ; _SLL_TAIL = new
                RBRA    _SLLAP_RET, 1

                ; filter rejected the element: keep head, do nothing else
_SLLAP_REJECT   MOVE    R0, R8

_SLLAP_RET      DECRB
                MOVE    R0, R9                  ; restore R9, R10, R11
                MOVE    R1, R10
                MOVE    R2, R11
                DECRB
                RET

; ----------------------------------------------------------------------------
; Sort: bottom-up iterative linked-list mergesort.
;
; Replaces the per-insert O(N^2) sorted-insert with an explicit O(N log N)
; pass.  Pair with SLL$APPEND for a build-then-sort flow.  See the file
; header for the algorithm reference (Knuth / Tatham).
;
; The sort walks SLL$NEXT only; a single O(N) forward pass at the end
; rebuilds the SLL$PREV chain.  After completion the internal tail tracker
; (_SLL_TAIL) is cleared so the next SLL$APPEND-driven build starts fresh.
;
; Input
;   R8: Pointer to head of linked list, zero if list is empty
;   R9: Pointer to a COMPARE function (same contract as the retired
;       SLL$S_INSERT comparator: R8=S0, R9=S1, returns sign in R10 - negative
;       if S0<S1, zero if equal, positive if S0>S1).  R10 is overwritten by
;       the call.  The comparator MUST preserve R8, R9, R11 across the call,
;       which existing M2M comparators (_DIRBR_COMPARE, CMP_FUNC) already
;       guarantee through the standard register-bank discipline.
;
; Output:
;   R8: New head of sorted list
;
; Notes:
;  - Caller's R9, R10, R11 are preserved across the call.
;  - Worst-case transient cost is on the order of 10 words across the two
;    internal register banks.  No per-node memory growth.
;  - On an empty input list (R8 == 0) the routine is a no-op that returns
;    R8 = 0; _SLL_TAIL is left untouched.
;  - Maximum list length is bounded by N <= 32767.  insize doubles each pass
;    via an unsigned 16-bit ADD, so the algorithm would wrap to zero at
;    insize = 32768.  Unreachable from current callers (HEAP_SIZE caps the
;    file browser at ~1800 entries; the testbed uses 500), but document it
;    here so any future caller knows.
; ----------------------------------------------------------------------------

SLL$SORT        INCRB
                ; bank+1: caller-save and outer-pass scalars
                ;   R0 = saved caller's R10
                ;   R1 = saved caller's R11
                ;   R2 = insize
                ;   R3 = nmerges
                ;   R4 = saved caller's R9
                MOVE    R10, R0
                MOVE    R11, R1
                MOVE    R9,  R4

                MOVE    R9, R11                 ; R11: comparator (kept here
                                                ; throughout; not banked, but
                                                ; preserved by all M2M
                                                ; comparators by convention)

                CMP     0, R8                   ; empty list?
                RBRA    _SORT_RET, Z

                MOVE    1, R2                   ; insize = 1

                INCRB
                ; bank+2: inner-loop scratch
                ;   R0 = p (input cursor)
                ;   R1 = out_head (built during pass)
                ;   R2 = out_tail
                ;   R3 = q (second sublist cursor)
                ;   R4 = psize
                ;   R5 = qsize
                ;   R6 = e (element chosen this iteration)
                ;   R7 = scratch (i counter for q-stepping, address temp)

_SORT_PASS      MOVE    R8, R0                  ; p = current pass head
                XOR     R1, R1                  ; out_head = 0
                XOR     R2, R2                  ; out_tail = 0
                DECRB
                XOR     R3, R3                  ; nmerges = 0
                INCRB

_SORT_PAIR      CMP     0, R0                   ; p == NULL?
                RBRA    _SORT_PASSEND, Z

                ; nmerges++ and pick up insize via the shared R8 register
                DECRB
                ADD     1, R3
                MOVE    R2, R8                  ; R8 carries insize across the
                                                ; bank switch (R8-R12 are not
                                                ; banked)
                INCRB

                MOVE    R0, R3                  ; q = p (start of q-walk)
                XOR     R4, R4                  ; psize = 0
                MOVE    R8, R7                  ; R7 = i (count down insize)

_SORT_STEPQ     CMP     0, R3                   ; q == NULL?
                RBRA    _SORT_QREADY, Z
                ADD     1, R4                   ; psize++
                ADD     SLL$NEXT, R3            ; q = q.NEXT
                MOVE    @R3, R3
                SUB     1, R7
                RBRA    _SORT_STEPQ, !Z

_SORT_QREADY    MOVE    R8, R5                  ; qsize = insize

_SORT_MERGE     CMP     0, R4                   ; psize == 0?
                RBRA    _SORT_TRYQ, Z
                CMP     0, R5                   ; qsize == 0?
                RBRA    _SORT_FROMP, Z
                CMP     0, R3                   ; q == NULL?
                RBRA    _SORT_FROMP, Z

                ; both sublists non-empty: call the comparator
                MOVE    R0, R8                  ; S0 = p
                MOVE    R3, R9                  ; S1 = q
                ASUB    R11, 1                  ; R10 = sign of S0 - S1
                CMP     0, R10                  ; R10 < 0?
                RBRA    _SORT_FROMP, V          ; yes: take p
                ; fall through: R10 >= 0: take q (FAT32 directory entry names
                ;   are unique by construction so ties never occur here)

_SORT_FROMQ     MOVE    R3, R6                  ; e = q
                ADD     SLL$NEXT, R3            ; q = q.NEXT
                MOVE    @R3, R3
                SUB     1, R5                   ; qsize--
                RBRA    _SORT_LINK, 1

_SORT_TRYQ      ; psize == 0: pick from q if possible, else end the merge
                CMP     0, R5                   ; qsize == 0?
                RBRA    _SORT_MERGEEND, Z
                CMP     0, R3                   ; q == NULL?
                RBRA    _SORT_MERGEEND, Z
                RBRA    _SORT_FROMQ, 1

_SORT_FROMP     MOVE    R0, R6                  ; e = p
                ADD     SLL$NEXT, R0            ; p = p.NEXT
                MOVE    @R0, R0
                SUB     1, R4                   ; psize--

_SORT_LINK      CMP     0, R2                   ; out_tail == NULL?
                RBRA    _SORT_LINKFST, Z
                MOVE    R2, R7                  ; tail.NEXT = e
                ADD     SLL$NEXT, R7
                MOVE    R6, @R7
                RBRA    _SORT_LINKEND, 1
_SORT_LINKFST   MOVE    R6, R1                  ; out_head = e

_SORT_LINKEND   MOVE    R6, R2                  ; out_tail = e
                RBRA    _SORT_MERGE, 1

_SORT_MERGEEND  MOVE    R3, R0                  ; p = q (start of next pair)
                RBRA    _SORT_PAIR, 1

_SORT_PASSEND   ; pass done.  Terminate the output list (out_tail may still
                ; hold a stale NEXT from when it was lifted out of its
                ; input sublist) and decide whether another pass is needed.
                CMP     0, R2
                RBRA    _SORT_PNMC, Z           ; (defensive: only possible if
                                                ;  the input had been empty,
                                                ;  which we already filtered)
                MOVE    R2, R7
                ADD     SLL$NEXT, R7
                MOVE    0, @R7                  ; out_tail.NEXT = 0

_SORT_PNMC      MOVE    R1, R8                  ; head for next pass / final

                DECRB
                CMP     1, R3                   ; nmerges == 1?
                RBRA    _SORT_FIX, Z            ; yes: done sorting
                ; nmerges < 1 cannot happen with a non-empty input list, but
                ; check defensively
                RBRA    _SORT_FIX, V            ; nmerges < 1: done

                ; nmerges >= 2: another pass with doubled run size
                ADD     R2, R2                  ; insize *= 2
                INCRB
                RBRA    _SORT_PASS, 1

_SORT_FIX       ; sort complete.  R8 holds the sorted head.  Walk the list
                ; once forward to rebuild the SLL$PREV chain.
                INCRB                           ; back to bank+2 for scratch
                XOR     R0, R0                  ; prev = 0
                MOVE    R8, R1                  ; curr = head

_SORT_FIXLOOP   CMP     0, R1                   ; curr == NULL?
                RBRA    _SORT_FIXDONE, Z
                MOVE    R1, R2                  ; &curr.PREV
                ADD     SLL$PREV, R2
                MOVE    R0, @R2                 ; curr.PREV = prev
                MOVE    R1, R0                  ; prev = curr (save before
                                                ;  mutating R1)
                ADD     SLL$NEXT, R1            ; curr = curr.NEXT
                MOVE    @R1, R1
                RBRA    _SORT_FIXLOOP, 1

_SORT_FIXDONE   MOVE    _SLL_TAIL, R0           ; clear the tail tracker so
                MOVE    0, @R0                  ; the next build starts fresh
                DECRB                           ; back to bank+1

_SORT_RET       MOVE    R0, R10                 ; restore R10, R11, R9
                MOVE    R1, R11
                MOVE    R4, R9
                DECRB
                RET

; ----------------------------------------------------------------------------
; Static state for SLL$APPEND / SLL$SORT
;
; _SLL_TAIL is a single word used by SLL$APPEND to remember the current tail
; of the list under construction, and reset by SLL$SORT on completion.
;
; The reservation does NOT live in llist.asm itself: the production Shell
; build includes this file inline well below the 0x8000 RAM boundary
; (CORE/m2m-rom/m2m-rom.asm:561 sets .ORG 0x8000 for the RAM section), so a
; .BLOCK at the end of this file would land in ROM and every write to
; _SLL_TAIL would be a silent no-op (QNICE BROM has no write port).  The
; tail reservation lives in:
;
;   - M2M/rom/dirbrowse_vars.asm  (production: included from shell_vars.asm
;                                  AFTER .ORG 0x8000, lands in RAM)
;   - M2M/rom/llist_test.asm      (standalone testbed: declared next to
;                                  HEAP_HEAD/HEAP_START at the file tail)
;
; Only one list may be under construction at any time; this is enforced by
; convention (every caller starts a new build with R8 = 0, which causes
; the first SLL$APPEND to reset _SLL_TAIL).
; ----------------------------------------------------------------------------
