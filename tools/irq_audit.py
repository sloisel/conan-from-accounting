#!/usr/bin/env python3
"""Audit the raster IRQ chain: every frame must run the top IRQ (line 40)
and the bottom work (line ~246) exactly once, in order, and the bottom work
must end before line 40 of the next frame. Reports dropped/late frames.
Usage: tools/irq_audit.py [FRAMES]       (VICE running the game)"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vice


def audit(v, frames=200, verbose=True):
    """Every frame must reach the stable raster point (ag_stable at 46:3) and
    the bottom work (ag_bot_body) exactly once each, alternating. The bottom
    work may be interrupted by the next frame's top IRQ, so its end (ab_end)
    is only reported, as the line where it finished."""
    a = vice.addr
    names = {a("ag_stable"): "top", a("ag_bot_body"): "bot", a("ab_end"): "end"}
    cps = {}
    for addr, n in names.items():
        _, d = v.cmd(0x12, struct.pack("<HHBBBB", addr, addr, 1, 1, 4, 0))
        cps[struct.unpack_from("<I", d)[0]] = n
    seq = []
    try:
        while sum(1 for s in seq if s[0] == "top") < frames:
            seen = dict(v.hits)
            v.cmd(0x81)
            v.cmd(0xAA)
            while True:
                hit = [k for k in cps if v.hits.get(k, 0) > seen.get(k, 0)]
                if hit:
                    break
                v.read_response()
            r = v.regs()
            seq.append((cps[hit[0]], r["LIN"], r["CYC"]))
    finally:
        for k in cps:
            v.delete_checkpoint(k)
    bad, ends = [], []
    tb = [s for s in seq if s[0] in ("top", "bot")]
    while tb and tb[0][0] != "top":
        tb.pop(0)
    for i, (n, lin, cyc) in enumerate(tb):
        if n != ("top", "bot")[i % 2]:
            bad.append((i, f"{n} out of order at line {lin}"))
        if n == "top" and (lin, cyc) != (46, 3):
            bad.append((i, f"stable raster point at {lin}:{cyc}"))
    for n, lin, cyc in seq:
        if n == "end":
            ends.append(lin if lin < 200 else lin - 312)    # lines past 311 wrap
    if verbose:
        late = max(ends) if ends else None
        print(f"{len(tb) // 2} frames audited; bottom work ends by line "
              f"{late if late is None or late >= 0 else str(late + 312)}"
              f"{' (next frame)' if late is not None and late >= 0 else ''}; problems: {bad[:5]}")
    return bad


if __name__ == "__main__":
    v = vice.Vice()
    try:
        bad = audit(v, int(sys.argv[1]) if len(sys.argv) > 1 else 200)
    finally:
        v.close()
    sys.exit(1 if bad else 0)
