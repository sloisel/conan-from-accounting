"""Additions to the CharPad map (ultimate.asm): the fence, the locked gates and
the princess's jail. convert.py applies them when it writes ultimate.s;
gen_gates.py and gen_spawns.py use the same data.

  red:   a fence along the south edge of the graveyard (row 58), with a red
         double door next to the lake; the red key lies in the south-east
         corner of the meadow south of it
  green: a green gate at the east end of the bridge; its key is in the
         north-east forest
  blue:  the princess's jail by the pond in the north-west (iron bars on a
         stone floor), with a blue gate on its east side; its key is by the
         lake shore at the east end of the hedge (west meadow)

Characters are multicolour: 4 double-width pixels per row, 8 rows:
'k' black (background), '.' grass (multicolour 1), 'g' grey (multicolour 2),
'c' the tile's own colour.
"""

GRASS = 1
BLOCKED, WALK = 0xFF, 0x80

# char codes free in the map's charset: $aa..$b1 are unused by the map's
# tiles, $b2..$b7 and $d0..$d4 are never written at run time (myvic2.s clip
# blocks start at glyph $b8, the pointer-slot glyphs are $d5..$dc)
FREE_CHARS = list(range(0xAA, 0xB8)) + list(range(0xD0, 0xD5))

PIX = {"k": 0, ".": 1, "g": 2, "c": 3}


def char(rows):
    assert len(rows) == 8, rows
    out = []
    for r in rows:
        assert len(r) == 4, r
        v = 0
        for p in r:
            v = v << 2 | PIX[p]
        out.append(v)
    return out


# ---- pictures ----------------------------------------------------------------
# fence (grey, 16 rows: char rows 1 and 2 of its tile): a post every 4 chars
FENCE_POST = ([".kk.", "kggk", "kggk", "kggk", "kggk", "kggk", "kggk", "kggk"],
              ["kggk", "kggk", "kggk", "kggk", "kggk", "kggk", "kggk", ".kk."])
FENCE_RAIL = (["....", "....", "....", "kkkk", "gggg", "gggg", "kkkk", "...."],
              ["....", "....", "kkkk", "gggg", "gggg", "kkkk", "....", "...."])
# the double door in the fence: bars in the tile's colour
DOOR = (["kkkk", "cccc", "cccc", "kkkk", "kcck", "kcck", "kcck", "kcck"],
        ["kcck", "kcck", "kcck", "kcck", "kkkk", "cccc", "cccc", "kkkk"])
# a gate across an east-west way (2 chars wide, the tile's full height):
# stone posts at both ends, bars in the tile's colour
GATE_POST = (["kkkk", "kggg", "kggg", "kggg", "kggg", "kggg", "kggg", "kkkk"],
             ["kkkk", "gggk", "gggk", "gggk", "gggk", "gggk", "gggk", "kkkk"])
GATE_BARS = (["kcck", "kcck", "kcck", "kccc", "kccc", "kcck", "kcck", "kcck"],
             ["kcck", "kcck", "kcck", "ccck", "ccck", "kcck", "kcck", "kcck"])
# the jail: a wall of iron bars along the north (top rail, bars, bottom
# rail), seen edge-on along the west (a post), flagstones inside, the blue
# gate on the east
JAIL = {
    "top":   ["kkkk", "gggg", "gggg", "kkkk", ".kg.", ".kg.", ".kg.", ".kg."],
    "bars":  [".kg."] * 8,
    "foot":  [".kg.", ".kg.", ".kg.", ".kg.", "kkkk", "gggg", "gggg", "kkkk"],
    "cap":   ["kkkk", "kggk", "kggk", "kggk", "kggk", "kggk", "kggk", "kggk"],
    "post":  ["kggk"] * 8,
    "floor": ["gggk", "gggk", "gggk", "kkkk", "gkgg", "gkgg", "gkgg", "kkkk"],
    "shade": ["kkkk", "kkkk", "gggk", "kkkk", "gkgg", "gkgg", "gkgg", "kkkk"],
}


# ---- new tiles, placements, gates ---------------------------------------------
# (tile numbers 37..54 are CharPad tiles the map does not use)
(T_FENCE, T_DOOR_L, T_DOOR_R, T_GATE_G, T_GATE_B, T_JAIL_NW, T_JAIL_N, T_JAIL_NE, T_JAIL_W,
 T_JAIL_FLOOR, T_JAIL_OPEN) = range(37, 48)

KEY_SPOTS = {20: (62, 62), 22: (52, 2), 24: (22, 47)}    # red, green, blue key (tile x, y)
PRINCESS = (6, 7)                                         # in her jail

EDITS = ([(x, 58, T_FENCE) for x in range(50, 63)]
         + [(48, 58, T_DOOR_L), (49, 58, T_DOOR_R), (40, 4, T_GATE_G),
            (5, 6, T_JAIL_NW), (6, 6, T_JAIL_N), (7, 6, T_JAIL_NE), (5, 7, T_JAIL_W),
            (6, 7, T_JAIL_FLOOR), (7, 7, T_GATE_B)])

# key colour index (0 red, 1 green, 2 blue) -> its tiles and what each
# becomes when it opens (grass; the jail's floor reaches into its gate's tile)
GATES = [[(48, 58, GRASS), (49, 58, GRASS)], [(40, 4, GRASS)], [(7, 7, T_JAIL_OPEN)]]


def apply(charset, tilechars, tilecols, tiletags, mapdata):
    """add the chars and tiles, edit the map. charset: list of bytes (grown to
    256 chars); tilechars: list of 16-char lists per tile; tilecols, tiletags:
    per tile; mapdata: 64*64 tile numbers. All modified in place."""
    charset.extend([0] * (2048 - len(charset)))
    free = iter(FREE_CHARS)
    codes = {}

    def new(name, data):
        c = next(free)
        assert all(c not in tilechars[t] for t in set(mapdata)), f"char ${c:02x} is in use"
        charset[c * 8:c * 8 + 8] = data
        codes[name] = c
        return c

    for name, pic in (("fpost", FENCE_POST), ("frail", FENCE_RAIL), ("door", DOOR),
                      ("gpost", GATE_POST), ("gbars", GATE_BARS)):
        new(name + "0", char(pic[0]))
        new(name + "1", char(pic[1]))
    g = tilechars[GRASS][0]

    def tile(t, chars, col, tag):
        while len(tilechars) <= t:
            tilechars.append([0] * 16)
            tilecols.append(0)
            tiletags.append(BLOCKED)
        tilechars[t], tilecols[t], tiletags[t] = list(chars), col, tag

    fp0, fp1, fr0, fr1 = codes["fpost0"], codes["fpost1"], codes["frail0"], codes["frail1"]
    d0, d1 = codes["door0"], codes["door1"]
    tile(T_FENCE, [g] * 4 + [fp0, fr0, fr0, fr0] + [fp1, fr1, fr1, fr1] + [g] * 4, 8 + 0, BLOCKED)
    tile(T_DOOR_L, [g] * 4 + [fp0, d0, d0, d0] + [fp1, d1, d1, d1] + [g] * 4, 8 + 2, BLOCKED)
    tile(T_DOOR_R, [g] * 4 + [d0, d0, d0, fp0] + [d1, d1, d1, fp1] + [g] * 4, 8 + 2, BLOCKED)
    gp = [g, codes["gpost0"], codes["gpost1"], g]          # middle of the tile: the
    gb = [g, codes["gbars0"], codes["gbars1"], g]          # player stops right at it
    tile(T_GATE_G, gp + gb + gb + gp, 8 + 5, BLOCKED)
    j = {k: new("jail_" + k, char(v)) for k, v in JAIL.items()}
    t, b, f, cp, p = j["top"], j["bars"], j["foot"], j["cap"], j["post"]
    fl, sh = j["floor"], j["shade"]
    tile(T_JAIL_NW, [g] * 4 + [g, g, g, cp] + [g, g, g, p] + [g, g, g, p], 8, BLOCKED)
    tile(T_JAIL_N, [g] * 4 + [t] * 4 + [b] * 4 + [f] * 4, 8, BLOCKED)
    tile(T_JAIL_NE, [g] * 4 + [t, t, cp, g] + [b, b, p, g] + [f, f, p, g], 8, BLOCKED)
    tile(T_JAIL_W, [g, g, g, p] * 4, 8, BLOCKED)
    tile(T_JAIL_FLOOR, [sh] * 4 + [fl] * 12, 8, WALK)
    tile(T_JAIL_OPEN, [sh, g, g, g] + [fl, g, g, g] * 3, 8, WALK)
    tile(T_GATE_B, [sh] + gp[1:] + ([fl] + gb[1:]) * 2 + [fl] + gp[1:], 8 + 6, BLOCKED)

    for tiles in GATES:                     # (gates stand on grass)
        assert all(mapdata[y * 64 + x] == GRASS for x, y, _ in tiles)
    for x, y, t in EDITS:
        assert tiletags[mapdata[y * 64 + x]] != BLOCKED, (x, y)
        mapdata[y * 64 + x] = t
    return codes


def pathing(mapdata, tiletags):
    """128x128 bits, as convert.py: a blocked tile blocks the half-tile cells
    2t..2t+2 in both directions. Returns a list of 2048 bytes (16 per row,
    bit k%8 of byte k//8 = column k)."""
    grid = [[0] * 129 for _ in range(129)]
    for j in range(64):
        for k in range(64):
            if tiletags[mapdata[j * 64 + k]] != BLOCKED:
                continue
            for x in range(2 * j, 2 * j + 3):
                for y in range(2 * k, 2 * k + 3):
                    grid[x][y] = 1
    out = []
    for j in range(128):
        for b in range(16):
            v = 0
            for bit in range(8):
                v |= grid[j][b * 8 + bit] << bit
            out.append(v)
    return out
