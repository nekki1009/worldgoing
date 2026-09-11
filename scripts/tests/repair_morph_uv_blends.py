"""Add the same UV-only fix to formal editable sources; export a test subset."""
import hashlib
import json
import shutil
import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT/'.godot-temp/morph_uv_repair/baseline'
sys.path.insert(0, str(ROOT/'scripts/tools/blender'))
from ensure_morph_uv import ensure_blender_morph_uv

sex = sys.argv[-1]
path = ROOT/('assets/mounts/horse/standard_horse_pack.blend' if sex == 'horse' else
             f'assets/characters/human/q35/standard_anime_{sex}_character_pack.blend')
backup = BASE/path.relative_to(ROOT)
assert not backup.exists(), ('Backup already exists; inspect before retry', backup)
backup.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(path, backup)
bpy.ops.wm.open_mainfile(filepath=str(path))
bpy.context.preferences.filepaths.save_version = 0
objects = [o for o in bpy.data.objects if o.type == 'MESH']


def geometry_digest():
    digest = hashlib.sha256()
    for obj in sorted(objects, key=lambda o: o.name):
        digest.update(obj.name.encode())
        for vertex in obj.data.vertices:
            digest.update(bytes(str((vertex.co[:], vertex.normal[:], [(g.group, g.weight) for g in vertex.groups])), 'ascii'))
        for polygon in obj.data.polygons:
            digest.update(bytes(str((polygon.vertices[:], polygon.material_index)), 'ascii'))
        if obj.data.shape_keys:
            for key in obj.data.shape_keys.key_blocks:
                digest.update(key.name.encode())
                for point in key.data:
                    digest.update(bytes(str(point.co[:]), 'ascii'))
    return digest.hexdigest()


before = geometry_digest()
changed = ensure_blender_morph_uv(objects)
assert len(changed) == (2 if sex == 'horse' else 3), changed
assert not ensure_blender_morph_uv(objects), 'UV repair must be idempotent'
assert geometry_digest() == before, 'Geometry, normals, skinning or morphs changed'
bpy.ops.wm.save_as_mainfile(filepath=str(path))
bpy.ops.object.select_all(action='DESELECT')
armature = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
for obj in [armature, *[o for o in objects if o.name in changed]]:
    obj.hide_viewport = False
    obj.hide_set(False)
    obj.select_set(True)
bpy.context.view_layer.objects.active = armature
target = ROOT/f'.godot-temp/morph_uv_repair/{sex}_uv_subset.glb'
bpy.ops.export_scene.gltf(filepath=str(target), export_format='GLB', use_selection=True,
                          export_animations=False, export_apply=False, export_skins=True,
                          export_morph=True, export_try_sparse_sk=False)
print('MORPH_UV_BLEND_PASS', sex, json.dumps(changed), before, flush=True)
