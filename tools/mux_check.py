#!/usr/bin/env python3
"""Sprite multiplexer checks (mymux.s).

frozen(v): monsters frozen, placed by the test: rows, rows of 7, rewrites
  while many other sprites show (their DMA slows the CPU), 8..10 on one line,
  and random layouts of 14 monsters. Every frame must be pixel-exact against
  the plan, and the plan must be exactly what model() (the planner's rules,
  in Python) gives: rewrites only once the old sprite is done, at most one at
  a time, clear of pointer-row switches, done before the new sprite starts.
live(v): a dozen monsters spawned around the player, behaving normally: the
  display stays pixel-exact, the raster IRQ chain stays intact, and the main
  loop keeps 50 Hz (spare CPU reported).

Usage: tools/mux_check.py [frozen|live]      (VICE running the game)"""
import os
import random
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vice
import game_check as g
import irq_audit

FIELDS = 27
COST, LEAD, DMA_N, SWLEAD = 3, 3, 4, 7   # mymux.s MX_COST, MX_LEAD, MX_DMA_N, MX_SWLEAD
NEAR_SWITCH = []                  # layouts with a rewrite next to a pointer-row switch
TIMING_DROPS = []                 # layouts where timing (not crowding) left a sprite out
PAL_FRAME = 312 * 63
# (controller, first frame) of the monster types: blob, skeleton, ghost, cyclops, jelly
KINDS = [(4, 49), (6, 53), (8, 79), (10, 65), (12, 73)]


def table(v):
    return v.mem_get(vice.addr("sprite_data_2"), 32 * FIELDS)


def visible(v):
    """screen y of the logical sprites the plan should show"""
    n = v.mem_get(vice.addr("sprite2_count"), 1)[0]
    t = table(v)
    return [t[64 + i] for i in range(n)
            if t[32 * 17 + i] == 0 and 0 < t[64 + i] <= g.BOTTOM]


def crowd(ys):
    """the most sprite spans [y, y + 25) over any one raster line"""
    return max((sum(1 for y in ys if y <= line < y + 25) for line in range(256)), default=0)


def model(ys, sw, cost, lead):
    """mux_plan's assignment (mymux.s) for sprites at screen y `ys` (in
    table order) and pointer-row switch badlines `sw`: (planned, dropped)"""
    order = sorted(range(len(ys)), key=lambda i: ys[i])      # stable, like the 6502 sort
    end = [0] * 8
    busy = planned = dropped = 0
    for i in order:
        y = ys[i]
        if planned < 8:
            slot = planned
        else:
            slot = planned % 8                              # frees up first (FIFO)
            e = end[slot]
            if e >= 250:
                dropped += 1
                continue
            s = max(e + 1, busy)
            for b in (sw[0], sw[1], sw[0]):
                if b and b - SWLEAD <= s <= b:
                    s = b + 1
            if s + lead > y:
                dropped += 1
                continue
            busy = min(s + cost + (sum(x >= s for x in end) >= DMA_N), 255)
        end[slot] = min(y + 21, 255)
        planned += 1
        if planned == 16:
            break
    return planned, dropped


def event_times(v):
    """raster line:cycle of the dispatcher's work during the next frame"""
    a = vice.addr
    g.bottom_irq(v)
    names = {}
    for nm in ("ag_irq_evt", "an_wdone", "ae_wdone", "ag_do_swap", "ds_done", "ag_bot_body",
               "ag_stable", "an_irq"):
        ad = a(nm)
        _, d = v.cmd(0x12, struct.pack("<HHBBBB", ad, ad, 1, 1, 4, 0))
        names[struct.unpack_from("<I", d)[0]] = nm
    out = []
    try:
        while len(out) < 60:
            seen = dict(v.hits)
            v.cmd(0x81)
            v.cmd(0xAA)
            while True:
                hit = [k for k in names if v.hits.get(k, 0) > seen.get(k, 0)]
                if hit:
                    break
                v.read_response()
            nm = names[hit[0]]
            if nm == "ag_bot_body":
                break
            r = v.regs()
            out.append(f"{nm}@{r['LIN']}:{r['CYC']}" + (f"/A{r['A']}" if nm == "an_irq" else ""))
    finally:
        for k in names:
            v.delete_checkpoint(k)
    return out


def settle(v, k=3):
    for _ in range(k):
        state = g.bottom_irq(v)
    return state


def check(v, ref, label, fails, verbose):
    """the frame shown and the plan just built (logical table = back plan)"""
    done = 0
    for _ in range(30):                  # two complete updates of the main loop
        state = g.bottom_irq(v)          # (the first may have begun before the
        done += g.bottom_irq.main_done   #  sprites were placed: a redraw is slow)
        if done >= 2 and g.bottom_irq.main_done:
            break
    _, bad, band = g.check_frame(v, ref, state)
    ys = visible(v)
    a = vice.addr
    back = v.mem_get(a("mx_back"), 1)[0]
    planned = v.mem_get(a("mx_n") + back, 1)[0]
    dropped = v.mem_get(a("mx_dropped"), 1)[0]
    need = crowd(ys)
    sw = tuple(v.mem_get(a("mx_sw1"), 2))
    want = model(ys, sw, COST, LEAD)
    ok = not bad and not band and (planned, dropped) == want
    if dropped and need <= 8:
        TIMING_DROPS.append(label)
    lines = v.mem_get(a("mx_line") + 16 * back, max(planned, 1))[:planned]
    if any(b and b - 8 <= ln <= b + 3 for ln in lines[8:] for b in sw):
        NEAR_SWITCH.append(label)
    if not ok:
        fails.append(label)
        if verbose and len(fails) <= 5:
            print(f"{label}: {len(bad)} wrong pixels {bad[:2]}, {len(ys)} on screen, "
                  f"planned {planned}, dropped {dropped} (model {want}), crowd {need}, sw {sw}, "
                  f"main done {g.bottom_irq.main_done}")
            if bad:
                spr = state[1].spr
                print(f"   wrong lines {sorted(set(b[0] for b in bad))}; switch {list(state[3])}, "
                      f"fine/xs/cx/cy {state[0]}")
                print(f"   shown (slot, x, y, lidx): {[(e[0], e[1], e[2], e[5]) for e in spr]}")
                fr = v.mem_get(a("mx_front"), 1)[0]
                n = v.mem_get(a("mx_n") + fr, 1)[0]
                print(f"   front plan lines {list(v.mem_get(a('mx_line') + 16 * fr, n))} "
                      f"y {list(v.mem_get(a('mx_y') + 16 * fr, n))} "
                      f"slot {list(v.mem_get(a('mx_slot') + 16 * fr, n))}")
                vice.do_shot(v, os.path.join(vice.ROOT, "screenshots", "mux_fail.png"))
                print("   next frame's events:", event_times(v))
                fine, xs, cx, cy = state[0]
                print("   ring/mirror vs map:", g.ring_diff(v, ref, cx, cy)[:10])
    return len(ys), planned, dropped, need


def setup(v):
    """freeze the monsters, make 14 of them; returns place(spots): put them
    at screen positions (the rest off screen)"""
    a = vice.addr
    base = a("sprite_data_2")
    v.mem_set(a("debug_freeze_enemies"), [1])
    v.mem_set(a("has_sword"), [0])
    sp0 = 0x2000 // 64
    for i in range(2, 16):                                  # 14 monsters
        c, f0 = KINDS[i % len(KINDS)]
        for field, val in ((5, c), (6, 0), (7, 1), (8, 255), (4, sp0 + f0), (3, 2 + i % 13),
                           (17, 0), (19, 0), (21, 0), (23, 1), (24, 0), (25, 0)):
            v.mem_set(base + 32 * field + i, [val])
    v.mem_set(a("sprite2_count"), [16])
    settle(v, 10)
    t = table(v)
    pgx, pgy = t[32 * 9] | t[32 * 10] << 8, t[32 * 11] | t[32 * 12] << 8
    psx, psy = t[0] | t[32] << 8, t[64]

    def place(spots, off=(0, 0)):
        """screen (x, y) for monsters 2.., the rest parked far away; the
        player (and so the camera) moved by `off` pixels, monsters with it"""
        ox, oy = off[0] * 32, off[1] * 32
        for off_, val in ((9, (pgx + ox) & 255), (10, (pgx + ox) >> 8 & 255),
                          (11, (pgy + oy) & 255), (12, (pgy + oy) >> 8 & 255)):
            v.mem_set(base + 32 * off_, [val])
        for i in range(2, 16):
            if i - 2 < len(spots):
                x, y = spots[i - 2]
                gx, gy = pgx + ox + (x - psx) * 32, pgy + oy + (y - psy) * 32
            else:
                gx, gy = pgx + 300 * 32, pgy                # off screen, right
            for off, val in ((9, gx & 255), (10, gx >> 8 & 255), (11, gy & 255), (12, gy >> 8 & 255)):
                v.mem_set(base + 32 * off + i, [val])
    return place


def frozen(v, verbose=True):
    """returns (failures, layouts checked, most sprites shown in one frame)"""
    a = vice.addr
    place = setup(v)
    ref = g.Ref(v)
    fails, layouts, most = [], 0, 0
    for gap in (21, 23, 25, 26, 30):                        # rows of 3 (the player too)
        spots = [(40 + 44 * c, 84 + gap * r) for r in range(5) for c in range(3)][:14]
        spots = [(x, y) for x, y in spots if y <= 225]
        place(spots)
        n, planned, dropped, need = check(v, ref, f"rows, gap {gap}", fails, verbose)
        layouts += 1
        most = max(most, planned)
    for gap in range(22, 40, 2):                            # rows of 7: chained rewrites
        place([(30 + 38 * c, 90 + r * gap) for r in range(2) for c in range(7)])
        check(v, ref, f"rows of 7, gap {gap}", fails, verbose)
        layouts += 1
    for c in (4, 6):                                        # rewrites while 4+ others show
        for d in range(8):
            y0 = 90 + d
            place([(30 + 34 * i, y0) for i in range(4)] + [(30 + 34 * i, y0 + 10) for i in range(4)]
                  + [(40 + 34 * i, y0 + 25 + 2 * i) for i in range(c)])
            check(v, ref, f"busy DMA, {c} rewrites, +{d}", fails, verbose)
            layouts += 1
    for k in (8, 9, 10):                                    # k on one line
        place([(30 + 30 * c, 150 + c % 3) for c in range(k)])
        _, _, dropped, _ = check(v, ref, f"{k} on one line", fails, verbose)
        layouts += 1
    rnd = random.Random(7)
    for r in range(40):                                     # random crowds
        place([(rnd.randrange(24, 320), rnd.randrange(82, 226)) for _ in range(14)])
        _, planned, _, _ = check(v, ref, f"random layout {r}", fails, verbose)
        layouts += 1
        most = max(most, planned)
    switched = 0
    for f in range(64):                                     # a row of 7 across the pointer
        off = (0, -48 - f)                                  # row's badline: their DMA
        place([(30 + 38 * c, 150) for c in range(7)], off)  # slows the switch's IRQ
        settle(v, 6)                                        # (upwards: the camera is
        b = v.mem_get(a("mx_sw1"), 1)[0]                    #  free there at any start)
        if not 100 <= b <= 220:
            continue
        place([(30 + 38 * c, b - 4 - f % 8) for c in range(7)], off)
        check(v, ref, f"row of 7 over the switch at {b}, {f}", fails, verbose)
        layouts += 1
        switched += 1
    for f in range(64):                                     # scrolling: the pointer-row
        if f % 8 == 0:                                      # switches move every frame
            spots = [(rnd.randrange(24, 320), rnd.randrange(82, 226)) for _ in range(14)]
        place(spots, (3 * f, -2 * f))
        _, planned, _, _ = check(v, ref, f"scrolling crowd {f}", fails, verbose)
        layouts += 1
        most = max(most, planned)
    v.mem_set(a("debug_freeze_enemies"), [0])
    if switched < 20:
        fails.append(f"only {switched} rows over a pointer-row switch")
    return fails, layouts, most


def live(v, verbose=True):
    """a dozen monsters around the player, behaving normally"""
    a = vice.addr
    n = a("spawn_ty") - a("spawn_tx")
    tx, ty = a("spawn_tx"), a("spawn_ty")
    tp = v.mem_get(a("spawn_type"), n)
    st = v.mem_get(a("spawn_state"), n)
    mp = v.mem_get(a("map"), 4096)
    tag = v.mem_get(a("tiletag"), 64)
    t = table(v)
    ptx, pty = (t[32 * 10]) // 4, (t[32 * 12]) // 4             # player's tile
    walk = lambda x, y: 0 <= x < 64 and 0 <= y < 64 and tag[mp[y * 64 + x]] != 0xFF
    tiles = [(ptx + dx, pty + dy) for dy in (-2, -1, 1, 2) for dx in range(-4, 5)
             if walk(ptx + dx, pty + dy)]
    random.Random(3).shuffle(tiles)
    picks = [k for k in range(n) if tp[k] in (4, 6, 8, 10, 12) and st[k] == 0][:12]
    for k, (x, y) in zip(picks, tiles):
        v.mem_set(tx + k, [x])
        v.mem_set(ty + k, [y])
        v.mem_set(a("spawn_cx") + k, [x * 4 + 2])      # (what spawn_update reads)
        v.mem_set(a("spawn_cy") + k, [y * 4 + 2])
    v.mem_set(a("spawn_grace"), [40])
    settle(v, 45)
    shown = []
    ref = g.Ref(v)
    bad_frames = 0
    for _ in range(100):
        state = g.bottom_irq(v)
        _, bad, band = g.check_frame(v, ref, state)
        shown.append(len(state[1].spr))
        if bad or band:
            bad_frames += 1
            if verbose and bad_frames <= 3:
                print(f"live: {len(bad)} wrong pixels {bad[:2]}")
    irq = irq_audit.audit(v, 100, verbose=False)
    cps = {}
    for name in ("forever", "ag_idle"):
        ad = a(name)
        _, d = v.cmd(0x12, struct.pack("<HHBBBB", ad, ad, 0, 1, 4, 0))
        cps[name] = struct.unpack_from("<I", d)[0]
    frames = 200
    v.frames(frames)
    hits = {}
    for name, num in cps.items():
        _, d = v.cmd(0x11, struct.pack("<I", num))
        hits[name] = struct.unpack_from("<I", d, 13)[0]
        v.delete_checkpoint(num)
    updates = hits["forever"] / frames
    spare = 100 * hits["ag_idle"] * 7 / frames / PAL_FRAME
    return bad_frames, irq, min(shown), max(shown), updates, spare


def main(argv):
    what = argv[0] if argv else "frozen"
    v = vice.Vice()
    try:
        if what == "frozen":
            fails, layouts, most = frozen(v)
            print(f"{layouts} layouts, up to {most} sprites in one frame, {len(fails)} bad; "
                  f"{len(NEAR_SWITCH)} with a rewrite next to a pointer-row switch; "
                  f"{len(TIMING_DROPS)} left a sprite out for timing (not crowding)")
        else:
            bad, irq, lo, hi, upd, spare = live(v)
            print(f"live: {lo}..{hi} sprites shown, {bad} bad frames, IRQ problems {irq[:2]}, "
                  f"{upd:.2f} updates/frame, {spare:.0f}% CPU spare")
    finally:
        v.close()


if __name__ == "__main__":
    main(sys.argv[1:])
