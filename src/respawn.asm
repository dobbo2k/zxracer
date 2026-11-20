; Respawn the vehicle IX somewhere ahead, beyond the scenery horizon
; (Pos + 3200..4223), in a random lane, its class and speed by the row's mix.
; (Lives in a gap of bank 2 after the dual-write chain.)
Respawn:
        call Random
        and 3
        add a, high 3200
        ld d, a
        call Random
        ld e, a
        ld hl, (Pos)
        add hl, de
        ld (ix + 0), l
        ld (ix + 1), h
        call Random
        ld c, LANE_X
        rra
        jr c, .lane
        ld c, -LANE_X
.lane:  ld (ix + 2), c
        ld (ix + 5), c
        and 7                   ; the class
        ld c, 0
        ld hl, VanFrom
        cp (hl)
        jr c, .cls
        inc c
        inc hl                  ; TruckFrom
        cp (hl)
        jr c, .cls
        inc c
.cls:   ld (ix + 4), c
        call ClassOf
        inc hl
        inc hl
        call Random
        inc hl
        and (hl)                ; random & mask
        dec hl
        add a, (hl)             ; + base
        ld (ix + 3), a
        ret
