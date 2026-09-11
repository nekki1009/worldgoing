"""Explicit gray/detail/export stages; export preserves hand-edited source art."""
import argparse
import json
import math
import sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector, Matrix

sys.path.insert(0, str(Path(__file__).parent))
import author_chinese_leather_mingguang as mesh
from detail_chinese_leather_mingguang import Detail, beast, grid_sample as source_grid_sample

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / '.godot-temp/chinese_leather_helmet_baseline_20260910'
WORK = ROOT / 'assets/characters/human/q35/chinese_leather_helmet'
QA = ROOT / '.visual_captures/chinese_leather_helmet'
PREFIX = 'Helmet_Chinese_Leather_01_'


def grid_sample(obj,u,v):
    point,normal=source_grid_sample(obj,u,v)
    return point-normal*.003,normal


def mat(name, color, metallic=0, roughness=.65):
    return mesh.material('LeatherHelmet_' + name, color, metallic, roughness)


def shape(fit):
    head = fit.bone('J_Bip_C_Head')
    scalp = [p for p in fit.points if p.z > head.z + .08]
    rx = max(abs(p.x-head.x) for p in scalp) + .018
    ry = max(.125, (max(p.y for p in scalp)-min(p.y for p in scalp))/2+.031)
    top = max(p.z for p in scalp)+.023
    brow = head.z+.110
    def dome(u,v):
        a=math.tau*u; phi=(.006+.994*v)*math.pi/2
        return Vector((head.x+rx*math.sin(phi)*math.sin(a),head.y-.005-ry*math.sin(phi)*math.cos(a),brow+(top-brow)*math.cos(phi)))
    return head,rx,ry,top,brow,dome


def gray(fit):
    head,rx,ry,top,brow,dome=shape(fit)
    leather=mat('Leather',(.14,.065,.031),roughness=.79)
    strap=mat('Strap',(.028,.013,.006),roughness=.80)
    bronze=mat('Bronze',(.29,.16,.062),.76,.43)
    lining=mat('Lining',(.10,.078,.057),roughness=.94)
    parts=[]
    def surface(name,fn,rows,cols,material,thickness=.004):
        obj=mesh.surface(PREFIX+name,fn,rows,cols,material,fit,'J_Bip_C_Head',thickness=thickness)
        obj['worldgoing_visual_id']='helmet_chinese_leather_01'
        parts.append(obj)
        return obj
    for i in range(8):
        surface('DomePanel_%d'%i,lambda u,v,i=i:dome((i+(u*.972+.014))/8,v),16,8,leather)
        surface('CrownBand_%d'%i,lambda u,v,i=i:dome((i+(u-.5)*.28)/8,.04+.96*v)+Vector((0,0,.004)),16,3,strap)
    def band(u,v):
        a=math.tau*u
        return Vector((head.x+(rx+.003)*math.sin(a),head.y-.005-(ry+.003)*math.cos(a),brow-.005+.030*v))
    surface('BrowBand',band,3,64,strap)
    for side,sign in [('L',1),('R',-1)]:
        def guard(u,v,sign=sign):
            # A flared leather cheek/ear plate, narrowing at its upper attachment.
            a=sign*(math.radians(61)+math.radians(69)*u)
            flare=.012+.020*v*v
            return head+Vector(((rx+flare)*math.sin(a),-.005-(ry+.011+.022*v)*math.cos(a),.111-.175*v+.020*(abs(u-.5)*2)**6*v))
        surface('EarGuard_'+side,guard,10,12,leather,.005)
    for i in range(4):
        def neck(u,v,i=i):
            a=math.radians(124)+math.radians(112)*u
            t=(i+v*1.16)/4
            return head+Vector(((rx+.008+.029*t)*math.sin(a),-.005-(ry+.010+.030*t)*math.cos(a),.115-.183*t))
        surface('NeckLame_%d'%i,neck,3,24,leather,.005)
    def rear(u,v):
        a=math.pi+(u-.5)*.19
        return head+Vector(((rx+.012+.029*v)*math.sin(a),-.005-(ry+.013+.030*v)*math.cos(a),.114-.185*v))
    surface('RearStrap',rear,12,3,strap)
    def inner(u,v):
        a=math.radians(55)+math.radians(250)*u
        return head+Vector(((rx-.006)*math.sin(a),-.005-(ry-.006)*math.cos(a),.096+.025*v))
    surface('QuiltedLining',inner,3,48,lining,.006)
    def chin(u,v):
        a=-math.pi/2+math.pi*u
        return head+Vector(((rx+.010)*math.sin(a),-.056-.034*math.cos(a)+(v-.5)*.012,.078-.140*math.cos(a)))
    surface('ChinStrap',chin,2,40,strap,.003)
    path=[Vector((head.x,head.y-.005,top-.002)),Vector((head.x,head.y-.005,top+.009))]
    parts.append(mesh.tube(PREFIX+'CrownButton',path,[.024,.016],bronze,fit,sides=24))
    print('HEAD_MEASUREMENTS',fit.sex,dict(rx=rx,ry=ry,top=top,brow=brow),flush=True)
    return parts


def finish(fit,parts):
    # Dedicated plain tanned leather, not the armor's repeating cloud motifs.
    leather=bpy.data.materials['ChineseGear_LeatherHelmet_Leather']
    bsdf=leather.node_tree.nodes.get('Principled BSDF');nodes=leather.node_tree.nodes;links=leather.node_tree.links
    size=1024;rng=np.random.default_rng(100926);y,x=np.mgrid[:size,:size]/size
    grain=rng.normal(0,1,(size,size));pores=np.sin(x*1650+np.sin(y*1100))*np.sin(y*1420+np.sin(x*1230))
    mottling=.075*np.sin(x*33+y*7)+.038*np.sin(y*69-x*21)+.030*grain+.025*pores
    rgb=np.clip(np.array([.245,.137,.077])[None,None,:]*(1+mottling[:,:,None]),0,1)
    gy,gx=np.gradient(.012*pores+.007*grain)
    normal=np.stack([-gx*16,gy*16,np.ones_like(x)],axis=2);normal/=np.linalg.norm(normal,axis=2,keepdims=True)
    maps=[('LeatherColor','Base Color',rgb),('LeatherRoughness','Roughness',np.repeat(np.clip(.79+.04*grain,.64,.94)[:,:,None],3,axis=2)),('LeatherNormal','Normal',normal*.5+.5)]
    for filename,target,values in maps:
        image=bpy.data.images.new('LeatherHelmet_'+filename,width=size,height=size)
        image.colorspace_settings.name='sRGB' if target=='Base Color' else 'Non-Color'
        image.pixels.foreach_set(np.concatenate([values,np.ones((size,size,1))],axis=2).astype(np.float32).ravel())
        image.filepath_raw=str(WORK/(filename+'.png'));image.file_format='PNG';image.save();image.pack()
        tex=nodes.new('ShaderNodeTexImage');tex.image=image
        if target=='Normal':
            normal=nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.23
            links.new(tex.outputs['Color'],normal.inputs['Color']);links.new(normal.outputs['Normal'],bsdf.inputs[target])
        else: links.new(tex.outputs['Color'],bsdf.inputs[target])
    bronze=bpy.data.materials['ChineseGear_LeatherHelmet_Bronze']
    dark=mat('Recess',(.036,.019,.011),.40,.61)
    thread=mat('Stitch',(.16,.10,.047),0,.86)
    edge=mat('Piping',(.05,.026,.013),0,.79)
    for obj in parts:
        if 'grid_rows' not in obj:continue
        d=Detail(obj,fit)
        if 'Lining' in obj.name or 'ChinStrap' in obj.name:continue
        # Borders and discrete saddle stitches remain readable in close views.
        for horizontal in [False,True]:
            for constant in [.055,.945]:
                sample=lambda t:grid_sample(obj,t,constant) if horizontal else grid_sample(obj,constant,t)
                d.tube([sample(t)[0] for t in np.linspace(.025,.975,24)],.0013,edge)
                for t in np.linspace(.045,.93,18):
                    d.tube([sample(t)[0],sample(t+.021)[0]],.00048,thread,4)
        if any(x in obj.name for x in ['CrownBand','BrowBand','RearStrap']):
            for t in np.linspace(.10,.90,5 if 'CrownBand' in obj.name else 12):
                p,n=grid_sample(obj,t,.5) if 'BrowBand' in obj.name else grid_sample(obj,.5,t)
                tangent=n.cross(Vector((1,0,0)))
                if tangent.length<.1:tangent=n.cross(Vector((0,1,0)))
                tangent.normalize()
                d.dome(p,[tangent,n.cross(tangent),n],(.0030,.0030,.0016),bronze,8,3)
        if 'EarGuard' in obj.name:
            for cx,cy in [(.48,.35),(.48,.69)]:
                path=[]
                for t in np.linspace(0,math.tau*1.3,50):
                    radius=.22*(1-t/(math.tau*1.6))
                    path.append(grid_sample(obj,cx+radius*math.cos(t),cy+radius*.64*math.sin(t))[0])
                d.tube(path,.0012,bronze,5)
            d.tube([grid_sample(obj,.26+.06*math.sin(t*math.tau),t)[0] for t in np.linspace(.19,.88,28)],.0010,bronze)
        if obj.name.endswith('BrowBand'):
            p,n=grid_sample(obj,0,.65)
            beast(d,p+Vector((0,-.001,.009)),Vector((1,0,0)),Vector((0,0,1)),Vector((0,-1,0)),.031,bronze,dark)
        d.finish()
    chin=bpy.data.objects[PREFIX+'ChinStrap'];d=Detail(chin,fit)
    p,n=grid_sample(chin,.63,.5)
    d.tube([p+Vector((x,-.003,z)) for x,z in [(-.009,-.007),(.009,-.007),(.009,.007),(-.009,.007),(-.009,-.007)]],.0018,bronze,8)
    d.tube([p+Vector((0,-.005,-.007)),p+Vector((0,-.005,.009))],.0011,bronze,6)
    d.finish()


def render(fit,parts):
    arm=fit.arm;scene=bpy.context.scene
    arm.animation_data.action=None
    for track in arm.animation_data.nla_tracks:track.mute=True
    for bone in arm.pose.bones:bone.matrix_basis=Matrix.Identity(4)
    for obj in bpy.data.objects:
        if obj.type=='MESH':
            show=obj in parts or obj.name in ('Body_Standard_'+fit.sex.title(),'Face_Standard_01')
            obj.hide_render=not show;obj.hide_viewport=not show
    scene.render.engine='BLENDER_WORKBENCH'
    scene.display.shading.light='STUDIO';scene.display.shading.studio_light='paint.sl'
    scene.display.shading.color_type='MATERIAL';scene.display.shading.show_cavity=True
    scene.render.resolution_x=1100;scene.render.resolution_y=1250;scene.render.resolution_percentage=100
    data=bpy.data.cameras.new('LeatherHelmetReview');camera=bpy.data.objects.new('LeatherHelmetReview',data)
    scene.collection.objects.link(camera);scene.camera=camera;data.type='ORTHO';data.ortho_scale=.60
    target=fit.bone('J_Bip_C_Head')+Vector((0,0,.04))
    for label,angle in [('front',0),('side',90),('back',180),('threequarter',35)]:
        a=math.radians(angle);camera.location=target+Vector((math.sin(a)*4,-math.cos(a)*4,0))
        camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(QA/f'{fit.sex}_gray_{label}.png');bpy.ops.render.render(write_still=True)


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--sex',choices=['male','female'],required=True)
    parser.add_argument('--stage',choices=['gray','detail','probe','export'],required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    WORK.mkdir(parents=True,exist_ok=True);QA.mkdir(parents=True,exist_ok=True)
    source=BASE/f'standard_anime_{args.sex}_character_pack.blend' if args.stage=='gray' else WORK/f'leather_helmet_{args.sex}{"_gray" if args.stage in ("detail","probe") else ""}.blend'
    bpy.ops.wm.open_mainfile(filepath=str(source))
    arm=bpy.data.objects['Armature'];fit=mesh.Fitting(arm,args.sex)
    parts=gray(fit) if args.stage=='gray' else [o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith(PREFIX)]
    for obj in parts:obj['worldgoing_visual_id']='helmet_chinese_leather_01'
    if args.stage=='detail':
        finish(fit,parts)
        for obj in bpy.data.objects:
            if obj.name.startswith(PREFIX):obj['worldgoing_visual_id']='helmet_chinese_leather_01'
        bpy.ops.wm.save_as_mainfile(filepath=str(WORK/f'leather_helmet_{args.sex}.blend'))
    elif args.stage=='gray':
        bpy.ops.wm.save_as_mainfile(filepath=str(WORK/f'leather_helmet_{args.sex}_gray.blend'))
        render(fit,parts)
    else:
        if args.stage=='probe':
            # UV checker is a route test, not a substitute for final texture QA.
            image=bpy.data.images.new('LeatherHelmetUVProbe',width=64,height=64)
            image.pixels.foreach_set([c for y in range(64) for x in range(64) for c in ((.7,.07,.02,1) if (x//8+y//8)%2 else (.03,.6,.08,1))]);image.pack()
            material=mat('UVProbe',(.5,.5,.5));tex=material.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image
            material.node_tree.links.new(tex.outputs['Color'],material.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
            bpy.data.objects[PREFIX+'DomePanel_0'].data.materials[0]=material
        metadata=json.loads((BASE/f'standard_anime_{args.sex}_character_pack.json').read_text(encoding='utf-8'))
        names={n for values in metadata['parts'].values() for n in values}
        bpy.ops.object.select_all(action='DESELECT')
        for obj in bpy.data.objects:
            if obj==arm or obj.name in names or obj in parts:
                obj.hide_viewport=False;obj.hide_set(False);obj.select_set(True)
        target=WORK/f'candidate_{args.sex}.glb'
        bpy.ops.export_scene.gltf(filepath=str(target),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=False,export_optimize_disable_viewport=True,export_skins=True,export_morph=True,export_apply=False)
        import author_chinese_cape as legacy
        legacy.BASE=BASE;legacy.preserve_legacy_clips(args.sex,target)
        metadata['parts']['helmet']+=sorted(o.name for o in parts)
        (WORK/f'candidate_{args.sex}.json').write_text(json.dumps(metadata,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    print('LEATHER_HELMET_STAGE_READY',args.sex,args.stage,flush=True)


if __name__=='__main__':main()
