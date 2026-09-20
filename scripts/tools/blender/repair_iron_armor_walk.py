"""Inspect and locally repair iron armor; output candidates, never formal files."""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import barycentric_transform

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).parent))
from repair_character_audit import reset_rig

OUT = ROOT / 'output/equipment_walk_fix_20260919/armor'
PREFIXES = ('Armor_Iron_01_', 'Armor_Western_Iron_01_')
SPLIT_FRONT = ('Armor_Iron_01_Tasset_Front', 'Armor_Iron_01_Tasset_Front_Gold')


def world_points(obj):
    return [obj.matrix_world @ v.co for v in obj.data.vertices]


def bounds(points):
    return [[min(p[i] for p in points) for i in range(3)],
            [max(p[i] for p in points) for i in range(3)]]


def inspect(sex, arm):
    reset_rig(arm)
    meshes = {}
    for obj in bpy.data.objects:
        if obj.type != 'MESH' or not obj.name.startswith(PREFIXES):
            continue
        groups = {}
        for v in obj.data.vertices:
            for g in v.groups:
                name = obj.vertex_groups[g.group].name
                groups[name] = groups.get(name, 0) + g.weight
        meshes[obj.name] = dict(vertices=len(obj.data.vertices), bounds=bounds(world_points(obj)),
            groups=groups, modifiers=[(m.name, m.type) for m in obj.modifiers],
            keys=[k.name for k in obj.data.shape_keys.key_blocks] if obj.data.shape_keys else [],
            uv=[u.name for u in obj.data.uv_layers])
    return {'sex': sex, 'meshes': meshes, 'actions': [a.name for a in bpy.data.actions],
            'bones': {b.name: list(arm.matrix_world @ b.head_local) for b in arm.data.bones
                      if 'Leg' in b.name or 'Hips' in b.name}}


def mesh_signature(obj, include_geometry=True):
    payload = dict(materials=[m.name if m else None for m in obj.data.materials],
        uv=[(u.name, [list(v.uv) for v in u.data]) for u in obj.data.uv_layers],
        faces=[(list(p.vertices), p.material_index, p.use_smooth) for p in obj.data.polygons])
    if include_geometry:
        payload['vertices'] = [(list(v.co), [(g.group, g.weight) for g in v.groups]) for v in obj.data.vertices]
        payload['groups'] = [g.name for g in obj.vertex_groups]
    return hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()


def action_signatures():
    return {a.name: hashlib.sha256(json.dumps([(f.data_path, f.array_index,
        [(list(k.co), k.interpolation, list(k.handle_left), list(k.handle_right))
         for k in f.keyframe_points]) for f in a.fcurves]).encode()).hexdigest()
        for a in bpy.data.actions}


def repair_western(fit, prefix='Armor_Western_Iron_01'):
    """Deform only original cuisse and edge vertices to the same-side fitted surface.

    Uses the existing loft_boot same-side polygon rule and limb_surface sampler.
    Mesh topology, original UVs, materials, trim, weights and transforms survive.
    """
    from author_western_plate import limb_surface
    changed, measurements = [], []
    whole = fit.bvh
    for side, sign in [('L', 1), ('R', -1)]:
        first, last = 'J_Bip_'+side+'_UpperLeg', 'J_Bip_'+side+'_LowerLeg'
        fit.bvh = whole
        old_fn = limb_surface(fit, first, last, .22, .85, .019, math.pi*.77)
        # limb_surface closes over fit, so collect the old samples before replacing bvh.
        old = [old_fn(c/36, r/14) for r in range(15) for c in range(37)]
        faces = [tuple(p.vertices) for p in fit.body.data.polygons
                 if all(fit.points[i].x*sign > 0 for i in p.vertices)]
        fit.bvh = BVHTree.FromPolygons(fit.points, faces)
        new_fn = limb_surface(fit, first, last, .22, .85, .019, math.pi*.77)
        new = [new_fn(c/36, r/14) for r in range(15) for c in range(37)]
        triangles = []
        for r in range(14):
            for c in range(36):
                i = r*37+c
                triangles.extend([(i,i+1,i+38), (i,i+38,i+37)])
        old_tree = BVHTree.FromPolygons(old, triangles, all_triangles=True)
        for suffix in ['', '_RolledEdge']:
            obj = bpy.data.objects[prefix+'_Cuisse_'+side+suffix]
            assert not obj.data.shape_keys, obj.name
            before = bounds(world_points(obj))
            inv = obj.matrix_world.inverted()
            assert suffix or len(obj.data.vertices) == len(old)*2
            # Original grid order preserves both solidified thickness layers;
            # trim maps continuously across that surface, as in boot repair.
            for v in obj.data.vertices:
                p = obj.matrix_world @ v.co
                if not suffix:
                    i = v.index % len(old)
                    assert (p-old[i]).length < .012, (obj.name, v.index)
                    delta = new[i]-old[i]
                else:
                    nearest, _, face, distance = old_tree.find_nearest(p)
                    assert distance < .012, (obj.name, v.index, distance)
                    a,b,c = triangles[face]
                    delta = barycentric_transform(nearest,old[a],old[b],old[c],new[a],new[b],new[c])-nearest
                v.co = inv @ (p + delta)
            obj.data.update()
            after = bounds(world_points(obj))
            assert after[1][0]-after[0][0] < before[1][0]-before[0][0]-.06
            changed.append(obj)
            measurements.append(dict(name=obj.name, before=before, after=after))
    fit.bvh = whole
    return changed, measurements


def native_counts(obj):
    mesh = obj.data
    mesh.calc_loop_triangles()
    return dict(vertices=len(mesh.vertices), faces=len(mesh.polygons),
                triangles=len(mesh.loop_triangles), materials=len(mesh.materials),
                material_names=[m.name if m else None for m in mesh.materials],
                uv_layer_count=len(mesh.uv_layers), uv_layer_names=[u.name for u in mesh.uv_layers])


def split_front(obj):
    """Cut existing solidified lames at world X=0, preserving loop custom data."""
    before = native_counts(obj)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.transform(obj.matrix_world)
    origin = bm.faces.layers.int.new('armor_cut_source_face')
    uv_layers = list(bm.loops.layers.uv.values())
    original = []
    for index, face in enumerate(bm.faces):
        face[origin] = index
        original.append(dict(material=face.material_index, smooth=face.smooth,
            points=[loop.vert.co.copy() for loop in face.loops],
            uv=[[loop[layer].uv.copy() for loop in face.loops] for layer in uv_layers]))
    bmesh.ops.bisect_plane(bm, geom=list(bm.verts)+list(bm.edges)+list(bm.faces),
                          dist=1e-7, plane_co=(0,0,0), plane_no=(1,0,0))
    center = [e for e in bm.edges if all(abs(v.co.x) < 1e-6 for v in e.verts)]
    assert center, obj.name
    bmesh.ops.split_edges(bm, edges=center)
    sides = {}
    for face in bm.faces:
        xs = [v.co.x for v in face.verts]
        assert not (min(xs) < -1e-6 and max(xs) > 1e-6), (obj.name, 'uncut bridge')
        sign = 1 if sum(xs) > 0 else -1
        for vertex in face.verts:
            assert vertex not in sides or sides[vertex] == sign, (obj.name, 'shared center vertex')
            sides[vertex] = sign
        source = original[face[origin]]
        assert (face.material_index, face.smooth) == (source['material'], source['smooth'])
        # A plane cut creates corners only on original polygon edges. Verify
        # BMesh's loop UV interpolation against that original edge, per face.
        for layer, old_uv in zip(uv_layers, source['uv']):
            points = source['points']
            for loop in face.loops:
                valid = False
                for i, a in enumerate(points):
                    b = points[(i+1) % len(points)]
                    edge = b-a
                    t = max(0, min(1, (loop.vert.co-a).dot(edge)/max(edge.length_squared, 1e-20)))
                    if (loop.vert.co-a-edge*t).length < 2e-6:
                        expected = old_uv[i].lerp(old_uv[(i+1) % len(points)], t)
                        valid |= (loop[layer].uv-expected).length < 2e-5
                assert valid, (obj.name, 'cut UV interpolation')
    cut_boundaries = [e for e in bm.edges if e.is_boundary and
                      all(abs(v.co.x) < 1e-6 for v in e.verts)]
    assert cut_boundaries, (obj.name, 'missing physical slit')
    caps = bmesh.ops.holes_fill(bm, edges=cut_boundaries, sides=0)['faces']
    assert caps, (obj.name, 'missing thickness caps')
    for face in caps:
        adjacent = next(f for e in face.edges for f in e.link_faces if f != face)
        face.material_index, face.smooth = adjacent.material_index, False
        for loop in face.loops:
            donor = next(l for f in loop.vert.link_faces if f not in caps
                         for l in f.loops if l.vert == loop.vert)
            for layer in uv_layers:
                loop[layer].uv = donor[layer].uv
    assert not any(e.is_boundary for e in cut_boundaries), (obj.name, 'open thickness cap')
    assert all(len({sides[v] for v in f.verts}) == 1 for f in bm.faces), obj.name
    bm.faces.layers.int.remove(origin)
    bm.verts.index_update()
    membership = {v.index: sides[v] for v in bm.verts}
    bm.transform(obj.matrix_world.inverted())
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    after = native_counts(obj)
    assert after['vertices'] > before['vertices']
    for key in ('materials', 'material_names', 'uv_layer_count', 'uv_layer_names'):
        assert after[key] == before[key], (obj.name, key)
    return membership, dict(before=before, after=after, cap_faces=len(caps),
        original_face_materials_preserved=True, uv_interpolation_verified=True,
        uv_loops_checked=sum(len(f['points'])*len(f['uv']) for f in original),
        no_shared_midline_vertices=True, no_cross_half_faces=True)


def repair_chinese(fit, prefix='Armor_Iron_01'):
    """Independent halves, with pelvis-supported plates and measured clearance."""
    from author_chinese_leather_mingguang import smooth
    front = (prefix+'_Tasset_Front', prefix+'_Tasset_Front_Gold')
    names = list(front)
    names += [prefix+'_Tasset_Side_'+suffix for suffix in ['L','R','Gold_L','Gold_R']]
    changed, topology = [], {}
    for name in names:
        obj = bpy.data.objects[name]
        assert not obj.data.shape_keys, name
        old_uv = mesh_signature(obj, False)
        halves = None
        if name in front:
            halves, topology[name] = split_front(obj)
        obj.vertex_groups.clear()
        hips = obj.vertex_groups.new(name='J_Bip_C_Hips')
        left = obj.vertex_groups.new(name='J_Bip_L_UpperLeg')
        right = obj.vertex_groups.new(name='J_Bip_R_UpperLeg')
        inv = obj.matrix_world.inverted()
        for v in obj.data.vertices:
            p = obj.matrix_world @ v.co
            influence = smooth((fit.hip+.015-p.z)/.14)
            leg = (.65 if halves else .98)*influence
            share = (1 if halves[v.index] > 0 else 0) if halves else smooth((p.x+.012)/.024)
            hips.add([v.index], 1-leg, 'REPLACE')
            if leg*share > 0:
                left.add([v.index], leg*share, 'REPLACE')
            if leg*(1-share) > 0:
                right.add([v.index], leg*(1-share), 'REPLACE')
            # Leave the belt fixed; preserve a little breathing room at the lames.
            if 'Front' in name:
                p.y -= .035*influence
                # 6mm total rest overlap, tapered to zero near the upper anchor.
                # Stagger the layers by 4.5mm so the 3.5mm plate thickness clears.
                seam = smooth((.025-abs(p.x))/.025)*influence
                p.x -= halves[v.index]*.003*seam
                if halves[v.index] > 0:
                    p.y -= .0045*seam
            v.co = inv @ p
            assert abs(sum(g.weight for g in v.groups)-1) < 1e-6
        obj.data.update()
        if halves:
            assert all(len({halves[i] for i in p.vertices}) == 1 for p in obj.data.polygons)
            assert all(not (left.index in {g.group for g in v.groups if g.weight > 0} and
                            right.index in {g.group for g in v.groups if g.weight > 0})
                       for v in obj.data.vertices)
            topology[name]['after'] = native_counts(obj)
            topology[name]['single_thigh_per_vertex'] = True
        else:
            assert mesh_signature(obj, False) == old_uv
        changed.append(obj)
    return changed, topology


def rest_clearance(sex):
    """Signed front-ray gaps to unchanged rest meshes, not animation acceptance."""
    apron = world_points(bpy.data.objects[SPLIT_FRONT[0]])
    result = {'apron_bounds': bounds(apron), 'sources': {}}
    for name in ['Body_Standard_'+sex.title(), 'Armor_Iron_01_Underlayer_Pants']:
        obj = bpy.data.objects[name]
        points = world_points(obj)
        bvh = BVHTree.FromPolygons(points, [tuple(p.vertices) for p in obj.data.polygons])
        gaps, hits = [], []
        for p in apron:
            hit, _, _, _ = bvh.ray_cast(Vector((p.x, -2, p.z)), Vector((0,1,0)), 4)
            if hit is not None:
                hits.append(hit.y)
                gaps.append(hit.y-p.y)
        assert gaps, name
        ordered = sorted(gaps)
        result['sources'][name] = dict(samples=len(gaps), misses=len(apron)-len(gaps),
            source_front_y=[min(hits), max(hits)], gap_min_m=min(gaps),
            gap_median_m=ordered[len(ordered)//2], gap_max_m=max(gaps),
            armor_behind_source_samples=sum(g < -1e-4 for g in gaps))
    return result


def repair_armor(arm, sex):
    """Parent integration entry; current formal pack must already be open/rested."""
    from author_chinese_leather_mingguang import Fitting
    assert not arm.get('iron_armor_walk_repair'), 'Armor repair already applied'
    before = {o.name: mesh_signature(o) for o in bpy.data.objects if o.type == 'MESH'}
    invariant = {o.name: mesh_signature(o, False) for o in bpy.data.objects
                 if o.type == 'MESH' and o.name.startswith(PREFIXES)}
    animations = action_signatures()
    reset_rig(arm)
    clearance_before = rest_clearance(sex)
    fit = Fitting(arm, sex)
    western, measurements = repair_western(fit)
    chinese, topology = repair_chinese(fit)
    changed = {o.name: {'before': before[o.name], 'after': mesh_signature(o),
                       'vertices': len(o.data.vertices)} for o in western+chinese
                       if before[o.name] != mesh_signature(o)}
    unchanged = {n:h for n,h in before.items() if n not in changed}
    assert all(mesh_signature(bpy.data.objects[n]) == h for n,h in unchanged.items())
    assert set(topology) == set(SPLIT_FRONT)
    invariant = {n:h for n,h in invariant.items() if n not in topology}
    assert all(mesh_signature(bpy.data.objects[n],False) == h for n,h in invariant.items())
    assert action_signatures() == animations
    arm['iron_armor_walk_repair'] = 4
    return {'changed': changed, 'unchanged_mesh_count': len(unchanged),
            'unchanged_hashes': unchanged, 'unchanged_surface_hashes': invariant,
            'unchanged_action_hashes': animations, 'western_measurements': measurements,
            'topology_changed': topology, 'new_morph_channels': 0,
            'chinese_static_parameters': {'max_thigh_weight': .98, 'front_max_thigh_weight': .65,
                'side_max_thigh_weight': .98, 'max_forward_m': .035,
                'max_seam_stagger_m': .0045, 'total_rest_overlap_m': .006},
            'rest_clearance': {'before': clearance_before, 'after': rest_clearance(sex)}}


def collision_probe(sex, arm):
    """Unmasked front rays are diagnostics, not a replacement for native GPU QA."""
    from repair_cultural_boot_walk import tree, mesh_world
    report = []
    pants = [bpy.data.objects[n] for n in ['Armor_Iron_01_Underlayer_Pants',
                                          'Armor_Western_Iron_01_UnderPants']]
    groups = [[bpy.data.objects[n] for n in ['Armor_Iron_01_Tasset_Front',
                  'Armor_Iron_01_Tasset_Side_L', 'Armor_Iron_01_Tasset_Side_R']],
              [o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith('Armor_Western_Iron_01_Cuisse_')]]
    eligible = [[v.index for v in p.data.vertices if .68 < (p.matrix_world@v.co).z < .91
                 and v.normal.y < -.25] for p in pants]
    for clip in ['walk', 'run', 'attack_jump_heavy', 'attack_spear', 'knockback']:
        reset_rig(arm)
        action = bpy.data.actions[clip]
        arm.animation_data.action = action
        first, last = action.frame_range
        for step in range(25):
            frame = first+(last-first)*step/24
            bpy.context.scene.frame_set(int(frame), subframe=frame%1)
            bpy.context.view_layer.update()
            graph = bpy.context.evaluated_depsgraph_get()
            row = {'clip': clip, 'step': step, 'counts': []}
            for source, armor, indices in zip(pants, groups, eligible):
                points = mesh_world(source, graph)[0]
                bvh, owners = tree(armor, graph)
                penetrating = []
                for i in indices:
                    p = points[i]
                    hit, _, face, _ = bvh.ray_cast(p+Vector((0,-1,0)), Vector((0,1,0)), 2)
                    if hit is not None and .001 < hit.y-p.y < .15:
                        penetrating.append({'vertex': i, 'depth': hit.y-p.y, 'mesh': owners[face]})
                row['counts'].append({'source': source.name, 'count': len(penetrating),
                    'worst': sorted(penetrating, key=lambda r:-r['depth'])[:3]})
            report.append(row)
        print('ARMOR_NATIVE_PROBE', sex, clip, flush=True)
    reset_rig(arm)
    return report


def candidate(sex, arm, folder, source_glb, subset_only=False):
    folder.mkdir(parents=True, exist_ok=False)
    meshes = {o.name: mesh_signature(o) for o in bpy.data.objects if o.type == 'MESH'}
    animations = action_signatures()
    previous_run = json.loads((OUT/'diagnostics'/f'{sex}_candidate_v2.json').read_text(encoding='utf-8'))
    assert previous_run['source_sha256'] == hashlib.sha256(Path(bpy.data.filepath).read_bytes()).hexdigest()
    before = previous_run['native_before']
    repair_report = repair_armor(arm, sex)
    previous = previous_run['repair']
    frozen = [n for n in previous['changed'] if n.startswith('Armor_Western_Iron_01_')]
    assert all(mesh_signature(bpy.data.objects[n]) == previous['changed'][n]['after'] for n in frozen), \
        'Western repair must remain exactly as v2'
    repair_report['frozen_v2_meshes_identical'] = frozen
    repair_report['before_probe_reused_from_same_sha256'] = str(OUT/'diagnostics'/f'{sex}_candidate_v2.json')
    changed = [bpy.data.objects[n] for n in repair_report['changed']]
    after = collision_probe(sex, arm)
    names = {o.name for o in changed}
    assert all(mesh_signature(bpy.data.objects[n]) == h for n, h in meshes.items() if n not in names)
    assert animations == action_signatures(), 'Original actions changed'
    bpy.ops.wm.save_as_mainfile(filepath=str(folder/f'{sex}.blend'))
    for o in bpy.context.scene.objects:
        o.select_set(False)
    for o in changed+[arm]:
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    subset = folder/f'{sex}_subset.glb'
    bpy.ops.export_scene.gltf(filepath=str(subset), export_format='GLB', use_selection=True,
        export_animations=False, export_skins=True, export_morph=False, export_apply=False)
    if subset_only:
        return {'repair': repair_report, 'changed': sorted(names),
            'unrelated_meshes_unchanged': len(meshes)-len(names), 'original_actions_unchanged': len(animations),
            'native_before': before, 'native_after': after,
            'acceptance': 'SUBSET CANDIDATE ONLY: original node-preserving splice and native GPU review pending.'}
    import author_weapon_refresh as splice_helper
    previous_prefix = splice_helper.PREFIX
    splice_helper.PREFIX = PREFIXES
    try:
        splice_helper.splice(source_glb, subset, folder/f'{sex}.glb', {})
    finally:
        splice_helper.PREFIX = previous_prefix
    return {'repair': repair_report, 'changed': sorted(names),
        'unrelated_meshes_unchanged': len(meshes)-len(names), 'original_actions_unchanged': len(animations),
        'native_before': before, 'native_after': after,
        'acceptance': 'CANDIDATE ONLY: native Godot walk and major-pose visual review pending.'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--sex', choices=['male', 'female'], required=True)
    parser.add_argument('--stage', choices=['inspect', 'candidate'], default='inspect')
    parser.add_argument('--revision', default='v1')
    parser.add_argument('--subset-only', action='store_true')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:])
    # Published packs can already contain a previous repair. Always start this
    # scoped candidate from the immutable batch baseline, never repair twice.
    source = OUT.parent / f'baseline/standard_anime_{args.sex}_character_pack.blend'
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(source))
    arm = next(o for o in bpy.context.scene.objects if o.type == 'ARMATURE')
    report = (inspect(args.sex, arm) if args.stage == 'inspect' else
              candidate(args.sex, arm, OUT/'candidate'/args.revision/args.sex,
                        source.with_suffix('.glb'), args.subset_only))
    report['source_sha256'] = source_hash
    assert hashlib.sha256(source.read_bytes()).hexdigest() == source_hash
    target = OUT / 'diagnostics' / f'{args.sex}_{args.stage}_{args.revision}.json'
    target.parent.mkdir(parents=True, exist_ok=True)
    assert not target.exists(), target
    target.write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('ARMOR_INSPECTION_COMPLETE', args.sex, flush=True)


if __name__ == '__main__':
    main()
