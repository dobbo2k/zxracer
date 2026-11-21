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
        IFNDEF EINSTEIN         ; (no front end on the Einstein yet: the demo)
        call LoadFrontEnd
        call TitleScreen
        or a
        jp nz, StartGame
        ld a, (Stage)
        call ReloadStage        ; (the overlay is over the theme)
        ENDIF
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
        IFNDEF EINSTEIN         ; (no front end on the Einstein yet: the demo)
        call LoadFrontEnd
        call GameOverScreens
        or a
        jp nz, StartGame
        ENDIF
        call Restart
        jr Attract





