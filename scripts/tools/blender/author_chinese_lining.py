"""Thin fitted under-armor shirt, editable source and scoped export."""
import argparse,json,math,sys,shutil,uuid
from pathlib import Path
import bpy,bmesh
import numpy as np
from mathutils import Matrix,Vector
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(Path(__file__).parent))
from build_standard_anime_male_character_pack import copy_mesh
from author_chinese_leather_mingguang import Fitting,mesh_part
from repair_chinese_cloak_run import repair_run
BASE=ROOT/'.godot-temp/lining_cloak_baseline_20260910'
WORK=ROOT/'assets/characters/human/q35/chinese_lining'
QA=ROOT/'.visual_captures/lining_cloak'
PREFIX='Outfit_Chinese_Lining_01_'


def save_source(sex):
    # Save outside the syncing art folder, then copy without a rename operation.
    temporary=ROOT/f'.godot-temp/lining_save_{sex}_{uuid.uuid4().hex}.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(temporary))
    shutil.copy2(temporary,WORK/f'chinese_lining_{sex}.blend')


def material(name,color):
    m=bpy.data.materials.new('ChineseLining_'+name);m.use_nodes=True;m.diffuse_color=(*color,1)
    bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1);bs.inputs['Roughness'].default_value=.87
    return m


def cut(bm,point,normal,inner=False,outer=False):
    bmesh.ops.bisect_plane(bm,geom=list(bm.verts)+list(bm.edges)+list(bm.faces),dist=.000001,plane_co=point,plane_no=normal,clear_inner=inner,clear_outer=outer)


def finish_mesh(obj,bm,mat):
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(obj.data);bm.free()
    obj.data.materials.clear();obj.data.materials.append(mat)
    for p in obj.data.polygons:p.material_index=0;p.use_smooth=True
    obj.data.update();return obj


def shirt(fit,cloth):
    obj=copy_mesh(fit.body,PREFIX+'Shirt','outfit','outfit_chinese_lining_01')
    obj.data.transform(obj.matrix_world);obj.matrix_world=Matrix.Identity(4);obj.parent=fit.arm
    bm=bmesh.new();bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.0001)
    cut(bm,(0,0,fit.hip-.025),(0,0,1),inner=True)
    cut(bm,(0,0,fit.neck+.010),(0,0,1),outer=True)
    wrist=fit.bone('J_Bip_L_Hand').x-.017
    cut(bm,(wrist,0,0),(1,0,0),outer=True);cut(bm,(-wrist,0,0),(-1,0,0),outer=True)
    # Two diagonal cuts provide a clean modest V at the front neckline.
    center=fit.neck-.075
    for side in [-1,1]:cut(bm,(0,0,center),(-side*1.55,0,1))
    remove=[f for f in bm.faces if (p:=f.calc_center_median()).y<fit.bone('J_Bip_C_Neck').y and p.z>center+abs(p.x)*1.55 and abs(p.x)<.07]
    bmesh.ops.delete(bm,geom=remove,context='FACES')
    bm.normal_update()
    for v in bm.verts:
        if not v.link_faces:continue
        v.co+=v.normal*.005
        # Cloth bridges abdominal/bust concavities instead of printing every
        # skin feature. The same measured envelope as the armor, with less ease.
        if abs(v.co.x)<fit.shoulder.x and fit.hip+.025<v.co.z<fit.neck-.05:
            rx,front,back=[float(np.interp(v.co.z,fit.levels,fit.profiles[:,i])) for i in range(3)]
            angle=math.atan2(v.co.x/rx,-(v.co.y-(front+back)/2)/((back-front)/2))
            target=fit.torso(angle,v.co.z,.004)
            amount=min(1,(fit.neck-.05-v.co.z)/.06,(v.co.z-fit.hip-.025)/.05)
            if v.co.y<0:v.co.y=min(v.co.y,v.co.y*(1-amount)+target.y*amount)
            else:v.co.y=max(v.co.y,v.co.y*(1-amount)+target.y*amount)
    finish_mesh(obj,bm,cloth)
    # Keep original deformation weights; a single refinement smooths cuts.
    bpy.context.view_layer.objects.active=obj
    sub=obj.modifiers.new('FabricSurface','SUBSURF');sub.levels=1
    bpy.ops.object.modifier_move_up(modifier=sub.name);bpy.ops.object.modifier_apply(modifier=sub.name)
    for v in obj.data.vertices:
        hit,normal,_,_=fit.bvh.find_nearest(v.co)
        signed=(v.co-hit).dot(normal)
        if signed<.003:v.co+=normal*(.003-signed)
    obj.data.update()
    return obj,wrist


def band_from_shirt(source,fit,name,mat,axis,lo,hi):
    obj=copy_mesh(source,PREFIX+name,'outfit','outfit_chinese_lining_01');bm=bmesh.new();bm.from_mesh(obj.data)
    normal=[0,0,0];normal[axis]=1;point=[0,0,0];point[axis]=lo;cut(bm,point,normal,inner=True)
    point[axis]=hi;cut(bm,point,normal,outer=True)
    bm.normal_update()
    for v in bm.verts:
        if v.link_faces:v.co+=v.normal*.0007
    return finish_mesh(obj,bm,mat)


def lapel(fit,shirt_obj,edge):
    # Trim actual shirt faces, preserving interpolated cloth weights at cuts.
    # Nearest-body weight transfer made a separate border sink when posed.
    path=[(-.048,fit.neck+.006),(0,fit.neck-.075),(.060,fit.neck-.16),(.112,fit.hip+.09)]
    segments=list(zip(path,path[1:]))+[((.048,fit.neck+.006),(0,fit.neck-.075))]
    parts=[]
    for index,((x0,z0),(x1,z1)) in enumerate(segments):
        obj=copy_mesh(shirt_obj,PREFIX+f'CrossLapel_{index}','outfit','outfit_chinese_lining_01')
        bm=bmesh.new();bm.from_mesh(obj.data);slope=(x1-x0)/(z1-z0)
        cut(bm,(0,0,min(z0,z1)-.002),(0,0,1),inner=True)
        cut(bm,(0,0,max(z0,z1)+.002),(0,0,1),outer=True)
        cut(bm,(x0-.009,0,z0),(1,0,-slope),inner=True)
        cut(bm,(x0+.009,0,z0),(1,0,-slope),outer=True)
        cut(bm,(0,0,0),(0,1,0),outer=True)
        bm.normal_update()
        for v in bm.verts:
            if v.link_faces:v.co.y-=.0014
        parts.append(finish_mesh(obj,bm,edge))
    collar=band_from_shirt(shirt_obj,fit,'BackCollar',edge,2,fit.neck-.006,fit.neck+.02)
    parts.append(collar)
    return parts


def build(fit):
    cloth=material('Linen',(.55,.52,.44));edge=material('Binding',(.18,.23,.28));shorts=material('Shorts',(.22,.24,.26))
    body,wrist=shirt(fit,cloth)
    parts=[body,band_from_shirt(body,fit,'Cuff_L',edge,0,wrist-.018,wrist+.01),band_from_shirt(body,fit,'Cuff_R',edge,0,-wrist-.01,-wrist+.018),band_from_shirt(body,fit,'Hem',cloth,2,fit.hip-.03,fit.hip-.008),*lapel(fit,body,edge)]
    # A complete Outfit choice includes modest shorts; old shorts stay unchanged.
    for original in [o for o in bpy.data.objects if o.name.startswith('Outfit_Underlayer_01_Underwear')]:
        copy=copy_mesh(original,PREFIX+original.name.removeprefix('Outfit_Underlayer_01_'),'outfit','outfit_chinese_lining_01')
        copy.data.materials.clear();copy.data.materials.append(shorts)
        for p in copy.data.polygons:p.material_index=0
        parts.append(copy)
    for obj in parts:obj['worldgoing_component_slot']='outfit';obj['worldgoing_visual_id']='outfit_chinese_lining_01'
    return parts


def under_armor_fit(fit,parts):
    # A thin fitted state for covered cloth, not a second body or new physics.
    # The standalone shirt retains its small ease; old close-fitting leather
    # armor has less clearance and must compress that ease when selected.
    for obj in parts:
        if obj.name.endswith('Shirt'):
            if not obj.data.shape_keys:obj.shape_key_add(name='Basis')
            key=obj.data.shape_keys.key_blocks.get('UnderArmor') or obj.shape_key_add(name='UnderArmor')
            for source,v in zip(obj.data.shape_keys.key_blocks['Basis'].data,key.data):
                hit,normal,_,_=fit.bvh.find_nearest(source.co)
                coverage=max(0,min(1,(.20-abs(source.co.x))/.04))
                # Only the central, armor-covered torso needs this inset;
                # keep exposed sleeves and neckline outside the original body.
                covered=min(1,max(0,(source.co.z-fit.hip-.015)/.035),max(0,(fit.neck-.025-source.co.z)/.04))
                covered*=max(0,min(1,(.12-abs(source.co.x))/.03))
                v.co=source.co.lerp(hit+normal*(.0013-.0033*covered),coverage)
    for obj in parts:
        if 'Underwear' in obj.name:
            obj.data.materials.clear();obj.data.materials.append(bpy.data.materials.get('ChineseLining_Shorts') or material('Shorts',(.22,.24,.26)))


def fabric_material():
    m=bpy.data.materials['ChineseLining_Linen'];bs=m.node_tree.nodes.get('Principled BSDF')
    size=1024;y,x=np.mgrid[0:size,0:size]/size
    weave=.012*np.cos(x*math.tau*128)*np.cos(y*math.tau*128)
    weave+=.007*np.random.default_rng(42).normal(size=(size,size))
    for label,base,socket in [('Color',(.62,.58,.49),'Base Color'),('Roughness',(.86,.86,.86),'Roughness')]:
        image=bpy.data.images.new('LiningFabric'+label,width=size,height=size)
        rgba=np.ones((size,size,4),dtype=np.float32)
        rgba[:,:,:3]=np.clip(np.array(base)[None,None,:]+weave[:,:,None],0,1)
        image.pixels.foreach_set(rgba.ravel());image.filepath_raw=str(WORK/f'Fabric{label}.png');image.file_format='PNG';image.save();image.pack()
        if label!='Color':image.colorspace_settings.name='Non-Color'
        tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image
        m.node_tree.links.new(tex.outputs['Color'],bs.inputs[socket])
    m.diffuse_color=(.62,.58,.49,1)
    # Real UV image routing is used; no unsupported procedural-only material.


def render(fit,parts):
    scene=bpy.context.scene;arm=fit.arm
    arm.animation_data.action=None
    for track in arm.animation_data.nla_tracks:track.mute=True
    for bone in arm.pose.bones:bone.matrix_basis=Matrix.Identity(4)
    bpy.context.view_layer.update()
    for side,angle in [('L',80),('R',-80)]:
        pb=arm.pose.bones['J_Bip_'+side+'_UpperArm'];pivot=pb.bone.head_local
        pb.matrix=Matrix.Translation(pivot)@Matrix.Rotation(math.radians(angle),4,'Y')@Matrix.Translation(-pivot)@pb.bone.matrix_local
    bpy.context.view_layer.update()
    for obj in bpy.data.objects:
        if obj.type=='MESH':obj.hide_render=not(obj in parts or obj.name in ('Body_Standard_'+fit.sex.title(),'Face_Standard_01','Hair_Short_01','Hair_Long_01'))
    scene.render.engine='BLENDER_WORKBENCH';scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_cavity=True
    scene.render.resolution_x=1024;scene.render.resolution_y=1280;scene.render.resolution_percentage=100
    data=bpy.data.cameras.new('LiningReview');camera=bpy.data.objects.new('LiningReview',data);scene.collection.objects.link(camera);scene.camera=camera;data.type='ORTHO';data.ortho_scale=2.05
    target=Vector((0,0,.86))
    for label,angle in [('front',0),('side',90),('back',180),('threequarter',35)]:
        a=math.radians(angle);camera.location=target+Vector((math.sin(a)*4,-math.cos(a)*4,0));camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(QA/f'{fit.sex}_gray_{label}.png');bpy.ops.render.render(write_still=True)


def export(sex,parts):
    arm=bpy.data.objects['Armature'];metadata=json.loads((BASE/f'standard_anime_{sex}_character_pack.json').read_text(encoding='utf-8'))
    names={name for values in metadata['parts'].values() for name in values}
    bpy.ops.object.select_all(action='DESELECT')
    for obj in bpy.data.objects:
        if obj==arm or obj.name in names or obj in parts:obj.hide_viewport=False;obj.hide_set(False);obj.select_set(True)
    target=WORK/f'candidate_{sex}.glb'
    bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=False,export_optimize_disable_viewport=True,export_skins=True,export_morph=True,export_apply=False)
    import author_chinese_cape as legacy
    legacy.BASE=BASE;legacy.preserve_legacy_clips(sex,target)
    metadata['parts']['outfit']+=sorted(o.name for o in parts)
    (WORK/f'candidate_{sex}.json').write_text(json.dumps(metadata,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--sex',choices=['male','female'],required=True);parser.add_argument('--stage',choices=['gray','detail','export'],required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);QA.mkdir(parents=True,exist_ok=True)
    # Immutable scoped backup exists; Dropbox can lock Blender's rolling .blend1.
    bpy.context.preferences.filepaths.save_version=0
    source=BASE/f'standard_anime_{args.sex}_character_pack.blend' if args.stage=='gray' else WORK/f'chinese_lining_{args.sex}.blend'
    bpy.ops.wm.open_mainfile(filepath=str(source));fit=Fitting(bpy.data.objects['Armature'],args.sex)
    if args.stage=='gray':
        repair_run(fit.arm);parts=build(fit)
        save_source(args.sex);render(fit,parts)
    else:
        if args.stage=='detail' and (redundant:=bpy.data.objects.get(PREFIX+'Top')):
            bpy.data.objects.remove(redundant,do_unlink=True)
        parts=[o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith(PREFIX)]
        if args.stage=='detail':
            under_armor_fit(fit,parts)
            fabric_material()
            save_source(args.sex)
        export(args.sex,parts)
    print('LINING_STAGE_READY',args.sex,args.stage,flush=True)


if __name__=='__main__':main()
