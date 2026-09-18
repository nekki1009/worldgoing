"""Additive GLB proof and guarded publication using the existing asset publisher."""
import json
import sys
from pathlib import Path
import numpy as np
import validate_cloth_hats as publication
from validate_chinese_cloak_assets import read_glb, accessor

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT/'output/neutral_faces_20260918'
ASSETS = ROOT/'assets/characters/human/q35'
WORK = ASSETS/'neutral_faces'


def check(sex, final=False):
    stem = f'standard_anime_{sex}_character_pack'
    paths = {ext: ASSETS/f'{stem}.{ext}' if final else WORK/(f'neutral_faces_{sex}.blend' if ext == 'blend' else f'candidate_{sex}.{ext}') for ext in ('blend','glb','json')}
    old, before = read_glb(OUT/'baseline'/f'{stem}.glb')
    new, after = read_glb(paths['glb'])
    assert after[:len(before)] == before
    for key in ('skins','meshes','materials','textures','images','samplers','accessors','bufferViews'):
        assert new.get(key,[])[:len(old.get(key,[]))] == old.get(key,[]), key
    assert old['animations'] == new['animations']
    for a,b in zip(old['nodes'],new['nodes']):
        assert {k:v for k,v in a.items() if k != 'children'} == {k:v for k,v in b.items() if k != 'children'}
        assert b.get('children',[])[:len(a.get('children',[]))] == a.get('children',[])
    added = new['nodes'][len(old['nodes']):]
    assert [n['name'] for n in added] == [f'Face_Standard_{i:02d}' for i in range(5,9)]
    triangles = 0
    eye_shapes = []
    for node in added:
        mesh = new['meshes'][node['mesh']]
        assert not mesh.get('weights') and not mesh.get('extras',{}).get('targetNames'), 'No baked emotion or live morph'
        eyes = []
        for primitive in mesh['primitives']:
            assert not primitive.get('targets')
            values = {key: accessor(new,after,value) for key,value in primitive['attributes'].items()}
            for key in ('POSITION','NORMAL','TEXCOORD_0','WEIGHTS_0'): assert np.isfinite(values[key]).all()
            assert np.allclose(values['WEIGHTS_0'].sum(1),1,atol=1e-6)
            assert values['JOINTS_0'].max() < len(new['skins'][node['skin']]['joints'])
            material = new['materials'][primitive['material']]
            if 'eyewhite' in material['name'].lower(): eyes.extend(values['POSITION'].ravel().tolist())
            triangles += new['accessors'][primitive['indices']]['count']//3
        assert eyes
        eye_shapes.append(tuple(eyes))
    assert len(set(eye_shapes)) == 4, 'Four real eye geometries, not repeated options'
    meta = json.loads(paths['json'].read_text(encoding='utf-8'))
    expected = json.loads((OUT/'baseline'/f'{stem}.json').read_text(encoding='utf-8'))
    expected['parts']['face'] += [n['name'] for n in added]
    expected['neutral_faces'] = meta['neutral_faces']
    assert meta == expected and len(meta['parts']['face']) == 8
    return {'sex':sex,'final':final,'added_meshes':4,'triangles':triangles,'old_binary_bytes_preserved':len(before),
            'old_meshes_preserved':len(old['meshes']),'old_animations_preserved':len(old['animations']),
            'sha256':{ext:publication.digest(path) for ext,path in paths.items()}}


if __name__ == '__main__':
    final = '--final' in sys.argv
    report = [check(sex,final) for sex in ('male','female')]
    (OUT/('formal_contract.json' if final else 'candidate_contract.json')).write_text(json.dumps(report,indent=2))
    if '--publish' in sys.argv:
        assert not final
        publication.OUT = OUT
        publication.WORK = WORK
        publication.publish(report,'neutral_faces')
    print('NEUTRAL_FACES_ASSET_PASS',json.dumps(report),flush=True)
