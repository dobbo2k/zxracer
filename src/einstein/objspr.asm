; ---------------------------------------------------------------------------
; Einstein: traffic and scenery as hardware sprites (-DEIN_OBJSPR, a
; prototype; docs/einstein_objects_plan.md option B)
;
; DrawSprites records the frame's commands (CmdListB) without drawing them:
; EinErase leaves RunCommand.clipY at 0. Here, after DrawPortal, they are
; taken nearest first (the lowest bottom line), and each that can be is
; made sprites 2-31 (EinObjSprite, from the 16 x 16 patterns OvSprPatterns
; made at the display reset); its y top becomes $FF, which RunCommand,
; EinSprCells and the next frame's erase all pass over. The rest are drawn
; into screen B as ever. No sprites while a tunnel or the gantry is in view
; (the portal hides objects by painting over cells). EinUpload sends the
; attributes (ESprAttr) in the vertical blank.
; ---------------------------------------------------------------------------
EinObjSprites:
        ld a, 192               ; (RunCommand draws again)
        ld (RunCommand.clipY + 1), a
        ld hl, ESprAttr
        ld (ESprPtr), hl
        ld a, (TunJN)
        ld hl, TunInside
        or (hl)
        ld hl, GateWas
        or (hl)
        jr nz, .rest
        ld hl, ESprBand         ; (A = 0) no sprites a band yet, but the tail
        ld b, 22                ; lamps' 2 on bands 22-23
.z:     ld (hl), a
        inc hl
        djnz .z
        ld (hl), 2
        inc hl
        ld (hl), 2
        ld a, 30                ; sprites 2-31
        ld (ESprLeft), a
.pick:  ld a, (CmdListB)        ; the nearest not looked at yet (its type's
        or a                    ; bit 7: looked at)
        jr z, .rest
        ld b, a
        ld ix, CmdListB + 1
        ld c, 0                 ; (its bottom line + 1)
        ld de, CMD_SIZE
.scan:  bit 7, (ix + 7)
        jr nz, .sn
        ld a, (ix + 0)
        add a, (ix + 6)
        cp c
        jr c, .sn
        ld c, a
        ld (ESprBest), ix
.sn:    add ix, de
        djnz .scan
        inc c
        dec c
        jr z, .rest             ; (all looked at)
        ld ix, (ESprBest)
        set 7, (ix + 7)
        ld a, (ix + 0)          ; clear of the car's cells (their names go
        add a, (ix + 6)         ; over objects)
        cp CAR_ROW * 8 + 1
        jr c, .sp
        ld a, (ix + 1)
        cp CAR_COL + CAR_W
        jr nc, .sp
        add a, (ix + 2)
        cp CAR_COL + 1
        jr nc, .pick
.sp:    call EinObjSprite       ; (src/einstein/objsprcmd.asm)
        jr .pick
.rest:  ld hl, (ESprPtr)        ; the attributes' end, and their length
        ld (hl), $D0
        inc hl
        ld a, l
        sub low ESprAttr
        ld (ESprLen), a
        ld hl, CmdListB         ; the rest into screen B
        ld b, (hl)
        inc hl
        inc b
        jr .rn
.run:   push bc
        push hl
        call RunCommand
        pop hl
        ld de, 7
        add hl, de
        res 7, (hl)             ; (its type as it was)
        inc hl
        pop bc
.rn:    djnz .run
        ret

; (EinObjSprAttrs) C = the sprites' colour, one for the object: its ink for
; the middle half of its height (the cells take the top quarter's, the
; middle half's or the bottom quarter's by rows of 8), and black where
; that is a verge's (as EinSprCell keeps an object seen)
EinObjSprInk:
        ld a, (ESprType)        ; EObjectInks + type * 3 + 1
        ld l, a
        add a, a
        add a, l
        inc a
        ld l, a
        ld h, high EObjectInks
        ld c, (hl)
        ld hl, EGroundPapers
        ld a, c
        cp (hl)
        jr z, .k
        inc hl
        cp (hl)
        ret nz
.k:     ld c, 1
        ret
