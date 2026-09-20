"""Scoped native boot walk diagnosis/candidate. Never publishes formal assets."""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).parent))
from repair_character_audit import reset_rig
from author_chinese_leather_mingguang import Fitting
from author_western_plate import limb_surface

TARGETS = ('Boots_Japanese_Iron_01_', 'Boots_Japanese_Steel_01_',
           'Boots_Western_Iron_01_', 'Boots_Western_Steel_01_')
OUT = ROOT / 'output/equipment_walk_fix_20260919/boots'


def mesh_hash(obj, positions=True):
    value = {'polygons': [(list(p.vertices), p.material_index, p.use_smooth) for p in obj.data.polygons],
             'materials': [m.name if m else None for m in obj.data.materials],
             'uv': [(u.name, [[float(x) for x in d.uv] for d in u.data]) for u in obj.data.uv_layers],
             'weights': [[(obj.vertex_groups[g.group].name, g.weight) for g in v.groups] for v in obj.data.vertices],
             'matrix': [list(row) for row in obj.matrix_world]}
    if positions:
        value['vertices'] = [list(v.co) for v in obj.data.vertices]
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def animation_state(arm):
    actions = {a.name: hashlib.sha256(json.dumps([(f.data_path, f.array_index,
        [(list(k.co), k.interpolation, list(k.handle_left), list(k.handle_right))
         for k in f.keyframe_points]) for f in a.fcurves]).encode()).hexdigest()
        for a in bpy.data.actions}
    rig = [(b.name, b.parent.name if b.parent else None, [list(row) for row in b.matrix_local])
           for b in arm.data.bones]
    pose = [(b.name, [list(row) for row in b.matrix_basis]) for b in arm.pose.bones]
    nla = [(t.name, t.mute, [(s.name, s.action.name if s.action else None, s.frame_start, s.frame_end)
                            for s in t.strips]) for t in arm.animation_data.nla_tracks]
    return {'actions': actions, 'rig': hashlib.sha256(json.dumps(rig).encode()).hexdigest(),
            'pose': hashlib.sha256(json.dumps(pose).encode()).hexdigest(),
            'nla': hashlib.sha256(json.dumps(nla).encode()).hexdigest(),
            'active_action': arm.animation_data.action.name if arm.animation_data.action else None}


def repair_boots(arm, sex):
    """Edit only four selected boot groups on the caller's loaded native pack.

    Requires caller-restored rest pose. Does not change animation, rig, topology,
    materials, UVs, names, weights, or any unrelated object. Returns provenance.
    """
    assert not arm.get('boot_same_side_walk_repair'), 'Boot repair already applied'
    animations = animation_state(arm)
    fit = Fitting(arm, sex)
    all_meshes = {o.name: mesh_hash(o) for o in bpy.data.objects if o.type == 'MESH'}
    invariants = {o.name: mesh_hash(o, False) for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith(TARGETS)}
    changed = {}
    for side, sign in (('L', 1), ('R', -1)):
        # Same source skin, but its opposite leg cannot be a ray-cast target.
        side_faces = [tuple(p.vertices) for p in fit.body.data.polygons
                      if all(fit.points[i].x * sign > 0 for i in p.vertices)]
        side_tree = BVHTree.FromPolygons(fit.points, side_faces)
        full_tree = fit.bvh
        lower, foot = 'J_Bip_' + side + '_LowerLeg', 'J_Bip_' + side + '_Foot'
        for prefix in TARGETS:
            specs = [('Greave_' + side, 18, 48, .13, .85, .023, math.pi * .94, None)] if 'Western' in prefix else [
                *[(f'Suneate_{i}_{side}', 12, 5, .16, .78, .015, math.pi, i) for i in range(3)],
                *[(f'ShinTie_{i}_{side}', 2, 40, .23 + .43*i, .26 + .43*i, .020, math.pi, None) for i in range(2)]]
            for suffix, rows, cols, lo, hi, offset, angular, splint in specs:
                obj = bpy.data.objects[prefix + suffix]
                count = (rows + 1) * (cols + 1)
                assert len(obj.data.vertices) == count * 2 and not obj.data.shape_keys, obj.name
                fit.bvh = full_tree
                old_fn = limb_surface(fit, lower, foot, lo, hi, offset, angular)
                # limb_surface closes over fit, so materialize before swapping.
                old = [old_fn(.25 + splint*.17 + c/cols*.15 if splint is not None else c/cols, r/rows)
                       for r in range(rows+1) for c in range(cols+1)]
                fit.bvh = side_tree
                new_fn = limb_surface(fit, lower, foot, lo, hi, offset, angular)
                new = [new_fn(.25 + splint*.17 + c/cols*.15 if splint is not None else c/cols, r/rows)
                       for r in range(rows+1) for c in range(cols+1)]
                fit.bvh = full_tree
                if max((a-b).length for a, b in zip(old, new)) < 1e-7:
                    continue
                # Keep baked thickness and all manually authored values. Move each
                # original vertex by the same-side correction at its source sample.
                inverse = obj.matrix_world.inverted()
                largest = 0.0
                for i, vertex in enumerate(obj.data.vertices):
                    delta = new[i % count] - old[i % count]
                    if delta.length > 1e-7:
                        vertex.co = inverse @ (obj.matrix_world @ vertex.co + delta)
                    largest = max(largest, delta.length)
                obj.data.update()
                changed[obj.name] = {'before': all_meshes[obj.name], 'after': mesh_hash(obj),
                                     'vertices': len(obj.data.vertices), 'max_displacement_m': largest}
                trim = bpy.data.objects.get(obj.name + '_RolledEdge')
                if trim is not None:
                    triangles = []
                    for r in range(rows):
                        for c in range(cols):
                            i = r * (cols+1) + c
                            triangles.extend(((i, i+1, i+cols+2), (i, i+cols+2, i+cols+1)))
                    source_tree = BVHTree.FromPolygons(old, triangles, all_triangles=True)
                    inverse = trim.matrix_world.inverted()
                    trim_largest = 0.0
                    for vertex in trim.data.vertices:
                        p = trim.matrix_world @ vertex.co
                        nearest, _, face, _ = source_tree.find_nearest(p)
                        a, b, c = triangles[face]
                        mapped = barycentric_transform(nearest, old[a], old[b], old[c], new[a], new[b], new[c])
                        delta = mapped - nearest
                        vertex.co = inverse @ (p + delta)
                        trim_largest = max(trim_largest, delta.length)
                    trim.data.update()
                    changed[trim.name] = {'before': all_meshes[trim.name], 'after': mesh_hash(trim),
                        'vertices': len(trim.data.vertices), 'max_displacement_m': trim_largest}
    untouched = {name: value for name, value in all_meshes.items() if name not in changed}
    assert all(mesh_hash(bpy.data.objects[name]) == value for name, value in untouched.items())
    assert all(mesh_hash(bpy.data.objects[name], False) == value for name, value in invariants.items()), 'Topology/material/UV/weights/transforms changed'
    assert animation_state(arm) == animations, 'Rig/action/NLA/pose changed'
    arm['boot_same_side_walk_repair'] = 1
    return {'changed': changed, 'untouched_mesh_count': len(untouched), 'untouched_hashes': untouched,
            'unchanged_attributes_hashes': invariants,
            'unchanged_animation_state': animations,
            'rule': 'Original limb grid + same-side skin-only raycast; existing baked thickness and rolled-edge topology preserved.'}


def pair_overlap(arm):
    reset_rig(arm)
    arm.animation_data.action = bpy.data.actions['walk']
    start, end = arm.animation_data.action.frame_range
    result = []
    for step in range(25):
        frame = start + (end-start)*step/24
        bpy.context.scene.frame_set(int(frame), subframe=frame % 1)
        graph = bpy.context.evaluated_depsgraph_get()
        row = {'frame': frame, 'overlaps': {}}
        for prefix in TARGETS:
            by_side = []
            for side in ('L', 'R'):
                parts = [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith(prefix)
                         and any(s in o.name for s in ('Greave', 'Suneate', 'ShinTie'))
                         and (o.name.endswith('_'+side) or o.name.endswith('_'+side+'_RolledEdge'))]
                by_side.append(tree(parts, graph)[0])
            row['overlaps'][prefix] = len(by_side[0].overlap(by_side[1]))
        result.append(row)
    reset_rig(arm)
    return result


def candidate(sex):
    arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    before = pair_overlap(arm)
    report = repair_boots(arm, sex)
    after = pair_overlap(arm)
    report.update({'before_walk_pair_intersections': before, 'after_walk_pair_intersections': after})
    parts = [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith(TARGETS)]
    scene = bpy.data.scenes.new('BootRepairCandidate')
    for obj in [arm, *parts]:
        scene.collection.objects.link(obj)
    blend = OUT / f'boots_candidate_{sex}.blend'
    assert not blend.exists()
    bpy.data.libraries.write(str(blend), {scene}, path_remap='RELATIVE_ALL', compress=True)
    bpy.data.scenes.remove(scene)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [arm, *parts]:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=str(OUT / f'boots_candidate_{sex}.glb'), export_format='GLB',
        use_selection=True, export_animations=False, export_skins=True, export_morph=False, export_apply=False)
    return report


def mesh_world(obj, graph):
    evaluated = obj.evaluated_get(graph)
    mesh = evaluated.to_mesh()
    points = [evaluated.matrix_world @ v.co for v in mesh.vertices]
    faces = [tuple(p.vertices) for p in mesh.polygons]
    evaluated.to_mesh_clear()
    return points, faces


def tree(objects, graph):
    vertices, faces, owners = [], [], []
    for obj in objects:
        points, polys = mesh_world(obj, graph)
        offset = len(vertices)
        vertices.extend(points)
        faces.extend(tuple(i + offset for i in p) for p in polys)
        owners.extend([obj.name] * len(polys))
    return BVHTree.FromPolygons(vertices, faces), owners


def inspection(sex):
    arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    reset_rig(arm)
    parts = [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith(TARGETS)]
    body = bpy.data.objects['Body_Standard_' + sex.title()]
    knee = (arm.matrix_world @ arm.data.bones['J_Bip_L_LowerLeg'].head_local).z
    sources = [body] + [o for o in bpy.data.objects if o.type == 'MESH' and
        o.name in ('Armor_Iron_01_Underlayer_Pants', 'Armor_Western_Iron_01_UnderPants',
                   'Armor_Japanese_Iron_01_UnderPants', 'Armor_Japanese_Steel_01_UnderPants')]
    report = {'sex': sex, 'knee': knee, 'actions': [a.name for a in bpy.data.actions],
              'meshes': {}, 'frames': [], 'scope': 'Unmasked native frontal ray occlusion; exposed open regions are not automatically defects.'}
    for obj in parts + sources:
        points = [obj.matrix_world @ v.co for v in obj.data.vertices]
        totals = {}
        for v in obj.data.vertices:
            for g in v.groups:
                name = obj.vertex_groups[g.group].name
                totals[name] = totals.get(name, 0) + g.weight
        report['meshes'][obj.name] = {'vertices': len(points), 'bounds': [[min(p[i] for p in points) for i in range(3)],
            [max(p[i] for p in points) for i in range(3)]], 'groups': totals,
            'modifiers': [(m.name, m.type) for m in obj.modifiers],
            'shape_keys': [k.name for k in obj.data.shape_keys.key_blocks] if obj.data.shape_keys else [],
            'materials': [m.name if m else None for m in obj.data.materials],
            'uv': [u.name for u in obj.data.uv_layers]}
    eligible = {o.name: [v.index for v in o.data.vertices if
        .015 < (o.matrix_world @ v.co).z < knee - .055 and v.normal.y < -.15] for o in sources}
    action = bpy.data.actions.get('walk')
    assert action is not None, report['actions']
    arm.animation_data.action = action
    start, end = action.frame_range
    report['walk_range'] = [start, end]
    for step in range(25):
        frame = start + (end - start) * step / 24
        bpy.context.scene.frame_set(int(frame), subframe=frame % 1)
        bpy.context.view_layer.update()
        graph = bpy.context.evaluated_depsgraph_get()
        posed_sources = {o.name: mesh_world(o, graph)[0] for o in sources}
        row = {'frame': frame, 'parts': {}}
        for prefix in TARGETS:
            bvh, owners = tree([o for o in parts if o.name.startswith(prefix)], graph)
            results = {}
            for source in sources:
                defects = []
                for index in eligible[source.name]:
                    p = posed_sources[source.name][index]
                    hit, _, face, _ = bvh.ray_cast(p + Vector((0, -1, 0)), Vector((0, 1, 0)), 2)
                    if hit is not None and hit.y > p.y + .001:
                        defects.append({'vertex': index, 'depth_m': hit.y-p.y, 'point': list(p), 'boot_mesh': owners[face]})
                defects.sort(key=lambda item: -item['depth_m'])
                results[source.name] = {'count': len(defects), 'worst': defects[:8]}
            row['parts'][prefix] = results
        report['frames'].append(row)
        print('BOOT_WALK_FRAME', sex, step, flush=True)
    return report


def main():
    global OUT
    parser = argparse.ArgumentParser()
    parser.add_argument('--sex', choices=('male', 'female'), required=True)
    parser.add_argument('--stage', choices=('inspect', 'candidate'), default='inspect')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    if args.stage == 'candidate':
        OUT = OUT / 'v3'
    OUT.mkdir(parents=True, exist_ok=True)
    source = ROOT / f'assets/characters/human/q35/standard_anime_{args.sex}_character_pack.blend'
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(source))
    report = inspection(args.sex) if args.stage == 'inspect' else candidate(args.sex)
    report['source'] = str(source.relative_to(ROOT))
    report['source_sha256'] = digest
    assert hashlib.sha256(source.read_bytes()).hexdigest() == digest
    target = OUT / f'{args.sex}_native_inspection.json' if args.stage == 'inspect' else OUT / f'{args.sex}_candidate_provenance.json'
    assert not target.exists(), target
    target.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('BOOT_WALK_DIAGNOSIS_COMPLETE', args.sex, str(target), flush=True)


if __name__ == '__main__':
    main()
