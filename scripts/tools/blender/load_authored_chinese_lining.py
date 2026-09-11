"""Append editable lining meshes without rebuilding the garment."""
from pathlib import Path
import bpy
from mathutils import Matrix
PREFIX='Outfit_Chinese_Lining_01_'
ROOT=Path(__file__).resolve().parents[3]


def load_chinese_lining(armature,is_female=False):
    sex='female' if is_female else 'male'
    source=ROOT/f'assets/characters/human/q35/chinese_lining/chinese_lining_{sex}.blend'
    with bpy.data.libraries.load(str(source),link=False) as (available,loaded):
        loaded.objects=[name for name in available.objects if name.startswith(PREFIX)]
    parts=[]
    for obj in loaded.objects:
        if obj is None or obj.type!='MESH':continue
        bpy.context.collection.objects.link(obj);obj.parent=armature;obj.matrix_parent_inverse=Matrix.Identity(4)
        for mod in obj.modifiers:
            if mod.type=='ARMATURE':mod.object=armature
        obj.hide_viewport=obj.hide_render=False
        parts.append(obj)
    assert len(parts)>=8,'Incomplete lining source'
    return parts
