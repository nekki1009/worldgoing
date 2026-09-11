import importlib.util
import os
import sys
from collections import Counter

import bpy
from mathutils import Vector


def load_vrm_addon(addon_dir: str):
    parent_dir = os.path.dirname(addon_dir)
    if parent_dir not in sys.path:
        sys.path.insert(0, parent_dir)
    bpy.ops.preferences.addon_enable(module="io_scene_vrm")
    return sys.modules.get("io_scene_vrm")


def main() -> None:
    project_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
    gender = os.environ.get("WORLDGOING_ANIME_GENDER", "male").strip().lower()
    model_name = "HairSample_Male.vrm" if gender == "male" else "HairSample_Female.vrm"
    model_path = os.path.join(project_dir, ".tools", "standard_anime_base", model_name)
    addon_dir = os.path.join(
        project_dir,
        ".tools",
        "standard_anime_base",
        "io_scene_vrm",
    )
    load_vrm_addon(addon_dir)
    bpy.ops.import_scene.vrm(filepath=model_path, use_addon_preferences=True)
    bpy.context.view_layer.update()
    print("WORLDGOING_STANDARD_VRM_IMPORT_PASS")
    for obj in bpy.context.scene.objects:
        if obj.type not in {"MESH", "ARMATURE", "EMPTY"}:
            continue
        corners = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box] if obj.type == "MESH" else []
        if corners:
            min_v = tuple(min(v[i] for v in corners) for i in range(3))
            max_v = tuple(max(v[i] for v in corners) for i in range(3))
            print("OBJECT=%s TYPE=%s MIN=%s MAX=%s" % (obj.name, obj.type, min_v, max_v))
            material_names = [material.name if material is not None else "<none>" for material in obj.data.materials]
            polygon_counts = Counter(polygon.material_index for polygon in obj.data.polygons)
            print("MATERIALS=%s POLYGON_COUNTS=%s" % (material_names, dict(polygon_counts)))
        else:
            print("OBJECT=%s TYPE=%s" % (obj.name, obj.type))


if __name__ == "__main__":
    main()
