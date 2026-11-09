#!/usr/bin/env python3
"""Pixel-exact check of the AGSP game display against a reference renderer.

At the bottom IRQ of a frame (line 246, the visible window is complete and
p_cx/p_cy/p_fine/p_xs still describe it) the frame buffer is compared with a
rendering of the map built from emulator RAM (map, tile tables, charset,
colours). Sprite boxes are masked out. The player is teleported by the test
(<= 8 px per frame for incremental scrolling, or far for full redraws).

Usage: tools/game_check.py [STEPS] [SEED]      (VICE must be running the game)
"""
import os
import random
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vice

T_LINE, BOTTOM, X_MIN, X_MAX = 81, 246, 31, 334


class Ref:
    def __init__(self, v):
        a = vice.addr
        self.map = v.mem_get(a("map"), 4096)
        self.tc = v.mem_get(a("tilechar"), 1024)
        self.tk = v.mem_get(a("tilecol"), 1024)
        self.cs = v.mem_get(a("charset"), 2048)
        regs = v.mem_get(0xD021, 3)
        self.bg = [regs[0] & 15, regs[1] & 15, regs[2] & 15]

    def pixel(self, wx, wy):
        """colour index of world pixel (wx, wy)"""
        cx, cy = wx >> 3, wy >> 3
        tile = self.map[(cy >> 2) * 64 + (cx >> 2)]
        j = (cy & 3) * 4 + (cx & 3)
        ch, col = self.tc[j * 64 + tile], self.tk[j * 64 + tile]
        bits = self.cs[ch * 8 + (wy & 7)]
        px = wx & 7
        if col & 8:                       # multicolour char
            pair = (bits >> (6 - (px & 6))) & 3
            return [self.bg[0], self.bg[1], self.bg[2], col & 7][pair]
        return col & 15 if bits & (0x80 >> px) else self.bg[0]


def frame(v):
    _, d = v.cmd(0x84, b"\x01\x00")
    flen = struct.unpack_from("<I", d)[0]
    dw, dh, xo, yo, iw, ih, bpp = struct.unpack_from("<HHHHHHB", d, 4)
    blen = struct.unpack_from("<I", d, 4 + flen)[0]
    pix = d[8 + flen: 8 + flen + blen]
    return lambda line, x: pix[(yo + line - 52) * dw + xo + x - 24]


def _unused_sprite_mask(v):
    r = v.mem_get(0xD000, 0x17)
    boxes = []
    for i in range(8):
        if r[0x15] >> i & 1:
            x = r[2 * i] | ((r[0x10] >> i & 1) << 8)
            y = r[2 * i + 1]
            boxes.append((x, x + 24, y + 1, y + 22))
    return lambda line, x: any(x0 <= x < x1 and y0 <= line < y1 for x0, x1, y0, y1 in boxes)


class Sprites:
    """the hardware sprites of the frame being displayed (multicolour)"""

    def __init__(self, v):
        r = v.mem_get(0xD000, 0x2F)
        ptr = v.mem_get(0x07F8, 8)              # pointers in AG_SCREEN
        self.spr = []
        for n in range(8):
            if r[0x15] >> n & 1:
                x = r[2 * n] | ((r[0x10] >> n & 1) << 8)
                self.spr.append((n, x, r[2 * n + 1], r[0x27 + n] & 15,
                                 v.mem_get(ptr[n] * 64, 63)))
        self.mc = (r[0x25] & 15, r[0x26] & 15)

    def pixel(self, line, x):
        """(colour, sprite number) of the topmost sprite pixel, or None"""
        for n, sx, sy, col, data in self.spr:  # sprite 0 has priority
            if sx <= x < sx + 24 and sy < line <= sy + 21:
                b = data[(line - sy - 1) * 3 + (x - sx) // 8]
                bits = b >> (6 - ((x - sx) & 6)) & 3
                if bits:
                    return [None, self.mc[0], col, self.mc[1]][bits], n
        return None

    def covers(self, line, x):
        return any(sx <= x < sx + 24 and sy < line <= sy + 21 for _, sx, sy, _, _ in self.spr)


def frame_state(v):
    """state of the frame being finished: p_fine, p_xs, p_cx, p_cy, sprites,
    blank flag, and the pointer-row switching done in it"""
    a = vice.addr
    n = v.mem_get(a("n_d018top"), 4)            # d018top, d018aft, swB1, swB2
    return (tuple(v.mem_get(a("p_fine"), 4)), Sprites(v),
            v.mem_get(a("n_blank"), 1)[0], n)


def glitch_lines(state):
    """raster lines on which sprites may legitimately read the mirror's
    pointer slots: lines B and B+1 of a switched row (the switch back waits
    for the badline's and the sprites' DMA), the whole rest of the window
    for B >= 245, lines 82..B+1 for an early switch"""
    (fine, xs, cx, cy), _, _, (top, aft, b1, b2) = state
    lines = set()
    if top != 0x1E and T_LINE - fine == T_LINE:   # row 0 at line 81
        lines.add(82)
    for b in (b1, b2):
        if not b:
            continue
        if b >= BOTTOM - 1:
            lines.update(range(b, BOTTOM + 1))
            continue
        first = 82 if (aft != 0x1E and b == b1) else b
        lines.update(range(first, b + 2))
    return {line: range(8) for line in lines}


def check_frame(v, ref, state, glitches=None):
    """Compare the window with the reference (background + sprites).
    Sprite pixels on the allowed pointer-switch lines are not failures but
    are tallied in `glitches` (a dict line -> count) if given."""
    (fine, xs, cx, cy), spr, blank, _ = state
    px = frame(v)
    bad = []
    if blank:                                   # full redraw in progress
        bad = [(line, x, px(line, x), 0) for line in range(T_LINE, BOTTOM + 1)
               for x in range(X_MIN, X_MAX + 1, 3)
               if px(line, x) and not spr.covers(line, x)]
        return (cx, cy, fine, xs), bad, []
    allow = glitch_lines(state)
    for line in range(T_LINE, BOTTOM + 1):
        wy = cy * 8 + fine + line - T_LINE
        ok_spr = allow.get(line, ())
        for x in range(X_MIN, X_MAX + 1):
            s = spr.pixel(line, x)
            want = s[0] if s else ref.pixel(cx * 8 + x - 24 - xs, wy)
            got = px(line, x)
            if got != want:
                if any(n in ok_spr and sx <= x < sx + 24 and sy < line <= sy + 21
                       for n, sx, sy, _, _ in spr.spr):
                    if glitches is not None:
                        glitches[line] = glitches.get(line, 0) + 1
                    continue
                bad.append((line, x, got, want))
    band = [(line, x) for line in range(56, T_LINE) for x in range(X_MIN, X_MAX + 1, 2)
            if px(line, x)]
    return (cx, cy, fine, xs), bad, band


def ring_diff(v, ref, cx, cy):
    """visible ring slots (rows 0..21, cols 0..38) that disagree with the map"""
    scr = v.mem_get(0x400, 1024)
    col = v.mem_get(0xD800, 1024)
    alt = v.mem_get(0x0C00, 1024)                  # AG_ALT mirror
    S = (40 * cy + cx) % 1024
    bad = []
    for r in range(22):
        for c in range(39):
            wx, wy = cx + c, cy + r
            tile = ref.map[(wy >> 2) * 64 + (wx >> 2)]
            j = (wy & 3) * 4 + (wx & 3)
            slot = (S + 40 * r + c) % 1024
            got = alt[slot] if slot >= 1016 else scr[slot]
            if (slot >= 977 or slot <= 38) and alt[slot] != got:
                bad.append((r, c, slot, "mirror"))
            if got != ref.tc[j * 64 + tile] or (col[slot] & 15) != (ref.tk[j * 64 + tile] & 15):
                bad.append((r, c, slot))
    return bad


def bottom_irq(v):
    """Stop at the bottom IRQ of the next frame. Returns that frame's state;
    on return the CPU is a few lines further on (line 246 fully rendered)."""
    num = v.checkpoint(vice.addr("ag_irq_bot"))
    if not v.run_until_hit(num, 10):
        raise RuntimeError("bottom IRQ not reached")
    state = frame_state(v)
    num = v.checkpoint(vice.addr("ab_done"))
    if not v.run_until_hit(num, 10):
        raise RuntimeError("bottom IRQ did not finish")
    return state


def run(v, steps=200, seed=1, verbose=True):
    """Random-walk the player (plus a far jump every 50 frames) and check
    every frame. Returns the number of bad frames."""
    rnd = random.Random(seed)
    a = vice.addr
    gx = a("sprite_data_2") + 32 * 9          # player global x lo/hi, y lo/hi
    failures = 0
    glitch_frames, glitch_lines_max = 0, 0
    bottom_irq(v)
    ref = Ref(v)
    vel = (0, 0)
    for step in range(steps):
        g = v.mem_get(gx, 128)
        x = g[0] | g[32] << 8
        y = g[64] | g[96] << 8
        if step % 50 == 49:                      # far jump: full redraw path
            x, y = rnd.randrange(40, 216) * 256, rnd.randrange(30, 240) * 256
        else:
            if step % 12 == 0:
                vel = (rnd.randint(-8, 8) * 32, rnd.randint(-8, 8) * 32)
            x = min(max(x + vel[0], 0), 255 * 256)
            y = min(max(y + vel[1], 0), 255 * 256)
        v.mem_set(gx, [x & 255]); v.mem_set(gx + 32, [x >> 8])
        v.mem_set(gx + 64, [y & 255]); v.mem_set(gx + 96, [y >> 8])
        state = bottom_irq(v)
        gl = {}
        (cx, cy, fine, xs), bad, band = check_frame(v, ref, state, gl)
        if gl:
            glitch_frames += 1
            glitch_lines_max = max(glitch_lines_max, len(gl))
        if bad or band:
            failures += 1
            if verbose:
                print(f"step {step}: cam ({cx},{cy}) fine={fine} xs={xs}: "
                      f"{len(bad)} wrong pixels, {len(band)} in blank band"
                      + (f"; first {bad[0]}" if bad else "")
                      + f"; lines {sorted(set(b[0] for b in bad))[:12]}"
                      + f"; d018top/aft/B1/B2 {list(state[3])}"
                      + f"; sprites {[(n, x, y) for n, x, y, _, _ in state[1].spr]}")
                rd = ring_diff(v, ref, cx, cy)
                print(f"   ring vs map: {len(rd)} wrong slots {rd[:6]}; "
                      f"ag_cx/cy={tuple(v.mem_get(a('ag_cx'), 2))}")
            if failures == 1:
                vice.do_shot(v, os.path.join(vice.ROOT, "screenshots", "game_check_fail.png"))
            if failures > 5:
                break
    if verbose:
        print(f"sprite pixel rows read from the mirror pointers: {glitch_frames} frames, "
              f"at most {glitch_lines_max} raster line(s) in a frame")
    return failures


def main(argv):
    steps = int(argv[0]) if argv else 200
    seed = int(argv[1]) if len(argv) > 1 else 1
    v = vice.Vice()
    try:
        failures = run(v, steps, seed)
    finally:
        v.close()
    print(f"{steps} frames checked, {failures} bad")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main(sys.argv[1:])
