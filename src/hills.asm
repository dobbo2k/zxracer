; ---------------------------------------------------------------------------
; Hills
;
; A segment's hill value bends the road vertically, the way its curvature
; bends it sideways: going up the depth lines from the car, the hill value
; (weighted by depth zone, like curves) is added to a vertical speed and
; that to a vertical offset, so depth line j lands on screen line
; s = j - offset. Positive hills lift the road ahead (a climb), negative ones
; drop it away (a crest).
;
; The road is drawn on screen lines, so each depth line pair is copied onto
; the screen line pairs it covers: a rising stretch covers several, and a
; stretch that falls behind nearer road (beyond a crest) covers none. Screen
; pairs above the furthest visible road are ground without road.
;
; HillMap works this out before pass 1, per odd depth line j:
;   ProjClip + j        screen line it lands on (its scenery stands there;
;                       0: at or above the top, scenery not drawn)
;   ProjClip + j - 1    $80 + number of screen pairs it covers (in view), or
;                       the first screen line of the road in front of it
;                       (hidden: its scenery is cut off there)
; and pass 1 stores each line through HillStore, which also fills
;   SrcLine[screen line]   depth line it shows (kerb width, centre line
;                          width, light/dark band).
; Without hills in view these are identities and pass 1 stores directly.
; ---------------------------------------------------------------------------

; Before pass 1, with hills in view. IY walks ProjClip + j, IXL = screen
; pairs still free above the road drawn so far, HL = vertical offset,
; DE = vertical speed (8.8 screen lines), BC = hill increment.
HillMap:
        ld hl, CurveList + 2    ; hill boundaries: (line, curvature, hill)
        ld (HmPtr), hl
        ld a, (hl)
        add a, low ProjClip
        ld (.nb + 1), a
        ld a, (CurveList + 1)
        ld (HillC), a
        ld hl, ZoneLines
        ld (HmZone), hl
        ld a, (hl)
        add a, low ProjClip
        ld (.nz + 1), a
        xor a
        ld (HmK), a
        ld ixl, ROAD_LINES / 2
        ld iy, ProjClip + ROAD_LINES - 1
        ld a, low ProjClip + ROAD_LINES - 1
        ld (HillTopJ), a
        ; flat from the car to the first boundary: depth line = screen line
        ld a, (HillC)
        or a
        jr nz, .weighed
        ld a, (CurveList + 2)   ; first boundary (lines nearer stay put)
        add a, 2
        ld c, a
        cp ROAD_LINES
        jr nc, .weighed
        ld hl, ProjClip + ROAD_LINES - 1
        ld a, ROAD_LINES - 1
.id:    ld (hl), a
        dec l
        ld (hl), $81
        dec l
        cp c
        jr z, .idEnd
        sub 2
        jr .id
.idEnd: add a, low ProjClip      ; last line done (the next is c - 2)
        ld (HillTopJ), a
        sub 2
        ld iyl, a
        ld a, c
        srl a
        ld ixl, a               ; pairs above line c - 1 are still free
        ld hl, (HmZone)         ; zones passed on the way
.zp:    ld a, (hl)
        cp $FF
        jr z, .zDone
        cp c
        jr c, .zDone
        inc hl
        ld a, (HmK)
        inc a
        ld (HmK), a
        jr .zp
.zDone: ld (HmZone), hl
        add a, low ProjClip
        ld (.nz + 1), a
.weighed:
        call .weigh             ; BC = hill increment
        ld hl, 0
        ld d, h
        ld e, l
.lp:    ld a, iyl
.nb:    cp $FF
        call z, .bound
        ld a, iyl
.nz:    cp $FF
        call z, .zone
        ex de, hl
        add hl, bc              ; speed += hill
        ex de, hl
        or a
        adc hl, de              ; offset += speed
        jp pe, .sat
.ok:    ; s = j - round(offset)
        ld a, l
        add a, $80              ; carry: round up
        ld a, iyl
        bit 7, h
        jr nz, .down
        sbc a, h                ; rising: maybe above the top
        sub low ProjClip
        jp p, .s
        xor a
        jr .s
.down:  sbc a, h                ; falling away: below (< 224)
        sub low ProjClip
        cp 128
        jr c, .s
        ld a, 127
.s:     ld (iy + 0), a
        srl a                   ; screen pair
        cp ixl
        jr nc, .hidden          ; behind the road in front
        ld ixh, a
        cpl
        add a, ixl
        inc a                   ; pairs it covers: up to the road in front
        or $80
        ld (iy - 1), a
        ld a, ixh
        ld ixl, a
        ld a, iyl
        ld (HillTopJ), a        ; (low ProjClip + j)
        jr .next
.hidden:
        ld a, ixl
        add a, a
        ld (iy - 1), a          ; its scenery is cut off at the road in front
.next:  ld a, iyl
        sub 2
        ld iyl, a
        cp low ProjClip
        jp nc, .lp

        ; screen pairs above the furthest road: ground without road
        ld a, (HillTopJ)
        sub low ProjClip
        ld (HillTopJ), a
        ld a, ixl
        ld (HillNf), a
        or a
        ret z
        ld b, a
        ld a, (HillTopJ)
        ld c, a
        ld l, 0
.e:     ld h, high DEPage
        ld (hl), $FF
        inc l
        ld (hl), $FF
        set 7, l
        ld (hl), 0
        dec l
        ld (hl), 0
        ld h, high DE2Page
        ld (hl), 0
        inc l
        ld (hl), 0
        ld h, high SrcLine
        ld (hl), c
        dec l
        ld (hl), c
        res 7, l
        ld h, high DE2Page
        ld (hl), $FF
        inc l
        ld (hl), $FF
        ld h, high LXPage
        ld (hl), $FF
        dec l
        ld (hl), $FF
        inc l
        inc l
        djnz .e
        ret

.sat:   ld hl, $7FFF
        bit 7, d
        jp z, .ok
        ld hl, $8000
        jp .ok

.bound: ; reached a segment boundary: its hill (more on the same line?)
        push hl
        ld hl, (HmPtr)
.b1:    inc hl
        inc hl
        ld a, (hl)
        ld (HillC), a
        inc hl
        ld a, (hl)              ; next boundary line
        add a, low ProjClip
        ld (.nb + 1), a
        cp iyl
        jr z, .b1
        ld (HmPtr), hl
        pop hl
        jr .weigh
.zone:  ; next depth zone: double the weight
        push hl
        ld hl, HmK
        inc (hl)
        ld hl, (HmZone)
        inc hl
        ld (HmZone), hl
        ld a, (hl)
        add a, low ProjClip
        ld (.nz + 1), a
        pop hl
.weigh: ; BC = hill << zone, in 1/256 screen lines per line pair
        push hl
        ld a, (HillC)
        ld l, a
        rlca
        sbc a, a
        ld h, a
        ld a, (HmK)
        or a
        jr z, .w1
        ld b, a
.w0:    add hl, hl
        djnz .w0
.w1:    ld b, h
        ld c, l
        pop hl
        ret

; Pass 1 store with hills in view. Alternate set active: L = odd depth line
; j, D, E = road edges, C = centre line x: copy them onto the screen pairs
; the line covers. Ends at RoadPass1.stored, L kept.
HillStore:
        ld a, l
        ld (.j + 1), a
        add a, low ProjClip
        ld l, a
        ld h, high ProjClip
        ld a, (hl)              ; screen line
        dec l
        bit 7, (hl)
        jr z, .j                ; hidden
        ld b, (hl)
        res 7, b                ; pairs
        and $FE
        ld l, a                 ; first screen line
        ld a, (.j + 1)
.pp:    ld h, high DEPage
        ld (hl), d
        inc l
        ld (hl), d
        set 7, l
        ld (hl), e
        dec l
        ld (hl), e
        ld h, high SrcLine
        ld (hl), a
        inc l
        ld (hl), a
        res 7, l
        ld h, high LXPage
        ld (hl), c
        dec l
        ld (hl), c
.hf:    jr .nf                  ; (patched: 0 with a fork in view)
        call ForkPair
.nf:    inc l
        inc l
        djnz .pp
.j:     ld l, 0
        jp RoadPass1.stored

; Hills out of view: one screen line per depth line again.
HillReset:
        ld hl, SrcLine
        xor a
.s:     ld (hl), a
        inc l
        inc a
        cp ROAD_LINES
        jr nz, .s
        ld hl, ProjClip
        ld a, 1
        ld b, ROAD_LINES / 2
.p:     ld (hl), $81            ; one pair
        inc l
        ld (hl), a
        inc l
        add a, 2
        djnz .p
        ret
