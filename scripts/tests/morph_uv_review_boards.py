"""Compare original screenshots and arrange them for review; never retouch them."""
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
DIR = ROOT/'.visual_captures/morph_uv_repair'
views = ['front', 'side', 'back', 'threequarter', 'run', 'attack_bow', 'ride_idle']
report = []
for sex in ['male', 'female']:
    for view in views:
        a = np.array(Image.open(DIR/f'{sex}_before_{view}.png')).astype('i2')
        b = np.array(Image.open(DIR/f'{sex}_after_{view}.png')).astype('i2')
        delta = abs(a-b)
        report.append({'sex': sex, 'view': view,
                       'different_pixels': int(np.any(delta > 0, axis=2).sum()),
                       'max_channel_difference': int(delta.max()),
                       'mean_channel_difference': float(delta.mean())})
    for group, selected in [('neutral', views[:4]), ('motion', views[4:])]:
        board = Image.new('RGB', (512*len(selected), 1320), '#232c35')
        draw = ImageDraw.Draw(board)
        for row, phase in enumerate(['before', 'after']):
            for col, view in enumerate(selected):
                picture = Image.open(DIR/f'{sex}_{phase}_{view}.png').convert('RGBA')
                picture.thumbnail((512, 640))
                board.paste(picture, (col*512, row*660+20), picture)
                draw.text((col*512+10, row*660+4), f'{sex} / {phase} / {view}', fill='white')
        board.save(DIR/f'{sex}_{group}_comparison.jpg', quality=95)
(DIR/'pixel_comparison.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report, indent=2))
