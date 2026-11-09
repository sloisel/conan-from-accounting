.segment ZEROPAGE
	* = $10 virtual
	.zp {
charptr:	.word 0
colptr:		.word 0
offset:		.word 0
rownum:	.byte 0
colnum:	.byte 0
mapx:	.byte 0
mapy:	.byte 0
mapxindex:	.byte 0
mapyindex:	.byte 0
mapxiter:	.byte 0
leftcol: .byte 0
toprow:	.byte 0
mapoffset:	.word 0
smoothx:	.word 0
smoothy:	.word 0
temp:	.word 0
vicflag:	.byte 0
vich:	.byte 0
vicv:	.byte 0
	}

	.segment MAIN
main:
	jsr initvic2
	set16(smoothx,0)
	set16(smoothy,0)
forever2:
	jsr smoothmap
//	add16imm(smoothx,smoothx,1)
	add16imm(smoothy,smoothy,1)
	jmp forever2
	jmp ($300)

//	jmp mytest
	lda #0
	sta mapx
	sta mapy
forever3:
	jsr drawmap
	inc mapx
	inc mapy
	jmp forever3
	
mytest:	
	lda #10
	sta mapx
	sta mapy
	jsr parsecoords
	.var col=10
	.var row=10
	lda #row
	sta rownum
	lda #col
	sta colnum
	set16(offset,row*40)
	jsr setmapoffset
	ldy mapxindex
	lda (mapoffset),y
	tax
	jsr cliptile
forever:	jmp forever
	jmp ($300)

initvic2:	
//	lda #%00110100
//	sta $01   // make more ram available
//	lda $dd02
//	ora #3
//	sta $dd02 // permit us to choose the vic bank please
//	lda $dd00
//	and #%11111100
//	ora #%00000001
//	sta $dd00 // vic bank is now $8000
//	lda #%11010000
	//	sta $d016 // multicolor mode is bit 4
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
//	lda #>charbuf
//	sta 648 // Try to keep Basic alive by telling it where the screen is
	rts


	.segment TABLES
hflipper:
	.byte vichposval+7,vichposval+6,vichposval+5,vichposval+4
	.byte vichposval+3,vichposval+2,vichposval+1,vichposval
vflipper:
	.byte vicvposval+0,vicvposval+7,vicvposval+6,vicvposval+5,vicvposval+4
	.byte vicvposval+3,vicvposval+2,vicvposval+1 //,vicvposval+0
	.segment MAIN

	// smoothmap: fills the screen with the map.
	// Arguments:
	// smoothx,smoothy: 16-bis signed coordinates of top-leftmost pixel. Conversion to character
	// coordinate is smoothx>>3, smoothy>>3, sub-character distance goes into vic smooth scrolling.
smoothmap:	{
rasterwait:	
	lda vicvpos+1
	cmp #$60
	bne rasterwait
	lda vicvpos
	and #$80
	bne rasterwait
	inc $d020
	lda smoothx
	and #7
	tax
	lda hflipper,x
	sta vich
	lda smoothy
	and #7
	tax
	lda vflipper,x
	sta vicv
	lda #$80
	sta vicflag
	jsr drawmap
	dec $d020
	mov16(temp,smoothx)
	shr16(temp)
	shr16(temp)
	shr16(temp)
	lda temp
	sta mapx
	mov16(temp,smoothy)
	shr16(temp)
	shr16(temp)
	shr16(temp)
	lda temp
	sta mapy
	rts
	}
	
	// drawmap: fills the screen with the map
	// Arguments:
	// mapx, mapy: 8 bit coordinates of top-left character. Conversion to "map coordinates" is given
	// by mapx>>2,mapy>>2.
drawmap: {
	jsr parsecoords
	lda toprow
	sta rownum
	jsr setmapoffset
	jsr cliptilerow
	lda rownum
	clc
	adc #4
	sta rownum
	add16imm(mapoffset,mapoffset,64)
	add16imm(offset,offset,160)
outerloop:
	jsr cliptilerow
	add16imm(mapoffset,mapoffset,64)
	add16imm(offset,offset,160)
	lda rownum
	clc
	adc #4
	sta rownum
	cmp #22
	bcc outerloop
endloop:
	jsr cliptilerow
	rts
	}

	// cliptilerow: draw a whole row of tiles, clipped.
	// Arguments:
	// mapxindex: the x index into the row of tiles
	// leftcol: the column of the left edge of the first tile
	// mapoffset: a pointer to the row on the map
	// rownum: positiom on the screen
	// offset: 40*rownum
cliptilerow:	{
	lda mapxindex
	sta mapxiter
	lda leftcol
	sta colnum
rowloop:	
	ldy mapxiter
	lda (mapoffset),y
	tax
	jsr cliptile
	lda colnum
	cmp #40
	bpl rowend
	clc
	adc #4
	sta colnum
	inc mapxiter
	jmp rowloop
rowend:	
	rts
	}

	// drawtilerow: draw a whole row of tiles. Inner tiles are not clipped for speed.
	// Arguments:
	// mapxindex: the x index into the row of tiles
	// leftcol: the column of the left edge of the first tile
	// mapoffset: a pointer to the row on the map
	// rownum: positiom on the screen
	// offset: 40*rownum
drawtilerow:	{
	lda mapxindex
	sta mapxiter
	lda leftcol
	sta colnum
	ldy mapxiter
	lda (mapoffset),y
	tax
	jsr cliptile
	lda colnum
	clc
	adc #4
	sta colnum
	inc mapxiter
rowloop:
	ldy mapxiter
	lda (mapoffset),y
	tax
	jsr drawtile
	inc mapxiter
	lda colnum
	clc
	adc #4
	sta colnum
	cmp #37
	bmi rowloop
rowend:
	ldy mapxiter
	lda (mapoffset),y
	tax
	jsr cliptile
	rts
	}

// setmapoffset: sets mapoffset = 64*mapyindex
setmapoffset:	{
	lda #0
	sta mapoffset+1
	lda mapyindex
	ldx #6
mul64:
	asl
	rol mapoffset+1
	dex
	bne mul64
	sta mapoffset
	add16imm(mapoffset,mapoffset,map)
	rts
	}
	
	
	.segment TABLES
coordpos:
	.byte 0,-1,-2,-3
coordoffsetslo:
	.byte <0,<-1*40,<-2*40,<-3*40
coordoffsetshi:
	.byte >0,>-1*40,>-2*40,>-3*40

	.segment MAIN
	// parsecoords: initialize leftcol,toprow,offset,mapxindex,mapyindex from mapx,mapy
parsecoords:
	lda mapx
	and #3
	tay
	lda coordpos,y
	sta leftcol
	lda mapx
	lsr
	lsr
	sta mapxindex
	lda mapy
	and #3
	tay
	lda coordpos,y
	sta toprow
	lda coordoffsetslo,y
	sta offset
	lda coordoffsetshi,y
	sta offset+1
	lda mapy
	lsr
	lsr
	sta mapyindex
	rts
	

	// drawtile: Draw a 4x4 map tile, no clipping performed.
	// Arguments:
	// rownum: 8 bit row index. Normal range is 0-21, otherwise you will write off-screen.
	// colnum: 8 bit column index. Range is 0-36, otherwise you will write off-screen or wrap around.
	// offset: 16 bit, this should be set to 40*row.
	// X: 8 bit unsigned tile number
drawtile:
	add16imm(charptr,offset,charbuf)
	add16imm(colptr,offset,colbuf)
	clc
	ldy colnum
	drawrow(0,true)
	drawrow(4,true)
	drawrow(8,true)
	drawrow(12,false)
	rts

	// cliptile: Draw a 4x4 map tile, with clipping to screen boundary.
	// Arguments:
	// rownum: 8 bit signed row index. Screen range is 0-24, if row<0 or row>21, clipping will occur.
	// colnum: 8 bit signed column index. Screen range is 0-39, if col<0 or col>36, clipping will occur.
	// offset: 16 bit signed, this should be set to 40*row (i.e. will be negative if row<0).
	// X: 8 bit unsigned tile number
cliptile:
//	lda colnum
//	cmp #0
//	bmi doclip
//	cmp #37
//	bpl doclip
//	lda rownum
//	cmp #0
//	bmi doclip
//	cmp #21
//	bpl doclip
//	jmp drawtile
doclip:	
	add16imm(charptr,offset,charbuf)
	add16imm(colptr,offset,colbuf)
	cliprow(0,true,0,25)
	cliprow(4,true,-1,24)
	cliprow(8,true,-2,23)
	cliprow(12,false,-3,22)
	rts

	.macro mov16(a,b) {
	lda b
	sta a
	lda b+1
	sta a+1
	}
	.macro shr16(a){
	lsr a+1
	ror a
	}
	.macro set16(mem,imm) {
	lda #<imm
	sta mem
	lda #>imm
	sta mem+1
	}
	.macro add16(result,a,b) {
	lda a
	clc
	adc b
	sta result
	lda a+1
	adc b+1
	sta result+1
	}
	.macro add16imm(result,a,b) {
	lda a
	clc
	adc #<b
	sta result
	lda a+1
	adc #>b
	sta result+1
	}
	.macro drawchar(tileindex,doinc) {
	lda tilechar+tileindex*numtiles,x
	sta (charptr),y
	lda tilecol+tileindex*numtiles,x
	sta (colptr),y
	.if(doinc) iny
	}
	.macro drawrow(tileindex,doinc) {
	drawchar(tileindex,true)
	drawchar(tileindex+1,true)
	drawchar(tileindex+2,true)
	drawchar(tileindex+3,false)
	.if(doinc) {
	tya
	adc #37
	tay
	}
	}
	.macro clipchar(tileindex,doinc) {
	cpy #00
	bmi skipchar
	cpy #40
	bpl skipchar
	lda tilechar+tileindex*numtiles,x
	sta (charptr),y
	lda tilecol+tileindex*numtiles,x
	sta (colptr),y
skipchar:	
	.if(doinc) iny
	}
	.macro cliprow(tileindex,doinc,rowmin,rowmax) {
	lda rownum
	cmp #rowmin
	//	bcc skiprow
	bmi skiprow
	cmp #rowmax
	//	bcs skiprow
	bpl skiprow
	ldy colnum
	clipchar(tileindex,true)
	clipchar(tileindex+1,true)
	clipchar(tileindex+2,true)
	clipchar(tileindex+3,false)
skiprow:	
	.if(doinc) {
	add16imm(charptr,charptr,40)
	add16imm(colptr,colptr,40)
	}
	}

	.align $100

