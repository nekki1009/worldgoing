"""Load authored short cape and its morph NLA without replacing existing art."""
from pathlib import Path
import bpy
from load_authored_chinese_cape import bind_cape_action_tracks

ROOT=Path(__file__).resolve().parents[3]
PREFIX='Cape_Japanese_01_'


def load_japanese_cape(armature,is_female=False):
    source=ROOT/f'assets/characters/human/q35/equipment_matrix/japanese_cape_{"female" if is_female else "male"}.blend'
    before=set(bpy.data.objects);actions=set(bpy.data.actions)
    assert not any(o.name.startswith(PREFIX) for o in before)
    with bpy.data.libraries.load(str(source),link=False) as (available,loaded):
        loaded.objects=[name for name in available.objects if name.startswith(PREFIX)]
    parts=list(loaded.objects)
    assert len(parts)==4
    for obj in parts:
        bpy.context.collection.objects.link(obj)
        world=obj.matrix_world.copy();obj.parent=armature
        obj.matrix_parent_inverse=armature.matrix_world.inverted();obj.matrix_world=world
        for mod in obj.modifiers:
            if mod.type=='ARMATURE':mod.object=armature
        obj.hide_viewport=obj.hide_render=False;obj.hide_set(False)
    bpy.context.view_layer.update()
    for obj in set(bpy.data.objects)-before-set(parts):
        data=obj.data if obj.type=='ARMATURE' else None
        bpy.data.objects.remove(obj,do_unlink=True)
        if data is not None and not data.users:bpy.data.armatures.remove(data)
    for action in set(bpy.data.actions)-actions:
        if not action.name.startswith(PREFIX):
            assert action.users==int(action.use_fake_user),action.name
            bpy.data.actions.remove(action)
    bind_cape_action_tracks(armature,parts)
    return parts
