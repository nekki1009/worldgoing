"""Load the authored IRON set without rebuilding shapes or changing the rig."""
from pathlib import Path
import bpy
from mathutils import Matrix

ROOT=Path(__file__).resolve().parents[3]
PREFIXES=('Armor_Western_Iron_01_', 'Helmet_Western_Iron_01_', 'Boots_Western_Iron_01_')


def load_western_iron(armature, is_female=False):
    sex='female' if is_female else 'male'
    source=ROOT/f'assets/characters/human/q35/western_plate/western_plate_{sex}.blend'
    original_objects=set(bpy.data.objects)
    original_actions=set(bpy.data.actions)
    with bpy.data.libraries.load(str(source),link=False) as (available,loaded):
        loaded.objects=[name for name in available.objects if name.startswith(PREFIXES)]
    armor,helmet,boots=[],[],[]
    for obj in loaded.objects:
        assert obj is not None and obj.type=='MESH',source
        bpy.context.collection.objects.link(obj)
        obj.parent=armature
        obj.matrix_parent_inverse=Matrix.Identity(4)
        for modifier in obj.modifiers:
            if modifier.type=='ARMATURE':modifier.object=armature
        obj.hide_viewport=obj.hide_render=False
        next(group for group,prefix in zip((armor,helmet,boots),PREFIXES) if obj.name.startswith(prefix)).append(obj)
    # Appending skinned meshes also imports their source rig as a dependency.
    # After rebinding, discard only new dependency objects (rig/VRM colliders)
    # and orphan clips; nothing that existed before this append is removed.
    for obj in set(bpy.data.objects)-original_objects-set(loaded.objects):
        data=obj.data if obj.type=='ARMATURE' else None
        bpy.data.objects.remove(obj,do_unlink=True)
        if data is not None and data.users==0:bpy.data.armatures.remove(data)
    for action in set(bpy.data.actions)-original_actions:
        assert action.users==int(action.use_fake_user),action.name
        bpy.data.actions.remove(action)
    assert armor and helmet and boots,'Incomplete western iron source: '+str(source)
    return armor,helmet,boots
