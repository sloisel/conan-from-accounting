#!/usr/bin/env python3
"""Where does the frame go? Counts, over N frames (exact, emulated time):
  - game updates (passes through `forever`) per frame,
  - spare CPU cycles: iterations of the 7-cycle idle loop `ag_idle`.
Usage: tools/profile.py [FRAMES] [KEY...]     e.g. tools/profile.py 200 D S"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vice

PAL_FRAME = 312 * 63


def hits(v, num):
    _, d = v.cmd(0x11, struct.pack("<I", num))
    return struct.unpack_from("<I", d, 13)[0]


def main(argv):
    frames = int(argv[0]) if argv else 200
    v = vice.Vice()
    vice.set_keys(v, argv[1:])
    v.frames(10)                                  # let movement settle
    cps = {}
    for name in ("forever", "ag_idle"):
        a = vice.addr(name)
        _, d = v.cmd(0x12, struct.pack("<HHBBBB", a, a, 0, 1, 4, 0))   # count only
        cps[name] = struct.unpack_from("<I", d)[0]
    v.frames(frames)
    n = {name: hits(v, num) for name, num in cps.items()}
    for num in cps.values():
        v.delete_checkpoint(num)
    vice.set_keys(v, [])
    v.close()
    idle = n["ag_idle"] * 7 / frames
    print(f"keys {' '.join(argv[1:]) or '-'}: {n['forever'] / frames:.2f} game updates/frame, "
          f"spare {idle:.0f} cycles/frame = {100 * idle / PAL_FRAME:.0f}% of {PAL_FRAME}")


if __name__ == "__main__":
    main(sys.argv[1:])
