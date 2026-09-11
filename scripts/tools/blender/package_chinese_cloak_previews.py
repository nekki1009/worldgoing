"""Package genuine editor frames as review sheets, GIFs and a local gallery."""
from pathlib import Path
import argparse
import json
import re
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[3]
FOLDER=ROOT/'.visual_captures/chinese_cloak_remake'

def composite(path,size):
    source=Image.open(path).convert('RGBA')
    background=Image.new('RGBA',source.size,(42,48,56,255))
    background.alpha_composite(source)
    return background.convert('RGB').resize(size,Image.Resampling.LANCZOS)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--sex',choices=['male','female'],required=True)
    parser.add_argument('--sheets-only',action='store_true')
    parser.add_argument('--log',type=Path)
    args=parser.parse_args()
    timing_file=FOLDER/f'{args.sex}_timing.json'
    timing=json.loads(timing_file.read_text()) if timing_file.exists() else {}
    if args.log:
        for clip,frames,duration in re.findall(r'CLOAK_CAPTURE_CLIP '+args.sex+r' (\S+) frames=(\d+) duration=([\d.]+)',args.log.read_text(encoding='utf-8')):
            timing[clip]={'duration':float(duration),'frames':int(frames)}
    meta=json.loads((ROOT/f'assets/characters/human/q35/standard_anime_{args.sex}_character_pack.json').read_text(encoding='utf-8'))
    cards=[]
    for clip in meta['animations']:
        if clip=='T-Pose': continue
        frames=sorted(FOLDER.glob(f'{args.sex}_{clip}_[0-9][0-9].png'))
        if not frames: continue
        pictures=[composite(path,(384,480)) for path in frames]
        name=f'{args.sex}_{clip}'
        if not args.sheets_only:
            assert clip in timing, 'Missing measured animation timing for '+clip
            duration=max(20,round(timing[clip]['duration']*1000/(len(frames)-1)/10)*10)
            pictures[0].save(FOLDER/f'{name}.gif',save_all=True,append_images=pictures[1:-1],duration=duration,loop=0,optimize=False)
        chosen=[round(i*(len(frames)-1)/7) for i in range(8)]
        sheet=Image.new('RGB',(1280,848),(32,37,44));draw=ImageDraw.Draw(sheet)
        for slot,index in enumerate(chosen):
            x=(slot%4)*320;y=(slot//4)*424
            sheet.paste(composite(frames[index],(320,400)),(x,y+24))
            draw.text((x+8,y+5),f'{args.sex} / {clip} / frame {index:02d}',fill='white')
        sheet.save(FOLDER/f'{name}_sheet.jpg',quality=92)
        resolved=timing.get(clip,{}).get('resolved',clip)
        label=clip if resolved==clip else f'{clip} → {resolved} (editor alias)'
        cards.append(f'<article><h2>{label}</h2><img src="{name}.gif"><p><a href="{name}_sheet.jpg">Eight keyframes</a> · <a href="{frames[0].name}">Full resolution</a></p></article>')
    page='<!doctype html><meta charset="utf-8"><title>Chinese cloak animation review</title><style>body{background:#20252c;color:#eee;font:16px system-ui;margin:32px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:24px}img{width:100%;max-width:384px}article{background:#2a3038;padding:16px}h2{font-size:18px}a{color:#eed08b}</style>'
    page+=f'<h1>{args.sex.title()} — Chinese cloak</h1><p>Actual character-editor captures. GIF timing follows each imported clip, rounded to 10 ms; it is not a performance measurement. Original PNGs retain 1024×1280 resolution.</p><main>'+''.join(cards)+'</main>'
    (FOLDER/f'{args.sex}_gallery.html').write_text(page,encoding='utf-8')
    views=Image.new('RGB',(1536,1328),(32,37,44));draw=ImageDraw.Draw(views)
    for i,view in enumerate(['neutral_front','neutral_threequarter','neutral_right','neutral_left','neutral_back','collar']):
        x=(i%3)*512;y=(i//3)*664
        views.paste(composite(FOLDER/f'{args.sex}_{view}.png',(512,640)),(x,y+24))
        draw.text((x+10,y+6),args.sex+' / '+view,fill='white')
    views.save(FOLDER/f'{args.sex}_views.jpg',quality=95)
    if all((FOLDER/f'{sex}_neutral_threequarter.png').exists() for sex in ['male','female']):
        overview=Image.new('RGB',(1024,672),(32,37,44));draw=ImageDraw.Draw(overview)
        for i,sex in enumerate(['male','female']):
            overview.paste(composite(FOLDER/f'{sex}_neutral_threequarter.png',(512,640)),(i*512,32))
            draw.text((i*512+16,10),sex.title()+' / Character editor capture',fill='white')
        overview.save(FOLDER/'final_overview.jpg',quality=95)
    print('CLOAK_PREVIEW_GALLERY',args.sex,len(cards))

if __name__=='__main__': main()
