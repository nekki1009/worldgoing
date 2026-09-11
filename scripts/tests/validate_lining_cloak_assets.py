"""Only new lining and existing cloak run morph geometry may differ."""
import json,sys
from pathlib import Path
import numpy as np
import validate_chinese_leather_helmet as helmet
original=helmet.original
ROOT=Path(__file__).resolve().parents[2]
original.BASE=ROOT/'.godot-temp/lining_cloak_baseline_20260910'
original.WORK=ROOT/'assets/characters/human/q35/chinese_lining'
original.PREFIXES=('Outfit_Chinese_Lining_01_',)
reports=[]
for sex in ['male','female']:
    report=original.check(sex,'--final' in sys.argv,min_parts=10)
    before,bb=original.read_glb(original.BASE/f'standard_anime_{sex}_character_pack.glb')
    after,ab=original.read_glb(Path(report['source']))
    new={n['name']:n for n in after['nodes']}
    lining={name for name in new if name.startswith(original.PREFIXES[0])}
    required={'Shirt','Cuff_L','Cuff_R','BackCollar','Hem','UnderwearBottom',*[f'CrossLapel_{i}' for i in range(4)]}
    assert {original.PREFIXES[0]+name for name in required}<=lining
    assert len(lining)==(13 if sex=='male' else 10),lining
    shirt=after['meshes'][new[original.PREFIXES[0]+'Shirt']['mesh']]
    assert shirt['extras']['targetNames']==['UnderArmor']
    changed=set()
    for node in before['nodes']:
        if 'mesh' not in node:continue
        old_mesh=before['meshes'][node['mesh']];new_mesh=after['meshes'][new[node['name']]['mesh']]
        labels=old_mesh.get('extras',{}).get('targetNames',[])
        assert labels==new_mesh.get('extras',{}).get('targetNames',[]),node['name']
        for p,q in zip(old_mesh['primitives'],new_mesh['primitives']):
            for i,(ot,nt) in enumerate(zip(p.get('targets',[]),q.get('targets',[]))):
                for attr in ot:
                    x=original.accessor(before,bb,ot[attr]);y=original.accessor(after,ab,nt[attr])
                    if not np.allclose(x,y,atol=1e-5):
                        assert node['name']=='Cape_Chinese_01_Main' and labels[i].startswith('run_'),(node['name'],labels[i],attr)
                        changed.add(labels[i])
    assert len(changed)==13,changed
    new_mats={m['name']:m for m in after['materials']}
    for m in before['materials']:
        assert helmet.material_value(m,before,bb)==helmet.material_value(new_mats[m['name']],after,ab),m['name']
    report['changed_cape_targets']=sorted(changed);report['old_materials_preserved']=len(before['materials'])
    reports.append(report)
(original.WORK/'validation.json').write_text(json.dumps(reports,indent=2,ensure_ascii=False),encoding='utf-8')
print('LINING_CLOAK_ASSET_PASS')
