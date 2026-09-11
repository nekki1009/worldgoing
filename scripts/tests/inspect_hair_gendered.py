"""Read actual current rest-pose head/scalp dimensions in Blender world space."""
import sys
from pathlib import Path
import bpy
from mathutils import Vector

root = Path(__file__).resolve().parents[2]
for sex in ['male', 'female']:
    bpy.ops.wm.open_mainfile(filepath=str(root/f'assets/characters/human/q35/standard_anime_{sex}_character_pack.blend'))
    arm = bpy.data.objects['Armature']
    for name in ['J_Bip_C_Head', 'J_Bip_C_Neck', 'J_Bip_C_UpperChest']:
        b = arm.data.bones[name]
        print('HAIR_HEAD', sex, name, list(arm.matrix_world @ b.head_local), flush=True)
    for o in bpy.data.objects:
        if o.type == 'MESH' and (o.name.startswith(('Hair_', 'Face_Standard_01')) or o.name == ('Body_Standard_Male' if sex == 'male' else 'Body_Standard_Female')):
            pts = [o.matrix_world @ v.co for v in o.data.vertices]
            if o.name.startswith('Body'): pts = [v for v in pts if v.z > 1.45]
            print('HAIR_BOUNDS',sex,o.name,[round(min(v[i] for v in pts),4) for i in range(3)],[round(max(v[i] for v in pts),4) for i in range(3)],'matrix', [list(r) for r in o.matrix_world],flush=True)
