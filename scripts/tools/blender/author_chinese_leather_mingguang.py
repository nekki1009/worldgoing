"""Explicit art stages for new Chinese leather armor and Mingguang helmet.

Work is saved separately from the live character packs. Gray rebuild is explicit;
export never recreates manually edited geometry.
"""
import argparse
import json
import math
import sys
from pathlib import Path
import bpy
import bmesh
import numpy as np
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).parent))
from build_standard_anime_male_character_pack import create_bone_rigid_component

BASE = ROOT / '.godot-temp/chinese_leather_mingguang_baseline_20260910'
WORK = ROOT / 'assets/characters/human/q35/chinese_leather_mingguang'
QA = ROOT / '.visual_captures/chinese_leather_mingguang'
ARMOR = 'Armor_Chinese_Leather_01_'
HELMET = 'Helmet_Mingguang_01_'


def material(name, color, metallic=0, roughness=.65):
    mat = bpy.data.materials.get('ChineseGear_' + name) or bpy.data.materials.new('ChineseGear_' + name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    return mat


def smooth(t):
    t = max(0, min(1, t))
    return t*t*(3-2*t)


class Fitting:
    def __init__(self, arm, sex):
        self.arm, self.sex = arm, sex
        self.body = bpy.data.objects['Body_Standard_' + sex.title()]
        self.points = [self.body.matrix_world @ v.co for v in self.body.data.vertices]
        self.bvh = BVHTree.FromPolygons(self.points, [tuple(p.vertices) for p in self.body.data.polygons])
        self.kd = KDTree(len(self.points))
        for i, point in enumerate(self.points): self.kd.insert(point, i)
        self.kd.balance()
        self.groups = {g.index:g.name for g in self.body.vertex_groups}
        self.hip = self.bone('J_Bip_C_Hips').z
        self.neck = self.bone('J_Bip_C_Neck').z
        self.shoulder = self.bone('J_Bip_L_UpperArm')
        self.knee = self.bone('J_Bip_L_LowerLeg').z
        levels=np.linspace(self.hip+.025,self.neck-.04,28)
        profiles=[]
        for z in levels:
            ring=[p for p in self.points if abs(p.z-z)<.038 and abs(p.x)<self.shoulder.x+.016]
            profiles.append((max(abs(p.x) for p in ring),min(p.y for p in ring),max(p.y for p in ring)))
        self.levels=levels
        values=np.array(profiles)
        self.profiles=np.array([np.convolve(np.pad(values[:,i],2,mode='edge'),np.ones(5)/5,mode='valid') for i in range(3)]).T

    def bone(self, name):
        return self.arm.matrix_world @ self.arm.data.bones[name].head_local

    def weights(self, point):
        found = self.kd.find_n(point, 4)
        result = {}
        for _, index, distance in found:
            factor = 1 / max(distance, .001)**2
            for group in self.body.data.vertices[index].groups:
                name = self.groups[group.group]
                if name in self.arm.data.bones:
                    result[name] = result.get(name, 0) + factor * group.weight
        result = dict(sorted(result.items(), key=lambda item:-item[1])[:4])
        total = sum(result.values())
        assert total > 0, 'Unweighted fitted armor vertex'
        return {k:v/total for k,v in result.items()}

    def torso(self, a, z, offset=.014):
        # A smooth armor shell follows measured torso envelopes, not irregular
        # intersections of the base body's split skin surfaces.
        rx,front,back=[float(np.interp(z,self.levels,self.profiles[:,i])) for i in range(3)]
        cy=(front+back)/2; ry=(back-front)/2
        c=math.cos(a)
        # Female chest has two lateral peaks; an ellipse fitted only at the
        # centerline cuts through them. A measured broad-front shell clears both.
        front_extra=.012*math.exp(-((z-(self.neck-.15))/.11)**2) if self.sex=='female' else 0
        y=cy-(ry+offset+(front_extra if c>0 else 0))*math.copysign(abs(c)**.58,c)
        return Vector(((rx+offset)*math.sin(a),y,z))


def mesh_part(name, vertices, faces, mat, fit, bone='J_Bip_C_UpperChest', weights=None, uvs=None, thickness=.003):
    data = bpy.data.meshes.new(name+'Surface')
    data.from_pydata(vertices, [], faces); data.update()
    if uvs:
        uv = data.uv_layers.new(name='UVMap')
        for loop in data.loops: uv.data[loop.index].uv = uvs[loop.vertex_index]
    bm = bmesh.new(); bm.from_mesh(data)
    if 'PerforatedAventail' in name:
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
    bpy.data.meshes.remove(data)
    slot = 'armor' if name.startswith(ARMOR) else 'helmet'
    visual_id = 'armor_chinese_leather_01' if slot == 'armor' else 'helmet_mingguang_01'
    obj = create_bone_rigid_component(name,bm,mat,bone,slot,visual_id,fit.arm)
    if not obj.data.uv_layers:
        uv = obj.data.uv_layers.new(name='UVMap')
        coords = np.array([v.co for v in obj.data.vertices]); extents = np.ptp(coords,axis=0)
        axes = np.argsort(extents)[-2:]; lo = coords.min(axis=0)
        for loop in obj.data.loops:
            uv.data[loop.index].uv = [(coords[loop.vertex_index,a]-lo[a])/max(extents[a],1e-6) for a in axes]
    if weights:
        obj.vertex_groups.clear()
        for i, vertex in enumerate(obj.data.vertices):
            for group_name, value in weights(Vector(vertices[i])).items():
                group = obj.vertex_groups.get(group_name) or obj.vertex_groups.new(name=group_name)
                group.add([i], value, 'REPLACE')
    if thickness:
        bpy.context.view_layer.objects.active = obj
        solid = obj.modifiers.new('LeatherOrMetalThickness','SOLIDIFY'); solid.thickness=thickness; solid.offset=0
        bpy.ops.object.modifier_move_up(modifier=solid.name)
        bpy.ops.object.modifier_apply(modifier=solid.name)
    obj['chinese_gear_revision'] = 1
    if 'PerforatedAventail' in name:
        for polygon in obj.data.polygons: polygon.use_smooth=False
    return obj


def surface(name, fn, rows, cols, mat, fit, bone='J_Bip_C_UpperChest', weights=None, thickness=.003):
    points, uvs, faces = [], [], []
    for r in range(rows+1):
        for c in range(cols+1):
            points.append(fn(c/cols,r/rows)); uvs.append((c/cols,1-r/rows))
    for r in range(rows):
        for c in range(cols):
            i=r*(cols+1)+c; faces.append((i,i+1,i+cols+2,i+cols+1))
    obj=mesh_part(name,points,faces,mat,fit,bone,weights,uvs,thickness)
    obj['grid_rows']=rows; obj['grid_cols']=cols
    return obj


def tube(name, path, radii, mat, fit, bone='J_Bip_C_Head', sides=10, flat=1):
    points, faces = [], []
    for i, center in enumerate(path):
        center=Vector(center)
        tangent=(Vector(path[min(i+1,len(path)-1)])-Vector(path[max(0,i-1)])).normalized()
        reference=Vector((1,0,0)) if abs(tangent.x)<.9 else Vector((0,1,0))
        normal=tangent.cross(reference).normalized(); bitangent=tangent.cross(normal).normalized()
        for j in range(sides):
            a=math.tau*j/sides
            points.append(center+radii[i]*(normal*math.cos(a)+bitangent*math.sin(a)*flat))
    for i in range(len(path)-1):
        for j in range(sides):
            n=(j+1)%sides; faces.append((i*sides+j,i*sides+n,(i+1)*sides+n,(i+1)*sides+j))
    faces.extend([tuple(reversed(range(sides))),tuple((len(path)-1)*sides+j for j in range(sides))])
    return mesh_part(name,points,faces,mat,fit,bone,thickness=0)


def armor_gray(fit):
    mat=material('Leather',(.20,.105,.054),roughness=.72)
    edge=material('LeatherEdge',(.30,.155,.071),roughness=.65)
    parts=[]
    def torso(u,v):
        a=math.tau*u
        top=fit.neck-.045-.025*math.sin(a)**2
        z=fit.hip+.045+(top-fit.hip-.045)*v
        return fit.torso(a,z)
    parts.append(surface(ARMOR+'Cuirass',torso,18,64,mat,fit,weights=fit.weights,thickness=.006))
    def yoke(u,v):
        a=math.tau*u
        inner=Vector((.061*math.sin(a),fit.bone('J_Bip_C_Neck').y-.065*math.cos(a),fit.neck-.027))
        z=fit.neck-.085+.060*math.sin(a)**2
        outer=fit.torso(a,z,.016)
        point=inner.lerp(outer,v)+Vector((0,0,.010*math.sin(math.pi*v)))
        hit,normal,_,_=fit.bvh.find_nearest(point)
        return hit+normal*.022 if hit is not None else point
    parts.append(surface(ARMOR+'ShoulderYoke',yoke,8,64,mat,fit,weights=fit.weights,thickness=.005))
    for label, start, end in [('Front',-.90,.90),('Back',math.pi-.86,math.pi+.86)]:
        def panel(u,v,start=start,end=end):
            a=start+(end-start)*u
            top=fit.neck-.070-.045*math.sin(a)**2
            return fit.torso(a,fit.hip+.11+(top-fit.hip-.11)*v,.024)
        parts.append(surface(ARMOR+'ChestPanel_'+label,panel,12,16,mat,fit,weights=fit.weights,thickness=.004))
    def collar(u,v):
        a=.32+(math.tau-.64)*u; n=fit.bone('J_Bip_C_Neck')
        return Vector((math.sin(a)*(.064+.012*v),n.y-math.cos(a)*(.066+.010*v),fit.neck-.040+.075*v))
    parts.append(surface(ARMOR+'Collar',collar,4,40,edge,fit,thickness=.004))
    for side, sign in [('L',1),('R',-1)]:
        shoulder=fit.bone('J_Bip_'+side+'_UpperArm'); elbow=fit.bone('J_Bip_'+side+'_LowerArm'); wrist=fit.bone('J_Bip_'+side+'_Hand')
        length=abs(elbow.x-shoulder.x)
        for tier in range(3):
            def pauldron(u,v,tier=tier):
                x=shoulder.x+sign*(length*(tier*.23-.04)+v*length*.43)
                a=-.13+(math.pi+.26)*u
                radius=(.078 if fit.sex=='male' else .070)*(1-.14*tier)*(1-.12*v)
                if tier==0: radius*=.57+.43*math.sin(math.pi*(.08+.84*v))
                x+=sign*.008*math.sin(a)*math.sin(math.pi*v)
                return Vector((x,shoulder.y-math.cos(a)*radius,shoulder.z+math.sin(a)*radius))
            parts.append(surface(ARMOR+f'Pauldron_{tier}_{side}',pauldron,5,18,mat,fit,'J_Bip_'+side+'_UpperArm',thickness=.005))
        for tier in range(2):
            def bracer(u,v,tier=tier):
                t=.16+tier*.37+v*.36
                center=elbow.lerp(wrist,t); a=math.tau*u
                candidates=[p for p in fit.points if abs(p.x-center.x)<.018]
                radius=max((math.hypot(p.y-center.y,p.z-center.z) for p in candidates),default=.04)+.006
                radius=min(radius,.060)
                return center+Vector((0,math.cos(a)*radius,math.sin(a)*radius))
            parts.append(surface(ARMOR+f'Bracer_{tier}_{side}',bracer,4,24,mat,fit,'J_Bip_'+side+'_LowerArm',thickness=.004))
    def belt(u,v): return fit.torso(math.tau*u,fit.hip+.04+.060*v,.024)
    parts.append(surface(ARMOR+'Belt',belt,3,56,edge,fit,'J_Bip_C_Hips',thickness=.006))
    for panel in range(8):
        angle=(panel+.5)*math.tau/8
        side='L' if math.sin(angle)>0 else 'R'
        bottom=fit.knee+.055
        top=fit.hip+.045
        def skirt(u,v,angle=angle):
            a=angle+(u-.5)*math.radians(42)
            z=top+(bottom-top)*v
            rx=(.185 if fit.sex=='male' else .163)+.045*v; ry=.126+.045*v
            return Vector((rx*math.sin(a),.012-ry*math.cos(a),z+.008*math.sin(math.pi*u)*v))
        def skirt_weights(p,side=side):
            leg=.96*smooth((top-p.z)/(top-bottom)/.42)
            return {'J_Bip_C_Hips':1-leg,'J_Bip_'+side+'_UpperLeg':leg}
        parts.append(surface(ARMOR+f'SkirtPanel_{panel}',skirt,12,10,mat,fit,weights=skirt_weights,thickness=.006))
    return parts


def helmet_gray(fit):
    black=material('Lacquer',(.018,.022,.027),.62,.28)
    silver=material('Silver',(.66,.70,.73),.86,.30)
    white=material('WhiteHorsehair',(.80,.79,.75),0,.62)
    leather=material('BlackLeather',(.022,.015,.012),0,.72)
    head=fit.bone('J_Bip_C_Head')
    scalp=[p for p in fit.points if p.z>head.z+.08]
    rx=max(abs(p.x-head.x) for p in scalp)+.022
    ry=max(.128,(max(p.y for p in scalp)-min(p.y for p in scalp))/2+.035)
    top=max(p.z for p in scalp)+.026
    brow=head.z+.112
    parts=[]
    def dome(u,v):
        a=math.tau*u; phi=(.015+v*.985)*math.pi/2
        return Vector((head.x+rx*math.sin(phi)*math.sin(a),head.y-.005-ry*math.sin(phi)*math.cos(a),top-(top-brow)*(1-math.cos(phi))))
    parts.append(surface(HELMET+'Dome',dome,20,64,black,fit,'J_Bip_C_Head',thickness=.004))
    for i in range(4):
        def band(u,v,i=i): return dome((i*.25+(u-.5)*.030)%1,.04+.96*v)+Vector((0,0,.003))
        parts.append(surface(HELMET+f'CrownBand_{i}',band,20,4,silver,fit,'J_Bip_C_Head',thickness=.003))
    def browband(u,v):
        a=math.tau*u
        return Vector((head.x+(rx+.003)*math.sin(a),head.y-.005-(ry+.003)*math.cos(a),brow+.008+.017*v+.012*math.cos(2*a)))
    parts.append(surface(HELMET+'BrowBand',browband,3,64,silver,fit,'J_Bip_C_Head',thickness=.003))
    for side,sign in [('L',1),('R',-1)]:
        def guard(u,v,sign=sign):
            a=math.tau*u; radius=.002+.050*v
            return head+Vector((sign*(rx+.006+.009*(1-v*v)),.002+math.cos(a)*radius,.080+math.sin(a)*radius))
        parts.append(surface(HELMET+'SideGuard_'+side,guard,8,40,silver,fit,'J_Bip_C_Head',thickness=.004))
    points, faces = [], []
    rows,cols=8,28
    def curtain(u,v):
        a=math.radians(63)+math.radians(234)*u
        return head+Vector(((rx+.005+.032*v)*math.sin(a),-.002-(ry-.012+.033*v)*math.cos(a),.119-.190*v))
    # Actual open holes: each cell connects a square border to an octagonal opening.
    for r in range(rows):
        for c in range(cols):
            start=len(points)
            for inner in [False,True]:
                for j in range(8):
                    a=math.tau*j/8
                    factor=.33 if inner else .5/max(abs(math.cos(a)),abs(math.sin(a)))
                    points.append(curtain((c+.5+factor*math.cos(a))/cols,(r+.5+factor*math.sin(a))/rows))
            for j in range(8):
                n=(j+1)%8; faces.append((start+j,start+n,start+8+n,start+8+j))
    parts.append(mesh_part(HELMET+'PerforatedAventail',points,faces,silver,fit,'J_Bip_C_Head',thickness=.002))
    for edge,v in [('Top',0),('Hem',1)]:
        parts.append(surface(HELMET+'Aventail'+edge,lambda u,t,v=v:curtain(u,max(0,min(1,v+(t-.5)*.09))),2,56,leather,fit,'J_Bip_C_Head',thickness=.004))
    path=[]; radii=[]
    for i in range(25):
        t=i/24
        path.append(head+Vector((0,.005+.19*t,top-head.z+.02+.12*math.sin(math.pi*t)-.25*t*t)))
        radii.append(.006+.027*math.sin(math.pi*t)**.7)
    parts.append(tube(HELMET+'WhitePlume',path,radii,white,fit,sides=16,flat=.65))
    parts.append(tube(HELMET+'PlumeSocket',[head+Vector((0,.005,top-head.z-.007)),head+Vector((0,.005,top-head.z+.045))],[.019,.015],silver,fit,sides=24))
    return parts


def render_gray(fit, parts):
    arm=fit.arm; scene=bpy.context.scene
    arm.animation_data.action=None
    for track in arm.animation_data.nla_tracks: track.mute=True
    for bone in arm.pose.bones: bone.matrix_basis=Matrix.Identity(4)
    bpy.context.view_layer.update()
    for side,sign in [('L',1),('R',-1)]:
        bone=arm.pose.bones['J_Bip_'+side+'_UpperArm']; pivot=bone.bone.head_local
        bone.matrix=Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(72)*sign,4,'Y') @ Matrix.Translation(-pivot) @ bone.bone.matrix_local
    for obj in bpy.data.objects:
        if obj.type=='MESH':
            show=obj in parts or obj.name in ('Body_Standard_'+fit.sex.title(),'Face_Standard_01') or obj.name.startswith('Outfit_Underlayer_01')
            obj.hide_render=not show; obj.hide_viewport=not show
    scene.render.engine='BLENDER_WORKBENCH'
    scene.display.shading.light='STUDIO'; scene.display.shading.studio_light='paint.sl'
    scene.display.shading.color_type='MATERIAL'; scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True; scene.display.shading.cavity_type='BOTH'
    scene.display.shading.background_type='WORLD'
    if scene.world is None: scene.world=bpy.data.worlds.new('ChineseGearReviewWorld')
    scene.world.color=(.075,.08,.09)
    scene.render.resolution_x=1100; scene.render.resolution_y=1250; scene.render.resolution_percentage=100
    data=bpy.data.cameras.new('ChineseGearReview'); cam=bpy.data.objects.new('ChineseGearReview',data)
    scene.collection.objects.link(cam); scene.camera=cam; data.type='ORTHO'; data.ortho_scale=2.35
    target=Vector((0,0,1.02))
    for name,angle in [('front',0),('threequarter',35),('side',90),('back',180)]:
        a=math.radians(angle); cam.location=target+Vector((math.sin(a)*4,-math.cos(a)*4,0))
        cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(QA/f'{fit.sex}_gray_{name}.png'); bpy.ops.render.render(write_still=True)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--sex',choices=['male','female'],required=True)
    parser.add_argument('--stage',choices=['gray','preview','detail','export'],default='gray')
    opt=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    WORK.mkdir(parents=True,exist_ok=True); QA.mkdir(parents=True,exist_ok=True)
    if opt.stage=='gray': source=BASE/f'standard_anime_{opt.sex}_character_pack.blend'
    else: source=WORK/f'chinese_gear_{opt.sex}{"_gray" if opt.stage in ("preview","detail") else ""}.blend'
    bpy.ops.wm.open_mainfile(filepath=str(source))
    arm=bpy.data.objects['Armature']; fit=Fitting(arm,opt.sex)
    parts=armor_gray(fit)+helmet_gray(fit) if opt.stage=='gray' else [o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith((ARMOR,HELMET))]
    for obj in parts:
        assert obj.data.uv_layers
        assert all(abs(sum(g.weight for g in v.groups)-1)<1e-5 for v in obj.data.vertices)
    if opt.stage=='detail':
        from detail_chinese_leather_mingguang import finish
        finish(fit,parts)
        bpy.ops.wm.save_as_mainfile(filepath=str(WORK/f'chinese_gear_{opt.sex}.blend'))
    elif opt.stage=='gray':
        bpy.ops.wm.save_as_mainfile(filepath=str(WORK/f'chinese_gear_{opt.sex}_gray.blend'))
        render_gray(fit,parts)
    else:
        if opt.stage=='preview':
            image=bpy.data.images.new('ChineseGear_UV_Probe',width=64,height=64)
            pixels=[]
            for y in range(64):
                for x in range(64): pixels.extend((.6,.08,.04,1) if (x//8+y//8)%2 else (.06,.5,.12,1))
            image.pixels.foreach_set(pixels); image.pack()
            mat=material('UVProbe',(.5,.5,.5))
            tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image
            mat.node_tree.links.new(tex.outputs['Color'],mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
            bpy.data.objects[ARMOR+'ChestPanel_Front'].data.materials[0]=mat
        metadata=json.loads((BASE/f'standard_anime_{opt.sex}_character_pack.json').read_text(encoding='utf-8'))
        names={name for values in metadata['parts'].values() for name in values}
        bpy.ops.object.select_all(action='DESELECT')
        for obj in bpy.data.objects:
            if obj==arm or obj.name in names or obj in parts:
                obj.hide_viewport=False; obj.hide_set(False); obj.select_set(True)
        target=WORK/f'candidate_{opt.sex}.glb'
        bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=False,export_optimize_disable_viewport=True,export_skins=True,export_morph=True,export_apply=False)
        import author_chinese_cape as legacy_export
        legacy_export.BASE=BASE
        legacy_export.preserve_legacy_clips(opt.sex,target)
        for slot,prefix in [('armor',ARMOR),('helmet',HELMET)]:
            metadata['parts'][slot]+=sorted(obj.name for obj in parts if obj.name.startswith(prefix))
        (WORK/f'candidate_{opt.sex}.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('CHINESE_GEAR_STAGE_READY',opt.sex,opt.stage,len(parts),flush=True)


if __name__ == '__main__': main()
