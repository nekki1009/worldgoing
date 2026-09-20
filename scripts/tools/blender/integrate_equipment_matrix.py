"""Additive integration: preserve old native data, append meshes and two clips."""
import argparse
import hashlib
import json
import shutil
import sys
import uuid
from pathlib import Path
import bpy

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(Path(__file__).parent))
from load_authored_cultural_armor import load_cultural_armor
from load_authored_cultural_shields import load_cultural_shields
from load_authored_mounted_heavy import load_mounted_actions
from load_authored_japanese_cape import load_japanese_cape
from append_mounted_animations import append_mounted
from medieval_cloth_export import append_cloth

OUT=ROOT/'output/equipment_matrix_20260918'
WORK=ROOT/'assets/characters/human/q35/equipment_matrix'


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--sex',choices=['male','female'],required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);sex=args.sex;female=sex=='female'
    with (WORK/f'mounted_actions_{sex}.blend').open('rb') as stream:
        mounted_hash=hashlib.file_digest(stream,'sha256').hexdigest()
    assert (WORK/f'cape_{sex}_mounted_source.sha256').read_text()==mounted_hash, 'Rebake cape after mounted-action edits'
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.open_mainfile(filepath=str(OUT/f'baseline/standard_anime_{sex}_character_pack.blend'))
    arm=bpy.data.objects['Armature'];before={o.name for o in bpy.data.objects}
    actions=load_mounted_actions(arm,female)
    armor,helmet,boots=load_cultural_armor(arm,female)
    shields=load_cultural_shields(arm,female)
    capes=load_japanese_cape(arm,female)
    bpy.context.view_layer.update()
    assert before<={o.name for o in bpy.data.objects}
    new_parts={'armor':armor,'helmet':helmet,'boots':boots,'shield':shields,'cape':capes}
    # The formal editable pack keeps native old geometry, old NLA and old actions.
    temp=ROOT/f'.godot-temp/equipment_matrix_{sex}_{uuid.uuid4().hex}.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(temp),compress=True)
    blend=WORK/f'equipment_matrix_{sex}.blend';shutil.copy2(temp,blend)
    assert temp.stat().st_size==blend.stat().st_size;temp.unlink()
    current=OUT/f'baseline/standard_anime_{sex}_character_pack.glb'
    for kind,prefix in [('armor',('Armor_','Helmet_','Boots_')),('shields','Shield_')]:
        target=WORK/f'merge_{kind}_{sex}.glb'
        append_cloth(current,WORK/f'subset_{kind}_{sex}.glb',target,{},prefix)
        current=target
    target=WORK/f'merge_actions_{sex}.glb'
    append_mounted(current,WORK/f'mounted_animations_{sex}.glb',target)
    times=json.loads((WORK/f'cape_{sex}_clip_times.json').read_text())
    append_cloth(target,WORK/f'subset_cape_{sex}.glb',WORK/f'candidate_{sex}.glb',times,'Cape_Japanese_01_')
    metadata=json.loads((OUT/f'baseline/standard_anime_{sex}_character_pack.json').read_text(encoding='utf-8'))
    for slot,parts in new_parts.items():metadata['parts'][slot]+=sorted(o.name for o in parts)
    metadata['animations']+=list(actions)
    metadata['equipment_matrix']={'revision':1,'cultures':['chinese','japanese','western'],
        'armor_materials':['cloth','leather','iron','steel'],'special_armor':['armor_mingguang_01'],
        'shield_materials':['wood','stone','iron','steel'],'cape_material':'cloth','cape_officer_only':True,
        'mounted_actions':list(actions),'native_gender':sex,'reference':'output/equipment_matrix_20260918/reference',
        'source':'assets/characters/human/q35/equipment_matrix'}
    (WORK/f'candidate_{sex}.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('EQUIPMENT_MATRIX_INTEGRATION_PASS',sex,{slot:len(parts) for slot,parts in new_parts.items()},flush=True)


if __name__=='__main__':main()
