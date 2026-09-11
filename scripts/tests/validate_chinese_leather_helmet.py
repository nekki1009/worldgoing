"""Reuse the full old-part/rig/animation comparison and add material preservation."""
import hashlib
import json
import sys
from pathlib import Path
import validate_chinese_leather_mingguang as original

ROOT=Path(__file__).resolve().parents[2]
original.BASE=ROOT/'.godot-temp/chinese_leather_helmet_baseline_20260910'
original.WORK=ROOT/'assets/characters/human/q35/chinese_leather_helmet'
original.PREFIXES=('Helmet_Chinese_Leather_01_',)


def material_value(value,doc,binary,key=''):
    if isinstance(value,list):return [material_value(v,doc,binary) for v in value]
    if not isinstance(value,dict):return value
    result={k:material_value(v,doc,binary,k) for k,v in value.items()}
    if key.endswith('Texture') and 'index' in value:
        texture=doc['textures'][value['index']]
        image=doc['images'][texture['source']]
        view=doc['bufferViews'][image['bufferView']];offset=view.get('byteOffset',0)
        result['index']=hashlib.sha256(binary[offset:offset+view['byteLength']]).hexdigest()
    return result


if __name__=='__main__':
    final='--final' in sys.argv
    reports=[]
    for sex in ['male','female']:
        report=original.check(sex,final)
        before,bb=original.read_glb(original.BASE/f'standard_anime_{sex}_character_pack.glb')
        after,ab=original.read_glb(Path(report['source']))
        new_materials={m['name']:m for m in after['materials']}
        for material in before['materials']:
            assert material_value(material,before,bb)==material_value(new_materials[material['name']],after,ab),material['name']
        report['old_materials_preserved']=len(before['materials'])
        reports.append(report)
    (original.WORK/'validation.json').write_text(json.dumps(reports,indent=2,ensure_ascii=False),encoding='utf-8')
    print('CHINESE_LEATHER_HELMET_ASSET_PASS')
