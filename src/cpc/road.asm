; ---------------------------------------------------------------------------
; CPC: the road (docs/port_cpc.md 5.4)
;
; Every game frame the road's 96 lines are drawn again into the hidden
; screen, a line pair at a time (pass 1's resolution: both lines of a pair
; are the same, its band, edges and centre line on its first line). A pair
; is grass, kerb, road, kerb, grass: four edges in Mode 0 pixels (x1-x4,
; the Spectrum's halved),
;   x1 = (D - RW) / 2, x2 = D / 2, x3 = E / 2 + 1, x4 = (E + RW) / 2 + 1
; (D, E its first and last road pixel, RW the kerb's width: pass 1's), and
; on the light bands the centre line.
;
; A pair is written a word (4 pixels) at a time with PUSH, from the line's
; end down, once for each of its lines (CRun): the word each edge is in (a
; "special" word: two pens, or one if the edge is at the word's start: from
; CSpecial, by the band's class, the edge and its pixel in the word), and
; between them the runs of words (grass, kerb, road, kerb, grass), each an
; unrolled chain of 32 PUSHes entered at its length. Every step ends in a
; jump patched for the pair (its low byte: the program is in one page), so
; any step can be left out: the right kerb and grass where the road runs
; off the screen's edge, a kerb whose two edges share a word (that word is
; the inner edge's, the outer edge's pixels put right after: CFill). The
; specials are in the registers the runs don't use: BC', DE', HL' and IX.
;
; The road in one word (far away) and a fork's two roads go the slow way:
; grass across through the same program, then the road over it a byte at a
; time (CFill).
; ---------------------------------------------------------------------------

; Pens (docs/port_cpc.md 5.5)
ROAD_ROWS       EQU ROAD_LINES / 8   ; (12: rows 12-23)
PEN_ROAD        EQU 0
PEN_BLACK       EQU 1
PEN_KERB_L      EQU 2
PEN_KERB_D      EQU 3
PEN_GRASS_L     EQU 4
PEN_GRASS_D     EQU 5
PEN_SKY         EQU 6
PEN_PANO_F      EQU 7
PEN_PANO_N      EQU 8
PEN_WALL_L      EQU 9
PEN_WALL_D      EQU 10
PEN_LANE        EQU 2           ; (bright white, as the light kerb)
PEN_LAMP        EQU 12          ; (bright yellow)

; A pen in both pixels of a byte: its bits 0-3 in bits 7 and 6, 3 and 2,
; 5 and 4, 1 and 0 (the left pixel's the odd bits: two pens' bytes as one,
; the left pixel the first's, are (first & $AA) | (second & $55))

; The special words, page-aligned: per band class (x 32), edge (x 8: x1
; grass | kerb, x2 kerb | road, x3 road | kerb, x4 kerb | grass) and its
; pixel in the word (x 2), the word (its left byte first)
        MACRO SPEC4 l_, r_
        db r_, r_                       ; (the edge at the word's start)
        db ((l_) & $AA) | ((r_) & $55), r_              ; 1 pixel in
        db l_, r_                       ; 2
        db l_, ((l_) & $AA) | ((r_) & $55)              ; 3
        ENDM
        MACRO SPECCLS g_, k_
        SPEC4 g_, k_
        SPEC4 k_, 0
        SPEC4 0, k_
        SPEC4 k_, g_
        ENDM
        ALIGN 256
CSpecial:
        SPECCLS CLS0_G, CLS0_K
        SPECCLS CLS1_G, CLS1_K
        SPECCLS CLS2_G, CLS2_K
        SPECCLS CLS3_G, CLS3_K
PenByte:
pn      DEFL 0
        DUP 16
        db (((pn) & 1) * $C0) | ((((pn) >> 1) & 1) * $0C) | ((((pn) >> 2) & 1) * $30) | ((((pn) >> 3) & 1) * $03)
pn      DEFL pn + 1
        EDUP

; Per band class (Band's bits 7-6: a tunnel's, dark): the grass's (or a
; tunnel's walls') and the kerb's pens
CLS0_G  EQU (((PEN_GRASS_L) & 1) * $C0) | ((((PEN_GRASS_L) >> 1) & 1) * $0C) | ((((PEN_GRASS_L) >> 2) & 1) * $30) | ((((PEN_GRASS_L) >> 3) & 1) * $03)
CLS0_K  EQU (((PEN_KERB_L) & 1) * $C0) | ((((PEN_KERB_L) >> 1) & 1) * $0C) | ((((PEN_KERB_L) >> 2) & 1) * $30) | ((((PEN_KERB_L) >> 3) & 1) * $03)
CLS1_G  EQU (((PEN_GRASS_D) & 1) * $C0) | ((((PEN_GRASS_D) >> 1) & 1) * $0C) | ((((PEN_GRASS_D) >> 2) & 1) * $30) | ((((PEN_GRASS_D) >> 3) & 1) * $03)
CLS1_K  EQU (((PEN_KERB_D) & 1) * $C0) | ((((PEN_KERB_D) >> 1) & 1) * $0C) | ((((PEN_KERB_D) >> 2) & 1) * $30) | ((((PEN_KERB_D) >> 3) & 1) * $03)
CLS2_G  EQU (((PEN_WALL_L) & 1) * $C0) | ((((PEN_WALL_L) >> 1) & 1) * $0C) | ((((PEN_WALL_L) >> 2) & 1) * $30) | ((((PEN_WALL_L) >> 3) & 1) * $03)
CLS2_K  EQU (((PEN_KERB_L) & 1) * $C0) | ((((PEN_KERB_L) >> 1) & 1) * $0C) | ((((PEN_KERB_L) >> 2) & 1) * $30) | ((((PEN_KERB_L) >> 3) & 1) * $03)
CLS3_G  EQU (((PEN_WALL_D) & 1) * $C0) | ((((PEN_WALL_D) >> 1) & 1) * $0C) | ((((PEN_WALL_D) >> 2) & 1) * $30) | ((((PEN_WALL_D) >> 3) & 1) * $03)
CLS3_K  EQU (((PEN_BLACK) & 1) * $C0) | ((((PEN_BLACK) >> 1) & 1) * $0C) | ((((PEN_BLACK) >> 2) & 1) * $30) | ((((PEN_BLACK) >> 3) & 1) * $03)
CBandPens:
        db CLS0_G, CLS0_K, CLS1_G, CLS1_K, CLS2_G, CLS2_K, CLS3_G, CLS3_K
CLaneByte:
        db (((PEN_LANE) & 1) * $C0) | ((((PEN_LANE) >> 1) & 1) * $0C) | ((((PEN_LANE) >> 2) & 1) * $30) | ((((PEN_LANE) >> 3) & 1) * $03)
        ASSERT high CBandPens == high CLaneByte

        ALIGN 256
; The road's line pairs, page-aligned: each pair's two lines' ends in the
; hidden screen (from the road's top: 4 bytes a pair, at its first line's
; index x 2)
CPairEnds:
y       DEFL ROAD_Y0
        DUP ROAD_LINES / 2
        dw $4000 + (y & 7) * $800 + (y >> 3) * 64 + 64
        dw $4000 + (y & 7) * $800 + (y >> 3) * 64 + 64 + SCR_LINE
y       DEFL y + 2
        EDUP
        ASSERT high CPairEnds == high ($ - 1)

        ALIGN 256

; ---- the line program, in one page: SP the line's end; BC the grass word,
; DE the kerb's, HL the road's; BC', DE', HL', IX the special words at x4,
; x3, x2, x1; IY where it goes after. A run of n words is entered n PUSHes
; before its jump.
CRun:   jp CGL                  ; -> the first step
CGR:    DUP 32
        push bc
        EDUP
CGRj:   jp CS4
CS4:    exx
        push bc                 ; x4's word
        exx
CS4j:   jp CKRj
CKR:    DUP 32
        push de
        EDUP
CKRj:   jp CS3
CS3:    exx
        push de                 ; x3's
        exx
CS3j:   jp CRRj
CRR:    DUP 32
        push hl
        EDUP
CRRj:   jp CS2
CS2:    exx
        push hl                 ; x2's
        exx
CS2j:   jp CKLj
CKL:    DUP 32
        push de
        EDUP
CKLj:   jp CS1
CS1:    push ix                 ; x1's
CS1j:   jp CGLe
CGL:    DUP 32
        push bc
        EDUP
CGLe:   jp (iy)
        ASSERT high CRun == high CGLe

CSave:          dw 0            ; the stack, while SP fills
CI:             db 0            ; the pair's first line (pass 1's index)
CG:             db 0            ; its grass byte
CK:             db 0            ; its kerb byte
CDark:          db 0            ; its band's dark bit (no centre line)
CFixR:          db 0            ; x3, x4 in one word: x4's pixels put right after
CFixL:          db 0            ; x1, x2 in one word: x1's
CXs:            ds 4            ; its edges x1-x4

; The road into the hidden screen: row by row (a fork's two roads the slow
; way), a line pair at a time
CpcRoad:
        xor a
.row:   ld (CI), a
        rrca                    ; its row's fork (RowFork: both roads on it)
        rrca
        rrca
        ld c, a
        add a, low CRowFull     ; (a row the portal covers: not drawn,
        ld l, a                 ; src/cpc/reset.asm CpcPortalRows)
        ld h, high CRowFull
        ld a, (hl)
        or a
        jr nz, .covered
        ld a, c
        add a, low RowFork
        ld l, a
        ld h, high RowFork
        ld a, (hl)
        ld (.fk + 1), a
        ld a, c                 ; the far rows: 4 lines a step
        cp ROAD_QUAD_ROWS
        sbc a, a
        and 1
        ld (CQuad), a
        jr z, .pairs
        ld hl, CPl3         ; (the program's second line on to the third)
        ld (CIy2 + 2), hl
        ld hl, 0                ; (CFill: its two lines more)
        ld (CFill.q1), hl
        ld (CFill.q2), hl
        ld a, 4
        ld b, 2                 ; (two 4-line groups a row)
        jr .q
.pairs: ld hl, CPdone
        ld (CIy2 + 2), hl
        ld hl, CFILL_Q1         ; (CFill: the jumps past them)
        ld (CFill.q1), hl
        ld hl, CFILL_Q2
        ld (CFill.q2), hl
        ld a, 2
        ld b, 4
.q:     ld (.step + 1), a
.pair:  push bc
        call CPrep
.fk:    ld b, 0
        inc b
        dec b
        jr nz, .fork
        call CPair
        jr .next
.fork:  call CForkPair
.next:  ld hl, CI
.step:  ld a, 0                 ; (2 lines on, or 4)
        add a, (hl)
        ld (hl), a
        pop bc
        djnz .pair
        ld a, (CI)
        cp ROAD_LINES
        jr c, .row
        ret
.covered:
        ld a, (CI)
        add a, 8
        cp ROAD_LINES
        jr c, .row
        ret
CQuad:          db 0            ; this row's steps are 4 lines (ROAD_QUAD_ROWS)
        IFNDEF ROAD_QUAD_ROWS   ; the road's first rows set up a step of 4
ROAD_QUAD_ROWS  EQU 6           ; lines at a time (the far half: the road narrow
        ENDIF                   ; there), the rest line pairs (-D: 0-12)
CFILL_Q1        EQU $18 | ((CFill.n1 - CFill.q1 - 2) << 8)  ; (jr .n1)
CFILL_Q2        EQU $18 | ((CFill.n2 - CFill.q2 - 2) << 8)

; The pair (CI: its first line, pass 1's index, even): its lines' ends
; patched into the program's runs, its band's class (IXH x 32, CDark) and
; pens (CG, CK)
CPrep:  ld a, (CI)
        ld l, a
        add a, a                ; its lines' ends (CPairEnds: 4 bytes a pair)
        ld (CEnd1 + 2), a
        add a, 2
        ld (CEnd2 + 2), a
        add a, 2                ; (and the next pair's: 4 lines)
        ld (CEnd3 + 2), a
        add a, 2
        ld (CEnd4 + 2), a
        ld h, high Band
        set 7, l
        ld a, (hl)              ; its band's class (x 32)
        rrca
        and $60
        ld ixh, a
        ld (CDark), a
        rrca                    ; (x 2: its pens)
        rrca
        rrca
        rrca
        add a, low CBandPens
        ld c, a
        ld b, high CBandPens
        ld a, (bc)
        ld (CG), a
        inc c
        ld a, (bc)
        ld (CK), a
        ret

; The pair drawn (CPrep first)
CPair:  ld a, (CI)
        ld l, a
        set 7, l
        ld h, high SrcLine
        ld a, (hl)              ; the depth line shown: the kerb's width
        or $80
        ld c, a
        ld b, high RoadRW
        ld a, (bc)
        ld c, a                 ; C = RW
        ld h, high DEPage
        ld e, (hl)              ; E
        res 7, l
        ld d, (hl)              ; D
        ld a, e
        cp d
        jp c, CGrassPair        ; (no road)
        ; ---- the edges: E = x1, D = x2, L = x3, H = x4
        add a, c                ; x4 = (E + RW) / 2 + 1, at most 128
        jr nc, .x4
        ld a, 255
.x4:    srl a
        inc a
        ld h, a
        ld a, e                 ; x3 = E / 2 + 1
        srl a
        inc a
        ld l, a
        ld a, d                 ; x1 = (D - RW) / 2, at least 0
        sub c
        jr nc, .x1
        xor a
.x1:    srl a
        ld e, a
        srl d                   ; x2 = D / 2
        ld a, e                 ; (x1, x4 kept: the fixes, a tunnel's lamps)
        ld (CXs), a
        ld a, h
        ld (CXs + 3), a
        ; ---- the road's words: w2 < w3 (else the slow way)
        ld a, d
        srl a
        srl a
        ld b, a                 ; B = w2
        ld a, l
        srl a
        srl a
        ld c, a                 ; C = w3
        cp b
        jp z, CSlowPair
        ; ---- the right: GR 31 - w4 words, x4's, KR w4 - w3 - 1, x3's; or
        ; none of it (the road to the screen's edge); or from KR (the kerb
        ; to it); or GR then x3's (x3, x4 in one word)
        ld a, l
        cp 128
        jr nc, .noR
        ld a, h
        srl a
        srl a                   ; w4
        cp 32
        jr z, .edgeR
        cp c
        jr z, .sameR
        ld (.w4 + 1), a
        add a, low CGRj - 31
        ld (CRun + 1), a        ; start: GR
        ld a, low CS4
        ld (CGRj + 1), a        ; GR, then x4's
.w4:    ld a, 0
        neg
        add a, c                ; w3 - w4
        add a, low CKRj + 1
        ld (CS4j + 1), a        ; x4's, then KR
        ld a, low CS3
        ld (CKRj + 1), a        ; KR, then x3's
        jr .rr
.edgeR: ld a, c
        add a, low CKRj - 31
        ld (CRun + 1), a        ; start: KR
        ld a, low CS3
        ld (CKRj + 1), a
        jr .rr
.sameR: add a, low CGRj - 31
        ld (CRun + 1), a        ; start: GR
        ld a, low CS3
        ld (CGRj + 1), a        ; GR, then x3's
        ld a, h
        ld (CXs + 3), a
        ld (CFixR), a           ; (not 0: x4 > 0)
        jr .rr
.noR:   ld a, b                 ; start: RR (w2 + 1 .. 31)
        add a, low CRRj - 31
        ld (CRun + 1), a
        jr .left
.rr:    ld a, b                 ; RR: w3 - w2 - 1 words, after x3's
        sub c
        add a, low CRRj + 1
        ld (CS3j + 1), a
        ; ---- the left: x2's, KL w2 - w1 - 1 words, x1's, GL w1; or x2's
        ; alone (the road from the screen's edge); or x2's then GL (x1,
        ; x2 in one word)
.left:  ld a, low CS2
        ld (CRRj + 1), a        ; RR, then x2's
        ld a, d
        or a
        jr nz, .l1
        ld a, low CGLe          ; x2 = 0: x2's last
        ld (CS2j + 1), a
        jr .specials
.l1:    ld a, e
        srl a
        srl a
        ld c, a                 ; C = w1
        cp b
        jr z, .sameL
        sub b
        add a, low CKLj + 1
        ld (CS2j + 1), a        ; x2's, then KL
        ld a, low CS1
        ld (CKLj + 1), a        ; KL, then x1's
        ld a, low CGLe
        sub c
        ld (CS1j + 1), a        ; x1's, then GL
        jr .specials
.sameL: ld a, low CGLe
        sub c
        ld (CS2j + 1), a        ; x2's, then GL
        ld a, e
        ld (CXs), a
        inc a
        ld (CFixL), a           ; (not 0)
        ; ---- the special words: CSpecial + class + edge x 8 + pixel x 2
.specials:
        exx
        ld h, high CSpecial
        exx
        ld a, h
        and 3
        add a, a
        add a, ixh
        add a, 24
        exx
        ld l, a
        ld c, (hl)
        inc l
        ld b, (hl)              ; BC' = x4's
        exx
        ld a, l
        and 3
        add a, a
        add a, ixh
        add a, 16
        exx
        ld l, a
        ld e, (hl)
        inc l
        ld d, (hl)              ; DE' = x3's
        exx
        ld a, d
        and 3
        add a, a
        add a, ixh
        add a, 8
        exx
        ld l, a
        ld a, (hl)
        inc l
        ld h, (hl)
        ld l, a                 ; HL' = x2's
        exx
        ld a, e
        and 3
        add a, a
        add a, ixh
        ld l, a
        ld h, high CSpecial
        ld a, (hl)
        ld ixl, a
        inc l
        ld a, (hl)
        ld ixh, a               ; IX = x1's
        ; ---- both lines
        ld a, (CG)
        ld b, a
        ld c, a
        ld a, (CK)
        ld d, a
        ld e, a
        ld hl, 0                ; (the road: pen 0)
        ld (CSave), sp
        di
CEnd1:  ld sp, (CPairEnds)      ; (its low byte patched: the pair's)
        ld iy, CPl2
        jp CRun
CPl2:
CEnd2:  ld sp, (CPairEnds + 2)
CIy2:   ld iy, CPdone           ; (CPl3 for a step of 4 lines)
        jp CRun
CPl3:
CEnd3:  ld sp, (CPairEnds + 4)
        ld iy, CPl4
        jp CRun
CPl4:
CEnd4:  ld sp, (CPairEnds + 6)
        ld iy, CPdone
        jp CRun
CPdone: ld sp, (CSave)
        ei
        ; ---- an outer edge in its inner edge's word: its pixels put right
        ld a, (CFixR)
        or a
        jr z, .fl
        xor a
        ld (CFixR), a
        ld a, (CXs + 3)         ; [x4, its word's end) grass
        ld e, a
        or 3
        inc a
        ld d, a
        ld a, (CG)
        ld c, a
        call CFill
.fl:    ld a, (CFixL)
        or a
        jr z, CLamps
        xor a
        ld (CFixL), a
        ld a, (CXs)             ; [x1's word's start, x1) grass
        ld d, a
        and $FC
        ld e, a
        ld a, (CG)
        ld c, a
        call CFill
        ; ---- in a tunnel, its light bands: lamps on the walls beside the
        ; kerbs (a cell's width, as the Spectrum's)
CLamps: ld a, (CDark)
        cp $40                  ; (class 2: a tunnel's, light)
        jr nz, CLane
        ld a, (TunInside)
        or a
        jr z, CLane
        ld a, (CXs)             ; [x1 - 4, x1)
        ld d, a
        sub 4
        jr c, .r
        ld e, a
        ld a, (PenByte + PEN_LAMP)
        ld c, a
        call CFill
.r:     ld a, (CXs + 3)         ; [x4, x4 + 4)
        ld e, a
        add a, 4
        cp 129
        jr nc, CLane
        ld d, a
        ld a, (PenByte + PEN_LAMP)
        ld c, a
        call CFill
        ; ---- the centre line (light bands only)
CLane:  ld a, (CDark)
        and $20
        ret nz
        ld a, (CI)
        ld l, a
        ld h, high LaneX
        ld a, (hl)
        cp $FF
        ret z
        ld e, a                 ; its first pixel (the Spectrum's)
        set 7, l
        ld h, high SrcLine
        ld a, (hl)
        or $80
        ld l, a
        ld h, high LaneW
        ld a, (hl)              ; its half-width: 2 x that the Spectrum's
        or a                    ; pixels wide, that many Mode 0 pixels
        ret z
        ld d, a
        ld a, e
        srl a
        ld e, a                 ; from Mode 0 pixel E
        add a, d
        ld d, a                 ; to D
        ld a, (CLaneByte)
        ld c, a
        jp CFill

; A pair with no road: grass across
CGrassPair:
; The pair grass across through the program: GL, all its 32 words
CGrassFill:
        ld a, low CGL
        ld (CRun + 1), a
        ld a, (CG)
        ld b, a
        ld c, a
        ld (CSave), sp
        di
        ld a, (CEnd1 + 2)       ; (the pair's ends' entry)
        ld l, a
        ld h, high CPairEnds
        ld e, (hl)
        inc l
        ld d, (hl)
        inc l
        ex de, hl
        ld sp, hl
        ld iy, .l2
        jp CRun
.l2:    ex de, hl
        ld e, (hl)
        inc l
        ld d, (hl)
        inc l
        ex de, hl
        ld sp, hl
        ld a, (CQuad)           ; (a step of 4 lines: two more)
        or a
        jr z, .last
        ld iy, .l3
        jp CRun
.l3:    ex de, hl
        ld e, (hl)
        inc l
        ld d, (hl)
        inc l
        ex de, hl
        ld sp, hl
        ld iy, .l4
        jp CRun
.l4:    ex de, hl
        ld e, (hl)
        inc l
        ld d, (hl)
        ex de, hl
        ld sp, hl
.last:  ld iy, .done
        jp CRun
.done:  ld sp, (CSave)
        ei
        ret

; The slow way (the road in one word): grass across, then the kerbs and
; the road over it (H = x4, L = x3, D = x2, E = x1)
CSlowPair:
        push hl
        push de
        call CGrassFill
        pop de
        pop hl
        push hl
        push de
        ld a, (CK)              ; the kerbs: [x1, x4)
        ld c, a
        ld d, h
        call CFill
        pop de                  ; the road: [x2, x3)
        pop hl
        ld e, d
        ld d, l
        ld c, 0
        call CFill
        jp CLane

; A fork's pair: grass across, then each road (pass 1's D, E and its
; second road's D2, E2) over it
CForkPair:
        call CGrassFill
        ld a, (CI)
        ld l, a
        ld h, high DEPage
        ld e, (hl)              ; D
        set 7, l
        ld d, (hl)              ; E
        call CForkRoad
        ld a, (CI)
        ld l, a
        ld h, high DE2Page
        ld e, (hl)              ; D2
        set 7, l
        ld d, (hl)              ; E2
; E = a road's first pixel, D = its last (the Spectrum's): its kerbs and
; road over the pair
CForkRoad:
        ld a, d
        cp e
        ret c
        push de
        ld a, (CI)              ; its kerb's width
        or $80
        ld l, a
        ld h, high SrcLine
        ld a, (hl)
        or $80
        ld l, a
        ld h, high RoadRW
        ld c, (hl)
        pop de
        ld a, e                 ; the kerbs: [(D - RW) / 2, (E + RW) / 2 + 1)
        sub c
        jr nc, .a
        xor a
.a:     srl a
        ld l, a
        ld a, d
        add a, c
        jr nc, .b
        ld a, 255
.b:     srl a
        inc a
        push de
        ld d, a
        ld e, l
        ld a, (CK)
        ld c, a
        call CFill
        pop de
        ld a, e                 ; the road: [D / 2, E / 2 + 1)
        srl a
        ld e, a
        ld a, d
        srl a
        inc a
        ld d, a
        ld c, 0
        ; (on to CFill)

; [E, D) Mode 0 pixels of both lines of the pair (CEnd1's) in the pen whose
; byte is C
CFill:  ld a, (CEnd1 + 2)       ; (the pair's first line: its end - 64)
        ld l, a
        ld h, high CPairEnds
        ld a, (hl)
        sub 64
        ld b, a
        inc l
        ld a, (hl)
        sbc a, 0
        ld h, a
.px:    ld a, e
        cp d
        ret nc
        bit 0, e                ; a pixel at a time to a byte's start
        jr nz, .odd
        ld a, d
        sub e
        cp 2
        jr c, .odd
        ld a, e                 ; a whole byte
        srl a
        add a, b
        ld l, a
        ld (hl), c
        set 3, h
        ld (hl), c
.q1:    jr .n1                  ; (nop, nop: a step of 4 lines)
        set 4, h
        ld (hl), c
        res 3, h
        ld (hl), c
        res 4, h
.n1:    res 3, h
        inc e
        inc e
        jr .px
.odd:   ld a, e
        srl a
        add a, b
        ld l, a
        bit 0, e
        ld a, c
        jr nz, .right
        and $AA
        ld (.m + 1), a
        ld a, (hl)
        and $55
        jr .w
.right: and $55
        ld (.m + 1), a
        ld a, (hl)
        and $AA
.w:
.m:     or 0
        ld (hl), a
        set 3, h
        ld (hl), a
.q2:    jr .n2                  ; (nop, nop: a step of 4 lines)
        set 4, h
        ld (hl), a
        res 3, h
        ld (hl), a
        res 4, h
.n2:    res 3, h
        inc e
        jr .px
