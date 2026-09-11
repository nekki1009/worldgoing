"""Only twelve bracers and one additive shirt morph may differ from baseline."""
import copy
import json
import sys
from pathlib import Path
import numpy as np
from validate_chinese_cloak_assets import read_glb, accessor

ROOT = Path(__file__).resolve().parents[2]
PREFIXES = ('Armor_Iron_01_Bracer','Armor_Mingguang_01_Bracer')


def check(sex, destination=None):
    stem = f'standard_anime_{sex}_character_pack'
    before,bb = read_glb(ROOT/f'.godot-temp/lining_armor_overlap/baseline/{stem}.glb')
    destination = destination or ROOT/f'assets/characters/human/q35/lining_armor_fit/candidate_{sex}.glb'
    after,ab = read_glb(destination)
    for key in ('nodes','skins','animations','materials','textures','images'):
        assert before[key] == after[key], (sex,key)
    assert ab[:len(bb)] == bb, 'Original data bytes must remain intact'
    changed = []
    preserved = 0
    for node in before['nodes']:
        if 'mesh' not in node:
            continue
        old,new = before['meshes'][node['mesh']],after['meshes'][node['mesh']]
        if node['name'] == 'Outfit_Chinese_Lining_01_Shirt':
            stripped = copy.deepcopy(new)
            assert stripped['extras']['targetNames'].pop() == 'UnderHardArmor'
            assert stripped['weights'].pop() == 0.0
            old_index = old['extras']['targetNames'].index('UnderArmor')
            for p,q in zip(old['primitives'],stripped['primitives']):
                hard = q['targets'].pop()
                assert set(hard) <= {'POSITION','NORMAL','TANGENT'} and 'POSITION' in hard
                positions = accessor(before,bb,p['attributes']['POSITION'])
                front = np.clip((.02+positions[:,2])/.04,0,1)
                expected = accessor(before,bb,p['targets'][old_index]['POSITION'])*(.3+.6*front[:,None])
                assert np.allclose(accessor(after,ab,hard['POSITION']),expected,atol=1e-6)
                assert all(np.isfinite(accessor(after,ab,v)).all() for v in hard.values())
            assert stripped == old, 'Standalone shirt and leather morph changed'
            continue
        if not node['name'].startswith(PREFIXES):
            from repair_morph_uv_assets import mesh_without_added_uv
            assert old == mesh_without_added_uv(old,new,after,ab), (sex,node['name'])
            preserved += 1
            continue
        assert len(old['primitives']) == len(new['primitives'])
        for p,q in zip(old['primitives'],new['primitives']):
            assert p['material'] == q['material']
            straps = '_Straps_' in node['name']
            assert set(q['attributes'])-set(p['attributes']) <= ({'TEXCOORD_0'} if straps else set())
            x = accessor(before,bb,p['attributes']['POSITION'])
            y = accessor(after,ab,q['attributes']['POSITION'])
            assert np.isfinite(y).all()
            # Hard plates keep topology and axial length. Soft straps gain
            # conformal cloth geometry/UVs but may use only existing arm bones.
            if straps:
                assert abs(x[:,0].min()-y[:,0].min()) < .0002 and abs(x[:,0].max()-y[:,0].max()) < .0002
                assert len(accessor(after,ab,q['indices'])) < 12000
            else:
                assert x.shape == y.shape
                assert np.allclose(np.sort(x[:,0]),np.sort(y[:,0]),atol=1e-6)
                assert len(accessor(before,bb,p['indices'])) == len(accessor(after,ab,q['indices']))
            for primitive,doc,data in [(p,before,bb),(q,after,ab)]:
                joints = accessor(doc,data,primitive['attributes']['JOINTS_0'])
                weights = accessor(doc,data,primitive['attributes']['WEIGHTS_0'])
                assert np.allclose(weights.sum(1),1,atol=1e-6)
                active = np.unique(joints[weights>1e-7])
                skin = doc['skins'][node['skin']]
                expected = ['J_Bip_'+node['name'][-1]+'_'+joint for joint in (['UpperArm','LowerArm','Hand'] if straps else ['LowerArm'])]
                assert all(doc['nodes'][skin['joints'][int(i)]]['name'] in expected for i in active)
            normals = accessor(after,ab,q['attributes']['NORMAL'])
            assert np.isfinite(normals).all() and np.allclose(np.linalg.norm(normals,axis=1),1,atol=1e-5)
        changed.append(node['name'])
    assert len(changed) == 12
    report = {'sex':sex,'source':str(destination),'fitted_meshes':changed,'preserved_meshes':preserved,'preserved_animations':len(after['animations'])}
    print('LINING_ARMOR_FIT_CONTRACT_PASS',json.dumps(report))
    return report


if __name__ == '__main__':
    report = [check(sex,ROOT/f'assets/characters/human/q35/standard_anime_{sex}_character_pack.glb' if '--final' in sys.argv else None) for sex in ['male','female']]
    (ROOT/'.godot-temp/lining_armor_overlap/contract.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
