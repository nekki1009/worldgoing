"""Build candidates only; retain old GLB geometry/morphs and append walk keys."""
import argparse
import copy
import json
import struct
import sys
from pathlib import Path
import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
TASK = ROOT/'output/steel_mingguang_walk_20260919'
sys.path.insert(0,str(Path(__file__).parent))
sys.path.insert(0,str(ROOT/'scripts/tests'))
from integrate_equipment_walk_repair import splice, digest
from validate_chinese_cloak_assets import read_glb, accessor
from repair_character_audit import reset_rig
from repair_steel_armor_walk import repair_steel
from repair_mingguang_walk import repair_mingguang, digest_keys
from repair_iron_armor_walk import mesh_signature, action_signatures


def append_walk(source, subset, dest, channels):
    doc, original_binary = read_glb(source)
    original = copy.deepcopy(doc)
    new, nb = read_glb(subset)
    binary = bytearray(original_binary)
    nodes = {n['name']:(i,n) for i,n in enumerate(doc['nodes'])}
    exported = {n['name']:n for n in new['nodes'] if 'mesh' in n}
    assert set(exported) == {c['object'] for c in channels}
    changed_meshes, changed_nodes, old_counts = set(),set(),{}

    def array(values, kind='SCALAR'):
        values = np.asarray(values,dtype='<f4')
        width = {'SCALAR':1,'VEC3':3}[kind]
        values = values.reshape(-1,width)
        binary.extend(b'\0'*(-len(binary)%4))
        view = len(doc['bufferViews'])
        doc['bufferViews'].append({'buffer':0,'byteOffset':len(binary),'byteLength':values.nbytes})
        binary.extend(values.tobytes())
        idx = len(doc['accessors'])
        doc['accessors'].append({'bufferView':view,'componentType':5126,'count':len(values),
            'type':kind,'min':values.min(axis=0).tolist(),'max':values.max(axis=0).tolist()})
        return idx

    for channel in channels:
        name = channel['object']
        ni,node = nodes[name]
        other = exported[name]
        for key in ('translation','rotation','scale','matrix'):
            assert node.get(key) == other.get(key),(name,key)
        mesh = doc['meshes'][node['mesh']]
        nm = new['meshes'][other['mesh']]
        names = mesh['extras']['targetNames']
        count = len(names)
        assert nm['extras']['targetNames'] == names+channel['target_names'],name
        old_counts[ni] = count
        assert len(mesh['primitives']) == len(nm['primitives']),name
        for p,q in zip(mesh['primitives'],nm['primitives']):
            # Preserve all original accessors/indices and all 280 old morphs.
            # A re-export may reorder split vertices, so identify by original
            # position, UV and skin before copying ONLY appended deltas.
            attrs = sorted(p['attributes'])
            assert set(attrs) == set(q['attributes']),(name,'attributes')
            pa = [accessor(doc,original_binary,p['attributes'][a]) for a in attrs]
            qa = [accessor(new,nb,q['attributes'][a]) for a in attrs]
            pv,qv = np.concatenate(pa,axis=1),np.concatenate(qa,axis=1)
            if pv.shape == qv.shape and np.allclose(pv,qv,atol=1e-6,rtol=0):
                mapping = np.arange(len(pv))
            else:
                mapping=[]
                for row in pv:
                    matches=np.flatnonzero(np.all(np.abs(qv-row)<2e-6,axis=1))
                    assert len(matches),(name,'unmatched original vertex',row.tolist())
                    mapping.append(int(matches[0]))
                mapping=np.array(mapping)
            assert len(p['targets']) == count
            for old_target,new_target in zip(p['targets'],q['targets'][:count]):
                assert old_target.keys() == new_target.keys()
                for attr,index in old_target.items():
                    assert np.allclose(accessor(doc,original_binary,index),
                        accessor(new,nb,new_target[attr])[mapping],atol=2e-6,rtol=0),(name,'old morph',attr)
            for target in q['targets'][count:]:
                p['targets'].append({a:array(accessor(new,nb,i)[mapping],'VEC3') for a,i in target.items()})
        mesh['extras']['targetNames'] += channel['target_names']
        mesh['weights'] = mesh.get('weights',[0]*count)+[0]*len(channel['target_names'])
        if 'weights' in node:
            node['weights'] += [0]*len(channel['target_names'])
        changed_meshes.add(node['mesh'])
        changed_nodes.add(ni)

    padded=0
    for anim in doc['animations']:
        for channel in anim['channels']:
            target = channel['target']
            ni = target.get('node')
            if target['path'] != 'weights' or ni not in old_counts:
                continue
            sampler=anim['samplers'][channel['sampler']]
            old_values=accessor(doc,original_binary,sampler['output']).reshape(-1,old_counts[ni])
            added=len(doc['meshes'][doc['nodes'][ni]['mesh']]['weights'])-old_counts[ni]
            # Clone sampler in case an original exporter shared it elsewhere.
            replacement=copy.deepcopy(sampler)
            replacement['output']=array(np.pad(old_values,((0,0),(0,added))))
            channel['sampler']=len(anim['samplers'])
            anim['samplers'].append(replacement)
            padded+=1
    for channel in channels:
        ni=nodes[channel['object']][0]
        anim=next(a for a in doc['animations'] if a['name']==channel['clip'])
        assert not any(c['target']=={'node':ni,'path':'weights'} for c in anim['channels'])
        times=np.asarray(channel['times'])
        duration=max(float(accessor(doc,binary,s['input']).max()) for s in anim['samplers'])
        assert abs(times[0])<1e-6 and abs(times[-1]-duration)<1e-5,(times[-1],duration)
        weights=np.asarray(channel['weights'])
        assert weights.shape==(len(times),len(channel['target_names']))
        values=np.column_stack((np.zeros((len(times),old_counts[ni])),weights))
        sampler={'input':array(times),'output':array(values),'interpolation':'LINEAR'}
        anim['channels'].append({'sampler':len(anim['samplers']),'target':{'node':ni,'path':'weights'}})
        anim['samplers'].append(sampler)
    for key in original:
        if key not in ('meshes','nodes','animations','accessors','bufferViews','buffers'):
            assert doc[key]==original[key],key
    assert all(m==original['meshes'][i] for i,m in enumerate(doc['meshes']) if i not in changed_meshes)
    assert all(n==original['nodes'][i] for i,n in enumerate(doc['nodes']) if i not in changed_nodes)
    assert bytes(binary[:len(original_binary)])==original_binary
    binary.extend(b'\0'*(-len(binary)%4))
    doc['buffers'][0]['byteLength']=len(binary)
    encoded=json.dumps(doc,separators=(',',':')).encode()
    encoded+=b' '*(-len(encoded)%4)
    dest.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(binary))+
        struct.pack('<I4s',len(encoded),b'JSON')+encoded+struct.pack('<I4s',len(binary),b'BIN\0')+binary)
    return {'preserved_binary_bytes':len(original_binary),'old_morphs_and_base_accessors_preserved':True,
        'padded_existing_weight_channels':padded,'appended_walk_channels':len(channels)}


def export_subset(arm,names,path,morph):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [arm,*[bpy.data.objects[n] for n in names]]:
        obj.hide_viewport=False
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active=arm
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
        export_animations=False,export_skins=True,export_morph=morph,export_apply=False,
        export_try_sparse_sk=False)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--sex',choices=['male','female'],required=True)
    parser.add_argument('--revision',required=True)
    parser.add_argument('--mingguang-native',default='')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    assert args.revision.isalnum()
    folder=TASK/'combined'/args.revision/args.sex
    folder.mkdir(parents=True,exist_ok=False)
    stem=f'standard_anime_{args.sex}_character_pack'
    base=TASK/'baseline'/stem
    sources={ext:digest(base.with_suffix(ext)) for ext in ('.blend','.glb','.json')}
    tool_paths=[Path(__file__),Path(repair_steel.__code__.co_filename),Path(repair_mingguang.__code__.co_filename),
        Path(splice.__code__.co_filename),Path(mesh_signature.__code__.co_filename)]
    tool_sources={p.name:digest(p) for p in tool_paths}
    bpy.ops.wm.open_mainfile(filepath=str(base.with_suffix('.blend')))
    bpy.context.preferences.filepaths.save_version=0
    arm=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
    reset_rig(arm)
    before={o.name:mesh_signature(o) for o in bpy.data.objects if o.type=='MESH'}
    actions=action_signatures()
    native_source=None
    if args.mingguang_native:
        assert args.mingguang_native.isalnum()
        native_dir=TASK/'mingguang'/args.mingguang_native/args.sex
        native_source={'blend_sha256':digest(native_dir/'candidate.blend'),
            'report_sha256':digest(native_dir/'repair.json'),'revision':args.mingguang_native}
        mingguang=json.loads((native_dir/'repair.json').read_text(encoding='utf-8'))
        assert mingguang['script_sha256']==digest(Path(repair_mingguang.__code__.co_filename))
        assert mingguang['original_mesh_hashes']==before
        assert mingguang['original_action_hashes']==actions
        old_keys={o.name:digest_keys(o) for o in bpy.data.objects if o.type=='MESH' and o.data.shape_keys}
        assert mingguang['original_key_hashes']==old_keys
        # Copy scalar rows: mathutils row views become invalid after loading
        # the second file. The independent rig probe confirmed exact equality.
        bones=[(b.name,b.parent.name if b.parent else None,[list(row) for row in b.matrix_local]) for b in arm.data.bones]
        transforms={o.name:(o.type,[list(row) for row in o.matrix_world]) for o in bpy.data.objects}
        bpy.ops.wm.open_mainfile(filepath=str(native_dir/'candidate.blend'))
        arm=next(o for o in bpy.context.scene.objects if o.type=='ARMATURE')
        reset_rig(arm)
        assert bones==[(b.name,b.parent.name if b.parent else None,[list(row) for row in b.matrix_local]) for b in arm.data.bones]
        assert transforms=={o.name:(o.type,[list(row) for row in o.matrix_world]) for o in bpy.data.objects}
        assert before=={o.name:mesh_signature(o) for o in bpy.data.objects if o.type=='MESH'}
        for name,value in old_keys.items():
            assert digest_keys(bpy.data.objects[name],281 if name in mingguang['changed'] else None)==value
        for name,proof in mingguang['changed'].items():
            assert digest_keys(bpy.data.objects[name])==proof['after']
        assert native_source['blend_sha256']==digest(native_dir/'candidate.blend')
    steel=repair_steel(arm,args.sex)
    print('STEEL_NATIVE_REPAIR_COMPLETE',args.sex,flush=True)
    if not args.mingguang_native:
        mingguang=repair_mingguang(arm,args.sex)
    print('MINGGUANG_NATIVE_REPAIR_COMPLETE',args.sex,flush=True)
    (folder/'native_repair.json').write_text(json.dumps({'steel':steel,'mingguang':mingguang},indent=2),encoding='utf-8')
    changed=set(steel['changed'])|set(mingguang['changed'])
    assert all(mesh_signature(bpy.data.objects[n])==value for n,value in before.items() if n not in changed)
    after_actions=action_signatures()
    assert all(after_actions[n]==value for n,value in actions.items()),'Original actions modified'
    reset_rig(arm)
    dest=folder/stem
    bpy.ops.wm.save_as_mainfile(filepath=str(dest.with_suffix('.blend')))
    export_subset(arm,steel['changed'],folder/'steel.glb',False)
    steel_proof=splice(base.with_suffix('.glb'),folder/'steel.glb',folder/'steel_full.glb',steel['changed'],steel['topology_changed'],
        {'Worldgoing_Chinese_Gold.001':'Worldgoing_Chinese_Gold'})
    export_subset(arm,mingguang['changed'],folder/'mingguang.glb',True)
    morph_proof=append_walk(folder/'steel_full.glb',folder/'mingguang.glb',dest.with_suffix('.glb'),mingguang['appended_morph_channels'])
    metadata=json.loads(base.with_suffix('.json').read_text(encoding='utf-8'))
    metadata['steel_mingguang_walk_repair_20260919']={'changed_meshes':sorted(changed),'baseline_sha256':sources}
    dest.with_suffix('.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
    assert sources=={ext:digest(base.with_suffix(ext)) for ext in sources}
    assert tool_sources=={p.name:digest(p) for p in tool_paths},'Sources changed during build'
    report={'status':'CANDIDATE_BUILT_NOT_VISUALLY_ACCEPTED','sex':args.sex,'baseline_sha256':sources,
        'candidate_sha256':{ext:digest(dest.with_suffix(ext)) for ext in sources},'tool_sources_sha256':tool_sources,
        'steel':steel,'mingguang':mingguang,'glb_steel':steel_proof,'glb_morph':morph_proof,
        'unrelated_native_meshes_unchanged':len(before)-len(changed),'original_actions_unchanged':len(actions),
        'native_mingguang_source':native_source}
    (folder/'build.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('STEEL_MINGGUANG_CANDIDATE_BUILT',args.sex,flush=True)


if __name__=='__main__':
    main()
