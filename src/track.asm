; ---------------------------------------------------------------------------
; Track: segments of (length, curve) from build/track.asm, looping.
;
; SegPtr / SegStart track the segment under the player. Each frame
; BuildCurveList turns the segments ahead into a list of the screen lines
; where the curvature changes, which RoadPass1 walks from the bottom line up.
; ---------------------------------------------------------------------------
MAX_BOUNDS      EQU 6               ; curvature changes considered per frame
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
        ld hl, Track            ; end of lap: loop
.ok:    ld (SegPtr), hl
        jr UpdateTrack

; Build CurveList: byte 0 = curvature at the bottom line, then pairs
; (line, curvature) for each segment boundary in view, from the bottom up,
; ended by line $FF. Sets RoadStraight = 1 if every curvature is 0.
BuildCurveList:
        ld hl, (SegPtr)
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld a, (hl)
        inc hl
        inc hl                  ; HL = next segment
        ld (CurveList), a
        ld (CurveOr), a
        push hl
        ld hl, (SegStart)
        add hl, de
        ld de, (Pos)
        or a
        sbc hl, de
        ex de, hl               ; DE = depth of the segment's end
        pop hl
        ld ix, CurveList + 1
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
        jr nz, .seg
        ld hl, Track
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
        inc hl
        inc ix
        inc ix
        djnz .next
.done:  ld (ix + 0), $FF
        ld a, (CurveOr)
        or a
        ld a, 1
        jr z, .st
        xor a
.st:    ld (RoadStraight), a
        ret

; DE = depth (>= 1) -> A = largest line i with Z[i] >= depth, i.e. the
; nearest line that already lies beyond it ($FF if none).
; Z decreases with i, so binary-search the first i with Z[i] < depth.
ZLine:  ld bc, ROAD_LINES       ; B = lo = 0, C = hi = 96
.bs:    ld a, b
        cp c
        jr z, .done
        add a, c
        rra
        ld l, a                 ; mid
        ld h, high ZLo
        ld a, (hl)
        sub e
        ld h, high ZHi
        ld a, (hl)
        sbc a, d
        jr c, .less             ; Z[mid] < depth
        ld b, l
        inc b
        jr .bs
.less:  ld c, l
        jr .bs
.done:  ld a, b
        dec a
        ret

; Called by RoadPass1 when it reaches a line in the curve list (A = line):
; switch to the next curvature(s) and arm the next boundary.
NextCurve:
        push hl
        ld hl, (CurvePtr)
.again: inc hl
        ld a, (hl)              ; new curvature
        call SetCurve
        inc hl
        ld a, (hl)              ; next boundary line
        ld (RoadPass1.nb + 1), a
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
; increment = (curvature << zone) >> 2, sign-extended into RoadPass1
ApplyCurve:
        push hl
        push bc
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
        rr l
        ld a, l
        ld (RoadPass1.cl + 1), a
        ld a, h
        ld (RoadPass1.ch + 1), a
        rlca
        sbc a, a
        ld (RoadPass1.ch2 + 1), a
        pop bc
        pop hl
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
        ld (RoadPass1.nz + 1), a
        pop hl
        jr ApplyCurve
