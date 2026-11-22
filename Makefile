# Speed Run build. Requires sjasmplus >= 1.20 on PATH, Python 3 and a C compiler.
ASM      ?= sjasmplus
CC       ?= cc
PYTHON   ?= python3
ASMFLAGS ?= --nologo --msg=war --fullpath -Ibuild --lst=build/zxracer.lst --sym=build/zxracer.sym
# ZX_OBJINK (1, the default): traffic and scenery in their own inks (src/objink.asm,
# PLAN.md 2.2); ZX_OBJINK=0: the black and white silhouettes of before. A change of
# it makes the packs and snapshots again (OBJINK_STAMP).
ZX_OBJINK  ?= 1
OBJINK_DEF := $(if $(filter 1,$(ZX_OBJINK)),-DZX_OBJINK=1)
OBJINK_STAMP := build/objink-$(ZX_OBJINK).stamp

SRC   := $(wildcard src/*.asm)
# On Windows (MSYS2) the C compiler writes zxsim.exe; the ./ lets Windows
# run it from the current directory even when NoDefaultCurrentDirectoryInExePath
# is set
EXE   := $(if $(findstring _NT,$(shell uname -s)),.exe)
ZXSIM := ./build/zxsim$(EXE)

# Machine-specific settings (emulator paths); see CLAUDE.md
-include local.mk

.PHONY: all clean run run-tape run-realtape test shots profile video tap release cover leaflet einstein release-einstein test-einstein run-einstein
all: build/zxracer.sna

build:
	mkdir -p build

build/tables.asm: tools/gen_tables.py | build
	$(PYTHON) tools/gen_tables.py $@

assets/gfx/car.png: tools/make_car.py
	$(PYTHON) $< $@

build/car_data.asm: tools/png2zx.py assets/gfx/car.png | build
	$(PYTHON) tools/png2zx.py assets/gfx/car.png $@ CarGfx 64 32 3

$(OBJINK_STAMP): | build
	rm -f build/objink-*.stamp
	touch $@

build/stages.asm: tools/make_stages.py tools/round_art.py tools/make_music.py tools/make_scenery.py tools/make_screens.py tools/gen_tables.py tools/make_font.py assets/stages.yaml assets/gfx/car.png $(OBJINK_STAMP) | build
	ZX_OBJINK=$(ZX_OBJINK) $(PYTHON) tools/make_stages.py assets/stages.yaml build

build/crew_data.asm: tools/make_crew.py tools/make_screens.py | build
	$(PYTHON) tools/make_crew.py $@

build/music_title.asm: tools/make_music.py | build
	$(PYTHON) tools/make_music.py $@

build/font_data.asm: tools/make_font.py | build
	$(PYTHON) tools/make_font.py $@

build/zxracer.sna: $(SRC) build/tables.asm build/stages.asm build/car_data.asm build/font_data.asm build/crew_data.asm build/music_title.asm | build
	$(ASM) $(ASMFLAGS) $(OBJINK_DEF) src/main.asm

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
	$(ASM) --nologo --msg=war --fullpath -Ibuild --sym=build/release.sym -DPROFILE=0 -DRELEASE=1 $(OBJINK_DEF) src/main.asm

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

assets/gfx/loading.scr: tools/make_screens.py tools/round_art.py tools/make_scenery.py tools/make_font.py assets/gfx/car.png
	$(PYTHON) tools/make_screens.py --loading

# Print artwork and spine lettering (needs Node with Playwright and Chromium).
cover: tools/make_cover.py | build
	mkdir -p release
	$(PYTHON) tools/make_cover.py release/cover.png build/cover.svg portrait
	$(PYTHON) tools/make_cover.py assets/gfx/spine.png build/spine.svg spine

# The route map leaflet (needs Chromium too): the stage pyramid as a printed insert
leaflet: tools/make_leaflet.py assets/stages.yaml | build
	mkdir -p release
	$(PYTHON) tools/make_leaflet.py release/route_map.png build/route_map.svg

build/video.sna: $(SRC) build/tables.asm build/stages.asm build/car_data.asm build/font_data.asm build/crew_data.asm build/music_title.asm | build
	$(ASM) --nologo --msg=war --fullpath -Ibuild --sym=build/video.sym -DPROFILE=0 -DAUTOPLAY=1 $(OBJINK_DEF) src/main.asm

video: $(ZXSIM) build/video.sna
	$(PYTHON) tools/make_video.py $(ZXSIM) build/video.sna build/gameplay.mp4 2400

# Real emulators. Set FUSE / ZESARUX to their paths in local.mk (not in git)
# if they are not on PATH. MACHINE is Fuse's (128, plus2, plus2a, plus3, 48);
# ZX_MACHINE is ZEsarUX's (128k, P2, P2A41, P341, 48k).
FUSE       ?= fuse
ZESARUX    ?= zesarux
MACHINE    ?= 128
ZX_MACHINE ?= 128k
TAPE       ?= build/speedrun.tzx
# FUSE_OPTS="--no-accelerate-loader --no-fastload --no-traps" loads at real speed
FUSE_OPTS  ?=

# the development snapshot, in Fuse
run: build/zxracer.sna
	"$(FUSE)" --machine $(MACHINE) build/zxracer.sna

# a tape image (TAPE=build/speedrun.tap for the standard one) through the ROM's loader, in Fuse
run-tape: build/speedrun.tap
	"$(FUSE)" --machine $(MACHINE) $(FUSE_OPTS) --tape $(TAPE)

# the same in ZEsarUX as a real tape (audio-level timing, as a real machine sees it)
run-realtape: build/speedrun.tap
	"$(ZESARUX)" --noconfigfile --machine $(ZX_MACHINE) --realtape "$(abspath $(TAPE))"

clean:
	rm -rf build

# ---------------------------------------------------------------------------
# Tatung Einstein (docs/port_einstein.md): build/einstein/speedrun.dsk, a
# bootable XtalDOS disc with SPEEDRUN.COM (type SPEEDRUN at the 0: prompt).
# EINSTEIN_REPO (local.mk) is the einstein repository: XtalDOS's system
# tracks, the MOS ROM and Albert's core for the test harness.
EINSTEIN_REPO   ?= $(subst \,/,$(USERPROFILE))/OneDrive/Documents/GitHub/einstein
EINSTEIN_SYSTEM ?= $(EINSTEIN_REPO)/roms/disassembled/Einstein/__XTALDOS131/SYSTEM131.CPM
EINSTEIN_ROM    ?= $(EINSTEIN_REPO)/roms/Tatung X-TAL MOS v1.2 (1983)(Tatung).rom
EIN_SRC := $(wildcard src/einstein/*.asm)
EIN_GEN := build/einstein/einstein_objects.asm build/einstein/spider.asm build/einstein/packs.asm build/einstein/stagepacks.asm build/einstein/music_notes.asm
EIN_DAT := build/einstein/stages.asm build/einstein/stageov_pack.asm build/einstein/screens_data.asm build/einstein/stages_raw.dat build/einstein/reserve.txt

einstein: build/einstein/speedrun.dsk

release-einstein: build/einstein/speedrun.dsk
	mkdir -p release
	cp $< release/speedrun.dsk

build/einstein:
	mkdir -p build/einstein

$(EIN_GEN) &: tools/einstein_art.py tools/einstein_illustration.py tools/make_einstein.py build/stages.asm | build/einstein
	$(PYTHON) tools/make_einstein.py gen assets/stages.yaml build/einstein

# every stage's packs, each assembled where it runs, then STAGES.DAT
build/einstein/stagepacks.stamp: build/einstein/stagepacks.asm
	$(ASM) --nologo --msg=war -Ibuild -Ibuild/einstein build/einstein/stagepacks.asm
	touch $@

$(EIN_DAT) &: build/einstein/stagepacks.stamp tools/make_einstein.py tools/make_screens.py
	$(PYTHON) tools/make_einstein.py dat assets/stages.yaml build/einstein

# the front end and the overlay, assembled with the game, into STAGES.DAT
build/einstein/STAGES.DAT: build/einstein/speedrun.com build/einstein/stages_raw.dat tools/make_einstein.py
	$(PYTHON) tools/make_einstein.py patch assets/stages.yaml build/einstein

build/einstein/speedrun.com: $(SRC) $(EIN_SRC) $(EIN_GEN) $(EIN_DAT) build/music_title.asm build/tables.asm build/car_data.asm build/font_data.asm build/crew_data.asm | build/einstein
	$(ASM) --nologo --msg=war --fullpath -DEINSTEIN=1 -Ibuild -Ibuild/einstein --lst=build/einstein/speedrun.lst --sym=build/einstein/speedrun.sym src/main.asm

build/einstein/speedrun.dsk: build/einstein/speedrun.com build/einstein/STAGES.DAT tools/make_einstein_disk.py
	$(PYTHON) tools/make_einstein_disk.py -o $@ -s "$(EINSTEIN_SYSTEM)" $< build/einstein/STAGES.DAT

# The harness (Albert's core, Visual Studio's C++ tools): tests/einstein/build_harness.cmd
EIN_HARNESS := build/einstein/speedrun_check.exe
$(EIN_HARNESS): tests/einstein/speedrun_check.cpp
	ALBERT_CORE="$(shell cygpath -w "$(EINSTEIN_REPO)/emulator")" cmd.exe //c "tests\einstein\build_harness.cmd"

test-einstein: build/einstein/speedrun.dsk $(EIN_HARNESS)
	$(PYTHON) tests/einstein_check.py $(EIN_HARNESS) "$(EINSTEIN_ROM)" build/einstein/speedrun.dsk build/einstein/speedrun.sym build/einstein

# Albert, the Einstein emulator: at XtalDOS's 0: prompt type SPEEDRUN and ENTER
ALBERT ?= /c/Tatung Einstein/albert/albert.exe
run-einstein: build/einstein/speedrun.dsk
	"$(ALBERT)" --disk build/einstein/speedrun.dsk &
