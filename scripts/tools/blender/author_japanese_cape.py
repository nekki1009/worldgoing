"""Measured short officer overcloak; additive source, never rebuilds legacy art."""
import argparse
import hashlib
import json
import math
import shutil
import sys
import uuid
from pathlib import Path
import bpy
import numpy as np
from mathutils import Matrix

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).parent))
import author_chinese_cape as cloth
from author_chinese_leather_mingguang import Fitting, tube

OUT = ROOT/'output/equipment_matrix_20260918'
WORK = ROOT/'assets/characters/human/q35/equipment_matrix'
PREFIX = 'Cape_Japanese_01'


def material(name, color):
    mat = bpy.data.materials.get('JapaneseCape_'+name) or bpy.data.materials.new('JapaneseCape_'+name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    bs = mat.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*color, 1)
    bs.inputs['Roughness'].default_value = .88
    bs.inputs['Metallic'].default_value = 0
    return mat


def surface(arm, d, collar=False):
    rows, cols = (4, 48) if collar else (16, 64)
    t = np.repeat(np.linspace(0, 1, rows+1), cols+1)
    u = np.tile(np.linspace(0, 1, cols+1), rows+1)
    angle = .32 + (math.tau-.64)*u
    scale = d['neck']/1.45634
    if collar:
        rx = d['neck_rx']+.017+.005*t
        ry = d['neck_ry']+.018+.003*t
        z = d['neck']-.025+.065*scale*t-.012*np.maximum(np.cos(angle),0)*t
    else:
        rx = np.interp(t, [0,.13,.27,.65,1], [d['neck_rx']+.025,d['shoulder_x']+.074,.255*scale,.272*scale,.314*scale])
        ry = np.interp(t, [0,.13,.27,.65,1], [d['neck_ry']+.03,.148*scale,.187*scale,.212*scale,.26*scale])
        # Broad seam-driven folds, not a uniformly corrugated cone.
        folds = np.zeros_like(t)
        for center, width, depth in [(1.05,.16,.013),(1.75,.22,-.012),(2.4,.21,.018),(3.18,.28,-.019),(3.85,.23,.016),(4.65,.19,-.012),(5.2,.17,.012)]:
            folds += depth*np.exp(-((angle-center)/width)**2)*cloth.smooth(t/.60)
        rx += folds
        ry += folds*.8
        length = d['neck']-d['hip']+.16*scale
        z = d['neck']-.018-t*length
        # The shoulder yoke arches over the measured deltoid instead of cutting
        # a straight cone through the shoulder between neck and arm openings.
        z += .10*scale*np.exp(-((t-.115)/.082)**2)*np.sin(angle)**2
        z += .055*np.maximum(np.cos(angle),0)**3*t**2
        # A shallow central rear vent, authored into the hem boundary.
        z += .11*np.exp(-((angle-math.pi)/.055)**2)*t**9
    p = np.column_stack((np.sin(angle)*rx, d['neck_y']*(1-t)-np.cos(angle)*ry, z))
    n = len(p)
    inner = p-cloth.cloth_normals(p,rows,cols)*(-.003 if collar else .003)
    coords = np.concatenate((p,inner))
    faces, indices, boundaries = [], [], {}
    for r in range(rows):
        for c in range(cols):
            i=r*(cols+1)+c
            mid=(angle[i]+angle[i+1])/2
            # Deep open sides free the upper arms; the upper yoke stays joined.
            if not collar and r>=3 and abs(math.sin(mid))>.70: continue
            q=(i,i+cols+1,i+cols+2,i+1)
            for tri in [(q[0],q[1],q[2]),(q[0],q[2],q[3])]:
                faces += [tri, tuple(j+n for j in reversed(tri))]
                edge_trim = r==rows-1 or c in (0,cols-1)
                indices += [2 if edge_trim else 0,1]
            for a,b in zip(q,q[1:]+q[:1]):
                edge=tuple(sorted((a,b)))
                if edge in boundaries: boundaries.pop(edge)
                else: boundaries[edge]=(a,b)
    for a,b in boundaries.values():
        faces.append((a,b,b+n,a+n));indices.append(2)
    spine=np.zeros_like(t) if collar else .20*cloth.smooth(t/.7)
    arms=np.zeros_like(t) if collar else .45*cloth.smooth(t/.1)*(1-cloth.smooth((t-.13)/.22))*np.sin(angle)**2
    left=arms*(np.sin(angle)>0);right=arms*(np.sin(angle)<0)
    weights={'J_Bip_C_UpperChest':np.tile((1-spine)*(1-arms),2), 'J_Bip_C_Spine':np.tile(spine*(1-arms),2),
             'J_Bip_L_UpperArm':np.tile(left,2),'J_Bip_R_UpperArm':np.tile(right,2)}
    skin=np.tile(np.eye(4),(len(coords),1,1))*(1-np.tile(arms,2))[:,None,None]
    for side,values,sgn in [('L',left,1),('R',right,-1)]:
        pivot=arm.data.bones['J_Bip_'+side+'_UpperArm'].head_local
        transform=Matrix.Translation(pivot)@Matrix.Rotation(math.radians(80)*sgn,4,'Y')@Matrix.Translation(-pivot)
        skin+=np.tile(values,2)[:,None,None]*np.array(transform)
    coords=np.einsum('nij,nj->ni',np.linalg.inv(skin),np.column_stack((coords,np.ones(len(coords)))))[:,:3]
    mats=[material('Fabric',(.22,.275,.34)),material('Lining',(.10,.14,.20)),material('Trim',(.48,.38,.22))]
    obj=cloth.mesh_object(PREFIX+('_Collar' if collar else '_Main'),coords.tolist(),faces,list(zip(u,1-t))*2,arm,mats,indices,weights)
    obj['worldgoing_visual_id']='cape_japanese_01'
    obj['cloth_rows']=rows;obj['cloth_cols']=cols;obj['cloth_layer_vertices']=n
    obj['neutral_cloth_positions']=p.ravel().tolist()
    return obj


def reset(arm):
    arm.animation_data.action=None
    for track in arm.animation_data.nla_tracks: track.mute=True
    for bone in arm.pose.bones: bone.matrix_basis=Matrix.Identity(4)
    for obj in bpy.data.objects:
        if obj.type=='MESH' and obj.data.shape_keys:
            keys=obj.data.shape_keys
            if keys.animation_data:
                keys.animation_data.action=None
                for track in keys.animation_data.nla_tracks:track.mute=True
            for key in keys.key_blocks:key.value=0
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()


def bake(arm, main, sex):
    # New actions are appended to the same native skeleton, not retargeted.
    action_file=WORK/f'mounted_actions_{sex}.blend'
    assert action_file.exists(), 'Mounted actions must be ready before cape corrections'
    # Corrections must sample the latest authored arms, never the previous
    # source copy retained in this editable cape file.
    mounted=('ride_heavy','ride_guard_break')
    arm.animation_data.action=None
    for track in list(arm.animation_data.nla_tracks):
        if track.name in mounted: arm.animation_data.nla_tracks.remove(track)
    for name in mounted:
        action=bpy.data.actions.get(name)
        if action: bpy.data.actions.remove(action,do_unlink=True)
    with bpy.data.libraries.load(str(action_file),link=False) as (source,target):
        target.actions=[a for a in source.actions if a in mounted]
    assert len(target.actions)==2
    reset(arm)
    modes={bone.name:bone.rotation_mode for bone in arm.pose.bones}
    # Only the new cloth needs evaluation; legacy thousand-mesh art is untouched.
    for obj in bpy.data.objects:
        if obj.type=='MESH' and not obj.name.startswith(PREFIX): obj.hide_viewport=True
    n=int(main['cloth_layer_vertices']);rows=int(main['cloth_rows']);cols=int(main['cloth_cols'])
    base=np.array([v.co[:] for v in main.data.vertices]);neutral=np.array(main['neutral_cloth_positions']).reshape(n,3)
    t=np.repeat(np.linspace(0,1,rows+1),cols+1)
    weights={group.name:np.zeros(n) for group in main.vertex_groups}
    for i,v in enumerate(main.data.vertices[:n]):
        for group in v.groups:weights[main.vertex_groups[group.group].name][i]=group.weight
    main.shape_key_add(name='Basis');timings={};clip_frames={}
    names=json.loads((OUT/f'baseline/standard_anime_{sex}_character_pack.json').read_text(encoding='utf-8'))['animations']+['ride_heavy','ride_guard_break']
    scene=bpy.context.scene
    for clip in names:
        action=bpy.data.actions.get(clip)
        if clip=='T-Pose' or action is None:continue
        reset(arm);arm.animation_data.action=action
        for bone in arm.pose.bones:
            bone.rotation_mode='QUATERNION' if clip in ('ride_heavy','ride_guard_break') else modes[bone.name]
        start,end=map(float,action.frame_range)
        count=25 if clip in ('run','attack_jump_heavy') else (13 if 'heavy' in clip or 'slash' in clip or 'break' in clip else 9)
        frames=np.linspace(start,end,count)
        timings[clip]=((frames-start)/scene.render.fps).tolist()
        clip_frames[clip]=frames
        for index,frame in enumerate(frames):
            scene.frame_set(int(frame),subframe=frame-int(frame));bpy.context.view_layer.update()
            skin=np.zeros((n,4,4))
            for bone,values in weights.items():
                skin+=values[:,None,None]*np.array(arm.pose.bones[bone].matrix@arm.data.bones[bone].matrix_local.inverted())
            posed=np.einsum('nij,nj->ni',skin,np.column_stack((base[:n],np.ones(n))))[:,:3]
            chest=np.array(arm.pose.bones['J_Bip_C_UpperChest'].matrix@arm.data.bones['J_Bip_C_UpperChest'].matrix_local.inverted())
            yaw=math.atan2(chest[1,0],chest[0,0]);rot=np.array([[math.cos(yaw),-math.sin(yaw),0],[math.sin(yaw),math.cos(yaw),0],[0,0,1]])
            neck=np.array(arm.pose.bones['J_Bip_C_Neck'].head);rest=np.array(arm.data.bones['J_Bip_C_Neck'].head_local)
            hanging=(neutral-rest)@rot.T+neck
            factor=.65*cloth.smooth((t-.26)/.62)[:,None]
            desired=posed*(1-factor)+hanging*factor
            tail=cloth.smooth((t-.25)/.75)
            # Broad clearance sections prevent pointed per-vertex leg projection.
            local=(desired-neck)@rot
            local[:,0]+=np.sign(neutral[:,0])*.035*tail
            if clip.startswith('ride_'):
                local[:,1]+=.10*tail*np.maximum(neutral[:,1],0)/max(.10,float(neutral[:,1].max()))
                local[:,2]+=.10*tail
            phase=math.tau*index/(len(frames)-1)
            local[:,1]+=(.008 if clip=='idle' else .026)*np.sin(phase-t*1.7)*tail**2
            if clip!='down' and not clip.startswith('ride_'):
                # Leaning moves the hips behind the neck's hanging axis. Leave
                # one smooth asymmetric section around pelvis/thighs (including
                # under-armor ease), not vertex-by-vertex projections onto knees.
                rx=np.full(n,.03);front=np.full(n,.03);back=np.full(n,.03)
                for name in ('J_Bip_C_Hips','J_Bip_C_Spine','J_Bip_L_UpperLeg','J_Bip_R_UpperLeg'):
                    bone=arm.pose.bones[name]
                    for fraction in (0,.5,1):
                        joint=(np.array(bone.head.lerp(bone.tail,fraction))-neck)@rot
                        influence=np.exp(-((local[:,2]-joint[2])/.22)**2)
                        rx=np.maximum(rx,(abs(joint[0])+.18)*influence)
                        front=np.maximum(front,(-joint[1]+.18)*influence)
                        back=np.maximum(back,(joint[1]+.20)*influence)
                ry=np.where(local[:,1]>=0,back,front)
                radius=np.sqrt((local[:,0]/rx)**2+(local[:,1]/ry)**2)
                expansion=np.maximum(1,1/np.maximum(radius,.1))
                local[:,:2]*=(1+(expansion-1)*cloth.smooth((t-.24)/.20))[:,None]
            desired=local@rot.T+neck
            desired[:,2]=np.maximum(desired[:,2],.04)
            inside=desired-cloth.cloth_normals(desired,rows,cols)*.003
            inv=np.linalg.inv(skin)
            result=np.concatenate([np.einsum('nij,nj->ni',inv,np.column_stack((p,np.ones(n))))[:,:3] for p in (desired,inside)])
            key=main.shape_key_add(name=f'Cloth_{clip}_{index:02d}')
            key.data.foreach_set('co',result.astype('float32').ravel())
        print('JAPANESE_CAPE_CLIP',clip,len(frames),flush=True)
    reset(arm)
    for bone in arm.pose.bones:bone.rotation_mode=modes[bone.name]
    keys=main.data.shape_keys
    keys.animation_data_create()
    for clip,frames in clip_frames.items():
        action=bpy.data.actions.new(main.name+'_'+clip)
        for key in list(keys.key_blocks)[1:]:
            curve=action.fcurves.new(data_path=key.path_from_id('value'))
            active=key.name.startswith('Cloth_'+clip+'_')
            curve.keyframe_points.add(len(frames) if active else 1)
            for index,point in enumerate(curve.keyframe_points):
                point.co=(float(frames[index]),float(active and key.name==f'Cloth_{clip}_{index:02d}'))
                point.interpolation='LINEAR'
        track=keys.animation_data.nla_tracks.new();track.name=clip
        track.strips.new(clip,int(frames[0]),action);track.mute=True
    cloth.bind_cape_action_tracks(arm,[main])
    (WORK/f'cape_{sex}_clip_times.json').write_text(json.dumps(timings,indent=2))
    with action_file.open('rb') as stream:
        (WORK/f'cape_{sex}_mounted_source.sha256').write_text(hashlib.file_digest(stream,'sha256').hexdigest())


def save(sex):
    temp=ROOT/f'.godot-temp/japanese_cape_{uuid.uuid4().hex}.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(temp),compress=True)
    target=WORK/f'japanese_cape_{sex}.blend'
    shutil.copy2(temp,target)
    assert temp.stat().st_size==target.stat().st_size
    temp.unlink()


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--sex',choices=['male','female'],required=True)
    parser.add_argument('--stage',choices=['gray','preview','finish','correct','open-arms','export'],required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);sex=args.sex
    bpy.context.preferences.filepaths.save_version=0
    source=OUT/f'baseline/standard_anime_{sex}_character_pack.blend' if args.stage=='gray' else WORK/f'japanese_cape_{sex}.blend'
    bpy.ops.wm.open_mainfile(filepath=str(source));arm=bpy.data.objects['Armature'];reset(arm)
    parts=[o for o in bpy.data.objects if o.name.startswith(PREFIX)]
    if args.stage=='gray':
        assert not parts
        measured=cloth.measure(arm,sex)
        parts=[surface(arm,measured),surface(arm,measured,True)]
        (OUT/f'cape_{sex}_measurements.json').write_text(json.dumps(measured,indent=2))
        save(sex)
    elif args.stage=='preview':
        cloth.QA=OUT/'cape_gray';cloth.QA.mkdir(exist_ok=True)
        cloth.render_gray(arm,parts,sex)
    elif args.stage in ('finish','correct','open-arms'):
        main_part=bpy.data.objects[PREFIX+'_Main']
        if args.stage in ('correct','open-arms'):
            assert main_part.data.shape_keys and all(k.name=='Basis' or k.name.startswith('Cloth_') for k in main_part.data.shape_keys.key_blocks)
            main_part.shape_key_clear()
            for action in list(bpy.data.actions):
                if action.name.startswith(PREFIX+'_Main_'):
                    bpy.data.actions.remove(action,do_unlink=True)
        if args.stage=='open-arms':
            # Explicit side-opening revision. Retain every authored vertex,
            # armature group and rest-space position; only the cut boundary changes.
            assert not main_part.get('wide_arm_openings'), 'Already corrected'
            replacement=surface(arm,cloth.measure(arm,sex))
            assert len(main_part.data.vertices)==len(replacement.data.vertices)
            for old,new in zip(main_part.data.vertices,replacement.data.vertices):new.co=old.co
            main_part.data=replacement.data
            bpy.data.objects.remove(replacement,do_unlink=True)
            main_part['wide_arm_openings']=True
        assert not main_part.data.shape_keys, 'Already finished; do not replace hand edits'
        bake(arm,main_part,sex)
        for obj in parts:
            for index,mat in enumerate(obj.data.materials):
                if mat.name.startswith('JapaneseCape_'):
                    obj.data.materials[index]=bpy.data.materials[mat.name.split('.')[0]]
        fit=Fitting(arm,sex);d=cloth.measure(arm,sex)
        cord=material('Cord',(.34,.25,.14))
        for side in (-1,1):
            if bpy.data.objects.get(PREFIX+'_Tie_'+str(side)): continue
            path=[(side*(.065*(1-t)+.015*t),-.145-.014*math.sin(t*math.pi),d['neck']-.063-.025*math.sin(t*math.pi)) for t in np.linspace(0,1,20)]
            obj=tube(PREFIX+'_Tie_'+str(side),path,[.0023]*len(path),cord,fit,sides=6)
            obj['worldgoing_component_slot']='cape';obj['worldgoing_visual_id']='cape_japanese_01'
        save(sex)
    else:
        bpy.ops.object.select_all(action='DESELECT')
        for obj in [arm]+parts:obj.hide_set(False);obj.hide_viewport=False;obj.select_set(True)
        bpy.context.view_layer.objects.active=arm
        bpy.ops.export_scene.gltf(filepath=str(WORK/f'subset_cape_{sex}.glb'),export_format='GLB',use_selection=True,export_animations=False,export_skins=True,export_morph=True,export_try_sparse_sk=False,export_apply=False)
    print('JAPANESE_CAPE_STAGE_PASS',sex,args.stage,flush=True)


if __name__=='__main__':main()
