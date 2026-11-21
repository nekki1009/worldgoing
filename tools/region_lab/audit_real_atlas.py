"""Read-only, exhaustive expandability audit for the packaged Taiwan atlas.

Every 200 m Site needs its 100x100 two-metre cells plus a one-cell halo.
Those coordinates touch exactly a 12x12 window of the 20 m source lattice.
For land, RegionData.sample_meters also interpolates from that same window.
This checks all classified land/mixed Sites without allocating any Site objects.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
import zlib
from pathlib import Path

import numpy as np
from numpy.lib.stride_tricks import sliding_window_view


ROOT = Path(__file__).resolve().parents[2]
ATLAS = ROOT / "assets" / "region_lab" / "earth_tw_tm2_121_v1"
NAMES = ("missing_data", "sea", "land", "inland_water", "mixed")


def verified_bytes(folder: Path, path: str, digest: str) -> bytes:
    data = (folder / path).read_bytes()
    if hashlib.sha256(data).hexdigest() != digest.lower():
        raise ValueError(f"HASH_MISMATCH: {path}")
    return data


def audit(folder: Path) -> dict:
    manifest_path = folder / "manifest.json"
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes)
    summary_info = manifest["summary"]
    width, height = summary_info["size"]
    origin_x, origin_y = summary_info["site_origin"]
    summary = np.frombuffer(verified_bytes(folder, summary_info["path"], summary_info["sha256"]), dtype=np.uint8)
    if summary.size != width * height:
        raise ValueError("INVALID_SUMMARY_LENGTH")
    summary = summary.reshape(height, width)
    if np.any(summary >= len(NAMES)):
        raise ValueError("INVALID_SUMMARY_CLASS")
    actual_counts = {name: int(np.count_nonzero(summary == index)) for index, name in enumerate(NAMES)}
    if actual_counts != manifest["summary_counts"]:
        raise ValueError("SUMMARY_COUNT_MISMATCH")
    scope_record = manifest.get("content_scope")
    scope = None
    if scope_record is not None:
        if (scope_record.get("size") != summary_info["size"] or
                scope_record.get("site_origin") != summary_info["site_origin"] or
                scope_record.get("encoding") != "u8" or
                scope_record.get("row_order") != "north_to_south"):
            raise ValueError("INVALID_CONTENT_SCOPE_GRID")
        scope_bytes = verified_bytes(folder, scope_record["path"], scope_record["sha256"])
        scope = np.frombuffer(scope_bytes, dtype=np.uint8)
        if scope.size != width * height or np.any(scope > 5):
            raise ValueError("INVALID_CONTENT_SCOPE_VALUES")
        scope = scope.reshape(height, width)
    quality_record = manifest.get("source_quality")
    site_quality = None
    if quality_record is not None:
        if (quality_record.get("size") != summary_info["size"] or
                quality_record.get("site_origin") != summary_info["site_origin"] or
                quality_record.get("encoding") != "u8" or
                quality_record.get("row_order") != "north_to_south"):
            raise ValueError("INVALID_SOURCE_QUALITY_GRID")
        quality_bytes = verified_bytes(folder, quality_record["path"], quality_record["sha256"])
        site_quality = np.frombuffer(quality_bytes, dtype=np.uint8)
        if site_quality.size != width * height or np.any(site_quality > 4):
            raise ValueError("INVALID_SOURCE_QUALITY_VALUES")
        site_quality = site_quality.reshape(height, width)
    water_bodies = {int(body["id"]): body for body in manifest.get("water_bodies", [])}
    if len(water_bodies) != len(manifest.get("water_bodies", [])) or any(
            body_id < 2 or int(body.get("kind", -1)) not in (1, 3, 4) or
            not isinstance(body.get("source_id"), str) or not body["source_id"]
            for body_id, body in water_bodies.items()):
        raise ValueError("INVALID_WATER_BODY_CATALOG")

    def summary_class(sx: int, sy: int) -> int:
        x, y = sx - origin_x, height - 1 - (sy - origin_y)
        return int(summary[y, x]) if 0 <= x < width and 0 <= y < height else 0

    tile_valid: dict[tuple[int, int], np.ndarray] = {}
    tile_errors: list[str] = []
    records_verified = 1 + int(scope is not None) + int(site_quality is not None)
    coast_decision_records = 0
    coast_decision_counts = np.zeros(7, dtype=np.int64)
    for tile in manifest["elevation_tiles"]:
        rx, ry = int(tile["origin"][0]) // 20_000, int(tile["origin"][1]) // 20_000
        if tile["size"] != [1000, 1000] or tile["spacing_m"] != 20 or tile["encoding"] != "int16_le_zlib":
            raise ValueError(f"UNSUPPORTED_TILE_FORMAT: {tile['id']}")
        if (rx, ry) in tile_valid:
            raise ValueError(f"DUPLICATE_TILE: {tile['id']}")
        derived = tile["derived"]
        if "coast_decision_path" in derived:
            decision_bytes = zlib.decompress(verified_bytes(folder, derived["coast_decision_path"],
                                                   derived["coast_decision_sha256"]))
            if len(decision_bytes) != 1_000_000:
                raise ValueError(f"INVALID_COAST_DECISION_LENGTH: {tile['id']}")
            decision = np.frombuffer(decision_bytes, dtype=np.uint8)
            if np.any(decision > 6):
                raise ValueError(f"INVALID_COAST_DECISION_CODE: {tile['id']}")
            coast_decision_counts += np.bincount(decision, minlength=7)
            coast_decision_records += 1
            records_verified += 1
        raw_height = zlib.decompress(verified_bytes(folder, tile["path"], tile["sha256"]))
        raw_level = zlib.decompress(verified_bytes(folder, derived["levels_path"], derived["levels_sha256"]))
        raw_water = zlib.decompress(verified_bytes(folder, derived["water_path"], derived["water_sha256"]))
        records_verified += 3
        if len(raw_height) != 2_000_000 or len(raw_level) != 1_000_000 or len(raw_water) != 1_000_000:
            raise ValueError(f"INVALID_TILE_LENGTH: {tile['id']}")
        elevation = np.frombuffer(raw_height, dtype="<i2").reshape(1000, 1000)
        level = np.frombuffer(raw_level, dtype=np.uint8).reshape(1000, 1000)
        water = np.frombuffer(raw_water, dtype=np.uint8).reshape(1000, 1000)
        quality = None
        if "quality_path" in derived:
            raw_quality = zlib.decompress(verified_bytes(folder, derived["quality_path"],
                                                         derived["quality_sha256"]))
            records_verified += 1
            if len(raw_quality) != 1_000_000:
                raise ValueError(f"INVALID_QUALITY_LENGTH: {tile['id']}")
            quality = np.frombuffer(raw_quality, dtype=np.uint8).reshape(1000, 1000)
        bodies = None
        if "water_body_path" in derived:
            if derived.get("water_body_encoding") != "u32_le_zlib":
                raise ValueError(f"INVALID_WATER_BODY_ENCODING: {tile['id']}")
            raw_bodies = zlib.decompress(verified_bytes(folder, derived["water_body_path"],
                                                        derived["water_body_sha256"]))
            records_verified += 1
            if len(raw_bodies) != 4_000_000:
                raise ValueError(f"INVALID_WATER_BODY_LENGTH: {tile['id']}")
            bodies = np.frombuffer(raw_bodies, dtype="<u4").reshape(1000, 1000)
        # r2 deliberately rejects unidentified freshwater. r4 may use it only
        # with a catalogued, stable body ID and real nonzero-capable height.
        inland = (water == 1) | (water == 3) | (water == 4)
        bad_tile = np.any((level > 5) & (level != 255)) or np.any((water > 4) & (water != 255))
        bad_tile |= (site_quality is not None and quality is None)
        bad_tile |= quality is not None and (np.any(quality > 4) or
                         np.any((water != 2) & (water != 255) & (quality == 0)))
        if bodies is None:
            bad_tile |= np.any(inland)
        else:
            bad_tile |= np.any(((water == 0) & (bodies != 0)) | ((water == 2) & (bodies != 1)))
            for body_id in np.unique(bodies[inland]):
                body = water_bodies.get(int(body_id))
                if body is None or np.any(water[inland & (bodies == body_id)] != int(body["kind"])):
                    bad_tile = True
                    break
            bad_tile |= np.any(inland & ((elevation == tile["nodata"]) | (level > 5)))
        if bad_tile:
            tile_errors.append(tile["id"])
            tile_valid[(rx, ry)] = np.zeros((1000, 1000), dtype=np.bool_)
        else:
            terrestrial = ((water == 0) | inland) & (elevation != tile["nodata"]) & (level <= 5)
            if quality is not None:
                terrestrial &= quality >= 1
            tile_valid[(rx, ry)] = (water == 2) | terrestrial

    def valid_at(rx: int, ry: int, row: int, column: int) -> bool:
        # row 0 is north; row 1000 is one sample south of the tile.
        global_x = rx * 1000 + column
        global_y = ry * 1000 + (999 - row)
        source_rx, source_ry = global_x // 1000, global_y // 1000
        source = tile_valid.get((source_rx, source_ry))
        if source is not None:
            local_x, local_y = global_x - source_rx * 1000, global_y - source_ry * 1000
            return bool(source[999 - local_y, local_x])
        # The runtime has exactly this one fallback: a verified whole-sea Site.
        return summary_class(global_x // 10, global_y // 10) == 1

    blocked = 0
    ready = 0
    blocked_examples: list[dict] = []
    content_blocked = 0
    content_ready = 0
    content_inland_blocked = 0
    content_inland_ready = 0
    site_quality_errors = 0
    content_blocked_examples: list[dict] = []
    ready_by_site: dict[tuple[int, int], bool] = {}
    for (rx, ry), core in tile_valid.items():
        expanded = np.empty((1002, 1002), dtype=np.bool_)
        expanded[1:-1, 1:-1] = core
        for x in range(1002):
            expanded[0, x] = valid_at(rx, ry, -1, x - 1)
            expanded[-1, x] = valid_at(rx, ry, 1000, x - 1)
        for y in range(1, 1001):
            expanded[y, 0] = valid_at(rx, ry, y - 1, -1)
            expanded[y, -1] = valid_at(rx, ry, y - 1, 1000)
        windows = sliding_window_view(expanded, (12, 12))[::10, ::10].all(axis=(2, 3))
        if windows.shape != (100, 100):
            raise ValueError("INVALID_SITE_WINDOW")
        summary_y = height - 1 - (ry * 100 + 99 - origin_y)
        summary_x = rx * 100 - origin_x
        region_summary = summary[summary_y:summary_y + 100, summary_x:summary_x + 100]
        if region_summary.shape != (100, 100):
            raise ValueError(f"TILE_OUTSIDE_ATLAS: {(rx, ry)}")
        land = (region_summary == 2) | (region_summary == 4)
        inland_site = region_summary == 3
        failed = land & ~windows
        ready += int(np.count_nonzero(land & windows))
        blocked += int(np.count_nonzero(failed))
        if scope is not None:
            region_scope = scope[summary_y:summary_y + 100, summary_x:summary_x + 100]
            included = land & (region_scope >= 1) & (region_scope <= 4)
            failed_in_scope = included & ~windows
            included_inland = inland_site & (region_scope >= 1) & (region_scope <= 4)
            content_ready += int(np.count_nonzero(included & windows))
            content_blocked += int(np.count_nonzero(failed_in_scope))
            content_inland_ready += int(np.count_nonzero(included_inland & windows))
            content_inland_blocked += int(np.count_nonzero(included_inland & ~windows))
            if site_quality is not None:
                region_quality = site_quality[summary_y:summary_y + 100, summary_x:summary_x + 100]
                site_quality_errors += int(np.count_nonzero(
                    (((region_summary == 2) | inland_site | (region_summary == 4)) & (region_quality == 0)) |
                    (((region_summary == 0) | (region_summary == 1)) & (region_quality != 0))))
            if len(content_blocked_examples) < 30:
                for row, column in np.argwhere(failed_in_scope)[:30 - len(content_blocked_examples)]:
                    content_blocked_examples.append({"site": [rx * 100 + int(column), ry * 100 + 99 - int(row)],
                                                     "class": NAMES[int(region_summary[row, column])],
                                                     "scope": int(region_scope[row, column])})
        if len(blocked_examples) < 30:
            for row, column in np.argwhere(failed)[:30 - len(blocked_examples)]:
                blocked_examples.append({"site": [rx * 100 + int(column), ry * 100 + 99 - int(row)],
                                         "class": NAMES[int(region_summary[row, column])],
                                         "scope": int(scope[summary_y + row, summary_x + column]) if scope is not None else None})
        for preview in manifest.get("preview_sites", []):
            sx, sy = preview["site"]
            if sx // 100 == rx and sy // 100 == ry:
                ready_by_site[(sx, sy)] = bool(windows[ry * 100 + 99 - sy, sx - rx * 100])

    classified_land = actual_counts["land"] + actual_counts["mixed"]
    no_tile_land = classified_land - ready - blocked
    blocked += no_tile_land
    scope_report = {"status": "unavailable", "taiwan_land_or_mixed_sites": None,
                    "taiwan_expandable_land_or_mixed_sites": None,
                    "taiwan_blocked_land_or_mixed_sites": None,
                    "outside_scope_geographic_land_or_mixed_sites": None}
    if scope is not None:
        content_mask = (scope >= 1) & (scope <= 4)
        content_total = int(np.count_nonzero(((summary == 2) | (summary == 4)) & content_mask))
        content_blocked += content_total - content_ready - content_blocked
        missing_class = int(np.count_nonzero((summary == 0) & content_mask))
        inland_total = int(np.count_nonzero((summary == 3) & content_mask))
        content_inland_blocked += inland_total - content_inland_ready - content_inland_blocked
        sea_class = int(np.count_nonzero((summary == 1) & content_mask))
        outside_land = int(np.count_nonzero(((summary == 2) | (summary == 4)) & (scope == 0)))
        scope_report = {
            "status": "verified", "counts": {str(i): int(np.count_nonzero(scope == i)) for i in range(6)},
            "taiwan_content_sites_total": int(np.count_nonzero(content_mask)),
            "taiwan_land_or_mixed_sites": content_total,
            "taiwan_expandable_land_or_mixed_sites": content_ready,
            "taiwan_blocked_land_or_mixed_sites": content_blocked,
            "taiwan_missing_class_sites": missing_class,
            "taiwan_inland_water_sites": inland_total,
            "taiwan_expandable_inland_water_sites": content_inland_ready,
            "taiwan_unresolved_inland_water_sites": content_inland_blocked,
            "taiwan_sea_class_sites": sea_class,
            "taiwan_unexpected_sea_class_sites": sea_class if site_quality is None else 0,
            "taiwan_blocked_examples": content_blocked_examples,
            "outside_scope_geographic_land_or_mixed_sites": outside_land,
            "unclassified_or_outside_sites": int(np.count_nonzero(scope == 0)),
            "surrounding_sea_sites": int(np.count_nonzero(scope == 5)),
        }
    preview_status = [{"label": p["label"], "site": p["site"],
                       "class": NAMES[summary_class(*p["site"])],
                       "scope": int(scope[height - 1 - (p["site"][1] - origin_y), p["site"][0] - origin_x]) if scope is not None else None,
                       "expandable": ready_by_site.get(tuple(p["site"]), False)}
                      for p in manifest.get("preview_sites", [])]
    return {
        "atlas_id": manifest["atlas_id"], "base_revision": manifest["base_revision"],
        "manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
        "summary_size_sites": [width, height], "summary_counts": actual_counts,
        "tile_count": len(tile_valid), "records_verified": records_verified,
        "coast_decision_records_verified": coast_decision_records,
        "coast_decision_post_counts": {str(i): int(coast_decision_counts[i]) for i in range(7)},
        "tile_errors": tile_errors, "classified_land_or_mixed_sites": classified_land,
        "site_quality_errors": site_quality_errors,
        "expandable_land_or_mixed_sites": ready,
        "blocked_land_or_mixed_sites": blocked,
        "land_sites_without_tile": no_tile_land,
        "blocked_examples": blocked_examples,
        "content_scope": scope_report,
        "preview_sites": preview_status,
        "scope": "All summary land/mixed Sites, source-level 12x12 sample and interpolation halo; no TerrainData or GPU rendering",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--atlas", type=Path, default=ATLAS)
    parser.add_argument("--report", type=Path, default=ROOT / ".godot-temp" / "region_lab_real_map_audit.json")
    args = parser.parse_args()
    report = audit(args.atlas)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("REGION_REAL_ATLAS_AUDIT", json.dumps({key: report[key] for key in
          ("manifest_sha256", "tile_count", "records_verified", "coast_decision_records_verified",
           "coast_decision_post_counts", "summary_counts", "content_scope",
           "classified_land_or_mixed_sites", "expandable_land_or_mixed_sites",
           "blocked_land_or_mixed_sites", "land_sites_without_tile", "preview_sites")}, ensure_ascii=False))
    print("REPORT", args.report)
    scope = report["content_scope"]
    blocked = (report["blocked_land_or_mixed_sites"] if scope["status"] == "unavailable"
               else scope["taiwan_blocked_land_or_mixed_sites"] + scope["taiwan_missing_class_sites"]
                    + scope["taiwan_unresolved_inland_water_sites"] + scope["taiwan_unexpected_sea_class_sites"])
    return 0 if not report["tile_errors"] and report["site_quality_errors"] == 0 and blocked == 0 else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, zlib.error) as error:
        print("REGION_REAL_ATLAS_AUDIT_FAILED", str(error), file=sys.stderr)
        sys.exit(1)
