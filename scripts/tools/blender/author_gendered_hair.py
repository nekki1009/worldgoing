"""Author only styles 05-08 on the measured male/female head, preserving the pack.

Run with Blender: --python author_gendered_hair.py -- male [--gray]
Re-running is explicit re-authoring; ordinary pack builds load the saved meshes.
"""
import copy
import json
import math
import struct
import sys
from pathlib import Path
import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[3]
WORK = ROOT / 'assets/characters/human/q35/hair_gendered'
BASE = ROOT / '.godot-temp/hair_gendered/baseline'
sys.path.insert(0, str(Path(__file__).parent))
sys.path.insert(0, str(ROOT/'scripts/tests'))
from build_standard_anime_male_character_pack import material, add_armature_skin
from repair_character_audit import _smooth_hair_lock
from validate_chinese_cloak_assets import read_glb, accessor


def make_styles(arm, sex):
    female = sex == 'female'
    prefix = 'Hair_Female_' if female else 'Hair_Male_'
    center = Vector((-.00034, .020, 1.515)) if female else Vector((-.00051, .007, 1.635))
    scale = .94 if female else 1.0
    verts, faces = [], []
    # Ray-fit the cap to actual skin, not a scaled copy of the other gender.
    for name in [('Body_Standard_Female' if female else 'Body_Standard_Male'), 'Face_Standard_01']:
        obj = bpy.data.objects[name]
        offset = len(verts)
        verts.extend(obj.matrix_world @ v.co for v in obj.data.vertices)
        faces.extend(tuple(offset+i for i in p.vertices) for p in obj.data.polygons)
    skin = BVHTree.FromPolygons(verts, faces)
    hairmat = material(f'Hair_{sex}_Dyeable', (.020, .019, .026), roughness=.78)
    tie_mat = material(f'Hair_{sex}_Tie', (.025, .018, .014), roughness=.84)
    result = []

    def point(x, y, z):
        return center + Vector((x, y, z))*scale

    def scalp(a, theta, lift=.010):
        direction = Vector((math.sin(theta)*math.sin(a), -math.sin(theta)*math.cos(a), math.cos(theta)))
        hit = skin.ray_cast(center+direction*.36, -direction, .36)
        if hit[0] is None:
            radius = 1/math.sqrt((direction.x/.109)**2+(direction.y/.125)**2+(direction.z/.119)**2)*scale
            return center+direction*(radius+lift)
        return hit[0]+direction*lift

    def hairline(a, index):
        front, back = max(math.cos(a),0),max(-math.cos(a),0)
        if not female and index == 8:
            return 1.56-.40*front+.42*back
        # The source face includes ears. Lift the boundary over them instead
        # of ray-fitting a layer of hair onto the ear itself.
        edge = 2.12-.96*front**2-.47*abs(math.sin(a))**10+.022*math.sin(a*17)
        if (not female and index in [5,7]) or (female and index in [6,8]): edge -= .18*front**3
        if female and index == 5: edge -= .08*(1-front)
        return edge

    def lock(bm, pts, widths, normal=(0,-1,0), relative=True, thickness=.20):
        guides = [point(*p) for p in pts] if relative else pts
        _smooth_hair_lock(bm, guides, [w*scale for w in widths], Vector(normal), thickness)

    def finish(bm, name, index, mat=hairmat):
        bm.verts.ensure_lookup_table()
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        mesh = bpy.data.meshes.new(name+'Mesh')
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        mesh.materials.append(mat)
        mesh.materials.append(mat)  # Existing lock helper uses material slot 1.
        for poly in mesh.polygons: poly.use_smooth = True
        # Untextured material, but valid UVs keep export/tangent paths complete.
        uv = mesh.uv_layers.new(name='UVMap')
        for poly in mesh.polygons:
            for li in poly.loop_indices:
                p = mesh.vertices[mesh.loops[li].vertex_index].co-center
                uv.data[li].uv = (math.atan2(p.x,p.y)/math.tau+.5, p.z/.6+.5)
        obj['worldgoing_component_slot'] = 'hair'
        obj['worldgoing_visual_id'] = f'hair_{sex}_{index:02d}'
        add_armature_skin(obj, arm, 'J_Bip_C_Head')
        if index == 7 or (female and index == 8):
            # Keep long ends with the shoulder/chest during motion using the
            # existing rig. No new hair skeleton, simulation or animation loop.
            neck_z = (arm.matrix_world @ arm.data.bones['J_Bip_C_Neck'].head_local).z
            head = obj.vertex_groups['J_Bip_C_Head']
            chest = obj.vertex_groups.new(name='J_Bip_C_UpperChest')
            for v in mesh.vertices:
                blend = min(.88,max(0,(neck_z+.025-v.co.z)/.15))
                head.add([v.index],1-blend,'REPLACE')
                if blend: chest.add([v.index],blend,'REPLACE')
        result.append(obj)
        return obj

    def braid(bm, guides, width):
        # Three interwoven closed locks, not beads. The centerline remains
        # outside neck/shoulder space and the tip has a visible taper.
        for phase in range(3):
            pts, widths = [], []
            for i in range(33):
                t = i/32
                f = t*(len(guides)-1)
                segment = min(int(f),len(guides)-2)
                p = Vector(guides[segment]).lerp(Vector(guides[segment+1]), f-segment)
                r = width*(1-.75*t)
                angle = t*math.tau*3.25+phase*math.tau/3
                p.x += math.sin(angle)*r*.46
                p.y += math.cos(angle)*r*.33
                pts.append(tuple(p)); widths.append(r*.8)
            lock(bm,pts,widths,thickness=.43)

    for index in range(5,9):
        bm = bmesh.new()
        cropped = (not female and index == 8)
        rows = []
        for row in range(25):
            ring = []
            for col in range(96):
                a = col*math.tau/96
                # Higher front boundary, temples above ears, lower back/nape.
                theta_end = hairline(a,index)
                theta = .012+(theta_end-.012)*row/24
                lift = .0045 if cropped else .010
                ring.append(bm.verts.new(scalp(a,theta,lift)))
            rows.append(ring)
        for row,nxt in zip(rows,rows[1:]):
            for col in range(96): bm.faces.new((row[col],row[(col+1)%96],nxt[(col+1)%96],nxt[col]))
        bm.faces.new(rows[0][::-1])
        # Flowing overlapping crown locks establish groom direction and avoid
        # a bare smooth helmet-like cap. Front bangs are separate below.
        for col in range(28 if not cropped else 40):
            a = col*math.tau/(28 if not cropped else 40)
            end = hairline(a,index)
            start = .13 if not cropped else .20
            if not female and index == 6:
                # Slick-back ridges run front-to-back over the entire crown.
                if col >= 13: continue
                u = (col-6)*.11
                pts = []
                for t in [-1.20,-1.05,-.65,-.15,.40,.95,1.50,1.94]:
                    d = Vector((u,math.sin(t),math.cos(t))).normalized()
                    pts.append(scalp(math.atan2(d.x,-d.y),math.acos(d.z),.003 if t == -1.20 else .013))
                lock(bm,pts,[.002,.016,.025,.027,.027,.024,.018,0],(0,0,1),False,.09)
            else:
                if not female and index in [5,7] and math.cos(a) > .18: continue
                if female and index in [6,8] and math.cos(a) > .18: continue
                if cropped:
                    end = min(end,1.3)
                pts = [scalp(a+.12*math.sin(t),start+(end-start)*t,.008 if cropped else .014) for t in [0,.25,.5,.75,1]]
                width = .014 if cropped else .029
                lock(bm,pts,[width*.3,width,width,width*.8,0],(math.sin(a),-math.cos(a),.2),False,.09)

        if not female:
            if index in [5,7]:
                for sign in [-1,1]:
                    for strand in range(4):
                        s = strand/3
                        pts = [scalp(sign*(.12+.10*s),.27,.009),scalp(sign*(.38+.20*s),.84,.020),scalp(sign*(.72+.18*s),1.43,.024),point(sign*(.097+.012*s),-.082,-.025-.025*s)]
                        lock(bm,pts,[.010,.035,.032,0],(0,-1,0),False,.13)
                    lock(bm,[(sign*.007,-.064,.121),(sign*.026,-.116,.076),(sign*.060,-.124,.016),(sign*.091,-.094,-.041)],[.009,.033,.036,0],thickness=.13)
            if index == 6:
                for sign in [-1,1]:
                    for row in range(4):
                        t = 1.12+row*.16
                        pts = [scalp(sign*a,t+(a-.9)*.21,.011) for a in [.9,1.35,1.85,2.3,2.75]]
                        lock(bm,pts,[.009,.020,.022,.018,0],(sign,0,.2),False,.09)
            if index == 7:
                anchor = tuple((scalp(math.pi,1.67,.002)-center)/scale)
                braid(bm,[anchor,(0,.125,-.105),(0,.150,-.168),(0,.158,-.230)],.035)
            if index == 8:
                for col in range(11):
                    a = (col-5)*.20
                    pts = [scalp(a,t,.007) for t in [.71,.88,1.10,1.22]]
                    lock(bm,pts,[.008,.017,.015,0],(0,-1,0),False,.16)
        else:
            if index in [5,7]:
                for strand in range(7):
                    s = strand/6
                    root = scalp(-.18*s,.32,.008)
                    pts = [root,point(.035-.113*s,-.110,.095),point(.017-.12*s,-.119,.035),point(-.038-.073*s,-.092,-.018-.055*s)]
                    lock(bm,pts,[.009,.031,.032,0],(0,-1,0),False,.13)
            if index in [6,8]:
                for sign in [-1,1]:
                    for strand in range(3):
                        s = strand/2
                        root = scalp(sign*.15,.30,.010)
                        lock(bm,[root,point(sign*(.045+.023*s),-.112,.078),point(sign*(.091+.012*s),-.106,-.021),point(sign*(.079+.019*s),-.084,-.114)],[.011,.032,.028,0],(0,-1,0),False,.13)
            if index == 7:
                braid(bm,[(.069,.077,-.05),(.130,.012,-.130),(.146,-.085,-.207),(.145,-.126,-.269),(.131,-.148,-.315)],.040)
            if index == 8:
                loose = bmesh.new()
                for col in range(11):
                    a = math.pi*.47 + math.pi*1.06*col/10
                    x,y = math.sin(a),-math.cos(a)
                    pts = [scalp(a,.75,.009),scalp(a,1.25,.014),point(x*.112,y*.136,-.043),point(x*.135,y*.155,-.124),point(x*.102,y*.171,-.202),point(x*.132,y*.151,-.279+.018*math.cos(col))]
                    lock(loose,pts,[.008,.029,.038,.041,.031,0],(x,y,.05),False,.13)
                finish(loose,prefix+'08_Loose',8)
                for sign in [-1,1]:
                    for row in range(3):
                        pts = [scalp(sign*a,t+row*.09,.015) for a,t in [(1.0,.97),(1.55,1.13),(2.2,1.29),(2.8,1.36)]]
                        pts.append(point(0,.124,.010))
                        lock(bm,pts,[.012,.025,.023,.017,0],(0,1,.2),False,.09)
        finish(bm,prefix+f'{index:02d}',index)
        if female and index == 6:
            # Buns remain independent so helmets can tuck these volumes away
            # without hiding the face-framing hair.
            bun = bmesh.new()
            for sign in [-1,1]:
                ball = bmesh.ops.create_uvsphere(bun,u_segments=24,v_segments=16,radius=1)['verts']
                for v in ball: v.co = point(sign*.104+v.co.x*.035,.035+v.co.y*.041,.080+v.co.z*.038)
                pts = []
                for step in range(65):
                    t = step/64
                    a = t*math.tau*3.4
                    r = .039*(1-t*.92)
                    pts.append((sign*(.104+.033*math.sqrt(1-(r/.043)**2)),.035+r*math.cos(a),.080+r*math.sin(a)))
                lock(bun,pts,[.010]*64+[.002],(sign,0,0),thickness=.38)
            finish(bun,prefix+'06_Buns',6)
        if index == 7 or (female and index == 8):
            band = bmesh.new()
            cx,cy,cz = ((.136,-.140,-.297) if female else (0,.156,-.212)) if index == 7 else (0,.124,.010)
            pts = [(cx+.018*math.cos(a),cy+.012*math.sin(a),cz) for a in [i*math.tau/24 for i in range(25)]]
            lock(band,pts,[.007]*24+[.004],(0,0,1),thickness=.40)
            finish(band,prefix+f'{index:02d}_Band',index,tie_mat)
    return result


def merge_hair(base, subset, destination):
    """Append selected meshes to the existing skin; keep all original bytes."""
    doc,binary = read_glb(base)
    new,nb = read_glb(subset)
    binary = bytearray(binary)
    old_names = {n.get('name'):i for i,n in enumerate(doc['nodes'])}
    existing_mesh = next(n for n in doc['nodes'] if n.get('name','').startswith('Hair_') and 'mesh' in n)
    skin_index = existing_mesh['skin']
    old_skin = doc['skins'][skin_index]
    old_parent = next(i for i,n in enumerate(doc['nodes']) if doc['nodes'].index(existing_mesh) in n.get('children',[]))
    material_map = {}
    for i,m in enumerate(new.get('materials',[])):
        assert not any('Texture' in k for k in m.get('pbrMetallicRoughness',{})), 'New hair is intentionally untextured'
        material_map[i] = len(doc['materials'])
        doc['materials'].append(m)
    def append_acc(index):
        acc = copy.deepcopy(new['accessors'][index])
        assert 'sparse' not in acc
        view = copy.deepcopy(new['bufferViews'][acc['bufferView']])
        binary.extend(b'\0'*(-len(binary)%4))
        start = view.get('byteOffset',0)
        view['byteOffset'] = len(binary)
        binary.extend(nb[start:start+view['byteLength']])
        acc['bufferView'] = len(doc['bufferViews'])
        doc['bufferViews'].append(view)
        doc['accessors'].append(acc)
        return len(doc['accessors'])-1
    for node in new['nodes']:
        if 'mesh' not in node: continue
        assert node['name'].startswith(('Hair_Male_','Hair_Female_')) and node['name'] not in old_names
        ns = new['skins'][node['skin']]
        assert [doc['nodes'][i]['name'] for i in old_skin['joints']] == [new['nodes'][i]['name'] for i in ns['joints']]
        assert (abs(accessor(doc,binary,old_skin['inverseBindMatrices'])-accessor(new,nb,ns['inverseBindMatrices'])) < 1e-6).all()
        mesh = copy.deepcopy(new['meshes'][node['mesh']])
        for p in mesh['primitives']:
            p['attributes'] = {k:append_acc(v) for k,v in p['attributes'].items()}
            p['indices'] = append_acc(p['indices'])
            p['material'] = material_map[p['material']]
        appended = copy.deepcopy(node)
        appended['mesh'] = len(doc['meshes'])
        appended['skin'] = skin_index
        doc['meshes'].append(mesh)
        doc['nodes'][old_parent]['children'].append(len(doc['nodes']))
        doc['nodes'].append(appended)
    doc['buffers'][0]['byteLength'] = len(binary)
    binary.extend(b'\0'*(-len(binary)%4))
    encoded = json.dumps(doc,separators=(',',':')).encode()
    encoded += b' '*(-len(encoded)%4)
    destination.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(encoded)+len(binary))+struct.pack('<I4s',len(encoded),b'JSON')+encoded+struct.pack('<I4s',len(binary),b'BIN\0')+binary)


def gray_preview(sex, hair):
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.render.resolution_x, scene.render.resolution_y = 512,640
    scene.render.resolution_percentage = 100
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'OBJECT'
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.display.shading.cavity_type = 'BOTH'
    scene.display.shading.background_type = 'WORLD'
    if scene.world is None: scene.world = bpy.data.worlds.new('HairGrayWorld')
    scene.world.color = (.18,.18,.18)
    arm = bpy.data.objects['Armature']
    arm.data.pose_position = 'REST'
    for obj in bpy.data.objects:
        obj.hide_viewport = False
        obj.hide_set(False)
        obj.hide_render = obj.type == 'MESH'
    for name in ['Body_Standard_Female' if sex == 'female' else 'Body_Standard_Male','Face_Standard_01']:
        bpy.data.objects[name].hide_render = False
        bpy.data.objects[name].color = (.67,.67,.67,1)
    camera_data = bpy.data.cameras.new('HairGrayCamera')
    camera = bpy.data.objects.new('HairGrayCamera',camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera_data.type = 'ORTHO'
    camera_data.ortho_scale = .66
    center = Vector((0,0,1.54 if sex == 'male' else 1.40))
    out = ROOT/f'.visual_captures/hair_gendered/blender_{sex}'
    out.mkdir(parents=True,exist_ok=True)
    for index in range(5,9):
        for obj in hair:
            obj.hide_render = obj.get('worldgoing_visual_id') != f'hair_{sex}_{index:02d}'
            obj.color = (.22,.22,.22,1)
        for name,offset in [('front',(0,-4,0)),('side',(4,0,0)),('back',(0,4,0))]:
            camera.location = center+Vector(offset)
            camera.rotation_euler = (center-camera.location).to_track_quat('-Z','Y').to_euler()
            scene.render.filepath = str(out/f'{index:02d}_{name}.png')
            bpy.ops.render.render(write_still=True)


def main():
    args = sys.argv[sys.argv.index('--')+1:]
    sex = args[0]
    assert sex in ['male','female']
    stem = f'standard_anime_{sex}_character_pack'
    bpy.ops.wm.open_mainfile(filepath=str(BASE/(stem+'.blend')))
    bpy.context.preferences.filepaths.save_version = 0
    arm = bpy.data.objects['Armature']
    hair = make_styles(arm,sex)
    # This full editable snapshot preserves all older assets and is the source
    # loaded by the pack builders for these new options.
    bpy.ops.wm.save_as_mainfile(filepath=str(WORK/f'candidate_{sex}.blend'))
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [arm,*hair]:
        obj.hide_viewport = False
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    subset = ROOT/f'.godot-temp/hair_gendered/{sex}_new_hair.glb'
    bpy.ops.export_scene.gltf(filepath=str(subset),export_format='GLB',use_selection=True,export_apply=False,export_animations=False,export_skins=True,export_morph=False)
    merge_hair(BASE/(stem+'.glb'),subset,WORK/f'candidate_{sex}.glb')
    metadata = json.loads((BASE/(stem+'.json')).read_text(encoding='utf-8'))
    metadata['parts']['hair'].extend(o.name for o in hair)
    metadata['hair_style_ids'] = [f'hair_{sex}_{i:02d}' for i in range(1,9)]
    (WORK/f'candidate_{sex}.json').write_text(json.dumps(metadata,ensure_ascii=False,indent=2),encoding='utf-8')
    if '--gray' in args: gray_preview(sex,hair)
    print('GENDERED_HAIR_CANDIDATE_PASS',sex,[o.name for o in hair],flush=True)


if __name__ == '__main__': main()
