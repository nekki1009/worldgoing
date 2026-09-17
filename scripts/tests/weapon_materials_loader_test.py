"""Author-source reload must preserve coordinates and reuse the original rig."""
import sys
from pathlib import Path
import bpy
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/tools/blender'))
from load_authored_weapon_materials import load_weapon_materials


for sex in ('male','female'):
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/f'assets/characters/human/q35/weapon_materials/weapon_materials_{sex}.blend'))
    expected={obj.name:np.array([obj.matrix_world@v.co for v in obj.data.vertices]) for obj in bpy.data.objects if obj.type=='MESH' and obj.name.startswith('Weapon_') and any('_'+kind+'_01_' in obj.name for kind in ('Wood','Stone','Iron','Steel'))}
    bpy.ops.wm.open_mainfile(filepath=str(ROOT/f'output/weapon_materials_20260917/baseline/standard_anime_{sex}_character_pack.blend'))
    arm=bpy.data.objects['Armature'];before=set(bpy.data.objects);actions=set(bpy.data.actions)
    parts=load_weapon_materials(arm,sex=='female')
    assert {o.name for o in parts}==set(expected)
    assert set(bpy.data.objects)==before|set(parts)
    assert set(bpy.data.actions)==actions
    for obj in parts:
        assert obj.parent==arm and all(mod.object==arm for mod in obj.modifiers if mod.type=='ARMATURE')
        assert np.allclose(np.array([obj.matrix_world@v.co for v in obj.data.vertices]),expected[obj.name],atol=1e-7),obj.name
        assert all(any(g.weight>.999 for g in v.groups) for v in obj.data.vertices),obj.name
    print('WEAPON_MATERIAL_LOADER_PASS',sex,len(parts),'same vertices, original rig/actions preserved',flush=True)
