"""Replace only the run skirt targets; preserve topology, rest and other clips."""
import math,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
import bpy
import numpy as np
from mathutils import Matrix
from author_chinese_cape import smooth,cloth_normals


def repair_run(arm):
    obj=bpy.data.objects['Cape_Chinese_01_Main']
    n=int(obj['cloth_layer_vertices']);rows=int(obj['cloth_rows']);cols=int(obj['cloth_cols'])
    neutral=np.array(obj['neutral_cloth_positions']).reshape(n,3)
    t=np.repeat(np.linspace(0,1,rows+1),cols+1)
    angle=np.tile(np.linspace(0,1,cols+1),rows+1)
    gap=.24+.34*smooth(t);angle=gap+(math.tau-2*gap)*angle
    weights={g.name:np.zeros(n) for g in obj.vertex_groups}
    for i,v in enumerate(obj.data.vertices[:n]):
        for g in v.groups:weights[obj.vertex_groups[g.group].name][i]=g.weight
    action=bpy.data.actions['run'];start,end=action.frame_range
    keys=[k for k in obj.data.shape_keys.key_blocks if k.name.startswith('run_')]
    assert len(keys)==13
    for tr in arm.animation_data.nla_tracks:tr.mute=True
    for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    arm.animation_data.action=action
    for i,key in enumerate(keys):
        frame=start+(end-start)*i/(len(keys)-1)
        bpy.context.scene.frame_set(int(frame),subframe=frame-int(frame));bpy.context.view_layer.update()
        skin=np.zeros((n,4,4))
        for bone,w in weights.items():
            skin+=w[:,None,None]*np.array(arm.pose.bones[bone].matrix@arm.data.bones[bone].matrix_local.inverted())
        old=np.array([v.co[:] for v in key.data[:n]])
        old=np.einsum('nij,nj->ni',skin,np.column_stack((old,np.ones(n))))[:,:3]
        chest=np.array(arm.pose.bones['J_Bip_C_UpperChest'].matrix@arm.data.bones['J_Bip_C_UpperChest'].matrix_local.inverted())
        yaw=math.atan2(chest[1,0],chest[0,0]);rot=np.array([[math.cos(yaw),-math.sin(yaw),0],[math.sin(yaw),math.cos(yaw),0],[0,0,1]])
        neck=np.array(arm.pose.bones['J_Bip_C_Neck'].head)
        local=neutral-np.array(arm.data.bones['J_Bip_C_Neck'].head_local)
        # One smooth trailing cloth volume. No foot-driven, height-local radial
        # projection: it stretched hems and made a narrow waist below the knee.
        tail=smooth((t-.18)/.82);phase=math.tau*i/(len(keys)-1)
        front=smooth((np.cos(angle)-.15)/.8)*smooth(t/.30)
        local[:,0]+=np.sign(neutral[:,0])*front*.16+neutral[:,0]*.10*tail
        # Running trails the whole hanging length backward, lifting the rear
        # hem above the kicking foot instead of widening a ring around it.
        pitch=.80 if bpy.data.objects.get('Body_Standard_Female') else .72
        trailing=np.array([[1,0,0],[0,math.cos(pitch),-math.sin(pitch)],[0,math.sin(pitch),math.cos(pitch)]])
        local=local@trailing.T
        local[:,1]+=.065*tail+.022*np.sin(phase-t*2.0)*tail
        local[:,2]+=.035*tail+.014*np.sin(phase-t*2.0)*tail
        local[:,0]+=.014*np.cos(phase-t)*tail
        target=local@rot.T+neck
        blend=smooth((t-.12)/.25)[:,None]
        desired=old*(1-blend)+target*blend
        inside=desired-cloth_normals(desired,rows,cols)*.0035
        inv=np.linalg.inv(skin)
        coords=np.concatenate([np.einsum('nij,nj->ni',inv,np.column_stack((p,np.ones(n))))[:,:3] for p in [desired,inside]])
        key.data.foreach_set('co',coords.astype('float32').ravel())
    arm.animation_data.action=None
    for pb in arm.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    bpy.context.scene.frame_set(0);bpy.context.view_layer.update()
    obj['run_drape_revision']=2
    print('CLOAK_RUN_REPAIR_READY',len(keys),flush=True)


if __name__=='__main__':
    # Keep the dedicated cloak art source intact apart from its 13 run keys.
    import shutil,uuid
    from pathlib import Path
    root=Path(__file__).resolve().parents[3]
    work=root/'assets/characters/human/q35/chinese_lining'
    bpy.context.preferences.filepaths.save_version=0
    for sex in ['male','female']:
        bpy.ops.wm.open_mainfile(filepath=str(root/f'.godot-temp/lining_cloak_baseline_20260910/chinese_cloak_{sex}.blend'))
        target=bpy.data.objects['Cape_Chinese_01_Main']
        with bpy.data.libraries.load(str(work/f'chinese_lining_{sex}.blend'),link=False) as (_,loaded):
            loaded.objects=['Cape_Chinese_01_Main']
        source=loaded.objects[0]
        assert len(target.data.vertices)==len(source.data.vertices)
        for key in source.data.shape_keys.key_blocks:
            if key.name.startswith('run_'):
                values=np.empty(len(key.data)*3,dtype=np.float32);key.data.foreach_get('co',values)
                target.data.shape_keys.key_blocks[key.name].data.foreach_set('co',values)
        target['run_drape_revision']=2
        bpy.data.objects.remove(source,do_unlink=True)
        temporary=root/f'.godot-temp/cloak_run_save_{sex}_{uuid.uuid4().hex}.blend'
        bpy.ops.wm.save_as_mainfile(filepath=str(temporary))
        shutil.copy2(temporary,work/f'chinese_cloak_{sex}.blend')
        print('CLOAK_EDITABLE_SOURCE_READY',sex,flush=True)
