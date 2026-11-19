"""Build the isolated Taiwan RegionLab atlas from pinned public GIS archives.

The archives are inputs, not runtime dependencies.  See README.md for their
URLs and SHA-256 values.  Generated binary rasters are north-to-south rows.
"""

from __future__ import annotations

import argparse
from contextlib import ExitStack
from functools import lru_cache
import hashlib
import json
import math
import shutil
import sys
import zipfile
import zlib
from pathlib import Path

import numpy as np
import rasterio
import shapefile
from pyproj import Geod, Transformer
from rasterio.enums import Resampling
from rasterio.features import rasterize
from rasterio.transform import from_origin
from rasterio.warp import reproject, transform_bounds
from shapely.geometry import Polygon, box
from shapely.geometry import Point
from shapely.ops import transform


ATLAS = "earth_tw_tm2_121_v1"
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "region_lab" / ATLAS
TRIAL_OUT = ROOT / "assets" / "region_lab" / f"{ATLAS}_r3_trial"
SOURCE = OUT / "source"
TEMP = Path(__file__).resolve().parent / ".tmp"
COP_INPUTS = Path(__file__).resolve().parent / "copernicus_inputs.json"
DEM_ARCHIVE = SOURCE / "moi_20m_taiwan_penghu_dem.zip"
COAST_ARCHIVE = SOURCE / "gshhg-shp-2.3.7.zip"
DEM_SHA = "66cd9ffc2da89982b530c4eca5d3d6f4ae295194dbec794259a55f5027ceaed9"
COAST_SHA = "8dbbe7e071e77e9e75f2d639239099ebca8d5c16d6a07df8169729d49f15cf41"
SOURCE_LINKS = {
    "moi_dtm": "https://www.tgos.tw/MDE/VirtualDir_TC/Product/9981ede9-584a-4470-8c5c-dbe579d4ecb4/%E4%B8%8D%E5%88%86%E5%B9%85_%E5%85%A8%E5%8F%B0%E5%8F%8A%E6%BE%8E%E6%B9%96DEM.zip",
    "gshhg": "https://github.com/GenericMappingTools/gshhg-gmt/releases/download/2.3.7/gshhg-shp-2.3.7.zip",
}
CELL_M = 2
SITE_M = 200
REGION_M = 20_000
SAMPLE_M = 20
SAMPLES_PER_REGION = REGION_M // SAMPLE_M
NODATA = -32767
LON_BOUNDS = (119.0, 122.5)
LAT_BOUNDS = (21.5, 25.5)
LEVEL_RADIUS = 10  # 200 m of source samples around every point, across Region boundaries.
LEVEL_METERS = 16.0
BASE_LEVEL = 2.0
BASE_REVISION = "moi-35430-gshhg-2.3.7-r2-scope-halo"
TRIAL_REVISION = "moi-35430-gshhg-2.3.7-copglo30-coast-r3-trial"


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify_source(path: Path, expected: str) -> None:
    if not path.is_file():
        raise FileNotFoundError(f"Missing pinned source {path}; download URL is in README.md")
    actual = sha256(path)
    if actual != expected:
        raise ValueError(f"Source hash mismatch: {path}: {actual}")


def extract_inputs() -> None:
    TEMP.mkdir(parents=True, exist_ok=True)
    for archive, suffixes in (
        (DEM_ARCHIVE, ("dem_20m.tif", "phDEM_20m_121.tif")),
        (COAST_ARCHIVE, tuple(f"GSHHS_f_L1.{ext}" for ext in ("shp", "shx", "dbf", "prj"))),
    ):
        with zipfile.ZipFile(archive) as z:
            for suffix in suffixes:
                found = next((name for name in z.namelist() if name.endswith("/" + suffix)), None)
                if found is None:
                    raise ValueError(f"{archive} lacks {suffix}")
                dst = TEMP / suffix
                if not dst.is_file() or dst.stat().st_size != z.getinfo(found).file_size:
                    with z.open(found) as src, dst.open("wb") as target:
                        shutil.copyfileobj(src, target)


def projected_bounds() -> tuple[int, int, int, int]:
    project = Transformer.from_crs("EPSG:4326", "EPSG:3826", always_xy=True)
    edge = []
    for i in range(101):
        t = i / 100.0
        edge.extend(((LON_BOUNDS[0] + t * (LON_BOUNDS[1] - LON_BOUNDS[0]), LAT_BOUNDS[0]),
                     (LON_BOUNDS[0] + t * (LON_BOUNDS[1] - LON_BOUNDS[0]), LAT_BOUNDS[1]),
                     (LON_BOUNDS[0], LAT_BOUNDS[0] + t * (LAT_BOUNDS[1] - LAT_BOUNDS[0])),
                     (LON_BOUNDS[1], LAT_BOUNDS[0] + t * (LAT_BOUNDS[1] - LAT_BOUNDS[0]))))
    points = [project.transform(*p) for p in edge]
    return (math.floor(min(p[0] for p in points) / REGION_M),
            math.ceil(max(p[0] for p in points) / REGION_M),
            math.floor(min(p[1] for p in points) / REGION_M),
            math.ceil(max(p[1] for p in points) / REGION_M))


def projection_error() -> float:
    inverse = Transformer.from_crs("EPSG:3826", "EPSG:4326", always_xy=True)
    geod = Geod(ellps="GRS80")
    west, east, south, north = projected_bounds()
    maximum = 0.0
    for e in np.linspace(west * REGION_M, east * REGION_M, 13):
        for n in np.linspace(south * REGION_M, north * REGION_M, 13):
            lon, lat = inverse.transform(e, n)
            for length, de, dn in ((SITE_M, SITE_M, 0), (SITE_M, 0, SITE_M),
                                    (REGION_M, REGION_M, 0), (REGION_M, 0, REGION_M)):
                end_lon, end_lat = inverse.transform(e + de, n + dn)
                _, _, measured = geod.inv(lon, lat, end_lon, end_lat)
                maximum = max(maximum, abs(measured - length) / length)
    return maximum


def land_polygons() -> list:
    west, east, south, north = projected_bounds()
    inverse = Transformer.from_crs("EPSG:3826", "EPSG:4326", always_xy=True)
    corners = [inverse.transform(e, n) for e in (west * REGION_M, east * REGION_M)
               for n in (south * REGION_M, north * REGION_M)]
    # The clipping window is larger than the atlas to preserve boundary lines.
    clip_lon = box(min(p[0] for p in corners) - .2, min(p[1] for p in corners) - .2,
                   max(p[0] for p in corners) + .2, max(p[1] for p in corners) + .2)
    reader = shapefile.Reader(str(TEMP / "GSHHS_f_L1.shp"))
    candidates = reader.iterShapes(bbox=list(clip_lon.bounds))
    project = Transformer.from_crs("EPSG:4326", "EPSG:3826", always_xy=True).transform
    atlas_rect = box(west * REGION_M, south * REGION_M, east * REGION_M, north * REGION_M)
    polygons = []
    for shape in candidates:
        if len(shape.parts) != 1:
            raise ValueError("Multipart shoreline needs per-part polygon handling")
        p = Polygon(shape.points)
        if not p.is_valid:
            p = p.buffer(0)
        cut = p.intersection(clip_lon)
        if not cut.is_empty:
            projected = transform(project, cut).intersection(atlas_rect)
            if not projected.is_empty:
                polygons.append(projected)
    if not polygons:
        raise ValueError("No shoreline polygons intersect the selected atlas")
    return polygons


def touching(polygons: list, rect) -> list:
    return [p for p in polygons if box(*p.bounds).intersects(rect)]


def coastal_summary(polygons: list, bounds: tuple[int, int, int, int]) -> np.ndarray:
    west, east, south, north = bounds
    width, height = (east - west) * 100, (north - south) * 100
    geometry = [(p, 1) for p in polygons]
    geo_transform = from_origin(west * REGION_M, north * REGION_M, SITE_M, SITE_M)
    land_touch = rasterize(geometry, out_shape=(height, width), transform=geo_transform,
                           fill=0, dtype="uint8", all_touched=True)
    shore_touch = rasterize([(p.boundary, 1) for p in polygons], out_shape=(height, width),
                            transform=geo_transform, fill=0, dtype="uint8", all_touched=True)
    summary = np.ones((height, width), dtype=np.uint8)
    summary[land_touch == 1] = 2
    summary[shore_touch == 1] = 4
    return summary


def content_scope(polygons: list, baseline: np.ndarray, bounds: tuple[int, int, int, int],
                  anchors: tuple | None = None) -> tuple[np.ndarray, dict]:
    """Select named island groups; untouched external land stays outside content."""
    project = Transformer.from_crs("EPSG:4326", "EPSG:3826", always_xy=True)
    if anchors is None:
        anchors = (("taiwan", 121.5654, 25.033, 20_000),
                   ("penghu", 119.56, 23.57, 35_000),
                   ("green_island", 121.492, 22.661, 10_000),
                   ("lanyu", 121.54, 22.05, 10_000))
    groups = []
    claimed = set()
    for name, lon, lat, near_m in anchors:
        e, n = project.transform(lon, lat)
        matches = [p for p in polygons if p.contains(Point(e, n))]
        if len(matches) != 1:
            raise ValueError(f"Expected one source island polygon at {name}, got {len(matches)}")
        body = matches[0]
        if id(body) in claimed:
            raise ValueError(f"Island anchor belongs to another content group: {name}")
        members = [p for p in polygons if id(p) not in claimed and
                   (p is body or p.distance(body) <= near_m)]
        claimed.update(id(p) for p in members)
        groups.append((name, [lon, lat], near_m, members))
    west, east, south, north = bounds
    scope = np.where(baseline == 1, 5, 0).astype(np.uint8)
    geo_transform = from_origin(west * REGION_M, north * REGION_M, SITE_M, SITE_M)
    scope_info = {}
    for code, (name, anchor, near_m, members) in enumerate(groups, start=1):
        footprints = rasterize([(p, 1) for p in members], out_shape=baseline.shape,
                               transform=geo_transform, fill=0, dtype="uint8", all_touched=True)
        occupied = footprints == 1
        if np.any((scope[occupied] != 0) & (scope[occupied] != 5)):
            raise ValueError(f"Named island Site footprints overlap: {name}")
        scope[occupied] = code
        scope_info[name] = {"code": code, "anchor_lonlat": anchor,
                            "nearby_islets_within_m": near_m,
                            "source_polygon_count": len(members),
                            "site_count": int(np.count_nonzero(occupied))}
    return scope, scope_info


def scope_gaps(baseline: np.ndarray, summary: np.ndarray, scope: np.ndarray) -> dict:
    result = {}
    for code, name in enumerate(("outside_content", "taiwan", "penghu", "green_island", "lanyu", "surrounding_sea")):
        area = scope == code
        result[name] = {"source_land": int(np.count_nonzero(area & (baseline == 2))),
                        "source_mixed": int(np.count_nonzero(area & (baseline == 4))),
                        "missing_land": int(np.count_nonzero(area & (baseline == 2) & (summary == 0))),
                        "missing_mixed": int(np.count_nonzero(area & (baseline == 4) & (summary == 0)))}
    return result


def nearshore_scope(scope: np.ndarray) -> np.ndarray:
    """Content assignment for at most 400 m of unclassified adjacent sea."""
    result = scope.copy()
    for _ in range(2):
        previous = result.copy()
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0:
                    continue
                sy0, sy1 = max(0, -dy), min(scope.shape[0], scope.shape[0] - dy)
                sx0, sx1 = max(0, -dx), min(scope.shape[1], scope.shape[1] - dx)
                source = previous[sy0:sy1, sx0:sx1]
                target = result[sy0 + dy:sy1 + dy, sx0 + dx:sx1 + dx]
                chosen = (target == 5) & (source >= 1) & (source <= 4)
                target[chosen] = source[chosen]
    return result


def copernicus_sources(stack: ExitStack) -> tuple[dict, list]:
    doc = json.loads(COP_INPUTS.read_text(encoding="utf-8"))
    sources = []
    for tile in doc["tiles"]:
        paths = []
        for key in ("dem", "water_body_mask"):
            record = tile[key]
            path = TEMP / record["filename"]
            verify_source(path, record["sha256"])
            if path.stat().st_size != record["bytes"]:
                raise ValueError(f"Copernicus source size mismatch: {path}")
            paths.append(path)
        dem = stack.enter_context(rasterio.open(paths[0]))
        water = stack.enter_context(rasterio.open(paths[1]))
        if dem.bounds != water.bounds or dem.transform != water.transform or dem.crs != water.crs:
            raise ValueError(f"Copernicus DEM/WBM grid mismatch: {tile['geocell']}")
        bounds = box(*transform_bounds(dem.crs, "EPSG:3826", *dem.bounds, densify_pts=21))
        sources.append((dem, water, bounds))
    return doc, sources


def copernicus_halo(sources: list, transform, shape: tuple[int, int], rect) -> tuple[np.ndarray, np.ndarray, int]:
    height = np.full(shape, np.nan, dtype=np.float32)
    water = np.full(shape, 255, dtype=np.uint8)
    conflicts = np.zeros(shape, dtype=np.bool_)
    for dem, wbm, bounds in sources:
        if not bounds.intersects(rect):
            continue
        candidate_height = np.full(shape, np.nan, dtype=np.float32)
        candidate_water = np.full(shape, 255, dtype=np.uint8)
        reproject(rasterio.band(dem, 1), candidate_height,
                  src_transform=dem.transform, src_crs=dem.crs,
                  dst_transform=transform, dst_crs="EPSG:3826", dst_nodata=np.nan,
                  resampling=Resampling.bilinear)
        reproject(rasterio.band(wbm, 1), candidate_water,
                  src_transform=wbm.transform, src_crs=wbm.crs,
                  dst_transform=transform, dst_crs="EPSG:3826", dst_nodata=255,
                  resampling=Resampling.nearest)
        valid = np.isfinite(candidate_height) & (candidate_water != 255)
        previous = np.isfinite(height) & (water != 255)
        both = valid & previous
        conflicts |= both & ((water != candidate_water) | (np.abs(height - candidate_height) > 5))
        fresh = valid & ~previous
        height[fresh] = candidate_height[fresh]
        water[fresh] = candidate_water[fresh]
    height[conflicts] = np.nan
    water[conflicts] = 255
    return height, water, int(np.count_nonzero(conflicts))


def coast_decisions(original_land: np.ndarray, moi: np.ndarray,
                    cop_height: np.ndarray, cop_water: np.ndarray,
                    nearby_scope: np.ndarray) -> np.ndarray:
    """Accept only MOI heights independently corroborated as land by COP-DEM."""
    candidate = (~original_land) & (moi > 2) & (nearby_scope >= 1) & (nearby_scope <= 4)
    decision = np.zeros(moi.shape, dtype=np.uint8)
    decision[candidate] = 6  # No Copernicus pair at this source post.
    decision[candidate & (cop_water == 1)] = 2  # Copernicus says ocean.
    decision[candidate & ((cop_water == 2) | (cop_water == 3))] = 3  # Inland water unresolved.
    ground = candidate & (cop_water == 0)
    decision[ground] = 4  # Copernicus height missing or nonpositive.
    comparable = ground & np.isfinite(cop_height) & (cop_height > 2)
    decision[comparable] = 5  # Vertical disagreement exceeds conservative bound.
    decision[comparable & (np.abs(cop_height - moi) <= 10)] = 1
    return decision


def source_dem(main, penghu, west: int, south: int, size: int = SAMPLES_PER_REGION,
               halo: int = 0) -> np.ndarray:
    count = size + 2 * halo
    pixel_west = west - halo * SAMPLE_M
    pixel_north = south + size * SAMPLE_M + halo * SAMPLE_M
    target = np.full((count, count), NODATA, dtype=np.int16)
    target_transform = from_origin(pixel_west, pixel_north, SAMPLE_M, SAMPLE_M)
    for dataset in (main, penghu):
        layer = np.full_like(target, NODATA)
        reproject(source=rasterio.band(dataset, 1), destination=layer,
                  src_transform=dataset.transform, src_crs=dataset.crs,
                  src_nodata=NODATA, dst_transform=target_transform,
                  dst_crs="EPSG:3826", dst_nodata=NODATA,
                  resampling=Resampling.nearest,
                  init_dest_nodata=True, num_threads=2)
        valid = layer != NODATA
        conflict = valid & (target != NODATA) & (target != layer)
        if np.any(conflict):
            raise ValueError("Official DEM sources conflict in overlapping cells")
        target[valid] = layer[valid]
    return target


def local_levels(elevation_halo: np.ndarray) -> np.ndarray:
    r = LEVEL_RADIUS
    side = 2 * r + 1
    valid = elevation_halo != NODATA
    values = np.where(valid, elevation_halo, 0).astype(np.int64)
    counts = valid.astype(np.int64)

    def box_sum(a: np.ndarray) -> np.ndarray:
        integral = np.pad(a.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
        return (integral[side:, side:] - integral[:-side, side:]
                - integral[side:, :-side] + integral[:-side, :-side])

    baseline = box_sum(values) / np.maximum(box_sum(counts), 1)
    core = elevation_halo[r:-r, r:-r]
    levels = np.clip(np.rint(BASE_LEVEL + (core.astype(np.float64) - baseline) / LEVEL_METERS),
                     0, 5).astype(np.uint8)
    levels[core == NODATA] = 255
    return levels


def save_bytes(path: Path, data: bytes) -> dict:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return {"path": path.relative_to(OUT).as_posix(), "sha256": sha256(path)}


def preview_sites() -> list[dict]:
    project = Transformer.from_crs("EPSG:4326", "EPSG:3826", always_xy=True)
    examples = (("Taipei", 121.5654, 25.033), ("Yushan", 120.9575, 23.47),
                ("East coast", 121.6260497547, 23.9921927053), ("Penghu", 119.56, 23.57),
                ("Green Island", 121.492, 22.661), ("Lanyu", 121.54, 22.05))
    result = []
    for label, lon, lat in examples:
        e, n = project.transform(lon, lat)
        result.append({"label": label, "category": "mountain" if label == "Yushan" else "geography",
                       "lonlat": [lon, lat],
                       "site": [math.floor(e / SITE_M), math.floor(n / SITE_M)]})
    return result


def reject_incomplete_halos(summary: np.ndarray, tiles: list[dict], bounds: tuple[int, int, int, int]) -> dict:
    """Require every 20m source post touched by the 102x102 two-metre Site."""
    west, east, south, north = bounds
    indexed = {(tile["origin"][0] // REGION_M, tile["origin"][1] // REGION_M): tile for tile in tiles}

    @lru_cache(maxsize=9)
    def valid_tile(rx: int, ry: int):
        tile = indexed.get((rx, ry))
        if tile is None:
            return None
        elevation = np.frombuffer(zlib.decompress((OUT / tile["path"]).read_bytes()),
                                  dtype="<i2").reshape(1000, 1000)
        derived = tile["derived"]
        level = np.frombuffer(zlib.decompress((OUT / derived["levels_path"]).read_bytes()),
                              dtype=np.uint8).reshape(1000, 1000)
        water = np.frombuffer(zlib.decompress((OUT / derived["water_path"]).read_bytes()),
                              dtype=np.uint8).reshape(1000, 1000)
        if np.any((water != 0) & (water != 2) & (water != 255)) or np.any((level > 5) & (level != 255)):
            raise ValueError(f"Unsupported fixed water or gameplay level in {tile['id']}")
        return (water == 2) | ((water == 0) & (elevation != NODATA) & (level <= 5))

    def valid_at(rx: int, ry: int, row: int, column: int) -> bool:
        gx = rx * 1000 + column
        gy = ry * 1000 + 999 - row
        source_rx, source_ry = gx // 1000, gy // 1000
        source = valid_tile(source_rx, source_ry)
        if source is not None:
            return bool(source[999 - (gy - source_ry * 1000), gx - source_rx * 1000])
        sx, sy = gx // 10, gy // 10
        sc, sr = sx - west * 100, (north * 100 - 1) - sy
        return 0 <= sr < summary.shape[0] and 0 <= sc < summary.shape[1] and summary[sr, sc] == 1

    rejected = {"land": 0, "mixed": 0}
    for (rx, ry), _tile in indexed.items():
        core = valid_tile(rx, ry)
        expanded = np.empty((1002, 1002), dtype=np.bool_)
        expanded[1:-1, 1:-1] = core
        for x in range(1002):
            expanded[0, x] = valid_at(rx, ry, -1, x - 1)
            expanded[-1, x] = valid_at(rx, ry, 1000, x - 1)
        for y in range(1, 1001):
            expanded[y, 0] = valid_at(rx, ry, y - 1, -1)
            expanded[y, -1] = valid_at(rx, ry, y - 1, 1000)
        bad = (~expanded).astype(np.int32)
        integral = np.pad(bad.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
        windows = (integral[12:, 12:] - integral[:-12, 12:] -
                   integral[12:, :-12] + integral[:-12, :-12])[::10, ::10]
        if windows.shape != (100, 100):
            raise ValueError("Invalid 12x12 source-post Site window")
        row, col = (north - 1 - ry) * 100, (rx - west) * 100
        region = summary[row:row + 100, col:col + 100]
        for code, label in ((2, "land"), (4, "mixed")):
            failed = (region == code) & (windows != 0)
            rejected[label] += int(np.count_nonzero(failed))
            region[failed] = 0
    return rejected


def build(coast_evidence: bool = False) -> None:
    verify_source(DEM_ARCHIVE, DEM_SHA)
    verify_source(COAST_ARCHIVE, COAST_SHA)
    extract_inputs()
    distortion = projection_error()
    if distortion > .001:
        raise ValueError(f"Projection error {distortion:.6%} exceeds 0.1%")
    bounds = projected_bounds()
    west, east, south, north = bounds
    polygons = land_polygons()
    baseline = coastal_summary(polygons, bounds)
    summary = baseline.copy()
    scope, scope_info = content_scope(polygons, baseline, bounds)
    nearby_scope = nearshore_scope(scope) if coast_evidence else None
    nearby_padded = np.pad(nearby_scope, 1, constant_values=0) if coast_evidence else None
    available = np.zeros_like(summary, dtype=np.bool_)
    conflicts = np.zeros_like(summary, dtype=np.bool_)
    tiles = []
    coast_counts = np.zeros(7, dtype=np.int64)
    cop_source_conflicts = 0
    promoted_sites = 0
    with ExitStack() as stack:
        main = stack.enter_context(rasterio.open(TEMP / "dem_20m.tif"))
        penghu = stack.enter_context(rasterio.open(TEMP / "phDEM_20m_121.tif"))
        cop_doc, cop_sources = copernicus_sources(stack) if coast_evidence else ({}, [])
        for ry in range(south, north):
            for rx in range(west, east):
                tile_rect = box(rx * REGION_M, ry * REGION_M,
                                (rx + 1) * REGION_M, (ry + 1) * REGION_M)
                # An all-ocean Region does not need a detailed tile.
                if not touching(polygons, tile_rect):
                    continue
                source_halo = source_dem(main, penghu, rx * REGION_M, ry * REGION_M,
                                         halo=LEVEL_RADIUS)
                source_core = source_halo[LEVEL_RADIUS:-LEVEL_RADIUS,
                                          LEVEL_RADIUS:-LEVEL_RADIUS]
                if not np.any(source_core != NODATA):
                    continue
                halo_rect = box(rx * REGION_M - LEVEL_RADIUS * SAMPLE_M,
                                ry * REGION_M - LEVEL_RADIUS * SAMPLE_M,
                                (rx + 1) * REGION_M + LEVEL_RADIUS * SAMPLE_M,
                                (ry + 1) * REGION_M + LEVEL_RADIUS * SAMPLE_M)
                local_polygons = touching(polygons, halo_rect)
                halo_transform = from_origin(rx * REGION_M - LEVEL_RADIUS * SAMPLE_M,
                                             (ry + 1) * REGION_M + LEVEL_RADIUS * SAMPLE_M,
                                             SAMPLE_M, SAMPLE_M)
                land_halo = rasterize([(p, 1) for p in local_polygons],
                                      out_shape=source_halo.shape, transform=halo_transform,
                                   fill=0, dtype="uint8")
                coast_decision = np.zeros(source_halo.shape, dtype=np.uint8)
                if coast_evidence:
                    sr, sc = (north - 1 - ry) * 100, (rx - west) * 100
                    scope_sites = nearby_padded[sr:sr + 102, sc:sc + 102]
                    if scope_sites.shape != (102, 102):
                        raise ValueError("Trial nearshore Site scope lacks Region halo")
                    if np.any((scope_sites >= 1) & (scope_sites <= 4)):
                        scope_halo = np.repeat(np.repeat(scope_sites, 10, axis=0), 10, axis=1)
                        cop_height, cop_water, overlap_count = copernicus_halo(
                            cop_sources, halo_transform, source_halo.shape, halo_rect)
                        cop_source_conflicts += overlap_count
                        coast_decision = coast_decisions(land_halo == 1, source_halo,
                                                         cop_height, cop_water, scope_halo)
                        land_halo[coast_decision == 1] = 1
                land20 = land_halo[LEVEL_RADIUS:-LEVEL_RADIUS,
                                    LEVEL_RADIUS:-LEVEL_RADIUS]
                decision20 = coast_decision[LEVEL_RADIUS:-LEVEL_RADIUS,
                                            LEVEL_RADIUS:-LEVEL_RADIUS]
                region_row = (north - 1 - ry) * 100
                region_col = (rx - west) * 100
                site_summary = summary[region_row:region_row + 100, region_col:region_col + 100]
                site_avail = available[region_row:region_row + 100, region_col:region_col + 100]
                site_conflict = conflicts[region_row:region_row + 100, region_col:region_col + 100]
                if coast_evidence:
                    accepted_sites = (decision20 == 1).reshape(100, 10, 100, 10).any(axis=(1, 3))
                    promote = accepted_sites & (site_summary == 1)
                    nearby_sites = nearby_scope[region_row:region_row + 100,
                                                region_col:region_col + 100]
                    site_scope = scope[region_row:region_row + 100, region_col:region_col + 100]
                    if np.any(promote & ((nearby_sites < 1) | (nearby_sites > 4))):
                        raise ValueError("Coast repair has no named content island")
                    site_scope[promote] = nearby_sites[promote]
                    promoted_sites += int(np.count_nonzero(promote))
                    # Keep the original whole-sea test for any still-disputed posts.
                    whole_sea_site = site_summary == 1
                    site_summary[promote] = 4
                    coast_counts += np.bincount(decision20.ravel(), minlength=7)[:7]
                else:
                    whole_sea_site = site_summary == 1
                # The official DEM contains many zero-valued ocean pixels.  The
                # shoreline is authoritative for sea; ocean has no DEM altitude.
                elevation_halo = np.where(land_halo == 1, source_halo, NODATA).astype(np.int16)
                elevation = elevation_halo[LEVEL_RADIUS:-LEVEL_RADIUS,
                                            LEVEL_RADIUS:-LEVEL_RADIUS]
                water = np.where(land20 == 0, 2, 0).astype(np.uint8)
                water[(land20 == 1) & (elevation == NODATA)] = 255
                # Positive terrain in GSHHG ocean can indicate a missed island or
                # incompatible shoreline epoch.  A mixed coastal Site already
                # has an explicit shoreline, so its sea pixels use that source.
                whole_sea = np.repeat(np.repeat(whole_sea_site, 10, axis=0), 10, axis=1)
                sea_conflict = (land20 == 0) & (source_core > 2) & whole_sea
                water[sea_conflict] = 255
                levels = local_levels(elevation_halo)
                levels[water == 2] = 0
                levels[water == 255] = 255
                by_site_height = (elevation != NODATA).reshape(100, 10, 100, 10).any(axis=(1, 3))
                by_site_land_gap = ((land20 == 1) & (elevation == NODATA)).reshape(100, 10, 100, 10).any(axis=(1, 3))
                site_avail[:] = by_site_height & ~by_site_land_gap
                site_conflict[:] = sea_conflict.reshape(100, 10, 100, 10).any(axis=(1, 3))
                # Regions where the 2017 shoreline and DTM disagree remain inspectable,
                # but cannot be certified as wholly ocean.
                site_summary[site_conflict & (site_summary == 1)] = 0
                code = f"r{rx}_{ry}"
                height_record = save_bytes(OUT / "tiles" / f"{code}.height.i16.z",
                                           zlib.compress(elevation.astype('<i2').tobytes(), 6))
                level_record = save_bytes(OUT / "tiles" / f"{code}.level.u8.z",
                                          zlib.compress(levels.tobytes(), 6))
                water_record = save_bytes(OUT / "tiles" / f"{code}.water.u8.z",
                                          zlib.compress(water.tobytes(), 6))
                derived = {"encoding": "u8_zlib",
                           "levels_path": level_record["path"],
                           "levels_sha256": level_record["sha256"],
                           "water_path": water_record["path"],
                           "water_sha256": water_record["sha256"]}
                if coast_evidence:
                    decision_record = save_bytes(OUT / "tiles" / f"{code}.coast_decision.u8.z",
                                                 zlib.compress(decision20.tobytes(), 6))
                    derived.update({"coast_decision_path": decision_record["path"],
                                    "coast_decision_sha256": decision_record["sha256"]})
                tiles.append({"id": code, "origin": [rx * REGION_M, ry * REGION_M],
                              "size": [SAMPLES_PER_REGION, SAMPLES_PER_REGION],
                              "spacing_m": SAMPLE_M, "encoding": "int16_le_zlib",
                              "row_order": "north_to_south", "nodata": NODATA,
                              **height_record, "derived": derived})
            print(f"Region row {ry} / {north - 1}: {len(tiles)} elevation tiles", flush=True)

    # Terrain absent on GSHHG land is Missing, never relabelled as ocean.
    summary[((summary == 2) | (summary == 4)) & ~available] = 0
    summary[conflicts] = 0
    interior_counts = {name: int(np.count_nonzero(summary == code)) for code, name in
                       enumerate(("missing_data", "sea", "land", "inland_water", "mixed"))}
    interior_gaps_by_scope = scope_gaps(baseline, summary, scope)
    halo_rejected = reject_incomplete_halos(summary, tiles, bounds)
    summary_record = save_bytes(OUT / "summary.u8", summary.tobytes())
    scope_record = save_bytes(OUT / "content_scope.u8", scope.tobytes())
    if coast_evidence:
        for item in scope_info.values():
            item["source_polygon_site_count"] = item["site_count"]
            item["site_count"] = int(np.count_nonzero(scope == item["code"]))
    counts = {name: int(np.count_nonzero(summary == code)) for code, name in
              enumerate(("missing_data", "sea", "land", "inland_water", "mixed"))}
    manifest = {
        "format": 1, "atlas_id": ATLAS, "grid_contract_version": 1,
        "crs": "EPSG:3826", "base_revision": BASE_REVISION,
        "grid": {"origin": [0, 0], "cell_m": CELL_M, "site_cells": 100,
                 "region_sites": 100},
        "geographic_input_bbox_lonlat": [*LON_BOUNDS, *LAT_BOUNDS],
        "aligned_region_bounds_half_open": [west, south, east, north],
        "summary": {**summary_record, "site_origin": [west * 100, south * 100],
                    "size": list(summary.shape[::-1]), "encoding": "u8",
                    "row_order": "north_to_south", "nodata": 0},
        "content_scope": {**scope_record, "site_origin": [west * 100, south * 100],
                          "size": list(scope.shape[::-1]), "encoding": "u8",
                          "row_order": "north_to_south"},
        "content_scope_codes": {"0": "outside_content", "1": "taiwan",
                                "2": "penghu", "3": "green_island", "4": "lanyu",
                                "5": "surrounding_sea"},
        "content_scope_selection": scope_info,
        "summary_counts": counts,
        "build_diagnostics": {"interior_summary_counts_before_halo_gate": interior_counts,
                              "interior_gaps_by_scope": interior_gaps_by_scope,
                              "halo_rejected_sites": halo_rejected},
        "elevation_tiles": tiles,
        "sea_surface_rule": {"source": "gshhg_2_3_7_full_l1", "summary_class": 1,
                             "gameplay_level": 0, "whole_site_verified": True},
        "terrain_rule": {"method": "land_valid_box_mean_residual",
                         "radius_m": LEVEL_RADIUS * SAMPLE_M,
                         "base_level": BASE_LEVEL, "meters_per_level": LEVEL_METERS,
                         "rounding": "numpy_rint_even", "clamp": [0, 5],
                         "source_spacing_m": SAMPLE_M,
                         "interpretation": "gameplay tier; not absolute elevation"},
        "max_measured_projection_scale_error": distortion,
        "horizontal_scale_error_limit": .001,
        "preview_sites": preview_sites(),
        "quality": "source_limited; 20m elevation is not 2m measurement precision",
        "sources": [
            {"id": "moi_dtm_35430", "provider": "Ministry of the Interior Department of Land Administration",
             "title": "20m Taiwan and Penghu digital elevation model",
             "dataset_url": "https://data.gov.tw/dataset/35430",
             "url": SOURCE_LINKS["moi_dtm"], "sha256": DEM_SHA,
             "license": "Taiwan Open Government Data License 1.0",
             "license_url": "https://data.gov.tw/license",
             "horizontal_datum": "TWD97 in dataset header; GeoTIFF is WGS84/GRS80-like TM121",
             "vertical_datum": "TWVD2001 in dataset header",
             "spacing_m": 20, "nodata": NODATA,
             "coverage": "Taiwan mainland, Penghu, Green Island and Lanyu valid samples checked; varies per image"},
            {"id": "gshhg_2_3_7_full_l1", "provider": "SOEST University of Hawaii and NOAA",
             "title": "GSHHG 2.3.7 full-resolution L1 shoreline polygons",
             "url": SOURCE_LINKS["gshhg"], "sha256": COAST_SHA,
             "license": "GNU Lesser General Public License",
             "license_url": "https://www.gnu.org/licenses/lgpl-3.0.html",
             "horizontal_datum": "WGS84", "year": 2017,
             "coverage": "Global shoreline clipped to aligned Taiwan atlas; source date differs from DTM"},
        ],
    }
    if coast_evidence:
        manifest["build_diagnostics"]["coast_decision_post_counts"] = {
            str(i): int(value) for i, value in enumerate(coast_counts)}
        manifest["build_diagnostics"]["cop_geocell_overlap_conflict_posts"] = cop_source_conflicts
        manifest["build_diagnostics"]["promoted_gshhg_sea_sites"] = promoted_sites
        manifest["coast_evidence"] = {"rule": "GSHHG sea + MOI >2m + Cop WBM land + Cop DSM >2m + abs(Cop-MOI)<=10m within 400m of named island",
                                       "height_source": "MOI 20m only; Copernicus DSM never supplies gameplay elevation",
                                       "decision_codes": {"0": "not_considered", "1": "accepted_MOI_land",
                                                          "2": "rejected_Cop_ocean", "3": "rejected_Cop_inland_water",
                                                          "4": "rejected_Cop_height_missing_or_low",
                                                          "5": "rejected_cross_source_height_difference_gt_10m",
                                                          "6": "rejected_Cop_geocell_missing_or_conflict"}}
        manifest["sources"].append({"id": "copernicus_glo30_2021_coast_evidence",
                                     "provider": "European Union Copernicus DEM / ESA / DLR / Airbus; public AWS COG mirror",
                                     "title": cop_doc["dataset"], "license_url": cop_doc["license_url"],
                                     "adapted_notice": cop_doc["adapted_notice"],
                                     "horizontal_datum": "WGS84", "vertical_datum": "EGM2008",
                                     "spacing": "1 arc-second, approximately 30m",
                                     "use": "shoreline corroboration only; no DSM gameplay elevation",
                                     "tiles": cop_doc["tiles"]})
    (OUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
                                       encoding="utf-8")
    print("Wrote", len(tiles), "tiles", counts, "projection_error", f"{distortion:.6%}")


def verify() -> None:
    manifest = json.loads((OUT / "manifest.json").read_text(encoding="utf-8"))
    records = [manifest["summary"], manifest["content_scope"]]
    for tile in manifest["elevation_tiles"]:
        records.append(tile)
        records.extend(({"path": tile["derived"][key + "_path"],
                         "sha256": tile["derived"][key + "_sha256"]} for key in ("levels", "water")))
        if "coast_decision_path" in tile["derived"]:
            records.append({"path": tile["derived"]["coast_decision_path"],
                            "sha256": tile["derived"]["coast_decision_sha256"]})
    for rec in records:
        path = OUT / rec["path"]
        if not path.is_file() or sha256(path) != rec["sha256"]:
            raise ValueError(f"Missing or changed generated file: {path}")
    for name in ("summary", "content_scope"):
        if len((OUT / manifest[name]["path"]).read_bytes()) != math.prod(manifest[name]["size"]):
            raise ValueError(f"{name} grid dimensions do not match")
    print("Verified", len(records), "generated records")


def report() -> None:
    """Record source-to-package gaps without changing the playable atlas."""
    verify()
    verify_source(DEM_ARCHIVE, DEM_SHA)
    verify_source(COAST_ARCHIVE, COAST_SHA)
    extract_inputs()
    manifest = json.loads((OUT / "manifest.json").read_text(encoding="utf-8"))
    baseline = coastal_summary(land_polygons(), projected_bounds())
    summary = np.frombuffer((OUT / "summary.u8").read_bytes(), dtype=np.uint8).reshape(baseline.shape)
    scope = np.frombuffer((OUT / "content_scope.u8").read_bytes(), dtype=np.uint8).reshape(baseline.shape)
    if np.any(scope > 5):
        raise ValueError("Content scope contains an unknown code")
    final_scope_gaps = scope_gaps(baseline, summary, scope)
    interior_scope_gaps = manifest["build_diagnostics"]["interior_gaps_by_scope"]
    labels = ("missing_data", "sea", "land", "inland_water", "mixed")
    scoped_coverage = {}
    for name, final in final_scope_gaps.items():
        code = ("outside_content", "taiwan", "penghu", "green_island", "lanyu", "surrounding_sea").index(name)
        current = scope == code
        interior = interior_scope_gaps[name]
        total = final["source_land"] + final["source_mixed"]
        source_missing = interior["missing_land"] + interior["missing_mixed"]
        final_missing = final["missing_land"] + final["missing_mixed"]
        scoped_coverage[name] = {**final,
                                 "content_sites_total": int(np.count_nonzero(current)),
                                 "current_summary_counts": {labels[i]: int(np.count_nonzero(current & (summary == i)))
                                                            for i in range(5)},
                                 "content_missing_site_count": int(np.count_nonzero(current & (summary == 0))),
                                 "content_available_land_or_mixed": int(np.count_nonzero(current & ((summary == 2) | (summary == 4)))),
                                 "source_land_or_mixed_sites": total,
                                 "missing_before_halo_gate": source_missing,
                                 "additional_missing_from_halo_gate": final_missing - source_missing,
                                 "final_missing_land_or_mixed": final_missing,
                                 "source_supported_land_or_mixed": total - final_missing}
    transitions = {labels[old]: {labels[new]: int(np.count_nonzero((baseline == old) & (summary == new)))
                                 for new in range(5) if np.any((baseline == old) & (summary == new))}
                   for old in (1, 2, 4)}
    sites = []
    by_id = {tile["id"]: tile for tile in manifest["elevation_tiles"]}
    ox, oy = manifest["summary"]["site_origin"]
    h, w = summary.shape
    for entry in manifest["preview_sites"]:
        sx, sy = entry["site"]
        label = labels[int(summary[h - 1 - (sy - oy), sx - ox])]
        rx, ry = sx // 100, sy // 100
        tile = by_id.get(f"r{rx}_{ry}")
        result = {"label": entry["label"], "lonlat": entry["lonlat"],
                  "site": [sx, sy], "summary_class": label}
        if tile is not None:
            row, col = (ry * 100 + 99 - sy) * 10, (sx - rx * 100) * 10
            raw = zlib.decompress((OUT / tile["path"]).read_bytes())
            height = np.frombuffer(raw, dtype="<i2").reshape(1000, 1000)[row:row + 10, col:col + 10]
            raw = zlib.decompress((OUT / tile["derived"]["levels_path"]).read_bytes())
            levels = np.frombuffer(raw, dtype=np.uint8).reshape(1000, 1000)[row:row + 10, col:col + 10]
            valid = height[height != NODATA]
            result["valid_dem_samples_20m"] = int(valid.size)
            if valid.size:
                result["elevation_m_min_max"] = [int(valid.min()), int(valid.max())]
                result["gameplay_levels_min_max"] = [int(levels[levels <= 5].min()),
                                                       int(levels[levels <= 5].max())]
        sites.append(result)
    files = [OUT / "manifest.json", OUT / manifest["summary"]["path"],
             OUT / manifest["content_scope"]["path"]]
    for tile in manifest["elevation_tiles"]:
        files.extend((OUT / tile["path"], OUT / tile["derived"]["levels_path"],
                      OUT / tile["derived"]["water_path"]))
        if "coast_decision_path" in tile["derived"]:
            files.append(OUT / tile["derived"]["coast_decision_path"])
    old_site = (1560, 13264)
    old_status = labels[int(summary[h - 1 - (old_site[1] - oy), old_site[0] - ox])]
    data = {
        "atlas_id": ATLAS, "base_revision": manifest["base_revision"],
        "method": "GSHHG whole-200m-Site land/mixed/sea class versus final MOI DEM-gated summary; 10x10 interior and complete 12x12 source-post halo checked",
        "source_site_counts": {labels[i]: int(np.count_nonzero(baseline == i)) for i in (1, 2, 4)},
        "packaged_site_counts": manifest["summary_counts"],
        "source_to_package_transitions": transitions,
        "scope_coverage": scoped_coverage,
        "build_diagnostics": manifest["build_diagnostics"],
        "atlas_wide_land_retained_fraction_including_outside_content": transitions["land"].get("land", 0) / int(np.count_nonzero(baseline == 2)),
        "atlas_wide_mixed_retained_fraction_including_outside_content": transitions["mixed"].get("mixed", 0) / int(np.count_nonzero(baseline == 4)),
        "source_dem_overlap_conflicts": 0,
        "projection_scale_error_fraction": manifest["max_measured_projection_scale_error"],
        "tile_count": len(manifest["elevation_tiles"]),
        "runtime_package_file_count": len(files),
        "runtime_package_bytes": sum(path.stat().st_size for path in files),
        "representative_sites": sites,
        "known_coast_counterexample": {"label": "East coast prior preview",
                                     "lonlat": [121.61, 23.98], "site": list(old_site),
                                     "scope": "taiwan",
                                     "final_summary_class": old_status,
                                     "r2_reason": "One 20m source post in its 12x12 halo was NoData because official MOI positive terrain conflicts with GSHHG whole-sea shoreline"},
        "limits": ["20m source height is sampled onto 2m gameplay cells; no 2m height measurement",
                   "final land/mixed retention checks the complete 12x12 source-post halo required by 102x102 gameplay cells",
                   "named island scope includes source polygons within declared nearshore distances; it is game content grouping, not an administrative border",
                   "GSHHG L1 has no inland water width/body identities in this atlas",
                   "coastal sites with land DEM gaps are Missing; a whole-sea Site with positive DEM conflict is Missing"],
    }
    if "coast_evidence" in manifest:
        old_folder = ROOT / "assets" / "region_lab" / ATLAS
        old_manifest = json.loads((old_folder / "manifest.json").read_text(encoding="utf-8"))
        old_summary = np.frombuffer((old_folder / old_manifest["summary"]["path"]).read_bytes(),
                                    dtype=np.uint8).reshape(summary.shape)
        old_scope = np.frombuffer((old_folder / old_manifest["content_scope"]["path"]).read_bytes(),
                                  dtype=np.uint8).reshape(scope.shape)
        if old_manifest["summary"]["size"] != manifest["summary"]["size"] or \
           old_manifest["summary"]["site_origin"] != manifest["summary"]["site_origin"]:
            raise ValueError("r2 and trial Site lattices differ")
        by_scope = {}
        for code, name in enumerate(("outside_content", "taiwan", "penghu", "green_island", "lanyu", "surrounding_sea")):
            current = scope == code
            was_available = (old_summary == 2) | (old_summary == 4)
            now_available = (summary == 2) | (summary == 4)
            by_scope[name] = {
                "newly_available_land_or_mixed": int(np.count_nonzero(current & ~was_available & now_available)),
                "lost_available_land_or_mixed": int(np.count_nonzero(current & was_available & ~now_available)),
                "gshhg_sea_promoted_to_mixed": int(np.count_nonzero(current & (old_summary == 1) & (summary == 4))),
                "scope_changes_from_r2": int(np.count_nonzero(current & (old_scope != scope)))}
        data["r2_comparison"] = {"r2_manifest_sha256": sha256(old_folder / "manifest.json"),
                                 "site_changes_by_final_scope": by_scope}
        data["coast_evidence"] = manifest["coast_evidence"]
        data["trial_review"] = {
            "status": "isolated_trial_not_promoted",
            "reason": "Lanyu 20m-post cross-source threshold fragments the shoreline into visible rectangular land/sea blocks at 2m gameplay scale",
            "counterexample_site": [1545, 12170],
            "source_audit": "coast_counterexample_lanyu.json",
            "gpu_capture": ".visual_captures/region_lab/r3_trial_20260927_01/lanyu.png",
            "delta_audit": "trial_delta_audit.json",
            "remaining_scope_1_to_4_missing_sites": sum(scoped_coverage[name]["content_missing_site_count"]
                                                        for name in ("taiwan", "penghu", "green_island", "lanyu"))}
    target = OUT / "coverage_report.json"
    target.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Wrote", target, "with", data["runtime_package_bytes"], "runtime bytes")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=("build", "verify", "report"))
    parser.add_argument("--trial", action="store_true", help="Use isolated Copernicus coast-evidence output")
    args = parser.parse_args()
    if args.trial:
        OUT = TRIAL_OUT
        BASE_REVISION = TRIAL_REVISION
    {"build": lambda: build(args.trial), "verify": verify, "report": report}[args.operation]()
