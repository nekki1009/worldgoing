"""Contact sheets and timed GIFs from unchanged Godot renders."""
import argparse
import json
from pathlib import Path
from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parents[3]
DIR=ROOT/'.visual_captures/chinese_leather_helmet'


def picture(path,size):
    source=Image.open(path).convert('RGBA')
    canvas=Image.new('RGBA',source.size,(42,48,56,255));canvas.alpha_composite(source)
    return canvas.convert('RGB').resize(size,Image.Resampling.LANCZOS)


def sheet(paths,labels,target,cols=4,width=320):
    height=round(width*1.25);row_height=height+24
    result=Image.new('RGB',(cols*width,((len(paths)+cols-1)//cols)*row_height),(32,37,44))
    draw=ImageDraw.Draw(result)
    for i,(path,label) in enumerate(zip(paths,labels)):
        x=i%cols*width;y=i//cols*row_height
        result.paste(picture(path,(width,height)),(x,y+24));draw.text((x+8,y+6),label,fill='white')
    result.save(target,quality=95)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--sex',choices=['male','female','both'],default='both');args=parser.parse_args()
    sexes=['male','female'] if args.sex=='both' else [args.sex]
    for sex in sexes:
        timing=json.loads((DIR/f'{sex}_timing.json').read_text())
        for clip,info in timing.items():
            for prefix in ['', 'head_']:
                paths=[DIR/f'{sex}_{prefix}{clip}_{i:02d}.png' for i in range(info['frames'])]
                pics=[picture(p,(384,480)) for p in paths]
                duration=max(20,round(info['duration']*1000/(len(paths)-1)/10)*10)
                pics[0].save(DIR/f'{sex}_{prefix}{clip}.gif',save_all=True,append_images=pics[1:-1],duration=duration,loop=0,optimize=False)
                sheet(paths,[f'{sex}/{clip}/{i:02d}' for i in range(len(paths))],DIR/f'{sex}_{prefix}{clip}_sheet.jpg')
        for label,names in {
            'views':['neutral_front','neutral_threequarter','neutral_right','neutral_back'],
            'helmet_views':['helmet_front','helmet_threequarter','helmet_side','helmet_back'],
            'hair':['hair_1','hair_2','hair_3','hair_4'],
            'combinations':['armor_only','helmet_only','full_idle_35','full_idle_145','full_run_35','full_guard_145'],
        }.items():
            sheet([DIR/f'{sex}_{name}.png' for name in names],[sex+'/'+name for name in names],DIR/f'{sex}_{label}.jpg',cols=2 if len(names)==4 else 3,width=512)
    if args.sex=='both':
        sheet([DIR/f'{sex}_helmet_threequarter.png' for sex in sexes],[sex+' / Actual editor render' for sex in sexes],DIR/'final_overview.jpg',cols=2,width=512)
    print('LEATHER_HELMET_PREVIEWS_READY',args.sex)
