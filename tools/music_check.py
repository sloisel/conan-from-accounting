#!/usr/bin/env python3
"""The music keeps time through the ending (VICE must be running the game,
in its main loop): from `victory` on, the gap between consecutive calls of
the music player, in frames, measured with CIA 2's timers chained into a
32-bit cycle counter (the game does not use them).

Usage: tools/music_check.py [CALLS]      (default 700: the hold, the fade,
                                          some scrolling)
Prints the gaps and returns (max gap, the calls' frame numbers)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vice

PAL_FRAME = 312 * 63
SIDPLAY = 0xE003


def cycles(v):
    t = v.mem_get(0xDD04, 4)
    return 0xFFFFFFFF - ((t[3] << 24) | (t[2] << 16) | (t[1] << 8) | t[0])


def ending(v, calls=700):
    """jump to the ending and time the music calls: list of gaps in frames"""
    v.mem_set(0xDD0E, [0x00])                   # timers stopped
    v.mem_set(0xDD0F, [0x00])
    v.mem_set(0xDD04, [0xFF, 0xFF, 0xFF, 0xFF])   # latches $ffff
    v.mem_set(0xDD0F, [0x51])                   # B: load, count A's underflows, start
    v.mem_set(0xDD0E, [0x11])                   # A: load, continuous, start
    num = v.checkpoint(SIDPLAY)                 # the game's last music call
    v.run_until_hit(num, 5)
    t0 = cycles(v)
    num = v.checkpoint(vice.addr("forever"))    # (back in the main loop)
    v.run_until_hit(num, 5)
    v.set_reg("PC", vice.addr("victory"))
    t, gaps = None, []
    for _ in range(calls):
        num = v.checkpoint(SIDPLAY)
        if not v.run_until_hit(num, 20):
            break
        c = cycles(v)
        if t is not None:
            gaps.append((c - t) / PAL_FRAME)
        t = c
        if len(gaps) == 0 and t0 is not None:
            gaps.append((c - t0) / PAL_FRAME)
    return gaps


def main(argv):
    calls = int(argv[0]) if argv else 700
    v = vice.Vice()
    try:
        gaps = ending(v, calls)
    finally:
        v.close()
    late = [(i, round(g, 2)) for i, g in enumerate(gaps) if g > 1.05]
    print(f"{len(gaps)} gaps, max {max(gaps):.2f} frames, mean {sum(gaps) / len(gaps):.3f}; "
          f"late calls (call number, gap): {late[:40]}")


if __name__ == "__main__":
    main(sys.argv[1:])
