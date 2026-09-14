"""Offline continuous body/all-shield bound from the actual native exporter.

No Godot, pose sampling, baked silhouette maxima, asset edits or dependencies.
All algebraic radii round outward in binary64. The separate float32 deployment
budget is an explicit conditional gate, not an assertion that a GPU was tested.
"""

import argparse
import hashlib
import json
import math
from pathlib import Path


def up(value):
    assert math.isfinite(value)
    return math.nextafter(value, math.inf)


def add(a, b):
    return up(a + b)


def mul(a, b):
    assert a >= 0 and b >= 0
    return up(a * b)


def norm(values):
    total = 0.0
    for value in values:
        total = add(total, mul(abs(value), abs(value)))
    return up(math.sqrt(total))


def dot_interval(a, b):
    lo = hi = 0.0
    for x, y in zip(a, b):
        product = x * y
        lo = math.nextafter(lo + math.nextafter(product, -math.inf), -math.inf)
        hi = up(hi + up(product))
    return lo, hi


def operator_norm(columns):
    """Spectral norm upper bound via both Gram matrices' row sums."""
    limits = []
    for vectors in (columns, list(zip(*columns))):
        rows = []
        for a in vectors:
            total = 0.0
            for b in vectors:
                lo, hi = dot_interval(a, b)
                total = add(total, max(abs(lo), abs(hi)))
            rows.append(total)
        limits.append(up(math.sqrt(max(rows))))
    return min(limits)


def transformed_radius(transform, vertex):
    """Outward norm of the actual native bind-pose transformed vertex."""
    components = []
    for row in range(3):
        lo, hi = dot_interval([transform[c][row] for c in range(3)], vertex)
        lo = math.nextafter(lo + transform[3][row], -math.inf)
        hi = up(hi + transform[3][row])
        components.append(max(abs(lo), abs(hi)))
    return norm(components)


def analyze(data):
    bones = data["bones"]
    names = {bone["name"]: bone["index"] for bone in bones}
    translation = [norm(bone["rest"][3]) for bone in bones]
    scale = [operator_norm(bone["rest"][:3]) for bone in bones]
    unsupported = []
    stats = {"position_keys": 0, "rotation_keys": 0, "scale_keys": 0,
             "irrelevant_morph_keys": 0, "max_rotation_norm_error": 0.0,
             "maximum_position_extrapolation_metres": 0.0, "maximum_match_time_ratio": 0.0}
    if data["default_blend"] != 0 or data["blend_times"] or data["queue"] or data["root_motion"]:
        unsupported.append("Nonzero blending, queue or root motion")
    for animation in data["animations"]:
        length = animation["length"]
        if not math.isfinite(length) or length <= 0:
            unsupported.append("Invalid native animation length: " + animation["name"])
            continue
        if animation["next"]:
            unsupported.append("Queued next clip: " + animation["name"])
        seen = set()
        for track in animation["tracks"]:
            kind = track["type_name"]
            label = f'{animation["name"]}:{track["index"]}:{track["path"]}'
            if kind == "blend_shape":
                if "Face_Standard" in track["path"] or "Shield_" in track["path"]:
                    unsupported.append("Morph on a body/shield collider: " + label)
                stats["irrelevant_morph_keys"] += len(track["keys"])
                continue
            if kind not in ("position", "rotation", "scale") or track["interpolation"] not in (0, 1) or track["compressed"]:
                unsupported.append("Unproven native curve: " + label)
                continue
            bone = track["bone"]
            if not 0 <= bone < len(bones) or (bone, kind) in seen:
                unsupported.append("Missing/duplicate fixed bone path: " + label)
                continue
            seen.add((bone, kind))
            keys = track["keys"]
            match_time = mul(1e-5, max(1, length))
            if kind == "position" and (not keys or (len(keys) > 1 and (keys[0][0] != 0 or keys[-1][0] != length))):
                unsupported.append("Incomplete native position time endpoints: " + label)
                continue
            previous_time = -math.inf
            previous_position = None
            position_norm = position_slope = 0.0
            for time, transition, value in keys:
                if not math.isfinite(time) or not 0 <= time <= length or time < previous_time or transition != 1 or not all(map(math.isfinite, value)):
                    unsupported.append("Unproven key: " + label)
                    break
                stats[kind + "_keys"] += 1
                if kind == "position":
                    if previous_position is not None:
                        delta = time - previous_time
                        if delta <= 0 or match_time / delta > .01:
                            unsupported.append("Dense native position times: " + label)
                            break
                        stats["maximum_match_time_ratio"] = max(stats["maximum_match_time_ratio"], up(match_time / delta))
                        # Float32 input differences are exact in binary64 here.
                        position_slope = max(position_slope, up(norm([x - y for x, y in zip(value, previous_position)]) / delta))
                    position_norm = max(position_norm, norm(value))
                    previous_position = value
                elif kind == "scale":
                    scale[bone] = max(scale[bone], max(map(abs, value)))
                else:
                    qnorm = math.sqrt(sum(x * x for x in value))
                    if qnorm == 0:
                        unsupported.append("Zero quaternion: " + label)
                    stats["max_rotation_norm_error"] = max(stats["max_rotation_norm_error"], abs(qnorm - 1))
                previous_time = time
            if kind == "position":
                extrapolation = mul(mul(2, match_time), position_slope)
                stats["maximum_position_extrapolation_metres"] = max(stats["maximum_position_extrapolation_metres"], extrapolation)
                translation[bone] = max(translation[bone], add(position_norm, extrapolation))

    def chain(root=-1):
        radii, gains = {}, {}
        if root >= 0:
            radii[root], gains[root] = 0.0, 1.0

        def visit(index, pending=()):
            if index in radii:
                return
            if index in pending or not 0 <= index < len(bones):
                raise ValueError("Non-tree skeleton")
            parent = bones[index]["parent"]
            if parent == -1:
                if root >= 0:
                    raise ValueError("Face influence outside head descendants")
                radii[index], gains[index] = translation[index], scale[index]
            else:
                visit(parent, pending + (index,))
                radii[index] = add(radii[parent], mul(gains[parent], translation[index]))
                gains[index] = mul(gains[parent], scale[index])

        return radii, gains, visit

    radii, gains, visit = chain()
    for index in range(len(bones)):
        visit(index)
    head = names["J_Bip_C_Head"]
    head_radii, head_gains, head_visit = chain(head)
    world_scale = operator_norm(data["skeleton_transform"][:3])
    world_origin = norm(data["skeleton_transform"][3])
    projection = data["projection"]
    if projection["type"] != 1:
        unsupported.append("Non-orthographic projection")
    pixels = operator_norm(projection["map_axes"])
    pixel_origin = norm(projection["map_origin"])
    offset = projection["maximum_combat_offset_pixels"]

    def projected(radius):
        return add(pixel_origin, mul(pixels, add(world_origin, mul(world_scale, radius))))

    limbs = []
    camera_x = norm(projection["camera_transform"][0])
    for start, end, radius in projection["limbs"]:
        centre = projected(max(radii[names[start]], radii[names[end]]))
        thickness = mul(mul(pixels, camera_x), radius)
        limbs.append({"start": start, "end": end, "pixels_before_offset": add(centre, thickness)})

    mesh_bounds, excluded = [], []
    max_influences = 0
    max_bind_radius = 0.0
    for mesh in data["meshes"]:
        name = mesh["name"]
        if name.startswith("Weapon_"):
            # No weapon is in the body/all-shield bound. Guard parry retains
            # the original 256 path; bow/crossbow never acquire melee bounds.
            excluded.append(name)
            continue
        if mesh["blend_shapes"] or not mesh["skin_id"]:
            unsupported.append("Unproven body/shield mesh: " + name)
            continue
        binds = data["skins"][mesh["skin_id"]]
        is_face = name.startswith("Face_Standard")
        radius = 0.0
        weights_min, weights_max = math.inf, -math.inf
        influence_bones = set()
        for surface in mesh["surfaces"]:
            vertices, weights, indices = surface["vertices"], surface["weights"], surface["bones"]
            assert vertices and len(indices) == len(weights) and len(indices) % len(vertices) == 0
            influences = len(indices) // len(vertices)
            max_influences = max(max_influences, influences)
            for vertex_index, vertex in enumerate(vertices):
                extent, total_weight = 0.0, 0.0
                for influence in range(influences):
                    location = vertex_index * influences + influence
                    weight = weights[location]
                    total_weight += weight
                    if weight == 0:
                        continue
                    binding = binds[indices[location]]
                    bone = binding["bone"]
                    assert 0 <= bone < len(bones)
                    influence_bones.add(bone)
                    bind_radius = transformed_radius(binding["pose"], vertex)
                    max_bind_radius = max(max_bind_radius, bind_radius)
                    if is_face:
                        head_visit(bone)
                        extent = add(extent, mul(abs(weight), add(head_radii[bone], mul(head_gains[bone], bind_radius))))
                    else:
                        extent = add(extent, mul(abs(weight), add(radii[bone], mul(gains[bone], bind_radius))))
                weights_min, weights_max = min(weights_min, total_weight), max(weights_max, total_weight)
                if is_face and total_weight != 1.0:
                    unsupported.append("Head inverse cancellation needs exact unit weight sum: " + name)
                radius = max(radius, extent)
        if is_face:
            # The first posed face is fitted into a head-local AABB. Each of
            # its three coordinates lies in [-radius,+radius], hence sqrt(3).
            corner_radius = mul(up(math.sqrt(3.0)), radius)
            total_radius = add(radii[head], mul(gains[head], corner_radius))
        else:
            corner_radius, total_radius = None, radius
        mesh_bounds.append({"name": name, "head_local_radius": radius if is_face else None,
                            "head_aabb_corner_radius": corner_radius, "world_radius_before_root": total_radius,
                            "pixels_before_offset": projected(total_radius),
                            "influence_bones": [bones[i]["name"] for i in sorted(influence_bones)],
                            "weight_sum_range": [weights_min, weights_max]})
    body_pixels = max([x["pixels_before_offset"] for x in limbs] +
                      [x["pixels_before_offset"] for x in mesh_bounds if x["name"].startswith("Face_")])
    shield_pixels = max(x["pixels_before_offset"] for x in mesh_bounds if x["name"].startswith("Shield_"))
    all_pixels = add(max(body_pixels, shield_pixels), offset)
    depth = max(_depth(bones, i) for i in range(len(bones)))
    return {"status": "CONTINUOUS_REAL_ALGEBRA_BOUND" if not unsupported else "UNSUPPORTED",
            "unsupported": sorted(set(unsupported)), "statistics": stats, "depth": depth,
            "max_influences": max_influences, "max_bind_radius": max_bind_radius,
            "projection_norm_upper": pixels, "world_scale_upper": world_scale,
            "body_pixels_with_offset": add(body_pixels, offset),
            "shield_pixels_with_offset": add(shield_pixels, offset),
            "body_allshield_pixels_with_offset": all_pixels,
            "parry": "Original 256 fallback; no weapon radius admitted",
            "deployment_ready": False, "limbs": limbs, "meshes": mesh_bounds, "excluded_weapons": excluded,
            "bones": [{"name": b["name"], "parent": b["parent"], "translation_norm_upper": translation[i],
                       "local_scale_upper": scale[i], "chain_radius_upper": radii[i], "chain_scale_upper": gains[i]}
                      for i, b in enumerate(bones)]}


def _depth(bones, index):
    seen = set()
    while index >= 0:
        assert index not in seen
        seen.add(index)
        index = bones[index]["parent"]
    return len(seen)


def guarded_float32_envelope(data, report):
    """A deliberately loose error budget for this fixed, unaimed native rig.

    This is forward error, not a sampled maximum. See the adjacent proof note
    for the elementary-operation bounds and the still-required runtime guards.
    Treat each actual local rotation as an arbitrary rotation: its angle need
    not agree with an ideal slerp; only the native quaternion-to-Basis norm is
    used. No IK, scale animation, blending or general camera is admitted.
    """
    u = 2 ** -24
    gamma = lambda n: up(n * u / (1 - n * u))
    relevant = [m for m in data["meshes"] if not m["name"].startswith("Weapon_")]
    rests = [norm(b["rest"][axis]) for b in data["bones"] for axis in range(3)]
    bind_gain = max(operator_norm(b["pose"][:3]) for skin in data["skins"].values() for b in skin)
    bind_origin = max(norm(b["pose"][3]) for skin in data["skins"].values() for b in skin)
    vertex_radius = max(norm(v) for m in relevant for s in m["surfaces"] for v in s["vertices"])
    face_vertices = max(sum(len(s["vertices"]) for s in m["surfaces"]) for m in relevant if m["name"].startswith("Face_"))
    shield_vertices = sum(len(s["vertices"]) for m in relevant if m["name"].startswith("Shield_") for s in m["surfaces"])
    actual = {"maximum_depth_with_world_root": report["depth"] + 1,
              "minimum_rest_column_length": min(rests), "maximum_rest_column_length": max(rests),
              "maximum_chain_radius": max(b["chain_radius_upper"] for b in report["bones"]),
              "maximum_local_translation": max(b["translation_norm_upper"] for b in report["bones"]),
              "maximum_bind_gain": bind_gain, "maximum_bind_origin": bind_origin,
              "maximum_vertex_radius": vertex_radius, "maximum_face_vertices": face_vertices,
              "maximum_body_shield_hull_vertices": shield_vertices + 10 * 24 + 8}
    gates = [actual["maximum_depth_with_world_root"] <= 16, min(rests) >= .999, max(rests) <= 1.001,
             actual["maximum_chain_radius"] <= 3, actual["maximum_local_translation"] <= 1.1,
             bind_gain <= 1.01, bind_origin <= 2, vertex_radius <= 2,
             face_vertices <= 4096, actual["maximum_body_shield_hull_vertices"] <= 4096,
             report["max_influences"] <= 4, report["statistics"]["scale_keys"] == 0,
             report["statistics"]["max_rotation_norm_error"] < .001,
             report["projection_norm_upper"] < 38, report["world_scale_upper"] < 1.001,
             data["projection"]["viewport"] == [1280, 1536],
             all(m["weight_sum_range"][0] >= 0 and m["weight_sum_range"][1] <= 1 for m in report["meshes"]),
             all(w >= 0 for m in relevant for s in m["surfaces"] for w in s["weights"])]
    if not all(gates) or report["unsupported"]:
        return {"status": "UNSUPPORTED_FIXED_NUMERIC_ENVELOPE", "actual": actual}
    # Local native lerp/rest accumulation and quaternion-Basis reconstruction:
    # each is < 1e-5 in the admitted unit-scale range. G/R below are loose
    # bounds over the complete original chain, not max-key pose samples.
    eb = et = 0.0
    g, r, s, t, local_error = 1.02, 3.0, 1.001, 1.1, 1e-5
    for _ in range(16):
        et = et + eb * t + (g + eb) * local_error + gamma(4) * (math.sqrt(3) * (g + eb) * (t + local_error) + r + et)
        eb = eb * s + (g + eb) * local_error + 3 * gamma(3) * (g + eb) * (s + local_error)
    # One more actual palette product with the original bind, then the
    # original four weighted transformed vertices. Bounds cover rigid too.
    palette_basis_error = eb * 1.01 + 3 * gamma(3) * (g + eb) * 1.01
    palette_origin_error = et + eb * 2 + gamma(4) * (math.sqrt(3) * (g + eb) * 2 + r + et)
    point_error = palette_basis_error * 2 + palette_origin_error + gamma(4) * (math.sqrt(3) * ((g + eb) * 1.01 + palette_basis_error) * 2 + r + (g + eb) * 2 + palette_origin_error)
    point_error += gamma(8) * (3 + point_error) # sum |w| <= 1, four products/additions.
    # Head inverse: lower singular bound before and after chain rounding.
    # The 1e-5 local matrix error also covers rest-column scale extraction.
    minimum_singular = (.999 - local_error) ** 16
    actual_minimum_singular = minimum_singular - eb
    determinant_minimum = actual_minimum_singular ** 3
    m = g + eb
    cofactor_error = gamma(2) * 2 * m * m
    determinant_error = 3 * m * cofactor_error + gamma(3) * 3 * m * (2 * m * m + cofactor_error)
    inverse_rounding = 3 * (cofactor_error / (determinant_minimum - determinant_error)
        + 2 * m * m * determinant_error / (determinant_minimum * (determinant_minimum - determinant_error))
        + gamma(2) * (2 * m * m + cofactor_error) / (determinant_minimum - determinant_error))
    inverse_error = eb / (minimum_singular * actual_minimum_singular) + inverse_rounding
    inverse_gain = 1 / minimum_singular + inverse_error
    inverse_origin_error = inverse_error * r + inverse_gain * et + gamma(3) * math.sqrt(3) * inverse_gain * (r + et)
    local_head_error = inverse_error * 3 + inverse_gain * point_error + inverse_origin_error + gamma(4) * (math.sqrt(3) * inverse_gain * (3 + point_error) + inverse_gain * (r + et))
    # AABB.expand stores end-begin then reconstructs begin+size next time;
    # 4096 repeated fits are included, not incorrectly treated as min/max only.
    head_radius = .25 # Runtime gate; wider than the actual .201048 native face radius.
    aabb_error = gamma(3 * 4096) * 2 * (head_radius + local_head_error)
    corner_error = math.sqrt(3) * (local_head_error + aabb_error)
    head_error = g * corner_error + eb * (math.sqrt(3) * head_radius + corner_error) + et + gamma(4) * (math.sqrt(3) * (g + eb) * (math.sqrt(3) * head_radius + corner_error) + r + et)
    geometry_error_pixels = 38 * max(point_error, head_error, et)
    # Two projection paths: direct unproject versus four-point axes followed
    # by packed affine. The audit admits camera/unit/sprite bounds only.
    unproject_error = gamma(32) * 8192
    projection_error_pixels = (1 + 2 * math.sqrt(3) * 3) * unproject_error * .2 + gamma(8) * 4096 * .2
    local_rect_error = gamma(3 * 4096) * 2 * 128
    # Original world translation, grow/intersects and half-open has_point:
    # <= 16 operations, |endpoints|<=16384: differences/summed absolute
    # terms can reach 65536. Do not confuse coordinates with intermediate sums.
    final_map_error = gamma(16) * 65536
    total = math.ceil((geometry_error_pixels + projection_error_pixels + local_rect_error + final_map_error) * 100) / 100
    return {"status": "CONDITIONAL_FIXED_NATIVE_FORWARD_ERROR_BOUND", "actual": actual,
            "unit_roundoff": u, "local_pose_error_budget": local_error,
            "chain_basis_error": eb, "chain_origin_error_metres": et,
            "head_minimum_singular": minimum_singular, "head_inverse_gain_upper": inverse_gain,
            "head_inverse_rounding_error": inverse_rounding, "head_fit_error_metres": local_head_error,
            "head_aabb_repeat_error_metres": aabb_error,
            "geometry_error_pixels": geometry_error_pixels, "both_projection_paths_error_pixels": projection_error_pixels,
            "local_rect_repeat_error_pixels": local_rect_error, "final_map_error_pixels": final_map_error,
            "total_error_pixels": total, "whole_pixel_padding": math.ceil(total),
            "rounded_outward_candidate_pixels": math.ceil((report["body_allshield_pixels_with_offset"] + math.ceil(total)) / 16) * 16,
            "runtime_conditions_not_exported": ["motion_scale == 1; no modifiers/global overrides/custom postprocess",
                "single original private model; original clip reset; no aim/IK/attack/guard",
                "same orthographic foot camera, zero offsets, native viewport and sprite contract",
                "fixed model transforms apart from original four cardinal rotations",
                "abs relevant world coordinates <= 16384; source/local collider radius < 128",
                "native resource mutation uses the existing clear/model-generation hook"],
            "deployment_ready": False}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("native", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    assert not args.output.exists(), "Preserve every prior analysis artifact"
    # Tiny exact algebra checks; no sampled animation is used in the proof.
    identity = [[1, 0, 0], [0, 1, 0], [0, 0, 1], [0, 0, 0]]
    assert operator_norm(identity[:3]) >= 1 and transformed_radius(identity, [3, 4, 0]) >= 5
    raw = args.native.read_bytes()
    data = json.loads(raw)
    report = analyze(data)
    report["guarded_float32_envelope"] = guarded_float32_envelope(data, report)
    report["native_sha256"] = hashlib.sha256(raw).hexdigest()
    report["analysis_sha256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print(json.dumps({key: value for key, value in report.items() if key not in ("bones", "meshes", "limbs", "excluded_weapons")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
