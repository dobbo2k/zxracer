; After a spin-out on traffic: lines about that (the fourth pair is one of
; the general ones). In a gap of bank 2.
CrewPickTraffic:
        ld de, CrewTraffic
        ld c, 3
        jp CrewPickDE
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
