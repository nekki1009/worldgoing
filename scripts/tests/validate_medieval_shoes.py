"""Footwear append contract and guarded publication; no old binary may change."""
import hashlib
import json
import os
import shutil
import sys
import uuid
from pathlib import Path
import numpy as np
from validate_chinese_cloak_assets import read_glb, accessor

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/medieval_shoes_20260916'
ASSETS=ROOT/'assets/characters/human/q35'
WORK=ASSETS/'medieval_shoes'


def digest(path):
    with path.open('rb') as stream:return hashlib.file_digest(stream,'sha256').hexdigest()


def check(sex, final=False):
    stem=f'standard_anime_{sex}_character_pack'
    before,bb=read_glb(OUT/'baseline'/f'{stem}.glb')
    sources={ext:ASSETS/f'{stem}.{ext}' if final else WORK/(f'medieval_shoes_{sex}.blend' if ext=='blend' else f'candidate_{sex}.{ext}') for ext in ('blend','glb','json')}
    after,ab=read_glb(sources['glb'])
    assert ab[:len(bb)]==bb,'Old model binary changed'
    for key in ('skins','meshes','materials','textures','images','samplers','accessors','bufferViews'):
        assert after.get(key,[])[:len(before.get(key,[]))]==before.get(key,[]),(sex,key)
    assert after['animations']==before['animations'],'Original clips or cloth correctives changed'
    for old,new in zip(before['nodes'],after['nodes']):
        assert {k:v for k,v in old.items() if k!='children'}=={k:v for k,v in new.items() if k!='children'},old['name']
        assert new.get('children',[])[:len(old.get('children',[]))]==old.get('children',[])
    added=after['nodes'][len(before['nodes']):]
    triangles=0
    for node in added:
        assert node['name'].startswith('Boots_Medieval_') and 'mesh' in node
        for primitive in after['meshes'][node['mesh']]['primitives']:
            values={k:accessor(after,ab,v) for k,v in primitive['attributes'].items()}
            for key in ('POSITION','NORMAL','TEXCOORD_0','WEIGHTS_0'):assert np.isfinite(values[key]).all(),(node['name'],key)
            assert np.allclose(values['WEIGHTS_0'].sum(1),1,atol=2e-5)
            assert values['WEIGHTS_0'].min()>=0
            assert np.ptp(values['TEXCOORD_0'],axis=0).max()>.001
            mat=after['materials'][primitive['material']]
            assert mat['name'].startswith('MedievalShoes_')
            if mat['name'] in ('MedievalShoes_Cloth','MedievalShoes_Tabi','MedievalShoes_Leather'):
                assert 'baseColorTexture' in mat['pbrMetallicRoughness'],'Missing packed material pattern'
            triangles+=after['accessors'][primitive['indices']]['count']//3
    for style in ('Chinese','Japanese','European'):
        for side in ('L','R'):
            for part in ('Upper','Sole','Binding'):
                assert any(node['name']==f'Boots_Medieval_{style}_01_{part}_{side}' for node in added)
    metadata=json.loads(sources['json'].read_text(encoding='utf-8'))
    oldmeta=json.loads((OUT/'baseline'/f'{stem}.json').read_text(encoding='utf-8'))
    expected=json.loads(json.dumps(oldmeta))
    expected['parts']['boots']+=sorted(n['name'] for n in added)
    expected['medieval_shoes']=metadata['medieval_shoes']
    assert metadata==expected,'Non-shoe metadata modified'
    return {'sex':sex,'final':final,'added_meshes':len(added),'triangles':triangles,
            'old_meshes_preserved':len(before['meshes']),'old_animation_channels_preserved':sum(len(a['channels']) for a in before['animations']),
            'old_binary_bytes_preserved':len(bb),'sha256':{ext:digest(path) for ext,path in sources.items()}}


def publish(report):
    pairs=[]
    for record in report:
        sex=record['sex']
        for ext in ('blend','glb','json'):
            name=f'standard_anime_{sex}_character_pack.{ext}'
            source=WORK/(f'medieval_shoes_{sex}.blend' if ext=='blend' else f'candidate_{sex}.{ext}')
            target=ASSETS/name
            baseline=OUT/'baseline'/name
            assert digest(target)==digest(baseline),'Formal asset changed since baseline: '+name
            assert digest(source)==record['sha256'][ext],'Candidate changed since validation'
            pairs.append((source,target,baseline,record['sha256'][ext]))
    incoming=OUT/('publication_'+uuid.uuid4().hex)
    incoming.mkdir()
    for source,target,baseline,sha in pairs:
        shutil.copy2(source,incoming/target.name)
        assert digest(incoming/target.name)==sha
    replaced=[]
    try:
        for source,target,baseline,sha in pairs:
            assert digest(target)==digest(baseline),'Concurrent formal change'
            os.replace(incoming/target.name,target)
            replaced.append((target,baseline))
            assert digest(target)==sha
    except Exception:
        for target,baseline in replaced:
            shutil.copy2(baseline,incoming/target.name)
            os.replace(incoming/target.name,target)
        raise
    incoming.rmdir()  # Only this verified, empty intermediate directory.


if __name__=='__main__':
    final='--final' in sys.argv
    report=[check(sex,final) for sex in ('male','female')]
    (OUT/('formal_contract.json' if final else 'candidate_contract.json')).write_text(json.dumps(report,indent=2),encoding='utf-8')
    if '--publish' in sys.argv:
        assert not final
        publish(report)
    print('MEDIEVAL_SHOES_ASSET_PASS',json.dumps(report),flush=True)
