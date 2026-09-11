"""Scoped bracer fitting: preserve the current pack's other meshes and clips."""
import copy
import json
import struct
import sys
from pathlib import Path
import bpy

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts/tools/blender'))
sys.path.insert(0,str(Path(__file__).parent))
from fit_armor_bracers import fit_armor_bracers, PREFIXES
from ensure_morph_uv import ensure_blender_morph_uv, patch_glb
from validate_chinese_cloak_assets import read_glb, accessor

sex = sys.argv[-1]
base = ROOT/f'.godot-temp/lining_armor_overlap/baseline/standard_anime_{sex}_character_pack'
dest = ROOT/f'assets/characters/human/q35/lining_armor_fit/candidate_{sex}'
dest.parent.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(base.with_suffix('.blend')))
bpy.context.preferences.filepaths.save_version = 0
arm = bpy.data.objects['Armature']
objects = [o for o in bpy.data.objects if o.type == 'MESH']
report = fit_armor_bracers(arm,objects)
assert len(report) == 12, report
assert not fit_armor_bracers(arm,objects), 'Fitting must be idempotent'
ensure_blender_morph_uv(objects)
bpy.ops.wm.save_as_mainfile(filepath=str(dest.with_suffix('.blend')))
bpy.ops.object.select_all(action='DESELECT')
for obj in [arm,*[o for o in objects if o.name.startswith(PREFIXES) or o.name == 'Outfit_Chinese_Lining_01_Shirt']]:
    obj.hide_viewport = False
    obj.hide_set(False)
    obj.select_set(True)
bpy.context.view_layer.objects.active = arm
subset = ROOT/f'.godot-temp/lining_armor_overlap/{sex}_bracers.glb'
bpy.ops.export_scene.gltf(filepath=str(subset),export_format='GLB',use_selection=True,export_apply=False,export_animations=False,export_skins=True,export_morph=True,export_try_sparse_sk=False)
doc,binary = read_glb(base.with_suffix('.glb'))
new,new_binary = read_glb(subset)
binary = bytearray(binary)


def append_accessor(index):
    acc = copy.deepcopy(new['accessors'][index])
    assert 'sparse' not in acc
    view = copy.deepcopy(new['bufferViews'][acc['bufferView']])
    binary.extend(b'\0'*(-len(binary)%4))
    start = view.get('byteOffset',0)
    view['byteOffset'] = len(binary)
    binary.extend(new_binary[start:start+view['byteLength']])
    acc['bufferView'] = len(doc['bufferViews'])
    doc['bufferViews'].append(view)
    doc['accessors'].append(acc)
    return len(doc['accessors'])-1


old_nodes = {n['name']:n for n in doc['nodes']}
for node in new['nodes']:
    if 'mesh' not in node:
        continue
    shirt = node['name'] == 'Outfit_Chinese_Lining_01_Shirt'
    assert node['name'].startswith(PREFIXES) or shirt
    old = old_nodes[node['name']]
    old_skin,new_skin = doc['skins'][old['skin']],new['skins'][node['skin']]
    assert [doc['nodes'][i]['name'] for i in old_skin['joints']] == [new['nodes'][i]['name'] for i in new_skin['joints']]
    assert (abs(accessor(doc,binary,old_skin['inverseBindMatrices'])-accessor(new,new_binary,new_skin['inverseBindMatrices'])) < 1e-6).all()
    old_mesh,new_mesh = doc['meshes'][old['mesh']],new['meshes'][node['mesh']]
    assert len(old_mesh['primitives']) == len(new_mesh['primitives'])
    for p,q in zip(old_mesh['primitives'],new_mesh['primitives']):
        assert doc['materials'][p['material']]['name'] == new['materials'][q['material']]['name']
        if shirt:
            # Preserve all original attributes and the leather morph. Only
            # append the native-exported hard-armor target with the same order.
            import numpy as np
            for attr in ('POSITION','TEXCOORD_0','JOINTS_0','WEIGHTS_0'):
                assert np.allclose(accessor(doc,binary,p['attributes'][attr]),accessor(new,new_binary,q['attributes'][attr]),atol=1e-6), attr
            key_index = new_mesh['extras']['targetNames'].index('UnderHardArmor')
            p['targets'].append({k:append_accessor(v) for k,v in q['targets'][key_index].items()})
            continue
        if '_Straps_' not in node['name']:
            assert len(accessor(doc,binary,p['indices'])) == len(accessor(new,new_binary,q['indices']))
        p['attributes'] = {k:append_accessor(v) for k,v in q['attributes'].items()}
        p['indices'] = append_accessor(q['indices'])
    if shirt:
        old_mesh['extras']['targetNames'].append('UnderHardArmor')
        old_mesh['weights'].append(0.0)
binary.extend(b'\0'*(-len(binary)%4))
doc['buffers'][0]['byteLength'] = len(binary)
encoded = json.dumps(doc,separators=(',',':')).encode()
encoded += b' '*(-len(encoded)%4)
dest.with_suffix('.glb').write_bytes(struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(binary))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+struct.pack('<I4s',len(binary),b'BIN\0')+binary)
patch_glb(dest.with_suffix('.glb'))
dest.with_suffix('.json').write_bytes(base.with_suffix('.json').read_bytes())
(ROOT/f'.godot-temp/lining_armor_overlap/{sex}_build.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('LINING_ARMOR_CANDIDATE_PASS',sex,report)
