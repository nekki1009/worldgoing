extends SceneTree
## 開始遊戲效能計畫 P0 probe (not an acceptance test): opens one new world from the main-menu request path, or resumes the
## last world with --perf-resume, and quits once the first frame after the world opened has been flushed by PerfTrace.
## Run with the user arguments --perf-trace [--perf-resume]; read the PERF_TRACE line. Output PERF_PROBE_DONE.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const PerfTrace = preload("res://scripts/terrain_lab/perf_trace.gd")
const START := Vector2i(1170, 13252)

func _initialize() -> void:
	create_timer(900.0).timeout.connect(func() -> void:
		printerr("PERF_PROBE_FAIL: deadline")
		quit(1))
	_run.call_deferred()

func _run() -> void:
	var resume := OS.get_cmdline_user_args().has("--perf-resume")
	var requested := RegionEntry.request_resume() if resume else RegionEntry.request_new_world(START, {"name": "計時者", "body": 0}, "計時世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "neutral"})
	if not requested:
		printerr("PERF_PROBE_FAIL: request ", RegionEntry.menu_message)
		quit(1)
		return
	PerfTrace.mark("start_pressed")
	change_scene_to_file(SITE)
	for _frame: int in range(20000):
		await process_frame
		var lab := current_scene as TerrainLab
		if lab != null and lab.site_controller != null and lab.site_controller.region_slot != null and lab.site_controller._boot_request.is_empty() and lab.crowd_site != null and lab.crowd_site.active:
			for _settle: int in range(5): await process_frame
			print("PERF_PROBE_DONE")
			quit(0)
			return
	printerr("PERF_PROBE_FAIL: the world never opened")
	quit(1)
