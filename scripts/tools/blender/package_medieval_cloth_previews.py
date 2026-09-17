"""Contact sheets from unretouched, actual Godot garment captures."""
import argparse
import json
from pathlib import Path
from package_chinese_leather_helmet_previews import sheet, picture

ROOT = Path(__file__).resolve().parents[3]
STYLES = ['chinese', 'japanese', 'european']
parser = argparse.ArgumentParser()
parser.add_argument('--sex', choices=['male', 'female', 'both'], default='both')
parser.add_argument('--output', default='output/medieval_cloth_20260916')
args = parser.parse_args()
OUT = (ROOT / args.output).resolve()
assert OUT.is_relative_to(ROOT / 'output')
FRAMES = OUT / 'final'
sexes = ['male', 'female'] if args.sex == 'both' else [args.sex]
for sex in sexes:
    timing = json.loads((ROOT / f'assets/characters/human/q35/medieval_cloth/{sex}_clip_times.json').read_text())
    for style in STYLES:
        prefix = f'{sex}_{style}'
        views = ['front', 'left', 'back', 'right', 'threequarter']
        sheet([FRAMES / f'{prefix}_{v}.png' for v in views], views, OUT / f'{prefix}_views.jpg', cols=5, width=256)
        palettes = sorted(FRAMES.glob(prefix + '_palette_*.png'))
        sheet(palettes, [p.stem.split('_palette_')[1] for p in palettes], OUT / f'{prefix}_palettes.jpg', cols=4, width=240)
        for clip in ['idle','walk','run','guard','attack_sword','attack_bow','attack_crossbow','attack_jump_heavy']:
            paths = [FRAMES / f'{prefix}_{clip}_{i:02d}.png' for i in range(25)]
            sheet(paths, [f'{clip} {i:02d}' for i in range(25)], OUT / f'{prefix}_{clip}_sheet.jpg', cols=5, width=220)
            if clip == 'run':
                pics = [picture(p, (384, 480)) for p in paths[:-1]]
                times = timing[clip]
                duration = max(20, round((times[-1]-times[0])*1000/24/10)*10)
                pics[0].save(OUT / f'{prefix}_{clip}.gif', save_all=True, append_images=pics[1:], duration=duration, loop=0)
        armor = sorted(p for p in FRAMES.glob(prefix + '_armor_*.png') if '_neutral_' in p.stem or p.stem.endswith('_00') or p.stem.endswith(('_35','_145')))
        sheet(armor, [p.stem.removeprefix(prefix+'_armor_') for p in armor], OUT / f'{prefix}_armor.jpg', cols=4, width=300)
        for kind in ['light_leather_01','chinese_leather_01','western_iron_01']:
            for clip in ['walk','run','attack_crossbow']:
                paths=sorted(FRAMES.glob(f'{prefix}_armor_{kind}_{clip}_*.png'))
                if len(paths)>2:
                    sheet(paths,[p.stem.split(clip+'_')[1] for p in paths],OUT/f'{prefix}_{kind}_{clip}.jpg',cols=7,width=220)
if args.sex == 'both':
    labels = [f'{sex.title()} / {style.title()}' for sex in sexes for style in STYLES]
    sheet([FRAMES / f'{sex}_{style}_threequarter.png' for sex in sexes for style in STYLES], labels, OUT / 'six_outfits.jpg', cols=3, width=400)
    sheet([FRAMES / f'{sex}_{style}_custom.png' for sex in sexes for style in STYLES], labels, OUT / 'custom_colors.jpg', cols=3, width=320)
    if OUT.name == 'medieval_cloth_fit_20260916':
        old=ROOT/'output/medieval_cloth_20260916/final'
        names=['female_chinese_run_12','female_chinese_attack_crossbow_12','female_chinese_armor_western_iron_01_run_35']
        paths=[];labels=[]
        for name in names:
            paths.extend([old/(name+'.png'),FRAMES/(name+('_00' if '_armor_' in name else '')+'.png')])
            labels.extend(['Before / '+name,'After / same pose'])
        sheet(paths,labels,OUT/'fit_comparison.jpg',cols=2,width=512)
print('MEDIEVAL_CLOTH_PREVIEWS_READY', args.sex)
