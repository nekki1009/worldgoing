"""Build a full candidate by replacing only measured armor/boot mesh payloads.

Never publishes. The immutable baseline and original animation/skin binary stay
intact; native Godot review must precede copying these outputs into the pack.
"""
import argparse
import copy
import hashlib
import json
import struct
import sys
from pathlib import Path

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
TASK = ROOT / 'output/equipment_walk_fix_20260919'
sys.path.insert(0, str(Path(__file__).parent))
sys.path.insert(0, str(ROOT / 'scripts/tests'))
from repair_character_audit import reset_rig
from repair_cultural_boot_walk import repair_boots
from repair_iron_armor_walk import repair_armor
from validate_chinese_cloak_assets import read_glb, accessor


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def splice(source, subset, dest, changed, topology_changed, material_aliases=None):
    assert set(topology_changed) <= {'Armor_Iron_01_Tasset_Front','Armor_Iron_01_Tasset_Front_Gold',
                                   'Armor_Chinese_Steel_01_Tasset_Front','Armor_Chinese_Steel_01_Tasset_Front_Gold'}
    doc, original_binary = read_glb(source)
    original = copy.deepcopy(doc)
    new, new_binary = read_glb(subset)
    binary = bytearray(original_binary)
    imported = {}

    def append_accessor(index):
        if index in imported:
            return imported[index]
        acc = copy.deepcopy(new['accessors'][index])
        assert 'sparse' not in acc
        view = copy.deepcopy(new['bufferViews'][acc['bufferView']])
        assert view.get('buffer', 0) == 0
        binary.extend(b'\0' * (-len(binary) % 4))
        start = view.get('byteOffset', 0)
        view['byteOffset'] = len(binary)
        binary.extend(new_binary[start:start+view['byteLength']])
        acc['bufferView'] = len(doc['bufferViews'])
        doc['bufferViews'].append(view)
        imported[index] = len(doc['accessors'])
        doc['accessors'].append(acc)
        return imported[index]

    old_nodes = {n['name']: n for n in doc['nodes']}
    seen, replaced_indices = set(), set()
    for node in new['nodes']:
        if 'mesh' not in node:
            continue
        name = node['name']
        assert name in changed and name not in seen, name
        seen.add(name)
        old = old_nodes[name]
        for key in ('translation', 'rotation', 'scale', 'matrix'):
            assert old.get(key) == node.get(key), (name, key)
        old_skin, new_skin = doc['skins'][old['skin']], new['skins'][node['skin']]
        assert [doc['nodes'][i]['name'] for i in old_skin['joints']] == [new['nodes'][i]['name'] for i in new_skin['joints']]
        assert np.allclose(accessor(doc, binary, old_skin['inverseBindMatrices']), accessor(new, new_binary, new_skin['inverseBindMatrices']), atol=1e-6)
        old_mesh, new_mesh = doc['meshes'][old['mesh']], new['meshes'][node['mesh']]
        replaced_indices.add(old['mesh'])
        assert len(old_mesh['primitives']) == len(new_mesh['primitives']), name
        for p, q in zip(old_mesh['primitives'], new_mesh['primitives']):
            assert not p.get('targets') and not q.get('targets'), name
            old_material = doc['materials'][p['material']]
            new_material = new['materials'][q['material']]
            if old_material['name'] != new_material['name']:
                assert (material_aliases or {}).get(new_material['name']) == old_material['name'], name
                assert {k:v for k,v in old_material.items() if k != 'name'} == {k:v for k,v in new_material.items() if k != 'name'}, (name,'material alias content')
            # The exporter can split/reorder vertices when a deformed face has
            # a different normal or quad diagonal. Both repair functions prove
            # original native face topology, per-loop UVs and materials intact.
            # Copy a complete indexed primitive; mixing old UV/index order with
            # newly exported positions would corrupt an otherwise valid mesh.
            old_triangles = len(accessor(doc,binary,p['indices']))//3
            new_triangles = len(accessor(new,new_binary,q['indices']))//3
            if name in topology_changed:
                cut = topology_changed[name]
                assert cut['no_cross_half_faces'] and cut['no_shared_midline_vertices'] and cut['uv_interpolation_verified']
                assert old_triangles == cut['before']['triangles'] and new_triangles == cut['after']['triangles'], (name,'declared cut geometry')
            else:
                assert old_triangles == new_triangles, (name,'triangle count')
            required = {'POSITION','NORMAL','JOINTS_0','WEIGHTS_0'} | {a for a in p['attributes'] if a.startswith('TEXCOORD_')}
            assert required <= q['attributes'].keys(), (name,'attribute loss')
            count = new['accessors'][q['attributes']['POSITION']]['count']
            assert all(new['accessors'][i]['count'] == count for i in q['attributes'].values()), name
            assert int(accessor(new,new_binary,q['indices']).max()) < count, name
            p['attributes'] = {attr:append_accessor(index) for attr,index in q['attributes'].items()}
            p['indices'] = append_accessor(q['indices'])
    assert seen == set(changed), (seen, changed)
    for key in original:
        if key not in ('meshes', 'accessors', 'bufferViews', 'buffers'):
            assert doc[key] == original[key], key
    assert all(m == original['meshes'][i] for i,m in enumerate(doc['meshes']) if i not in replaced_indices)
    assert bytes(binary[:len(original_binary)]) == original_binary
    binary.extend(b'\0' * (-len(binary) % 4))
    doc['buffers'][0]['byteLength'] = len(binary)
    encoded = json.dumps(doc, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    dest.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(binary)) + struct.pack('<I4s',len(encoded),b'JSON') + encoded + struct.pack('<I4s',len(binary),b'BIN\0') + binary)
    return {'replaced_meshes': sorted(seen), 'original_binary_bytes_preserved': len(original_binary),
            'unchanged_meshes': len(doc['meshes'])-len(replaced_indices),
            'original_nodes_skins_materials_images_textures_animations_unchanged': True}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sex', choices=['male','female'], required=True)
    parser.add_argument('--revision', required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    assert args.revision.isalnum()
    folder = TASK / 'combined' / args.revision / args.sex
    folder.mkdir(parents=True, exist_ok=False)
    stem = f'standard_anime_{args.sex}_character_pack'
    base = TASK / 'baseline' / stem
    sources = {ext: digest(base.with_suffix(ext)) for ext in ('.blend','.glb','.json')}
    tool_paths = [Path(__file__),Path(repair_boots.__code__.co_filename),Path(repair_armor.__code__.co_filename)]
    tool_sources = {p.name:digest(p) for p in tool_paths}
    bpy.ops.wm.open_mainfile(filepath=str(base.with_suffix('.blend')))
    bpy.context.preferences.filepaths.save_version = 0
    arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    reset_rig(arm)
    boots = repair_boots(arm, args.sex)
    armor = repair_armor(arm, args.sex)
    changed = sorted(set(boots['changed']) | set(armor['changed']))
    reset_rig(arm)
    dest = folder / stem
    bpy.ops.wm.save_as_mainfile(filepath=str(dest.with_suffix('.blend')))
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [arm, *[bpy.data.objects[n] for n in changed]]:
        obj.hide_viewport = False
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    subset = folder / 'changed_meshes.glb'
    bpy.ops.export_scene.gltf(filepath=str(subset),export_format='GLB',use_selection=True,
        export_animations=False,export_skins=True,export_morph=False,export_apply=False)
    (folder/'native_repair.json').write_text(json.dumps({'boots':boots,'armor':armor},indent=2),encoding='utf-8')
    glb_report = splice(base.with_suffix('.glb'),subset,dest.with_suffix('.glb'),changed,armor.get('topology_changed',{}))
    metadata = json.loads(base.with_suffix('.json').read_text(encoding='utf-8'))
    metadata['equipment_walk_repair_20260919'] = {'changed_meshes':changed,
        'source_baseline_sha256':sources, 'builder':'scripts/tools/blender/integrate_equipment_walk_repair.py'}
    dest.with_suffix('.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
    assert sources == {ext:digest(base.with_suffix(ext)) for ext in sources}
    assert tool_sources == {p.name:digest(p) for p in tool_paths}, 'Builder source changed during run'
    report = {'status':'CANDIDATE_BUILT_NOT_VISUALLY_ACCEPTED','sex':args.sex,
        'baseline_sha256':sources,'candidate_sha256':{ext:digest(dest.with_suffix(ext)) for ext in sources},
        'boots':boots,'armor':armor,'glb':glb_report,'tool_sources_sha256':tool_sources}
    (folder/'build.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('EQUIPMENT_WALK_CANDIDATE_BUILT',args.sex,len(changed),flush=True)


if __name__ == '__main__':
    main()
