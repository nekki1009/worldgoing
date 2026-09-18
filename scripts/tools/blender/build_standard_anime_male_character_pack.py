"""Build one real, modular 3D character pack from the retained VRM source."""

import json
import math
import os
import sys
from pathlib import Path

import bmesh
import bpy
import mathutils
from mathutils import Vector, Matrix, Euler, Quaternion
from mathutils.bvhtree import BVHTree

_script_dir = os.path.dirname(os.path.abspath(__file__))
if _script_dir not in sys.path:
    sys.path.insert(0, _script_dir)
from make_chinese_iron_helmet import make_chinese_iron_helmet
from make_chinese_steel_helmet import make_chinese_steel_helmet
from make_chinese_iron_armor import make_chinese_iron_armor
from make_mingguang_armor import make_mingguang_armor
from make_chinese_iron_boots import make_chinese_iron_boots, make_mingguang_boots
from load_authored_chinese_leather_boots import load_chinese_leather_boots
from load_authored_medieval_shoes import load_medieval_shoes
from load_authored_cloth_hats import load_cloth_hats
from make_chinese_cape import make_chinese_cape, bind_cape_action_tracks
from load_authored_chinese_gear import load_chinese_gear
from load_authored_western_plate import load_western_iron
from load_authored_chinese_leather_helmet import load_chinese_leather_helmet
from load_authored_chinese_lining import load_chinese_lining


PROJECT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SOURCE_VRM = os.environ.get(
    "WORLDGOING_SOURCE_VRM",
    os.path.join(PROJECT_DIR, ".tools", "standard_anime_base", "HairSample_Male.vrm"),
)
ADDON_DIR = os.environ.get(
    "WORLDGOING_VRM_ADDON",
    os.path.join(PROJECT_DIR, ".tools", "standard_anime_base", "io_scene_vrm"),
)
OUTPUT_DIR = os.path.join(PROJECT_DIR, "assets", "characters", "human", "q35")
OUTPUT_BLEND = os.path.join(OUTPUT_DIR, "standard_anime_male_character_pack.blend")
OUTPUT_GLB = os.path.join(OUTPUT_DIR, "standard_anime_male_character_pack.glb")
OUTPUT_METADATA = os.path.join(OUTPUT_DIR, "standard_anime_male_character_pack.json")
LEGACY_ANIMATION_SOURCE = OUTPUT_GLB
PREVIEW_DIR = os.path.join(PROJECT_DIR, ".visual_captures", "standard_anime_male_character_pack", "blender")
FRAME_START = 1
FRAME_END = 25


def load_vrm_addon(addon_dir: str) -> None:
    parent_dir = os.path.dirname(addon_dir)
    if parent_dir not in sys.path:
        sys.path.insert(0, parent_dir)
    bpy.ops.preferences.addon_enable(module="io_scene_vrm")


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for datablocks in (
        bpy.data.objects,
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def component_props(obj: bpy.types.Object, slot: str, visual_id: str) -> None:
    obj["worldgoing_component_slot"] = slot
    obj["worldgoing_visual_id"] = visual_id


def copy_mesh(source: bpy.types.Object, name: str, slot: str, visual_id: str) -> bpy.types.Object:
    obj = source.copy()
    obj.data = source.data.copy()
    obj.name = name
    bpy.context.collection.objects.link(obj)
    component_props(obj, slot, visual_id)
    return obj


def copy_material_subset(
    source: bpy.types.Object,
    name: str,
    keep_material_indices: set[int],
    slot: str,
    visual_id: str,
) -> bpy.types.Object:
    obj = copy_mesh(source, name, slot, visual_id)
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    delete_faces = [face for face in bm.faces if face.material_index not in keep_material_indices]
    bmesh.ops.delete(bm, geom=delete_faces, context="FACES")
    loose_vertices = [vertex for vertex in bm.verts if not vertex.link_faces]
    bmesh.ops.delete(bm, geom=loose_vertices, context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    return obj


def trim_source_top_without_hood(obj: bpy.types.Object) -> None:
    """Keep the fitted source top while removing hood and drawstring geometry."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    delete_faces = []
    for face in bm.faces:
        face_bones = {
            obj.vertex_groups[assignment.group].name
            for vertex in face.verts
            for assignment in obj.data.vertices[vertex.index].groups
            if assignment.group < len(obj.vertex_groups)
        }
        if any("Hood" in bone_name or "HoodString" in bone_name for bone_name in face_bones):
            delete_faces.append(face)
    bmesh.ops.delete(bm, geom=delete_faces, context="FACES")
    loose_vertices = [vertex for vertex in bm.verts if not vertex.link_faces]
    bmesh.ops.delete(bm, geom=loose_vertices, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    print(
        "WORLDGOING_SOURCE_TOP_TRIM_PASS "
        f"name={obj.name} faces={len(obj.data.polygons)}"
    )


def create_baked_face_variant(
    source_face: bpy.types.Object,
    name: str,
    visual_id: str,
    shape_weights: dict[str, float],
    armature: bpy.types.Object,
) -> bpy.types.Object:
    new_obj = source_face.copy()
    new_obj.name = name
    new_obj.data = source_face.data.copy()
    new_obj.data.name = f"{name}Mesh"
    bpy.context.scene.collection.objects.link(new_obj)

    kb = source_face.data.shape_keys.key_blocks
    basis_key = kb["Basis"]

    active_keys = []
    for key_pattern, weight in shape_weights.items():
        matched = next((k for k in kb if key_pattern.lower() in k.name.lower()), None)
        if matched and weight != 0.0:
            active_keys.append((matched, weight))

    n_verts = len(new_obj.data.vertices)
    target_coords = []
    for i in range(n_verts):
        base_co = basis_key.data[i].co.copy()
        delta = Vector((0.0, 0.0, 0.0))
        for key, weight in active_keys:
            delta += (key.data[i].co - base_co) * weight
        target_coords.append(base_co + delta)

    copy_kb = new_obj.data.shape_keys.key_blocks
    copy_basis = copy_kb["Basis"]
    for i in range(n_verts):
        copy_basis.data[i].co = target_coords[i]
        new_obj.data.vertices[i].co = target_coords[i]

    non_basis = [k for k in copy_kb if k.name != "Basis"]
    for k in non_basis:
        new_obj.shape_key_remove(k)
    new_obj.shape_key_remove(copy_basis)
    new_obj.data.update()

    for mod in new_obj.modifiers:
        if mod.type == "ARMATURE":
            mod.object = armature
    new_obj.parent = armature
    new_obj.matrix_parent_inverse = armature.matrix_world.inverted()
    component_props(new_obj, "face", visual_id)

    return new_obj


def material(name: str, color: tuple[float, float, float], metallic: float = 0.0, roughness: float = 0.78) -> bpy.types.Material:
    result = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    result.diffuse_color = (*color, 1.0)
    result.use_nodes = True
    nodes = result.node_tree.nodes
    links = result.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    return result


def apply_transforms(obj: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.select_set(False)


def add_armature_skin(obj: bpy.types.Object, armature: bpy.types.Object, bone_name: str) -> None:
    for m in list(obj.modifiers):
        if m.type == 'ARMATURE':
            obj.modifiers.remove(m)
    obj.vertex_groups.clear()
    group = obj.vertex_groups.new(name=bone_name)
    group.add([vertex.index for vertex in obj.data.vertices], 1.0, "REPLACE")
    modifier = obj.modifiers.new("WorldgoingArmature", "ARMATURE")
    modifier.object = armature
    obj.parent = armature
    obj.matrix_parent_inverse = armature.matrix_world.inverted()
    component_props(obj, str(obj.get("worldgoing_component_slot", "")), str(obj.get("worldgoing_visual_id", "")))


def add_z_blended_armature_skin(
    obj: bpy.types.Object,
    armature: bpy.types.Object,
    anchors: list[tuple[float, str]],
) -> None:
    """Blend deforming clothing between the same vertical bone regions as the body."""
    if not anchors:
        add_armature_skin(obj, armature, "J_Bip_C_Spine")
        return
    for m in list(obj.modifiers):
        if m.type == 'ARMATURE':
            obj.modifiers.remove(m)
    obj.vertex_groups.clear()
    groups = {bone_name: obj.vertex_groups.new(name=bone_name) for _, bone_name in anchors}
    for vertex in obj.data.vertices:
        z = vertex.co.z
        if z <= anchors[0][0]:
            groups[anchors[0][1]].add([vertex.index], 1.0, "REPLACE")
            continue
        if z >= anchors[-1][0]:
            groups[anchors[-1][1]].add([vertex.index], 1.0, "REPLACE")
            continue
        for index in range(len(anchors) - 1):
            lower_z, lower_bone = anchors[index]
            upper_z, upper_bone = anchors[index + 1]
            if z > upper_z:
                continue
            blend = (z - lower_z) / max(upper_z - lower_z, 0.0001)
            groups[lower_bone].add([vertex.index], 1.0 - blend, "REPLACE")
            groups[upper_bone].add([vertex.index], blend, "REPLACE")
            break
    modifier = obj.modifiers.new("WorldgoingArmature", "ARMATURE")
    modifier.object = armature
    obj.parent = armature
    obj.matrix_parent_inverse = armature.matrix_world.inverted()
    component_props(obj, str(obj.get("worldgoing_component_slot", "")), str(obj.get("worldgoing_visual_id", "")))


def add_briefs_armature_skin(obj: bpy.types.Object, armature: bpy.types.Object) -> None:
    """Keep the waistband on the pelvis while the two leg openings follow thighs."""
    for m in list(obj.modifiers):
        if m.type == 'ARMATURE':
            obj.modifiers.remove(m)
    obj.vertex_groups.clear()
    hips = obj.vertex_groups.new(name="J_Bip_C_Hips")
    left_leg = obj.vertex_groups.new(name="J_Bip_L_UpperLeg")
    right_leg = obj.vertex_groups.new(name="J_Bip_R_UpperLeg")
    for vertex in obj.data.vertices:
        lower_t = max(0.0, min(1.0, (1.025 - vertex.co.z) / 0.195))
        side_t = max(0.0, min(1.0, (abs(vertex.co.x) - 0.025) / 0.145))
        thigh_weight = 0.72 * lower_t * side_t
        hips.add([vertex.index], 1.0 - thigh_weight, "REPLACE")
        if vertex.co.x < 0.0:
            left_leg.add([vertex.index], thigh_weight, "REPLACE")
        else:
            right_leg.add([vertex.index], thigh_weight, "REPLACE")
    modifier = obj.modifiers.new("WorldgoingArmature", "ARMATURE")
    modifier.object = armature
    obj.parent = armature
    obj.matrix_parent_inverse = armature.matrix_world.inverted()
    component_props(obj, str(obj.get("worldgoing_component_slot", "")), str(obj.get("worldgoing_visual_id", "")))


def fit_mesh_outside_surfaces(
    objects: list[bpy.types.Object],
    collision_objects: list[bpy.types.Object],
    clearance: float = 0.012,
) -> int:
    """Push each fitted layer outside the already-built inner surfaces."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    adjusted = 0
    # Most authored layers already have an explicit outward offset.  Four
    # passes are enough to resolve the remaining local overlaps and keep the
    # modular rebuild bounded as the number of real equipment parts grows.
    for _iteration in range(4):
        depsgraph.update()
        collision_bvhs = [
            BVHTree.FromObject(collision, depsgraph)
            for collision in collision_objects
        ]
        for obj in objects:
            if obj.type != "MESH":
                continue
            evaluated = obj.evaluated_get(depsgraph)
            mesh = evaluated.to_mesh()
            inverse_basis = obj.matrix_world.to_3x3().inverted()
            try:
                for index, vertex in enumerate(mesh.vertices):
                    world_co = evaluated.matrix_world @ vertex.co
                    nearest = None
                    for collision_bvh in collision_bvhs:
                        surface_co, normal, _index, distance = collision_bvh.find_nearest(world_co)
                        if distance is not None and (nearest is None or distance < nearest[3]):
                            nearest = (surface_co, normal, _index, distance)
                    if nearest is None:
                        continue
                    surface_co, normal, _index, distance = nearest
                    normal = normal.normalized()
                    signed_clearance = (world_co - surface_co).dot(normal)
                    if signed_clearance < clearance:
                        delta_world = normal * (clearance - signed_clearance)
                        obj.data.vertices[index].co += inverse_basis @ delta_world
                        adjusted += 1
            finally:
                evaluated.to_mesh_clear()
            obj.data.update()
    return adjusted


def mesh_object(
    name: str,
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    mat: bpy.types.Material,
    armature: bpy.types.Object,
    bone_name: str,
    slot: str,
    visual_id: str,
    weight_anchors: list[tuple[float, str]] | None = None,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.data.materials.append(mat)
    component_props(obj, slot, visual_id)
    if weight_anchors is None:
        add_armature_skin(obj, armature, bone_name)
    else:
        add_z_blended_armature_skin(obj, armature, weight_anchors)
    return obj


def filter_male_hair_islands(source_hair: bpy.types.Object, name: str, visual_id: str, armature: bpy.types.Object, mat: bpy.types.Material, del_condition) -> bpy.types.Object:
    """Filters specific hair ribbon islands from the authentic VRM spiky hair while preserving 360-degree skull cap and styled layers."""
    obj = copy_mesh(source_hair, name, "hair", visual_id)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    visited = set()
    del_faces = []
    for f in bm.faces:
        if f not in visited:
            island = []
            stack = [f]
            visited.add(f)
            while stack:
                cf = stack.pop()
                island.append(cf)
                for e in cf.edges:
                    for nxt in e.link_faces:
                        if nxt not in visited:
                            visited.add(nxt)
                            stack.append(nxt)
            verts = list({v for face in island for v in face.verts})
            min_z = min(v.co.z for v in verts)
            max_z = max(v.co.z for v in verts)
            avg_x = sum(v.co.x for v in verts) / len(verts)
            avg_y = sum(v.co.y for v in verts) / len(verts)
            avg_z = sum(v.co.z for v in verts) / len(verts)
            if del_condition(verts, min_z, max_z, avg_x, avg_y, avg_z):
                del_faces.extend(island)
    bmesh.ops.delete(bm, geom=del_faces, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    add_armature_skin(obj, armature, "J_Bip_C_Head")
    return obj


def create_hair_strand(
    bm: bmesh.types.BMesh,
    points: list[Vector],
    widths: list[float],
    normal_dir: Vector = Vector((0, 0, 1)),
    thickness_ratio: float = 0.35,
) -> list[bmesh.types.BMVert]:
    """Generates a curved 3D anime hair strand along a spine of points."""
    if len(points) < 2 or len(widths) != len(points):
        raise ValueError("points and widths must have the same length >= 2")

    normal_dir = normal_dir.normalized()
    layers = []
    created_verts = []

    for i, pt in enumerate(points):
        w = widths[i]
        if i == 0:
            tangent = (points[1] - points[0]).normalized()
        elif i == len(points) - 1:
            tangent = (points[-1] - points[-2]).normalized()
        else:
            tangent = (points[i + 1] - points[i - 1]).normalized()

        side = tangent.cross(normal_dir).normalized()
        crest_norm = side.cross(tangent).normalized()

        if w > 1e-4:
            v_l = bm.verts.new(pt - side * (w * 0.5))
            v_c = bm.verts.new(pt + crest_norm * (w * thickness_ratio))
            v_r = bm.verts.new(pt + side * (w * 0.5))
            layers.append((v_l, v_c, v_r))
            created_verts.extend([v_l, v_c, v_r])
        else:
            v_tip = bm.verts.new(pt)
            layers.append((v_tip, v_tip, v_tip))
            created_verts.append(v_tip)

    bm.verts.ensure_lookup_table()

    for i in range(len(layers) - 1):
        l1, c1, r1 = layers[i]
        l2, c2, r2 = layers[i + 1]
        if l2 != c2:
            bm.faces.new([l1, c1, c2, l2])
            bm.faces.new([c1, r1, r2, c2])
            bm.faces.new([r1, l1, l2, r2])
        else:
            bm.faces.new([l1, c1, l2])
            bm.faces.new([c1, r1, l2])
            bm.faces.new([r1, l1, l2])

    bm.faces.ensure_lookup_table()
    return created_verts


def build_world_hair_strand(
    bm: bmesh.types.BMesh,
    world_pts: list[Vector],
    widths: list[float],
    world_normal: Vector,
    inv_mat: Matrix,
    thickness_ratio: float = 0.35,
) -> list[bmesh.types.BMVert]:
    """Transforms world coordinates and normal vector into local object space and builds strand."""
    local_pts = [inv_mat @ p for p in world_pts]
    local_normal = (inv_mat.to_3x3() @ world_normal).normalized()
    return create_hair_strand(
        bm,
        local_pts,
        widths,
        normal_dir=local_normal,
        thickness_ratio=thickness_ratio,
    )


def make_male_hair_spiky_hero(
    source_hair: bpy.types.Object,
    name: str,
    visual_id: str,
    mat: bpy.types.Material,
    armature: bpy.types.Object,
) -> bpy.types.Object:
    """Hair 01: Complete authentic anime layered spiky hero cut."""
    obj = copy_mesh(source_hair, name, "hair", visual_id)
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    add_armature_skin(obj, armature, "J_Bip_C_Head")
    return obj


def make_male_hair_undercut(
    source_hair: bpy.types.Object,
    name: str,
    visual_id: str,
    mat: bpy.types.Material,
    armature: bpy.types.Object,
) -> bpy.types.Object:
    """Hair 02: Clean 7:3 anime side-parted hairstyle (側分短髮) with open forehead and styled fringe."""
    obj = copy_mesh(source_hair, name, "hair", visual_id)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()

    # Identify mesh islands
    visited = set()
    del_faces = []
    for f in bm.faces:
        if f not in visited:
            island = []
            stack = [f]
            visited.add(f)
            while stack:
                cf = stack.pop()
                island.append(cf)
                for e in cf.edges:
                    for nxt in e.link_faces:
                        if nxt not in visited:
                            visited.add(nxt)
                            stack.append(nxt)
            verts = list({v for face in island for v in face.verts})
            min_z = min(v.co.z for v in verts)
            avg_x = sum(v.co.x for v in verts) / len(verts)
            avg_y = sum(v.co.y for v in verts) / len(verts)
            # Character local X: +X is character right.
            # Remove the front bangs on character right side to open up forehead in a clean 7:3 part
            if 0.005 < avg_x < 0.075 and avg_y > 0.05 and min_z < 1.62:
                del_faces.extend(island)

    bmesh.ops.delete(bm, geom=del_faces, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")

    # Softly sweep remaining front fringe to the left (-X) and ensure tip height frames eyebrows
    for v in bm.verts:
        if v.co.y > 0.05 and 1.55 < v.co.z < 1.69:
            factor = (1.69 - v.co.z) / 0.14
            v.co.x -= 0.022 * factor
            if v.co.z < 1.60:
                v.co.z += 0.012 * (1.60 - v.co.z) / 0.05

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    add_armature_skin(obj, armature, "J_Bip_C_Head")
    return obj


def make_male_hair_wild_spiky(
    source_hair: bpy.types.Object,
    name: str,
    visual_id: str,
    mat: bpy.types.Material,
    armature: bpy.types.Object,
) -> bpy.types.Object:
    """Hair 03: Wild wolf cut (狼尾) with layered spiky locks streaming down the nape of the neck."""
    obj = copy_mesh(source_hair, name, "hair", visual_id)
    inv_mat = obj.matrix_world.inverted()
    bm = bmesh.new()
    bm.from_mesh(obj.data)

    # Nape is at Y_world = +0.050 ~ +0.065, Z_world = 1.30 ~ 1.55
    pts_m3_c = [
        Vector((0.0, 0.052, 1.55)),
        Vector((0.0, 0.065, 1.48)),
        Vector((0.0, 0.070, 1.42)),
        Vector((0.0, 0.065, 1.36)),
        Vector((0.0, 0.055, 1.30)),
    ]
    w_m3_c = [0.038, 0.055, 0.050, 0.035, 0.000]

    pts_m3_l = [
        Vector((-0.030, 0.048, 1.54)),
        Vector((-0.042, 0.060, 1.47)),
        Vector((-0.048, 0.065, 1.41)),
        Vector((-0.040, 0.058, 1.34)),
    ]
    w_m3_l = [0.030, 0.045, 0.038, 0.000]

    pts_m3_r = [
        Vector((0.030, 0.048, 1.54)),
        Vector((0.042, 0.060, 1.47)),
        Vector((0.048, 0.065, 1.41)),
        Vector((0.040, 0.058, 1.34)),
    ]
    w_m3_r = [0.030, 0.045, 0.038, 0.000]

    pts_m3_fl = [
        Vector((-0.055, 0.038, 1.52)),
        Vector((-0.068, 0.050, 1.45)),
        Vector((-0.070, 0.052, 1.38)),
    ]
    w_m3_fl = [0.025, 0.035, 0.000]

    pts_m3_fr = [
        Vector((0.055, 0.038, 1.52)),
        Vector((0.068, 0.050, 1.45)),
        Vector((0.070, 0.052, 1.38)),
    ]
    w_m3_fr = [0.025, 0.035, 0.000]

    build_world_hair_strand(bm, pts_m3_c, w_m3_c, Vector((0.0, 1.0, 0.2)), inv_mat)
    build_world_hair_strand(bm, pts_m3_l, w_m3_l, Vector((-0.5, 1.0, 0.2)), inv_mat)
    build_world_hair_strand(bm, pts_m3_r, w_m3_r, Vector((0.5, 1.0, 0.2)), inv_mat)
    build_world_hair_strand(bm, pts_m3_fl, w_m3_fl, Vector((-0.8, 0.8, 0.2)), inv_mat)
    build_world_hair_strand(bm, pts_m3_fr, w_m3_fr, Vector((0.8, 0.8, 0.2)), inv_mat)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    add_armature_skin(obj, armature, "J_Bip_C_Head")
    return obj


def make_male_hair_topknot(
    source_hair: bpy.types.Object,
    name: str,
    visual_id: str,
    mat: bpy.types.Material,
    gold_mat: bpy.types.Material,
    armature: bpy.types.Object,
) -> list[bpy.types.Object]:
    """Hair 04: Samurai warrior cut with golden topknot ring and upright ponytail plume arching back."""
    obj_base = copy_mesh(source_hair, name, "hair", visual_id)
    inv_mat = obj_base.matrix_world.inverted()
    bm = bmesh.new()
    bm.from_mesh(obj_base.data)

    # Crown tie point in world space is (0.0, 0.035, 1.76)
    pts_m4_c = [
        Vector((0.0, 0.035, 1.76)),
        Vector((0.0, 0.055, 1.83)),
        Vector((0.0, 0.090, 1.82)),
        Vector((0.0, 0.120, 1.76)),
        Vector((0.0, 0.135, 1.68)),
        Vector((0.0, 0.130, 1.58)),
    ]
    w_m4_c = [0.035, 0.055, 0.052, 0.042, 0.025, 0.000]

    pts_m4_l = [
        Vector((-0.015, 0.035, 1.76)),
        Vector((-0.025, 0.055, 1.82)),
        Vector((-0.035, 0.085, 1.80)),
        Vector((-0.038, 0.115, 1.74)),
        Vector((-0.028, 0.128, 1.66)),
    ]
    w_m4_l = [0.025, 0.040, 0.035, 0.020, 0.000]

    pts_m4_r = [
        Vector((0.015, 0.035, 1.76)),
        Vector((0.025, 0.055, 1.82)),
        Vector((0.035, 0.085, 1.80)),
        Vector((0.038, 0.115, 1.74)),
        Vector((0.028, 0.128, 1.66)),
    ]
    w_m4_r = [0.025, 0.040, 0.035, 0.020, 0.000]

    build_world_hair_strand(bm, pts_m4_c, w_m4_c, Vector((0.0, 0.5, 1.0)), inv_mat)
    build_world_hair_strand(bm, pts_m4_l, w_m4_l, Vector((-0.5, 0.5, 1.0)), inv_mat)
    build_world_hair_strand(bm, pts_m4_r, w_m4_r, Vector((0.5, 0.5, 1.0)), inv_mat)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj_base.data)
    bm.free()
    obj_base.data.update()
    obj_base.data.materials.clear()
    obj_base.data.materials.append(mat)
    add_armature_skin(obj_base, armature, "J_Bip_C_Head")

    # Gold Band Ring at crown tie point
    mesh_ring = bpy.data.meshes.new(name + "_BandMesh")
    bm_ring = bmesh.new()
    bmesh.ops.create_circle(bm_ring, cap_ends=False, radius=0.032, segments=20)
    res = bmesh.ops.extrude_edge_only(bm_ring, edges=bm_ring.edges)
    bmesh.ops.translate(bm_ring, vec=(0.0, 0.0, 0.016), verts=[v for v in res["geom"] if isinstance(v, bmesh.types.BMVert)])
    bmesh.ops.rotate(bm_ring, cent=(0.0, 0.0, 0.0), matrix=Matrix.Rotation(math.radians(35), 3, 'X'), verts=bm_ring.verts)
    loc_ring = inv_mat @ Vector((0.0, 0.038, 1.76))
    bmesh.ops.translate(bm_ring, vec=loc_ring, verts=bm_ring.verts)
    bm_ring.to_mesh(mesh_ring)
    bm_ring.free()
    obj_ring = bpy.data.objects.new(name + "_Band", mesh_ring)
    bpy.context.collection.objects.link(obj_ring)
    obj_ring.data.materials.append(gold_mat)
    for p in obj_ring.data.polygons:
        p.use_smooth = True
    component_props(obj_ring, "hair", visual_id)
    add_armature_skin(obj_ring, armature, "J_Bip_C_Head")

    return [obj_base, obj_ring]


def body_face_bones(obj: bpy.types.Object, face: bmesh.types.BMFace) -> set[str]:
    return {
        obj.vertex_groups[assignment.group].name
        for vertex in face.verts
        for assignment in obj.data.vertices[vertex.index].groups
    }


def make_conformal_body_layer(
    source: bpy.types.Object,
    name: str,
    mat: bpy.types.Material,
    armature: bpy.types.Object,
    slot: str,
    visual_id: str,
    keep_face,
    offset: float = 0.022,
) -> bpy.types.Object:
    """Copy the complete body surface, trim it by region, then offset it outward.

    The source VRM splits the skin across several material indices.  Filtering
    by material before the geometric trim can remove otherwise valid shoulder,
    leg, or foot faces and leave the clothing with holes.  Geometry, not the
    source material index, is the authority for a conformal clothing layer.
    """
    obj = copy_mesh(source, name, slot, visual_id)
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.faces.ensure_lookup_table()
    bm.normal_update()
    delete_faces = [
        face for face in bm.faces
        if not keep_face(face.calc_center_median(), face.normal, body_face_bones(obj, face))
    ]
    bmesh.ops.delete(bm, geom=delete_faces, context="FACES")
    bm.normal_update()
    for vertex in bm.verts:
        if vertex.link_faces and vertex.normal.length > 0.0:
            vertex.co += vertex.normal.normalized() * offset
    loose_vertices = [vertex for vertex in bm.verts if not vertex.link_faces]
    bmesh.ops.delete(bm, geom=loose_vertices, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    for polygon in obj.data.polygons:
        polygon.material_index = 0
    obj.data.update()
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    print(
        "WORLDGOING_CONFORMAL_LAYER "
        f"name={name} faces={len(obj.data.polygons)} offset={offset:.3f}"
    )
    return obj


def make_elliptical_shell(
    name: str,
    center_x: float,
    center_y: float,
    rings: list[tuple[float, float, float]],
    mat: bpy.types.Material,
    armature: bpy.types.Object,
    slot: str,
    visual_id: str,
    weight_anchors: list[tuple[float, str]],
    segments: int = 20,
) -> bpy.types.Object:
    """Create a clean, open-ended fitted garment shell from smooth rings."""
    vertices: list[tuple[float, float, float]] = []
    for z, radius_x, radius_y in rings:
        for index in range(segments):
            angle = math.tau * index / segments
            vertices.append((
                center_x + radius_x * math.cos(angle),
                center_y + radius_y * math.sin(angle),
                z,
            ))
    faces: list[tuple[int, ...]] = []
    for ring_index in range(len(rings) - 1):
        start = ring_index * segments
        next_start = (ring_index + 1) * segments
        for index in range(segments):
            next_index = (index + 1) % segments
            faces.append((start + index, start + next_index, next_start + next_index, next_start + index))
    obj = mesh_object(
        name,
        vertices,
        faces,
        mat,
        armature,
        weight_anchors[0][1],
        slot,
        visual_id,
        weight_anchors,
    )
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def super_ellipse_pt(ang: float, rx: float, ry: float, cy: float, p: float = 3.0) -> tuple[float, float]:
    cos_a = math.cos(ang)
    sin_a = math.sin(ang)
    sgn_x = 1.0 if cos_a >= 0 else -1.0
    sgn_y = 1.0 if sin_a >= 0 else -1.0
    vx = rx * sgn_x * (abs(cos_a) ** (2.0 / p))
    vy = cy + ry * sgn_y * (abs(sin_a) ** (2.0 / p))
    return vx, vy


def make_outfit(
    source_raw_body: bpy.types.Object,
    armature: bpy.types.Object,
    underwear_main: bpy.types.Material,
    underwear_accent: bpy.types.Material,
    underwear_shadow: bpy.types.Material,
) -> list[bpy.types.Object]:
    """Create a sleek, fitted boxer-briefs layer matching the art reference with zero back protrusion and 100% deformation fidelity."""
    del underwear_shadow

    def extract_mat2_layer(name: str, z_min: float, z_max: float, mat: bpy.types.Material, offset: float = 0.0, side_filter: str | None = None) -> bpy.types.Object:
        obj = copy_mesh(source_raw_body, name, "outfit", "outfit_underlayer_01")
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bm.faces.ensure_lookup_table()

        delete_faces = []
        for f in bm.faces:
            center = f.calc_center_median()
            keep = f.material_index == 0 and (z_min <= center.z <= z_max)
            if keep and side_filter == "L" and center.x >= -0.010:
                keep = False
            elif keep and side_filter == "R" and center.x <= 0.010:
                keep = False
            if not keep:
                delete_faces.append(f)
        bmesh.ops.delete(bm, geom=delete_faces, context="FACES")

        if offset > 0.0:
            bm.normal_update()
            for v in bm.verts:
                if v.link_faces and v.normal.length > 0:
                    v.co += v.normal.normalized() * offset

        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")

        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(obj.data)
        bm.free()
        obj.data.update()
        obj.data.materials.clear()
        obj.data.materials.append(mat)
        for poly in obj.data.polygons:
            poly.material_index = 0
            poly.use_smooth = True
        return obj

    # Fitted boxer briefs strictly extracted from skin (material_index == 0) with sleek 1.8mm offset
    briefs = extract_mat2_layer("Outfit_Underlayer_01_UnderwearBottom", 0.770, 1.015, underwear_main, offset=0.0018)
    waistband = extract_mat2_layer("Outfit_Underlayer_01_UnderwearWaistband", 0.985, 1.015, underwear_accent, offset=0.0024)
    cuff_l = extract_mat2_layer("Outfit_Underlayer_01_UnderwearLegOpening_L", 0.770, 0.790, underwear_accent, offset=0.0024, side_filter="L")
    cuff_r = extract_mat2_layer("Outfit_Underlayer_01_UnderwearLegOpening_R", 0.770, 0.790, underwear_accent, offset=0.0024, side_filter="R")

    return [briefs, waistband, cuff_l, cuff_r]


def beveled_cube(
    name: str,
    location: tuple[float, float, float],
    dimensions: tuple[float, float, float],
    mat: bpy.types.Material,
    armature: bpy.types.Object,
    bone_name: str,
    slot: str,
    visual_id: str,
    bevel_width: float = 0.015,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    obj.data.materials.append(mat)
    apply_transforms(obj)
    bevel = obj.modifiers.new("SoftEdges", "BEVEL")
    bevel.width = bevel_width
    bevel.segments = 4
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    component_props(obj, slot, visual_id)
    add_armature_skin(obj, armature, bone_name)
    return obj


def cylinder_segment(
    name: str,
    location: tuple[float, float, float],
    radius: float,
    depth: float,
    mat: bpy.types.Material,
    armature: bpy.types.Object,
    bone_name: str,
    slot: str,
    visual_id: str,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=radius, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    apply_transforms(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    component_props(obj, slot, visual_id)
    add_armature_skin(obj, armature, bone_name)
    return obj


def tapered_segment(
    name: str,
    location: tuple[float, float, float],
    radius_bottom: float,
    radius_top: float,
    depth: float,
    mat: bpy.types.Material,
    armature: bpy.types.Object,
    bone_name: str,
    slot: str,
    visual_id: str,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(
        vertices=12,
        radius1=radius_bottom,
        radius2=radius_top,
        depth=depth,
        location=location,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    apply_transforms(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    component_props(obj, slot, visual_id)
    add_armature_skin(obj, armature, bone_name)
    return obj


def boot_shaft(
    name: str,
    x_center: float,
    mat: bpy.types.Material,
    armature: bpy.types.Object,
    bone_name: str,
    slot: str,
    visual_id: str,
    weight_anchors: list[tuple[float, str]] | None = None,
) -> bpy.types.Object:
    """Low-poly ankle boot shaft with a calf swell and blended ankle weights."""
    rings = [
        (0.045, 0.028, 0.032),
        (0.105, 0.030, 0.034),
        (0.180, 0.032, 0.037),
        (0.270, 0.035, 0.040),
        (0.335, 0.038, 0.043),
    ]
    segments = 12
    vertices: list[tuple[float, float, float]] = []
    for z, radius_x, radius_y in rings:
        for index in range(segments):
            angle = math.tau * index / segments
            vertices.append((x_center + radius_x * math.cos(angle), -0.015 + radius_y * math.sin(angle), z))
    faces: list[tuple[int, ...]] = []
    for ring_index in range(len(rings) - 1):
        start = ring_index * segments
        next_start = (ring_index + 1) * segments
        for index in range(segments):
            next_index = (index + 1) % segments
            faces.append((start + index, start + next_index, next_start + next_index, next_start + index))
    faces.append(tuple(range(segments - 1, -1, -1)))
    top_start = (len(rings) - 1) * segments
    faces.append(tuple(top_start + index for index in range(segments)))
    obj = mesh_object(name, vertices, faces, mat, armature, bone_name, slot, visual_id, weight_anchors)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def ico_ellipsoid(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    mat: bpy.types.Material,
    armature: bpy.types.Object,
    bone_name: str,
    slot: str,
    visual_id: str,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.data.materials.append(mat)
    apply_transforms(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    component_props(obj, slot, visual_id)
    add_armature_skin(obj, armature, bone_name)
    return obj


def panel_prism(
    name: str,
    points: list[tuple[float, float]],
    front_y: float,
    back_y: float,
    mat: bpy.types.Material,
    armature: bpy.types.Object,
    bone_name: str,
    slot: str,
    visual_id: str,
    weight_anchors: list[tuple[float, str]] | None = None,
) -> bpy.types.Object:
    """A thin, deliberately faceted leather/cloth panel for sprite-like silhouettes."""
    vertices = [(x, front_y, z) for x, z in points]
    vertices += [(x, back_y, z) for x, z in points]
    count = len(points)
    signed_area = sum(
        points[index][0] * points[(index + 1) % count][1]
        - points[(index + 1) % count][0] * points[index][1]
        for index in range(count)
    )
    front_face = tuple(range(count - 1, -1, -1)) if signed_area < 0.0 else tuple(range(count))
    back_face = tuple(range(count, count * 2)) if signed_area < 0.0 else tuple(range(count * 2 - 1, count - 1, -1))
    faces: list[tuple[int, ...]] = [front_face, back_face]
    for index in range(count):
        next_index = (index + 1) % count
        faces.append((index, next_index, count + next_index, count + index))
    return mesh_object(name, vertices, faces, mat, armature, bone_name, slot, visual_id, weight_anchors)


def softened_panel(
    name: str,
    points: list[tuple[float, float]],
    front_y: float,
    back_y: float,
    mat: bpy.types.Material,
    armature: bpy.types.Object,
    bone_name: str,
    slot: str,
    visual_id: str,
    bevel_width: float,
    weight_anchors: list[tuple[float, str]] | None = None,
) -> bpy.types.Object:
    obj = panel_prism(name, points, front_y, back_y, mat, armature, bone_name, slot, visual_id, weight_anchors)
    # Apply the shape bevel before the skin modifier.  The old order made
    # Blender evaluate the bevel after the armature and produced a warning as
    # well as slightly mechanical-looking edge deformation.
    armature_modifier = next((modifier for modifier in obj.modifiers if modifier.type == "ARMATURE"), None)
    if armature_modifier is not None:
        obj.modifiers.remove(armature_modifier)
    bevel = obj.modifiers.new("SoftPanelEdges", "BEVEL")
    bevel.width = bevel_width
    bevel.segments = 2
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    obj.select_set(False)
    restored_armature = obj.modifiers.new("WorldgoingArmature", "ARMATURE")
    restored_armature.object = armature
    return obj


def curved_cuirass(
    name: str,
    rows: list[tuple[float, float]],
    edge_front_y: float,
    back_y: float,
    front_bulge: float,
    mat: bpy.types.Material,
    armature: bpy.types.Object,
    slot: str,
    visual_id: str,
    weight_anchors: list[tuple[float, str]],
) -> bpy.types.Object:
    """Build a small curved front shell with clean, animation-safe borders."""
    factors = (-1.0, -0.5, 0.0, 0.5, 1.0)
    vertices: list[tuple[float, float, float]] = []
    for z, half_width in rows:
        for factor in factors:
            x = half_width * factor
            bulge = front_bulge * max(0.0, 1.0 - factor * factor)
            vertices.append((x, edge_front_y - bulge, z))
    front_count = len(vertices)
    for z, half_width in rows:
        for factor in factors:
            vertices.append((half_width * factor, back_y, z))

    faces: list[tuple[int, ...]] = []
    column_count = len(factors)
    row_count = len(rows)
    for row in range(row_count - 1):
        start = row * column_count
        next_start = (row + 1) * column_count
        back_start = front_count + start
        back_next_start = front_count + next_start
        for column in range(column_count - 1):
            faces.append((start + column, start + column + 1, next_start + column + 1, next_start + column))
            faces.append((back_start + column, back_next_start + column, back_next_start + column + 1, back_start + column + 1))
        faces.append((start, next_start, back_next_start, back_start))
        last = column_count - 1
        faces.append((start + last, back_start + last, back_next_start + last, next_start + last))
    last_row = (row_count - 1) * column_count
    last_back_row = front_count + last_row
    for column in range(column_count - 1):
        faces.append((last_row + column, last_back_row + column, last_back_row + column + 1, last_row + column + 1))
        faces.append((column + 1, column, front_count + column, front_count + column + 1))

    obj = mesh_object(name, vertices, faces, mat, armature, "J_Bip_C_Chest", slot, visual_id, weight_anchors)
    armature_modifier = next((modifier for modifier in obj.modifiers if modifier.type == "ARMATURE"), None)
    if armature_modifier is not None:
        obj.modifiers.remove(armature_modifier)
    bevel = obj.modifiers.new("SoftCuirassEdges", "BEVEL")
    bevel.width = 0.008
    bevel.segments = 2
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    obj.select_set(False)
    restored_armature = obj.modifiers.new("WorldgoingArmature", "ARMATURE")
    restored_armature.object = armature
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def make_cape(
    armature: bpy.types.Object,
    mat: bpy.types.Material,
    gold: bpy.types.Material,
    silver: bpy.types.Material,
) -> list[bpy.types.Object]:
    """Create authentic flowing adventurer travel cape with shoulder brooch clasps and snug draped back."""
    parts: list[bpy.types.Object] = []
    visual_id = "cape_travel_01"

    def create_cape_rigid_component(name: str, bm: bmesh.types.BMesh, comp_mat: bpy.types.Material, bone: str) -> bpy.types.Object:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        mesh = bpy.data.meshes.new(name + "Mesh")
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(comp_mat)
        for p in obj.data.polygons:
            p.use_smooth = True
        vg = obj.vertex_groups.new(name=bone)
        vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
        mod = obj.modifiers.new("WorldgoingArmature", "ARMATURE")
        mod.object = armature
        obj.parent = armature
        obj.matrix_parent_inverse = armature.matrix_world.inverted()
        component_props(obj, "cape", visual_id)
        return obj

    def create_spine_skinned_cape_component(
        name: str,
        bm: bmesh.types.BMesh,
        comp_mat: bpy.types.Material,
        z_anchors: list[tuple[float, str]],
    ) -> bpy.types.Object:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        mesh = bpy.data.meshes.new(name + "Mesh")
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        if comp_mat:
            obj.data.materials.append(comp_mat)
        for p in obj.data.polygons:
            p.use_smooth = True

        vgs = {b_name: obj.vertex_groups.new(name=b_name) for _, b_name in z_anchors}
        for v_idx, v in enumerate(obj.data.vertices):
            vz = v.co.z
            if vz >= z_anchors[0][0]:
                vgs[z_anchors[0][1]].add([v_idx], 1.0, "REPLACE")
            elif vz <= z_anchors[-1][0]:
                vgs[z_anchors[-1][1]].add([v_idx], 1.0, "REPLACE")
            else:
                for i in range(len(z_anchors) - 1):
                    z_hi, bone_hi = z_anchors[i]
                    z_lo, bone_lo = z_anchors[i + 1]
                    if z_lo <= vz <= z_hi:
                        weight_hi = (vz - z_lo) / max(z_hi - z_lo, 0.001)
                        weight_lo = 1.0 - weight_hi
                        if weight_hi > 0.001:
                            vgs[bone_hi].add([v_idx], weight_hi, "REPLACE")
                        if weight_lo > 0.001:
                            vgs[bone_lo].add([v_idx], weight_lo, "REPLACE")
                        break

        mod = obj.modifiers.new("WorldgoingArmature", "ARMATURE")
        mod.object = armature
        obj.parent = armature
        obj.matrix_parent_inverse = armature.matrix_world.inverted()
        component_props(obj, "cape", visual_id)
        return obj

    # 1. Front Shoulder Brooches & Gem Insets
    for side, sign in (("L", 1.0), ("R", -1.0)):
        bm_b = bmesh.new()
        res_b = bmesh.ops.create_icosphere(bm_b, subdivisions=2, radius=0.014)
        for v in res_b["verts"]:
            v.co.y *= 0.35
            v.co.x += sign * 0.090
            v.co.y += -0.125
            v.co.z += 1.448
        parts.append(create_cape_rigid_component(f"Cape_Travel_01_Brooch_{side}", bm_b, gold, "J_Bip_C_UpperChest"))

        bm_gem = bmesh.new()
        res_gem = bmesh.ops.create_icosphere(bm_gem, subdivisions=1, radius=0.007)
        for v in res_gem["verts"]:
            v.co.x += sign * 0.090
            v.co.y += -0.131
            v.co.z += 1.448
        parts.append(create_cape_rigid_component(f"Cape_Travel_01_Gem_{side}", bm_gem, silver, "J_Bip_C_UpperChest"))

    # 2. Fastener Collar Band across front collarbone
    bm_cb = bmesh.new()
    cb_pts = [(-0.090, -0.125, 1.448), (0.0, -0.134, 1.440), (0.090, -0.125, 1.448)]
    w = 0.010
    v_l1 = bm_cb.verts.new((cb_pts[0][0], cb_pts[0][1], cb_pts[0][2] + w * 0.5))
    v_l2 = bm_cb.verts.new((cb_pts[0][0], cb_pts[0][1], cb_pts[0][2] - w * 0.5))
    v_m1 = bm_cb.verts.new((cb_pts[1][0], cb_pts[1][1], cb_pts[1][2] + w * 0.5))
    v_m2 = bm_cb.verts.new((cb_pts[1][0], cb_pts[1][1], cb_pts[1][2] - w * 0.5))
    v_r1 = bm_cb.verts.new((cb_pts[2][0], cb_pts[2][1], cb_pts[2][2] + w * 0.5))
    v_r2 = bm_cb.verts.new((cb_pts[2][0], cb_pts[2][1], cb_pts[2][2] - w * 0.5))
    bm_cb.faces.new((v_l1, v_m1, v_m2, v_l2))
    bm_cb.faces.new((v_m1, v_r1, v_r2, v_m2))
    bmesh.ops.solidify(bm_cb, geom=bm_cb.faces[:], thickness=0.0035)
    parts.append(create_cape_rigid_component("Cape_Travel_01_FastenerBand", bm_cb, gold, "J_Bip_C_UpperChest"))

    # 3. Draping Cape Body (At back +Y, smoothly skinned across UpperChest -> Chest -> Spine -> Hips)
    bm_cape = bmesh.new()
    n_rows = 16
    n_cols = 18
    grid = []
    
    # Profile coordinates: (Z, Y_center, half_width)
    # Calibrated to gracefully clear full iron backplate (py ~ 0.142) and rear skirt (py ~ 0.180)
    profile = [
        (1.445, 0.155, 0.155),
        (1.360, 0.178, 0.180),
        (1.250, 0.198, 0.208),
        (1.140, 0.215, 0.238),
        (1.000, 0.222, 0.268),
        (0.850, 0.215, 0.298),
        (0.720, 0.205, 0.322),
        (0.600, 0.188, 0.345),
    ]
    
    for r in range(n_rows):
        t = r / (n_rows - 1)
        idx = t * (len(profile) - 1)
        i0 = int(idx)
        i1 = min(i0 + 1, len(profile) - 1)
        f = idx - i0
        z = profile[i0][0] * (1.0 - f) + profile[i1][0] * f
        y_base = profile[i0][1] * (1.0 - f) + profile[i1][1] * f
        width = profile[i0][2] * (1.0 - f) + profile[i1][2] * f
        
        row = []
        for c in range(n_cols):
            u = c / (n_cols - 1)
            x = (u - 0.5) * 2.0 * width
            fold_wave = math.sin(u * math.pi * 4.0) * (0.007 + 0.018 * t)
            center_dip = (1.0 - 4.0 * (u - 0.5)**2) * (0.005 + 0.012 * t)
            y = y_base + fold_wave + center_dip
            row.append(bm_cape.verts.new((x, y, z)))
        grid.append(row)

    for r in range(n_rows - 1):
        for c in range(n_cols - 1):
            bm_cape.faces.new((grid[r][c], grid[r + 1][c], grid[r + 1][c + 1], grid[r][c + 1]))

    bmesh.ops.solidify(bm_cape, geom=bm_cape.faces[:], thickness=0.004)
    male_cape_anchors = [
        (1.380, "J_Bip_C_UpperChest"),
        (1.260, "J_Bip_C_Chest"),
        (1.150, "J_Bip_C_Spine"),
        (1.000, "J_Bip_C_Hips"),
    ]
    parts.append(create_spine_skinned_cape_component("Cape_Travel_01_Main", bm_cape, mat, male_cape_anchors))

    return parts


def make_cape_folds(armature: bpy.types.Object, mat: bpy.types.Material) -> list[bpy.types.Object]:
    del armature, mat
    return []





# =========================================================================
# 5. Shared Weapons, Scabbards, Back Holsters & Shields
# =========================================================================

def create_bone_rigid_component(
    name: str,
    bm: bmesh.types.BMesh,
    comp_mat: bpy.types.Material,
    bone_name: str,
    slot: str,
    visual_id: str,
    armature: bpy.types.Object,
) -> bpy.types.Object:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name + "Mesh")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if comp_mat:
        obj.data.materials.append(comp_mat)
    for p in obj.data.polygons:
        p.use_smooth = True
    vg = obj.vertex_groups.new(name=bone_name)
    vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    mod = obj.modifiers.new("WorldgoingArmature", "ARMATURE")
    mod.object = armature
    obj.parent = armature
    obj.matrix_parent_inverse = armature.matrix_world.inverted()
    component_props(obj, slot, visual_id)
    return obj


def create_spine_skinned_component(
    name: str,
    bm: bmesh.types.BMesh,
    comp_mat: bpy.types.Material,
    z_anchors: list[tuple[float, str]],
    slot: str,
    visual_id: str,
    armature: bpy.types.Object,
) -> bpy.types.Object:
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name + "Mesh")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if comp_mat:
        obj.data.materials.append(comp_mat)
    for p in obj.data.polygons:
        p.use_smooth = True

    vgs = {bone_name: obj.vertex_groups.new(name=bone_name) for _, bone_name in z_anchors}
    for v_idx, v in enumerate(obj.data.vertices):
        vz = v.co.z
        if vz >= z_anchors[0][0]:
            vgs[z_anchors[0][1]].add([v_idx], 1.0, "REPLACE")
        elif vz <= z_anchors[-1][0]:
            vgs[z_anchors[-1][1]].add([v_idx], 1.0, "REPLACE")
        else:
            for i in range(len(z_anchors) - 1):
                z_hi, bone_hi = z_anchors[i]
                z_lo, bone_lo = z_anchors[i + 1]
                if z_lo <= vz <= z_hi:
                    weight_hi = (vz - z_lo) / max(z_hi - z_lo, 0.001)
                    weight_lo = 1.0 - weight_hi
                    if weight_hi > 0.001:
                        vgs[bone_hi].add([v_idx], weight_hi, "REPLACE")
                    if weight_lo > 0.001:
                        vgs[bone_lo].add([v_idx], weight_lo, "REPLACE")
                    break

    mod = obj.modifiers.new("WorldgoingArmature", "ARMATURE")
    mod.object = armature
    obj.parent = armature
    obj.matrix_parent_inverse = armature.matrix_world.inverted()
    component_props(obj, slot, visual_id)
    return obj


def make_longsword(
    armature: bpy.types.Object,
    steel: bpy.types.Material,
    grip: bpy.types.Material,
    gold: bpy.types.Material,
    leather: bpy.types.Material,
) -> list[bpy.types.Object]:
    parts: list[bpy.types.Object] = []
    visual_id = "longsword_01"
    db_rh = armature.data.bones.get("J_Bip_R_Hand")
    p_palm = (db_rh.matrix_local @ Vector((0.0, 0.045, -0.015, 1.0))).xyz
    hx, hy, hz = p_palm.x, p_palm.y, p_palm.z

    # Hand Components (Drawn in combat)
    def create_hand_weapon(name: str, bm: bmesh.types.BMesh, comp_mat: bpy.types.Material) -> bpy.types.Object:
        rot_mat = Matrix.Rotation(math.radians(90), 3, 'X')
        center = Vector((hx, hy, hz))
        for v in bm.verts:
            rel = v.co - center
            v.co = center + rot_mat @ rel
        return create_bone_rigid_component(name, bm, comp_mat, "J_Bip_R_Hand", "weapon", visual_id, armature)

    bm_pommel = bmesh.new()
    res_p = bmesh.ops.create_cone(bm_pommel, cap_ends=True, cap_tris=False, segments=12, radius1=0.015, radius2=0.015, depth=0.010)
    for v in res_p["verts"]:
        v.co.x += hx; v.co.y += hy; v.co.z += hz - 0.050
    parts.append(create_hand_weapon("Weapon_Longsword_01_Pommel", bm_pommel, gold))

    bm_grip = bmesh.new()
    res_g = bmesh.ops.create_cone(bm_grip, cap_ends=True, cap_tris=False, segments=10, radius1=0.010, radius2=0.010, depth=0.10)
    for v in res_g["verts"]:
        v.co.x += hx; v.co.y += hy; v.co.z += hz
    parts.append(create_hand_weapon("Weapon_Longsword_01_Grip", bm_grip, grip))

    bm_guard = bmesh.new()
    res_gd = bmesh.ops.create_cube(bm_guard, size=1.0)
    for v in res_gd["verts"]:
        v.co.x *= 0.020; v.co.y *= 0.160; v.co.z *= 0.014
        v.co.x += hx; v.co.y += hy; v.co.z += hz + 0.055
    bmesh.ops.bevel(bm_guard, geom=bm_guard.edges[:], offset=0.003, segments=1)
    parts.append(create_hand_weapon("Weapon_Longsword_01_Guard", bm_guard, gold))

    bm_blade = bmesh.new()
    blade_len = 0.680
    b_base_z = hz + 0.065
    b_tip_z = b_base_z + blade_len
    n_blade_rows = 12
    grid_b = []
    for r in range(n_blade_rows):
        t = r / (n_blade_rows - 1)
        z = b_base_z * (1.0 - t) + b_tip_z * t
        hw = 0.020 * (1.0 - 0.25 * t) if t < 0.88 else 0.020 * 0.75 * (1.0 - (t - 0.88) / 0.12)
        t_mid = 0.0035 * (1.0 - 0.3 * t)
        row = [
            bm_blade.verts.new((hx, hy - hw, z)),
            bm_blade.verts.new((hx - t_mid, hy, z)),
            bm_blade.verts.new((hx, hy + hw, z)),
            bm_blade.verts.new((hx + t_mid, hy, z)),
        ]
        grid_b.append(row)
    v_tip = bm_blade.verts.new((hx, hy, b_tip_z + 0.015))
    for r in range(n_blade_rows - 1):
        for j in range(4):
            j_next = (j + 1) % 4
            bm_blade.faces.new((grid_b[r][j], grid_b[r + 1][j], grid_b[r + 1][j_next], grid_b[r][j_next]))
    for j in range(4):
        j_next = (j + 1) % 4
        bm_blade.faces.new((grid_b[-1][j], v_tip, grid_b[-1][j_next]))
    parts.append(create_hand_weapon("Weapon_Longsword_01_Blade", bm_blade, steel))

    # Scabbard Components on Left Hip (J_Bip_C_Hips)
    scab_top = Vector((0.170, -0.020, 0.950))
    scab_tip = Vector((0.190, 0.030, 0.320))
    scab_dir = (scab_tip - scab_top).normalized()
    rot_q = Vector((0,0,1)).rotation_difference(scab_dir)
    p_side_u = Vector((-scab_dir.y, scab_dir.x, 0)).normalized()
    p_thick_u = scab_dir.cross(p_side_u).normalized()

    # 1. Scabbard Leather Body
    bm_body = bmesh.new()
    n_rows = 10
    grid_scab = []
    for r in range(n_rows):
        t = r / (n_rows - 1)
        center = scab_top * (1.0 - t) + scab_tip * t
        w = 0.024 * (1.0 - 0.22 * t)
        th = 0.011 * (1.0 - 0.22 * t)
        p_side = p_side_u * w
        p_thick = p_thick_u * th
        row = [
            bm_body.verts.new(center - p_side - p_thick),
            bm_body.verts.new(center + p_side - p_thick),
            bm_body.verts.new(center + p_side + p_thick),
            bm_body.verts.new(center - p_side + p_thick),
        ]
        grid_scab.append(row)
    for r in range(n_rows - 1):
        for j in range(4):
            j_next = (j + 1) % 4
            bm_body.faces.new((grid_scab[r][j], grid_scab[r+1][j], grid_scab[r+1][j_next], grid_scab[r][j_next]))
    v_tip_scab = bm_body.verts.new(scab_tip + scab_dir * 0.02)
    for j in range(4):
        j_next = (j + 1) % 4
        bm_body.faces.new((grid_scab[-1][j], v_tip_scab, grid_scab[-1][j_next]))
    parts.append(create_bone_rigid_component("Weapon_Longsword_01_Scabbard_Body", bm_body, leather, "J_Bip_C_Hips", "weapon", visual_id, armature))

    # 2. Golden Fitted Scabbard Throat Collar (Conforming sleeve around the mouth)
    bm_throat = bmesh.new()
    n_th_rows = 4
    grid_th = []
    for r in range(n_th_rows):
        t = r / (n_th_rows - 1)
        c_th = scab_top + scab_dir * (0.038 * t)
        w_th = 0.026
        th_th = 0.013
        row = [
            bm_throat.verts.new(c_th - p_side_u * w_th - p_thick_u * th_th),
            bm_throat.verts.new(c_th + p_side_u * w_th - p_thick_u * th_th),
            bm_throat.verts.new(c_th + p_side_u * w_th + p_thick_u * th_th),
            bm_throat.verts.new(c_th - p_side_u * w_th + p_thick_u * th_th),
        ]
        grid_th.append(row)
    for r in range(n_th_rows - 1):
        for j in range(4):
            j_next = (j + 1) % 4
            bm_throat.faces.new((grid_th[r][j], grid_th[r+1][j], grid_th[r+1][j_next], grid_th[r][j_next]))
    parts.append(create_bone_rigid_component("Weapon_Longsword_01_Scabbard_Throat", bm_throat, gold, "J_Bip_C_Hips", "weapon", visual_id, armature))

    # 3. Golden Scabbard Chape (End cap at bottom)
    bm_chape = bmesh.new()
    res_ch = bmesh.ops.create_cone(bm_chape, cap_ends=True, cap_tris=False, segments=8, radius1=0.018, radius2=0.004, depth=0.050)
    bmesh.ops.rotate(bm_chape, cent=(0,0,0), matrix=rot_q.to_matrix(), verts=bm_chape.verts)
    for v in bm_chape.verts:
        v.co += scab_tip + scab_dir * 0.01
    parts.append(create_bone_rigid_component("Weapon_Longsword_01_Scabbard_Chape", bm_chape, gold, "J_Bip_C_Hips", "weapon", visual_id, armature))

    # 4. Sheathed Sword Guard (Sleek elegant crossguard aligned flush with scabbard mouth)
    bm_sh_gd = bmesh.new()
    c_gd = scab_top - scab_dir * 0.007
    gd_w = 0.040
    gd_th = 0.013
    gd_h = 0.007
    gd_pts_top = [
        c_gd - scab_dir * gd_h - p_side_u * gd_w - p_thick_u * gd_th,
        c_gd - scab_dir * gd_h + p_side_u * gd_w - p_thick_u * gd_th,
        c_gd - scab_dir * gd_h + p_side_u * gd_w + p_thick_u * gd_th,
        c_gd - scab_dir * gd_h - p_side_u * gd_w + p_thick_u * gd_th,
    ]
    gd_pts_bot = [
        c_gd + scab_dir * gd_h - p_side_u * (gd_w * 0.88) - p_thick_u * (gd_th * 0.88),
        c_gd + scab_dir * gd_h + p_side_u * (gd_w * 0.88) - p_thick_u * (gd_th * 0.88),
        c_gd + scab_dir * gd_h + p_side_u * (gd_w * 0.88) + p_thick_u * (gd_th * 0.88),
        c_gd + scab_dir * gd_h - p_side_u * (gd_w * 0.88) + p_thick_u * (gd_th * 0.88),
    ]
    v_top = [bm_sh_gd.verts.new(p) for p in gd_pts_top]
    v_bot = [bm_sh_gd.verts.new(p) for p in gd_pts_bot]
    bm_sh_gd.faces.new(v_top)
    bm_sh_gd.faces.new(list(reversed(v_bot)))
    for j in range(4):
        j_next = (j + 1) % 4
        bm_sh_gd.faces.new((v_bot[j], v_bot[j_next], v_top[j_next], v_top[j]))
    parts.append(create_bone_rigid_component("Weapon_Longsword_01_Sheathed_Guard", bm_sh_gd, gold, "J_Bip_C_Hips", "weapon", visual_id, armature))

    # 5. Sheathed Sword Grip (Extending up along -scab_dir)
    bm_hilt = bmesh.new()
    res_hg = bmesh.ops.create_cone(bm_hilt, cap_ends=True, cap_tris=False, segments=10, radius1=0.010, radius2=0.010, depth=0.10)
    bmesh.ops.rotate(bm_hilt, cent=(0,0,0), matrix=rot_q.to_matrix(), verts=bm_hilt.verts)
    for v in bm_hilt.verts:
        v.co += scab_top - scab_dir * 0.065
    parts.append(create_bone_rigid_component("Weapon_Longsword_01_Sheathed_Grip", bm_hilt, grip, "J_Bip_C_Hips", "weapon", visual_id, armature))

    # 6. Sheathed Sword Pommel (Capping the grip)
    bm_sh_pommel = bmesh.new()
    res_shp = bmesh.ops.create_cone(bm_sh_pommel, cap_ends=True, cap_tris=False, segments=10, radius1=0.014, radius2=0.014, depth=0.012)
    bmesh.ops.rotate(bm_sh_pommel, cent=(0,0,0), matrix=rot_q.to_matrix(), verts=bm_sh_pommel.verts)
    for v in bm_sh_pommel.verts:
        v.co += scab_top - scab_dir * 0.120
    parts.append(create_bone_rigid_component("Weapon_Longsword_01_Sheathed_Pommel", bm_sh_pommel, gold, "J_Bip_C_Hips", "weapon", visual_id, armature))

    return parts


def make_spear(
    armature: bpy.types.Object,
    wood: bpy.types.Material,
    steel: bpy.types.Material,
    gold: bpy.types.Material,
    tassel: bpy.types.Material,
) -> list[bpy.types.Object]:
    parts: list[bpy.types.Object] = []
    visual_id = "spear_01"
    db_rh = armature.data.bones.get("J_Bip_R_Hand")
    p_palm = (db_rh.matrix_local @ Vector((0.0, 0.045, -0.015, 1.0))).xyz
    hx, hy, hz = p_palm.x, p_palm.y, p_palm.z

    # Hand Components
    def create_spear_comp(name: str, bm: bmesh.types.BMesh, comp_mat: bpy.types.Material) -> bpy.types.Object:
        rot_mat = Matrix.Rotation(math.radians(90), 3, 'X')
        center = Vector((hx, hy, hz))
        for v in bm.verts:
            rel = v.co - center
            v.co = center + rot_mat @ rel
        return create_bone_rigid_component(name, bm, comp_mat, "J_Bip_R_Hand", "weapon", visual_id, armature)

    bm_shaft = bmesh.new()
    res_s = bmesh.ops.create_cone(bm_shaft, cap_ends=True, cap_tris=False, segments=12, radius1=0.012, radius2=0.012, depth=1.90)
    for v in res_s["verts"]:
        v.co.x += hx; v.co.y += hy; v.co.z += hz + 0.55
    parts.append(create_spear_comp("Weapon_Spear_01_Shaft", bm_shaft, wood))

    bm_head = bmesh.new()
    res_h = bmesh.ops.create_cone(bm_head, cap_ends=True, cap_tris=False, segments=4, radius1=0.030, radius2=0.002, depth=0.30)
    for v in res_h["verts"]:
        v.co.x += hx; v.co.y += hy; v.co.z += hz + 1.65
    parts.append(create_spear_comp("Weapon_Spear_01_Head", bm_head, steel))

    bm_col = bmesh.new()
    res_c = bmesh.ops.create_cone(bm_col, cap_ends=True, cap_tris=False, segments=12, radius1=0.016, radius2=0.013, depth=0.07)
    for v in res_c["verts"]:
        v.co.x += hx; v.co.y += hy; v.co.z += hz + 1.48
    parts.append(create_spear_comp("Weapon_Spear_01_Collar", bm_col, gold))

    bm_tas = bmesh.new()
    res_t = bmesh.ops.create_cone(bm_tas, cap_ends=True, cap_tris=False, segments=10, radius1=0.024, radius2=0.015, depth=0.09)
    for v in res_t["verts"]:
        v.co.x += hx; v.co.y += hy; v.co.z += hz + 1.42
    parts.append(create_spear_comp("Weapon_Spear_01_Tassel", bm_tas, tassel))

    # Holstered Back Components (J_Bip_C_UpperChest)
    p_top = Vector((-0.18, 0.14, 1.58))
    p_bot = Vector((0.20, 0.16, 0.60))
    s_dir = (p_bot - p_top).normalized()
    rot_q = Vector((0,0,1)).rotation_difference(s_dir)

    bm_h_shaft = bmesh.new()
    res_hs = bmesh.ops.create_cone(bm_h_shaft, cap_ends=True, cap_tris=False, segments=10, radius1=0.012, radius2=0.012, depth=1.95)
    bmesh.ops.rotate(bm_h_shaft, cent=(0,0,0), matrix=rot_q.to_matrix(), verts=bm_h_shaft.verts)
    center = (p_top + p_bot) * 0.5
    for v in bm_h_shaft.verts:
        v.co += center
    parts.append(create_bone_rigid_component("Weapon_Spear_01_Holstered_Shaft", bm_h_shaft, wood, "J_Bip_C_UpperChest", "weapon", visual_id, armature))

    bm_h_head = bmesh.new()
    res_hh = bmesh.ops.create_cone(bm_h_head, cap_ends=True, cap_tris=False, segments=4, radius1=0.030, radius2=0.002, depth=0.30)
    bmesh.ops.rotate(bm_h_head, cent=(0,0,0), matrix=rot_q.to_matrix(), verts=bm_h_head.verts)
    for v in bm_h_head.verts:
        v.co += p_top - s_dir * 0.15
    parts.append(create_bone_rigid_component("Weapon_Spear_01_Holstered_Head", bm_h_head, steel, "J_Bip_C_UpperChest", "weapon", visual_id, armature))

    bm_h_tas = bmesh.new()
    res_ht = bmesh.ops.create_cone(bm_h_tas, cap_ends=True, cap_tris=False, segments=8, radius1=0.022, radius2=0.014, depth=0.08)
    bmesh.ops.rotate(bm_h_tas, cent=(0,0,0), matrix=rot_q.to_matrix(), verts=bm_h_tas.verts)
    for v in bm_h_tas.verts:
        v.co += p_top - s_dir * 0.02
    parts.append(create_bone_rigid_component("Weapon_Spear_01_Holstered_Tassel", bm_h_tas, tassel, "J_Bip_C_UpperChest", "weapon", visual_id, armature))

    return parts


def make_axe(
    armature: bpy.types.Object,
    wood: bpy.types.Material,
    steel: bpy.types.Material,
    gold: bpy.types.Material,
    grip: bpy.types.Material,
) -> list[bpy.types.Object]:
    parts: list[bpy.types.Object] = []
    visual_id = "axe_01"
    db_rh = armature.data.bones.get("J_Bip_R_Hand")
    p_palm = (db_rh.matrix_local @ Vector((0.0, 0.045, -0.015, 1.0))).xyz
    hx, hy, hz = p_palm.x, p_palm.y, p_palm.z

    # Hand Components
    def create_axe_comp(name: str, bm: bmesh.types.BMesh, comp_mat: bpy.types.Material) -> bpy.types.Object:
        rot_mat = Matrix.Rotation(math.radians(90), 3, 'X')
        center = Vector((hx, hy, hz))
        for v in bm.verts:
            rel = v.co - center
            v.co = center + rot_mat @ rel
        return create_bone_rigid_component(name, bm, comp_mat, "J_Bip_R_Hand", "weapon", visual_id, armature)

    bm_haft = bmesh.new()
    res_h = bmesh.ops.create_cone(bm_haft, cap_ends=True, cap_tris=False, segments=12, radius1=0.013, radius2=0.013, depth=0.76)
    for v in res_h["verts"]:
        v.co.x += hx; v.co.y += hy; v.co.z += hz + 0.20
    parts.append(create_axe_comp("Weapon_Axe_01_Haft", bm_haft, wood))

    bm_g = bmesh.new()
    res_g = bmesh.ops.create_cone(bm_g, cap_ends=True, cap_tris=False, segments=12, radius1=0.015, radius2=0.015, depth=0.18)
    for v in res_g["verts"]:
        v.co.x += hx; v.co.y += hy; v.co.z += hz
    parts.append(create_axe_comp("Weapon_Axe_01_Grip", bm_g, grip))

    bm_b = bmesh.new()
    b_n = 10
    blade_pts = []
    for i in range(b_n):
        t = i / (b_n - 1)
        bz = (hz + 0.35) * (1.0 - t) + (hz + 0.62) * t
        reach = math.sin(t * math.pi) * 0.20 + 0.04
        by = hy - reach
        blade_pts.append((by, bz))
    v_blade_l = [bm_b.verts.new((hx - 0.003, pt[0], pt[1])) for pt in blade_pts]
    v_blade_r = [bm_b.verts.new((hx + 0.003, pt[0], pt[1])) for pt in blade_pts]
    v_socket_l = [bm_b.verts.new((hx - 0.013, hy, pt[1])) for pt in blade_pts]
    v_socket_r = [bm_b.verts.new((hx + 0.013, hy, pt[1])) for pt in blade_pts]
    for i in range(b_n - 1):
        bm_b.faces.new((v_socket_l[i], v_blade_l[i], v_blade_l[i+1], v_socket_l[i+1]))
        bm_b.faces.new((v_socket_r[i+1], v_blade_r[i+1], v_blade_r[i], v_socket_r[i]))
        bm_b.faces.new((v_blade_l[i], v_blade_r[i], v_blade_r[i+1], v_blade_l[i+1]))
        bm_b.faces.new((v_socket_r[i], v_socket_l[i], v_socket_l[i+1], v_socket_r[i+1]))
    parts.append(create_axe_comp("Weapon_Axe_01_Blade", bm_b, steel))

    # Holstered Back Components (J_Bip_C_UpperChest)
    p_top = Vector((-0.14, 0.14, 1.48))
    p_bot = Vector((0.10, 0.15, 0.78))
    a_dir = (p_bot - p_top).normalized()
    rot_q = Vector((0,0,1)).rotation_difference(a_dir)

    bm_h_haft = bmesh.new()
    res_hh = bmesh.ops.create_cone(bm_h_haft, cap_ends=True, cap_tris=False, segments=10, radius1=0.013, radius2=0.013, depth=0.78)
    bmesh.ops.rotate(bm_h_haft, cent=(0,0,0), matrix=rot_q.to_matrix(), verts=bm_h_haft.verts)
    center = (p_top + p_bot) * 0.5
    for v in bm_h_haft.verts:
        v.co += center
    parts.append(create_bone_rigid_component("Weapon_Axe_01_Holstered_Haft", bm_h_haft, wood, "J_Bip_C_UpperChest", "weapon", visual_id, armature))

    bm_hb = bmesh.new()
    b_n = 8
    hblade_pts = []
    for i in range(b_n):
        t = i / (b_n - 1)
        bz = (1.24) * (1.0 - t) + (1.50) * t
        reach = math.sin(t * math.pi) * 0.17 + 0.03
        by = 0.16 + reach
        hblade_pts.append((by, bz))
    vh_blade_l = [bm_hb.verts.new((-0.14 - 0.003, pt[0], pt[1])) for pt in hblade_pts]
    vh_blade_r = [bm_hb.verts.new((-0.14 + 0.003, pt[0], pt[1])) for pt in hblade_pts]
    vh_socket_l = [bm_hb.verts.new((-0.14 - 0.013, 0.15, pt[1])) for pt in hblade_pts]
    vh_socket_r = [bm_hb.verts.new((-0.14 + 0.013, 0.15, pt[1])) for pt in hblade_pts]
    for i in range(b_n - 1):
        bm_hb.faces.new((vh_socket_l[i], vh_blade_l[i], vh_blade_l[i+1], vh_socket_l[i+1]))
        bm_hb.faces.new((vh_socket_r[i+1], vh_blade_r[i+1], vh_blade_r[i], vh_socket_r[i]))
        bm_hb.faces.new((vh_blade_l[i], vh_blade_r[i], vh_blade_r[i+1], vh_blade_l[i+1]))
        bm_hb.faces.new((vh_socket_r[i], vh_socket_l[i], vh_socket_l[i+1], v_socket_r_next := vh_socket_r[i+1]))
    parts.append(create_bone_rigid_component("Weapon_Axe_01_Holstered_Blade", bm_hb, steel, "J_Bip_C_UpperChest", "weapon", visual_id, armature))

    return parts


def make_hammer(
    armature: bpy.types.Object,
    wood: bpy.types.Material,
    steel: bpy.types.Material,
    gold: bpy.types.Material,
    grip: bpy.types.Material,
) -> list[bpy.types.Object]:
    parts: list[bpy.types.Object] = []
    visual_id = "hammer_01"
    db_rh = armature.data.bones.get("J_Bip_R_Hand")
    p_palm = (db_rh.matrix_local @ Vector((0.0, 0.045, -0.015, 1.0))).xyz
    hx, hy, hz = p_palm.x, p_palm.y, p_palm.z

    # Hand Components
    def create_ham_comp(name: str, bm: bmesh.types.BMesh, comp_mat: bpy.types.Material) -> bpy.types.Object:
        rot_mat = Matrix.Rotation(math.radians(90), 3, 'X')
        center = Vector((hx, hy, hz))
        for v in bm.verts:
            rel = v.co - center
            v.co = center + rot_mat @ rel
        return create_bone_rigid_component(name, bm, comp_mat, "J_Bip_R_Hand", "weapon", visual_id, armature)

    bm_haft = bmesh.new()
    res_h = bmesh.ops.create_cone(bm_haft, cap_ends=True, cap_tris=False, segments=12, radius1=0.013, radius2=0.013, depth=0.74)
    for v in res_h["verts"]:
        v.co.x += hx; v.co.y += hy; v.co.z += hz + 0.18
    parts.append(create_ham_comp("Weapon_Hammer_01_Haft", bm_haft, wood))

    bm_head = bmesh.new()
    res_hd = bmesh.ops.create_cube(bm_head, size=1.0)
    for v in res_hd["verts"]:
        v.co.x *= 0.060; v.co.y *= 0.150; v.co.z *= 0.060
        v.co.x += hx; v.co.y += hy - 0.04; v.co.z += hz + 0.48
    bmesh.ops.bevel(bm_head, geom=bm_head.edges[:], offset=0.008, segments=2)
    parts.append(create_ham_comp("Weapon_Hammer_01_Head", bm_head, steel))

    # Holstered Back Components (J_Bip_C_UpperChest)
    p_top = Vector((-0.14, 0.14, 1.45))
    p_bot = Vector((0.08, 0.15, 0.76))
    h_dir = (p_bot - p_top).normalized()
    rot_q = Vector((0,0,1)).rotation_difference(h_dir)

    bm_h_haft = bmesh.new()
    res_hh = bmesh.ops.create_cone(bm_h_haft, cap_ends=True, cap_tris=False, segments=10, radius1=0.013, radius2=0.013, depth=0.76)
    bmesh.ops.rotate(bm_h_haft, cent=(0,0,0), matrix=rot_q.to_matrix(), verts=bm_h_haft.verts)
    center = (p_top + p_bot) * 0.5
    for v in bm_h_haft.verts:
        v.co += center
    parts.append(create_bone_rigid_component("Weapon_Hammer_01_Holstered_Haft", bm_h_haft, wood, "J_Bip_C_UpperChest", "weapon", visual_id, armature))

    bm_h_head = bmesh.new()
    res_hhd = bmesh.ops.create_cube(bm_h_head, size=1.0)
    for v in res_hhd["verts"]:
        v.co.x *= 0.060; v.co.y *= 0.140; v.co.z *= 0.060
        v.co += p_top
    bmesh.ops.bevel(bm_h_head, geom=bm_h_head.edges[:], offset=0.006, segments=1)
    parts.append(create_bone_rigid_component("Weapon_Hammer_01_Holstered_Head", bm_h_head, steel, "J_Bip_C_UpperChest", "weapon", visual_id, armature))

    return parts


def make_dagger(
    armature: bpy.types.Object,
    steel: bpy.types.Material,
    gold: bpy.types.Material,
    grip: bpy.types.Material,
) -> list[bpy.types.Object]:
    parts: list[bpy.types.Object] = []
    visual_id = "dagger_01"
    db_rh = armature.data.bones.get("J_Bip_R_Hand")
    p_palm = (db_rh.matrix_local @ Vector((0.0, 0.045, -0.015, 1.0))).xyz
    hx, hy, hz = p_palm.x, p_palm.y, p_palm.z

    # Hand Components
    def create_dag_comp(name: str, bm: bmesh.types.BMesh, comp_mat: bpy.types.Material) -> bpy.types.Object:
        rot_mat = Matrix.Rotation(math.radians(90), 3, 'X')
        center = Vector((hx, hy, hz))
        for v in bm.verts:
            rel = v.co - center
            v.co = center + rot_mat @ rel
        return create_bone_rigid_component(name, bm, comp_mat, "J_Bip_R_Hand", "weapon", visual_id, armature)

    bm_dp = bmesh.new()
    res_p = bmesh.ops.create_icosphere(bm_dp, subdivisions=1, radius=0.012)
    for v in res_p["verts"]:
        v.co.x += hx; v.co.y += hy; v.co.z += hz - 0.060
    parts.append(create_dag_comp("Weapon_Dagger_01_Pommel", bm_dp, gold))

    bm_dg = bmesh.new()
    res_g = bmesh.ops.create_cone(bm_dg, cap_ends=True, cap_tris=False, segments=10, radius1=0.010, radius2=0.010, depth=0.11)
    for v in res_g["verts"]:
        v.co.x += hx; v.co.y += hy; v.co.z += hz
    parts.append(create_dag_comp("Weapon_Dagger_01_Grip", bm_dg, grip))

    bm_dblade = bmesh.new()
    res_b = bmesh.ops.create_cone(bm_dblade, cap_ends=True, cap_tris=False, segments=4, radius1=0.018, radius2=0.002, depth=0.30)
    for v in res_b["verts"]:
        v.co.x += hx; v.co.y += hy; v.co.z += hz + 0.22
    parts.append(create_dag_comp("Weapon_Dagger_01_Blade", bm_dblade, steel))

    # Holstered Belt Components (J_Bip_C_Hips)
    d_center = Vector((0.0, 0.12, 0.94))
    bm_scab = bmesh.new()
    res_s = bmesh.ops.create_cone(bm_scab, cap_ends=True, cap_tris=False, segments=8, radius1=0.018, radius2=0.006, depth=0.22)
    bmesh.ops.rotate(bm_scab, cent=(0,0,0), matrix=Matrix.Rotation(math.radians(90), 3, 'Y'), verts=bm_scab.verts)
    for v in bm_scab.verts:
        v.co += d_center + Vector((0.04, 0, 0))
    parts.append(create_bone_rigid_component("Weapon_Dagger_01_Holstered_Sheath", bm_scab, grip, "J_Bip_C_Hips", "weapon", visual_id, armature))

    bm_hgrip = bmesh.new()
    res_hg = bmesh.ops.create_cone(bm_hgrip, cap_ends=True, cap_tris=False, segments=8, radius1=0.010, radius2=0.010, depth=0.10)
    bmesh.ops.rotate(bm_hgrip, cent=(0,0,0), matrix=Matrix.Rotation(math.radians(90), 3, 'Y'), verts=bm_hgrip.verts)
    for v in bm_hgrip.verts:
        v.co += d_center - Vector((0.11, 0, 0))
    parts.append(create_bone_rigid_component("Weapon_Dagger_01_Holstered_Grip", bm_hgrip, grip, "J_Bip_C_Hips", "weapon", visual_id, armature))

    return parts


def make_bow(
    armature: bpy.types.Object,
    wood: bpy.types.Material,
    gold: bpy.types.Material,
    grip: bpy.types.Material,
    string_mat: bpy.types.Material,
) -> list[bpy.types.Object]:
    parts: list[bpy.types.Object] = []
    visual_id = "bow_01"
    db_lh = armature.data.bones.get("J_Bip_L_Hand")
    M_lh_rest = db_lh.matrix_local

    # Hand Components
    def create_bow_comp(name: str, bm: bmesh.types.BMesh, comp_mat: bpy.types.Material) -> bpy.types.Object:
        return create_bone_rigid_component(name, bm, comp_mat, "J_Bip_L_Hand", "weapon", visual_id, armature)

    bm_bow = bmesh.new()
    n_bow = 21
    pts_bow = []
    for i in range(n_bow):
        t = i / (n_bow - 1)
        xl = -0.58 * (1.0 - t) + 0.58 * t
        curve = math.cos((t - 0.5) * math.pi) * 0.09
        yl = curve - 0.02
        pts_bow.append((xl, yl))
    grid_bow = []
    for xl, yl in pts_bow:
        v_local = [
            Vector((xl, yl - 0.010, -0.008, 1.0)),
            Vector((xl, yl - 0.010, 0.008, 1.0)),
            Vector((xl, yl + 0.010, 0.008, 1.0)),
            Vector((xl, yl + 0.010, -0.008, 1.0)),
        ]
        grid_bow.append([bm_bow.verts.new((M_lh_rest @ v).xyz) for v in v_local])
    for i in range(n_bow - 1):
        for j in range(4):
            j_next = (j + 1) % 4
            bm_bow.faces.new((grid_bow[i][j], grid_bow[i+1][j], grid_bow[i+1][j_next], grid_bow[i][j_next]))
    parts.append(create_bow_comp("Weapon_Bow_01_Limbs", bm_bow, wood))

    bm_grp = bmesh.new()
    n_grp = 5
    grid_grp = []
    for i in range(n_grp):
        t = i / (n_grp - 1)
        xl = -0.06 * (1.0 - t) + 0.06 * t
        curve = math.cos((t - 0.5) * math.pi) * 0.09
        yl = curve - 0.02
        v_local = [
            Vector((xl, yl - 0.012, -0.010, 1.0)),
            Vector((xl, yl - 0.012, 0.010, 1.0)),
            Vector((xl, yl + 0.012, 0.010, 1.0)),
            Vector((xl, yl + 0.012, -0.010, 1.0)),
        ]
        grid_grp.append([bm_grp.verts.new((M_lh_rest @ v).xyz) for v in v_local])
    for i in range(n_grp - 1):
        for j in range(4):
            j_next = (j + 1) % 4
            bm_grp.faces.new((grid_grp[i][j], grid_grp[i+1][j], grid_grp[i+1][j_next], grid_grp[i][j_next]))
    parts.append(create_bow_comp("Weapon_Bow_01_Grip", bm_grp, grip))

    bm_str = bmesh.new()
    p_bot_arm = (M_lh_rest @ Vector((-0.57, -0.02, 0.0, 1.0))).xyz
    p_top_arm = (M_lh_rest @ Vector((0.57, -0.02, 0.0, 1.0))).xyz
    res_str = bmesh.ops.create_cone(bm_str, cap_ends=True, cap_tris=False, segments=8, radius1=0.003, radius2=0.003, depth=(p_top_arm - p_bot_arm).length)
    mid_arm = (p_top_arm + p_bot_arm) * 0.5
    str_dir = (p_top_arm - p_bot_arm).normalized()
    R_str = Vector((0, 0, 1)).rotation_difference(str_dir).to_matrix().to_4x4()
    R_str.translation = mid_arm
    bmesh.ops.transform(bm_str, matrix=R_str, verts=res_str["verts"])
    parts.append(create_bow_comp("Weapon_Bow_01_String", bm_str, string_mat))

    # Holstered Back Components (J_Bip_C_UpperChest)
    p_top = Vector((0.18, 0.13, 1.45))
    p_bot = Vector((-0.18, 0.15, 0.60))
    bm_h_bow = bmesh.new()
    pts_h_bow = []
    for i in range(n_bow):
        t = i / (n_bow - 1)
        pos = p_top * (1.0 - t) + p_bot * t
        curve = math.cos((t - 0.5) * math.pi) * 0.08
        pos.y += curve
        pts_h_bow.append(pos)
    grid_h_bow = []
    for pt in pts_h_bow:
        row = [
            bm_h_bow.verts.new((pt.x - 0.007, pt.y, pt.z)),
            bm_h_bow.verts.new((pt.x, pt.y - 0.008, pt.z)),
            bm_h_bow.verts.new((pt.x + 0.007, pt.y, pt.z)),
            bm_h_bow.verts.new((pt.x, pt.y + 0.008, pt.z)),
        ]
        grid_h_bow.append(row)
    for i in range(n_bow - 1):
        for j in range(4):
            j_next = (j + 1) % 4
            bm_h_bow.faces.new((grid_h_bow[i][j], grid_h_bow[i+1][j], grid_h_bow[i+1][j_next], grid_h_bow[i][j_next]))
    parts.append(create_bone_rigid_component("Weapon_Bow_01_Holstered_Limbs", bm_h_bow, wood, "J_Bip_C_UpperChest", "weapon", visual_id, armature))

    return parts


def make_crossbow(
    armature: bpy.types.Object,
    wood: bpy.types.Material,
    steel: bpy.types.Material,
    gold: bpy.types.Material,
    string_mat: bpy.types.Material,
) -> list[bpy.types.Object]:
    parts: list[bpy.types.Object] = []
    visual_id = "crossbow_01"
    db_rh = armature.data.bones.get("J_Bip_R_Hand")
    p_palm = (db_rh.matrix_local @ Vector((0.0, 0.045, -0.015, 1.0))).xyz
    hx, hy, hz = p_palm.x, p_palm.y, p_palm.z

    # Hand Components
    def create_cb_comp(name: str, bm: bmesh.types.BMesh, comp_mat: bpy.types.Material) -> bpy.types.Object:
        return create_bone_rigid_component(name, bm, comp_mat, "J_Bip_R_Hand", "weapon", visual_id, armature)

    bm_cbs = bmesh.new()
    res_s = bmesh.ops.create_cube(bm_cbs, size=1.0)
    for v in res_s["verts"]:
        v.co.x *= 0.035; v.co.y *= 0.580; v.co.z *= 0.045
        v.co.x += hx; v.co.y += hy - 0.10; v.co.z += hz
    parts.append(create_cb_comp("Weapon_Crossbow_01_Stock", bm_cbs, wood))

    bm_cbp = bmesh.new()
    res_p = bmesh.ops.create_cube(bm_cbp, size=1.0)
    for v in res_p["verts"]:
        v.co.x *= 0.022; v.co.y *= 0.022; v.co.z *= 0.480
        v.co.x += hx; v.co.y += hy - 0.38; v.co.z += hz + 0.015
    parts.append(create_cb_comp("Weapon_Crossbow_01_Prod", bm_cbp, steel))

    # Holstered Back Components (J_Bip_C_UpperChest)
    hbx, hby, hbz = 0.0, 0.15, 1.20
    bm_h_cbs = bmesh.new()
    res_hs = bmesh.ops.create_cube(bm_h_cbs, size=1.0)
    for v in res_hs["verts"]:
        v.co.x *= 0.035; v.co.y *= 0.045; v.co.z *= 0.560
        v.co += Vector((hbx, hby, hbz))
    parts.append(create_bone_rigid_component("Weapon_Crossbow_01_Holstered_Stock", bm_h_cbs, wood, "J_Bip_C_UpperChest", "weapon", visual_id, armature))

    bm_h_cbp = bmesh.new()
    res_hp = bmesh.ops.create_cube(bm_h_cbp, size=1.0)
    for v in res_hp["verts"]:
        v.co.x *= 0.460; v.co.y *= 0.022; v.co.z *= 0.022
        v.co += Vector((hbx, hby + 0.02, hbz + 0.20))
    parts.append(create_bone_rigid_component("Weapon_Crossbow_01_Holstered_Prod", bm_h_cbp, steel, "J_Bip_C_UpperChest", "weapon", visual_id, armature))

    return parts


def make_shield(
    armature: bpy.types.Object,
    shield_mat: bpy.types.Material,
    gold: bpy.types.Material,
    silver: bpy.types.Material,
    leather: bpy.types.Material,
) -> list[bpy.types.Object]:
    """Create authentic forward-facing heater shield strapped firmly to the left forearm (J_Bip_L_LowerArm) and holstered on back."""
    parts: list[bpy.types.Object] = []
    visual_id = "shield_heater_01"
    
    db_la = armature.data.bones.get("J_Bip_L_LowerArm")
    bone_mat = armature.matrix_world @ db_la.matrix_local

    def create_shield_comp(name: str, bm: bmesh.types.BMesh, comp_mat: bpy.types.Material) -> bpy.types.Object:
        for v in bm.verts:
            v.co = bone_mat @ v.co
        return create_bone_rigid_component(name, bm, comp_mat, "J_Bip_L_LowerArm", "shield", visual_id, armature)

    shield_h = 0.580
    shield_w = 0.400
    bow_radius = 0.400
    n_rows = 16
    n_cols = 14
    y_mid = 0.125

    grid_local = []
    for r in range(n_rows):
        t_v = r / (n_rows - 1)
        cur_x = (shield_h * 0.45) * (1.0 - t_v) + (-shield_h * 0.55) * t_v
        half_w = shield_w * 0.5 if t_v < 0.38 else (shield_w * 0.5) * math.sqrt(max(0.0, 1.0 - ((t_v - 0.38) / 0.62)**1.5))
        row = []
        for c in range(n_cols):
            u_h = (c / (n_cols - 1) - 0.5) * 2.0
            local_y = y_mid + u_h * half_w
            local_z = 0.058 + (math.sqrt(max(0.001, bow_radius**2 - (u_h * shield_w * 0.5)**2)) - bow_radius)
            row.append(Vector((cur_x, local_y, local_z)))
        grid_local.append(row)

    # 1. Main Field
    bm_field = bmesh.new()
    grid_verts = [[bm_field.verts.new(grid_local[r][c]) for c in range(n_cols)] for r in range(n_rows)]
    for r in range(n_rows - 1):
        for c in range(n_cols - 1):
            bm_field.faces.new((grid_verts[r][c], grid_verts[r + 1][c], grid_verts[r + 1][c + 1], grid_verts[r][c + 1]))
    bmesh.ops.solidify(bm_field, geom=bm_field.faces[:], thickness=0.010)
    parts.append(create_shield_comp("Shield_Heater_01_Field", bm_field, shield_mat))

    # 2. Gold Border Rim
    bm_rim = bmesh.new()
    perimeter_coords = []
    for c in range(n_cols):
        perimeter_coords.append(grid_local[0][c])
    for r in range(1, n_rows):
        perimeter_coords.append(grid_local[r][-1])
    for c in range(n_cols - 2, -1, -1):
        perimeter_coords.append(grid_local[-1][c])
    for r in range(n_rows - 2, 0, -1):
        perimeter_coords.append(grid_local[r][0])

    rim_outer = []
    rim_inner = []
    for co in perimeter_coords:
        to_center = Vector((0.0, y_mid, 0.058)) - co
        to_center.z = 0.0
        inward = to_center.normalized() if to_center.length > 0 else Vector((0, 0, 0))
        v_out = bm_rim.verts.new((co.x - inward.x * 0.006, co.y - inward.y * 0.006, co.z + 0.004))
        v_in = bm_rim.verts.new((co.x + inward.x * 0.016, co.y + inward.y * 0.016, co.z + 0.003))
        rim_outer.append(v_out)
        rim_inner.append(v_in)
    n_rim = len(perimeter_coords)
    for i in range(n_rim):
        i_next = (i + 1) % n_rim
        bm_rim.faces.new((rim_outer[i], rim_outer[i_next], rim_inner[i_next], rim_inner[i]))
    bmesh.ops.solidify(bm_rim, geom=bm_rim.faces[:], thickness=0.008)
    parts.append(create_shield_comp("Shield_Heater_01_Border", bm_rim, gold))

    # 3. Golden Cross (Horizontal & Vertical)
    bm_cross_h = bmesh.new()
    bmesh.ops.create_cube(bm_cross_h, size=1.0)
    for v in bm_cross_h.verts:
        v.co.x *= 0.040; v.co.y *= 0.220; v.co.z *= 0.006
        v.co.x += 0.028; v.co.y += y_mid; v.co.z += 0.062
    bmesh.ops.bevel(bm_cross_h, geom=bm_cross_h.edges[:], offset=0.003, segments=1)
    parts.append(create_shield_comp("Shield_Heater_01_Cross_H", bm_cross_h, gold))

    bm_cross_v = bmesh.new()
    bmesh.ops.create_cube(bm_cross_v, size=1.0)
    for v in bm_cross_v.verts:
        v.co.x *= 0.280; v.co.y *= 0.040; v.co.z *= 0.006
        v.co.x += 0.028; v.co.y += y_mid; v.co.z += 0.062
    bmesh.ops.bevel(bm_cross_v, geom=bm_cross_v.edges[:], offset=0.003, segments=1)
    parts.append(create_shield_comp("Shield_Heater_01_Cross_V", bm_cross_v, gold))

    # 4. Center Boss Diamond
    bm_boss = bmesh.new()
    bmesh.ops.create_cube(bm_boss, size=1.0)
    for v in bm_boss.verts:
        v.co.x *= 0.058; v.co.y *= 0.058; v.co.z *= 0.012
        v.co.x += 0.028; v.co.y += y_mid; v.co.z += 0.067
    bmesh.ops.rotate(bm_boss, cent=(0.028, y_mid, 0.067), matrix=Matrix.Rotation(math.radians(45), 3, 'Z'), verts=bm_boss.verts)
    bmesh.ops.bevel(bm_boss, geom=bm_boss.edges[:], offset=0.004, segments=1)
    parts.append(create_shield_comp("Shield_Heater_01_Boss", bm_boss, silver))

    # 5. Inner Arm Straps & Handle
    bm_strap = bmesh.new()
    bmesh.ops.create_cone(bm_strap, cap_ends=False, segments=12, radius1=0.035, radius2=0.035, depth=0.038)
    bmesh.ops.rotate(bm_strap, cent=(0,0,0), matrix=Matrix.Rotation(math.radians(90), 3, 'X'), verts=bm_strap.verts)
    for v in bm_strap.verts:
        v.co.x += 0.0
        v.co.y += y_mid + 0.04
        v.co.z += 0.022
    parts.append(create_shield_comp("Shield_Heater_01_Strap", bm_strap, leather))

    # 6. Holstered Back Shield (Spine-skinned matching cape anchors)
    male_cape_anchors = [
        (1.380, "J_Bip_C_UpperChest"),
        (1.260, "J_Bip_C_Chest"),
        (1.150, "J_Bip_C_Spine"),
        (1.000, "J_Bip_C_Hips"),
    ]
    grid_back = []
    for r in range(n_rows):
        t_v = r / (n_rows - 1)
        z = (1.45) * (1.0 - t_v) + (0.90) * t_v
        half_w = shield_w * 0.5 if t_v < 0.38 else (shield_w * 0.5) * math.sqrt(max(0.0, 1.0 - ((t_v - 0.38) / 0.62)**1.5))
        y_base = 0.235 * (1.0 - t_v) + 0.295 * t_v
        row = []
        for c in range(n_cols):
            u_h = (c / (n_cols - 1) - 0.5) * 2.0
            x = u_h * half_w
            y = y_base + (1.0 - abs(u_h)) * 0.02
            row.append(Vector((x, y, z)))
        grid_back.append(row)

    bm_field_bk = bmesh.new()
    grid_verts_bk = [[bm_field_bk.verts.new(grid_back[r][c]) for c in range(n_cols)] for r in range(n_rows)]
    for r in range(n_rows - 1):
        for c in range(n_cols - 1):
            bm_field_bk.faces.new((grid_verts_bk[r][c], grid_verts_bk[r + 1][c], grid_verts_bk[r + 1][c + 1], grid_verts_bk[r][c + 1]))
    bmesh.ops.solidify(bm_field_bk, geom=bm_field_bk.faces[:], thickness=0.010)
    parts.append(create_spine_skinned_component("Shield_Heater_01_Holstered_Field", bm_field_bk, shield_mat, male_cape_anchors, "shield", visual_id, armature))

    bm_cross_bk = bmesh.new()
    bmesh.ops.create_cube(bm_cross_bk, size=1.0)
    for v in bm_cross_bk.verts:
        v.co.x *= 0.040; v.co.y *= 0.008; v.co.z *= 0.280
        v.co.x += 0.0; v.co.y += 0.292; v.co.z += 1.250
    parts.append(create_spine_skinned_component("Shield_Heater_01_Holstered_Cross_V", bm_cross_bk, gold, male_cape_anchors, "shield", visual_id, armature))

    bm_cross_hbk = bmesh.new()
    bmesh.ops.create_cube(bm_cross_hbk, size=1.0)
    for v in bm_cross_hbk.verts:
        v.co.x *= 0.220; v.co.y *= 0.008; v.co.z *= 0.040
        v.co.x += 0.0; v.co.y += 0.292; v.co.z += 1.250
    parts.append(create_spine_skinned_component("Shield_Heater_01_Holstered_Cross_H", bm_cross_hbk, gold, male_cape_anchors, "shield", visual_id, armature))

    return parts


def make_leather_helmet(
    armature: bpy.types.Object,
    leather: bpy.types.Material,
    leather_body: bpy.types.Material,
    leather_edge: bpy.types.Material,
    steel: bpy.types.Material,
    gold: bpy.types.Material,
) -> list[bpy.types.Object]:
    """Create authentic ornate Norman Spangenhelm / Combat Sallet in rich antique hardened leather matching reference image."""
    parts: list[bpy.types.Object] = []
    visual_id = "helmet_leather_01"

    head_bone = armature.data.bones.get("J_Bip_C_Head")
    head_pos = head_bone.head_local.copy()

    bm_dome = bmesh.new()
    bm_ridge = bmesh.new()
    bm_band = bmesh.new()
    bm_cheeks = bmesh.new()
    bm_emblem = bmesh.new()
    bm_rosettes = bmesh.new()
    bm_rivets = bmesh.new()
    bm_strap = bmesh.new()
    bm_buckle = bmesh.new()

    def add_rivet(bm: bmesh.types.BMesh, center: Vector, normal: Vector, radius: float = 0.0038, depth: float = 0.0030):
        z_axis = normal.normalized()
        up = Vector((0, 0, 1)) if abs(z_axis.z) < 0.9 else Vector((1, 0, 0))
        x_axis = z_axis.cross(up).normalized()
        y_axis = z_axis.cross(x_axis).normalized()
        
        n_segs = 8
        base_ring = []
        mid_ring = []
        for s in range(n_segs):
            a = s * 2.0 * math.pi / n_segs
            cos_a = math.cos(a)
            sin_a = math.sin(a)
            r_vec = (x_axis * cos_a + y_axis * sin_a)
            base_ring.append(bm.verts.new(center + r_vec * (radius * 1.15)))
            mid_ring.append(bm.verts.new(center + r_vec * radius + z_axis * (depth * 0.45)))
        apex = bm.verts.new(center + z_axis * depth)

        for s in range(n_segs):
            s_next = (s + 1) % n_segs
            bm.faces.new([base_ring[s], base_ring[s_next], mid_ring[s_next], mid_ring[s]])
            bm.faces.new([mid_ring[s], mid_ring[s_next], apex])

    def make_fleur_de_lis(bm: bmesh.types.BMesh, center: Vector, normal: Vector, up_dir: Vector, scale: float = 1.0):
        """Construct authentic 3D cast brass Fleur-de-lis emblem with faceted petals, collar, and base stud."""
        z_axis = normal.normalized()
        y_axis = (up_dir - z_axis * up_dir.dot(z_axis)).normalized()
        x_axis = y_axis.cross(z_axis).normalized()

        def tr(lx, ly, lz):
            return center + (x_axis * lx + y_axis * ly + z_axis * lz) * scale

        # Central Spear Petal (faceted lanceolate petal)
        c_apex = bm.verts.new(tr(0.0, 0.026, 0.0040))
        c_ridge_top = bm.verts.new(tr(0.0, 0.015, 0.0055))
        c_ridge_mid = bm.verts.new(tr(0.0, 0.005, 0.0050))
        c_ridge_bot = bm.verts.new(tr(0.0, -0.004, 0.0038))

        c_left_wide = bm.verts.new(tr(-0.0065, 0.013, 0.0025))
        c_left_mid = bm.verts.new(tr(-0.0055, 0.005, 0.0022))
        c_left_base = bm.verts.new(tr(-0.0030, -0.004, 0.0020))

        c_right_wide = bm.verts.new(tr(0.0065, 0.013, 0.0025))
        c_right_mid = bm.verts.new(tr(0.0055, 0.005, 0.0022))
        c_right_base = bm.verts.new(tr(0.0030, -0.004, 0.0020))

        bm.faces.new([c_apex, c_left_wide, c_ridge_top])
        bm.faces.new([c_apex, c_ridge_top, c_right_wide])
        bm.faces.new([c_ridge_top, c_left_wide, c_left_mid, c_ridge_mid])
        bm.faces.new([c_ridge_top, c_ridge_mid, c_right_mid, c_right_wide])
        bm.faces.new([c_ridge_mid, c_left_mid, c_left_base, c_ridge_bot])
        bm.faces.new([c_ridge_mid, c_ridge_bot, c_right_base, c_right_mid])

        # Left & Right Curled Outer Petals
        for side in [-1.0, 1.0]:
            sx = side
            p_hook_tip = bm.verts.new(tr(sx * 0.0135, 0.0015, 0.0028))
            p_crest_top = bm.verts.new(tr(sx * 0.0130, 0.0105, 0.0040))
            p_crest_mid = bm.verts.new(tr(sx * 0.0080, 0.0125, 0.0038))
            p_crest_base = bm.verts.new(tr(sx * 0.0038, 0.0045, 0.0032))
            p_root = bm.verts.new(tr(sx * 0.0032, -0.0035, 0.0024))

            p_inner_mid = bm.verts.new(tr(sx * 0.0075, 0.0065, 0.0024))
            p_outer_mid = bm.verts.new(tr(sx * 0.0150, 0.0075, 0.0020))

            if side == -1.0:
                bm.faces.new([p_crest_mid, p_crest_top, p_hook_tip, p_inner_mid])
                bm.faces.new([p_crest_mid, p_crest_base, p_root, p_inner_mid])
                bm.faces.new([p_crest_top, p_crest_mid, p_outer_mid])
                bm.faces.new([p_crest_top, p_outer_mid, p_hook_tip])
            else:
                bm.faces.new([p_crest_top, p_crest_mid, p_inner_mid, p_hook_tip])
                bm.faces.new([p_crest_base, p_crest_mid, p_inner_mid, p_root])
                bm.faces.new([p_crest_mid, p_crest_top, p_outer_mid])
                bm.faces.new([p_outer_mid, p_crest_top, p_hook_tip])

        # Horizontal Collar Clasp
        col_w = 0.010
        col_h = 0.0032
        col_d = 0.0045
        col_y = -0.0038
        bmesh.ops.create_cube(bm, size=1.0)
        for v in bm.verts[-8:]:
            v.co = center + (x_axis * (v.co.x * col_w * 2.0) +
                             y_axis * (col_y + v.co.y * col_h) +
                             z_axis * (0.0025 + v.co.z * col_d)) * scale

        # Lower Base Boss Stud
        add_rivet(bm, tr(0.0, -0.011, 0.0025), normal, radius=0.0036 * scale, depth=0.0028 * scale)

    def make_rosette(bm: bmesh.types.BMesh, center: Vector, normal: Vector, radius: float = 0.014):
        """Construct 8-pointed star / compass rose ear medallion with outer stepped bezel."""
        z_axis = normal.normalized()
        up = Vector((0, 0, 1)) if abs(z_axis.z) < 0.9 else Vector((1, 0, 0))
        x_axis = z_axis.cross(up).normalized()
        y_axis = z_axis.cross(x_axis).normalized()

        n_outer = 16
        outer_rim_verts = []
        inner_rim_verts = []
        for i in range(n_outer):
            a = i * 2.0 * math.pi / n_outer
            r_vec = x_axis * math.cos(a) + y_axis * math.sin(a)
            outer_rim_verts.append(bm.verts.new(center + r_vec * radius + z_axis * 0.0010))
            inner_rim_verts.append(bm.verts.new(center + r_vec * (radius * 0.82) + z_axis * 0.0022))

        for i in range(n_outer):
            i_next = (i + 1) % n_outer
            bm.faces.new([outer_rim_verts[i], outer_rim_verts[i_next], inner_rim_verts[i_next], inner_rim_verts[i]])

        star_tips = []
        n_star = 16
        for i in range(n_star):
            a = i * 2.0 * math.pi / n_star
            r_vec = x_axis * math.cos(a) + y_axis * math.sin(a)
            if i % 4 == 0:
                r_pt = radius * 0.76
                z_pt = 0.0036
            elif i % 2 == 0:
                r_pt = radius * 0.52
                z_pt = 0.0030
            else:
                r_pt = radius * 0.28
                z_pt = 0.0020
            star_tips.append(bm.verts.new(center + r_vec * r_pt + z_axis * z_pt))

        star_center = bm.verts.new(center + z_axis * 0.0042)
        for i in range(n_star):
            i_next = (i + 1) % n_star
            bm.faces.new([star_tips[i], star_tips[i_next], star_center])

        add_rivet(bm, center + z_axis * 0.0025, normal, radius=0.0036, depth=0.0028)

    def make_buckle(bm: bmesh.types.BMesh, center: Vector, normal: Vector, tangent: Vector, width: float = 0.009, height: float = 0.007, thickness: float = 0.0020):
        """Construct miniature rectangular antiqued brass roller buckle with center prong."""
        z_axis = normal.normalized()
        y_axis = tangent.normalized()
        x_axis = y_axis.cross(z_axis).normalized()

        hw = width * 0.5
        hh = height * 0.5
        beam_r = thickness * 0.5

        corners = [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)]
        frame_verts = [center + x_axis * cx + y_axis * cy for cx, cy in corners]

        for i in range(4):
            p0 = frame_verts[i]
            p1 = frame_verts[(i + 1) % 4]
            dir_beam = (p1 - p0).normalized()
            up_beam = dir_beam.cross(z_axis).normalized()
            v_bar = []
            for side in range(4):
                ang = side * math.pi * 0.5 + math.pi * 0.25
                off = (up_beam * math.cos(ang) + z_axis * math.sin(ang)) * beam_r
                v_bar.append((bm.verts.new(p0 + off), bm.verts.new(p1 + off)))
            for s in range(4):
                s_next = (s + 1) % 4
                bm.faces.new([v_bar[s][0], v_bar[s_next][0], v_bar[s_next][1], v_bar[s][1]])

        p_prong_base = center + y_axis * (-hh) + z_axis * 0.0005
        p_prong_tip = center + y_axis * (hh + 0.001) + z_axis * (beam_r + 0.0005)
        dir_p = (p_prong_tip - p_prong_base).normalized()
        side_p = dir_p.cross(z_axis).normalized()
        pr = 0.0008
        vp = []
        for side in range(4):
            ang = side * math.pi * 0.5 + math.pi * 0.25
            off = (side_p * math.cos(ang) + z_axis * math.sin(ang)) * pr
            vp.append((bm.verts.new(p_prong_base + off), bm.verts.new(p_prong_tip + off)))
        for s in range(4):
            s_next = (s + 1) % 4
            bm.faces.new([vp[s][0], vp[s_next][0], vp[s_next][1], vp[s][1]])

    # Dedicated high-fidelity antique leather materials matching reference image:
    # 1) Deep rich chestnut/chocolate antique leather for dome panels and cheek plates:
    mat_leather_dome = material("Worldgoing_Helmet_Leather_Dome", (0.040, 0.016, 0.006), roughness=0.52)
    # 2) Darker burnished espresso edge/rib leather for spangen ribs, brow band, and straps:
    mat_leather_trim = material("Worldgoing_Helmet_Leather_Trim", (0.018, 0.008, 0.003), roughness=0.48)
    # 3) Polished antique cast brass for Fleur-de-lis, star rosettes, rivets, and buckles:
    mat_brass = material("Worldgoing_Helmet_Brass", (0.95, 0.76, 0.22), metallic=0.96, roughness=0.20)

    # =========================================================================
    # 1. Spangenhelm 4-Panel Cranial Dome
    # =========================================================================
    n_lat = 16
    n_lon = 32
    z_apex = 0.238
    z_rim_base = 0.120

    rx_max = 0.124
    ry_front_max = 0.146
    ry_back_max = 0.124

    verts_grid = []
    for i in range(n_lat):
        v = i / (n_lat - 1)
        row = []
        pz_base = z_apex - (z_apex - z_rim_base) * (v ** 0.94)
        rad_profile = 0.0 if v == 0 else math.sin(v * math.pi * 0.5) ** 0.44

        for j in range(n_lon):
            angle = j * 2.0 * math.pi / n_lon
            cos_a = math.cos(angle)
            sin_a = math.sin(angle)

            # Polar orientation:
            # cos_a > 0 is FRONT (-Y)
            # cos_a < 0 is BACK (+Y)
            # sin_a > 0 is RIGHT (+X)
            # sin_a < 0 is LEFT (-X)
            rx = rx_max
            ry = ry_front_max if cos_a >= 0 else ry_back_max

            panel_dish = 0.0022 * (math.sin(angle * 2.0) ** 2) * math.sin(v * math.pi)
            r_mod = 1.0 + panel_dish

            px = sin_a * rx * rad_profile * r_mod
            py = -cos_a * ry * rad_profile * r_mod - 0.005
            pz = pz_base

            vert = bm_dome.verts.new(head_pos + Vector((px, py, pz)))
            row.append(vert)
        verts_grid.append(row)

    apex_vert = bm_dome.verts.new(head_pos + Vector((0, -0.003, z_apex + 0.002)))
    for j in range(n_lon):
        next_j = (j + 1) % n_lon
        bm_dome.faces.new([apex_vert, verts_grid[1][j], verts_grid[1][next_j]])

    for i in range(1, n_lat - 1):
        for j in range(n_lon):
            next_j = (j + 1) % n_lon
            bm_dome.faces.new([verts_grid[i][j], verts_grid[i + 1][j], verts_grid[i + 1][next_j], verts_grid[i][next_j]])

    bmesh.ops.recalc_face_normals(bm_dome, faces=bm_dome.faces)
    bmesh.ops.solidify(bm_dome, geom=bm_dome.faces[:], thickness=0.0036)

    # =========================================================================
    # 2. Spangen Cross-Ribs (Sagittal & Coronal Arched Stitched Ribs)
    # =========================================================================
    # 2A. Sagittal Arched Rib: from front brow (-Y), over apex (+Z), down to nape (+Y)
    n_sag = 28
    half_w_sag = 0.011
    ridge_h = 0.0035
    sag_l = []
    sag_r = []
    sag_top = []

    for i in range(n_sag):
        t = i / (n_sag - 1)
        ang = math.radians(-15.0 + 210.0 * t)
        cos_ang = math.cos(ang)
        sin_ang = math.sin(ang)

        ry = ry_front_max + 0.002 if cos_ang >= 0 else ry_back_max + 0.002
        rz = z_apex
        
        cy = -cos_ang * ry - 0.005
        cz = 0.125 + sin_ang * (rz - 0.125) if sin_ang >= 0 else 0.125 + sin_ang * 0.075
        
        n_dir = Vector((0, -cos_ang / ry, sin_ang / (rz - 0.125) if sin_ang >= 0 else -0.5)).normalized()
        
        pt_c = head_pos + Vector((0, cy, cz))
        pt_l = pt_c + Vector((-half_w_sag, 0, 0)) + n_dir * 0.0012
        pt_r = pt_c + Vector((half_w_sag, 0, 0)) + n_dir * 0.0012
        pt_top = pt_c + n_dir * ridge_h

        sag_l.append(bm_ridge.verts.new(pt_l))
        sag_r.append(bm_ridge.verts.new(pt_r))
        sag_top.append(bm_ridge.verts.new(pt_top))

    for i in range(n_sag - 1):
        bm_ridge.faces.new([sag_l[i], sag_l[i + 1], sag_top[i + 1], sag_top[i]])
        bm_ridge.faces.new([sag_top[i], sag_top[i + 1], sag_r[i + 1], sag_r[i]])

    # 2B. Coronal Arched Rib: from left ear (-X), over apex (+Z), down to right ear (+X)
    n_cor = 24
    half_w_cor = 0.010
    cor_f = []
    cor_b = []
    cor_top = []

    for i in range(n_cor):
        t = i / (n_cor - 1)
        ang = math.radians(10.0 + 160.0 * t)
        cos_ang = math.cos(ang)
        sin_ang = math.sin(ang)

        cx = -cos_ang * (rx_max + 0.003)
        cz = 0.120 + sin_ang * (z_apex - 0.120)
        cy = -0.004
        
        n_dir = Vector((-cos_ang, 0, sin_ang)).normalized()
        pt_c = head_pos + Vector((cx, cy, cz))
        pt_f = pt_c + Vector((0, -half_w_cor, 0)) + n_dir * 0.0012
        pt_b = pt_c + Vector((0, half_w_cor, 0)) + n_dir * 0.0012
        pt_top = pt_c + n_dir * ridge_h

        cor_f.append(bm_ridge.verts.new(pt_f))
        cor_b.append(bm_ridge.verts.new(pt_b))
        cor_top.append(bm_ridge.verts.new(pt_top))

    for i in range(n_cor - 1):
        bm_ridge.faces.new([cor_f[i], cor_f[i + 1], cor_top[i + 1], cor_top[i]])
        bm_ridge.faces.new([cor_top[i], cor_top[i + 1], cor_b[i + 1], cor_b[i]])

    bmesh.ops.solidify(bm_ridge, geom=bm_ridge.faces[:], thickness=0.0020)

    # Embossed leather fleur-de-lis on forehead crest:
    pt_crest_emb = head_pos + Vector((0, -ry_front_max * 0.98 - 0.008, 0.155))
    fleur_pts = [
        Vector((0, -0.004, 0.018)), Vector((-0.0055, -0.002, 0.009)), Vector((0, -0.003, 0.002)), Vector((0.0055, -0.002, 0.009))
    ]
    f_verts = [bm_ridge.verts.new(pt_crest_emb + p) for p in fleur_pts]
    bm_ridge.faces.new(f_verts)

    # =========================================================================
    # 3. Brow Band with Nasal Guard and Flared Nape Guard
    # =========================================================================
    n_band = 32
    band_lower = []
    band_upper = []
    
    for j in range(n_band):
        angle = j * 2.0 * math.pi / n_band
        cos_a = math.cos(angle)
        sin_a = math.sin(angle)

        rx = rx_max + 0.0035
        ry = (ry_front_max if cos_a >= 0 else ry_back_max) + 0.0035

        z_b_top = 0.128
        z_b_bot = 0.092

        # 3A. Raised brow arches above eyes on front face
        if cos_a > 0.35 and 0.18 < abs(sin_a) < 0.82:
            ocular_lift = 0.012 * math.sin((abs(sin_a) - 0.18) / 0.64 * math.pi)
            z_b_bot += ocular_lift

        # 3B. Central triangular nasal guard extending down nose bridge
        if cos_a > 0.70 and abs(sin_a) < 0.18:
            t_nasal = 1.0 - abs(sin_a) / 0.18
            z_b_bot -= 0.060 * (t_nasal ** 1.25)
            ry += 0.010 * t_nasal

        # 3C. Flared nape guard protecting back of neck
        if cos_a < -0.15:
            t_nape = (-cos_a - 0.15) / 0.85
            z_b_bot -= 0.080 * (t_nape ** 1.1)
            flare_dist = 0.020 * (t_nape ** 1.4)
            rx += flare_dist * 0.45
            ry += flare_dist

        pt_bot = head_pos + Vector((sin_a * rx, -cos_a * ry - 0.005, z_b_bot))
        pt_top = head_pos + Vector((sin_a * rx, -cos_a * ry - 0.005, z_b_top))

        band_lower.append(bm_band.verts.new(pt_bot))
        band_upper.append(bm_band.verts.new(pt_top))

    for j in range(n_band):
        next_j = (j + 1) % n_band
        bm_band.faces.new([band_lower[j], band_lower[next_j], band_upper[next_j], band_upper[j]])

    bmesh.ops.recalc_face_normals(bm_band, faces=bm_band.faces)
    bmesh.ops.solidify(bm_band, geom=bm_band.faces[:], thickness=0.0032)

    # =========================================================================
    # 4. Anatomical Cheek Guards with Tooled Scrollwork Relief
    # =========================================================================
    for side in [-1.0, 1.0]:
        sx = side
        p_top_back  = head_pos + Vector((sx * 0.114,  0.005,  0.092))
        p_top_mid   = head_pos + Vector((sx * 0.108, -0.052,  0.092))
        p_top_front = head_pos + Vector((sx * 0.098, -0.100,  0.092))

        p_mid_back   = head_pos + Vector((sx * 0.108, -0.005,  0.035))
        p_mid_center = head_pos + Vector((sx * 0.100, -0.062,  0.030))
        p_mid_front  = head_pos + Vector((sx * 0.088, -0.104,  0.022))

        p_low_back  = head_pos + Vector((sx * 0.096, -0.015, -0.030))
        p_low_mid   = head_pos + Vector((sx * 0.090, -0.070, -0.038))
        p_tip       = head_pos + Vector((sx * 0.080, -0.100, -0.050))

        c_grid = [
            [p_top_back, p_top_mid, p_top_front],
            [p_mid_back, p_mid_center, p_mid_front],
            [p_low_back, p_low_mid, p_tip],
        ]

        v_grid = []
        for row in c_grid:
            v_row = [bm_cheeks.verts.new(pt) for pt in row]
            v_grid.append(v_row)

        for r in range(2):
            for c in range(2):
                if side == 1.0:
                    bm_cheeks.faces.new([v_grid[r][c], v_grid[r + 1][c], v_grid[r + 1][c + 1], v_grid[r][c + 1]])
                else:
                    bm_cheeks.faces.new([v_grid[r][c], v_grid[r][c + 1], v_grid[r + 1][c + 1], v_grid[r + 1][c]])

        norm_cheek = Vector((sx * 0.88, -0.28, -0.10)).normalized()
        sc_center1 = p_mid_center + norm_cheek * 0.0025
        sc_center2 = p_low_mid + norm_cheek * 0.0025
        sc_pts = [
            sc_center1 + Vector((0,  0.012,  0.015)),
            sc_center1 + Vector((sx * 0.003, -0.005,  0.008)),
            sc_center1 + Vector((-sx * 0.002, -0.012, -0.006)),
            sc_center2 + Vector((sx * 0.002, -0.008,  0.005)),
            sc_center2 + Vector((0,  0.005, -0.008)),
        ]
        sc_v0 = [bm_cheeks.verts.new(pt - Vector((0, 0.0025, 0))) for pt in sc_pts]
        sc_v1 = [bm_cheeks.verts.new(pt + Vector((0, 0.0025, 0))) for pt in sc_pts]
        for idx in range(len(sc_pts) - 1):
            if side == 1.0:
                bm_cheeks.faces.new([sc_v0[idx], sc_v1[idx], sc_v1[idx + 1], sc_v0[idx + 1]])
            else:
                bm_cheeks.faces.new([sc_v0[idx], sc_v0[idx + 1], sc_v1[idx + 1], sc_v1[idx]])

    bmesh.ops.recalc_face_normals(bm_cheeks, faces=bm_cheeks.faces)
    bmesh.ops.solidify(bm_cheeks, geom=bm_cheeks.faces[:], thickness=0.0032)

    # =========================================================================
    # 5. 3D Cast Brass Fleur-de-lis Emblem (Front Brow Centerpiece)
    # =========================================================================
    emblem_center = head_pos + Vector((0, -ry_front_max - 0.015, 0.096))
    emblem_norm = Vector((0, -0.99, 0.10)).normalized()
    emblem_up = Vector((0, -0.10, 0.99)).normalized()
    make_fleur_de_lis(bm_emblem, emblem_center, emblem_norm, emblem_up, scale=1.45)
    bmesh.ops.recalc_face_normals(bm_emblem, faces=bm_emblem.faces)

    # =========================================================================
    # 6. Brass Ear Rosettes (Star Medallions)
    # =========================================================================
    for side in [-1.0, 1.0]:
        sx = side
        rosette_center = head_pos + Vector((sx * (rx_max + 0.010), 0.002, 0.096))
        rosette_norm = Vector((sx * 0.98, 0.05, 0.15)).normalized()
        make_rosette(bm_rosettes, rosette_center, rosette_norm, radius=0.017)
    bmesh.ops.recalc_face_normals(bm_rosettes, faces=bm_rosettes.faces)

    # =========================================================================
    # 7. Domed Antique Brass Rivets
    # =========================================================================
    add_rivet(bm_rivets, head_pos + Vector((0, -ry_front_max * 0.96 - 0.010, 0.170)), Vector((0, -0.92, 0.38)), radius=0.0045, depth=0.0035)

    for side in [-1.0, 1.0]:
        sx = side
        pt_r1 = head_pos + Vector((sx * 0.038, -ry_front_max * 0.99 - 0.012, 0.098))
        norm_r1 = Vector((sx * 0.32, -0.92, 0.15)).normalized()
        add_rivet(bm_rivets, pt_r1, norm_r1, radius=0.0042, depth=0.0032)

        pt_r2 = head_pos + Vector((sx * 0.076, -ry_front_max * 0.90 - 0.012, 0.102))
        norm_r2 = Vector((sx * 0.68, -0.70, 0.18)).normalized()
        add_rivet(bm_rivets, pt_r2, norm_r2, radius=0.0042, depth=0.0032)

        add_rivet(bm_rivets, head_pos + Vector((sx * 0.112, 0.000, 0.065)), Vector((sx * 0.95, -0.15, 0.0)), radius=0.0038, depth=0.0028)
        add_rivet(bm_rivets, head_pos + Vector((sx * 0.106, -0.012, 0.025)), Vector((sx * 0.95, -0.18, 0.0)), radius=0.0038, depth=0.0028)
        add_rivet(bm_rivets, head_pos + Vector((sx * 0.096, -0.022, -0.018)), Vector((sx * 0.94, -0.22, 0.0)), radius=0.0038, depth=0.0028)

        add_rivet(bm_rivets, head_pos + Vector((sx * 0.076, 0.000, 0.214)), Vector((sx * 0.72, 0.0, 0.68)), radius=0.0038, depth=0.0028)

        add_rivet(bm_rivets, head_pos + Vector((sx * 0.055, ry_back_max * 0.98 + 0.005, 0.055)), Vector((sx * 0.40, 0.90, 0.15)), radius=0.0038, depth=0.0028)
    bmesh.ops.recalc_face_normals(bm_rivets, faces=bm_rivets.faces)

    # =========================================================================
    # 8. Chin Strap & Rear Adjustment Strap
    # =========================================================================
    left_anchor = head_pos + Vector((-0.078, -0.068, -0.035))
    right_anchor = head_pos + Vector((0.078, -0.068, -0.035))
    chin_center = head_pos + Vector((0.0, -0.065, -0.058))

    strap_pts = []
    n_strap = 11
    for i in range(n_strap):
        t = i / (n_strap - 1)
        pt = ((1 - t) ** 2) * left_anchor + 2 * (1 - t) * t * chin_center + (t ** 2) * right_anchor
        strap_pts.append(pt)

    strap_w = 0.0065
    sv0 = []
    sv1 = []
    for i, pt in enumerate(strap_pts):
        tang = (strap_pts[min(i + 1, n_strap - 1)] - strap_pts[max(0, i - 1)]).normalized()
        norm = (pt - head_pos).normalized()
        binorm = tang.cross(norm).normalized()
        sv0.append(bm_strap.verts.new(pt - binorm * (strap_w * 0.5)))
        sv1.append(bm_strap.verts.new(pt + binorm * (strap_w * 0.5)))

    for i in range(n_strap - 1):
        bm_strap.faces.new([sv0[i], sv0[i + 1], sv1[i + 1], sv1[i]])

    rear_l = head_pos + Vector((-0.110, 0.010, 0.092))
    rear_r = head_pos + Vector((0.110, 0.010, 0.092))
    rear_mid = head_pos + Vector((0.0, ry_back_max + 0.008, 0.090))

    n_rstrap = 9
    r_pts = []
    for i in range(n_rstrap):
        t = i / (n_rstrap - 1)
        pt = ((1 - t) ** 2) * rear_l + 2 * (1 - t) * t * rear_mid + (t ** 2) * rear_r
        r_pts.append(pt)

    rv0 = []
    rv1 = []
    for i, pt in enumerate(r_pts):
        tang = (r_pts[min(i + 1, n_rstrap - 1)] - r_pts[max(0, i - 1)]).normalized()
        norm = (pt - head_pos).normalized()
        binorm = tang.cross(norm).normalized()
        rv0.append(bm_strap.verts.new(pt - binorm * 0.0045))
        rv1.append(bm_strap.verts.new(pt + binorm * 0.0045))

    for i in range(n_rstrap - 1):
        bm_strap.faces.new([rv0[i], rv0[i + 1], rv1[i + 1], rv1[i]])

    bmesh.ops.recalc_face_normals(bm_strap, faces=bm_strap.faces)
    bmesh.ops.solidify(bm_strap, geom=bm_strap.faces[:], thickness=0.0022)

    # =========================================================================
    # 9. Antiqued Brass Buckles
    # =========================================================================
    b_center = strap_pts[3]
    b_tang = (strap_pts[4] - strap_pts[2]).normalized()
    b_norm = (b_center - head_pos).normalized()
    make_buckle(bm_buckle, b_center, b_norm, b_tang, width=0.009, height=0.007, thickness=0.0020)

    rb_center = r_pts[2]
    rb_tang = (r_pts[3] - r_pts[1]).normalized()
    rb_norm = (rb_center - head_pos).normalized()
    make_buckle(bm_buckle, rb_center, rb_norm, rb_tang, width=0.0095, height=0.0075, thickness=0.0020)
    bmesh.ops.recalc_face_normals(bm_buckle, faces=bm_buckle.faces)

    parts.append(create_bone_rigid_component("Helmet_Leather_01_Dome", bm_dome, mat_leather_dome, "J_Bip_C_Head", "helmet", visual_id, armature))
    parts.append(create_bone_rigid_component("Helmet_Leather_01_Ridge", bm_ridge, mat_leather_trim, "J_Bip_C_Head", "helmet", visual_id, armature))
    parts.append(create_bone_rigid_component("Helmet_Leather_01_Band", bm_band, mat_leather_trim, "J_Bip_C_Head", "helmet", visual_id, armature))
    parts.append(create_bone_rigid_component("Helmet_Leather_01_CheekGuards", bm_cheeks, mat_leather_dome, "J_Bip_C_Head", "helmet", visual_id, armature))
    parts.append(create_bone_rigid_component("Helmet_Leather_01_Emblem", bm_emblem, mat_brass, "J_Bip_C_Head", "helmet", visual_id, armature))
    parts.append(create_bone_rigid_component("Helmet_Leather_01_Rosettes", bm_rosettes, mat_brass, "J_Bip_C_Head", "helmet", visual_id, armature))
    parts.append(create_bone_rigid_component("Helmet_Leather_01_Rivets", bm_rivets, mat_brass, "J_Bip_C_Head", "helmet", visual_id, armature))
    parts.append(create_bone_rigid_component("Helmet_Leather_01_Strap", bm_strap, mat_leather_trim, "J_Bip_C_Head", "helmet", visual_id, armature))
    parts.append(create_bone_rigid_component("Helmet_Leather_01_Buckle", bm_buckle, mat_brass, "J_Bip_C_Head", "helmet", visual_id, armature))

    return parts


def make_boots(
    source_raw_body: bpy.types.Object,
    armature: bpy.types.Object,
    leather_body: bpy.types.Material,
    leather_edge: bpy.types.Material,
    gold: bpy.types.Material,
) -> list[bpy.types.Object]:
    """Create authentic adventure leather boots extracted from native VRM shoes and calf topology."""
    del gold
    parts: list[bpy.types.Object] = []
    for side, sign in (("L", 1.0), ("R", -1.0)):
        # Main Boot (Foot + Calf Shaft up to clean edge loop at Z=0.418)
        obj_boot = copy_mesh(source_raw_body, f"Boots_Leather_01_Foot_{side}", "boots", "boots_leather_01")
        bm = bmesh.new()
        bm.from_mesh(obj_boot.data)
        bm.faces.ensure_lookup_table()

        delete_faces = []
        for f in bm.faces:
            center = f.calc_center_median()
            is_side = (center.x >= 0.0) if sign > 0 else (center.x <= 0.0)
            is_shoe = (f.material_index == 3 and center.z <= 0.120)
            is_shaft = (f.material_index == 2 and 0.060 <= center.z <= 0.418)
            if not (is_side and (is_shoe or is_shaft)):
                delete_faces.append(f)
        bmesh.ops.delete(bm, geom=delete_faces, context="FACES")

        # Outward offset of 0.0035 for leather boot thickness
        bm.normal_update()
        for v in bm.verts:
            if v.link_faces and v.normal.length > 0:
                v.co += v.normal.normalized() * 0.0035

        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(obj_boot.data)
        bm.free()
        obj_boot.data.update()
        obj_boot.data.materials.clear()
        obj_boot.data.materials.append(leather_body)
        for poly in obj_boot.data.polygons:
            poly.material_index = 0
            poly.use_smooth = True
        parts.append(obj_boot)

        # Boot Top Cuff (Trim at Z in [0.370, 0.418])
        obj_cuff = copy_mesh(source_raw_body, f"Boots_Leather_01_Cuff_{side}", "boots", "boots_leather_01")
        bm = bmesh.new()
        bm.from_mesh(obj_cuff.data)
        bm.faces.ensure_lookup_table()
        delete_faces = []
        for f in bm.faces:
            center = f.calc_center_median()
            is_side = (center.x >= 0.0) if sign > 0 else (center.x <= 0.0)
            is_cuff = (f.material_index == 2 and 0.370 <= center.z <= 0.418)
            if not (is_side and is_cuff):
                delete_faces.append(f)
        bmesh.ops.delete(bm, geom=delete_faces, context="FACES")
        bm.normal_update()
        for v in bm.verts:
            if v.link_faces and v.normal.length > 0:
                v.co += v.normal.normalized() * 0.0055
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(obj_cuff.data)
        bm.free()
        obj_cuff.data.update()
        obj_cuff.data.materials.clear()
        obj_cuff.data.materials.append(leather_edge)
        for poly in obj_cuff.data.polygons:
            poly.material_index = 0
            poly.use_smooth = True
        parts.append(obj_cuff)

        # Boot Ankle Strap (Trim at Z in [0.115, 0.145])
        obj_strap = copy_mesh(source_raw_body, f"Boots_Leather_01_Strap_{side}", "boots", "boots_leather_01")
        bm = bmesh.new()
        bm.from_mesh(obj_strap.data)
        bm.faces.ensure_lookup_table()
        delete_faces = []
        for f in bm.faces:
            center = f.calc_center_median()
            is_side = (center.x >= 0.0) if sign > 0 else (center.x <= 0.0)
            is_strap = (f.material_index == 2 and 0.115 <= center.z <= 0.145)
            if not (is_side and is_strap):
                delete_faces.append(f)
        bmesh.ops.delete(bm, geom=delete_faces, context="FACES")
        bm.normal_update()
        for v in bm.verts:
            if v.link_faces and v.normal.length > 0:
                v.co += v.normal.normalized() * 0.0055
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(obj_strap.data)
        bm.free()
        obj_strap.data.update()
        obj_strap.data.materials.clear()
        obj_strap.data.materials.append(leather_edge)
        for poly in obj_strap.data.polygons:
            poly.material_index = 0
            poly.use_smooth = True
        parts.append(obj_strap)

    return parts


def make_armor_details(
    source_raw_body: bpy.types.Object,
    armature: bpy.types.Object,
    leather: bpy.types.Material,
    leather_body: bpy.types.Material,
    leather_edge: bpy.types.Material,
    cloth: bpy.types.Material,
    steel: bpy.types.Material,
    gold: bpy.types.Material,
) -> list[bpy.types.Object]:
    parts: list[bpy.types.Object] = []
    visual_id = "armor_light_leather_01"

    def create_rigid_component(name: str, bm: bmesh.types.BMesh, mat: bpy.types.Material, bone: str) -> bpy.types.Object:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        mesh = bpy.data.meshes.new(name + "Mesh")
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        obj.data.materials.append(mat)
        for p in obj.data.polygons:
            p.use_smooth = True
        vg = obj.vertex_groups.new(name=bone)
        vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
        mod = obj.modifiers.new("WorldgoingArmature", "ARMATURE")
        mod.object = armature
        obj.parent = armature
        obj.matrix_parent_inverse = armature.matrix_world.inverted()
        component_props(obj, "armor", visual_id)
        return obj

    # 0. Adventurer Fitted Pants / Trousers (冒險者合身長褲，收納於皮靴內，保留100%動態骨骼權重)
    obj_pants = copy_mesh(source_raw_body, "Armor_Light_Leather_01_Pants", "armor", visual_id)
    bm = bmesh.new()
    bm.from_mesh(obj_pants.data)
    bm.faces.ensure_lookup_table()
    delete_faces = [f for f in bm.faces if f.material_index != 2 or not (0.300 <= f.calc_center_median().z <= 1.045)]
    bmesh.ops.delete(bm, geom=delete_faces, context="FACES")
    
    bmesh.ops.bisect_plane(
        bm,
        geom=bm.faces[:] + bm.edges[:] + bm.verts[:],
        plane_co=(0, 0, 0.320),
        plane_no=(0, 0, 1),
        clear_inner=True,
    )
    bmesh.ops.bisect_plane(
        bm,
        geom=bm.faces[:] + bm.edges[:] + bm.verts[:],
        plane_co=(0, 0, 1.035),
        plane_no=(0, 0, -1),
        clear_inner=True,
    )
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    for v in bm.verts:
        if v.normal.length > 0:
            v.co += v.normal.normalized() * 0.0025
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj_pants.data)
    bm.free()
    obj_pants.data.update()
    obj_pants.data.materials.clear()
    obj_pants.data.materials.append(cloth)
    for p in obj_pants.data.polygons:
        p.material_index = 0
        p.use_smooth = True
    parts.append(obj_pants)

    # 1. Adventurer Leather Jerkin / Vest (立領真皮背心，完整覆蓋胸腹與肩峰，法線偏移+0.0080m)
    obj_vest = copy_mesh(source_raw_body, "Armor_Light_Leather_01_Vest", "armor", visual_id)
    bm = bmesh.new()
    bm.from_mesh(obj_vest.data)
    bm.faces.ensure_lookup_table()
    
    delete_faces = [
        f for f in bm.faces
        if f.material_index != 0 or not (1.040 <= f.calc_center_median().z <= 1.480 and abs(f.calc_center_median().x) <= 0.220)
    ]
    bmesh.ops.delete(bm, geom=delete_faces, context="FACES")
    
    # Bisect bottom hem at Z = 1.072 (clean straight bottom hem above belt)
    bmesh.ops.bisect_plane(
        bm,
        geom=bm.faces[:] + bm.edges[:] + bm.verts[:],
        plane_co=(0, 0, 1.072),
        plane_no=(0, 0, 1),
        clear_inner=True,
    )
    # Bisect collar at Z = 1.445 (clean top collar line)
    bmesh.ops.bisect_plane(
        bm,
        geom=bm.faces[:] + bm.edges[:] + bm.verts[:],
        plane_co=(0, 0, 1.445),
        plane_no=(0, 0, -1),
        clear_inner=True,
    )
    
    # Bisect armholes cleanly at |X| = 0.185 (clean armhole loop covering entire shoulder joint)
    arm_faces = [f for f in bm.faces if f.calc_center_median().z >= 1.260]
    arm_geom = arm_faces + list(set(e for f in arm_faces for e in f.edges)) + list(set(v for f in arm_faces for v in f.verts))
    bmesh.ops.bisect_plane(
        bm,
        geom=arm_geom,
        plane_co=(0.185, 0, 1.350),
        plane_no=(-1, 0, 0),
        clear_inner=True,
    )
    arm_faces = [f for f in bm.faces if f.calc_center_median().z >= 1.260]
    arm_geom = arm_faces + list(set(e for f in arm_faces for e in f.edges)) + list(set(v for f in arm_faces for v in f.verts))
    bmesh.ops.bisect_plane(
        bm,
        geom=arm_geom,
        plane_co=(-0.185, 0, 1.350),
        plane_no=(1, 0, 0),
        clear_inner=True,
    )
    
    # Outward displacement of 0.0080m (8.0mm) for comfortable clearance over body skin
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    for v in bm.verts:
        if v.normal.length > 0:
            v.co += v.normal.normalized() * 0.0080
            
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj_vest.data)
    bm.free()
    obj_vest.data.update()
    obj_vest.data.materials.clear()
    obj_vest.data.materials.append(leather_body)
    for p in obj_vest.data.polygons:
        p.material_index = 0
        p.use_smooth = True
    parts.append(obj_vest)

    # 2. Stand Collar Trim (立領邊緣包邊，+0.0105m偏移)
    obj_collar = copy_mesh(source_raw_body, "Armor_Light_Leather_01_Collar", "armor", visual_id)
    bm = bmesh.new()
    bm.from_mesh(obj_collar.data)
    bm.faces.ensure_lookup_table()
    delete_faces = [
        f for f in bm.faces
        if f.material_index != 0 or not (1.385 <= f.calc_center_median().z <= 1.450 and abs(f.calc_center_median().x) <= 0.085)
    ]
    bmesh.ops.delete(bm, geom=delete_faces, context="FACES")
    bmesh.ops.bisect_plane(
        bm,
        geom=bm.faces[:] + bm.edges[:] + bm.verts[:],
        plane_co=(0, 0, 1.390),
        plane_no=(0, 0, 1),
        clear_inner=True,
    )
    bmesh.ops.bisect_plane(
        bm,
        geom=bm.faces[:] + bm.edges[:] + bm.verts[:],
        plane_co=(0, 0, 1.445),
        plane_no=(0, 0, -1),
        clear_inner=True,
    )
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    for v in bm.verts:
        if v.normal.length > 0:
            v.co += v.normal.normalized() * 0.0105
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj_collar.data)
    bm.free()
    obj_collar.data.update()
    obj_collar.data.materials.clear()
    obj_collar.data.materials.append(leather_edge)
    for p in obj_collar.data.polygons:
        p.material_index = 0
        p.use_smooth = True
    parts.append(obj_collar)

    # 3. Front Center Trim Seam
    bm_seam = bmesh.new()
    bmesh.ops.create_cube(bm_seam, size=1.0)
    for v in bm_seam.verts:
        v.co.x *= 0.008
        v.co.y *= 0.006
        v.co.z *= 0.320
        v.co.x += 0.0
        v.co.y += -0.118
        v.co.z += 1.250
    parts.append(create_rigid_component("Armor_Light_Leather_01_FrontSeam", bm_seam, leather_edge, "J_Bip_C_Chest"))

    # 4. Diagonal Baldric / Chest Cross-Strap & Buckle (斜跨皮帶與胸扣)
    bm_strap = bmesh.new()
    strap_pts = [
        (-0.095, -0.075, 1.410),
        (-0.065, -0.115, 1.345),
        (-0.020, -0.136, 1.260),
        ( 0.025, -0.132, 1.180),
        ( 0.070, -0.115, 1.100),
        ( 0.095, -0.080, 1.070),
    ]
    w = 0.018
    verts_strap = []
    for pt in strap_pts:
        v_l = bm_strap.verts.new((pt[0] - w * 0.7, pt[1] - 0.004, pt[2] + w * 0.7))
        v_r = bm_strap.verts.new((pt[0] + w * 0.7, pt[1] - 0.004, pt[2] - w * 0.7))
        verts_strap.append((v_l, v_r))
    for i in range(len(strap_pts) - 1):
        v1, v2 = verts_strap[i]
        v3, v4 = verts_strap[i + 1]
        bm_strap.faces.new((v1, v3, v4, v2))
    bmesh.ops.solidify(bm_strap, geom=bm_strap.faces[:], thickness=0.004)
    parts.append(create_rigid_component("Armor_Light_Leather_01_CrossStrap", bm_strap, leather, "J_Bip_C_Chest"))

    # Buckle on Chest Strap
    bm_buckle = bmesh.new()
    bmesh.ops.create_cube(bm_buckle, size=1.0)
    for v in bm_buckle.verts:
        v.co.x *= 0.038
        v.co.y *= 0.008
        v.co.z *= 0.028
        v.co.x += -0.045
        v.co.y += -0.134
        v.co.z += 1.310
    bmesh.ops.bevel(bm_buckle, geom=bm_buckle.edges[:], offset=0.003, segments=2)
    parts.append(create_rigid_component("Armor_Light_Leather_01_StrapBuckle", bm_buckle, steel, "J_Bip_C_Chest"))

    # 5. Conformal Curving Pauldrons (立體弧形真皮護肩，貼合肩部關節圓頂)
    for side, sign in (("L", 1.0), ("R", -1.0)):
        # Upper Pauldron Guard Dome
        bm_p1 = bmesh.new()
        n_lat, n_lon = 10, 10
        r_p1 = 0.065
        grid_p1 = []
        for i in range(n_lat):
            theta = (i / (n_lat - 1)) * (math.pi * 0.45)
            row = []
            for j in range(n_lon):
                phi = (j / (n_lon - 1) - 0.5) * math.pi * 0.90
                lx = sign * (math.sin(theta) * math.cos(phi) * 0.85) * r_p1
                ly = math.sin(theta) * math.sin(phi) * r_p1
                lz = math.cos(theta) * (r_p1 * 0.50)
                wx = sign * 0.175 + lx
                wy = -0.015 + ly
                wz = 1.415 + lz
                row.append(bm_p1.verts.new((wx, wy, wz)))
            grid_p1.append(row)
        for i in range(n_lat - 1):
            for j in range(n_lon - 1):
                bm_p1.faces.new((grid_p1[i][j], grid_p1[i + 1][j], grid_p1[i + 1][j + 1], grid_p1[i][j + 1]))
        bmesh.ops.solidify(bm_p1, geom=bm_p1.faces[:], thickness=0.0045)
        parts.append(create_rigid_component(f"Armor_Light_Leather_01_Pauldron_Upper_{side}", bm_p1, leather_body, f"J_Bip_{side}_UpperArm"))

        # Lower Pauldron Tier Guard
        bm_p2 = bmesh.new()
        r_p2 = 0.060
        grid_p2 = []
        for i in range(n_lat):
            theta = (i / (n_lat - 1)) * (math.pi * 0.45)
            row = []
            for j in range(n_lon):
                phi = (j / (n_lon - 1) - 0.5) * math.pi * 0.85
                lx = sign * (math.sin(theta) * math.cos(phi) * 0.85 + 0.015) * r_p2
                ly = math.sin(theta) * math.sin(phi) * r_p2
                lz = math.cos(theta) * (r_p2 * 0.45) - 0.016
                wx = sign * 0.175 + lx
                wy = -0.015 + ly
                wz = 1.415 + lz
                row.append(bm_p2.verts.new((wx, wy, wz)))
            grid_p2.append(row)
        for i in range(n_lat - 1):
            for j in range(n_lon - 1):
                bm_p2.faces.new((grid_p2[i][j], grid_p2[i + 1][j], grid_p2[i + 1][j + 1], grid_p2[i][j + 1]))
        bmesh.ops.solidify(bm_p2, geom=bm_p2.faces[:], thickness=0.004)
        parts.append(create_rigid_component(f"Armor_Light_Leather_01_Pauldron_Lower_{side}", bm_p2, leather_edge, f"J_Bip_{side}_UpperArm"))

        # Silver Rivets
        bm_riv = bmesh.new()
        for offset_y in (-0.025, 0.0, 0.025):
            bmesh.ops.create_icosphere(bm_riv, subdivisions=1, radius=0.0035)
            for v in bm_riv.verts[-12:]:
                v.co.x += sign * 0.175
                v.co.y += offset_y - 0.015
                v.co.z += 1.450
        parts.append(create_rigid_component(f"Armor_Light_Leather_01_Pauldron_Rivets_{side}", bm_riv, steel, f"J_Bip_{side}_UpperArm"))

    # 6. Conformal Forearm Bracers (貼身真皮護腕，保留動態骨骼權重)
    for side, sign in (("L", 1.0), ("R", -1.0)):
        obj_bracer = copy_mesh(source_raw_body, f"Armor_Light_Leather_01_Bracer_{side}", "armor", visual_id)
        bm = bmesh.new()
        bm.from_mesh(obj_bracer.data)
        bm.faces.ensure_lookup_table()
        delete_faces = [
            f for f in bm.faces
            if f.material_index != 0 or not (0.420 <= abs(f.calc_center_median().x) <= 0.590 and 1.320 <= f.calc_center_median().z <= 1.460 and ((f.calc_center_median().x >= 0) if sign > 0 else (f.calc_center_median().x <= 0)))
        ]
        bmesh.ops.delete(bm, geom=delete_faces, context="FACES")
        
        bmesh.ops.bisect_plane(
            bm,
            geom=bm.faces[:] + bm.edges[:] + bm.verts[:],
            plane_co=(sign * 0.440, 0, 0),
            plane_no=(sign * 1, 0, 0),
            clear_inner=True,
        )
        bmesh.ops.bisect_plane(
            bm,
            geom=bm.faces[:] + bm.edges[:] + bm.verts[:],
            plane_co=(sign * 0.570, 0, 0),
            plane_no=(sign * -1, 0, 0),
            clear_inner=True,
        )
        
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.normal_update()
        for v in bm.verts:
            if v.normal.length > 0:
                v.co += v.normal.normalized() * 0.0065
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(obj_bracer.data)
        bm.free()
        obj_bracer.data.update()
        obj_bracer.data.materials.clear()
        obj_bracer.data.materials.append(leather_body)
        for p in obj_bracer.data.polygons:
            p.material_index = 0
            p.use_smooth = True
        parts.append(obj_bracer)

        # Bracer Straps & Buckles
        obj_bstrap = copy_mesh(source_raw_body, f"Armor_Light_Leather_01_BracerStraps_{side}", "armor", visual_id)
        bm = bmesh.new()
        bm.from_mesh(obj_bstrap.data)
        bm.faces.ensure_lookup_table()
        delete_faces = [
            f for f in bm.faces
            if f.material_index != 0 or not (((0.455 <= abs(f.calc_center_median().x) <= 0.480) or (0.530 <= abs(f.calc_center_median().x) <= 0.555)) and 1.340 <= f.calc_center_median().z <= 1.440 and ((f.calc_center_median().x >= 0) if sign > 0 else (f.calc_center_median().x <= 0)))
        ]
        bmesh.ops.delete(bm, geom=delete_faces, context="FACES")
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.normal_update()
        for v in bm.verts:
            if v.normal.length > 0:
                v.co += v.normal.normalized() * 0.0085
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(obj_bstrap.data)
        bm.free()
        obj_bstrap.data.update()
        obj_bstrap.data.materials.clear()
        obj_bstrap.data.materials.append(leather_edge)
        for p in obj_bstrap.data.polygons:
            p.material_index = 0
            p.use_smooth = True
        parts.append(obj_bstrap)

    # 7. Adventurer Waist Belt & Hip Tassets (腰帶與戰裙皮甲片)
    obj_belt = copy_mesh(source_raw_body, "Armor_Light_Leather_01_WaistBand", "armor", visual_id)
    bm = bmesh.new()
    bm.from_mesh(obj_belt.data)
    bm.faces.ensure_lookup_table()
    delete_faces = [f for f in bm.faces if f.material_index != 2 or not (1.025 <= f.calc_center_median().z <= 1.080)]
    bmesh.ops.delete(bm, geom=delete_faces, context="FACES")
    bmesh.ops.bisect_plane(
        bm,
        geom=bm.faces[:] + bm.edges[:] + bm.verts[:],
        plane_co=(0, 0, 1.035),
        plane_no=(0, 0, 1),
        clear_inner=True,
    )
    bmesh.ops.bisect_plane(
        bm,
        geom=bm.faces[:] + bm.edges[:] + bm.verts[:],
        plane_co=(0, 0, 1.070),
        plane_no=(0, 0, -1),
        clear_inner=True,
    )
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.normal_update()
    for v in bm.verts:
        if v.normal.length > 0:
            v.co += v.normal.normalized() * 0.0065
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj_belt.data)
    bm.free()
    obj_belt.data.update()
    obj_belt.data.materials.clear()
    obj_belt.data.materials.append(leather_edge)
    for p in obj_belt.data.polygons:
        p.material_index = 0
        p.use_smooth = True
    parts.append(obj_belt)

    # Center Belt Buckle
    bm_bb = bmesh.new()
    bmesh.ops.create_cube(bm_bb, size=1.0)
    for v in bm_bb.verts:
        v.co.x *= 0.048
        v.co.y *= 0.012
        v.co.z *= 0.034
        v.co.x += 0.0
        v.co.y += -0.096
        v.co.z += 1.055
    bmesh.ops.bevel(bm_bb, geom=bm_bb.edges[:], offset=0.004, segments=2)
    parts.append(create_rigid_component("Armor_Light_Leather_01_BeltBuckle", bm_bb, gold, "J_Bip_C_Hips"))

    # Hip Tassets (4 hanging leather tasset flaps over hips, Z in [0.935, 1.035])
    for side, sign in (("L", 1.0), ("R", -1.0)):
        obj_tasset = copy_mesh(source_raw_body, f"Armor_Light_Leather_01_Tasset_{side}", "armor", visual_id)
        bm = bmesh.new()
        bm.from_mesh(obj_tasset.data)
        bm.faces.ensure_lookup_table()
        delete_faces = []
        for f in bm.faces:
            center = f.calc_center_median()
            is_side = (center.x >= 0.0) if sign > 0 else (center.x <= 0.0)
            is_flap = (f.material_index == 2 and 0.920 <= center.z <= 1.040 and abs(center.x) >= 0.035 and is_side)
            if not is_flap:
                delete_faces.append(f)
        bmesh.ops.delete(bm, geom=delete_faces, context="FACES")
        
        bmesh.ops.bisect_plane(
            bm,
            geom=bm.faces[:] + bm.edges[:] + bm.verts[:],
            plane_co=(0, 0, 0.935),
            plane_no=(0, 0, 1),
            clear_inner=True,
        )
        bmesh.ops.bisect_plane(
            bm,
            geom=bm.faces[:] + bm.edges[:] + bm.verts[:],
            plane_co=(0, 0, 1.035),
            plane_no=(0, 0, -1),
            clear_inner=True,
        )
        
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.normal_update()
        for v in bm.verts:
            if v.normal.length > 0:
                v.co += v.normal.normalized() * 0.0080
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(obj_tasset.data)
        bm.free()
        obj_tasset.data.update()
        obj_tasset.data.materials.clear()
        obj_tasset.data.materials.append(leather_body)
        for p in obj_tasset.data.polygons:
            p.material_index = 0
            p.use_smooth = True
        parts.append(obj_tasset)

        # Hanging Utility Pouch on Hips
        bm_pch = bmesh.new()
        bmesh.ops.create_cube(bm_pch, size=1.0)
        for v in bm_pch.verts:
            v.co.x *= 0.032
            v.co.y *= 0.052
            v.co.z *= 0.062
            v.co.x += sign * 0.148
            v.co.y += 0.005
            v.co.z += 0.970
        bmesh.ops.bevel(bm_pch, geom=bm_pch.edges[:], offset=0.005, segments=2)
        parts.append(create_rigid_component(f"Armor_Light_Leather_01_Pouch_{side}", bm_pch, leather, "J_Bip_C_Hips"))

    return parts


def add_scene_preview(mesh_objects: list[bpy.types.Object]) -> None:
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except (TypeError, ValueError):
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 640
    scene.render.resolution_y = 800
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.frame_start = FRAME_START
    scene.frame_end = FRAME_END
    scene.render.fps = 24
    if scene.world is None:
        scene.world = bpy.data.worlds.new("Worldgoing_CharacterPack_World")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    if background is not None:
        background.inputs["Color"].default_value = (0.035, 0.055, 0.075, 1.0)
        background.inputs["Strength"].default_value = 0.75

    ground_mat = material("Worldgoing_CharacterPack_Ground", (0.09, 0.13, 0.17), roughness=0.92)
    bpy.ops.mesh.primitive_plane_add(size=20.0, location=(0.0, 0.0, -0.012))
    ground = bpy.context.object
    ground.name = "PreviewGround"
    ground.data.materials.append(ground_mat)

    target = Vector((0.0, -0.02, 0.90))
    for name, location, energy, size, color in [
        ("Key", (3.0, -4.0, 3.8), 950.0, 3.0, (1.0, 0.88, 0.72)),
        ("Fill", (-3.0, -2.0, 2.4), 650.0, 4.0, (0.60, 0.76, 1.0)),
        ("Rim", (0.0, 3.6, 3.5), 1100.0, 2.8, (1.0, 0.92, 0.78)),
    ]:
        data = bpy.data.lights.new("Preview" + name + "Data", "AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        data.color = color
        light = bpy.data.objects.new("Preview" + name, data)
        bpy.context.scene.collection.objects.link(light)
        light.location = location
        light.rotation_euler = (target - light.location).to_track_quat("-Z", "Y").to_euler()

    def camera(name: str, location: tuple[float, float, float], output_name: str) -> None:
        data = bpy.data.cameras.new(name + "Data")
        data.type = "ORTHO"
        data.ortho_scale = 2.12
        cam = bpy.data.objects.new(name, data)
        scene.collection.objects.link(cam)
        cam.location = location
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.camera = cam
        scene.render.filepath = os.path.join(PREVIEW_DIR, output_name)
        bpy.ops.render.render(write_still=True)

    scene.frame_set(FRAME_START)
    camera("CharacterPackFrontCamera", (0.0, -5.0, target.z), "01_front_equipped.png")
    camera("CharacterPackQuarterCamera", (3.55, -3.55, target.z + 0.10), "02_three_quarter_equipped.png")


CONTROLLED_ANIM_BONES = [
    "J_Bip_C_Hips", "J_Bip_C_Spine", "J_Bip_C_Chest", "J_Bip_C_UpperChest", "J_Bip_C_Neck", "J_Bip_C_Head",
    "J_Bip_L_Shoulder", "J_Bip_L_UpperArm", "J_Bip_L_LowerArm", "J_Bip_L_Hand",
    "J_Bip_R_Shoulder", "J_Bip_R_UpperArm", "J_Bip_R_LowerArm", "J_Bip_R_Hand",
    "J_Bip_L_UpperLeg", "J_Bip_L_LowerLeg", "J_Bip_L_Foot", "J_Bip_L_ToeBase",
    "J_Bip_R_UpperLeg", "J_Bip_R_LowerLeg", "J_Bip_R_Foot", "J_Bip_R_ToeBase",
]


def pose_bone(armature: bpy.types.Object, name: str) -> bpy.types.PoseBone:
    bone = armature.pose.bones.get(name)
    if bone is None:
        raise RuntimeError("Missing required bone: " + name)
    bone.rotation_mode = "XYZ"
    return bone


def reset_pose(armature: bpy.types.Object) -> None:
    for pb in armature.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)


def apply_right_hand_grip(armature: bpy.types.Object, frame: int | None = None) -> None:
    """Apply authentic weapon power grip to right hand fingers (tight wrap around hilt, thumb locked over index)."""
    q_seg1 = Euler((math.radians(-65), 0.0, 0.0), 'XYZ').to_quaternion()
    q_seg2 = Euler((math.radians(-85), 0.0, 0.0), 'XYZ').to_quaternion()
    q_seg3 = Euler((math.radians(-65), 0.0, 0.0), 'XYZ').to_quaternion()

    for finger in ("Index", "Middle", "Ring", "Little"):
        for seg, q in enumerate((q_seg1, q_seg2, q_seg3), start=1):
            b = armature.pose.bones.get(f"J_Bip_R_{finger}{seg}")
            if b:
                b.rotation_mode = "QUATERNION"
                b.rotation_quaternion = q
                if frame is not None:
                    b.keyframe_insert(data_path="rotation_quaternion", frame=frame)

    q_th1 = Euler((math.radians(25), math.radians(20), math.radians(-70)), 'XYZ').to_quaternion()
    q_th2 = Euler((math.radians(-50), 0.0, 0.0), 'XYZ').to_quaternion()
    q_th3 = Euler((math.radians(-50), 0.0, 0.0), 'XYZ').to_quaternion()
    for seg, q in enumerate((q_th1, q_th2, q_th3), start=1):
        b = armature.pose.bones.get(f"J_Bip_R_Thumb{seg}")
        if b:
            b.rotation_mode = "QUATERNION"
            b.rotation_quaternion = q
            if frame is not None:
                b.keyframe_insert(data_path="rotation_quaternion", frame=frame)


def apply_left_hand_grip(armature: bpy.types.Object, frame: int | None = None) -> None:
    """Apply firm shield/bow grip to left hand fingers (fingers curled around handle/grip)."""
    q_seg1 = Euler((math.radians(-60), 0.0, 0.0), 'XYZ').to_quaternion()
    q_seg2 = Euler((math.radians(-75), 0.0, 0.0), 'XYZ').to_quaternion()
    q_seg3 = Euler((math.radians(-60), 0.0, 0.0), 'XYZ').to_quaternion()

    for finger in ("Index", "Middle", "Ring", "Little"):
        for seg, q in enumerate((q_seg1, q_seg2, q_seg3), start=1):
            b = armature.pose.bones.get(f"J_Bip_L_{finger}{seg}")
            if b:
                b.rotation_mode = "QUATERNION"
                b.rotation_quaternion = q
                if frame is not None:
                    b.keyframe_insert(data_path="rotation_quaternion", frame=frame)

    q_th1 = Euler((math.radians(25), math.radians(-20), math.radians(70)), 'XYZ').to_quaternion()
    q_th2 = Euler((math.radians(-50), 0.0, 0.0), 'XYZ').to_quaternion()
    q_th3 = Euler((math.radians(-50), 0.0, 0.0), 'XYZ').to_quaternion()
    for seg, q in enumerate((q_th1, q_th2, q_th3), start=1):
        b = armature.pose.bones.get(f"J_Bip_L_Thumb{seg}")
        if b:
            b.rotation_mode = "QUATERNION"
            b.rotation_quaternion = q
            if frame is not None:
                b.keyframe_insert(data_path="rotation_quaternion", frame=frame)


def apply_finger_grips(armature: bpy.types.Object, action_name: str, frame: int) -> None:
    apply_r_grip = action_name not in ("down", "T-Pose", "attack_bow")
    apply_l_grip = action_name in ("attack_spear", "guard", "attack_bow", "attack_axe", "attack_hammer", "attack_dagger", "attack_crossbow", "attack_shield_bash", "ride_idle", "ride_walk", "ride_run", "ride_attack", "ride_slash", "ride_thrust")
    if apply_r_grip:
        apply_right_hand_grip(armature, frame)
    if apply_l_grip:
        apply_left_hand_grip(armature, frame)


def key_animation_frame(armature: bpy.types.Object, action_name: str, frame: int) -> None:
    for name in CONTROLLED_ANIM_BONES:
        b = pose_bone(armature, name)
        b.rotation_mode = "QUATERNION"
        if b.rotation_euler.x != 0.0 or b.rotation_euler.y != 0.0 or b.rotation_euler.z != 0.0:
            b.rotation_quaternion = b.rotation_euler.to_quaternion()
        b.keyframe_insert(data_path="rotation_quaternion", frame=frame, group=action_name)
        if name == "J_Bip_C_Hips":
            b.keyframe_insert(data_path="location", frame=frame, group=action_name)
    apply_finger_grips(armature, action_name, frame)


def prepare_tpose_action(armature: bpy.types.Object) -> bpy.types.Action:
    action = bpy.data.actions.get("T-Pose") or bpy.data.actions.new("T-Pose")
    armature.animation_data_create()
    armature.animation_data.action = action
    reset_pose(armature)
    key_animation_frame(armature, "T-Pose", 0)
    action.use_fake_user = True
    return action


SWORD_SHIELD_PACK = os.path.join(PROJECT_DIR, "assets", "animations", "Pro Sword and Shield Pack")


MIXAMO_TO_VRM_MAP = {
    "mixamorig1:Hips": "J_Bip_C_Hips",
    "mixamorig1:Spine": "J_Bip_C_Spine",
    "mixamorig1:Spine1": "J_Bip_C_Chest",
    "mixamorig1:Spine2": "J_Bip_C_UpperChest",
    "mixamorig1:Neck": "J_Bip_C_Neck",
    "mixamorig1:Head": "J_Bip_C_Head",
    "mixamorig1:LeftShoulder": "J_Bip_L_Shoulder",
    "mixamorig1:LeftArm": "J_Bip_L_UpperArm",
    "mixamorig1:LeftForeArm": "J_Bip_L_LowerArm",
    "mixamorig1:LeftHand": "J_Bip_L_Hand",
    "mixamorig1:RightShoulder": "J_Bip_R_Shoulder",
    "mixamorig1:RightArm": "J_Bip_R_UpperArm",
    "mixamorig1:RightForeArm": "J_Bip_R_LowerArm",
    "mixamorig1:RightHand": "J_Bip_R_Hand",
    "mixamorig1:LeftUpLeg": "J_Bip_L_UpperLeg",
    "mixamorig1:LeftLeg": "J_Bip_L_LowerLeg",
    "mixamorig1:LeftFoot": "J_Bip_L_Foot",
    "mixamorig1:LeftToeBase": "J_Bip_L_ToeBase",
    "mixamorig1:RightUpLeg": "J_Bip_R_UpperLeg",
    "mixamorig1:RightLeg": "J_Bip_R_LowerLeg",
    "mixamorig1:RightFoot": "J_Bip_R_Foot",
    "mixamorig1:RightToeBase": "J_Bip_R_ToeBase",
}

for side_m, side_v in [("LeftHand", "J_Bip_L_"), ("RightHand", "J_Bip_R_")]:
    for f_m, f_v in [("Thumb", "Thumb"), ("Index", "Index"), ("Middle", "Middle"), ("Ring", "Ring"), ("Pinky", "Little")]:
        for idx in (1, 2, 3):
            MIXAMO_TO_VRM_MAP[f"mixamorig1:{side_m}{f_m}{idx}"] = f"{side_v}{f_v}{idx}"


def retarget_mixamo_fbx_to_action(
    target_arm: bpy.types.Object,
    fbx_filepath: str,
    action_name: str,
    lock_root_xy: bool = True,
    mirror: bool = False,
) -> bpy.types.Action:
    if not os.path.exists(fbx_filepath):
        raise FileNotFoundError(f"FBX animation file not found: {fbx_filepath}")

    bpy.ops.import_scene.fbx(filepath=fbx_filepath)
    source_arm = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE" and obj != target_arm)
    source_action = source_arm.animation_data.action if source_arm.animation_data else None
    if not source_action:
        bpy.data.objects.remove(source_arm, do_unlink=True)
        raise ValueError(f"No animation action found in {fbx_filepath}")

    start_frame = int(source_action.frame_range[0])
    end_frame = int(source_action.frame_range[1])

    target_action = bpy.data.actions.get(action_name) or bpy.data.actions.new(action_name)
    target_arm.animation_data_create()
    target_arm.animation_data.action = target_action

    src_rest_world = {src_bname: (source_arm.matrix_world @ source_arm.data.bones[src_bname].matrix_local).to_3x3()
                      for src_bname in MIXAMO_TO_VRM_MAP.keys() if src_bname in source_arm.data.bones}
    tgt_rest_world = {tgt_bname: (target_arm.matrix_world @ target_arm.data.bones[tgt_bname].matrix_local).to_3x3()
                      for tgt_bname in MIXAMO_TO_VRM_MAP.values() if tgt_bname in target_arm.data.bones}

    src_hips_data = next((b for b in source_arm.data.bones if "Hips" in b.name), None)
    tgt_hips_data = target_arm.data.bones.get("J_Bip_C_Hips")
    source_rest_hips_z = (source_arm.matrix_world @ src_hips_data.head_local).z if src_hips_data else 1.0
    target_rest_hips_z = (target_arm.matrix_world @ tgt_hips_data.head_local).z if tgt_hips_data else 0.82
    scale_ratio = target_rest_hips_z / max(source_rest_hips_z, 0.001)

    apply_r_grip = action_name not in ("down", "attack_bow")
    apply_l_grip = action_name in ("attack_spear", "guard", "attack_bow", "attack_axe", "attack_hammer", "attack_dagger")

    Mx = Matrix((
        (-1.0,  0.0,  0.0),
        ( 0.0,  1.0,  0.0),
        ( 0.0,  0.0,  1.0)
    ))

    ordered_pairs = []
    if "mixamorig1:Hips" in source_arm.pose.bones and "J_Bip_C_Hips" in target_arm.pose.bones:
        ordered_pairs.append(("mixamorig1:Hips", "J_Bip_C_Hips"))
    for src_name, tgt_name in MIXAMO_TO_VRM_MAP.items():
        if src_name == "mixamorig1:Hips":
            continue
        if mirror:
            if "Left" in src_name:
                tgt_name = tgt_name.replace("_L_", "_R_")
            elif "Right" in src_name:
                tgt_name = tgt_name.replace("_R_", "_L_")
        if apply_r_grip and tgt_name.startswith("J_Bip_R_") and any(f in tgt_name for f in ("Thumb", "Index", "Middle", "Ring", "Little")):
            continue
        if apply_l_grip and tgt_name.startswith("J_Bip_L_") and any(f in tgt_name for f in ("Thumb", "Index", "Middle", "Ring", "Little")):
            continue
        if src_name in source_arm.pose.bones and tgt_name in target_arm.pose.bones:
            ordered_pairs.append((src_name, tgt_name))

    for pb in target_arm.pose.bones:
        pb.rotation_mode = "QUATERNION"

    prev_quats = {}
    src_hips_pb = next((b for b in source_arm.pose.bones if "Hips" in b.name), None)
    tgt_hips_db = target_arm.data.bones.get("J_Bip_C_Hips")
    tgt_hips_pb = target_arm.pose.bones.get("J_Bip_C_Hips")

    pitch_up_neck = Matrix.Rotation(math.radians(-25), 3, 'X')
    pitch_up_head = Matrix.Rotation(math.radians(-25), 3, 'X')

    for f in range(start_frame, end_frame + 1):
        bpy.context.scene.frame_set(f)
        bpy.context.view_layer.update()

        if src_hips_pb and tgt_hips_pb and tgt_hips_db:
            cur_hips_world_pos = (source_arm.matrix_world @ src_hips_pb.matrix).translation
            delta_z = (cur_hips_world_pos.z - source_rest_hips_z) * scale_ratio
            if lock_root_xy:
                delta_world = Vector((0.0, 0.0, delta_z))
            else:
                src_orig_head = source_arm.matrix_world @ src_hips_data.head_local if src_hips_data else Vector((0,0,0))
                dx = (cur_hips_world_pos.x - src_orig_head.x) * scale_ratio
                if mirror:
                    dx = -dx
                delta_world = Vector((
                    dx,
                    (cur_hips_world_pos.y - src_orig_head.y) * scale_ratio,
                    delta_z
                ))
            delta_bone_local = tgt_hips_db.matrix_local.to_3x3().inverted() @ (target_arm.matrix_world.to_3x3().inverted() @ delta_world)
            tgt_hips_pb.location = delta_bone_local
            tgt_hips_pb.keyframe_insert(data_path="location", frame=f - start_frame)

        desired_w_rots = {}

        for src_name, tgt_name in ordered_pairs:
            src_pb = source_arm.pose.bones[src_name]
            tgt_pb = target_arm.pose.bones[tgt_name]
            tgt_bone_data = target_arm.data.bones[tgt_name]

            src_w = (source_arm.matrix_world @ src_pb.matrix).to_3x3()
            src_rest_w = src_rest_world[src_name]
            tgt_rest_w = tgt_rest_world[tgt_name]

            delta_rot = src_w @ src_rest_w.inverted()
            if mirror:
                delta_rot = Mx @ delta_rot @ Mx
            tgt_desired_w_rot = delta_rot @ tgt_rest_w

            if tgt_name == "J_Bip_C_Neck":
                tgt_desired_w_rot = pitch_up_neck @ tgt_desired_w_rot
            elif tgt_name == "J_Bip_C_Head":
                tgt_desired_w_rot = pitch_up_head @ tgt_desired_w_rot

            desired_w_rots[tgt_name] = tgt_desired_w_rot

            parent_db = tgt_bone_data.parent
            if parent_db and parent_db.name in desired_w_rots:
                parent_w_rot = desired_w_rots[parent_db.name]
                basis_rot = (
                    tgt_bone_data.matrix_local.to_3x3().inverted()
                    @ parent_db.matrix_local.to_3x3()
                    @ parent_w_rot.inverted()
                    @ tgt_desired_w_rot
                )
            else:
                basis_rot = tgt_bone_data.matrix_local.to_3x3().inverted() @ tgt_desired_w_rot

            cur_q = basis_rot.to_quaternion()
            if tgt_name in prev_quats:
                if cur_q.dot(prev_quats[tgt_name]) < 0.0:
                    cur_q = -cur_q
            prev_quats[tgt_name] = cur_q.copy()

            tgt_pb.rotation_quaternion = cur_q
            tgt_pb.keyframe_insert(data_path="rotation_quaternion", frame=f - start_frame)

        if apply_r_grip:
            apply_right_hand_grip(target_arm, f - start_frame)
        if apply_l_grip:
            apply_left_hand_grip(target_arm, f - start_frame)

    target_action.use_fake_user = True
    bpy.data.objects.remove(source_arm, do_unlink=True)
    return target_action


def prepare_idle_action(armature: bpy.types.Object) -> bpy.types.Action:
    fbx = os.path.join(SWORD_SHIELD_PACK, "sword and shield idle.fbx")
    if os.path.exists(fbx):
        return retarget_mixamo_fbx_to_action(armature, fbx, "idle")

    action = bpy.data.actions.get("idle") or bpy.data.actions.new("idle")
    armature.animation_data_create()
    armature.animation_data.action = action
    for f in (0, 15, 30):
        reset_pose(armature)
        key_animation_frame(armature, "idle", f)
    action.use_fake_user = True
    return action


def prepare_walk_action(armature: bpy.types.Object) -> bpy.types.Action:
    fbx = os.path.join(SWORD_SHIELD_PACK, "sword and shield walk.fbx")
    if os.path.exists(fbx):
        return retarget_mixamo_fbx_to_action(armature, fbx, "walk")

    action = bpy.data.actions.get("walk") or bpy.data.actions.new("walk")
    armature.animation_data_create()
    armature.animation_data.action = action
    for f in range(0, 25, 2):
        reset_pose(armature)
        key_animation_frame(armature, "walk", f)
    action.use_fake_user = True
    return action


def prepare_run_action(armature: bpy.types.Object) -> bpy.types.Action:
    fbx = os.path.join(SWORD_SHIELD_PACK, "sword and shield run.fbx")
    if os.path.exists(fbx):
        return retarget_mixamo_fbx_to_action(armature, fbx, "run")

    action = bpy.data.actions.get("run") or bpy.data.actions.new("run")
    armature.animation_data_create()
    armature.animation_data.action = action
    for f in range(0, 21, 2):
        reset_pose(armature)
        key_animation_frame(armature, "run", f)
    action.use_fake_user = True
    return action


def prepare_guard_action(armature: bpy.types.Object) -> bpy.types.Action:
    fbx = os.path.join(SWORD_SHIELD_PACK, "sword and shield block.fbx")
    if os.path.exists(fbx):
        return retarget_mixamo_fbx_to_action(armature, fbx, "guard")

    action = bpy.data.actions.get("guard") or bpy.data.actions.new("guard")
    armature.animation_data_create()
    armature.animation_data.action = action
    reset_pose(armature)
    key_animation_frame(armature, "guard", 0)
    action.use_fake_user = True
    return action


def prepare_hit_action(armature: bpy.types.Object) -> bpy.types.Action:
    fbx = os.path.join(SWORD_SHIELD_PACK, "sword and shield impact.fbx")
    if os.path.exists(fbx):
        return retarget_mixamo_fbx_to_action(armature, fbx, "hit")

    action = bpy.data.actions.get("hit") or bpy.data.actions.new("hit")
    armature.animation_data_create()
    armature.animation_data.action = action
    for f in (0, 5, 12, 20):
        reset_pose(armature)
        key_animation_frame(armature, "hit", f)
    action.use_fake_user = True
    return action


def prepare_down_action(armature: bpy.types.Object) -> bpy.types.Action:
    fbx = os.path.join(SWORD_SHIELD_PACK, "sword and shield death.fbx")
    if os.path.exists(fbx):
        return retarget_mixamo_fbx_to_action(armature, fbx, "down")

    action = bpy.data.actions.get("down") or bpy.data.actions.new("down")
    armature.animation_data_create()
    armature.animation_data.action = action
    for f in (0, 10, 20, 30):
        reset_pose(armature)
        key_animation_frame(armature, "down", f)
    action.use_fake_user = True
    return action


def prepare_knockback_action(armature: bpy.types.Object) -> bpy.types.Action:
    fbx = os.path.join(SWORD_SHIELD_PACK, "sword and shield impact (2).fbx")
    if os.path.exists(fbx):
        return retarget_mixamo_fbx_to_action(armature, fbx, "knockback")

    action = bpy.data.actions.get("knockback") or bpy.data.actions.new("knockback")
    armature.animation_data_create()
    armature.animation_data.action = action
    for f in range(0, 31, 5):
        reset_pose(armature)
        key_animation_frame(armature, "knockback", f)
    action.use_fake_user = True
    return action


# Constant stable shield guard for all 1-handed weapon attacks (shield protects left flank steadily without flailing/bashing)
SHIELD_GUARD_LA = (-0.80, 0.10, -0.60)
SHIELD_GUARD_LF = (0.65, 0.0, -0.10)
SHIELD_GUARD_LH = (math.radians(-20), 0.0, math.radians(10))


def prepare_attack_sword_action(armature: bpy.types.Object) -> bpy.types.Action:
    fbx = os.path.join(SWORD_SHIELD_PACK, "sword and shield attack.fbx")
    if os.path.exists(fbx):
        act_jump = retarget_mixamo_fbx_to_action(armature, fbx, "attack_jump_heavy")
        act_sword = retarget_mixamo_fbx_to_action(armature, fbx, "attack_sword")
        act_attack = retarget_mixamo_fbx_to_action(armature, fbx, "attack")
        return act_jump

    action = bpy.data.actions.get("attack_jump_heavy") or bpy.data.actions.new("attack_jump_heavy")
    armature.animation_data_create()
    armature.animation_data.action = action
    reset_pose(armature)
    key_animation_frame(armature, "attack_jump_heavy", 0)
    action.use_fake_user = True
    act_sword = bpy.data.actions.get("attack_sword") or bpy.data.actions.new("attack_sword")
    act_sword.use_fake_user = True
    act_attack = bpy.data.actions.get("attack") or bpy.data.actions.new("attack")
    act_attack.use_fake_user = True
    return action


def prepare_attack_spear_action(armature: bpy.types.Object) -> bpy.types.Action:
    """Authentic spear combo with explosive piercing thrust retargeted from Upward Thrust.fbx, aligned forward with anti-clipping shield guard."""
    fbx = os.path.join(PROJECT_DIR, "assets", "animations", "Upward Thrust.fbx")
    if os.path.exists(fbx):
        act = retarget_mixamo_fbx_to_action(armature, fbx, "attack_spear", lock_root_xy=True)
        db_rh = armature.data.bones.get("J_Bip_R_Hand")
        pb_rf = armature.pose.bones.get("J_Bip_R_LowerArm")
        pb_rh = armature.pose.bones.get("J_Bip_R_Hand")
        pb_la = armature.pose.bones.get("J_Bip_L_UpperArm")
        pb_lf = armature.pose.bones.get("J_Bip_L_LowerArm")
        pb_lh = armature.pose.bones.get("J_Bip_L_Hand")
        db_la = armature.data.bones.get("J_Bip_L_UpperArm")
        db_lf = armature.data.bones.get("J_Bip_L_LowerArm")
        parent_pb = pb_rh.parent if pb_rh else None
        parent_la = pb_la.parent if pb_la else None

        if db_rh and pb_rf and pb_rh and parent_pb and db_la and db_lf and pb_la and pb_lf and parent_la:
            spear_local_dir = (db_rh.matrix_local.to_3x3().inverted() @ Vector((0.0, -1.0, 0.0))).normalized()
            aim_forward = Vector((0.05, -0.98, 0.12)).normalized()

            # Outward shield guard (左手往外擋：盾牌豎立並朝前外側防禦，與長槍保持 > 40cm 安全間距，全動作不穿模)
            q_la_windup = Euler((-0.60, 0.20, 0.60), 'XYZ').to_quaternion()
            q_lf_windup = Euler((0.0, math.radians(-45), -1.35), 'XYZ').to_quaternion()
            q_la_thrust = Euler((-0.40, 0.20, -0.50), 'XYZ').to_quaternion()
            q_lf_thrust = Euler((0.0, math.radians(-45), -1.40), 'XYZ').to_quaternion()
            q_lh = Euler((math.radians(35), math.radians(10), math.radians(-20)), 'XYZ').to_quaternion()

            for f in range(int(act.frame_range[0]), int(act.frame_range[1]) + 1):
                bpy.context.scene.frame_set(f)
                bpy.context.view_layer.update()

                # Left arm shield guard (solid flank guard, completely clear of spear and torso)
                if f < 18:
                    blend_t = 0.0
                elif f < 25:
                    blend_t = (f - 18) / 7.0
                elif f <= 48:
                    blend_t = 1.0
                elif f <= 58:
                    blend_t = 1.0 - (f - 48) / 10.0
                else:
                    blend_t = 0.0

                pb_la.rotation_quaternion = q_la_windup.slerp(q_la_thrust, blend_t)
                pb_la.keyframe_insert(data_path="rotation_quaternion", frame=f)
                pb_lf.rotation_quaternion = q_lf_windup.slerp(q_lf_thrust, blend_t)
                pb_lf.keyframe_insert(data_path="rotation_quaternion", frame=f)
                if pb_lh:
                    pb_lh.rotation_quaternion = q_lh
                    pb_lh.keyframe_insert(data_path="rotation_quaternion", frame=f)

                # Right hand spear forward alignment
                rf_w = armature.matrix_world @ pb_rf.matrix.translation
                rh_w = armature.matrix_world @ pb_rh.matrix.translation
                forearm_dir = (rh_w - rf_w).normalized()
                thrust_vec = forearm_dir.copy()
                thrust_vec.z = max(0.05, min(thrust_vec.z, 0.20))
                thrust_vec = thrust_vec.normalized()

                if f < 18:
                    t = max(0.0, (f - 10) / 8.0)
                    desired_dir = aim_forward.lerp(thrust_vec, t).normalized()
                elif f <= 48:
                    desired_dir = thrust_vec
                else:
                    t = min(1.0, (f - 48) / 10.0)
                    desired_dir = thrust_vec.lerp(aim_forward, t).normalized()

                rh_w_rot = (armature.matrix_world @ pb_rh.matrix).to_3x3()
                curr_spear_dir = (rh_w_rot @ spear_local_dir).normalized()
                delta_w = curr_spear_dir.rotation_difference(desired_dir).to_matrix()
                new_w_rot = delta_w @ rh_w_rot
                parent_w_rot = (armature.matrix_world @ parent_pb.matrix).to_3x3()
                basis_rot = (
                    db_rh.matrix_local.to_3x3().inverted()
                    @ parent_pb.bone.matrix_local.to_3x3()
                    @ parent_w_rot.inverted()
                    @ new_w_rot
                )
                pb_rh.rotation_quaternion = basis_rot.to_quaternion()
                pb_rh.keyframe_insert(data_path="rotation_quaternion", frame=f)

                apply_right_hand_grip(armature, f)
                apply_left_hand_grip(armature, f)
        return act

    action = bpy.data.actions.get("attack_spear") or bpy.data.actions.new("attack_spear")
    armature.animation_data_create()
    armature.animation_data.action = action
    
    LEG_LU = (0.0, 0.0, 0.06)
    LEG_LK = 0.0
    LEG_LF = (0.0, 0.0, -0.06)
    LEG_RU = (0.0, 0.0, -0.06)
    LEG_RK = 0.0
    LEG_RF = (0.0, 0.0, 0.06)
    
    keyframes_spear = [
        # (frame, sp_rot, ch_rot, hd_rot, ra, rf, rh)
        # f0: Ready Stance
        (0, (0.0, 0.05, 0.0), (0.0, 0.05, 0.0), (0.0, -0.08, 0.0),
         (-1.15, 0.05, -0.12), (0.20, 0.0, -0.15), (math.radians(20), math.radians(10), math.radians(-15))),
        # f8: Deep Draw (引槍蓄勢)
        (8, (0.0, 0.20, 0.0), (0.02, 0.25, 0.0), (0.0, -0.25, 0.0),
         (-0.85, 0.20, 0.40), (0.95, 0.0, 0.0), (-1.45, -1.05, 0.85)),
        # f12: Explosive Forward Piercing Thrust (直刺貫穿)
        (12, (0.04, -0.15, 0.0), (0.06, -0.20, 0.0), (0.0, 0.20, 0.0),
         (-1.45, 0.15, 0.35), (0.25, 0.0, 0.0), (-0.85, -1.15, 0.75)),
        # f15: Hit-Stop
        (15, (0.04, -0.15, 0.0), (0.06, -0.20, 0.0), (0.0, 0.20, 0.0),
         (-1.48, 0.15, 0.35), (0.22, 0.0, 0.0), (-0.85, -1.15, 0.75)),
        # f22: Snappy Drawback Recovery (抽槍收回)
        (22, (0.02, -0.05, 0.0), (0.03, -0.05, 0.0), (0.0, 0.05, 0.0),
         (-0.95, 0.15, 0.20), (0.75, 0.0, 0.0), (-1.30, -1.05, 0.85)),
        # f30: Return to Ready
        (30, (0.0, 0.05, 0.0), (0.0, 0.05, 0.0), (0.0, -0.08, 0.0),
         (-1.15, 0.05, -0.12), (0.20, 0.0, -0.15), (math.radians(20), math.radians(10), math.radians(-15))),
    ]
    for kf in keyframes_spear:
        f, sp_rot, ch_rot, hd_rot, ra, rf, rh = kf
        reset_pose(armature)
        pose_bone(armature, "J_Bip_C_Hips").location = (0.0, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Hips").rotation_euler = (0.0, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Spine").rotation_euler = sp_rot
        pose_bone(armature, "J_Bip_C_Chest").rotation_euler = ch_rot
        pose_bone(armature, "J_Bip_C_Head").rotation_euler = hd_rot
        pose_bone(armature, "J_Bip_L_UpperArm").rotation_euler = SHIELD_GUARD_LA
        pose_bone(armature, "J_Bip_L_LowerArm").rotation_euler = SHIELD_GUARD_LF
        pose_bone(armature, "J_Bip_L_Hand").rotation_euler = SHIELD_GUARD_LH
        pose_bone(armature, "J_Bip_R_UpperArm").rotation_euler = ra
        pose_bone(armature, "J_Bip_R_LowerArm").rotation_euler = rf
        pose_bone(armature, "J_Bip_R_Hand").rotation_euler = rh
        pose_bone(armature, "J_Bip_L_UpperLeg").rotation_euler = LEG_LU
        pose_bone(armature, "J_Bip_L_LowerLeg").rotation_euler = (LEG_LK, 0.0, 0.0)
        pose_bone(armature, "J_Bip_L_Foot").rotation_euler = LEG_LF
        pose_bone(armature, "J_Bip_R_UpperLeg").rotation_euler = LEG_RU
        pose_bone(armature, "J_Bip_R_LowerLeg").rotation_euler = (LEG_RK, 0.0, 0.0)
        pose_bone(armature, "J_Bip_R_Foot").rotation_euler = LEG_RF
        key_animation_frame(armature, "attack_spear", f)
    action.use_fake_user = True
    return action


def prepare_attack_axe_action(armature: bpy.types.Object) -> bpy.types.Action:
    """Heavy battle axe vertical cleave retargeted from Standing Torch Melee Attack 04.fbx."""
    fbx = os.path.join(PROJECT_DIR, "assets", "animations", "Standing Torch Melee Attack 04.fbx")
    if os.path.exists(fbx):
        return retarget_mixamo_fbx_to_action(armature, fbx, "attack_axe", lock_root_xy=True, mirror=True)

    action = bpy.data.actions.get("attack_axe") or bpy.data.actions.new("attack_axe")
    armature.animation_data_create()
    armature.animation_data.action = action
    
    LEG_LU = (0.0, 0.0, 0.06)
    LEG_LK = 0.0
    LEG_LF = (0.0, 0.0, -0.06)
    LEG_RU = (0.0, 0.0, -0.06)
    LEG_RK = 0.0
    LEG_RF = (0.0, 0.0, 0.06)
    
    keyframes_axe = [
        # (frame, sp_rot, ch_rot, hd_rot, ra, rf, rh)
        # f0: Ready Stance
        (0, (0.0, 0.05, 0.0), (0.0, 0.05, 0.0), (0.0, -0.08, 0.0),
         (-1.05, 0.05, -0.30), (0.25, 0.0, -0.15), (math.radians(20), math.radians(10), math.radians(-15))),
        # f8: High Overhead Windup (戰斧高舉蓄力)
        (8, (-0.02, 0.20, 0.0), (0.02, 0.25, 0.0), (0.0, -0.25, 0.0),
         (-0.25, 0.25, -0.65), (1.45, 0.0, 0.0), (0.20, 1.20, -1.20)),
        # f14: Downward Cleave Strike (正面全力重劈)
        (14, (0.06, -0.18, 0.0), (0.08, -0.22, 0.0), (0.0, 0.20, 0.0),
         (-1.30, 0.20, 0.40), (0.55, 0.0, -0.15), (-1.40, -0.85, 1.10)),
        # f16: Hit-Stop
        (16, (0.06, -0.18, 0.0), (0.08, -0.22, 0.0), (0.0, 0.20, 0.0),
         (-1.32, 0.20, 0.40), (0.50, 0.0, -0.15), (-1.40, -0.85, 1.10)),
        # f23: Recovery
        (23, (0.02, -0.05, 0.0), (0.04, -0.05, 0.0), (0.0, 0.05, 0.0),
         (-1.10, 0.10, 0.10), (0.45, 0.0, -0.10), (-1.20, -1.00, 0.85)),
        # f30: Return to Ready
        (30, (0.0, 0.05, 0.0), (0.0, 0.05, 0.0), (0.0, -0.08, 0.0),
         (-1.05, 0.05, -0.30), (0.25, 0.0, -0.15), (math.radians(20), math.radians(10), math.radians(-15))),
    ]
    for kf in keyframes_axe:
        f, sp_rot, ch_rot, hd_rot, ra, rf, rh = kf
        reset_pose(armature)
        pose_bone(armature, "J_Bip_C_Hips").location = (0.0, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Hips").rotation_euler = (0.0, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Spine").rotation_euler = sp_rot
        pose_bone(armature, "J_Bip_C_Chest").rotation_euler = ch_rot
        pose_bone(armature, "J_Bip_C_Head").rotation_euler = hd_rot
        pose_bone(armature, "J_Bip_L_UpperArm").rotation_euler = SHIELD_GUARD_LA
        pose_bone(armature, "J_Bip_L_LowerArm").rotation_euler = SHIELD_GUARD_LF
        pose_bone(armature, "J_Bip_L_Hand").rotation_euler = SHIELD_GUARD_LH
        pose_bone(armature, "J_Bip_R_UpperArm").rotation_euler = ra
        pose_bone(armature, "J_Bip_R_LowerArm").rotation_euler = rf
        pose_bone(armature, "J_Bip_R_Hand").rotation_euler = rh
        pose_bone(armature, "J_Bip_L_UpperLeg").rotation_euler = LEG_LU
        pose_bone(armature, "J_Bip_L_LowerLeg").rotation_euler = (LEG_LK, 0.0, 0.0)
        pose_bone(armature, "J_Bip_L_Foot").rotation_euler = LEG_LF
        pose_bone(armature, "J_Bip_R_UpperLeg").rotation_euler = LEG_RU
        pose_bone(armature, "J_Bip_R_LowerLeg").rotation_euler = (LEG_RK, 0.0, 0.0)
        pose_bone(armature, "J_Bip_R_Foot").rotation_euler = LEG_RF
        key_animation_frame(armature, "attack_axe", f)
    action.use_fake_user = True
    return action


def prepare_attack_hammer_action(armature: bpy.types.Object) -> bpy.types.Action:
    """Warhammer crushing swing retargeted from Standing Torch Melee Attack 04.fbx."""
    fbx = os.path.join(PROJECT_DIR, "assets", "animations", "Standing Torch Melee Attack 04.fbx")
    if os.path.exists(fbx):
        return retarget_mixamo_fbx_to_action(armature, fbx, "attack_hammer", lock_root_xy=True, mirror=True)

    action = bpy.data.actions.get("attack_hammer") or bpy.data.actions.new("attack_hammer")
    armature.animation_data_create()
    armature.animation_data.action = action
    
    LEG_LU = (0.0, 0.0, 0.06)
    LEG_LK = 0.0
    LEG_LF = (0.0, 0.0, -0.06)
    LEG_RU = (0.0, 0.0, -0.06)
    LEG_RK = 0.0
    LEG_RF = (0.0, 0.0, 0.06)
    
    keyframes_hammer = [
        # (frame, sp_rot, ch_rot, hd_rot, ra, rf, rh)
        # f0: Ready
        (0, (0.0, 0.05, 0.0), (0.0, 0.05, 0.0), (0.0, -0.08, 0.0),
         (-1.05, 0.05, -0.30), (0.25, 0.0, -0.15), (math.radians(20), math.radians(10), math.radians(-15))),
        # f10: Deep Rear Windup
        (10, (-0.02, 0.22, 0.0), (0.02, 0.26, 0.0), (0.0, -0.25, 0.0),
         (-0.45, 0.20, 0.65), (1.40, 0.0, 0.15), (-1.20, -1.00, 0.85)),
        # f15: Crushing Sweep Impact
        (15, (0.06, -0.18, 0.0), (0.08, -0.24, 0.0), (0.0, 0.20, 0.0),
         (-1.35, 0.15, 0.45), (0.45, 0.0, -0.10), (-0.95, -1.05, 0.80)),
        # f17: Hit-Stop
        (17, (0.06, -0.18, 0.0), (0.08, -0.24, 0.0), (0.0, 0.20, 0.0),
         (-1.38, 0.15, 0.45), (0.40, 0.0, -0.10), (-0.95, -1.05, 0.80)),
        # f24: Deceleration
        (24, (0.02, -0.05, 0.0), (0.04, -0.05, 0.0), (0.0, 0.05, 0.0),
         (-1.10, 0.10, 0.10), (0.45, 0.0, -0.10), (-1.20, -1.00, 0.85)),
        # f32: Return to Ready
        (32, (0.0, 0.05, 0.0), (0.0, 0.05, 0.0), (0.0, -0.08, 0.0),
         (-1.05, 0.05, -0.30), (0.25, 0.0, -0.15), (math.radians(20), math.radians(10), math.radians(-15))),
    ]
    for kf in keyframes_hammer:
        f, sp_rot, ch_rot, hd_rot, ra, rf, rh = kf
        reset_pose(armature)
        pose_bone(armature, "J_Bip_C_Hips").location = (0.0, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Hips").rotation_euler = (0.0, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Spine").rotation_euler = sp_rot
        pose_bone(armature, "J_Bip_C_Chest").rotation_euler = ch_rot
        pose_bone(armature, "J_Bip_C_Head").rotation_euler = hd_rot
        pose_bone(armature, "J_Bip_L_UpperArm").rotation_euler = SHIELD_GUARD_LA
        pose_bone(armature, "J_Bip_L_LowerArm").rotation_euler = SHIELD_GUARD_LF
        pose_bone(armature, "J_Bip_L_Hand").rotation_euler = SHIELD_GUARD_LH
        pose_bone(armature, "J_Bip_R_UpperArm").rotation_euler = ra
        pose_bone(armature, "J_Bip_R_LowerArm").rotation_euler = rf
        pose_bone(armature, "J_Bip_R_Hand").rotation_euler = rh
        pose_bone(armature, "J_Bip_L_UpperLeg").rotation_euler = LEG_LU
        pose_bone(armature, "J_Bip_L_LowerLeg").rotation_euler = (LEG_LK, 0.0, 0.0)
        pose_bone(armature, "J_Bip_L_Foot").rotation_euler = LEG_LF
        pose_bone(armature, "J_Bip_R_UpperLeg").rotation_euler = LEG_RU
        pose_bone(armature, "J_Bip_R_LowerLeg").rotation_euler = (LEG_RK, 0.0, 0.0)
        pose_bone(armature, "J_Bip_R_Foot").rotation_euler = LEG_RF
        key_animation_frame(armature, "attack_hammer", f)
    action.use_fake_user = True
    return action


def prepare_attack_dagger_action(armature: bpy.types.Object) -> bpy.types.Action:
    """Swift dagger rapid stabbing combo retargeted from Stabbing.fbx with solid outward shield guard."""
    fbx = os.path.join(PROJECT_DIR, "assets", "animations", "Stabbing.fbx")
    if os.path.exists(fbx):
        act = retarget_mixamo_fbx_to_action(armature, fbx, "attack_dagger", lock_root_xy=True, mirror=True)
        pb_la = armature.pose.bones.get("J_Bip_L_UpperArm")
        pb_lf = armature.pose.bones.get("J_Bip_L_LowerArm")
        pb_lh = armature.pose.bones.get("J_Bip_L_Hand")

        if pb_la and pb_lf:
            # Outward shield guard (左手盾稍微往外擋：盾牌護住左側並朝前外側防禦，與軀幹保持 >11cm 安全間距，全動作零穿模，右手連刺順暢無阻)
            q_la_guard = Euler((math.radians(-32), math.radians(-15), math.radians(-55)), 'XYZ').to_quaternion()
            q_lf_guard = Euler((math.radians(0), math.radians(-25), math.radians(-85)), 'XYZ').to_quaternion()
            q_lh_guard = Euler((math.radians(25), math.radians(10), math.radians(-15)), 'XYZ').to_quaternion()

            for f in range(int(act.frame_range[0]), int(act.frame_range[1]) + 1):
                pb_la.rotation_quaternion = q_la_guard
                pb_la.keyframe_insert(data_path="rotation_quaternion", frame=f)
                pb_lf.rotation_quaternion = q_lf_guard
                pb_lf.keyframe_insert(data_path="rotation_quaternion", frame=f)
                if pb_lh:
                    pb_lh.rotation_quaternion = q_lh_guard
                    pb_lh.keyframe_insert(data_path="rotation_quaternion", frame=f)
                apply_left_hand_grip(armature, f)
        return act

    action = bpy.data.actions.get("attack_dagger") or bpy.data.actions.new("attack_dagger")
    armature.animation_data_create()
    armature.animation_data.action = action
    
    LEG_LU = (0.0, 0.0, 0.06)
    LEG_LK = 0.0
    LEG_LF = (0.0, 0.0, -0.06)
    LEG_RU = (0.0, 0.0, -0.06)
    LEG_RK = 0.0
    LEG_RF = (0.0, 0.0, 0.06)
    
    keyframes_dag = [
        # (frame, sp_rot, ch_rot, hd_rot, ra, rf, rh)
        # f0: Ready
        (0, (0.0, 0.05, 0.0), (0.0, 0.05, 0.0), (0.0, -0.08, 0.0),
         (-1.15, 0.05, -0.12), (0.20, 0.0, -0.15), (math.radians(20), math.radians(10), math.radians(-15))),
        # f6: Chamber (蓄勢)
        (6, (0.0, 0.16, 0.0), (0.02, 0.20, 0.0), (0.0, -0.20, 0.0),
         (-0.85, 0.20, 0.40), (0.95, 0.0, 0.0), (-1.45, -1.05, 0.85)),
        # f11: Forward Stab (迅捷刺擊)
        (11, (0.04, -0.14, 0.0), (0.06, -0.18, 0.0), (0.0, 0.18, 0.0),
         (-1.45, 0.15, 0.35), (0.25, 0.0, 0.0), (-0.85, -1.15, 0.75)),
        # f13: Stab Hit-Stop
        (13, (0.04, -0.14, 0.0), (0.06, -0.18, 0.0), (0.0, 0.18, 0.0),
         (-1.48, 0.15, 0.35), (0.22, 0.0, 0.0), (-0.85, -1.15, 0.75)),
        # f17: Upward Slash (斜上挑斬)
        (17, (0.04, -0.10, 0.0), (0.06, -0.14, 0.0), (0.0, 0.12, 0.0),
         (-1.25, 0.25, 0.45), (0.60, 0.0, -0.20), (-1.45, -0.85, 1.15)),
        # f24: Recovery
        (24, (0.02, -0.04, 0.0), (0.03, -0.04, 0.0), (0.0, 0.05, 0.0),
         (-1.00, 0.10, 0.10), (0.35, 0.0, -0.10), (-1.20, -1.00, 0.85)),
        # f30: Return to Ready
        (30, (0.0, 0.05, 0.0), (0.0, 0.05, 0.0), (0.0, -0.08, 0.0),
         (-1.15, 0.05, -0.12), (0.20, 0.0, -0.15), (math.radians(20), math.radians(10), math.radians(-15))),
    ]
    for kf in keyframes_dag:
        f, sp_rot, ch_rot, hd_rot, ra, rf, rh = kf
        reset_pose(armature)
        pose_bone(armature, "J_Bip_C_Hips").location = (0.0, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Hips").rotation_euler = (0.0, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Spine").rotation_euler = sp_rot
        pose_bone(armature, "J_Bip_C_Chest").rotation_euler = ch_rot
        pose_bone(armature, "J_Bip_C_Head").rotation_euler = hd_rot
        pose_bone(armature, "J_Bip_L_UpperArm").rotation_euler = SHIELD_GUARD_LA
        pose_bone(armature, "J_Bip_L_LowerArm").rotation_euler = SHIELD_GUARD_LF
        pose_bone(armature, "J_Bip_L_Hand").rotation_euler = SHIELD_GUARD_LH
        pose_bone(armature, "J_Bip_R_UpperArm").rotation_euler = ra
        pose_bone(armature, "J_Bip_R_LowerArm").rotation_euler = rf
        pose_bone(armature, "J_Bip_R_Hand").rotation_euler = rh
        pose_bone(armature, "J_Bip_L_UpperLeg").rotation_euler = LEG_LU
        pose_bone(armature, "J_Bip_L_LowerLeg").rotation_euler = (LEG_LK, 0.0, 0.0)
        pose_bone(armature, "J_Bip_L_Foot").rotation_euler = LEG_LF
        pose_bone(armature, "J_Bip_R_UpperLeg").rotation_euler = LEG_RU
        pose_bone(armature, "J_Bip_R_LowerLeg").rotation_euler = (LEG_RK, 0.0, 0.0)
        pose_bone(armature, "J_Bip_R_Foot").rotation_euler = LEG_RF
        key_animation_frame(armature, "attack_dagger", f)
    action.use_fake_user = True
    return action


def prepare_attack_bow_action(armature: bpy.types.Object) -> bpy.types.Action:
    """Archery shot retargeted from Shooting Arrow.fbx:
    Raise and extend bow firmly with left hand -> draw bowstring to cheek with right hand -> release arrow recoil."""
    fbx = os.path.join(PROJECT_DIR, "assets", "animations", "Shooting Arrow.fbx")
    if os.path.exists(fbx):
        return retarget_mixamo_fbx_to_action(armature, fbx, "attack_bow", lock_root_xy=True)

    action = bpy.data.actions.get("attack_bow") or bpy.data.actions.new("attack_bow")
    armature.animation_data_create()
    armature.animation_data.action = action
    
    LEG_LU = (0.0, 0.0, 0.06)
    LEG_LK = 0.0
    LEG_LF = (0.0, 0.0, -0.06)
    LEG_RU = (0.0, 0.0, -0.06)
    LEG_RK = 0.0
    LEG_RF = (0.0, 0.0, 0.06)
    
    keyframes_bow = [
        # (frame, sp_rot, ch_rot, hd_rot, la, lf, lh, ra, rf, rh)
        (0, (0.0, 0.0, 0.0), (0.02, 0, 0), (0, 0, 0),
         (-1.10, 0.0, 0.05), (0.25, 0.0, 0.10), (math.radians(15), math.radians(-10), math.radians(15)),
         (-1.15, 0.05, -0.12), (0.20, 0.0, -0.15), (math.radians(20), math.radians(10), math.radians(-15))),
        (8, (0.0, 0.04, 0.0), (0.02, 0.08, 0.0), (0.0, -0.06, 0.0),
         (-0.75, -0.15, 0.55), (0.10, 0.0, 0.0), (math.radians(0), math.radians(-10), math.radians(15)),
         (-0.35, 0.10, -0.55), (1.10, 0.0, 0.10), (math.radians(25), math.radians(10), math.radians(-15))),
        (16, (0.0, 0.06, 0.0), (0.06, 0.12, 0.0), (0.0, -0.08, 0.0),
         (-0.75, -0.15, 0.60), (0.05, 0.0, 0.0), (math.radians(0), math.radians(-10), math.radians(15)),
         (-0.30, 0.10, -0.85), (1.70, 0.0, 0.10), (math.radians(25), math.radians(10), math.radians(-15))),
        (20, (0.0, 0.04, 0.0), (0.02, 0.06, 0.0), (0.0, -0.06, 0.0),
         (-0.70, -0.15, 0.55), (0.15, 0.0, 0.0), (math.radians(0), math.radians(-10), math.radians(15)),
         (-0.35, 0.10, -0.95), (0.85, 0.0, 0.10), (math.radians(20), math.radians(10), math.radians(-15))),
        (30, (0.0, 0.0, 0.0), (0.02, 0, 0), (0, 0, 0),
         (-1.10, 0.0, 0.05), (0.25, 0.0, 0.10), (math.radians(15), math.radians(-10), math.radians(15)),
         (-1.15, 0.05, -0.12), (0.20, 0.0, -0.15), (math.radians(20), math.radians(10), math.radians(-15))),
    ]
    for kf in keyframes_bow:
        f, sp_rot, ch_rot, hd_rot, la, lf, lh, ra, rf, rh = kf
        reset_pose(armature)
        pose_bone(armature, "J_Bip_C_Hips").location = (0.0, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Hips").rotation_euler = (0.0, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Spine").rotation_euler = sp_rot
        pose_bone(armature, "J_Bip_C_Chest").rotation_euler = ch_rot
        pose_bone(armature, "J_Bip_C_Head").rotation_euler = hd_rot
        pose_bone(armature, "J_Bip_L_UpperArm").rotation_euler = la
        pose_bone(armature, "J_Bip_L_LowerArm").rotation_euler = lf
        pose_bone(armature, "J_Bip_L_Hand").rotation_euler = lh
        pose_bone(armature, "J_Bip_R_UpperArm").rotation_euler = ra
        pose_bone(armature, "J_Bip_R_LowerArm").rotation_euler = rf
        pose_bone(armature, "J_Bip_R_Hand").rotation_euler = rh
        pose_bone(armature, "J_Bip_L_UpperLeg").rotation_euler = LEG_LU
        pose_bone(armature, "J_Bip_L_LowerLeg").rotation_euler = (LEG_LK, 0.0, 0.0)
        pose_bone(armature, "J_Bip_L_Foot").rotation_euler = LEG_LF
        pose_bone(armature, "J_Bip_R_UpperLeg").rotation_euler = LEG_RU
        pose_bone(armature, "J_Bip_R_LowerLeg").rotation_euler = (LEG_RK, 0.0, 0.0)
        pose_bone(armature, "J_Bip_R_Foot").rotation_euler = LEG_RF
        key_animation_frame(armature, "attack_bow", f)
    action.use_fake_user = True
    return action


def prepare_attack_crossbow_action(armature: bpy.types.Object) -> bpy.types.Action:
    """Crossbow discharge: raise stock to shoulder and aim -> trigger release with sharp upward recoil -> reload tilt."""
    action = bpy.data.actions.get("attack_crossbow") or bpy.data.actions.new("attack_crossbow")
    armature.animation_data_create()
    armature.animation_data.action = action
    
    LEG_LU = (0.0, 0.0, 0.06)
    LEG_LK = 0.0
    LEG_LF = (0.0, 0.0, -0.06)
    LEG_RU = (0.0, 0.0, -0.06)
    LEG_RK = 0.0
    LEG_RF = (0.0, 0.0, 0.06)
    
    keyframes_xbow = [
        # (frame, sp_rot, ch_rot, hd_rot, la, lf, lh, ra, rf, rh)
        (0, (0.0, 0.0, 0.0), (0.02, 0, 0), (0, 0, 0),
         (-1.10, 0.0, 0.05), (0.25, 0.0, 0.10), (math.radians(15), math.radians(-10), math.radians(15)),
         (-1.15, 0.05, -0.12), (0.20, 0.0, -0.15), (math.radians(20), math.radians(10), math.radians(-15))),
        (6, (0.0, 0.02, 0.0), (0.04, 0.04, 0.0), (0.0, -0.04, 0.0),
         (-0.95, -0.10, 0.35), (0.45, 0.0, 0.05), (math.radians(10), math.radians(-10), math.radians(15)),
         (-0.85, 0.15, -0.35), (0.95, 0.0, 0.05), (math.radians(20), math.radians(10), math.radians(-15))),
        (10, (0.0, -0.02, 0.0), (-0.08, -0.04, 0.0), (0.0, 0.02, 0.0),
         (-1.15, -0.10, 0.30), (0.35, 0.0, 0.05), (math.radians(15), math.radians(-10), math.radians(15)),
         (-1.05, 0.15, -0.30), (0.85, 0.0, 0.05), (math.radians(25), math.radians(10), math.radians(-15))),
        (18, (0.0, 0.04, 0.0), (0.10, 0.08, 0.0), (0.0, -0.06, 0.0),
         (-0.75, -0.15, 0.45), (0.75, 0.0, 0.10), (math.radians(0), math.radians(-10), math.radians(15)),
         (-0.65, 0.20, -0.45), (1.20, 0.0, 0.10), (math.radians(20), math.radians(10), math.radians(-15))),
        (30, (0.0, 0.0, 0.0), (0.02, 0, 0), (0, 0, 0),
         (-1.10, 0.0, 0.05), (0.25, 0.0, 0.10), (math.radians(15), math.radians(-10), math.radians(15)),
         (-1.15, 0.05, -0.12), (0.20, 0.0, -0.15), (math.radians(20), math.radians(10), math.radians(-15))),
    ]
    for kf in keyframes_xbow:
        f, sp_rot, ch_rot, hd_rot, la, lf, lh, ra, rf, rh = kf
        reset_pose(armature)
        pose_bone(armature, "J_Bip_C_Hips").location = (0.0, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Hips").rotation_euler = (0.0, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Spine").rotation_euler = sp_rot
        pose_bone(armature, "J_Bip_C_Chest").rotation_euler = ch_rot
        pose_bone(armature, "J_Bip_C_Head").rotation_euler = hd_rot
        pose_bone(armature, "J_Bip_L_UpperArm").rotation_euler = la
        pose_bone(armature, "J_Bip_L_LowerArm").rotation_euler = lf
        pose_bone(armature, "J_Bip_L_Hand").rotation_euler = lh
        pose_bone(armature, "J_Bip_R_UpperArm").rotation_euler = ra
        pose_bone(armature, "J_Bip_R_LowerArm").rotation_euler = rf
        pose_bone(armature, "J_Bip_R_Hand").rotation_euler = rh
        pose_bone(armature, "J_Bip_L_UpperLeg").rotation_euler = LEG_LU
        pose_bone(armature, "J_Bip_L_LowerLeg").rotation_euler = (LEG_LK, 0.0, 0.0)
        pose_bone(armature, "J_Bip_L_Foot").rotation_euler = LEG_LF
        pose_bone(armature, "J_Bip_R_UpperLeg").rotation_euler = LEG_RU
        pose_bone(armature, "J_Bip_R_LowerLeg").rotation_euler = (LEG_RK, 0.0, 0.0)
        pose_bone(armature, "J_Bip_R_Foot").rotation_euler = LEG_RF
        key_animation_frame(armature, "attack_crossbow", f)
    from fix_crossbow_idle_stance import apply_crossbow_idle_stance
    apply_crossbow_idle_stance(armature)
    action.use_fake_user = True
    return action


def prepare_attack_unarmed_action(armature: bpy.types.Object) -> bpy.types.Action:
    fbx = os.path.join(SWORD_SHIELD_PACK, "sword and shield kick.fbx")
    if os.path.exists(fbx):
        return retarget_mixamo_fbx_to_action(armature, fbx, "attack_unarmed")

    action = bpy.data.actions.get("attack_unarmed") or bpy.data.actions.new("attack_unarmed")
    armature.animation_data_create()
    armature.animation_data.action = action
    reset_pose(armature)
    key_animation_frame(armature, "attack_unarmed", 0)
    action.use_fake_user = True
    return action


def prepare_attack_shield_bash_action(armature: bpy.types.Object) -> bpy.types.Action:
    """Dedicated Heavy Shield Bash: Deep anticipation draw -> explosive forward shield slam with body weight -> hit stop -> recovery."""
    action = bpy.data.actions.get("attack_shield_bash") or bpy.data.actions.new("attack_shield_bash")
    armature.animation_data_create()
    armature.animation_data.action = action
    
    LEG_LU = (0.0, 0.0, 0.06)
    LEG_LK = 0.0
    LEG_LF = (0.0, 0.0, -0.06)
    LEG_RU = (0.0, 0.0, -0.06)
    LEG_RK = 0.0
    LEG_RF = (0.0, 0.0, 0.06)
    
    keyframes_bash = [
        # (frame, sp_rot, ch_rot, hd_rot, la, lf, lh, ra, rf, rh)
        # f0: Ready Stance
        (0, (0.0, 0.05, 0.0), (0.0, 0.05, 0.0), (0.0, -0.08, 0.0),
         (-0.80, 0.10, -0.60), (0.65, 0.0, -0.10), (math.radians(-20), 0, math.radians(10)),
         (-0.35, 0.0, -1.10), (0.20, 0.0, 0.0), (math.radians(-75), 0.0, 0.0)),

        # f7: Anticipation / Chamber
        (7, (-0.02, 0.14, 0.0), (0.02, 0.18, 0.0), (0.0, -0.16, 0.0),
         (-0.35, -0.15, -1.45), (1.35, 0.0, 0.0), (0.118, 0.744, 1.403),
         (-0.55, 0.10, 0.20), (0.35, 0.0, 0.0), (math.radians(20), math.radians(10), math.radians(-15))),

        # f10: Initiate Shield Slam
        (10, (0.04, -0.10, 0.0), (0.06, -0.14, 0.0), (0.0, 0.10, 0.0),
         (-0.35, -0.15, -1.45), (0.50, 0.0, 0.0), (0.118, 0.350, 1.403),
         (-0.40, 0.12, 0.25), (0.25, 0.0, 0.0), (math.radians(20), math.radians(10), math.radians(-15))),

        # f13: Impact / Full Extension
        (13, (0.06, -0.18, 0.0), (0.08, -0.22, 0.0), (0.0, 0.20, 0.0),
         (-0.35, -0.15, -1.45), (0.10, 0.0, 0.0), (0.118, -0.006, 1.403),
         (-0.45, 0.15, 0.25), (0.20, 0.0, 0.0), (math.radians(20), math.radians(10), math.radians(-15))),

        # f15: Hit-Stop
        (15, (0.06, -0.18, 0.0), (0.08, -0.22, 0.0), (0.0, 0.20, 0.0),
         (-0.35, -0.15, -1.45), (0.08, 0.0, 0.0), (0.118, -0.006, 1.403),
         (-0.45, 0.15, 0.25), (0.20, 0.0, 0.0), (math.radians(20), math.radians(10), math.radians(-15))),

        # f20: Recoil
        (20, (0.02, -0.05, 0.0), (0.04, -0.08, 0.0), (0.0, 0.05, 0.0),
         (-0.35, -0.15, -1.45), (0.85, 0.0, 0.0), (0.118, 0.744, 1.403),
         (-0.85, 0.10, 0.05), (0.25, 0.0, 0.0), (math.radians(20), math.radians(10), math.radians(-15))),

        # f30: Recovery
        (30, (0.0, 0.05, 0.0), (0.0, 0.05, 0.0), (0.0, -0.08, 0.0),
         (-0.80, 0.10, -0.60), (0.65, 0.0, -0.10), (math.radians(-20), 0, math.radians(10)),
         (-0.35, 0.0, -1.10), (0.20, 0.0, 0.0), (math.radians(-75), 0.0, 0.0)),
    ]
    for kf in keyframes_bash:
        f, sp_rot, ch_rot, hd_rot, la, lf, lh, ra, rf, rh = kf
        reset_pose(armature)
        pose_bone(armature, "J_Bip_C_Hips").location = (0.0, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Hips").rotation_euler = (0.0, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Spine").rotation_euler = sp_rot
        pose_bone(armature, "J_Bip_C_Chest").rotation_euler = ch_rot
        pose_bone(armature, "J_Bip_C_Head").rotation_euler = hd_rot
        pose_bone(armature, "J_Bip_L_UpperArm").rotation_euler = la
        pose_bone(armature, "J_Bip_L_LowerArm").rotation_euler = lf
        pose_bone(armature, "J_Bip_L_Hand").rotation_euler = lh
        pose_bone(armature, "J_Bip_R_UpperArm").rotation_euler = ra
        pose_bone(armature, "J_Bip_R_LowerArm").rotation_euler = rf
        pose_bone(armature, "J_Bip_R_Hand").rotation_euler = rh
        pose_bone(armature, "J_Bip_L_UpperLeg").rotation_euler = LEG_LU
        pose_bone(armature, "J_Bip_L_LowerLeg").rotation_euler = (LEG_LK, 0.0, 0.0)
        pose_bone(armature, "J_Bip_L_Foot").rotation_euler = LEG_LF
        pose_bone(armature, "J_Bip_R_UpperLeg").rotation_euler = LEG_RU
        pose_bone(armature, "J_Bip_R_LowerLeg").rotation_euler = (LEG_RK, 0.0, 0.0)
        pose_bone(armature, "J_Bip_R_Foot").rotation_euler = LEG_RF
        key_animation_frame(armature, "attack_shield_bash", f)
    action.use_fake_user = True
    return action


def prepare_hit_back_action(armature: bpy.types.Object) -> bpy.types.Action:
    """Back Impact Action (背後受擊): Grounded on exact 'hit' combat base stance -> thoracic impact from behind -> violent forward chest/hips thrust -> inertial head whiplash -> forward stumble/flexion -> arrest -> recovery back to combat stance."""
    hit_act = bpy.data.actions.get("hit")
    base_loc = {}
    base_rot = {}
    if hit_act:
        armature.animation_data.action = hit_act
        if hasattr(hit_act, "slots") and hit_act.slots:
            armature.animation_data.action_slot = hit_act.slots[0]
        bpy.context.scene.frame_set(0)
        bpy.context.view_layer.update()
        for pb in armature.pose.bones:
            base_loc[pb.name] = pb.location.copy()
            base_rot[pb.name] = pb.rotation_quaternion.copy()
    else:
        for pb in armature.pose.bones:
            base_loc[pb.name] = pb.location.copy()
            base_rot[pb.name] = pb.rotation_quaternion.copy()

    action = bpy.data.actions.get("hit_back") or bpy.data.actions.new("hit_back")
    armature.animation_data_create()
    armature.animation_data.action = action
    if hasattr(action, "slots") and action.slots:
        armature.animation_data.action_slot = action.slots[0]

    for pb in armature.pose.bones:
        pb.rotation_mode = "QUATERNION"

    def mul_quat(base_q, euler_xyz):
        delta_q = Euler(euler_xyz, 'XYZ').to_quaternion()
        return base_q @ delta_q

    # 32-frame dynamic combat back hit: left arm flung OUTWARD (guard break) & pronounced forward lean
    keyframes_data = [
        # (frame, hips_dloc, spine_euler, chest_euler, head_euler, l_upperarm_euler, l_lowerarm_euler, r_upperarm_euler, r_lowerarm_euler, l_upperleg_euler, l_lowerleg_euler, r_upperleg_euler, r_lowerleg_euler)
        # F0: Base Combat Guard (Shield raised in front, sword ready)
        (0,
         Vector((0.0, 0.0, 0.0)),
         (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0),
         (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0),
         (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),

        # F4: Impact & LEFT ARM FLUNG OUTWARD TO BREAK GUARD (Pronounced forward lean!)
        (4,
         Vector((0.0, 0.025, 0.12)),
         (0.48, 0.0, 0.0), (0.42, 0.0, 0.0), (-0.42, 0.0, 0.0),
         (-0.35, 0.20, 1.70), (0.55, -0.40, 0.0),  # Left arm blasted OUTWARD to the left!
         (0.35, -0.30, 0.60), (0.20, 0.20, 0.0),
         (0.12, 0.0, 0.0), (0.15, 0.0, 0.0), (-0.06, 0.0, 0.0), (0.06, 0.0, 0.0)),

        # F10: Maximum Forward Stumble & Peak Forward Pitch (Guard broken wide open)
        (10,
         Vector((0.0, 0.035, 0.25)),
         (0.58, 0.0, 0.0), (0.50, 0.0, 0.0), (-0.35, 0.0, 0.0),
         (-0.25, 0.25, 1.50), (0.45, -0.30, 0.0),  # Shield arm still trailing wide open to left
         (0.40, -0.35, 0.65), (0.20, 0.20, 0.0),
         (0.22, 0.0, 0.0), (0.30, 0.0, 0.0), (-0.10, 0.0, 0.0), (0.08, 0.0, 0.0)),

        # F16: Stumble Caught & Arrested (Front foot brakes momentum)
        (16,
         Vector((0.0, 0.030, 0.18)),
         (0.42, 0.0, 0.0), (0.35, 0.0, 0.0), (-0.15, 0.0, 0.0),
         (-0.15, 0.15, 1.00), (0.30, -0.20, 0.0),  # Left arm begins pulling back inward
         (0.25, -0.20, 0.40), (0.15, 0.15, 0.0),
         (0.15, 0.0, 0.0), (0.20, 0.0, 0.0), (-0.07, 0.0, 0.0), (0.06, 0.0, 0.0)),

        # F22: Frantically Pulling Guard Back (Torso rising, bringing shield back across chest)
        (22,
         Vector((0.0, 0.018, 0.08)),
         (0.20, 0.0, 0.0), (0.18, 0.0, 0.0), (0.0, 0.0, 0.0),
         (-0.05, 0.08, 0.40), (0.12, -0.08, 0.0),
         (0.10, -0.08, 0.15), (0.05, 0.05, 0.0),
         (0.08, 0.0, 0.0), (0.10, 0.0, 0.0), (-0.04, 0.0, 0.0), (0.03, 0.0, 0.0)),

        # F27: Guard almost completely reformed
        (27,
         Vector((0.0, 0.005, 0.02)),
         (0.05, 0.0, 0.0), (0.04, 0.0, 0.0), (0.0, 0.0, 0.0),
         (-0.01, 0.02, 0.08), (0.02, -0.02, 0.0),
         (0.02, -0.02, 0.03), (0.01, 0.01, 0.0),
         (0.02, 0.0, 0.0), (0.02, 0.0, 0.0), (-0.01, 0.0, 0.0), (0.01, 0.0, 0.0)),

        # F32: Return to exact base combat stance
        (32,
         Vector((0.0, 0.0, 0.0)),
         (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0),
         (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0),
         (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)),
    ]

    controlled_bones = [
        ("J_Bip_C_Spine", 2),
        ("J_Bip_C_Chest", 3),
        ("J_Bip_C_Head", 4),
        ("J_Bip_L_UpperArm", 5),
        ("J_Bip_L_LowerArm", 6),
        ("J_Bip_R_UpperArm", 7),
        ("J_Bip_R_LowerArm", 8),
        ("J_Bip_L_UpperLeg", 9),
        ("J_Bip_L_LowerLeg", 10),
        ("J_Bip_R_UpperLeg", 11),
        ("J_Bip_R_LowerLeg", 12),
    ]

    for kf in keyframes_data:
        f = kf[0]
        h_dloc = kf[1]

        # Reset all bones to base pose
        for bname, pb in armature.pose.bones.items():
            pb.location = base_loc[bname].copy()
            pb.rotation_quaternion = base_rot[bname].copy()

        # Apply hips displacement
        hips_pb = armature.pose.bones.get("J_Bip_C_Hips")
        if hips_pb:
            hips_pb.location = base_loc["J_Bip_C_Hips"] + h_dloc
            hips_pb.keyframe_insert(data_path="location", frame=f, group="hit_back")
            hips_pb.keyframe_insert(data_path="rotation_quaternion", frame=f, group="hit_back")

        # Apply offsets to controlled bones
        for bname, idx in controlled_bones:
            pb = armature.pose.bones.get(bname)
            if pb:
                euler_offset = kf[idx]
                pb.rotation_quaternion = mul_quat(base_rot[bname], euler_offset)
                pb.keyframe_insert(data_path="rotation_quaternion", frame=f, group="hit_back")

        # Keyframe all other bones (hands, fingers, feet, toes) to preserve exact combat stance
        for bname, pb in armature.pose.bones.items():
            if bname != "J_Bip_C_Hips" and bname not in [cb[0] for cb in controlled_bones]:
                pb.keyframe_insert(data_path="rotation_quaternion", frame=f, group="hit_back")

    action.use_fake_user = True
    return action


def prepare_ride_idle_action(armature: bpy.types.Object) -> bpy.types.Action:
    """Natural seated riding idle on horseback holding reins tightly, thighs & calves hugging horse flanks."""
    action = bpy.data.actions.get("ride_idle") or bpy.data.actions.new("ride_idle")
    armature.animation_data_create()
    armature.animation_data.action = action

    for f in range(0, 61, 5):
        reset_pose(armature)
        t = f / 60.0 * math.tau
        breath_pitch = math.sin(t) * 0.015
        bounce_z = math.sin(t) * 0.005

        pose_bone(armature, "J_Bip_C_Hips").location = (0.0, 0.605 + bounce_z, -0.05)
        pose_bone(armature, "J_Bip_L_UpperLeg").rotation_euler = (math.radians(-38), math.radians(-12), math.radians(-34))
        pose_bone(armature, "J_Bip_L_LowerLeg").rotation_euler = (math.radians(64), math.radians(-6), math.radians(26))
        pose_bone(armature, "J_Bip_L_Foot").rotation_euler = (math.radians(-16), 0.0, 0.0)

        pose_bone(armature, "J_Bip_R_UpperLeg").rotation_euler = (math.radians(-38), math.radians(12), math.radians(34))
        pose_bone(armature, "J_Bip_R_LowerLeg").rotation_euler = (math.radians(64), math.radians(6), math.radians(-26))
        pose_bone(armature, "J_Bip_R_Foot").rotation_euler = (math.radians(-16), 0.0, 0.0)

        pose_bone(armature, "J_Bip_C_Spine").rotation_euler = (math.radians(5) + breath_pitch, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Chest").rotation_euler = (math.radians(3) + breath_pitch * 0.5, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Head").rotation_euler = (math.radians(-5), 0.0, 0.0)

        pose_bone(armature, "J_Bip_L_UpperArm").rotation_euler = (math.radians(-55), math.radians(12), math.radians(-35))
        pose_bone(armature, "J_Bip_L_LowerArm").rotation_euler = (0.0, 0.0, math.radians(-80))
        pose_bone(armature, "J_Bip_L_Hand").rotation_euler = (math.radians(10), math.radians(15), 0.0)

        pose_bone(armature, "J_Bip_R_UpperArm").rotation_euler = (math.radians(-55), math.radians(-12), math.radians(35))
        pose_bone(armature, "J_Bip_R_LowerArm").rotation_euler = (0.0, 0.0, math.radians(80))
        pose_bone(armature, "J_Bip_R_Hand").rotation_euler = (math.radians(10), math.radians(-15), 0.0)

        key_animation_frame(armature, "ride_idle", f)

    action.use_fake_user = True
    return action


def prepare_ride_walk_action(armature: bpy.types.Object) -> bpy.types.Action:
    """Synchronized 24-frame riding walk cycle (1.00s) matching horse_walk."""
    action = bpy.data.actions.get("ride_walk") or bpy.data.actions.new("ride_walk")
    armature.animation_data_create()
    armature.animation_data.action = action

    for f in range(0, 25, 2):
        reset_pose(armature)
        t_stride = (f / 24.0) * (2 * math.tau)
        t_cycle = (f / 24.0) * math.tau

        sway_roll = math.sin(t_cycle) * math.radians(1.5)
        pitch_bob = math.cos(t_stride) * math.radians(2.0)
        bounce_z = -math.sin(t_stride) * 0.010

        pose_bone(armature, "J_Bip_C_Hips").location = (0.0, 0.605 + bounce_z, -0.05)
        pose_bone(armature, "J_Bip_C_Hips").rotation_euler = (pitch_bob, 0.0, sway_roll)

        pose_bone(armature, "J_Bip_L_UpperLeg").rotation_euler = (math.radians(-38) - pitch_bob * 0.5, math.radians(-12), math.radians(-34))
        pose_bone(armature, "J_Bip_L_LowerLeg").rotation_euler = (math.radians(64) + pitch_bob * 0.3, math.radians(-6), math.radians(26))
        pose_bone(armature, "J_Bip_L_Foot").rotation_euler = (math.radians(-16), 0.0, 0.0)

        pose_bone(armature, "J_Bip_R_UpperLeg").rotation_euler = (math.radians(-38) - pitch_bob * 0.5, math.radians(12), math.radians(34))
        pose_bone(armature, "J_Bip_R_LowerLeg").rotation_euler = (math.radians(64) + pitch_bob * 0.3, math.radians(6), math.radians(-26))
        pose_bone(armature, "J_Bip_R_Foot").rotation_euler = (math.radians(-16), 0.0, 0.0)

        pose_bone(armature, "J_Bip_C_Spine").rotation_euler = (math.radians(6) - pitch_bob * 0.6, 0.0, -sway_roll * 0.6)
        pose_bone(armature, "J_Bip_C_Chest").rotation_euler = (math.radians(3) - pitch_bob * 0.3, 0.0, -sway_roll * 0.3)
        pose_bone(armature, "J_Bip_C_Head").rotation_euler = (math.radians(-6) + pitch_bob * 0.2, 0.0, 0.0)

        pose_bone(armature, "J_Bip_L_UpperArm").rotation_euler = (math.radians(-55) + pitch_bob * 0.4, math.radians(12), math.radians(-35))
        pose_bone(armature, "J_Bip_L_LowerArm").rotation_euler = (0.0, 0.0, math.radians(-80))
        pose_bone(armature, "J_Bip_L_Hand").rotation_euler = (math.radians(10), math.radians(15), 0.0)

        pose_bone(armature, "J_Bip_R_UpperArm").rotation_euler = (math.radians(-55) + pitch_bob * 0.4, math.radians(-12), math.radians(35))
        pose_bone(armature, "J_Bip_R_LowerArm").rotation_euler = (0.0, 0.0, math.radians(80))
        pose_bone(armature, "J_Bip_R_Hand").rotation_euler = (math.radians(10), math.radians(-15), 0.0)

        key_animation_frame(armature, "ride_walk", f)

    action.use_fake_user = True
    return action


def prepare_ride_run_action(armature: bpy.types.Object) -> bpy.types.Action:
    """Synchronized 8-frame rapid riding run cycle (0.333s) matching horse_run (10x faster stride)."""
    action = bpy.data.actions.get("ride_run") or bpy.data.actions.new("ride_run")
    armature.animation_data_create()
    armature.animation_data.action = action

    for f in range(0, 9):
        reset_pose(armature)
        t_stride = (f / 8.0) * (2 * math.tau)
        t_cycle = (f / 8.0) * math.tau

        sway_roll = math.sin(t_cycle) * math.radians(1.6)
        pitch_bob = math.cos(t_stride) * math.radians(2.2)
        bounce_z = -math.sin(t_stride) * 0.012

        pose_bone(armature, "J_Bip_C_Hips").location = (0.0, 0.605 + bounce_z, -0.05)
        pose_bone(armature, "J_Bip_C_Hips").rotation_euler = (pitch_bob, 0.0, sway_roll)

        pose_bone(armature, "J_Bip_L_UpperLeg").rotation_euler = (math.radians(-38) - pitch_bob * 0.5, math.radians(-12), math.radians(-34))
        pose_bone(armature, "J_Bip_L_LowerLeg").rotation_euler = (math.radians(64) + pitch_bob * 0.3, math.radians(-6), math.radians(26))
        pose_bone(armature, "J_Bip_L_Foot").rotation_euler = (math.radians(-16), 0.0, 0.0)

        pose_bone(armature, "J_Bip_R_UpperLeg").rotation_euler = (math.radians(-38) - pitch_bob * 0.5, math.radians(12), math.radians(34))
        pose_bone(armature, "J_Bip_R_LowerLeg").rotation_euler = (math.radians(64) + pitch_bob * 0.3, math.radians(6), math.radians(-26))
        pose_bone(armature, "J_Bip_R_Foot").rotation_euler = (math.radians(-16), 0.0, 0.0)

        # Forward riding lean with amplified galloping dynamic
        pose_bone(armature, "J_Bip_C_Spine").rotation_euler = (math.radians(16) - pitch_bob * 0.6, 0.0, -sway_roll * 0.6)
        pose_bone(armature, "J_Bip_C_Chest").rotation_euler = (math.radians(10) - pitch_bob * 0.4, 0.0, -sway_roll * 0.4)
        pose_bone(armature, "J_Bip_C_Head").rotation_euler = (math.radians(-6) + pitch_bob * 0.2, 0.0, 0.0)

        # Both hands hold reins firmly
        pose_bone(armature, "J_Bip_L_UpperArm").rotation_euler = (math.radians(-56) + pitch_bob * 0.4, math.radians(12), math.radians(-35))
        pose_bone(armature, "J_Bip_L_LowerArm").rotation_euler = (0.0, 0.0, math.radians(-80))
        pose_bone(armature, "J_Bip_L_Hand").rotation_euler = (math.radians(10), math.radians(15), 0.0)

        pose_bone(armature, "J_Bip_R_UpperArm").rotation_euler = (math.radians(-56) + pitch_bob * 0.4, math.radians(-12), math.radians(35))
        pose_bone(armature, "J_Bip_R_LowerArm").rotation_euler = (0.0, 0.0, math.radians(80))
        pose_bone(armature, "J_Bip_R_Hand").rotation_euler = (math.radians(10), math.radians(-15), 0.0)

        key_animation_frame(armature, "ride_run", f)

    action.use_fake_user = True
    return action


def prepare_ride_slash_action(armature: bpy.types.Object) -> bpy.types.Action:
    """Heroic, complete mounted sword slash along the horse's right flank:
    - Phase 1 (F0-F14): Chamber & High Wind-up over right shoulder, blade pointing up-back.
    - Phase 2 (F15-F23): Powerful downward-forward cleave slicing through beside right flank.
    - Phase 3 (F24-F32): Full follow-through cutting down and back past rider's knee/stirrup ("做完").
    - Phase 4 (F33-F42): Smooth circular recovery arc lifting sword back to ready combat stance.
    - Right hand grips sword with weapon grip; left hand holds reins firmly.
    - Lower body seated stably in saddle with zero clipping and natural galloping stride vibration.
    """
    action = bpy.data.actions.get("ride_slash") or bpy.data.actions.new("ride_slash")
    armature.animation_data_create()
    armature.animation_data.action = action
    action.fcurves.clear()

    keyframes = [
        # F0: Ready combat grip (hand beside saddle horn, sword pointing forward along right flank)
        (0,
         (8, 0, 0), (6, 0, 0), (-6, 0, 0),
         (-40, 15, 20), (-10, 0, 55), (90, 75, 0)),

        # F7: Initiating draw back & coiling (Right elbow pulls back and up)
        (7,
         (10, 3, -6), (8, 3, -8), (-4, 2, -6),
         (-10, 15, -10), (10, 0, 65), (0, 75, 45)),

        # F14: Peak High Wind-up (Cocked high over right shoulder, blade pointing up-back)
        (14,
         (12, 4, -12), (10, 4, -14), (-2, 2, -10),
         (30, 15, -25), (20, 0, 60), (-90, 90, 90)),

        # F19: Downward Cleave Flight (Driving forward-down along right flank)
        (19,
         (16, -2, 4), (12, -2, 4), (-2, 0, 4),
         (-10, 12, 25), (-5, 0, 40), (45, 60, 10)),

        # F23: Impact & Full Downward-Forward Cleave (Blade slicing through beside right flank)
        (23,
         (20, -5, 10), (16, -5, 10), (0, -2, 6),
         (-30, 10, 35), (-15, 0, 20), (90, 30, 0)),

        # F28: Full Follow-Through (Completed Slash: Sword swept through down-back past knee - "做完")
        (28,
         (16, -3, 6), (12, -3, 6), (-2, -1, 4),
         (-55, 0, 5), (-25, 0, 10), (60, 45, -75)),

        # F34: Low Arc Rise (Wrist relaxes, sword blade sweeps smoothly back up along flank)
        (34,
         (12, -1, 2), (9, -1, 2), (-4, 0, 2),
         (-50, 5, -5), (-20, 0, 30), (60, 40, -50)),

        # F38: Recovery Lift (Lifting back to ready position)
        (38,
         (10, 0, 0), (7, 0, 0), (-5, 0, 0),
         (-45, 10, 10), (-15, 0, 45), (75, 60, -20)),

        # F42: Seamless Return to Ready Stance
        (42,
         (8, 0, 0), (6, 0, 0), (-6, 0, 0),
         (-40, 15, 20), (-10, 0, 55), (90, 75, 0)),
    ]

    num_frames = 43
    for kf in keyframes:
        f, sp, ch, hd, rua, rla, rh = kf
        reset_pose(armature)

        t_stride = (f / float(num_frames)) * (4 * math.pi)
        bounce_z = -math.sin(t_stride) * 0.008
        pitch_bob = math.cos(t_stride) * math.radians(1.5)

        pb_hips = armature.pose.bones["J_Bip_C_Hips"]
        pb_hips.location = Vector((0.0, 0.605 + bounce_z, -0.05))
        pb_hips.rotation_quaternion = Euler((pitch_bob, 0.0, 0.0), 'XYZ').to_quaternion()
        pb_hips.keyframe_insert(data_path="location", frame=f)
        pb_hips.keyframe_insert(data_path="rotation_quaternion", frame=f)

        for side, sign in [("L", -1), ("R", 1)]:
            armature.pose.bones[f"J_Bip_{side}_UpperLeg"].rotation_quaternion = Euler((math.radians(-38), math.radians(sign * 12), math.radians(sign * 34)), 'XYZ').to_quaternion()
            armature.pose.bones[f"J_Bip_{side}_LowerLeg"].rotation_quaternion = Euler((math.radians(64), math.radians(sign * 6), math.radians(-sign * 26)), 'XYZ').to_quaternion()
            armature.pose.bones[f"J_Bip_{side}_Foot"].rotation_quaternion = Euler((math.radians(-16), 0.0, 0.0), 'XYZ').to_quaternion()
            for b in ["UpperLeg", "LowerLeg", "Foot"]:
                armature.pose.bones[f"J_Bip_{side}_{b}"].keyframe_insert(data_path="rotation_quaternion", frame=f)

        # Left hand holds reins firmly
        armature.pose.bones["J_Bip_L_UpperArm"].rotation_quaternion = Euler((math.radians(-56) + pitch_bob * 0.4, math.radians(12), math.radians(-35)), 'XYZ').to_quaternion()
        armature.pose.bones["J_Bip_L_LowerArm"].rotation_quaternion = Euler((0.0, 0.0, math.radians(-80)), 'XYZ').to_quaternion()
        armature.pose.bones["J_Bip_L_Hand"].rotation_quaternion = Euler((math.radians(10), math.radians(15), 0.0), 'XYZ').to_quaternion()
        for b in ["UpperArm", "LowerArm", "Hand"]:
            armature.pose.bones[f"J_Bip_L_{b}"].keyframe_insert(data_path="rotation_quaternion", frame=f)

        # Upper body & Right arm
        armature.pose.bones["J_Bip_C_Spine"].rotation_quaternion = Euler((math.radians(sp[0]), math.radians(sp[1]), math.radians(sp[2])), 'XYZ').to_quaternion()
        armature.pose.bones["J_Bip_C_Chest"].rotation_quaternion = Euler((math.radians(ch[0]), math.radians(ch[1]), math.radians(ch[2])), 'XYZ').to_quaternion()
        armature.pose.bones["J_Bip_C_Head"].rotation_quaternion = Euler((math.radians(hd[0]), math.radians(hd[1]), math.radians(hd[2])), 'XYZ').to_quaternion()
        armature.pose.bones["J_Bip_R_UpperArm"].rotation_quaternion = Euler((math.radians(rua[0]), math.radians(rua[1]), math.radians(rua[2])), 'XYZ').to_quaternion()
        armature.pose.bones["J_Bip_R_LowerArm"].rotation_quaternion = Euler((math.radians(rla[0]), math.radians(rla[1]), math.radians(rla[2])), 'XYZ').to_quaternion()
        armature.pose.bones["J_Bip_R_Hand"].rotation_quaternion = Euler((math.radians(rh[0]), math.radians(rh[1]), math.radians(rh[2])), 'XYZ').to_quaternion()

        for bname in ["J_Bip_C_Spine", "J_Bip_C_Chest", "J_Bip_C_Head", "J_Bip_R_UpperArm", "J_Bip_R_LowerArm", "J_Bip_R_Hand"]:
            armature.pose.bones[bname].keyframe_insert(data_path="rotation_quaternion", frame=f)

        apply_right_hand_grip(armature, f)
        apply_left_hand_grip(armature, f)

    for fc in action.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = 'BEZIER'

    action.use_fake_user = True
    return action


def prepare_ride_attack_action(armature: bpy.types.Object) -> bpy.types.Action:
    """Mirror of ride_slash for backwards compatibility under the ride_attack identifier."""
    act_slash = bpy.data.actions.get("ride_slash")
    act_att = bpy.data.actions.get("ride_attack") or bpy.data.actions.new("ride_attack")
    act_att.fcurves.clear()
    if act_slash:
        for fc in act_slash.fcurves:
            new_fc = act_att.fcurves.new(data_path=fc.data_path, index=fc.array_index)
            for kp in fc.keyframe_points:
                new_fc.keyframe_points.insert(kp.co.x, kp.co.y)
    armature.animation_data_create()
    armature.animation_data.action = act_att
    act_att.use_fake_user = True
    return act_att


def prepare_ride_thrust_action(armature: bpy.types.Object) -> bpy.types.Action:
    """Heroic mounted spear thrust along the horse's right flank:
    - Phase 1 (F0-F6): Ready combat couch (spear level beside waist/saddle, aiming forward).
    - Phase 2 (F7-F14): Draw-back & coiling (Right elbow pulls back and up behind torso, spear retracted & cocked).
    - Phase 3 (F15-F23): Explosive forward drive & thrust impact (Full arm punch forward along right flank).
    - Phase 4 (F24-F28): Impale hold & push (Cavalry charge momentum driving spear into target).
    - Phase 5 (F29-F42): Retraction & recovery arc back to ready combat couch.
    - Right hand grips spear firmly; left hand holds reins firmly.
    - Lower body seated stably in saddle with zero clipping and natural galloping stride vibration.
    """
    action = bpy.data.actions.get("ride_thrust") or bpy.data.actions.new("ride_thrust")
    armature.animation_data_create()
    armature.animation_data.action = action
    action.fcurves.clear()

    db_rh = armature.data.bones.get("J_Bip_R_Hand")
    spear_local_dir = (db_rh.matrix_local.to_3x3().inverted() @ Vector((0.0, -1.0, 0.0))).normalized()

    keyframes = [
        # F0: Ready combat couch (Spear held level beside right flank/saddle, aiming forward)
        (0,
         (8, 0, 0), (6, 0, 0), (-6, 0, 0),
         (-25, 5, 20), (0, 0, 65), Vector((-0.03, -0.99, -0.05))),

        # F7: Initiating draw-back & coiling (Right elbow pulls back and slightly up)
        (7,
         (10, 2, -4), (8, 2, -6), (-4, 1, -4),
         (-5, 10, -20), (0, 0, 75), Vector((-0.02, -0.99, -0.05))),

        # F14: Peak chamber (Elbow pulled well back behind torso, spear retracted & cocked)
        (14,
         (12, 4, -8), (10, 4, -10), (-2, 2, -6),
         (15, 15, -45), (0, 0, 70), Vector((-0.02, -0.99, -0.04))),

        # F19: Explosive forward drive (Arm punching forward, torso lunging)
        (19,
         (18, -2, 4), (14, -2, 4), (-2, 0, 2),
         (-15, 0, 35), (0, 0, 30), Vector((-0.03, -0.99, -0.06))),

        # F23: Maximum extension thrust impact (Full arm reach, driving spear tip into target)
        (23,
         (22, -4, 8), (18, -4, 8), (0, -1, 4),
         (-20, -5, 70), (0, 0, 5), Vector((-0.03, -0.99, -0.07))),

        # F28: Impale hold & push (Cavalry momentum driving through)
        (28,
         (22, -4, 8), (18, -4, 8), (0, -1, 4),
         (-20, -5, 70), (0, 0, 5), Vector((-0.03, -0.99, -0.07))),

        # F34: Retraction & pull-back (Pulling spear back along flank)
        (34,
         (16, -1, 2), (12, -1, 2), (-3, 0, 2),
         (-10, 5, 10), (0, 0, 50), Vector((-0.03, -0.99, -0.06))),

        # F38: Recovery lift back to couch stance
        (38,
         (10, 0, 0), (8, 0, 0), (-5, 0, 0),
         (-20, 5, 15), (0, 0, 60), Vector((-0.03, -0.99, -0.05))),

        # F42: Seamless loop return to ready combat couch
        (42,
         (8, 0, 0), (6, 0, 0), (-6, 0, 0),
         (-25, 5, 20), (0, 0, 65), Vector((-0.03, -0.99, -0.05))),
    ]

    num_frames = 43
    for kf in keyframes:
        f, sp, ch, hd, rua, rla, aim_dir = kf

        reset_pose(armature)

        t_stride = (f / float(num_frames)) * (4 * math.pi)
        bounce_z = -math.sin(t_stride) * 0.008
        pitch_bob = math.cos(t_stride) * math.radians(1.5)

        pb_hips = armature.pose.bones["J_Bip_C_Hips"]
        pb_hips.location = Vector((0.0, 0.605 + bounce_z, -0.05))
        pb_hips.rotation_quaternion = Euler((pitch_bob, 0.0, 0.0), 'XYZ').to_quaternion()
        pb_hips.keyframe_insert(data_path="location", frame=f)
        pb_hips.keyframe_insert(data_path="rotation_quaternion", frame=f)

        for side, sign in [("L", -1), ("R", 1)]:
            armature.pose.bones[f"J_Bip_{side}_UpperLeg"].rotation_quaternion = Euler((math.radians(-38), math.radians(sign * 12), math.radians(sign * 34)), 'XYZ').to_quaternion()
            armature.pose.bones[f"J_Bip_{side}_LowerLeg"].rotation_quaternion = Euler((math.radians(64), math.radians(sign * 6), math.radians(-sign * 26)), 'XYZ').to_quaternion()
            armature.pose.bones[f"J_Bip_{side}_Foot"].rotation_quaternion = Euler((math.radians(-16), 0.0, 0.0), 'XYZ').to_quaternion()
            for b in ["UpperLeg", "LowerLeg", "Foot"]:
                armature.pose.bones[f"J_Bip_{side}_{b}"].keyframe_insert(data_path="rotation_quaternion", frame=f)

        # Left hand holds reins firmly
        armature.pose.bones["J_Bip_L_UpperArm"].rotation_quaternion = Euler((math.radians(-56) + pitch_bob * 0.4, math.radians(12), math.radians(-35)), 'XYZ').to_quaternion()
        armature.pose.bones["J_Bip_L_LowerArm"].rotation_quaternion = Euler((0.0, 0.0, math.radians(-80)), 'XYZ').to_quaternion()
        armature.pose.bones["J_Bip_L_Hand"].rotation_quaternion = Euler((math.radians(10), math.radians(15), 0.0), 'XYZ').to_quaternion()
        for b in ["UpperArm", "LowerArm", "Hand"]:
            armature.pose.bones[f"J_Bip_L_{b}"].keyframe_insert(data_path="rotation_quaternion", frame=f)

        # Upper body & Right arm
        armature.pose.bones["J_Bip_C_Spine"].rotation_quaternion = Euler((math.radians(sp[0]), math.radians(sp[1]), math.radians(sp[2])), 'XYZ').to_quaternion()
        armature.pose.bones["J_Bip_C_Chest"].rotation_quaternion = Euler((math.radians(ch[0]), math.radians(ch[1]), math.radians(ch[2])), 'XYZ').to_quaternion()
        armature.pose.bones["J_Bip_C_Head"].rotation_quaternion = Euler((math.radians(hd[0]), math.radians(hd[1]), math.radians(hd[2])), 'XYZ').to_quaternion()
        armature.pose.bones["J_Bip_R_UpperArm"].rotation_quaternion = Euler((math.radians(rua[0]), math.radians(rua[1]), math.radians(rua[2])), 'XYZ').to_quaternion()
        armature.pose.bones["J_Bip_R_LowerArm"].rotation_quaternion = Euler((math.radians(rla[0]), math.radians(rla[1]), math.radians(rla[2])), 'XYZ').to_quaternion()

        bpy.context.view_layer.update()

        # Hand orientation solved to precisely aim spear
        pb_rh = armature.pose.bones["J_Bip_R_Hand"]
        parent_pb = pb_rh.parent
        rh_w_rot = (armature.matrix_world @ pb_rh.matrix).to_3x3()
        curr_dir = (rh_w_rot @ spear_local_dir).normalized()
        delta_w = curr_dir.rotation_difference(aim_dir.normalized()).to_matrix()
        new_w_rot = delta_w @ rh_w_rot
        parent_w_rot = (armature.matrix_world @ parent_pb.matrix).to_3x3()
        basis_rot = (
            db_rh.matrix_local.to_3x3().inverted()
            @ parent_pb.bone.matrix_local.to_3x3()
            @ parent_w_rot.inverted()
            @ new_w_rot
        )
        pb_rh.rotation_quaternion = basis_rot.to_quaternion()

        for bname in ["J_Bip_C_Spine", "J_Bip_C_Chest", "J_Bip_C_Head", "J_Bip_R_UpperArm", "J_Bip_R_LowerArm", "J_Bip_R_Hand"]:
            armature.pose.bones[bname].keyframe_insert(data_path="rotation_quaternion", frame=f)

        apply_right_hand_grip(armature, f)
        apply_left_hand_grip(armature, f)

    for fc in action.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = 'BEZIER'

    action.use_fake_user = True
    return action


def prepare_walk_slash_action(armature: bpy.types.Object) -> bpy.types.Action:
    """Ground on-foot sword slash action from Standing Melee Combo Attack Ver. 3.fbx (83 frames)."""
    fbx = os.path.join(PROJECT_DIR, "assets", "animations", "Standing Melee Combo Attack Ver. 3.fbx")
    if os.path.exists(fbx):
        return retarget_mixamo_fbx_to_action(armature, fbx, "walk_slash", lock_root_xy=True)
    action = bpy.data.actions.get("walk_slash") or bpy.data.actions.new("walk_slash")
    action.use_fake_user = True
    return action


def prepare_all_actions(armature: bpy.types.Object) -> list[str]:
    # Unlock J_Bip_C_Hips use_connect so translation can move the hips
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode="EDIT")
    eb = armature.data.edit_bones.get("J_Bip_C_Hips")
    if eb:
        eb.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")

    actions = [
        prepare_tpose_action(armature),
        prepare_idle_action(armature),
        prepare_walk_action(armature),
        prepare_run_action(armature),
        prepare_guard_action(armature),
        prepare_hit_action(armature),
        prepare_hit_back_action(armature),
        prepare_knockback_action(armature),
        prepare_down_action(armature),
        prepare_attack_unarmed_action(armature),
        prepare_attack_sword_action(armature),
        bpy.data.actions.get("attack_sword"),
        prepare_walk_slash_action(armature),
        prepare_attack_spear_action(armature),
        prepare_attack_axe_action(armature),
        prepare_attack_hammer_action(armature),
        prepare_attack_dagger_action(armature),
        prepare_attack_bow_action(armature),
        prepare_attack_crossbow_action(armature),
        prepare_ride_idle_action(armature),
        prepare_ride_walk_action(armature),
        prepare_ride_run_action(armature),
        prepare_ride_slash_action(armature),
        prepare_ride_attack_action(armature),
        prepare_ride_thrust_action(armature),
    ]
    for pb in armature.pose.bones:
        pb.rotation_mode = "QUATERNION"

    return [a.name for a in actions]


def trim_body_under_clothes(obj: bpy.types.Object) -> None:
    """Keep only the neck and hand geometry intentionally left uncovered."""
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    delete_faces = []
    for face in bm.faces:
        center = face.calc_center_median()
        keep_neck = center.z >= 1.45 and abs(center.x) <= 0.14
        keep_hand = 1.20 <= center.z <= 1.50 and abs(center.x) >= 0.52
        if not (keep_neck or keep_hand):
            delete_faces.append(face)
    bmesh.ops.delete(bm, geom=delete_faces, context="FACES")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def strip_source_body_clothing(obj: bpy.types.Object) -> None:
    """Turn the imported clothed VRM body into the actual skin base.

    HairSample_Male stores skin, hoodie, trousers, and shoes in one mesh.  The
    VRM material boundary is the only reliable source boundary, so remove the
    non-skin faces before any outfit is copied from the body surface.
    """
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    clothing_faces = [face for face in bm.faces if face.material_index > 0]
    if not clothing_faces:
        bm.free()
        raise RuntimeError("standard anime source body has no clothing faces to strip")
    bmesh.ops.delete(bm, geom=clothing_faces, context="FACES")
    loose_vertices = [vertex for vertex in bm.verts if not vertex.link_faces]
    bmesh.ops.delete(bm, geom=loose_vertices, context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    obj["worldgoing_source_body_only"] = True
    obj["worldgoing_removed_clothing_faces"] = len(clothing_faces)


def main() -> None:
    if not os.path.exists(SOURCE_VRM):
        raise FileNotFoundError(SOURCE_VRM)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    clear_scene()
    load_vrm_addon(ADDON_DIR)
    bpy.ops.import_scene.vrm(filepath=SOURCE_VRM, use_addon_preferences=True)
    bpy.context.view_layer.update()

    armature = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    body = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.name == "Body")
    face = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.name == "Face")
    hair = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.name == "Hair001")
    underwear_main = material("Worldgoing_Underwear_Main", (0.18, 0.22, 0.28), roughness=0.88)
    underwear_accent = material("Worldgoing_Underwear_Accent", (0.08, 0.10, 0.14), roughness=0.84)
    underwear_shadow = material("Worldgoing_Underwear_Shadow", (0.12, 0.15, 0.20), roughness=0.90)
    leather = material("Worldgoing_LightLeather", (0.070, 0.022, 0.007), roughness=0.90)
    leather_body = material("Worldgoing_LightLeather_Body", (0.155, 0.052, 0.012), roughness=0.88)
    leather_edge = material("Worldgoing_LightLeather_Edge", (0.235, 0.090, 0.014), metallic=0.08, roughness=0.88)
    cloth = material("Worldgoing_Armor_Cloth", (0.032, 0.060, 0.082), roughness=0.94)
    cape_mat = material("Worldgoing_Cape_Travel", (0.018, 0.055, 0.10), roughness=0.94)
    steel = material("Worldgoing_LongSword_Steel", (0.75, 0.78, 0.82), metallic=0.92, roughness=0.22)
    grip = material("Worldgoing_LongSword_Grip", (0.080, 0.030, 0.010), roughness=0.88)
    gold = material("Worldgoing_Gold_Detail", (0.85, 0.62, 0.12), metallic=0.85, roughness=0.28)
    silver = material("Worldgoing_Silver_Detail", (0.80, 0.82, 0.85), metallic=0.85, roughness=0.25)
    wood = material("Worldgoing_Hardwood", (0.18, 0.09, 0.04), roughness=0.68)
    tassel = material("Worldgoing_Spear_Tassel", (0.75, 0.08, 0.10), roughness=0.85)
    string_mat = material("Worldgoing_Bow_String", (0.92, 0.92, 0.90), roughness=0.35)
    shield_mat = material("Worldgoing_HeaterShield", (0.020, 0.045, 0.095), roughness=0.82)

    # 1. Extract conformal layers from raw unstripped VRM mesh
    outfit_objects = make_outfit(body, armature, underwear_main, underwear_accent, underwear_shadow) + load_chinese_lining(armature)
    boots_objects = make_boots(body, armature, leather_body, leather_edge, gold)
    armor_objects = make_armor_details(body, armature, leather, leather_body, leather_edge, cloth, steel, gold)

    cape_objects = make_cape(armature, cape_mat, gold, silver)
    chinese_cape_objects = make_chinese_cape(armature, is_female=False, create_rigid_fn=create_bone_rigid_component)
    cape_folds: list[bpy.types.Object] = []
    helmet_objects = make_leather_helmet(armature, leather, leather_body, leather_edge, steel, gold)
    iron_helmet_objects = make_chinese_iron_helmet(armature, is_female=False, create_rigid_fn=create_bone_rigid_component)
    steel_helmet_objects = make_chinese_steel_helmet(armature, is_female=False, create_rigid_fn=create_bone_rigid_component)
    chinese_leather_objects, mingguang_helmet_objects = load_chinese_gear(armature)
    western_armor_objects, western_helmet_objects, western_boots_objects = load_western_iron(armature)
    all_helmet_objects = helmet_objects + iron_helmet_objects + steel_helmet_objects + mingguang_helmet_objects + load_chinese_leather_helmet(armature) + western_helmet_objects + load_cloth_hats(armature)
    longsword_objects = make_longsword(armature, steel, grip, gold, leather)
    spear_objects = make_spear(armature, wood, steel, gold, tassel)
    axe_objects = make_axe(armature, wood, steel, gold, grip)
    hammer_objects = make_hammer(armature, wood, steel, gold, grip)
    dagger_objects = make_dagger(armature, steel, gold, grip)
    bow_objects = make_bow(armature, wood, gold, grip, string_mat)
    crossbow_objects = make_crossbow(armature, wood, steel, gold, string_mat)
    all_weapon_objects = (
        longsword_objects
        + spear_objects
        + axe_objects
        + hammer_objects
        + dagger_objects
        + bow_objects
        + crossbow_objects
    )
    shield_objects = make_shield(armature, shield_mat, gold, silver, leather)

    # 2. Strip clothing from body so body_skin becomes 100% pure skin
    strip_source_body_clothing(body)

    body_full = copy_mesh(body, "Body_Standard_Male_Full", "body", "body_standard_male_full")
    body_skin = copy_material_subset(body, "Body_Standard_Male", {0}, "body", "body_standard_male")

    iron_boots_objects = make_chinese_iron_boots(armature, source_raw_body=body_skin, is_female=False, create_rigid_fn=create_bone_rigid_component)
    mingguang_boots_objects = make_mingguang_boots(armature, source_raw_body=body_skin, is_female=False, create_rigid_fn=create_bone_rigid_component)
    all_boots_objects = boots_objects + iron_boots_objects + mingguang_boots_objects + load_chinese_leather_boots(armature) + western_boots_objects + load_medieval_shoes(armature)

    iron_armor_objects = make_chinese_iron_armor(armature, source_raw_body=body_skin, is_female=False, create_rigid_fn=create_bone_rigid_component)
    mingguang_armor_objects = make_mingguang_armor(armature, source_raw_body=body_skin, is_female=False, create_rigid_fn=create_bone_rigid_component)
    all_armor_objects = armor_objects + iron_armor_objects + mingguang_armor_objects + chinese_leather_objects + western_armor_objects
    face_one = create_baked_face_variant(face, "Face_Standard_01", "face_standard_01", {}, armature)
    face_two = create_baked_face_variant(face, "Face_Standard_02", "face_standard_02", {"Fcl_ALL_Joy": 1.0, "Fcl_MTH_Joy": 1.0}, armature)
    face_three = create_baked_face_variant(face, "Face_Standard_03", "face_standard_03", {"Fcl_ALL_Angry": 1.0, "Fcl_BRW_Angry": 1.0, "Fcl_EYE_Angry": 1.0}, armature)
    face_four = create_baked_face_variant(face, "Face_Standard_04", "face_standard_04", {"Fcl_ALL_Fun": 0.85, "Fcl_ALL_Surprised": 0.40, "Fcl_BRW_Joy": 0.80}, armature)
    hair_material = next((slot for slot in hair.data.materials if slot is not None), None)
    if hair_material is None:
        hair_material = material("Worldgoing_Hair_Accent", (0.025, 0.010, 0.035), roughness=0.76)

    hair_obj = make_male_hair_spiky_hero(hair, "Hair_Short_01", "hair_short_01", hair_material, armature)
    hair_two = make_male_hair_undercut(hair, "Hair_Short_02", "hair_short_02", hair_material, armature)
    hair_three = make_male_hair_wild_spiky(hair, "Hair_Short_03", "hair_short_03", hair_material, armature)
    hair_four_parts = make_male_hair_topknot(hair, "Hair_Short_04", "hair_short_04", hair_material, gold, armature)

    skin = material("Worldgoing_Skin_Stable", (0.72, 0.27, 0.13), roughness=0.78)
    body_skin.data.materials[0] = skin
    body_full.data.materials.clear()
    body_full.data.materials.append(skin)
    for polygon in body_full.data.polygons:
        polygon.material_index = 0
    body_full["worldgoing_full_body_base"] = True
    body_full.hide_render = True
    body_full.hide_viewport = True

    for source_obj in (body, face, hair):
        source_obj.hide_render = True
        source_obj.hide_viewport = True
    for face_var_obj in (face_two, face_three, face_four):
        face_var_obj.hide_render = True
        face_var_obj.hide_viewport = True
    for hair_var_obj in [hair_two, hair_three, *hair_four_parts]:
        hair_var_obj.hide_render = True
        hair_var_obj.hide_viewport = True
    for extra_obj in all_armor_objects + iron_boots_objects + mingguang_boots_objects + cape_objects + chinese_cape_objects + cape_folds + all_weapon_objects + shield_objects + all_helmet_objects:
        extra_obj.hide_render = True
        extra_obj.hide_viewport = True
    for obj in [body_skin, face_one, hair_obj, *outfit_objects, *boots_objects]:
        obj.hide_render = False
        obj.hide_viewport = False

    export_objects = [
        armature, body_full, body_skin, *outfit_objects,
        face_one, face_two, face_three, face_four,
        hair_obj, hair_two, hair_three, *hair_four_parts,
        *all_armor_objects, *cape_objects, *chinese_cape_objects, *cape_folds, *all_weapon_objects, *shield_objects, *all_boots_objects,
        *all_helmet_objects,
    ]
    action_names = prepare_all_actions(armature)
    bind_cape_action_tracks(armature, chinese_cape_objects + mingguang_helmet_objects)
    add_scene_preview([body_skin, *outfit_objects, face_one, hair_obj, *armor_objects, *cape_objects, *cape_folds, *longsword_objects, *shield_objects, *boots_objects])

    from repair_character_audit import apply_repairs
    repaired_parts = [obj for obj in export_objects if obj != armature]
    apply_repairs(armature, repaired_parts, sys.modules[__name__], False)
    from load_authored_weapon_materials import load_weapon_materials
    repaired_parts.extend(load_weapon_materials(armature))
    from load_authored_medieval_cloth import load_medieval_cloth
    cloth_parts = load_medieval_cloth(armature)
    repaired_parts.extend(cloth_parts)
    armor_objects.extend(cloth_parts)
    from load_authored_gendered_hair import load_gendered_hair
    repaired_parts.extend(load_gendered_hair(armature, False))
    from load_authored_neutral_faces import load_neutral_faces
    repaired_parts.extend(load_neutral_faces(armature, False))
    from refine_body_joints import refine_body_joints
    refine_body_joints(armature, repaired_parts)
    from fit_armor_bracers import fit_armor_bracers
    fit_armor_bracers(armature, repaired_parts)
    from ensure_morph_uv import ensure_blender_morph_uv
    ensure_blender_morph_uv(repaired_parts)
    export_objects = [armature, *repaired_parts]

    bpy.ops.object.select_all(action="DESELECT")
    for obj in export_objects:
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = armature
    legacy_clips = Path(LEGACY_ANIMATION_SOURCE).read_bytes() if Path(LEGACY_ANIMATION_SOURCE).exists() else None
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_GLB,
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_frame_range=False,
        export_frame_step=1,
        export_force_sampling=False,
        export_optimize_disable_viewport=True,
        export_skins=True,
        export_morph=True,
    )
    if legacy_clips:
        from author_chinese_cape import preserve_legacy_clips
        preserve_legacy_clips('male', Path(OUTPUT_GLB), legacy_clips, prune_duplicates=True)
    bpy.ops.object.select_all(action="DESELECT")
    body_full.hide_render = True
    body_full.hide_viewport = True
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND)

    metadata = {
        "asset_id": "standard_anime_male_character_pack",
        "source": "HairSample_Male.vrm",
        "hair_style_ids": [f"hair_male_{i:02d}" for i in range(1, 9)],
        "art_direction_reference": "res://assets/doll/reference/male_body_v2_highres.png",
        "parts": {slot: [obj.name for obj in repaired_parts if obj.get("worldgoing_component_slot") == slot]
                  for slot in ("body", "face", "hair", "helmet", "outfit", "armor", "cape", "weapon", "shield", "boots")},
        "animations": action_names,
        "walk_frames": FRAME_END - FRAME_START,
        "skeleton": "Armature",
    }
    with open(OUTPUT_METADATA, "w", encoding="utf-8") as handle:
        json.dump(metadata, handle, ensure_ascii=False, indent=2)
    print(
        "WORLDGOING_STANDARD_ANIME_CHARACTER_PACK_BUILD_PASS "
        f"parts={sum(len(value) for value in metadata['parts'].values())} "
        f"face_options={len(metadata['parts']['face'])} actions={action_names} "
        f"blend={OUTPUT_BLEND} glb={OUTPUT_GLB}"
    )
    bpy.ops.wm.quit_blender()


if __name__ == "__main__":
    main()
