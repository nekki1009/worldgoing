"""Prepare locked OSM source vectors; never clip a coastline to a map boundary.

Uses the existing region_lab GIS dependencies. Network acquisition is explicit;
processing is offline and preserves the downloaded inputs and their hashes.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import zipfile

import shapefile
from shapely import make_valid, prepare, transform as transform_geometry
from shapely.geometry import LinearRing, Point, Polygon, box, mapping, shape
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parent / ".tmp" / "osm_source"
BBOX = (118.9, 21.3, 122.7, 25.75)
SHAPE_URL = "https://download.geofabrik.de/asia/taiwan-260926-free.shp.zip"
OVERPASS_URL = "https://overpass-api.de/api/interpreter"
LICENSE_URL = "https://opendatacommons.org/licenses/odbl/1-0/"
ANCHORS = {"taiwan": (121.0, 23.8), "penghu": (119.60, 23.58),
           "green_island": (121.485, 22.66), "lanyu": (121.55, 22.03)}


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_json(path, value):
    text = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    if path.exists() and path.read_text(encoding="utf-8") == text:
        return
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(text, encoding="utf-8")
    temporary.replace(path)


def file_record(path, url):
    return {"path": path.name, "url": url, "bytes": path.stat().st_size,
            "sha256": digest(path),
            "created_at_utc" if url == "derived" else "retrieved_at_utc":
                datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat()}


def polygonal(geometry, repairs, identity):
    if not geometry.is_valid:
        original_area = geometry.area
        geometry = make_valid(geometry)
        repairs.append({"id": identity, "operation": "shapely.make_valid",
                        "area_degrees2_before": original_area, "area_degrees2_after": geometry.area})
    if geometry.geom_type == "GeometryCollection":
        geometry = unary_union([g for g in geometry.geoms if g.geom_type in ("Polygon", "MultiPolygon")])
    if geometry.is_empty or geometry.geom_type not in ("Polygon", "MultiPolygon"):
        raise ValueError(f"No polygonal surface for {identity}")
    return geometry


def water_kind_hint(tags):
    if tags.get("water") in ("sea", "ocean"):
        return 2, "explicit water=sea/ocean"
    if tags.get("salt") == "yes" or tags.get("salinity") in ("salt", "saline", "brackish"):
        return 3, "explicit salt/salinity tag"
    if tags.get("salt") == "no" or tags.get("salinity") in ("fresh", "freshwater"):
        return 1, "explicit fresh/salt=no tag"
    return 4, "known water surface; salinity unspecified in source tags"


def coast_polygons(elements):
    """Join complete, directed OSM ways by node ID; never add closing segments."""
    ways = {e["id"]: e for e in elements
            if e["type"] == "way" and e.get("tags", {}).get("natural") == "coastline"}
    outgoing = defaultdict(list)
    for identity, way in ways.items():
        assert len(way["nodes"]) == len(way["geometry"]) >= 2, identity
        outgoing[way["nodes"][0]].append(identity)
    unused = set(ways)
    rings, incomplete, branches = [], [], []
    while unused:
        identity = min(unused)
        way = ways[identity]
        start, end = way["nodes"][0], way["nodes"][-1]
        coordinates = [(p["lon"], p["lat"]) for p in way["geometry"]]
        members = [identity]
        unused.remove(identity)
        while end != start:
            candidates = [i for i in outgoing[end] if i in unused]
            if len(candidates) != 1:
                if len(candidates) > 1:
                    branches.append({"node": end, "ways": candidates})
                break
            next_id = candidates[0]
            next_way = ways[next_id]
            assert coordinates[-1] == (next_way["geometry"][0]["lon"], next_way["geometry"][0]["lat"])
            coordinates.extend((p["lon"], p["lat"]) for p in next_way["geometry"][1:])
            end = next_way["nodes"][-1]
            unused.remove(next_id)
            members.append(next_id)
        if end != start:
            incomplete.append({"way_ids": members, "start_node": start, "end_node": end,
                               "bounds": [min(p[0] for p in coordinates), min(p[1] for p in coordinates),
                                          max(p[0] for p in coordinates), max(p[1] for p in coordinates)]})
            continue
        assert coordinates[0] == coordinates[-1]
        rings.append((coordinates, sorted(members), LinearRing(coordinates).is_ccw))
    outers = [(Polygon(coords), members) for coords, members, ccw in rings if ccw]
    holes = [(Polygon(coords), members) for coords, members, ccw in rings if not ccw]
    features, repairs = [], []
    assigned_holes = set()
    for outer, members in outers:
        inside = []
        for index, (hole, hole_members) in enumerate(holes):
            if outer.covers(hole.representative_point()):
                inside.append(hole)
                members = members + hole_members
                assigned_holes.add(index)
        geometry = outer.difference(unary_union(inside)) if inside else outer
        identity = "osm_coast:way/" + str(min(members))
        geometry = polygonal(geometry, repairs, identity)
        features.append({"type": "Feature", "id": identity,
                         "properties": {"source": "OpenStreetMap", "osm_way_ids": sorted(members),
                                        "closure": "original_node_ids", "bbox_clipped": False},
                         "geometry": mapping(geometry)})
    coverage = {}
    for name, coordinates in ANCHORS.items():
        containing = [f["id"] for f in features if shape(f["geometry"]).covers(Point(coordinates))]
        if len(containing) != 1:
            raise ValueError(f"Island anchor {name} must be covered once, found {containing}")
        coverage[name] = {"anchor": coordinates, "land_feature_id": containing[0]}
    return features, {"source_ways": len(ways), "closed_rings": len(rings), "land_features": len(features),
                      "incomplete_chains": incomplete, "branch_nodes": branches,
                      "unassigned_clockwise_rings": [ids for i, (_, ids) in enumerate(holes) if i not in assigned_holes],
                      "coverage": coverage, "repairs": repairs}


def inland_water(archive_path, elements, folder):
    identities = defaultdict(set)
    osm_tags = {}
    for element in elements:
        if element["type"] in ("way", "relation"):
            identities[str(element["id"])].add(element["type"])
            osm_tags[(element["type"], str(element["id"]))] = element.get("tags", {})
    with zipfile.ZipFile(archive_path) as archive:
        names = archive.namelist()
        if "README" in names:
            (folder / "Geofabrik-README.txt").write_bytes(archive.read("README"))
        selected = [n for n in names if Path(n).name.startswith("gis_osm_water_a_free_")]
        if not selected:
            raise ValueError("Geofabrik archive has no polygon water layer")
        extracted = folder / "geofabrik_water"
        extracted.mkdir(exist_ok=True)
        for name in selected:
            # Only explicitly selected layer files, flattened under our output.
            (extracted / Path(name).name).write_bytes(archive.read(name))
    features, repairs, unresolved, excluded = [], [], [], []
    seen = defaultdict(int)
    counts = defaultdict(int)
    source_rings = output_rings = 0
    for filename in sorted(extracted.glob("*.shp")):
        reader = shapefile.Reader(str(filename), encoding="utf-8")
        for record in reader.iterShapeRecords(bbox=BBOX):
            properties = record.record.as_dict()
            raw_id = str(properties["osm_id"])
            if properties["fclass"] not in ("water", "reservoir", "riverbank"):
                excluded.append({"osm_id": raw_id, "fclass": properties["fclass"],
                                 "reason": "Not an explicit open-water polygon class"})
                continue
            known_types = identities.get(raw_id, set())
            if len(known_types) != 1:
                unresolved.append({"osm_id": raw_id, "name": properties.get("name"), "fclass": properties.get("fclass"),
                                   "candidate_types": sorted(known_types)})
                continue
            osm_type = next(iter(known_types))
            identity = f"{osm_type}/{raw_id}"
            geometry = polygonal(shape(record.shape.__geo_interface__), repairs, identity)
            if not geometry.intersects(box(*BBOX)):
                continue
            polygons = [geometry] if geometry.geom_type == "Polygon" else geometry.geoms
            ring_count = sum(1 + len(p.interiors) for p in polygons)
            assert len(record.shape.parts) == ring_count, f"Source rings changed: {identity}"
            source_rings += len(record.shape.parts)
            output_rings += ring_count
            part = seen[identity]
            seen[identity] += 1
            tags = osm_tags[(osm_type, raw_id)]
            kind, reason = water_kind_hint(tags)
            properties.update({"osm_type": osm_type, "osm_id": raw_id, "source_id": identity,
                               "water_body_id": "ocean" if kind == 2 else identity,
                               "osm_tags": tags, "kind_hint": kind, "kind_evidence": reason,
                               "source": "Geofabrik/OpenStreetMap", "bbox_clipped": False})
            features.append({"type": "Feature", "id": f"{identity}:part/{part}",
                             "properties": properties, "geometry": mapping(geometry)})
            counts[str(properties["fclass"])] += 1
    return features, {"archive_layers": [n for n in names if n.endswith(".shp")],
                      "coast_layer_present": any("coast" in n.lower() for n in names),
                      "features": len(features), "body_ids": len(seen), "classes": dict(counts),
                      "source_rings": source_rings, "output_rings": output_rings,
                      "unresolved_osm_types": unresolved, "excluded_non_water_classes": excluded,
                      "repairs": repairs}


def scope_report(water, manifest_path, folder):
    """Exact polygon intersection with the existing 200m content-scope footprint."""
    import numpy as np
    from affine import Affine
    from pyproj import Transformer
    from rasterio.features import shapes

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    record = manifest["content_scope"]
    width, height = record["size"]
    raw = (manifest_path.parent / record["path"]).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == record["sha256"]
    scope = np.frombuffer(raw, dtype=np.uint8).reshape(height, width)
    west, south = (int(v) * 200 for v in record["site_origin"])
    affine = Affine(200, 0, west, 0, -200, south + height * 200)
    groups = defaultdict(list)
    for geometry, value in shapes(scope, mask=np.isin(scope, [1, 2, 3, 4]), transform=affine):
        groups[int(value)].append(shape(geometry))
    scope_geometries = {key: unary_union(values) for key, values in groups.items()}
    for geometry in scope_geometries.values():
        prepare(geometry)
    projection = Transformer.from_crs(4326, 3826, always_xy=True)
    counts, kind_counts = defaultdict(int), defaultdict(int)
    bodies = {}
    included_features = 0
    for feature in water:
        geometry = transform_geometry(shape(feature["geometry"]), projection.transform, interleaved=False)
        matched = [key for key, scope_geometry in scope_geometries.items() if scope_geometry.intersects(geometry)]
        if not matched:
            continue
        included_features += 1
        for key in matched:
            counts[key] += 1
        properties = feature["properties"]
        kind_counts[properties["kind_hint"]] += 1
        bodies[properties["water_body_id"]] = {"source_id": properties["water_body_id"],
                                               "kind": properties["kind_hint"],
                                               "name": properties.get("name", "")}
    # This is a capacity probe, not a second runtime water/body authority.
    registry = [{"id": 1, "source_id": "ocean", "kind": 2, "name": "Ocean"}] if "ocean" in bodies else []
    registry.extend({"id": i + 2, **bodies[key]} for i, key in enumerate(sorted(k for k in bodies if k != "ocean")))
    path = folder / "water_registry_scope1_4.json"
    write_json(path, registry)
    result = {"scope_manifest": str(manifest_path), "scope_manifest_sha256": digest(manifest_path),
              "scope_mask_sha256": record["sha256"], "selection": "any exact polygon intersection; no clipping",
              "features": included_features, "features_by_scope": dict(counts), "body_ids": len(registry),
              "features_by_explicit_kind_hint": dict(kind_counts), "unknown_hint": 4,
              "registry_utf8_bytes": path.stat().st_size, "registry_4MiB_headroom": 4194304 - path.stat().st_size,
              "registry_sha256": digest(path),
              "note": "4 is water of unspecified salinity, never land or freshwater by default; ocean is shared ID 1. Other registry IDs here only measure capacity."}
    write_json(folder / "water_scope_report.json", result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--folder", type=Path, default=ROOT)
    parser.add_argument("--scope-manifest", type=Path)
    args = parser.parse_args()
    folder = args.folder.resolve()
    archive = folder / "taiwan-260926-free.shp.zip"
    raw = folder / "coast_water_ids.json"
    dataset = json.loads(raw.read_text(encoding="utf-8"))
    if dataset.get("remark"):
        raise ValueError(dataset["remark"])
    land, coast_report = coast_polygons(dataset["elements"])
    water, water_report = inland_water(archive, dataset["elements"], folder)
    for name, features in (("land.geojson", land), ("inland_water.geojson", water)):
        write_json(folder / name, {"type": "FeatureCollection", "features": features})
    provenance = {"format": 1, "prepared_utc": datetime.now(timezone.utc).isoformat(),
                  "crs": "EPSG:4326", "query_bbox": BBOX, "bbox_used_only_for_selection": True,
                  "license": "ODbL-1.0", "license_url": LICENSE_URL,
                  "water_kind_rule": {"1": "explicit salt=no or freshwater salinity tag",
                                      "2": "explicit water=sea/ocean, shared ocean body",
                                      "3": "explicit salt=yes or saline/brackish salinity tag",
                                      "4": "known mapped water surface, salinity unspecified"},
                  "attribution": "© OpenStreetMap contributors; water shapes processed by Geofabrik GmbH",
                  "osm_base_timestamp": dataset.get("osm3s", {}).get("timestamp_osm_base"),
                  "inputs": [file_record(archive, SHAPE_URL), file_record(raw, OVERPASS_URL)],
                  "source_documents": [file_record(folder / name, url) for name, url in
                                       (("LICENSE-ODbL-1.0.html", LICENSE_URL),
                                        ("Geofabrik-README.txt", SHAPE_URL + "#README")) if (folder / name).exists()],
                  "query_sha256": digest(folder / "coast_water_ids.query"),
                  "coast": coast_report, "inland_water": water_report,
                  "outputs": [file_record(folder / n, "derived") for n in ("land.geojson", "inland_water.geojson")],
                  "limitations": ["OSM records mapped geography, not a completeness survey or historical reconstruction.",
                                  "Line-only rivers are not expanded into invented water widths.",
                                  "Open chains from the mainland/query edge are recorded, never closed using the bbox.",
                                  "The land output completely encloses the four island groups; it is not a land/sea authority for the open Fujian mainland background.",
                                  "Geofabrik water polygons include ponds, wastewater and coastal waters. Original OSM tags are retained; freshwater or salinity must not be inferred from the filename.",
                                  "Water names/classes do not establish a measured water-surface elevation."]}
    write_json(folder / "provenance.json", provenance)
    if args.scope_manifest:
        print(json.dumps(scope_report(water, args.scope_manifest, folder), ensure_ascii=True), flush=True)
    print(json.dumps({"land": len(land), "water": len(water), "coast_open_chains": len(coast_report["incomplete_chains"]),
                      "water_unresolved": len(water_report["unresolved_osm_types"]), "folder": str(folder)}, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
