"""Append the six editable clothing variants, without regenerating their art."""
from pathlib import Path
import bpy
from mathutils import Matrix
from load_authored_chinese_cape import bind_cape_action_tracks

ROOT=Path(__file__).resolve().parents[3]


def load_medieval_cloth(armature,is_female=False):
    sex='female' if is_female else 'male'
    source=ROOT/f'assets/characters/human/q35/medieval_cloth/medieval_cloth_{sex}.blend'
    with bpy.data.libraries.load(str(source),link=False) as (available,loaded):
        loaded.objects=[name for name in available.objects if name.startswith('Outfit_Medieval_') and not name.endswith('SkirtArmored')]
    parts=[]
    for obj in loaded.objects:
        if obj is None or obj.type!='MESH':continue
        obj['worldgoing_component_slot']='armor'
        obj['worldgoing_armor_category']='cloth'
        bpy.context.collection.objects.link(obj);obj.parent=armature;obj.matrix_parent_inverse=Matrix.Identity(4)
        for modifier in obj.modifiers:
            if modifier.type=='ARMATURE':modifier.object=armature
        obj.hide_viewport=obj.hide_render=False
        parts.append(obj)
    assert all(any(o.name.startswith('Outfit_Medieval_'+style+'_01_') for o in parts) for style in ['Chinese','Japanese','European'])
    bind_cape_action_tracks(armature,parts)
    return parts
