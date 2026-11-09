#!/usr/bin/env python3
"""Closed-loop verification of the AGSP prototype (proto/agsp.s).

For each (S, fine, xs) it pokes the parameters, runs a few frames, grabs the
raw VIC framebuffer and decodes every fully visible cell back to the ring
slot it shows (glyph row 0 = colour = 1 + slot>>8, glyph row 2 = slot & 255).
It then checks slot == (S + 40*row + col) mod 1024 and that the visible
window starts exactly at line 81 with row 0 at line 81 - fine.

Usage: VICE_SYMS=build/agsp.vs tools/agsp_check.py [all|quick|S [fine [xs]]]
"""
import os
import random
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vice

T_LINE, BOTTOM = 81, 246          # visible raster lines (inclusive)
X_MIN, X_MAX = 31, 334            # 38-column window, VIC x coordinates


def frame(v):
    _, d = v.cmd(0x84, b"\x01\x00")
    flen = struct.unpack_from("<I", d)[0]
    dw, dh, xo, yo, iw, ih, bpp = struct.unpack_from("<HHHHHHB", d, 4)
    blen = struct.unpack_from("<I", d, 4 + flen)[0]
    pix = d[8 + flen: 8 + flen + blen]
    # inner area = 320x200 text window; measured: first row is raster line 52, x 24
    return lambda line, x: pix[(yo + line - 52) * dw + xo + x - 24]


def decode(v, S, fine, xs):
    px = frame(v)
    r0 = T_LINE - fine
    errors, cells = [], 0
    for r in range(23):
        top = r0 + 8 * r
        if top < T_LINE or top + 2 > BOTTOM:
            continue
        for c in range(40):
            left = 24 + 8 * c + xs
            if left < X_MIN or left + 7 > X_MAX:
                continue
            colour = px(top, left)
            code = 0
            for b in range(8):
                code = code << 1 | (px(top + 2, left + b) != 0)
            got = ((colour - 1) & 3) * 256 + code if colour else None
            want = (S + 40 * r + c) % 1024
            cells += 1
            if got != want:
                errors.append((r, c, got, want))
    # blank band above the window, picture right at line T_LINE
    band = any(px(line, x) for line in range(56, T_LINE) for x in range(X_MIN, X_MAX, 3))
    first = any(px(T_LINE, x) for x in range(X_MIN, X_MAX))
    return cells, errors, band, first


def run(v, S, fine, xs, verbose=False):
    v.mem_set(vice.addr("p_S"), [S & 255, S >> 8])
    v.mem_set(vice.addr("p_fine"), [fine])
    v.mem_set(vice.addr("p_xs"), [xs])
    run_frames(v, 3)
    cells, errors, band, first = decode(v, S, fine, xs)
    ok = not errors and not band and first and cells > 700
    if verbose or not ok:
        msg = f"S={S:4} fine={fine} xs={xs}: {cells} cells, {len(errors)} wrong"
        if band:
            msg += ", junk in blank band"
        if not first:
            msg += ", line 81 empty"
        if errors:
            r, c, got, want = errors[0]
            delta = None if got is None else (got - want) % 1024
            msg += f"; first r{r}c{c} got {got} want {want} (delta {delta})"
        print(msg)
    return ok


def run_frames(v, n):
    a = vice.addr("irq_bot")
    _, d = v.cmd(0x12, struct.pack("<HHBBBB", a, a, 1, 1, 4, 0))
    num = struct.unpack_from("<I", d)[0]
    for _ in range(n):
        v.run_until_hit(num, 5)
    v.delete_checkpoint(num)


def main(argv):
    v = vice.Vice()
    try:
        if argv and argv[0] not in ("all", "quick"):
            S = int(argv[0])
            fine = int(argv[1]) if len(argv) > 1 else 0
            xs = int(argv[2]) if len(argv) > 2 else 0
            run(v, S, fine, xs, verbose=True)
            vice.do_shot(v, os.path.join(vice.ROOT, "screenshots", "agsp.png"))
            return
        if argv and argv[0] == "all":
            cases = [(S, S % 8, (S // 8) % 8) for S in range(1024)]
        else:
            rnd = random.Random(1)
            cases = [(S, 0, 0) for S in range(0, 80)] + \
                    [(rnd.randrange(1024), rnd.randrange(8), rnd.randrange(8)) for _ in range(60)]
        bad = sum(not run(v, *c) for c in cases)
        print(f"{len(cases) - bad}/{len(cases)} positions OK")
    finally:
        v.close()


if __name__ == "__main__":
    main(sys.argv[1:])
