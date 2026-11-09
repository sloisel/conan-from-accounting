#!/usr/bin/env python3
"""The open border (status strip, myui.s) must be black apart from the
strip's own pictures: below the window (line 247 on) and above it (lines
0..80). Stops at the top IRQ (line 37) every frame, when the buffer holds the
previous frame's bottom border and this frame's top lines. (The side
borders are not checked: they still show $d020, which flashes when hurt.)
Usage: tools/border_check.py [FRAMES] [KEY...]      (VICE running the game)
       tools/border_check.py sweep [POSITIONS]     many camera positions"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vice
import game_check as g

UI_X = (32, 48, 64, 284, 298, 312)
STOP_AT = os.environ.get("STOP_AT", "ag_irq_pre")


def check(v, frames=200, verbose=True):
    """returns (bad frames, {line: count} of stray pixels, frames missing the strip)"""
    a = vice.addr
    bad, lines, missing = 0, {}, 0
    for f in range(frames):
        num = v.checkpoint(a(STOP_AT))
        v.run_until_hit(num, 10)
        v.delete_checkpoint(num)
        dw, dh, xo, yo, iw, ih, pix, pal = v.screenshot()
        first = max(0, 52 - yo)                      # first raster line in the buffer
        last = min(311, 52 - yo + dh - 1)
        col = lambda line, x: pix[(yo + line - 52) * dw + xo + x - 24]
        cols = list(v.mem_get(a("ui_col"), 6))
        stray = {}
        for line in list(range(first, 37)) + list(range(247, last + 1)):
            for x in range(31, 335):                  # (side borders: $d020, hurt flash)
                c = col(line, x)
                if not c:
                    continue
                if 16 <= line <= 36 and any(ux <= x < ux + 24 for ux in UI_X):
                    continue
                stray[line] = stray.get(line, 0) + 1
        seen = [any(col(line, x) for line in range(26, 37) for x in range(UI_X[k], UI_X[k] + 16))
                for k in range(6)]
        if stray or not all(seen):
            bad += 1
            missing += not all(seen)
            for k, n in stray.items():
                lines[k] = lines.get(k, 0) + 1
            if verbose and bad <= 5:
                for line in sorted(stray)[:3]:
                    xs = [x for x in range(31, 335) if col(line, x)
                          and not (16 <= line <= 36 and any(ux <= x < ux + 24 for ux in UI_X))]
                    print(f"   line {line}: x {xs[0]}..{xs[-1]} ({len(xs)} px), colours "
                          f"{sorted({col(line, x) for x in xs})}")
                print(f"frame {f}: stray pixels on lines {sorted(stray)[:12]}"
                      f"{'...' if len(stray) > 12 else ''}, strip pictures {seen}")
    return bad, lines, missing


def sweep(v, spots=60, seed=5, verbose=True):
    """the same check at many camera positions (teleports all over the map:
    the ring offset decides which screen bytes the hidden badline fetches)"""
    import random
    rnd = random.Random(seed)
    a = vice.addr
    gx = a("sprite_data_2") + 32 * 9
    bad = 0
    for _ in range(spots):
        x, y = rnd.randrange(40, 216) * 256 + rnd.randrange(8) * 32, rnd.randrange(30, 240) * 256 + rnd.randrange(8) * 32
        v.mem_set(gx, [x & 255]); v.mem_set(gx + 32, [x >> 8])
        v.mem_set(gx + 64, [y & 255]); v.mem_set(gx + 96, [y >> 8])
        for _ in range(12):                        # (a full redraw takes a few frames)
            g.bottom_irq(v)
        b, lines, _ = check(v, 2, verbose=False)
        if b:
            bad += 1
            if verbose and bad <= 5:
                print(f"camera at char ({x >> 8}, {y >> 8}): stray lines {sorted(lines)[:10]}")
    return bad


def main(argv):
    if argv and argv[0] == "sweep":
        v = vice.Vice()
        try:
            v.mem_set(vice.addr("debug_no_death"), [1])
            bad = sweep(v, int(argv[1]) if len(argv) > 1 else 60)
        finally:
            v.close()
        print(f"sweep: {bad} camera positions with border glitches")
        return
    frames = int(argv[0]) if argv else 200
    v = vice.Vice()
    try:
        vice.set_keys(v, argv[1:])
        bad, lines, missing = check(v, frames)
        vice.set_keys(v, [])
    finally:
        v.close()
    print(f"{frames} frames: {bad} with border glitches ({missing} missing a strip picture); "
          f"lines {sorted(lines.items())[:20]}")


if __name__ == "__main__":
    main(sys.argv[1:])
