extends SceneTree
## 開始遊戲效能 P1-5 acceptance (visual): the loading screen while a world opens on the main thread.
## Part 1: the screen on a plain host — it presents at once, follows the start-chain stages, counts the cadre bodies,
## and is gone after finish(). The presented frame is read back: dark background, a bar that grows with the stages.
## Part 2: a real new world from the menu request path — the screen presents during the opening, is finished when the
## boot request settles, and leaves no node in the Lab.
## Output: START_PROGRESS_VISUAL_PASS on success; quit(1) on any failure or the deadline.

const SITE := "res://scenes/terrain_lab/TerrainLab.tscn"
const RegionEntry = preload("res://scripts/region_lab/region_entry.gd")
const StartProgress = preload("res://scripts/terrain_lab/start_progress.gd")
const PerfTrace = preload("res://scripts/terrain_lab/perf_trace.gd")
const START := Vector2i(1170, 13252)
const SHOTS := "user://start_progress_visual"

var _step := 0
var _done := false

func _initialize() -> void:
	create_timer(420.0).timeout.connect(func() -> void: _fail("420-second deadline"))
	_run.call_deferred()

func _fail(message: String) -> void:
	if _done: return
	_done = true
	printerr("START_PROGRESS_VISUAL_FAIL: ", message)
	quit(1)

func _check(ok: bool, label: String, detail: Variant = "") -> bool:
	_step += 1
	if ok:
		print("START_PROGRESS_VISUAL OK %d: %s" % [_step, label])
		return true
	_fail("%s %s" % [label, str(detail)])
	return false

func _frame() -> Image:
	return root.get_texture().get_image()

func _bar_fill(image: Image) -> float:
	# The bar spans 30–70 % of the width at the vertical centre; count the filled (bar colour) share of its row.
	var y := int(image.get_height() * 0.5) + 3
	var filled := 0
	var total := 0
	for x: int in range(int(image.get_width() * 0.3) + 2, int(image.get_width() * 0.7) - 2):
		total += 1
		if image.get_pixel(x, y).g > 0.55: filled += 1
	return float(filled) / maxf(1.0, float(total))

## Share of a 20 × 20 sample grid that has the loading background colour.
func _background_share(image: Image) -> float:
	var hits := 0
	for gy: int in range(20):
		for gx: int in range(20):
			var pixel := image.get_pixel(int((gx + 0.5) * image.get_width() / 20.0), int((gy + 0.5) * image.get_height() / 20.0))
			var back: Color = StartProgress.BACKGROUND
			if absf(pixel.r - back.r) < 0.03 and absf(pixel.g - back.g) < 0.03 and absf(pixel.b - back.b) < 0.03: hits += 1
	return float(hits) / 400.0

func _run() -> void:
	if not _check(StartProgress.available(), "a display is present (visual acceptance)", DisplayServer.get_name()): return
	DirAccess.make_dir_recursive_absolute(SHOTS)
	var host := Node2D.new()
	root.add_child(host)
	await process_frame
	StartProgress.begin(host, "正在建立新世界…")
	if not _check(StartProgress.active() and StartProgress.draws == 1, "begin presents the screen at once", StartProgress.draws): return
	var first := _frame()
	var corner := first.get_pixel(4, 4)
	if not _check(corner.r < 0.1 and corner.g < 0.12 and corner.b < 0.13, "the presented frame has the dark loading background", corner): return
	var empty_bar := _bar_fill(first)
	OS.delay_msec(StartProgress.MIN_REDRAW_MSEC + 30)
	PerfTrace.mark("open_begin")
	if not _check(StartProgress.draws == 2 and StartProgress.last_detail == "讀取地理資料", "a start-chain stage redraws with its text", [StartProgress.draws, StartProgress.last_detail]): return
	OS.delay_msec(StartProgress.MIN_REDRAW_MSEC + 30)
	PerfTrace.mark("bind_armies")
	var later := _frame()
	if not _check(_bar_fill(later) > empty_bar + 0.2, "the bar grows with the stages", [empty_bar, _bar_fill(later)]): return
	later.save_png(SHOTS.path_join("loading.png"))
	print("START_PROGRESS_VISUAL SHOT ", ProjectSettings.globalize_path(SHOTS.path_join("loading.png")))
	PerfTrace.mark("crowd_body")
	OS.delay_msec(StartProgress.MIN_REDRAW_MSEC + 30)
	PerfTrace.mark("crowd_body")
	if not _check(StartProgress.last_detail == "準備人物（2）", "each cadre body is counted on the screen", StartProgress.last_detail): return
	var before := StartProgress.draws
	PerfTrace.mark("crowd_body")
	if not _check(StartProgress.draws == before, "redraws are spaced (no redraw within the minimum interval)", [before, StartProgress.draws]): return
	PerfTrace.mark("not_a_stage")
	if not _check(StartProgress.active(), "an unknown stage only keeps the window alive"): return
	StartProgress.finish()
	await process_frame
	if not _check(not StartProgress.active() and host.get_node_or_null("StartProgress") == null, "finish removes the screen"): return
	StartProgress.stage("open_begin")
	if not _check(not StartProgress.active(), "a stage after finish draws nothing"): return
	host.queue_free()
	# Part 2: the real opening.
	var requested := RegionEntry.request_new_world(START, {"name": "載入者", "body": 0}, "載入世界", "", RegionData.DEFAULT_MANIFEST, {"mode": "neutral"})
	if not _check(requested, "a new world is requested", RegionEntry.menu_message): return
	change_scene_to_file(SITE)
	var lab: TerrainLab = null
	for _wait: int in range(20000):
		await process_frame
		lab = current_scene as TerrainLab
		if lab != null and lab.site_controller != null and lab.site_controller.region_slot != null and lab.site_controller._boot_request.is_empty() and lab.crowd_site != null and lab.crowd_site.active:
			break
	if not _check(lab != null and lab.crowd_site != null and lab.crowd_site.active, "the new world opens"): return
	if not _check(StartProgress.draws >= 8, "the screen was redrawn through the opening", StartProgress.draws): return
	if not _check(not StartProgress.active(), "the screen is finished once the boot request settled"): return
	await process_frame
	if not _check(lab.get_node_or_null("StartProgress") == null, "no loading node is left in the Lab"): return
	var opened := _frame()
	opened.save_png(SHOTS.path_join("opened.png"))
	if not _check(_background_share(opened) < 0.3 and _background_share(later) > 0.9, "the opened world is drawn, not the loading screen", [_background_share(opened), _background_share(later)]): return
	print("START_PROGRESS_VISUAL_PASS")
	_done = true
	quit(0)
