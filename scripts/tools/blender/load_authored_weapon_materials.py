"""Append only authored material variants, preserving their source edits."""
from pathlib import Path
import re
import bpy
from mathutils import Matrix

ROOT=Path(__file__).resolve().parents[3]


def load_weapon_materials(armature,is_female=False):
    sex='female' if is_female else 'male'
    source=ROOT/f'assets/characters/human/q35/weapon_materials/weapon_materials_{sex}.blend'
    originals=set(bpy.data.objects);actions=set(bpy.data.actions)
    with bpy.data.libraries.load(str(source),link=False) as (available,loaded):
        loaded.objects=[name for name in available.objects if name.startswith('Weapon_') and any('_'+kind+'_01_' in name for kind in ('Wood','Stone','Steel','Iron'))]
    for obj in loaded.objects:
        assert obj is not None and obj.type=='MESH'
        bpy.context.collection.objects.link(obj);obj.parent=armature;obj.matrix_parent_inverse=Matrix.Identity(4)
        for mod in obj.modifiers:
            if mod.type=='ARMATURE':mod.object=armature
        obj.hide_render=obj.hide_viewport=False
    for obj in set(bpy.data.objects)-originals-set(loaded.objects):
        data=obj.data if obj.type=='ARMATURE' else None
        bpy.data.objects.remove(obj,do_unlink=True)
        if data is not None and data.users==0:bpy.data.armatures.remove(data)
    originals_by_name={action.name:action for action in actions}
    def signature(action):
        return [(curve.data_path,curve.array_index,[(tuple(key.co),tuple(key.handle_left),tuple(key.handle_right),key.interpolation) for key in curve.keyframe_points]) for curve in action.fcurves]
    for action in set(bpy.data.actions)-actions:
        if action.users>int(action.use_fake_user):
            original=originals_by_name.get(re.sub(r'\.\d{3}$','',action.name))
            assert original is not None and signature(action)==signature(original),('Unmatched morph action',action.name)
            action.user_remap(original)
        assert action.users==int(action.use_fake_user),action.name
        bpy.data.actions.remove(action)
    assert len(loaded.objects)>200
    return loaded.objects
