"""Non-target bytes/descriptors stay immutable; new geometry is weighted and IRON."""
import json
import sys
from pathlib import Path
import numpy as np
from validate_chinese_cloak_assets import read_glb, accessor

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'.godot-temp/western_plate_20260913/baseline'
WORK=ROOT/'.godot-temp/western_plate_20260913/candidate'
PREFIXES=('Armor_Western_Iron_01_','Helmet_Western_Iron_01_','Boots_Western_Iron_01_')


def check(sex, formal=False):
    destination=ROOT/f'assets/characters/human/q35/standard_anime_{sex}_character_pack.glb' if formal else WORK/f'{sex}.glb'
    if formal and json.loads(destination.with_suffix('.json').read_text(encoding='utf-8')).get('crossbow_idle_stance'):
        from crossbow_stance_files_test import check as check_crossbow, BASE as CROSSBOW_BASE
        check_crossbow(sex, formal=True)
        destination=CROSSBOW_BASE/f'standard_anime_{sex}_character_pack.glb'
    before, old=read_glb(BASE/f'standard_anime_{sex}_character_pack.glb')
    after, binary=read_glb(destination)
    assert binary[:len(old)]==old,'Original binary changed'
    for key in ['meshes','accessors','bufferViews','materials']:
        assert after[key][:len(before[key])]==before[key],key
    for key in ['skins','scenes']:
        assert after[key]==before[key],key
    assert len(after['animations'])==len(before['animations'])
    corrected=set()
    for old_clip,new_clip in zip(before['animations'],after['animations']):
        if sex!='male' or old_clip['name']!='attack_axe':
            assert old_clip==new_clip,old_clip['name']
            continue
        assert old_clip['name']==new_clip['name']
        assert new_clip['samplers'][:len(old_clip['samplers'])]==old_clip['samplers']
        assert len(old_clip['channels'])==len(new_clip['channels'])
        for original,current in zip(old_clip['channels'],new_clip['channels']):
            assert original['target']==current['target']
            if original==current:continue
            target=current['target']
            name=after['nodes'][target['node']]['name']
            assert name in ['J_Bip_L_LowerArm','J_Bip_L_Hand'],name
            corrected.add(name)
            output=accessor(after,binary,new_clip['samplers'][current['sampler']]['output'])
            if target['path']!='rotation':
                expected=before['nodes'][target['node']].get(target['path'],[1,1,1] if target['path']=='scale' else [0,0,0])
                assert np.allclose(output,expected,atol=2e-6),(name,target['path'])
        assert corrected=={'J_Bip_L_LowerArm','J_Bip_L_Hand'},corrected
    for i,node in enumerate(before['nodes']):
        added=dict(after['nodes'][i])
        if 'children' in added:
            added['children']=[c for c in added['children'] if c<len(before['nodes'])]
        assert added==node,node['name']
    additions=after['nodes'][len(before['nodes']):]
    assert additions and all(n['name'].startswith(PREFIXES) for n in additions)
    triangles=0
    for node in additions:
        assert node['skin']==0,node['name']
        for p in after['meshes'][node['mesh']]['primitives']:
            a=p['attributes']
            assert {'POSITION','NORMAL','TEXCOORD_0','JOINTS_0','WEIGHTS_0'}<=a.keys(),node['name']
            for index in a.values():assert np.isfinite(accessor(after,binary,index)).all(),node['name']
            weights=accessor(after,binary,a['WEIGHTS_0'])
            assert (weights>=0).all() and np.allclose(weights.sum(axis=1),1,atol=2e-5),node['name']
            joints=accessor(after,binary,a['JOINTS_0'])
            used={after['nodes'][after['skins'][0]['joints'][int(j)]]['name'] for j in joints[weights>1e-6]}
            if 'Cuirass' in node['name']:
                assert all(name.startswith('J_Bip_C_') for name in used),(node['name'],used)
            if node['name'].startswith('Boots_Western_Iron_01_'):
                side='L' if '_L' in node['name'].removeprefix('Boots_Western_Iron_01_') else 'R'
                assert all('_'+side+'_' in name for name in used),(node['name'],used)
            triangles+=len(accessor(after,binary,p['indices']))//3
            material=after['materials'][p['material']]
            assert 'Steel' not in material.get('name',''),material
    for prefix in PREFIXES:assert any(n['name'].startswith(prefix) for n in additions)
    report={'sex':sex,'formal':formal,'new_mesh_nodes':len(additions),'new_triangles':triangles,'old_nodes_preserved':len(before['nodes']),'old_clips_preserved':len(before['animations'])-int(bool(corrected)),'male_attack_axe_corrected_bones':sorted(corrected)}
    print('WESTERN_IRON_FILES_PASS',json.dumps(report))
    return report


if __name__=='__main__':
    reports=[check(sex,'--formal' in sys.argv) for sex in ['male','female']]
    (ROOT/'output/western_plate_20260913'/('formal_files.json' if '--formal' in sys.argv else 'candidate_files.json')).write_text(json.dumps(reports,indent=2),encoding='utf-8')
