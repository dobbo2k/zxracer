; ---------------------------------------------------------------------------
; Tunnels (the alpine stages: the track pack's header gives a tunnel's start
; and end, 0: none). Each game frame: which road lines are in the tunnel -
; RoadBands flags them (bit 7 of the band) and RowAttrs gives those rows the
; tunnel's walls and kerbs - and whether the car is in it: then the sky is
; its ceiling and the backdrop is not drawn.
; ---------------------------------------------------------------------------
TunWall:        db $48, $08         ; walls: bright blue, blue (light / dark bands)
TunKerbs:       db $70, $00         ; kerbs: bright yellow, black
TunSky:         db C_, C_           ; the ceiling (white ink: the message line; the backdrop is cleared)

; ---------------------------------------------------------------------------
; After the road, on the screen being drawn: the tunnel's mouth ahead - a
; rock face, a white arch round the road, dark inside - or, in it, the way
; out: the sky round the far road, dark around it. Painted in attributes
; from the line where the road meets the tunnel (its edges size the
; opening); road rows it paints are marked so the road redraws them later.
; ---------------------------------------------------------------------------
F_              EQU $09             ; the mountain face: blue rock (blue ink too: the
                                    ; backdrop's pixels underneath must not show)
A_              EQU $76             ; the arch: bright yellow, yellow ink (white would be lost in the snow)
D_              EQU $00             ; dark
S_              EQU $FF             ; (left as it is)
C_              EQU $07             ; the ceiling: black, white ink

DrawPortal:
        ld a, (TunJN)
        or a
        ret z
        ld a, (TunInside)
        or a
        ld hl, Band + ROAD_LINES - 2
        ld bc, (low Band - 2) * 256 + $FE    ; the mouth: the nearest line in it
        jr z, .scan
        ld l, low Band
        ld bc, (low Band + ROAD_LINES) * 256 + 2   ; the way out: the furthest
.scan:  bit 7, (hl)
        jr nz, .found
        ld a, l
        add a, c
        ld l, a
        cp b
        jr nz, .scan
        ret
.found: ld a, l
        sub low Band
        ld l, a
        add a, ROAD_ROW0 * 8
        ld (PtY), a             ; its screen line
        ld h, high DEPage
        ld d, (hl)              ; the road's edges there
        set 7, l
        ld e, (hl)
        ld a, e
        sub d
        ret c
        ld b, a                 ; B = width
        rrca
        rrca
        and $3F
        ld c, a                 ; C = the walls: a quarter of it
        ld a, d
        sub c
        jr nc, .c0
        xor a
.c0:    call Cell
        ld d, a                 ; D = the opening's first column
        ld a, e
        add a, c
        jr nc, .c1
        sbc a, a
.c1:    call Cell
        ld e, a                 ; E = its last
        ; the row's runs: [0, a0) [a0, D) [D, E] (E, a1] (a1, 32)
        ld hl, PtN
        ld a, d
        or a
        jr z, .a0
        dec a
.a0:    ld (hl), a
        inc hl
        cpl
        add a, d
        inc a
        ld (hl), a
        inc hl
        ld a, e
        sub d
        inc a
        ld (hl), a
        inc hl
        ld a, e
        cp 31
        ld a, 0
        adc a, a
        ld (hl), a
        inc hl
        add a, e
        cpl
        add a, 32
        ld (hl), a
        ; its height: three quarters of its width
        ld a, b
        srl a
        ld c, a
        srl a
        add a, c
        ld c, a
        ld a, (PtY)
        call Cell
        cp CAR_ROW
        jr c, .rm
        ld a, CAR_ROW
.rm:    ld (PtRow), a           ; rows down to the road's (not the car's)
        ld a, (PtY)
        sub c
        jr c, .t0
        cp 4 * 8
        jr nc, .t1
.t0:    ld a, 4 * 8
.t1:    call Cell
        ld (PtTop), a           ; the opening's top row (the arch above it)
        ld b, a
        ld a, (THEME_CACHE + 6) ; the way out: the theme's sky, its ink hidden
        and $F8
        ld c, a
        rrca
        rrca
        rrca
        and 7
        or c
        ld (PatOut + 2), a
        ld a, (TunInside)
        or a
        ld a, 3
        jr nz, .row             ; (the way out: the whole ceiling, as the opening moves)
        ld a, (PtRow)           ; the mouth: its face half as high again
        sub b
        srl a
        cpl
        add a, b
        cp 3
        jr nc, .row
        ld a, 3
.row:   ld (PtR), a
        ld hl, PtRow
        cp (hl)
        ret nc
        call PortalRow
        ld a, (PtR)
        inc a
        jr .row

; A -> A / 8
Cell:   rrca
        rrca
        rrca
        and 31
        ret

; A = row: its five runs in the colours of its kind
PortalRow:
        ld c, a
        ld l, a
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld a, (AttrHi)
        add a, h
        ld h, a
        ld a, c
        sub ROAD_ROW0
        jr c, .kind
        push hl                 ; a road row: mark it to be redrawn
        or $80
        ld l, a
        ld a, (StatePage)
        add a, 2
        ld h, a
        ld (hl), 1
        pop hl
.kind:  ld de, PatFace
        ld a, (PtTop)
        dec a
        cp c
        jr c, .opening
        ld a, (TunInside)       ; above the opening: the way out's ceiling, or ...
        or a
        jr z, .fa
        ld de, PatCeil
        jr .go
.fa:    ld a, (PtTop)           ; ... the mouth's face and the arch's row
        dec a
        cp c
        jr nz, .go
        ld de, PatArch
        jr .go
.opening:
        ld de, PatSky
        ld a, c
        cp ROAD_ROW0
        jr c, .op
        ld de, PatRoad
.op:    ld a, (TunInside)
        or a
        jr z, .go
        ld a, e                 ; (the way out's)
        add a, PatOut - PatSky
        ld e, a
        adc a, d
        sub e
        ld d, a
.go:    push ix
        ld ix, PtN
        ld b, 5
.run:   push bc
        ld c, (ix + 0)
        inc ix
        ld a, (de)
        inc de
        cp S_
        jr z, .skip
        ld b, c
        call FillA
        jr .next
.skip:  ld a, l
        add a, c
        ld l, a
.next:  pop bc
        djnz .run
        pop ix
        ret

PatFace:        db F_, F_, F_, F_, F_
PatArch:        db F_, A_, A_, A_, F_
PatSky:         db F_, A_, D_, A_, F_
PatRoad:        db F_, A_, S_, A_, F_
PatOut:         db C_, C_, 0, C_, C_    ; (the sky, set per frame)
                db D_, D_, S_, D_, D_
PatCeil:        db C_, C_, C_, C_, C_   ; (the way out: above the opening)
PtN:            ds 5
PtY:            db 0
PtRow:          db 0
PtTop:          db 0
PtR:            db 0
