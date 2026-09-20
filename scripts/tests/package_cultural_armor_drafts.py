"""Arrange the unchanged full-resolution captures into review contact sheets."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
QA = ROOT / 'reports/output/equipment_matrix_20260918/armor'
destination = QA / 'sheets'
destination.mkdir(exist_ok=True)
font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 20)
for sex in ('male', 'female'):
    for style in ('Japanese_Leather', 'Japanese_Iron', 'Japanese_Steel', 'Chinese_Steel', 'Western_Steel', 'Cloth_Western'):
        paths = [QA / 'draft' / f'{sex}_{style}_{v}.png' for v in ('front', 'back', 'side', 'threequarter')]
        paths += [next((QA / 'draft').glob(f'{sex}_{style}_{v}_peak_*.png')) for v in ('walk', 'run', 'attack_axe')] if style != 'Cloth_Western' else []
        paths = [QA / 'draft_revision_2' / p.name if (QA / 'draft_revision_2' / p.name).exists() else p for p in paths]
        sheet = Image.new('RGB', (1920, 530 * ((len(paths) + 3) // 4)), '#30343a')
        draw = ImageDraw.Draw(sheet)
        for i, path in enumerate(paths):
            frame = Image.open(path).convert('RGB')
            frame.thumbnail((480, 480), Image.Resampling.LANCZOS)
            x, y = i % 4 * 480, i // 4 * 530
            sheet.paste(frame, (x, y + 35))
            draw.text((x + 8, y + 6), path.stem.removeprefix(sex + '_'), fill='white', font=font)
        target = destination / f'{sex}_{style}.jpg'
        sheet.save(target, quality=94)
        print(target.name, len(paths))
