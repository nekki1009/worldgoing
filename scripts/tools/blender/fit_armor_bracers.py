"""Fit existing hard-armor bracers to the authored sleeves, not a guessed circle."""
import math
import bpy, bmesh
import numpy as np
from mathutils import Matrix
from repair_character_audit import surface_layer, save_geometry

PREFIXES = ('Armor_Iron_01_Bracer', 'Armor_Mingguang_01_Bracer')
CLIPS = ('idle','walk','run','guard','attack_bow','attack_crossbow','attack_spear','attack_hammer')
MARKER = 'worldgoing_lining_bracer_fit_v1'


def fit_closure_straps(obj, shirt, arm):
    # The original iron closure arc was a quarter-turn away from the plate's
    # open side. Use the sleeve surface for a closed, flexible strap instead
    # of another guessed rigid circle. Keep both original band widths/places.
    edges = sorted({round((obj.matrix_world @ v.co).x,6) for v in obj.data.vertices})
    assert len(edges) == 4, (obj.name,edges)
    combined = bmesh.new()
    material = obj.data.materials[0]
    for low,high in [(edges[0],edges[1]),(edges[2],edges[3])]:
        band = surface_layer(shirt,obj.name+'_FitSource',material,arm,'armor',obj['worldgoing_visual_id'],-1,3,.0018,xmin=low,xmax=high)
        band.data.transform(band.matrix_world)
        combined.from_mesh(band.data)
        bpy.data.objects.remove(band,do_unlink=True)
    bmesh.ops.solidify(combined,geom=combined.faces[:],thickness=.0010)
    obj.vertex_groups.clear()
    for group in shirt.vertex_groups:
        obj.vertex_groups.new(name=group.name)
    save_geometry(obj,combined)
    obj[MARKER] = True
    return {'name':obj.name,'fit':'conformal sleeve weights','vertices':len(obj.data.vertices)}


def fit_armor_bracers(arm, objects):
    # A hard shell needs chest compression, but its exposed back gaps need
    # cloth ease. Keep the leather key and standalone shirt exactly as authored.
    shirt = next(o for o in objects if o.name == 'Outfit_Chinese_Lining_01_Shirt')
    keys = shirt.data.shape_keys.key_blocks
    if 'UnderHardArmor' not in keys:
        hard = shirt.shape_key_add(name='UnderHardArmor')
        for source, fitted, vertex in zip(keys['Basis'].data, keys['UnderArmor'].data, hard.data):
            amount = .3 + .6 * max(0.0, min(1.0, (.02-source.co.y)/.04))
            vertex.co = source.co.lerp(fitted.co, amount)
    targets = [o for o in objects if o.type == 'MESH' and o.name.startswith(PREFIXES) and not o.get(MARKER)]
    if not targets:
        return []
    original_action = arm.animation_data.action
    original_mutes = [track.mute for track in arm.animation_data.nla_tracks]
    original_frame = bpy.context.scene.frame_current
    original_pose = {p.name: p.matrix_basis.copy() for p in arm.pose.bones}
    original_shapes = [(key, key.value) for key in shirt.data.shape_keys.key_blocks]
    for key, _ in original_shapes:
        key.value = 0
    for track in arm.animation_data.nla_tracks:
        track.mute = True
    # Fixed samples cover a whole clip. Engine extrema captures remain a
    # separate acceptance check, not an inferred continuous-collision proof.
    rest = {side: arm.data.bones[f'J_Bip_{side}_LowerArm'] for side in ('L','R')}
    raw = np.array([tuple(shirt.matrix_world @ v.co) for v in shirt.data.vertices])
    selected = {side: np.where((raw[:,0]*sign > abs(rest[side].head_local.x)-.01) &
                              (raw[:,0]*sign < abs(rest[side].tail_local.x)+.01))[0]
                for side,sign in [('L',1),('R',-1)]}
    samples = {side: [] for side in rest}
    try:
        poses = [(None, 0)]
        for name in CLIPS:
            action = bpy.data.actions.get(name)
            assert action is not None, ('Missing fitting action', name)
            start, end = action.frame_range
            poses.extend((action, float(start+(end-start)*i/16)) for i in range(17))
        for action, frame in poses:
            arm.animation_data.action = action
            for bone in arm.pose.bones:
                bone.matrix_basis = Matrix.Identity(4)
            bpy.context.scene.frame_set(math.floor(frame), subframe=frame%1)
            bpy.context.view_layer.update()
            evaluated = shirt.evaluated_get(bpy.context.evaluated_depsgraph_get())
            mesh = evaluated.to_mesh()
            assert len(mesh.vertices) == len(raw), 'Unexpected sleeve topology modifier'
            coords = np.empty(len(raw)*3, dtype=np.float32)
            mesh.vertices.foreach_get('co', coords)
            coords = coords.reshape(-1,3)
            for side in rest:
                to_rest = rest[side].matrix_local @ arm.pose.bones[rest[side].name].matrix.inverted() @ arm.matrix_world.inverted() @ evaluated.matrix_world
                transform = np.array(to_rest)
                samples[side].append(coords[selected[side]] @ transform[:3,:3].T + transform[:3,3])
            evaluated.to_mesh_clear()
    finally:
        arm.animation_data.action = original_action
        for track, mute in zip(arm.animation_data.nla_tracks, original_mutes):
            track.mute = mute
        bpy.context.scene.frame_set(original_frame)
        for bone in arm.pose.bones:
            bone.matrix_basis = original_pose[bone.name]
        for key, value in original_shapes:
            key.value = value
        bpy.context.view_layer.update()

    report = []
    for side, sign in [('L',1),('R',-1)]:
        bone = rest[side]
        cloud = np.concatenate(samples[side])
        # The authored plates use a constant Y/Z center; retain their axial
        # length and relief, expanding only each measured radial section.
        center = np.array(bone.head_local)
        length = abs(bone.tail_local.x-bone.head_local.x)
        u = (cloud[:,0]*sign-abs(center[0]))/length
        phi = np.arctan2(cloud[:,1]-center[1], cloud[:,2]-center[2])
        radius = np.linalg.norm(cloud[:,1:]-center[1:],axis=1)
        envelope = np.zeros((64,64))
        valid = (u >= 0) & (u <= 1)
        np.maximum.at(envelope, (np.clip((u[valid]*63).astype(int),0,63), ((phi[valid]+math.pi)*64/math.tau).astype(int)%64), radius[valid])
        # Cover inter-vertex chords and near-bin samples without adding nodes,
        # animation tracks, physics, or any body deformation.
        padded = np.pad(envelope,((2,2),(0,0)),mode='edge')
        envelope = np.maximum.reduce([np.roll(padded[j:j+64],k,axis=1) for j in range(5) for k in range(-2,3)])
        assert np.count_nonzero(envelope) > 3000, ('Insufficient sleeve samples', side)
        for prefix in PREFIXES:
            main = next(o for o in targets if o.name == prefix+'_'+side)
            original = np.array([tuple(main.matrix_world @ v.co) for v in main.data.vertices])
            base_radius = np.linalg.norm(original[:,1:]-center[1:],axis=1)
            for obj in targets:
                if not obj.name.startswith(prefix) or not obj.name.endswith('_'+side):
                    continue
                if '_Straps_' in obj.name:
                    report.append(fit_closure_straps(obj,shirt,arm))
                    continue
                inverse = obj.matrix_world.inverted()
                scales = []
                for vertex in obj.data.vertices:
                    p = obj.matrix_world @ vertex.co
                    along = (p.x*sign-abs(center[0]))/length
                    angle = math.atan2(p.y-center[1],p.z-center[2])
                    nearby = np.abs(original[:,0]-p.x) < .012
                    if not nearby.any():
                        nearby = np.abs(original[:,0]-p.x) <= np.min(np.abs(original[:,0]-p.x))+.001
                    base = float(np.percentile(base_radius[nearby],25))
                    needed = envelope[max(0,min(63,int(along*63))),int((angle+math.pi)*64/math.tau)%64] + .0035
                    scale = max(1.0, needed/base)
                    assert scale < 1.85, (obj.name, 'Excessive radial fitting', scale)
                    p.y = center[1]+(p.y-center[1])*scale
                    p.z = center[2]+(p.z-center[2])*scale
                    vertex.co = inverse @ p
                    scales.append(scale)
                obj.data.update()
                if obj.data.has_custom_normals:
                    obj.data.normals_split_custom_set([(0,0,0)]*len(obj.data.loops))
                obj[MARKER] = True
                report.append({'name':obj.name,'max_radial_scale':max(scales),'vertices':len(scales)})
    return report
