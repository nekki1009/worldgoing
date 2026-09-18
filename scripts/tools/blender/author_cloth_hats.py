"""Explicit measured cloth-cap authoring. Export appends; never rebuilds old art."""
import argparse
import json
import math
import shutil
import sys
import time
import uuid
from pathlib import Path
import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).parent))
from author_chinese_leather_mingguang import Fitting, surface, tube
from medieval_cloth_export import append_cloth

QA = ROOT / 'output/cloth_hats_20260918'
BASE = QA / 'baseline'
WORK = ROOT / 'assets/characters/human/q35/cloth_hats'
PREFIX = 'Helmet_Cloth_'
STYLES = ('Chinese', 'Japanese', 'Western')


def material(name, color):
    mat = bpy.data.materials.get('ClothHats_'+name) or bpy.data.materials.new('ClothHats_'+name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    bs = mat.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*color, 1)
    bs.inputs['Metallic'].default_value = 0
    bs.inputs['Roughness'].default_value = .91
    return mat


def forms(fit):
    head = fit.bone('J_Bip_C_Head')
    # The skin owner excludes the separate face/forehead mesh. Measure both;
    # a body-only ellipse would cut straight through the forehead at the brim.
    head_points = list(fit.points)
    for obj in bpy.data.objects:
        if obj.type=='MESH' and obj.name.startswith('Face_Standard_01'):
            head_points += [obj.matrix_world @ v.co for v in obj.data.vertices]
    scalp = [p for p in head_points if p.z > head.z+.08]
    rx = max(abs(p.x-head.x) for p in scalp)+.014
    front, back = min(p.y for p in scalp), max(p.y for p in scalp)
    cy = (front+back)/2
    ry = (back-front)/2+.021
    brow = head.z+.108
    height = max(p.z for p in scalp)-brow+.019
    def crown(style, u, v):
        a = math.tau*u
        if style == 'Japanese':
            # A swept, folded cloth crown; upper tip folds back without touching scalp.
            knots = [0,.30,.57,.78,.90,1]
            def curved(values):
                i=min(len(knots)-2,max(0,int(np.searchsorted(knots,v)-1)))
                t=(v-knots[i])/(knots[i+1]-knots[i])
                m0=(values[i+1]-values[max(0,i-1)])/(knots[i+1]-knots[max(0,i-1)])
                m1=(values[min(len(knots)-1,i+2)]-values[i])/(knots[min(len(knots)-1,i+2)]-knots[i])
                return (2*t**3-3*t*t+1)*values[i]+(t**3-2*t*t+t)*m0*(knots[i+1]-knots[i])+(-2*t**3+3*t*t)*values[i+1]+(t**3-t*t)*m1*(knots[i+1]-knots[i])
            r = max(.004,curved([1,.96,.68,.25,.10,.004]))
            z = brow+curved([.024,height*.85,height+.067,height+.13,height+.107,height+.048])
            shift = curved([0,0,.014,.045,.100,.150])
            fold = .005*math.sin(a*3+v*4)*math.sin(math.pi*v)
            return Vector((head.x+(rx*r+fold)*math.sin(a), cy+shift-(ry*r+fold)*math.cos(a),z))
        phi = (1-v)*math.pi/2
        r = math.sin(phi)
        if style == 'Chinese':
            fold = .0017*math.sin(a*6)*math.sin(phi)*math.sin(math.pi*v)
            return Vector((head.x+(rx*r+fold)*math.sin(a), cy-(ry*r+fold)*math.cos(a),brow+.018+height*math.cos(phi)))
        # Sixteen soft gathered pleats feed a broad, asymmetrically slouched crown.
        fullness = 1+.30*math.sin(math.pi*v)**.7
        fold = .009*math.sin(a*16+.6)*math.sin(math.pi*v)**1.8
        shift = -.030*math.sin(math.pi*v/2)
        return Vector((head.x+shift+(rx*r*fullness+fold)*math.sin(a),cy+.012*v-(ry*r*fullness+fold)*math.cos(a),brow+.022+height*.88*math.cos(phi)+.009*math.cos(a)*math.sin(math.pi*v)))
    def band(u,v):
        a=math.tau*u
        r=.003*math.sin(math.pi*v)
        return Vector((head.x+(rx+.003+r)*math.sin(a),cy-(ry+.003+r)*math.cos(a),brow+.031*v))
    return head, rx, ry, cy, brow, height, crown, band


def tag(parts):
    for obj in parts:
        obj['worldgoing_component_slot']='helmet'
        obj['worldgoing_visual_id']='helmet_cloth_'+obj.name.split('_')[2].lower()+'_01'


def build(fit):
    cloth=material('Fabric',(.27,.31,.37))
    trim=material('Band',(.21,.245,.295))
    head,rx,ry,cy,brow,height,crown,band=forms(fit)
    parts=[]
    for style in STYLES:
        prefix=PREFIX+style+'_01_'
        parts.append(surface(prefix+'Crown',lambda u,v: crown(style,u,v*.998),40,96,cloth,fit,'J_Bip_C_Head',thickness=.003))
        parts.append(surface(prefix+'Band',band,6,96,trim,fit,'J_Bip_C_Head',thickness=.003))
        if style != 'Western':
            for side in (-1,1):
                def tab(u,v,side=side):
                    return Vector((head.x+side*(.008+.012*v)+(u-.5)*.018,cy+ry+.006+.012*math.sin(v*math.pi/2),brow+.019-.056*v+.002*math.sin(u*math.pi)))
                parts.append(surface(prefix+'Tie_'+str(side),tab,12,5,trim,fit,'J_Bip_C_Head',thickness=.002))
            parts.append(surface(prefix+'Knot',lambda u,v:Vector((head.x+(u-.5)*.025,cy+ry+.007+.006*math.sin(math.pi*u),brow+.003+.025*v)),4,8,trim,fit,'J_Bip_C_Head',thickness=.005))
        if style=='Chinese':
            top=crown(style,0,1)
            parts.append(tube(prefix+'ClothButton',[top+Vector((0,0,z)) for z in [-.003,0,.007,.012]],[.007,.010,.009,.002],cloth,fit,sides=24))
    tag(parts)
    (QA/f'{fit.sex}_fit.json').write_text(json.dumps({'head':list(head),'rx':rx,'ry':ry,'cy':cy,'brow':brow,'height':height},indent=2))
    return parts


def detail(fit,parts):
    thread=material('Seams',(.17,.20,.245))
    *_,crown,band=forms(fit)
    for style in STYLES:
        prefix=PREFIX+style+'_01_'
        for i in range(6 if style=='Chinese' else 4 if style=='Japanese' else 8):
            count=6 if style=='Chinese' else 4 if style=='Japanese' else 8
            u=i/count
            path=[crown(style,u,float(v))+Vector((math.sin(math.tau*u),-math.cos(math.tau*u),.3))*.002 for v in np.linspace(.04,.96,36)]
            parts.append(tube(prefix+'PanelSeam_'+str(i),path,[.00065]*len(path),thread,fit,sides=5))
        for edge in (.09,.9):
            path=[band(float(u),edge)+Vector((math.sin(math.tau*u),-math.cos(math.tau*u),0))*.002 for u in np.linspace(0,1,129)]
            parts.append(tube(prefix+'Hem_'+str(edge),path,[.0006]*len(path),thread,fit,sides=5))
    # Native baked material weave, not editing the generated reference image.
    size=512
    y,x=np.mgrid[:size,:size]
    noise=np.random.default_rng(918).normal(0,.013,(size,size))
    weave=.035*np.sin(x*math.pi/2)*np.sin(y*math.pi/2)+noise
    for name in ('Fabric','Band'):
        mat=bpy.data.materials['ClothHats_'+name]
        rgba=np.ones((size,size,4),dtype=np.float32)
        rgba[:,:,:3]=np.clip(np.array(mat.diffuse_color[:3])[None,None,:]*(1+weave[:,:,None]),0,1)
        img=bpy.data.images.new('ClothHats_'+name+'_Weave',width=size,height=size)
        img.pixels.foreach_set(rgba.ravel());img.pack()
        tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=img
        mat.node_tree.links.new(tex.outputs['Color'],mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
    tag(parts)


def reset(fit):
    fit.arm.animation_data.action=None
    for track in fit.arm.animation_data.nla_tracks:track.mute=True
    for bone in fit.arm.pose.bones:bone.matrix_basis=Matrix.Identity(4)
    bpy.context.view_layer.update()


def save(sex):
    tmp=ROOT/f'.godot-temp/cloth_hats_{sex}_{uuid.uuid4().hex}.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(tmp))
    target=WORK/f'cloth_hats_{sex}.blend'
    shutil.copy2(tmp,target)
    assert target.stat().st_size==tmp.stat().st_size
    for attempt in range(6):
        try:tmp.unlink();break
        except PermissionError:
            if attempt==5:raise
            time.sleep(.3)


def preview(fit,parts):
    reset(fit)
    scene=bpy.context.scene
    scene.render.engine='BLENDER_WORKBENCH'
    scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_cavity=True
    scene.render.resolution_x=1024;scene.render.resolution_y=1024;scene.render.resolution_percentage=100
    data=bpy.data.cameras.new('ClothHatsReview');camera=bpy.data.objects.new('ClothHatsReview',data)
    scene.collection.objects.link(camera);scene.camera=camera;data.type='ORTHO';data.ortho_scale=.65
    target=fit.bone('J_Bip_C_Head')+Vector((0,0,.13))
    for style in STYLES:
        for obj in bpy.data.objects:
            if obj.type=='MESH':obj.hide_render=not(obj==fit.body or obj.name=='Face_Standard_01' or obj in parts and style in obj.name)
        for label,angle in [('front',0),('side',90),('back',180),('threequarter',35)]:
            a=math.radians(angle);camera.location=target+Vector((math.sin(a)*3,-math.cos(a)*3,.08))
            camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
            scene.render.filepath=str(QA/f'{fit.sex}_{style.lower()}_gray_{label}.png')
            bpy.ops.render.render(write_still=True)


def export(fit,parts):
    reset(fit)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [fit.arm]+parts:
        obj.hide_viewport=False;obj.hide_set(False);obj.select_set(True)
    subset=WORK/f'subset_{fit.sex}.glb'
    bpy.ops.export_scene.gltf(filepath=str(subset),export_format='GLB',use_selection=True,export_animations=False,export_skins=True,export_morph=False,export_apply=False)
    append_cloth(BASE/f'standard_anime_{fit.sex}_character_pack.glb',subset,WORK/f'candidate_{fit.sex}.glb',{},PREFIX)
    meta=json.loads((BASE/f'standard_anime_{fit.sex}_character_pack.json').read_text(encoding='utf-8'))
    meta['parts']['helmet']+=sorted(o.name for o in parts)
    meta['cloth_hats']={'styles':list(STYLES),'slot':'helmet','material':'cloth','native_gender_fit':fit.sex,'reference':'output/cloth_hats_20260918/reference/cloth_hats_board.png'}
    (WORK/f'candidate_{fit.sex}.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--sex',choices=['male','female'],required=True)
    parser.add_argument('--stage',choices=['gray','detail','preview','export'],required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    WORK.mkdir(parents=True,exist_ok=True)
    bpy.context.preferences.filepaths.save_version=0
    source=BASE/f'standard_anime_{args.sex}_character_pack.blend' if args.stage=='gray' else WORK/f'cloth_hats_{args.sex}.blend'
    bpy.ops.wm.open_mainfile(filepath=str(source));fit=Fitting(bpy.data.objects['Armature'],args.sex)
    parts=[o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith(PREFIX)]
    if args.stage=='gray':
        assert not parts,'Already authored; export preserves edits'
        parts=build(fit);save(args.sex);preview(fit,parts)
    elif args.stage=='preview':preview(fit,parts)
    else:
        if args.stage=='detail':
            assert not any('PanelSeam' in o.name for o in parts),'Do not overwrite authored details'
            detail(fit,parts);save(args.sex)
        export(fit,parts)
    print('CLOTH_HATS_STAGE_READY',args.sex,args.stage,len(parts),flush=True)


if __name__=='__main__':main()
