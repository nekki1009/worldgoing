"""Production append binds all new helmet vertices to each existing head bone."""
import sys
from pathlib import Path
import bpy

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/tools/blender'))
from load_authored_chinese_leather_helmet import load_chinese_leather_helmet

for sex in ['male','female']:
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/f'.godot-temp/chinese_leather_helmet_baseline_20260910/standard_anime_{sex}_character_pack.blend'))
    arm=bpy.data.objects['Armature']
    old_names=set(bpy.data.objects.keys())
    parts=load_chinese_leather_helmet(arm,sex=='female')
    assert old_names<=set(bpy.data.objects.keys())
    for obj in parts:
        assert obj.parent==arm
        assert all(m.object==arm for m in obj.modifiers if m.type=='ARMATURE')
        assert obj.data.uv_layers
        assert all(abs(sum(g.weight for g in v.groups)-1)<1e-5 for v in obj.data.vertices)
        assert all(obj.vertex_groups[g.group].name=='J_Bip_C_Head' for v in obj.data.vertices for g in v.groups if g.weight>0)
    print('LEATHER_HELMET_LOADER_PASS',sex,len(parts),flush=True)
