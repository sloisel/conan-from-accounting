// myenemies.s: monsters.
//
// Spawn points come from spawns.s (tools/gen_spawns.py, by biome and route
// progression). spawn_update activates a spawn point when it comes near the
// screen and there is a free sprite; en_common despawns a monster that
// wandered far off screen (its spawn point becomes idle again) and handles
// sword hits and touching the player. A killed monster's spawn point stays
// dead. Without a sprite multiplexer at most 8 sprites exist: player, sword
// and up to 6 monsters.
//
// Types (= controller numbers, see mycontrol.s):
//   blob      rolls left/right, rotating the way it rolls; turns at walls
//   skeleton  wanders in 4 directions, sometimes heads for the player
//   ghost     drifts towards the player through walls, eyes follow
//   cyclops   patrols; charges when the player lines up with it
//   jelly     turns on the spot, sinks, resurfaces near the player
//   wizard    friendly, near the start: hands over the sword, then vanishes
//   princess  at the pond, behind her guards: touch her to win

.const T_BLOB = 4
.const T_SKEL = 6
.const T_GHOST = 8
.const T_CYCL = 10
.const T_JELLY = 12
.const T_WIZ = 14
.const T_PRIN = 16
.const MAX_SPRITES = 8
.const INTANGIBLE = $80                // sprite_state bit: no hits, no contact

.segment TABLES
// per type (index = type / 2)
en_hp_tab:     .byte 0, 0, 1, 2, 1, 3, 2, 255, 255
debug_freeze_enemies: .byte 0          // tests: monsters keep still, no (de)spawning
has_sword:     .byte 0                 // given by the wizard
player_hurt:   .byte 0                 // frames of knockback/invulnerability left
knock_dx:      .word 0
knock_dy:      .word 0
spawn_rr:      .byte 0
en_t:          .byte 0
en_h:          .byte 0
en_sgn:        .byte 0
en_ax:         .byte 0                 // |dx|, |dy| in pixels (255 = far)
en_ay:         .byte 0
en_sx:         .byte 0                 // 1 if this sprite is left of / above the other
en_sy:         .byte 0
en_tmp:        .byte 0
en_ox:         .word 0
en_oy:         .word 0
sat_n:         .byte 0
sp_i:          .byte 0
// 4 directions: 0 down, 1 right, 2 up, 3 left (velocity tables in 1/32 px)
.var skelv = 20
.var cyclv = 16
.var chargev = 72
dir4_dx_skel:  .word 0, skelv, 0, -skelv
dir4_dy_skel:  .word skelv, 0, -skelv, 0
dir4_dx_cycl:  .word 0, cyclv, 0, -cyclv
dir4_dy_cycl:  .word cyclv, 0, -cyclv, 0
dir4_dx_chg:   .word 0, chargev, 0, -chargev
dir4_dy_chg:   .word chargev, 0, -chargev, 0

// animations (delay, frame; 0 ends a sequence) and their start indices
.var blob_list = List().add(
    8,sp0+49, 8,sp0+50, 8,sp0+51, 8,sp0+52, 0,      // 0: rolling right
    8,sp0+52, 8,sp0+51, 8,sp0+50, 8,sp0+49, 0)      // 1: rolling left
.var skel_list = List().add(
    10,sp0+53, 10,sp0+54, 10,sp0+53, 10,sp0+55, 0,  // 0: down
    10,sp0+56, 10,sp0+57, 10,sp0+56, 10,sp0+58, 0,  // 1: right
    10,sp0+59, 10,sp0+60, 10,sp0+59, 10,sp0+61, 0,  // 2: up
    10,sp0+62, 10,sp0+63, 10,sp0+62, 10,sp0+64, 0)  // 3: left
.var ghost_list = List().add(
    255,sp0+82, 0,   // 0: looking down
    255,sp0+79, 0,   // 1: right
    255,sp0+81, 0,   // 2: up
    255,sp0+80, 0)   // 3: left
.var cycl_list = List().add(
    14,sp0+65, 14,sp0+66, 0,   // 0..3: walking down/right/up/left
    14,sp0+67, 14,sp0+68, 0,
    14,sp0+69, 14,sp0+70, 0,
    14,sp0+71, 14,sp0+72, 0,
    4,sp0+65, 4,sp0+66, 0,     // 4..7: charging
    4,sp0+67, 4,sp0+68, 0,
    4,sp0+69, 4,sp0+70, 0,
    4,sp0+71, 4,sp0+72, 0)
.var jelly_list = List().add(
    12,sp0+73, 12,sp0+74, 12,sp0+75, 12,sp0+76, 0,  // 0: turning on the spot
    255,sp0+77, 0)                                   // 1: sunk
.var wiz_list = List().add(255,sp0+78, 0)
.var prin_list = List().add(60,sp0+83, 8,sp0+84, 0)

blob_anim:  anim(blob_list)
blob_index: index(blob_list)
skel_anim:  anim(skel_list)
skel_index: index(skel_list)
ghost_anim: anim(ghost_list)
ghost_index: index(ghost_list)
cycl_anim:  anim(cycl_list)
cycl_index: index(cycl_list)
jelly_anim: anim(jelly_list)
jelly_index: index(jelly_list)
wiz_anim:   anim(wiz_list)
wiz_index:  index(wiz_list)
prin_anim:  anim(prin_list)
prin_index: index(prin_list)

.segment MAIN

// ---- helpers -----------------------------------------------------------

// en_rnd: A = pseudo random byte (clobbers Y)
en_rnd:
    ldy rand_index
    lda randperm,y
    inc rand_index
    rts

// sprite_anim_to: X = sprite, A = animation number; restart only if changed
sprite_anim_to:
    sta sat_n
    ldy sprite_data_2+sprite_controller,x
    lda indices,y
    sta sat_ld+1
    lda indices+1,y
    sta sat_ld+2
    ldy sat_n
sat_ld:
    lda $ffff,y
    cmp sprite_data_2+sprite_anim,x
    beq !+
    lda sat_n
    jmp sprite_init
!:  rts

// sprite_free: X = sprite (>= 2); the last sprite moves into its slot
sprite_free:
    ldy sprite2_count
    dey
    .for (var f = 0; f < sprite_nfields; f++) {
    lda sprite_data_2+f*32,y
    sta sprite_data_2+f*32,x
    }
    dec sprite2_count
    rts

// en_abs_px: A:en_t = signed difference in 1/32 px. Returns A = |d| in
// pixels (255 if 255 or more), en_sgn = 1 if d < 0. Keeps X and Y.
en_abs_px:
    sta en_h
    lda #0
    sta en_sgn
    lda en_h
    bpl !+
    inc en_sgn
    lda en_t
    eor #$ff
    clc
    adc #1
    sta en_t
    lda en_h
    eor #$ff
    adc #0
    sta en_h
!:  lda en_h
    cmp #$20
    bcs !+
    lda en_t
    lsr
    lsr
    lsr
    lsr
    lsr
    sta en_t
    lda en_h
    asl
    asl
    asl
    ora en_t
    rts
!:  lda #255
    rts

// en_dist: X = this sprite, Y = other -> en_ax, en_ay (pixels), en_sx, en_sy
en_dist:
    sec
    lda sprite_data_2+sprite_global_xlo,x
    sbc sprite_data_2+sprite_global_xlo,y
    sta en_t
    lda sprite_data_2+sprite_global_xhi,x
    sbc sprite_data_2+sprite_global_xhi,y
    jsr en_abs_px
    sta en_ax
    lda en_sgn
    sta en_sx
    sec
    lda sprite_data_2+sprite_global_ylo,x
    sbc sprite_data_2+sprite_global_ylo,y
    sta en_t
    lda sprite_data_2+sprite_global_yhi,x
    sbc sprite_data_2+sprite_global_yhi,y
    jsr en_abs_px
    sta en_ay
    lda en_sgn
    sta en_sy
    rts

// en_save_pos / en_moved: did control_move change the position?
en_save_pos:
    lda sprite_data_2+sprite_global_xlo,x
    sta en_ox
    lda sprite_data_2+sprite_global_xhi,x
    sta en_ox+1
    lda sprite_data_2+sprite_global_ylo,x
    sta en_oy
    lda sprite_data_2+sprite_global_yhi,x
    sta en_oy+1
    rts
en_moved:                       // Z = 1 if the sprite did not move
    lda sprite_data_2+sprite_global_xlo,x
    cmp en_ox
    bne !+
    lda sprite_data_2+sprite_global_xhi,x
    cmp en_ox+1
    bne !+
    lda sprite_data_2+sprite_global_ylo,x
    cmp en_oy
    bne !+
    lda sprite_data_2+sprite_global_yhi,x
    cmp en_oy+1
!:  rts

// en_set_vel: X = sprite, Y = 2 * dir, table pair given by the macro
.macro en_set_vel(tx, ty) {
    lda tx,y
    sta sprite_data_2+sprite_dxlo,x
    lda tx+1,y
    sta sprite_data_2+sprite_dxhi,x
    lda ty,y
    sta sprite_data_2+sprite_dylo,x
    lda ty+1,y
    sta sprite_data_2+sprite_dyhi,x
}

// en_toward: dir (0 down, 1 right, 2 up, 3 left) from this sprite towards
// the player along the longer axis (en_dist must have been called with Y=0)
en_toward:
    lda en_ax
    cmp en_ay
    bcc !+
    lda en_sx                   // horizontal: left of the player -> right
    beq en_tw_left
    lda #1
    rts
en_tw_left:
    lda #3
    rts
!:  lda en_sy                   // vertical: above the player -> down
    beq en_tw_up
    lda #0
    rts
en_tw_up:
    lda #2
    rts

// ---- common to all monsters --------------------------------------------
en_despawn:                     // (kept close: reached by short branches)
    ldy sprite_data_2+sprite_spawn,x
    lda #0
    sta spawn_state,y
    jsr sprite_free
    sec
    rts
en_ok0:
    clc
    rts

// en_common: X = monster. Despawn when far, sword hits, touching the player.
// Returns C = 1 if the monster is gone (the caller must just return).
en_common:
    lda debug_freeze_enemies
    beq !+
    jsr control_coords
    sec
    rts
!:  lda sprite_data_2+sprite_global_xhi,x   // far from the camera?
    sec
    sbc smooth_x+1
    clc
    adc #14
    cmp #68
    bcs en_despawn
    lda sprite_data_2+sprite_global_yhi,x
    sec
    sbc smooth_y+1
    clc
    adc #14
    cmp #50
    bcs en_despawn
    lda sprite_data_2+sprite_state,x
    bmi en_ok0                  // intangible (sunk jelly)
    lda sprite_data_2+sprite_controller,x
    cmp #T_WIZ
    bcs en_ok0                  // wizard and princess are friendly
    lda sprite_data_2+1+sprite_anim     // sword out?
    beq en_touch
    lda sprite_data_2+sprite_flash,x
    bne en_touch                // just hit: invulnerable for a moment
    ldy #1
    jsr en_dist
    lda en_ax
    cmp #14
    bcs en_touch
    lda en_ay
    cmp #16
    bcs en_touch
    lda #16                     // hit!
    sta sprite_data_2+sprite_flash,x
    dec sprite_data_2+sprite_hp,x
    bne en_touch
    ldy sprite_data_2+sprite_spawn,x        // killed
    lda #2
    sta spawn_state,y
    jsr sprite_free
    sec
    rts
en_touch:
    lda player_hurt
    bne en_ok
    ldy #0
    jsr en_dist
    lda en_ax
    cmp #12
    bcs en_ok
    lda en_ay
    cmp #14
    bcs en_ok
    lda #40                     // knock the player away from the monster
    sta player_hurt
    lda #<48
    ldy #>48
    ldx en_sx                   // monster left of the player: push right
    bne !+
    lda #<-48
    ldy #>-48
!:  sta knock_dx
    sty knock_dx+1
    lda #<48
    ldy #>48
    ldx en_sy
    bne !+
    lda #<-48
    ldy #>-48
!:  sta knock_dy
    sty knock_dy+1
    ldx control_index
en_ok:
    clc
    rts

// ---- spawning ----------------------------------------------------------
// spawn_update: look at a few spawn points per frame; activate those near
// the screen when there is a free sprite
spawn_update:
    lda debug_freeze_enemies
    bne su_end
    lda #8
    sta sp_i
su_next:
    ldx spawn_rr
    inx
    cpx #SPAWN_N
    bcc !+
    ldx #0
!:  stx spawn_rr
    lda spawn_state,x
    bne su_skip
    lda spawn_tx,x              // tile centre (chars) relative to the camera
    asl
    asl
    sec
    sbc smooth_x+1
    clc
    adc #2+6
    cmp #40+12
    bcs su_skip
    lda spawn_ty,x
    asl
    asl
    sec
    sbc smooth_y+1
    clc
    adc #2+6
    cmp #22+12
    bcs su_skip
    lda sprite2_count
    cmp #MAX_SPRITES
    bcs su_end
    jsr en_spawn
su_skip:
    dec sp_i
    bne su_next
su_end:
    rts

// en_spawn: X = spawn point
en_spawn:
    lda #1
    sta spawn_state,x
    stx en_tmp
    ldy spawn_type,x
    jsr sprite_alloc            // X = new sprite
    ldy en_tmp
    tya
    sta sprite_data_2+sprite_spawn,x
    lda spawn_tx,y
    asl
    asl
    clc
    adc #1
    sta sprite_data_2+sprite_global_xhi,x
    lda spawn_ty,y
    asl
    asl
    clc
    adc #1
    sta sprite_data_2+sprite_global_yhi,x
    lda #0
    sta sprite_data_2+sprite_global_xlo,x
    sta sprite_data_2+sprite_global_ylo,x
    sta sprite_data_2+sprite_state,x
    sta sprite_data_2+sprite_flash,x
    sta sprite_data_2+sprite_dxlo,x
    sta sprite_data_2+sprite_dxhi,x
    sta sprite_data_2+sprite_dylo,x
    sta sprite_data_2+sprite_dyhi,x
    sta sprite_data_2+sprite_clip,x
    lda sprite_data_2+sprite_controller,x
    lsr
    tay
    lda en_hp_tab,y
    sta sprite_data_2+sprite_hp,x
    jsr en_rnd
    and #3
    sta sprite_data_2+sprite_dir,x
    jsr en_rnd
    and #31
    clc
    adc #20
    sta sprite_data_2+sprite_timer,x
    lda #0
    jsr sprite_init
    jsr control_coords
    ldx en_tmp
    rts

// map_clear_markers: the map editor's spawn-marker tiles (tag < $80)
// become their background tile (start-up only: uses zero page temp)
map_clear_markers:
    lda #<map
    sta temp
    lda #>map
    sta temp+1
    ldx #16
mc_page:
    ldy #0
mc_loop:
    lda (temp),y
    sty en_tmp
    tay
    lda tiletag,y
    bmi mc_keep
    tay
    lda empty_tile_numbers,y
    ldy en_tmp
    sta (temp),y
    jmp mc_next
mc_keep:
    ldy en_tmp
mc_next:
    iny
    bne mc_loop
    inc temp+1
    dex
    bne mc_page
    rts

// ---- behaviours (X = sprite on entry; must end with control_coords) -----

control_blob:
    jsr en_common
    bcc !+
    rts
!:  lda sprite_data_2+sprite_dir,x
    and #1
    sta sprite_data_2+sprite_dir,x
    lda #24                     // 0.75 px per frame
    ldy sprite_data_2+sprite_dir,x
    beq !+
    lda #<-24
!:  sta sprite_data_2+sprite_dxlo,x
    and #$80
    beq !+
    lda #$ff
!:  sta sprite_data_2+sprite_dxhi,x
    lda #0
    sta sprite_data_2+sprite_dylo,x
    sta sprite_data_2+sprite_dyhi,x
    jsr en_save_pos
    jsr control_move
    jsr en_moved
    bne !+
    lda sprite_data_2+sprite_dir,x   // bumped into something: roll back
    eor #1
    sta sprite_data_2+sprite_dir,x
!:  lda sprite_data_2+sprite_dir,x
    jsr sprite_anim_to
    jmp control_coords

control_skel:
    jsr en_common
    bcc !+
    rts
!:  dec sprite_data_2+sprite_timer,x
    bne sk_walk
    jsr en_rnd                  // new direction: towards the player 1 in 3
    and #63
    clc
    adc #40
    sta sprite_data_2+sprite_timer,x
    jsr en_rnd
    cmp #85
    bcs !+
    ldy #0
    jsr en_dist
    jsr en_toward
    jmp sk_dir
!:  and #3
sk_dir:
    sta sprite_data_2+sprite_dir,x
sk_walk:
    lda sprite_data_2+sprite_dir,x
    asl
    tay
    en_set_vel(dir4_dx_skel, dir4_dy_skel)
    jsr en_save_pos
    jsr control_move
    jsr en_moved
    bne !+
    lda #1                      // blocked: pick a new direction next frame
    sta sprite_data_2+sprite_timer,x
!:  lda sprite_data_2+sprite_dir,x
    jsr sprite_anim_to
    jmp control_coords

control_ghost:
    jsr en_common
    bcc !+
    rts
!:  ldy #0
    jsr en_dist
    jsr en_toward
    jsr sprite_anim_to
    lda en_ax                   // drift 12/32 px per frame on each axis
    cmp #3
    bcc gh_y
    lda en_sx
    beq !+
    add16 sprite_data_2+sprite_global_xlo,x:sprite_data_2+sprite_global_xhi,x:sprite_data_2+sprite_global_xlo,x:sprite_data_2+sprite_global_xhi,x:#12:#0
    jmp gh_y
!:  sub16 sprite_data_2+sprite_global_xlo,x:sprite_data_2+sprite_global_xhi,x:sprite_data_2+sprite_global_xlo,x:sprite_data_2+sprite_global_xhi,x:#12:#0
gh_y:
    lda en_ay
    cmp #3
    bcc gh_done
    lda en_sy
    beq !+
    add16 sprite_data_2+sprite_global_ylo,x:sprite_data_2+sprite_global_yhi,x:sprite_data_2+sprite_global_ylo,x:sprite_data_2+sprite_global_yhi,x:#12:#0
    jmp gh_done
!:  sub16 sprite_data_2+sprite_global_ylo,x:sprite_data_2+sprite_global_yhi,x:sprite_data_2+sprite_global_ylo,x:sprite_data_2+sprite_global_yhi,x:#12:#0
gh_done:
    jmp control_coords

control_cycl:
    jsr en_common
    bcc !+
    rts
!:  lda sprite_data_2+sprite_state,x
    cmp #1
    bne !+
    jmp cy_charge
!:  cmp #2
    bne !+
    jmp cy_rest
!:  ldy #0                      // patrol; charge when lined up with the player
    jsr en_dist
    lda en_ax
    cmp #6
    bcs !+
    lda en_ay
    cmp #90
    bcs !+
    lda en_sy                   // same column
    beq cy_up
    lda #0
    jmp cy_go
cy_up:
    lda #2
    jmp cy_go
!:  lda en_ay
    cmp #6
    bcs cy_patrol
    lda en_ax
    cmp #110
    bcs cy_patrol
    lda en_sx                   // same row
    beq cy_left
    lda #1
    jmp cy_go
cy_left:
    lda #3
cy_go:
    sta sprite_data_2+sprite_dir,x
    lda #1
    sta sprite_data_2+sprite_state,x
    jmp cy_charge
cy_patrol:
    dec sprite_data_2+sprite_timer,x
    bne !+
    jsr en_rnd
    and #63
    clc
    adc #50
    sta sprite_data_2+sprite_timer,x
    jsr en_rnd
    and #3
    sta sprite_data_2+sprite_dir,x
!:  lda sprite_data_2+sprite_dir,x
    asl
    tay
    en_set_vel(dir4_dx_cycl, dir4_dy_cycl)
    jsr en_save_pos
    jsr control_move
    jsr en_moved
    bne !+
    lda #1
    sta sprite_data_2+sprite_timer,x
!:  lda sprite_data_2+sprite_dir,x
    jsr sprite_anim_to
    jmp control_coords
cy_charge:
    lda sprite_data_2+sprite_dir,x
    asl
    tay
    en_set_vel(dir4_dx_chg, dir4_dy_chg)
    jsr en_save_pos
    jsr control_move
    jsr en_moved
    bne !+
    lda #2                      // hit a wall: catch its breath
    sta sprite_data_2+sprite_state,x
    lda #60
    sta sprite_data_2+sprite_timer,x
!:  lda sprite_data_2+sprite_dir,x
    clc
    adc #4
    jsr sprite_anim_to
    jmp control_coords
cy_rest:
    dec sprite_data_2+sprite_timer,x
    bne !+
    lda #0
    sta sprite_data_2+sprite_state,x
    lda #30
    sta sprite_data_2+sprite_timer,x
!:  lda sprite_data_2+sprite_dir,x
    jsr sprite_anim_to
    jmp control_coords

control_jelly:
    jsr en_common
    bcc !+
    rts
!:  dec sprite_data_2+sprite_timer,x
    bne je_anim
    lda sprite_data_2+sprite_state,x
    bne je_rise
    lda #INTANGIBLE             // sink
    sta sprite_data_2+sprite_state,x
    lda #40
    sta sprite_data_2+sprite_timer,x
    jmp je_anim
je_rise:
    lda #6                      // resurface somewhere walkable near the player
    sta en_tmp
je_try:
    jsr en_rnd
    and #7
    sec
    sbc #4
    clc
    adc sprite_data_2+sprite_global_xhi
    sta temp+1
    lda #0
    sta temp
    jsr en_rnd
    and #7
    sec
    sbc #4
    clc
    adc sprite_data_2+sprite_global_yhi
    sta temp2+1
    lda #0
    sta temp2
    jsr control_path_test
    beq je_place
    dec en_tmp
    bne je_try
    beq !+                      // nowhere walkable: stay put
je_place:
    lda temp+1
    sta sprite_data_2+sprite_global_xhi,x
    lda temp2+1
    sta sprite_data_2+sprite_global_yhi,x
    lda #0
    sta sprite_data_2+sprite_global_xlo,x
    sta sprite_data_2+sprite_global_ylo,x
!:  lda #0
    sta sprite_data_2+sprite_state,x
    jsr en_rnd
    and #63
    clc
    adc #90
    sta sprite_data_2+sprite_timer,x
je_anim:
    lda sprite_data_2+sprite_state,x
    beq !+
    lda #1
!:  jsr sprite_anim_to
    jmp control_coords

control_wiz:
    jsr en_common
    bcc !+
    rts
!:  lda #0
    jsr sprite_anim_to
    jsr control_coords
    lda has_sword
    bne wz_done
    ldy #0
    jsr en_dist
    lda en_ax
    cmp #16
    bcs wz_done
    lda en_ay
    cmp #18
    bcs wz_done
    jsr show_message            // "it's dangerous to go alone..."
    lda #1
    sta has_sword
    ldx control_index           // and off he goes
    ldy sprite_data_2+sprite_spawn,x
    lda #2
    sta spawn_state,y
    jsr sprite_free
wz_done:
    rts

control_prin:
    jsr en_common
    bcc !+
    rts
!:  ldy #0
    jsr en_dist
    lda en_ax
    cmp #14
    bcs !+
    lda en_ay
    cmp #16
    bcs !+
    jmp victory
!:  lda #0
    jsr sprite_anim_to
    jmp control_coords

// ---- the wizard's message ----------------------------------------------
// Stops the AGSP display, shows a plain text screen (ROM font, using the
// AG_SAFE screen and colour RAM) with the wizard and the sword, keeps the
// music going, waits for J or space, then restarts the display (ag_init
// redraws the whole map, restoring AG_SAFE and colour RAM).
.const MSG_SCREEN = AG_SAFE
.const MSG_D018 = ((MSG_SCREEN >> 6) & $f0) | (($1000 >> 10) & $0e)

.segment TABLES
.encoding "screencode_upper"
msg_line1: .text "IT'S DANGEROUS TO GO ALONE!"
msg_line2: .text "TAKE THIS."
msg_line3: .text "PRESS J OR SPACE"
.encoding "petscii_mixed"
.segment MAIN

show_message:
    sei
    lda #0
    sta $d01a                   // no AGSP raster interrupts
    sta $d015
    sta $d020
    sta $d021
    lda #$ff
    sta $d019
    ldx #0
!:  lda #$20                    // clear the screen, white text
    sta MSG_SCREEN,x
    sta MSG_SCREEN+$100,x
    sta MSG_SCREEN+$200,x
    sta MSG_SCREEN+$2e8,x
    lda #1
    sta $d800,x
    sta $d900,x
    sta $da00,x
    sta $dae8,x
    inx
    bne !-
    ldx #msg_line2-msg_line1-1
!:  lda msg_line1,x
    sta MSG_SCREEN+14*40+(40-(msg_line2-msg_line1))/2,x
    dex
    bpl !-
    ldx #msg_line3-msg_line2-1
!:  lda msg_line2,x
    sta MSG_SCREEN+16*40+(40-(msg_line3-msg_line2))/2,x
    dex
    bpl !-
    ldx #16-1
!:  lda msg_line3,x
    sta MSG_SCREEN+22*40+12,x
    lda #12
    sta $d800+22*40+12,x
    dex
    bpl !-
    lda #sp0+78                 // the wizard and the sword
    sta MSG_SCREEN+$3f8
    lda #sp0+41
    sta MSG_SCREEN+$3f9
    lda spritecolors+78
    sta $d027
    lda spritecolors+41
    sta $d028
    lda #160
    sta $d000
    lda #188
    sta $d002
    lda #110
    sta $d001
    sta $d003
    lda #0
    sta $d010
    lda #MSG_D018
    sta $d018
    lda #$c8
    sta $d016
    lda #$1b
    sta $d011
    lda #3
    sta $d015
    ldx #<victory_irq           // music only
    ldy #>victory_irq
    jsr setup_irq
!:  jsr msg_key                 // wait: released, pressed, released
    bne !-
!:  jsr msg_key
    beq !-
!:  jsr msg_key
    bne !-
    sei
    lda #0
    sta $d01a
    sta $d015
    jmp ag_init                 // redraw the map, restart the raster engine

// msg_key: Z = 0 if J or space is down
msg_key:
    jsr readkb
    lda keyboard+4
    and #4                      // J
    beq !+
    lda keyboard+7
    and #$10                    // space
    beq !+
    lda #0
    rts
!:  lda #1
    rts

// player_effects: border flash while hurt (main loop, once per frame)
player_effects:
    lda player_hurt
    beq !+
    dec player_hurt
    cmp #30
    bcc !+
    lda #2
    sta $d020
    rts
!:  lda #COLR_SCREEN
    sta $d020
    rts

// victory: stop the game, show the title picture again with the music
victory:
    sei
    lda #0
    sta $d01a
    sta $d015
    lda #$ff
    sta $d019
    jsr show_splash
    ldx #<victory_irq
    ldy #>victory_irq
    jsr setup_irq
!:  jmp !-
victory_irq:
    pha
    txa
    pha
    tya
    pha
    asl $d019
    jsr sidplay
    pla
    tay
    pla
    tax
    pla
    rti
