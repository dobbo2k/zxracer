#!/usr/bin/env python3
"""Original tunes for ZX Racer, and their encoding for src/music.asm.

A tune is three channels on the AY: drums (channel A), bass (B) and melody
(C), written in sections. A section has a bass pattern (the bass follows each
bar's chord with it), a one-bar drum pattern (sixteenths: K kick, S snare,
H hi-hat, O open hi-hat, T tom, - nothing) with a fill for its last bar, and
per bar a chord and the melody. Melody tokens, lengths in sixteenths:
  E5:4      a note            /E5:4  slide into it    //E5:4  a slower slide
  -:4       a rest            =:4    the last note goes on
  @A5.m:8   an arpeggio: the chord (quality after the dot: '' major, m, 7,
            m7, maj7, sus4, 5 power, 8 octave) rooted on A5, cycling fast
  !1        envelope: 0 pluck, 1 sustained lead, 2 soft (no length)
Long melody notes get vibrato (the player starts it a little into a note).

Encoding, per channel (a byte stream, looping):
  $00         rest for the current length
  $01-$5E     note (1 = C2 ... 60 = B6) for the current length (drums:
              1 kick, 2 snare, 3 hi-hat, 4 tom, 5 open hi-hat)
  $5F         tie: the note goes on for the current length
  $60-$9F     current length = byte - $5F (1-64 interrupts)
  $A0+n       arpeggio n (src/music.asm ArpTab; 0: off)
  $B0+n       envelope n (EnvTab)
  $C0+s       the next note slides in over 2^s interrupts
  $D0+s       vibrato depth: period >> s (0: off)
  $FF         back to the start
Tune: dw bass, melody, drums.

usage: make_music.py out.asm       (the title tune; theme tunes go into
                                    the theme packs via make_stages.py)
"""
import re
import sys

NAMES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7,
         "G#": 8, "A": 9, "A#": 10, "B": 11}
FIRST_OCTAVE = 2                    # note 1 = C2
NOTES = 60                          # C2 .. B6
AY_CLOCK = 1773400
ARPS = {"": 1, "m": 2, "7": 3, "m7": 4, "maj7": 5, "sus4": 6, "5": 7, "8": 8}
DRUM_IDS = {"K": 1, "S": 2, "H": 3, "T": 4, "O": 5}
LEAD_VIB = 6                        # melody vibrato depth: period >> 6
ENV_BASS, ENV_HEAVY = 3, 4


def note_index(name):
    """'C#5' -> 1-based index (C2 = 1)."""
    pitch, octave = name[:-1], int(name[-1])
    n = (octave - FIRST_OCTAVE) * 12 + NAMES[pitch] + 1
    assert 1 <= n <= NOTES, name
    return n


def periods():
    """AY tone periods for notes 1..NOTES (equal temperament, A4 = 440 Hz)."""
    out = []
    for n in range(1, NOTES + 1):
        midi = 12 * (FIRST_OCTAVE + 1) + n - 1          # C2 = MIDI 36
        f = 440 * 2 ** ((midi - 69) / 12)
        out.append(round(AY_CLOCK / (16 * f)))
    return out


def chord_parts(chord):
    """'Am7' -> (root name, minor?)"""
    root = chord[:2] if len(chord) > 1 and chord[1] == "#" else chord[:1]
    rest = chord[len(root):]
    return root, rest.startswith("m") and not rest.startswith("maj")


# Bass patterns: per bar, (interval above the root - 'T' the chord's third -,
# sixteenths, slide in)
BASS = {
    "drive":   [(0, 2), (0, 2), (0, 2), (12, 2), (0, 2), (0, 2), (7, 2), (12, 2)],
    "gallop":  [(0, 2), (0, 1), (0, 1), (0, 2), (12, 2), (0, 2), (0, 1), (0, 1), (7, 2), (12, 2)],
    "pump":    [(0, 2), (12, 2)] * 4,
    "boom":    [(0, 4), (7, 4), (12, 4), (7, 4)],
    "walk":    [(0, 4), ("T", 4), (7, 4), (12, 3), (10, 1)],
    "funk":    [(0, 2), (0, 1), (12, 1, 1), (0, 2), (10, 2), (0, 1), (0, 1), (12, 2, 1), (7, 2), (10, 2)],
    "slap":    [(0, 1), (0, 1), (12, 2, 1), (0, 1), (12, 1), (0, 2), (7, 2), (0, 1), (12, 1, 1), (10, 2), (12, 2)],
    "epic":    [(0, 8), (7, 4), (12, 4, 2)],
}

# Drum patterns (one bar) and fills
DRUMS = {
    "rock":  "K-H-S-H-K-KHS-H-",
    "drive": "K-HHS-HHK-HHS-HK",
    "funk":  "K--HS-HKK-HHS-OH",
    "disco": "K-OHS-OHK-OHS-OH",
    "epic":  "K---S---K-K-S---",
    "half":  "K-H-S-H-K-H-S-HH",
}
FILL = "K-H-S-H-S-SSS-SS"
TOMS = "S-S-T-T-TTT-TTSS"
ROLL = "TTT-TT-TT-TTSSSS"

# The tunes: interrupts per sixteenth, sections of
# (bass pattern, bass envelope, drums, fill, bars of (chord, melody))
TUNES = {
    # bright pop with a funky bass, C major
    "coast": (6, [
        ("funk", ENV_BASS, "rock", FILL, [
            ("C", "E5:3 G5:3 /C6:2 B5:2 G5:2 E5:4"),
            ("G", "D5:3 G5:3 /B5:2 A5:2 G5:2 D5:4"),
            ("Am", "C5:3 E5:3 /A5:2 G5:2 E5:2 C5:4"),
            ("F", "A4:2 C5:2 F5:4 E5:2 F5:2 !1 /A5:4 !0"),
            ("C", "G5:4 E5:2 G5:2 /C6:4 B5:2 A5:2"),
            ("G", "B5:4 G5:2 D5:2 !1 //G5:6 !0 -:2"),
            ("F", "A5:2 G5:2 F5:2 E5:2 F5:2 A5:2 C6:4"),
            ("G", "@G5.:4 @G5.:4 @G5.7:8"),
        ]),
        ("slap", ENV_BASS, "disco", TOMS, [
            ("Am", "A5:4 /C6:4 B5:2 A5:2 E5:4"),
            ("F", "F5:4 /A5:4 G5:2 F5:2 C5:4"),
            ("C", "@C5.:4 @C5.:4 @E5.m:4 @G5.:4"),
            ("G", "!1 //D6:8 B5:4 G5:4 !0"),
            ("Am", "C6:4 B5:2 A5:2 E5:4 A5:4"),
            ("F", "F5:4 A5:2 C6:2 /F6:4 E6:4"),
            ("G", "G5:2 A5:2 B5:2 D6:2 B5:2 A5:2 G5:4"),
            ("G", "@G5.sus4:8 @G5.:8"),
        ]),
        ("epic", ENV_HEAVY, "epic", ROLL, [
            ("F", "!1 //A5:8 C6:4 F6:4"),
            ("G", "//G6:8 F6:4 D6:4"),
            ("Em", "//E6:8 D6:4 B5:4"),
            ("Am", "@A5.m:8 @G5.:8 !0"),
        ]),
    ]),
    # driving rock-funk, A minor
    "desert": (5, [
        ("gallop", ENV_BASS, "drive", FILL, [
            ("Am", "@A4.5:4 @A4.5:4 @A4.5:2 -:2 @C5.5:4"),
            ("Am", "@A4.5:4 @A4.5:4 @G4.5:4 @E4.5:4"),
            ("G", "@G4.5:4 @G4.5:4 @G4.5:2 -:2 @B4.5:4"),
            ("G", "@G4.5:4 @F4.5:4 @E4.5:8"),
        ]),
        ("drive", ENV_BASS, "drive", FILL, [
            ("Am", "A4:2 C5:2 D5:2 /E5:6 G5:2 E5:2"),
            ("Am", "D5:2 C5:2 !1 //A4:8 !0 -:4"),
            ("G", "G4:2 B4:2 D5:2 /G5:6 A5:2 G5:2"),
            ("G", "E5:2 D5:2 !1 //B4:8 !0 -:4"),
            ("F", "F5:4 E5:2 D5:2 C5:4 D5:2 E5:2"),
            ("F", "F5:2 G5:2 !1 /A5:8 !0 G5:4"),
            ("G", "G5:4 F5:2 E5:2 D5:4 B4:4"),
            ("E", "@E5.:8 /G#5:4 B5:4"),
        ]),
        ("epic", ENV_HEAVY, "epic", ROLL, [
            ("F", "!1 //A5:8 C6:4 A5:4"),
            ("G", "//B5:8 D6:4 B5:4"),
            ("Am", "//C6:12 =:4"),
            ("Am", "@A5.m:8 @A5.m:4 E6:4"),
            ("F", "F6:4 E6:4 D6:4 C6:4"),
            ("G", "D6:4 C6:4 B5:4 G5:4"),
            ("E", "//G#5:8 B5:4 D6:4"),
            ("E", "@E5.:8 @E5.:4 !0 E6:4"),
        ]),
    ]),
    # fast and heroic, E minor
    "alpine": (5, [
        ("pump", ENV_BASS, "epic", TOMS, [
            ("Em", "@E5.m:16"),
            ("C", "@C5.:16"),
            ("D", "@D5.:16"),
            ("B", "@B4.:8 @B4.7:8"),
        ]),
        ("pump", ENV_BASS, "half", TOMS, [
            ("Em", "E5:2 F#5:2 G5:2 B5:2 /E6:4 D6:2 B5:2"),
            ("C", "C6:4 B5:2 G5:2 E5:4 G5:4"),
            ("D", "F#5:2 A5:2 /D6:4 C6:2 A5:2 F#5:4"),
            ("B", "D#5:4 F#5:4 !1 //B5:8 !0"),
            ("Em", "G5:2 F#5:2 E5:2 G5:2 B5:4 /E6:4"),
            ("C", "E6:2 D6:2 C6:2 B5:2 !1 //G5:8 !0"),
            ("Am", "A5:2 C6:2 /E6:4 D6:2 C6:2 A5:4"),
            ("B", "@B4.7:8 /D#6:4 F#6:4"),
        ]),
        ("epic", ENV_HEAVY, "epic", ROLL, [
            ("C", "!1 //G5:8 C6:4 E6:4"),
            ("D", "//F#6:8 E6:4 D6:4"),
            ("Em", "//E6:12 =:4"),
            ("Em", "@E5.m:8 @E5.m:4 B5:4"),
            ("C", "C6:4 E6:4 G6:4 E6:4"),
            ("D", "/F#6:4 D6:4 A5:4 D6:4"),
            ("B", "//D#6:8 F#6:4 B6:4"),
            ("B", "@B4.:8 @B4.7:8 !0"),
        ]),
    ]),
    # upbeat and lush, G major
    "country": (5, [
        ("walk", ENV_BASS, "half", FILL, [
            ("G", "B4:4 D5:4 !1 /G5:6 !0 F#5:2"),
            ("Em", "E5:4 G5:4 !1 //B5:8 !0"),
            ("C", "C6:4 B5:2 A5:2 G5:4 E5:4"),
            ("D", "F#5:4 A5:4 @D5.:8"),
            ("G", "G5:2 A5:2 B5:4 /D6:4 B5:4"),
            ("Em", "G5:4 E5:4 B4:4 E5:4"),
            ("C", "E5:2 F#5:2 G5:4 A5:4 C6:4"),
            ("D", "@D5.:4 @D5.sus4:4 @D5.:8"),
        ]),
        ("drive", ENV_BASS, "disco", TOMS, [
            ("C", "E5:4 G5:4 !1 /C6:6 !0 B5:2"),
            ("G", "B5:4 G5:4 !1 //D5:8 !0"),
            ("D", "F#5:4 A5:4 /D6:6 C6:2"),
            ("Em", "B5:4 G5:4 @E5.m:8"),
            ("C", "C5:2 E5:2 G5:4 /C6:4 E6:4"),
            ("G", "!1 //D6:8 B5:4 G5:4 !0"),
            ("D", "A5:2 B5:2 C6:2 B5:2 A5:4 F#5:4"),
            ("D", "@D5.:8 @D5.7:8"),
        ]),
    ]),
    # night-time funk on sevenths, D dorian
    "sunset": (6, [
        ("slap", ENV_BASS, "funk", FILL, [
            ("Dm7", "@D5.m7:2 -:2 @D5.m7:1 -:3 @D5.m7:2 -:2 /A5:2 C6:2"),
            ("G7", "@G4.7:2 -:2 @G4.7:1 -:3 @G4.7:2 -:2 /B5:2 D6:2"),
            ("Dm7", "@D5.m7:2 -:2 @D5.m7:1 -:3 @D5.m7:2 -:2 /A5:2 C6:2"),
            ("G7", "@G4.7:2 -:2 @G4.7:1 -:3 /F6:4 E6:2 D6:2"),
        ]),
        ("funk", ENV_BASS, "funk", TOMS, [
            ("Dm7", "F5:3 A5:3 /C6:2 =:2 A5:2 G5:2 F5:2"),
            ("G7", "/B5:2 D6:2 F6:6 E6:2 D6:2 B5:2"),
            ("Cmaj7", "!1 //E6:8 D6:2 C6:2 B5:2 G5:2"),
            ("Am7", "C6:3 A5:3 E5:2 !0 G5:2 A5:2 C6:4"),
            ("Dm7", "D6:2 C6:2 A5:2 F5:2 /A5:4 C6:4"),
            ("G7", "B5:3 G5:3 F5:2 D5:4 -:4"),
            ("Em7", "G5:2 B5:2 /D6:4 E6:4 D6:4"),
            ("A7", "!1 //C#6:8 @A4.7:8 !0"),
        ]),
        ("slap", ENV_HEAVY, "disco", ROLL, [
            ("Dm7", "@D5.m7:4 @D5.m7:4 /A6:4 F6:4"),
            ("G7", "@G5.7:4 @G5.7:4 /G6:4 F6:4"),
            ("Cmaj7", "!1 //E6:12 D6:4"),
            ("Am7", "C6:4 B5:4 A5:4 G5:4 !0"),
            ("Dm7", "F6:2 E6:2 D6:2 C6:2 A5:2 C6:2 D6:4"),
            ("G7", "/F6:4 D6:4 B5:4 G5:4"),
            ("Em7", "@E5.m7:8 /G6:8"),
            ("A7", "!1 //A6:12 -:4 !0"),
        ]),
    ]),
    # the title: an anthem
    "title": (6, [
        ("epic", ENV_HEAVY, "epic", ROLL, [
            ("F", "@F5.:16"),
            ("G", "@G5.:16"),
            ("Em", "@E5.m:16"),
            ("Am", "@A5.m:8 @A5.m7:8"),
        ]),
        ("drive", ENV_BASS, "rock", TOMS, [
            ("F", "A5:4 C6:4 /F6:4 E6:2 C6:2"),
            ("G", "!1 //D6:6 !0 B5:2 G5:8"),
            ("Em", "G5:2 B5:2 /E6:4 D6:4 B5:4"),
            ("Am", "C6:4 A5:4 !1 //E5:8 !0"),
            ("F", "F5:2 A5:2 C6:2 F6:2 /E6:4 C6:4"),
            ("G", "D6:4 /G6:4 F6:2 E6:2 D6:4"),
            ("C", "!1 //E6:8 D6:4 C6:4"),
            ("C", "@C5.:8 @C5.maj7:8 !0"),
        ]),
    ]),
}

TOKEN = re.compile(r"^(/{0,2})(@?)([A-G]#?\d|-|=)(?:\.(\w*))?:(\d+)$")


def bars_of(tune):
    return [bar for sec in TUNES[tune][1] for bar in sec[4]]


def events(tune):
    """-> (bass, melody, drums): lists of events (kind, ...)."""
    tick, sections = TUNES[tune]
    bass = [("vib", 0)]
    melody = [("env", 0), ("vib", LEAD_VIB)]
    drums = []
    for pattern, env, dpat, fill, bars in sections:
        bass.append(("env", env))
        for k, (chord, line) in enumerate(bars):
            root, minor = chord_parts(chord)
            base = note_index(root + "2")
            for step in BASS[pattern]:
                iv, length = step[0], step[1]
                if iv == "T":
                    iv = 3 if minor else 4
                bass.append(("note", base + iv, length * tick, step[2] if len(step) > 2 else 0, 0))
            total = 0
            for tok in line.split():
                if tok.startswith("!"):
                    melody.append(("env", int(tok[1:])))
                    continue
                m = TOKEN.match(tok)
                assert m, (tune, tok)
                slide, arp, name, quality, length = m.groups()
                length = int(length)
                total += length
                ticks = length * tick
                if name == "-":
                    melody.append(("rest", ticks))
                elif name == "=":
                    melody.append(("tie", ticks))
                else:
                    melody.append(("note", note_index(name), ticks, len(slide) + (1 if slide else 0),
                                   ARPS[quality or ""] if arp else 0))
            assert total == 16, (tune, chord, line, total)
            bar = DRUMS[dpat] if k < len(bars) - 1 or not fill else fill
            assert len(bar) == 16, bar
            for ch in bar:
                if ch == "-":
                    if drums:
                        drums[-1] = ("drum", drums[-1][1], drums[-1][2] + tick)
                    else:
                        drums.append(("drum", 0, tick))
                else:
                    drums.append(("drum", DRUM_IDS[ch], tick))
    return bass, melody, drums


def encode(evs):
    out, cur_len, arp_on = [], None, 0

    def length(n):
        nonlocal cur_len
        if n != cur_len:
            out.append(0x5F + n)
            cur_len = n

    def timed(first, ticks, cont=0x5F):
        f = True
        while ticks > 0:
            n = min(ticks, 64)
            length(n)
            out.append(first if f else cont)
            f = False
            ticks -= n

    for ev in evs:
        kind = ev[0]
        if kind == "env":
            out.append(0xB0 + ev[1])
        elif kind == "vib":
            out.append(0xD0 + ev[1])
        elif kind == "rest":
            timed(0, ev[1], 0)
        elif kind == "tie":
            timed(0x5F, ev[1])
        elif kind == "drum":
            timed(ev[1], ev[2], 0)
        else:
            _, note, ticks, slide, arp = ev
            if arp != arp_on:
                out.append(0xA0 + arp)
                arp_on = arp
            if slide:
                out.append(0xC0 + slide)
            timed(note, ticks)
    if arp_on:
        out.append(0xA0)
    out.append(0xFF)
    return out


def tune_asm(tune, label):
    """Assembler lines for a tune: label: dw bass, melody, drums; the data."""
    lines = [f"{label}:", f"        dw {label}_b, {label}_m, {label}_d"]
    for suffix, evs in zip(("_b", "_m", "_d"), events(tune)):
        data = encode(evs)
        lines.append(f"{label}{suffix}:")
        for i in range(0, len(data), 16):
            lines.append("        db " + ", ".join(f"${b:02X}" for b in data[i:i + 16]))
    return lines


def tune_bytes(tune):
    return 6 + sum(len(encode(evs)) for evs in events(tune))


def main(out):
    lines = ["; Generated by tools/make_music.py - do not edit"]
    lines += tune_asm("title", "TitleTune")
    open(out, "w").write("\n".join(lines) + "\n")
    notes = ["; Generated by tools/make_music.py - do not edit"]
    p = periods()
    for i in range(0, len(p), 8):
        notes.append("        dw " + ", ".join(str(v) for v in p[i:i + 8]))
    open(out.replace("music_title.asm", "music_notes.asm"), "w").write("\n".join(notes) + "\n")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--sizes":
        for t in TUNES:
            print(t, tune_bytes(t), "bytes,", len(bars_of(t)), "bars")
    else:
        main(sys.argv[1] if len(sys.argv) > 1 else "build/music_title.asm")
