#!/usr/bin/env python3
"""Closed-loop gameplay checks for the monsters (VICE must be running the game).

  behaviour: each type, observed for a while near its spawn point
  sword:     every type dies after its hit points' worth of sword hits
  contact:   touching a monster knocks the player back (hurt timer, border)
  wizard:    no sword at first, it lies by the old wizard; touching him
             pauses the game with his message in a box under the play
             window, J continues: the player has the sword, the wizard and
             the sword on the ground are gone
  gates:     the locked gates open with their keys; the jail's starts
             the rescue, which ends on the title picture

  hitbox:    the sword hits exactly where the blade's pixels overlap a monster

Usage: tools/monster_check.py [wizard|behaviour|sword|hitbox|contact|health|items|strip|gates|all]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vice
import game_check as g

BLOB, SKEL, GHOST, CYCL, JELLY, WIZ, PRIN = 4, 6, 8, 10, 12, 14, 16
HEART, KEYR, KEYG, KEYB, SWORDI = 18, 20, 22, 24, 26
NAMES = {BLOB: "blob", SKEL: "skeleton", GHOST: "ghost", CYCL: "cyclops",
         JELLY: "jelly", WIZ: "wizard", PRIN: "princess", HEART: "heart",
         KEYR: "red key", KEYG: "green key", KEYB: "blue key", SWORDI: "sword"}
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
        v.mem_set(a("debug_no_death"), [1])       # (health: its own check)
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
        prin = [(self.tx[j], self.ty[j]) for j in range(self.n) if self.tp[j] == PRIN]
        far = lambda k: typ == PRIN or all(max(abs(self.tx[k] - x), abs(self.ty[k] - y)) > 8 for x, y in prin)
        ks = [k for k in range(self.n) if self.tp[k] == typ and self.spawn_state(k) != 2 and far(k)]
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
    track = []
    for _ in range(120):
        gm.frame()
        s = gm.find(k)
        if s:
            ys.add(s["y"]); xs.add(s["x"]); frames.add(s["pointer"] - 128)
            track.append((s["x"], s["pointer"] - 128))
    # frames 49..52 turn it counter-clockwise: rolling right steps them down
    good = bad = 0
    for (x0, f0), (x1, f1), (x2, _) in zip(track, track[1:], track[2:]):
        if f1 != f0 and x2 != x0:
            ccw = (f1 - f0) % 4 == 1
            good += ccw == (x2 < x0)
            bad += ccw != (x2 < x0)
    r = len(ys) == 1 and len(xs) > 20 and frames <= {49, 50, 51, 52} and len(frames) >= 3 \
        and good >= 3 and bad <= 1
    print(("ok   " if r else "FAIL ") + f"blob rolls sideways only, turning the way it rolls: "
          f"{len(xs)} x positions, {len(ys)} y, frames {sorted(frames)}, "
          f"{good} frame steps the right way, {bad} wrong")
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
    # skeleton: walks, several directions over time (a second one if the
    # first happens to keep one way, e.g. heading for the player)
    for which in range(2):
        k, s = gm.go_near(SKEL, which, dx=20)
        dirs, pos = set(), set()
        for _ in range(300):
            gm.frame()
            s = gm.find(k)
            if s:
                dirs.add(s["dir"]); pos.add((s["x"], s["y"]))
        r = len(dirs) >= 2 and len(pos) > 50
        if r:
            break
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
    for _ in range(40):                                     # the sword by him
        sw = [t for t in gm.sprites() if t["controller"] == SWORDI]
        if sw:
            break
        gm.frame()
    sy = gm.v.mem_get(gm.base + 64 + sw[0]["i"], 1)[0] if sw else 0
    r = bool(sw) and sy != 0 and abs(sw[0]["x"] - s["x"]) <= 40 * 32 and abs(sw[0]["y"] - s["y"]) <= 40 * 32
    print(("ok   " if r else "FAIL ") + f"the sword lies by the wizard, on screen ({bool(sw)}, y {sy})")
    ok &= r
    gm.put(0, s["x"] + 6 * 32, s["y"])                      # walk up to him
    on = 0
    for _ in range(10):
        gm.frame()                                          # (the display goes on)
        on = gm.v.mem_get(a("msg_on"), 1)[0]
        if on:
            break
    gm.frame(2)
    px = g.frame(gm.v)
    box = {px(line, x) for line in range(254, 275) for x in range(100, 268)}
    junk = {px(line, x) for line in range(254 + 17, 275) for x in range(100, 268)}   # below the text
    window = {px(line, x) for line in range(100, 200) for x in range(40, 320)}
    vice.do_shot(gm.v, os.path.join(vice.ROOT, "screenshots", "wizard_message.png"))
    arrow = []                                              # the arrow blinks
    for _ in range(4):
        gm.frame(9)
        q = g.frame(gm.v)
        arrow.append(1 in {q(line, x) for line in range(264, 272) for x in range(268, 284)})
    blinks = True in arrow and False in arrow
    r = on == 1 and 1 in box and len(window) > 2 and junk == {0} and blinks
    print(("ok   " if r else "FAIL ") + f"touching the wizard: the game pauses with his message in a box under "
          f"the play window (shown {on == 1}, white text {1 in box}, map still shown {len(window) > 2}, "
          f"clean below the text {junk == {0}}, arrow blinking {blinks})")
    ok &= r
    vice.set_keys(gm.v, ["J"])
    gm.frame(5)
    vice.set_keys(gm.v, [])
    gm.frame(30)
    has = gm.v.mem_get(a("has_sword"), 1)[0]
    gone = gm.find(k) is None and gm.spawn_state(k) == 2
    sword_gone = not any(t["controller"] == SWORDI for t in gm.sprites())
    off = gm.v.mem_get(a("msg_on"), 1)[0] == 0
    r = has == 1 and gone and sword_gone and off
    print(("ok   " if r else "FAIL ") + f"after J: box gone ({off}), player has the sword ({has}), wizard "
          f"gone ({gone}), sword off the ground ({sword_gone})")
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
        dying, harmless = 0, True                      # death animation, then gone
        for _ in range(60):
            s = gm.find(k)
            if s is None:
                break
            dying += 1
            harmless &= s["state"] & 0xC0 == 0xC0
            gm.frame()
        dead = gm.spawn_state(k) == 2 and gm.find(k) is None
        r = dead and hits + 1 == HP[typ] and 20 <= dying <= 40 and harmless   # (28 updates)
        print(("ok   " if r else "FAIL ") + f"{NAMES[typ]} dies after {HP[typ]} sword hit(s), "
              f"death animation {dying} frames (harmless: {harmless}), then gone: {dead}")
        ok &= r
    return ok


def hitbox(gm):
    """The sword hits exactly when the blade's pixel box overlaps the
    monster: for every direction, a cyclops held at the centre of the
    overlap is hit, one held 3 px outside it (on each side) is not."""
    import gen_hitbox
    spr = gen_hitbox.sprites()
    mx0, mx1, my0, my1 = gen_hitbox.bbox(spr, range(65, 73))
    a = vice.addr
    sx = [0, 0, 22, 24, 22, 0, -22, -24, -22]      # sword sprite offset per direction (px)
    sy = [0, 21, 19, 0, -19, -21, -19, 0, 19]
    gm.v.mem_set(a("has_sword"), [1])
    k, s = gm.go_near(CYCL, 1, dx=8)
    ok = True
    for d in range(1, 9):
        bx0, bx1, by0, by1 = gen_hitbox.bbox(spr, [40 + d])
        xr, yr = (bx0 - mx1, bx1 - mx0), (by0 - my1, by1 - my0)
        cases = [((sum(xr) // 2, sum(yr) // 2), True),
                 ((xr[0] - 3, sum(yr) // 2), False), ((xr[1] + 3, sum(yr) // 2), False),
                 ((sum(xr) // 2, yr[0] - 3), False), ((sum(xr) // 2, yr[1] + 3), False)]
        for (dx, dy), want in cases:
            gm.v.mem_set(a("player_dir_nz"), [d])
            hit, step_strike = False, 0
            settled, step = 0, 0
            while step < 80:
                # first let a camera jump (full redraw) settle with the sword away:
                # 3 frames in a row in which the main loop finished its update
                strike = settled >= 3
                if strike and step_strike >= 4:
                    break
                s = gm.find(k)
                gm.v.mem_set(gm.base + 32 * F["hp"] + s["i"], [3])
                gm.v.mem_set(gm.base + 32 * F["flash"] + s["i"], [0])
                gm.v.mem_set(a("player_hurt"), [20])        # no knockback during the test
                # monster - sword = (dx, dy)  ->  player = monster - (dx, dy) - sword offset
                gm.put(0, s["x"] - (dx + sx[d]) * 32, s["y"] - (dy + sy[d]) * 32)
                vice.set_keys(gm.v, ["J"] if strike else [])
                gm.frame()
                step += 1
                settled = settled + 1 if g.bottom_irq.main_done else 0
                s = gm.find(k)
                if strike:
                    step_strike += 1
                    hit |= s["flash"] > 0
            vice.set_keys(gm.v, [])
            gm.frame(3)
            if hit != want:
                ok = False
                print(f"FAIL dir {d} offset ({dx},{dy}): hit={hit}, expected {want}")
    print(("ok   " if ok else "FAIL ") + "sword hits exactly where the blade overlaps (8 directions, 5 offsets each)")
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


def health(gm):
    """three hearts: a touch costs one (and the strip shows it); the last one
    sends the player back to the start with full hearts"""
    v, a = gm.v, vice.addr
    v.mem_set(a("debug_no_death"), [0])
    v.mem_set(a("player_hp"), [3]); v.mem_set(a("player_hurt"), [0])
    v.mem_set(a("ui_col"), [0] * 6)                 # (ui_update must rewrite it)

    def touch():
        """walk into a skeleton until a heart is lost (or the player is sent
        back to the start, which also clears the hurt timer)"""
        k, s = gm.go_near(SKEL, 2, dx=6)
        v.mem_set(a("player_hurt"), [0])
        hp0 = v.mem_get(a("player_hp"), 1)[0]
        for _ in range(80):
            s = gm.find(k)
            if v.mem_get(a("player_hp"), 1)[0] != hp0 or v.mem_get(a("player_hurt"), 1)[0]:
                return True
            if s:
                gm.put(0, s["x"] + 4 * 32, s["y"])
            gm.frame()
        return False
    t = touch()
    gm.frame(2)
    hp = v.mem_get(a("player_hp"), 1)[0]
    col = list(v.mem_get(a("ui_col"), 3))
    r1 = t and hp == 2 and col == [2, 2, 11]
    v.mem_set(a("player_hp"), [1])
    t2 = touch()
    # the last heart: a turn on the spot, lying dead, then back at the start
    seen, frames, shot = [], 0, None
    for frames in range(200):
        gm.frame()
        ptr = gm.sprites()[0]["pointer"]
        if not seen or seen[-1] != ptr:
            seen.append(ptr)
            if ptr == 0x34 + 4:
                shot = frames + 5
        if frames == shot:
            vice.do_shot(v, os.path.join(vice.ROOT, "screenshots", "dead.png"))
        if not v.mem_get(a("player_dead"), 1)[0]:
            break
    spin = [128 + f for f in (0, 35, 30, 25, 20, 15, 10, 5)]
    dead_blk = 0x34 + 4
    died = dead_blk in seen and all(f in seen for f in spin) and frames > 100
    gm.frame(3)
    hp2 = v.mem_get(a("player_hp"), 1)[0]
    p = gm.sprites()[0]
    at_start = abs(p["x"] - 10 * 256) < 4 * 256 and abs(p["y"] - 245 * 256) < 4 * 256
    v.mem_set(a("debug_no_death"), [1])
    r = r1 and t2 and died and hp2 == 3 and at_start
    print(("ok   " if r else "FAIL ") + f"health: a touch costs a heart ({hp} left, strip {col}); "
          f"the last one: death spin and lying frame ({died}, {frames} frames), then back at "
          f"the start ({at_start}) with {hp2} hearts")
    return r


def items(gm):
    """a dying monster may leave a heart (forced here through the random
    sequence); touching it gives a heart back. Touching a key collects it
    for good and lights it up in the strip."""
    v, a = gm.v, vice.addr
    ok = True
    heart = None
    for which in range(4):
        k, s = gm.go_near(SKEL, which, dx=14)
        v.mem_set(gm.base + 32 * F["state"] + s["i"], [0xC0])     # dying, harmless
        v.mem_set(gm.base + 32 * F["timer"] + s["i"], [2])
        v.mem_set(a("rand_index"), [224])                          # 4 low values
        for _ in range(4):
            gm.frame()
            hs = [h for h in gm.sprites() if h["controller"] == HEART]
            if hs:
                heart = hs[0]
                break
        if heart:
            break
    v.mem_set(a("player_hp"), [2])
    taken = False
    if heart:
        for _ in range(10):
            gm.put(0, heart["x"], heart["y"])
            gm.frame()
            if not any(h["controller"] == HEART for h in gm.sprites()):
                taken = True
                break
    hp = v.mem_get(a("player_hp"), 1)[0]
    r = heart is not None and taken and hp == 3
    print(("ok   " if r else "FAIL ") + f"a monster leaves a heart ({heart is not None}); "
          f"taking it: gone {taken}, hearts 2 -> {hp}")
    ok &= r
    for c, typ in enumerate((KEYR, KEYG, KEYB)):
        k, s = gm.go_near(typ, 0, dx=4)
        for _ in range(10):
            s = gm.find(k)
            if s is None:
                break
            gm.put(0, s["x"], s["y"])
            gm.frame()
        got = v.mem_get(a("has_key") + c, 1)[0]
        col = v.mem_get(a("ui_col") + 3 + c, 1)[0]
        r = s is None and got == 1 and gm.spawn_state(k) == 2 and col == (2, 5, 14)[c]
        print(("ok   " if r else "FAIL ") + f"{NAMES[typ]}: collected {got == 1}, gone for good "
              f"{gm.spawn_state(k) == 2}, strip colour {col}")
        ok &= r
    return ok


def strip(gm):
    """the status strip on screen: each picture in its colour, above line 37"""
    v, a = gm.v, vice.addr
    g.bottom_irq(gm.v)
    px = g.frame(v)
    cols = list(v.mem_get(a("ui_col"), 6))
    xs = (32, 48, 64, 284, 298, 312)
    found = []
    for k in range(6):
        seen = {px(line, x) for line in range(16, 37) for x in range(xs[k], xs[k] + 16)}
        found.append(cols[k] in seen)
    below = {px(line, x) for line in range(37, 81) for x in range(31, 334)}
    r = all(found) and below == {0}
    print(("ok   " if r else "FAIL ") + f"status strip drawn: {found}, black between it and "
          f"the window: {below == {0}}")
    return r


def gates(gm):
    """the locked gates (mygates.s): shut without the key; with it, touching
    the gate opens it (map tiles grass, collision bits clear) and the player
    walks through. The jail's gate starts the rescue: Conan steps aside,
    the princess walks out, then the title picture (VIC bank 1, bitmap mode)
    with the credits scrolling up over it."""
    v, a = gm.v, vice.addr
    ok = True
    n = 3
    t = v.mem_get(a("gate_t"), n + 1)
    tl, th = v.mem_get(a("gate_tile_lo"), t[n]), v.mem_get(a("gate_tile_hi"), t[n])
    p = v.mem_get(a("gate_p"), n + 1)
    pl, ph = v.mem_get(a("gate_path_lo"), p[n]), v.mem_get(a("gate_path_hi"), p[n])
    pm = v.mem_get(a("gate_path_mask"), p[n])
    bx0, bx1 = v.mem_get(a("gate_bx0"), n), v.mem_get(a("gate_bx1"), n)
    by0, by1 = v.mem_get(a("gate_by0"), n), v.mem_get(a("gate_by1"), n)
    v.mem_set(a("debug_freeze_enemies"), [1])           # (nobody in the way)

    tn = v.mem_get(a("gate_tile_new"), t[n])                # what each gate tile becomes

    def state(c):
        """(open, shut)"""
        tiles = [v.mem_get(tl[i] | th[i] << 8, 1)[0] == tn[i] for i in range(t[c], t[c + 1])]
        bits = [v.mem_get(pl[i] | ph[i] << 8, 1)[0] & ~pm[i] & 0xFF for i in range(p[c], p[c + 1])]
        return all(tiles) and not any(bits), not any(tiles) and all(bits)

    # where the player stands to touch each gate, and the way through
    spots = [((bx0[0] + bx1[0]) // 2, by1[0], ["W"], lambda x, y: y < by0[0]),        # red: from the south
             (bx1[1], (by0[1] + by1[1]) // 2, ["A"], lambda x, y: x < bx0[1]),        # green: from the east
             (bx1[2], (by0[2] + by1[2]) // 2, None, None)]                             # blue: the rescue
    names = ("red door", "green gate", "blue gate")
    for c, (x, y, keys, past) in enumerate(spots):
        if keys is None:                                 # the princess must be there
            v.mem_set(a("debug_freeze_enemies"), [0])
            gm.go_near(PRIN, 0, dx=12)
        v.mem_set(a("has_key") + c, [0])
        gm.put(0, x * 256 + 128, y * 256 + 128)
        gm.frame(15)
        shut = state(c)[1] and v.mem_get(a("gate_open") + c, 1)[0] == 0
        v.mem_set(a("has_key") + c, [1])
        gm.put(0, x * 256 + 128, y * 256 + 128)
        for _ in range(15):                             # (a teleport: a redraw first)
            gm.frame()
            if v.mem_get(a("gate_open") + c, 1)[0]:
                break
        opened = state(c)[0] and v.mem_get(a("gate_open") + c, 1)[0] == 1
        if keys is None:
            break
        vice.set_keys(v, keys)
        through = False
        for _ in range(60):
            gm.frame()
            s0 = gm.sprites()[0]
            if past(s0["gxhi"], s0["gyhi"]):
                through = True
                break
        vice.set_keys(v, [])
        if c == 0:
            vice.do_shot(v, os.path.join(vice.ROOT, "screenshots", "gate_red.png"))
        r = shut and opened and through
        print(("ok   " if r else "FAIL ") + f"{names[c]}: shut without its key {shut}, opens with it "
              f"{opened}, walked through {through}")
        ok &= r
    # the rescue
    phases, shot, prin_x = [], False, None
    regs = (0, 0)
    for _ in range(600):
        try:
            gm.frame()
        except RuntimeError:
            break                                           # the game loop has stopped
        ph = v.mem_get(a("cut_phase"), 1)[0]
        if not phases or phases[-1] != ph:
            phases.append(ph)
        pr = [s for s in gm.sprites() if s["controller"] == PRIN]
        if pr:
            prin_x = pr[0]["gxhi"]
        if ph == 3 and not shot:
            vice.do_shot(v, os.path.join(vice.ROOT, "screenshots", "rescue.png"))
            shot = True
            num = v.checkpoint(a("credits"))                # the pause, then the end
            v.run_until_hit(num, 20)
            break
    # the title picture (moved to VIC bank 1), credits scrolling up over it
    ys, stray = [], False
    for _ in range(600):                                # (a hold, a fade, then the text)
        num = v.checkpoint(a("cr_irq_bot"))
        if not v.run_until_hit(num, 5):
            break
        ys.append(v.mem_get(a("cr_y0"), 1)[0])
        if v.mem_get(a("cr_phase"), 1)[0] < 2:                 # picture alone: no sprites
            stray |= v.mem_get(0xD015, 1)[0] != 0
        if len(ys) == 580:
            vice.do_shot(v, os.path.join(vice.ROOT, "screenshots", "credits.png"))
    regs = v.mem_get(0xD011, 1)[0], v.mem_get(0xDD00, 1)[0] & 3, v.mem_get(0xD015, 1)[0]
    won = bool(regs[0] & 0x20 and regs[1] == 2 and regs[2] == 0xFF)
    rolling = len(ys) == 600 and sum(1 for p, q in zip(ys, ys[1:]) if q == p - 1) > 150
    r = opened and shut and [q for q in phases if q][:3] == [1, 2, 3] and prin_x is not None \
        and prin_x >= 4 * 8 + 2 and won and rolling and not stray
    print(("ok   " if r else "FAIL ") + f"{names[2]}: shut without its key {shut}, opens with it {opened}; "
          f"rescue phases {phases}, princess out at char x {prin_x}, title picture {won}, "
          f"credits scrolling {rolling} ({len(ys)} frames), no stray sprites before {not stray}")
    return ok and r


def main(argv):
    what = argv[0] if argv else "all"
    v = vice.Vice()
    try:
        gm = Game(v)
        ok = True
        for name, fn in (("wizard", wizard), ("behaviour", behaviour), ("sword", sword),
                         ("hitbox", hitbox), ("contact", contact), ("health", health),
                         ("items", items), ("strip", strip), ("gates", gates)):
            if what in (name, "all"):
                ok &= fn(gm)
    finally:
        v.close()
    print("PASS" if ok else "FAILED")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main(sys.argv[1:])
