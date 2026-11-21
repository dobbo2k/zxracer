; ---------------------------------------------------------------------------
; Tunnels (the alpine stages: the track pack's header gives a tunnel's start
; and end, 0: none). Each game frame: which road lines are in the tunnel -
; RoadBands flags them (bit 7 of the band) and RowAttrs gives those rows the
; tunnel's walls and kerbs - and whether the car is in it: then the sky is
; its ceiling and the backdrop is not drawn.
; ---------------------------------------------------------------------------

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
ARCH_MIN        EQU 24              ; the road's width (pixels) at the mouth from which the arch shows
EXIT_SEE        EQU 1024            ; the way out shows from this near (src/holes.asm UpdateTunnel):
                                    ; further, the tunnel goes on into the dark
C_              EQU $07             ; the ceiling: black, white ink

DrawPortal:
        xor a
        ld (PtGate), a
        ld a, (TunJN)
        or a
        jp z, Gate              ; (no tunnel in view: perhaps a gantry, src/tunnelb2.asm)
        ld a, (TunInside)
        or a
        ld hl, Band + ROAD_LINES - 2
        ld bc, (low Band - 2) * 256 + $FE    ; the mouth: the nearest line in it
        jr z, .scan
        ld a, (TunJ0)           ; in it: the way out not in sight yet?
        or a
        ret z
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
.atLine:                        ; (A = the screen line; Gate comes in here)
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
        ; far away (the road narrow there): no arch yet - its cells are face
        ld a, b
        cp ARCH_MIN
        sbc a, a
        ld (PtFar), a
        jr z, .h
        ld hl, PtN
        ld a, (hl)              ; [0, a0) takes in [a0, C0) ...
        inc hl
        add a, (hl)
        ld (hl), 0
        dec hl
        ld (hl), a
        ld hl, PtN + 3
        ld a, (hl)              ; ... and (a1, 32) takes in (C1, a1]
        ld (hl), 0
        inc hl
        add a, (hl)
        ld (hl), a
.h:     ; its height: three quarters of its width
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
        ld a, (PtGate)          ; a gantry: its beam (two rows when it is wide), then the posts
        or a
        jr z, .tun
        ld a, (PtN + 2)
        cp 10
        ld a, b
        jr c, .b1
        dec a
.b1:    dec a
        cp 3
        jr nc, .row
        ld a, 3
        jr .row
.tun:   ld a, (TunInside)
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
        call Chequer            ; (a gantry's beam)
        ld a, (PtR)
        inc a
        jr .row

; A = row: its five runs in the colours of its kind
PortalRow:
        ld c, a
        call RowAttrHL
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
.kind:  ld a, (PtGate)
        or a
        jp nz, GateKind         ; (src/tunnelb2.asm)
        ld de, PatFace
        ld a, (PtTop)
        dec a
        cp c
        jr c, .opening
        ld a, (TunInside)       ; above the opening: the way out's ceiling, or ...
        or a
        jr z, .fa
        ld de, PatCeil
        jr .go
.fa:    ld a, (PtFar)           ; ... the mouth's face and the arch's row
        or a
        jr nz, .go              ; (no arch from far away)
        ld a, (PtTop)
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


; ---------------------------------------------------------------------------
; Engine sound mode, no beep on C (EngineSounds): in a tunnel the engine
; booms - C plays it again a little off its pitch and quieter, beating
; against it like an echo off the walls. (With music on, A, B and C are all
; the music's.)
TunEcho:
        ld a, (TunInside)
        or a
        ld e, %00101110         ; out of one: tone A, noise B
        jp z, EngineSounds.mw
        ld hl, (EnginePeriod)
        inc hl
        inc hl
        inc hl
        ld e, l
        ld a, 4
        call AyWrite
        ld e, h
        ld a, 5
        call AyWrite
        ld e, 9
        ld a, 10
        call AyWrite
        ld e, %00101010         ; tone A and C, noise B
        jp EngineSounds.mw
