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


class Sprites:
    """the sprites of the frame being displayed, from the multiplexer's
    front plan (mymux.s): each entry = one sprite on one hardware sprite"""

    def __init__(self, v):
        a = vice.addr
        front = v.mem_get(a("mx_front"), 1)[0]
        n = v.mem_get(a("mx_n") + front, 1)[0]
        base = front * 16
        get = lambda name: v.mem_get(a(name) + base, max(n, 1))
        slot, y, xlo, msb, col, ptr, lidx = (get(k) for k in
            ("mx_slot", "mx_y", "mx_xlo", "mx_msb", "mx_col", "mx_ptr", "mx_lidx"))
        self.spr = []
        for e in range(n):
            self.spr.append((slot[e], xlo[e] | (1 if msb[e] else 0) << 8, y[e], col[e] & 15,
                             v.mem_get(ptr[e] * 64, 63), lidx[e], ptr[e]))
        self.spr.sort(key=lambda s: s[0])            # hardware sprite 0 in front
        r = v.mem_get(0xD025, 2)
        self.mc = (r[0] & 15, r[1] & 15)

    def pixel(self, line, x):
        """(colour, hardware sprite) of the topmost sprite pixel, or None"""
        for n, sx, sy, col, data, _, _ in self.spr:
            if sx <= x < sx + 24 and sy < line <= sy + 21:
                b = data[(line - sy - 1) * 3 + (x - sx) // 8]
                bits = b >> (6 - ((x - sx) & 6)) & 3
                if bits:
                    return [None, self.mc[0], col, self.mc[1]][bits], n
        return None

    def covers(self, line, x):
        return any(sx <= x < sx + 24 and sy < line <= sy + 21 for _, sx, sy, *_ in self.spr)

    def entry(self, lidx):
        for e in self.spr:
            if e[5] == lidx:
                return e
        return None


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
                       for n, sx, sy, *_ in spr.spr):
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
    ptrcode = vice.addr("ag_fix_rows") and 0xD5
    S = (40 * cy + cx) % 1024
    bad = []
    for r in range(22):
        for c in range(39):
            wx, wy = cx + c, cy + r
            tile = ref.map[(wy >> 2) * 64 + (wx >> 2)]
            j = (wy & 3) * 4 + (wx & 3)
            slot = (S + 40 * r + c) % 1024
            want = ref.tc[j * 64 + tile]
            if slot >= 1016:                        # dedicated code + glyph copy
                n = slot - 1016
                if alt[slot] != ptrcode + n:
                    bad.append((r, c, slot, "slot code"))
                got = want if ref.cs[(ptrcode + n) * 8:(ptrcode + n) * 8 + 8] == \
                    ref.cs[want * 8:want * 8 + 8] else -1
            else:
                got = scr[slot]
                if (slot >= 977 or slot <= 38) and alt[slot] != got:
                    bad.append((r, c, slot, "mirror"))
            if got != want or (col[slot] & 15) != (ref.tk[j * 64 + tile] & 15):
                bad.append((r, c, slot))
    return bad


def bottom_irq(v):
    """Stop at the bottom IRQ of the next frame. Returns that frame's state;
    on return the CPU is a few lines further on (line 246 fully rendered)."""
    # ag_bot_body runs once per frame (bottom IRQ, or chained from a swap IRQ
    # when the pointer row is at line 245/246); p_* still describe this frame
    num = v.checkpoint(vice.addr("ag_bot_body"))
    if not v.run_until_hit(num, 10):
        raise RuntimeError("bottom IRQ not reached")
    state = frame_state(v)
    # did the main loop finish its update (it commits, then idles)?
    bottom_irq.main_done = v.mem_get(vice.addr("ag_commit"), 1)[0] == 1
    num = v.checkpoint(vice.addr("ab_done"))
    if not v.run_until_hit(num, 10):
        raise RuntimeError("bottom IRQ did not finish")
    return state


def check_coords(v):
    """Every sprite's screen position must be its world position minus the
    camera (both in whole pixels) plus the screen offsets; y only where it
    is fully inside the window (clipping and parking change it otherwise)."""
    a = vice.addr
    n = v.mem_get(a("sprite2_count"), 1)[0]
    t = v.mem_get(a("sprite_data_2"), 32 * 27)
    sm = v.mem_get(a("smooth_x"), 2)
    smy = v.mem_get(a("smooth_y"), 2)
    camx, camy = (sm[0] | sm[1] << 8) >> 5, (smy[0] | smy[1] << 8) >> 5
    bad = []
    for i in range(n):
        f = lambda k: t[32 * k + i]
        gx, gy = f(9) | f(10) << 8, f(11) | f(12) << 8
        ex, ey = (gx >> 5) - camx + 20, (gy >> 5) - camy + 68
        x = f(0) | f(1) << 8
        if f(2) == 0:
            continue                       # parked: not displayed (frozen, idle sword)
        if x != ex & 0xFFFF:
            bad.append((i, "x", x, ex))
        parked_sword = i == 1 and f(6) == 0 and f(2) == 0    # idle sword: no sprite
        if 81 <= ey <= 230 and 0 <= ex < 344 and not f(21) & 0x40 and f(2) != ey \
                and not parked_sword:
            bad.append((i, "y", f(2), ey))
    return bad


def run(v, steps=200, seed=1, verbose=True):
    """Random-walk the player (plus a far jump every 50 frames) and check
    every frame. Returns the number of bad frames."""
    rnd = random.Random(seed)
    a = vice.addr
    gx = a("sprite_data_2") + 32 * 9          # player global x lo/hi, y lo/hi
    failures = 0
    glitch_frames, glitch_lines_max, crossing = 0, 0, 0
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
        idle_at_poke = getattr(bottom_irq, "main_done", False)
        state = bottom_irq(v)
        # (only when the main loop read the poked position: it was idle when
        # the harness poked, and has finished an update since)
        cb = check_coords(v) if idle_at_poke and bottom_irq.main_done else []
        if cb:
            failures += 1
            if verbose:
                print(f"step {step}: sprite screen positions wrong: {cb[:3]}")
        gl = {}
        (cx, cy, fine, xs), bad, band = check_frame(v, ref, state, gl)
        if not state[2] and any(sy < line <= sy + 21 for line in glitch_lines(state)
                                for _, _, sy, *_ in state[1].spr):
            crossing += 1
        if gl:                       # sprites must be right on switched lines too
            glitch_frames += 1
            glitch_lines_max = max(glitch_lines_max, len(gl))
            bad = bad + [(line, None, "sprite on pointer-switch line", n)
                         for line, n in sorted(gl.items())]
        if bad or band:
            failures += 1
            if verbose:
                print(f"step {step}: cam ({cx},{cy}) fine={fine} xs={xs}: "
                      f"{len(bad)} wrong pixels, {len(band)} in blank band"
                      + (f"; first {bad[0]}" if bad else "")
                      + f"; lines {sorted(set(b[0] for b in bad))[:12]}"
                      + f"; d018top/aft/B1/B2 {list(state[3])}"
                      + f"; sprites {[(n, x, y) for n, x, y, *_ in state[1].spr]}")
                rd = ring_diff(v, ref, cx, cy)
                print(f"   ring vs map: {len(rd)} wrong slots {rd[:6]}; "
                      f"ag_cx/cy={tuple(v.mem_get(a('ag_cx'), 2))}")
                fr = v.mem_get(a("mx_front"), 1)[0]
                print(f"   plan: front {fr} back {v.mem_get(a('mx_back'), 1)[0]} "
                      f"n {list(v.mem_get(a('mx_n'), 2))} "
                      f"y {list(v.mem_get(a('mx_y') + fr * 16, 8))} "
                      f"line {list(v.mem_get(a('mx_line') + fr * 16, 8))} "
                      f"slot {list(v.mem_get(a('mx_slot') + fr * 16, 8))} "
                      f"state-n {len(state[1].spr)}")
            if failures == 1:
                vice.do_shot(v, os.path.join(vice.ROOT, "screenshots", "game_check_fail.png"))
            if failures > 5:
                break
    if verbose:
        print(f"frames with a sprite on a pointer-switch line: {crossing}; "
              f"wrong sprite rows there: {glitch_frames} frames")
    return failures


def ensure_test_monster(v):
    """Freeze the monsters (no behaviour, no (de)spawning) and make sure
    sprite 2 exists, so tests can place it freely."""
    a = vice.addr
    v.mem_set(a("debug_freeze_enemies"), [1])
    if v.mem_get(a("sprite2_count"), 1)[0] < 3:
        base = a("sprite_data_2")
        sp0 = 0x2000 // 64
        for field, val in ((5, 4), (6, 0), (7, 1), (8, 255), (4, sp0 + 49), (3, 14),
                           (19, 0), (21, 0), (23, 1), (25, 0)):
            v.mem_set(base + 32 * field + 2, [val])
        v.mem_set(a("sprite2_count"), [3])


def check_top_clip(v, verbose=True):
    """Put the player so the enemy (logical sprite 2, fixed in the world)
    straddles the top edge by k = 1..20 rows. Each time the hardware sprite
    must start at line 82 and show exactly rows k..20 of one of the enemy's
    animation frames, and the whole window must pass the pixel check.
    Returns the number of failures."""
    a = vice.addr
    base = a("sprite_data_2")
    ensure_test_monster(v)
    ex, ey = 14 * 256, 222 * 256                        # put the test monster here
    for off, val in ((32 * 9, ex & 255), (32 * 10, ex >> 8), (32 * 11, ey & 255), (32 * 12, ey >> 8)):
        v.mem_set(base + off + 2, [val])
    sp0 = 0x2000 // 64
    frames = [v.mem_get((sp0 + f) * 64, 63) for f in range(49, 85)]   # any monster frame
    ref = Ref(v)
    fails = 0
    for k in list(range(1, 21)) + [0, 21, 25]:
        px, py = ex, ey + (70 + k) * 32                # enemy y reg = 81 - k
        for off, val in ((32 * 9, px & 255), (32 * 10, px >> 8),
                         (32 * 11, py & 255), (32 * 12, py >> 8)):
            v.mem_set(base + off, [val])
        settled = 0
        for _ in range(60):                             # until any redraw is done
            state = bottom_irq(v)
            cam = tuple(v.mem_get(a("ag_cx"), 2))
            settled = settled + 1 if (state[0][2:] == cam and not state[2]) else 0
            if settled >= 3:
                break
        e = state[1].entry(2)                       # the test monster's plan entry
        enabled = e is not None
        y = e[2] if e else 0
        data = e[4] if e else bytes(63)
        _, bad, band = check_frame(v, ref, state)
        if 1 <= k <= 20:
            vis = 63 - 3 * k
            ok = (enabled and y == 81 and not bad and not band and data[vis:] == bytes(63 - vis)
                  and any(data[:vis] == f[3 * k:] for f in frames))
        elif k == 0:
            ok = enabled and y == 81 and any(data == f for f in frames) and not bad
        else:                                           # fully above: parked
            ok = y == 0 and not bad and not band
        if not ok:
            fails += 1
        if verbose and not ok:
            print(f"top clip k={k}: sprite 2 y={y} enabled={enabled}, {len(bad)} wrong pixels")
    return fails


def check_edges(v, verbose=True, frames=7 * 130):
    """Pointer-row switching at the window edges. The pointer cells are fixed
    in the world, so walk the camera diagonally (the ring offset changes
    every frame) while keeping the enemy at a fixed screen position near the
    top or bottom edge. Every frame must be pixel-exact, sprites included.
    Returns (bad frames, frames with a sprite on an edge switch line)."""
    a = vice.addr
    base = a("sprite_data_2")
    ensure_test_monster(v)
    ref = Ref(v)
    bad_frames = edge = 0
    def put(i, x, y):
        x, y = min(max(x, 0), 0xFFFF), min(max(y, 0), 0xFFFF)
        for off, val in ((32 * 9, x & 255), (32 * 10, x >> 8),
                         (32 * 11, y & 255), (32 * 12, y >> 8)):
            v.mem_set(base + off + i, [val])
    for yreg in (81, 84, 88, 222, 230, 238, 244):
        cam_x, cam_y = 10 * 256, 10 * 256
        put(0, cam_x + 160 * 32, cam_y + 83 * 32)
        for _ in range(8):                                # let any redraw finish
            bottom_irq(v)
        for step in range(frames // 7):
            cam_x += 5 * 32
            cam_y += 3 * 32
            put(0, cam_x + 160 * 32, cam_y + 83 * 32)     # player -> camera
            put(2, cam_x + 100 * 32, cam_y + (yreg - 68) * 32)   # enemy on screen
            state = bottom_irq(v)
            if state[2]:
                continue
            gl = {}
            _, bad, band = check_frame(v, ref, state, gl)
            if any(sy < l <= sy + 21 and (l <= 90 or l >= 238) for l in glitch_lines(state)
                   for _, _, sy, *_ in state[1].spr):
                edge += 1
            if bad or band or gl:
                bad_frames += 1
                if verbose and bad_frames <= 5:
                    print(f"edge y={yreg}: {len(bad)} bad {bad[:2]}, glitch {gl}, "
                          f"switch {list(state[3])}")
    return bad_frames, edge


def main(argv):
    steps = int(argv[0]) if argv else 200
    seed = int(argv[1]) if len(argv) > 1 else 1
    v = vice.Vice()
    try:
        failures = run(v, steps, seed)
        eb, ec = check_edges(v)
        print(f"window-edge pointer switching: {ec} frames with a sprite there, {eb} bad")
        failures += eb
        clip_fails = check_top_clip(v)
        print(f"top-edge clipping: {23 - clip_fails}/23 positions OK")
        failures += clip_fails
    finally:
        v.close()
    print(f"{steps} frames checked, {failures} bad")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main(sys.argv[1:])
