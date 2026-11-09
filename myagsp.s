// myagsp.s: AGSP ("any given screen position") raster engine.
//
// The 1 KB screen at AG_SCREEN is a ring: the VIC's 10-bit video counter
// wraps at 1024, so it fetches screen and colour RAM at
// (S + 40*row + col) mod 1024. For a ring start S each frame does:
//   * k = S div 40 linecrunched lines (each adds 40 to VCBASE), lines 48..,
//   * m = S mod 40: a VSP (DMA delay) on line V = 80 - fine adds 40 - m,
//   * a forced badline on V+1 = 81 - fine starts the visible rows.
// Lines 47..80 are blanked with the invalid ECM+BMM mode; the visible window
// is lines 81..246 (RSEL=0, the bottom border starts at 247).
// Timing was calibrated cycle by cycle in VICE with proto/agsp.s and
// tools/agsp_check.py (all 1024 ring positions verified).
//
// VSP crash safety (best effort, untested on real hardware): the VSP bug is
// DRAM row-address metastability when VIC address bits 3-7 flip from the
// idle fetch ($3fff/$39ff) to a char fetch at the VSP moment. A hidden
// badline at line 247 fetches from AG_SAFE (all $ff codes), so the VIC line
// buffer holds $ff when the next VSP happens and the first display fetches
// ((code*8)|7 = $ff in the low byte) keep bits 3-7 unchanged.
//
// Sprite pointers live in ring slots 1016..1023. The screen at AG_SCREEN
// keeps the pointers there; AG_ALT mirrors the ring slots 977..1023 and
// 0..38 (every row that can contain those slots) but holds the *map chars*
// in 1016..1023. Only for the badline whose row fetches those slots, $d018
// points at AG_ALT: switched on line B-1 and switched back while the CPU is
// halted by that badline (write lands on cycle 56-58). Sprites on line B
// (and hardware sprite 0 on line B+1) read their pointer from AG_ALT, i.e.
// may show one wrong pixel row while crossing that row.
// Sprites must not be displayed on lines 40..81 (cycle-exact code there):
// control_coords parks sprites above AG_SPRITE_YMIN at y=0.

.const AG_SCREEN    = charbuf1        // $0400
.const AG_SAFE      = charbuf2        // $0800, 1 KB of $ff
.const AG_ALT       = $0c00           // pointer-row mirror (loader space, free after load)
.const AG_D018_MAIN = ((AG_SCREEN >> 6) & $f0) | ((charsetaddr >> 10) & $0e)
.const AG_D018_SAFE = ((AG_SAFE >> 6) & $f0) | ((charsetaddr >> 10) & $0e)
.const AG_D018_ALT  = ((AG_ALT >> 6) & $f0) | ((charsetaddr >> 10) & $0e)
.const AG_LINE_PRE  = 40
.const AG_FIRST_LINE = 47
.const AG_T_LINE    = 81              // first visible line
.const AG_BOT_LINE  = 246
.const AG_SPRITE_YMIN = 81            // sprite y register (first line y+1)
.const AG_SPRITE_DY = 68              // sprite y = (world - camera)/32 + this
.const AG_STAB_DELAY = 8
.const AG_PRE_DELAY = 20
.const AG_SLIDE_LEN = 48
.const AG_SLIDE_CAL = 9               // measured: VSP shift = write cycle - 13

.segment TABLES
// committed by the main loop (ag_commit_frame)
c_S:      .word 0
c_fine:   .byte 0
c_xs:     .byte 0
c_cx:     .byte 0     // camera char position (for debugging/tests)
c_cy:     .byte 0
ag_commit: .byte 0
ag_frame:  .byte 0
ag_blank:  .byte 0    // nonzero: keep the window black until the next commit
ag_vbl:    .byte 0    // incremented by every bottom IRQ
// in use for the coming frame
p_S:      .word 0
p_fine:   .byte 0
p_xs:     .byte 0
p_cx:     .byte 0
p_cy:     .byte 0
// prepared by ag_prepare for the top IRQ
n_k:      .byte 0
n_m:      .byte 0
n_V:      .byte 0
n_count:  .byte 0
n_vsp:    .byte 0
n_arm:    .byte 0
n_norm:   .byte 0
n_d016:   .byte 0
n_blank:  .byte 0     // the frame being prepared is blank
n_botd011: .byte 0    // bottom IRQ's $d011: YSCROLL 7, blank or not
n_d018top: .byte 0    // $d018 for row 0: AG_ALT if row 0 holds the pointer slots
n_d018aft: .byte 0    // $d018 right after unblanking (AG_ALT if row 1 needs it soon)
n_swB1:   .byte 0     // badlines of rows >= 1 holding the pointer slots, 0 = none
n_swB2:   .byte 0
ag_swidx: .byte 0
ag_irqline: .byte 0
ag_o:     .word 0
ag_B:     .byte 0
ag_q8:    .byte 0
ag_div5:  .fill 110, floor(i / 5)
.align $100
ytab:     .fill 64, 0

.segment MAIN

// ag_init: draw the ring for the current camera and start the raster IRQs.
ag_init:
    sei
    lda #$7f
    sta $dc0d
    sta $dd0d
    lda $dc0d
    lda $dd0d
    lda #<ag_nmi
    sta $fffa
    lda #>ag_nmi
    sta $fffb
    lda #0
    sta $d011               // blank while drawing
    sta $d015
    ldx #0
    lda #$ff
!:  sta AG_SAFE,x
    sta AG_SAFE+$100,x
    sta AG_SAFE+$200,x
    sta AG_SAFE+$300,x
    inx
    bne !-
    lda smooth_x+1
    sta ag_cx
    lda smooth_y+1
    sta ag_cy
    jsr ag_redraw_all
    jsr scroll_update
    lda c_S
    sta p_S
    lda c_S+1
    sta p_S+1
    lda c_fine
    sta p_fine
    lda c_xs
    sta p_xs
    jsr ag_prepare
    lda #AG_D018_MAIN
    sta $d018
    lda #<ag_irq_pre
    sta $fffe
    lda #>ag_irq_pre
    sta $ffff
    lda #AG_LINE_PRE
    sta $d012
    lda #$17
    sta $d011
    lda #1
    sta $d01a
    lda #$ff
    sta $d019
    cli
    rts
ag_nmi:
    rti

// ag_prepare: compute the raster program for p_S / p_fine / p_xs.
ag_prepare:
    lda p_S
    sta ag_o
    lda p_S+1
    and #3
    sta ag_o+1
    ldx #0
pr_div:
    lda ag_o
    sec
    sbc #40
    tay
    lda ag_o+1
    sbc #0
    bcc pr_divdone
    sta ag_o+1
    sty ag_o
    inx
    jmp pr_div
pr_divdone:
    stx n_k
    lda ag_o
    sta n_m
    lda #AG_T_LINE-1
    sec
    sbc p_fine
    sta n_V
    sec
    sbc #AG_FIRST_LINE
    sta n_count
    ldx #0
pr_y:
    cpx n_count
    beq pr_ydone
    cpx n_k
    bcs pr_fld
    txa                     // crunch next line: YSCROLL = (n+1)&7
    clc
    adc #AG_FIRST_LINE+1
    jmp pr_ystore
pr_fld:
    txa                     // no badline next line: YSCROLL = (n-1)&7
    clc
    adc #AG_FIRST_LINE-1
pr_ystore:
    and #7
    ora #$70                // ECM+BMM (blank), DEN, RSEL=0
    sta ytab,x
    inx
    jmp pr_y
pr_ydone:
    lda n_V                 // n_vsp: badline value at the VSP cycle; for
    ldx n_m                 // m = 0 the unchanged value (same timing)
    bne !+
    sec
    sbc #2
!:  and #7
    ora #$70
    sta n_vsp
    lda n_V
    clc
    adc #1
    and #7
    ora #$10
    sta n_norm
    ldx #$17
    stx n_botd011
    ldx ag_blank
    stx n_blank
    beq !+
    ldx #$77
    stx n_botd011
    ora #$60                // blank frame: stay in the invalid (black) mode
    sta n_norm
!:  ldx p_fine              // n_arm: written in the hblank of line V;
    beq !+                  // if row 0 starts on line 81 it also unblanks
    ora #$60
!:  sta n_arm
    lda p_xs
    and #7
    ora #vichposval
    sta n_d016
    lda n_m
    bne !+
    lda #1                  // m = 0: same slide timing as m = 1
!:  clc
    adc #<(ag_slide + AG_SLIDE_CAL)
    sta ag_slide_jmp+1
    lda #>(ag_slide + AG_SLIDE_CAL)
    adc #0
    sta ag_slide_jmp+2
    // which visible rows fetch ring slots 1016..1023?
    lda #AG_D018_MAIN
    sta n_d018top
    lda #0
    sta n_swB1
    sta n_swB2
    lda #<1016
    sec
    sbc p_S
    sta ag_o
    lda #>1016
    sbc p_S+1
    and #3
    sta ag_o+1              // visible offset of slot 1016
    jsr ag_sw_row
    lda ag_o
    clc
    adc #7
    sta ag_o
    lda ag_o+1
    adc #0
    and #3
    sta ag_o+1              // visible offset of slot 1023
    jsr ag_sw_row
    lda #AG_D018_MAIN       // a pointer row starting by line 83 is too close
    ldx n_swB1              // for the IRQ path: switch right after unblanking
    beq !+
    cpx #84
    bcs !+
    lda #AG_D018_ALT
!:  sta n_d018aft
    rts

// ag_sw_row: note the row showing visible offset ag_o (if visible)
ag_sw_row:
    lda ag_o+1
    cmp #>880
    bcc !+
    bne sw_none
    lda ag_o
    cmp #<880
    bcs sw_none
!:  lda ag_o+1
    sta ag_q8
    lda ag_o
    lsr ag_q8
    ror
    lsr ag_q8
    ror
    lsr ag_q8
    ror
    tay
    lda ag_div5,y           // row
    tax
    bne sw_later
    lda #AG_D018_ALT        // row 0: fetched from AG_ALT (set at line 46)
    sta n_d018top
    rts
sw_later:
    asl
    asl
    asl
    clc
    adc #AG_T_LINE
    sec
    sbc p_fine              // its badline B = 81 - fine + 8*row
    cmp #AG_BOT_LINE+1
    bcs sw_none             // starts below the window
    cmp n_swB1
    beq sw_none             // same row as the first slot
    ldx n_swB1
    bne !+
    sta n_swB1
    rts
!:  sta n_swB2
sw_none:
    rts

// ag_do_swap: A = badline B whose row holds the pointer slots
ag_do_swap:
    sta ag_B
    sec
    sbc #1
!:  cmp $d012
    beq !+
    bcs !-                  // wait for line B-1
!:  nop
    nop
    nop
    nop                     // past line B-1's sprite pointer fetches
    lda #AG_D018_ALT
    sta $d018               // row B fetches the mirror (map chars in the slots)
    lda ag_B
    cmp #AG_BOT_LINE-1
    bcs ds_done             // B >= 245: the bottom IRQ switches away after it
    ldx #AG_D018_MAIN
!:  cmp $d012
    beq !+
    bcs !-                  // wait for line B
!:  nop
    nop
    nop
    stx $d018               // halted by the badline: lands on cycle 56..58
ds_done:
    rts

// ag_next: schedule the next pointer-row switch (doing it right away when
// it is too close for an IRQ), else the bottom IRQ.
ag_next:
    ldx ag_swidx
    cpx #2
    bcs an_bot
    lda n_swB1,x
    beq an_bot
    sec
    sbc #2
    sta ag_irqline
    lda $d012
    clc
    adc #2
    cmp ag_irqline
    bcc an_irq
    ldx ag_swidx
    lda n_swB1,x
    jsr ag_do_swap
    inc ag_swidx
    jmp ag_next
an_irq:
    lda ag_irqline
    sta $d012
    lda #<ag_irq_swap
    sta $fffe
    lda #>ag_irq_swap
    sta $ffff
    rts
an_bot:
    jmp ag_set_bottom

ag_set_bottom:
    lda #<ag_irq_bot
    sta $fffe
    lda #>ag_irq_bot
    sta $ffff
    lda #AG_BOT_LINE
    sta $d012
    rts

// ---- pointer-row IRQ (line B-2) -------------------------------------
ag_irq_swap:
    pha
    txa
    pha
    tya
    pha
    asl $d019               // ack first: the next IRQ may be close
    ldx ag_swidx
    lda n_swB1,x
    jsr ag_do_swap
    lda ag_B
    cmp #AG_BOT_LINE-1
    bcs sw_chain            // B >= 245: too close to set the bottom IRQ
    inc ag_swidx
    jsr ag_next
    pla
    tay
    pla
    tax
    pla
    rti

sw_chain:                   // do the bottom IRQ's work from here
!:  lda $d012
    cmp #AG_BOT_LINE
    bcc !-
    lda n_botd011
    sta $d011
    lda #AG_D018_SAFE
    sta $d018
    jmp ag_bot_body

// ---- bottom IRQ: hidden safe badline, commit, sprites, music ------------
ag_irq_bot:
    pha
    lda n_botd011           // YSCROLL=7: line 247 is a badline (hidden);
    sta $d011               // must land before 247:12 even if 246 is a badline
    lda #AG_D018_SAFE
    sta $d018
    txa
    pha
    tya
    pha
ag_bot_body:
    lda ag_commit
    beq !+
    lda c_S
    sta p_S
    lda c_S+1
    sta p_S+1
    lda c_fine
    sta p_fine
    lda c_xs
    sta p_xs
    lda c_cx
    sta p_cx
    lda c_cy
    sta p_cy
    jsr copy_sprites
    lda #0
    sta ag_blank            // a commit carries a consistent ring: unblank
    sta ag_commit
    lda #1
    sta ag_frame
!:  jsr ag_prepare
    inc ag_vbl
    lda #0
    sta sprite_logical_iterator
    sta sprite_hw_iterator
ab_loop:
    lda sprite1_count
    cmp sprite_logical_iterator
    beq ab_done
    jsr do_sprite
    jmp ab_loop
ab_done:
    ldx sprite1_count
    lda sprite_enable_bits,x
    sta $d015
    jsr sidplay
    lda #<ag_irq_pre
    sta $fffe
    lda #>ag_irq_pre
    sta $ffff
    lda #AG_LINE_PRE
    sta $d012
    asl $d019
    pla
    tay
    pla
    tax
    pla
    rti

// ---- top IRQ (line 40): set up a stable raster at line 45 -------------
ag_irq_pre:
    pha
    txa
    pha
    tya
    pha
    lda #<ag_irq_top2
    sta $fffe
    lda #>ag_irq_top2
    sta $ffff
    lda #45
    sta $d012
    asl $d019
    lda #44
!:  cmp $d012
    bne !-
    tsx
    cli
    jmp ag_sled

// Timed code: one page, so no branch or index ever crosses a page.
.align $100
ag_sled:
    .fill 40, $ea
ag_irq_top2:
    txs
    ldx #AG_STAB_DELAY
!:  dex
    bne !-
    bit $00
    lda $d012
    cmp $d012
    beq !+
!:
ag_stable:                  // line 46, cycle 3, every frame
    lda n_d018top
    sta $d018
    lda n_d016
    sta $d016
    .fill AG_PRE_DELAY, $ea
    ldx #0
ag_lineloop:
    lda ytab,x              // 4
ag_wr_line:
    sta $d011               // 4: write at cycle 5 of line 47+x
    inx                     // 2
    ldy #8                  // 2
!:  dey
    bne !-                  // 39
    bit $ea                 // 3
    nop                     // 2
    cpx n_count             // 4
    bne ag_lineloop         // 3: 63 per line
    ldx n_norm              // line V (preloaded: keeps the unblank write early)
    ldy n_vsp
ag_slide_jmp:
    jmp ag_slide            // entry set by ag_prepare = VSP cycle
ag_slide:
    .fill AG_SLIDE_LEN, $c9
    .byte $c5, $ea
ag_wr_vsp:
    sty $d011               // DMA delay: badline condition mid-line
    lda n_arm               // (CPU stalls here until cycle 55 after a VSP)
ag_wr_arm:
    sta $d011               // hblank of line V: line V+1 is the first badline
    ldy #AG_T_LINE
    lda n_d018aft
!:  cpy $d012
    bne !-
ag_wr_norm:
    stx $d011               // leave the blanking mode: window starts
    sta $d018               // after row 0's fetch (halted till cycle 55 if
                            // line 81 is that badline: lands on cycle 58)
    asl $d019               // ack before scheduling the next IRQ
    lda #0
    sta ag_swidx
    jsr ag_next
ti_out:
    pla
    tay
    pla
    tax
    pla
    rti
.assert "AGSP timed code fits in one page", >ag_sled, >ti_out
