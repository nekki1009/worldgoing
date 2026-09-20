"""Arrange untouched Godot captures for visual review; never fabricate game art."""
import json
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/equipment_matrix_20260918'
IMAGES=OUT/'visual'
SHEETS=OUT/'sheets'
FONT=ImageFont.truetype('C:/Windows/Fonts/msjh.ttc',22)


def sheet(name,tiles,columns,size=(360,440)):
    width,height=size;rows=(len(tiles)+columns-1)//columns
    canvas=Image.new('RGB',(columns*width,rows*(height+42)),(37,43,51));draw=ImageDraw.Draw(canvas)
    for index,(path,label) in enumerate(tiles):
        image=Image.open(path).convert('RGBA');image.thumbnail((width,height))
        x=index%columns*width;y=index//columns*(height+42)
        canvas.paste(image,(x+(width-image.width)//2,y),image)
        draw.text((x+10,y+height+8),label,font=FONT,fill=(235,233,220))
    SHEETS.mkdir(exist_ok=True)
    canvas.save(SHEETS/(name+'.jpg'),quality=94)


def main():
    names={'cloth':'布','leather':'皮','iron':'鐵','steel':'鋼','wood':'木','stone':'石','chinese':'中式','japanese':'日式','western':'西式'}
    for sex,label in [('male','男'),('female','女')]:
        sheet('armor_'+sex,[(IMAGES/f'{sex}_{material}_{culture}_35.png',label+'・'+names[material]+'製・'+names[culture]) for material in ['cloth','leather','iron','steel'] for culture in ['chinese','japanese','western']],3)
        sheet('shields_'+sex,[(IMAGES/f'{sex}_shield_{material}_{culture}_held.png',label+'・'+names[material]+'製・'+names[culture]) for material in ['wood','stone','iron','steel'] for culture in ['chinese','japanese','western']],3)
        sheet('capes_'+sex,[(IMAGES/f'{sex}_cape_{culture}_{angle}.png',label+'・'+names[culture]+'・'+str(angle)+'°') for culture in ['chinese','japanese','western'] for angle in [0,90,180]],3)
        for clip,label2 in [('ride_heavy','馬上重擊'),('ride_guard_break','馬上破防')]:
            sheet(sex+'_'+clip,[(IMAGES/f'{sex}_{clip}_longsword_01_{step}.png',label+'・'+label2+'・'+str(step)+'%') for step in [0,20,45,65,100]],5,size=(400,488))
        for clip in ['walk','run','attack_axe','attack_jump_heavy','ride_heavy','ride_guard_break']:
            sheet(sex+'_cape_'+clip,[(IMAGES/f'{sex}_cape_motion_{clip}_{step:02d}.png',f'{clip} {step}/12') for step in range(13)],5,size=(280,342))
        for clip in ['ride_heavy','ride_guard_break']:
            sheet(sex+'_mounted_sets_'+clip,[(IMAGES/f'{sex}_mounted_set_{culture}_{clip}_{step}.png',names[culture]+f' {step}%') for culture in ['chinese','japanese','western'] for step in [0,25,53,78,100]],5,size=(320,391))
    report=json.loads((IMAGES/'result.json').read_text(encoding='utf-8'))
    assert report['status']=='PASS' and report['captures']
    print('EQUIPMENT_MATRIX_SHEETS_READY',len(list(SHEETS.glob('*.jpg'))))


if __name__=='__main__':main()
