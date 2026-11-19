# ZX Racer build. Requires sjasmplus >= 1.20 on PATH, Python 3 and a C compiler.
ASM      ?= sjasmplus
CC       ?= cc
PYTHON   ?= python3
ASMFLAGS ?= --nologo --msg=war --fullpath -Ibuild --lst=build/zxracer.lst --sym=build/zxracer.sym

SRC   := $(wildcard src/*.asm)
ZXSIM := build/zxsim

.PHONY: all clean run test shots profile video
all: build/zxracer.sna

build:
	mkdir -p build

build/tables.asm: tools/gen_tables.py | build
	$(PYTHON) tools/gen_tables.py $@

build/car_data.asm: tools/png2zx.py assets/gfx/car.png | build
	$(PYTHON) tools/png2zx.py assets/gfx/car.png $@ CarGfx 64 32

build/stages.asm: tools/make_stages.py tools/make_scenery.py assets/stages.yaml | build
	$(PYTHON) tools/make_stages.py assets/stages.yaml build

build/font_data.asm: tools/make_font.py | build
	$(PYTHON) tools/make_font.py $@

build/zxracer.sna: $(SRC) build/tables.asm build/stages.asm build/car_data.asm build/font_data.asm | build
	$(ASM) $(ASMFLAGS) src/main.asm

$(ZXSIM): tools/zxsim/zxsim.c | build
	$(CC) -O2 -Wall -o $@ $<

build/cputest.sna: tests/cputest.asm | build
	$(ASM) --nologo --msg=war tests/cputest.asm

# CPU core self-test, then a smoke run of the game with screenshots
test: $(ZXSIM) build/cputest.sna build/zxracer.sna build/video.sna
	$(PYTHON) tests/run_cputest.py $(ZXSIM) build/cputest.sna
	$(PYTHON) tests/smoke.py $(ZXSIM) build/zxracer.sna build
	$(PYTHON) tests/carcheck.py $(ZXSIM) build/zxracer.sna build
	$(PYTHON) tests/stagecheck.py $(ZXSIM) build/zxracer.sna build/video.sna

# Border-bar profile: T-states per phase per game frame
profile: $(ZXSIM) build/zxracer.sna
	$(PYTHON) tools/profile.py $(ZXSIM) build/zxracer.sna

# Gameplay video (build/gameplay.mp4): no timing bars, autopilot drives the game
build/video.sna: $(SRC) build/tables.asm build/stages.asm build/car_data.asm build/font_data.asm | build
	$(ASM) --nologo --msg=war --fullpath -Ibuild --sym=build/video.sym -DPROFILE=0 -DAUTOPLAY=1 src/main.asm

video: $(ZXSIM) build/video.sna
	$(PYTHON) tools/make_video.py $(ZXSIM) build/video.sna build/gameplay.mp4 2400

run: build/zxracer.sna
	fuse --machine 128 build/zxracer.sna

clean:
	rm -rf build
