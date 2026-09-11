"""Refine current backed-up .blend and replace only body geometry in its GLB."""
import copy
import json
import struct
import sys
from pathlib import Path
import bpy
from mathutils.bvhtree import BVHTree

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / 'scripts/tools/blender'))
sys.path.insert(0, str(Path(__file__).parent))
from refine_body_joints import refine_body_joints
from ensure_morph_uv import ensure_blender_morph_uv, patch_glb
from validate_chinese_cloak_assets import read_glb, accessor

sex = sys.argv[-1]
base = root / f'.godot-temp/joint_refinement/baseline/standard_anime_{sex}_character_pack'
dest = root / f'assets/characters/human/q35/joint_refinement/candidate_{sex}'
dest.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(base.with_suffix('.blend')))
arm = bpy.data.objects['Armature']
bodies = [o for o in bpy.data.objects if o.name.startswith('Body_Standard_')]
surfaces = {o.name: BVHTree.FromPolygons([v.co.copy() for v in o.data.vertices], [list(p.vertices) for p in o.data.polygons]) for o in bodies}
report = refine_body_joints(arm, bodies)
assert report, 'No bodies refined'
for obj, row in zip(bodies, report):
    error = max(surfaces[obj.name].find_nearest(v.co)[3] for v in obj.data.vertices)
    assert error < 1e-6, (obj.name, 'rest surface changed', error)
    row['max_rest_surface_error_m'] = error
assert not refine_body_joints(arm, bodies), 'Repeated calls must not subdivide again'
ensure_blender_morph_uv([o for o in bpy.data.objects if o.type == 'MESH'])
bpy.ops.wm.save_as_mainfile(filepath=str(dest.with_suffix('.blend')))
bpy.ops.object.select_all(action='DESELECT')
for obj in [arm, *bodies]:
    obj.hide_viewport = False
    obj.hide_render = False
    obj.hide_set(False)
    obj.select_set(True)
bpy.context.view_layer.objects.active = arm
body_glb = root / f'.godot-temp/joint_refinement/{sex}_body.glb'
bpy.ops.export_scene.gltf(filepath=str(body_glb), export_format='GLB', use_selection=True, export_apply=False, export_animations=False, export_skins=True, export_morph=False)
doc, binary = read_glb(base.with_suffix('.glb'))
new, new_binary = read_glb(body_glb)
binary = bytearray(binary)

def append_accessor(index):
    acc = copy.deepcopy(new['accessors'][index])
    assert 'sparse' not in acc
    view = copy.deepcopy(new['bufferViews'][acc['bufferView']])
    binary.extend(b'\0'*(-len(binary)%4))
    start = view.get('byteOffset', 0)
    view['byteOffset'] = len(binary)
    binary.extend(new_binary[start:start+view['byteLength']])
    acc['bufferView'] = len(doc['bufferViews'])
    doc['bufferViews'].append(view)
    doc['accessors'].append(acc)
    return len(doc['accessors'])-1

old_nodes = {n['name']: n for n in doc['nodes']}
for node in new['nodes']:
    if 'mesh' not in node:
        continue
    old_node = old_nodes[node['name']]
    old_skin, new_skin = doc['skins'][old_node['skin']], new['skins'][node['skin']]
    assert [doc['nodes'][i]['name'] for i in old_skin['joints']] == [new['nodes'][i]['name'] for i in new_skin['joints']], 'Skin order must match'
    assert (abs(accessor(doc, binary, old_skin['inverseBindMatrices'])-accessor(new, new_binary, new_skin['inverseBindMatrices'])) < 1e-6).all()
    old_mesh, new_mesh = doc['meshes'][old_node['mesh']], new['meshes'][node['mesh']]
    assert len(old_mesh['primitives']) == len(new_mesh['primitives'])
    for p, q in zip(old_mesh['primitives'], new_mesh['primitives']):
        assert doc['materials'][p['material']]['name'] == new['materials'][q['material']]['name']
        p['attributes'] = {k: append_accessor(v) for k, v in q['attributes'].items()}
        p['indices'] = append_accessor(q['indices'])
binary.extend(b'\0'*(-len(binary)%4))
doc['buffers'][0]['byteLength'] = len(binary)
encoded = json.dumps(doc, separators=(',', ':')).encode()
encoded += b' '*(-len(encoded)%4)
dest.with_suffix('.glb').write_bytes(struct.pack('<4sII', b'glTF', 2, 28+len(encoded)+len(binary))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+struct.pack('<I4s',len(binary),b'BIN\0')+binary)
patch_glb(dest.with_suffix('.glb'))
dest.with_suffix('.json').write_bytes(base.with_suffix('.json').read_bytes())
(root / f'.godot-temp/joint_refinement/{sex}_build.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print('BODY_JOINT_CANDIDATE_PASS', sex, report)
