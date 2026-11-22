extends SceneTree
## 示範劇本 A step 7 (GPU capture, not a gameplay check): the demo scenario's start Site after the real package is born.
## Requests a new world from res://assets/scenarios/demo_a/demo_a.json (46 Sites, about 7 minutes to birth), waits for the
## Site to open and settle, lets a few seconds of play pass, and captures the start Site to
## res://.visual_captures/scenario_start. Prints SCENARIO_START CAPTURE <path> and SCENARIO_START CAPTURE DONE.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const PACKAGE := "res://assets/scenarios/demo_a/demo_a.json"
const START := Vector2i(1170, 13252)
const OUT := "res://.visual_captures/scenario_start"
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 1500000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("SCENARIO_START CAPTURE deadline")
		quit(1)
	return false

func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := OUT.path_join(name + ".png")
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("SCENARIO_START CAPTURE save failed %s" % path)
		quit(1)
		return
	print("SCENARIO_START CAPTURE ", path)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	root.size = Vector2i(1600, 900)
	if not RegionEntry.request_new_world(START, {}, "開墾之地", "", PACKAGE):
		push_error("SCENARIO_START request refused ", RegionEntry.menu_message)
		quit(1)
		return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	for _frame: int in range(60000):
		await process_frame
		var scene := current_scene as TerrainLab
		if scene != null and scene.site_controller != null and scene.site_controller.region_slot != null and scene.site_controller._boot_request.is_empty() and scene.crowd_site != null and scene.crowd_site.active:
			lab = scene
			break
	if lab == null:
		push_error("SCENARIO_START the world did not open: ", RegionEntry.menu_message)
		quit(1)
		return
	for _frame: int in range(240): await process_frame
	await _capture("01_start_born")
	print("SCENARIO_START CAPTURE DONE")
	quit(0)
