# Build requires sjasmplus >= 1.20 on PATH (https://github.com/z00m128/sjasmplus)
ASM      ?= sjasmplus
ASMFLAGS ?= --nologo --fullpath --lst=build/zxracer.lst --sym=build/zxracer.sym

SRC := $(wildcard src/*.asm)

.PHONY: all clean run
all: build/zxracer.sna

build/zxracer.sna: $(SRC) | build
	$(ASM) $(ASMFLAGS) src/main.asm

build:
	mkdir -p build

run: build/zxracer.sna
	fuse --machine 128 build/zxracer.sna

clean:
	rm -rf build
