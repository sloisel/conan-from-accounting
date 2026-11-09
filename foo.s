BasicUpstart2(start)
//----------------------------------------------------------
//----------------------------------------------------------
// Simple IRQ
//----------------------------------------------------------
//----------------------------------------------------------
	* = $4000 "Main Program"
start: lda #$00
	sta $d020
	sta $d021
	lda #$00
	jsr $1000 // init music
	sei
	lda #<irq1
	sta $0314
	lda #>irq1
	sta $0315
	lda #$7f
	sta $dc0d
	sta $dd0d
	lda #$81
	sta $d01a
	lda #$1b
	sta $d011
	lda #$80
	sta $d012
	lda $dc0d
	lda $dd0d
	asl $d019
	cli
	jmp *
//----------------------------------------------------------
irq1: asl $d019
	SetBorderColor(2)
	jsr $1003 // play music
	SetBorderColor(0)
	jmp $ea81
//----------------------------------------------------------
*=$1000 "Music"
.import binary "ode to 64.bin"
//----------------------------------------------------------
// A little macro
.macro SetBorderColor(color) {
	lda #color
	sta $d020
}
