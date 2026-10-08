"""Recompute r4 Site quality from packed 2 m masks and 20 m contributors.

This is a metadata-only repair.  Every elevation, water, level and fine-mask
file stays byte-identical, and the pre-repair manifest/report are preserved.
"""

from __future__ import annotations

from functools import lru_cache
import hashlib
import json
import os
from pathlib import Path
import time
import zlib

import numpy as np

import build_r4 as build
import import_taiwan as atlas
from r4_estimation import NODATA


ROOT = atlas.ROOT / "assets/region_lab/earth_tw_tm2_121_v1_r4"
BACKUP = atlas.ROOT / "output/region_lab_real_acceptance/r4_pre_quality_fix"
EXPECTED_OLD_SHA = "dcc4171ccda374e6f4c6bc95f68bc0cfb5f01acdb6643594517a98f760125b3d"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> None:
    started = time.monotonic()
    manifest_path = ROOT / "manifest.json"
    old_manifest = manifest_path.read_bytes()
    if digest(old_manifest) != EXPECTED_OLD_SHA:
        raise ValueError("r4 candidate manifest changed before quality repair")
    manifest = json.loads(old_manifest)
    quality_path = ROOT / manifest["source_quality"]["path"]
    old_quality = quality_path.read_bytes()
    atlas.verify_source(quality_path, manifest["source_quality"]["sha256"])
    report_path = ROOT / "coverage_report.json"
    old_report = report_path.read_bytes()
    report = json.loads(old_report)
    BACKUP.mkdir(parents=True, exist_ok=True)
    for name, data in (("manifest.json", old_manifest),
                       ("coverage_report.json", old_report),
                       ("source_quality.u8", old_quality)):
        destination = BACKUP / name
        if destination.exists() and destination.read_bytes() != data:
            raise ValueError(f"Existing backup disagrees: {destination}")
        if not destination.exists():
            destination.write_bytes(data)
    size = manifest["summary"]["size"]
    origin = manifest["summary"]["site_origin"]
    quality = np.frombuffer(old_quality, dtype="u1").copy().reshape(size[1], size[0])
    old = quality.copy()
    west = origin[0] // 100
    south = origin[1] // 100
    north = south + size[1] // 100
    tiles = {(t["origin"][0] // atlas.REGION_M,
              t["origin"][1] // atlas.REGION_M): t
             for t in manifest["elevation_tiles"]}
    kinds = np.full(max([1] + [b["id"] for b in manifest["water_bodies"]]) + 1,
                    255, dtype="u1")
    kinds[0], kinds[1] = 0, 2
    for body in manifest["water_bodies"]:
        kinds[body["id"]] = body["kind"]

    @lru_cache(maxsize=24)
    def core(rx: int, ry: int, field: str) -> np.ndarray:
        tile = tiles.get((rx, ry))
        dtype, fill = {"height": ("<i2", NODATA),
                       "quality": ("u1", 0),
                       "body": ("<u4", 1)}[field]
        if tile is None:
            return np.full((1000, 1000), fill, dtype=dtype)
        if field == "height":
            record = {"path": tile["path"], "sha256": tile["sha256"]}
        else:
            derived = tile["derived"]
            label = "quality" if field == "quality" else "water_body"
            record = {"path": derived[f"{label}_path"],
                      "sha256": derived[f"{label}_sha256"]}
        path = ROOT / record["path"]
        atlas.verify_source(path, record["sha256"])
        raw = zlib.decompress(path.read_bytes())
        result = np.frombuffer(raw, dtype=dtype)
        if result.size != 1_000_000:
            raise ValueError(f"Invalid {field} core size: {path}")
        return result.reshape(1000, 1000)

    segments = 0
    for (rx, ry), tile in tiles.items():
        if time.monotonic() - started > 600:
            raise TimeoutError("Metadata-only r4 quality scan exceeded 600 seconds")
        detail = tile["derived"].get("water_detail")
        if detail is None:
            continue
        q_halo = build.assemble_fixed_cores(lambda x, y: core(x, y, "quality"),
                                            rx, ry, 1, np.uint8, 0)
        h_halo = build.assemble_fixed_cores(lambda x, y: core(x, y, "height"),
                                            rx, ry, 1, np.int16, NODATA)
        b_halo = build.assemble_fixed_cores(lambda x, y: core(x, y, "body"),
                                            rx, ry, 1, np.uint32, 1)
        if np.any(b_halo >= len(kinds)):
            raise ValueError(f"Unknown water body near r{rx}_{ry}")
        w_halo = kinds[b_halo]
        if np.any(w_halo == 255):
            raise ValueError(f"Unregistered water body near r{rx}_{ry}")
        index_path = ROOT / detail["index_path"]
        bank_path = ROOT / detail["data_path"]
        atlas.verify_source(index_path, detail["index_sha256"])
        atlas.verify_source(bank_path, detail["data_sha256"])
        index = json.loads(index_path.read_text(encoding="utf-8"))
        bank = bank_path.read_bytes()
        for key, segment in index.items():
            local = int(key)
            row, col = divmod(local, 100)
            offset, length = segment["offset"], segment["compressed_bytes"]
            compressed = bank[offset:offset + length]
            if digest(compressed) != segment["sha256"]:
                raise ValueError(f"Fine segment hash changed in r{rx}_{ry}/{key}")
            mask = np.frombuffer(zlib.decompress(compressed),
                                 dtype="<u4").reshape(100, 100)
            y0, x0 = row * 10, col * 10
            public = build.fine_public_quality_max(
                mask, q_halo[y0:y0 + 12, x0:x0 + 12],
                h_halo[y0:y0 + 12, x0:x0 + 12],
                w_halo[y0:y0 + 12, x0:x0 + 12])
            gy, gx = (north - 1 - ry) * 100 + row, (rx - west) * 100 + col
            quality[gy, gx] = max(int(quality[gy, gx]), public)
            segments += 1
    changed = int(np.count_nonzero(quality != old))
    if changed != 5051 or np.any(quality < old) or np.any(quality > 4):
        raise ValueError(f"Unexpected Site quality repair: {changed} changed")
    new_quality = quality.tobytes()
    manifest["source_quality"]["sha256"] = digest(new_quality)
    manifest["source_quality_rule"] = (
        "worst_public_2m_contributor_including_water_height_support")
    manifest["base_revision"] = build.REVISION
    new_manifest = (json.dumps(manifest, ensure_ascii=False,
                               separators=(",", ":")) + "\n").encode("utf-8")
    new_manifest_sha = digest(new_manifest)
    report["r4_manifest_sha256"] = new_manifest_sha
    report["site_quality_correction"] = {
        "from_manifest_sha256": EXPECTED_OLD_SHA,
        "site_count": changed, "fine_segments_scanned": segments,
        "method": manifest["source_quality_rule"],
        "elevation_water_level_and_fine_masks_unchanged": True}
    new_report = (json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    quality_tmp = quality_path.with_suffix(quality_path.suffix + ".tmp")
    manifest_tmp = manifest_path.with_suffix(".json.tmp")
    report_tmp = report_path.with_suffix(".json.tmp")
    quality_tmp.write_bytes(new_quality)
    manifest_tmp.write_bytes(new_manifest)
    report_tmp.write_bytes(new_report)
    os.replace(quality_tmp, quality_path)
    os.replace(manifest_tmp, manifest_path)
    os.replace(report_tmp, report_path)
    build.write_coverage_report(report)
    print(f"r4 Site quality corrected: {changed} Sites, {segments} fine masks; "
          f"manifest_sha256={new_manifest_sha}; elapsed={time.monotonic() - started:.1f}s",
          flush=True)


if __name__ == "__main__":
    main()
