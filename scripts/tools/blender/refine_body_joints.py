"""Local arm tessellation and skin-weight continuity; rig/rest silhouette unchanged."""
import bmesh


def refine_body_joints(armature, objects):
    reports = []
    for obj in objects:
        if not obj.name.startswith('Body_Standard_') or obj.get('worldgoing_joint_refinement_v1'):
            continue
        assert not obj.data.shape_keys, 'Body shape keys require explicit interpolation'
        mesh = obj.data
        original_count = len(mesh.vertices)
        original_normals = {(tuple(sorted(tuple(mesh.vertices[v].co) for v in p.vertices)), tuple(mesh.vertices[mesh.loops[i].vertex_index].co)): tuple(mesh.corner_normals[i].vector)
                            for p in mesh.polygons for i in p.loop_indices}
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bm.verts.ensure_lookup_table()
        deform = bm.verts.layers.deform.verify()
        affected = set()
        for side in ('L', 'R'):
            for joint, parent, width in [('LowerArm', 'UpperArm', .075), ('Hand', 'LowerArm', .037)]:
                bone = armature.data.bones[f'J_Bip_{side}_{joint}']
                transform = obj.matrix_world.inverted() @ armature.matrix_world
                center = transform @ bone.head_local
                axis = (transform.to_3x3() @ (bone.tail_local - bone.head_local)).normalized()
                child_id = obj.vertex_groups[bone.name].index
                parent_id = obj.vertex_groups[f'J_Bip_{side}_{parent}'].index

                def inside(v):
                    delta = v.co - center
                    distance = delta.dot(axis)
                    return abs(distance) < width and (delta-axis*distance).length < .065 and v[deform].get(child_id, 0) + v[deform].get(parent_id, 0) > .90

                selected = [v for v in bm.verts if inside(v)]
                selected_set = set(selected)
                edges = [e for e in bm.edges if all(v in selected_set for v in e.verts)]
                affected.update(tuple(v.co) for v in selected)
                bmesh.ops.subdivide_edges(bm, edges=edges, cuts=2, use_grid_fill=True)
                for v in bm.verts:
                    if not inside(v):
                        continue
                    distance = (v.co-center).dot(axis)
                    influence = max(0, 1-(abs(distance)/width)**2)**2
                    t = max(0, min(1, .5 + distance/(width*1.5)))
                    t = t*t*(3-2*t)
                    weights = v[deform]
                    total = weights.get(child_id, 0) + weights.get(parent_id, 0)
                    child = weights.get(child_id, 0)*(1-influence) + total*t*influence
                    weights[child_id] = child
                    weights[parent_id] = total-child
        bm.normal_update()
        # Unmodified body faces retain their authored split normals, not a global smooth pass.
        normals = []
        for face in bm.faces:
            points = tuple(sorted(tuple(v.co) for v in face.verts))
            protected = all(tuple(v.co) not in affected for v in face.verts)
            for loop in face.loops:
                original = original_normals.get((points, tuple(loop.vert.co)))
                normals.append(original if protected and original is not None else tuple(loop.vert.normal))
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()
        mesh.normals_split_custom_set(normals)
        obj['worldgoing_joint_refinement_v1'] = True
        reports.append({'object': obj.name, 'original_vertices': original_count, 'refined_vertices': len(mesh.vertices), 'local_original_vertices': len(affected)})
    return reports
