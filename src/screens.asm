; ---------------------------------------------------------------------------
; Front end, resident part (bank 5). The title, goal and other between-game
; screens are an overlay (src/frontend.asm): stored in a pack bank and copied
; into bank 7 over the theme cache when the front end runs; the stage is
; loaded again afterwards. Only the way in and the picture unpacker (which
; pages the pictures' banks over the overlay) stay here.
; ---------------------------------------------------------------------------
ATTRACT_LOOPS   EQU 360             ; game frames of demo between title screens

; From the demo (and at power-on): the title screens; then a game if a key
; was pressed, else the demo carries on where it was.
GoTitle:
        call LoadFrontEnd
        call TitleScreen
        or a
        jp nz, StartGame
        ld a, (Stage)
        call LoadPacks          ; (the overlay is over the theme)
        call ResetDisplay
Attract:
        ld hl, ATTRACT_LOOPS
        ld (AttractTimer), hl
        ld hl, MsgAttract
        ld (Message), hl
        ret

; The game has ended (the car has rolled to a stop): the goal screen if the
; goal was reached and the other end-of-game screens, then the title; a
; game, or the demo from stage 1.
EndGame:
        ld a, ST_ATTRACT
        ld (GameState), a
        call LoadFrontEnd
        call GameOverScreens
        or a
        jp nz, StartGame
        call Restart
        jr Attract

; Copy the front-end overlay into bank 7 (over the theme cache)
LoadFrontEnd:
        call WaitFlip
        ld hl, FrontEndPack
        ld a, (hl)
        inc hl
        ld e, (hl)
        inc hl
        ld d, (hl)
        inc hl
        ld c, (hl)
        inc hl
        ld b, (hl)
        ld hl, THEME_CACHE
        jp CopyToCache

; A = bank, HL = compressed picture in it: unpack into screen A, show it
ShowPic:
        or P7FFD_ROM48 | P7FFD_SHADOW
        ld bc, PORT_7FFD
        out (c), a
        ld de, $4000
        call UnLZ
        ld a, P7FFD_ROM48 | 7   ; screen A on show, bank 7 back
        ld (Port7FFD), a
        ld bc, PORT_7FFD
        out (c), a
        ret

; HL = source, DE = destination (see tools/make_screens.py)
UnLZ:   ld a, (hl)
        inc hl
        cp $FF
        ret z
        cp $80
        jr nc, .match
        inc a
        ld c, a
        ld b, 0
        ldir                    ; literals
        jr UnLZ
.match: sub $80 - 3
        ld c, a
        ld b, 0
        ld a, (hl)
        inc hl
        push hl
        ld h, (hl)
        ld l, a                 ; offset
        push de
        ex de, hl
        or a
        sbc hl, de              ; destination - offset
        pop de
        ldir                    ; (overlapping copies repeat, like LDIR should)
        pop hl
        inc hl
        jr UnLZ
