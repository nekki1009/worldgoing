"""Render the editable Blender Q35 scene for visual handoff review."""

import os

import bpy


ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUTPUT_DIR = os.path.join(ROOT_DIR, ".visual_captures", "base_body_series_male_q35", "blender")


def main() -> None:
    os.makedirs(OUTPUT_DIR, exist_ok=True)
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
    # The preview judges the replaceable dressed layers.  Keep the formal base
    # mesh in the .blend/GLB handoff, but do not let it poke through the slimmer
    # presentation silhouette during art review.
    for object_name in ("BaseBody_Male_Q35", "BaseShorts_Male_Q35"):
        base_object = bpy.data.objects.get(object_name)
        if base_object is not None:
            base_object.hide_render = True
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
        scene.render.filepath = os.path.join(OUTPUT_DIR, filename)
        bpy.ops.render.render(write_still=True)
        print("WORLDGOING_Q35_RENDER_PASS=%s" % scene.render.filepath)


if __name__ == "__main__":
    main()
