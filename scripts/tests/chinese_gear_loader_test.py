"""Exercise production-loader append and binding, without rebuilding old assets."""
import sys
from pathlib import Path
import bpy

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/tools/blender'))
from load_authored_chinese_gear import load_chinese_gear
from load_authored_chinese_cape import bind_cape_action_tracks

for sex in ['male','female']:
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/f'.godot-temp/chinese_leather_mingguang_baseline_20260910/standard_anime_{sex}_character_pack.blend'))
    arm=bpy.data.objects['Armature']
    armor,helmet=load_chinese_gear(arm,is_female=sex=='female')
    assert len(armor)==46 and len(helmet)==22
    bind_cape_action_tracks(arm,helmet)
    for obj in armor+helmet:
        assert obj.parent==arm
        assert all(m.object==arm for m in obj.modifiers if m.type=='ARMATURE')
        assert obj.data.uv_layers
        assert all(abs(sum(g.weight for g in v.groups)-1)<1e-5 for v in obj.data.vertices)
    plume=next(o for o in helmet if 'WhitePlume' in o.name)
    assert len(plume.data.shape_keys.key_blocks)==3
    assert len(plume.data.shape_keys.animation_data.nla_tracks)>=20
    print('CHINESE_GEAR_LOADER_PASS',sex,len(armor),len(helmet),flush=True)
