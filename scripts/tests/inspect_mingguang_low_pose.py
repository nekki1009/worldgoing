"""Inspect only the saved Mingguang lower layers, without changing the source."""
import json
import sys
from pathlib import Path
import bpy
from mathutils import Matrix

root = Path(__file__).resolve().parents[2]
work = root / '.godot-temp/mingguang_low_pose_20260912'
args = sys.argv[sys.argv.index('--') + 1:]
sex = args[0]
feet = 'feet' in args
source = root / '.godot-temp/site_combat_assets/candidate' if 'combat' in args else work / ('candidate' if feet else 'baseline')
bpy.ops.wm.open_mainfile(filepath=str(source / f'{sex}.blend'))
arm = next(obj for obj in bpy.data.objects if obj.type == 'ARMATURE')
for track in arm.animation_data.nla_tracks:
    track.mute = True
if feet:
    arm.animation_data.action = bpy.data.actions['get_up']
    boots = [obj for obj in bpy.data.objects if obj.type == 'MESH' and obj.name.startswith('Boots_Leather_01')]
    rows = []
    for frame in range(213):
        time = min(frame / 96, 2.2)
        bpy.context.scene.frame_set(int(time * 24), subframe=time * 24 % 1)
        deps = bpy.context.evaluated_depsgraph_get()
        low, part_name = 100, ''
        for obj in boots:
            evaluated = obj.evaluated_get(deps)
            mesh = evaluated.to_mesh()
            bottom = min((evaluated.matrix_world @ v.co).z for v in mesh.vertices)
            if bottom < low:
                low, part_name = bottom, obj.name
            evaluated.to_mesh_clear()
        if low < -.008:
            rows.append({'time': time, 'min_z': low, 'part': part_name,
                         'feet': {side: list(arm.pose.bones[f'J_Bip_{side}_Foot'].head) for side in ['L', 'R']}})
    (work / f'feet_{sex}.json').write_text(json.dumps(rows, indent=2), encoding='utf-8')
    print(json.dumps(rows, indent=2))
    assert not rows, 'GET_UP_FEET_FLOOR_SCAN_FAILED'
    print('GET_UP_FEET_FLOOR_SCAN_PASS', sex, '213 samples')
    bpy.ops.wm.quit_blender()
    raise SystemExit(0)
parts = [obj for obj in bpy.data.objects if obj.type == 'MESH' and obj.name.startswith('Armor_Mingguang_01_')]
result = {}
for clip, fraction in [('T-Pose', 0), ('get_up', .5), ('rescue', .5)]:
    for bone in arm.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    action = bpy.data.actions[clip]
    arm.animation_data.action = action
    frame = action.frame_range[0] + fraction * (action.frame_range[1] - action.frame_range[0])
    bpy.context.scene.frame_set(int(frame), subframe=frame % 1)
    deps = bpy.context.evaluated_depsgraph_get()
    rows = []
    for obj in parts:
        evaluated = obj.evaluated_get(deps)
        mesh = evaluated.to_mesh()
        points = [evaluated.matrix_world @ vertex.co for vertex in mesh.vertices]
        low = min(point.z for point in points)
        if low < .85:
            rows.append({'name': obj.name, 'vertices': len(mesh.vertices), 'low': low,
                         'high': max(point.z for point in points), 'shape_keys': bool(obj.data.shape_keys),
                         'parent': obj.parent.name if obj.parent else '', 'parent_bone': obj.parent_bone,
                         'matrix': [list(row) for row in obj.matrix_world],
                         'groups': [group.name for group in obj.vertex_groups]})
        evaluated.to_mesh_clear()
    result[clip] = rows
(work / f'inspect_{sex}.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps(result, indent=2))
