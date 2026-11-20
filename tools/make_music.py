#!/usr/bin/env python3
"""Original tunes for ZX Racer, and their encoding for src/music.asm.

A tune is two channels on the AY: bass (channel B) and melody (channel C);
the engine keeps channel A. Each is written per bar: a chord (the bass line
follows it with the tune's bass pattern) and the melody as notes with
lengths in sixteenths.

Encoding, per channel (a byte stream, looping):
  $00         rest for the current length
  $01-$5E     note (1 = C2 ... 60 = B6) for the current length
  $5F         tie: the note goes on for the current length (no new attack)
  $60-$9F     current length = byte - $5F (1-64 interrupts)
  $FF         back to the start
Tune: dw bass, melody.

usage: make_music.py out.asm       (the title tune; theme tunes go into
                                    the theme packs via make_stages.py)
"""
import sys

NAMES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7,
         "G#": 8, "A": 9, "A#": 10, "B": 11}
FIRST_OCTAVE = 2                    # note 1 = C2
NOTES = 60                          # C2 .. B6
AY_CLOCK = 1773400


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


CHORD_ROOTS = {}                    # chord name -> bass root (octave 2)


def chord_root(chord):
    """'Am', 'G7', 'Cmaj7', 'F#m' -> root note name in octave 2."""
    root = chord[:2] if len(chord) > 1 and chord[1] == "#" else chord[:1]
    return root + "2"


# Bass patterns: per bar, (interval above the root, sixteenths)
BASS = {
    "eights":  [(0, 2), (0, 2), (12, 2), (0, 2), (0, 2), (7, 2), (12, 2), (7, 2)],
    "gallop":  [(0, 2), (0, 1), (0, 1), (0, 2), (12, 2), (0, 2), (0, 1), (0, 1), (7, 2), (12, 2)],
    "pump":    [(0, 2), (12, 2)] * 4,
    "boomchick": [(0, 4), (7, 4), (12, 4), (7, 4)],
    "funk":    [(0, 3), (0, 1), (12, 2), (0, 2), (7, 3), (0, 1), (10, 2), (12, 2)],
    "straight": [(0, 2), (0, 2), (12, 2), (0, 2), (0, 2), (0, 2), (12, 2), (0, 2)],
}

# The tunes: tempo (interrupts per sixteenth), bass pattern, and bars of
# (chord, melody). Melody: "NOTE:len" or "-:len" (rest), sixteenths.
TUNES = {
    # bright and breezy, C major
    "coast": (6, "eights", [
        ("C", "E5:3 G5:3 C6:2 B5:2 G5:2 E5:4"),
        ("G", "D5:3 G5:3 B5:2 A5:2 G5:2 D5:4"),
        ("Am", "C5:3 E5:3 A5:2 G5:2 E5:2 C5:4"),
        ("F", "A4:2 C5:2 F5:4 E5:2 F5:2 A5:4"),
        ("C", "G5:4 E5:2 G5:2 C6:4 B5:2 A5:2"),
        ("G", "B5:4 G5:2 D5:2 G5:6 -:2"),
        ("F", "A5:2 G5:2 F5:2 E5:2 F5:2 A5:2 C6:4"),
        ("G", "B5:4 A5:2 G5:2 D5:8"),
        ("Am", "A5:4 C6:4 B5:2 A5:2 E5:4"),
        ("F", "F5:4 A5:4 G5:2 F5:2 C5:4"),
        ("C", "E5:2 G5:2 C6:2 G5:2 E5:2 G5:2 C6:4"),
        ("G", "D6:4 B5:4 G5:4 D5:4"),
        ("Am", "C6:4 B5:2 A5:2 E5:4 A5:4"),
        ("F", "F5:4 A5:2 C6:2 A5:4 F5:4"),
        ("G", "G5:2 A5:2 B5:2 D6:2 B5:2 A5:2 G5:4"),
        ("G", "D5:4 G5:4 B5:8"),
    ]),
    # driving, A minor
    "desert": (5, "gallop", [
        ("Am", "A4:2 C5:2 D5:2 E5:6 G5:2 E5:2"),
        ("Am", "D5:2 C5:2 A4:8 -:4"),
        ("G", "G4:2 B4:2 D5:2 G5:6 A5:2 G5:2"),
        ("G", "E5:2 D5:2 B4:8 -:4"),
        ("F", "F5:4 E5:2 D5:2 C5:4 D5:2 E5:2"),
        ("F", "F5:2 G5:2 A5:8 G5:4"),
        ("G", "G5:4 F5:2 E5:2 D5:4 B4:4"),
        ("E", "E5:8 G#5:4 B5:4"),
        ("Am", "A5:4 G5:2 E5:2 A5:4 C6:4"),
        ("Am", "B5:2 A5:2 G5:2 E5:2 A5:8"),
        ("G", "G5:4 D5:2 G5:2 B5:4 D6:4"),
        ("G", "C6:2 B5:2 A5:2 G5:2 D5:8"),
        ("F", "A5:4 F5:2 A5:2 C6:4 A5:4"),
        ("F", "G5:2 F5:2 E5:2 C5:2 F5:8"),
        ("G", "D5:2 E5:2 F5:2 G5:2 A5:2 B5:2 C6:2 D6:2"),
        ("E", "E6:8 B5:4 G#5:4"),
    ]),
    # fast and bright in the cold, E minor
    "alpine": (5, "pump", [
        ("Em", "E5:2 F#5:2 G5:2 B5:2 E6:4 D6:2 B5:2"),
        ("C", "C6:4 B5:2 G5:2 E5:4 G5:4"),
        ("D", "F#5:2 A5:2 D6:4 C6:2 A5:2 F#5:4"),
        ("B", "D#5:4 F#5:4 B5:8"),
        ("Em", "G5:2 F#5:2 E5:2 G5:2 B5:4 E6:4"),
        ("C", "E6:2 D6:2 C6:2 B5:2 G5:8"),
        ("Am", "A5:2 C6:2 E6:4 D6:2 C6:2 A5:4"),
        ("B", "B5:4 A5:2 G5:2 F#5:4 D#5:4"),
        ("C", "G5:4 C6:4 E6:4 C6:4"),
        ("D", "F#5:4 A5:4 D6:8"),
        ("Em", "B5:2 A5:2 G5:2 F#5:2 E5:4 G5:4"),
        ("B", "F#5:4 B5:4 D#6:8"),
        ("C", "E6:4 D6:2 C6:2 G5:4 E5:4"),
        ("D", "F#5:2 G5:2 A5:2 B5:2 C6:4 D6:4"),
        ("Am", "E6:4 C6:2 A5:2 B5:4 G5:4"),
        ("B", "F#5:8 D#5:4 B4:4"),
    ]),
    # easy-going, G major
    "country": (7, "boomchick", [
        ("G", "B4:4 D5:4 G5:6 F#5:2"),
        ("Em", "E5:4 G5:4 B5:8"),
        ("C", "C6:4 B5:2 A5:2 G5:4 E5:4"),
        ("D", "F#5:4 A5:4 D5:8"),
        ("G", "G5:2 A5:2 B5:4 D6:4 B5:4"),
        ("Em", "G5:4 E5:4 B4:4 E5:4"),
        ("C", "E5:2 F#5:2 G5:4 A5:4 C6:4"),
        ("D", "B5:4 A5:4 F#5:4 D5:4"),
        ("C", "E5:4 G5:4 C6:6 B5:2"),
        ("G", "B5:4 G5:4 D5:8"),
        ("D", "F#5:4 A5:4 D6:6 C6:2"),
        ("Em", "B5:4 G5:4 E5:8"),
        ("C", "C5:2 E5:2 G5:4 C6:4 E6:4"),
        ("G", "D6:4 B5:4 G5:8"),
        ("D", "A5:2 B5:2 C6:2 B5:2 A5:4 F#5:4"),
        ("D", "D5:4 E5:4 F#5:4 A5:4"),
    ]),
    # night-time cruising, D minor sevenths
    "sunset": (6, "funk", [
        ("Dm7", "F5:3 A5:3 C6:2 A5:4 -:4"),
        ("G7", "B5:2 D6:2 F6:4 D6:2 B5:2 G5:4"),
        ("Cmaj7", "E6:6 D6:2 B5:4 G5:4"),
        ("Am7", "C6:3 A5:3 E5:2 G5:8"),
        ("Dm7", "D6:2 C6:2 A5:2 F5:2 A5:4 C6:4"),
        ("G7", "B5:3 G5:3 F5:2 D5:8"),
        ("Em7", "G5:2 B5:2 D6:4 E6:4 D6:4"),
        ("A7", "C#6:6 A5:2 E5:4 G5:4"),
        ("Dm7", "A5:4 F5:2 A5:2 D6:8"),
        ("G7", "F6:4 D6:2 B5:2 G5:8"),
        ("Cmaj7", "B5:2 C6:2 E6:4 G6:4 E6:4"),
        ("Am7", "D6:2 C6:2 A5:4 E5:8"),
        ("Dm7", "F5:2 G5:2 A5:2 C6:2 D6:4 F6:4"),
        ("G7", "E6:2 D6:2 B5:4 G5:4 F5:4"),
        ("Em7", "E5:4 G5:4 B5:4 D6:4"),
        ("A7", "C#6:4 E6:4 A6:8"),
    ]),
    # the title: an anthem
    "title": (6, "straight", [
        ("F", "A5:4 C6:4 F6:4 E6:2 C6:2"),
        ("G", "D6:6 B5:2 G5:8"),
        ("Em", "G5:2 B5:2 E6:4 D6:4 B5:4"),
        ("Am", "C6:4 A5:4 E5:8"),
        ("F", "F5:2 A5:2 C6:2 F6:2 E6:4 C6:4"),
        ("G", "D6:4 G6:4 F6:2 E6:2 D6:4"),
        ("C", "E6:8 D6:4 C6:4"),
        ("C", "C6:12 -:4"),
    ]),
}


def events(tune):
    """-> (bass, melody): lists of (note index or 0, interrupts)."""
    tick, pattern, bars = TUNES[tune]
    bass, melody = [], []
    for chord, line in bars:
        root = note_index(chord_root(chord))
        for interval, length in BASS[pattern]:
            bass.append((root + interval, length * tick))
        total = 0
        for tok in line.split():
            name, length = tok.split(":")
            length = int(length)
            total += length
            melody.append((0 if name == "-" else note_index(name), length * tick))
        assert total == 16, (tune, chord, line, total)
    return bass, melody


def encode(evs):
    out, cur = [], None
    for note, ticks in evs:
        first = True
        while ticks > 0:
            n = min(ticks, 64)
            if n != cur:
                out.append(0x5F + n)
                cur = n
            out.append(note if first or note == 0 else 0x5F)
            first = False
            ticks -= n
    out.append(0xFF)
    return out


def tune_asm(tune, label):
    """Assembler lines for a tune: label: dw bass, melody; then the data."""
    bass, melody = events(tune)
    lines = [f"{label}:", f"        dw {label}_b, {label}_m"]
    for suffix, evs in (("_b", bass), ("_m", melody)):
        data = encode(evs)
        lines.append(f"{label}{suffix}:")
        for i in range(0, len(data), 16):
            lines.append("        db " + ", ".join(f"${b:02X}" for b in data[i:i + 16]))
    return lines


def tune_bytes(tune):
    bass, melody = events(tune)
    return 4 + len(encode(bass)) + len(encode(melody))


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
            print(t, tune_bytes(t))
    else:
        main(sys.argv[1] if len(sys.argv) > 1 else "build/music_title.asm")
