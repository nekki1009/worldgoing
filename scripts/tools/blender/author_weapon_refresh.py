"""Scoped axe mesh and spear/off-hand animation repair, from an immutable pack."""
import copy
import json
import math
import struct
import sys
from pathlib import Path
import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector, Quaternion

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).parent))
sys.path.insert(0, str(ROOT / 'scripts/tests'))
from repair_character_audit import tube, box, point_arm, reset_rig
from validate_chinese_cloak_assets import read_glb, accessor

WORK = ROOT / '.godot-temp/weapon_refresh_20260913'
PREFIX = 'Weapon_Axe_01_'
WOOD_PREFIX = 'Weapon_WoodAxe_01_'
PARTS = ['Haft', 'Grip', 'Grip_Wrap', 'Blade', 'Holstered_Haft', 'Holstered_Blade']
LEFT = ['J_Bip_L_' + name for name in ['UpperArm', 'LowerArm', 'Hand']]
RIGHT = ['J_Bip_R_' + name for name in ['UpperArm', 'LowerArm', 'Hand']]


def material(name, color, metal=0.0, rough=.65):
    mat = bpy.data.materials.new('AxeRefresh_' + name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Metallic'].default_value = metal
    bsdf.inputs['Roughness'].default_value = rough
    return mat


def centerline(z):
    # A monotonic gentle bow keeps the existing tube helper's frame from
    # flipping 180 degrees at the old sine curve's inflection.
    return Vector((.012 * (z / .75) ** 2, 0, z))


def axe_geometry(detail):
    meshes = {name: bmesh.new() for name in ['Haft', 'Grip', 'Grip_Wrap', 'Blade']}
    tube(meshes['Haft'], [centerline(z) for z in np.linspace(.025, .756, 24)],
         [.016 + .002 * math.sin(z * 6) for z in np.linspace(.025, .756, 24)], 16)
    tube(meshes['Grip'], [centerline(z) for z in np.linspace(.025, .23, 14)], .019, 16)
    # One continuous spiral rather than disconnected ring decorations.
    turns = 8 if detail else 1
    points = [centerline(.026 + .202 * t) + Vector((math.cos(t * turns * math.tau), math.sin(t * turns * math.tau), 0)) * .020
              for t in np.linspace(0, 1, turns * 24 + 1)]
    tube(meshes['Grip_Wrap'], points, .0015 if detail else .0005, 6)
    outline = [(.017,.705),(.017,.596),(-.037,.596),(-.068,.615),(-.095,.621),
               (-.127,.60),(-.128,.514),(-.158,.539),(-.192,.586),(-.218,.652),
               (-.224,.720),(-.208,.795),(-.185,.752),(-.045,.738),(.017,.738)]
    inset = outline.copy()
    inset[6:12] = [(-.112,.548),(-.143,.563),(-.173,.599),(-.200,.654),(-.205,.719),(-.199,.758)]
    bm = meshes['Blade']
    front, back, edge_front, edge_back = [], [], [], []
    for i, ((x,z),(ix,iz)) in enumerate(zip(outline,inset)):
        width = .0016 if 6 <= i <= 11 else .014
        edge_front.append(bm.verts.new((x, -width, z)))
        edge_back.append(bm.verts.new((x, width, z)))
        front.append(bm.verts.new((ix, -.014, iz)))
        back.append(bm.verts.new((ix, .014, iz)))
    bm.faces.new(front)
    bm.faces.new(tuple(reversed(back)))
    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        for vertices in [(front[i],edge_front[i],edge_front[j],front[j]),
                         (back[j],edge_back[j],edge_back[i],back[i])]:
            face = bm.faces.new(vertices)
            face.material_index = 1 if 5 <= i <= 11 else 0
        bm.faces.new((edge_front[i],edge_back[i],edge_back[j],edge_front[j]))
    # The socket encloses the haft; the small poll is visibly connected to it.
    tube(bm, [centerline(z) for z in [.594,.600,.730,.736]], [.022,.024,.023,.021], 16)
    box(bm, (.047,0,.669), (.075,.038,.060), .003)
    if detail:
        tube(bm, [centerline(.006),centerline(.026)], [.023,.020], 16)
        for z in [.032,.228,.598]:
            tube(bm, [centerline(z-.004),centerline(z+.004)], .022, 16)
        # Small bronze pin, geometry detail only; no unconsumed texture workflow.
        old = set(bm.faces)
        tube(bm, [(0,-.026,.613),(0,.026,.613)], .004, 12)
        for face in set(bm.faces) - old:
            face.material_index = 2
    return meshes


def replace_axe(arm, detail):
    steel = material('ForgedSteel', (.12,.15,.18) if detail else (.4,.4,.4), .72, .4)
    edge = material('CuttingBevel', (.54,.61,.67) if detail else (.4,.4,.4), .85, .25)
    brass = material('Pin', (.31,.22,.10) if detail else (.4,.4,.4), .65, .42)
    wood = material('AshWood', (.105,.063,.032) if detail else (.4,.4,.4))
    leather = material('Leather', (.047,.029,.019) if detail else (.4,.4,.4), 0,.85)
    meshes = axe_geometry(detail)
    # Match the old held axe's palm center and blade plane, not the camera.
    palm = arm.data.bones['J_Bip_R_Hand'].matrix_local @ Vector((0,.045,-.015))
    rotation = Matrix(((0,-1,0),(0,0,-1),(1,0,0)))
    held = Matrix.Translation(palm - rotation @ centerline(.13)) @ rotation.to_4x4()
    old = bpy.data.objects[PREFIX+'Holstered_Haft']
    vertices = np.array([old.matrix_world @ v.co for v in old.data.vertices])
    center = vertices.mean(axis=0)
    _,_,basis = np.linalg.svd(vertices-center, full_matrices=False)
    direction = Vector(basis[0]); direction *= 1 if direction.z > 0 else -1
    bottom = Vector(center) - direction * .37
    back_rotation = Vector((0,0,1)).rotation_difference(direction).to_matrix()
    holstered = Matrix.Translation(bottom) @ back_rotation.to_4x4()
    # Keep exactly the existing six names/nodes. Holstered groups reuse the same
    # actual blade and handle geometry, not the previous flat proxy shapes.
    for name in PARTS:
        on_back = name.startswith('Holstered_')
        source = name.removeprefix('Holstered_')
        bm = meshes[source].copy()
        if name == 'Holstered_Haft':
            for extra in ['Grip','Grip_Wrap']:
                temporary = bpy.data.meshes.new('AxeJoinTemp')
                meshes[extra].to_mesh(temporary)
                for polygon in temporary.polygons:
                    polygon.material_index = 1
                bm.from_mesh(temporary)
                bpy.data.meshes.remove(temporary)
        obj = bpy.data.objects[PREFIX+name]
        transform = holstered if on_back else held
        bmesh.ops.transform(bm, matrix=obj.matrix_world.inverted() @ transform, verts=bm.verts)
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=.000001)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        old_mesh = obj.data
        obj.data = bpy.data.meshes.new(obj.name+'Refreshed')
        bm.to_mesh(obj.data); bm.free()
        materials = [steel,edge,brass] if source == 'Blade' else [wood if source == 'Haft' else leather]
        if name == 'Holstered_Haft':
            materials.append(leather)
        for mat in materials:
            obj.data.materials.append(mat)
        obj.vertex_groups.clear()
        group = obj.vertex_groups.new(name='J_Bip_C_UpperChest' if on_back else 'J_Bip_R_Hand')
        group.add(list(range(len(obj.data.vertices))), 1.0, 'REPLACE')
        for face in obj.data.polygons:
            face.use_smooth = source != 'Blade'
        if old_mesh.users == 0:
            bpy.data.meshes.remove(old_mesh)
    for bm in meshes.values():
        bm.free()


def fix_actions(arm, sex):
    guard = bpy.data.actions['guard']
    reset_rig(arm); arm.animation_data.action = guard
    bpy.context.scene.frame_set(int(sum(guard.frame_range)/2))
    bpy.context.view_layer.update()
    # Shield is rigid to the forearm, not the hand. Keep its guard orientation
    # in rig space: a fixed local pose inherits the source clavicle's rearward
    # swing and turns the shield inside-out during the axe follow-through.
    left_pose = {name: arm.pose.bones[name].matrix.to_quaternion() for name in LEFT}
    # Open the left elbow to the shield side. The original guard crossed the
    # chest, placing the extended right forearm through the shield in a thrust.
    upper_rest = arm.data.bones[LEFT[0]].matrix_local.to_quaternion()
    left_pose[LEFT[0]] = (upper_rest @ Vector((0,1,0))).rotation_difference(Vector((.85,-.25,-.4)).normalized()) @ upper_rest
    if sex == 'female':
        # The female guard's forearm crosses farther inward. Open it separately
        # instead of scaling/moving the body or reusing the male clearance.
        outward = Quaternion(Vector((0,0,1)), math.radians(35))
        for name in LEFT[1:]:
            left_pose[name] = outward @ left_pose[name]
    modified = {}
    for clip in ['attack_spear','attack_axe']:
        action = bpy.data.actions[clip]
        first,last = map(float,action.frame_range)
        arm.animation_data.action = action
        original = []
        # Match the runtime's 120 Hz pose sampling. A 48 Hz hand bake can
        # interpolate through a different elbow solution near full extension.
        times = np.linspace(first,last,round((last-first)*5)+1)
        for frame in times:
            bpy.context.scene.frame_set(int(frame), subframe=frame%1)
            bpy.context.view_layer.update()
            original.append((arm.pose.bones['J_Bip_R_Hand'].matrix @ Vector((0,.045,-.015))).copy())
        stable_x = float(np.median([p.x for p in original]))
        stable_z = float(np.median([p.z for p in original]))
        start_y = original[0].y
        peak_y = min(p.y for p in original)
        affected = LEFT + (RIGHT if clip == 'attack_spear' else [])
        # Sample the original remaining body tracks before replacing just these
        # six/three arm bones; legs, torso, event timing and other clips survive.
        baked = []
        for frame in times:
            bpy.context.scene.frame_set(int(frame), subframe=frame%1)
            for name, pose in left_pose.items():
                bone = arm.pose.bones[name]
                bone.matrix = Matrix.LocRotScale(bone.head.copy(), pose, None)
                bpy.context.view_layer.update()
            bpy.context.view_layer.update()
            if clip == 'attack_spear':
                t = (frame-first)/(last-first)
                keys = [(0,0),(.20,0),(.38,1),(.56,1),(.88,0),(1,0)]
                segment = next((a,b) for a,b in zip(keys,keys[1:]) if a[0] <= t <= b[0])
                a,b = segment; f = (t-a[0])/(b[0]-a[0]); f = f*f*(3-2*f)
                extension = a[1]*(1-f)+b[1]*f
                palm = Vector((stable_x,start_y+(peak_y-start_y)*extension,stable_z))
                rest = arm.data.bones['J_Bip_R_Hand'].matrix_local.to_3x3()
                turn = Vector((0,-1,0)).rotation_difference(Vector((0,-1,.035)).normalized())
                hand_basis = turn.to_matrix() @ rest
                offset = hand_basis @ Vector((0,.045,-.015))
                shoulder = arm.pose.bones['J_Bip_R_UpperArm'].head.copy()
                reach = sum(arm.pose.bones['J_Bip_R_'+p].length for p in ['UpperArm','LowerArm']) - .005
                delta = palm-offset-shoulder
                if delta.length > reach:
                    palm = shoulder+delta.normalized()*reach+offset
                point_arm(arm,'R',palm,hand_basis)
            baked.append({name: arm.pose.bones[name].matrix_basis.copy() for name in affected})
        for curve in list(action.fcurves):
            if any(curve.data_path.startswith('pose.bones["'+name+'"]') for name in affected):
                action.fcurves.remove(curve)
        for frame, pose in zip(times,baked):
            for name, matrix in pose.items():
                bone = arm.pose.bones[name]
                bone.rotation_mode = 'QUATERNION'
                bone.matrix_basis = matrix
                for path in ['location','rotation_quaternion','scale']:
                    bone.keyframe_insert(path, frame=float(frame), group=name)
        for curve in action.fcurves:
            if any(curve.data_path.startswith('pose.bones["'+name+'"]') for name in affected):
                for key in curve.keyframe_points:
                    key.interpolation = 'LINEAR'
        modified[clip] = affected
    reset_rig(arm)
    return modified


def render_gray(arm, sex):
    """Unretouched Blender workbench views before adding finish details."""
    scene = bpy.context.scene
    reset_rig(arm)
    for obj in scene.objects:
        if obj.type == 'MESH':
            obj.hide_render = not (obj.name == 'Body' or obj.name.startswith('Body_') or
                                   (obj.name.startswith(PREFIX) and 'Holstered' not in obj.name))
    camera_data = bpy.data.cameras.new('WeaponReviewCamera')
    camera = bpy.data.objects.new('WeaponReviewCamera', camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera_data.type = 'ORTHO'; camera_data.ortho_scale = 2.4
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'SINGLE'
    scene.display.shading.single_color = (.55,.55,.55)
    scene.display.shading.show_shadows = True
    scene.render.resolution_x = scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    destination = ROOT / 'output/weapon_refresh_20260913/blender_gray'
    destination.mkdir(parents=True, exist_ok=True)
    center = Vector((0,0,.9))
    for name, position in [('front',(0,-5,.9)),('back',(0,5,.9)),('side',(5,0,.9)),('three_quarter',(3,-5,1.1))]:
        camera.location = position
        camera.rotation_euler = (center-camera.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath = str(destination/f'{sex}_{name}.png')
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(camera, do_unlink=True)


def splice(source, subset, target, modified, skip_meshes=False):
    doc,raw = read_glb(source); new,new_raw = read_glb(subset)
    binary = bytearray(raw); copied = {}; mats = {}
    def copy_accessor(index):
        if index in copied: return copied[index]
        acc = copy.deepcopy(new['accessors'][index]); assert 'sparse' not in acc
        view = copy.deepcopy(new['bufferViews'][acc['bufferView']])
        begin = view.get('byteOffset',0)
        binary.extend(b'\0'*(-len(binary)%4)); view['byteOffset'] = len(binary)
        binary.extend(new_raw[begin:begin+view['byteLength']])
        acc['bufferView'] = len(doc['bufferViews']); doc['bufferViews'].append(view)
        copied[index] = len(doc['accessors']); doc['accessors'].append(acc)
        return copied[index]
    def copy_material(index):
        if index not in mats:
            mat = copy.deepcopy(new['materials'][index])
            assert not any('Texture' in k for k in mat.get('pbrMetallicRoughness',{}))
            mats[index] = len(doc['materials']); doc['materials'].append(mat)
        return mats[index]
    nodes = {node['name']: (i,node) for i,node in enumerate(doc['nodes'])}
    for node in new['nodes']:
        if skip_meshes: continue
        if 'mesh' not in node: continue
        assert node['name'].startswith(PREFIX)
        _,old = nodes[node['name']]
        old_skin,new_skin = doc['skins'][old['skin']],new['skins'][node['skin']]
        assert [doc['nodes'][i]['name'] for i in old_skin['joints']] == [new['nodes'][i]['name'] for i in new_skin['joints']]
        assert np.allclose(accessor(doc,raw,old_skin['inverseBindMatrices']),accessor(new,new_raw,new_skin['inverseBindMatrices']),atol=1e-6)
        mesh = copy.deepcopy(new['meshes'][node['mesh']])
        for part in mesh['primitives']:
            part['attributes'] = {k:copy_accessor(v) for k,v in part['attributes'].items()}
            part['indices'] = copy_accessor(part['indices'])
            part['material'] = copy_material(part['material'])
        doc['meshes'][old['mesh']] = mesh
    for clip,affected in modified.items():
        original = next(a for a in doc['animations'] if a['name']==clip)
        exported = next(a for a in new['animations'] if a['name']==clip)
        channels = {}
        for channel in exported['channels']:
            name = new['nodes'][channel['target']['node']]['name']
            if name not in affected: continue
            sampler = copy.deepcopy(exported['samplers'][channel['sampler']])
            sampler['input'] = copy_accessor(sampler['input']); sampler['output'] = copy_accessor(sampler['output'])
            changed = copy.deepcopy(channel); changed['target']['node'] = nodes[name][0]
            changed['sampler'] = len(original['samplers']); original['samplers'].append(sampler)
            channels[(name,channel['target']['path'])] = changed
        for i,channel in enumerate(original['channels']):
            key = (doc['nodes'][channel['target']['node']]['name'],channel['target']['path'])
            if key in channels: original['channels'][i] = channels.pop(key)
        original['channels'].extend(channels.values())
    binary.extend(b'\0'*(-len(binary)%4)); doc['buffers'][0]['byteLength'] = len(binary)
    encoded = json.dumps(doc,separators=(',',':')).encode(); encoded += b' '*(-len(encoded)%4)
    target.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(binary))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+struct.pack('<I4s',len(binary),b'BIN\0')+binary)


def clone_logging_axe():
    for name in PARTS:
        assert WOOD_PREFIX + name not in bpy.data.objects
        old = bpy.data.objects[PREFIX + name]
        obj = old.copy()
        obj.name = WOOD_PREFIX + name
        obj['visual_id'] = 'wood_axe_01'
        old.users_collection[0].objects.link(obj)


def append_logging_glb(source, target):
    before, original = read_glb(source)
    doc, binary = read_glb(target)
    assert binary[:len(original)] == original
    assert not any(n.get('name', '').startswith(WOOD_PREFIX) for n in doc['nodes'])
    for index, old in enumerate(before['nodes']):
        if old.get('name') not in {PREFIX + p for p in PARTS}:
            continue
        node = copy.deepcopy(old)
        node['name'] = node['name'].replace(PREFIX, WOOD_PREFIX, 1)
        node['mesh'] = len(doc['meshes'])
        # Reuse original accessors, materials, skin and binary bytes exactly.
        doc['meshes'].append(copy.deepcopy(before['meshes'][old['mesh']]))
        parent = next(i for i, n in enumerate(before['nodes']) if index in n.get('children', []))
        doc['nodes'][parent]['children'].append(len(doc['nodes']))
        doc['nodes'].append(node)
    encoded = json.dumps(doc, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    target.write_bytes(struct.pack('<4sII', b'glTF', 2, 28 + len(encoded) + len(binary)) +
                      struct.pack('<I4s', len(encoded), b'JSON') + encoded +
                      struct.pack('<I4s', len(binary), b'BIN\0') + binary)


def add_logging_metadata(metadata):
    metadata['parts']['weapon'].extend(WOOD_PREFIX + p for p in PARTS)
    metadata['weapon_refresh']['preserved_logging_axe'] = {
        'id': 'wood_axe_01', 'label': '伐木斧', 'prefix': WOOD_PREFIX.rstrip('_'),
        'source': 'baseline original axe; unchanged geometry, materials and skin'}


def keep_old(sex):
    """Upgrade the reviewed candidate without resampling its repaired actions."""
    source = WORK / 'baseline' / sex
    dest = WORK / 'candidate' / sex
    bpy.ops.wm.open_mainfile(filepath=str(source.with_suffix('.blend')))
    originals = {}
    for part in PARTS:
        obj = bpy.data.objects[PREFIX + part]
        originals[part] = (obj.data.name, [g.name for g in obj.vertex_groups],
                           obj.matrix_basis.copy(), obj.matrix_parent_inverse.copy())
    bpy.ops.wm.open_mainfile(filepath=str(dest.with_suffix('.blend')))
    bpy.context.preferences.filepaths.save_version = 0
    # Import only the original meshes, never a second skeleton or animation set.
    with bpy.data.libraries.load(str(source.with_suffix('.blend')), link=False) as (_, loaded):
        loaded.meshes = [originals[p][0] for p in PARTS]
    for part, mesh in zip(PARTS, loaded.meshes):
        assert mesh is not None and WOOD_PREFIX + part not in bpy.data.objects
        obj = bpy.data.objects[PREFIX + part].copy()
        obj.data = mesh
        obj.name = WOOD_PREFIX + part
        obj['visual_id'] = 'wood_axe_01'
        assert [g.name for g in obj.vertex_groups] == originals[part][1], part
        obj.matrix_basis = originals[part][2]
        obj.matrix_parent_inverse = originals[part][3]
        bpy.context.scene.collection.objects.link(obj)
    assert len([o for o in bpy.data.objects if o.type == 'ARMATURE']) == 1
    bpy.ops.wm.save_as_mainfile(filepath=str(dest.with_suffix('.blend')))
    append_logging_glb(source.with_suffix('.glb'), dest.with_suffix('.glb'))
    metadata = json.loads(dest.with_suffix('.json').read_text(encoding='utf-8'))
    add_logging_metadata(metadata)
    dest.with_suffix('.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding='utf-8')
    print('LOGGING_AXE_PRESERVED', sex, 'six original meshes; existing rig/actions unchanged', flush=True)


def main(sex,stage):
    if stage == 'keep_old':
        keep_old(sex)
        return
    source = WORK/'baseline'/sex; dest = WORK/'candidate'/sex
    bpy.ops.wm.open_mainfile(filepath=str(source.with_suffix('.blend')))
    bpy.context.preferences.filepaths.save_version = 0
    arm = bpy.data.objects['Armature']
    mutes = {t.name:t.mute for t in arm.animation_data.nla_tracks}
    reset_rig(arm)
    clone_logging_axe()
    replace_axe(arm,stage=='final')
    modified = fix_actions(arm, sex)
    for track in arm.animation_data.nla_tracks: track.mute = mutes[track.name]
    bpy.ops.wm.save_as_mainfile(filepath=str(dest.with_suffix('.blend')))
    # Temporary export contains only the six scoped meshes and two repaired
    # actions. The splice preserves every other channel and morph byte.
    for action in list(bpy.data.actions):
        if action.name not in modified: bpy.data.actions.remove(action)
    parts = [bpy.data.objects[PREFIX+n] for n in PARTS]
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [arm,*parts]:
        obj.hide_set(False); obj.hide_viewport=False; obj.select_set(True)
    bpy.context.view_layer.objects.active=arm
    subset = dest.with_name(sex+'_subset.glb')
    bpy.ops.export_scene.gltf(filepath=str(subset),export_format='GLB',use_selection=True,
        export_apply=False,export_animations=True,export_animation_mode='ACTIONS',
        export_frame_range=False,export_force_sampling=False,export_skins=True,export_morph=False)
    splice(source.with_suffix('.glb'),subset,dest.with_suffix('.glb'),modified)
    append_logging_glb(source.with_suffix('.glb'),dest.with_suffix('.glb'))
    metadata=json.loads(source.with_suffix('.json').read_text(encoding='utf-8'))
    metadata['weapon_refresh']={'date':'2026-09-13','stage':stage,'reference':'output/weapon_refresh_20260913/reference/battle_axe_reference.png','parts':PARTS,'bones':modified}
    add_logging_metadata(metadata)
    dest.with_suffix('.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
    if stage == 'gray':
        render_gray(arm, sex)
    print('WEAPON_REFRESH_CANDIDATE',sex,stage,flush=True)

if __name__=='__main__':
    main(*sys.argv[sys.argv.index('--')+1:])
