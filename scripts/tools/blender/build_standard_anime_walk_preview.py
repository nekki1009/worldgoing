"""Bake and render a short walk cycle for the retained Standard Anime base."""

import math
import os

import bpy
from mathutils import Vector


PROJECT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
INPUT_BLEND = os.path.join(
    PROJECT_DIR,
    "assets",
    "characters",
    "human",
    "q35",
    "base_body_series_male_standard_anime_body_only.blend",
)
OUTPUT_BLEND = os.path.join(
    PROJECT_DIR,
    "assets",
    "characters",
    "human",
    "q35",
    "base_body_series_male_standard_anime_body_only_walk.blend",
)
OUTPUT_GLB = os.path.join(
    PROJECT_DIR,
    "assets",
    "characters",
    "human",
    "q35",
    "base_body_series_male_standard_anime_body_only_walk.glb",
)
FRAME_DIR = os.path.join(
    PROJECT_DIR, ".visual_captures", "standard_anime_walk_blender", "frames"
)
FRAME_START = 1
FRAME_END = 25


def pose_bone(armature: bpy.types.Object, name: str) -> bpy.types.PoseBone:
    bone = armature.pose.bones.get(name)
    if bone is None:
        raise RuntimeError(f"Missing required walk bone: {name}")
    bone.rotation_mode = "XYZ"
    return bone


def apply_walk_pose(armature: bpy.types.Object, frame: int) -> None:
    phase = (frame - FRAME_START) / 12.0 * math.pi
    stride = math.sin(phase)
    knee_left = max(0.0, -stride) * 0.42
    knee_right = max(0.0, stride) * 0.42
    arm_swing = math.sin(phase + math.pi) * 0.22

    controlled = [
        "J_Bip_C_Hips",
        "J_Bip_C_Chest",
        "J_Bip_C_Head",
        "J_Bip_L_UpperArm",
        "J_Bip_L_LowerArm",
        "J_Bip_R_UpperArm",
        "J_Bip_R_LowerArm",
        "J_Bip_L_UpperLeg",
        "J_Bip_L_LowerLeg",
        "J_Bip_L_Foot",
        "J_Bip_R_UpperLeg",
        "J_Bip_R_LowerLeg",
        "J_Bip_R_Foot",
    ]
    bones = {name: pose_bone(armature, name) for name in controlled}
    for bone in bones.values():
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.location = (0.0, 0.0, 0.0)

    bones["J_Bip_L_UpperLeg"].rotation_euler.x = stride * 0.48
    bones["J_Bip_R_UpperLeg"].rotation_euler.x = -stride * 0.48
    bones["J_Bip_L_LowerLeg"].rotation_euler.x = knee_left
    bones["J_Bip_R_LowerLeg"].rotation_euler.x = knee_right
    bones["J_Bip_L_Foot"].rotation_euler.x = -stride * 0.16 - knee_left * 0.20
    bones["J_Bip_R_Foot"].rotation_euler.x = stride * 0.16 - knee_right * 0.20

    # The source is a T-pose. Local X is the shoulder drop axis on this VRM
    # skeleton; the Z component is a small counter-swing after the drop.
    bones["J_Bip_L_UpperArm"].rotation_euler = (-1.16, 0.0, arm_swing)
    bones["J_Bip_R_UpperArm"].rotation_euler = (-1.16, 0.0, -arm_swing)
    bones["J_Bip_L_LowerArm"].rotation_euler = (0.12, 0.0, arm_swing * 0.25)
    bones["J_Bip_R_LowerArm"].rotation_euler = (0.12, 0.0, -arm_swing * 0.25)
    bones["J_Bip_C_Chest"].rotation_euler.z = stride * 0.035
    bones["J_Bip_C_Head"].rotation_euler.z = -stride * 0.025
    bones["J_Bip_C_Hips"].location.z = abs(math.sin(phase * 2.0)) * 0.025

    for name, bone in bones.items():
        bone.keyframe_insert(data_path="rotation_euler", frame=frame, group="Walk")
        if name == "J_Bip_C_Hips":
            bone.keyframe_insert(data_path="location", frame=frame, group="Walk")


def bounds(mesh_objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    points: list[Vector] = []
    for obj in mesh_objects:
        points.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    return (
        Vector((min(point.x for point in points), min(point.y for point in points), min(point.z for point in points))),
        Vector((max(point.x for point in points), max(point.y for point in points), max(point.z for point in points))),
    )


def prepare_action(armature: bpy.types.Object) -> bpy.types.Action:
    armature.animation_data_clear()
    action = bpy.data.actions.new("walk")
    armature.animation_data_create()
    armature.animation_data.action = action
    for frame in range(FRAME_START, FRAME_END + 1, 6):
        bpy.context.scene.frame_set(frame)
        apply_walk_pose(armature, frame)
    bpy.context.scene.frame_set(FRAME_START)
    action.use_fake_user = True
    return action


def configure_camera(scene: bpy.types.Scene, mesh_objects: list[bpy.types.Object]) -> None:
    minimum, maximum = bounds(mesh_objects)
    target = Vector(((minimum.x + maximum.x) * 0.5, -0.03, (minimum.z + maximum.z) * 0.5))
    height = maximum.z - minimum.z
    camera_data = bpy.data.cameras.new("StandardAnimeWalkCameraData")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = max(2.05, height * 1.18)
    camera = bpy.data.objects.new("StandardAnimeWalkCamera", camera_data)
    scene.collection.objects.link(camera)
    camera.location = (0.0, -5.0, target.z)
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    scene.render.resolution_x = 512
    scene.render.resolution_y = 768
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.frame_start = FRAME_START
    scene.frame_end = FRAME_END
    scene.render.fps = 24


def export_walk_glb(objects: list[bpy.types.Object]) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        if obj.type in {"MESH", "ARMATURE"} and obj.name in {"Body", "Face", "Armature"}:
            obj.hide_viewport = False
            obj.hide_render = False
            obj.select_set(True)
    selected = [obj for obj in bpy.context.selected_objects if obj.type in {"MESH", "ARMATURE"}]
    bpy.context.view_layer.objects.active = next(obj for obj in selected if obj.type == "ARMATURE")
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_GLB,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_frame_range=True,
        export_frame_step=1,
        export_force_sampling=True,
        export_skins=True,
    )


def main() -> None:
    if not os.path.exists(INPUT_BLEND):
        raise FileNotFoundError(INPUT_BLEND)
    os.makedirs(FRAME_DIR, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=INPUT_BLEND)
    scene = bpy.context.scene
    armature = next(obj for obj in scene.objects if obj.type == "ARMATURE")
    meshes = [
        obj for obj in scene.objects if obj.type == "MESH" and obj.name in {"Body", "Face"}
    ]
    if len(meshes) != 2:
        raise RuntimeError(f"Expected Body and Face meshes, found {[obj.name for obj in meshes]}")
    action = prepare_action(armature)
    configure_camera(scene, meshes)
    for frame in range(FRAME_START, FRAME_END):
        scene.frame_set(frame)
        scene.render.filepath = os.path.join(FRAME_DIR, f"frame_{frame - FRAME_START:03d}.png")
        bpy.ops.render.render(write_still=True)
    export_walk_glb([armature, *meshes])
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND)
    print(
        "WORLDGOING_STANDARD_ANIME_WALK_BUILD_PASS "
        f"frames={FRAME_END - FRAME_START} action={action.name} "
        f"blend={OUTPUT_BLEND} glb={OUTPUT_GLB}"
    )


if __name__ == "__main__":
    main()
