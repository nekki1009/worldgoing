"""Contact sheets of unchanged Blender/Godot captures; no painted corrections."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]/'.visual_captures/hair_gendered'
mode = sys.argv[1] if len(sys.argv)>1 else 'candidate'
sexes = sys.argv[2:] or ['male','female']
source = ROOT/mode
out = source/'boards'
out.mkdir(parents=True,exist_ok=True)
font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf',20)


def board(items,name,columns=4,width=384):
    height = int(width*1.25)
    sheet = Image.new('RGB',(columns*width,((len(items)+columns-1)//columns)*(height+30)),(31,37,46))
    draw = ImageDraw.Draw(sheet)
    for i,(path,label) in enumerate(items):
        pic = Image.open(path).convert('RGBA')
        pic.thumbnail((width,height))
        x,y = (i%columns)*width,(i//columns)*(height+30)
        sheet.paste(pic,(x+(width-pic.width)//2,y),pic)
        draw.text((x+8,y+height+4),label,font=font,fill='white')
    sheet.save(out/name)


for sex in sexes:
    board([(source/f'{sex}_{i:02d}_threequarter.png',f'{sex.upper()} {i:02d}') for i in range(1,9)],f'{sex}_eight_styles.png')
    for start in [1,5]:
        board([(source/f'{sex}_{i:02d}_{v}.png',f'{i:02d} {v}') for i in range(start,start+4) for v in ['front','side','back','threequarter']],f'{sex}_views_{start}_{start+3}.jpg')
    board([(source/f'{sex}_{i:02d}_{v}.png',f'{i:02d} {v}') for i in range(1,9) for v in ['front','dye0','dye1']],f'{sex}_dye.jpg',3,320)
    helmets = ['leather','iron','steel','mingguang','chinese_leather']
    for helmet in helmets:
        files = [(source/f'{sex}_{i:02d}_helmet_{helmet}_01_{yaw}.png',f'{i:02d} {yaw}') for i in range(1,9) for yaw in [35,145]]
        if all(p.exists() for p,label in files): board(files,f'{sex}_helmet_{helmet}.jpg',4,320)
    for clip in ['idle','walk','run','attack_jump_heavy']:
        files = [(source/f'{sex}_{i:02d}_{clip}_{s}.png',f'{i:02d} {clip} {s}') for i in range(1,9) for s in range(6)]
        if all(p.exists() for p,label in files): board(files,f'{sex}_motion_{clip}.jpg',6,256)
    files = [(source/f'{sex}_{i:02d}_equipped_{clip}_{s}.png',f'{i:02d} equipped {clip} {s}') for i in [7,8] for clip in ['idle','run'] for s in range(6)]
    if all(p.exists() for p,label in files): board(files,f'{sex}_equipped.jpg',6,320)
    for i in range(5,9):
        paths = [source/f'{sex}_{i:02d}_cycle_run_{s:02d}.png' for s in range(24)]
        if not all(p.exists() for p in paths): continue
        frames = []
        for path in paths:
            pic = Image.open(path).convert('RGBA')
            pic.thumbnail((384,480))
            frame = Image.new('RGB',pic.size,(31,37,46))
            frame.paste(pic,mask=pic.getchannel('A'))
            frames.append(frame)
        frames[0].save(out/f'{sex}_{i:02d}_run.gif',save_all=True,append_images=frames[1:],duration=35,loop=0)
print('HAIR_REVIEW_BOARDS',out)
