"""Strict native candidate audit and opt-in source-only atlas publication.

Default publication CLI is PREVIEW ONLY. --native-only needs no GPU evidence.
Original publisher transaction/parent ordering is reused without changing its
default task semantics. This module never imports Blender or trusts build flags.
"""
import argparse
import copy
import sys
import numpy as np
import steel_walk_atlas_provenance as audit
import publish_equipment_walk_atlas as publisher
from validate_chinese_cloak_assets import read_glb, accessor

STEEL = {f'Armor_Western_Steel_01_Cuisse_{side}{suffix}'
         for side in ('L', 'R') for suffix in ('', '_RolledEdge')} | {
    'Armor_Chinese_Steel_01_Tasset_' + suffix
    for suffix in ('Front', 'Front_Gold', 'Side_L', 'Side_R', 'Side_Gold_L', 'Side_Gold_R')}
MING = {'Armor_Mingguang_01_' + suffix for suffix in (
    'PleatedSkirt', 'Pteruges_Front', 'Pteruges_Silver', 'Pteruges_Studs',
    'Skirt_Rear', 'Skirt_Rear_Rim', 'Skirt_Side_L', 'Skirt_Rim_L', 'Skirt_Side_R', 'Skirt_Rim_R')}
OLD_COUNT, ADDED = 280, 67
NAMES = [f'WalkClearance_{i:03d}' for i in range(ADDED)]
audit.EDITOR = audit.a.EDITOR


def require(ok, message):
    if not ok:
        raise ValueError(message)


def padded(old, new, label):
    require(len(old) == OLD_COUNT and len(new) == OLD_COUNT + ADDED, label + ': count')
    require(new[:OLD_COUNT] == old and new[OLD_COUNT:] == [0] * ADDED, label + ': nonzero/changed defaults')


def validate_documents(old, ob, new, nb):
    require(set(old) == set(new), 'GLB root keys changed')
    require(nb[:len(ob)] == ob, 'Original binary prefix changed')
    for key in old:
        if key not in ('meshes', 'nodes', 'animations', 'accessors', 'bufferViews', 'buffers'):
            require(new[key] == old[key], 'Unrelated root field: ' + key)
    for key in ('accessors', 'bufferViews'):
        require(new[key][:len(old[key])] == old[key], 'Original ' + key + ' changed')
    buffers = copy.deepcopy(new['buffers'])
    require(len(buffers) == len(old['buffers']) == 1, 'Buffer count')
    require(buffers[0]['byteLength'] == len(nb), 'Buffer size mismatch')
    buffers[0]['byteLength'] = old['buffers'][0]['byteLength']
    require(buffers == old['buffers'], 'Buffer metadata changed')
    for view in new['bufferViews'][len(old['bufferViews']):]:
        start = view.get('byteOffset', 0)
        require(view['buffer'] == 0 and start >= len(ob) and view['byteLength'] > 0
                and start + view['byteLength'] <= len(nb), 'Appended bufferView out of bounds')
    require(len(old['nodes']) == len(new['nodes']) and len(old['meshes']) == len(new['meshes']), 'Node/mesh count')
    named = {n['name']: (i, n) for i, n in enumerate(old['nodes']) if 'mesh' in n}
    require(STEEL | MING <= named.keys(), 'Missing explicitly allowed meshes')
    allowed_indices = {named[n][1]['mesh']: n for n in STEEL | MING}
    require(len(allowed_indices) == 20, 'Allowed meshes aliased')
    require(all(n.get('mesh') not in allowed_indices or n.get('name') in STEEL | MING
                for n in old['nodes']), 'Changed mesh used by unrelated node')
    ming_nodes = {named[n][0] for n in MING}
    for i, (x, y) in enumerate(zip(old['nodes'], new['nodes'])):
        y = copy.deepcopy(y)
        if i in ming_nodes and 'weights' in x:
            padded(x['weights'], y['weights'], 'Node defaults')
            y['weights'] = x['weights']
        require(x == y, 'Node changed beyond permitted zero padding: ' + str(i))
    changed = []
    for i, (x, y) in enumerate(zip(old['meshes'], new['meshes'])):
        if i not in allowed_indices:
            require(x == y, 'Unrelated mesh changed: ' + str(i))
            continue
        name = allowed_indices[i]
        require(x != y, 'Expected target mesh unchanged: ' + name)
        changed.append(name)
        normalized = copy.deepcopy(y)
        require(len(x['primitives']) == len(y['primitives']), 'Primitive count: ' + name)
        if name in MING:
            require(len(x['extras']['targetNames']) == OLD_COUNT, 'Original target names count')
            require(y['extras']['targetNames'] == x['extras']['targetNames'] + NAMES, 'Target names changed')
            normalized['extras']['targetNames'] = x['extras']['targetNames']
            padded(x.get('weights', [0] * OLD_COUNT), y['weights'], 'Mesh defaults')
            if 'weights' in x: normalized['weights'] = x['weights']
            else: normalized.pop('weights')
        for p, q, restored in zip(x['primitives'], y['primitives'], normalized['primitives']):
            if name in STEEL:
                require(set(p['attributes']) == set(q['attributes']), 'Steel attributes changed')
                count = new['accessors'][q['attributes']['POSITION']]['count']
                for semantic, index in q['attributes'].items():
                    data = accessor(new, nb, index)
                    require(index >= len(old['accessors']) and len(data) == count and np.isfinite(data).all(), 'Invalid new steel attributes')
                indices = accessor(new, nb, q['indices'])
                require(q['indices'] >= len(old['accessors']) and indices.size % 3 == 0
                        and indices.min() >= 0 and indices.max() < count, 'Invalid steel indices')
                restored['attributes'], restored['indices'] = p['attributes'], p['indices']
            else:
                require(len(p['targets']) == OLD_COUNT and len(q['targets']) == OLD_COUNT + ADDED
                        and q['targets'][:OLD_COUNT] == p['targets'], 'Original morph targets changed')
                count = old['accessors'][p['attributes']['POSITION']]['count']
                for target in q['targets'][OLD_COUNT:]:
                    require(set(target) == set(p['targets'][0]), 'Appended morph semantics differ')
                    for semantic, index in target.items():
                        data = accessor(new, nb, index)
                        require(index >= len(old['accessors']) and new['accessors'][index]['componentType'] == 5126
                                and data.shape == (count, 3) and np.isfinite(data).all(), 'Invalid appended delta')
                restored['targets'] = p['targets']
        require(normalized == x, 'Mesh metadata/basis/material/old target changed: ' + name)
    require(len(old['animations']) == len(new['animations']), 'Animation count changed')
    padded_channels = appended_channels = 0
    for x, y in zip(old['animations'], new['animations']):
        normalized = copy.deepcopy(y)
        require(y['samplers'][:len(x['samplers'])] == x['samplers'], 'Original samplers changed')
        next_sampler = len(x['samplers'])
        require(len(y['channels']) >= len(x['channels']), 'Original channels removed')
        for p, q in zip(x['channels'], y['channels']):
            target = p['target']
            if target.get('node') not in ming_nodes or target['path'] != 'weights':
                require(p == q, 'Original skeletal/unrelated channel changed')
                continue
            restored = copy.deepcopy(q)
            restored['sampler'] = p['sampler']
            require(restored == p and q['sampler'] == next_sampler, 'Weight channel rerouting mismatch')
            s, t = x['samplers'][p['sampler']], y['samplers'][next_sampler]
            metadata = copy.deepcopy(t); metadata['output'] = s['output']
            require(metadata == s and t['output'] >= len(old['accessors']), 'Padded sampler metadata/input changed')
            require(new['accessors'][t['output']]['type'] == 'SCALAR'
                    and new['accessors'][t['output']]['componentType'] == 5126, 'Padded weights must be float scalars')
            a = accessor(old, ob, s['output']).reshape(-1, OLD_COUNT)
            b = accessor(new, nb, t['output']).reshape(-1, OLD_COUNT + ADDED)
            require(a.shape[0] == b.shape[0] and np.array_equal(a, b[:, :OLD_COUNT])
                    and np.all(b[:, OLD_COUNT:] == 0), 'Existing animation weight values changed')
            factor = 3 if s.get('interpolation') == 'CUBICSPLINE' else 1
            require(len(a) == len(accessor(old, ob, s['input'])) * factor, 'Original weight timing shape')
            next_sampler += 1; padded_channels += 1
        extras = y['channels'][len(x['channels']):]
        if x['name'] == 'walk':
            require(len(extras) == 10 and {c['target']['node'] for c in extras} == ming_nodes, 'Walk needs exactly ten target channels')
            duration = max(float(accessor(old, ob, s['input']).max()) for s in x['samplers'])
            for c in extras:
                require(c == {'sampler': next_sampler, 'target': {'node': c['target']['node'], 'path': 'weights'}}, 'Invalid new walk channel')
                require(not any(p['target'] == c['target'] for p in x['channels']), 'Duplicate old walk weight channel')
                s = y['samplers'][next_sampler]
                require(set(s) == {'input', 'output', 'interpolation'} and s['interpolation'] == 'LINEAR'
                        and s['input'] >= len(old['accessors']) and s['output'] >= len(old['accessors']), 'Invalid new walk sampler')
                require(all(new['accessors'][s[k]]['type'] == 'SCALAR'
                            and new['accessors'][s[k]]['componentType'] == 5126 for k in ('input', 'output')), 'Walk accessor types')
                times = accessor(new, nb, s['input']).ravel()
                weights = accessor(new, nb, s['output']).reshape(ADDED, OLD_COUNT + ADDED)
                require(times.shape == (ADDED,) and np.allclose(times, np.linspace(0, duration, ADDED), atol=1e-7, rtol=0)
                        and np.all(np.diff(times) > 0), 'Walk sample times changed')
                require(np.all(weights[:, :OLD_COUNT] == 0) and np.array_equal(weights[:, OLD_COUNT:], np.eye(ADDED)), 'Walk not zero-old/one-hot-new')
                next_sampler += 1; appended_channels += 1
        else:
            require(not extras, 'Channels appended outside walk')
        require(len(y['samplers']) == next_sampler, 'Unexpected appended sampler')
        normalized['channels'], normalized['samplers'] = x['channels'], x['samplers']
        require(normalized == x, 'Animation metadata changed')
    require(appended_channels == 10 and padded_channels > 0, 'Expected walk/low-pose channels missing')
    return {'changed_mesh_names': sorted(changed), 'steel_meshes': 10, 'mingguang_meshes': 10,
            'preserved_morph_targets_per_mesh': OLD_COUNT, 'appended_targets_per_mesh': ADDED,
            'padded_existing_weight_channels': padded_channels, 'appended_walk_channels': appended_channels,
            'original_binary_bytes_unchanged': len(ob), 'unrelated_meshes_nodes_skeletal_channels_unchanged': True,
            'existing_sampler_prefix_unchanged': True, 'basis_original_targets_and_old_weight_columns_exact': True}


def native_proof(revision, candidate=False, sexes=('male', 'female')):
    require(revision.isalnum(), 'Unsafe revision')
    results = {}
    snapshot = audit.load(audit.OUT / 'snapshot.json')
    for sex in sexes:
        name = f'standard_anime_{sex}_character_pack.glb'
        before = audit.TASK / 'baseline' / name
        candidate_path = audit.TASK / 'combined' / revision / sex / name
        require(audit.record(before) == snapshot['baseline_files'][audit.resource(before)], 'Baseline changed')
        if not candidate:
            require(audit.record(candidate_path) == audit.record(audit.ROOT / 'assets/characters/human/q35' / name), 'Formal differs from validated candidate')
        hashes = [audit.record(before), audit.record(candidate_path)]
        old, ob = read_glb(before); new, nb = read_glb(candidate_path)
        results[sex] = validate_documents(old, ob, new, nb)
        require(hashes == [audit.record(before), audit.record(candidate_path)], 'Files changed during validation')
        results[sex].update(before=hashes[0], after=hashes[1], formal_identical_checked=not candidate)
    require(audit.digest(audit.path(audit.EDITOR)) == snapshot['sources'][audit.EDITOR], 'Editor changed')
    return results


def rejection_checks(revision):
    """Real candidate positive control plus targeted in-memory counterexamples."""
    native_proof(revision, candidate=True)
    name = 'standard_anime_male_character_pack.glb'
    old, ob = read_glb(audit.TASK / 'baseline' / name)
    new, nb = read_glb(audit.TASK / 'combined' / revision / 'male' / name)
    ming_node = next(i for i, n in enumerate(old['nodes']) if n.get('name') in MING)
    mesh = old['nodes'][ming_node]['mesh']
    failures = []

    def reject(label, doc, binary):
        try:
            validate_documents(old, ob, doc, binary)
        except (ValueError, KeyError, IndexError):
            failures.append(label)
            return
        raise ValueError('Counterexample incorrectly accepted: ' + label)

    reject('binary prefix', new, bytes([nb[0] ^ 1]) + nb[1:])
    bad = copy.deepcopy(new); bad['nodes'][ming_node]['translation'] = [999, 0, 0]
    reject('node transform', bad, nb)
    bad = copy.deepcopy(new); bad['meshes'][mesh]['primitives'][0]['targets'][0]['POSITION'] += 1
    reject('original morph accessor', bad, nb)
    bad = copy.deepcopy(new); bad['meshes'][mesh]['weights'][-1] = 1
    reject('nonzero new default', bad, nb)
    bad = copy.deepcopy(new)
    anim = next(a for a in bad['animations'] if a['name'] == 'walk')
    anim['samplers'][0]['interpolation'] = 'STEP'
    reject('original sampler', bad, nb)
    bad = copy.deepcopy(new)
    anim = next(a for a in bad['animations'] if a['name'] == 'walk')
    anim['channels'][-1]['target']['path'] = 'translation'
    reject('new walk channel path', bad, nb)
    padded_channel = next((a, c) for a in new['animations'] for c in a['channels']
                          if c['target'] == {'node': ming_node, 'path': 'weights'} and a['name'] != 'walk')
    anim, channel = padded_channel
    index = anim['samplers'][channel['sampler']]['output']
    bad_binary = bytearray(nb)
    values = accessor(new, bad_binary, index)
    values[0, 0] += 1
    reject('old animation weight column', new, bad_binary)
    require(len(failures) == 7, 'Counterexample coverage')
    target = audit.a.report_path('native_rejection_checks_' + revision)
    audit.write_json(target, {'status': 'NATIVE_POSITIVE_AND_SEVEN_REJECTIONS_PASS', 'published': False, 'rejected': failures})
    print('STEEL_WALK_REJECTION_CHECKS_PASS', audit.resource(target))


if __name__ == '__main__':
    try:
        if '--native-only' in sys.argv or '--self-test' in sys.argv:
            parser = argparse.ArgumentParser(description=__doc__)
            parser.add_argument('--native-only', action='store_true')
            parser.add_argument('--self-test', action='store_true')
            parser.add_argument('--revision', required=True)
            parser.add_argument('--sex', choices=('male', 'female'))
            args = parser.parse_args()
            if args.self_test:
                rejection_checks(args.revision)
                raise SystemExit(0)
            result = native_proof(args.revision, candidate=True, sexes=(args.sex,) if args.sex else ('male', 'female'))
            file = audit.a.report_path('native_proof_' + args.revision)
            audit.write_json(file, {'status': 'NATIVE_SEMANTICS_PASS_NOT_VISUAL_ACCEPTANCE', 'published': False, 'native_preservation': result})
            print('STEEL_WALK_NATIVE_PASS', audit.resource(file))
        else:
            publisher.main(audit_module=audit, native_validator=native_proof,
                           stamp_key='steel_mingguang_walk_revalidation')
    except Exception as exc:
        audit.write_json(audit.a.report_path('publication_failure'), {'error': repr(exc), 'arguments': sys.argv[1:], 'published_by_this_result': False})
        raise
