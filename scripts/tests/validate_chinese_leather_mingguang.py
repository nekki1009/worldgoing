"""Scoped geometry, UV/weight, shared-rig and existing-parts preservation checks."""
import json
from pathlib import Path
import numpy as np
from validate_chinese_cloak_assets import read_glb, accessor

ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'.godot-temp/chinese_leather_mingguang_baseline_20260910'
WORK=ROOT/'assets/characters/human/q35/chinese_leather_mingguang'
PREFIXES=('Armor_Chinese_Leather_01_','Helmet_Mingguang_01_')


def check(sex,final=False,min_parts=11):
    before,bb=read_glb(BASE/f'standard_anime_{sex}_character_pack.glb')
    path=WORK/f'candidate_{sex}.glb' if not final else WORK.parent/f'standard_anime_{sex}_character_pack.glb'
    after,ab=read_glb(path)
    an={n['name']:n for n in after['nodes']}
    failures=[]
    for node in before['nodes']:
        name=node['name'];other=an.get(name)
        if other is None:failures.append((name,'missing'));continue
        for key,default in [('translation',[0,0,0]),('rotation',[0,0,0,1]),('scale',[1,1,1])]:
            if not np.allclose(node.get(key,default),other.get(key,default),atol=1e-6):failures.append((name,key))
        if 'mesh' not in node:continue
        bp=before['meshes'][node['mesh']]['primitives'];ap=after['meshes'][other['mesh']]['primitives']
        if len(bp)!=len(ap):failures.append((name,'primitives'));continue
        for p,q in zip(bp,ap):
            for attr in p['attributes']:
                x=accessor(before,bb,p['attributes'][attr]);y=accessor(after,ab,q['attributes'][attr])
                if x.shape!=y.shape or not np.allclose(x,y,atol=1e-5):failures.append((name,attr))
            if not np.array_equal(accessor(before,bb,p['indices']),accessor(after,ab,q['indices'])):failures.append((name,'indices'))
            if len(p.get('targets',[]))!=len(q.get('targets',[])):failures.append((name,'morph count'))
    old_clips={a['name'] for a in before['animations']};new_clips={a['name'] for a in after['animations']}
    assert old_clips<=new_clips,old_clips-new_clips
    for animation in before['animations']:
        other=next(a for a in after['animations'] if a['name']==animation['name'])
        channels={(after['nodes'][c['target']['node']]['name'],c['target']['path']):c for c in other['channels']}
        for channel in animation['channels']:
            key=(before['nodes'][channel['target']['node']]['name'],channel['target']['path'])
            if key not in channels:failures.append((animation['name'],key,'missing channel'));continue
            bs=animation['samplers'][channel['sampler']];as_=other['samplers'][channels[key]['sampler']]
            for kind in ['input','output']:
                x=accessor(before,bb,bs[kind]);y=accessor(after,ab,as_[kind])
                if x.shape!=y.shape or not np.allclose(x,y,atol=1e-5):failures.append((animation['name'],key,kind))
    for skin in before['skins']:
        joints=[before['nodes'][i]['name'] for i in skin['joints']]
        match=next((s for s in after['skins'] if [after['nodes'][i]['name'] for i in s['joints']]==joints),None)
        assert match is not None
        assert np.allclose(accessor(before,bb,skin['inverseBindMatrices']),accessor(after,ab,match['inverseBindMatrices']),atol=1e-6)
    counts={}
    for prefix in PREFIXES:
        nodes=[n for n in after['nodes'] if n.get('name','').startswith(prefix) and 'mesh' in n]
        assert len(nodes)>=min_parts
        tris=0
        for node in nodes:
            for p in after['meshes'][node['mesh']]['primitives']:
                assert 'TEXCOORD_0' in p['attributes'] and 'WEIGHTS_0' in p['attributes'],node['name']
                assert np.allclose(accessor(after,ab,p['attributes']['WEIGHTS_0']).sum(axis=1),1,atol=1e-5)
                assert np.isfinite(accessor(after,ab,p['attributes']['POSITION'])).all()
                tris+=after['accessors'][p['indices']]['count']//3
        counts[prefix]={'meshes':len(nodes),'triangles':tris}
    plume=an['Helmet_Mingguang_01_WhitePlume_Fittings']
    assert all(len(p.get('targets',[]))==2 for p in after['meshes'][plume['mesh']]['primitives'])
    report={'sex':sex,'source':str(path),'new_parts':counts,'raw_clips':len(new_clips),'unrelated_failures':failures}
    print(json.dumps(report,ensure_ascii=False),flush=True)
    assert not failures,'Existing geometry or transforms changed'
    return report


if __name__=='__main__':
    import sys
    reports=[check(sex,'--final' in sys.argv) for sex in ['male','female']]
    (WORK/'validation.json').write_text(json.dumps(reports,indent=2,ensure_ascii=False),encoding='utf-8')
    print('CHINESE_GEAR_ASSET_CONTRACT_PASS')
