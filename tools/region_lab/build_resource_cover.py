"""Build/verify fixed OSM land-cover tiles without changing the geography atlas.

Run with the existing Python 3.12 GIS dependencies under .tmp/deps. Land cover
constrains game placement; it is not an inventory, mineral or forestry survey.
"""
from __future__ import annotations

from collections import Counter
import hashlib
import io
import json
from pathlib import Path
import sys
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).parent / ".tmp/deps"))
import numpy as np
from pyproj import Transformer
from rasterio.features import rasterize
from rasterio.transform import from_origin
import shapefile
from shapely.geometry import Point, box, shape
from shapely.ops import transform
from shapely.strtree import STRtree

OUT = ROOT / "assets/region_lab/earth_tw_resources_v1"
GEO = ROOT / "assets/region_lab/earth_tw_tm2_121_v1_r4/manifest.json"
ZIP = Path(__file__).parent / ".tmp/osm_source/taiwan-260926-free.shp.zip"
GEO_SHA = "e3108aad1cbfd5118af08fd699ac03bf64d19b5bc9d186154dc9a5fea279f7b8"
ZIP_SHA = "960710795bd19191f19fbadc6decf4843c177ea5b8e616254bf87212c458d89c"
CATEGORIES = {"0": "unclassified", "1": "forest", "2": "grass_meadow",
              "3": "scrub_heath", "4": "farmland_vineyard", "5": "orchard",
              "6": "quarry", "7": "built"}
CLASSES = {"forest": 1, "grass": 2, "meadow": 2, "scrub": 3, "heath": 3,
           "farmland": 4, "orchard": 5, "vineyard": 4, "quarry": 6,
           "residential": 7, "industrial": 7, "commercial": 7, "retail": 7,
           "farmyard": 7, "cemetery": 7, "military": 7, "landfill": 7}
REGION_M, CELL_M, SIDE = 20000, 20, 1000
PLACEMENT_EVIDENCE = {
    "alpine_vegetation": {
        "source_url": "https://www.ysnp.gov.tw/RecreationArea/1fbfec62-e8ce-4916-a902-a6c28c9dd33e?Tab=6",
        "source_title": "Yushan National Park vegetation zones",
        "source_scope": "Yushan; not a Taiwan-wide species or tree-position survey",
        "documented_bands_m": [
            {"min": 3000, "max": 3600, "vegetation": "fir"},
            {"min": 3600, "max": 3850, "vegetation": "dwarf_shrubs"},
            {"min": 3850, "max": 3952, "vegetation": "herbaceous"}],
        "game_rule": "Use absolute elevation, not the 0-5 gameplay levels. At or above 3600 m, forest cover produces no timber and uses sparse scrub resources; at or above 3850 m, only sparse food/herb candidates remain.",
        "limitation": "Conservative game placement rule based on mapped vegetation belts; it does not establish surveyed trees, edible plants, medicinal properties or resource quantities."}}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def pinned(path: Path, expected: str) -> bytes:
    raw = path.read_bytes()
    if sha(raw) != expected:
        raise ValueError(f"Pinned input hash changed: {path}")
    return raw


def write_json(path: Path, value: dict) -> None:
    # Preserve the pinned Windows package bytes when rebuilding on another OS.
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\r\n")


def read_sources():
    """Preserve original polygons and holes; no buffer, repair or all-touched."""
    geometries, features, classes, empty_sources = [], [], Counter(), []
    project = Transformer.from_crs(4326, 3826, always_xy=True).transform
    with zipfile.ZipFile(io.BytesIO(pinned(ZIP, ZIP_SHA))) as archive:
        stem = "gis_osm_landuse_a_free_1"
        reader = shapefile.Reader(**{ext: io.BytesIO(archive.read(f"{stem}.{ext}"))
                                    for ext in ("shp", "shx", "dbf")}, encoding="utf-8")
        for source in reader.iterShapeRecords():
            record = source.record.as_dict()
            fclass = record["fclass"]
            classes[fclass] += 1
            if fclass not in CLASSES:
                continue
            if not source.shape.points:
                empty_sources.append(record)
                continue
            geometry = transform(project, shape(source.shape.__geo_interface__))
            if geometry.is_empty or geometry.geom_type not in ("Polygon", "MultiPolygon"):
                raise ValueError(f"Unsupported source geometry: {record}")
            geometries.append(geometry)
            features.append({"osm_id": record["osm_id"], "fclass": fclass,
                             "name": record["name"], "category": CLASSES[fclass]})
    return geometries, features, classes, empty_sources


def verify() -> dict:
    manifest = json.loads((OUT / "manifest.json").read_text(encoding="utf-8"))
    geography = json.loads(pinned(GEO, GEO_SHA))
    expected = {(int(t["origin"][0]) // REGION_M, int(t["origin"][1]) // REGION_M)
                for t in geography["elevation_tiles"]}
    actual = {tuple(map(int, key.split(","))) for key in manifest["tiles"]}
    assert actual == expected, "Resource coverage must exactly follow geography core tiles"
    assert manifest["geography_manifest_sha256"] == GEO_SHA
    assert manifest["source"]["sha256"] == ZIP_SHA
    assert manifest["categories"] == CATEGORIES and manifest["class_mapping"] == CLASSES
    assert manifest["placement_evidence"] == PLACEMENT_EVIDENCE
    assert (manifest["cell_size_m"], manifest["region_size_m"], manifest["tile_size"],
            manifest["crs"], manifest["row_order"]) == (20, 20000, [1000, 1000],
                                                       "EPSG:3826", "north_to_south")
    totals = np.zeros(8, dtype=np.int64)
    for key, entry in manifest["tiles"].items():
        rx, ry = map(int, key.split(","))
        assert entry["origin"] == [rx * REGION_M, ry * REGION_M]
        compressed = (OUT / entry["path"]).read_bytes()
        assert sha(compressed) == entry["sha256"] and len(compressed) == entry["bytes"]
        raw = zlib.decompress(compressed)
        assert len(raw) == SIDE * SIDE == entry["raw_bytes"]
        cover = np.frombuffer(raw, dtype=np.uint8)
        assert int(cover.max()) <= 7
        counts = np.bincount(cover, minlength=8)
        assert counts.tolist() == entry["counts"]
        totals += counts
    assert totals.tolist() == manifest["pixel_counts"]
    for sample in manifest["samples"]:
        entry = manifest["tiles"][sample["region_key"]]
        raw = zlib.decompress((OUT / entry["path"]).read_bytes())
        assert raw[sample["row"] * SIDE + sample["col"]] == sample["category"]
    assert {s["category"] for s in manifest["samples"]} == set(range(8))
    runtime_package_bytes = (OUT / "manifest.json").stat().st_size + sum(
        (OUT / entry["path"]).stat().st_size for entry in manifest["tiles"].values())
    return {"status": "PASS", "tiles": len(actual), "pixel_counts": totals.tolist(),
            "package_bytes": runtime_package_bytes,
            "package_bytes_scope": "manifest.json plus referenced runtime tiles; excludes README.md and verification.json",
            "sample_categories": len(manifest["samples"])}


def build() -> None:
    if (OUT / "manifest.json").exists():
        raise FileExistsError("Resource package already exists; use --verify to check it")
    geography = json.loads(pinned(GEO, GEO_SHA))
    assert geography["crs"] == "EPSG:3826"
    cores = sorted({(int(t["origin"][0]) // REGION_M, int(t["origin"][1]) // REGION_M)
                    for t in geography["elevation_tiles"]})
    geometries, features, class_counts, empty_sources = read_sources()
    print(f"Loaded {len(geometries)} classified polygons for {len(cores)} cores", flush=True)
    tree = STRtree(geometries)
    inverse = Transformer.from_crs(3826, 4326, always_xy=True)
    manifest = {"format": 1, "placement_rule": "osm_landcover_resources_v1",
                "geography_manifest_sha256": GEO_SHA, "crs": "EPSG:3826",
                "cell_size_m": CELL_M, "region_size_m": REGION_M,
                "tile_size": [SIDE, SIDE], "encoding": "u8_zlib",
                "row_order": "north_to_south", "categories": CATEGORIES,
                "class_mapping": CLASSES, "overlap_rule": "higher_category_wins",
                "sampling_rule": "pixel_center_all_touched_false",
                "source": {"url": "https://download.geofabrik.de/asia/taiwan-260926-free.shp.zip",
                           "sha256": ZIP_SHA, "bytes": ZIP.stat().st_size,
                           "snapshot_utc": "2026-09-26T20:22:51Z",
                           "layer": "gis_osm_landuse_a_free_1",
                           "feature_counts": dict(sorted(class_counts.items())),
                           "selected_feature_count": len(features),
                           "empty_geometries_excluded": empty_sources,
                           "license": "ODbL-1.0",
                           "attribution": "Copyright OpenStreetMap contributors; processed by Geofabrik GmbH"},
                "limitations": ["Mapped present-day land cover, not exhaustive ground truth or historical reconstruction.",
                                "20 m cell-center samples preserve polygon holes but can omit smaller features.",
                                "Unclassified is unknown, not evidence that resources are absent.",
                                "Forest does not establish tree species or quantities; quarry does not establish mineral type or remaining stock.",
                                "Game resource instances, yields and ecology remain game rules, not surveyed source facts."],
                "tiles": {}, "samples": []}
    (OUT / "tiles").mkdir(parents=True, exist_ok=True)
    totals = np.zeros(8, dtype=np.int64)
    sampled = set()
    for index, (rx, ry) in enumerate(cores):
        west, south = rx * REGION_M, ry * REGION_M
        north = south + REGION_M
        ids = sorted(tree.query(box(west, south, west + REGION_M, north), predicate="intersects"),
                     key=lambda i: (features[i]["category"], int(i)))
        cover = (rasterize([(geometries[i], features[i]["category"]) for i in ids],
                           out_shape=(SIDE, SIDE), fill=0, dtype="uint8", all_touched=False,
                           transform=from_origin(west, north, CELL_M, CELL_M))
                 if ids else np.zeros((SIDE, SIDE), dtype=np.uint8))
        counts = np.bincount(cover.ravel(), minlength=8)
        totals += counts
        key = f"{rx},{ry}"
        relative = f"tiles/{rx}_{ry}.cover.zlib"
        compressed = zlib.compress(cover.tobytes(), level=9)
        (OUT / relative).write_bytes(compressed)
        manifest["tiles"][key] = {"path": relative, "sha256": sha(compressed),
                                  "bytes": len(compressed), "raw_bytes": SIDE * SIDE,
                                  "origin": [west, south], "counts": counts.tolist()}
        for category in range(8):
            if category in sampled or not counts[category]:
                continue
            row, col = np.argwhere(cover == category)[counts[category] // 2]
            easting, northing = west + (int(col) + .5) * CELL_M, north - (int(row) + .5) * CELL_M
            point = Point(easting, northing)
            source_ids = tree.query(point, predicate="intersects")
            expected = max((features[i]["category"] for i in source_ids), default=0)
            assert expected == category, "Raster category differs from independent source point query"
            sample = {"category": category, "region_key": key, "row": int(row), "col": int(col),
                      "projected_m": [easting, northing], "lon_lat": list(inverse.transform(easting, northing)),
                      "source_features": [features[i] for i in source_ids]}
            manifest["samples"].append(sample)
            sampled.add(category)
        if (index + 1) % 25 == 0:
            print(f"Built {index + 1}/{len(cores)} resource tiles", flush=True)
    manifest["pixel_counts"] = totals.tolist()
    manifest["samples"].sort(key=lambda s: s["category"])
    manifest["placement_evidence"] = PLACEMENT_EVIDENCE
    write_json(OUT / "manifest.json", manifest)
    report = verify()
    write_json(OUT / "verification.json", report)
    print(json.dumps(report), flush=True)


if __name__ == "__main__":
    if len(sys.argv) == 1:
        build()
    elif sys.argv[1:] == ["--verify"]:
        print(json.dumps(verify()), flush=True)
    else:
        raise SystemExit("Usage: build_resource_cover.py [--verify]")
