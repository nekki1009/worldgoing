extends SceneTree
## Bounded GPU acceptance for the isolated RegionLab near-Site preview UI.

const SCENE_PATH := "res://scenes/region_lab/RegionLab.tscn"
const OUTPUT_ROOT := "res://output/region_lab_real_acceptance"
const Preview = preload("res://scripts/region_lab/region_site_preview.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const CAPTURE_SIZE := Vector2i(1440, 960)
const YUSHAN := Vector2i(1228, 12981)
const FOREST := Vector2i(1170, 13252)
const LANYU := Vector2i(1545, 12170)
const MISSING_SITE := Vector2i(1600, 12170)
const CACHE_LIMIT := 32

class FaultSource extends RegionData:
	# The real r4 atlas has no active missing Site. Fail one otherwise valid sea
	# Site only in this test to exercise the UI's stale-image error boundary.
	func make_terrain_data(site_x: int, site_y: int) -> Dictionary:
		if Vector2i(site_x, site_y) == Vector2i(1600, 12170):
			return {"ok": false, "code": "MISSING_DATA", "message": "測試注入缺資料"}
		return super.make_terrain_data(site_x, site_y)

var _lab
var _directory := ""
var _deadline_usec := 0
var _finished := false
var _failures: Array[String] = []
var _captures: Array[Dictionary] = []
var _report: Dictionary = {}
var _started_unix := 0

func _init() -> void:
	call_deferred("_run")

func _process(_delta: float) -> bool:
	if not _finished and is_instance_valid(_lab):
		if _lab._preview_thread != null and _lab._open_thread != null:
			_failures.append("CONCURRENT_SOURCE_WORKERS_FRAME")
			_finish()
		elif _lab._preview_tiles.size() > CACHE_LIMIT or _lab._preview_lru.size() > CACHE_LIMIT:
			_failures.append("PREVIEW_CACHE_OVER_32_FRAME")
			_finish()
	if not _finished and _deadline_usec > 0 and Time.get_ticks_usec() > _deadline_usec:
		_failures.append("scene_timeout_180s")
		_finish()
	return false

func _run() -> void:
	_started_unix = int(Time.get_unix_time_from_system())
	_deadline_usec = Time.get_ticks_usec() + 180_000_000
	if DisplayServer.get_name() == "headless":
		_failures.append("GPU_WINDOW_REQUIRED")
		_finish()
		return
	var run_id := str(Time.get_ticks_usec())
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--preview-run="):
			run_id = argument.trim_prefix("--preview-run=")
	if not _valid_run_id(run_id):
		_failures.append("INVALID_RUN_ID")
		_finish()
		return
	_directory = OUTPUT_ROOT.path_join("preview_ui_" + run_id)
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_directory)) != OK:
		_failures.append("OUTPUT_DIRECTORY_FAILED")
		_finish()
		return
	if FileAccess.file_exists(_directory.path_join("preview_ui_result.json")):
		_failures.append("OUTPUT_ALREADY_EXISTS")
		_finish()
		return
	DisplayServer.window_set_size(CAPTURE_SIZE)
	root.size = CAPTURE_SIZE
	root.content_scale_size = CAPTURE_SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		_failures.append("SCENE_LOAD_FAILED")
		_finish()
		return
	_lab = scene.instantiate()
	_lab.source = FaultSource.new()
	root.add_child(_lab)
	current_scene = _lab
	await process_frame
	await process_frame
	if _lab.source.manifest.is_empty() or not _lab.has_method("focus_selected_area"):
		_failures.append("PREVIEW_SCENE_OR_ATLAS_UNAVAILABLE")
		_finish()
		return
	_report["scene"] = SCENE_PATH
	_report["manifest_sha256"] = _lab.source.manifest_hash
	_report["base_revision"] = str(_lab.source.manifest.get("base_revision", ""))
	_report["display_server"] = DisplayServer.get_name()
	_report["window_size"] = [CAPTURE_SIZE.x, CAPTURE_SIZE.y]
	_report["fault_injection"] = {"site": _coord(MISSING_SITE), "code": "MISSING_DATA", "scope": "UI stale-result test only"}
	if not _check_frame("initial", true):
		_finish()
		return
	if not await _preview_and_capture(YUSHAN, "yushan", true):
		_finish()
		return
	if not await _open_and_capture(YUSHAN, "yushan"):
		_finish()
		return
	_lab.show_overview()
	await process_frame
	if not _check_frame("after_yushan_return", true):
		_finish()
		return
	if not await _preview_and_capture(FOREST, "forest", false):
		_finish()
		return
	if not await _open_and_capture(FOREST, "forest"):
		_finish()
		return
	_lab.show_overview()
	await process_frame
	if not _check_frame("after_forest_return", true):
		_finish()
		return
	if not await _preview_and_capture(LANYU, "lanyu", true):
		_finish()
		return
	if not await _open_and_capture(LANYU, "lanyu"):
		_finish()
		return
	_lab.show_overview()
	await process_frame
	if not _check_frame("after_lanyu_return", true):
		_finish()
		return
	if not await _selection_races():
		_finish()
		return
	if not await _missing_data_boundary():
		_finish()
		return
	if not await _cache_cap():
		_finish()
		return
	_finish()

func _preview_and_capture(site: Vector2i, label: String, require_neighbour: bool) -> bool:
	var chosen: Dictionary = _lab.select_site(site)
	if not bool(chosen.get("ok", false)) or not bool(chosen.get("has_terrain", false)):
		return _fail("SELECT_UNAVAILABLE_" + label)
	_lab.focus_selected_area()
	if not await _wait_preview(site, "preview_" + label):
		return false
	var tile: Dictionary = _lab._preview_tiles[site]
	var info: Dictionary = tile.metadata
	if str(info.get("site_id", "")) != str(chosen.get("site_id", "")):
		return _fail("PREVIEW_ID_MISMATCH_" + label)
	if str(info.get("terrain_fingerprint", "")).is_empty() or str(info.get("water_body_sha256", "")).is_empty():
		return _fail("PREVIEW_FINGERPRINT_MISSING_" + label)
	if site == YUSHAN and int(info.get("height_max", 0)) <= int(info.get("height_min", 0)):
		return _fail("MOUNTAIN_RELIEF_MISSING")
	if site == LANYU and (int(info.get("water_cells", 0)) <= 0 or int(info.get("land_cells", 0)) <= 0):
		return _fail("COAST_LAND_WATER_MISSING")
	var resource_counts: Variant = info.get("resource_counts")
	if not resource_counts is Array or str(_lab._preview_label.text).is_empty():
		return _fail("RESOURCE_PREVIEW_METADATA_MISSING_" + label)
	if resource_counts.size() != Env.NAMES.size():
		return _fail("RESOURCE_KIND_COUNT_INVALID_" + label)
	if site == YUSHAN and int(resource_counts[Env.Kind.TIMBER]) != 0:
		return _fail("YUSHAN_ABOVE_TREELINE_SHOWS_TIMBER")
	if site == FOREST and int(resource_counts[Env.Kind.TIMBER]) <= 0:
		return _fail("FOREST_SITE_TIMBER_NOT_VISIBLE")
	if not str(info.get("resource_source_summary", "")).is_empty() \
			and not str(_lab._preview_label.text).contains(str(info.resource_source_summary)):
		return _fail("RESOURCE_SOURCE_NOT_SHOWN_" + label)
	if require_neighbour:
		var neighbour_deadline := mini(_deadline_usec, Time.get_ticks_usec() + 20_000_000)
		while Time.get_ticks_usec() < neighbour_deadline and (_nearby_ready() < 2 or _nearby_pending() > 0):
			await process_frame
			if not _check_frame("nearby_" + label, true):
				return false
		if _nearby_ready() < 2 or _nearby_pending() > 0:
			return _fail("NEARBY_RASTER_NOT_VISIBLE_" + label)
	var visible_before: Array = _lab._preview_visible_sites.duplicate()
	if visible_before.size() <= 1 or visible_before.size() >= CACHE_LIMIT:
		return _fail("NEARBY_SITE_RANGE_INVALID_" + label)
	if not await _capture("region_near_" + label + ".png"):
		return false
	# A map pan must change the visible Site set without relabelling the panel.
	_lab._offset += Vector2(280.0, 0.0)
	_lab._update_transform()
	var pan_deadline := mini(_deadline_usec, Time.get_ticks_usec() + 2_000_000)
	while _lab._preview_visible_sites == visible_before and Time.get_ticks_usec() < pan_deadline:
		await process_frame
		if not _check_frame("pan_" + label, true):
			return false
	if _lab._preview_visible_sites == visible_before:
		return _fail("PAN_DID_NOT_UPDATE_VISIBLE_SITES_" + label)
	if _lab._preview_image.texture != tile.texture:
		return _fail("PAN_RELABELED_SELECTED_PREVIEW_" + label)
	if not await _capture("selection_preview_" + label + ".png"):
		return false
	_report[label + "_preview"] = {"site": _coord(site), "terrain_fingerprint": str(info.terrain_fingerprint),
		"water_body_sha256": str(info.water_body_sha256), "height_range": [int(info.height_min), int(info.height_max)],
		"land_cells": int(info.land_cells), "water_cells": int(info.water_cells),
		"resource_counts": info.resource_counts, "resource_source_summary": str(info.resource_source_summary),
		"nearby_visible": visible_before.size(), "nearby_loaded": _nearby_ready()}
	return true

func _open_and_capture(site: Vector2i, label: String) -> bool:
	var info: Dictionary = _lab._preview_tiles[site].metadata.duplicate(true)
	_lab.request_open_selected_site()
	var local_deadline := mini(_deadline_usec, Time.get_ticks_usec() + 15_000_000)
	while not _lab.site_visible and Time.get_ticks_usec() < local_deadline:
		await process_frame
		if not _check_frame("open_" + label, false):
			return false
	if not _lab.site_visible or _lab.render_pending or _lab.terrain == null:
		return _fail("SITE_OPEN_TIMEOUT_" + label)
	await RenderingServer.frame_post_draw
	if _lab.selected_site != site or _lab._renderer.data != _lab.terrain:
		return _fail("OPENED_WRONG_SITE_" + label)
	var data: TerrainData = _lab.terrain
	var water_hash := _water_body_sha256(data)
	var terrain_hash := data.fingerprint()
	if terrain_hash != str(info.terrain_fingerprint) or water_hash != str(info.water_body_sha256):
		return _fail("PREVIEW_OPEN_SOURCE_MISMATCH_" + label)
	var fixed_base: Dictionary = data.parameters.get("fixed_base", {})
	if str(fixed_base.get("terrain_fingerprint", "")) != terrain_hash:
		return _fail("OPEN_BASE_FINGERPRINT_MISMATCH_" + label)
	if data.site.is_empty() or Preview.visible_resource_counts(data) != info.get("resource_counts", []):
		return _fail("OPEN_RESOURCE_BASE_DIVERGED_" + label)
	if data.resource_base.is_empty():
		if _lab._resource_view != null:
			return _fail("EMPTY_BASE_CREATED_RESOURCE_VIEW_" + label)
	else:
		if _lab._resource_view == null or _lab._resource_view.data != data:
			return _fail("OPEN_RESOURCE_VIEW_NOT_BOUND_" + label)
		for key: String in data.resource_base:
			var base: Dictionary = data.resource_base[key]
			var index := int(base.cell)
			if not data.resources_at.get(index, []).has(key):
				return _fail("OPEN_RESOURCE_INDEX_MISSING_" + label)
			if bool(base.get("blocks", false)) and int(Env.resource(data, key).remaining) > 0 \
					and data.static_blocked[index] != 1:
				return _fail("OPEN_RESOURCE_BLOCKER_MISSING_" + label)
	if _lab._renderer.display_samples.size() != 520 or _count_actors(_lab) != 1:
		return _fail("RESOURCE_ENTRY_CHANGED_RENDER_OR_ACTOR_COUNT_" + label)
	if site == LANYU:
		var ocean := false
		var dry := false
		for body: int in data.water_body:
			ocean = ocean or body == 1
			dry = dry or body == -1
		if not ocean or not dry:
			return _fail("COAST_WATER_BODY_NOT_MIXED")
	_report[label + "_opened"] = {"site": _coord(site), "terrain_fingerprint": terrain_hash,
		"water_body_sha256": water_hash, "actor_count": _count_actors(_lab),
		"canvas_submissions": _lab._renderer.display_samples.size(),
		"resource_view_bound": _lab._resource_view != null, "resource_base_count": data.resource_base.size()}
	if not await _capture("opened_" + label + ".png"):
		return false
	if site == FOREST:
		var timber_cell := Vector2i(-1, -1)
		var best_distance := INF
		for key: String in data.resource_base:
			if int(data.resource_base[key].kind) != Env.Kind.TIMBER:
				continue
			var cell: Vector2i = data.cell_from_index(int(data.resource_base[key].cell))
			var distance := Vector2(cell).distance_squared_to(Vector2(50, 50))
			if distance < best_distance:
				best_distance = distance
				timber_cell = cell
		if timber_cell == Vector2i(-1, -1):
			return _fail("FOREST_DETAIL_HAS_NO_TIMBER")
		_lab._scale = 0.9
		_lab._offset = _lab._canvas.size * 0.5 - (Vector2(timber_cell) + Vector2.ONE * 0.5) \
			* TerrainRenderer.CELL_PIXELS * _lab._scale
		_lab._update_transform()
		_report["forest_detail_cell"] = _coord(timber_cell)
		if not await _capture("opened_forest_detail.png"):
			return false
	return true

func _selection_races() -> bool:
	# A previewing A, a queued B, then A again: B's late result may be cached,
	# but it must not replace A's selected image or start a Site actor.
	_lab._fit_view()
	while _lab._preview_thread != null and Time.get_ticks_usec() < _deadline_usec:
		await process_frame
		if not _check_frame("race_drain", true):
			return false
	var a := Vector2i(1218, 12981)
	var b := Vector2i(1219, 12981)
	for site: Vector2i in [a, b]:
		if not bool(_lab.source.get_site_summary(site.x, site.y).get("has_terrain", false)):
			return _fail("RACE_SITE_UNAVAILABLE")
	_lab.select_site(a)
	if not await _wait_worker(a, "race_a"):
		return false
	_lab.select_site(b)
	if not await _wait_worker(b, "race_b"):
		return false
	_lab.select_site(a)
	if not await _wait_preview(a, "race_return_a"):
		return false
	while _lab._preview_thread != null and Time.get_ticks_usec() < _deadline_usec:
		await process_frame
		if not _check_frame("race_b_completion", true):
			return false
	if _lab.selected_site != a or _lab._preview_image.texture != _lab._preview_tiles[a].texture:
		return _fail("STALE_B_REPLACED_A")
	_report["selection_aba"] = {"a": _coord(a), "b": _coord(b), "a_selected_after_b_result": true}
	# Queue explicit entry behind an in-flight preview, then cancel that entry.
	var c := Vector2i(1210, 12981)
	if not bool(_lab.source.get_site_summary(c.x, c.y).get("has_terrain", false)):
		return _fail("CANCEL_SITE_UNAVAILABLE")
	_lab.select_site(c)
	_lab.focus_selected_area()
	if not await _wait_worker(c, "cancel_preview"):
		return false
	var unfinished_neighbour := Vector2i(-1, -1)
	for nearby: Vector2i in _lab._preview_visible_sites:
		if nearby != c and not _lab._preview_tiles.has(nearby) \
				and bool(_lab.source.get_site_summary(nearby.x, nearby.y).get("has_terrain", false)):
			unfinished_neighbour = nearby
			break
	if unfinished_neighbour == Vector2i(-1, -1):
		return _fail("CANCEL_CASE_HAS_NO_UNFINISHED_NEIGHBOUR")
	_lab.request_open_selected_site()
	if _lab._preview_open_site != c or _lab._open_thread != null:
		return _fail("PREVIEW_OPEN_NOT_SERIALIZED")
	_lab.show_overview()
	if _lab._preview_open_site != null:
		return _fail("CANCEL_LEFT_QUEUED_OPEN")
	while _lab._preview_thread != null and _lab._preview_requested_site == c and Time.get_ticks_usec() < _deadline_usec:
		await process_frame
		if not _check_frame("cancel_preview_result", true):
			return false
	if _lab.site_visible or _lab.terrain != null or _count_actors(_lab) != 0:
		return _fail("CANCEL_OPENED_SITE_LATE")
	var neighbour_deadline := mini(_deadline_usec, Time.get_ticks_usec() + 12_000_000)
	while not _lab._preview_tiles.has(unfinished_neighbour) and Time.get_ticks_usec() < neighbour_deadline:
		await process_frame
		if not _check_frame("cancel_neighbour_resume", true):
			return false
	if not _lab._preview_tiles.has(unfinished_neighbour):
		return _fail("CANCEL_STOPPED_NEARBY_PREVIEWS")
	_report["preview_open_cancel"] = {"site": _coord(c), "queued_then_cancelled": true,
		"unfinished_neighbour_resumed": _coord(unfinished_neighbour), "actor_count": 0}
	# The same-site preview result can also finish an explicit enter without a
	# second source worker. This is a separate success case from cancellation.
	var d := Vector2i(1200, 12981)
	if not bool(_lab.source.get_site_summary(d.x, d.y).get("has_terrain", false)):
		return _fail("PREVIEW_OPEN_SITE_UNAVAILABLE")
	_lab._fit_view()
	if _lab._preview_tiles.has(d):
		return _fail("PREVIEW_OPEN_SITE_ALREADY_CACHED")
	_lab.select_site(d)
	if not await _wait_worker(d, "preview_open_success"):
		return false
	_lab.request_open_selected_site()
	if _lab._preview_open_site != d or _lab._open_thread != null:
		return _fail("PREVIEW_OPEN_SUCCESS_NOT_QUEUED")
	var saw_open_worker := false
	var open_deadline := mini(_deadline_usec, Time.get_ticks_usec() + 15_000_000)
	while not _lab.site_visible and Time.get_ticks_usec() < open_deadline:
		await process_frame
		saw_open_worker = saw_open_worker or _lab._open_thread != null
		if not _check_frame("preview_open_success", false):
			return false
	if not _lab.site_visible or _lab.terrain == null or saw_open_worker \
			or not _lab._preview_tiles.has(d) \
			or _lab.terrain.fingerprint() != str(_lab._preview_tiles[d].metadata.terrain_fingerprint):
		return _fail("PREVIEW_RESULT_NOT_REUSED_FOR_ENTER")
	_lab.show_overview()
	await process_frame
	if not _check_frame("preview_open_success_return", true):
		return false
	_report["preview_open_success"] = {"site": _coord(d), "same_result_reused": true,
		"second_source_worker_seen": saw_open_worker}
	# Pressing Open for E, selecting B, then reselecting E without pressing Open
	# must not revive the old explicit-entry request.
	var e := Vector2i(1188, 12981)
	var alternate := Vector2i(1189, 12981)
	if _lab._preview_tiles.has(e) or not bool(_lab.source.get_site_summary(e.x, e.y).get("has_terrain", false)) \
			or not bool(_lab.source.get_site_summary(alternate.x, alternate.y).get("has_terrain", false)):
		return _fail("STALE_OPEN_RACE_SITE_UNAVAILABLE")
	_lab._fit_view()
	_lab.select_site(e)
	if not await _wait_worker(e, "stale_open_e"):
		return false
	_lab.request_open_selected_site()
	if _lab._preview_open_site != e:
		return _fail("STALE_OPEN_RACE_NOT_QUEUED")
	_lab.select_site(alternate)
	if _lab._preview_open_site != null:
		return _fail("STALE_OPEN_RACE_NOT_CLEARED_ON_NEW_SELECTION")
	_lab.select_site(e) # No second Open press.
	if not await _wait_preview(e, "stale_open_return_e"):
		return false
	for followup: int in range(3):
		await process_frame
		if not _check_frame("stale_open_followup_" + str(followup), true):
			return false
	if _lab._preview_open_site != null or _lab._open_thread != null or _lab.site_visible:
		return _fail("STALE_OPEN_REVIVED_AFTER_ABA")
	_report["queued_open_aba"] = {"requested": _coord(e), "intervening_selection": _coord(alternate),
		"returned_to_a_without_new_open": true, "site_remained_closed": true}
	return true

func _missing_data_boundary() -> bool:
	var summary: Dictionary = _lab.source.get_site_summary(MISSING_SITE.x, MISSING_SITE.y)
	if not bool(summary.get("has_terrain", false)):
		return _fail("FAULT_SITE_NOT_REAL_VALID_GEOGRAPHY")
	_lab.select_site(YUSHAN)
	if not await _wait_preview(YUSHAN, "before_fault"):
		return false
	var old_texture: Texture2D = _lab._preview_image.texture
	_lab.select_site(MISSING_SITE)
	if _lab._preview_image.texture != null:
		return _fail("OLD_PREVIEW_VISIBLE_ON_FAILED_SELECTION")
	var local_deadline := mini(_deadline_usec, Time.get_ticks_usec() + 8_000_000)
	while not _lab._preview_errors.has(MISSING_SITE) and Time.get_ticks_usec() < local_deadline:
		await process_frame
		if not _check_frame("missing_source", true):
			return false
	if not _lab._preview_errors.has(MISSING_SITE) or _lab._preview_tiles.has(MISSING_SITE):
		return _fail("MISSING_PREVIEW_NOT_REJECTED")
	if _lab._preview_image.texture != null or _lab._preview_image.texture == old_texture \
			or not str(_lab._preview_label.text).contains("失敗"):
		return _fail("FAILED_PREVIEW_DISPLAYED_STALE_SITE")
	_report["missing_data"] = {"site": _coord(MISSING_SITE), "error": str(_lab._preview_errors[MISSING_SITE]),
		"old_image_cleared": true}
	return true

func _cache_cap() -> bool:
	_lab._fit_view()
	var visited := 0
	var first := Vector2i(1620, 12170)
	for step: int in range(34):
		var site := first + Vector2i(step, 0)
		if not bool(_lab.source.get_site_summary(site.x, site.y).get("has_terrain", false)):
			return _fail("CACHE_SWEEP_SITE_UNAVAILABLE_" + str(step))
		_lab.select_site(site)
		if not await _wait_preview(site, "cache_" + str(step)):
			return false
		visited += 1
	if _lab._preview_tiles.size() > CACHE_LIMIT or _lab._preview_lru.size() > CACHE_LIMIT:
		return _fail("PREVIEW_CACHE_OVER_32")
	if _lab._preview_tiles.has(first) and visited > CACHE_LIMIT:
		return _fail("PREVIEW_CACHE_DID_NOT_EVICT")
	_report["cache"] = {"distinct_selected_sites": visited, "cached_tiles": _lab._preview_tiles.size(),
		"lru_entries": _lab._preview_lru.size(), "limit": CACHE_LIMIT, "first_evicted": not _lab._preview_tiles.has(first)}
	return true

func _wait_preview(site: Vector2i, phase: String) -> bool:
	var local_deadline := mini(_deadline_usec, Time.get_ticks_usec() + 12_000_000)
	while Time.get_ticks_usec() < local_deadline:
		if _lab._preview_tiles.has(site) and _lab._preview_image.texture == _lab._preview_tiles[site].texture:
			return _check_frame(phase + "_ready", true)
		await process_frame
		if not _check_frame(phase, true):
			return false
	return _fail("PREVIEW_TIMEOUT_" + phase)

func _wait_worker(site: Vector2i, phase: String) -> bool:
	var local_deadline := mini(_deadline_usec, Time.get_ticks_usec() + 8_000_000)
	while Time.get_ticks_usec() < local_deadline:
		if _lab._preview_thread != null and _lab._preview_requested_site == site:
			return _check_frame(phase + "_started", true)
		await process_frame
		if not _check_frame(phase, true):
			return false
	return _fail("PREVIEW_WORKER_NOT_OBSERVED_" + phase)

func _nearby_ready() -> int:
	var count := 0
	for site: Vector2i in _lab._preview_visible_sites:
		count += int(_lab._preview_tiles.has(site))
	return count

func _nearby_pending() -> int:
	var count := 0
	for site: Vector2i in _lab._preview_visible_sites:
		var info: Dictionary = _lab.source.get_site_summary(site.x, site.y)
		if bool(info.get("has_terrain", false)) and int(info.get("class_id", 0)) != 1 \
				and not _lab._preview_tiles.has(site):
			count += 1
	return count

func _check_frame(phase: String, before_enter: bool) -> bool:
	if _lab._preview_thread != null and _lab._open_thread != null:
		return _fail("CONCURRENT_SOURCE_WORKERS_" + phase)
	if _lab._preview_tiles.size() > CACHE_LIMIT or _lab._preview_lru.size() > CACHE_LIMIT:
		return _fail("PREVIEW_CACHE_OVER_32_" + phase)
	if before_enter and (_lab.site_visible or _lab.render_pending or _lab.terrain != null \
			or _lab._resource_view != null or _count_actors(_lab) != 0):
		return _fail("SITE_STATE_BEFORE_EXPLICIT_ENTRY_" + phase)
	return true

func _capture(filename: String) -> bool:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_width() < 1000 or image.get_height() < 600:
		return _fail("EMPTY_GPU_CAPTURE_" + filename)
	var path := _directory.path_join(filename)
	if FileAccess.file_exists(path) or image.save_png(path) != OK:
		return _fail("CAPTURE_SAVE_FAILED_" + filename)
	if FileAccess.get_modified_time(path) < _started_unix:
		return _fail("STALE_CAPTURE_" + filename)
	_captures.append({"path": ProjectSettings.globalize_path(path), "sha256": FileAccess.get_sha256(path),
		"size": [image.get_width(), image.get_height()]})
	return true

func _water_body_sha256(data: TerrainData) -> String:
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(data.water_body.to_byte_array())
	return hasher.finish().hex_encode()

func _count_actors(node: Node) -> int:
	var count := int(node is TerrainTestCharacter)
	for child: Node in node.get_children():
		count += _count_actors(child)
	return count

func _coord(site: Vector2i) -> Array[int]:
	return [site.x, site.y]

func _valid_run_id(value: String) -> bool:
	if value.is_empty() or value.length() > 72:
		return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true

func _fail(code: String) -> bool:
	_failures.append(code)
	return false

func _finish() -> void:
	if _finished:
		return
	_finished = true
	_report["failures"] = _failures
	_report["captures"] = _captures
	_report["elapsed_seconds"] = (Time.get_ticks_usec() - (_deadline_usec - 180_000_000)) / 1_000_000.0
	if not _directory.is_empty():
		var path := _directory.path_join("preview_ui_result.json")
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			_failures.append("REPORT_WRITE_FAILED")
		else:
			_report["failures"] = _failures
			file.store_string(JSON.stringify(_report, "\t"))
			file.close()
			_report["report_path"] = ProjectSettings.globalize_path(path)
	if _failures.is_empty():
		print("REGION_LAB_PREVIEW_UI_PASS " + JSON.stringify(_report))
		quit(0)
	else:
		printerr("REGION_LAB_PREVIEW_UI_FAIL " + JSON.stringify(_report))
		quit(1)
