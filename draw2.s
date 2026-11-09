	.var mapwidth=64
	.var mapheight=64
	.var charbuf=$0400
	.var colbuf=$D800
	.var readyprompt=$A483
	.var charsetaddr=$3800
	.var vichposval=%11010000
	.var vichpos=$D016
	.var vicvposval=%00010000
	.var vicvpos=$D011
	.var GETIN=$FFE4
	

	.disk [filename="mygame.d64", name="mygame", id="2025!" ]
	{
	[name="MYGAME", type="prg", segments="LOADER" ],
	[name="MAIN", type="prg", segments="MAP,TILECHAR,TILECOL,MAIN,TABLES,CHARSET" ],
	}

	.segmentdef ZEROPAGE [start=$10]
	.segmentdef LOADER [start=$1f0]
	.segmentdef CHARSET [start=charsetaddr]
	.segmentdef MAP [startAfter="CHARSET"]
	.segmentdef TILECHAR [startAfter="MAP"]
	.segmentdef TILECOL [startAfter="TILECHAR"]
	.segmentdef MAIN [startAfter="TILECOL"]
	.segmentdef TABLES [startAfter="MAIN"]


	#import "ultimate.s"
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
	jmp main

f_main:	.text "MAIN"
f_main_end:	
	.byte $00

	.segment ZEROPAGE
	.zp {
draw_x:	.byte 0
draw_y:	.byte 0
temp:	.word 0
screen_map:	.word 0
row_map:	.word 0
tile_char_ptr:	.word 0
tile_col_ptr:	.word 0
vicflag:        .byte 0
vich:   .byte 0
vicv:   .byte 0
	}

	.segment MAIN

main:
	jsr initvic2
//	set16(tile_char_ptr,charbuf)
//	set16(tile_col_ptr,colbuf)
	//	set16(screen_map,map)
	lda #0
	sta draw_x
	sta draw_y
forever:
	lda #$60
	jsr rasterwait
	inc $d020
	jsr draw
	dec $d020
//	inc draw_x
//	inc draw_y
//	jmp forever
	jsr GETIN
	cmp #0
	beq forever
	cmp #$57
	bne notup
	dec draw_y
	jmp forever
notup:
	cmp #$41
	bne notleft
	dec draw_x
	jmp forever
notleft:
	cmp #$53
	bne notdown
	inc draw_y
	jmp forever
notdown:
	cmp #$44
	bne notright
	inc draw_x
	jmp forever
notright:
	jmp forever
	jmp ($300)
	
initvic2:	
        lda #0
        sta vicflag
        lda #vicvposval
        sta vicv
        sta vicvpos
        lda #vichposval
        sta vich
        sta vichpos
        lda #((((>charset)>>2)&14)|(((>charbuf)&60)<<2)|1)
        sta $d018 // set screen buffer and character map addresses
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

        .macro tilechar(tileindex,doinc) {
        lda tilechar+tileindex*numtiles,x
        sta (tile_char_ptr),y
        lda tilecol+tileindex*numtiles,x
        sta (tile_col_ptr),y
        .if(doinc) iny
        }
        .macro tilerow(tileindex,x1,x2,doinc) {
	.for(var x=x1;x<x2-1;x++) tilechar(tileindex+x,true)
        tilechar(tileindex+x2-1,false)
        .if(doinc) {
        tya
        adc #41-(x2-x1)
        tay
        }
        }
	.macro drawtile(x1,x2,y1,y2) {
	.for(var y=y1;y<y2-1;y++) {
	tilerow(4*y,x1,x2,true)
	}
	tilerow(4*(y2-1),x1,x2,false)
	rts
	}

	// drawtileabcd: draw a tile.
	// Arguments:
	// tile_char_ptr: the top-left character of the tile on screen.
	// tile_col_ptr: the top-left color of the tile on screen.
	// Register x: tile id, range 0-255.
	// Register y: initialized to 0, or initialized to 0-40 to offset the tile.
	// numbers a,b,c,d mean:
	// delete leftmost a characters from tile, delete topmost c characters from tile.
	// delete rightmost 4-b characters from tile, delete 4-d topmost characters from tile.
drawtile3434:	drawtile(3,4,3,4)
drawtile2434:	drawtile(2,4,3,4)
drawtile1434:	drawtile(1,4,3,4)
drawtile0434:	drawtile(0,4,3,4)
drawtile0334:	drawtile(0,3,3,4)
drawtile0234:	drawtile(0,2,3,4)
drawtile0134:	drawtile(0,1,3,4)

drawtile3424:	drawtile(3,4,2,4)
drawtile2424:	drawtile(2,4,2,4)
drawtile1424:	drawtile(1,4,2,4)
drawtile0424:	drawtile(0,4,2,4)
drawtile0324:	drawtile(0,3,2,4)
drawtile0224:	drawtile(0,2,2,4)
drawtile0124:	drawtile(0,1,2,4)

drawtile3414:	drawtile(3,4,1,4)
drawtile2414:	drawtile(2,4,1,4)
drawtile1414:	drawtile(1,4,1,4)
drawtile0414:	drawtile(0,4,1,4)
drawtile0314:	drawtile(0,3,1,4)
drawtile0214:	drawtile(0,2,1,4)
drawtile0114:	drawtile(0,1,1,4)

drawtile3404:	drawtile(3,4,0,4)
drawtile2404:	drawtile(2,4,0,4)
drawtile1404:	drawtile(1,4,0,4)
drawtile0404:	drawtile(0,4,0,4)
drawtile0304:	drawtile(0,3,0,4)
drawtile0204:	drawtile(0,2,0,4)
drawtile0104:	drawtile(0,1,0,4)

drawtile3403:	drawtile(3,4,0,3)
drawtile2403:	drawtile(2,4,0,3)
drawtile1403:	drawtile(1,4,0,3)
drawtile0403:	drawtile(0,4,0,3)
drawtile0303:	drawtile(0,3,0,3)
drawtile0203:	drawtile(0,2,0,3)
drawtile0103:	drawtile(0,1,0,3)

drawtile3402:	drawtile(3,4,0,2)
drawtile2402:	drawtile(2,4,0,2)
drawtile1402:	drawtile(1,4,0,2)
drawtile0402:	drawtile(0,4,0,2)
drawtile0302:	drawtile(0,3,0,2)
drawtile0202:	drawtile(0,2,0,2)
drawtile0102:	drawtile(0,1,0,2)

drawtile3401:	drawtile(3,4,0,1)
drawtile2401:	drawtile(2,4,0,1)
drawtile1401:	drawtile(1,4,0,1)
drawtile0401:	drawtile(0,4,0,1)
drawtile0301:	drawtile(0,3,0,1)
drawtile0201:	drawtile(0,2,0,1)
drawtile0101:	drawtile(0,1,0,1)

row_inc:
	.macro row_load(inc,col) {
	.if(inc) inc row_map
	ldy #0
	lda (row_map),y
	tax
	ldy #col
	}

	.macro drawrow(left,mid,right,x1) {
	.var x0
	row_load(false,0)
	jsr left
	.for(x0=x1;x0<36;x0+=4) {
	row_load(true,x0)
	jsr mid
	}
	row_load(true,x0)
	jsr right
	rts
	}

	// drawrowabc: Draw a row of tiles.
	// Arguments:
	// row_map: pointer to the leftmost tile in the map.
	// tile_char_ptr: pointer to the top-leftmost character in the row.
	// tile_col_ptr: pointer to the top-leftmost color in the row.
	// Numbers a,b,c:
	// Shift tiles a characters to the left.
	// Delete top b characters, and 4-c bottom characters.
	// Note: row_map gets incremented through the loop.
	
drawrow004:	drawrow(drawtile0404,drawtile0404,drawtile0404,4)
drawrow104:	drawrow(drawtile1404,drawtile0404,drawtile0104,3)
drawrow204:	drawrow(drawtile2404,drawtile0404,drawtile0204,2)
drawrow304:	drawrow(drawtile3404,drawtile0404,drawtile0304,1)

drawrow014:	drawrow(drawtile0414,drawtile0414,drawtile0414,4)
drawrow114:	drawrow(drawtile1414,drawtile0414,drawtile0114,3)
drawrow214:	drawrow(drawtile2414,drawtile0414,drawtile0214,2)
drawrow314:	drawrow(drawtile3414,drawtile0414,drawtile0314,1)

drawrow024:	drawrow(drawtile0424,drawtile0424,drawtile0424,4)
drawrow124:	drawrow(drawtile1424,drawtile0424,drawtile0124,3)
drawrow224:	drawrow(drawtile2424,drawtile0424,drawtile0224,2)
drawrow324:	drawrow(drawtile3424,drawtile0424,drawtile0324,1)

drawrow034:	drawrow(drawtile0434,drawtile0434,drawtile0434,4)
drawrow134:	drawrow(drawtile1434,drawtile0434,drawtile0134,3)
drawrow234:	drawrow(drawtile2434,drawtile0434,drawtile0234,2)
drawrow334:	drawrow(drawtile3434,drawtile0434,drawtile0334,1)

drawrow003:	drawrow(drawtile0403,drawtile0403,drawtile0403,4)
drawrow103:	drawrow(drawtile1403,drawtile0403,drawtile0103,3)
drawrow203:	drawrow(drawtile2403,drawtile0403,drawtile0203,2)
drawrow303:	drawrow(drawtile3403,drawtile0403,drawtile0303,1)

drawrow002:	drawrow(drawtile0402,drawtile0402,drawtile0402,4)
drawrow102:	drawrow(drawtile1402,drawtile0402,drawtile0102,3)
drawrow202:	drawrow(drawtile2402,drawtile0402,drawtile0202,2)
drawrow302:	drawrow(drawtile3402,drawtile0402,drawtile0302,1)

drawrow001:	drawrow(drawtile0401,drawtile0401,drawtile0401,4)
drawrow101:	drawrow(drawtile1401,drawtile0401,drawtile0101,3)
drawrow201:	drawrow(drawtile2401,drawtile0401,drawtile0201,2)
drawrow301:	drawrow(drawtile3401,drawtile0401,drawtile0301,1)

	// Increment screen_map, tile_char_ptr, tile_col_ptr by one row of tiles.
	// Height in characters of the row of tile is in register x
screeninc:
	lda #64
	adc screen_map
	sta screen_map
	lda #0
	adc screen_map+1
	sta screen_map+1
	txa
	adc tile_char_ptr
	sta tile_char_ptr
	lda #0
	adc tile_char_ptr+1
	sta tile_char_ptr+1
	txa
	adc tile_col_ptr
	sta tile_col_ptr
	lda #0
	adc tile_col_ptr+1
	sta tile_col_ptr+1
	lda screen_map
	sta row_map
	lda screen_map+1
	sta row_map+1
	rts

	.macro drawscreen(top,mid,bot,y1) {
	clc
	lda screen_map
	sta row_map
	lda screen_map+1
	sta row_map+1
	jsr top
	ldx #y1*40
	jsr screeninc
	.for(var row=0;row<5;row++) {
	jsr mid
	ldx #160
	jsr screeninc
	}
	jsr bot
	rts
	}

	// drawscreenab: draw a whole screen of tiles
	// Arguments:
	// screen_map: pointer to the top-leftmost tile on the screen.
	// tile_char_ptr: initialize to charbuf (will get clobbered).
	// tile_col_ptr: initialize to colbuf (will get clobbered).
	// Numbers a,b: shift the tiles a character left, b characters up.
drawscreen00:	drawscreen(drawrow004,drawrow004,drawrow001,4)
drawscreen10:	drawscreen(drawrow104,drawrow104,drawrow101,4)
drawscreen20:	drawscreen(drawrow204,drawrow204,drawrow201,4)
drawscreen30:	drawscreen(drawrow304,drawrow304,drawrow301,4)

drawscreen01:	drawscreen(drawrow014,drawrow004,drawrow002,3)
drawscreen11:	drawscreen(drawrow114,drawrow104,drawrow102,3)
drawscreen21:	drawscreen(drawrow214,drawrow204,drawrow202,3)
drawscreen31:	drawscreen(drawrow314,drawrow304,drawrow302,3)

drawscreen02:	drawscreen(drawrow024,drawrow004,drawrow003,2)
drawscreen12:	drawscreen(drawrow124,drawrow104,drawrow103,2)
drawscreen22:	drawscreen(drawrow224,drawrow204,drawrow203,2)
drawscreen32:	drawscreen(drawrow324,drawrow304,drawrow303,2)

drawscreen03:	drawscreen(drawrow034,drawrow004,drawrow004,1)
drawscreen13:	drawscreen(drawrow134,drawrow104,drawrow104,1)
drawscreen23:	drawscreen(drawrow234,drawrow204,drawrow204,1)
drawscreen33:	drawscreen(drawrow334,drawrow304,drawrow304,1)


	.segment TABLES
	.align $100
drawscreens:	
	.word drawscreen00, drawscreen10, drawscreen20, drawscreen30
	.word drawscreen01, drawscreen11, drawscreen21, drawscreen31
	.word drawscreen02, drawscreen12, drawscreen22, drawscreen32
	.word drawscreen03, drawscreen13, drawscreen23, drawscreen33

	.segment MAIN
	// draw whole screen
	// Arguments:
	// draw_x,draw_y: range 0-255. (draw_x/4,draw_y/4) is tile in upper-left corner.
	// Remainder is character offset.
draw:
	lda draw_x
	and #3
	sta temp
	lda draw_y
	and #3
	asl
	asl
	ora temp
	asl
	sta whichdraw+1
	lda #0
	sta screen_map+1
//	sta temp+1
	lda draw_y
	and #%11111100
	sta screen_map
	shl16(screen_map)
	shl16(screen_map)
	shl16(screen_map)
	shl16(screen_map)
	lda draw_x
	lsr
	lsr
	add16a(screen_map,screen_map)
	add16imm(screen_map,screen_map,map)
	set16(tile_char_ptr,charbuf)
	set16(tile_col_ptr,colbuf)
whichdraw:
	jmp (drawscreens)
	// no rts on purpose

	// rasterwait: wait for raster line between a
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
	sta result
	}
	.macro set16(a,b) {
	lda #<b
	sta a
	lda #>b
	sta a+1
	}
	.macro shl16(z) {
	asl z
	rol z+1
	}

	
