	.var mapwidth=64
	.var mapheight=64
	.var charbuf1=$0400
	.var charbuf2=$0800
	.var colbuf=$D800
	.var readyprompt=$A483
	.var charsetaddr=$3800
	.var vichposval=%11010000
	.var vichpos=$D016
	.var vicvposval=%00010000
	.var vicvpos=$D011
	.var vicpointers=$D018
	.var vicbuf1=((((>charset)>>2)&14)|(((>charbuf1)&60)<<2)|1)
	.var vicbuf2=((((>charset)>>2)&14)|(((>charbuf2)&60)<<2)|1)
	.var spritesaddr=$1200
.var sprite_xlo=0
.var sprite_xhi=32
.var sprite_y=64
.var sprite_color=96
.var sprite_pointer=128


	.disk [filename="mygame.d64", name="mygame", id="2025!" ]
	{
	[name="MYGAME", type="prg", segments="LOADER" ],
	[name="MAIN", type="prg", segments="MAP,TILECHAR,TILECOL,MAIN,TABLES,CHARSET" ],
	}

	.segmentdef ZEROPAGE [start=$10]
	.segmentdef LOADER [start=$1f0]
	.segmentdef SPRITES [start=spritesaddr]
	.segmentdef CHARSET [start=charsetaddr]
	.segmentdef MAP [startAfter="CHARSET"]
	.segmentdef TILECHAR [startAfter="MAP"]
	.segmentdef TILECOL [startAfter="TILECHAR"]
	.segmentdef MAIN [startAfter="TILECOL"]
	.segmentdef TABLES [startAfter="MAIN"]


	#import "ultimate.s"
	#import "sprites.s"
//	#import "draw.s"


	.segment LOADER

//BasicUpstart2(start)

	.byte $02,$02,$02,$02,$02,$02,$02,$02
	.byte $02,$02,$02,$02,$02,$02,$02,$02
	* = $203
start:
        lda #f_main_end-f_main
        ldx #<f_main
        ldy #>f_main
        jsr $FFBD     // call SETNAM
        lda #$01
        ldx #$08
	ldy #$01      // not $01 means: load to address stored in file
        jsr $FFBA     // call SETLFS
        lda #$00      // $00 means: load to memory (not verify)
        jsr $FFD5     // call LOAD
	ldx #0
	txs
//	lda %00110100
//	sta $01
	lda #$35   //we turn off the BASIC and KERNAL rom here
	sta $01    //the cpu now sees RAM everywhere except at $d000-$e000, where still the registers of
           //SID/VICII/etc are visible

	jmp main

f_main:	.text "MAIN"
f_main_end:	
	.byte $00

	.segment ZEROPAGE
	.zp {
screen_draw_ptr:	.word 0
tile_draw_ptr:	.word 0,0,0,0
row_map_ptr:	.word 0
row_map_col:	.byte 0
screen_map_col:	.byte 0
vicflag:	.byte 0
vich:	.byte 0
vicv:	.byte 0
vicbuf:	.byte 0
temp:	.word 0
screen_x:	.byte 0
screen_y:	.byte 0
smooth_x: 	.word 0
smooth_y: 	.word 0
vel_x: .word 0
vel_y: .word 0
keyboard: .fill 8,0
player_dir: .word 0
sprite_hw_iterator: .byte 0
sprite_logical_iterator: .byte 0
sprite_logical_num: .byte 0
	}

//bits: sdaw
//654
//703
//812
.var U=41
.var V=29
	.segment TABLES
	//            -  S  E SE  W SW  -  S  N  - NE  E NW  W  N  -
	//            0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F
	dir:   .byte  0, 1, 3, 2, 7, 8, 0, 1, 5, 0, 4, 3, 6, 7, 5, 0

    //            .  S SE  E NE  N NW  W SW
	dir_x: .word  0, 0, V, U, V, 0,-V,-U,-V
	dir_y: .word  0, U, V, 0,-V,-U,-V, 0, V
	.segment MAIN

main:
	jsr initvic2
	jsr setup_irq
//	set16(tile_char_ptr,charbuf)
//	set16(tile_col_ptr,colbuf)
	//	set16(screen_map,map)
	// screen_draw_ptr: charbuf (or colbuf with screen_col)
	set16(smooth_x,0)
	set16(smooth_y,0)
	set16(vel_x,0)
	set16(vel_y,0)
/*	set8(sprite_hw_iterator,0)
	set8(sprite_logical_iterator,0)
	set8(sprite_logical_num,1)
	set8(sprite_data_1+sprite_xlo,172)
	set8(sprite_data_1+sprite_xhi,0)
	set8(sprite_data_1+sprite_y,140)
	set8(sprite_data_1+sprite_color,$0a)
	set8(sprite_data_1+sprite_pointer,spritesaddr/64)
	set8(sprite_data_2+sprite_xlo,172)
	set8(sprite_data_2+sprite_xhi,0)
	set8(sprite_data_2+sprite_y,140)
	set8(sprite_data_2+sprite_color,$0a)
	set8(sprite_data_2+sprite_pointer,spritesaddr/64)
	set8(charbuf1+1016,$0a)
	set8(charbuf2+1016,$0a)
	lda #1
	sta $d015 // enable sprite
	lda #$ff
	sta $d01c // multicolor sprites
	lda #$00 // sprite multicolor 1
	sta $D025
	lda #$01 // sprite multicolor 2
	sta $D026*/

forever:
	add16(smooth_x,smooth_x,vel_x)
	add16(smooth_y,smooth_y,vel_y)
	asr16(vel_x)
	lda vel_x+1
	and #$80
	beq nox
	add16imm(vel_x,vel_x,1)
nox:
	asr16(vel_y)
	lda vel_y+1
	and #$80
	beq noy
	add16imm(vel_y,vel_y,1)
noy:
	jsr smooth_flip
//	inc $d020
//	jsr draw
//	dec $d020
//	inc draw_x
//	inc draw_y
//	jmp forever
//	jsr GETIN
    jsr readkb
	lda keyboard+1
	and #$06
	lsr
	sta player_dir
	lda keyboard+1
	and #$20
	lsr
	lsr
	ora player_dir
	sta player_dir
	lda keyboard+2
	and #$04
//	asl
	ora player_dir
	tax
	lda dir,x
	sta player_dir
	asl
	tax
	clc
	lda dir_x,x
	adc vel_x
	sta vel_x
	lda dir_x+1,x
	adc vel_x+1
	sta vel_x+1
	clc
	lda dir_y,x
	adc vel_y
	sta vel_y
	lda dir_y+1,x
	adc vel_y+1
	sta vel_y+1
	jmp forever
	jmp ($300)

.var PRA  =  $dc00            //; CIA#1 (Port Register A)
.var DDRA =  $dc02            //; CIA#1 (Data Direction Register A)

.var PRB  =  $dc01            //; CIA#1 (Port Register B)
.var DDRB =  $dc03            //; CIA#1 (Data Direction Register B)

	.macro readkb_1(mask,col) {
		lda #mask
		sta PRA
		lda PRB
		sta keyboard+col
	}

readkb:
         lda #%11111111  // CIA#1 port A = outputs 
         sta DDRA             

         lda #%00000000  // CIA#1 port B = inputs
         sta DDRB             
	readkb_1(%11111110,0)
	readkb_1(%11111101,1)
	readkb_1(%11111011,2)
	readkb_1(%11110111,3)
	readkb_1(%11101111,4)
	readkb_1(%11011111,5)
	readkb_1(%10111111,6)
	readkb_1(%01111111,7)
	rts

initvic2:	
        lda #0
        sta vicflag
        lda #vicvposval
        sta vicv
        sta vicvpos
        lda #vichposval
        sta vich
        sta vichpos
        lda #vicbuf1
		sta vicbuf
        sta vicpointers // set screen buffer and character map addresses
        lda #COLR_SCREEN
        sta $d020 // set border color
        sta $d021 // and background color
        lda #COLR_CHAR_MC1
        sta $d022 // bg color #1
        lda #COLR_CHAR_MC2
        sta $d023 // bg color #2
	//      lda #>charbuf
	//      sta 648 // Try to keep Basic alive by telling it where the screen is
        rts

	// rasterwait: wait for raster to cross from above scanline a to below scaline a.
rasterwait:
	sta rastercomparea+1
	sta rastercomparex+1
rasterloop1:	
	lda vicvpos
	and #$80
	bne rasterloop1
rasterloop2:
	lda vicvpos+1
rastercomparea:	
	cmp #$ff
	bcs rasterloop2
	lda vicvpos
	and #$80
	bne rasterloop1
rasterloop3:
	lda vicvpos+1
rastercomparex:
	cmp #$ff
	bcc rasterloop3
	rts
	

	.macro tiledraw(buf,x1,y1){
	.for(var x0=max(x1,3);x0<min(x1+4,7);x0++){
	.if(x0>max(x1,3)) iny
	.for(var y0=max(y1,3);y0<min(y1+4,7);y0++){
	lda buf+((x0-x1)+(y0-y1)*4)*numtiles,x
	sta (tile_draw_ptr+2*(y0-max(y1,3))),y
	}
	}
	rts
	}

tile_char00:	tiledraw(tilechar,0,0)
tile_char01:	tiledraw(tilechar,0,1)
tile_char02:	tiledraw(tilechar,0,2)
tile_char03:	tiledraw(tilechar,0,3)
tile_char04:	tiledraw(tilechar,0,4)
tile_char05:	tiledraw(tilechar,0,5)
tile_char06:	tiledraw(tilechar,0,6)

tile_char10:	tiledraw(tilechar,1,0)
tile_char11:	tiledraw(tilechar,1,1)
tile_char12:	tiledraw(tilechar,1,2)
tile_char13:	tiledraw(tilechar,1,3)
tile_char14:	tiledraw(tilechar,1,4)
tile_char15:	tiledraw(tilechar,1,5)
tile_char16:	tiledraw(tilechar,1,6)

tile_char20:	tiledraw(tilechar,2,0)
tile_char21:	tiledraw(tilechar,2,1)
tile_char22:	tiledraw(tilechar,2,2)
tile_char23:	tiledraw(tilechar,2,3)
tile_char24:	tiledraw(tilechar,2,4)
tile_char25:	tiledraw(tilechar,2,5)
tile_char26:	tiledraw(tilechar,2,6)

tile_char30:	tiledraw(tilechar,3,0)
tile_char31:	tiledraw(tilechar,3,1)
tile_char32:	tiledraw(tilechar,3,2)
tile_char33:	tiledraw(tilechar,3,3)
tile_char34:	tiledraw(tilechar,3,4)
tile_char35:	tiledraw(tilechar,3,5)
tile_char36:	tiledraw(tilechar,3,6)

tile_char40:	tiledraw(tilechar,4,0)
tile_char41:	tiledraw(tilechar,4,1)
tile_char42:	tiledraw(tilechar,4,2)
tile_char43:	tiledraw(tilechar,4,3)
tile_char44:	tiledraw(tilechar,4,4)
tile_char45:	tiledraw(tilechar,4,5)
tile_char46:	tiledraw(tilechar,4,6)

tile_char50:	tiledraw(tilechar,5,0)
tile_char51:	tiledraw(tilechar,5,1)
tile_char52:	tiledraw(tilechar,5,2)
tile_char53:	tiledraw(tilechar,5,3)
tile_char54:	tiledraw(tilechar,5,4)
tile_char55:	tiledraw(tilechar,5,5)
tile_char56:	tiledraw(tilechar,5,6)

tile_char60:	tiledraw(tilechar,6,0)
tile_char61:	tiledraw(tilechar,6,1)
tile_char62:	tiledraw(tilechar,6,2)
tile_char63:	tiledraw(tilechar,6,3)
tile_char64:	tiledraw(tilechar,6,4)
tile_char65:	tiledraw(tilechar,6,5)
tile_char66:	tiledraw(tilechar,6,6)




tile_col00:	tiledraw(tilecol,0,0)
tile_col01:	tiledraw(tilecol,0,1)
tile_col02:	tiledraw(tilecol,0,2)
tile_col03:	tiledraw(tilecol,0,3)
tile_col04:	tiledraw(tilecol,0,4)
tile_col05:	tiledraw(tilecol,0,5)
tile_col06:	tiledraw(tilecol,0,6)

tile_col10:	tiledraw(tilecol,1,0)
tile_col11:	tiledraw(tilecol,1,1)
tile_col12:	tiledraw(tilecol,1,2)
tile_col13:	tiledraw(tilecol,1,3)
tile_col14:	tiledraw(tilecol,1,4)
tile_col15:	tiledraw(tilecol,1,5)
tile_col16:	tiledraw(tilecol,1,6)

tile_col20:	tiledraw(tilecol,2,0)
tile_col21:	tiledraw(tilecol,2,1)
tile_col22:	tiledraw(tilecol,2,2)
tile_col23:	tiledraw(tilecol,2,3)
tile_col24:	tiledraw(tilecol,2,4)
tile_col25:	tiledraw(tilecol,2,5)
tile_col26:	tiledraw(tilecol,2,6)

tile_col30:	tiledraw(tilecol,3,0)
tile_col31:	tiledraw(tilecol,3,1)
tile_col32:	tiledraw(tilecol,3,2)
tile_col33:	tiledraw(tilecol,3,3)
tile_col34:	tiledraw(tilecol,3,4)
tile_col35:	tiledraw(tilecol,3,5)
tile_col36:	tiledraw(tilecol,3,6)

tile_col40:	tiledraw(tilecol,4,0)
tile_col41:	tiledraw(tilecol,4,1)
tile_col42:	tiledraw(tilecol,4,2)
tile_col43:	tiledraw(tilecol,4,3)
tile_col44:	tiledraw(tilecol,4,4)
tile_col45:	tiledraw(tilecol,4,5)
tile_col46:	tiledraw(tilecol,4,6)

tile_col50:	tiledraw(tilecol,5,0)
tile_col51:	tiledraw(tilecol,5,1)
tile_col52:	tiledraw(tilecol,5,2)
tile_col53:	tiledraw(tilecol,5,3)
tile_col54:	tiledraw(tilecol,5,4)
tile_col55:	tiledraw(tilecol,5,5)
tile_col56:	tiledraw(tilecol,5,6)

tile_col60:	tiledraw(tilecol,6,0)
tile_col61:	tiledraw(tilecol,6,1)
tile_col62:	tiledraw(tilecol,6,2)
tile_col63:	tiledraw(tilecol,6,3)
tile_col64:	tiledraw(tilecol,6,4)
tile_col65:	tiledraw(tilecol,6,5)
tile_col66:	tiledraw(tilecol,6,6)


	.macro rowinit(increment,col) {
	.if(increment) inc row_map_col
	ldy row_map_col
	lda (row_map_ptr),y
	tax
	ldy #col
	}
	.macro rowdraw(left,mid,right,dx) {
	.var x0
	rowinit(false,0)
	jsr left
	.for(x0=dx;x0<36;x0+=4) {
	rowinit(true,x0)
	jsr mid
	}
	rowinit(true,x0)
	jsr right
	rts
	}
	// row_charAB: draw a row of tile on the screen
	// Arguments:
	// tile_draw_ptr: an array of pointers to the target screen, one per each of four rows.
	// row_map_ptr: a pointer to the row of tiles to copy to screen.
	// row_map_col: 8 bit offset to add to row_map_ptr to indicate where the visible part
	// of the row begins. row_map_col gets incremented/clobbered.
	// A ranges in 0-3, B ranges in 0-6. The top-left tile starts at coordinate (A-3,B-3)
	// and the whole row should be clipped to the box [0,40)x[0,4)
	// Tile char data is taken from tilechar.
	// row_colAB is similar but copies from tilecol instead of tilechar.
row_char00:	rowdraw(tile_char00,tile_char30,tile_char40,1)
row_char01:	rowdraw(tile_char01,tile_char31,tile_char41,1)
row_char02:	rowdraw(tile_char02,tile_char32,tile_char42,1)
row_char03:	rowdraw(tile_char03,tile_char33,tile_char43,1)
row_char04:	rowdraw(tile_char04,tile_char34,tile_char44,1)
row_char05:	rowdraw(tile_char05,tile_char35,tile_char45,1)
row_char06:	rowdraw(tile_char06,tile_char36,tile_char46,1)

row_char10:	rowdraw(tile_char10,tile_char30,tile_char50,2)
row_char11:	rowdraw(tile_char11,tile_char31,tile_char51,2)
row_char12:	rowdraw(tile_char12,tile_char32,tile_char52,2)
row_char13:	rowdraw(tile_char13,tile_char33,tile_char53,2)
row_char14:	rowdraw(tile_char14,tile_char34,tile_char54,2)
row_char15:	rowdraw(tile_char15,tile_char35,tile_char55,2)
row_char16:	rowdraw(tile_char16,tile_char36,tile_char56,2)

row_char20:	rowdraw(tile_char20,tile_char30,tile_char60,3)
row_char21:	rowdraw(tile_char21,tile_char31,tile_char61,3)
row_char22:	rowdraw(tile_char22,tile_char32,tile_char62,3)
row_char23:	rowdraw(tile_char23,tile_char33,tile_char63,3)
row_char24:	rowdraw(tile_char24,tile_char34,tile_char64,3)
row_char25:	rowdraw(tile_char25,tile_char35,tile_char65,3)
row_char26:	rowdraw(tile_char26,tile_char36,tile_char66,3)

row_char30:	rowdraw(tile_char30,tile_char30,tile_char30,4)
row_char31:	rowdraw(tile_char31,tile_char31,tile_char31,4)
row_char32:	rowdraw(tile_char32,tile_char32,tile_char32,4)
row_char33:	rowdraw(tile_char33,tile_char33,tile_char33,4)
row_char34:	rowdraw(tile_char34,tile_char34,tile_char34,4)
row_char35:	rowdraw(tile_char35,tile_char35,tile_char35,4)
row_char36:	rowdraw(tile_char36,tile_char36,tile_char36,4)



row_col00:	rowdraw(tile_col00,tile_col30,tile_col40,1)
row_col01:	rowdraw(tile_col01,tile_col31,tile_col41,1)
row_col02:	rowdraw(tile_col02,tile_col32,tile_col42,1)
row_col03:	rowdraw(tile_col03,tile_col33,tile_col43,1)
row_col04:	rowdraw(tile_col04,tile_col34,tile_col44,1)
row_col05:	rowdraw(tile_col05,tile_col35,tile_col45,1)
row_col06:	rowdraw(tile_col06,tile_col36,tile_col46,1)

row_col10:	rowdraw(tile_col10,tile_col30,tile_col50,2)
row_col11:	rowdraw(tile_col11,tile_col31,tile_col51,2)
row_col12:	rowdraw(tile_col12,tile_col32,tile_col52,2)
row_col13:	rowdraw(tile_col13,tile_col33,tile_col53,2)
row_col14:	rowdraw(tile_col14,tile_col34,tile_col54,2)
row_col15:	rowdraw(tile_col15,tile_col35,tile_col55,2)
row_col16:	rowdraw(tile_col16,tile_col36,tile_col56,2)

row_col20:	rowdraw(tile_col20,tile_col30,tile_col60,3)
row_col21:	rowdraw(tile_col21,tile_col31,tile_col61,3)
row_col22:	rowdraw(tile_col22,tile_col32,tile_col62,3)
row_col23:	rowdraw(tile_col23,tile_col33,tile_col63,3)
row_col24:	rowdraw(tile_col24,tile_col34,tile_col64,3)
row_col25:	rowdraw(tile_col25,tile_col35,tile_col65,3)
row_col26:	rowdraw(tile_col26,tile_col36,tile_col66,3)

row_col30:	rowdraw(tile_col30,tile_col30,tile_col30,4)
row_col31:	rowdraw(tile_col31,tile_col31,tile_col31,4)
row_col32:	rowdraw(tile_col32,tile_col32,tile_col32,4)
row_col33:	rowdraw(tile_col33,tile_col33,tile_col33,4)
row_col34:	rowdraw(tile_col34,tile_col34,tile_col34,4)
row_col35:	rowdraw(tile_col35,tile_col35,tile_col35,4)
row_col36:	rowdraw(tile_col36,tile_col36,tile_col36,4)



	.segment MAIN

screen_init:
	txa
	asl
	sta temp
	ldx #0
screen_init_loop:
	lda screen_draw_ptr
	sta tile_draw_ptr,x
	lda screen_draw_ptr+1
	sta tile_draw_ptr+1,x
	add16imm(screen_draw_ptr,screen_draw_ptr,40)
	inx
	inx
	cpx temp
	bne screen_init_loop
	lda screen_map_col
	sta row_map_col
	cpy #0
	beq skipinc
	add16imm(row_map_ptr,row_map_ptr,64)
skipinc:	
	rts

	.macro screendraw(top,mid,bot,dy) {
	ldy #0
	ldx #dy
	jsr screen_init
	jsr top
	.var y0
	.for(y0=dy;y0<21;y0+=4) {
	ldy #1
	ldx #4
	jsr screen_init
	jsr mid
	}
	ldy #1
	ldx #25-y0
	jsr screen_init
	jsr bot
	rts
	}

	// screen_charAB: draw whole screen of tiles
	// Arguments:
	// row_map_ptr: the start of the row of tiles at the top of the screen.
	// This will get incremented/clobbered.
	// screen_draw_ptr: initialize to charbuf or colbuf.
	// screen_map_col: an offset into row_map_ptr for the top-leftmost tile on screen.
	// A,B range in 0-3. Tiles are offset left 3-A characters, and up 3-B characters.
	// Tile characters are read from tilechar.
	// screen_colAB: similar but reads from tilecol instead of tilechar.
screen_char00:	screendraw(row_char00,row_char03,row_char03,1)
screen_char01:	screendraw(row_char01,row_char03,row_char04,2)
screen_char02:	screendraw(row_char02,row_char03,row_char05,3)
screen_char03:	screendraw(row_char03,row_char03,row_char06,4)

screen_char10:	screendraw(row_char10,row_char13,row_char13,1)
screen_char11:	screendraw(row_char11,row_char13,row_char14,2)
screen_char12:	screendraw(row_char12,row_char13,row_char15,3)
screen_char13:	screendraw(row_char13,row_char13,row_char16,4)

screen_char20:	screendraw(row_char20,row_char23,row_char23,1)
screen_char21:	screendraw(row_char21,row_char23,row_char24,2)
screen_char22:	screendraw(row_char22,row_char23,row_char25,3)
screen_char23:	screendraw(row_char23,row_char23,row_char26,4)

screen_char30:	screendraw(row_char30,row_char33,row_char33,1)
screen_char31:	screendraw(row_char31,row_char33,row_char34,2)
screen_char32:	screendraw(row_char32,row_char33,row_char35,3)
screen_char33:	screendraw(row_char33,row_char33,row_char36,4)



screen_col00:	screendraw(row_col00,row_col03,row_col03,1)
screen_col01:	screendraw(row_col01,row_col03,row_col04,2)
screen_col02:	screendraw(row_col02,row_col03,row_col05,3)
screen_col03:	screendraw(row_col03,row_col03,row_col06,4)

screen_col10:	screendraw(row_col10,row_col13,row_col13,1)
screen_col11:	screendraw(row_col11,row_col13,row_col14,2)
screen_col12:	screendraw(row_col12,row_col13,row_col15,3)
screen_col13:	screendraw(row_col13,row_col13,row_col16,4)

screen_col20:	screendraw(row_col20,row_col23,row_col23,1)
screen_col21:	screendraw(row_col21,row_col23,row_col24,2)
screen_col22:	screendraw(row_col22,row_col23,row_col25,3)
screen_col23:	screendraw(row_col23,row_col23,row_col26,4)

screen_col30:	screendraw(row_col30,row_col33,row_col33,1)
screen_col31:	screendraw(row_col31,row_col33,row_col34,2)
screen_col32:	screendraw(row_col32,row_col33,row_col35,3)
screen_col33:	screendraw(row_col33,row_col33,row_col36,4)

	.segment TABLES
	.align $100
screen_char_table:
	.word screen_char00, screen_char10, screen_char20, screen_char30
	.word screen_char01, screen_char11, screen_char21, screen_char31
	.word screen_char02, screen_char12, screen_char22, screen_char32
	.word screen_char03, screen_char13, screen_char23, screen_char33
	.align $100
screen_col_table:
	.word screen_col00, screen_col10, screen_col20, screen_col30
	.word screen_col01, screen_col11, screen_col21, screen_col31
	.word screen_col02, screen_col12, screen_col22, screen_col32
	.word screen_col03, screen_col13, screen_col23, screen_col33

flip:	
	.byte 3,2,1,0

	.segment MAIN

screen_init2:
        lda screen_x
        and #3
	tax
	lda flip,x
        sta temp
	lda #3
        lda screen_y
        and #3
	tax
	lda flip,x
        asl
        asl
        ora temp
        asl
	sta temp
        lda #0
        sta row_map_ptr+1
//      sta temp+1
        lda screen_y
        and #%11111100
        sta row_map_ptr
        shl16(row_map_ptr)
        shl16(row_map_ptr)
        shl16(row_map_ptr)
        shl16(row_map_ptr)
        lda screen_x
        lsr
        lsr
	sta screen_map_col
        add16imm(row_map_ptr,row_map_ptr,map)
	rts

	// screen_char: draw a screenful of tiles
	// Arguments:
	// screen_x ranges 0-216
	// screen_y ranges 0-231
	// (screen_x/4,screen_y/4) is top-left tile. Remainder results in characterwise scroll.
	// screen_draw_ptr: charbuf (or colbuf with screen_col)
screen_char:
	jsr screen_init2
	lda temp
	sta whichdrawchar+1
//	lda temp+1
//	sta whichdrawchar+2
whichdrawchar:
        jmp (screen_char_table)
screen_col:
	jsr screen_init2
	lda temp
	sta whichdrawcol+1
//	lda temp+1
//	sta whichdrawcol+2
whichdrawcol:
        jmp (screen_col_table)

screen_flip:
	lda vicbuf
	cmp #vicbuf1
	beq screen_flip2
	set16(screen_draw_ptr,charbuf1)
	jmp screen_flip3
screen_flip2:
	set16(screen_draw_ptr,charbuf2)
screen_flip3:
	jsr screen_char
	lda #$80
	jsr rasterwait
	lda vicbuf
	cmp #vicbuf1
	beq screen_flip4
	lda #vicbuf1
	sta vicbuf
	jmp screen_flip5
screen_flip4:
	lda #vicbuf2
	sta vicbuf
screen_flip5:
	set16(screen_draw_ptr,colbuf)
	jsr screen_col
	rts

.segment TABLES
smoothfliptable: .byte 7,6,5,4,3,2,1,0
.segment MAIN

smooth_flip:
	lda smooth_x
	lsr
	lsr
	lsr
	lsr
	lsr
	and #7
	tax
	lda smoothfliptable,x
	ora #vichposval
	sta vich
	lda smooth_y
	lsr
	lsr
	lsr
	lsr
	lsr
	and #7
	tax
	lda smoothfliptable,x
	ora #vicvposval
	sta vicv
	lda smooth_x+1
	sta screen_x
	lda smooth_y+1
	sta screen_y
	jmp screen_flip




	.macro add16imm(result,a,b) {
	clc
	lda a
	adc #<b
	sta result
	lda a+1
	adc #>b
	sta result+1
	}
	.macro add16a(result,a) {
	clc
	adc a
	sta result
	lda a+1
	adc #0
	sta result+1
	}
	.macro add16(result,a,b) {
	clc
	lda a
	adc b
	sta result
	lda a+1
	adc b+1
	sta result+1
	}
	.macro set16(a,b) {
	lda #<b
	sta a
	lda #>b
	sta a+1
	}
	.macro set8(a,b) {
		lda #b
		sta a
	}
	.macro mov16(a,b) {
	lda b
	sta a
	lda b+1
	sta a+1
	}
	.macro shl16(z) {
	asl z
	rol z+1
	}
	.macro shr16(z) {
		lsr z+1
		ror z
	}
	.macro asr16(z) {
		lda z+1
		cmp #$80
		ror z+1
		ror z
	}

setup_irq:
sei
//lda #0
//sta irq_state

lda #$7f
sta $dc0d
sta $dd0d
lda $dc0d
lda $dd0d

lda #$01
sta $d01a
lda #250
sta $d012
lda #vicvposval
sta $d011

lda #<irq
sta $fffe
lda #>irq
sta $ffff

cli

rts
irq:
	sta atemp+1
	stx xtemp+1
	sty ytemp+1

	lsr $d019 // acknowledge interrupt
	lda vicbuf
	cmp vicpointers
	bne irqdone
	jsr swapbuffers

irqdone:
	atemp:	lda #$00
	xtemp:	ldx #$00
	ytemp:	ldy #$00
	rti

	// swapbuffers: swap the screen buffers
	// Arguments:
	// A: vicbuf1 or vicbuf2
swapbuffers:
	lda #0
	sta sprite_hw_iterator
	sta sprite_logical_iterator
	sta vicpointers
	lda vich
	sta vichpos
	lda vicv
	sta vicvpos
	rts

	.macro dosprite(buf,sbase) {
		tya
		asl
		tay
		lda sbase+sprite_xlo,x
		sta $d000,y
		lda sbase+sprite_y,x
		sta $d001,y
		tya
		lsr
		tay
		lda sbase+sprite_color,x
		sta $d027,y
		lda sbase+sprite_pointer,x
		sta buf+1016,y
		lda sbase+sprite_xhi,x
		beq sprite_clear_xhi
		lda $d010
		ora bitset,y
		jmp sprite_store_xhi
	sprite_clear_xhi:
		lda $d010
		and bitclear,y
	sprite_store_xhi:
		sta $d010
		inx
		iny
		cpy #8
		bne sprite_end
		ldy #0
	sprite_end:
		rts
	}
	// do_sprite: draw a sprite
	// Arguments:
	// X: 0-31, the "logical number" of the sprite.
	// Y: 0-7, the "physical number" of the sprite.
	// You need to set up sprite_data_1 or sprite_data_2,
	// depending on which buffer is selected by vicbuf.
do_sprite:
	lda vicbuf
	cmp #vicbuf2
	beq do_sprite_2
do_sprite_1: dosprite(charbuf1,sprite_data_1)
do_sprite_2: dosprite(charbuf2,sprite_data_2)

//schedule_refresh:
//	lda #255
//	sta $d012
//	jmp irqdone

	.segment TABLES
	.align 32
sprite_data_1: .fill 5*32,0
	.align 32
sprite_data_2: .fill 5*32,0
bitset: .byte 1,2,4,8,16,32,64,128
bitclear: .byte 255-1,255-2,255-4,255-8,255-16,255-32,255-64,255-128

