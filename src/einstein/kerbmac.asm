; ---------------------------------------------------------------------------
; Einstein, -DEIN_KERB (a prototype): src/einstein/kerbrow.asm's macros,
; assembled first (src/einstein/kerbcell.asm, below $4000, uses them too).
; ---------------------------------------------------------------------------

; The line groups a cell's kerb is made from: 4 line pairs (2-line steps),
; or with -DEIN_KERB4 lines 0 and 4 only (4-line steps: each group's byte
; on 4 lines)
        IFDEF EIN_KERB4
KPAIRS          EQU 2
KSTEP           EQU 4
        ELSE
KPAIRS          EQU 4
KSTEP           EQU 2
        ENDIF
KALL            EQU (1 << KPAIRS) - 1   ; (every group over road)

; Group k (its line C; C on KSTEP): L, D, E, R into EKP; B the least L, IXL
; the most D, IXH the least E, IYL the most R (group 0 sets them).
        MACRO KLOAD k
        ld l, c
        ld h, high DEPage
        ld d, (hl)              ; D
        set 7, l
        ld e, (hl)              ; E
        res 7, l
        ld h, high SrcLine      ; the kerb's width: the depth line shown's
        ld a, (hl)
        or $80
        ld l, a
        ld h, high RoadRW
        ld a, d
        ld (EKP + 4 + k), a
        IF k == 0
        ld ixl, a
        ELSE
        cp ixl
        jr c, $ + 4
        ld ixl, a
        ENDIF
        sub (hl)                ; L = D - RW (at least 0)
        jr nc, $ + 3
        xor a
        ld (EKP + k), a
        IF k == 0
        ld b, a
        ELSE
        cp b
        jr nc, $ + 3
        ld b, a
        ENDIF
        ld a, e
        ld (EKP + 8 + k), a
        IF k == 0
        ld ixh, a
        ELSE
        cp ixh
        jr nc, $ + 4
        ld ixh, a
        ENDIF
        add a, (hl)             ; R = E + RW (at most 255)
        jr nc, $ + 4
        ld a, 255
        ld (EKP + 12 + k), a
        IF k == 0
        ld iyl, a
        ELSE
        cp iyl
        jr c, $ + 4
        ld iyl, a
        ENDIF
        DUP KSTEP
        inc c
        EDUP
        ENDM

; Store the group's byte. Four-line kerbs keep it compact until commit.
; B gets a bit (set: over road); in 2-line steps D the AND of the bytes, E
; the OR (4-line steps: EinKerbCell works them out from EKPattern).
        MACRO KPUT k
        IFDEF EIN_KERB4
        ld (EKPattern + k), a
        rl b
        ELSE
        ld (EPat + 2 * k), a
        ld (EPat + 2 * k + 1), a
        rl b
        ld l, a
        and d
        ld d, a
        ld a, l
        or e
        ld e, a
        ENDIF
        ENDM

; The left run: road from D (kerb left of it, and grass as kerb), or no
; road in the cell: kerb from L
        MACRO KLEFT k
        ld a, (EKP + 4 + k)
        sub c
        ld l, a
        ld a, (hl)
        or a
        jr z, $ + 6
        cpl
        scf
        jr $ + 9
        ld a, (EKP + k)
        sub c
        ld l, a
        ld a, (hl)
        or a
        KPUT k
        ENDM

; The right run: road to E (kerb right of it, and grass as kerb), or no
; road in the cell: kerb to R
        MACRO KRIGHT k
        ld a, (EKP + 8 + k)
        sub c
        inc a
        ld l, a
        ld a, (hl)
        inc a
        jr z, $ + 6
        dec a
        scf
        jr $ + 11
        ld a, (EKP + 12 + k)
        sub c
        inc a
        ld l, a
        ld a, (hl)
        cpl
        or a
        KPUT k
        ENDM

; A = a pixel -> A = its cell
        MACRO KCELL
        rrca
        rrca
        rrca
        and 31
        ENDM
