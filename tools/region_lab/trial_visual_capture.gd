extends SceneTree

## Captures the unchanged RegionLab scene with an injected r3 trial data source.
const ScenePath := "res://scenes/region_lab/RegionLab.tscn"
const TrialSource = preload("res://tools/region_lab/trial_source.gd")
const OutputRoot := "res://.visual_captures/region_lab"
const CaptureSize := Vector2i(1440, 960)
const ShoreSites := {
	"east_coast": Vector2i(1573, 13272),
	"penghu": Vector2i(505, 13033),
	"green_island": Vector2i(1506, 12519),
	"lanyu": Vector2i(1545, 12170),
}

var _viewer: Control
var _output := ""
var _captures: Array[Dictionary] = []
var _failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _require(ok: bool, code: String) -> bool:
	if not ok:
		_failures.append(code)
		push_error("REGION_TRIAL_VISUAL_FAIL " + code)
		quit(1)
	return ok

func _run() -> void:
	if not _require(DisplayServer.get_name() != "headless", "GPU_WINDOW_REQUIRED"):
		return
	var run_id := "r3_trial"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--region-capture-run="):
			run_id = arg.trim_prefix("--region-capture-run=")
	if not _require(run_id.length() > 0 and run_id.length() < 64, "INVALID_RUN_ID"):
		return
	for character: String in run_id:
		if not _require(character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-", "INVALID_RUN_ID"):
			return
	_output = OutputRoot.path_join(run_id)
	if not _require(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output)) == OK,
			"OUTPUT_DIRECTORY_FAILED"):
		return
	for filename: String in ["overview.png", "east_coast.png", "penghu.png", "green_island.png", "lanyu.png", "capture_result.json"]:
		if not _require(not FileAccess.file_exists(_output.path_join(filename)), "OUTPUT_ALREADY_EXISTS:" + filename):
			return
	DisplayServer.window_set_size(CaptureSize)
	root.size = CaptureSize
	root.content_scale_size = CaptureSize
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var scene := load(ScenePath) as PackedScene
	if not _require(scene != null, "SCENE_LOAD_FAILED"):
		return
	_viewer = scene.instantiate() as Control
	if not _require(_viewer != null, "SCENE_INSTANTIATION_FAILED"):
		return
	_viewer.source = TrialSource.new()
	root.add_child(_viewer)
	await process_frame
	await process_frame
	if not _require(str(_viewer.source.manifest.get("base_revision", "")).ends_with("r3-trial"), "WRONG_REVISION"):
		return
	if not _require(_viewer._overview_texture != null, "OVERVIEW_UNAVAILABLE"):
		return
	_viewer.show_overview()
	if not await _capture("overview.png"):
		return
	var shore_results: Array[Dictionary] = []
	for label: String in ShoreSites:
		var site: Vector2i = ShoreSites[label]
		var summary: Dictionary = _viewer.select_site(site)
		if not _require(summary.ok and summary.has_terrain and summary.class_id == 4, "MIXED_SHORE_UNAVAILABLE:" + label):
			return
		var opened: Dictionary = _viewer.open_selected_site()
		if not _require(opened.ok and opened.metadata.land_cells > 0 and opened.metadata.water_cells > 0,
				"SHORE_SURFACES_UNAVAILABLE:" + label):
			return
		if not _require(_viewer.actor is TerrainTestCharacter and _viewer.actor.data == _viewer.terrain and _viewer._renderer.data == _viewer.terrain,
				"ORIGINAL_OWNER_MISMATCH:" + label):
			return
		shore_results.append({"label": label, "site": [site.x, site.y],
			"land_cells": opened.metadata.land_cells, "water_cells": opened.metadata.water_cells})
		if not await _capture(label + ".png"):
			return
		_viewer.show_overview()
		await process_frame
	var report := {"ok": true, "scene": ScenePath,
		"trial_manifest_sha256": str(_viewer.source.manifest_hash),
		"base_revision": str(_viewer.source.manifest.base_revision),
		"shore_sites": shore_results, "captures": _captures,
		"evidence_boundary": "Actual GPU scene images and original renderer; sampled coast only."}
	var path := _output.path_join("capture_result.json")
	var handle := FileAccess.open(path, FileAccess.WRITE)
	if not _require(handle != null, "REPORT_WRITE_FAILED"):
		return
	handle.store_string(JSON.stringify(report, "\t"))
	handle.close()
	print("REGION_TRIAL_VISUAL_PASS " + JSON.stringify(report))
	_viewer.queue_free()
	await process_frame
	quit(0)

func _capture(filename: String) -> bool:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	if not _require(picture != null and not picture.is_empty() and picture.get_width() >= 1000,
			"EMPTY_GPU_IMAGE:" + filename):
		return false
	var path := _output.path_join(filename)
	if not _require(picture.save_png(path) == OK and FileAccess.file_exists(path), "PNG_SAVE_FAILED:" + filename):
		return false
	var check := Image.new()
	if not _require(check.load(path) == OK and check.get_size() == picture.get_size(), "PNG_READBACK_FAILED:" + filename):
		return false
	_captures.append({"path": ProjectSettings.globalize_path(path), "size": [picture.get_width(), picture.get_height()],
		"sha256": FileAccess.get_sha256(path)})
	return true
