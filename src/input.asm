; ---------------------------------------------------------------------------
; Input: the five controls through KeyMap (keyboard rows and keys, set on
; the options screen: default Q / A / O / P / SPACE, Sinclair or Cursor
; joystick, or keys of the player's choosing), plus a Kempston joystick.
; Input bits (as the Kempston's): 0 right, 1 left, 2 down, 3 up, 4 fire.
; ---------------------------------------------------------------------------

ReadInput:
        ld hl, KeyMap
        ld de, $0501            ; D: keys to read, E: the input bit
        ld c, 0
.key:   ld a, (hl)              ; keyboard row (port high byte)
        inc hl
        in a, ($FE)
        and (hl)                ; the key's bit (0: pressed)
        inc hl
        jr nz, .up
        ld a, c
        or e
        ld c, a
.up:    sla e
        dec d
        jr nz, .key
        in a, ($1F)             ; Kempston; ignore if the bus floats high
        ld b, a
        and $E0
        jr nz, .noKemp
        ld a, b
        or c
        ld c, a
.noKemp:
        ld a, c
        ld (Input), a
        ret
