"""Scoped append for authored cloth, preserving all original binary data."""
import copy
import json
import struct
import sys
from pathlib import Path
import numpy as np

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'scripts/tests'))
from validate_chinese_cloak_assets import read_glb, accessor


def append_cloth(source, subset, target, clip_times, prefix='Outfit_Medieval_', animation_aliases=None):
    doc,raw=read_glb(source);new,addition=read_glb(subset)
    binary=bytearray(raw);copied={};views={}
    def view(index):
        if index not in views:
            item=copy.deepcopy(new['bufferViews'][index]);start=item.get('byteOffset',0)
            binary.extend(b'\0'*(-len(binary)%4));item['byteOffset']=len(binary)
            binary.extend(addition[start:start+item['byteLength']])
            views[index]=len(doc['bufferViews']);doc['bufferViews'].append(item)
        return views[index]
    def acc(index):
        if index not in copied:
            item=copy.deepcopy(new['accessors'][index]);assert 'sparse' not in item
            item['bufferView']=view(item['bufferView'])
            copied[index]=len(doc['accessors']);doc['accessors'].append(item)
        return copied[index]
    def array(values):
        values=np.asarray(values,dtype='<f4')
        binary.extend(b'\0'*(-len(binary)%4))
        doc['bufferViews'].append({'buffer':0,'byteOffset':len(binary),'byteLength':values.nbytes})
        binary.extend(values.tobytes())
        item={'bufferView':len(doc['bufferViews'])-1,'componentType':5126,'count':values.size,'type':'SCALAR','min':[float(values.min())],'max':[float(values.max())]}
        doc['accessors'].append(item);return len(doc['accessors'])-1
    # Images/materials remain real embedded PBR resources, not procedural nodes.
    offsets={key:len(doc.get(key,[])) for key in ['images','textures','samplers','materials']}
    for key in offsets:doc.setdefault(key,[])
    for item in new.get('images',[]):
        item=copy.deepcopy(item);assert 'uri' not in item
        item['bufferView']=view(item['bufferView']);doc['images'].append(item)
    doc['samplers'].extend(copy.deepcopy(new.get('samplers',[])))
    for item in new.get('textures',[]):
        item=copy.deepcopy(item);item['source']+=offsets['images']
        if 'sampler' in item:item['sampler']+=offsets['samplers']
        doc['textures'].append(item)
    def textures(item):
        if isinstance(item,dict):
            for key,value in item.items():
                if key.endswith('Texture') and isinstance(value,dict):value['index']+=offsets['textures']
                else:textures(value)
        elif isinstance(item,list):
            for value in item:textures(value)
    for mat in new.get('materials',[]):
        mat=copy.deepcopy(mat);textures(mat);doc['materials'].append(mat)
    existing={n.get('name'):i for i,n in enumerate(doc['nodes'])}
    shirt=next(n for n in doc['nodes'] if n.get('name')=='Outfit_Chinese_Lining_01_Shirt')
    skin_index=shirt['skin'];oldskin=doc['skins'][skin_index]
    parent=next(i for i,n in enumerate(doc['nodes']) if existing[shirt['name']] in n.get('children',[]))
    added=[]
    for node in new['nodes']:
        if 'mesh' not in node:continue
        assert node['name'].startswith(prefix) and node['name'] not in existing
        ns=new['skins'][node['skin']]
        assert [doc['nodes'][i]['name'] for i in oldskin['joints']]==[new['nodes'][i]['name'] for i in ns['joints']]
        assert np.allclose(accessor(doc,raw,oldskin['inverseBindMatrices']),accessor(new,addition,ns['inverseBindMatrices']),atol=1e-6)
        mesh=copy.deepcopy(new['meshes'][node['mesh']])
        for p in mesh['primitives']:
            p['attributes']={k:acc(v) for k,v in p['attributes'].items()}
            p['indices']=acc(p['indices']);p['material']+=offsets['materials']
            if 'targets' in p:p['targets']=[{k:acc(v) for k,v in target.items()} for target in p['targets']]
        item=copy.deepcopy(node);item['skin']=skin_index;item['mesh']=len(doc['meshes'])
        doc['meshes'].append(mesh);ni=len(doc['nodes'])
        doc['nodes'][parent]['children'].append(ni);doc['nodes'].append(item)
        added.append(ni)
    # Only append weight channels targeting new skirts; original channels,
    # samplers and their binary ranges stay byte-for-byte unchanged.
    times_with_reset={**clip_times,'T-Pose':[0.0]}
    for clip,times in times_with_reset.items():
        animation=next(a for a in doc['animations'] if a['name']==clip)
        for ni in added:
            mesh=doc['meshes'][doc['nodes'][ni]['mesh']]
            names=mesh.get('extras',{}).get('targetNames',[])
            if not any(n.startswith('Cloth_') for n in names):continue
            if clip!='T-Pose' and not any(n.startswith('Cloth_'+clip+'_') for n in names):continue
            weights=np.zeros((len(times),len(names)),dtype=np.float32)
            if clip!='T-Pose':
                for si in range(len(times)):weights[si,names.index(f'Cloth_{clip}_{si:02d}')]=1
            animation['channels'].append({'sampler':len(animation['samplers']),'target':{'node':ni,'path':'weights'}})
            animation['samplers'].append({'input':array(times),'output':array(weights.ravel()),'interpolation':'LINEAR'})
    for key in ['extensionsUsed','extensionsRequired']:
        for extension in new.get(key,[]):
            if extension not in doc.setdefault(key,[]):doc[key].append(extension)
    # Material variants of the same authored bow reuse its exact existing
    # weight samples. Never replace an old channel or regenerate its timings.
    if animation_aliases:
        aliases={}
        for ni in added:
            node=doc['nodes'][ni]
            source_name=animation_aliases.get(node['name'])
            if source_name is None:continue
            original=existing[source_name]
            before=doc['meshes'][doc['nodes'][original]['mesh']]
            after=doc['meshes'][node['mesh']]
            assert before.get('extras',{}).get('targetNames',[])==after.get('extras',{}).get('targetNames',[]),node['name']
            aliases.setdefault(original,[]).append(ni)
        for animation in doc['animations']:
            for channel in list(animation['channels']):
                for ni in aliases.get(channel['target']['node'],[]):
                    assert channel['target']['path']=='weights','Only authored mesh weight aliases are supported'
                    cloned=copy.deepcopy(channel);cloned['target']['node']=ni
                    animation['channels'].append(cloned)
    binary.extend(b'\0'*(-len(binary)%4));doc['buffers'][0]['byteLength']=len(binary)
    encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4)
    target.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(binary))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+struct.pack('<I4s',len(binary),b'BIN\0')+binary)
