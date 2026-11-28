; Title and screen clears in the space used by AY data on the 128K.
TitleScreen:
        call Silence
        xor a
        call ClearFront
        ld hl, TitleArt0
        ld bc, $4040
        call .part
        ld bc, $4840
        call .part
        ld bc, $5028
        call .part
        ex de, hl
        ld de, RACE_ATTRS
        ld bc, 21 * 32
        ldir
        jp TitlePrompt
.part:  push bc
        ld de, SharedSprites
        call Unpack
        ex (sp), hl
        ld d, h
        ld e, 0
        ld a, l
        ld (.height + 1), a
        ld hl, SharedSprites
        ld c, 32
.col:   push de
.height:
        ld b, 64
.line:  ld a, (hl)
        inc hl
        ld (de), a
        inc d
        ld a, d
        and 7
        jr nz, .down
        ld a, e
        add a, 32
        ld e, a
        jr c, .down
        ld a, d
        sub 8
        ld d, a
.down:  djnz .line
        pop de
        inc e
        dec c
        jr nz, .col
        ; Return the unpacker's source in HL, decoded text attributes in DE.
        pop de
        ex de, hl
        ret

BlankAttrs:
        xor a
        jr FrontAttrs
ClearFront:
        push af
        call BlankAttrs
        ld hl, RACE_PIXELS
        ld de, RACE_PIXELS + 1
        ld bc, 6143
        ld (hl), l
        ldir
        pop af
FrontAttrs:
        ld hl, RACE_ATTRS
        ld de, RACE_ATTRS + 1
        ld bc, 767
        ld (hl), a
        ldir
        ret

; The options screen uses the title's blue/cyan trim.
MenuDecor:
        ld hl, RACE_ATTRS
        ld de, RACE_ATTRS + 23 * 32
        ld b, 16
.pair:  ld a, $48
        call .stripe
        ld a, $68
        call .stripe
        djnz .pair
        ld hl, RACE_ATTRS + 32
        ld a, $4F
        call MenuAttrRow
        ld a, $4D
        call MenuAttrRow
        ld hl, RACE_ATTRS + 5 * 32 + 4
        ld de, 32
        ld b, 6
.numbers:
        ld (hl), $46
        add hl, de
        djnz .numbers
        ld hl, RACE_ATTRS + 13 * 32
        ld a, $46
        jr MenuAttrRow
.stripe:
        ld (hl), a
        ld (de), a
        inc hl
        inc de
        ret

MenuAttrRow:
        ld b, 32
.attr:  ld (hl), a
        inc hl
        djnz .attr
        ret
