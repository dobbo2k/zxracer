/*
 * zxsim - minimal headless ZX Spectrum 128K emulator for automated testing
 * and profiling of ZX Racer.
 *
 *  - Z80 core with documented instructions (+ common undocumented IXH/IXL/SLL)
 *  - 128K memory paging via port $7FFD, banks 5/7 displayable
 *  - approximate memory contention (128K timings, access-driven model)
 *  - IM1/IM2 interrupts at the start of each 70908 T frame; FLASH swaps every 16
 *  - scanline-accurate screen + border capture -> PPM screenshots
 *  - keyboard / Kempston input scripts, border-change and flip logging
 *
 * Usage: zxsim game.sna [options]
 *   -n N            run N frames (default 50)
 *   -s F:file.ppm   save screenshot at end of frame F (repeatable)
 *   -k F:KEYS       from frame F hold KEYS (e.g. "P+Q", "none"); repeatable
 *   -j F:BITS       from frame F set Kempston bits (decimal, 1=R 2=L 4=D 8=U 16=F)
 *   -b F            log border writes (frame, T, colour) from frame F onwards
 *   -d ADDR:LEN     at exit, hex-dump LEN bytes at ADDR (current paging)
 *   -w ADDR[:N]     print registers when PC reaches ADDR (first N hits, default 20)
 *   -p F:file       from frame F, accumulate T-states per PC; write "addr T" lines to file
 *   -a              print the AY registers at exit
 *   -v FILE         write every frame as raw RGB24 (320x288) to FILE (video capture;
 *                   "-" for stdout)
 *   --screens ADDR:FILE  record frame number (LE32), then 256x192 palette
 *                        indices sampled at ADDR (without raster scanning)
 *   --capture-from F    begin -v and --screens at refresh F
 *   -y FILE         write the 14 AY registers at the end of every frame to FILE
 *                   (register 13's bit 7 set: it was written that frame)
 *   -q              quiet summary
 *   -R SEED         fill RAM and the (absent) ROM with random bytes first, as
 *                   a real machine's leftovers would be (robustness testing)
 *   -T file.tap     tape boot instead of a snapshot (.tap, or .tzx with standard
 *                   and turbo data blocks): does what the BASIC loader
 *                   would (loads the first CODE block to its address and calls
 *                   it, 48K BASIC ROM paged, bank 0 at $C000), then plays the
 *                   following blocks into the EAR input (port $FE bit 6) with
 *                   the ROM's timings (no ROM image is needed)
 *   -x PERCENT      play the tape at PERCENT of its speed (default 100)
 *   -48             48K frame timing and fixed memory map
 *   --rom FILE      install a 16 KiB ROM image
 *   --rom-tape F     boot the ROM and play the complete tape from frame F;
 *                   use -k to enter LOAD "" from the BASIC prompt
 *   --eject F        disconnect the tape from the EAR input at frame F
 *   -F              no Kempston interface: port $1F reads the floating bus, as
 *                   on a real 128K or +2 (the byte the ULA is fetching from the
 *                   shown screen during the picture, else $FF)
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif
#include <ctype.h>

static long frame_t = 70908, line_t = 228;
static long cont_t0 = 14361, line0_t = 14364;

/* ------------------------------------------------------------------ memory */
static uint8_t rom[16384];
static uint8_t ram[8][16384];
static uint8_t *page[4];
static int contended[4];
static uint8_t p7ffd;
static uint8_t border;
static long T;                 /* T-states within current frame */
static long frame;

static void update_paging(void) {
    page[0] = rom; page[1] = ram[5]; page[2] = ram[2]; page[3] = ram[p7ffd & 7];
    contended[0] = 0; contended[1] = 1; contended[2] = 0; contended[3] = (p7ffd & 1);
}

static inline void contend(uint16_t a) {
    static const int pat[8] = {6, 5, 4, 3, 2, 1, 0, 0};
    if (!contended[a >> 14]) return;
    long t = T - cont_t0;
    if (t < 0 || t >= 192L * line_t) return;
    int lt = (int)(t % line_t);
    if (lt >= 128) return;
    T += pat[lt & 7];
}

/* The 128K's floating bus: in each display line's first 128 T, 8-T groups
   of bitmap, attribute, bitmap, attribute (two columns), then 4 idle T;
   $FF elsewhere. (Approximate timing: enough to show what a read of an
   unattached port can return.) */
static uint8_t floating_bus(void) {
    long t = T - line0_t;
    if (t < 0 || t >= 192L * line_t) return 0xff;
    int y = (int)(t / line_t), lt = (int)(t % line_t);
    if (lt >= 128 || (lt & 7) >= 4) return 0xff;
    int col = (lt >> 3) * 2 + ((lt & 7) >> 1);
    const uint8_t *scr = ram[(p7ffd & 8) ? 7 : 5];
    if (lt & 1) return scr[0x1800 + (y >> 3) * 32 + col];
    return scr[((y & 0xc0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2) | col];
}

/* -u: a map of the CPU addresses in [use_lo, use_hi) the program touched
   (bit 0 read, bit 1 written, bit 2 executed) */
static uint8_t usemap[65536];
static long use_lo = -1, use_hi = -1;
#define USE(a, bit) do { if ((long)(a) >= use_lo && (long)(a) < use_hi) usemap[a] |= (bit); } while (0)

static inline uint8_t peek(uint16_t a) { return page[a >> 14][a & 0x3fff]; }
static inline uint8_t rd(uint16_t a) { contend(a); T += 3; USE(a, 1); return peek(a); }
static inline void wr(uint16_t a, uint8_t v) {
    contend(a); T += 3; USE(a, 2);
    if (a >= 0x4000) page[a >> 14][a & 0x3fff] = v;
}

/* ------------------------------------------------------------------ input */
static uint8_t keyrows[8];     /* bit set = key pressed, row index = high byte bit */
static uint8_t kempston;
static int no_kempston;        /* -F: port $1F floats */
static uint8_t floating_bus(void);

static const char *keynames[8][5] = {
    {"CS", "Z", "X", "C", "V"},
    {"A", "S", "D", "F", "G"},
    {"Q", "W", "E", "R", "T"},
    {"1", "2", "3", "4", "5"},
    {"0", "9", "8", "7", "6"},
    {"P", "O", "I", "U", "Y"},
    {"ENTER", "L", "K", "J", "H"},
    {"SPACE", "SS", "M", "N", "B"},
};

static void set_keys(const char *spec) {
    memset(keyrows, 0, sizeof keyrows);
    char buf[256]; strncpy(buf, spec, 255); buf[255] = 0;
    for (char *tok = strtok(buf, "+"); tok; tok = strtok(NULL, "+")) {
        for (char *p = tok; *p; p++) *p = (char)toupper((unsigned char)*p);
        if (!strcmp(tok, "NONE")) continue;
        int found = 0;
        for (int r = 0; r < 8; r++)
            for (int b = 0; b < 5; b++)
                if (!strcmp(tok, keynames[r][b])) { keyrows[r] |= 1 << b; found = 1; }
        if (!found) fprintf(stderr, "zxsim: unknown key '%s'\n", tok);
    }
}

static uint8_t *tape;          /* (tape boot, see below) */
static int tape_ear(void);

static uint8_t port_in(uint16_t port) {
    if ((port & 0xff) == 0x1f) return no_kempston ? floating_bus() : kempston;
    if (!(port & 1)) {
        uint8_t v = 0x1f;
        for (int r = 0; r < 8; r++)
            if (!(port & (0x100 << r))) v &= ~keyrows[r];
        return v | 0xa0 | (tape && tape_ear() ? 0x40 : 0);
    }
    return 0xff;
}

static int no_paging;
static uint8_t ay_reg[16], ay_sel;     /* AY-3-8912: registers only, no audio */
static int ay_env_hit;                 /* register 13 written this frame */
static int log_border_from = -1;
static long flips;
static void port_out(uint16_t port, uint8_t v) {
    if (!(port & 1)) {
        border = v & 7;
        if (log_border_from >= 0 && frame >= log_border_from)
            printf("border frame=%ld T=%ld colour=%d\n", frame, T, border);
    }
    if ((port & 0xC002) == 0xC000) ay_sel = v & 15;              /* $FFFD */
    else if ((port & 0xC002) == 0x8000) {                       /* $BFFD */
        ay_reg[ay_sel] = v;
        if (ay_sel == 13) ay_env_hit = 1;
    }
    if (!(port & 0x8002) && !no_paging) {    /* $7FFD decoding: A15=0, A1=0 */
        if ((p7ffd ^ v) & 8) flips++;
        p7ffd = v; update_paging();
    }
}

/* ------------------------------------------------------------------ video */
#define IMG_W 320
#define IMG_H 288
static uint8_t img[IMG_H][IMG_W];  /* palette index 0..15 */
static int next_row;

static void render_row(uint8_t *row, int y) {
    int line = y - 48;
    uint8_t b = border;
    memset(row, b, IMG_W);
    if (line < 0 || line >= 192) return;
    const uint8_t *scr = ram[(p7ffd & 8) ? 7 : 5];
    int addr = ((line & 0xc0) << 5) | ((line & 7) << 8) | ((line & 0x38) << 2);
    int aaddr = 0x1800 + (line >> 3) * 32;
    for (int c = 0; c < 32; c++) {
        uint8_t px = scr[addr + c], at = scr[aaddr + c];
        uint8_t br = (at & 0x40) ? 8 : 0;
        uint8_t ink = (at & 7) | br, pap = ((at >> 3) & 7) | br;
        if ((at & 0x80) && (frame & 16)) {          /* FLASH: swapped every 16 frames */
            uint8_t t = ink; ink = pap; pap = t;
        }
        for (int i = 0; i < 8; i++)
            row[32 + c * 8 + i] = (px & (0x80 >> i)) ? ink : pap;
    }
}

static void render_upto(long t) {
    while (next_row < IMG_H && line0_t + (long)(next_row - 48) * line_t <= t) {
        render_row(img[next_row], next_row);
        next_row++;
    }
}

/* A completed game frame, sampled all at once. Separate from the
   scanline capture so tests can recognise partially updated rows. */
static void write_screen(FILE *f) {
    uint8_t row[IMG_W];
    for (int i = 0; i < 4; i++) fputc((uint32_t)frame >> (i * 8) & 255, f);
    for (int y = 48; y < 240; y++) {
        render_row(row, y);
        fwrite(row + 32, 1, 256, f);
    }
}

static const uint8_t pal[16][3] = {
        {0, 0, 0}, {0, 0, 0xd7}, {0xd7, 0, 0}, {0xd7, 0, 0xd7},
        {0, 0xd7, 0}, {0, 0xd7, 0xd7}, {0xd7, 0xd7, 0}, {0xd7, 0xd7, 0xd7},
        {0, 0, 0}, {0, 0, 0xff}, {0xff, 0, 0}, {0xff, 0, 0xff},
        {0, 0xff, 0}, {0, 0xff, 0xff}, {0xff, 0xff, 0}, {0xff, 0xff, 0xff}};

/* raw RGB24 of the current frame (IMG_W x IMG_H) */
static void write_rgb(FILE *f) {
    static uint8_t row[IMG_W * 3];
    for (int y = 0; y < IMG_H; y++) {
        for (int x = 0; x < IMG_W; x++) memcpy(row + 3 * x, pal[img[y][x]], 3);
        fwrite(row, 1, sizeof row, f);
    }
}

static void save_ppm(const char *fn) {
    FILE *f = fopen(fn, "wb");
    if (!f) { perror(fn); return; }
    fprintf(f, "P6\n%d %d\n255\n", IMG_W, IMG_H);
    for (int y = 0; y < IMG_H; y++)
        for (int x = 0; x < IMG_W; x++) fwrite(pal[img[y][x]], 1, 3, f);
    fclose(f);
}

/* ------------------------------------------------------------------ Z80 */
typedef union { uint16_t w; struct { uint8_t l, h; } b; } pair;
static pair af, bc, de, hl, ix, iy, af_, bc_, de_, hl_;
static uint16_t sp, pc;
static uint8_t I, R, iff1, iff2, im, halted, ei_delay;

#define A af.b.h
#define F af.b.l
#define B bc.b.h
#define C bc.b.l
#define D de.b.h
#define E de.b.l
#define H hl.b.h
#define L hl.b.l

#define FC 0x01
#define FN 0x02
#define FV 0x04
#define FX 0x08
#define FH 0x10
#define FY 0x20
#define FZ 0x40
#define FS 0x80

static uint8_t sz53[256], sz53p[256];

static void init_tables(void) {
    for (int i = 0; i < 256; i++) {
        int p = 0;
        for (int b = 0; b < 8; b++) p ^= (i >> b) & 1;
        sz53[i] = (i & (FS | FX | FY)) | (i ? 0 : FZ);
        sz53p[i] = sz53[i] | (p ? 0 : FV);
    }
}

static inline uint8_t fetch_op(void) {
    contend(pc); T += 4;
    R = (R & 0x80) | ((R + 1) & 0x7f);
    USE(pc, 4);
    return peek(pc++);
}
static inline uint8_t imm8(void) { return rd(pc++); }
static inline uint16_t imm16(void) { uint8_t l = rd(pc++); return l | (rd(pc++) << 8); }
static inline void push16(uint16_t v) { wr(--sp, v >> 8); wr(--sp, v & 0xff); }
static inline uint16_t pop16(void) { uint8_t l = rd(sp++); return l | (rd(sp++) << 8); }

static void add8(uint8_t v, int c) {
    int r = A + v + c;
    F = ((r >> 8) & FC) | ((A ^ v ^ r) & FH) | ((((A ^ ~v) & (A ^ r)) & 0x80) ? FV : 0) | sz53[r & 0xff];
    A = (uint8_t)r;
}
static void sub8(uint8_t v, int c) {
    int r = A - v - c;
    F = FN | ((r >> 8) & FC) | ((A ^ v ^ r) & FH) | ((((A ^ v) & (A ^ r)) & 0x80) ? FV : 0) | sz53[r & 0xff];
    A = (uint8_t)r;
}
static void cp8(uint8_t v) {
    int r = A - v;
    F = FN | ((r >> 8) & FC) | ((A ^ v ^ r) & FH) | ((((A ^ v) & (A ^ r)) & 0x80) ? FV : 0) |
        (sz53[r & 0xff] & ~(FX | FY)) | (v & (FX | FY));
}
static void alu(int op, uint8_t v) {
    switch (op) {
    case 0: add8(v, 0); break;
    case 1: add8(v, F & FC); break;
    case 2: sub8(v, 0); break;
    case 3: sub8(v, F & FC); break;
    case 4: A &= v; F = sz53p[A] | FH; break;
    case 5: A ^= v; F = sz53p[A]; break;
    case 6: A |= v; F = sz53p[A]; break;
    case 7: cp8(v); break;
    }
}
static uint8_t inc8(uint8_t v) {
    uint8_t r = v + 1;
    F = (F & FC) | (r == 0x80 ? FV : 0) | ((r & 0xf) ? 0 : FH) | sz53[r];
    return r;
}
static uint8_t dec8(uint8_t v) {
    uint8_t r = v - 1;
    F = (F & FC) | FN | (v == 0x80 ? FV : 0) | ((v & 0xf) ? 0 : FH) | sz53[r];
    return r;
}
static uint16_t add16(uint16_t a, uint16_t b) {
    uint32_t r = a + b;
    F = (F & (FS | FZ | FV)) | (((a ^ b ^ r) >> 8) & FH) | ((r >> 16) & FC) | ((r >> 8) & (FX | FY));
    return (uint16_t)r;
}
static uint16_t adc16(uint16_t a, uint16_t b) {
    uint32_t r = a + b + (F & FC);
    F = ((r >> 16) & FC) | (((a ^ b ^ r) >> 8) & FH) | (((~(a ^ b) & (a ^ r)) & 0x8000) ? FV : 0) |
        ((r >> 8) & (FS | FX | FY)) | ((r & 0xffff) ? 0 : FZ);
    return (uint16_t)r;
}
static uint16_t sbc16(uint16_t a, uint16_t b) {
    uint32_t r = a - b - (F & FC);
    F = FN | ((r >> 16) & FC) | (((a ^ b ^ r) >> 8) & FH) | ((((a ^ b) & (a ^ r)) & 0x8000) ? FV : 0) |
        ((r >> 8) & (FS | FX | FY)) | ((r & 0xffff) ? 0 : FZ);
    return (uint16_t)r;
}
static uint8_t rot(int op, uint8_t v) {
    uint8_t r, c;
    switch (op) {
    case 0: c = v >> 7; r = (v << 1) | c; break;
    case 1: c = v & 1; r = (v >> 1) | (c << 7); break;
    case 2: c = v >> 7; r = (v << 1) | (F & FC); break;
    case 3: c = v & 1; r = (v >> 1) | ((F & FC) << 7); break;
    case 4: c = v >> 7; r = v << 1; break;
    case 5: c = v & 1; r = (v >> 1) | (v & 0x80); break;
    case 6: c = v >> 7; r = (v << 1) | 1; break;
    default: c = v & 1; r = v >> 1; break;
    }
    F = sz53p[r] | c;
    return r;
}
static void bit(int b, uint8_t v) {
    uint8_t r = v & (1 << b);
    F = (F & FC) | FH | (r ? 0 : (FZ | FV)) | (r & FS) | (v & (FX | FY));
}
static int cond(int y) {
    switch (y) {
    case 0: return !(F & FZ);
    case 1: return F & FZ;
    case 2: return !(F & FC);
    case 3: return F & FC;
    case 4: return !(F & FV);
    case 5: return F & FV;
    case 6: return !(F & FS);
    default: return F & FS;
    }
}

/* register access; xy = HL/IX/IY for H/L substitution */
static uint8_t *reg8(int r, pair *xy) {
    switch (r) {
    case 0: return &B;
    case 1: return &C;
    case 2: return &D;
    case 3: return &E;
    case 4: return &xy->b.h;
    case 5: return &xy->b.l;
    default: return &A;
    }
}
static uint16_t *rp(int p, pair *xy) {
    switch (p) {
    case 0: return &bc.w;
    case 1: return &de.w;
    case 2: return &xy->w;
    default: return &sp;
    }
}
static uint16_t *rp2(int p, pair *xy) {
    switch (p) {
    case 0: return &bc.w;
    case 1: return &de.w;
    case 2: return &xy->w;
    default: return &af.w;
    }
}

/* effective address of (HL) or (IX+d); extra = internal T for indexed form */
static uint16_t ea(pair *xy, int extra) {
    if (xy == &hl) return hl.w;
    int8_t d = (int8_t)imm8();
    T += extra;
    return (uint16_t)(xy->w + d);
}

static void exec_cb(pair *xy) {
    uint16_t addr = 0; int8_t d = 0;
    uint8_t op;
    if (xy != &hl) {
        d = (int8_t)imm8();
        op = imm8(); T += 2;
        addr = (uint16_t)(xy->w + d);
    } else {
        op = fetch_op();
    }
    int x = op >> 6, y = (op >> 3) & 7, z = op & 7;
    uint8_t v;
    int mem = (xy != &hl) || z == 6;
    if (xy == &hl && z == 6) addr = hl.w;
    if (mem) { v = rd(addr); T += 1; }
    else v = *reg8(z, &hl);
    if (x == 1) { bit(y, v); return; }
    uint8_t r;
    if (x == 0) r = rot(y, v);
    else if (x == 2) r = v & ~(1 << y);
    else r = v | (1 << y);
    if (mem) { wr(addr, r); if (xy != &hl && z != 6) *reg8(z, &hl) = r; }
    else *reg8(z, &hl) = r;
}

static void exec_ed(void) {
    uint8_t op = fetch_op();
    int x = op >> 6, y = (op >> 3) & 7, z = op & 7, p = y >> 1, q = y & 1;
    if (x == 1) {
        switch (z) {
        case 0: { T += 4; uint8_t v = port_in(bc.w); F = (F & FC) | sz53p[v]; if (y != 6) *reg8(y, &hl) = v; break; }
        case 1: T += 4; port_out(bc.w, y == 6 ? 0 : *reg8(y, &hl)); break;
        case 2: T += 7; if (q) hl.w = adc16(hl.w, *rp(p, &hl)); else hl.w = sbc16(hl.w, *rp(p, &hl)); break;
        case 3: { uint16_t a = imm16(); uint16_t *r = rp(p, &hl);
            if (q) { uint8_t l = rd(a); *r = l | (rd(a + 1) << 8); }
            else { wr(a, *r & 0xff); wr(a + 1, *r >> 8); } break; }
        case 4: { uint8_t v = A; A = 0; sub8(v, 0); break; }
        case 5: iff1 = iff2; pc = pop16(); break;
        case 6: { static const int ims[8] = {0, 0, 1, 2, 0, 0, 1, 2}; im = ims[y]; break; }
        case 7:
            switch (y) {
            case 0: T += 1; I = A; break;
            case 1: T += 1; R = A; break;
            case 2: T += 1; A = I; F = (F & FC) | sz53[A] | (iff2 ? FV : 0); break;
            case 3: T += 1; A = R; F = (F & FC) | sz53[A] | (iff2 ? FV : 0); break;
            case 4: { uint8_t v = rd(hl.w); T += 4; wr(hl.w, (A << 4) | (v >> 4)); A = (A & 0xf0) | (v & 0x0f); F = (F & FC) | sz53p[A]; break; }
            case 5: { uint8_t v = rd(hl.w); T += 4; wr(hl.w, (v << 4) | (A & 0x0f)); A = (A & 0xf0) | (v >> 4); F = (F & FC) | sz53p[A]; break; }
            default: break;
            }
        }
        return;
    }
    if (x == 2 && z <= 3 && y >= 4) {
        int dir = (y & 1) ? -1 : 1, rep = y >= 6;
        switch (z) {
        case 0: { /* LDI/LDD */
            uint8_t v = rd(hl.w); wr(de.w, v); T += 2;
            hl.w += dir; de.w += dir; bc.w--;
            uint8_t n = v + A;
            F = (F & (FS | FZ | FC)) | (bc.w ? FV : 0) | (n & FX) | ((n & 2) ? FY : 0);
            if (rep && bc.w) { pc -= 2; T += 5; }
            break; }
        case 1: { /* CPI/CPD */
            uint8_t v = rd(hl.w); int r = A - v; T += 5;
            hl.w += dir; bc.w--;
            F = (F & FC) | FN | (sz53[r & 0xff] & ~(FX | FY)) | ((A ^ v ^ r) & FH) | (bc.w ? FV : 0);
            uint8_t n = (uint8_t)(r - ((F & FH) ? 1 : 0));
            F |= (n & FX) | ((n & 2) ? FY : 0);
            if (rep && bc.w && (r & 0xff)) { pc -= 2; T += 5; }
            break; }
        case 2: { /* INI/IND */
            T += 1; uint8_t v = port_in(bc.w); T += 4; wr(hl.w, v);
            hl.w += dir; B--; F = (B ? 0 : FZ) | FN | (B & (FS | FX | FY));
            if (rep && B) { pc -= 2; T += 5; }
            break; }
        default: { /* OUTI/OUTD */
            T += 1; uint8_t v = rd(hl.w); B--; T += 4; port_out(bc.w, v);
            hl.w += dir; F = (B ? 0 : FZ) | FN | (B & (FS | FX | FY));
            if (rep && B) { pc -= 2; T += 5; }
            break; }
        }
        return;
    }
    /* other ED opcodes: 8T NOP */
}

static void exec(void) {
    if (halted) { T += 4; R = (R & 0x80) | ((R + 1) & 0x7f); return; }
    uint8_t op = fetch_op();
    pair *xy = &hl;
    while (op == 0xdd || op == 0xfd) { xy = (op == 0xdd) ? &ix : &iy; op = fetch_op(); }
    if (op == 0xcb) { exec_cb(xy); return; }
    if (op == 0xed) { exec_ed(); return; }

    int x = op >> 6, y = (op >> 3) & 7, z = op & 7, p = y >> 1, q = y & 1;
    switch (x) {
    case 0:
        switch (z) {
        case 0:
            switch (y) {
            case 0: break;
            case 1: { pair t = af; af = af_; af_ = t; break; }
            case 2: { T += 1; int8_t e = (int8_t)imm8(); if (--B) { T += 5; pc += e; } break; }
            case 3: { int8_t e = (int8_t)imm8(); T += 5; pc += e; break; }
            default: { int8_t e = (int8_t)imm8(); if (cond(y - 4)) { T += 5; pc += e; } break; }
            }
            break;
        case 1:
            if (!q) *rp(p, xy) = imm16();
            else { T += 7; xy->w = add16(xy->w, *rp(p, xy)); }
            break;
        case 2:
            switch (y) {
            case 0: wr(bc.w, A); break;
            case 1: A = rd(bc.w); break;
            case 2: wr(de.w, A); break;
            case 3: A = rd(de.w); break;
            case 4: { uint16_t a = imm16(); wr(a, xy->b.l); wr(a + 1, xy->b.h); break; }
            case 5: { uint16_t a = imm16(); uint8_t l = rd(a); xy->w = l | (rd(a + 1) << 8); break; }
            case 6: wr(imm16(), A); break;
            default: A = rd(imm16()); break;
            }
            break;
        case 3: T += 2; if (!q) (*rp(p, xy))++; else (*rp(p, xy))--; break;
        case 4: case 5:
            if (y == 6) {
                uint16_t a = ea(xy, 5);
                uint8_t v = rd(a); T += 1;
                wr(a, z == 4 ? inc8(v) : dec8(v));
            } else {
                uint8_t *r = reg8(y, xy);
                *r = (z == 4) ? inc8(*r) : dec8(*r);
            }
            break;
        case 6:
            if (y == 6) {
                uint16_t a;
                if (xy == &hl) a = hl.w;
                else { int8_t d = (int8_t)imm8(); a = (uint16_t)(xy->w + d); }
                uint8_t n = imm8();
                if (xy != &hl) T += 2;
                wr(a, n);
            } else *reg8(y, xy) = imm8();
            break;
        default:
            switch (y) {
            case 0: A = (A << 1) | (A >> 7); F = (F & (FS | FZ | FV)) | (A & (FX | FY | FC)); break;
            case 1: F = (F & (FS | FZ | FV)) | (A & FC); A = (A >> 1) | (A << 7); F |= A & (FX | FY); break;
            case 2: { uint8_t c = A >> 7; A = (A << 1) | (F & FC); F = (F & (FS | FZ | FV)) | (A & (FX | FY)) | c; break; }
            case 3: { uint8_t c = A & 1; A = (A >> 1) | ((F & FC) << 7); F = (F & (FS | FZ | FV)) | (A & (FX | FY)) | c; break; }
            case 4: {
                uint8_t a = A, c = F & FC, n = F & FN, diff = 0;
                if ((F & FH) || (a & 0x0f) > 9) diff |= 0x06;
                if (c || a > 0x99) { diff |= 0x60; c = FC; }
                uint8_t h = n ? ((F & FH) && (a & 0x0f) < 6 ? FH : 0) : ((a & 0x0f) > 9 ? FH : 0);
                A = n ? a - diff : a + diff;
                F = sz53p[A] | c | n | h;
                break; }
            case 5: A = ~A; F = (F & (FS | FZ | FV | FC)) | FH | FN | (A & (FX | FY)); break;
            case 6: F = (F & (FS | FZ | FV)) | FC | (A & (FX | FY)); break;
            default: F = (F & (FS | FZ | FV)) | ((F & FC) ? FH : FC) | (A & (FX | FY)); break;
            }
        }
        break;
    case 1:
        if (z == 6 && y == 6) { halted = 1; break; }   /* PC already points past HALT */
        if (y == 6) { uint16_t a = ea(xy, 5); wr(a, *reg8(z, &hl)); }
        else if (z == 6) { uint16_t a = ea(xy, 5); *reg8(y, &hl) = rd(a); }
        else *reg8(y, xy) = *reg8(z, xy);
        break;
    case 2:
        if (z == 6) alu(y, rd(ea(xy, 5)));
        else alu(y, *reg8(z, xy));
        break;
    default:
        switch (z) {
        case 0: T += 1; if (cond(y)) pc = pop16(); break;
        case 1:
            if (!q) *rp2(p, xy) = pop16();
            else switch (p) {
                case 0: pc = pop16(); break;
                case 1: { pair t; t = bc; bc = bc_; bc_ = t; t = de; de = de_; de_ = t; t = hl; hl = hl_; hl_ = t; break; }
                case 2: pc = xy->w; break;
                default: T += 2; sp = xy->w; break;
                }
            break;
        case 2: { uint16_t a = imm16(); if (cond(y)) pc = a; break; }
        case 3:
            switch (y) {
            case 0: pc = imm16(); break;
            case 2: { uint8_t n = imm8(); T += 4; port_out((A << 8) | n, A); break; }
            case 3: { uint8_t n = imm8(); T += 4; A = port_in((A << 8) | n); break; }
            case 4: { uint16_t v = rd(sp) | (rd(sp + 1) << 8); T += 1; wr(sp + 1, xy->b.h); wr(sp, xy->b.l); T += 2; xy->w = v; break; }
            case 5: { uint16_t t = de.w; de.w = hl.w; hl.w = t; break; }
            case 6: iff1 = iff2 = 0; break;
            case 7: iff1 = iff2 = 1; ei_delay = 1; break;
            }
            break;
        case 4: { uint16_t a = imm16(); if (cond(y)) { T += 1; push16(pc); pc = a; } break; }
        case 5:
            if (!q) { T += 1; push16(*rp2(p, xy)); }
            else { uint16_t a = imm16(); T += 1; push16(pc); pc = a; } /* p==0 CALL nn */
            break;
        case 6: alu(y, imm8()); break;
        default: T += 1; push16(pc); pc = y * 8; break;
        }
    }
}

static void interrupt(void) {
    if (halted) { halted = 0; }
    iff1 = iff2 = 0;
    R = (R & 0x80) | ((R + 1) & 0x7f);
    if (im == 2) {
        T += 7; push16(pc);
        uint16_t v = (I << 8) | 0xff;
        uint8_t l = rd(v); pc = l | (rd(v + 1) << 8);
    } else {
        T += 7; push16(pc); pc = 0x38;
    }
}

/* ------------------------------------------------------------------ tape */
static long tape_len;
/* the signal: pulse lengths in T; a negative length is a gap (no edge) */
static long *pulses;
static long npulses, pulse_i;
static long long pulse_end;    /* absolute T when pulse pulse_i ends */
static int ear;

static long long now_t(void) { return (long long)frame * frame_t + T; }

/* tape blocks (from a .tap, or a .tzx's standard / turbo data blocks) */
struct tblock {
    uint8_t *data; long len;            /* flag, data, checksum */
    int pilot, pilot_n, sync1, sync2, zero, one, last_bits;
    long pause_ms;
};
static struct tblock *tblocks;
static long ntblocks, tblock_i;

static void add_tblock(uint8_t *d, long len, int pilot, int pilot_n, int s1, int s2,
                       int zero, int one, int last_bits, long pause_ms) {
    static long cap;
    if (ntblocks == cap) { cap = cap ? cap * 2 : 64; tblocks = realloc(tblocks, cap * sizeof *tblocks); }
    tblocks[ntblocks++] = (struct tblock){d, len, pilot, pilot_n, s1, s2, zero, one, last_bits, pause_ms};
}

/* split the file into blocks: .tap, or .tzx blocks 10 (standard), 11 (turbo),
   30 / 32 (text, skipped) */
static int tape_parse(void) {
    if (tape_len >= 10 && !memcmp(tape, "ZXTape!\x1a", 8)) {
        long p = 10;
        while (p < tape_len) {
            uint8_t id = tape[p++];
            uint8_t *h = tape + p;
            if (id == 0x10) {
                long len = h[2] | h[3] << 8;
                add_tblock(h + 4, len, 2168, h[4] < 128 ? 8063 : 3223, 667, 735, 855, 1710, 8,
                           h[0] | h[1] << 8);
                p += 4 + len;
            } else if (id == 0x11) {
                long len = h[15] | h[16] << 8 | (long)h[17] << 16;
                add_tblock(h + 18, len, h[0] | h[1] << 8, h[10] | h[11] << 8, h[2] | h[3] << 8,
                           h[4] | h[5] << 8, h[6] | h[7] << 8, h[8] | h[9] << 8, h[12],
                           h[13] | h[14] << 8);
                p += 18 + len;
            } else if (id == 0x30) {
                p += 1 + h[0];
            } else if (id == 0x32) {
                p += 2 + (h[0] | h[1] << 8);
            } else {
                fprintf(stderr, "zxsim: TZX block %02X not supported\n", id);
                return -1;
            }
        }
    } else {
        long p = 0;
        while (p + 2 <= tape_len) {
            long len = tape[p] | tape[p + 1] << 8;
            if (p + 2 + len > tape_len) break;
            uint8_t *d = tape + p + 2;
            add_tblock(d, len, 2168, d[0] < 128 ? 8063 : 3223, 667, 735, 855, 1710, 8, 1000);
            p += 2 + len;
        }
    }
    return 0;
}

/* the next block: returns its body (flag, data, checksum) and length */
static struct tblock *tape_next(long *len) {
    if (tblock_i >= ntblocks) return NULL;
    *len = tblocks[tblock_i].len;
    return &tblocks[tblock_i++];
}

static long tape_speed = 100;
static void add_pulse(long t) {
    static long cap;
    t = t * 100 / tape_speed;
    if (npulses == cap) { cap = cap ? cap * 2 : 1 << 16; pulses = realloc(pulses, cap * sizeof *pulses); }
    pulses[npulses++] = t;
}

/* the rest of the tape as a signal: per block its pilot, sync pulses, two
   pulses per bit (zero / one lengths), then its pause */
static void tape_signal(void) {
    long len;
    struct tblock *t;
    add_pulse(-3500000);                        /* (the gap after the loader) */
    while ((t = tape_next(&len))) {
        uint8_t *b = t->data;
        for (int i = t->pilot_n; i > 0; i--) add_pulse(t->pilot);
        add_pulse(t->sync1); add_pulse(t->sync2);
        for (long i = 0; i < len; i++)
            for (int k = 7; k >= (i == len - 1 ? 8 - t->last_bits : 0); k--) {
                long p = (b[i] >> k & 1) ? t->one : t->zero;
                add_pulse(p); add_pulse(p);
            }
        if (t->pause_ms) add_pulse(-3500L * t->pause_ms);
    }
    pulse_end = pulses[0] < 0 ? -pulses[0] : pulses[0];
}

/* EAR level now: step through the pulses that have ended */
static int tape_ear(void) {
    long long t = now_t();
    while (pulse_i < npulses && t >= pulse_end) {
        if (pulses[pulse_i] > 0) ear ^= 1;      /* a pulse ends with an edge */
        if (++pulse_i < npulses) pulse_end += pulses[pulse_i] < 0 ? -pulses[pulse_i] : pulses[pulse_i];
    }
    return ear;
}

/* do what 10 ...: LOAD "" CODE: RANDOMIZE USR n would: the loader block */
static int tape_boot(const char *fn, long rom_tape_frame) {
    FILE *f = fopen(fn, "rb");
    if (!f) { perror(fn); return -1; }
    fseek(f, 0, SEEK_END); tape_len = ftell(f); fseek(f, 0, SEEK_SET);
    tape = malloc(tape_len);
    if (fread(tape, 1, tape_len, f) != (size_t)tape_len) { fclose(f); return -1; }
    fclose(f);
    if (tape_parse()) return -1;
    if (rom_tape_frame >= 0) {
        p7ffd = 0x10;
        update_paging();
        tape_signal();
        pulse_end += (long long)rom_tape_frame * frame_t;
        return 0;
    }
    long len;
    struct tblock *t;
    while ((t = tape_next(&len))) {
        uint8_t *b = t->data;
        if (b[0] == 0 && b[1] == 3) {            /* CODE header: its data follows */
            uint16_t addr = b[14] | b[15] << 8;
            struct tblock *dt = tape_next(&len);
            if (!dt) break;
            uint8_t *d = dt->data;
            p7ffd = 0x10; update_paging();
            memset(ram[5] + 0x1800, 0x07, 768);   /* CLS with INK 7, PAPER 0 */
            for (long i = 0; i < len - 2; i++) wr((uint16_t)(addr + i), d[1 + i]);
            sp = 0x7FF0; push16(0);              /* (returning would go back to BASIC) */
            pc = addr; im = 1; iff1 = iff2 = 0;  /* (the ROM would take the interrupt) */
            T = 0;
            tape_signal();
            return 0;
        }
    }
    fprintf(stderr, "zxsim: no CODE block in %s\n", fn);
    return -1;
}

/* ------------------------------------------------------------------ snapshot */
static int load_sna(const char *fn) {
    FILE *f = fopen(fn, "rb");
    if (!f) { perror(fn); return -1; }
    uint8_t h[27];
    if (fread(h, 1, 27, f) != 27) goto bad;
    I = h[0];
    hl_.w = h[1] | h[2] << 8; de_.w = h[3] | h[4] << 8; bc_.w = h[5] | h[6] << 8; af_.w = h[7] | h[8] << 8;
    hl.w = h[9] | h[10] << 8; de.w = h[11] | h[12] << 8; bc.w = h[13] | h[14] << 8;
    iy.w = h[15] | h[16] << 8; ix.w = h[17] | h[18] << 8;
    iff1 = iff2 = (h[19] & 4) ? 1 : 0; R = h[20];
    af.w = h[21] | h[22] << 8; sp = h[23] | h[24] << 8; im = h[25]; border = h[26] & 7;
    uint8_t m48[49152];
    if (fread(m48, 1, 49152, f) != 49152) goto bad;
    uint8_t ext[4];
    size_t n = fread(ext, 1, 4, f);
    if (n == 4) {
        pc = ext[0] | ext[1] << 8; p7ffd = ext[2];
        int cur = p7ffd & 7;
        memcpy(ram[5], m48, 16384); memcpy(ram[2], m48 + 16384, 16384); memcpy(ram[cur], m48 + 32768, 16384);
        for (int b = 0; b < 8; b++) {
            if (b == 5 || b == 2 || b == cur) continue;
            if (fread(ram[b], 1, 16384, f) != 16384) goto bad;
        }
    } else {
        p7ffd = 0x10;
        memcpy(ram[5], m48, 16384); memcpy(ram[2], m48 + 16384, 16384); memcpy(ram[0], m48 + 32768, 16384);
        update_paging();
        pc = pop16();
    }
    update_paging();
    fclose(f);
    return 0;
bad:
    fprintf(stderr, "zxsim: bad snapshot %s\n", fn);
    fclose(f);
    return -1;
}

/* ------------------------------------------------------------------ main */
typedef struct { long frame; char arg[256]; } event;

int main(int argc, char **argv) {
    const char *sna = NULL;
    long nframes = 50;
    enum { MAX_EVENTS = 1024 };
    static event shots[MAX_EVENTS], keys[MAX_EVENTS], joys[MAX_EVENTS];
    int nshots = 0, nkeys = 0, njoys = 0, quiet = 0, show_ay = 0;
    FILE *vid = NULL, *aylog = NULL;
    const char *use_file = NULL, *ram_file = NULL;
    long stop_at = -1, stop_n = 0, screen_at = -1;
    long capture_from = 0;
    FILE *screens = NULL;
    long dump_addr = -1, dump_len = 0, watch = -1, watch_n = 20, prof_from = -1, rand_seed = -1;
    const char *prof_file = NULL;
    const char *rom_file = NULL;
    long rom_tape_frame = -1;
    long eject_frame = -1;
    static unsigned long long prof[65536];
    for (int i = 1; i < argc; i++) {
        char *a = argv[i];
        if (!strcmp(a, "-n") && i + 1 < argc) nframes = atol(argv[++i]);
        else if ((!strcmp(a, "-s") || !strcmp(a, "-k") || !strcmp(a, "-j")) && i + 1 < argc) {
            char *v = argv[++i], *colon = strchr(v, ':');
            if (!colon) { fprintf(stderr, "zxsim: expected F:VALUE for %s\n", a); return 2; }
            int *cnt = a[1] == 's' ? &nshots : a[1] == 'k' ? &nkeys : &njoys;
            if (*cnt >= MAX_EVENTS) { fprintf(stderr, "zxsim: too many %s options\n", a); return 2; }
            event *e = a[1] == 's' ? &shots[nshots++] : a[1] == 'k' ? &keys[nkeys++] : &joys[njoys++];
            e->frame = atol(v);
            strncpy(e->arg, colon + 1, 255); e->arg[255] = 0;
        } else if (!strcmp(a, "-b") && i + 1 < argc) log_border_from = atoi(argv[++i]);
        else if (!strcmp(a, "-q")) quiet = 1;
        else if (!strcmp(a, "-a")) show_ay = 1;
        else if (!strcmp(a, "-v") && i + 1 < argc) {
            if (!strcmp(argv[++i], "-")) {          /* stdout, binary */
#ifdef _WIN32
                _setmode(_fileno(stdout), _O_BINARY);
#endif
                vid = stdout;
            } else if (!(vid = fopen(argv[i], "wb"))) { perror(argv[i]); return 1; }
        } else if (!strcmp(a, "-y") && i + 1 < argc) {
            if (!(aylog = fopen(argv[++i], "wb"))) { perror(argv[i]); return 1; }
        }
        else if (!strcmp(a, "-p") && i + 1 < argc) {
            char *v = argv[++i];
            prof_from = strtol(v, &v, 0);
            if (*v == ':') prof_file = v + 1;
        }
        else if (!strcmp(a, "-H") && i + 1 < argc) {
            char *v = argv[++i];
            stop_at = strtol(v, &v, 0);
            stop_n = 1;
            if (*v == ':') stop_n = strtol(v + 1, NULL, 0);
        }
        else if (!strcmp(a, "--screens") && i + 1 < argc) {
            char *v = argv[++i];
            screen_at = strtol(v, &v, 0);
            if (*v != ':' || !(screens = fopen(v + 1, "wb"))) {
                fprintf(stderr, "zxsim: expected --screens ADDRESS:FILE\n");
                return 2;
            }
        }
        else if (!strcmp(a, "--capture-from") && i + 1 < argc) capture_from = atol(argv[++i]);
        else if (!strcmp(a, "-D") && i + 1 < argc) ram_file = argv[++i];
        else if (!strcmp(a, "-u") && i + 1 < argc) {
            char *v = argv[++i];
            use_lo = strtol(v, &v, 0);
            if (*v == ':') use_hi = strtol(v + 1, &v, 0);
            if (*v == ':') use_file = v + 1;
        }
        else if (!strcmp(a, "-w") && i + 1 < argc) {
            char *v = argv[++i];
            watch = strtol(v, &v, 0);
            if (*v == ':') watch_n = strtol(v + 1, NULL, 0);
        }
        else if (!strcmp(a, "-d") && i + 1 < argc) {
            char *v = argv[++i];
            dump_addr = strtol(v, &v, 0);
            if (*v == ':') dump_len = strtol(v + 1, NULL, 0);
        }
        else if (!strcmp(a, "-T") && i + 1 < argc) sna = argv[++i], tape = (uint8_t *)1;
        else if (!strcmp(a, "-R") && i + 1 < argc) rand_seed = atol(argv[++i]);
        else if (!strcmp(a, "--rom") && i + 1 < argc) rom_file = argv[++i];
        else if (!strcmp(a, "--rom-tape") && i + 1 < argc) rom_tape_frame = atol(argv[++i]);
        else if (!strcmp(a, "--eject") && i + 1 < argc) eject_frame = atol(argv[++i]);
        else if (!strcmp(a, "-x") && i + 1 < argc) tape_speed = atol(argv[++i]);
        else if (!strcmp(a, "-48")) no_paging = 1;
        else if (!strcmp(a, "-F")) no_kempston = 1;
        else if (a[0] != '-') sna = a;
        else { fprintf(stderr, "zxsim: unknown option %s\n", a); return 2; }
    }
    if (!sna) { fprintf(stderr, "usage: zxsim game.sna [-n frames] [-s F:shot.ppm] [-k F:KEYS] [-j F:BITS] [-b F] [-q]\n"); return 2; }
    init_tables();
    if (no_paging) {
        frame_t = 69888;
        line_t = 224;
        cont_t0 = 14335;
        line0_t = 14336;
    }
    memset(rom, 0xff, sizeof rom);
    if (rand_seed >= 0) {
        srand((unsigned)rand_seed);
        for (int i = 0; i < 16384; i++) rom[i] = (uint8_t)rand();
        for (int b = 0; b < 8; b++) for (int i = 0; i < 16384; i++) ram[b][i] = (uint8_t)rand();
    }
    if (rom_file) {
        FILE *rf = fopen(rom_file, "rb");
        if (!rf) { perror(rom_file); return 1; }
        size_t n = fread(rom, 1, sizeof rom, rf);
        fclose(rf);
        if (n != sizeof rom) { fprintf(stderr, "zxsim: short ROM file\n"); return 1; }
    }
    if (rom_tape_frame >= 0 && (!rom_file || !tape)) {
        fprintf(stderr, "zxsim: --rom-tape requires --rom and -T\n");
        return 2;
    }
    if (tape) { if (tape_boot(sna, rom_tape_frame)) return 1; }
    else if (load_sna(sna)) return 1;

    long rom_warn = 0;
    for (frame = 0; frame < nframes; frame++) {
        if (frame == eject_frame) tape = NULL;
        for (int i = 0; i < nkeys; i++) if (keys[i].frame == frame) set_keys(keys[i].arg);
        for (int i = 0; i < njoys; i++) if (joys[i].frame == frame) kempston = (uint8_t)atoi(joys[i].arg);
        next_row = 0;
        while (T < frame_t) {
            if (T < 32 && iff1 && !ei_delay) interrupt();
            ei_delay = 0;
            if (pc == watch && watch_n > 0 && !halted) {
                watch_n--;
                printf("watch f=%ld T=%ld PC=%04X AF=%04X BC=%04X DE=%04X HL=%04X IX=%04X IY=%04X SP=%04X\n",
                       frame, T, pc, af.w, bc.w, de.w, hl.w, ix.w, iy.w, sp);
            }
            if (pc == stop_at && !halted && --stop_n <= 0) goto stopped;
            if (screens && frame >= capture_from && pc == screen_at && !halted) write_screen(screens);
            uint16_t pc0 = pc; long t0 = T;
            exec();
            if (prof_file && frame >= prof_from) prof[pc0] += (unsigned long long)(T - t0);
            if (pc < 0x4000 && !rom_warn && !rom_file) {
                rom_warn = 1;
                fprintf(stderr, "zxsim: warning: execution entered ROM at %04X (frame %ld)\n", pc, frame);
            }
            render_upto(T);
        }
        render_upto(frame_t + line_t * 400);
        T -= frame_t;
        for (int i = 0; i < nshots; i++) if (shots[i].frame == frame) save_ppm(shots[i].arg);
        if (vid && frame >= capture_from) write_rgb(vid);
        if (aylog) {            /* register 13 bit 7: the envelope restarted */
            uint8_t r[14];
            memcpy(r, ay_reg, 14);
            if (ay_env_hit) r[13] |= 0x80;
            ay_env_hit = 0;
            fwrite(r, 1, 14, aylog);
        }
    }
    if (0) {
stopped:
        if (!quiet) printf("stopped at %04X in frame %ld\n", (unsigned)stop_at, frame);
    }
    if (ram_file) {
        FILE *rf = fopen(ram_file, "wb");
        if (rf) { for (int b = 0; b < 8; b++) fwrite(ram[b], 1, 16384, rf); fclose(rf); }
    }
    if (prof_file) {
        FILE *pf = fopen(prof_file, "w");
        if (pf) {
            for (int a = 0; a < 65536; a++) if (prof[a]) fprintf(pf, "%04X %llu\n", a, prof[a]);
            fclose(pf);
        }
    }
    if (vid) fclose(vid);
    if (screens) fclose(screens);
    if (aylog) fclose(aylog);
    if (show_ay) {
        printf("ay");
        for (int r = 0; r < 14; r++) printf(" %02X", ay_reg[r]);
        printf("\n");
    }
    if (use_file && use_lo >= 0 && use_hi > use_lo) {
        FILE *u = fopen(use_file, "wb");
        if (u) { fwrite(usemap + use_lo, 1, (size_t)(use_hi - use_lo), u); fclose(u); }
    }
    if (dump_addr >= 0) {
        for (long i = 0; i < dump_len; i++)
            printf("%02X%s", peek((uint16_t)(dump_addr + i)), (i % 16 == 15 || i == dump_len - 1) ? "\n" : " ");
    }
    if (!quiet)
        printf("frames=%ld flips=%ld fps=%.2f pc=%04X sp=%04X 7ffd=%02X\n",
               nframes, flips, nframes ? flips * 50.0 / nframes : 0.0, pc, sp, p7ffd);
    return 0;
}
