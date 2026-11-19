"""Build a separate, reviewable r4 Taiwan atlas from closed OSM geometry.

The r2 package remains untouched.  Every source DEM value retained as land
stays byte-identical; estimates carry per-post quality/method/distance.
"""

from __future__ import annotations

from collections import Counter
from contextlib import ExitStack
import argparse
from functools import lru_cache
import hashlib
import json
import math
import shutil
import time
import zlib
from pathlib import Path

import numpy as np
import rasterio
from pyproj import Transformer
from rasterio.features import rasterize
from rasterio.transform import from_origin
from shapely.geometry import Point, box, shape
from shapely.ops import transform, unary_union
from shapely.strtree import STRtree

import import_taiwan as atlas
from r4_estimation import METHODS, NODATA, NO_DISTANCE, estimate_posts

OUT = atlas.ROOT / "assets/region_lab/earth_tw_tm2_121_v1_r4"
SOURCE = atlas.TEMP / "osm_source"
SOURCE_FILES = ("land.geojson", "inland_water.geojson", "provenance.json")
REVISION = "moi-35430-osm-20260927-r4-pinned-source-quality-fix"
R2_MANIFEST_SHA = "2ab25eeaa685782b42928d206ec808e4f1bb4da5e771cc67f0f86e8fefb07f61"
EST_HALO = 61  # 1000 m support search, 200 m level background, one shore-neighbour post.
POSTS = atlas.SAMPLES_PER_REGION
SITE_POSTS = atlas.SITE_M // atlas.SAMPLE_M
NAMES = ("outside_content", "taiwan", "penghu", "green_island", "lanyu", "surrounding_sea")


def save(path: Path, data: bytes) -> dict:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return {"path": path.relative_to(OUT).as_posix(), "sha256": atlas.sha256(path)}


def write_coverage_report(report: dict) -> None:
    """Include the report itself in the exact on-disk package byte total."""
    path = OUT / "coverage_report.json"
    other_bytes = sum(p.stat().st_size for p in OUT.rglob("*")
                      if p.is_file() and p != path)
    for _ in range(8):
        data = (json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        total = other_bytes + len(data)
        if report.get("package_bytes") == total:
            path.write_bytes(data)
            return
        report["package_bytes"] = total
    raise ValueError("Coverage-report package size did not converge")


def assemble_fixed_cores(core_reader, rx: int, ry: int, halo: int,
                         dtype, fill) -> np.ndarray:
    """Copy one globally owned 20 km core per post into a halo window."""
    side = POSTS + 2 * halo
    result = np.full((side, side), fill, dtype=dtype)
    west_post = rx * POSTS - halo
    north_post = (ry + 1) * POSTS + halo - 1
    for owner_y in range(ry - 1, ry + 2):
        for owner_x in range(rx - 1, rx + 2):
            x0 = max(0, owner_x * POSTS - west_post)
            x1 = min(side, (owner_x + 1) * POSTS - west_post)
            y0 = max(0, north_post - ((owner_y + 1) * POSTS - 1))
            y1 = min(side, north_post - owner_y * POSTS + 1)
            if x0 >= x1 or y0 >= y1:
                continue
            core = core_reader(owner_x, owner_y)
            source_x = west_post + x0 - owner_x * POSTS
            source_y = (owner_y + 1) * POSTS - 1 - (north_post - y0)
            result[y0:y1, x0:x1] = core[source_y:source_y + y1 - y0,
                                         source_x:source_x + x1 - x0]
    return result


class FixedSourceReader:
    """Window-independent MOI/Cop posts, with r2 dry measurements pinned."""

    def __init__(self, main, penghu, cop_sources):
        atlas.verify_source(atlas.OUT / "manifest.json", R2_MANIFEST_SHA)
        old = json.loads((atlas.OUT / "manifest.json").read_text(encoding="utf-8"))
        if old["atlas_id"] != atlas.ATLAS or old["grid"] != {
                "origin": [0, 0], "cell_m": 2, "site_cells": 100,
                "region_sites": 100}:
            raise ValueError("Pinned r2 canonical source grid changed")
        self.old_tiles = {(int(t["origin"][0]) // atlas.REGION_M,
                           int(t["origin"][1]) // atlas.REGION_M): t
                          for t in old["elevation_tiles"]}
        self.main = main
        self.penghu = penghu
        self.cop_sources = cop_sources
        self.r2_pinned_changed: dict[tuple[int, int], int] = {}
        self.cop_conflicts: dict[tuple[int, int], int] = {}

    @lru_cache(maxsize=16)
    def moi_core(self, rx: int, ry: int) -> np.ndarray:
        raw = atlas.source_dem(self.main, self.penghu,
                               rx * atlas.REGION_M, ry * atlas.REGION_M)
        old = self.old_tiles.get((rx, ry))
        if old is not None:
            height_path = atlas.OUT / old["path"]
            water_path = atlas.OUT / old["derived"]["water_path"]
            atlas.verify_source(height_path, old["sha256"])
            atlas.verify_source(water_path, old["derived"]["water_sha256"])
            old_height = np.frombuffer(zlib.decompress(height_path.read_bytes()),
                                       dtype="<i2").reshape(POSTS, POSTS)
            old_water = np.frombuffer(zlib.decompress(water_path.read_bytes()),
                                      dtype="u1").reshape(POSTS, POSTS)
            pinned = (old_water == 0) & (old_height != NODATA)
            self.r2_pinned_changed[(rx, ry)] = int(np.count_nonzero(
                pinned & (raw != old_height)))
            raw[pinned] = old_height[pinned]
        return raw

    @lru_cache(maxsize=16)
    def cop_core(self, rx: int, ry: int) -> tuple[np.ndarray, np.ndarray]:
        west, south = rx * atlas.REGION_M, ry * atlas.REGION_M
        rect = box(west, south, west + atlas.REGION_M, south + atlas.REGION_M)
        matrix = from_origin(west, south + atlas.REGION_M,
                             atlas.SAMPLE_M, atlas.SAMPLE_M)
        dem, wbm, conflicts = atlas.copernicus_halo(
            self.cop_sources, matrix, (POSTS, POSTS), rect)
        self.cop_conflicts[(rx, ry)] = conflicts
        return dem, wbm

    def window(self, rx: int, ry: int, halo: int):
        raw = assemble_fixed_cores(self.moi_core, rx, ry, halo, np.int16, NODATA)
        cop = assemble_fixed_cores(lambda x, y: self.cop_core(x, y)[0],
                                   rx, ry, halo, np.float32, np.nan)
        wbm = assemble_fixed_cores(lambda x, y: self.cop_core(x, y)[1],
                                   rx, ry, halo, np.uint8, 255)
        return raw, cop, wbm


def load_sources():
    provenance = json.loads((SOURCE / "provenance.json").read_text(encoding="utf-8"))
    expected = {entry["path"]: entry["sha256"] for entry in provenance["outputs"]}
    for name in SOURCE_FILES[:2]:
        atlas.verify_source(SOURCE / name, expected[name])
    project = Transformer.from_crs(4326, 3826, always_xy=True).transform
    land_doc = json.loads((SOURCE / "land.geojson").read_text(encoding="utf-8"))
    land = [transform(project, shape(f["geometry"])) for f in land_doc["features"]]
    original = atlas.land_polygons()
    osm_tree = STRtree(land)
    # Keep Fujian and other external geography from r2; replace intersecting
    # island outlines rather than unioning old and new coasts.
    external = [p for p in original if len(osm_tree.query(p, predicate="intersects")) == 0]
    combined = land + external
    water_doc = json.loads((SOURCE / "inland_water.geojson").read_text(encoding="utf-8"))
    water = [transform(project, shape(f["geometry"])) for f in water_doc["features"]]
    water_properties = [f["properties"] for f in water_doc["features"]]
    source_ids = sorted({str(p["source_id"]) for p in water_properties
                         if int(p["kind_hint"]) != 2})
    id_by_source = {source: index + 2 for index, source in enumerate(source_ids)}
    water_ids = np.array([1 if int(p["kind_hint"]) == 2 else
                          id_by_source[str(p["source_id"])] for p in water_properties], dtype=np.uint32)
    body_data = {}
    for p in water_properties:
        if int(p["kind_hint"]) == 2:
            continue
        source_id = str(p["source_id"])
        entry = {
            "id": id_by_source[source_id], "source_id": source_id,
            "kind": int(p["kind_hint"]), "name": str(p.get("name") or "")}
        previous = body_data.get(entry["id"])
        if previous is not None and previous["kind"] != entry["kind"]:
            raise ValueError(f"Conflicting water kinds for {source_id}")
        body_data[entry["id"]] = entry
    kind_by_body = np.zeros(len(source_ids) + 2, dtype=np.uint8)
    kind_by_body[1] = 2
    for ident, entry in body_data.items():
        kind_by_body[ident] = entry["kind"]
    return provenance, combined, land, water, water_ids, body_data, kind_by_body


def global_scope(polygons: list, baseline: np.ndarray, bounds: tuple[int, int, int, int]):
    # The original r2 Penghu anchor lies in the sea according to the newer
    # unsimplified OSM coast.  This verified land anchor is recorded upstream.
    anchors = (("taiwan", 121.5654, 25.033, 20_000),
               ("penghu", 119.6, 23.58, 35_000),
               ("green_island", 121.492, 22.661, 10_000),
               ("lanyu", 121.54, 22.05, 10_000))
    scope, selection = atlas.content_scope(polygons, baseline, bounds, anchors)
    old = np.frombuffer((atlas.OUT / "content_scope.u8").read_bytes(), dtype="u1").reshape(scope.shape)
    # Old active coordinates remain in the same named content area even when
    # the newer OSM coastline says a former GSHHG land Site is now sea.
    active = (old >= 1) & (old <= 4)
    changed = int(np.count_nonzero(active & (scope != old)))
    scope[active] = old[active]
    return scope, selection, changed


def r4_preview_sites() -> list[dict]:
    previews = atlas.preview_sites()
    east, north = Transformer.from_crs(4326, 3826, always_xy=True).transform(119.6, 23.58)
    for item in previews:
        if item["label"] == "Penghu":
            item["lonlat"] = [119.6, 23.58]
            item["site"] = [math.floor(east / atlas.SITE_M),
                            math.floor(north / atlas.SITE_M)]
    return previews


def retain_external_background(summary: np.ndarray, scope: np.ndarray) -> dict:
    """Restore GSHHG geography outside the four OSM island groups.

    The OSM mainland query has open chains.  A coarse GSHHG mainland polygon
    can intersect an OSM island and be removed from the combined coast.  Old
    outside-content Sites must remain outside, with their GSHHG land silhouette
    even though no external gameplay elevation is packaged.
    """
    old_summary = np.frombuffer((atlas.OUT / "summary.u8").read_bytes(), dtype="u1")
    old_scope = np.frombuffer((atlas.OUT / "content_scope.u8").read_bytes(), dtype="u1")
    if old_summary.size != summary.size or old_scope.size != scope.size:
        raise ValueError("r2/r4 global Site grids differ")
    old_summary = old_summary.reshape(summary.shape)
    old_scope = old_scope.reshape(scope.shape)
    stale_sea = (old_scope == 0) & (scope == 5)
    reopened_islets = (old_scope == 0) & (scope >= 1) & (scope <= 4)
    scope[stale_sea] = 0
    external = scope == 0
    gshhg = atlas.coastal_summary(atlas.land_polygons(), atlas.projected_bounds())
    if gshhg.shape != summary.shape:
        raise ValueError("GSHHG external silhouette differs from Site grid")
    report = {
        "source": "gshhg_2_3_7_external_only",
        "r2_scope0_sites": int(np.count_nonzero(old_scope == 0)),
        "r2_scope0_summary_missing": int(np.count_nonzero((old_scope == 0) & (old_summary == 0))),
        "r2_external_reclassified_as_sea_before_restore": int(np.count_nonzero(stale_sea)),
        "r2_external_reopened_as_osm_islet_sites": int(np.count_nonzero(reopened_islets)),
        "gshhg_land_mixed_scope0_sites": int(np.count_nonzero(external & np.isin(gshhg, [2, 4]))),
    }
    summary[external] = gshhg[external]
    report["post_restore_class_match"] = int(np.count_nonzero(
        summary[external] == gshhg[external]))
    report["scope0_sites"] = int(np.count_nonzero(external))
    return report


def active_posts(scope: np.ndarray, rx: int, ry: int, bounds, halo: int) -> np.ndarray:
    west, east, south, north = bounds
    side = POSTS + 2 * halo
    global_x = rx * POSTS + np.arange(side) - halo
    global_y = ry * POSTS + POSTS - 1 - (np.arange(side) - halo)
    col = np.floor_divide(global_x, SITE_POSTS) - west * 100
    row = north * 100 - 1 - np.floor_divide(global_y, SITE_POSTS)
    x_ok = (col >= 0) & (col < scope.shape[1])
    y_ok = (row >= 0) & (row < scope.shape[0])
    codes = scope[np.clip(row, 0, scope.shape[0] - 1)[:, None],
                  np.clip(col, 0, scope.shape[1] - 1)[None, :]]
    return y_ok[:, None] & x_ok[None, :] & (codes >= 1) & (codes <= 4)


def support_components(center: np.ndarray, touched: np.ndarray):
    components = center.copy()
    new = (components == 0) & (touched > 0)
    components[new] = touched[new]
    # Extend one 20 m post into the sea so a 2 m vector-land cell can bilinearly
    # use a marked estimate even if its source-post centre is outside the shore.
    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1),
                   (-1, -1), (-1, 1), (1, -1), (1, 1)):
        shifted = np.roll(touched, (dy, dx), axis=(0, 1))
        if dy == -1:
            shifted[-1, :] = 0
        if dy == 1:
            shifted[0, :] = 0
        if dx == -1:
            shifted[:, -1] = 0
        if dx == 1:
            shifted[:, 0] = 0
        new = (components == 0) & (shifted > 0)
        components[new] = shifted[new]
    return components, (center == 0) & (components > 0)


def region_shapes(tree: STRtree, shapes: list, rect):
    return [shapes[int(index)] for index in sorted(tree.query(rect))]


def water_shapes(tree: STRtree, water: list, body_ids: np.ndarray, rect):
    indexes = sorted(tree.query(rect))
    return [(water[int(index)], int(body_ids[int(index)])) for index in indexes]


def fine_public_quality_max(mask: np.ndarray, quality: np.ndarray,
                            height: np.ndarray, water_kind: np.ndarray) -> int:
    """Worst quality actually exposed by a 2 m Site's four-post sampling.

    The containing post supplies the base quality.  Dry fine cells may also
    interpolate a coarse water post with valid height; the runtime labels that
    support as quality 4 even when its original measured height has quality 1.
    """
    if (mask.shape != (100, 100) or quality.shape != (12, 12) or
            height.shape != (12, 12) or water_kind.shape != (12, 12)):
        raise ValueError("Fine quality inputs have different Site grids")
    cell = np.arange(100)
    centre, low = cell // 10 + 1, (cell - 5) // 10 + 1
    base = quality[centre[:, None], centre[None, :]]
    dry = base.copy()
    for dy, dx in ((0, 0), (1, 0), (0, 1), (1, 1)):
        source_height = height[(low + dy)[:, None], (low + dx)[None, :]]
        source_quality = quality[(low + dy)[:, None], (low + dx)[None, :]]
        source_water = water_kind[(low + dy)[:, None], (low + dx)[None, :]]
        contributes = source_height != NODATA
        dry = np.maximum(dry, np.where(contributes, source_quality, 0))
        dry[contributes & (source_water != 0)] = 4
    return int(np.where(mask == 1, 0, np.where(mask == 0, dry, base)).max())


def fine_bank(rx: int, ry: int, site_candidates: np.ndarray,
              land_tree: STRtree, land: list, water_tree: STRtree,
              water: list, water_ids: np.ndarray, used_bodies: set[int],
              coarse_bodies: np.ndarray, source_quality: np.ndarray,
              source_height: np.ndarray, source_water: np.ndarray):
    index: dict[str, dict] = {}
    bank = bytearray()
    visible_land_sites = 0
    fine_quality_sites = np.zeros((100, 100), dtype=np.uint8)
    for site_row, site_col in np.argwhere(site_candidates):
        site_row, site_col = int(site_row), int(site_col)
        origin_e = rx * atlas.REGION_M + site_col * atlas.SITE_M
        north_n = (ry + 1) * atlas.REGION_M - site_row * atlas.SITE_M
        rect = box(origin_e, north_n - atlas.SITE_M,
                   origin_e + atlas.SITE_M, north_n)
        matrix = from_origin(origin_e, north_n, atlas.CELL_M, atlas.CELL_M)
        near_land = region_shapes(land_tree, land, rect)
        land_2m = rasterize([(g, 1) for g in near_land], out_shape=(100, 100),
                            transform=matrix, fill=0, dtype="uint8",
                            all_touched=True)
        mask = np.where(land_2m == 1, 0, 1).astype("<u4")
        if np.any(land_2m):
            visible_land_sites += 1
        near_water = water_shapes(water_tree, water, water_ids, rect)
        if near_water:
            inland = rasterize(near_water, out_shape=(100, 100), transform=matrix,
                               fill=0, dtype="uint32")
            choose = (land_2m == 1) & (inland > 0)
            mask[choose] = inland[choose]
        # Keep an exact fine source classification for every vector boundary
        # Site, including a tiny island which has no 20m source-post centre.
        coarse = coarse_bodies[site_row * SITE_POSTS:(site_row + 1) * SITE_POSTS,
                               site_col * SITE_POSTS:(site_col + 1) * SITE_POSTS]
        q0, x0 = EST_HALO + site_row * SITE_POSTS - 1, EST_HALO + site_col * SITE_POSTS - 1
        fine_quality_sites[site_row, site_col] = fine_public_quality_max(
            mask, source_quality[q0:q0 + 12, x0:x0 + 12],
            source_height[q0:q0 + 12, x0:x0 + 12],
            source_water[q0:q0 + 12, x0:x0 + 12])
        if np.all(mask == mask.flat[0]) and np.all(coarse == mask.flat[0]):
            continue
        used_bodies.update(int(x) for x in np.unique(mask) if x > 1)
        compressed = zlib.compress(mask.tobytes(), 6)
        local_index = site_row * 100 + site_col
        index[str(local_index)] = {
            "offset": len(bank), "compressed_bytes": len(compressed),
            "sha256": hashlib.sha256(compressed).hexdigest()}
        bank.extend(compressed)
    if not index:
        return None, visible_land_sites, fine_quality_sites
    code = f"r{rx}_{ry}"
    index_bytes = json.dumps(index, separators=(",", ":")).encode("utf-8")
    index_rec = save(OUT / "tiles" / f"{code}.fine_index.json", index_bytes)
    data_rec = save(OUT / "tiles" / f"{code}.fine_bank.bin", bytes(bank))
    return {
        "index_path": index_rec["path"], "index_sha256": index_rec["sha256"],
        "index_bytes": len(index_bytes),
        "data_path": data_rec["path"], "data_sha256": data_rec["sha256"],
        "data_bytes": len(bank), "encoding": "u32_le_zlib_segments",
        "site_size": [100, 100], "site_order": "north_to_south"}, visible_land_sites, fine_quality_sites


def build(only_region: tuple[int, int] | None = None) -> None:
    start = time.monotonic()
    deadline = start + 3600  # Explicit bound for the full isolated CPU-heavy build.
    atlas.verify_source(atlas.DEM_ARCHIVE, atlas.DEM_SHA)
    atlas.verify_source(atlas.COAST_ARCHIVE, atlas.COAST_SHA)
    atlas.extract_inputs()
    provenance, polygons, osm_land, water, water_ids, body_data, kind_by_body = load_sources()
    bounds = atlas.projected_bounds()
    west, east, south, north = bounds
    baseline = atlas.coastal_summary(polygons, bounds)
    summary = baseline.copy()
    scope, scope_selection, kept_r2_scope = global_scope(polygons, baseline, bounds)
    land_tree, water_tree = STRtree(polygons), STRtree(water)
    water_boundary = rasterize([(g.boundary, 1) for g in water],
                               out_shape=summary.shape,
                               transform=from_origin(west * atlas.REGION_M,
                                                     north * atlas.REGION_M,
                                                     atlas.SITE_M, atlas.SITE_M),
                               fill=0, dtype="uint8", all_touched=True)
    summary[(summary == 2) & (water_boundary > 0)] = 4
    source_quality = np.zeros_like(summary)
    used_bodies: set[int] = set()
    tiles = []
    diagnostics = Counter()
    region_reports = []
    with ExitStack() as stack:
        main = stack.enter_context(rasterio.open(atlas.TEMP / "dem_20m.tif"))
        penghu = stack.enter_context(rasterio.open(atlas.TEMP / "phDEM_20m_121.tif"))
        cop_doc, cop_sources = atlas.copernicus_sources(stack)
        fixed_sources = FixedSourceReader(main, penghu, cop_sources)
        for ry in range(south, north):
            if time.monotonic() > deadline:
                raise TimeoutError("r4 atlas build exceeded 3600 seconds")
            for rx in range(west, east):
                if only_region is not None and (rx, ry) != only_region:
                    continue
                site_row, site_col = (north - 1 - ry) * 100, (rx - west) * 100
                local_scope = scope[site_row:site_row + 100, site_col:site_col + 100]
                local_summary = summary[site_row:site_row + 100, site_col:site_col + 100]
                active_sites = (local_scope >= 1) & (local_scope <= 4)
                if not np.any(active_sites & (local_summary != 1)):
                    continue
                e0, n0 = rx * atlas.REGION_M, ry * atlas.REGION_M
                side = POSTS + 2 * EST_HALO
                rect = box(e0 - EST_HALO * atlas.SAMPLE_M,
                           n0 - EST_HALO * atlas.SAMPLE_M,
                           e0 + atlas.REGION_M + EST_HALO * atlas.SAMPLE_M,
                           n0 + atlas.REGION_M + EST_HALO * atlas.SAMPLE_M)
                matrix = from_origin(rect.bounds[0], rect.bounds[3],
                                     atlas.SAMPLE_M, atlas.SAMPLE_M)
                # STRtree indexes keep polygon identity stable across Regions.
                pairs = [(polygons[int(i)], int(i) + 1) for i in sorted(land_tree.query(rect))]
                center = rasterize(pairs, out_shape=(side, side), transform=matrix,
                                   fill=0, dtype="uint16")
                touched = rasterize(pairs, out_shape=(side, side), transform=matrix,
                                    fill=0, dtype="uint16", all_touched=True)
                active = active_posts(scope, rx, ry, bounds, EST_HALO)
                center[~active] = 0
                touched[~active] = 0
                components, support = support_components(center, touched)
                if not np.any(components[EST_HALO:-EST_HALO, EST_HALO:-EST_HALO]):
                    continue
                raw, cop, wbm = fixed_sources.window(rx, ry, EST_HALO)
                height_halo, quality_halo, method_halo, distance_halo, methods = estimate_posts(
                    raw, components, support, cop, wbm)
                diagnostics.update({f"method_{key}": value for key, value in methods.items()})
                core = np.s_[EST_HALO:EST_HALO + POSTS, EST_HALO:EST_HALO + POSTS]
                height = height_halo[core].copy()
                quality = quality_halo[core].copy()
                method = method_halo[core].copy()
                distance = distance_halo[core].copy()
                center_core = center[core]
                local_water_shapes = water_shapes(water_tree, water, water_ids, rect)
                bodies_halo = rasterize(local_water_shapes, out_shape=(side, side),
                                        transform=matrix, fill=0, dtype="uint32")
                source_water_halo = kind_by_body[np.where(center == 0, 1, bodies_halo)]
                bodies = bodies_halo[core].copy()
                bodies[center_core == 0] = 1
                bodies[(center_core != 0) & (bodies == 1)] = 1
                water_kind = kind_by_body[bodies]
                used_bodies.update(int(body) for body in np.unique(bodies) if body > 1)
                # The 200m neighbourhood rule is unchanged; only its documented
                # source surface may now contain explicit quality-2..4 estimates.
                level_input = height_halo[EST_HALO - atlas.LEVEL_RADIUS:
                                          EST_HALO + POSTS + atlas.LEVEL_RADIUS,
                                          EST_HALO - atlas.LEVEL_RADIUS:
                                          EST_HALO + POSTS + atlas.LEVEL_RADIUS]
                levels = atlas.local_levels(level_input)
                levels[(water_kind == 2) & (quality == 0)] = 0
                unresolved = (water_kind != 2) & (height == NODATA)
                water_kind[unresolved] = 255
                levels[unresolved] = 255
                diagnostics["unresolved_core_posts"] += int(unresolved.sum())
                quality_neighbourhood = quality_halo[
                    EST_HALO - 1:EST_HALO + POSTS + 1,
                    EST_HALO - 1:EST_HALO + POSTS + 1]
                quality_sites = np.lib.stride_tricks.sliding_window_view(
                    quality_neighbourhood, (12, 12))[::10, ::10].max(axis=(-2, -1))
                local_quality = source_quality[site_row:site_row + 100,
                                               site_col:site_col + 100]
                local_quality[:] = quality_sites
                per_site_bad = unresolved.reshape(100, 10, 100, 10).any(axis=(1, 3))
                local_summary[per_site_bad & active_sites & (local_summary != 1)] = 0
                all_fresh = ((water_kind != 0) & (water_kind != 2) &
                             (water_kind != 255)).reshape(100, 10, 100, 10).all(axis=(1, 3))
                local_summary[all_fresh & (local_summary == 2)] = 3
                code = f"r{rx}_{ry}"
                height_record = save(OUT / "tiles" / f"{code}.height.i16.z",
                                     zlib.compress(height.astype("<i2").tobytes(), 6))
                level_record = save(OUT / "tiles" / f"{code}.level.u8.z",
                                    zlib.compress(levels.tobytes(), 6))
                water_record = save(OUT / "tiles" / f"{code}.water.u8.z",
                                    zlib.compress(water_kind.tobytes(), 6))
                quality_record = save(OUT / "tiles" / f"{code}.quality.u8.z",
                                      zlib.compress(quality.tobytes(), 6))
                body_record = save(OUT / "tiles" / f"{code}.body.u32.z",
                                   zlib.compress(bodies.astype("<u4").tobytes(), 6))
                method_record = save(OUT / "tiles" / f"{code}.method.u8.z",
                                     zlib.compress(method.tobytes(), 6))
                distance_record = save(OUT / "tiles" / f"{code}.distance.u16.z",
                                       zlib.compress(distance.astype("<u2").tobytes(), 6))
                derived = {
                    "encoding": "u8_zlib",
                    "levels_path": level_record["path"], "levels_sha256": level_record["sha256"],
                    "water_path": water_record["path"], "water_sha256": water_record["sha256"],
                    "quality_path": quality_record["path"], "quality_sha256": quality_record["sha256"],
                    "water_body_path": body_record["path"], "water_body_sha256": body_record["sha256"],
                    "water_body_encoding": "u32_le_zlib",
                    "method_path": method_record["path"], "method_sha256": method_record["sha256"],
                    "support_distance_path": distance_record["path"],
                    "support_distance_sha256": distance_record["sha256"],
                }
                candidates = ((local_summary == 4) | (water_boundary[
                    site_row:site_row + 100, site_col:site_col + 100] > 0)) & active_sites
                detail, visible, fine_quality = fine_bank(
                    rx, ry, candidates, land_tree, polygons, water_tree, water,
                    water_ids, used_bodies, bodies, quality_halo,
                    height_halo, source_water_halo)
                np.maximum(local_quality, fine_quality, out=local_quality)
                if detail is not None:
                    derived["water_detail"] = detail
                    diagnostics["fine_mask_sites"] += int(len(json.loads(
                        (OUT / detail["index_path"]).read_text(encoding="utf-8"))))
                diagnostics["visible_land_boundary_sites"] += visible
                tiles.append({"id": code, "origin": [e0, n0], "size": [POSTS, POSTS],
                              "spacing_m": atlas.SAMPLE_M, "encoding": "int16_le_zlib",
                              "row_order": "north_to_south", "nodata": NODATA,
                              **height_record, "derived": derived})
                region_reports.append({"region": [rx, ry], "unresolved_posts": int(unresolved.sum()),
                                       "estimated_posts": int(np.count_nonzero((quality >= 2) & (water_kind != 2))),
                                       "fine_mask_sites": int(detail is not None and len(json.loads(
                                           (OUT / detail["index_path"]).read_text(encoding="utf-8"))))})
            print(f"r4 Region row {ry}/{north - 1}: {len(tiles)} tiles; "
                  f"elapsed={time.monotonic() - start:.1f}s", flush=True)
        diagnostics["cop_overlap_conflicts"] = sum(fixed_sources.cop_conflicts.values())
        diagnostics["r2_dry_MOI_posts_pinned_from_window_ties"] = sum(
            fixed_sources.r2_pinned_changed.values())
    metadata = []
    for name in ("provenance.json", "LICENSE-ODbL-1.0.html",
                 "Geofabrik-README.txt", "README.md"):
        metadata.append(save(OUT / "source_metadata" / name,
                             (SOURCE / name).read_bytes()))
    # Full Site gate, including 12x12 interpolation halo and adjacent sea rule,
    # is checked by the independent r4 audit before this candidate is promoted.
    summary[(scope >= 1) & (scope <= 4) & (summary == 2) & (source_quality == 0)] = 0
    external_retention = retain_external_background(summary, scope)
    # A source post may support a neighbouring 2 m shore while this entire
    # Site is mapped ocean; public Site quality describes its sea surface.
    source_quality[summary == 1] = 0
    source_quality[scope == 0] = 0
    summary_record = save(OUT / "summary.u8", summary.tobytes())
    scope_record = save(OUT / "content_scope.u8", scope.tobytes())
    quality_record = save(OUT / "source_quality.u8", source_quality.tobytes())
    body_registry = [body_data[i] for i in sorted(used_bodies) if i in body_data]
    manifest = {
        "format": 1, "atlas_id": atlas.ATLAS, "grid_contract_version": 1,
        "crs": "EPSG:3826", "base_revision": REVISION,
        "grid": {"origin": [0, 0], "cell_m": 2, "site_cells": 100, "region_sites": 100},
        "summary": {**summary_record, "site_origin": [west * 100, south * 100],
                    "size": list(summary.shape[::-1]), "encoding": "u8",
                    "row_order": "north_to_south", "nodata": 0},
        "content_scope": {**scope_record, "site_origin": [west * 100, south * 100],
                          "size": list(scope.shape[::-1]), "encoding": "u8",
                          "row_order": "north_to_south"},
        "source_quality": {**quality_record, "site_origin": [west * 100, south * 100],
                           "size": list(summary.shape[::-1]), "encoding": "u8",
                           "row_order": "north_to_south"},
        "source_quality_codes": {"0": "sea_or_missing", "1": "measured_MOI",
                                 "2": "local_MOI_interpolation",
                                 "3": "local_MOI_extrapolation",
                                 "4": "explicit_estimate_unknown_vertical_accuracy"},
        "source_quality_rule": "worst_public_2m_contributor_including_water_height_support",
        "water_bodies": body_registry, "elevation_tiles": tiles,
        "sea_surface_rule": {"source": "osm_coast_20260927", "summary_class": 1,
                             "gameplay_level": 0, "whole_site_verified": True},
        "terrain_rule": {"method": "available_land_and_marked_coast_support_box_mean_residual",
                         "coast_support_in_background": True, "radius_m": 200,
                         "base_level": 2, "meters_per_level": 16,
                         "rounding": "numpy_rint_even", "clamp": [0, 5],
                         "source_spacing_m": 20, "interpretation": "gameplay tier, not measured 2m elevation"},
        "quality": "20m MOI measurements plus explicitly marked estimates; 2m vector raster is a gameplay classification",
        "source_post_rule": {"method": "fixed_20km_global_core_then_join_halo",
                             "r2_valid_dry_posts": "pinned_from_r2_manifest",
                             "r2_manifest_sha256": R2_MANIFEST_SHA},
        "attribution": "© OpenStreetMap contributors (ODbL 1.0); MOI 20m DTM (Taiwan Open Government Data License 1.0); Copernicus DEM (adapted terrain estimates); GSHHG external land (LGPL)",
        "max_measured_projection_scale_error": atlas.projection_error(),
        "horizontal_scale_error_limit": .001,
        "preview_sites": r4_preview_sites(),
        "content_scope_selection": scope_selection,
        "summary_counts": {name: int(np.count_nonzero(summary == code)) for code, name in
                           enumerate(("missing_data", "sea", "land", "inland_water", "mixed"))},
        "build_diagnostics": {**dict(diagnostics), "r2_scope_sites_preserved": kept_r2_scope},
        "external_background_retention": external_retention,
        "source_metadata": metadata,
        "estimate_method_codes": {str(k): value for k, value in METHODS.items()},
        "sources": [
            {"id": "moi_dtm_35430", "url": atlas.SOURCE_LINKS["moi_dtm"],
             "sha256": atlas.DEM_SHA, "vertical_datum": "TWVD2001",
             "license": "Taiwan Open Government Data License 1.0"},
            {"id": "osm_coast_20260927", "url": provenance["inputs"][1]["url"],
             "sha256": atlas.sha256(SOURCE / "land.geojson"), "license": "ODbL-1.0",
             "source_timestamp": provenance["osm_base_timestamp"],
             "geometry_rule": "closed original OSM node rings; no bbox closure"},
            {"id": "osm_water_20260927", "url": provenance["inputs"][0]["url"],
             "sha256": atlas.sha256(SOURCE / "inland_water.geojson"),
             "license": "ODbL-1.0", "source_timestamp": provenance["osm_base_timestamp"]},
            {"id": "copernicus_glo30_2021_relative_shape", "license_url": cop_doc["license_url"],
             "adapted_notice": cop_doc["adapted_notice"], "vertical_datum": "EGM2008",
             "usage": "quality4 relative shape only; never unmarked measured MOI",
             "tiles": cop_doc["tiles"]},
            {"id": "gshhg_2_3_7_external_only", "url": atlas.SOURCE_LINKS["gshhg"],
             "sha256": atlas.COAST_SHA, "license": "LGPL",
             "usage": "background external-content land only"},
        ],
    }
    manifest_path = OUT / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, separators=(",", ":")) + "\n",
                             encoding="utf-8")
    report = {"status": "r4_region_sample" if only_region else "r4_isolated_candidate_needs_independent_audit",
              "r2_manifest_sha256": atlas.sha256(atlas.OUT / "manifest.json"),
              "r4_manifest_sha256": atlas.sha256(manifest_path),
              "source_files": {name: atlas.sha256(SOURCE / name) for name in SOURCE_FILES},
              "region_reports": region_reports, "counts": dict(diagnostics),
              "summary_counts": manifest["summary_counts"],
              "external_background_retention": external_retention,
              "active_missing_sites": {NAMES[code]: int(np.count_nonzero((scope == code) &
                                          (summary == 0))) for code in range(1, 5)},
              "package_bytes": 0,
              "elapsed_seconds": time.monotonic() - start}
    write_coverage_report(report)
    print("r4 candidate", manifest_path, report["active_missing_sites"],
          "bytes", report["package_bytes"], flush=True)


def finalize_existing() -> None:
    """Apply presentation-only fixes to a completed r4 build, retaining tile hashes."""
    manifest_path = OUT / "manifest.json"
    report_path = OUT / "coverage_report.json"
    if not manifest_path.is_file() or not report_path.is_file():
        raise FileNotFoundError("Complete r4 manifest and coverage report required")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if report.get("status") != "r4_isolated_candidate_needs_independent_audit":
        raise ValueError("Only completed isolated candidates may be finalized")
    summary = np.frombuffer((OUT / manifest["summary"]["path"]).read_bytes(), dtype="u1").copy()
    quality = np.frombuffer((OUT / manifest["source_quality"]["path"]).read_bytes(), dtype="u1").copy()
    if summary.size != quality.size:
        raise ValueError("Summary and source quality differ in length")
    scope = np.frombuffer((OUT / manifest["content_scope"]["path"]).read_bytes(),
                          dtype="u1").copy()
    if scope.size != summary.size:
        raise ValueError("Summary and content scope differ in length")
    shape = (int(manifest["summary"]["size"][1]), int(manifest["summary"]["size"][0]))
    external_retention = retain_external_background(summary.reshape(shape),
                                                    scope.reshape(shape))
    summary_record = save(OUT / manifest["summary"]["path"], summary.tobytes())
    manifest["summary"]["sha256"] = summary_record["sha256"]
    scope_record = save(OUT / manifest["content_scope"]["path"], scope.tobytes())
    manifest["content_scope"]["sha256"] = scope_record["sha256"]
    quality[summary == 1] = 0
    quality[scope == 0] = 0
    quality_record = save(OUT / manifest["source_quality"]["path"], quality.tobytes())
    manifest["source_quality"]["sha256"] = quality_record["sha256"]
    manifest["preview_sites"] = r4_preview_sites()
    manifest["summary_counts"] = {name: int(np.count_nonzero(summary == code)) for code, name in
                                  enumerate(("missing_data", "sea", "land", "inland_water", "mixed"))}
    manifest["external_background_retention"] = external_retention
    manifest["attribution"] = ("© OpenStreetMap contributors (ODbL 1.0); MOI 20m DTM "
                               "(Taiwan Open Government Data License 1.0); Copernicus DEM "
                               "(adapted terrain estimates); GSHHG external land (LGPL)")
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False,
                                        separators=(",", ":")) + "\n", encoding="utf-8")
    report["r4_manifest_sha256"] = atlas.sha256(manifest_path)
    report["summary_counts"] = manifest["summary_counts"]
    report["external_background_retention"] = external_retention
    report["build_attempts"] = [
        {"result": "stopped_before_timeout", "bound_seconds": 1200,
         "last_region_row": 125, "partial_tile_count": 24,
         "reason": "observed full-map rate required a longer explicit bounded run"},
        {"result": "completed", "bound_seconds": 3600,
         "elapsed_seconds": report["elapsed_seconds"]}]
    write_coverage_report(report)
    print(f"Finalized r4 manifest SHA256 {report['r4_manifest_sha256']}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--sample-region", help="Build one Region into the ignored .tmp/r4_sample directory")
    parser.add_argument("--finalize-existing", action="store_true",
                        help="Finalize a completed full candidate without rebuilding source tiles")
    args = parser.parse_args()
    if args.finalize_existing:
        finalize_existing()
        raise SystemExit(0)
    selected = None
    if args.sample_region:
        x, y = args.sample_region.split(",")
        selected = int(x), int(y)
        OUT = atlas.TEMP / "r4_sample"
    build(selected)
