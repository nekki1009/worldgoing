"""Build the Worldgoing Male Q35 handoff asset in Blender.

Run this file from Blender 3.6+ (Scripting workspace or --background).
It creates only the dedicated ``Worldgoing_Q35_Male_v1`` collection, an
editable BaseBody + BaseShorts mesh, the 22-bone HumanRig_v1 armature, socket
markers, optional presentation layers, orthographic cameras, and a base GLB.

This is the DCC handoff step. Godot preview captures and production acceptance
remain separate checks after the generated GLB is imported.
"""

import json
import math
import os
from typing import Iterable, List, Sequence, Tuple

import bpy
from mathutils import Matrix, Vector


ASSET_ID = "BaseBodySeries_Male_Q35_v1"
COLLECTION_NAME = "Worldgoing_Q35_Male_v1"
ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUTPUT_DIR = os.path.join(ROOT_DIR, "assets", "characters", "human", "q35")
BLEND_PATH = os.path.join(OUTPUT_DIR, "base_body_series_male_q35.blend")
GLB_PATH = os.path.join(OUTPUT_DIR, "base_body_series_male_q35.glb")
DRESSED_GLB_PATH = os.path.join(OUTPUT_DIR, "base_body_series_male_q35_dressed_preview.glb")
SPEC_PATH = os.path.join(OUTPUT_DIR, "base_body_series_male_q35_spec.json")

HEIGHT_M = 1.78
FORWARD_AXIS = "-Z"

BONE_NAMES = [
    "root", "pelvis", "spine", "chest", "neck", "head",
    "upper_arm_l", "lower_arm_l", "hand_l",
    "upper_arm_r", "lower_arm_r", "hand_r",
    "upper_leg_l", "lower_leg_l", "foot_l",
    "upper_leg_r", "lower_leg_r", "foot_r",
    "weapon_socket_r", "shield_socket_l", "head_socket", "back_socket",
]

PARENT_INDICES = [
    -1, 0, 1, 2, 3, 4,
    3, 6, 7,
    3, 9, 10,
    1, 12, 13,
    1, 15, 16,
    11, 8, 5, 3,
]

# These are local rest positions matching HumanRigV1's existing Godot contract.
LOCAL_BONE_POSITIONS = [
    (0.0, 0.00, 0.00), (0.0, 0.72, 0.00), (0.0, 0.16, 0.00),
    (0.0, 0.15, 0.00), (0.0, 0.12, 0.00), (0.0, 0.37, 0.00),
    (-0.21, 0.00, 0.00), (-0.17, -0.22, 0.00), (-0.08, -0.18, 0.00),
    (0.21, 0.00, 0.00), (0.17, -0.22, 0.00), (0.08, -0.18, 0.00),
    (-0.105, -0.20, 0.00), (0.00, -0.23, 0.00), (0.00, -0.29, 0.00),
    (0.105, -0.20, 0.00), (0.00, -0.23, 0.00), (0.00, -0.29, 0.00),
    (0.07, -0.02, 0.11), (-0.07, -0.02, 0.11), (0.0, 0.0, 0.0),
    (0.0, -0.05, 0.16),
]

SOCKET_BONES = {
    "HEAD_SOCKET": "head",
    "HAND_R_SOCKET": "hand_r",
    "HAND_L_SOCKET": "hand_l",
    "CHEST_SOCKET": "chest",
    "PELVIS_SOCKET": "pelvis",
    "FOOT_SOCKET_L": "foot_l",
    "FOOT_SOCKET_R": "foot_r",
}


class MeshBuilder:
    """Small dependency-free mesh builder for editable Blender mesh data."""

    def __init__(self) -> None:
        self.vertices: List[Tuple[float, float, float]] = []
        self.faces: List[Tuple[int, ...]] = []

    def _add_vertex(self, value: Vector) -> int:
        self.vertices.append((float(value.x), float(value.y), float(value.z)))
        return len(self.vertices) - 1

    def add_revolved(
        self,
        centers: Sequence[Vector],
        radii_x: Sequence[float],
        radii_z: Sequence[float],
        sides: int = 16,
    ) -> None:
        assert len(centers) == len(radii_x) == len(radii_z)
        base = len(self.vertices)
        for center, radius_x, radius_z in zip(centers, radii_x, radii_z):
            for side in range(sides):
                angle = math.tau * side / sides
                self._add_vertex(Vector((
                    center.x + math.cos(angle) * radius_x,
                    center.y,
                    center.z - math.sin(angle) * radius_z,
                )))
        for ring in range(len(centers) - 1):
            for side in range(sides):
                nxt = (side + 1) % sides
                a = base + ring * sides + side
                b = base + ring * sides + nxt
                c = base + (ring + 1) * sides + nxt
                d = base + (ring + 1) * sides + side
                self.faces.extend(((a, c, b), (a, d, c)))
        bottom = self._add_vertex(centers[0])
        top = self._add_vertex(centers[-1])
        top_base = base + (len(centers) - 1) * sides
        for side in range(sides):
            nxt = (side + 1) % sides
            self.faces.append((bottom, base + nxt, base + side))
            self.faces.append((top, top_base + side, top_base + nxt))

    def add_revolved_sector(
        self,
        centers: Sequence[Vector],
        radii_x: Sequence[float],
        radii_z: Sequence[float],
        start_angle: float,
        end_angle: float,
        sides: int = 20,
    ) -> None:
        """Add an open, curved shell sector for tailored front/back panels.

        The old preview used flat back panels, which made the jacket and cape
        read like cardboard from three-quarter and rear views.  A sector keeps
        the replaceable layer boundary while following the torso volume.
        """
        assert len(centers) == len(radii_x) == len(radii_z)
        columns = sides + 1
        base = len(self.vertices)
        for center, radius_x, radius_z in zip(centers, radii_x, radii_z):
            for side in range(columns):
                angle = start_angle + (end_angle - start_angle) * side / sides
                self._add_vertex(Vector((
                    center.x + math.cos(angle) * radius_x,
                    center.y,
                    center.z - math.sin(angle) * radius_z,
                )))
        for ring in range(len(centers) - 1):
            for side in range(sides):
                a = base + ring * columns + side
                b = a + 1
                c = base + (ring + 1) * columns + side + 1
                d = base + (ring + 1) * columns + side
                self.faces.extend(((a, c, b), (a, d, c)))

    def add_tube(
        self,
        points: Sequence[Vector],
        radii: Sequence[float],
        sides: int = 12,
        depth_scale: float = 0.86,
    ) -> None:
        assert len(points) == len(radii) and len(points) >= 2
        base = len(self.vertices)
        for index, point in enumerate(points):
            if index == 0:
                tangent = (points[1] - points[0]).normalized()
            elif index == len(points) - 1:
                tangent = (points[-1] - points[-2]).normalized()
            else:
                tangent = (points[index + 1] - points[index - 1]).normalized()
            reference = Vector((0.0, 0.0, 1.0))
            if abs(tangent.dot(reference)) > 0.92:
                reference = Vector((1.0, 0.0, 0.0))
            ring_x = tangent.cross(reference).normalized()
            ring_z = tangent.cross(ring_x).normalized()
            radius = float(radii[index])
            for side in range(sides):
                angle = math.tau * side / sides
                self._add_vertex(
                    point + ring_x * math.cos(angle) * radius
                    + ring_z * math.sin(angle) * radius * depth_scale
                )
        for ring in range(len(points) - 1):
            for side in range(sides):
                nxt = (side + 1) % sides
                a = base + ring * sides + side
                b = base + ring * sides + nxt
                c = base + (ring + 1) * sides + nxt
                d = base + (ring + 1) * sides + side
                self.faces.extend(((a, c, b), (a, d, c)))
        bottom = self._add_vertex(points[0])
        top = self._add_vertex(points[-1])
        top_base = base + (len(points) - 1) * sides
        for side in range(sides):
            nxt = (side + 1) % sides
            self.faces.append((bottom, base + nxt, base + side))
            self.faces.append((top, top_base + side, top_base + nxt))

    def add_foot(self, center: Vector, width_scale: float = 1.0, depth_scale: float = 1.0) -> None:
        footprint = [
            (-0.120, 0.105), (0.120, 0.105), (0.140, -0.015),
            (0.110, -0.130), (0.055, -0.185), (-0.055, -0.185),
            (-0.110, -0.130), (-0.140, -0.015),
        ]
        base = len(self.vertices)
        for x, z in footprint:
            self._add_vertex(center + Vector((x * width_scale, -0.045, z * depth_scale)))
        for x, z in footprint:
            self._add_vertex(center + Vector((x * width_scale * 0.88, 0.045, z * depth_scale * 0.88)))
        bottom_center = self._add_vertex(center + Vector((0.0, -0.045, -0.015)))
        top_center = self._add_vertex(center + Vector((0.0, 0.045, -0.015)))
        count = len(footprint)
        for side in range(count):
            nxt = (side + 1) % count
            self.faces.extend((
                (base + side, base + count + nxt, base + nxt),
                (base + side, base + count + side, base + count + nxt),
                (bottom_center, base + nxt, base + side),
                (top_center, base + count + side, base + count + nxt),
            ))

    def add_prism_xy(self, points: Sequence[Tuple[float, float]], z_center: float, depth: float) -> None:
        base = len(self.vertices)
        half = depth * 0.5
        for x, y in points:
            self._add_vertex(Vector((x, y, z_center - half)))
        for x, y in points:
            self._add_vertex(Vector((x, y, z_center + half)))
        count = len(points)
        for index in range(1, count - 1):
            self.faces.append((base, base + index + 1, base + index))
            self.faces.append((base + count, base + count + index, base + count + index + 1))
        for index in range(count):
            nxt = (index + 1) % count
            self.faces.extend((
                (base + index, base + nxt, base + count + nxt),
                (base + index, base + count + nxt, base + count + index),
            ))

    def add_prism_yz(self, points: Sequence[Tuple[float, float]], x_center: float, depth: float) -> None:
        """Extrude a side-profile polygon along x for a hanging 3D cloth edge."""
        base = len(self.vertices)
        half = depth * 0.5
        for y, z in points:
            self._add_vertex(Vector((x_center - half, y, z)))
        for y, z in points:
            self._add_vertex(Vector((x_center + half, y, z)))
        count = len(points)
        for index in range(1, count - 1):
            self.faces.append((base, base + index, base + index + 1))
            self.faces.append((base + count, base + count + index + 1, base + count + index))
        for index in range(count):
            nxt = (index + 1) % count
            self.faces.extend((
                (base + index, base + count + index, base + count + nxt),
                (base + index, base + count + nxt, base + nxt),
            ))

    def add_prism_xyz(self, points: Sequence[Tuple[float, float, float]], depth: float) -> None:
        """Extrude a perimeter whose center surface already has z curvature."""
        base = len(self.vertices)
        half = depth * 0.5
        for x, y, z in points:
            self._add_vertex(Vector((x, y, z - half)))
        for x, y, z in points:
            self._add_vertex(Vector((x, y, z + half)))
        count = len(points)
        for index in range(1, count - 1):
            self.faces.append((base, base + index + 1, base + index))
            self.faces.append((base + count, base + count + index, base + count + index + 1))
        for index in range(count):
            nxt = (index + 1) % count
            self.faces.extend((
                (base + index, base + nxt, base + count + nxt),
                (base + index, base + count + nxt, base + count + index),
            ))

    def add_grid_prism(
        self,
        rows: Sequence[Sequence[Tuple[float, float, float]]],
        depth: float,
    ) -> None:
        """Extrude a small curved cloth/panel grid along the z axis.

        A perimeter-only prism keeps its center completely flat.  This grid
        gives the hero preview an actual drape or tailored bulge while still
        remaining a cheap, editable mesh.
        """
        assert len(rows) >= 2 and all(len(row) == len(rows[0]) for row in rows)
        row_count = len(rows)
        column_count = len(rows[0])
        half = depth * 0.5
        base = len(self.vertices)
        for offset in (-half, half):
            for row in rows:
                for x, y, z in row:
                    self._add_vertex(Vector((x, y, z + offset)))

        surface_size = row_count * column_count
        back_base = base
        front_base = base + surface_size
        for row in range(row_count - 1):
            for column in range(column_count - 1):
                a = back_base + row * column_count + column
                b = a + 1
                d = back_base + (row + 1) * column_count + column
                c = d + 1
                self.faces.extend(((a, b, c), (a, c, d)))
                a = front_base + row * column_count + column
                b = a + 1
                d = front_base + (row + 1) * column_count + column
                c = d + 1
                self.faces.extend(((a, c, b), (a, d, c)))

        # Close the four perimeter edges so the panel has a real cloth edge
        # instead of a paper-thin surface at oblique angles.
        perimeter: List[Tuple[int, int]] = []
        for column in range(column_count - 1):
            perimeter.append((column, column + 1))
            perimeter.append(((row_count - 1) * column_count + column,
                              (row_count - 1) * column_count + column + 1))
        for row in range(row_count - 1):
            perimeter.append((row * column_count, (row + 1) * column_count))
            perimeter.append((row * column_count + column_count - 1,
                              (row + 1) * column_count + column_count - 1))
        for first, second in perimeter:
            self.faces.extend((
                (back_base + first, back_base + second, front_base + second),
                (back_base + first, front_base + second, front_base + first),
            ))

    def to_object(self, name: str, collection: bpy.types.Collection, material: bpy.types.Material) -> bpy.types.Object:
        mesh = bpy.data.meshes.new(name + "_Mesh")
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        collection.objects.link(obj)
        obj.data.materials.append(material)
        for polygon in mesh.polygons:
            polygon.use_smooth = True
        return obj


def delete_dedicated_collection(name: str) -> None:
    collection = bpy.data.collections.get(name)
    if collection is None:
        return
    for obj in list(collection.all_objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for child in list(collection.children):
        collection.children.unlink(child)
        bpy.data.collections.remove(child)
    for parent in list(collection.users_scene):
        parent.collection.children.unlink(collection)
    bpy.data.collections.remove(collection)


def hide_factory_startup_objects() -> None:
    for object_name in ("Cube", "Camera", "Light"):
        obj = bpy.data.objects.get(object_name)
        if obj is not None:
            obj.hide_viewport = True
            obj.hide_render = True


def new_collection(name: str, parent: bpy.types.Collection) -> bpy.types.Collection:
    collection = bpy.data.collections.new(name)
    parent.children.link(collection)
    return collection


def move_to_collection(obj: bpy.types.Object, collection: bpy.types.Collection) -> None:
    for old_collection in list(obj.users_collection):
        old_collection.objects.unlink(obj)
    collection.objects.link(obj)


def make_material(name: str, color: Tuple[float, float, float], roughness: float = 0.82) -> bpy.types.Material:
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
        metallic = bsdf.inputs.get("Metallic")
        if metallic is not None and "Gold" in name:
            metallic.default_value = 0.62
        specular = bsdf.inputs.get("Specular IOR Level")
        if specular is not None:
            specular.default_value = 0.34 if ("Skin" in name or "Face" in name) else 0.24
        coat = bsdf.inputs.get("Coat Weight")
        if coat is not None and "Hair" in name:
            coat.default_value = 0.18
        coat_roughness = bsdf.inputs.get("Coat Roughness")
        if coat_roughness is not None and "Hair" in name:
            coat_roughness.default_value = 0.28
        subsurface = bsdf.inputs.get("Subsurface Weight")
        if subsurface is not None and ("Skin" in name or "Face" in name):
            subsurface.default_value = 0.06
    material["worldgoing_asset_id"] = ASSET_ID
    return material


def create_mesh_object(name: str, builder: MeshBuilder, collection: bpy.types.Collection, material: bpy.types.Material) -> bpy.types.Object:
    obj = builder.to_object(name, collection, material)
    obj["worldgoing_asset_id"] = ASSET_ID
    obj["forward_axis"] = FORWARD_AXIS
    return obj


def add_subdivision(obj: bpy.types.Object, levels: int = 1) -> bpy.types.Object:
    modifier = obj.modifiers.new("Q35_Smooth_Surface", "SUBSURF")
    modifier.subdivision_type = "CATMULL_CLARK"
    modifier.levels = levels
    modifier.render_levels = levels + 1
    return obj


def build_base_body(collection: bpy.types.Collection, skin: bpy.types.Material) -> bpy.types.Object:
    builder = MeshBuilder()
    builder.add_revolved(
        [
            Vector((0.0, 0.56, 0.000)), Vector((0.0, 0.64, 0.000)),
            Vector((0.0, 0.76, 0.000)), Vector((0.0, 0.88, -0.008)),
            Vector((0.0, 1.01, -0.025)), Vector((0.0, 1.10, -0.015)),
            Vector((0.0, 1.17, 0.000)),
        ],
        [0.17, 0.215, 0.215, 0.18, 0.215, 0.250, 0.105],
        [0.115, 0.140, 0.140, 0.118, 0.145, 0.155, 0.082],
    )
    builder.add_revolved(
        [Vector((0.0, 1.15, 0.0)), Vector((0.0, 1.22, 0.0)), Vector((0.0, 1.29, 0.0))],
        [0.105, 0.090, 0.095], [0.085, 0.078, 0.085], 14,
    )
    builder.add_revolved(
        [
            Vector((0.0, 1.29, 0.005)), Vector((0.0, 1.34, 0.000)),
            Vector((0.0, 1.45, -0.008)), Vector((0.0, 1.57, -0.005)),
            Vector((0.0, 1.68, 0.008)), Vector((0.0, 1.78, 0.018)),
        ],
        [0.08, 0.135, 0.185, 0.205, 0.175, 0.105],
        [0.074, 0.115, 0.145, 0.165, 0.140, 0.095],
        18,
    )
    builder.add_tube(
        [Vector((-0.215, 1.09, 0.0)), Vector((-0.25, 0.98, -0.005)),
         Vector((-0.265, 0.84, -0.012)), Vector((-0.268, 0.715, -0.025)),
         Vector((-0.268, 0.665, -0.040))],
        [0.073, 0.067, 0.059, 0.050, 0.056],
    )
    builder.add_tube(
        [Vector((0.215, 1.09, 0.0)), Vector((0.25, 0.98, -0.005)),
         Vector((0.265, 0.84, -0.012)), Vector((0.268, 0.715, -0.025)),
         Vector((0.268, 0.665, -0.040))],
        [0.073, 0.067, 0.059, 0.050, 0.056],
    )
    builder.add_tube(
        [Vector((-0.10, 0.68, 0.0)), Vector((-0.112, 0.53, 0.0)),
         Vector((-0.108, 0.36, -0.005)), Vector((-0.095, 0.17, -0.005)),
         Vector((-0.095, 0.065, -0.005))],
        [0.105, 0.100, 0.082, 0.060, 0.050],
    )
    builder.add_tube(
        [Vector((0.10, 0.68, 0.0)), Vector((0.112, 0.53, 0.0)),
         Vector((0.108, 0.36, -0.005)), Vector((0.095, 0.17, -0.005)),
         Vector((0.095, 0.065, -0.005))],
        [0.105, 0.100, 0.082, 0.060, 0.050],
    )
    builder.add_foot(Vector((-0.095, 0.045, -0.040)), 0.55, 0.65)
    builder.add_foot(Vector((0.095, 0.045, -0.040)), 0.55, 0.65)
    return add_subdivision(create_mesh_object("BaseBody_Male_Q35", builder, collection, skin))


def build_base_shorts(collection: bpy.types.Collection, material: bpy.types.Material) -> bpy.types.Object:
    builder = MeshBuilder()
    for side in (-1.0, 1.0):
        builder.add_revolved(
            [Vector((side * 0.115, 0.55, 0.0)), Vector((side * 0.120, 0.63, -0.005)), Vector((side * 0.120, 0.76, 0.0))],
            [0.105, 0.125, 0.115], [0.125, 0.145, 0.135], 14,
        )
    return add_subdivision(create_mesh_object("BaseShorts_Male_Q35", builder, collection, material))


def add_uv_sphere(
    name: str,
    location: Tuple[float, float, float],
    scale: Tuple[float, float, float],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    segments: int = 24,
    ring_count: int = 16,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=ring_count, radius=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    obj.data.materials.append(material)
    move_to_collection(obj, collection)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    obj["worldgoing_asset_id"] = ASSET_ID
    return obj


def add_beveled_cube(
    name: str,
    location: Tuple[float, float, float],
    dimensions: Tuple[float, float, float],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    bevel_factor: float = 0.18,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.context.view_layer.update()
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.select_set(False)
    bevel = obj.modifiers.new("Q35_Rounded_Edge", "BEVEL")
    bevel.width = min(dimensions) * bevel_factor
    bevel.segments = 3
    obj.data.materials.append(material)
    move_to_collection(obj, collection)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    obj["worldgoing_asset_id"] = ASSET_ID
    return obj


def build_presentation_layers(
    hair_collection: bpy.types.Collection,
    face_collection: bpy.types.Collection,
    clothing_collection: bpy.types.Collection,
    materials: dict,
) -> List[Tuple[bpy.types.Object, str]]:
    """Build the dressed Q35 preview while keeping each appearance layer replaceable."""
    appearance: List[Tuple[bpy.types.Object, str]] = []

    def register(obj: bpy.types.Object, bone_name: str = "") -> bpy.types.Object:
        appearance.append((obj, bone_name))
        return obj

    def panel(
        name: str,
        points: Sequence[Tuple[float, float]],
        z_center: float,
        depth: float,
        material: bpy.types.Material,
        collection: bpy.types.Collection,
        bone_name: str = "",
    ) -> bpy.types.Object:
        builder = MeshBuilder()
        builder.add_prism_xy(points, z_center, depth)
        obj = create_mesh_object(name, builder, collection, material)
        bevel = obj.modifiers.new("Q35_Panel_Edge", "BEVEL")
        bevel.width = min(depth * 0.42, 0.022)
        bevel.segments = 4
        return register(obj, bone_name)

    def cloth_panel(
        name: str,
        points: Sequence[Tuple[float, float, float]],
        depth: float,
        material: bpy.types.Material,
        collection: bpy.types.Collection,
        bone_name: str = "",
    ) -> bpy.types.Object:
        builder = MeshBuilder()
        builder.add_prism_xyz(points, depth)
        obj = create_mesh_object(name, builder, collection, material)
        bevel = obj.modifiers.new("Q35_HeroClothEdge", "BEVEL")
        bevel.width = min(depth * 0.42, 0.018)
        bevel.segments = 4
        return register(obj, bone_name)

    def grid_panel(
        name: str,
        rows: Sequence[Sequence[Tuple[float, float, float]]],
        depth: float,
        material: bpy.types.Material,
        collection: bpy.types.Collection,
        bone_name: str = "",
        bevel_width: float = 0.012,
    ) -> bpy.types.Object:
        builder = MeshBuilder()
        builder.add_grid_prism(rows, depth)
        obj = create_mesh_object(name, builder, collection, material)
        bevel = obj.modifiers.new("Q35_CurvedPanelEdge", "BEVEL")
        bevel.width = bevel_width
        bevel.segments = 3
        return register(obj, bone_name)

    def strand(
        name: str,
        points: Sequence[Tuple[float, float, float]],
        radii: Sequence[float],
        material: bpy.types.Material,
    ) -> bpy.types.Object:
        builder = MeshBuilder()
        builder.add_tube([Vector(point) for point in points], radii, 12, 0.34)
        return register(add_subdivision(create_mesh_object(name, builder, hair_collection, material)), "head")

    def face_line(
        name: str,
        points: Sequence[Tuple[float, float, float]],
        radius: float,
        material: bpy.types.Material,
    ) -> bpy.types.Object:
        builder = MeshBuilder()
        builder.add_tube([Vector(point) for point in points], [radius] * len(points), 10, 0.34)
        return register(add_subdivision(create_mesh_object(name, builder, face_collection, material)), "head")

    # Refined jacket silhouette: ivory torso, navy center panel, diagonal sash and belt.
    jacket_builder = MeshBuilder()
    jacket_builder.add_revolved(
        [Vector((0.0, 0.76, 0.0)), Vector((0.0, 0.86, 0.0)), Vector((0.0, 1.03, -0.005)), Vector((0.0, 1.18, 0.0))],
        [0.175, 0.215, 0.225, 0.17], [0.125, 0.155, 0.165, 0.12], 24,
    )
    register(add_subdivision(create_mesh_object("JacketBody_Male_Q35", jacket_builder, clothing_collection, materials["ivory"])))
    back_jacket_builder = MeshBuilder()
    back_jacket_builder.add_revolved_sector(
        [Vector((0.0, 0.76, 0.008)), Vector((0.0, 0.88, 0.008)), Vector((0.0, 1.04, 0.006)), Vector((0.0, 1.18, 0.008))],
        [0.175, 0.215, 0.225, 0.17], [0.132, 0.162, 0.172, 0.127], math.pi, math.tau, 24,
    )
    register(add_subdivision(create_mesh_object("JacketBackShell_Male_Q35", back_jacket_builder, clothing_collection, materials["navy"])), "chest")
    for side, start_angle, end_angle in ((-1.0, math.pi * 0.5, math.pi), (1.0, 0.0, math.pi * 0.5)):
        front_builder = MeshBuilder()
        front_builder.add_revolved_sector(
            [Vector((0.0, 0.78, -0.004)), Vector((0.0, 0.90, -0.004)), Vector((0.0, 1.05, -0.004)), Vector((0.0, 1.18, -0.004))],
            [0.178, 0.218, 0.228, 0.174], [0.132, 0.162, 0.172, 0.127], start_angle, end_angle, 14,
        )
        panel_name = "JacketFrontShellL_Male_Q35" if side < 0 else "JacketFrontShellR_Male_Q35"
        register(add_subdivision(create_mesh_object(panel_name, front_builder, clothing_collection, materials["ivory"])), "chest")
    panel("JacketSideL_Male_Q35", [(-0.185, 1.14), (-0.105, 1.18), (-0.085, 0.82), (-0.155, 0.80)], -0.145, 0.035, materials["ivory"], clothing_collection)
    panel("JacketSideR_Male_Q35", [(0.105, 1.18), (0.185, 1.14), (0.155, 0.80), (0.085, 0.82)], -0.145, 0.035, materials["ivory"], clothing_collection)
    panel("JacketCenter_Male_Q35", [(-0.065, 1.19), (0.065, 1.19), (0.055, 0.82), (-0.055, 0.82)], -0.185, 0.035, materials["navy"], clothing_collection)
    panel("JacketInner_Male_Q35", [(-0.060, 1.245), (0.060, 1.245), (0.050, 1.105), (-0.050, 1.105)], -0.215, 0.025, materials["black"], clothing_collection)
    panel("JacketNeckBib_Male_Q35", [(-0.073, 1.17), (0.073, 1.17), (0.050, 1.29), (-0.050, 1.29)], -0.225, 0.030, materials["ivory"], clothing_collection)
    panel("JacketNeckInset_Male_Q35", [(-0.041, 1.20), (0.041, 1.20), (0.034, 1.315), (-0.034, 1.315)], -0.245, 0.018, materials["black"], clothing_collection)
    panel("BackNeckGuard_Male_Q35", [(-0.058, 1.31), (0.058, 1.31), (0.052, 1.37), (-0.052, 1.37)], 0.18, 0.020, materials["navy"], clothing_collection)
    panel("JacketNeckTrimL_Male_Q35", [(-0.066, 1.30), (-0.057, 1.30), (-0.088, 1.175), (-0.098, 1.175)], -0.255, 0.010, materials["gold"], clothing_collection)
    panel("JacketNeckTrimR_Male_Q35", [(0.057, 1.30), (0.066, 1.30), (0.098, 1.175), (0.088, 1.175)], -0.255, 0.010, materials["gold"], clothing_collection)
    panel("JacketLapelL_Male_Q35", [(-0.14, 1.20), (-0.082, 1.22), (-0.022, 0.94), (-0.075, 0.88)], -0.235, 0.025, materials["ivory"], clothing_collection)
    panel("JacketLapelR_Male_Q35", [(0.082, 1.22), (0.14, 1.20), (0.075, 0.88), (0.022, 0.94)], -0.235, 0.025, materials["ivory"], clothing_collection)
    panel("JacketLapelTrimL_Male_Q35", [(-0.142, 1.20), (-0.129, 1.205), (-0.067, 0.885), (-0.080, 0.88)], -0.255, 0.014, materials["gold"], clothing_collection)
    panel("JacketLapelTrimR_Male_Q35", [(0.129, 1.205), (0.142, 1.20), (0.080, 0.88), (0.067, 0.885)], -0.255, 0.014, materials["gold"], clothing_collection)
    collar_builder = MeshBuilder()
    collar_builder.add_revolved([Vector((0.0, 1.27, 0.0)), Vector((0.0, 1.33, 0.0))], [0.10, 0.105], [0.08, 0.085], 18)
    register(add_subdivision(create_mesh_object("HighCollar_Male_Q35", collar_builder, clothing_collection, materials["black"])), "neck")
    panel("JacketSash_Male_Q35", [(-0.185, 1.17), (-0.125, 1.22), (0.185, 0.86), (0.125, 0.82)], -0.215, 0.035, materials["navy_light"], clothing_collection)
    panel("JacketSashTrim_Male_Q35", [(-0.17, 1.17), (-0.158, 1.18), (0.17, 0.86), (0.158, 0.85)], -0.24, 0.012, materials["gold"], clothing_collection)
    panel("WaistBelt_Male_Q35", [(-0.19, 0.82), (0.19, 0.82), (0.178, 0.75), (-0.178, 0.75)], -0.19, 0.038, materials["black"], clothing_collection)
    panel("WaistBeltAccent_Male_Q35", [(-0.040, 0.825), (0.040, 0.825), (0.046, 0.742), (-0.046, 0.742)], -0.225, 0.025, materials["gold"], clothing_collection)
    panel("JacketTailL_Male_Q35", [(-0.20, 0.78), (-0.03, 0.78), (-0.045, 0.48), (-0.17, 0.55)], -0.14, 0.04, materials["navy_light"], clothing_collection)
    panel("JacketTailR_Male_Q35", [(0.03, 0.78), (0.20, 0.78), (0.17, 0.55), (0.045, 0.48)], -0.14, 0.04, materials["navy_light"], clothing_collection)
    panel("ShoulderCapeL_Male_Q35", [(-0.12, 1.24), (-0.22, 1.21), (-0.30, 1.08), (-0.22, 1.02), (-0.14, 1.13)], -0.055, 0.035, materials["navy"], clothing_collection)
    panel("ShoulderCapeR_Male_Q35", [(0.22, 1.21), (0.12, 1.24), (0.14, 1.13), (0.22, 1.02), (0.30, 1.08)], -0.055, 0.035, materials["navy"], clothing_collection)
    panel("ShoulderCapeTrimL_Male_Q35", [(-0.215, 1.215), (-0.225, 1.205), (-0.295, 1.08), (-0.282, 1.075)], -0.082, 0.012, materials["gold"], clothing_collection)
    panel("ShoulderCapeTrimR_Male_Q35", [(0.225, 1.205), (0.215, 1.215), (0.282, 1.075), (0.295, 1.08)], -0.082, 0.012, materials["gold"], clothing_collection)
    panel("JacketSeamL_Male_Q35", [(-0.108, 1.17), (-0.098, 1.17), (-0.090, 0.86), (-0.102, 0.86)], -0.258, 0.012, materials["gold"], clothing_collection)
    panel("JacketSeamR_Male_Q35", [(0.098, 1.17), (0.108, 1.17), (0.102, 0.86), (0.090, 0.86)], -0.258, 0.012, materials["gold"], clothing_collection)
    panel("WaistBeltUpper_Male_Q35", [(-0.188, 0.82), (0.188, 0.82), (0.180, 0.79), (-0.180, 0.79)], -0.235, 0.020, materials["navy"], clothing_collection)
    panel("WaistBeltLower_Male_Q35", [(-0.180, 0.775), (0.180, 0.775), (0.172, 0.745), (-0.172, 0.745)], -0.235, 0.020, materials["black"], clothing_collection)

    # Slim trousers and tall boots replace the old exposed base legs in the preview.
    for side in (-1.0, 1.0):
        side_name = "L" if side < 0 else "R"
        pants_builder = MeshBuilder()
        pants_builder.add_tube(
            [Vector((side * 0.108, 0.73, 0.0)), Vector((side * 0.118, 0.58, 0.0)), Vector((side * 0.103, 0.42, 0.0)), Vector((side * 0.090, 0.34, 0.0))],
            [0.104, 0.092, 0.075, 0.062], 18,
        )
        register(add_subdivision(create_mesh_object("Trousers%s_Male_Q35" % side_name, pants_builder, clothing_collection, materials["black"])), "upper_leg_l" if side < 0 else "upper_leg_r")
        panel("TrouserStripe%s_Male_Q35" % side_name, [(side * 0.145, 0.72), (side * 0.125, 0.72), (side * 0.108, 0.45), (side * 0.124, 0.45)], -0.075, 0.018, materials["navy_light"], clothing_collection, "upper_leg_l" if side < 0 else "upper_leg_r")
        panel("TrouserStripeTrim%s_Male_Q35" % side_name, [(side * 0.143, 0.70), (side * 0.137, 0.70), (side * 0.116, 0.47), (side * 0.121, 0.47)], -0.092, 0.010, materials["gold"], clothing_collection, "upper_leg_l" if side < 0 else "upper_leg_r")

        boot_builder = MeshBuilder()
        boot_builder.add_tube(
            [Vector((side * 0.090, 0.35, 0.0)), Vector((side * 0.090, 0.20, 0.0)), Vector((side * 0.090, 0.08, -0.005))],
            [0.071, 0.066, 0.060], 16,
        )
        register(add_subdivision(create_mesh_object("Boot%s_Male_Q35" % side_name, boot_builder, clothing_collection, materials["boot"])), "foot_l" if side < 0 else "foot_r")
        shoe_builder = MeshBuilder()
        shoe_builder.add_foot(Vector((side * 0.090, 0.050, -0.070)), 0.60, 0.82)
        shoe = add_subdivision(create_mesh_object("Shoe%s_Male_Q35" % side_name, shoe_builder, clothing_collection, materials["boot"]))
        register(shoe, "foot_l" if side < 0 else "foot_r")
        sole_builder = MeshBuilder()
        sole_builder.add_foot(Vector((side * 0.090, 0.012, -0.070)), 0.64, 0.86)
        sole = create_mesh_object("ShoeSole%s_Male_Q35" % side_name, sole_builder, clothing_collection, materials["black"])
        register(sole, "foot_l" if side < 0 else "foot_r")
        toe_cap = add_uv_sphere("ToeCap%s_Male_Q35" % side_name, (side * 0.090, 0.085, -0.215), (0.032, 0.012, 0.018), materials["gold"], clothing_collection, 16, 10)
        register(toe_cap, "foot_l" if side < 0 else "foot_r")
        panel("BootBand%s_Male_Q35" % side_name, [(side * 0.090, 0.375), (side * 0.145, 0.33), (side * 0.090, 0.285), (side * 0.035, 0.33)], -0.070, 0.025, materials["gold"], clothing_collection, "foot_l" if side < 0 else "foot_r")
        panel("BootAnkleBand%s_Male_Q35" % side_name, [(side * 0.090, 0.165), (side * 0.150, 0.135), (side * 0.090, 0.105), (side * 0.030, 0.135)], -0.070, 0.022, materials["gold"], clothing_collection, "foot_l" if side < 0 else "foot_r")
        panel("BootToeBand%s_Male_Q35" % side_name, [(side * 0.135, 0.095), (side * 0.120, 0.070), (side * 0.030, 0.070), (side * 0.030, 0.095)], -0.218, 0.014, materials["gold"], clothing_collection, "foot_l" if side < 0 else "foot_r")

    # Long tapered sleeves, dark cuffs and simple shoulder ornaments.
    for side in (-1.0, 1.0):
        side_name = "L" if side < 0 else "R"
        sleeve_builder = MeshBuilder()
        sleeve_builder.add_tube(
            [Vector((side * 0.245, 1.12, 0.0)), Vector((side * 0.290, 1.00, 0.0)), Vector((side * 0.315, 0.83, -0.005)), Vector((side * 0.310, 0.73, -0.02))],
            [0.072, 0.064, 0.054, 0.044], 18,
        )
        register(add_subdivision(create_mesh_object("Sleeve%s_Male_Q35" % side_name, sleeve_builder, clothing_collection, materials["ivory"])), "upper_arm_l" if side < 0 else "upper_arm_r")
        cuff_builder = MeshBuilder()
        cuff_builder.add_tube([Vector((side * 0.310, 0.78, -0.02)), Vector((side * 0.310, 0.68, -0.025))], [0.055, 0.05], 16)
        register(add_subdivision(create_mesh_object("Cuff%s_Male_Q35" % side_name, cuff_builder, clothing_collection, materials["black"])), "lower_arm_l" if side < 0 else "lower_arm_r")
        cuff_trim_builder = MeshBuilder()
        cuff_trim_builder.add_tube([Vector((side * 0.310, 0.755, -0.022)), Vector((side * 0.310, 0.725, -0.023))], [0.058, 0.054], 16)
        register(add_subdivision(create_mesh_object("CuffTrim%s_Male_Q35" % side_name, cuff_trim_builder, clothing_collection, materials["gold"])), "lower_arm_l" if side < 0 else "lower_arm_r")
        panel("CuffPlate%s_Male_Q35" % side_name, [(side * 0.300, 0.77), (side * 0.245, 0.75), (side * 0.245, 0.69), (side * 0.285, 0.67)], -0.085, 0.022, materials["navy"], clothing_collection, "lower_arm_l" if side < 0 else "lower_arm_r")
        panel("CuffPlateTrim%s_Male_Q35" % side_name, [(side * 0.297, 0.765), (side * 0.288, 0.76), (side * 0.252, 0.685), (side * 0.260, 0.69)], -0.100, 0.010, materials["gold"], clothing_collection, "lower_arm_l" if side < 0 else "lower_arm_r")
        shoulder = add_uv_sphere("Shoulder%s_Male_Q35" % side_name, (side * 0.245, 1.12, 0.015), (0.075, 0.050, 0.065), materials["navy"], clothing_collection)
        register(shoulder, "upper_arm_l" if side < 0 else "upper_arm_r")
        hand = add_uv_sphere("Hand%s_Male_Q35" % side_name, (side * 0.300, 0.655, -0.035), (0.046, 0.060, 0.043), materials["skin_light"], clothing_collection)
        register(hand, "hand_l" if side < 0 else "hand_r")
        thumb = add_uv_sphere("Thumb%s_Male_Q35" % side_name, (side * 0.338, 0.655, -0.040), (0.016, 0.028, 0.015), materials["skin_light"], clothing_collection, 16, 10)
        thumb.rotation_euler[2] = side * 0.45
        register(thumb, "hand_l" if side < 0 else "hand_r")
        for finger_index, finger_x in enumerate((-0.020, 0.0, 0.020)):
            finger = add_uv_sphere(
                "Finger%s_%d_Male_Q35" % (side_name, finger_index),
                (side * 0.300 + finger_x, 0.615 - abs(finger_x) * 0.25, -0.045),
                (0.011, 0.028, 0.012),
                materials["skin_light"],
                clothing_collection,
                16,
                10,
            )
            finger.rotation_euler[2] = side * 0.18
            register(finger, "hand_l" if side < 0 else "hand_r")

    # Asymmetric cape with a warm inner panel, placed behind the body on the
    # viewer's right to match the concept sheet.
    panel("CapeOuter_Male_Q35", [(-0.16, 1.16), (-0.37, 1.10), (-0.55, 0.93), (-0.59, 0.75), (-0.57, 0.54), (-0.52, 0.32), (-0.43, 0.13), (-0.30, 0.05), (-0.23, 0.28), (-0.23, 0.52)], -0.015, 0.08, materials["navy"], clothing_collection)
    panel("CapeInner_Male_Q35", [(-0.23, 1.08), (-0.35, 1.02), (-0.48, 0.84), (-0.50, 0.66), (-0.46, 0.42), (-0.42, 0.25), (-0.36, 0.16), (-0.28, 0.30), (-0.28, 0.50)], -0.045, 0.025, materials["cape_inner"], clothing_collection)
    panel("CapeTrim_Male_Q35", [(-0.48, 0.86), (-0.53, 0.78), (-0.50, 0.58), (-0.48, 0.36), (-0.43, 0.20), (-0.41, 0.22)], -0.075, 0.025, materials["gold"], clothing_collection)
    # A full rear drape is separate from the asymmetric front-facing cape.
    # It sits outside the jacket volume so the back view matches the reference
    # instead of exposing a blank ivory torso.
    panel("CapeBackDrape_Male_Q35", [(-0.25, 1.18), (0.23, 1.18), (0.34, 1.03), (0.35, 0.82), (0.30, 0.59), (0.22, 0.35), (0.08, 0.22), (-0.08, 0.28), (-0.21, 0.52), (-0.29, 0.86)], 0.185, 0.060, materials["navy"], clothing_collection)
    panel("CapeBackInner_Male_Q35", [(-0.16, 1.10), (0.17, 1.10), (0.25, 0.98), (0.26, 0.80), (0.21, 0.60), (0.14, 0.42), (0.06, 0.32), (-0.07, 0.37), (-0.16, 0.58), (-0.22, 0.86)], 0.222, 0.018, materials["navy_light"], clothing_collection)
    panel("CapeBackTrim_Male_Q35", [(-0.25, 1.18), (-0.23, 1.15), (-0.27, 0.87), (-0.25, 0.60), (-0.18, 0.40), (-0.08, 0.27), (-0.05, 0.28), (-0.15, 0.48), (-0.22, 0.72), (-0.21, 0.98)], 0.238, 0.018, materials["gold"], clothing_collection)
    panel("CapeBackYoke_Male_Q35", [(-0.18, 1.23), (0.18, 1.23), (0.20, 1.08), (-0.20, 1.08)], 0.222, 0.035, materials["navy"], clothing_collection)
    panel("CapeBackSpine_Male_Q35", [(-0.012, 1.10), (0.012, 1.10), (0.016, 0.74), (-0.016, 0.74)], 0.244, 0.016, materials["gold"], clothing_collection)
    panel("CapeBackStar_Male_Q35", [(0.0, 1.28), (0.018, 1.20), (0.085, 1.20), (0.030, 1.16), (0.050, 1.09), (0.0, 1.13), (-0.050, 1.09), (-0.030, 1.16), (-0.085, 1.20), (-0.018, 1.20)], 0.255, 0.018, materials["gold"], clothing_collection)

    # A tapered egg-shaped head gives the face a soft anime jaw instead of a round ball.
    head_builder = MeshBuilder()
    head_builder.add_revolved(
        [
            Vector((0.0, 1.35, 0.0)), Vector((0.0, 1.40, 0.0)),
            Vector((0.0, 1.49, -0.005)), Vector((0.0, 1.60, -0.002)),
            Vector((0.0, 1.70, 0.008)), Vector((0.0, 1.77, 0.018)),
        ],
        [0.072, 0.128, 0.175, 0.184, 0.158, 0.070],
        [0.060, 0.102, 0.142, 0.152, 0.126, 0.056],
        28,
    )
    head_skin = add_subdivision(create_mesh_object("HeadSkin_Male_Q35", head_builder, face_collection, materials["skin"]))
    register(head_skin, "head")
    neck_skin = add_uv_sphere("NeckSkin_Male_Q35", (0.0, 1.385, 0.0), (0.070, 0.105, 0.060), materials["skin"], face_collection)
    register(neck_skin, "neck")
    for side in (-1.0, 1.0):
        ear_name = "EarL_Male_Q35" if side < 0 else "EarR_Male_Q35"
        ear = add_uv_sphere(ear_name, (side * 0.155, 1.535, -0.005), (0.032, 0.052, 0.024), materials["skin_light"], face_collection)
        register(ear, "head")

    # Hair cap, side locks and separated front bangs.
    hair_cap = add_uv_sphere("HairCap_Male_Q35", (0.0, 1.67, 0.005), (0.225, 0.175, 0.16), materials["hair"], hair_collection)
    register(hair_cap, "head")
    for side in (-1.0, 1.0):
        side_name = "L" if side < 0 else "R"
        side_lock = add_uv_sphere("HairLock%s_Male_Q35" % side_name, (side * 0.205, 1.60, 0.012), (0.034, 0.086, 0.045), materials["hair"], hair_collection)
        register(side_lock, "head")
    strand("HairLockFrontL_Male_Q35", [(-0.015, 1.77, -0.145), (-0.07, 1.71, -0.205), (-0.12, 1.62, -0.215), (-0.14, 1.54, -0.19)], [0.043, 0.050, 0.034, 0.010], materials["hair"])
    strand("HairLockFrontR_Male_Q35", [(0.015, 1.77, -0.145), (0.07, 1.71, -0.205), (0.12, 1.62, -0.215), (0.14, 1.54, -0.19)], [0.043, 0.050, 0.034, 0.010], materials["hair"])
    strand("HairLockSweepL_Male_Q35", [(-0.10, 1.78, -0.115), (-0.16, 1.72, -0.17), (-0.20, 1.64, -0.16), (-0.21, 1.56, -0.10)], [0.034, 0.040, 0.030, 0.009], materials["hair_highlight"])
    strand("HairLockSweepR_Male_Q35", [(0.10, 1.78, -0.115), (0.16, 1.72, -0.17), (0.20, 1.64, -0.16), (0.21, 1.56, -0.10)], [0.034, 0.040, 0.030, 0.009], materials["hair"])
    strand("HairLayerOuterL_Male_Q35", [(-0.13, 1.76, -0.075), (-0.20, 1.70, -0.11), (-0.235, 1.61, -0.09), (-0.22, 1.53, -0.045)], [0.028, 0.038, 0.027, 0.008], materials["hair"])
    strand("HairLayerOuterR_Male_Q35", [(0.13, 1.76, -0.075), (0.20, 1.70, -0.11), (0.235, 1.61, -0.09), (0.22, 1.53, -0.045)], [0.028, 0.038, 0.027, 0.008], materials["hair"])
    strand("HairLayerCrownL_Male_Q35", [(-0.025, 1.82, -0.075), (-0.10, 1.80, -0.13), (-0.16, 1.75, -0.12)], [0.025, 0.038, 0.012], materials["hair_highlight"])
    strand("HairLayerCrownR_Male_Q35", [(0.025, 1.82, -0.075), (0.10, 1.80, -0.13), (0.16, 1.75, -0.12)], [0.025, 0.038, 0.012], materials["hair"])
    strand("HairLayerNapeL_Male_Q35", [(-0.13, 1.67, 0.06), (-0.18, 1.61, 0.08), (-0.16, 1.53, 0.06)], [0.030, 0.034, 0.010], materials["hair"])
    strand("HairLayerNapeR_Male_Q35", [(0.13, 1.67, 0.06), (0.18, 1.61, 0.08), (0.16, 1.53, 0.06)], [0.030, 0.034, 0.010], materials["hair"])
    strand("HairLayerFlareL_Male_Q35", [(-0.18, 1.66, -0.04), (-0.235, 1.61, -0.07), (-0.265, 1.56, -0.035)], [0.024, 0.032, 0.008], materials["hair_highlight"])
    strand("HairLayerFlareR_Male_Q35", [(0.18, 1.66, -0.04), (0.235, 1.61, -0.07), (0.265, 1.56, -0.035)], [0.024, 0.032, 0.008], materials["hair"])
    strand("HairLayerTempleL_Male_Q35", [(-0.13, 1.69, -0.17), (-0.17, 1.64, -0.18), (-0.19, 1.59, -0.14)], [0.018, 0.028, 0.007], materials["hair"])
    strand("HairLayerTempleR_Male_Q35", [(0.13, 1.69, -0.17), (0.17, 1.64, -0.18), (0.19, 1.59, -0.14)], [0.018, 0.028, 0.007], materials["hair_highlight"])
    strand("HairCowlick_Male_Q35", [(0.0, 1.78, -0.02), (-0.01, 1.84, -0.07), (0.025, 1.89, -0.06), (0.065, 1.90, -0.025)], [0.025, 0.021, 0.013, 0.004], materials["hair_highlight"])
    # Layered rear locks keep the turnaround readable from behind; the cap
    # alone made the previous back view look bald and toy-like.
    strand("HairBackCenter_Male_Q35", [(0.0, 1.79, 0.125), (0.0, 1.71, 0.16), (0.0, 1.61, 0.17), (0.0, 1.49, 0.115)], [0.038, 0.046, 0.034, 0.010], materials["hair"])
    strand("HairBackL_Male_Q35", [(-0.055, 1.78, 0.11), (-0.12, 1.72, 0.145), (-0.18, 1.64, 0.15), (-0.20, 1.54, 0.095)], [0.034, 0.043, 0.031, 0.009], materials["hair_highlight"])
    strand("HairBackR_Male_Q35", [(0.055, 1.78, 0.11), (0.12, 1.72, 0.145), (0.18, 1.64, 0.15), (0.20, 1.54, 0.095)], [0.034, 0.043, 0.031, 0.009], materials["hair"])
    strand("HairBackOuterL_Male_Q35", [(-0.14, 1.72, 0.075), (-0.21, 1.65, 0.10), (-0.245, 1.57, 0.085), (-0.235, 1.50, 0.050)], [0.027, 0.036, 0.024, 0.007], materials["hair"])
    strand("HairBackOuterR_Male_Q35", [(0.14, 1.72, 0.075), (0.21, 1.65, 0.10), (0.245, 1.57, 0.085), (0.235, 1.50, 0.050)], [0.027, 0.036, 0.024, 0.007], materials["hair_highlight"])

    # Large readable anime eyes, brows, nose and mouth.
    face_line("BrowL_Male_Q35", [(-0.125, 1.655, -0.207), (-0.095, 1.669, -0.210), (-0.055, 1.661, -0.207)], 0.006, materials["face"])
    face_line("BrowR_Male_Q35", [(0.055, 1.661, -0.207), (0.095, 1.669, -0.210), (0.125, 1.655, -0.207)], 0.006, materials["face"])
    face_line("Smile_Male_Q35", [(-0.028, 1.452, -0.205), (-0.010, 1.444, -0.211), (0.010, 1.444, -0.211), (0.028, 1.452, -0.205)], 0.004, materials["face"])
    brooch = add_uv_sphere("ChestBrooch_Male_Q35", (0.16, 1.13, -0.23), (0.020, 0.026, 0.012), materials["gold"], clothing_collection)
    register(brooch, "chest")
    panel(
        "ShoulderRosette_Male_Q35",
        [(-0.18, 1.205), (-0.14, 1.16), (-0.18, 1.115), (-0.22, 1.16)],
        -0.265,
        0.018,
        materials["gold"],
        clothing_collection,
        "chest",
    )
    panel(
        "ShoulderRosetteR_Male_Q35",
        [(0.18, 1.215), (0.215, 1.175), (0.25, 1.17), (0.215, 1.14), (0.23, 1.095), (0.18, 1.115), (0.13, 1.095), (0.145, 1.14), (0.11, 1.17), (0.145, 1.175)],
        -0.265,
        0.018,
        materials["gold"],
        clothing_collection,
        "chest",
    )
    panel("ShoulderEpauletL_Male_Q35", [(-0.20, 1.17), (-0.125, 1.205), (-0.105, 1.14), (-0.175, 1.10)], -0.18, 0.035, materials["navy"], clothing_collection, "chest")
    panel("ShoulderEpauletR_Male_Q35", [(0.125, 1.205), (0.20, 1.17), (0.175, 1.10), (0.105, 1.14)], -0.18, 0.035, materials["navy"], clothing_collection, "chest")
    panel("ShoulderEpauletTrimL_Male_Q35", [(-0.205, 1.17), (-0.195, 1.166), (-0.17, 1.11), (-0.18, 1.108)], -0.205, 0.012, materials["gold"], clothing_collection, "chest")
    panel("ShoulderEpauletTrimR_Male_Q35", [(0.195, 1.166), (0.205, 1.17), (0.18, 1.108), (0.17, 1.11)], -0.205, 0.012, materials["gold"], clothing_collection, "chest")
    gem = add_uv_sphere("ShoulderGem_Male_Q35", (-0.175, 1.14, -0.278), (0.015, 0.019, 0.006), materials["navy_light"], clothing_collection)
    register(gem, "chest")
    gem_r = add_uv_sphere("ShoulderGemR_Male_Q35", (0.175, 1.14, -0.278), (0.015, 0.019, 0.006), materials["navy_light"], clothing_collection)
    register(gem_r, "chest")
    panel("BeltGem_Male_Q35", [(-0.04, 0.82), (0.0, 0.855), (0.04, 0.82), (0.0, 0.775)], -0.25, 0.018, materials["gold"], clothing_collection, "pelvis")
    for button_index, button_y in enumerate((1.08, 0.98, 0.89)):
        button = add_uv_sphere("JacketButton%d_Male_Q35" % button_index, (0.0, button_y, -0.215), (0.014, 0.014, 0.008), materials["gold"], clothing_collection)
        register(button, "chest")
    nose = add_uv_sphere("Nose_Male_Q35", (0.0, 1.535, -0.178), (0.016, 0.022, 0.010), materials["skin_light"], face_collection)
    register(nose, "head")
    for side in (-1.0, 1.0):
        side_name = "L" if side < 0 else "R"
        if side < 0:
            eye_points = [(-0.125, 1.59), (-0.092, 1.621), (-0.045, 1.621), (-0.020, 1.59), (-0.045, 1.561), (-0.092, 1.561)]
        else:
            eye_points = [(0.020, 1.59), (0.045, 1.621), (0.092, 1.621), (0.125, 1.59), (0.092, 1.561), (0.045, 1.561)]
        # A shallow eyeball is embedded into the face instead of using a flat
        # white billboard.  It catches a soft highlight and keeps the profile
        # three-dimensional while the lid still supplies the almond silhouette.
        eye_socket = add_uv_sphere(
            "EyeSocket_%s_Male_Q35" % side_name,
            (side * 0.074, 1.59, -0.142),
            (0.056, 0.039, 0.016),
            materials["face"],
            face_collection,
            20,
            12,
        )
        register(eye_socket, "head")
        eye = add_uv_sphere(
            "EyeWhite_%s_Male_Q35" % side_name,
            (side * 0.074, 1.59, -0.151),
            (0.048, 0.032, 0.018),
            materials["eye_white"],
            face_collection,
            20,
            12,
        )
        register(eye, "head")
        if side < 0:
            eyelid_points = [(-0.125, 1.595, -0.181), (-0.096, 1.627, -0.181), (-0.048, 1.627, -0.181), (-0.020, 1.595, -0.181)]
        else:
            eyelid_points = [(0.020, 1.595, -0.181), (0.048, 1.627, -0.181), (0.096, 1.627, -0.181), (0.125, 1.595, -0.181)]
        face_line("UpperLid_%s_Male_Q35" % side_name, eyelid_points, 0.006, materials["face"])
        if side < 0:
            lash_points = [(-0.126, 1.602, -0.185), (-0.145, 1.615, -0.185), (-0.151, 1.625, -0.185)]
        else:
            lash_points = [(0.126, 1.602, -0.185), (0.145, 1.615, -0.185), (0.151, 1.625, -0.185)]
        face_line("Lash_%s_Male_Q35" % side_name, lash_points, 0.006, materials["face"])
        if side < 0:
            lower_lid_points = [(-0.122, 1.582, -0.178), (-0.094, 1.558, -0.178), (-0.046, 1.558, -0.178), (-0.022, 1.582, -0.178)]
        else:
            lower_lid_points = [(0.022, 1.582, -0.178), (0.046, 1.558, -0.178), (0.094, 1.558, -0.178), (0.122, 1.582, -0.178)]
        face_line("LowerLid_%s_Male_Q35" % side_name, lower_lid_points, 0.002, materials["face"])
        iris = add_uv_sphere("Iris_%s_Male_Q35" % side_name, (side * 0.074, 1.59, -0.171), (0.030, 0.031, 0.010), materials["iris"], face_collection)
        pupil = add_uv_sphere("Pupil_%s_Male_Q35" % side_name, (side * 0.074, 1.59, -0.181), (0.009, 0.015, 0.003), materials["pupil"], face_collection)
        glint = add_uv_sphere("EyeGlint_%s_Male_Q35" % side_name, (side * 0.066, 1.602, -0.188), (0.005, 0.006, 0.002), materials["eye_white"], face_collection, 12, 8)
        register(iris, "head")
        register(pupil, "head")
        register(glint, "head")

    return appearance


def build_q35_hero_layers(
    hair_collection: bpy.types.Collection,
    face_collection: bpy.types.Collection,
    clothing_collection: bpy.types.Collection,
    materials: dict,
) -> List[Tuple[bpy.types.Object, str]]:
    """Build the reference-facing dressed preview with fewer, fuller forms.

    This layer is intentionally separate from the production mannequin.  It
    uses curved torso panels, embedded eyes, rounded sleeves and a two-level
    cape so the visual review is about the character silhouette instead of a
    collection of flat decals.
    """
    appearance: List[Tuple[bpy.types.Object, str]] = []

    def register(obj: bpy.types.Object, bone_name: str = "") -> bpy.types.Object:
        appearance.append((obj, bone_name))
        return obj

    def panel(
        name: str,
        points: Sequence[Tuple[float, float]],
        z_center: float,
        depth: float,
        material: bpy.types.Material,
        collection: bpy.types.Collection,
        bone_name: str = "",
    ) -> bpy.types.Object:
        builder = MeshBuilder()
        builder.add_prism_xy(points, z_center, depth)
        obj = create_mesh_object(name, builder, collection, material)
        bevel = obj.modifiers.new("Q35_HeroPanelEdge", "BEVEL")
        bevel.width = min(depth * 0.46, 0.020)
        bevel.segments = 4
        return register(obj, bone_name)

    def cloth_panel(
        name: str,
        points: Sequence[Tuple[float, float, float]],
        depth: float,
        material: bpy.types.Material,
        collection: bpy.types.Collection,
        bone_name: str = "",
    ) -> bpy.types.Object:
        builder = MeshBuilder()
        builder.add_prism_xyz(points, depth)
        obj = create_mesh_object(name, builder, collection, material)
        bevel = obj.modifiers.new("Q35_HeroClothEdge", "BEVEL")
        bevel.width = min(depth * 0.42, 0.018)
        bevel.segments = 4
        return register(obj, bone_name)

    def grid_panel(
        name: str,
        rows: Sequence[Sequence[Tuple[float, float, float]]],
        depth: float,
        material: bpy.types.Material,
        collection: bpy.types.Collection,
        bone_name: str = "",
        bevel_width: float = 0.012,
    ) -> bpy.types.Object:
        builder = MeshBuilder()
        builder.add_grid_prism(rows, depth)
        obj = create_mesh_object(name, builder, collection, material)
        bevel = obj.modifiers.new("Q35_CurvedPanelEdge", "BEVEL")
        bevel.width = bevel_width
        bevel.segments = 3
        return register(obj, bone_name)

    def profile_panel(
        name: str,
        points: Sequence[Tuple[float, float]],
        x_center: float,
        depth: float,
        material: bpy.types.Material,
        collection: bpy.types.Collection,
        bone_name: str = "",
    ) -> bpy.types.Object:
        builder = MeshBuilder()
        builder.add_prism_yz(points, x_center, depth)
        obj = create_mesh_object(name, builder, collection, material)
        bevel = obj.modifiers.new("Q35_ProfilePanelEdge", "BEVEL")
        bevel.width = min(depth * 0.42, 0.018)
        bevel.segments = 3
        return register(obj, bone_name)

    def tube(
        name: str,
        points: Sequence[Tuple[float, float, float]],
        radii: Sequence[float],
        material: bpy.types.Material,
        collection: bpy.types.Collection,
        bone_name: str = "",
        depth_scale: float = 0.82,
    ) -> bpy.types.Object:
        builder = MeshBuilder()
        builder.add_tube([Vector(point) for point in points], radii, 18, depth_scale)
        return register(add_subdivision(create_mesh_object(name, builder, collection, material)), bone_name)

    def line(
        name: str,
        points: Sequence[Tuple[float, float, float]],
        radius: float,
        material: bpy.types.Material,
        collection: bpy.types.Collection,
        bone_name: str = "",
    ) -> bpy.types.Object:
        return tube(name, points, [radius] * len(points), material, collection, bone_name, 0.38)

    def tailored_panel(
        name: str,
        points: Sequence[Tuple[float, float]],
        depth: float,
        material: bpy.types.Material,
        collection: bpy.types.Collection,
        bone_name: str = "",
        lift: float = 0.012,
    ) -> bpy.types.Object:
        """Place a front detail on the torso curve instead of one flat plane."""
        curved_points = []
        for x, y in points:
            t = max(0.0, min(1.0, (y - 0.72) / 0.45))
            front_z = -0.090 - 0.055 * (math.sin(math.pi * t) ** 0.82)
            curved_points.append((x, y, front_z - lift))
        return cloth_panel(name, curved_points, depth, material, collection, bone_name)

    def ring(
        name: str,
        location: Tuple[float, float, float],
        major_radius: float,
        minor_radius: float,
        material: bpy.types.Material,
        collection: bpy.types.Collection,
        bone_name: str = "",
    ) -> bpy.types.Object:
        bpy.ops.mesh.primitive_torus_add(
            major_segments=24,
            minor_segments=8,
            mode="MAJOR_MINOR",
            major_radius=major_radius,
            minor_radius=minor_radius,
            location=location,
            rotation=(math.pi * 0.5, 0.0, 0.0),
        )
        obj = bpy.context.object
        obj.name = name
        obj.data.materials.append(material)
        move_to_collection(obj, collection)
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
        obj["worldgoing_asset_id"] = ASSET_ID
        return register(obj, bone_name)

    # Tailored torso: follow the male 3.5-head reference instead of the old
    # long-legged concept pass.  The chest is broad, the waist tapers, and the
    # neck ring closes sharply so the side profile is not a rectangular block.
    torso_builder = MeshBuilder()
    torso_builder.add_revolved(
        [Vector((0.0, 0.72, 0.0)), Vector((0.0, 0.80, 0.0)), Vector((0.0, 0.94, -0.004)), Vector((0.0, 1.07, 0.0)), Vector((0.0, 1.17, 0.0))],
        [0.170, 0.185, 0.205, 0.225, 0.105],
        [0.130, 0.140, 0.150, 0.155, 0.085],
        28,
    )
    register(add_subdivision(create_mesh_object("JacketBody_Male_Q35", torso_builder, clothing_collection, materials["ivory"])), "chest")

    # JacketBody is already a complete rounded shell.  The earlier open
    # front-shell sectors duplicated its front edge, creating the white
    # scallop in front view and several razor-thin layers in profile.

    # A broad curved bib creates the dark center plane seen in the reference.
    # The previous narrow sector sat on the side of the torso, so the front
    # became an unbroken white slab from the camera's actual forward axis.
    grid_panel("JacketCenter_Male_Q35", [
        [(-0.045, 1.275, -0.078), (0.000, 1.275, -0.095), (0.045, 1.275, -0.078)],
        [(-0.065, 1.175, -0.100), (0.000, 1.175, -0.115), (0.065, 1.175, -0.100)],
        [(-0.078, 1.045, -0.145), (0.000, 1.045, -0.165), (0.078, 1.045, -0.145)],
        [(-0.068, 0.915, -0.160), (0.000, 0.915, -0.178), (0.068, 0.915, -0.160)],
        [(-0.042, 0.805, -0.145), (0.000, 0.805, -0.158), (0.042, 0.805, -0.145)],
    ], 0.014, materials["navy"], clothing_collection, "chest", 0.005)
    grid_panel("JacketInner_Male_Q35", [
        [(-0.034, 1.275, -0.094), (0.000, 1.275, -0.105), (0.034, 1.275, -0.094)],
        [(-0.046, 1.175, -0.114), (0.000, 1.175, -0.128), (0.046, 1.175, -0.114)],
        [(-0.040, 1.045, -0.158), (0.000, 1.045, -0.178), (0.040, 1.045, -0.158)],
    ], 0.010, materials["black"], clothing_collection, "chest", 0.004)
    # The previous full bib formed a scalloped white patch under the collar.
    # The high collar and central bib are enough for a clean, tailored neck.
    collar_builder = MeshBuilder()
    collar_builder.add_revolved([Vector((0.0, 1.16, 0.0)), Vector((0.0, 1.28, 0.0))], [0.090, 0.098], [0.076, 0.084], 22)
    register(add_subdivision(create_mesh_object("HighCollar_Male_Q35", collar_builder, clothing_collection, materials["black"])), "neck")
    ring("CollarTrim_Male_Q35", (0.0, 1.265, 0.0), 0.089, 0.006, materials["gold"], clothing_collection, "neck")
    # No separate yoke: it read as a white scalloped bib in the front view.
    # The jacket shell now meets the high collar directly.
    # The rounded jacket shell already supplies the lapel silhouette.  Extra
    # open front plates only created a second edge when viewed from the side.
    # The sash follows the jacket's actual front curve.  Keeping it only a
    # few millimetres proud prevents a true side view from reading it as a
    # floating ribbon.
    tube("JacketSash_Male_Q35", [(-0.135, 1.17, -0.108), (-0.012, 0.99, -0.172), (0.14, 0.80, -0.153)], [0.022, 0.024, 0.019], materials["navy_light"], clothing_collection, "chest", 0.44)
    line("JacketSashTrim_Male_Q35", [(-0.143, 1.17, -0.130), (-0.012, 0.99, -0.198), (0.145, 0.80, -0.176)], 0.0035, materials["gold"], clothing_collection, "chest")
    # Keep the belt as a thin fitted panel.  A second revolved belt volume
    # flared at the side and reintroduced a fat-thin-fat break in the waist.
    panel("WaistBelt_Male_Q35", [(-0.174, 0.82), (0.174, 0.82), (0.160, 0.75), (-0.160, 0.75)], -0.150, 0.026, materials["black"], clothing_collection)
    panel("WaistBeltAccent_Male_Q35", [(-0.034, 0.825), (0.034, 0.825), (0.042, 0.748), (-0.042, 0.748)], -0.182, 0.018, materials["gold"], clothing_collection)
    # The hip tails made the waist look wider than the shoulders and turned
    # the silhouette into a fat-thin-fat rhythm.  Let the belt and trousers
    # define the waist instead of adding two bulky hanging blocks.
    # Let the broad bib and sash carry the tailoring.  A central gold line and
    # three buttons became isolated dots in profile, so omit them here.
    panel("ShoulderCapeL_Male_Q35", [(-0.12, 1.22), (-0.22, 1.18), (-0.285, 1.05), (-0.22, 1.00), (-0.14, 1.10)], -0.055, 0.032, materials["navy"], clothing_collection)
    panel("ShoulderCapeR_Male_Q35", [(0.12, 1.22), (0.22, 1.18), (0.285, 1.05), (0.22, 1.00), (0.14, 1.10)], -0.055, 0.032, materials["navy"], clothing_collection)
    panel("ShoulderCapeTrimL_Male_Q35", [(-0.215, 1.185), (-0.227, 1.178), (-0.280, 1.05), (-0.268, 1.045)], -0.080, 0.010, materials["gold"], clothing_collection)
    panel("ShoulderCapeTrimR_Male_Q35", [(0.227, 1.178), (0.215, 1.185), (0.268, 1.045), (0.280, 1.05)], -0.080, 0.010, materials["gold"], clothing_collection)
    brooch_points = [(0.0, 1.20), (0.018, 1.175), (0.048, 1.17), (0.026, 1.145), (0.030, 1.11), (0.0, 1.13), (-0.030, 1.11), (-0.026, 1.145), (-0.048, 1.17), (-0.018, 1.175)]
    tailored_panel("ChestBrooch_Male_Q35", [(0.14 + x, y) for x, y in brooch_points], 0.010, materials["gold"], clothing_collection, "chest", 0.030)
    register(add_uv_sphere("ChestBroochGem_Male_Q35", (0.14, 1.165, -0.218), (0.010, 0.013, 0.005), materials["navy_light"], clothing_collection, 16, 10), "chest")

    # Arms are deliberately separated from the torso in the neutral pose and
    # use continuous tubes rather than stacked rectangular strips.
    for side in (-1.0, 1.0):
        side_name = "L" if side < 0 else "R"
        bone_arm = "upper_arm_l" if side < 0 else "upper_arm_r"
        bone_forearm = "lower_arm_l" if side < 0 else "lower_arm_r"
        bone_hand = "hand_l" if side < 0 else "hand_r"
        shoulder = add_uv_sphere("Shoulder%s_Male_Q35" % side_name, (side * 0.250, 1.12, 0.012), (0.076, 0.054, 0.066), materials["navy"], clothing_collection, 20, 12)
        register(shoulder, bone_arm)
        tube("Sleeve%s_Male_Q35" % side_name, [(side * 0.250, 1.11, 0.0), (side * 0.295, 1.00, 0.0), (side * 0.327, 0.84, -0.004), (side * 0.324, 0.74, -0.018)], [0.080, 0.074, 0.066, 0.054], materials["ivory"], clothing_collection, bone_arm)
        tube("Cuff%s_Male_Q35" % side_name, [(side * 0.334, 0.78, -0.018), (side * 0.334, 0.68, -0.024)], [0.058, 0.052], materials["black"], clothing_collection, bone_forearm)
        tube("CuffTrim%s_Male_Q35" % side_name, [(side * 0.334, 0.755, -0.022), (side * 0.334, 0.725, -0.024)], [0.061, 0.056], materials["gold"], clothing_collection, bone_forearm)
        panel("CuffPlate%s_Male_Q35" % side_name, [(side * 0.365, 0.775), (side * 0.305, 0.75), (side * 0.305, 0.69), (side * 0.350, 0.67)], -0.090, 0.018, materials["navy"], clothing_collection, bone_forearm)
        hand = add_uv_sphere("Hand%s_Male_Q35" % side_name, (side * 0.332, 0.645, -0.030), (0.054, 0.070, 0.050), materials["skin_light"], clothing_collection, 20, 12)
        register(hand, bone_hand)
        thumb = add_uv_sphere("Thumb%s_Male_Q35" % side_name, (side * 0.368, 0.655, -0.038), (0.017, 0.030, 0.016), materials["skin_light"], clothing_collection, 16, 10)
        thumb.rotation_euler[2] = side * 0.42
        register(thumb, bone_hand)
        for finger_index, finger_x in enumerate((-0.018, 0.0, 0.018)):
            finger = add_uv_sphere(
                "Finger%d%s_Male_Q35" % (finger_index, side_name),
                (side * (0.332 + finger_x), 0.616, -0.046),
                (0.010, 0.026, 0.013),
                materials["skin_light"], clothing_collection, 14, 10,
            )
            register(finger, bone_hand)

    # Slim tailored trousers and boots with a rounded shoe instead of a square
    # terminal block.
    for side in (-1.0, 1.0):
        side_name = "L" if side < 0 else "R"
        bone_leg = "upper_leg_l" if side < 0 else "upper_leg_r"
        bone_foot = "foot_l" if side < 0 else "foot_r"
        tube("Trousers%s_Male_Q35" % side_name, [(side * 0.108, 0.73, 0.0), (side * 0.118, 0.58, 0.0), (side * 0.104, 0.42, 0.0), (side * 0.094, 0.34, 0.0)], [0.118, 0.108, 0.092, 0.076], materials["black"], clothing_collection, bone_leg)
        panel("TrouserStripe%s_Male_Q35" % side_name, [(side * 0.142, 0.70), (side * 0.126, 0.70), (side * 0.109, 0.46), (side * 0.122, 0.46)], -0.078, 0.014, materials["navy_light"], clothing_collection, bone_leg)
        boot_builder = MeshBuilder()
        boot_builder.add_tube([Vector((side * 0.094, 0.35, 0.0)), Vector((side * 0.094, 0.19, 0.0)), Vector((side * 0.094, 0.075, -0.004))], [0.086, 0.080, 0.068], 18)
        register(add_subdivision(create_mesh_object("Boot%s_Male_Q35" % side_name, boot_builder, clothing_collection, materials["boot"])), bone_foot)
        shoe_builder = MeshBuilder()
        shoe_builder.add_foot(Vector((side * 0.090, 0.050, -0.066)), 0.60, 0.82)
        register(add_subdivision(create_mesh_object("Shoe%s_Male_Q35" % side_name, shoe_builder, clothing_collection, materials["boot"])), bone_foot)
        sole_builder = MeshBuilder()
        sole_builder.add_foot(Vector((side * 0.090, 0.012, -0.066)), 0.64, 0.86)
        register(create_mesh_object("ShoeSole%s_Male_Q35" % side_name, sole_builder, clothing_collection, materials["black"]), bone_foot)
        ring("BootTopRing%s_Male_Q35" % side_name, (side * 0.090, 0.335, 0.0), 0.067, 0.009, materials["gold"], clothing_collection, bone_foot)
        ring("BootAnkleRing%s_Male_Q35" % side_name, (side * 0.090, 0.145, -0.002), 0.061, 0.008, materials["gold"], clothing_collection, bone_foot)
        # Keep only the subtle boot rings.  The earlier gold appliques read as
        # random triangles in front view and detached bars in true profile.

    # Asymmetric front cape plus a narrow rear drape.  Both are separate
    # objects so the cape remains replaceable at runtime.
    # Keep the asymmetric front cape as a single readable silhouette.  The
    # rear drape below uses the denser cloth grid; forcing this hanging piece
    # into a narrow strip made it disappear behind the torso in front view.
    cloth_panel("CapeOuter_Male_Q35", [
        (-0.14, 1.16, 0.020), (-0.32, 1.11, 0.030), (-0.50, 0.97, 0.050),
        (-0.58, 0.79, 0.062), (-0.57, 0.59, 0.048), (-0.53, 0.39, 0.022),
        (-0.47, 0.20, -0.008), (-0.36, 0.04, -0.034), (-0.28, 0.18, -0.022),
        (-0.22, 0.50, -0.004), (-0.22, 0.82, 0.010),
    ], 0.050, materials["navy"], clothing_collection, "chest")
    cloth_panel("CapeInner_Male_Q35", [
        (-0.20, 1.08, -0.030), (-0.32, 1.00, -0.038), (-0.44, 0.83, -0.050),
        (-0.48, 0.64, -0.058), (-0.44, 0.44, -0.066), (-0.38, 0.25, -0.074),
        (-0.32, 0.13, -0.080), (-0.29, 0.28, -0.070), (-0.28, 0.52, -0.056),
        (-0.25, 0.79, -0.042),
    ], 0.014, materials["cape_inner"], clothing_collection, "chest")
    grid_panel("CapeBackDrape_Male_Q35", [
        [(-0.20, 1.18, 0.225), (-0.12, 1.18, 0.242), (-0.04, 1.18, 0.245)],
        [(-0.27, 1.05, 0.240), (-0.18, 1.05, 0.275), (-0.07, 1.05, 0.300)],
        [(-0.31, 0.86, 0.250), (-0.20, 0.86, 0.320), (-0.08, 0.86, 0.370)],
        [(-0.30, 0.64, 0.250), (-0.19, 0.64, 0.340), (-0.07, 0.64, 0.390)],
        [(-0.25, 0.40, 0.240), (-0.15, 0.40, 0.330), (-0.04, 0.40, 0.360)],
        [(-0.16, 0.21, 0.220), (-0.08, 0.21, 0.280), (0.00, 0.21, 0.310)],
    ], 0.035, materials["navy"], clothing_collection, "", 0.008)
    grid_panel("CapeBackInner_Male_Q35", [
        [(-0.16, 1.10, 0.260), (-0.10, 1.10, 0.270), (-0.04, 1.10, 0.272)],
        [(-0.22, 0.91, 0.270), (-0.15, 0.91, 0.300), (-0.06, 0.91, 0.320)],
        [(-0.23, 0.70, 0.270), (-0.15, 0.70, 0.315), (-0.06, 0.70, 0.340)],
        [(-0.18, 0.47, 0.255), (-0.11, 0.47, 0.300), (-0.04, 0.47, 0.325)],
        [(-0.09, 0.28, 0.235), (-0.05, 0.28, 0.265), (0.00, 0.28, 0.290)],
    ], 0.012, materials["navy_light"], clothing_collection, "", 0.005)
    # The rear grid already supplies the cape's side silhouette.  A second
    # yz-profile slice created a razor-thin line in the rear camera, so keep
    # the cape represented by one continuous surface instead of overlapping
    # edge-on helper panels.

    # Head, layered hair and a compact embedded eye system.
    head_builder = MeshBuilder()
    head_builder.add_revolved(
        [Vector((0.0, 1.35, 0.0)), Vector((0.0, 1.40, 0.0)), Vector((0.0, 1.49, -0.005)), Vector((0.0, 1.60, -0.002)), Vector((0.0, 1.70, 0.008)), Vector((0.0, 1.77, 0.018))],
        [0.064, 0.108, 0.158, 0.184, 0.158, 0.070],
        [0.066, 0.110, 0.154, 0.188, 0.158, 0.068],
        28,
    )
    register(add_subdivision(create_mesh_object("HeadSkin_Male_Q35", head_builder, face_collection, materials["skin"])), "head")
    register(add_uv_sphere("NeckSkin_Male_Q35", (0.0, 1.385, 0.0), (0.070, 0.105, 0.060), materials["skin"], face_collection), "neck")
    for side in (-1.0, 1.0):
        side_name = "L" if side < 0 else "R"
        register(add_uv_sphere("Ear%s_Male_Q35" % side_name, (side * 0.165, 1.535, -0.005), (0.032, 0.052, 0.024), materials["skin_light"], face_collection), "head")

    register(add_uv_sphere("HairCap_Male_Q35", (0.0, 1.67, 0.005), (0.235, 0.184, 0.195), materials["hair"], hair_collection), "head")
    for side in (-1.0, 1.0):
        side_name = "L" if side < 0 else "R"
        register(add_uv_sphere("HairLock%s_Male_Q35" % side_name, (side * 0.205, 1.60, 0.012), (0.034, 0.086, 0.045), materials["hair"], hair_collection), "head")
    hair_strands = (
        ("HairLockFrontL_Male_Q35", [(-0.015, 1.77, -0.145), (-0.07, 1.71, -0.205), (-0.12, 1.62, -0.215), (-0.14, 1.54, -0.19)], [0.043, 0.050, 0.034, 0.010], materials["hair"]),
        ("HairLockFrontR_Male_Q35", [(0.015, 1.77, -0.145), (0.07, 1.71, -0.205), (0.12, 1.62, -0.215), (0.14, 1.54, -0.19)], [0.043, 0.050, 0.034, 0.010], materials["hair"]),
        ("HairSweepL_Male_Q35", [(-0.10, 1.78, -0.115), (-0.16, 1.72, -0.17), (-0.20, 1.64, -0.16), (-0.21, 1.56, -0.10)], [0.034, 0.040, 0.030, 0.009], materials["hair_highlight"]),
        ("HairSweepR_Male_Q35", [(0.10, 1.78, -0.115), (0.16, 1.72, -0.17), (0.20, 1.64, -0.16), (0.21, 1.56, -0.10)], [0.034, 0.040, 0.030, 0.009], materials["hair"]),
        ("HairBackCenter_Male_Q35", [(0.0, 1.79, 0.125), (0.0, 1.71, 0.16), (0.0, 1.61, 0.17), (0.0, 1.49, 0.115)], [0.038, 0.046, 0.034, 0.010], materials["hair"]),
        ("HairBackL_Male_Q35", [(-0.055, 1.78, 0.11), (-0.12, 1.72, 0.145), (-0.18, 1.64, 0.15), (-0.20, 1.54, 0.095)], [0.034, 0.043, 0.031, 0.009], materials["hair_highlight"]),
        ("HairBackR_Male_Q35", [(0.055, 1.78, 0.11), (0.12, 1.72, 0.145), (0.18, 1.64, 0.15), (0.20, 1.54, 0.095)], [0.034, 0.043, 0.031, 0.009], materials["hair"]),
        ("HairBackOuterL_Male_Q35", [(-0.14, 1.72, 0.075), (-0.21, 1.65, 0.10), (-0.245, 1.57, 0.085), (-0.235, 1.50, 0.050)], [0.027, 0.036, 0.024, 0.007], materials["hair"]),
        ("HairBackOuterR_Male_Q35", [(0.14, 1.72, 0.075), (0.21, 1.65, 0.10), (0.245, 1.57, 0.085), (0.235, 1.50, 0.050)], [0.027, 0.036, 0.024, 0.007], materials["hair_highlight"]),
        ("HairFringeInnerL_Male_Q35", [(-0.035, 1.80, -0.155), (-0.090, 1.75, -0.215), (-0.145, 1.68, -0.225), (-0.165, 1.61, -0.205)], [0.030, 0.038, 0.030, 0.008], materials["hair_highlight"]),
        ("HairFringeInnerR_Male_Q35", [(0.035, 1.80, -0.155), (0.090, 1.75, -0.215), (0.145, 1.68, -0.225), (0.165, 1.61, -0.205)], [0.030, 0.038, 0.030, 0.008], materials["hair"]),
        ("HairFringeOuterL_Male_Q35", [(-0.145, 1.77, -0.105), (-0.205, 1.71, -0.155), (-0.245, 1.64, -0.135), (-0.265, 1.58, -0.060)], [0.028, 0.038, 0.028, 0.007], materials["hair"]),
        ("HairFringeOuterR_Male_Q35", [(0.145, 1.77, -0.105), (0.205, 1.71, -0.155), (0.245, 1.64, -0.135), (0.265, 1.58, -0.060)], [0.028, 0.038, 0.028, 0.007], materials["hair_highlight"]),
        ("HairBackLayerL_Male_Q35", [(-0.085, 1.80, 0.205), (-0.185, 1.72, 0.245), (-0.255, 1.61, 0.235), (-0.285, 1.51, 0.145)], [0.039, 0.050, 0.035, 0.009], materials["hair_highlight"]),
        ("HairBackLayerR_Male_Q35", [(0.085, 1.80, 0.205), (0.185, 1.72, 0.245), (0.255, 1.61, 0.235), (0.285, 1.51, 0.145)], [0.039, 0.050, 0.035, 0.009], materials["hair"]),
    )
    for name, points, radii, material in hair_strands:
        tube(name, points, radii, material, hair_collection, "head", 0.34)
    # Solid tapered locks break up the smooth cap.  These sit between the
    # scalp volume and the fine strands, giving the silhouette the layered,
    # hand-sculpted hair shape of the reference from the rear as well.
    for name, points, depth, material in (
        ("HairClumpFrontL_Male_Q35", [(-0.020, 1.80, -0.170), (-0.090, 1.76, -0.205), (-0.165, 1.68, -0.218), (-0.185, 1.61, -0.185), (-0.135, 1.66, -0.175), (-0.070, 1.75, -0.155)], 0.030, materials["hair"]),
        ("HairClumpFrontR_Male_Q35", [(0.020, 1.80, -0.170), (0.090, 1.76, -0.205), (0.165, 1.68, -0.218), (0.185, 1.61, -0.185), (0.135, 1.66, -0.175), (0.070, 1.75, -0.155)], 0.030, materials["hair_highlight"]),
        ("HairClumpSideL_Male_Q35", [(-0.175, 1.78, -0.075), (-0.235, 1.70, -0.105), (-0.285, 1.62, -0.055), (-0.270, 1.55, 0.020), (-0.220, 1.62, 0.025)], 0.034, materials["hair_highlight"]),
        ("HairClumpSideR_Male_Q35", [(0.175, 1.78, -0.075), (0.235, 1.70, -0.105), (0.285, 1.62, -0.055), (0.270, 1.55, 0.020), (0.220, 1.62, 0.025)], 0.034, materials["hair"]),
        ("HairClumpBackL_Male_Q35", [(-0.055, 1.84, 0.205), (-0.145, 1.79, 0.245), (-0.235, 1.69, 0.255), (-0.295, 1.58, 0.200), (-0.245, 1.63, 0.175), (-0.130, 1.76, 0.175)], 0.040, materials["hair_highlight"]),
        ("HairClumpBackR_Male_Q35", [(0.055, 1.84, 0.205), (0.145, 1.79, 0.245), (0.235, 1.69, 0.255), (0.295, 1.58, 0.200), (0.245, 1.63, 0.175), (0.130, 1.76, 0.175)], 0.040, materials["hair"]),
    ):
        cloth_panel(name, points, depth, material, hair_collection, "head")
    # Bring the rear lock layers just outside the scalp cap.  Their source
    # paths hug the head, but if they stay behind the cap the back view reads
    # as one smooth helmet instead of layered hair.
    for name, offset in (
        ("HairBackCenter_Male_Q35", 0.120),
        ("HairBackL_Male_Q35", 0.105),
        ("HairBackR_Male_Q35", 0.105),
        ("HairBackOuterL_Male_Q35", 0.090),
        ("HairBackOuterR_Male_Q35", 0.090),
        ("HairBackLayerL_Male_Q35", 0.040),
        ("HairBackLayerR_Male_Q35", 0.040),
        ("HairClumpBackL_Male_Q35", 0.035),
        ("HairClumpBackR_Male_Q35", 0.035),
    ):
        rear_lock = bpy.data.objects.get(name)
        if rear_lock is not None:
            rear_lock.location.z += offset
    # The fine front/sweep locks already define the side contour.  Extra flat
    # taper panels made the profile look like two detached hair blades.
    tube("HairCowlick_Male_Q35", [(0.0, 1.78, -0.02), (-0.01, 1.84, -0.07), (0.025, 1.89, -0.06), (0.065, 1.90, -0.025)], [0.025, 0.021, 0.013, 0.004], materials["hair_highlight"], hair_collection, "head", 0.34)

    line("BrowL_Male_Q35", [(-0.125, 1.655, -0.218), (-0.095, 1.669, -0.222), (-0.055, 1.661, -0.218)], 0.007, materials["face"], face_collection, "head")
    line("BrowR_Male_Q35", [(0.055, 1.661, -0.218), (0.095, 1.669, -0.222), (0.125, 1.655, -0.218)], 0.007, materials["face"], face_collection, "head")
    line("Smile_Male_Q35", [(-0.030, 1.452, -0.232), (-0.012, 1.444, -0.240), (0.012, 1.444, -0.240), (0.030, 1.452, -0.232)], 0.004, materials["face"], face_collection, "head")
    line("LowerLip_Male_Q35", [(-0.012, 1.431, -0.226), (0.0, 1.428, -0.231), (0.012, 1.431, -0.226)], 0.0025, materials["skin_light"], face_collection, "head")
    # Give the profile a small but real bridge/tip; the former shallow dot
    # disappeared completely when the character was viewed from the side.
    tube("NoseBridge_Male_Q35", [(0.0, 1.610, -0.186), (0.0, 1.570, -0.205), (0.0, 1.545, -0.220)], [0.009, 0.012, 0.011], materials["skin_light"], face_collection, "head", 0.52)
    register(add_uv_sphere("Nose_Male_Q35", (0.0, 1.535, -0.228), (0.018, 0.019, 0.029), materials["skin_light"], face_collection), "head")
    for side in (-1.0, 1.0):
        side_name = "L" if side < 0 else "R"
        socket_outline = [
            (-0.135, 1.595, -0.184), (-0.103, 1.636, -0.184), (-0.043, 1.636, -0.184),
            (-0.010, 1.595, -0.184), (-0.043, 1.553, -0.184), (-0.103, 1.553, -0.184),
        ]
        eye_outline = [
            (-0.125, 1.595, -0.204), (-0.096, 1.622, -0.204), (-0.048, 1.622, -0.204),
            (-0.020, 1.595, -0.204), (-0.048, 1.567, -0.204), (-0.096, 1.567, -0.204),
        ]
        if side > 0:
            socket_outline = [(-x, y, z) for x, y, z in socket_outline]
            eye_outline = [(-x, y, z) for x, y, z in eye_outline]
        cloth_panel("EyeSocket_%s_Male_Q35" % side_name, socket_outline, 0.018, materials["skin"], face_collection, "head")
        cloth_panel("EyeWhite_%s_Male_Q35" % side_name, eye_outline, 0.014, materials["eye_white"], face_collection, "head")
        if side < 0:
            upper_points = [(-0.125, 1.595, -0.224), (-0.096, 1.621, -0.224), (-0.048, 1.621, -0.224), (-0.020, 1.595, -0.224)]
            lower_points = [(-0.122, 1.583, -0.221), (-0.094, 1.564, -0.221), (-0.046, 1.564, -0.221), (-0.022, 1.583, -0.221)]
            lash_points = [(-0.126, 1.602, -0.230), (-0.145, 1.614, -0.230), (-0.151, 1.623, -0.230)]
        else:
            upper_points = [(0.020, 1.595, -0.224), (0.048, 1.621, -0.224), (0.096, 1.621, -0.224), (0.125, 1.595, -0.224)]
            lower_points = [(0.022, 1.583, -0.221), (0.046, 1.564, -0.221), (0.094, 1.564, -0.221), (0.122, 1.583, -0.221)]
            lash_points = [(0.126, 1.602, -0.230), (0.145, 1.614, -0.230), (0.151, 1.623, -0.230)]
        line("UpperLid_%s_Male_Q35" % side_name, upper_points, 0.007, materials["face"], face_collection, "head")
        line("LowerLid_%s_Male_Q35" % side_name, lower_points, 0.0015, materials["skin_light"], face_collection, "head")
        line("Lash_%s_Male_Q35" % side_name, lash_points, 0.007, materials["face"], face_collection, "head")
        register(add_uv_sphere("Iris_%s_Male_Q35" % side_name, (side * 0.074, 1.59, -0.223), (0.032, 0.024, 0.010), materials["iris"], face_collection), "head")
        register(add_uv_sphere("Pupil_%s_Male_Q35" % side_name, (side * 0.074, 1.59, -0.234), (0.008, 0.012, 0.003), materials["pupil"], face_collection), "head")
        register(add_uv_sphere("EyeGlint_%s_Male_Q35" % side_name, (side * 0.064, 1.602, -0.241), (0.005, 0.006, 0.002), materials["eye_glint"], face_collection, 12, 8), "head")

    return appearance


def apply_preview_proportions(appearance: Sequence[Tuple[bpy.types.Object, str]]) -> None:
    """Keep the dressed presentation aligned to the specification's 3.5-head body.

    The clean BaseBody export remains at the contracted Q35 proportions.  Only the
    replaceable dressed layers are adjusted here, so the preview can be judged as
    character art without changing the formal rig/base asset.  The compact male
    reference is the source of truth; do not stretch it into a long-legged variant.
    """
    overall = Matrix.Diagonal((1.0, 1.0, 1.0, 1.0))
    for obj, _ in appearance:
        obj.matrix_world = overall @ obj.matrix_world

    head_prefixes = (
        "HeadSkin_", "NeckSkin_", "Ear", "Hair", "Brow", "Smile", "Nose", "Cheek", "Eye", "Iris", "Pupil",
        "UpperLid", "LowerLid", "Lash", "LowerLip",
    )
    head_pivot = Vector((0.0, 1.30, 0.0))
    head_transform = (
        Matrix.Translation(Vector((0.0, -0.010, 0.0)))
        @ Matrix.Translation(head_pivot)
        @ Matrix.Diagonal((0.86, 0.93, 0.92, 1.0))
        @ Matrix.Translation(-head_pivot)
    )
    for obj, _ in appearance:
        if obj.name.startswith(head_prefixes):
            obj.matrix_world = head_transform @ obj.matrix_world
        # Blender can retain a unit scale on the last UV sphere created in a
        # repeated eye loop when the parent transform is rebuilt.  Keep the
        # tiny catchlight explicitly tiny so it can never become a full-face
        # billboard.
        if obj.name.startswith("EyeGlint_"):
            obj.scale = (0.005, 0.006 * 0.93 * 0.82, 0.002 * 0.92)


def global_bone_positions() -> List[Vector]:
    result: List[Vector] = []
    for index, local in enumerate(LOCAL_BONE_POSITIONS):
        position = Vector(local)
        parent = PARENT_INDICES[index]
        if parent >= 0:
            position += result[parent]
        result.append(position)
    return result


def create_armature(collection: bpy.types.Collection) -> bpy.types.Object:
    data = bpy.data.armatures.new("HumanRig_v1_Q35_Armature")
    armature = bpy.data.objects.new("HumanRig_v1_Q35", data)
    collection.objects.link(armature)
    armature["worldgoing_asset_id"] = ASSET_ID
    armature["rig_contract"] = "HumanRig_v1"
    armature["bone_count"] = len(BONE_NAMES)
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    positions = global_bone_positions()
    edit_bones = []
    for index, bone_name in enumerate(BONE_NAMES):
        bone = data.edit_bones.new(bone_name)
        bone.head = positions[index]
        bone.tail = positions[index] + Vector((0.0, 0.08, 0.0))
        edit_bones.append(bone)
    for index, parent_index in enumerate(PARENT_INDICES):
        if parent_index >= 0:
            edit_bones[index].parent = edit_bones[parent_index]
            edit_bones[index].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.select_set(False)
    return armature


def add_socket_markers(armature: bpy.types.Object, collection: bpy.types.Collection) -> List[bpy.types.Object]:
    markers = []
    for socket_name, bone_name in SOCKET_BONES.items():
        marker = bpy.data.objects.new(socket_name, None)
        marker.empty_display_type = "PLAIN_AXES"
        marker.empty_display_size = 0.045
        marker.parent = armature
        marker.parent_type = "BONE"
        marker.parent_bone = bone_name
        marker["socket_contract"] = socket_name
        marker["bone_name"] = bone_name
        collection.objects.link(marker)
        markers.append(marker)
    return markers


def bone_name_for_vertex(co: Vector) -> str:
    if co.y >= 1.29:
        return "head"
    if co.y >= 1.16:
        return "neck"
    if abs(co.x) >= 0.20 and co.y >= 0.96:
        return "upper_arm_l" if co.x < 0 else "upper_arm_r"
    if abs(co.x) >= 0.20 and co.y >= 0.70:
        return "lower_arm_l" if co.x < 0 else "lower_arm_r"
    if abs(co.x) >= 0.20:
        return "hand_l" if co.x < 0 else "hand_r"
    if co.y <= 0.18:
        return "lower_leg_l" if co.x < 0 else "lower_leg_r"
    if co.y <= 0.55:
        return "upper_leg_l" if co.x < 0 else "upper_leg_r"
    if co.y <= 0.78:
        return "pelvis"
    if co.y <= 1.02:
        return "spine"
    return "chest"


def add_skinning(obj: bpy.types.Object, armature: bpy.types.Object) -> None:
    world_matrix = obj.matrix_world.copy()
    obj.parent = armature
    obj.parent_type = "OBJECT"
    obj.matrix_world = world_matrix
    for bone_name in BONE_NAMES:
        obj.vertex_groups.new(name=bone_name)
    for vertex in obj.data.vertices:
        bone_name = bone_name_for_vertex(vertex.co)
        obj.vertex_groups[bone_name].add([vertex.index], 1.0, "REPLACE")
    modifier = obj.modifiers.new("HumanRig_v1_Skin", "ARMATURE")
    modifier.object = armature
    obj["skin_contract"] = "single_armature_modifier_with_explicit_region_weights"


def parent_to_bone(obj: bpy.types.Object, armature: bpy.types.Object, bone_name: str) -> None:
    bpy.context.view_layer.update()
    world_matrix = obj.matrix_world.copy()
    obj.parent = armature
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    bpy.context.view_layer.update()
    obj.matrix_world = world_matrix


def parent_to_armature(obj: bpy.types.Object, armature: bpy.types.Object) -> None:
    bpy.context.view_layer.update()
    world_matrix = obj.matrix_world.copy()
    obj.parent = armature
    obj.parent_type = "OBJECT"
    bpy.context.view_layer.update()
    obj.matrix_world = world_matrix


def add_camera(name: str, location: Tuple[float, float, float], target: Tuple[float, float, float], collection: bpy.types.Collection) -> bpy.types.Object:
    data = bpy.data.cameras.new(name + "_Data")
    data.type = "ORTHO"
    data.ortho_scale = 2.20
    camera = bpy.data.objects.new(name, data)
    collection.objects.link(camera)
    camera.location = location
    direction = (Vector(target) - camera.location).normalized()
    right = direction.cross(Vector((0.0, 1.0, 0.0))).normalized()
    up = right.cross(direction).normalized()
    camera.rotation_euler = Matrix((
        (right.x, up.x, -direction.x),
        (right.y, up.y, -direction.y),
        (right.z, up.z, -direction.z),
    )).to_euler()
    camera["view_contract"] = name.replace("Q35_Camera_", "").lower()
    return camera


def add_area_light(name: str, location: Tuple[float, float, float], target: Tuple[float, float, float], energy: float, size: float) -> bpy.types.Object:
    old_light = bpy.data.objects.get(name)
    if old_light is not None:
        bpy.data.objects.remove(old_light, do_unlink=True)
    data = bpy.data.lights.new(name + "_Data", "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    light = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(light)
    light.location = location
    light.rotation_euler = (Vector(target) - light.location).to_track_quat("-Z", "Y").to_euler()
    return light


def add_preview_ground() -> None:
    old_ground = bpy.data.objects.get("Q35_PreviewGround")
    if old_ground is not None:
        bpy.data.objects.remove(old_ground, do_unlink=True)
    ground_material = make_material("Q35_Ground", (0.16, 0.17, 0.20), 0.92)
    bpy.ops.mesh.primitive_plane_add(size=20.0, location=(0.0, -0.015, 0.0))
    ground = bpy.context.object
    ground.name = "Q35_PreviewGround"
    ground.data.materials.append(ground_material)


def configure_scene() -> None:
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    try:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    except (TypeError, ValueError):
        scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.world.color = (0.38, 0.40, 0.45)
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    if background is not None:
        background.inputs["Color"].default_value = (0.38, 0.40, 0.45, 1.0)
        background.inputs["Strength"].default_value = 0.65
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except (TypeError, ValueError):
        pass
    add_area_light("Q35_Key_Light", (3.0, 3.0, -4.0), (0.0, 0.95, 0.0), 900.0, 3.0)
    add_area_light("Q35_Fill_Light", (-3.0, 1.5, -2.0), (0.0, 0.95, 0.0), 500.0, 3.5)
    add_area_light("Q35_Rim_Light", (0.0, 3.0, 4.0), (0.0, 1.05, 0.0), 1000.0, 2.5)
    add_preview_ground()


def export_glb(objects: Iterable[bpy.types.Object], filepath: str) -> None:
    object_list = list(objects)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in object_list:
        obj.hide_viewport = False
        obj.hide_render = False
        obj.select_set(True)
    bpy.context.view_layer.objects.active = object_list[0]
    try:
        bpy.ops.export_scene.gltf(
            filepath=filepath,
            export_format="GLB",
            use_selection=True,
            export_apply=True,
            export_animations=False,
        )
    finally:
        bpy.ops.object.select_all(action="DESELECT")


def export_base_glb(objects: Iterable[bpy.types.Object]) -> None:
    export_glb(objects, GLB_PATH)


def export_dressed_preview_glb(objects: Iterable[bpy.types.Object]) -> None:
    export_glb(objects, DRESSED_GLB_PATH)


def main() -> None:
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    if not os.path.exists(SPEC_PATH):
        raise FileNotFoundError("Missing Q35 contract: %s" % SPEC_PATH)
    hide_factory_startup_objects()
    delete_dedicated_collection(COLLECTION_NAME)
    root = bpy.data.collections.new(COLLECTION_NAME)
    bpy.context.scene.collection.children.link(root)
    base_collection = new_collection("Base", root)
    hair_collection = new_collection("Hair", root)
    face_collection = new_collection("Face", root)
    clothing_collection = new_collection("Clothing", root)
    socket_collection = new_collection("Sockets", root)
    camera_collection = new_collection("PreviewCameras", root)

    materials = {
        "skin": make_material("Q35_Skin", (0.70, 0.34, 0.17), 0.72),
        "skin_light": make_material("Q35_SkinLight", (0.74, 0.38, 0.20), 0.68),
        "shorts": make_material("Q35_Shorts", (0.10, 0.11, 0.13)),
        "hair": make_material("Q35_Hair", (0.016, 0.004, 0.0015), 0.58),
        "hair_highlight": make_material("Q35_HairHighlight", (0.028, 0.006, 0.002), 0.56),
        "face": make_material("Q35_Face", (0.025, 0.018, 0.020)),
        "eye_white": make_material("Q35_EyeWhite", (0.86, 0.78, 0.69), 0.52),
        "eye_glint": make_material("Q35_EyeGlint", (1.0, 0.97, 0.88), 0.22),
        "iris": make_material("Q35_Iris", (0.045, 0.010, 0.003), 0.38),
        "pupil": make_material("Q35_Pupil", (0.008, 0.004, 0.002)),
        "ivory": make_material("Q35_Ivory", (0.78, 0.66, 0.48), 0.64),
        "navy": make_material("Q35_Navy", (0.006, 0.012, 0.045), 0.52),
        "navy_light": make_material("Q35_NavyLight", (0.014, 0.030, 0.095), 0.52),
        "black": make_material("Q35_Black", (0.018, 0.014, 0.018), 0.58),
        "boot": make_material("Q35_Boot", (0.004, 0.005, 0.014), 0.42),
        "gold": make_material("Q35_Gold", (0.68, 0.25, 0.035), 0.32),
        "cape_inner": make_material("Q35_CapeInner", (0.72, 0.61, 0.46), 0.62),
    }

    body = build_base_body(base_collection, materials["skin"])
    shorts = build_base_shorts(base_collection, materials["shorts"])
    armature = create_armature(base_collection)
    add_skinning(body, armature)
    add_skinning(shorts, armature)
    socket_markers = add_socket_markers(armature, socket_collection)

    presentation_objects = build_q35_hero_layers(hair_collection, face_collection, clothing_collection, materials)
    apply_preview_proportions(presentation_objects)
    for obj, bone_name in presentation_objects:
        if bone_name:
            parent_to_bone(obj, armature, bone_name)
        else:
            parent_to_armature(obj, armature)
    for collection in (hair_collection, face_collection, clothing_collection):
        collection["replaceable_layer"] = True
        collection["production_export"] = False

    add_camera("Q35_Camera_Front", (0.0, 0.88, -5.5), (0.0, 0.88, 0.0), camera_collection)
    add_camera("Q35_Camera_Side", (5.5, 0.88, 0.0), (0.0, 0.88, 0.0), camera_collection)
    add_camera("Q35_Camera_Back", (0.0, 0.88, 5.5), (0.0, 0.88, 0.0), camera_collection)
    add_camera("Q35_Camera_ThreeQuarter", (3.4, 1.08, -3.4), (0.0, 0.88, 0.0), camera_collection)
    configure_scene()

    for obj in (body, shorts, armature):
        obj["asset_id"] = ASSET_ID
        obj["height_m"] = HEIGHT_M
        obj["head_ratio"] = 3.5
        obj["forward_axis"] = FORWARD_AXIS
    armature["socket_markers"] = json.dumps(sorted(SOCKET_BONES.keys()))

    bpy.context.scene.camera = bpy.data.objects.get("Q35_Camera_Front")
    export_base_glb((body, shorts, armature, *socket_markers))
    export_dressed_preview_glb((body, shorts, armature, *socket_markers, *(obj for obj, _ in presentation_objects)))
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print("WORLDGOING_Q35_BLENDER_BUILD_PASS")
    print("BLEND=%s" % BLEND_PATH)
    print("GLB=%s" % GLB_PATH)
    print("DRESSED_GLB=%s" % DRESSED_GLB_PATH)
    print("BODY=BaseBody_Male_Q35 SHORTS=BaseShorts_Male_Q35 BONES=22")


if __name__ == "__main__":
    main()
