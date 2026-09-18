"""Reuse editable caps on the existing skeleton; no second armature/actions."""
from pathlib import Path
import bpy
from mathutils import Matrix

ROOT=Path(__file__).resolve().parents[3]


def load_cloth_hats(armature,is_female=False):
    sex='female' if is_female else 'male'
    source=ROOT/f'assets/characters/human/q35/cloth_hats/cloth_hats_{sex}.blend'
    original_objects=set(bpy.data.objects);original_actions=set(bpy.data.actions)
    with bpy.data.libraries.load(str(source),link=False) as (available,loaded):
        loaded.objects=[name for name in available.objects if name.startswith('Helmet_Cloth_')]
    parts=[]
    for obj in loaded.objects:
        assert obj is not None and obj.type=='MESH'
        bpy.context.collection.objects.link(obj)
        obj.parent=armature;obj.matrix_parent_inverse=Matrix.Identity(4)
        for mod in obj.modifiers:
            if mod.type=='ARMATURE':mod.object=armature
        obj.hide_viewport=obj.hide_render=False
        parts.append(obj)
    for obj in set(bpy.data.objects)-original_objects-set(loaded.objects):
        data=obj.data if obj.type=='ARMATURE' else None
        bpy.data.objects.remove(obj,do_unlink=True)
        if data is not None and data.users==0:bpy.data.armatures.remove(data)
    for action in set(bpy.data.actions)-original_actions:
        assert action.users==int(action.use_fake_user)
        bpy.data.actions.remove(action)
    for style in ('Chinese','Japanese','Western'):
        assert any(obj.name==f'Helmet_Cloth_{style}_01_Crown' for obj in parts)
    return parts
