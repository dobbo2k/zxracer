; ---------------------------------------------------------------------------
; Roadside scenery
;
; Objects (z, lateral offset, type) come from build/track_data.asm, sorted
; by z. Each frame the ones in view are projected: the screen line from
; their depth (ZLine), the size from that line, x from the road centre on
; that line plus offset * perspective scale. Pre-scaled, pre-shifted
; silhouettes are XORed onto the back buffer.
;
; XOR makes erasing exact and cheap: before the road is updated, the
; buffer's previous draw commands are replayed, which restores precisely
; what the road had drawn there (kerb pixels included), so the road's
; incremental update stays valid. On the zero grass/sky background XOR
; looks the same as OR, and kerb road pixels are black ink like the
; silhouettes.
;
; Draw command (8 bytes): y top, column, bytes per line (n), source skip
; per line (width - n), source address (2), height, unused.
; ---------------------------------------------------------------------------
MAX_SPR         EQU 14             ; draw commands per buffer
MAX_SCN         EQU 8              ; scenery objects considered per frame
Z_NEARV         EQU 130             ; objects nearer than this have passed the bottom line
Z_FARV          EQU 2000            ; and further than this (specks) are not drawn
CMD_SIZE        EQU 8
PALM_HALFWIDTH  EQU 48             ; car half-width + the palm's crown

; Skip objects that have passed behind the camera.
UpdateObjects:
        ld hl, (ObjFirst)
        ld b, 0                 ; at most 256 steps
.lp:    push hl
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        inc hl
        ld a, (hl)              ; type
        pop hl
        cp $FF
        jr nz, .obj
        ld hl, Objects          ; end of the list: next lap
        jr .next
.obj:   push hl
        ld hl, (Pos)
        ex de, hl
        or a
        sbc hl, de              ; HL = z - Pos
        bit 7, h
        jr nz, .behind
        ld a, h
        or a
        jr nz, .ahead
        ld a, l
        cp Z_NEARV
        jr nc, .ahead
.behind:
        pop hl
        ; passing a palm: did the player drive into it?
        push hl
        inc hl
        inc hl
        ld a, (hl)              ; x / 4
        inc hl
        ld c, (hl)              ; type
        pop hl
        push hl
        push bc
        call ObjHit
        pop bc
        pop hl
        ld de, 4
        add hl, de
.next:  djnz .lp
        ld (ObjFirst), hl
        ret
.ahead: pop hl
        ld (ObjFirst), hl
        ret

; A = object x / 4, C = type: crash if the player's car overlaps a palm
; that has just reached it (only possible well off the road).
ObjHit: ld e, a
        ld a, c
        cp TYPE_TRAFFIC         ; palms and signs are solid; traffic is handled apart
        ret z
        ld a, (CrashTimer)
        or a
        ret nz
        ld a, e
        ld l, a
        rlca
        sbc a, a
        ld h, a
        add hl, hl
        add hl, hl
        ld de, (PlayerX)
        or a
        sbc hl, de
        bit 7, h
        jr z, .p
        ex de, hl
        ld hl, 0
        or a
        sbc hl, de
.p:     ld de, PALM_HALFWIDTH
        or a
        sbc hl, de
        ret nc
        ld a, CRASH_FRAMES
        ld (CrashTimer), a
        xor a
        ld (Speed), a
        ld a, SFX_CRASH
        jp PlaySfx

; Replay the draw commands this buffer holds (XOR = erase).
EraseSprites:
        ld hl, (CmdList)
        ld a, (hl)              ; count
        or a
        ret z
        ld b, a
        inc hl
.lp:    push bc
        push hl
        call RunCommand
        pop hl
        ld bc, CMD_SIZE
        add hl, bc
        pop bc
        djnz .lp
        ret

; Project visible objects, XOR them onto the back buffer and record the
; commands in this buffer's list: traffic first, then scenery.
DrawSprites:
        ld hl, (CmdList)
        ld (hl), 0
        inc hl
        ld (CmdPtr), hl
        call DrawTraffic
        ld hl, (ObjFirst)
        ld b, MAX_SCN
.obj:   push bc
        ; ---- read the object; the end marker wraps to the start of the list
        ld a, (hl)
        ld (ObjZ), a
        inc hl
        ld a, (hl)
        ld (ObjZ + 1), a
        inc hl
        ld a, (hl)
        ld (ObjX), a
        inc hl
        ld a, (hl)
        inc hl
        cp $FF
        jr nz, .have
        ld hl, Objects
        pop bc
        jr .obj
.have:  ld (ObjType), a
        push hl
        call DrawObject
        pop hl
        pop bc
        ret c                   ; the rest of the list is further away
        djnz .obj
        ret

; Project and draw one object (ObjZ, ObjX, ObjType).
; Returns carry if it lies beyond the far limit.
DrawObject:
        ; ---- depth relative to the camera
        ld hl, (ObjZ)
        ld de, (Pos)
        or a
        sbc hl, de
        ex de, hl               ; DE = z_rel
        ld hl, Z_FARV
        or a
        sbc hl, de
        ret c                   ; beyond the far limit (carry set)
        call ObjLine            ; A = screen line index (or $FF)
        cp $FF
        jp z, .skip
        ld (ObjI), a
        ; ---- size from the line
        or $80
        ld l, a
        ld h, high SizeForLine
        ld a, (hl)
        cp $FF
        jp z, .skip
        add a, a
        add a, a
        add a, a                ; 8 bytes per directory entry
        ld e, a
        ld d, 0
        ld a, (ObjType)
        add a, a
        ld l, a
        ld h, 0
        push de
        ld de, TypeDir
        add hl, de
        ld e, (hl)
        inc hl
        ld d, (hl)
        ex de, hl               ; HL = the type's size directory
        pop de
        add hl, de
        ld a, (hl)
        ld (SprW), a
        inc hl
        ld a, (hl)
        ld (SprH), a
        inc hl
        ld a, (hl)
        ld (SprMask), a
        inc hl
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld (SprSrc), de
        ld e, (hl)
        inc hl
        ld d, (hl)
        ld (SprStride), de
        ; ---- x = cx + (ObjX * scale) >> 6, then the left edge
        ld a, (ObjI)
        ld l, a
        ld h, high ObjScale
        ld e, (hl)
        ld a, (ObjX)
        call MulS8U8            ; HL = ObjX * scale
        sra h
        rr l
        sra h
        rr l
        sra h
        rr l
        sra h
        rr l
        sra h
        rr l
        sra h
        rr l
        ex de, hl
        call LineCentre         ; HL = cx on line ObjI
        jp c, .skip             ; no road on that line
        add hl, de              ; x
        ld a, (SprW)
        dec a
        add a, a
        add a, a                ; half the drawn width (width - padding) * 4
        ld e, a
        ld d, 0
        or a
        sbc hl, de              ; left edge
        ; shift copy: shift & mask, scaled down to a copy index
        ld a, (SprMask)
        and l
        ld c, a
        ld a, (SprMask)
        cp 7
        ld a, c
        jr z, .idx
        rrca
        ld c, a
        ld a, (SprMask)
        cp 6
        ld a, c
        jr z, .idx
        rrca
.idx:   and 7
        jr z, .noShift
        ld b, a
        push hl
        ld hl, (SprSrc)
        ld de, (SprStride)
.mul:   add hl, de
        djnz .mul
        ld (SprSrc), hl
        pop hl
.noShift:
        ; column = left >> 3 (signed); must overlap 0..31
        sra h
        rr l
        sra h
        rr l
        sra h
        rr l
        ld a, h
        or a
        jr z, .colPos
        inc a
        jp nz, .skip            ; far off screen
        ld a, l                 ; negative: visible if col + width > 0
        ld b, a
        ld a, (SprW)
        add a, b
        jr nc, .skip            ; (col + w wraps past 0 only if visible)
        jr z, .skip
        ; clipped on the left: skip -col bytes
        ld a, b
        neg
        ld c, a                 ; bytes clipped
        ld a, (SprW)
        sub c
        ld (SprN), a
        ld a, c
        ld (SprSkip), a
        ld hl, (SprSrc)
        ld e, c
        ld d, 0
        add hl, de
        ld (SprSrc), hl
        xor a
        jr .colSet
.colPos:
        ld a, l
        cp 32
        jr nc, .skip
        ld c, a
        ld a, 32
        sub c                   ; bytes to the right edge
        ld b, a
        ld a, (SprW)
        cp b
        jr c, .fits
        ld a, b
.fits:  ld (SprN), a
        ld b, a
        ld a, (SprW)
        sub b
        ld (SprSkip), a
        ld a, c
.colSet:
        ; ---- build the command (if the list has room)
        ld hl, (CmdList)
        ld b, a
        ld a, (hl)
        cp MAX_SPR
        jr nc, .skip
        ld a, b
        ld hl, (CmdPtr)
        ld c, a                 ; column
        ld a, (ObjI)
        add a, ROAD_Y0 + 1
        ld b, a
        ld a, (SprH)
        ld e, a
        ld a, b
        sub e                   ; y top = base line + 1 - height
        ld (hl), a
        inc hl
        ld (hl), c
        inc hl
        ld a, (SprN)
        ld (hl), a
        inc hl
        ld a, (SprSkip)
        ld (hl), a
        inc hl
        ld de, (SprSrc)
        ld (hl), e
        inc hl
        ld (hl), d
        inc hl
        ld a, (SprH)
        ld (hl), a
        inc hl
        inc hl
        ld (CmdPtr), hl
        ld de, -CMD_SIZE
        add hl, de
        call RunCommand
        ld hl, (CmdList)
        inc (hl)
.skip:  or a                    ; no carry: keep going
        ret

; DE = depth (< Z_FARV) -> A = largest line i with Z[i] >= depth ($FF: none)
ObjLine:
        ld a, d
        cp 4
        jr nc, .far
        ; depth < 1024: ZNear[depth >> 2]
        ld a, e
        srl d
        rra
        srl d
        rra
        ld l, a
        ld h, high ZNear
        ld a, (hl)
        ret
.far:   ; depth < 4096: ZFar[depth >> 4]
        ld a, e
        and $F0
        or d
        rrca
        rrca
        rrca
        rrca
        ld l, a
        ld h, high ZFar
        ld a, (hl)
        ret

; Road centre on line ObjI from the clamped edges: (D + E + 1) / 2 when
; neither edge is clamped, else from the unclamped edge and X1.
; Returns HL = cx, carry set if the line has no road on screen. Keeps DE.
LineCentre:
        ld a, (ObjI)
        ld l, a
        ld h, high RoadD
        ld b, (hl)              ; D
        set 7, l
        ld c, (hl)              ; E
        ld a, c
        cp b
        ret c                   ; no road
        ld h, high RoadX1
        ld a, b
        or a
        jr z, .fromE
        ; cx = D + X1
        add a, (hl)
        ld l, a
        ld a, 0
        adc a, 0
        ld h, a
        or a
        ret
.fromE: ; cx = E + 1 - X1
        ld a, c
        inc a
        ld b, (hl)
        ld l, a
        ld h, 0
        jr nz, .e1
        inc h                   ; E = 255: E + 1 = 256
.e1:    ld a, l
        sub b
        ld l, a
        ld a, h
        sbc a, 0
        ld h, a
        or a
        ret

; A = signed multiplier, E = unsigned multiplicand -> HL = signed product
MulS8U8:
        ld c, a
        bit 7, a
        jr z, .pos
        neg
.pos:   ld hl, 0
        ld d, h
        ; |A| < 128: 7 bits, unrolled, stopping when no bits are left
        DUP 7
        add hl, hl
        add a, a
        jr nc, $ + 3
        add hl, de
        EDUP
        add hl, hl
        add a, a
        jr nc, .done
        add hl, de
.done:  bit 7, c
        ret z
        ex de, hl
        ld hl, 0
        or a
        sbc hl, de
        ret

; HL -> draw command. XOR the sprite into the back buffer.
RunCommand:
        ; does the sprite overlap the player's car block (rows 20-23, cols 12-19)?
        push hl
        ld a, (hl)              ; y top
        ld b, a
        inc hl
        ld c, (hl)              ; column
        inc hl
        ld e, (hl)              ; n
        inc hl
        inc hl
        inc hl
        inc hl
        add a, (hl)             ; y top + height
        cp CAR_ROW * 8 + 1
        jr c, .noCar
        ld a, c
        cp CAR_COL + CAR_W
        jr nc, .noCar
        add a, e
        cp CAR_COL + 1
        jr c, .noCar
        ld a, 1
        ld (CarDirty), a
.noCar: pop hl
        ld a, (hl)              ; y top
        ld c, a
        inc hl
        ld a, (hl)
        ld (.col + 1), a
        inc hl
        ld a, (hl)              ; n
        add a, a
        add a, a
        ld b, a
        ld a, (hl)
        add a, b                ; 5 * n
        neg
        ld (.jent + 1), a       ; XorEnd - 5n  (low byte; XorEnd is page-aligned)
        inc hl
        ld a, (hl)
        ld (.skp + 1), a
        or a
        ld de, ((.adv - .back - 2) << 8) | $18      ; JR .adv: nothing clipped
        jr z, .noClip
        ld de, $007B            ; LD A,E : NOP -> source adjustment
.noClip:
        ld (.back), de
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)              ; DE = source
        inc hl
        ld b, (hl)              ; height
        ld iy, .back
        ; first line address
        call .rowAddr
.ln:
.lcol:  ld l, 0
.jent:  jp XorEnd - 256         ; low byte patched (n > 0 always)
.back:  jr .adv                 ; patched: JR .adv or LD A,E : NOP
.skp:   add a, 0
        ld e, a
        adc a, d
        sub e
        ld d, a
.adv:   inc c
        inc h
        ld a, h
        and 7
        call z, .rowAddr        ; crossed into the next character row
        djnz .ln
        ret
.rowAddr:
        push de
        ld l, c
        ld h, high ScrLo
        ld e, (hl)
        inc h
        ld a, (hl)
.bufOr: or 0
        ld h, a
        ld a, e
.col:   add a, 0
        ld (.lcol + 1), a
        pop de
        ret
