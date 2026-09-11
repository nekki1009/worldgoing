"""Blender smoke test for the actual production loader, without rebuilding armor."""
import sys
from pathlib import Path
import bpy

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/tools/blender'))
from make_chinese_cape import make_chinese_cape, bind_cape_action_tracks

for sex in ['male','female']:
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/f'.godot-temp/chinese_cape_remake_baseline/standard_anime_{sex}_character_pack.blend'))
    arm=next(o for o in bpy.data.objects if o.type=='ARMATURE')
    bone_names=list(arm.data.bones.keys())
    for obj in list(bpy.data.objects):
        if obj.name.startswith('Cape_Chinese_01'): bpy.data.objects.remove(obj,do_unlink=True)
    parts=make_chinese_cape(arm,is_female=sex=='female')
    assert len(parts)==7
    bind_cape_action_tracks(arm,parts)
    assert list(arm.data.bones.keys())==bone_names
    for obj in parts:
        assert obj.parent==arm
        assert all(m.object==arm for m in obj.modifiers if m.type=='ARMATURE')
        assert obj.data.uv_layers
        for vertex in obj.data.vertices:
            assert abs(sum(g.weight for g in vertex.groups)-1)<1e-5
        if obj.name.endswith(('_Main','_Mantle')):
            assert len(obj.data.shape_keys.key_blocks)==337
            for track in obj.data.shape_keys.animation_data.nla_tracks:
                assert any(t.name==track.name and any(s.action.name==track.name for s in t.strips) for t in arm.animation_data.nla_tracks)
    print('CHINESE_CLOAK_PRODUCTION_LOADER_PASS',sex,flush=True)
