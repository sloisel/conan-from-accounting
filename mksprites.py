import re
import numpy as np

redata = re.compile(r'.byte.*')
recolor = re.compile(r'color: (\$[0-9a-f]*)')
recolor1 = re.compile(r'LDA #(\$[0-9a-f]*) // sprite multicolor 1')
recolor2 = re.compile(r'LDA #(\$[0-9a-f]*) // sprite multicolor 2')

with open('mysprites.txt') as f:
    s = f.read()
#    print(s)
    data = redata.findall(s)
    color = recolor.findall(s)
    print('.segment SPRITES')
    print('.var spritecolor1='+recolor1.findall(s)[0])
    print('.var spritecolor2='+recolor2.findall(s)[0])
    print('spritedata:')
    print('\n'.join(data))
    print('.segment TABLES')
    print('spritecolors:')
    print('.byte '+(','.join(color)))
    # (the same colours as a list, for tables built at assembly time)
    print('.var spritecolor_list = List().add('+(','.join(color))+')')

    
    
