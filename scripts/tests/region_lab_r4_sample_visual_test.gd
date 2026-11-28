extends SceneTree

# Isolated r4 Lanyu sample through the actual RegionLab canvas and renderer.
const SCENE := "res://scenes/region_lab/RegionLab.tscn"
const TestSource = preload("res://scripts/tests/region_lab_test_source.gd")
## The shipped r4 source (the r4 sample under tools/region_lab/.tmp was the pre-publication copy; it lacks the source
## quality of this Lanyu Site: SAMPLE_SITE_NOT_MIXED_ESTIMATED). Run with -- --region-capture-run=<fresh id>.
const MANIFEST := "res://assets/region_lab/earth_tw_tm2_121_v1_r4/manifest.json"
const SITE := Vector2i(1545, 12170)
const CAPTURE := "res://.visual_captures/region_lab/r4_sample_lanyu_final_20260927.png"
const REPORT := "res://.visual_captures/region_lab/r4_sample_lanyu_final_20260927.json"
const SIZE := Vector2i(1440, 960)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var manifest_path := MANIFEST
	var capture_path := CAPTURE
	var report_path := REPORT
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--manifest="):
			manifest_path = argument.trim_prefix("--manifest=")
		elif argument.begins_with("--region-capture-run="):
			var run_id := argument.trim_prefix("--region-capture-run=")
			if not _valid_run_id(run_id):
				_fail("INVALID_RUN_ID")
				return
			capture_path = "res://.visual_captures/region_lab/%s_lanyu.png" % run_id
			report_path = "res://.visual_captures/region_lab/%s_lanyu.json" % run_id
	if DisplayServer.get_name() == "headless":
		_fail("GPU_WINDOW_REQUIRED")
		return
	if FileAccess.file_exists(capture_path) or FileAccess.file_exists(report_path):
		_fail("OUTPUT_ALREADY_EXISTS")
		return
	DisplayServer.window_set_size(SIZE)
	root.size = SIZE
	root.content_scale_size = SIZE
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var packed := load(SCENE) as PackedScene
	if packed == null:
		_fail("SCENE_LOAD_FAILED")
		return
	var lab := packed.instantiate() as Control
	TestSource.selected_manifest = manifest_path
	lab.source = TestSource.new()
	root.add_child(lab)
	await process_frame
	await process_frame
	if lab.source.manifest.is_empty() or lab._overview_texture == null:
		_fail("SAMPLE_MANIFEST_REJECTED:" + str(lab._status.text))
		return
	if not str(lab._attribution.text).contains("OpenStreetMap"):
		_fail("R4_SOURCE_ATTRIBUTION_NOT_VISIBLE")
		return
	var summary: Dictionary = lab.select_site(SITE)
	if not summary.ok or summary.class_id != 4 or summary.source_quality_code != 4:
		_fail("SAMPLE_SITE_NOT_MIXED_ESTIMATED:" + str(summary))
		return
	if lab._samples.selected != -1 or lab._samples.text != "代表地點":
		_fail("CUSTOM_COORDINATE_SHOWS_STALE_PREVIEW_LABEL")
		return
	var opened: Dictionary = lab.open_selected_site()
	if not opened.ok:
		_fail("SAMPLE_SITE_OPEN_FAILED:" + str(opened))
		return
	var deadline := Time.get_ticks_usec() + 10_000_000
	while not lab.site_visible and Time.get_ticks_usec() < deadline:
		await process_frame
	if not lab.site_visible or lab.render_pending or lab._renderer.display_pending or lab.terrain == null:
		_fail("SAMPLE_RENDER_INCOMPLETE")
		return
	if lab._renderer.display_samples.size() != 520:
		_fail("INCOMPLETE_CANVAS_SUBMISSIONS:" + str(lab._renderer.display_samples.size()))
		return
	if lab.actor == null or lab.actor.data != lab.terrain or lab._renderer.data != lab.terrain:
		_fail("ACTOR_RENDERER_OWNER_MISMATCH")
		return
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	if picture == null or picture.is_empty() or picture.get_size() != SIZE:
		_fail("GPU_IMAGE_INVALID")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_path.get_base_dir()))
	if picture.save_png(capture_path) != OK or not FileAccess.file_exists(capture_path):
		_fail("PNG_WRITE_FAILED")
		return
	var report := {"ok": true, "scene": SCENE, "manifest": manifest_path,
		"manifest_sha256": lab.source.manifest_hash, "site": [SITE.x, SITE.y],
		"base_revision": lab.source.manifest.base_revision,
		"estimated_cells": int(opened.metadata.estimated_elevation_cells),
		"land_cells": int(opened.metadata.land_cells), "water_cells": int(opened.metadata.water_cells),
		"canvas_submissions": lab._renderer.display_samples.size(),
		"image": ProjectSettings.globalize_path(capture_path), "image_sha256": FileAccess.get_sha256(capture_path),
		"gpu": {"display_server": DisplayServer.get_name()},
		"scope": "One r4 Lanyu Site via actual GPU RegionLab; visual check, not a performance result"}
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		_fail("REPORT_WRITE_FAILED")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("REGION_LAB_R4_SAMPLE_VISUAL_PASS ", JSON.stringify(report))
	lab.queue_free()
	await process_frame
	quit(0)

func _fail(code: String) -> void:
	push_error("REGION_LAB_R4_SAMPLE_VISUAL_FAIL " + code)
	quit(1)

func _valid_run_id(value: String) -> bool:
	if value.is_empty() or value.length() > 80:
		return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return false
	return true
