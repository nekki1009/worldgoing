"""Contact sheets from unchanged engine frames, with no aspect-ratio distortion."""
from pathlib import Path
import sys
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/medieval_shoes_20260916'
SOURCE=OUT/'final'
STYLES=('chinese','japanese','european')


def picture(path,width=400):
    image=Image.open(path).convert('RGBA')
    background=Image.new('RGBA',image.size,(36,42,50,255))
    background.alpha_composite(image)
    return background.convert('RGB').resize((width,width),Image.Resampling.LANCZOS)


def sheet(paths,labels,name,cols=3,width=400):
    canvas=Image.new('RGB',(cols*width,((len(paths)+cols-1)//cols)*(width+26)),(27,32,40))
    draw=ImageDraw.Draw(canvas)
    for i,(path,label) in enumerate(zip(paths,labels)):
        x=i%cols*width;y=i//cols*(width+26)
        draw.text((x+10,y+7),label,fill='white')
        canvas.paste(picture(path,width),(x,y+26))
    canvas.save(OUT/name,quality=94)


if __name__=='__main__':
    keys=[f'{sex}_{style}' for sex in ('male','female') for style in STYLES]
    if '--ankles' in sys.argv:
        for key in keys:
            for clip in ('run','attack_jump_heavy'):
                frames=[OUT/'ankles'/f'{key}_{clip}_{i:02d}.png' for i in range(17)]
                sheet(frames,[f'{clip} {i}/16' for i in range(17)],key+'_'+clip+'_uncovered.jpg',cols=5,width=280)
        print('MEDIEVAL_SHOE_ANKLE_SHEETS_READY')
        sys.exit(0)
    sheet([SOURCE/f'{k}_threequarter.png' for k in keys],keys,'six_shoes.jpg')
    sheet([SOURCE/f'{k}_outfit.png' for k in keys],keys,'six_matching_outfits.jpg')
    for key in keys:
        views=('front','back','side','threequarter')
        sheet([SOURCE/f'{key}_{v}.png' for v in views],list(views),key+'_views.jpg',cols=2)
        for clip in ('idle','walk','run','attack_crossbow','attack_jump_heavy'):
            frames=[SOURCE/f'{key}_{clip}_{i:02d}.png' for i in range(17)]
            sheet(frames,[f'{clip} {i}/16' for i in range(17)],key+'_'+clip+'.jpg',cols=5,width=280)
        frames=[picture(SOURCE/f'{key}_run_{i:02d}.png',480) for i in range(16)]
        frames[0].save(OUT/(key+'_run.gif'),save_all=True,append_images=frames[1:],duration=52,loop=0)
    print('MEDIEVAL_SHOES_PREVIEWS_READY')
