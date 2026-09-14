"""Preserve geometry and every animation channel except the scoped stance."""
import hashlib
import json
import sys
from pathlib import Path
import numpy as np
from validate_chinese_cloak_assets import read_glb, accessor

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / '.godot-temp/crossbow_stance_20260914/baseline'
WORK = ROOT / '.godot-temp/crossbow_stance_20260914/candidate'
LOWER = ['J_Bip_C_Hips'] + ['J_Bip_' + side + '_' + part
    for side in ['L', 'R'] for part in ['UpperLeg', 'LowerLeg', 'Foot', 'ToeBase']]
CHANGED = set(LOWER + ['J_Bip_C_Spine'])


def check(sex, formal=False):
    stem = f'standard_anime_{sex}_character_pack'
    destination = ROOT / 'assets/characters/human/q35' / (stem + '.glb') if formal else WORK / (sex + '.glb')
    before, old = read_glb(BASE / (stem + '.glb'))
    after, data = read_glb(destination)
    assert data[:len(old)] == old
    for key in before.keys() - {'animations', 'accessors', 'bufferViews', 'buffers'}:
        assert before[key] == after[key], (sex, key)
    for key in ['accessors', 'bufferViews']:
        assert before[key] == after[key][:len(before[key])], key
    assert len(before['animations']) == len(after['animations'])
    changed = set()
    for a, b in zip(before['animations'], after['animations']):
        if a['name'] != 'attack_crossbow':
            assert a == b, (sex, a['name'])
            continue
        assert {k: v for k, v in a.items() if k not in ['samplers', 'channels']} == {k: v for k, v in b.items() if k not in ['samplers', 'channels']}
        assert a['samplers'] == b['samplers'][:len(a['samplers'])]
        original_channels = {(c['target']['node'], c['target']['path']): c for c in a['channels']}
        for channel in b['channels']:
            name = after['nodes'][channel['target']['node']]['name']
            key = (channel['target']['node'], channel['target']['path'])
            if channel != original_channels.get(key):
                assert name in CHANGED, (sex, name)
                changed.add(name)
            sampler = b['samplers'][channel['sampler']]
            assert np.isfinite(accessor(after, data, sampler['output'])).all()
        assert set(original_channels) <= {(c['target']['node'], c['target']['path']) for c in b['channels']}
    assert set(LOWER) <= changed and changed <= CHANGED
    report = {'sex': sex, 'formal': formal, 'changed_bones': sorted(changed),
        'unchanged_other_clips': len(after['animations']) - 1,
        'original_meshes_preserved': len(before['meshes']),
        'sha256': hashlib.sha256(destination.read_bytes()).hexdigest()}
    print('CROSSBOW_STANCE_FILES_PASS', json.dumps(report))
    return report


if __name__ == '__main__':
    reports = [check(sex, '--formal' in sys.argv) for sex in ['male', 'female']]
    output = ROOT / 'output/crossbow_stance_20260914'
    output.mkdir(parents=True, exist_ok=True)
    (output / ('formal_files.json' if '--formal' in sys.argv else 'candidate_files.json')).write_text(json.dumps(reports, indent=2), encoding='utf-8')
