class_name PersistenceService
extends RefCounted

const PersistenceResultType = preload("res://scripts/persistence/persistence_result.gd")
const SessionSaveDataType = preload("res://scripts/persistence/session_save_data.gd")
const RegionFeatureDeltaType = preload("res://scripts/runtime/region_feature_delta.gd")

const DEFAULT_SAVE_PATH: String = "user://worldgoing_save.json"

var world_data: WorldData

func _init(p_world_data: WorldData = null) -> void:
	world_data = p_world_data

func save_session(session: GameSession, file_path: String = DEFAULT_SAVE_PATH) -> PersistenceResult:
	var result: PersistenceResult = PersistenceResultType.new()
	result.file_path = file_path
	if session == null or session.party == null:
		result.failure_reason = PersistenceResultType.Code.INVALID_SESSION
		return result
	if file_path.is_empty():
		result.failure_reason = PersistenceResultType.Code.INVALID_PATH
		return result
	if session.has_travel_plan():
		result.failure_reason = PersistenceResultType.Code.TRAVEL_IN_PROGRESS
		return result
	var snapshot: SessionSaveData = SessionSaveDataType.capture(session)
	var validation_reason: int = _validate_snapshot(snapshot, world_data)
	if validation_reason != PersistenceResultType.Code.NONE:
		result.failure_reason = validation_reason
		return result
	var wire_result: Dictionary = _snapshot_to_wire(snapshot)
	if not bool(wire_result.get("ok", false)):
		result.failure_reason = int(wire_result.get(
			"reason",
			PersistenceResultType.Code.INVALID_DATA
		))
		return result
	var serialized: String = JSON.stringify(wire_result["data"])
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		result.failure_reason = PersistenceResultType.Code.IO_ERROR
		return result
	file.store_string(serialized)
	file.close()
	result.success = true
	result.bytes_written = serialized.to_utf8_buffer().size()
	return result

func load_session(
		file_path: String = DEFAULT_SAVE_PATH,
		p_world_data: WorldData = null
	) -> PersistenceResult:
	var result: PersistenceResult = PersistenceResultType.new()
	result.file_path = file_path
	if file_path.is_empty():
		result.failure_reason = PersistenceResultType.Code.INVALID_PATH
		return result
	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		result.failure_reason = PersistenceResultType.Code.IO_ERROR
		return result
	var raw_text: String = file.get_as_text()
	file.close()
	var json: JSON = JSON.new()
	if json.parse(raw_text) != OK:
		result.failure_reason = PersistenceResultType.Code.CORRUPT_DATA
		return result
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		result.failure_reason = PersistenceResultType.Code.CORRUPT_DATA
		return result
	var parsed_snapshot: Dictionary = _snapshot_from_wire(parsed as Dictionary)
	if not bool(parsed_snapshot.get("ok", false)):
		result.failure_reason = int(parsed_snapshot.get(
			"reason",
			PersistenceResultType.Code.CORRUPT_DATA
		))
		return result
	var snapshot: SessionSaveData = parsed_snapshot["snapshot"] as SessionSaveData
	var validation_world_data: WorldData = p_world_data if p_world_data != null else world_data
	var validation_reason: int = _validate_snapshot(snapshot, validation_world_data)
	if validation_reason != PersistenceResultType.Code.NONE:
		result.failure_reason = validation_reason
		return result
	result.session = _restore_snapshot(snapshot)
	result.success = result.session != null
	if not result.success:
		result.failure_reason = PersistenceResultType.Code.INVALID_DATA
	return result

func _snapshot_to_wire(snapshot: SessionSaveData) -> Dictionary:
	var regions: Array = []
	for entry: Dictionary in snapshot.regions:
		var world_cell: Variant = entry.get("world_cell", null)
		var delta: Variant = entry.get("delta", null)
		if not world_cell is Vector2i or not delta is RegionDelta:
			return _failed_wire(PersistenceResultType.Code.INVALID_REGION_DELTA)
		var delta_wire: Dictionary = _delta_to_wire(delta as RegionDelta)
		if not bool(delta_wire.get("ok", false)):
			return delta_wire
		var site_ids: Array = []
		for site_id: Variant in entry.get("discovered_site_ids", []):
			if not site_id is String:
				return _failed_wire(PersistenceResultType.Code.INVALID_DATA)
			site_ids.append(site_id as String)
		regions.append({
			"world_cell": _vector_to_wire(world_cell as Vector2i),
			"discovered": bool(entry.get("discovered", false)),
			"discovered_site_ids": site_ids,
			"delta": delta_wire["data"],
		})
	return {
		"ok": true,
		"data": {
			"format_version": snapshot.format_version,
			"generation_versions": {
				"terrain": snapshot.terrain_generation_version,
				"poi": snapshot.poi_generation_version,
				"road": snapshot.road_generation_version,
			},
			"world_seed": snapshot.world_seed,
			"world_time_seconds": snapshot.world_time_seconds,
			"party": {
				"party_id": snapshot.party_id,
				"display_name": snapshot.party_display_name,
				"global_cell": _vector_to_wire(snapshot.party_global_cell),
				"base_walk_speed_kmh": snapshot.party_base_walk_speed_kmh,
				"initialized": snapshot.party_initialized,
			},
			"regions": regions,
		},
	}

func _snapshot_from_wire(wire: Dictionary) -> Dictionary:
	var format_result: Dictionary = _read_int(wire.get("format_version", null))
	if not bool(format_result.get("ok", false)):
		return _failed_wire(PersistenceResultType.Code.CORRUPT_DATA)
	if int(format_result["value"]) != SessionSaveData.FORMAT_VERSION:
		return _failed_wire(PersistenceResultType.Code.UNSUPPORTED_VERSION)
	var versions: Variant = wire.get("generation_versions", null)
	if not versions is Dictionary:
		return _failed_wire(PersistenceResultType.Code.CORRUPT_DATA)
	var terrain_version: Dictionary = _read_int((versions as Dictionary).get("terrain", null))
	var poi_version: Dictionary = _read_int((versions as Dictionary).get("poi", null))
	var road_version: Dictionary = _read_int((versions as Dictionary).get("road", null))
	if not bool(terrain_version.get("ok", false)) \
		or not bool(poi_version.get("ok", false)) \
		or not bool(road_version.get("ok", false)):
		return _failed_wire(PersistenceResultType.Code.CORRUPT_DATA)
	var world_seed: Dictionary = _read_int(wire.get("world_seed", null))
	var world_time: Dictionary = _read_int(wire.get("world_time_seconds", null))
	if not bool(world_seed.get("ok", false)) or not bool(world_time.get("ok", false)):
		return _failed_wire(PersistenceResultType.Code.CORRUPT_DATA)
	var party_value: Variant = wire.get("party", null)
	if not party_value is Dictionary:
		return _failed_wire(PersistenceResultType.Code.CORRUPT_DATA)
	var party: Dictionary = party_value as Dictionary
	var party_id: Dictionary = _read_string(party.get("party_id", null))
	var display_name: Dictionary = _read_string(party.get("display_name", null))
	var global_cell: Dictionary = _read_vector2i(party.get("global_cell", null))
	var walk_speed: Dictionary = _read_float(party.get("base_walk_speed_kmh", null))
	if not bool(party_id.get("ok", false)) \
		or not bool(display_name.get("ok", false)) \
		or not bool(global_cell.get("ok", false)) \
		or not bool(walk_speed.get("ok", false)) \
		or not party.has("initialized") \
		or not party["initialized"] is bool:
		return _failed_wire(PersistenceResultType.Code.CORRUPT_DATA)
	var regions_value: Variant = wire.get("regions", null)
	if not regions_value is Array:
		return _failed_wire(PersistenceResultType.Code.CORRUPT_DATA)
	var snapshot: SessionSaveData = SessionSaveDataType.new()
	snapshot.format_version = int(format_result["value"])
	snapshot.terrain_generation_version = int(terrain_version["value"])
	snapshot.poi_generation_version = int(poi_version["value"])
	snapshot.road_generation_version = int(road_version["value"])
	snapshot.world_seed = int(world_seed["value"])
	snapshot.world_time_seconds = int(world_time["value"])
	snapshot.party_id = party_id["value"] as String
	snapshot.party_display_name = display_name["value"] as String
	snapshot.party_global_cell = global_cell["value"] as Vector2i
	snapshot.party_base_walk_speed_kmh = float(walk_speed["value"])
	snapshot.party_initialized = party["initialized"] as bool
	for region_value: Variant in regions_value as Array:
		if not region_value is Dictionary:
			return _failed_wire(PersistenceResultType.Code.CORRUPT_DATA)
		var region: Dictionary = region_value as Dictionary
		var region_cell: Dictionary = _read_vector2i(region.get("world_cell", null))
		if not bool(region_cell.get("ok", false)) \
			or not region.has("discovered") \
			or not region["discovered"] is bool \
			or not region.get("discovered_site_ids", []) is Array \
			or not region.get("delta", null) is Dictionary:
			return _failed_wire(PersistenceResultType.Code.CORRUPT_DATA)
		var site_ids: Array[String] = []
		for site_id: Variant in region["discovered_site_ids"] as Array:
			if not site_id is String:
				return _failed_wire(PersistenceResultType.Code.CORRUPT_DATA)
			site_ids.append(site_id as String)
		var delta_result: Dictionary = _delta_from_wire(region["delta"] as Dictionary)
		if not bool(delta_result.get("ok", false)):
			return delta_result
		snapshot.regions.append({
			"world_cell": region_cell["value"],
			"discovered": region["discovered"] as bool,
			"discovered_site_ids": site_ids,
			"delta": delta_result["delta"],
		})
	snapshot.regions.sort_custom(Callable(snapshot, "_region_less"))
	return {"ok": true, "snapshot": snapshot}

func _delta_to_wire(delta: RegionDelta) -> Dictionary:
	var terrain_overrides: Array = []
	var terrain_cells: Array[Vector2i] = []
	for key: Variant in delta.terrain_overrides.keys():
		if not key is Vector2i:
			return _failed_wire(PersistenceResultType.Code.INVALID_REGION_DELTA)
		terrain_cells.append(key as Vector2i)
	terrain_cells.sort_custom(Callable(self, "_vector_less"))
	for cell: Vector2i in terrain_cells:
		var terrain_type: Dictionary = _read_int(delta.terrain_overrides[cell])
		if not bool(terrain_type.get("ok", false)):
			return _failed_wire(PersistenceResultType.Code.INVALID_REGION_DELTA)
		terrain_overrides.append({
			"cell": _vector_to_wire(cell),
			"terrain_type": terrain_type["value"],
		})
	var added_features: Array = []
	var feature_ids: Array[String] = []
	for key: Variant in delta.added_features.keys():
		if not key is String:
			return _failed_wire(PersistenceResultType.Code.INVALID_REGION_DELTA)
		feature_ids.append(key as String)
	feature_ids.sort()
	for feature_id: String in feature_ids:
		var feature: Variant = delta.added_features[feature_id]
		if not feature is RegionFeatureDelta:
			return _failed_wire(PersistenceResultType.Code.INVALID_REGION_DELTA)
		var payload_result: Dictionary = _encode_value((feature as RegionFeatureDelta).payload)
		if not bool(payload_result.get("ok", false)):
			return _failed_wire(PersistenceResultType.Code.INVALID_REGION_DELTA)
		added_features.append({
			"feature_id": feature_id,
			"feature_type": str((feature as RegionFeatureDelta).feature_type),
			"cell": _vector_to_wire((feature as RegionFeatureDelta).region_cell),
			"payload": payload_result["value"],
		})
	var removed_feature_ids: Array[String] = []
	for key: Variant in delta.removed_feature_ids.keys():
		if not key is String:
			return _failed_wire(PersistenceResultType.Code.INVALID_REGION_DELTA)
		removed_feature_ids.append(key as String)
	removed_feature_ids.sort()
	return {
		"ok": true,
		"data": {
			"world_cell": _vector_to_wire(delta.world_cell),
			"base_generation_version": delta.base_generation_version,
			"revision": delta.revision,
			"terrain_overrides": terrain_overrides,
			"added_features": added_features,
			"removed_feature_ids": removed_feature_ids,
			"owner_id": delta.owner_id,
			"development_level": delta.development_level,
		},
	}

func _delta_from_wire(wire: Dictionary) -> Dictionary:
	var world_cell: Dictionary = _read_vector2i(wire.get("world_cell", null))
	var base_version: Dictionary = _read_int(wire.get("base_generation_version", null))
	var revision: Dictionary = _read_int(wire.get("revision", null))
	var owner: Dictionary = _read_string(wire.get("owner_id", null))
	var development: Dictionary = _read_int(wire.get("development_level", null))
	if not bool(world_cell.get("ok", false)) \
		or not bool(base_version.get("ok", false)) \
		or not bool(revision.get("ok", false)) \
		or not bool(owner.get("ok", false)) \
		or not bool(development.get("ok", false)):
		return _failed_wire(PersistenceResultType.Code.CORRUPT_DATA)
	if int(base_version["value"]) < 0 \
		or int(revision["value"]) < 0 \
		or int(development["value"]) < 0:
		return _failed_wire(PersistenceResultType.Code.INVALID_REGION_DELTA)
	var terrain_value: Variant = wire.get("terrain_overrides", null)
	var added_value: Variant = wire.get("added_features", null)
	var removed_entries: Variant = wire.get("removed_feature_ids", null)
	if not terrain_value is Array or not added_value is Array or not removed_entries is Array:
		return _failed_wire(PersistenceResultType.Code.CORRUPT_DATA)
	var delta: RegionDelta = RegionDelta.new(
		world_cell["value"] as Vector2i,
		int(base_version["value"])
	)
	delta.revision = int(revision["value"])
	delta.owner_id = owner["value"] as String
	delta.development_level = int(development["value"])
	for terrain_entry_value: Variant in terrain_value as Array:
		if not terrain_entry_value is Dictionary:
			return _failed_wire(PersistenceResultType.Code.CORRUPT_DATA)
		var terrain_entry: Dictionary = terrain_entry_value as Dictionary
		var cell: Dictionary = _read_vector2i(terrain_entry.get("cell", null))
		var terrain_type: Dictionary = _read_int(terrain_entry.get("terrain_type", null))
		if not bool(cell.get("ok", false)) or not bool(terrain_type.get("ok", false)) \
			or not WorldCoordinates.is_valid_region_cell(cell["value"] as Vector2i) \
			or not TerrainType.is_valid(int(terrain_type["value"])) \
			or delta.terrain_overrides.has(cell["value"]):
			return _failed_wire(PersistenceResultType.Code.INVALID_REGION_DELTA)
		delta.terrain_overrides[cell["value"] as Vector2i] = int(terrain_type["value"])
	for feature_value: Variant in added_value as Array:
		if not feature_value is Dictionary:
			return _failed_wire(PersistenceResultType.Code.CORRUPT_DATA)
		var feature_wire: Dictionary = feature_value as Dictionary
		var feature_id: Dictionary = _read_string(feature_wire.get("feature_id", null))
		var feature_type: Dictionary = _read_string(feature_wire.get("feature_type", null))
		var feature_cell: Dictionary = _read_vector2i(feature_wire.get("cell", null))
		var payload: Dictionary = _decode_value(feature_wire.get("payload", null))
		if not bool(feature_id.get("ok", false)) \
			or not bool(feature_type.get("ok", false)) \
			or not bool(feature_cell.get("ok", false)) \
			or not bool(payload.get("ok", false)) \
			or (feature_id["value"] as String).is_empty() \
			or not WorldCoordinates.is_valid_region_cell(feature_cell["value"] as Vector2i) \
			or delta.added_features.has(feature_id["value"] as String) \
			or delta.removed_feature_ids.has(feature_id["value"] as String):
			return _failed_wire(PersistenceResultType.Code.INVALID_REGION_DELTA)
		delta.added_features[feature_id["value"] as String] = RegionFeatureDeltaType.new(
			feature_id["value"] as String,
			StringName(feature_type["value"] as String),
			feature_cell["value"] as Vector2i,
			payload["value"] as Dictionary
		)
	var removed_ids: Dictionary = {}
	for removed_entry: Variant in removed_entries as Array:
		if not removed_entry is String \
			or (removed_entry as String).is_empty() \
			or removed_ids.has(removed_entry as String):
			return _failed_wire(PersistenceResultType.Code.INVALID_REGION_DELTA)
		if delta.added_features.has(removed_entry as String):
			return _failed_wire(PersistenceResultType.Code.INVALID_REGION_DELTA)
		removed_ids[removed_entry as String] = true
	delta.removed_feature_ids = removed_ids
	return {"ok": true, "delta": delta}

func _validate_snapshot(snapshot: SessionSaveData, p_world_data: WorldData) -> int:
	if snapshot == null or snapshot.format_version != SessionSaveData.FORMAT_VERSION:
		return PersistenceResultType.Code.UNSUPPORTED_VERSION
	if snapshot.terrain_generation_version != RegionTerrainGenerator.GENERATION_VERSION \
		or snapshot.poi_generation_version != WorldPOIGenerator.GENERATION_VERSION \
		or snapshot.road_generation_version != WorldRoadGenerator.GENERATION_VERSION:
		return PersistenceResultType.Code.UNSUPPORTED_VERSION
	if snapshot.world_time_seconds < 0 or snapshot.party_id.is_empty() \
		or snapshot.party_base_walk_speed_kmh <= 0.0 \
		or not is_finite(snapshot.party_base_walk_speed_kmh):
		return PersistenceResultType.Code.INVALID_DATA
	if not _is_valid_world_cell(snapshot.party_global_cell, p_world_data):
		return PersistenceResultType.Code.INVALID_WORLD_POSITION
	var seen_regions: Dictionary = {}
	for entry: Dictionary in snapshot.regions:
		var world_cell: Vector2i = entry["world_cell"] as Vector2i
		var delta: RegionDelta = entry["delta"] as RegionDelta
		if seen_regions.has(world_cell) or delta == null or delta.world_cell != world_cell:
			return PersistenceResultType.Code.INVALID_REGION_DELTA
		if not _is_valid_world_cell(world_cell, p_world_data) \
			or delta.base_generation_version != RegionData.BASE_GENERATION_VERSION:
			return PersistenceResultType.Code.INVALID_REGION_DELTA
		seen_regions[world_cell] = true
	return PersistenceResultType.Code.NONE

func _restore_snapshot(snapshot: SessionSaveData) -> GameSession:
	var session: GameSession = GameSession.new()
	session.world_seed = snapshot.world_seed
	session.world_time_seconds = snapshot.world_time_seconds
	session.party.party_id = snapshot.party_id
	session.party.display_name = snapshot.party_display_name
	session.party.base_walk_speed_kmh = snapshot.party_base_walk_speed_kmh
	session.party.set_global_region_cell(snapshot.party_global_cell)
	session.party.initialized = snapshot.party_initialized
	session.selected_world_cell = session.party.get_world_cell()
	session.selected_region_cell = session.party.get_region_cell()
	for entry: Dictionary in snapshot.regions:
		var world_cell: Vector2i = entry["world_cell"] as Vector2i
		var state: RegionRuntimeState = session.get_region_runtime_state(world_cell)
		state.discovered = bool(entry.get("discovered", false))
		state.discovered_site_ids.clear()
		for site_id: String in entry.get("discovered_site_ids", []):
			state.discovered_site_ids[site_id] = true
		state.delta = (entry["delta"] as RegionDelta).copy()
	return session

func _is_valid_world_cell(global_cell: Vector2i, p_world_data: WorldData) -> bool:
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(global_cell)
	var world_cell: Vector2i = converted["world_cell"] as Vector2i
	if p_world_data != null:
		return p_world_data.is_valid_world_cell(world_cell)
	return world_cell.x >= 0 and world_cell.y >= 0 \
		and world_cell.x < WorldData.WORLD_CELLS.x \
		and world_cell.y < WorldData.WORLD_CELLS.y

func _vector_to_wire(value: Vector2i) -> Array:
	return [value.x, value.y]

func _vector_less(left: Vector2i, right: Vector2i) -> bool:
	if left.x != right.x:
		return left.x < right.x
	return left.y < right.y

func _failed_wire(reason: int) -> Dictionary:
	return {"ok": false, "reason": reason}

func _read_int(value: Variant) -> Dictionary:
	if value is int:
		return {"ok": true, "value": value}
	if value is float and is_finite(value as float):
		var converted: float = value as float
		var rounded: int = roundi(converted)
		if is_equal_approx(converted, float(rounded)):
			return {"ok": true, "value": rounded}
	return {"ok": false}

func _read_float(value: Variant) -> Dictionary:
	if value is int or value is float:
		var converted: float = float(value)
		return {"ok": true, "value": converted} if is_finite(converted) else {"ok": false}
	return {"ok": false}

func _read_string(value: Variant) -> Dictionary:
	return {"ok": true, "value": value} if value is String else {"ok": false}

func _read_vector2i(value: Variant) -> Dictionary:
	if not value is Array or (value as Array).size() != 2:
		return {"ok": false}
	var values: Array = value as Array
	var x: Dictionary = _read_int(values[0])
	var y: Dictionary = _read_int(values[1])
	if not bool(x.get("ok", false)) or not bool(y.get("ok", false)):
		return {"ok": false}
	return {"ok": true, "value": Vector2i(x["value"] as int, y["value"] as int)}

func _encode_value(value: Variant) -> Dictionary:
	if value == null or value is bool or value is int or value is String:
		return {"ok": true, "value": value}
	if value is float:
		return {"ok": true, "value": value} if is_finite(value as float) else {"ok": false}
	if value is StringName:
		return {"ok": true, "value": {"$type": "StringName", "value": str(value)}}
	if value is Vector2i:
		return {"ok": true, "value": {"$type": "Vector2i", "x": (value as Vector2i).x, "y": (value as Vector2i).y}}
	if value is Array:
		var encoded_array: Array = []
		for item: Variant in value as Array:
			var encoded_item: Dictionary = _encode_value(item)
			if not bool(encoded_item.get("ok", false)):
				return {"ok": false}
			encoded_array.append(encoded_item["value"])
		return {"ok": true, "value": encoded_array}
	if value is Dictionary:
		var entries: Array = []
		for key: Variant in (value as Dictionary).keys():
			var encoded_key: Dictionary = _encode_value(key)
			var encoded_value: Dictionary = _encode_value((value as Dictionary)[key])
			if not bool(encoded_key.get("ok", false)) or not bool(encoded_value.get("ok", false)):
				return {"ok": false}
			entries.append({"key": encoded_key["value"], "value": encoded_value["value"]})
		return {"ok": true, "value": {"$type": "Dictionary", "entries": entries}}
	return {"ok": false}

func _decode_value(value: Variant) -> Dictionary:
	if value == null or value is bool or value is int or value is float or value is String:
		return {"ok": true, "value": value}
	if value is Array:
		var decoded_array: Array = []
		for item: Variant in value as Array:
			var decoded_item: Dictionary = _decode_value(item)
			if not bool(decoded_item.get("ok", false)):
				return {"ok": false}
			decoded_array.append(decoded_item["value"])
		return {"ok": true, "value": decoded_array}
	if not value is Dictionary:
		return {"ok": false}
	var dictionary: Dictionary = value as Dictionary
	var marker: Variant = dictionary.get("$type", null)
	if marker == "Vector2i":
		var x: Dictionary = _read_int(dictionary.get("x", null))
		var y: Dictionary = _read_int(dictionary.get("y", null))
		if not bool(x.get("ok", false)) or not bool(y.get("ok", false)):
			return {"ok": false}
		return {"ok": true, "value": Vector2i(x["value"] as int, y["value"] as int)}
	if marker == "StringName":
		var name: Dictionary = _read_string(dictionary.get("value", null))
		return {"ok": true, "value": StringName(name["value"] as String)} if bool(name.get("ok", false)) else {"ok": false}
	if marker != "Dictionary":
		return {"ok": false}
	var entries: Variant = dictionary.get("entries", null)
	if not entries is Array:
		return {"ok": false}
	var decoded_dictionary: Dictionary = {}
	for entry_value: Variant in entries as Array:
		if not entry_value is Dictionary:
			return {"ok": false}
		var entry: Dictionary = entry_value as Dictionary
		var key: Dictionary = _decode_value(entry.get("key", null))
		var decoded_value: Dictionary = _decode_value(entry.get("value", null))
		if not bool(key.get("ok", false)) or not bool(decoded_value.get("ok", false)):
			return {"ok": false}
		decoded_dictionary[key["value"]] = decoded_value["value"]
	return {"ok": true, "value": decoded_dictionary}
