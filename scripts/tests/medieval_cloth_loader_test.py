"""Read-only Blender integration check for the reassigned cloth armor catalog."""
import sys
from pathlib import Path
import bpy

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/tools/blender'))
from load_authored_medieval_cloth import load_medieval_cloth

for sex in ['male','female']:
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/f'output/medieval_cloth_20260916/baseline/standard_anime_{sex}_character_pack.blend'))
    arm=bpy.data.objects['Armature']
    bone_names=[bone.name for bone in arm.data.bones]
    parts=load_medieval_cloth(arm,sex=='female')
    assert len(parts)==(31 if sex=='male' else 28)
    assert all(obj['worldgoing_component_slot']=='armor' and obj['worldgoing_armor_category']=='cloth' for obj in parts)
    assert not any(obj.name.endswith('SkirtArmored') for obj in parts)
    assert [bone.name for bone in arm.data.bones]==bone_names
    assert len([obj for obj in parts if obj.name.endswith('Skirt') and len(obj.data.shape_keys.key_blocks)>300])==3
    assert all(obj.parent==arm for obj in parts)
    print('CLOTH_ARMOR_LOADER_PASS',sex,len(parts),'native bones/morphs preserved; no armored-skirt prototype',flush=True)
