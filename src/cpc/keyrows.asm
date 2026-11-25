; ---------------------------------------------------------------------------
; CPC: the Spectrum's keyboard half-rows made from the CPC's lines (in bank 2,
; always paged at $8000; src/cpc/keys.asm CpcSpecIn calls them)
; ---------------------------------------------------------------------------
; A Spectrum key's bit cleared in L if its CPC key (line, mask) is down
        MACRO KEYBIT line_, mask_, bit_
        ld a, (CpcKeys + line_)
        and mask_
        jr nz, $ + 4
        res bit_, l
        ENDM
CRowMakers:     dw CRow0, CRow1, CRow2, CRow3, CRow4, CRow5, CRow6, CRow7
        ASSERT high CRowMakers == high (CRowMakers + 15)
; The Spectrum's keyboard on the CPC's: per half-row (from $FE's bit 0) its
; five keys (from bit 0), each a CPC line and its bit
CRow0:  ld l, $FF               ; CAPS (SHIFT) Z X C V
        KEYBIT 2, $20, 0
        KEYBIT 8, $80, 1
        KEYBIT 7, $80, 2
        KEYBIT 7, $40, 3
        KEYBIT 6, $80, 4
        ld a, l
        ret
CRow1:  ld l, $FF               ; A S D F G
        KEYBIT 8, $20, 0
        KEYBIT 7, $10, 1
        KEYBIT 7, $20, 2
        KEYBIT 6, $20, 3
        KEYBIT 6, $10, 4
        ld a, l
        ret
CRow2:  ld l, $FF               ; Q W E R T
        KEYBIT 8, $08, 0
        KEYBIT 7, $08, 1
        KEYBIT 7, $04, 2
        KEYBIT 6, $04, 3
        KEYBIT 6, $08, 4
        ld a, l
        ret
CRow3:  ld l, $FF               ; 1 2 3 4 5
        KEYBIT 8, $01, 0
        KEYBIT 8, $02, 1
        KEYBIT 7, $02, 2
        KEYBIT 7, $01, 3
        KEYBIT 6, $02, 4
        ld a, l
        ret
CRow4:  ld l, $FF               ; 0 9 8 7 6
        KEYBIT 4, $01, 0
        KEYBIT 4, $02, 1
        KEYBIT 5, $01, 2
        KEYBIT 5, $02, 3
        KEYBIT 6, $01, 4
        ld a, l
        ret
CRow5:  ld l, $FF               ; P O I U Y
        KEYBIT 3, $08, 0
        KEYBIT 4, $04, 1
        KEYBIT 4, $08, 2
        KEYBIT 5, $04, 3
        KEYBIT 5, $08, 4
        ld a, l
        ret
CRow6:  ld l, $FF               ; ENTER (RETURN) L K J H
        KEYBIT 2, $04, 0
        KEYBIT 4, $10, 1
        KEYBIT 4, $20, 2
        KEYBIT 5, $20, 3
        KEYBIT 5, $10, 4
        ld a, l
        ret
CRow7:  ld l, $FF               ; SPACE SYMBOL (CONTROL) M N B
        KEYBIT 5, $80, 0
        KEYBIT 2, $80, 1
        KEYBIT 4, $40, 2
        KEYBIT 5, $40, 3
        KEYBIT 6, $40, 4
        ld a, l
        ret

