"""Pixel regressions and contact sheets from unchanged Godot captures."""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2] / '.visual_captures/helmet_hair_mask'
STAGE = sys.argv[1] if len(sys.argv) > 1 else 'scalp_retained'
SEXES = sys.argv[2:] or ['male', 'female']
HELMETS = ['leather', 'iron', 'steel', 'mingguang', 'chinese_leather']
OUT = ROOT / STAGE / 'boards'
OUT.mkdir(parents=True, exist_ok=True)
FONT = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 19)


def changed_mask(a, b):
    a = np.asarray(Image.open(a).convert('RGBA'), dtype=np.int16)
    b = np.asarray(Image.open(b).convert('RGBA'), dtype=np.int16)
    assert a.shape == b.shape == (960, 768, 4)
    return np.abs(a - b).max(axis=2) > 24


def board(items, name, columns=4, width=320):
    height = width * 5 // 4
    sheet = Image.new('RGB', (columns * width, ((len(items)+columns-1)//columns)*(height+28)), (31, 37, 46))
    draw = ImageDraw.Draw(sheet)
    for i, (path, label) in enumerate(items):
        pic = Image.open(path).convert('RGBA')
        pic.thumbnail((width, height))
        x, y = i % columns * width, i // columns * (height+28)
        sheet.paste(pic, (x, y), pic)
        draw.text((x+6, y+height+3), label, font=FONT, fill='white')
    sheet.save(OUT / name)


report = []
negative_controls = []
for sex in SEXES:
    for helmet in HELMETS:
        for style in range(1, 9):
            stem = f'{sex}_{style:02d}_helmet_{helmet}_01'
            rear = changed_mask(ROOT/STAGE/f'{stem}_180.png', ROOT/STAGE/f'{stem}_back_hidden.png')
            front = changed_mask(ROOT/STAGE/f'{stem}_0.png', ROOT/STAGE/f'{stem}_front_hidden.png')
            # Diagnostic camera is fixed at 768x960. Separate the actual scalp
            # region from the crown and below-neck regions; zero rear hair is a bug.
            report.append(dict(sex=sex, style=style, helmet=helmet, rear_pixels=int(rear.sum()), scalp_pixels=int(rear[330:540].sum()), crown_pixels=int(rear[:300].sum()), detached_pixels=int(rear[610:].sum()), front_pixels=int(front.sum())))
        for views, suffix in [([0, 90], 'front_side'), ([35, 145], 'threequarter')]:
            board([(ROOT/STAGE/f'{sex}_{i:02d}_helmet_{helmet}_01_{yaw}.png', f'{i:02d} / {yaw}') for i in range(1, 9) for yaw in views], f'{sex}_{helmet}_{suffix}.jpg')
    for helmet in ['leather', 'mingguang']:
        for clip in ['run', 'attack_jump_heavy']:
            board([(ROOT/STAGE/f'{sex}_{i:02d}_helmet_{helmet}_01_{clip}_{s}.png', f'{i:02d} / {s}') for i in range(1, 9) for s in range(6)], f'{sex}_{helmet}_{clip}.jpg', 6, 256)
    board([(ROOT/STAGE/f'{sex}_{i:02d}_restored.png', f'{sex} {i:02d} restored') for i in range(1, 9)], f'{sex}_restored.jpg')
    old_style = 2 if sex == 'female' else 3
    stem = f'{sex}_{old_style:02d}_helmet_leather_01'
    old_detached = int(changed_mask(ROOT/'before'/f'{stem}_180.png', ROOT/STAGE/f'{stem}_back_hidden.png')[610:].sum())
    bald_stem = f'{sex}_01_helmet_mingguang_01'
    old_scalp = int(changed_mask(ROOT/'final2'/f'{bald_stem}_180.png', ROOT/'final2'/f'{bald_stem}_back_hidden.png')[330:540].sum())
    negative_controls.append(dict(sex=sex, original_detached_pixels=old_detached, overmasked_scalp_pixels=old_scalp))
    assert old_detached > 1000, 'Original detached ends must fail the below-neck check'
    assert old_scalp < 100, 'Previous bald mask must fail the scalp-coverage check'

examples = [('female', 2, 'leather', 145), ('female', 5, 'mingguang', 145), ('male', 1, 'leather', 145), ('male', 5, 'mingguang', 145)]
items = [(ROOT/stage/f'{sex}_{style:02d}_helmet_{helmet}_01_{yaw}.png', f'{sex} {style:02d} / ' + ('Overmasked' if stage == 'final2' else 'Scalp retained')) for sex, style, helmet, yaw in examples if sex in SEXES for stage in ['final2', STAGE]]
board(items, 'before_after.png', 4, 384)
(OUT/'pixel_report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
stray_failures = [r for r in report if r['crown_pixels'] > 64 or r['detached_pixels'] > 64]
scalp_failures = [r for r in report if (r['helmet'] == 'mingguang' or (r['helmet'] == 'leather' and r['style'] <= 4)) and r['scalp_pixels'] < 100]
front_failures = [r for r in report if r['style'] in [1, 2, 3, 4, 5, 7] and r['front_pixels'] < 50]
print('HELMET_HAIR_PIXELS', json.dumps(dict(cases=len(report), max_crown=max(r['crown_pixels'] for r in report), max_detached=max(r['detached_pixels'] for r in report), min_mingguang_scalp=min(r['scalp_pixels'] for r in report if r['helmet'] == 'mingguang'), negative_controls=negative_controls, stray_failures=stray_failures, scalp_failures=scalp_failures, front_failures=front_failures)))
assert not stray_failures, 'Hair penetrated the crown or left detached ends below the neck'
assert not scalp_failures, 'Auto erased the scalp behind the open guards'
assert not front_failures, 'Auto lost the expected visible bangs'
print('HELMET_HAIR_IMAGE_REGRESSION_PASS')
