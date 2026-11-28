; HL = track stream. Recreate the original ten-byte header, four-byte
; segment and object records, and both sentinels at TRACK_CACHE.
ExpandTrack:
        ld de, TRACK_CACHE
        ld bc, 10
        ldir
        ld a, (hl)
        ld (.segments + 1), a
        inc hl
        ld a, (hl)
        ld (.objects + 1), a
        inc hl
        push de
        pop iy
        xor a
        ld (.curve + 1), a
        ld (.hill + 1), a
        ld a, $80
        ex af, af'
.segment:
        call TrackFlag
        ld b, 12
        jr nc, .length
        ld b, 14
.length:
        call TrackBits
        ld (iy + 0), e
        ld (iy + 1), d
        call TrackFlag
        jr nc, .curve
        ld b, 6
        call TrackBits
        ld a, e
        bit 5, a
        jr z, .curvePositive
        or $C0
.curvePositive:
        ld (.curve + 1), a
.curve: ld a, 0
        ld (iy + 2), a
        call TrackFlag
        jr nc, .hill
        ld b, 4
        call TrackBits
        ld a, e
        bit 3, a
        jr z, .hillPositive
        or $F0
.hillPositive:
        ld (.hill + 1), a
.hill:  ld a, 0
        ld (iy + 3), a
        ld bc, 4
        add iy, bc
.segments:
        ld a, 0
        dec a
        ld (.segments + 1), a
        jr nz, .segment
        ld (iy + 0), a
        ld (iy + 1), a
        inc iy
        inc iy
        ld ix, 0
.object:
        call TrackFlag
        ld b, 8
        jr nc, .delta
        call TrackFlag
        ld b, 10
        jr nc, .delta
        ld b, 13
.delta: call TrackBits
        add ix, de
        ld a, ixl
        ld (iy + 0), a
        ld a, ixh
        ld (iy + 1), a
        call TrackFlag
        ld b, 5
        jr nc, .pair
        call TrackFlag
        ld b, 7
        jr nc, .pair
        ld b, 3
        call TrackBits
        push hl
        ld hl, ObjectKinds
        add hl, de
        ld a, (hl)
        pop hl
        ld (iy + 3), a
        ld b, 8
        call TrackBits
        ld (iy + 2), e
        jr .next
.pair:  call TrackBits
        sla e
        push hl
        ld hl, ObjectPairs
        add hl, de
        ld a, (hl)
        ld (iy + 2), a
        inc hl
        ld a, (hl)
        ld (iy + 3), a
        pop hl
.next:  ld bc, 4
        add iy, bc
.objects:
        ld a, 0
        dec a
        ld (.objects + 1), a
        jr nz, .object
        ld (iy + 0), a
        ld (iy + 1), a
        ld (iy + 2), a
        ld (iy + 3), $FF
        ret

; Held in A' so symbol fields can be interpreted in A.
TrackFlag:
        ex af, af'
        call GetBit
        jr c, .one
        ex af, af'
        or a
        ret
.one:  ex af, af'
        scf
        ret

; B = field width. DE = the unsigned field.
TrackBits:
        ex af, af'
        ld de, 0
.bit:   call GetBit
        rl e
        rl d
        djnz .bit
        ex af, af'
        ret
