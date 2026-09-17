"""Validate appended cloth and exact preservation of unrelated character data."""
import json
import hashlib
import sys
from pathlib import Path
import numpy as np
from validate_chinese_cloak_assets import read_glb,accessor

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/medieval_cloth_20260916'


def check(sex,final=False):
    stem=f'standard_anime_{sex}_character_pack'
    before,bb=read_glb(OUT/'baseline'/f'{stem}.glb')
    path=ROOT/f'assets/characters/human/q35/{stem}.glb' if final else ROOT/f'assets/characters/human/q35/medieval_cloth/candidate_{sex}.glb'
    after,ab=read_glb(path)
    assert ab[:len(bb)]==bb,'Old geometry/skin/material/animation binary changed'
    for key in ['skins','meshes','materials','textures','images','samplers','accessors','bufferViews']:
        assert after.get(key,[])[:len(before.get(key,[]))]==before.get(key,[]),(sex,key)
    for old,new in zip(before['nodes'],after['nodes']):
        assert {k:v for k,v in old.items() if k!='children'}=={k:v for k,v in new.items() if k!='children'},old['name']
        assert new.get('children',[])[:len(old.get('children',[]))]==old.get('children',[])
    for old,new in zip(before['animations'],after['animations']):
        assert new['name']==old['name']
        assert new['channels'][:len(old['channels'])]==old['channels']
        assert new['samplers'][:len(old['samplers'])]==old['samplers']
        for channel in new['channels'][len(old['channels']):]:
            assert channel['target']['path']=='weights'
            assert after['nodes'][channel['target']['node']]['name'].startswith('Outfit_Medieval_')
    additions=after['nodes'][len(before['nodes']):]
    assert all(n['name'].startswith(('Outfit_Medieval_','Boots_Medieval_')) for n in additions)
    # Footwear has its own exact append contract against the completed cloth.
    added=[n for n in additions if n['name'].startswith('Outfit_Medieval_')]
    triangles=0;skirts=0;surfaces=0;armor_variants=0
    for node in added:
        assert node['name'].startswith('Outfit_Medieval_') and 'mesh' in node
        mesh=after['meshes'][node['mesh']]
        keys=mesh.get('extras',{}).get('targetNames',[])
        if node['name'].endswith('Skirt'):
            assert len(keys)>=300,node['name'];skirts+=1
        if node['name'].endswith('SkirtArmored'):
            assert len(keys)>=300,node['name'];armor_variants+=1
        for p in mesh['primitives']:
            values={k:accessor(after,ab,v) for k,v in p['attributes'].items()}
            for key in ['POSITION','NORMAL','TEXCOORD_0','WEIGHTS_0']:
                assert np.isfinite(values[key]).all(),(node['name'],key)
            assert np.allclose(values['WEIGHTS_0'].sum(1),1,atol=2e-5)
            assert values['WEIGHTS_0'].min()>=0
            assert np.ptp(values['TEXCOORD_0'],axis=0).max()>.001
            material=after['materials'][p['material']]
            assert material['name'].startswith('MedievalCloth_')
            if material['name']=='MedievalCloth_Linen':assert 'baseColorTexture' in material['pbrMetallicRoughness']
            assert material['pbrMetallicRoughness'].get('metallicFactor',1)==0
            for morph in p.get('targets',[]):
                assert all(np.isfinite(accessor(after,ab,index)).all() for index in morph.values())
            triangles+=after['accessors'][p['indices']]['count']//3;surfaces+=1
    assert skirts==3
    assert armor_variants==0,'Canceled armored-skirt prototypes must not be published'
    for style in ['Chinese','Japanese','European']:
        names={n['name'] for n in added if n['name'].startswith('Outfit_Medieval_'+style+'_01_')}
        assert any(name.endswith('Shirt') for name in names) and any(name.endswith('Skirt') for name in names)
        if sex=='male':assert any(name.endswith(('Trousers','Hakama')) for name in names)
    digests={}
    sources={'glb':path,'blend':ROOT/f'assets/characters/human/q35/{stem}.blend' if final else ROOT/f'assets/characters/human/q35/medieval_cloth/medieval_cloth_{sex}.blend','json':ROOT/f'assets/characters/human/q35/{stem}.json' if final else ROOT/f'assets/characters/human/q35/medieval_cloth/candidate_{sex}.json'}
    for key,source in sources.items():
        with source.open('rb') as stream:digests[key]=hashlib.file_digest(stream,'md5').hexdigest()
    metadata=json.loads(sources['json'].read_text(encoding='utf-8'))
    assert metadata['medieval_cloth']['slot']=='armor' and metadata['medieval_cloth']['category']=='cloth'
    assert not any(name.startswith('Outfit_Medieval_') for name in metadata['parts']['outfit'])
    assert {node['name'] for node in added}=={name for name in metadata['parts']['armor'] if name.startswith('Outfit_Medieval_')}
    return {'sex':sex,'final':final,'source_md5':digests,'added_meshes':len(added),'surfaces':surfaces,'triangles':triangles,'skirts':skirts,'armor_variants':armor_variants,'old_meshes_unchanged':len(before['meshes']),'old_animation_channels_unchanged':sum(len(a['channels']) for a in before['animations']),'old_binary_bytes_unchanged':len(bb)}


if __name__=='__main__':
    final='--final' in sys.argv
    report=[check(sex,final) for sex in ['male','female']]
    (OUT/('formal_contract.json' if final else 'candidate_contract.json')).write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('MEDIEVAL_CLOTH_ASSET_PASS',json.dumps(report))
