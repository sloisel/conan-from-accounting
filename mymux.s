// mymux.s: sprite multiplexer.
//
// Each frame the main loop builds a plan (mux_plan) from the logical sprites
// that are on screen (y != 0): sorted by y, each gets the hardware sprite
// that frees up first. The first 8 entries are written by the top IRQ
// (line 37) before the window; the others are rewrites during the frame, done by the
// IRQ dispatcher (myagsp.s ag_next) at line mx_line. A rewrite can only start
// once the hardware sprite's previous sprite has finished, must be done before
// the new sprite starts, and the dispatcher does one at a time and none while
// it busy-waits for a pointer-row switch. The plan models that timing:
//   - a rewrite starts no earlier than the line after the old sprite's last
//     line, and MX_COST lines after the previous rewrite started (one more
//     if MX_DMA_N other sprites are showing then: their DMA steals cycles);
//   - not in B-7..B for a pointer-row switch at badline B (moved to B+1):
//     the dispatcher busy-waits from B-4 to B there, and must not be late;
//   (the sprites come sorted by y, so the hardware sprites free up in the
//   order they were given out: entry k reuses entry k-8's)
//   - it needs MX_LEAD lines before the new sprite's y.
// A sprite that cannot be fitted is left out this frame (it flickers rather
// than showing garbage). Plans are double buffered: main builds the back
// buffer, the bottom IRQ swaps it in together with the rest of the frame.

.const MX_COST = 3                     // lines per rewrite (measured worst case 2.65:
.const MX_DMA_N = 4                    //  IRQ entry, a badline, DMA), plus one with
                                       //  this many others showing (worst 3.45)
.const MX_SWLEAD = 7                   // no rewrite may start in B-7..B: one
                                       //  starting before is done (<= 3.45 lines)
                                       //  when the switch's IRQ comes (B-4)
.const MX_LEAD = 3                     // lines from its start to the new y
.const MX_MAX = 16

.segment TABLES
mx_n:       .fill 2, 0                 // entries per buffer
mx_back:    .byte 0                    // buffer the main loop builds (0/1)
mx_front:   .byte 1                    // buffer the display uses
mx_i:       .byte 0                    // dispatcher: next entry to write
mx_end:     .byte 0
mx_slot:    .fill 2*MX_MAX, 0          // buffer b's entries at b*MX_MAX
mx_line:    .fill 2*MX_MAX, 0          // 0: before the frame, else IRQ line
mx_y:       .fill 2*MX_MAX, 0
mx_xlo:     .fill 2*MX_MAX, 0
mx_msb:     .fill 2*MX_MAX, 0          // its $d010 bit, or 0
mx_reg:     .fill 2*MX_MAX, 0          // 2 * hardware sprite
mx_d010:    .fill 2*MX_MAX, 0          // $d010 after writing this entry
mx_col:     .fill 2*MX_MAX, 0
mx_ptr:     .fill 2*MX_MAX, 0
mx_lidx:    .fill 2*MX_MAX, 0          // logical sprite (tests)
mx_idx:     .fill 32, 0                // logical sprites on screen, sorted by y
mx_cnt:     .byte 0
mx_slot_end: .fill 8, 0                // last line shown by each hardware sprite
mx_k:       .byte 0                    // entries accepted
mx_j:       .byte 0                    // position in the sorted list
mx_key:     .byte 0
mx_best:    .byte 0
mx_bestv:   .byte 0
mx_line_v:  .byte 0
mx_base:    .byte 0
mx_outer:   .byte 0
mx_dropped: .byte 0                    // sprites left out this frame (tests)
mx_busy:    .byte 0                    // model: dispatcher free from this line
mx_act:     .byte 0
mx_mask:    .byte 0
mx_sw1:     .byte 0                    // pointer-row switch badlines (0: none)
mx_sw2:     .byte 0
mx_tb:      .byte 0
mx_w1lo:    .byte 0                    // rewrites may not start in [lo, e):
mx_w1e:     .byte 0                    // a switch's busy-wait (B-7..B)
mx_w2lo:    .byte 0
mx_w2e:     .byte 0
mx_keyv:    .fill 32, 0                // sort key per logical sprite
mx_e:       .byte 0
mx_t:       .byte 0
mx_o:       .word 0

.segment MAIN

// mux_plan: build the back plan from the logical sprites (main loop)
mux_plan:
    jsr mx_swaplines
    ldx sprite2_count           // the sort order is kept from frame to frame
    cpx mx_cnt                  // (a permutation of 0..count-1, nearly sorted);
    beq mp_keys                 // a new count: start from 0..count-1
    stx mx_cnt
    dex
!:  txa
    sta mx_idx,x
    dex
    bpl !-
mp_keys:
    ldx sprite2_count           // sort key: y, or 255 when not shown
    dex
mp_key:
    lda #255
    ldy sprite_data_2+sprite_yhi,x
    bne !+
    ldy sprite_data_2+sprite_y,x
    beq !+                      // parked
    cpy #AG_BOT_LINE+1
    bcs !+                      // below the window
    tya
!:  sta mx_keyv,x
    dex
    bpl mp_key
    ldx #1                      // insertion sort by key (stable): mostly
mp_ins:                         // just checks that it is still in order
    cpx mx_cnt
    bcs mp_assign
    ldy mx_idx,x
    lda mx_keyv,y
    ldy mx_idx-1,x
    cmp mx_keyv,y
    bcc mp_move
    inx
    bne mp_ins
mp_move:                        // A = key of entry X, smaller than the one before
    sta mx_key
    stx mx_outer
    lda mx_idx,x
    sta mx_k
mp_shift:
    ldy mx_idx-1,x
    lda mx_keyv,y
    cmp mx_key
    bcc mp_place
    beq mp_place
    tya
    sta mx_idx,x
    dex
    bne mp_shift
mp_place:
    lda mx_k
    sta mx_idx,x
    ldx mx_outer
    inx
    bne mp_ins

// Sprites come in y order, so hardware sprites free up in the order they were
// given out: the one to reuse is always entry k mod 8's.
mp_assign:
    lda #0
    ldx #7
!:  sta mx_slot_end,x
    dex
    bpl !-
    sta mx_k
    sta mx_j
    sta mx_dropped
    sta mx_busy
    sta mx_mask
    lda mx_back
    asl
    asl
    asl
    asl
    sta mx_e                    // entry index in the plan buffers
mp_each:
    ldx mx_j
    cpx mx_cnt
    bcs mp_end
    ldy mx_idx,x                // logical sprite
    lda mx_keyv,y
    cmp #255
    bne !+
mp_end:
    jmp mp_done                 // the rest are not shown
!:  sta mx_key                  // its y
    lda mx_k
    and #7
    sta mx_best
    lda mx_k
    cmp #8
    bcs mp_reuse
    lda #0                      // the first 8: before the frame
    sta mx_line_v
    jmp mp_store
mp_drop:
    inc mx_dropped
    jmp mp_nextj
mp_reuse:
    ldx mx_best                 // start: the line after its last one,
    lda mx_slot_end,x           // when the dispatcher is free, clear of the
    cmp #250                    // pointer-row switches
    bcs mp_drop
    adc #1
    cmp mx_busy
    bcs !+
    lda mx_busy
!:  cmp mx_w1lo
    bcc !+
    cmp mx_w1e
    bcs !+
    lda mx_w1e
!:  cmp mx_w2lo
    bcc !+
    cmp mx_w2e
    bcs !+
    lda mx_w2e
!:  cmp mx_w1lo
    bcc !+
    cmp mx_w1e
    bcs !+
    lda mx_w1e
!:  sta mx_line_v
    clc
    adc #MX_LEAD                // and done before the new sprite's y
    bcs mp_drop
    cmp mx_key
    beq !+
    bcs mp_drop
!:  lda #7                      // other sprites showing meanwhile steal
    sta mx_act                  // cycles (DMA): with MX_DMA_N or more a
mp_dma:                         // rewrite takes a line longer. The next ones
    inx                         // to free up that already have are idle.
    txa
    and #7
    tax
    cpx mx_best
    beq mp_dmad
    lda mx_slot_end,x
    cmp mx_line_v
    bcs mp_dmad
    dec mx_act
    jmp mp_dma
mp_dmad:
    lda mx_act
    cmp #MX_DMA_N               // C = 1: one more line
    lda mx_line_v
    adc #MX_COST
    bcc !+
    lda #255
!:  sta mx_busy
mp_store:
    ldx mx_e
    lda mx_best
    sta mx_slot,x
    asl
    sta mx_reg,x
    lda mx_line_v
    sta mx_line,x
    lda mx_key
    sta mx_y,x
    lda sprite_data_2+sprite_xlo,y
    sta mx_xlo,x
    lda sprite_data_2+sprite_color,y
    sta mx_col,x
    lda sprite_data_2+sprite_pointer,y
    sta mx_ptr,x
    tya
    sta mx_lidx,x
    lda sprite_data_2+sprite_xhi,y  // (0 or 1 for a sprite on screen)
    ldy mx_best
    cmp #1
    lda #0
    bcc !+
    lda bitset,y
!:  sta mx_msb,x
    sta mx_t
    lda mx_mask                 // $d010 once this entry is written (the
    and bitclear,y              // dispatcher writes entries in order)
    ora mx_t
    sta mx_mask
    sta mx_d010,x
    lda mx_key                  // the hardware sprite is busy until y + 21
    clc
    adc #21
    bcc !+
    lda #255
!:  sta mx_slot_end,y
    inc mx_e
    inc mx_k
    lda mx_k
    cmp #MX_MAX
    bcs mp_done
mp_nextj:
    inc mx_j
    jmp mp_each
mp_done:
    ldx mx_back
    lda mx_k
    sta mx_n,x
    rts

// mx_commit: bottom IRQ, on commit: the back plan becomes the front one
mx_commit:
    lda mx_back
    sta mx_front
    eor #1
    sta mx_back
    rts

// mx_frame_setup: bottom IRQ, before interrupts may nest: where the
// dispatcher's entries (rewrites during the frame) start and end
mx_frame_setup:
    ldx mx_front
    lda mx_n,x
    sta mx_end                  // (temporarily the count)
    txa
    asl
    asl
    asl
    asl
    sta mx_base_f
    clc
    adc mx_end
    sta mx_end
    lda mx_n,x
    cmp #8
    bcc !+
    lda #8
!:  sta mx_init_n
    clc
    adc mx_base_f
    sta mx_i
    rts

// mx_apply_top: top IRQ (line 37, after the status strip): the hardware
// sprites for the top of the frame. Entry k of the first 8 is on hardware
// sprite k; unused ones are written too but stay disabled. ~290 cycles.
mx_apply_top:
    ldx mx_base_f
    .for (var k = 0; k < 8; k++) {
    lda mx_y+k,x
    sta $d001+2*k
    lda mx_xlo+k,x
    sta $d000+2*k
    lda mx_ptr+k,x
    sta AG_SCREEN+$3f8+k
    lda mx_col+k,x
    sta $d027+k
    }
    ldy mx_init_n
    lda #0
    cpy #0
    beq !+
    txa                         // $d010 after the first init_n entries
    clc
    adc mx_init_n
    tax
    lda mx_d010-1,x
!:  sta $d010
    lda sprite_enable_bits,y
    sta $d015
    rts

// mx_irq_0..7: the IRQ of a multiplexer rewrite, one copy per hardware
// sprite (an_irq_mux points the vector at the one for the entry's sprite):
// no register offsets to load, plain absolute stores, Y saved only after the
// writes. Y lands 16 cycles sooner than with MX_WRITE, the whole IRQ is ~15
// cycles shorter. Ends in ag_irq's common tail (ae_wdone). In TABLES: there
// is room there.
.var mx_irq_addr = List()
.segment TABLES
.for (var k = 0; k < 8; k++) {
    .eval mx_irq_addr.add(*)
    pha
    txa
    pha
    ldx mx_i
    lda mx_y,x
    sta $d001 + 2 * k
    lda mx_xlo,x
    sta $d000 + 2 * k
    lda mx_ptr,x
    sta AG_SCREEN + $3f8 + k
    lda mx_col,x
    sta $d027 + k
    lda mx_d010,x
    sta $d010
    tya
    pha
    jmp ae_wdone
}
mx_irq_lo: .fill 8, <mx_irq_addr.get(i)
mx_irq_hi: .fill 8, >mx_irq_addr.get(i)
.segment MAIN

// MX_WRITE: X = plan entry: rewrite its hardware sprite during the frame
// (y first: it has the earliest deadline). Clobbers A, Y. 52 cycles.
.macro MX_WRITE() {
    ldy mx_reg,x
    lda mx_y,x
    sta $d001,y
    lda mx_xlo,x
    sta $d000,y
    ldy mx_slot,x
    lda mx_ptr,x
    sta AG_SCREEN+$3f8,y
    lda mx_col,x
    sta $d027,y
    lda mx_d010,x
    sta $d010
}

// mx_swaplines: badlines of the rows >= 1 that fetch ring slots 1016 and 1023
// in the frame being planned (c_S, c_fine): as ag_prepare / ag_sw_row
mx_swaplines:
    lda #0
    sta mx_sw1
    sta mx_sw2
    lda #<1016
    sec
    sbc c_S
    sta mx_o
    lda #>1016
    sbc c_S+1
    and #3
    sta mx_o+1
    jsr ms_row
    sta mx_sw1
    lda mx_o
    clc
    adc #7
    sta mx_o
    lda mx_o+1
    adc #0
    and #3
    sta mx_o+1
    jsr ms_row
    sta mx_sw2
    ldx #0                      // their windows (none: lo 255, e 0)
    lda mx_sw1
    jsr ms_win
    ldx #2
    lda mx_sw2
ms_win:                         // A = B, X = 0/2
    beq !+
    sta mx_w1e,x
    inc mx_w1e,x
    sec
    sbc #MX_SWLEAD
    sta mx_w1lo,x
    rts
!:  sta mx_w1e,x
    lda #255
    sta mx_w1lo,x
    rts
ms_row:                         // A = badline of the row of offset mx_o, 0: none
    lda mx_o+1
    cmp #>880
    bcc !+
    bne ms_none
    lda mx_o
    cmp #<880
    bcs ms_none                 // below the 22 visible rows
!:  lda mx_o+1
    sta mx_tb
    lda mx_o
    lsr mx_tb
    ror
    lsr mx_tb
    ror
    lsr mx_tb
    ror
    tay
    lda ag_div5,y               // row
    beq ms_none                 // row 0: switched at the top, no event
    asl
    asl
    asl
    clc
    adc #AG_T_LINE
    sec
    sbc c_fine
    cmp #AG_BOT_LINE        // (as ag_sw_row: no switch for a row at 246)
    bcs ms_none
    rts
ms_none:
    lda #0
    rts

.segment TABLES
mx_base_f:  .byte 0                    // front buffer's first entry
mx_init_n:  .byte 0                    // entries written before the frame
