"""Read-only baseline geometry/rig inventory for the scoped visual repairs."""
import sys,json
from pathlib import Path
import bpy
from mathutils import Vector

root=Path(__file__).resolve().parents[3]
sex=sys.argv[-1]
asset=root/'assets/mounts/horse/standard_horse_pack.blend' if sex=='horse' else root/f'assets/characters/human/q35/standard_anime_{sex}_character_pack.blend'
if '--candidate' in sys.argv:asset=root/f'assets/characters/human/q35/audit_repair/candidate_{sex}.blend'
bpy.ops.wm.open_mainfile(filepath=str(asset))
arm=next(o for o in bpy.data.objects if o.type=='ARMATURE')
arm.animation_data.action=None
for track in arm.animation_data.nla_tracks: track.mute=True
for bone in arm.pose.bones: bone.matrix_basis.identity()
bpy.context.view_layer.update()
data={}
for obj in bpy.data.objects:
    if obj.type!='MESH':continue
    pts=[obj.matrix_world@v.co for v in obj.data.vertices]
    data[obj.name]={'verts':len(pts),'faces':len(obj.data.polygons),'materials':[m.name if m else None for m in obj.data.materials], 'bounds':[[min(p[i] for p in pts),max(p[i] for p in pts)] for i in range(3)] if pts else [],'parent':obj.parent.name if obj.parent else None,'parent_bone':obj.parent_bone,'matrix':[list(row) for row in obj.matrix_world], 'shapes':len(obj.data.shape_keys.key_blocks) if obj.data.shape_keys else 0}
    data[obj.name]['modifiers']=[(m.name,m.type) for m in obj.modifiers]
    data[obj.name]['custom_normals']=obj.data.has_custom_normals
data['BONES']={b.name:[list(b.head_local),list(b.tail_local)] for b in arm.data.bones if sex=='horse' or b.name.startswith('J_Bip_') and any(k in b.name for k in ['Hand','Arm','Chest','Foot','Hips'])}
if sex!='horse':
    body=bpy.data.objects['Body_Standard_'+sex.title()]
    points=[body.matrix_world@v.co for v in body.data.vertices]
    sections={}
    for z in ([1.333,1.35,1.372] if sex=='female' else [1.439,1.46,1.48]):
        cuts=[]
        for edge in body.data.edges:
            a,b=[points[i] for i in edge.vertices]
            if (a.z-z)*(b.z-z)<0:
                p=a.lerp(b,(z-a.z)/(b.z-a.z))
                if abs(p.x)<.15:cuts.append(p)
        sections[z]=[[min(p[i] for p in cuts),max(p[i] for p in cuts)] for i in range(2)]
    print('NECK_SECTIONS',sections,flush=True)
dest=root/f'.godot-temp/model_audit_repairs/{sex}_inventory.json'
if '--candidate' in sys.argv:dest=dest.with_stem(sex+'_candidate_inventory')
dest.parent.mkdir(parents=True,exist_ok=True)
dest.write_text(json.dumps(data,indent=2))
print('AUDIT_INVENTORY',sex,len(data),dest)
