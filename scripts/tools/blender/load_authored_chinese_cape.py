"""Load the editable fitted cloak; production builders never regenerate its art."""
from pathlib import Path
import bpy
from mathutils import Matrix

PREFIX = 'Cape_Chinese_01'
ROOT = Path(__file__).resolve().parents[3]
SOURCE_DIR = ROOT / 'assets/characters/human/q35/chinese_cloak'


def make_chinese_cape(armature, is_female=False, create_rigid_fn=None):
    sex = 'female' if is_female else 'male'
    source = SOURCE_DIR / f'chinese_cloak_{sex}.blend'
    if not source.exists():
        raise FileNotFoundError(f'Author the fitted cloak source before building: {source}')
    with bpy.data.libraries.load(str(source), link=False) as (available, loaded):
        loaded.objects = [n for n in available.objects if n.startswith(PREFIX)]
    parts = []
    for obj in loaded.objects:
        if obj is None or obj.type != 'MESH':
            continue
        bpy.context.collection.objects.link(obj)
        obj.parent = armature
        obj.matrix_parent_inverse = Matrix.Identity(4)
        for modifier in obj.modifiers:
            if modifier.type == 'ARMATURE':
                modifier.object = armature
        obj.hide_viewport = obj.hide_render = False
        parts.append(obj)
    if not parts:
        raise RuntimeError(f'No cloak meshes in {source}')
    return parts


def bind_cape_action_tracks(armature, parts):
    """Merge morph actions with skeletal clips by NLA track name in glTF ACTIONS mode."""
    armature.animation_data_create()
    clips = set()
    for obj in parts:
        keys = obj.data.shape_keys
        if keys and keys.animation_data:
            clips.update(track.name for track in keys.animation_data.nla_tracks)
    for name in sorted(clips):
        action = bpy.data.actions.get(name)
        if action is None:
            raise RuntimeError(f'Cloak clip missing from target rig: {name}')
        existing = next((t for t in armature.animation_data.nla_tracks
                         if any(s.action == action for s in t.strips)), None)
        if existing:
            existing.name = name
        else:
            track = armature.animation_data.nla_tracks.new()
            track.name = name
            track.strips.new(name, int(action.frame_range[0]), action)
            track.mute = True
