"""Build a viewable preview from a standard anime base mesh.

This deliberately keeps the imported VRoid model isolated from the existing
HumanBase prototype. It is a source/shape comparison asset, not a production
replacement for the Worldgoing rig yet.
"""

import os
import sys
from typing import Iterable

import bpy
import bmesh
from mathutils import Vector


PROJECT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
ANIME_GENDER = os.environ.get("WORLDGOING_ANIME_GENDER", "male").strip().lower()
if ANIME_GENDER not in {"male", "female"}:
    raise ValueError("WORLDGOING_ANIME_GENDER must be male or female")
ANIME_SAMPLE = "HairSample_Male.vrm" if ANIME_GENDER == "male" else "HairSample_Female.vrm"
BODY_ONLY = os.environ.get("WORLDGOING_ANIME_BODY_ONLY", "0").strip() == "1"
ASSET_PREFIX = "base_body_series_%s_standard_anime%s" % (ANIME_GENDER, "_body_only" if BODY_ONLY else "")
MODEL_PATH = os.path.join(PROJECT_DIR, ".tools", "standard_anime_base", ANIME_SAMPLE)
ADDON_DIR = os.path.join(PROJECT_DIR, ".tools", "standard_anime_base", "io_scene_vrm")
PREVIEW_DIR = os.path.join(PROJECT_DIR, ".visual_captures", ASSET_PREFIX, "blender")
BLEND_PATH = os.path.join(PROJECT_DIR, "assets", "characters", "human", "q35", ASSET_PREFIX + ".blend")
GLB_PATH = os.path.join(PROJECT_DIR, "assets", "characters", "human", "q35", ASSET_PREFIX + ".glb")


def load_vrm_addon(addon_dir: str) -> None:
    parent_dir = os.path.dirname(addon_dir)
    if parent_dir not in sys.path:
        sys.path.insert(0, parent_dir)
    if "io_scene_vrm" not in bpy.context.preferences.addons:
        bpy.ops.preferences.addon_enable(module="io_scene_vrm")
    elif not hasattr(bpy.ops.import_scene, "vrm"):
        bpy.ops.preferences.addon_enable(module="io_scene_vrm")


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for datablocks in (bpy.data.objects, bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def imported_objects() -> list[bpy.types.Object]:
    return [obj for obj in bpy.context.scene.objects if obj.type in {"MESH", "ARMATURE", "EMPTY"}]


def bounds(objects: Iterable[bpy.types.Object]) -> tuple[Vector, Vector]:
    points: list[Vector] = []
    for obj in objects:
        if obj.type != "MESH" or obj.hide_render:
            continue
        points.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    if not points:
        raise RuntimeError("standard anime import contained no mesh")
    return (
        Vector((min(point.x for point in points), min(point.y for point in points), min(point.z for point in points))),
        Vector((max(point.x for point in points), max(point.y for point in points), max(point.z for point in points))),
    )


def add_material(name: str, color: tuple[float, float, float], roughness: float = 0.82) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = (*color, 1.0)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    links = material.node_tree.links
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Roughness"].default_value = roughness
    links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    return material


def add_ground() -> None:
    material = add_material("Worldgoing_AnimePreview_Ground", (0.12, 0.16, 0.19), 0.94)
    bpy.ops.mesh.primitive_plane_add(size=20.0, location=(0.0, 0.0, -0.012))
    ground = bpy.context.object
    ground.name = "Worldgoing_AnimePreview_Ground"
    ground.data.materials.append(material)


def add_camera(name: str, location: tuple[float, float, float], target: Vector, ortho_scale: float) -> bpy.types.Object:
    data = bpy.data.cameras.new(name + "_Data")
    data.type = "ORTHO"
    data.ortho_scale = ortho_scale
    camera = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(camera)
    camera.location = location
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    return camera


def add_area_light(name: str, location: tuple[float, float, float], target: Vector, energy: float, size: float) -> None:
    data = bpy.data.lights.new(name + "_Data", "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    light = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(light)
    light.location = location
    light.rotation_euler = (target - light.location).to_track_quat("-Z", "Y").to_euler()


def configure_scene(target: Vector, ortho_scale: float) -> None:
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except (TypeError, ValueError):
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 512
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    if scene.world is None:
        scene.world = bpy.data.worlds.new("Worldgoing_AnimePreview_World")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    if background is not None:
        background.inputs["Color"].default_value = (0.055, 0.085, 0.11, 1.0)
        background.inputs["Strength"].default_value = 0.72
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except (TypeError, ValueError):
        pass
    add_area_light("Worldgoing_AnimePreview_Key", (3.6, -4.0, 4.2), target, 850.0, 3.2)
    add_area_light("Worldgoing_AnimePreview_Fill", (-3.0, -1.6, 2.0), target, 500.0, 3.8)
    add_area_light("Worldgoing_AnimePreview_Rim", (0.0, 3.2, 3.8), target, 950.0, 2.6)
    add_ground()
    scene.camera = add_camera("Worldgoing_AnimePreview_Front", (0.0, -5.0, target.z), target, ortho_scale)


def strip_to_body(objects: list[bpy.types.Object]) -> None:
    body = next((obj for obj in objects if obj.type == "MESH" and obj.name == "Body"), None)
    if body is None:
        raise RuntimeError("standard anime import has no Body mesh")
    face = next((obj for obj in objects if obj.type == "MESH" and obj.name == "Face"), None)
    for obj in objects:
        if obj.type == "MESH" and obj not in {body, face}:
            obj.hide_render = True
            obj.hide_viewport = True
    mesh = body.data
    mesh.update()
    body_bmesh = bmesh.new()
    body_bmesh.from_mesh(mesh)
    clothing_faces = [face for face in body_bmesh.faces if face.material_index > 0]
    if not clothing_faces:
        body_bmesh.free()
        raise RuntimeError("standard anime Body mesh has no clothing faces to strip")
    bmesh.ops.delete(body_bmesh, geom=clothing_faces, context="FACES")
    body_bmesh.to_mesh(mesh)
    body_bmesh.free()
    # Replace the imported material slots explicitly.  Blender can retain the
    # VRM material slots through mesh datablock updates, so assigning every
    # remaining polygon to a new skin-only slot is more reliable than relying
    # on clear() alone.
    skin_material = add_material("Worldgoing_StandardAnime_SkinOnly", (0.62, 0.28, 0.15), 0.86)

    def assign_skin_only(target_mesh: bpy.types.Mesh) -> None:
        while len(target_mesh.materials) > 0:
            target_mesh.materials.pop(index=0)
        target_mesh.materials.append(skin_material)
        for polygon in target_mesh.polygons:
            polygon.material_index = 0

    assign_skin_only(mesh)
    # Keep the imported Face mesh and its facial materials.  A base body still
    # needs a complete head; only hair, clothes, and shoes are stripped here.
    body.data.update()
    body["standard_anime_body_only"] = True
    body["removed_material_faces"] = "clothing_and_shoes"
    body["remaining_polygon_count"] = len(body.data.polygons)
    if len(body.data.polygons) == 0:
        raise RuntimeError("body-only strip removed every Body polygon")


def render_views(target: Vector, ortho_scale: float) -> None:
    scene = bpy.context.scene
    cameras = [
        ("01_front", (0.0, -5.0, target.z)),
        ("02_side", (5.0, 0.0, target.z)),
        ("03_back", (0.0, 5.0, target.z)),
        ("04_three_quarter", (3.55, -3.55, target.z + 0.08)),
    ]
    for filename, location in cameras:
        camera = add_camera("Worldgoing_AnimePreview_" + filename, location, target, ortho_scale)
        scene.camera = camera
        scene.render.filepath = os.path.join(PREVIEW_DIR, filename + ".png")
        bpy.ops.render.render(write_still=True)


def export_glb(objects: list[bpy.types.Object]) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        if obj.type in {"MESH", "ARMATURE"}:
            if BODY_ONLY and obj.type == "MESH" and obj.name not in {"Body", "Face"}:
                continue
            obj.hide_viewport = False
            obj.hide_render = False
            obj.select_set(True)
    selected = [obj for obj in bpy.context.selected_objects if obj.type in {"MESH", "ARMATURE"}]
    if not selected:
        raise RuntimeError("no mesh or armature selected for GLB export")
    bpy.context.view_layer.objects.active = selected[0]
    bpy.ops.export_scene.gltf(
        filepath=GLB_PATH,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_animations=False,
    )
    bpy.ops.object.select_all(action="DESELECT")


def main() -> None:
    if not os.path.exists(MODEL_PATH):
        raise FileNotFoundError(MODEL_PATH)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(BLEND_PATH), exist_ok=True)
    clear_scene()
    load_vrm_addon(ADDON_DIR)
    bpy.ops.import_scene.vrm(filepath=MODEL_PATH, use_addon_preferences=True)
    bpy.context.view_layer.update()
    objects = imported_objects()
    if BODY_ONLY:
        strip_to_body(objects)
    for obj in objects:
        if "collider" in obj.name.lower() or obj.type == "EMPTY":
            obj.hide_render = True
    mesh_objects = [obj for obj in objects if obj.type == "MESH"]
    min_v, max_v = bounds(mesh_objects)
    height = max_v.z - min_v.z
    target = Vector(((min_v.x + max_v.x) * 0.5, 0.0, (min_v.z + max_v.z) * 0.5))
    ortho_scale = max(2.05, height * 1.18)
    configure_scene(target, ortho_scale)
    render_views(target, ortho_scale)
    export_glb(objects)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("WORLDGOING_STANDARD_ANIME_BASE_BUILD_PASS gender=%s" % ANIME_GENDER)
    print("WORLDGOING_STANDARD_ANIME_BASE_BOUNDS gender=%s height=%.4f width=%.4f depth=%.4f" % (ANIME_GENDER, height, max_v.x - min_v.x, max_v.y - min_v.y))
    print("WORLDGOING_STANDARD_ANIME_BASE_GLB gender=%s path=%s" % (ANIME_GENDER, GLB_PATH))
    for filename, _ in (("01_front", None), ("02_side", None), ("03_back", None), ("04_three_quarter", None)):
        print("WORLDGOING_STANDARD_ANIME_BASE_PREVIEW gender=%s path=%s" % (ANIME_GENDER, os.path.join(PREVIEW_DIR, filename + ".png")))


if __name__ == "__main__":
    main()
