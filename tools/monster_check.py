#!/usr/bin/env python3
"""Closed-loop gameplay checks for the monsters (VICE must be running the game).

  behaviour: each type, observed for a while near its spawn point
  sword:     every type dies after its hit points' worth of sword hits
  contact:   touching a monster knocks the player back (hurt timer, border)
  wizard:    no sword at first; touching the old wizard shows his message,
             J continues, the player has the sword and the wizard is gone
  victory:   touching the princess shows the title picture again
             (VIC bank 2, bitmap mode)

Usage: tools/monster_check.py [wizard|behaviour|sword|contact|victory|all]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vice
import game_check as g

BLOB, SKEL, GHOST, CYCL, JELLY, WIZ, PRIN = 4, 6, 8, 10, 12, 14, 16
NAMES = {BLOB: "blob", SKEL: "skeleton", GHOST: "ghost", CYCL: "cyclops",
         JELLY: "jelly", WIZ: "wizard", PRIN: "princess"}
HP = {BLOB: 1, SKEL: 2, GHOST: 1, CYCL: 3, JELLY: 2}
F = {"pointer": 4, "controller": 5, "gxlo": 9, "gxhi": 10, "gylo": 11, "gyhi": 12,
     "state": 21, "timer": 22, "hp": 23, "spawn": 24, "flash": 25, "dir": 26}


class Game:
    def __init__(self, v):
        self.v = v
        a = vice.addr
        self.base = a("sprite_data_2")
        n = 0
        while vice.symbols().get("spawn_tx") is not None and n == 0:
            n = a("spawn_ty") - a("spawn_tx")
        self.n = n
        self.tx = v.mem_get(a("spawn_tx"), n)
        self.ty = v.mem_get(a("spawn_ty"), n)
        self.tp = v.mem_get(a("spawn_type"), n)
        self.map = v.mem_get(a("map"), 4096)
        self.tag = v.mem_get(a("tiletag"), 64)

    def walkable(self, cx, cy):
        """is the tile under char position (cx, cy) walkable?"""
        if not (0 <= cx < 256 and 0 <= cy < 256):
            return False
        return self.tag[self.map[(cy // 4) * 64 + cx // 4]] != 0xFF

    def frame(self, k=1):
        for _ in range(k):
            g.bottom_irq(self.v)

    def sprites(self):
        n = self.v.mem_get(vice.addr("sprite2_count"), 1)[0]
        t = self.v.mem_get(self.base, 32 * 27)
        out = []
        for i in range(n):
            s = {k: t[32 * f + i] for k, f in F.items()}
            s["i"] = i
            s["x"] = s["gxlo"] | s["gxhi"] << 8
            s["y"] = s["gylo"] | s["gyhi"] << 8
            out.append(s)
        return out

    def put(self, i, x, y):
        x, y = min(max(x, 0), 0xFFFF), min(max(y, 0), 0xFFFF)
        for f, val in (("gxlo", x & 255), ("gxhi", x >> 8), ("gylo", y & 255), ("gyhi", y >> 8)):
            self.v.mem_set(self.base + 32 * F[f] + i, [val])

    def spawn_state(self, k):
        return self.v.mem_get(vice.addr("spawn_state") + k, 1)[0]

    def go_near(self, typ, which=0, dx=12):
        """teleport the player next to the which-th spawn point of a type and
        wait until its monster is active; returns (spawn index, sprite)"""
        ks = [k for k in range(self.n) if self.tp[k] == typ and self.spawn_state(k) != 2]
        k = ks[which]
        cx, cy = self.tx[k] * 4 + 1, self.ty[k] * 4 + 1
        for d in (dx, -dx, dx // 2, -dx // 2, dx + 4, -dx - 4):    # stand on open ground
            if self.walkable(cx + d + 1, cy + 1):
                dx = d
                break
        self.put(0, (cx + dx) * 256, cy * 256)
        for _ in range(60):
            self.frame()
            s = [s for s in self.sprites() if s["spawn"] == k and s["controller"] == typ and s["i"] >= 2]
            if s and self.spawn_state(k) == 1:
                return k, s[0]
        raise RuntimeError(f"{NAMES[typ]} at spawn {k} did not appear")

    def find(self, k):
        for s in self.sprites():
            if s["i"] >= 2 and s["spawn"] == k:
                return s
        return None


def behaviour(gm):
    ok = True
    # blob: rolls horizontally only, through its rotation frames
    k, s = gm.go_near(BLOB, 1)
    ys, xs, frames = set(), set(), set()
    for _ in range(120):
        gm.frame()
        s = gm.find(k)
        if s:
            ys.add(s["y"]); xs.add(s["x"]); frames.add(s["pointer"] - 128)
    r = len(ys) == 1 and len(xs) > 20 and frames <= {49, 50, 51, 52} and len(frames) >= 3
    print(("ok   " if r else "FAIL ") + f"blob rolls sideways only: {len(xs)} x positions, "
          f"{len(ys)} y, frames {sorted(frames)}")
    ok &= r
    # ghost: closes in on the player, eyes in 4 frames 79..82
    k, s = gm.go_near(GHOST, 0, dx=16)
    p = gm.sprites()[0]
    d0 = abs(s["x"] - p["x"]) + abs(s["y"] - p["y"])
    gm.frame(60)
    s, p = gm.find(k), gm.sprites()[0]
    d1 = abs(s["x"] - p["x"]) + abs(s["y"] - p["y"]) if s else 0
    r = s is not None and d1 < d0 and 79 <= s["pointer"] - 128 <= 82
    print(("ok   " if r else "FAIL ") + f"ghost drifts towards the player: distance {d0 // 32} -> {d1 // 32} px")
    ok &= r
    # skeleton: walks, several directions over time
    k, s = gm.go_near(SKEL, 0, dx=20)
    dirs, pos = set(), set()
    for _ in range(300):
        gm.frame()
        s = gm.find(k)
        if s:
            dirs.add(s["dir"]); pos.add((s["x"], s["y"]))
    r = len(dirs) >= 2 and len(pos) > 50
    print(("ok   " if r else "FAIL ") + f"skeleton wanders: {len(dirs)} directions, {len(pos)} positions")
    ok &= r
    # cyclops: line up with it horizontally -> it charges fast
    k, s = gm.go_near(CYCL, 0, dx=10)
    gm.put(0, s["x"] + 10 * 8 * 32, s["y"])
    speeds = []
    for _ in range(40):
        a = gm.find(k)
        gm.frame()
        b = gm.find(k)
        if a and b:
            speeds.append(abs(b["x"] - a["x"]) + abs(b["y"] - a["y"]))
    r = max(speeds or [0]) >= 64
    print(("ok   " if r else "FAIL ") + f"cyclops charges when lined up: top speed {max(speeds or [0]) / 32:.2f} px/frame")
    ok &= r
    # jelly: sinks (disc, intangible) and resurfaces somewhere else
    k, s = gm.go_near(JELLY, 0, dx=8)
    sunk, jumped, last = False, False, (s["x"], s["y"])
    for _ in range(400):
        gm.frame()
        s = gm.find(k)
        if not s:
            continue
        sunk |= s["pointer"] - 128 == 77 and s["state"] & 0x80 != 0
        jumped |= abs(s["x"] - last[0]) > 256 or abs(s["y"] - last[1]) > 256
        last = (s["x"], s["y"])
    r = sunk and jumped
    print(("ok   " if r else "FAIL ") + f"jelly sinks and resurfaces elsewhere: sunk={sunk} moved={jumped}")
    ok &= r
    return ok


def wizard(gm):
    a = vice.addr
    ok = True
    gm.v.mem_set(a("has_sword"), [0])
    vice.set_keys(gm.v, ["J"])                              # no sword: J does nothing
    gm.frame(10)
    vice.set_keys(gm.v, [])
    anim = gm.v.mem_get(gm.base + 32 * 6 + 1, 1)[0]         # sword sprite's animation
    r = anim == 0
    print(("ok   " if r else "FAIL ") + "without the sword, J does not strike")
    ok &= r
    k, s = gm.go_near(WIZ, 0, dx=10)
    gm.put(0, s["x"] + 6 * 32, s["y"])                      # walk up to him
    shown = False
    for _ in range(10):
        try:
            gm.frame()
        except RuntimeError:                                # the game loop is paused
            shown = gm.v.mem_get(0xD018, 1)[0] & 0xFE == 0x24
            break
    vice.do_shot(gm.v, os.path.join(vice.ROOT, "screenshots", "wizard_message.png"))
    text = gm.v.mem_get(0x0800 + 14 * 40, 40)
    r = shown and bytes([9, 20, 39, 19]) in text            # "IT'S"
    print(("ok   " if r else "FAIL ") + f"touching the wizard shows his message (text screen: {shown})")
    ok &= r
    vice.set_keys(gm.v, ["J"])
    gm.v.resume(); import time; time.sleep(0.3)
    vice.set_keys(gm.v, [])
    gm.frame(30)
    has = gm.v.mem_get(a("has_sword"), 1)[0]
    gone = gm.find(k) is None and gm.spawn_state(k) == 2
    r = has == 1 and gone
    print(("ok   " if r else "FAIL ") + f"after J: player has the sword ({has}), wizard gone ({gone})")
    ok &= r
    return ok


def sword(gm):
    """hold the sword out against each type until it dies"""
    ok = True
    gm.v.mem_set(vice.addr("has_sword"), [1])
    gm.v.mem_set(vice.addr("player_dir_nz"), [3])          # facing east
    for typ in (BLOB, SKEL, GHOST, CYCL, JELLY):
        k, s = gm.go_near(typ, 0, dx=8)
        hits, frames = 0, 0
        vice.set_keys(gm.v, ["J"])
        last_hp = s["hp"]
        while frames < 400 and gm.spawn_state(k) != 2:
            s = gm.find(k)
            if s:
                if s["hp"] < last_hp:
                    hits += 1
                last_hp = s["hp"]
                # keep the sword's tip on it: the sword is ~24 px right of the player
                gm.put(0, s["x"] - 22 * 32, s["y"] - 2 * 32)
            gm.frame()
            frames += 1
        vice.set_keys(gm.v, [])
        gm.frame(20)
        dead = gm.spawn_state(k) == 2 and gm.find(k) is None
        r = dead and hits + 1 == HP[typ]
        print(("ok   " if r else "FAIL ") + f"{NAMES[typ]} dies after {HP[typ]} sword hit(s): "
              f"dead={dead} after {frames} frames")
        ok &= r
    return ok


def contact(gm):
    k, s = gm.go_near(SKEL, 1, dx=6)
    gm.v.mem_set(vice.addr("player_hurt"), [0])
    before = None
    for _ in range(80):
        s = gm.find(k)
        if not s:
            gm.frame(); continue
        if gm.v.mem_get(vice.addr("player_hurt"), 1)[0]:
            break
        gm.put(0, s["x"] + 4 * 32, s["y"])                  # walk into it from the right
        before = s["x"] + 4 * 32
        gm.frame()
    hurt = gm.v.mem_get(vice.addr("player_hurt"), 1)[0]
    gm.frame(1)
    border = gm.v.mem_get(0xD020, 1)[0] & 15
    gm.frame(9)
    p = gm.sprites()[0]
    r = hurt > 0 and border == 2 and p["x"] > before
    print(("ok   " if r else "FAIL ") + f"touching a monster: hurt timer {hurt}, border colour {border}, "
          f"pushed {(p['x'] - before) // 32} px away")
    return r


def victory(gm):
    kp, p = gm.go_near(PRIN, 0, dx=6)
    gm.put(0, p["x"], p["y"])
    try:
        gm.frame(5)
    except RuntimeError:
        pass                                                # the game loop has stopped
    regs = gm.v.mem_get(0xD011, 1)[0], gm.v.mem_get(0xDD00, 1)[0] & 3
    r = regs[0] & 0x20 and regs[1] == 1
    vice.do_shot(gm.v, os.path.join(vice.ROOT, "screenshots", "victory.png"))
    print(("ok   " if r else "FAIL ") + f"princess reached -> title picture "
          f"($d011=${regs[0]:02x}, VIC bank {3 - regs[1]})")
    return r


def main(argv):
    what = argv[0] if argv else "all"
    v = vice.Vice()
    try:
        gm = Game(v)
        ok = True
        for name, fn in (("wizard", wizard), ("behaviour", behaviour), ("sword", sword),
                         ("contact", contact), ("victory", victory)):
            if what in (name, "all"):
                ok &= fn(gm)
    finally:
        v.close()
    print("PASS" if ok else "FAILED")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main(sys.argv[1:])
