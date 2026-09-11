"""Repair the saved pack into a candidate; never overwrite the input baseline."""
import json,sys
from pathlib import Path
import bpy

root=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(Path(__file__).parent))
from repair_character_audit import apply_repairs

sex=sys.argv[-1]
if sex=='female':import build_standard_anime_female_character_pack as api
elif sex=='horse':import build_standard_horse_pack as api
else:import build_standard_anime_male_character_pack as api
baseline=root/'.godot-temp/model_audit_repairs/baseline'
stem='standard_horse_pack' if sex=='horse' else f'standard_anime_{sex}_character_pack'
finishing='--finish-surfaces' in sys.argv
faces_only='--repair-faces' in sys.argv
source=root/f'assets/characters/human/q35/audit_repair/candidate_{sex}' if finishing or faces_only else baseline/stem
bpy.ops.wm.open_mainfile(filepath=str(source.with_suffix('.blend')))
meta=json.loads(source.with_suffix('.json').read_text(encoding='utf-8'))
if sex=='horse':objects=[o for o in bpy.data.objects if o.type=='MESH']
else:
    names={name for values in meta['parts'].values() for name in values}
    objects=[bpy.data.objects[name] for name in sorted(names)]
arm=next(o for o in bpy.data.objects if o.type=='ARMATURE')
track_mutes={tr.name:tr.mute for tr in arm.animation_data.nla_tracks}
if faces_only:
    from repair_character_audit import repair_face_variants
    with bpy.data.libraries.load(str((baseline/stem).with_suffix('.blend')),link=False) as (available,loaded):
        loaded.objects=['Face_Standard_02','Face_Standard_04']
    for original,name in zip(loaded.objects,['Face_Standard_02','Face_Standard_04']):
        target=bpy.data.objects[name]
        for old,new in zip(original.data.vertices,target.data.vertices):new.co=old.co
        bpy.data.objects.remove(original,do_unlink=True)
    repair_face_variants(objects)
elif finishing:
    from repair_character_audit import finish_surfaces
    finish_surfaces(objects,api)
elif sex=='horse':
    from repair_horse_audit import apply_repairs as repair_horse
    repair_horse(arm,objects,api)
else:apply_repairs(arm,objects,api,sex=='female')
from ensure_morph_uv import ensure_blender_morph_uv
ensure_blender_morph_uv(objects)
for tr in arm.animation_data.nla_tracks:tr.mute=track_mutes.get(tr.name,False)
arm.animation_data.action=None
dest=root/'assets/characters/human/q35/audit_repair'
dest.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='DESELECT')
for obj in [arm,*objects]:
    obj.hide_viewport=False;obj.hide_render=False;obj.hide_set(False);obj.select_set(True)
bpy.context.view_layer.objects.active=arm
bpy.ops.wm.save_as_mainfile(filepath=str(dest/f'candidate_{sex}.blend'))
bpy.ops.export_scene.gltf(filepath=str(dest/f'candidate_{sex}.glb'),export_format='GLB',use_selection=True,export_apply=False,export_animations=True,export_animation_mode='ACTIONS',export_frame_range=False,export_force_sampling=False,export_optimize_disable_viewport=True,export_skins=True,export_morph=True)
from author_chinese_cape import preserve_legacy_clips
preserve_legacy_clips(sex,dest/f'candidate_{sex}.glb',baseline/(stem+'.glb'),replace_existing=sex=='horse',prune_duplicates=True)
if sex=='horse':
    meta['parts']=[{'slot':o.get('worldgoing_component_slot','mount_detail'),'object':o.name,'visual_id':o.get('worldgoing_visual_id','')} for o in objects]
else:
    for slot in meta['parts']:
        meta['parts'][slot]=[o.name for o in objects if o.get('worldgoing_component_slot')==slot or o.name in meta['parts'][slot]]
(dest/f'candidate_{sex}.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2),encoding='utf-8')
print('MODEL_AUDIT_REPAIRS_CANDIDATE',sex,len(objects))
