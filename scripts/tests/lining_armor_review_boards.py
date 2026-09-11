"""Contact sheets and timed frame sequences from actual engine captures."""
import json
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2] / '.visual_captures/lining_armor_overlap'
MODE = sys.argv[1] if len(sys.argv)>1 else 'final'
OUT = ROOT / MODE / 'boards'
OUT.mkdir(parents=True, exist_ok=True)
FONT = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 19)
CLIPS = ['idle','walk','run','guard','attack_bow','attack_crossbow','attack_spear','attack_hammer']


def board(items, name, columns=4, size=380):
    canvas = Image.new('RGB', (columns*size, ((len(items)+columns-1)//columns)*(size+28)), (34,40,49))
    draw = ImageDraw.Draw(canvas)
    for i, (path, label) in enumerate(items):
        im = Image.open(path).convert('RGBA')
        im.thumbnail((size,size))
        x, y = i%columns*size, i//columns*(size+28)
        canvas.paste(im, (x+(size-im.width)//2,y), im)
        draw.text((x+7,y+size+3), label, font=FONT, fill='white')
    canvas.save(OUT/name, quality=94)


for sex in ['male','female']:
    durations = json.loads((ROOT/f'{MODE}/{sex}_durations.json').read_text())
    for armor in ['armor_iron_01','armor_mingguang_01']:
        stem = f'{sex}_{armor}'
        board([(ROOT/f'{MODE}/{stem}_neutral_{view}.png', view) for view in ['front','side','back','threequarter']], f'{stem}_neutral.jpg')
        for clip in CLIPS:
            frames = [ROOT/f'{MODE}/{stem}_{clip}_{i:02d}.png' for i in range(17)]
            board([(p,f'{clip} {i}/16') for i,p in enumerate(frames)], f'{stem}_{clip}.jpg')
            images = []
            for path in frames:
                im = Image.open(path).convert('RGBA').resize((512,512))
                bg = Image.new('RGB', im.size, (34,40,49))
                bg.paste(im,mask=im.getchannel('A'))
                images.append(bg)
            images[0].save(OUT/f'{stem}_{clip}.gif',save_all=True,append_images=images[1:],duration=[round(durations[clip]*1000/16)]*16+[100],loop=0)
            closeups = [(ROOT/f'{MODE}/{stem}_extreme_{clip}_{side}_{yaw}.png',f'{side} - yaw {yaw}') for side in ['L','R'] for yaw in [65,245]]
            if all(path.exists() for path,_ in closeups):
                board(closeups,f'{stem}_extreme_{clip}.jpg',2,500)
board([(ROOT/f'{stage}/{sex}_{armor}_{suffix}.png', f'{sex} {armor.split("_")[1]} - {label}')
       for armor in ['armor_iron_01','armor_mingguang_01'] for sex in ['male','female']
       for stage,suffix,label in [('isolated','both','before'),(MODE,'attack_bow_08','after')]], 'comparison.jpg',4,440)
print('LINING_ARMOR_REVIEW_BOARDS',OUT)
