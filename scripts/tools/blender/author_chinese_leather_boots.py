"""Explicit conformal boot authoring; export preserves the scoped baseline."""
import argparse, json, math, sys, shutil, uuid
from pathlib import Path
import bpy, bmesh
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(Path(__file__).parent))
from author_chinese_leather_mingguang import Fitting, mesh_part, tube
from author_chinese_lining import cut, finish_mesh
from build_standard_anime_male_character_pack import copy_mesh
BASE=ROOT/'.godot-temp/chinese_leather_boots_baseline_20260910'
WORK=ROOT/'assets/characters/human/q35/chinese_leather_boots'
QA=ROOT/'.visual_captures/chinese_leather_boots'
PREFIX='Boots_Chinese_Leather_01_'

def reweight(fit,parts):
    for side,sign in [('L',1),('R',-1)]:
        indices=[i for i,p in enumerate(fit.points) if p.x*sign>0 and p.z<fit.knee+.05]
        kd=KDTree(len(indices))
        for i in indices:kd.insert(fit.points[i],i)
        kd.balance()
        for obj in parts:
            if not obj.name.endswith('_'+side):continue
            if obj.name==PREFIX+'Heel_'+side:
                sole=bpy.data.objects[PREFIX+'Sole_'+side]
                contact=min(v.co.z for v in sole.data.vertices)
                lo=min(v.co.z for v in obj.data.vertices);hi=max(v.co.z for v in obj.data.vertices)
                for v in obj.data.vertices:v.co.z=contact-.006+(v.co.z-lo)/max(hi-lo,1e-6)*.0062
            obj.vertex_groups.clear()
            for v in obj.data.vertices:
                weights={}
                for _,i,distance in kd.find_n(obj.matrix_world@v.co,4):
                    for g in fit.body.data.vertices[i].groups:
                        name=fit.groups[g.group]
                        if name in fit.arm.data.bones and '_'+side+'_' in name:
                            weights[name]=weights.get(name,0)+g.weight/max(distance,.001)**2
                total=sum(weights.values());assert total>0,(obj.name,v.index)
                for name,value in weights.items():
                    group=obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name);group.add([v.index],value/total,'REPLACE')

def material(name,color):
    m=bpy.data.materials.new('ChineseBoots_'+name);m.use_nodes=True;m.diffuse_color=(*color,1)
    bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*color,1);bs.inputs['Roughness'].default_value=.72
    return m

def clone(source,name,mat):
    obj=copy_mesh(source,PREFIX+name,'boots','boots_chinese_leather_01')
    obj.data.transform(obj.matrix_world);obj.matrix_world=Matrix.Identity(4)
    bm=bmesh.new();bm.from_mesh(obj.data)
    return obj,bm

def build(fit):
    leather=material('Chestnut',(.17,.065,.028));dark=material('Binding',(.045,.025,.018));solemat=material('Sole',(.026,.020,.016))
    parts=[];top=fit.knee-.068
    for side,sign in [('L',1),('R',-1)]:
        parts.extend(loft_boot(fit,side,sign,top,leather,dark,solemat))
    for obj in parts:
        obj['worldgoing_component_slot']='boots';obj['worldgoing_visual_id']='boots_chinese_leather_01'
    return parts

def loft_boot(fit,side,sign,top,leather,dark,solemat):
    foot=fit.bone('J_Bip_'+side+'_Foot');knee=fit.bone('J_Bip_'+side+'_LowerLeg')
    points=list(fit.points)
    faces=[tuple(p.vertices) for p in fit.body.data.polygons if all(points[i].x*sign>0 for i in p.vertices)]
    bvh=BVHTree.FromPolygons(points,faces)
    low=min(p.z for p in points if p.x*sign>0 and p.z<foot.z)
    levels=[low+.004,low+.018,low+.030,low+.046,low+.065,foot.z-.015,foot.z+.010,foot.z+.040]
    levels=sorted(set(levels+[float(v) for v in np.linspace(foot.z+.065,top,20)]))
    rings=[];cols=64
    for z in levels:
        t=max(0,min(1,(z-foot.z)/(top-foot.z)))
        center=foot.lerp(knee,t);center.z=z
        if z<foot.z:center.y-=.050*(1-(z-low)/(foot.z-low))
        radii=[]
        for c in range(cols):
            a=math.tau*c/cols;d=Vector((math.sin(a),-math.cos(a),0));hits=[]
            for dz in [-.008,0,.008,.020]:
                origin=center+d*.4+Vector((0,0,dz))
                hit,_,_,_=bvh.ray_cast(origin,-d,.8)
                if hit is not None:hits.append((hit-center).dot(d))
            radii.append(max(hits,default=.040)+.014)
        values=np.array(radii)
        for _ in range(3):values=(np.roll(values,1)+values*2+np.roll(values,-1))/4
        rings.append([center+Vector((math.sin(math.tau*c/cols),-math.cos(math.tau*c/cols),0))*float(values[c]) for c in range(cols)])
    # A native-footprint sole and continuous vamp replace toe-by-toe skin detail.
    # First rings use the same footprint, preventing a separate floating sole.
    footprint=[]
    for c in range(cols):
        a=math.tau*c/cols;d=Vector((math.sin(a),-math.cos(a),0))
        p=max([r[c] for r in rings[:4]],key=lambda p:(p-Vector((foot.x,foot.y-.045,p.z))).dot(d)).copy()
        p.z=low-.002;footprint.append(p)
    rings[0]=footprint
    for _ in range(2):
        previous=[[p.copy() for p in r] for r in rings]
        for r in range(1,len(rings)-1):
            if levels[r]<foot.z+.03:continue
            for c in range(cols):
                z=rings[r][c].z;rings[r][c]=(previous[r-1][c]+previous[r][c]*4+previous[r+1][c])/6;rings[r][c].z=z
    def make(name,rows,mat,thickness=0,cap=False):
        verts=[p for ring in rows for p in ring];faces=[];uv=[]
        for r in range(len(rows)):
            for c in range(cols):uv.append((c/cols,r/max(1,len(rows)-1)))
        for r in range(len(rows)-1):
            for c in range(cols):
                n=(c+1)%cols;faces.append((r*cols+c,r*cols+n,(r+1)*cols+n,(r+1)*cols+c))
        if cap:faces.extend([tuple(reversed(range(cols))),tuple((len(rows)-1)*cols+c for c in range(cols))])
        obj=mesh_part(PREFIX+name+'_'+side,verts,faces,mat,fit,'J_Bip_'+side+'_Foot',fit.weights,uv,thickness)
        bm=bmesh.new();bm.from_mesh(obj.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(obj.data);bm.free()
        return obj
    main=make('Main',rings,leather,.002)
    cuffrows=[]
    for z in [top-.030,top]:
        ring=min(rings,key=lambda r:abs(r[0].z-z))
        center=sum(ring,Vector())/cols
        cuffrows.append([Vector((center.x+(p.x-center.x)*1.025,center.y+(p.y-center.y)*1.025,z)) for p in ring])
    cuff=make('Cuff',cuffrows,dark,.003)
    solerows=[]
    for z in [low-.014,low-.001]:solerows.append([Vector((p.x,p.y,z)) for p in footprint])
    sole=make('Sole',solerows,solemat,cap=True)
    heel,hb=clone(sole,'Heel_'+side,solemat)
    cut(hb,(0,foot.y-.015,0),(0,1,0),inner=True)
    for v in hb.verts:v.co.z-=.006
    boundary=[e for e in hb.edges if e.is_boundary]
    if boundary:bmesh.ops.holes_fill(hb,edges=boundary,sides=0)
    finish_mesh(heel,hb,solemat)
    return [main,cuff,sole,heel]


def save(sex):
    temporary=ROOT/f'.godot-temp/boots_{sex}_{uuid.uuid4().hex}.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(temporary));shutil.copy2(temporary,WORK/f'chinese_leather_boots_{sex}.blend')
    temporary.unlink()

def preview(fit,parts):
    scene=bpy.context.scene;arm=fit.arm
    arm.animation_data.action=None
    for track in arm.animation_data.nla_tracks:track.mute=True
    for bone in arm.pose.bones:bone.matrix_basis=Matrix.Identity(4)
    bpy.context.view_layer.update()
    for o in bpy.data.objects:
        if o.type=='MESH':o.hide_render=not(o in parts or o==fit.body)
    scene.render.engine='BLENDER_WORKBENCH';scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_cavity=True
    scene.render.resolution_x=1024;scene.render.resolution_y=1024;scene.render.resolution_percentage=100
    data=bpy.data.cameras.new('BootReview');camera=bpy.data.objects.new('BootReview',data);scene.collection.objects.link(camera);scene.camera=camera;data.type='ORTHO';data.ortho_scale=.72
    target=Vector((0,0,.29))
    for label,angle in [('front',0),('side',90),('back',180),('threequarter',35)]:
        a=math.radians(angle);camera.location=target+Vector((math.sin(a)*3,-math.cos(a)*3,.10));camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(QA/f'{fit.sex}_gray_{label}.png');bpy.ops.render.render(write_still=True)

def export(sex,parts):
    # Same selected-object and legacy-channel preservation, with a boots list.
    arm=bpy.data.objects['Armature'];metadata=json.loads((BASE/f'standard_anime_{sex}_character_pack.json').read_text(encoding='utf-8'))
    names={name for values in metadata['parts'].values() for name in values}
    bpy.ops.object.select_all(action='DESELECT')
    for obj in bpy.data.objects:
        if obj==arm or obj.name in names or obj in parts:obj.hide_viewport=False;obj.hide_set(False);obj.select_set(True)
    target=WORK/f'candidate_{sex}.glb'
    bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=False,export_optimize_disable_viewport=True,export_skins=True,export_morph=True,export_apply=False)
    import author_chinese_cape as legacy
    legacy.BASE=BASE;legacy.preserve_legacy_clips(sex,target)
    metadata['parts']['boots']+=sorted(o.name for o in parts)
    (WORK/f'candidate_{sex}.json').write_text(json.dumps(metadata,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')

def detail(fit,parts):
    dark=bpy.data.materials['ChineseBoots_Binding'];thread=material('Stitch',(.34,.21,.115))
    for side,sign in [('L',1),('R',-1)]:
        main=bpy.data.objects[PREFIX+'Main_'+side];pts=[main.matrix_world@v.co for v in main.data.vertices]
        bvh=BVHTree.FromPolygons(pts,[tuple(p.vertices) for p in main.data.polygons])
        foot=fit.bone('J_Bip_'+side+'_Foot');knee=fit.bone('J_Bip_'+side+'_LowerLeg');top=fit.knee-.068
        def point(a,z,offset=.002):
            center=foot.lerp(knee,max(0,min(1,(z-foot.z)/(top-foot.z))));center.z=z
            direction=Vector((math.sin(a),-math.cos(a),0))
            hit,n,_,_=bvh.ray_cast(center+direction*.4,-direction,.8)
            assert hit is not None,(a,z)
            return hit+direction*offset
        from author_chinese_leather_mingguang import surface
        strap=surface(PREFIX+'AnkleBand_'+side,lambda u,v:point(math.tau*u,foot.z+.035+.012*math.cos(math.tau*u)+.018*v),3,64,dark,fit,weights=fit.weights,thickness=.002)
        parts.append(strap)
        # Heel and toe overlays retain exactly the main's weights at clipped edges.
        for label,axis,value,inner in [('ToeCap',1,foot.y-.095,False),('HeelPatch',1,foot.y+.015,True)]:
            obj,bm=clone(main,label+'_'+side,dark)
            cut(bm,(0,value,0),(0,1,0),inner=inner,outer=not inner)
            cut(bm,(0,0,foot.z+.015),(0,0,1),outer=True)
            bm.normal_update()
            for v in bm.verts:v.co+=v.normal*.0015
            parts.append(finish_mesh(obj,bm,dark))
        def cord(label,path,radius,mat):
            obj=tube(PREFIX+label+'_'+side,path,[radius]*len(path),mat,fit,'J_Bip_'+side+'_LowerLeg',sides=6)
            # Shared native interpolation keeps straps and stitching on the vamp.
            obj.vertex_groups.clear()
            for v in obj.data.vertices:
                for name,value in fit.weights(v.co).items():
                    g=obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name);g.add([v.index],value,'REPLACE')
            parts.append(obj);return obj
        cord('BackSeam',[point(math.pi,float(z),.0025) for z in np.linspace(foot.z+.025,top-.003,40)],.0008,dark)
        for j,z in enumerate([top-.029,top-.002]):
            cord('CuffPiping'+str(j),[point(math.tau*c/96,z,.0035) for c in range(97)],.0008,thread)
        a=sign*math.pi*.48;z=foot.z+.046
        for petal in range(4):
            path=[]
            for t in np.linspace(0,math.tau,25):
                q=petal*math.pi/2
                horizontal=.0045*math.cos(q)+.005*math.cos(t)*math.cos(q)-.003*math.sin(t)*math.sin(q)
                vertical=.0045*math.sin(q)+.005*math.cos(t)*math.sin(q)+.003*math.sin(t)*math.cos(q)
                path.append(point(a+horizontal/.047,z+vertical,.005))
            cord('Knot'+str(petal),path,.0014,dark)
        for j in range(2):cord('KnotTail'+str(j),[point(a+(j-.5)*.075,z-.004-t*.024,.004) for t in np.linspace(0,1,10)],.0011,dark)
    for obj in parts:obj['worldgoing_component_slot']='boots';obj['worldgoing_visual_id']='boots_chinese_leather_01'
    # Image textures, not an unsupported procedural-only shader.
    mat=bpy.data.materials['ChineseBoots_Chestnut'];size=512
    rng=np.random.default_rng(61);noise=rng.normal(0,.009,(size,size));y,x=np.mgrid[0:size,0:size]
    noise+=.008*np.sin(x*.044)*np.cos(y*.029)
    img=bpy.data.images.new('ChineseBoots_LeatherColor',width=size,height=size)
    rgba=np.ones((size,size,4),dtype=np.float32);rgba[:,:,:3]=np.clip(np.array([.30,.155,.075])+noise[:,:,None],0,1)
    img.pixels.foreach_set(rgba.ravel());img.filepath_raw=str(WORK/'LeatherColor.png');img.file_format='PNG';img.save();img.pack()
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=img;mat.node_tree.links.new(tex.outputs['Color'],mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--sex',choices=['male','female'],required=True);parser.add_argument('--stage',choices=['gray','detail','export','preview','probe'],required=True);args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    WORK.mkdir(parents=True,exist_ok=True);QA.mkdir(parents=True,exist_ok=True);bpy.context.preferences.filepaths.save_version=0
    source=BASE/f'standard_anime_{args.sex}_character_pack.blend' if args.stage=='gray' else WORK/f'chinese_leather_boots_{args.sex}.blend'
    bpy.ops.wm.open_mainfile(filepath=str(source));fit=Fitting(bpy.data.objects['Armature'],args.sex)
    if args.stage=='gray':parts=build(fit);save(args.sex);preview(fit,parts)
    else:
        parts=[o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith(PREFIX)]
        if args.stage=='preview':preview(fit,parts)
        else:
            if args.stage=='detail':
                core={PREFIX+name+'_'+side for name in ['Main','Cuff','Sole','Heel'] for side in ['L','R']}
                for obj in list(parts):
                    if obj.name not in core:parts.remove(obj);bpy.data.objects.remove(obj,do_unlink=True)
                detail(fit,parts);reweight(fit,parts);save(args.sex)
            if args.stage=='probe':reweight(fit,parts);save(args.sex)
            export(args.sex,parts)
    print('CHINESE_BOOTS_STAGE_READY',args.sex,args.stage,flush=True)

if __name__=='__main__':main()
