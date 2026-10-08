# Taiwan fixed-geography atlas importer

This isolated importer builds fixed Taiwan geography without changing the project's current entry scene. RegionLab now defaults to the accepted `assets/region_lab/earth_tw_tm2_121_v1_r4/` package; the r2 baseline remains at `assets/region_lab/earth_tw_tm2_121_v1/`. The game reads packaged rasters; Python and raw archives are build-time dependencies only. Do not commit this task's files until the user asks.

## r2 baseline inputs

Download these pinned public archives into `assets/region_lab/earth_tw_tm2_121_v1/source/`:

| Local filename | Provider and URL | SHA-256 |
| --- | --- | --- |
| `moi_20m_taiwan_penghu_dem.zip` | [Ministry of the Interior, dataset 35430](https://data.gov.tw/dataset/35430), [archive](https://www.tgos.tw/MDE/VirtualDir_TC/Product/9981ede9-584a-4470-8c5c-dbe579d4ecb4/%E4%B8%8D%E5%88%86%E5%B9%85_%E5%85%A8%E5%8F%B0%E5%8F%8A%E6%BE%8E%E6%B9%96DEM.zip) | `66cd9ffc2da89982b530c4eca5d3d6f4ae295194dbec794259a55f5027ceaed9` |
| `gshhg-shp-2.3.7.zip` | [GSHHG 2.3.7 full-resolution L1 coastline](https://www.soest.hawaii.edu/pwessel/gshhg/), [archive](https://github.com/GenericMappingTools/gshhg-gmt/releases/download/2.3.7/gshhg-shp-2.3.7.zip) | `8dbbe7e071e77e9e75f2d639239099ebca8d5c16d6a07df8169729d49f15cf41` |

The MOI release is under [Taiwan Open Government Data License 1.0](https://data.gov.tw/license). GSHHG is LGPL. The exact source versions, coordinate references, transforms, and hashes are recorded in `manifest.json`. Raw downloads are ignored by Git to keep the runtime package compact.

## Rebuild the r2 baseline on Windows PowerShell

Use Python with the pinned dependencies in `requirements.txt`. For an isolated local installation:

```powershell
python -m pip install --target tools/region_lab/.tmp/deps -r tools/region_lab/requirements.txt
$env:PYTHONPATH = (Resolve-Path tools/region_lab/.tmp/deps).Path
python tools/region_lab/import_taiwan.py build
python tools/region_lab/import_taiwan.py verify
python tools/region_lab/import_taiwan.py report
```

`build` checks both archive SHA-256 values before reading them and aborts on conflicting overlapping DEM posts. `verify` checks every packaged file hash and raster size. `report` recomputes the original GSHHG Site classes and compares them with final availability by content scope. These are reproducibility commands, not permission to alter an accepted release; a rebuild changes the manifest hash and saved fixed-base identity.

## r2 package contract and limits

`manifest.json` points to `summary.u8` (200 m Site geography), `content_scope.u8` (200 m content group), and 20 m compressed height/level/water tiles. All rows run north to south in EPSG:3826. Each 200 m Site contains 100×100 gameplay cells of 2 m, with source height sampled or interpolated from 20 m posts. The horizontal projection's measured maximum 200 m/20 km scale error is in the manifest; 20 m height **does not** become 2 m measurement accuracy.

Summary values are 0 missing, 1 verified whole sea, 2 land, 3 inland water, and 4 mixed coast. Scope values are 0 outside content, 1 Taiwan main island and nearby islets, 2 Penghu, 3 Green Island, 4 Lanyu, 5 surrounding sea. Scope groups are editorial game content: they do not define legal or administrative boundaries. The named group anchors and inclusion distances are in the manifest. A Site marked land or mixed survives only if its full 12×12 source-post window for 102×102 two-metre gameplay cells is valid; source gaps stay Missing. Outside-content land such as the clipped Fujian coast retains its true geography but cannot be entered.

Gameplay heights are local 0–5 levels derived from 20 m absolute heights using a fixed 200 m-radius land-only background. Absolute elevation remains read-only metadata. Ocean uses a verified GSHHG whole-Site rule and never invents seabed height. This version does not infer river width or collapse distinct lakes into one water body; inland water is unimplemented and reported as zero. GSHHG 2017 and the MOI source differ along some coasts, so missing Sites in `coverage_report.json` are real source conflicts, not hidden as ocean. `coverage_report_r1.json` preserves the earlier candidate's limitations for comparison.

See `coverage_report.json` for exact per-island missing counts, halo rejections, representative coordinates, package bytes, and the retained east-coast counterexample. The source-level audit under `tools/region_lab/audit_real_atlas.py` and the separate Godot run are different acceptance checks.

## Isolated r3 coast-evidence trial — not adopted

The separate `assets/region_lab/earth_tw_tm2_121_v1_r3_trial/` keeps the same Site IDs but has its own `base_revision` and manifest hash. It **does not replace r2**. The ten pinned Copernicus GLO-30 DSM/WBM geocells are listed with exact URLs, byte counts and SHA-256 values in `copernicus_inputs.json`; download each to `tools/region_lab/.tmp/` under its listed filename before rebuilding. Copernicus data is used only to corroborate some GSHHG/MOI shoreline conflicts. Its EGM2008 DSM elevations are never merged into the MOI TWVD2001 gameplay height tiles. Include the Copernicus adapted-product notice in the trial manifest when redistributing the trial.

```powershell
$env:PYTHONPATH = (Resolve-Path tools/region_lab/.tmp/deps).Path
python tools/region_lab/import_taiwan.py build --trial
python tools/region_lab/import_taiwan.py verify --trial
python tools/region_lab/import_taiwan.py report --trial
python tools/region_lab/audit_trial_delta.py
python tools/region_lab/audit_coast_counterexample.py
```

The r3 manifest SHA-256 is `b9e08c76143c2ea6d46f98ab4cab5bd8f1b7a787923d8b21199f816ca519149f`. `trial_delta_audit.json` verifies that all 89,737,402 previously valid MOI land posts retain their exact height; all 681,939 new land posts have acceptance code 1, and no previously available Site is lost. Four named island groups gain 4,404 expandable Sites, but their actual current content scope still contains **14,601 Missing Sites** (Taiwan 12,783; Penghu 926; Green Island 263; Lanyu 629). The 8,941 figure in `coverage_report.json` uses only original GSHHG land/mixed Sites as its denominator and must not be presented as the full content gap. All 900,595 r3 Sites classed land/mixed in the named scope pass the complete 12×12 source-post/halo gate.

The trial is rejected as a release candidate after actual RegionLab GPU captures in `.visual_captures/region_lab/r3_trial_20260927_01/`. At Lanyu Site `[1545,12170]`, the source audit `coast_counterexample_lanyu.json` records every 20m MOI, Copernicus DSM/WBM and acceptance-code post: 21 posts are newly classified land while 23 adjacent posts are rejected by the 10m cross-datum height threshold. The resulting 20m square shoreline fragments become visible as rectangular patches in the 2m Site view. This cannot be repaired by presenting the 20m pixels as more precise 2m geography, smoothing the image without a source, or substituting Copernicus DSM absolute heights. At this rejection, r2 remained the fixed-data baseline with its reported coast gaps; r4's later vector-coast and marked-estimate work is separate.

## r4 vector coasts and explicit height estimates

The accepted manifest SHA-256 is `e3108aad1cbfd5118af08fd699ac03bf64d19b5bc9d186154dc9a5fea279f7b8`. Independent full-map audit `r4_full_audit_20260927_140942` passed all 914,075 active non-sea Sites and accounted for all 11,711 original r2 gaps: 7,193 recovered and 4,518 confirmed as sea by the pinned vector coast. Package size is 152,701,104 bytes. Godot contracts, real geography, visual inspection and the 100-cycle Vulkan UI acceptance `20260927_143934_365` passed; see `TAIWAN_REGION_MAP_PLAN.md` section 17 for exact conditions, measurements, preserved failures and scope.

`build_r4.py` writes the separate `assets/region_lab/earth_tw_tm2_121_v1_r4/` package. It keeps the coordinate contract and original r2 content coordinates, replaces the covered coastline with closed OSM polygons, and retains GSHHG external geography. `prepare_osm_sources.py` records the pinned Geofabrik extraction, OSM coastline node rings, original water-body identities, source timestamps, file hashes and licence. The frozen inputs are under `.tmp/osm_source/`; raw archives and Python dependencies remain build inputs.

The r4 height grid carries quality codes: 0 sea/no height, 1 retained MOI sample, 2 local MOI interpolation, 3 local MOI extrapolation, 4 explicit terrain estimate of unknown vertical accuracy. `r4_estimation.py` uses support from the same island, records the method and distance, and preserves original valid MOI land values. Copernicus relative shape is only an explicitly marked estimate. A complete playable grid is not a claim of complete measured elevation coverage.

To keep adjacent Region seams numerically identical, each global 20m post has one fixed 20km source-core owner; MOI and Copernicus cores are sampled once, then neighbouring halos copy those cores. Valid dry MOI samples in the pinned r2 manifest override GDAL nearest-pixel ties before r4 estimation and level derivation. The builder checks the exact r2 manifest SHA and records this post policy in r4. `test_r4_fixed_source.py` covers source overlap and the original tie counterexamples. Site quality conservatively includes the 12×12 source halo and any fine land or inland water over a coarse water post; a wholly sea Site still reports quality 0.

Vector coast and inland-water boundaries become 100×100 masks at the 2m gameplay resolution. Each mask contains uint32 water-body IDs: 0 dry land, 1 ocean, and named OSM source IDs from the manifest registry for inland water. The per-Region index addresses independently compressed Site segments; every file and segment has a SHA-256. Polygon holes survive, and intersected land cells preserve tiny islands with at most one 2m cell of shoreline expansion. Unknown salinity has `water_kind=4`; it cannot satisfy the existing freshwater-source rule.

The runtime validates source quality, body IDs, mask lengths and hashes, then samples the same masks for the Site and its halo. It keeps a bounded coarse-source cache and at most nine expanded fine masks. Ocean has no fabricated seabed height; valid support for a fine land cell over a coarse water post is marked estimated. Inland water must have a valid surface height. Original `TerrainData`, movement, renderer and `SiteStore` remain the owners of the resulting terrain and mutable state.

After full manifest validation, the runtime stores the water registry in compact kind/source/name columns with an ID index. `RegionData.get_water_body(id)` returns one body's metadata; the runtime manifest header does not retain the large `water_bodies` array. The on-disk manifest, source registry and saved manifest hash are unchanged. Sparse IDs remain supported without allocating an array up to the largest ID.

With the pinned r2 and Copernicus inputs already present and the dependencies above installed:

```powershell
python tools/region_lab/r4_estimation.py
python tools/region_lab/test_r4_fixed_source.py
python tools/region_lab/build_r4.py --sample-region 15,121
python tools/region_lab/build_r4.py
```

The sample writes only to the ignored `.tmp/r4_sample/` folder. The full build has an explicit execution bound and produces a candidate for independent validation. The fixed r2 gap inventory in `output/region_lab_real_acceptance/r2_gap_inventory.jsonl` retains all 11,711 old missing coordinates; a revised coastline may classify an old gap as sea, but scope shrinkage cannot count as recovery. Candidate acceptance, Godot results and any remaining limits are recorded in `TAIWAN_REGION_MAP_PLAN.md` section 17.

## Open the isolated viewer

In the Godot editor, open `scenes/region_lab/RegionLab.tscn` and run the current scene (F6). Selecting a Site now prepares its terrain thumbnail automatically. Use **查看所選附近地形** to zoom to the selected Site and progressively display the nearby 200 m tiles; then use **開啟所選 Site** to enter. Returning restores the previous map position and zoom.

These thumbnails come from the same `RegionData.make_terrain_data` result used for entry, including the original height levels, water, cliffs and ramps. They are simplified terrain rasters, not screenshots of the full renderer. The viewer keeps at most 32 textures (300×300 RGBA8 each), runs one source worker at a time, and creates no actors or mutable Site state just for a preview. The broad Taiwan overview still uses the compact geography summary. Source failures clear the selected thumbnail and display an error.

From the project directory on this workstation:

```powershell
& 'C:\Users\Nekki\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe' --path . --debug --rendering-driver vulkan 'res://scenes/region_lab/RegionLab.tscn'
```

Vulkan is a per-process option for this standalone viewer. The formal TerrainLab entry and project renderer settings stay unchanged. The documented performance results apply to the named GPU, resolution and driver; the original D3D12/VSync stall is retained in the plan's failure record.

Keep `--debug` enabled for verification so GDScript reload warnings reach the log. Check `WARNING:` / `GDScript::reload` explicitly as well as the verifier result: a helper PASS alone does not establish zero warnings. For a full editor import, use the unchanged verifier in headless mode with `--editor --debug --import`; the short editor mode can exit before the filesystem scan finishes.

Ramps now use connected ground surfaces and height shading instead of arrows. Consecutive ramps share their landings; parallel ramps share the full opening. Both the thumbnail and the original TerrainRenderer use the same opening calculation. Grass repeats every 20 cells on both ground and ramp surfaces, so each 100-cell Site contains five complete repeats. Fixed geography retains only the outer halo's level/water samples for visual joins; the existing boundary refresh updates these samples alongside saved neighbouring terrain changes. Height levels and legal movement edges remain authoritative.

`scripts/tests/terrain_ramp_continuity_visual_test.gd` is a bounded GPU check. Run it with `--debug --rendering-driver vulkan --script res://scripts/tests/terrain_ramp_continuity_visual_test.gd -- --run=<unique-name>` through the canonical verifier. It saves ordinary/progressive renderer comparisons, four slope directions, consecutive/wide/turning slopes, forbidden cliffs, real Yushan terrain and a split-Site opening comparison under `output/terrain_ramp_continuity/`.

## Other surveyed sources

Other surveyed sources remain outside r4. The [NLSC WFS layer list](https://maps.nlsc.gov.tw/S09SOA/pro/Wfs_ajax_main.jsp) names `EMAP_COASTLINE`, `EMAP_RIVERA` and `EMAP_WATERA`, but states the service requires approval for public agencies and limits each request to a 1km-square area. The [national ocean-data portal](https://nodass.namr.gov.tw/newsInfo?id=245) announces an updated 113-year natural/artificial coast vector with download after member login; it has not been acquired or validated for coverage and redistribution. The local exploratory 114-year NLSC 1:25,000 ZIP spans only 32 sheets, with nonempty coast features confined to approximately 120.02–120.17°E, 23.00–23.55°N, so it cannot settle Lanyu or the whole atlas. Within the pinned GSHHG archive, L2–L4 contain zero lake polygons in the atlas longitude/latitude bounding box; WDBII full-resolution L05 has 23 river **lines** there, with no water widths. None is silently turned into gameplay water.
