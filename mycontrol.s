//bits: sdaw
//654
//703
//812
.var U=116
.var V=82
.var Ux=96
.var Uy=72
.var Vx=68
.var Vy=51
.var Sx=32*24
.var Tx=Sx-2*32
.var Sy=32*21
.var Ty=Sy-2*32
.var sp0=spritebase/64
	.segment TABLES
	//            -  S  E SE  W SW  -  S  N  - NE  E NW  W  N  -
	//            0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F
	dir:   .byte  0, 1, 3, 2, 7, 8, 0, 1, 5, 0, 4, 3, 6, 7, 5, 0

    //            .   S  SE   E  NE   N  NW   W  SW
	dir_x: .word  0,  0, Vx, Ux, Vx,  0,-Vx,-Ux,-Vx
	dir_y: .word  0, Uy, Vy,  0,-Vy,-Uy,-Vy,  0, Vy
	sword_x: .word 0, 0, Tx, Sx, Tx,  0,-Tx,-Sx,-Tx
	sword_y: .word 0,Sy, Ty,  0,-Ty,-Sy,-Ty,  0, Ty

.var st=3
.var player_list = List().add(
		st,sp0+0,st,sp0+2,st,sp0+0,st,sp0+3,0,
		st,sp0+5,st,sp0+7,st,sp0+5,st,sp0+8,0,
		st,sp0+10,st,sp0+12,st,sp0+10,st,sp0+13,0,
		st,sp0+15,st,sp0+17,st,sp0+15,st,sp0+18,0,
		st,sp0+20,st,sp0+22,st,sp0+20,st,sp0+23,0,
		st,sp0+25,st,sp0+27,st,sp0+25,st,sp0+28,0,
		st,sp0+30,st,sp0+32,st,sp0+30,st,sp0+33,0,
		st,sp0+35,st,sp0+37,st,sp0+35,st,sp0+38,0,
		255,sp0+0,10,sp0+1,0,
		255,sp0+5,10,sp0+6,0,
		255,sp0+10,10,sp0+11,0,
		255,sp0+15,10,sp0+16,0,
		255,sp0+20,10,sp0+21,0,
		255,sp0+25,10,sp0+26,0,
		255,sp0+30,10,sp0+31,0,
		255,sp0+35,10,sp0+36,0,
		4,sp0+4,0,
		4,sp0+9,0,
		4,sp0+14,0,
		4,sp0+19,0,
		4,sp0+24,0,
		4,sp0+29,0,
		4,sp0+34,0,
		4,sp0+39,0)
.macro anim(z) {
	.for(var k=0;k<z.size();k++) {
		.byte z.get(k)
	}
}
.macro index(z) {
	.byte 0
	.for(var k=0;k<z.size()-1;k++) {
		.if(z.get(k)==0) .byte k+1
	}
}
player_anim: anim(player_list)
player_index: index(player_list)
.var sword_list = List().add(
		5,sp0+40,0,
		5,sp0+41,0,
		5,sp0+42,0,
		5,sp0+43,0,
		5,sp0+44,0,
		5,sp0+45,0,
		5,sp0+46,0,
		5,sp0+47,0,
		5,sp0+48,0)
sword_anim: anim(sword_list)
sword_index: index(sword_list)

.var star_list = List().add(
	5,sp0+50,5,sp0+51,5,sp0+52,5,sp0+53,0
)
star_anim: anim(star_list)
star_index: index(star_list)
controllers: .word control_nop, control_sword, control_basic
animations: .word player_anim, sword_anim, star_anim
indices: .word player_index, sword_index, star_index
.segment MAIN

.var delx=160*32
//.var maxx=55296
.var maxx=55808
.var dely=100*32
//.var maxy=59136
.var maxy=59392

// control_path_test: test to see if a sprite can move to a given location.
// Arguments:
// temp - x coordinate
// temp2 - y coordinate
// Returns:
// Result is provided in "zero" status flag. So you'd do:
//    jsr control_path_test
//    bne cannot_move
// or
//    beq can_move
control_path_test:
	lda #0    // initialize path array index (low byte)
	sta temp3
	ldy temp2+1 // find array offset due to y coordinate in temp2
	iny
	tya
	lsr
	.for(var i=0;i<4;i++) {
		lsr
		ror temp3
	}
	sta temp3+1
	ldy temp+1 // find array offset due to x coordinate in temp
	iny
	tya
	lsr
	sta temp4
	lsr
	lsr
	lsr
	ora temp3
	sta temp3 // now temp3 contains the array offset
	add16 temp3:temp3+1:#<pathing:#>pathing:temp3:temp3+1 // add offset to array base
	lda temp4 // find which bit is relevant
	and #7
	tay
	lda bitset,y
	ldy #0 // check to see if the corresponding bit is set
	and (temp3),y
	rts

// control_move: try to move a sprite.
// Arguments:
// X - sprite index
control_move:
	add16 temp :temp+1 :sprite_data_2+sprite_global_xlo,x:sprite_data_2+sprite_global_xhi,x:sprite_data_2+sprite_dxlo,x:sprite_data_2+sprite_dxhi,x
	add16 temp2:temp2+1:sprite_data_2+sprite_global_ylo,x:sprite_data_2+sprite_global_yhi,x:sprite_data_2+sprite_dylo,x:sprite_data_2+sprite_dyhi,x
	jsr control_path_test
	beq control_move_ok
	add16 temp :temp+1 :sprite_data_2+sprite_global_xlo,x:sprite_data_2+sprite_global_xhi,x:sprite_data_2+sprite_dxlo,x:sprite_data_2+sprite_dxhi,x
	set8 temp2:sprite_data_2+sprite_global_ylo,x
	set8 temp2+1:sprite_data_2+sprite_global_yhi,x
	jsr control_path_test
	beq control_move_ok
	set8 temp:sprite_data_2+sprite_global_xlo,x
	set8 temp+1:sprite_data_2+sprite_global_xhi,x
	add16 temp2:temp2+1:sprite_data_2+sprite_global_ylo,x:sprite_data_2+sprite_global_yhi,x:sprite_data_2+sprite_dylo,x:sprite_data_2+sprite_dyhi,x
	jsr control_path_test
	beq control_move_ok
	set8 temp2:sprite_data_2+sprite_global_ylo,x
	set8 temp2+1:sprite_data_2+sprite_global_yhi,x
control_move_ok:
	set8 sprite_data_2+sprite_global_xlo,x:temp
	set8 sprite_data_2+sprite_global_xhi,x:temp+1
	set8 sprite_data_2+sprite_global_ylo,x:temp2
	set8 sprite_data_2+sprite_global_yhi,x:temp2+1
	rts


control_player_keyboard:
	lda keyboard+4
	and #4
	sta player_sword
	bne control_direction
	jmp update_vel0
control_direction:
	lda sprite_data_2+sprite_anim // check to see if we're in the middle of sword stroke
	cmp player_index+16
	bcs update_vel0
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
	ora player_dir
	tax
	lda dir,x
	sta player_dir
	cmp #0
	beq do_direction
	sta player_dir_nz
do_direction:
	asl
	tax
	bne update_vel
update_vel0:
	ldx #0
update_vel:
	set8 sprite_data_2+sprite_dxlo:dir_x,x
	set8 sprite_data_2+sprite_dxhi:dir_x+1,x
	set8 sprite_data_2+sprite_dylo:dir_y,x
	set8 sprite_data_2+sprite_dyhi:dir_y+1,x
	ldx #0
	jsr control_move
	sub16 ::sprite_data_2+sprite_global_xlo:sprite_data_2+sprite_global_xhi:#<maxx+delx:#>maxx+delx
	bcs rightside
	sub16 smooth_x:smooth_x+1:sprite_data_2+sprite_global_xlo:sprite_data_2+sprite_global_xhi:#<delx:#>delx
	bcc leftside
	jmp leftrightok
rightside:
	set16(smooth_x,maxx)
	jmp leftrightok
leftside:
	set16(smooth_x,0)
leftrightok:
	sub16 ::sprite_data_2+sprite_global_ylo:sprite_data_2+sprite_global_yhi:#<maxy+dely:#>maxy+dely
	bcs bottomside
	sub16 smooth_y:smooth_y+1:sprite_data_2+sprite_global_ylo:sprite_data_2+sprite_global_yhi:#<dely:#>dely
	bcc topside
	jmp topbottomok
bottomside:
	set16(smooth_y,maxy)
	jmp topbottomok
topside:
	set16(smooth_y,0)
topbottomok:
	ldx #0
	jsr control_coords
	rts

control_coords:
	sub16 sprite_data_2+sprite_xlo,x:sprite_data_2+sprite_xhi,x:sprite_data_2+sprite_global_xlo,x:sprite_data_2+sprite_global_xhi,x:smooth_x:smooth_x+1
	shr16 sprite_data_2+sprite_xlo,x:sprite_data_2+sprite_xhi,x
	shr16 sprite_data_2+sprite_xlo,x:sprite_data_2+sprite_xhi,x
	shr16 sprite_data_2+sprite_xlo,x:sprite_data_2+sprite_xhi,x
	shr16 sprite_data_2+sprite_xlo,x:sprite_data_2+sprite_xhi,x
	shr16 sprite_data_2+sprite_xlo,x:sprite_data_2+sprite_xhi,x
	add16 sprite_data_2+sprite_xlo,x:sprite_data_2+sprite_xhi,x:sprite_data_2+sprite_xlo,x:sprite_data_2+sprite_xhi,x:#<20:#>20
	sub16 sprite_data_2+sprite_y,x:sprite_data_2+sprite_yhi,x:sprite_data_2+sprite_global_ylo,x:sprite_data_2+sprite_global_yhi,x:smooth_y:smooth_y+1
	shr16 sprite_data_2+sprite_y,x:sprite_data_2+sprite_yhi,x
	shr16 sprite_data_2+sprite_y,x:sprite_data_2+sprite_yhi,x
	shr16 sprite_data_2+sprite_y,x:sprite_data_2+sprite_yhi,x
	shr16 sprite_data_2+sprite_y,x:sprite_data_2+sprite_yhi,x
	shr16 sprite_data_2+sprite_y,x:sprite_data_2+sprite_yhi,x
	add16 sprite_data_2+sprite_y,x:sprite_data_2+sprite_yhi,x:sprite_data_2+sprite_y,x:sprite_data_2+sprite_yhi,x:#<42:#>42
	rts

control_sword:
	lda player_dir_nz
	asl
	tax
	add16 sprite_data_2+1+sprite_global_xlo:sprite_data_2+1+sprite_global_xhi:sprite_data_2+sprite_global_xlo:sprite_data_2+sprite_global_xhi:sword_x,x:sword_x+1,x
	add16 sprite_data_2+1+sprite_global_ylo:sprite_data_2+1+sprite_global_yhi:sprite_data_2+sprite_global_ylo:sprite_data_2+sprite_global_yhi:sword_y,x:sword_y+1,x
	ldx player_dir_nz
//	lda player_sword
//	beq control_sword_stab
	lda sprite_data_2+sprite_anim // check to see if we're in the middle of sword stroke
	cmp player_index+16
	bcs control_sword_stab
	ldx #0
control_sword_stab:
	ldy sword_index,x
	sty sprite_data_2+1+sprite_anim
	lda sword_anim,y
	sta sprite_data_2+1+sprite_delay
	iny
	tya
	sta sprite_data_2+1+sprite_frame
	ldx #1
	jsr control_coords
	rts

control_nop:
	rts

control_basic:
	jsr control_coords
	rts

control_player:
	jsr control_player_keyboard
	lda sprite_data_2+sprite_anim // check to see if we're in the middle of sword stroke
	cmp player_index+16
	bcc control_player_normal
	lda sprite_data_2+sprite_delay
	cmp #1
	bne control_player_end
	lda player_sword
	bne control_player_normal
	inc sprite_data_2+sprite_delay
control_player_normal: // we are not in the middle of a sword stroke, see if we need to start one
	lda player_sword
	beq control_player_sword
	ldx player_dir // check to see if we're idle
	beq control_player_idle
	dex // we're not idle, set animation if necessary
	lda player_index,x
	cmp sprite_data_2+sprite_anim
	beq control_player_end
	tay
	sta sprite_data_2+sprite_anim
	lda player_anim,y
	sta sprite_data_2+sprite_delay
	iny
	tya
	sta sprite_data_2+sprite_frame
	jmp control_player_end
control_player_idle: // we're idle, play blinking animation
	ldx player_dir_nz
	lda player_index+7,x
	cmp sprite_data_2+sprite_anim
	beq control_player_end
	tay
	sta sprite_data_2+sprite_anim
	lda player_anim,y
	sta sprite_data_2+sprite_delay
	iny
	tya
	sta sprite_data_2+sprite_frame
	jmp control_player_end
control_player_sword: // sword stab, see if we're already in the middle of a sword stroke
	ldx player_dir_nz
	lda player_index+15,x
//	cmp sprite_data_2+sprite_anim
//	bne control_player_sword2
//	inc sprite_data_2+sprite_delay
//	jmp control_player_end
//control_player_sword2: // this is a fresh new sword stab
	tay
	sta sprite_data_2+sprite_anim
	lda player_anim,y
	sta sprite_data_2+sprite_delay
	iny
	sty sprite_data_2+sprite_frame
//	iny
//	tya
//	sta sprite_data_2+sprite_frame
control_player_end:
	rts


// sprite_alloc: allocate a sprite.
// Arguments:
// Register Y: desired sprite controller.
// Returns:
// Register X: sprite index.
// If no sprite is available, X is set to 32 and zero flag is set. So you can detect this with:
//    jsr sprite_alloc
//    beq sprite_alloc_failed
sprite_alloc:
    ldx sprite2_count
    cpx #32
    bne sprite_alloc_ok
    rts
sprite_alloc_ok:
    inc sprite2_count
    lda sprite_data_2+sprite_order,x
    tax
    tya
	sta sprite_data_2+sprite_controller,x
    rts

// sprite_set_anim: set sprite animation.
// Arguments:
// Register X: sprite index.
// Register A: animation index.
sprite_init:
    pha
	ldy sprite_data_2+sprite_controller,x
    lda indices,y
    sta sprite_init_load_index+1
    lda indices+1,y
    sta sprite_init_load_index+2
    lda animations,y
    sta sprite_init_load_anim+1
    lda animations+1,y
    sta sprite_init_load_anim+2
    pla
    tay
sprite_init_load_index:
    lda $ffff,y
    sta sprite_data_2+sprite_anim,x
    tay
    jsr sprite_init_load_anim
    sta sprite_data_2+sprite_delay,x
    iny
    tya
    sta sprite_data_2+sprite_frame,x
    jsr sprite_init_load_anim
    sta sprite_data_2+sprite_pointer,x
    rts
sprite_init_load_anim:
    lda $ffff,y
    rts

sprite_from_tile:
    cpx #64
    bcs finish2
    cpy #64
    bcs finish2
//xxxx: jmp xxxx
	stx temp4
	sty temp4+1
sprite_reader:
    lda $ffff,x
	tay
	lda tiletag,y
    bmi finish
	tay
	set8 sprite_writer+1:sprite_reader+1
	set8 sprite_writer+2:sprite_reader+2
	lda empty_tile_numbers,y
sprite_writer:
	sta $ffff,x
    jsr sprite_alloc
	beq finish
	lda #0
	jsr sprite_init

	lda temp4
	asl
	asl
	clc
	adc #2
	sta sprite_data_2+sprite_global_xhi,x

	lda temp4+1
	asl
	asl
	adc #2
	sta sprite_data_2+sprite_global_yhi,x

	lda #0
	sta sprite_data_2+sprite_global_ylo,x
	sta sprite_data_2+sprite_global_xlo,x
finish:
	ldx temp4
	ldy temp4+1
finish2:
//	jmp finish2
	rts

sprite_from_tiles:
	lda #0
	sta sprite_reader+1
	lda smooth_x
	lsr
	lsr
	tax
	dex
	stx temp
	clc
	adc #11
	sta temp+1
	lda smooth_y
	lsr
	lsr
	tay
	dey
	adc #4
	sta sprite_from_tiles_cpy
	tya
	lsr
	ror sprite_reader+1
	lsr
	ror sprite_reader+1
	clc
	adc #>map
	sta sprite_reader+2
	jsr sprite_tile_row
	jsr sprite_tile_next_row
sprite_from_tiles_loop:
	ldx temp
	jsr sprite_from_tile
	ldx temp+1
	jsr sprite_from_tile
	jsr sprite_tile_next_row
sprite_from_tiles_cpy:
	cpy #0
	bne sprite_from_tiles_loop
	jsr sprite_tile_row
	rts

sprite_tile_row:
	ldx temp
sprite_tile_row_loop:
	jsr sprite_from_tile
	cpx temp+1
	beq sprite_tile_row_end
	inx
	jmp sprite_tile_row_loop
sprite_tile_row_end:
	rts

sprite_tile_next_row:
	iny
	lda sprite_reader+1
	clc
	adc #64
	sta sprite_reader+1
	sta sprite_writer+1
	lda #0
	adc sprite_reader
	sta sprite_reader
	sta sprite_writer
	rts

exec_controllers:
	ldx #0
	stx control_index
exec_controllers_loop:
	cpx sprite2_count
	beq exec_controllers_end
	ldy sprite_data_2+sprite_controller,x
	lda controllers,y
	sta exec_controllers_jsr+1
//	iny
	lda controllers+1,y
	sta exec_controllers_jsr+2
exec_controllers_jsr:
	jsr $1234
	inc control_index
	ldx control_index
	jmp exec_controllers_loop
exec_controllers_end:
	rts

exec_animations:
	ldx #0
//	stx control_index
exec_animations_loop:
	cpx sprite2_count
	beq exec_animations_end
	ldy sprite_data_2+sprite_controller,x
	lda animations,y
	sta row_map_ptr
	lda animations+1,y
	sta row_map_ptr+1
	dec sprite_data_2+sprite_delay,x
	bne exec_animations_skip
	inc sprite_data_2+sprite_frame,x
	ldy sprite_data_2+sprite_frame,x
	lda (row_map_ptr),y
	bne exec_animations_skip2
	lda sprite_data_2+sprite_anim,x
	sta sprite_data_2+sprite_frame,x
	tay
	lda (row_map_ptr),y
exec_animations_skip2:
	sta sprite_data_2+sprite_delay,x
	inc sprite_data_2+sprite_frame,x
exec_animations_skip:
	ldy sprite_data_2+sprite_frame,x
	lda (row_map_ptr),y
	sta sprite_data_2+sprite_pointer,x
	tay
	lda spritecolors-sp0,y
	sta sprite_data_2+sprite_color,x
	inx
//	foo:jmp foo
	jmp exec_animations_loop
exec_animations_end:
	rts

