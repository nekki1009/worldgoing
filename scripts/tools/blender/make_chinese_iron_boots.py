"""Build authentic Chinese Style Iron Armor Boots (Boots_Iron_01 / 中式鐵靴) matching reference sheet.

Components per side (L/R):
1. Boots_Iron_01_Shaft_L/R: High boot base (Z ~ 0.10 to 0.42m) with top padded collar
2. Boots_Iron_01_ShinGuard_L/R: Contoured dark steel shin guard plate with bronze filigree border
3. Boots_Iron_01_ShinEmblem_L/R: 3D sculpted ferocious beast / taotie mask boss on upper shin
4. Boots_Iron_01_Straps_L/R: 3 horizontal leather straps with bronze roller buckles on outer calf
5. Boots_Iron_01_Instep_L/R: Segmented 4-tier articulated curved iron plates across instep
6. Boots_Iron_01_ToeCap_L/R: Reinforced curved bronze bumper cap over toe box
7. Boots_Iron_01_Heel_L/R: Reinforced curved heel counter armor with bronze trim & rivets
8. Boots_Iron_01_Sole_L/R: Heavy treaded boot sole with stepped heel
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
    radius: float = 0.0030,
    depth: float = 0.0022,
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
        base_ring.append(bm.verts.new(center + r_vec * (radius * 1.12)))
        mid_ring.append(bm.verts.new(center + r_vec * radius + z_axis * (depth * 0.45)))
    apex = bm.verts.new(center + z_axis * depth)

    for s in range(n_segs):
        s_next = (s + 1) % n_segs
        bm.faces.new([base_ring[s], base_ring[s_next], mid_ring[s_next], mid_ring[s]])
        bm.faces.new([mid_ring[s], mid_ring[s_next], apex])


def add_beast_face(
    bm: bmesh.types.BMesh,
    center: Vector,
    forward: Vector,
    up: Vector,
    scale: float = 0.024,
):
    """3D sculpted ferocious beast / lion / taotie mask boss."""
    n_fwd = forward.normalized()
    n_up = up.normalized()
    n_right = n_fwd.cross(n_up).normalized()

    def tr_e(x: float, y: float, z: float) -> Vector:
        return center + n_right * (x * scale) + n_up * (y * scale) + n_fwd * (z * scale)

    # 1. Brow & Crest
    c_top = bm.verts.new(tr_e(0.0, 0.85, 0.35))
    c_mid = bm.verts.new(tr_e(0.0, 0.45, 0.50))
    c_bot = bm.verts.new(tr_e(0.0, 0.15, 0.55))

    c_l_mid = bm.verts.new(tr_e(-0.45, 0.45, 0.35))
    c_r_mid = bm.verts.new(tr_e(0.45, 0.45, 0.35))
    c_l_top = bm.verts.new(tr_e(-0.30, 0.80, 0.25))
    c_r_top = bm.verts.new(tr_e(0.30, 0.80, 0.25))

    bm.faces.new([c_top, c_r_top, c_r_mid, c_mid])
    bm.faces.new([c_top, c_mid, c_l_mid, c_l_top])

    # 2. Dual Curved Horns (祥雲雙角)
    for s_sign in [-1.0, 1.0]:
        sx = s_sign
        h0 = bm.verts.new(tr_e(sx * 0.25, 0.70, 0.20))
        h1 = bm.verts.new(tr_e(sx * 0.55, 1.00, 0.25))
        h2 = bm.verts.new(tr_e(sx * 0.85, 1.30, 0.30))
        h3 = bm.verts.new(tr_e(sx * 1.10, 1.45, 0.20))

        h0_in = bm.verts.new(tr_e(sx * 0.15, 0.75, 0.15))
        h1_in = bm.verts.new(tr_e(sx * 0.40, 1.05, 0.20))
        h2_in = bm.verts.new(tr_e(sx * 0.65, 1.30, 0.25))
        h3_in = bm.verts.new(tr_e(sx * 0.90, 1.40, 0.18))

        if s_sign == 1.0:
            bm.faces.new([h0, h1, h1_in, h0_in])
            bm.faces.new([h1, h2, h2_in, h1_in])
            bm.faces.new([h2, h3, h3_in, h2_in])
        else:
            bm.faces.new([h0, h0_in, h1_in, h1])
            bm.faces.new([h1, h1_in, h2_in, h2])
            bm.faces.new([h2, h2_in, h3_in, h3])

    # 3. Bulging Fierce Eyes
    for s_sign in [-1.0, 1.0]:
        sx = s_sign
        eye_c = tr_e(sx * 0.48, 0.20, 0.40)
        norm_eye = (n_fwd * 0.85 + n_right * (sx * 0.40) + n_up * 0.25).normalized()
        add_brass_rivet(bm, eye_c, norm_eye, radius=scale * 0.22, depth=scale * 0.16, n_segs=8)

        br0 = bm.verts.new(tr_e(sx * 0.22, 0.38, 0.40))
        br1 = bm.verts.new(tr_e(sx * 0.50, 0.45, 0.48))
        br2 = bm.verts.new(tr_e(sx * 0.78, 0.32, 0.35))
        br0_d = bm.verts.new(tr_e(sx * 0.22, 0.28, 0.35))
        br1_d = bm.verts.new(tr_e(sx * 0.50, 0.32, 0.40))
        br2_d = bm.verts.new(tr_e(sx * 0.78, 0.22, 0.30))
        if s_sign == 1.0:
            bm.faces.new([br0, br1, br1_d, br0_d])
            bm.faces.new([br1, br2, br2_d, br1_d])
        else:
            bm.faces.new([br0, br0_d, br1_d, br1])
            bm.faces.new([br1, br1_d, br2_d, br2])

    # 4. Broad Lion Snout
    nose_tip = bm.verts.new(tr_e(0.0, -0.15, 0.65))
    nose_l = bm.verts.new(tr_e(-0.30, -0.18, 0.55))
    nose_r = bm.verts.new(tr_e(0.30, -0.18, 0.55))

    bm.faces.new([c_bot, nose_r, nose_tip])
    bm.faces.new([c_bot, nose_tip, nose_l])
    bm.faces.new([c_bot, c_r_mid, nose_r])
    bm.faces.new([c_bot, nose_l, c_l_mid])

    # 5. Snarling Mouth & Fangs
    lip_c = bm.verts.new(tr_e(0.0, -0.42, 0.50))
    lip_l = bm.verts.new(tr_e(-0.40, -0.42, 0.45))
    lip_r = bm.verts.new(tr_e(0.40, -0.42, 0.45))
    lip_l_wide = bm.verts.new(tr_e(-0.75, -0.45, 0.30))
    lip_r_wide = bm.verts.new(tr_e(0.75, -0.45, 0.30))

    bm.faces.new([nose_tip, nose_r, lip_r, lip_c])
    bm.faces.new([nose_tip, lip_c, lip_l, nose_l])
    bm.faces.new([nose_r, lip_r_wide, lip_r])
    bm.faces.new([nose_l, lip_l, lip_l_wide])

    fang_l = bm.verts.new(tr_e(-0.40, -0.80, 0.40))
    fang_r = bm.verts.new(tr_e(0.40, -0.80, 0.40))
    bm.faces.new([lip_l, lip_l_wide, fang_l])
    bm.faces.new([lip_r, fang_r, lip_r_wide])

    tooth_c = bm.verts.new(tr_e(0.0, -0.62, 0.40))
    bm.faces.new([lip_l, lip_c, tooth_c])
    bm.faces.new([lip_c, lip_r, tooth_c])

    # 6. Flared Whisker/Jowl Flame Wing Plates
    for s_sign in [-1.0, 1.0]:
        sx = s_sign
        w_top = bm.verts.new(tr_e(sx * 0.85, 0.20, 0.25))
        w_mid = bm.verts.new(tr_e(sx * 1.15, -0.10, 0.30))
        w_bot = bm.verts.new(tr_e(sx * 1.00, -0.55, 0.20))
        w_in_t = bm.verts.new(tr_e(sx * 0.70, 0.05, 0.20))
        w_in_b = bm.verts.new(tr_e(sx * 0.65, -0.35, 0.20))
        if s_sign == 1.0:
            bm.faces.new([w_top, w_mid, w_in_t])
            bm.faces.new([w_mid, w_in_b, w_in_t])
            bm.faces.new([w_mid, w_bot, w_in_b])
        else:
            bm.faces.new([w_top, w_in_t, w_mid])
            bm.faces.new([w_mid, w_in_t, w_in_b])
            bm.faces.new([w_mid, w_in_b, w_bot])


def make_chinese_iron_boots(
    armature: bpy.types.Object,
    source_raw_body: bpy.types.Object = None,
    is_female: bool = False,
    create_rigid_fn=None,
    component_prefix: str = "Boots_Iron_01",
    visual_id: str = "boots_iron_01",
    mingguang_style: bool = False,
) -> list[bpy.types.Object]:
    """Generate a modular Chinese boot variant for both male and female rigs."""
    parts: list[bpy.types.Object] = []

    # Materials unified with Chinese Iron Helmet and Armor
    if mingguang_style:
        mat_steel_dark = get_material("Worldgoing_Mingguang_Boot_Steel", (0.16, 0.19, 0.25), metallic=0.94, roughness=0.28)
        mat_bronze = get_material("Worldgoing_Mingguang_Boot_Gold", (0.82, 0.56, 0.12), metallic=0.96, roughness=0.18)
        mat_lamellar = get_material("Worldgoing_Mingguang_Boot_Lamellar", (0.34, 0.39, 0.49), metallic=0.90, roughness=0.26)
        mat_leather = get_material("Worldgoing_Mingguang_Boot_Leather", (0.035, 0.018, 0.008), metallic=0.0, roughness=0.46)
        mat_collar = get_material("Worldgoing_Mingguang_Boot_Cloth", (0.045, 0.050, 0.065), metallic=0.0, roughness=0.86)
        mat_sole = get_material("Worldgoing_Mingguang_Boot_Sole", (0.018, 0.021, 0.030), metallic=0.34, roughness=0.74)
    else:
        mat_steel_dark = get_material("Worldgoing_Iron_Dark", (0.042, 0.045, 0.052), metallic=0.92, roughness=0.34)
        mat_bronze = get_material("Worldgoing_Chinese_Gold", (0.95, 0.76, 0.22), metallic=0.96, roughness=0.20)
        mat_lamellar = get_material("Worldgoing_Iron_Lamellar", (0.048, 0.050, 0.056), metallic=0.88, roughness=0.38)
        mat_leather = get_material("Worldgoing_Leather_Dark", (0.024, 0.012, 0.005), metallic=0.0, roughness=0.52)
        mat_collar = get_material("Worldgoing_Chinese_Cloth_Dark", (0.025, 0.025, 0.030), metallic=0.0, roughness=0.92)
        mat_sole = get_material("Worldgoing_Boot_Sole", (0.022, 0.024, 0.028), metallic=0.30, roughness=0.80)

    # Dimensional anchors based on actual bone data
    # Male: lower leg head z=0.577, ankle z=0.121, foot tail y=-0.104, toe y=-0.160
    # Female: lower leg head z=0.552, ankle z=0.137, foot tail y=-0.085, toe y=-0.131
    leg_x = 0.060 if not is_female else 0.054
    calf_top_z = 0.435 if not is_female else 0.415
    ankle_z = 0.120 if not is_female else 0.132
    sole_bot_z = 0.000
    sole_top_z = 0.038 if not is_female else 0.036

    foot_y_back = 0.075 if not is_female else 0.068
    foot_y_front = -0.215 if not is_female else -0.190
    toe_cap_y = -0.165 if not is_female else -0.145

    calf_r_x = 0.056 if not is_female else 0.048
    calf_r_y = 0.060 if not is_female else 0.052
    ankle_r_x = 0.046 if not is_female else 0.039
    ankle_r_y = 0.050 if not is_female else 0.043

    for side, sign in (("L", 1.0), ("R", -1.0)):
        center_x = sign * leg_x

        # 0. Boots_Iron_01_Foot_L/R: Base boot shoe & ankle shaft extracted with 100% skinning weights
        if source_raw_body is not None:
            obj_boot = source_raw_body.copy()
            obj_boot.name = f"{component_prefix}_Foot_{side}"
            obj_boot.data = source_raw_body.data.copy()
            obj_boot.data.name = f"{component_prefix}_Foot_{side}Mesh"
            bpy.context.collection.objects.link(obj_boot)
            bm_b = bmesh.new()
            bm_b.from_mesh(obj_boot.data)
            delete_faces = []
            for f in bm_b.faces:
                center = f.calc_center_median()
                is_side = (center.x >= 0.0) if sign > 0 else (center.x <= 0.0)
                # Strictly keep ONLY raw skin body faces (material_index == 0) within feet & lower calf
                if f.material_index != 0 or not is_side or not (0.005 <= center.z <= 0.420):
                    delete_faces.append(f)
            bmesh.ops.delete(bm_b, geom=delete_faces, context="FACES")
            bmesh.ops.bisect_plane(
                bm_b,
                geom=bm_b.faces[:] + bm_b.edges[:] + bm_b.verts[:],
                plane_co=(0, 0, 0.420),
                plane_no=(0, 0, -1),
                clear_inner=True,
            )
            bm_b.normal_update()
            for v in bm_b.verts:
                if v.link_faces and v.normal.length > 0:
                    v.co += v.normal.normalized() * 0.0040
            loose = [v for v in bm_b.verts if not v.link_faces]
            bmesh.ops.delete(bm_b, geom=loose, context="VERTS")
            bmesh.ops.recalc_face_normals(bm_b, faces=bm_b.faces)
            bm_b.to_mesh(obj_boot.data)
            bm_b.free()
            obj_boot.data.update()
            obj_boot.data.materials.clear()
            obj_boot.data.materials.append(mat_steel_dark)
            for p in obj_boot.data.polygons:
                p.material_index = 0
                p.use_smooth = True
            obj_boot["worldgoing_character_part"] = True
            obj_boot["worldgoing_component_slot"] = "boots"
            obj_boot["worldgoing_visual_id"] = visual_id
            parts.append(obj_boot)

        # =====================================================================
        # 1. Boots_Iron_01_Shaft_L/R (高筒靴體與頂部軟領)
        # =====================================================================
        bm_shaft = bmesh.new()
        bm_collar = bmesh.new()
        n_lat = 10
        n_lon = 18
        shaft_grid = []

        for i in range(n_lat):
            v = i / (n_lat - 1)
            pz = calf_top_z - (calf_top_z - ankle_z) * v
            # Slight calf flare in upper-middle
            flare = 1.0 + 0.12 * math.sin(v * math.pi)
            rx = (calf_r_x * (1.0 - v) + ankle_r_x * v) * flare
            ry = (calf_r_y * (1.0 - v) + ankle_r_y * v) * flare
            py_center = 0.012 * (1.0 - v) + 0.025 * v

            row = []
            for j in range(n_lon):
                ang = j * 2.0 * math.pi / n_lon
                px = center_x + math.sin(ang) * rx
                py = py_center - math.cos(ang) * ry
                row.append(bm_shaft.verts.new((px, py, pz)))
            shaft_grid.append(row)

        for i in range(n_lat - 1):
            for j in range(n_lon):
                j_next = (j + 1) % n_lon
                bm_shaft.faces.new([
                    shaft_grid[i][j],
                    shaft_grid[i + 1][j],
                    shaft_grid[i + 1][j_next],
                    shaft_grid[i][j_next],
                ])

        bmesh.ops.recalc_face_normals(bm_shaft, faces=bm_shaft.faces)
        bmesh.ops.solidify(bm_shaft, geom=bm_shaft.faces[:], thickness=0.0032)

        # Padded Collar rim at top (靴口加厚軟布/皮革內襯)
        col_pts_outer = []
        col_pts_inner = []
        for j in range(n_lon):
            ang = j * 2.0 * math.pi / n_lon
            px_o = center_x + math.sin(ang) * (calf_r_x * 1.04)
            py_o = 0.012 - math.cos(ang) * (calf_r_y * 1.04)
            px_i = center_x + math.sin(ang) * (calf_r_x * 0.94)
            py_i = 0.012 - math.cos(ang) * (calf_r_y * 0.94)
            col_pts_outer.append(bm_collar.verts.new((px_o, py_o, calf_top_z + 0.012)))
            col_pts_inner.append(bm_collar.verts.new((px_i, py_i, calf_top_z - 0.010)))

        for j in range(n_lon):
            j_next = (j + 1) % n_lon
            bm_collar.faces.new([
                col_pts_inner[j],
                col_pts_outer[j],
                col_pts_outer[j_next],
                col_pts_inner[j_next],
            ])
        bmesh.ops.recalc_face_normals(bm_collar, faces=bm_collar.faces)

        # =====================================================================
        # 2. Boots_Iron_01_ShinGuard_L/R (前向圓弧護脛甲與銅邊)
        # =====================================================================
        bm_shin = bmesh.new()
        n_shin_lat = 9
        n_shin_lon = 10
        shin_grid = []

        z_shin_top = calf_top_z - 0.010
        z_shin_bot = ankle_z + 0.015

        for i in range(n_shin_lat):
            v = i / (n_shin_lat - 1)
            pz = z_shin_top - (z_shin_top - z_shin_bot) * v
            # Shin curvature: front arc extending +/- 65 degrees
            rx = (calf_r_x * (1.0 - v) + ankle_r_x * v) * 1.08
            ry = (calf_r_y * (1.0 - v) + ankle_r_y * v) * 1.08
            py_c = 0.012 * (1.0 - v) + 0.025 * v

            row = []
            for j in range(n_shin_lon):
                # Front span: -60 deg to +60 deg
                frac = (j / (n_shin_lon - 1) - 0.5) * 2.0
                ang = frac * (math.pi * 0.35)
                px = center_x + math.sin(ang) * rx
                py = py_c - math.cos(ang) * ry - 0.003
                row.append(bm_shin.verts.new((px, py, pz)))
            shin_grid.append(row)

        for i in range(n_shin_lat - 1):
            for j in range(n_shin_lon - 1):
                bm_shin.faces.new([
                    shin_grid[i][j],
                    shin_grid[i + 1][j],
                    shin_grid[i + 1][j + 1],
                    shin_grid[i][j + 1],
                ])

        bmesh.ops.recalc_face_normals(bm_shin, faces=bm_shin.faces)
        bmesh.ops.solidify(bm_shin, geom=bm_shin.faces[:], thickness=0.0035)

        # Rivets along the shin guard borders
        for i in [0, 2, 4, 6, 8]:
            v_l = shin_grid[i][0]
            v_r = shin_grid[i][-1]
            add_brass_rivet(bm_shin, v_l.co, Vector((sign * -0.5, -0.85, 0.1)), radius=0.0028, depth=0.0018)
            add_brass_rivet(bm_shin, v_r.co, Vector((sign * 0.5, -0.85, 0.1)), radius=0.0028, depth=0.0018)

        # =====================================================================
        # 3. Boots_Iron_01_ShinEmblem_L/R (3D 辟邪/饕餮獸面護脛飾)
        # =====================================================================
        bm_emblem = bmesh.new()
        z_emblem = z_shin_top - 0.048
        emblem_c = Vector((center_x, 0.012 - (calf_r_y * 1.08) - 0.005, z_emblem))
        add_beast_face(
            bm_emblem,
            center=emblem_c,
            forward=Vector((0.0, -1.0, 0.0)),
            up=Vector((0.0, 0.0, 1.0)),
            scale=0.014 if not is_female else 0.012,
        )
        bmesh.ops.recalc_face_normals(bm_emblem, faces=bm_emblem.faces)

        # =====================================================================
        # 4. Boots_Iron_01_Straps_L/R (3 道橫向皮革束帶與外側青銅帶扣)
        # =====================================================================
        bm_straps = bmesh.new()
        bm_buckles = bmesh.new()

        strap_heights = [
            calf_top_z - 0.025,  # Top calf strap
            (calf_top_z + ankle_z) * 0.50,  # Mid calf strap
            ankle_z + 0.030,  # Lower ankle strap
        ]

        strap_w = 0.012
        for s_z in strap_heights:
            v_frac = (calf_top_z - s_z) / max(1e-4, calf_top_z - ankle_z)
            rx = (calf_r_x * (1.0 - v_frac) + ankle_r_x * v_frac) * 1.09
            ry = (calf_r_y * (1.0 - v_frac) + ankle_r_y * v_frac) * 1.09
            py_c = 0.012 * (1.0 - v_frac) + 0.025 * v_frac

            st_top = []
            st_bot = []
            for j in range(n_lon):
                ang = j * 2.0 * math.pi / n_lon
                px = center_x + math.sin(ang) * rx
                py = py_c - math.cos(ang) * ry
                st_top.append(bm_straps.verts.new((px, py, s_z + strap_w * 0.5)))
                st_bot.append(bm_straps.verts.new((px, py, s_z - strap_w * 0.5)))

            for j in range(n_lon):
                j_next = (j + 1) % n_lon
                bm_straps.faces.new([st_bot[j], st_top[j], st_top[j_next], st_bot[j_next]])

            # Bronze Roller Buckle on OUTER side of leg
            # Left leg: outer is +X; Right leg: outer is -X
            b_x = center_x + sign * (rx + 0.003)
            b_y = py_c
            b_z = s_z
            bw, bh, bt = 0.007, 0.016, 0.0032
            b_pts = [
                Vector((b_x, b_y - bw * 0.5, b_z - bh * 0.5)),
                Vector((b_x, b_y + bw * 0.5, b_z - bh * 0.5)),
                Vector((b_x, b_y + bw * 0.5, b_z + bh * 0.5)),
                Vector((b_x, b_y - bw * 0.5, b_z + bh * 0.5)),
            ]
            bv = [bm_buckles.verts.new(p) for p in b_pts]
            bv_out = [bm_buckles.verts.new(p + Vector((sign * bt, 0, 0))) for p in b_pts]
            for bi in range(4):
                bi_next = (bi + 1) % 4
                bm_buckles.faces.new([bv[bi], bv[bi_next], bv_out[bi_next], bv_out[bi]])

        bmesh.ops.recalc_face_normals(bm_straps, faces=bm_straps.faces)
        bmesh.ops.solidify(bm_straps, geom=bm_straps.faces[:], thickness=0.0022)
        bmesh.ops.recalc_face_normals(bm_buckles, faces=bm_buckles.faces)

        # =====================================================================
        # 5. Boots_Iron_01_Instep_L/R (腳背 4 層關節重疊扎甲)
        # =====================================================================
        bm_instep = bmesh.new()
        n_instep_tiers = 4
        # Spans from ankle down to toe cap
        for t_idx in range(n_instep_tiers):
            t_frac = t_idx / (n_instep_tiers - 1)
            # Tier parameters: curved plate arching over foot bridge
            pz_tier = ankle_z - 0.010 - t_frac * 0.065
            py_tier = -0.045 - t_frac * 0.090
            width_tier = (0.048 - t_frac * 0.006) if not is_female else (0.042 - t_frac * 0.005)
            tier_len = 0.026

            n_arc = 8
            tier_grid = []
            for r_step in range(3):
                dy = r_step * (tier_len * 0.5)
                row = []
                for a_i in range(n_arc):
                    ang_f = (a_i / (n_arc - 1) - 0.5) * math.pi * 0.85
                    px = center_x + math.sin(ang_f) * width_tier
                    py = py_tier - dy
                    pz = pz_tier + math.cos(ang_f) * (width_tier * 0.38) - dy * 0.45
                    row.append(bm_instep.verts.new((px, py, pz)))
                tier_grid.append(row)

            for r_step in range(2):
                for a_i in range(n_arc - 1):
                    bm_instep.faces.new([
                        tier_grid[r_step][a_i],
                        tier_grid[r_step + 1][a_i],
                        tier_grid[r_step + 1][a_i + 1],
                        tier_grid[r_step][a_i + 1],
                    ])

            # Tier center rivet
            c_riv = tier_grid[1][n_arc // 2].co
            add_brass_rivet(bm_instep, c_riv, Vector((0.0, -0.6, 0.8)), radius=0.0024, depth=0.0016)

        bmesh.ops.recalc_face_normals(bm_instep, faces=bm_instep.faces)
        bmesh.ops.solidify(bm_instep, geom=bm_instep.faces[:], thickness=0.0032)

        # =====================================================================
        # 6. Boots_Iron_01_ToeCap_L/R (鞋頭弧形青銅防撞護甲)
        # =====================================================================
        bm_toecap = bmesh.new()
        n_toe_lat = 5
        n_toe_lon = 10
        toe_grid = []
        r_toe_x = 0.040 if not is_female else 0.035
        r_toe_y = 0.042 if not is_female else 0.036
        r_toe_z = 0.032 if not is_female else 0.028

        for i in range(n_toe_lat):
            theta = (i / (n_toe_lat - 1)) * (math.pi * 0.5)
            pz = sole_top_z + math.cos(theta) * r_toe_z
            row = []
            for j in range(n_toe_lon):
                # Front dome: 90 to 270 deg (facing -Y)
                phi = math.pi * 0.5 + (j / (n_toe_lon - 1)) * math.pi
                px = center_x + math.cos(phi) * r_toe_x * math.sin(theta)
                py = toe_cap_y + math.sin(phi) * r_toe_y * math.sin(theta)
                row.append(bm_toecap.verts.new((px, py, pz)))
            toe_grid.append(row)

        for i in range(n_toe_lat - 1):
            for j in range(n_toe_lon - 1):
                bm_toecap.faces.new([
                    toe_grid[i][j],
                    toe_grid[i + 1][j],
                    toe_grid[i + 1][j + 1],
                    toe_grid[i][j + 1],
                ])

        bmesh.ops.recalc_face_normals(bm_toecap, faces=bm_toecap.faces)
        bmesh.ops.solidify(bm_toecap, geom=bm_toecap.faces[:], thickness=0.0035)

        # Brass rivets on toe cap rim
        for j in [1, 3, 6, 8]:
            v_t = toe_grid[1][j]
            add_brass_rivet(bm_toecap, v_t.co, Vector((0, -0.9, 0.4)), radius=0.0026, depth=0.0018)

        # =====================================================================
        # 7. Boots_Iron_01_Heel_L/R (後跟弧形強化甲板與銅邊)
        # =====================================================================
        bm_heel = bmesh.new()
        n_heel_lat = 5
        n_heel_lon = 8
        heel_grid = []
        r_heel_x = 0.042 if not is_female else 0.036
        r_heel_y = 0.040 if not is_female else 0.034
        z_heel_top = sole_top_z + 0.065

        for i in range(n_heel_lat):
            v = i / (n_heel_lat - 1)
            pz = z_heel_top - v * 0.065
            row = []
            for j in range(n_heel_lon):
                # Posterior span: -60 to +60 deg around +Y
                ang = (j / (n_heel_lon - 1) - 0.5) * (math.pi * 0.70)
                px = center_x + math.sin(ang) * r_heel_x
                py = foot_y_back - 0.015 + math.cos(ang) * r_heel_y
                row.append(bm_heel.verts.new((px, py, pz)))
            heel_grid.append(row)

        for i in range(n_heel_lat - 1):
            for j in range(n_heel_lon - 1):
                bm_heel.faces.new([
                    heel_grid[i][j],
                    heel_grid[i + 1][j],
                    heel_grid[i + 1][j + 1],
                    heel_grid[i][j + 1],
                ])

        bmesh.ops.recalc_face_normals(bm_heel, faces=bm_heel.faces)
        bmesh.ops.solidify(bm_heel, geom=bm_heel.faces[:], thickness=0.0035)

        # =====================================================================
        # 8. Boots_Iron_01_Sole_L/R (厚實防滑幾何大底)
        # =====================================================================
        bm_sole = bmesh.new()
        n_sole_pts = 16
        sole_rim_top = []
        sole_rim_bot = []

        # Shoe footprint perimeter
        for k in range(n_sole_pts):
            t_f = k / n_sole_pts
            ang_s = t_f * 2.0 * math.pi
            # Elongated boot shape
            sin_s = math.sin(ang_s)
            cos_s = math.cos(ang_s)
            f_w = (0.048 if cos_s <= 0 else 0.042) * (1.0 if not is_female else 0.90)
            f_len = (foot_y_back - foot_y_front) * 0.52
            y_mid = (foot_y_back + foot_y_front) * 0.5

            px = center_x + sin_s * f_w
            py = y_mid - cos_s * f_len
            sole_rim_top.append(bm_sole.verts.new((px, py, sole_top_z)))
            sole_rim_bot.append(bm_sole.verts.new((px, py, sole_bot_z)))

        # Side walls
        for k in range(n_sole_pts):
            k_next = (k + 1) % n_sole_pts
            bm_sole.faces.new([
                sole_rim_bot[k],
                sole_rim_top[k],
                sole_rim_top[k_next],
                sole_rim_bot[k_next],
            ])

        # Bottom tread face
        c_bot_sole = bm_sole.verts.new((center_x, (foot_y_back + foot_y_front) * 0.5, sole_bot_z))
        for k in range(n_sole_pts):
            k_next = (k + 1) % n_sole_pts
            bm_sole.faces.new([sole_rim_bot[k], c_bot_sole, sole_rim_bot[k_next]])

        bmesh.ops.recalc_face_normals(bm_sole, faces=bm_sole.faces)

        # =====================================================================
        # Skinning & Registration
        # =====================================================================
        bone_leg = f"J_Bip_{side}_LowerLeg"
        bone_foot = f"J_Bip_{side}_Foot"

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

        # Shaft, Shin Guard, Shin Emblem, Straps -> LowerLeg
        parts.append(create_rigid_fn(f"{component_prefix}_Shaft_{side}", bm_shaft, mat_steel_dark, bone_leg, "boots", visual_id, armature))
        parts.append(create_rigid_fn(f"{component_prefix}_Collar_{side}", bm_collar, mat_collar, bone_leg, "boots", visual_id, armature))
        parts.append(create_rigid_fn(f"{component_prefix}_ShinGuard_{side}", bm_shin, mat_steel_dark, bone_leg, "boots", visual_id, armature))
        parts.append(create_rigid_fn(f"{component_prefix}_ShinEmblem_{side}", bm_emblem, mat_bronze, bone_leg, "boots", visual_id, armature))
        parts.append(create_rigid_fn(f"{component_prefix}_Straps_{side}", bm_straps, mat_leather, bone_leg, "boots", visual_id, armature))
        parts.append(create_rigid_fn(f"{component_prefix}_Buckles_{side}", bm_buckles, mat_bronze, bone_leg, "boots", visual_id, armature))

        # Instep, Toe Cap, Heel, Sole -> Foot
        parts.append(create_rigid_fn(f"{component_prefix}_Instep_{side}", bm_instep, mat_lamellar, bone_foot, "boots", visual_id, armature))
        parts.append(create_rigid_fn(f"{component_prefix}_ToeCap_{side}", bm_toecap, mat_bronze, bone_foot, "boots", visual_id, armature))
        parts.append(create_rigid_fn(f"{component_prefix}_Heel_{side}", bm_heel, mat_steel_dark, bone_foot, "boots", visual_id, armature))
        parts.append(create_rigid_fn(f"{component_prefix}_Sole_{side}", bm_sole, mat_sole, bone_foot, "boots", visual_id, armature))

    return parts


def make_mingguang_boots(
    armature: bpy.types.Object,
    source_raw_body: bpy.types.Object = None,
    is_female: bool = False,
    create_rigid_fn=None,
) -> list[bpy.types.Object]:
    """Generate the separate Mingguang War Boots 01 equipment variant."""
    return make_chinese_iron_boots(
        armature,
        source_raw_body=source_raw_body,
        is_female=is_female,
        create_rigid_fn=create_rigid_fn,
        component_prefix="Boots_Mingguang_01",
        visual_id="boots_mingguang_01",
        mingguang_style=True,
    )
