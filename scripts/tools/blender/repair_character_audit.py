"""Scoped, rebuildable repairs for the 2026-09-10 visual audit.

Uses the current pack's body surface, rig, actions and authored equipment.
No body scaling, replacement skeleton or runtime attachment framework.
"""
import math
import random
import numpy as np
import bpy,bmesh
from mathutils import Vector,Matrix,Euler


def geometry(obj):
    bm=bmesh.new();bm.from_mesh(obj.data)
    bmesh.ops.transform(bm,matrix=obj.matrix_world,verts=bm.verts)
    return bm


def save_geometry(obj,bm):
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
    bmesh.ops.transform(bm,matrix=obj.matrix_world.inverted(),verts=bm.verts)
    bm.to_mesh(obj.data);bm.free();obj.data.update()
    if obj.data.has_custom_normals:
        obj.data.normals_split_custom_set([(0,0,0)]*len(obj.data.loops))


def tube(bm,points,radii,sides=10):
    rows=[]
    for i,point in enumerate(points):
        p=Vector(point)
        tangent=(Vector(points[min(i+1,len(points)-1)])-Vector(points[max(0,i-1)])).normalized()
        normal=tangent.cross(Vector((0,0,1)))
        if normal.length<0.01:normal=tangent.cross(Vector((0,1,0)))
        normal.normalize();other=tangent.cross(normal).normalized()
        radius=radii[i] if isinstance(radii,list) else radii
        rows.append([bm.verts.new(p+radius*(normal*math.cos(j*math.tau/sides)+other*math.sin(j*math.tau/sides))) for j in range(sides)])
    for row,nxt in zip(rows,rows[1:]):
        for j in range(sides):bm.faces.new((row[j],row[(j+1)%sides],nxt[(j+1)%sides],nxt[j]))
    bm.faces.new(tuple(reversed(rows[0])));bm.faces.new(tuple(rows[-1]))


def box(bm,center,size,bevel=0.003):
    out=bmesh.ops.create_cube(bm,size=1.0)
    for v in out['verts']:v.co=Vector(center)+Vector(tuple(v.co[i]*size[i] for i in range(3)))
    if bevel:
        edges=list({e for v in out['verts'] for e in v.link_edges})
        bmesh.ops.bevel(bm,geom=edges,offset=bevel,segments=3,affect='EDGES')


def rigid(api,arm,name,bm,mat,bone,slot,visual):
    return api.create_bone_rigid_component(name,bm,mat,bone,slot,visual,arm)


def replace_objects(objects,old,new):
    replaced_names={obj.name for obj in old}
    for obj in old:
        if obj in objects:objects.remove(obj)
        bpy.data.objects.remove(obj,do_unlink=True)
    objects.extend(new)
    for obj in new:
        if obj.name.endswith('.001') and obj.name[:-4] in replaced_names:
            assert obj.name[:-4] not in bpy.data.objects
            obj.name=obj.name[:-4]


def surface_layer(body,name,mat,arm,slot,visual,zmin,zmax,offset=0.005,xmin=None,xmax=None):
    obj=body.copy();obj.data=body.data.copy();obj.name=name
    bpy.context.collection.objects.link(obj)
    for modifier in list(obj.modifiers):
        if modifier.type=='NODES' and 'MToon Outline' in modifier.name:obj.modifiers.remove(modifier)
    if obj.data.shape_keys:obj.shape_key_clear()
    bm=geometry(obj)
    # Weld duplicated skin seams before offsetting: otherwise normals open a slit.
    bmesh.ops.remove_doubles(bm,verts=bm.verts[:],dist=0.00005)
    bm.normal_update()
    for v in bm.verts:v.co+=v.normal*offset
    planes=[((0,0,zmin),(0,0,1),True),((0,0,zmax),(0,0,1),False)]
    if xmin is not None:planes.append(((xmin,0,0),(1,0,0),True))
    if xmax is not None:planes.append(((xmax,0,0),(1,0,0),False))
    for co,normal,inner in planes:
        bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],dist=0.000001,plane_co=co,plane_no=normal,clear_inner=inner,clear_outer=not inner)
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
    save_geometry(obj,bm)
    obj.data.materials.clear();obj.data.materials.append(mat)
    for poly in obj.data.polygons:poly.material_index=0;poly.use_smooth=True
    obj['worldgoing_component_slot']=slot;obj['worldgoing_visual_id']=visual
    obj['worldgoing_audit_repair']=1
    assert len(obj.data.polygons)>0,name
    return obj


def reset_rig(arm):
    if arm.animation_data:
        arm.animation_data.action=None
        for tr in arm.animation_data.nla_tracks:tr.mute=True
    for pb in arm.pose.bones:pb.matrix_basis.identity()
    bpy.context.view_layer.update()


def point_arm(arm,side,palm_target,basis):
    upper=arm.pose.bones['J_Bip_'+side+'_UpperArm'];lower=arm.pose.bones['J_Bip_'+side+'_LowerArm'];hand=arm.pose.bones['J_Bip_'+side+'_Hand']
    wrist=Vector(palm_target)-basis@Vector((0,0.045,-0.015))
    shoulder=upper.head.copy();delta=wrist-shoulder
    distance=delta.length;a=upper.length;b=lower.length
    assert distance<a+b,('unreachable hand',side,distance,a+b)
    direction=delta.normalized()
    bend=Vector((0.6 if side=='L' else -0.6,0.0,-1))
    bend=(bend-direction*bend.dot(direction)).normalized()
    along=(a*a-b*b+distance*distance)/(2*distance)
    elbow=shoulder+direction*along+bend*math.sqrt(max(0,a*a-along*along))
    for pb,start,end in [(upper,shoulder,elbow),(lower,elbow,wrist)]:
        rest=pb.bone.matrix_local.to_quaternion()
        rotation=(rest@Vector((0,1,0))).rotation_difference((end-start).normalized())@rest
        pb.matrix=Matrix.LocRotScale(start,rotation,None)
        bpy.context.view_layer.update()
    hand.matrix=Matrix.LocRotScale(wrist,basis.to_quaternion(),None)
    bpy.context.view_layer.update()


def repair_weapons(arm,objects,api,female):
    reset_rig(arm)
    # Move the shield shell away from the fingers, retaining forearm binding.
    left=arm.data.bones['J_Bip_L_LowerArm'].matrix_local
    for obj in objects:
        if not obj.name.startswith('Shield_Heater_01_') or '_Holstered_' in obj.name or '_Strap' in obj.name:continue
        bm=geometry(obj)
        for v in bm.verts:
            p=left.inverted()@v.co;p.y+=0.035;p.z+=0.065;v.co=left@p
        save_geometry(obj,bm)
    leather=next(o for o in objects if o.name=='Shield_Heater_01_Strap').data.materials[0]
    handle=bmesh.new();tube(handle,[left@Vector((-0.045,0.285,0.028)),left@Vector((0.045,0.285,0.028))],0.011)
    objects.append(rigid(api,arm,'Shield_Heater_01_Handle',handle,leather,'J_Bip_L_LowerArm','shield','shield_heater_01'))

    # Rebuild the crossbow as a stock, recurved prod, string and mechanism.
    old=[o for o in objects if o.name.startswith('Weapon_Crossbow_01_')]
    wood=next(o for o in old if o.name.endswith('_Stock')).data.materials[0]
    steel=next(o for o in old if o.name.endswith('_Prod')).data.materials[0]
    gold=next(o for o in objects if o.name=='Weapon_Longsword_01_Guard').data.materials[0]
    string_mat=next(o for o in objects if o.name=='Weapon_Bow_01_String').data.materials[0]
    hand_rest=arm.data.bones['J_Bip_R_Hand'].matrix_local
    palm=hand_rest@Vector((0,0.045,-0.015))
    new=[]
    for holstered in [False,True]:
        bone='J_Bip_C_UpperChest' if holstered else 'J_Bip_R_Hand'
        prefix='Weapon_Crossbow_01_'+('Holstered_' if holstered else '')
        transform=Matrix.Identity(4)
        if holstered:
            transform=Matrix.Rotation(math.pi/2,4,'X');transform.translation=Vector((0,0.24,1.18 if not female else 1.10))
        else:transform.translation=palm
        def part(suffix,bm,mat):
            bmesh.ops.transform(bm,matrix=transform,verts=bm.verts)
            new.append(rigid(api,arm,prefix+suffix,bm,mat,bone,'weapon','crossbow_01'))
        bm=bmesh.new()
        box(bm,(0,-0.10,0.022),(0.046,0.54,0.055),0.008)
        box(bm,(0,0.145,-0.002),(0.063,0.10,0.085),0.012)
        box(bm,(0,0.012,-0.022),(0.031,0.060,0.070),0.006)
        part('Stock',bm,wood)
        bm=bmesh.new()
        points=[Vector((x,-0.31-0.045*math.cos(x/0.24*math.pi/2),0.035+0.01*abs(x/0.24))) for x in [i*0.02 for i in range(-12,13)]]
        tube(bm,points,[0.007+0.006*(1-abs(p.x)/0.24) for p in points],10)
        part('Prod',bm,steel)
        bm=bmesh.new();tube(bm,[(-0.24,-0.31,0.045),(0,-0.115,0.052),(0.24,-0.31,0.045)],0.0025,8)
        part('String',bm,string_mat)
        bm=bmesh.new();box(bm,(0,-0.10,0.056),(0.019,0.31,0.009),0.002)
        tube(bm,[(-0.023,0.028,-0.036),(-0.026,-0.034,-0.056),(0.026,-0.034,-0.056),(0.023,0.028,-0.036)],0.004,8)
        tube(bm,[(-0.035,-0.36,0.018),(-0.035,-0.43,0.018),(0.035,-0.43,0.018),(0.035,-0.36,0.018)],0.005,8)
        part('Mechanism',bm,gold)
    replace_objects(objects,old,new)

    # Bake a genuine two-hand aiming pose on the existing arm bones.
    action=bpy.data.actions.get('attack_crossbow') or bpy.data.actions.new('attack_crossbow')
    for curve in list(action.fcurves):action.fcurves.remove(curve)
    action.use_fake_user=True
    height=1.21 if female else 1.31
    for f in range(31):
        reset_rig(arm);arm.animation_data.action=action
        recoil=0.014*math.exp(-((f-15)/2.0)**2)
        basis_r=arm.data.bones['J_Bip_R_Hand'].matrix_local.to_3x3()
        basis_l=arm.data.bones['J_Bip_L_Hand'].matrix_local.to_3x3()
        point_arm(arm,'R',(-0.09,-0.21+recoil,height+recoil),basis_r)
        point_arm(arm,'L',(-0.09,-0.325+recoil,height-0.018+recoil),basis_l)
        # Fingers curl around the trigger grip and fore-end; no extra rig.
        api.apply_right_hand_grip(arm)
        api.apply_left_hand_grip(arm)
        for pb in arm.pose.bones:
            pb.rotation_mode='QUATERNION'
            pb.keyframe_insert('rotation_quaternion',frame=f,group=pb.name)
            pb.keyframe_insert('location',frame=f,group=pb.name)
    reset_rig(arm)

    # Bowstring nock follows the actual drawing hand, baked into 3 morph axes.
    old_string=next(o for o in objects if o.name=='Weapon_Bow_01_String')
    lrest=arm.data.bones['J_Bip_L_Hand'].matrix_local
    bm=bmesh.new();base_points=[Vector((-0.57+1.14*i/16,-0.02,0)) for i in range(17)]
    tube(bm,base_points,0.0022,8)
    bmesh.ops.transform(bm,matrix=lrest,verts=bm.verts)
    string=rigid(api,arm,'Weapon_Bow_01_DynamicString',bm,string_mat,'J_Bip_L_Hand','weapon','bow_01')
    replace_objects(objects,[old_string],[string]);string.name='Weapon_Bow_01_String'
    string.shape_key_add(name='Basis')
    for axis in range(3):
        key=string.shape_key_add(name='Draw_'+str(axis));key.slider_min=-2;key.slider_max=2
        for v,point in zip(string.data.vertices,key.data):
            local=lrest.inverted()@v.co
            factor=max(0,1-abs(local.x)/0.57)
            shift=Vector((0,0,0));shift[axis]=factor
            point.co=v.co+lrest.to_3x3()@shift
    keys=string.data.shape_keys;keys.animation_data_create()
    morph=bpy.data.actions.new('AuditBow_Draw');morph.use_fake_user=True
    keys.animation_data.action=morph
    draw=bpy.data.actions.get('attack_bow');assert draw
    lo,hi=draw.frame_range
    for f in range(int(lo),int(hi)+1):
        arm.animation_data.action=draw;bpy.context.scene.frame_set(f);bpy.context.view_layer.update()
        lh=arm.pose.bones['J_Bip_L_Hand'].matrix
        rh=arm.pose.bones['J_Bip_R_Hand'].matrix
        nock=lh.inverted()@(rh@Vector((0,0.045,-0.015)))
        phase=(f-lo)/max(1,hi-lo)
        pull=min(1,max(0,(phase-0.26)/0.16))*min(1,max(0,(0.87-phase)/0.10))
        delta=(nock-Vector((0,-0.02,0)))*pull
        for axis in range(3):
            key=keys.key_blocks['Draw_'+str(axis)];key.value=delta[axis];key.keyframe_insert('value',frame=f)
    keys.animation_data.action=None
    tr=keys.animation_data.nla_tracks.new();tr.name='attack_bow'
    tr.strips.new(morph.name,int(lo),morph)
    for key in keys.key_blocks:key.value=0
    reset_rig(arm)
    # Small weapons retain their design, but gain readable edge highlights.
    for obj in objects:
        if obj.name.startswith('Weapon_Hammer_01_') and obj.name.endswith('_Head'):
            bm=geometry(obj);center=sum((v.co for v in bm.verts),Vector())/len(bm.verts)
            for v in bm.verts:v.co=center+Vector(tuple((v.co-center)[i]*[1.5,1.4,1.25][i] for i in range(3)))
            save_geometry(obj,bm)


def repair_clothing(arm,objects,api,female):
    body=next(o for o in objects if o.name==('Body_Standard_Female' if female else 'Body_Standard_Male'))
    prefix='Outfit_Underlayer_01'
    old=[o for o in objects if o.name.startswith(prefix)]
    main=next(o for o in old if 'Bottom' in o.name).data.materials[0]
    accent=api.material('Audit_Underwear_Binding',(0.07,0.10,0.15),roughness=0.9)
    top=0.958 if female else 1.015;bottom=0.755 if female else 0.775
    new=[surface_layer(body,prefix+'_UnderwearBottom',main,arm,'outfit','outfit_underlayer_01',bottom,top)]
    new.append(surface_layer(body,prefix+'_UnderwearWaistband',accent,arm,'outfit','outfit_underlayer_01',top-0.025,top+0.001,0.006))
    for side in ['L','R']:
        new.append(surface_layer(body,prefix+'_UnderwearLegOpening_'+side,accent,arm,'outfit','outfit_underlayer_01',bottom,bottom+0.018,0.006,xmin=0 if side=='L' else None,xmax=0 if side=='R' else None))
    if female:new.append(surface_layer(body,prefix+'_Top',main,arm,'outfit','outfit_underlayer_01',1.08,1.245,0.005,xmin=-0.14,xmax=0.14))
    replace_objects(objects,old,new)
    for obj in new:obj.name=obj.name.split('.')[0]
    # Repair the old light armor using that same actual skin, not guessed shells.
    prefix='Armor_Light_Leather_01'
    replacements={
        'Pants':(0.31 if female else 0.325,0.975 if female else 1.04,0.008,None,None),
        'Vest':(0.975 if female else 1.064,1.358 if female else 1.469,0.008,-0.154 if female else -0.184,0.154 if female else 0.184),
        'Collar':(1.308 if female else 1.401,1.338 if female else 1.444,0.011,-0.085 if female else -0.11,0.085 if female else 0.11),
        'WaistBand':(0.955 if female else 1.036,0.983 if female else 1.066,0.011,None,None),
    }
    for suffix,params in replacements.items():
        old=next(o for o in objects if o.name==prefix+'_'+suffix)
        new=surface_layer(body,old.name+'_New',old.data.materials[0],arm,'armor','armor_light_leather_01',*params)
        name=old.name;replace_objects(objects,[old],[new]);new.name=name
    for side in ['L','R']:
        bone=arm.data.bones['J_Bip_'+side+'_LowerArm']
        # Forearm region follows actual rest orientation. Female old bracers were empty.
        for suffix,a,b,offset in [('Bracer',0.12,0.72,0.008),('BracerStraps',0.16,0.25,0.010)]:
            old=next(o for o in objects if o.name==prefix+'_'+suffix+'_'+side)
            obj=body.copy();obj.data=body.data.copy();bpy.context.collection.objects.link(obj)
            if obj.data.shape_keys:obj.shape_key_clear()
            bm=geometry(obj);inv=bone.matrix_local.inverted()
            bmesh.ops.transform(bm,matrix=inv,verts=bm.verts)
            bmesh.ops.delete(bm,geom=[f for f in bm.faces if abs(f.calc_center_median().x)>0.10 or abs(f.calc_center_median().z)>0.12],context='FACES')
            for t,inner in [(a,True),(b,False)]:
                bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],plane_co=(0,bone.length*t,0),plane_no=(0,1,0),clear_inner=inner,clear_outer=not inner,dist=0.00001)
            bm.normal_update()
            for v in bm.verts:v.co+=v.normal*offset
            bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
            bmesh.ops.transform(bm,matrix=bone.matrix_local,verts=bm.verts)
            save_geometry(obj,bm)
            obj.data.materials.clear();obj.data.materials.append(old.data.materials[0])
            for p in obj.data.polygons:p.material_index=0;p.use_smooth=True
            name=old.name;replace_objects(objects,[old],[obj]);obj.name=name
            obj['worldgoing_component_slot']='armor';obj['worldgoing_visual_id']='armor_light_leather_01'


def smooth_hair_strand(bm,points,widths,normal_dir=Vector((0,0,1)),thickness_ratio=0.35):
    # Smaller overlapping locks with staggered tips break the repeated hard-strip
    # silhouette; roots are embedded in the original cap, not capped outside it.
    created=[]
    for strand in range(3):
        guides=[]
        for i,p in enumerate(points):
            tangent=(points[min(i+1,len(points)-1)]-points[max(0,i-1)]).normalized()
            side=tangent.cross(normal_dir).normalized()
            q=p+side*((strand-1)*0.26*widths[i])
            if i==0 and p.z<1.61:q.z+=0.035;q-=normal_dir.normalized()*0.012
            if i==len(points)-1:q+=(points[-2]-p)*(0.07*strand)
            guides.append(q)
        created.extend(_smooth_hair_lock(bm,guides,[w*0.53 for w in widths],normal_dir,thickness_ratio))
    return created


def _smooth_hair_lock(bm,points,widths,normal_dir,thickness_ratio):
    """Closed elliptical locks, smooth along the same authored guide curves."""
    rows=[];created=[]
    samples=[]
    for i in range(len(points)-1):
        p0=points[max(0,i-1)];p1=points[i];p2=points[i+1];p3=points[min(i+2,len(points)-1)]
        for step in range(6):
            t=step/6
            p=0.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t)
            samples.append((p,max(0.0005,widths[i]*(1-t)+widths[i+1]*t)))
    samples.append((points[-1],0.0005))
    previous_side=None
    for i,(p,width) in enumerate(samples):
        tangent=(samples[min(i+1,len(samples)-1)][0]-samples[max(0,i-1)][0]).normalized()
        side=(previous_side-tangent*previous_side.dot(tangent)).normalized() if previous_side else tangent.cross(normal_dir).normalized()
        if side.length<0.1:side=tangent.cross(Vector((1,0,0))).normalized()
        previous_side=side
        normal=side.cross(tangent).normalized()
        row=[bm.verts.new(p+side*(width*0.5*math.cos(j*math.tau/8))+normal*(width*thickness_ratio*math.sin(j*math.tau/8))) for j in range(8)]
        rows.append(row);created.extend(row)
    for row,nxt in zip(rows,rows[1:]):
        for j in range(8):
            f=bm.faces.new((row[j],row[(j+1)%8],nxt[(j+1)%8],nxt[j]));f.smooth=True;f.material_index=1
    for row in [rows[0][::-1],rows[-1]]:
        f=bm.faces.new(row);f.material_index=1
    return created


def repair_hair(arm,objects,api,female):
    source=next(o for o in objects if o.name==('Hair_Long_01' if female else 'Hair_Short_01'))
    mat=source.data.materials[0]
    # Source textures remain on the original cap. New closed locks have their own
    # matching untextured material instead of sampling an absent/zero UV island.
    lockmat=api.material('Audit_Hair_Locks',(0.018,0.017,0.024),roughness=0.72)
    for material in {m for o in objects if o.get('worldgoing_component_slot')=='hair' for m in o.data.materials if m}:
        if material.use_nodes:
            for node in material.node_tree.nodes:
                if node.type=='BSDF_PRINCIPLED':
                    node.inputs['Roughness'].default_value=0.72
                    node.inputs['Metallic'].default_value=0
                    node.inputs['Specular IOR Level'].default_value=0.22
    api.create_hair_strand=smooth_hair_strand
    gold=next(o for o in objects if o.name=='Weapon_Longsword_01_Guard').data.materials[0]
    for index in ([2,3,4] if female else [3,4]):
        name=('Hair_Long_' if female else 'Hair_Short_')+f'{index:02d}'
        old=[o for o in objects if o.name==name or o.name.startswith(name+'_')]
        visual=f'hair_short_{index:02d}'
        if female:
            fn={2:api.make_female_flowing_hair,3:api.make_female_bob_hair,4:api.make_female_high_ponytail}[index]
            args=[source,name+'_New',visual,arm,mat]+([gold] if index==4 else [])
        else:
            fn=api.make_male_hair_topknot if index==4 else api.make_male_hair_wild_spiky
            args=[source,name+'_New',visual,mat]+([gold] if index==4 else [])+[arm]
        result=fn(*args);new=result if isinstance(result,list) else [result]
        replace_objects(objects,old,new)
        for obj in new:
            obj.name=obj.name.replace('_New','')
            if not obj.name.endswith('_Band'):
                obj.data.materials.append(lockmat)
                for poly in obj.data.polygons:poly.use_smooth=True
        if index==4:
            band=next(o for o in new if o.name.endswith('_Band'))
            center=Vector((0,0.068,1.585)) if female else Vector((0,0.038,1.76))
            normal=Vector((0,0.5,1)).normalized();side=Vector((1,0,0));up=normal.cross(side)
            bm=bmesh.new()
            tube(bm,[center+0.025*(side*math.cos(t)+up*math.sin(t)) for t in [i*math.tau/32 for i in range(33)]],0.0035,8)
            save_geometry(band,bm)
            band.vertex_groups.clear()
            band.vertex_groups.new(name='J_Bip_C_Head').add(list(range(len(band.data.vertices))),1,'REPLACE')


def repair_travel_cape(arm,objects,api,female):
    """Join the existing back cloth to a real continuous shoulder collar."""
    main=next(o for o in objects if o.name=='Cape_Travel_01_Main')
    mat=main.data.materials[0]
    top=1.348 if female else 1.448
    half=0.13 if female else 0.155
    front=-0.112 if female else -0.125
    bm=bmesh.new();grid=[]
    for r in range(9):
        t=r/8;row=[]
        for c in range(33):
            a=-math.pi*0.72+math.tau*0.72*c/32
            # Open front; inner edge follows the neck, outer edge over shoulders.
            x=(0.070*(1-t)+half*t)*math.sin(a)
            y=(0.063*(1-t)+0.16*t)*math.cos(a)
            z=top+0.032*(1-t)-0.030*t*math.sin(a)**2
            row.append(bm.verts.new((x,y,z)))
        grid.append(row)
    for r in range(8):
        for c in range(32):bm.faces.new((grid[r][c],grid[r+1][c],grid[r+1][c+1],grid[r][c+1]))
    # Two front-to-back shoulder panels close the previously missing connection.
    for sign in [-1,1]:
        rows=[]
        for i in range(17):
            t=i/16;y=front+(0.165-front)*t
            x=sign*(0.083+0.015*math.sin(math.pi*t))*(0.85 if female else 1)
            z=top-0.026*math.sin(math.pi*t)-0.003*t
            rows.append([bm.verts.new((x+sign*d,y,z-abs(d)*0.16)) for d in [-0.029,0.029]])
        for a,b in zip(rows,rows[1:]):bm.faces.new((a[0],a[1],b[1],b[0]))
    bmesh.ops.solidify(bm,geom=bm.faces[:],thickness=0.003)
    objects.append(rigid(api,arm,'Cape_Travel_01_ShoulderMantle',bm,mat,'J_Bip_C_UpperChest','cape','cape_travel_01'))
    # Add an irregular soft vertical fold profile without changing its skinning.
    bm=geometry(main)
    for v in bm.verts:
        t=max(0,min(1,(top-v.co.z)/0.85))
        v.co.y+=0.008*math.sin(19*v.co.x+1.2)*t+0.010*math.sin(37*v.co.x-0.5)*t*t
        v.co.z-=0.008*math.cos(13*v.co.x)*t*t
    save_geometry(main,bm)


def repair_boots(arm,objects,api,female):
    # Reuse the actual fitted boot lasts, including the native ankle transition.
    # The old adventure boots remain plain cuff/strap boots, not Chinese knot boots.
    old=[o for o in objects if o.name.startswith('Boots_Leather_01_')]
    leather=api.material('Audit_AdventureBoot_Leather',(0.16,0.065,0.028),roughness=0.73)
    edge=api.material('Audit_AdventureBoot_Edge',(0.075,0.032,0.018),roughness=0.82)
    new=[]
    mapping={'Main':'Foot','Sole':'Sole','Heel':'Heel','Cuff':'Cuff','AnkleBand':'Strap'}
    for side in ['L','R']:
        for original,suffix in mapping.items():
            src=next(o for o in objects if o.name==f'Boots_Chinese_Leather_01_{original}_{side}')
            obj=src.copy();obj.data=src.data.copy();obj.name=f'Boots_Leather_01_{suffix}_{side}'
            bpy.context.collection.objects.link(obj)
            obj.data.materials.clear();obj.data.materials.append(leather if original=='Main' else edge)
            for p in obj.data.polygons:p.material_index=0
            # Shorter adventure boot, preserving foot and ankle exactly.
            bm=geometry(obj)
            for v in bm.verts:
                if v.co.z>0.18:v.co.z=0.18+(v.co.z-0.18)*0.74
            save_geometry(obj,bm)
            obj['worldgoing_visual_id']='boots_leather_01';new.append(obj)
    replace_objects(objects,old,new)
    for obj in objects:
        if not obj.name.startswith('Boots_'):continue
        bm=geometry(obj)
        # A softly lifted and rounded toe, applied consistently to vamp, cap and sole.
        for v in bm.verts:
            if v.co.z<0.16 and v.co.y<-0.07:
                t=min(1,(-v.co.y-0.07)/0.12)
                v.co.z+=0.006*t*t
            if obj.name.startswith('Boots_Chinese_Leather_01_Main') and 0.13<v.co.z<0.23:
                v.co.y+=0.0025*math.sin((v.co.z-0.13)*math.pi*40)
        if any(s in obj.name for s in ['_Sole_','_Heel_']):
            edges=[e for e in bm.edges if e.is_manifold and e.calc_face_angle()>0.45]
            if edges:bmesh.ops.bevel(bm,geom=edges,offset=0.002,segments=3,affect='EDGES')
        save_geometry(obj,bm)
    # High-tier greaves gain an arched crest and distinct scalloped upper profile.
    gold=next(o for o in objects if o.name=='Weapon_Longsword_01_Guard').data.materials[0]
    for side in ['L','R']:
        src=next(o for o in objects if o.name==f'Boots_Mingguang_01_ShinGuard_{side}')
        bm=geometry(src);zmin=min(v.co.z for v in bm.verts);zmax=max(v.co.z for v in bm.verts)
        center_x=(min(v.co.x for v in bm.verts)+max(v.co.x for v in bm.verts))/2
        width=max(abs(v.co.x-center_x) for v in bm.verts)
        for v in bm.verts:
            t=max(0,(v.co.z-zmin)/(zmax-zmin))
            v.co.z+=0.026*t**4*(1-(abs(v.co.x-center_x)/max(width,0.001))**2)
        save_geometry(src,bm)
        front=min((src.matrix_world@v.co).y for v in src.data.vertices)-0.004
        bm=bmesh.new()
        path=[(center_x+0.018*math.sin(t*math.tau),front,zmin+0.035+t*(zmax-zmin-0.050)) for t in [i/24 for i in range(25)]]
        tube(bm,path,0.0025,8)
        objects.append(rigid(api,arm,f'Boots_Mingguang_01_RaisedScroll_{side}',bm,gold,f'J_Bip_{side}_LowerLeg','boots','boots_mingguang_01'))


def repair_helmets(arm,objects,api,female):
    head=arm.data.bones['J_Bip_C_Head'].head_local
    for prefix in ['Helmet_Iron_01','Helmet_Steel_01']:
        old=next(o for o in objects if o.name==prefix+'_Plume')
        coords=[old.matrix_world@v.co for v in old.data.vertices]
        top=max(v.z for v in coords)-0.006;start_y=min(v.y for v in coords)+0.01
        bm=bmesh.new();rng=random.Random(717 if 'Iron' in prefix else 818)
        for strand in range(42):
            angle=rng.random()*math.tau;spread=rng.uniform(0.004,0.029);length=rng.uniform(0.90,1.15)
            points=[];radii=[]
            for step in range(25):
                t=step/24;s=spread*math.sin(math.pi*t*.8)
                points.append((head.x+math.cos(angle)*s,start_y+0.16*t+math.sin(angle)*s,top+0.025*math.sin(math.pi*t)-0.18*length*t*t))
                radii.append(0.00025+0.0021*(1-t)**0.8)
            tube(bm,points,radii,6)
        mat=api.material(prefix+'_Horsehair',(0.30,0.013,0.021),roughness=0.83)
        new=rigid(api,arm,prefix+'_Plume_New',bm,mat,'J_Bip_C_Head','helmet','helmet_iron_01' if 'Iron' in prefix else 'helmet_steel_01')
        name=old.name;replace_objects(objects,[old],[new]);new.name=name
        # Lamellar rear guard follows a curved neck envelope, narrowing below ears.
        old=next(o for o in objects if o.name==prefix+'_Aventail')
        bm=geometry(old);bottom=min(v.co.z for v in bm.verts);upper=max(v.co.z for v in bm.verts)
        for v in bm.verts:
            t=max(0,min(1,(upper-v.co.z)/(upper-bottom)))
            v.co.x=head.x+(v.co.x-head.x)*(1-0.17*t)
            if v.co.y>head.y:v.co.y=head.y+(v.co.y-head.y)*(1-0.18*t)
        edges=[e for e in bm.edges if e.is_manifold and e.calc_face_angle()>0.5]
        if edges:bmesh.ops.bevel(bm,geom=edges,offset=0.0015,segments=2,affect='EDGES')
        save_geometry(old,bm)
    # Steel helmet retains its own cords; a raised sagittal rib differentiates it.
    dome=next(o for o in objects if o.name=='Helmet_Steel_01_Dome')
    pts=[dome.matrix_world@v.co for v in dome.data.vertices];top=max(p.z for p in pts)
    bm=bmesh.new();path=[]
    for i in range(25):
        a=-1.05+2.10*i/24
        path.append((head.x,head.y+0.125*math.sin(a),top-0.12+0.126*math.cos(a)))
    tube(bm,path,0.0045,8)
    gold=next(o for o in objects if o.name=='Weapon_Longsword_01_Guard').data.materials[0]
    objects.append(rigid(api,arm,'Helmet_Steel_01_CrownRib',bm,gold,'J_Bip_C_Head','helmet','helmet_steel_01'))
    # Soften leather rear projections, not the fitted skull cap or face opening.
    for obj in objects:
        if not obj.name.startswith('Helmet_Leather_01_'):continue
        bm=geometry(obj)
        for v in bm.verts:
            if v.co.y>head.y+0.05 and v.co.z<head.z+0.15:
                t=min(1,(v.co.y-head.y-0.05)/0.12)
                v.co.z-=0.014*t;v.co.y-=0.008*t
        save_geometry(obj,bm)
    # Rebuild the white horsehair at full curve sampling; preserve named morph
    # channels and every existing action by transferring the original key deltas.
    plume=next(o for o in objects if o.name=='Helmet_Mingguang_01_WhitePlume_Fittings')
    from mathutils.kdtree import KDTree
    coords=[v.co.copy() for v in plume.data.vertices];tree=KDTree(len(coords))
    for i,p in enumerate(coords):tree.insert(p,i)
    tree.balance()
    keys=plume.data.shape_keys
    deltas={key.name:[p.co-coords[i] for i,p in enumerate(key.data)] for key in keys.key_blocks if key.name!='Basis'}
    tracks=[(tr.name,tr.mute,[(s.frame_start,s.action) for s in tr.strips]) for tr in keys.animation_data.nla_tracks]
    top=max(p.z for p in coords);root_y=min(p.y for p in coords)+0.005
    bm=bmesh.new();rng=random.Random(807)
    for strand in range(64):
        angle=rng.random()*math.tau;spread=rng.uniform(0.004,0.033);length=rng.uniform(0.86,1.12)
        path=[];radii=[]
        for step in range(33):
            t=step/32;s=spread*math.sin(math.pi*t*.8)
            path.append((head.x+math.cos(angle)*s,root_y+0.18*t+math.sin(angle)*s,top-0.075+0.11*math.sin(math.pi*t)-0.29*length*t*t))
            radii.append(0.0002+0.0016*(1-t)**0.7)
        first=len(bm.faces);tube(bm,path,radii,6)
        bm.faces.ensure_lookup_table()
        for f in list(bm.faces)[first:]:f.material_index=strand%len(plume.data.materials)
    plume.shape_key_clear();save_geometry(plume,bm);plume.shape_key_add(name='Basis')
    nearest=[tree.find(v.co)[1] for v in plume.data.vertices]
    for name,delta in deltas.items():
        key=plume.shape_key_add(name=name);key.slider_min=-1
        for i,p in enumerate(key.data):p.co+=delta[nearest[i]]
    keys=plume.data.shape_keys;keys.animation_data_create()
    for name,mute,strips in tracks:
        tr=keys.animation_data.nla_tracks.new();tr.name=name;tr.mute=mute
        for start,action in strips:tr.strips.new(action.name,int(start),action)
    for p in plume.data.polygons:p.use_smooth=True
    plume.vertex_groups.clear()
    plume.vertex_groups.new(name='J_Bip_C_Head').add(list(range(len(plume.data.vertices))),1,'REPLACE')
    for i,mat in enumerate(plume.data.materials):
        for node in mat.node_tree.nodes:
            if node.type=='BSDF_PRINCIPLED':
                shade=0.28+0.025*i
                node.inputs['Base Color'].default_value=(shade,shade+0.006,shade+0.012,1)
                node.inputs['Roughness'].default_value=0.83


def repair_armor(arm,objects,api,female):
    body=next(o for o in objects if o.name==('Body_Standard_Female' if female else 'Body_Standard_Male'))
    for prefix in ['Armor_Iron_01','Armor_Mingguang_01']:
        old=next(o for o in objects if o.name==prefix+'_Underlayer_Pants')
        obj=surface_layer(body,old.name+'_New',old.data.materials[0],arm,'armor',prefix.lower(),0.30,0.975 if female else 1.06,0.010)
        name=old.name;replace_objects(objects,[old],[obj]);obj.name=name
    for obj in objects:
        name=obj.name
        if name.startswith('Armor_Iron_01_') and ('Cuirass' in name or 'Chest' in name or 'BackMotif' in name):
            bm=geometry(obj);center=1.18 if female else 1.30
            for v in bm.verts:
                x=v.co.x;z=v.co.z
                waist=max(0,min(1,(center-z)/0.23))
                v.co.x*=1-0.09*waist
                v.co.y+=(1 if v.co.y<0 else -1)*0.022*(abs(x)/0.19)**2
                if abs(x)>0.12 and z>center+0.08:v.co.z-=0.020*((abs(x)-0.12)/0.07)
            save_geometry(obj,bm)
        if name.startswith('Armor_Iron_01_Tasset'):
            # Curve each panel around the thigh, keep the existing skin transitions.
            bm=geometry(obj)
            for v in bm.verts:
                if abs(v.co.y)>0.08:
                    v.co.y-=(1 if v.co.y>0 else -1)*0.018*(abs(v.co.x)/0.19)**2
            save_geometry(obj,bm)
        if name.startswith('Armor_Mingguang_01_Back_') and any(k in name for k in ['Mirrors','Frames','Relief']):
            # Keep the established twin back motifs but make them subordinate to
            # the front chest mirrors instead of a second equally-sized breastplate.
            bm=geometry(obj)
            mid=sum((v.co for v in bm.verts),Vector())/len(bm.verts)
            for v in bm.verts:
                v.co.x=mid.x+(v.co.x-mid.x)*0.72
                v.co.z=mid.z+(v.co.z-mid.z)*0.72
            save_geometry(obj,bm)
    # Old light-armor hip panels were cut by face centres; replace with clean cuts.
    for side in ['L','R']:
        name='Armor_Light_Leather_01_Tasset_'+side;old=next(o for o in objects if o.name==name)
        obj=surface_layer(body,name+'_New',old.data.materials[0],arm,'armor','armor_light_leather_01',0.89 if female else 0.955,0.968 if female else 1.036,0.014,xmin=0.06 if side=='L' else None,xmax=-0.06 if side=='R' else None)
        replace_objects(objects,[old],[obj]);obj.name=name
    from mathutils.bvhtree import BVHTree
    bm_body=geometry(body);surface=BVHTree.FromBMesh(bm_body)
    # Rebuild the diagonal strap as one skin-weighted ribbon. Projecting both
    # sides of the old solid onto one plane made coincident, flickering faces.
    for suffix in ['CrossStrap','FrontSeam']:
        name='Armor_Light_Leather_01_'+suffix;old=next(o for o in objects if o.name==name)
        bottom,top=(.99,1.328) if female else (1.08,1.425)
        part=surface_layer(body,name+'_New',old.data.materials[0],arm,'armor','armor_light_leather_01',bottom,top,.019)
        bm=geometry(part)
        slope=.23/(top-bottom) if suffix=='CrossStrap' else 0
        center=-.105 if suffix=='CrossStrap' else 0
        half=.017 if suffix=='CrossStrap' else .002
        for offset,inner in [(-half,True),(half,False)]:
            bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],plane_co=(center+offset,0,top),plane_no=(1,0,slope),clear_inner=inner,clear_outer=not inner,dist=.000001)
        bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],plane_co=(0,-.025,0),plane_no=(0,1,0),clear_outer=True,dist=.000001)
        bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context='VERTS')
        save_geometry(part,bm);replace_objects(objects,[old],[part]);part.name=name
    for obj in objects:
        name=obj.name
        if not name.startswith('Armor_Light_Leather_01_'):continue
        if any(s in name for s in ['StrapBuckle','BeltBuckle']):
            bm=geometry(obj)
            center=sum((v.co for v in bm.verts),Vector())/len(bm.verts)
            if 'StrapBuckle' in name:
                target_x=-.105+.23*(top-center.z)/(top-bottom)
                for v in bm.verts:v.co.x+=target_x-center.x
                center.x=target_x
            hit=surface.ray_cast(Vector((center.x,-1,center.z)),Vector((0,1,0)))
            if hit[0]:
                for v in bm.verts:v.co.y+=hit[0].y-center.y-0.026
            save_geometry(obj,bm)
        if female and 'Pauldron' in name:
            side='L' if name.endswith('_L') else 'R';sign=1 if side=='L' else -1
            anchor=arm.data.bones[f'J_Bip_{side}_UpperArm'].head_local
            bm=geometry(obj)
            for v in bm.verts:
                v.co.x=anchor.x+(v.co.x-anchor.x)*2.3+sign*0.015
                v.co.y=anchor.y+(v.co.y-anchor.y)*1.2
                v.co.z+=0.030
            save_geometry(obj,bm)
        if 'Pouch_' in name:
            sign=1 if name.endswith('_L') else -1;bm=geometry(obj)
            center=sum((v.co for v in bm.verts),Vector())/len(bm.verts)
            hit=surface.ray_cast(Vector((sign,center.y,center.z)),Vector((-sign,0,0)))
            if hit[0]:
                for v in bm.verts:v.co.x+=hit[0].x-center.x+sign*0.017
            edges=[e for e in bm.edges if e.is_manifold and e.calc_face_angle()>0.5]
            if edges:bmesh.ops.bevel(bm,geom=edges,offset=0.003,segments=3,affect='EDGES')
            save_geometry(obj,bm)
    bm_body.free()


def repair_face_variants(objects):
    neutral=next(o for o in objects if o.name=='Face_Standard_01')
    joy=next(o for o in objects if o.name=='Face_Standard_02')
    smile=next(o for o in objects if o.name=='Face_Standard_04')
    assert len(neutral.data.vertices)==len(joy.data.vertices)==len(smile.data.vertices)
    # Baked variants share source-local vertex order, not object transforms.
    # Female Face 01 retains a 180-degree object transform; siblings use identity.
    joy_local=[v.co.copy() for v in joy.data.vertices]
    assert max((v.co-joy_local[i]).length for i,v in enumerate(neutral.data.vertices))<.08
    for i,base in enumerate(neutral.data.vertices):
        p=base.co
        joy.data.vertices[i].co=p.lerp(joy_local[i],0.40)
        smile_p=smile.data.vertices[i].co.copy()
        smile.data.vertices[i].co=p+(smile_p-p)*0.68+(joy_local[i]-p)*0.10
    joy.data.update();smile.data.update()


def repair_riding_legs(arm,api,female):
    """Bake leg clearance around the existing horse, without changing leg lengths."""
    for action in [a for a in bpy.data.actions if a.name in ['ride_idle','ride_walk','ride_run','ride_slash','ride_thrust','ride_attack']]:
        reset_rig(arm);arm.animation_data.action=action
        for frame in range(int(action.frame_range[0]),int(action.frame_range[1])+1):
            bpy.context.scene.frame_set(frame);bpy.context.view_layer.update()
            hip=arm.pose.bones['J_Bip_C_Hips'].head.copy()
            for side,sign in [('L',1),('R',-1)]:
                upper=arm.pose.bones[f'J_Bip_{side}_UpperLeg'];lower=arm.pose.bones[f'J_Bip_{side}_LowerLeg'];foot=arm.pose.bones[f'J_Bip_{side}_Foot']
                start=upper.head.copy();target=hip+Vector((sign*0.36,-0.095,-0.59 if female else -0.68))
                delta=target-start;distance=delta.length;a=upper.length;b=lower.length
                assert distance<a+b,(action.name,side,'leg reach',distance,a+b)
                direction=delta.normalized();bend=Vector((sign*0.85,-1,0.1));bend=(bend-direction*bend.dot(direction)).normalized()
                along=(a*a-b*b+distance*distance)/(2*distance)
                knee=start+direction*along+bend*math.sqrt(max(0,a*a-along*along))
                for pb,p,q in [(upper,start,knee),(lower,knee,target)]:
                    rest=pb.bone.matrix_local.to_quaternion()
                    rotation=(rest@Vector((0,1,0))).rotation_difference((q-p).normalized())@rest
                    pb.matrix=Matrix.LocRotScale(p,rotation,None);bpy.context.view_layer.update()
                foot.matrix=Matrix.LocRotScale(target,foot.bone.matrix_local.to_quaternion(),None)
                bpy.context.view_layer.update()
                for pb in [upper,lower,foot]:
                    pb.rotation_mode='QUATERNION';pb.keyframe_insert('rotation_quaternion',frame=frame,group=pb.name);pb.keyframe_insert('location',frame=frame,group=pb.name)
    reset_rig(arm)


def repair_spear_and_grips(arm,objects,api):
    shaft=next(o for o in objects if o.name=='Weapon_Spear_01_Shaft')
    pts=[shaft.matrix_world@v.co for v in shaft.data.vertices]
    low=Vector(tuple(min(p[i] for p in pts) for i in range(3)));high=Vector(tuple(max(p[i] for p in pts) for i in range(3)))
    axis=max(range(3),key=lambda i:high[i]-low[i]);start=(low+high)*0.5;start[axis]=low[axis]
    end=start.copy();end[axis]=high[axis]
    action=bpy.data.actions['attack_spear'];reset_rig(arm);arm.animation_data.action=action
    rrest=arm.data.bones['J_Bip_R_Hand'].matrix_local;lrest=arm.data.bones['J_Bip_L_Hand'].matrix_local
    for frame in range(int(action.frame_range[0]),int(action.frame_range[1])+1):
        bpy.context.scene.frame_set(frame);bpy.context.view_layer.update()
        transform=arm.pose.bones['J_Bip_R_Hand'].matrix@rrest.inverted()
        a=transform@start;b=transform@end;direction=(b-a).normalized()
        shoulder=arm.pose.bones['J_Bip_L_UpperArm'].head.copy()
        basis=transform.to_3x3()@lrest.to_3x3()
        wrist_offset=basis@Vector((0,0.045,-0.015))
        along=max(0.12,min((b-a).length-0.12,(shoulder-(a-wrist_offset)).dot(direction)))
        target=a+direction*along
        right_palm=arm.pose.bones['J_Bip_R_Hand'].matrix@Vector((0,0.045,-0.015))
        if (target-right_palm).length<0.16:
            options=[target+direction*0.18,target-direction*0.18]
            target=min(options,key=lambda p:(p-shoulder).length)
        reach=arm.pose.bones['J_Bip_L_UpperArm'].length+arm.pose.bones['J_Bip_L_LowerArm'].length
        wrist=target-wrist_offset
        if (wrist-shoulder).length>reach-0.01:
            shift=(shoulder-wrist).normalized()*((wrist-shoulder).length-reach+0.012)
            assert shift.length<0.10,('spear stance correction',frame,shift.length)
            point_arm(arm,'R',right_palm+shift,arm.pose.bones['J_Bip_R_Hand'].matrix.to_3x3())
            target+=shift
        point_arm(arm,'L',target,basis)
        api.apply_left_hand_grip(arm)
        for pb in arm.pose.bones:
            if pb.name in [f'J_Bip_{s}_{b}' for s in ['L','R'] for b in ['UpperArm','LowerArm','Hand']] or pb.name.startswith('J_Bip_L_') and any(s in pb.name for s in ['Thumb','Index','Middle','Ring','Little']):
                pb.rotation_mode='QUATERNION';pb.keyframe_insert('rotation_quaternion',frame=frame,group=pb.name);pb.keyframe_insert('location',frame=frame,group=pb.name)
    reset_rig(arm)


def repair_grip_wraps(arm,objects,api):
    """Fit wrap in the grip's principal axes, including rotated bow grips."""
    thread=api.material('Audit_Weapon_Grip_Wrap',(0.065,0.035,0.02),roughness=0.84)
    targets=[o for o in objects if o.name.startswith('Weapon_') and o.name.endswith(('_Grip','_Blade'))]
    for obj in targets:
        if obj.name.startswith('Weapon_') and obj.name.endswith('_Blade'):
            for p in obj.data.polygons:p.use_smooth=False
        if not obj.name.startswith('Weapon_') or not obj.name.endswith('_Grip'):continue
        if obj.name.startswith('Weapon_Bow_01_'):
            # The old grip used the whole-bow bend over 12 cm, creating two spikes.
            replace_objects(objects,[o for o in objects if o.name==obj.name+'_Wrap'],[])
            if not obj.get('worldgoing_bow_grip_v3'):
                rest=arm.data.bones['J_Bip_L_Hand'].matrix_local;bm=bmesh.new()
                path=[rest@Vector((x,.09*math.cos(x/1.16*math.pi)-.02,0)) for x in np.linspace(-.058,.058,13)]
                tube(bm,path,.014,10);save_geometry(obj,bm)
                for group in list(obj.vertex_groups):obj.vertex_groups.remove(group)
                obj.vertex_groups.new(name='J_Bip_L_Hand').add(list(range(len(obj.data.vertices))),1,'REPLACE')
                obj['worldgoing_bow_grip_v3']=True
            continue
        if obj.get('worldgoing_grip_wrap_v2'):continue
        pts=np.array([tuple(obj.matrix_world@v.co) for v in obj.data.vertices]);center=pts.mean(axis=0)
        _,axes=np.linalg.eigh(np.cov((pts-center).T));local=(pts-center)@axes
        low=local.min(axis=0);high=local.max(axis=0);middle=(low+high)*.5
        bm=bmesh.new();path=[]
        for i in range(81):
            t=i/80;p=middle.copy();p[2]=low[2]+0.006+(high[2]-low[2]-0.012)*t
            p[0]+=(high[0]-low[0])*.49*math.cos(t*math.tau*6);p[1]+=(high[1]-low[1])*.49*math.sin(t*math.tau*6)
            path.append(Vector(tuple(center+axes@p)))
        tube(bm,path,0.001,6)
        bone=next(g.name for g in obj.vertex_groups if g.name in arm.data.bones)
        name=obj.name+'_Wrap';old=[o for o in objects if o.name==name]
        wrap=rigid(api,arm,name+'_New',bm,thread,bone,'weapon',obj.get('worldgoing_visual_id',''))
        replace_objects(objects,old,[wrap]);wrap.name=name;obj['worldgoing_grip_wrap_v2']=True


def bake_travel_cape(arm,objects):
    """Broad pose-corrective back clearance; no per-vertex collision spikes."""
    obj=next(o for o in objects if o.name=='Cape_Travel_01_Main')
    reset_rig(arm)
    visibility={part:part.hide_viewport for part in bpy.context.scene.objects if part.type=='MESH'}
    for part in visibility:part.hide_viewport=True
    world=np.array(obj.matrix_world);world_inv=np.linalg.inv(world)
    arm_world=arm.matrix_world;arm_inv=arm_world.inverted()
    base=np.array([(*v.co,1) for v in obj.data.vertices])
    neutral=(base@world.T)[:,:3];n=len(base)
    t=np.clip((neutral[:,2].max()-neutral[:,2])/.80,0,1)
    smooth=lambda x:(lambda a:a*a*(3-2*a))(np.clip(x,0,1))
    factor=smooth((t-.16)/.36)
    weights={g.name:np.zeros(n) for g in obj.vertex_groups if g.name in arm.data.bones}
    for v in obj.data.vertices:
        for g in v.groups:
            name=obj.vertex_groups[g.group].name
            if name in weights:weights[name][v.index]=g.weight
    clips=[tr.name for tr in arm.animation_data.nla_tracks if bpy.data.actions.get(tr.name) and tr.name!='T-Pose' and '|' not in tr.name]
    obj.shape_key_add(name='Basis');keys=obj.data.shape_keys;records=[]
    for clip in clips:
        arm.animation_data.action=bpy.data.actions[clip]
        start,end=arm.animation_data.action.frame_range
        frames=np.linspace(start,end,25);blocks=[]
        for index,frame in enumerate(frames):
            bpy.context.scene.frame_set(int(frame),subframe=frame-int(frame));bpy.context.view_layer.update()
            skin=np.zeros((n,4,4))
            for bone,w in weights.items():
                matrix=arm_world@arm.pose.bones[bone].matrix@arm.data.bones[bone].matrix_local.inverted()@arm_inv
                skin+=w[:,None,None]*np.array(matrix)
            posed=np.einsum('nij,nj->ni',skin,np.column_stack((neutral,np.ones(n))))[:,:3]
            chest=arm_world@arm.pose.bones['J_Bip_C_UpperChest'].matrix@arm.data.bones['J_Bip_C_UpperChest'].matrix_local.inverted()@arm_inv
            yaw=math.atan2(chest[1][0],chest[0][0]);c,s=math.cos(yaw),math.sin(yaw)
            rot=np.array([[c,-s,0],[s,c,0],[0,0,1]])
            neck=np.array(arm_world@arm.pose.bones['J_Bip_C_Neck'].head)
            local=(posed-neck)@rot
            envelope=local[:,1].copy()
            for side in ['L','R']:
                for bone in ['UpperLeg','LowerLeg','Foot','ToeBase']:
                    pb=arm.pose.bones['J_Bip_'+side+'_'+bone]
                    for fraction in [0,.5,1]:
                        joint=(np.array(arm_world@pb.head.lerp(pb.tail,fraction))-neck)@rot
                        falloff=np.exp(-((local[:,2]-joint[2])/.25)**4)
                        envelope=np.maximum(envelope,(joint[1]+.20)*falloff)
            local[:,1]+=np.maximum(0,envelope-local[:,1])*factor
            local[:,1]+=.014*math.sin(math.tau*index/24)*t*t
            if clip.startswith('ride_'):
                local[:,1]+=.14*smooth(t/.75);local[:,2]+=.18*smooth((t-.3)/.7)
            desired=local@rot.T+neck
            desired[:,2]=np.maximum(desired[:,2],.02)
            corrected=np.einsum('nij,nj->ni',np.linalg.inv(skin),np.column_stack((desired,np.ones(n))))@world_inv.T
            key=obj.shape_key_add(name=f'{clip}_{index:02d}')
            key.data.foreach_set('co',corrected[:,:3].astype('float32').ravel());blocks.append(key)
        records.append((clip,frames,blocks))
    keys.animation_data_create()
    for clip,frames,blocks in records:
        act=bpy.data.actions.new(obj.name+'_'+clip)
        for key in list(keys.key_blocks)[1:]:
            curve=act.fcurves.new(data_path=key.path_from_id('value'))
            if key in blocks:
                i=blocks.index(key);curve.keyframe_points.add(len(frames))
                for j,frame in enumerate(frames):curve.keyframe_points[j].co=(frame,float(i==j))
            else:
                curve.keyframe_points.add(1);curve.keyframe_points[0].co=(frames[0],0)
            for point in curve.keyframe_points:point.interpolation='LINEAR'
        track=keys.animation_data.nla_tracks.new();track.name=clip
        track.strips.new(clip,int(frames[0]),act);track.mute=True
    keys.animation_data.action=None
    reset_rig(arm)
    for part,hidden in visibility.items():part.hide_viewport=hidden


def apply_repairs(arm,objects,api,female=False):
    if arm.get('worldgoing_audit_repair_v1'):return objects
    mutes={tr.name:tr.mute for tr in arm.animation_data.nla_tracks}
    repair_weapons(arm,objects,api,female)
    repair_clothing(arm,objects,api,female)
    repair_hair(arm,objects,api,female)
    repair_travel_cape(arm,objects,api,female)
    repair_boots(arm,objects,api,female)
    repair_helmets(arm,objects,api,female)
    repair_armor(arm,objects,api,female)
    repair_face_variants(objects)
    repair_riding_legs(arm,api,female)
    repair_spear_and_grips(arm,objects,api)
    bake_travel_cape(arm,objects)
    finish_surfaces(objects,api)
    for obj in objects:
        bone_groups={g.index for g in obj.vertex_groups if g.name in arm.data.bones}
        unbound=[v.index for v in obj.data.vertices if not any(g.group in bone_groups and g.weight>0.000001 for g in v.groups)]
        assert not unbound,('unbound repaired mesh',obj.name,len(unbound))
    for tr in arm.animation_data.nla_tracks:tr.mute=mutes.get(tr.name,False)
    arm.animation_data.action=None
    arm['worldgoing_audit_repair_v1']=True
    return objects


def retime_hammer(arm,objects):
    """Keep the tested swing path; give the heavier head a deliberate cadence."""
    if arm.get('worldgoing_hammer_timing_v1'):return
    action=bpy.data.actions['attack_hammer'];start,end=action.frame_range
    old=np.array([0,.12,.25,.34,.42,.65,1.0])
    new=np.array([0,.12,.36,.405,.52,.82,1.2])
    def time(frame):return start+(end-start)*np.interp((frame-start)/(end-start),old,new)
    actions={action};strips=[]
    for owner in [arm,*[o.data.shape_keys for o in objects if o.data.shape_keys]]:
        data=owner.animation_data
        if not data:continue
        for track in data.nla_tracks:
            if track.name!='attack_hammer':continue
            for strip in track.strips:
                actions.add(strip.action);strips.append(strip)
    for act in actions:
        for curve in act.fcurves:
            for key in curve.keyframe_points:
                key.co.x=time(key.co.x)
                key.handle_left.x=time(key.handle_left.x)
                key.handle_right.x=time(key.handle_right.x)
            curve.update()
    for strip in strips:
        strip.action_frame_end=time(end);strip.frame_end=time(end)
    arm['worldgoing_hammer_timing_v1']=True


def finish_surfaces(objects,api):
    """Remove inherited skin-only modifiers/normals from newly cut garment meshes."""
    arm=next(o for o in bpy.data.objects if o.type=='ARMATURE' and o.name=='Armature')
    repair_grip_wraps(arm,objects,api)
    retime_hammer(arm,objects)
    for obj in list(objects):
        if obj.name.startswith(('Outfit_Underlayer_01','Boots_Leather_01','Weapon_Crossbow_01')) and obj.name.endswith('.001'):
            target=obj.name[:-4]
            assert target not in bpy.data.objects,('duplicate fitted garment',target)
            obj.name=target
        fitted=obj.name.startswith(('Armor_Light_Leather_01','Outfit_Underlayer_01')) or '_Underlayer_' in obj.name
        if fitted:
            for modifier in list(obj.modifiers):
                if modifier.type=='NODES' and 'MToon Outline' in modifier.name:obj.modifiers.remove(modifier)
            if obj.data.has_custom_normals:
                obj.data.normals_split_custom_set([(0,0,0)]*len(obj.data.loops))
            for polygon in obj.data.polygons:polygon.use_smooth=True
        if obj.name=='Armor_Light_Leather_01_Vest' and not obj.get('worldgoing_vest_neckline_v2'):
            female=any(o.name=='Body_Standard_Female' for o in objects)
            body=next(o for o in objects if o.name==('Body_Standard_Female' if female else 'Body_Standard_Male'))
            half=.154 if female else .184
            part=surface_layer(body,obj.name+'_New',obj.data.materials[0],body.parent,'armor','armor_light_leather_01',.975 if female else 1.064,1.358 if female else 1.469,.008,xmin=-half,xmax=half)
            name=obj.name;replace_objects(objects,[obj],[part]);part.name=name;part['worldgoing_vest_neckline_v2']=True
            continue
        if obj.name=='Armor_Light_Leather_01_Collar' and not obj.get('worldgoing_collar_clearance_v5'):
            female=any(o.name=='Body_Standard_Female' for o in objects)
            body=next(o for o in objects if o.name==('Body_Standard_Female' if female else 'Body_Standard_Male'))
            from mathutils.bvhtree import BVHTree
            source=geometry(body);surface=BVHTree.FromBMesh(source);bm=bmesh.new();layers=[]
            low,high=(1.333,1.372) if female else (1.439,1.480)
            # Sample the actual neck section, then join regular rings. This
            # avoids long mitres from solidifying an irregular cut skin mesh.
            for thickness in [0,.003]:
                rows=[]
                for row in range(5):
                    ring=[]
                    for column in range(48):
                        angle=math.tau*column/48;direction=Vector((math.sin(angle),math.cos(angle),0))
                        z=low+(high-low)*row/4+(.021 if female else .026)*math.sin(angle)**2*(1-row/4)
                        center=Vector((0,.012 if female else .003,z));hit=surface.ray_cast(center,direction)
                        radius=(hit[0]-center).length if hit[0] else .075
                        radius=max(.025,min(.108 if female else .120,radius))+.012+thickness
                        ring.append(bm.verts.new(center+direction*radius))
                    rows.append(ring)
                layers.append(rows)
            for layer,rows in enumerate(layers):
                for r in range(4):
                    for c in range(48):
                        face=(rows[r][c],rows[r][(c+1)%48],rows[r+1][(c+1)%48],rows[r+1][c])
                        bm.faces.new(face if layer else face[::-1]).smooth=True
            for r in [0,4]:
                for c in range(48):bm.faces.new((layers[0][r][c],layers[0][r][(c+1)%48],layers[1][r][(c+1)%48],layers[1][r][c]))
            source.free()
            part=rigid(api,body.parent,obj.name+'_New',bm,obj.data.materials[0],'J_Bip_C_UpperChest','armor','armor_light_leather_01')
            name=obj.name;replace_objects(objects,[obj],[part]);part.name=name;part['worldgoing_collar_clearance_v5']=True
            continue
        if obj.name=='Armor_Light_Leather_01_CrossStrap':
            obj.data.materials.clear();obj.data.materials.append(api.material('Audit_Dark_Leather_Strap',(0.075,0.032,0.013),roughness=.84))
        if obj.get('worldgoing_component_slot')=='hair':
            for material in obj.data.materials:
                if not material or not material.use_nodes:continue
                for node in material.node_tree.nodes:
                    if node.type!='BSDF_PRINCIPLED':continue
                    for name,value in [('Roughness',.78),('Metallic',0),('Specular IOR Level',.18)]:
                        for link in list(node.inputs[name].links):material.node_tree.links.remove(link)
                        node.inputs[name].default_value=value
