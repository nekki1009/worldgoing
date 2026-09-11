"""Arrange unchanged current-engine captures for per-option inspection."""
import json,re,sys
from package_chinese_leather_helmet_previews import ROOT, sheet, picture

directory = ROOT / ('.visual_captures/all_model_repaired' if '--repaired' in sys.argv else '.visual_captures/all_model_audit')
source = (ROOT / 'scripts/ui/human_character_3d_editor.gd').read_text(encoding='utf-8')
slots = source.split('const PART_SLOTS := [', 1)[1].split('const ANIMATION_SLOTS', 1)[0]
groups = re.split(r'"id": &"(face|hair|helmet|outfit|armor|cape|weapon|shield|boots)",\s*"label"', slots)
for sex in ['male', 'female']:
    for slot, block in zip(groups[1::2], groups[2::2]):
        options = [key for key in re.findall(r'"id": &"([^"]+)"', block) if key != 'none']
        names = [f'{option}_{view}' for option in options for view in ['front','side','back','motion0','motion1','motion2','motion3']]
        paths = [directory / f'{sex}_{name}.png' for name in names]
        if all(path.exists() for path in paths):
            sheet(paths, names, directory / f'{sex}_{slot}_sheet.jpg', cols=7, width=240)
print('AUDIT_SHEETS_READY')

if '--repaired' in sys.argv:
    combo=directory/'combinations'
    for sex in ['male','female']:
        for index in range(4):
            for lining in ['outfit_underlayer_01','outfit_chinese_lining_01']:
                for group,clips in [('motion',['idle','walk','run','guard','hit','knockback','attack_jump_heavy']),('riding',['ride_run','ride_slash'])]:
                    paths=[combo/f'{sex}_set{index}_{lining}_{clip}_{i}.png' for clip in clips for i in range(8)]
                    if all(p.exists() for p in paths):sheet(paths,[p.stem.replace(f'{sex}_set{index}_{lining}_','') for p in paths],combo/f'{sex}_set{index}_{lining}_{group}_sheet.jpg',cols=8,width=220)
        paths=sorted(combo.glob(f'{sex}_fit_*.png'))
        if paths:sheet(paths,[p.stem for p in paths],combo/f'{sex}_helmet_fit_sheet.jpg',cols=8,width=240)
    cycles=directory/'weapon_cycles'
    for sex in ['male','female']:
        timing_path=cycles/f'{sex}_timing.json'
        if not timing_path.exists():continue
        for weapon,length in json.loads(timing_path.read_text()).items():
            paths=[cycles/f'{sex}_{weapon}_{i:02d}.png' for i in range(24)]
            assert all(p.exists() for p in paths),(sex,weapon)
            sheet(paths,[f'{weapon}/{i:02d}' for i in range(24)],cycles/f'{sex}_{weapon}_sheet.jpg',cols=6,width=320)
            frames=[picture(p,(384,480)) for p in paths]
            frames[0].save(cycles/f'{sex}_{weapon}.gif',save_all=True,append_images=frames[1:],duration=max(20,round(length*1000/24/10)*10),loop=0,optimize=False)
    sheet([combo/f'{sex}_set3_outfit_chinese_lining_01_idle_0.png' for sex in ['male','female']],['Male / repaired formal assets','Female / repaired formal assets'],directory/'final_overview.jpg',cols=2,width=512)
    proof=['male_detail_bow_01_1.png','female_detail_none_1.png','male_detail_crossbow_01_1.png','female_mount_white_true_1.png']
    sheet([directory/name for name in proof],['Bow string and grip','Shield inner-side grip','Two-handed crossbow aim','White horse and fitted tack'],directory/'final_repair_details.jpg',cols=2,width=512)

for sex in ['male','female']:
    for group, pattern in [('details', f'{sex}_detail_*.png'), ('mounts', f'{sex}_mount_*.png')]:
        paths = sorted(directory.glob(pattern))
        if paths:
            sheet(paths, [p.stem for p in paths], directory / f'{sex}_{group}_sheet.jpg', cols=3, width=400)
