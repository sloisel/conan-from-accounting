#!/usr/bin/env python3
"""Boot the game in VICE (background, warp, emulator audio off) and check
that the basics work. Exits non-zero on failure. Run via `make test`."""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vice
import game_check

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
        check(n == 3, f"3 sprites allocated (player, sword, enemy): got {n}")
        check(f(5, 2) == 4, f"enemy uses controller 4 (control_basic): got {f(5, 2)}")
        check(f(10, 2) == 14 and f(12, 2) == 222, "enemy placed at its map tile (3,55)")
        map_tile = v.mem_get(vice.addr("map") + 55 * 64 + 3, 1)[0]
        check(map_tile == 1, "enemy spawn tile replaced with grass")

        x0 = f(10, 0)
        vice.set_keys(v, ["D"])
        v.frames(20)
        vice.set_keys(v, [])
        v.frames(2)
        n, f = sprites(v)
        check(f(10, 0) > x0, f"player walks right with D: gx {x0} -> {f(10, 0)}")

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
        on_screen = 30 < f(2, 2) < 250
        check(on_screen, f"enemy scrolls into view after walking north: y={f(2, 2)}")
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
        v.close()
    finally:
        subprocess.run([TOOL, "stop"], capture_output=True)
    print("PASS" if not failures else f"{len(failures)} FAILED")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
