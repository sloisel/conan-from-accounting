// myui.s: status strip (3 hearts, 3 keys) in the open top border, the
// player's health, hearts dropped by monsters, and the keys on the map.
//
// The strip uses hardware sprites 0..5 on lines 16..36, above the timed raster
// code (lines 37..81). The border is kept open (myagsp.s: RSEL trick around
// line 247), and:
//  - the bottom IRQ switches to the AG_SAFE screen at line 246; its sprite
//    pointers all name a blank block, so game sprites still drawing below the
//    window show nothing;
//  - ag_irq_ui (line 2) switches to screen $0000, whose pointers ($03f8..)
//    name the strip's pictures, and places sprites 0..5;
//  - the top IRQ (line 37) puts the game's first 8 sprites back (mymux.s).
// The pictures live in AG_ALT's unused middle ($0d00..), copied at ag_init.

// (constants UI_*, PLAYER_HP, HEART_LIFE: myagsp.s, which needs some first)
.const PLAYER_START_X = 10*8*32         // as in mygame.s main
.const PLAYER_START_Y = 245*8*32
.var key_colors = List().add(2, 5, 14)  // red, green, light blue
.var ui_x = List().add(32, 48, 64, 284, 298, 312)
.assert "status strip pictures clear of AG_ALT's mirrored slots",
        UI_BLK * 64 >= AG_ALT + 39 && (UI_DEAD_BLK + 1) * 64 <= AG_ALT + 977, true
.assert "blank sprite block = glyphs $f8..$ff (above the map's)", UI_BLANK_BLK * 64, charsetaddr + $7c0

// colour of a sprite by its pointer (exec_animations)
.function ptr_color(i) {
    .if (i >= sp0 && i < sp0 + spritecolor_list.size()) .return spritecolor_list.get(i - sp0)
    .if (i == UI_HEART_BLK) .return 2
    .if (i >= UI_KEY_BLK && i < UI_KEY_BLK + 3) .return key_colors.get(i - UI_KEY_BLK)
    .if (i == UI_DEAD_BLK) .return spritecolor_list.get(0)
    .return 0
}

.segment MAIN
ptr_colors: .fill 256, ptr_color(i)
ui_gfx:
    #import "uigfx.s"
ui_key_col: .fill 3, key_colors.get(i)

// animations of the items (myenemies.s T_HEART, T_KEY..)
.var heart_list = List().add(255, UI_HEART_BLK, 0)
.var keyr_list = List().add(255, UI_KEY_BLK, 0)
.var keyg_list = List().add(255, UI_KEY_BLK + 1, 0)
.var keyb_list = List().add(255, UI_KEY_BLK + 2, 0)
heart_anim: anim(heart_list)
heart_index: index(heart_list)
keyr_anim:  anim(keyr_list)
keyr_index: index(keyr_list)
keyg_anim:  anim(keyg_list)
keyg_index: index(keyg_list)
keyb_anim:  anim(keyb_list)
keyb_index: index(keyb_list)

.segment TABLES
player_hp:      .byte PLAYER_HP
has_key:        .fill 3, 0
ui_col:         .fill 6, UI_DIM          // colours of the strip's 6 sprites
player_dead:    .byte 0
player_dying:   .byte 0                  // frames of the death animation left
debug_no_death: .byte 0                  // tests: health stops at 1
.segment MAIN

// ui_init: ag_init: pictures, pointer screens, colours
ui_init:
    ldx #0
!:  lda ui_gfx,x                // 5 blocks
    sta UI_BLK * 64,x
    lda ui_gfx+160,x
    sta UI_BLK * 64 + 160,x
    inx
    cpx #160
    bne !-
    ldx #7
!:  lda #UI_BLANK_BLK           // AG_SAFE: game sprites going on below the
    sta AG_SAFE+$3f8,x          // window draw nothing
    lda ui_ptrs,x
    sta UI_SCREEN+$3f8,x
    dex
    bpl !-
    lda #0                      // block $ff: the blank sprite block, glyph $ff
    ldx #63                     // (the hidden badline's rows, in the open
!:  sta UI_BLANK_BLK * 64,x     // border) and the idle byte $3fff
    dex
    bpl !-
    jsr msg_render              // the wizard's message box
    // fall through
// ui_update: the strip's colours from player_hp and has_key
ui_update:
    ldx #2
uu_loop:
    lda #UI_DIM
    cpx player_hp
    bcs !+
    lda #2                      // a full heart: red
!:  sta ui_col,x
    lda #UI_DIM
    ldy has_key,x
    beq !+
    lda ui_key_col,x
!:  sta ui_col+3,x
    dex
    bpl uu_loop
    rts
ui_ptrs: .byte UI_HEART_BLK, UI_HEART_BLK, UI_HEART_BLK
         .byte UI_KEY_BLK, UI_KEY_BLK + 1, UI_KEY_BLK + 2, UI_BLANK_BLK, UI_BLANK_BLK

// ag_irq_ui: line 2: the status strip's sprites (the game's are all done)
ag_irq_ui:
    pha
    lda #$ff                    // multicolour (the message box's are hires)
    sta $d01c
    lda #UI_Y
    .for (var k = 0; k < 6; k++) { sta $d001 + 2 * k }
    .for (var k = 0; k < 6; k++) {
    lda #<ui_x.get(k)
    sta $d000 + 2 * k
    lda ui_col + k
    sta $d027 + k
    }
    lda #%111000                // keys: x >= 256
    sta $d010
    lda #%111111
    sta $d015
    lda #AG_D018_UI
    sta $d018
    lda #<ag_irq_pre
    sta $fffe
    lda #>ag_irq_pre
    sta $ffff
    lda #AG_LINE_PRE
    sta $d012
    asl $d019
    pla
    rti
.for (var k = 0; k < 6; k++) {
    .assert "status strip x high bits", (ui_x.get(k) >= 256) == (k >= 3), true
}

// ---- health ----------------------------------------------------------------
// player_damage: a monster touched the player (en_touch)
player_damage:
    lda player_hp
    beq !+
    dec player_hp
    bne !+
    lda debug_no_death
    beq pd_dead
    inc player_hp
!:  jmp ui_update
pd_dead:
    lda #1
    sta player_dead
    jmp ui_update

// player_respawn: out of hearts (after the death animation): back at the
// start, hearts full (keys and the sword are kept; the monsters stay where
// they are)
player_respawn:
    lda #0
    sta player_dead
    sta player_dying
    sta player_hurt
    ldx #1                      // standing, facing down
    lda player_index+7,x
    tay
    sta sprite_data_2+sprite_anim
    lda player_anim,y
    sta sprite_data_2+sprite_delay
    iny
    sty sprite_data_2+sprite_frame
    lda #PLAYER_HP
    sta player_hp
    lda #<PLAYER_START_X
    sta sprite_data_2+sprite_global_xlo
    lda #>PLAYER_START_X
    sta sprite_data_2+sprite_global_xhi
    lda #<PLAYER_START_Y
    sta sprite_data_2+sprite_global_ylo
    lda #>PLAYER_START_Y
    sta sprite_data_2+sprite_global_yhi
    jmp ui_update

// ---- items -----------------------------------------------------------------
// en_drop: X = a monster whose death animation is over: one time in three it
// leaves a heart where it died (it becomes that heart), else it is gone
en_drop:
    jsr en_rnd
    cmp #86
    bcc !+
    jmp sprite_free
!:  lda #T_HEART
    sta sprite_data_2+sprite_controller,x
    lda #0
    sta sprite_data_2+sprite_state,x
    sta sprite_data_2+sprite_flash,x
    sta sprite_data_2+sprite_dxlo,x
    sta sprite_data_2+sprite_dxhi,x
    sta sprite_data_2+sprite_dylo,x
    sta sprite_data_2+sprite_dyhi,x
    lda #HEART_LIFE
    sta sprite_data_2+sprite_timer,x
    lda #255                    // no spawn point's
    sta sprite_data_2+sprite_spawn,x
    lda #0
    jsr sprite_init
    jmp control_coords

// control_heart: a dropped heart: taken when touched (one heart back), gone
// after a while (blinking first) or when far away. Not a spawn point's.
control_heart:
    dec sprite_data_2+sprite_timer,x
    beq ch_gone
    lda sprite_data_2+sprite_global_xhi,x
    jsr en_relx
    cmp #64-28
    bcc ch_gone
    cmp #64+68
    bcs ch_gone
    lda sprite_data_2+sprite_global_yhi,x
    jsr en_rely
    cmp #64-20
    bcc ch_gone
    cmp #64+42
    bcs ch_gone
    ldy #0
    jsr en_dist
    jsr it_touching
    bcc ch_show
    lda player_hp
    cmp #PLAYER_HP
    bcs ch_gone
    inc player_hp
    jsr ui_update
    ldx control_index
ch_gone:
    jmp sprite_free
ch_show:
    lda sprite_data_2+sprite_timer,x
    cmp #50                     // the last 2 s: blinking
    bcs !+
    lda #8
    sta sprite_data_2+sprite_flash,x
!:  jmp en_finish

// control_key: a key on the map (T_KEY + 2 * colour): taken when touched
control_key:
    jsr en_common               // (friendly: despawn/freeze zones, distance)
    bcc !+
    rts
!:  jsr it_touching
    bcs !+
    jmp en_finish
!:  lda sprite_data_2+sprite_controller,x
    sec
    sbc #T_KEY
    lsr
    tay
    lda #1
    sta has_key,y
    ldy sprite_data_2+sprite_spawn,x        // taken for good
    lda #2
    sta spawn_state,y
    jsr ui_update
    ldx control_index
    jmp sprite_free

// it_touching: after en_dist (item X, player): C = 1 if the player touches it
it_touching:
    lda en_ax
    cmp #12
    bcs it_no
    lda en_ay
    cmp #14
    bcs it_no
    sec
    rts
it_no:
    clc
    rts

// ---- the message box (the wizard's words) -----------------------------------
// Two lines of 21 chars in 7 hires sprites side by side, and a blinking
// arrow (the 8th: J or space goes on), in the open border under the play
// window: the bottom IRQ places them (msg_sprites) while msg_on; their
// pointers are AG_SAFE's (the screen from line 246 on), set by show_message.
// The text is drawn into 7 spare blocks of AG_ALT's middle at ag_init, from
// the ROM font (rows 0..6 of each glyph, lines 10 rows apart).
// (MSG_Y, MSG_X, MSG_PARK_Y: myagsp.s)
.var msg_blk = List().add($31, $32, $33, $3a, $3b, $3c, $3d, $3e)
.var msg_lines = List().add("IT'S DANGEROUS TO GO", "ALONE! TAKE THIS.")
.const MSG_W = 21                       // chars a line (7 sprites)
.for (var i = 0; i < 8; i++) {
    .assert "message blocks in AG_ALT's middle, clear of the strip's and the clip's",
        msg_blk.get(i) * 64 >= AG_ALT + 39 && msg_blk.get(i) * 64 + 64 <= AG_ALT + 977
        && (msg_blk.get(i) < UI_BLK || msg_blk.get(i) > UI_BLK + 5), true
}
.segment TABLES
msg_on:     .byte 0
msg_blocks: .fill 8, msg_blk.get(i)
.encoding "screencode_upper"
msg_text:
.for (var l = 0; l < 2; l++) {
    .var t = msg_lines.get(l)
    .errorif t.size() > MSG_W, "message line too long: " + t
    .var p = floor((MSG_W - t.size()) / 2)
    .fill p, $20
    .text t
    .fill MSG_W - p - t.size(), $20
}
.encoding "petscii_mixed"
// char i of the text: where its rows go (block (i % MSG_W) / 3, byte
// i % 3, row 10 * line)
.function msg_dest(i) {
    .var c = mod(i, MSG_W)
    .return msg_blk.get(floor(c / 3)) * 64 + floor(i / MSG_W) * 30 + mod(c, 3)
}
msg_dlo: .fill 2 * MSG_W, <msg_dest(i)
msg_dhi: .fill 2 * MSG_W, >msg_dest(i)
// the arrow (8th block)
msg_arrow: .byte %11111110, %01111100, %00111000, %00010000
mr_i:    .byte 0

// msg_render: ag_init (interrupts off): the text into the 8 blocks
msg_render:
    ldx #62                     // the 8 blocks: empty (loader leftovers)
    lda #0
!:  .for (var i = 0; i < 8; i++) { sta msg_blk.get(i) * 64,x }
    dex
    bpl !-
    lda $01
    pha
    lda #$33                    // the character ROM at $d000
    sta $01
    ldx #0
mr_loop:
    stx mr_i
    lda msg_text,x              // its glyph: $d000 + 8 * code
    sta temp
    lda #0
    asl temp
    rol
    asl temp
    rol
    asl temp
    rol
    ora #$d0
    sta temp+1
    lda msg_dlo,x
    sta temp2
    lda msg_dhi,x
    sta temp2+1
    .for (var r = 0; r < 7; r++) {
    ldy #r
    lda (temp),y
    ldy #r * 3
    sta (temp2),y
    }
    ldx mr_i
    inx
    cpx #2 * MSG_W
    bne mr_loop
    pla
    sta $01
    .for (var r = 0; r < 4; r++) {  // the arrow: rows 12..15, at the left
    lda msg_arrow + r
    sta msg_blk.get(7) * 64 + (12 + r) * 3
    }
    rts

.var msg_msb = 0
.for (var k = 0; k < 8; k++) { .if (MSG_X + 24 * k >= 256) .eval msg_msb = msg_msb | (1 << k) }
// msg_sprites: bottom IRQ (line 248+), while msg_on: the box's sprites
msg_sprites:
    lda #MSG_Y
    .for (var k = 0; k < 8; k++) { sta $d001 + 2 * k }
    .for (var k = 0; k < 8; k++) {
    lda #<(MSG_X + 24 * k)
    sta $d000 + 2 * k
    }
    lda #msg_msb                // (x >= 256: the high bits)
    sta $d010
    lda #1                      // white
    .for (var k = 0; k < 8; k++) { sta $d027 + k }
    lda #0
    sta $d01c                   // hires
    sta $d017
    sta $d01d
    lda ag_vbl                  // the arrow blinks
    and #16
    beq !+
    lda #$80
!:  eor #$ff
    sta $d015
    rts
.segment MAIN
