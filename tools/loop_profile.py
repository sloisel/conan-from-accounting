#!/usr/bin/env python3
"""Where does a game update go? Stops after every subroutine call of the main
loop (`forever`) and reads the raster position: cycles per routine (IRQ time
spent meanwhile included), averaged over N updates.
Usage: tools/loop_profile.py [UPDATES]       (VICE running the game)
       tools/loop_profile.py exact [UPDATES]  each routine alone, interrupts masked
       tools/loop_profile.py routine NAME...  exact cost of calls of subroutines"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vice

FRAME = 312 * 63


def calls(v):
    """(return address, routine name) of each jsr in the main loop"""
    a = vice.addr("forever")
    code = v.mem_get(a, 80)
    names = {addr: n for n, addr in vice.symbols().items()}
    out, i = [], 0
    while code[i] == 0x20:
        target = code[i + 1] | code[i + 2] << 8
        out.append((a + i + 3, names.get(target, hex(target))))
        i += 3
    return out


def profile(v, updates=50):
    cs = calls(v)
    cps = {}
    for ret, name in [(vice.addr("forever"), "start")] + cs:
        _, d = v.cmd(0x12, struct.pack("<HHBBBB", ret, ret, 1, 1, 4, 0))
        cps[struct.unpack_from("<I", d)[0]] = name
    order = ["start"] + [n for _, n in cs]
    tot = {n: 0 for n in order}
    last, done = None, 0
    try:
        while done < updates:
            seen = dict(v.hits)
            v.cmd(0x81)
            v.cmd(0xAA)
            while True:
                hit = [k for k in cps if v.hits.get(k, 0) > seen.get(k, 0)]
                if hit:
                    break
                v.read_response()
            r = v.regs()
            t = r["LIN"] * 63 + r["CYC"]
            name = cps[hit[0]]
            if last is not None and name != "start":
                tot[name] += (t - last) % FRAME
            if name == order[-1]:
                done += 1
            last = t
    finally:
        for k in cps:
            v.delete_checkpoint(k)
    return {n: tot[n] / updates for n in order[1:]}


def rearm(v):
    """after interrupts were masked for a while: restart the raster IRQ
    chain at the bottom IRQ (which schedules the rest)"""
    a = vice.addr("ag_irq_bot")
    v.mem_set(0xFFFE, [a & 255, a >> 8])
    d011 = v.mem_get(0xD011, 1)[0]
    v.mem_set(0xD011, [d011 & 0x7F])
    v.mem_set(0xD012, [246])
    v.mem_set(0xD019, [0x0F])


def isolated(v, updates=20):
    """exact cycles of each main-loop routine: each call runs with interrupts
    masked (the frame it lands in may glitch; tests only)"""
    cs = calls(v)
    starts = {}
    a = vice.addr("forever")
    prev = a
    for ret, name in cs:
        starts[prev] = (ret, name)
        prev = ret
    tot = {name: [] for _, name in cs if name != "ag_commit_frame"}
    for _ in range(updates):
        for start, (ret, name) in starts.items():
            if name == "ag_commit_frame":           # waits for the IRQ
                continue
            num = v.checkpoint(start)
            v.run_until_hit(num, 10)
            v.delete_checkpoint(num)
            r = v.regs()
            fl = r["FL"]
            v.set_reg("FL", fl | 4)
            t0 = r["LIN"] * 63 + r["CYC"]
            num = v.checkpoint(ret)
            v.run_until_hit(num, 10)
            v.delete_checkpoint(num)
            r = v.regs()
            tot[name].append((r["LIN"] * 63 + r["CYC"] - t0) % FRAME)
            rearm(v)
            v.set_reg("FL", (r["FL"] & ~4) | (fl & 4))
    return tot


def routine_cost(v, name, n=20):
    """exact cycles of `n` calls of a subroutine (entry to its rts, through
    the return address on the stack), interrupts masked: list of (cycles, X)"""
    entry = int(name[1:], 16) if name.startswith("$") else vice.addr(name)
    out = []
    for _ in range(n):
        num = v.checkpoint(entry)
        if not v.run_until_hit(num, 10):
            v.delete_checkpoint(num)
            break
        v.delete_checkpoint(num)
        r = v.regs()
        sp = r["SP"]
        lo, hi = v.mem_get(0x100 + ((sp + 1) & 255), 1)[0], v.mem_get(0x100 + ((sp + 2) & 255), 1)[0]
        ret = (lo | hi << 8) + 1
        fl = r["FL"]
        v.set_reg("FL", fl | 4)
        t0 = r["LIN"] * 63 + r["CYC"]
        num = v.checkpoint(ret)
        v.run_until_hit(num, 10)
        v.delete_checkpoint(num)
        r2 = v.regs()
        out.append(((r2["LIN"] * 63 + r2["CYC"] - t0) % FRAME, r["X"]))
        rearm(v)
        v.set_reg("FL", (r2["FL"] & ~4) | (fl & 4))
    return out


def main(argv):
    v = vice.Vice()
    try:
        if argv and argv[0] == "routine":
            for name in argv[1:]:
                c = [x for x, _ in routine_cost(v, name, 30)] or [0]
                print(f"{name:20s} min {min(c):6d}  max {max(c):6d}  mean {sum(c) / len(c):7.0f}")
            return
        if argv and argv[0] == "exact":
            res = {n: max(c) for n, c in isolated(v, int(argv[1]) if len(argv) > 1 else 20).items()}
            print("(exact, interrupts masked; worst of the updates)")
        else:
            res = profile(v, int(argv[0]) if argv else 50)
    finally:
        v.close()
    for n, c in res.items():
        print(f"{n:20s} {c:8.0f} cycles  {100 * c / FRAME:5.1f}% of a frame")
    print(f"{'total':20s} {sum(res.values()):8.0f}")


if __name__ == "__main__":
    main(sys.argv[1:])
