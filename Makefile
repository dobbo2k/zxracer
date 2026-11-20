# Speed Run build. Requires sjasmplus >= 1.20 on PATH, Python 3 and a C compiler.
ASM      ?= sjasmplus
CC       ?= cc
PYTHON   ?= python3
ASMFLAGS ?= --nologo --msg=war --fullpath -Ibuild --lst=build/zxracer.lst --sym=build/zxracer.sym

SRC   := $(wildcard src/*.asm)
ZXSIM := build/zxsim

.PHONY: all clean run test shots profile video tap release cover
all: build/zxracer.sna

build:
	mkdir -p build

build/tables.asm: tools/gen_tables.py | build
	$(PYTHON) tools/gen_tables.py $@

build/car_data.asm: tools/png2zx.py assets/gfx/car.png | build
	$(PYTHON) tools/png2zx.py assets/gfx/car.png $@ CarGfx 64 32 3

build/stages.asm: tools/make_stages.py tools/make_music.py tools/make_scenery.py tools/make_screens.py tools/gen_tables.py tools/make_font.py assets/stages.yaml assets/gfx/car.png | build
	$(PYTHON) tools/make_stages.py assets/stages.yaml build

build/crew_data.asm: tools/make_crew.py tools/make_screens.py | build
	$(PYTHON) tools/make_crew.py $@

build/music_title.asm: tools/make_music.py | build
	$(PYTHON) tools/make_music.py $@

build/font_data.asm: tools/make_font.py | build
	$(PYTHON) tools/make_font.py $@

build/zxracer.sna: $(SRC) build/tables.asm build/stages.asm build/car_data.asm build/font_data.asm build/crew_data.asm build/music_title.asm | build
	$(ASM) $(ASMFLAGS) src/main.asm

$(ZXSIM): tools/zxsim/zxsim.c | build
	$(CC) -O2 -Wall -o $@ $<

build/cputest.sna: tests/cputest.asm | build
	$(ASM) --nologo --msg=war tests/cputest.asm

# CPU core self-test, then a smoke run of the game with screenshots
test: $(ZXSIM) build/cputest.sna build/zxracer.sna build/video.sna build/speedrun.tap
	$(PYTHON) tests/run_cputest.py $(ZXSIM) build/cputest.sna
	$(PYTHON) tests/smoke.py $(ZXSIM) build/zxracer.sna build
	$(PYTHON) tests/carcheck.py $(ZXSIM) build/zxracer.sna build
	$(PYTHON) tests/stagecheck.py $(ZXSIM) build/zxracer.sna build/video.sna
	$(PYTHON) tests/tapecheck.py $(ZXSIM) build/speedrun.tap build/release.sym build

# Border-bar profile: T-states per phase per game frame
profile: $(ZXSIM) build/zxracer.sna
	$(PYTHON) tools/profile.py $(ZXSIM) build/zxracer.sna

# Gameplay video (build/gameplay.mp4): no timing bars, autopilot drives the game
# Release build (no timing bars) and the tape image made from it
build/release.sna: $(SRC) build/tables.asm build/stages.asm build/car_data.asm build/font_data.asm build/crew_data.asm build/music_title.asm | build
	$(ASM) --nologo --msg=war --fullpath -Ibuild --sym=build/release.sym -DPROFILE=0 -DRELEASE=1 src/main.asm

build/speedrun.tap: build/release.sna tools/make_tap.py tools/zpack.py assets/gfx/loading.scr src/loader.asm | build
	$(PYTHON) tools/make_tap.py build/release.sna build/release.sym $@

tap: build/speedrun.tap

# The release folder: both tape files, how to play, a printable inlay
# (screenshots from an autopilot run)
SHOTS := 3300 4600 8800 11600
release: build/speedrun.tap build/video.sna $(ZXSIM) tools/make_inlay.py release/cover.png assets/gfx/spine.png
	$(ZXSIM) build/video.sna -n 11700 -k 250:Q -k 256:none -q $(foreach f,$(SHOTS),-s $(f):build/shot_$(f).ppm)
	$(PYTHON) tools/make_inlay.py build release/cover.png assets/gfx/spine.png $(foreach f,$(SHOTS),build/shot_$(f).ppm)
	mkdir -p release
	cp build/speedrun.tap build/speedrun.tzx build/inlay_outside.png build/inlay_inside.png release/

# Hand-drawn style cover art (needs Node with Playwright and Chromium to render):
# the cover, the tape's loading screen made from a 4:3 version of it, and the
# lettering for the inlay's spine (the last two are kept in assets/gfx, so
# building the tape does not need Chromium)
cover: tools/make_cover.py tools/make_loading.py | build
	mkdir -p release
	$(PYTHON) tools/make_cover.py release/cover.png build/cover.svg portrait
	$(PYTHON) tools/make_cover.py build/cover_wide.png build/cover_wide.svg wide
	$(PYTHON) tools/make_loading.py build/cover_wide.png assets/gfx/loading.scr assets/gfx/loading_preview.png
	$(PYTHON) tools/make_cover.py assets/gfx/spine.png build/spine.svg spine

build/video.sna: $(SRC) build/tables.asm build/stages.asm build/car_data.asm build/font_data.asm build/crew_data.asm build/music_title.asm | build
	$(ASM) --nologo --msg=war --fullpath -Ibuild --sym=build/video.sym -DPROFILE=0 -DAUTOPLAY=1 src/main.asm

video: $(ZXSIM) build/video.sna
	$(PYTHON) tools/make_video.py $(ZXSIM) build/video.sna build/gameplay.mp4 2400

run: build/zxracer.sna
	fuse --machine 128 build/zxracer.sna

clean:
	rm -rf build
