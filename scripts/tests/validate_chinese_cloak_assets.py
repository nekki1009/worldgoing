"""Compare the scoped cloak export against its immutable character-pack baseline."""
import json
import struct
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / '.godot-temp/chinese_cape_remake_baseline'
WORK = ROOT / 'assets/characters/human/q35/chinese_cloak'
PREFIX = 'Cape_Chinese_01'


def read_glb(path):
    raw = path.read_bytes()
    size = struct.unpack_from('<I', raw, 12)[0]
    return json.loads(raw[20:20+size]), raw[28+size:]


def accessor(doc, binary, index):
    a = doc['accessors'][index]
    dtype = {5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}[a['componentType']]
    width = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
    item = np.dtype(dtype).itemsize
    result = np.zeros((a['count'],width),dtype=dtype)
    if 'bufferView' in a:
        v = doc['bufferViews'][a['bufferView']]
        result = np.ndarray((a['count'],width),dtype=dtype,buffer=binary,
                            offset=v.get('byteOffset',0)+a.get('byteOffset',0),
                            strides=(v.get('byteStride',width*item),item))
    if 'sparse' in a:
        result = result.copy()
        sparse=a['sparse'];indices=sparse['indices'];values=sparse['values']
        iv=doc['bufferViews'][indices['bufferView']];vv=doc['bufferViews'][values['bufferView']]
        ids=np.frombuffer(binary,dtype={5121:'u1',5123:'<u2',5125:'<u4'}[indices['componentType']],count=sparse['count'],offset=iv.get('byteOffset',0)+indices.get('byteOffset',0))
        result[ids]=np.frombuffer(binary,dtype=dtype,count=sparse['count']*width,offset=vv.get('byteOffset',0)+values.get('byteOffset',0)).reshape(-1,width)
    return result


def check(sex):
    before, bb = read_glb(BASE / f'standard_anime_{sex}_character_pack.glb')
    after, ab = read_glb(WORK / f'candidate_{sex}.glb')
    bn = {n['name']:n for n in before['nodes']}
    an = {n['name']:n for n in after['nodes']}
    failures = []
    for name, node in bn.items():
        if name.startswith(PREFIX): continue
        if name not in an:
            failures.append((name,'missing node')); continue
        other = an[name]
        for key, default in [('translation',[0,0,0]),('rotation',[0,0,0,1]),('scale',[1,1,1])]:
            if not np.allclose(node.get(key,default),other.get(key,default),atol=1e-6):
                failures.append((name,key))
        if 'mesh' not in node: continue
        bp = before['meshes'][node['mesh']]['primitives']
        ap = after['meshes'][other['mesh']]['primitives']
        if len(bp) != len(ap): failures.append((name,'primitive count')); continue
        for p,q in zip(bp,ap):
            for attribute in set(p['attributes']) | set(q['attributes']):
                if attribute not in p['attributes'] or attribute not in q['attributes']:
                    failures.append((name,attribute+' missing')); continue
                x = accessor(before,bb,p['attributes'][attribute])
                y = accessor(after,ab,q['attributes'][attribute])
                if x.shape != y.shape or not np.allclose(x,y,atol=1e-5):
                    failures.append((name,attribute,tuple(x.shape),tuple(y.shape)))
            x,y = accessor(before,bb,p['indices']),accessor(after,ab,q['indices'])
            if x.shape != y.shape or not np.array_equal(x,y): failures.append((name,'indices'))
    old_clips = {a['name'] for a in before['animations']}
    new_clips = {a['name'] for a in after['animations']}
    if not old_clips <= new_clips: failures.append(('animations','missing',sorted(old_clips-new_clips)))
    for skin in before['skins']:
        joints = [before['nodes'][i]['name'] for i in skin['joints']]
        match = next((s for s in after['skins'] if [after['nodes'][i]['name'] for i in s['joints']] == joints),None)
        if match is None: failures.append(('rig','joint order or membership'))
        elif not np.allclose(accessor(before,bb,skin['inverseBindMatrices']),accessor(after,ab,match['inverseBindMatrices']),atol=1e-6):
            failures.append(('rig','inverse bind matrices'))
    cape = [n for n in after['nodes'] if n.get('name','').startswith(PREFIX) and 'mesh' in n]
    assert len(cape) == 7, len(cape)
    triangles = 0
    for n in cape:
        for p in after['meshes'][n['mesh']]['primitives']:
            assert 'TEXCOORD_0' in p['attributes'], n['name']
            weights = accessor(after,ab,p['attributes']['WEIGHTS_0'])
            assert np.allclose(weights.sum(axis=1),1,atol=1e-5), n['name']
            triangles += after['accessors'][p['indices']]['count']//3
            if n['name'].endswith(('_Main','_Mantle')): assert len(p['targets']) == 336
    print(json.dumps({'sex':sex,'cape_meshes':len(cape),'cape_triangles':triangles,
                      'animations':len(new_clips),'non_cape_failures':failures},ensure_ascii=False),flush=True)
    assert not failures, f'{sex}: unrelated asset changes'


if __name__ == '__main__':
    import sys
    for sex in sys.argv[1:] or ['male','female']: check(sex)
    print('CHINESE_CLOAK_ASSET_CONTRACT_PASS')
