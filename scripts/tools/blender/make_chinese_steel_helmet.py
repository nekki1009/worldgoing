"""Build authentic Chinese Style Steel Helmet (Helmet_Steel_01 / 中國風鋼盔) matching reference sheet.

Constructs 10 modular components skinned rigidly to J_Bip_C_Head:
1. Helmet_Steel_01_Dome: 4-quadrant dark steel cranial bowl with 4-way cross-ridge reinforcing bronze bands and domed rivets (十字梁穹頂)
2. Helmet_Steel_01_Finial: Multi-tiered bronze lotus petal base, stepped bead collar, and top plume tube (蓮花算盤珠纓管)
3. Helmet_Steel_01_Plume: Volumetric flowing crimson horsehair plume cascading backward and down the rear (大紅長馬尾毛纓)
4. Helmet_Steel_01_BeastEmblem: 3D sculpted ferocious beast / taotie mask at brow center (額前立體饕餮/辟邪獸面)
5. Helmet_Steel_01_BrowBand: Double ocular arched steel brow band with bronze cloud scrollwork and brass rivets (雙弧額弓)
6. Helmet_Steel_01_SideMedallions: Left and right circular sunburst-lotus boss rosettes at ear axes (兩側蓮花寶相花圓盤)
7. Helmet_Steel_01_Aventail: 4-tier articulated dark steel lamellar aventail / neck guard (4層扎甲頓項)
8. Helmet_Steel_01_CordTassels: Red braided vertical cord columns with Chinese knots and hanging tassels (紅色編織穿繩結與懸掛流蘇)
9. Helmet_Steel_01_Strap & Helmet_Steel_01_Buckle: Leather chin strap and bronze roller buckle (下顎真皮束帶與扣環)
10. Helmet_Steel_01_Lining: Quilted diamond padded felt interior lining (防震菱格軟布內襯)
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
    cap_radius: float = 0.0030,
    cap_height: float = 0.0050,
    tassel_len: float = 0.0240,
    flare_radius: float = 0.0062,
    n_segs: int = 8,
):
    """Generates a traditional Chinese knot cap and flared hanging tassel fringe."""
    z_axis = hang_dir.normalized()
    up = Vector((0, 1, 0)) if abs(z_axis.x) > 0.7 else Vector((1, 0, 0))
    x_axis = z_axis.cross(up).normalized()
    y_axis = z_axis.cross(x_axis).normalized()

    # 1. Knot Cap Bead (Spherical/Cylindrical knot collar)
    top_vert = bm.verts.new(knot_center)
    mid_ring = []
    bot_ring = []
    fringe_ring = []

    p_mid = knot_center + z_axis * (cap_height * 0.5)
    p_bot = knot_center + z_axis * cap_height
    p_tip = knot_center + z_axis * (cap_height + tassel_len)

    for s in range(n_segs):
        a = s * 2.0 * math.pi / n_segs
        r_vec = x_axis * math.cos(a) + y_axis * math.sin(a)
        mid_ring.append(bm.verts.new(p_mid + r_vec * cap_radius))
        bot_ring.append(bm.verts.new(p_bot + r_vec * (cap_radius * 0.85)))
        # Flared fringe at bottom
        fringe_ring.append(bm.verts.new(p_tip + r_vec * flare_radius))

    for s in range(n_segs):
        s_next = (s + 1) % n_segs
        bm.faces.new([top_vert, mid_ring[s], mid_ring[s_next]])
        bm.faces.new([mid_ring[s], bot_ring[s], bot_ring[s_next], mid_ring[s_next]])
        bm.faces.new([bot_ring[s], fringe_ring[s], fringe_ring[s_next], bot_ring[s_next]])

    # Bottom cap closing the fringe
    bottom_center = bm.verts.new(p_tip + z_axis * 0.002)
    for s in range(n_segs):
        s_next = (s + 1) % n_segs
        bm.faces.new([fringe_ring[s], bottom_center, fringe_ring[s_next]])


def make_chinese_steel_helmet(
    armature: bpy.types.Object,
    is_female: bool = False,
    create_rigid_fn=None,
) -> list[bpy.types.Object]:
    parts: list[bpy.types.Object] = []
    visual_id = "helmet_steel_01"

    head_bone = armature.data.bones.get("J_Bip_C_Head")
    if head_bone is None:
        raise RuntimeError("Missing J_Bip_C_Head bone in armature!")
    head_pos = head_bone.head_local.copy()

    # Materials matching Chinese Steel Helmet reference sheet
    mat_steel_dark = get_material("Worldgoing_Steel_Dark", (0.048, 0.052, 0.058), metallic=0.92, roughness=0.32)
    mat_bronze = get_material("Worldgoing_Steel_Bronze", (0.86, 0.65, 0.18), metallic=0.95, roughness=0.22)
    mat_plume = get_material("Worldgoing_Steel_Plume_Red", (0.82, 0.03, 0.04), metallic=0.0, roughness=0.82)
    mat_cord = get_material("Worldgoing_Steel_Cord_Red", (0.88, 0.05, 0.06), metallic=0.0, roughness=0.70)
    mat_lamellar = get_material("Worldgoing_Steel_Lamellar", (0.050, 0.054, 0.060), metallic=0.90, roughness=0.34)
    mat_leather = get_material("Worldgoing_Helmet_Leather_Trim", (0.024, 0.012, 0.005), metallic=0.0, roughness=0.50)
    mat_lining = get_material("Worldgoing_Helmet_Lining", (0.032, 0.030, 0.034), metallic=0.0, roughness=0.92)

    bm_dome = bmesh.new()
    bm_finial = bmesh.new()
    bm_plume = bmesh.new()
    bm_emblem = bmesh.new()
    bm_brow = bmesh.new()
    bm_medallions = bmesh.new()
    bm_aventail = bmesh.new()
    bm_tassels = bmesh.new()
    bm_strap = bmesh.new()
    bm_buckle = bmesh.new()
    bm_lining = bmesh.new()

    # Dome geometric parameters
    z_apex = 0.236
    z_rim_base = 0.118
    rx_max = 0.125
    ry_front_max = 0.144
    ry_back_max = 0.128
    y_center_offset = -0.005

    # =========================================================================
    # 1. Helmet_Steel_01_Dome: 4-Quadrant Steel Cranial Bowl with 4-Way Cross-Ridge Bands
    # =========================================================================
    n_lat = 16
    n_lon = 48  # 4 quadrants -> 12 slices per quadrant
    verts_grid = []

    for i in range(n_lat):
        v = i / (n_lat - 1)
        row = []
        pz_base = z_apex - (z_apex - z_rim_base) * (v ** 0.95)
        rad_prof = 0.0 if v == 0 else math.sin(v * math.pi * 0.5) ** 0.46

        for j in range(n_lon):
            angle = j * 2.0 * math.pi / n_lon
            cos_a = math.cos(angle)
            sin_a = math.sin(angle)

            rx = rx_max
            ry = ry_front_max if cos_a >= 0 else ry_back_max

            # 4-quadrant dishing (cross-ridge division along 0, 90, 180, 270 degrees)
            quad_dish = 0.0028 * math.cos(4.0 * angle) * (math.sin(v * math.pi) ** 0.72)
            r_mod = 1.0 + quad_dish

            px = sin_a * rx * rad_prof * r_mod
            py = -cos_a * ry * rad_prof * r_mod + y_center_offset
            pz = pz_base

            row.append(bm_dome.verts.new(head_pos + Vector((px, py, pz))))
        verts_grid.append(row)

    apex_vert = bm_dome.verts.new(head_pos + Vector((0.0, y_center_offset, z_apex + 0.002)))
    for j in range(n_lon):
        next_j = (j + 1) % n_lon
        bm_dome.faces.new([apex_vert, verts_grid[1][j], verts_grid[1][next_j]])

    for i in range(1, n_lat - 1):
        for j in range(n_lon):
            next_j = (j + 1) % n_lon
            bm_dome.faces.new([
                verts_grid[i][j],
                verts_grid[i + 1][j],
                verts_grid[i + 1][next_j],
                verts_grid[i][next_j],
            ])

    bmesh.ops.recalc_face_normals(bm_dome, faces=bm_dome.faces)
    bmesh.ops.solidify(bm_dome, geom=bm_dome.faces[:], thickness=0.0035)

    # 1B. 4-Way Cross-Ridge Reinforcing Bronze Bands (俯視十字梁) on Finial/Dome
    # Front arm (angle 0), Back arm (angle pi), Right arm (angle pi/2), Left arm (angle 3pi/2)
    cross_arms = [
        {"angle": 0.0,               "name": "front"},
        {"angle": math.pi * 0.5,     "name": "right"},
        {"angle": math.pi,           "name": "back"},
        {"angle": math.pi * 1.5,     "name": "left"},
    ]
    n_arm_pts = 14
    band_half_w = 0.0068

    for arm in cross_arms:
        arm_ang = arm["angle"]
        cos_s = math.cos(arm_ang)
        sin_s = math.sin(arm_ang)

        rx = rx_max
        ry = ry_front_max if cos_s >= 0 else ry_back_max

        tan_x = -cos_s
        tan_y = -sin_s

        vl = []
        vr = []
        vc = []
        for m in range(n_arm_pts):
            u = m / (n_arm_pts - 1)
            pz = z_apex - 0.006 - (z_apex - z_rim_base + 0.006) * (u ** 0.96)
            rad_p = 0.0 if u == 0 else math.sin(u * math.pi * 0.5) ** 0.46

            cx = sin_s * rx * rad_p
            cy = -cos_s * ry * rad_p + y_center_offset
            center_pt = head_pos + Vector((cx, cy, pz))

            norm_dir = Vector((sin_s * rx, -cos_s * ry, 0.40)).normalized()
            raise_pt = center_pt + norm_dir * 0.0028

            vl.append(bm_finial.verts.new(raise_pt + Vector((tan_x * band_half_w, tan_y * band_half_w, 0))))
            vr.append(bm_finial.verts.new(raise_pt - Vector((tan_x * band_half_w, tan_y * band_half_w, 0))))
            vc.append(raise_pt)

        for m in range(n_arm_pts - 1):
            bm_finial.faces.new([vl[m], vl[m + 1], vr[m + 1], vr[m]])

        # 4 Domed brass rivets along each cross arm
        for riv_idx in [2, 5, 8, 11]:
            riv_center = vc[riv_idx]
            riv_norm = (riv_center - (head_pos + Vector((0, y_center_offset, 0.120)))).normalized()
            add_brass_rivet(bm_finial, riv_center, riv_norm, radius=0.0034, depth=0.0024)

    # =========================================================================
    # 2. Helmet_Steel_01_Finial: Multi-Tiered Lotus Petal Base, Stepped Gourd Collar & Tube
    # =========================================================================
    # 2A. Flared Lotus Petal Base (16 petals)
    n_base = 24
    base_rings = []
    z_fl0 = 0.233
    r_fl0_base = 0.028
    r0 = []
    for s in range(n_base):
        ang = s * 2.0 * math.pi / n_base
        r_fl = r_fl0_base + 0.0040 * math.cos(4.0 * ang)
        r0.append(bm_finial.verts.new(head_pos + Vector((math.sin(ang) * r_fl, -math.cos(ang) * r_fl + y_center_offset, z_fl0))))
    base_rings.append(r0)

    # Ring 1: Waist of base
    z_fl1 = 0.244
    r1 = []
    for s in range(n_base):
        ang = s * 2.0 * math.pi / n_base
        r1.append(bm_finial.verts.new(head_pos + Vector((math.sin(ang) * 0.017, -math.cos(ang) * 0.017 + y_center_offset, z_fl1))))
    base_rings.append(r1)

    # Ring 2: Flanged collar
    z_fl2 = 0.249
    r2 = []
    for s in range(n_base):
        ang = s * 2.0 * math.pi / n_base
        r2.append(bm_finial.verts.new(head_pos + Vector((math.sin(ang) * 0.023, -math.cos(ang) * 0.023 + y_center_offset, z_fl2))))
    base_rings.append(r2)

    # Ring 3: Top step
    z_fl3 = 0.252
    r3 = []
    for s in range(n_base):
        ang = s * 2.0 * math.pi / n_base
        r3.append(bm_finial.verts.new(head_pos + Vector((math.sin(ang) * 0.018, -math.cos(ang) * 0.018 + y_center_offset, z_fl3))))
    base_rings.append(r3)

    for r_idx in range(len(base_rings) - 1):
        for s in range(n_base):
            s_next = (s + 1) % n_base
            bm_finial.faces.new([
                base_rings[r_idx][s],
                base_rings[r_idx][s_next],
                base_rings[r_idx + 1][s_next],
                base_rings[r_idx + 1][s],
            ])

    # 2B. Stepped Melon / Gourd Bead Collar (算盤珠雙層環)
    for z_bead, r_bead in [(0.262, 0.0145), (0.281, 0.0120)]:
        n_sp_lat = 8
        n_sp_lon = 18
        sp_grid = []
        for i in range(n_sp_lat):
            v = i / (n_sp_lat - 1)
            lat_ang = (v - 0.5) * math.pi
            z_b = z_bead + math.sin(lat_ang) * r_bead
            r_b = math.cos(lat_ang) * r_bead
            sp_row = []
            for j in range(n_sp_lon):
                ang = j * 2.0 * math.pi / n_sp_lon
                # Fluted bead lobes matching reference melon bead
                r_flute = r_b * (1.0 + 0.04 * math.cos(8.0 * ang))
                sp_row.append(bm_finial.verts.new(head_pos + Vector((
                    math.sin(ang) * r_flute,
                    -math.cos(ang) * r_flute + y_center_offset,
                    z_b,
                ))))
            sp_grid.append(sp_row)

        for i in range(n_sp_lat - 1):
            for j in range(n_sp_lon):
                j_next = (j + 1) % n_sp_lon
                bm_finial.faces.new([
                    sp_grid[i][j],
                    sp_grid[i][j_next],
                    sp_grid[i + 1][j_next],
                    sp_grid[i + 1][j],
                ])

    # 2C. Vertical Plume Tube (纓管)
    z_tube_bot = 0.292
    z_tube_top = 0.328
    r_tube = 0.0072
    r_tube_lip = 0.0098
    n_tube_seg = 16
    t_bot = []
    t_mid = []
    t_lip = []
    t_inner = []
    for s in range(n_tube_seg):
        ang = s * 2.0 * math.pi / n_tube_seg
        sin_a = math.sin(ang)
        cos_a = math.cos(ang)
        t_bot.append(bm_finial.verts.new(head_pos + Vector((sin_a * r_tube, -cos_a * r_tube + y_center_offset, z_tube_bot))))
        t_mid.append(bm_finial.verts.new(head_pos + Vector((sin_a * r_tube, -cos_a * r_tube + y_center_offset, z_tube_top - 0.003))))
        t_lip.append(bm_finial.verts.new(head_pos + Vector((sin_a * r_tube_lip, -cos_a * r_tube_lip + y_center_offset, z_tube_top))))
        t_inner.append(bm_finial.verts.new(head_pos + Vector((sin_a * (r_tube * 0.72), -cos_a * (r_tube * 0.72) + y_center_offset, z_tube_top - 0.005))))

    for s in range(n_tube_seg):
        s_next = (s + 1) % n_tube_seg
        bm_finial.faces.new([t_bot[s], t_bot[s_next], t_mid[s_next], t_mid[s]])
        bm_finial.faces.new([t_mid[s], t_mid[s_next], t_lip[s_next], t_lip[s]])
        bm_finial.faces.new([t_lip[s], t_lip[s_next], t_inner[s_next], t_inner[s]])

    # 2D. Bronze Brow Piping (rim border)
    n_pipe = 36
    for s in range(n_pipe):
        a1 = s * 2.0 * math.pi / n_pipe
        a2 = (s + 1) * 2.0 * math.pi / n_pipe
        ca1, sa1 = math.cos(a1), math.sin(a1)
        ca2, sa2 = math.cos(a2), math.sin(a2)
        ry1 = (ry_front_max if ca1 >= 0 else ry_back_max) + 0.0042
        ry2 = (ry_front_max if ca2 >= 0 else ry_back_max) + 0.0042
        rx1, rx2 = rx_max + 0.0042, rx_max + 0.0042

        p1_top = head_pos + Vector((sa1 * rx1, -ca1 * ry1 + y_center_offset, 0.095))
        p1_bot = head_pos + Vector((sa1 * rx1, -ca1 * ry1 + y_center_offset, 0.089))
        p2_top = head_pos + Vector((sa2 * rx2, -ca2 * ry2 + y_center_offset, 0.095))
        p2_bot = head_pos + Vector((sa2 * rx2, -ca2 * ry2 + y_center_offset, 0.089))

        v1t = bm_finial.verts.new(p1_top)
        v1b = bm_finial.verts.new(p1_bot)
        v2t = bm_finial.verts.new(p2_top)
        v2b = bm_finial.verts.new(p2_bot)
        bm_finial.faces.new([v1b, v2b, v2t, v1t])

    bmesh.ops.recalc_face_normals(bm_finial, faces=bm_finial.faces)

    # =========================================================================
    # 3. Helmet_Steel_01_Plume: Volumetric Flowing Crimson Horsehair Plume (大紅長馬尾毛纓)
    # =========================================================================
    n_plume_steps = 18

    def plume_spine(t: float) -> tuple[Vector, float, float]:
        # Curves up out of the tube, backward and cascades down over the back aventail
        py = y_center_offset + 0.045 * t + 0.115 * (t ** 1.35)
        pz = z_tube_top + 0.018 * math.sin(t * math.pi) - 0.225 * (t ** 1.15)
        width = 0.007 + 0.042 * (math.sin(t * math.pi) ** 0.55) + 0.026 * t
        height = 0.007 + 0.024 * (math.sin(t * math.pi) ** 0.65) + 0.008 * (1.0 - t)
        return Vector((0.0, py, pz)), width, height

    # 3A. Central Volumetric Horsehair Plume Body
    n_ring = 8
    spine_rings = []
    for s in range(n_plume_steps):
        t = s / (n_plume_steps - 1)
        c_pos, w, h = plume_spine(t)
        t_next = min(1.0, t + 0.02)
        c_next, _, _ = plume_spine(t_next)
        tan_vec = (c_next - c_pos).normalized() if (c_next - c_pos).length > 1e-4 else Vector((0, 1, 0))
        side_vec = tan_vec.cross(Vector((0, 0, 1))).normalized()
        up_vec = side_vec.cross(tan_vec).normalized()

        ring_verts = []
        for r_i in range(n_ring):
            ang = r_i * 2.0 * math.pi / n_ring
            cos_r = math.cos(ang)
            sin_r = math.sin(ang)
            pt = head_pos + c_pos + side_vec * (cos_r * w * 0.5) + up_vec * (sin_r * h * 0.5)
            ring_verts.append(bm_plume.verts.new(pt))
        spine_rings.append(ring_verts)

    for s in range(n_plume_steps - 1):
        for r_i in range(n_ring):
            r_next = (r_i + 1) % n_ring
            bm_plume.faces.new([
                spine_rings[s][r_i],
                spine_rings[s][r_next],
                spine_rings[s + 1][r_next],
                spine_rings[s + 1][r_i],
            ])

    # Tip cap of central plume
    tip_vert = bm_plume.verts.new(head_pos + plume_spine(1.0)[0] + Vector((0, 0.012, -0.018)))
    for r_i in range(n_ring):
        r_next = (r_i + 1) % n_ring
        bm_plume.faces.new([spine_rings[-1][r_i], tip_vert, spine_rings[-1][r_next]])

    # 3B. Flanking Left and Right Cascading Horsehair Locks
    for side_sign in [-1.0, 1.0]:
        lock_rings = []
        for s in range(n_plume_steps):
            t = s / (n_plume_steps - 1)
            c_pos, w, h = plume_spine(t)
            offset_x = side_sign * (w * 0.55 + 0.005 * t)
            lock_pos = c_pos + Vector((offset_x, 0.004 * t, -0.010 * t))
            lock_w = w * 0.44
            lock_h = h * 0.42

            ring = []
            for r_i in range(6):
                ang = r_i * 2.0 * math.pi / 6
                pt = head_pos + lock_pos + Vector((math.cos(ang) * lock_w * 0.5, 0, math.sin(ang) * lock_h * 0.5))
                ring.append(bm_plume.verts.new(pt))
            lock_rings.append(ring)

        for s in range(n_plume_steps - 1):
            for r_i in range(6):
                r_next = (r_i + 1) % 6
                bm_plume.faces.new([
                    lock_rings[s][r_i],
                    lock_rings[s][r_next],
                    lock_rings[s + 1][r_next],
                    lock_rings[s + 1][r_i],
                ])

    bmesh.ops.recalc_face_normals(bm_plume, faces=bm_plume.faces)

    # =========================================================================
    # 4. Helmet_Steel_01_BeastEmblem: 3D Cast Bronze Taotie / Beast Mask (額前辟邪獸面)
    # =========================================================================
    emblem_center = head_pos + Vector((0.0, -ry_front_max - 0.010, 0.110))
    n_fwd = Vector((0.0, -0.98, 0.18)).normalized()
    n_up = Vector((0.0, 0.18, 0.98)).normalized()
    n_right = Vector((1.0, 0.0, 0.0))

    def tr_e(lx: float, ly: float, lz: float) -> Vector:
        return emblem_center + (n_right * lx + n_up * ly + n_fwd * lz)

    # 4A. Horns & Upper Cloud Crest (祥雲雙角)
    for s_sign in [-1.0, 1.0]:
        sx = s_sign
        h0 = bm_emblem.verts.new(tr_e(sx * 0.008, 0.016, 0.004))
        h1 = bm_emblem.verts.new(tr_e(sx * 0.016, 0.024, 0.006))
        h2 = bm_emblem.verts.new(tr_e(sx * 0.024, 0.034, 0.008))
        h3 = bm_emblem.verts.new(tr_e(sx * 0.030, 0.040, 0.006))

        h0_in = bm_emblem.verts.new(tr_e(sx * 0.004, 0.018, 0.003))
        h1_in = bm_emblem.verts.new(tr_e(sx * 0.010, 0.026, 0.004))
        h2_in = bm_emblem.verts.new(tr_e(sx * 0.016, 0.035, 0.005))
        h3_in = bm_emblem.verts.new(tr_e(sx * 0.022, 0.039, 0.004))

        bm_emblem.faces.new([h0, h1, h1_in, h0_in])
        bm_emblem.faces.new([h1, h2, h2_in, h1_in])
        bm_emblem.faces.new([h2, h3, h3_in, h2_in])

    # 4B. Forehead Central Ridge & Brow
    c_crest_top = bm_emblem.verts.new(tr_e(0.0, 0.028, 0.007))
    c_crest_mid = bm_emblem.verts.new(tr_e(0.0, 0.015, 0.009))
    c_crest_bot = bm_emblem.verts.new(tr_e(0.0, 0.005, 0.011))

    c_left_mid = bm_emblem.verts.new(tr_e(-0.010, 0.015, 0.007))
    c_right_mid = bm_emblem.verts.new(tr_e(0.010, 0.015, 0.007))
    c_left_top = bm_emblem.verts.new(tr_e(-0.006, 0.026, 0.005))
    c_right_top = bm_emblem.verts.new(tr_e(0.006, 0.026, 0.005))

    bm_emblem.faces.new([c_crest_top, c_right_top, c_right_mid, c_crest_mid])
    bm_emblem.faces.new([c_crest_top, c_crest_mid, c_left_mid, c_left_top])

    # 4C. Fierce Bulging Eyes & Eyebrow Arches (凸圓怒目)
    for s_sign in [-1.0, 1.0]:
        sx = s_sign
        eye_c = tr_e(sx * 0.014, 0.004, 0.008)
        norm_eye = (n_fwd * 0.88 + n_right * (sx * 0.35) + n_up * 0.20).normalized()
        add_brass_rivet(bm_emblem, eye_c, norm_eye, radius=0.0055, depth=0.0040, n_segs=8)

        br0 = bm_emblem.verts.new(tr_e(sx * 0.006, 0.011, 0.008))
        br1 = bm_emblem.verts.new(tr_e(sx * 0.014, 0.013, 0.010))
        br2 = bm_emblem.verts.new(tr_e(sx * 0.022, 0.009, 0.007))
        br0_d = bm_emblem.verts.new(tr_e(sx * 0.006, 0.008, 0.007))
        br1_d = bm_emblem.verts.new(tr_e(sx * 0.014, 0.009, 0.008))
        br2_d = bm_emblem.verts.new(tr_e(sx * 0.022, 0.006, 0.006))
        if s_sign == 1.0:
            bm_emblem.faces.new([br0, br1, br1_d, br0_d])
            bm_emblem.faces.new([br1, br2, br2_d, br1_d])
        else:
            bm_emblem.faces.new([br0, br0_d, br1_d, br1])
            bm_emblem.faces.new([br1, br1_d, br2_d, br2])

    # 4D. Snout / Broad Lion Nose (闊獅鼻)
    nose_tip = bm_emblem.verts.new(tr_e(0.0, -0.004, 0.013))
    nose_l = bm_emblem.verts.new(tr_e(-0.008, -0.005, 0.011))
    nose_r = bm_emblem.verts.new(tr_e(0.008, -0.005, 0.011))

    bm_emblem.faces.new([c_crest_bot, nose_r, nose_tip])
    bm_emblem.faces.new([c_crest_bot, nose_tip, nose_l])
    bm_emblem.faces.new([c_crest_bot, c_right_mid, nose_r])
    bm_emblem.faces.new([c_crest_bot, nose_l, c_left_mid])

    # 4E. Snarling Maw with Sharp Upper Fangs (怒目闊口利齒)
    lip_c = bm_emblem.verts.new(tr_e(0.0, -0.010, 0.010))
    lip_l = bm_emblem.verts.new(tr_e(-0.012, -0.010, 0.009))
    lip_r = bm_emblem.verts.new(tr_e(0.012, -0.010, 0.009))
    lip_l_wide = bm_emblem.verts.new(tr_e(-0.022, -0.012, 0.006))
    lip_r_wide = bm_emblem.verts.new(tr_e(0.022, -0.012, 0.006))

    bm_emblem.faces.new([nose_tip, nose_r, lip_r, lip_c])
    bm_emblem.faces.new([nose_tip, lip_c, lip_l, nose_l])
    bm_emblem.faces.new([nose_r, lip_r_wide, lip_r])
    bm_emblem.faces.new([nose_l, lip_l, lip_l_wide])

    fang_l_tip = bm_emblem.verts.new(tr_e(-0.012, -0.020, 0.008))
    fang_r_tip = bm_emblem.verts.new(tr_e(0.012, -0.020, 0.008))
    bm_emblem.faces.new([lip_l, lip_l_wide, fang_l_tip])
    bm_emblem.faces.new([lip_r, fang_r_tip, lip_r_wide])

    tooth_c_tip = bm_emblem.verts.new(tr_e(0.0, -0.015, 0.008))
    bm_emblem.faces.new([lip_l, lip_c, tooth_c_tip])
    bm_emblem.faces.new([lip_c, lip_r, tooth_c_tip])

    # 4F. Flared Whisker/Jowl Wing Plates (頰側鬃毛翼)
    for s_sign in [-1.0, 1.0]:
        sx = s_sign
        w_top = bm_emblem.verts.new(tr_e(sx * 0.024, 0.006, 0.005))
        w_mid = bm_emblem.verts.new(tr_e(sx * 0.034, -0.002, 0.006))
        w_bot = bm_emblem.verts.new(tr_e(sx * 0.030, -0.014, 0.004))
        w_in_t = bm_emblem.verts.new(tr_e(sx * 0.020, 0.002, 0.004))
        w_in_b = bm_emblem.verts.new(tr_e(sx * 0.020, -0.010, 0.004))

        if s_sign == 1.0:
            bm_emblem.faces.new([w_in_t, w_top, w_mid, w_in_b])
            bm_emblem.faces.new([w_in_b, w_mid, w_bot])
        else:
            bm_emblem.faces.new([w_in_t, w_in_b, w_mid, w_top])
            bm_emblem.faces.new([w_in_b, w_bot, w_mid])

    bmesh.ops.recalc_face_normals(bm_emblem, faces=bm_emblem.faces)
    bmesh.ops.solidify(bm_emblem, geom=bm_emblem.faces[:], thickness=0.0025)

    # =========================================================================
    # 5. Helmet_Steel_01_BrowBand: Arched Steel Brow Band with Ocular Curves (額弓鐵帶)
    # =========================================================================
    n_brow_segs = 36
    b_lower = []
    b_upper = []

    for j in range(n_brow_segs):
        ang = j * 2.0 * math.pi / n_brow_segs
        cos_a = math.cos(ang)
        sin_a = math.sin(ang)

        rx = rx_max + 0.0032
        ry = (ry_front_max if cos_a >= 0 else ry_back_max) + 0.0032

        z_top = 0.126
        z_bot = 0.092

        # Double ocular eyebrow arch over eyes on front face:
        if cos_a > 0.30 and 0.16 < abs(sin_a) < 0.75:
            ocular_lift = 0.014 * math.sin((abs(sin_a) - 0.16) / 0.59 * math.pi)
            z_bot += ocular_lift

        # Center dips slightly behind the beast emblem:
        if cos_a > 0.80 and abs(sin_a) <= 0.16:
            z_bot -= 0.004

        pt_b = head_pos + Vector((sin_a * rx, -cos_a * ry + y_center_offset, z_bot))
        pt_t = head_pos + Vector((sin_a * rx, -cos_a * ry + y_center_offset, z_top))

        b_lower.append(bm_brow.verts.new(pt_b))
        b_upper.append(bm_brow.verts.new(pt_t))

    for j in range(n_brow_segs):
        j_next = (j + 1) % n_brow_segs
        bm_brow.faces.new([b_lower[j], b_lower[j_next], b_upper[j_next], b_upper[j]])

    bmesh.ops.recalc_face_normals(bm_brow, faces=bm_brow.faces)
    bmesh.ops.solidify(bm_brow, geom=bm_brow.faces[:], thickness=0.0032)

    # =========================================================================
    # 6. Helmet_Steel_01_SideMedallions: Left and Right Sunburst-Lotus Boss Rosettes (兩側圓盤)
    # =========================================================================
    r_medallion = 0.016
    z_medallion = 0.118
    n_petals = 16

    for side_sign in [-1.0, 1.0]:
        med_center = head_pos + Vector((side_sign * (rx_max + 0.0052), y_center_offset, z_medallion))
        n_out = Vector((side_sign, 0.0, 0.0))
        n_tang_y = Vector((0.0, 1.0, 0.0))
        n_tang_z = Vector((0.0, 0.0, 1.0))

        # Concentric rings: outer scalloped petal rim, middle step, inner boss
        outer_rim = []
        mid_step = []
        inner_step = []

        for p in range(n_petals):
            a = p * 2.0 * math.pi / n_petals
            cos_p = math.cos(a)
            sin_p = math.sin(a)
            # Scalloped petal curvature
            r_outer = r_medallion * (1.0 + 0.08 * math.cos(8.0 * a))
            p_out = med_center + (n_tang_y * cos_p + n_tang_z * sin_p) * r_outer
            p_mid = med_center + (n_tang_y * cos_p + n_tang_z * sin_p) * (r_medallion * 0.68) + n_out * 0.0018
            p_in = med_center + (n_tang_y * cos_p + n_tang_z * sin_p) * (r_medallion * 0.38) + n_out * 0.0032

            outer_rim.append(bm_medallions.verts.new(p_out))
            mid_step.append(bm_medallions.verts.new(p_mid))
            inner_step.append(bm_medallions.verts.new(p_in))

        for p in range(n_petals):
            p_next = (p + 1) % n_petals
            if side_sign > 0:
                bm_medallions.faces.new([outer_rim[p], outer_rim[p_next], mid_step[p_next], mid_step[p]])
                bm_medallions.faces.new([mid_step[p], mid_step[p_next], inner_step[p_next], inner_step[p]])
            else:
                bm_medallions.faces.new([outer_rim[p], mid_step[p], mid_step[p_next], outer_rim[p_next]])
                bm_medallions.faces.new([mid_step[p], inner_step[p], inner_step[p_next], mid_step[p_next]])

        # Central boss rivet on medallion
        boss_center = med_center + n_out * 0.0036
        add_brass_rivet(bm_medallions, boss_center, n_out, radius=0.0046, depth=0.0032, n_segs=8)

    bmesh.ops.recalc_face_normals(bm_medallions, faces=bm_medallions.faces)

    # =========================================================================
    # 7. Helmet_Steel_01_Aventail: 4-Tier Dark Steel Lamellar Aventail (4層扎甲頓項)
    # =========================================================================
    z_av_bot = -0.036 if is_female else -0.045

    tiers = [
        {"z_top": 0.096, "z_bot": 0.062, "r_extra": 0.000},
        {"z_top": 0.066, "z_bot": 0.028, "r_extra": 0.003},
        {"z_top": 0.032, "z_bot": -0.006, "r_extra": 0.007},
        {"z_top": -0.002, "z_bot": z_av_bot, "r_extra": 0.014},
    ]

    flaps = [
        {"name": "left",  "start_deg": -135.0, "end_deg": -32.0,  "n_steps": 16},
        {"name": "right", "start_deg": 32.0,   "end_deg": 135.0,  "n_steps": 16},
        {"name": "back",  "start_deg": 138.0,  "end_deg": 222.0,  "n_steps": 14},
    ]

    for flap in flaps:
        for tier_idx, tier in enumerate(tiers):
            n_s = flap["n_steps"]
            t_verts_top = []
            t_verts_bot = []

            for s in range(n_s):
                t_f = s / (n_s - 1)
                deg = flap["start_deg"] + (flap["end_deg"] - flap["start_deg"]) * t_f
                ang = math.radians(deg)
                cos_a = math.cos(ang)
                sin_a = math.sin(ang)

                rx = rx_max + 0.004 + tier["r_extra"]
                ry = (ry_front_max if cos_a >= 0 else ry_back_max) + 0.004 + tier["r_extra"]

                if tier_idx == 3:
                    flare = 0.012
                    rx += flare * (0.6 if abs(sin_a) > 0.5 else 0.3)
                    ry += flare

                plate_wave = 0.0016 * math.cos(ang * 16.0)
                rx += plate_wave
                ry += plate_wave

                pt_top = head_pos + Vector((sin_a * rx, -cos_a * ry + y_center_offset, tier["z_top"]))
                pt_bot = head_pos + Vector((sin_a * rx, -cos_a * ry + y_center_offset, tier["z_bot"]))

                t_verts_top.append(bm_aventail.verts.new(pt_top))
                t_verts_bot.append(bm_aventail.verts.new(pt_bot))

            for s in range(n_s - 1):
                bm_aventail.faces.new([
                    t_verts_bot[s],
                    t_verts_bot[s + 1],
                    t_verts_top[s + 1],
                    t_verts_top[s],
                ])

    bmesh.ops.recalc_face_normals(bm_aventail, faces=bm_aventail.faces)
    bmesh.ops.solidify(bm_aventail, geom=bm_aventail.faces[:], thickness=0.0030)

    # =========================================================================
    # 8. Helmet_Steel_01_CordTassels: Red Braided Cords, Overlap Knots & Dangling Tassels
    # =========================================================================
    # 3 columns on left cheek, 3 columns on right cheek, 4 columns on rear neck
    cord_column_angles = [
        # Left cheek columns
        -115.0, -85.0, -55.0,
        # Right cheek columns
        55.0, 85.0, 115.0,
        # Rear neck columns
        152.0, 172.0, 188.0, 208.0,
    ]

    cord_half_w = 0.0018
    for deg in cord_column_angles:
        ang = math.radians(deg)
        cos_a = math.cos(ang)
        sin_a = math.sin(ang)

        # 8A. Vertical Braided Cord Ribbon running down from Tier 1 to Tier 4
        cord_pts = []
        for tier_idx, tier in enumerate(tiers):
            rx = rx_max + 0.005 + tier["r_extra"] + 0.0028
            ry = (ry_front_max if cos_a >= 0 else ry_back_max) + 0.005 + tier["r_extra"] + 0.0028
            if tier_idx == 3:
                flare = 0.012
                rx += flare * (0.6 if abs(sin_a) > 0.5 else 0.3)
                ry += flare

            pt_top = head_pos + Vector((sin_a * rx, -cos_a * ry + y_center_offset, tier["z_top"]))
            pt_bot = head_pos + Vector((sin_a * rx, -cos_a * ry + y_center_offset, tier["z_bot"]))
            cord_pts.append(pt_top)
            cord_pts.append(pt_bot)

            # Small decorative knot at tier overlap (between tier_idx and tier_idx+1)
            if tier_idx < 3:
                knot_p = head_pos + Vector((sin_a * (rx + 0.001), -cos_a * (ry + 0.001) + y_center_offset, tier["z_bot"] + 0.002))
                norm_out = Vector((sin_a, -cos_a, 0.0)).normalized()
                add_brass_rivet(bm_tassels, knot_p, norm_out, radius=0.0028, depth=0.0020, n_segs=6)

        # Build ribbon quad strip for the cord column
        c_l = []
        c_r = []
        tan_x = -cos_a
        tan_y = -sin_a
        for pt in cord_pts:
            c_l.append(bm_tassels.verts.new(pt + Vector((tan_x * cord_half_w, tan_y * cord_half_w, 0))))
            c_r.append(bm_tassels.verts.new(pt - Vector((tan_x * cord_half_w, tan_y * cord_half_w, 0))))

        for idx in range(len(cord_pts) - 1):
            bm_tassels.faces.new([c_l[idx], c_l[idx + 1], c_r[idx + 1], c_r[idx]])

        # 8B. Dangling Tassel at Bottom of Column (terminated below Tier 4)
        tassel_base = cord_pts[-1]
        add_tassel(
            bm=bm_tassels,
            knot_center=tassel_base,
            hang_dir=Vector((0.0, 0.0, -1.0)),
            cap_radius=0.0032,
            cap_height=0.0050,
            tassel_len=0.0240,
            flare_radius=0.0065,
            n_segs=8,
        )

    bmesh.ops.recalc_face_normals(bm_tassels, faces=bm_tassels.faces)

    # =========================================================================
    # 9. Helmet_Steel_01_Strap & Buckle: Leather Chin Strap & Bronze Roller Buckle
    # =========================================================================
    chin_z = -0.046 if is_female else -0.052
    strap_pts = [
        head_pos + Vector((-0.070, -0.040, -0.015)),
        head_pos + Vector((-0.052, -0.070, -0.038)),
        head_pos + Vector((0.000, -0.088, chin_z)),
        head_pos + Vector((0.052, -0.070, -0.038)),
        head_pos + Vector((0.070, -0.040, -0.015)),
    ]

    strap_w = 0.009
    s_v0 = []
    s_v1 = []
    for i, pt in enumerate(strap_pts):
        tang = (strap_pts[min(len(strap_pts) - 1, i + 1)] - strap_pts[max(0, i - 1)]).normalized()
        norm = (pt - head_pos).normalized()
        binorm = tang.cross(norm).normalized()
        s_v0.append(bm_strap.verts.new(pt - binorm * (strap_w * 0.5)))
        s_v1.append(bm_strap.verts.new(pt + binorm * (strap_w * 0.5)))

    for i in range(len(strap_pts) - 1):
        bm_strap.faces.new([s_v0[i], s_v0[i + 1], s_v1[i + 1], s_v1[i]])

    bmesh.ops.recalc_face_normals(bm_strap, faces=bm_strap.faces)
    bmesh.ops.solidify(bm_strap, geom=bm_strap.faces[:], thickness=0.0022)

    # Buckle on left jaw
    b_pos = strap_pts[1]
    b_tang = (strap_pts[2] - strap_pts[0]).normalized()
    b_norm = (b_pos - head_pos).normalized()
    b_side = b_tang.cross(b_norm).normalized()

    bw, bh, bt = 0.009, 0.007, 0.0022
    p_c = [
        b_pos - b_side * (bw * 0.5) - b_tang * (bh * 0.5),
        b_pos + b_side * (bw * 0.5) - b_tang * (bh * 0.5),
        b_pos + b_side * (bw * 0.5) + b_tang * (bh * 0.5),
        b_pos - b_side * (bw * 0.5) + b_tang * (bh * 0.5),
    ]
    bv = [bm_buckle.verts.new(p) for p in p_c]
    bv_out = [bm_buckle.verts.new(p + b_norm * bt) for p in p_c]
    for i in range(4):
        i_next = (i + 1) % 4
        bm_buckle.faces.new([bv[i], bv[i_next], bv_out[i_next], bv_out[i]])

    bmesh.ops.recalc_face_normals(bm_buckle, faces=bm_buckle.faces)

    # =========================================================================
    # 10. Helmet_Steel_01_Lining: Quilted Diamond Felt Interior Lining (防震軟布內襯)
    # =========================================================================
    n_lin_lat = 10
    n_lin_lon = 24
    lin_grid = []
    z_lin_top = z_apex - 0.006
    z_lin_bot = 0.090

    for i in range(n_lin_lat):
        v = i / (n_lin_lat - 1)
        row = []
        pz = z_lin_top - (z_lin_top - z_lin_bot) * (v ** 0.95)
        rad_p = 0.0 if v == 0 else math.sin(v * math.pi * 0.5) ** 0.46

        for j in range(n_lin_lon):
            ang = j * 2.0 * math.pi / n_lin_lon
            cos_a = math.cos(ang)
            sin_a = math.sin(ang)
            rx = rx_max * 0.978
            ry = (ry_front_max if cos_a >= 0 else ry_back_max) * 0.978
            row.append(bm_lining.verts.new(head_pos + Vector((
                sin_a * rx * rad_p,
                -cos_a * ry * rad_p + y_center_offset,
                pz,
            ))))
        lin_grid.append(row)

    lin_apex = bm_lining.verts.new(head_pos + Vector((0.0, y_center_offset, z_lin_top)))
    for j in range(n_lin_lon):
        j_next = (j + 1) % n_lin_lon
        bm_lining.faces.new([lin_apex, lin_grid[1][j], lin_grid[1][j_next]])

    for i in range(1, n_lin_lat - 1):
        for j in range(n_lin_lon):
            j_next = (j + 1) % n_lin_lon
            bm_lining.faces.new([
                lin_grid[i][j],
                lin_grid[i + 1][j],
                lin_grid[i + 1][j_next],
                lin_grid[i][j_next],
            ])

    bmesh.ops.recalc_face_normals(bm_lining, faces=bm_lining.faces)
    bmesh.ops.solidify(bm_lining, geom=bm_lining.faces[:], thickness=0.0020)

    # =========================================================================
    # Assemble Rigid Components skinned to J_Bip_C_Head
    # =========================================================================
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
            obj["worldgoing_component_slot"] = slot
            obj["worldgoing_visual_id"] = vid
            return obj
        create_rigid_fn = default_create_rigid

    parts.append(create_rigid_fn("Helmet_Steel_01_Dome", bm_dome, mat_steel_dark, "J_Bip_C_Head", "helmet", visual_id, armature))
    parts.append(create_rigid_fn("Helmet_Steel_01_Finial", bm_finial, mat_bronze, "J_Bip_C_Head", "helmet", visual_id, armature))
    parts.append(create_rigid_fn("Helmet_Steel_01_Plume", bm_plume, mat_plume, "J_Bip_C_Head", "helmet", visual_id, armature))
    parts.append(create_rigid_fn("Helmet_Steel_01_BeastEmblem", bm_emblem, mat_bronze, "J_Bip_C_Head", "helmet", visual_id, armature))
    parts.append(create_rigid_fn("Helmet_Steel_01_BrowBand", bm_brow, mat_steel_dark, "J_Bip_C_Head", "helmet", visual_id, armature))
    parts.append(create_rigid_fn("Helmet_Steel_01_SideMedallions", bm_medallions, mat_bronze, "J_Bip_C_Head", "helmet", visual_id, armature))
    parts.append(create_rigid_fn("Helmet_Steel_01_Aventail", bm_aventail, mat_lamellar, "J_Bip_C_Head", "helmet", visual_id, armature))
    parts.append(create_rigid_fn("Helmet_Steel_01_CordTassels", bm_tassels, mat_cord, "J_Bip_C_Head", "helmet", visual_id, armature))
    parts.append(create_rigid_fn("Helmet_Steel_01_Strap", bm_strap, mat_leather, "J_Bip_C_Head", "helmet", visual_id, armature))
    parts.append(create_rigid_fn("Helmet_Steel_01_Buckle", bm_buckle, mat_bronze, "J_Bip_C_Head", "helmet", visual_id, armature))
    parts.append(create_rigid_fn("Helmet_Steel_01_Lining", bm_lining, mat_lining, "J_Bip_C_Head", "helmet", visual_id, armature))

    return parts
