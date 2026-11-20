#!/usr/bin/env python3
"""The tape's compression (src/loader.asm Unpack decodes it): LZ77 with
bit-level codes and an optimal parse, packing about a fifth better than the
byte-level LZ the pictures use (make_screens.lz).

The stream mixes bits (read MSB first from bytes taken as needed) and
whole bytes (literals, offsets' low bytes) in one byte sequence. Numbers
n >= 1 are interlaced Elias-gamma codes: for each bit of n below its top
one, from the highest, a 0 then that bit; then a 1 (2k + 1 bits).

  literal run:  gamma(length), then the bytes
  match:        gamma(hi + 1), a byte lo (offset = hi * 256 + lo + 1), then
                gamma(length - 1) (length >= 2)
  repeat match: gamma(length) (length >= 1), with the last match's offset
The stream opens with a literal run. After a literal run a bit: 1 a match,
0 a repeat match; after a match or repeat match a bit: 1 a match, 0 a
literal run. A match with gamma(hi + 1) = 256 ends the stream.
"""
import hashlib
import os


def gamma_bits(n):
    return 2 * (n.bit_length() - 1) + 1


class _Writer:
    def __init__(self):
        self.out = bytearray()
        self.bitpos = None          # index of the byte collecting bits
        self.nbits = 8

    def bit(self, b):
        if self.nbits == 8:
            self.bitpos = len(self.out)
            self.out.append(0)
            self.nbits = 0
        if b:
            self.out[self.bitpos] |= 0x80 >> self.nbits
        self.nbits += 1

    def gamma(self, n):
        assert n >= 1
        k = n.bit_length() - 1
        for i in range(k - 1, -1, -1):
            self.bit(0)
            self.bit(n >> i & 1)
        self.bit(1)

    def byte(self, b):
        self.out.append(b)


MAX_LEN = 4096          # longest match considered
CHAIN = 96              # candidates looked at per position
EXACT = 48              # lengths relaxed one by one (longer: only the longest)


def _matches(data):
    """Per position: list of (length, offset), nearest offset per length."""
    n = len(data)
    heads = {}
    found = [None] * n
    for i in range(n - 1):
        key = data[i] | data[i + 1] << 8
        chain = heads.get(key)
        res = []
        if chain:
            best = 1
            for j in reversed(chain[-CHAIN:]):
                if data[j + best] != data[i + best] if i + best < n else True:
                    continue
                m = 2
                lim = min(MAX_LEN, n - i)
                while m + 8 <= lim and data[j + m:j + m + 8] == data[i + m:i + m + 8]:
                    m += 8
                while m < lim and data[j + m] == data[i + m]:
                    m += 1
                if m > best:
                    res.append((m, i - j))
                    best = m
                    if m == lim:
                        break
            heads[key].append(i)
        else:
            heads[key] = [i]
        found[i] = res
    found[n - 1] = []
    return found


def _match_len(data, i, off):
    n = len(data)
    j = i - off
    if j < 0:
        return 0
    m = 0
    lim = min(MAX_LEN, n - i)
    while m < lim and data[j + m] == data[i + m]:
        m += 1
    return m


def _pack(data):
    n = len(data)
    assert n > 0
    found = _matches(data)
    INF = float("inf")
    # two states per position: after a literal run (L) or a match (M);
    # each: cost, last offset, run length (L), back pointer
    costL = [INF] * (n + 1)
    costM = [INF] * (n + 1)
    infoL = [None] * (n + 1)       # (run length, last offset, prev state, prev pos)
    infoM = [None] * (n + 1)       # (kind, length, offset, last offset, prev state, prev pos)
    costL[1] = gamma_bits(1) + 8
    infoL[1] = (1, 0, None, 0)
    for i in range(1, n):
        cl, cm = costL[i], costM[i]
        if cl == INF and cm == INF:
            continue
        # literal runs: from a match, or one longer
        if cm < INF:
            c = cm + 1 + gamma_bits(1) + 8
            if c < costL[i + 1]:
                costL[i + 1] = c
                infoL[i + 1] = (1, infoM[i][3], "M", i)
        if cl < INF:
            run, last = infoL[i][0], infoL[i][1]
            c = cl + 8 + gamma_bits(run + 1) - gamma_bits(run)
            if c < costL[i + 1]:
                costL[i + 1] = c
                infoL[i + 1] = (run + 1, last, infoL[i][2], infoL[i][3])
            # repeat match after a literal run
            if last:
                m = _match_len(data, i, last)
                for ln in list(range(1, min(m, EXACT) + 1)) + ([m] if m > EXACT else []):
                    c = cl + 1 + gamma_bits(ln)
                    if c < costM[i + ln]:
                        costM[i + ln] = c
                        infoM[i + ln] = ("R", ln, last, last, "L", i)
        # new matches, from either state
        for prev, base in (("L", cl), ("M", cm)):
            if base == INF:
                continue
            lo = 2
            for m, off in found[i]:
                oc = base + 1 + gamma_bits(((off - 1) >> 8) + 1) + 8
                hi = min(m, EXACT)
                lens = range(lo, hi + 1)
                for ln in lens:
                    c = oc + gamma_bits(ln - 1)
                    if c < costM[i + ln]:
                        costM[i + ln] = c
                        infoM[i + ln] = ("N", ln, off, off, prev, i)
                if m > EXACT:
                    c = oc + gamma_bits(m - 1)
                    if c < costM[i + m]:
                        costM[i + m] = c
                        infoM[i + m] = ("N", m, off, off, prev, i)
                lo = max(lo, hi + 1)
    # walk back
    state = "L" if costL[n] <= costM[n] else "M"
    pos = n
    tokens = []
    while pos > 0:
        if state == "L":
            run, last, prev, start = infoL[pos]
            # the run started at pos - run; its predecessor state is prev
            tokens.append(("L", pos - run, run))
            pos -= run
            state = prev
        else:
            kind, ln, off, last, prev, start = infoM[pos]
            tokens.append((kind, ln, off))
            pos = start
            state = prev
    tokens.reverse()
    # emit
    w = _Writer()
    after = None
    for t in tokens:
        if t[0] == "L":
            if after is not None:
                w.bit(0)
            w.gamma(t[2])
            for b in data[t[1]:t[1] + t[2]]:
                w.byte(b)
            after = "L"
        elif t[0] == "R":
            assert after == "L"
            w.bit(0)
            w.gamma(t[1])
            after = "M"
        else:
            w.bit(1)
            off = t[2] - 1
            w.gamma((off >> 8) + 1)
            w.byte(off & 0xFF)
            w.gamma(t[1] - 1)
            after = "M"
    w.bit(1)
    w.gamma(256)
    return bytes(w.out)


def unpack(src):
    out = bytearray()
    pos = 0
    cur, left = 0, 0

    def bit():
        nonlocal pos, cur, left
        if left == 0:
            cur = src[pos]
            pos += 1
            left = 8
        left -= 1
        return cur >> left & 1

    def gamma():
        v = 1
        while not bit():
            v = v * 2 + bit()
        return v

    def byte():
        nonlocal pos
        b = src[pos]
        pos += 1
        return b

    last = 0
    ln = gamma()
    for _ in range(ln):
        out.append(byte())
    after = "L"
    while True:
        if bit():
            hi = gamma()
            if hi == 256:
                return bytes(out)
            last = (hi - 1) * 256 + byte() + 1
            ln = gamma() + 1
        elif after == "L":
            ln = gamma()
        else:
            ln = gamma()
            for _ in range(ln):
                out.append(byte())
            after = "L"
            continue
        for _ in range(ln):
            out.append(out[-last])
        after = "M"


def pack(data, cache_dir=None):
    data = bytes(data)
    path = None
    if cache_dir:
        path = os.path.join(cache_dir, "zpack_" + hashlib.sha1(data).hexdigest()[:16] + ".bin")
        if os.path.exists(path):
            return open(path, "rb").read()
    out = _pack(data)
    assert unpack(out) == data
    if path:
        open(path, "wb").write(out)
    return out
