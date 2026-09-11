"""Build the modular 3D Horse Pack for Worldgoing from Horse.blend."""

import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector, Matrix, Euler, Quaternion

PROJECT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SOURCE_HORSE_BLEND = os.path.join(PROJECT_DIR, "assets", "3D", "Horse.blend")
OUTPUT_DIR = os.path.join(PROJECT_DIR, "assets", "mounts", "horse")
OUTPUT_BLEND = os.path.join(OUTPUT_DIR, "standard_horse_pack.blend")
OUTPUT_GLB = os.path.join(OUTPUT_DIR, "standard_horse_pack.glb")
OUTPUT_METADATA = os.path.join(OUTPUT_DIR, "standard_horse_pack.json")
PREVIEW_DIR = os.path.join(PROJECT_DIR, ".visual_captures", "standard_horse_pack", "blender")

HORSE_SCALE = 0.40
Z_GROUND_OFFSET = 0.81288 # Shift up so rest hoof is precisely at Z=0.0


def clear_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for datablocks in (
        bpy.data.objects,
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.materials,
        bpy.data.actions,
        bpy.data.armatures,
    ):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def component_props(obj: bpy.types.Object, slot: str, visual_id: str) -> None:
    obj["worldgoing_component_slot"] = slot
    obj["worldgoing_visual_id"] = visual_id


def material(name: str, color: tuple[float, float, float], metallic: float = 0.0, roughness: float = 0.78) -> bpy.types.Material:
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputMaterial")
    bsdf = nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


def add_armature_skin(obj: bpy.types.Object, armature: bpy.types.Object, primary_bone: str, weight: float = 1.0) -> None:
    vg = obj.vertex_groups.get(primary_bone) or obj.vertex_groups.new(name=primary_bone)
    indices = [v.index for v in obj.data.vertices]
    vg.add(indices, weight, 'REPLACE')
    mod = obj.modifiers.new(name="ArmatureModifier", type='ARMATURE')
    mod.object = armature


def mesh_object(
    name: str,
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    mat: bpy.types.Material,
    armature: bpy.types.Object,
    bone_name: str,
    slot: str,
    visual_id: str,
) -> bpy.types.Object:
    me = bpy.data.meshes.new(name + "Mesh")
    me.from_pydata(vertices, [], faces)
    me.update()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(mat)
    for p in obj.data.polygons:
        p.use_smooth = True
    component_props(obj, slot, visual_id)
    add_armature_skin(obj, armature, bone_name)
    return obj


def create_saddle_mesh(armature: bpy.types.Object, leather_mat: bpy.types.Material, pad_mat: bpy.types.Material, gold_mat: bpy.types.Material) -> list[bpy.types.Object]:
    """Create authentic 3D equestrian saddle with pommel, cantle, draping flaps, pad, stirrups, and reins."""
    objs = []

    # 1. Saddle Pad (汗墊) under the saddle
    pad_bm = bmesh.new()
    pad_ys = [-0.30, -0.20, -0.10, 0.0, 0.10, 0.20, 0.30]
    pad_cols_u = [-1.0, -0.7, -0.35, 0.0, 0.35, 0.7, 1.0]
    pad_grid = []
    for y in pad_ys:
        row = []
        spine_z = 1.485 + 0.03 * ((y - 0.0) / 0.30) ** 2 if y > 0 else 1.485 + 0.04 * (abs(y) / 0.30)
        for u in pad_cols_u:
            abs_u = abs(u)
            sign_u = 1.0 if u >= 0 else -1.0
            if abs_u <= 0.35:
                x = (abs_u / 0.35 * 0.15) * sign_u
                z = spine_z + 0.005 - 0.02 * (abs_u / 0.35) ** 2
            elif abs_u <= 0.7:
                t = (abs_u - 0.35) / 0.35
                x = (0.15 + t * 0.13) * sign_u
                z = spine_z - 0.15 * t
            else:
                t = (abs_u - 0.7) / 0.3
                x = (0.28 + t * 0.05) * sign_u
                z = spine_z - 0.15 - 0.18 * t
            v = pad_bm.verts.new((x, y, z))
            row.append(v)
        pad_grid.append(row)

    pad_bm.verts.ensure_lookup_table()
    for j in range(len(pad_ys) - 1):
        for i in range(len(pad_cols_u) - 1):
            pad_bm.faces.new((
                pad_grid[j][i],
                pad_grid[j][i + 1],
                pad_grid[j + 1][i + 1],
                pad_grid[j + 1][i]
            ))

    pad_me = bpy.data.meshes.new("Mount_Saddle_01_PadMesh")
    pad_bm.to_mesh(pad_me)
    pad_bm.free()
    pad_me.update()
    pad_obj = bpy.data.objects.new("Mount_Saddle_01_Pad", pad_me)
    bpy.context.scene.collection.objects.link(pad_obj)
    pad_obj.data.materials.append(pad_mat)
    for p in pad_obj.data.polygons:
        p.use_smooth = True
    component_props(pad_obj, "saddle", "saddle_standard_01")
    add_armature_skin(pad_obj, armature, "waste")
    pad_solid = pad_obj.modifiers.new("PadThickness", "SOLIDIFY")
    pad_solid.thickness = 0.014
    pad_solid.offset = -0.5
    objs.append(pad_obj)

    # 2. 3D Saddle (Seat + Pommel + Cantle + Flaps / 鞍翼)
    saddle_bm = bmesh.new()
    saddle_ys = [-0.24, -0.18, -0.12, -0.06, 0.0, 0.06, 0.12, 0.18, 0.24]
    cols_u = [-1.0, -0.75, -0.45, -0.20, 0.0, 0.20, 0.45, 0.75, 1.0]

    saddle_grid = []
    for y in saddle_ys:
        row = []
        spine_z = 1.495 + 0.03 * ((y - 0.0) / 0.24) ** 2 if y > 0 else 1.495 + 0.04 * (abs(y) / 0.24)

        if y <= -0.12:  # Pommel arch
            t_p = (y - (-0.12)) / (-0.12)
            seat_rise = 0.085 * t_p
        elif y >= 0.06:  # Cantle arch
            t_c = (y - 0.06) / 0.18
            seat_rise = 0.13 * (t_c ** 1.5)
        else:
            seat_rise = 0.0

        for u in cols_u:
            abs_u = abs(u)
            sign_u = 1.0 if u >= 0 else -1.0

            if abs_u <= 0.45:
                # Dished seat center
                w_seat = 0.12 + 0.05 * max(0.0, (y - 0.0) / 0.24) + 0.02 * max(0.0, (-y - 0.0) / 0.24)
                x = abs_u / 0.45 * w_seat * sign_u
                dish = 0.03 * (abs_u / 0.45) ** 2 if seat_rise < 0.08 else 0.01
                z = spine_z + seat_rise + dish + 0.025
            elif abs_u <= 0.75:
                # Skirt slope
                w_mid = 0.24 + 0.03 * max(0.0, (-y) / 0.24)
                t_flap = (abs_u - 0.45) / 0.30
                x = (0.14 + t_flap * (w_mid - 0.14)) * sign_u
                z = spine_z + seat_rise * (1.0 - t_flap) - 0.10 * t_flap + 0.02
            else:
                # Flap (鞍翼) hanging down the horse flank
                t_bot = (abs_u - 0.75) / 0.25
                w_bot = 0.30 + 0.025 * max(0.0, (-y) / 0.24)
                knee_bulge = 0.02 if (y < -0.08 and t_bot > 0.4) else 0.0
                x = (w_bot + knee_bulge) * sign_u
                flap_trim = 0.05 * ((y - 0.0) / 0.24) ** 2
                z = 1.39 - 0.16 * t_bot + flap_trim + 0.02

            v = saddle_bm.verts.new((x, y, z))
            row.append(v)
        saddle_grid.append(row)

    saddle_bm.verts.ensure_lookup_table()
    for j in range(len(saddle_ys) - 1):
        for i in range(len(cols_u) - 1):
            saddle_bm.faces.new((
                saddle_grid[j][i],
                saddle_grid[j][i + 1],
                saddle_grid[j + 1][i + 1],
                saddle_grid[j + 1][i]
            ))

    seat_me = bpy.data.meshes.new("Mount_Saddle_01_SeatMesh")
    saddle_bm.to_mesh(seat_me)
    saddle_bm.free()
    seat_me.update()

    seat_obj = bpy.data.objects.new("Mount_Saddle_01_Seat", seat_me)
    bpy.context.scene.collection.objects.link(seat_obj)
    seat_obj.data.materials.append(leather_mat)
    for p in seat_obj.data.polygons:
        p.use_smooth = True
    component_props(seat_obj, "saddle", "saddle_standard_01")
    add_armature_skin(seat_obj, armature, "waste")
    seat_solid = seat_obj.modifiers.new("SeatThickness", "SOLIDIFY")
    seat_solid.thickness = 0.016
    seat_solid.offset = 0.5
    objs.append(seat_obj)

    # 3. Girth / Cinch strap (around the belly)
    girth_verts = []
    girth_faces = []
    segs = 16
    r_belly_x = 0.325
    r_belly_z = 0.35
    center_y = -0.05
    center_z = 1.20
    w = 0.05
    for i in range(segs):
        ang = math.pi * 2 * i / segs
        gx = r_belly_x * math.cos(ang)
        gz = center_z + r_belly_z * math.sin(ang)
        girth_verts.append((gx, center_y - w * 0.5, gz))
        girth_verts.append((gx, center_y + w * 0.5, gz))
    for i in range(segs):
        i0 = i * 2
        i1 = i0 + 1
        i2 = ((i + 1) % segs) * 2 + 1
        i3 = ((i + 1) % segs) * 2
        girth_faces.append((i0, i1, i2, i3))

    girth_obj = mesh_object(
        "Mount_Saddle_01_Girth", girth_verts, girth_faces, leather_mat,
        armature, "waste", "saddle", "saddle_standard_01"
    )
    objs.append(girth_obj)

    # 4. Stirrup Leathers & Iron Stirrups
    for side, s_sign in [("L", 1.0), ("R", -1.0)]:
        s_bm = bmesh.new()
        sx = 0.33 * s_sign
        # Strap hanging down along flank
        v0 = s_bm.verts.new((sx, -0.045, 1.30))
        v1 = s_bm.verts.new((sx, -0.020, 1.30))
        v2 = s_bm.verts.new((sx, -0.020, 0.88))
        v3 = s_bm.verts.new((sx, -0.045, 0.88))
        if s_sign > 0:
            s_bm.faces.new((v0, v1, v2, v3))
        else:
            s_bm.faces.new((v0, v3, v2, v1))

        # D-ring stirrup iron with tread plate
        ix = sx + 0.015 * s_sign
        t_y0 = -0.08
        t_y1 = 0.02
        t0 = s_bm.verts.new((ix - 0.025 * s_sign, t_y0, 0.86))
        t1 = s_bm.verts.new((ix + 0.025 * s_sign, t_y0, 0.86))
        t2 = s_bm.verts.new((ix + 0.025 * s_sign, t_y1, 0.86))
        t3 = s_bm.verts.new((ix - 0.025 * s_sign, t_y1, 0.86))
        s_bm.faces.new((t0, t1, t2, t3))

        a0 = s_bm.verts.new((ix, t_y0, 0.92))
        a1 = s_bm.verts.new((ix, t_y1, 0.92))
        top = s_bm.verts.new((ix, -0.03, 0.94))
        s_bm.faces.new((t0, t1, a0))
        s_bm.faces.new((t2, t3, a1))
        s_bm.faces.new((a0, top, a1))

        s_me = bpy.data.meshes.new(f"Mount_Stirrups_01_{side}Mesh")
        s_bm.to_mesh(s_me)
        s_bm.free()
        s_me.update()
        s_obj = bpy.data.objects.new(f"Mount_Stirrups_01_{side}", s_me)
        bpy.context.scene.collection.objects.link(s_obj)
        s_obj.data.materials.append(gold_mat)
        for p in s_obj.data.polygons:
            p.use_smooth = True
        component_props(s_obj, "stirrups", "stirrups_standard_01")
        add_armature_skin(s_obj, armature, "waste")
        s_solid = s_obj.modifiers.new("StirrupThickness", "SOLIDIFY")
        s_solid.thickness = 0.012
        objs.append(s_obj)

    # 5. Reins connecting into rider's fists and pommel loop
    reins_bm = bmesh.new()
    l_pts = [
        Vector((-0.08, -1.06, 1.68)), # Bit at mouth
        Vector((-0.13, -0.85, 1.73)), # Lower neck
        Vector((-0.15, -0.62, 1.76)), # Mid neck
        Vector((-0.14, -0.40, 1.76)), # Withers
        Vector((0.11, -0.23, 1.73)),  # Left fist
        Vector((0.05, -0.25, 1.65)),  # Pommel loop
        Vector((0.0, -0.27, 1.63)),   # Center rest
    ]
    r_pts = [
        Vector((0.08, -1.06, 1.68)),  # Bit at mouth
        Vector((0.13, -0.85, 1.73)),  # Lower neck
        Vector((0.15, -0.62, 1.76)),  # Mid neck
        Vector((0.14, -0.40, 1.76)),  # Withers
        Vector((-0.11, -0.23, 1.73)), # Right fist
        Vector((-0.05, -0.25, 1.65)), # Pommel loop
        Vector((0.0, -0.27, 1.63)),   # Center rest
    ]

    strap_w = 0.020
    all_reins_verts = []
    for pts, side_sign in [(l_pts, 1.0), (r_pts, -1.0)]:
        v_pairs = []
        for i, p in enumerate(pts):
            if i == 0:
                tang = (pts[1] - p).normalized()
            elif i == len(pts) - 1:
                tang = (p - pts[i - 1]).normalized()
            else:
                tang = (pts[i + 1] - pts[i - 1]).normalized()
            norm = Vector((-tang.y, tang.x, 0.0)).normalized()
            va = reins_bm.verts.new(p - norm * strap_w * 0.5)
            vb = reins_bm.verts.new(p + norm * strap_w * 0.5)
            v_pairs.append((va, vb))
            all_reins_verts.extend([va, vb])

        for i in range(len(v_pairs) - 1):
            reins_bm.faces.new((
                v_pairs[i][0],
                v_pairs[i][1],
                v_pairs[i + 1][1],
                v_pairs[i + 1][0]
            ))

    reins_me = bpy.data.meshes.new("Mount_Reins_01Mesh")
    reins_bm.to_mesh(reins_me)
    reins_bm.free()
    reins_me.update()

    reins_obj = bpy.data.objects.new("Mount_Reins_01", reins_me)
    bpy.context.scene.collection.objects.link(reins_obj)
    reins_obj.data.materials.append(leather_mat)
    for p in reins_obj.data.polygons:
        p.use_smooth = True
    component_props(reins_obj, "reins", "reins_standard_01")
    add_armature_skin(reins_obj, armature, "head")

    # Vertex skinning: head (mouth bit), neck, waste (withers & fists)
    # Each side has 7 stations * 2 verts = 14 verts. Total 28 verts.
    # Left side: verts 0..13. Right side: verts 14..27.
    # Bit: stations 0 (verts 0,1, 14,15) -> head
    # Neck: stations 1,2 (verts 2..5, 16..19) -> neck
    # Rear/fists/loop: stations 3,4,5,6 (verts 6..13, 20..27) -> waste
    vg_head = reins_obj.vertex_groups.get("head")
    if vg_head:
        vg_head.remove(list(range(28)))
        vg_head.add([0, 1, 14, 15], 1.0, 'REPLACE')
    vg_neck = reins_obj.vertex_groups.new(name="neck")
    vg_neck.add([2, 3, 4, 5, 16, 17, 18, 19], 1.0, 'REPLACE')
    vg_waste = reins_obj.vertex_groups.new(name="waste")
    vg_waste.add(list(range(6, 14)) + list(range(20, 28)), 1.0, 'REPLACE')

    reins_solid = reins_obj.modifiers.new("ReinThickness", "SOLIDIFY")
    reins_solid.thickness = 0.008
    objs.append(reins_obj)

    return objs


def build_standard_horse_pack() -> None:
    print(f"Building standard horse pack from {SOURCE_HORSE_BLEND}...")
    clear_scene()
    
    # 1. Append horse data
    with bpy.data.libraries.load(SOURCE_HORSE_BLEND) as (data_from, data_to):
        data_to.objects = [name for name in data_from.objects if name in [
            'Armature', 'Retopo_Icosphere.003', 'Retopo_Icosphere.004', 'Retopo_Icosphere.005', 'Sphere.002'
        ]]
        data_to.actions = [name for name in data_from.actions if name == 'ArmatureAction']

    for obj in data_to.objects:
        bpy.context.scene.collection.objects.link(obj)

    armature = bpy.data.objects.get("Armature")
    armature.name = "StandardHorseArmature"
    
    body_obj = bpy.data.objects.get("Retopo_Icosphere.003")
    body_obj.name = "Horse_Body_01"
    component_props(body_obj, "mount_body", "horse_bay")

    mane_obj = bpy.data.objects.get("Retopo_Icosphere.004")
    mane_obj.name = "Horse_Mane_01"
    component_props(mane_obj, "mount_mane", "mane_dark")

    tail_obj = bpy.data.objects.get("Retopo_Icosphere.005")
    tail_obj.name = "Horse_Tail_01"
    component_props(tail_obj, "mount_tail", "tail_dark")

    eye_obj = bpy.data.objects.get("Sphere.002")
    eye_obj.name = "Horse_Eye_01"
    component_props(eye_obj, "mount_eye", "eye_standard")

    # 2. Scale and ground alignment
    bpy.context.view_layer.objects.active = armature
    armature.location = (0.0, 0.0, Z_GROUND_OFFSET)
    armature.scale = (HORSE_SCALE, HORSE_SCALE, HORSE_SCALE)
    bpy.ops.object.select_all(action='DESELECT')
    armature.select_set(True)
    for child in armature.children:
        child.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # 3. Add Socket_Rider bone in Edit Mode
    bpy.context.view_layer.objects.active = armature
    bpy.ops.object.mode_set(mode='EDIT')
    edit_bones = armature.data.edit_bones
    
    socket_bone = edit_bones.new("Socket_Rider")
    socket_bone.head = (0.0, -0.04, 1.54)
    socket_bone.tail = (0.0, -0.04, 1.70)
    waste_bone = edit_bones.get("waste")
    if waste_bone:
        socket_bone.parent = waste_bone
        socket_bone.use_connect = False
    
    bpy.ops.object.mode_set(mode='OBJECT')

    # 4. Materials
    mat_bay = material("Horse_Coat_Bay", (0.36, 0.18, 0.10), roughness=0.75)
    mat_chestnut = material("Horse_Coat_Chestnut", (0.45, 0.22, 0.11), roughness=0.75)
    mat_black = material("Horse_Coat_Black", (0.08, 0.08, 0.09), roughness=0.70)
    mat_white = material("Horse_Coat_White", (0.86, 0.85, 0.82), roughness=0.80)

    mat_mane_dark = material("Horse_Mane_Dark", (0.07, 0.05, 0.05), roughness=0.85)
    mat_eye = material("Horse_Eye", (0.03, 0.03, 0.04), metallic=0.2, roughness=0.1)

    mat_saddle_leather = material("Mount_Leather_01", (0.22, 0.12, 0.07), roughness=0.65)
    mat_saddle_pad = material("Mount_Pad_Cloth_01", (0.16, 0.24, 0.40), roughness=0.85)
    mat_gold = material("Mount_Hardware_Gold_01", (0.82, 0.68, 0.22), metallic=0.85, roughness=0.35)

    # Assign default materials
    body_obj.data.materials.clear()
    body_obj.data.materials.append(mat_bay)

    mane_obj.data.materials.clear()
    mane_obj.data.materials.append(mat_mane_dark)

    tail_obj.data.materials.clear()
    tail_obj.data.materials.append(mat_mane_dark)

    eye_obj.data.materials.clear()
    eye_obj.data.materials.append(mat_eye)

    # 5. Build Modular Tack / Saddlery
    tack_objs = create_saddle_mesh(armature, mat_saddle_leather, mat_saddle_pad, mat_gold)
    for tobj in tack_objs:
        tobj.parent = armature

    # 6. Prepare Actions
    raw_walk_act = bpy.data.actions.get("ArmatureAction")

    LEG_BONES = {
        "bicept.L", "bicept.R", "forearm.L", "forearm.R", "wrist.L", "wrist.R", "hand.L", "hand.R",
        "thigh.L", "thigh.R", "shin.L", "shin.R", "ankle.L", "ankle.R", "foot.L", "foot.R",
    }

    def resample_stride_action(source_act, action_name, duration_frames, stride_scale=1.0):
        act = bpy.data.actions.get(action_name) or bpy.data.actions.new(action_name)
        armature.animation_data_create()
        armature.animation_data.action = act
        act.fcurves.clear()
        if source_act:
            source_start = source_act.frame_range[0]
            source_end = source_act.frame_range[1]
            source_span = max(1.0, source_end - source_start)
            for fc in source_act.fcurves:
                new_fc = act.fcurves.new(data_path=fc.data_path, index=fc.array_index)
                is_leg_qx = stride_scale != 1.0 and any(b in fc.data_path for b in LEG_BONES) and "rotation_quaternion" in fc.data_path and fc.array_index == 1
                mean_val = (sum(kp.co.y for kp in fc.keyframe_points) / len(fc.keyframe_points)) if is_leg_qx else 0.0
                for kp in fc.keyframe_points:
                    t_norm = (kp.co.x - source_start) / source_span
                    new_frame = t_norm * duration_frames
                    val = kp.co.y
                    if is_leg_qx:
                        val = mean_val + stride_scale * (val - mean_val)
                    new_fc.keyframe_points.insert(new_frame, val)
                for kp in new_fc.keyframe_points:
                    kp.interpolation = 'BEZIER'
        act.use_fake_user = True
        return act

    # horse_walk: The 24-frame (1.00s) grounded walk stride is the standard walk speed.
    walk_act = resample_stride_action(raw_walk_act, "horse_walk", 24.0, stride_scale=1.0)

    # horse_run: 8-frame (0.333s) 10x speed stride with amplified leg reach (stride_scale=1.65, +55% span).
    run_act = resample_stride_action(raw_walk_act, "horse_run", 8.0, stride_scale=1.65)

    idle_act = bpy.data.actions.get("horse_idle") or bpy.data.actions.new("horse_idle")
    armature.animation_data_create()
    armature.animation_data.action = idle_act
    
    pb_chest = armature.pose.bones.get("chest")
    pb_waste = armature.pose.bones.get("waste")
    pb_neck = armature.pose.bones.get("neck")
    pb_tail = armature.pose.bones.get("tail1")
    
    for f in [1, 30, 60]:
        t = (f - 1) / 59.0 * math.tau
        pitch = math.sin(t) * 0.02
        if pb_chest:
            pb_chest.rotation_mode = 'QUATERNION'
            pb_chest.rotation_quaternion = Euler((pitch, 0.0, 0.0), 'XYZ').to_quaternion()
            pb_chest.keyframe_insert(data_path="rotation_quaternion", frame=f)
        if pb_neck:
            pb_neck.rotation_mode = 'QUATERNION'
            pb_neck.rotation_quaternion = Euler((-pitch * 0.8, 0.0, 0.0), 'XYZ').to_quaternion()
            pb_neck.keyframe_insert(data_path="rotation_quaternion", frame=f)
        if pb_tail:
            tail_sway = math.cos(t) * 0.06
            pb_tail.rotation_mode = 'QUATERNION'
            pb_tail.rotation_quaternion = Euler((0.0, tail_sway, 0.0), 'XYZ').to_quaternion()
            pb_tail.keyframe_insert(data_path="rotation_quaternion", frame=f)
    idle_act.use_fake_user = True

    # Ensure all actions have fake user and clean animation data
    armature.animation_data_create()
    while armature.animation_data.nla_tracks:
        armature.animation_data.nla_tracks.remove(armature.animation_data.nla_tracks[0])

    for act in [idle_act, walk_act, run_act]:
        if act:
            act.use_fake_user = True

    armature.animation_data.action = idle_act

    # 7. Metadata Manifest
    from repair_horse_audit import apply_repairs
    repaired_parts = [obj for obj in bpy.data.objects if obj.type == 'MESH']
    apply_repairs(armature, repaired_parts, sys.modules[__name__])
    from ensure_morph_uv import ensure_blender_morph_uv
    ensure_blender_morph_uv(repaired_parts)
    armature.animation_data.action = idle_act
    metadata = {
        "asset_name": "standard_horse_pack",
        "scale_applied": HORSE_SCALE,
        "socket_rider": "Socket_Rider",
        "actions": ["horse_idle", "horse_walk", "horse_run"],
        "parts": [
            {"slot": "mount_body", "object": body_obj.name, "visual_id": "horse_bay"},
            {"slot": "mount_mane", "object": mane_obj.name, "visual_id": "mane_dark"},
            {"slot": "mount_tail", "object": tail_obj.name, "visual_id": "tail_dark"},
            {"slot": "mount_eye", "object": eye_obj.name, "visual_id": "eye_standard"},
            {"slot": "mount_saddle", "objects": ["Mount_Saddle_01_Pad", "Mount_Saddle_01_Seat", "Mount_Saddle_01_Girth"], "visual_id": "saddle_standard_01"},
            {"slot": "mount_stirrups", "objects": ["Mount_Stirrups_01_L", "Mount_Stirrups_01_R"], "visual_id": "stirrups_standard_01"},
            {"slot": "mount_reins", "objects": ["Mount_Reins_01"], "visual_id": "reins_standard_01"},
        ],
        "coat_materials": ["Horse_Coat_Bay", "Horse_Coat_Chestnut", "Horse_Coat_Black", "Horse_Coat_White"],
    }

    metadata['parts'] = [{'slot': obj.get('worldgoing_component_slot', 'mount_detail'),
                          'object': obj.name, 'visual_id': obj.get('worldgoing_visual_id', '')}
                         for obj in repaired_parts]
    
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with open(OUTPUT_METADATA, "w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2, ensure_ascii=False)
    print(f"Wrote metadata to {OUTPUT_METADATA}")

    # 8. Save Blend File
    bpy.ops.wm.save_as_mainfile(filepath=OUTPUT_BLEND)
    print(f"Saved blend file to {OUTPUT_BLEND}")

    # 9. Export GLB with ACTIONS mode
    bpy.ops.export_scene.gltf(
        filepath=OUTPUT_GLB,
        export_format='GLB',
        use_selection=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_frame_range=False,
        export_current_frame=False,
        export_skins=True,
        export_morph=True,
        export_materials='EXPORT',
    )
    print(f"Exported GLB to {OUTPUT_GLB}")
    print("WORLDGOING_STANDARD_HORSE_PACK_BUILD_PASS")


if __name__ == "__main__":
    build_standard_horse_pack()
    bpy.ops.wm.quit_blender()
