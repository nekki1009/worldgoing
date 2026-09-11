"""Read current body topology and measured run cloth shape before authoring."""
import json,sys
from pathlib import Path
import bpy
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
sex=sys.argv[-1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/f'.godot-temp/lining_cloak_baseline_20260910/standard_anime_{sex}_character_pack.blend'))
arm=next(o for o in bpy.data.objects if o.type=='ARMATURE')
for o in bpy.data.objects:
    if o.type=='MESH' and (o.name.startswith('Body_Standard_') or o.name.startswith('Outfit_')):
        p=np.array([o.matrix_world@v.co for v in o.data.vertices]);print(o.name,len(p),p.min(axis=0),p.max(axis=0),[m.name for m in o.data.materials],flush=True)
for name in ['Neck','Hips','Chest','UpperChest','Spine','L_UpperArm','L_LowerArm','L_Hand']:
    name='J_Bip_'+(name if name.startswith('L_') else 'C_'+name)
    print(name,list(arm.data.bones[name].head_local),list(arm.data.bones[name].tail_local),flush=True)
obj=bpy.data.objects['Cape_Chinese_01_Main'];keys=obj.data.shape_keys
print('CLOAK',len(obj.data.vertices),len(keys.key_blocks),[k.name for k in keys.key_blocks if k.name.startswith('run_')],flush=True)
