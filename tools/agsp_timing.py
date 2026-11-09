#!/usr/bin/env python3
"""Sample LIN/CYC at labels in the AGSP raster code over several frames.
Usage: VICE_SYMS=build/agsp.vs tools/agsp_timing.py LABEL [N]"""
import struct, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vice

label = sys.argv[1]
n = int(sys.argv[2]) if len(sys.argv) > 2 else 12
v = vice.Vice()
a = vice.addr(label)
_, d = v.cmd(0x12, struct.pack("<HHBBBB", a, a, 1, 1, 4, 0))
num = struct.unpack_from("<I", d)[0]
seen = []
for _ in range(n):
    if not v.run_until_hit(num, 5):
        print("timeout"); break
    r = v.regs()
    seen.append((r["LIN"], r["CYC"]))
v.delete_checkpoint(num)
v.close()
print(label, f"${a:04x}", " ".join(f"{l}:{c}" for l, c in seen))
