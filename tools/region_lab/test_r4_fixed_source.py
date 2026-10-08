"""Bounded source-post consistency checks for the fixed r4 atlas builder."""

from contextlib import ExitStack
import numpy as np
import rasterio

import import_taiwan as atlas
from build_r4 import EST_HALO, FixedSourceReader, assemble_fixed_cores


def main() -> None:
    def synthetic_core(rx: int, ry: int) -> np.ndarray:
        xx = rx * 1000 + np.arange(1000, dtype=np.int64)
        yy = (ry + 1) * 1000 - 1 - np.arange(1000, dtype=np.int64)
        return yy[:, None] * 100000 + xx[None, :]

    synthetic = assemble_fixed_cores(synthetic_core, -2, -3, 61, np.int64, -1)
    assert synthetic.shape == (1122, 1122)
    assert synthetic[0, 0] == synthetic_core(-3, -2)[939, 939]
    assert synthetic[61, 61] == synthetic_core(-2, -3)[0, 0]
    assert synthetic[-1, -1] == synthetic_core(-1, -4)[60, 60]

    atlas.verify_source(atlas.DEM_ARCHIVE, atlas.DEM_SHA)
    atlas.extract_inputs()
    with ExitStack() as stack:
        main_dem = stack.enter_context(rasterio.open(atlas.TEMP / "dem_20m.tif"))
        penghu_dem = stack.enter_context(rasterio.open(atlas.TEMP / "phDEM_20m_121.tif"))
        _, cop_sources = atlas.copernicus_sources(stack)
        reader = FixedSourceReader(main_dem, penghu_dem, cop_sources)
        for rx, ry, horizontal in ((12, 125, True), (15, 121, False)):
            a = reader.window(rx, ry, EST_HALO)
            b = reader.window(rx + int(horizontal), ry + int(not horizontal), EST_HALO)
            if horizontal:
                left = [x[:, 1000:] for x in a]
                right = [x[:, :122] for x in b]
            else:
                left = [x[:122, :] for x in a]
                right = [x[1000:, :] for x in b]
            for same_a, same_b in zip(left, right):
                assert np.array_equal(same_a, same_b, equal_nan=True)
        for easting, northing, expected in ((250810, 2519990, 820),
                                            (250850, 2519970, 820),
                                            (250790, 2539990, 2194)):
            rx, ry = easting // 20000, northing // 20000
            source = reader.window(rx, ry, EST_HALO)[0]
            col = EST_HALO + (easting - rx * 20000) // 20
            row = EST_HALO + 999 - (northing - ry * 20000) // 20
            assert int(source[row, col]) == expected
        assert sum(reader.r2_pinned_changed.values()) > 0
        print("r4 fixed-source contract PASS; pinned-window-ties=",
              sum(reader.r2_pinned_changed.values()),
              "Cop-overlap-conflicts=", sum(reader.cop_conflicts.values()))


if __name__ == "__main__":
    main()
