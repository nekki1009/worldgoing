"""Small shared arrow, bolt and wearable ammunition containers, in metres."""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector


def build_props(destination):
    materials = []
    for name, color, metallic in [('Wood', (.27, .14, .055), 0), ('Steel', (.33, .38, .40), .75),
                                  ('Feather', (.72, .67, .49), 0), ('Leather', (.10, .047, .02), 0),
                                  ('Trim', (.39, .22, .075), .25)]:
        material = bpy.data.materials.new('CombatProp_' + name)
        material.diffuse_color = (*color, 1)
        material.use_nodes = True
        shader = material.node_tree.nodes['Principled BSDF']
        shader.inputs['Base Color'].default_value = (*color, 1)
        shader.inputs['Metallic'].default_value = metallic
        shader.inputs['Roughness'].default_value = .7
        materials.append(material)

    def cylinder(bm, z0, z1, radius, material, center=(0, 0), top_radius=None):
        result = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=12,
            radius1=radius, radius2=radius if top_radius is None else top_radius, depth=z1-z0,
            matrix=Matrix.Translation((center[0], center[1], (z0+z1)*.5)))
        for vertex in result['verts']:
            for face in vertex.link_faces:
                face.material_index = material

    def arrow(bm, length, center=(0, 0), base=0):
        cylinder(bm, base, base+length-.09, .0055, 0, center)
        cylinder(bm, base+length-.12, base+length-.09, .008, 4, center)
        ring = [bm.verts.new((center[0]+x, center[1]+y, base+length-.09))
                for x, y in [(-.023, 0), (0, .007), (.023, 0), (0, -.007)]]
        tip = bm.verts.new((center[0], center[1], base+length))
        for i in range(4):
            bm.faces.new((ring[i], ring[(i+1)%4], tip)).material_index = 1
        for angle in [0, 2*math.pi/3, 4*math.pi/3]:
            d = Vector((math.cos(angle), math.sin(angle), 0))
            points = [(0.004, .025), (.030, .055), (.026, .15), (.004, .18)]
            vertices = [bm.verts.new(Vector((center[0], center[1], base+z))+d*r) for r,z in points]
            bm.faces.new(vertices).material_index = 2

    def quiver(bm, height, radius):
        # Open tapered leather wall, rolled lip, inner wall and two reinforcing bands.
        rows = []
        for z,r in [(0,radius*.78), (height-.025,radius), (height,radius*1.04),
                    (height,radius*.91), (.025,radius*.68)]:
            rows.append([bm.verts.new((math.cos(i*math.tau/20)*r, math.sin(i*math.tau/20)*r*.70,z)) for i in range(20)])
        for row in range(len(rows)-1):
            for i in range(20):
                face = bm.faces.new((rows[row][i],rows[row][(i+1)%20],rows[row+1][(i+1)%20],rows[row+1][i]))
                face.material_index = 4 if row in [1,2] else 3
        bm.faces.new(tuple(reversed(rows[-1]))).material_index = 3
        for z in [.065, height-.12]:
            for i in range(20):
                a,b = i*math.tau/20,(i+1)*math.tau/20
                vertices = [bm.verts.new((math.cos(t)*radius*1.025, math.sin(t)*radius*.72,h))
                            for t,h in [(a,z),(b,z),(b,z+.026),(a,z+.026)]]
                bm.faces.new(vertices).material_index = 4
        result = bmesh.ops.create_cube(bm, size=1, matrix=Matrix.Translation((.085,0,height-.065)) @ Matrix.Diagonal((.03,.08,.13,1)))
        for vertex in result['verts']:
            for face in vertex.link_faces:
                face.material_index = 3

    objects = []
    def finish(name, bm, parent=None):
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        mesh = bpy.data.meshes.new(name+'Mesh')
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(name,mesh)
        bpy.context.collection.objects.link(obj)
        obj.parent = parent
        for material in materials:
            mesh.materials.append(material)
        for face in mesh.polygons:
            face.use_smooth = face.material_index == 0
        objects.append(obj)
        return obj

    for name,length,container in [('Arrow', .78, False), ('Bolt', .39, False), ('QuiverArrow', .78, True), ('QuiverBolt', .39, True)]:
        bm = bmesh.new()
        if container:
            height = .47 if name == 'QuiverArrow' else .24
            quiver(bm,height,.085)
            container_obj = finish(name, bm)
            for index,center in enumerate([(-.035,-.015),(.027,-.017),(0,.023)]):
                bm = bmesh.new()
                arrow(bm,length,center,.018+index*.022)
                for vertex in bm.verts:
                    vertex.co.z = length + .036 + index*.044 - vertex.co.z
                finish(name + 'Contents' + str(index), bm, container_obj)
        else:
            arrow(bm,length)
            # Blender -Y becomes glTF forward +Z.
            bmesh.ops.transform(bm, matrix=Matrix.Rotation(math.pi/2,4,'X'), verts=list(bm.verts))
            finish(name, bm)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    destination.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(destination),export_format='GLB',use_selection=True,
                              export_animations=False,export_skins=False,export_morph=False)
    return objects
