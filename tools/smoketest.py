#!/usr/bin/env python3
"""Boot the game in VICE (background, warp, emulator audio off) and check
that the basics work. Exits non-zero on failure. Run via `make test`."""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vice
import game_check
import monster_check
import irq_audit
import mux_check
import border_check

ROOT = vice.ROOT
TOOL = os.path.join(ROOT, "tools", "vice.py")
SHOTS = os.path.join(ROOT, "screenshots")
failures = []


def check(cond, msg):
    print(("ok   " if cond else "FAIL ") + msg)
    if not cond:
        failures.append(msg)


def sprites(v):
    n = v.mem_get(vice.addr("sprite2_count"), 1)[0]
    t = v.mem_get(vice.addr("sprite_data_2"), 32 * 19)
    field = lambda f, i: t[32 * f + i]
    return n, field


def main():
    subprocess.run([TOOL, "stop"], capture_output=True)
    subprocess.run([TOOL, "start"], check=True)
    try:
        v = vice.Vice()
        num = v.checkpoint(vice.addr("forever"))
        check(v.run_until_hit(num, 60), "game loads and reaches main loop")
        v.frames(5)

        n, f = sprites(v)
        check(n == 2, f"at the start: player and sword (monsters and the wizard stream in): {n} sprites")
        spawns = vice.addr("spawn_ty") - vice.addr("spawn_tx")
        check(spawns >= 80, f"spawn table: {spawns} monster spawn points")
        map_tile = v.mem_get(vice.addr("map") + 55 * 64 + 3, 1)[0]
        check(map_tile == 1, "spawn marker tiles in the map turned into grass")

        x0 = f(10, 0)
        vice.set_keys(v, ["D"])
        v.frames(20)
        vice.set_keys(v, [])
        v.frames(2)
        n, f = sprites(v)
        check(f(10, 0) > x0, f"player walks right with D: gx {x0} -> {f(10, 0)}")

        v.mem_set(vice.addr("has_sword"), [1])          # (monster_check tests the wizard)
        vice.set_keys(v, ["J"])
        v.frames(3)
        n, f = sprites(v)
        check(f(6, 0) >= v.mem_get(vice.addr("player_index") + 16, 1)[0],
              "J starts a sword stroke")
        vice.set_keys(v, [])
        v.frames(30)

        vice.set_keys(v, ["A"])
        v.frames(40)
        vice.set_keys(v, ["W"])
        v.frames(120)
        vice.set_keys(v, [])
        v.frames(2)
        n, f = sprites(v)
        blobs = [i for i in range(2, n) if f(5, i) == 4 and 81 <= f(2, i) < 250]
        check(blobs, f"a blob spawned and is on screen after walking north: {n - 2} monster(s)")
        os.makedirs(SHOTS, exist_ok=True)
        vice.do_shot(v, os.path.join(SHOTS, "smoketest.png"))

        bad = game_check.run(v, 500, seed=1, verbose=False)
        check(bad == 0, f"AGSP display pixel-exact (background and sprites) over "
                        f"500 random scroll frames: {bad} bad")
        bad, crossings = game_check.check_edges(v, verbose=False)
        check(bad == 0 and crossings > 0,
              f"sprites exact on pointer-switch lines at the window edges: "
              f"{crossings} frames with a sprite there, {bad} bad")
        bad = game_check.check_top_clip(v, verbose=False)
        check(bad == 0, f"sprites slide in at the top edge (clipped 1..20 rows): {bad} bad")
        fails, layouts, most = mux_check.frozen(v, verbose=True)   # (prints failures)
        check(not fails, f"multiplexer: {layouts} layouts of up to {most} sprites pixel-exact, "
                         f"plan as modelled (rewrite timing): {len(fails)} bad {fails[:3]}")
        v.close()

        # multiplexer with a crowd of live monsters, in a fresh game
        subprocess.run([TOOL, "start"], check=True, capture_output=True)
        v = vice.Vice()
        num = v.checkpoint(vice.addr("forever"))
        v.run_until_hit(num, 60)
        bad, irq, lo, hi, upd, spare = mux_check.live(v, verbose=False)
        check(bad == 0 and not irq and lo >= 10,
              f"multiplexer, live crowd: {lo}..{hi} sprites, {bad} bad frames, "
              f"IRQ chain {'intact' if not irq else irq[:2]} ({upd:.2f} updates/frame)")
        vice.set_keys(v, ["W", "A"])                    # the crowd, scrolling
        bad, lines, missing = border_check.check(v, 150, verbose=False)
        vice.set_keys(v, ["S", "D"])
        bad2, lines2, missing2 = border_check.check(v, 150, verbose=False)
        vice.set_keys(v, [])
        bad3 = border_check.sweep(v, 120, verbose=False)
        check(bad3 == 0, f"open border clean at 120 camera positions all over the map: {bad3} bad")
        check(bad + bad2 == 0, f"open border (status strip) clean while scrolling past a crowd: "
                               f"{bad + bad2} of 300 frames with stray pixels or a missing picture "
                               f"(lines {sorted(set(lines) | set(lines2))[:8]})")
        v.close()

        # gameplay, in a fresh game (the checks above froze the monsters)
        subprocess.run([TOOL, "start"], check=True, capture_output=True)
        v = vice.Vice()
        num = v.checkpoint(vice.addr("forever"))
        v.run_until_hit(num, 60)
        gm = monster_check.Game(v)
        gm.go_near(monster_check.JELLY, 8, dx=4)        # a busy scene (7 sprites)
        gm.frame(30)
        bad = irq_audit.audit(v, 100, verbose=False)
        check(not bad, f"raster IRQ chain intact in a busy scene (100 frames): {bad[:2]}")
        for name, fn in (("wizard", monster_check.wizard), ("behaviour", monster_check.behaviour),
                         ("sword", monster_check.sword), ("hitbox", monster_check.hitbox),
                         ("contact", monster_check.contact),
                         ("health", monster_check.health), ("items", monster_check.items),
                         ("strip", monster_check.strip),
                         ("gates", monster_check.gates)):
            check(fn(gm), f"monsters: {name} checks")
        v.close()
    finally:
        subprocess.run([TOOL, "stop"], capture_output=True)
    print("PASS" if not failures else f"{len(failures)} FAILED")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
