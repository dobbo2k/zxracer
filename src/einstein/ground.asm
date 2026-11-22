; Two reserved bottom-third patterns add low-contrast detail to the verge.
GROUND_PAT      EQU KERB_T2 + KERB_N
        ASSERT GROUND_PAT + 2 <= CAR_PAT

EinGroundInit:
        ld hl, EGroundPatterns
        ld de, VRAM_PAT + $1000 + GROUND_PAT * 8
        ld b, 16
        call VdpWrite
        ld de, VRAM_COL + $1000 + GROUND_PAT * 8
        ld b, 16
        jp VdpWrite

; A = solid paper. Substitute only on open road in the bottom third.
EinGroundName:
        push hl
        ld hl, ERow
        bit 3, (hl)
        jr nz, .near
        bit 2, (hl)
        jr z, .end
.near:  ld hl, ERBand
        bit 7, (hl)
        jr nz, .end
        ld hl, EGroundPapers
        cp (hl)
        jr nz, .dark
        ld a, GROUND_PAT
        jr .end
.dark:  inc hl
        cp (hl)
        jr nz, .end
        ld a, GROUND_PAT + 1
.end:   pop hl
        ret

; A = name. Recover the paper underneath a car or roadside object.
EinGroundPaper:
        cp GROUND_PAT
        ret c
        jr z, .light
        cp GROUND_PAT + 1
        ret nz
        ld a, (EGroundPapers + 1)
        ret
.light: ld a, (EGroundPapers)
        ret
