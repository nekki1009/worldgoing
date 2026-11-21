"""Reproduce the Lanyu r3 trial coast artifact from pinned source rasters."""

from __future__ import annotations

import json
import zlib
from contextlib import ExitStack
from pathlib import Path

import numpy as np
import rasterio
from pyproj import Transformer
from rasterio.transform import from_origin
from shapely.geometry import box

import import_taiwan as atlas


SITE = (1545, 12170)
ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "assets/region_lab/earth_tw_tm2_121_v1"
TRIAL = ROOT / "assets/region_lab/earth_tw_tm2_121_v1_r3_trial"


def tile_window(folder: Path, manifest: dict, suffix: str, dtype: str) -> np.ndarray:
    sx, sy = SITE
    tile = next(t for t in manifest["elevation_tiles"] if t["id"] == f"r{sx // 100}_{sy // 100}")
    path = tile["derived"][suffix] if suffix else tile["path"]
    array = np.frombuffer(zlib.decompress((folder / path).read_bytes()), dtype=dtype).reshape(1000, 1000)
    row, col = (99 - sy % 100) * 10, sx % 100 * 10
    return array[row:row + 10, col:col + 10]


def main() -> None:
    old = json.loads((BASE / "manifest.json").read_text(encoding="utf-8"))
    new = json.loads((TRIAL / "manifest.json").read_text(encoding="utf-8"))
    old_water = tile_window(BASE, old, "water_path", "u1")
    new_water = tile_window(TRIAL, new, "water_path", "u1")
    decision = tile_window(TRIAL, new, "coast_decision_path", "u1")
    sx, sy = SITE
    rx, ry = sx // 100, sy // 100
    west, south = rx * atlas.REGION_M, ry * atlas.REGION_M
    radius = atlas.LEVEL_RADIUS
    side = atlas.SAMPLES_PER_REGION + 2 * radius
    bounds = box(west - radius * atlas.SAMPLE_M, south - radius * atlas.SAMPLE_M,
                 west + atlas.REGION_M + radius * atlas.SAMPLE_M,
                 south + atlas.REGION_M + radius * atlas.SAMPLE_M)
    transform = from_origin(bounds.bounds[0], bounds.bounds[3], atlas.SAMPLE_M, atlas.SAMPLE_M)
    row, col = radius + (99 - sy % 100) * 10, radius + sx % 100 * 10
    with ExitStack() as stack:
        main_dem = stack.enter_context(rasterio.open(atlas.TEMP / "dem_20m.tif"))
        penghu_dem = stack.enter_context(rasterio.open(atlas.TEMP / "phDEM_20m_121.tif"))
        moi = atlas.source_dem(main_dem, penghu_dem, west, south, halo=radius)[row:row + 10, col:col + 10]
        _, cop_sources = atlas.copernicus_sources(stack)
        cop_height, cop_water, overlap_conflicts = atlas.copernicus_halo(
            cop_sources, transform, (side, side), bounds)
        cop_height = cop_height[row:row + 10, col:col + 10]
        cop_water = cop_water[row:row + 10, col:col + 10]

    accepted = decision == 1
    disputed = decision == 5
    accepted_rule = ((moi > 2) & (cop_water == 0) & (cop_height > 2)
                     & (np.abs(cop_height - moi) <= 10))
    disputed_rule = ((moi > 2) & (cop_water == 0) & (cop_height > 2)
                     & (np.abs(cop_height - moi) > 10))
    if not np.all(accepted <= accepted_rule) or not np.all(disputed <= disputed_rule):
        raise ValueError("Packaged coast decisions do not match the pinned source samples")
    if not np.all((decision == 1) <= ((old_water != 0) & (new_water == 0))):
        raise ValueError("Accepted source posts are not precisely the new land")
    center = Transformer.from_crs("EPSG:3826", "EPSG:4326", always_xy=True).transform(
        sx * 200 + 100, sy * 200 + 100)
    counts = np.bincount(decision.ravel(), minlength=7)
    result = {
        "site": list(SITE), "center_lonlat": list(center), "region": [rx, ry],
        "post_spacing_m": 20, "gameplay_cell_m": 2,
        "r2_land_posts": int(np.count_nonzero(old_water == 0)),
        "r2_sea_posts": int(np.count_nonzero(old_water == 2)),
        "r3_land_posts": int(np.count_nonzero(new_water == 0)),
        "r3_sea_posts": int(np.count_nonzero(new_water == 2)),
        "decision_counts": {str(i): int(v) for i, v in enumerate(counts)},
        "MOI_TWVD2001_height_m": moi.tolist(),
        "Copernicus_EGM2008_DSM_height_m": np.round(cop_height, 2).tolist(),
        "Copernicus_WBM_code": cop_water.tolist(),
        "r2_water_code": old_water.tolist(),
        "r3_water_code": new_water.tolist(),
        "coast_decision_code": decision.tolist(),
        "visual_capture": ".visual_captures/region_lab/r3_trial_20260927_01/lanyu.png",
        "assessment": "Reject r3 for promotion: a per-20m-post 10m cross-datum DSM threshold fragments the shoreline into visible square land and sea blocks at 2m gameplay scale. Do not smooth or invent a 2m shoreline.",
        "source_overlap_conflicts_in_region_halo": overlap_conflicts,
        "source_manifest_paths": [str(BASE / "manifest.json"), str(TRIAL / "manifest.json")],
    }
    target = TRIAL / "coast_counterexample_lanyu.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Verified {int(counts[1])} accepted and {int(counts[5])} DSM-disputed posts: {target}")


if __name__ == "__main__":
    main()
