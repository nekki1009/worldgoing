"""Verify the authored hair source loads onto the existing rig, without rebuilding."""
import sys
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/tools/blender'))
from load_authored_gendered_hair import load_gendered_hair

for sex in ['male','female']:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    source = ROOT/f'.godot-temp/hair_gendered/baseline/standard_anime_{sex}_character_pack.blend'
    with bpy.data.libraries.load(str(source),link=False) as (available,loaded): loaded.objects = ['Armature']
    arm = loaded.objects[0]
    bpy.context.scene.collection.objects.link(arm)
    objects = load_gendered_hair(arm,sex == 'female')
    assert len(objects) == (8 if sex == 'female' else 5)
    assert len([o for o in bpy.context.scene.objects if o.type == 'ARMATURE']) == 1
    assert all(o.parent == arm for o in objects)
    assert all(m.object == arm for o in objects for m in o.modifiers if m.type == 'ARMATURE')
    assert all(o.data.uv_layers for o in objects)
    assert all(g.name in arm.data.bones for o in objects for g in o.vertex_groups)
    print('GENDERED_HAIR_LOADER_PASS',sex,len(objects),flush=True)
