"""Verify append-only mounted clips, skeletal anchors and every morph sampler."""
import hashlib
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts/tools/blender'))
from append_mounted_animations import CLIPS, floats, read_glb


def channels(doc, animation):
    return {(doc['nodes'][c['target']['node']]['name'], c['target']['path']): animation['samplers'][c['sampler']]
            for c in animation['channels']}


def values(doc, binary, sampler):
    rows = floats(doc, binary, sampler['output'])
    return rows[1::3] if sampler.get('interpolation') == 'CUBICSPLINE' else rows


def check(sex):
    base = ROOT / 'output/equipment_matrix_20260918/baseline'
    out = ROOT / 'output/equipment_matrix_20260918/mounted'
    source = base / f'standard_anime_{sex}_character_pack.glb'
    before, bb = read_glb(source)
    after, ab = read_glb(out / f'candidate_{sex}.glb')
    # All old clip metadata/channel/sampler/accessor indices AND their bytes.
    assert ab[:len(bb)] == bb, 'Original BIN bytes changed'
    assert after['animations'][:len(before['animations'])] == before['animations']
    for key, val in before.items():
        if key in ('buffers', 'animations'):
            continue
        if key in ('accessors', 'bufferViews'):
            assert after[key][:len(val)] == val, key
        else:
            assert after[key] == val, key
    assert {a['name'] for a in after['animations'][len(before['animations']):]} == set(CLIPS)
    idle = next(a for a in before['animations'] if a['name'] == 'ride_idle')
    idle_channels = channels(before, idle)
    lower = {'J_Bip_C_Hips'} | {n['name'] for n in before['nodes'] if any(p in n['name'] for p in ('UpperLeg', 'LowerLeg', 'Foot', 'ToeBase'))}
    report = {'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'old_animation_count': len(before['animations']),
              'original_binary_bytes_preserved': len(bb), 'clips': {}}
    for animation in after['animations'][-2:]:
        name = animation['name']
        current = channels(after, animation)
        length = 70 / 24 if name == 'ride_heavy' else .4
        weight_count, locked_count = 0, 0
        for (node, prop), sampler in current.items():
            times = [r[0] for r in floats(after, ab, sampler['input'])]
            assert times[0] == 0 and abs(times[-1] - length) < 1e-6, (name, node, times[-1], length)
            assert all(a < b for a, b in zip(times, times[1:])), (name, node, 'time order')
            rows = floats(after, ab, sampler['output'])
            assert all(math.isfinite(v) for row in rows for v in row)
            if prop == 'weights':
                weight_count += 1
                ni = next(i for i, n in enumerate(after['nodes']) if n['name'] == node)
                width = len(after['meshes'][after['nodes'][ni]['mesh']]['primitives'][0]['targets'])
                factor = 3 if sampler.get('interpolation') == 'CUBICSPLINE' else 1
                assert len(rows) == len(times) * width * factor, (name, node, 'weight count')
                if node.startswith('Weapon_'):
                    assert all(r[0] == 0 for r in rows), 'Generic heavy cannot fire/draw bow'
                elif (node, prop) in idle_channels:
                    old = idle_channels[node, prop]
                    assert sampler['output'] == old['output'], (name, node, 'must reuse actual old sampler output')
                    assert floats(before, bb, old['output']) == rows
                    old_times = [r[0] for r in floats(before, bb, old['input'])]
                    assert all(abs(t - old_times[i] / old_times[-1] * length) < 1e-6 for i, t in enumerate(times))
                continue
            if node in lower:
                locked_count += 1
                vals = values(after, ab, sampler)
                assert all(max(abs(v - w) for v, w in zip(vals[0], row)) < 1e-6 for row in vals), (name, node, 'lower motion')
                if (node, prop) in idle_channels:
                    expected = values(before, bb, idle_channels[node, prop])[0]
                    difference = max(abs(v - w) for v, w in zip(vals[0], expected))
                    if prop == 'rotation':
                        difference = min(difference, max(abs(v + w) for v, w in zip(vals[0], expected)))
                    assert difference < 1e-5, (name, node, prop, 'original ride anchor', difference)
        spine = values(after, ab, current['J_Bip_C_Chest', 'rotation'])
        assert max(max(abs(v - w) for v, w in zip(spine[0], row)) for row in spine) > .1
        required_morphs = {key for a in before['animations'] for key in channels(before, a) if key[1] == 'weights'}
        assert required_morphs <= set(current), 'Stale morph possible when switching clips'
        assert weight_count > 0 and locked_count >= 9
        report['clips'][name] = {'seconds': length, 'weight_channels': weight_count, 'locked_channels': locked_count}
    return report


if __name__ == '__main__':
    report = {sex: check(sex) for sex in ('male', 'female')}
    (ROOT / 'output/equipment_matrix_20260918/mounted/assets_contract.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('MOUNTED_ASSETS_CONTRACT_PASS', json.dumps(report, indent=2))
