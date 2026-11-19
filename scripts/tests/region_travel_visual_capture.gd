extends SceneTree
## GPU capture (canonical verifier, visual mode): the real RegionLab in travel
## mode with a party part-way along a Yushan route on the packaged Taiwan map.
## Writes .visual_captures/region_travel/<run>/travel_map.png and capture_result.json.

const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const ScenePath := "res://scenes/region_lab/RegionLab.tscn"
const OutputRoot := "res://.visual_captures/region_travel"
const CaptureSize := Vector2i(1600, 960)
const START := Vector2i(1228, 12981)
const GOAL := Vector2i(1231, 12979)

var _viewer: Control
var _output_dir := ""
var _started_unix := 0

func _init() -> void:
	call_deferred("_run")

func _fail(message: String) -> bool:
	push_error("REGION_TRAVEL_CAPTURE_FAIL: " + message)
	quit(1)
	return false

func _run():
	_started_unix = int(Time.get_unix_time_from_system())
	if DisplayServer.get_name() == "headless": return _fail("GPU window required")
	var run_id := "r1_%d" % Time.get_ticks_msec()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--run="): run_id = argument.trim_prefix("--run=")
	_output_dir = OutputRoot.path_join(run_id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output_dir))
	DisplayServer.window_set_size(CaptureSize)
	root.size = CaptureSize
	root.content_scale_size = CaptureSize
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	# 1. A real world: open the start Site, depart, plan, travel ~45 %.
	RegionTravelSite.scene_handoff = false
	var lab := TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller.save_root = _output_dir.path_join("archive")
	var world_id := "travel_capture_%d" % Time.get_ticks_msec()
	var opened: Dictionary = lab.site_controller.open_fixed_world(RegionData.DEFAULT_MANIFEST, world_id, RegionEntry.SLOT, START, true)
	if not opened.ok: return _fail("world open: " + str(opened))
	var departed := RegionTravelSite.depart(lab.site_controller)
	if not departed.ok: return _fail("depart: " + str(departed))
	var slot: RegionSaveSlot = lab.site_controller.region_slot
	var status := slot.region_travel_status()
	var router := RegionData.new()
	router.load_manifest()
	var search := RegionRoute.Search.new()
	search.source = router
	search.start_site = status.site
	search.start_component = int(status.component)
	search.goal_site = GOAL
	var route := search.run()
	if not route.ok: return _fail("route: " + str(route))
	var planned := slot.set_region_travel_plan(route.steps)
	if not planned.ok: return _fail("plan: " + str(planned))
	var target := float(planned.game_seconds) * 0.45
	var travelled := 0.0
	while travelled < target:
		var advanced := slot.advance_region_travel(4)
		if not advanced.ok or bool(advanced.arrived): return _fail("advance: " + str(advanced))
		travelled += float(advanced.advanced)
	if not slot.checkpoint_region_travel().ok: return _fail("checkpoint")
	lab.queue_free()
	await process_frame
	# 2. The actual Region map scene in travel mode.
	RegionEntry.region_mode = "travel"
	RegionEntry.view = {"world_id": world_id, "slot_id": RegionEntry.SLOT, "manifest": RegionData.DEFAULT_MANIFEST}
	var scene := load(ScenePath) as PackedScene
	_viewer = scene.instantiate() as Control
	root.add_child(_viewer)
	for frame: int in range(4): await process_frame
	var panel: Node = _viewer.get("_travel")
	if panel == null or panel.get("slot") == null: return _fail("travel panel did not open: " + str(_viewer.get("_status").text))
	# Frame the whole route: 200 m Sites, route centre in view.
	var canvas: Control = _viewer.get("_canvas")
	var bounds: Array = _viewer.get("_bounds")
	var low := Vector2(minf(START.x, GOAL.x), minf(START.y, GOAL.y))
	var high := Vector2(maxf(START.x, GOAL.x), maxf(START.y, GOAL.y))
	var span := maxf(high.x - low.x + 3.0, high.y - low.y + 3.0) * 200.0
	# RegionLab bakes fine terrain tiles only below 32 visible Sites; 230 px per
	# Site keeps this short Yushan route in view and under that limit.
	var scale := maxf(minf(canvas.size.x, canvas.size.y) / span, 230.0 / 200.0)
	var centre := Vector2(((low.x + high.x) * 0.5 + 0.5) * 200.0 - float(bounds[0]), float(bounds[3]) - ((low.y + high.y) * 0.5 + 0.5) * 200.0)
	_viewer.set("_scale", scale)
	_viewer.set("_offset", canvas.size * 0.5 - centre * scale)
	_viewer.call("_update_transform")
	var waited := 0
	while waited < 1500:
		await process_frame
		waited += 1
		if waited > 30 and _viewer.get("_preview_thread") == null and (_viewer.get("_preview_queue") as Array).is_empty() and not bool(_viewer.get("_preview_dirty")): break
	for frame: int in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	if picture == null or picture.is_empty(): return _fail("empty GPU image")
	var path := _output_dir.path_join("travel_map.png")
	if picture.save_png(path) != OK: return _fail("png save")
	var result := {"png": ProjectSettings.globalize_path(path), "size": [picture.get_width(), picture.get_height()],
		"route_sites": route.steps.size(), "route_metres": route.metres, "travelled_game_seconds": travelled,
		"plan_game_seconds": planned.game_seconds, "clock": slot.control.logical_game_seconds, "status_text": str(panel.get("_status").text),
		"clock_text": str(panel.get("_clock").text), "info_text": str(panel.get("_info").text)}
	var file := FileAccess.open(_output_dir.path_join("capture_result.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("REGION_TRAVEL_CAPTURE_PASS: " + JSON.stringify(result))
	quit(0)
