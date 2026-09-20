"""Exact preservation, matrix geometry/skin/UV and new-animation admission."""
import json
import sys
from pathlib import Path
import numpy as np
from validate_chinese_cloak_assets import read_glb,accessor
import validate_cloth_hats as publication

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/equipment_matrix_20260918'
WORK=ROOT/'assets/characters/human/q35/equipment_matrix'
ASSETS=WORK.parent
sys.path.insert(0,str(ROOT/'scripts/tools/blender'))
from append_mounted_animations import CLIPS


def duration(doc,binary,animation):
    return max(float(accessor(doc,binary,s['input']).max()) for s in animation['samplers'])


def check(sex,final):
    stem=f'standard_anime_{sex}_character_pack'
    paths={ext:ASSETS/f'{stem}.{ext}' if final else WORK/(f'equipment_matrix_{sex}.blend' if ext=='blend' else f'candidate_{sex}.{ext}') for ext in ('blend','glb','json')}
    old,ob=read_glb(OUT/'baseline'/f'{stem}.glb');new,nb=read_glb(paths['glb'])
    assert nb[:len(ob)]==ob, 'Existing native BIN changed'
    for key in ('skins','meshes','materials','textures','images','samplers','accessors','bufferViews'):
        assert new.get(key,[])[:len(old.get(key,[]))]==old.get(key,[]),(sex,key)
    for before,after in zip(old['nodes'],new['nodes']):
        assert {k:v for k,v in before.items() if k!='children'}=={k:v for k,v in after.items() if k!='children'}
        assert after.get('children',[])[:len(before.get('children',[]))]==before.get('children',[])
    for before,after in zip(old['animations'],new['animations']):
        assert after['name']==before['name']
        for key in ('samplers','channels'):assert after[key][:len(before[key])]==before[key]
        for channel in after['channels'][len(before['channels']):]:
            assert new['nodes'][channel['target']['node']]['name'].startswith('Cape_Japanese_01_') and channel['target']['path']=='weights'
        assert abs(duration(old,ob,before)-duration(new,nb,after))<1e-5, before['name']
    assert {a['name'] for a in new['animations'][len(old['animations']):]}==set(CLIPS)
    added=new['nodes'][len(old['nodes']):];groups={};triangles=0
    for node in added:
        assert 'mesh' in node and node['name'].startswith(('Armor_','Helmet_','Boots_','Shield_','Cape_Japanese_01_'))
        group=node['name'].split('_01')[0]+'_01';groups[group]=groups.get(group,0)+1
        mesh=new['meshes'][node['mesh']]
        for p in mesh['primitives']:
            v={k:accessor(new,nb,a) for k,a in p['attributes'].items()}
            for key in ('POSITION','NORMAL','TEXCOORD_0','WEIGHTS_0'):assert np.isfinite(v[key]).all(),node['name']
            assert np.allclose(v['WEIGHTS_0'].sum(1),1,atol=1e-5),node['name']
            assert v['JOINTS_0'].max()<len(new['skins'][node['skin']]['joints'])
            assert np.ptp(v['TEXCOORD_0'],axis=0).max()>.01,node['name']
            triangles+=new['accessors'][p['indices']]['count']//3
            for target in p.get('targets',[]):
                for index in target.values(): assert np.isfinite(accessor(new,nb,index)).all()
    assert len(groups)==27,(sex,groups)
    for animation in new['animations']:
        for channel in animation['channels']:
            if channel['target']['path']!='weights':continue
            node=new['nodes'][channel['target']['node']];mesh=new['meshes'][node['mesh']]
            sampler=animation['samplers'][channel['sampler']]
            count=new['accessors'][sampler['output']]['count']
            factor=3 if sampler.get('interpolation')=='CUBICSPLINE' else 1
            assert count==new['accessors'][sampler['input']]['count']*len(mesh['primitives'][0]['targets'])*factor
    meta=json.loads(paths['json'].read_text(encoding='utf-8'))
    oldmeta=json.loads((OUT/'baseline'/f'{stem}.json').read_text(encoding='utf-8'))
    for slot,names in oldmeta['parts'].items():assert meta['parts'][slot][:len(names)]==names
    assert meta['animations']==oldmeta['animations']+list(CLIPS)
    assert {n['name'] for n in added}=={n for slot,names in meta['parts'].items() for n in names if n not in oldmeta['parts'][slot]}
    return {'sex':sex,'final':final,'groups':groups,'new_meshes':len(added),'triangles':triangles,
        'old_binary_bytes_preserved':len(ob),'old_meshes_preserved':len(old['meshes']),'old_animations_preserved':len(old['animations']),
        'sha256':{ext:publication.digest(path) for ext,path in paths.items()}}


if __name__=='__main__':
    final='--final' in sys.argv
    report=[check(sex,final) for sex in ('male','female')]
    (OUT/('formal_contract.json' if final else 'candidate_contract.json')).write_text(json.dumps(report,indent=2))
    if '--publish' in sys.argv:
        assert not final
        publication.OUT=OUT;publication.WORK=WORK
        publication.publish(report,blend_prefix='equipment_matrix')
    print('EQUIPMENT_MATRIX_ASSET_PASS',json.dumps(report),flush=True)
