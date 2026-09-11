"""Read-only rest-space measurements for the new leather armor and helmet."""
import json
from pathlib import Path
import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[2]


def inspect(sex):
    source = ROOT / f'assets/characters/human/q35/standard_anime_{sex}_character_pack.blend'
    bpy.ops.wm.open_mainfile(filepath=str(source))
    arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE' and 'J_Bip_C_Head' in o.data.bones)
    body = bpy.data.objects.get(f'Body_Standard_{sex.title()}_Full')
    if body is None:
        body = bpy.data.objects[f'Body_Standard_{sex.title()}']
    points = np.array([body.matrix_world @ v.co for v in body.data.vertices])
    bones = {name: list(arm.matrix_world @ arm.data.bones[name].head_local) for name in [
        'J_Bip_C_Hips', 'J_Bip_C_Spine', 'J_Bip_C_Chest', 'J_Bip_C_UpperChest',
        'J_Bip_C_Neck', 'J_Bip_C_Head', 'J_Bip_L_UpperArm', 'J_Bip_L_LowerArm',
        'J_Bip_L_Hand', 'J_Bip_L_UpperLeg', 'J_Bip_L_LowerLeg']}
    cross_sections = []
    lo, hi = bones['J_Bip_C_Hips'][2], bones['J_Bip_C_Neck'][2]
    for z in np.linspace(lo - .04, hi + .24, 16):
        ring = points[(np.abs(points[:, 2]-z) < .012) & (np.abs(points[:, 0]) < .20)]
        if len(ring):
            cross_sections.append({'z':float(z), 'min':ring.min(axis=0).tolist(), 'max':ring.max(axis=0).tolist()})
    report = {'sex':sex, 'armature':arm.name, 'armature_matrix':list(map(list,arm.matrix_world)),
              'body':body.name, 'body_min':points.min(axis=0).tolist(), 'body_max':points.max(axis=0).tolist(),
              'bones':bones, 'sections':cross_sections,
              'mesh_count':sum(o.type == 'MESH' for o in bpy.context.scene.objects)}
    print('CHINESE_EQUIPMENT_BASE ' + json.dumps(report), flush=True)


if __name__ == '__main__':
    for sex in ['male', 'female']:
        inspect(sex)
