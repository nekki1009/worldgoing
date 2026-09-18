"""Load only the four authored neutral faces; retain the one original rig."""
from pathlib import Path
import bpy


def load_neutral_faces(armature, is_female=False):
    root = Path(__file__).resolve().parents[3]
    sex = 'female' if is_female else 'male'
    source = root/f'assets/characters/human/q35/neutral_faces/neutral_faces_{sex}.blend'
    before = set(bpy.data.objects)
    actions = set(bpy.data.actions)
    names = [f'Face_Standard_{i:02d}' for i in range(5, 9)]
    with bpy.data.libraries.load(str(source), link=False) as (available, loaded):
        assert all(name in available.objects for name in names)
        loaded.objects = names
    for obj in loaded.objects:
        assert obj is not None and obj.type == 'MESH'
        bpy.context.collection.objects.link(obj)
        obj.parent = armature
        for modifier in obj.modifiers:
            if modifier.type == 'ARMATURE': modifier.object = armature
        obj.hide_viewport = obj.hide_render = False
    for obj in set(bpy.data.objects)-before-set(loaded.objects):
        data = obj.data if obj.type == 'ARMATURE' else None
        bpy.data.objects.remove(obj, do_unlink=True)
        if data is not None and data.users == 0: bpy.data.armatures.remove(data)
    for action in set(bpy.data.actions)-actions:
        assert action.users == int(action.use_fake_user)
        bpy.data.actions.remove(action)
    bpy.context.view_layer.update()
    return list(loaded.objects)
