extends SceneTree
## Independent process, explicit fixture carry; real Site/Controller and restore-only builder.
## Does not prove ordinary OS userdata path continuity or physical audio device output.

const RESULT := "user://audio_settings_restart_cold_result.json"
const SEED_ROOT := "res://output/audio_implementation_20261008/settings_restart_candidates_v2/runtime"
const SEED_PATH := SEED_ROOT + "/settings_seed.cfg"
const SEED_META := SEED_ROOT + "/settings_seed_completed.json"
const EXPECTED_SEED_SOURCE := "28725b5f4070b4a90c72923c255f929d8c2791417d99edd1bec4bed6bb6fb375"
var lab: TerrainLab
var cold: TerrainLab
var checks := 0
var failures: Array[String] = []
var finished := false
var settings_existed := false
var settings_bytes := PackedByteArray()
var settings_backup_ready := false
var seed_process_id := 0
var seed_sha := ""

func _initialize() -> void:
	create_timer(45.0, true, false, true).timeout.connect(func() -> void: _finish(false, "45-second restart/cold deadline"))
	_run.call_deferred()

func _check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures.append(label)
		push_error("AUDIO_SETTINGS_RESTART_COLD_FAIL: " + label)
	return value

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	paused = false
	if is_instance_valid(cold): cold.free()
	if is_instance_valid(lab):
		lab.set_process(false)
		lab.free()
	# A failed backup exits before any cfg write; leave that unreadable original untouched.
	if settings_backup_ready and not _check(_restore_settings(), "original settings cleanup restores exact bytes or confirms successful removal"):
		ok = false
	TerrainArmy.release_contact_source()
	var file := FileAccess.open(RESULT, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok":ok, "checks":checks, "failures":failures, "reason":reason,
			"process_id":OS.get_process_id(), "seed_process_id":seed_process_id, "seed_sha256":seed_sha,
			"phase1_source_sha256":EXPECTED_SEED_SOURCE, "source_sha256":FileAccess.get_sha256(get_script().resource_path),
			"scope":"independent process reads explicit carried ConfigFile bytes; real Site boot/system controls and hidden restore-only builder no-write; excludes ordinary OS userdata continuity, device listening, save failure, Party/Native/GPU/performance/export"}, "\t"))
	print("AUDIO_SETTINGS_RESTART_COLD_", "PASS" if ok else "FAIL", " checks=", checks, " ", reason)
	quit(0 if ok else 1)

func _run() -> void:
	settings_existed = FileAccess.file_exists(SiteAudioView.SETTINGS_PATH)
	if not _check(_backup_settings(), "original settings backup is readable before any test cfg write"):
		_finish(false); return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SEED_META)) if FileAccess.file_exists(SEED_META) else null
	if not _check(parsed is Dictionary and bool(parsed.get("completed", false))
		and str(parsed.get("phase", "")) == "original_site_ui_seed_phase1"
		and str(parsed.get("test_source_sha256", "")) == EXPECTED_SEED_SOURCE
		and str(parsed.get("original_source_sha256", "")) == "c163587556f4480f16cd62da27b75f9c5836f97c58f41ad4aa09eb89b75cbaea",
		"completed seed receipt belongs to the exact original Site seed test"):
		_finish(false); return
	seed_process_id = int(parsed.get("seed_process_id", 0))
	seed_sha = str(parsed.get("seed_sha256", ""))
	if not _check(seed_process_id > 0 and seed_process_id != OS.get_process_id(), "restart uses an independent Godot process"):
		_finish(false); return
	if not _check(not seed_sha.is_empty() and FileAccess.file_exists(SEED_PATH)
		and FileAccess.get_sha256(SEED_PATH) == seed_sha, "exported seed bytes match the completed first-process SHA"):
		_finish(false); return
	var seed_bytes := FileAccess.get_file_as_bytes(SEED_PATH)
	var carry := FileAccess.open(SiteAudioView.SETTINGS_PATH, FileAccess.WRITE)
	if carry == null: _finish(false, "cannot install explicit carried settings fixture"); return
	carry.store_buffer(seed_bytes)
	carry.flush()
	carry.close()
	if not _check(FileAccess.get_file_as_bytes(SiteAudioView.SETTINGS_PATH) == seed_bytes,
		"isolated second run receives byte-identical fixture at the original settings path"):
		_finish(false); return
	var master := AudioServer.get_bus_index(&"Master")
	var sfx := AudioServer.get_bus_index(&"SFX")
	if not _check(master >= 0 and sfx >= 0, "actual Master and unique SFX buses exist"): _finish(false); return
	var master_db := AudioServer.get_bus_volume_db(master)
	var master_mute := AudioServer.is_bus_mute(master)
	var scene := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _check(scene != null, "original TerrainLab PackedScene loads"): _finish(false); return
	lab = scene.instantiate() as TerrainLab
	if not _check(lab != null, "actual original Lab instantiates"): _finish(false); return
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	await process_frame
	await process_frame
	if not _check(lab.terrain != null and lab.site_controller != null and lab.audio_view != null,
		"original boot builds real terrain Controller and presenter"):
		_finish(false); return
	var view: SiteAudioView = lab.audio_view
	view.set_process(false)
	var state: Dictionary = view.stats_snapshot()
	if not _check(bool(state.active) and is_equal_approx(float(state.volume), 0.37) and bool(state.muted),
		"second process original activation loads 37 percent muted settings"):
		_finish(false); return
	var window: Window = lab.site_controller.formal_windows.get("system")
	if not _check(window != null and window.is_inside_tree(), "actual system Window belongs to live SiteUI"):
		_finish(false); return
	lab.site_controller.open_window("system")
	var slider := window.find_child("SFXVolume", true, false) as HSlider
	var mute := window.find_child("SFXMute", true, false) as CheckButton
	if not _check(slider != null and mute != null and slider == lab.site_controller._audio_volume_slider
		and mute == lab.site_controller._audio_mute_toggle and window.is_ancestor_of(slider) and window.is_ancestor_of(mute)
		and slider.editable and not mute.disabled and is_equal_approx(slider.value, 37.0) and mute.button_pressed,
		"original second-process UI displays the actual loaded settings"):
		_finish(false); return
	if not _check(is_equal_approx(AudioServer.get_bus_volume_db(sfx), linear_to_db(0.37)) and AudioServer.is_bus_mute(sfx)
		and AudioServer.get_bus_volume_db(master) == master_db and AudioServer.is_bus_mute(master) == master_mute
		and FileAccess.get_file_as_bytes(SiteAudioView.SETTINGS_PATH) == seed_bytes,
		"real boot applies only SFX and does not rewrite the carried ConfigFile"):
		_finish(false); return
	var body_before: Dictionary = lab.character.capture_state()
	var site_before: Dictionary = lab.terrain.site.duplicate(true)
	var action_before: float = lab.fire_action_cursor
	var speed_before: float = lab.simulation_speed
	var sfx_db := AudioServer.get_bus_volume_db(sfx)
	var sfx_mute := AudioServer.is_bus_mute(sfx)
	lab.site_controller._audio_settings_changed(0.53, false)
	if not _check(is_equal_approx(slider.value, 53.0) and not mute.button_pressed
		and FileAccess.get_file_as_bytes(SiteAudioView.SETTINGS_PATH) == seed_bytes
		and AudioServer.get_bus_volume_db(sfx) == sfx_db and AudioServer.is_bus_mute(sfx) == sfx_mute,
		"original no-signal UI refresh changes controls without writing settings or bus"):
		_finish(false); return
	lab.site_controller._audio_settings_changed(float(state.volume), bool(state.muted))
	cold = scene.instantiate() as TerrainLab
	if not _check(cold != null, "original cold Lab instantiates"): _finish(false); return
	cold.restore_only = true
	root.add_child(cold) # Actual _ready constructs original hidden Controller/UI synchronously.
	var cold_ui := cold.get_node_or_null("SiteUI") as CanvasLayer
	if not _check(cold.is_inside_tree() and not cold.visible and cold.restore_only and cold.audio_view == null
		and cold.site_controller != null and cold_ui != null and not cold_ui.visible and current_scene == lab,
		"real restore-only builder remains hidden and does not create or activate SFX presenter"):
		_finish(false); return
	var cold_window: Window = cold.site_controller.formal_windows.get("system")
	var cold_slider: HSlider = cold.site_controller._audio_volume_slider
	var cold_mute: CheckButton = cold.site_controller._audio_mute_toggle
	if not _check(cold_window != null and not cold_window.visible and cold_slider != null and cold_mute != null
		and cold_window.is_ancestor_of(cold_slider) and cold_window.is_ancestor_of(cold_mute)
		and not cold_slider.editable and cold_mute.disabled,
		"real hidden cold system builder owns disabled original SFX controls"):
		_finish(false); return
	var cold_body_before: Dictionary = cold.character.capture_state()
	var cold_volume_before: float = cold_slider.value / 100.0
	var cold_muted_before: bool = cold_mute.button_pressed
	cold.site_controller._audio_settings_changed(0.37, true)
	cold_slider.value = 91.0 # Fires the real connected callback despite disabled user input.
	cold_mute.button_pressed = false
	cold.site_controller._audio_settings_changed(cold_volume_before, cold_muted_before)
	view._process(0.0)
	if not _check(FileAccess.get_file_as_bytes(SiteAudioView.SETTINGS_PATH) == seed_bytes
		and FileAccess.get_sha256(SEED_PATH) == seed_sha
		and AudioServer.get_bus_volume_db(master) == master_db and AudioServer.is_bus_mute(master) == master_mute
		and AudioServer.get_bus_volume_db(sfx) == sfx_db and AudioServer.is_bus_mute(sfx) == sfx_mute
		and cold.character.capture_state() == cold_body_before and lab.character.capture_state() == body_before
		and lab.terrain.site == site_before and lab.fire_action_cursor == action_before and lab.simulation_speed == speed_before
		and cold.audio_view == null and bool(view.stats_snapshot().active)
		and is_equal_approx(float(view.stats_snapshot().volume), 0.37) and bool(view.stats_snapshot().muted)
		and int(view.stats_snapshot().short_count) == 0 and int(view.stats_snapshot().loop_count) == 0
		and is_equal_approx(slider.value, 37.0) and mute.button_pressed,
		"cold build and original refresh/callbacks preserve raw settings live SFX Master body and original clock"):
		_finish(false); return
	_finish(failures.is_empty())


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
	if not settings_backup_ready: return false
	if not settings_existed:
		if not FileAccess.file_exists(SiteAudioView.SETTINGS_PATH): return true
		var removed := DirAccess.remove_absolute(ProjectSettings.globalize_path(SiteAudioView.SETTINGS_PATH))
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
