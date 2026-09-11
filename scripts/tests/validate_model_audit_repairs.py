"""Shared body/rig preservation and complete repaired-pack export checks."""
import json,sys
from pathlib import Path
import numpy as np
from validate_chinese_cloak_assets import read_glb,accessor

root=Path(__file__).resolve().parents[2]
reports=[]
for sex in ['male','female','horse']:
    if '--sex' in sys.argv and sex!=sys.argv[sys.argv.index('--sex')+1]:continue
    stem='standard_horse_pack' if sex=='horse' else f'standard_anime_{sex}_character_pack'
    baseline=root/'.godot-temp/model_audit_repairs/baseline'/f'{stem}.glb'
    destination=(root/'assets/mounts/horse' if sex=='horse' else root/'assets/characters/human/q35')/f'{stem}.glb' if '--final' in sys.argv else root/f'assets/characters/human/q35/audit_repair/candidate_{sex}.glb'
    if '--rebuild' in sys.argv:destination=destination.parent/'rebuild'/destination.name
    before,bb=read_glb(baseline);after,ab=read_glb(destination)
    old={n['name']:n for n in before['nodes']};new={n['name']:n for n in after['nodes']}
    protected=[name for name in old if name.startswith('Body_Standard_') or name in ['Face_Standard_01','Face_Standard_03','Horse_Body_01','Horse_Eye_01']]
    if sex != 'horse' and '--with-joint-refinement' in sys.argv:
        from validate_body_joint_refinement import check as check_body_joints
        check_body_joints(sex, destination, '--with-lining-armor-fit' in sys.argv)
        protected = [name for name in protected if not name.startswith('Body_Standard_')]
    for name in protected:
        p=before['meshes'][old[name]['mesh']]['primitives'];q=after['meshes'][new[name]['mesh']]['primitives']
        assert len(p)==len(q),name
        for a,b in zip(p,q):
            for attribute in ['POSITION','NORMAL','TEXCOORD_0','JOINTS_0','WEIGHTS_0']:
                if attribute not in a['attributes']:continue
                x=accessor(before,bb,a['attributes'][attribute]);y=accessor(after,ab,b['attributes'][attribute])
                assert x.shape==y.shape and np.allclose(x,y,atol=1e-6),(sex,name,attribute)
            assert np.array_equal(accessor(before,bb,a['indices']),accessor(after,ab,b['indices'])),(sex,name,'topology')
    for skin in before['skins']:
        joints=[before['nodes'][i]['name'] for i in skin['joints']]
        other=next(s for s in after['skins'] if [after['nodes'][i]['name'] for i in s['joints']]==joints)
        assert np.allclose(accessor(before,bb,skin['inverseBindMatrices']),accessor(after,ab,other['inverseBindMatrices']),atol=1e-6)
        for joint in joints:
            for key,default in [('translation',[0,0,0]),('rotation',[0,0,0,1]),('scale',[1,1,1])]:
                assert np.allclose(old[joint].get(key,default),new[joint].get(key,default),atol=1e-6),(joint,key)
    old_clips={a['name'] for a in before['animations']};new_clips={a['name'] for a in after['animations']}
    assert old_clips==new_clips,(sex,old_clips-new_clips,new_clips-old_clips)
    if sex!='horse':
        for name in ['Face_Standard_02','Face_Standard_04']:
            original=before['meshes'][old[name]['mesh']]['primitives'];repaired=after['meshes'][new[name]['mesh']]['primitives']
            assert len(original)==len(repaired),(sex,name,'material topology')
            for a,b in zip(original,repaired):
                x=accessor(before,bb,a['attributes']['POSITION']);y=accessor(after,ab,b['attributes']['POSITION'])
                assert x.shape==y.shape and np.max(np.linalg.norm(x-y,axis=1))<.06,(sex,name,'expression exceeds local facial displacement')
    checked_channels=0
    def channel_map(doc,animation):
        return {(doc['nodes'][c['target']['node']]['name'],c['target']['path']):animation['samplers'][c['sampler']] for c in animation['channels'] if c['target']['path']!='weights'}
    after_anims={a['name']:a for a in after['animations']}
    for animation in before['animations']:
        clip=animation['name'];channels=channel_map(after,after_anims[clip])
        clip_end=max(float(accessor(before,bb,s['input']).max()) for s in animation['samplers'])
        if clip=='attack_crossbow':continue # Entire aiming stance is intentionally replaced.
        for (node,kind),sampler in channel_map(before,animation).items():
            if clip in ['attack_crossbow','attack_spear'] and node.startswith(('J_Bip_L_','J_Bip_R_')) and any(s in node for s in ['Arm','Hand','Thumb','Index','Middle','Ring','Little']):continue
            if clip.startswith('ride_') and any(node.endswith('_'+b) for b in ['UpperLeg','LowerLeg','Foot']):continue
            if (node,kind) not in channels:
                # glTF may omit channels constant at the bind transform.
                value=new[node].get(kind,{'translation':[0,0,0],'rotation':[0,0,0,1],'scale':[1,1,1]}[kind])
                assert np.allclose(accessor(before,bb,sampler['output']),value,atol=1e-5),(sex,clip,node,kind,'missing nonconstant channel')
                checked_channels+=1
                continue
            other=channels[(node,kind)]
            for key in ['input','output']:
                x=accessor(before,bb,sampler[key]);y=accessor(after,ab,other[key])
                if clip=='attack_hammer' and key=='input':
                    x=clip_end*np.interp(x/clip_end,[0,.12,.25,.34,.42,.65,1],[0,.12,.36,.405,.52,.82,1.2])
                if clip=='attack_hammer' and key=='output' and sampler.get('interpolation')=='CUBICSPLINE':
                    # Retiming changes derivatives, not the keyed poses between them.
                    assert np.isfinite(y).all() and other.get('interpolation')=='CUBICSPLINE'
                    x=x[1::3];y=y[1::3]
                assert x.shape==y.shape and np.allclose(x,y,atol=1e-5),(sex,clip,node,kind,key,x.shape,y.shape)
            checked_channels+=1
    mesh_count=0;triangles=0
    for node in after['nodes']:
        if 'mesh' not in node:continue
        mesh_count+=1
        for primitive in after['meshes'][node['mesh']]['primitives']:
            positions=accessor(after,ab,primitive['attributes']['POSITION'])
            assert len(positions)>0 and np.isfinite(positions).all(),node['name']
            if 'WEIGHTS_0' in primitive['attributes']:
                weights=accessor(after,ab,primitive['attributes']['WEIGHTS_0'])
                assert np.allclose(weights.sum(axis=1),1,atol=1e-5),(node['name'],'weights')
            triangles+=after['accessors'][primitive['indices']]['count']//3
    if sex!='horse':
        assert 'Outfit_Underlayer_01_UnderwearBottom' in new
        assert not any(n.startswith(('Outfit_Underlayer_01','Boots_Leather_01','Weapon_Crossbow_01')) and n.endswith('.001') for n in new)
        assert 'Cape_Travel_01_ShoulderMantle' in new
        assert 'Shield_Heater_01_Handle' in new
        assert 'Weapon_Crossbow_01_Mechanism' in new
        assert any(after['nodes'][c['target']['node']]['name']=='Weapon_Bow_01_String' and c['target']['path']=='weights' for a in after['animations'] if a['name']=='attack_bow' for c in a['channels'])
        assert any(after['nodes'][c['target']['node']]['name']=='Cape_Travel_01_Main' and c['target']['path']=='weights' for a in after['animations'] if a['name']=='run' for c in a['channels'])
        hammer=after_anims['attack_hammer'];axe=after_anims['attack_axe']
        duration=lambda a:max(float(accessor(after,ab,s['input']).max()) for s in a['samplers'])
        assert duration(hammer)>duration(axe)*1.15,('hammer cadence',duration(hammer),duration(axe))
        cape=next(c for c in hammer['channels'] if after['nodes'][c['target']['node']]['name']=='Cape_Travel_01_Main' and c['target']['path']=='weights')
        assert abs(float(accessor(after,ab,hammer['samplers'][cape['sampler']]['input']).max())-duration(hammer))<.05,'hammer cape timing'
    else:
        assert 'Horse_Hooves_01' in new and 'Horse_Nostrils_01' in new
        for side in ['L','R']:
            mesh=after['meshes'][new[f'Mount_Stirrups_01_{side}']['mesh']]
            assert set(mesh['extras']['targetNames'])=={'Side','Forward','Lift'}
    reports.append({'sex':sex,'source':str(destination),'protected_meshes':protected,'preserved_animation_channels':checked_channels,'mesh_count':mesh_count,'triangles':triangles,'animations':len(new_clips)})
suffix=('_rebuild_'+sys.argv[sys.argv.index('--sex')+1]) if '--rebuild' in sys.argv else '_final' if '--final' in sys.argv else ''
path=root/f'assets/characters/human/q35/audit_repair/validation{suffix}.json'
path.write_text(json.dumps(reports,indent=2),encoding='utf-8')
print('MODEL_AUDIT_REPAIRS_ASSET_PASS',json.dumps(reports))
