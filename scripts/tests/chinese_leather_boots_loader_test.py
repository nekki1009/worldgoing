"""Append both authored pairs and reject cross-leg skin influences."""
import sys
from pathlib import Path
import bpy
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/tools/blender'))
from load_authored_chinese_leather_boots import load_chinese_leather_boots
for sex in ['male','female']:
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/f'.godot-temp/chinese_leather_boots_baseline_20260910/standard_anime_{sex}_character_pack.blend'))
    arm=bpy.data.objects['Armature'];bones=list(arm.data.bones.keys())
    parts=load_chinese_leather_boots(arm,is_female=sex=='female')
    for obj in parts:
        assert obj.parent==arm and obj.data.uv_layers
        assert all(m.object==arm for m in obj.modifiers if m.type=='ARMATURE')
        side=obj.name[-1]
        for v in obj.data.vertices:
            assert abs(sum(g.weight for g in v.groups)-1)<1e-4
            assert all('_'+side+'_' in obj.vertex_groups[g.group].name for g in v.groups)
    assert list(arm.data.bones.keys())==bones
    print('CHINESE_BOOTS_LOADER_PASS',sex,len(parts),flush=True)
