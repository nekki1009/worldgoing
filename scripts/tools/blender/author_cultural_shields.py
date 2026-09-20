"""Measured held shields on the original forearm; no formal publication."""
import argparse
import hashlib
import json
import math
import struct
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.geometry import barycentric_transform
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[3]
BASE = ROOT / 'output/equipment_matrix_20260918/baseline'
WORK = ROOT / 'assets/characters/human/q35/equipment_matrix'
QA = ROOT / 'reports/output/equipment_matrix_20260918/shields'
BONE = 'J_Bip_L_LowerArm'
STYLES = ('Chinese', 'Japanese', 'Western')
MATERIALS = ('Wood', 'Stone', 'Iron', 'Steel')
PREFIXES = tuple(f'Shield_{s}_{m}_01' for s in STYLES for m in MATERIALS
                 if (s, m) != ('Western', 'Iron'))
sys.path.insert(0, str(Path(__file__).parent))
from build_standard_anime_male_character_pack import create_bone_rigid_component


def rest(arm):
    arm.animation_data_clear()
    for bone in arm.pose.bones:
        bone.matrix_basis = Matrix.Identity(4)
    arm.data.pose_position = 'REST'
    bpy.context.view_layer.update()


def measure(arm, sex):
    basis = arm.matrix_world @ arm.data.bones[BONE].matrix_local
    inverse = basis.inverted()
    bones = {}
    for name in (BONE, 'J_Bip_L_Hand', 'J_Bip_L_Middle1', 'J_Bip_L_Index1'):
        bone = arm.data.bones.get(name)
        if bone:
            bones[name] = {'head': list(inverse @ arm.matrix_world @ bone.head_local),
                           'tail': list(inverse @ arm.matrix_world @ bone.tail_local)}
    objects = {}
    for obj in bpy.data.objects:
        if obj.type != 'MESH' or not obj.name.startswith('Shield_Heater_01'):
            continue
        points = [inverse @ obj.matrix_world @ v.co for v in obj.data.vertices]
        objects[obj.name] = {
            'min': [min(p[i] for p in points) for i in range(3)],
            'max': [max(p[i] for p in points) for i in range(3)],
            'groups': [g.name for g in obj.vertex_groups],
            'vertices': len(points),
        }
    bodies = [bpy.data.objects['Body_Standard_' + sex.title()]]
    hand_points = []
    arm_points = []
    for obj in bodies:
        group_names = {g.index: g.name for g in obj.vertex_groups}
        for v in obj.data.vertices:
            groups = {group_names[g.group] for g in v.groups if g.weight > .5}
            if 'J_Bip_L_Hand' in groups:
                hand_points.append(inverse @ obj.matrix_world @ v.co)
            if BONE in groups:
                arm_points.append(inverse @ obj.matrix_world @ v.co)
    result = {'sex': sex, 'bone': BONE, 'basis': [list(row) for row in basis],
              'bones': bones, 'objects': objects, 'body_names': [o.name for o in bodies],
              'hand_points': [list(p) for p in hand_points],
              'arm_points': [list(p) for p in arm_points]}
    QA.mkdir(parents=True, exist_ok=True)
    (QA / f'{sex}_measurement.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print('SHIELD_MEASURE', sex, json.dumps({k: v for k, v in result.items()
          if k not in ('hand_points', 'arm_points')}), flush=True)
    return result


def hull(points):
    points = sorted(set((round(p[0], 6), round(p[1], 6)) for p in points))
    def cross(o, a, b):
        return (a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0])
    lower, upper = [], []
    for p in points:
        while len(lower) > 1 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(points):
        while len(upper) > 1 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def clip(poly, axis, limit, greater):
    result = []
    for a, b in zip(poly, poly[1:] + poly[:1]):
        ina = (a[axis] >= limit) if greater else (a[axis] <= limit)
        inb = (b[axis] >= limit) if greater else (b[axis] <= limit)
        if ina:
            result.append(a)
        if ina != inb:
            t = (limit-a[axis])/(b[axis]-a[axis])
            result.append(tuple(a[i]+t*(b[i]-a[i]) for i in range(2)))
    return result


class ShieldFit:
    def __init__(self, arm, measurement):
        self.arm, self.measurement = arm, measurement
        self.basis = Matrix(measurement['basis'])
        self.inverse = self.basis.inverted()
        native = measurement['objects']['Shield_Heater_01_Field']
        self.height = native['max'][0]-native['min'][0]
        self.width = native['max'][1]-native['min'][1]
        self.cy = (native['min'][1]+native['max'][1])/2
        self.front = native['max'][2]
        obj = bpy.data.objects['Shield_Heater_01_Field']
        self.heater = hull([self.inverse @ obj.matrix_world @ v.co for v in obj.data.vertices])
        bones = measurement['bones']
        wrist = Vector(bones['J_Bip_L_Hand']['head'])
        fingers = Vector(bones['J_Bip_L_Middle1']['head'])
        self.grip = (wrist+fingers)/2
        # The old held grip fixes the signed side of the palm, not a copied Y position.
        native_grip = measurement['objects']['Shield_Heater_01_Handle']
        self.grip.z = (native_grip['min'][2]+native_grip['max'][2])/2
        native_strap = measurement['objects']['Shield_Heater_01_Strap']
        self.strap_y = (native_strap['min'][1]+native_strap['max'][1])/2
        nearby = [Vector(p) for p in measurement['arm_points'] if abs(p[1]-self.strap_y) < .025]
        assert nearby, 'Native forearm skin sample missing'
        self.arm_rx = max(abs(p.x) for p in nearby)+.009
        self.arm_rz = max(abs(p.z) for p in nearby)+.009

    def outline(self, style):
        if style == 'Western':
            return self.heater
        if style == 'Chinese':
            r = self.width*.62
            return [(r*math.cos(i*math.tau/64), self.cy+r*math.sin(i*math.tau/64)) for i in range(64)]
        # Compact hand shield: deliberately not a historical standing tate.
        hx, hy, bevel = self.height*.43, self.width*.46, .014
        return hull([(sx*(hx-dx), self.cy+sy*(hy-dy)) for sx in (-1, 1)
                     for sy in (-1, 1) for dx, dy in ((bevel, 0), (0, bevel))])

    def depth(self, style, x, y):
        if style == 'Chinese':
            r = self.width*.62
            return self.front-.020+.037*max(0, 1-(x*x+(y-self.cy)**2)/(r*r))
        radius = self.width if style == 'Western' else self.width*1.9
        return self.front+math.sqrt(max(.001, radius*radius-(y-self.cy)**2))-radius


def material(kind, role='Main'):
    name = f'CulturalShields_{kind}_{role}'
    mat = bpy.data.materials.get(name)
    if mat:
        return mat
    colors = {'Wood': (.30, .135, .048), 'Stone': (.32, .345, .31),
              'Iron': (.13, .15, .17), 'Steel': (.54, .60, .66),
              'Leather': (.115, .050, .024), 'Cord': (.43, .31, .16)}
    metal = .92 if kind in ('Iron', 'Steel') else 0
    rough = {'Wood': .85, 'Stone': .96, 'Iron': .76, 'Steel': .30, 'Leather': .82, 'Cord': .95}[kind]
    tint = 1.25 if role == 'Edge' else .78 if role == 'Dark' else 1
    color = tuple(c*tint for c in colors[kind])
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    bs = mat.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*color, 1)
    bs.inputs['Metallic'].default_value = metal
    bs.inputs['Roughness'].default_value = rough
    # Baked native material detail exports as a real image, without procedural-node loss.
    size = 256
    y, x = np.mgrid[:size, :size]/size
    noise = np.random.default_rng(918).normal(0, 1, (size, size))
    if kind == 'Wood':
        grain = np.sin(y*230 + np.sin(x*15+y*9)*2 + np.sin(x*32)*.5)
        detail = 1+.17*grain+.065*np.sin(y*70+x*5)+.028*noise
    elif kind == 'Stone':
        detail = 1+.10*noise+.08*np.sin(x*39+y*17)*np.cos(y*41-x*11)
    elif kind == 'Iron':
        distance = np.full((size, size), 10.0)
        for px, py in np.random.default_rng(319).random((150, 2)):
            distance = np.minimum(distance, (x-px)**2+(y-py)**2)
        detail = 1+.055*noise-.22*np.exp(-distance/.0005)
    elif kind == 'Steel':
        detail = 1+.018*noise+.025*np.sin(y*630)
    else:
        detail = 1+.06*noise+.04*np.sin(x*190)*np.sin(y*170)
    rgba = np.ones((size, size, 4), dtype=np.float32)
    # Blender image pixels are linear; save/export handles their color conversion.
    rgba[:, :, :3] = np.clip(np.array(color)[None, None, :]*detail[:, :, None], 0, 1)
    img = bpy.data.images.new(name+'_Surface', width=size, height=size)
    img.pixels.foreach_set(rgba.ravel())
    img.pack()
    texture = mat.node_tree.nodes.new('ShaderNodeTexImage')
    texture.image = img
    mat.node_tree.links.new(texture.outputs['Color'], bs.inputs['Base Color'])
    return mat


def mesh_part(name, vertices, faces, mat, fit, smooth=False, bevel=0):
    mesh = bpy.data.meshes.new(name+'_Draft')
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bpy.data.meshes.remove(mesh)
    bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=.000001)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    if bevel:
        # Bevel physical plate boundaries, not the coplanar tessellation triangles.
        edges = [e for e in bm.edges if e.is_manifold and e.calc_face_angle() > .65]
        bmesh.ops.bevel(bm, geom=edges, offset=bevel, segments=2, affect='EDGES')
        bmesh.ops.remove_doubles(bm, verts=list(bm.verts), dist=.000001)
        bmesh.ops.dissolve_degenerate(bm, edges=list(bm.edges), dist=.000001)
    bm.normal_update()
    for edge in bm.edges:
        if edge.is_manifold and edge.calc_face_angle() > .65:
            edge.smooth = False
    uv = bm.loops.layers.uv.new('UVMap')
    for face in bm.faces:
        for loop in face.loops:
            loop[uv].uv = (loop.vert.co.x/fit.height+.5, (loop.vert.co.y-fit.cy)/fit.width+.5)
    for vertex in bm.verts:
        vertex.co = fit.basis @ vertex.co
    prefix = next(p for p in PREFIXES if name.startswith(p+'_'))
    obj = create_bone_rigid_component(name, bm, mat, BONE, 'shield', prefix.lower(), fit.arm)
    for poly in obj.data.polygons:
        poly.use_smooth = smooth
    obj['shield_surface_kind'] = prefix.split('_')[2].lower()
    obj['shield_front_axis'] = '+Z in J_Bip_L_LowerArm rest space'
    return obj


def tube(name, path, radius, mat, fit, sides=8, flat=1):
    vertices, faces = [], []
    closed = (Vector(path[0])-Vector(path[-1])).length < .000001
    if closed:
        path = path[:-1]
    previous_tangent = previous_normal = None
    for i, point in enumerate(path):
        point = Vector(point)
        before = (i-1)%len(path) if closed else max(i-1, 0)
        after = (i+1)%len(path) if closed else min(i+1, len(path)-1)
        tangent = (Vector(path[after])-Vector(path[before])).normalized()
        if previous_tangent is None:
            ref = Vector((0, 0, 1)) if abs(tangent.z) < .9 else Vector((1, 0, 0))
            normal = tangent.cross(ref).normalized()
        else:
            normal = previous_tangent.rotation_difference(tangent) @ previous_normal
        previous_tangent, previous_normal = tangent, normal
        bitangent = tangent.cross(normal).normalized()
        for j in range(sides):
            angle = math.tau*j/sides
            vertices.append(point+radius*(normal*math.cos(angle)+bitangent*math.sin(angle)*flat))
    for i in range(len(path) if closed else len(path)-1):
        for j in range(sides):
            a, b = i*sides+j, i*sides+(j+1)%sides
            next_ring = ((i+1)%len(path))*sides
            faces.append((a, b, next_ring+(j+1)%sides, next_ring+j))
    if not closed:
        faces += [tuple(reversed(range(sides))), tuple((len(path)-1)*sides+j for j in range(sides))]
    return mesh_part(name, vertices, faces, mat, fit, smooth=True)


def panel(name, polygon, depth, thickness, mat, fit, hammered=False, bevel=0):
    if len(polygon) < 3:
        return None
    polygon = hull(polygon)
    center = sum((Vector(p) for p in polygon), Vector((0, 0)))/len(polygon)
    inset = []
    for i, p in enumerate(polygon):
        p = Vector(p)
        before = (p-Vector(polygon[i-1])).normalized()
        after = (Vector(polygon[(i+1)%len(polygon)])-p).normalized()
        n0, n1 = Vector((-before.y, before.x)), Vector((-after.y, after.x))
        bisector = (n0+n1).normalized()
        inset.append(p+bisector*min(bevel/max(.1, bisector.dot(n0)), (center-p).length*.15))
    outer, inner = [], []
    for i, p in enumerate(polygon):
        count = max(1, math.ceil(math.dist(p, polygon[(i+1)%len(polygon)])/.024))
        for j in range(count):
            outer.append(Vector(p).lerp(Vector(polygon[(i+1)%len(polygon)]), j/count))
            inner.append(inset[i].lerp(inset[(i+1)%len(polygon)], j/count))
    vertices, faces = [], []
    n = len(outer)
    def ring(points, offset):
        indices = []
        for x, y in points:
            z = depth(x, y)+offset
            if hammered:
                z += .0007*(math.sin(x*183+y*139)+math.sin(y*197-x*83)+math.sin(x*77+y*231))/3
            indices.append(len(vertices))
            vertices.append((x, y, z))
        return indices
    def bridge(a, b):
        faces.extend((a[j], a[(j+1)%n], b[(j+1)%n], b[j]) for j in range(n))
    # Explicit rings avoid beveling tessellation edges and keep every slab closed.
    centers = ring([center], 0)+ring([center], -thickness)
    front = back = None
    rings = 3 if max((p-center).length for p in inner) > .025 else 1
    for k in range(1, rings+1):
        xy = [center.lerp(p, k/rings) for p in inner]
        f, b = ring(xy, 0), ring(xy, -thickness)
        if front is None:
            faces.extend((centers[0], f[j], f[(j+1)%n]) for j in range(n))
            faces.extend((centers[1], b[(j+1)%n], b[j]) for j in range(n))
        else:
            bridge(front, f)
            bridge(b, back)
        front, back = f, b
    if bevel:
        outer_front, outer_back = ring(outer, -bevel), ring(outer, -thickness+bevel)
        bridge(front, outer_front)
        bridge(outer_front, outer_back)
        bridge(outer_back, back)
    else:
        bridge(front, back)
    return mesh_part(name, vertices, faces, mat, fit, smooth=not hammered)


def rectangle(polygon, xmin, xmax, ymin, ymax):
    for axis, value, greater in ((0, xmin, True), (0, xmax, False), (1, ymin, True), (1, ymax, False)):
        polygon = clip(polygon, axis, value, greater)
        if len(polygon) < 3:
            return []
    return polygon


def outline_path(polygon, depth, scale=1, cy=0):
    points = []
    for a, b in zip(polygon, polygon[1:]+polygon[:1]):
        n = max(1, math.ceil(math.dist(a, b)/.013))
        for j in range(n):
            x = (a[0]+(b[0]-a[0])*j/n)*scale
            y = cy+(a[1]+(b[1]-a[1])*j/n-cy)*scale
            points.append((x, y, depth(x, y)))
    return points+[points[0]]


def fittings(prefix, style, kind, fit, depth, thickness):
    leather, cord = material('Leather'), material('Cord')
    grip = fit.grip
    half = min(.045, fit.width*.105)
    parts = [tube(prefix+'_Handle', [grip+Vector((x, 0, 0)) for x in (-half, half)],
                  .0105, leather, fit, sides=12)]
    for side in (-1, 1):
        x = grip.x+side*half
        z = depth(x, grip.y)-thickness
        parts.append(tube(prefix+'_HandleMount_'+str(side), [(x, grip.y, grip.z), (x, grip.y, z)],
                          .008, material('Wood') if kind in ('Wood', 'Stone') else material(kind), fit))
    # A thick open tunnel across the arm; both endpoints are attached to the back plate.
    rx, rz = fit.arm_rx, fit.arm_rz
    path = []
    for i in range(33):
        a = math.pi*i/32
        path.append((rx*math.cos(a), fit.strap_y, -rz*math.sin(a)))
    path = [(rx, fit.strap_y, depth(rx, fit.strap_y)-thickness), *path,
            (-rx, fit.strap_y, depth(-rx, fit.strap_y)-thickness)]
    vertices, faces = [], []
    for x, y, z in path:
        vertices.extend([(x, y-.016, z), (x, y+.016, z), (x-.004, y-.016, z-.003), (x-.004, y+.016, z-.003)])
    for i in range(len(path)-1):
        a = i*4
        for j, k in ((0, 1), (1, 3), (3, 2), (2, 0)):
            faces.append((a+j, a+k, a+4+k, a+4+j))
    faces += [(0, 2, 3, 1), tuple((len(path)-1)*4+i for i in (0, 1, 3, 2))]
    parts.append(mesh_part(prefix+'_ArmStrap', vertices, faces, leather, fit, smooth=True))
    for i in range(9):
        x = grip.x-half+.009+i*(2*half-.018)/8
        circle = [(x, grip.y+.011*math.cos(a), grip.z+.011*math.sin(a)) for a in np.linspace(0, math.tau, 17)]
        parts.append(tube(prefix+'_GripWrap_'+str(i), circle, .0015, cord if kind == 'Stone' else leather, fit, sides=5))
    return parts


def build(fit):
    parts = []
    for style in STYLES:
        outline = fit.outline(style)
        for kind in MATERIALS:
            if (style, kind) == ('Western', 'Iron'):
                continue
            prefix = f'Shield_{style}_{kind}_01'
            # A thick stone plate grows outward so its curved rim stays clear of the hand.
            depth = lambda x, y, style=style, kind=kind: fit.depth(style, x, y)+(.015 if kind == 'Stone' else 0)
            thickness = {'Wood': .018, 'Stone': .036, 'Iron': .012, 'Steel': .009}[kind]
            mat = material(kind)
            edge = material(kind, 'Edge')
            if kind in ('Wood', 'Stone'):
                # Each slab/plank is a separately editable closed, beveled solid.
                rows = 1 if kind == 'Wood' else 4
                cols = 7 if kind == 'Wood' else 3
                xmin, xmax = min(p[0] for p in outline), max(p[0] for p in outline)
                ymin, ymax = min(p[1] for p in outline), max(p[1] for p in outline)
                for row in range(rows):
                    for col in range(cols):
                        gap = .0015 if kind == 'Wood' else .003
                        polygon = rectangle(outline, xmin+(xmax-xmin)*row/rows+gap,
                                            xmin+(xmax-xmin)*(row+1)/rows-gap,
                                            ymin+(ymax-ymin)*col/cols+gap,
                                            ymin+(ymax-ymin)*(col+1)/cols-gap)
                        obj = panel(prefix+f'_{"Plank" if kind == "Wood" else "StonePlate"}_{row}_{col}',
                                    polygon, depth, thickness, material(kind, 'Dark') if (row+col)%3 == 0 else mat,
                                    fit, bevel=.0012 if kind == 'Wood' else .0025)
                        if obj:
                            parts.append(obj)
                # Structural back battens connect the separate panels.
                for i, x in enumerate((xmin*.55, xmax*.55)):
                    polygon = rectangle(outline, x-.018, x+.018, ymin+.023, ymax-.023)
                    parts.append(panel(prefix+f'_BackBatten_{i}', polygon,
                                       lambda x, y: depth(x, y)-thickness-.002, .014,
                                       material('Wood', 'Dark'), fit, bevel=.001))
            else:
                parts.append(panel(prefix+'_Field', outline, depth, thickness, mat, fit, hammered=kind == 'Iron'))
            rim_mat = material('Leather') if kind == 'Stone' else edge
            parts.append(tube(prefix+'_Rim', outline_path(outline, lambda x, y: depth(x, y)-thickness*.25),
                              .008 if kind != 'Steel' else .0055, rim_mat, fit, sides=10))
            if kind == 'Steel':
                parts.append(tube(prefix+'_FineBead', outline_path(outline, lambda x, y: depth(x, y)+.004,
                                                                 .95, fit.cy), .002, edge, fit))
            if kind == 'Stone':
                # Nonmetal cord crossings physically wrap front, edges and back.
                for i, y in enumerate((fit.cy-fit.width*.20, fit.cy+fit.width*.20)):
                    band = rectangle(outline, -1, 1, y-.001, y+.001)
                    if len(band) < 3:
                        continue
                    lo, hi = min(p[0] for p in band), max(p[0] for p in band)
                    path = [(x, y+.002*math.sin(t*math.tau*12), depth(x, y)+.004)
                            for t, x in zip(np.linspace(0, 1, 45), np.linspace(lo, hi, 45))]
                    path += [(x, y, depth(x, y)-thickness-.019) for x in np.linspace(hi, lo, 45)]
                    path.append(path[0])
                    parts.append(tube(prefix+f'_CordBinding_{i}', path, .004, material('Cord'), fit))
            if style == 'Chinese':
                radius = fit.width*.15
                dome = [(radius*math.cos(a), fit.cy+radius*math.sin(a)) for a in np.linspace(0, math.tau, 41)[:-1]]
                bossdepth = lambda x, y: depth(0, fit.cy)+.043*math.sqrt(max(0, 1-(x*x+(y-fit.cy)**2)/(radius*radius)))
                parts.append(panel(prefix+'_ConvexBoss', dome, bossdepth, .006 if kind != 'Stone' else .014,
                                   edge, fit, hammered=kind == 'Iron'))
                parts.append(tube(prefix+'_BossCollar', outline_path(dome, lambda x, y: depth(0, fit.cy)),
                                  .0045, material('Cord') if kind == 'Stone' else edge, fit))
            elif style == 'Japanese':
                for i, x in enumerate((-.14, .14)):
                    polygon = rectangle(outline, x-.014, x+.014, fit.cy-fit.width*.42, fit.cy+fit.width*.42)
                    parts.append(panel(prefix+f'_FaceCrossbrace_{i}', polygon, lambda x, y: depth(x, y)+.007,
                                       .012, material('Wood', 'Dark') if kind == 'Wood' else rim_mat, fit, bevel=.001))
            else:
                for i, box in enumerate(((-.12, .17, fit.cy-.017, fit.cy+.017),
                                         (.014, .048, fit.cy-.115, fit.cy+.115))):
                    polygon = rectangle(outline, *box)
                    parts.append(panel(prefix+f'_HeraldicCross_{i}', polygon, lambda x, y: depth(x, y)+.006,
                                       .006, material(kind, 'Dark') if kind != 'Steel' else edge, fit))
            if kind in ('Wood', 'Iron', 'Steel'):
                # Pegs on wood; rivets on metal. All are real raised mesh.
                for i in range(12 if style == 'Chinese' else 8):
                    p = outline[int(i*len(outline)/(12 if style == 'Chinese' else 8))]
                    x, y = p[0]*.9, fit.cy+(p[1]-fit.cy)*.9
                    radius = .0042 if kind == 'Wood' else .0035
                    circle = [(x+radius*math.cos(a), y+radius*math.sin(a)) for a in np.linspace(0, math.tau, 9)[:-1]]
                    parts.append(panel(prefix+f'_Rivet_{i}', circle, lambda x, y: depth(x, y)+.004, .006, edge, fit))
            parts.extend(fittings(prefix, style, kind, fit, depth, thickness))
    assert all(parts)
    return parts


def authored_parts():
    return sorted([o for o in bpy.data.objects if o.type == 'MESH' and any(o.name.startswith(p+'_') for p in PREFIXES)],
                  key=lambda o: o.name)


def add_holstered(sex, arm, parts):
    """Map held geometry through native paired heater surfaces and native skin weights."""
    assert not any('_Holstered_' in o.name for o in parts), 'Holsters already authored; use export to preserve edits'
    held_signatures = {o.name: mesh_signature(o) for o in parts}
    native_held = bpy.data.objects['Shield_Heater_01_Field']
    if 'Shield_Heater_01_Holstered_Field' not in bpy.data.objects:
        originals = set(bpy.data.objects)
        original_actions = set(bpy.data.actions)
        with bpy.data.libraries.load(str(BASE / f'standard_anime_{sex}_character_pack.blend'), link=False) as (available, loaded):
            loaded.objects = [n for n in available.objects if n.startswith('Shield_Heater_01_Holstered_')]
        for obj in loaded.objects:
            bpy.context.collection.objects.link(obj)
            world = obj.matrix_world.copy()
            obj.parent = arm
            obj.matrix_parent_inverse = arm.matrix_world.inverted()
            obj.matrix_world = world
            for mod in obj.modifiers:
                if mod.type == 'ARMATURE':
                    mod.object = arm
        for obj in set(bpy.data.objects)-originals-set(loaded.objects):
            data = obj.data if obj.type == 'ARMATURE' else None
            bpy.data.objects.remove(obj, do_unlink=True)
            if data is not None and data.users == 0:
                bpy.data.armatures.remove(data)
        for action in set(bpy.data.actions)-original_actions:
            assert action.users == int(action.use_fake_user)
            bpy.data.actions.remove(action)
    native_back = bpy.data.objects['Shield_Heater_01_Holstered_Field']
    inverse = (arm.matrix_world @ arm.data.bones[BONE].matrix_local).inverted()
    h = np.array([inverse @ native_held.matrix_world @ v.co for v in native_held.data.vertices])
    b = np.array([native_back.matrix_world @ v.co for v in native_back.data.vertices])
    assert h.shape == b.shape
    # First skin of the native extruded grid; correspondence is independently verified.
    count = len(h)//2
    planar = np.column_stack((h[:count, 0], h[:count, 1], np.ones(count)))
    affine = np.linalg.lstsq(planar, b[:count, (0, 2)], rcond=None)[0]
    residual = float(np.max(np.abs(planar @ affine-b[:count, (0, 2)])))
    assert residual < .00002, ('Native shield correspondence changed', residual)
    native_held.data.calc_loop_triangles()
    triangles = [tuple(t.vertices) for t in native_held.data.loop_triangles if all(i < count for i in t.vertices)
                 and abs(np.cross(h[t.vertices[1], :2]-h[t.vertices[0], :2], h[t.vertices[2], :2]-h[t.vertices[0], :2])) > 1e-10]
    points = [Vector((p[0], p[1], 0)) for p in h[:count]]
    tree = BVHTree.FromPolygons(points, triangles, all_triangles=True)
    native_groups = {g.index: g.name for g in native_back.vertex_groups}
    weights = [{native_groups[g.group]: g.weight for g in v.groups} for v in native_back.data.vertices]
    created = []
    for obj in parts:
        prefix = next(p for p in PREFIXES if obj.name.startswith(p+'_'))
        clone = obj.copy()
        clone.data = obj.data.copy()
        clone.name = prefix+'_Holstered_'+obj.name[len(prefix)+1:]
        clone.data.name = clone.name+'Mesh'
        bpy.context.collection.objects.link(clone)
        clone.vertex_groups.clear()
        for name in native_groups.values():
            clone.vertex_groups.new(name=name)
        output_inverse = clone.matrix_world.inverted()
        for vertex in clone.data.vertices:
            local = inverse @ obj.matrix_world @ obj.data.vertices[vertex.index].co
            query = Vector((local.x, local.y, 0))
            nearest, _, triangle_index, _ = tree.find_nearest(query)
            assert nearest is not None
            ids = triangles[triangle_index]
            a, c, d = [points[i] for i in ids]
            bary = barycentric_transform(nearest, a, c, d, Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))
            native_point = sum((Vector(b[i])*w for i, w in zip(ids, bary)), Vector())
            reference_z = sum(h[i, 2]*w for i, w in zip(ids, bary))
            # Preserve each new outline beyond the original heater triangle boundary.
            xz = np.array((local.x, local.y, 1.0)) @ affine
            native_point.x, native_point.z = xz
            native_point.y += local.z-reference_z
            vertex.co = output_inverse @ native_point
            combined = {}
            for index, factor in zip(ids, bary):
                for group, weight in weights[index].items():
                    combined[group] = combined.get(group, 0)+max(0, factor)*weight
            total = sum(combined.values())
            assert total > 0
            for group, weight in combined.items():
                if weight > 1e-7:
                    clone.vertex_groups[group].add([vertex.index], weight/total, 'REPLACE')
        clone['shield_carry_state'] = 'holstered'
        clone['shield_front_axis'] = '+Y through exact native back-shield surface'
        clone.data.update()
        created.append(clone)
    assert held_signatures == {o.name: mesh_signature(o) for o in parts}
    evidence = {'sex': sex, 'native_surface': native_back.name, 'native_vertex_pairs': count,
                'native_xz_correspondence_max_error_m': residual, 'native_groups': list(native_groups.values()),
                'held_meshes_preserved': len(parts), 'holstered_meshes': len(created),
                'affine_xz': affine.tolist(), 'mapping': 'native triangle barycentric surface and weights; signed thickness to +Y'}
    (QA / f'{sex}_holster_fit.json').write_text(json.dumps(evidence, indent=2)+'\n', encoding='utf-8')
    print('CULTURAL_SHIELDS_HOLSTERED', json.dumps(evidence), flush=True)
    return parts+created


def component_signature(obj):
    """Geometry, weights, UVs, material slots and attachment, excluding preview visibility."""
    record = [mesh_signature(obj), [list(row) for row in obj.matrix_world],
              [g.name for g in obj.vertex_groups],
              [[(g.group, g.weight) for g in v.groups] for v in obj.data.vertices],
              [[list(v.uv) for v in layer.data] for layer in obj.data.uv_layers],
              [m.name for m in obj.data.materials], obj.parent.name if obj.parent else None,
              [(m.type, m.object.name if m.type == 'ARMATURE' and m.object else None) for m in obj.modifiers]]
    return hashlib.sha256(json.dumps(record, separators=(',', ':')).encode()).hexdigest()


def rigid_backcarry(sex, arm, parts, repair=False):
    """Retain native X/Z anchors; replace the singular tip projection and cloth skinning."""
    inverse = (arm.matrix_world @ arm.data.bones[BONE].matrix_local).inverted()
    held = bpy.data.objects['Shield_Heater_01_Field']
    native = bpy.data.objects['Shield_Heater_01_Holstered_Field']
    count = len(held.data.vertices)//2
    h = np.array([inverse @ held.matrix_world @ v.co for v in held.data.vertices])[:count]
    b = np.array([native.matrix_world @ v.co for v in native.data.vertices])[:count]
    planar = np.column_stack((h[:, 0], h[:, 1], np.ones(count)))
    xz = np.linalg.lstsq(planar, b[:, (0, 2)], rcond=None)[0]
    depth = np.linalg.lstsq(planar, b[:, 1]-h[:, 2], rcond=None)[0]
    buckets = {}
    for p, offset in zip(h, b[:, 1]-h[:, 2]):
        buckets.setdefault((round(float(p[0]), 5), round(float(p[1]), 5)), []).append(float(offset))
    collapsed = [values for values in buckets.values() if len(values) > 1]
    grip = bpy.data.objects['Shield_Western_Steel_01_Holstered_Handle']
    source_grip = bpy.data.objects['Shield_Western_Steel_01_Handle']
    anchor = sum((grip.matrix_world @ v.co for v in grip.data.vertices), Vector())/len(grip.data.vertices)
    local_anchor = sum((inverse @ source_grip.matrix_world @ v.co for v in source_grip.data.vertices), Vector())/len(source_grip.data.vertices)
    # A single continuous native-surface tilt, translated to the measured grip anchor.
    # Unlike the collapsing native tip, this is a single-valued affine depth mapping.
    depth[2] = anchor.y-local_anchor.z-depth[0]*local_anchor.x-depth[1]*local_anchor.y
    mapping = Matrix(((xz[0, 0], xz[1, 0], 0, xz[2, 0]),
                      (depth[0], depth[1], 1, depth[2]),
                      (xz[0, 1], xz[1, 1], 0, xz[2, 1]), (0, 0, 0, 1)))
    weights = {g.name: sum(next((w.weight for w in v.groups if w.group == g.index), 0)
                          for v in grip.data.vertices)/len(grip.data.vertices) for g in grip.vertex_groups}
    weights = {name: value for name, value in weights.items() if value > 1e-7}
    total = sum(weights.values())
    weights = {name: value/total for name, value in weights.items()}
    protected = {o.name: component_signature(o) for o in bpy.data.objects if o.type == 'MESH'
                 and not (o in parts and '_Holstered_' in o.name)}
    bones = {bone.name: [list(r) for r in bone.matrix_local] for bone in arm.data.bones}
    report = {'sex': sex, 'repair': repair, 'native_projected_duplicate_groups': len(collapsed),
              'native_same_xy_depth_offset_range_m': max((max(v)-min(v) for v in collapsed), default=0),
              'native_grip_anchor': list(anchor), 'native_grip_weights': weights,
              'continuous_rest_mapping': [list(row) for row in mapping], 'options': []}
    for prefix in PREFIXES:
        maximum_offset = 0.0
        maximum_weight_jump = 0.0
        count_vertices = 0
        for back in [o for o in parts if o.name.startswith(prefix+'_Holstered_')]:
            source = bpy.data.objects[prefix+'_'+back.name[len(prefix+'_Holstered_'):]]
            assert len(source.data.vertices) == len(back.data.vertices)
            old_weights = [{back.vertex_groups[w.group].name: w.weight for w in v.groups} for v in back.data.vertices]
            for edge in back.data.edges:
                a, c = (old_weights[i] for i in edge.vertices)
                maximum_weight_jump = max(maximum_weight_jump, sum(abs(a.get(n, 0)-c.get(n, 0)) for n in set(a)|set(c)))
            if repair:
                for group in back.vertex_groups:
                    group.remove(list(range(len(back.data.vertices))))
            output_inverse = back.matrix_world.inverted()
            for vertex in back.data.vertices:
                target = mapping @ inverse @ source.matrix_world @ source.data.vertices[vertex.index].co
                maximum_offset = max(maximum_offset, (back.matrix_world @ vertex.co-target).length)
                if repair:
                    vertex.co = output_inverse @ target
                count_vertices += 1
            if repair:
                for name, value in weights.items():
                    back.vertex_groups[name].add(list(range(len(back.data.vertices))), value, 'REPLACE')
                back['shield_front_axis'] = '+Y continuous native back-plane tilt; native grip anchored'
                back['shield_carry_rigid_weights'] = json.dumps(weights, sort_keys=True)
                back.data.update()
        report['options'].append({'id': prefix.lower(), 'vertices': count_vertices,
                                  'old_rest_nonaffine_depth_deviation_m': maximum_offset,
                                  'old_max_edge_weight_l1_jump': maximum_weight_jump})
    assert protected == {name: component_signature(bpy.data.objects[name]) for name in protected}
    assert bones == {bone.name: [list(r) for r in bone.matrix_local] for bone in arm.data.bones}
    report['protected_signatures'] = protected
    report['held_original_body_material_uv_weights_and_bones_preserved'] = True
    if repair:
        after_anchor = sum((grip.matrix_world @ v.co for v in grip.data.vertices), Vector())/len(grip.data.vertices)
        report['grip_anchor_shift_m'] = (after_anchor-anchor).length
        assert report['grip_anchor_shift_m'] < .000002
        arm['cultural_shields_backcarry_rigid'] = json.dumps({'mapping': [list(row) for row in mapping],
                                                           'weights': weights, 'anchor': list(anchor)})
    suffix = 'rigid_carry_fix' if repair else 'carry_probe'
    (QA / f'{sex}_{suffix}.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
    print('SHIELDS_CARRY_DIAGNOSIS', sex, report['native_same_xy_depth_offset_range_m'],
          'anchor weights', weights, 'options', report['options'], flush=True)


def save_source(sex, arm, parts):
    # Keep only reference body/native shield, the original rig and the new editable parts.
    keep = set(parts+[arm])
    keep.update(o for o in bpy.data.objects if o.name == 'Body_Standard_'+sex.title()
                or o.name.startswith('Shield_Heater_01'))
    for obj in list(bpy.data.objects):
        if obj not in keep:
            bpy.data.objects.remove(obj, do_unlink=True)
    for obj in keep:
        obj.hide_render = obj not in parts or not obj.name.startswith(PREFIXES[0]+'_') or '_Holstered_' in obj.name
        obj.hide_set(obj.hide_render and obj != arm)
    for collection in (bpy.data.actions, bpy.data.materials, bpy.data.meshes, bpy.data.images, bpy.data.node_groups):
        for data in collection:
            data.use_fake_user = False
    bpy.ops.outliner.orphans_purge(do_recursive=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(WORK / f'cultural_shields_{sex}.blend'))


def export(sex, arm, parts):
    rest(arm)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [arm]+parts:
        obj.hide_viewport = False
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=str(WORK / f'subset_shields_{sex}.glb'),
                             export_format='GLB', use_selection=True, export_animations=False,
                             export_skins=True, export_morph=False, export_apply=False,
                             export_extras=True, export_yup=True)
    manifest = {'sex': sex, 'skeleton': arm.name, 'bone': BONE,
                'carry_states': ['held', 'holstered'],
                'holstered_bones': ['J_Bip_C_UpperChest', 'J_Bip_C_Chest', 'J_Bip_C_Spine', 'J_Bip_C_Hips'],
                'original_id_preserved': 'shield_heater_01', 'export_animations': False,
                'options': [{'id': p.lower(), 'prefix': p,
                             'meshes': [o.name for o in parts if o.name.startswith(p+'_')]} for p in PREFIXES]}
    (WORK / f'cultural_shields_{sex}.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    print('CULTURAL_SHIELDS_EXPORTED', sex, len(parts), flush=True)


def mesh_signature(obj):
    digest = hashlib.sha256()
    for v in obj.data.vertices:
        digest.update(struct.pack('<3f', *v.co))
    for p in obj.data.polygons:
        digest.update(struct.pack('<'+'I'*len(p.vertices), *p.vertices))
    return digest.hexdigest()


def test(sex, arm, parts):
    result = {'sex': sex, 'passed': False, 'checks': {}, 'options': []}
    try:
        assert len([o for o in bpy.data.objects if o.type == 'ARMATURE']) == 1
        assert len(PREFIXES) == 11
        fit = json.loads(arm['cultural_shields_fit'])
        basis = arm.matrix_world @ arm.data.bones[BONE].matrix_local
        inverse = basis.inverted()
        rigid = json.loads(arm['cultural_shields_backcarry_rigid'])
        carry_mapping = Matrix(rigid['mapping'])
        assert carry_mapping.to_3x3().determinant() > 0
        carry_error = 0.0
        for back in [o for o in parts if '_Holstered_' in o.name]:
            source = bpy.data.objects[back.name.replace('_Holstered_', '_', 1)]
            for vertex in back.data.vertices:
                expected = carry_mapping @ inverse @ source.matrix_world @ source.data.vertices[vertex.index].co
                carry_error = max(carry_error, (back.matrix_world @ vertex.co-expected).length)
                actual = {back.vertex_groups[g.group].name: g.weight for g in vertex.groups}
                assert all(abs(actual.get(n, 0)-rigid['weights'].get(n, 0)) < .000001 for n in set(actual)|set(rigid['weights']))
        assert carry_error < .000002, ('Backcarry rest fold', carry_error)
        correction = json.loads((QA / f'{sex}_rigid_carry_fix.json').read_text(encoding='utf-8'))
        assert correction['protected_signatures'] == {n: component_signature(bpy.data.objects[n]) for n in correction['protected_signatures']}
        result['checks']['all_holstered_continuous_rest_mapping_max_error_m'] = carry_error
        result['checks']['all_holstered_uniform_native_anchor_weights'] = rigid['weights']
        result['checks']['pre_fix_held_body_and_original_mesh_fingerprints_preserved'] = True
        for prefix in PREFIXES:
            items = [o for o in parts if o.name.startswith(prefix+'_')]
            held = [o for o in items if '_Holstered_' not in o.name]
            back = [o for o in items if '_Holstered_' in o.name]
            assert len(held) == len(back) and len(back) > 0, (prefix, 'missing carry state')
            assert {o.name[len(prefix)+1:] for o in held} == {o.name[len(prefix+'_Holstered_'):] for o in back}
            assert items and prefix != 'Shield_Western_Iron_01'
            grip = next(o for o in held if o.name == prefix+'_Handle')
            points = [inverse @ grip.matrix_world @ v.co for v in grip.data.vertices]
            center = sum(points, Vector())/len(points)
            assert (center-Vector(fit['grip'])).length < .0001, (prefix, 'grip alignment')
            assert any(o.name.endswith('_ArmStrap') for o in items)
            triangles = 0
            for obj in items:
                assert obj['worldgoing_visual_id'] == prefix.lower()
                assert obj['worldgoing_component_slot'] == 'shield'
                assert obj.parent == arm and obj.parent_type == 'OBJECT'
                assert len(obj.modifiers) == 1 and obj.modifiers[0].type == 'ARMATURE'
                assert obj.modifiers[0].object == arm
                if '_Holstered_' in obj.name:
                    assert {g.name for g in obj.vertex_groups} == {'J_Bip_C_UpperChest', 'J_Bip_C_Chest', 'J_Bip_C_Spine', 'J_Bip_C_Hips'}
                    assert all(abs(sum(g.weight for g in v.groups)-1) < .00001 for v in obj.data.vertices)
                    assert obj['shield_carry_state'] == 'holstered'
                else:
                    assert len(obj.vertex_groups) == 1 and obj.vertex_groups[0].name == BONE
                    assert all(len(v.groups) == 1 and abs(v.groups[0].weight-1) < .00001 for v in obj.data.vertices)
                assert obj.data.uv_layers and all(math.isfinite(c) for v in obj.data.vertices for c in v.co)
                bm = bmesh.new()
                bm.from_mesh(obj.data)
                bad_edges = sum(not e.is_manifold for e in bm.edges)
                tiny = sum(f.calc_area() < 1e-12 for f in bm.faces)
                bm.free()
                assert bad_edges == 0, (obj.name, 'nonmanifold', bad_edges)
                assert tiny == 0, (obj.name, 'zero-area', tiny)
                for mat in obj.data.materials:
                    bs = mat.node_tree.nodes.get('Principled BSDF')
                    assert bs and bs.inputs['Base Color'].is_linked
                    if '_Stone_' in prefix:
                        assert bs.inputs['Metallic'].default_value == 0, (obj.name, 'metallic stone')
                triangles += sum(len(p.vertices)-2 for p in obj.data.polygons)
            fronts = [o for o in held if any(k in o.name for k in ('_Field', '_Plank_', '_StonePlate_'))]
            assert fronts
            front_z = [float((inverse @ o.matrix_world @ v.co).z) for o in fronts for v in o.data.vertices]
            assert min(front_z) > center.z+.012, (prefix, 'front/back inversion', min(front_z), center.z)
            result['options'].append({'id': prefix.lower(), 'meshes': len(items), 'held_meshes': len(held),
                                      'holstered_meshes': len(back), 'triangles': triangles,
                                      'grip': list(center), 'min_front_z': min(front_z)})
        result['checks']['mesh_weights_uv_closed_geometry_materials_and_back_grip'] = True
        result['checks']['each_option_has_complete_editor_held_and_holstered_name_routes'] = True
        data = (WORK / f'subset_shields_{sex}.glb').read_bytes()
        assert data[:4] == b'glTF'
        length = struct.unpack_from('<I', data, 12)[0]
        doc = json.loads(data[20:20+length])
        assert not doc.get('animations')
        names = {n['name'] for n in doc['nodes'] if 'mesh' in n}
        assert names == {o.name for o in parts}, (len(names), len(parts), sorted(names-{o.name for o in parts}))
        assert not any(n.startswith('Shield_Heater') for n in names)
        for node in doc['nodes']:
            if 'mesh' in node:
                assert 'skin' in node
        result['checks']['glb_only_new_meshes_original_skin_no_animations'] = True
        # Exercise the real append loader in a fresh baseline, with original assets/actions fingerprinted.
        source_bones = {b.name: [list(r) for r in b.matrix_local] for b in arm.data.bones}
        bpy.ops.wm.open_mainfile(filepath=str(BASE / f'standard_anime_{sex}_character_pack.blend'))
        native_arm = bpy.data.objects['Armature']
        assert source_bones == {b.name: [list(r) for r in b.matrix_local] for b in native_arm.data.bones}
        native_shields = {o.name: mesh_signature(o) for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith('Shield_Heater_01')}
        actions = {a.name for a in bpy.data.actions}
        arms = {o.name for o in bpy.data.objects if o.type == 'ARMATURE'}
        from load_authored_cultural_shields import load_cultural_shields
        loaded = load_cultural_shields(native_arm, is_female=sex == 'female')
        assert len(loaded) == len(names)
        assert actions == {a.name for a in bpy.data.actions}
        assert arms == {o.name for o in bpy.data.objects if o.type == 'ARMATURE'}
        assert native_shields == {o.name: mesh_signature(o) for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith('Shield_Heater_01')}
        result['checks']['loader_preserves_existing_rig_actions_and_original_shield_meshes'] = True
        # Native clips prove attachment transforms, not all-combination collision clearance.
        rest(native_arm)
        native_arm.data.pose_position = 'POSE'
        native_arm.animation_data_create()
        animation_results = []
        rigid_results = []
        samples = [next(o for o in loaded if o.name == p+'_Handle') for p in PREFIXES]
        back_samples = [next(o for o in loaded if o.name == p+'_Holstered_Handle') for p in PREFIXES]
        action_by_name = {a.name.lower(): a for a in bpy.data.actions}
        for wanted in ('idle', 'walk', 'run', 'guard', 'attack_sword'):
            action = action_by_name.get(wanted) or next((a for a in bpy.data.actions if a.name.lower().endswith('_'+wanted)), None)
            assert action, ('Missing native action', wanted, list(action_by_name))
            native_arm.animation_data.action = action
            for t in (0, .5, 1):
                frame = action.frame_range[0]+t*(action.frame_range[1]-action.frame_range[0])
                bpy.context.scene.frame_set(int(frame), subframe=frame-int(frame))
                bpy.context.view_layer.update()
                deps = bpy.context.evaluated_depsgraph_get()
                transform = native_arm.matrix_world @ native_arm.pose.bones[BONE].matrix @ native_arm.data.bones[BONE].matrix_local.inverted() @ native_arm.matrix_world.inverted()
                for obj in samples:
                    evaluated = obj.evaluated_get(deps)
                    mesh = evaluated.to_mesh()
                    error = max((evaluated.matrix_world @ mesh.vertices[i].co-transform @ obj.matrix_world @ obj.data.vertices[i].co).length for i in range(len(mesh.vertices)))
                    evaluated.to_mesh_clear()
                    assert error < .00002, (obj.name, wanted, frame, error)
                for obj in back_samples:
                    evaluated = obj.evaluated_get(deps)
                    mesh = evaluated.to_mesh()
                    transforms = {g.index: native_arm.matrix_world @ native_arm.pose.bones[g.name].matrix @ native_arm.data.bones[g.name].matrix_local.inverted() @ native_arm.matrix_world.inverted() for g in obj.vertex_groups}
                    for i, vertex in enumerate(obj.data.vertices):
                        expected = sum((transforms[g.group] @ obj.matrix_world @ vertex.co*g.weight for g in vertex.groups), Vector())
                        error = (evaluated.matrix_world @ mesh.vertices[i].co-expected).length
                        assert error < .00002, (obj.name, wanted, frame, 'native spine skin', error)
                    evaluated.to_mesh_clear()
                blended = Matrix(((0, 0, 0, 0),)*4)
                for name, weight in rigid['weights'].items():
                    blended += (native_arm.matrix_world @ native_arm.pose.bones[name].matrix @
                                native_arm.data.bones[name].matrix_local.inverted() @ native_arm.matrix_world.inverted())*weight
                strains = np.linalg.svd(np.array(blended.to_3x3()), compute_uv=False)
                max_strain = float(np.max(np.abs(strains-1)))
                assert blended.to_3x3().determinant() > 0 and max_strain < .02, (wanted, frame, 'anchor affine stretch', max_strain)
                rigid_results.append({'action': action.name, 'frame': frame, 'maximum_uniform_affine_strain': max_strain})
                animation_results.append({'action': action.name, 'frame': frame})
        result['checks']['native_animation_rigid_attachment_samples'] = animation_results
        result['checks']['native_spine_holstered_animation_samples'] = animation_results
        result['checks']['uniform_hard_shield_transform_no_inversion_samples'] = rigid_results
        result['passed'] = True
        print('CULTURAL_SHIELDS_TEST_PASS', sex, len(names), flush=True)
    except Exception as exc:
        result['failure'] = repr(exc)
        raise
    finally:
        (QA / f'{sex}_test.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')


def preview(sex, arm, parts, back_only=False):
    """Four material-lit contact sheets. Run only after the main grants the GPU slot."""
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_EEVEE_NEXT'
    scene.eevee.taa_render_samples = 24
    scene.render.resolution_x = 1800
    scene.render.resolution_y = 2200
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.film_transparent = False
    scene.view_settings.view_transform = 'AgX'
    world = bpy.data.worlds.new('CulturalShieldReviewWorld')
    world.use_nodes = True
    world.node_tree.nodes['Background'].inputs[0].default_value = (.12, .14, .17, 1)
    world.node_tree.nodes['Background'].inputs[1].default_value = .5
    scene.world = world
    for obj in bpy.data.objects:
        obj.hide_render = True
    data = bpy.data.cameras.new('ShieldReviewCamera')
    camera = bpy.data.objects.new('ShieldReviewCamera', data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.location = (0, -8, 0)
    camera.rotation_euler = (Vector((0, 0, 0))-camera.location).to_track_quat('-Z', 'Y').to_euler()
    data.type = 'ORTHO'
    data.ortho_scale = 3.12
    for name, position, power, size in [('Key', (-3, -4, 4), 700, 4), ('Fill', (3, -2, 1), 400, 3),
                                         ('Rim', (1, 2, 3), 600, 3)]:
        lamp = bpy.data.lights.new('ShieldReview'+name, 'AREA')
        lamp.energy, lamp.shape, lamp.size = power, 'DISK', size
        light = bpy.data.objects.new(lamp.name, lamp)
        scene.collection.objects.link(light)
        light.location = position
        light.rotation_euler = (-light.location).to_track_quat('-Z', 'Y').to_euler()
    if back_only:
        render_backcarry(sex, arm, parts)
        return
    basis = arm.matrix_world @ arm.data.bones[BONE].matrix_local
    inverse = basis.inverted()
    measurement = json.loads((QA / f'{sex}_measurement.json').read_text(encoding='utf-8'))
    fit = ShieldFit(arm, measurement)
    orient = Matrix(((0, -1, 0, 0), (0, 0, -1, 0), (1, 0, 0, 0), (0, 0, 0, 1)))
    review = []
    # Include the unchanged original in the otherwise missing Western Iron cell.
    for row, kind in enumerate(MATERIALS):
        for col, style in enumerate(STYLES):
            prefix = 'Shield_Heater_01' if (style, kind) == ('Western', 'Iron') else f'Shield_{style}_{kind}_01'
            objects = [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith(prefix+'_') and 'Holstered' not in o.name]
            target = Vector(((col-1)*.78, 0, (1.5-row)*.71-.04))
            for obj in objects:
                clone = bpy.data.objects.new('Review_'+obj.name, obj.data)
                scene.collection.objects.link(clone)
                review.append((clone, obj.matrix_world.copy(), target))
            label_data = bpy.data.curves.new('ShieldLabel', 'FONT')
            label_data.body = f'{style.upper()} / {kind.upper()}'+(' [ORIGINAL]' if prefix == 'Shield_Heater_01' else '')
            label_data.align_x = 'CENTER'
            label_data.size = .027
            label = bpy.data.objects.new('ShieldLabel', label_data)
            scene.collection.objects.link(label)
            label.location = target+Vector((0, -.32, .335))
            label.rotation_euler = (math.pi/2, 0, 0)
            text_mat = bpy.data.materials.get('ShieldReviewText') or bpy.data.materials.new('ShieldReviewText')
            text_mat.diffuse_color = (.92, .93, .95, 1)
            label_data.materials.append(text_mat)
    for label, angle in [('front', 0), ('side', 90), ('back_grip', 180), ('threequarter', 35)]:
        rotation = Matrix.Rotation(math.radians(angle), 4, 'X')
        for obj, original_world, target in review:
            obj.matrix_world = Matrix.Translation(target) @ orient @ rotation @ Matrix.Translation((0, -fit.cy, -.06)) @ inverse @ original_world
        scene.render.filepath = str(QA / f'{sex}_shields_{label}.png')
        bpy.ops.render.render(write_still=True)
    # Use evaluated native guard animation and actual body skin for a grip close-up.
    for obj in bpy.data.objects:
        if obj.type in ('MESH', 'FONT'):
            obj.hide_render = True
    with bpy.data.libraries.load(str(BASE / f'standard_anime_{sex}_character_pack.blend'), link=False) as (available, loaded):
        loaded.actions = [name for name in available.actions if name.lower() == 'guard']
    assert loaded.actions, 'Native guard clip missing'
    arm.data.pose_position = 'POSE'
    arm.animation_data_create()
    arm.animation_data.action = loaded.actions[0]
    scene.frame_set(12)
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    posed_inverse = (arm.matrix_world @ arm.pose.bones[BONE].matrix).inverted()
    body = bpy.data.objects['Body_Standard_'+sex.title()]
    group_names = {g.index: g.name for g in body.vertex_groups}
    accepted = {v.index for v in body.data.vertices if sum(g.weight for g in v.groups
                if group_names[g.group].startswith(('J_Bip_L_LowerArm', 'J_Bip_L_Hand', 'J_Bip_L_Thumb',
                                                     'J_Bip_L_Index', 'J_Bip_L_Middle', 'J_Bip_L_Ring', 'J_Bip_L_Little'))) > .5}
    evaluated = body.evaluated_get(deps)
    body_mesh = evaluated.to_mesh()
    faces = [tuple(p.vertices) for p in body.data.polygons if all(v in accepted for v in p.vertices)]
    skin = bpy.data.meshes.new('ShieldNativeGuardForearm')
    skin.from_pydata([v.co for v in body_mesh.vertices], [], faces)
    skin.materials.clear()
    skin_mat = bpy.data.materials.new('ShieldProofNativeSkin')
    skin_mat.diffuse_color = (.63, .36, .22, 1)
    skin.materials.append(skin_mat)
    for polygon in skin.polygons:
        polygon.use_smooth = True
    evaluated.to_mesh_clear()
    for row, angle in enumerate((30, 145)):
        for col, prefix in enumerate(('Shield_Chinese_Stone_01', 'Shield_Japanese_Wood_01', 'Shield_Western_Steel_01')):
            target = Vector(((col-1)*.80, 0, (.5-row)*.78))
            transform = Matrix.Translation(target) @ orient @ Matrix.Rotation(math.radians(angle), 4, 'X') @ Matrix.Translation((0, -fit.cy, -.06)) @ posed_inverse
            skin_obj = bpy.data.objects.new('NativeGuardSkinReview', skin)
            scene.collection.objects.link(skin_obj)
            skin_obj.matrix_world = transform @ body.matrix_world
            for obj in parts:
                if not obj.name.startswith(prefix+'_') or '_Holstered_' in obj.name:
                    continue
                data = bpy.data.meshes.new_from_object(obj.evaluated_get(deps))
                clone = bpy.data.objects.new('NativeGuard_'+obj.name, data)
                scene.collection.objects.link(clone)
                clone.matrix_world = transform @ obj.matrix_world
    scene.render.resolution_y = 1300
    scene.camera.data.ortho_scale = 2.5
    scene.render.filepath = str(QA / f'{sex}_native_guard_grip.png')
    bpy.ops.render.render(write_still=True)
    print('CULTURAL_SHIELDS_PREVIEW_READY', sex, flush=True)


def render_backcarry(sex, arm, parts):
    """One bounded torso/contact sheet per sex; no source/export writes."""
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = 1800, 1500
    scene.camera.location = (0, 8, 0)
    scene.camera.rotation_euler = (-scene.camera.location).to_track_quat('-Z', 'Y').to_euler()
    scene.camera.data.ortho_scale = 2.55
    body = bpy.data.objects['Body_Standard_'+sex.title()]
    accepted = {v.index for v in body.data.vertices if .78 < (body.matrix_world @ v.co).z < 1.50}
    faces = [tuple(p.vertices) for p in body.data.polygons if all(i in accepted for i in p.vertices)]
    with bpy.data.libraries.load(str(BASE / f'standard_anime_{sex}_character_pack.blend'), link=False) as (available, loaded):
        loaded.actions = [n for n in available.actions if n.lower() in ('idle', 'walk')]
    actions = {a.name.lower(): a for a in loaded.actions}
    assert set(actions) == {'idle', 'walk'}
    arm.data.pose_position = 'POSE'
    arm.animation_data_create()
    neutral = bpy.data.materials.new('ShieldBackCarryNeutralSkin')
    neutral.diffuse_color = (.39, .40, .41, 1)
    for row, (action, frame, angle) in enumerate((('idle', 12, 0), ('walk', 6, 70))):
        arm.animation_data.action = actions[action]
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        deps = bpy.context.evaluated_depsgraph_get()
        evaluated = body.evaluated_get(deps)
        native_mesh = evaluated.to_mesh()
        torso = bpy.data.meshes.new('ShieldBackCarryTorso')
        torso.from_pydata([v.co for v in native_mesh.vertices], [], faces)
        torso.materials.append(neutral)
        for polygon in torso.polygons:
            polygon.use_smooth = True
        evaluated.to_mesh_clear()
        for col, prefix in enumerate(('Shield_Chinese_Stone_01', 'Shield_Japanese_Wood_01', 'Shield_Western_Steel_01')):
            target = Vector(((col-1)*.80, 0, (.5-row)*1.0))
            transform = Matrix.Translation(target) @ Matrix.Rotation(math.radians(angle), 4, 'Z') @ Matrix.Translation((0, 0, -1.15 if sex == 'male' else -1.10))
            obj = bpy.data.objects.new('NativeBackCarryTorso', torso)
            scene.collection.objects.link(obj)
            obj.matrix_world = transform @ body.matrix_world
            for source in parts:
                if not source.name.startswith(prefix+'_Holstered_'):
                    continue
                mesh = bpy.data.meshes.new_from_object(source.evaluated_get(deps))
                obj = bpy.data.objects.new('BackCarryReview_'+source.name, mesh)
                scene.collection.objects.link(obj)
                obj.matrix_world = transform @ source.matrix_world
    scene.render.filepath = str(QA / f'{sex}_native_backcarry.png')
    bpy.ops.render.render(write_still=True)
    print('CULTURAL_SHIELDS_BACKCARRY_PREVIEW_READY', sex, flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sex', choices=['male', 'female'], required=True)
    parser.add_argument('--stage', choices=['probe', 'build', 'holster', 'carry_probe', 'rigid_carry', 'export', 'test', 'preview', 'back_preview'], required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    WORK.mkdir(parents=True, exist_ok=True)
    QA.mkdir(parents=True, exist_ok=True)
    source = BASE / f'standard_anime_{args.sex}_character_pack.blend' if args.stage in ('probe', 'build') else WORK / f'cultural_shields_{args.sex}.blend'
    bpy.ops.wm.open_mainfile(filepath=str(source))
    arm = bpy.data.objects['Armature']
    rest(arm)
    if args.stage == 'probe':
        measure(arm, args.sex)
    elif args.stage == 'build':
        fit = ShieldFit(arm, measure(arm, args.sex))
        parts = build(fit)
        arm['cultural_shields_fit'] = json.dumps({'grip': list(fit.grip), 'strap_y': fit.strap_y,
                                                 'arm_rx': fit.arm_rx, 'arm_rz': fit.arm_rz})
        parts = add_holstered(args.sex, arm, parts)
        rigid_backcarry(args.sex, arm, parts, repair=True)
        save_source(args.sex, arm, parts)
        export(args.sex, arm, parts)
    elif args.stage == 'holster':
        parts = add_holstered(args.sex, arm, authored_parts())
        rigid_backcarry(args.sex, arm, parts, repair=True)
        save_source(args.sex, arm, parts)
        export(args.sex, arm, parts)
    elif args.stage in ('carry_probe', 'rigid_carry'):
        parts = authored_parts()
        repair = args.stage == 'rigid_carry'
        rigid_backcarry(args.sex, arm, parts, repair=repair)
        if repair:
            save_source(args.sex, arm, parts)
            export(args.sex, arm, parts)
    elif args.stage == 'export':
        export(args.sex, arm, authored_parts())
    elif args.stage == 'test':
        test(args.sex, arm, authored_parts())
    elif args.stage == 'preview':
        preview(args.sex, arm, authored_parts())
    elif args.stage == 'back_preview':
        preview(args.sex, arm, authored_parts(), back_only=True)
    else:
        raise NotImplementedError(args.stage)


if __name__ == '__main__':
    main()
