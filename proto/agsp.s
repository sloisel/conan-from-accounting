// AGSP prototype ("any given screen position") via linecrunch + VSP.
//
// The 1 KB video matrix is used as a ring: VC is a 10-bit counter, so the
// VIC fetches screen (and colour RAM) at (S + 40*row + col) mod 1024.
// Each frame we pick S:
//   k = S div 40 crunched lines (each adds 40 to VCBASE)
//   m = S mod 40: a VSP (DMA delay) on line V adds 40-m to VCBASE and a
//       forced badline on V+1 starts the visible screen there.
//   (m = 0: no VSP at all, the badline on V+1 just starts the screen.)
// Vertical fine scroll: V = 80 - fine, so row 0 starts at line 81 - fine.
// Lines 47..80 are blanked with the invalid ECM+BMM mode; the visible window
// is lines 81..246 (RSEL=0 bottom border at 247).
//
// Test pattern: slot i holds char code (i & 255) with colour 1 + (i >> 8);
// glyph c has row 0 = $ff (shows the colour) and rows 1-7 = c (bit pattern),
// so a screenshot can be decoded back to slot numbers by tools/agsp_check.py.

.const SCREEN   = $0400
.const SAFE     = $0800       // 1 KB of $ff codes, fetched by the hidden badline
.const CHARSET  = $3800
.const D018_MAIN = ((SCREEN >> 6) & $f0) | ((CHARSET >> 10) & $0e)
.const D018_SAFE = ((SAFE >> 6) & $f0) | ((CHARSET >> 10) & $0e)

.const IRQ_TOP_LINE = 44
.const FIRST_LINE   = 47      // ytab[0] is written on this line
.const T_LINE       = 81      // first visible line
.const BOT_LINE     = 246

// timing knobs (calibrated with tools/agsp_check.py)
.const STAB_DELAY  = 8        // double-IRQ stabiliser loop count
.const PRE_DELAY   = 21       // NOPs before the first ytab write (-> write at cycle 5)
.const SLIDE_LEN   = 44
.const SLIDE_CAL   = 1        // measured: VSP shift = write cycle - 13

.const zp_ptr = $fb

BasicUpstart2(start)

* = $4000 "code"
start:
    sei
    lda #$35
    sta $01
    lda #$7f
    sta $dc0d
    sta $dd0d
    lda $dc0d
    lda $dd0d
    lda #<nmi
    sta $fffa
    lda #>nmi
    sta $fffb
    lda $dd00
    ora #3
    sta $dd00
    jsr gen_charset
    jsr fill_screen
    lda #0
    sta $d020
    sta $d021
    sta $d015
    lda #D018_MAIN
    sta $d018
    lda #$c0
    sta $d016
    lda #$17
    sta $d011
    jsr prepare
    lda #<irq_top
    sta $fffe
    lda #>irq_top
    sta $ffff
    lda #IRQ_TOP_LINE
    sta $d012
    lda #1
    sta $d01a
    lda #$ff
    sta $d019
    cli
mainloop:
    jmp mainloop
nmi:
    rti

gen_charset:
    lda #<CHARSET
    sta zp_ptr
    lda #>CHARSET
    sta zp_ptr+1
    ldx #0
gc_char:
    ldy #0
    lda #$ff
    sta (zp_ptr),y
    txa
gc_row:
    iny
    sta (zp_ptr),y
    cpy #7
    bne gc_row
    lda zp_ptr
    clc
    adc #8
    sta zp_ptr
    bcc !+
    inc zp_ptr+1
!:  inx
    bne gc_char
    rts

fill_screen:
    ldx #0
fs_loop:
    txa
    sta SCREEN,x
    sta SCREEN+$100,x
    sta SCREEN+$200,x
    sta SCREEN+$300,x
    lda #1
    sta $d800,x
    lda #2
    sta $d900,x
    lda #3
    sta $da00,x
    lda #4
    sta $db00,x
    lda #$ff
    sta SAFE,x
    sta SAFE+$100,x
    sta SAFE+$200,x
    sta SAFE+$300,x
    inx
    bne fs_loop
    rts

// ---- per-frame parameters (poked by the test harness) ---------------------
p_S:    .word 0       // ring start offset 0..1023
p_fine: .byte 0       // vertical fine scroll 0..7
p_xs:   .byte 0       // horizontal fine scroll 0..7

// ---- values prepared for the next top IRQ ---------------------------------
n_k:       .byte 0
n_m:       .byte 0
n_V:       .byte 0
n_count:   .byte 0
n_vsp:     .byte 0
n_arm:     .byte 0
n_norm:    .byte 0
n_d016:    .byte 0
tmp:       .word 0

// prepare: compute next frame's raster program from p_S/p_fine/p_xs.
prepare:
    lda p_S
    sta tmp
    lda p_S+1
    and #3
    sta tmp+1
    ldx #0
pr_div:
    lda tmp
    sec
    sbc #40
    tay
    lda tmp+1
    sbc #0
    bcc pr_divdone
    sta tmp+1
    sty tmp
    inx
    jmp pr_div
pr_divdone:
    stx n_k
    lda tmp
    sta n_m
    lda #80
    sec
    sbc p_fine
    sta n_V
    sec
    sbc #FIRST_LINE
    sta n_count
    ldx #0
pr_y:
    cpx n_count
    beq pr_ydone
    cpx n_k
    bcs pr_fld
    txa             // crunch next line: YSCROLL = (n+1)&7, n = 47+x
    clc
    adc #FIRST_LINE+1
    jmp pr_ystore
pr_fld:
    txa             // no badline next line: YSCROLL = (n-1)&7
    clc
    adc #FIRST_LINE-1
pr_ystore:
    and #7
    ora #$70        // ECM+BMM (invalid mode = black), DEN, RSEL=0
    sta ytab,x
    inx
    jmp pr_y
pr_ydone:
    // n_vsp: written at the VSP cycle on line V. For m = 0 it repeats the
    // value already in $d011 (no badline), so both paths have equal timing.
    lda n_V
    ldx n_m
    bne !+
    sec
    sbc #2
!:  and #7
    ora #$70
    sta n_vsp
    // n_arm: makes line V+1 the first visible badline. Written in the
    // hblank at the end of line V; if the window starts right there
    // (fine = 0) it also leaves the blanking mode.
    lda n_V
    clc
    adc #1
    and #7
    pha
    ora #$10
    sta n_norm
    ldx p_fine
    beq !+
    ora #$60
!:  sta n_arm
    pla
    lda p_xs
    and #7
    ora #$c0
    sta n_d016
    lda n_m
    bne !+
    lda #1           // m = 0: same slide timing as m = 1
!:  clc
    adc #<(slide + SLIDE_CAL)
    sta slide_jmp+1
    lda #>(slide + SLIDE_CAL)
    adc #0
    sta slide_jmp+2
    rts

// ---- bottom IRQ: hidden "safe" badline + prepare next frame ---------------
irq_bot:
    pha
    txa
    pha
    tya
    pha
    lda #D018_SAFE
    sta $d018
    lda #$17         // YSCROLL=7 -> line 247 is a badline under the border
    sta $d011
    jsr prepare
    lda #<irq_top
    sta $fffe
    lda #>irq_top
    sta $ffff
    lda #IRQ_TOP_LINE
    sta $d012
    asl $d019
    pla
    tay
    pla
    tax
    pla
    rti

// ---- timed code: keep within one page so branches never cross ------------
.align $100
irq_top:
    pha
    txa
    pha
    tya
    pha
    lda #<irq_top2
    sta $fffe
    lda #>irq_top2
    sta $ffff
    inc $d012
    asl $d019
    tsx
    cli
    .fill 30, $ea
irq_top2:
    txs
    ldx #STAB_DELAY
!:  dex
    bne !-
    bit $00
    lda $d012
    cmp $d012
    beq !+
!:
stable:
    lda #D018_MAIN
    sta $d018
    lda n_d016
    sta $d016
    .fill PRE_DELAY, $ea
    ldx #0
lineloop:
    lda ytab,x       // 4
wr_line:
    sta $d011        // 4  (write on its last cycle)
    inx              // 2
    ldy #8           // 2
!:  dey
    bne !-           // 39
    bit $ea          // 3
    nop              // 2
    cpx n_count      // 4
    bne lineloop     // 3   -> 63 per line
    ldy n_vsp        // line V
slide_jmp:
    jmp slide        // entry set by prepare: cycle of the VSP write
slide:
    .fill SLIDE_LEN, $c9
    .byte $c5, $ea
wr_vsp:
    sty $d011        // DMA delay: badline condition mid-line
arm:
    lda n_arm        // (CPU stalls here until cycle 55 after a VSP)
wr_arm:
    sta $d011        // hblank of line V: line V+1 becomes the first badline
    ldx n_norm
    lda #T_LINE
!:  cmp $d012
    bne !-
wr_norm:
    stx $d011        // leave invalid mode: visible window starts
    lda #<irq_bot
    sta $fffe
    lda #>irq_bot
    sta $ffff
    lda #BOT_LINE
    sta $d012
    asl $d019
    pla
    tay
    pla
    tax
    pla
    rti

.align $100
ytab: .fill 64, 0
