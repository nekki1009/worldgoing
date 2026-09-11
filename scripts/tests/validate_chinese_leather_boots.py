"""New boots only; baseline parts, material images and all morphs preserved."""
import json,sys
from pathlib import Path
import numpy as np
import validate_chinese_leather_helmet as shared
check=shared.original
ROOT=Path(__file__).resolve().parents[2]
check.BASE=ROOT/'.godot-temp/chinese_leather_boots_baseline_20260910'
check.WORK=ROOT/'assets/characters/human/q35/chinese_leather_boots'
check.PREFIXES=('Boots_Chinese_Leather_01_',)
reports=[]
for sex in ['male','female']:
    report=check.check(sex,'--final' in sys.argv,min_parts=32)
    before,bb=check.read_glb(check.BASE/f'standard_anime_{sex}_character_pack.glb')
    after,ab=check.read_glb(Path(report['source']))
    nodes={n['name']:n for n in after['nodes']};materials={m['name']:m for m in after['materials']}
    for m in before['materials']:assert shared.material_value(m,before,bb)==shared.material_value(materials[m['name']],after,ab),m['name']
    for node in before['nodes']:
        if 'mesh' not in node:continue
        old=before['meshes'][node['mesh']];new=after['meshes'][nodes[node['name']]['mesh']]
        assert old.get('extras',{}).get('targetNames',[])==new.get('extras',{}).get('targetNames',[])
        for p,q in zip(old['primitives'],new['primitives']):
            for a,b in zip(p.get('targets',[]),q.get('targets',[])):
                for attr in a:assert np.allclose(check.accessor(before,bb,a[attr]),check.accessor(after,ab,b[attr]),atol=1e-5),(node['name'],attr)
    reports.append(report)
(check.WORK/'validation.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
print('CHINESE_BOOTS_ASSET_PASS')
