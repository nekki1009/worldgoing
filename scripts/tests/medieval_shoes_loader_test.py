"""Builder route test without saving or rebuilding the formal packs."""
import sys
from pathlib import Path
import bpy

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/tools/blender'))
from load_authored_medieval_shoes import load_medieval_shoes

for sex in ('male','female'):
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/f'output/medieval_shoes_20260916/baseline/standard_anime_{sex}_character_pack.blend'))
    arm=bpy.data.objects['Armature']
    before=set(bpy.data.objects)
    actions=set(bpy.data.actions)
    parts=load_medieval_shoes(arm,sex=='female')
    assert len(parts)==62
    assert set(bpy.data.objects)==before|set(parts)
    assert set(bpy.data.actions)==actions
    for part in parts:
        assert part.parent==arm and part['worldgoing_component_slot']=='boots'
        assert all(mod.object==arm for mod in part.modifiers if mod.type=='ARMATURE')
        assert len(part.data.vertices)>0
    print('MEDIEVAL_SHOES_LOADER_PASS',sex,len(parts),flush=True)
