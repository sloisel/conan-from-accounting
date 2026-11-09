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
        UI_BLK * 64 >= AG_ALT + 39 && (UI_BLK + 4) * 64 <= AG_ALT + 977, true
.assert "blank sprite block = glyphs $f8..$ff (above the map's)", UI_BLANK_BLK * 64, charsetaddr + $7c0

// colour of a sprite by its pointer (exec_animations)
.function ptr_color(i) {
    .if (i >= sp0 && i < sp0 + spritecolor_list.size()) .return spritecolor_list.get(i - sp0)
    .if (i == UI_HEART_BLK) .return 2
    .if (i >= UI_KEY_BLK && i < UI_KEY_BLK + 3) .return key_colors.get(i - UI_KEY_BLK)
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
debug_no_death: .byte 0                  // tests: health stops at 1
.segment MAIN

// ui_init: ag_init: pictures, pointer screens, colours
ui_init:
    ldx #0
!:  lda ui_gfx,x                // 4 blocks
    sta UI_BLK * 64,x
    lda ui_gfx+128,x
    sta UI_BLK * 64 + 128,x
    inx
    cpx #128
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

// player_respawn: out of hearts: back at the start, hearts full (keys and
// the sword are kept; the monsters stay where they are)
player_respawn:
    lda #0
    sta player_dead
    sta player_hurt
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
