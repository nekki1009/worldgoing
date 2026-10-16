class_name SiteAudioView
extends Node2D

signal settings_changed(volume: float, muted: bool)

const SHORT_LIMIT := 20
const LOOP_LIMIT := 4
const CANDIDATE_LIMIT := 64
const GENERAL_RADIUS := 640.0
const LARGE_RADIUS := 1920.0
const GENERAL_LOOP_START := 576.0
const LARGE_LOOP_START := 1760.0
const CELL_PIXELS := 64.0
const CATALOG_PATH := "res://assets/audio/catalog.json"
const SETTINGS_PATH := "user://audio_settings.cfg"
const DEFAULT_VOLUME := 0.8
const DEDUP_LIMIT := 512
const DEDUP_MSEC := 3000
const LARGE_KINDS := [&"structure_collapse", &"siege_release", &"heavy_projectile_contact", &"fire_large"]
const GROUP_LIMITS := {"step": 6, "contact": 8, "projectile": 6, "call": 2}

var _lab: Node2D
var _listener: AudioListener2D
var _short_players: Array[AudioStreamPlayer2D] = []
var _loop_players: Array[AudioStreamPlayer2D] = []
var _short_rows: Array[Dictionary] = []
var _loop_rows: Array[Dictionary] = []
var _candidates: Array[Dictionary] = []
var _loop_requests: Array[Dictionary] = []
var _fire_loop_requests: Array[Dictionary] = []
var _environment_loop_requests: Array[Dictionary] = []
var _last_animal_call_msec: int = -1
const AUDIO_ENV_RESOURCE_READS := 512
const AUDIO_ANIMAL_CALL_MSEC := 15000
var _catalog: Dictionary = {}
var _streams: Dictionary = {}
var _seen: Dictionary = {}
var _diagnostics: Array[String] = []
var _active := false
var _volume := DEFAULT_VOLUME
var _muted := false
var _epoch := 1
var _controlled_id := 0
var _listener_owner_id := 0
var _listener_ground := Vector2.ZERO
var _listener_valid := false
var _candidate_frame := -1
var _batch_serial := 0
var _batch_open := false
var _batch_cancelled := false
var _batch_epoch := 0
var _batch_frame := -1
var _offer_order := 0
var _last_seen_prune := -1
var _last_fire_refresh_msec := -1
var _counts := {"offered": 0, "played": 0, "dropped": 0, "stream_loads": 0,
	"peak_short": 0, "peak_loop": 0}


func setup(lab: Node2D) -> void:
	if is_instance_valid(_listener):
		return
	_lab = lab
	process_mode = Node.PROCESS_MODE_ALWAYS
	_listener = AudioListener2D.new()
	_listener.name = "GroundListener"
	add_child(_listener)
	for index in SHORT_LIMIT:
		_short_players.append(_new_player("Short%02d" % index))
		_short_rows.append({})
	for index in LOOP_LIMIT:
		_loop_players.append(_new_player("Loop%02d" % index))
		_loop_rows.append({})
	_load_catalog()


func set_active(value: bool) -> bool:
	if not value:
		_active = false
		invalidate_epoch()
		return true
	if not _original_scene():
		return false
	if AudioServer.get_bus_index(&"SFX") < 0:
		_diagnose("Missing SFX bus; world audio remains disabled.")
		_active = false
		_clear_sound()
		return false
	if not _active:
		_load_settings()
	_active = true
	_apply_settings()
	settings_changed.emit(_volume, _muted)
	return true


func invalidate_epoch() -> void:
	var cancelled_batch := _batch_open
	if is_instance_valid(_lab) and _lab.has_method("_audio_clear_sources"):
		_lab.call("_audio_clear_sources")
	_epoch += 1
	_clear_sound()
	_batch_cancelled = cancelled_batch
	_seen.clear()
	_controlled_id = 0
	_listener_owner_id = 0
	_listener_valid = false
	_candidate_frame = -1
	_batch_open = false
	_last_fire_refresh_msec = -1


func begin_batch() -> void:
	discard_batch()
	_prepare_frame()
	_batch_serial += 1
	_batch_epoch = _epoch
	_batch_frame = Engine.get_process_frames()
	_batch_open = true


func commit_batch() -> void:
	if not _batch_open:
		_batch_cancelled = false
		return
	var allowed := _gate()
	if _batch_epoch != _epoch or _batch_frame != Engine.get_process_frames() or not allowed:
		discard_batch()
		return
	for row: Dictionary in _candidates:
		if int(row.get("batch", 0)) == _batch_serial:
			row.batch = 0
	_batch_open = false


func discard_batch() -> void:
	if _batch_open:
		for index in range(_candidates.size() - 1, -1, -1):
			if int(_candidates[index].get("batch", 0)) == _batch_serial:
				_candidates.remove_at(index)
				_counts.dropped += 1
	_batch_open = false
	_batch_cancelled = false


# ground is the original TerrainLab-local XY, before any visual surface offset.
# Callers offer only original successful results, then commit their outer batch.
func offer(kind: StringName, ground: Vector2, event_key: String, person_id: int = 0,
		duration: float = 0.0, mounted: bool = false) -> bool:
	_counts.offered += 1
	_prepare_frame()
	if not _batch_open or _batch_cancelled or _batch_epoch != _epoch or _batch_frame != Engine.get_process_frames():
		_counts.dropped += 1
		return false
	_prune_seen()
	var key := "%d:%s" % [_epoch, event_key]
	if event_key.is_empty() or _seen.has(key):
		_counts.dropped += 1
		return false
	for queued: Dictionary in _candidates:
		if str(queued.key) == key:
			_counts.dropped += 1
			return false
	var step := _is_step(kind)
	# Remove the older step before checking the newest one's radius or budget.
	if step and person_id > 0:
		for index in range(_candidates.size() - 1, -1, -1):
			if bool(_candidates[index].step) and int(_candidates[index].person_id) == person_id:
				_candidates.remove_at(index)
				_counts.dropped += 1
	var offered_epoch := _epoch
	if not _gate() or offered_epoch != _epoch or not ground.is_finite():
		_counts.dropped += 1
		return false
	var distance_squared := ground.distance_squared_to(_listener_ground)
	var radius := _radius(kind)
	if distance_squared >= radius * radius:
		_counts.dropped += 1
		return false
	if step and (not is_finite(duration) or duration <= 0.0):
		_diagnose("Invalid original step duration; skipping footstep.")
		_counts.dropped += 1
		return false
	if step and (person_id <= 0 or not _step_source_alive(person_id)):
		_counts.dropped += 1
		return false
	_offer_order += 1
	var row := {"kind": kind, "position": ground, "key": key, "person_id": person_id,
		"duration": duration, "mounted": mounted, "step": step, "epoch": _epoch,
		"distance_squared": distance_squared, "radius": radius, "order": _offer_order,
		"priority": _priority(kind, person_id), "group": _group(kind),
		"batch": _batch_serial}
	if _candidates.size() < CANDIDATE_LIMIT:
		_candidates.append(row)
		return true
	var worst := _worst_index(_candidates)
	if _better(row, _candidates[worst]):
		_candidates[worst] = row
		_counts.dropped += 1
		return true
	_counts.dropped += 1
	return false


# Rows: {key: String, kind: StringName, position: Vector2, person_id: int = 0}.
# Person loops re-read their original owner position each presentation frame.
func set_loops(rows: Array[Dictionary]) -> void:
	_loop_requests.clear()
	if not _gate():
		return
	for source: Dictionary in rows:
		var ground: Variant = source.get("position")
		var key := str(source.get("key", ""))
		if key.is_empty() or not ground is Vector2 or not ground.is_finite():
			continue
		var kind := StringName(str(source.get("kind", "")))
		var radius := _radius(kind)
		var distance_squared: float = ground.distance_squared_to(_listener_ground)
		if kind.is_empty() or distance_squared >= radius * radius:
			continue
		var row := {"key": key, "kind": kind, "position": ground,
			"person_id": int(source.get("person_id", 0)), "epoch": _epoch,
			"radius": radius, "distance_squared": distance_squared,
			"priority": _priority(kind, int(source.get("person_id", 0))), "order": 0}
		if source.has("vehicle_id"):
			row.vehicle_id = str(source.vehicle_id)
			row.vehicle_record = source.get("vehicle_record")
			row.source_data = source.get("source_data")
		var duplicate := -1
		for index in _loop_requests.size():
			if str(_loop_requests[index].key) == key:
				duplicate = index
				break
		if duplicate >= 0:
			if _better(row, _loop_requests[duplicate]):
				_loop_requests[duplicate] = row
		elif _loop_requests.size() < CANDIDATE_LIMIT:
			_loop_requests.append(row)
		else:
			var worst := _worst_index(_loop_requests)
			if _better(row, _loop_requests[worst]):
				_loop_requests[worst] = row


func set_volume(value: float, user: bool = true) -> bool:
	if not _settings_owner() or not is_finite(value):
		return false
	_volume = clampf(value, 0.0, 1.0)
	_apply_settings()
	if _muted or _volume <= 0.0:
		_clear_sound()
	if user:
		_save_settings()
	settings_changed.emit(_volume, _muted)
	return true


func set_muted(value: bool, user: bool = true) -> bool:
	if not _settings_owner():
		return false
	_muted = value
	_apply_settings()
	if _muted:
		_clear_sound()
	if user:
		_save_settings()
	settings_changed.emit(_volume, _muted)
	return true


func stats_snapshot() -> Dictionary:
	var result := _counts.duplicate()
	result.merge({"active": _active, "epoch": _epoch, "volume": _volume, "muted": _muted,
		"listener_valid": _listener_valid, "listener_ground": _listener_ground,
		"controlled_person_id": _controlled_id, "candidate_count": _candidates.size(),
		"short_count": _playing_count(_short_players), "loop_count": _playing_count(_loop_players),
		"dedup_count": _seen.size(), "batch_open": _batch_open,
		"diagnostics": _diagnostics.duplicate()})
	return result


func _process(_delta: float) -> void:
	if not _gate():
		_clear_sound()
		return
	_prune_seen()
	var environment_now := Time.get_ticks_msec()
	if _last_fire_refresh_msec < 0 or environment_now - _last_fire_refresh_msec >= 100:
		var environment_data: Variant = _lab.get("terrain")
		if environment_data is TerrainData:
			_audio_environment_refresh(environment_data, environment_now)
	_recheck_short()
	var ready: Array[Dictionary] = []
	if _candidate_frame == Engine.get_process_frames():
		for row: Dictionary in _candidates:
			if int(row.batch) == 0 and int(row.epoch) == _epoch:
				row.distance_squared = row.position.distance_squared_to(_listener_ground)
				ready.append(row)
	ready.sort_custom(_better)
	_candidates.clear()
	_batch_open = false
	_batch_cancelled = false
	for row: Dictionary in ready:
		if float(row.distance_squared) >= float(row.radius) * float(row.radius) or bool(row.step) and not _step_source_alive(int(row.person_id)):
			_counts.dropped += 1
			continue
		_play_short(row)
	var now := Time.get_ticks_msec()
	if _last_fire_refresh_msec < 0 or now - _last_fire_refresh_msec >= 100:
		var terrain: Variant = _lab.get("terrain")
		if terrain is TerrainData:
			_fire_loop_requests = _audio_fire_loops(terrain, _listener_ground)
			for row: Dictionary in _fire_loop_requests:
				row.epoch = _epoch
				row.radius = _radius(row.kind)
				row.priority = _priority(row.kind, int(row.person_id))
				row.order = 0
		_last_fire_refresh_msec = now
	_refresh_loops()
	_counts.peak_short = maxi(int(_counts.peak_short), _playing_count(_short_players))
	_counts.peak_loop = maxi(int(_counts.peak_loop), _playing_count(_loop_players))


func _exit_tree() -> void:
	_active = false
	_clear_sound()


func _new_player(node_name: String) -> AudioStreamPlayer2D:
	var player := AudioStreamPlayer2D.new()
	player.name = node_name
	player.bus = &"SFX"
	player.max_polyphony = 1
	player.max_distance = GENERAL_RADIUS
	player.attenuation = 1.0
	player.panning_strength = 0.0
	add_child(player)
	return player


func _original_scene() -> bool:
	return is_inside_tree() and is_instance_valid(_lab) and _lab.is_inside_tree() \
		and get_tree().current_scene == _lab and not bool(_lab.get("restore_only")) \
		and _lab.get("terrain") != null


func _settings_owner() -> bool:
	return _active and _original_scene() and AudioServer.get_bus_index(&"SFX") >= 0


func _gate() -> bool:
	_listener_valid = false
	if not _active or not _original_scene() or _muted or _volume <= 0.0 or get_tree().paused:
		return false
	if AudioServer.get_bus_index(&"SFX") < 0:
		_diagnose("Missing SFX bus; world audio remains disabled.")
		return false
	var terrain: Variant = _lab.get("terrain")
	var site: Variant = terrain.get("site")
	if not site is Dictionary or bool(site.get("paused", false)):
		return false
	var controller: Variant = _lab.get("site_controller")
	if controller != null:
		if controller.has_method("original_step_fault_guard"):
			var guard: Dictionary = controller.call("original_step_fault_guard")
			if not bool(guard.get("ok", false)):
				return false
		if controller.has_method("region_operation_pending") and bool(controller.call("region_operation_pending")):
			return false
		if controller.has_method("ground_crossing_blocks_clock") and bool(controller.call("ground_crossing_blocks_clock")):
			return false
	var identity := int(_lab.call("controlled_person_id"))
	if identity <= 0:
		return false
	var target: Dictionary = _lab.call("_combat_target_in_site", identity)
	var ground: Variant = target.get("position")
	var size: Variant = terrain.get("size")
	if target.is_empty() or not _finite_number(target.get("hp")) or float(target.hp) <= 0.0 \
			or not ground is Vector2 or not ground.is_finite() or not size is Vector2i \
			or ground.x < 0.0 or ground.y < 0.0 or ground.x >= float(size.x) * CELL_PIXELS \
			or ground.y >= float(size.y) * CELL_PIXELS:
		return false
	var owner: Variant = target.get("owner")
	if not owner is Object or not is_instance_valid(owner):
		return false
	var owner_id: int = owner.get_instance_id()
	if _controlled_id > 0 and (_controlled_id != identity or _listener_owner_id != owner_id):
		invalidate_epoch()
	_controlled_id = identity
	_listener_owner_id = owner_id
	_listener_ground = ground
	_listener.global_position = _lab.to_global(_listener_ground)
	if not _listener.is_current():
		_listener.make_current()
	_listener_valid = true
	return true


func _step_source_alive(identity: int) -> bool:
	if not is_instance_valid(_lab) or identity <= 0:
		return false
	var target: Dictionary = _lab.call("_combat_target_in_site", identity)
	if target.is_empty() or not _finite_number(target.get("hp")) or float(target.hp) <= 0.0:
		return false
	var owner: Variant = target.get("owner")
	if not owner is Object or not is_instance_valid(owner):
		return false
	var unit := int(target.get("unit", -1))
	var ko: Variant = owner.call("combat_hot_get", unit, &"ko", 0.0) if unit >= 0 else owner.get("knockout_left")
	return _finite_number(ko) and float(ko) <= 0.0


func _clear_sound() -> void:
	_counts.dropped += _candidates.size()
	_candidates.clear()
	_loop_requests.clear()
	_fire_loop_requests.clear()
	_environment_loop_requests.clear()
	_last_animal_call_msec = -1
	_batch_open = false
	for index in _short_players.size():
		_short_players[index].stop()
		_short_rows[index] = {}
	for index in _loop_players.size():
		_loop_players[index].stop()
		_loop_rows[index] = {}
	_listener_valid = false
	_last_fire_refresh_msec = -1
	if is_instance_valid(_listener) and _listener.is_inside_tree() and _listener.is_current():
		_listener.clear_current()


func _prepare_frame() -> void:
	var frame := Engine.get_process_frames()
	if frame != _candidate_frame:
		_counts.dropped += _candidates.size()
		_candidates.clear()
		_candidate_frame = frame


func _radius(kind: StringName) -> float:
	return LARGE_RADIUS if kind in LARGE_KINDS else GENERAL_RADIUS


func _is_step(kind: StringName) -> bool:
	return str(kind).begins_with("step_") or str(kind).begins_with("hoof_")


func _group(kind: StringName) -> String:
	if _is_step(kind):
		return "step"
	var definition: Dictionary = _catalog.get(str(kind), {})
	var group := str(definition.get("group", "other"))
	return "contact" if group == "combat" else group


func _priority(kind: StringName, person_id: int) -> int:
	var definition: Dictionary = _catalog.get(str(kind), {})
	var base := 10
	if _finite_number(definition.get("priority")):
		base = clampi(int(definition.priority), 0, 100)
	if person_id == _controlled_id and kind in [&"hurt", &"contact", &"shield", &"down"]:
		base += 100
	return base


func _better(first: Dictionary, second: Dictionary) -> bool:
	if int(first.priority) != int(second.priority):
		return int(first.priority) > int(second.priority)
	if float(first.distance_squared) != float(second.distance_squared):
		return float(first.distance_squared) < float(second.distance_squared)
	return int(first.order) > int(second.order)


func _worst_index(rows: Array[Dictionary]) -> int:
	var worst := 0
	for index in range(1, rows.size()):
		if _better(rows[worst], rows[index]):
			worst = index
	return worst


func _recheck_short() -> void:
	for index in _short_rows.size():
		var row := _short_rows[index]
		if row.is_empty():
			continue
		row.distance_squared = row.position.distance_squared_to(_listener_ground)
		if not _short_players[index].playing or int(row.epoch) != _epoch \
				or float(row.distance_squared) >= float(row.radius) * float(row.radius) \
				or bool(row.step) and not _step_source_alive(int(row.person_id)):
			_short_players[index].stop()
			_short_rows[index] = {}


func _play_short(row: Dictionary) -> void:
	var selection := _select_variant(row)
	if selection.is_empty():
		_counts.dropped += 1
		return
	var stream := _stream(selection, false)
	if stream == null:
		_counts.dropped += 1
		return
	var slot := _short_slot(row)
	if slot < 0:
		_counts.dropped += 1
		return
	var player := _short_players[slot]
	player.stop()
	player.stream = stream
	player.global_position = _lab.to_global(row.position)
	player.max_distance = float(row.radius)
	player.pitch_scale = clampf(float(selection.duration) / float(row.duration), 0.8, 1.25) if bool(row.step) else 1.0
	player.volume_db = _kind_volume(row.kind)
	_short_rows[slot] = row
	_remember(str(row.key))
	player.play()
	_counts.played += 1


func _short_slot(row: Dictionary) -> int:
	var free := -1
	var group_slots: Array[int] = []
	var all_slots: Array[int] = []
	for index in _short_rows.size():
		var current := _short_rows[index]
		if current.is_empty() or not _short_players[index].playing:
			if free < 0:
				free = index
			continue
		if bool(row.step) and bool(current.step) and int(current.person_id) == int(row.person_id):
			return index
		all_slots.append(index)
		if str(current.group) == str(row.group):
			group_slots.append(index)
	var slots: Array[int] = all_slots
	if group_slots.size() >= int(GROUP_LIMITS.get(str(row.group), SHORT_LIMIT)):
		slots = group_slots
	elif free >= 0:
		return free
	if slots.is_empty():
		return -1
	var worst := slots[0]
	for index in slots:
		if _better(_short_rows[worst], _short_rows[index]):
			worst = index
	return worst if _better(row, _short_rows[worst]) else -1


func _refresh_loops() -> void:
	var ready: Array[Dictionary] = []
	var requests: Array[Dictionary] = _loop_requests.duplicate()
	requests.append_array(_fire_loop_requests)
	requests.append_array(_environment_loop_requests)
	for request: Dictionary in requests:
		var row := request.duplicate()
		if int(row.epoch) != _epoch:
			continue
		if row.has("vehicle_id"):
			var vehicle_ground := _audio_vehicle_loop_ground(row)
			if not vehicle_ground.is_finite():
				continue
			row.position = vehicle_ground
		if int(row.person_id) > 0:
			if not _step_source_alive(int(row.person_id)):
				continue
			var target: Dictionary = _lab.call("_combat_target_in_site", int(row.person_id))
			var ground: Variant = target.get("position")
			if not ground is Vector2 or not ground.is_finite():
				continue
			row.position = ground
		row.distance_squared = row.position.distance_squared_to(_listener_ground)
		var existing := _loop_slot(str(row.key))
		var start := LARGE_LOOP_START if row.kind in LARGE_KINDS else GENERAL_LOOP_START
		var radius := float(row.radius) if existing >= 0 else start
		if float(row.distance_squared) < radius * radius:
			ready.append(row)
	ready.sort_custom(_better)
	if ready.size() > LOOP_LIMIT:
		ready.resize(LOOP_LIMIT)
	var selected: Dictionary = {}
	for row: Dictionary in ready:
		selected[str(row.key)] = true
	for index in _loop_rows.size():
		if not _loop_rows[index].is_empty() and not selected.has(str(_loop_rows[index].key)):
			_loop_players[index].stop()
			_loop_rows[index] = {}
	for row: Dictionary in ready:
		var slot := _loop_slot(str(row.key))
		if slot >= 0 and _loop_rows[slot].kind == row.kind and _loop_players[slot].playing:
			_loop_rows[slot] = row
			_loop_players[slot].global_position = _lab.to_global(row.position)
			_loop_players[slot].max_distance = float(row.radius)
			continue
		if slot < 0:
			for index in _loop_rows.size():
				if _loop_rows[index].is_empty():
					slot = index
					break
		if slot < 0:
			continue
		var selection := _select_variant(row)
		var stream: AudioStream = null if selection.is_empty() else _stream(selection, true)
		if stream == null:
			_loop_players[slot].stop()
			_loop_rows[slot] = {}
			continue
		var player := _loop_players[slot]
		player.stop()
		player.stream = stream
		player.global_position = _lab.to_global(row.position)
		player.max_distance = float(row.radius)
		player.pitch_scale = 1.0
		player.volume_db = _kind_volume(row.kind)
		_loop_rows[slot] = row
		player.play()


func _loop_slot(key: String) -> int:
	for index in _loop_rows.size():
		if not _loop_rows[index].is_empty() and str(_loop_rows[index].key) == key:
			return index
	return -1


func _select_variant(row: Dictionary) -> Dictionary:
	var definition: Dictionary = _catalog.get(str(row.kind), {})
	var variants: Variant = definition.get("variants", [])
	if not variants is Array or variants.is_empty():
		_diagnose("No audio asset for kind %s." % str(row.kind))
		return {}
	var choices: Array[Dictionary] = []
	var best := INF
	for value: Variant in variants:
		if not value is Dictionary or not value.get("path") is String:
			continue
		if not _finite_number(value.get("duration")) or float(value.duration) <= 0.0:
			_diagnose("Invalid audio duration for kind %s." % str(row.kind))
			continue
		var score := absf(float(value.duration) / float(row.duration) - 1.0) if bool(row.get("step", false)) else 0.0
		if score < best - 0.000001:
			choices.clear()
			best = score
		if absf(score - best) <= 0.000001:
			choices.append(value)
	if choices.is_empty():
		return {}
	# Event-derived selection never consumes the gameplay RNG.
	return choices[posmod(str(row.key).hash(), choices.size())]


func _stream(variant: Dictionary, loop: bool) -> AudioStream:
	var path := str(variant.path)
	var cache_key := "%s:%s" % [path, str(loop)]
	if _streams.has(cache_key):
		return _streams[cache_key] as AudioStream
	if not path.begins_with("res://assets/audio/") or not ResourceLoader.exists(path):
		_diagnose("Missing audio resource %s." % path)
		_streams[cache_key] = null
		return null
	var stream := ResourceLoader.load(path) as AudioStream
	_counts.stream_loads += 1
	if stream == null:
		_diagnose("Invalid audio resource %s." % path)
		_streams[cache_key] = null
		return null
	if stream is AudioStreamWAV:
		# One shared copy per path/mode, never one copy per event or person.
		var wav := stream.duplicate() as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
		if loop:
			wav.loop_begin = 0
			wav.loop_end = maxi(0, int(round(wav.get_length() * float(wav.mix_rate))) - 1)
		stream = wav
	elif stream is AudioStreamOggVorbis:
		var ogg := stream.duplicate() as AudioStreamOggVorbis
		ogg.loop = loop
		stream = ogg
	elif loop:
		_diagnose("Unsupported loop audio resource %s." % path)
		stream = null
	_streams[cache_key] = stream
	return stream


func _kind_volume(kind: StringName) -> float:
	var definition: Dictionary = _catalog.get(str(kind), {})
	return clampf(float(definition.volume_db), -60.0, 0.0) if _finite_number(definition.get("volume_db")) else 0.0


func _load_catalog() -> void:
	if not FileAccess.file_exists(CATALOG_PATH):
		_diagnose("Missing audio catalog.")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if parsed is Dictionary and parsed.get("sounds") is Dictionary:
		_catalog = parsed.sounds
	else:
		_diagnose("Invalid audio catalog.")


func _load_settings() -> void:
	_volume = DEFAULT_VOLUME
	_muted = false
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error == ERR_FILE_NOT_FOUND:
		return
	if error != OK:
		_diagnose("Cannot read local audio settings (%d)." % error)
		return
	var saved_volume: Variant = config.get_value("sfx", "volume", DEFAULT_VOLUME)
	var saved_muted: Variant = config.get_value("sfx", "muted", false)
	if _finite_number(saved_volume):
		_volume = clampf(float(saved_volume), 0.0, 1.0)
	else:
		_diagnose("Invalid local SFX volume; using default.")
	if saved_muted is bool:
		_muted = saved_muted
	else:
		_diagnose("Invalid local SFX mute; using default.")


func _apply_settings() -> void:
	var bus := AudioServer.get_bus_index(&"SFX")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(_volume, 0.0001)))
		AudioServer.set_bus_mute(bus, _muted or _volume <= 0.0)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("sfx", "volume", _volume)
	config.set_value("sfx", "muted", _muted)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		_diagnose("Local audio settings were not saved (%d)." % error)


func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


func _remember(key: String) -> void:
	while _seen.size() >= DEDUP_LIMIT:
		_seen.erase(_seen.keys()[0])
	_seen[key] = Time.get_ticks_msec()


func _prune_seen() -> void:
	var frame := Engine.get_process_frames()
	if frame == _last_seen_prune:
		return
	_last_seen_prune = frame
	var now := Time.get_ticks_msec()
	for key: Variant in _seen.keys():
		if now - int(_seen[key]) >= DEDUP_MSEC:
			_seen.erase(key)


func _playing_count(players: Array[AudioStreamPlayer2D]) -> int:
	var count := 0
	for player: AudioStreamPlayer2D in players:
		if player.playing:
			count += 1
	return count


func _diagnose(message: String) -> void:
	if message in _diagnostics or _diagnostics.size() >= 64:
		return
	_diagnostics.append(message)
	push_warning("SiteAudioView: " + message)


# Paste into the unique SiteAudioView. It only returns loop rows; never plays.
# position/listener_ground are TerrainLab local ground pixels (not to_global).
# ponytail: P1 projects one nearest fire group; other loop slots remain shared.
# Counts below bound this projection; borrowed Runtime descriptor/edge queries
# keep their existing implementation cost and still require the P1 p95 check.
const AUDIO_FIRE_QUERY_RADIUS_PX := 1920.0 # 60 m at 32 ground px/m.
const AUDIO_FIRE_GRID_READS := 4096
const AUDIO_FIRE_ENTRY_READS := 2048
const AUDIO_FIRE_UNIT_READS := 64
const AUDIO_FIRE_CELL_READS := 1024
const AUDIO_FIRE_EDGE_READS := 512
const AUDIO_FIRE_SEEDS := 64

func _audio_fire_loops(data: TerrainData, listener_ground: Vector2) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if data == null or data.site.is_empty() or not listener_ground.is_finite():
		return rows
	var state: Dictionary = data.site.get("fire", {})
	var cached: Dictionary = data.get_meta(&"fire_hazard_projection", {})
	# ponytail: borrow only the original owner's current cache. Missing/stale
	# cache is silent until that owner publishes; audio never rebuilds all fire.
	if cached.is_empty() or not is_same(cached.get("state"), state) \
			or int(cached.get("step", -2)) != int(state.get("step_index", -1)) \
			or int(cached.get("environment", -1)) != data.environment_revision \
			or int(cached.get("navigation", -1)) != data.navigation_revision:
		return rows
	var snapshot: Dictionary = cached.get("snapshot", {})
	if not snapshot.get("cells") is Dictionary or not snapshot.get("chunks") is Dictionary:
		return rows
	var units: Dictionary = state.get("units", {})
	var pixels := float(TerrainRenderer.CELL_PIXELS)
	var radius_cells := ceili(AUDIO_FIRE_QUERY_RADIUS_PX / pixels)
	var center := Vector2i((listener_ground / pixels).floor())
	var seeds := {}
	var grid_reads := 0
	var entry_reads := 0
	for y in range(maxi(0, center.y - radius_cells), mini(data.size.y, center.y + radius_cells + 1)):
		for x in range(maxi(0, center.x - radius_cells), mini(data.size.x, center.x + radius_cells + 1)):
			grid_reads += 1
			if grid_reads > AUDIO_FIRE_GRID_READS:
				return rows # Unknown: caller set_loops([]) stops an old fire loop.
			var cell := Vector2i(x, y)
			if not snapshot.chunks.has(Vector2i(floori(float(x) / 16.0), floori(float(y) / 16.0))):
				continue
			var fire_position := (Vector2(cell) + Vector2.ONE * 0.5) * pixels
			var distance_sq := fire_position.distance_squared_to(listener_ground)
			if distance_sq >= AUDIO_FIRE_QUERY_RADIUS_PX * AUDIO_FIRE_QUERY_RADIUS_PX:
				continue
			for entry: Dictionary in snapshot.cells.get(data.index(cell), []):
				entry_reads += 1
				if entry_reads > AUDIO_FIRE_ENTRY_READS:
					return rows
				var key := str(entry.get("key", ""))
				var unit: Dictionary = units.get(key, {})
				if str(unit.get("state", "")) not in ["BURNING", "EMBERS"]:
					continue # Hazard risk/warnings are not burning sound evidence.
				if seeds.has(key) and float(seeds[key].distance_sq) <= distance_sq:
					continue
				seeds[key] = {"key": key, "position": fire_position, "distance_sq": distance_sq}
				if seeds.size() > AUDIO_FIRE_SEEDS:
					var worst := key
					for candidate_key: String in seeds:
						if float(seeds[candidate_key].distance_sq) > float(seeds[worst].distance_sq) or (float(seeds[candidate_key].distance_sq) == float(seeds[worst].distance_sq) and candidate_key > worst):
							worst = candidate_key
					seeds.erase(worst)
	var ordered: Array = seeds.values()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.key) < str(b.key) if float(a.distance_sq) == float(b.distance_sq) else float(a.distance_sq) < float(b.distance_sq))
	var budget := {"units": AUDIO_FIRE_UNIT_READS, "cells": AUDIO_FIRE_CELL_READS, "edges": AUDIO_FIRE_EDGE_READS}
	var completed_keys := {}
	for seed: Dictionary in ordered:
		var seed_key := str(seed.key)
		if completed_keys.has(seed_key):
			continue
		var classification := _audio_fire_group_classification(data, units, seed_key, budget)
		if not bool(classification.get("known", false)):
			continue # Do not retain a stale unknown loop.
		for visited_key: String in classification.get("complete_keys", {}):
			completed_keys[visited_key] = true
		var large := bool(classification.large)
		var loop_key := "fire:" + seed_key + "@" + str(units[seed_key].get("generation", 1))
		var existing := _loop_slot(loop_key) >= 0
		var radius := LARGE_RADIUS if large else GENERAL_RADIUS
		if not existing:
			radius = LARGE_LOOP_START if large else GENERAL_LOOP_START
		if float(seed.distance_sq) >= radius * radius:
			continue # An uncreated 19 m small fire must not mask a valid 50 m large fire.
		# _refresh_loops repeats creation hysteresis and the hard stop every frame.
		# P1 returns one seed, so incomplete identity cannot create duplicate loops.
		rows.append({"key": loop_key,
			"kind": &"fire_large" if large else &"fire_small", "position": Vector2(seed.position), "person_id": 0})
		break
	return rows

func _audio_fire_group_classification(data: TerrainData, units: Dictionary, seed_key: String, budget: Dictionary) -> Dictionary:
	var pending: Array[String] = [seed_key]
	var queued := {seed_key: true}
	var head := 0
	var burning_cells := {}
	while head < pending.size():
		budget.units -= 1
		if int(budget.units) < 0:
			return {"known": false}
		var key := pending[head]
		head += 1
		var unit: Dictionary = units.get(key, {})
		if str(unit.get("state", "")) not in ["BURNING", "EMBERS"]:
			continue
		var descriptor := SiteRuntime._fire_descriptor(data, unit)
		if descriptor.is_empty():
			if key == seed_key:
				return {"known": false}
			continue
		if str(unit.state) == "BURNING":
			if _audio_fire_live_burning_part(data, unit):
				return {"known": true, "large": true}
			for value: int in descriptor.get("hazard_cells", []):
				budget.cells -= 1
				if int(budget.cells) < 0:
					return {"known": false}
				burning_cells[value] = true # Unique ground index, not entry/unit/surface.
				if burning_cells.size() >= 4:
					return {"known": true, "large": true}
		# Follow original admitted contacts outside the listener query rectangle.
		# BURNING/EMBERS connect; unvoiced DORMANT/HEATING/COOLING never bridge.
		budget.cells -= descriptor.get("cells", []).size()
		if int(budget.cells) < 0:
			return {"known": false}
		var neighbors: Array[Dictionary] = SiteRuntime._fire_resource_edges(data, descriptor)
		neighbors.append_array(SiteRuntime._fire_feature_edges(data, descriptor))
		for other: Dictionary in neighbors:
			budget.edges -= 1
			if int(budget.edges) < 0:
				return {"known": false}
			var other_key := str(other.get("key", ""))
			if queued.has(other_key) or str(units.get(other_key, {}).get("state", "")) not in ["BURNING", "EMBERS"]:
				continue
			queued[other_key] = true
			if pending.size() >= AUDIO_FIRE_UNIT_READS:
				return {"known": false}
			pending.append(other_key)
	return {"known": true, "large": false, "complete_keys": queued} # Only a complete component can be small.

func _audio_fire_live_burning_part(data: TerrainData, unit: Dictionary) -> bool:
	if str(unit.get("kind", "")) != "feature" or int(unit.get("debris_version", 0)) != 0:
		return false
	var feature: Dictionary = data.site.get("features", {}).get(str(unit.get("feature", "")), {})
	var part: Dictionary = feature.get("parts", {}).get(str(unit.get("part", "")), {})
	return str(feature.get("stage", "")) == "complete" and float(part.get("hp", 0.0)) > 0.0

func native_step_watch_ids() -> PackedInt64Array:
	var ids := PackedInt64Array()
	if not _batch_open or _batch_cancelled or _batch_epoch != _epoch or _batch_frame != Engine.get_process_frames(): return ids
	for row: Dictionary in _candidates:
		if bool(row.step) and int(row.person_id) > 0: ids.append(int(row.person_id))
	return ids # _candidates already has the single 64-row ceiling.

func invalidate_step_candidate(identity: int) -> void:
	if identity <= 0 or not _batch_open or _batch_cancelled or _batch_epoch != _epoch or _batch_frame != Engine.get_process_frames(): return
	for index in range(_candidates.size() - 1, -1, -1):
		if bool(_candidates[index].step) and int(_candidates[index].person_id) == identity:
			_candidates.remove_at(index)
			_counts.dropped += 1

# OUTPUT ONLY: original local water/resource projection, no world state writes.
# ponytail: 441 local cells and 512 index entries per 100 ms; unknown animal
# coverage stays silent. Reuse a bounded owner query if its contract is added.

func _audio_environment_sources(data: TerrainData, listener_ground: Vector2) -> Dictionary:
	var water: Array[Dictionary] = []
	var animals: Array[Dictionary] = []
	var result := {"water": water, "animals": animals, "cells": 0,
		"resource_reads": 0, "animal_complete": true}
	if data == null or not listener_ground.is_finite():
		return result
	var count := data.size.x * data.size.y
	var has_water := data.surface_types.size() == count and data.water_kind.size() == count
	var center := Vector2i((listener_ground / CELL_PIXELS).floor())
	var area := Rect2i(center - Vector2i(10, 10), Vector2i(21, 21)).intersection(Rect2i(Vector2i.ZERO, data.size))
	var seen: Dictionary = {}
	var nearest_water: Dictionary = {}
	for y: int in range(area.position.y, area.end.y):
		for x: int in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			var index := data.index(cell)
			result.cells += 1
			var ground := (Vector2(cell) + Vector2.ONE * 0.5) * CELL_PIXELS
			var distance_squared := ground.distance_squared_to(listener_ground)
			if distance_squared >= GENERAL_RADIUS * GENERAL_RADIUS:
				continue
			if has_water and int(data.surface_types[index]) == TerrainData.Surface.WATER:
				var kind: StringName = &""
				if int(data.water_kind[index]) == 1:
					kind = &"water_fresh" # Water ambience; no invented current/weather.
				elif int(data.water_kind[index]) == 2:
					for direction: Vector2i in TerrainData.DIRECTIONS:
						var adjacent := cell + direction
						if data.contains(adjacent) and int(data.surface_types[data.index(adjacent)]) != TerrainData.Surface.WATER:
							kind = &"water_shore" # Real sea/dry boundary, not open ocean.
							break
				if not kind.is_empty():
					var row := {"key": "environment:" + str(kind), "kind": kind,
						"position": ground, "person_id": 0, "distance_squared": distance_squared,
						"priority": _priority(kind, 0), "order": -index}
					if nearest_water.is_empty() or _better(row, nearest_water):
						nearest_water = row
			if not bool(result.animal_complete):
				continue
			var keys: Variant = data.resources_at.get(index, [])
			if not keys is Array:
				continue
			for raw_key: Variant in keys:
				if int(result.resource_reads) >= AUDIO_ENV_RESOURCE_READS:
					result.animal_complete = false
					animals.clear()
					break
				result.resource_reads += 1
				var key := str(raw_key)
				if seen.has(key):
					continue
				seen[key] = true
				var base: Variant = data.resource_base.get(key)
				if not base is Dictionary or int(base.get("kind", -1)) != SiteEnvironment.Kind.WILDLIFE:
					continue
				var source := SiteEnvironment.resource(data, key)
				if bool(source.get("cleared", false)) or int(source.get("remaining", 0)) <= 0:
					continue
				var source_index := int(source.get("cell", -1))
				if source_index < 0 or source_index >= count:
					continue
				var source_ground := (Vector2(data.cell_from_index(source_index)) + Vector2.ONE * 0.5) * CELL_PIXELS
				var source_distance := source_ground.distance_squared_to(listener_ground)
				if source_distance >= GENERAL_RADIUS * GENERAL_RADIUS:
					continue
				var species: String = SiteEnvironment.resource_species(source)
				var kind := StringName("animal_" + ("deer" if species in ["stag", "doe"] else species))
				var row := {"key": "wildlife:" + key, "kind": kind,
					"position": source_ground, "person_id": 0, "distance_squared": source_distance,
					"priority": _priority(kind, 0), "order": -source_index}
				if animals.size() < CANDIDATE_LIMIT:
					animals.append(row)
				else:
					var worst := _worst_index(animals)
					if _better(row, animals[worst]):
						animals[worst] = row
	if not nearest_water.is_empty():
		water.append(nearest_water)
	animals.sort_custom(_better)
	return result

func _audio_environment_refresh(data: TerrainData, now: int) -> void:
	var projection := _audio_environment_sources(data, _listener_ground)
	_environment_loop_requests = projection.water
	for row: Dictionary in _environment_loop_requests:
		row.epoch = _epoch
		row.radius = _radius(row.kind)
	# A separate presentation batch must never take an original open batch.
	if _batch_open:
		return
	if _last_animal_call_msec < 0:
		_last_animal_call_msec = now
		return
	if now - _last_animal_call_msec < AUDIO_ANIMAL_CALL_MSEC:
		return
	_last_animal_call_msec = now # No catch-up calls after pause/mute/scene replace.
	var animals: Array[Dictionary] = projection.animals
	if animals.is_empty() or not bool(projection.animal_complete):
		return
	for animal: Dictionary in animals:
		var definition: Dictionary = _catalog.get(str(animal.kind), {})
		var variants: Variant = definition.get("variants", [])
		if not variants is Array or variants.is_empty():
			continue # A missing boar bank must not mask an available nearby horse.
		begin_batch()
		offer(animal.kind, animal.position, "%s:%d" % [str(animal.key), now])
		commit_batch()
		break

# Borrow the original vehicle record and current committed ground every frame.
# An ID reused by removal/restore cannot retain the old loop's record identity.

# Borrow the original vehicle record and current committed ground every frame.
# An ID reused by removal/restore cannot retain the old loop's record identity.
func _audio_vehicle_loop_ground(request: Dictionary) -> Vector2:
	var invalid := Vector2(INF, INF)
	var data: Variant = _lab.get("terrain")
	if not data is TerrainData or not is_same(request.get("source_data"), data):
		return invalid
	var controller: Variant = _lab.get("site_controller")
	if controller == null:
		return invalid
	var transport: Variant = controller.get("vehicles")
	if not transport is SiteVehicleTransport:
		return invalid
	var vehicle: Dictionary = transport.records().get(str(request.get("vehicle_id", "")), {})
	if vehicle.is_empty() or not is_same(vehicle, request.get("vehicle_record")) or vehicle.get("move", {}).is_empty():
		return invalid
	var kind := str(vehicle.get("kind", ""))
	if kind == "ship":
		if not transport.ship_afloat(vehicle) or float(vehicle.get("naval", {}).get("hp", 0.0)) <= 0.0 \
				or transport._ship_in_journey(str(vehicle.id)):
			return invalid
	elif kind != "cart":
		return invalid # Existing wagon is riding a horse; hoof steps own its sound.
	var pose: Dictionary = transport.render_state(vehicle)
	var ground: Variant = pose.get("position")
	if not bool(pose.get("moving", false)) or float(pose.get("progress", 0.0)) <= 0.0 \
			or not ground is Vector2 or not ground.is_finite():
		return invalid
	return ground
