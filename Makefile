# ZX Racer build. Requires sjasmplus >= 1.20 on PATH, Python 3 and a C compiler.
ASM      ?= sjasmplus
CC       ?= cc
PYTHON   ?= python3
ASMFLAGS ?= --nologo --msg=war --fullpath -Ibuild --lst=build/zxracer.lst --sym=build/zxracer.sym

SRC   := $(wildcard src/*.asm)
ZXSIM := build/zxsim

.PHONY: all clean run test shots profile
all: build/zxracer.sna

build:
	mkdir -p build

build/tables.asm: tools/gen_tables.py | build
	$(PYTHON) tools/gen_tables.py $@

build/track_data.asm: tools/track.py assets/tracks/test.yaml | build
	$(PYTHON) tools/track.py assets/tracks/test.yaml $@

build/car_data.asm: tools/png2zx.py assets/gfx/car.png | build
	$(PYTHON) tools/png2zx.py assets/gfx/car.png $@ CarGfx 64 32

build/scenery_data.asm: tools/make_scenery.py | build
	$(PYTHON) tools/make_scenery.py $@

build/horizon_data.asm: tools/make_horizon.py | build
	$(PYTHON) tools/make_horizon.py $@

build/font_data.asm: tools/make_font.py | build
	$(PYTHON) tools/make_font.py $@

build/zxracer.sna: $(SRC) build/tables.asm build/track_data.asm build/car_data.asm build/scenery_data.asm build/horizon_data.asm build/font_data.asm | build
	$(ASM) $(ASMFLAGS) src/main.asm

$(ZXSIM): tools/zxsim/zxsim.c | build
	$(CC) -O2 -Wall -o $@ $<

build/cputest.sna: tests/cputest.asm | build
	$(ASM) --nologo --msg=war tests/cputest.asm

# CPU core self-test, then a smoke run of the game with screenshots
test: $(ZXSIM) build/cputest.sna build/zxracer.sna
	$(PYTHON) tests/run_cputest.py $(ZXSIM) build/cputest.sna
	$(PYTHON) tests/smoke.py $(ZXSIM) build/zxracer.sna build
	$(PYTHON) tests/carcheck.py $(ZXSIM) build/zxracer.sna build

# Border-bar profile: T-states per phase per game frame
profile: $(ZXSIM) build/zxracer.sna
	$(PYTHON) tools/profile.py $(ZXSIM) build/zxracer.sna

run: build/zxracer.sna
	fuse --machine 128 build/zxracer.sna

clean:
	rm -rf build
