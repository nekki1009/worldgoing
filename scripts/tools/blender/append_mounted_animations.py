"""Append mounted clips only; retain all existing GLB data and animation indices."""
import argparse
import copy
import json
import struct
from pathlib import Path

CLIPS = ('ride_heavy', 'ride_guard_break')


def read_glb(path):
    raw = Path(path).read_bytes()
    assert raw[:4] == b'glTF' and struct.unpack_from('<I', raw, 4)[0] == 2
    size, tag = struct.unpack_from('<I4s', raw, 12)
    assert tag == b'JSON'
    doc = json.loads(raw[20:20 + size])
    length, tag = struct.unpack_from('<I4s', raw, 20 + size)
    assert tag == b'BIN\0' and len(doc['buffers']) == 1
    return doc, raw[28 + size:28 + size + length]


def write_glb(path, doc, binary):
    binary = bytes(binary) + b'\0' * (-len(binary) % 4)
    doc['buffers'][0]['byteLength'] = len(binary)
    encoded = json.dumps(doc, separators=(',', ':'), ensure_ascii=False).encode('utf-8')
    encoded += b' ' * (-len(encoded) % 4)
    Path(path).write_bytes(struct.pack('<4sII', b'glTF', 2, 28 + len(encoded) + len(binary))
                          + struct.pack('<I4s', len(encoded), b'JSON') + encoded
                          + struct.pack('<I4s', len(binary), b'BIN\0') + binary)


def floats(doc, binary, index):
    a = doc['accessors'][index]
    assert a['componentType'] == 5126 and 'sparse' not in a
    width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
    v = doc['bufferViews'][a['bufferView']]
    offset = v.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = v.get('byteStride', width * 4)
    return [struct.unpack_from('<' + 'f' * width, binary, offset + i * stride)
            for i in range(a['count'])]


def append_mounted(source, subset, target):
    source, subset, target = map(Path, (source, subset, target))
    assert target.resolve() not in (source.resolve(), subset.resolve()), 'Use a distinct candidate path'
    doc, original = read_glb(source)
    new, extra = read_glb(subset)
    assert {a['name'] for a in new['animations']} == set(CLIPS)
    assert not set(CLIPS) & {a['name'] for a in doc['animations']}, 'Already integrated; do not replace clips'
    nodes = {n['name']: i for i, n in enumerate(doc['nodes'])}
    assert len(nodes) == len(doc['nodes']), 'Node names must be unique'
    binary = bytearray(original)
    copied, views = {}, {}

    def acc(index):
        if index not in copied:
            a = copy.deepcopy(new['accessors'][index])
            assert 'sparse' not in a
            vi = a['bufferView']
            if vi not in views:
                v = copy.deepcopy(new['bufferViews'][vi])
                assert v.get('buffer', 0) == 0
                start = v.get('byteOffset', 0)
                binary.extend(b'\0' * (-len(binary) % 4))
                v['byteOffset'] = len(binary)
                binary.extend(extra[start:start + v['byteLength']])
                views[vi] = len(doc['bufferViews'])
                doc['bufferViews'].append(v)
            a['bufferView'] = views[vi]
            copied[index] = len(doc['accessors'])
            doc['accessors'].append(a)
        return copied[index]

    def scalar(values):
        values = list(values)
        binary.extend(b'\0' * (-len(binary) % 4))
        doc['bufferViews'].append({'buffer': 0, 'byteOffset': len(binary), 'byteLength': len(values) * 4})
        binary.extend(struct.pack('<' + 'f' * len(values), *values))
        doc['accessors'].append({'bufferView': len(doc['bufferViews']) - 1, 'componentType': 5126,
                                 'count': len(values), 'type': 'SCALAR', 'min': [min(values)], 'max': [max(values)]})
        return len(doc['accessors']) - 1

    idle = next(a for a in doc['animations'] if a['name'] == 'ride_idle')
    idle_weights = {c['target']['node']: c for c in idle['channels'] if c['target']['path'] == 'weights'}
    # Every existing animated morph must be set by these clips: switching from
    # bow draw/cape correction cannot leave a stale value in a private library.
    morph_nodes = {c['target']['node'] for a in doc['animations'] for c in a['channels']
                   if c['target']['path'] == 'weights'}
    report = {}
    for original_animation in new['animations']:
        animation = copy.deepcopy(original_animation)
        duration = max(row[0] for s in original_animation['samplers'] for row in floats(new, extra, s['input']))
        for sampler in animation['samplers']:
            sampler['input'], sampler['output'] = acc(sampler['input']), acc(sampler['output'])
        for channel in animation['channels']:
            source_node = new['nodes'][channel['target']['node']]
            ni = nodes[source_node['name']]
            assert channel['target']['path'] != 'weights', 'Subset must contain skeletal channels only'
            for key, default in [('translation', [0, 0, 0]), ('rotation', [0, 0, 0, 1]), ('scale', [1, 1, 1])]:
                assert all(abs(a - b) < 1e-5 for a, b in zip(source_node.get(key, default), doc['nodes'][ni].get(key, default))), (source_node['name'], key)
            channel['target']['node'] = ni
        morph_report = []
        for ni in sorted(morph_nodes):
            node = doc['nodes'][ni]
            mesh = doc['meshes'][node['mesh']]
            width = len(mesh['primitives'][0].get('targets', []))
            names = mesh.get('extras', {}).get('targetNames', [])
            assert width > 0 and (not names or len(names) == width)
            assert all(len(p.get('targets', [])) == width for p in mesh['primitives'])
            if ni in idle_weights and not node['name'].startswith('Weapon_'):
                # Copy the sampler referenced by THIS channel, never enumerate
                # channels as sampler IDs (cape/helmet use shared samplers).
                old_sampler = idle['samplers'][idle_weights[ni]['sampler']]
                times = [v[0] for v in floats(doc, original, old_sampler['input'])]
                count = doc['accessors'][old_sampler['output']]['count']
                factor = 3 if old_sampler.get('interpolation') == 'CUBICSPLINE' else 1
                assert count == len(times) * width * factor
                assert times[0] == 0 and times[-1] > 0
                # Linear/step morphs can retime while keeping authored values.
                assert factor == 1, 'Cubic morph tangents need explicit retiming'
                sampler = copy.deepcopy(old_sampler)
                sampler['input'] = scalar(t / times[-1] * duration for t in times)
                mode = 'ride_idle_retimed'
            else:
                rest = node.get('weights', mesh.get('weights', [0.0] * width))
                assert len(rest) == width
                if node['name'].startswith('Weapon_'):
                    rest = [0.0] * width # Generic melee strike never draws/releases a bow.
                sampler = {'input': scalar([0.0, duration]), 'output': scalar(rest + rest), 'interpolation': 'LINEAR'}
                mode = 'rest_reset'
            animation['channels'].append({'sampler': len(animation['samplers']), 'target': {'node': ni, 'path': 'weights'}})
            animation['samplers'].append(sampler)
            morph_report.append({'node': node['name'], 'targets': names, 'width': width, 'mode': mode})
        doc['animations'].append(animation)
        report[animation['name']] = {'duration': duration, 'channels': len(animation['channels']), 'morphs': morph_report}
    write_glb(target, doc, binary)
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source'); parser.add_argument('subset'); parser.add_argument('target')
    args = parser.parse_args()
    print(json.dumps(append_mounted(args.source, args.subset, args.target), ensure_ascii=False, indent=2))
