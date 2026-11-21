; ---------------------------------------------------------------------------
; Einstein: the stage packs from the disc (STAGES.DAT, tools/make_einstein.py)
;
; Read through XtalDOS's BDOS (CP/M: open, then random-access reads of 128-
; byte records), as the Wonder Boy port reads its rounds. The BDOS needs
; MOS's own interrupts to time the disc (the motor, the timeouts), so for
; each read the machine goes back to MOS's set-up: I = $FB (its vector
; table at $FB00), the CTC's vector base 0, channel 2 a timer and channel 3
; its clock (Mos12.zsm ZZTIME), interrupts on just for the BDOS call; then
; back to the game's (InitInterrupts). The BDOS pages the MOS ROM over
; $0000-$1FFF while it works, so this code, the FCB and the stack are all
; above $2000. The file is opened once (an open takes a second or two).
; MOS may touch the VDP meanwhile: a stage load is always followed by
; EinResetDisplay, which sets it all up again.
; ---------------------------------------------------------------------------
BDOS            EQU $0005
BDOS_OPEN       EQU 15
BDOS_SET_DMA    EQU 26
BDOS_READ_RANDOM EQU 33
FCB_RANDOM      EQU 33
MOS_I           EQU $FB

; HL = first record, DE = destination, BC = bytes: read them (src/stage.asm
; CopyFromBank and src/stageov.asm CopyToCache on the Einstein). Whole
; records straight in, the last part of one through ERecBuf: no byte past
; the length is written (a track pack ends at $8000). A read that fails is
; tried again; the disc must be there.
EinRead:
        ld a, b
        or c
        ret z
        push hl                 ; a cache that holds these records already
        ld hl, THEME_CACHE      ; (the theme's or the track's): nothing to read
        or a
        sbc hl, de
        ld ix, ELastTheme
        jr z, .cached
        ld hl, TRACK_CACHE
        or a
        sbc hl, de
        ld ix, ELastTrack
        jr z, .cached
        pop hl
        jr .read
.cached:
        pop hl
        ld a, (ix + 0)
        cp l
        jr nz, .new
        ld a, (ix + 1)
        cp h
        ret z
.new:   ld (ix + 0), l
        ld (ix + 1), h
.read:  push bc
        push de
        push hl
        call EinMosMode
        ld a, (EFileOpen)
        or a
        call z, EinOpen
        pop hl
        pop de
        pop bc
.rec:   push bc
        push de
        push hl
        ld a, b                 ; less than a record left: into ERecBuf
        or a
        jr nz, .again
        ld a, c
        cp 128
        jr nc, .again
        ld de, ERecBuf
.again: ld (EDma), de           ; (kept: a retry needs it, the BDOS may not)
        ld (EFcb + FCB_RANDOM), hl
        xor a
        ld (EFcb + FCB_RANDOM + 2), a
        push hl
        ld de, (EDma)
        ld c, BDOS_SET_DMA
        call EinBdos
        ld c, BDOS_READ_RANDOM
        ld de, EFcb
        call EinBdos
        pop hl
        or a
        jr z, .ok
        ld de, (EDma)
        jr .again
.ok:    pop hl
        pop de
        pop bc
        ld a, b                 ; the last part: from ERecBuf
        or a
        jr nz, .whole
        ld a, c
        cp 128
        jr nc, .whole
        ld hl, ERecBuf
        ldir
        jp EinGameMode
.whole: inc hl                  ; the next record, 128 bytes on
        ld a, e
        add a, 128
        ld e, a
        jr nc, .d
        inc d
.d:     ld a, c
        sub 128
        ld c, a
        jr nc, .n
        dec b
.n:     ld a, b
        or c
        jr nz, .rec
        jp EinGameMode

; Open STAGES.DAT (tried until it opens)
EinOpen:
        ld hl, EFcb
        ld b, 36
.clr:   ld (hl), 0
        inc hl
        djnz .clr
        ld hl, EFcbName
        ld de, EFcb + 1
        ld bc, 11
        ldir
        ld c, BDOS_OPEN
        ld de, EFcb
        call EinBdos
        inc a                   ; $FF: not found
        jr z, EinOpen
        ld a, 1
        ld (EFileOpen), a
        ret

; C = function, DE = its argument: the BDOS, with MOS's interrupts on
EinBdos:
        ei
        call BDOS
        di
        ret

; MOS's interrupts (interrupts off)
EinMosMode:
        di
        ld a, MOS_I
        ld i, a
        xor a
        out (EIN_CTC0), a       ; vector base 0
        ld a, $3F               ; channel 2: timer, /256, 125 (Mos12.zsm ZZTIME)
        out (EIN_CTC2), a
        ld a, $7D
        out (EIN_CTC2), a
        ld a, $DF               ; channel 3: its interrupt, counting 125
        out (EIN_CTC3), a
        ld a, $7D
        out (EIN_CTC3), a
        ret

; The game's again (src/interrupt.asm InitInterrupts), interrupts on
EinGameMode:
        di
        ld a, high IM2_TABLE
        ld i, a
        call EinCtcInit
        ei
        ret

ELastTheme:     dw $FFFF        ; the first records the caches hold
ELastTrack:     dw $FFFF
EFcbName:       db "STAGES  DAT"
EFileOpen:      db 0
EFcb:           ds 36
ERecBuf:        ds 128          ; a last part-record
EDma:           dw 0
