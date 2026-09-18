"""Validate additive cap assets and publish only against their exact baseline."""
import hashlib
import json
import os
import shutil
import sys
import uuid
from pathlib import Path
import numpy as np
from validate_chinese_cloak_assets import read_glb,accessor

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/cloth_hats_20260918'
ASSETS=ROOT/'assets/characters/human/q35'
WORK=ASSETS/'cloth_hats'


def digest(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def check(sex,final=False):
    stem=f'standard_anime_{sex}_character_pack'
    paths={ext:ASSETS/f'{stem}.{ext}' if final else WORK/(f'cloth_hats_{sex}.blend' if ext=='blend' else f'candidate_{sex}.{ext}') for ext in ('blend','glb','json')}
    old,ob=read_glb(OUT/'baseline'/f'{stem}.glb');new,nb=read_glb(paths['glb'])
    assert nb[:len(ob)]==ob,'Existing binary must be byte-identical'
    for key in ('skins','meshes','materials','textures','images','samplers','accessors','bufferViews'):
        assert new.get(key,[])[:len(old.get(key,[]))]==old.get(key,[]),(sex,key)
    assert old['animations']==new['animations'],'Do not replace any skeletal or morph animation'
    for before,after in zip(old['nodes'],new['nodes']):
        assert {k:v for k,v in before.items() if k!='children'}=={k:v for k,v in after.items() if k!='children'}
        assert after.get('children',[])[:len(before.get('children',[]))]==before.get('children',[])
    added=new['nodes'][len(old['nodes']):];triangles=0
    for node in added:
        assert node['name'].startswith('Helmet_Cloth_') and 'mesh' in node
        skin=new['skins'][node['skin']]
        head=next(i for i,j in enumerate(skin['joints']) if new['nodes'][j]['name']=='J_Bip_C_Head')
        for p in new['meshes'][node['mesh']]['primitives']:
            values={k:accessor(new,nb,v) for k,v in p['attributes'].items()}
            for key in ('POSITION','NORMAL','TEXCOORD_0','WEIGHTS_0'):assert np.isfinite(values[key]).all()
            weights=values['WEIGHTS_0'];joints=values['JOINTS_0']
            assert np.allclose(weights.sum(1),1,atol=1e-6)
            assert np.all(joints[weights>0]==head),'Cap not anchored exclusively to original head bone'
            assert np.ptp(values['TEXCOORD_0'],axis=0).max()>.01
            mat=new['materials'][p['material']];pbr=mat['pbrMetallicRoughness']
            assert mat['name'].startswith('ClothHats_') and pbr.get('metallicFactor',1)==0
            assert pbr.get('roughnessFactor',1)>=.85
            if mat['name'] in ('ClothHats_Fabric','ClothHats_Band'):assert 'baseColorTexture' in pbr
            triangles+=new['accessors'][p['indices']]['count']//3
    assert len(added)==37,len(added)
    for style in ('Chinese','Japanese','Western'):
        assert any(n['name']==f'Helmet_Cloth_{style}_01_Crown' for n in added)
    meta=json.loads(paths['json'].read_text(encoding='utf-8'))
    expected=json.loads((OUT/'baseline'/f'{stem}.json').read_text(encoding='utf-8'))
    expected['parts']['helmet']+=sorted(n['name'] for n in added)
    expected['cloth_hats']=meta['cloth_hats']
    assert meta==expected
    return {'sex':sex,'final':final,'added_meshes':len(added),'triangles':triangles,'old_binary_bytes_preserved':len(ob),'old_meshes_preserved':len(old['meshes']),'old_animations_preserved':len(old['animations']),'sha256':{ext:digest(path) for ext,path in paths.items()}}


def publish(report,blend_prefix='cloth_hats'):
    incoming=OUT/('publication_'+uuid.uuid4().hex);incoming.mkdir()
    pairs=[];replaced=[]
    try:
        for row in report:
            for ext in ('blend','glb','json'):
                sex=row['sex'];name=f'standard_anime_{sex}_character_pack.{ext}'
                source=WORK/(f'{blend_prefix}_{sex}.blend' if ext=='blend' else f'candidate_{sex}.{ext}')
                target=ASSETS/name;baseline=OUT/'baseline'/name
                assert digest(target)==digest(baseline),'Concurrent formal asset change: '+name
                assert digest(source)==row['sha256'][ext]
                shutil.copy2(source,incoming/name)
                assert digest(incoming/name)==row['sha256'][ext]
                pairs.append((incoming/name,target,baseline))
        for source,target,baseline in pairs:
            assert digest(target)==digest(baseline),'Concurrent publication'
            os.replace(source,target);replaced.append((target,baseline))
    except Exception:
        for target,baseline in replaced:shutil.copy2(baseline,target)
        raise
    incoming.rmdir() # Only the verified empty intermediate, never the baseline.


if __name__=='__main__':
    final='--final' in sys.argv
    report=[check(sex,final) for sex in ('male','female')]
    (OUT/('formal_contract.json' if final else 'candidate_contract.json')).write_text(json.dumps(report,indent=2))
    if '--publish' in sys.argv:
        assert not final
        publish(report)
    print('CLOTH_HATS_ASSET_PASS',json.dumps(report),flush=True)
