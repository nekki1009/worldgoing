"""Independent r2 gap inventory and r4 recovery audit.

The immutable r2 Site lattice defines the 11,711 Taiwan-content gaps. A new
revision must account for every coordinate; changing the editorial scope is
not a substitute for resolving one. This script reads packaged data and the
hash-pinned OSM source properties; it does not call the builder or Godot.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter
from datetime import datetime, timezone
from functools import lru_cache
from pathlib import Path
import time
import zlib
import zipfile

import numpy as np
from pyproj import Transformer
from shapely import intersects_xy
from shapely.geometry import shape
from shapely.ops import transform, unary_union
import rasterio
from rasterio.transform import from_origin
from rasterio.warp import reproject, Resampling

import import_taiwan as legacy_sources


ROOT = Path(__file__).resolve().parents[2]
R2 = ROOT / "assets/region_lab/earth_tw_tm2_121_v1"
OUTPUT = ROOT / "output/region_lab_real_acceptance"
EXPECTED_R2_MANIFEST_SHA256 = "2ab25eeaa685782b42928d206ec808e4f1bb4da5e771cc67f0f86e8fefb07f61"
EXPECTED_GAPS_BY_SCOPE = {1: 9993, 2: 950, 3: 228, 4: 540}
SCOPE_NAMES = {1: "taiwan", 2: "penghu", 3: "green_island", 4: "lanyu"}
R4 = ROOT / "assets/region_lab/earth_tw_tm2_121_v1_r4"
NODATA = -32767
ALL_READY = 511


def verified_bytes(folder: Path, record: dict) -> bytes:
    relative = Path(record["path"])
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError(f"INVALID_RECORD_PATH: {relative}")
    data = (folder / record["path"]).read_bytes()
    actual = hashlib.sha256(data).hexdigest()
    if actual != record["sha256"].lower():
        raise ValueError(f"HASH_MISMATCH: {record['path']}: {actual}")
    return data


def site_raster(folder: Path, record: dict, expected_grid: dict | None = None) -> tuple[bytes, tuple[int, int], tuple[int, int]]:
    if record.get("encoding") != "u8" or record.get("row_order") != "north_to_south":
        raise ValueError(f"INVALID_SITE_RASTER_FORMAT: {record.get('path')}")
    size = tuple(record["size"])
    origin = tuple(record["site_origin"])
    if len(size) != 2 or len(origin) != 2 or size[0] <= 0 or size[1] <= 0:
        raise ValueError(f"INVALID_SITE_GRID: {record.get('path')}")
    if expected_grid is not None and (list(size) != expected_grid["size"] or
                                      list(origin) != expected_grid["site_origin"]):
        raise ValueError(f"SITE_GRID_MISMATCH: {record.get('path')}")
    data = verified_bytes(folder, record)
    if len(data) != size[0] * size[1]:
        raise ValueError(f"INVALID_SITE_RASTER_LENGTH: {record.get('path')}")
    return data, size, origin


def r2_gap_inventory(folder: Path) -> tuple[dict, list[dict], dict]:
    manifest_bytes = (folder / "manifest.json").read_bytes()
    manifest_hash = hashlib.sha256(manifest_bytes).hexdigest()
    if manifest_hash != EXPECTED_R2_MANIFEST_SHA256:
        raise ValueError(f"WRONG_R2_BASELINE: {manifest_hash}")
    manifest = json.loads(manifest_bytes)
    if manifest["grid"]["cell_m"] != 2 or manifest["grid"]["site_cells"] != 100:
        raise ValueError("R2_SITE_GRID_CONTRACT_CHANGED")
    summary, size, origin = site_raster(folder, manifest["summary"])
    scope, _, _ = site_raster(folder, manifest["content_scope"], manifest["summary"])
    width, height = size
    west, south = origin
    gaps: list[dict] = []
    counts: Counter[int] = Counter()
    for index, (site_class, content_scope) in enumerate(zip(summary, scope, strict=True)):
        if content_scope not in SCOPE_NAMES or site_class != 0:
            continue
        row, column = divmod(index, width)
        site = [west + column, south + height - 1 - row]
        gaps.append({"site": site, "scope": content_scope, "scope_name": SCOPE_NAMES[content_scope],
                     "r2_status": "missing_data"})
        counts[content_scope] += 1
    if dict(counts) != EXPECTED_GAPS_BY_SCOPE:
        raise ValueError(f"R2_GAP_COUNT_CHANGED: {dict(counts)}")
    report = {"r2_manifest_sha256": manifest_hash,
              "summary_sha256": manifest["summary"]["sha256"],
              "content_scope_sha256": manifest["content_scope"]["sha256"],
              "site_origin": list(origin), "site_size": list(size),
              "gap_count": len(gaps),
              "gaps_by_scope": {SCOPE_NAMES[scope_id]: counts[scope_id]
                                for scope_id in EXPECTED_GAPS_BY_SCOPE},
              "first_gap_sites": gaps[:12],
              "scope": "Every r2 summary=missing_data Site in content_scope 1..4; fixed coordinates for r4 review"}
    return report, gaps, manifest


def site_states(valid: np.ndarray, cells: int) -> np.ndarray:
    """Core, N/S/W/E and four corners, in north-to-south Site order."""
    rows, columns = valid.shape[0] // cells, valid.shape[1] // cells
    blocks = valid.reshape(rows, cells, columns, cells)
    result = blocks.all(axis=(1, 3)).astype(np.uint16)
    for bit, edge in ((2, blocks[:, 0, :, :].all(axis=2)),
                      (4, blocks[:, -1, :, :].all(axis=2)),
                      (8, blocks[:, :, :, 0].all(axis=1)),
                      (16, blocks[:, :, :, -1].all(axis=1)),
                      (32, blocks[:, 0, :, 0]), (64, blocks[:, 0, :, -1]),
                      (128, blocks[:, -1, :, 0]), (256, blocks[:, -1, :, -1])):
        result |= edge.astype(np.uint16) * bit
    return result


def with_neighbours(states: np.ndarray) -> np.ndarray:
    """Exact one 2m-cell halo; outside atlas is unavailable."""
    padded = np.pad(states, 1)
    h, w = states.shape
    result = (states & 1) != 0
    for dy, dx, bit in ((-1, 0, 4), (1, 0, 2), (0, -1, 16), (0, 1, 8),
                        (-1, -1, 256), (-1, 1, 128), (1, -1, 64), (1, 1, 32)):
        result &= (padded[1 + dy:1 + dy + h, 1 + dx:1 + dx + w] & bit) != 0
    return result


def fine_validity(mask: np.ndarray, flags: np.ndarray) -> np.ndarray:
    """Mirror sample_meters availability, not its height/level algorithm.

    flags is the 12x12 source window: bit1 sample succeeds, bit2 has height,
    bit4 dry land. A fine sea bypasses the source. Fine inland needs the
    containing post's height. Fine dry land needs four successful samples
    and at least one height; water support is allowed and marked q4 at runtime.
    """
    cell = np.arange(100)
    centre = cell // 10 + 1
    low = (cell - 5) // 10 + 1
    contained = flags[centre[:, None], centre[None, :]]
    four = [flags[(low + dy)[:, None], (low + dx)[None, :]]
            for dy, dx in ((0, 0), (1, 0), (0, 1), (1, 1))]
    good = np.logical_and.reduce([(part & 1) != 0 for part in four])
    height = np.logical_or.reduce([(part & 2) != 0 for part in four])
    dry = ((contained & 1) != 0) & good & height
    inland = (contained & 3) == 3
    return (mask == 1) | ((mask == 0) & dry) | ((mask > 1) & inland)


def fine_site(region: tuple[int, int], key: int) -> tuple[int, int]:
    row, column = divmod(key, 100)
    return region[0] * 100 + column, region[1] * 100 + 99 - row


def fine_public_quality(mask: np.ndarray, flags: np.ndarray) -> np.ndarray:
    """Quality from actual runtime contributors; encoded source quality is bits 3..5."""
    cell = np.arange(100)
    centre, low = cell // 10 + 1, (cell - 5) // 10 + 1
    original = (flags[centre[:, None], centre[None, :]] >> 3) & 7
    dry = original.copy()
    for dy, dx in ((0, 0), (1, 0), (0, 1), (1, 1)):
        point = flags[(low + dy)[:, None], (low + dx)[None, :]]
        contributes = (point & 2) != 0
        dry = np.maximum(dry, np.where(contributes, (point >> 3) & 7, 0))
        dry[contributes & ((point & 4) == 0)] = 4
    return np.where(mask == 1, 0, np.where(mask == 0, dry, original)).astype("u1")


def independent_moi_core(rx: int, ry: int) -> np.ndarray:
    """Native source warp under the fixed, published core policy; no builder call."""
    target = np.full((1000, 1000), NODATA, dtype="<i2")
    matrix = from_origin(rx * 20000, (ry + 1) * 20000, 20, 20)
    for name in ("dem_20m.tif", "phDEM_20m_121.tif"):
        with rasterio.open(legacy_sources.TEMP / name) as dataset:
            layer = np.full_like(target, NODATA)
            reproject(source=rasterio.band(dataset, 1), destination=layer,
                      src_transform=dataset.transform, src_crs=dataset.crs,
                      src_nodata=NODATA, dst_transform=matrix, dst_crs="EPSG:3826",
                      dst_nodata=NODATA, resampling=Resampling.nearest,
                      init_dest_nodata=True, num_threads=2)
            valid = layer != NODATA
            if np.any(valid & (target != NODATA) & (target != layer)):
                raise ValueError("ORIGINAL_MOI_SOURCES_CONFLICT")
            target[valid] = layer[valid]
    return target


def box_sum_21(array: np.ndarray) -> np.ndarray:
    integral = np.pad(array.astype(np.int64).cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    return integral[21:, 21:] - integral[:-21, 21:] - integral[21:, :-21] + integral[:-21, :-21]


def independently_derived_levels(heights: np.ndarray) -> np.ndarray:
    valid = heights != NODATA
    background = box_sum_21(np.where(valid, heights, 0)) / np.maximum(box_sum_21(valid), 1)
    core = heights[10:-10, 10:-10]
    levels = np.clip(np.rint(2 + (core.astype(np.float64) - background) / 16), 0, 5).astype("u1")
    levels[core == NODATA] = 255
    return levels


def audit_r4(folder: Path, r2_folder: Path, gaps: list[dict], r2_manifest: dict,
             out: Path, timeout_seconds: int, osm_source: Path, level_halo_index: Path | None = None) -> dict:
    started = time.monotonic()
    deadline = started + timeout_seconds
    manifest_raw = (folder / "manifest.json").read_bytes()
    manifest = json.loads(manifest_raw)
    (out / "audited_manifest.json").write_bytes(manifest_raw)
    if (manifest["grid"] != r2_manifest["grid"] or manifest["atlas_id"] != r2_manifest["atlas_id"] or
            manifest.get("crs") != "EPSG:3826" or manifest.get("format") != 1 or manifest.get("grid_contract_version") != 1):
        raise ValueError("R4_COORDINATE_CONTRACT_CHANGED")
    source_policy = manifest.get("source_post_rule", {})
    if (source_policy.get("method") != "fixed_20km_global_core_then_join_halo" or
            source_policy.get("r2_valid_dry_posts") != "pinned_from_r2_manifest" or
            source_policy.get("r2_manifest_sha256") != EXPECTED_R2_MANIFEST_SHA256):
        raise ValueError("UNVERIFIED_FIXED_SOURCE_POST_POLICY")
    terrain_rule = manifest["terrain_rule"]
    if (terrain_rule.get("method") != "available_land_and_marked_coast_support_box_mean_residual" or
            terrain_rule.get("coast_support_in_background") is not True or terrain_rule.get("radius_m") != 200 or
            terrain_rule.get("base_level") != 2 or terrain_rule.get("meters_per_level") != 16 or
            terrain_rule.get("rounding") != "numpy_rint_even" or terrain_rule.get("clamp") != [0, 5]):
        raise ValueError("UNVERIFIED_GAMEPLAY_LEVEL_FORMULA")
    legacy_sources.verify_source(legacy_sources.DEM_ARCHIVE, legacy_sources.DEM_SHA)
    moi_source_hashes = {}
    with zipfile.ZipFile(legacy_sources.DEM_ARCHIVE) as archive:
        for name in ("dem_20m.tif", "phDEM_20m_121.tif"):
            member = next(entry for entry in archive.namelist() if entry.endswith("/" + name))
            with archive.open(member) as source, (legacy_sources.TEMP / name).open("rb") as cached:
                expected_hash = hashlib.file_digest(source, "sha256").hexdigest()
                if hashlib.file_digest(cached, "sha256").hexdigest() != expected_hash:
                    raise ValueError(f"CACHED_MOI_DIFFERS_FROM_PINNED_ARCHIVE: {name}")
            moi_source_hashes[name] = expected_hash
    sea_rule = manifest.get("sea_surface_rule", {})
    if (sea_rule.get("summary_class") != 1 or sea_rule.get("gameplay_level") != 0 or
            sea_rule.get("whole_site_verified") is not True or not sea_rule.get("source")):
        raise ValueError("INVALID_WHOLE_SEA_RULE")
    summary_bytes, size, origin = site_raster(folder, manifest["summary"], r2_manifest["summary"])
    width, height = size
    summary = np.frombuffer(summary_bytes, dtype="u1").reshape(height, width)
    scope = np.frombuffer(site_raster(folder, manifest["content_scope"], manifest["summary"])[0],
                          dtype="u1").reshape(height, width)
    quality = np.frombuffer(site_raster(folder, manifest["source_quality"], manifest["summary"])[0],
                            dtype="u1").reshape(height, width)
    if np.any(summary > 4) or np.any(scope > 5) or np.any(quality > 4):
        raise ValueError("INVALID_SITE_CLASSIFICATION")
    actual_counts = {name: int(np.count_nonzero(summary == code)) for code, name in
                     enumerate(("missing_data", "sea", "land", "inland_water", "mixed"))}
    if actual_counts != manifest["summary_counts"]:
        raise ValueError("SUMMARY_COUNT_MISMATCH")
    old_scope = np.frombuffer(site_raster(r2_folder, r2_manifest["content_scope"])[0],
                              dtype="u1").reshape(height, width)
    old_summary = np.frombuffer(site_raster(r2_folder, r2_manifest["summary"])[0],
                                dtype="u1").reshape(height, width)
    old_active = (old_scope >= 1) & (old_scope <= 4)
    old_playable = old_active & np.isin(old_summary, [2, 4])
    scope_changed = old_active & (scope != old_scope)
    active = (scope >= 1) & (scope <= 4)
    # Reuse the established r2 source reader, not r4's merging/finalizer logic.
    # A missing elevation summary is not a coastline authority.
    legacy_sources.verify_source(legacy_sources.COAST_ARCHIVE, legacy_sources.COAST_SHA)
    original_geography = legacy_sources.coastal_summary(legacy_sources.land_polygons(), legacy_sources.projected_bounds())
    external = scope == 0
    outside_scope_leak = (old_scope == 0) & (scope == 5)
    external_geography_mismatch = external & (summary != original_geography)
    records = 3
    counts: Counter = Counter()
    for record in manifest.get("source_metadata", []):
        counts["source_metadata_bytes_verified"] += len(verified_bytes(folder, record))
        records += 1
    issues: list[dict] = []
    candidates: list[dict] = []
    body_by_id = {}
    source_ids = set()
    for body in manifest.get("water_bodies", []):
        ident, source_id, kind = body["id"], body["source_id"], body["kind"]
        if (not isinstance(ident, int) or ident < 2 or ident in body_by_id or
                source_id in source_ids or not source_id or kind not in (1, 3, 4)):
            raise ValueError("INVALID_OR_DUPLICATE_BODY_ID")
        body_by_id[ident] = body
        source_ids.add(source_id)
    body_kind = np.full(max(body_by_id, default=1) + 1, 255, dtype="u1")
    body_kind[0:2] = [0, 2]
    for ident, body in body_by_id.items():
        body_kind[ident] = body["kind"]
    source_records = {record["id"]: record for record in manifest["sources"]}
    source_water = verified_bytes(osm_source, {"path": "inland_water.geojson",
        "sha256": source_records["osm_water_20260927"]["sha256"]})
    verified_bytes(osm_source, {"path": "land.geojson",
        "sha256": source_records["osm_coast_20260927"]["sha256"]})
    water_features = json.loads(source_water)["features"]
    del source_water
    original_kinds = {}
    source_geometry = {}
    project = Transformer.from_crs(4326, 3826, always_xy=True).transform
    for feature in water_features:
        prop = feature["properties"]
        tags = prop["osm_tags"]
        expected = (2 if tags.get("water") in ("sea", "ocean") else
                    3 if tags.get("salt") == "yes" or tags.get("salinity") in ("salt", "saline", "brackish") else
                    1 if tags.get("salt") == "no" or tags.get("salinity") in ("fresh", "freshwater") else 4)
        if prop["kind_hint"] != expected:
            raise ValueError(f"SOURCE_SALINITY_TAG_MISMATCH: {prop['source_id']}")
        previous = original_kinds.setdefault(prop["source_id"], expected)
        if previous != expected:
            raise ValueError(f"CONFLICTING_SOURCE_WATER_KIND: {prop['source_id']}")
        if prop["source_id"] in source_ids:
            source_geometry.setdefault(prop["source_id"], []).append(transform(project, shape(feature["geometry"])))
    for body in body_by_id.values():
        if original_kinds.get(body["source_id"]) != body["kind"]:
            raise ValueError(f"BODY_KIND_DIFFERS_FROM_SOURCE: {body['source_id']}")
    body_geometry = {ident: unary_union(source_geometry[body["source_id"]]) for ident, body in body_by_id.items()}
    del water_features, source_geometry
    flags_by_region = {}
    tile_records = {}
    old_tiles = {tuple(int(x) // 20000 for x in t["origin"]): t for t in r2_manifest["elevation_tiles"]}
    fine_records = []
    body_regions: dict[int, set] = {}
    body_fine_sites: Counter = Counter()
    states = np.where(summary == 1, ALL_READY, 0).astype(np.uint16)
    classes_by_site = np.zeros_like(summary)  # bit1 dry, bit2 sea, bit4 inland
    classes_by_site[summary == 1] = 2
    fine_present = np.zeros_like(summary, dtype=bool)
    fine_bad = np.zeros_like(summary, dtype=bool)
    public_quality = np.zeros_like(summary)
    method_distance: Counter = Counter()
    declared_methods = {int(x) for x in manifest["estimate_method_codes"]}

    def check_time():
        if time.monotonic() > deadline:
            raise TimeoutError(f"AUDIT_TIMEOUT_{timeout_seconds}s")

    def region_slice(rx, ry):
        x, y = rx * 100 - origin[0], height - (ry * 100 - origin[1]) - 100
        if x < 0 or y < 0 or x + 100 > width or y + 100 > height:
            raise ValueError(f"REGION_OUTSIDE_SUMMARY: {(rx, ry)}")
        return np.s_[y:y + 100, x:x + 100]

    def field(tile, name, dtype):
        nonlocal records
        record = tile if name == "height" else {"path": tile["derived"][name + "_path"],
                                                 "sha256": tile["derived"][name + "_sha256"]}
        raw = zlib.decompress(verified_bytes(folder, record))
        records += 1
        if len(raw) != 1_000_000 * np.dtype(dtype).itemsize:
            raise ValueError(f"INVALID_FIELD_LENGTH: {tile['id']}:{name}")
        return np.frombuffer(raw, dtype=dtype).reshape(1000, 1000)

    def example(mask, rx, ry, reason, values=None):
        locations = np.argwhere(mask)
        if not len(locations):
            return
        for row, col in locations[:1 if reason == "estimated_height_max" else 4]:
            entry = {"reason": reason, "site": [rx * 100 + int(col) // 10,
                                                ry * 100 + 99 - int(row) // 10],
                     "post_m": [rx * 20000 + int(col) * 20 + 10,
                                (ry + 1) * 20000 - int(row) * 20 - 10]}
            if values is not None:
                entry["value"] = int(values[row, col])
            if reason == "estimated_height_max" or sum(item["reason"] == reason for item in candidates) < 80:
                candidates.append(entry)

    for tile in manifest["elevation_tiles"]:
        check_time()
        rx, ry = (int(x) // 20000 for x in tile["origin"])
        if (tile["origin"] != [rx * 20000, ry * 20000] or tile["size"] != [1000, 1000] or
                tile["spacing_m"] != 20 or tile["encoding"] != "int16_le_zlib" or
                tile["row_order"] != "north_to_south" or tile["nodata"] != NODATA or
                (rx, ry) in tile_records):
            raise ValueError(f"INVALID_R4_TILE: {tile['id']}")
        tile_records[rx, ry] = tile
        elevation, level, water = field(tile, "height", "<i2"), field(tile, "levels", "u1"), field(tile, "water", "u1")
        q, bodies = field(tile, "quality", "u1"), field(tile, "water_body", "<u4")
        method, distance = field(tile, "method", "u1"), field(tile, "support_distance", "<u2")
        expected_interior = independently_derived_levels(elevation)
        interior_valid = elevation[10:-10, 10:-10] != NODATA
        interior_wrong = interior_valid & (expected_interior != level[10:-10, 10:-10])
        counts["level_formula_interior_posts_checked"] += int(interior_valid.sum())
        counts["level_formula_interior_mismatch"] += int(interior_wrong.sum())
        if np.any(interior_wrong):
            padded_wrong = np.pad(interior_wrong, 10)
            example(padded_wrong, rx, ry, "level_formula_interior_mismatch", level)
        invalid = ((level > 5) & (level != 255)) | ((water > 4) & (water != 255)) | (q > 4)
        invalid |= ~np.isin(method, list(declared_methods))
        inland = np.isin(water, [1, 3, 4])
        body_valid = bodies < len(body_kind)
        mapped_kind = body_kind[np.minimum(bodies, len(body_kind) - 1)]
        invalid |= (~body_valid & (water != 255)) | ((mapped_kind != water) & (water != 255))
        invalid |= inland & ((elevation == NODATA) | (level > 5))
        invalid |= ((water != 2) & (water != 255) & (q == 0))
        invalid |= (q == 1) & ((method != 0) | (distance != 0) | (elevation == NODATA))
        invalid |= np.isin(q, [2, 3]) & ((method != 1) | (distance > 60))
        invalid |= (method == 3) & (distance > 1000)
        invalid |= (q >= 2) & (elevation == NODATA)
        if np.any(invalid):
            issues.append({"tile": tile["id"], "invalid_posts": int(invalid.sum())})
            example(invalid, rx, ry, "invalid_post")
        measured_height = elevation != NODATA
        sample_ok = ((water == 2) | ((water != 255) & measured_height & (level <= 5))) & ~invalid
        usable_height = sample_ok & measured_height
        flags_by_region[rx, ry] = (sample_ok.astype("u1") | (usable_height.astype("u1") << 1) |
                                     ((water == 0).astype("u1") << 2) | (q << 3) | ((water == 2).astype("u1") << 6))
        local_classes = ((water == 0).astype("u1") | ((water == 2).astype("u1") << 1) |
                          (inland.astype("u1") << 2))
        classes_by_site[region_slice(rx, ry)] = np.bitwise_or.reduce(
            np.bitwise_or.reduce(local_classes.reshape(100, 10, 100, 10), axis=3), axis=1)
        for label, array in (("quality", q), ("water_kind", water), ("method", method)):
            for value, number in zip(*np.unique(array, return_counts=True)):
                counts[f"{label}_{value}"] += int(number)
        for code in declared_methods:
            chosen = method == code
            for name, selected in (("zero", distance == 0), ("1_60", (distance > 0) & (distance <= 60)),
                                   ("61_200", (distance > 60) & (distance <= 200)),
                                   ("201_1000", (distance > 200) & (distance <= 1000)),
                                   ("over_1000", (distance > 1000) & (distance < 65535)),
                                   ("unavailable", distance == 65535)):
                method_distance[f"{code}:{name}"] += int(np.count_nonzero(chosen & selected))
        estimated = (q >= 2) & measured_height
        if np.any(estimated):
            values = np.where(estimated, elevation, -32768)
            maximum = int(values.max())
            example(estimated & (elevation == maximum), rx, ry, "estimated_height_max", elevation)
            example(estimated & (distance == 65535), rx, ry, "estimate_without_local_MOI_distance", method)
        for ident in np.unique(bodies[bodies > 1]):
            body_regions.setdefault(int(ident), set()).add((rx, ry))
        old = old_tiles.get((rx, ry))
        original_known = np.zeros((1000, 1000), dtype=bool)
        if old is not None:
            old_height = np.frombuffer(zlib.decompress(verified_bytes(r2_folder, old)), dtype="<i2").reshape(1000, 1000)
            old_d = old["derived"]
            old_water = np.frombuffer(zlib.decompress(verified_bytes(r2_folder,
                {"path": old_d["water_path"], "sha256": old_d["water_sha256"]})), dtype="u1").reshape(1000, 1000)
            original_known = (old_water == 0) & (old_height != NODATA)
            original = original_known & (old_active | active)[region_slice(rx, ry)].repeat(10, axis=0).repeat(10, axis=1)
            retained = original & (water == 0)
            changed = retained & (old_height != elevation)
            nonsea_changed = original & ((water == 0) | inland) & (old_height != elevation)
            counts["r2_valid_land_posts_compared"] += int(original.sum())
            counts["r2_land_retained_as_land"] += int(retained.sum())
            counts["r2_retained_MOI_height_changed"] += int(changed.sum())
            counts["r2_retained_nonsea_MOI_height_changed"] += int(nonsea_changed.sum())
            for name, condition in (("sea", water == 2), ("inland", inland), ("missing", water == 255)):
                counts[f"r2_land_reclassified_{name}"] += int(np.count_nonzero(original & condition))
            if np.any(changed):
                example(changed, rx, ry, "changed_retained_MOI", elevation)
        new_measured = (q == 1) & ~original_known
        if np.any(new_measured):
            original_core = independent_moi_core(rx, ry)
            different = new_measured & (elevation != original_core)
            counts["new_q1_posts_compared_to_fixed_MOI_core"] += int(new_measured.sum())
            counts["new_q1_MOI_value_mismatch"] += int(different.sum())
            counts["new_q1_zero_height_posts_checked"] += int(np.count_nonzero(new_measured & (elevation == 0)))
            example(different, rx, ry, "new_q1_MOI_mismatch", elevation)
            example(new_measured & (elevation == 0), rx, ry, "new_q1_zero_source", elevation)
            example(new_measured, rx, ry, "new_q1_source_check", elevation)
        detail = tile["derived"].get("water_detail")
        if detail:
            fine_records.append(((rx, ry), detail))
        print(f"R4_AUDIT_POSTS {len(tile_records)}/{len(manifest['elevation_tiles'])}", flush=True)

    @lru_cache(maxsize=9)
    def packaged_height(region):
        tile = tile_records[region]
        return np.frombuffer(zlib.decompress(verified_bytes(folder, tile)), dtype="<i2").reshape(1000, 1000)

    formula_skipped_sites = np.zeros_like(summary, dtype=bool)
    external_halos = {}
    halo_evidence = None
    if level_halo_index is not None:
        halo_raw = level_halo_index.read_bytes()
        halo_index = json.loads(halo_raw)
        if (halo_index.get("format") != 1 or halo_index.get("source_post_rule") != source_policy or
                halo_index.get("source_manifest_sha256") != hashlib.sha256(manifest_raw).hexdigest()):
            raise ValueError("LEVEL_HALO_SOURCE_PIN_MISMATCH")
        for record in halo_index["tiles"]:
            region = tuple(record["region"])
            if region in external_halos or region not in tile_records:
                raise ValueError("INVALID_OR_DUPLICATE_LEVEL_HALO_REGION")
            rx, ry = region
            if (record.get("origin") != [rx * 20000 - 200, ry * 20000 - 200] or
                    record.get("size") != [1020, 1020] or record.get("spacing_m") != 20 or
                    record.get("row_order") != "north_to_south" or record.get("encoding") != "int16_le_zlib" or
                    record.get("nodata") != NODATA or record.get("core_height_sha256") != tile_records[region]["sha256"]):
                raise ValueError("INVALID_LEVEL_HALO_GRID_OR_CORE_PIN")
            external_halos[region] = record
        halo_evidence = {"index_path": str(level_halo_index),
                         "index_sha256": hashlib.sha256(halo_raw).hexdigest(),
                         "source_manifest_sha256": halo_index["source_manifest_sha256"],
                         "tiles": len(external_halos)}
    with (out / "level_formula_unverifiable_sites.jsonl").open("w", encoding="utf-8") as skips:
        for (rx, ry), tile in tile_records.items():
            check_time()
            halo = np.full((1020, 1020), NODATA, dtype="<i2")
            known = np.zeros((1020, 1020), dtype=bool)
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    neighbour = (rx + dx, ry - dy)
                    if neighbour not in tile_records:
                        continue
                    dest_y = slice(0, 10) if dy == -1 else (slice(10, 1010) if dy == 0 else slice(1010, 1020))
                    dest_x = slice(0, 10) if dx == -1 else (slice(10, 1010) if dx == 0 else slice(1010, 1020))
                    source_y = slice(990, 1000) if dy == -1 else (slice(None) if dy == 0 else slice(0, 10))
                    source_x = slice(990, 1000) if dx == -1 else (slice(None) if dx == 0 else slice(0, 10))
                    halo[dest_y, dest_x] = packaged_height(neighbour)[source_y, source_x]
                    known[dest_y, dest_x] = True
            if (rx, ry) in external_halos:
                raw = zlib.decompress(verified_bytes(level_halo_index.parent, external_halos[rx, ry]))
                if len(raw) != 1020 * 1020 * 2:
                    raise ValueError("INVALID_LEVEL_HALO_LENGTH")
                reconstructed = np.frombuffer(raw, dtype="<i2").reshape(1020, 1020)
                different = known & (halo != reconstructed)
                counts["audit_only_halo_packaged_posts_compared"] += int(known.sum())
                counts["audit_only_halo_packaged_mismatch"] += int(different.sum())
                if np.any(different):
                    raise ValueError(f"LEVEL_HALO_DIFFERS_FROM_PACKED_NEIGHBOUR: {(rx, ry)}:{int(different.sum())}")
                halo[~known] = reconstructed[~known]
                counts["audit_only_halo_posts_supplied"] += int(np.count_nonzero(~known))
                known[:] = True
            coverage = box_sum_21(known) == 441
            boundary = np.ones((1000, 1000), dtype=bool)
            boundary[10:-10, 10:-10] = False
            valid = halo[10:-10, 10:-10] != NODATA
            chosen = boundary & coverage & valid
            skipped = boundary & ~coverage & valid
            levels = field(tile, "levels", "u1")
            expected = independently_derived_levels(halo)
            wrong = chosen & (expected != levels)
            counts["level_formula_boundary_posts_checked"] += int(chosen.sum())
            counts["level_formula_boundary_mismatch"] += int(wrong.sum())
            counts["level_formula_unverifiable_without_unpacked_halo_posts"] += int(skipped.sum())
            example(wrong, rx, ry, "level_formula_boundary_mismatch", levels)
            per_site = skipped.reshape(100, 10, 100, 10).sum(axis=(1, 3))
            formula_skipped_sites[region_slice(rx, ry)] = per_site > 0
            for row, column in np.argwhere(per_site > 0):
                skips.write(json.dumps({"site": [rx * 100 + int(column), ry * 100 + 99 - int(row)],
                    "posts": int(per_site[row, column]), "reason": "unverifiable_without_unpacked_halo"}, separators=(",", ":")) + "\n")
    packaged_height.cache_clear()

    def expanded_flags(rx, ry):
        result = np.zeros((1002, 1002), dtype="u1")
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                neighbour = (rx + dx, ry - dy)
                dest_y = slice(0, 1) if dy == -1 else (slice(1, 1001) if dy == 0 else slice(1001, 1002))
                dest_x = slice(0, 1) if dx == -1 else (slice(1, 1001) if dx == 0 else slice(1001, 1002))
                source_y = slice(999, 1000) if dy == -1 else (slice(None) if dy == 0 else slice(0, 1))
                source_x = slice(999, 1000) if dx == -1 else (slice(None) if dx == 0 else slice(0, 1))
                source = flags_by_region.get(neighbour)
                if source is not None:
                    result[dest_y, dest_x] = source[source_y, source_x]
                else:
                    yy, xx = np.mgrid[dest_y, dest_x]
                    sx = (rx * 1000 + xx - 1) // 10
                    sy = (ry * 1000 + 1000 - yy) // 10
                    gx, gy = sx - origin[0], height - 1 - (sy - origin[1])
                    inside = (gx >= 0) & (gx < width) & (gy >= 0) & (gy < height)
                    classes = summary[np.clip(gy, 0, height - 1), np.clip(gx, 0, width - 1)]
                    result[dest_y, dest_x] = (inside & (classes == 1)).astype("u1")
        return result

    for (rx, ry), core in flags_by_region.items():
        check_time()
        expanded = expanded_flags(rx, ry)
        half = np.empty((2000, 2000), dtype=bool)
        half_quality = np.empty((2000, 2000), dtype="u1")
        for dy in (0, 1):
            for dx in (0, 1):
                points = [expanded[dy + y:dy + y + 1000, dx + x:dx + x + 1000]
                          for y, x in ((0, 0), (1, 0), (0, 1), (1, 1))]
                four_good = np.logical_and.reduce([(point & 1) != 0 for point in points])
                half[dy::2, dx::2] = ((core & 1) != 0) & (((core & 4) == 0) | four_good)
                source_q = (core >> 3) & 7
                dry_q = source_q.copy()
                for point in points:
                    dry_q = np.maximum(dry_q, np.where((point & 6) == 6, (point >> 3) & 7, 0))
                half_quality[dy::2, dx::2] = np.where((core & 64) != 0, 0,
                                                       np.where((core & 4) != 0, dry_q, source_q))
        states[region_slice(rx, ry)] = site_states(half, 20)
        public_quality[region_slice(rx, ry)] = half_quality.reshape(100, 20, 100, 20).max(axis=(1, 3))

    for (rx, ry), detail in fine_records:
        check_time()
        if detail["encoding"] != "u32_le_zlib_segments" or detail["site_size"] != [100, 100] or detail["site_order"] != "north_to_south":
            raise ValueError("INVALID_FINE_GRID")
        raw_index = verified_bytes(folder, {"path": detail["index_path"], "sha256": detail["index_sha256"]})
        bank = verified_bytes(folder, {"path": detail["data_path"], "sha256": detail["data_sha256"]})
        records += 2
        if len(raw_index) != detail["index_bytes"] or len(bank) != detail["data_bytes"]:
            raise ValueError("INVALID_FINE_BANK_LENGTH")
        index = json.loads(raw_index)
        if not isinstance(index, dict) or len(index) > 10000:
            raise ValueError("INVALID_FINE_INDEX")
        end = 0
        expanded = expanded_flags(rx, ry)
        for key, segment in sorted(index.items(), key=lambda p: p[1]["offset"]):
            if str(int(key)) != key or not 0 <= int(key) < 10000 or segment["offset"] != end:
                raise ValueError("INVALID_FINE_SEGMENT_ORDER")
            start, length = segment["offset"], segment["compressed_bytes"]
            if length <= 0 or start + length > len(bank):
                raise ValueError("INVALID_FINE_SEGMENT_RANGE")
            compressed = bank[start:start + length]
            if hashlib.sha256(compressed).hexdigest() != segment["sha256"]:
                raise ValueError("FINE_SEGMENT_HASH_MISMATCH")
            raw = zlib.decompress(compressed)
            if len(raw) != 40000:
                raise ValueError("INVALID_FINE_MASK_LENGTH")
            mask = np.frombuffer(raw, dtype="<u4").reshape(100, 100)
            if np.any(mask >= len(body_kind)) or np.any(body_kind[mask] == 255):
                raise ValueError("UNKNOWN_FINE_BODY_ID")
            row, col = divmod(int(key), 100)
            sx, sy = fine_site((rx, ry), int(key))
            gx, gy = sx - origin[0], height - 1 - (sy - origin[1])
            window = expanded[row * 10:row * 10 + 12, col * 10:col * 10 + 12]
            valid = fine_validity(mask, window)
            states[gy, gx] = site_states(valid, 100)[0, 0]
            fine_present[gy, gx] = True
            fine_bad[gy, gx] = not bool(valid.all())
            public_quality[gy, gx] = fine_public_quality(mask, window).max()
            classes_by_site[gy, gx] = int(np.any(mask == 0)) | (int(np.any(mask == 1)) << 1) | (int(np.any(mask > 1)) << 2)
            counts["fine_segments_verified"] += 1
            counts["fine_bad_cells"] += int(np.count_nonzero(~valid))
            for ident in np.unique(mask[mask > 1]):
                body_regions.setdefault(int(ident), set()).add((rx, ry))
                body_fine_sites[int(ident)] += 1
                water_rows, water_columns = np.nonzero(mask == ident)
                eastings = sx * 200 + water_columns * 2 + 1
                northings = (sy + 1) * 200 - water_rows * 2 - 1
                inside_source = intersects_xy(body_geometry[int(ident)], eastings, northings)
                counts["fine_water_centres_checked_against_source_polygon"] += len(water_rows)
                mismatches = int(np.count_nonzero(~inside_source))
                counts["fine_water_centres_outside_source_body"] += mismatches
                if mismatches and sum(item["reason"] == "fine_water_source_coordinate_mismatch" for item in candidates) < 30:
                    first = int(np.flatnonzero(~inside_source)[0])
                    candidates.append({"reason": "fine_water_source_coordinate_mismatch", "site": [sx, sy],
                                       "cell": [int(water_columns[first]), int(water_rows[first])],
                                       "body_id": int(ident), "source_id": body_by_id[int(ident)]["source_id"],
                                       "mismatched_cells": mismatches})
            if not valid.all():
                global_x = rx * 1000 + col * 10 + np.arange(12) - 1
                global_y = ry * 1000 + 1000 - row * 10 - np.arange(12)
                missing = np.array([[(int(x) // 1000, int(y) // 1000) not in tile_records
                                      for x in global_x] for y in global_y])
                # Diagnostic only: this does not change readiness or forgive a
                # missing neighbour. It distinguishes partial samples from a
                # failure that persists even if absent tiles were fully valid.
                optimistic = fine_validity(mask, np.where(missing & (window == 0), 7, window).astype("u1"))
                restored = int(np.count_nonzero(~valid & optimistic))
                residual = int(np.count_nonzero(~valid & ~optimistic))
                counts["fine_bad_cells_requiring_absent_neighbor_tile"] += restored
                counts["fine_bad_cells_not_explained_by_absent_neighbor_tile"] += residual
                bad_row, bad_col = np.argwhere(~valid)[0]
                if sum(item["reason"] == "fine_nonsea_without_support" for item in candidates) < 100:
                    candidates.append({"reason": "fine_nonsea_without_support", "site": [sx, sy],
                                       "cell": [int(bad_col), int(bad_row)], "absent_neighbor_cells": restored,
                                       "remaining_bad_cells": residual, "water_body": int(mask[bad_row, bad_col])})
            end += length
        if end != len(bank):
            raise ValueError("UNINDEXED_FINE_BANK_BYTES")

    ready = with_neighbours(states)
    required = active & np.isin(summary, [2, 3, 4])
    old_playable_lost = old_playable & ((scope != old_scope) | (summary == 0) | ~ready)
    changed_playable = old_playable & ((old_summary != summary) | old_playable_lost)
    playable_matrix = {str(old): {str(new): int(np.count_nonzero(old_playable &
                       (old_summary == old) & (summary == new))) for new in range(5)} for old in (2, 4)}
    with (out / "r2_playable_transitions.jsonl").open("w", encoding="utf-8") as handle:
        for y, x in np.argwhere(changed_playable):
            handle.write(json.dumps({"site": [origin[0] + int(x), origin[1] + height - 1 - int(y)],
                "r2_scope": int(old_scope[y, x]), "r2_summary": int(old_summary[y, x]),
                "r4_scope": int(scope[y, x]), "r4_summary": int(summary[y, x]),
                "r4_quality": int(quality[y, x]), "expandable_102": bool(ready[y, x]),
                "lost_expandability": bool(old_playable_lost[y, x])}, separators=(",", ":")) + "\n")
    ledger = []
    for gap in gaps:
        sx, sy = gap["site"]
        x, y = sx - origin[0], height - 1 - (sy - origin[1])
        status = int(summary[y, x])
        reason = ("scope_changed" if int(scope[y, x]) != gap["scope"] else
                  "still_missing" if status == 0 else
                  ("source_reclassified_sea" if ready[y, x] else "sea_reclassified_but_unexpandable") if status == 1 else
                  "recovered_expandable" if ready[y, x] else "classified_but_unexpandable")
        ledger.append({**gap, "r2_summary": 0, "r4_scope": int(scope[y, x]), "r4_summary": status,
                       "r4_source_quality": int(quality[y, x]), "tile_present": (sx // 100, sy // 100) in tile_records,
                       "fine_mask_present": bool(fine_present[y, x]),
                       "fine_core_supported": not bool(fine_bad[y, x]) if fine_present[y, x] else None,
                       "expandable_102": bool(ready[y, x]), "transition_reason": reason})
    ledger_text = "".join(json.dumps(x, ensure_ascii=False, separators=(",", ":")) + "\n" for x in ledger)
    ledger_path = out / "gap_sites.jsonl"
    ledger_path.write_text(ledger_text, encoding="utf-8")
    contradictions = {
        "summary_land_but_only_sea": (summary == 2) & (classes_by_site == 2) & active,
        "summary_sea_but_nonsea_cells": (summary == 1) & ((classes_by_site & 5) != 0) & active,
        "summary_sea_with_source_support_quality": (summary == 1) & (quality > 0) & active,
        "nonsea_with_zero_site_quality": required & (quality == 0),
        "public_quality_understates_contributors": active & (summary != 0) & (quality < public_quality),
    }
    contradiction_report = {}
    (out / "public_quality_required.u8").write_bytes(public_quality.tobytes())
    with (out / "quality_understated_sites.jsonl").open("w", encoding="utf-8") as handle:
        for y, x in np.argwhere(contradictions["public_quality_understates_contributors"]):
            handle.write(json.dumps({"site": [origin[0] + int(x), origin[1] + height - 1 - int(y)],
                "scope": int(scope[y, x]), "summary": int(summary[y, x]), "quality": int(quality[y, x]),
                "actual_public_quality_max": int(public_quality[y, x]),
                "fine_mask_present": bool(fine_present[y, x])}, separators=(",", ":")) + "\n")
    for name, selected in contradictions.items():
        contradiction_report[name] = {"count": int(selected.sum()), "examples": [
            {"site": [origin[0] + int(x), origin[1] + height - 1 - int(y)],
             "summary": int(summary[y, x]), "quality": int(quality[y, x]),
             "actual_public_quality_max": int(public_quality[y, x]),
             "surface_bits": int(classes_by_site[y, x])} for y, x in np.argwhere(selected)[:15]]}
    blocked = required & ~ready
    with (out / "blocked_sites.jsonl").open("w", encoding="utf-8") as handle:
        for y, x in np.argwhere(blocked):
            handle.write(json.dumps({"site": [origin[0] + int(x), origin[1] + height - 1 - int(y)],
                "scope": int(scope[y, x]), "summary": int(summary[y, x]), "quality": int(quality[y, x]),
                "fine_mask_present": bool(fine_present[y, x]), "fine_core_failed": bool(fine_bad[y, x]),
                "own_core_supported": bool(states[y, x] & 1)}, separators=(",", ":")) + "\n")
    for y, x in np.argwhere(blocked)[:100]:
        candidates.append({"reason": "blocked_102_halo", "site": [origin[0] + int(x), origin[1] + height - 1 - int(y)],
                           "summary": int(summary[y, x]), "fine": bool(fine_present[y, x])})
    highest = sorted((item for item in candidates if item["reason"] == "estimated_height_max"),
                     key=lambda item: item["value"], reverse=True)[:40]
    candidates = highest + [item for item in candidates if item["reason"] != "estimated_height_max"]
    (out / "extreme_candidates.json").write_text(json.dumps(candidates, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    missing_old_tiles = sorted(set(old_tiles) - set(tile_records))
    missing_required_regions = [region for region in missing_old_tiles if np.any(
        active[region_slice(*region)] & (summary[region_slice(*region)] != 1))]
    transition_counts = dict(Counter(x["transition_reason"] for x in ledger))
    errors = {"invalid_tiles": len(issues), "scope_changed_sites": int(scope_changed.sum()),
              "content_missing_sites": int(np.count_nonzero(active & (summary == 0))),
              "content_nonsea_unexpandable_sites": int(blocked.sum()),
              "original_gaps_unresolved": sum(1 for x in ledger if x["transition_reason"] in
                                               ("scope_changed", "still_missing", "classified_but_unexpandable", "sea_reclassified_but_unexpandable")),
              "retained_MOI_height_changes": counts["r2_retained_nonsea_MOI_height_changed"],
              "new_q1_MOI_value_mismatch": counts["new_q1_MOI_value_mismatch"],
              "public_site_quality_understated": contradiction_report["public_quality_understates_contributors"]["count"],
              "level_formula_mismatch": counts["level_formula_interior_mismatch"] + counts["level_formula_boundary_mismatch"],
              "original_r2_playable_sites_lost": int(old_playable_lost.sum()),
              "old_external_scope_leaked_to_open_sea": int(outside_scope_leak.sum()),
              "external_GSHHG_summary_mismatch": int(external_geography_mismatch.sum()),
              "fine_water_source_coordinate_mismatches": counts["fine_water_centres_outside_source_body"],
              "summary_sea_contradictions": contradiction_report["summary_sea_but_nonsea_cells"]["count"]}
    report = {"status": "PASS" if not any(errors.values()) else "FAIL", "errors": errors,
              "manifest_sha256": hashlib.sha256(manifest_raw).hexdigest(), "base_revision": manifest["base_revision"],
              "r2_manifest_sha256": EXPECTED_R2_MANIFEST_SHA256, "tile_count": len(tile_records),
              "records_verified": records, "post_counts": dict(counts), "method_distance_counts": dict(method_distance),
              "gap_count": len(ledger), "gap_transition_counts": transition_counts,
              "gap_transitions_by_scope": {name: dict(Counter(row["transition_reason"] for row in ledger if row["scope"] == code))
                                            for code, name in SCOPE_NAMES.items()},
              "gap_ledger_sha256": hashlib.sha256(ledger_path.read_bytes()).hexdigest(),
              "content_required_nonsea_sites": int(required.sum()), "content_expandable_nonsea_sites": int((required & ready).sum()),
              "original_r2_playable_sites": int(old_playable.sum()),
              "r2_playable_class_transitions": playable_matrix,
              "content_by_scope": {name: {"required_nonsea": int(np.count_nonzero(required & (scope == code))),
                                            "expandable_nonsea": int(np.count_nonzero(required & ready & (scope == code))),
                                            "blocked_nonsea": int(np.count_nonzero(blocked & (scope == code))),
                                            "missing": int(np.count_nonzero((summary == 0) & (scope == code)))}
                                   for code, name in SCOPE_NAMES.items()},
              "body_registry_count": len(body_by_id), "bodies_in_multiple_regions": sum(len(v) > 1 for v in body_regions.values()),
              "OSM_source_properties_verified": len(original_kinds),
              "bodies_in_multiple_fine_sites": sum(v > 1 for v in body_fine_sites.values()),
              "body_identity_rule": "One unique source ID maps to one global body ID; every coarse and fine reference resolves with the same kind",
              "summary_surface_contradictions": contradiction_report, "invalid_tiles": issues,
              "missing_r2_regions": [list(p) for p in missing_old_tiles],
              "missing_r2_regions_still_containing_nonsea_content": [list(p) for p in missing_required_regions],
              "external_background": {"scope0_sites": int(external.sum()),
                  "old_scope0_sites": int(np.count_nonzero(old_scope == 0)),
                  "old_scope0_opened_as_four_island_content": int(np.count_nonzero((old_scope == 0) & active)),
                  "GSHHG_source_sha256": legacy_sources.COAST_SHA,
                  "note": "Scope0 geography is checked separately and never counted as recovered active content"},
              "MOI_comparison_scope": "Original r2 valid dry-land posts within old or current scopes 1..4; compare retained land and inland-water heights, count sea/missing reclassification separately. Missing Regions are listed, not silently compared as equal.",
              "original_MOI_TIFF_sha256": moi_source_hashes,
              "new_MOI_comparison": "All q1 posts not supplied by the pinned r2 lattice are independently reprojected from original MOI TIFFs under the fixed Region-core GDAL-nearest policy; this validates provenance/policy, not surveyed ground truth or the estimator's numerical accuracy.",
              "level_formula": {"status": "unverifiable_without_unpacked_halo" if np.any(formula_skipped_sites) else "all_materialized_valid_height_posts_checked",
                  "unverifiable_sites": int(formula_skipped_sites.sum()),
                  "unverifiable_active_nonsea_sites": int(np.count_nonzero(formula_skipped_sites & required)),
                  "audit_only_halo": halo_evidence,
                  "note": "Interior and every boundary whose 21x21 input window is packaged are checked exactly. Skipped sea-side source halos are not declared formula PASS."},
              "public_quality_required": {"path": "public_quality_required.u8", "size": list(size),
                  "site_origin": list(origin), "encoding": "u8", "row_order": "north_to_south",
                  "sha256": hashlib.sha256(public_quality.tobytes()).hexdigest()},
              "coordinate_rule": "fine key=row*100+column; site=(region_x*100+column,region_y*100+99-row); 2m rows run north to south",
              "scope": "All packaged records and all original/r4 content Sites; exact source availability for 100x100 gameplay cells plus 1-cell halo; every fine inland-water centre checked against the source body's projected polygon including holes; not Godot/rendering or geometric coastline accuracy",
              "elapsed_seconds": time.monotonic() - started}
    if (folder / "manifest.json").read_bytes() != manifest_raw:
        raise ValueError("MANIFEST_CHANGED_DURING_AUDIT")
    return report


def self_check():
    flags = np.full((12, 12), 7, dtype="u1")
    mask = np.zeros((100, 100), dtype="u4")
    assert fine_validity(mask, flags).all()
    flags[:] = 1  # coarse sea without measured height is not dry-island support
    assert not fine_validity(mask, flags).any()
    mask[:] = 1
    assert fine_validity(mask, flags).all()
    mask[:] = 2
    assert not fine_validity(mask, flags).any()
    flags[:] = 3  # valid water height can support a fine lake island
    mask[:] = 0
    assert fine_validity(mask, flags).all()
    mask[:] = 2
    flags[1, 1] = 1
    actual = fine_validity(mask, flags)
    assert not actual[:10, :10].any() and actual[-10:, -10:].all()
    assert fine_site((-2, -3), 0) == (-200, -201)
    assert fine_site((-2, -3), 9999) == (-101, -300)
    assert fine_site((0, 0), 9900) == (0, 0)
    flags[:] = 7 | (1 << 3)
    mask[:] = 0
    assert np.all(fine_public_quality(mask, flags) == 1)
    # A neighbouring Site's q1 water can be a contributor even if this Site's
    # containing 10x10 posts are all dry q1. Test all four sides and corners.
    for source, expected in (
            ((0, slice(None)), (slice(0, 5), slice(None))),
            ((11, slice(None)), (slice(95, 100), slice(None))),
            ((slice(None), 0), (slice(None), slice(0, 5))),
            ((slice(None), 11), (slice(None), slice(95, 100))),
            ((0, 0), (slice(0, 5), slice(0, 5))),
            ((0, 11), (slice(0, 5), slice(95, 100))),
            ((11, 0), (slice(95, 100), slice(0, 5))),
            ((11, 11), (slice(95, 100), slice(95, 100)))):
        flags[:] = 7 | (1 << 3)
        flags[source] = 3 | (1 << 3)
        expected_quality = np.ones((100, 100), dtype="u1")
        expected_quality[expected] = 4
        assert np.array_equal(fine_public_quality(mask, flags), expected_quality)
    flags[:] = 7 | (1 << 3)
    # A tiny lake island is dry in the fine mask but uses measured water posts.
    # Its public sample is q4 even when every source post is q1.
    flags[1:11, 1:11] = 3 | (1 << 3)
    assert fine_validity(mask, flags).all()
    assert np.all(fine_public_quality(mask, flags) == 4)
    mask[:] = 2
    assert np.all(fine_public_quality(mask, flags) == 1)
    mask[:] = 1
    assert np.all(fine_public_quality(mask, flags) == 0)
    heights = np.full((50, 50), 1000, dtype="<i2")
    assert np.all(independently_derived_levels(heights) == 2)
    heights[25, 25] += 16
    assert independently_derived_levels(heights)[15, 15] == 3
    heights[:] = NODATA
    heights[25, 25] = 1234
    expected = independently_derived_levels(heights)
    assert expected[15, 15] == 2 and np.count_nonzero(expected != 255) == 1
    valid = np.ones((300, 300), dtype=bool)
    valid[99, 150] = False  # south edge of northern neighbour blocks centre halo
    ready = with_neighbours(site_states(valid, 100))
    assert not ready[1, 1] and ready[1, 0] == False
    valid[:] = True
    assert with_neighbours(site_states(valid, 100))[1, 1]
    # Compare the compact nine-bit representation with a literal 102x102
    # window, including each cardinal/diagonal neighbouring border.
    for row, col in ((99, 99), (99, 150), (99, 200), (150, 99), (150, 200),
                     (200, 99), (200, 150), (200, 200), (100, 100), (98, 150)):
        valid[:] = True
        valid[row, col] = False
        assert with_neighbours(site_states(valid, 100))[1, 1] == valid[99:201, 99:201].all()
    print("R4_AUDIT_SELF_CHECK PASS")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--r2", type=Path, default=R2)
    parser.add_argument("--out", type=Path, default=OUTPUT)
    parser.add_argument("--r4", type=Path, help="Audit this r4 candidate as well as writing the immutable r2 inventory")
    parser.add_argument("--timeout-seconds", type=int, default=600)
    parser.add_argument("--osm-source", type=Path, default=ROOT / "tools/region_lab/.tmp/osm_source")
    parser.add_argument("--level-halo-index", type=Path, help="Hash-pinned audit-only source halos for otherwise unpackaged sea neighbours")
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        self_check()
        return 0
    report, gaps, r2_manifest = r2_gap_inventory(args.r2)
    args.out.mkdir(parents=True, exist_ok=True)
    lines = "".join(json.dumps(gap, ensure_ascii=False, separators=(",", ":")) + "\n" for gap in gaps)
    list_path = args.out / "r2_gap_inventory.jsonl"
    list_path.write_text(lines, encoding="utf-8")
    report["gap_inventory_path"] = str(list_path)
    report["gap_inventory_sha256"] = hashlib.sha256(list_path.read_bytes()).hexdigest()
    report_path = args.out / "r2_gap_inventory_report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("REGION_R2_GAP_INVENTORY", json.dumps(report, ensure_ascii=False))
    if args.r4 is not None:
        audit_path = args.out / "r4_recovery_report.json"
        if audit_path.exists():
            raise ValueError("OUTPUT_ALREADY_EXISTS: use a fresh --out directory to preserve every run")
        try:
            recovered = audit_r4(args.r4, args.r2, gaps, r2_manifest, args.out, args.timeout_seconds, args.osm_source,
                                 args.level_halo_index)
        except (OSError, ValueError, KeyError, TypeError, TimeoutError, zlib.error) as error:
            recovered = {"status": "FAIL", "exception": f"{type(error).__name__}: {error}",
                         "candidate": str(args.r4), "recorded_at": datetime.now(timezone.utc).isoformat()}
        audit_path.write_text(json.dumps(recovered, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print("REGION_R4_RECOVERY_AUDIT", json.dumps({key: recovered[key] for key in
              ("status", "errors", "exception", "tile_count", "gap_count", "gap_transition_counts", "elapsed_seconds")
              if key in recovered}, ensure_ascii=False), flush=True)
        return 0 if recovered["status"] == "PASS" else 1
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, TypeError) as error:
        print("REGION_R2_GAP_INVENTORY_FAIL", str(error))
        raise SystemExit(1) from error
