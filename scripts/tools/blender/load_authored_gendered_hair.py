"""Load the four extra authored hairstyles onto the existing character rig."""
from pathlib import Path
import bpy
from mathutils import Matrix


def load_gendered_hair(armature, is_female=False):
    sex = 'female' if is_female else 'male'
    root = Path(__file__).resolve().parents[3]
    source = root/f'assets/characters/human/q35/hair_gendered/candidate_{sex}.blend'
    prefix = 'Hair_Female_' if is_female else 'Hair_Male_'
    prefixes = tuple(prefix+f'{i:02d}' for i in range(5,9))
    with bpy.data.libraries.load(str(source),link=False) as (available,loaded):
        loaded.objects = [n for n in available.objects if n.startswith(prefixes)]
    result = []
    for obj in loaded.objects:
        if obj is None or obj.type != 'MESH': continue
        bpy.context.collection.objects.link(obj)
        obj.parent = armature
        obj.matrix_parent_inverse = Matrix.Identity(4)
        for modifier in obj.modifiers:
            if modifier.type == 'ARMATURE': modifier.object = armature
        obj.hide_viewport = obj.hide_render = False
        result.append(obj)
    assert all(any(o.name == prefix+f'{i:02d}' for o in result) for i in range(5,9)), f'Incomplete hairstyles: {source}'
    return result
