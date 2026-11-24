; ---------------------------------------------------------------------------
; Track: segments of (length, curve) from build/track.asm, looping.
;
; SegPtr / SegStart track the segment under the player. Each frame
; BuildCurveList turns the segments ahead into a list of the screen lines
; where the curvature changes, which RoadPass1 walks from the bottom line up.
; ---------------------------------------------------------------------------
MAX_BOUNDS      EQU 8               ; curvature / hill changes considered per frame
Z_FAR           EQU 12288           ; depth of the horizon line (ZLo/ZHi[0])

; Advance SegPtr / SegStart so that SegStart <= Pos < SegStart + length.
UpdateTrack:
        ld hl, (SegPtr)
        ld e, (hl)
        inc hl
        ld d, (hl)              ; DE = length
        inc hl
        ld a, (hl)
        ld (SegCurve), a
        ld hl, (Pos)
        ld bc, (SegStart)
        or a
        sbc hl, bc              ; distance into the segment
        or a
        sbc hl, de
        ret c                   ; still inside
        ld hl, (SegStart)
        add hl, de
        ld (SegStart), hl
        ld hl, (SegPtr)
        ld bc, 4
        add hl, bc
        ld a, (hl)
        inc hl
        or (hl)
        dec hl
        jr nz, .ok
        ld hl, (StTrack)        ; past the end: loop (never reached in play)
.ok:    ld (SegPtr), hl
        jr UpdateTrack

; Build CurveList: curvature and hill at the bottom line, then triples
; (line, curvature, hill) for each segment boundary in view, from the bottom
; up, ended by line $FF. HillOr <> 0 if any hill is in view; RoadStraight = 1
; if no curve or hill is.
BuildCurveList:
        ld hl, (SegPtr)
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld a, (hl)
        inc hl
        ld (CurveList), a
        ld (CurveOr), a
        ld a, (hl)
        inc hl                  ; HL = next segment
        ld (CurveList + 1), a
        ld (HillOr), a
        push hl
        ld hl, (SegStart)
        add hl, de
        ld de, (Pos)
        or a
        sbc hl, de
        ex de, hl               ; DE = depth of the segment's end
        pop hl
        ld ix, CurveList + 2
        ld b, MAX_BOUNDS
.next:  ; boundary beyond the horizon? then done
        push hl
        ld hl, Z_FAR
        or a
        sbc hl, de
        pop hl
        jr c, .done
        push hl
        call ZLine              ; A = first line (from the bottom) in the new segment
        pop hl
        cp $FF
        jr z, .odd
        or 1                    ; events are checked on odd lines only
.odd:   ld (ix + 0), a
        ; next segment (looping)
        ld a, (hl)
        inc hl
        or (hl)
        dec hl
        jr z, .done             ; end of the stage: the last straight runs on
.seg:   ld a, (hl)
        add a, e
        ld e, a
        inc hl
        ld a, (hl)
        adc a, d
        ld d, a                 ; DE = depth of this segment's end
        jr nc, .noOv
        ld de, $FFFF            ; far beyond the horizon: stops the next pass
.noOv:  inc hl
        ld a, (hl)
        ld (ix + 1), a
        ld c, a
        ld a, (CurveOr)
        or c
        ld (CurveOr), a
        inc hl
        ld a, (hl)
        ld (ix + 2), a
        ld c, a
        ld a, (HillOr)
        or c
        ld (HillOr), a
        inc hl
        inc ix
        inc ix
        inc ix
        djnz .next
.done:  ld (ix + 0), $FF
        ld a, (CurveOr)
        ld hl, HillOr
        or (hl)
        ld a, 1
        jr z, .st
        xor a
.st:    ld (RoadStraight), a
        ret

; DE = depth (>= 1) -> A = largest line i with Z[i] >= depth, i.e. the
; nearest line that already lies beyond it ($FF if none). Keeps BC, DE.
; The depth tables (ZNear by 4 units, ZFar by 16) give a line at or below
; the answer; then step up while Z[i] < depth.
ZLine:  ld a, d
        cp 4
        jr nc, .far
        ld l, e                 ; ZNear[depth >> 2]
        ld a, d
        srl a
        rr l
        srl a
        rr l
        ld h, high ZNear
        ld a, (hl)
        jr .ref
.far:   cp 16
        ld a, 2                 ; 4096 and beyond: lines 0-2 at most
        jr nc, .ref
        ld a, e                 ; ZFar[depth >> 4]
        and $F0
        or d
        rrca
        rrca
        rrca
        rrca
        ld l, a
        ld h, high ZFar
        ld a, (hl)
.ref:   cp $FF
        ret z
        ld l, a
        ld h, high ZLo
        ld a, (hl)
        sub e
        ld h, high ZHi
        ld a, (hl)
        sbc a, d
        ld a, l
        ret nc                  ; Z[i] >= depth
        dec a
        jr .ref

; Called by RoadPass1 when it reaches a line in the curve list (A = line):
; switch to the next curvature(s) and arm the next boundary.
NextCurve:
        push hl
        ld hl, (CurvePtr)
.again: inc hl
        ld a, (hl)              ; new curvature
        inc hl                  ; (skip the hill: HillMap's)
        call SetCurve
        inc hl
        ld a, (hl)              ; next boundary line
        ld (NextNB), a
        ld (CurvePtr), hl
        ; another boundary on the same line? (A = next line, compare to this one)
        exx
        cp l
        exx
        jr z, .again
        pop hl
        ret

; Curvature is weighted by how much depth a screen line spans: near lines
; (bottom) get 1/4, and the weight doubles at each zone line going up, to 16
; near the horizon. So bends build up in the distance and the near road
; straightens gradually instead of snapping when a segment boundary passes
; under the car.
ZoneLines:
        db 65, 49, 35, 25, 17, 13, $FF     ; odd: pass 1 checks events on odd lines

; A = segment curvature -> patch RoadPass1's dx increment for the current zone
SetCurve:
        ld (CurC), a
; k = (curvature << zone) >> 2 (16.8, signed): RoadPass1 adds 4 k to P per
; line pair (patched), and its event path uses 3 k (CurK3) to correct P
ApplyCurve:
        ld a, (CurC)
        or a
        jr z, .straight         ; (no curvature: all of it 0)
        push hl
        push bc
        push de
        IFDEF EINSTEIN          ; (A = CurC) the zone's 2 or more: << (zone - 2),
        ld l, a                 ; exactly the same, with fewer shifts
        rlca
        sbc a, a
        ld h, a
        ld a, (CurK)
        sub 2
        jr c, .near
        jr z, .shifted
        ld b, a
.sh:    add hl, hl
        djnz .sh
        jr .shifted
.near:  inc a                   ; (zone 0: >> 2, zone 1: >> 1)
        jr z, .r1
        sra h
        rr l
.r1:    sra h
        rr l
.shifted:                       ; HL = k (8.8)
        ELSE
        ld a, (CurC)
        ld l, a
        rlca
        sbc a, a
        ld h, a
        ld a, (CurK)
        or a
        jr z, .shifted
        ld b, a
.sh:    add hl, hl
        djnz .sh
.shifted:
        sra h
        rr l
        sra h
        rr l                    ; HL = k (8.8)
        ENDIF
        ld a, h
        rlca
        sbc a, a                ; A:H:L = k
        ld c, a
        ld d, h
        ld e, l                 ; C:D:E = k
        add hl, hl
        rla                     ; A:H:L = 2 k
        ld b, a
        push hl
        add hl, hl
        rla                     ; 4 k
        ld (RoadPass1.p4h + 1), a
        ld a, h
        ld (RoadPass1.p4l + 1), a
        ld a, l
        ld (RoadPass1.p4f + 1), a
        pop hl
        add hl, de
        ld a, b
        adc a, c                ; A:H:L = 3 k
        ld (CurK3), hl
        ld (CurK3 + 2), a
        pop de
        pop bc
        pop hl
        ret
.straight:
        ld (RoadPass1.p4h + 1), a
        ld (RoadPass1.p4l + 1), a
        ld (RoadPass1.p4f + 1), a
        ld (CurK3), a
        ld (CurK3 + 1), a
        ld (CurK3 + 2), a
        ret

; RoadPass1's next event line: the nearer (higher) of the next curve
; boundary and zone line ($FF: none - both end with $FF)
NextEvent:
        push bc
        ld a, (NextNB)
        cp $FF
        jr nz, .b
        xor a
.b:     ld b, a
        ld a, (NextNZ)
        cp $FF
        jr nz, .z
        xor a
.z:     cp b
        jr nc, .m
        ld a, b
.m:     or a
        jr nz, .s
        dec a
.s:     ld (RoadPass1.nx + 1), a
        pop bc
        ret

; Called by RoadPass1 at a zone line: double the curvature weight.
NextZone:
        push hl
        ld hl, CurK
        inc (hl)
        ld hl, (ZonePtr)
        inc hl
        ld (ZonePtr), hl
        ld a, (hl)
        ld (NextNZ), a
        pop hl
        jp ApplyCurve
