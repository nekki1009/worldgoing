"""Explicit mounted-only authoring. 'export' preserves manual edits; no publication."""
import argparse
import json
import math
import sys
from pathlib import Path
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / 'assets/characters/human/q35/equipment_matrix'
OUT = ROOT / 'output/equipment_matrix_20260918/mounted'
BASE = ROOT / 'output/equipment_matrix_20260918/baseline'
sys.path.insert(0, str(Path(__file__).parent))
from append_mounted_animations import CLIPS, append_mounted

# Source frames at 24 fps. Offset rotations are local to the original seated
# pose; hips and every lower-body bone keep that pose at all subframes.
HEAVY = [
    (0, {}),
    (16, {'Spine': (-8, -9, -3), 'Chest': (-10, -17, -4), 'UpperChest': (-6, -10, 0),
          'R_UpperArm': (-28, -12, 18), 'R_LowerArm': (0, 0, 22), 'R_Hand': (-12, 0, -7),
          'L_UpperArm': (-10, 8, -9), 'L_LowerArm': (0, 0, -12), 'Head': (6, 8, 0)}),
    (29, {'Spine': (-12, -12, -4), 'Chest': (-15, -22, -5), 'UpperChest': (-8, -12, 0),
          'R_UpperArm': (-42, -16, 26), 'R_LowerArm': (0, 0, 30), 'R_Hand': (-18, 0, -10),
          'L_UpperArm': (-15, 10, -14), 'L_LowerArm': (0, 0, -18), 'Head': (9, 12, 0)}),
    (37, {'Spine': (15, 12, 4), 'Chest': (20, 24, 6), 'UpperChest': (10, 9, 0),
          'R_UpperArm': (18, 16, -18), 'R_LowerArm': (0, 0, -34), 'R_Hand': (14, 0, 8),
          'L_UpperArm': (12, -8, 12), 'L_LowerArm': (0, 0, 18), 'Head': (-11, -10, 0)}),
    (44, {'Spine': (10, 17, 6), 'Chest': (15, 28, 8), 'UpperChest': (8, 11, 0),
          'R_UpperArm': (25, 20, -22), 'R_LowerArm': (0, 0, -24), 'R_Hand': (8, 0, 12),
          'L_UpperArm': (8, -10, 9), 'L_LowerArm': (0, 0, 10), 'Head': (-8, -12, -2)}),
    (54, {'Spine': (-3, 6, -2), 'Chest': (-4, 8, -3), 'R_UpperArm': (-10, 4, 8),
          'R_LowerArm': (0, 0, 10), 'L_UpperArm': (-4, 0, -3), 'Head': (4, -3, 0)}),
    (70, {}),
]
BREAK = [
    (0, {}),
    (2.0, {'Spine': (-18, -5, 5), 'Chest': (-22, -10, 9), 'UpperChest': (-10, -4, 3),
           'Head': (-12, 5, -3), 'R_UpperArm': (-12, -6, 22), 'R_LowerArm': (0, 0, 18),
           'L_UpperArm': (-18, 5, -25), 'L_LowerArm': (0, 0, -24)}),
    (4.0, {'Spine': (-11, 6, 8), 'Chest': (-14, 10, 10), 'UpperChest': (-6, 4, 2),
           'Head': (5, -7, -3), 'R_UpperArm': (2, 5, 16), 'R_LowerArm': (0, 0, 10),
           'L_UpperArm': (-4, -4, -18), 'L_LowerArm': (0, 0, -12)}),
    (6.5, {'Spine': (8, 3, -4), 'Chest': (10, 5, -5), 'UpperChest': (3, 2, -2),
           'Head': (-3, -3, 3), 'R_UpperArm': (7, 2, -8), 'L_UpperArm': (8, -2, 8)}),
    (9.6, {}),
]


def bone_name(short):
    return 'J_Bip_' + (short if short.startswith(('L_', 'R_')) else 'C_' + short)


def idle_pose(arm):
    arm.animation_data_create()
    for track in arm.animation_data.nla_tracks:
        track.mute = True
    arm.animation_data.action = bpy.data.actions['ride_idle']
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()
    pose = {b.name: b.matrix_basis.copy() for b in arm.pose.bones}
    arm.animation_data.action = None
    return pose


def set_pose(arm, pose):
    for name, basis in pose.items():
        bone = arm.pose.bones[name]
        bone.rotation_mode = 'QUATERNION'
        bone.location, bone.rotation_quaternion, bone.scale = basis.decompose()
    bpy.context.view_layer.update()


def arm_to(arm, side, target, direction):
    """Solve the native two-bone arm; keep the prop outside the horse flank."""
    prefix = 'J_Bip_' + side + '_'
    upper, lower, hand = (arm.pose.bones[prefix + n] for n in ('UpperArm', 'LowerArm', 'Hand'))
    origin = upper.head.copy()
    a, b = upper.bone.length, lower.bone.length
    axis = target - origin
    distance = min(a + b - .0001, max(abs(a - b) + .0001, axis.length))
    axis.normalize()
    pole = Vector((-1 if side == 'R' else 1, .25, -.3))
    bend = (pole - axis * pole.dot(axis)).normalized()
    along = (a * a - b * b + distance * distance) / (2 * distance)
    joint = origin + axis * along + bend * math.sqrt(max(0, a * a - along * along))
    end = origin + axis * distance
    for bone, start, stop in ((upper, origin, joint), (lower, joint, end)):
        rest = bone.bone.matrix_local.to_quaternion()
        turn = (rest @ Vector((0, 1, 0))).rotation_difference((stop - start).normalized())
        bone.matrix = Matrix.Translation(start) @ (turn @ rest).to_matrix().to_4x4()
        bpy.context.view_layer.update()
    # Native held sword/spear/axe geometry rotates its stock from +Z to -Y
    # before skin binding (the refreshed axe preserves that same palm frame).
    # Aim that actual rest shaft, not the pre-attachment construction axis.
    rest = hand.bone.matrix_local.to_quaternion()
    stock_axis = Vector((0, -1, 0)) if side == 'R' else Vector((0, 0, 1))
    turn = stock_axis.rotation_difference(Vector(direction).normalized())
    hand.matrix = Matrix.Translation(end) @ (turn @ rest).to_matrix().to_4x4()
    bpy.context.view_layer.update()


def clear_heavy_arms(arm, base, frame):
    if frame in (0, 70):
        return # Exact original seated entry/exit remains authoritative.
    # Offset from each native-sex shoulder, in native armature space. A
    # horizontal outboard stroke clears the horse with blades and long shafts;
    # left-hand bow remains upright and has no draw/release shape key.
    positions = {16: (-.19, .02, .12), 29: (-.22, .06, .17),
                 37: (-.46, -.10, .06), 44: (-.46, -.02, .06), 54: (-.24, -.04, -.02)}
    directions = {16: (-.3, .1, 1), 29: (-.4, .25, 1),
                  37: (-1, -.35, .2), 44: (-1, -.05, .25), 54: (-.6, -.1, .8)}
    right = arm.pose.bones['J_Bip_R_UpperArm'].head.copy()
    arm_to(arm, 'R', right + Vector(positions[frame]), directions[frame])
    left = arm.pose.bones['J_Bip_L_UpperArm'].head.copy()
    arm_to(arm, 'L', left + Vector((.18, -.16, -.14)), (.22, -.08, 1))


def author(arm, base, names=CLIPS):
    assert not any(bpy.data.actions.get(name) for name in names), 'Already authored; use export to keep edits'
    for name, keys in zip(CLIPS, (HEAVY, BREAK)):
        if name not in names:
            continue
        action = bpy.data.actions.new(name)
        action.use_fake_user = True
        action['worldgoing_source_pose'] = 'ride_idle:0'
        action['worldgoing_loop'] = False
        arm.animation_data.action = action
        for frame, offsets in keys:
            set_pose(arm, base)
            for short, degrees in offsets.items():
                bone = arm.pose.bones[bone_name(short)]
                bone.rotation_quaternion = bone.rotation_quaternion @ Euler(tuple(math.radians(v) for v in degrees), 'XYZ').to_quaternion()
            bpy.context.view_layer.update()
            if name == 'ride_heavy':
                clear_heavy_arms(arm, base, frame)
            for bone in arm.pose.bones:
                for prop in ('location', 'rotation_quaternion', 'scale'):
                    bone.keyframe_insert(prop, frame=frame, group=bone.name)
        for curve in action.fcurves:
            for key in curve.keyframe_points:
                key.interpolation = 'BEZIER'
                key.handle_left_type = key.handle_right_type = 'AUTO_CLAMPED'
    arm.animation_data.action = None
    set_pose(arm, base)


def check(arm, base):
    locked = ['J_Bip_C_Hips'] + [b.name for b in arm.pose.bones if any(p in b.name for p in ('UpperLeg', 'LowerLeg', 'Foot', 'ToeBase'))]
    set_pose(arm, base)
    reference = {n: arm.pose.bones[n].matrix.copy() for n in locked}
    report = {'fps': bpy.context.scene.render.fps, 'locked_bones': locked, 'clips': {}}
    for name, length in zip(CLIPS, (70, 9.6)):
        action = bpy.data.actions[name]
        assert abs(action.frame_range[0]) < 1e-6 and abs(action.frame_range[1] - length) < 1e-5
        arm.animation_data.action = action
        max_error = 0.0
        hands = []
        poses = []
        # Include subframes: checking only authored keys misses overshoot.
        for i in range(121):
            frame = length * i / 120
            bpy.context.scene.frame_set(int(frame), subframe=frame % 1)
            bpy.context.view_layer.update()
            for n in locked:
                error = max(abs(arm.pose.bones[n].matrix[r][c] - reference[n][r][c]) for r in range(4) for c in range(4))
                max_error = max(max_error, error)
            hands.append(arm.pose.bones['J_Bip_R_Hand'].head.copy())
            if i in (0, 30, 60, 90, 120):
                poses.append({n: list(arm.matrix_world @ arm.pose.bones[n].head) for n in ('J_Bip_C_Hips', 'J_Bip_C_Head', 'J_Bip_R_Hand', 'J_Bip_L_Hand', 'J_Bip_L_Foot', 'J_Bip_R_Foot')})
            if i in (0, 120):
                assert all(max(abs(arm.pose.bones[n].matrix_basis[r][c] - m[r][c]) for r in range(4) for c in range(4)) < 1e-5 for n, m in base.items()), (name, 'endpoint')
        travel = max((v - hands[0]).length for v in hands)
        assert max_error < 1e-5, (name, 'saddle/stirrup drift', max_error)
        assert travel > 0.15, (name, 'upper body lacks motion', travel)
        report['clips'][name] = {'frames': length, 'seconds': length / 24, 'max_lower_matrix_error': max_error,
                                 'right_hand_excursion_m': travel, 'pose_samples': poses}
    arm.animation_data.action = None
    set_pose(arm, base)
    return report


def export(arm, sex):
    # Work on the in-memory export slice only; saved blend retains original art.
    for obj in bpy.data.objects:
        if obj.animation_data:
            obj.animation_data_clear()
    arm.animation_data_create()
    for action in list(bpy.data.actions):
        if action.name not in CLIPS:
            bpy.data.actions.remove(action)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in (arm, bpy.data.objects['Face_Standard_01']):
        obj.hide_viewport = False; obj.hide_set(False); obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    path = WORK / f'mounted_animations_{sex}.glb'
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
        export_apply=False, export_animations=True, export_animation_mode='ACTIONS',
        export_frame_range=False, export_force_sampling=False, export_skins=True, export_morph=False)
    return append_mounted(BASE / f'standard_anime_{sex}_character_pack.glb', path, OUT / f'candidate_{sex}.glb')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sex', choices=('male', 'female'), required=True)
    parser.add_argument('--stage', choices=('inspect', 'author', 'export', 'check', 'loader-check', 'refine-arms'), required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    WORK.mkdir(exist_ok=True, parents=True); OUT.mkdir(exist_ok=True, parents=True)
    authored = WORK / f'mounted_actions_{args.sex}.blend'
    source = BASE / f'standard_anime_{args.sex}_character_pack.blend' if args.stage in ('author', 'inspect', 'loader-check') else authored
    if args.stage == 'author':
        assert not authored.exists(), 'Do not overwrite editable art; use export'
    bpy.ops.wm.open_mainfile(filepath=str(source))
    bpy.context.preferences.filepaths.save_version = 0
    scene = bpy.context.scene
    assert scene.render.fps == 24 and scene.render.fps_base == 1
    arm = bpy.data.objects['Armature']
    base = idle_pose(arm)
    if args.stage == 'inspect':
        report = {'actions': {a.name: list(a.frame_range) for a in bpy.data.actions},
                  'bones': {b.name: {'head': list(arm.matrix_world @ b.head), 'euler_degrees': [math.degrees(v) for v in b.matrix_basis.to_euler()]} for b in arm.pose.bones if b.name.startswith('J_Bip_')},
                  'morph_tracks': {o.name: [t.name for t in o.data.shape_keys.animation_data.nla_tracks] for o in bpy.data.objects if o.type == 'MESH' and o.data.shape_keys and o.data.shape_keys.animation_data}}
    else:
        if args.stage == 'author':
            author(arm, base)
        elif args.stage == 'refine-arms':
            # Explicit scoped correction after visual QA; the failed source and
            # captures were preserved in mounted/before_arm_clearance.
            bpy.data.actions.remove(bpy.data.actions['ride_heavy'])
            author(arm, base, ('ride_heavy',))
        elif args.stage == 'loader-check':
            from load_authored_mounted_heavy import load_mounted_actions
            load_mounted_actions(arm, args.sex == 'female')
        report = check(arm, base)
        if args.stage in ('author', 'refine-arms'):
            scene.frame_start, scene.frame_end = 0, 70
            bpy.ops.wm.save_as_mainfile(filepath=str(authored), compress=True)
        if args.stage in ('author', 'export', 'refine-arms'):
            report['merge'] = export(arm, args.sex)
    (OUT / f'{args.sex}_{args.stage}.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print('MOUNTED_ACTIONS_PASS', args.sex, args.stage, flush=True)


if __name__ == '__main__':
    main()
