"""Read-only coastal gap probe against pinned Copernicus GLO-30 DSM/WBM tiles.

Download the four latitude/longitude tile pairs listed in PROBES into .tmp.
This script never changes the accepted runtime atlas.
"""

from __future__ import annotations

import hashlib
import json
import sys
import zlib
from pathlib import Path

import numpy as np
import rasterio
from rasterio.enums import Resampling
from rasterio.features import rasterize
from rasterio.transform import from_origin
from rasterio.warp import reproject
from shapely.geometry import box

import import_taiwan as atlas


PROBES = (
    ("east_coast", 15, 132, "N23_E121", [1560, 13264]),
    ("taiwan_west_coast", 8, 130, "N23_E120", [850, 13050]),
    ("penghu", 5, 130, "N23_E119", [514, 13040]),
    ("green_island", 15, 125, "N22_E121", [1502, 12534]),
    ("lanyu", 15, 121, "N22_E121", [1528, 12195]),
)
BASE_MANIFEST_SHA = "2ab25eeaa685782b42928d206ec808e4f1bb4da5e771cc67f0f86e8fefb07f61"


def source_record(short: str, suffix: str) -> dict:
    path = atlas.TEMP / f"copernicus_{short}{suffix}.tif"
    if not path.is_file():
        raise FileNotFoundError(path)
    north, east = short.split("_")
    stem = f"Copernicus_DSM_COG_10_{north}_00_{east}_00"
    relative = f"{stem}_DEM/"
    relative += f"AUXFILES/{stem}_WBM.tif" if suffix else f"{stem}_DEM.tif"
    return {"file": path.name, "sha256": atlas.sha256(path), "bytes": path.stat().st_size,
            "url": "https://copernicus-dem-30m.s3.eu-central-1.amazonaws.com/" + relative}


def reproject_tile(src, transform, dtype, fill, method) -> np.ndarray:
    result = np.full((1000, 1000), fill, dtype=dtype)
    reproject(rasterio.band(src, 1), result, src_transform=src.transform, src_crs=src.crs,
              dst_transform=transform, dst_crs="EPSG:3826", dst_nodata=fill,
              resampling=method)
    return result


def good_sites(valid: np.ndarray) -> np.ndarray:
    # Edges are deliberately excluded: this one-Region probe has no corrected
    # neighbour tiles. Final acceptance must use the full atlas halo audit.
    padded = np.pad(valid, 1, constant_values=False)
    bad = (~padded).astype(np.int32)
    integral = np.pad(bad.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    return (integral[12:, 12:] - integral[:-12, 12:] -
            integral[12:, :-12] + integral[:-12, :-12])[::10, ::10] == 0


def probe_one(name, rx, ry, short, example, polygons, manifest, summary, scope, main, penghu):
    transform = from_origin(rx * 20_000, (ry + 1) * 20_000, 20, 20)
    rect = box(rx * 20_000, ry * 20_000, (rx + 1) * 20_000, (ry + 1) * 20_000)
    land = rasterize([(p, 1) for p in atlas.touching(polygons, rect)],
                     out_shape=(1000, 1000), transform=transform, fill=0, dtype="uint8") == 1
    moi = atlas.source_dem(main, penghu, rx * 20_000, ry * 20_000)
    with rasterio.open(atlas.TEMP / f"copernicus_{short}.tif") as dem, \
         rasterio.open(atlas.TEMP / f"copernicus_{short}_WBM.tif") as wbm:
        cop = reproject_tile(dem, transform, np.float32, np.nan, Resampling.bilinear)
        waterbody = reproject_tile(wbm, transform, np.uint8, 255, Resampling.nearest)
    tile = next(t for t in manifest["elevation_tiles"] if t["id"] == f"r{rx}_{ry}")
    height = np.frombuffer(zlib.decompress((atlas.OUT / tile["path"]).read_bytes()),
                           dtype="<i2").reshape(1000, 1000)
    derived = tile["derived"]
    level = np.frombuffer(zlib.decompress((atlas.OUT / derived["levels_path"]).read_bytes()),
                          dtype=np.uint8).reshape(1000, 1000)
    sea = np.frombuffer(zlib.decompress((atlas.OUT / derived["water_path"]).read_bytes()),
                        dtype=np.uint8).reshape(1000, 1000)
    original_valid = (sea == 2) | ((sea == 0) & (height != atlas.NODATA) & (level <= 5))
    common = land & (moi != atlas.NODATA) & (waterbody == 0) & np.isfinite(cop)
    difference = cop[common] - moi[common]
    missing_land = land & (moi == atlas.NODATA)
    possible_fill = missing_land & (waterbody == 0) & np.isfinite(cop)
    # A strong coastal correction requires two independent observations of
    # positive land height, with a conservative cross-source difference bound.
    wrong_sea = (~land) & (moi > 2)
    coast_fix = wrong_sea & (waterbody == 0) & np.isfinite(cop) & (cop > 2) & (np.abs(cop - moi) <= 10)
    candidate_valid = original_valid | possible_fill | coast_fix
    west, east, south, north = atlas.projected_bounds()
    row, col = (north - 1 - ry) * 100, (rx - west) * 100
    region_summary = summary[row:row + 100, col:col + 100]
    region_scope = scope[row:row + 100, col:col + 100]
    original_site_good = good_sites(original_valid)
    candidate_site_good = good_sites(candidate_valid)
    interior = np.zeros((100, 100), bool)
    interior[1:-1, 1:-1] = True
    content = (region_scope >= 1) & (region_scope <= 4)
    recovered = (region_summary == 0) & content & interior & ~original_site_good & candidate_site_good
    ex_row, ex_col = (ry * 100 + 99 - example[1]) * 10, (example[0] - rx * 100) * 10
    sample_trace = []
    for y in range(max(ex_row - 1, 0), min(ex_row + 11, 1000)):
        for x in range(max(ex_col - 1, 0), min(ex_col + 11, 1000)):
            if not original_valid[y, x] and len(sample_trace) < 12:
                sample_trace.append({"easting_m": rx * 20_000 + x * 20 + 10,
                                     "northing_m": (ry + 1) * 20_000 - y * 20 - 10,
                                     "moi_m": None if moi[y, x] == atlas.NODATA else int(moi[y, x]),
                                     "cop_dsm_m": None if not np.isfinite(cop[y, x]) else round(float(cop[y, x]), 2),
                                     "cop_wbm": int(waterbody[y, x]),
                                     "gshhg_land": bool(land[y, x]),
                                     "coast_fix_candidate": bool(coast_fix[y, x]),
                                     "land_height_fill_candidate": bool(possible_fill[y, x])})
    return {
        "region": [rx, ry], "example_site": example,
        "cop_covered_posts": int(np.count_nonzero(waterbody != 255)),
        "official_moi_land_nodata_posts": int(np.count_nonzero(missing_land)),
        "cop_wbm_land_at_missing_moi_posts": int(np.count_nonzero(possible_fill)),
        "positive_moi_height_where_gshhg_says_sea": int(np.count_nonzero(wrong_sea)),
        "coast_fix_candidates_two_sources_and_10m_difference": int(np.count_nonzero(coast_fix)),
        "cop_wbm_lake_posts": int(np.count_nonzero(waterbody == 2)),
        "cop_wbm_river_posts": int(np.count_nonzero(waterbody == 3)),
        "shared_land_height_difference_cop_minus_moi_m": {
            "count": int(difference.size),
            "p05_p50_p95": [round(float(v), 2) for v in np.percentile(difference, [5, 50, 95])] if difference.size else [],
        },
        "currently_missing_content_sites_in_region": int(np.count_nonzero((region_summary == 0) & content)),
        "candidate_recovered_interior_sites_before_height_seam_qc": int(np.count_nonzero(recovered)),
        "example_invalid_source_posts": sample_trace,
    }


def main() -> None:
    manifest_bytes = (atlas.OUT / "manifest.json").read_bytes()
    actual_hash = hashlib.sha256(manifest_bytes).hexdigest()
    if actual_hash != BASE_MANIFEST_SHA:
        raise ValueError("Probe was designed for r2 manifest " + BASE_MANIFEST_SHA)
    manifest = json.loads(manifest_bytes)
    width, height = manifest["summary"]["size"]
    summary = np.frombuffer((atlas.OUT / "summary.u8").read_bytes(), np.uint8).reshape(height, width)
    scope = np.frombuffer((atlas.OUT / "content_scope.u8").read_bytes(), np.uint8).reshape(height, width)
    sources = {short: {"dem": source_record(short, ""), "water_body_mask": source_record(short, "_WBM")}
               for short in sorted({p[3] for p in PROBES})}
    polygons = atlas.land_polygons()
    with rasterio.open(atlas.TEMP / "dem_20m.tif") as main_dem, \
         rasterio.open(atlas.TEMP / "phDEM_20m_121.tif") as penghu_dem:
        results = {name: probe_one(name, rx, ry, short, example, polygons, manifest, summary, scope,
                                   main_dem, penghu_dem)
                   for name, rx, ry, short, example in PROBES}
    report = {"base_manifest_sha256": actual_hash,
              "source": "Copernicus GLO-30 public 2021 release, 30m DSM + WBM; EGM2008 vertical datum",
              "license_notice": "produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved",
              "source_files": sources, "regions": results,
              "limits": ["Read-only five-Region probe; no atlas tile or Site changed",
                         "Copernicus is a 30m surface model, not the MOI 20m terrain model; EGM2008 and TWVD2001 are different vertical references",
                         "Potential height fills have not passed local seam/slope quality control and must not be packaged",
                         "Recovered Site count excludes Region edge Sites and does not certify complete atlas coverage",
                         "WBM lake and river posts have no distinct stable water-body IDs in current runtime and remain unimplemented"]}
    target = atlas.OUT / "copernicus_probe_report.json"
    target.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(target)
    for name, result in results.items():
        print(name, "possible_sites", result["candidate_recovered_interior_sites_before_height_seam_qc"],
              "coast_posts", result["coast_fix_candidates_two_sources_and_10m_difference"],
              "height_posts", result["cop_wbm_land_at_missing_moi_posts"])


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, zlib.error) as error:
        print("COPERNICUS_PROBE_FAILED", error, file=sys.stderr)
        sys.exit(1)
