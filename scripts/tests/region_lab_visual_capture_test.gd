extends SceneTree
## Run only with the canonical GPU visual verifier; uses the actual RegionLab UI.

const ScenePath := "res://scenes/region_lab/RegionLab.tscn"
const Atlas = preload("res://scripts/region_lab/region_data.gd")
const TestSource = preload("res://scripts/tests/region_lab_test_source.gd")
const ManifestPath := Atlas.DEFAULT_MANIFEST
const OutputRoot := "res://.visual_captures/region_lab"
const CaptureSize := Vector2i(1440, 960)

var _viewer
var _output_dir := ""
var _started_unix := 0
var _captures: Array[Dictionary] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_started_unix = int(Time.get_unix_time_from_system())
	if not _require(DisplayServer.get_name() != "headless", "GPU_WINDOW_REQUIRED", "Use the canonical verifier in visual mode."):
		return
	var run_id := str(int(Time.get_unix_time_from_system() * 1000000.0))
	var capture_manifest := ManifestPath
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--region-capture-run="):
			run_id = argument.trim_prefix("--region-capture-run=")
		elif argument.begins_with("--manifest="):
			capture_manifest = argument.trim_prefix("--manifest=")
	if not _require(FileAccess.file_exists(capture_manifest), "MANIFEST_MISSING", capture_manifest):
		return
	if not _require(_valid_run_id(run_id), "INVALID_RUN_ID", "Use only ASCII letters, digits, underscores or hyphens."):
		return
	_output_dir = OutputRoot.path_join(run_id)
	var output_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_dir))
	if not _require(output_error == OK, "OUTPUT_DIRECTORY_FAILED", error_string(output_error)):
		return
	for filename: String in ["overview.png", "land_site.png", "capture_result.json"]:
		if not _require(not FileAccess.file_exists(_output_dir.path_join(filename)), "OUTPUT_ALREADY_EXISTS", "Use a fresh run ID: " + _output_dir):
			return
	DisplayServer.window_set_size(CaptureSize)
	root.size = CaptureSize
	root.content_scale_size = CaptureSize
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var scene := load(ScenePath) as PackedScene
	if not _require(scene != null, "SCENE_LOAD_FAILED", ScenePath):
		return
	_viewer = scene.instantiate() as Control
	if not _require(_viewer != null, "SCENE_TYPE_FAILED", "RegionLab must be the actual Control scene."):
		return
	if capture_manifest != ManifestPath:
		TestSource.selected_manifest = capture_manifest
		_viewer.source = TestSource.new()
	root.add_child(_viewer)
	await process_frame
	await process_frame
	if not _require(not _viewer.source.manifest.is_empty(), "MANIFEST_REJECTED", str(_viewer._status.text)):
		return
	if not _require(_viewer._overview_texture != null, "OVERVIEW_UNAVAILABLE", str(_viewer._status.text)):
		return
	if not _require(str(_viewer.source.manifest.get("atlas_id", "")) == "earth_tw_tm2_121_v1", "WRONG_ATLAS", "This capture requires the packaged Taiwan atlas."):
		return
	_viewer.show_overview()
	if not await _capture("overview.png"):
		return
	var candidates: Array = _viewer.source.manifest.get("preview_sites", [])
	var rejected: Array[Dictionary] = []
	var opened := false
	var mountain_elevation: Dictionary = {}
	for candidate: Variant in candidates.slice(0, 64):
		if not candidate is Dictionary or str(candidate.get("category", "")) != "mountain":
			continue
		var site_value: Variant = candidate.get("site", [])
		if not site_value is Array or site_value.size() != 2:
			continue
		var site := Vector2i(int(site_value[0]), int(site_value[1]))
		var summary: Dictionary = _viewer.select_site(site)
		if not bool(summary.get("ok", false)) or int(summary.get("class_id", 0)) not in [2, 4] or not bool(summary.get("has_terrain", false)):
			rejected.append({"site": [site.x, site.y], "reason": "LAND_TERRAIN_UNAVAILABLE", "summary": summary})
			continue
		var result: Dictionary = _viewer.open_selected_site()
		if not bool(result.get("ok", false)):
			rejected.append({"site": [site.x, site.y], "reason": str(result.get("code", "OPEN_FAILED")), "message": str(result.get("message", ""))})
			continue
		if not await _wait_for_site_render(site):
			return
		if _viewer.actor == null:
			rejected.append({"site": [site.x, site.y], "reason": "NO_LEGAL_LAND_SPAWN"})
			_viewer.show_overview()
			continue
		var minimum_level: int = _viewer.terrain.height_levels[0]
		var maximum_level: int = minimum_level
		for level: int in _viewer.terrain.height_levels:
			minimum_level = mini(minimum_level, level)
			maximum_level = maxi(maximum_level, level)
		if maximum_level <= minimum_level:
			rejected.append({"site": [site.x, site.y], "reason": "MOUNTAIN_PREVIEW_HAS_NO_RELIEF"})
			_viewer.show_overview()
			continue
		var metadata: Dictionary = result.get("metadata", {})
		var elevations: PackedFloat32Array = metadata.get("absolute_elevation_m", PackedFloat32Array())
		var minimum_metres := INF
		var maximum_metres := -INF
		for elevation: float in elevations:
			if is_finite(elevation):
				minimum_metres = minf(minimum_metres, elevation)
				maximum_metres = maxf(maximum_metres, elevation)
		if not is_finite(minimum_metres) or not is_finite(maximum_metres):
			rejected.append({"site": [site.x, site.y], "reason": "MOUNTAIN_SOURCE_ELEVATION_MISSING"})
			_viewer.show_overview()
			continue
		mountain_elevation = {"minimum_m": minimum_metres, "maximum_m": maximum_metres,
			"gameplay_levels": [minimum_level, maximum_level], "sample_label": str(candidate.get("label", ""))}
		opened = true
		break
	if not _require(opened, "NO_EXPANDABLE_MOUNTAIN_SITE", JSON.stringify({"preview_count": candidates.size(), "rejected": rejected})):
		return
	if not _require(_viewer.actor is TerrainTestCharacter and _viewer.actor.data == _viewer.terrain and _viewer._renderer.data == _viewer.terrain, "ORIGINAL_OWNER_MISMATCH", "Capture must use the original Actor and TerrainRenderer with the same TerrainData."):
		return
	if not _require(_viewer.terrain.is_walkable(_viewer.actor.terrain_cell), "ILLEGAL_LAND_SPAWN", str(_viewer.actor.terrain_cell)):
		return
	if not await _capture("land_site.png"):
		return
	var report := {"ok": true, "scene": ScenePath, "manifest": capture_manifest,
		"manifest_sha256": str(_viewer.source.manifest_hash), "base_revision": str(_viewer.source.manifest.get("base_revision", "")),
		"site": [_viewer.selected_site.x, _viewer.selected_site.y], "site_id": str(_viewer.selection.get("site_id", "")),
		"captures": _captures, "candidate_rejections": rejected, "mountain_elevation": mountain_elevation,
		"evidence_boundary": "Actual GPU scene captures; visual inspection and gameplay acceptance remain separate."}
	var report_file := FileAccess.open(_output_dir.path_join("capture_result.json"), FileAccess.WRITE)
	if not _require(report_file != null, "REPORT_WRITE_FAILED", error_string(FileAccess.get_open_error())):
		return
	report_file.store_string(JSON.stringify(report, "\t"))
	report_file.flush()
	report_file.close()
	print("REGION_LAB_VISUAL_CAPTURE_PASS " + JSON.stringify(report))
	_viewer.queue_free()
	await process_frame
	quit(0)

func _wait_for_site_render(site: Vector2i) -> bool:
	var deadline_usec := Time.get_ticks_usec() + 5_000_000
	while Time.get_ticks_usec() < deadline_usec:
		if _viewer.site_visible and _viewer.terrain != null and _viewer._renderer.data == _viewer.terrain:
			# The final canvas submission must finish before the GPU capture.
			await RenderingServer.frame_post_draw
			return true
		await process_frame
	return _require(false, "SITE_RENDER_TIMEOUT", "Site %s never completed all canvas segments." % site)

func _capture(filename: String) -> bool:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	if not _require(picture != null and not picture.is_empty(), "EMPTY_GPU_IMAGE", filename):
		return false
	if not _require(picture.get_width() >= 1000 and picture.get_height() >= 600, "CAPTURE_TOO_SMALL", str(picture.get_size())):
		return false
	var path := _output_dir.path_join(filename)
	var saved: Error = picture.save_png(path)
	if not _require(saved == OK and FileAccess.file_exists(path), "PNG_SAVE_FAILED", path + ": " + error_string(saved)):
		return false
	if not _require(FileAccess.get_modified_time(path) >= _started_unix, "STALE_OUTPUT", path):
		return false
	var loaded := Image.new()
	if not _require(loaded.load(path) == OK and loaded.get_size() == picture.get_size(), "PNG_READBACK_FAILED", path):
		return false
	_captures.append({"path": ProjectSettings.globalize_path(path), "size": [picture.get_width(), picture.get_height()],
		"sha256": FileAccess.get_sha256(path), "modified_unix": FileAccess.get_modified_time(path)})
	return true

func _valid_run_id(value: String) -> bool:
	if value.is_empty() or value.length() > 80:
		return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true

func _require(condition: bool, code: String, message: String) -> bool:
	if condition:
		return true
	push_error("REGION_LAB_VISUAL_CAPTURE_FAIL [%s] %s" % [code, message])
	quit(1)
	return false
