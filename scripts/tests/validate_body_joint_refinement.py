"""Prove local joint-only geometry changes and exact unrelated GLB preservation."""
import json
import sys
from pathlib import Path
import numpy as np
from validate_chinese_cloak_assets import read_glb, accessor

ROOT = Path(__file__).resolve().parents[2]


def check(sex, destination=None, with_lining_armor_fit=False):
    stem = f'standard_anime_{sex}_character_pack'
    before, bb = read_glb(ROOT / f'.godot-temp/joint_refinement/baseline/{stem}.glb')
    destination = destination or ROOT / f'assets/characters/human/q35/joint_refinement/candidate_{sex}.glb'
    after, ab = read_glb(destination)
    if with_lining_armor_fit:
        from validate_lining_armor_fit import check as check_lining_armor_fit
        check_lining_armor_fit(sex,destination)
    for key in ('nodes', 'skins', 'animations', 'materials', 'textures', 'images'):
        assert before[key] == after[key], (sex, key)
    assert ab[:len(bb)] == bb, 'Original geometry, textures, rig and animation bytes must remain untouched'
    report = {'sex': sex, 'source': str(destination), 'preserved_meshes': 0, 'preserved_animations': len(before['animations']), 'bodies': []}
    for node in before['nodes']:
        if 'mesh' not in node:
            continue
        old_mesh, new_mesh = before['meshes'][node['mesh']], after['meshes'][node['mesh']]
        if not node['name'].startswith('Body_Standard_'):
            if with_lining_armor_fit and (node['name'].startswith(('Armor_Iron_01_Bracer','Armor_Mingguang_01_Bracer')) or node['name'] == 'Outfit_Chinese_Lining_01_Shirt'):
                continue
            from repair_morph_uv_assets import mesh_without_added_uv
            assert old_mesh == mesh_without_added_uv(old_mesh,new_mesh,after,ab), (sex, node['name'])
            report['preserved_meshes'] += 1
            continue
        skin = before['skins'][node['skin']]
        matrices = accessor(before, bb, skin['inverseBindMatrices'])
        centers = [(np.linalg.inv(m.reshape(4,4).T)[:3,3], .075 if before['nodes'][j]['name'].endswith('LowerArm') else .037)
                   for j,m in zip(skin['joints'], matrices) if before['nodes'][j]['name'] in [f'J_Bip_{side}_{joint}' for side in ['L','R'] for joint in ['LowerArm','Hand']]]
        old_triangles = new_triangles = 0
        max_normal_roundtrip = 0.0
        for p,q in zip(old_mesh['primitives'], new_mesh['primitives']):
            old_triangles += len(accessor(before,bb,p['indices']))//3
            new_triangles += len(accessor(after,ab,q['indices']))//3
            x = {k: accessor(before,bb,v) for k,v in p['attributes'].items()}
            y = {k: accessor(after,ab,v) for k,v in q['attributes'].items()}
            assert np.allclose(x['POSITION'].min(0),y['POSITION'].min(0),atol=1e-7)
            assert np.allclose(x['POSITION'].max(0),y['POSITION'].max(0),atol=1e-7)
            assert np.isfinite(y['POSITION']).all()
            assert np.allclose(y['WEIGHTS_0'].sum(1),1,atol=1e-6)
            assert (y['WEIGHTS_0'] >= 0).all()
            lookup = {}
            for i,co in enumerate(y['POSITION']):
                lookup.setdefault(tuple(co), []).append(i)
            for i,co in enumerate(x['POSITION']):
                matches = lookup.get(tuple(co), [])
                assert matches, (sex,node['name'],'original vertex moved',i)
                matches = [j for j in matches if np.allclose(x['TEXCOORD_0'][i],y['TEXCOORD_0'][j],atol=1e-7)]
                assert matches, (sex,node['name'],'original UV moved',i)
                # One boundary triangle may share a changed normal with the joint.
                local = any(abs(abs(co[0])-abs(c[0])) < width+.04 and abs(co[1]-c[1]) < .09 for c,width in centers)
                if not local:
                    error = min(np.linalg.norm(x['NORMAL'][i]-y['NORMAL'][j]) for j in matches)
                    max_normal_roundtrip = max(max_normal_roundtrip,float(error))
                    # Blender stores split normals as quantized angles; tolerate <0.03 degrees.
                    assert error < .0005, (sex,node['name'],'nonlocal normal',co,error)
                    weights = {int(j):float(w) for j,w in zip(x['JOINTS_0'][i],x['WEIGHTS_0'][i]) if w>1e-7}
                    def equal_weights(j):
                        candidate = {int(k):float(w) for k,w in zip(y['JOINTS_0'][j],y['WEIGHTS_0'][j]) if w>1e-7}
                        return weights.keys() == candidate.keys() and all(abs(w-candidate[k]) < 1e-6 for k,w in weights.items())
                    assert any(equal_weights(j) for j in matches), (sex,node['name'],'nonlocal weights',i)
        assert new_triangles > old_triangles
        report['bodies'].append({'name':node['name'],'triangles_before':old_triangles,'triangles_after':new_triangles,'max_outer_normal_roundtrip_error':max_normal_roundtrip})
    print('BODY_JOINT_CONTRACT_PASS',json.dumps(report))
    return report


if __name__ == '__main__':
    reports = [check(sex, ROOT/f'assets/characters/human/q35/standard_anime_{sex}_character_pack.glb' if '--final' in sys.argv else None, '--with-lining-armor-fit' in sys.argv) for sex in ['male','female']]
    (ROOT/'.godot-temp/joint_refinement/contract.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
