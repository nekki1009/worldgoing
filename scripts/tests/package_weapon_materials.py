"""Contact sheets of unchanged Godot captures; raw PNGs remain alongside."""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/weapon_materials_20260917'
KINDS=('wood','stone','iron','steel')
BASES=('longsword_01','spear_01','axe_01','wood_axe_01','hammer_01','dagger_01','bow_01','crossbow_01','pickaxe_01','tool_hammer_01','shovel_01')


def sheet(paths,labels,target,cols=4,width=400):
    result=Image.new('RGB',(cols*width,((len(paths)+cols-1)//cols)*(width+32)),(31,39,49))
    draw=ImageDraw.Draw(result)
    for index,(path,label) in enumerate(zip(paths,labels)):
        src=Image.open(path).convert('RGBA')
        bg=Image.new('RGBA',src.size,(48,57,68,255));bg.alpha_composite(src)
        bg.thumbnail((width,width),Image.Resampling.LANCZOS)
        x=index%cols*width;y=index//cols*(width+32)
        draw.text((x+10,y+10),label,fill='white')
        result.paste(bg.convert('RGB'),(x,y+32))
    result.save(target,quality=94)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--source',choices=['candidate','final'],default='candidate');parser.add_argument('--sex',choices=['male','female','both'],default='both')
    args=parser.parse_args();source=OUT/args.source;destination=OUT/(args.source+'_boards');destination.mkdir(exist_ok=True)
    for sex in ('male','female') if args.sex=='both' else (args.sex,):
        for base in BASES:
            ids=[base if kind=='iron' else base+'_'+kind for kind in KINDS]
            paths=[source/f'{sex}_{asset}_detail.png' for asset in ids]
            if all(p.exists() for p in paths):sheet(paths,list(KINDS),destination/f'{sex}_{base}_materials.jpg',width=500)
            if base in ('bow_01','crossbow_01'):
                paths=[source/f'{sex}_{asset}_ammo.png' for asset in ids]
                if all(p.exists() for p in paths):sheet(paths,list(KINDS),destination/f'{sex}_{base}_ammo.jpg',width=500)
            asset=base+'_stone'
            paths=[source/f'{sex}_{asset}_{view}.png' for view in ('front','back','side','threequarter')]
            if all(p.exists() for p in paths):sheet(paths,['front','back','side','threequarter'],destination/f'{sex}_{base}_views.jpg',width=480)
            for asset in ids:
                paths=[source/f'{sex}_{asset}_attack_{i:02d}.png' for i in range(9)]
                if all(p.exists() for p in paths):sheet(paths,[f'attack {i}/8' for i in range(9)],destination/f'{sex}_{asset}_motion.jpg',cols=3,width=380)
                paths=[source/f'{sex}_{asset}_{pose}_stowed.png' for pose in ('idle','walk','run')]
                if all(p.exists() for p in paths):sheet(paths,['stowed idle','stowed walk','stowed run'],destination/f'{sex}_{asset}_stowed.jpg',cols=3,width=480)
        ids=[base if kind=='iron' else base+'_'+kind for base in ('axe_01','wood_axe_01','pickaxe_01','tool_hammer_01','shovel_01') for kind in KINDS]
        paths=[source/f'{sex}_{asset}_detail.png' for asset in ids]
        if all(p.exists() for p in paths):sheet(paths,ids,destination/f'{sex}_weapons_tools.jpg',width=480)
    print('WEAPON_MATERIAL_BOARDS_READY',destination)
