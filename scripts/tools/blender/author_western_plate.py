"""Explicit Western plate art stages; add only to the immutable current pack.

gray rebuilds shape; detail adds finish; export keeps hand-edited source geometry.
The regular builders load the authored parts instead of recreating them.
"""
import copy
import json
import math
import struct
import sys
import shutil
import hashlib
import uuid
from pathlib import Path
import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector, Quaternion
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).parent))
sys.path.insert(0, str(ROOT / 'scripts/tests'))
from author_chinese_leather_mingguang import Fitting, mesh_part as fitted_mesh
from build_standard_anime_male_character_pack import copy_mesh
from repair_character_audit import reset_rig
from validate_chinese_cloak_assets import read_glb, accessor

BASE = ROOT / '.godot-temp/western_plate_20260913/baseline'
WORK = ROOT / 'assets/characters/human/q35/western_plate'
QA = ROOT / 'output/western_plate_20260913'
PREFIXES = ('Armor_Western_Iron_01_', 'Helmet_Western_Iron_01_', 'Boots_Western_Iron_01_')
IDS = ('armor_western_iron_01', 'helmet_western_iron_01', 'boots_western_iron_01')
SLOTS = ('armor', 'helmet', 'boots')
A, H, B = PREFIXES


def material(name, color, metallic=0, roughness=.55):
    mat = bpy.data.materials.get('WesternPlate_' + name) or bpy.data.materials.new('WesternPlate_' + name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    return mat


def tag(obj):
    i = next(i for i, prefix in enumerate(PREFIXES) if obj.name.startswith(prefix))
    obj['worldgoing_component_slot'] = SLOTS[i]
    obj['worldgoing_visual_id'] = IDS[i]
    obj['western_plate_revision'] = 1
    return obj


def part(name, vertices, faces, mat, fit, bone='J_Bip_C_UpperChest', weights=None, uvs=None, thickness=.004):
    return tag(fitted_mesh(name, vertices, faces, mat, fit, bone, weights, uvs, thickness))


def surface(name, fn, mat, fit, bone='J_Bip_C_UpperChest', weights=None, rows=8, cols=32, thickness=.004):
    points = [fn(c / cols, r / rows) for r in range(rows + 1) for c in range(cols + 1)]
    faces = []
    for r in range(rows):
        for c in range(cols):
            i = r * (cols + 1) + c
            faces.append((i, i + 1, i + cols + 2, i + cols + 1))
    uvs = [(c / cols, r / rows) for r in range(rows + 1) for c in range(cols + 1)]
    obj = part(name, points, faces, mat, fit, bone, weights, uvs, thickness)
    obj['western_rims'] = json.dumps([[list(p) for p in points[:cols+1]], [list(p) for p in points[-cols-1:]]])
    return obj


def clone(source, name, mat):
    obj = copy_mesh(source, name, '', '')
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for face in obj.data.polygons:
        face.material_index = 0
    return tag(obj)


def source_weights(obj):
    """Keep trim and footwear on their own source surface, never the opposite leg."""
    kd = KDTree(len(obj.data.vertices))
    for vertex in obj.data.vertices:
        kd.insert(obj.matrix_world @ vertex.co, vertex.index)
    kd.balance()
    def weights(point):
        result = {}
        for _, index, distance in kd.find_n(point, 4):
            for group in obj.data.vertices[index].groups:
                name = obj.vertex_groups[group.group].name
                result[name] = result.get(name, 0) + group.weight / max(distance, .001)**2
        result = dict(sorted(result.items(), key=lambda item: -item[1])[:4])
        total = sum(result.values())
        assert total > 0, obj.name
        return {name: value / total for name, value in result.items()}
    return weights


def torso_weights(fit, point):
    # A cuirass cannot follow nearby upper-arm vertices at the armpit.
    weights = {name: value for name, value in fit.weights(point).items() if name.startswith('J_Bip_C_')}
    total = sum(weights.values())
    return {name: value / total for name, value in weights.items()} if total else {'J_Bip_C_UpperChest': 1.0}


def inspection(fit):
    return {
        'sex': fit.sex, 'body_bounds': [list(np.min(fit.points, axis=0)), list(np.max(fit.points, axis=0))],
        'bones': {b.name: list(fit.bone(b.name)) for b in fit.arm.data.bones if b.name.startswith('J_Bip_') and not any(s in b.name for s in ['Thumb','Index','Middle','Ring','Little'])},
        'profiles': list(zip(fit.levels.tolist(), fit.profiles.tolist())),
        'cloth_sources': [o.name for o in bpy.data.objects if o.type == 'MESH' and any(s in o.name for s in ['Pants','UnderTunic','Boots_Chinese_Leather_01','Face_01'])],
        'foot_probe': {o.name: {'shape_keys': [k.name for k in o.data.shape_keys.key_blocks] if o.data.shape_keys else [], 'modifiers': [(m.name,m.type) for m in o.modifiers], 'bounds': [list(np.min([o.matrix_world@v.co for v in o.data.vertices],axis=0)),list(np.max([o.matrix_world@v.co for v in o.data.vertices],axis=0))]} for o in bpy.data.objects if o.type=='MESH' and o.name in ['Boots_Chinese_Leather_01_Main_L','Face_Standard_01']},
    }


def limb_surface(fit, first, last, start, end, offset, angular=math.pi):
    """Measured body sections, in a plane perpendicular to the real limb axis."""
    a, b = fit.bone(first), fit.bone(last)
    axis = (b-a).normalized()
    forward = Vector((0,-1,0))
    across = axis.cross(forward).normalized()
    def point(u,v):
        center = a.lerp(b, start + (end-start)*v)
        angle = (u-.5)*2*angular
        direction = forward*math.cos(angle) + across*math.sin(angle)
        # Cast from outside toward the axis; this measures skin, not a nominal cylinder.
        hit, _, _, _ = fit.bvh.ray_cast(center + direction*.24, -direction, .24)
        radius = max(.027, (hit-center).dot(direction) if hit is not None else .035)
        return center + direction*(radius+offset)
    return point


def build_cuirass(fit, iron):
    hip, neck = fit.hip, fit.neck
    waist = hip+.105
    # A continuous broad convex shell, including the female chest; no breast cups.
    def torso(u,v):
        angle = math.tau*u
        top = neck-.037-.077*abs(math.sin(angle))**3
        z = waist+(top-waist)*v
        p = fit.torso(angle,z,.016 if fit.sex=='female' else .008)
        if math.cos(angle)>0:
            ridge=.010 if fit.sex=='female' else .004
            p.y -= ridge*(1-abs(math.sin(angle)))*math.sin(math.pi*(.12+.80*v))
        return p
    return surface(A+'Cuirass',torso,iron,fit,weights=lambda p: torso_weights(fit,p),rows=20,cols=64,thickness=.004)


def build(fit):
    iron = material('ForgedIron',(.14,.15,.16),.55,.80)
    cloth = material('Padding',(.042,.048,.055),0,.87)
    leather = material('Leather',(.065,.045,.029),0,.72)
    from author_chinese_lining import shirt
    inner, _ = shirt(fit,cloth)
    inner.name = A+'UnderShirt'
    tag(inner)
    parts = [inner, clone(bpy.data.objects['Armor_Iron_01_Underlayer_Pants'],A+'UnderPants',cloth), build_cuirass(fit,iron)]
    hip, neck = fit.hip, fit.neck
    waist = hip+.105
    neckcenter = fit.bone('J_Bip_C_Neck')
    def gorget(u,v):
        a = math.tau*u
        return neckcenter + Vector((math.sin(a)*(.077+.021*(1-v)), -math.cos(a)*(.077+.030*(1-v)), -.047+.047*v))
    parts.append(surface(A+'Gorget',gorget,iron,fit,rows=4,cols=48))
    for tier in range(3):
        top = waist+.020-tier*.038
        def fauld(u,v,top=top,tier=tier):
            z = top-.049*v
            return fit.torso(math.tau*u,z,.023+.009*v+.004*tier)
        parts.append(surface(A+f'Fauld_{tier}',fauld,iron,fit,'J_Bip_C_Hips',rows=4,cols=64))
    for side, sign in [('L',1),('R',-1)]:
        upper, lower, hand = ['J_Bip_'+side+'_'+s for s in ['UpperArm','LowerArm','Hand']]
        thigh, knee, foot = ['J_Bip_'+side+'_'+s for s in ['UpperLeg','LowerLeg','Foot']]
        shoulder, elbow = fit.bone(upper), fit.bone(lower)
        # Top/side cap and lames follow the upper-arm rest anchor, not the chest.
        for tier in range(3):
            def pauldron(u,v,tier=tier):
                x = shoulder.x+sign*(-.025+.067*tier+.091*v)
                t = min(1,abs(x-shoulder.x)/abs(elbow.x-shoulder.x))
                center = shoulder.lerp(elbow,t)
                radius = .020+.078*math.sin(math.pi*v*.5) if tier==0 else .091-.015*tier+.006*math.sin(math.pi*v)
                a = -.10+(math.pi+.20)*u
                return Vector((x,center.y-radius*math.cos(a),center.z+radius*math.sin(a)))
            parts.append(surface(A+f'Pauldron_{tier}_{side}',pauldron,iron,fit,upper,rows=6,cols=28))
        parts.append(surface(A+'Rerebrace_'+side,limb_surface(fit,upper,lower,.53,.86,.014),iron,fit,upper,rows=8,cols=40))
        parts.append(surface(A+'Vambrace_'+side,limb_surface(fit,lower,hand,.22,.83,.004),iron,fit,lower,rows=12,cols=40,thickness=.003))
        # Front cop with a visible point and rear opening for flexion.
        def elbowcop(u,v):
            a=(u-.5)*math.pi*1.30
            r=math.sin(math.pi*(.06+.88*v))
            return elbow+Vector((sign*(v-.5)*.090,-math.cos(a)*(.043+.020*r),math.sin(a)*(.052+.014*r)))
        parts.append(surface(A+'Couter_'+side,elbowcop,iron,fit,lower,rows=10,cols=24))
        def tasset(u,v):
            angle=sign*(.16+.93*u)
            z=hip+.012-.155*v+.012*abs(u-.5)
            p=fit.torso(angle,max(hip+.025,z),.036+.014*v)
            p.z=z
            return p
        parts.append(surface(A+'Tasset_'+side,tasset,iron,fit,thigh,rows=8,cols=20))
        parts.append(surface(A+'Cuisse_'+side,limb_surface(fit,thigh,knee,.22,.85,.019,math.pi*.77),iron,fit,thigh,rows=14,cols=36))
        kneecenter=fit.bone(knee)
        def poleyn(u,v):
            a=(u-.5)*math.pi*1.28
            bell=math.sin(math.pi*v)
            return kneecenter+Vector((math.sin(a)*(.026+.041*bell),-.060-math.cos(a)*(.010+.026*bell),(v-.5)*.12))
        parts.append(surface(A+'Poleyn_'+side,poleyn,iron,fit,knee,rows=10,cols=32))
        # Reuse the measured native-foot loft and its same-side skin transfer.
        from author_chinese_leather_boots import loft_boot, reweight
        boots=loft_boot(fit,side,sign,fit.knee-.068,leather,leather,leather)
        for boot in boots:
            suffix=boot.name.removeprefix('Boots_Chinese_Leather_01_').split('.')[0]
            boot.name=B+'Inner'+suffix
            tag(boot)
        reweight(fit,boots)
        parts.extend(boots)
        parts.append(surface(B+'Greave_'+side,limb_surface(fit,knee,foot,.13,.85,.023,math.pi*.94),iron,fit,knee,rows=18,cols=48))
        shoe = bpy.data.objects[B+'InnerMain_'+side]
        shoe_weights = source_weights(shoe)
        pts = [shoe.matrix_world@v.co for v in shoe.data.vertices]
        bvh = BVHTree.FromPolygons(pts,[tuple(p.vertices) for p in shoe.data.polygons])
        ankle = fit.bone(foot)
        toe = min(p.y for p in pts)
        for tier in range(5):
            y0 = toe+.016+(ankle.y-toe-.115)*tier/5
            y1 = toe+.016+(ankle.y-toe-.115)*(tier+1)/5+.006
            def sabaton(u,v,y0=y0,y1=y1):
                y=y0+(y1-y0)*v
                row=[p for p in pts if abs(p.y-y)<.018 and p.z<ankle.z+.025]
                width=max([abs(p.x-ankle.x) for p in row],default=.037)
                x=ankle.x+(u-.5)*2*width*.78
                # Begin above the entire boot, never inside its open shaft.
                hit,_,_,_=bvh.ray_cast(Vector((x,y,fit.knee+.10)),Vector((0,0,-1)),fit.knee+.20)
                z=hit.z+.010 if hit is not None else .036
                return Vector((x,y,z))
            parts.append(surface(B+f'Sabaton_{tier}_{side}',sabaton,iron,fit,foot,weights=shoe_weights,rows=4,cols=20))
        def ankleplate(u,v):
            z=ankle.z-.035+.120*v
            axispoint=ankle.lerp(fit.bone(knee),max(0,(z-ankle.z)/(fit.knee-ankle.z)))
            x=axispoint.x+(u-.5)*(.049 if fit.sex=='female' else .062)
            hit,_,_,_=bvh.ray_cast(Vector((x,-.5,z)),Vector((0,1,0)),.8)
            assert hit is not None,('ankle plate misses shoe',x,z)
            return hit+Vector((0,-.009,0))
        parts.append(surface(B+'AnklePlate_'+side,ankleplate,iron,fit,foot,weights=shoe_weights,rows=10,cols=16))
    # Helmet follows each sex's actual head envelope, with an open face and rear tail.
    head = fit.bone('J_Bip_C_Head')
    headpoints=fit.points+[obj.matrix_world@v.co for obj in bpy.data.objects if obj.type=='MESH' and obj.name=='Face_Standard_01' for v in obj.data.vertices]
    points=[p for p in headpoints if p.z>head.z+.07 and abs(p.x)<.20]
    top=max(p.z for p in points)+.016
    rx=max(abs(p.x-head.x) for p in points)+.013
    front=min(p.y for p in points)-.013
    back=max(p.y for p in points)+.018
    cy=(front+back)/2
    def helmet(u,v):
        a=math.tau*u
        rim=head.z+.100-.055*max(0,-math.cos(a))
        theta=math.pi*.5*(.025+.975*v)
        radius=math.sin(theta)
        return Vector((head.x+rx*math.sin(a)*radius,cy-(back-front)/2*math.cos(a)*radius,top+(rim-top)*(1-math.cos(theta))))
    parts.append(surface(H+'Skull',helmet,iron,fit,'J_Bip_C_Head',rows=20,cols=64))
    def necktail(u,v):
        a=math.pi*.48+math.pi*1.04*u
        p=helmet(a/math.tau,1)
        p+=Vector((math.sin(a)*.020*v,-math.cos(a)*.037*v,-.050*v))
        return p
    parts.append(surface(H+'NeckTail',necktail,iron,fit,'J_Bip_C_Head',rows=5,cols=36))
    return parts


def render_gray(fit, parts):
    scene=bpy.context.scene
    reset_rig(fit.arm)
    for obj in scene.objects:
        if obj.type=='MESH':
            obj.hide_render=not(obj in parts or obj==fit.body or obj.name.startswith('Face_') and '01' in obj.name)
    data=bpy.data.cameras.new('WesternReview')
    camera=bpy.data.objects.new('WesternReview',data)
    scene.collection.objects.link(camera)
    scene.camera=camera
    data.type='ORTHO'; data.ortho_scale=2.13
    scene.render.engine='BLENDER_WORKBENCH'
    scene.display.shading.light='STUDIO'
    scene.display.shading.color_type='OBJECT'
    for obj in scene.objects:
        if obj.type=='MESH':
            obj.color=(.44,.44,.44,1) if obj in parts else (.74,.74,.74,1)
    scene.display.shading.show_cavity=True
    scene.render.resolution_x=scene.render.resolution_y=1200
    scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG'
    destination=QA/'blender_gray';destination.mkdir(exist_ok=True)
    target=Vector((0,0,.89 if fit.sex=='male' else .82))
    for label,angle in [('front',0),('back',180),('side',90),('three_quarter',35)]:
        a=math.radians(angle)
        camera.location=target+Vector((math.sin(a)*5,-math.cos(a)*5,0))
        camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(destination/f'{fit.sex}_{label}.png')
        bpy.ops.render.render(write_still=True)
    for obj in scene.objects:
        if obj.type=='MESH': obj.hide_render=not(obj in parts and obj.name.startswith(B))
    target=Vector((0,0,.27));data.ortho_scale=.70
    camera.location=target+Vector((2,-4,.30))
    camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(destination/f'{fit.sex}_boots_isolated.png')
    bpy.ops.render.render(write_still=True)
    for token in ['InnerMain','Sabaton']:
        for obj in scene.objects:
            if obj.type=='MESH': obj.hide_render=not(obj in parts and token in obj.name)
        scene.render.filepath=str(destination/f'{fit.sex}_{token}_isolated.png')
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(camera,do_unlink=True)


def finish(fit, parts):
    from repair_character_audit import tube
    trim=material('IronRolledEdge',(.20,.21,.22),.60,.72)
    additions=[]
    for obj in parts:
        if 'western_rims' not in obj: continue
        bm=bmesh.new()
        paths=json.loads(obj['western_rims'])
        for points in paths:
            # Shared tube helper; real rolled edges and small rivets, no texture claims.
            tube(bm,[Vector(p) for p in points],.0018,6)
        for p in paths[-1][2:-2:8]:
            bmesh.ops.create_uvsphere(bm,u_segments=8,v_segments=4,radius=.0034,matrix=Matrix.Translation(Vector(p)))
        mesh=bpy.data.meshes.new('WesternTrimTemporary');bm.to_mesh(mesh);bm.free()
        vertices=[v.co.copy() for v in mesh.vertices];faces=[tuple(p.vertices) for p in mesh.polygons]
        groups=[g.name for g in obj.vertex_groups]
        additions.append(part(obj.name+'_RolledEdge',vertices,faces,trim,fit,groups[0],source_weights(obj) if len(groups)>1 else None,thickness=0))
        bpy.data.meshes.remove(mesh)
    return parts+additions


def append_glb(source, subset, destination):
    """Append only new mesh nodes; keep every pre-existing byte and descriptor."""
    doc, raw=read_glb(source); new, addition=read_glb(subset)
    binary=bytearray(raw); copied={}; mats={}
    def copy_accessor(index):
        if index in copied:return copied[index]
        acc=copy.deepcopy(new['accessors'][index]);assert 'sparse' not in acc
        view=copy.deepcopy(new['bufferViews'][acc['bufferView']]);start=view.get('byteOffset',0)
        binary.extend(b'\0'*(-len(binary)%4));view['byteOffset']=len(binary)
        binary.extend(addition[start:start+view['byteLength']])
        acc['bufferView']=len(doc['bufferViews']);doc['bufferViews'].append(view)
        copied[index]=len(doc['accessors']);doc['accessors'].append(acc)
        return copied[index]
    names={n['name']:i for i,n in enumerate(doc['nodes'])}
    oldskin=doc['skins'][0]
    joints=[doc['nodes'][i]['name'] for i in oldskin['joints']]
    parent=next(i for i,n in enumerate(doc['nodes']) if any('mesh' in doc['nodes'][c] for c in n.get('children',[])))
    for node in new['nodes']:
        if 'mesh' not in node:continue
        assert node['name'].startswith(PREFIXES) and node['name'] not in names,node['name']
        skin=new['skins'][node['skin']]
        assert joints==[new['nodes'][i]['name'] for i in skin['joints']]
        assert np.allclose(accessor(doc,raw,oldskin['inverseBindMatrices']),accessor(new,addition,skin['inverseBindMatrices']),atol=1e-6)
        mesh=copy.deepcopy(new['meshes'][node['mesh']])
        for primitive in mesh['primitives']:
            assert not primitive.get('targets'),'No morph authoring in this armor stage'
            primitive['attributes']={k:copy_accessor(v) for k,v in primitive['attributes'].items()}
            primitive['indices']=copy_accessor(primitive['indices'])
            index=primitive['material']
            if index not in mats:
                mat=copy.deepcopy(new['materials'][index])
                assert 'Texture' not in json.dumps(mat),'Solid material route only'
                mats[index]=len(doc['materials']);doc['materials'].append(mat)
            primitive['material']=mats[index]
        added=copy.deepcopy(node);added['skin']=0;added['mesh']=len(doc['meshes'])
        doc['meshes'].append(mesh)
        doc['nodes'][parent]['children'].append(len(doc['nodes']));doc['nodes'].append(added)
    binary.extend(b'\0'*(-len(binary)%4));doc['buffers'][0]['byteLength']=len(binary)
    encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4)
    destination.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(binary))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+struct.pack('<I4s',len(binary),b'BIN\0')+binary)


def export(fit, parts):
    candidate=ROOT/'.godot-temp/western_plate_20260913/candidate'
    candidate.mkdir(exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [fit.arm,*parts]:
        obj.hide_set(False);obj.hide_viewport=False;obj.hide_render=False;obj.select_set(True)
    bpy.context.view_layer.objects.active=fit.arm
    subset=candidate/f'{fit.sex}_subset.glb'
    bpy.ops.export_scene.gltf(filepath=str(subset),export_format='GLB',use_selection=True,export_animations=False,export_skins=True,export_morph=False,export_apply=False)
    append_glb(BASE/f'standard_anime_{fit.sex}_character_pack.glb',subset,candidate/f'{fit.sex}.glb')
    if fit.arm.get('western_iron_axe_clearance'):
        from author_weapon_refresh import splice
        bpy.ops.object.select_all(action='DESELECT')
        fit.arm.select_set(True)
        bpy.data.objects[A+'Cuirass'].select_set(True)
        animation_subset=candidate/f'{fit.sex}_clearance.glb'
        bpy.ops.export_scene.gltf(filepath=str(animation_subset),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=False,export_optimize_disable_viewport=True,export_skins=True,export_morph=False,export_apply=False)
        corrected=candidate/f'{fit.sex}_corrected.glb'
        splice(candidate/f'{fit.sex}.glb',animation_subset,corrected,{'attack_axe':['J_Bip_L_LowerArm','J_Bip_L_Hand']},skip_meshes=True)
        shutil.copy2(corrected,candidate/f'{fit.sex}.glb')
        corrected.unlink()
    metadata=json.loads((BASE/f'standard_anime_{fit.sex}_character_pack.json').read_text(encoding='utf-8'))
    for slot,prefix in zip(SLOTS,PREFIXES):
        metadata['parts'][slot]+=sorted(o.name for o in parts if o.name.startswith(prefix))
    metadata['western_plate']={'revision':1,'material':'iron','source':f'res://assets/characters/human/q35/western_plate/western_plate_{fit.sex}.blend','reference':'res://output/western_plate_20260913/reference/western_iron_reference.png'}
    if fit.arm.get('western_iron_axe_clearance'):
        metadata['western_plate']['male_axe_shield_clearance']={'clip':'attack_axe','bones':['J_Bip_L_LowerArm','J_Bip_L_Hand'],'outward_degrees':35}
    (candidate/f'{fit.sex}.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('WESTERN_PLATE_EXPORTED',fit.sex,len(parts))


def main(sex, stage):
    WORK.mkdir(parents=True, exist_ok=True)
    QA.mkdir(parents=True, exist_ok=True)
    source = WORK / f'western_plate_{sex}.blend'
    bpy.ops.wm.open_mainfile(filepath=str(BASE / f'standard_anime_{sex}_character_pack.blend' if stage in ['inspect', 'gray', 'loader'] else source))
    arm = bpy.data.objects['Armature']
    reset_rig(arm)
    fit = Fitting(arm, sex)
    if stage == 'loader':
        from load_authored_western_plate import load_western_iron
        original = {o.name: o.as_pointer() for o in bpy.data.objects}
        actions = {a.name: a.as_pointer() for a in bpy.data.actions}
        groups = load_western_iron(arm, is_female=sex=='female')
        for group in groups:
            for obj in group:
                assert obj.parent == arm and obj.data.uv_layers
                assert all(m.object == arm for m in obj.modifiers if m.type == 'ARMATURE')
                assert all(abs(sum(g.weight for g in v.groups)-1)<1e-5 for v in obj.data.vertices)
        assert all(bpy.data.objects[name].as_pointer()==pointer for name,pointer in original.items())
        assert actions=={a.name:a.as_pointer() for a in bpy.data.actions}
        print('WESTERN_IRON_LOADER_PASS',sex,[len(g) for g in groups],'; original objects and actions untouched')
        return
    if stage == 'inspect':
        info = inspection(fit)
        (QA / f'{sex}_fit.json').write_text(json.dumps(info, indent=2), encoding='utf-8')
        print(json.dumps(info, indent=2))
        return
    parts=[o for o in bpy.data.objects if o.type=='MESH' and o.name.startswith(PREFIXES)]
    if stage=='preview':
        render_gray(fit,parts)
        return
    if stage=='gray':
        assert not parts,'Baseline must not contain the new option'
        parts=build(fit)
        render_gray(fit,parts)
    elif stage=='detail':
        assert not any(o.name.endswith('_RolledEdge') for o in parts),'Detail already authored; use export to preserve edits'
        parts=finish(fit,parts)
    elif stage=='cuirass':
        for name in [A+'Cuirass',A+'Cuirass_RolledEdge']:
            obj=bpy.data.objects[name]
            parts.remove(obj)
            bpy.data.objects.remove(obj,do_unlink=True)
        cuirass=build_cuirass(fit,bpy.data.materials['WesternPlate_ForgedIron'])
        parts.append(cuirass)
        render_gray(fit,parts)
        parts.remove(cuirass)
        parts.extend(finish(fit,[cuirass]))
    elif stage=='refine':
        cuirass = bpy.data.objects[A+'Cuirass']
        for obj in [cuirass, bpy.data.objects[A+'Cuirass_RolledEdge']]:
            obj.vertex_groups.clear()
            for vertex in obj.data.vertices:
                for name, value in torso_weights(fit, obj.matrix_world @ vertex.co).items():
                    group = obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
                    group.add([vertex.index],value,'REPLACE')
    elif stage=='shield_clearance':
        assert sex=='male' and not arm.get('western_iron_axe_clearance')
        action=bpy.data.actions['attack_axe']
        arm.animation_data.action=action
        first,last=map(float,action.frame_range)
        names=['J_Bip_L_LowerArm','J_Bip_L_Hand']
        outward=Quaternion(Vector((0,0,1)),math.radians(35))
        poses=[]
        for frame in np.linspace(first,last,round((last-first)*5)+1):
            bpy.context.scene.frame_set(int(frame),subframe=frame%1)
            bpy.context.view_layer.update()
            rotations={name:arm.pose.bones[name].matrix.to_quaternion() for name in names}
            for name in names:
                bone=arm.pose.bones[name]
                bone.matrix=Matrix.LocRotScale(bone.head.copy(),outward@rotations[name],None)
                bpy.context.view_layer.update()
            poses.append((frame,{name:arm.pose.bones[name].matrix_basis.copy() for name in names}))
        for curve in list(action.fcurves):
            if any(curve.data_path.startswith('pose.bones["'+name+'"]') for name in names):action.fcurves.remove(curve)
        for frame,pose in poses:
            for name,matrix in pose.items():
                bone=arm.pose.bones[name]
                bone.rotation_mode='QUATERNION';bone.matrix_basis=matrix
                for path in ['location','rotation_quaternion','scale']:bone.keyframe_insert(path,frame=float(frame),group=name)
        for curve in action.fcurves:
            if any(curve.data_path.startswith('pose.bones["'+name+'"]') for name in names):
                for key in curve.keyframe_points:key.interpolation='LINEAR'
        arm['western_iron_axe_clearance']=True
        reset_rig(arm)
    elif stage!='export':
        raise ValueError(stage)
    for obj in parts:
        obj.hide_render=False;obj.hide_viewport=False;obj.hide_set(False)
    # Publish only after Blender closes its intermediate file; Dropbox can lock
    # version-backup renames on a source opened from the synchronized folder.
    temporary = ROOT / '.godot-temp/western_plate_20260913' / f'{sex}_{uuid.uuid4().hex}.blend'
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(temporary))
    shutil.copy2(temporary, source)
    with temporary.open('rb') as before, source.open('rb') as after:
        assert hashlib.file_digest(before, 'sha256').digest() == hashlib.file_digest(after, 'sha256').digest()
    temporary.unlink()
    if stage in ['detail','export','refine','cuirass','shield_clearance']:
        export(fit,parts)
    print('WESTERN_PLATE_STAGE_PASS',sex,stage,len(parts))


if __name__ == '__main__':
    main(*sys.argv[sys.argv.index('--') + 1:])
