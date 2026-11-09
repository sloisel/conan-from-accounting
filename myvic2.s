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
// ($ff is not used: its last 8 bytes are glyph $ff, shown blank in the
// open border below the window -- myui.s; UI_BLK + 5 is spare AG_ALT space)
.var clipList = List().add($dd, $de, $df, $f7, $f8, $f9, $fc, $fd, $fe, UI_BLK + 5)
clip_blocks: .fill clipList.size(), clipList.get(i)
.for (var i = 0; i < clipList.size(); i++) {
    .var a0 = clipList.get(i) * 64
    .assert "clip block above the map's glyphs", a0 < charsetaddr || a0 >= charsetaddr + $b8 * 8, true
    .assert "clip block clear of block $ff (blank sprite block, glyph $ff)", a0 + 64 <= UI_BLANK_BLK * 64, true
    .assert "clip block clear of the status strip's pictures and AG_ALT's mirror",
            a0 >= (UI_BLK + 5) * 64 || a0 + 64 <= UI_BLK * 64, true
    .assert "clip block clear of AG_ALT's mirrored slots", a0 >= AG_ALT + 977 || a0 + 64 <= AG_ALT + 977 || a0 >= $1000, true
    .assert "clip block clear of pointer-slot glyphs", a0 + 64 <= AG_PTRGLYPH || a0 >= AG_PTRGLYPH + 64, true
    .assert "clip block clear of pointer-slot blocks", a0 >= (AG_PTRCODE + 8) * 64 || a0 + 64 <= AG_PTRCODE * 64, true
}
clip_base:   .byte 0, CLIP_SET
clip_parity: .byte 0
clip_next:   .byte 0
clip_limit:  .byte 0

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
    bcs cs_done
    lda sprite_data_2+sprite_clip,x
    beq cs_next
    ldy clip_next
    cpy clip_limit
    bcc !+
    lda #0                  // out of spare blocks: hide this one
    sta sprite_data_2+sprite_y,x
    jmp cs_next
!:  inc clip_next
    jsr clip_one
    ldx cl_x
cs_next:
    inx
    jmp cs_loop
cs_done:
    rts

// clip_one: X = sprite, Y = index of its spare block in clip_blocks. The
// block gets the sprite frame's visible rows (from row `clip` on) followed by
// empty rows, and becomes the sprite's pointer. A block keeps what it holds:
// if that is already this frame with this clip (a sprite resting at the
// edge), nothing is copied; otherwise an unrolled copy is entered at the
// right point (13 cycles per byte), and only the bytes it held beyond the
// new visible part are cleared (usually a row or two as a sprite slides).
clip_one:
    stx cl_x
    sty cl_slot
    lda sprite_data_2+sprite_clip,x
    sta cl_c
    lda sprite_data_2+sprite_pointer,x
    sta sprite_data_2+sprite_srcptr,x
    cmp clip_blk_src,y
    bne cl_fill
    lda cl_c
    cmp clip_blk_clip,y
    beq cl_set              // already there
    lda sprite_data_2+sprite_pointer,x
cl_fill:                    // A = source frame
    sta clip_blk_src,y
    tax
    lda cl_c
    sta clip_blk_clip,y
    lda clip_blocks,y
    tay
    lda cl_blk_lo,y         // destination: block * 64
    sta temp4
    lda cl_blk_hi,y
    sta temp4+1
    ldy cl_c
    lda cl_blk_lo,x         // source: frame * 64 + 3 * clip (low 6 bits free)
    ora cl_mul3,y
    sta temp3
    lda cl_blk_hi,x
    sta temp3+1
    lda cl_copy_lo,y        // copy 63 - 3 * clip bytes
    sta cl_vec
    lda cl_copy_hi,y
    sta cl_vec+1
    ldy #0
    jsr cl_go               // Y = bytes copied
    sty cl_n
    ldx cl_slot
    lda clip_blk_end,x      // what it held may go further: clear the rest
    pha
    tya
    sta clip_blk_end,x
    pla
    sec
    sbc cl_n                // count
    beq cl_set
    bcc cl_set
    eor #$ff
    sec
    adc #63                 // enter at 63 - count
    tax
    lda cl_zero_lo,x
    sta cl_vec
    lda cl_zero_hi,x
    sta cl_vec+1
    lda #0
    jsr cl_go
cl_set:
    ldy cl_slot
    lda clip_blocks,y
    ldx cl_x
    sta sprite_data_2+sprite_pointer,x
    rts
cl_go:
    jmp (cl_vec)
cl_copy:
    .for (var i = 0; i < 63; i++) {
    lda (temp3),y
    sta (temp4),y
    iny
    }
    rts
cl_zero:
    .for (var i = 0; i < 63; i++) {
    sta (temp4),y
    iny
    }
    rts
cl_copy_lo: .fill 21, <(cl_copy + 15 * i)       // skip 3 * clip copies
cl_copy_hi: .fill 21, >(cl_copy + 15 * i)
cl_zero_lo: .fill 64, <(cl_zero + 3 * i)
cl_zero_hi: .fill 64, >(cl_zero + 3 * i)
cl_mul3:    .fill 21, 3 * i
cl_blk_lo:  .fill 256, (i << 6) & 255
cl_blk_hi:  .fill 256, i >> 2

.segment TABLES
cl_vec:        .word 0
.assert "cl_vec not on a page end (jmp indirect)", (cl_vec & $ff) != $ff, true
cl_x:          .byte 0
cl_slot:       .byte 0
cl_c:          .byte 0
cl_n:          .byte 0
clip_blk_src:  .fill clipList.size(), 0       // what each spare block holds
clip_blk_clip: .fill clipList.size(), 0
clip_blk_end:  .fill clipList.size(), 63      // bytes up to which it may be non-empty

.segment MAIN
// The raster interrupts live in myagsp.s; the multiplexer (mymux.s) writes
// the hardware sprite registers.

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



