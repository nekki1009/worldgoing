"""Unretouched contact sheets and correctly timed previews from Godot frames."""
import json,sys
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(Path(__file__).parent))
from package_chinese_leather_helmet_previews import sheet,picture
DIR=ROOT/'.visual_captures/lining_cloak'
stage=sys.argv[1] if len(sys.argv)>1 else 'shirt'
for sex in ['male','female']:
    if not (DIR/f'{sex}_{stage}_run_side_24.png').exists():continue
    timing=json.loads((DIR/f'{sex}_timing.json').read_text()) if (DIR/f'{sex}_timing.json').exists() else {}
    for view in ['front','side','back']:
        paths=[DIR/f'{sex}_{stage}_run_{view}_{i:02d}.png' for i in range(25)]
        sheet(paths,[f'{sex} {view} {i:02d}' for i in range(25)],DIR/f'{sex}_{stage}_run_{view}_sheet.jpg',cols=5,width=320)
        frames=[picture(p,(512,640)) for p in paths[:-1]]
        if 'cloak_run' in timing:
            duration=max(20,round(timing['cloak_run']['duration']*1000/24/10)*10)
            frames[0].save(DIR/f'{sex}_{stage}_run_{view}.gif',save_all=True,append_images=frames[1:],loop=0,duration=duration)
    if (DIR/f'{sex}_lining_front.png').exists():
        views=['front','threequarter','side','back']
        sheet([DIR/f'{sex}_lining_{v}.png' for v in views],[sex+' / '+v for v in views],DIR/f'{sex}_lining_views.jpg',cols=2,width=512)
        for clip in ['idle','walk','run','attack_axe','attack_jump_heavy','ride_slash']:
            paths=[DIR/f'{sex}_lining_{clip}_{i:02d}.png' for i in range(16)]
            sheet(paths,[f'{sex} {clip} {i:02d}' for i in range(16)],DIR/f'{sex}_lining_{clip}_sheet.jpg',cols=4,width=320)
            if clip in timing:
                frames=[picture(p,(512,640)) for p in paths[:-1]]
                duration=max(20,round(timing[clip]['duration']*1000/15/10)*10)
                frames[0].save(DIR/f'{sex}_lining_{clip}.gif',save_all=True,append_images=frames[1:],loop=0,duration=duration)
        armor=['armor_light_leather_01','armor_chinese_leather_01','armor_iron_01','armor_mingguang_01']
        paths=[DIR/f'{sex}_lining_{a}_{v}.png' for a in armor for v in [35,145]]
        sheet(paths,[f'{a} / {v}' for a in armor for v in [35,145]],DIR/f'{sex}_lining_combinations.jpg',cols=4,width=384)
sheet([DIR/'male_lining_front.png',DIR/'female_lining_front.png',DIR/'male_lining_armor_chinese_leather_01_35.png',DIR/'female_lining_armor_chinese_leather_01_35.png'],['Male lining','Female lining','Male under leather armor','Female under leather armor'],DIR/'lining_overview.jpg',cols=2,width=512)
print('LINING_PREVIEWS_PACKAGED',stage)
