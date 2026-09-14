"""Author low-pose skirt corrections without rebuilding the character pack."""
import copy
import json
import math
import struct
import sys
from pathlib import Path
import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'scripts/tests'))
sys.path.insert(0, str(Path(__file__).parent))
from validate_chinese_cloak_assets import read_glb, accessor
from ensure_morph_uv import ensure_blender_morph_uv

WORK = ROOT / '.godot-temp/mingguang_low_pose_20260912'
PREFIX = 'Armor_Mingguang_01_'
GROUPS = {'cloth': ['PleatedSkirt'], 'front': ['Pteruges_Front', 'Pteruges_Silver', 'Pteruges_Studs'],
          'rear': ['Skirt_Rear', 'Skirt_Rear_Rim'], 'left': ['Skirt_Side_L', 'Skirt_Rim_L'],
          'right': ['Skirt_Side_R', 'Skirt_Rim_R']}
CLIPS = ['down', 'unconscious', 'get_up', 'rescue']


def skin_matrices(arm, obj):
    matrices = np.zeros((len(obj.data.vertices), 4, 4))
    transforms = [np.array(arm.pose.bones[g.name].matrix @ arm.data.bones[g.name].matrix_local.inverted())
                  for g in obj.vertex_groups]
    for i, vertex in enumerate(obj.data.vertices):
        for group in vertex.groups:
            matrices[i] += transforms[group.group] * group.weight
    return matrices


def posed(points, matrices):
    return np.einsum('nij,nj->ni', matrices, np.column_stack((points, np.ones(len(points)))))[:, :3]


def correct_group(label, points, hip, bases):
    combined = np.concatenate(points)
    floor, low, top = .06, combined[:, 2].min(), combined[:, 2].max()
    if low >= floor:
        return points
    if label == 'cloth':
        # Gather the hanging cloth continuously, leaving the waistband fixed.
        # Extra horizontal rings retain rounded folds instead of one rigid tube.
        top = max(top, floor + .025)
        ratio = (top - floor) / (top - low)
        corrected = []
        for original in points:
            target = original.copy()
            t = np.clip((top - original[:, 2]) / (top - low), 0, 1)
            radial = original[:, :2] - hip[:2]
            radial /= np.maximum(np.linalg.norm(radial, axis=1)[:, None], .0001)
            target[:, :2] += radial * ((1 - ratio) * .06 * np.sin(t * math.pi))[:, None]
            target[:, 2] = top + (original[:, 2] - top) * ratio
            corrected.append(target)
        return corrected
    # Articulated hanging plates swing from their upper seam as whole groups;
    # shared trims/rivets follow the same hinge, not independent floor clamps.
    rest_top = max(base[:, 2].max() for base in bases)
    upper = np.concatenate([point[base[:, 2] > rest_top - .035] for point, base in zip(points, bases)])
    hinge = upper.mean(axis=0)
    # The inherited prone pose places the rear waist seam below the ground.
    # Lift its attached group continuously before swinging the loose end;
    # otherwise a rotate/translate fallback changes abruptly during roll-up.
    lift = max(0.0, floor + .015 - upper[:, 2].min())
    offset = np.array((0, 0, lift))
    points = [point + offset for point in points]
    combined = combined + offset
    hinge = hinge + offset
    # Rotate the hanging direction up about the authored waist seam, including
    # when the character lies down and the plate is nearly horizontal.
    direction = combined.mean(axis=0) - hinge
    axis = Vector(direction).cross(Vector((0, 0, 1)))
    if axis.length < .0001:
        axis = Vector((1, 0, 0))
    def rotate(angle):
        rotation = np.array(Matrix.Rotation(angle, 3, axis))
        return [(p - hinge) @ rotation.T + hinge for p in points]
    # Search the first safe deflection; existing skin already angles the sides.
    angle = next((a for a in np.linspace(0, math.pi * .75, 136)
                  if min(p[:, 2].min() for p in rotate(a)) >= floor), None)
    assert angle is not None, (label, low, top, hinge)
    return rotate(float(angle))


def author(sex):
    source = WORK / 'grounded_baseline' / sex
    if not source.with_suffix('.blend').exists():
        source = WORK / 'baseline' / sex
    dest = WORK / 'candidate' / sex
    dest.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(source.with_suffix('.blend')))
    bpy.context.preferences.filepaths.save_version = 0
    arm = bpy.data.objects['Armature']
    track_mutes = {t.name: t.mute for t in arm.animation_data.nla_tracks}
    for track in arm.animation_data.nla_tracks:
        track.mute = True
    parts = {name: bpy.data.objects[PREFIX + name] for names in GROUPS.values() for name in names}
    # Subdivide only long vertical cloth edges. Rest silhouette, thickness,
    # original UVs, pleats and waist anchoring are retained.
    cloth = parts['PleatedSkirt']
    bm = bmesh.new()
    bm.from_mesh(cloth.data)
    edges = [edge for edge in bm.edges if abs(edge.verts[0].co.z - edge.verts[1].co.z) > .3]
    bmesh.ops.subdivide_edges(bm, edges=edges, cuts=5, use_grid_fill=True)
    bm.to_mesh(cloth.data)
    bm.free()
    cloth.data.update()
    bases, keys = {}, {}
    for name, obj in parts.items():
        assert not obj.data.shape_keys, name
        assert np.allclose(np.array(obj.matrix_world), np.eye(4), atol=1e-5), name
        bases[name] = np.array([v.co[:] for v in obj.data.vertices])
        obj.shape_key_add(name='Basis')
        keys[name] = []
    times_by_clip = {}
    for clip in CLIPS:
        action = bpy.data.actions[clip]
        duration = action.frame_range[1] / 24.0
        times = sorted(set([i / 24 for i in range(math.ceil(duration * 24))] + [duration]))
        times_by_clip[clip] = times
        arm.animation_data.action = action
        for index, time in enumerate(times):
            bpy.context.scene.frame_set(int(time * 24), subframe=(time * 24) % 1)
            bpy.context.view_layer.update()
            hip = np.array(arm.pose.bones['J_Bip_C_Hips'].head)
            for group, names in GROUPS.items():
                matrices = [skin_matrices(arm, parts[name]) for name in names]
                points = [posed(bases[name], matrix) for name, matrix in zip(names, matrices)]
                targets = correct_group(group, points, hip, [bases[name] for name in names])
                for name, matrix, target in zip(names, matrices, targets):
                    key = parts[name].shape_key_add(name=f'Combat_{clip}_{index:03d}')
                    local = posed(target, np.linalg.inv(matrix))
                    assert np.isfinite(local).all(), name
                    key.data.foreach_set('co', local.astype('float32').ravel())
                    keys[name].append((clip, time, key))
        print('MINGGUANG_LOW_POSE_AUTHORED', sex, clip, len(times), flush=True)
    for name, obj in parts.items():
        shape_keys = obj.data.shape_keys
        shape_keys.animation_data_create()
        for clip, times in times_by_clip.items():
            action = bpy.data.actions.new(f'Mingguang_{name}_{clip}')
            action.use_fake_user = True
            shape_keys.animation_data.action = action
            for key_clip, key_time, key in keys[name]:
                for time in times:
                    key.value = float(key_clip == clip and abs(time - key_time) < 1e-6)
                    key.keyframe_insert('value', frame=time * 24)
            for curve in action.fcurves:
                for point in curve.keyframe_points:
                    point.interpolation = 'LINEAR'
            track = shape_keys.animation_data.nla_tracks.new()
            track.name = clip
            track.strips.new(clip, 0, action)
            track.mute = True
        shape_keys.animation_data.action = None
        for key in shape_keys.key_blocks:
            key.value = 0
        obj['mingguang_low_pose_revision'] = 2
    arm.animation_data.action = None
    for track in arm.animation_data.nla_tracks:
        track.mute = track_mutes[track.name]
    for bone in arm.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    ensure_blender_morph_uv(list(parts.values()))
    bpy.context.scene.frame_set(0)
    bpy.ops.wm.save_as_mainfile(filepath=str(dest.with_suffix('.blend')))
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [arm, *parts.values()]:
        obj.hide_viewport = False
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    subset = WORK / f'{sex}_skirt_subset.glb'
    bpy.ops.export_scene.gltf(filepath=str(subset), export_format='GLB', use_selection=True,
        export_apply=False, export_animations=False, export_skins=True, export_morph=True,
        export_try_sparse_sk=False)
    merge(source.with_suffix('.glb'), subset, dest.with_suffix('.glb'), times_by_clip)
    metadata = json.loads(source.with_suffix('.json').read_text(encoding='utf-8'))
    metadata['mingguang_low_pose'] = {'revision': 2, 'clips': CLIPS, 'parts': list(parts), 'fps': 24}
    dest.with_suffix('.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8')


def merge(source, subset, target, times):
    # Same scoped splice used by build_lining_armor_candidate.py: native export
    # for the changed parts, original bytes and indices for everything else.
    doc, raw = read_glb(source)
    new, new_binary = read_glb(subset)
    binary = bytearray(raw)
    copied = {}
    def append_accessor(index):
        if index in copied:
            return copied[index]
        acc = copy.deepcopy(new['accessors'][index])
        assert 'sparse' not in acc
        view = copy.deepcopy(new['bufferViews'][acc['bufferView']])
        start = view.get('byteOffset', 0)
        binary.extend(b'\0' * (-len(binary) % 4))
        view['byteOffset'] = len(binary)
        binary.extend(new_binary[start:start + view['byteLength']])
        acc['bufferView'] = len(doc['bufferViews'])
        doc['bufferViews'].append(view)
        copied[index] = len(doc['accessors'])
        doc['accessors'].append(acc)
        return copied[index]
    def array_accessor(values, kind):
        values = np.asarray(values, dtype='<f4')
        binary.extend(b'\0' * (-len(binary) % 4))
        doc['bufferViews'].append({'buffer': 0, 'byteOffset': len(binary), 'byteLength': values.nbytes})
        binary.extend(values.tobytes())
        doc['accessors'].append({'bufferView': len(doc['bufferViews']) - 1, 'componentType': 5126,
                                'count': len(values), 'type': kind, 'min': [float(values.min())], 'max': [float(values.max())]})
        return len(doc['accessors']) - 1
    old_nodes = {node['name']: (i, node) for i, node in enumerate(doc['nodes'])}
    for node in new['nodes']:
        if 'mesh' not in node:
            continue
        index, old = old_nodes[node['name']]
        old_skin, new_skin = doc['skins'][old['skin']], new['skins'][node['skin']]
        assert [doc['nodes'][i]['name'] for i in old_skin['joints']] == [new['nodes'][i]['name'] for i in new_skin['joints']]
        assert np.allclose(accessor(doc, binary, old_skin['inverseBindMatrices']), accessor(new, new_binary, new_skin['inverseBindMatrices']), atol=1e-6)
        old_mesh, new_mesh = doc['meshes'][old['mesh']], new['meshes'][node['mesh']]
        assert len(old_mesh['primitives']) == len(new_mesh['primitives'])
        for original, changed in zip(old_mesh['primitives'], new_mesh['primitives']):
            assert doc['materials'][original['material']]['name'] == new['materials'][changed['material']]['name']
            original['attributes'] = {key: append_accessor(value) for key, value in changed['attributes'].items()}
            original['indices'] = append_accessor(changed['indices'])
            original['targets'] = [{key: append_accessor(value) for key, value in shape.items()} for shape in changed['targets']]
        old_mesh['weights'] = new_mesh['weights']
        old_mesh.setdefault('extras', {})['targetNames'] = new_mesh['extras']['targetNames']
        for clip, samples in times.items():
            animation = next(a for a in doc['animations'] if a['name'] == clip)
            shape_names = old_mesh['extras']['targetNames']
            weights = np.zeros((len(samples), len(shape_names)), dtype='<f4')
            for sample_index in range(len(samples)):
                weights[sample_index, shape_names.index(f'Combat_{clip}_{sample_index:03d}')] = 1
            sampler = len(animation['samplers'])
            animation['samplers'].append({'input': array_accessor(samples, 'SCALAR'),
                                         'output': array_accessor(weights.ravel(), 'SCALAR'), 'interpolation': 'LINEAR'})
            animation['channels'].append({'sampler': sampler, 'target': {'node': index, 'path': 'weights'}})
    binary.extend(b'\0' * (-len(binary) % 4))
    doc['buffers'][0]['byteLength'] = len(binary)
    encoded = json.dumps(doc, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    target.write_bytes(struct.pack('<4sII', b'glTF', 2, 28 + len(encoded) + len(binary)) +
                       struct.pack('<I4s', len(encoded), b'JSON') + encoded +
                       struct.pack('<I4s', len(binary), b'BIN\0') + binary)
    print('MINGGUANG_LOW_POSE_CANDIDATE', target, len(binary) - len(raw), 'added bytes', flush=True)


if __name__ == '__main__':
    author(sys.argv[sys.argv.index('--') + 1])
