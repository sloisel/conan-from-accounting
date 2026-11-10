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
fr_tiles:    .fill 11, 0     // ag_draw_row: the row's tiles
fr_base:     .word 0         //   its copy of the unrolled code
fr_vec:      .word 0         //   entry of a run
.assert "fr_vec: jmp () must not straddle a page", (fr_vec & $ff) != $ff, true
fr_saved:    .byte 0         //   the byte the rts replaced
fr_end:      .byte 0         //   slot low byte after the run
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
ag_len:      .byte 0
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

// ag_draw_row: A = wy, X = wx of screen column 0, Y = column count (<= 40),
// ag_s = ring slot of screen column 0 (ag_s is left undefined).
//
// One pass from the tile data to the ring, ~22 cycles a char: the 44 chars
// that 11 tiles can give are unrolled code (fr_code, in CODE2), one copy per
// char row of a tile (no operands to patch), X = tile, Y = slot within its
// page, stores through ag_ps / ag_pk. A run is entered through a table of
// step addresses and stopped by turning the step after its end into an rts
// (put back afterwards). Runs end at page ends and before the sprite-pointer
// slots 1016..1023 (each through ag_put: its glyph copy); slots 977..1015 and
// 0..38 are then copied to the mirror screen AG_ALT.
ag_draw_row:
    sty ag_n
    sta ag_wy
    and #3
    tay
    lda fr_vlo,y                // the copy for this char row of the tiles
    sta fr_base
    lda fr_vhi,y
    sta fr_base+1
    tya
    clc
    adc #>tilechar
    sta ag_pc+1                 // (pointer slots: ag_pc = that char row)
    txa
    and #3
    sta ag_i                    // first char: within the first tile
    txa
    lsr
    lsr
    tay
    lda ag_wy
    jsr ag_map_row
    .for (var t = 0; t < 11; t++) {
    lda (ag_mp),y               // the 11 tiles
    sta fr_tiles + t
    .if (t < 10) iny
    }
fr_seg:
    lda ag_n
    bne !+
    rts
!:  ldx ag_s+1
    lda ag_scrhi,x
    sta ag_ps+1
    lda ag_colhi,x
    sta ag_pk+1
    lda #0
    sta ag_ps
    sta ag_pk
    cpx #3
    bne fr_pg
    lda ag_s                    // page 3: up to the pointer slots
    cmp #$f8
    bcc !+
    jmp fr_ptr
!:  lda #$f8
    sec
    sbc ag_s
    jmp fr_clamp
fr_pg:
    lda #0                      // up to the page end
    sec
    sbc ag_s
    beq fr_all
fr_clamp:
    cmp ag_n
    bcc !+
fr_all:
    lda ag_n
!:  sta ag_len
    jsr fr_run
    ldx ag_s+1                  // mirrored slots: AG_ALT too
    bne fr_m3
    ldy ag_s                    // page 0: slots ag_s .. min(end, 39) - 1
    cpy #39
    bcs fr_adv
    lda fr_end
    beq !+
    cmp #39
    bcc !++
!:  lda #39
!:  sta fr_m0e+1
fr_m0:
    lda AG_SCREEN,y
    sta AG_ALT,y
    iny
fr_m0e:
    cpy #0                      // (patched)
    bne fr_m0
    beq fr_adv
fr_m3:
    cpx #3
    bne fr_adv
    ldy ag_s                    // page 3: slots max(ag_s, 977) .. end - 1
    cpy #<977
    bcs !+
    ldy #<977
!:  cpy fr_end
    bcs fr_adv
    lda fr_end
    sta fr_m3e+1
fr_m3l:
    lda AG_SCREEN+$300,y
    sta AG_ALT+$300,y
    iny
fr_m3e:
    cpy #0                      // (patched)
    bne fr_m3l
fr_adv:
    lda ag_i
    clc
    adc ag_len
    sta ag_i
    lda ag_n
    sec
    sbc ag_len
    sta ag_n
    lda ag_len
    jsr ag_slot_add
    jmp fr_seg
fr_ptr:                         // sprite-pointer slots 1016..: no screen
    lda ag_s                    // byte (AG_ALT holds code AG_PTRCODE+n), the
    sec                         // colour, and the char's glyph copied to that
    sbc #$f8                    // code's glyph
    asl
    asl
    asl
    tax                         // X = (slot - 1016) * 8
fp_loop:
    lda ag_i
    and #3
    tay
    lda ag_subtab,y
    sta ag_pc
    lda ag_i
    lsr
    lsr
    tay
    lda fr_tiles,y
    tay                         // Y = tile
    lda tilecol,y
    sta ag_k
    lda (ag_pc),y               // the char
    sta temp
    lsr
    lsr
    lsr
    lsr
    lsr
    clc
    adc #>charsetaddr
    sta temp+1
    lda temp
    asl
    asl
    asl
    sta temp                    // temp = its glyph
    ldy ag_s
    lda ag_k
    sta $db00,y
    .for (var b = 0; b < 8; b++) {
    ldy #b
    lda (temp),y
    sta AG_PTRGLYPH + b,x
    }
    txa
    clc
    adc #8
    tax
    inc ag_i
    dec ag_n
    inc ag_s
    beq !+                      // past 1023: slot 0
    lda ag_n
    beq !++
    jmp fp_loop
!:  lda #0
    sta ag_s+1
!:  jmp fr_seg

// fr_run: chars ag_i .. ag_i + ag_len - 1 to slots ag_s.. (one page, plain)
fr_run:
    lda ag_s
    clc
    adc ag_len
    sta fr_end                  // (0: the page end)
    lda ag_i                    // the step after the run: rts
    clc
    adc ag_len
    tax
    lda fr_base
    clc
    adc fr_offlo,x
    sta ag_pkc
    lda fr_base+1
    adc fr_offhi,x
    sta ag_pkc+1
    ldy #0
    lda (ag_pkc),y
    sta fr_saved
    lda #$60                    // rts
    sta (ag_pkc),y
    ldx ag_i                    // the run's first step
    lda fr_base
    clc
    adc fr_offlo,x
    sta fr_vec
    lda fr_base+1
    adc fr_offhi,x
    sta fr_vec+1
    txa
    lsr
    lsr
    tax
    lda fr_tiles,x
    tax                         // X = its tile
    ldy ag_s
    jsr fr_go
    ldy #0
    lda fr_saved
    sta (ag_pkc),y
    rts
fr_go:
    jmp (fr_vec)

// ag_draw_col: A = wy of screen row 0, X = wx, ag_s = slot of row 0.
// Draws all AG_ROWS rows of that world column (ag_s is left undefined).
//
// Fast path, ~45 cycles a row: the tile's 4 char rows are 4 unrolled copies
// (operands patched for the column's char within the tile), entered at the
// first row's; X = tile, Y = slot within its page, stores through ag_ps /
// ag_pk. Only slots 977..1023 and 0..38 need more (mirror, pointer glyphs):
// dc_run counts the rows before the next such slot (they are at the start
// of page 0 and the end of page 3), and those rows go through ag_put.
// In CODE2 ($13e8..: RAM the VIC cannot use, after the title's colours).
.segment CODE2
dc_run:  .byte 0
dc_pg:   .byte 0
dc_x:    .byte 0
dc_vec:  .word 0
dc_entry: .word dcr[0].row, dcr[1].row, dcr[2].row, dcr[3].row
ag_draw_col:
    sta ag_wy
    txa
    and #3
    tay
    lda ag_subtab,y             // (wx & 3) * 64: the char within the tile
    .for (var k = 0; k < 4; k++) {
    sta dcr[k].chr+1
    sta dcr[k].col+1
    sta dcx[k].col+1
    }
    txa
    lsr
    lsr
    sta ag_tx
    lda ag_wy
    jsr ag_map_row
    lda ag_mp
    clc
    adc ag_tx
    sta dc_map+1
    lda ag_mp+1
    adc #0
    sta dc_map+2
    lda ag_wy                   // enter at the first row's copy
    and #3
    asl
    tay
    lda dc_entry,y
    sta dc_vec
    lda dc_entry+1,y
    sta dc_vec+1
    lda #AG_ROWS
    sta ag_n
    lda #0
    sta ag_ps
    sta ag_pk
    lda ag_s+1
    sta dc_pg
    ldy ag_s
    jsr dc_pages
    lda dc_map+1
    sta ag_mp
    lda dc_map+2
    sta ag_mp+1
    sty dc_x
    ldy #0
    lda (ag_mp),y
    tax                         // X = tile
    ldy dc_x
    jmp (dc_vec)

dc_tile:                        // next tile down
    lda dc_map+1
    clc
    adc #64
    sta dc_map+1
    bcc dc_map
    inc dc_map+2
dc_map:
    ldx $ffff
dcr: .for (var k = 0; k < 4; k++) {
row:
chr:
    lda tilechar + k * $100,x   // (low byte patched)
    dec dc_run
    bmi dcx[k].go
    sta (ag_ps),y
col:
    lda tilecol + k * $100,x
    sta (ag_pk),y
next:
    dec ag_n
    bne !+
    rts
!:  tya
    clc
    adc #40
    tay
    bcc !+
    jsr dc_page
!:
    .if (k == 3) {
    jmp dc_tile
    }
}
dcx: .for (var k = 0; k < 4; k++) {
go:                             // a special slot: ag_put (A = char)
    pha
col:
    lda tilecol + k * $100,x
    sta ag_k
    pla
    jsr dc_put
    jmp dcr[k].next
}

// dc_put: A = char, ag_k = colour: ag_put at slot (dc_pg, Y); keeps X, Y
dc_put:
    stx dc_x
    sty ag_s
    ldx dc_pg
    stx ag_s+1
    jsr ag_put
    ldx dc_x
    ldy ag_s
    lda dc_pg                   // page 0: the next rows are fine (Y + 40 >= 39);
    beq !+                      // page 3: special until the page ends
    lda #0
    sta dc_run
    rts
!:  lda #127
    sta dc_run
    rts

// dc_page: Y wrapped past the page end: the next page
dc_page:
    lda dc_pg
    clc
    adc #1
    and #3
    sta dc_pg
// dc_pages: pointers for page dc_pg; dc_run = plain rows from slot (dc_pg, Y)
dc_pages:
    lda dc_pg
    clc
    adc #>AG_SCREEN
    sta ag_ps+1
    lda dc_pg
    clc
    adc #>$d800
    sta ag_pk+1
    lda dc_pg
    beq dp_0
    cmp #3
    beq dp_3
    lda #127                    // pages 1, 2: all plain
    sta dc_run
    rts
dp_0:
    lda #0                      // page 0: slots 0..38 are mirrored
    cpy #39
    bcc !+
    lda #127
!:  sta dc_run
    rts
dp_3:
    lda #0                      // page 3: plain below 977 (low byte $d1)
    sta dc_run
    tya
!:  cmp #<977
    bcs !+
    inc dc_run
    adc #40                     // (C = 0)
    bcc !-
!:  rts

// fr_code: ag_draw_row's unrolled steps, one copy per char row r of a tile:
// step j (0..43) draws char j of the row's 11 tiles (tile j / 4, char j % 4),
// then step 44 returns. X = tile (loaded at each tile's first step), Y = slot.
frv: .for (var r = 0; r < 4; r++) {
start:
    frs: .for (var j = 0; j < 44; j++) {
step:
        .var k = mod(j, 4)
        .if (k == 0) {
        ldx fr_tiles + floor(j / 4)
        }
        lda tilechar + r * $100 + k * 64,x
        sta (ag_ps),y
        lda tilecol + r * $100 + k * 64,x
        sta (ag_pk),y
        iny
    }
fin:
    rts
}
fr_vlo:   .fill 4, <frv[i].start
fr_vhi:   .fill 4, >frv[i].start
.function fr_off(j) {                   // step j's offset in a copy
    .if (j == 44) .return frv[0].fin - frv[0].start
    .return frv[0].frs[j].step - frv[0].start
}
fr_offlo: .fill 45, <fr_off(i)
fr_offhi: .fill 45, >fr_off(i)
.assert "fr_code copies the same size", frv[3].start - frv[2].start, frv[1].start - frv[0].start
.assert "ag_draw_col's code below $2000 (sprites)", * <= $2000, true
.segment MAIN

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
    lda #SPAWN_GRACE       // new view: monsters may spawn in it for a moment
    sta spawn_grace
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
