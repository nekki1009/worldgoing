"""Use the authored idle lower body; retain the crossbow upper-body animation."""
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix

LOWER = ['J_Bip_C_Hips'] + ['J_Bip_' + side + '_' + part
    for side in ['L', 'R'] for part in ['UpperLeg', 'LowerLeg', 'Foot', 'ToeBase']]
SPINE = 'J_Bip_C_Spine'
CHANGED = LOWER + [SPINE]


def apply_crossbow_idle_stance(arm):
    idle, action = bpy.data.actions['idle'], bpy.data.actions['attack_crossbow']
    scene = bpy.context.scene
    saved_action, saved_frame = arm.animation_data.action, scene.frame_current
    mutes = [(track, track.mute) for track in arm.animation_data.nla_tracks]
    for track, _ in mutes:
        track.mute = True
    def sample(clip, frame):
        arm.animation_data.action = None
        for bone in arm.pose.bones:
            bone.matrix_basis = Matrix.Identity(4)
        arm.animation_data.action = clip
        scene.frame_set(math.floor(frame), subframe=frame % 1)
        bpy.context.view_layer.update()
    sample(idle, idle.frame_range[0])
    stance = {name: arm.pose.bones[name].matrix_basis.copy() for name in LOWER}
    idle_hips = arm.pose.bones[LOWER[0]].matrix.translation.copy()
    # Blender's connected edit-bone constraint discards pose translation. Allow
    # the compensating spine keys without changing its parent or rest matrix.
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode='EDIT')
    arm.data.edit_bones[SPINE].use_connect = False
    bpy.ops.object.mode_set(mode='OBJECT')
    start, end = action.frame_range
    frames = sorted({float(key.co.x) for curve in action.fcurves for key in curve.keyframe_points}
                    | {float(frame) for frame in range(math.ceil(start), math.floor(end) + 1)})
    corrected = []
    for frame in frames:
        sample(action, frame)
        old_spine = arm.pose.bones[SPINE].matrix.copy()
        shift = idle_hips - arm.pose.bones[LOWER[0]].matrix.translation
        arm.animation_data.action = None
        for name, matrix in stance.items():
            arm.pose.bones[name].matrix_basis = matrix
        bpy.context.view_layer.update()
        # Keep original torso/arms orientation and recoil, translated only by
        # the stance's pelvis-height/position change. No retargeted arm tracks.
        arm.pose.bones[SPINE].matrix = Matrix.Translation(shift) @ old_spine
        bpy.context.view_layer.update()
        corrected.append((frame, {name: arm.pose.bones[name].matrix_basis.copy() for name in CHANGED}))
    paths = {arm.pose.bones[name].path_from_id() for name in CHANGED}
    for curve in list(action.fcurves):
        if any(curve.data_path.startswith(path + '.') for path in paths):
            action.fcurves.remove(curve)
    arm.animation_data.action = action
    for frame, pose in corrected:
        for name, matrix in pose.items():
            bone = arm.pose.bones[name]
            bone.rotation_mode = 'QUATERNION'
            bone.matrix_basis = matrix
            for channel in ['location', 'rotation_quaternion', 'scale']:
                bone.keyframe_insert(data_path=channel, frame=frame, group=name)
    for curve in action.fcurves:
        if any(curve.data_path.startswith(path + '.') for path in paths):
            for key in curve.keyframe_points:
                key.interpolation = 'LINEAR'
    for track, mute in mutes:
        track.mute = mute
    arm.animation_data.action = saved_action
    scene.frame_set(saved_frame)
    print('CROSSBOW_IDLE_STANCE_AUTHORED', len(corrected), 'samples', CHANGED)


def main(sex):
    root = Path(__file__).resolve().parents[3]
    sys.path.insert(0, str(Path(__file__).parent))
    from author_weapon_refresh import splice
    work = root / '.godot-temp/crossbow_stance_20260914'
    source = work / 'baseline' / f'standard_anime_{sex}_character_pack'
    target = work / 'candidate' / sex
    bpy.ops.wm.open_mainfile(filepath=str(source.with_suffix('.blend')))
    bpy.context.preferences.filepaths.save_version = 0
    arm = next(obj for obj in bpy.data.objects if obj.type == 'ARMATURE')
    apply_crossbow_idle_stance(arm)
    bpy.ops.wm.save_as_mainfile(filepath=str(target.with_suffix('.blend')))
    for track in list(arm.animation_data.nla_tracks):
        arm.animation_data.nla_tracks.remove(track)
    for action in list(bpy.data.actions):
        if action.name != 'attack_crossbow':
            bpy.data.actions.remove(action)
    arm.animation_data.action = bpy.data.actions['attack_crossbow']
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [arm, bpy.data.objects['Body']]:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    subset = target.with_name(sex + '_subset.glb')
    bpy.ops.export_scene.gltf(filepath=str(subset), export_format='GLB', use_selection=True,
        export_animations=True, export_animation_mode='ACTIONS', export_force_sampling=False,
        export_frame_range=False, export_skins=True, export_morph=False, export_apply=False)
    splice(source.with_suffix('.glb'), subset, target.with_suffix('.glb'),
        {'attack_crossbow': CHANGED}, skip_meshes=True)
    metadata = json.loads(source.with_suffix('.json').read_text(encoding='utf-8'))
    metadata['crossbow_idle_stance'] = {'date': '2026-09-14', 'clip': 'attack_crossbow',
        'reference': 'idle first authored frame', 'bones': CHANGED,
        'upper_body': 'Original chest/arms/weapon channels; spine compensates pelvis transform'}
    target.with_suffix('.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('CROSSBOW_STANCE_CANDIDATE', sex)


def audit_source(sex):
    root = Path(__file__).resolve().parents[3]
    stem = f'standard_anime_{sex}_character_pack.blend'
    original = root / '.godot-temp/crossbow_stance_20260914/baseline' / stem
    formal = root / 'assets/characters/human/q35' / stem
    snapshots = []
    for path in [original, formal]:
        bpy.ops.wm.open_mainfile(filepath=str(path))
        arm = next(obj for obj in bpy.data.objects if obj.type == 'ARMATURE')
        rig = {bone.name: (bone.parent.name if bone.parent else None, bone.matrix_local.copy()) for bone in arm.data.bones}
        curves = {}
        for action in bpy.data.actions:
            for curve in action.fcurves:
                if action.name == 'attack_crossbow' and any(curve.data_path.startswith(arm.pose.bones[name].path_from_id() + '.') for name in CHANGED):
                    continue
                # Disconnecting the authoring constraint cannot reveal latent
                # translation in another clip; those channels must remain zero.
                if curve.data_path == arm.pose.bones[SPINE].path_from_id() + '.location':
                    assert all(abs(key.co.y) < 1e-6 for key in curve.keyframe_points)
                curves[(action.name, curve.data_path, curve.array_index)] = [(tuple(key.co), tuple(key.handle_left), tuple(key.handle_right), key.interpolation) for key in curve.keyframe_points]
        snapshots.append((rig, curves, set(action.name for action in bpy.data.actions)))
    old, new = snapshots
    assert old[0].keys() == new[0].keys() and old[1:] == new[1:]
    for name, (parent, matrix) in old[0].items():
        assert parent == new[0][name][0]
        assert max(abs(a - b) for row_a, row_b in zip(matrix, new[0][name][1]) for a, b in zip(row_a, row_b)) < 1e-6
    print('CROSSBOW_BLEND_SOURCE_PASS', sex, len(old[0]), 'bones; rest transforms, parents and all unrelated authored channels preserved')


if __name__ == '__main__':
    (audit_source if '--audit-source' in sys.argv else main)(sys.argv[sys.argv.index('--') + 1])
