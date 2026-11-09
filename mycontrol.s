//bits: sdaw
//654
//703
//812
.var U=116
.var V=82
// speeds in 1/32 pixel per frame (the game loop now runs at 50 Hz)
.var Ux=48
.var Uy=36
.var Vx=34
.var Vy=26
.var Sx=32*24
.var Tx=Sx-2*32
.var Sy=32*21
.var Ty=Sy-2*32
.var sp0=spritebase/64
	.segment TABLES
cam_px_x: .word 0               // camera position in pixels (cam_update)
cam_px_y: .word 0
cc_t:     .byte 0
cc_h:     .byte 0
	//            -  S  E SE  W SW  -  S  N  - NE  E NW  W  N  -
	//            0  1  2  3  4  5  6  7  8  9  A  B  C  D  E  F
	dir:   .byte  0, 1, 3, 2, 7, 8, 0, 1, 5, 0, 4, 3, 6, 7, 5, 0

    //            .   S  SE   E  NE   N  NW   W  SW
	dir_x: .word  0,  0, Vx, Ux, Vx,  0,-Vx,-Ux,-Vx
	dir_y: .word  0, Uy, Vy,  0,-Vy,-Uy,-Vy,  0, Vy
	sword_x: .word 0, 0, Tx, Sx, Tx,  0,-Tx,-Sx,-Tx
	sword_y: .word 0,Sy, Ty,  0,-Ty,-Sy,-Ty,  0, Ty

.var st=6
.var player_list = List().add(
		st,sp0+0,st,sp0+2,st,sp0+0,st,sp0+3,0,
		st,sp0+5,st,sp0+7,st,sp0+5,st,sp0+8,0,
		st,sp0+10,st,sp0+12,st,sp0+10,st,sp0+13,0,
		st,sp0+15,st,sp0+17,st,sp0+15,st,sp0+18,0,
		st,sp0+20,st,sp0+22,st,sp0+20,st,sp0+23,0,
		st,sp0+25,st,sp0+27,st,sp0+25,st,sp0+28,0,
		st,sp0+30,st,sp0+32,st,sp0+30,st,sp0+33,0,
		st,sp0+35,st,sp0+37,st,sp0+35,st,sp0+38,0,
		255,sp0+0,20,sp0+1,0,
		255,sp0+5,20,sp0+6,0,
		255,sp0+10,20,sp0+11,0,
		255,sp0+15,20,sp0+16,0,
		255,sp0+20,20,sp0+21,0,
		255,sp0+25,20,sp0+26,0,
		255,sp0+30,20,sp0+31,0,
		255,sp0+35,20,sp0+36,0,
		8,sp0+4,0,
		8,sp0+9,0,
		8,sp0+14,0,
		8,sp0+19,0,
		8,sp0+24,0,
		8,sp0+29,0,
		8,sp0+34,0,
		8,sp0+39,0)
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
		10,sp0+40,0,
		10,sp0+41,0,
		10,sp0+42,0,
		10,sp0+43,0,
		10,sp0+44,0,
		10,sp0+45,0,
		10,sp0+46,0,
		10,sp0+47,0,
		10,sp0+48,0)
sword_anim: anim(sword_list)
sword_index: index(sword_list)

// controller numbers: 0 player, 2 sword, 4.. monsters (myenemies.s T_*)
controllers: .word control_nop, control_sword, control_blob, control_skel, control_ghost, control_cycl, control_jelly, control_wiz, control_prin
animations: .word player_anim, sword_anim, blob_anim, skel_anim, ghost_anim, cycl_anim, jelly_anim, wiz_anim, prin_anim
indices: .word player_index, sword_index, blob_index, skel_index, ghost_index, cycl_index, jelly_index, wiz_index, prin_index
.segment MAIN

// camera: player shown at (160, 83) of the 304x166 AGSP window
.var delx=160*32
.var maxx=216*256     // camera col + 39 must stay on the 256-char map
.var dely=83*32
.var maxy=234*256     // camera row + 21 must stay on the map

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
	ldy temp2+1              // row of the 128x128 bit grid (2x2 chars per bit)
	lda path_row_lo,y
	sta temp3
	lda path_row_hi,y
	sta temp3+1
	ldy temp+1
	lda path_bit,y
	sta temp4
	lda path_byte,y
	tay
	lda temp4
	and (temp3),y
	rts
// (char coordinate c -> half-tile (c+1)/2, wrapping like the 8-bit index)
path_row_lo: .fill 256, <(pathing + (((i+1)&255)>>1)*16)
path_row_hi: .fill 256, >(pathing + (((i+1)&255)>>1)*16)
path_byte:   .fill 256, (((i+1)&255)>>1)>>3
path_bit:    .fill 256, 1 << ((((i+1)&255)>>1)&7)
cc_shr5:     .fill 256, i >> 5
cc_shl3:     .fill 256, (i << 3) & 255

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
	lda has_sword            // no sword yet: J does nothing
	bne !+
	lda #4
	bne cpk_sword
!:	lda keyboard+4
	and #4
cpk_sword:
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
	lda player_hurt          // knocked back by a monster
	cmp #30
	bcc !+
	set8 sprite_data_2+sprite_dxlo:knock_dx
	set8 sprite_data_2+sprite_dxhi:knock_dx+1
	set8 sprite_data_2+sprite_dylo:knock_dy
	set8 sprite_data_2+sprite_dyhi:knock_dy+1
!:	ldx #0
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
	jsr cam_update
	ldx #0
	jsr control_coords
	rts

// cam_update: camera position in pixels (smooth >> 5), once per frame
cam_update:
	lda smooth_x+1
	sta cam_px_x+1
	lda smooth_x
	.for (var i = 0; i < 5; i++) {
	lsr cam_px_x+1
	ror
	}
	sta cam_px_x
	lda smooth_y+1
	sta cam_px_y+1
	lda smooth_y
	.for (var i = 0; i < 5; i++) {
	lsr cam_px_y+1
	ror
	}
	sta cam_px_y
	rts

// control_coords: sprite X's screen position from its world position:
// pixel = (global >> 5) - camera pixel + offset, the same rounding the
// background's fine scroll uses (no jitter between sprites and map)
control_coords:
	ldy sprite_data_2+sprite_global_xhi,x      // pixel = global / 32 (11 bits)
	lda cc_shr5,y
	sta sprite_data_2+sprite_px_hi,x
	sta cc_h
	lda cc_shl3,y
	ldy sprite_data_2+sprite_global_xlo,x
	ora cc_shr5,y
	sta sprite_data_2+sprite_px_lo,x
	sec                                        // screen x = pixel - camera + 20
	sbc cam_px_x
	tay
	lda cc_h
	sbc cam_px_x+1
	sta cc_h
	tya
	clc
	adc #20
	sta sprite_data_2+sprite_xlo,x
	lda cc_h
	adc #0
	sta sprite_data_2+sprite_xhi,x
	ldy sprite_data_2+sprite_global_yhi,x
	lda cc_shr5,y
	sta sprite_data_2+sprite_py_hi,x
	sta cc_h
	lda cc_shl3,y
	ldy sprite_data_2+sprite_global_ylo,x
	ora cc_shr5,y
	sta sprite_data_2+sprite_py_lo,x
	sec
	sbc cam_px_y
	tay
	lda cc_h
	sbc cam_px_y+1
	sta cc_h
	tya
	clc
	adc #AG_SPRITE_DY
	sta sprite_data_2+sprite_y,x
	lda cc_h
	adc #0
	sta sprite_data_2+sprite_yhi,x
	// Sprites may not touch the cycle-exact raster code above the window.
	// One that straddles the top edge is shown from the window's first
	// sprite line with its top `clip` rows cut off (clip_sprites copies the
	// visible rows); one entirely above it is parked at y=0 (top border).
	lda #0
	sta sprite_data_2+sprite_clip,x
	lda sprite_data_2+sprite_xhi,x     // off screen sideways (x < 0 or >= 344)?
	bmi control_coords_park
	beq !+
	cmp #2
	bcs control_coords_park
	lda sprite_data_2+sprite_xlo,x
	cmp #<344
	bcs control_coords_park
!:	lda sprite_data_2+sprite_yhi,x
	bne control_coords_park
	lda sprite_data_2+sprite_y,x
	cmp #AG_SPRITE_YMIN
	bcs control_coords_ok
	eor #$ff
	sec
	adc #AG_SPRITE_YMIN        // clip = YMIN - y
	cmp #21
	bcs control_coords_park
	sta sprite_data_2+sprite_clip,x
	lda #AG_SPRITE_YMIN
	sta sprite_data_2+sprite_y,x
	rts
control_coords_park:
	lda #0
	sta sprite_data_2+sprite_y,x
control_coords_ok:
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
	lda sprite_data_2+1+sprite_anim    // sword not out: no hardware sprite
	bne !+
	sta sprite_data_2+1+sprite_y
!:	rts

control_nop:
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
// If no sprite is available, carry is set. So you can detect this with:
//    jsr sprite_alloc
//    bcs sprite_alloc_failed
// (Carry rather than zero flag: Z would also be set on success whenever the
// controller number is 0.)
sprite_alloc:
    ldx sprite2_count
    cpx #32
    bcc sprite_alloc_ok
    rts
sprite_alloc_ok:
    inc sprite2_count          // sprites are kept contiguous (sprite_free)
    tya
	sta sprite_data_2+sprite_controller,x
    clc
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

exec_controllers:
	inc en_phase             // monsters think every other frame (myenemies.s)
	ldx #0
	stx control_index
exec_controllers_loop:
	cpx sprite2_count
	bcs exec_controllers_end               // (>=: a controller may free sprites)
	jsr en_offframe
	bcs exec_controllers_next              // its other frame: move completed
	ldy sprite_data_2+sprite_controller,x
	lda controllers,y
	sta exec_controllers_jsr+1
//	iny
	lda controllers+1,y
	sta exec_controllers_jsr+2
	lda #0
	sta sf_moved
exec_controllers_jsr:
	jsr $1234
	lda sf_moved             // freed: the last sprite moved into this slot,
	bne !+                   // so run this slot again
exec_controllers_next:
	inc control_index
!:	ldx control_index
	jmp exec_controllers_loop
exec_controllers_end:
	rts

exec_animations:
	ldx #0
//	stx control_index
exec_animations_loop:
	cpx sprite2_count
	bcs exec_animations_end               // (>=: a controller may free sprites)
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
	lda sprite_data_2+sprite_flash,x   // just hit: blink white
	beq ea_noflash
	dec sprite_data_2+sprite_flash,x
	and #4
	beq ea_noflash
	lda #1
	sta sprite_data_2+sprite_color,x
ea_noflash:
	inx
//	foo:jmp foo
	jmp exec_animations_loop
exec_animations_end:
	rts

