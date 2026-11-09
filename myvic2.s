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



