"""Byte-preservation and numeric motion report for the scoped weapon refresh."""
import hashlib
import copy
import json
import sys
from pathlib import Path
import numpy as np
from validate_chinese_cloak_assets import read_glb, accessor

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / '.godot-temp/weapon_refresh_20260913'
FORMAL = ROOT / 'assets/characters/human/q35'
PARTS = {'Weapon_Axe_01_' + n for n in ['Haft','Grip','Grip_Wrap','Blade','Holstered_Haft','Holstered_Blade']}
LEFT = {'J_Bip_L_'+n for n in ['UpperArm','LowerArm','Hand']}
RIGHT = {'J_Bip_R_'+n for n in ['UpperArm','LowerArm','Hand']}
CHANGED = {'attack_spear': LEFT | RIGHT, 'attack_axe': LEFT}


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def check(sex, formal=True):
    baseline = WORK / 'baseline' / sex
    candidate = FORMAL / f'standard_anime_{sex}_character_pack' if formal else WORK / 'candidate' / sex
    published = candidate
    if formal and json.loads(candidate.with_suffix('.json').read_text(encoding='utf-8')).get('western_plate'):
        # Prove the newer additive stage first, then audit the immutable
        # weapon-refresh output it was based on. Neither check is skipped.
        from western_iron_files_test import check as check_western_iron, BASE as WESTERN_BASE
        check_western_iron(sex, formal=True)
        candidate = WESTERN_BASE / f'standard_anime_{sex}_character_pack'
    before, raw = read_glb(baseline.with_suffix('.glb'))
    after, binary = read_glb(candidate.with_suffix('.glb'))
    assert binary[:len(raw)] == raw
    for key in ['skins','textures','images','scenes','samplers']:
        assert before.get(key) == after.get(key), (sex,key)
    expected_nodes = copy.deepcopy(before['nodes'])
    expected_old_meshes = []
    for index, old in enumerate(before['nodes']):
        if old.get('name') not in PARTS:
            continue
        node = copy.deepcopy(old)
        node['name'] = node['name'].replace('Weapon_Axe_01_', 'Weapon_WoodAxe_01_', 1)
        node['mesh'] = len(before['meshes']) + len(expected_old_meshes)
        expected_old_meshes.append(before['meshes'][old['mesh']])
        parent = next(i for i, n in enumerate(before['nodes']) if index in n.get('children', []))
        expected_nodes[parent]['children'].append(len(expected_nodes))
        expected_nodes.append(node)
    assert after['nodes'] == expected_nodes, (sex, 'only six logging axe nodes may be appended')
    assert after['meshes'][len(before['meshes']):] == expected_old_meshes, (sex, 'logging axe must reuse original mesh descriptors')
    for key in ['materials','accessors','bufferViews']:
        assert before[key] == after[key][:len(before[key])], (sex,key)
    changed_meshes = {n['mesh'] for n in before['nodes'] if n.get('name') in PARTS}
    assert len(changed_meshes) == 6 and len(before['meshes']) + 6 == len(after['meshes'])
    for index, mesh in enumerate(before['meshes']):
        assert (mesh != after['meshes'][index]) == (index in changed_meshes), (sex,index)
    assert len(before['animations']) == len(after['animations'])
    for old, new in zip(before['animations'],after['animations']):
        assert old['name'] == new['name']
        if old['name'] not in CHANGED:
            assert old == new, (sex,old['name'])
            continue
        assert old['samplers'] == new['samplers'][:len(old['samplers'])]
        for channel in new['channels'][len(old['channels']):]:
            target = channel['target']
            assert before['nodes'][target['node']]['name'] in CHANGED[old['name']]
            assert target['path'] in ['translation','scale']
            values = accessor(after,binary,new['samplers'][channel['sampler']]['output'])
            expected = before['nodes'][target['node']].get(target['path'], [1,1,1] if target['path'] == 'scale' else [0,0,0])
            assert np.allclose(values,expected,atol=2e-6), (sex,old['name'],target)
        for a,b in zip(old['channels'],new['channels']):
            name = before['nodes'][a['target']['node']]['name']
            assert a['target'] == b['target']
            if name not in CHANGED[old['name']]:
                assert a == b, (sex,old['name'],name)
        duration = lambda doc, blob, clip: max(float(accessor(doc,blob,s['input']).max()) for s in clip['samplers'])
        assert abs(duration(before,raw,old)-duration(after,binary,new)) < 1e-5
    hashes = {ext:sha(published.with_suffix('.'+ext)) for ext in ['blend','glb','json']}
    metadata = json.loads(candidate.with_suffix('.json').read_text(encoding='utf-8'))
    assert metadata['weapon_refresh']['preserved_logging_axe']['id'] == 'wood_axe_01'
    assert all(name.replace('Weapon_Axe_01_', 'Weapon_WoodAxe_01_', 1) in metadata['parts']['weapon'] for name in PARTS)
    print('WEAPON_REFRESH_PRESERVATION_PASS',sex,'6 new battle meshes; 6 original logging meshes; spear 6 arm bones; axe 3 offhand bones; other bytes unchanged',hashes)
    return hashes


if __name__ == '__main__':
    formal = '--candidate' not in sys.argv
    report = {sex:check(sex,formal) for sex in ['male','female']}
    out = ROOT/'output/weapon_refresh_20260913'
    (out/('formal_hashes.json' if formal else 'candidate_hashes.json')).write_text(json.dumps(report,indent=2),encoding='utf-8')
