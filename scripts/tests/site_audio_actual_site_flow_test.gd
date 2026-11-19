extends SceneTree
## Actual ordinary Site owners, shared clock, native players and system controls.
## Does not prove Party publication, Native parity, device listening or performance.

const RESULT := "user://audio_actual_site_flow_result.json"
const STEP := 1.0 / 30.0
var lab: TerrainLab
var checks := 0
var failures: Array[String] = []
var finished := false
var settings_existed := false
var settings_bytes := PackedByteArray()

func _initialize() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func() -> void: _finish(false, "45-second actual Site deadline"))
	_run.call_deferred()

func _check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures.append(label)
		push_error("AUDIO_ACTUAL_SITE_FAIL: " + label)
	return value

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	paused = false
	if is_instance_valid(lab):
		lab.set_process(false)
		lab.free()
	if settings_existed:
		var previous := FileAccess.open(SiteAudioView.SETTINGS_PATH, FileAccess.WRITE)
		if previous != null: previous.store_buffer(settings_bytes)
	elif FileAccess.file_exists(SiteAudioView.SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SiteAudioView.SETTINGS_PATH))
	TerrainArmy.release_contact_source()
	var file := FileAccess.open(RESULT, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok":ok, "checks":checks, "failures":failures, "reason":reason,
			"scope":"actual ordinary TerrainLab/Actor shared-step -> SiteAudioView native player; original system slider/mute and local config, camera, pause, scene gating; excludes Party/Native/GPU/performance/listening/export"}, "\t"))
	print("AUDIO_ACTUAL_SITE_FLOW_", "PASS" if ok else "FAIL", " checks=", checks, " ", reason)
	quit(0 if ok else 1)

func _run() -> void:
	settings_existed = FileAccess.file_exists(SiteAudioView.SETTINGS_PATH)
	if settings_existed: settings_bytes = FileAccess.get_file_as_bytes(SiteAudioView.SETTINGS_PATH)
	var original_scene := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _check(original_scene != null, "formal TerrainLab scene loads"): _finish(false); return
	lab = original_scene.instantiate() as TerrainLab
	if not _check(lab != null and lab.has_method("_audio_boot_complete"), "actual Lab has merged audio hooks"): _finish(false); return
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	await process_frame
	await process_frame
	if not _check(lab.terrain != null and lab.site_controller != null and lab.audio_view != null,
		"real ready builds terrain, Controller and presenter"): _finish(false); return
	var view: SiteAudioView = lab.audio_view
	view.set_process(false)
	if not _check(bool(view.stats_snapshot().active), "original direct Site boot activates audio"): _finish(false); return
	# Original Controller builds its tool windows under the sibling Lab/SiteUI CanvasLayer.
	var system_window: Window = lab.site_controller.formal_windows.get("system")
	if not _check(system_window != null and system_window.is_inside_tree(),
		"original system tool window belongs to live SiteUI"): _finish(false); return
	lab.site_controller.open_window("system")
	var original_body := lab.character
	var body_before: Dictionary = original_body.capture_state()
	var site_before: Dictionary = lab.terrain.site.duplicate(true)
	var master := AudioServer.get_bus_index(&"Master")
	var master_db := AudioServer.get_bus_volume_db(master)
	var master_mute := AudioServer.is_bus_mute(master)
	var slider := system_window.find_child("SFXVolume", true, false) as HSlider
	var mute := system_window.find_child("SFXMute", true, false) as CheckButton
	if not _check(slider != null and mute != null and slider.editable and not mute.disabled
		and slider == lab.site_controller._audio_volume_slider and mute == lab.site_controller._audio_mute_toggle
		and system_window.is_ancestor_of(slider) and system_window.is_ancestor_of(mute),
		"original system column owns enabled SFX controls"): _finish(false); return
	slider.value = 37.0
	mute.button_pressed = true
	var config := ConfigFile.new()
	if not _check(config.load(SiteAudioView.SETTINGS_PATH) == OK and is_equal_approx(float(config.get_value("sfx", "volume", -1.0)), 0.37)
		and config.get_value("sfx", "muted", false) == true, "real UI callbacks persist SFX settings locally"):
		_finish(false); return
	if not _check(original_body.capture_state() == body_before and lab.terrain.site == site_before
		and AudioServer.get_bus_volume_db(master) == master_db and AudioServer.is_bus_mute(master) == master_mute,
		"SFX controls preserve original body/Site and Master"): _finish(false); return
	view.set_active(false)
	if not _check(view.set_active(true) and is_equal_approx(slider.value, 37.0) and mute.button_pressed,
		"real reactivation loads config and updates existing controls without rewriting gameplay"): _finish(false); return
	mute.button_pressed = false
	slider.value = 80.0
	view._process(0.0)
	if not _check(bool(view.stats_snapshot().listener_valid) and view.stats_snapshot().listener_ground == original_body.position,
		"native AudioListener reads original controlled ground"): _finish(false); return
	var ground: Vector2 = view.stats_snapshot().listener_ground
	var camera := lab.find_child("Camera2D", true, false) as Camera2D
	if camera == null:
		for child: Node in lab.get_children():
			if child is Camera2D: camera = child; break
	if not _check(camera != null, "actual Lab camera exists"): _finish(false); return
	var camera_ground := camera.position
	var camera_zoom := camera.zoom
	camera.position += Vector2(1000, -500)
	camera.zoom *= 0.5
	view._process(0.0)
	if not _check(view.stats_snapshot().listener_ground == ground, "camera pan and zoom preserve ground listener"):
		_finish(false); return
	camera.position = camera_ground
	camera.zoom = camera_zoom
	if not _true_step(original_body, view): _finish(false); return
	var played := int(view.stats_snapshot().played)
	lab.terrain.site.paused = true
	var rejected := lab._advance_original_shared_step(STEP)
	view._process(0.0)
	if not _check(not rejected.get("ok", true) and not bool(view.stats_snapshot().batch_open)
		and int(view.stats_snapshot().candidate_count) == 0 and int(view.stats_snapshot().short_count) == 0
		and int(view.stats_snapshot().played) == played, "original paused shared-step rejects and silences native players"):
		_finish(false); return
	lab.terrain.site.paused = false
	paused = true
	view._process(0.0)
	if not _check(int(view.stats_snapshot().short_count) == 0 and not bool(view.stats_snapshot().listener_valid),
		"actual tree pause stops audio immediately"): _finish(false); return
	paused = false
	var next := Node2D.new()
	root.add_child(next)
	current_scene = next
	view._process(0.0)
	if not _check(int(view.stats_snapshot().short_count) == 0 and int(view.stats_snapshot().loop_count) == 0
		and not bool(view.stats_snapshot().listener_valid), "leaving actual current scene silences all pools"):
		next.free(); _finish(false); return
	next.free()
	current_scene = lab
	_finish(failures.is_empty())

func _true_step(actor: TerrainTestCharacter, view: SiteAudioView) -> bool:
	actor.reset_combat()
	var admitted := false
	var source := actor.terrain_cell
	for direction: Vector2i in TerrainData.DIRECTIONS:
		if actor.step(direction, false):
			admitted = true
			break
	if not _check(admitted, "original Actor.step admits legal ordinary Site movement"): return false
	var duration: float = actor.get_move_interval(false)
	var offered := int(view.stats_snapshot().offered)
	var played := int(view.stats_snapshot().played)
	var intervals := 0
	while actor.is_moving() and intervals < 60:
		var result := lab._advance_original_shared_step(STEP)
		if not _check(bool(result.get("ok", false)) and bool(result.get("completed", false)),
			"actual original shared clock completes movement slice"): return false
		if actor.is_moving() and not _check(int(view.stats_snapshot().offered) == offered,
			"real shared clock offers no step before original endpoint"): return false
		view._process(0.0)
		intervals += 1
	if not _check(not actor.is_moving() and actor.terrain_cell != source and intervals * STEP + 0.000001 >= duration,
		"original movement reaches its legal endpoint with original duration"): return false
	return _check(int(view.stats_snapshot().offered) == offered + 1 and int(view.stats_snapshot().played) == played + 1
		and int(view.stats_snapshot().short_count) == 1 and not bool(view.stats_snapshot().batch_open),
		"true completed shared-step commits exactly one native footstep")
