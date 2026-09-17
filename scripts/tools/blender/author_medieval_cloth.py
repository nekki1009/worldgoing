"""Explicit six-outfit art stages. Never called by the production pack builders.

Current body topology/weights supply fitted cloth; skirts are sewn panel grids.
The immutable task baseline protects every original underwear and animation.
"""
import argparse
import json
import math
import shutil
import sys
from pathlib import Path
import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).parent))
from build_standard_anime_male_character_pack import copy_mesh
from author_chinese_leather_mingguang import Fitting
from author_chinese_lining import cut, finish_mesh as finish_source_mesh
from author_chinese_cape import mesh_object
from author_mingguang_low_pose import skin_matrices, posed
from medieval_cloth_export import append_cloth

WORK = ROOT / 'assets/characters/human/q35/medieval_cloth'
QA = ROOT / 'output/medieval_cloth_20260916'
BASE = QA / 'baseline'
STYLES = ['Chinese', 'Japanese', 'European']


def finish_mesh(obj,bm,mat):
    finish_source_mesh(obj,bm,mat)
    # Refined body meshes carry custom skin normals. They are not valid after
    # cutting and easing cloth and otherwise emboss anatomy onto flat fabric.
    bpy.context.view_layer.objects.active=obj
    if obj.data.has_custom_normals:bpy.ops.mesh.customdata_custom_splitnormals_clear()
    return obj


def ident(style):
    return 'Outfit_Medieval_' + style + '_01_', 'outfit_medieval_' + style.lower() + '_01'


def material(name, shade):
    mat = bpy.data.materials.get('MedievalCloth_' + name) or bpy.data.materials.new('MedievalCloth_' + name)
    mat.use_nodes = True
    mat.diffuse_color = (*shade, 1)
    bs = mat.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*shade, 1)
    bs.inputs['Roughness'].default_value = .88
    return mat


def fitted_top(fit, style, cloth):
    prefix, visual = ident(style)
    # Reuse the already-authored under-shirt topology and seam weights. The
    # original garment is never edited; these are independent cloth meshes.
    source=bpy.data.objects['Outfit_Chinese_Lining_01_Shirt']
    obj=copy_mesh(source,prefix+'Shirt','outfit',visual)
    obj.shape_key_clear()
    for modifier in list(obj.modifiers):
        if modifier.type!='ARMATURE':obj.modifiers.remove(modifier)
    bm=bmesh.new();bm.from_mesh(obj.data)
    cut(bm,(0,0,fit.hip+.066),(0,0,1),inner=True)
    bm.normal_update()
    wrist=fit.bone('J_Bip_L_Hand').x-.018
    for vertex in bm.verts:
        if not vertex.link_faces:continue
        vertex.co+=vertex.normal*.003
        if style=='Japanese' and abs(vertex.co.x)>fit.shoulder.x+.025:
            t=float(np.clip((abs(vertex.co.x)-fit.shoulder.x-.025)/(wrist-fit.shoulder.x-.025),0,1))
            below=float(np.clip((fit.shoulder.z-vertex.co.z)/.035,0,1))
            vertex.co.z-=below*.075*math.sin(math.pi*t)**.5
            vertex.co.y*=1+.15*math.sin(math.pi*t)
    finish_mesh(obj,bm,cloth)
    return obj


def seam(source, name, mat, planes):
    obj=copy_mesh(source,source.name.removesuffix('Shirt')+name,'outfit',source['worldgoing_visual_id'])
    bm=bmesh.new();bm.from_mesh(obj.data)
    for point, normal, inner, outer in planes:cut(bm,point,normal,inner=inner,outer=outer)
    bm.normal_update()
    for v in bm.verts:
        if v.link_faces:v.co+=v.normal*.0012
    return finish_mesh(obj,bm,mat)


def trims(fit, style, top, binding):
    parts=[]
    for source in list(bpy.data.objects):
        name=source.name.removeprefix('Outfit_Chinese_Lining_01_')
        if source.type!='MESH' or name==source.name:continue
        if not (name.startswith('CrossLapel_') or name.startswith('Cuff_') or name=='BackCollar'):continue
        if style=='European' and name in ['CrossLapel_1','CrossLapel_2']:continue
        label=name.replace('CrossLapel_','Collar_')
        obj=copy_mesh(source,ident(style)[0]+label,'outfit',ident(style)[1])
        obj.shape_key_clear()
        for mod in list(obj.modifiers):
            if mod.type!='ARMATURE':obj.modifiers.remove(mod)
        bm=bmesh.new();bm.from_mesh(obj.data)
        cut(bm,(0,0,fit.hip+.071),(0,0,1),inner=True)
        bm.normal_update()
        for vertex in bm.verts:
            if vertex.link_faces:vertex.co+=vertex.normal*.003
        finish_mesh(obj,bm,binding)
        parts.append(obj)
    return parts


def trousers(fit, style, cloth):
    prefix,visual=ident(style)
    obj=copy_mesh(fit.body,prefix+('Hakama' if style=='Japanese' else 'Trousers'),'outfit',visual)
    obj.shape_key_clear()
    for modifier in list(obj.modifiers):
        if modifier.type!='ARMATURE':obj.modifiers.remove(modifier)
    obj.data.transform(obj.matrix_world);obj.matrix_world=Matrix.Identity(4);obj.parent=fit.arm
    bm=bmesh.new();bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.0001)
    ankle=fit.bone('J_Bip_L_Foot').z+.035
    cut(bm,(0,0,fit.hip+.025),(0,0,1),outer=True)
    cut(bm,(0,0,ankle),(0,0,1),inner=True)
    bm.normal_update()
    for v in bm.verts:
        if not v.link_faces:continue
        v.co+=v.normal*.013
        side='L' if v.co.x>=0 else 'R'
        hip=fit.bone('J_Bip_'+side+'_UpperLeg'); knee=fit.bone('J_Bip_'+side+'_LowerLeg'); foot=fit.bone('J_Bip_'+side+'_Foot')
        lower,upper=(foot,knee) if v.co.z<knee.z else (knee,hip)
        center=lower.lerp(upper,float(np.clip((v.co.z-lower.z)/(upper.z-lower.z),0,1)))
        delta=v.co-center
        theta=math.atan2(delta.x,-delta.y)
        free=max(0,min(1,(fit.hip-.09-v.co.z)/.12))
        ease=(.045 if style=='Japanese' else .017 if style=='Chinese' else .010)*free
        if style=='Japanese':
            ease+=.023*free*max(0,1-(v.co.z-ankle)/(fit.hip-ankle))
            # Pressed broad front pleats, not a smooth rigid leg cylinder.
            ease+=.012*free*math.cos(theta*5+.3)
        v.co.x+=math.sin(theta)*ease;v.co.y-=math.cos(theta)*ease
    finish_mesh(obj,bm,cloth)
    bpy.context.view_layer.objects.active=obj
    sub=obj.modifiers.new('TrouserTailoring','SUBSURF');sub.levels=1
    bpy.ops.object.modifier_move_up(modifier=sub.name);bpy.ops.object.modifier_apply(modifier=sub.name)
    return obj


def skirt(fit, style, cloth, binding, short=False):
    prefix,visual=ident(style)
    rows,cols=18,80
    top=fit.hip+.065
    bottom=fit.hip-({'European':.22,'Chinese':.135,'Japanese':.11}[style]) if short else fit.bone('J_Bip_L_Foot').z+.19
    hip_points=[p for p in fit.points if fit.hip-.06<p.z<fit.hip+.065 and abs(p.x)<fit.shoulder.x]
    rx=max(abs(p.x) for p in hip_points)+.022
    cy=(max(p.y for p in hip_points)+min(p.y for p in hip_points))/2
    ry=(max(p.y for p in hip_points)-min(p.y for p in hip_points))/2+.022
    verts=[];uvs=[];faces=[];mi=[]
    for r in range(rows+1):
        t=r/rows
        for c in range(cols+1):
            angle=math.tau*c/cols
            # Unequal sewn gores: broad center front, narrower side panels.
            fold=0.0
            for pos,strength,width in [(.35,.018,.11),(-.41,.014,.13),(1.15,.011,.10),(-1.03,.014,.10),(2.72,.016,.14),(-2.62,.019,.11)]:
                d=(angle-pos+math.pi)%math.tau-math.pi
                fold+=strength*(math.exp(-((d-width)/width)**2)-.7*math.exp(-((d+width)/width)**2))
            flare=(.055 if short else .15 if style!='Japanese' else .115)*t**.8
            fold*=math.sin(t*math.pi/2)
            waist=waist_point(fit,style,angle,top)
            blend=min(t/.25,1)
            x=waist.x*(1-blend)+(rx+flare+fold)*math.sin(angle)*blend
            y=waist.y*(1-blend)+(cy-(ry+flare*.72+fold)*math.cos(angle))*blend
            z=top+(bottom-top)*t+.003*math.cos(angle*3+.2)*t**3
            verts.append((x,y,z));uvs.append((c/cols,t))
    for r in range(rows):
        for c in range(cols):
            i=r*(cols+1)+c;faces.append((i,i+1,i+cols+2,i+cols+1))
            mi.append(1 if r==rows-1 else 0)
    points=np.array(verts);t=np.repeat(np.linspace(0,1,rows+1),cols+1)
    left=np.clip(.5+points[:,0]/(rx*2),0,1)
    # The upper sewn panels follow the thighs; the loose hem blends back to
    # the pelvis/gravity correction instead of splitting into rigid leg tubes.
    leg=.62*np.clip(t/.28,0,1)*(1-.6*np.clip((t-.35)/.65,0,1))
    weights={'J_Bip_C_Hips':1-leg,'J_Bip_L_UpperLeg':leg*left,'J_Bip_R_UpperLeg':leg*(1-left)}
    # Match the shirt's supporting torso weights at the shared waist seam.
    for i,point in enumerate(verts):
        anchor=max(0,1-t[i]/.25)
        if anchor<=0:continue
        for group in weights:weights[group][i]*=1-anchor
        for group,value in fit.weights(Vector(point)).items():
            if group not in weights:weights[group]=np.zeros(len(verts))
            weights[group][i]+=value*anchor
    names=list(weights)
    values=np.column_stack([weights[name] for name in names])
    if len(names)>4:
        dropped=np.argsort(values,axis=1)[:,:-4]
        values[np.arange(len(verts))[:,None],dropped]=0
    values/=values.sum(axis=1)[:,None]
    weights={name:values[:,i] for i,name in enumerate(names)}
    obj=mesh_object(prefix+('TunicSkirt' if short else 'Skirt'),verts,faces,uvs,fit.arm,[cloth,binding],mi,weights)
    obj['worldgoing_component_slot']='outfit';obj['worldgoing_visual_id']=visual
    obj['cloth_rows']=rows;obj['cloth_cols']=cols;obj['cloth_top']=top;obj['cloth_bottom']=bottom
    return obj


def waist_point(fit,style,angle,z):
    direction=Vector((math.sin(angle),-math.cos(angle),0))
    origin=Vector((0,0,max(z,fit.hip+.079)))
    hit,normal,_,_=fit.cloth_waist[style].ray_cast(origin,direction,.4)
    if hit is None:return fit.torso(angle,z,.012)
    hit+=direction*.002;hit.z=z
    return hit


def sash(fit, style, top, mat):
    points=[];faces=[];uv=[]
    for r in range(2):
        for c in range(81):
            p=waist_point(fit,style,math.tau*c/80,fit.hip+.060+r*.025)
            p+=Vector((math.sin(math.tau*c/80),-math.cos(math.tau*c/80),0))*.006
            points.append(p);uv.append((c/80,r))
    for c in range(80):faces.append((c,c+1,c+82,c+81))
    weights={}
    for i,point in enumerate(points):
        for group,value in fit.weights(point).items():
            if group not in weights:weights[group]=np.zeros(len(points))
            weights[group][i]=value
    obj=mesh_object(ident(style)[0]+'WaistTie',points,faces,uv,fit.arm,[mat],[0]*80,weights)
    obj['worldgoing_component_slot']='outfit';obj['worldgoing_visual_id']=ident(style)[1]
    obj['medieval_waist_clearance']=2
    return obj


def build(fit):
    cloth=material('Linen',(.66,.63,.56));binding=material('Binding',(.16,.145,.12));tie=material('Tie',(.025,.027,.029))
    parts=[];fit.cloth_waist={}
    for style in STYLES:
        top=fitted_top(fit,style,cloth)
        fit.cloth_waist[style]=BVHTree.FromPolygons([v.co for v in top.data.vertices],[tuple(p.vertices) for p in top.data.polygons])
        parts.extend([top,*trims(fit,style,top,binding),sash(fit,style,top,tie)])
        if fit.sex=='male':parts.append(trousers(fit,style,cloth))
        parts.append(skirt(fit,style,cloth,binding,short=fit.sex=='male'))
    for obj in parts:
        obj['worldgoing_component_slot']='armor'
        obj['worldgoing_armor_category']='cloth'
    return parts


def save(sex):
    temporary=ROOT/f'.godot-temp/medieval_cloth_{sex}_source.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(temporary))
    dest=WORK/f'medieval_cloth_{sex}.blend'
    shutil.copy2(temporary,dest)
    assert dest.stat().st_size==temporary.stat().st_size
    temporary.unlink()


def detail(fit,parts):
    cloth=bpy.data.materials['MedievalCloth_Linen']
    image=bpy.data.images.load(str(ROOT/'assets/characters/human/q35/chinese_lining/FabricColor.png'),check_existing=True)
    image.pack()
    node=cloth.node_tree.nodes.new('ShaderNodeTexImage');node.image=image
    bs=cloth.node_tree.nodes.get('Principled BSDF')
    cloth.node_tree.links.new(node.outputs['Color'],bs.inputs['Base Color'])
    for obj in parts:
        if obj.name.endswith('Shirt'):
            obj.shape_key_add(name='Basis');key=obj.shape_key_add(name='UnderArmor')
            for source,v in zip(obj.data.vertices,key.data):
                hit,normal,_,_=fit.bvh.find_nearest(source.co)
                factor=float(np.clip((.19-abs(source.co.x))/.05,0,1))
                v.co=source.co.lerp(hit+normal*.0025,factor)
        elif obj.name.endswith(('Trousers','Hakama')):
            obj.shape_key_add(name='Basis');key=obj.shape_key_add(name='BootTuck')
            for source,v in zip(obj.data.vertices,key.data):
                hit,normal,_,_=fit.bvh.find_nearest(source.co)
                factor=float(np.clip((fit.knee-.025-source.co.z)/.12,0,1))
                v.co=source.co.lerp(hit+normal*.004,factor)
    return bake_skirts(fit,[o for o in parts if 'cloth_rows' in o])




def skirt_contact(local, probes, rows, cols):
    """Local convex capsule sections, not a scaled ellipse around the whole ring."""
    angles=np.linspace(0,math.tau,cols,endpoint=False)
    normals=np.column_stack((np.sin(angles),-np.cos(angles)))
    points=np.array([p for p,r in probes]);radii=np.array([r for p,r in probes])
    target=local.reshape(rows+1,cols+1,3)
    radial=np.linalg.norm(target[:,:,:2],axis=2)
    direction=target[:,:,:2]/np.maximum(radial[:,:,None],1e-6)
    needed=radial.copy()
    for row in range(1,rows+1):
        z=float(target[row,:,2].mean())
        section=radii*radii-(points[:,2]-z)**2
        valid=section>0
        if not valid.any():continue
        support=np.maximum(.003,np.max(points[valid,:2]@normals.T+np.sqrt(section[valid,None]),axis=0))
        dot=direction[row]@normals.T
        boundary=np.min(np.where(dot>1e-6,support[None,:]/np.maximum(dot,1e-6),np.inf),axis=1)
        needed[row]=np.maximum(radial[row],boundary+.009)
    # Spread a contact over adjacent cloth rings and panels, retaining folds
    # elsewhere. Neither the opposite side nor the whole hem is scaled up.
    delta=needed-radial
    for _ in range(4):
        padded=np.pad(delta,((1,1),(0,0)),mode='edge')
        soft=(padded[:-2]+2*padded[1:-1]+padded[2:])/4
        soft=(np.roll(soft,1,axis=1)+2*soft+np.roll(soft,-1,axis=1))/4
        delta=np.maximum(delta,soft)
    fade=np.minimum(np.arange(rows+1)/rows/.17,1)
    target[:,:,:2]+=direction*delta[:,:,None]*fade[:,None,None]
    target[:,-1]=target[:,0]
    return target.reshape(-1,3)


def bake_skirts(fit,skirts):
    arm=fit.arm;scene=bpy.context.scene
    visibility={obj:obj.hide_viewport for obj in bpy.data.objects if obj.type=='MESH'}
    # Posed coordinates are evaluated below from native bone matrices. Disable
    # unrelated mesh evaluation while sampling, then restore it before saving.
    for obj in visibility:obj.hide_viewport=True
    for tr in arm.animation_data.nla_tracks:tr.mute=True
    clips=json.loads((BASE/f'standard_anime_{fit.sex}_character_pack.json').read_text(encoding='utf-8'))['animations']
    timing={}
    for obj in skirts:
        if obj.data.shape_keys:obj.shape_key_clear()
        obj.shape_key_add(name='Basis')
        base=np.array([v.co[:] for v in obj.data.vertices])
        rows,cols=int(obj['cloth_rows']),int(obj['cloth_cols'])
        t=np.repeat(np.linspace(0,1,rows+1),cols+1)
        angle=np.tile(np.linspace(0,math.tau,cols+1),rows+1)
        top=float(obj['cloth_top']);bottom=float(obj['cloth_bottom'])
        waist=np.array((0,0,top));blocks_by_clip={}
        for clip in clips:
            if clip=='T-Pose':continue
            action=bpy.data.actions.get(clip)
            assert action is not None,clip
            for bone in arm.pose.bones:bone.matrix_basis=Matrix.Identity(4)
            arm.animation_data.action=action
            start,end=map(float,action.frame_range)
            frames=np.linspace(start,end,17 if clip in ['run','walk_slash','attack_jump_heavy'] else 13)
            timing[clip]=[float(frame/24) for frame in frames]
            blocks=[]
            for si,frame in enumerate(frames):
                scene.frame_set(int(frame),subframe=frame-int(frame));bpy.context.view_layer.update()
                skin=skin_matrices(arm,obj);raw=posed(base,skin)
                hip=arm.pose.bones['J_Bip_C_Hips'].matrix@arm.data.bones['J_Bip_C_Hips'].matrix_local.inverted()
                anchor=np.array(hip@Vector(waist))
                yaw=math.atan2(hip[1][0],hip[0][0]);cs,sn=math.cos(yaw),math.sin(yaw)
                rot=np.array([[cs,-sn,0],[sn,cs,0],[0,0,1]])
                hanging=(base-waist)@rot.T+anchor
                blend=(t*t*(3-2*t))[:,None]*.82
                target=raw*(1-blend)+hanging*blend
                local=(target-anchor)@rot
                probes=[]
                for side in ['L','R']:
                    for name,radius in [('UpperLeg',.092 if fit.sex=='female' else .102),('LowerLeg',.067),('Foot',.073),('Hand',.042)]:
                        bone=arm.pose.bones['J_Bip_'+side+'_'+name]
                        for fraction in np.linspace(0,1,11):
                            point=(np.array(bone.head.lerp(bone.tail,float(fraction)))-anchor)@rot
                            probes.append((point,radius))
                local=skirt_contact(local,probes,rows,cols)
                if clip.startswith('ride_') and top-bottom>.4:
                    local[:,0]*=1+.35*t*t
                    local[:,2]+=.18*t*t
                amplitude=.003 if clip in ['idle','guard'] else .012
                phase=math.tau*si/(len(frames)-1)
                local[:,1]+=amplitude*np.sin(phase-t*1.3)*t*t
                target=local@rot.T+anchor
                # Soft hem lift from the waist for low poses, not per-vertex
                # flattening; keep the sewn ring topology and lower clearance.
                low=float(target[:,2].min())
                if low<.035:target[:,2]+=(.035-low)*t
                corrected=posed(target,np.linalg.inv(skin))
                key=obj.shape_key_add(name=f'Cloth_{clip}_{si:02d}')
                key.data.foreach_set('co',corrected.astype('float32').ravel());blocks.append(key)
            blocks_by_clip[clip]=(frames,blocks)
        keys=obj.data.shape_keys;keys.animation_data_create()
        for clip,(frames,blocks) in blocks_by_clip.items():
            action=bpy.data.actions.new(obj.name+'_'+clip);action.use_fake_user=True
            for key in list(keys.key_blocks)[1:]:
                curve=action.fcurves.new(data_path=key.path_from_id('value'))
                samples=list(enumerate(frames)) if key in blocks else [(0,frames[0])]
                curve.keyframe_points.add(len(samples))
                for i,frame in samples:
                    curve.keyframe_points[i].co=(float(frame),float(key in blocks and blocks.index(key)==i))
                    curve.keyframe_points[i].interpolation='LINEAR'
            track=keys.animation_data.nla_tracks.new();track.name=clip
            track.strips.new(clip,int(frames[0]),action);track.mute=True
        keys.animation_data.action=None
        for key in keys.key_blocks:key.value=0
        print('MEDIEVAL_SKIRT_CORRECTIVES',obj.name,len(keys.key_blocks)-1,flush=True)
    arm.animation_data.action=None
    for bone in arm.pose.bones:bone.matrix_basis=Matrix.Identity(4)
    scene.frame_set(0);bpy.context.view_layer.update()
    for obj,hidden in visibility.items():obj.hide_viewport=hidden
    (WORK/f'{fit.sex}_clip_times.json').write_text(json.dumps(timing,indent=2),encoding='utf-8')
    return timing


def export(fit,parts):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [fit.arm,*parts]:
        obj.hide_set(False);obj.hide_viewport=False;obj.hide_render=False;obj.select_set(True)
    bpy.context.view_layer.objects.active=fit.arm
    subset=QA/f'{fit.sex}_subset.glb'
    bpy.ops.export_scene.gltf(filepath=str(subset),export_format='GLB',use_selection=True,
        export_animations=False,export_skins=True,export_morph=True,export_apply=False,export_try_sparse_sk=False)
    timing=json.loads((WORK/f'{fit.sex}_clip_times.json').read_text(encoding='utf-8'))
    append_cloth(BASE/f'standard_anime_{fit.sex}_character_pack.glb',subset,WORK/f'candidate_{fit.sex}.glb',timing)
    metadata=json.loads((BASE/f'standard_anime_{fit.sex}_character_pack.json').read_text(encoding='utf-8'))
    metadata['parts']['armor'].extend(o.name for o in parts)
    metadata['medieval_cloth']={'revision':4,'slot':'armor','category':'cloth','styles':[ident(s)[1] for s in STYLES],'source':f'res://assets/characters/human/q35/medieval_cloth/medieval_cloth_{fit.sex}.blend','reference':'res://output/medieval_cloth_20260916/reference','clips':list(timing)}
    (WORK/f'candidate_{fit.sex}.json').write_text(json.dumps(metadata,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')


def render(fit, parts, source=False):
    arm=fit.arm;arm.animation_data.action=None
    for track in arm.animation_data.nla_tracks:track.mute=True
    for bone in arm.pose.bones:bone.matrix_basis=Matrix.Identity(4)
    for side,angle in [('L',75),('R',-75)]:
        bone=arm.pose.bones['J_Bip_'+side+'_UpperArm'];pivot=bone.bone.head_local
        bone.matrix=Matrix.Translation(pivot)@Matrix.Rotation(math.radians(angle),4,'Y')@Matrix.Translation(-pivot)@bone.bone.matrix_local
    bpy.context.view_layer.update()
    scene=bpy.context.scene;scene.render.engine='BLENDER_WORKBENCH'
    scene.display.shading.light='STUDIO';scene.display.shading.color_type='OBJECT';scene.display.shading.show_cavity=True
    scene.display.shading.background_type='WORLD'
    if scene.world is None:scene.world=bpy.data.worlds.new('ClothReviewWorld')
    scene.world.color=(.11,.11,.11)
    scene.render.resolution_x=1024;scene.render.resolution_y=1280;scene.render.resolution_percentage=100
    data=bpy.data.cameras.new('ClothReview');camera=bpy.data.objects.new('ClothReview',data);scene.collection.objects.link(camera);scene.camera=camera
    data.type='ORTHO';data.ortho_scale=1.94 if fit.sex=='male' else 1.82
    target=Vector((0,0,.87 if fit.sex=='male' else .81))
    for style in ['Source'] if source else STYLES:
        visible={fit.body.name,'Face_Standard_01','Hair_Short_01' if fit.sex=='male' else 'Hair_Long_01'}
        if source:visible.update(o.name for o in bpy.data.objects if o.name.startswith('Outfit_Underlayer_01'))
        else:visible.update(o.name for o in parts if o.name.startswith(ident(style)[0]) and not o.name.endswith('Armored'))
        for obj in bpy.data.objects:
            if obj.type!='MESH':continue
            obj.hide_set(False);obj.hide_viewport=False;obj.hide_render=obj.name not in visible
            obj.color=(.55,.55,.55,1) if obj in parts else (.24,.24,.24,1)
            if obj in parts and obj.data.materials and obj.data.materials[0].name != 'MedievalCloth_Linen':obj.color=(.25,.25,.25,1)
        for label,angle in [('front',0),('left',-90),('right',90),('back',180),('threequarter',35),('cloth_only',35)]:
            if label=='cloth_only':fit.body.hide_render=True
            a=math.radians(angle);camera.location=target+Vector((math.sin(a)*4,-math.cos(a)*4,0))
            camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
            scene.render.filepath=str(QA/'gray'/f'{fit.sex}_{style.lower()}_{label}.png')
            bpy.ops.render.render(write_still=True)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--sex',choices=['male','female'],required=True);parser.add_argument('--stage',choices=['probe','gray','detail','polish','export'],required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    WORK.mkdir(parents=True,exist_ok=True);(QA/'gray').mkdir(parents=True,exist_ok=True)
    bpy.context.preferences.filepaths.save_version=0
    path=BASE/f'standard_anime_{args.sex}_character_pack.blend' if args.stage in ['probe','gray'] else WORK/f'medieval_cloth_{args.sex}.blend'
    bpy.ops.wm.open_mainfile(filepath=str(path));fit=Fitting(bpy.data.objects['Armature'],args.sex)
    print('CLOTH_BODY_SOURCE',fit.body.name,'modifiers',[(m.name,m.type) for m in fit.body.modifiers], 'matrix',list(fit.body.matrix_world),'shape_keys',fit.body.data.shape_keys,flush=True)
    if args.stage=='probe':
        report={'sex':args.sex,'body_vertices':len(fit.points),'hip':fit.hip,'neck':fit.neck,'knee':fit.knee,'bones':{b.name:list(fit.arm.matrix_world@b.head_local) for b in fit.arm.data.bones},'body_groups':dict((g.name,len([v for v in fit.body.data.vertices if any(w.group==g.index for w in v.groups)])) for g in fit.body.vertex_groups)}
        (QA/f'{args.sex}_fit_probe.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
        render(fit,[],source=True)
    elif args.stage=='gray':
        parts=build(fit);save(args.sex);render(fit,parts)
    else:
        parts=[o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith('Outfit_Medieval_') and not o.name.endswith('SkirtArmored')]
        for obj in parts:
            obj['worldgoing_component_slot']='armor'
            obj['worldgoing_armor_category']='cloth'
        if args.stage=='detail':detail(fit,parts);save(args.sex)
        elif args.stage=='polish':
            rebind=False
            for obj in parts:
                if obj.name.endswith('WaistTie') and obj.get('medieval_waist_clearance',1)<2:
                    for vertex in obj.data.vertices:
                        radial=Vector((vertex.co.x,vertex.co.y,0)).normalized()
                        vertex.co+=radial*.0045
                    obj.data.update();obj['medieval_waist_clearance']=2
                if 'cloth_rows' in obj:
                    for vertex in obj.data.vertices:
                        groups=sorted([(g.group,g.weight) for g in vertex.groups if g.weight>1e-7],key=lambda g:-g[1])
                        if len(groups)<=4:continue
                        rebind=True
                        for index,_ in groups[4:]:obj.vertex_groups[index].remove([vertex.index])
                        total=sum(weight for _,weight in groups[:4])
                        for index,weight in groups[:4]:obj.vertex_groups[index].add([vertex.index],weight/total,'REPLACE')
            bake_skirts(fit,[o for o in parts if 'cloth_rows' in o])
            save(args.sex)
        else:export(fit,parts)
    print('MEDIEVAL_CLOTH_STAGE_READY',args.sex,args.stage,flush=True)


if __name__=='__main__':main()
