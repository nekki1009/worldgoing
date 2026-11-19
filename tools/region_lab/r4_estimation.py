"""Explicitly marked 20 m height estimates for r4 source gaps.

Original MOI samples are never modified.  Estimates are a playable terrain
surface, not additional measurements.  All calculations use the same global
20 m lattice and fixed windows, so adjacent Region tiles agree at seams.
"""

from __future__ import annotations

import numpy as np

NODATA = -32767
NO_DISTANCE = 65535
POST_M = 20
LOCAL_POSTS = 3       # 60 m, MOI-only interpolation/extrapolation.
OFFSET_POSTS = 10     # 200 m, local MOI/Cop shape anchor.
FAR_POSTS = 50        # 1000 m, explicit quality-4 candidate ceiling.

METHODS = {
    0: "original_moi_or_no_height",
    1: "local_moi_plane_or_idw",
    2: "cop_relative_shape_local_moi_offset",
    3: "long_range_moi_plane_or_idw",
    4: "cop_relative_shape_island_moi_offset",
    5: "cop_relative_shape_local_shoreline_zero_anchor",
    6: "coastal_support_estimate",
}


def _near_points(valid: np.ndarray, components: np.ndarray, component: int,
                 row: int, col: int, radius: int):
    r0, r1 = max(0, row - radius), min(valid.shape[0], row + radius + 1)
    c0, c1 = max(0, col - radius), min(valid.shape[1], col + radius + 1)
    points = np.argwhere(valid[r0:r1, c0:c1] &
                         (components[r0:r1, c0:c1] == component))
    if not points.size:
        return np.empty(0, dtype=np.int32), np.empty(0, dtype=np.int32), np.empty(0)
    yy = points[:, 0] + r0
    xx = points[:, 1] + c0
    dist = np.hypot((yy - row) * POST_M, (xx - col) * POST_M)
    inside = dist <= radius * POST_M
    order = np.argsort(dist[inside], kind="stable")
    return yy[inside][order], xx[inside][order], dist[inside][order]


def _moi_surface(raw: np.ndarray, rows: np.ndarray, cols: np.ndarray,
                 distances: np.ndarray, row: int, col: int) -> float:
    """Fit a small weighted plane; IDW covers collinear/undersupported edges."""
    n = min(len(rows), 24)
    yy, xx, d = rows[:n], cols[:n], distances[:n]
    values = raw[yy, xx].astype(np.float64)
    weights = 1.0 / np.maximum(d, POST_M)
    if n >= 4:
        design = np.column_stack((np.ones(n), (xx - col) * POST_M, (yy - row) * POST_M))
        scaled = design * np.sqrt(weights[:, None])
        if np.linalg.matrix_rank(scaled) == 3:
            coefficients = np.linalg.lstsq(scaled, values * np.sqrt(weights), rcond=None)[0]
            value = float(coefficients[0])
        else:
            value = float(np.average(values, weights=weights))
    else:
        value = float(np.average(values, weights=weights))
    # Prevent a one-sided fit from launching far outside the observed neighborhood.
    margin = min(40.0, max(5.0, float(d[0]) * .15))
    return float(np.clip(value, float(values.min()) - margin, float(values.max()) + margin))


def _local_cop_offset(raw: np.ndarray, valid: np.ndarray, components: np.ndarray,
                      component: int, cop: np.ndarray, wbm: np.ndarray,
                      row: int, col: int) -> float | None:
    radius = OFFSET_POSTS
    r0, r1 = max(0, row - radius), min(raw.shape[0], row + radius + 1)
    c0, c1 = max(0, col - radius), min(raw.shape[1], col + radius + 1)
    pair = (valid[r0:r1, c0:c1] &
            (components[r0:r1, c0:c1] == component) &
            np.isfinite(cop[r0:r1, c0:c1]) & (wbm[r0:r1, c0:c1] == 0))
    yy, xx = np.ogrid[r0:r1, c0:c1]
    pair &= (yy - row) ** 2 + (xx - col) ** 2 <= radius ** 2
    if int(pair.sum()) < 16:
        return None
    delta = raw[r0:r1, c0:c1][pair].astype(np.float64) - cop[r0:r1, c0:c1][pair]
    median = float(np.median(delta))
    if np.percentile(np.abs(delta - median), 95) > 10.0:
        return None
    return median


def _shore_reference(cop: np.ndarray, shore: np.ndarray,
                     components: np.ndarray, component: int,
                     row: int, col: int) -> float | None:
    radius = FAR_POSTS
    r0, r1 = max(0, row - radius), min(cop.shape[0], row + radius + 1)
    c0, c1 = max(0, col - radius), min(cop.shape[1], col + radius + 1)
    mask = (shore[r0:r1, c0:c1] &
            (components[r0:r1, c0:c1] == component) &
            np.isfinite(cop[r0:r1, c0:c1]))
    yy, xx = np.ogrid[r0:r1, c0:c1]
    mask &= (yy - row) ** 2 + (xx - col) ** 2 <= radius ** 2
    if not np.any(mask):
        return None
    return float(np.median(cop[r0:r1, c0:c1][mask]))


def estimate_posts(raw: np.ndarray, components: np.ndarray, support: np.ndarray,
                   cop: np.ndarray, wbm: np.ndarray,
                   island_offsets: dict[int, float] | None = None):
    """Return height, quality, method, MOI support distance and counts.

    components labels mapped island polygons (0 is sea); support is a one-post strip
    outside mapped land for fine 2 m coast interpolation; it never denotes a
    measured seabed.  Source arrays must include >=1000 m halo around the
    output core, or the caller must report the reduced support window.
    """
    if not (raw.shape == components.shape == support.shape == cop.shape == wbm.shape):
        raise ValueError("r4 estimation arrays have different grids")
    mapped_land = components > 0
    land = mapped_land & ~support
    original = (raw != NODATA) & land
    target = (land | support) & (raw == NODATA)
    heights = np.where(land & (raw != NODATA), raw, NODATA).astype(np.int16)
    quality = np.where(land & (raw != NODATA), 1, 0).astype(np.uint8)
    method = np.zeros(raw.shape, dtype=np.uint8)
    distance_m = np.full(raw.shape, NO_DISTANCE, dtype=np.uint16)
    distance_m[original] = 0
    # A measured zero from the DEM sea raster is support only, not land evidence.
    sea_source_support = support & (raw != NODATA)
    heights[sea_source_support] = raw[sea_source_support]
    quality[sea_source_support] = 4
    method[sea_source_support] = 6
    water_neighbor = np.zeros_like(land, dtype=bool)
    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        shifted = np.roll(mapped_land, (dy, dx), axis=(0, 1))
        water_neighbor |= ~shifted
    # A sub-post island can have no centre sample.  Its touched component and
    # marked sea-side support still supply a same-island shoreline anchor.
    shore = mapped_land & water_neighbor
    counts = {code: 0 for code in METHODS}
    counts["unresolved"] = 0
    for row, col in np.argwhere(target):
        row, col = int(row), int(col)
        component = int(components[row, col])
        if component == 0:
            counts["unresolved"] += 1
            continue
        yy, xx, dd = _near_points(original, components, component, row, col, LOCAL_POSTS)
        if len(dd):
            value = _moi_surface(raw, yy, xx, dd, row, col)
            bracket_x = np.any(xx < col) and np.any(xx > col)
            bracket_y = np.any(yy < row) and np.any(yy > row)
            q = 2 if bracket_x and bracket_y else 3
            m = 1
            nearest = float(dd[0])
        else:
            yy, xx, dd = _near_points(original, components, component, row, col, FAR_POSTS)
            nearest = float(dd[0]) if len(dd) else None
            cop_value = float(cop[row, col])
            if np.isfinite(cop_value):
                local_offset = _local_cop_offset(raw, original, components,
                                                 component, cop, wbm, row, col)
                if local_offset is not None:
                    value, m = cop_value + local_offset, 2
                elif nearest is not None and nearest <= FAR_POSTS * POST_M:
                    # A local MOI shape remains traceable even where Cop's DSM
                    # canopy/building residual defeats a vertical fit.
                    value, m = _moi_surface(raw, yy, xx, dd, row, col), 3
                elif island_offsets is not None and component in island_offsets:
                    value, m = cop_value + island_offsets[component], 4
                else:
                    shore_cop = _shore_reference(cop, shore, components,
                                                 component, row, col)
                    if shore_cop is None:
                        counts["unresolved"] += 1
                        continue
                    value, m = max(0.0, cop_value - shore_cop), 5
            elif nearest is not None:
                value, m = _moi_surface(raw, yy, xx, dd, row, col), 3
            else:
                counts["unresolved"] += 1
                continue
            q = 4
        if support[row, col]:
            m = 6
            q = 4
        heights[row, col] = int(np.clip(np.rint(value), -20, 9000))
        quality[row, col] = q
        method[row, col] = m
        distance_m[row, col] = NO_DISTANCE if nearest is None else min(int(np.rint(nearest)), NO_DISTANCE - 1)
        counts[m] += 1
    return heights, quality, method, distance_m, counts


def _self_check() -> None:
    raw = np.full((15, 15), NODATA, dtype=np.int16)
    raw[2:13, 2:13] = 20
    raw[7, 7] = NODATA
    land = np.zeros_like(raw, dtype=bool)
    land[2:13, 2:13] = True
    components = land.astype(np.uint16)
    support = np.zeros_like(land)
    cop = np.full(raw.shape, 22, dtype=np.float32)
    wbm = np.zeros(raw.shape, dtype=np.uint8)
    h, q, m, d, _ = estimate_posts(raw, components, support, cop, wbm)
    assert h[7, 7] == 20 and q[7, 7] == 2 and m[7, 7] == 1 and d[7, 7] == 20
    assert h[3, 3] == raw[3, 3] and q[3, 3] == 1
    assert h[0, 0] == NODATA and q[0, 0] == 0
    # A nearby but disconnected island must never supply a missing height.
    components = np.zeros((15, 15), dtype=np.uint16)
    components[2:5, 2:5] = 1
    components[2:5, 7:10] = 2
    raw = np.full((15, 15), NODATA, dtype=np.int16)
    raw[3, 3] = 900
    raw[3, 9] = 10
    h, q, _, _, _ = estimate_posts(raw, components, np.zeros_like(land),
                                   np.full(raw.shape, np.nan, dtype=np.float32), wbm)
    assert h[3, 7] < 100 and q[3, 7] == 3
    # A mapped island narrower than one source post has no centre measurement.
    # Its fine coast still receives explicitly estimated same-island support.
    components = np.zeros((15, 15), dtype=np.uint16)
    components[6:9, 6:9] = 3
    support = components > 0
    raw = np.full((15, 15), NODATA, dtype=np.int16)
    cop = np.full((15, 15), 10, dtype=np.float32)
    h, q, m, _, _ = estimate_posts(raw, components, support, cop, wbm)
    assert h[7, 7] != NODATA and q[7, 7] == 4 and m[7, 7] == 6
    # Overlapping 20m source windows on opposite sides of a Region seam agree.
    components = np.ones((80, 80), dtype=np.uint16)
    raw = np.fromfunction(lambda y, x: 30 + x + 2 * y, (80, 80), dtype=int).astype(np.int16)
    raw[35:43, 37:43] = NODATA
    cop = raw.astype(np.float32) + 2
    a = estimate_posts(raw[:, :60], components[:, :60], np.zeros((80, 60), bool),
                       cop[:, :60], np.zeros((80, 60), np.uint8))
    b = estimate_posts(raw[:, 20:], components[:, 20:], np.zeros((80, 60), bool),
                       cop[:, 20:], np.zeros((80, 60), np.uint8))
    assert np.array_equal(a[0][:, 20:60], b[0][:, :40])
    assert np.array_equal(a[1][:, 20:60], b[1][:, :40])


if __name__ == "__main__":
    _self_check()
    print("r4 estimation self-check PASS")
