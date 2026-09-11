"""Polish the existing horse and tack with the original horse rig intact."""
import math
import bpy,bmesh
from mathutils import Vector
from repair_character_audit import geometry,save_geometry,tube,box,reset_rig


def apply_repairs(arm,objects,api):
    if arm.get('worldgoing_audit_repair_v1'):return
    reset_rig(arm)
    # The same saddle surface, but lower, rounded arches and curved flap edges.
    for name in ['Mount_Saddle_01_Seat','Mount_Saddle_01_Pad']:
        obj=bpy.data.objects[name];bm=geometry(obj)
        for v in bm.verts:
            if name.endswith('Seat') and v.co.z>1.54:v.co.z=1.54+(v.co.z-1.54)*0.48
            if abs(v.co.x)>0.25:
                t=min(1,(abs(v.co.x)-0.25)/0.10)
                v.co.y*=1-0.13*t
                v.co.z+=0.010*t*abs(v.co.y)/0.3
                v.co.x+=(1 if v.co.x>0 else -1)*0.035*t
        save_geometry(obj,bm)
        sub=obj.modifiers.new('Audit_SoftSaddle','SUBSURF');sub.levels=2;sub.render_levels=2
        bpy.context.view_layer.objects.active=obj
        # Apply only this authored modelling modifier, never bake the armature.
        bpy.ops.object.modifier_move_up(modifier=sub.name)
        bpy.ops.object.modifier_move_up(modifier=sub.name)
        bpy.ops.object.modifier_apply(modifier=sub.name)
    # Flaps sit on a deforming flank, not entirely on the rigid seat bone.
    # Match the nearest horse surface weights so gait doesn't poke through them.
    from mathutils.bvhtree import BVHTree
    from mathutils.kdtree import KDTree
    body=bpy.data.objects['Horse_Body_01'];body_bm=geometry(body)
    surface=BVHTree.FromBMesh(body_bm);tree=KDTree(len(body.data.vertices))
    for v in body.data.vertices:tree.insert(body.matrix_world@v.co,v.index)
    tree.balance()
    for name in ['Mount_Saddle_01_Seat','Mount_Saddle_01_Pad']:
        obj=bpy.data.objects[name];bm=geometry(obj)
        for v in bm.verts:
            if abs(v.co.x)>0.16 and v.co.z<1.51:
                sign=1 if v.co.x>0 else -1
                hit=surface.ray_cast(Vector((sign,v.co.y,v.co.z)),Vector((-sign,0,0)))
                if hit[0]:v.co.x=hit[0].x+sign*(0.026 if name.endswith('Pad') else 0.045)
        save_geometry(obj,bm);obj.vertex_groups.clear()
        groups={g.index:obj.vertex_groups.new(name=g.name) for g in body.vertex_groups}
        seat_group=obj.vertex_groups.get('waste')
        for v in obj.data.vertices:
            if abs(v.co.x)<0.14 or v.co.z>1.52:
                seat_group.add([v.index],1,'REPLACE');continue
            nearest=tree.find(v.co)[1]
            weights=sorted(body.data.vertices[nearest].groups,key=lambda g:g.weight,reverse=True)[:4]
            total=sum(g.weight for g in weights)
            for g in weights:
                if g.weight>0:groups[g.group].add([v.index],g.weight/total,'REPLACE')
    body_bm.free()
    # Actual open D-shaped stirrups. Leather straps are separate material faces.
    for side,sign in [('L',1),('R',-1)]:
        obj=bpy.data.objects['Mount_Stirrups_01_'+side];bm=bmesh.new()
        x=sign*0.345
        points=[]
        for i in range(33):
            a=math.pi*i/32
            points.append((x,-0.03+0.066*math.cos(a),0.865+0.090*math.sin(a)))
        tube(bm,points,0.006,8)
        box(bm,(x,-0.03,0.863),(0.07,0.142,0.012),0.003)
        count=len(bm.faces)
        tube(bm,[(sign*0.30,-0.03,1.39),(sign*0.335,-0.03,1.22),(x,-0.03,0.956)],0.007,8)
        for f in list(bm.faces)[count:]:f.material_index=1
        for mod in list(obj.modifiers):
            if mod.type!='ARMATURE':obj.modifiers.remove(mod)
        save_geometry(obj,bm)
        obj.data.materials.append(bpy.data.objects['Mount_Saddle_01_Seat'].data.materials[0])
        obj.vertex_groups.clear();api.add_armature_skin(obj,arm,'waste')
        for mod in list(obj.modifiers)[1:]:
            if mod.type=='ARMATURE':obj.modifiers.remove(mod)
        obj.shape_key_add(name='Basis')
        for axis,name in enumerate(['Side','Forward','Lift']):
            key=obj.shape_key_add(name=name);key.slider_min=-1;key.slider_max=1
            for v,p in zip(obj.data.vertices,key.data):
                p.co[axis]+=max(0,min(1,(1.39-v.co.z)/0.435))
    # Round reins stay visible edge-on. Native head/neck/seat weights are blended.
    obj=bpy.data.objects['Mount_Reins_01'];bm=bmesh.new()
    for sign in [-1,1]:
        points=[]
        for i in range(33):
            t=i/32
            points.append((sign*(0.10+0.04*math.sin(math.pi*t)),-1.30+1.05*t,1.535+0.205*t-0.035*math.sin(math.pi*t)))
        tube(bm,points,0.005,8)
    for mod in list(obj.modifiers):
        if mod.type!='ARMATURE':obj.modifiers.remove(mod)
    save_geometry(obj,bm);obj.vertex_groups.clear()
    groups={name:obj.vertex_groups.new(name=name) for name in ['head','neck','waste']}
    for v in obj.data.vertices:
        t=max(0,min(1,(v.co.y+1.30)/1.05))
        head=max(0,1-t*3);waist=max(0,(t-0.45)/0.55);neck=1-head-waist
        for name,w in [('head',head),('neck',neck),('waste',waist)]:
            if w>0:groups[name].add([v.index],w,'REPLACE')
    # Hoof shells come directly from the current horse foot surfaces and weights.
    body=bpy.data.objects['Horse_Body_01']
    hoofmat=api.material('Audit_Horse_Hoof',(0.055,0.045,0.035),roughness=0.58)
    obj=body.copy();obj.data=body.data.copy();obj.name='Horse_Hooves_01'
    bpy.context.collection.objects.link(obj)
    bm=geometry(obj)
    bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],plane_co=(0,0,0.10),plane_no=(0,0,1),clear_outer=True,dist=0.000001)
    bm.normal_update()
    for v in bm.verts:v.co+=v.normal*0.0012
    save_geometry(obj,bm)
    obj.data.materials.clear();obj.data.materials.append(hoofmat)
    for p in obj.data.polygons:p.material_index=0;p.use_smooth=True
    api.component_props(obj,'mount_hoof','hoof_standard');objects.append(obj)
    # Eyes already exist; preserve their shape and give nostrils a small inset rim.
    bm=bmesh.new()
    for sign in [-1,1]:
        out=bmesh.ops.create_uvsphere(bm,u_segments=16,v_segments=8,radius=1)
        for v in out['verts']:
            v.co=Vector((sign*(0.083+v.co.x*0.004),-1.356+v.co.y*0.022,1.548+v.co.z*0.011))
    mesh=bpy.data.meshes.new('Horse_NostrilsMesh');bm.to_mesh(mesh);bm.free()
    obj=bpy.data.objects.new('Horse_Nostrils_01',mesh);bpy.context.collection.objects.link(obj)
    obj.data.materials.append(hoofmat);obj.parent=arm
    api.add_armature_skin(obj,arm,'head');api.component_props(obj,'mount_detail','nostrils_standard')
    for p in obj.data.polygons:p.use_smooth=True
    objects.append(obj)
    arm['worldgoing_audit_repair_v1']=True
