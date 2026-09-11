"""Arrange unaltered diagnostic captures into review/contact sheets."""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from validate_chinese_cloak_assets import read_glb, accessor

root = Path(__file__).resolve().parents[2] / '.visual_captures/body_joint_refinement'
mode = sys.argv[1] if len(sys.argv)>1 else 'candidate'
out = root/mode/'boards'
out.mkdir(parents=True,exist_ok=True)
font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf',20)


def board(items, name, columns=3, size=420):
    canvas = Image.new('RGB',(columns*size,((len(items)+columns-1)//columns)*(size+32)),(34,40,49))
    draw = ImageDraw.Draw(canvas)
    for i,(path,label) in enumerate(items):
        im=Image.open(path).convert('RGBA')
        im.thumbnail((size,size))
        x,y=(i%columns)*size,(i//columns)*(size+32)
        canvas.paste(im,(x+(size-im.width)//2,y),im)
        draw.text((x+8,y+size+4),label,fill='white',font=font)
    canvas.save(out/name,quality=93)


for sex in ['male','female']:
    asset = Path(__file__).resolve().parents[2] / f'assets/characters/human/q35/standard_anime_{sex}_character_pack.glb'
    doc, binary = read_glb(asset)
    durations = {a['name']: max(float(accessor(doc,binary,s['input']).max()) for s in a['samplers']) for a in doc['animations']}
    board([(root/stage/f'{sex}_L_{joint}_{angle}.png',f'{sex} {label} {angle} - {stage}') for joint,label,angle in [('LowerArm','Elbow',135),('Hand','Wrist',55),('Hand','Wrist',-55)] for stage in ['baseline',mode]],f'{sex}_comparison.jpg',2,520)
    board([(root/mode/f'{sex}_neutral_{v}.png',f'{sex} {v}') for v in ['front','side','back','threequarter']],f'{sex}_neutral.jpg',4,450)
    board([(root/mode/f'{sex}_{side}_{joint}_{angle}.png',f'{side} {joint} {angle}') for side in ['L','R'] for joint,angles in [('LowerArm',[0,45,90,135]),('Hand',[-55,0,55])] for angle in angles],f'{sex}_joints.jpg',4,350)
    for clip in ['run','guard','attack_bow','attack_crossbow','attack_spear','attack_hammer']:
        files = [(root/mode/f'{sex}_extreme_{clip}_{side}_{joint}.png',f'{side} {joint}') for side in ['L','R'] for joint in ['LowerArm','Hand']]
        if all(p.exists() for p,label in files):
            board(files,f'{sex}_extreme_{clip}.jpg',2,480)
        frames = [root/mode/f'{sex}_cycle_{clip}_{i:02d}.png' for i in range(0,61,4)]
        if all(p.exists() for p in frames):
            board([(p,f'{clip} {i+1}/16') for i,p in enumerate(frames)],f'{sex}_cycle_{clip}.jpg',4,360)
            images=[]
            for p in frames:
                im=Image.open(p).convert('RGBA').resize((512,512))
                background=Image.new('RGB',im.size,(34,40,49))
                background.paste(im,mask=im.getchannel('A'))
                images.append(background)
            images[0].save(out/f'{sex}_{clip}.gif',save_all=True,append_images=images[1:],duration=[round(durations[clip]*1000/15)]*15+[100],loop=0)
    for outfit in ['outfit_underlayer_01','outfit_chinese_lining_01']:
        for armor in ['none','armor_light_leather_01','armor_iron_01','armor_mingguang_01','armor_chinese_leather_01']:
            board([(root/mode/f'{sex}_{outfit}_{armor}_{clip}_{i}.png',f'{clip} {i+1}/3') for clip in ['run','guard','attack_bow','attack_crossbow','attack_spear','attack_hammer'] for i in range(3)],f'{sex}_{outfit}_{armor}.jpg',3,440)
board([(root/stage/f'{sex}_L_{joint}_{angle}.png',f'{sex} {label} - {stage}') for joint,label,angle in [('LowerArm','Elbow 135',135),('Hand','Wrist 55',55)] for sex in ['male','female'] for stage in ['baseline',mode]],'joint_comparison.jpg',4,400)
print('BODY_JOINT_REVIEW_BOARDS',out)
