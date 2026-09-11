"""Supply missing UVs on untextured morph surfaces for Godot's tangent importer."""
import copy
import json
import struct
from pathlib import Path

import numpy as np


def projected_uv(gltf_positions):
    # A seam-free oblique projection avoids collapsed UVs on axis-aligned faces.
    # ponytail: only for solid-color surfaces; author an atlas before texturing.
    xyz = np.asarray(gltf_positions, dtype=np.float64)
    return np.column_stack((xyz[:, 0] + .314159 * xyz[:, 2],
                            xyz[:, 1] + .271828 * xyz[:, 2])).astype('<f4')


def ensure_blender_morph_uv(objects):
    changed = []
    for obj in objects:
        if obj.type != 'MESH' or not obj.data.shape_keys or obj.data.uv_layers:
            continue
        for material in obj.data.materials:
            assert not material or not material.use_nodes or not any(
                n.type == 'TEX_IMAGE' for n in material.node_tree.nodes), obj.name
        xyz = np.array([v.co[:] for v in obj.data.vertices], dtype=np.float64)
        uv = projected_uv(xyz[:, (0, 2, 1)] * (1, 1, -1))
        layer = obj.data.uv_layers.new(name='MorphUV')
        for loop in obj.data.loops:
            u, v = uv[loop.vertex_index]
            layer.data[loop.index].uv = (float(u), 1.0 - float(v))
        changed.append(obj.name)
    return changed


def patch_glb(path):
    """Append only UV accessors; retain every existing binary byte and JSON field."""
    path = Path(path)
    raw = path.read_bytes()
    assert struct.unpack_from('<4sII', raw) == (b'glTF', 2, len(raw))
    size = struct.unpack_from('<I', raw, 12)[0]
    assert raw[16:20] == b'JSON' and raw[24+size:28+size] == b'BIN\0'
    doc = json.loads(raw[20:20+size])
    binary = bytearray(raw[28+size:])
    assert len(doc['buffers']) == 1 and 'uri' not in doc['buffers'][0]
    changed = []
    for mesh in doc['meshes']:
        for pi, primitive in enumerate(mesh['primitives']):
            attrs = primitive['attributes']
            if not primitive.get('targets') or 'TEXCOORD_0' in attrs:
                continue
            material = doc.get('materials', [])[primitive['material']]
            assert 'Texture"' not in json.dumps(material), mesh['name']
            acc = doc['accessors'][attrs['POSITION']]
            assert acc['type'] == 'VEC3' and acc['componentType'] == 5126 and 'sparse' not in acc
            view = doc['bufferViews'][acc['bufferView']]
            xyz = np.ndarray((acc['count'], 3), dtype='<f4', buffer=binary,
                             offset=view.get('byteOffset', 0)+acc.get('byteOffset', 0),
                             strides=(view.get('byteStride', 12), 4)).copy()
            uv = projected_uv(xyz)
            assert np.isfinite(uv).all()
            binary.extend(b'\0' * (-len(binary) % 4))
            doc['bufferViews'].append({'buffer': 0, 'byteOffset': len(binary),
                                       'byteLength': uv.nbytes, 'target': 34962})
            attrs['TEXCOORD_0'] = len(doc['accessors'])
            doc['accessors'].append({'bufferView': len(doc['bufferViews'])-1,
                                     'componentType': 5126, 'count': len(uv), 'type': 'VEC2'})
            binary.extend(uv.tobytes())
            changed.append((mesh['name'], pi))
    if not changed:
        return []
    doc['buffers'][0]['byteLength'] = len(binary)
    encoded = json.dumps(doc, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    result = (struct.pack('<4sII', b'glTF', 2, 28+len(encoded)+len(binary))
              + struct.pack('<I4s', len(encoded), b'JSON') + encoded
              + struct.pack('<I4s', len(binary), b'BIN\0') + binary)
    # Validate the exact allowed diff before publishing the updated asset.
    original = json.loads(raw[20:20+size])
    stripped = copy.deepcopy(doc)
    for mi, mesh in enumerate(original['meshes']):
        for pi, primitive in enumerate(mesh['primitives']):
            if 'TEXCOORD_0' not in primitive['attributes']:
                stripped['meshes'][mi]['primitives'][pi]['attributes'].pop('TEXCOORD_0', None)
    stripped['accessors'] = stripped['accessors'][:len(original['accessors'])]
    stripped['bufferViews'] = stripped['bufferViews'][:len(original['bufferViews'])]
    stripped['buffers'] = original['buffers']
    assert stripped == original and binary[:len(raw)-28-size] == raw[28+size:]
    temporary = path.with_suffix('.glb.uvtmp')
    temporary.write_bytes(result)
    temporary.replace(path)
    return changed
