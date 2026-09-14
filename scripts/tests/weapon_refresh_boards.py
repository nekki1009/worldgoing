"""Contact sheets from unmodified engine captures; no painted corrections."""
import sys
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[2] / 'output/weapon_refresh_20260913' / sys.argv[1]
font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 16)
if root.name.endswith('options'):
    labels = [('axe_01', '新版戰斧'), ('wood_axe_01', '舊版保留：伐木斧')]
    title_font = ImageFont.truetype('C:/Windows/Fonts/msjh.ttc', 27)
    sheet = Image.new('RGB', (1200, 420), '#293039')
    draw = ImageDraw.Draw(sheet)
    for column, (axe, label) in enumerate(labels):
        with Image.open(root / f'male_{axe}_detail.png') as source:
            tile = source.convert('RGBA')
        tile = tile.crop(tile.getchannel('A').getbbox())
        tile.thumbnail((550, 300))
        sheet.paste(tile, (column * 600 + (600 - tile.width) // 2, 90 + (300 - tile.height) // 2), tile)
        draw.text((column * 600 + 28, 24), label, font=title_font, fill='white')
    sheet.save(root / 'axe_comparison.png')
    for sex in ['male', 'female']:
        for axe, label in labels:
            sheet = Image.new('RGB', (1280, 1350), '#293039')
            draw = ImageDraw.Draw(sheet)
            views = ['front', 'back', 'side', 'three_quarter', 'idle_held', 'idle_holstered', 'walk_holstered', 'run_held', 'attack_00', 'attack_03', 'attack_06', 'attack_09', 'attack_12', 'guard']
            for index, view in enumerate(views):
                with Image.open(root / f'{sex}_{axe}_{view}.png') as source:
                    tile = source.convert('RGBA')
                tile.thumbnail((320, 310))
                x, y = index % 4 * 320, index // 4 * 335
                sheet.paste(tile, (x, y), tile)
                draw.text((x + 6, y + 310), f'{sex} {view}', font=font, fill='white')
            sheet.save(root / f'{sex}_{axe}_review.jpg')
    print('AXE_OPTION_REVIEW_BOARDS', root)
    sys.exit(0)
for sex in sys.argv[2:] or ['male', 'female']:
    measurements = json.loads((root / f'{sex}_measurements.json').read_text())
    for clip in ['T-Pose', 'attack_axe', 'attack_spear', 'guard', 'idle', 'walk']:
        paths = sorted(root.glob(f'{sex}_{clip}_[0-9][0-9].png'))
        if not paths:
            continue
        sheet = Image.new('RGB', (1200, 1280), '#293039')
        draw = ImageDraw.Draw(sheet)
        frames = []
        for i, path in enumerate(paths):
            with Image.open(path) as source:
                tile = source.convert('RGBA')
            tile.thumbnail((300, 300))
            x, y = (i % 4) * 300, (i // 4) * 320
            sheet.paste(tile, (x, y), tile)
            draw.text((x + 6, y + 302), f'{clip} {i}/12', font=font, fill='white')
            frame = Image.new('RGB', tile.size, '#293039')
            frame.paste(tile, mask=tile.getchannel('A'))
            frames.append(frame)
        sheet.save(root / f'{sex}_{clip}_sheet.jpg')
        duration = max(row['time'] for row in measurements if row['clip'] == clip) * 1000 / 12
        frames[0].save(root / f'{sex}_{clip}.gif', save_all=True, append_images=frames[1:], duration=max(20,round(duration)), loop=0)
        full = []
        for path in sorted(root.glob(f'{sex}_{clip}_full_*.png')):
            with Image.open(path) as source:
                tile = source.convert('RGBA')
            tile.thumbnail((640,640))
            frame = Image.new('RGB',tile.size,'#293039')
            frame.paste(tile,mask=tile.getchannel('A'))
            full.append(frame)
        if full:
            full[0].save(root/f'{sex}_{clip}_full.gif',save_all=True,append_images=full[1:],duration=[80,80,90]*(len(full)//3)+[80]*(len(full)%3),loop=0)
print('WEAPON_REVIEW_BOARDS', root)
