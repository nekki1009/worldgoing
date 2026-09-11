"""Assert eight real styles, normalized skinning and exact unrelated preservation."""
import json
import sys
from pathlib import Path
import numpy as np
from validate_chinese_cloak_assets import read_glb, accessor

ROOT = Path(__file__).resolve().parents[2]


def check(sex, final=False):
    stem = f'standard_anime_{sex}_character_pack'
    baseline = ROOT/f'.godot-temp/hair_gendered/baseline/{stem}.glb'
    destination = ROOT/f'assets/characters/human/q35/{stem}.glb' if final else ROOT/f'assets/characters/human/q35/hair_gendered/candidate_{sex}.glb'
    before, bb = read_glb(baseline)
    after, ab = read_glb(destination)
    assert ab[:len(bb)] == bb, 'All previous geometry, textures, skin and animation bytes must remain exact'
    for key in ['skins','animations','textures','images','meshes','materials','accessors','bufferViews']:
        assert after[key][:len(before[key])] == before[key], (sex,key)
    for old,new in zip(before['nodes'],after['nodes']):
        assert {k:v for k,v in old.items() if k != 'children'} == {k:v for k,v in new.items() if k != 'children'}, (sex,old['name'])
        assert new.get('children',[])[:len(old.get('children',[]))] == old.get('children',[])
    prefixes = [('Hair_Long_' if sex == 'female' else 'Hair_Short_')+f'{i:02d}' for i in range(1,5)]
    prefixes += [('Hair_Female_' if sex == 'female' else 'Hair_Male_')+f'{i:02d}' for i in range(5,9)]
    assert all(any(n.get('name') == p and 'mesh' in n for n in after['nodes']) for p in prefixes)
    added = after['nodes'][len(before['nodes']):]
    assert len(added) == (8 if sex == 'female' else 5)
    triangles = 0
    for node in added:
        assert node['name'].startswith(tuple(prefixes[4:])), node['name']
        for p in after['meshes'][node['mesh']]['primitives']:
            a = {k:accessor(after,ab,v) for k,v in p['attributes'].items()}
            assert np.isfinite(a['POSITION']).all()
            assert np.isfinite(a['NORMAL']).all()
            assert np.isfinite(a['TEXCOORD_0']).all()
            assert (a['WEIGHTS_0'] >= 0).all() and np.allclose(a['WEIGHTS_0'].sum(1),1,atol=1e-6)
            joints = [after['nodes'][i]['name'] for i in after['skins'][node['skin']]['joints']]
            assert all(joints[int(j)] in ['J_Bip_C_Head','J_Bip_C_UpperChest'] for row,weights in zip(a['JOINTS_0'],a['WEIGHTS_0']) for j,w in zip(row,weights) if w > 1e-6)
            triangles += after['accessors'][p['indices']]['count']//3
    return {'sex':sex,'styles':8,'added_meshes':len(added),'added_triangles':triangles,'preserved_meshes':len(before['meshes']),'preserved_animations':len(before['animations']),'original_binary_bytes_preserved':len(bb)}


if __name__ == '__main__':
    reports = [check(sex,'--final' in sys.argv) for sex in ['male','female']]
    (ROOT/'.godot-temp/hair_gendered/contract.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
    print('GENDERED_HAIR_ASSET_CONTRACT_PASS',json.dumps(reports))
