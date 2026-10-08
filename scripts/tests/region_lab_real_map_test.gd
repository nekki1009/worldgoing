extends SceneTree

# Run with --mode=geography, then separately with --mode=performance.
# This reads the packaged atlas; the synthetic contract has its own test.
const Atlas = preload("res://scripts/region_lab/region_data.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const Slot = preload("res://scripts/region_lab/region_save_slot.gd")
const NAMES := ["missing_data", "sea", "land", "inland_water", "mixed"]

var _started := false
var _finished := false
var _failures: Array[String] = []
var _report: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _process(_delta: float) -> bool:
	if _started and not _finished:
		printerr("REGION_REAL_MAP_INTERRUPTED: ", JSON.stringify(_report))
		quit(1)
	return false

func _run() -> void:
	_started = true
	var mode := "geography"
	var manifest_path := Atlas.DEFAULT_MANIFEST
	var focus_site := Vector2i(1545, 12170)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--manifest="):
			manifest_path = argument.trim_prefix("--manifest=")
		elif argument.begins_with("--site="):
			var parts := argument.trim_prefix("--site=").split(",")
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				focus_site = Vector2i(int(parts[0]), int(parts[1]))
			else:
				_failures.append("invalid_site_argument")
	var source := Atlas.new()
	var loaded: Dictionary = source.load_manifest(manifest_path)
	if not loaded.ok:
		_failures.append("load_manifest:%s" % str(loaded.get("code", "UNKNOWN")))
		_finish()
		return
	_report["manifest_sha256"] = source.manifest_hash
	_report["manifest_path"] = manifest_path
	_report["atlas_id"] = str(source.manifest.atlas_id)
	_report["base_revision"] = str(source.manifest.base_revision)
	_report["mode"] = mode
	if mode == "geography":
		_geography(source)
	elif mode == "sample":
		_sample_region(source, focus_site)
	elif mode == "performance":
		_performance(source)
	else:
		_failures.append("unknown_mode:" + mode)
	_finish()

func _sample_region(source: RegionData, site: Vector2i) -> void:
	var summary := source.get_site_summary(site.x, site.y)
	var started := Time.get_ticks_usec()
	var opened := source.make_terrain_data(site.x, site.y)
	_report["focus_site"] = [site.x, site.y]
	_report["summary"] = summary
	_report["open_code"] = str(opened.get("code", "UNKNOWN"))
	_report["load_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	_check(summary.ok and summary.has_terrain and summary.class_id == 4,
		"r4_sample_is_not_mixed_content")
	_check(opened.ok, "r4_sample_site_not_expandable:" + str(opened.get("code", "UNKNOWN")))
	if not opened.ok:
		return
	var data: TerrainData = opened.data
	_check(data.site.is_empty(), "r4_sample_created_mutable_site")
	if source.resource_manifest_hash.is_empty():
		_check(data.resource_base.is_empty(), "geography_only_sample_invented_resources")
	else:
		_check(opened.base.get("resource_layer_sha256") == source.resource_manifest_hash \
			and opened.base.get("resource_fingerprint") == JSON.stringify(data.resource_base, "", true, true).sha256_text(),
			"r4_sample_resources_not_pinned")
	var quality: PackedByteArray = opened.metadata.source_quality_codes
	var altitude: PackedFloat32Array = opened.metadata.absolute_elevation_m
	var land := 0
	var sea := 0
	var estimated_land := 0
	var transitions := 0
	var sub_20m_transitions := 0
	var invalid_land := 0
	var invalid_ocean := 0
	var invalid_inland := 0
	var sampled_disagreements := 0
	for y: int in range(100):
		for x: int in range(100):
			var index := data.index(Vector2i(x, y))
			var water_kind := int(data.water_kind[index])
			if water_kind == 0:
				land += 1
				if quality[index] >= 2:
					estimated_land += 1
				if not is_finite(altitude[index]) or quality[index] not in [1, 2, 3, 4]:
					invalid_land += 1
			elif water_kind == 2:
				sea += 1
				if data.water_body[index] != 1 or not is_nan(altitude[index]):
					invalid_ocean += 1
			else:
				if water_kind not in [1, 3, 4] or data.water_body[index] < 2:
					invalid_inland += 1
			if x > 0 and data.water_kind[index - 1] != water_kind:
				transitions += 1
				if x % 10 != 0:
					sub_20m_transitions += 1
			if y > 0 and data.water_kind[index - 100] != water_kind:
				transitions += 1
				if y % 10 != 0:
					sub_20m_transitions += 1
			if x % 10 == 0 and y % 10 == 0 or x in [0, 99] and y in [0, 99]:
				var sample := source.sample_meters(site.x * 200.0 + x * 2.0 + 1.0,
					site.y * 200.0 + (99 - y) * 2.0 + 1.0)
				if not sample.ok or int(sample.water_kind) != water_kind \
						or data.water_body[index] != (int(sample.water_body) if water_kind > 0 else -1) \
						or quality[index] != int(sample.source_quality_code):
					sampled_disagreements += 1
	_report["fine_cells"] = {"land": land, "ocean": sea, "estimated_land": estimated_land,
		"water_transitions": transitions, "sub_20m_transitions": sub_20m_transitions,
		"source_quality_site": summary.source_quality_code,
		"manifest_mask_site": summary.class_id, "invalid_land": invalid_land,
		"invalid_ocean": invalid_ocean, "invalid_inland": invalid_inland,
		"sampled_disagreements": sampled_disagreements}
	_check(land > 0 and sea > 0 and transitions > 0 and sub_20m_transitions > 0
		and estimated_land > 0,
		"r4_sample_lost_coast_or_estimate")
	_check(invalid_land == 0 and invalid_ocean == 0 and invalid_inland == 0
		and sampled_disagreements == 0, "r4_sample_cell_contract")
	_check(opened.base.terrain_fingerprint == data.fingerprint(), "r4_sample_base_fingerprint")
	_check(int(source.cache_stats().bytes) <= Atlas.MAX_CACHE_BYTES, "r4_sample_cache_limit")
	_report["cache"] = source.cache_stats()
	_report["scope"] = "One packaged r4 coastal Site through RegionData and TerrainData; not whole-atlas coverage or GPU proof"

func _geography(source: RegionData) -> void:
	var overview: Dictionary = source.get_overview()
	if not overview.ok:
		_failures.append("overview:%s" % str(overview.get("code", "UNKNOWN")))
		return
	var width: int = int(overview.width)
	var height: int = int(overview.height)
	var classes: PackedByteArray = overview.classes
	_check(width > 0 and height > 0 and classes.size() == width * height, "invalid_summary_shape")
	if classes.size() != width * height:
		return
	var counts := [0, 0, 0, 0, 0]
	for kind: int in classes:
		if kind >= 0 and kind < counts.size():
			counts[kind] += 1
		else:
			_failures.append("unknown_summary_class:%d" % kind)
	var actual_counts := {}
	for index: int in range(NAMES.size()):
		actual_counts[NAMES[index]] = counts[index]
	_report["summary"] = {"sites": [width, height], "classes": actual_counts}
	for name: String in NAMES:
		_check(int(actual_counts[name]) == int(source.manifest.summary_counts.get(name, -1)), "summary_count_mismatch:" + name)
	_check(float(source.manifest.get("max_measured_projection_scale_error", INF)) <= 0.001,
		"declared_projection_scale_error_over_0.1_percent")
	var source_ids := {}
	for item: Dictionary in source.manifest.get("sources", []):
		source_ids[str(item.get("id", ""))] = item
	var r4_source := str(source.manifest.base_revision).contains("r4")
	if r4_source:
		_check(source_ids.has("moi_dtm_35430") and source_ids.has("osm_coast_20260927")
			and source_ids.has("osm_water_20260927")
			and source_ids.has("copernicus_glo30_2021_relative_shape"), "r4_source_provenance_missing")
	else:
		_check(source_ids.has("moi_dtm_35430") and source_ids.has("gshhg_2_3_7_full_l1"), "source_provenance_missing")
	if source_ids.has("moi_dtm_35430"):
		_check(not str(source_ids.moi_dtm_35430.get("vertical_datum", "")).is_empty(), "vertical_datum_missing")
	var previews := {}
	for entry: Dictionary in source.manifest.get("preview_sites", []):
		previews[str(entry.get("label", ""))] = entry
	var sample_report: Array[Dictionary] = []
	var yushan: Dictionary = {}
	var taipei: Dictionary = {}
	for label: String in ["Taipei", "Yushan", "East coast", "Penghu", "Green Island", "Lanyu"]:
		if not previews.has(label):
			_failures.append("preview_missing:" + label)
			continue
		var site: Array = previews[label].site
		var address := Vector2i(int(site[0]), int(site[1]))
		var summary := source.get_site_summary(address.x, address.y)
		var start := Time.get_ticks_usec()
		var opened := source.make_terrain_data(address.x, address.y)
		var sample := {"name": label, "site": site, "summary": str(summary.get("status", "invalid")),
			"source_quality_code": int(summary.get("source_quality_code", -1)),
			"open_code": str(opened.get("code", "UNKNOWN")), "load_ms": (Time.get_ticks_usec() - start) / 1000.0}
		if opened.ok:
			var metadata: Dictionary = opened.metadata
			sample["land_cells"] = metadata.land_cells
			sample["water_cells"] = metadata.water_cells
			sample["estimated_elevation_cells"] = metadata.get("estimated_elevation_cells", 0)
			sample["region"] = [Grid.region_of(address).x, Grid.region_of(address).y]
			if r4_source:
				_check(int(summary.get("source_quality_code", 0)) in [1, 2, 3, 4],
					"r4_preview_quality_unlabelled:" + label)
			_check(opened.base.terrain_fingerprint == opened.data.fingerprint(), "base_fingerprint:" + label)
			_check(opened.metadata.absolute_elevation_m.size() == 10000, "absolute_elevation_size:" + label)
			if label == "Yushan":
				yushan = opened
			elif label == "Taipei":
				taipei = opened
		else:
			_failures.append("source_gap_preview:%s:%s" % [label, sample.open_code])
		sample_report.append(sample)
	_report["preview_sites"] = sample_report
	var previous_coast_site := Vector2i(1560, 13264)
	var previous_coast_summary := source.get_site_summary(previous_coast_site.x, previous_coast_site.y)
	var previous_coast_open := source.make_terrain_data(previous_coast_site.x, previous_coast_site.y)
	_report["previous_east_coast_gap"] = {"site": [previous_coast_site.x, previous_coast_site.y],
		"summary_status": str(previous_coast_summary.get("status", previous_coast_summary.get("code", "UNKNOWN"))),
		"open_code": str(previous_coast_open.get("code", "UNKNOWN")),
		"historical_r1_open_code": "MISSING_DATA"}
	var outside_site := Vector2i(443, 12829)
	var outside_summary := source.get_site_summary(outside_site.x, outside_site.y)
	var outside_open := source.make_terrain_data(outside_site.x, outside_site.y)
	_report["outside_content"] = {"site": [outside_site.x, outside_site.y],
		"geography_class": outside_summary.get("class_id", -1),
		"status": outside_summary.get("status", outside_summary.get("code", "UNKNOWN")),
		"open_code": outside_open.get("code", "UNKNOWN")}
	_check(outside_summary.ok and outside_summary.status == "outside_content" and not outside_summary.has_terrain,
		"outside_land_exposed_as_terrain")
	_check(not outside_open.ok and outside_open.code == "OUTSIDE_CONTENT", "outside_land_opened")
	if not yushan.is_empty():
		_mountain(yushan)
	if not taipei.is_empty():
		_save_slot_real(source, taipei)
	_coast(source, overview, previews)
	if r4_source:
		_r4_water_body(source)
	_region_corner(source, overview, previews)
	var sea_site := _find_sea(source, overview)
	if sea_site == Vector2i(-1, -1):
		_failures.append("no_verified_pure_sea_site")
	else:
		var sea := source.make_terrain_data(sea_site.x, sea_site.y)
		_check(sea.ok and sea.metadata.water_cells == 10000 and sea.data.spawn_cell == Vector2i(-1, -1), "pure_sea_created_land")
		if sea.ok:
			_check(sea.data.site.is_empty(), "pure_sea_initialized_site")
		_report["pure_sea_site"] = [sea_site.x, sea_site.y]
	_check(int(source.cache_stats().tiles) <= Atlas.MAX_CACHE_TILES and int(source.cache_stats().bytes) <= Atlas.MAX_CACHE_BYTES,
		"cache_limit")
	_report["cache"] = source.cache_stats()
	_report["scope"] = "Packaged atlas API and original TerrainData movement; renderer/GPU and exhaustive land coverage require separate checks"

func _r4_water_body(source: RegionData) -> void:
	# Frozen OSM water polygon spanning this Site boundary. SiteRuntime alone
	# decides whether a named water kind may satisfy a freshwater request.
	var body_id := 7433
	var body: Dictionary = source.get_water_body(body_id)
	_check(int(body.get("id", -1)) == body_id and str(body.get("source_id", "")) == "way/1263181010",
		"r4_cross_site_water_body_registry_changed")
	_check(int(body.get("kind", -1)) == 4, "r4_unknown_salinity_marked_fresh")
	if body.is_empty():
		return
	var west_site := Vector2i(1097, 12194)
	var east_site := Vector2i(1098, 12194)
	var west_summary := source.get_site_summary(west_site.x, west_site.y)
	var east_summary := source.get_site_summary(east_site.x, east_site.y)
	var west := source.make_terrain_data(west_site.x, west_site.y)
	var east := source.make_terrain_data(east_site.x, east_site.y)
	_check(west_summary.ok and east_summary.ok and west_summary.content_scope == 1
		and east_summary.content_scope == 1 and west_summary.class_id == 4
		and east_summary.class_id == 4, "r4_cross_site_water_scope_or_class")
	_check(west.ok and east.ok, "r4_cross_site_water_not_expandable")
	if not west.ok or not east.ok:
		return
	var matching_edges := 0
	var invalid_height := 0
	var unknown_shore := 0
	var unknown_as_fresh := 0
	for row: int in range(100):
		var wi: int = west.data.index(Vector2i(99, row))
		var ei: int = east.data.index(Vector2i(0, row))
		if west.data.water_body[wi] == body_id and east.data.water_body[ei] == body_id:
			matching_edges += 1
	for opened: Dictionary in [west, east]:
		var data: TerrainData = opened.data
		var heights: PackedFloat32Array = opened.metadata.absolute_elevation_m
		for i: int in range(10000):
			if data.water_body[i] == body_id:
				if data.water_kind[i] != 4 or not is_finite(heights[i]):
					invalid_height += 1
			elif data.is_terrain_walkable(data.cell_from_index(i)) \
					and SiteRuntime.adjacent_water(data, [i], 4) == "water:%d" % body_id:
				unknown_shore += 1
				if SiteRuntime.adjacent_water(data, [i], 1) == "water:%d" % body_id:
					unknown_as_fresh += 1
	_report["r4_cross_site_water"] = {"source_id": "way/1263181010", "body_id": body_id,
		"kind": 4, "west_site": [west_site.x, west_site.y],
		"east_site": [east_site.x, east_site.y], "matching_edge_cells": matching_edges,
		"water_cells_invalid_height_or_kind": invalid_height,
		"unknown_shore_cells": unknown_shore, "unknown_as_fresh_cells": unknown_as_fresh}
	_check(matching_edges > 0 and invalid_height == 0 and unknown_as_fresh == 0,
		"r4_cross_site_unknown_water_contract")
	var slot := Slot.new()
	var map_open := slot.open_map(source, "r4_water_%d" % Time.get_ticks_usec(), "slot")
	_check(map_open.ok, "r4_water_slot_open_failed")
	if not map_open.ok:
		return
	var first := slot.open_site(west_site)
	_check(first.ok and first.interactive, "r4_water_site_not_interactive")
	if not first.ok or not first.interactive:
		return
	var saved := slot.save_site(first.data)
	var reread: Dictionary = slot.open_site(west_site) if saved.ok else saved
	var retained := 0
	if reread.ok:
		for i: int in range(10000):
			if reread.data.water_kind[i] == 4 and reread.data.water_body[i] == body_id:
				retained += 1
	_report.r4_cross_site_water["save_roundtrip"] = saved.ok and reread.ok
	_report.r4_cross_site_water["named_water_cells_after_reload"] = retained
	_check(saved.ok and reread.ok and retained > 0 and reread.data.fingerprint() == first.data.fingerprint(),
		"r4_water_identity_lost_on_save_reload")

func _save_slot_real(source: RegionData, taipei: Dictionary) -> void:
	var site := Vector2i(1535, 13847)
	var slot := Slot.new()
	var opened := slot.open_map(source, "real_acceptance_%d" % Time.get_ticks_usec(), "slot")
	if not opened.ok:
		_failures.append("real_save_slot_open:%s" % str(opened.get("code", "UNKNOWN")))
		return
	var first := slot.open_site(site)
	if not first.ok or not bool(first.get("interactive", false)):
		_failures.append("real_save_slot_site:%s" % str(first.get("code", "NOT_INTERACTIVE")))
		return
	var original_fingerprint: String = first.data.fingerprint()
	_check(original_fingerprint == taipei.data.fingerprint(), "real_slot_changed_base_terrain")
	var saved := slot.save_site(first.data)
	if not saved.ok:
		_failures.append("real_save_slot_write:%s" % str(saved.get("code", "UNKNOWN")))
		return
	var second := slot.open_site(site)
	if not second.ok:
		_failures.append("real_save_slot_read:%s" % str(second.get("code", "UNKNOWN")))
		return
	var pin_path: String = slot.folder.path_join("manifest.json")
	var pin: Variant = JSON.parse_string(FileAccess.get_file_as_string(pin_path))
	_check(pin is Dictionary and pin.get("manifest_sha256") == source.manifest_hash and pin.get("base_revision") == source.manifest.base_revision,
		"real_save_slot_pin")
	_check(second.data.fingerprint() == original_fingerprint, "real_save_slot_terrain_changed")
	_check(second.data.site.get("id", "") == first.data.site.get("id", ""), "real_save_slot_identity_changed")
	_report["real_save_slot"] = {"site": [site.x, site.y], "pin_sha256": str(pin.get("manifest_sha256", "")) if pin is Dictionary else "INVALID",
		"fingerprint": original_fingerprint, "roundtrip": second.data.fingerprint() == original_fingerprint,
		"scope": "Fresh isolated helper user-data world; original SiteStore owner"}

func _mountain(opened: Dictionary) -> void:
	var data: TerrainData = opened.data
	var altitude: PackedFloat32Array = opened.metadata.absolute_elevation_m
	var peak := -1
	var peak_m := -INF
	for i: int in range(altitude.size()):
		if data.is_walkable(data.cell_from_index(i)) and is_finite(altitude[i]) and altitude[i] > peak_m:
			peak = i
			peak_m = altitude[i]
	if peak < 0:
		_failures.append("yushan_no_measured_peak")
		return
	var summit := data.cell_from_index(peak)
	var reached := {summit: true}
	var queue: Array[Vector2i] = [summit]
	var head := 0
	var lowest := peak
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var i := data.index(cell)
		if is_finite(altitude[i]) and altitude[i] < altitude[lowest]:
			lowest = i
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if not reached.has(next) and data.can_step(cell, next):
				reached[next] = true
				queue.append(next)
	var approach := data.cell_from_index(lowest)
	var route := data.path_between(approach, summit)
	_report["yushan_summit"] = {"peak_cell": [summit.x, summit.y], "peak_elevation_m": peak_m,
		"approach_cell": [approach.x, approach.y], "approach_elevation_m": altitude[lowest],
		"approach_level": int(data.height_levels[lowest]), "peak_level": int(data.height_levels[peak]),
		"reachable_cells": queue.size(), "route_steps": route.size()}
	_check(peak_m >= 3800.0, "yushan_peak_not_in_test_site")
	_check(peak_m > altitude[lowest] and int(data.height_levels[peak]) > int(data.height_levels[lowest]) and not route.is_empty(),
		"yushan_summit_not_reachable_from_lower_level")
	if not route.is_empty():
		var current := approach
		for step: Vector2i in route:
			_check(data.can_step(current, step), "yushan_route_has_illegal_step")
			current = step

func _coast(source: RegionData, overview: Dictionary, previews: Dictionary) -> void:
	var center: Vector2i = Vector2i(int(previews["East coast"].site[0]), int(previews["East coast"].site[1])) if previews.has("East coast") else Vector2i(1500, 13000)
	var candidates := _matching_sites(overview, 4, center).slice(0, 32)
	if str(source.manifest.base_revision).contains("r4"):
		candidates.append(Vector2i(1545, 12170)) # Frozen Lanyu land/ocean positive if the nearest east-coast mixed cells are inland water.
	var tried: Array[Dictionary] = []
	for candidate: Vector2i in candidates:
		var result := source.make_terrain_data(candidate.x, candidate.y)
		if not result.ok:
			tried.append({"site": [candidate.x, candidate.y], "code": result.code})
			continue
		if int(result.metadata.land_cells) == 0 or int(result.metadata.water_cells) == 0:
			tried.append({"site": [candidate.x, candidate.y], "code": "NOT_BOTH_SURFACES"})
			continue
		var sea_cells := 0
		for i: int in range(10000):
			if result.data.water_kind[i] == 2:
				sea_cells += 1
				_check(result.data.water_body[i] == 1, "coast_ocean_body_id")
		if sea_cells == 0:
			tried.append({"site": [candidate.x, candidate.y], "code": "INLAND_WATER_MIXED",
				"land_cells": result.metadata.land_cells, "water_cells": result.metadata.water_cells})
			continue
		_report["mixed_coast"] = {"site": [candidate.x, candidate.y], "land_cells": result.metadata.land_cells,
			"water_cells": result.metadata.water_cells, "ocean_cells": sea_cells, "rejected_nearby": tried}
		return
	_report["mixed_coast"] = {"rejected_nearby": tried}
	_failures.append("no_expandable_land_ocean_coast_in_test_candidates")

func _region_corner(source: RegionData, overview: Dictionary, previews: Dictionary) -> void:
	var center := Vector2i(int(previews["Yushan"].site[0]), int(previews["Yushan"].site[1])) if previews.has("Yushan") else Vector2i(1300, 13000)
	var west: int = int(source.manifest.summary.site_origin[0])
	var south: int = int(source.manifest.summary.site_origin[1])
	var candidates: Array[Vector2i] = []
	for sy: int in range(Grid.floor_div(south, 100) * 100 + 100, south + int(overview.height), 100):
		for sx: int in range(Grid.floor_div(west, 100) * 100 + 100, west + int(overview.width), 100):
			var corner := Vector2i(sx, sy)
			var valid := true
			for offset: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i.ZERO]:
				valid = valid and _class_at(overview, west, south, corner + offset) == 2
			if valid:
				candidates.append(corner)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.distance_squared_to(center) < b.distance_squared_to(center))
	var rejected: Array[Dictionary] = []
	for corner: Vector2i in candidates.slice(0, mini(8, candidates.size())):
		var sw := source.make_terrain_data(corner.x - 1, corner.y - 1)
		var se := source.make_terrain_data(corner.x, corner.y - 1)
		var nw := source.make_terrain_data(corner.x - 1, corner.y)
		var ne := source.make_terrain_data(corner.x, corner.y)
		if not (sw.ok and se.ok and nw.ok and ne.ok):
			rejected.append({"corner": [corner.x, corner.y], "codes": [sw.get("code"), se.get("code"), nw.get("code"), ne.get("code")]})
			continue
		var edge_checks := 0
		for i: int in range(100):
			if _edge(sw.data, Vector2i(99, i), se.data, Vector2i(0, i), 1): edge_checks += 1
			if _edge(nw.data, Vector2i(99, i), ne.data, Vector2i(0, i), 1): edge_checks += 1
			if _edge(sw.data, Vector2i(i, 0), nw.data, Vector2i(i, 99), 0): edge_checks += 1
			if _edge(se.data, Vector2i(i, 0), ne.data, Vector2i(i, 99), 0): edge_checks += 1
		var reverse_ne := source.make_terrain_data(corner.x, corner.y)
		var reverse_sw := source.make_terrain_data(corner.x - 1, corner.y - 1)
		_check(reverse_ne.ok and reverse_sw.ok and reverse_ne.data.fingerprint() == ne.data.fingerprint() and reverse_sw.data.fingerprint() == sw.data.fingerprint(), "opposite_load_order_changed_sites")
		_report["four_region_corner"] = {"corner_site": [corner.x, corner.y], "edge_checks": edge_checks,
			"regions": [[Grid.region_of(Vector2i(corner.x - 1, corner.y - 1)).x, Grid.region_of(Vector2i(corner.x - 1, corner.y - 1)).y],
				[Grid.region_of(corner).x, Grid.region_of(corner).y]], "rejected_nearby": rejected}
		_check(edge_checks == 400, "four_region_corner_edge_mismatch")
		return
	_report["four_region_corner"] = {"rejected_nearby": rejected}
	_failures.append("no_expandable_four_region_corner_near_yushan")

func _edge(a: TerrainData, from: Vector2i, b: TerrainData, to: Vector2i, direction: int) -> bool:
	var ai := a.index(from)
	var bi := b.index(to)
	var opposite := (direction + 2) % 4
	var difference := int(a.height_levels[ai]) - int(b.height_levels[bi])
	var dry := a.water_kind[ai] == 0 and b.water_kind[bi] == 0
	var ramp := (a.ramp_edges[ai] & (1 << direction)) != 0
	if ramp and (not dry or absi(difference) != 1):
		return false
	if a.cliff_drops[ai * 4 + direction] != maxi(difference, 0) or b.cliff_drops[bi * 4 + opposite] != maxi(-difference, 0):
		return false
	if ((a.ramp_edges[ai] >> direction) & 1) != int(ramp) or ((b.ramp_edges[bi] >> opposite) & 1) != int(ramp):
		return false
	return a.water_kind[ai] != 2 or b.water_kind[bi] != 2 or a.water_body[ai] == b.water_body[bi]

func _performance(source: RegionData) -> void:
	var previews: Array = source.manifest.get("preview_sites", [])
	var sites: Array[Vector2i] = []
	for label: String in ["Taipei", "Yushan", "Penghu", "Green Island", "Lanyu"]:
		for entry: Dictionary in previews:
			if entry.get("label") == label:
				sites.append(Vector2i(int(entry.site[0]), int(entry.site[1])))
	if sites.size() != 5:
		_failures.append("performance_preview_sites_missing")
		return
	var cold: Array[int] = []
	var warm: Array[int] = []
	var memory_start := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var max_open_us := 0
	for i: int in range(100):
		var fresh := i % 5 == 0
		if fresh:
			source.clear_cache()
		var site := sites[Grid.floor_div(i, 5) % sites.size()]
		var start := Time.get_ticks_usec()
		var opened := source.make_terrain_data(site.x, site.y)
		var elapsed := Time.get_ticks_usec() - start
		if not opened.ok:
			_failures.append("open_%d:%s" % [i, str(opened.get("code", "UNKNOWN"))])
			break
		if fresh:
			cold.append(elapsed)
		else:
			warm.append(elapsed)
		max_open_us = maxi(max_open_us, elapsed)
		var cache: Dictionary = source.cache_stats()
		if int(cache.tiles) > Atlas.MAX_CACHE_TILES or int(cache.bytes) > Atlas.MAX_CACHE_BYTES:
			_failures.append("cache_limit_at_switch_%d" % i)
			break
		if i % 20 == 19:
			print("REGION_REAL_MAP_PROGRESS switches=", i + 1)
	var memory_end := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	_report["performance"] = {"switches": cold.size() + warm.size(), "cold_samples": cold.size(),
		"warm_samples": warm.size(), "cold_p95_ms": _p95_ms(cold), "warm_p95_ms": _p95_ms(warm),
		"max_open_ms": max_open_us / 1000.0, "static_memory_before_bytes": memory_start,
		"static_memory_after_bytes": memory_end, "static_memory_delta_bytes": memory_end - memory_start,
		"cache": source.cache_stats(), "scope": "Synchronous source.make_terrain_data only; no renderer upload, UI frame, or GPU"}
	_check(cold.size() + warm.size() == 100, "incomplete_100_switches")
	_check(_p95_ms(cold) <= 2000.0, "cold_p95_over_2_seconds")
	_check(_p95_ms(warm) <= 500.0, "warm_p95_over_0.5_seconds")
	_check(memory_end - memory_start <= 16 * 1024 * 1024, "static_memory_growth_over_16_mib")

func _matching_sites(overview: Dictionary, target: int, center: Vector2i) -> Array[Vector2i]:
	var west: int = Grid.floor_div(int(overview.bounds_m[0]), 200)
	var south: int = Grid.floor_div(int(overview.bounds_m[1]), 200)
	var ranked: Array[Dictionary] = []
	for row: int in range(int(overview.height)):
		for column: int in range(int(overview.width)):
			if overview.classes[row * int(overview.width) + column] == target:
				var site := Vector2i(west + column, south + int(overview.height) - 1 - row)
				ranked.append({"site": site, "distance": site.distance_squared_to(center)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	var result: Array[Vector2i] = []
	for entry: Dictionary in ranked:
		result.append(entry.site)
	return result

func _class_at(overview: Dictionary, west: int, south: int, site: Vector2i) -> int:
	var x := site.x - west
	var y := int(overview.height) - 1 - (site.y - south)
	return int(overview.classes[y * int(overview.width) + x]) if x >= 0 and y >= 0 and x < int(overview.width) and y < int(overview.height) else 0

func _find_sea(source: RegionData, overview: Dictionary) -> Vector2i:
	var west: int = int(source.manifest.summary.site_origin[0])
	var south: int = int(source.manifest.summary.site_origin[1])
	for row: int in range(100, int(overview.height) - 100, 100):
		for column: int in range(100, int(overview.width) - 100, 100):
			var site := Vector2i(west + column, south + int(overview.height) - 1 - row)
			var all_sea := true
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					all_sea = all_sea and _class_at(overview, west, south, site + Vector2i(dx, dy)) == 1
			if not all_sea:
				continue
			var summary := source.get_site_summary(site.x, site.y)
			if summary.ok and not summary.has_elevation:
				return site
	return Vector2i(-1, -1)

func _p95_ms(values: Array[int]) -> float:
	if values.is_empty():
		return INF
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	return sorted[ceili(sorted.size() * 0.95) - 1] / 1000.0

func _check(condition: bool, code: String) -> void:
	if not condition:
		_failures.append(code)

func _finish() -> void:
	_report["failures"] = _failures
	_finished = true
	if _failures.is_empty():
		print("REGION_REAL_MAP_PASS ", JSON.stringify(_report))
		quit(0)
	else:
		printerr("REGION_REAL_MAP_FAIL ", JSON.stringify(_report))
		quit(1)
