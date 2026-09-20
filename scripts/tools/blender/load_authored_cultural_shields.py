"""Append authored held shields to the caller's rig without rebuilding artwork."""
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[3]
PREFIXES = tuple(f'Shield_{s}_{m}_01' for s in ('Chinese', 'Japanese', 'Western')
                 for m in ('Wood', 'Stone', 'Iron', 'Steel') if (s, m) != ('Western', 'Iron'))


def load_cultural_shields(armature, is_female=False):
    sex = 'female' if is_female else 'male'
    source = ROOT / f'assets/characters/human/q35/equipment_matrix/cultural_shields_{sex}.blend'
    original_objects = set(bpy.data.objects)
    original_actions = set(bpy.data.actions)
    assert not any(o.type == 'MESH' and o.name.startswith(PREFIXES) for o in original_objects), 'Shields already loaded'
    with bpy.data.libraries.load(str(source), link=False) as (available, loaded):
        loaded.objects = [name for name in available.objects if any(name.startswith(p+'_') for p in PREFIXES)]
    parts = list(loaded.objects)
    for obj in parts:
        assert obj is not None and obj.type == 'MESH'
        bpy.context.collection.objects.link(obj)
        world = obj.matrix_world.copy()
        obj.parent = armature
        obj.matrix_parent_inverse = armature.matrix_world.inverted()
        obj.matrix_world = world
        for mod in obj.modifiers:
            if mod.type == 'ARMATURE':
                mod.object = armature
        obj.hide_viewport = obj.hide_render = False
        obj.hide_set(False)
    for obj in set(bpy.data.objects)-original_objects-set(parts):
        data = obj.data if obj.type == 'ARMATURE' else None
        bpy.data.objects.remove(obj, do_unlink=True)
        if data is not None and data.users == 0:
            bpy.data.armatures.remove(data)
    for action in set(bpy.data.actions)-original_actions:
        assert action.users == int(action.use_fake_user)
        bpy.data.actions.remove(action)
    for prefix in PREFIXES:
        assert any(o.name == prefix+'_Handle' for o in parts), prefix
        assert any(o.name == prefix+'_ArmStrap' for o in parts), prefix
        assert any(o.name == prefix+'_Holstered_Handle' for o in parts), prefix
        assert any(o.name == prefix+'_Holstered_ArmStrap' for o in parts), prefix
    return parts
