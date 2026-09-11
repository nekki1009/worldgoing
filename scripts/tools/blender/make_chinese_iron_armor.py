"""Build authentic Chinese Iron Armor (Armor_Iron_01 / 中式鐵甲) matching reference sheet.

Components:
1. Armor_Iron_01_Underlayer_Pants: Dark fitted trousers extracted from source body (100% skinning weights)
2. Armor_Iron_01_UnderTunic: Dark fitted inner tunic extracted from source body (100% skinning weights)
3. Armor_Iron_01_InnerCollar: Dark crossover collar (交領深衣) exposed at the neckline
4. Armor_Iron_01_Cuirass_Front: Heavy contoured dark iron breastplate with anatomical pectoral swell and gold collar rim
5. Armor_Iron_01_ChestEmblem: 3D sculpted ferocious beast / Taotie mask (饕餮/辟邪獸面) on upper chest
6. Armor_Iron_01_ChestMotif_L & _R: Symmetrical sculpted golden cloud & dragon filigree reliefs (祥雲紋浮雕)
7. Armor_Iron_01_Cuirass_Back: Contoured dark iron backplate with vertical spine ridge & gold shoulder trim
8. Armor_Iron_01_Pauldron_Beast_L & _R: 3D sculpted cast bronze dragon/lion head shoulder caps (肩頭吞口)
9. Armor_Iron_01_Pauldron_Plates_L & _R: 3-tier articulated shingled lamellar plates with gold trim & rivets
10. Armor_Iron_01_Pauldron_Tassels_L & _R: Crimson silk cord ties and hanging tassels on pauldrons
11. Armor_Iron_01_Bracer_L & _R: Cylindrical dark iron forearm bracers with raised golden coiled dragon/cloud relief
12. Armor_Iron_01_Bracer_Straps_L & _R: Leather forearm straps and bronze roller buckles
13. Armor_Iron_01_WaistGirdle: Broad dark leather waist girdle wrapped around hips
14. Armor_Iron_01_BeltBuckle: Large ornate circular bronze buckle with embossed beast motif
15. Armor_Iron_01_BeltTassels: Red braided silk cord loops & dual hanging tassels
16. Armor_Iron_01_Tasset_Front: Multi-tier shingled geometric lamellar front apron (蔽膝) with wide gold cloud hem
17. Armor_Iron_01_Tasset_Side_L & _R: Shingled geometric lamellar side skirts (胯甲) with wide gold cloud hem
18. Armor_Iron_01_Tasset_Rear: Shingled geometric lamellar rear skirt (後裙甲) split for riding
"""

import math
import bmesh
import bpy
from mathutils import Vector, Matrix


def get_material(
    name: str,
    color: tuple[float, float, float],
    metallic: float = 0.0,
    roughness: float = 0.78,
) -> bpy.types.Material:
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name=name)
        mat.use_nodes = True
        nodes = mat.node_tree.nodes
        bsdf = nodes.get("Principled BSDF")
        if bsdf is None:
            bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
        bsdf.inputs["Base Color"].default_value = (*color, 1.0)
        bsdf.inputs["Roughness"].default_value = roughness
        if "Metallic" in bsdf.inputs:
            bsdf.inputs["Metallic"].default_value = metallic
    return mat


def add_brass_rivet(
    bm: bmesh.types.BMesh,
    center: Vector,
    normal: Vector,
    radius: float = 0.0034,
    depth: float = 0.0026,
    n_segs: int = 8,
):
    z_axis = normal.normalized()
    up = Vector((0, 0, 1)) if abs(z_axis.z) < 0.9 else Vector((1, 0, 0))
    x_axis = z_axis.cross(up).normalized()
    y_axis = z_axis.cross(x_axis).normalized()

    base_ring = []
    mid_ring = []
    for s in range(n_segs):
        a = s * 2.0 * math.pi / n_segs
        cos_a = math.cos(a)
        sin_a = math.sin(a)
        r_vec = x_axis * cos_a + y_axis * sin_a
        base_ring.append(bm.verts.new(center + r_vec * (radius * 1.15)))
        mid_ring.append(bm.verts.new(center + r_vec * radius + z_axis * (depth * 0.48)))
    apex = bm.verts.new(center + z_axis * depth)

    for s in range(n_segs):
        s_next = (s + 1) % n_segs
        bm.faces.new([base_ring[s], base_ring[s_next], mid_ring[s_next], mid_ring[s]])
        bm.faces.new([mid_ring[s], mid_ring[s_next], apex])


def add_tassel(
    bm: bmesh.types.BMesh,
    knot_center: Vector,
    hang_dir: Vector = Vector((0, 0, -1)),
    cap_radius: float = 0.0042,
    cap_height: float = 0.0075,
    tassel_len: float = 0.0450,
    flare_radius: float = 0.0105,
    n_segs: int = 8,
):
    """Generates a traditional Chinese knot cap and flared hanging silk tassel fringe."""
    z_axis = hang_dir.normalized()
    up = Vector((0, 1, 0)) if abs(z_axis.x) > 0.7 else Vector((1, 0, 0))
    x_axis = z_axis.cross(up).normalized()
    y_axis = z_axis.cross(x_axis).normalized()

    mid_ring = []
    bot_ring = []
    fringe_ring = []

    p_top = knot_center
    p_mid = knot_center + z_axis * (cap_height * 0.5)
    p_bot = knot_center + z_axis * cap_height
    p_tip = knot_center + z_axis * (cap_height + tassel_len)

    top_v = bm.verts.new(p_top)
    tip_v = bm.verts.new(p_tip)

    for s in range(n_segs):
        a = s * 2.0 * math.pi / n_segs
        r_vec = x_axis * math.cos(a) + y_axis * math.sin(a)
        mid_ring.append(bm.verts.new(p_mid + r_vec * cap_radius))
        bot_ring.append(bm.verts.new(p_bot + r_vec * (cap_radius * 0.85)))
        fringe_ring.append(bm.verts.new(p_tip + r_vec * flare_radius))

    for s in range(n_segs):
        s_next = (s + 1) % n_segs
        bm.faces.new([top_v, mid_ring[s], mid_ring[s_next]])
        bm.faces.new([mid_ring[s], bot_ring[s], bot_ring[s_next], mid_ring[s_next]])
        bm.faces.new([bot_ring[s], fringe_ring[s], fringe_ring[s_next], bot_ring[s_next]])
        bm.faces.new([fringe_ring[s], tip_v, fringe_ring[s_next]])


def add_beast_face(
    bm: bmesh.types.BMesh,
    center: Vector,
    forward: Vector,
    up: Vector,
    scale: float = 0.045,
):
    """3D sculpted ferocious beast / lion / taotie mask boss with majestic proportions."""
    n_fwd = forward.normalized()
    n_up = up.normalized()
    n_right = n_fwd.cross(n_up).normalized()

    def tr_e(x: float, y: float, z: float) -> Vector:
        return center + n_right * (x * scale) + n_up * (y * scale) + n_fwd * (z * scale)

    # 1. Brow, Crown & Forehead Crest
    c_top = bm.verts.new(tr_e(0.0, 0.95, 0.38))
    c_mid = bm.verts.new(tr_e(0.0, 0.50, 0.55))
    c_bot = bm.verts.new(tr_e(0.0, 0.18, 0.60))

    c_l_mid = bm.verts.new(tr_e(-0.48, 0.48, 0.38))
    c_r_mid = bm.verts.new(tr_e(0.48, 0.48, 0.38))
    c_l_top = bm.verts.new(tr_e(-0.32, 0.88, 0.28))
    c_r_top = bm.verts.new(tr_e(0.32, 0.88, 0.28))

    bm.faces.new([c_top, c_r_top, c_r_mid, c_mid])
    bm.faces.new([c_top, c_mid, c_l_mid, c_l_top])

    # 2. Dual Curved Horns (祥雲雙角)
    for s_sign in [-1.0, 1.0]:
        sx = s_sign
        h0 = bm.verts.new(tr_e(sx * 0.28, 0.75, 0.22))
        h1 = bm.verts.new(tr_e(sx * 0.60, 1.10, 0.28))
        h2 = bm.verts.new(tr_e(sx * 0.95, 1.45, 0.32))
        h3 = bm.verts.new(tr_e(sx * 1.25, 1.65, 0.22))

        h0_in = bm.verts.new(tr_e(sx * 0.16, 0.82, 0.16))
        h1_in = bm.verts.new(tr_e(sx * 0.42, 1.15, 0.22))
        h2_in = bm.verts.new(tr_e(sx * 0.70, 1.45, 0.26))
        h3_in = bm.verts.new(tr_e(sx * 0.98, 1.58, 0.18))

        if s_sign == 1.0:
            bm.faces.new([h0, h1, h1_in, h0_in])
            bm.faces.new([h1, h2, h2_in, h1_in])
            bm.faces.new([h2, h3, h3_in, h2_in])
        else:
            bm.faces.new([h0, h0_in, h1_in, h1])
            bm.faces.new([h1, h1_in, h2_in, h2])
            bm.faces.new([h2, h2_in, h3_in, h3])

    # 3. Bulging Fierce Eyes & Eyebrow Arches
    for s_sign in [-1.0, 1.0]:
        sx = s_sign
        eye_c = tr_e(sx * 0.50, 0.22, 0.42)
        norm_eye = (n_fwd * 0.82 + n_right * (sx * 0.45) + n_up * 0.28).normalized()
        add_brass_rivet(bm, eye_c, norm_eye, radius=scale * 0.24, depth=scale * 0.18, n_segs=8)

        br0 = bm.verts.new(tr_e(sx * 0.24, 0.40, 0.42))
        br1 = bm.verts.new(tr_e(sx * 0.52, 0.48, 0.50))
        br2 = bm.verts.new(tr_e(sx * 0.82, 0.35, 0.38))
        br0_d = bm.verts.new(tr_e(sx * 0.24, 0.30, 0.38))
        br1_d = bm.verts.new(tr_e(sx * 0.52, 0.35, 0.44))
        br2_d = bm.verts.new(tr_e(sx * 0.82, 0.24, 0.32))
        if s_sign == 1.0:
            bm.faces.new([br0, br1, br1_d, br0_d])
            bm.faces.new([br1, br2, br2_d, br1_d])
        else:
            bm.faces.new([br0, br0_d, br1_d, br1])
            bm.faces.new([br1, br1_d, br2_d, br2])

    # 4. Broad Lion Snout & Nostrils
    nose_tip = bm.verts.new(tr_e(0.0, -0.16, 0.70))
    nose_l = bm.verts.new(tr_e(-0.32, -0.20, 0.58))
    nose_r = bm.verts.new(tr_e(0.32, -0.20, 0.58))

    bm.faces.new([c_bot, nose_r, nose_tip])
    bm.faces.new([c_bot, nose_tip, nose_l])
    bm.faces.new([c_bot, c_r_mid, nose_r])
    bm.faces.new([c_bot, nose_l, c_l_mid])

    # 5. Snarling Mouth & Fangs
    lip_c = bm.verts.new(tr_e(0.0, -0.45, 0.54))
    lip_l = bm.verts.new(tr_e(-0.42, -0.45, 0.48))
    lip_r = bm.verts.new(tr_e(0.42, -0.45, 0.48))
    lip_l_wide = bm.verts.new(tr_e(-0.80, -0.48, 0.34))
    lip_r_wide = bm.verts.new(tr_e(0.80, -0.48, 0.34))

    bm.faces.new([nose_tip, nose_r, lip_r, lip_c])
    bm.faces.new([nose_tip, lip_c, lip_l, nose_l])
    bm.faces.new([nose_r, lip_r_wide, lip_r])
    bm.faces.new([nose_l, lip_l, lip_l_wide])

    fang_l = bm.verts.new(tr_e(-0.42, -0.85, 0.42))
    fang_r = bm.verts.new(tr_e(0.42, -0.85, 0.42))
    bm.faces.new([lip_l, lip_l_wide, fang_l])
    bm.faces.new([lip_r, fang_r, lip_r_wide])

    tooth_c = bm.verts.new(tr_e(0.0, -0.66, 0.42))
    bm.faces.new([lip_l, lip_c, tooth_c])
    bm.faces.new([lip_c, lip_r, tooth_c])

    # 6. Flared Whisker / Jowl Flame Wings
    for s_sign in [-1.0, 1.0]:
        sx = s_sign
        w_top = bm.verts.new(tr_e(sx * 0.90, 0.22, 0.28))
        w_mid = bm.verts.new(tr_e(sx * 1.25, -0.12, 0.32))
        w_bot = bm.verts.new(tr_e(sx * 1.08, -0.60, 0.22))
        w_in_t = bm.verts.new(tr_e(sx * 0.74, 0.06, 0.22))
        w_in_b = bm.verts.new(tr_e(sx * 0.68, -0.38, 0.22))
        if s_sign == 1.0:
            bm.faces.new([w_top, w_mid, w_in_t])
            bm.faces.new([w_mid, w_in_b, w_in_t])
            bm.faces.new([w_mid, w_bot, w_in_b])
        else:
            bm.faces.new([w_top, w_in_t, w_mid])
            bm.faces.new([w_mid, w_in_t, w_in_b])
            bm.faces.new([w_mid, w_in_b, w_bot])


def add_cloud_tendril_relief(
    bm: bmesh.types.BMesh,
    origin: Vector,
    forward: Vector,
    up: Vector,
    sign: float = 1.0,
    scale: float = 0.075,
):
    """3D sculpted sweeping cloud & dragon tendril relief (祥雲紋浮雕) spreading across pectorals."""
    n_fwd = forward.normalized()
    n_up = up.normalized()
    n_right = n_fwd.cross(n_up).normalized() * sign

    def tr_c(x: float, y: float, z: float) -> Vector:
        return origin + n_right * (x * scale) + n_up * (y * scale) + n_fwd * (z * scale)

    spine_pts = [
        (0.10, 0.15, 0.05),
        (0.35, 0.30, 0.06),
        (0.65, 0.45, 0.07),
        (0.95, 0.48, 0.06),
        (1.25, 0.38, 0.05),
        (1.45, 0.18, 0.04),
        (1.60, -0.05, 0.03),
    ]
    curl_pts = [
        (0.40, -0.05, 0.05),
        (0.70, -0.15, 0.06),
        (0.95, -0.28, 0.05),
        (1.15, -0.45, 0.04),
    ]

    v_top = []
    v_mid = []
    v_bot = []
    for sx, sy, sz in spine_pts:
        v_top.append(bm.verts.new(tr_c(sx, sy + 0.08, sz * 0.6)))
        v_mid.append(bm.verts.new(tr_c(sx, sy, sz + 0.04)))
        v_bot.append(bm.verts.new(tr_c(sx, sy - 0.08, sz * 0.6)))

    for i in range(len(spine_pts) - 1):
        bm.faces.new([v_top[i], v_top[i + 1], v_mid[i + 1], v_mid[i]])
        bm.faces.new([v_mid[i], v_mid[i + 1], v_bot[i + 1], v_bot[i]])

    c_top = []
    c_mid = []
    c_bot = []
    for sx, sy, sz in curl_pts:
        c_top.append(bm.verts.new(tr_c(sx, sy + 0.07, sz * 0.6)))
        c_mid.append(bm.verts.new(tr_c(sx, sy, sz + 0.035)))
        c_bot.append(bm.verts.new(tr_c(sx, sy - 0.07, sz * 0.6)))

    for i in range(len(curl_pts) - 1):
        bm.faces.new([c_top[i], c_top[i + 1], c_mid[i + 1], c_mid[i]])
        bm.faces.new([c_mid[i], c_mid[i + 1], c_bot[i + 1], c_bot[i]])


def make_chinese_iron_armor(
    armature: bpy.types.Object,
    source_raw_body: bpy.types.Object = None,
    is_female: bool = False,
    create_rigid_fn=None,
) -> list[bpy.types.Object]:
    """Generates authentic Chinese Iron Armor (Armor_Iron_01 / 中式鐵甲) matching the reference sheet."""
    parts: list[bpy.types.Object] = []
    visual_id = "armor_iron_01"

    # Materials unified 100% with Chinese Iron Helmet & Boots
    mat_iron_dark = get_material("Worldgoing_Iron_Dark", (0.042, 0.045, 0.052), metallic=0.92, roughness=0.34)
    mat_gold = get_material("Worldgoing_Chinese_Gold", (0.95, 0.76, 0.22), metallic=0.96, roughness=0.20)
    mat_lamellar = get_material("Worldgoing_Iron_Lamellar", (0.048, 0.050, 0.056), metallic=0.88, roughness=0.38)
    mat_leather = get_material("Worldgoing_Leather_Dark", (0.024, 0.012, 0.005), metallic=0.0, roughness=0.52)
    mat_cloth = get_material("Worldgoing_Chinese_Cloth_Dark", (0.025, 0.025, 0.030), metallic=0.0, roughness=0.92)
    mat_cord = get_material("Worldgoing_Chinese_Cord_Red", (0.78, 0.04, 0.05), metallic=0.0, roughness=0.82)

    if create_rigid_fn is None:
        def default_create_rigid(name, bm, mat, bone, slot, vid, arm):
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
            mesh = bpy.data.meshes.new(name + "Mesh")
            bm.to_mesh(mesh)
            bm.free()
            mesh.update()
            obj = bpy.data.objects.new(name, mesh)
            bpy.context.collection.objects.link(obj)
            if mat:
                obj.data.materials.append(mat)
            for p in obj.data.polygons:
                p.use_smooth = True
            vg = obj.vertex_groups.new(name=bone)
            vg.add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
            mod = obj.modifiers.new("WorldgoingArmature", "ARMATURE")
            mod.object = arm
            obj.parent = arm
            obj.matrix_parent_inverse = arm.matrix_world.inverted()
            obj["worldgoing_character_part"] = True
            obj["worldgoing_component_slot"] = slot
            obj["worldgoing_visual_id"] = vid
            return obj
        create_rigid_fn = default_create_rigid

    def create_skinned_component(name, bm, mat, weights_dict, slot, vid, arm):
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        mesh = bpy.data.meshes.new(name + "Mesh")
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.collection.objects.link(obj)
        if mat:
            obj.data.materials.append(mat)
        for p in obj.data.polygons:
            p.use_smooth = True
        n_v = len(obj.data.vertices)
        for b_name, b_w in weights_dict.items():
            if b_w > 0.0:
                vg = obj.vertex_groups.new(name=b_name)
                vg.add(list(range(n_v)), b_w, "REPLACE")
        mod = obj.modifiers.new("WorldgoingArmature", "ARMATURE")
        mod.object = arm
        obj.parent = arm
        obj.matrix_parent_inverse = arm.matrix_world.inverted()
        obj["worldgoing_character_part"] = True
        obj["worldgoing_component_slot"] = slot
        obj["worldgoing_visual_id"] = vid
        return obj

    # Bone Positions in T-Pose
    bone_ua_l = armature.data.bones.get("J_Bip_L_UpperArm")
    bone_la_l = armature.data.bones.get("J_Bip_L_LowerArm")
    if bone_ua_l:
        ua_head_x = bone_ua_l.head_local.x
        ua_tail_x = bone_ua_l.tail_local.x
        ua_z = bone_ua_l.head_local.z
        ua_y = bone_ua_l.head_local.y
    else:
        ua_head_x = 0.147 if not is_female else 0.108
        ua_tail_x = 0.367 if not is_female else 0.327
        ua_z = 1.405 if not is_female else 1.307
        ua_y = -0.005

    if bone_la_l:
        la_head_x = bone_la_l.head_local.x
        la_tail_x = bone_la_l.tail_local.x
        la_z = bone_la_l.head_local.z
        la_y = bone_la_l.head_local.y
    else:
        la_head_x = 0.367 if not is_female else 0.327
        la_tail_x = 0.615 if not is_female else 0.541
        la_z = 1.394 if not is_female else 1.297
        la_y = -0.015

    # Torso anchors
    chest_z = 1.285 if not is_female else 1.200
    waist_z = 1.075 if not is_female else 1.015
    collar_z = 1.455 if not is_female else 1.350

    torso_rx = 0.188 if not is_female else 0.158
    torso_ry_front = 0.144 if not is_female else 0.136
    torso_ry_back = 0.132 if not is_female else 0.118

    waist_rx = 0.165 if not is_female else 0.138
    waist_ry_front = 0.130 if not is_female else 0.115
    waist_ry_back = 0.125 if not is_female else 0.110

    # =========================================================================
    # 1. Underlayer: Fitted Trousers, Inner Tunic & Crossover Collar
    # =========================================================================
    if source_raw_body is not None:
        # Trousers
        obj_pants = source_raw_body.copy()
        obj_pants.name = "Armor_Iron_01_Underlayer_Pants"
        obj_pants.data = source_raw_body.data.copy()
        obj_pants.data.name = "Armor_Iron_01_Underlayer_PantsMesh"
        bpy.context.collection.objects.link(obj_pants)
        bm_p = bmesh.new()
        bm_p.from_mesh(obj_pants.data)
        bm_p.faces.ensure_lookup_table()
        delete_f = [f for f in bm_p.faces if not (0.320 <= f.calc_center_median().z <= 1.045)]
        bmesh.ops.delete(bm_p, geom=delete_f, context="FACES")
        bmesh.ops.bisect_plane(bm_p, geom=bm_p.faces[:] + bm_p.edges[:] + bm_p.verts[:], plane_co=(0, 0, 0.330), plane_no=(0, 0, 1), clear_inner=True)
        bmesh.ops.bisect_plane(bm_p, geom=bm_p.faces[:] + bm_p.edges[:] + bm_p.verts[:], plane_co=(0, 0, 1.035), plane_no=(0, 0, -1), clear_inner=True)
        for v in bm_p.verts:
            if v.link_faces and v.normal.length > 0:
                v.co += v.normal.normalized() * 0.0035
        loose = [v for v in bm_p.verts if not v.link_faces]
        bmesh.ops.delete(bm_p, geom=loose, context="VERTS")
        bmesh.ops.recalc_face_normals(bm_p, faces=bm_p.faces)
        bm_p.to_mesh(obj_pants.data)
        bm_p.free()
        obj_pants.data.update()
        obj_pants.data.materials.clear()
        obj_pants.data.materials.append(mat_cloth)
        for p in obj_pants.data.polygons:
            p.material_index = 0
            p.use_smooth = True
        obj_pants["worldgoing_character_part"] = True
        obj_pants["worldgoing_component_slot"] = "armor"
        obj_pants["worldgoing_visual_id"] = visual_id
        parts.append(obj_pants)

        # Inner Tunic & Sleeves
        obj_tunic = source_raw_body.copy()
        obj_tunic.name = "Armor_Iron_01_UnderTunic"
        obj_tunic.data = source_raw_body.data.copy()
        obj_tunic.data.name = "Armor_Iron_01_UnderTunicMesh"
        bpy.context.collection.objects.link(obj_tunic)
        bm_t = bmesh.new()
        bm_t.from_mesh(obj_tunic.data)
        bm_t.faces.ensure_lookup_table()
        delete_t = [f for f in bm_t.faces if not (0.960 <= f.calc_center_median().z <= 1.500)]
        bmesh.ops.delete(bm_t, geom=delete_t, context="FACES")
        for v in bm_t.verts:
            if v.link_faces and v.normal.length > 0:
                v.co += v.normal.normalized() * 0.0030
        loose_t = [v for v in bm_t.verts if not v.link_faces]
        bmesh.ops.delete(bm_t, geom=loose_t, context="VERTS")
        bmesh.ops.recalc_face_normals(bm_t, faces=bm_t.faces)
        bm_t.to_mesh(obj_tunic.data)
        bm_t.free()
        obj_tunic.data.update()
        obj_tunic.data.materials.clear()
        obj_tunic.data.materials.append(mat_cloth)
        for p in obj_tunic.data.polygons:
            p.material_index = 0
            p.use_smooth = True
        obj_tunic["worldgoing_character_part"] = True
        obj_tunic["worldgoing_component_slot"] = "armor"
        obj_tunic["worldgoing_visual_id"] = visual_id
        parts.append(obj_tunic)

    # Crossover Collar (交領領口)
    bm_in_col = bmesh.new()
    col_z_top = collar_z + 0.025
    col_z_mid = collar_z - 0.020
    col_z_bot = collar_z - 0.065
    lapel_l = [
        bm_in_col.verts.new((-0.070, -0.065, col_z_top)),
        bm_in_col.verts.new((-0.045, -0.082, col_z_mid)),
        bm_in_col.verts.new(( 0.025, -0.105, col_z_bot)),
        bm_in_col.verts.new(( 0.005, -0.106, col_z_bot)),
        bm_in_col.verts.new((-0.060, -0.083, col_z_mid)),
        bm_in_col.verts.new((-0.085, -0.066, col_z_top)),
    ]
    bm_in_col.faces.new([lapel_l[0], lapel_l[1], lapel_l[4], lapel_l[5]])
    bm_in_col.faces.new([lapel_l[1], lapel_l[2], lapel_l[3], lapel_l[4]])
    lapel_r = [
        bm_in_col.verts.new(( 0.070, -0.065, col_z_top)),
        bm_in_col.verts.new(( 0.045, -0.082, col_z_mid)),
        bm_in_col.verts.new((-0.020, -0.102, col_z_bot)),
        bm_in_col.verts.new((-0.005, -0.103, col_z_bot)),
        bm_in_col.verts.new(( 0.060, -0.083, col_z_mid)),
        bm_in_col.verts.new(( 0.085, -0.066, col_z_top)),
    ]
    bm_in_col.faces.new([lapel_r[5], lapel_r[4], lapel_r[1], lapel_r[0]])
    bm_in_col.faces.new([lapel_r[4], lapel_r[3], lapel_r[2], lapel_r[1]])
    bmesh.ops.recalc_face_normals(bm_in_col, faces=bm_in_col.faces)
    bmesh.ops.solidify(bm_in_col, geom=bm_in_col.faces[:], thickness=0.0025)
    parts.append(create_rigid_fn("Armor_Iron_01_InnerCollar", bm_in_col, mat_cloth, "J_Bip_C_UpperChest", "armor", visual_id, armature))

    # =========================================================================
    # 2. Armor_Iron_01_Cuirass_Front: Heavy Contoured Dark Iron Breastplate
    # =========================================================================
    bm_cuirass = bmesh.new()
    bm_c_gold_rim = bmesh.new()
    n_c_lat = 11
    n_c_lon = 16
    cuirass_grid = []

    z_c_top = collar_z - 0.008
    z_c_bot = waist_z

    for i in range(n_c_lat):
        v = i / (n_c_lat - 1)
        pz = z_c_top - (z_c_top - z_c_bot) * v

        chest_expand = math.sin(v * math.pi * 0.72) ** 1.3
        rx = (torso_rx * (1.0 - v) + waist_rx * v) * (1.0 + 0.06 * chest_expand)
        ry = (torso_ry_front * (1.0 - v) + waist_ry_front * v) * (1.0 + 0.12 * chest_expand)

        row = []
        for j in range(n_c_lon):
            frac = (j / (n_c_lon - 1) - 0.5) * 2.0
            ang = frac * (math.pi * 0.42)
            px = math.sin(ang) * rx
            py = -math.cos(ang) * ry - 0.012

            z_mod = pz
            if i == 0:
                neck_scoop = max(0.0, 1.0 - (abs(frac) / 0.45) ** 2) * 0.035
                z_mod -= neck_scoop

            row.append(bm_cuirass.verts.new((px, py, z_mod)))
        cuirass_grid.append(row)

    for i in range(n_c_lat - 1):
        for j in range(n_c_lon - 1):
            bm_cuirass.faces.new([
                cuirass_grid[i][j],
                cuirass_grid[i + 1][j],
                cuirass_grid[i + 1][j + 1],
                cuirass_grid[i][j + 1],
            ])

    neck_rim_top = []
    neck_rim_bot = []
    for j in range(n_c_lon):
        v_pt = cuirass_grid[0][j].co
        neck_rim_top.append(bm_c_gold_rim.verts.new(v_pt + Vector((0, -0.002, 0.006))))
        neck_rim_bot.append(bm_c_gold_rim.verts.new(v_pt + Vector((0, -0.002, -0.006))))
    for j in range(n_c_lon - 1):
        bm_c_gold_rim.faces.new([neck_rim_bot[j], neck_rim_top[j], neck_rim_top[j + 1], neck_rim_bot[j + 1]])

    bmesh.ops.recalc_face_normals(bm_c_gold_rim, faces=bm_c_gold_rim.faces)
    bmesh.ops.solidify(bm_c_gold_rim, geom=bm_c_gold_rim.faces[:], thickness=0.0025)

    for i in [1, 3, 5, 7, 9]:
        v_l = cuirass_grid[i][0].co
        v_r = cuirass_grid[i][-1].co
        add_brass_rivet(bm_cuirass, v_l, Vector((-0.8, -0.6, 0.1)), radius=0.0032, depth=0.0024)
        add_brass_rivet(bm_cuirass, v_r, Vector((0.8, -0.6, 0.1)), radius=0.0032, depth=0.0024)

    bmesh.ops.recalc_face_normals(bm_cuirass, faces=bm_cuirass.faces)
    bmesh.ops.solidify(bm_cuirass, geom=bm_cuirass.faces[:], thickness=0.0045)

    weights_chest = {"J_Bip_C_Chest": 0.65, "J_Bip_C_UpperChest": 0.35}
    parts.append(create_skinned_component("Armor_Iron_01_Cuirass_Front", bm_cuirass, mat_iron_dark, weights_chest, "armor", visual_id, armature))
    parts.append(create_skinned_component("Armor_Iron_01_Cuirass_Rim", bm_c_gold_rim, mat_gold, weights_chest, "armor", visual_id, armature))

    # =========================================================================
    # 3. Armor_Iron_01_ChestEmblem: Majestic 3D Beast Head & Pectoral Cloud Motifs
    # =========================================================================
    bm_emblem = bmesh.new()
    emblem_center = Vector((0.0, -torso_ry_front * 1.14 - 0.012, chest_z + 0.038))

    add_beast_face(
        bm_emblem,
        center=emblem_center,
        forward=Vector((0.0, -0.98, 0.15)),
        up=Vector((0.0, 0.15, 0.98)),
        scale=0.065 if not is_female else 0.054,
    )
    bmesh.ops.recalc_face_normals(bm_emblem, faces=bm_emblem.faces)
    bmesh.ops.solidify(bm_emblem, geom=bm_emblem.faces[:], thickness=0.0028)
    parts.append(create_skinned_component("Armor_Iron_01_ChestEmblem", bm_emblem, mat_gold, weights_chest, "armor", visual_id, armature))

    for side, sign in (("L", 1.0), ("R", -1.0)):
        bm_motif = bmesh.new()
        motif_origin = emblem_center + Vector((sign * 0.055, 0.004, -0.010))
        add_cloud_tendril_relief(
            bm_motif,
            origin=motif_origin,
            forward=Vector((0.0, -0.96, 0.15)),
            up=Vector((0.0, 0.15, 0.98)),
            sign=sign,
            scale=0.068 if not is_female else 0.056,
        )
        bmesh.ops.recalc_face_normals(bm_motif, faces=bm_motif.faces)
        bmesh.ops.solidify(bm_motif, geom=bm_motif.faces[:], thickness=0.0026)
        parts.append(create_skinned_component(f"Armor_Iron_01_ChestMotif_{side}", bm_motif, mat_gold, weights_chest, "armor", visual_id, armature))

    # =========================================================================
    # 4. Armor_Iron_01_Cuirass_Back: Contoured Backplate with Spine Ridge & Straps
    # =========================================================================
    bm_back = bmesh.new()
    bm_b_gold = bmesh.new()
    back_grid = []

    for i in range(n_c_lat):
        v = i / (n_c_lat - 1)
        pz = z_c_top - (z_c_top - z_c_bot) * v
        rx = (torso_rx * (1.0 - v) + waist_rx * v) * 1.04
        ry = (torso_ry_back * (1.0 - v) + waist_ry_back * v) * 1.05

        row = []
        for j in range(n_c_lon):
            frac = (j / (n_c_lon - 1) - 0.5) * 2.0
            ang = math.pi + frac * (math.pi * 0.42)
            px = math.sin(ang) * rx
            py = -math.cos(ang) * ry + 0.005

            spine_lift = max(0.0, 1.0 - abs(frac) / 0.18) * 0.010
            py += spine_lift

            row.append(bm_back.verts.new((px, py, pz)))
        back_grid.append(row)

    for i in range(n_c_lat - 1):
        for j in range(n_c_lon - 1):
            bm_back.faces.new([
                back_grid[i][j],
                back_grid[i + 1][j],
                back_grid[i + 1][j + 1],
                back_grid[i][j + 1],
            ])

    for j in range(2, n_c_lon - 2):
        v_top = back_grid[1][j].co + Vector((0, 0.003, 0.005))
        v_bot = back_grid[3][j].co + Vector((0, 0.003, -0.005))
        v_top_n = back_grid[1][j + 1].co + Vector((0, 0.003, 0.005))
        v_bot_n = back_grid[3][j + 1].co + Vector((0, 0.003, -0.005))
        p0 = bm_b_gold.verts.new(v_top)
        p1 = bm_b_gold.verts.new(v_top_n)
        p2 = bm_b_gold.verts.new(v_bot_n)
        p3 = bm_b_gold.verts.new(v_bot)
        bm_b_gold.faces.new([p0, p1, p2, p3])

    bmesh.ops.recalc_face_normals(bm_b_gold, faces=bm_b_gold.faces)
    bmesh.ops.solidify(bm_b_gold, geom=bm_b_gold.faces[:], thickness=0.0026)

    bmesh.ops.recalc_face_normals(bm_back, faces=bm_back.faces)
    bmesh.ops.solidify(bm_back, geom=bm_back.faces[:], thickness=0.0042)

    weights_back = {"J_Bip_C_Chest": 0.50, "J_Bip_C_UpperChest": 0.35, "J_Bip_C_Spine": 0.15}
    parts.append(create_skinned_component("Armor_Iron_01_Cuirass_Back", bm_back, mat_iron_dark, weights_back, "armor", visual_id, armature))
    parts.append(create_skinned_component("Armor_Iron_01_BackMotif", bm_b_gold, mat_gold, weights_back, "armor", visual_id, armature))

    # =========================================================================
    # 5. Pauldrons: Modeled in T-Pose along UpperArm X-Axis
    # =========================================================================
    for side, sign in (("L", 1.0), ("R", -1.0)):
        bone_arm = f"J_Bip_{side}_UpperArm"

        # 5A. 3D Sculpted Bronze Dragon/Lion Beast Cap (肩頭吞口)
        # In T-pose, sits directly over head of UpperArm bone
        bm_p_beast = bmesh.new()
        p_cap_c = Vector((sign * (ua_head_x + 0.024), ua_y - 0.012, ua_z + 0.028))
        add_beast_face(
            bm_p_beast,
            center=p_cap_c,
            forward=Vector((sign * 0.70, -0.60, 0.35)).normalized(),
            up=Vector((sign * 0.25, 0.35, 0.90)).normalized(),
            scale=0.042 if not is_female else 0.035,
        )
        bmesh.ops.recalc_face_normals(bm_p_beast, faces=bm_p_beast.faces)
        bmesh.ops.solidify(bm_p_beast, geom=bm_p_beast.faces[:], thickness=0.0028)
        parts.append(create_rigid_fn(f"Armor_Iron_01_Pauldron_Beast_{side}", bm_p_beast, mat_gold, bone_arm, "armor", visual_id, armature))

        # 5B. 3 Articulated Curved Lamellar Tiers (披膊三層疊甲)
        # In T-pose, tiers step outwards along the X-axis from shoulder towards elbow
        bm_p_plates = bmesh.new()
        bm_p_gold = bmesh.new()

        ua_len = abs(ua_tail_x - ua_head_x)
        tier_steps = [
            (0.010, 0.075, 1.00),
            (0.060, 0.130, 1.06),
            (0.115, 0.190, 1.12),
        ]

        n_p_x = 5
        n_p_phi = 12
        r_arm_y = 0.064 if not is_female else 0.054
        r_arm_z = 0.068 if not is_female else 0.058

        for t_idx, (x_in, x_out, flare) in enumerate(tier_steps):
            ry = r_arm_y * flare
            rz = r_arm_z * flare

            t_grid = []
            for i in range(n_p_x):
                u = i / (n_p_x - 1)
                px = sign * (ua_head_x + x_in + (x_out - x_in) * u)

                row = []
                for j in range(n_p_phi):
                    # Cups top (+Z), front (-Y), and back (+Y) of the arm
                    phi = (j / (n_p_phi - 1) - 0.5) * (math.pi * 0.88)
                    py = ua_y + math.sin(phi) * ry
                    pz = ua_z + math.cos(phi) * rz
                    row.append(bm_p_plates.verts.new((px, py, pz)))
                t_grid.append(row)

            for i in range(n_p_x - 1):
                for j in range(n_p_phi - 1):
                    bm_p_plates.faces.new([
                        t_grid[i][j],
                        t_grid[i + 1][j],
                        t_grid[i + 1][j + 1],
                        t_grid[i][j + 1],
                    ])

            # Gold trim rim along the outer edge of each tier
            bot_rim_in = []
            bot_rim_out = []
            for j in range(n_p_phi):
                v_pt = t_grid[-1][j].co
                norm_out = Vector((sign * 0.9, 0.0, 0.1)).normalized()
                bot_rim_in.append(bm_p_gold.verts.new(v_pt + norm_out * 0.002))
                bot_rim_out.append(bm_p_gold.verts.new(v_pt + norm_out * 0.002 + Vector((sign * 0.008, 0, 0))))
            for j in range(n_p_phi - 1):
                bm_p_gold.faces.new([bot_rim_in[j], bot_rim_out[j], bot_rim_out[j + 1], bot_rim_in[j + 1]])

            # Rivets on tier corners
            add_brass_rivet(bm_p_plates, t_grid[1][0].co, Vector((0.0, -0.9, 0.2)), radius=0.0028, depth=0.0020)
            add_brass_rivet(bm_p_plates, t_grid[1][-1].co, Vector((0.0, 0.9, 0.2)), radius=0.0028, depth=0.0020)

        bmesh.ops.recalc_face_normals(bm_p_plates, faces=bm_p_plates.faces)
        bmesh.ops.solidify(bm_p_plates, geom=bm_p_plates.faces[:], thickness=0.0035)
        parts.append(create_rigid_fn(f"Armor_Iron_01_Pauldron_Plates_{side}", bm_p_plates, mat_lamellar, bone_arm, "armor", visual_id, armature))

        bmesh.ops.recalc_face_normals(bm_p_gold, faces=bm_p_gold.faces)
        bmesh.ops.solidify(bm_p_gold, geom=bm_p_gold.faces[:], thickness=0.0024)
        parts.append(create_rigid_fn(f"Armor_Iron_01_Pauldron_GoldRim_{side}", bm_p_gold, mat_gold, bone_arm, "armor", visual_id, armature))

        # 5C. Crimson Silk Cord & Hanging Pauldron Tassels (朱紅絲絛流蘇)
        bm_p_tassels = bmesh.new()
        knot_pt = p_cap_c + Vector((sign * 0.035, -0.045, -0.012))
        add_tassel(bm_p_tassels, knot_center=knot_pt, hang_dir=Vector((sign * 0.15, -0.10, -0.98)), tassel_len=0.055)
        bmesh.ops.recalc_face_normals(bm_p_tassels, faces=bm_p_tassels.faces)
        parts.append(create_rigid_fn(f"Armor_Iron_01_Pauldron_Tassels_{side}", bm_p_tassels, mat_cord, bone_arm, "armor", visual_id, armature))

    # =========================================================================
    # 6. Forearm Bracers: Modeled in T-Pose along LowerArm X-Axis
    # =========================================================================
    for side, sign in (("L", 1.0), ("R", -1.0)):
        bone_forearm = f"J_Bip_{side}_LowerArm"
        bm_bracer = bmesh.new()
        bm_b_relief = bmesh.new()
        bm_b_straps = bmesh.new()

        x_elbow = la_head_x + 0.018
        x_wrist = la_tail_x - 0.022
        la_len = abs(x_wrist - x_elbow)

        n_br_x = 9
        n_br_phi = 14
        r_el = 0.046 if not is_female else 0.039
        r_wr = 0.036 if not is_female else 0.030

        bracer_grid = []
        for i in range(n_br_x):
            u = i / (n_br_x - 1)
            px = sign * (x_elbow + (x_wrist - x_elbow) * u)
            r_cur = r_el * (1.0 - u) + r_wr * u

            row = []
            for j in range(n_br_phi):
                # Covers dorsal & lateral forearm: 200 deg wrap around +Z, -Y, +Y
                phi = (j / (n_br_phi - 1) - 0.5) * (math.pi * 1.10)
                py = la_y + math.sin(phi) * r_cur
                pz = la_z + math.cos(phi) * r_cur
                row.append(bm_bracer.verts.new((px, py, pz)))
            bracer_grid.append(row)

        for i in range(n_br_x - 1):
            for j in range(n_br_phi - 1):
                bm_bracer.faces.new([
                    bracer_grid[i][j],
                    bracer_grid[i + 1][j],
                    bracer_grid[i + 1][j + 1],
                    bracer_grid[i][j + 1],
                ])

        # Gold rims at elbow and wrist ends
        for row_idx in [0, -1]:
            rim_t = []
            rim_b = []
            for j in range(n_br_phi):
                v_co = bracer_grid[row_idx][j].co
                rim_t.append(bm_b_relief.verts.new(v_co + Vector((sign * 0.003, 0, 0.004))))
                rim_b.append(bm_b_relief.verts.new(v_co + Vector((sign * 0.003, 0, -0.004))))
            for j in range(n_br_phi - 1):
                bm_b_relief.faces.new([rim_b[j], rim_t[j], rim_t[j + 1], rim_b[j + 1]])

        # 3D Golden Coiled Dragon & Cloud Spine Relief down the dorsal line (+Z)
        d_top = []
        d_mid = []
        d_bot = []
        for i in range(n_br_x):
            v_c = bracer_grid[i][n_br_phi // 2].co
            d_mid.append(bm_b_relief.verts.new(v_c + Vector((0.0, 0.0, 0.008))))
            d_top.append(bm_b_relief.verts.new(v_c + Vector((0.0, -0.010, 0.003))))
            d_bot.append(bm_b_relief.verts.new(v_c + Vector((0.0, 0.010, 0.003))))

        for i in range(n_br_x - 1):
            bm_b_relief.faces.new([d_top[i], d_top[i + 1], d_mid[i + 1], d_mid[i]])
            bm_b_relief.faces.new([d_mid[i], d_mid[i + 1], d_bot[i + 1], d_bot[i]])

        bmesh.ops.recalc_face_normals(bm_b_relief, faces=bm_b_relief.faces)
        bmesh.ops.solidify(bm_b_relief, geom=bm_b_relief.faces[:], thickness=0.0024)
        parts.append(create_rigid_fn(f"Armor_Iron_01_Bracer_Relief_{side}", bm_b_relief, mat_gold, bone_forearm, "armor", visual_id, armature))

        bmesh.ops.recalc_face_normals(bm_bracer, faces=bm_bracer.faces)
        bmesh.ops.solidify(bm_bracer, geom=bm_bracer.faces[:], thickness=0.0034)
        parts.append(create_rigid_fn(f"Armor_Iron_01_Bracer_{side}", bm_bracer, mat_iron_dark, bone_forearm, "armor", visual_id, armature))

        # Two Leather Closure Straps on the inner forearm (-Z side)
        for s_u in [0.25, 0.75]:
            sx = sign * (x_elbow + (x_wrist - x_elbow) * s_u)
            r_cur = r_el * (1.0 - s_u) + r_wr * s_u
            st_pts = []
            for j in range(8):
                ang = math.pi * 0.55 + (j / 7.0) * (math.pi * 0.90)
                py = la_y + math.cos(ang) * (r_cur * 1.05)
                pz = la_z - math.sin(ang) * (r_cur * 1.05)
                st_pts.append(bm_b_straps.verts.new((sx, py, pz)))
            for j in range(7):
                v0 = st_pts[j]
                v1 = st_pts[j + 1]
                v0_t = bm_b_straps.verts.new(v0.co + Vector((sign * 0.010, 0, 0)))
                v1_t = bm_b_straps.verts.new(v1.co + Vector((sign * 0.010, 0, 0)))
                bm_b_straps.faces.new([v0, v1, v1_t, v0_t])

        bmesh.ops.recalc_face_normals(bm_b_straps, faces=bm_b_straps.faces)
        bmesh.ops.solidify(bm_b_straps, geom=bm_b_straps.faces[:], thickness=0.0022)
        parts.append(create_rigid_fn(f"Armor_Iron_01_Bracer_Straps_{side}", bm_b_straps, mat_leather, bone_forearm, "armor", visual_id, armature))

    # =========================================================================
    # 7. Waist Girdle, Circular Beast Buckle & Hanging Tassels (腰帶、獸面扣、流蘇)
    # =========================================================================
    bm_girdle = bmesh.new()
    bm_buckle = bmesh.new()
    bm_b_tassels = bmesh.new()

    z_belt_top = waist_z + 0.030
    z_belt_bot = waist_z - 0.055
    n_belt_pts = 24

    b_top = []
    b_bot = []
    for j in range(n_belt_pts):
        ang = j * 2.0 * math.pi / n_belt_pts
        px = math.sin(ang) * (waist_rx * 1.06)
        py = -math.cos(ang) * (waist_ry_front * 1.06) - 0.008
        b_top.append(bm_girdle.verts.new((px, py, z_belt_top)))
        b_bot.append(bm_girdle.verts.new((px, py, z_belt_bot)))

    for j in range(n_belt_pts):
        j_next = (j + 1) % n_belt_pts
        bm_girdle.faces.new([b_bot[j], b_top[j], b_top[j_next], b_bot[j_next]])

    bmesh.ops.recalc_face_normals(bm_girdle, faces=bm_girdle.faces)
    bmesh.ops.solidify(bm_girdle, geom=bm_girdle.faces[:], thickness=0.0040)
    parts.append(create_rigid_fn("Armor_Iron_01_WaistGirdle", bm_girdle, mat_leather, "J_Bip_C_Hips", "armor", visual_id, armature))

    # Circular Bronze Beast Buckle at front center
    z_buckle = (z_belt_top + z_belt_bot) * 0.5
    buckle_c = Vector((0.0, -waist_ry_front * 1.06 - 0.016, z_buckle))
    r_buckle = 0.040 if not is_female else 0.034

    n_b_disk = 18
    disk_rim = []
    disk_mid = []
    disk_center = bm_buckle.verts.new(buckle_c + Vector((0, -0.008, 0)))
    for j in range(n_b_disk):
        ang = j * 2.0 * math.pi / n_b_disk
        dx = math.sin(ang) * r_buckle
        dz = math.cos(ang) * r_buckle
        disk_rim.append(bm_buckle.verts.new(buckle_c + Vector((dx, -0.002, dz))))
        disk_mid.append(bm_buckle.verts.new(buckle_c + Vector((dx * 0.75, -0.006, dz * 0.75))))

    for j in range(n_b_disk):
        j_next = (j + 1) % n_b_disk
        bm_buckle.faces.new([disk_rim[j], disk_rim[j_next], disk_mid[j_next], disk_mid[j]])
        bm_buckle.faces.new([disk_mid[j], disk_mid[j_next], disk_center])

    add_beast_face(
        bm_buckle,
        center=buckle_c + Vector((0, -0.007, 0)),
        forward=Vector((0, -1, 0)),
        up=Vector((0, 0, 1)),
        scale=0.022 if not is_female else 0.018,
    )
    bmesh.ops.recalc_face_normals(bm_buckle, faces=bm_buckle.faces)
    parts.append(create_rigid_fn("Armor_Iron_01_BeltBuckle", bm_buckle, mat_gold, "J_Bip_C_Hips", "armor", visual_id, armature))

    # Dual hanging tassels flanking the belt buckle
    add_tassel(bm_b_tassels, knot_center=buckle_c + Vector((-0.058, 0.005, -0.010)), hang_dir=Vector((0, 0, -1)), tassel_len=0.060)
    add_tassel(bm_b_tassels, knot_center=buckle_c + Vector(( 0.058, 0.005, -0.010)), hang_dir=Vector((0, 0, -1)), tassel_len=0.060)
    bmesh.ops.recalc_face_normals(bm_b_tassels, faces=bm_b_tassels.faces)
    parts.append(create_rigid_fn("Armor_Iron_01_BeltTassels", bm_b_tassels, mat_cord, "J_Bip_C_Hips", "armor", visual_id, armature))

    # =========================================================================
    # 8. Genuine Shingled Lamellar Tassets: Front Apron, Side Skirts, Rear Skirt
    # =========================================================================
    def build_shingled_lamellar_mesh(
        bm_iron: bmesh.types.BMesh,
        bm_gold: bmesh.types.BMesh,
        top_z: float,
        bot_z: float,
        n_tiers: int,
        n_cols: int,
        get_span_pts_func,
    ):
        """Generates authentic tiered shingled lamellar plates (札甲片幾何) with wide gold hem."""
        z_step = (top_z - bot_z) / n_tiers
        overlap = 0.006

        for t in range(n_tiers):
            t_top = top_z - t * z_step
            t_bot = t_top - z_step - overlap
            is_lowest = (t == n_tiers - 1)

            out_offset = (n_tiers - t) * 0.0025

            row_top = []
            row_bot = []
            for col in range(n_cols):
                u = col / (n_cols - 1)
                p_top, p_bot_pt, normal_dir = get_span_pts_func(u, t_top, t_bot)
                p_top = p_top + normal_dir * out_offset
                p_bot_pt = p_bot_pt + normal_dir * out_offset

                row_top.append(bm_iron.verts.new(p_top))
                row_bot.append(bm_iron.verts.new(p_bot_pt))

            for col in range(n_cols - 1):
                bm_iron.faces.new([
                    row_bot[col],
                    row_top[col],
                    row_top[col + 1],
                    row_bot[col + 1],
                ])
                mid_pt = (row_top[col].co + row_top[col + 1].co) * 0.5 + Vector((0, 0, -0.004))
                _, _, n_dir = get_span_pts_func(col / (n_cols - 1), t_top, t_bot)
                add_brass_rivet(bm_iron, mid_pt, n_dir, radius=0.0022, depth=0.0016, n_segs=6)

            if is_lowest:
                hem_h = 0.038
                hem_top = []
                hem_bot = []
                for col in range(n_cols):
                    u = col / (n_cols - 1)
                    p_t, p_b, n_d = get_span_pts_func(u, t_bot + hem_h, t_bot)
                    hem_top.append(bm_gold.verts.new(p_t + n_d * (out_offset + 0.003)))
                    hem_bot.append(bm_gold.verts.new(p_b + n_d * (out_offset + 0.003)))

                for col in range(n_cols - 1):
                    bm_gold.faces.new([
                        hem_bot[col],
                        hem_top[col],
                        hem_top[col + 1],
                        hem_bot[col + 1],
                    ])
                    h_mid = (hem_bot[col].co + hem_bot[col + 1].co) * 0.5 + Vector((0, 0, 0.008))
                    _, _, n_d = get_span_pts_func(col / (n_cols - 1), t_bot, t_bot)
                    add_brass_rivet(bm_gold, h_mid, n_d, radius=0.0028, depth=0.0020, n_segs=8)

    # 8A. Front Apron / 蔽膝
    bm_apron_iron = bmesh.new()
    bm_apron_gold = bmesh.new()
    z_ap_top = z_belt_bot + 0.010
    z_ap_bot = 0.620 if not is_female else 0.580

    def get_apron_pt(u: float, z_t: float, z_b: float):
        frac = (u - 0.5) * 2.0
        w_t = (0.085 if not is_female else 0.075)
        w_b = (0.118 if not is_female else 0.105)
        v_prog = (z_belt_bot - z_t) / max(1e-4, z_belt_bot - z_ap_bot)
        w_cur = w_t * (1.0 - v_prog) + w_b * v_prog
        px = frac * w_cur
        py = -waist_ry_front * 1.08 - 0.015 - v_prog * 0.022
        norm = Vector((frac * 0.20, -0.98, 0.0)).normalized()
        return Vector((px, py, z_t)), Vector((px, py, z_b)), norm

    build_shingled_lamellar_mesh(bm_apron_iron, bm_apron_gold, z_ap_top, z_ap_bot, n_tiers=5, n_cols=7, get_span_pts_func=get_apron_pt)
    bmesh.ops.recalc_face_normals(bm_apron_iron, faces=bm_apron_iron.faces)
    bmesh.ops.solidify(bm_apron_iron, geom=bm_apron_iron.faces[:], thickness=0.0035)
    bmesh.ops.recalc_face_normals(bm_apron_gold, faces=bm_apron_gold.faces)
    bmesh.ops.solidify(bm_apron_gold, geom=bm_apron_gold.faces[:], thickness=0.0028)

    weights_apron = {"J_Bip_C_Hips": 0.75, "J_Bip_L_UpperLeg": 0.125, "J_Bip_R_UpperLeg": 0.125}
    parts.append(create_skinned_component("Armor_Iron_01_Tasset_Front", bm_apron_iron, mat_lamellar, weights_apron, "armor", visual_id, armature))
    parts.append(create_skinned_component("Armor_Iron_01_Tasset_Front_Gold", bm_apron_gold, mat_gold, weights_apron, "armor", visual_id, armature))

    # 8B. Side Skirts / 胯甲 (L & R)
    for side, sign in (("L", 1.0), ("R", -1.0)):
        bm_side_iron = bmesh.new()
        bm_side_gold = bmesh.new()
        z_sk_top = z_belt_bot + 0.015
        z_sk_bot = 0.635 if not is_female else 0.595

        def get_side_pt(u: float, z_t: float, z_b: float):
            ang = (u - 0.5) * (math.pi * 0.70)
            v_p = (z_belt_bot - z_t) / max(1e-4, z_belt_bot - z_sk_bot)
            rx = (waist_rx * 1.08 + v_p * 0.035)
            ry = (waist_ry_front * 1.06 + v_p * 0.025)
            px = sign * (math.cos(ang) * rx)
            py = math.sin(ang) * ry - 0.010
            norm = Vector((sign * math.cos(ang), math.sin(ang), 0.0)).normalized()
            return Vector((px, py, z_t)), Vector((px, py, z_b)), norm

        build_shingled_lamellar_mesh(bm_side_iron, bm_side_gold, z_sk_top, z_sk_bot, n_tiers=5, n_cols=7, get_span_pts_func=get_side_pt)
        bmesh.ops.recalc_face_normals(bm_side_iron, faces=bm_side_iron.faces)
        bmesh.ops.solidify(bm_side_iron, geom=bm_side_iron.faces[:], thickness=0.0035)
        bmesh.ops.recalc_face_normals(bm_side_gold, faces=bm_side_gold.faces)
        bmesh.ops.solidify(bm_side_gold, geom=bm_side_gold.faces[:], thickness=0.0028)

        bone_leg = f"J_Bip_{side}_UpperLeg"
        weights_side = {"J_Bip_C_Hips": 0.60, bone_leg: 0.40}
        parts.append(create_skinned_component(f"Armor_Iron_01_Tasset_Side_{side}", bm_side_iron, mat_lamellar, weights_side, "armor", visual_id, armature))
        parts.append(create_skinned_component(f"Armor_Iron_01_Tasset_Side_Gold_{side}", bm_side_gold, mat_gold, weights_side, "armor", visual_id, armature))

    # 8C. Rear Skirt / 後裙甲
    bm_rear_iron = bmesh.new()
    bm_rear_gold = bmesh.new()
    z_rear_top = z_belt_bot + 0.012
    z_rear_bot = 0.640 if not is_female else 0.600

    def get_rear_pt(u: float, z_t: float, z_b: float):
        frac = (u - 0.5) * 2.0
        v_p = (z_belt_bot - z_t) / max(1e-4, z_belt_bot - z_rear_bot)
        w_cur = (waist_rx * 0.88) + v_p * 0.030
        px = frac * w_cur
        py = waist_ry_back * 1.08 + 0.015 + v_p * 0.020
        norm = Vector((frac * 0.20, 0.98, 0.0)).normalized()
        return Vector((px, py, z_t)), Vector((px, py, z_b)), norm

    build_shingled_lamellar_mesh(bm_rear_iron, bm_rear_gold, z_rear_top, z_rear_bot, n_tiers=5, n_cols=8, get_span_pts_func=get_rear_pt)
    bmesh.ops.recalc_face_normals(bm_rear_iron, faces=bm_rear_iron.faces)
    bmesh.ops.solidify(bm_rear_iron, geom=bm_rear_iron.faces[:], thickness=0.0035)
    bmesh.ops.recalc_face_normals(bm_rear_gold, faces=bm_rear_gold.faces)
    bmesh.ops.solidify(bm_rear_gold, geom=bm_rear_gold.faces[:], thickness=0.0028)

    weights_rear = {"J_Bip_C_Hips": 0.80, "J_Bip_L_UpperLeg": 0.10, "J_Bip_R_UpperLeg": 0.10}
    parts.append(create_skinned_component("Armor_Iron_01_Tasset_Rear", bm_rear_iron, mat_lamellar, weights_rear, "armor", visual_id, armature))
    parts.append(create_skinned_component("Armor_Iron_01_Tasset_Rear_Gold", bm_rear_gold, mat_gold, weights_rear, "armor", visual_id, armature))

    return parts
