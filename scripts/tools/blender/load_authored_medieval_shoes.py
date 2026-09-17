"""Append authored male/female footwear to the existing skeleton, without rebuilding."""
from pathlib import Path
import bpy
from mathutils import Matrix

ROOT = Path(__file__).resolve().parents[3]


def load_medieval_shoes(armature, is_female=False):
    sex = 'female' if is_female else 'male'
    source = ROOT / f'assets/characters/human/q35/medieval_shoes/medieval_shoes_{sex}.blend'
    original_objects=set(bpy.data.objects)
    original_actions=set(bpy.data.actions)
    with bpy.data.libraries.load(str(source), link=False) as (available, loaded):
        loaded.objects = [name for name in available.objects if name.startswith('Boots_Medieval_')]
    parts = []
    for obj in loaded.objects:
        if obj is None or obj.type != 'MESH': continue
        bpy.context.collection.objects.link(obj)
        obj.parent = armature
        obj.matrix_parent_inverse = Matrix.Identity(4)
        for mod in obj.modifiers:
            if mod.type == 'ARMATURE': mod.object = armature
        obj.hide_viewport = obj.hide_render = False
        parts.append(obj)
    # Remove only the just-appended rig dependencies after native rebinding.
    for obj in set(bpy.data.objects)-original_objects-set(loaded.objects):
        data=obj.data if obj.type=='ARMATURE' else None
        bpy.data.objects.remove(obj,do_unlink=True)
        if data is not None and data.users==0:bpy.data.armatures.remove(data)
    for action in set(bpy.data.actions)-original_actions:
        assert action.users==int(action.use_fake_user),action.name
        bpy.data.actions.remove(action)
    for style in ('Chinese', 'Japanese', 'European'):
        assert all(any(obj.name == f'Boots_Medieval_{style}_01_Upper_{side}' for obj in parts) for side in ('L','R'))
    return parts
