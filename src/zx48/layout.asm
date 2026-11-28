; The screen at $4000-$5AFF also serves as decoder scratch between rounds.
; $5B00-$7D9F holds resident graphics and code, with the track cache above.
; $8000-$BFFF holds the engine, aligned tables, interrupt vectors and stack.
; Everything from $C000 upwards is either immutable archive or active art.
        ORG $C000
ArchiveStart:
        INCLUDE "zx48_archive.asm"
ArchiveDataEnd:
        INCLUDE "options.asm"
        INCLUDE "audio.asm"
ArchiveEnd:
        ASSERT ArchiveEnd <= $10000
        SAVEBIN "build/zx48/speedrun.bin", TapeEntry, ArchiveEnd - TapeEntry
        SAVEBIN "build/zx48/resident.bin", SCN_DATA, ScnEnd - SCN_DATA
        SAVESNA "build/zx48/speedrun.sna", start

SharedSprites   EQU ScnEnd
SharedSpritesEnd EQU SharedSprites + SHARED_SPRITES_SIZE
        ASSERT SharedSpritesEnd <= TRACK_CACHE
        ASSERT SharedSprites + 2048 <= $8000 ; title block including attributes
        ORG ArchiveEnd
ThemeSprites:   ds THEME_SPRITES_SIZE
ThemeSpritesEnd:
        ALIGN 32
PANO_CACHE:     ds 512
CacheEnd:
        ASSERT CacheEnd <= $FFFE
