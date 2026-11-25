; ---------------------------------------------------------------------------
; CPC: traffic, scenery and the car (docs/port_cpc.md 5.6)
;
; The shared code projects and clips the objects as ever (src/scenery.asm,
; its CPC way: columns in Mode 0 bytes, 64 a line) and writes their draw
; commands (8 bytes: y top, column, bytes a line drawn, bytes a line
; skipped, the data, its height, its type). They are drawn here from the
; list, far to near (by their bottom line), each masked by pen 0 through a
; table (pen 0: transparent): nothing in the road needs erasing, the road
; is drawn again each frame. Where one reaches the sky or the panorama
; (rows 0-11), that screen's cells there are converted again, or its
; panorama drawn again, the next time it is drawn. Then the car, last.
; ---------------------------------------------------------------------------

SprPx:          db 0            ; (src/scenery.asm) the object's width in pixels
COrder:         ds MAX_SPR * 2, 0   ; the commands, far to near: their addresses

; Traffic and scenery from the command list, then the car
CpcObjects:
        ld hl, (CmdList)
        ld a, (hl)
        or a
        jp z, CpcCar
        ld b, a
        ld c, a                 ; (C: how many)
        inc hl
        ld de, COrder           ; their addresses, then sorted by bottom
.a:     ld a, l
        ld (de), a
        inc de
        ld a, h
        ld (de), a
        inc de
        push bc
        ld bc, CMD_SIZE
        add hl, bc
        pop bc
        djnz .a
        ld a, c
        ld (.n + 1), a
        call CSort
.n:     ld b, 0
        ld hl, COrder
.d:     push bc
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        push hl
        call CDrawCmd
        pop hl
        pop bc
        djnz .d
        jp CpcCar

; COrder's C commands sorted by bottom line (y top + height), lowest
; first: an insertion sort (fourteen at most)
CSort:  ld a, c
        cp 2
        ret c
        ld ix, COrder + 2       ; IX -> the next to place
        dec c
.next:  push bc
        ld e, (ix + 0)          ; its address and its bottom
        ld d, (ix + 1)
        call CBottom
        ld c, a
        push ix
        pop hl                  ; HL -> where it is: shift the ones before
.back:  ld a, l                 ; it with a lower bottom up
        cp low COrder
        jr nz, .cmp
        ld a, h
        cp high COrder
        jr z, .put
.cmp:   dec hl
        ld a, (hl)
        dec hl
        push de
        ld e, (hl)
        ld d, a
        push hl
        call CBottom
        pop hl
        pop de
        cp c
        jr c, .put2             ; (lower than its own: it goes after)
        jr z, .put2
        ld a, (hl)              ; moved up one
        inc hl
        inc hl
        ld (hl), a
        dec hl
        ld a, (hl)
        inc hl
        inc hl
        ld (hl), a
        dec hl
        dec hl
        dec hl
        jr .back
.put2:  inc hl
        inc hl
.put:   ld (hl), e
        inc hl
        ld (hl), d
        inc ix
        inc ix
        pop bc
        dec c
        jr nz, .next
        ret

; DE -> a command: A = its bottom line (y top + height). HL used.
CBottom:
        ld a, (de)
        ld h, d
        ld l, e
        inc hl
        inc hl
        inc hl
        inc hl
        inc hl
        inc hl
        add a, (hl)
        ret

; DE -> a command: drawn into the hidden screen, masked by pen 0
CDrawCmd:
        ex de, hl
        ld a, (hl)              ; y top
        ld (CY), a
        inc hl
        ld c, (hl)              ; column
        ld a, c
        ld (CCol), a
        inc hl
        ld a, (hl)              ; bytes a line
        ld (.w + 1), a
        ld (CW), a
        inc hl
        ld a, (hl)              ; skipped a line
        ld (.sk + 1), a
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)              ; DE = the data
        inc hl
        ld a, (hl)              ; height
        ld (CHt), a
        ld ixh, a
        ; the first line's address: $4000 + (y & 7) x $800 + (y / 8) x 64 + column
        ld a, (CY)
        ld b, a
        and 7
        add a, a
        add a, a
        add a, a
        add a, high SCR
        ld h, a
        ld a, b
        and $F8
        rrca
        rrca
        rrca                    ; the row
        rrca
        rrca                    ; x 64: its low byte's top bits, high's low
        ld l, a
        and 7
        add a, h
        ld h, a
        ld a, l
        and $C0
        add a, c
        ld l, a
        ld b, high CMaskTab
.ln:    push hl
.w:     ld a, 0
        ld ixl, a
.px:    ld a, (de)
        inc de
        or a
        jr z, .t                ; (all pen 0)
        ld c, a
        ld a, (bc)
        and (hl)
        or c
        ld (hl), a
.t:     inc l
        dec ixl
        jr nz, .px
        pop hl
.sk:    ld a, 0                 ; (the bytes skipped)
        add a, e
        ld e, a
        jr nc, .nl
        inc d
.nl:    ld a, h                 ; the next line: $800 on, or past the 8th
        add a, high SCR_LINE    ; line the next row's
        ld h, a
        cp high (SCR + 8 * SCR_LINE)
        jr c, .nr
        sub high (8 * SCR_LINE)
        ld h, a
        ld a, l
        add a, SCR_ROW
        ld l, a
        jr nc, .nr
        inc h
.nr:    dec ixh
        jr nz, .ln
        ; ---- over the sky or the panorama: that screen's cells there
        ; converted again, its panorama drawn again, next time
        ld a, (CY)
        cp ROAD_Y0
        ret nc
        rrca                    ; its rows: y top / 8 ..
        rrca
        rrca
        and 31
        ld b, a
        ld a, (CY)
        ld hl, CHt
        add a, (hl)
        dec a
        rrca                    ; .. (y top + height - 1) / 8, at most 11
        rrca
        rrca
        and 31
        cp ROAD_ROW0
        jr c, .r1
        ld a, ROAD_ROW0 - 1
.r1:    ld (.last + 1), a
        cp PANO_ROW0            ; the panorama's rows: drawn again next time
        jr c, .cells
        ld hl, CPanoA
        ld a, (CpcHidden)
        add a, l
        ld l, a
        ld (hl), $FF
.cells: ld a, (CW)              ; its cells: column / 2 .. (column + w - 1) / 2
        ld hl, CCol
        add a, (hl)
        dec a
        srl a
        ld e, a
        ld a, (hl)
        srl a
        ld d, a
.row:   ld a, b
        cp PANO_ROW0            ; (the sky's rows only)
        ret nc
.last:  cp 0
        ret z
        ret nc
        ld c, d
.col:   call CpcMarkHid
        ld a, c
        cp e
        jr nc, .nextr
        inc c
        jr .col
.nextr: inc b
        jr .row

CY:             db 0
CW:             db 0
CHt:            db 0
CCol:           db 0

; The car: its pose (CarFrame, src/car.asm) masked over the road, at the
; screen's bottom middle
CpcCar:
        call CarFrame           ; C = its pose (0-6)
        ld a, c                 ; (3-6: smoke, spinning: the squeal)
        cp 3
        sbc a, a
        cpl
        ld (Squeal), a
        ld a, c                 ; a new pose: its lines' jumps
        ld hl, CCarLast
        cp (hl)
        call nz, CCarPatch
        ld bc, CAR_BC           ; (its commonest bytes, as the code expects)
        ld de, CAR_DE
CCarGo: jp CCarDone             ; (patched: the pose's first line)
CCarDone:
        ret

; A = the pose (HL = CCarLast): each of its lines' jump to its next line
; (build/cpc/cpc_car.asm: tools/cpc_art.py car_code)
CCarPatch:
        ld (hl), a
        ld l, a                 ; HL = its lines' numbers
        ld h, 0
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        add hl, hl
        ld de, CCarPoses
        add hl, de
        ld de, CCarGo + 1       ; the jump to point at the next line
        ld b, CARH_M0
.ln:    push bc
        ld a, (hl)
        inc hl
        push hl
        ld l, a                 ; its entry: its code, its jump's operand
        ld h, 0
        add hl, hl
        add hl, hl
        ld bc, CCarLines
        add hl, bc
        ld c, (hl)
        inc hl
        ld b, (hl)
        inc hl
        ex de, hl
        ld (hl), c
        inc hl
        ld (hl), b
        ex de, hl
        ld e, (hl)
        inc hl
        ld d, (hl)
        pop hl
        pop bc
        djnz .ln
        ex de, hl               ; the last line's: back
        ld (hl), low CCarDone
        inc hl
        ld (hl), high CCarDone
        ret
CCarLast:       db $FF          ; the pose the jumps are set for

; Per sprite byte: the screen's pixels it leaves (its pen 0 pixels'), page-
; aligned
        ALIGN 256
CMaskTab:
bv      DEFL 0
        DUP 256
        db ((1 - (((bv >> 7) | (bv >> 5) | (bv >> 3) | (bv >> 1)) & 1)) * $AA) | ((1 - (((bv >> 6) | (bv >> 4) | (bv >> 2) | bv) & 1)) * $55)
bv      DEFL bv + 1
        EDUP

; A = n (0-64): n bytes from (HL) to (DE), both on past them (an unrolled
; LDI chain: 4 us a byte, LDIR's 6). BC spent.
LdiN:   or a
        ret z
        add a, a
        neg
        add a, low LdiEnd
        ld (.j + 1), a
.j:     jp LdiEnd               ; (its low byte patched: LdiEnd - 2n)
LdiChain:
        DUP 64
        ldi
        EDUP
LdiEnd: ret
        ASSERT high LdiChain == high LdiEnd
