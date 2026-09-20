"""Append the 15 authored armor/helmet/boots options onto the existing rig."""
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[3]
PREFIXES = (
    'Armor_Japanese_Leather_01', 'Armor_Japanese_Iron_01',
    'Armor_Chinese_Steel_01', 'Armor_Japanese_Steel_01', 'Armor_Western_Steel_01',
    'Helmet_Japanese_Leather_01', 'Helmet_Japanese_Iron_01',
    'Helmet_Japanese_Steel_01', 'Helmet_Western_Steel_01',
    'Boots_Cloth_Western_01', 'Boots_Japanese_Leather_01', 'Boots_Japanese_Iron_01',
    'Boots_Chinese_Steel_01', 'Boots_Japanese_Steel_01', 'Boots_Western_Steel_01',
)


def load_cultural_armor(armature, is_female=False):
    sex = 'female' if is_female else 'male'
    source = ROOT / f'assets/characters/human/q35/equipment_matrix/cultural_armor_{sex}.blend'
    before = set(bpy.data.objects)
    actions = set(bpy.data.actions)
    prefixes = tuple(p + '_' for p in PREFIXES)
    assert not any(o.name.startswith(prefixes) for o in before), 'Cultural armor already loaded'
    with bpy.data.libraries.load(str(source), link=False) as (available, loaded):
        loaded.objects = [name for name in available.objects if name.startswith(prefixes)]
    result = ([], [], [])
    for obj in loaded.objects:
        assert obj is not None and obj.type == 'MESH', source
        bpy.context.collection.objects.link(obj)
        world = obj.matrix_world.copy()
        obj.parent = armature
        obj.matrix_parent_inverse = armature.matrix_world.inverted()
        obj.matrix_world = world
        for modifier in obj.modifiers:
            if modifier.type == 'ARMATURE':
                modifier.object = armature
        obj.hide_viewport = obj.hide_render = False
        obj.hide_set(False)
        result[('armor', 'helmet', 'boots').index(obj['worldgoing_component_slot'])].append(obj)
    assert all(any(o.name.startswith(p + '_') for o in loaded.objects) for p in PREFIXES), 'Incomplete cultural armor source'
    # Appended meshes bring their source armature; remove only those new dependencies.
    for obj in set(bpy.data.objects) - before - set(loaded.objects):
        data = obj.data if obj.type == 'ARMATURE' else None
        bpy.data.objects.remove(obj, do_unlink=True)
        if data is not None and not data.users:
            bpy.data.armatures.remove(data)
    for action in set(bpy.data.actions) - actions:
        assert action.users == int(action.use_fake_user), action.name
        bpy.data.actions.remove(action)
    return result
