"""Append the editable leather armor and helmet to the existing shared rig."""
from pathlib import Path
import bpy
from mathutils import Matrix

ROOT = Path(__file__).resolve().parents[3]
PREFIXES = ('Armor_Chinese_Leather_01_', 'Helmet_Mingguang_01_')


def load_chinese_gear(armature, is_female=False):
    sex = 'female' if is_female else 'male'
    source = ROOT / f'assets/characters/human/q35/chinese_leather_mingguang/chinese_gear_{sex}.blend'
    with bpy.data.libraries.load(str(source), link=False) as (available, loaded):
        loaded.objects = [name for name in available.objects if name.startswith(PREFIXES)]
    armor, helmet = [], []
    for obj in loaded.objects:
        if obj is None or obj.type != 'MESH': continue
        bpy.context.collection.objects.link(obj)
        obj.parent = armature
        obj.matrix_parent_inverse = Matrix.Identity(4)
        for modifier in obj.modifiers:
            if modifier.type == 'ARMATURE': modifier.object = armature
        obj.hide_viewport = obj.hide_render = False
        (armor if obj.name.startswith(PREFIXES[0]) else helmet).append(obj)
    if not armor or not helmet:
        raise RuntimeError(f'Incomplete authored Chinese equipment: {source}')
    return armor, helmet
