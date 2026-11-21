extends SceneTree
## One real failed ConfigFile write; original UI, SFX bus and shared Actor clock.
## Run alone through the unchanged canonical helper; retain all stderr/ERRORs.

const RESULT := "user://audio_settings_save_failure_result.json"
const STEP := 1.0 / 30.0
var lab: TerrainLab
var checks := 0
var failures: Array[String] = []
var finished := false
var settings_existed := false
var settings_bytes := PackedByteArray()
var settings_backup_ready := false
var fixture_directory_created := false
var evidence := {}

func _initialize() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func() -> void: _finish(false, "45-second real cfg failure deadline"))
	_run.call_deferred()

func _check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures.append(label)
		push_error("AUDIO_SETTINGS_SAVE_FAILURE_FAIL: " + label)
	return value

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	paused = false
	if is_instance_valid(lab):
		lab.set_process(false)
		lab.free()
	var cleaned := _restore_settings()
	if not _check(cleaned, "owned empty cfg directory removed and original cfg restored byte-exact or absent"):
		ok = false
	TerrainArmy.release_contact_source()
	evidence.merge({"behavior_assertions_ok":ok, "checks":checks, "failures":failures, "reason":reason,
		"process_id":OS.get_process_id(), "cleanup_verified":cleaned,
		"test_source_sha256":FileAccess.get_sha256(get_script().resource_path),
		"scope":"isolated real ConfigFile write rejection and original UI/SFX/body shared-step continuation; canonical stderr verdict remains separate and strict"})
	var result_bytes := JSON.stringify(evidence, "\t").to_utf8_buffer()
	var file := FileAccess.open(RESULT, FileAccess.WRITE)
	var receipt_ok := file != null
	if file != null:
		file.store_buffer(result_bytes)
		file.flush()
		receipt_ok = file.get_error() == OK
		file.close()
	if receipt_ok:
		var saved := FileAccess.open(RESULT, FileAccess.READ)
		receipt_ok = saved != null
		if saved != null:
			var saved_bytes := saved.get_buffer(saved.get_length())
			var read_error := saved.get_error()
			saved.close()
			receipt_ok = read_error == OK and saved_bytes == result_bytes
	if not receipt_ok:
		ok = false
		failures.append("behavior receipt could not be written and read back byte-exact")
		push_error("AUDIO_SETTINGS_SAVE_FAILURE_FAIL: " + failures.back())
	print("AUDIO_SETTINGS_SAVE_FAILURE_BEHAVIOR_", "PASS" if ok else "FAIL", " checks=", checks, " ", reason)
	quit(0 if ok else 1)

func _run() -> void:
	if not _check(SiteAudioView.SETTINGS_PATH == "user://audio_settings.cfg"
		and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(SiteAudioView.SETTINGS_PATH)),
		"canonical original settings filename has no pre-existing directory"):
		_finish(false); return
	settings_existed = FileAccess.file_exists(SiteAudioView.SETTINGS_PATH)
	if not _check(_backup_settings(), "readable original cfg backup precedes every fixture mutation"):
		_finish(false); return
	var scene := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _check(scene != null, "original TerrainLab PackedScene loads"): _finish(false); return
	lab = scene.instantiate() as TerrainLab
	if not _check(lab != null, "original TerrainLab instantiates"): _finish(false); return
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	await process_frame
	if finished: return
	await process_frame
	if finished: return
	if not _check(lab.terrain != null and lab.site_controller != null and lab.audio_view != null,
		"original ready constructs actual terrain Controller and presenter"):
		_finish(false); return
	var view: SiteAudioView = lab.audio_view
	view.set_process(false)
	if not _check(bool(view.stats_snapshot().active), "original direct Site boot activates presenter"):
		_finish(false); return
	var window: Window = lab.site_controller.formal_windows.get("system")
	if not _check(window != null and window.is_inside_tree(), "original system Window belongs to live SiteUI"):
		_finish(false); return
	lab.site_controller.open_window("system")
	var slider := window.find_child("SFXVolume", true, false) as HSlider
	var mute := window.find_child("SFXMute", true, false) as CheckButton
	if not _check(slider != null and mute != null and slider.editable and not mute.disabled
		and slider == lab.site_controller._audio_volume_slider and mute == lab.site_controller._audio_mute_toggle
		and window.is_ancestor_of(slider) and window.is_ancestor_of(mute),
		"real enabled system controls retain their original connected callbacks"):
		_finish(false); return
	var master := AudioServer.get_bus_index(&"Master")
	var sfx := AudioServer.get_bus_index(&"SFX")
	if not _check(master >= 0 and sfx >= 0, "original Master and SFX buses exist"): _finish(false); return
	var master_db := AudioServer.get_bus_volume_db(master)
	var master_muted := AudioServer.is_bus_mute(master)
	var body_before := lab.character.capture_state()
	var site_before := lab.terrain.site.duplicate(true)
	var clock_before := _clock()
	var speed_before := lab.simulation_speed
	var diagnostics_before: Array = view.stats_snapshot().diagnostics
	if not _check(_create_directory_fixture(), "only the backed-up canonical cfg filename becomes an owned empty directory"):
		_finish(false); return
	# This genuine ConfigFile probe records the platform error; it does not call any audio owner hook.
	var probe := ConfigFile.new()
	probe.set_value("sfx", "volume", 0.19)
	var save_error := probe.save(SiteAudioView.SETTINGS_PATH)
	if not _check(save_error != OK, "real ConfigFile.save refuses the exact original cfg path"):
		_finish(false); return
	var volume_percent := 37.0 if not is_equal_approx(slider.value, 37.0) else 53.0
	var requested_mute := not mute.button_pressed
	slider.value = volume_percent
	mute.button_pressed = requested_mute
	var expected_diagnostic := "Local audio settings were not saved (%d)." % save_error
	var state: Dictionary = view.stats_snapshot()
	if not _check(expected_diagnostic not in diagnostics_before and expected_diagnostic in state.diagnostics
		and is_equal_approx(float(state.volume), volume_percent / 100.0) and bool(state.muted) == requested_mute
		and is_equal_approx(AudioServer.get_bus_volume_db(sfx), linear_to_db(volume_percent / 100.0))
		and AudioServer.is_bus_mute(sfx) == requested_mute,
		"original slider/mute callbacks warn for genuine failed saves while applying SFX"):
		_finish(false); return
	# Continue ordinary unmuted play through the same real callback, with the write rejection still present.
	mute.button_pressed = false
	if not _check(not bool(view.stats_snapshot().muted) and not AudioServer.is_bus_mute(sfx)
		and AudioServer.get_bus_volume_db(master) == master_db and AudioServer.is_bus_mute(master) == master_muted
		and lab.character.capture_state() == body_before and lab.terrain.site == site_before
		and _clock() == clock_before and lab.simulation_speed == speed_before and _fixture_is_empty(),
		"failed cfg writes preserve Master original body Site and clocks before the real step"):
		_finish(false); return
	evidence.merge({"save_failure_error":save_error, "expected_warning":"SiteAudioView: " + expected_diagnostic,
		"diagnostics":view.stats_snapshot().diagnostics, "controls_clock_before":clock_before,
		"controls_clock_after":_clock(), "settings_failure_scope":"real original filename is an owned empty directory"})
	view._process(0.0)
	var step_clock := _clock()
	var step_body := lab.character.capture_state()
	if not _true_step(lab.character, view): _finish(false); return
	var after_step := _clock()
	if not _check(float(after_step.action_seconds) > float(step_clock.action_seconds)
		and float(after_step.game_seconds) > float(step_clock.game_seconds)
		and lab.character.capture_state() != step_body and _fixture_is_empty(),
		"original completed shared movement advances its real action/game clock despite cfg rejection"):
		_finish(false); return
	evidence.merge({"step_clock_before":step_clock, "step_clock_after":after_step,
		"step_body_before":step_body, "step_body_after":lab.character.capture_state()})
	_finish(failures.is_empty())

func _clock() -> Dictionary:
	return {"action_seconds":lab.fire_action_cursor,
		"game_seconds":(float(lab.terrain.site.minute) + float(lab.terrain.site.phase)) * 60.0}

func _create_directory_fixture() -> bool:
	var path := ProjectSettings.globalize_path(SiteAudioView.SETTINGS_PATH)
	if not settings_backup_ready or DirAccess.dir_exists_absolute(path): return false
	if FileAccess.file_exists(SiteAudioView.SETTINGS_PATH):
		if DirAccess.remove_absolute(path) != OK or FileAccess.file_exists(SiteAudioView.SETTINGS_PATH): return false
	if DirAccess.make_dir_absolute(path) != OK: return false
	fixture_directory_created = true
	return _fixture_is_empty()

func _fixture_is_empty() -> bool:
	if not fixture_directory_created: return false
	var directory := DirAccess.open(ProjectSettings.globalize_path(SiteAudioView.SETTINGS_PATH))
	return directory != null and directory.get_files().is_empty() and directory.get_directories().is_empty()

func _backup_settings() -> bool:
	if not settings_existed:
		settings_backup_ready = true
		return true
	var previous := FileAccess.open(SiteAudioView.SETTINGS_PATH, FileAccess.READ)
	if previous == null: return false
	var length := previous.get_length()
	var bytes := previous.get_buffer(length)
	var read_error := previous.get_error()
	previous.close()
	if read_error != OK or bytes.size() != length: return false
	settings_bytes = bytes
	settings_backup_ready = true
	return true

func _restore_settings() -> bool:
	var path := ProjectSettings.globalize_path(SiteAudioView.SETTINGS_PATH)
	if fixture_directory_created:
		if DirAccess.remove_absolute(path) != OK or DirAccess.dir_exists_absolute(path): return false
		fixture_directory_created = false
	if not settings_backup_ready: return true # No fixture mutation occurred after an unavailable backup.
	if DirAccess.dir_exists_absolute(path): return false # Never remove an unowned directory.
	if not settings_existed:
		if not FileAccess.file_exists(SiteAudioView.SETTINGS_PATH): return true
		var removed := DirAccess.remove_absolute(path)
		return removed == OK and not FileAccess.file_exists(SiteAudioView.SETTINGS_PATH)
	var previous := FileAccess.open(SiteAudioView.SETTINGS_PATH, FileAccess.WRITE)
	if previous == null: return false
	previous.store_buffer(settings_bytes)
	previous.flush()
	var write_error := previous.get_error()
	previous.close()
	if write_error != OK: return false
	var restored := FileAccess.open(SiteAudioView.SETTINGS_PATH, FileAccess.READ)
	if restored == null: return false
	var length := restored.get_length()
	var bytes := restored.get_buffer(length)
	var read_error := restored.get_error()
	restored.close()
	return read_error == OK and bytes.size() == length and bytes == settings_bytes

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
