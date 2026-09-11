"""Build authentic, organic, historical Mingguang Armor (Armor_Mingguang_01 / 明光鎧).

Faithfully matching traditional Chinese armor craftsmanship and the 3D reference sheet:
- Eliminates all robotic / mecha / industrial appearances.
- High padded/plated gorget collar (護頸領圈) with golden rivets enclosing the inner crossover V-collar (交領).
- Deep midnight navy brocade under-robe with full sleeves and fitted dark trousers.
- Tailored black leather cuirass vest with deep U-neck scoop (身甲開弧領口).
- FRONT: Twin shallow-convex polished silver chest mirrors with dragon boss and studded leather bezel (雙明光胸鏡).
- BACK: Twin shallow-convex polished silver back mirrors with dragon boss and studded leather bezel (雙明光背鏡).
- Continuous tiered shingled fish-scale lamellae (魚鱗札甲) across abdomen, pauldrons, skirts, and greaves (zero gaps).
- Prominent sculpted silver dragon/lion beast belly buckle (腹吞獸首 / 饕餮吞口) biting the belt ring.
- Organic silver beast pauldron caps (吞肩獸首) with 3 articulated scalloped fish-scale tiers.
- Curved silver lamellar forearm bracers (護臂) with leather closure straps.
- Heavy studded black leather belt.
- Front center apron of vertical black leather pteruges (蔽膝 / 前排鬚) with 3D silver filigree ruyi tip plaques and gold rivets.
- Side and rear tiered fish-scale lamellar skirts (吊腿 / 裙甲) properly skinned to hips & legs.
- Draped columnar pleated brocade fabric under-skirt.
- Curved silver lamellar shin guards (脛甲) with leather calf straps, strictly preserving separate boot slots.
- Strictly NO helmet and NO boots (per user requirement).
"""

import math
import bmesh
import bpy
from mathutils import Vector, Matrix


def get_material(
    name: str,
    color: tuple[float, float, float],
    metallic: float = 0.0,
    roughness: float = 0.50,
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
    else:
        if mat.use_nodes and mat.node_tree:
            bsdf = mat.node_tree.nodes.get("Principled BSDF")
            if bsdf:
                bsdf.inputs["Base Color"].default_value = (*color, 1.0)
                bsdf.inputs["Roughness"].default_value = roughness
                if "Metallic" in bsdf.inputs:
                    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def add_dome_rivet(
    bm: bmesh.types.BMesh,
    center: Vector,
    normal: Vector,
    radius: float = 0.0030,
    depth: float = 0.0020,
    n_segs: int = 8,
):
    """Add a half-sphere dome metal rivet."""
    z_axis = normal.normalized()
    up = Vector((0, 0, 1)) if abs(z_axis.z) < 0.9 else Vector((1, 0, 0))
    x_axis = up.cross(z_axis).normalized()
    y_axis = z_axis.cross(x_axis).normalized()

    tip = bm.verts.new(center + z_axis * depth)
    mid_ring = []
    base_ring = []
    for s in range(n_segs):
        ang = s * (2.0 * math.pi / n_segs)
        co_mid = center + (x_axis * math.cos(ang) + y_axis * math.sin(ang)) * (radius * 0.70) + z_axis * (depth * 0.65)
        mid_ring.append(bm.verts.new(co_mid))
        co_base = center + (x_axis * math.cos(ang) + y_axis * math.sin(ang)) * radius
        base_ring.append(bm.verts.new(co_base))

    for s in range(n_segs):
        s_next = (s + 1) % n_segs
        bm.faces.new([tip, mid_ring[s], mid_ring[s_next]])
        bm.faces.new([mid_ring[s], base_ring[s], base_ring[s_next], mid_ring[s_next]])


def add_filigree_tip(
    bm: bmesh.types.BMesh,
    center: Vector,
    normal: Vector,
    width: float = 0.022,
    height: float = 0.028,
    thickness: float = 0.0030,
):
    """3D ornamental openwork cloud / ruyi filigree plaque for pteruges tips."""
    z_axis = normal.normalized()
    up = Vector((0, 0, 1)) if abs(z_axis.z) < 0.9 else Vector((1, 0, 0))
    x_axis = up.cross(z_axis).normalized()
    y_axis = z_axis.cross(x_axis).normalized()

    w2 = width * 0.5
    h2 = height * 0.5

    def tr_pt(x: float, y: float, z: float) -> Vector:
        return center + x_axis * x + y_axis * y + z_axis * z

    front_pts = [
        tr_pt(-w2, h2, thickness),
        tr_pt(w2, h2, thickness),
        tr_pt(w2 * 1.12, 0.0, thickness),
        tr_pt(w2 * 0.50, -h2 * 0.70, thickness),
        tr_pt(0.0, -h2, thickness * 1.25),
        tr_pt(-w2 * 0.50, -h2 * 0.70, thickness),
        tr_pt(-w2 * 1.12, 0.0, thickness),
    ]
    back_pts = [
        tr_pt(-w2, h2, 0.0),
        tr_pt(w2, h2, 0.0),
        tr_pt(w2 * 1.12, 0.0, 0.0),
        tr_pt(w2 * 0.50, -h2 * 0.70, 0.0),
        tr_pt(0.0, -h2, 0.0),
        tr_pt(-w2 * 0.50, -h2 * 0.70, 0.0),
        tr_pt(-w2 * 1.12, 0.0, 0.0),
    ]

    v_f = [bm.verts.new(p) for p in front_pts]
    v_b = [bm.verts.new(p) for p in back_pts]
    v_c = bm.verts.new(tr_pt(0.0, 0.0, thickness * 1.5))

    n_pts = len(v_f)
    for i in range(n_pts):
        i_nxt = (i + 1) % n_pts
        bm.faces.new([v_c, v_f[i], v_f[i_nxt]])
        bm.faces.new([v_f[i], v_b[i], v_b[i_nxt], v_f[i_nxt]])
    bm.faces.new([v_b[0], v_b[6], v_b[5], v_b[4], v_b[3], v_b[2], v_b[1]])


def add_beast_face_organic(
    bm: bmesh.types.BMesh,
    center: Vector,
    forward: Vector,
    up: Vector,
    scale: float = 0.038,
):
    """Sculpted 3D ferocious silver lion/taotie beast head (饕餮吞口/吞肩獸首).

    Crafted with organic, curved contours, sweeping brow horns, and open fanged jaws.
    """
    n_fwd = forward.normalized()
    n_up = up.normalized()
    n_right = n_fwd.cross(n_up).normalized()

    def tr_e(x: float, y: float, z: float) -> Vector:
        return center + n_right * (x * scale) + n_up * (y * scale) + n_fwd * (z * scale)

    # Forehead Crest & Sweeping Horns
    c_top = bm.verts.new(tr_e(0.0, 0.88, 0.32))
    c_mid = bm.verts.new(tr_e(0.0, 0.50, 0.52))
    c_bot = bm.verts.new(tr_e(0.0, 0.20, 0.58))

    c_l_mid = bm.verts.new(tr_e(-0.42, 0.48, 0.38))
    c_r_mid = bm.verts.new(tr_e(0.42, 0.48, 0.38))
    c_l_top = bm.verts.new(tr_e(-0.32, 0.82, 0.26))
    c_r_top = bm.verts.new(tr_e(0.32, 0.82, 0.26))

    bm.faces.new([c_top, c_r_top, c_r_mid, c_mid])
    bm.faces.new([c_top, c_mid, c_l_mid, c_l_top])

    # Curved Horns
    for s_sign in [-1.0, 1.0]:
        sx = s_sign
        h_b1 = bm.verts.new(tr_e(sx * 0.24, 0.78, 0.28))
        h_b2 = bm.verts.new(tr_e(sx * 0.38, 0.85, 0.22))
        h_m1 = bm.verts.new(tr_e(sx * 0.52, 1.05, 0.15))
        h_m2 = bm.verts.new(tr_e(sx * 0.64, 1.12, 0.10))
        h_tip = bm.verts.new(tr_e(sx * 0.52, 1.28, 0.04))

        bm.faces.new([h_b1, h_b2, h_m2, h_m1])
        bm.faces.new([h_m1, h_m2, h_tip])

    # Brow Arches & Eyes
    for s_sign in [-1.0, 1.0]:
        sx = s_sign
        b_in = bm.verts.new(tr_e(sx * 0.10, 0.38, 0.58))
        b_out = bm.verts.new(tr_e(sx * 0.48, 0.40, 0.42))
        e_up = bm.verts.new(tr_e(sx * 0.26, 0.34, 0.62))
        e_dn = bm.verts.new(tr_e(sx * 0.26, 0.16, 0.60))
        e_pupil = bm.verts.new(tr_e(sx * 0.26, 0.24, 0.70))

        bm.faces.new([b_in, e_up, b_out])
        bm.faces.new([e_up, e_pupil, b_out])
        bm.faces.new([b_in, e_pupil, e_up])
        bm.faces.new([b_in, e_dn, e_pupil])
        bm.faces.new([e_dn, b_out, e_pupil])

    # Flared Lion Snout
    n_bridge = bm.verts.new(tr_e(0.0, 0.22, 0.66))
    n_tip = bm.verts.new(tr_e(0.0, 0.05, 0.80))
    n_l = bm.verts.new(tr_e(-0.22, 0.03, 0.74))
    n_r = bm.verts.new(tr_e(0.22, 0.03, 0.74))

    bm.faces.new([c_bot, n_bridge, n_l])
    bm.faces.new([c_bot, n_r, n_bridge])
    bm.faces.new([n_bridge, n_tip, n_l])
    bm.faces.new([n_bridge, n_r, n_tip])

    # Gaping Fanged Mouth / 吞口
    j_l_mid = bm.verts.new(tr_e(-0.48, -0.14, 0.58))
    j_r_mid = bm.verts.new(tr_e(0.48, -0.14, 0.58))
    lip_c = bm.verts.new(tr_e(0.0, -0.15, 0.72))
    lip_l = bm.verts.new(tr_e(-0.30, -0.15, 0.66))
    lip_r = bm.verts.new(tr_e(0.30, -0.15, 0.66))

    bm.faces.new([n_tip, lip_c, lip_l, n_l])
    bm.faces.new([n_tip, n_r, lip_r, lip_c])
    bm.faces.new([n_l, lip_l, j_l_mid])
    bm.faces.new([n_r, j_r_mid, lip_r])

    # Fangs
    for s_sign in [-1.0, 1.0]:
        sx = s_sign
        f_b1 = bm.verts.new(tr_e(sx * 0.22, -0.15, 0.66))
        f_b2 = bm.verts.new(tr_e(sx * 0.34, -0.15, 0.62))
        f_tip = bm.verts.new(tr_e(sx * 0.28, -0.38, 0.58))
        bm.faces.new([f_b1, f_b2, f_tip])

    # Whisker & Mane Flanges
    for s_sign in [-1.0, 1.0]:
        sx = s_sign
        m_t1 = bm.verts.new(tr_e(sx * 0.46, 0.20, 0.35))
        m_t2 = bm.verts.new(tr_e(sx * 0.76, 0.10, 0.18))
        m_b1 = bm.verts.new(tr_e(sx * 0.54, -0.10, 0.38))
        m_b2 = bm.verts.new(tr_e(sx * 0.84, -0.18, 0.16))
        m_tip = bm.verts.new(tr_e(sx * 0.66, -0.36, 0.20))

        bm.faces.new([m_t1, m_t2, m_b2, m_b1])
        bm.faces.new([m_b1, m_b2, m_tip])


def build_shingled_fishscale_mesh(
    bm_scales: bmesh.types.BMesh,
    top_z: float,
    bot_z: float,
    n_tiers: int,
    n_cols: int,
    get_span_pts_func,
    scale_tongue_len: float = 0.0055,
    ridge_out: float = 0.0030,
):
    """Builds authentic tiered shingled fish-scale lamellae (魚鱗札甲片).

    Tiers continuously overlap in Z with zero gaps.
    Each column features a 3D scalloped tongue and specular central ridge.
    """
    z_step = (top_z - bot_z) / float(n_tiers)
    overlap = 0.006

    for t in range(n_tiers):
        t_top = top_z - t * z_step
        t_bot = t_top - z_step - overlap
        z_mid = (t_top + t_bot) * 0.5

        out_offset = (n_tiers - t) * 0.0022

        v_bnd_top = []
        v_bnd_mid = []

        for i in range(n_cols + 1):
            u = i / float(n_cols)
            pt_t, _, norm_t = get_span_pts_func(u, t_top, t_bot)
            pt_m, _, norm_m = get_span_pts_func(u, z_mid, z_mid)
            v_bnd_top.append(bm_scales.verts.new(pt_t + norm_t * out_offset))
            v_bnd_mid.append(bm_scales.verts.new(pt_m + norm_m * out_offset))

        for s in range(n_cols):
            u_m = (s + 0.5) / float(n_cols)
            pt_tm, _, norm_tm = get_span_pts_func(u_m, t_top, t_bot)
            pt_mm, _, norm_mm = get_span_pts_func(u_m, z_mid, z_mid)
            pt_bt, _, norm_bt = get_span_pts_func(u_m, t_bot - scale_tongue_len, t_bot - scale_tongue_len)

            v_tm = bm_scales.verts.new(pt_tm + norm_tm * out_offset)
            v_mc = bm_scales.verts.new(pt_mm + norm_mm * (out_offset + ridge_out))
            v_bt = bm_scales.verts.new(pt_bt + norm_bt * out_offset)

            v_tl = v_bnd_top[s]
            v_tr = v_bnd_top[s + 1]
            v_ml = v_bnd_mid[s]
            v_mr = v_bnd_mid[s + 1]

            bm_scales.faces.new([v_tl, v_tm, v_mc, v_ml])
            bm_scales.faces.new([v_tm, v_tr, v_mr, v_mc])
            bm_scales.faces.new([v_ml, v_mc, v_bt])
            bm_scales.faces.new([v_mc, v_mr, v_bt])


def build_pteruges_ring(
    bm_leather: bmesh.types.BMesh,
    bm_silver: bmesh.types.BMesh,
    bm_studs: bmesh.types.BMesh,
    z_top: float,
    z_bot: float,
    rx: float,
    ry_f: float,
    ry_b: float,
    strip_w: float = 0.022,
    angle_ranges: list = None,
    side_sign: float = 1.0,
):
    """Build draped vertical leather pteruges strips with silver tips and gold rivets."""
    if angle_ranges is None:
        angle_ranges = [(-0.40, 0.40, 8)]

    pt_len = z_top - z_bot

    for (ang_start, ang_end, n_st) in angle_ranges:
        for s_idx in range(n_st):
            u = s_idx / float(max(1, n_st - 1)) if n_st > 1 else 0.5
            ang = (ang_start + (ang_end - ang_start) * u) * math.pi
            rx_pos = math.sin(ang) * rx * side_sign
            ry_pos = -math.cos(ang) * ry_f if math.cos(ang) > 0 else -math.cos(ang) * ry_b

            strip_verts = []
            n_seg_v = 5
            for vi in range(n_seg_v):
                v_frac = vi / float(n_seg_v - 1)
                pz = z_top - pt_len * v_frac
                vx = rx_pos * (1.0 + 0.012 * v_frac)
                vy = ry_pos * (1.0 + 0.012 * v_frac)
                strip_verts.append((
                    bm_leather.verts.new((vx - strip_w * 0.48, vy, pz)),
                    bm_leather.verts.new((vx + strip_w * 0.48, vy, pz)),
                ))

            for vi in range(n_seg_v - 1):
                bm_leather.faces.new([
                    strip_verts[vi][0],
                    strip_verts[vi][1],
                    strip_verts[vi + 1][1],
                    strip_verts[vi + 1][0],
                ])

            norm_pt = Vector((math.sin(ang) * side_sign, -math.cos(ang) if math.cos(ang) > 0 else 0.5, 0.0)).normalized()
            for r_vi in [1, 2]:
                pt_rv = (strip_verts[r_vi][0].co + strip_verts[r_vi][1].co) * 0.5
                add_dome_rivet(bm_studs, pt_rv, norm_pt, radius=0.0028, depth=0.0018, n_segs=8)

            tip_pt = (strip_verts[-1][0].co + strip_verts[-1][1].co) * 0.5
            add_filigree_tip(bm_silver, tip_pt, norm_pt, width=strip_w * 1.10, height=0.026, thickness=0.0030)


def build_columnar_pleated_skirt(
    bm: bmesh.types.BMesh,
    z_top: float,
    z_bot: float,
    rx_top: float,
    ry_top: float,
    rx_bot: float,
    ry_bot: float,
    n_pleats: int = 32,
    pleat_depth: float = 0.007,
):
    """Build an authentic draped vertical pleated fabric robe skirt."""
    n_pts = n_pleats * 2
    top_ring = []
    bot_ring = []

    for i in range(n_pts):
        ang = i * (2.0 * math.pi / n_pts)
        is_inner = (i % 2 == 1)
        r_top_adj = 1.0 - (pleat_depth / max(1e-4, rx_top)) if is_inner else 1.0
        r_bot_adj = 1.0 - (pleat_depth * 1.1 / max(1e-4, rx_bot)) if is_inner else 1.0

        px_t = math.sin(ang) * (rx_top * r_top_adj)
        py_t = math.cos(ang) * (ry_top * r_top_adj)
        px_b = math.sin(ang) * (rx_bot * r_bot_adj)
        py_b = math.cos(ang) * (ry_bot * r_bot_adj)

        top_ring.append(bm.verts.new((px_t, py_t, z_top)))
        bot_ring.append(bm.verts.new((px_b, py_b, z_bot)))

    for i in range(n_pts):
        i_next = (i + 1) % n_pts
        bm.faces.new([top_ring[i], top_ring[i_next], bot_ring[i_next], bot_ring[i]])


def add_relief_ribbon(
    bm: bmesh.types.BMesh,
    center: Vector,
    x_axis: Vector,
    y_axis: Vector,
    normal: Vector,
    points: list[tuple[float, float]],
    width: float = 0.006,
    height: float = 0.006,
):
    """Build a raised, ribbon-like cloud/dragon line on a mirror plate."""
    if len(points) < 2:
        return
    front = []
    back = []
    for idx, (px, py) in enumerate(points):
        if idx == 0:
            tangent = Vector((points[1][0] - px, points[1][1] - py))
        elif idx == len(points) - 1:
            tangent = Vector((px - points[idx - 1][0], py - points[idx - 1][1]))
        else:
            tangent = Vector((points[idx + 1][0] - points[idx - 1][0], points[idx + 1][1] - points[idx - 1][1]))
        if tangent.length < 1e-5:
            tangent = Vector((1.0, 0.0))
        tangent.normalize()
        perpendicular = Vector((-tangent.y, tangent.x))
        p_l = center + x_axis * (px + perpendicular.x * width * 0.5) + y_axis * (py + perpendicular.y * width * 0.5)
        p_r = center + x_axis * (px - perpendicular.x * width * 0.5) + y_axis * (py - perpendicular.y * width * 0.5)
        back.extend([bm.verts.new(p_l + normal * (height * 0.35)), bm.verts.new(p_r + normal * (height * 0.35))])
        front.extend([bm.verts.new(p_l + normal * height), bm.verts.new(p_r + normal * height)])
    for idx in range(len(points) - 1):
        base = idx * 2
        next_base = (idx + 1) * 2
        bm.faces.new([front[base], front[next_base], front[next_base + 1], front[base + 1]])
        bm.faces.new([front[base + 1], front[next_base + 1], back[next_base + 1], back[base + 1]])
        bm.faces.new([front[next_base], front[base], back[base], back[next_base]])


def add_mirror_dragon_relief(
    bm: bmesh.types.BMesh,
    center: Vector,
    normal: Vector,
    scale: float,
):
    """Add a readable raised cloud-dragon curl and pearl to a Mingguang mirror."""
    z_axis = normal.normalized()
    up = Vector((0.0, 0.0, 1.0)) if abs(z_axis.z) < 0.9 else Vector((1.0, 0.0, 0.0))
    x_axis = up.cross(z_axis).normalized()
    y_axis = z_axis.cross(x_axis).normalized()
    dragon_path = [
        (-0.72, -0.10), (-0.58, 0.24), (-0.28, 0.42), (0.08, 0.33),
        (0.38, 0.08), (0.48, -0.22), (0.28, -0.40), (-0.02, -0.35),
        (-0.20, -0.15), (-0.06, 0.02), (0.18, 0.05),
    ]
    add_relief_ribbon(
        bm,
        center + z_axis * 0.004,
        x_axis,
        y_axis,
        z_axis,
        [(px * scale, py * scale) for px, py in dragon_path],
        width=scale * 0.12,
        height=scale * 0.105,
    )
    pearl = center + z_axis * (scale * 0.105)
    add_dome_rivet(bm, pearl, z_axis, radius=scale * 0.105, depth=scale * 0.085, n_segs=10)


def build_curved_front_shell(
    bm: bmesh.types.BMesh,
    top_z: float,
    bot_z: float,
    top_rx: float,
    top_ry: float,
    bot_rx: float,
    bot_ry: float,
    n_lat: int = 6,
    n_lon: int = 18,
    y_offset: float = -0.006,
):
    """Build a thin dark curved backing behind a front lamellar field."""
    rows = []
    for i in range(n_lat):
        v = i / float(max(1, n_lat - 1))
        z = top_z + (bot_z - top_z) * v
        rx = top_rx + (bot_rx - top_rx) * v
        ry = top_ry + (bot_ry - top_ry) * v
        row = []
        for j in range(n_lon):
            frac = (j / float(max(1, n_lon - 1)) - 0.5) * 2.0
            ang = frac * (math.pi * 0.44)
            row.append(bm.verts.new((math.sin(ang) * rx, -math.cos(ang) * ry + y_offset, z)))
        rows.append(row)
    for i in range(n_lat - 1):
        for j in range(n_lon - 1):
            bm.faces.new([rows[i][j], rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j]])


def make_mingguang_armor(
    armature: bpy.types.Object,
    source_raw_body: bpy.types.Object = None,
    is_female: bool = False,
    create_rigid_fn=None,
) -> list[bpy.types.Object]:
    """Generate the full authentic 3D Mingguang Armor (Armor_Mingguang_01) matching reference."""
    parts: list[bpy.types.Object] = []
    visual_id = "armor_mingguang_01"

    # Authentic historical materials
    mat_silver = get_material(
        "Worldgoing_Mingguang_Silver",
        (0.42, 0.48, 0.56),
        metallic=0.78,
        roughness=0.34,
    )
    mat_silver_relief = get_material(
        "Worldgoing_Mingguang_Silver_Relief",
        (0.72, 0.78, 0.88),
        metallic=0.84,
        roughness=0.24,
    )
    mat_leather = get_material(
        "Worldgoing_Mingguang_Leather",
        (0.010, 0.012, 0.018),
        metallic=0.0,
        roughness=0.68,
    )
    mat_gold = get_material(
        "Worldgoing_Mingguang_Gold",
        (0.62, 0.36, 0.09),
        metallic=0.82,
        roughness=0.30,
    )
    mat_navy_brocade = get_material(
        "Worldgoing_Mingguang_Brocade",
        (0.012, 0.022, 0.042),
        metallic=0.0,
        roughness=0.88,
    )
    mat_cloth = get_material(
        "Worldgoing_Mingguang_Cloth",
        (0.008, 0.010, 0.016),
        metallic=0.0,
        roughness=0.92,
    )

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

    # Bone anchors in T-Pose
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

    z_belt_top = waist_z + 0.024
    z_belt_bot = waist_z - 0.055

    # =========================================================================
    # 1. Underlayer Garments: Fitted Robe, Full Sleeves, Pants & Gorget Collar
    # =========================================================================
    if source_raw_body is not None:
        # A. Full Long Sleeves (Underlayer)
        obj_sleeves = source_raw_body.copy()
        obj_sleeves.name = "Armor_Mingguang_01_UnderSleeves"
        obj_sleeves.data = source_raw_body.data.copy()
        obj_sleeves.data.name = "Armor_Mingguang_01_UnderSleevesMesh"
        bpy.context.collection.objects.link(obj_sleeves)
        bm_sl = bmesh.new()
        bm_sl.from_mesh(obj_sleeves.data)
        bm_sl.faces.ensure_lookup_table()
        del_sl = [f for f in bm_sl.faces if f.material_index != 0 or abs(f.calc_center_median().x) < (ua_head_x - 0.015) or abs(f.calc_center_median().x) > (la_tail_x - 0.010)]
        bmesh.ops.delete(bm_sl, geom=del_sl, context="FACES")
        for v in bm_sl.verts:
            if v.link_faces and v.normal.length > 0:
                v.co += v.normal.normalized() * 0.0030
        loose_sl = [v for v in bm_sl.verts if not v.link_faces]
        bmesh.ops.delete(bm_sl, geom=loose_sl, context="VERTS")
        bmesh.ops.recalc_face_normals(bm_sl, faces=bm_sl.faces)
        bm_sl.to_mesh(obj_sleeves.data)
        bm_sl.free()
        obj_sleeves.data.update()
        obj_sleeves.data.materials.clear()
        obj_sleeves.data.materials.append(mat_navy_brocade)
        for p in obj_sleeves.data.polygons:
            p.use_smooth = True
        obj_sleeves.parent = armature
        obj_sleeves.matrix_parent_inverse = armature.matrix_world.inverted()
        obj_sleeves["worldgoing_character_part"] = True
        obj_sleeves["worldgoing_component_slot"] = "armor"
        obj_sleeves["worldgoing_visual_id"] = visual_id
        parts.append(obj_sleeves)

        # B. Dark Fitted Pants (Underlayer)
        obj_pants = source_raw_body.copy()
        obj_pants.name = "Armor_Mingguang_01_Underlayer_Pants"
        obj_pants.data = source_raw_body.data.copy()
        obj_pants.data.name = "Armor_Mingguang_01_Underlayer_PantsMesh"
        bpy.context.collection.objects.link(obj_pants)
        bm_p = bmesh.new()
        bm_p.from_mesh(obj_pants.data)
        bm_p.faces.ensure_lookup_table()
        z_pants_bot = 0.200 if is_female else 0.280
        delete_f = [f for f in bm_p.faces if f.material_index != 0 or not (z_pants_bot <= f.calc_center_median().z <= 1.045)]
        bmesh.ops.delete(bm_p, geom=delete_f, context="FACES")
        bmesh.ops.bisect_plane(bm_p, geom=bm_p.faces[:] + bm_p.edges[:] + bm_p.verts[:], plane_co=(0, 0, z_pants_bot + 0.010), plane_no=(0, 0, 1), clear_inner=True)
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
            p.use_smooth = True
        obj_pants.parent = armature
        obj_pants.matrix_parent_inverse = armature.matrix_world.inverted()
        obj_pants["worldgoing_character_part"] = True
        obj_pants["worldgoing_component_slot"] = "armor"
        obj_pants["worldgoing_visual_id"] = visual_id
        parts.append(obj_pants)

        # C. Dark Fitted Tunic (Underlayer)
        obj_tunic = source_raw_body.copy()
        obj_tunic.name = "Armor_Mingguang_01_UnderTunic"
        obj_tunic.data = source_raw_body.data.copy()
        obj_tunic.data.name = "Armor_Mingguang_01_UnderTunicMesh"
        bpy.context.collection.objects.link(obj_tunic)
        bm_t = bmesh.new()
        bm_t.from_mesh(obj_tunic.data)
        bm_t.faces.ensure_lookup_table()
        z_tunic_top = 1.490 if not is_female else 1.395
        z_tunic_bot = 0.920 if not is_female else 0.860
        delete_t = [f for f in bm_t.faces if f.material_index != 0 or not (z_tunic_bot <= f.calc_center_median().z <= z_tunic_top)]
        bmesh.ops.delete(bm_t, geom=delete_t, context="FACES")
        bmesh.ops.bisect_plane(bm_t, geom=bm_t.faces[:] + bm_t.edges[:] + bm_t.verts[:], plane_co=(0, 0, z_tunic_top), plane_no=(0, 0, -1), clear_inner=True)
        bmesh.ops.bisect_plane(bm_t, geom=bm_t.faces[:] + bm_t.edges[:] + bm_t.verts[:], plane_co=(0, 0, z_tunic_bot), plane_no=(0, 0, 1), clear_inner=True)
        for v in bm_t.verts:
            if v.link_faces and v.normal.length > 0:
                v.co += v.normal.normalized() * 0.0035
        loose_t = [v for v in bm_t.verts if not v.link_faces]
        bmesh.ops.delete(bm_t, geom=loose_t, context="VERTS")
        bmesh.ops.recalc_face_normals(bm_t, faces=bm_t.faces)
        bm_t.to_mesh(obj_tunic.data)
        bm_t.free()
        obj_tunic.data.update()
        obj_tunic.data.materials.clear()
        obj_tunic.data.materials.append(mat_cloth)
        for p in obj_tunic.data.polygons:
            p.use_smooth = True
        obj_tunic.parent = armature
        obj_tunic.matrix_parent_inverse = armature.matrix_world.inverted()
        obj_tunic["worldgoing_character_part"] = True
        obj_tunic["worldgoing_component_slot"] = "armor"
        obj_tunic["worldgoing_visual_id"] = visual_id
        parts.append(obj_tunic)

    # D. Contoured Gorget Collar (護頸領圈) with Gold Rim & Rivets
    bm_gorget = bmesh.new()
    bm_g_rim = bmesh.new()
    bm_g_rivets = bmesh.new()
    n_g_pts = 20
    g_z_top = collar_z + 0.022
    g_z_bot = collar_z - 0.032
    rx_g_top = 0.078 if not is_female else 0.068
    ry_g_top = 0.082 if not is_female else 0.072
    rx_g_bot = 0.110 if not is_female else 0.098
    ry_g_bot = 0.115 if not is_female else 0.102

    g_top_v = []
    g_bot_v = []
    for j in range(n_g_pts):
        ang = j * (2.0 * math.pi / n_g_pts)
        px_t = math.sin(ang) * rx_g_top
        py_t = -math.cos(ang) * ry_g_top - 0.005
        px_b = math.sin(ang) * rx_g_bot
        py_b = -math.cos(ang) * ry_g_bot - 0.008
        g_top_v.append(bm_gorget.verts.new((px_t, py_t, g_z_top)))
        g_bot_v.append(bm_gorget.verts.new((px_b, py_b, g_z_bot)))

        v_rim_t = bm_g_rim.verts.new((px_t, py_t, g_z_top + 0.002))
        v_rim_b = bm_g_rim.verts.new((px_t, py_t, g_z_top - 0.004))

        if j % 2 == 0:
            norm_g = Vector((math.sin(ang), -math.cos(ang), 0.2)).normalized()
            add_dome_rivet(bm_g_rivets, Vector(((px_t + px_b) * 0.5, (py_t + py_b) * 0.5, (g_z_top + g_z_bot) * 0.5)) + norm_g * 0.002, norm_g, radius=0.0026, depth=0.0016, n_segs=8)

    for j in range(n_g_pts):
        j_nxt = (j + 1) % n_g_pts
        bm_gorget.faces.new([g_top_v[j], g_top_v[j_nxt], g_bot_v[j_nxt], g_bot_v[j]])

    bmesh.ops.solidify(bm_gorget, geom=bm_gorget.faces[:], thickness=0.0032)
    bmesh.ops.solidify(bm_g_rim, geom=bm_g_rim.faces[:], thickness=0.0022)
    parts.append(create_rigid_fn("Armor_Mingguang_01_GorgetCollar", bm_gorget, mat_leather, "J_Bip_C_UpperChest", "armor", visual_id, armature))
    parts.append(create_rigid_fn("Armor_Mingguang_01_GorgetRim", bm_g_rim, mat_gold, "J_Bip_C_UpperChest", "armor", visual_id, armature))
    parts.append(create_rigid_fn("Armor_Mingguang_01_GorgetRivets", bm_g_rivets, mat_gold, "J_Bip_C_UpperChest", "armor", visual_id, armature))

    # E. Inner Crossover V-Collar (交領) tucked inside the gorget
    bm_in_col = bmesh.new()
    col_z_top = collar_z + 0.025
    col_z_mid = collar_z - 0.015
    col_z_bot = collar_z - 0.055

    lapel_l = [
        bm_in_col.verts.new((-0.065, -0.065, col_z_top)),
        bm_in_col.verts.new((-0.042, -0.080, col_z_mid)),
        bm_in_col.verts.new(( 0.022, -0.098, col_z_bot)),
        bm_in_col.verts.new(( 0.005, -0.099, col_z_bot)),
        bm_in_col.verts.new((-0.055, -0.081, col_z_mid)),
        bm_in_col.verts.new((-0.078, -0.066, col_z_top)),
    ]
    bm_in_col.faces.new([lapel_l[0], lapel_l[1], lapel_l[4], lapel_l[5]])
    bm_in_col.faces.new([lapel_l[1], lapel_l[2], lapel_l[3], lapel_l[4]])

    lapel_r = [
        bm_in_col.verts.new(( 0.065, -0.065, col_z_top)),
        bm_in_col.verts.new(( 0.042, -0.080, col_z_mid)),
        bm_in_col.verts.new((-0.018, -0.096, col_z_bot)),
        bm_in_col.verts.new((-0.005, -0.097, col_z_bot)),
        bm_in_col.verts.new(( 0.055, -0.081, col_z_mid)),
        bm_in_col.verts.new(( 0.078, -0.066, col_z_top)),
    ]
    bm_in_col.faces.new([lapel_r[5], lapel_r[4], lapel_r[1], lapel_r[0]])
    bm_in_col.faces.new([lapel_r[4], lapel_r[3], lapel_r[2], lapel_r[1]])

    bmesh.ops.recalc_face_normals(bm_in_col, faces=bm_in_col.faces)
    bmesh.ops.solidify(bm_in_col, geom=bm_in_col.faces[:], thickness=0.0025)
    parts.append(create_rigid_fn("Armor_Mingguang_01_InnerCollar", bm_in_col, mat_cloth, "J_Bip_C_UpperChest", "armor", visual_id, armature))

    # =========================================================================
    # 2. Authentic Columnar Pleated Brocade Fabric Skirt (深藍暗紋錦緞戰袍下擺)
    # =========================================================================
    bm_pleats = bmesh.new()
    z_plt_top = z_belt_bot + 0.010
    z_plt_bot = 0.450 if not is_female else 0.410
    rx_plt_top = waist_rx * 1.04
    ry_plt_top = (waist_ry_front + waist_ry_back) * 0.52
    rx_plt_bot = waist_rx * 1.10
    ry_plt_bot = (waist_ry_front + waist_ry_back) * 0.55

    build_columnar_pleated_skirt(bm_pleats, z_plt_top, z_plt_bot, rx_plt_top, ry_plt_top, rx_plt_bot, ry_plt_bot, n_pleats=32, pleat_depth=0.007)
    bmesh.ops.solidify(bm_pleats, geom=bm_pleats.faces[:], thickness=0.0025)
    parts.append(create_rigid_fn("Armor_Mingguang_01_PleatedSkirt", bm_pleats, mat_navy_brocade, "J_Bip_C_Hips", "armor", visual_id, armature))

    # =========================================================================
    # 3. Front Cuirass Leather Vest & Scooped U-Neckline (黑革身甲座與開弧領口)
    # =========================================================================
    bm_cuirass_f = bmesh.new()
    bm_c_neck_rim = bmesh.new()
    bm_c_rivets = bmesh.new()
    n_c_lat = 8
    n_c_lon = 16
    front_grid = []

    z_c_top = collar_z - 0.015
    z_c_bot = chest_z - 0.035

    for i in range(n_c_lat):
        v = i / float(n_c_lat - 1)
        pz = z_c_top - (z_c_top - z_c_bot) * v

        chest_expand = math.sin(v * math.pi * 0.72) ** 1.3
        rx = torso_rx * (1.0 - v * 0.05) * (1.0 + 0.05 * chest_expand)
        ry = (torso_ry_front if not is_female else torso_ry_front * 1.03) * (1.0 - v * 0.03) * (1.0 + 0.10 * chest_expand)

        row = []
        for j in range(n_c_lon):
            frac = (j / float(n_c_lon - 1) - 0.5) * 2.0
            ang = frac * (math.pi * 0.44)
            px = math.sin(ang) * rx
            py = -math.cos(ang) * ry - (0.014 if is_female else 0.008)

            z_mod = pz
            if i == 0:
                neck_scoop = max(0.0, 1.0 - (abs(frac) / 0.45) ** 2) * 0.030
                z_mod -= neck_scoop
            elif i == 1:
                neck_scoop = max(0.0, 1.0 - (abs(frac) / 0.45) ** 2) * 0.014
                z_mod -= neck_scoop

            row.append(bm_cuirass_f.verts.new((px, py, z_mod)))
        front_grid.append(row)

    for i in range(n_c_lat - 1):
        for j in range(n_c_lon - 1):
            bm_cuirass_f.faces.new([
                front_grid[i][j],
                front_grid[i][j + 1],
                front_grid[i + 1][j + 1],
                front_grid[i + 1][j],
            ])

    neck_rim_top = []
    neck_rim_bot = []
    for j in range(n_c_lon):
        v_pt = front_grid[0][j].co
        norm_up = Vector((0.0, -0.002, 0.005))
        norm_dn = Vector((0.0, -0.002, -0.005))
        neck_rim_top.append(bm_c_neck_rim.verts.new(v_pt + norm_up))
        neck_rim_bot.append(bm_c_neck_rim.verts.new(v_pt + norm_dn))
    for j in range(n_c_lon - 1):
        bm_c_neck_rim.faces.new([neck_rim_bot[j], neck_rim_top[j], neck_rim_top[j + 1], neck_rim_bot[j + 1]])

    for j_idx in [2, 4, 7, 8, 11, 13]:
        v_pt = front_grid[0][j_idx].co
        add_dome_rivet(bm_c_rivets, v_pt + Vector((0, -0.003, 0)), Vector((0, -0.9, 0.2)), radius=0.0028, depth=0.0018, n_segs=8)

    bmesh.ops.solidify(bm_cuirass_f, geom=bm_cuirass_f.faces[:], thickness=0.0035)
    bmesh.ops.solidify(bm_c_neck_rim, geom=bm_c_neck_rim.faces[:], thickness=0.0025)

    weights_chest = {"J_Bip_C_Chest": 0.50, "J_Bip_C_UpperChest": 0.35, "J_Bip_C_Spine": 0.15}
    parts.append(create_skinned_component("Armor_Mingguang_01_Cuirass_Front", bm_cuirass_f, mat_leather, weights_chest, "armor", visual_id, armature))
    parts.append(create_skinned_component("Armor_Mingguang_01_Cuirass_NeckRim", bm_c_neck_rim, mat_gold, weights_chest, "armor", visual_id, armature))
    parts.append(create_skinned_component("Armor_Mingguang_01_Cuirass_Rivets", bm_c_rivets, mat_gold, weights_chest, "armor", visual_id, armature))

    # =========================================================================
    # 4. Twin Convex Polished Silver Chest Mirrors (雙明光胸鏡)
    # =========================================================================
    m_r = 0.058 if not is_female else 0.048
    m_dx = 0.066 if not is_female else 0.056
    m_z = (chest_z + 0.016) if not is_female else (chest_z + 0.012)
    m_y = (-torso_ry_front - 0.016) if not is_female else (-torso_ry_front - 0.024)

    bm_mirrors = bmesh.new()
    bm_mirror_relief = bmesh.new()
    bm_mirror_frames = bmesh.new()
    bm_chest_straps = bmesh.new()

    for side, sign in (("L", 1.0), ("R", -1.0)):
        center = Vector((sign * m_dx, m_y, m_z))
        norm = Vector((sign * 0.08, -0.99, 0.05)).normalized()
        z_ax = norm
        up = Vector((0, 0, 1))
        x_ax = up.cross(z_ax).normalized()
        y_ax = z_ax.cross(x_ax).normalized()

        n_m_segs = 24
        f_rim_in = []
        f_rim_out = []
        for s in range(n_m_segs):
            ang = s * (2.0 * math.pi / n_m_segs)
            p_in = center + (x_ax * math.cos(ang) + y_ax * math.sin(ang)) * m_r + z_ax * 0.002
            p_out = center + (x_ax * math.cos(ang) + y_ax * math.sin(ang)) * (m_r * 1.14) + z_ax * 0.001
            f_rim_in.append(bm_mirror_frames.verts.new(p_in))
            f_rim_out.append(bm_mirror_frames.verts.new(p_out))

        for s in range(n_m_segs):
            s_nxt = (s + 1) % n_m_segs
            bm_mirror_frames.faces.new([f_rim_out[s], f_rim_out[s_nxt], f_rim_in[s_nxt], f_rim_in[s]])
            if s % 3 == 0:
                ang = s * (2.0 * math.pi / n_m_segs)
                p_stud = center + (x_ax * math.cos(ang) + y_ax * math.sin(ang)) * (m_r * 1.07) + z_ax * 0.003
                add_dome_rivet(bm_mirrors, p_stud, z_ax, radius=0.0030, depth=0.0018, n_segs=8)

        # Shallow convex dome curvature (5mm rise)
        m_inner_ring = []
        for s in range(n_m_segs):
            ang = s * (2.0 * math.pi / n_m_segs)
            p_m = center + (x_ax * math.cos(ang) + y_ax * math.sin(ang)) * (m_r * 0.98) + z_ax * 0.0025
            m_inner_ring.append(bm_mirrors.verts.new(p_m))

        m_mid_ring = []
        for s in range(n_m_segs):
            ang = s * (2.0 * math.pi / n_m_segs)
            p_mid = center + (x_ax * math.cos(ang) + y_ax * math.sin(ang)) * (m_r * 0.58) + z_ax * 0.0048
            m_mid_ring.append(bm_mirrors.verts.new(p_mid))

        m_center_v = bm_mirrors.verts.new(center + z_ax * 0.0062)

        for s in range(n_m_segs):
            s_nxt = (s + 1) % n_m_segs
            bm_mirrors.faces.new([m_inner_ring[s], m_inner_ring[s_nxt], m_mid_ring[s_nxt], m_mid_ring[s]])
            bm_mirrors.faces.new([m_mid_ring[s], m_mid_ring[s_nxt], m_center_v])

        # Dragon boss relief
        b_c = bm_mirror_relief.verts.new(center + z_ax * 0.0080)
        b_ring = []
        for s in range(12):
            ang = s * (2.0 * math.pi / 12)
            r_scale = 0.018 * (1.0 + 0.22 * math.sin(ang * 3.0))
            p_b = center + (x_ax * math.cos(ang) + y_ax * math.sin(ang)) * r_scale + z_ax * 0.0058
            b_ring.append(bm_mirror_relief.verts.new(p_b))
        for s in range(12):
            s_nxt = (s + 1) % 12
            bm_mirror_relief.faces.new([b_c, b_ring[s], b_ring[s_nxt]])

        # The previous boss read as a flat dot in the editor.  Keep it as the
        # mirror foundation, then add a low-profile cloud-dragon curl that
        # remains visible after the editor's toon material pass.
        add_mirror_dragon_relief(bm_mirror_relief, center, z_ax, m_r * 0.82)

    # Leather connecting bridge between mirrors
    st_z1 = m_z + 0.012
    st_z2 = m_z - 0.012
    v_st1 = bm_chest_straps.verts.new((-m_dx * 0.62, m_y + 0.002, st_z1))
    v_st2 = bm_chest_straps.verts.new((m_dx * 0.62, m_y + 0.002, st_z1))
    v_st3 = bm_chest_straps.verts.new((m_dx * 0.62, m_y + 0.002, st_z2))
    v_st4 = bm_chest_straps.verts.new((-m_dx * 0.62, m_y + 0.002, st_z2))
    bm_chest_straps.faces.new([v_st1, v_st2, v_st3, v_st4])

    top_rivet_z1 = m_z + m_r * 0.85
    top_rivet_z2 = m_z + m_r * 1.25
    add_dome_rivet(bm_mirrors, Vector((0.0, m_y + 0.003, top_rivet_z1)), Vector((0, -1, 0)), radius=0.0042, depth=0.0030, n_segs=10)
    add_dome_rivet(bm_mirrors, Vector((0.0, m_y + 0.003, top_rivet_z2)), Vector((0, -1, 0)), radius=0.0042, depth=0.0030, n_segs=10)

    bmesh.ops.solidify(bm_mirror_frames, geom=bm_mirror_frames.faces[:], thickness=0.0028)
    bmesh.ops.solidify(bm_chest_straps, geom=bm_chest_straps.faces[:], thickness=0.0028)

    parts.append(create_skinned_component("Armor_Mingguang_01_Mirror_Plates", bm_mirrors, mat_silver, weights_chest, "armor", visual_id, armature))
    parts.append(create_skinned_component("Armor_Mingguang_01_Mirror_Relief", bm_mirror_relief, mat_silver_relief, weights_chest, "armor", visual_id, armature))
    parts.append(create_skinned_component("Armor_Mingguang_01_Mirror_Frames", bm_mirror_frames, mat_leather, weights_chest, "armor", visual_id, armature))
    parts.append(create_skinned_component("Armor_Mingguang_01_Chest_Straps", bm_chest_straps, mat_leather, weights_chest, "armor", visual_id, armature))

    # =========================================================================
    # 5. Abdomen: Dark Backing + Continuous Shingled Fish-Scale Lamellae (腹部細密魚鱗札甲)
    #    (Uses build_shingled_fishscale_mesh: 6 tiers continuously overlapping down to the belt)
    # =========================================================================
    bm_abdomen_base = bmesh.new()
    bm_abdomen_scales = bmesh.new()
    bm_abd_leather_side = bmesh.new()
    z_abd_top = chest_z - 0.020
    z_abd_bot = z_belt_top

    def get_abd_span(u: float, z1: float, z2: float):
        ang = (-0.40 + u * 0.80) * math.pi
        v_prog = max(0.0, min(1.0, (z_abd_top - z1) / max(1e-4, z_abd_top - z_abd_bot)))
        rx = torso_rx * (1.0 - v_prog * 0.08)
        ry = (torso_ry_front if not is_female else torso_ry_front * 1.02) * (1.0 - v_prog * 0.06)
        px = math.sin(ang) * rx
        py = -math.cos(ang) * ry - 0.015
        norm = Vector((math.sin(ang), -math.cos(ang), 0.0)).normalized()
        return Vector((px, py, z1)), Vector((px, py, z2)), norm

    build_curved_front_shell(
        bm_abdomen_base,
        top_z=z_abd_top,
        bot_z=z_abd_bot,
        top_rx=torso_rx * 0.975,
        top_ry=(torso_ry_front if not is_female else torso_ry_front * 1.01) * 0.975,
        bot_rx=torso_rx * 0.935,
        bot_ry=(torso_ry_front if not is_female else torso_ry_front * 1.01) * 0.940,
        n_lat=6,
        n_lon=18,
        y_offset=-0.010,
    )

    build_shingled_fishscale_mesh(
        bm_abdomen_scales,
        top_z=z_abd_top,
        bot_z=z_abd_bot,
        n_tiers=6,
        n_cols=16,
        get_span_pts_func=get_abd_span,
        scale_tongue_len=0.0045,
        ridge_out=0.0024,
    )

    # Leather flank panels
    for side, sign in (("L", 1.0), ("R", -1.0)):
        flank_t = []
        flank_b = []
        n_fl = 6
        for fi in range(n_fl):
            u_fl = fi / float(n_fl - 1)
            ang = (0.38 + u_fl * 0.26) * math.pi
            px = sign * math.sin(ang) * (torso_rx * 0.98)
            py = -math.cos(ang) * (torso_ry_front * 0.98) - 0.010
            flank_t.append(bm_abd_leather_side.verts.new((px, py, z_abd_top)))
            flank_b.append(bm_abd_leather_side.verts.new((px, py, z_abd_bot)))
        for fi in range(n_fl - 1):
            if sign == 1.0:
                bm_abd_leather_side.faces.new([flank_t[fi], flank_t[fi + 1], flank_b[fi + 1], flank_b[fi]])
            else:
                bm_abd_leather_side.faces.new([flank_t[fi], flank_b[fi], flank_b[fi + 1], flank_t[fi + 1]])

    bmesh.ops.solidify(bm_abdomen_scales, geom=bm_abdomen_scales.faces[:], thickness=0.0030)
    bmesh.ops.solidify(bm_abd_leather_side, geom=bm_abd_leather_side.faces[:], thickness=0.0035)

    weights_abdomen = {"J_Bip_C_Spine": 0.60, "J_Bip_C_Chest": 0.25, "J_Bip_C_Hips": 0.15}
    bmesh.ops.solidify(bm_abdomen_base, geom=bm_abdomen_base.faces[:], thickness=0.0024)
    parts.append(create_skinned_component("Armor_Mingguang_01_Abdomen_Base", bm_abdomen_base, mat_leather, weights_abdomen, "armor", visual_id, armature))
    parts.append(create_skinned_component("Armor_Mingguang_01_Abdomen_Scales", bm_abdomen_scales, mat_silver, weights_abdomen, "armor", visual_id, armature))
    parts.append(create_skinned_component("Armor_Mingguang_01_Abdomen_Flanks", bm_abd_leather_side, mat_leather, weights_abdomen, "armor", visual_id, armature))

    # =========================================================================
    # 6. Back Cuirass: Leather Base, Twin Back Mirrors & Continuous Lamellar Tiers
    # =========================================================================
    bm_cuirass_b = bmesh.new()
    bm_back_mirrors = bmesh.new()
    bm_back_relief = bmesh.new()
    bm_back_frames = bmesh.new()
    bm_back_scales = bmesh.new()
    n_c_lat = 8
    n_c_lon = 16
    back_grid = []

    for i in range(n_c_lat):
        v = i / float(n_c_lat - 1)
        pz = collar_z - (collar_z - z_belt_top) * v
        rx = torso_rx + (waist_rx - torso_rx) * v
        ry = torso_ry_back + (waist_ry_back - torso_ry_back) * v
        row = []
        for j in range(n_c_lon):
            ang = -0.46 * math.pi + (j / float(n_c_lon - 1)) * (0.92 * math.pi)
            px = math.sin(ang) * rx
            py = math.cos(ang) * ry + 0.006
            row.append(bm_cuirass_b.verts.new((px, py, pz)))
        back_grid.append(row)

    for i in range(n_c_lat - 1):
        for j in range(n_c_lon - 1):
            bm_cuirass_b.faces.new([
                back_grid[i][j],
                back_grid[i + 1][j],
                back_grid[i + 1][j + 1],
                back_grid[i][j + 1],
            ])

    # Twin Back Mirrors (雙背鏡)
    b_m_z = m_z + 0.010
    b_m_y = torso_ry_back + 0.012
    for side, sign in (("L", 1.0), ("R", -1.0)):
        b_center = Vector((sign * m_dx, b_m_y, b_m_z))
        b_norm = Vector((sign * 0.06, 0.99, 0.05)).normalized()
        bz_ax = b_norm
        b_up = Vector((0, 0, 1))
        bx_ax = b_up.cross(bz_ax).normalized()
        by_ax = bz_ax.cross(bx_ax).normalized()

        n_bm_segs = 20
        b_rim_in = []
        b_rim_out = []
        for s in range(n_bm_segs):
            ang = s * (2.0 * math.pi / n_bm_segs)
            p_in = b_center + (bx_ax * math.cos(ang) + by_ax * math.sin(ang)) * (m_r * 0.95) + bz_ax * 0.002
            p_out = b_center + (bx_ax * math.cos(ang) + by_ax * math.sin(ang)) * (m_r * 1.10) + bz_ax * 0.001
            b_rim_in.append(bm_back_frames.verts.new(p_in))
            b_rim_out.append(bm_back_frames.verts.new(p_out))

        for s in range(n_bm_segs):
            s_nxt = (s + 1) % n_bm_segs
            bm_back_frames.faces.new([b_rim_out[s], b_rim_in[s], b_rim_in[s_nxt], b_rim_out[s_nxt]])

        bm_ring = []
        for s in range(n_bm_segs):
            ang = s * (2.0 * math.pi / n_bm_segs)
            p_m = b_center + (bx_ax * math.cos(ang) + by_ax * math.sin(ang)) * (m_r * 0.92) + bz_ax * 0.0025
            bm_ring.append(bm_back_mirrors.verts.new(p_m))
        bm_mid = []
        for s in range(n_bm_segs):
            ang = s * (2.0 * math.pi / n_bm_segs)
            p_mid = b_center + (bx_ax * math.cos(ang) + by_ax * math.sin(ang)) * (m_r * 0.52) + bz_ax * 0.0045
            bm_mid.append(bm_back_mirrors.verts.new(p_mid))
        bm_c = bm_back_mirrors.verts.new(b_center + bz_ax * 0.0058)

        for s in range(n_bm_segs):
            s_nxt = (s + 1) % n_bm_segs
            bm_back_mirrors.faces.new([bm_ring[s], bm_mid[s], bm_mid[s_nxt], bm_ring[s_nxt]])
            bm_back_mirrors.faces.new([bm_mid[s], bm_c, bm_mid[s_nxt]])

        add_mirror_dragon_relief(bm_back_relief, b_center, bz_ax, m_r * 0.76)

    # Lower back fish-scale tiers
    z_b_top = b_m_z - m_r * 1.08
    z_b_bot = z_belt_top
    def get_back_span(u: float, z1: float, z2: float):
        ang = (-0.36 + u * 0.72) * math.pi
        px = math.sin(ang) * (torso_rx * 0.98)
        py = math.cos(ang) * (torso_ry_back * 0.98) + 0.010
        norm = Vector((math.sin(ang), math.cos(ang), 0.0)).normalized()
        return Vector((px, py, z1)), Vector((px, py, z2)), norm

    build_shingled_fishscale_mesh(
        bm_back_scales,
        top_z=z_b_top,
        bot_z=z_b_bot,
        n_tiers=5,
        n_cols=14,
        get_span_pts_func=get_back_span,
        scale_tongue_len=0.0042,
        ridge_out=0.0022,
    )

    bmesh.ops.solidify(bm_cuirass_b, geom=bm_cuirass_b.faces[:], thickness=0.0035)
    bmesh.ops.solidify(bm_back_frames, geom=bm_back_frames.faces[:], thickness=0.0025)
    bmesh.ops.solidify(bm_back_scales, geom=bm_back_scales.faces[:], thickness=0.0028)

    parts.append(create_skinned_component("Armor_Mingguang_01_Cuirass_Back", bm_cuirass_b, mat_leather, weights_chest, "armor", visual_id, armature))
    parts.append(create_skinned_component("Armor_Mingguang_01_Back_Mirrors", bm_back_mirrors, mat_silver, weights_chest, "armor", visual_id, armature))
    parts.append(create_skinned_component("Armor_Mingguang_01_Back_Relief", bm_back_relief, mat_silver_relief, weights_chest, "armor", visual_id, armature))
    parts.append(create_skinned_component("Armor_Mingguang_01_Back_Frames", bm_back_frames, mat_leather, weights_chest, "armor", visual_id, armature))
    parts.append(create_skinned_component("Armor_Mingguang_01_Back_Scales", bm_back_scales, mat_silver, weights_chest, "armor", visual_id, armature))

    # =========================================================================
    # 7. Pauldrons: Organic Silver Beast Head & 3 Curved Articulated Tiers
    #    (Modeled along UpperArm X axis with robust grid geometry and gold rim)
    # =========================================================================
    for side, sign in (("L", 1.0), ("R", -1.0)):
        bone_arm = f"J_Bip_{side}_UpperArm"

        # A. Beast Head Shoulder Cap (吞肩獸首)
        bm_p_beast = bmesh.new()
        p_cap_c = Vector((sign * (ua_head_x + 0.022), ua_y - 0.008, ua_z + 0.028))
        add_beast_face_organic(
            bm_p_beast,
            center=p_cap_c,
            forward=Vector((sign * 0.65, -0.65, 0.40)).normalized(),
            up=Vector((sign * 0.18, 0.35, 0.92)).normalized(),
            scale=0.048 if not is_female else 0.040,
        )
        bmesh.ops.solidify(bm_p_beast, geom=bm_p_beast.faces[:], thickness=0.0028)
        parts.append(create_rigid_fn(f"Armor_Mingguang_01_Pauldron_Beast_{side}", bm_p_beast, mat_silver_relief, bone_arm, "armor", visual_id, armature))

        # B. 3 Articulated Curved Lamellar Tiers (披膊三層疊甲)
        bm_p_plates = bmesh.new()
        bm_p_rim = bmesh.new()

        tier_steps = [
            (0.010, 0.075, 1.00),
            (0.060, 0.130, 1.06),
            (0.115, 0.190, 1.12),
        ]

        n_p_x = 6
        n_p_phi = 14
        r_arm_y = 0.064 if not is_female else 0.054
        r_arm_z = 0.068 if not is_female else 0.058

        for t_idx, (x_in, x_out, flare) in enumerate(tier_steps):
            ry = r_arm_y * flare
            rz = r_arm_z * flare

            t_grid = []
            for i in range(n_p_x):
                u = i / float(n_p_x - 1)
                px = sign * (ua_head_x + x_in + (x_out - x_in) * u)

                row = []
                for j in range(n_p_phi):
                    phi = (j / float(n_p_phi - 1) - 0.5) * (math.pi * 0.88)
                    # Scalloped wave along the outer edge
                    scallop = 0.004 * math.sin(j * math.pi * 0.5) if i == n_p_x - 1 else 0.0
                    py = ua_y + math.sin(phi) * ry
                    pz = ua_z + math.cos(phi) * rz - scallop
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

            # Gold rim along the outer edge of each tier
            rim_in = []
            rim_out = []
            for j in range(n_p_phi):
                v_co = t_grid[-1][j].co
                rim_in.append(bm_p_rim.verts.new(v_co))
                rim_out.append(bm_p_rim.verts.new(v_co + Vector((sign * 0.007, 0, 0))))
            for j in range(n_p_phi - 1):
                if sign == 1.0:
                    bm_p_rim.faces.new([rim_in[j], rim_out[j], rim_out[j + 1], rim_in[j + 1]])
                else:
                    bm_p_rim.faces.new([rim_in[j], rim_in[j + 1], rim_out[j + 1], rim_out[j]])

            # Rivets on tier corners
            add_dome_rivet(bm_p_plates, t_grid[1][0].co, Vector((0.0, -0.9, 0.2)), radius=0.0028, depth=0.0020, n_segs=8)
            add_dome_rivet(bm_p_plates, t_grid[1][-1].co, Vector((0.0, 0.9, 0.2)), radius=0.0028, depth=0.0020, n_segs=8)

        bmesh.ops.solidify(bm_p_plates, geom=bm_p_plates.faces[:], thickness=0.0032)
        bmesh.ops.solidify(bm_p_rim, geom=bm_p_rim.faces[:], thickness=0.0022)
        parts.append(create_rigid_fn(f"Armor_Mingguang_01_Pauldron_Plates_{side}", bm_p_plates, mat_silver, bone_arm, "armor", visual_id, armature))
        parts.append(create_rigid_fn(f"Armor_Mingguang_01_Pauldron_Rim_{side}", bm_p_rim, mat_gold, bone_arm, "armor", visual_id, armature))

    # =========================================================================
    # 8. Forearm Curved Silver Lamellar Bracers (護臂 / 臂甲)
    # =========================================================================
    for side, sign in (("L", 1.0), ("R", -1.0)):
        bone_forearm = f"J_Bip_{side}_LowerArm"
        bm_bracer = bmesh.new()
        bm_b_straps = bmesh.new()
        bm_b_rim = bmesh.new()

        x_elbow = la_head_x + 0.015
        x_wrist = la_tail_x - 0.020

        n_br_x = 8
        n_br_phi = 12
        r_el = 0.042 if not is_female else 0.036
        r_wr = 0.033 if not is_female else 0.028

        bracer_grid = []
        for i in range(n_br_x):
            u = i / float(n_br_x - 1)
            px = sign * (x_elbow + (x_wrist - x_elbow) * u)
            r_cur = r_el * (1.0 - u) + r_wr * u
            row = []
            for j in range(n_br_phi):
                phi = (j / float(n_br_phi - 1) - 0.5) * (math.pi * 1.05)
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

        # Gold rims at elbow and wrist
        for row_idx in [0, -1]:
            r_in = []
            r_out = []
            s_dir = -1.0 if row_idx == 0 else 1.0
            for j in range(n_br_phi):
                v_co = bracer_grid[row_idx][j].co
                r_in.append(bm_b_rim.verts.new(v_co))
                r_out.append(bm_b_rim.verts.new(v_co + Vector((sign * s_dir * 0.005, 0, 0))))
            for j in range(n_br_phi - 1):
                bm_b_rim.faces.new([r_in[j], r_out[j], r_out[j + 1], r_in[j + 1]])

        # Leather closure straps on inner forearm
        for st_u in [0.28, 0.72]:
            px = sign * (x_elbow + (x_wrist - x_elbow) * st_u)
            r_st = (r_el * (1.0 - st_u) + r_wr * st_u) * 1.03
            st_ring_1 = []
            st_ring_2 = []
            for j in range(16):
                phi = j * (2.0 * math.pi / 16)
                py = la_y + math.sin(phi) * r_st
                pz = la_z + math.cos(phi) * r_st
                st_ring_1.append(bm_b_straps.verts.new((px - sign * 0.004, py, pz)))
                st_ring_2.append(bm_b_straps.verts.new((px + sign * 0.004, py, pz)))
            for j in range(16):
                j_nxt = (j + 1) % 16
                bm_b_straps.faces.new([st_ring_1[j], st_ring_2[j], st_ring_2[j_nxt], st_ring_1[j_nxt]])

        bmesh.ops.solidify(bm_bracer, geom=bm_bracer.faces[:], thickness=0.0030)
        bmesh.ops.solidify(bm_b_rim, geom=bm_b_rim.faces[:], thickness=0.0022)
        bmesh.ops.solidify(bm_b_straps, geom=bm_b_straps.faces[:], thickness=0.0020)

        parts.append(create_rigid_fn(f"Armor_Mingguang_01_Bracer_{side}", bm_bracer, mat_silver, bone_forearm, "armor", visual_id, armature))
        parts.append(create_rigid_fn(f"Armor_Mingguang_01_Bracer_Rim_{side}", bm_b_rim, mat_gold, bone_forearm, "armor", visual_id, armature))
        parts.append(create_rigid_fn(f"Armor_Mingguang_01_Bracer_Straps_{side}", bm_b_straps, mat_leather, bone_forearm, "armor", visual_id, armature))

    # =========================================================================
    # 9. Waist: Studded Black Leather Belt & Large Silver Beast Buckle (腹吞獸首)
    # =========================================================================
    bm_belt = bmesh.new()
    bm_belt_studs = bmesh.new()
    n_b_segs = 24
    b_top_ring = []
    b_bot_ring = []
    rx_belt = waist_rx * 1.07
    ry_belt_f = waist_ry_front * 1.08
    ry_belt_b = waist_ry_back * 1.07

    for j in range(n_b_segs):
        ang = j * (2.0 * math.pi / n_b_segs)
        px = math.sin(ang) * rx_belt
        py = -math.cos(ang) * ry_belt_f if math.cos(ang) > 0 else -math.cos(ang) * ry_belt_b
        b_top_ring.append(bm_belt.verts.new((px, py, z_belt_top)))
        b_bot_ring.append(bm_belt.verts.new((px, py, z_belt_bot)))

        norm_b = Vector((math.sin(ang), -math.cos(ang), 0.0)).normalized()
        add_dome_rivet(bm_belt_studs, Vector((px, py, z_belt_top - 0.015)) + norm_b * 0.002, norm_b, radius=0.0028, depth=0.0020, n_segs=8)
        add_dome_rivet(bm_belt_studs, Vector((px, py, z_belt_bot + 0.015)) + norm_b * 0.002, norm_b, radius=0.0028, depth=0.0020, n_segs=8)

    for j in range(n_b_segs):
        j_nxt = (j + 1) % n_b_segs
        bm_belt.faces.new([b_top_ring[j], b_bot_ring[j], b_bot_ring[j_nxt], b_top_ring[j_nxt]])

    bmesh.ops.solidify(bm_belt, geom=bm_belt.faces[:], thickness=0.0035)
    parts.append(create_rigid_fn("Armor_Mingguang_01_Belt_Leather", bm_belt, mat_leather, "J_Bip_C_Hips", "armor", visual_id, armature))
    parts.append(create_rigid_fn("Armor_Mingguang_01_Belt_Studs", bm_belt_studs, mat_gold, "J_Bip_C_Hips", "armor", visual_id, armature))

    # Large Majestic Sculpted 3D Silver Beast Belly Buckle (腹吞獸首 / 饕餮吞口)
    bm_beast_buckle = bmesh.new()
    bm_buckle_ring = bmesh.new()
    z_bkl = (z_belt_top + z_belt_bot) * 0.5 + 0.014
    y_bkl = -ry_belt_f - 0.014
    bkl_scale = 0.068 if not is_female else 0.056
    add_beast_face_organic(
        bm_beast_buckle,
        Vector((0.0, y_bkl, z_bkl)),
        forward=Vector((0.0, -0.96, 0.28)).normalized(),
        up=Vector((0.0, 0.28, 0.96)).normalized(),
        scale=bkl_scale,
    )
    r_ring = 0.024 * (bkl_scale / 0.068)
    n_r_pts = 16
    ring_pts = []
    c_ring = Vector((0.0, y_bkl - 0.010, z_bkl - 0.024))
    for j in range(n_r_pts):
        ang = j * (2.0 * math.pi / n_r_pts)
        ring_pts.append(bm_buckle_ring.verts.new(c_ring + Vector((math.sin(ang) * r_ring, 0.0, math.cos(ang) * r_ring))))
    for j in range(n_r_pts):
        j_nxt = (j + 1) % n_r_pts
        bm_buckle_ring.faces.new([ring_pts[j], ring_pts[j_nxt], bm_buckle_ring.verts.new(ring_pts[j_nxt].co + Vector((0, 0.004, 0))), bm_buckle_ring.verts.new(ring_pts[j].co + Vector((0, 0.004, 0)))])

    bmesh.ops.solidify(bm_beast_buckle, geom=bm_beast_buckle.faces[:], thickness=0.0032)
    bmesh.ops.solidify(bm_buckle_ring, geom=bm_buckle_ring.faces[:], thickness=0.0025)
    parts.append(create_rigid_fn("Armor_Mingguang_01_BeastBuckle", bm_beast_buckle, mat_silver_relief, "J_Bip_C_Hips", "armor", visual_id, armature))
    parts.append(create_rigid_fn("Armor_Mingguang_01_BuckleRing", bm_buckle_ring, mat_silver_relief, "J_Bip_C_Hips", "armor", visual_id, armature))

    # =========================================================================
    # 10. Skirts & Tassets: Front Center Apron (蔽膝) & Side/Rear Skinned Lamellar Skirts
    # =========================================================================
    # A. Front Center Apron of Hanging Leather Pteruges Strips (前排鬚 / 蔽膝)
    bm_pt_f = bmesh.new()
    bm_pt_f_silver = bmesh.new()
    bm_pt_f_studs = bmesh.new()
    z_pt_top = z_belt_bot + 0.005
    z_pt_bot = 0.580 if not is_female else 0.540

    build_pteruges_ring(
        bm_pt_f, bm_pt_f_silver, bm_pt_f_studs,
        z_top=z_pt_top, z_bot=z_pt_bot,
        rx=waist_rx * 1.08, ry_f=waist_ry_front * 1.10, ry_b=waist_ry_back * 1.08,
        strip_w=0.022,
        angle_ranges=[(-0.25, 0.25, 8)],
        side_sign=1.0,
    )
    bmesh.ops.solidify(bm_pt_f, geom=bm_pt_f.faces[:], thickness=0.0028)
    weights_apron = {"J_Bip_C_Hips": 0.75, "J_Bip_L_UpperLeg": 0.125, "J_Bip_R_UpperLeg": 0.125}
    parts.append(create_skinned_component("Armor_Mingguang_01_Pteruges_Front", bm_pt_f, mat_leather, weights_apron, "armor", visual_id, armature))
    parts.append(create_skinned_component("Armor_Mingguang_01_Pteruges_Silver", bm_pt_f_silver, mat_silver, weights_apron, "armor", visual_id, armature))
    parts.append(create_skinned_component("Armor_Mingguang_01_Pteruges_Studs", bm_pt_f_studs, mat_gold, weights_apron, "armor", visual_id, armature))

    # B. Side Lamellar Skirts (吊腿 / 左右腿側魚鱗札甲)
    # Skinned to Hips (0.60) and UpperLeg (0.40) so they naturally articulate without tearing!
    for side, sign in (("L", 1.0), ("R", -1.0)):
        bm_skirt_s = bmesh.new()
        bm_skirt_rim = bmesh.new()
        bone_leg = f"J_Bip_{side}_UpperLeg"

        z_sk_top = z_belt_bot + 0.015
        z_sk_bot = 0.635 if not is_female else 0.595

        def get_side_skirt_span(u: float, z_t: float, z_b: float, ssign=sign):
            ang = (u - 0.5) * (math.pi * 0.70)
            v_p = (z_belt_bot - z_t) / max(1e-4, z_belt_bot - z_sk_bot)
            rx_s = waist_rx * 1.08 + v_p * 0.035
            ry_s = waist_ry_front * 1.06 + v_p * 0.025
            px = ssign * (math.cos(ang) * rx_s)
            py = math.sin(ang) * ry_s - 0.010
            norm = Vector((ssign * math.cos(ang), math.sin(ang), 0.0)).normalized()
            return Vector((px, py, z_t)), Vector((px, py, z_b)), norm

        build_shingled_fishscale_mesh(
            bm_skirt_s,
            top_z=z_sk_top,
            bot_z=z_sk_bot,
            n_tiers=5,
            n_cols=9,
            get_span_pts_func=get_side_skirt_span,
            scale_tongue_len=0.0045,
            ridge_out=0.0024,
        )

        # Bottom gold rim
        b_rim_1 = []
        b_rim_2 = []
        for j in range(10):
            u_r = j / 9.0
            p1, _, n_d = get_side_skirt_span(u_r, z_sk_bot, z_sk_bot)
            b_rim_1.append(bm_skirt_rim.verts.new(p1 + n_d * 0.002))
            b_rim_2.append(bm_skirt_rim.verts.new(p1 + n_d * 0.002 - Vector((0, 0, 0.008))))
        for j in range(9):
            if sign == 1.0:
                bm_skirt_rim.faces.new([b_rim_1[j], b_rim_1[j + 1], b_rim_2[j + 1], b_rim_2[j]])
            else:
                bm_skirt_rim.faces.new([b_rim_1[j], b_rim_2[j], b_rim_2[j + 1], b_rim_1[j + 1]])

        bmesh.ops.solidify(bm_skirt_s, geom=bm_skirt_s.faces[:], thickness=0.0030)
        bmesh.ops.solidify(bm_skirt_rim, geom=bm_skirt_rim.faces[:], thickness=0.0022)

        weights_side = {"J_Bip_C_Hips": 0.60, bone_leg: 0.40}
        parts.append(create_skinned_component(f"Armor_Mingguang_01_Skirt_Side_{side}", bm_skirt_s, mat_silver, weights_side, "armor", visual_id, armature))
        parts.append(create_skinned_component(f"Armor_Mingguang_01_Skirt_Rim_{side}", bm_skirt_rim, mat_gold, weights_side, "armor", visual_id, armature))

    # C. Rear Lamellar Skirt (後裙甲 / 臀部銀札)
    bm_skirt_r = bmesh.new()
    bm_skirt_r_rim = bmesh.new()
    z_rear_top = z_belt_bot + 0.012
    z_rear_bot = 0.640 if not is_female else 0.600

    def get_rear_skirt_span(u: float, z_t: float, z_b: float):
        frac = (u - 0.5) * 2.0
        v_p = (z_belt_bot - z_t) / max(1e-4, z_belt_bot - z_rear_bot)
        w_cur = (waist_rx * 0.88) + v_p * 0.030
        px = frac * w_cur
        py = waist_ry_back * 1.08 + 0.015 + v_p * 0.020
        norm = Vector((frac * 0.20, 0.98, 0.0)).normalized()
        return Vector((px, py, z_t)), Vector((px, py, z_b)), norm

    build_shingled_fishscale_mesh(
        bm_skirt_r,
        top_z=z_rear_top,
        bot_z=z_rear_bot,
        n_tiers=5,
        n_cols=9,
        get_span_pts_func=get_rear_skirt_span,
        scale_tongue_len=0.0045,
        ridge_out=0.0024,
    )

    r_rim_1 = []
    r_rim_2 = []
    for j in range(10):
        u_r = j / 9.0
        p1, _, n_d = get_rear_skirt_span(u_r, z_rear_bot, z_rear_bot)
        r_rim_1.append(bm_skirt_r_rim.verts.new(p1 + n_d * 0.002))
        r_rim_2.append(bm_skirt_r_rim.verts.new(p1 + n_d * 0.002 - Vector((0, 0, 0.008))))
    for j in range(9):
        bm_skirt_r_rim.faces.new([r_rim_1[j], r_rim_1[j + 1], r_rim_2[j + 1], r_rim_2[j]])

    bmesh.ops.solidify(bm_skirt_r, geom=bm_skirt_r.faces[:], thickness=0.0030)
    bmesh.ops.solidify(bm_skirt_r_rim, geom=bm_skirt_r_rim.faces[:], thickness=0.0022)

    weights_rear = {"J_Bip_C_Hips": 0.85, "J_Bip_C_Spine": 0.15}
    parts.append(create_skinned_component("Armor_Mingguang_01_Skirt_Rear", bm_skirt_r, mat_silver, weights_rear, "armor", visual_id, armature))
    parts.append(create_skinned_component("Armor_Mingguang_01_Skirt_Rear_Rim", bm_skirt_r_rim, mat_gold, weights_rear, "armor", visual_id, armature))

    # =========================================================================
    # 11. Shin Guards / Greaves (脛甲 / 腿甲)
    # =========================================================================
    for side, sign in (("L", 1.0), ("R", -1.0)):
        bone_leg = f"J_Bip_{side}_LowerLeg"
        bone_ll = armature.data.bones.get(bone_leg)
        if bone_ll:
            ll_head_z = bone_ll.head_local.z
            ll_tail_z = bone_ll.tail_local.z
            ll_head_x = bone_ll.head_local.x
            ll_head_y = bone_ll.head_local.y
        else:
            ll_head_z = 0.500 if not is_female else 0.460
            ll_tail_z = 0.120 if not is_female else 0.100
            ll_head_x = sign * (0.095 if not is_female else 0.082)
            ll_head_y = -0.015

        bm_greave = bmesh.new()
        bm_g_straps = bmesh.new()
        bm_g_rim = bmesh.new()

        z_grv_top = ll_head_z - 0.035
        z_grv_bot = ll_tail_z + 0.055

        r_calf_y = 0.056 if not is_female else 0.048
        r_calf_x = 0.052 if not is_female else 0.044
        r_ank_y = 0.040 if not is_female else 0.034
        r_ank_x = 0.038 if not is_female else 0.032

        def get_greave_span(u: float, z1: float, z2: float, lx=ll_head_x, ly=ll_head_y):
            vg = max(0.0, min(1.0, (z_grv_top - z1) / max(1e-4, z_grv_top - z_grv_bot)))
            rx_g = r_calf_x * (1.0 - vg) + r_ank_x * vg
            ry_g = r_calf_y * (1.0 - vg) + r_ank_y * vg
            phi = (-0.36 + u * 0.72) * math.pi
            px = lx + math.sin(phi) * rx_g
            py = ly - math.cos(phi) * ry_g - 0.004
            norm = Vector((math.sin(phi), -math.cos(phi), 0.0)).normalized()
            return Vector((px, py, z1)), Vector((px, py, z2)), norm

        build_shingled_fishscale_mesh(
            bm_greave,
            top_z=z_grv_top,
            bot_z=z_grv_bot,
            n_tiers=5,
            n_cols=9,
            get_span_pts_func=get_greave_span,
            scale_tongue_len=0.0042,
            ridge_out=0.0022,
        )

        for z_edge in [z_grv_top, z_grv_bot]:
            vg = 0.0 if z_edge == z_grv_top else 1.0
            rx_g = (r_calf_x * (1.0 - vg) + r_ank_x * vg) * 1.02
            ry_g = (r_calf_y * (1.0 - vg) + r_ank_y * vg) * 1.02
            r1 = []
            r2 = []
            for j in range(10):
                phi = (-0.36 + (j / 9.0) * 0.72) * math.pi
                px = ll_head_x + math.sin(phi) * rx_g
                py = ll_head_y - math.cos(phi) * ry_g - 0.004
                r1.append(bm_g_rim.verts.new((px, py, z_edge)))
                r2.append(bm_g_rim.verts.new((px, py, z_edge + (0.005 if z_edge == z_grv_top else -0.005))))
            for j in range(9):
                bm_g_rim.faces.new([r1[j], r1[j + 1], r2[j + 1], r2[j]])

        for st_v in [0.25, 0.75]:
            pz_st = z_grv_top - (z_grv_top - z_grv_bot) * st_v
            rx_st = (r_calf_x * (1.0 - st_v) + r_ank_x * st_v) * 1.04
            ry_st = (r_calf_y * (1.0 - st_v) + r_ank_y * st_v) * 1.04
            st_top = []
            st_bot = []
            n_st_phi = 16
            for j in range(n_st_phi):
                ang = j * (2.0 * math.pi / n_st_phi)
                px = ll_head_x + math.sin(ang) * rx_st
                py = ll_head_y - math.cos(ang) * ry_st
                st_top.append(bm_g_straps.verts.new((px, py, pz_st + 0.004)))
                st_bot.append(bm_g_straps.verts.new((px, py, pz_st - 0.004)))
            for j in range(n_st_phi):
                j_nxt = (j + 1) % n_st_phi
                bm_g_straps.faces.new([st_top[j], st_top[j_nxt], st_bot[j_nxt], st_bot[j]])

        bmesh.ops.solidify(bm_greave, geom=bm_greave.faces[:], thickness=0.0030)
        bmesh.ops.solidify(bm_g_rim, geom=bm_g_rim.faces[:], thickness=0.0022)
        bmesh.ops.solidify(bm_g_straps, geom=bm_g_straps.faces[:], thickness=0.0022)

        parts.append(create_rigid_fn(f"Armor_Mingguang_01_Greaves_{side}", bm_greave, mat_silver, bone_leg, "armor", visual_id, armature))
        parts.append(create_rigid_fn(f"Armor_Mingguang_01_Greave_Rim_{side}", bm_g_rim, mat_gold, bone_leg, "armor", visual_id, armature))
        parts.append(create_rigid_fn(f"Armor_Mingguang_01_Greave_Straps_{side}", bm_g_straps, mat_leather, bone_leg, "armor", visual_id, armature))

    return parts
