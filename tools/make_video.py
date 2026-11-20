#!/usr/bin/env python3
"""Record a gameplay video of a snapshot with zxsim.

Video: every 50 Hz frame from zxsim (-v), scaled 2x with nearest-neighbour.
Audio: zxsim logs the AY-3-8912 registers at the end of every frame (-y);
this script synthesises them (3 square-wave tone channels, 17-bit LFSR
noise, the AY's logarithmic volume table and its envelope generator) at
44.1 kHz. zxsim sets bit 7 of the logged register 13 in a frame that wrote
it, which restarts the envelope.

usage: make_video.py ZXSIM SNA OUT.mp4 [frames] [zxsim key options...]
"""
import os
import subprocess
import sys
import wave

import numpy as np

AY_CLOCK = 1773400              # 128K AY clock, Hz
RATE = 44100
FPS = 50
W, H = 320, 288
VOLUMES = [0.0, 0.0137, 0.0205, 0.0291, 0.0423, 0.0618, 0.0847, 0.1369,
           0.1691, 0.2647, 0.3527, 0.4499, 0.5704, 0.6873, 0.8482, 1.0]


def envelope(shape, pos):
    """The AY's envelope level (0-15) at positions pos, in steps from its start."""
    step = np.floor(pos).astype(np.int64)
    cycle, s = step // 16, step % 16
    up = bool(shape & 4)
    first = s if up else 15 - s
    if not shape & 8:                   # one ramp, then silence
        return np.where(cycle == 0, first, 0)
    if shape & 1:                       # one ramp, then hold
        end = 15 if up != bool(shape & 2) else 0
        return np.where(cycle == 0, first, end)
    if shape & 2:                       # up and down
        rising = (cycle % 2 == 0) == up
        return np.where(rising, s, 15 - s)
    return first                        # saw: the ramp again and again


def synth(regs):
    """regs: (frames, 14) uint8 -> mono float32 samples."""
    spf = RATE // FPS
    out = np.zeros(len(regs) * spf, dtype=np.float32)
    t = np.arange(spf)
    phase = [0.0, 0.0, 0.0]
    lfsr, noise_acc = 1, 0.0
    env_pos = 1e9                       # (no envelope started: silent)
    vol_tab = np.array(VOLUMES, dtype=np.float32)
    for f, r in enumerate(regs):
        r = [int(v) for v in r]         # numpy uint8 would overflow the shifts
        if r[13] & 0x80:
            env_pos = 0.0
        eper = (r[11] | (r[12] << 8)) or 1
        estep = AY_CLOCK / (256 * eper) / RATE
        epos = env_pos + t * estep
        env_pos += spf * estep
        env = vol_tab[envelope(r[13] & 15, epos)]
        periods = [(r[2 * c] | ((r[2 * c + 1] & 15) << 8)) or 1 for c in range(3)]
        mixer = r[7]
        vols = [env if r[8 + c] & 16 else VOLUMES[r[8 + c] & 15] for c in range(3)]
        # noise: one LFSR step per noise period
        nper = (r[6] & 31) or 1
        nstep = AY_CLOCK / (16 * nper) / RATE
        noise = np.empty(spf, dtype=np.float32)
        for k in range(spf):
            noise_acc += nstep
            while noise_acc >= 1.0:
                noise_acc -= 1.0
                bit = (lfsr ^ (lfsr >> 3)) & 1
                lfsr = (lfsr >> 1) | (bit << 16)
            noise[k] = lfsr & 1
        frame = np.zeros(spf, dtype=np.float32)
        for c in range(3):
            if np.isscalar(vols[c]) and vols[c] == 0:
                continue
            freq = AY_CLOCK / (16 * periods[c])
            ph = phase[c] + t * freq / RATE
            phase[c] = (phase[c] + spf * freq / RATE) % 1.0
            tone = (ph % 1.0 < 0.5).astype(np.float32)
            if mixer & (1 << c):            # tone disabled: output stays high
                tone[:] = 1.0
            nz = noise if not mixer & (8 << c) else 1.0
            frame += tone * nz * vols[c]
        out[f * spf:(f + 1) * spf] = frame
    out -= np.convolve(out, np.ones(256) / 256, mode="same")   # remove DC
    peak = np.max(np.abs(out)) or 1.0
    return out / peak * 0.8


def main():
    zxsim, sna, dst = sys.argv[1:4]
    frames = int(sys.argv[4]) if len(sys.argv) > 4 else 2250
    keys = sys.argv[5:] or ["-k", "250:Q", "-k", "256:none"]
    tmp = os.path.splitext(dst)[0]
    video, aylog, audio = tmp + "_video.mp4", tmp + ".ay", tmp + ".wav"

    enc = subprocess.Popen(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
         "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
         "-vf", "scale=iw*2:ih*2:flags=neighbor", "-c:v", "libx264",
         "-crf", "18", "-preset", "medium", "-pix_fmt", "yuv420p", video],
        stdin=subprocess.PIPE)
    sim = subprocess.Popen([zxsim, sna, "-n", str(frames), "-q", "-v", "/dev/stdout",
                            "-y", aylog] + keys, stdout=enc.stdin)
    sim.wait()
    enc.stdin.close()
    enc.wait()
    if sim.returncode or enc.returncode:
        sys.exit("zxsim or ffmpeg failed")

    regs = np.frombuffer(open(aylog, "rb").read(), dtype=np.uint8).reshape(-1, 14)
    pcm = (synth(regs) * 32767).astype(np.int16)
    with wave.open(audio, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())

    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", video, "-i", audio,
                    "-c:v", "copy", "-c:a", "aac", "-b:a", "128k", "-shortest", dst],
                   check=True)
    for f in (video, aylog, audio):
        os.remove(f)
    print(f"{dst}: {frames} frames ({frames / FPS:.1f} s)")


if __name__ == "__main__":
    main()
