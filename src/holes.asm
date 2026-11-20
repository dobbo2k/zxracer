; ---------------------------------------------------------------------------
; Data in the unused ends of the lookup-table pages (bank 2, src/main.asm
; includes tables.asm). Most tables fill 96 or 192 bytes of their 256-byte
; page; nothing reads or writes past them - checked with zxsim -u over whole
; games (PLAN.md) - except one byte after ScrLo and ScrHi, kept clear, and
; the state pages, which ResetDisplay clears whole (nothing goes there). The
; ASSERTs keep a table from growing into what follows it.
; ---------------------------------------------------------------------------
        ORG ScrLo + $C4         ; (ScrLo + $C0..$C3 kept clear)
        ASSERT ScrLo_end <= ScrLo + $C4
CrewSay0a: db "< WATCH THE ROAD!   ", 0
CrewSay0b: db "   SORRY, SORRY... >", 0
        ASSERT $ <= ScrLo + 256
        ORG ScrHi + $C4
        ASSERT ScrHi_end <= ScrHi + $C4
CrewSay1a: db "< ARE YOU BLIND?!   ", 0
CrewSay1b: db "  THE SUN WAS LOW! >", 0
        ASSERT $ <= ScrHi + 256
        ORG X1Page + $60
        ASSERT RoadX1_end <= X1Page + $60
CrewSay2a: db "< MY HAIR! MY HAIR! ", 0
        ASSERT $ <= X1Page + $80
        ORG X1Page + $E0
        ASSERT RoadRW_end <= X1Page + $E0
CrewSay2b: db "   IT LOOKS GREAT! >", 0
        ASSERT $ <= X1Page + 256
        ORG LWPage + $60
        ASSERT LaneWp_end <= LWPage + $60
CrewSay3a: db "< LET ME DRIVE!     ", 0
        ASSERT $ <= LWPage + $80
        ORG LWPage + $E0
        ASSERT Band_end <= LWPage + $E0
CrewSay3b: db "   NOT A CHANCE... >", 0
        ASSERT $ <= LWPage + 256
        ORG ZPage + $60
        ASSERT ZLo_end <= ZPage + $60
CrewSay4a: db "< NICE ONE, GENIUS! ", 0
        ASSERT $ <= ZPage + $80
        ORG ZPage + $E0
        ASSERT LaneW_end <= ZPage + $E0
CrewSay4b: db "    IT JUMPED OUT! >", 0
        ASSERT $ <= ZPage + 256
        ORG DEPage + $60
        ASSERT RoadD_end <= DEPage + $60
CrewSay5a: db "< I SAID SLOW DOWN! ", 0
        ASSERT $ <= DEPage + $80
        ORG DEPage + $E0
        ASSERT RoadE_end <= DEPage + $E0
CrewSay5b: db "   I WAS GOING TO! >", 0
        ASSERT $ <= DEPage + 256
        ORG LXPage + $60
        ASSERT LaneX_end <= LXPage + $60
CrewSay6a: db "< LOSE THE SHADES!  ", 0
        ASSERT $ <= LXPage + $80
        ORG LXPage + $E0
        ASSERT ForkT1_end <= LXPage + $E0
CrewSay6b: db " THEY LOOK COOL... >", 0
        ASSERT $ <= LXPage + 256
        ORG ObjPage + $60
        ASSERT ObjScale_end <= ObjPage + $60
CrewSay7a: db "< OPEN YOUR EYES!   ", 0
        ASSERT $ <= ObjPage + $80
        ORG ObjPage + $E0
        ASSERT SizeForLine_end <= ObjPage + $E0
CrewSay7b: db "    THEY ARE OPEN! >", 0
        ASSERT $ <= ObjPage + 256
        ORG ZHiPage + $60
        ASSERT ZHi_end <= ZHiPage + $60
CrewTraffic:
        dw CrewSayT0a, CrewSayT0b
        dw CrewSayT1a, CrewSayT1b
        dw CrewSayT2a, CrewSayT2b
        dw CrewSay4a, CrewSay4b
CrewSayT0a: db "< YOU HIT A LORRY!  ", 0
CrewSayT0b: db "   IT BRAKED HARD! >", 0
CrewSayT1a: db "< YOU TAILGATED HIM!", 0
CrewSayT1b: db " HE WAS IN MY WAY! >", 0
CrewSayT2a: db "< LOOK AT THAT DENT!", 0
CrewSayT2b: db "   THAT WAS THERE! >", 0
        ASSERT $ <= ZHiPage + 256
        ORG MaskPage + $20
        ASSERT LMaskIncl_end <= MaskPage + $20
CrewLines:      ; her line, his reply
        dw CrewSay0a, CrewSay0b
        dw CrewSay1a, CrewSay1b
        dw CrewSay2a, CrewSay2b
        dw CrewSay3a, CrewSay3b
        dw CrewSay4a, CrewSay4b
        dw CrewSay5a, CrewSay5b
        dw CrewSay6a, CrewSay6b
        dw CrewSay7a, CrewSay7b
        ASSERT $ <= MaskPage + $40
        ORG MaskPage + $C0
        ASSERT LaneM2_end <= MaskPage + $C0
LampGlyph:
        db $00, $00, $03, $C0, $0F, $F0, $1F, $F8, $3F, $FC, $3F, $FC, $7F, $FE, $7F, $FE
        db $7F, $FE, $7F, $FE, $3F, $FC, $3F, $FC, $1F, $F8, $0F, $F0, $03, $C0, $00, $00
; the route of the last game (the stage played on each row; $FF: not reached)
Route:          ds 5, $FF
        ASSERT $ <= MaskPage + 256
        ORG StripPage + $39
        ASSERT StripR_end <= StripPage + $39
; The high-score table (score: 4 BCD bytes, low byte first; initials)
HI_ENTRIES      EQU 5
HI_SIZE         EQU 7
HiTable:
        db $00, $00, $06, $00, "ACE"
        db $00, $00, $05, $00, "SUN"
        db $00, $00, $04, $00, "ZXR"
        db $00, $00, $03, $00, "BOB"
        db $00, $00, $02, $00, "DOT"
        ASSERT $ <= StripPage + 256
