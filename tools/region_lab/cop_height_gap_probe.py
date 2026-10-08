"""Read-only r2 gap feasibility probe using pinned Copernicus GLO-30 DSM/WBM.

This does not build terrain, change the shoreline, or claim a safe vertical datum
conversion. Output is a per-Site upper-bound audit, not a release candidate.
"""

from __future__ import annotations

import json
from collections import Counter, defaultdict
from contextlib import ExitStack
from pathlib import Path

import numpy as np
import rasterio
from rasterio.features import rasterize
from rasterio.transform import from_origin
from shapely.geometry import box

import import_taiwan as atlas


OUT = atlas.ROOT / "assets/region_lab/earth_tw_tm2_121_v1_r4_probe"
NAMES = ("outside_content", "taiwan", "penghu", "green_island", "lanyu", "surrounding_sea")


def quantiles(values: list[float]) -> dict:
    if not values:
        return {"count": 0}
    arr = np.asarray(values, dtype=np.float32)
    return {"count": int(arr.size), "min": float(arr.min()),
            "p05": float(np.percentile(arr, 5)), "p50": float(np.median(arr)),
            "p95": float(np.percentile(arr, 95)), "max": float(arr.max())}


def main() -> None:
    atlas.verify_source(atlas.DEM_ARCHIVE, atlas.DEM_SHA)
    atlas.verify_source(atlas.COAST_ARCHIVE, atlas.COAST_SHA)
    atlas.extract_inputs()
    manifest = json.loads((atlas.OUT / "manifest.json").read_text(encoding="utf-8"))
    polygons = atlas.land_polygons()
    west, east, south, north = atlas.projected_bounds()
    baseline = atlas.coastal_summary(polygons, (west, east, south, north))
    summary = np.frombuffer((atlas.OUT / "summary.u8").read_bytes(), dtype="u1").reshape(baseline.shape)
    scope = np.frombuffer((atlas.OUT / "content_scope.u8").read_bytes(), dtype="u1").reshape(baseline.shape)
    missing = (summary == 0) & (baseline != 1) & (scope >= 1) & (scope <= 4)
    if int(missing.sum()) != 11711:
        raise ValueError(f"r2 gap count changed: {int(missing.sum())}")
    OUT.mkdir(parents=True, exist_ok=True)
    report_file = OUT / "cop_height_gap_sites.jsonl"
    counters = {name: Counter() for name in NAMES[1:5]}
    values = {name: defaultdict(list) for name in NAMES[1:5]}
    reasons = {name: [] for name in NAMES[1:5]}
    cop_overlap_conflict_posts = 0
    with ExitStack() as stack, report_file.open("w", encoding="utf-8") as detail:
        main_dem = stack.enter_context(rasterio.open(atlas.TEMP / "dem_20m.tif"))
        penghu_dem = stack.enter_context(rasterio.open(atlas.TEMP / "phDEM_20m_121.tif"))
        cop_doc, cop_sources = atlas.copernicus_sources(stack)
        for ry in range(south, north):
            for rx in range(west, east):
                row, col = (north - 1 - ry) * 100, (rx - west) * 100
                region_missing = missing[row:row + 100, col:col + 100]
                if not np.any(region_missing):
                    continue
                origin_e, origin_n = rx * atlas.REGION_M, ry * atlas.REGION_M
                radius = atlas.LEVEL_RADIUS
                side = atlas.SAMPLES_PER_REGION + radius * 2
                bounds = box(origin_e - radius * atlas.SAMPLE_M,
                             origin_n - radius * atlas.SAMPLE_M,
                             origin_e + atlas.REGION_M + radius * atlas.SAMPLE_M,
                             origin_n + atlas.REGION_M + radius * atlas.SAMPLE_M)
                transform = from_origin(bounds.bounds[0], bounds.bounds[3],
                                        atlas.SAMPLE_M, atlas.SAMPLE_M)
                land = rasterize([(p, 1) for p in atlas.touching(polygons, bounds)],
                                 out_shape=(side, side), transform=transform,
                                 fill=0, dtype="uint8") == 1
                moi = atlas.source_dem(main_dem, penghu_dem, origin_e, origin_n, halo=radius)
                cop, wbm, overlap_conflicts = atlas.copernicus_halo(
                    cop_sources, transform, (side, side), bounds)
                cop_overlap_conflict_posts += overlap_conflicts
                for site_row, site_col in np.argwhere(region_missing):
                    sx, sy = rx * 100 + int(site_col), (ry + 1) * 100 - 1 - int(site_row)
                    name = NAMES[int(scope[row + site_row, col + site_col])]
                    counts = counters[name]
                    metrics = values[name]
                    r0, c0 = radius + int(site_row) * 10 - 1, radius + int(site_col) * 10 - 1
                    land12 = land[r0:r0 + 12, c0:c0 + 12]
                    moi12 = moi[r0:r0 + 12, c0:c0 + 12]
                    cop12 = cop[r0:r0 + 12, c0:c0 + 12]
                    wbm12 = wbm[r0:r0 + 12, c0:c0 + 12]
                    core_land = land12[1:11, 1:11]
                    core_moi = moi12[1:11, 1:11]
                    core_land_posts = int(core_land.sum())
                    core_moi_valid_land_posts = int(np.count_nonzero(core_land & (core_moi != atlas.NODATA)))
                    land_gap = land12 & (moi12 == atlas.NODATA)
                    land_overlap = land12 & (moi12 != atlas.NODATA) & np.isfinite(cop12) & (wbm12 == 0)
                    cop_pair = np.isfinite(cop12) & (wbm12 != 255)
                    cop_land = np.isfinite(cop12) & (wbm12 == 0) & (cop12 > 2)
                    candidate = land_gap & cop_land
                    missing_posts = int(land_gap.sum())
                    candidate_posts = int(candidate.sum())
                    cop_pair_posts = int((land_gap & cop_pair).sum())
                    nonland_posts = int((land_gap & cop_pair & (wbm12 != 0)).sum())
                    low_posts = int((land_gap & cop_pair & (wbm12 == 0) & (cop12 <= 2)).sum())
                    overlap_diff = (cop12[land_overlap] - moi12[land_overlap]).astype(np.float32)
                    overlap_median = float(np.median(overlap_diff)) if overlap_diff.size else None
                    residual_p95 = float(np.percentile(np.abs(overlap_diff - overlap_median), 95)) if overlap_diff.size else None
                    record = {"site": [sx, sy], "scope": name,
                              "gshhg_class": int(baseline[row + site_row, col + site_col]),
                              "core_GSHHG_land_posts": core_land_posts,
                              "core_MOI_valid_land_posts": core_moi_valid_land_posts,
                              "land_gap_posts_in_12x12": missing_posts,
                              "gap_posts_with_Cop_DEM_WBM_pair": cop_pair_posts,
                              "gap_posts_Cop_WBM_nonland": nonland_posts,
                              "gap_posts_Cop_DSM_low": low_posts,
                              "gap_posts_Cop_land_DSM_gt_2m": candidate_posts,
                              "all_12x12_posts_have_Cop_pair": bool(np.all(cop_pair)),
                              "all_MOI_land_gaps_have_Cop_pair": bool(np.all(~land_gap | cop_pair)),
                              "all_MOI_land_gaps_have_Cop_land": bool(np.all(~land_gap | cop_land)),
                              "overlap_posts_for_local_seam": int(overlap_diff.size),
                              "Cop_minus_MOI_local_median_m": overlap_median,
                              "local_offset_residual_p95_m": residual_p95}
                    detail.write(json.dumps(record, ensure_ascii=False) + "\n")
                    counts["r2_missing_sites"] += 1
                    counts["moi_missing_land_posts_counted_per_site"] += missing_posts
                    counts["cop_pair_at_missing_land_posts_counted_per_site"] += cop_pair_posts
                    counts["cop_land_at_missing_land_posts_counted_per_site"] += candidate_posts
                    counts["cop_nonland_at_missing_land_posts_counted_per_site"] += nonland_posts
                    counts["cop_low_at_missing_land_posts_counted_per_site"] += low_posts
                    counts["sites_with_no_MOI_land_gap_in_12x12"] += int(missing_posts == 0)
                    counts["sites_with_no_20m_GSHHG_land_post_in_core"] += int(core_land_posts == 0)
                    counts["sites_with_no_MOI_valid_land_post_in_core"] += int(core_moi_valid_land_posts == 0)
                    counts["sites_no_MOI_land_gap_but_core_MOI_land_valid"] += int(missing_posts == 0 and core_moi_valid_land_posts > 0)
                    counts["sites_all_12x12_Cop_pair"] += int(record["all_12x12_posts_have_Cop_pair"])
                    counts["sites_all_missing_land_Cop_pair"] += int(record["all_MOI_land_gaps_have_Cop_pair"])
                    counts["sites_all_missing_land_Cop_WBM_land_any_finite_DSM"] += int(
                        missing_posts > 0 and record["all_MOI_land_gaps_have_Cop_pair"] and nonland_posts == 0)
                    counts["sites_all_missing_land_Cop_land"] += int(record["all_MOI_land_gaps_have_Cop_land"])
                    counts["sites_Cop_pair_but_nonland_or_low"] += int(
                        record["all_MOI_land_gaps_have_Cop_pair"] and not record["all_MOI_land_gaps_have_Cop_land"])
                    counts["sites_with_local_overlap_at_least_16_posts"] += int(overlap_diff.size >= 16)
                    counts["sites_with_Cop_land_and_local_residual_p95_le_5m"] += int(
                        missing_posts > 0 and record["all_MOI_land_gaps_have_Cop_land"]
                        and overlap_diff.size >= 16 and residual_p95 <= 5)
                    if overlap_median is not None:
                        metrics["site_overlap_median_Cop_minus_MOI_m"].append(overlap_median)
                        metrics["site_overlap_residual_p95_m"].append(residual_p95)
                        metrics["individual_overlap_Cop_minus_MOI_m"].extend(overlap_diff.tolist())
                    if len(reasons[name]) < 12 and (nonland_posts or low_posts or cop_pair_posts < missing_posts or missing_posts == 0):
                        reasons[name].append(record)
            print(f"Completed r2 gap row {ry}/{north - 1}", flush=True)
    result = {
        "status": "read_only_upper_bound_probe_no_runtime_package",
        "r2_base_revision": manifest["base_revision"],
        "r2_manifest_sha256": atlas.sha256(atlas.OUT / "manifest.json"),
        "shoreline": "unchanged GSHHG L1 polygons; no coast promotion or scope change",
        "Copernicus_source_geocells": len(cop_doc["tiles"]),
        "Copernicus_source_records": cop_doc["tiles"],
        "Copernicus_region_halo_overlap_conflict_posts_counted_per_region": cop_overlap_conflict_posts,
        "method": "For each of 11,711 r2 Missing GSHHG land/mixed Sites, inspect every 20m post in its 12x12 interpolation halo. Count MOI NoData on unchanged GSHHG land and Cop DSM/WBM pair coverage. Cop land candidate requires WBM=0, finite DSM>2m. Existing MOI heights are never replaced.",
        "limitation": "The all-gap-Cop-land count is only an optimistic coverage upper bound. It does not solve existing GSHHG sea conflicts, per-Site source quality, TWVD2001-to-EGM2008 conversion, DSM vegetation/buildings, natural gradients, or cross-Region gameplay continuity.",
        "by_scope": {name: {"counts": dict(counters[name]),
                            "Cop_MOI_difference": {key: quantiles(v) for key, v in values[name].items()},
                            "representative_unresolved": reasons[name]}
                     for name in NAMES[1:5]},
        "per_site_file": report_file.name,
    }
    groups = NAMES[1:5]
    total = lambda key: sum(counters[name][key] for name in groups)
    result["outcome"] = {
        "r2_named_island_missing_sites": total("r2_missing_sites"),
        "sites_all_MOI_land_gaps_have_Cop_DEM_WBM_pair": total("sites_all_missing_land_Cop_pair"),
        "sites_all_12x12_posts_have_Cop_DEM_WBM_pair": total("sites_all_12x12_Cop_pair"),
        "sites_with_no_MOI_land_gap_to_fill": total("sites_with_no_MOI_land_gap_in_12x12"),
        "sites_with_true_MOI_land_gap_and_all_Cop_WBM_land_any_finite_DSM": total(
            "sites_all_missing_land_Cop_WBM_land_any_finite_DSM"),
        "sites_with_true_MOI_land_gap_and_all_Cop_land_gt_2m": (
            total("sites_all_missing_land_Cop_land") - total("sites_with_no_MOI_land_gap_in_12x12")),
        "sites_passing_exploratory_local_residual_gate_only": total(
            "sites_with_Cop_land_and_local_residual_p95_le_5m"),
        "decision": "No full-coverage r4 is viable from this source pair with unchanged GSHHG shoreline. Cop WBM marks most GSHHG-land MOI gaps as sea, and cross-datum DSM height differences are not a validated vertical conversion. The local-residual gate is a diagnostic, not authorization to fill gameplay height.",
    }
    target = OUT / "cop_height_gap_probe.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {target}; {report_file}")


if __name__ == "__main__":
    main()
