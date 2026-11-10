// mycredits.s: the end: the title picture with credits scrolling up over it.
//
// The game is over, so all of $4000-$7fff (pathing, tiles, most of the code)
// is free: the picture moves to VIC bank 1 (bitmap $6000, screen $5c00) and
// the credits are hires sprites in front of it. 8 sprites side by side make a
// band of 24 characters, two text lines (role, name) per band; the bands are
// multiplexed down the screen (a raster IRQ before each re-places all 8
// sprites), 10 band slots of sprite data ($4000-$53ff) are reused as the text
// scrolls, one text line rendered per frame from a bold copy of the ROM
// font (from its RAM copy at MSG_FONT). The music plays from a raster IRQ
// throughout, also while the picture is copied (the screen blank then). First the picture is shown as it is for a moment, then it fades two
// steps darker (colours only: screen and colour RAM, the background) so the
// white text reads well over it.
// This code and its data live above $8000 (segment CREDITS, the text in
// TABLES), out of the way; it never returns.

.const CR_SCREEN = $5c00
.const CR_BITMAP = $6000
.const CR_FONT   = $5400                 // 64 glyphs (screen codes 0..63)
.const CR_D018   = ((CR_SCREEN & $3c00) >> 6) | ((CR_BITMAP & $2000) >> 10)
.const CR_SLOTS  = 10                    // band slots of 8 sprite blocks
.const CR_STEP   = 28                    // lines from band to band
.const CR_LINE_B = 10                    // name line: sprite rows 10..17
.const CR_YMIN   = 30                    // a band above this is gone (border)
.const CR_YMAX   = 250                   // a band below this is not shown yet
.const CR_START  = 255                   // band 0 starts here (below the screen)
.const CR_IRQ_TOP = 10
.const CR_IRQ_BOT = 254
.const CR_X      = 88                    // 192 px of text, centred
.const CR_COLOUR = 1                     // white, over the darkened picture
.const CR_HOLD   = 150                   // frames of the picture as it is
.const CR_FADE_STEPS = 2                 // then this many steps darker,
.const CR_FADE_GAP = 10                  //   frames between steps (each 8 frames)
.assert "band slots below the font", CR_SLOTS * 8 * 64 <= CR_FONT - $4000, true

// ---- the credits (24 characters a line; role, name) -------------------------
.var cr_list = List().add(
    "CONAN FROM ACCOUNTING", "",
    "GAME DESIGN", "S. LOISEL",
    "DIRECTOR", "S. LOISEL",
    "PRODUCER", "S. LOISEL",
    "LEAD PROGRAMMER", "S. LOISEL",
    "ENGINE PROGRAMMER", "S. LOISEL",
    "GAMEPLAY PROGRAMMER", "S. LOISEL",
    "ART DIRECTOR", "S. LOISEL",
    "PIXEL ARTIST", "S. LOISEL",
    "ANIMATOR", "S. LOISEL",
    "LEVEL DESIGNER", "S. LOISEL",
    "WRITER", "S. LOISEL",
    "SOUND DESIGN", "S. LOISEL",
    "MUSIC: 'DEGALVANIZED'", "BY OLE MARIUS PETTERSEN",
    "(C) 2011 OFFENCE", "",
    "QUALITY ASSURANCE", "S. LOISEL",
    "LOCALIZATION", "S. LOISEL",
    "MARKETING", "S. LOISEL",
    "COMMUNITY MANAGER", "S. LOISEL",
    "CATERING", "S. LOISEL",
    "ACCOUNTING", "S. LOISEL",
    "SPECIAL THANKS", "S. LOISEL",
    "", "",
    "THANK YOU FOR PLAYING!", "")
.const CR_BANDS = cr_list.size() / 2
.assert "credits: whole bands", cr_list.size() & 1, 0

// each different line once (length, screen codes), centred when rendered
.var cr_seen = Hashtable()
.var cr_uniq = List()
.var cr_off = List()
.var cr_n = 0
.for (var i = 0; i < cr_list.size(); i++) {
    .var t = cr_list.get(i)
    .errorif t.size() > 24, "credits line too long: " + t
    .if (!cr_seen.containsKey(t)) {
        .eval cr_seen.put(t, cr_n)
        .eval cr_uniq.add(t)
        .eval cr_n = cr_n + 1 + t.size()
    }
    .eval cr_off.add(cr_seen.get(t))
}
.segment TABLES
.encoding "screencode_upper"
cr_text:
.for (var i = 0; i < cr_uniq.size(); i++) {
    .byte cr_uniq.get(i).size()
    .text cr_uniq.get(i)
}
.encoding "petscii_mixed"
.segment CREDITS

cr_tlo:   .fill CR_BANDS * 2, <(cr_text + cr_off.get(i))    // per text line
cr_thi:   .fill CR_BANDS * 2, >(cr_text + cr_off.get(i))
cr_slot:  .fill CR_BANDS, mod(i, CR_SLOTS)           // band -> its slot
cr_shi:   .fill CR_SLOTS, >($4000 + i * 512)         // slot -> data page
// character c of a line: offset in the band's data (sprite c / 3, byte c % 3)
cr_clo:   .fill 24, <(floor(i / 3) * 64 + mod(i, 3))
cr_chi:   .fill 24, >(floor(i / 3) * 64 + mod(i, 3))
// the frame's bands (double buffered: entries 0..9 and 10..19)
cr_ty:    .fill 2 * CR_SLOTS, 0                      // sprite y
cr_tp:    .fill 2 * CR_SLOTS, 0                      // first sprite pointer
cr_tn:    .byte 0, 0                                 // end index of each buffer
cr_front: .byte 0                                    // 0 or 1: the buffer shown
cr_k:     .byte 0                                    // IRQ: next entry
cr_end:   .byte 0                                    //      end of this frame's
cr_b0:    .byte 0                                    // first band still showing
cr_y0:    .byte CR_START                             // its y
cr_rend:  .byte 0                                    // next text line to render
cr_tick:  .byte 0
cr_frame: .byte 0                                    // set by the bottom IRQ
cr_save1: .byte 0
cr_phase: .byte 0                                    // 0 hold, 1 fading, 2 credits
cr_wait:  .byte CR_HOLD
cr_fsteps: .byte CR_FADE_STEPS
cr_chunk: .byte 0                                    // fading: next 125-byte chunk
cr_lo:    .byte 0
// one step darker: greys down the grey ramp (the picture is white, light
// grey, grey, dark grey, black), other colours down the brightness order
.var cr_lum = List().add(0, 6, 9, 2, 11, 4, 8, 14, 12, 5, 10, 3, 15, 7, 13, 1)
.function cr_darker(c) {
    .if (c == 1) .return 15
    .if (c == 15) .return 12
    .if (c == 12) .return 11
    .if (c == 11) .return 0
    .for (var k = 1; k < 16; k++) { .if (cr_lum.get(k) == c) .return cr_lum.get(k - 1) }
    .return 0
}
cr_dark:   .fill 16, cr_darker(i)
cr_darkhi: .fill 16, cr_darker(i) << 4
cr_chlo:   .fill 8, <(i * 125)
cr_chs:    .fill 8, >(CR_SCREEN + i * 125)
cr_chc:    .fill 8, >($d800 + i * 125)

// credits: from victory (IRQs off, game display stopped); never returns
credits:
    sei
    lda $01
    sta cr_save1
    lda #$35                    // RAM at $a000, I/O
    sta $01
    jsr cr_music_on             // the music goes on meanwhile, screen blank
    ldx #0                      // the picture: bitmap $a000 -> $6000
!:  .for (var p = 0; p < 32; p++) {
    lda $a000 + p * $100,x
    sta CR_BITMAP + p * $100,x
    }
    lda $8c00,x                 //   screen (VIC bank 2: $8c00) -> $5c00
    sta CR_SCREEN,x
    lda $8d00,x
    sta CR_SCREEN+$100,x
    lda $8e00,x
    sta CR_SCREEN+$200,x
    lda $8f00,x
    sta CR_SCREEN+$300,x
    lda splashColorRam,x        //   colours
    sta $d800,x
    lda splashColorRam+$100,x
    sta $d900,x
    lda splashColorRam+$200,x
    sta $da00,x
    lda splashColorRam+$2e8,x
    sta $dae8,x
    lda #0                      // the sprite slots: empty
    .for (var p = 0; p < 20; p++) {
    sta $4000 + p * $100,x
    }
    inx
    beq !+
    jmp !-
!:  lda MSG_FONT,x              // the ROM font (its RAM copy, myui.s),
    sta cr_lo                   // bold: each glyph ORed with itself a pixel
    lsr                         // to the right
    ora cr_lo
    sta CR_FONT,x
    lda MSG_FONT+$100,x
    sta cr_lo
    lsr
    ora cr_lo
    sta CR_FONT+$100,x
    inx
    bne !-
    lda $dd00                   // VIC bank 1
    and #%11111100
    ora #%00000010
    sta $dd00
    lda #CR_D018
    sta $d018
    lda #$d8                    // multicolour, 40 columns
    sta $d016
    lda #$3b                    // bitmap, 25 rows
    sta $d011
    lda #splash.getBackgroundColor()
    sta $d020
    sta $d021
    ldx #7
!:  lda #CR_COLOUR
    sta $d027,x
    txa
    asl
    tay
    lda cr_xlo,x
    sta $d000,y
    dex
    bpl !-
    lda #%10000000              // sprite 7: x = 256
    sta $d010
    lda #0
    sta $d01c                   // hires
    sta $d017
    sta $d01d
    sta $d01b                   // in front of the picture
    lda #0                      // (on with the first band: cr_irq_top)
    sta $d015
    lda #0                      // the first bands' text
    sta cr_rend
!:  jsr cr_render
    lda cr_rend
    cmp #2 * CR_SLOTS
    bcc !-
    jsr cr_build
    sei                         // the music IRQ off: the credits' own on,
    lda #<cr_irq_bot            // from the bottom one (line 254, the music:
    sta $fffe                   // like the music IRQ's, so no frame without)
    lda #>cr_irq_bot
    sta $ffff
    lda #CR_IRQ_BOT
    sta $d012
    lda #1
    sta $d01a
    asl $d019
    cli
cr_loop:
    lda cr_frame                // once a frame, after the last band
    beq cr_loop
    lda #0
    sta cr_frame
    jsr cr_dim
    jsr cr_scroll
    jsr cr_build
    lda cr_rend                 // the next text line, once its slot is free
    lsr
    cmp #CR_BANDS
    bcs cr_loop
    sec
    sbc cr_b0
    cmp #CR_SLOTS
    bcs cr_loop
    jsr cr_render
    jmp cr_loop
cr_xlo: .fill 8, <(CR_X + i * 24)

// cr_dim: the picture as it is for a moment, then a few steps darker (one
// eighth of the screen per frame)
cr_dim:
    lda cr_phase
    cmp #1
    beq cd_fade
    bcs cd_done
    dec cr_wait                 // 0: holding
    bne cd_done
    inc cr_phase
cd_done:
    rts
cd_fade:
    lda cr_wait                 // (between steps)
    beq !+
    dec cr_wait
    rts
!:  ldx cr_chunk
    bne !+
    lda $d021                   // a step begins: the background
    and #$0f
    tay
    lda cr_dark,y
    sta $d021
    sta $d020
!:  lda cr_chlo,x
    sta temp
    sta temp2
    lda cr_chs,x
    sta temp+1
    lda cr_chc,x
    sta temp2+1
    ldy #124
cd_loop:
    lda (temp),y                // screen: two colours per byte
    and #$0f
    tax
    lda cr_dark,x
    sta cr_lo
    lda (temp),y
    lsr
    lsr
    lsr
    lsr
    tax
    lda cr_darkhi,x
    ora cr_lo
    sta (temp),y
    lda (temp2),y               // colour RAM
    and #$0f
    tax
    lda cr_dark,x
    sta (temp2),y
    dey
    bpl cd_loop
    inc cr_chunk
    lda cr_chunk
    cmp #8
    bne cd_done
    lda #0
    sta cr_chunk
    lda #CR_FADE_GAP
    sta cr_wait
    dec cr_fsteps
    bne cd_done
    lda #2                      // dark enough: the credits
    sta cr_phase
    rts

// cr_scroll: up a line every other frame (once the picture is dark); past
// the last band: again
cr_scroll:
    lda cr_phase
    cmp #2
    bcs !+
    rts
!:  inc cr_tick
    lda cr_tick
    lsr
    bcs crs_done
    dec cr_y0
    lda cr_y0
    cmp #CR_YMIN
    bcs crs_done
    adc #CR_STEP                // (C = 0) the top band is gone
    sta cr_y0
    inc cr_b0
    lda cr_b0
    cmp #CR_BANDS
    bcc crs_done
    lda #0                      // all gone: from the start
    sta cr_b0
    sta cr_rend
    sta cr_rend_band
    lda #CR_START
    sta cr_y0
crs_done:
    rts

// cr_build: the bands to show next frame (y, pointer) into the back buffer
cr_build:
    lda cr_front
    eor #1
    tay                         // Y = back buffer
    beq !+
    ldx #CR_SLOTS
    .byte $2c                   // (skip the ldx #0)
!:  ldx #0
    lda cr_b0
    sta temp
    lda cr_y0
    sta temp+1
crb_loop:
    lda temp
    cmp #CR_BANDS
    bcs crb_done
    cmp cr_rend_band            // (not rendered yet: stop)
    bcs crb_done
    lda temp+1
    cmp #CR_YMAX+1
    bcs crb_done
    sta cr_ty,x
    sty temp2
    ldy temp
    lda cr_slot,y
    asl
    asl
    asl                         // first block of the slot: 8 * slot
    sta cr_tp,x
    ldy temp2
    inx
    inc temp
    lda temp+1
    clc
    adc #CR_STEP
    sta temp+1
    bcc crb_loop                 // (past 255: below the screen)
crb_done:
    txa
    sta cr_tn,y
    sty cr_front                // shown from the next frame on
    rts
cr_rend_band: .byte 0           // bands rendered so far (cr_render)

// cr_render: text line cr_rend into its band's slot
cr_render:
    ldx cr_rend
    lda cr_tlo,x
    sta temp3
    lda cr_thi,x
    sta temp3+1
    txa
    lsr
    tay
    lda cr_slot,y
    tay
    lda cr_shi,y
    sta cr_page
    lda #0                      // role: sprite rows 0..7, name: 10..17
    bcc !+
    lda #CR_LINE_B * 3
!:  sta cr_roff
    ldy #0                      // centred: characters cr_p .. cr_p + length - 1
    lda #24
    sec
    sbc (temp3),y
    lsr
    sta cr_p
    clc
    adc (temp3),y
    sta cr_q
    lda #0
    sta cr_c
cr_char:
    lda cr_c
    cmp cr_p
    bcc cr_space
    cmp cr_q
    bcs cr_space
    sec
    sbc cr_p                    // (+ 1: past the length byte)
    tay
    iny
    lda (temp3),y
    .byte $2c                   // (skip the lda #$20)
cr_space:
    lda #$20
    sta cr_code                 // glyph: font + 8 * code
    asl
    asl
    asl
    sta temp4
    lda cr_code
    lsr
    lsr
    lsr
    lsr
    lsr
    clc
    adc #>CR_FONT
    sta temp4+1
    ldy cr_c
    lda cr_clo,y
    clc
    adc cr_roff
    sta temp2
    lda cr_chi,y
    adc cr_page
    sta temp2+1
    .for (var r = 0; r < 8; r++) {
    ldy #r
    lda (temp4),y
    ldy #r * 3
    sta (temp2),y
    }
    inc cr_c
    lda cr_c
    cmp #24
    beq !+
    jmp cr_char
!:  inc cr_rend
    lda cr_rend
    lsr
    sta cr_rend_band
    rts
cr_page: .byte 0
cr_roff: .byte 0
cr_c:    .byte 0
cr_p:    .byte 0
cr_q:    .byte 0
cr_code: .byte 0

// ---- raster IRQs: top (line 10), one per band, bottom (line 254) ------------
cr_irq_top:
    pha
    txa
    pha
    tya
    pha
    lda cr_front                // this frame's buffer
    tax
    lda cr_tn,x
    sta cr_end
    lda #0
    cpx #0
    beq !+
    lda #CR_SLOTS
!:  sta cr_k
    cmp cr_end
    lda #0                      // the sprites: on only with a band to show
    bcs !+                      // (else they would show whatever they
    lda #$ff                    //  showed last, where they were left)
!:  sta $d015
    bcs cri_bottom
    bcc cri_band
cr_irq_band:
    pha
    txa
    pha
    tya
    pha
cri_band:                        // re-place the 8 sprites: the next band
    ldx cr_k
    lda cr_ty,x
    .for (var s = 0; s < 8; s++) { sta $d001 + 2 * s }
    ldy cr_tp,x
    .for (var s = 0; s < 8; s++) {
    sty CR_SCREEN + $3f8 + s
    .if (s < 7) iny
    }
    inx
    stx cr_k
    cpx cr_end
    bcs cri_bottom
    lda cr_ty,x                 // the next band: 4 lines before it
    sec
    sbc #4
    sta $d012
    lda #<cr_irq_band
    sta $fffe
    lda #>cr_irq_band
    sta $ffff
    jmp cri_out
cri_bottom:
    lda #CR_IRQ_BOT
    sta $d012
    lda #<cr_irq_bot
    sta $fffe
    lda #>cr_irq_bot
    sta $ffff
cri_out:
    asl $d019
    pla
    tay
    pla
    tax
    pla
    rti
cr_code_end:
.segment TABLES
// cr_irq_bot: line 254, after the last band: the music (here, not in the
// main loop: on time whatever the loop is busy with), the next frame
cr_irq_bot:
    pha
    txa
    pha
    tya
    pha
    lda #1
    sta cr_frame
    lda #CR_IRQ_TOP
    sta $d012
    lda #<cr_irq_top
    sta $fffe
    lda #>cr_irq_top
    sta $ffff
    asl $d019
cr_music_irq:
    jsr sidplay
    pla
    tay
    pla
    tax
    pla
    rti

// cr_music_on: while the picture and the font are copied (several frames):
// the screen blank, a raster IRQ once a frame plays the music
cr_music_on:
    lda #$0b                    // screen off (the game's display is gone)
    sta $d011
    lda #0
    sta $d020
    lda #CR_IRQ_BOT
    sta $d012
    lda #<cr_irq_music
    sta $fffe
    lda #>cr_irq_music
    sta $ffff
    lda #1
    sta $d01a
    lda #$ff
    sta $d019
    cli
    rts
cr_irq_music:
    pha
    txa
    pha
    tya
    pha
    asl $d019
    jmp cr_music_irq
.segment CREDITS
.assert "credits code above the picture's new place ($4000-$7fff)", credits >= $8000, true
.assert "credits code below the title screen ($8c00)", cr_code_end <= $8c00, true
