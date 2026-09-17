"""Strict scoped append validation and guarded publication, retaining old bytes."""
import json
import sys
from pathlib import Path
import numpy as np
import validate_medieval_shoes as publication
from validate_chinese_cloak_assets import read_glb,accessor

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'output/weapon_materials_20260917'
ASSETS=ROOT/'assets/characters/human/q35'
WORK=ASSETS/'weapon_materials'
CATALOG=json.loads((ROOT/'scripts/ui/weapon_materials.gd').read_text(encoding='utf-8').split('const OPTIONS := ',1)[1].split('\n\nconst ATTACKS',1)[0])[:-1]


def check(sex,final=False):
    stem=f'standard_anime_{sex}_character_pack'
    source={ext:ASSETS/f'{stem}.{ext}' if final else WORK/(f'weapon_materials_{sex}.blend' if ext=='blend' else f'candidate_{sex}.{ext}') for ext in ('blend','glb','json')}
    old,ob=read_glb(OUT/'baseline'/f'{stem}.glb');new,nb=read_glb(source['glb'])
    assert nb[:len(ob)]==ob,'Original binary changed'
    for key in ('skins','meshes','materials','textures','images','samplers','accessors','bufferViews'):
        assert new.get(key,[])[:len(old.get(key,[]))]==old.get(key,[]),(sex,key)
    assert len(new['animations'])==len(old['animations'])
    for before,after in zip(old['animations'],new['animations']):
        assert {k:v for k,v in before.items() if k!='channels'}=={k:v for k,v in after.items() if k!='channels'}
        assert after['channels'][:len(before['channels'])]==before['channels'],'Original channels changed'
        aliases=after['channels'][len(before['channels']):]
        assert len(aliases)==(3 if before['name']=='attack_bow' else 0)
        for channel in aliases:
            name=new['nodes'][channel['target']['node']]['name']
            assert name in ['Weapon_Bow_'+kind+'_01_String' for kind in ('Wood','Stone','Steel')]
            source_channel=next(c for c in before['channels'] if old['nodes'][c['target']['node']].get('name')=='Weapon_Bow_01_String')
            assert channel['sampler']==source_channel['sampler'] and channel['target']['path']=='weights'
    for a,b in zip(old['nodes'],new['nodes']):
        assert {k:v for k,v in a.items() if k!='children'}=={k:v for k,v in b.items() if k!='children'},a['name']
        assert b.get('children',[])[:len(a.get('children',[]))]==a.get('children',[])
    added=new['nodes'][len(old['nodes']):];triangles=0
    allowed=[r['prefixes'][0]+'_' for r in CATALOG if r['material']!='iron' or r['base'] in ('pickaxe_01','tool_hammer_01','shovel_01')]
    for node in added:
        assert node['name'].startswith(tuple(allowed)) and 'mesh' in node,node['name']
        assert len([p for p in allowed if node['name'].startswith(p)])==1
        for primitive in new['meshes'][node['mesh']]['primitives']:
            values={k:accessor(new,nb,v) for k,v in primitive['attributes'].items()}
            for key in ('POSITION','NORMAL','WEIGHTS_0'):assert np.isfinite(values[key]).all(),(node['name'],key)
            assert np.allclose(values['WEIGHTS_0'].sum(1),1,atol=2e-5)
            assert values['WEIGHTS_0'].min()>=0
            mat=new['materials'][primitive['material']]
            if mat['name'].startswith(('WeaponMaterial_wood','WeaponMaterial_stone')):
                assert 'TEXCOORD_0' in values and np.ptp(values['TEXCOORD_0'],axis=0).max()>.001
                assert 'baseColorTexture' in mat['pbrMetallicRoughness']
            triangles+=new['accessors'][primitive['indices']]['count']//3
    names=[n.get('name','') for n in new['nodes']]
    for row in CATALOG:
        actual=[n for n in names if n.startswith(row['prefixes'][0]+'_')]
        assert actual,(sex,row['id'])
        assert any('Holstered' in n or 'Sheathed' in n for n in actual),(sex,row['id'],'missing stowed mesh')
    metadata=json.loads(source['json'].read_text(encoding='utf-8'))
    expected=json.loads((OUT/'baseline'/f'{stem}.json').read_text(encoding='utf-8'))
    expected['parts']['weapon']+=sorted(n['name'] for n in added)
    expected['weapon_materials']=metadata['weapon_materials']
    assert metadata==expected,'Unrelated metadata changed'
    return {'sex':sex,'final':final,'options':len(CATALOG),'added_meshes':len(added),'triangles':triangles,'old_meshes_preserved':len(old['meshes']),
            'old_binary_bytes_preserved':len(ob),'old_animation_channels_preserved':sum(len(a['channels']) for a in old['animations']),
            'sha256':{ext:publication.digest(path) for ext,path in source.items()}}


if __name__=='__main__':
    final='--final' in sys.argv;report=[check(sex,final) for sex in ('male','female')]
    (OUT/('formal_contract.json' if final else 'candidate_contract.json')).write_text(json.dumps(report,indent=2),encoding='utf-8')
    # Compare with either the immutable original or the last exact publication
    # from this task; a concurrent asset edit still aborts the transaction.
    if '--publish' in sys.argv:
        assert not final
        import os,shutil,uuid
        published_path=OUT/'published_contract.json'
        published=json.loads(published_path.read_text()) if published_path.exists() else []
        pairs=[]
        for record in report:
            for ext in ('blend','glb','json'):
                sex=record['sex'];name=f'standard_anime_{sex}_character_pack.{ext}'
                candidate=WORK/(f'weapon_materials_{sex}.blend' if ext=='blend' else f'candidate_{sex}.{ext}')
                target=ASSETS/name;baseline=OUT/'baseline'/name
                previous=next((r['sha256'][ext] for r in published if r['sex']==sex),publication.digest(baseline))
                assert publication.digest(target)==previous,'Formal asset changed since last baseline/publication: '+name
                assert publication.digest(candidate)==record['sha256'][ext]
                pairs.append((candidate,target,previous,record['sha256'][ext]))
        incoming=OUT/('publication_'+uuid.uuid4().hex);incoming.mkdir();replaced=[]
        try:
            for candidate,target,previous,digest in pairs:
                shutil.copy2(candidate,incoming/target.name);assert publication.digest(incoming/target.name)==digest
                shutil.copy2(target,incoming/(target.name+'.previous'))
                assert publication.digest(incoming/(target.name+'.previous'))==previous
            for candidate,target,previous,digest in pairs:
                assert publication.digest(target)==previous,'Concurrent formal change'
                os.replace(incoming/target.name,target);replaced.append((target,incoming/(target.name+'.previous')))
                assert publication.digest(target)==digest
        except Exception:
            for target,baseline in replaced:shutil.copy2(baseline,target)
            raise
        published_path.write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('WEAPON_MATERIAL_ASSET_PASS',json.dumps(report),flush=True)
