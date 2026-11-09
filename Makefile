all: mygame.d64

asm := $(wildcard *.s)

sprites.s: mysprites.txt mksprites.py
	python3 mksprites.py > sprites.s

ultimate.s: ultimate.asm convert.py
	python3 convert.py > ultimate.s

spawns.s: ultimate.s tools/gen_spawns.py
	python3 tools/gen_spawns.py > spawns.s

mygame.d64: Makefile KickAss.cfg $(asm)
	java -jar KickAss.jar mygame.s

# play it: normal window, sound, real speed
run: mygame.d64
	x64sc -autostart mygame.d64

# automated smoke test: VICE in the background at warp speed, no focus steal
test: mygame.d64
	python3 tools/smoketest.py

# AGSP raster prototype: verify all 1024 ring positions (after timing changes)
test-agsp:
	build/asm.sh
	python3 tools/vice.py stop; sleep 1
	python3 tools/vice.py start build/agsp.prg
	VICE_SYMS=build/agsp.vs python3 tools/vice.py until mainloop 30
	VICE_SYMS=build/agsp.vs python3 tools/agsp_check.py all
	python3 tools/vice.py stop

.PHONY: all run test test-agsp
