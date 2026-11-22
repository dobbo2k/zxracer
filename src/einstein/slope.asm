; ---------------------------------------------------------------------------
; Einstein: a sloped row of the near road (rows 16-23), drawn in one pass
;
; EinRowFast hands over a row whose kerb edges slope more than EIN_SLOPE
; pixels, its ranges made as EinRowRanges makes them. It is drawn the exact
; way, as EinRowBase would (src/einstein/roadgfx.asm): its names, its slots,
; each kerb cell an edge crosses in its line pairs (lines 0, 2, 4, 6: the
; Spectrum draws both lines of a pair from the even one), the centre line.
; But the kerb cells come straight from the pairs' edges in pixels: in the
; left run a pair's byte is all road left of its D's cell, none right of it
; and RMask in it; in the right run, all road right of its E's cell, none
; left of it and LMaskIncl in it. That is EinCellMasks' rule wherever each
; run is crossed by its own edge alone (every pair's E right of the left
; run, every D left of the right run): else, and for a pair without road,
; the generic way.
; ---------------------------------------------------------------------------

; From EinRowFast (sloped). NZ: drawn (EinRow notes its slots); carry: not
; this way (ESloped, its ranges made: EinRowBase)
EinSlopeRow:
        ld a, (EI)              ; ---- the pairs' D (ESlD) and E (ESlE)
        ld l, a
        ld h, high DEPage
        ld de, ESlD
        ld b, 4
.ld:    ld a, (hl)              ; D
        ld (de), a
        set 7, l
        ld c, (hl)              ; E
        res 7, l
        cp c
        jr z, .road
        jp nc, .generic         ; (no road on the pair)
.road:  ld a, e
        add a, 4
        ld e, a
        ld a, c
        ld (de), a
        ld a, e
        sub 3
        ld e, a
        inc l
        inc l
        djnz .ld
        ld hl, ESlD             ; ---- the runs, each crossed by one edge
        call .minmax            ; (B: the leftmost D, C: the rightmost)
        ld a, c
        call .cell
        ld hl, ERC
        cp (hl)
        jr nc, .generic         ; (a D's cell in the right run)
        ld a, b                 ; the left run: from the leftmost D's cell,
        call .cell              ; at least ERA, to ERB
        ld hl, ERA
        cp (hl)
        jr nc, .l0
        ld a, (hl)
.l0:    ld (.left + 1), a
        ld hl, ESlE
        call .minmax            ; (B: the leftmost E, C: the rightmost)
        ld a, b
        call .cell
        ld hl, ERB
        cp (hl)
        jr c, .generic          ; (an E's cell in the left run)
        ld a, c                 ; the right run: ERC to the rightmost E's
        call .cell              ; cell, at most ERD - 1
        inc a
        ld hl, ERD
        cp (hl)
        jr c, .r1
        ld a, (hl)
.r1:    ld (.right + 1), a
        call EinRowNames        ; ---- its names, slots, kerb cells
        call EinRowSlots
        call EinSlotRange
        ld hl, ESlD             ; the left run: D, RMask; left of it all road
        ld (.src + 1), hl
        ld a, low RMask
        ld (.tab + 1), a
        ld a, $FF
        ld (.below + 1), a
        xor a
        ld (.past + 1), a
        ld a, (ERB)
        ld (.end + 1), a
.left:  ld a, 0
        call .run
        ld hl, ESlE             ; the right run: E, LMaskIncl; right of it all road
        ld (.src + 1), hl
        ld a, low LMaskIncl
        ld (.tab + 1), a
        xor a
        ld (.below + 1), a
        dec a
        ld (.past + 1), a
.right: ld a, 0
        ld (.end + 1), a
        ld a, (ERC)
        call .run
        call EinDashRow
        or 1                    ; (drawn: NZ, no carry)
        ret
.generic:
        ld a, 1                 ; (EinRowBase: its ranges not made again)
        ld (ESloped), a
        scf
        ret

; A = a pixel -> A = its cell
.cell:  rrca
        rrca
        rrca
        and 31
        ret

; HL = 4 bytes -> B = the least, C = the most (HL on 3)
.minmax:
        ld a, (hl)
        ld b, a
        ld c, a
        DUP 3
        inc l
        ld a, (hl)
        cp b
        jr nc, $ + 3
        ld b, a
        cp c
        jr c, $ + 3
        ld c, a
        EDUP
        ret

; A = the run's first cell, .end its end: each cell's pairs into EPat (a
; pair's byte on both its lines); no road: kerb, as named; all road: road;
; else a slot in the kerb's colour (as EinKerbCells)
.run:   ld c, a                 ; C: the cell
.next:
.end:   ld a, 0
        cp c
        ret z
        ret c
        push bc
        ld a, c
        add a, a
        add a, a
        add a, a
        ld c, a                 ; C: its first pixel
.src:   ld hl, ESlD
        ld de, EPat
        ld b, 4
.px:    ld a, (hl)
        inc l
        sub c
        jr c, .below
        cp 8
        jr nc, .past
.tab:   add a, low RMask
        ld (.mk + 1), a
.mk:    ld a, (RMask)
        ASSERT high RMask == high LMaskIncl
        jr .put
.below: ld a, $FF
        jr .put
.past:  ld a, 0
.put:   ld (de), a
        inc e
        ld (de), a
        inc e
        djnz .px
        ld hl, EPat             ; ---- none, all or some road? (E: any, D: all)
        ld a, (hl)
        ld e, a
        ld d, a
        DUP 3
        inc l
        inc l
        ld a, (hl)
        or e
        ld e, a
        ld a, (hl)
        and d
        ld d, a
        EDUP
        pop bc
        ld a, e
        or a
        jr z, .skip             ; no road in it: kerb, as named
        ld a, (ECR)
        inc d
        jr z, .name             ; all road
        push bc
        ld a, (EKC)
        call EinCommitSlot
        pop bc
        cp $FF
        jr z, .skip             ; (the row's slots are all used)
.name:  ld e, a
        ld hl, (ERowPtr)
        ld a, l
        add a, c
        ld l, a
        jr nc, .nm
        inc h
.nm:    ld (hl), e
.skip:  inc c
        jr .next

ESlD:   ds 4                    ; the pairs' D, then E (pixels)
ESlE:   ds 4
        ASSERT high ESlD == high (ESlE + 3)
