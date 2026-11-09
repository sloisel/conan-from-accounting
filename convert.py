import re
import sys
import numpy as np
sys.path.insert(0, 'tools')
import map_extras     # fence, locked gates, the prison (tools/map_extras.py)

recharset = re.compile(r'charset_data[^;]*;')
rechartileset = re.compile(r'chartileset_data[^;]*;')
rechartilesetcolor = re.compile(r'chartileset_colour_data[^;]*;')
rechartilesettag = re.compile(r'chartileset_tag_data[^;]*;')
remapdata = re.compile(r'map_data[^;]*$')
hexfinder = re.compile(r'\$[0-9A-F]*')
recolr = re.compile(r'COLR[^\n]*')

with open('ultimate.asm') as f:
    s = f.read()
    chartileset = np.array(hexfinder.findall(rechartileset.search(s).group()))
    charset = np.array(hexfinder.findall(recharset.search(s).group()))
    chartilesetcolor = np.array(hexfinder.findall(rechartilesetcolor.search(s).group()))
    chartilesettag = np.array(hexfinder.findall(rechartilesettag.search(s).group()))
    mapdata = np.array(hexfinder.findall(remapdata.search(s).group()))
    colr = np.array(recolr.findall(s))

    pathing = np.zeros((129,129),dtype=int)
    grass = 0
    for k in range(len(chartilesettag)):
        if chartilesettag[k] == "$80":
            grass = k
        if chartilesettag[k] == "$00":
            chartilesettag[k] = "$ff"
    # the additions: new chars and tiles, map edits
    h = lambda a: [int(x[1:], 16) for x in a]
    cs_i, tags_i, map_i = h(charset), h(chartilesettag), h(mapdata)
    tc_i = [h(chartileset[t * 16:t * 16 + 16]) for t in range(len(chartileset) // 16)]
    col_i = h(chartilesetcolor)
    map_extras.apply(cs_i, tc_i, col_i, tags_i, map_i)
    fmt = lambda v: "$ff" if v == 0xFF else "$%02X" % v
    charset = np.array([fmt(v) for v in cs_i])
    chartilesettag = np.array([fmt(v) for v in tags_i])
    mapdata = np.array([fmt(v) for v in map_i])
    chartileset = np.array([fmt(v) for t in tc_i for v in t])
    chartilesetcolor = np.array([fmt(v) for v in col_i])
    for j in range(64):
        for k in range(64):
            uu = int(mapdata[j*64+k][1:],16)
            if chartilesettag[uu] != "$ff":
                continue
            for x in range(2*j,2*j+3):
                for y in range(2*k,2*k+3):
                    pathing[x,y] = 1
    empty_tile_numbers = np.ones((99,),dtype=int)*grass
    empty_tile_numbers = map(lambda x: "$"+hex(x)[2:],empty_tile_numbers)
    pathing = pathing[:-1,:-1]
    p2 = np.tile("$00",(128,16))
    for j in range(128):
        for k in range(0,128,8):
            foo = 0
            for l in range(8):
                foo = foo*2 + pathing[j,k+7-l]
            p2[j,k//8] = '$'+hex(foo)[2:]
    ntiles = len(chartileset)//16
    m = 2**int(np.ceil(np.log2(ntiles)))
    z = np.tile("$00",(16,m))
    col = np.tile("$00",(16,m))
    for j in range(16):
        for k in range(ntiles):
            z[j,k] = chartileset[k*16+j]
            col[j,k] = chartilesetcolor[k]
    for j in range(len(colr)):
        print(".var ",colr[j])
    print(".var numtiles=",m)
    print('.segment TILECHAR')
    print('tilechar:')
    for j in range(16):
        print(".byte ",",".join(z[j,:]))
    print('.segment TILETAG')
    print('tiletag:')
    print(".byte ",",".join(chartilesettag))
    print('.segment TILECOL')
    print('tilecol:')
    for j in range(16):
        print(".byte ",",".join(col[j,:]))
    print('.segment MAP')
    print('map:')
    for j in range(64):
        k = j*64
        print(".byte",",".join(mapdata[k:k+64]))
    cs = np.tile("$00",(256*8,))
    cs[0:len(charset)] = charset
    print('.segment CHARSET')
    print('charset:')
    for j in range(128):
        k = j*16
        print(".byte",",".join(cs[k:k+16]))
    print('.segment PATHING')
    print('pathing:')
    for j in range(128):
        print(".byte",",".join(p2[j,:]))
    print('.segment TABLES')
    print('empty_tile_numbers:')
    print(".byte",",".join(empty_tile_numbers))
    
    
