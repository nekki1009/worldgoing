"""Measure MOI height support for the fixed OSM coastline before building r4.

This probe only reads the pinned inputs and writes an isolated JSON report.
"""

from __future__ import annotations

from collections import Counter
import json
from pathlib import Path
import time

import numpy as np
import rasterio
from pyproj import Transformer
from rasterio.features import rasterize
from rasterio.transform import from_origin
from shapely.geometry import box, shape
from shapely.ops import transform
from shapely.strtree import STRtree

import import_taiwan as atlas


INPUT = atlas.TEMP / "osm_source" / "land.geojson"
OUT = atlas.ROOT / "assets/region_lab/earth_tw_tm2_121_v1_r4_probe/osm_height_distance.json"
DISTANCES_M = (20, 40, 60, 100, 200, 400)


def main() -> None:
    deadline = time.monotonic() + 180
    atlas.verify_source(atlas.DEM_ARCHIVE, atlas.DEM_SHA)
    atlas.extract_inputs()
    doc = json.loads(INPUT.read_text(encoding="utf-8"))
    project = Transformer.from_crs(4326, 3826, always_xy=True).transform
    polygons = [transform(project, shape(f["geometry"])) for f in doc["features"]]
    tree = STRtree(polygons)
    bounds = atlas.projected_bounds()
    west, east, south, north = bounds
    r2_manifest = json.loads((atlas.OUT / "manifest.json").read_text(encoding="utf-8"))
    r2_summary = np.frombuffer((atlas.OUT / "summary.u8").read_bytes(), dtype="u1").reshape(
        r2_manifest["summary"]["size"][1], r2_manifest["summary"]["size"][0])
    r2_scope = np.frombuffer((atlas.OUT / "content_scope.u8").read_bytes(), dtype="u1").reshape(r2_summary.shape)
    missing = (r2_summary == 0) & (r2_scope >= 1) & (r2_scope <= 4)
    if int(missing.sum()) != 11711:
        raise ValueError(f"Changed r2 baseline: {int(missing.sum())} missing Sites")
    osm_summary = atlas.coastal_summary(polygons, bounds)
    counters: dict[str, Counter] = {name: Counter() for name in
        ("taiwan", "penghu", "green_island", "lanyu")}
    examples = []
    seen_posts = set()
    with rasterio.open(atlas.TEMP / "dem_20m.tif") as main_dem, rasterio.open(
            atlas.TEMP / "phDEM_20m_121.tif") as penghu_dem:
        for ry in range(south, north):
            if time.monotonic() > deadline:
                raise TimeoutError("OSM/MOI support probe exceeded 180 seconds")
            for rx in range(west, east):
                sr, sc = (north - 1 - ry) * 100, (rx - west) * 100
                local_missing = missing[sr:sr + 100, sc:sc + 100]
                if not np.any(local_missing):
                    continue
                origin_e, origin_n = rx * atlas.REGION_M, ry * atlas.REGION_M
                radius = 40  # Include a full 400 m support search across Region edges.
                side = atlas.SAMPLES_PER_REGION + radius * 2
                rect = box(origin_e - radius * atlas.SAMPLE_M,
                           origin_n - radius * atlas.SAMPLE_M,
                           origin_e + atlas.REGION_M + radius * atlas.SAMPLE_M,
                           origin_n + atlas.REGION_M + radius * atlas.SAMPLE_M)
                transform20 = from_origin(rect.bounds[0], rect.bounds[3],
                                          atlas.SAMPLE_M, atlas.SAMPLE_M)
                land = rasterize([(polygons[i], 1) for i in tree.query(rect)],
                                 out_shape=(side, side), transform=transform20,
                                 fill=0, dtype="uint8") == 1
                moi = atlas.source_dem(main_dem, penghu_dem, origin_e, origin_n, halo=radius)
                valid = land & (moi != atlas.NODATA)
                target_window = np.zeros_like(land)
                for site_row, site_col in np.argwhere(local_missing):
                    r0, c0 = radius + int(site_row) * 10 - 1, radius + int(site_col) * 10 - 1
                    target_window[r0:r0 + 12, c0:c0 + 12] = True
                    scope_name = tuple(counters)[r2_scope[sr + site_row, sc + site_col] - 1]
                    count = counters[scope_name]
                    osm_class = int(osm_summary[sr + site_row, sc + site_col])
                    count[f"osm_class_{osm_class}_sites"] += 1
                    if osm_class != 1:
                        count["osm_land_or_mixed_sites"] += 1
                targets = np.argwhere(target_window & land & (moi == atlas.NODATA))
                for row, col in targets:
                    row, col = int(row), int(col)
                    global_post = (rx * 1000 + col - radius,
                                   ry * 1000 + 999 - (row - radius))
                    if global_post in seen_posts:
                        continue
                    seen_posts.add(global_post)
                    sy = min(max(row - radius, 0) // 10, 99)
                    sx = min(max(col - radius, 0) // 10, 99)
                    code = int(r2_scope[sr + sy, sc + sx])
                    if code not in (1, 2, 3, 4):
                        continue
                    scope_name = tuple(counters)[code - 1]
                    count = counters[scope_name]
                    count["unique_osm_land_moi_nodata_posts_in_gap_windows"] += 1
                    window_radius = 20  # Probe to 400 m; larger support remains explicitly unmeasured.
                    r0, r1 = max(0, row - window_radius), min(side, row + window_radius + 1)
                    c0, c1 = max(0, col - window_radius), min(side, col + window_radius + 1)
                    near = np.argwhere(valid[r0:r1, c0:c1])
                    if near.size:
                        dy = near[:, 0] + r0 - row
                        dx = near[:, 1] + c0 - col
                        distance = float(np.sqrt(np.min(dx * dx + dy * dy)) * atlas.SAMPLE_M)
                        bucket = next((f"nearest_m_le_{limit}" for limit in DISTANCES_M
                                       if distance <= limit), "nearest_m_gt_400")
                    else:
                        distance = None
                        bucket = "no_moi_within_400m_square"
                    count[bucket] += 1
                    if len(examples) < 30 and (distance is None or distance > 200):
                        examples.append({"region": [rx, ry], "post_row_col": [row, col],
                                         "scope": scope_name, "nearest_m": distance})
            print(f"Region row {ry}/{north - 1}", flush=True)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    report = {"status": "read_only_osm_moi_support_probe", "osm_land_sha256": atlas.sha256(INPUT),
              "r2_manifest_sha256": atlas.sha256(atlas.OUT / "manifest.json"),
              "distance_probe_max_m": 400,
              "distance_note": "nearest source MOI post inside OSM land, Euclidean 20m lattice; source window has 800m halo, including full 400m search across Region edges",
              "by_scope": {name: dict(c) for name, c in counters.items()},
              "far_examples": examples}
    OUT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Wrote", OUT)


if __name__ == "__main__":
    main()
