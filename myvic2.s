.segment MAIN

initvic2:
	lda $dd00 // select VIC bank #0
	and #%11111100
	ora #%00000011
	sta $dd00
    lda #vichposval // multicolour, 38 columns
    sta $d016
    lda #COLR_SCREEN
    sta $d020 // set border color
    sta $d021 // and background color
    lda #COLR_CHAR_MC1
    sta $d022 // bg color #1
    lda #COLR_CHAR_MC2
    sta $d023 // bg color #2
    lda #$ff
    sta $d01c // multicolor sprites
    lda #spritecolor1 // sprite multicolor 1
    sta $D025
    lda #spritecolor2 // sprite multicolor 2
    sta $D026
    rts

.segment TABLES
// sprite_enable_bits[n]: $d015 value with the first n hardware sprites on
sprite_enable_bits:
    .fill 32, i >= 8 ? $ff : (1 << i) - 1

// ---- top-edge sprite clipping ------------------------------------------
// A sprite straddling the top of the AGSP window is displayed from the
// window's first sprite line, using a spare sprite block that holds only its
// visible rows. Two sets of 5 spare blocks alternate every frame, so the set
// being displayed is never the one being written. The blocks: $3740-$37ff
// and unused glyph space at the top of the charset (the map uses codes up to
// $a9; $3ea8-$3ee7 holds the AGSP pointer-slot glyphs, $3540-$373f their
// sprite blocks).
.const CLIP_SET = 5

.segment SPRITES
sprites_end:
.assert "AGSP pointer-slot blocks are free", sprites_end <= AG_PTRCODE * 64, true

.segment TABLES
.var clipList = List().add($dd, $de, $df, $f7, $f8, $f9, $fc, $fd, $fe, $ff)
clip_blocks: .fill clipList.size(), clipList.get(i)
.for (var i = 0; i < clipList.size(); i++) {
    .var a0 = clipList.get(i) * 64
    .assert "clip block above the map's glyphs", a0 < charsetaddr || a0 >= charsetaddr + $aa * 8, true
    .assert "clip block clear of pointer-slot glyphs", a0 + 64 <= AG_PTRGLYPH || a0 >= AG_PTRGLYPH + 64, true
    .assert "clip block clear of pointer-slot blocks", a0 >= (AG_PTRCODE + 8) * 64 || a0 + 64 <= AG_PTRCODE * 64, true
}
clip_base:   .byte 0, CLIP_SET
clip_parity: .byte 0
clip_next:   .byte 0
clip_limit:  .byte 0
clip_block:  .byte 0
clip_n:      .byte 0

.segment MAIN
// clip_sprites: run after exec_animations (needs this frame's pointers)
clip_sprites:
    lda clip_parity
    eor #1
    sta clip_parity
    tay
    lda clip_base,y         // index into clip_blocks
    sta clip_next
    clc
    adc #CLIP_SET
    sta clip_limit
    ldx #0
cs_loop:
    cpx sprite2_count
    beq cs_done
    lda sprite_data_2+sprite_clip,x
    beq cs_next
    ldy clip_next
    cpy clip_limit
    bcc !+
    lda #0                  // out of spare blocks: hide this one
    sta sprite_data_2+sprite_y,x
    jmp cs_next
!:  inc clip_next
    lda clip_blocks,y
    sta clip_block
    jsr clip_one
cs_next:
    inx
    jmp cs_loop
cs_done:
    rts

// clip_one: X = sprite, clip_block = destination block
clip_one:
    lda clip_block          // destination = block * 64
    lsr
    lsr
    sta temp4+1
    lda clip_block
    asl
    asl
    asl
    asl
    asl
    asl
    sta temp4
    lda sprite_data_2+sprite_pointer,x
    sta sprite_data_2+sprite_srcptr,x
    lsr                     // source = frame * 64 + 3 * clip
    lsr
    sta temp3+1
    lda sprite_data_2+sprite_pointer,x
    asl
    asl
    asl
    asl
    asl
    asl
    sta temp3
    lda sprite_data_2+sprite_clip,x
    sta clip_n
    asl
    adc clip_n              // 3 * clip (clip < 21: no carry)
    sta clip_n
    clc
    adc temp3
    sta temp3
    bcc !+
    inc temp3+1
!:  lda #63
    sec
    sbc clip_n
    sta clip_n              // visible bytes
    ldy #0
!:  lda (temp3),y
    sta (temp4),y
    iny
    cpy clip_n
    bne !-
    lda #0
!:  sta (temp4),y           // rows below the visible part: empty
    iny
    cpy #63
    bne !-
    lda clip_block
    sta sprite_data_2+sprite_pointer,x
    rts

.segment MAIN
// The raster interrupts live in myagsp.s; ag_irq_bot calls copy_sprites
// (on commit) and do_sprite for each sprite.

copy_sprites:
	lda sprite2_count
	sta sprite1_count
	ldx #0
copy_sprites_loop:
	lda sprite_data_2+sprite_xlo,x
	sta sprite_data_1+sprite_xlo,x
	lda sprite_data_2+sprite_xhi,x
	sta sprite_data_1+sprite_xhi,x
	lda sprite_data_2+sprite_y,x
	sta sprite_data_1+sprite_y,x
	lda sprite_data_2+sprite_color,x
	sta sprite_data_1+sprite_color,x
	lda sprite_data_2+sprite_pointer,x
	sta sprite_data_1+sprite_pointer,x
	inx
	cpx sprite1_count
	bcc copy_sprites_loop
	rts

// do_sprite: copy sprite data from sprite_data_1 to frame buffer.
do_sprite:
	ldx sprite_logical_iterator
    lda sprite_hw_iterator
    asl
    tay
    lda sprite_data_1+sprite_xlo,x
    sta $d000,y
    lda sprite_data_1+sprite_y,x
    sta $d001,y
	ldy sprite_hw_iterator
    lda sprite_data_1+sprite_color,x
    sta $d027,y
    lda sprite_data_1+sprite_pointer,x
    sta AG_SCREEN+$3f8,y
    lda sprite_data_1+sprite_xhi,x
    beq sprite_clear_xhi
    lda $d010
    ora bitset,y
    jmp sprite_store_xhi
sprite_clear_xhi:
    lda $d010
    and bitclear,y
sprite_store_xhi:
    sta $d010
	inc sprite_logical_iterator
	iny
    cpy #8
    bne sprite_end
	ldy #0
sprite_end:
    sty sprite_hw_iterator
    rts


.var PRA  =  $dc00            //; CIA#1 (Port Register A)
.var DDRA =  $dc02            //; CIA#1 (Data Direction Register A)

.var PRB  =  $dc01            //; CIA#1 (Port Register B)
.var DDRB =  $dc03            //; CIA#1 (Data Direction Register B)

.macro readkb_1(mask,col) {
		lda #mask
		sta PRA
		lda PRB
		and debug_keys+col // lets the debugger inject keypresses (all $ff = no effect)
		sta keyboard+col
}

.segment TABLES
// debug_keys: AND-mask applied to each keyboard matrix row. A cleared bit
// is a "pressed" key. Written by tools/vice.py through the VICE monitor.
debug_keys: .fill 8,$ff
.segment MAIN

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



