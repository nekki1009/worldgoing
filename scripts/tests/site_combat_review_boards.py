"""Review sheets and animations made only from the actual Godot captures."""
import html
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2] / '.visual_captures/site_combat_assets'
MODE = sys.argv[1] if len(sys.argv) > 1 else 'final'
LOW_POSE = MODE == 'mingguang'
if LOW_POSE:
    ROOT = ROOT.parent / 'mingguang_low_pose'
    MODE = sys.argv[2] if len(sys.argv) > 2 else 'candidate'
OUT = ROOT / MODE / 'boards'
OUT.mkdir(parents=True, exist_ok=True)
FONT = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 18)
CLIPS = ['guard_raise', 'guard_lower', 'guard_break', 'unconscious', 'get_up',
         'rescue', 'reload_bow', 'reload_crossbow']
CLIPS += [prefix + suffix for prefix in ['guard_weapon', 'guard_polearm']
          for suffix in ['', '_raise', '_lower', '_break']]
if LOW_POSE:
    CLIPS = ['down', 'unconscious', 'get_up', 'rescue']


def board(items, name, columns=4, width=384):
    height = round(width * 1.25)
    canvas = Image.new('RGB', (columns * width, ((len(items) + columns - 1) // columns) * (height + 28)), '#293039')
    draw = ImageDraw.Draw(canvas)
    for i, (path, label) in enumerate(items):
        with Image.open(path) as source:
            image = source.convert('RGBA')
        image.thumbnail((width, height))
        x, y = i % columns * width, i // columns * (height + 28)
        canvas.paste(image, (x + (width - image.width) // 2, y), image)
        draw.text((x + 5, y + height + 3), label, font=FONT, fill='white')
    canvas.save(OUT / name, quality=95)


for sex in ['male', 'female']:
    if LOW_POSE:
        for clip in ['T-Pose', *CLIPS, 'idle']:
            paths = [ROOT / MODE / f'{sex}_{clip}_{view}.png' for view in ['front', 'side', 'back']]
            paths += sorted((ROOT / MODE).glob(f'{sex}_{clip}_key_*.png'))
            if all(path.exists() for path in paths):
                board([(path, path.stem.replace(sex + '_', '')) for path in paths], f'{sex}_{clip}_views.jpg')
    if MODE == 'final' and not LOW_POSE:
        for start in range(0, len(CLIPS), 2):
            board([(ROOT / MODE / f'{sex}_{clip}_{view}.png', f'{clip} {view}')
                   for clip in CLIPS[start:start + 2] for view in ['front', 'side', 'back', '02']],
                  f'{sex}_views_{start:02d}.jpg')
        for start in range(0, len(CLIPS), 4):
            board([(ROOT / MODE / f'{sex}_{clip}_{sample:02d}.png', f'{clip} {sample}/4')
                   for clip in CLIPS[start:start + 4] for sample in range(5)],
                  f'{sex}_keyframes_{start:02d}.jpg', 5, 256)
    elif MODE == 'motion' or LOW_POSE:
        for clip in CLIPS:
            marker = 'motion_' if LOW_POSE else ''
            paths = sorted((ROOT / MODE).glob(f'{sex}_{clip}_{marker}[0-9][0-9][0-9].png'))
            if LOW_POSE and not paths:
                continue
            assert paths, (sex, clip)
            for start in range(0, len(paths), 24):
                board([(path, f'{clip} {(start + i) / 12:.2f}s') for i, path in enumerate(paths[start:start + 24])],
                      f'{sex}_{clip}_{start:03d}.jpg', 6, 240)
            frames = []
            for path in paths:
                with Image.open(path) as source:
                    image = source.convert('RGBA')
                image.thumbnail((512, 640))
                frame = Image.new('RGB', image.size, '#293039')
                frame.paste(image, mask=image.getchannel('A'))
                frames.append(frame)
            frames[0].save(OUT / f'{sex}_{clip}.gif', save_all=True, append_images=frames[1:],
                           duration=[83] * (len(frames) - 1) + [250], loop=0)
    else:
        raise ValueError(MODE)

if MODE == 'final' and not LOW_POSE:
    board([(ROOT / MODE / f'{sex}_{clip}_02.png', f'{sex} {clip}') for sex in ['male', 'female']
           for clip in ['guard_weapon', 'guard_break', 'rescue', 'reload_crossbow']], 'overview.jpg')
entries = ''.join(f'<figure><a href="{html.escape(path.name)}"><img loading="lazy" src="{html.escape(path.name)}"></a><figcaption>{html.escape(path.stem)}</figcaption></figure>'
                  for path in sorted(OUT.glob('*.gif' if MODE == 'motion' or LOW_POSE else '*.jpg')))
(OUT / 'index.html').write_text('<!doctype html><meta charset="utf-8"><title>Site combat asset review</title>'
    '<style>body{background:#202630;color:#fff;font:16px sans-serif;margin:24px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(420px,1fr));gap:20px}figure{margin:0}img{max-width:100%}figcaption{padding:8px}</style>'
    f'<h1>Site combat · {MODE}</h1><p>Actual Godot captures; motion sampled at 12 fps. Visual review is separate from runtime assertions.</p><main>{entries}</main>', encoding='utf-8')
print('SITE_COMBAT_REVIEW_BOARDS', OUT)
