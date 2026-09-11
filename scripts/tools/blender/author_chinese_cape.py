"""Explicit art authoring, never invoked by production builders.

Blender --background --python author_chinese_cape.py -- --sex male --stage gray
The scoped baseline is immutable; intermediate work stays outside the live pack.
"""
import argparse
import copy
import json
import math
import struct
import sys
from pathlib import Path
import bpy
import bmesh
import numpy as np
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).parent))
from load_authored_chinese_cape import PREFIX, SOURCE_DIR, bind_cape_action_tracks
WORK = SOURCE_DIR
QA = ROOT / '.visual_captures/chinese_cloak_remake'
BASE = ROOT / '.godot-temp/chinese_cape_remake_baseline'
PACK_DIR = ROOT / 'assets/characters/human/q35'


def reference_file(sex, suffix):
    name=f'standard_anime_{sex}_character_pack.{suffix}'
    # The scoped backup protects this remake. Once it is archived, the shipped
    # character pack remains a self-contained source for later art revisions.
    saved=BASE/name
    return saved if saved.exists() else PACK_DIR/name


def preserve_legacy_clips(sex, target, source=None, replace_existing=False, prune_duplicates=False):
    """Keep original non-menu clips that the direct-key exporter cannot retarget.

    This copies their existing glTF channels verbatim; it does not invent cloak
    correction for unsupported source clips. Canonical clips use the new export.
    """
    def read(path):
        raw=path if isinstance(path,bytes) else path.read_bytes(); size=struct.unpack_from('<I',raw,12)[0]
        return json.loads(raw[20:20+size]),bytearray(raw[28+size:])
    old,old_bin=read(source or reference_file(sex,'glb'))
    doc,binary=read(target)
    if prune_duplicates:
        originals={a['name'] for a in old['animations']}
        doc['animations']=[a for a in doc['animations'] if a['name'] in originals or not (a['name'].rpartition('.')[2].isdigit() and a['name'].rpartition('.')[0] in originals)]
    if replace_existing:doc['animations']=[]
    names={a['name'] for a in doc['animations']}
    nodes={n['name']:i for i,n in enumerate(doc['nodes'])}
    copied={}
    def copy_accessor(index):
        if index in copied: return copied[index]
        acc=copy.deepcopy(old['accessors'][index]); assert 'sparse' not in acc
        view=copy.deepcopy(old['bufferViews'][acc['bufferView']])
        binary.extend(b'\0'*(-len(binary)%4))
        start=view.get('byteOffset',0)
        offset=len(binary);binary.extend(old_bin[start:start+view['byteLength']])
        view['byteOffset']=offset;view['buffer']=0
        acc['bufferView']=len(doc['bufferViews']);doc['bufferViews'].append(view)
        copied[index]=len(doc['accessors']);doc['accessors'].append(acc)
        return copied[index]
    for animation in old['animations']:
        if animation['name'] in names: continue
        animation=copy.deepcopy(animation)
        for sampler in animation['samplers']:
            sampler['input']=copy_accessor(sampler['input']);sampler['output']=copy_accessor(sampler['output'])
        for channel in animation['channels']:
            channel['target']['node']=nodes[old['nodes'][channel['target']['node']]['name']]
        doc['animations'].append(animation)
    binary.extend(b'\0'*(-len(binary)%4));doc['buffers'][0]['byteLength']=len(binary)
    encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*(-len(encoded)%4)
    target.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(binary))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+struct.pack('<I4s',len(binary),b'BIN\0')+binary)


def smooth(t):
    t = np.clip(t, 0, 1)
    return t*t*(3-2*t)


def cloth_normals(points, rows, cols):
    grid=points.reshape(rows+1,cols+1,3)
    normals=np.cross(np.gradient(grid,axis=0),np.gradient(grid,axis=1)).reshape(-1,3)
    return normals/np.maximum(np.linalg.norm(normals,axis=1)[:,None],1e-8)


def mat(name, color, texture=None, metallic=0, roughness=.8):
    m = bpy.data.materials.new('ChineseCloak_' + name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metallic
    bsdf.inputs['Roughness'].default_value = roughness
    if texture:
        image = bpy.data.images.load(str(WORK / texture), check_existing=True)
        image.pack()
        tex = m.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image = image
        m.node_tree.links.new(tex.outputs['Color'], bsdf.inputs['Base Color'])
    return m


def mesh_object(name, vertices, faces, uvs, arm, materials, face_materials, weights):
    mesh = bpy.data.meshes.new(name + 'Mesh')
    mesh.from_pydata(vertices, [], faces)
    bm=bmesh.new(); bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces)); bm.to_mesh(mesh); bm.free()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    for material in materials:
        mesh.materials.append(material)
    uv_layer = mesh.uv_layers.new(name='UVMap')
    for poly, mi in zip(mesh.polygons, face_materials):
        poly.use_smooth = True
        poly.material_index = mi
        for loop_index in poly.loop_indices:
            uv_layer.data[loop_index].uv = uvs[mesh.loops[loop_index].vertex_index]
    obj.parent = arm
    obj.matrix_parent_inverse = Matrix.Identity(4)
    mod = obj.modifiers.new('CloakSkin', 'ARMATURE'); mod.object = arm
    for bone, values in weights.items():
        group = obj.vertex_groups.new(name=bone)
        for i, value in enumerate(values):
            if value > 1e-6: group.add([i], float(value), 'REPLACE')
    obj['worldgoing_character_part'] = True
    obj['worldgoing_component_slot'] = 'cape'
    obj['worldgoing_visual_id'] = 'cape_chinese_01'
    obj['worldgoing_cloak_revision'] = 2
    return obj


def measure(arm, sex):
    def head(name): return arm.matrix_world @ arm.data.bones[name].head_local
    neck = head('J_Bip_C_Neck'); shoulder = head('J_Bip_L_UpperArm')
    body = bpy.data.objects.get('Body_Standard_' + sex.title())
    pts = np.array([body.matrix_world @ v.co for v in body.data.vertices])
    chest = pts[(pts[:,2] > neck.z-.25) & (pts[:,2] < neck.z-.07) & (abs(pts[:,0]) < .16)]
    neck_pts = pts[(pts[:,2] > neck.z+.018) & (pts[:,2] < neck.z+.060) & (abs(pts[:,0]) < .085)]
    return dict(neck=float(neck.z), neck_y=float(neck.y),
                neck_rx=float(max(abs(neck_pts[:,0])))+.008,
                neck_ry=float(np.ptp(neck_pts[:,1])/2)+.009,
                shoulder_x=float(shoulder.x),
                chest_front=float(chest[:,1].min()), chest_back=float(chest[:,1].max()),
                hip=float(head('J_Bip_C_Hips').z), sex=sex)


def cloth_surface(arm, d, kind, materials):
    # A continuous open wrap. Inside and outside share the complete boundary.
    cols = 88 if kind != 'Collar' else 48
    rows = {'Main':28, 'Mantle':10, 'Collar':4}[kind]
    t = np.repeat(np.linspace(0,1,rows+1), cols+1)
    u = np.tile(np.linspace(0,1,cols+1), rows+1)
    scale = d['neck']/1.45634
    gap = (.24 + .34*smooth(t)) if kind == 'Main' else np.full_like(t, .26)
    a = gap + (2*math.pi-2*gap)*u
    if kind == 'Main':
        rx = np.interp(t,[0,.09,.25,.55,1],[d['neck_rx']+.018,d['shoulder_x']+.105,.30*scale,.37*scale,.49*scale])
        ry = np.interp(t,[0,.09,.25,.55,1],[d['neck_ry']+.014,.145,.225,.340,.460])*scale
        folds = (np.cos(a*12+.3)+.32*np.cos(a*23-.4))*(.002+.022*smooth(t/.55))
        rx += folds; ry += folds
        z = d['neck']-.012 - t*(d['neck']-.155)
        z += .014*(np.cos(a*6)-1)*t**3
        z += .045*(np.maximum(np.cos(a),0)**4)*t**2
        z += .025*smooth(t/.10)*(1-smooth((t-.18)/.20))
    elif kind == 'Mantle':
        rx = d['neck_rx']+.020 + (.355*scale-d['neck_rx']-.020)*t
        ry = d['neck_ry']+.018 + (.205*scale-d['neck_ry']-.018)*t
        fold = .005*np.cos(a*12)*t
        rx += fold; ry += fold
        z = d['neck']+.008 - .215*scale*t**1.8
        z += .012*np.cos(a*5)*t**3
        z += .055*np.sin(math.pi*t/1.4)
    else:
        rx = np.full_like(t,d['neck_rx']+.005) + .007*t
        ry = np.full_like(t,d['neck_ry']+.003) + .004*t
        z = d['neck']-.008 + .073*scale*t
        z -= .016*np.maximum(np.cos(a),0)**3*t
    center = d['neck_y']*(1-t) + .008*t
    p = np.column_stack((np.sin(a)*rx, center-np.cos(a)*ry, z))
    normal_sign=-1 if kind=='Collar' else 1
    inner = p-cloth_normals(p,rows,cols)*(.0035*normal_sign)
    count = len(p)
    vertices = np.concatenate((p,inner))
    uv = list(zip(u,1-t))*2
    faces=[]; indices=[]
    for r in range(rows):
        for c in range(cols):
            i=r*(cols+1)+c
            q=(i,i+cols+1,i+cols+2,i+1)
            # The two layers must use the SAME diagonal when the quad bends.
            for tri in [(q[0],q[1],q[2]),(q[0],q[2],q[3])]:
                faces.append(tri); indices.append(0)
                faces.append(tuple(j+count for j in reversed(tri))); indices.append(1)
    edges=[]
    edges.extend((c,c+1) for c in range(cols))
    edges.extend((rows*(cols+1)+c+1,rows*(cols+1)+c) for c in range(cols))
    edges.extend((r*(cols+1),(r+1)*(cols+1)) for r in range(rows))
    edges.extend(((r+1)*(cols+1)+cols,r*(cols+1)+cols) for r in range(rows))
    for i,j in edges:
        faces.append((i,j,j+count,i+count)); indices.append(2)
    # Shoulder carries the cloth; tail has modest spine influence, never pelvis-only.
    # Fit the soft upper section in an arms-down pose, then inverse-skin that
    # fit into the unchanged T-pose bind. This avoids a rigid shoulder flap.
    spine = .28*smooth(t/.7) if kind=='Main' else np.zeros_like(t)
    if kind=='Mantle':
        arm_weight=.78*smooth(t/.7)*np.sin(a)**2
    elif kind=='Main':
        arm_weight=.55*smooth(t/.1)*(1-smooth((t-.12)/.35))*np.sin(a)**2
    else:
        arm_weight=np.zeros_like(t)
    left=arm_weight*(np.sin(a)>0);right=arm_weight*(np.sin(a)<0)
    weights={'J_Bip_C_UpperChest':np.tile((1-spine)*(1-arm_weight),2),
             'J_Bip_C_Spine':np.tile(spine*(1-arm_weight),2),
             'J_Bip_L_UpperArm':np.tile(left,2),'J_Bip_R_UpperArm':np.tile(right,2)}
    neutral_skin=np.tile(np.eye(4),(len(vertices),1,1))*(1-np.tile(arm_weight,2))[:,None,None]
    for side,values,sgn in [('L',left,1),('R',right,-1)]:
        pivot=arm.data.bones['J_Bip_'+side+'_UpperArm'].head_local
        transform=Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(80)*sgn,4,'Y') @ Matrix.Translation(-pivot)
        neutral_skin+=np.tile(values,2)[:,None,None]*np.array(transform)
    vertices=np.einsum('nij,nj->ni',np.linalg.inv(neutral_skin),np.column_stack((vertices,np.ones(len(vertices)))))[:,:3]
    obj=mesh_object(PREFIX+'_'+kind,vertices.tolist(),faces,uv,arm,materials,indices,weights)
    obj['cloth_rows']=rows; obj['cloth_cols']=cols; obj['cloth_layer_vertices']=count
    obj['neutral_cloth_positions']=p.ravel().tolist()
    return obj


def gray_parts(arm, d):
    gray=mat('Gray',(.42,.44,.46)); inside=mat('GrayInside',(.24,.26,.28)); edge=mat('GrayEdge',(.48,.48,.48))
    return [cloth_surface(arm,d,k,[gray,inside,edge]) for k in ('Main','Mantle','Collar')]


def finish_parts(parts):
    lining=mat('CrimsonSilk',(1,1,1),'cloak_lining.png',roughness=.72)
    gold=mat('AntiqueGold',(.58,.35,.10),metallic=.65,roughness=.38)
    for obj,texture in zip(parts,['cloak_outer.png','mantle_outer.png','collar_outer.png']):
        indices=[p.material_index for p in obj.data.polygons]
        obj.data.materials.clear()
        obj.data.materials.append(mat(obj.name,(1,1,1),texture,roughness=.86))
        obj.data.materials.append(lining);obj.data.materials.append(gold)
        for poly,index in zip(obj.data.polygons,indices): poly.material_index=index
        if obj.name.endswith('_Mantle'):
            cols=int(obj['cloth_cols'])+1
            rows=int(obj['cloth_rows'])
            for poly in obj.data.polygons:
                if poly.material_index==0 and max(v//cols for v in poly.vertices)<=int(rows*.3):
                    poly.material_index=1


def fasteners(arm,d):
    gold=mat('ClaspGold',(.65,.40,.13),metallic=.75,roughness=.32)
    red=mat('TasselSilk',(.30,.014,.025),roughness=.65)
    result=[]
    for side in [-1,1]:
        vertices=[];faces=[]
        for strand in range(13):
            offset=len(vertices)
            for row in range(9):
                t=row/8
                center=Vector((side*(.064+.012*t)+.012*math.cos(strand*2.4)*(t+.3),-.145-.025*t,d['neck']-.07-.29*t))
                for k in range(6):
                    a=k*math.tau/6
                    vertices.append(tuple(center+Vector((.0015*math.cos(a),.0015*math.sin(a),0))))
            for row in range(8):
                for k in range(6):
                    i=offset+row*6+k;j=offset+row*6+(k+1)%6
                    faces.append((i,j,j+6,i+6))
        obj=mesh_object(PREFIX+('_Tassels_L' if side<0 else '_Tassels_R'),vertices,faces,[(0,0)]*len(vertices),arm,[red],[0]*len(faces),{'J_Bip_C_UpperChest':[1]*len(vertices)})
        result.append(obj)
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=8,location=(side*.063,-.140,d['neck']-.061))
        clasp=bpy.context.object;clasp.name=PREFIX+('_Clasp_L' if side<0 else '_Clasp_R')
        for v in clasp.data.vertices:
            a=math.atan2(v.co.z,v.co.x)
            v.co.x*=1+.22*math.cos(a*6)
            v.co.z*=1+.22*math.cos(a*6)
        clasp.scale=(.018,.006,.024)
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        clasp.data.materials.append(gold);clasp.parent=arm
        clasp.data.materials.append(red)
        bm=bmesh.new();bm.from_mesh(clasp.data)
        gem=bmesh.ops.create_uvsphere(bm,u_segments=12,v_segments=6,radius=1)
        transform=Matrix.Translation((side*.063,-.148,d['neck']-.061)) @ Matrix.Diagonal((.007,.003,.009,1))
        for v in gem['verts']: v.co=transform @ v.co
        gem_vertices=set(gem['verts'])
        for face in bm.faces:
            if all(v in gem_vertices for v in face.verts): face.material_index=1
        bm.to_mesh(clasp.data);bm.free()
        mod=clasp.modifiers.new('CloakSkin','ARMATURE');mod.object=arm
        clasp.vertex_groups.new(name='J_Bip_C_UpperChest').add(list(range(len(clasp.data.vertices))),1,'REPLACE')
        for poly in clasp.data.polygons: poly.use_smooth=True
        result.append(clasp)
    return result


def bake_corrections(arm,parts,sex,only_clip=None):
    """Sampled pose-corrective morphs, not a claim of physical cloth simulation.

    Preserve layered correspondence and soft shoulder weighting. Broad opening,
    gravity alignment and sway are authored in posed space and inverse-skinned.
    """
    names=json.loads(reference_file(sex,'json').read_text(encoding='utf-8'))['animations']
    if only_clip: names=[only_clip]
    scene=bpy.context.scene
    for tr in arm.animation_data.nla_tracks: tr.mute=True
    for obj in parts[:2]:
        n=int(obj['cloth_layer_vertices']);rows=int(obj['cloth_rows']);cols=int(obj['cloth_cols'])
        base=np.array([v.co[:] for v in obj.data.vertices]); p=base[:n]
        neutral=np.array(obj['neutral_cloth_positions']).reshape(n,3)
        t=np.repeat(np.linspace(0,1,rows+1),cols+1)
        u=np.tile(np.linspace(0,1,cols+1),rows+1)
        angle=(.24+.34*smooth(t))+(2*math.pi-2*(.24+.34*smooth(t)))*u
        weight_map={group.name:np.zeros(n) for group in obj.vertex_groups}
        for vi,vertex in enumerate(obj.data.vertices[:n]):
            for group in vertex.groups: weight_map[obj.vertex_groups[group.group].name][vi]=group.weight
        obj.shape_key_add(name='Basis'); keys=obj.data.shape_keys
        clips=[]
        for clip in names:
            action=bpy.data.actions.get(clip)
            if not action or clip=='T-Pose': continue
            for pb in arm.pose.bones: pb.matrix_basis=Matrix.Identity(4)
            arm.animation_data.action=action
            sample_count=25 if clip in {'attack_sword','walk_slash'} else 13
            start,end=map(float,action.frame_range); frames=np.linspace(start,end,sample_count)
            blocks=[]
            for si,frame in enumerate(frames):
                scene.frame_set(int(frame),subframe=frame-int(frame));bpy.context.view_layer.update()
                skin=np.zeros((n,4,4))
                for bone,weights in weight_map.items():
                    matrix=np.array(arm.pose.bones[bone].matrix @ arm.data.bones[bone].matrix_local.inverted())
                    skin+=weights[:,None,None]*matrix
                chest_matrix=np.array(arm.pose.bones['J_Bip_C_UpperChest'].matrix @ arm.data.bones['J_Bip_C_UpperChest'].matrix_local.inverted())
                posed=np.einsum('nij,nj->ni',skin,np.column_stack((p,np.ones(n))))[:,:3]
                desired=posed.copy()
                if obj==parts[0]:
                    # The hanging skirt keeps a gravity axis when the torso leans.
                    neck_rest=np.array(arm.data.bones['J_Bip_C_Neck'].head_local)
                    neck_pose=np.array(arm.pose.bones['J_Bip_C_Neck'].head)
                    yaw=math.atan2(chest_matrix[1,0],chest_matrix[0,0])
                    rot=np.array([[math.cos(yaw),-math.sin(yaw),0],[math.sin(yaw),math.cos(yaw),0],[0,0,1]])
                    hanging=(neutral-neck_rest) @ rot.T+neck_pose
                    factor=smooth((t-.22)/.50)[:,None]*.8
                    desired=desired*(1-factor)+hanging*factor
                    # Open the front as one broad fold, before local clearance.
                    # This lets the legs emerge through the opening, rather than
                    # dragging a small patch of cloth around each kneecap.
                    front=smooth((np.cos(angle)-.15)/.8)*smooth(t/.30)
                    knee_span=max(abs(arm.pose.bones['J_Bip_'+side+'_LowerLeg'].head.x) for side in ['L','R'])
                    opening=.14+max(knee_span-.15,0)*.8
                    opening_delta=np.column_stack((np.sign(neutral[:,0])*front*opening,front*.045,np.zeros(n)))
                    desired+=opening_delta @ rot.T
                    spread=(neutral[:,0]*.24*smooth(t/.65))[:,None]*rot[:,0][None,:]
                    desired+=spread
                    if not clip.startswith('ride_'):
                        feet=[(np.array(arm.pose.bones['J_Bip_'+side+'_Foot'].tail)-neck_pose) @ rot for side in ['L','R']]
                        back_room=max(.46,max(foot[1] for foot in feet)+.12)
                        local=(desired-neck_pose) @ rot
                        back_delta=np.maximum(local[:,1],0)*(back_room/.46-1)*smooth(t/.60)
                        desired+=back_delta[:,None]*rot[:,1][None,:]
                    # A smooth cross-section envelope leaves room for both
                    # legs during yawing lunges. Expand whole curved sections;
                    # never project isolated vertices onto a knee surface.
                    if clip != 'down' and not clip.startswith('ride_'):
                        local=(desired-neck_pose) @ rot
                        rx=np.full(n,.03);ry=np.full(n,.03)
                        for side in ['L','R']:
                            for bone in ['UpperLeg','LowerLeg','Foot']:
                                pb=arm.pose.bones['J_Bip_'+side+'_'+bone]
                                for fraction in [0,.33,.67,1]:
                                    joint=(np.array(pb.head.lerp(pb.tail,fraction))-neck_pose) @ rot
                                    influence=np.exp(-((local[:,2]-joint[2])/.22)**2)
                                    rx=np.maximum(rx,(abs(joint[0])+.22)*influence)
                                    ry=np.maximum(ry,(abs(joint[1])+.24)*influence)
                        radius=np.sqrt((local[:,0]/rx)**2+(local[:,1]/ry)**2)
                        expansion=np.maximum(1,1/np.maximum(radius,.1))
                        local[:,:2]*=(1+(expansion-1)*smooth((t-.15)/.18))[:,None]
                        desired=local @ rot.T+neck_pose
                phase=2*math.pi*si/(sample_count-1)
                amplitude=.016 if clip=='idle' else .050 if 'walk' in clip else .085
                desired[:,1] += amplitude*np.sin(phase-t*1.8)*smooth(t)**2
                desired[:,0] += amplitude*.3*np.cos(phase-t)*smooth(t)**2
                if clip.startswith('ride_') and obj==parts[0]:
                    # Open the skirt around the mount; retain shoulder anchors.
                    desired[:,1]+= .20*smooth((t-.3)/.7)
                    desired[:,2]+= .25*smooth((t-.40)/.6)
                desired[:,2]=np.maximum(desired[:,2],.035)
                inv=np.linalg.inv(skin)
                corrected=np.einsum('nij,nj->ni',inv,np.column_stack((desired,np.ones(n))))[:,:3]
                inside=desired-cloth_normals(desired,rows,cols)*.0035
                corrected_inside=np.einsum('nij,nj->ni',inv,np.column_stack((inside,np.ones(n))))[:,:3]
                coords=np.concatenate((corrected,corrected_inside))
                key=obj.shape_key_add(name=f'{clip}_{si:02d}')
                key.data.foreach_set('co',coords.astype('float32').ravel());blocks.append(key)
            clips.append((clip,frames,blocks))
        # Direct authored sample targets; no lossy mode compression.
        keys.animation_data_create()
        for clip,frames,blocks in clips:
            act=bpy.data.actions.new(obj.name+'_'+clip)
            keys.animation_data.action=act
            for key in list(keys.key_blocks)[1:]:
                curve=act.fcurves.new(data_path=key.path_from_id('value'))
                if key in blocks:
                    i=blocks.index(key)
                    curve.keyframe_points.add(len(frames))
                    for j,frame in enumerate(frames):
                        curve.keyframe_points[j].co=(float(frame),1.0 if i==j else 0.0)
                else:
                    curve.keyframe_points.add(1)
                    curve.keyframe_points[0].co=(float(frames[0]),0)
                for kp in curve.keyframe_points: kp.interpolation='LINEAR'
            track=keys.animation_data.nla_tracks.new();track.name=clip
            track.strips.new(clip,int(frames[0]),act);track.mute=True
        keys.animation_data.action=None
        for key in keys.key_blocks: key.value=0
    arm.animation_data.action=None
    for pb in arm.pose.bones: pb.matrix_basis=Matrix.Identity(4)
    scene.frame_set(0);bpy.context.view_layer.update()
    bind_cape_action_tracks(arm,parts)


def render_gray(arm, parts, sex):
    scene=bpy.context.scene
    if scene.world is None: scene.world=bpy.data.worlds.new('CloakReviewWorld')
    if arm.animation_data:
        arm.animation_data.action=None
        for tr in arm.animation_data.nla_tracks: tr.mute=True
    for pb in arm.pose.bones: pb.matrix_basis=Matrix.Identity(4)
    bpy.context.view_layer.update()
    for side,sgn in [('L',1),('R',-1)]:
        pb=arm.pose.bones['J_Bip_'+side+'_UpperArm']
        pivot=pb.bone.head_local
        pb.matrix=Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(80)*sgn,4,'Y') @ Matrix.Translation(-pivot) @ pb.bone.matrix_local
    bpy.context.view_layer.update()
    for obj in bpy.data.objects:
        if obj.type=='MESH':
            show=obj in parts or obj.name in ('Body_Standard_'+sex.title(),'Face_Standard_01','Hair_Short_01','Hair_Long_01') or obj.name.startswith('Outfit_Underlayer_01')
            obj.hide_render=not show; obj.hide_viewport=not show
    scene.render.engine='BLENDER_WORKBENCH'
    scene.display.shading.light='STUDIO';scene.display.shading.studio_light='paint.sl'
    scene.display.shading.color_type='MATERIAL';scene.display.shading.show_shadows=True
    scene.display.shading.show_cavity=True;scene.display.shading.cavity_type='BOTH'
    scene.display.shading.background_type='WORLD';scene.world.color=(.075,.08,.09)
    scene.render.resolution_x=1100;scene.render.resolution_y=1250;scene.render.resolution_percentage=100
    cam_data=bpy.data.cameras.new('CloakReviewCamera');cam=bpy.data.objects.new('CloakReviewCamera',cam_data)
    scene.collection.objects.link(cam);scene.camera=cam;cam_data.type='ORTHO';cam_data.ortho_scale=1.94
    QA.mkdir(parents=True,exist_ok=True)
    target=Vector((0,0,.84))
    for name,angle in [('front',0),('threequarter',35),('side',90),('back',180)]:
        a=math.radians(angle);cam.location=Vector((math.sin(a)*4,-math.cos(a)*4,.84))
        cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(QA/f'{sex}_gray_{name}.png')
        bpy.ops.render.render(write_still=True)


def main():
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    parser=argparse.ArgumentParser();parser.add_argument('--sex',choices=['male','female'],default='male');parser.add_argument('--stage',choices=['gray','finish','export'],default='gray')
    parser.add_argument('--clip',default=None)
    opt=parser.parse_args(args)
    WORK.mkdir(parents=True,exist_ok=True)
    source=WORK/f'chinese_cloak_{opt.sex}.blend' if opt.stage=='export' else reference_file(opt.sex,'blend')
    bpy.ops.wm.open_mainfile(filepath=str(source))
    arm=next(o for o in bpy.data.objects if o.type=='ARMATURE')
    if opt.stage!='export':
        for obj in list(bpy.data.objects):
            if obj.name.startswith(PREFIX): bpy.data.objects.remove(obj,do_unlink=True)
    d=measure(arm,opt.sex)
    (WORK/f'{opt.sex}_measurements.json').write_text(json.dumps(d,indent=2),encoding='utf-8')
    parts=[o for o in bpy.data.objects if o.name.startswith(PREFIX)] if opt.stage=='export' else gray_parts(arm,d)
    if opt.stage=='gray':
        render_gray(arm,parts,opt.sex)
        bpy.ops.wm.save_as_mainfile(filepath=str(WORK/f'chinese_cloak_{opt.sex}_gray.blend'))
    else:
        if opt.stage!='export':
            finish_parts(parts)
            bake_corrections(arm,parts,opt.sex,opt.clip)
            parts.extend(fasteners(arm,d))
            bpy.ops.wm.save_as_mainfile(filepath=str(WORK/f'chinese_cloak_{opt.sex}.blend'))
        if opt.stage=='export':
            # Refresh only this cloak's external textures before packing the
            # editable source; other character materials remain untouched.
            textures={}
            for obj in parts:
                for material in obj.data.materials:
                    if material and material.use_nodes:
                        for node in material.node_tree.nodes:
                            if node.type=='TEX_IMAGE' and node.image:
                                name=Path(node.image.filepath).name
                                if name in {'cloak_outer.png','mantle_outer.png','collar_outer.png','cloak_lining.png'}:
                                    if name not in textures:
                                        textures[name]=bpy.data.images.load(str(WORK/name),check_existing=False)
                                        textures[name].pack()
                                    node.image=textures[name]
            bpy.ops.wm.save_as_mainfile(filepath=str(source))
            metadata=json.loads(reference_file(opt.sex,'json').read_text(encoding='utf-8'))
            export_names={n for values in metadata['parts'].values() for n in values}
            clip_names={opt.clip} if opt.clip else set(metadata['animations'])
            for action in list(bpy.data.actions):
                if opt.clip and not action.name.startswith(PREFIX) and action.name not in clip_names:
                    bpy.data.actions.remove(action)
            bpy.ops.object.select_all(action='DESELECT')
            for obj in bpy.data.objects:
                if obj==arm or obj.name in export_names or obj in parts:
                    obj.hide_viewport=False;obj.hide_set(False);obj.select_set(True)
            bpy.ops.export_scene.gltf(filepath=str(WORK/f'candidate_{opt.sex}.glb'),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='ACTIONS',export_force_sampling=False,export_optimize_disable_viewport=True,export_skins=True,export_morph=True,export_apply=False)
            if not opt.clip: preserve_legacy_clips(opt.sex,WORK/f'candidate_{opt.sex}.glb')
    print('CHINESE_CLOAK_STAGE_PASS',opt.sex,opt.stage,flush=True)


if __name__=='__main__': main()
