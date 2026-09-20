"""Append walk-only Mingguang skirt corrections; caller owns GLB/channel splice.

Original Basis, weights and low-pose keys/actions are immutable. Native keys
are returned as channel data, not installed into a second animation owner.
"""
import hashlib
import json
import sys
from pathlib import Path

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from author_mingguang_low_pose import GROUPS, PREFIX, skin_matrices, posed
from repair_character_audit import reset_rig
from repair_iron_armor_walk import mesh_signature, action_signatures


def points(data):
    result = np.empty((len(data), 3), dtype=np.float32)
    data.foreach_get('co', result.ravel())
    return result.astype(float)


def digest_keys(obj, count=None):
    keys = obj.data.shape_keys
    if not keys:
        return None
    digest = hashlib.sha256()
    for key in list(keys.key_blocks)[:count]:
        digest.update(key.name.encode())
        digest.update(points(key.data).astype('<f4').tobytes())
    return digest.hexdigest()


def envelope(source, heights, rest_rx, rest_ry, top):
    """One uniform flare per direction, fitted to actual limb bounds.

    A rounded-box dilation keeps lateral extrema out of longitudinal fitting.
    No ellipse divisor and no independent height-ring peaks are permitted.
    """
    slopes = np.zeros(3)
    for z in heights:
        drop = top - z
        if drop < .10:
            continue
        band = source[np.abs(source[:, 2] - z) < .045]
        if not len(band):
            continue
        needed = np.array([float(np.max(np.abs(band[:, 0]))) + .018 - rest_rx,
                           float(np.max(-band[:, 1])) + .022 - rest_ry,
                           float(np.max(band[:, 1])) + .022 - rest_ry])
        slopes = np.maximum(slopes, needed / drop)
    return slopes


def repair_mingguang(arm, sex):
    assert sex in ('male', 'female')
    parts = {name: bpy.data.objects[PREFIX + name]
             for names in GROUPS.values() for name in names}
    assert len(parts) == 10
    for obj in parts.values():
        assert obj.data.shape_keys and len(obj.data.shape_keys.key_blocks) == 281, obj.name
        assert np.allclose(np.array(obj.matrix_world), np.eye(4), atol=1e-6)
        assert not any(k.name.startswith('WalkClearance_') for k in obj.data.shape_keys.key_blocks)
    before = {o.name: mesh_signature(o) for o in bpy.data.objects if o.type == 'MESH'}
    old_keys = {o.name: digest_keys(o) for o in bpy.data.objects
                if o.type == 'MESH' and o.data.shape_keys}
    actions = action_signatures()
    bases = {name: points(obj.data.shape_keys.key_blocks[0].data) for name, obj in parts.items()}
    source_names = ['Body_Standard_' + sex.title(), PREFIX + 'Underlayer_Pants']
    source_names += [PREFIX + n for n in ('Greaves_L', 'Greaves_R', 'Greave_Rim_L', 'Greave_Rim_R')]
    sources = [bpy.data.objects[n] for n in source_names]
    source_bases = [points(o.data.vertices) for o in sources]
    reset_rig(arm)
    action = bpy.data.actions['walk']
    start, end = map(float, action.frame_range)
    from author_mingguang_low_pose import read_glb, accessor
    root = Path(__file__).resolve().parents[3]
    doc, raw = read_glb(root / f'output/steel_mingguang_walk_20260919/baseline/standard_anime_{sex}_character_pack.glb')
    walk = next(a for a in doc['animations'] if a['name'] == 'walk')
    duration = max(float(np.max(accessor(doc, raw, s['input']))) for s in walk['samplers'])
    assert duration > 0
    times = np.linspace(0, duration, int(np.ceil(duration * 48)) + 1)
    frames = start + (end - start) * times / duration
    skirt = bases['PleatedSkirt']
    top, low = float(skirt[:, 2].max()), float(skirt[:, 2].min())
    source_masks = [(p[:, 2] >= low - .15) & (p[:, 2] <= top + .03)
                    for p in source_bases]
    heights = np.linspace(low - .04, top + .02, 25)
    # Actual authored pleat trough, not an arbitrary document dimension.
    rest_rx = float(np.max(np.abs(skirt[:, 0]))) - .009
    rest_ry = float(np.max(np.abs(skirt[:, 1]))) - .009
    names = []
    samples = []
    for index, frame in enumerate(frames):
        arm.animation_data.action = action
        bpy.context.scene.frame_set(int(frame), subframe=float(frame % 1))
        bpy.context.view_layer.update()
        hips = np.array(arm.pose.bones['J_Bip_C_Hips'].matrix @
                        arm.data.bones['J_Bip_C_Hips'].matrix_local.inverted())
        inv_hips = np.linalg.inv(hips)
        cloud = np.concatenate([posed(base, skin_matrices(arm, obj))[mask]
                                for obj, base, mask in zip(sources, source_bases, source_masks)])
        cloud = (np.column_stack((cloud, np.ones(len(cloud)))) @ inv_hips.T)[:, :3]
        cloud = cloud[(cloud[:, 2] >= low - .10) & (cloud[:, 2] <= top + .03)]
        slopes = envelope(cloud, heights, rest_rx, rest_ry, top)
        key_name = f'WalkClearance_{index:03d}'
        names.append(key_name)
        max_delta = 0.0
        posed_bounds = {}
        for name, obj in parts.items():
            base = bases[name]
            target = base.copy()
            drop = np.maximum(top - base[:, 2], 0)
            # The same waist hinge map applies to every layer and ornament.
            # Rotate each hanging generator instead of dilating its length.
            x_gate = np.clip(np.abs(base[:, 0]) / .065, 0, 1)
            y_gate = np.clip(np.abs(base[:, 1]) / .065, 0, 1)
            x_gate = x_gate * x_gate * (3 - 2 * x_gate)
            y_gate = y_gate * y_gate * (3 - 2 * y_gate)
            slope_x = np.sign(base[:, 0]) * slopes[0] * x_gate
            slope_y = np.sign(base[:, 1]) * np.where(base[:, 1] < 0, slopes[1], slopes[2]) * y_gate
            cosine = 1 / np.sqrt(1 + slope_x * slope_x + slope_y * slope_y)
            target[:, 0] += slope_x * drop * cosine
            target[:, 1] += slope_y * drop * cosine
            target[:, 2] += drop * (1 - cosine)
            # Exact generator-radius preservation before the separate 18mm
            # cloth waist tuck. Existing authored offsets/thickness survive.
            radius = np.linalg.norm(np.column_stack((target[:, 0]-base[:, 0],
                target[:, 1]-base[:, 1], target[:, 2]-top)), axis=1)
            assert np.allclose(radius[drop>0], drop[drop>0], atol=1e-7)
            if name == 'PleatedSkirt':
                # Only the existing inner waist ring tucks beneath the belt;
                # no added cover or changed Basis/low-pose geometry.
                tuck = np.clip(1 - drop / .08, 0, 1)
                target[:, 2] += .018 * tuck * tuck * (3 - 2 * tuck)
            posed_bounds[name] = [target.min(axis=0).tolist(), target.max(axis=0).tolist()]
            world_target = (np.column_stack((target, np.ones(len(target)))) @ hips.T)[:, :3]
            local_target = posed(world_target, np.linalg.inv(skin_matrices(arm, obj)))
            assert np.isfinite(local_target).all()
            max_delta = max(max_delta, float(np.max(np.linalg.norm(local_target - base, axis=1))))
            key = obj.shape_key_add(name=key_name)
            key.data.foreach_set('co', local_target.astype('float32').ravel())
            key.value = 0
        samples.append({'frame': float(frame), 'max_local_delta_m': max_delta,
                        'uniform_flare_slopes': slopes.tolist(), 'pelvis_space_bounds': posed_bounds,
                        'source_pelvis_space_bounds': [cloud.min(axis=0).tolist(), cloud.max(axis=0).tolist()]})
    reset_rig(arm)
    bpy.context.scene.frame_set(0)
    channels = []
    for obj in parts.values():
        assert digest_keys(obj, 281) == old_keys[obj.name], obj.name
        keys = obj.data.shape_keys
        keys.animation_data_create()
        new_action = bpy.data.actions.new(f'MingguangWalkRepair_{obj.name}')
        new_action.use_fake_user = True
        keys.animation_data.action = new_action
        for key in keys.key_blocks[1:]:
            column = names.index(key.name) if key.name in names else -1
            for index, time in enumerate(times):
                key.value = float(column == index)
                key.keyframe_insert('value', frame=float(time * 24))
        for curve in new_action.fcurves:
            for point in curve.keyframe_points:
                point.interpolation = 'LINEAR'
        track = keys.animation_data.nla_tracks.new()
        track.name = 'walk'
        track.strips.new('walk', 0, new_action)
        track.mute = True
        keys.animation_data.action = None
        for key in keys.key_blocks:
            key.value = 0
        channels.append({'object': obj.name, 'clip': 'walk', 'old_target_count': 280,
                         'target_names': names, 'times': [float(t) for t in times],
                         'weights': np.eye(len(frames)).tolist(), 'interpolation': 'LINEAR'})
    current_actions = action_signatures()
    assert all(current_actions[n] == h for n, h in actions.items())
    assert all(mesh_signature(bpy.data.objects[n]) == h for n, h in before.items())
    assert all(digest_keys(bpy.data.objects[n], 281 if n.startswith(PREFIX) else None) == h
               for n, h in old_keys.items())
    return {'revision': 'v4', 'changed': {o.name: {'before': old_keys[o.name],
             'after': digest_keys(o), 'vertices': len(o.data.vertices)} for o in parts.values()},
            'topology_changed': {}, 'appended_morph_channels': channels,
            'original_mesh_hashes': before, 'original_key_hashes': old_keys,
            'original_action_hashes': actions, 'basis_weights_uv_materials_unchanged': True,
            'all_280_low_pose_keys_per_part_unchanged': True, 'samples': samples,
            'hinge_generator_length_preserved': True,
            'walk_duration_seconds': duration, 'original_action_frame_range': [start, end],
            'acceptance': 'Native candidate only. MAIN must zero-pad existing weight samplers and verify native GPU walk and low-pose regression.'}


if __name__ == '__main__':
    root = Path(__file__).resolve().parents[3]
    sex = sys.argv[-1]
    out = root / 'output/steel_mingguang_walk_20260919/mingguang/v4' / sex
    out.mkdir(parents=True, exist_ok=False)
    bpy.ops.wm.open_mainfile(filepath=str(root / f'output/steel_mingguang_walk_20260919/baseline/standard_anime_{sex}_character_pack.blend'))
    report = repair_mingguang(bpy.data.objects['Armature'], sex)
    report['script_sha256'] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    (out / 'repair.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(out / 'candidate.blend'))
    print('MINGGUANG_WALK_NATIVE_COMPLETE', sex, flush=True)
