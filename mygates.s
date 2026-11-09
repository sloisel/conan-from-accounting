// mygates.s: the locked gates and the rescue.
//
// Three gates bar the way (tools/map_extras.py draws them into the map,
// gates.s says where they are): the red door in the graveyard's fence, the
// green gate at the east end of the bridge, the blue gate of the princess's
// prison. Touching a gate with its key opens it for good: its tiles become
// grass in the map, its collision bits clear, and the rows of it on screen
// are redrawn (a frame's worth of CPU, once).
//
// Opening the prison starts the rescue: Conan steps aside (scripted keys),
// the princess walks out through the gate (control_prin), a pause, then the
// title picture (victory). Monsters keep still meanwhile (en_common).

#import "gates.s"

.const CUT_X = 4 * (PRIN_TX + 3)         // where Conan waits (chars): up and to
.const CUT_Y = 4 * (PRIN_TY - 1)         // the right of the gate
.const PRIN_OUT_X = 4 * (PRIN_TX + 2) + 2   // the princess stops outside it
.const CUT_DIR = 8                       // Conan then looks down-left, at her
.const CUT_STEP_MAX = 150                // frames: Conan's walk (in case he is stuck)
.const CUT_WALK_MAX = 250                //   the princess's walk (in case she is not there)
.const CUT_PAUSE = 100                   //   together, before the title picture

.segment MAIN
gate_open:  .fill GATE_N, 0
cut_phase:  .byte 0             // 0 playing, 1 Conan steps aside, 2 she walks out, 3 pause
cut_t:      .byte 0
gt_g:       .byte 0
gt_i:       .byte 0
gt_r:       .byte 0
gt_sr:      .byte 0

// gate_update: main loop, after control_player: open a gate the player
// touches with its key; run the rescue's clock
gate_update:
    lda cut_phase
    beq !+
    jmp cut_update
!:  ldx #GATE_N-1
gu_loop:
    lda gate_open,x
    bne gu_next
    lda has_key,x
    beq gu_next
    lda sprite_data_2+sprite_global_xhi     // the player's collision point
    cmp gate_bx0,x
    bcc gu_next
    cmp gate_bx1,x
    beq !+
    bcs gu_next
!:  lda sprite_data_2+sprite_global_yhi
    cmp gate_by0,x
    bcc gu_next
    cmp gate_by1,x
    beq !+
    bcs gu_next
!:  jmp gate_open_x
gu_next:
    dex
    bpl gu_loop
    rts

// gate_open_x: X = gate: open it for good (one per frame at most)
gate_open_x:
    lda #1
    sta gate_open,x
    stx gt_g
    ldy gate_t,x                // its tiles become grass
go_tile:
    tya
    cmp gate_t+1,x
    bcs go_path
    lda gate_tile_lo,y
    sta temp
    lda gate_tile_hi,y
    sta temp+1
    sty gt_i
    ldy #0
    lda #GATE_OPEN_TILE
    sta (temp),y
    ldy gt_i
    iny
    jmp go_tile
go_path:
    ldy gate_p,x                // and walkable
go_pl:
    tya
    cmp gate_p+1,x
    bcs go_draw
    lda gate_path_lo,y
    sta temp
    lda gate_path_hi,y
    sta temp+1
    lda gate_path_mask,y
    sty gt_i
    ldy #0
    and (temp),y
    sta (temp),y
    ldy gt_i
    iny
    jmp go_pl
go_draw:                        // redraw its 4 char rows where on screen
    lda #0
    sta gt_r
gd_loop:
    ldx gt_g
    lda gate_row,x
    clc
    adc gt_r
    sec
    sbc ag_cy                   // screen row (above the screen: wraps, >= AG_ROWS)
    cmp #AG_ROWS
    bcs gd_next
    sta gt_sr
    lda ag_cy
    ldx ag_cx
    jsr ag_ring_pos             // ag_s = slot of screen row 0, column 0
    ldx gt_sr
    beq !+
gd_add:
    lda #40
    jsr ag_slot_add
    dex
    bne gd_add
!:  ldx gt_g
    lda gate_row,x
    clc
    adc gt_r
    ldx ag_cx
    ldy #40
    jsr ag_draw_row
gd_next:
    inc gt_r
    lda gt_r
    cmp #4
    bne gd_loop
    lda gt_g
    cmp #2                      // the prison: the rescue begins
    bne !+
    lda #1
    sta cut_phase
    lda #0
    sta cut_t
!:  rts

// cut_update: the rescue's clock (phase 2 ends in control_prin)
cut_update:
    inc cut_t
    lda cut_phase
    cmp #2
    beq cu_walk
    bcs cu_pause
    lda cut_t                   // 1: Conan steps aside (cut_input)
    cmp #CUT_STEP_MAX
    bcs cu_next
    rts
cu_walk:
    lda cut_t
    cmp #CUT_WALK_MAX
    bcs cu_next
    rts
cu_pause:
    lda cut_t
    cmp #CUT_PAUSE
    bcs !+
    rts
!:  jmp victory
cu_next:
    inc cut_phase
    lda #0
    sta cut_t
    rts

// cut_input: after readkb: during the rescue the keys are scripted (the
// keyboard matrix is active low: W, A, S = row 1 bits 1, 2, 5; D = row 2
// bit 2; J = row 4 bit 2)
cut_input:
    lda cut_phase
    bne !+
    rts
!:  lda keyboard+1              // nothing pressed
    ora #$26
    sta keyboard+1
    lda keyboard+2
    ora #$04
    sta keyboard+2
    lda keyboard+4
    ora #$04
    sta keyboard+4
    lda cut_phase
    cmp #1
    beq ci_step
ci_face:
    lda #CUT_DIR                // standing, looking at her
    sta player_dir_nz
    rts
ci_step:
    ldy #0                      // keys still needed
    lda sprite_data_2+sprite_global_yhi
    cmp #CUT_Y+1
    bcc !+
    lda keyboard+1              // below: W
    and #$fd
    sta keyboard+1
    iny
!:  lda sprite_data_2+sprite_global_yhi
    cmp #CUT_Y-1
    bcs !+
    lda keyboard+1              // above: S
    and #$df
    sta keyboard+1
    iny
!:  lda sprite_data_2+sprite_global_xhi
    cmp #CUT_X
    bcs !+
    lda keyboard+2              // left of it: D
    and #$fb
    sta keyboard+2
    iny
!:  lda sprite_data_2+sprite_global_xhi
    cmp #CUT_X+2
    bcc !+
    lda keyboard+1              // right of it: A
    and #$fb
    sta keyboard+1
    iny
!:  tya
    bne !+
    lda #2                      // there: her turn
    sta cut_phase
    lda #0
    sta cut_t
    beq ci_face
!:  rts
