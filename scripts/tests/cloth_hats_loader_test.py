"""Read-only builder route check, with the original rig/actions retained."""
import sys
from pathlib import Path
import bpy
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/tools/blender'))
from load_authored_cloth_hats import load_cloth_hats
for sex in ('male','female'):
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/f'output/cloth_hats_20260918/baseline/standard_anime_{sex}_character_pack.blend'))
    arm=bpy.data.objects['Armature'];objects=set(bpy.data.objects);actions=set(bpy.data.actions)
    parts=load_cloth_hats(arm,sex=='female')
    assert len(parts)==37 and set(bpy.data.objects)==objects|set(parts)
    assert set(bpy.data.actions)==actions
    for obj in parts:
        assert obj.parent==arm and obj['worldgoing_component_slot']=='helmet'
        assert all(m.object==arm for m in obj.modifiers if m.type=='ARMATURE')
        assert len(obj.vertex_groups)==1 and obj.vertex_groups[0].name=='J_Bip_C_Head'
    print('CLOTH_HATS_LOADER_PASS',sex,len(parts),flush=True)
