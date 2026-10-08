extends SceneTree
## Run only through the canonical verifier's isolated user directory.
## Functional contracts; no subjective listening, GPU or performance claim.

const AudioView := preload("res://scripts/terrain_lab/site_audio_view.gd")
const OUTPUT := "res://output/audio_implementation_20261008/site_audio_contract_result.json"
const SETTINGS := "user://audio_settings.cfg"

class MockActor extends RefCounted:
	var knockout_left: float = 0.0

class MockController extends RefCounted:
	var fault: bool = false
	var pending: bool = false
	var crossing: bool = false
	func original_step_fault_guard() -> Dictionary:
		return {"ok": not fault}
	func region_operation_pending() -> bool:
		return pending
	func ground_crossing_blocks_clock() -> bool:
		return crossing

class MockLab extends Node2D:
	var terrain: TerrainData
	var site_controller: RefCounted = null
	var restore_only: bool = false
	var identity: int = 1
	var targets: Dictionary = {}
	func controlled_person_id() -> int:
		return identity
	func _combat_target_in_site(id: int) -> Dictionary:
		return targets.get(id, {})

var lab: MockLab
var view: SiteAudioView
var checks: int = 0
var failed: bool = false
var finished: bool = false
var evidence: Array[Dictionary] = []
var saved_settings: PackedByteArray = PackedByteArray()
var had_settings: bool = false
var made_bus: bool = false
var original_bus_volume: float = 0.0
var original_bus_muted: bool = false
var deadline: int = 0
var sequence: int = 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 20000
	create_timer(20.0, true, false, true).timeout.connect(func() -> void: _finish(false, "20-second deadline"))
	_run.call_deferred()

func _check(value: bool, label: String, detail: Variant = null) -> bool:
	checks += 1
	if Time.get_ticks_msec() > deadline:
		value = false
	if not value:
		failed = true
		evidence.append({"failure": label, "detail": str(detail)})
		push_error("SITE_AUDIO_CONTRACT_FAIL: " + label + " " + str(detail))
	return value

func _finish(ok: bool, reason: String = "") -> void:
	if finished:
		return
	finished = true
	paused = false
	if is_instance_valid(view):
		view.set_active(false)
	if had_settings:
		var restored: FileAccess = FileAccess.open(SETTINGS, FileAccess.WRITE)
		if restored != null:
			restored.store_buffer(saved_settings)
			restored.close()
		else:
			ok = false
			evidence.append({"failure": "restore isolated pre-existing settings"})
	else:
		if FileAccess.file_exists(SETTINGS):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS))
	var bus: int = AudioServer.get_bus_index(&"SFX")
	if bus < 0:
		bus = AudioServer.get_bus_index(&"AudioContractHiddenSFX")
		if bus >= 0:
			AudioServer.set_bus_name(bus, &"SFX")
	if bus >= 0:
		if made_bus:
			AudioServer.remove_bus(bus)
		else:
			AudioServer.set_bus_volume_db(bus, original_bus_volume)
			AudioServer.set_bus_mute(bus, original_bus_muted)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var result: FileAccess = FileAccess.open(OUTPUT, FileAccess.WRITE)
	if result == null:
		ok = false
	else:
		result.store_string(JSON.stringify({"ok": ok, "checks": checks, "reason": reason, "evidence": evidence,
			"scope": "SiteAudioView player-local radius, lifecycle, batches, bounded pools, real catalog, ConfigFile, L/T and original fire-source classification; subjective/GPU/performance NOT_RUN"}, "\t"))
		result.close()
	print("SITE_AUDIO_CONTRACT_", "PASS" if ok else "FAIL", " checks=", checks, " ", reason)
	quit(0 if ok else 1)

func _key(label: String) -> String:
	sequence += 1
	return label + ":" + str(sequence)

func _offer(kind: StringName, ground: Vector2, event_key: String, person_id: int = 0, duration: float = 0.0, mounted: bool = false) -> bool:
	view.begin_batch()
	var accepted: bool = view.offer(kind, ground, event_key, person_id, duration, mounted)
	view.commit_batch()
	return accepted

func _players(short: bool = true) -> Array[AudioStreamPlayer2D]:
	var result: Array[AudioStreamPlayer2D] = []
	for child: Node in view.get_children():
		if child is AudioStreamPlayer2D and str(child.name).begins_with("Short" if short else "Loop"):
			var player: AudioStreamPlayer2D = child as AudioStreamPlayer2D
			if player.playing:
				result.append(player)
	return result

func _ground() -> Vector2:
	return Vector2(lab.targets[lab.identity].position)

func _tick() -> void:
	# A deterministic same-frame engine callback, with normal processing disabled.
	view._process(0.0)

func _reset_audio() -> void:
	view.invalidate_epoch()
	_tick()

func _empty(label: String) -> void:
	var stats: Dictionary = view.stats_snapshot()
	_check(int(stats.short_count) == 0 and int(stats.loop_count) == 0 and int(stats.candidate_count) == 0, label, stats)

func _seed_audio() -> void:
	_reset_audio()
	_offer(&"contact", _ground(), _key("seed"))
	view.set_loops([{"key": _key("fire"), "kind": &"fire_small", "position": _ground()}])
	_tick()
	_offer(&"contact", _ground(), _key("queued"))
	_check(int(view.stats_snapshot().short_count) > 0 and int(view.stats_snapshot().loop_count) == 1, "fixture creates actual short and loop players")

func _data(size: Vector2i = Vector2i(96, 96)) -> TerrainData:
	var data: TerrainData = TerrainData.new()
	data.allocate(size)
	data.spawn_cell = Vector2i(3, 3)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "audio-contract")
	data.resource_base.clear()
	data.site.changes.clear()
	data.height_levels.fill(0)
	data.water_kind.fill(0)
	data.water_body.fill(-1)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.foundation.fill(80)
	data.moisture.fill(0)
	data.groundwater.fill(80)
	for item: String in SiteEnvironment.ITEM_NAMES:
		data.site.inventory[item] = 1000
	data.site.capacity = 100000
	_check(SiteRuntime.initialize_item_storage(data.site).ok, "fixture keeps original item registry")
	SiteEnvironment.rebuild_indexes(data)
	return data

func _write_settings(volume: Variant, muted: Variant) -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("sfx", "volume", volume)
	config.set_value("sfx", "muted", muted)
	_check(config.save(SETTINGS) == OK, "isolated canonical user settings fixture saves")

func _test_catalog() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AudioView.CATALOG_PATH))
	var sounds: Dictionary = catalog.get("sounds", {})
	var unique: Dictionary = {}
	var step_paths: Dictionary = {}
	var banks: Dictionary = {}
	for kind: String in sounds:
		var sound: Dictionary = sounds[kind]
		for entry: Dictionary in sound.variants:
			var path: String = str(entry.path)
			unique[path] = true
			var stream: AudioStream = ResourceLoader.load(path) as AudioStream
			if not _check(stream is AudioStreamWAV, "catalog resolves native WAV", path):
				continue
			var wav: AudioStreamWAV = stream as AudioStreamWAV
			_check(wav.mix_rate == 44100 and not wav.stereo and wav.format == AudioStreamWAV.FORMAT_16_BITS, "mono 44100 PCM16 import", path)
			_check(float(entry.duration) > 0.0 and absf(float(entry.duration) - wav.get_length()) <= 1.0 / 44100.0, "catalog L is real decoded duration", path)
			if kind.begins_with("step_"):
				step_paths[path] = true
				banks[str(entry.surface) + ":" + str(entry.locomotion) + ":" + str(entry.tempo)] = true
				_check(int(entry.footsteps) == 2, "each completed-cell segment has two beats", path)
	_check(unique.size() == 42 and step_paths.size() == 24 and banks.size() == 16, "36 baseline plus 6 additional / 24 footsteps / 16 banks", [unique.size(), step_paths.size(), banks.size()])
	_check(int(catalog.baseline_files) == 36 and int(catalog.additional_p1_files) == 6, "catalog preserves baseline counts")

func _test_ranges() -> void:
	var center: Vector2 = _ground()
	_check(_offer(&"contact", center + Vector2(639.99, 0), _key("inside20")), "strictly inside 20m accepted")
	_check(not _offer(&"contact", center + Vector2(640, 0), _key("edge20")), "20m hard boundary rejected")
	_check(_offer(&"contact", center + Vector2(383.9, 511.9), _key("diagonal_inside")), "Euclidean diagonal inside accepted")
	_check(not _offer(&"contact", center + Vector2(384, 512), _key("diagonal_edge")), "Euclidean diagonal 20m boundary rejected")
	_check(not _offer(&"contact", center + Vector2(384.1, 512.1), _key("diagonal_outside")), "diagonal outside rejected")
	_check(_offer(&"fire_large", center + Vector2(1919.99, 0), _key("inside60")), "designated loud source strictly inside60 accepted")
	_check(not _offer(&"fire_large", center + Vector2(1920, 0), _key("edge60")), "60m hard boundary rejected")
	_check(not _offer(&"fire_large", center + Vector2(1152, 1536), _key("diagonal60")), "large Euclidean diagonal boundary rejected")
	_check(not _offer(&"contact", Vector2(NAN, 0), _key("nan")), "non-finite source rejected")
	_reset_audio()
	var camera: Camera2D = Camera2D.new()
	lab.add_child(camera)
	camera.make_current()
	camera.position = center + Vector2(3000, -2000)
	camera.zoom = Vector2(8, 8)
	_check(_offer(&"contact", center + Vector2(639, 0), _key("camera_inside")), "camera pan/zoom does not move distance origin")
	_check(not _offer(&"contact", center + Vector2(640, 0), _key("camera_edge")), "camera pan/zoom cannot extend 20m radius")
	_tick()
	_check(view.stats_snapshot().listener_ground == center, "listener uses controlled original ground")
	for child: Node in view.get_children():
		if child is AudioStreamPlayer2D:
			_check(float(child.panning_strength) == 0.0 and str(child.bus) == "SFX", "P0/P1 mono playback remains on SFX")
	camera.queue_free()
	_reset_audio()

func _test_batches_and_pools() -> void:
	var played: int = int(view.stats_snapshot().played)
	_check(not view.offer(&"contact", _ground(), _key("no_batch")), "short sound requires the original result batch")
	view.begin_batch()
	view.offer(&"contact", _ground(), _key("discard"))
	view.discard_batch()
	_tick()
	_check(int(view.stats_snapshot().played) == played, "discarded original result never plays")
	view.begin_batch()
	var committed_key: String = _key("commit")
	view.offer(&"contact", _ground(), committed_key)
	view.commit_batch()
	_tick()
	_check(int(view.stats_snapshot().played) == played + 1, "committed original result plays once")
	_check(not _offer(&"contact", _ground(), committed_key), "played event deduplicated")
	_reset_audio()
	played = int(view.stats_snapshot().played)
	view.begin_batch()
	view.offer(&"contact", _ground(), _key("uncommitted"))
	_tick()
	_check(int(view.stats_snapshot().played) == played, "uncommitted batch cannot play")
	view.begin_batch()
	view.offer(&"contact", _ground(), _key("old_epoch_batch"))
	view.invalidate_epoch()
	view.commit_batch()
	_tick()
	_check(int(view.stats_snapshot().played) == played, "epoch-invalidated batch cannot commit old events")
	_reset_audio()
	for index: int in 64:
		_offer(&"contact", _ground() + Vector2(600 - index, 0), _key("far"))
	_check(int(view.stats_snapshot().candidate_count) == 64, "candidate pool reaches bounded64")
	_check(_offer(&"contact", _ground() + Vector2(5, 0), _key("nearest")), "same-priority later nearest replaces worse full-pool entry")
	_check(int(view.stats_snapshot().candidate_count) == 64, "candidate replacement stays64")
	_tick()
	_check(int(view.stats_snapshot().short_count) == 8, "contact group quota remains8 under candidate overflow")
	var nearest_played: bool = false
	for player: AudioStreamPlayer2D in _players():
		if lab.to_local(player.global_position).distance_to(_ground() + Vector2(5, 0)) < 0.01:
			nearest_played = true
	_check(nearest_played, "full-pool nearest retained through actual playback")
	_reset_audio()
	for identity: int in range(2, 8):
		_offer(&"step_grass_walk", _ground(), _key("step_limit"), identity, 0.38)
	for index: int in 8:
		_offer(&"contact", _ground(), _key("contact_limit"))
	for index: int in 6:
		_offer(&"bow", _ground(), _key("projectile_limit"))
	var loops: Array[Dictionary] = []
	for index: int in 7:
		loops.append({"key": _key("loop_limit"), "kind": &"fire_small", "position": _ground() + Vector2(index * 10, 0)})
	view.set_loops(loops)
	_tick()
	var stats: Dictionary = view.stats_snapshot()
	_check(int(stats.short_count) == 20 and int(stats.loop_count) == 4, "20 actual short +4 actual native loop shared caps", stats)
	for player: AudioStreamPlayer2D in _players(false):
		var real_loop: AudioStreamWAV = player.stream as AudioStreamWAV
		if not _check(real_loop != null, "actual native loop uses WAV stream"):
			continue
		var pcm_bytes: int = real_loop.data.size()
		var pcm_frames: int = int(pcm_bytes / 2.0)
		_check(real_loop.format == AudioStreamWAV.FORMAT_16_BITS and not real_loop.stereo and pcm_bytes >= 2,
			"actual native loop keeps mono PCM16 data", {"format": real_loop.format, "stereo": real_loop.stereo, "bytes": pcm_bytes})
		_check(real_loop.loop_mode == AudioStreamWAV.LOOP_FORWARD and real_loop.loop_begin == 0 and real_loop.loop_end == pcm_frames - 1,
			"native forward loop ends at the inclusive final PCM frame", {"frames": pcm_frames, "begin": real_loop.loop_begin, "end": real_loop.loop_end})
	_offer(&"contact", _ground(), _key("extra_short"))
	_tick()
	stats = view.stats_snapshot()
	_check(int(stats.short_count) <= 20 and int(stats.loop_count) <= 4 and int(stats.peak_short) <= 20 and int(stats.peak_loop) <= 4, "overflow preserves hard playback caps", stats)
	_reset_audio()

func _test_steps() -> void:
	var played: int = int(view.stats_snapshot().played)
	_offer(&"step_grass_walk", _ground(), _key("old_step"), 2, 0.38)
	_offer(&"step_grass_walk", _ground() + Vector2(640, 0), _key("latest_outside"), 2, 0.38)
	_tick()
	_check(int(view.stats_snapshot().played) == played, "newest same-id step outside cancels older in-range candidate")
	_check(not _offer(&"step_grass_walk", _ground(), _key("zero_T"), 2, 0.0), "zero original duration rejected")
	_check(not _offer(&"step_grass_walk", _ground(), _key("nan_T"), 2, NAN), "non-finite original duration rejected")
	for case: Dictionary in [{"kind": &"step_grass_walk", "T": 0.02, "pitch": 1.25}, {"kind": &"step_grass_walk", "T": 5.0, "pitch": 0.8}, {"kind": &"step_grass_walk", "T": 0.5, "pitch": 1.0}, {"kind": &"step_grass_run", "T": 0.26, "pitch": 1.0}, {"kind": &"hoof_run", "T": 0.02, "pitch": 1.25}]:
		_reset_audio()
		_offer(case.kind, _ground(), _key("pitch"), 2, float(case.T), case.kind == &"hoof_run")
		_tick()
		var players: Array[AudioStreamPlayer2D] = _players()
		if _check(players.size() == 1, "one same-person tail", case):
			var player: AudioStreamPlayer2D = players[0]
			_check(absf(player.pitch_scale - float(case.pitch)) < 0.00001, "real L/T chooses bank and clamps 0.8..1.25 including mounted", case)
	_reset_audio()
	_offer(&"step_grass_walk", _ground(), _key("old_inside"), 2, 0.38)
	_offer(&"step_grass_walk", _ground() + Vector2(12, 0), _key("latest_inside"), 2, 0.38)
	_tick()
	_check(_players().size() == 1 and lab.to_local(_players()[0].global_position).distance_to(_ground() + Vector2(12, 0)) < 0.01, "same-frame latest successful step converges to one tail")
	var actor: MockActor = lab.targets[2].owner as MockActor
	actor.knockout_left = 2.0
	_tick()
	_empty("ongoing step tail stops at original source KO")
	actor.knockout_left = 0.0
	actor = lab.targets[lab.identity].owner as MockActor
	actor.knockout_left = 2.0
	_check(not _offer(&"step_grass_walk", _ground(), _key("player_KO_step"), lab.identity, 0.38), "KO player cannot emit steps")
	_check(_offer(&"hurt", _ground(), _key("player_KO_hurt"), lab.identity), "living KO player still hears original hurt feedback")
	_tick()
	_check(int(view.stats_snapshot().short_count) == 1, "KO is not a global audio mute")
	actor.knockout_left = 0.0
	_reset_audio()

func _test_loops_and_lifecycle() -> void:
	view.set_loops([{"key": "small_hysteresis", "kind": &"fire_small", "position": _ground() + Vector2(576, 0)}])
	_tick()
	_check(int(view.stats_snapshot().loop_count) == 0, "small loop does not create at18m")
	view.set_loops([{"key": "small_hysteresis", "kind": &"fire_small", "position": _ground() + Vector2(575, 0)}])
	_tick()
	_check(int(view.stats_snapshot().loop_count) == 1, "small loop creates inside18m")
	view.set_loops([{"key": "small_hysteresis", "kind": &"fire_small", "position": _ground() + Vector2(639, 0)}])
	_tick()
	_check(int(view.stats_snapshot().loop_count) == 1, "existing small loop survives hysteresis band")
	view.set_loops([{"key": "small_hysteresis", "kind": &"fire_small", "position": _ground() + Vector2(640, 0)}])
	_tick()
	_empty("small loop stops exactly20m")
	view.set_loops([{"key": "large_hysteresis", "kind": &"fire_large", "position": _ground() + Vector2(1759, 0)}])
	_tick()
	_check(int(view.stats_snapshot().loop_count) == 1, "large loop creates inside55m")
	view.set_loops([{"key": "large_hysteresis", "kind": &"fire_large", "position": _ground() + Vector2(1920, 0)}])
	_tick()
	_empty("large loop stops exactly60m")
	_seed_audio()
	lab.terrain.site.paused = true
	_tick()
	_empty("original Site pause clears current and pending audio")
	lab.terrain.site.paused = false
	_seed_audio()
	paused = true
	_tick()
	_empty("SceneTree pause clears current and pending audio")
	paused = false
	_seed_audio()
	var other: Node2D = Node2D.new()
	root.add_child(other)
	current_scene = other
	_tick()
	_empty("scene departure clears audio")
	current_scene = lab
	other.queue_free()
	_seed_audio()
	lab.restore_only = true
	_tick()
	_empty("restore-only cold gate clears audio")
	lab.restore_only = false
	_seed_audio()
	var epoch: int = int(view.stats_snapshot().epoch)
	lab.identity = 2
	_tick()
	_empty("controlled-person takeover clears previous generation")
	_check(int(view.stats_snapshot().epoch) > epoch, "takeover advances presenter epoch")
	lab.identity = 1
	_tick()
	_seed_audio()
	view.invalidate_epoch()
	_empty("explicit location/restore epoch invalidation clears every pool")
	_check(int(view.stats_snapshot().dedup_count) == 0 and not bool(view.stats_snapshot().batch_open), "epoch invalidation removes dedup and open batch")
	_seed_audio()
	lab.targets[1].hp = 0.0
	_tick()
	_empty("invalid/dead controlled target clears audio")
	lab.targets[1].hp = 100.0
	var controller: MockController = MockController.new()
	lab.site_controller = controller
	_seed_audio()
	controller.fault = true
	_tick()
	_empty("original shared-step fault guard clears audio")
	controller.fault = false
	_seed_audio()
	controller.pending = true
	_tick()
	_empty("original region transaction gate clears audio")
	controller.pending = false
	_seed_audio()
	controller.crossing = true
	_tick()
	_empty("original boundary crossing gate clears audio")
	lab.site_controller = null
	_reset_audio()

func _test_mute_and_settings() -> void:
	_seed_audio()
	_check(view.set_muted(true, false), "mute accepted by active settings owner")
	_empty("mute stops tails, loops and pending events")
	var played: int = int(view.stats_snapshot().played)
	_check(not _offer(&"contact", _ground(), _key("muted_event")), "muted event dropped")
	view.set_muted(false, false)
	_tick()
	_check(int(view.stats_snapshot().played) == played, "unmute cannot replay dropped events")
	_seed_audio()
	view.set_volume(0.0, false)
	_empty("zero SFX volume stops tails, loops and pending events")
	_check(not _offer(&"contact", _ground(), _key("zero_event")), "zero volume event dropped")
	played = int(view.stats_snapshot().played)
	view.set_volume(0.8, false)
	_tick()
	_check(int(view.stats_snapshot().played) == played, "restoring volume cannot replay dropped events")
	view.set_active(false)
	_write_settings("invalid", "invalid")
	_check(view.set_active(true), "active original presenter reloads settings")
	_check(float(view.stats_snapshot().volume) == 0.8 and not bool(view.stats_snapshot().muted), "illegal saved values use defaults")
	view.set_active(false)
	_write_settings(2.0, false)
	view.set_active(true)
	_check(float(view.stats_snapshot().volume) == 1.0, "saved high volume clamps1")
	view.set_active(false)
	_write_settings(-2.0, false)
	view.set_active(true)
	_check(float(view.stats_snapshot().volume) == 0.0, "saved negative volume clamps0")
	_check(not view.set_volume(NAN) and not view.set_volume(INF), "non-finite user volume rejected")
	view.set_volume(0.42, true)
	view.set_muted(true, true)
	var config: ConfigFile = ConfigFile.new()
	_check(config.load(SETTINGS) == OK and float(config.get_value("sfx", "volume")) == 0.42 and config.get_value("sfx", "muted") == true, "UI settings save only original ConfigFile path")
	view.set_active(false)
	view.set_active(true)
	_check(float(view.stats_snapshot().volume) == 0.42 and bool(view.stats_snapshot().muted), "saved volume/mute survive active presenter reload")
	view.set_muted(false, false)
	view.set_volume(0.8, false)
	_reset_audio()
	var sfx: int = AudioServer.get_bus_index(&"SFX")
	var master: int = AudioServer.get_bus_index(&"Master")
	var master_volume: float = AudioServer.get_bus_volume_db(master)
	var master_muted: bool = AudioServer.is_bus_mute(master)
	view.set_active(false)
	AudioServer.set_bus_name(sfx, &"AudioContractHiddenSFX")
	_check(not view.set_active(true), "missing SFX disables world presenter")
	_check(not _offer(&"contact", _ground(), _key("missing_bus")), "missing SFX cannot fall back to playback")
	_tick()
	_empty("missing SFX leaves all players stopped")
	_check(AudioServer.get_bus_volume_db(master) == master_volume and AudioServer.is_bus_mute(master) == master_muted, "missing SFX does not alter Master")
	AudioServer.set_bus_name(sfx, &"SFX")
	view.set_active(true)
	view.set_volume(0.8, false)
	view.set_muted(false, false)
	_reset_audio()

func _timber(data: TerrainData, cell: Vector2i) -> String:
	SiteEnvironment._add_resource(data, SiteEnvironment.Kind.TIMBER, data.index(cell), 256, 0)
	SiteEnvironment.rebuild_indexes(data)
	var key: String = "%d:%d" % [SiteEnvironment.Kind.TIMBER, data.index(cell)]
	var state: Dictionary = SiteRuntime._fire_state(data, 0.0)
	var descriptor: Dictionary = SiteRuntime._fire_resource_descriptor(data, key)
	var unit: Dictionary = SiteRuntime._fire_unit(data, state, descriptor)
	unit.merge({"heat": 100.0, "state": "BURNING", "intensity": 1.0, "moisture": 0.0}, true)
	state.active[str(descriptor.key)] = true
	SiteRuntime.fire_hazard_invalidate(data)
	return str(descriptor.key)

func _classify(data: TerrainData, seed: String, unit_budget: int = 64) -> Dictionary:
	return view._audio_fire_group_classification(data, data.site.fire.units, seed, {"units": unit_budget, "cells": 1024, "edges": 512})

func _meta_bytes(data: TerrainData) -> PackedByteArray:
	var metadata: Dictionary = {}
	for key: StringName in data.get_meta_list():
		metadata[str(key)] = data.get_meta(key)
	return var_to_bytes(metadata)

func _test_fire_cache(data: TerrainData, listener: Vector2) -> void:
	for reason: String in ["missing", "step", "environment", "navigation", "state_identity"]:
		# Original fixture owner publishes; the audio view may only borrow it.
		SiteRuntime.fire_hazard_snapshot(data)
		match reason:
			"missing":
				SiteRuntime.fire_hazard_invalidate(data)
			"step":
				data.site.fire.step_index = int(data.site.fire.step_index) + 1
			"environment":
				data.environment_revision += 1
			"navigation":
				data.navigation_revision += 1
			"state_identity":
				data.site.fire = data.site.fire.duplicate(true)
		var original_meta: PackedByteArray = _meta_bytes(data)
		var original_state: PackedByteArray = var_to_bytes(data.site.fire)
		var rows: Array[Dictionary] = view._audio_fire_loops(data, listener)
		_check(rows.is_empty(), "missing/stale original fire cache stays silent: " + reason)
		_check(_meta_bytes(data) == original_meta and var_to_bytes(data.site.fire) == original_state,
			"audio never rebuilds cache or writes original metadata/units: " + reason)
	SiteRuntime.fire_hazard_snapshot(data)

func _test_fire_hysteresis() -> void:
	var data: TerrainData = _data()
	# sqrt(9^2+3^2)*2m = 18.974m; the nearest large-group seed is 50m.
	_timber(data, Vector2i(29, 23))
	for x: int in range(45, 49):
		_timber(data, Vector2i(x, 20))
	SiteRuntime.fire_hazard_snapshot(data)
	var listener: Vector2 = (Vector2(20, 20) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	var original_terrain: TerrainData = lab.terrain
	var original_ground: Vector2 = _ground()
	lab.terrain = data
	lab.targets[lab.identity].position = listener
	_reset_audio()
	var rows: Array[Dictionary] = view._audio_fire_loops(data, listener)
	_check(rows.size() == 1 and rows[0].kind == &"fire_large", "uncreated near19m small fire cannot mask a new50m large fire")
	_check(int(view.stats_snapshot().loop_count) == 1, "eligible large fire actually creates one native loop")
	view.invalidate_epoch()
	lab.targets[lab.identity].position = listener + Vector2(64, 0)
	_tick()
	rows = view._audio_fire_loops(data, _ground())
	_check(rows.size() == 1 and rows[0].kind == &"fire_small" and int(view.stats_snapshot().loop_count) == 1, "inside18m original small fire actually creates")
	lab.targets[lab.identity].position = listener
	_tick()
	rows = view._audio_fire_loops(data, listener)
	_check(rows.size() == 1 and rows[0].kind == &"fire_small" and int(view.stats_snapshot().loop_count) == 1, "same existing small-fire identity remains audible near19m within20m stop radius")
	lab.terrain = original_terrain
	lab.targets[lab.identity].position = original_ground
	_reset_audio()

func _test_fire_sources() -> void:
	var data: TerrainData = _data()
	var seed: String = _timber(data, Vector2i(17, 10))
	_timber(data, Vector2i(18, 10))
	_timber(data, Vector2i(19, 10))
	var classification: Dictionary = _classify(data, seed)
	_check(bool(classification.known) and not bool(classification.large), "three connected unique BURNING ground cells remain small")
	var snapshot: Dictionary = SiteRuntime.fire_hazard_snapshot(data)
	var index: int = data.index(Vector2i(17, 10))
	var entry: Dictionary = snapshot.cells[index][0].duplicate(true)
	for number: int in 4:
		snapshot.cells[index].append(entry.duplicate(true))
	classification = _classify(data, seed)
	_check(bool(classification.known) and not bool(classification.large), "duplicate hazard entries cannot manufacture four unique cells")
	_timber(data, Vector2i(20, 10))
	var source_before: PackedByteArray = var_to_bytes(data.site.fire.units)
	classification = _classify(data, seed)
	_check(bool(classification.known) and bool(classification.large), "four connected unique BURNING ground cells classify large")
	var listener: Vector2 = (Vector2(10, 10) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS - Vector2(16, 0)
	SiteRuntime.fire_hazard_snapshot(data) # Original owner publishes after the fourth source invalidated its cache.
	var rows: Array[Dictionary] = view._audio_fire_loops(data, listener)
	_check(rows.size() == 1 and rows[0].kind == &"fire_large", "fourth connected cell outside20m still promotes entire original group")
	_check(var_to_bytes(data.site.fire.units) == source_before, "fire projection never changes authoritative unit state")
	_check(not bool(_classify(data, seed, 0).known), "bounded incomplete fire query reports unknown")
	_test_fire_cache(data, listener)
	for unit: Dictionary in data.site.fire.units.values():
		unit.state = "EMBERS"
	SiteRuntime.fire_hazard_invalidate(data)
	classification = _classify(data, seed)
	_check(bool(classification.known) and not bool(classification.large), "EMBER cells connect without counting as burning cells")
	data = _data()
	var options: Dictionary = {"owner_faction": 1}
	var layout: Dictionary = SiteRuntime.building_cells(data, "palisade", Vector2i(20, 20), Vector2i.ONE, options)
	if not _check(bool(layout.ok), "original paid palisade layout"):
		return
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var built: Dictionary = SiteRuntime.request_build(data, "palisade", cells, Callable(), options)
	if not _check(bool(built.ok), "original paid palisade material debit"):
		return
	var feature_id: String = str(built.feature)
	var feature: Dictionary = data.site.features[feature_id]
	var work: Dictionary = {"version": 2, "zone": -1, "target": "feature:" + feature_id, "action": "construct", "work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	SiteRuntime._feature_work(data, feature_id, float(feature.work), Callable(), Callable(), work, {}, 20, 1)
	if not _check(str(feature.stage) == "complete", "original construction completes palisade"):
		return
	var part: String = "c:" + str(data.index(Vector2i(20, 20)))
	var descriptor: Dictionary = SiteRuntime._fire_feature_descriptor(data, feature_id, part)
	if not _check(not descriptor.is_empty(), "original combustible part descriptor exists"):
		return
	var state: Dictionary = SiteRuntime._fire_state(data, 0.0)
	var unit: Dictionary = SiteRuntime._fire_unit(data, state, descriptor)
	unit.merge({"heat": 100.0, "state": "BURNING", "intensity": 1.0}, true)
	seed = str(descriptor.key)
	state.active[seed] = true
	classification = _classify(data, seed)
	_check(bool(classification.known) and bool(classification.large), "live original BURNING building part is large")
	unit.state = "EMBERS"
	classification = _classify(data, seed)
	_check(bool(classification.known) and not bool(classification.large), "live EMBER building part does not auto-promote")
	unit.state = "BURNING"
	feature.parts[part].hp = 0.0
	SiteRuntime._fire_collapse_state(state)
	SiteRuntime._fire_commit_collapse(data, state, feature_id, part)
	classification = _classify(data, seed)
	_check(int(unit.debris_version) == SiteRuntime.FIRE_COLLAPSE_VERSION and bool(classification.known) and not bool(classification.large), "one-cell original collapsed debris is not a live large building")
	view.set_loops([{"key": "old_fire", "kind": &"fire_small", "position": _ground()}])
	_tick()
	var empty_data: TerrainData = _data()
	SiteRuntime.fire_hazard_snapshot(empty_data)
	rows = view._audio_fire_loops(empty_data, Vector2(640, 640))
	view.set_loops(rows)
	_tick()
	_check(rows.is_empty() and int(view.stats_snapshot().loop_count) == 0, "absent current fire projection stops old loop")

func _run() -> void:
	had_settings = FileAccess.file_exists(SETTINGS)
	if had_settings:
		saved_settings = FileAccess.get_file_as_bytes(SETTINGS)
	var sfx: int = AudioServer.get_bus_index(&"SFX")
	_check(sfx >= 0, "formal default bus layout loaded SFX")
	if sfx < 0:
		AudioServer.add_bus()
		sfx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(sfx, &"SFX")
		made_bus = true
	original_bus_volume = AudioServer.get_bus_volume_db(sfx)
	original_bus_muted = AudioServer.is_bus_mute(sfx)
	_write_settings(0.37, true)
	lab = MockLab.new()
	lab.terrain = _data(Vector2i(128, 128))
	lab.position = Vector2(120, -70)
	for identity: int in range(1, 101):
		lab.targets[identity] = {"owner": MockActor.new(), "unit": -1, "position": Vector2(4096, 4096), "hp": 100.0}
	root.add_child(lab)
	current_scene = lab
	view = AudioView.new()
	lab.add_child(view)
	view.setup(lab)
	view.set_process(false)
	_check(not bool(view.stats_snapshot().active) and float(view.stats_snapshot().volume) == 0.8, "inactive setup does not read saved global settings")
	_check(AudioServer.get_bus_volume_db(sfx) == original_bus_volume and AudioServer.is_bus_mute(sfx) == original_bus_muted, "inactive setup does not apply global SFX settings")
	_check(not view.set_volume(0.2) and not view.set_muted(false), "inactive presenter cannot own settings")
	lab.restore_only = true
	_check(not view.set_active(true), "cold restore-only placeholder cannot activate audio")
	_check(AudioServer.get_bus_volume_db(sfx) == original_bus_volume and AudioServer.is_bus_mute(sfx) == original_bus_muted, "cold placeholder leaves global SFX settings unchanged")
	lab.restore_only = false
	_check(view.set_active(true) and float(view.stats_snapshot().volume) == 0.37 and bool(view.stats_snapshot().muted), "original active scene loads its fixed ConfigFile settings")
	view.set_muted(false, false)
	view.set_volume(0.8, false)
	_tick()
	_test_catalog()
	_test_ranges()
	_test_batches_and_pools()
	_reset_audio()
	var played: int = int(view.stats_snapshot().played)
	var offered_frame: int = Engine.get_process_frames()
	_offer(&"contact", _ground(), _key("past_frame"))
	# A deferred runner may begin before this iteration's process_frame signal.
	# Two signals guarantee the native process counter has crossed an iteration.
	await process_frame
	await process_frame
	var resumed_frame: int = Engine.get_process_frames()
	var frame_evidence: Dictionary = {"offered": offered_frame, "resumed": resumed_frame}
	_check(resumed_frame > offered_frame, "past-frame fixture advances the actual engine counter", frame_evidence)
	_tick()
	_check(int(view.stats_snapshot().played) == played, "past-frame candidate is discarded instead of replayed", frame_evidence)
	_test_steps()
	_test_loops_and_lifecycle()
	_test_mute_and_settings()
	_test_fire_sources()
	_test_fire_hysteresis()
	_finish(not failed)
