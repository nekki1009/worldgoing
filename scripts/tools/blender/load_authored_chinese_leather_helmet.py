"""Load the new editable helmet onto the existing character rig."""
from pathlib import Path
import bpy
from mathutils import Matrix

PREFIX='Helmet_Chinese_Leather_01_'
ROOT=Path(__file__).resolve().parents[3]


def load_chinese_leather_helmet(armature,is_female=False):
    sex='female' if is_female else 'male'
    source=ROOT/f'assets/characters/human/q35/chinese_leather_helmet/leather_helmet_{sex}.blend'
    with bpy.data.libraries.load(str(source),link=False) as (available,loaded):
        loaded.objects=[name for name in available.objects if name.startswith(PREFIX)]
    parts=[]
    for obj in loaded.objects:
        if obj is None or obj.type!='MESH':continue
        bpy.context.collection.objects.link(obj)
        obj.parent=armature;obj.matrix_parent_inverse=Matrix.Identity(4)
        for modifier in obj.modifiers:
            if modifier.type=='ARMATURE':modifier.object=armature
        obj.hide_viewport=obj.hide_render=False
        obj['worldgoing_visual_id']='helmet_chinese_leather_01'
        parts.append(obj)
    assert len(parts)>=27,'Incomplete leather helmet source'
    return parts
