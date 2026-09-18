"""Review sheets assembled only from untouched Blender/Godot captures."""
from pathlib import Path
import sys
import package_medieval_shoes as contact

OUT = Path(__file__).resolve().parents[2]/'output/neutral_faces_20260918'
contact.OUT = OUT
phase = 'candidate' if '--candidate' in sys.argv else 'final'
source = OUT/phase
styles = {1:'Original 01',5:'05 Round',6:'06 Almond',7:'07 Slim',8:'08 Wide-set'}
for kind in ('bare_front','styled'):
    names = [(sex,n) for sex in ('male','female') for n in styles]
    contact.sheet([source/f'{sex}_{n:02d}_{kind}.png' for sex,n in names],
                  [f'{sex} / {styles[n]}' for sex,n in names],f'{phase}_{kind}.jpg',cols=5,width=400)
for sex in ('male','female'):
    keys = [(n,v) for n in range(5,9) for v in ('front','threequarter','side','back')]
    contact.sheet([OUT/f'{sex}_{n:02d}_shape_{v}.png' for n,v in keys],
                  [f'{styles[n]} / {v}' for n,v in keys],f'{sex}_blender_views.jpg',cols=4,width=320)
    if phase == 'candidate': continue
    contact.sheet([source/f'{sex}_{n:02d}_bare_{v}.png' for n,v in keys],
                  [f'{styles[n]} / {v}' for n,v in keys],f'{sex}_godot_views.jpg',cols=4,width=320)
    for n in range(5,9):
        paths = [source/f'{sex}_{n:02d}_hair_{hair:02d}_{angle}.png' for hair in range(1,9) for angle in (0,35)]
        contact.sheet(paths,[p.stem for p in paths],f'{sex}_{n:02d}_hair.jpg',cols=4,width=280)
        paths = sorted(source.glob(f'{sex}_{n:02d}_helmet_*.png'))
        contact.sheet(paths,[p.stem for p in paths],f'{sex}_{n:02d}_headgear.jpg',cols=5,width=280)
    for clip in ('idle','walk','run','hit','attack_jump_heavy'):
        paths = [source/f'{sex}_{n:02d}_{clip}_{step:02d}.png' for n in range(5,9) for step in range(9)]
        contact.sheet(paths,[p.stem for p in paths],f'{sex}_{clip}.jpg',cols=9,width=220)
print('NEUTRAL_FACES_SHEETS_PASS',phase,flush=True)
