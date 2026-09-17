"""Build real, modular 3D female character pack with stripped pure body, beautiful V-cut underwear, upright head pitch, forward facing shield, and distinct baked faces."""

import json
import math
import os
import sys
from pathlib import Path

import bmesh
import bpy
import mathutils
from mathutils import Vector, Matrix, Euler, Quaternion

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
from make_chinese_cape import make_chinese_cape, bind_cape_action_tracks
from load_authored_chinese_gear import load_chinese_gear
from load_authored_western_plate import load_western_iron
from load_authored_chinese_leather_helmet import load_chinese_leather_helmet
from load_authored_chinese_lining import load_chinese_lining


PROJECT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SOURCE_VRM = os.environ.get(
    "WORLDGOING_SOURCE_VRM",
    os.path.join(PROJECT_DIR, ".tools", "standard_anime_base", "HairSample_Female.vrm"),
)
ADDON_DIR = os.environ.get(
    "WORLDGOING_VRM_ADDON",
    os.path.join(PROJECT_DIR, ".tools", "standard_anime_base", "io_scene_vrm"),
)
SWORD_SHIELD_PACK = os.path.join(PROJECT_DIR, "assets", "animations", "Pro Sword and Shield Pack")

OUTPUT_DIR = os.path.join(PROJECT_DIR, "assets", "characters", "human", "q35")
OUTPUT_BLEND = os.path.join(OUTPUT_DIR, "standard_anime_female_character_pack.blend")
OUTPUT_GLB = os.path.join(OUTPUT_DIR, "standard_anime_female_character_pack.glb")
OUTPUT_METADATA = os.path.join(OUTPUT_DIR, "standard_anime_female_character_pack.json")
LEGACY_ANIMATION_SOURCE = OUTPUT_GLB
PREVIEW_DIR = os.path.join(PROJECT_DIR, ".visual_captures", "standard_anime_female_character_pack", "blender")
TRACE_LOG = os.path.join(PROJECT_DIR, ".godot-temp", "female_build_trace.log")


def disk_log(msg: str) -> None:
    os.makedirs(os.path.dirname(TRACE_LOG), exist_ok=True)
    with open(TRACE_LOG, "a", encoding="utf-8") as handle:
        handle.write(f"{msg}\n")
        handle.flush()
    print(msg, flush=True)


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
    obj["worldgoing_character_part"] = True
    obj["worldgoing_component_slot"] = slot
    obj["worldgoing_visual_id"] = visual_id


def copy_mesh(
    source_obj: bpy.types.Object,
    name: str,
    slot: str,
    visual_id: str,
    armature: bpy.types.Object,
) -> bpy.types.Object:
    obj = source_obj.copy()
    obj.name = name
    obj.data = source_obj.data.copy()
    obj.data.name = f"{name}Mesh"
    bpy.context.collection.objects.link(obj)
    for mod in obj.modifiers:
        if mod.type == "ARMATURE":
            mod.object = armature
    obj.parent = armature
    obj.matrix_parent_inverse = armature.matrix_world.inverted()
    component_props(obj, slot, visual_id)
    return obj


def material(
    name: str,
    color: tuple[float, float, float],
    roughness: float = 0.5,
    metallic: float = 0.0,
) -> bpy.types.Material:
    result = bpy.data.materials.get(name) or bpy.data.materials.new(name=name)
    result.use_nodes = True
    nodes = result.node_tree.nodes
    links = result.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    return result


def strip_source_body_clothing(obj: bpy.types.Object) -> None:
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    clothing_faces = [face for face in bm.faces if face.material_index > 0]
    if not clothing_faces:
        bm.free()
        raise RuntimeError("Female VRM source body has no clothing faces to strip")
    bmesh.ops.delete(bm, geom=clothing_faces, context="FACES")
    loose_vertices = [vertex for vertex in bm.verts if not vertex.link_faces]
    bmesh.ops.delete(bm, geom=loose_vertices, context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()
    obj["worldgoing_source_body_only"] = True
    obj["worldgoing_removed_clothing_faces"] = len(clothing_faces)


# =========================================================================
# 1. Distinct Shape-Key Baked Face Variants (Exact Geometric Math + Shader Preservation)
# =========================================================================

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


# =========================================================================
# 2. Female-Specific Clothing: Pure Skin, Beautiful V-Cut Underwear & Boots
# =========================================================================

def make_female_body_skin(
    source_body: bpy.types.Object,
    armature: bpy.types.Object,
) -> bpy.types.Object:
    obj = copy_mesh(source_body, "Body_Standard_Female", "body", "female_standard_anime_body_only", armature)
    strip_source_body_clothing(obj)
    skin_mat = bpy.data.materials.get("F00_002_02_Body_00_SKIN")
    obj.data.materials.clear()
    if skin_mat:
        obj.data.materials.append(skin_mat)
    for poly in obj.data.polygons:
        poly.material_index = 0
        poly.use_smooth = True
    obj["worldgoing_female_skin"] = True
    return obj


def make_female_underwear(
    source_body: bpy.types.Object,
    armature: bpy.types.Object,
    underwear_mat: bpy.types.Material,
) -> list[bpy.types.Object]:
    parts = []

    # 1. Underwear Top (Sports Bra Bandeau from Skin Mesh)
    obj_top = copy_mesh(source_body, "Outfit_Underlayer_01_Top", "outfit", "outfit_underlayer_01", armature)
    bm_top = bmesh.new()
    bm_top.from_mesh(obj_top.data)
    bm_top.faces.ensure_lookup_table()
    del_top = [
        f for f in bm_top.faces
        if not (1.05 <= f.calc_center_median().z <= 1.28 and abs(f.calc_center_median().x) <= 0.17)
    ]
    bmesh.ops.delete(bm_top, geom=del_top, context="FACES")
    bmesh.ops.bisect_plane(
        bm_top, geom=bm_top.faces[:] + bm_top.edges[:] + bm_top.verts[:],
        plane_co=(0, 0, 1.240), plane_no=(0, 0, 1), clear_inner=False, clear_outer=True
    )
    bmesh.ops.bisect_plane(
        bm_top, geom=bm_top.faces[:] + bm_top.edges[:] + bm_top.verts[:],
        plane_co=(0, 0, 1.070), plane_no=(0, 0, -1), clear_inner=False, clear_outer=True
    )
    bm_top.normal_update()
    for v in bm_top.verts:
        if v.link_faces and v.normal.length > 0:
            v.co += v.normal.normalized() * 0.0018
    loose = [v for v in bm_top.verts if not v.link_faces]
    bmesh.ops.delete(bm_top, geom=loose, context="VERTS")
    bmesh.ops.recalc_face_normals(bm_top, faces=bm_top.faces)
    bm_top.to_mesh(obj_top.data)
    bm_top.free()
    obj_top.data.update()
    obj_top.data.materials.clear()
    obj_top.data.materials.append(underwear_mat)
    for p in obj_top.data.polygons:
        p.material_index = 0
        p.use_smooth = True
    parts.append(obj_top)

    # 2. Underwear Bottom (Fitted Panties from Skin Mesh - Smooth Lines, No Skirt)
    obj_bot = copy_mesh(source_body, "Outfit_Underlayer_01_UnderwearBottom", "outfit", "outfit_underlayer_01", armature)
    bm_bot = bmesh.new()
    bm_bot.from_mesh(obj_bot.data)
    bm_bot.faces.ensure_lookup_table()

    del_faces = [
        f for f in bm_bot.faces
        if not (0.72 <= f.calc_center_median().z <= 0.98 and abs(f.calc_center_median().x) <= 0.17)
    ]
    bmesh.ops.delete(bm_bot, geom=del_faces, context="FACES")

    # Clean horizontal waistline covering painted base texture
    bmesh.ops.bisect_plane(
        bm_bot, geom=bm_bot.faces[:] + bm_bot.edges[:] + bm_bot.verts[:],
        plane_co=(0, 0, 0.965), plane_no=(0, 0, 1), clear_inner=False, clear_outer=True
    )
    # Bottom crotch trim
    bmesh.ops.bisect_plane(
        bm_bot, geom=bm_bot.faces[:] + bm_bot.edges[:] + bm_bot.verts[:],
        plane_co=(0, 0, 0.740), plane_no=(0, 0, -1), clear_inner=False, clear_outer=True
    )
    # Left leg opening
    bmesh.ops.bisect_plane(
        bm_bot, geom=bm_bot.faces[:] + bm_bot.edges[:] + bm_bot.verts[:],
        plane_co=(0.040, 0, 0.750), plane_no=(0.60, 0.15, -0.78), clear_inner=False, clear_outer=True
    )
    # Right leg opening
    bmesh.ops.bisect_plane(
        bm_bot, geom=bm_bot.faces[:] + bm_bot.edges[:] + bm_bot.verts[:],
        plane_co=(-0.040, 0, 0.750), plane_no=(-0.60, 0.15, -0.78), clear_inner=False, clear_outer=True
    )

    bm_bot.normal_update()
    for v in bm_bot.verts:
        if v.link_faces and v.normal.length > 0:
            v.co += v.normal.normalized() * 0.0018
    loose = [v for v in bm_bot.verts if not v.link_faces]
    bmesh.ops.delete(bm_bot, geom=loose, context="VERTS")
    bmesh.ops.recalc_face_normals(bm_bot, faces=bm_bot.faces)
    bm_bot.to_mesh(obj_bot.data)
    bm_bot.free()
    obj_bot.data.update()
    obj_bot.data.materials.clear()
    obj_bot.data.materials.append(underwear_mat)
    for p in obj_bot.data.polygons:
        p.material_index = 0
        p.use_smooth = True
    parts.append(obj_bot)

    return parts


def make_female_boots(
    source_body: bpy.types.Object,
    armature: bpy.types.Object,
    leather_body: bpy.types.Material,
    leather_cuff: bpy.types.Material,
) -> list[bpy.types.Object]:
    parts = []
    visual_id = "boots_leather_01"

    for side, sign in (("L", 1.0), ("R", -1.0)):
        obj_foot = copy_mesh(source_body, f"Boots_Leather_01_Foot_{side}", "boots", visual_id, armature)
        bm = bmesh.new()
        bm.from_mesh(obj_foot.data)
        bm.faces.ensure_lookup_table()
        del_faces = []
        for f in bm.faces:
            c = f.calc_center_median()
            is_side = (c.x >= 0) if sign > 0 else (c.x <= 0)
            if not (c.z <= 0.35 and is_side):
                del_faces.append(f)
        bmesh.ops.delete(bm, geom=del_faces, context="FACES")
        bmesh.ops.bisect_plane(
            bm,
            geom=bm.faces[:] + bm.edges[:] + bm.verts[:],
            plane_co=(0, 0, 0.280),
            plane_no=(0, 0, 1),
            clear_inner=False,
            clear_outer=True,
        )
        bm.normal_update()
        for v in bm.verts:
            if v.link_faces and v.normal.length > 0:
                v.co += v.normal.normalized() * 0.0045
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(obj_foot.data)
        bm.free()
        obj_foot.data.update()
        obj_foot.data.materials.clear()
        obj_foot.data.materials.append(leather_body)
        for p in obj_foot.data.polygons:
            p.material_index = 0
            p.use_smooth = True
        parts.append(obj_foot)

        obj_cuff = copy_mesh(source_body, f"Boots_Leather_01_Cuff_{side}", "boots", visual_id, armature)
        bm = bmesh.new()
        bm.from_mesh(obj_cuff.data)
        bm.faces.ensure_lookup_table()
        del_cuffs = []
        for f in bm.faces:
            c = f.calc_center_median()
            is_side = (c.x >= 0) if sign > 0 else (c.x <= 0)
            if not (0.25 <= c.z <= 0.32 and is_side):
                del_cuffs.append(f)
        bmesh.ops.delete(bm, geom=del_cuffs, context="FACES")
        bmesh.ops.bisect_plane(
            bm,
            geom=bm.faces[:] + bm.edges[:] + bm.verts[:],
            plane_co=(0, 0, 0.250),
            plane_no=(0, 0, -1),
            clear_inner=False,
            clear_outer=True,
        )
        bmesh.ops.bisect_plane(
            bm,
            geom=bm.faces[:] + bm.edges[:] + bm.verts[:],
            plane_co=(0, 0, 0.300),
            plane_no=(0, 0, 1),
            clear_inner=False,
            clear_outer=True,
        )
        bm.normal_update()
        for v in bm.verts:
            if v.link_faces and v.normal.length > 0:
                v.co += v.normal.normalized() * 0.0070
        loose = [v for v in bm.verts if not v.link_faces]
        bmesh.ops.delete(bm, geom=loose, context="VERTS")
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(obj_cuff.data)
        bm.free()
        obj_cuff.data.update()
        obj_cuff.data.materials.clear()
        obj_cuff.data.materials.append(leather_cuff)
        for p in obj_cuff.data.polygons:
            p.material_index = 0
            p.use_smooth = True
        parts.append(obj_cuff)

    return parts


# =========================================================================
# 3. Female Hair 01..04 with Anti-Clipping Geometry & Bone Weighting
# =========================================================================

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


def filter_female_hair_islands(source_hair: bpy.types.Object, name: str, visual_id: str, armature: bpy.types.Object, hair_mat: bpy.types.Material, remove_left: bool, remove_right: bool) -> bpy.types.Object:
    """Filters twintails while preserving 100% of the skull cap, neck coverage, bangs, and cat ears."""
    hair_obj = copy_mesh(source_hair, name, "hair", visual_id, armature)
    bm = bmesh.new()
    bm.from_mesh(hair_obj.data)
    bm.faces.ensure_lookup_table()
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
            # Remove cat ear tufts from crown:
            if max_z > 1.65 and abs(avg_x) > 0.07:
                del_faces.extend(island)
            if min_z < 1.35 and max_z < 1.61:
                if remove_left and avg_x < -0.10:
                    del_faces.extend(island)
                elif remove_right and avg_x > 0.10:
                    del_faces.extend(island)
    bmesh.ops.delete(bm, geom=del_faces, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(hair_obj.data)
    bm.free()
    hair_obj.data.update()
    hair_obj.data.materials.clear()
    hair_obj.data.materials.append(hair_mat)
    hair_obj.vertex_groups.clear()
    vg_head = hair_obj.vertex_groups.new(name="J_Bip_C_Head")
    vg_head.add(list(range(len(hair_obj.data.vertices))), 1.0, "REPLACE")
    return hair_obj


def make_female_hair_twintails(source_hair: bpy.types.Object, name: str, visual_id: str, armature: bpy.types.Object, hair_mat: bpy.types.Material) -> bpy.types.Object:
    """Hair 01: Authentic complete anime twin-tails with full 360-degree skull cap coverage."""
    return filter_female_hair_islands(source_hair, name, visual_id, armature, hair_mat, remove_left=False, remove_right=False)


def make_female_flowing_hair(source_hair: bpy.types.Object, name: str, visual_id: str, armature: bpy.types.Object, hair_mat: bpy.types.Material) -> bpy.types.Object:
    """Hair 02: Flowing long hair cascading down the back and draping over the shoulders."""
    hair_obj = copy_mesh(source_hair, name, "hair", visual_id, armature)
    bm = bmesh.new()
    bm.from_mesh(hair_obj.data)
    bm.faces.ensure_lookup_table()
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
            # Remove cat ear tufts from crown and side pigtails:
            if (max_z > 1.65 and abs(avg_x) > 0.07) or (min_z < 1.45 and abs(avg_x) > 0.088):
                del_faces.extend(island)
    bmesh.ops.delete(bm, geom=del_faces, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")

    inv_mat = hair_obj.matrix_world.inverted()
    # Back cascading locks down upper spine
    for x_off in [-0.07, -0.035, 0.0, 0.035, 0.07]:
        pts_b = [
            Vector((x_off * 0.8, 0.08, 1.48)),
            Vector((x_off * 1.0, 0.11, 1.40)),
            Vector((x_off * 1.1, 0.12, 1.30)),
            Vector((x_off * 1.15, 0.11, 1.20)),
            Vector((x_off * 1.1, 0.09, 1.14)),
        ]
        w_b = [0.030, 0.045, 0.042, 0.032, 0.000]
        build_world_hair_strand(bm, pts_b, w_b, Vector((x_off * 0.5, 1.0, 0.2)), inv_mat)

    # Shoulder drape locks (left & right)
    for sign in [-1.0, 1.0]:
        pts_s = [
            Vector((sign * 0.075, 0.02, 1.48)),
            Vector((sign * 0.090, -0.01, 1.40)),
            Vector((sign * 0.095, -0.03, 1.30)),
            Vector((sign * 0.085, -0.04, 1.22)),
            Vector((sign * 0.075, -0.03, 1.16)),
        ]
        w_s = [0.025, 0.038, 0.035, 0.022, 0.000]
        build_world_hair_strand(bm, pts_s, w_s, Vector((sign * 0.8, -0.5, 0.2)), inv_mat)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(hair_obj.data)
    bm.free()
    hair_obj.data.update()
    hair_obj.data.materials.clear()
    hair_obj.data.materials.append(hair_mat)
    hair_obj.vertex_groups.clear()
    vg_head = hair_obj.vertex_groups.new(name="J_Bip_C_Head")
    vg_head.add(list(range(len(hair_obj.data.vertices))), 1.0, "REPLACE")
    return hair_obj


def make_female_bob_hair(source_hair: bpy.types.Object, name: str, visual_id: str, armature: bpy.types.Object, hair_mat: bpy.types.Material) -> bpy.types.Object:
    """Hair 03: Neat anime bob with face-framing curved locks hugging jawline and rounded nape."""
    hair_obj = copy_mesh(source_hair, name, "hair", visual_id, armature)
    bm = bmesh.new()
    bm.from_mesh(hair_obj.data)
    bm.faces.ensure_lookup_table()
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
            # Remove cat ear tufts from crown and side pigtails:
            if (max_z > 1.65 and abs(avg_x) > 0.07) or (min_z < 1.45 and abs(avg_x) > 0.088):
                del_faces.extend(island)
    bmesh.ops.delete(bm, geom=del_faces, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")

    inv_mat = hair_obj.matrix_world.inverted()
    # Face framing cheek locks
    for sign in [-1.0, 1.0]:
        pts_bob = [
            Vector((sign * 0.080, 0.00, 1.48)),
            Vector((sign * 0.085, -0.03, 1.42)),
            Vector((sign * 0.075, -0.06, 1.36)),
            Vector((sign * 0.055, -0.07, 1.32)),
        ]
        w_bob = [0.028, 0.036, 0.025, 0.000]
        build_world_hair_strand(bm, pts_bob, w_bob, Vector((sign * 0.8, -0.5, 0.2)), inv_mat)

    # Neat nape contour locks
    for x_off in [-0.05, -0.025, 0.0, 0.025, 0.05]:
        pts_nape = [
            Vector((x_off * 0.8, 0.08, 1.48)),
            Vector((x_off * 0.9, 0.09, 1.42)),
            Vector((x_off * 0.8, 0.08, 1.36)),
        ]
        w_nape = [0.025, 0.032, 0.000]
        build_world_hair_strand(bm, pts_nape, w_nape, Vector((x_off * 0.5, 1.0, 0.0)), inv_mat)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(hair_obj.data)
    bm.free()
    hair_obj.data.update()
    hair_obj.data.materials.clear()
    hair_obj.data.materials.append(hair_mat)
    hair_obj.vertex_groups.clear()
    vg_head = hair_obj.vertex_groups.new(name="J_Bip_C_Head")
    vg_head.add(list(range(len(hair_obj.data.vertices))), 1.0, "REPLACE")
    return hair_obj


def make_female_high_ponytail(
    source_hair: bpy.types.Object,
    name: str,
    visual_id: str,
    armature: bpy.types.Object,
    hair_mat: bpy.types.Material,
    gold_mat: bpy.types.Material,
) -> list[bpy.types.Object]:
    """Hair 04: Combat high ponytail with golden clasp and high arched cascading plume."""
    hair_obj = copy_mesh(source_hair, name, "hair", visual_id, armature)
    bm = bmesh.new()
    bm.from_mesh(hair_obj.data)
    bm.faces.ensure_lookup_table()
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
            # Remove cat ear tufts from crown and side pigtails:
            if (max_z > 1.65 and abs(avg_x) > 0.07) or (min_z < 1.45 and abs(avg_x) > 0.088):
                del_faces.extend(island)
    bmesh.ops.delete(bm, geom=del_faces, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")

    inv_mat = hair_obj.matrix_world.inverted()
    # High ponytail locks arching back from crown tie point (0.0, 0.065, 1.585)
    pts_f4_c = [
        Vector((0.0, 0.065, 1.585)),
        Vector((0.0, 0.105, 1.635)),
        Vector((0.0, 0.145, 1.590)),
        Vector((0.0, 0.165, 1.480)),
        Vector((0.0, 0.155, 1.360)),
        Vector((0.0, 0.138, 1.240)),
        Vector((0.0, 0.120, 1.150)),
    ]
    w_f4_c = [0.035, 0.055, 0.062, 0.052, 0.038, 0.020, 0.000]

    pts_f4_l = [
        Vector((-0.015, 0.065, 1.585)),
        Vector((-0.035, 0.100, 1.625)),
        Vector((-0.050, 0.138, 1.570)),
        Vector((-0.055, 0.155, 1.460)),
        Vector((-0.045, 0.145, 1.340)),
        Vector((-0.025, 0.130, 1.230)),
        Vector((-0.010, 0.118, 1.140)),
    ]
    w_f4_l = [0.025, 0.045, 0.050, 0.042, 0.028, 0.015, 0.000]

    pts_f4_r = [
        Vector((0.015, 0.065, 1.585)),
        Vector((0.035, 0.100, 1.625)),
        Vector((0.050, 0.138, 1.570)),
        Vector((0.055, 0.155, 1.460)),
        Vector((0.045, 0.145, 1.340)),
        Vector((0.025, 0.130, 1.230)),
        Vector((0.010, 0.118, 1.140)),
    ]
    w_f4_r = [0.025, 0.045, 0.050, 0.042, 0.028, 0.015, 0.000]

    build_world_hair_strand(bm, pts_f4_c, w_f4_c, Vector((0, 0.5, 1)), inv_mat)
    build_world_hair_strand(bm, pts_f4_l, w_f4_l, Vector((-0.5, 0.5, 1)), inv_mat)
    build_world_hair_strand(bm, pts_f4_r, w_f4_r, Vector((0.5, 0.5, 1)), inv_mat)

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(hair_obj.data)
    bm.free()
    hair_obj.data.update()
    hair_obj.data.materials.clear()
    hair_obj.data.materials.append(hair_mat)
    hair_obj.vertex_groups.clear()
    vg_head = hair_obj.vertex_groups.new(name="J_Bip_C_Head")
    vg_head.add(list(range(len(hair_obj.data.vertices))), 1.0, "REPLACE")

    # Gold Band Ring at crown tie point
    mesh_ring = bpy.data.meshes.new(name + "_BandMesh")
    bm_ring = bmesh.new()
    bmesh.ops.create_circle(bm_ring, cap_ends=False, radius=0.032, segments=20)
    res = bmesh.ops.extrude_edge_only(bm_ring, edges=bm_ring.edges)
    bmesh.ops.translate(bm_ring, vec=(0.0, 0.0, 0.016), verts=[v for v in res["geom"] if isinstance(v, bmesh.types.BMVert)])
    bmesh.ops.rotate(bm_ring, cent=(0.0, 0.0, 0.0), matrix=Matrix.Rotation(math.radians(40), 3, 'X'), verts=bm_ring.verts)
    loc_ring = inv_mat @ Vector((0.0, 0.068, 1.585))
    bmesh.ops.translate(bm_ring, vec=loc_ring, verts=bm_ring.verts)
    bm_ring.to_mesh(mesh_ring)
    bm_ring.free()
    obj_ring = bpy.data.objects.new(name + "_Band", mesh_ring)
    bpy.context.collection.objects.link(obj_ring)
    obj_ring.data.materials.append(gold_mat)
    for p in obj_ring.data.polygons:
        p.use_smooth = True
    vg_ring = obj_ring.vertex_groups.new(name="J_Bip_C_Head")
    vg_ring.add(list(range(len(obj_ring.data.vertices))), 1.0, "REPLACE")
    mod_ring = obj_ring.modifiers.new("WorldgoingArmature", "ARMATURE")
    mod_ring.object = armature
    obj_ring.parent = armature
    obj_ring.matrix_parent_inverse = armature.matrix_world.inverted()
    component_props(obj_ring, "hair", visual_id)

    return [hair_obj, obj_ring]


# =========================================================================
# 4b. Female Modular Leather Armor (22 Complete Components)
# =========================================================================

def make_female_leather_armor(
    source_raw_body: bpy.types.Object,
    armature: bpy.types.Object,
    leather_body: bpy.types.Material,
    leather_edge: bpy.types.Material,
    cloth: bpy.types.Material,
    steel: bpy.types.Material,
    gold: bpy.types.Material,
    leather: bpy.types.Material,
) -> list[bpy.types.Object]:
    parts = []
    visual_id = "armor_light_leather_01"

    def create_rigid_component(name: str, bm: bmesh.types.BMesh, comp_mat: bpy.types.Material, bone: str) -> bpy.types.Object:
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
        component_props(obj, "armor", visual_id)
        return obj

    # 0. Adventurer Fitted Pants (貼身冒險者長褲，無洋裝裙擺，保留動態骨骼權重)
    obj_pants = copy_mesh(source_raw_body, "Armor_Light_Leather_01_Pants", "armor", visual_id, armature)
    bm = bmesh.new()
    bm.from_mesh(obj_pants.data)
    bm.faces.ensure_lookup_table()
    delete_faces = [
        f for f in bm.faces
        if not (0.280 <= f.calc_center_median().z <= 0.960 and abs(f.calc_center_median().x) <= 0.200)
    ]
    bmesh.ops.delete(bm, geom=delete_faces, context="FACES")
    bm.normal_update()
    for v in bm.verts:
        if v.link_faces and v.normal.length > 0:
            v.co += v.normal.normalized() * 0.0030
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

    # 1. Adventurer Leather Vest (合身真皮背心/胸甲，貼合女性身型)
    obj_vest = copy_mesh(source_raw_body, "Armor_Light_Leather_01_Vest", "armor", visual_id, armature)
    bm = bmesh.new()
    bm.from_mesh(obj_vest.data)
    bm.faces.ensure_lookup_table()
    delete_faces = [
        f for f in bm.faces
        if not (0.960 <= f.calc_center_median().z <= 1.340 and abs(f.calc_center_median().x) <= 0.180)
    ]
    delete_faces += [f for f in bm.faces if f.calc_center_median().z >= 1.200 and abs(f.calc_center_median().x) >= 0.115]
    bmesh.ops.delete(bm, geom=list(set(delete_faces)), context="FACES")
    bm.normal_update()
    for v in bm.verts:
        if v.link_faces and v.normal.length > 0:
            v.co += v.normal.normalized() * 0.0050
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

    # 2. Stand Collar Trim
    obj_collar = copy_mesh(source_raw_body, "Armor_Light_Leather_01_Collar", "armor", visual_id, armature)
    bm = bmesh.new()
    bm.from_mesh(obj_collar.data)
    bm.faces.ensure_lookup_table()
    delete_faces = [
        f for f in bm.faces
        if not (1.300 <= f.calc_center_median().z <= 1.345 and abs(f.calc_center_median().x) <= 0.065)
    ]
    bmesh.ops.delete(bm, geom=delete_faces, context="FACES")
    bm.normal_update()
    for v in bm.verts:
        if v.link_faces and v.normal.length > 0:
            v.co += v.normal.normalized() * 0.0075
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
        v.co.x *= 0.006
        v.co.y *= 0.004
        v.co.z *= 0.250
        v.co.x += 0.0
        v.co.y += -0.080
        v.co.z += 1.140
    parts.append(create_rigid_component("Armor_Light_Leather_01_FrontSeam", bm_seam, leather_edge, "J_Bip_C_Chest"))

    # 4. Diagonal Baldric / Chest Cross-Strap & Buckle
    bm_strap = bmesh.new()
    strap_pts = [
        (-0.055, -0.055, 1.300),
        (-0.035, -0.080, 1.250),
        (-0.010, -0.090, 1.180),
        ( 0.015, -0.085, 1.100),
        ( 0.040, -0.075, 1.040),
        ( 0.055, -0.060, 0.990),
    ]
    w = 0.014
    verts_strap = []
    for pt in strap_pts:
        v_l = bm_strap.verts.new((pt[0] - w * 0.7, pt[1] - 0.004, pt[2] + w * 0.7))
        v_r = bm_strap.verts.new((pt[0] + w * 0.7, pt[1] - 0.004, pt[2] - w * 0.7))
        verts_strap.append((v_l, v_r))
    for i in range(len(strap_pts) - 1):
        v1, v2 = verts_strap[i]
        v3, v4 = verts_strap[i + 1]
        bm_strap.faces.new((v1, v3, v4, v2))
    bmesh.ops.solidify(bm_strap, geom=bm_strap.faces[:], thickness=0.0035)
    parts.append(create_rigid_component("Armor_Light_Leather_01_CrossStrap", bm_strap, leather, "J_Bip_C_Chest"))

    # Buckle on Chest Strap
    bm_buckle = bmesh.new()
    bmesh.ops.create_cube(bm_buckle, size=1.0)
    for v in bm_buckle.verts:
        v.co.x *= 0.028
        v.co.y *= 0.006
        v.co.z *= 0.022
        v.co.x += -0.035
        v.co.y += -0.086
        v.co.z += 1.200
    bmesh.ops.bevel(bm_buckle, geom=bm_buckle.edges[:], offset=0.002, segments=2)
    parts.append(create_rigid_component("Armor_Light_Leather_01_StrapBuckle", bm_buckle, steel, "J_Bip_C_Chest"))

    # 5. Pauldrons (Anchored precisely to female upper arm joint X=±0.108, Z=1.307)
    for side, sign in (("L", 1.0), ("R", -1.0)):
        bm_p1 = bmesh.new()
        n_lat, n_lon = 8, 8
        r_p1 = 0.042
        grid_p1 = []
        for i in range(n_lat):
            theta = (i / (n_lat - 1)) * (math.pi * 0.45)
            row = []
            for j in range(n_lon):
                phi = (j / (n_lon - 1) - 0.5) * math.pi * 0.90
                lx = sign * (math.sin(theta) * math.cos(phi) * 0.85) * r_p1
                ly = math.sin(theta) * math.sin(phi) * r_p1
                lz = math.cos(theta) * (r_p1 * 0.50)
                wx = sign * 0.108 + lx
                wy = 0.006 + ly
                wz = 1.307 + lz
                row.append(bm_p1.verts.new((wx, wy, wz)))
            grid_p1.append(row)
        for i in range(n_lat - 1):
            for j in range(n_lon - 1):
                bm_p1.faces.new((grid_p1[i][j], grid_p1[i + 1][j], grid_p1[i + 1][j + 1], grid_p1[i][j + 1]))
        bmesh.ops.solidify(bm_p1, geom=bm_p1.faces[:], thickness=0.0035)
        parts.append(create_rigid_component(f"Armor_Light_Leather_01_Pauldron_Upper_{side}", bm_p1, leather_body, f"J_Bip_{side}_UpperArm"))

        bm_p2 = bmesh.new()
        r_p2 = 0.038
        grid_p2 = []
        for i in range(n_lat):
            theta = (i / (n_lat - 1)) * (math.pi * 0.45)
            row = []
            for j in range(n_lon):
                phi = (j / (n_lon - 1) - 0.5) * math.pi * 0.85
                lx = sign * (math.sin(theta) * math.cos(phi) * 0.85 + 0.010) * r_p2
                ly = math.sin(theta) * math.sin(phi) * r_p2
                lz = math.cos(theta) * (r_p2 * 0.45) - 0.010
                wx = sign * 0.108 + lx
                wy = 0.006 + ly
                wz = 1.307 + lz
                row.append(bm_p2.verts.new((wx, wy, wz)))
            grid_p2.append(row)
        for i in range(n_lat - 1):
            for j in range(n_lon - 1):
                bm_p2.faces.new((grid_p2[i][j], grid_p2[i + 1][j], grid_p2[i + 1][j + 1], grid_p2[i][j + 1]))
        bmesh.ops.solidify(bm_p2, geom=bm_p2.faces[:], thickness=0.0030)
        parts.append(create_rigid_component(f"Armor_Light_Leather_01_Pauldron_Lower_{side}", bm_p2, leather_edge, f"J_Bip_{side}_UpperArm"))

        bm_riv = bmesh.new()
        for offset_y in (-0.016, 0.0, 0.016):
            bmesh.ops.create_icosphere(bm_riv, subdivisions=1, radius=0.0025)
            for v in bm_riv.verts[-12:]:
                v.co.x += sign * 0.108
                v.co.y += offset_y + 0.006
                v.co.z += 1.328
        parts.append(create_rigid_component(f"Armor_Light_Leather_01_Pauldron_Rivets_{side}", bm_riv, steel, f"J_Bip_{side}_UpperArm"))

    # 6. Forearm Bracers
    for side, sign in (("L", 1.0), ("R", -1.0)):
        obj_bracer = copy_mesh(source_raw_body, f"Armor_Light_Leather_01_Bracer_{side}", "armor", visual_id, armature)
        bm = bmesh.new()
        bm.from_mesh(obj_bracer.data)
        bm.faces.ensure_lookup_table()
        del_faces = []
        for f in bm.faces:
            c = f.calc_center_median()
            is_side = (c.x >= 0) if sign > 0 else (c.x <= 0)
            if not (0.93 <= c.z <= 1.10 and is_side and abs(c.x) >= 0.18):
                del_faces.append(f)
        bmesh.ops.delete(bm, geom=del_faces, context="FACES")
        bm.normal_update()
        for v in bm.verts:
            if v.link_faces and v.normal.length > 0:
                v.co += v.normal.normalized() * 0.0040
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

        obj_bstrap = copy_mesh(source_raw_body, f"Armor_Light_Leather_01_BracerStraps_{side}", "armor", visual_id, armature)
        bm = bmesh.new()
        bm.from_mesh(obj_bstrap.data)
        bm.faces.ensure_lookup_table()
        del_bstraps = []
        for f in bm.faces:
            c = f.calc_center_median()
            is_side = (c.x >= 0) if sign > 0 else (c.x <= 0)
            if not (1.04 <= c.z <= 1.09 and is_side and abs(c.x) >= 0.18):
                del_bstraps.append(f)
        bmesh.ops.delete(bm, geom=del_bstraps, context="FACES")
        bm.normal_update()
        for v in bm.verts:
            if v.link_faces and v.normal.length > 0:
                v.co += v.normal.normalized() * 0.0065
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

    # 7. Belt / Waistband & Buckle
    obj_belt = copy_mesh(source_raw_body, "Armor_Light_Leather_01_WaistBand", "armor", visual_id, armature)
    bm = bmesh.new()
    bm.from_mesh(obj_belt.data)
    bm.faces.ensure_lookup_table()
    del_faces = [f for f in bm.faces if not (0.940 <= f.calc_center_median().z <= 1.000 and abs(f.calc_center_median().x) <= 0.160)]
    bmesh.ops.delete(bm, geom=del_faces, context="FACES")
    bm.normal_update()
    for v in bm.verts:
        if v.link_faces and v.normal.length > 0:
            v.co += v.normal.normalized() * 0.0070
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

    # Belt Buckle (Front at Y = -0.088)
    bm_bb = bmesh.new()
    bmesh.ops.create_cube(bm_bb, size=1.0)
    for v in bm_bb.verts:
        v.co.x *= 0.034
        v.co.y *= 0.007
        v.co.z *= 0.028
        v.co.x += 0.0
        v.co.y += -0.088
        v.co.z += 0.970
    bmesh.ops.bevel(bm_bb, geom=bm_bb.edges[:], offset=0.0025, segments=2)
    parts.append(create_rigid_component("Armor_Light_Leather_01_BeltBuckle", bm_bb, gold, "J_Bip_C_Hips"))

    # 8. Side Tassets & Pouches
    for side, sign in (("L", 1.0), ("R", -1.0)):
        obj_tasset = copy_mesh(source_raw_body, f"Armor_Light_Leather_01_Tasset_{side}", "armor", visual_id, armature)
        bm = bmesh.new()
        bm.from_mesh(obj_tasset.data)
        bm.faces.ensure_lookup_table()
        del_faces = []
        for f in bm.faces:
            c = f.calc_center_median()
            is_side = (c.x >= 0) if sign > 0 else (c.x <= 0)
            if not (0.83 <= c.z <= 0.95 and is_side and abs(c.x) >= 0.075):
                del_faces.append(f)
        bmesh.ops.delete(bm, geom=del_faces, context="FACES")
        bm.normal_update()
        for v in bm.verts:
            if v.link_faces and v.normal.length > 0:
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

        bm_pch = bmesh.new()
        bmesh.ops.create_cube(bm_pch, size=1.0)
        for v in bm_pch.verts:
            v.co.x *= 0.024
            v.co.y *= 0.034
            v.co.z *= 0.040
            v.co.x += sign * 0.110
            v.co.y += 0.015
            v.co.z += 0.965
        parts.append(create_rigid_component(f"Armor_Light_Leather_01_Pouch_{side}", bm_pch, leather_edge, "J_Bip_C_Hips"))

    return parts


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
    p_palm = (db_rh.matrix_local @ Vector((0.0, 0.040, -0.012, 1.0))).xyz
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
    scab_top = Vector((0.145, -0.020, 0.880))
    scab_tip = Vector((0.165, 0.025, 0.280))
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
    p_palm = (db_rh.matrix_local @ Vector((0.0, 0.040, -0.012, 1.0))).xyz
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
    p_top = Vector((-0.16, 0.12, 1.48))
    p_bot = Vector((0.18, 0.14, 0.55))
    s_dir = (p_bot - p_top).normalized()
    rot_q = Vector((0,0,1)).rotation_difference(s_dir)

    bm_h_shaft = bmesh.new()
    res_hs = bmesh.ops.create_cone(bm_h_shaft, cap_ends=True, cap_tris=False, segments=10, radius1=0.012, radius2=0.012, depth=1.85)
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
    p_palm = (db_rh.matrix_local @ Vector((0.0, 0.040, -0.012, 1.0))).xyz
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
    p_top = Vector((-0.12, 0.12, 1.38))
    p_bot = Vector((0.08, 0.13, 0.72))
    a_dir = (p_bot - p_top).normalized()
    rot_q = Vector((0,0,1)).rotation_difference(a_dir)

    bm_h_haft = bmesh.new()
    res_hh = bmesh.ops.create_cone(bm_h_haft, cap_ends=True, cap_tris=False, segments=10, radius1=0.013, radius2=0.013, depth=0.74)
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
        bz = (1.18) * (1.0 - t) + (1.42) * t
        reach = math.sin(t * math.pi) * 0.16 + 0.03
        by = 0.14 + reach
        hblade_pts.append((by, bz))
    vh_blade_l = [bm_hb.verts.new((-0.12 - 0.003, pt[0], pt[1])) for pt in hblade_pts]
    vh_blade_r = [bm_hb.verts.new((-0.12 + 0.003, pt[0], pt[1])) for pt in hblade_pts]
    vh_socket_l = [bm_hb.verts.new((-0.12 - 0.013, 0.13, pt[1])) for pt in hblade_pts]
    vh_socket_r = [bm_hb.verts.new((-0.12 + 0.013, 0.13, pt[1])) for pt in hblade_pts]
    for i in range(b_n - 1):
        bm_hb.faces.new((vh_socket_l[i], vh_blade_l[i], vh_blade_l[i+1], vh_socket_l[i+1]))
        bm_hb.faces.new((vh_socket_r[i+1], vh_blade_r[i+1], vh_blade_r[i], vh_socket_r[i]))
        bm_hb.faces.new((vh_blade_l[i], vh_blade_r[i], vh_blade_r[i+1], vh_blade_l[i+1]))
        bm_hb.faces.new((vh_socket_r[i], vh_socket_l[i], vh_socket_l[i+1], vh_socket_r[i+1]))
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
    p_palm = (db_rh.matrix_local @ Vector((0.0, 0.040, -0.012, 1.0))).xyz
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
    p_top = Vector((-0.12, 0.12, 1.36))
    p_bot = Vector((0.06, 0.13, 0.70))
    h_dir = (p_bot - p_top).normalized()
    rot_q = Vector((0,0,1)).rotation_difference(h_dir)

    bm_h_haft = bmesh.new()
    res_hh = bmesh.ops.create_cone(bm_h_haft, cap_ends=True, cap_tris=False, segments=10, radius1=0.013, radius2=0.013, depth=0.72)
    bmesh.ops.rotate(bm_h_haft, cent=(0,0,0), matrix=rot_q.to_matrix(), verts=bm_h_haft.verts)
    center = (p_top + p_bot) * 0.5
    for v in bm_h_haft.verts:
        v.co += center
    parts.append(create_bone_rigid_component("Weapon_Hammer_01_Holstered_Haft", bm_h_haft, wood, "J_Bip_C_UpperChest", "weapon", visual_id, armature))

    bm_h_head = bmesh.new()
    res_hhd = bmesh.ops.create_cube(bm_h_head, size=1.0)
    for v in res_hhd["verts"]:
        v.co.x *= 0.055; v.co.y *= 0.130; v.co.z *= 0.055
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
    p_palm = (db_rh.matrix_local @ Vector((0.0, 0.040, -0.012, 1.0))).xyz
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
    d_center = Vector((0.0, 0.11, 0.88))
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
    p_palm = (db_rh.matrix_local @ Vector((0.0, 0.040, -0.012, 1.0))).xyz
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
    hbx, hby, hbz = 0.0, 0.14, 1.10
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

    shield_h = 0.540
    shield_w = 0.380
    bow_radius = 0.380
    n_rows = 14
    n_cols = 12
    y_mid = 0.120

    grid_local = []
    for r in range(n_rows):
        t_v = r / (n_rows - 1)
        cur_x = (shield_h * 0.45) * (1.0 - t_v) + (-shield_h * 0.55) * t_v
        half_w = shield_w * 0.5 if t_v < 0.38 else (shield_w * 0.5) * math.sqrt(max(0.0, 1.0 - ((t_v - 0.38) / 0.62)**1.5))
        row = []
        for c in range(n_cols):
            u_h = (c / (n_cols - 1) - 0.5) * 2.0
            local_y = y_mid + u_h * half_w
            local_z = 0.055 + (math.sqrt(max(0.001, bow_radius**2 - (u_h * shield_w * 0.5)**2)) - bow_radius)
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
        to_center = Vector((0.0, y_mid, 0.055)) - co
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
        v.co.x *= 0.038; v.co.y *= 0.200; v.co.z *= 0.006
        v.co.x += 0.025; v.co.y += y_mid; v.co.z += 0.058
    bmesh.ops.bevel(bm_cross_h, geom=bm_cross_h.edges[:], offset=0.003, segments=1)
    parts.append(create_shield_comp("Shield_Heater_01_Cross_H", bm_cross_h, gold))

    bm_cross_v = bmesh.new()
    bmesh.ops.create_cube(bm_cross_v, size=1.0)
    for v in bm_cross_v.verts:
        v.co.x *= 0.260; v.co.y *= 0.038; v.co.z *= 0.006
        v.co.x += 0.025; v.co.y += y_mid; v.co.z += 0.058
    bmesh.ops.bevel(bm_cross_v, geom=bm_cross_v.edges[:], offset=0.003, segments=1)
    parts.append(create_shield_comp("Shield_Heater_01_Cross_V", bm_cross_v, gold))

    # 4. Center Boss Diamond
    bm_boss = bmesh.new()
    bmesh.ops.create_cube(bm_boss, size=1.0)
    for v in bm_boss.verts:
        v.co.x *= 0.055; v.co.y *= 0.055; v.co.z *= 0.012
        v.co.x += 0.025; v.co.y += y_mid; v.co.z += 0.063
    bmesh.ops.rotate(bm_boss, cent=(0.025, y_mid, 0.063), matrix=Matrix.Rotation(math.radians(45), 3, 'Z'), verts=bm_boss.verts)
    bmesh.ops.bevel(bm_boss, geom=bm_boss.edges[:], offset=0.004, segments=1)
    parts.append(create_shield_comp("Shield_Heater_01_Boss", bm_boss, silver))

    # 5. Inner Arm Straps & Handle
    bm_strap = bmesh.new()
    bmesh.ops.create_cone(bm_strap, cap_ends=False, segments=12, radius1=0.032, radius2=0.032, depth=0.035)
    bmesh.ops.rotate(bm_strap, cent=(0,0,0), matrix=Matrix.Rotation(math.radians(90), 3, 'X'), verts=bm_strap.verts)
    for v in bm_strap.verts:
        v.co.x += 0.0; v.co.y += y_mid + 0.04; v.co.z += 0.020
    parts.append(create_shield_comp("Shield_Heater_01_Strap", bm_strap, leather))

    # 6. Holstered Back Shield (Spine-skinned to match Cape)
    female_cape_anchors = [
        (1.280, "J_Bip_C_UpperChest"),
        (1.180, "J_Bip_C_Chest"),
        (1.050, "J_Bip_C_Spine"),
        (0.940, "J_Bip_C_Hips"),
    ]
    grid_back = []
    for r in range(n_rows):
        t_v = r / (n_rows - 1)
        z = (1.35) * (1.0 - t_v) + (0.85) * t_v
        half_w = shield_w * 0.5 if t_v < 0.38 else (shield_w * 0.5) * math.sqrt(max(0.0, 1.0 - ((t_v - 0.38) / 0.62)**1.5))
        y_base = 0.225 * (1.0 - t_v) + 0.285 * t_v
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
    parts.append(create_spine_skinned_component("Shield_Heater_01_Holstered_Field", bm_field_bk, shield_mat, female_cape_anchors, "shield", visual_id, armature))

    bm_cross_bk = bmesh.new()
    bmesh.ops.create_cube(bm_cross_bk, size=1.0)
    for v in bm_cross_bk.verts:
        v.co.x *= 0.038; v.co.y *= 0.008; v.co.z *= 0.260
        v.co.x += 0.0; v.co.y += 0.282; v.co.z += 1.150
    parts.append(create_spine_skinned_component("Shield_Heater_01_Holstered_Cross_V", bm_cross_bk, gold, female_cape_anchors, "shield", visual_id, armature))

    bm_cross_hbk = bmesh.new()
    bmesh.ops.create_cube(bm_cross_hbk, size=1.0)
    for v in bm_cross_hbk.verts:
        v.co.x *= 0.200; v.co.y *= 0.008; v.co.z *= 0.038
        v.co.x += 0.0; v.co.y += 0.282; v.co.z += 1.150
    parts.append(create_spine_skinned_component("Shield_Heater_01_Holstered_Cross_H", bm_cross_hbk, gold, female_cape_anchors, "shield", visual_id, armature))

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


def make_cape(
    armature: bpy.types.Object,
    mat: bpy.types.Material,
    gold: bpy.types.Material,
    silver: bpy.types.Material,
) -> list[bpy.types.Object]:
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
        component_props(obj, "cape", visual_id)
        return obj
    # 1. Front Shoulder Brooches (Clasped at female upper chest X=±0.068, Y=-0.112, Z=1.348)
    for side, sign in (("L", 1.0), ("R", -1.0)):
        bm_b = bmesh.new()
        res_b = bmesh.ops.create_icosphere(bm_b, subdivisions=2, radius=0.011)
        for v in res_b["verts"]:
            v.co.y *= 0.35
            v.co.x += sign * 0.068
            v.co.y += -0.112
            v.co.z += 1.348
        parts.append(create_cape_rigid_component(f"Cape_Travel_01_Brooch_{side}", bm_b, gold, "J_Bip_C_UpperChest"))

    # 2. Fastener Collar Band (Across front collarbone, resting right above iron armor collar rim)
    bm_cb = bmesh.new()
    cb_pts = [(-0.068, -0.112, 1.348), (0.0, -0.120, 1.340), (0.068, -0.112, 1.348)]
    w = 0.009
    v_l1 = bm_cb.verts.new((cb_pts[0][0], cb_pts[0][1], cb_pts[0][2] + w * 0.5))
    v_l2 = bm_cb.verts.new((cb_pts[0][0], cb_pts[0][1], cb_pts[0][2] - w * 0.5))
    v_m1 = bm_cb.verts.new((cb_pts[1][0], cb_pts[1][1], cb_pts[1][2] + w * 0.5))
    v_m2 = bm_cb.verts.new((cb_pts[1][0], cb_pts[1][1], cb_pts[1][2] - w * 0.5))
    v_r1 = bm_cb.verts.new((cb_pts[2][0], cb_pts[2][1], cb_pts[2][2] + w * 0.5))
    v_r2 = bm_cb.verts.new((cb_pts[2][0], cb_pts[2][1], cb_pts[2][2] - w * 0.5))
    bm_cb.faces.new((v_l1, v_m1, v_m2, v_l2))
    bm_cb.faces.new((v_m1, v_r1, v_r2, v_m2))
    bmesh.ops.solidify(bm_cb, geom=bm_cb.faces[:], thickness=0.003)
    parts.append(create_cape_rigid_component("Cape_Travel_01_FastenerBand", bm_cb, gold, "J_Bip_C_UpperChest"))

    # 3. Draping Cape Body (At back +Y, smoothly skinned across UpperChest -> Chest -> Spine -> Hips)
    bm_cape = bmesh.new()
    n_rows = 16
    n_cols = 16
    grid = []
    # Calibrated to gracefully clear female iron backplate (py ~ 0.137) and rear skirt (py ~ 0.165)
    profile = [
        (1.345, 0.148, 0.140),
        (1.280, 0.168, 0.160),
        (1.180, 0.185, 0.185),
        (1.050, 0.198, 0.210),
        (0.920, 0.205, 0.235),
        (0.780, 0.195, 0.260),
        (0.650, 0.180, 0.285),
        (0.540, 0.165, 0.305),
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
            fold_wave = abs(math.sin(u * math.pi * 4.0)) * (0.005 + 0.015 * t)
            center_dip = (1.0 - 4.0 * (u - 0.5)**2) * (0.005 + 0.012 * t)
            y = y_base + fold_wave + center_dip
            row.append(bm_cape.verts.new((x, y, z)))
        grid.append(row)

    for r in range(n_rows - 1):
        for c in range(n_cols - 1):
            bm_cape.faces.new((grid[r][c], grid[r + 1][c], grid[r + 1][c + 1], grid[r][c + 1]))

    bmesh.ops.solidify(bm_cape, geom=bm_cape.faces[:], thickness=0.004)
    female_cape_anchors = [
        (1.280, "J_Bip_C_UpperChest"),
        (1.180, "J_Bip_C_Chest"),
        (1.050, "J_Bip_C_Spine"),
        (0.940, "J_Bip_C_Hips"),
    ]
    parts.append(create_spine_skinned_cape_component("Cape_Travel_01_Main", bm_cape, mat, female_cape_anchors))

    return parts


# =========================================================================
# 5. Motion Capture Retargeting & Upright Head Pitch Compensation
# =========================================================================

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
    target_rest_hips_z = (target_arm.matrix_world @ tgt_hips_data.head_local).z if tgt_hips_data else 0.76
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


def reset_pose(armature: bpy.types.Object) -> None:
    for pb in armature.pose.bones:
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.rotation_euler = (0.0, 0.0, 0.0)


def pose_bone(armature: bpy.types.Object, bone_name: str) -> bpy.types.PoseBone:
    return armature.pose.bones[bone_name]


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


def key_animation_frame(armature: bpy.types.Object, action_name: str, frame: int) -> None:
    apply_r_grip = action_name not in ("down", "T-Pose", "attack_bow")
    apply_l_grip = action_name in ("attack_spear", "guard", "attack_bow", "attack_axe", "attack_hammer", "attack_dagger", "attack_crossbow", "attack_shield_bash", "ride_idle", "ride_walk", "ride_run", "ride_attack", "ride_slash", "ride_thrust")
    if apply_r_grip:
        apply_right_hand_grip(armature, frame)
    if apply_l_grip:
        apply_left_hand_grip(armature, frame)
    for pb in armature.pose.bones:
        pb.rotation_mode = "QUATERNION"
        if pb.rotation_euler.x != 0.0 or pb.rotation_euler.y != 0.0 or pb.rotation_euler.z != 0.0:
            pb.rotation_quaternion = pb.rotation_euler.to_quaternion()
        pb.keyframe_insert(data_path="rotation_quaternion", frame=frame)
        pb.keyframe_insert(data_path="location", frame=frame)


def prepare_tpose_action(armature: bpy.types.Object) -> bpy.types.Action:
    action = bpy.data.actions.get("T-Pose") or bpy.data.actions.new("T-Pose")
    armature.animation_data_create()
    armature.animation_data.action = action
    reset_pose(armature)
    key_animation_frame(armature, "T-Pose", 0)
    action.use_fake_user = True
    return action


def prepare_attack_spear_action(armature: bpy.types.Object) -> bpy.types.Action:
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
    
    SHIELD_GUARD_LA = (math.radians(-35), math.radians(20), math.radians(30))
    SHIELD_GUARD_LF = (math.radians(-50), 0.0, math.radians(-15))
    SHIELD_GUARD_LH = (math.radians(10), 0.0, 0.0)
    LEG_LU = (0.0, 0.0, 0.08)
    LEG_LK = 0.0
    LEG_LF = (0.0, 0.0, -0.08)
    LEG_RU = (0.0, 0.0, -0.08)
    LEG_RK = 0.0
    LEG_RF = (0.0, 0.0, 0.08)

    keyframes_spear = [
        (0, (0.0, 0.05, 0.0), (0.0, 0.05, 0.0), (0.0, -0.08, 0.0),
         (-1.15, 0.05, -0.12), (0.20, 0.0, -0.15), (math.radians(20), math.radians(10), math.radians(-15))),
        (8, (0.0, 0.20, 0.0), (0.02, 0.25, 0.0), (0.0, -0.25, 0.0),
         (-0.85, 0.20, 0.40), (0.95, 0.0, 0.0), (-1.45, -1.05, 0.85)),
        (12, (0.04, -0.15, 0.0), (0.06, -0.20, 0.0), (0.0, 0.20, 0.0),
         (-1.45, 0.15, 0.35), (0.25, 0.0, 0.0), (-0.85, -1.15, 0.75)),
        (15, (0.04, -0.15, 0.0), (0.06, -0.20, 0.0), (0.0, 0.20, 0.0),
         (-1.48, 0.15, 0.35), (0.22, 0.0, 0.0), (-0.85, -1.15, 0.75)),
        (22, (0.02, -0.05, 0.0), (0.03, -0.05, 0.0), (0.0, 0.05, 0.0),
         (-0.95, 0.15, 0.20), (0.75, 0.0, 0.0), (-1.30, -1.05, 0.85)),
        (30, (0.0, 0.05, 0.0), (0.0, 0.05, 0.0), (0.0, -0.08, 0.0),
         (-1.15, 0.05, -0.12), (0.20, 0.0, -0.15), (math.radians(20), math.radians(10), math.radians(-15))),
    ]
    for kf in keyframes_spear:
        f, sp_rot, ch_rot, hd_rot, ra, rf, rh = kf
        reset_pose(armature)
        pose_bone(armature, "J_Bip_C_Hips").location = (0.0, 0.0, 0.0)
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
    
    keyframes_axe = [
        (0, (0.0, 0.05, 0.0), (0.0, 0.05, 0.0), (0.0, -0.08, 0.0),
         (-1.05, 0.05, -0.30), (0.25, 0.0, -0.15), (math.radians(20), math.radians(10), math.radians(-15))),
        (8, (-0.02, 0.20, 0.0), (0.02, 0.25, 0.0), (0.0, -0.25, 0.0),
         (-0.25, 0.25, -0.65), (1.45, 0.0, 0.0), (0.20, 1.20, -1.20)),
        (14, (0.06, -0.18, 0.0), (0.08, -0.22, 0.0), (0.0, 0.20, 0.0),
         (-1.30, 0.20, 0.40), (0.55, 0.0, -0.15), (-1.40, -0.85, 1.10)),
        (16, (0.06, -0.18, 0.0), (0.08, -0.22, 0.0), (0.0, 0.20, 0.0),
         (-1.32, 0.20, 0.40), (0.50, 0.0, -0.15), (-1.40, -0.85, 1.10)),
        (23, (0.02, -0.05, 0.0), (0.04, -0.05, 0.0), (0.0, 0.05, 0.0),
         (-1.10, 0.10, 0.10), (0.45, 0.0, -0.10), (-1.20, -1.00, 0.85)),
        (30, (0.0, 0.05, 0.0), (0.0, 0.05, 0.0), (0.0, -0.08, 0.0),
         (-1.05, 0.05, -0.30), (0.25, 0.0, -0.15), (math.radians(20), math.radians(10), math.radians(-15))),
    ]
    for kf in keyframes_axe:
        f, sp_rot, ch_rot, hd_rot, ra, rf, rh = kf
        reset_pose(armature)
        pose_bone(armature, "J_Bip_C_Hips").location = (0.0, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Spine").rotation_euler = sp_rot
        pose_bone(armature, "J_Bip_C_Chest").rotation_euler = ch_rot
        pose_bone(armature, "J_Bip_C_Head").rotation_euler = hd_rot
        pose_bone(armature, "J_Bip_R_UpperArm").rotation_euler = ra
        pose_bone(armature, "J_Bip_R_LowerArm").rotation_euler = rf
        pose_bone(armature, "J_Bip_R_Hand").rotation_euler = rh
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
    
    keyframes_hammer = [
        (0, (0.0, 0.05, 0.0), (0.0, 0.05, 0.0), (0.0, -0.08, 0.0),
         (-1.05, 0.05, -0.30), (0.25, 0.0, -0.15), (math.radians(20), math.radians(10), math.radians(-15))),
        (10, (-0.04, 0.22, 0.0), (0.04, 0.30, 0.0), (0.0, -0.30, 0.0),
         (-0.15, 0.30, -0.75), (1.55, 0.0, 0.0), (0.30, 1.30, -1.35)),
        (16, (0.08, -0.22, 0.0), (0.10, -0.28, 0.0), (0.0, 0.25, 0.0),
         (-1.40, 0.25, 0.45), (0.65, 0.0, -0.20), (-1.55, -0.90, 1.20)),
        (19, (0.08, -0.22, 0.0), (0.10, -0.28, 0.0), (0.0, 0.25, 0.0),
         (-1.42, 0.25, 0.45), (0.60, 0.0, -0.20), (-1.55, -0.90, 1.20)),
        (26, (0.03, -0.06, 0.0), (0.05, -0.06, 0.0), (0.0, 0.06, 0.0),
         (-1.15, 0.12, 0.12), (0.45, 0.0, -0.10), (-1.25, -1.05, 0.85)),
        (34, (0.0, 0.05, 0.0), (0.0, 0.05, 0.0), (0.0, -0.08, 0.0),
         (-1.05, 0.05, -0.30), (0.25, 0.0, -0.15), (math.radians(20), math.radians(10), math.radians(-15))),
    ]
    for kf in keyframes_hammer:
        f, sp_rot, ch_rot, hd_rot, ra, rf, rh = kf
        reset_pose(armature)
        pose_bone(armature, "J_Bip_C_Hips").location = (0.0, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Spine").rotation_euler = sp_rot
        pose_bone(armature, "J_Bip_C_Chest").rotation_euler = ch_rot
        pose_bone(armature, "J_Bip_C_Head").rotation_euler = hd_rot
        pose_bone(armature, "J_Bip_R_UpperArm").rotation_euler = ra
        pose_bone(armature, "J_Bip_R_LowerArm").rotation_euler = rf
        pose_bone(armature, "J_Bip_R_Hand").rotation_euler = rh
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
    
    keyframes_dagger = [
        (0, (0.0, 0.05, 0.0), (0.0, 0.05, 0.0), (0.0, -0.08, 0.0),
         (-1.15, 0.05, -0.12), (0.20, 0.0, -0.15), (math.radians(20), math.radians(10), math.radians(-15))),
        (5, (0.0, 0.15, 0.0), (0.02, 0.20, 0.0), (0.0, -0.20, 0.0),
         (-0.80, 0.15, 0.35), (0.90, 0.0, 0.0), (-1.40, -1.00, 0.80)),
        (9, (0.04, -0.12, 0.0), (0.06, -0.18, 0.0), (0.0, 0.18, 0.0),
         (-1.40, 0.12, 0.30), (0.22, 0.0, 0.0), (-0.80, -1.10, 0.70)),
        (14, (0.0, 0.15, 0.0), (0.02, 0.20, 0.0), (0.0, -0.20, 0.0),
         (-0.80, 0.15, 0.35), (0.90, 0.0, 0.0), (-1.40, -1.00, 0.80)),
        (18, (0.04, -0.12, 0.0), (0.06, -0.18, 0.0), (0.0, 0.18, 0.0),
         (-1.40, 0.12, 0.30), (0.22, 0.0, 0.0), (-0.80, -1.10, 0.70)),
        (26, (0.0, 0.05, 0.0), (0.0, 0.05, 0.0), (0.0, -0.08, 0.0),
         (-1.15, 0.05, -0.12), (0.20, 0.0, -0.15), (math.radians(20), math.radians(10), math.radians(-15))),
    ]
    for kf in keyframes_dagger:
        f, sp_rot, ch_rot, hd_rot, ra, rf, rh = kf
        reset_pose(armature)
        pose_bone(armature, "J_Bip_C_Hips").location = (0.0, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Spine").rotation_euler = sp_rot
        pose_bone(armature, "J_Bip_C_Chest").rotation_euler = ch_rot
        pose_bone(armature, "J_Bip_C_Head").rotation_euler = hd_rot
        pose_bone(armature, "J_Bip_R_UpperArm").rotation_euler = ra
        pose_bone(armature, "J_Bip_R_LowerArm").rotation_euler = rf
        pose_bone(armature, "J_Bip_R_Hand").rotation_euler = rh
        key_animation_frame(armature, "attack_dagger", f)
    action.use_fake_user = True
    return action


def prepare_attack_bow_action(armature: bpy.types.Object) -> bpy.types.Action:
    fbx = os.path.join(PROJECT_DIR, "assets", "animations", "Shooting Arrow.fbx")
    if os.path.exists(fbx):
        return retarget_mixamo_fbx_to_action(armature, fbx, "attack_bow", lock_root_xy=True)

    action = bpy.data.actions.get("attack_bow") or bpy.data.actions.new("attack_bow")
    armature.animation_data_create()
    armature.animation_data.action = action
    
    keyframes_bow = [
        (0, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0),
         (-1.20, 0.0, 0.0), (0.10, 0.0, 0.0), (0.0, 0.0, 0.0)),
        (10, (0.0, 0.40, 0.0), (0.0, 0.45, 0.0), (0.0, -0.45, 0.0),
         (-1.45, 0.20, 0.55), (1.20, 0.0, 0.0), (-0.80, -0.40, 0.0)),
        (16, (0.0, 0.40, 0.0), (0.0, 0.45, 0.0), (0.0, -0.45, 0.0),
         (-1.45, 0.20, 0.55), (1.20, 0.0, 0.0), (-0.80, -0.40, 0.0)),
        (18, (0.0, 0.35, 0.0), (0.0, 0.40, 0.0), (0.0, -0.40, 0.0),
         (-1.30, 0.10, 0.40), (0.80, 0.0, 0.0), (-0.40, -0.20, 0.0)),
        (28, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0),
         (-1.20, 0.0, 0.0), (0.10, 0.0, 0.0), (0.0, 0.0, 0.0)),
    ]
    for kf in keyframes_bow:
        f, sp_rot, ch_rot, hd_rot, ra, rf, rh = kf
        reset_pose(armature)
        pose_bone(armature, "J_Bip_C_Hips").location = (0.0, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Spine").rotation_euler = sp_rot
        pose_bone(armature, "J_Bip_C_Chest").rotation_euler = ch_rot
        pose_bone(armature, "J_Bip_C_Head").rotation_euler = hd_rot
        pose_bone(armature, "J_Bip_L_UpperArm").rotation_euler = (-1.45, 0.0, 0.0)
        pose_bone(armature, "J_Bip_L_LowerArm").rotation_euler = (0.05, 0.0, 0.0)
        pose_bone(armature, "J_Bip_R_UpperArm").rotation_euler = ra
        pose_bone(armature, "J_Bip_R_LowerArm").rotation_euler = rf
        pose_bone(armature, "J_Bip_R_Hand").rotation_euler = rh
        key_animation_frame(armature, "attack_bow", f)
    action.use_fake_user = True
    return action


def prepare_attack_crossbow_action(armature: bpy.types.Object) -> bpy.types.Action:
    action = bpy.data.actions.get("attack_crossbow") or bpy.data.actions.new("attack_crossbow")
    armature.animation_data_create()
    armature.animation_data.action = action
    
    keyframes_cb = [
        (0, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0),
         (-1.35, 0.0, 0.0), (0.35, 0.0, 0.0), (0.0, 0.0, 0.0)),
        (10, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0),
         (-1.40, 0.0, 0.0), (0.40, 0.0, 0.0), (0.0, 0.0, 0.0)),
        (12, (0.05, 0.0, 0.0), (0.08, 0.0, 0.0), (0.0, 0.0, 0.0),
         (-1.50, 0.0, 0.0), (0.50, 0.0, 0.0), (0.15, 0.0, 0.0)),
        (22, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0), (0.0, 0.0, 0.0),
         (-1.35, 0.0, 0.0), (0.35, 0.0, 0.0), (0.0, 0.0, 0.0)),
    ]
    for kf in keyframes_cb:
        f, sp_rot, ch_rot, hd_rot, ra, rf, rh = kf
        reset_pose(armature)
        pose_bone(armature, "J_Bip_C_Hips").location = (0.0, 0.0, 0.0)
        pose_bone(armature, "J_Bip_C_Spine").rotation_euler = sp_rot
        pose_bone(armature, "J_Bip_C_Chest").rotation_euler = ch_rot
        pose_bone(armature, "J_Bip_C_Head").rotation_euler = hd_rot
        pose_bone(armature, "J_Bip_L_UpperArm").rotation_euler = (-1.25, 0.15, 0.35)
        pose_bone(armature, "J_Bip_L_LowerArm").rotation_euler = (0.75, 0.0, 0.0)
        pose_bone(armature, "J_Bip_R_UpperArm").rotation_euler = ra
        pose_bone(armature, "J_Bip_R_LowerArm").rotation_euler = rf
        pose_bone(armature, "J_Bip_R_Hand").rotation_euler = rh
        key_animation_frame(armature, "attack_crossbow", f)
    from fix_crossbow_idle_stance import apply_crossbow_idle_stance
    apply_crossbow_idle_stance(armature)
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

        pose_bone(armature, "J_Bip_C_Hips").location = (0.0, 0.685 + bounce_z, -0.160)
        pose_bone(armature, "J_Bip_L_UpperLeg").rotation_euler = (math.radians(-32), math.radians(-10), math.radians(-40))
        pose_bone(armature, "J_Bip_L_LowerLeg").rotation_euler = (math.radians(60), math.radians(-6), math.radians(24))
        pose_bone(armature, "J_Bip_L_Foot").rotation_euler = (math.radians(-16), 0.0, 0.0)

        pose_bone(armature, "J_Bip_R_UpperLeg").rotation_euler = (math.radians(-32), math.radians(10), math.radians(40))
        pose_bone(armature, "J_Bip_R_LowerLeg").rotation_euler = (math.radians(60), math.radians(6), math.radians(-24))
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

        pose_bone(armature, "J_Bip_C_Hips").location = (0.0, 0.685 + bounce_z, -0.160)
        pose_bone(armature, "J_Bip_C_Hips").rotation_euler = (pitch_bob, 0.0, sway_roll)

        pose_bone(armature, "J_Bip_L_UpperLeg").rotation_euler = (math.radians(-32) - pitch_bob * 0.5, math.radians(-10), math.radians(-40))
        pose_bone(armature, "J_Bip_L_LowerLeg").rotation_euler = (math.radians(60) + pitch_bob * 0.3, math.radians(-6), math.radians(24))
        pose_bone(armature, "J_Bip_L_Foot").rotation_euler = (math.radians(-16), 0.0, 0.0)

        pose_bone(armature, "J_Bip_R_UpperLeg").rotation_euler = (math.radians(-32) - pitch_bob * 0.5, math.radians(10), math.radians(40))
        pose_bone(armature, "J_Bip_R_LowerLeg").rotation_euler = (math.radians(60) + pitch_bob * 0.3, math.radians(6), math.radians(-24))
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

        pose_bone(armature, "J_Bip_C_Hips").location = (0.0, 0.685 + bounce_z, -0.160)
        pose_bone(armature, "J_Bip_C_Hips").rotation_euler = (pitch_bob, 0.0, sway_roll)

        pose_bone(armature, "J_Bip_L_UpperLeg").rotation_euler = (math.radians(-32) - pitch_bob * 0.5, math.radians(-10), math.radians(-40))
        pose_bone(armature, "J_Bip_L_LowerLeg").rotation_euler = (math.radians(60) + pitch_bob * 0.3, math.radians(-6), math.radians(24))
        pose_bone(armature, "J_Bip_L_Foot").rotation_euler = (math.radians(-16), 0.0, 0.0)

        pose_bone(armature, "J_Bip_R_UpperLeg").rotation_euler = (math.radians(-32) - pitch_bob * 0.5, math.radians(10), math.radians(40))
        pose_bone(armature, "J_Bip_R_LowerLeg").rotation_euler = (math.radians(60) + pitch_bob * 0.3, math.radians(6), math.radians(-24))
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
        pb_hips.location = Vector((0.0, 0.685 + bounce_z, -0.160))
        pb_hips.rotation_quaternion = Euler((pitch_bob, 0.0, 0.0), 'XYZ').to_quaternion()
        pb_hips.keyframe_insert(data_path="location", frame=f)
        pb_hips.keyframe_insert(data_path="rotation_quaternion", frame=f)

        for side, sign in [("L", -1), ("R", 1)]:
            armature.pose.bones[f"J_Bip_{side}_UpperLeg"].rotation_quaternion = Euler((math.radians(-32), math.radians(sign * 10), math.radians(sign * 40)), 'XYZ').to_quaternion()
            armature.pose.bones[f"J_Bip_{side}_LowerLeg"].rotation_quaternion = Euler((math.radians(60), math.radians(sign * 6), math.radians(-sign * 24)), 'XYZ').to_quaternion()
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
    """Heroic mounted spear thrust along the horse's right flank (Female character pack):
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
        pb_hips.location = Vector((0.0, 0.685 + bounce_z, -0.160))
        pb_hips.rotation_quaternion = Euler((pitch_bob, 0.0, 0.0), 'XYZ').to_quaternion()
        pb_hips.keyframe_insert(data_path="location", frame=f)
        pb_hips.keyframe_insert(data_path="rotation_quaternion", frame=f)

        for side, sign in [("L", -1), ("R", 1)]:
            armature.pose.bones[f"J_Bip_{side}_UpperLeg"].rotation_quaternion = Euler((math.radians(-32), math.radians(sign * 10), math.radians(sign * 40)), 'XYZ').to_quaternion()
            armature.pose.bones[f"J_Bip_{side}_LowerLeg"].rotation_quaternion = Euler((math.radians(60), math.radians(sign * 6), math.radians(-sign * 24)), 'XYZ').to_quaternion()
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
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = armature.data.edit_bones.get("J_Bip_C_Hips")
    if eb:
        eb.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.select_set(False)

    for pb in armature.pose.bones:
        pb.rotation_mode = "QUATERNION"

    def get_ss_action(fbx_name: str, act_name: str) -> bpy.types.Action:
        fbx_path = os.path.join(SWORD_SHIELD_PACK, fbx_name)
        return retarget_mixamo_fbx_to_action(armature, fbx_path, act_name)

    actions = [
        prepare_tpose_action(armature),
        get_ss_action("sword and shield idle.fbx", "idle"),
        get_ss_action("sword and shield walk.fbx", "walk"),
        get_ss_action("sword and shield run.fbx", "run"),
        get_ss_action("sword and shield block.fbx", "guard"),
        get_ss_action("sword and shield impact.fbx", "hit"),
        prepare_hit_back_action(armature),
        get_ss_action("sword and shield impact (2).fbx", "knockback"),
        get_ss_action("sword and shield death.fbx", "down"),
        get_ss_action("sword and shield kick.fbx", "attack_unarmed"),
        get_ss_action("sword and shield attack.fbx", "attack_jump_heavy"),
        get_ss_action("sword and shield attack.fbx", "attack_sword"),
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
    return [a.name for a in actions]


# =========================================================================
# 6. Main Female Pack Builder Entry Point
# =========================================================================

def main() -> None:
    disk_log("WORLDGOING_FEMALE_PACK_BUILD_START")
    if not os.path.exists(SOURCE_VRM):
        raise FileNotFoundError(SOURCE_VRM)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    clear_scene()
    disk_log("Cleared scene. Loading VRM addon...")
    load_vrm_addon(ADDON_DIR)
    disk_log("Importing VRM...")
    bpy.ops.import_scene.vrm(filepath=SOURCE_VRM, use_addon_preferences=True)
    bpy.context.scene.render.fps = 24
    bpy.context.view_layer.update()
    disk_log("VRM imported successfully.")

    armature = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    body = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.name == "Body")
    face = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.name == "Face")
    hair = next(obj for obj in bpy.context.scene.objects if obj.type == "MESH" and obj.name == "Hair001")

    # Materials
    skin_mat = material("Worldgoing_Skin_Female", (0.94, 0.72, 0.58), roughness=0.75)
    hair_mat = material("Worldgoing_Hair_Dark", (0.012, 0.012, 0.014), roughness=0.55)
    leather_body = material("Worldgoing_Leather_Body", (0.24, 0.09, 0.02), roughness=0.82)
    leather_edge = material("Worldgoing_Leather_Edge", (0.34, 0.14, 0.03), roughness=0.78)
    leather_cuff = leather_edge
    underwear_mat = material("Worldgoing_Underwear_Fabric", (0.15, 0.18, 0.24), roughness=0.88)
    gold_mat = material("Worldgoing_Gold_Female", (0.85, 0.62, 0.12), metallic=0.85, roughness=0.28)
    silver_mat = material("Worldgoing_Silver_Female", (0.90, 0.90, 0.92), metallic=0.90, roughness=0.22)
    steel_mat = material("Worldgoing_Steel_Female", (0.75, 0.76, 0.78), metallic=0.92, roughness=0.25)
    wood_mat = material("Worldgoing_Wood_Female", (0.35, 0.18, 0.08), roughness=0.75)
    tassel_mat = material("Worldgoing_Tassel_Female", (0.80, 0.10, 0.10), roughness=0.85)
    grip_mat = material("Worldgoing_Grip_Female", (0.15, 0.08, 0.05), roughness=0.80)
    string_mat = material("Worldgoing_String_Female", (0.95, 0.95, 0.95), roughness=0.40)
    cape_mat = material("Worldgoing_Cape_Female", (0.12, 0.18, 0.32), roughness=0.85)
    shield_mat = material("Worldgoing_Shield_Female", (0.10, 0.22, 0.45), roughness=0.40)

    # 2. Gender-specific Body, Clothing & Boots
    disk_log("Making skin...")
    body_skin = make_female_body_skin(body, armature)
    disk_log("Making underwear...")
    underwear_parts = make_female_underwear(body_skin, armature, underwear_mat) + load_chinese_lining(armature, is_female=True)
    disk_log("Making armor...")
    armor_parts = make_female_leather_armor(body_skin, armature, leather_body, leather_edge, underwear_mat, steel_mat, gold_mat, leather_body)
    disk_log("Making boots...")
    boots_parts = make_female_boots(body, armature, leather_body, leather_cuff)

    # 3. Shape-Key Baked Faces (Exact Geometric Math + Shader Preservation)
    disk_log("Making faces with exact shape key morphing...")
    face_one = create_baked_face_variant(face, "Face_Standard_01", "face_standard_01", {}, armature)
    face_two = create_baked_face_variant(face, "Face_Standard_02", "face_standard_02", {"Fcl_ALL_Joy": 0.65, "Fcl_MTH_Joy": 0.50}, armature)
    face_three = create_baked_face_variant(face, "Face_Standard_03", "face_standard_03", {"Fcl_ALL_Angry": 0.70, "Fcl_BRW_Angry": 0.75}, armature)
    face_four = create_baked_face_variant(face, "Face_Standard_04", "face_standard_04", {"Fcl_ALL_Fun": 0.65, "Fcl_BRW_Joy": 0.60, "Fcl_ALL_Surprised": 0.20}, armature)

    # 4. Anti-Clipping Solid 360-Degree Hair Variants
    disk_log("Making hair 1..4...")
    hair_one = make_female_hair_twintails(hair, "Hair_Long_01", "hair_long_01", armature, hair_mat)
    hair_two = make_female_flowing_hair(hair, "Hair_Long_02", "hair_long_02", armature, hair_mat)
    hair_three = make_female_bob_hair(hair, "Hair_Long_03", "hair_long_03", armature, hair_mat)
    hair_four_parts = make_female_high_ponytail(hair, "Hair_Long_04", "hair_long_04", armature, hair_mat, gold_mat)

    # 5. Shared Weapons (7 Types), Forward Facing Shield, Cape
    disk_log("Making shared weapons, scabbards, back holsters, shield, cape...")
    longsword_parts = make_longsword(armature, steel_mat, grip_mat, gold_mat, leather_body)
    spear_parts = make_spear(armature, wood_mat, steel_mat, gold_mat, tassel_mat)
    axe_parts = make_axe(armature, wood_mat, steel_mat, gold_mat, grip_mat)
    hammer_parts = make_hammer(armature, wood_mat, steel_mat, gold_mat, grip_mat)
    dagger_parts = make_dagger(armature, steel_mat, gold_mat, grip_mat)
    bow_parts = make_bow(armature, wood_mat, gold_mat, grip_mat, string_mat)
    crossbow_parts = make_crossbow(armature, wood_mat, steel_mat, gold_mat, string_mat)
    shield_parts = make_shield(armature, shield_mat, gold_mat, silver_mat, leather_body)
    cape_parts = make_cape(armature, cape_mat, gold_mat, silver_mat)
    chinese_cape_parts = make_chinese_cape(armature, is_female=True, create_rigid_fn=create_bone_rigid_component)
    helmet_parts = make_leather_helmet(armature, leather_body, leather_body, leather_edge, steel_mat, gold_mat)
    iron_helmet_parts = make_chinese_iron_helmet(armature, is_female=True, create_rigid_fn=create_bone_rigid_component)
    steel_helmet_parts = make_chinese_steel_helmet(armature, is_female=True, create_rigid_fn=create_bone_rigid_component)
    chinese_leather_parts, mingguang_helmet_parts = load_chinese_gear(armature, is_female=True)
    western_armor_parts, western_helmet_parts, western_boots_parts = load_western_iron(armature, is_female=True)
    all_helmet_parts = helmet_parts + iron_helmet_parts + steel_helmet_parts + mingguang_helmet_parts + load_chinese_leather_helmet(armature, is_female=True) + western_helmet_parts

    iron_armor_parts = make_chinese_iron_armor(armature, source_raw_body=body_skin, is_female=True, create_rigid_fn=create_bone_rigid_component)
    mingguang_armor_parts = make_mingguang_armor(armature, source_raw_body=body_skin, is_female=True, create_rigid_fn=create_bone_rigid_component)
    all_armor_parts = armor_parts + iron_armor_parts + mingguang_armor_parts + chinese_leather_parts + western_armor_parts

    iron_boots_parts = make_chinese_iron_boots(armature, source_raw_body=body_skin, is_female=True, create_rigid_fn=create_bone_rigid_component)
    mingguang_boots_parts = make_mingguang_boots(armature, source_raw_body=body_skin, is_female=True, create_rigid_fn=create_bone_rigid_component)
    all_boots_parts = boots_parts + iron_boots_parts + mingguang_boots_parts + load_chinese_leather_boots(armature,is_female=True) + western_boots_parts + load_medieval_shoes(armature,is_female=True)

    all_weapon_parts = longsword_parts + spear_parts + axe_parts + hammer_parts + dagger_parts + bow_parts + crossbow_parts

    # Hide source objects
    for source_obj in (body, face, hair):
        source_obj.hide_render = True
        source_obj.hide_viewport = True

    export_objects = [
        armature, body_skin,
        face_one, face_two, face_three, face_four,
        hair_one, hair_two, hair_three, *hair_four_parts,
    ] + all_boots_parts + underwear_parts + all_armor_parts + all_weapon_parts + shield_parts + cape_parts + chinese_cape_parts + all_helmet_parts

    disk_log(f"Total modular parts count: {len(export_objects) - 1}")

    disk_log("Retargeting 16 complete animation actions with upright head pitch...")
    action_names = prepare_all_actions(armature)
    bind_cape_action_tracks(armature, chinese_cape_parts + mingguang_helmet_parts)
    disk_log(f"Actions prepared: {action_names}")

    from repair_character_audit import apply_repairs
    repaired_parts = [obj for obj in export_objects if obj != armature]
    apply_repairs(armature, repaired_parts, sys.modules[__name__], True)
    from load_authored_weapon_materials import load_weapon_materials
    repaired_parts.extend(load_weapon_materials(armature, True))
    from load_authored_medieval_cloth import load_medieval_cloth
    cloth_parts = load_medieval_cloth(armature, True)
    repaired_parts.extend(cloth_parts)
    all_armor_parts.extend(cloth_parts)
    from load_authored_gendered_hair import load_gendered_hair
    repaired_parts.extend(load_gendered_hair(armature, True))
    from refine_body_joints import refine_body_joints
    refine_body_joints(armature, repaired_parts)
    from fit_armor_bracers import fit_armor_bracers
    fit_armor_bracers(armature, repaired_parts)
    from ensure_morph_uv import ensure_blender_morph_uv
    ensure_blender_morph_uv(repaired_parts)
    export_objects = [armature, *repaired_parts]

    # Export GLB (Make all export objects visible & selected)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in export_objects:
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.context.scene.render.fps = 24

    disk_log("Exporting glTF/GLB...")
    legacy_clips = Path(LEGACY_ANIMATION_SOURCE).read_bytes() if Path(LEGACY_ANIMATION_SOURCE).exists() else None
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_GLB,
        use_selection=True,
        export_format="GLB",
        export_apply=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_frame_range=False,
        export_frame_step=1,
        export_force_sampling=False,
        export_optimize_disable_viewport=True,
        export_skins=True,
        export_morph=True,
        export_materials="EXPORT",
    )
    if legacy_clips:
        from author_chinese_cape import preserve_legacy_clips
        preserve_legacy_clips('female', Path(OUTPUT_GLB), legacy_clips, prune_duplicates=True)
    disk_log(f"Saved GLB file: {OUTPUT_GLB}")

    # Configure default visibility for blend
    for obj in repaired_parts:
        default_visible = obj.name in ("Body_Standard_Female", "Face_Standard_01", "Hair_Long_01") or obj.name.startswith(("Outfit_Underlayer_01", "Boots_Leather_01"))
        obj.hide_render = not default_visible
        obj.hide_viewport = not default_visible

    # Export Blend
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND)
    disk_log(f"Saved blend file: {OUTPUT_BLEND}")

    # Metadata
    metadata = {
        "asset_id": "standard_anime_female_character_pack",
        "source": "HairSample_Female.vrm",
        "hair_style_ids": [f"hair_female_{i:02d}" for i in range(1, 9)],
        "parts": {slot: [obj.name for obj in repaired_parts if obj.get("worldgoing_component_slot") == slot]
                  for slot in ("body", "face", "hair", "helmet", "outfit", "armor", "cape", "weapon", "shield", "boots")},
        "animations": action_names,
        "skeleton": "Armature",
    }
    with open(OUTPUT_METADATA, "w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2)

    disk_log(
        "WORLDGOING_STANDARD_ANIME_FEMALE_CHARACTER_PACK_BUILD_PASS "
        f"parts={len(export_objects) - 1} face_options=4 actions={action_names} "
        f"blend={OUTPUT_BLEND} glb={OUTPUT_GLB}"
    )


if __name__ == "__main__":
    main()
