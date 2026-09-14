"""Arrange unchanged engine/Blender captures for visual review (no retouching)."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2] / 'output/western_plate_20260913'
FONT = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 18)


def sheet(paths, destination, columns=4):
    size = 360
    board = Image.new('RGB', (columns * size, ((len(paths)+columns-1)//columns)*(size+26)), '#293039')
    draw = ImageDraw.Draw(board)
    for i, path in enumerate(paths):
        with Image.open(path) as original:
            tile = original.convert('RGBA')
        tile.thumbnail((size, size))
        x, y = i % columns * size, i // columns * (size+26)
        board.paste(tile, (x, y), tile)
        draw.text((x+5, y+size), path.stem, font=FONT, fill='white')
    board.save(destination)


stage = sys.argv[1]
if stage == 'gray':
    sheet([ROOT/'blender_gray'/f'{sex}_{view}.png' for sex in ['male','female'] for view in ['front','back','side','three_quarter']], ROOT/'blender_gray/review.jpg')
else:
    for sex in sys.argv[2:] or ['male','female']:
        folder = ROOT/stage/sex
        sheet([folder/f'neutral_{view}.png' for view in ['front','back','side','three_quarter']], folder/'neutral_review.jpg')
        sheet(sorted(folder.glob('layer_*.png')), folder/'layers_review.jpg', 3)
        for clip in ['idle','walk','run','guard','walk_slash','attack_spear','attack_axe','attack_jump_heavy','rescue','get_up']:
            paths = sorted(folder.glob(f'{clip}_[0-9][0-9].png'))
            if paths:
                sheet(paths, folder/f'{clip}_review.jpg', 3)
        for clip in ['walk','run']:
            frames = []
            for path in sorted(folder.glob(f'{clip}_full_*.png')):
                with Image.open(path) as original:
                    tile = original.convert('RGBA')
                tile.thumbnail((640,640))
                frame = Image.new('RGB', tile.size, '#293039')
                frame.paste(tile, mask=tile.getchannel('A'))
                frames.append(frame)
            if frames:
                frames[0].save(folder/f'{clip}_full.gif', save_all=True, append_images=frames[1:], duration=83, loop=0)
    if stage == 'final':
        board = Image.new('RGB',(1280,710),'#293039')
        draw = ImageDraw.Draw(board)
        title_font = ImageFont.truetype('C:/Windows/Fonts/msjh.ttc',26)
        for column,(sex,label) in enumerate([('male','男版・西式鐵甲'),('female','女版・西式鐵甲')]):
            with Image.open(ROOT/stage/sex/'neutral_three_quarter.png') as original:
                tile = original.convert('RGBA')
            tile.thumbnail((640,640))
            board.paste(tile,(column*640,62),tile)
            draw.text((column*640+190,20),label,font=title_font,fill='white')
        board.save(ROOT/stage/'western_iron_preview.png')
print('WESTERN_IRON_REVIEW_BOARDS', stage)
