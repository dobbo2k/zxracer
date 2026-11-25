; ---------------------------------------------------------------------------
; CPC: the disc drive read by the game itself, the firmware gone (from the
; Wonder Boy port's src/platform/cpc/fdc.asm): the uPD765 controller at
; $FB7E (its main status) and $FB7F (data), the motor at $FA7E. Drive A,
; side 0, AMSDOS's DATA format (tools/cpc/make_dsk.py): 9 sectors of 512
; bytes a track, numbered $C1-$C9. Polled, interrupts off while a sector
; is read: the controller hands a byte over every 32 us.
;
; The CPC does not wire the controller's terminal count, so a read always
; ends "abnormally" at its end-of-track sector (ST0 $40, ST1 $80): that is
; success here, any other error bit is not.
;
; Included by the game (src/cpc/disc.asm) and by the disc's loader
; (src/cpc/loader.asm): each gives FdcFailed and FdcRecovered.
; ---------------------------------------------------------------------------

FDC_STATUS      EQU $FB7E
FDC_READ        EQU $46         ; read data: MFM, one side
FDC_SEEK        EQU $0F
FDC_RECALIBRATE EQU $07
FDC_SENSE       EQU $08         ; sense interrupt status
FDC_TRIES       EQU 8
FDC_FIRST_ID    EQU $C1
FDC_SECTORS     EQU 9

; The motor on and about a second for it to come up to speed (if it was
; off); the head to track 0 the first time
FdcStart:
        ld a, (FdcMotor)
        or a
        ret nz
        inc a
        ld (FdcMotor), a
        ld bc, $FA7E
        out (c), a
        ld de, 0                ; 2 x 65,536 x 7 us: about 0.9 s
        ld h, 2
.wait:  dec de
        ld a, d
        or e
        jr nz, .wait
        dec h
        jr nz, .wait
        ld a, (FdcTrack)
        inc a
        ret nz                  ; (where the head is, known)
FdcRecalibrate:                 ; the head to track 0
        ld a, FDC_RECALIBRATE
        call FdcPut
        xor a                   ; drive 0
        call FdcPut
        call FdcSeekEnd
        xor a
        ld (FdcTrack), a
        ret

; The motor off
FdcStop:
        xor a
        ld (FdcMotor), a
        ld bc, $FA7E
        out (c), a
        ret

; D = track, E = sector number ($C1-$C9), HL = where its 512 bytes go: read,
; HL past them. Carry set if read; tried FDC_TRIES times, the head
; recalibrated after a failure. A, BC used; DE kept. Failing, FdcFailed is
; called, and FdcRecovered at the next sector read; each keeps DE and HL.
FdcReadSector:
        ld a, FDC_TRIES
        ld (FdcTries), a
.again: push hl                 ; (where: for a retry)
        ld a, (FdcTrack)
        cp d
        jr z, .onTrack
        push de
        call FdcSeek
        pop de
.onTrack:
        pop hl
        push hl
        di
        ld a, FDC_READ
        call FdcPut
        xor a                   ; drive 0, side 0
        call FdcPut
        ld a, d                 ; C, H, R, N
        call FdcPut
        xor a
        call FdcPut
        ld a, e
        call FdcPut
        ld a, 2
        call FdcPut
        ld a, e                 ; EOT: this sector alone
        call FdcPut
        ld a, $2A               ; GPL
        call FdcPut
        ld a, $FF               ; DTL
        call FdcPut
        ld bc, FDC_STATUS
.byte:  in a, (c)
        jp p, .byte             ; RQM not yet
        and $20                 ; EXM: still the data phase?
        jr z, .done
        inc c
        in a, (c)
        ld (hl), a
        inc hl
        dec c
        jr .byte
.done:  push hl
        call FdcResults
        pop hl
        IFNDEF FDC_LOADER       ; (the loader: interrupts off throughout)
        ei
        ENDIF
        ld a, (FdcResult + 1)   ; ST1: missing marks, no data, overrun, CRC
        and $37
        ld c, a
        ld a, (FdcResult + 2)   ; ST2: CRC in the data, a wrong cylinder
        and $33
        or c
        ld c, a
        ld a, (FdcResult)       ; ST0: an invalid command, not ready
        and $88
        or c
        jr nz, .failed
        pop af                  ; (where it started: HL stays past the sector)
        ld a, (FdcFailing)
        or a
        jr z, .ok
        xor a
        ld (FdcFailing), a
        push de
        push hl
        call FdcRecovered
        pop hl
        pop de
.ok:    scf
        ret
.failed:
        pop hl                  ; the sector again
        ld a, (FdcTries)
        dec a
        ld (FdcTries), a
        jr nz, .retry
        inc a
        ld (FdcFailing), a
        push de
        push hl
        call FdcFailed
        pop hl
        pop de
        or a                    ; (carry clear)
        ret
.retry: push hl
        push de
        call FdcRecalibrate
        pop de
        pop hl
        jp .again

; HL = a logical sector (track x 9 + sector - $C1) -> D = its track, E its
; number ($C1-$C9). A, BC, HL used.
FdcPlace:
        ld d, 0
.track: ld e, l
        ld bc, -FDC_SECTORS
        add hl, bc
        jr nc, .found
        inc d
        jr .track
.found: ld a, e                 ; (the remainder, before the last subtraction)
        add a, FDC_FIRST_ID
        ld e, a
        ret

; D, E = a sector's place -> the next one's. A used.
FdcNext:
        inc e
        ld a, e
        cp FDC_FIRST_ID + FDC_SECTORS
        ret c
        ld e, FDC_FIRST_ID
        inc d
        ret

; D = the track: the head moved there
FdcSeek:
        ld a, FDC_SEEK
        call FdcPut
        xor a
        call FdcPut
        ld a, d
        call FdcPut
        ld a, d
        ld (FdcTrack), a
; Waits for a seek or recalibration to end (sense interrupt status till it
; reports one)
FdcSeekEnd:
        ld a, FDC_SENSE
        call FdcPut
        call FdcResults
        ld a, (FdcResult)
        and $20                 ; seek end
        jr z, FdcSeekEnd
        ret

; A = a command byte, given when the controller asks for one. BC used.
FdcPut:
        push af
        ld bc, FDC_STATUS
.wait:  in a, (c)
        add a, a                ; RQM
        jr nc, .wait
        add a, a                ; DIO: it should be waiting for us
        jr c, .wait
        pop af
        inc c
        out (c), a
        ret

; The result phase read into FdcResult (up to 7 bytes). A, BC, HL used.
FdcResults:
        ld hl, FdcResult
        ld bc, FDC_STATUS
.wait:  in a, (c)
        add a, a                ; RQM
        jr nc, .wait
        add a, a                ; DIO: a byte for us, else done
        ret nc
        inc c
        in a, (c)
        dec c
        ld (hl), a
        inc hl
        ld a, l
        cp low (FdcResult + 7)
        jr nz, .wait
        ret

FdcTrack:       db $FF          ; the track the head is on ($FF: not known)
FdcMotor:       db 0            ; the motor on
FdcTries:       db 0
FdcFailing:     db 0            ; 1: the last sector would not read
FdcResult:      ds 7, 0         ; a command's result phase (ST0-ST2, C, H, R, N)
