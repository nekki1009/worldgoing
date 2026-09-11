"""Read-only joint topology/weight inventory of the current authored packs."""
import bpy
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
sex = sys.argv[sys.argv.index('--') + 1]
bpy.ops.wm.open_mainfile(filepath=str(root / f'assets/characters/human/q35/standard_anime_{sex}_character_pack.blend'))
arm = bpy.data.objects['Armature']
out = {'sex': sex, 'bones': {}, 'bodies': {}}
for side in ('L', 'R'):
    for joint in ('UpperArm', 'LowerArm', 'Hand'):
        bone = arm.data.bones[f'J_Bip_{side}_{joint}']
        out['bones'][bone.name] = {'head': list(arm.matrix_world @ bone.head_local), 'tail': list(arm.matrix_world @ bone.tail_local)}
for obj in bpy.data.objects:
    if not obj.name.startswith('Body_Standard'):
        continue
    data = {'vertices': len(obj.data.vertices), 'polygons': len(obj.data.polygons), 'shape_keys': list(obj.data.shape_keys.key_blocks.keys()) if obj.data.shape_keys else [], 'modifiers': [(m.name, m.type) for m in obj.modifiers], 'matrix': [list(row) for row in obj.matrix_world], 'joints': {}}
    for side in ('L', 'R'):
        for joint, radius in [('LowerArm', .10), ('Hand', .065)]:
            bone = arm.data.bones[f'J_Bip_{side}_{joint}']
            center = arm.matrix_world @ bone.head_local
            vertices = []
            for v in obj.data.vertices:
                pos = obj.matrix_world @ v.co
                if (pos-center).length < radius:
                    vertices.append({'index': v.index, 'co': list(pos), 'weights': {obj.vertex_groups[g.group].name: round(g.weight, 5) for g in v.groups if g.weight > .001}})
            data['joints'][bone.name] = vertices
    out['bodies'][obj.name] = data
dest = root / '.godot-temp/joint_refinement'
dest.mkdir(parents=True, exist_ok=True)
(dest / f'{sex}_inventory.json').write_text(json.dumps(out, indent=2), encoding='utf-8')
print('BODY_JOINT_INVENTORY', sex, json.dumps({n: {k:v for k,v in d.items() if k!='joints'} for n,d in out['bodies'].items()}))
print('JOINT_CENTERS', json.dumps(out['bones']))
