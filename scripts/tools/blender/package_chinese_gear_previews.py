"""Package unchanged editor captures as contact sheets and time-correct GIFs."""
from pathlib import Path
import json
from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parents[3]
DIR=ROOT/'.visual_captures/chinese_leather_mingguang'

def picture(path,size):
    source=Image.open(path).convert('RGBA')
    canvas=Image.new('RGBA',source.size,(42,48,56,255));canvas.alpha_composite(source)
    return canvas.convert('RGB').resize(size,Image.Resampling.LANCZOS)

for sex in ['male','female']:
    timing=json.loads((DIR/f'{sex}_timing.json').read_text())
    for clip,info in timing.items():
        frames=[DIR/f'{sex}_{clip}_{i:02d}.png' for i in range(info['frames'])]
        pics=[picture(p,(384,480)) for p in frames]
        duration=max(20,round(info['duration']*1000/(len(frames)-1)/10)*10)
        pics[0].save(DIR/f'{sex}_{clip}.gif',save_all=True,append_images=pics[1:-1],duration=duration,loop=0,optimize=False)
        sheet=Image.new('RGB',(1280,1696),(32,37,44));draw=ImageDraw.Draw(sheet)
        for i,p in enumerate(frames):
            x=(i%4)*320;y=(i//4)*424
            sheet.paste(picture(p,(320,400)),(x,y+24))
            draw.text((x+8,y+6),f'{sex} / {clip} / {i:02d}',fill='white')
        sheet.save(DIR/f'{sex}_{clip}_sheet.jpg',quality=94)
    groups={'views':['neutral_front','neutral_threequarter','neutral_right','neutral_back'],
            'details':['armor_detail','helmet_front','helmet_side','helmet_back'],
            'hair':['hair_1','hair_2','hair_3','hair_4'],
            'combinations':['armor_only','helmet_only','full_idle_35','full_idle_145','full_run_35','full_guard_145']}
    for label,names in groups.items():
        cols=2 if len(names)==4 else 3
        sheet=Image.new('RGB',(512*cols,1328),(32,37,44));draw=ImageDraw.Draw(sheet)
        for i,name in enumerate(names):
            x=(i%cols)*512;y=(i//cols)*664
            sheet.paste(picture(DIR/f'{sex}_{name}.png',(512,640)),(x,y+24))
            draw.text((x+8,y+6),sex+' / '+name,fill='white')
        sheet.save(DIR/f'{sex}_{label}.jpg',quality=95)
overview=Image.new('RGB',(1024,672),(32,37,44));draw=ImageDraw.Draw(overview)
for i,sex in enumerate(['male','female']):
    overview.paste(picture(DIR/f'{sex}_neutral_threequarter.png',(512,640)),(i*512,32))
    draw.text((i*512+16,10),sex.title()+' / Actual character-editor capture',fill='white')
overview.save(DIR/'final_overview.jpg',quality=95)
print('CHINESE_GEAR_PREVIEW_PACKAGE_READY')
