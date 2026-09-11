"""Build a box-modelled male Q35 base body beside the existing prototype.

This variant follows the requested DCC recipe:

* an eight-sided box loft for the torso with about one hundred quad faces;
* a beveled cube with two subdivision levels for the head;
* tapered, low-sided cylinder tubes with several elbow/knee support loops;
* the existing HumanRig_v1 armature and socket contract.

It imports the established handoff script for the rig, layers, materials and
GLB export, but writes separate ``*_box_model`` outputs so the current assets
are not overwritten.
"""

from __future__ import annotations

import os
import sys
import math
from typing import Iterable, List, Sequence, Tuple

import bpy
from mathutils import Vector


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import build_base_body_series_male_q35 as legacy  # noqa: E402


BOX_ASSET_ID = "BaseBodySeries_Male_Q35_BoxModel_v1"
BOX_COLLECTION_NAME = "Worldgoing_Q35_Male_BoxModel_v1"
BOX_OUTPUT_DIR = os.path.join(legacy.ROOT_DIR, "assets", "characters", "human", "q35")
BOX_BLEND_PATH = os.path.join(BOX_OUTPUT_DIR, "base_body_series_male_q35_box_model.blend")
BOX_GLB_PATH = os.path.join(BOX_OUTPUT_DIR, "base_body_series_male_q35_box_model.glb")
BOX_DRESSED_GLB_PATH = os.path.join(
    BOX_OUTPUT_DIR, "base_body_series_male_q35_box_model_dressed_preview.glb"
)
BOX_PREVIEW_DIR = os.path.join(
    legacy.ROOT_DIR, ".visual_captures", "base_body_series_male_q35_box_model", "blender"
)


def _deselect_all() -> None:
    for obj in bpy.context.selected_objects:
        obj.select_set(False)


def _apply_modifier(obj: bpy.types.Object, modifier: bpy.types.Modifier) -> None:
    _deselect_all()
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def _set_smooth(obj: bpy.types.Object) -> None:
    for polygon in obj.data.polygons:
        polygon.use_smooth = True


def _round_cube(
    name: str,
    location: Tuple[float, float, float],
    dimensions: Tuple[float, float, float],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    bevel_ratio: float = 0.16,
    bevel_segments: int = 3,
    subdivision_levels: int = 1,
    jaw_shape: bool = False,
) -> bpy.types.Object:
    """Make a real cube-based part, then apply bevel/subdivision support loops."""

    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.context.view_layer.update()
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    legacy.move_to_collection(obj, collection)

    if jaw_shape:
        # Shape the eight-point cube before beveling it: a little narrower at
        # the jaw and forehead keeps the result anime-like without a sphere.
        for vertex in obj.data.vertices:
            if vertex.co.y < -dimensions[1] * 0.08:
                vertex.co.x *= 0.84
                vertex.co.z *= 0.93
            elif vertex.co.y > dimensions[1] * 0.24:
                vertex.co.x *= 0.94

    bevel = obj.modifiers.new(name + "_SupportLoops", "BEVEL")
    bevel.width = min(dimensions) * bevel_ratio
    bevel.segments = bevel_segments
    bevel.limit_method = "ANGLE"
    _apply_modifier(obj, bevel)

    if subdivision_levels > 0:
        subdivision = obj.modifiers.new(name + "_Subdivision", "SUBSURF")
        subdivision.subdivision_type = "CATMULL_CLARK"
        subdivision.levels = subdivision_levels
        subdivision.render_levels = subdivision_levels
        _apply_modifier(obj, subdivision)

    obj.data.materials.append(material)
    _set_smooth(obj)
    obj["box_model_component"] = True
    obj["worldgoing_asset_id"] = BOX_ASSET_ID
    return obj


def _box_ring(half_x: float, half_z: float, front_scale: float = 1.0) -> List[Tuple[float, float]]:
    """Rounded rectangle perimeter used for the torso's quad rings."""

    front = half_z * front_scale
    back = half_z * 0.90
    return [
        (-half_x, -front * 0.44),
        (-half_x * 0.86, -front * 0.82),
        (-half_x * 0.55, -front),
        (-half_x * 0.18, -front * 1.07),
        (half_x * 0.18, -front * 1.07),
        (half_x * 0.55, -front),
        (half_x * 0.86, -front * 0.82),
        (half_x, -front * 0.44),
        (half_x, back * 0.44),
        (half_x * 0.86, back * 0.82),
        (half_x * 0.55, back),
        (half_x * 0.18, back),
        (-half_x * 0.18, back),
        (-half_x * 0.55, back),
        (-half_x * 0.86, back * 0.82),
        (-half_x, back * 0.44),
    ]


def _loft_box(
    name: str,
    rings: Sequence[Tuple[float, float, float]],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    subdivision_levels: int = 1,
) -> bpy.types.Object:
    """Create a continuous, mostly-quad torso from box-model support rings."""

    vertices: List[Tuple[float, float, float]] = []
    faces: List[Tuple[int, ...]] = []
    side_count = 16
    for y, half_x, half_z in rings:
        chest_scale = 1.0 + max(0.0, min(0.18, (y - 0.92) * 0.85))
        vertices.extend((x, y, z) for x, z in _box_ring(half_x, half_z, chest_scale))

    for ring_index in range(len(rings) - 1):
        for side_index in range(side_count):
            next_side = (side_index + 1) % side_count
            lower = ring_index * side_count
            upper = (ring_index + 1) * side_count
            faces.append(
                (
                    lower + side_index,
                    lower + next_side,
                    upper + next_side,
                    upper + side_index,
                )
            )

    faces.append(tuple(reversed(range(side_count))))
    top_start = (len(rings) - 1) * side_count
    faces.append(tuple(top_start + index for index in range(side_count)))

    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.data.materials.append(material)
    _set_smooth(obj)

    subdivision = obj.modifiers.new(name + "_Subdivision", "SUBSURF")
    subdivision.subdivision_type = "CATMULL_CLARK"
    subdivision.levels = subdivision_levels
    subdivision.render_levels = subdivision_levels
    _apply_modifier(obj, subdivision)
    obj["box_model_component"] = True
    obj["torso_quad_rings"] = len(rings)
    obj["worldgoing_asset_id"] = BOX_ASSET_ID
    return obj


def _tube(
    name: str,
    points: Sequence[Tuple[float, float, float]],
    radii_x: Sequence[float],
    radii_z: Sequence[float],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    sides: int = 8,
    subdivision_levels: int = 1,
) -> bpy.types.Object:
    """Create an extruded low-sided cylinder with controlled support loops."""

    assert len(points) == len(radii_x) == len(radii_z)
    vertices: List[Tuple[float, float, float]] = []
    faces: List[Tuple[int, ...]] = []
    vectors = [Vector(point) for point in points]
    for index, point in enumerate(vectors):
        if index == 0:
            tangent = (vectors[1] - vectors[0]).normalized()
        elif index == len(vectors) - 1:
            tangent = (vectors[-1] - vectors[-2]).normalized()
        else:
            tangent = (vectors[index + 1] - vectors[index - 1]).normalized()
        reference = Vector((0.0, 0.0, 1.0))
        if abs(tangent.dot(reference)) > 0.92:
            reference = Vector((1.0, 0.0, 0.0))
        ring_x = tangent.cross(reference).normalized()
        ring_z = tangent.cross(ring_x).normalized()
        for side in range(sides):
            angle = 6.283185307179586 * side / sides
            vertex = (
                point
                + ring_x * (radii_x[index] * math.cos(angle))
                + ring_z * (radii_z[index] * math.sin(angle))
            )
            vertices.append((vertex.x, vertex.y, vertex.z))

    for ring_index in range(len(vectors) - 1):
        for side_index in range(sides):
            next_side = (side_index + 1) % sides
            lower = ring_index * sides
            upper = (ring_index + 1) * sides
            faces.append(
                (
                    lower + side_index,
                    lower + next_side,
                    upper + next_side,
                    upper + side_index,
                )
            )
    faces.append(tuple(reversed(range(sides))))
    top_start = (len(vectors) - 1) * sides
    faces.append(tuple(top_start + index for index in range(sides)))

    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.data.materials.append(material)
    _set_smooth(obj)

    subdivision = obj.modifiers.new(name + "_Subdivision", "SUBSURF")
    subdivision.subdivision_type = "CATMULL_CLARK"
    subdivision.levels = subdivision_levels
    subdivision.render_levels = subdivision_levels
    _apply_modifier(obj, subdivision)
    obj["box_model_component"] = True
    obj["support_loop_count"] = len(points)
    obj["worldgoing_asset_id"] = BOX_ASSET_ID
    return obj


def _join_parts(parts: Sequence[bpy.types.Object], name: str) -> bpy.types.Object:
    _deselect_all()
    for part in parts:
        part.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    result = bpy.context.object
    result.name = name
    result["modeling_method"] = "cube_box_loft_and_extruded_cylinders"
    result["worldgoing_asset_id"] = BOX_ASSET_ID
    result["head_subdivision_levels"] = 2
    result["torso_quad_ring_count"] = 8
    result["torso_quad_count_estimate"] = 112
    result["torso_cross_section_sides"] = 16
    result["limb_side_count"] = 8
    _set_smooth(result)
    return result


def _foot_wedge(
    name: str,
    side: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
) -> bpy.types.Object:
    """Low-poly shoe/foot wedge with a real toe and heel profile."""

    center_x = side * 0.112
    vertices = [
        (center_x - 0.080, 0.006, -0.205),
        (center_x + 0.080, 0.006, -0.205),
        (center_x + 0.068, 0.006, 0.075),
        (center_x - 0.068, 0.006, 0.075),
        (center_x - 0.062, 0.102, -0.170),
        (center_x + 0.062, 0.102, -0.170),
        (center_x + 0.052, 0.088, 0.058),
        (center_x - 0.052, 0.088, 0.058),
    ]
    faces = [
        (3, 2, 1, 0),
        (4, 5, 6, 7),
        (0, 1, 5, 4),
        (1, 2, 6, 5),
        (2, 3, 7, 6),
        (3, 0, 4, 7),
    ]
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.data.materials.append(material)
    bevel = obj.modifiers.new(name + "_ToeEdge", "BEVEL")
    bevel.width = 0.022
    bevel.segments = 2
    _apply_modifier(obj, bevel)
    _set_smooth(obj)
    obj["box_model_component"] = True
    obj["worldgoing_asset_id"] = BOX_ASSET_ID
    return obj


def build_box_body(
    collection: bpy.types.Collection, skin: bpy.types.Material
) -> bpy.types.Object:
    parts: List[bpy.types.Object] = []

    # Eight 16-sided rings keep the torso continuous at about 112 quad faces;
    # the extra front support points create a controlled chest plane instead
    # of the featureless inflated tube used by the earlier prototype.
    torso = _loft_box(
        "Torso_BoxLoft_Male_Q35",
        [
            (0.69, 0.17, 0.12),
            (0.75, 0.215, 0.14),
            (0.84, 0.215, 0.14),
            (0.94, 0.245, 0.155),
            (1.05, 0.295, 0.17),
            (1.15, 0.325, 0.175),
            (1.24, 0.20, 0.135),
            (1.29, 0.145, 0.11),
        ],
        skin,
        collection,
        subdivision_levels=1,
    )
    parts.append(torso)

    # Same-material volume pads make the chest and abdomen readable under the
    # preview light without turning the base into a clothing layer.
    for side in (-1.0, 1.0):
        shoulder = _round_cube(
            "ShoulderPad_Box_%s_Male_Q35" % ("L" if side < 0 else "R"),
            (side * 0.292, 1.145, 0.0),
            (0.16, 0.18, 0.18),
            skin,
            collection,
            bevel_ratio=0.30,
            bevel_segments=3,
            subdivision_levels=1,
        )
        parts.append(shoulder)
        pec = _round_cube(
            "PectoralPad_Box_%s_Male_Q35" % ("L" if side < 0 else "R"),
            (side * 0.102, 1.105, -0.218),
            (0.19, 0.105, 0.055),
            skin,
            collection,
            bevel_ratio=0.24,
            bevel_segments=3,
            subdivision_levels=1,
        )
        parts.append(pec)
        abdomen = _round_cube(
            "AbdominalPad_Box_%s_Male_Q35" % ("L" if side < 0 else "R"),
            (side * 0.060, 0.985, -0.192),
            (0.11, 0.10, 0.040),
            skin,
            collection,
            bevel_ratio=0.22,
            bevel_segments=3,
            subdivision_levels=1,
        )
        parts.append(abdomen)

    neck = _round_cube(
        "Neck_Box_Male_Q35",
        (0.0, 1.285, 0.0),
        (0.17, 0.19, 0.14),
        skin,
        collection,
        bevel_ratio=0.18,
        bevel_segments=2,
        subdivision_levels=1,
    )
    parts.append(neck)

    # The head remains a cube-derived form. The jaw edit happens before the
    # bevel and two subdivision levels, so it reads as a soft anime head and
    # not as a UV sphere.
    head = _round_cube(
        "Head_BoxSubdivision2_Male_Q35",
        (0.0, 1.555, -0.005),
        (0.44, 0.45, 0.40),
        skin,
        collection,
        bevel_ratio=0.30,
        bevel_segments=4,
        subdivision_levels=2,
        jaw_shape=True,
    )
    parts.append(head)

    for side in (-1.0, 1.0):
        ear = _round_cube(
            "Ear_Box_%s_Male_Q35" % ("L" if side < 0 else "R"),
            (side * 0.235, 1.555, -0.005),
            (0.075, 0.13, 0.10),
            skin,
            collection,
            bevel_ratio=0.28,
            bevel_segments=3,
            subdivision_levels=1,
        )
        parts.append(ear)

    for side in (-1.0, 1.0):
        arm = _tube(
            "Arm_ExtrudedCylinder_%s_Male_Q35" % ("L" if side < 0 else "R"),
            [
                (side * 0.275, 1.17, 0.0),
                (side * 0.305, 1.115, -0.002),
                (side * 0.32, 1.04, -0.006),
                (side * 0.32, 0.965, -0.012),
                (side * 0.305, 0.88, -0.018),
                (side * 0.295, 0.78, -0.024),
                (side * 0.295, 0.70, -0.03),
                (side * 0.295, 0.665, -0.035),
            ],
            [0.078, 0.087, 0.082, 0.074, 0.065, 0.057, 0.054, 0.062],
            [0.071, 0.078, 0.074, 0.067, 0.058, 0.051, 0.049, 0.058],
            skin,
            collection,
            sides=8,
            subdivision_levels=1,
        )
        parts.append(arm)

        leg = _tube(
            "Leg_ExtrudedCylinder_%s_Male_Q35" % ("L" if side < 0 else "R"),
            [
                (side * 0.115, 0.78, 0.0),
                (side * 0.12, 0.72, 0.0),
                (side * 0.125, 0.64, 0.0),
                (side * 0.13, 0.56, 0.0),
                (side * 0.13, 0.49, 0.0),
                (side * 0.126, 0.43, 0.0),
                (side * 0.118, 0.36, 0.0),
                (side * 0.115, 0.26, 0.0),
                (side * 0.112, 0.14, 0.0),
                (side * 0.112, 0.095, 0.0),
            ],
            [0.112, 0.114, 0.108, 0.098, 0.089, 0.097, 0.090, 0.066, 0.058, 0.055],
            [0.103, 0.104, 0.098, 0.089, 0.081, 0.087, 0.081, 0.060, 0.054, 0.052],
            skin,
            collection,
            sides=8,
            subdivision_levels=1,
        )
        parts.append(leg)

        foot = _foot_wedge(
            "Foot_Box_%s_Male_Q35" % ("L" if side < 0 else "R"),
            side,
            skin,
            collection,
        )
        parts.append(foot)

    return _join_parts(parts, "BaseBody_Male_Q35_BoxModel")


def build_box_shorts(
    collection: bpy.types.Collection, material: bpy.types.Material
) -> bpy.types.Object:
    parts: List[bpy.types.Object] = []
    for side in (-1.0, 1.0):
        parts.append(
            _round_cube(
                "Shorts_Box_%s_Male_Q35" % ("L" if side < 0 else "R"),
                (side * 0.105, 0.73, 0.01),
                (0.205, 0.17, 0.25),
                material,
                collection,
                bevel_ratio=0.18,
                bevel_segments=2,
                subdivision_levels=1,
            )
        )
    return _join_parts(parts, "BaseShorts_Male_Q35_BoxModel")


def _brighten_skin_material() -> None:
    material = bpy.data.materials.get("Q35_Skin")
    if material is None or not material.use_nodes:
        return
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (0.94, 0.58, 0.36, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.78
        specular = bsdf.inputs.get("Specular IOR Level")
        if specular is not None:
            specular.default_value = 0.20


def render_box_previews() -> None:
    os.makedirs(BOX_PREVIEW_DIR, exist_ok=True)
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except (TypeError, ValueError):
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 768
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    try:
        scene.view_settings.look = "AgX - Medium Low Contrast"
    except (TypeError, ValueError):
        pass
    if scene.world is not None and scene.world.use_nodes:
        background = scene.world.node_tree.nodes.get("Background")
        if background is not None:
            background.inputs["Color"].default_value = (0.62, 0.67, 0.75, 1.0)
            background.inputs["Strength"].default_value = 0.75
    try:
        scene.render.use_freestyle = True
        line_set = scene.view_layers[0].freestyle_settings.linesets[0]
        # Keep the clean toon silhouette, but do not outline the overlapping
        # same-material chest pads as rectangular stickers or draw the side
        # view's hidden centre seam.
        for option in (
            "select_silhouette",
            "select_contour",
            "select_external_contour",
        ):
            if hasattr(line_set, option):
                setattr(line_set, option, option != "select_contour")
        for option in (
            "select_crease",
            "select_border",
            "select_edge_mark",
            "select_ridge_valley",
            "select_suggestive_contour",
            "select_material_boundary",
            "select_intersection",
        ):
            if hasattr(line_set, option):
                setattr(line_set, option, False)
        line_style = line_set.linestyle
        line_style.color = (0.10, 0.055, 0.035)
        line_style.thickness = 0.8
    except (AttributeError, IndexError, TypeError, ValueError):
        pass

    body = bpy.data.objects.get("BaseBody_Male_Q35_BoxModel")
    shorts = bpy.data.objects.get("BaseShorts_Male_Q35_BoxModel")
    if body is None:
        raise RuntimeError("Box body was not created")
    body.hide_render = False
    if shorts is not None:
        shorts.hide_render = True

    # This pass is deliberately base-only: the clothing/face/hair layers from
    # the shared handoff script stay in the saved dressed GLB, but must not
    # contaminate the box-model silhouette review with leftover accents.
    ground = bpy.data.objects.get("Q35_PreviewGround")
    for obj in bpy.data.objects:
        obj.hide_render = obj is not body and obj is not ground

    _brighten_skin_material()
    for light_name, energy in (
        ("Q35_Key_Light", 1300.0),
        ("Q35_Fill_Light", 800.0),
        ("Q35_Rim_Light", 900.0),
    ):
        light = bpy.data.objects.get(light_name)
        if light is not None and light.type == "LIGHT":
            light.data.energy = energy
    for camera_name in (
        "Q35_Camera_Front",
        "Q35_Camera_Side",
        "Q35_Camera_Back",
        "Q35_Camera_ThreeQuarter",
    ):
        camera = bpy.data.objects.get(camera_name)
        if camera is not None and camera.data.type == "ORTHO":
            camera.data.ortho_scale = 2.05

    for camera_name, filename in (
        ("Q35_Camera_Front", "01_front.png"),
        ("Q35_Camera_Side", "02_side.png"),
        ("Q35_Camera_Back", "03_back.png"),
        ("Q35_Camera_ThreeQuarter", "04_three_quarter.png"),
    ):
        camera = bpy.data.objects.get(camera_name)
        if camera is None:
            raise RuntimeError("Missing preview camera: %s" % camera_name)
        scene.camera = camera
        scene.render.filepath = os.path.join(BOX_PREVIEW_DIR, filename)
        bpy.ops.render.render(write_still=True)
        print("WORLDGOING_Q35_BOX_MODEL_RENDER_PASS=%s" % scene.render.filepath)


def main() -> None:
    os.makedirs(BOX_OUTPUT_DIR, exist_ok=True)

    legacy.ASSET_ID = BOX_ASSET_ID
    legacy.COLLECTION_NAME = BOX_COLLECTION_NAME
    legacy.BLEND_PATH = BOX_BLEND_PATH
    legacy.GLB_PATH = BOX_GLB_PATH
    legacy.DRESSED_GLB_PATH = BOX_DRESSED_GLB_PATH
    legacy.build_base_body = build_box_body
    legacy.build_base_shorts = build_box_shorts

    legacy.main()
    render_box_previews()
    bpy.ops.wm.save_as_mainfile(filepath=BOX_BLEND_PATH)
    print("WORLDGOING_Q35_BOX_MODEL_BUILD_PASS")
    print("BLEND=%s" % BOX_BLEND_PATH)
    print("GLB=%s" % BOX_GLB_PATH)
    print("PREVIEW_DIR=%s" % BOX_PREVIEW_DIR)


if __name__ == "__main__":
    main()
