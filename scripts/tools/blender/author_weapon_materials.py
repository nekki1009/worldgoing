"""Scoped material variants on each retained native rig; never rebuild old packs.

gray creates geometry; detail assigns packed materials; export preserves edits.
The editor's JSON-compatible OPTIONS block is the only equipment catalogue.
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

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).parent))
from repair_character_audit import tube, box, reset_rig
from build_standard_anime_male_character_pack import create_bone_rigid_component
from medieval_cloth_export import append_cloth

OUT = ROOT/'output/weapon_materials_20260917'
BASE = OUT/'baseline'
WORK = ROOT/'assets/characters/human/q35/weapon_materials'
CATALOG = json.loads((ROOT/'scripts/ui/weapon_materials.gd').read_text(encoding='utf-8').split('const OPTIONS := ',1)[1].split('\n\nconst ATTACKS',1)[0])[:-1]
NEW = [r for r in CATALOG if r['material'] != 'iron' or r['base'] in ('pickaxe_01','tool_hammer_01','shovel_01')]
PREFIXES = tuple(r['prefixes'][0]+'_' for r in NEW)


def material(kind, gray=True):
    name='WeaponMaterial_'+kind
    result=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    result.use_nodes=True
    color,metal,rough={
        'wood':((.27,.125,.039),0,.77), 'wood_edge':((.44,.255,.108),0,.72),
        'stone':((.085,.105,.123),0,.86), 'stone_edge':((.20,.23,.25),0,.74),
        'iron':((.13,.15,.17),.72,.53), 'iron_edge':((.28,.31,.33),.8,.4),
        # Stylized preview has no bright environment map. A controlled diffuse
        # share keeps steel visibly silver without changing scene-wide lighting.
        'steel':((.62,.70,.77),.60,.30), 'steel_edge':((.86,.90,.95),.65,.28),
        'leather':((.055,.027,.013),0,.86), 'cord':((.40,.29,.15),0,.91),
    }[kind]
    if gray: color,metal,rough=(.42,.42,.42),0,.8
    result.diffuse_color=(*color,1)
    shader=result.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value=(*color,1)
    shader.inputs['Metallic'].default_value=metal
    shader.inputs['Roughness'].default_value=rough
    return result


def solid(outline, thickness, chipped=False):
    """Closed beveled blade with real faceted stone edge, not a color swap."""
    bm=bmesh.new()
    center=Vector((sum(x for x,z in outline)/len(outline),sum(z for x,z in outline)/len(outline)))
    edge=[];front=[];back=[]
    for i,(x,z) in enumerate(outline):
        if chipped:
            factor=1.0-(.045 if i%2 else 0)
            x=center.x+(x-center.x)*factor;z=center.y+(z-center.y)*factor
        edge.append(bm.verts.new((x,0,z)))
        point=center+(Vector((x,z))-center)*(.65 if chipped else .82)
        depth=thickness*(.70+.3*math.sin(i*2.4)**2) if chipped else thickness
        front.append(bm.verts.new((point.x,-depth,point.y)))
        back.append(bm.verts.new((point.x,depth,point.y)))
    for side,row in enumerate((front,back)):
        ridge=bm.verts.new((center.x,thickness*(-1 if side==0 else 1)*1.12,center.y))
        for i in range(len(outline)):
            j=(i+1)%len(outline)
            for triangle in ((edge[i],edge[j],row[j]),(edge[i],row[j],row[i])):
                face=bm.faces.new(triangle);face.material_index=1 if i%3 or not chipped else 0
            bm.faces.new((row[i],row[j],ridge))
    return bm


def bind_mesh(arm, name, bm, transform, kind, bone, row):
    bmesh.ops.transform(bm,matrix=transform,verts=bm.verts)
    obj=create_bone_rigid_component(name,bm,material(kind),bone,'weapon',row['id'],arm)
    if kind in ('wood','stone','iron','steel'): obj.data.materials.append(material(kind+'_edge'))
    for polygon in obj.data.polygons: polygon.use_smooth=False
    obj['worldgoing_material']=row['material'];obj['worldgoing_weapon_family']=row['base']
    uv=obj.data.uv_layers.new(name='UVMap')
    # Canonical local X/Z projection gives lengthwise grain on blades and handles.
    inv=transform.inverted()
    for loop in obj.data.loops:
        p=inv@(obj.matrix_world@obj.data.vertices[loop.vertex_index].co)
        uv.data[loop.index].uv=(p.x*5+p.y*3,p.z*2)
    return obj


def transforms(arm):
    palm=arm.data.bones['J_Bip_R_Hand'].matrix_local@Vector((0,.045,-.015))
    rotation=Matrix(((0,-1,0),(0,0,-1),(1,0,0)))
    held=Matrix.Translation(palm-rotation@Vector((0,0,.13)))@rotation.to_4x4()
    old=bpy.data.objects['Weapon_WoodAxe_01_Holstered_Haft']
    points=np.array([old.matrix_world@v.co for v in old.data.vertices])
    center=points.mean(axis=0);_,_,basis=np.linalg.svd(points-center,full_matrices=False)
    direction=Vector(basis[0]);direction*=1 if direction.z>0 else -1
    back=Matrix.Translation(Vector(center)-direction*.38)@Vector((0,0,1)).rotation_difference(direction).to_matrix().to_4x4()
    return held,back


def clone(row, source):
    result=[]
    for old in source:
        obj=old.copy();obj.data=old.data.copy()
        obj.name=old.name.replace(row['source_prefix'],row['prefixes'][0],1)
        bpy.context.collection.objects.link(obj)
        if row['base']=='spear_01' and ('Holstered_Head' in obj.name or 'Holstered_Tassel' in obj.name):
            offset=spear_stow_offset()
            for v in obj.data.vertices:v.co+=obj.matrix_world.inverted().to_3x3()@offset
        obj['worldgoing_visual_id']=row['id'];obj['worldgoing_material']=row['material'];obj['worldgoing_weapon_family']=row['base']
        for i,mat in enumerate(obj.data.materials):
            if row['base'] in ('bow_01','crossbow_01'):continue # Material grade belongs to the projectile head, not the wooden stock.
            label=mat.name.lower()
            if 'steel' in label or 'bevel' in label or 'gold' in label or 'pin' in label:
                kind=row['material']+('_edge' if 'bevel' in label else '')
                if row['material']=='stone' and ('gold' in label or 'pin' in label):kind='wood'
            elif 'wood' in label:kind='wood'
            elif 'grip' in label or 'leather' in label:kind='leather'
            else:kind='cord'
            obj.data.materials[i]=material(kind)
        # Wooden training blades have actual thickness, not a metal razor profile.
        if row['material']=='wood' and obj.name.endswith('_Blade'):
            points=np.array([v.co for v in obj.data.vertices]);center=points.mean(axis=0)
            _,_,basis=np.linalg.svd(points-center,full_matrices=False)
            normal=Vector(basis[-1]);width=float(np.ptp((points-center)@basis[-1]))
            if width<.025:
                for v in obj.data.vertices:v.co+=normal*((v.co-Vector(center)).dot(normal))*(.025/max(width,.001)-1)
        if row['base']=='longsword_01' and row['material']=='stone' and '_Scabbard_' in obj.name:
            points=np.array([v.co for v in obj.data.vertices]);center=Vector(points.mean(axis=0))
            _,_,basis=np.linalg.svd(points-np.array(center),full_matrices=False);axis=Vector(basis[0])
            for v in obj.data.vertices:
                delta=v.co-center;v.co+= (delta-axis*delta.dot(axis))*.65
        obj.hide_render=obj.hide_viewport=False
        result.append(obj)
    return result


def spear_stow_offset():
    shaft=bpy.data.objects['Weapon_Spear_01_Holstered_Shaft']
    head=bpy.data.objects['Weapon_Spear_01_Holstered_Head']
    pts=np.array([shaft.matrix_world@v.co for v in shaft.data.vertices]);center=pts.mean(axis=0)
    _,_,axes=np.linalg.svd(pts-center,full_matrices=False)
    direction=Vector(axes[0]);direction*=1 if direction.z>0 else -1
    end=max(Vector(p).dot(direction) for p in pts)
    start=min((head.matrix_world@v.co).dot(direction) for v in head.data.vertices)
    return direction*(end-start-.014)


def build(arm):
    held,back=transforms(arm);parts=[]
    for entry in NEW:
        row=dict(entry);prefix=row['prefixes'][0]+'_';base=row['base'];kind=row['material']
        oldrow=next((r for r in CATALOG if r['id']==base and r['material']=='iron'),None)
        oldprefix=oldrow['prefixes'][0]
        originals=[o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith(oldprefix+'_')]
        is_tool=base in ('pickaxe_01','tool_hammer_01','shovel_01')
        if not is_tool:
            row['source_prefix']=oldprefix
            copies=clone(row,originals)
            assert copies,(base,kind,'Missing original weapon')
            parts+=copies
            if base=='spear_01' and kind=='stone':
                for obj in [o for o in copies if o.name.endswith('_Tassel')]:
                    copies.remove(obj);parts.remove(obj);bpy.data.objects.remove(obj,do_unlink=True)
        if kind!='stone' and not is_tool:continue
        if base in ('bow_01','crossbow_01'):continue
        if not is_tool:
            # Replace only new variant heads. Original iron meshes stay untouched.
            suffix='_Blade' if base in ('longsword_01','dagger_01','axe_01','wood_axe_01') else '_Head'
            removed=[o for o in copies if o.name.endswith(suffix)]
            for obj in removed:parts.remove(obj);bpy.data.objects.remove(obj,do_unlink=True)
        for holstered,transform in ((False,held),(True,back)):
            if not is_tool and base in ('longsword_01','dagger_01') and holstered:continue # Existing leather sleeve covers the stowed blade.
            if holstered and base=='spear_01':
                # Match the retained spear shaft, not the shorter axe's back socket.
                old=bpy.data.objects['Weapon_Spear_01_Holstered_Head']
                pts=np.array([old.matrix_world@v.co for v in old.data.vertices])
                center=Vector(pts.mean(axis=0));_,_,axes=np.linalg.svd(pts-np.array(center),full_matrices=False)
                center+=spear_stow_offset()
                direction=Vector(axes[0]);direction*=1 if direction.z>0 else -1
                rotation=Vector((0,0,1)).rotation_difference(direction).to_matrix().to_4x4()
                transform=Matrix.Translation(center-rotation.to_3x3()@Vector((0,0,1.78)))@rotation
            name=prefix+('Holstered_' if holstered else '')
            bone='J_Bip_C_UpperChest' if holstered else 'J_Bip_R_Hand'
            if is_tool:
                length={'pickaxe_01':.78,'tool_hammer_01':.48,'shovel_01':1.05}[base]
                bm=bmesh.new();tube(bm,[(0,0,.02),(0,0,length-.09)],.016,14)
                parts.append(bind_mesh(arm,name+'Haft',bm,transform,'wood',bone,row))
                bm=bmesh.new();tube(bm,[(0,0,.025),(0,0,.23)],.0185,14)
                parts.append(bind_mesh(arm,name+'Grip',bm,transform,'leather',bone,row))
            if base=='longsword_01':
                # Wooden core with inset flint teeth; no impossible monolithic stone sword.
                core=solid([(-.025,.19),(-.034,.75),(0,.88),(.034,.75),(.025,.19)],.011)
                parts.append(bind_mesh(arm,name+'Blade_Core',core,transform,'wood',bone,row))
                for side in (-1,1):
                    for index in range(9):
                        z=.24+index*.060
                        reach=.047+.004*math.sin(index*3.7+side)
                        bm=solid([(side*.021,z-.026),(side*.037,z-.028),(side*reach,z-.008),(side*(reach-.005),z+.018),(side*.032,z+.028),(side*.023,z+.024)],.008,True)
                        parts.append(bind_mesh(arm,name+f'Blade_Flint_{side}_{index:02}',bm,transform,'stone',bone,row))
            else:
                outlines={
                    'spear_01':[(-.007,1.63),(-.026,1.70),(-.030,1.79),(-.023,1.86),(0,1.93),(.021,1.86),(.029,1.78),(.024,1.69),(.007,1.63)],
                    'dagger_01':[(-.010,.18),(-.027,.24),(-.032,.31),(-.021,.42),(0,.50),(.020,.43),(.029,.33),(.025,.25),(.012,.18)],
                    'axe_01':[(.025,.60),(-.065,.58),(-.155,.54),(-.204,.61),(-.222,.69),(-.192,.77),(-.074,.74),(.024,.73)],
                    'wood_axe_01':[(.025,.58),(-.075,.57),(-.196,.56),(-.227,.62),(-.221,.71),(-.186,.77),(-.060,.73),(.024,.70)],
                    'hammer_01':[(-.15,.62),(-.16,.74),(-.10,.78),(.075,.77),(.10,.72),(.088,.64),(.04,.61)],
                    'pickaxe_01':[(-.28,.66),(-.20,.74),(-.04,.78),(.04,.78),(.21,.74),(.28,.65),(.19,.70),(.035,.715),(-.035,.715),(-.19,.70)],
                    'tool_hammer_01':[(-.095,.37),(-.095,.46),(.075,.46),(.089,.445),(.089,.386),(.07,.37)],
                    'shovel_01':[(-.02,.88),(-.075,.89),(-.101,1.00),(-.086,1.13),(0,1.17),(.086,1.13),(.101,1.00),(.075,.89),(.02,.88)],
                }
                depth=.037 if 'hammer' in base else .023 if kind=='stone' else .012 if kind=='wood' else .009
                bm=solid(outlines[base],depth,kind=='stone')
                parts.append(bind_mesh(arm,name+('Blade' if base in ('dagger_01','axe_01','wood_axe_01','shovel_01') else 'Head'),bm,transform,kind,bone,row))
            if kind=='stone':
                z={'longsword_01':.20,'spear_01':1.64,'dagger_01':.19,'axe_01':.66,'wood_axe_01':.64,'hammer_01':.69,'pickaxe_01':.74,'tool_hammer_01':.414,'shovel_01':.92}[base]
                bm=bmesh.new()
                wide=base in ('axe_01','wood_axe_01','hammer_01','pickaxe_01','tool_hammer_01')
                for index in range(5):
                    points=[((.047 if wide else .021)*math.cos(t)-(.015 if wide else 0),(.040 if 'hammer' in base else .025)*math.sin(t),z-.024+index*.012) for t in np.linspace(0,math.tau,25)]
                    tube(bm,points,.003,6)
                parts.append(bind_mesh(arm,name+'Grip_Bindings',bm,transform,'cord',bone,row))
    return parts


def detail(parts):
    for kind in ('wood','wood_edge','stone','stone_edge','iron','iron_edge','steel','steel_edge','leather','cord'):
        mat=material(kind,False)
        if kind not in ('wood','wood_edge','stone','stone_edge'):continue
        size=256; y,x=np.mgrid[0:size,0:size]/size
        if kind.startswith('wood'):
            pattern=.82+.12*np.sin((x*28+.16*np.sin(y*math.tau*2))*math.tau)+.035*np.sin(x*math.tau*111+y*11)
        else:
            pattern=.89+.055*np.random.default_rng(417).normal(size=(size,size))+.025*np.sin(x*23+np.sin(y*29)*2)
        pixels=np.ones((size,size,4),np.float32)
        pixels[:,:,:3]=np.array(mat.diffuse_color[:3])[None,None,:]*pattern[:,:,None]
        img=bpy.data.images.new(mat.name+'_Pattern',width=size,height=size)
        img.pixels.foreach_set(pixels.ravel());img.pack()
        tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=img
        mat.node_tree.links.new(tex.outputs['Color'],mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    for obj in parts:
        if obj.data.uv_layers:continue
        uv=obj.data.uv_layers.new(name='UVMap')
        points=np.array([v.co for v in obj.data.vertices]);center=points.mean(axis=0)
        _,_,basis=np.linalg.svd(points-center,full_matrices=False)
        for loop in obj.data.loops:
            delta=np.array(obj.data.vertices[loop.vertex_index].co)-center
            uv.data[loop.index].uv=(float(delta@basis[1])*5,float(delta@basis[0])*2)


def save(sex):
    temporary=ROOT/f'.godot-temp/weapon_materials_{sex}_{uuid.uuid4().hex}.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(temporary))
    shutil.copy2(temporary,WORK/f'weapon_materials_{sex}.blend')
    for attempt in range(6):
        try:temporary.unlink();break
        except PermissionError:
            if attempt==5:raise
            time.sleep(.3)


def preview(arm,parts,sex):
    reset_rig(arm);scene=bpy.context.scene
    scene.render.engine='BLENDER_WORKBENCH'
    scene.display.shading.light='STUDIO';scene.display.shading.color_type='MATERIAL';scene.display.shading.show_cavity=True
    scene.render.resolution_x=1200;scene.render.resolution_y=900;scene.render.resolution_percentage=100
    data=bpy.data.cameras.new('MaterialReview');camera=bpy.data.objects.new('MaterialReview',data)
    scene.collection.objects.link(camera);scene.camera=camera;data.type='ORTHO'
    for row in NEW:
        if row['material']!='stone':continue
        selected=[o for o in parts if o.name.startswith(row['prefixes'][0]+'_') and not any(s in o.name for s in ('Holstered','Sheathed','Scabbard'))]
        points=[o.matrix_world@v.co for o in selected for v in o.data.vertices]
        low=Vector(tuple(min(p[i] for p in points) for i in range(3)));high=Vector(tuple(max(p[i] for p in points) for i in range(3)))
        target=(low+high)*.5;data.ortho_scale=max(high-low)*1.45
        for obj in bpy.data.objects:
            if obj.type=='MESH':obj.hide_render=obj not in selected
        for label,direction in [('front',(3,-1,1)),('side',(0,-4,1)),('back',(-3,1,1)),('threequarter',(3,-3,2))]:
            camera.location=target+Vector(direction)
            camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
            scene.render.filepath=str(OUT/f'{sex}_{row["id"]}_gray_{label}.png')
            bpy.ops.render.render(write_still=True)


def export(arm,parts,sex):
    reset_rig(arm);bpy.ops.object.select_all(action='DESELECT')
    for obj in [arm]+parts:obj.hide_viewport=False;obj.hide_set(False);obj.select_set(True)
    subset=WORK/f'subset_{sex}.glb'
    bpy.ops.export_scene.gltf(filepath=str(subset),export_format='GLB',use_selection=True,export_animations=False,export_skins=True,export_morph=True,export_apply=False,export_try_sparse_sk=False)
    stem=f'standard_anime_{sex}_character_pack'
    aliases={row['prefixes'][0]+'_String':'Weapon_Bow_01_String' for row in NEW if row['base']=='bow_01'}
    append_cloth(BASE/f'{stem}.glb',subset,WORK/f'candidate_{sex}.glb',{},'Weapon_',aliases)
    metadata=json.loads((BASE/f'{stem}.json').read_text(encoding='utf-8'))
    metadata['parts']['weapon']+=sorted(o.name for o in parts)
    metadata['weapon_materials']={'catalogue':'scripts/ui/weapon_materials.gd','materials':['wood','stone','iron','steel'],'existing_weapons':'iron','reference':'output/weapon_materials_20260917/reference/material_board.png','balance':'unchanged'}
    (WORK/f'candidate_{sex}.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--sex',choices=['male','female'],required=True)
    parser.add_argument('--stage',choices=['gray','detail','preview','export','probe'],required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);WORK.mkdir(parents=True,exist_ok=True)
    bpy.context.preferences.filepaths.save_version=0
    source=BASE/f'standard_anime_{args.sex}_character_pack.blend' if args.stage in ('gray','probe') else WORK/f'weapon_materials_{args.sex}.blend'
    bpy.ops.wm.open_mainfile(filepath=str(source));arm=bpy.data.objects['Armature']
    if args.stage=='probe':
        for obj in bpy.data.objects:
            if obj.name.startswith('Weapon_'):
                print(obj.name, list(obj.vertex_groups.keys()),tuple(obj.dimensions),dict(obj),flush=True)
        return
    parts=[o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith(PREFIXES)]
    if args.stage=='gray':
        assert not parts,'Variants already present in baseline'
        reset_rig(arm);parts=build(arm);save(args.sex);preview(arm,parts,args.sex)
    elif args.stage=='preview':preview(arm,parts,args.sex)
    else:
        if args.stage=='detail':detail(parts);save(args.sex)
        export(arm,parts,args.sex)
    print('WEAPON_MATERIAL_STAGE_READY',args.sex,args.stage,len(parts),flush=True)


if __name__=='__main__':main()
