"""Three measured footwear lasts on each native body; gray/detail/export are explicit.

Export appends to the immutable task baseline, never regenerates old equipment.
The saved blend contains the original pack plus editable new footwear.
"""
import argparse
import json
import math
import shutil
import sys
import time
import uuid
from pathlib import Path
import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).parent))
from author_chinese_leather_mingguang import Fitting, mesh_part, tube
from author_chinese_leather_boots import reweight
from medieval_cloth_export import append_cloth

BASE = ROOT / 'output/medieval_shoes_20260916/baseline'
WORK = ROOT / 'assets/characters/human/q35/medieval_shoes'
QA = ROOT / 'output/medieval_shoes_20260916'
PREFIX = 'Boots_Medieval_'
STYLES = ('Chinese', 'Japanese', 'European')


def material(name, color, rough=.82):
    mat = bpy.data.materials.get('MedievalShoes_'+name) or bpy.data.materials.new('MedievalShoes_'+name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    bs = mat.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*color, 1)
    bs.inputs['Roughness'].default_value = rough
    return mat


def mesh(name, rings, mat, fit, side, cap=False, thickness=0):
    cols = len(rings[0])
    verts = [p for row in rings for p in row]
    uv = [(c/cols, r/(len(rings)-1)) for r in range(len(rings)) for c in range(cols)]
    faces = [(r*cols+c, r*cols+(c+1)%cols, (r+1)*cols+(c+1)%cols, (r+1)*cols+c)
             for r in range(len(rings)-1) for c in range(cols)]
    if cap:
        faces += [tuple(reversed(range(cols))), tuple((len(rings)-1)*cols+c for c in range(cols))]
    obj = mesh_part(name, verts, faces, mat, fit, 'J_Bip_'+side+'_Foot', fit.weights, uv, thickness)
    bm = bmesh.new(); bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces)); bm.to_mesh(obj.data); bm.free()
    return obj


def last(fit, side, sign, top):
    foot = fit.bone('J_Bip_'+side+'_Foot')
    knee = fit.bone('J_Bip_'+side+'_LowerLeg')
    points = fit.points
    faces = [tuple(p.vertices) for p in fit.body.data.polygons if all(points[i].x*sign>0 for i in p.vertices)]
    bvh = BVHTree.FromPolygons(points, faces)
    low = min(p.z for p in points if p.x*sign>0 and p.z<foot.z)
    levels = np.linspace(low+.004, top, 24)
    rings = []
    for z in levels:
        center = foot.lerp(knee, max(0, (z-foot.z)/(knee.z-foot.z)))
        center.z = z
        if z < foot.z: center.y -= .048*(1-(z-low)/(foot.z-low))
        radii = []
        for c in range(80):
            direction = Vector((math.sin(math.tau*c/80), -math.cos(math.tau*c/80), 0))
            hits = []
            for dz in (-.005, 0, .005, .012, .020):
                hit, _, _, _ = bvh.ray_cast(center+direction*.4+Vector((0,0,dz)), -direction, .8)
                if hit is not None: hits.append((hit-center).dot(direction))
            radii.append(max(hits)+.006 if hits else float('nan'))
        values = np.array(radii)
        valid = np.flatnonzero(np.isfinite(values))
        assert len(valid)>=40,(fit.sex,side,float(z),'insufficient measured cross section')
        values = np.interp(np.arange(80),valid,values[valid],period=80)
        for _ in range(3): values = (np.roll(values,1)+values*2+np.roll(values,-1))/4
        rings.append([center+Vector((math.sin(math.tau*c/80),-math.cos(math.tau*c/80),0))*float(values[c]) for c in range(80)])
    # The foot-derived perimeter gives the shoe its heel, arch and broad toe.
    footprint = []
    for c in range(80):
        direction = Vector((math.sin(math.tau*c/80),-math.cos(math.tau*c/80),0))
        p = max((r[c] for r in rings[:6]), key=lambda p:(p-Vector((foot.x,foot.y-.045,p.z))).dot(direction)).copy()
        p.z = low+.001; footprint.append(p)
    rings[0] = [p.copy() for p in footprint]
    return rings, footprint, low


def build(fit):
    cloth = material('Cloth', (.09,.14,.23))
    tabi = material('Tabi', (.68,.63,.52))
    leather = material('Leather', (.23,.10,.045), .73)
    binding = material('Binding', (.032,.039,.053))
    sole = material('Sole', (.055,.033,.021))
    straw = material('Straw', (.46,.30,.13))
    linen = material('LinenSole', (.56,.50,.36))
    parts = []
    for style, mat in zip(STYLES, (cloth,tabi,leather)):
        for side, sign in [('L',1),('R',-1)]:
            prefix = PREFIX+style+'_01_'
            foot = fit.bone('J_Bip_'+side+'_Foot')
            top = foot.z + {'Chinese':.005,'Japanese':.085,'European':.065}[style]
            rings, footprint, low = last(fit,side,sign,top)
            if style=='Japanese':
                # Recess between great toe and the other four, on the medial side.
                for row in rings:
                    for p in row:
                        medial = (p.x-foot.x)*sign
                        front = max(0,min(1,(foot.y-.070-p.y)/.075))
                        p.y += .030*math.exp(-((medial+.018)/.007)**2)*front
            parts.append(mesh(prefix+'Upper_'+side,rings,mat,fit,side,thickness=.002))
            sole_mat = {'Chinese':linen,'Japanese':straw,'European':sole}[style]
            floor = low-.009
            sole_rows = [[Vector((p.x,p.y,z)) for p in footprint] for z in (floor,low+.002)]
            parts.append(mesh(prefix+'Sole_'+side,sole_rows,sole_mat,fit,side,cap=True))
            cuff_rows = [[p+Vector((0,0,dz)) for p in rings[-1]] for dz in (-.004,.001)]
            parts.append(mesh(prefix+'Binding_'+side,cuff_rows,binding if style!='European' else leather,fit,side,thickness=.003))
            print('LAST',fit.sex,style,side,'ankle',tuple(foot),'top',top,'low',low,flush=True)
    tag(parts)
    reweight(fit,parts)
    return parts


def textures():
    # Small packed image maps retain weave/grain in glTF and the dye shader.
    # These are baked native material patterns, not edits of the reference art.
    size=256
    y,x=np.mgrid[0:size,0:size]
    noise=np.random.default_rng(714).normal(0,.015,(size,size))
    for name in ('Cloth','Tabi','Leather'):
        mat=bpy.data.materials['MedievalShoes_'+name]
        base=np.array(mat.diffuse_color[:3])
        pattern=noise if name=='Leather' else noise+.027*np.sin(x*math.pi/2)*np.sin(y*math.pi/2)
        rgba=np.ones((size,size,4),dtype=np.float32)
        rgba[:,:,:3]=np.clip(base[None,None,:]*(1+pattern[:,:,None]),0,1)
        img=bpy.data.images.new('MedievalShoes_'+name+'_Color',width=size,height=size)
        img.pixels.foreach_set(rgba.ravel());img.pack()
        tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=img
        mat.node_tree.links.new(tex.outputs['Color'],mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])


def tag(parts):
    for obj in parts:
        style = obj.name.split('_')[2].lower()
        obj['worldgoing_component_slot'] = 'boots'
        obj['worldgoing_visual_id'] = 'boots_medieval_'+style+'_01'


def detail(fit,parts):
    # Native-weighted piping and actual tied straps, not floating decorations.
    for style in STYLES:
        for side,sign in [('L',1),('R',-1)]:
            prefix=PREFIX+style+'_01_'
            upper=bpy.data.objects[prefix+'Upper_'+side]
            points=[upper.matrix_world@v.co for v in upper.data.vertices]
            bvh=BVHTree.FromPolygons(points,[tuple(p.vertices) for p in upper.data.polygons])
            foot=fit.bone('J_Bip_'+side+'_Foot')
            lo=min(p.z for p in points);top=max(p.z for p in points)
            def point(a,z,offset=.002):
                center=Vector((foot.x,foot.y,z))
                if z<foot.z:center.y-=.048*(1-(z-lo)/(foot.z-lo))
                direction=Vector((math.sin(a),-math.cos(a),0))
                hit,_,_,_=bvh.ray_cast(center+direction*.4,-direction,.8)
                assert hit is not None,(style,side,a,z)
                return hit+direction*offset
            def cord(label,path,radius,mat):
                obj=tube(prefix+label+'_'+side,path,[radius]*len(path),mat,fit,'J_Bip_'+side+'_Foot',sides=6)
                parts.append(obj)
            dark=material('LeatherBinding',(.06,.031,.016)) if style=='European' else bpy.data.materials['MedievalShoes_Binding']
            thread=material('Thread',(.47,.35,.21))
            if style=='Chinese':
                cord('VampSeam',[point(0,float(z),.0012) for z in np.linspace(lo+.013,top-.008,24)],.0007,dark)
                for i in range(2):
                    cord('SoleStitch'+str(i),[point(math.tau*c/100,lo+.004+i*.003) for c in range(101)],.00065,thread)
            elif style=='European':
                cord('BackSeam',[point(math.pi,float(z)) for z in np.linspace(lo+.017,top-.003,32)],.0008,thread)
                # A narrow recessed tongue, bounded by two raised lace facings.
                for i in range(2):
                    a=(i-.5)*.36
                    cord('Facing'+str(i),[point(a,float(z),.002) for z in np.linspace(foot.z+.002,top-.005,24)],.0015,dark)
                for i in range(4):
                    z=foot.z+.008+i*.013
                    for k in range(2):
                        path=[point((-.18+.36*t)*(1 if k else -1),z+.010*t,.004) for t in np.linspace(0,1,14)]
                        cord('Lace'+str(i)+str(k),path,.0012,thread)
            else:
                # Two instep straps, continuous around the sides to a tied ankle band.
                for i in range(2):
                    path=[point((i*2-1)*(1-t)*math.pi*.63,lo+.019+t*.042,.004) for t in np.linspace(0,1,36)]
                    cord('InstepStrap'+str(i),path,.0035,dark)
                for i in range(2):
                    cord('AnkleTie'+str(i),[point(math.tau*c/100,top-.018-i*.007,.004) for c in range(101)],.0025,dark)
                # Readable woven rim: small repeated twists around the sole.
                straw=bpy.data.materials['MedievalShoes_Straw']
                for i in range(2):
                    path=[point(math.tau*c/160,lo+.003+math.sin(math.tau*c/4+i*math.pi)*.002,.003) for c in range(161)]
                    cord('WovenRim'+str(i),path,.0018,straw)
                a=sign*math.pi*.55
                for i in range(2):
                    path=[point(a+.08*math.sin(t),top-.016-.009*(1-math.cos(t)),.007) for t in np.linspace(0,math.tau,33)]
                    cord('TieLoop'+str(i),path,.002,dark)
    tag(parts)
    reweight(fit,parts)


def save(sex):
    temporary=ROOT/f'.godot-temp/medieval_shoes_{sex}_{uuid.uuid4().hex}.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(temporary))
    shutil.copy2(temporary,WORK/f'medieval_shoes_{sex}.blend')
    for attempt in range(6):
        try:
            temporary.unlink()
            break
        except PermissionError:
            if attempt==5: raise
            time.sleep(.3)


def preview(fit,parts):
    scene=bpy.context.scene
    fit.arm.animation_data.action=None
    for track in fit.arm.animation_data.nla_tracks:track.mute=True
    for bone in fit.arm.pose.bones:bone.matrix_basis=Matrix.Identity(4)
    bpy.context.view_layer.update()
    scene.render.engine='BLENDER_WORKBENCH'
    scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_cavity=True
    scene.render.resolution_x=1024;scene.render.resolution_y=768;scene.render.resolution_percentage=100
    data=bpy.data.cameras.new('ShoesReview');camera=bpy.data.objects.new('ShoesReview',data)
    scene.collection.objects.link(camera);scene.camera=camera;data.type='ORTHO';data.ortho_scale=.52
    target=Vector((0,-.05,.09))
    for style in STYLES:
        for obj in bpy.data.objects:
            if obj.type=='MESH':obj.hide_render=not(obj==fit.body or obj in parts and style in obj.name)
        for label,angle in [('front',0),('side',90),('back',180),('threequarter',35)]:
            a=math.radians(angle);camera.location=target+Vector((math.sin(a)*3,-math.cos(a)*3,.65))
            camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
            scene.render.filepath=str(QA/f'{fit.sex}_{style.lower()}_gray_{label}.png')
            bpy.ops.render.render(write_still=True)


def export(fit,parts):
    fit.arm.animation_data.action=None
    for track in fit.arm.animation_data.nla_tracks:track.mute=True
    for bone in fit.arm.pose.bones:bone.matrix_basis=Matrix.Identity(4)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [fit.arm]+parts:
        obj.hide_viewport=False;obj.hide_set(False);obj.select_set(True)
    subset=WORK/f'subset_{fit.sex}.glb'
    bpy.ops.export_scene.gltf(filepath=str(subset),export_format='GLB',use_selection=True,
        export_animations=False,export_skins=True,export_morph=False,export_apply=False)
    append_cloth(BASE/f'standard_anime_{fit.sex}_character_pack.glb',subset,WORK/f'candidate_{fit.sex}.glb',{},PREFIX)
    metadata=json.loads((BASE/f'standard_anime_{fit.sex}_character_pack.json').read_text(encoding='utf-8'))
    metadata['parts']['boots']+=sorted(o.name for o in parts)
    metadata['medieval_shoes']={'styles':list(STYLES),'slot':'boots','native_gender_fit':fit.sex,'reference':'output/medieval_shoes_20260916/reference/footwear_board.png'}
    (WORK/f'candidate_{fit.sex}.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--sex',choices=['male','female'],required=True)
    parser.add_argument('--stage',choices=['gray','detail','preview','export'],required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    WORK.mkdir(parents=True,exist_ok=True);QA.mkdir(parents=True,exist_ok=True)
    bpy.context.preferences.filepaths.save_version=0
    source=BASE/f'standard_anime_{args.sex}_character_pack.blend' if args.stage=='gray' else WORK/f'medieval_shoes_{args.sex}.blend'
    bpy.ops.wm.open_mainfile(filepath=str(source));fit=Fitting(bpy.data.objects['Armature'],args.sex)
    parts=[o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith(PREFIX)]
    if args.stage=='gray':
        assert not parts,'Shoes already in baseline'
        parts=build(fit);save(args.sex);preview(fit,parts)
    elif args.stage=='preview':preview(fit,parts)
    else:
        if args.stage=='detail':
            assert len(parts)==18,'Use export after manual/detail authoring'
            detail(fit,parts)
        changed=args.stage=='detail'
        if not any(node.type=='TEX_IMAGE' for node in bpy.data.materials['MedievalShoes_Cloth'].node_tree.nodes):
            textures();changed=True
        if changed: save(args.sex)
        export(fit,parts)
    print('MEDIEVAL_SHOES_STAGE_READY',args.sex,args.stage,len(parts),flush=True)


if __name__=='__main__':main()
