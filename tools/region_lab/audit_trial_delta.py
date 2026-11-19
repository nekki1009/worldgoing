"""Read-only, whole-atlas r2 versus isolated coast-evidence trial audit.

Run after import_taiwan.py verify --trial. This never builds or changes an atlas.
"""

from __future__ import annotations

import json
import zlib
from collections import Counter
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "assets/region_lab/earth_tw_tm2_121_v1"
TRIAL = ROOT / "assets/region_lab/earth_tw_tm2_121_v1_r3_trial"
NODATA = -32767
SCOPE_NAMES = ("outside_content", "taiwan", "penghu", "green_island", "lanyu", "surrounding_sea")


def load_manifest(folder: Path) -> dict:
    return json.loads((folder / "manifest.json").read_text(encoding="utf-8"))


def raster(folder: Path, record: dict, dtype: str, shape: tuple[int, int], compressed: bool) -> np.ndarray:
    data = (folder / record["path"]).read_bytes()
    if compressed:
        data = zlib.decompress(data)
    result = np.frombuffer(data, dtype=dtype)
    if result.size != shape[0] * shape[1]:
        raise ValueError(f"Unexpected raster dimensions: {record['path']}")
    return result.reshape(shape)


def tile_arrays(folder: Path, tile: dict) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    shape = tile["size"][1], tile["size"][0]
    height = raster(folder, tile, "<i2", shape, True)
    derived = tile["derived"]
    level = raster(folder, {"path": derived["levels_path"]}, "u1", shape, True)
    water = raster(folder, {"path": derived["water_path"]}, "u1", shape, True)
    return height, level, water


def main() -> None:
    old = load_manifest(BASE)
    new = load_manifest(TRIAL)
    for key in ("atlas_id", "grid", "summary"):
        if key == "summary":
            fields = ("site_origin", "size", "row_order")
            if any(old[key][f] != new[key][f] for f in fields):
                raise ValueError("Site lattice changed between revisions")
        elif old[key] != new[key]:
            raise ValueError(f"Atlas contract changed: {key}")
    if old["base_revision"] == new["base_revision"]:
        raise ValueError("Trial has no distinct revision")
    old_tiles = {t["id"]: t for t in old["elevation_tiles"]}
    new_tiles = {t["id"]: t for t in new["elevation_tiles"]}
    if old_tiles.keys() != new_tiles.keys():
        raise ValueError("Source tile coverage changed")
    shape = old["summary"]["size"][1], old["summary"]["size"][0]
    old_summary = raster(BASE, old["summary"], "u1", shape, False)
    new_summary = raster(TRIAL, new["summary"], "u1", shape, False)
    old_scope = raster(BASE, old["content_scope"], "u1", shape, False)
    new_scope = raster(TRIAL, new["content_scope"], "u1", shape, False)
    west, south, east, north = new["aligned_region_bounds_half_open"]
    if shape != ((north - south) * 100, (east - west) * 100):
        raise ValueError("Site and Region bounds disagree")

    errors: Counter[str] = Counter()
    counters: Counter[str] = Counter()
    decisions = np.zeros(7, dtype=np.int64)
    levels_changed = Counter()
    accepted_by_old_summary = Counter()
    accepted_by_scope = Counter()
    accepted_site_by_scope = Counter()
    seam_height_differences: list[np.ndarray] = []
    seam_level_differences: list[np.ndarray] = []
    examples: dict[str, list] = {"large_seam_height": [], "large_seam_level": []}

    def seam(a_h, a_l, a_old, b_h, b_l, b_old, rx, ry, row_offset=0, col_offset=0):
        boundary = (a_old != 0) & (b_old == 0) | (a_old == 0) & (b_old != 0)
        valid = boundary & (a_h != NODATA) & (b_h != NODATA)
        if not np.any(valid):
            return
        dh = np.abs(a_h.astype(np.int32) - b_h.astype(np.int32))[valid]
        dl = np.abs(a_l.astype(np.int16) - b_l.astype(np.int16))[valid]
        seam_height_differences.append(dh)
        seam_level_differences.append(dl)
        counters["new_old_post_seam_pairs"] += int(dh.size)
        counters["new_old_post_seam_over_20m"] += int(np.count_nonzero(dh > 20))
        counters["new_old_post_seam_over_50m"] += int(np.count_nonzero(dh > 50))
        counters["new_old_post_seam_levels_over_1"] += int(np.count_nonzero(dl > 1))
        # These are source-grid sample positions, not Site ids.
        if np.max(dh) > 50 and len(examples["large_seam_height"]) < 12:
            examples["large_seam_height"].append({"region": [rx, ry], "max_height_delta_m": int(dh.max())})
        if np.max(dl) > 1 and len(examples["large_seam_level"]) < 12:
            examples["large_seam_level"].append({"region": [rx, ry], "max_level_delta": int(dl.max())})

    for tile_id in sorted(new_tiles):
        old_tile, new_tile = old_tiles[tile_id], new_tiles[tile_id]
        for field in ("origin", "size", "spacing_m", "nodata"):
            if old_tile[field] != new_tile[field]:
                raise ValueError(f"Tile contract changed: {tile_id} {field}")
        old_h, old_l, old_w = tile_arrays(BASE, old_tile)
        new_h, new_l, new_w = tile_arrays(TRIAL, new_tile)
        decision = raster(TRIAL, {"path": new_tile["derived"]["coast_decision_path"]},
                          "u1", old_h.shape, True)
        if np.any(decision > 6):
            errors["unknown_decision_code"] += int(np.count_nonzero(decision > 6))
        decisions += np.bincount(decision.ravel(), minlength=7)[:7]
        old_land = (old_w == 0) & (old_h != NODATA)
        new_land = (new_w == 0) & (new_h != NODATA)
        gained = new_land & ~old_land
        lost = old_land & ~new_land
        errors["old_valid_land_post_lost"] += int(np.count_nonzero(lost))
        errors["old_land_height_changed"] += int(np.count_nonzero(old_land & (old_h != new_h)))
        errors["gained_without_acceptance_code"] += int(np.count_nonzero(gained & (decision != 1)))
        errors["accepted_without_new_land"] += int(np.count_nonzero((decision == 1) & ~gained))
        errors["rejected_but_new_land"] += int(np.count_nonzero((decision >= 2) & new_land & ~old_land))
        errors["land_height_without_level"] += int(np.count_nonzero(new_land & (new_l > 5)))
        counters["old_valid_land_posts"] += int(np.count_nonzero(old_land))
        counters["new_valid_land_posts"] += int(np.count_nonzero(new_land))
        counters["gained_valid_land_posts"] += int(np.count_nonzero(gained))
        changed = old_land & new_land & (old_l != new_l)
        levels_changed["posts"] += int(np.count_nonzero(changed))
        if np.any(changed):
            levels_changed["max_absolute_level_delta"] = max(
                levels_changed["max_absolute_level_delta"],
                int(np.max(np.abs(new_l[changed].astype(np.int16) - old_l[changed].astype(np.int16)))))
        rx, ry = [v // 20000 for v in new_tile["origin"]]
        row, col = (north - 1 - ry) * 100, (rx - west) * 100
        old_site = old_summary[row:row + 100, col:col + 100]
        new_site = new_summary[row:row + 100, col:col + 100]
        scope_site = new_scope[row:row + 100, col:col + 100]
        accepted_post_by_site = (decision == 1).reshape(100, 10, 100, 10).sum(axis=(1, 3))
        accepted_site_mask = accepted_post_by_site > 0
        counters["sites_with_accepted_posts"] += int(np.count_nonzero(accepted_site_mask))
        for code in range(5):
            accepted_by_old_summary[str(code)] += int(accepted_post_by_site[old_site == code].sum())
        for code, name in enumerate(SCOPE_NAMES):
            mask = scope_site == code
            accepted_by_scope[name] += int(accepted_post_by_site[mask].sum())
            accepted_site_by_scope[name] += int(np.count_nonzero(accepted_site_mask & mask))
        # Compare neighbouring new and old land posts within each fixed tile.
        seam(new_h[:, :-1], new_l[:, :-1], old_w[:, :-1],
             new_h[:, 1:], new_l[:, 1:], old_w[:, 1:], rx, ry)
        seam(new_h[:-1, :], new_l[:-1, :], old_w[:-1, :],
             new_h[1:, :], new_l[1:, :], old_w[1:, :], rx, ry)

    expected = {str(i): int(v) for i, v in enumerate(decisions)}
    if expected != new["build_diagnostics"]["coast_decision_post_counts"]:
        errors["decision_histogram_manifest_mismatch"] += 1
    transitions = {}
    scope_totals = {}
    for code, name in enumerate(SCOPE_NAMES):
        mask = new_scope == code
        old_available = (old_summary == 2) | (old_summary == 4)
        new_available = (new_summary == 2) | (new_summary == 4)
        transitions[name] = {f"{a}_to_{b}": int(np.count_nonzero(mask & (old_summary == a) & (new_summary == b)))
                             for a in (0, 1, 2, 4) for b in (0, 1, 2, 4)
                             if np.any(mask & (old_summary == a) & (new_summary == b))}
        scope_totals[name] = {
            "r2_scope_sites": int(np.count_nonzero(old_scope == code)),
            "r3_scope_sites": int(np.count_nonzero(mask)),
            "r3_missing": int(np.count_nonzero(mask & (new_summary == 0))),
            "new_available": int(np.count_nonzero(mask & ~old_available & new_available)),
            "lost_available": int(np.count_nonzero(mask & old_available & ~new_available)),
        }
    all_dh = np.concatenate(seam_height_differences) if seam_height_differences else np.empty(0)
    all_dl = np.concatenate(seam_level_differences) if seam_level_differences else np.empty(0)
    result = {
        "r2_manifest_sha256": __import__("hashlib").sha256((BASE / "manifest.json").read_bytes()).hexdigest(),
        "r3_manifest_sha256": __import__("hashlib").sha256((TRIAL / "manifest.json").read_bytes()).hexdigest(),
        "verification": "PASS" if not any(errors.values()) and not any(v["lost_available"] for v in scope_totals.values()) else "FAIL",
        "errors": dict(errors), "post_counts": dict(counters),
        "decision_counts": expected,
        "accepted_posts_by_r2_summary_class": dict(accepted_by_old_summary),
        "accepted_posts_by_r3_scope": dict(accepted_by_scope),
        "sites_with_accepted_posts_by_r3_scope": dict(accepted_site_by_scope),
        "retained_land_level_changes": dict(levels_changed),
        "new_old_land_seam": {
            "height_delta_m_percentiles_50_95_99_max": [float(np.percentile(all_dh, q)) for q in (50, 95, 99, 100)] if all_dh.size else [],
            "level_delta_percentiles_50_95_99_max": [float(np.percentile(all_dl, q)) for q in (50, 95, 99, 100)] if all_dl.size else [],
            "examples": examples,
            "note": "Natural MOI source gradients at 20m adjacent posts; steep cliffs are retained, not smoothed.",
        },
        "scope_totals": scope_totals,
        "summary_transitions_by_r3_scope": transitions,
    }
    target = TRIAL / "trial_delta_audit.json"
    target.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"{result['verification']}: {target}")
    print("r3 scope1–4 missing", sum(scope_totals[SCOPE_NAMES[i]]["r3_missing"] for i in range(1, 5)))
    print("gained land posts", counters["gained_valid_land_posts"], "accepted", decisions[1])
    if result["verification"] != "PASS":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
