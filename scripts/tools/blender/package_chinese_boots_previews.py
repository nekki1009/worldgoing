"""Unretouched Godot contact sheets and duration-correct animation previews."""
import json,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(Path(__file__).parent))
from package_chinese_leather_helmet_previews import sheet,picture
DIR=ROOT/'.visual_captures/chinese_leather_boots'
for sex in ['male','female']:
    timing=json.loads((DIR/f'{sex}_timing.json').read_text())
    views=['front','side','back','threequarter']
    sheet([DIR/f'{sex}_{v}.png' for v in views],views,DIR/f'{sex}_views.jpg',cols=2,width=512)
    for clip in timing:
        paths=[DIR/f'{sex}_{clip}_{i:02d}.png' for i in range(16)]
        sheet(paths,[f'{clip} {i:02d}' for i in range(16)],DIR/f'{sex}_{clip}_sheet.jpg',cols=4,width=320)
        frames=[picture(p,(512,640)) for p in paths[:-1]]
        duration=max(20,round(timing[clip]['duration']*1000/15/10)*10)
        frames[0].save(DIR/f'{sex}_{clip}.gif',save_all=True,append_images=frames[1:],loop=0,duration=duration)
    combos=[(a,v) for a in ['armor_light_leather_01','armor_chinese_leather_01'] for v in [35,145]]
    sheet([DIR/f'{sex}_{a}_{v}.png' for a,v in combos],[f'{a} {v}' for a,v in combos],DIR/f'{sex}_combinations.jpg',cols=2,width=512)
sheet([DIR/f'{sex}_threequarter.png' for sex in ['male','female']],['Male / Chinese leather boots','Female / Chinese leather boots'],DIR/'boots_overview.jpg',cols=2,width=512)
print('CHINESE_BOOTS_PREVIEWS_PACKAGED')
