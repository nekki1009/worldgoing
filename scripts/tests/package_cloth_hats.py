"""QA contact sheets only; original engine/gray frames remain untouched."""
import sys
import package_medieval_shoes as sheets

sheets.OUT=sheets.ROOT/'output/cloth_hats_20260918'
styles=('chinese','japanese','western')
if '--gray' in sys.argv:
    for sex in ('male','female'):
        keys=[f'{sex}_{style}_gray_{view}' for style in styles for view in ('front','side','back','threequarter')]
        sheets.sheet([sheets.OUT/(k+'.png') for k in keys],keys,sex+'_gray_board.jpg',cols=4,width=320)
else:
    source=sheets.OUT/('candidate' if '--candidate' in sys.argv else 'final')
    keys=[f'{sex}_{style}' for sex in ('male','female') for style in styles]
    sheets.sheet([source/(k+'_threequarter.png') for k in keys],keys,source.name+'_six_hats.jpg',width=400)
    sheets.sheet([source/(k+'_outfit.png') for k in keys],keys,source.name+'_outfits.jpg',width=400)
    for sex in ('male','female'):
        views=[f'{sex}_{style}_{v}' for style in styles for v in ('front','side','back','threequarter')]
        sheets.sheet([source/(k+'.png') for k in views],views,source.name+'_'+sex+'_views.jpg',cols=4,width=320)
        for style in styles:
            hairs=[f'{sex}_{style}_hair_{i:02d}_{v}' for i in range(1,9) for v in ('front','back')]
            if (source/(hairs[-1]+'.png')).exists():
                sheets.sheet([source/(k+'.png') for k in hairs],hairs,f'{source.name}_{sex}_{style}_hair.jpg',cols=4,width=300)
            clips=('idle','walk','run','attack_axe','attack_crossbow','attack_jump_heavy')
            frames=[f'{sex}_{style}_{clip}_{i:02d}' for clip in clips for i in range(9)]
            if (source/(frames[-1]+'.png')).exists():
                sheets.sheet([source/(k+'.png') for k in frames],frames,f'{source.name}_{sex}_{style}_motion.jpg',cols=9,width=220)
print('CLOTH_HATS_BOARDS_READY')
