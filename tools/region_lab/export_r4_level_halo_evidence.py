"""Recreate unpackaged r4 level-input halos for independent formula audit.

This writes evidence under output only.  It does not change the atlas package.
"""

from __future__ import annotations

from contextlib import ExitStack
import argparse
import hashlib
import json
from pathlib import Path
import time
import zlib

import numpy as np
import rasterio
from rasterio.features import rasterize
from rasterio.transform import from_origin
from shapely.geometry import box
from shapely.strtree import STRtree

import build_r4 as build
import import_taiwan as atlas
from r4_estimation import NODATA, estimate_posts


REGIONS = ((11, 122), (11, 136), (12, 136))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(manifest_path: Path, output: Path) -> None:
    started = time.monotonic()
    manifest_sha = sha(manifest_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest["source_post_rule"]["method"] != "fixed_20km_global_core_then_join_halo":
        raise ValueError("Unexpected source-post policy")
    if manifest["source_post_rule"]["r2_manifest_sha256"] != build.R2_MANIFEST_SHA:
        raise ValueError("Unpinned r2 source")
    bounds = atlas.projected_bounds()
    west, _, south, north = bounds
    shape = tuple(reversed(manifest["summary"]["size"]))
    scope = np.frombuffer((manifest_path.parent / manifest["content_scope"]["path"])
                          .read_bytes(), dtype="u1").reshape(shape)
    provenance, polygons, *_ = build.load_sources()
    land_tree = STRtree(polygons)
    output.mkdir(parents=True, exist_ok=True)
    records = []
    with ExitStack() as stack:
        main = stack.enter_context(rasterio.open(atlas.TEMP / "dem_20m.tif"))
        penghu = stack.enter_context(rasterio.open(atlas.TEMP / "phDEM_20m_121.tif"))
        _, cop_sources = atlas.copernicus_sources(stack)
        fixed = build.FixedSourceReader(main, penghu, cop_sources)
        for rx, ry in REGIONS:
            if time.monotonic() - started > 300:
                raise TimeoutError("Audit-only halo recreation exceeded 300 seconds")
            e0, n0 = rx * atlas.REGION_M, ry * atlas.REGION_M
            halo = build.EST_HALO
            side = build.POSTS + 2 * halo
            rect = box(e0 - halo * atlas.SAMPLE_M, n0 - halo * atlas.SAMPLE_M,
                       e0 + atlas.REGION_M + halo * atlas.SAMPLE_M,
                       n0 + atlas.REGION_M + halo * atlas.SAMPLE_M)
            matrix = from_origin(rect.bounds[0], rect.bounds[3],
                                 atlas.SAMPLE_M, atlas.SAMPLE_M)
            pairs = [(polygons[int(i)], int(i) + 1)
                     for i in sorted(land_tree.query(rect))]
            center = rasterize(pairs, out_shape=(side, side), transform=matrix,
                               fill=0, dtype="uint16")
            touched = rasterize(pairs, out_shape=(side, side), transform=matrix,
                                fill=0, dtype="uint16", all_touched=True)
            active = build.active_posts(scope, rx, ry, bounds, halo)
            center[~active] = 0
            touched[~active] = 0
            components, support = build.support_components(center, touched)
            raw, cop, wbm = fixed.window(rx, ry, halo)
            height_halo, _, _, _, _ = estimate_posts(raw, components, support,
                                                       cop, wbm)
            tile = next((t for t in manifest["elevation_tiles"]
                         if t["id"] == f"r{rx}_{ry}"), None)
            if tile is None:
                raise ValueError(f"Expected packed tile r{rx}_{ry} is absent")
            packed_path = manifest_path.parent / tile["path"]
            atlas.verify_source(packed_path, tile["sha256"])
            level_path = manifest_path.parent / tile["derived"]["levels_path"]
            atlas.verify_source(level_path, tile["derived"]["levels_sha256"])
            packed = np.frombuffer(zlib.decompress(packed_path.read_bytes()),
                                   dtype="<i2").reshape(build.POSTS, build.POSTS)
            core = height_halo[halo:halo + build.POSTS,
                               halo:halo + build.POSTS]
            mismatches = int(np.count_nonzero(core != packed))
            if mismatches:
                raise ValueError(f"r{rx}_{ry} reconstructed core differs at {mismatches} posts")
            radius = atlas.LEVEL_RADIUS
            level_input = height_halo[halo - radius:halo + build.POSTS + radius,
                                      halo - radius:halo + build.POSTS + radius]
            if level_input.shape != (1020, 1020):
                raise ValueError("Wrong 10-post level input halo")
            code = f"r{rx}_{ry}"
            data_path = output / f"{code}.level_input.i16.z"
            data_path.write_bytes(zlib.compress(level_input.astype("<i2").tobytes(), 6))
            records.append({"region": [rx, ry], "path": data_path.name,
                            "sha256": sha(data_path), "encoding": "int16_le_zlib",
                            "bytes": data_path.stat().st_size,
                            "row_order": "north_to_south", "size": [1020, 1020],
                            "origin": [e0 - radius * atlas.SAMPLE_M,
                                       n0 - radius * atlas.SAMPLE_M],
                            "spacing_m": atlas.SAMPLE_M, "nodata": NODATA,
                            "core_height_sha256": tile["sha256"],
                            "core_level_sha256": tile["derived"]["levels_sha256"],
                            "recreated_core_height_mismatches": mismatches})
    evidence = {"format": 1,
                "purpose": "unpacked_level_formula_halo_only",
                "source_manifest_sha256": manifest_sha,
                "r2_manifest_sha256": build.R2_MANIFEST_SHA,
                "source_post_rule": manifest["source_post_rule"],
                "osm_provenance_sha256": sha(build.SOURCE / "provenance.json"),
                "source_outputs": provenance["outputs"],
                "tiles": records,
                "elapsed_seconds": round(time.monotonic() - started, 3)}
    (output / "index.json").write_text(
        json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Audit-only halos complete: {output / 'index.json'}; "
          f"r4={manifest_sha}; regions={len(records)}", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    run(args.manifest, args.out)
