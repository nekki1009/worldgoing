extends SceneTree

const SCENE_PATH := "res://scenes/region_lab/RegionLab.tscn"
const TestSource = preload("res://scripts/tests/region_lab_test_source.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const YUSHAN := Vector2i(1228, 12981)
const TAIPEI := Vector2i(1535, 13847)
const LIFECYCLE_LABELS: Array[String] = ["Taipei", "Yushan", "Penghu", "Green Island", "Lanyu"]
const EXPECTED_CANVAS_SUBMISSIONS := 520 # 20 ground + 20 water + 400 detail + 20 rows x 4 cliff passes.

var _started := false
var _finished := false
var _deadline_usec := 0
var _failures: Array[String] = []
var _report: Dictionary = {}
var _frame_us: Array[int] = []
var _frame_events: Array[Dictionary] = []
var _last_frame_usec := 0
var _lifecycle_mode := false
var _lifecycle_max_event: Dictionary = {}
var _lifecycle_slow_count := 0
var _lifecycle_slow_examples: Array[Dictionary] = []
var _vsync_diagnostic_mode := false
var _blank_memory: Dictionary = {}
var _scene_memory: Dictionary = {}
var _blank_process_us: Array[int] = []
var _overview_process_us: Array[int] = []
var _blank_process_warmup_us: Array[int] = []
var _overview_process_warmup_us: Array[int] = []
var _overview_command_us: Array[int] = []
var _blank_process_duration_usec := 0
var _overview_process_duration_usec := 0
var _lifecycle_sites: Array[Vector2i] = []

func _init() -> void:
	call_deferred("_run")

func _process(_delta: float) -> bool:
	if _started and not _finished and Time.get_ticks_usec() > _deadline_usec:
		_failures.append("async_scene_timeout")
		_finish()
	return false

func _run() -> void:
	_started = true
	_deadline_usec = Time.get_ticks_usec() + 30_000_000
	_vsync_diagnostic_mode = "--diagnostic-vsync-off" in OS.get_cmdline_user_args()
	if _vsync_diagnostic_mode:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if "--mode=blank-frame-probe" in OS.get_cmdline_user_args():
		await _blank_frame_probe()
		return
	var overview_probe := "--mode=overview-cpu-probe" in OS.get_cmdline_user_args()
	var lifecycle := "--mode=lifecycle" in OS.get_cmdline_user_args()
	if lifecycle or overview_probe:
		_deadline_usec = Time.get_ticks_usec() + 60_000_000 # Blank-scene sampling precedes the later 150-second lifecycle deadline.
	var test_manifest := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--manifest="):
			test_manifest = argument.trim_prefix("--manifest=")
	if lifecycle or overview_probe:
		for frame_index: int in range(180):
			await process_frame
			_blank_process_warmup_us.append(roundi(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1_000_000.0))
		var blank_started := Time.get_ticks_usec()
		for frame_index: int in range(600):
			await process_frame
			_blank_process_us.append(roundi(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1_000_000.0))
		_blank_process_duration_usec = Time.get_ticks_usec() - blank_started
		_blank_memory = _memory_snapshot()
	var scene := load(SCENE_PATH) as PackedScene
	if scene == null:
		_failures.append("region_lab_scene_not_loaded")
		_finish()
		return
	var lab: Variant = scene.instantiate()
	if not test_manifest.is_empty():
		TestSource.selected_manifest = test_manifest
		lab.source = TestSource.new()
	root.add_child(lab)
	current_scene = lab
	await process_frame
	if not lab.has_method("select_site"):
		_failures.append("scene_script_not_loaded")
		_finish()
		return
	if lab.source.manifest.is_empty():
		_failures.append("real_atlas_not_loaded")
		_finish()
		return
	_report["manifest_sha256"] = lab.source.manifest_hash
	_report["manifest_path"] = test_manifest if not test_manifest.is_empty() else "default"
	_report["display_server"] = DisplayServer.get_name()
	_report["window_environment"] = _window_environment()
	_report["scene"] = "res://scenes/region_lab/RegionLab.tscn"
	_report["diagnostic_vsync_disabled"] = _vsync_diagnostic_mode
	if lifecycle or overview_probe:
		_lifecycle_mode = lifecycle
		_deadline_usec = Time.get_ticks_usec() + 150_000_000
		if lifecycle:
			for label: String in LIFECYCLE_LABELS:
				var found := false
				for entry: Dictionary in lab.source.manifest.get("preview_sites", []):
					if str(entry.get("label", "")) == label and entry.get("site", []) is Array \
							and entry.site.size() == 2:
						_lifecycle_sites.append(Vector2i(int(entry.site[0]), int(entry.site[1])))
						found = true
						break
				if not found:
					_failures.append("lifecycle_preview_missing:" + label)
			if not _failures.is_empty():
				_finish()
				return
		await RenderingServer.frame_post_draw
		_scene_memory = _memory_snapshot()
		var anchor: Vector2 = lab._canvas.size * 0.5
		for frame_index: int in range(180):
			lab._zoom(1.005 if frame_index % 2 == 0 else 1.0 / 1.005, anchor)
			lab._offset += Vector2(1.0 if frame_index % 2 == 0 else -1.0, 0.0)
			lab._update_transform()
			await process_frame
			_overview_process_warmup_us.append(roundi(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1_000_000.0))
		var overview_started := Time.get_ticks_usec()
		for frame_index: int in range(600):
			var command_started := Time.get_ticks_usec()
			lab._zoom(1.005 if frame_index % 2 == 0 else 1.0 / 1.005, anchor)
			lab._offset += Vector2(1.0 if frame_index % 2 == 0 else -1.0, 0.0)
			lab._update_transform()
			_overview_command_us.append(Time.get_ticks_usec() - command_started)
			await process_frame
			_overview_process_us.append(roundi(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1_000_000.0))
		_overview_process_duration_usec = Time.get_ticks_usec() - overview_started
		lab._fit_view()
		if overview_probe:
			var overview_metrics := _overview_process_metrics()
			_report["overview_process"] = overview_metrics
			_report["memory_probe"] = {"blank": _blank_memory, "regionlab_loaded": _scene_memory,
				"static_scene_increment_bytes": int(_scene_memory.static_bytes) - int(_blank_memory.static_bytes)}
			if _blank_process_us.size() != 600 or _overview_process_us.size() != 600 \
					or float(overview_metrics.pan_zoom_p95_ms) <= 0.0:
				_failures.append("overview_process_monitor_unavailable")
			elif float(overview_metrics.p95_increment_ms) > 2.0:
				_failures.append("overview_process_increment_over_2ms")
			_finish()
			return
		await _lifecycle(lab)
		_finish()
		return
	var first: Dictionary = lab.select_site(YUSHAN)
	if not first.ok:
		_failures.append("yushan_select:" + str(first.get("code", "UNKNOWN")))
		_finish()
		return
	lab.request_open_selected_site()
	if lab._open_thread == null:
		_failures.append("yushan_thread_not_started")
		_finish()
		return
	await _sample_frame(lab, "yushan_worker")
	var second: Dictionary = lab.select_site(TAIPEI)
	if not second.ok:
		_failures.append("taipei_select:" + str(second.get("code", "UNKNOWN")))
		_finish()
		return
	lab.request_open_selected_site()
	if lab._queued_open_site != TAIPEI:
		_failures.append("new_selection_not_queued")
	while not lab.site_visible and Time.get_ticks_usec() < _deadline_usec:
		await _sample_frame(lab, "taipei_queued_worker")
	# Keep the frame after full readiness, including the last canvas submission.
	await _sample_frame(lab, "terrain_first_draw_followup")
	var shown: bool = lab.site_visible and lab.terrain != null
	_report["rapid_switch"] = {"selected_site": [lab.selected_site.x, lab.selected_site.y],
		"shown": shown, "queued_result_discarded": shown and lab.terrain.parameters.fixed_base.site == [TAIPEI.x, TAIPEI.y],
		"actor_site_id": str(lab.terrain.parameters.fixed_base.site_id) if shown else ""}
	if not shown or lab.selected_site != TAIPEI or lab.terrain.parameters.fixed_base.site != [TAIPEI.x, TAIPEI.y]:
		_failures.append("stale_yushan_result_replaced_taipei")
		_finish()
		return
	lab.show_overview()
	await _sample_frame(lab, "return_overview")
	var third: Dictionary = lab.select_site(YUSHAN)
	if not third.ok:
		_failures.append("cancel_select:" + str(third.get("code", "UNKNOWN")))
		_finish()
		return
	lab.request_open_selected_site()
	if lab._open_thread == null:
		_failures.append("cancel_thread_not_started")
		_finish()
		return
	lab.show_overview()
	while lab._open_thread != null and Time.get_ticks_usec() < _deadline_usec:
		await _sample_frame(lab, "cancel_worker")
	await _sample_frame(lab, "cancel_discard_followup")
	_report["cancel"] = {"site_visible": lab.site_visible, "terrain_retained": lab.terrain != null,
		"thread_finished": lab._open_thread == null, "selected_site": [lab.selected_site.x, lab.selected_site.y]}
	if lab._open_thread != null or lab.site_visible or lab.terrain != null:
		_failures.append("cancel_shown_or_retained_stale_site")
	# Keep the first user-visible draw in the strict maximum, then observe one
	# repeat draw separately to distinguish first-use setup from recurring cost.
	var repeat_selection: Dictionary = lab.select_site(TAIPEI)
	if not repeat_selection.ok:
		_failures.append("repeat_select:" + str(repeat_selection.get("code", "UNKNOWN")))
	else:
		lab.request_open_selected_site()
		while not lab.site_visible and Time.get_ticks_usec() < _deadline_usec:
			await _sample_frame(lab, "repeat_taipei_worker")
		await _sample_frame(lab, "repeat_terrain_first_draw_followup")
		if not lab.site_visible or lab.terrain == null or lab.terrain.parameters.fixed_base.site != [TAIPEI.x, TAIPEI.y]:
			_failures.append("repeat_taipei_not_shown")
	# Cancel after the renderer has actually submitted a partial image, then
	# replace a second partial image with a different Site.
	lab.show_overview()
	await _sample_frame(lab, "before_render_cancel")
	for scenario: int in range(2):
		var selected: Dictionary = lab.select_site(YUSHAN)
		if not selected.ok:
			_failures.append("render_interruption_select_%d" % scenario)
			break
		lab.request_open_selected_site()
		while (not lab.render_pending or lab._renderer.display_samples.is_empty()) and Time.get_ticks_usec() < _deadline_usec:
			await _sample_frame(lab, "render_interruption_wait_%d" % scenario)
		var partial_count: int = lab._renderer.display_samples.size()
		if not lab.render_pending or lab.site_visible or lab.actor != null or lab._resource_view != null \
				or partial_count < 1 or partial_count >= EXPECTED_CANVAS_SUBMISSIONS:
			_failures.append("render_interruption_no_partial_canvas_%d" % scenario)
			break
		if scenario == 0:
			lab.show_overview()
			for followup: int in range(3):
				await _sample_frame(lab, "render_cancel_followup_%d" % followup)
			_report["render_cancel"] = {"submitted_before_cancel": partial_count,
				"pending": lab.render_pending, "renderer_pending": lab._renderer.display_pending,
				"retained_samples": lab._renderer.display_samples.size(), "site_visible": lab.site_visible,
				"terrain_retained": lab.terrain != null, "renderer_data_retained": lab._renderer.data != null,
				"actors": _count_actors(lab), "resource_view_retained": lab._resource_view != null,
				"cliff_cache_entries": lab._renderer._cliff_slice_batches.size()}
			if lab.render_pending or lab._renderer.display_pending or not lab._renderer.display_samples.is_empty() \
					or lab.site_visible or lab.terrain != null or lab._renderer.data != null \
					or lab._resource_view != null or _count_actors(lab) != 0 \
					or not lab._renderer._cliff_slice_batches.is_empty():
				_failures.append("render_cancel_retained_or_late_canvas")
		else:
			var replacement: Dictionary = lab.select_site(TAIPEI)
			if not replacement.ok or lab.render_pending or lab._renderer.display_pending or lab.terrain != null:
				_failures.append("render_stale_not_cancelled_before_replacement")
				break
			lab.request_open_selected_site()
			while not lab.site_visible and Time.get_ticks_usec() < _deadline_usec:
				await _sample_frame(lab, "render_replacement_taipei")
			await _sample_frame(lab, "render_replacement_first_draw_followup")
			var replaced: bool = lab.site_visible and not lab.render_pending and not lab._renderer.display_pending \
				and lab.terrain != null and lab._renderer.data == lab.terrain \
				and lab.terrain.parameters.fixed_base.site == [TAIPEI.x, TAIPEI.y] \
				and lab.actor != null and lab.actor.data == lab.terrain and _count_actors(lab) == 1 \
				and lab._renderer.display_samples.size() == EXPECTED_CANVAS_SUBMISSIONS \
				and lab._renderer._cliff_slice_batches.is_empty()
			_report["render_replacement"] = {"submitted_before_replacement": partial_count,
				"selected_site": [lab.selected_site.x, lab.selected_site.y], "shown": replaced,
				"new_canvas_batches": lab._renderer.display_samples.size()}
			if not replaced:
				_failures.append("render_stale_yushan_overwrote_taipei")
	# A queued B must not survive when the player reselects the still-running A.
	lab.show_overview()
	await _sample_frame(lab, "before_aba_selection")
	var aba_a: Dictionary = lab.select_site(YUSHAN)
	if not aba_a.ok:
		_failures.append("aba_initial_a_selection_failed")
	else:
		lab.request_open_selected_site()
		var original_a_thread: Thread = lab._open_thread
		var aba_b: Dictionary = lab.select_site(TAIPEI)
		lab.request_open_selected_site()
		var b_was_queued: bool = aba_b.ok and lab._queued_open_site == TAIPEI
		var aba_return_a: Dictionary = lab.select_site(YUSHAN)
		lab.request_open_selected_site()
		var b_queue_cleared: bool = lab._queued_open_site == null
		var original_a_retained: bool = lab._open_thread == original_a_thread
		var b_worker_seen := false
		while not lab.site_visible and Time.get_ticks_usec() < _deadline_usec:
			await _sample_frame(lab, "aba_wait_a")
			if lab._open_thread != null and lab._open_request_site == TAIPEI:
				b_worker_seen = true
		await _sample_frame(lab, "aba_a_first_draw_followup")
		var a_shown: bool = lab.site_visible and lab.selected_site == YUSHAN and lab.terrain != null \
			and lab.terrain.parameters.fixed_base.site == [YUSHAN.x, YUSHAN.y]
		_report["queued_selection_aba"] = {"b_queued": b_was_queued, "a_reselected": aba_return_a.ok,
			"b_queue_cleared": b_queue_cleared, "original_a_worker_retained": original_a_retained,
			"b_worker_seen": b_worker_seen, "a_shown": a_shown}
		if not b_was_queued or not aba_return_a.ok or not b_queue_cleared \
				or not original_a_retained or b_worker_seen or not a_shown:
			_failures.append("queued_selection_aba_did_not_keep_a")
	# Cancelling a worker must restore the button for the same valid selection.
	lab.show_overview()
	await _sample_frame(lab, "before_cancel_reopen")
	var cancel_a: Dictionary = lab.select_site(YUSHAN)
	if not cancel_a.ok:
		_failures.append("cancel_reopen_initial_selection_failed")
	else:
		lab.request_open_selected_site()
		var cancel_worker_started: bool = lab._open_thread != null
		lab.show_overview()
		while lab._open_thread != null and Time.get_ticks_usec() < _deadline_usec:
			await _sample_frame(lab, "cancel_reopen_wait_cancelled_worker")
		await _sample_frame(lab, "cancel_reopen_button_followup")
		var button_restored: bool = not lab._open_button.disabled and lab.selected_site == YUSHAN \
			and not lab.site_visible and lab._open_thread == null
		lab.request_open_selected_site() # Intentionally no select_site call here.
		var same_a_reopen_started: bool = lab._open_thread != null and lab._open_request_site == YUSHAN
		while not lab.site_visible and Time.get_ticks_usec() < _deadline_usec:
			await _sample_frame(lab, "cancel_reopen_wait_a")
		await _sample_frame(lab, "cancel_reopen_a_first_draw_followup")
		var same_a_shown: bool = lab.site_visible and lab.terrain != null \
			and lab.terrain.parameters.fixed_base.site == [YUSHAN.x, YUSHAN.y]
		_report["cancel_worker_reopen"] = {"worker_started": cancel_worker_started,
			"button_restored": button_restored, "same_a_reopen_started": same_a_reopen_started,
			"same_a_shown": same_a_shown}
		if not cancel_worker_started or not button_restored or not same_a_reopen_started or not same_a_shown:
			_failures.append("cancel_worker_left_open_unusable")
	var sorted_frames: Array[int] = _frame_us.duplicate()
	sorted_frames.sort()
	var max_frame_ms := _percentile_ms(sorted_frames, 1.0)
	var max_index := -1
	for index: int in range(_frame_events.size()):
		if max_index < 0 or int(_frame_events[index].usec) > int(_frame_events[max_index].usec):
			max_index = index
	var slow_frames: Array[Dictionary] = []
	for event: Dictionary in _frame_events:
		if int(event.usec) >= 40_000:
			slow_frames.append(event)
	var completion_draws: Array[Dictionary] = []
	for event: Dictionary in _frame_events:
		if event.phase == "completion_apply_and_first_draw":
			completion_draws.append(event)
	_report["frames"] = {"samples": _frame_us.size(),
		"p95_ms": _percentile_ms(sorted_frames, 0.95), "max_ms": max_frame_ms,
		"target_max_ms": 50.0, "target_met": max_frame_ms >= 0.0 and max_frame_ms <= 50.0,
		"max_event": _frame_events[max_index] if max_index >= 0 else {},
		"before_max": _frame_events[max_index - 1] if max_index > 0 else {},
		"after_max": _frame_events[max_index + 1] if max_index >= 0 and max_index + 1 < _frame_events.size() else {},
		"slow_frames_over_40ms": slow_frames,
		"first_and_repeat_completion_draws": completion_draws,
		"scope": "Observed RegionLab frame intervals during async open/cancel; display mode and hardware specific"}
	if DisplayServer.get_name() != "headless" and max_frame_ms > 50.0:
		_failures.append("frame_gap_over_50ms")
	_report["scope"] = "Isolated RegionLab scene; formal project main entry not changed"
	_finish()

func _blank_frame_probe() -> void:
	var intervals: Array[int] = []
	var last_usec := 0
	var slow_frames: Array[Dictionary] = []
	for frame_index: int in range(100):
		await process_frame
		var now := Time.get_ticks_usec()
		if last_usec != 0:
			var interval := now - last_usec
			intervals.append(interval)
			if interval >= 40_000:
				slow_frames.append({"frame_index": frame_index, "usec": interval,
					"window_focused": _display_call(&"window_is_focused")})
		last_usec = now
	intervals.sort()
	print("REGION_LAB_BLANK_FRAME_DIAGNOSTIC ", JSON.stringify({"samples": intervals.size(),
		"p95_ms": _percentile_ms(intervals, 0.95), "max_ms": _percentile_ms(intervals, 1.0),
		"slow_frames_over_40ms": slow_frames, "window_environment": _window_environment(),
		"scope": "Blank GPU process-frame timing on the same desktop; diagnostic only"}))
	_finished = true
	quit(0)

func _lifecycle(lab: Variant) -> void:
	var baseline_nodes := _count_nodes(lab)
	var completion_us: Array[int] = []
	var site_sequence: Array[Array] = []
	var cycle_diagnostics: Array[Dictionary] = []
	var all_batch_us: Array[int] = []
	var by_kind_us: Array[Array] = [[], [], [], []]
	var over_4ms_count := 0
	var over_4ms_examples: Array[Dictionary] = []
	var batch_counts: Array[int] = []
	var diagnostic_validation_us: Array[int] = []
	var diagnostic_write_us: Array[int] = []
	var batch_path := "res://output/region_lab_real_acceptance/lifecycle_batches_%d.jsonl" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(batch_path.get_base_dir()))
	var batch_file := FileAccess.open(batch_path, FileAccess.WRITE)
	if batch_file == null:
		_failures.append("lifecycle_batch_log_open_failed:%s" % error_string(FileAccess.get_open_error()))
		return
	var memory_after_return: Array[int] = []
	var texture_after_return: Array[int] = []
	var video_after_return: Array[int] = []
	var nodes_after_return: Array[int] = []
	var cache_after_return: Array[int] = []
	var actor_count_after_return: Array[int] = []
	var resource_node_accounts: Array[Dictionary] = []
	var memory_after_warmup := -1
	var peak_nodes := baseline_nodes
	var peak_expected_nodes := baseline_nodes + 1
	var peak_cache_bytes := 0
	var start_memory := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	var peak_memory := _scene_memory.duplicate()
	for i: int in range(100):
		if Time.get_ticks_usec() >= _deadline_usec:
			_failures.append("lifecycle_timeout_at_%d" % i)
			break
		var site: Vector2i = _lifecycle_sites[i % _lifecycle_sites.size()]
		var first_frame_index := _frame_us.size()
		var selected: Dictionary = lab.select_site(site)
		if not selected.ok:
			_failures.append("lifecycle_select_%d:%s" % [i, str(selected.get("code", "UNKNOWN"))])
			break
		var open_start := Time.get_ticks_usec()
		lab.request_open_selected_site()
		if lab._open_thread == null:
			_failures.append("lifecycle_thread_not_started_%d" % i)
			break
		while not lab.site_visible and Time.get_ticks_usec() < _deadline_usec:
			await _sample_frame(lab, "lifecycle_worker_%d" % i)
		await _sample_frame(lab, "lifecycle_first_draw_%d" % i)
		if lab._open_thread != null or not lab.site_visible or lab.terrain == null or lab.selected_site != site:
			_failures.append("lifecycle_site_not_shown_%d" % i)
			break
		if lab.terrain.parameters.fixed_base.site != [site.x, site.y] or lab.actor == null or _count_actors(lab) != 1:
			_failures.append("lifecycle_wrong_owner_or_actor_%d" % i)
			break
		if lab.render_pending or lab._renderer.display_pending:
			_failures.append("lifecycle_declared_ready_before_render_complete_%d" % i)
			break
		var shown_memory := _memory_snapshot()
		for key: String in peak_memory:
			peak_memory[key] = maxi(int(peak_memory[key]), int(shown_memory[key]))
		completion_us.append(Time.get_ticks_usec() - open_start)
		site_sequence.append([site.x, site.y])
		var diagnostic_started := Time.get_ticks_usec()
		var display_samples: Array = lab._renderer.display_samples
		batch_counts.append(display_samples.size())
		if display_samples.size() != EXPECTED_CANVAS_SUBMISSIONS:
			_failures.append("lifecycle_incomplete_canvas_batches_%d_%d" % [i, display_samples.size()])
			break
		for kind: int in range(4):
			var passes: Array = [null]
			if kind == 1:
				passes.clear()
				for sample: Dictionary in display_samples:
					if int(sample.kind) == 1 and sample.has("cliff_pass") and not passes.has(sample.cliff_pass):
						passes.append(sample.cliff_pass)
				if passes.size() != 4:
					_failures.append("lifecycle_cliff_pass_count_%d_%d" % [i, passes.size()])
			for pass_id: Variant in passes:
				var covered := PackedByteArray()
				covered.resize(lab.terrain.size.x * lab.terrain.size.y)
				for sample: Dictionary in display_samples:
					if int(sample.kind) != kind or (kind == 1 and sample.get("cliff_pass") != pass_id):
						continue
					var row_start := int(sample.row_start)
					var row_end := int(sample.row_end)
					var column_start := int(sample.column_start)
					var column_end := int(sample.column_end)
					if row_start < 0 or row_end > lab.terrain.size.y or row_start >= row_end \
							or column_start < 0 or column_end > lab.terrain.size.x or column_start >= column_end:
						_failures.append("lifecycle_invalid_canvas_span_%d_%d" % [i, kind])
						break
					for row: int in range(row_start, row_end):
						for column: int in range(column_start, column_end):
							covered[row * lab.terrain.size.x + column] += 1
				for cell_index: int in range(covered.size()):
					if covered[cell_index] != 1:
						_failures.append("lifecycle_canvas_cell_coverage_%d_%d_%s_%d" % [i, kind, str(pass_id), cell_index])
						break
		for sample: Dictionary in display_samples:
			var elapsed: int = int(sample.usec)
			all_batch_us.append(elapsed)
			by_kind_us[int(sample.kind)].append(elapsed)
			if elapsed > 4000:
				over_4ms_count += 1
				if over_4ms_examples.size() < 100:
					var example: Dictionary = sample.duplicate()
					example["cycle"] = i
					example["site"] = [site.x, site.y]
					over_4ms_examples.append(example)
		var batch_json_line := JSON.stringify({"cycle": i, "site": [site.x, site.y], "samples": display_samples}) + "\n"
		for row_start: int in range(0, lab.terrain.size.y, 5):
			var observed_passes: Array[int] = []
			for sample: Dictionary in display_samples:
				if int(sample.kind) == 1 and int(sample.row_start) == row_start:
					observed_passes.append(int(sample.cliff_pass))
			if observed_passes != [0, 1, 2, 3]:
				_failures.append("lifecycle_cliff_pass_order_%d_%d:%s" % [i, row_start, str(observed_passes)])
		for row: int in range(lab.terrain.size.y):
			var observed_columns: Array[int] = []
			for sample: Dictionary in display_samples:
				if int(sample.kind) == 3 and int(sample.row_start) == row:
					observed_columns.append(int(sample.column_start))
			if observed_columns != [0, 25, 50, 75]:
				_failures.append("lifecycle_detail_column_order_%d_%d:%s" % [i, row, str(observed_columns)])
		if not lab._renderer._cliff_slice_batches.is_empty():
			_failures.append("lifecycle_cliff_cache_retained_%d" % i)
		var cycle_max_usec := 0
		for frame_index: int in range(first_frame_index, _frame_us.size()):
			cycle_max_usec = maxi(cycle_max_usec, _frame_us[frame_index])
		cycle_diagnostics.append({"index": i, "site": [site.x, site.y],
			"open_frame_max_ms": cycle_max_usec / 1000.0,
			"open_frame_samples": _frame_us.size() - first_frame_index})
		var resource_account := _resource_node_account(lab)
		if not lab.terrain.resource_base.is_empty() and lab._resource_view == null:
			_failures.append("lifecycle_missing_resource_view_%d" % i)
			break
		if int(resource_account.get("actual_rows", 0)) != int(resource_account.rows) \
				or int(resource_account.get("actual_row_nodes", 0)) != int(resource_account.rows) \
				or int(resource_account.get("actual_runs", 0)) != int(resource_account.resource_runs) \
					+ int(resource_account.feature_runs):
			_failures.append("lifecycle_resource_row_or_run_count_%d" % i)
			break
		var shown_nodes := _count_nodes(lab)
		var expected_nodes := baseline_nodes + 1 + int(resource_account.total_nodes)
		resource_account["cycle"] = i
		resource_account["site"] = [site.x, site.y]
		resource_account["actual_scene_nodes"] = shown_nodes
		resource_account["expected_scene_nodes"] = expected_nodes
		resource_node_accounts.append(resource_account)
		peak_nodes = maxi(peak_nodes, shown_nodes)
		peak_expected_nodes = maxi(peak_expected_nodes, expected_nodes)
		if shown_nodes != expected_nodes:
			_failures.append("lifecycle_resource_node_budget_%d_%d_%d" % [i, shown_nodes, expected_nodes])
			break
		var cache: Dictionary = lab.source.cache_stats()
		peak_cache_bytes = maxi(peak_cache_bytes, int(cache.peak_bytes))
		if int(cache.tiles) > 9 or int(cache.bytes) > 64 * 1024 * 1024:
			_failures.append("lifecycle_cache_limit_%d" % i)
			break
		diagnostic_validation_us.append(Time.get_ticks_usec() - diagnostic_started)
		# Exclude only test-side validation/serialization from the next UI frame gap.
		_last_frame_usec = Time.get_ticks_usec()
		lab.show_overview()
		await _sample_frame(lab, "lifecycle_return_%d" % i)
		var returned_nodes := _count_nodes(lab)
		var returned_actors := _count_actors(lab)
		nodes_after_return.append(returned_nodes)
		actor_count_after_return.append(returned_actors)
		var returned_memory := _memory_snapshot()
		memory_after_return.append(int(returned_memory.static_bytes))
		texture_after_return.append(int(returned_memory.texture_bytes))
		video_after_return.append(int(returned_memory.video_bytes))
		for key: String in peak_memory:
			peak_memory[key] = maxi(int(peak_memory[key]), int(returned_memory[key]))
		cache_after_return.append(int(lab.source.cache_stats().bytes))
		if i == 4:
			memory_after_warmup = memory_after_return[-1]
		if returned_nodes != baseline_nodes or returned_actors != 0 or lab.actor != null or lab.terrain != null \
				or lab._resource_view != null \
				or lab._renderer.data != null or lab._open_thread != null:
			_failures.append("lifecycle_return_retained_state_%d" % i)
			break
		var write_started := Time.get_ticks_usec()
		batch_file.store_string(batch_json_line)
		diagnostic_write_us.append(Time.get_ticks_usec() - write_started)
		# File I/O belongs to the acceptance harness, not the RegionLab frame.
		_last_frame_usec = Time.get_ticks_usec()
		if i % 20 == 19:
			print("REGION_LAB_LIFECYCLE_PROGRESS switches=", i + 1)
	batch_file.flush()
	if batch_file.get_error() != OK:
		_failures.append("lifecycle_batch_log_write_failed:%s" % error_string(batch_file.get_error()))
	batch_file.close()
	var sorted_completion: Array[int] = completion_us.duplicate()
	sorted_completion.sort()
	var cold_completion: Array[int] = completion_us.slice(0, mini(5, completion_us.size()))
	cold_completion.sort()
	var warm_completion: Array[int] = completion_us.slice(mini(5, completion_us.size()), completion_us.size())
	warm_completion.sort()
	var sorted_frames: Array[int] = _frame_us.duplicate()
	sorted_frames.sort()
	var memory_delta := memory_after_return[-1] - memory_after_warmup if not memory_after_return.is_empty() and memory_after_warmup >= 0 else 0
	var static_map_increment := maxi(0, int(peak_memory.static_bytes) - int(_blank_memory.static_bytes))
	var video_map_increment := maxi(0, int(peak_memory.video_bytes) - int(_blank_memory.video_bytes))
	var texture_map_increment := maxi(0, int(peak_memory.texture_bytes) - int(_blank_memory.texture_bytes))
	var combined_map_increment := static_map_increment + video_map_increment
	var overview_metrics := _overview_process_metrics()
	var process_increment_ms := float(overview_metrics.p95_increment_ms)
	var max_frame_ms := _percentile_ms(sorted_frames, 1.0)
	all_batch_us.sort()
	var batch_costs: Array[Dictionary] = []
	for kind: int in range(4):
		by_kind_us[kind].sort()
		batch_costs.append({"kind": kind, "samples": by_kind_us[kind].size(),
			"p95_ms": _percentile_ms(by_kind_us[kind], 0.95),
			"max_ms": _percentile_ms(by_kind_us[kind], 1.0)})
	var site_costs: Array[Dictionary] = []
	for site_index: int in range(_lifecycle_sites.size()):
		var site: Vector2i = _lifecycle_sites[site_index]
		var frame_values: Array[int] = []
		for cycle: Dictionary in cycle_diagnostics:
			if cycle.site != [site.x, site.y]:
				continue
			frame_values.append(roundi(float(cycle.open_frame_max_ms) * 1000.0))
		frame_values.sort()
		site_costs.append({"site": [site.x, site.y], "samples": frame_values.size(),
			"open_frame_p95_ms": _percentile_ms(frame_values, 0.95),
			"open_frame_max_ms": _percentile_ms(frame_values, 1.0)})
	_report["lifecycle"] = {"switches": completion_us.size(), "site_sequence": site_sequence,
		"cycle_diagnostics": cycle_diagnostics, "site_costs": site_costs,
		"batch_samples_jsonl": ProjectSettings.globalize_path(batch_path),
		"batch_count_after_each_open": batch_counts,
		"batch_p95_ms": _percentile_ms(all_batch_us, 0.95),
		"batch_max_ms": _percentile_ms(all_batch_us, 1.0), "batch_target_max_ms": 4.0,
		"batch_by_kind": batch_costs, "batches_over_4ms_count": over_4ms_count,
		"batches_over_4ms_first_100": over_4ms_examples,
		"excluded_test_validation_usec": diagnostic_validation_us,
		"excluded_test_file_write_usec": diagnostic_write_us,
		"completion_ms": _as_ms(completion_us), "completion_p95_ms": _percentile_ms(sorted_completion, 0.95),
		"completion_p99_ms": _percentile_ms(sorted_completion, 0.99),
		"completion_max_ms": _percentile_ms(sorted_completion, 1.0),
		"cold_complete_p95_ms": _percentile_ms(cold_completion, 0.95), "cold_target_p95_ms": 2000.0,
		"warm_complete_p95_ms": _percentile_ms(warm_completion, 0.95), "warm_target_p95_ms": 500.0,
		"frame_samples": _frame_us.size(), "frame_p95_ms": _percentile_ms(sorted_frames, 0.95),
		"frame_p99_ms": _percentile_ms(sorted_frames, 0.99), "frame_max_ms": max_frame_ms,
		"max_frame_event": _lifecycle_max_event, "slow_frame_count_over_40ms": _lifecycle_slow_count,
		"slow_frame_examples": _lifecycle_slow_examples,
		"static_memory_before_bytes": start_memory, "static_memory_after_each_return_bytes": memory_after_return,
		"static_memory_after_5_warmup_bytes": memory_after_warmup,
		"static_memory_growth_after_warmup_bytes": memory_delta,
		"memory_blank_scene_before_regionlab_bytes": _blank_memory,
		"memory_regionlab_loaded_bytes": _scene_memory,
		"memory_peak_bytes": peak_memory,
		"texture_memory_after_each_return_bytes": texture_after_return,
		"video_memory_after_each_return_bytes": video_after_return,
		"static_map_peak_increment_bytes": static_map_increment,
		"texture_map_peak_increment_bytes": texture_map_increment,
		"video_map_peak_increment_bytes": video_map_increment,
		"static_plus_video_peak_increment_bytes": combined_map_increment,
		"cpu_map_increment_target_bytes": 128 * 1024 * 1024,
		"texture_map_increment_target_bytes": 128 * 1024 * 1024,
		"memory_scope": "Godot Performance monitors. Video and texture are engine-reported estimates; texture is a subset of video and must not be counted twice. These monitors are not OS process memory or VRAM.",
		"memory_sample_points": "Blank SceneTree after 180 warmup and 600 monitor-observation frames; RegionLab ready after frame_post_draw; each of 100 fully shown Sites before test validation; each return after one frame. Peak is maximum of these samples, not an instantaneous allocator spike.",
		"overview_process": overview_metrics,
		"cache_bytes_after_each_return": cache_after_return, "peak_cache_bytes": peak_cache_bytes,
		"baseline_nodes": baseline_nodes, "peak_nodes": peak_nodes,
		"peak_expected_nodes": peak_expected_nodes, "resource_node_accounts": resource_node_accounts,
		"nodes_after_each_return": nodes_after_return, "actors_after_each_return": actor_count_after_return,
		"scope": "100 real RegionLab UI opens and returns on this GPU; fixed five-site cycle; original formal entry untouched"}
	if completion_us.size() != 100:
		_failures.append("lifecycle_incomplete_100_switches")
	if cold_completion.size() == 5 and _percentile_ms(cold_completion, 0.95) > 2000.0:
		_failures.append("lifecycle_cold_ready_p95_over_2s")
	if warm_completion.size() == 95 and _percentile_ms(warm_completion, 0.95) > 500.0:
		_failures.append("lifecycle_warm_ready_p95_over_500ms")
	if max_frame_ms > 50.0:
		_failures.append("lifecycle_frame_gap_over_50ms")
	if over_4ms_count > 0:
		_failures.append("lifecycle_canvas_batch_over_4ms")
	if memory_after_warmup >= 0 and memory_delta > 16 * 1024 * 1024:
		_failures.append("lifecycle_memory_growth_over_16_mib")
	if int(peak_memory.texture_bytes) <= 0:
		_failures.append("lifecycle_texture_memory_monitor_unavailable")
	if static_map_increment > 128 * 1024 * 1024:
		_failures.append("lifecycle_cpu_map_increment_over_128_mib")
	if texture_map_increment > 128 * 1024 * 1024:
		_failures.append("lifecycle_texture_map_increment_over_128_mib")
	if _blank_process_us.size() != 600 or _overview_process_us.size() != 600 \
			or float(overview_metrics.pan_zoom_p95_ms) <= 0.0:
		_failures.append("lifecycle_overview_process_monitor_unavailable")
	elif process_increment_ms > 2.0:
		_failures.append("lifecycle_overview_process_increment_over_2ms")
	if peak_nodes != peak_expected_nodes:
		_failures.append("lifecycle_peak_node_count_exceeds_resource_account")
	_report["scope"] = "Isolated RegionLab visual UI lifecycle; original formal main entry not changed"

func _resource_node_account(lab: Variant) -> Dictionary:
	if lab._resource_view == null:
		return {"view": 0, "rows": 0, "resource_runs": 0, "feature_runs": 0, "total_nodes": 0,
			"actual_rows": 0, "actual_row_nodes": 0, "actual_runs": 0}
	var view: SiteResourceView = lab._resource_view
	var resource_runs := 0
	for row: int in range(lab.terrain.size.y):
		var previous_animated := -1
		for key: String in view.resources_by_row.get(row, []):
			var kind := int(lab.terrain.resource_base[key].kind)
			var animated := int(kind in [Env.Kind.WILDLIFE, Env.Kind.FISH])
			if animated != previous_animated:
				resource_runs += 1
				previous_animated = animated
	var feature_runs := 1 # Fresh fixed Site has one original depot row and no constructed features.
	var rows: int = lab.terrain.size.y
	var actual_runs := 0
	for row: Node2D in view.rows:
		actual_runs += row.get_child_count()
	return {"view": 1, "rows": rows, "resource_runs": resource_runs,
		"feature_runs": feature_runs, "total_nodes": 1 + rows + resource_runs + feature_runs,
		"actual_rows": view.rows.size(), "actual_row_nodes": view.get_child_count(),
		"actual_runs": actual_runs}

func _as_ms(values: Array[int]) -> Array[float]:
	var result: Array[float] = []
	for value: int in values:
		result.append(value / 1000.0)
	return result

func _count_nodes(node: Node) -> int:
	var total := 1
	for child: Node in node.get_children():
		total += _count_nodes(child)
	return total

func _count_actors(node: Node) -> int:
	var total := int(node is TerrainTestCharacter)
	for child: Node in node.get_children():
		total += _count_actors(child)
	return total

func _memory_snapshot() -> Dictionary:
	return {"static_bytes": int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		"texture_bytes": int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)),
		"video_bytes": int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))}

func _overview_process_metrics() -> Dictionary:
	var blank_sorted: Array[int] = _blank_process_us.duplicate()
	blank_sorted.sort()
	var overview_sorted: Array[int] = _overview_process_us.duplicate()
	overview_sorted.sort()
	var command_sorted: Array[int] = _overview_command_us.duplicate()
	command_sorted.sort()
	var blank_p95 := _percentile_ms(blank_sorted, 0.95)
	var overview_p95 := _percentile_ms(overview_sorted, 0.95)
	return {"blank_warmup_samples_usec": _blank_process_warmup_us,
		"pan_zoom_warmup_samples_usec": _overview_process_warmup_us,
		"blank_samples_usec": _blank_process_us, "pan_zoom_samples_usec": _overview_process_us,
		"blank_observed_value_runs": _monitor_value_runs(_blank_process_us),
		"pan_zoom_observed_value_runs": _monitor_value_runs(_overview_process_us),
		"blank_sample_duration_seconds": _blank_process_duration_usec / 1_000_000.0,
		"pan_zoom_sample_duration_seconds": _overview_process_duration_usec / 1_000_000.0,
		"blank_p95_ms": blank_p95, "pan_zoom_p95_ms": overview_p95,
		"p95_increment_ms": overview_p95 - blank_p95, "target_increment_ms": 2.0,
		"zoom_pan_transform_call_p95_ms": _percentile_ms(command_sorted, 0.95),
		"zoom_pan_transform_call_max_ms": _percentile_ms(command_sorted, 1.0),
		"scope": "Godot TIME_PROCESS process_max refreshes about once per second and includes render sync/draw. Each 600-frame phase follows a 180-frame warmup; actual duration and observed value runs above show how many update windows were sampled. Frame arrays repeat the current monitor value. Direct zoom/pan/transform call timing is auxiliary and excludes drawing. Isolated RegionLab, not formal main scene."}

func _monitor_value_runs(values: Array[int]) -> int:
	var runs := 0
	var previous := -1
	for value: int in values:
		if value != previous:
			runs += 1
			previous = value
	return runs

func _sample_frame(lab: Variant, requested_phase: String) -> void:
	var before := _scene_state(lab)
	await process_frame
	var now := Time.get_ticks_usec()
	var after := _scene_state(lab)
	var new_draw_count := maxi(int(after.submitted_segments) - int(before.submitted_segments), 0)
	var new_draw_usec := 0
	var new_draw_max_usec := 0
	var new_draws_by_kind: Array[int] = [0, 0, 0, 0]
	if new_draw_count > 0:
		for sample_index: int in range(int(before.submitted_segments), int(after.submitted_segments)):
			var sample: Dictionary = lab._renderer.display_samples[sample_index]
			var draw_usec := int(sample.usec)
			new_draw_usec += draw_usec
			new_draw_max_usec = maxi(new_draw_max_usec, draw_usec)
			new_draws_by_kind[int(sample.kind)] += 1
	var phase := requested_phase
	if before.render_pending and after.render_pending:
		phase = "render_segment"
	elif not before.render_pending and after.render_pending:
		phase = "render_begin"
	elif before.render_pending and not after.render_pending and after.visible:
		phase = "render_complete"
	elif before.render_pending and not after.render_pending and not after.visible:
		phase = "render_cancel_or_stale"
	elif before.thread and not after.thread and after.visible:
		phase = "completion_apply_and_first_draw"
	elif before.thread and not after.thread and not after.visible:
		phase = "cancel_or_stale_result_discard"
	elif not before.visible and after.visible:
		phase = "terrain_first_draw"
	elif before.visible and not after.visible:
		phase = "return_overview"
	if _last_frame_usec != 0:
		var elapsed := now - _last_frame_usec
		_frame_us.append(elapsed)
		var event := {"frame_index": _frame_us.size(), "usec": elapsed, "phase": phase,
			"requested_phase": requested_phase, "selected_site": [lab.selected_site.x, lab.selected_site.y],
			"before": before, "after": after, "new_draw_count": new_draw_count,
			"new_draw_usec": new_draw_usec, "new_draw_max_usec": new_draw_max_usec,
			"new_draws_by_kind": new_draws_by_kind,
			"window_focused": _display_call(&"window_is_focused"),
			"window_mode": _display_call(&"window_get_mode")}
		if _lifecycle_mode:
			if _lifecycle_max_event.is_empty() or elapsed > int(_lifecycle_max_event.usec):
				_lifecycle_max_event = event
			if elapsed >= 40_000:
				_lifecycle_slow_count += 1
				if _lifecycle_slow_examples.size() < 12:
					_lifecycle_slow_examples.append(event)
		else:
			_frame_events.append(event)
	_last_frame_usec = now

func _scene_state(lab: Variant) -> Dictionary:
	return {"thread": lab._open_thread != null,
		"worker_alive": lab._open_thread != null and lab._open_thread.is_alive(),
		"visible": lab.site_visible, "terrain": lab.terrain != null,
		"render_pending": lab.render_pending, "submitted_segments": lab._renderer.display_samples.size()}

func _percentile_ms(values: Array, fraction: float) -> float:
	return values[clampi(ceili(values.size() * fraction) - 1, 0, values.size() - 1)] / 1000.0 if not values.is_empty() else -1.0

func _display_call(method: StringName) -> Variant:
	return DisplayServer.call(method) if DisplayServer.has_method(method) else "UNAVAILABLE"

func _window_environment() -> Dictionary:
	var window_size := DisplayServer.window_get_size()
	return {"os": OS.get_name(), "window_focused": _display_call(&"window_is_focused"),
		"window_mode": _display_call(&"window_get_mode"),
		"vsync_mode": _display_call(&"window_get_vsync_mode"),
		"window_size_px": [window_size.x, window_size.y],
		"screen_refresh_rate_hz": DisplayServer.screen_get_refresh_rate(),
		"low_processor_usage_mode": OS.get("low_processor_usage_mode"),
		"low_processor_usage_mode_sleep_usec": OS.get("low_processor_usage_mode_sleep_usec"),
		"engine_max_fps": Engine.get("max_fps")}

func _finish() -> void:
	if _finished:
		return
	_finished = true
	_report["failures"] = _failures
	if _failures.is_empty():
		print("REGION_LAB_ASYNC_DIAGNOSTIC_PASS " if _vsync_diagnostic_mode else "REGION_LAB_ASYNC_PASS ", JSON.stringify(_report))
		quit(0)
	else:
		printerr("REGION_LAB_ASYNC_DIAGNOSTIC_FAIL " if _vsync_diagnostic_mode else "REGION_LAB_ASYNC_FAIL ", JSON.stringify(_report))
		quit(1)
