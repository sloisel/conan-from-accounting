all: mygame.d64

asm := $(wildcard *.s)

sprites.s: mysprites.txt mksprites.py
	python3 mksprites.py > sprites.s

ultimate.s: ultimate.asm convert.py
	python3 convert.py > ultimate.s

mygame.d64: Makefile $(asm)
	java -jar KickAss.jar mygame.s

