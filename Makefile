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

build/zxracer.sna: $(SRC) build/tables.asm | build
	$(ASM) $(ASMFLAGS) src/main.asm

$(ZXSIM): tools/zxsim/zxsim.c | build
	$(CC) -O2 -Wall -o $@ $<

build/cputest.sna: tests/cputest.asm | build
	$(ASM) --nologo --msg=war tests/cputest.asm

# CPU core self-test, then a smoke run of the game with screenshots
test: $(ZXSIM) build/cputest.sna build/zxracer.sna
	$(PYTHON) tests/run_cputest.py $(ZXSIM) build/cputest.sna
	$(PYTHON) tests/smoke.py $(ZXSIM) build/zxracer.sna build

# Border-bar profile: T-states per phase per game frame
profile: $(ZXSIM) build/zxracer.sna
	$(PYTHON) tools/profile.py $(ZXSIM) build/zxracer.sna

run: build/zxracer.sna
	fuse --machine 128 build/zxracer.sna

clean:
	rm -rf build
