.var splash = LoadBinary("conan.kla", BF_KOALA )
.segment SPLASHBITMAP
.fill splash.getBitmapSize(), splash.getBitmap(i)
.segment SPLASHSCREEN
splashScreenRam:
	.fill splash.getScreenRamSize(), splash.getScreenRam(i)
.segment SPLASHCOLOR
splashColorRam: .fill splash.getColorRamSize(), splash.getColorRam(i)
show_splash:
	lda $dd00 // select VIC bank #2
	and #%11111101
	sta $dd00
//	lda #$38
	lda #%00111111 // select bitmap and screen base address
//	lda #%11100001 // select bitmap and screen base address
	sta $d018
	lda #$d8 //#%11011000 select multicolor mode, 40 columns
	sta $d016
	lda #$3b //#%00111011 select bitmap mode, 25 rows, and vertical scrolling
	sta $d011
	lda #splash.getBackgroundColor()
	sta $d020
	sta $d021
	ldx #0
splashloop:
	.for (var i=0; i<4; i++) {
	lda splashColorRam+i*$100,x
	sta $d800+i*$100,x
	}
	inx
	bne splashloop
	rts
splashcopyscreen:
	ldx #0
splashcopyloop:
	.for (var i=0; i<4; i++) {
	lda splashScreenRam+i*$100,x
	sta $8c00+i*$100,x
	}
	inx
	bne splashcopyloop
	rts

// setup_irq: set up the interrupt handler.
// Arguments:
// X,Y: the address of the interrupt handler.
setup_irq:
	sei

	lda #$7f
	sta $dc0d
	sta $dd0d
	lda $dc0d
	lda $dd0d

	lda #$01
	sta $d01a
	lda #251
	sta $d012

	stx $fffe
	sty $ffff
	cli
	rts

irq_music:
	sta atemp1+1
	stx xtemp1+1
	sty ytemp1+1
	lsr $d019 // acknowledge interrupt
//	jsr sidplay
atemp1:	lda #$00
xtemp1:	ldx #$00
ytemp1:	ldy #$00
	rti

	.segment LOADER

//BasicUpstart2(start)

start:
//	lda #$c0 // send printing to $c000 where it is harmless
//	sta $0288
		jsr $e544 // clear screen
		lda #$01 // make screen white
		ldx #0
		sta $d020
		sta $d021
		ldx #0
startloop:
		lda loadingtext,x
		cmp #0
		beq startcontinue
		sta $0400+10+12*40,x
		lda #0
		sta $d800+10+12*40,x
		inx
		jmp startloop
startcontinue:
		lda #$00  // suppress printing during loading
		sta $009D
        lda #f_main_end-f_main
        ldx #<f_main
        ldy #>f_main
		jsr loadit
	ldx #$ff
	txs
//	lda %00110100
//	sta $01
//	lda #$35   //we turn off the BASIC and KERNAL rom here
//	sta $01    //the cpu now sees RAM everywhere except at $d000-$e000, where still the registers of
           //SID/VICII/etc are visible	
//	jmp main
	clc
	jsr InitLoader
//	jsr loader_my_init
	lda #$01
	jsr LoadUnpacked
	bcs loaderror
	lda #$02
	jsr LoadUnpacked
	bcs loaderror
	jsr splashcopyscreen
	jsr show_splash
	lda #$03
	jsr LoadUnpacked
	bcs loaderror
	jsr sidinit
//	ldx #<irq_music
//	ldy #>irq_music
//	jsr setup_irq
	lda #$04
	jsr LoadUnpacked
	bcs loaderror
	lda #$05
	jsr LoadUnpacked
	bcs loaderror
	lda #$06
	jsr LoadUnpacked
	bcs loaderror
	jmp main
loaderror:
	jmp loaderror
loadit:
        jsr $FFBD     // call SETNAM
        lda #$01
        ldx $BA       // last used device number
        bne loadskip
        ldx #$08
loadskip:
		ldy #$01      // not $01 means: load to address stored in file
        jsr $FFBA     // call SETLFS
        lda #$00      // $00 means: load to memory (not verify)
        jsr $FFD5     // call LOAD
		rts
f_main:	.text "CB"
f_main_end:	
loadingtext: .text "conan from accounting"
	.byte $00

loadingpad:
	.fill $200-loadingpad,$01

