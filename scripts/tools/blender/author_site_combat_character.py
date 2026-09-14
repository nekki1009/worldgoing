"""Append scoped combat assets to the saved, reviewed character (never rebuild it)."""
import json
import math
import shutil
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / '.godot-temp/site_combat_assets'
stage, sex = sys.argv[sys.argv.index('--') + 1:]
COMBAT_ACTIONS = ['guard_raise', 'guard_lower', 'guard_break', 'unconscious', 'get_up',
                 'rescue', 'reload_bow', 'reload_crossbow'] + [
    prefix + suffix for prefix in ['guard_weapon', 'guard_polearm'] for suffix in ['', '_raise', '_lower', '_break']]
stem = f'standard_anime_{sex}_character_pack'
source_dir = WORK / 'baseline'
if not (source_dir / (stem + '.blend')).exists():
    source_dir = ROOT / 'assets/characters/human/q35'
bpy.ops.wm.open_mainfile(filepath=str(WORK / 'candidate' / f'{sex}.blend' if stage == 'export' or stage in COMBAT_ACTIONS else source_dir / (stem + '.blend')))
bpy.context.preferences.filepaths.save_version = 0 # Explicit scoped baseline is retained separately.
arm = next(obj for obj in bpy.data.objects if obj.type == 'ARMATURE')
track_mutes = {track.name: track.mute for track in arm.animation_data.nla_tracks}
for track in arm.animation_data.nla_tracks:
    track.mute = True


def read_pose(clip, fraction):
    action = bpy.data.actions[clip]
    arm.animation_data.action = action
    frame = action.frame_range[0] + fraction * (action.frame_range[1] - action.frame_range[0])
    bpy.context.scene.frame_set(int(frame), subframe=frame % 1)
    return snapshot()


def snapshot():
    return {bone.name: tuple(part.copy() for part in bone.matrix_basis.decompose()) for bone in arm.pose.bones}


def apply_pose(pose):
    arm.animation_data.action = None
    for name, (location, rotation, scale) in pose.items():
        bone = arm.pose.bones[name]
        bone.rotation_mode = 'QUATERNION'
        bone.location, bone.rotation_quaternion, bone.scale = location, rotation, scale
    bpy.context.view_layer.update()


def copy_pose(pose):
    return {name: tuple(part.copy() for part in values) for name, values in pose.items()}


def mix_pose(a, b, factor):
    return {name: (location.lerp(b[name][0], factor), rotation.slerp(b[name][1], factor),
                   scale.lerp(b[name][2], factor)) for name, (location, rotation, scale) in a.items()}


def point_bone(name, start, end):
    bone = arm.pose.bones[name]
    rest = bone.bone.matrix_local.to_quaternion()
    turn = (rest @ Vector((0, 1, 0))).rotation_difference((end - start).normalized())
    bone.matrix = Matrix.Translation(start) @ (turn @ rest).to_matrix().to_4x4()
    bpy.context.view_layer.update()


def limb_to(upper_name, lower_name, tip_name, target, pole):
    upper, lower = arm.pose.bones[upper_name], arm.pose.bones[lower_name]
    origin = upper.head.copy()
    first = (upper.bone.tail_local - upper.bone.head_local).length
    second = (lower.bone.tail_local - lower.bone.head_local).length
    direction = Vector(target) - origin
    distance = min(first + second - 0.0001, max(abs(first - second) + 0.0001, direction.length))
    direction.normalize()
    bend = Vector(pole) - origin
    bend = (bend - direction * bend.dot(direction)).normalized()
    along = (first * first - second * second + distance * distance) / (2 * distance)
    joint = origin + direction * along + bend * math.sqrt(max(0, first * first - along * along))
    endpoint = origin + direction * distance
    point_bone(upper_name, origin, joint)
    point_bone(lower_name, joint, endpoint)
    tip = arm.pose.bones[tip_name]
    tip.matrix = Matrix.Translation(endpoint) @ tip.bone.matrix_local.to_quaternion().to_matrix().to_4x4()
    bpy.context.view_layer.update()


def kneeling_pose(height, reach=False, sitting=False):
    # Solve the existing limbs against explicit ground contacts; no extra bones.
    apply_pose(read_pose('T-Pose', 0))
    hips = arm.pose.bones['J_Bip_C_Hips']
    scale = hips.bone.head_local.z / 1.008
    hips.matrix = Matrix.Translation(Vector((0, -.20 * scale if reach else 0.0, height * scale))) @ hips.bone.matrix_local.to_quaternion().to_matrix().to_4x4()
    bpy.context.view_layer.update()
    for name, angle in [('J_Bip_C_Spine', 45 if reach else 8), ('J_Bip_C_Chest', 25 if reach else 6), ('J_Bip_C_Head', 0)]:
        arm.pose.bones[name].rotation_quaternion = Quaternion(Vector((1, 0, 0)), math.radians(angle))
    bpy.context.view_layer.update()
    for side, sign, foot_y in [('L', 1, -0.65 if sitting else -0.40), ('R', -1, -0.67 if sitting else 0.42)]:
        prefix = f'J_Bip_{side}_'
        limb_to(prefix + 'UpperLeg', prefix + 'LowerLeg', prefix + 'Foot',
                Vector((sign * .13, foot_y, .10)) * scale, Vector((sign * .13, -1, .35)) * scale)
        target = Vector((sign * .30, .13, .10)) * scale if sitting else Vector((sign * .23, -.75 if reach else -.25, .15 if reach else .62)) * scale
        limb_to(prefix + 'UpperArm', prefix + 'LowerArm', prefix + 'Hand', target,
                Vector((sign * .65, -.1, .55)) * scale)
        if reach:
            hand = arm.pose.bones[prefix + 'Hand']
            point_bone(hand.name, hand.head, hand.head + Vector((0, -.12, 0)))
    return snapshot()


def add_action(name, keys):
    if bpy.data.actions.get(name):
        bpy.data.actions.remove(bpy.data.actions[name])
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    fps = bpy.context.scene.render.fps
    boots = {side: [obj for obj in bpy.data.objects if obj.type == 'MESH' and
                   obj.name.startswith('Boots_Leather_01') and obj.name.endswith('_' + side)]
             for side in ['L', 'R']} if name == 'get_up' else {}
    # Grounded get-up needs intermediate leg poses; other authored clips keep
    # 24 Hz and all clips retain their exact fractional event/end times.
    sample_fps = 48 if name == 'get_up' else fps
    times = sorted(set([i / sample_fps for i in range(math.ceil(keys[-1][0] * sample_fps))] + [key[0] for key in keys]))
    for time in times:
        index = next((i for i in range(1, len(keys)) if keys[i][0] >= time), len(keys) - 1)
        a, b = keys[index - 1], keys[index]
        fraction = max(0, min(1, (time - a[0]) / max(.0001, b[0] - a[0])))
        fraction = fraction * fraction * (3 - 2 * fraction)
        pose = mix_pose(a[1], b[1], fraction)
        apply_pose(pose)
        if name == 'get_up' and .65 < time < 1.25:
            # Quaternion interpolation swings the rear ankle below the floor.
            # Author its foot path above ground, then solve the same two bones.
            scale = arm.data.bones['J_Bip_C_Hips'].head_local.z / 1.008
            for side, sign, start_y, end_y in [('L', 1, -.65, -.40), ('R', -1, -.67, .42)]:
                prefix = f'J_Bip_{side}_'
                height = .10 + (.16 * math.sin(math.pi * fraction) if side == 'R' else 0.0)
                target = Vector((sign * .13, start_y + (end_y - start_y) * fraction, height)) * scale
                limb_to(prefix + 'UpperLeg', prefix + 'LowerLeg', prefix + 'Foot',
                        target, Vector((sign * .13, -1, .35)) * scale)
        if name == 'get_up':
            # Ground contacts need the sole, not merely an ankle above zero.
            # Keep each foot's current orientation and bend plane, moving only
            # the two existing leg bones when the actual boot crosses ground.
            for side in ['L', 'R']:
                prefix = f'J_Bip_{side}_'
                for _ in range(3):
                    deps = bpy.context.evaluated_depsgraph_get()
                    bottom = math.inf
                    for obj in boots[side]:
                        evaluated = obj.evaluated_get(deps)
                        mesh = evaluated.to_mesh()
                        bottom = min(bottom, min((evaluated.matrix_world @ v.co).z for v in mesh.vertices))
                        evaluated.to_mesh_clear()
                    if bottom >= -.005:
                        break
                    foot = arm.pose.bones[prefix + 'Foot']
                    orientation = foot.matrix.to_quaternion()
                    target = foot.head + Vector((0, 0, .008 - bottom))
                    pole = arm.pose.bones[prefix + 'LowerLeg'].head.copy()
                    if time >= .65:
                        # A nearly straight knee has an unstable current bend
                        # plane. Keep the authored forward bend through standing.
                        scale = arm.data.bones['J_Bip_C_Hips'].head_local.z / 1.008
                        pole = Vector((.13 if side == 'L' else -.13, -1, .35)) * scale
                    limb_to(prefix + 'UpperLeg', prefix + 'LowerLeg', prefix + 'Foot', target, pole)
                    foot.matrix = Matrix.Translation(foot.head) @ orientation.to_matrix().to_4x4()
                    bpy.context.view_layer.update()
        arm.animation_data.action = action
        for bone in arm.pose.bones:
            bone.keyframe_insert(data_path='rotation_quaternion', frame=time * fps)
            bone.keyframe_insert(data_path='location', frame=time * fps)
    for curve in action.fcurves:
        for key in curve.keyframe_points:
            key.interpolation = 'LINEAR'
    return action


def author_actions(only=''):
    idle, guard = read_pose('idle', 0), read_pose('guard', 1)
    down = read_pose('down', 1)
    broken = read_pose('hit_back', .42)
    kneel, help_pose = kneeling_pose(.50), kneeling_pose(.30, True)
    seated = kneeling_pose(.22, sitting=True)
    kneel_armed, seated_armed = copy_pose(kneel), copy_pose(seated)
    for name in guard:
        if any(finger in name for finger in ['Index', 'Middle', 'Ring', 'Little', 'Thumb']):
            kneel_armed[name] = guard[name]
            seated_armed[name] = guard[name]
    breath = copy_pose(down)
    location, rotation, scale = breath['J_Bip_C_Chest']
    breath['J_Bip_C_Chest'] = (location, rotation @ Quaternion(Vector((1, 0, 0)), .018), scale)
    bow_start, bow_nock = read_pose('attack_bow', 0), read_pose('attack_bow', .25)
    cross_start, cross_load = read_pose('attack_crossbow', 0), read_pose('attack_crossbow', .60)
    scale = arm.data.bones['J_Bip_C_Hips'].head_local.z / 1.008
    def pick_ammo(base, target, side='R'):
        apply_pose(base)
        prefix = f'J_Bip_{side}_'
        limb_to(prefix + 'UpperArm', prefix + 'LowerArm', prefix + 'Hand',
                Vector(target) * scale, Vector((-.65 if side == 'R' else .65, -.15, .95)) * scale)
        for name in guard:
            if name.startswith(prefix) and any(finger in name for finger in ['Index', 'Middle', 'Ring', 'Little', 'Thumb']):
                bone = arm.pose.bones[name]
                bone.rotation_quaternion = guard[name][1]
        return snapshot()
    bow_pick = pick_ammo(bow_start, (-.27, .015, 1.21))
    cross_pick = pick_ammo(cross_start, (-.27, .015, 1.13), 'L')
    cross_load = pick_ammo(cross_start, (-.09, -.36, 1.36), 'L')
    def weapon_guard(polearm):
        apply_pose(idle)
        # Physical cross-body guard: put the existing hilt/haft in front of the
        # torso. A polearm gets a second hand on its shaft, not on a sword edge.
        for side, target in [('R', (-.25, -.38, 1.13)),
                             ('L', (.28, -.38, 1.24) if polearm else (.26, -.18, 1.12))]:
            prefix = f'J_Bip_{side}_'
            limb_to(prefix + 'UpperArm', prefix + 'LowerArm', prefix + 'Hand',
                    Vector(target) * scale, Vector((-.65 if side == 'R' else .65, -.12, .90)) * scale)
        hand = arm.pose.bones['J_Bip_R_Hand']
        turn = Vector((0, -1, 0)).rotation_difference(Vector((1, 0, .20)).normalized())
        hand.matrix = Matrix.Translation(hand.head) @ (turn @ hand.bone.matrix_local.to_quaternion()).to_matrix().to_4x4()
        for name in guard:
            if any(finger in name for finger in ['Index', 'Middle', 'Ring', 'Little', 'Thumb']):
                arm.pose.bones[name].rotation_quaternion = guard[name][1]
        bpy.context.view_layer.update()
        return snapshot()
    specs = {
        'guard_raise': [(0, idle), (.15, guard)],
        'guard_lower': [(0, guard), (.15, idle)],
        'guard_break': [(0, guard), (.09, broken), (.32, broken), (.4, idle)],
        'unconscious': [(0, down), (1.2, breath), (2.4, down)],
        'get_up': [(0, down), (.65, seated_armed), (1.25, kneel_armed), (1.55, kneel_armed), (2.2, idle)],
        'rescue': [(0, idle), (.55, kneel), (1, help_pose), (1.5, kneel), (2, help_pose),
                   (2.5, kneel), (3, help_pose), (3.45, kneel), (4, idle)],
        'reload_bow': [(0, bow_start), (.4, bow_pick), (.6, bow_pick), (.9, bow_nock), (1.15, bow_start)],
        'reload_crossbow': [(0, cross_start), (.4, cross_pick), (.6, cross_pick), (1.1, cross_load), (1.5, cross_start)],
    }
    for label, pose in [('guard_weapon', weapon_guard(False)), ('guard_polearm', weapon_guard(True))]:
        break_pose = broken
        if label == 'guard_polearm':
            # A long shaft must deflect sideways, not inherit the short blade's
            # downward wrist angle and drive its point through the ground.
            apply_pose(broken)
            hand = arm.pose.bones['J_Bip_R_Hand']
            turn = Vector((0, -1, 0)).rotation_difference(Vector((-1, .3, .08)).normalized())
            hand.matrix = Matrix.Translation(hand.head) @ (turn @ hand.bone.matrix_local.to_quaternion()).to_matrix().to_4x4()
            bpy.context.view_layer.update()
            break_pose = snapshot()
        specs[label] = [(0, pose), (1.2, pose)]
        specs[label + '_raise'] = [(0, idle), (.15, pose)]
        specs[label + '_lower'] = [(0, pose), (.15, idle)]
        specs[label + '_break'] = [(0, pose), (.09, break_pose), (.32, break_pose), (.4, idle)]
    for name, keys in specs.items():
        if not only or name == only:
            add_action(name, keys)
    return list(specs)

if stage == 'inspect':
    report = {'fps': bpy.context.scene.render.fps, 'armature': arm.name, 'actions': {}, 'poses': {}}
    for action in bpy.data.actions:
        report['actions'][action.name] = list(action.frame_range)
    for name in ['idle', 'guard', 'down', 'hit_back', 'attack_bow', 'attack_crossbow']:
        action = bpy.data.actions[name]
        arm.animation_data.action = action
        report['poses'][name] = []
        for fraction in [0, 0.5, 1]:
            frame = action.frame_range[0] + fraction * (action.frame_range[1] - action.frame_range[0])
            bpy.context.scene.frame_set(int(frame), subframe=frame % 1)
            report['poses'][name].append({bone.name: {'xyz': list(arm.matrix_world @ bone.head),
                'rotation': list(bone.rotation_quaternion), 'location': list(bone.location)}
                for bone in arm.pose.bones if bone.name in ['J_Bip_C_Hips', 'J_Bip_C_Head',
                'J_Bip_L_Hand', 'J_Bip_R_Hand', 'J_Bip_L_Foot', 'J_Bip_R_Foot']})
    (WORK / f'inspect_{sex}.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps({'fps': report['fps'], 'actions': report['actions']}, indent=2))
elif stage == 'props':
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sys.path.insert(0, str(Path(__file__).parent))
    from author_site_combat_props import build_props
    candidate = WORK / 'candidate'
    props = build_props(candidate / 'combat_props.glb')
    bpy.ops.wm.save_as_mainfile(filepath=str(candidate / 'combat_props.blend'))
    print('SITE_COMBAT_PROPS_AUTHORED', [obj.name for obj in props])
elif stage in ['author', 'export'] or stage in COMBAT_ACTIONS:
    names = author_actions(stage if stage in COMBAT_ACTIONS else '') if stage != 'export' else COMBAT_ACTIONS
    assert all(bpy.data.actions.get(name) for name in names), 'Missing authored combat action'
    candidate = WORK / 'candidate'
    candidate.mkdir(exist_ok=True)
    for track in arm.animation_data.nla_tracks:
        track.mute = track_mutes[track.name]
    arm.animation_data.action = None
    if stage != 'export':
        bpy.ops.wm.save_as_mainfile(filepath=str(candidate / f'{sex}.blend'))
    # The editable source above retains every original action. The temporary
    # export scene needs only this slice; avoid exporting unrelated Euler clips.
    for action in list(bpy.data.actions):
        if action.name not in names:
            bpy.data.actions.remove(action)
    # Export only the rig and one mesh, then append NEW channels to original GLB.
    # All original mesh/texture/skin/animation binary bytes stay untouched.
    bpy.ops.object.select_all(action='DESELECT')
    mesh = next(obj for obj in bpy.data.objects if obj.name == 'Face_Standard_01')
    for obj in [arm, mesh]:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    subset = candidate / f'{sex}_animation_subset.glb'
    bpy.ops.export_scene.gltf(filepath=str(subset), export_format='GLB', use_selection=True,
        export_apply=False, export_animations=True, export_animation_mode='ACTIONS',
        export_frame_range=False, export_force_sampling=False, export_skins=True, export_morph=False)
    sys.path.insert(0, str(Path(__file__).parent))
    from author_chinese_cape import preserve_legacy_clips
    destination = candidate / f'{sex}.glb'
    shutil.copyfile(source_dir / (stem + '.glb'), destination)
    # Re-author only this slice when the formal source already contains it.
    import struct
    raw = destination.read_bytes()
    size = struct.unpack_from('<I', raw, 12)[0]
    doc = json.loads(raw[20:20+size])
    doc['animations'] = [a for a in doc['animations'] if a['name'] not in names]
    encoded = json.dumps(doc,separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    tail = raw[20+size:]
    destination.write_bytes(struct.pack('<4sII', b'glTF', 2, 20+len(encoded)+len(tail)) +
                            struct.pack('<I4s', len(encoded), b'JSON') + encoded + tail)
    preserve_legacy_clips(sex, destination, subset)
    metadata = json.loads((source_dir / (stem + '.json')).read_text(encoding='utf-8'))
    metadata['site_combat_actions'] = names
    (candidate / f'{sex}.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8')
    print('SITE_COMBAT_ACTIONS_AUTHORED', sex, names)
else:
    raise ValueError('Unsupported stage: ' + stage)
