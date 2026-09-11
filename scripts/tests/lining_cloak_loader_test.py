"""Exercise existing-rig source append and the scoped cloth repair artifact."""
import sys
from pathlib import Path
import bpy
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/tools/blender'))
from load_authored_chinese_lining import load_chinese_lining
from load_authored_chinese_cape import make_chinese_cape,bind_cape_action_tracks
for sex in ['male','female']:
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/f'.godot-temp/lining_cloak_baseline_20260910/standard_anime_{sex}_character_pack.blend'))
    arm=bpy.data.objects['Armature'];bones=list(arm.data.bones.keys())
    parts=load_chinese_lining(arm,is_female=sex=='female')
    shirt=next(o for o in parts if o.name.endswith('Shirt'))
    assert shirt.data.shape_keys.key_blocks.get('UnderArmor') is not None
    for obj in parts:
        assert obj.parent==arm and obj.data.uv_layers
        assert all(m.object==arm for m in obj.modifiers if m.type=='ARMATURE')
        assert all(abs(sum(g.weight for g in v.groups)-1)<1e-4 for v in obj.data.vertices)
    assert list(arm.data.bones.keys())==bones
    if '--with-cloak' in sys.argv:
        for obj in list(bpy.data.objects):
            if obj.name.startswith('Cape_Chinese_01_'):bpy.data.objects.remove(obj,do_unlink=True)
        cloaks=make_chinese_cape(arm,is_female=sex=='female');bind_cape_action_tracks(arm,cloaks)
        main=next(o for o in cloaks if o.name.endswith('_Main'))
        assert main.get('run_drape_revision')==2
        assert len(main.data.shape_keys.key_blocks)==337
    print('LINING_CLOAK_LOADER_PASS',sex,len(parts),flush=True)
