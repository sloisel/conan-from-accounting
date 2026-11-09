// mydraw.s: ring-buffer map renderer for the AGSP display (see myagsp.s).
//
// World char (wx, wy) always lives in ring slot (40*wy + wx) mod 1024 of the
// screen at AG_SCREEN and of colour RAM. For camera char position (cx, cy)
// the VIC shows rows 0..21 starting at slot S = (40*cy + cx) mod 1024, so a
// one-char scroll step only needs the newly exposed row or column drawn:
//
//   down/up: new bottom/top row, drawn before the step is shown (its slots
//            are off-screen in the current frame);
//   left:    new column 0, drawn before (its slots are column 39 now);
//   right:   new column 39, drawn after the step is shown (column 39 is
//            never visible in 38-column mode, but before the step those
//            slots are the visible column 0 of the next row).
//
// Ring slots 1016..1023 double as sprite pointers: in the mirror screen
// AG_ALT (which also mirrors slots 977..1015 and 0..38, every row that can
// contain them) slot n holds the fixed code AG_PTRCODE+n, whose glyph is set
// to the map char's glyph here. See myagsp.s.

.const AG_ROWS = 22

.segment TABLES
ag_rbc:      .fill 44, 0     // row build buffer: chars (11 tiles)
ag_rbk:      .fill 44, 0     //                   colours
ag_scrhi:    .byte >AG_SCREEN, (>AG_SCREEN)+1, (>AG_SCREEN)+2, (>AG_SCREEN)+3
ag_colhi:    .byte $d8, $d9, $da, $db
ag_subtab:   .byte 0, 64, 128, 192
ag_cx:       .byte 0         // camera char position currently in the ring
ag_cy:       .byte 0
ag_S:        .word 0         // its ring start slot
ag_after:    .byte 0         // right step: column 39 still to draw
ag_ncx:      .byte 0
ag_ncy:      .byte 0
ag_dx:       .byte 0
ag_dy:       .byte 0
ag_rowcnt:   .byte 0
ag_r:        .byte 0
ag_wy:       .byte 0
ag_tx:       .byte 0
ag_rboff:    .byte 0
ag_n:        .byte 0
ag_i:        .byte 0
ag_k:        .byte 0
ag_t:        .word 0
ag_tmp:      .byte 0
ag_cnt:      .byte 0

.segment MAIN
.assert "map must be page aligned", <map, 0
.assert "tilechar must be page aligned", <tilechar, 0
.assert "tilecol must be page aligned", <tilecol, 0
.assert "64 tiles per tile table row", numtiles, 64

// ag_ring_pos: ag_s = (40*A + X) & 1023   (A = wy, X = wx)
ag_ring_pos:
    stx ag_tmp
    sta ag_s
    lda #0
    sta ag_s+1
    asl ag_s
    rol ag_s+1
    asl ag_s
    rol ag_s+1
    asl ag_s
    rol ag_s+1          // 8*wy
    lda ag_s
    sta ag_t
    lda ag_s+1
    sta ag_t+1
    asl ag_s
    rol ag_s+1
    asl ag_s
    rol ag_s+1          // 32*wy
    lda ag_s
    clc
    adc ag_t
    sta ag_s
    lda ag_s+1
    adc ag_t+1
    sta ag_s+1          // 40*wy
    lda ag_s
    clc
    adc ag_tmp
    sta ag_s
    lda ag_s+1
    adc #0
    and #3
    sta ag_s+1
    rts

// ag_slot_add: ag_s = (ag_s + A) & 1023
ag_slot_add:
    clc
    adc ag_s
    sta ag_s
    lda ag_s+1
    adc #0
    and #3
    sta ag_s+1
    rts

// ag_map_row: ag_mp = map + (A >> 2) * 64   (A = wy)
ag_map_row:
    lsr
    lsr
    sta ag_mp+1
    lda #0
    lsr ag_mp+1
    ror
    lsr ag_mp+1
    ror
    sta ag_mp
    lda ag_mp+1
    clc
    adc #>map
    sta ag_mp+1
    rts

// ag_put: store char A, colour ag_k at ring slot ag_s
// (slots 977..1015 and 0..38 also go to the mirror AG_ALT; for 1016..1023,
// the sprite pointers, the char's glyph is copied to code AG_PTRCODE+n)
ag_put:
    ldy ag_s+1
    beq ap_low
    cpy #3
    bne ap_normal
    ldy ag_s
    cpy #$f8
    bcs ap_ptr
    cpy #<977
    bcc ap_normal
    sta AG_ALT+$300,y
    jmp ap_normal
ap_low:
    ldy ag_s
    cpy #39
    bcs ap_normal
    sta AG_ALT,y
ap_normal:
    pha
    ldy ag_s+1
    lda ag_scrhi,y
    sta ap_scr+2
    lda ag_colhi,y
    sta ap_col+2
    pla
    ldy ag_s
ap_scr:
    sta $0400,y
    lda ag_k
ap_col:
    sta $d800,y
    rts
ap_ptr:
    pha
    lda ag_k
    sta $db00,y
    tya
    sec
    sbc #$f8
    asl
    asl
    asl
    tax                     // glyph offset of code AG_PTRCODE+n
    pla
    pha
    asl
    asl
    asl
    sta ap_g+1              // glyph of char A: charset + 8*A
    pla
    lsr
    lsr
    lsr
    lsr
    lsr
    clc
    adc #>charsetaddr
    sta ap_g+2
    ldy #0
ap_g:
    lda $ffff,y
    sta AG_PTRGLYPH,x
    inx
    iny
    cpy #8
    bne ap_g
    rts

// ag_build_row: A = wy, X = wx. Fills ag_rbc/ag_rbk with the 11 tiles
// starting at tile column wx>>2; the first wanted char is at ag_rboff.
ag_build_row:
    sta ag_wy
    txa
    and #3
    sta ag_rboff
    txa
    lsr
    lsr
    sta ag_tx
    lda ag_wy
    jsr ag_map_row
    lda ag_wy
    and #3
    clc
    adc #>tilechar
    sta br_c0+2
    sta br_c1+2
    sta br_c2+2
    sta br_c3+2
    lda ag_wy
    and #3
    clc
    adc #>tilecol
    sta br_k0+2
    sta br_k1+2
    sta br_k2+2
    sta br_k3+2
    ldx #0
br_loop:
    ldy ag_tx
    lda (ag_mp),y
    tay
br_c0: lda $ff00,y
    sta ag_rbc,x
br_k0: lda $ff00,y
    sta ag_rbk,x
br_c1: lda $ff40,y
    sta ag_rbc+1,x
br_k1: lda $ff40,y
    sta ag_rbk+1,x
br_c2: lda $ff80,y
    sta ag_rbc+2,x
br_k2: lda $ff80,y
    sta ag_rbk+2,x
br_c3: lda $ffc0,y
    sta ag_rbc+3,x
br_k3: lda $ffc0,y
    sta ag_rbk+3,x
    inc ag_tx
    txa
    clc
    adc #4
    tax
    cpx #44
    bne br_loop
    rts

// ag_blit_row: copy X chars from the row buffer into the ring at ag_s
// (ag_s is clobbered on the slow path)
ag_blit_row:
    stx ag_n
    lda ag_s+1
    beq bl_p0
    cmp #3
    bcc bl_fast
    lda ag_s
    clc
    adc ag_n
    bcs bl_slow
    cmp #<977+1            // ends at or before slot 977?
    bcs bl_slow
    bcc bl_fast
bl_p0:
    lda ag_s
    cmp #39                // starts after the mirrored slots 0..38?
    bcc bl_slow
bl_fast:
    lda ag_s
    sta ag_ps
    sta ag_pk
    lda ag_s+1
    ora #>AG_SCREEN
    sta ag_ps+1
    lda ag_s+1
    ora #$d8
    sta ag_pk+1
    ldx ag_rboff
    ldy #0
bl_floop:
    lda ag_rbc,x
    sta (ag_ps),y
    lda ag_rbk,x
    sta (ag_pk),y
    inx
    iny
    cpy ag_n
    bne bl_floop
    rts
bl_slow:                   // wraps at 1024 or touches the mirrored slots
    lda ag_rboff
    sta ag_i
bl_sloop:
    ldx ag_i
    lda ag_rbk,x
    sta ag_k
    lda ag_rbc,x
    jsr ag_put
    lda #1
    jsr ag_slot_add
    inc ag_i
    dec ag_n
    bne bl_sloop
    rts

// ag_draw_row: A = wy, X = wx of screen column 0, Y = column count,
// ag_s = ring slot of screen column 0
ag_draw_row:
    sty ag_cnt
    jsr ag_build_row
    ldx ag_cnt
    jmp ag_blit_row

// ag_draw_col: A = wy of screen row 0, X = wx, ag_s = slot of row 0.
// Draws all AG_ROWS rows of that world column.
ag_draw_col:
    sta ag_wy
    txa
    and #3
    tay
    lda ag_subtab,y
    sta ag_pc
    sta ag_pkc
    txa
    lsr
    lsr
    sta ag_tx
    lda ag_wy
    jsr ag_map_row
    lda ag_mp
    clc
    adc ag_tx
    sta ag_mp
    bcc !+
    inc ag_mp+1
!:  lda ag_wy
    and #3
    clc
    adc #>tilechar
    sta ag_pc+1
    lda ag_wy
    and #3
    clc
    adc #>tilecol
    sta ag_pkc+1
    lda #AG_ROWS
    sta ag_n
dc_loop:
    ldy #0
    lda (ag_mp),y
    tay
    lda (ag_pkc),y
    sta ag_k
    lda (ag_pc),y
    jsr ag_put
    lda #40
    jsr ag_slot_add
    inc ag_wy
    lda ag_wy
    and #3
    bne dc_same
    lda ag_pc+1            // next tile row
    sec
    sbc #3
    sta ag_pc+1
    lda ag_pkc+1
    sec
    sbc #3
    sta ag_pkc+1
    lda ag_mp
    clc
    adc #64
    sta ag_mp
    bcc dc_next
    inc ag_mp+1
    jmp dc_next
dc_same:
    inc ag_pc+1
    inc ag_pkc+1
dc_next:
    dec ag_n
    bne dc_loop
    rts

// ag_redraw_all: draw the whole ring for camera (ag_cx, ag_cy)
ag_redraw_all:
    lda ag_cy
    ldx ag_cx
    jsr ag_ring_pos
    lda ag_s
    sta ag_S
    lda ag_s+1
    sta ag_S+1
    lda #0
    sta ag_r
ra_loop:
    lda ag_s
    pha
    lda ag_s+1
    pha
    lda ag_cy
    clc
    adc ag_r
    ldx ag_cx
    ldy #40
    jsr ag_draw_row
    pla
    sta ag_s+1
    pla
    sta ag_s
    lda #40
    jsr ag_slot_add
    inc ag_r
    lda ag_r
    cmp #AG_ROWS
    bne ra_loop
    rts

// scroll_update: follow the camera (smooth_x, smooth_y). Draws the edges
// that must exist before the new position is shown and prepares the
// parameters that ag_commit_frame hands to the raster IRQ.
scroll_update:
    lda smooth_x
    lsr
    lsr
    lsr
    lsr
    lsr
    eor #7                 // XSCROLL = 7 - fine x
    sta c_xs
    lda smooth_y
    lsr
    lsr
    lsr
    lsr
    lsr
    sta c_fine             // row 0 starts at line 81 - fine y
    lda smooth_x+1
    sta ag_ncx
    lda smooth_y+1
    sta ag_ncy
    sec
    sbc ag_cy
    sta ag_dy
    lda ag_ncx
    sec
    sbc ag_cx
    sta ag_dx
    ora ag_dy
    bne !+
    jmp su_done
!:  lda ag_dx
    clc
    adc #1
    cmp #3
    bcs su_far_j
    lda ag_dy
    clc
    adc #1
    cmp #3
    bcc !+
su_far_j:
    jmp su_far
!:
    lda ag_ncx
    sta ag_cx
    lda ag_ncy
    sta ag_cy
    ldx ag_cx
    jsr ag_ring_pos
    lda ag_s
    sta ag_S
    lda ag_s+1
    sta ag_S+1
    ldy #40                // rows skip column 39 on a right step
    lda ag_dx
    cmp #1
    bne !+
    ldy #39
!:  sty ag_rowcnt
    lda ag_dy
    beq su_cols
    bmi su_up
    lda ag_S               // down: new row 21 at S + 840
    clc
    adc #<840
    sta ag_s
    lda ag_S+1
    adc #>840
    and #3
    sta ag_s+1
    lda ag_cy
    clc
    adc #AG_ROWS-1
    ldx ag_cx
    ldy ag_rowcnt
    jsr ag_draw_row
    jmp su_cols
su_up:
    lda ag_S               // up: new row 0 at S
    sta ag_s
    lda ag_S+1
    sta ag_s+1
    lda ag_cy
    ldx ag_cx
    ldy ag_rowcnt
    jsr ag_draw_row
su_cols:
    lda ag_dx
    beq su_done
    bmi su_left
    lda #1                 // right: column 39 after the commit
    sta ag_after
    jmp su_done
su_left:
    lda ag_S               // left: new column 0 at S
    sta ag_s
    lda ag_S+1
    sta ag_s+1
    lda ag_cy
    ldx ag_cx
    jsr ag_draw_col
    jmp su_done
su_far:                    // jumped more than one char: redraw everything,
    lda #1                 // with the window blanked from the next frame on
    sta ag_blank
    lda ag_vbl
!:  cmp ag_vbl
    beq !-                 // the frame after this bottom IRQ is blank
    lda ag_ncx
    sta ag_cx
    lda ag_ncy
    sta ag_cy
    jsr ag_redraw_all      // (ag_blank is lifted by the IRQ with the commit)
su_done:
    lda ag_S
    sta c_S
    lda ag_S+1
    sta c_S+1
    lda ag_cx
    sta c_cx
    lda ag_cy
    sta c_cy
    rts

// ag_commit_frame: hand this frame's scroll position and sprites to the
// raster IRQ, wait until it has taken them, then draw the deferred column.
ag_commit_frame:
    lda #0
    sta ag_frame
    lda #1
    sta ag_commit
ag_idle:                   // spare CPU time is spent here (tools/profile.py)
    lda ag_frame
    beq ag_idle
    lda ag_after
    beq !+
    lda #0
    sta ag_after
    lda ag_S
    clc
    adc #39
    sta ag_s
    lda ag_S+1
    adc #0
    and #3
    sta ag_s+1
    lda ag_cx
    clc
    adc #39
    tax
    lda ag_cy
    jsr ag_draw_col
!:  rts
