class_name RegionSaveSlot
extends RefCounted

# Save-slot metadata pins the immutable geography used by both visited and
# unvisited Sites. SiteStore remains the owner of mutable Site snapshots.
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
const GameplayClock = preload("res://scripts/region_lab/region_gameplay_clock.gd")
const RegionCheckpoint = preload("res://scripts/terrain_lab/site_region_checkpoint.gd")
const TechnologyPolicy = preload("res://scripts/terrain_lab/site_technology_policy.gd")
const EntryPolicy = preload("res://scripts/region_lab/region_entry.gd")

var source: RegionData
var pin: Dictionary = {}
var folder := ""
var control: Dictionary = {"logical_game_seconds": 0.0, "active_site_id": "", "fire_clock": {}}
# The original clock and sea initialization owners provide these candidates.
# This slot publishes snapshots; it never advances people or invents Actors.
var cold_site_advance: Callable
var ship_site_initialize: Callable
var _marker: Dictionary = {}
var _prepared: Dictionary = {}
var last_error: Dictionary = {}
var _control_scope := ""

static func fail(code: String, message: String = "") -> Dictionary:
	return {"ok": false, "code": code, "message": message if not message.is_empty() else code}

static func _safe_part(value: String) -> bool:
	if value.is_empty() or value.length() > 64:
		return false
	for i: int in range(value.length()):
		var character := value.unicode_at(i)
		if not ((character >= 48 and character <= 57) or (character >= 65 and character <= 90) \
				or (character >= 97 and character <= 122) or character == 45 or character == 95):
			return false
	return true

static func _whole(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) == floor(float(value)) and float(value) >= low and float(value) <= high

static func _new_fire_clock(base_game_seconds: float) -> Dictionary:
	return {"version": 1, "epoch": "fire_" + Crypto.new().generate_random_bytes(16).hex_encode(),
		"action_seconds": 0.0, "sequence": 0, "base_sequence": 0, "base_action_seconds": 0.0,
		"base_game_seconds": base_game_seconds, "journal": [], "index": {}}

func open_map(map_data: RegionData, world_instance_id: String, slot_id: String, prepare_new: bool = false, initial_context: Dictionary = {}) -> Dictionary:
	# Reject non-creation config before reading a world file or making folders.
	if not prepare_new and not initial_context.is_empty(): return fail("INVALID_INITIAL_SCENARIO")
	if prepare_new and not _initial_context_ok(initial_context): return fail("INVALID_INITIAL_SCENARIO")
	if map_data == null or map_data.manifest.is_empty(): return fail("MISSING_BASE", "尚未載入固定地圖")
	if not _safe_part(world_instance_id) or not _safe_part(slot_id): return fail("INVALID_SLOT")
	var empty_policy := TechnologyPolicy.new_policy([])
	if not empty_policy.ok: return empty_policy
	var expected := {"format": 2, "world_instance_id": world_instance_id, "slot_id": slot_id,
		"technology_policy": empty_policy.policy, "atlas_id": str(map_data.manifest.atlas_id),
		"grid_contract_version": int(map_data.manifest.grid_contract_version), "base_revision": str(map_data.manifest.base_revision),
		"manifest_sha256": map_data.manifest_hash, "ramp_rule_revision": RegionTerrainAdapter.RAMP_RULE_REVISION}
	if map_data.resource_manifest_hash.is_empty() != map_data.resource_rule_revision.is_empty(): return fail("MISSING_BASE")
	if not map_data.resource_manifest_hash.is_empty():
		expected["resource_layer_sha256"] = map_data.resource_manifest_hash
		expected["resource_rule_revision"] = map_data.resource_rule_revision
		if not Store._same_resource_pin(expected, expected): return fail("MISSING_BASE")
	var location := "user://region_lab/worlds/%s/slots/%s" % [world_instance_id, slot_id]
	var manifest_path := location.path_join("manifest.json")
	var pending_path := location.path_join("manifest.pending.json")
	var complete_path := location.path_join("manifest.initialized.json")
	var manifest_exists := FileAccess.file_exists(manifest_path)
	var pending_record := {}
	var recover_first_marker := false
	if manifest_exists:
		var file := FileAccess.open(manifest_path, FileAccess.READ)
		if file == null or file.get_length() > 4096: return fail("INVALID_SLOT")
		var recorded: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if not recorded is Dictionary or not _whole(recorded.get("format"), 1, 2): return fail("INVALID_SLOT")
		var policy := TechnologyPolicy.candidate(recorded, int(recorded.format) == 1)
		if not policy.ok: return policy
		var metadata := EntryPolicy.read_world(world_instance_id)
		if FileAccess.file_exists(EntryPolicy.world_path(world_instance_id)) and metadata.is_empty(): return fail("INVALID_SLOT")
		if not metadata.is_empty():
			var compared := TechnologyPolicy.same_candidate(metadata, recorded, int(metadata.version) == 1, int(recorded.format) == 1)
			if not compared.ok: return compared
		if not prepare_new:
			expected.format = int(recorded.format)
			if int(recorded.format) == 1 and not recorded.has("technology_policy"): expected.erase("technology_policy")
			else: expected.technology_policy = policy.policy
		if not _same_pin(recorded, expected): return fail("SAVE_VERSION", "原存檔地圖／固定政策不符")
		if prepare_new and (not FileAccess.file_exists(pending_path) or FileAccess.file_exists(complete_path)): return fail("CONFLICT", "此世界已完成建立，不能重生")
	if FileAccess.file_exists(pending_path):
		var pending_read := _read_document(pending_path, 16384)
		if not pending_read.ok: return pending_read
		if not _initial_pending_ok(pending_read.payload, expected): return fail("INITIAL_PIN_CONFLICT")
		pending_record = pending_read.payload
		if prepare_new and (pending_record.starting_site != initial_context.starting_site or pending_record.initial_scenario_id != initial_context.initial_scenario_id): return fail("INITIAL_SCENARIO_CONFLICT", "待提交的原開局選擇不可重選")
	elif not manifest_exists:
		# A valid same-pin pending write can be completed after a rename crash.
		if FileAccess.file_exists(pending_path + ".tmp"):
			var pending_read := _read_document(pending_path + ".tmp", 16384)
			if pending_read.ok and _initial_pending_ok(pending_read.get("payload"), expected):
				if prepare_new and (pending_read.payload.starting_site != initial_context.starting_site or pending_read.payload.initial_scenario_id != initial_context.initial_scenario_id): return fail("INITIAL_SCENARIO_CONFLICT")
				if DirAccess.rename_absolute(ProjectSettings.globalize_path(pending_path + ".tmp"), ProjectSettings.globalize_path(pending_path)) != OK: return fail("SAVE_IO")
				pending_record = pending_read.payload
			elif folder == location and _initial_pending_ok(_initialization, expected):
				# Only this original Slot may finish its own failed temporary write.
				pending_record = _initialization.duplicate(true)
			else: return fail("INVALID_SLOT")
		elif DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(location)):
			# Only this same original Slot's retained unpublished context, or a
			# genuine checked first marker below, can recover a partial folder.
			if folder == location and _initial_pending_ok(_initialization, expected): pending_record = _initialization.duplicate(true)
			elif FileAccess.file_exists(location.path_join("commits/%020d.json" % 1)): recover_first_marker = true
			else: return fail("INVALID_SLOT", "缺原同 pin 初始化證據；不覆寫資料")
		elif not prepare_new:
			# Preserve the original 3-argument empty-slot API. This old manifest
			# path never grants birth authority or manufactures pending metadata.
			var absolute := ProjectSettings.globalize_path(location)
			var made := DirAccess.make_dir_recursive_absolute(absolute)
			if made != OK: return fail("SAVE_IO", error_string(made))
			var temporary := ProjectSettings.globalize_path(manifest_path + ".tmp")
			var output := FileAccess.open(temporary, FileAccess.WRITE)
			if output == null: return fail("SAVE_IO", error_string(FileAccess.get_open_error()))
			output.store_string(JSON.stringify(expected, "\t"))
			output.flush()
			var error := output.get_error()
			output.close()
			if error != OK or DirAccess.rename_absolute(temporary, ProjectSettings.globalize_path(manifest_path)) != OK: return fail("SAVE_IO", "固定地圖版本記錄寫入失敗")
			manifest_exists = true
		if pending_record.is_empty() and folder == location and _initial_pending_ok(_initialization, expected):
			pending_record = _initialization.duplicate(true)
		if pending_record.is_empty() and prepare_new and not recover_first_marker:
			pending_record = {"version": 1, "pin": expected.duplicate(true), "starting_site": initial_context.starting_site.duplicate(), "initial_scenario_id": str(initial_context.initial_scenario_id)}
	if prepare_new and not pending_record.is_empty() and (pending_record.starting_site != initial_context.starting_site or pending_record.initial_scenario_id != initial_context.initial_scenario_id): return fail("INITIAL_SCENARIO_CONFLICT")
	source = map_data
	pin = expected
	folder = location
	_initialization = pending_record
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	if not manifest_exists and _initialization.is_empty():
		# Never treat an arbitrary partial directory as a new world. This path
		# can only restore a genuine first original marker, without birth.
		var derived := _derive_initial_context()
		if not derived.ok: return derived
		_initialization = derived.context
		if prepare_new and (_initialization.starting_site != initial_context.starting_site or _initialization.initial_scenario_id != initial_context.initial_scenario_id): return fail("INITIAL_SCENARIO_CONFLICT")
	if not _initialization.is_empty():
		if not FileAccess.file_exists(pending_path):
			var pending_written := _write_new_document(pending_path, _initialization)
			if not pending_written.ok: return pending_written
		if FileAccess.file_exists(complete_path):
			var completed := _read_document(complete_path, 16384)
			if not completed.ok or not _initial_complete_ok(completed.get("payload")): return fail("INVALID_INITIAL_RECEIPT")
			if prepare_new: return fail("CONFLICT", "此世界已完成建立")
			if not manifest_exists:
				var finalized := _finish_initial_manifest()
				if not finalized.ok: return finalized
			_initialization = {}
		elif not _marker.is_empty():
			var committed := _check_initial_record(_marker)
			if not committed.ok: return committed
			var finalized := _finish_initial_manifest()
			if not finalized.ok: return finalized
		elif not prepare_new:
			return fail("INITIALIZATION_PENDING", "原開局尚無已提交世代，請接續同一建立請求")
	return {"ok": true, "path": manifest_path, "initialization_pending": initialization_pending(), "initialization_committed": not _marker.is_empty()}

static func _same_pin(left: Variant, right: Dictionary) -> bool:
	if not left is Dictionary or left.size() != right.size():
		return false
	for key: String in ["world_instance_id", "slot_id", "atlas_id", "base_revision", "manifest_sha256", "ramp_rule_revision"]:
		if left.get(key) != right.get(key):
			return false
	if not Store._same_resource_pin(left, right):
		return false
	if not _whole(left.get("format"), 1, 2) or not _whole(right.get("format"), 1, 2) or int(left.format) != int(right.format): return false
	var policy: Dictionary = TechnologyPolicy.same_candidate(left, right, int(left.format) == 1, int(right.format) == 1)
	return policy.ok \
		and _whole(left.get("grid_contract_version"), 1, 1000) \
		and int(left.grid_contract_version) == int(right.grid_contract_version)

func _matches_base(base: Dictionary, site: Vector2i) -> bool:
	return not pin.is_empty() and source != null and source.manifest_hash == str(pin.manifest_sha256) \
		and source.resource_manifest_hash == str(pin.get("resource_layer_sha256", "")) \
		and source.resource_rule_revision == str(pin.get("resource_rule_revision", "")) \
		and Store._same_resource_pin(base, pin) and Store._same_resource_pin(base, base, true) \
		and base.get("base_kind") == "fixed_geography" \
		and base.get("atlas_id") == pin.atlas_id \
		and _whole(base.get("grid_contract_version"), 1, 1000) \
		and int(base.grid_contract_version) == int(pin.grid_contract_version) \
		and base.get("base_revision") == pin.base_revision \
		and base.get("manifest_sha256") == pin.manifest_sha256 \
		and base.get("ramp_rule_revision") == pin.get("ramp_rule_revision") \
		and base.get("site_id") == Grid.site_id(str(pin.atlas_id), site) \
		and base.get("site") is Array and base.site.size() == 2 \
		and _whole(base.site[0], -10000000, 10000000) \
		and _whole(base.site[1], -10000000, 10000000) \
		and int(base.site[0]) == site.x and int(base.site[1]) == site.y

func site_path(site: Vector2i) -> String:
	var entry: Dictionary = _marker.get("sites", {}).get(_site_key(site), {})
	if not entry.is_empty(): return folder.path_join(str(entry.path))
	return folder.path_join("sites/%d/%d.json" % [site.x, site.y])

func open_site(site: Vector2i) -> Dictionary:
	if pin.is_empty() or source == null:
		return fail("INVALID_SLOT", "存檔尚未開啟")
	var path := site_path(site)
	if FileAccess.file_exists(path):
		var loaded: Dictionary = Store.load_site(path, func(saved_base: Dictionary) -> Dictionary:
			if not _matches_base(saved_base, site):
				return fail("SAVE_VERSION", "存檔的固定地圖版本不符")
			var rebuilt: Dictionary = source.make_terrain_data(site.x, site.y)
			if not bool(rebuilt.get("ok", false)) or not _matches_base(rebuilt.get("base", {}), site) \
					or str(rebuilt.base.terrain_fingerprint) != str(saved_base.get("terrain_fingerprint", "")):
				return fail("SAVE_VERSION", "原固定地圖資料不可用")
			return rebuilt
		, 1, true)
		if not bool(loaded.get("ok", false)):
			return loaded
		var policy_guard := _admit_world_pin(loaded.data)
		if not policy_guard.ok: return policy_guard
		var loaded_boundary := _refresh_boundaries(loaded.data, site)
		if not loaded_boundary.ok: return loaded_boundary
		if _marker.is_empty(): return loaded
		if loaded.data.site.has("fire_settlement"):
			var fire_settlement := validate_fire_settlement(loaded.data.site, control.fire_clock)
			if not fire_settlement.ok: return fire_settlement
		if loaded.data.site.has("region_snapshot"):
			var hot: Dictionary = Store.validate_region_snapshot(loaded.data, {})
			if not hot.ok: return hot
			if not bool(hot.context.effects_complete) or str(hot.context.mode) in ["materializing", "dematerializing", "committed-unbound"]:
				if absf(float(hot.context.game_seconds) - float(control.logical_game_seconds)) > 0.00000001:
					return fail("REGION_RECOVERY_REQUIRED", "內部端點須先由已提交原 owner 接續")
				loaded["region_commit"] = region_bind_proof(loaded.data)
				return loaded
		var settled := _settle_cold_candidate(loaded.data, float(control.logical_game_seconds))
		if not settled.ok: return settled
		loaded.data = settled.data
		return loaded
	var fresh: Dictionary = source.make_terrain_data(site.x, site.y)
	if not bool(fresh.get("ok", false)):
		return fresh
	if not _matches_base(fresh.base, site):
		return fail("SAVE_VERSION", "固定地圖版本已變更")
	var data: TerrainData = fresh.data
	if not Store._resource_base_matches(data, fresh.base):
		return fail("SAVE_VERSION", "固定資源內容與來源版本不同")
	var refreshed := _refresh_boundaries(data, site)
	if not refreshed.ok:
		return refreshed
	if not data.is_walkable(data.spawn_cell):
		return {"ok": true, "data": data, "interactive": false, "message": "此地點僅能檢視地形"}
	Env.initialize(data, str(fresh.base.site_id))
	data.site.world_pin = pin.duplicate(true)
	var genesis := _settle_cold_candidate(data, float(control.logical_game_seconds))
	if not genesis.ok: return genesis
	data = genesis.data
	if not _fire_history_empty(data.site): return fail("INVALID_NEW_SITE", "新地點已存在原火攻歷史")
	data.site.fire_settlement = {"version": 1, "epoch": str(control.fire_clock.epoch), "sequence": int(control.fire_clock.sequence),
		"action_seconds": float(control.fire_clock.action_seconds), "game_seconds": float(control.logical_game_seconds)}
	return {"ok": true, "data": data, "interactive": true, "created": true}

func save_site(data: TerrainData) -> Dictionary:
	if pin.is_empty() or data == null or data.site.is_empty():
		return fail("NO_TARGET", "沒有可保存的陸地地點")
	var base: Variant = data.parameters.get("fixed_base")
	if not base is Dictionary or not base.get("site") is Array or base.site.size() != 2:
		return fail("SAVE_VERSION", "缺少固定地圖基底識別")
	var site := Vector2i(int(base.site[0]), int(base.site[1]))
	if not _matches_base(base, site) or str(data.site.get("id", "")) != str(base.site_id):
		return fail("SAVE_VERSION", "保存位置與地圖版本不同")
	var refreshed := _refresh_boundaries(data, site)
	if not refreshed.ok:
		return refreshed
	if _marker.is_empty() and str(control.active_site_id).is_empty() and not data.site.has(SETTLEMENT_FIELD):
		return Store.save(data, site_path(site)) # Existing single-Site slots retain their old paths.
	var settlement := validate_settlement(data.site, control.logical_game_seconds)
	if not settlement.ok: return settlement
	if not settlement.legacy and float(settlement.pending) > 0.00001: return fail("UNSETTLED_SITE", "地點尚有原時鐘補算債，未提交保存")
	if data.site.has("fire_settlement"):
		var fire_settlement := validate_fire_settlement(data.site, control.fire_clock)
		if not fire_settlement.ok: return fire_settlement
	var generation := int(_marker.get("generation", 0)) + 1
	var path := _generation_path(generation, site)
	var saved := _save_checked(data, site, path)
	if not saved.ok: return saved
	var sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	sites[_site_key(site)] = _file_entry(path)
	var next_control := control.duplicate(true)
	if str(next_control.active_site_id).is_empty(): next_control.active_site_id = str(data.site.id)
	if data.site.has("fire_settlement"):
		var fire_settlement: Dictionary = data.site.fire_settlement
		var fire_clock: Dictionary = next_control.fire_clock
		var prior_fire_active := bool(fire_clock.get("index", {}).get(str(data.site.id), {}).get("fire_active", false))
		var fire_active := bool(data.get_meta(&"region_fire_active", Runtime.fire_active(data))) \
			or prior_fire_active and float(data.site.get("combat_left", 0.0)) > 0.0
		fire_clock.index[str(data.site.id)] = {"coordinate": [site.x, site.y],
			"active": str(next_control.active_site_id) == str(data.site.id), "fire_active": fire_active,
			"sequence": int(fire_settlement.sequence), "action_seconds": float(fire_settlement.action_seconds),
			"game_seconds": float(fire_settlement.game_seconds)}
	# A cold result and the active snapshot share ONE generation/clock marker.
	# In particular, a BUSY active save cannot first commit a newer cold epoch.
	var pending_cold := _collect_cold_checkpoint(generation, sites, next_control)
	if not pending_cold.ok: return pending_cold
	var published := _publish(sites, next_control, str(_marker.get("transfer_token", "")), _marker.get("journey", {}))
	if published.ok:
		for identity: String in pending_cold.identities: _fire_cold_candidates.erase(identity)
	return saved if published.ok else published

func _refresh_boundaries(data: TerrainData, site: Vector2i, live_neighbour: TerrainData = null, live_site: Vector2i = Vector2i.ZERO) -> Dictionary:
	var cached_deltas: Dictionary = {}
	return source.refresh_boundary(data, site, func(neighbour_site: Vector2i, neighbour_cell: Vector2i) -> Dictionary:
		var center: Dictionary = Grid.cell_center_mm(neighbour_site, neighbour_cell)
		var sample: Dictionary = source.sample_meters(float(center.easting_mm) / 1000.0,
			float(center.northing_mm) / 1000.0)
		if not bool(sample.get("ok", false)):
			return sample
		# A detached preflight may supply the actual other side before its save.
		# Natural edges stay natural; effective walls are compared after rebuild.
		if live_neighbour != null and neighbour_site == live_site:
			if not live_neighbour.contains(neighbour_cell): return fail("INVALID_SITE", "跨界鄰格非法")
			var live_index := live_neighbour.index(neighbour_cell)
			sample.level = int(live_neighbour.height_levels[live_index])
			sample.water_kind = int(live_neighbour.water_kind[live_index])
			return sample
		var key := "%d:%d" % [neighbour_site.x, neighbour_site.y]
		if not cached_deltas.has(key):
			var neighbour_path := site_path(neighbour_site)
			if FileAccess.file_exists(neighbour_path):
				var saved: Dictionary = Store.read_fixed_terrain_changes(neighbour_path)
				if not bool(saved.get("ok", false)):
					return saved
				if not _matches_base(saved.base, neighbour_site):
					return fail("SAVE_VERSION", "相鄰 Site 使用另一版地形，原存檔保留")
				cached_deltas[key] = saved.changes
			else:
				cached_deltas[key] = {}
		var index := neighbour_cell.y * 100 + neighbour_cell.x
		var changes: Dictionary = cached_deltas[key]
		if changes.has(str(index)):
			sample.level = int(changes[str(index)])
		return sample
	)

static func _site_key(site: Vector2i) -> String:
	return "%d:%d" % [site.x, site.y]

static func _site_seconds(data: TerrainData) -> float:
	return (float(data.site.get("minute", 0)) + float(data.site.get("phase", 0.0))) * 60.0

func _coordinate(data: TerrainData) -> Dictionary:
	if data == null or not data.parameters.get("fixed_base") is Dictionary:
		return fail("SAVE_VERSION", "旅程必須沿原固定地圖存檔槽")
	var base: Dictionary = data.parameters.fixed_base
	if not base.get("site") is Array or base.site.size() != 2 \
			or not _whole(base.site[0], -10000000, 10000000) or not _whole(base.site[1], -10000000, 10000000):
		return fail("SAVE_VERSION", "旅程來源位置非法")
	var site := Vector2i(int(base.site[0]), int(base.site[1]))
	if not _matches_base(base, site) or str(data.site.get("id", "")) != str(base.site_id):
		return fail("SAVE_VERSION", "旅程來源與原存檔槽版本不同")
	var policy_guard := _admit_world_pin(data)
	if not policy_guard.ok: return policy_guard
	return {"ok": true, "site": site}

func _load_checked(path: String, site: Vector2i) -> Dictionary:
	var loaded := Store.load_site(path, func(base: Dictionary) -> Dictionary:
		if not _matches_base(base, site): return fail("SAVE_VERSION", "提交候選使用另一固定地圖")
		var rebuilt: Dictionary = source.make_terrain_data(site.x, site.y)
		if not bool(rebuilt.get("ok", false)) or not _matches_base(rebuilt.get("base", {}), site) \
				or str(rebuilt.base.terrain_fingerprint) != str(base.get("terrain_fingerprint", "")):
			return fail("SAVE_VERSION", "提交候選的固定來源不可重建")
		return rebuilt, 1, true)
	if not loaded.ok: return loaded
	var policy_guard := _admit_world_pin(loaded.data)
	return loaded if policy_guard.ok else policy_guard

func _save_checked(data: TerrainData, site: Vector2i, path: String) -> Dictionary:
	var coordinate := _coordinate(data)
	if not coordinate.ok or coordinate.site != site: return coordinate if not coordinate.ok else fail("SAVE_VERSION", "候選位置不符")
	var original := _region_bound_original_lab(data)
	var saved: Dictionary
	if original != null:
		var effects_complete := original._region_point_pending.is_empty() and not original._region_point_consuming and pending_region_events().is_empty()
		var capture: Dictionary = original.site_controller.capture_region_checkpoint("region_checkpoint" if effects_complete else "region_barrier",
			effects_complete, original._region_point_pending)
		if not capture.ok: return capture
		saved = Store.save_region_snapshot(data, path, capture.context, capture.owners)
	elif data.site.has("region_snapshot"):
		var captured := Store.validate_region_snapshot(data, {})
		if not captured.ok: return captured
		saved = Store.save_region_snapshot(data, path, captured.context, captured.owners)
	else:
		saved = Store.save(data, path)
	if not saved.ok: return saved
	var readback := _load_checked(path, site)
	if not readback.ok: return readback
	return {"ok": true, "path": path, "data": readback.data}

func _file_entry(path: String) -> Dictionary:
	return {"path": path.trim_prefix(folder + "/"), "sha256": FileAccess.get_sha256(path)}

func _generation_path(generation: int, site: Vector2i) -> String:
	return folder.path_join("generations/%020d_%d_%d_%d.json" % [generation, site.x, site.y, Time.get_ticks_usec()])

func _read_document(path: String, maximum: int = 1048576) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > maximum: return fail("SAVE_IO", "存檔槽記錄無法讀取")
	var envelope: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not envelope is Dictionary or envelope.size() != 2 or not envelope.get("payload") is String \
			or not envelope.get("checksum") is String or str(envelope.payload).sha256_text() != str(envelope.checksum):
		return fail("CORRUPT_SAVE", "存檔槽記錄校驗失敗，原代保留")
	var payload: Variant = JSON.parse_string(envelope.payload)
	return {"ok": true, "payload": payload} if payload is Dictionary else fail("CORRUPT_SAVE", "存檔槽記錄格式")

func _write_new_document(path: String, payload: Dictionary) -> Dictionary:
	if FileAccess.file_exists(path): return fail("SAVE_IO", "提交記錄已存在，拒絕覆寫")
	var absolute := ProjectSettings.globalize_path(path)
	var made := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if made != OK: return fail("SAVE_IO", error_string(made))
	var body := JSON.stringify(payload, "", true, true)
	var envelope := JSON.stringify({"payload": body, "checksum": body.sha256_text()}, "\t")
	var temporary := absolute + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return fail("SAVE_IO", error_string(FileAccess.get_open_error()))
	file.store_string(envelope)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or FileAccess.get_file_as_string(temporary) != envelope:
		return fail("SAVE_IO", "提交記錄尚未完整寫入，未發布")
	var renamed := DirAccess.rename_absolute(temporary, absolute)
	return {"ok": true} if renamed == OK else fail("SAVE_IO", error_string(renamed))

func _recover_control() -> Dictionary:
	# Reading a bad latest commit must not erase the live owner's clock/job.
	# Keep exact original objects; strict file validation still returns its error.
	var previous_control: Dictionary = control
	var previous_marker: Dictionary = _marker
	var previous_scope: String = _control_scope
	var result: Dictionary = _recover_control_from_files()
	if not result.ok:
		control = previous_control
		_marker = previous_marker
		_control_scope = previous_scope
	return result

func _recover_control_from_files() -> Dictionary:
	var live_control: Dictionary = control
	var live_marker := _marker.duplicate(true)
	var preserve_live := _control_scope == folder
	_marker = {}
	control = {"logical_game_seconds": 0.0, "active_site_id": "", "fire_clock": _new_fire_clock(0.0)}
	_control_scope = folder
	var commits := DirAccess.open(folder.path_join("commits"))
	if commits == null:
		if preserve_live: control = live_control
		if not control.has("fire_clock"): control.fire_clock = _new_fire_clock(float(control.logical_game_seconds))
		return {"ok": true}
	var files: Array[String] = []
	for name: String in commits.get_files():
		if name.ends_with(".json") and name.trim_suffix(".json").length() == 20 and name.trim_suffix(".json").is_valid_int(): files.append(name)
	if files.is_empty():
		if preserve_live: control = live_control
		if not control.has("fire_clock"): control.fire_clock = _new_fire_clock(float(control.logical_game_seconds))
		return {"ok": true}
	files.sort()
	# A fully renamed marker is a commit. Corruption of its selected generation
	# is an error; falling back would resurrect ownership from an older Site.
	var latest := _read_document(folder.path_join("commits").path_join(files.back()))
	if not latest.ok: return latest
	var recorded: Dictionary = latest.payload
	if recorded.size() != 7 or not _whole(recorded.get("format"), 1, 1) \
			or not _whole(recorded.get("generation"), 1, 2147483647) or not _same_pin(recorded.get("pin"), pin) \
			or int(recorded.generation) != int(files.back().trim_suffix(".json")) \
			or not recorded.get("sites") is Dictionary or not recorded.get("transfer_token") is String \
			or not recorded.get("journey") is Dictionary or not recorded.get("control") is Dictionary:
		return fail("CORRUPT_SAVE", "存檔槽提交版本／來源／欄位")
	var clock: Dictionary = recorded.control
	if clock.size() not in [2, 3, 4] or clock.size() == 4 and not clock.has("region_gameplay") or not clock.get("active_site_id") is String \
			or not clock.get("logical_game_seconds") is float and not clock.get("logical_game_seconds") is int \
			or not is_finite(float(clock.logical_game_seconds)) or float(clock.logical_game_seconds) < 0.0:
		return fail("CORRUPT_SAVE", "存檔槽唯一遊戲時鐘／活動地點")
	if clock.size() == 2: clock.fire_clock = _new_fire_clock(float(clock.logical_game_seconds))
	if not clock.get("fire_clock") is Dictionary:
		return fail("CORRUPT_SAVE", "存檔槽火攻時鐘欄位")
	if clock.has("region_gameplay"):
		var gameplay_check := GameplayClock.validate_registry(clock.region_gameplay, float(clock.logical_game_seconds))
		if not gameplay_check.ok: return gameplay_check
	var fire_clock_check := validate_fire_clock(clock.fire_clock, clock.logical_game_seconds)
	if not fire_clock_check.ok: return fire_clock_check
	var active_found: bool = str(clock.active_site_id).is_empty()
	for key: Variant in recorded.sites:
		var components: PackedStringArray = str(key).split(":")
		var entry: Variant = recorded.sites[key]
		if not key is String or components.size() != 2 or not components[0].is_valid_int() or not components[1].is_valid_int() \
				or not entry is Dictionary or entry.size() != 2 or not entry.get("path") is String or not entry.get("sha256") is String:
			return fail("CORRUPT_SAVE", "提交地點／檔案欄位")
		var relative := str(entry.path)
		if not relative.begins_with("generations/") or not relative.ends_with(".json") or relative.contains("..") or relative.contains("\\") \
				or relative.split("/").size() != 2 or str(entry.sha256).length() != 64 \
				or FileAccess.get_sha256(folder.path_join(relative)) != str(entry.sha256):
			return fail("CORRUPT_SAVE", "提交地點檔案缺失／變更，拒絕重播舊移交")
		var coordinate := Vector2i(int(components[0]), int(components[1]))
		if _site_key(coordinate) != key: return fail("CORRUPT_SAVE", "提交地點坐標不是唯一格式")
		active_found = active_found or str(clock.active_site_id) == Grid.site_id(str(pin.atlas_id), coordinate)
	if not active_found: return fail("CORRUPT_SAVE", "活動地點未包含在同代提交")
	var journey: Dictionary = recorded.journey
	var normalized := _normalize_journey(journey)
	if not normalized.ok: return normalized
	recorded.journey = normalized.journey
	_marker = recorded
	control = clock.duplicate(true)
	if not preserve_live and control.has("region_gameplay"):
		# A persisted activation records history, not a bind in this process.
		for value: Dictionary in control.region_gameplay.modes.values(): value.activation = {}
	if preserve_live and float(live_control.logical_game_seconds) > float(control.logical_game_seconds):
		control = live_control
	elif preserve_live and int(live_marker.get("generation", -1)) == int(recorded.generation):
		control = live_control
	return {"ok": true}

static func _normalize_journey(value: Dictionary) -> Dictionary:
	if value.is_empty(): return {"ok": true, "journey": {}}
	if str(value.get("kind", "")) == RegionTravel.KIND: return _normalize_travel_journey(value)
	if value.size() == 2 and value.get("token") is String and _safe_part(str(value.token)) and _seconds(value.get("elapsed_action_seconds")):
		return {"ok": true, "journey": {"version": 1, "token": str(value.token), "phase": "outbound", "elapsed_action_seconds": float(value.elapsed_action_seconds), "return_required_action_seconds": 0.0, "return_elapsed_action_seconds": 0.0}}
	const FIELDS := ["version", "token", "phase", "elapsed_action_seconds", "return_required_action_seconds", "return_elapsed_action_seconds"]
	if value.size() != FIELDS.size() or not _whole(value.get("version"), 1, 1) or not value.get("token") is String or not _safe_part(str(value.token)) or value.get("phase") not in ["outbound", "return"]:
		return fail("CORRUPT_SAVE", "原旅程版本／phase／ACTION 欄位非法")
	for field: String in FIELDS.slice(3):
		if not _seconds(value.get(field)): return fail("CORRUPT_SAVE", "原旅程 ACTION 秒數非法")
	if str(value.phase) == "outbound" and (float(value.return_required_action_seconds) != 0.0 or float(value.return_elapsed_action_seconds) != 0.0) \
		or str(value.phase) == "return" and (float(value.return_required_action_seconds) != float(value.elapsed_action_seconds) or float(value.return_elapsed_action_seconds) > float(value.return_required_action_seconds) + 0.000001):
		return fail("CORRUPT_SAVE", "返航距離必須等於已航原 ACTION，不能縮短或超前")
	return {"ok": true, "journey": value.duplicate(true)}

func _publish(sites: Dictionary, clock: Dictionary, transfer_token: String = "", journey: Dictionary = {}) -> Dictionary:
	var expected := int(_marker.get("generation", 0))
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	if int(_marker.get("generation", 0)) != expected: return fail("CONFLICT", "存檔槽已有新提交，未發布舊候選")
	if float(clock.logical_game_seconds) < float(control.logical_game_seconds) - 0.00001:
		return fail("TIME_MISMATCH", "同一世界遊戲時鐘不可倒退")
	var next_clock := clock.duplicate(true)
	# Older transfer callers supply just the clock/active ID. Carry the original
	# registry instead of dropping NPC owners and pending player barriers.
	if not next_clock.has("region_gameplay") and control.has("region_gameplay"):
		next_clock.region_gameplay = control.region_gameplay.duplicate(true)
	if next_clock.has("region_gameplay"):
		var gameplay_check := GameplayClock.validate_registry(next_clock.region_gameplay, float(next_clock.logical_game_seconds))
		if not gameplay_check.ok: return gameplay_check
	if not next_clock.has("fire_clock"): next_clock.fire_clock = control.fire_clock.duplicate(true)
	if not next_clock.fire_clock.has("base_sequence") and not next_clock.fire_clock.has("base_action_seconds"):
		next_clock.fire_clock.base_sequence = 0
		next_clock.fire_clock.base_action_seconds = 0.0
	var fire_clock_check := validate_fire_clock(next_clock.get("fire_clock"), next_clock.get("logical_game_seconds"))
	if not fire_clock_check.ok: return fire_clock_check
	var next_fire_clock: Dictionary = next_clock.fire_clock
	var previous_active := str(control.get("active_site_id", ""))
	var next_active := str(next_clock.get("active_site_id", ""))
	if previous_active != next_active:
		if next_fire_clock.get("index", {}).has(previous_active): next_fire_clock.index[previous_active].active = false
		if next_fire_clock.get("index", {}).has(next_active): next_fire_clock.index[next_active].active = true
	var generation := expected + 1
	if next_clock.has("region_gameplay"):
		for value: Dictionary in next_clock.region_gameplay.modes.values():
			value.generation = generation
			if not value.activation.is_empty(): value.activation.generation = generation
	var record := {"format": 1, "generation": generation, "pin": pin.duplicate(true), "sites": sites.duplicate(true),
		"control": next_clock.duplicate(true), "transfer_token": transfer_token, "journey": journey.duplicate(true)}
	if initialization_pending() and expected == 0:
		var initial_guard := _check_initial_record(record)
		if not initial_guard.ok: return initial_guard
	var committed := _write_new_document(folder.path_join("commits/%020d.json" % generation), record)
	if not committed.ok: return committed
	_marker = record
	control = next_clock
	if initialization_pending() and generation == 1:
		var manifested := _finish_initial_manifest()
		if not manifested.ok:
			manifested.committed = true
			manifested.generation = 1
			return manifested
	return {"ok": true, "generation": generation}

func advance_world_time(delta: float) -> float:
	if not is_finite(delta) or delta < 0.0:
		last_error = fail("INVALID_TIME", "遊戲時鐘增量非法")
		return -1.0
	var next := float(control.logical_game_seconds) + delta
	if not is_finite(next) or delta > 0.0 and next <= float(control.logical_game_seconds):
		last_error = fail("INVALID_TIME", "遊戲時鐘超出可表示範圍")
		return -1.0
	control.logical_game_seconds = next
	return float(control.logical_game_seconds)

func _settle_cold_candidate(data: TerrainData, target_seconds: float) -> Dictionary:
	var fire_guard := Store.fire_event_guard(data)
	if not fire_guard.ok: return fire_guard
	if data.site.is_empty(): return {"ok": true, "data": data}
	# A completed bound original must keep its actual body/item capture owner.
	# A derived copy cannot stand in for that owner even at the same GAME time.
	var original := _region_bound_original_lab(data)
	if original != null and original.region_bind_receipt(data).get("complete") == true:
		var completed_original := validate_settlement(data.site, target_seconds)
		if not completed_original.ok: return completed_original
		if not completed_original.legacy and float(completed_original.pending) <= 0.00001:
			return {"ok": true, "data": data}
	var copy := Env.navigation_for_state(data, data.site.duplicate(true))
	var empty: bool = copy.site.get("actors", {}).is_empty() and copy.site.get("armies", []).is_empty() \
		and copy.site.get("features", {}).is_empty() and copy.site.get("person_supply", {}).is_empty() \
		and copy.site.get("team_supply", {}).is_empty() and str(copy.site.get("worker", {}).get("target", "")).is_empty()
	if empty and not copy.site.has(SETTLEMENT_FIELD):
		# No resident, food history or production exists before this first attach.
		copy.site.minute = floori(target_seconds / 60.0)
		copy.site.phase = target_seconds / 60.0 - float(copy.site.minute)
	var window := replay_window(copy.site, target_seconds)
	if not window.ok: return window
	if float(window.pending) <= 0.00001: return {"ok": true, "data": copy}
	if cold_site_advance.is_valid():
		var settled: Variant = cold_site_advance.call(copy, target_seconds)
		if not settled is Dictionary or not bool(settled.get("ok", false)) or not settled.get("data") is TerrainData:
			return settled if settled is Dictionary else fail("TIME_MISMATCH", "原冷地點時鐘候選未完成")
		var completed := validate_settlement(settled.data.site, target_seconds)
		if not completed.ok or float(completed.pending) > 0.00001: return fail("UNSETTLED_SITE", "原冷地點候選尚有補算債")
		return settled
	return fail("UNSETTLED_SITE", "冷地點須由原 shared step 補算；存檔槽不假推時間")

func _ship_destination(site: Vector2i, seconds: float) -> Dictionary:
	var opened := open_site(site)
	if not opened.ok: return opened
	var data: TerrainData = opened.data
	if bool(opened.get("created", false)):
		# A fresh travel destination has no original resident Actor. Explicit
		# new-world initialization still uses open_site's standard starter path.
		data.site.actor_presence_version = 1
		data.site.actors = {}
	if data.site.is_empty():
		var initialized: Variant = ship_site_initialize.call(data) if ship_site_initialize.is_valid() \
			else Env.initialize_marine(data, str(data.parameters.fixed_base.site_id))
		if not initialized is Dictionary or not bool(initialized.get("ok", false)):
			return initialized if initialized is Dictionary else fail("NO_TARGET", "原海洋地點初始化未完成")
		if initialized.has("data"):
			if not initialized.data is TerrainData: return fail("NO_TARGET", "原海洋候選不是 TerrainData")
			data = initialized.data
	return _settle_cold_candidate(data, seconds)

static func _people(state: Dictionary) -> Dictionary:
	var result := {}
	for actor: Dictionary in state.get("actors", {}).values(): result[int(actor.person_id)] = true
	for army: Dictionary in state.get("armies", []):
		for row: Dictionary in army.get("units", []): result[int(row.person_id)] = true
	return result

static func _rotate_offset(offset: Vector2i, from_facing: Vector2i, to_facing: Vector2i) -> Vector2i:
	var old_right := Vector2i(-from_facing.y, from_facing.x)
	var new_right := Vector2i(-to_facing.y, to_facing.x)
	return new_right * (offset.x * old_right.x + offset.y * old_right.y) \
		+ to_facing * (offset.x * from_facing.x + offset.y * from_facing.y)

func _transfer_pair(source_data: TerrainData, destination_data: TerrainData, boat_ids: Array[String],
		anchor: Vector2i, facing: Vector2i, destination_path: String, transfer_token: String) -> Dictionary:
	if boat_ids.is_empty() or not Ship.valid_facing(facing) or not _safe_part(transfer_token): return fail("INVALID", "船隊／目的朝向／原 token 非法")
	if not is_equal_approx(_site_seconds(source_data), _site_seconds(destination_data)):
		return fail("TIME_MISMATCH", "原供養 epoch 不同，不能重定餐份時間")
	var origin: Dictionary = source_data.site.duplicate(true)
	var captured := _capture_transfer_fire_snapshots(source_data, origin)
	if not captured.ok: return captured
	var selected := {}
	var teams: Array[int] = []
	var slowest := INF
	for identity: String in boat_ids:
		var boat: Dictionary = origin.get("vehicles", {}).get(identity, {})
		if selected.has(identity) or boat.get("kind") != "ship" or int(boat.get("team_id", 0)) <= 0:
			return fail("INVALID", "原選定船隊須唯一且有原隊 owner")
		if not boat.get("move", {}).is_empty() or not boat.get("command", {}).is_empty() or bool(boat.get("stop_pending", false)):
			return fail("BUSY", "原船隊尚有未完 movement／command")
		selected[identity] = true
		if not teams.has(int(boat.team_id)): teams.append(int(boat.team_id))
		var metrics := RegionTravel.ship_metrics(origin, boat)
		if float(metrics.speed) <= 0.0: return fail("CREW", "原船缺有效掌舵人／最低船員或超載")
		slowest = minf(slowest, float(metrics.speed))
	var controlled := int(origin.get("controlled_person_id", -1))
	var bodies := RegionTravel._body_records(origin)
	if not bodies.has(controlled) or not selected.has(str(bodies[controlled].get("embarked_vehicle_id", ""))):
		return fail("PLAYER_CONTROL", "玩家原船旅程須帶原受控身體；NPC派遣沿原NPC旅隊出口")
	var actor_key := ""
	for key: String in origin.get("actors", {}):
		if int(origin.actors[key].person_id) == controlled: actor_key = key
	var spec := {"person_id": controlled, "actor_key": actor_key, "team_id": teams[0], "team_ids": teams,
		"controller": "player", "mode": "sea", "game_seconds": float(control.logical_game_seconds),
		"family_transfer_guard": region_family_transfer_guard}
	var extracted := RegionTravel.extract(origin, spec, transfer_token)
	if not extracted.ok: return extracted
	if extracted.party.vehicle_ids.size() != boat_ids.size(): return fail("PARTIAL_FLEET", "真原隊仍有未選定船，不拆船隊 owner")
	for identity: String in extracted.party.vehicle_ids:
		if not selected.has(identity): return fail("PARTIAL_FLEET", "原隊的每艘船須同一選定閉包")
	var first: Dictionary = origin.vehicles[boat_ids[0]]
	var old_anchor := source_data.cell_from_index(int(first.cell))
	var old_facing := Vector2i(int(first.facing[0]), int(first.facing[1]))
	var poses := {}
	for identity: String in boat_ids:
		var boat: Dictionary = origin.vehicles[identity]
		var at := anchor + _rotate_offset(source_data.cell_from_index(int(boat.cell)) - old_anchor, old_facing, facing)
		var direction := _rotate_offset(Vector2i(int(boat.facing[0]), int(boat.facing[1])), old_facing, facing)
		poses[identity] = {"anchor": [at.x, at.y], "facing": [direction.x, direction.y]}
	var navigation := Env.navigation_for_state(destination_data, destination_data.site)
	var inserted := RegionTravel.insert(destination_data.site, extracted.party, navigation, anchor, destination_path,
		float(control.logical_game_seconds), float(control.logical_game_seconds),
		{"generation": int(_marker.get("generation", 0)) + 1, "family_transfer_guard": region_family_transfer_guard, "vehicle_poses": poses})
	if not inserted.ok: return inserted
	var source_candidate := Env.navigation_for_state(source_data, extracted.origin)
	var destination_candidate := Env.navigation_for_state(destination_data, inserted.state)
	source_candidate.set_meta(&"region_bind_source", source_data)
	destination_candidate.set_meta(&"region_bind_source", destination_data)
	return {"ok": true, "source_data": source_candidate, "destination_data": destination_candidate,
		"speed": slowest, "person_ids": extracted.party.person_ids, "team_ids": extracted.party.team_ids,
		"mapping": inserted.mapping, "leader_person_id": inserted.leader_person_id, "token": transfer_token}

func _capture_transfer_fire_snapshots(data: TerrainData, state: Dictionary) -> Dictionary:
	var guard := Store.fire_event_guard(data)
	if not guard.ok: return guard
	for pair: Array in [[&"fire_transport_snapshot", "fire_transport"], [&"fire_owner_snapshot", "fire_owners"]]:
		if not data.has_meta(pair[0]): continue
		var capture: Variant = data.get_meta(pair[0])
		if not capture is Callable or not capture.is_valid(): return fail("BUSY", "Fire owner snapshot unavailable")
		var captured: Variant = capture.call()
		if not captured is Dictionary or not captured.get("ok") is bool: return fail("BUSY", "Invalid Fire owner snapshot")
		if not captured.ok: return captured
		var snapshot: Variant = captured.get("state", {})
		if not snapshot is Dictionary: return fail("CORRUPT_FIRE_OWNER", "原 Fire owner 快照不是字典")
		if snapshot.is_empty(): state.erase(str(pair[1]))
		else: state[str(pair[1])] = snapshot.duplicate(true)
	if data.site.has("fire_settlement"):
		var settlement: Variant = data.site.fire_settlement
		if not settlement is Dictionary: return fail("CORRUPT_FIRE_SETTLEMENT", "即時 Site Fire 水印格式非法")
		state.fire_settlement = settlement.duplicate(true)
	return {"ok": true}

static func _fire_history_empty(state: Dictionary) -> bool:
	var fire: Variant = state.get("fire", {})
	var owners: Variant = state.get("fire_owners", {})
	var transport: Variant = state.get("fire_transport", {})
	if not fire is Dictionary or not fire.is_empty() or not owners is Dictionary or not owners.is_empty() \
			or not transport is Dictionary or not _seconds(transport.get("action_cursor", 0.0)):
		return false
	for field: String in ["release_sequence", "exposure_sequence", "round_robin"]:
		if not _whole(transport.get(field, 0), 0, 2147483647) or int(transport.get(field, 0)) != 0:
			return false
	for field: String in ["projectiles", "reservations", "member_cursor"]:
		var value: Variant = transport.get(field, [])
		if not value is Array and not value is Dictionary: return false
		if not value.is_empty(): return false
	var raw_orders: Variant = transport.get("orders", [])
	var orders: Array = raw_orders if raw_orders is Array else raw_orders.values() if raw_orders is Dictionary else []
	if not raw_orders is Array and not raw_orders is Dictionary: return false
	for order: Variant in orders:
		if not order is Dictionary or bool(order.get("enabled", true)): return false
		var releases: Variant = order.get("release_ids", [])
		if releases is Array:
			for release: Variant in releases:
				if not release is Array or release.size() != 2 or not _whole(release[1], 0, 2147483647) \
						or int(release[1]) != 0: return false
		elif releases is Dictionary:
			for sequence: Variant in releases.values():
				if not _whole(sequence, 0, 2147483647) or int(sequence) != 0: return false
		else: return false
	return true

func _transfer_fire_transport(origin: Dictionary, destination: Dictionary, teams: Dictionary) -> Dictionary:
	var source_owners: Dictionary = origin.get("fire_owners", {})
	for team_id: int in teams:
		if team_id in source_owners.get("teams", []): return fail("BUSY", "原 Fire navigation／job 尚未收束，不能跨 Site")
	var source_value: Variant = origin.get("fire_transport", {})
	if not source_value is Dictionary or source_value.is_empty(): return {"ok": true}
	var source_entry: Dictionary = source_value.duplicate(true)
	var destination_settlement: Variant = destination.get("fire_settlement", {})
	var destination_can_start_fire_epoch: bool = (not destination.has("fire_settlement") \
		or destination_settlement is Dictionary and destination_settlement.is_empty()) and _fire_history_empty(destination)
	if not source_entry.get("projectiles", []).is_empty() or not source_entry.get("reservations", []).is_empty():
		return fail("BUSY", "原射擊飛行／準備尚未收束，不能跨 Site")
	var target_value: Variant = destination.get("fire_transport", {})
	var target: Dictionary = target_value.duplicate(true) if target_value is Dictionary else {}
	var new_target_transport := target.is_empty()
	if new_target_transport:
		target = source_entry.duplicate(true)
		target.orders = []
		target.member_cursor = []
		target.projectiles = []
		target.reservations = []
		target.round_robin = 0
	var source_orders: Variant = source_entry.get("orders", [])
	var target_orders: Variant = target.get("orders", [])
	if source_orders is Dictionary:
		var rows: Array = []
		for group: Variant in source_orders:
			var row: Dictionary = source_orders[group].duplicate(true)
			row.group = int(group)
			rows.append(row)
		source_orders = rows
	if target_orders is Dictionary:
		var rows: Array = []
		for group: Variant in target_orders:
			var row: Dictionary = target_orders[group].duplicate(true)
			row.group = int(group)
			rows.append(row)
		target_orders = rows
	if not source_orders is Array or not target_orders is Array: return fail("CORRUPT_FIRE_OWNER", "原 Fire 命令快照格式非法")
	var moved_orders: Array = []
	var remaining_orders: Array = []
	var found := {}
	for row: Variant in source_orders:
		if not row is Dictionary: return fail("CORRUPT_FIRE_OWNER", "原 Fire 命令列格式非法")
		var group := int(row.get("group", 0))
		if teams.has(group):
			if found.has(group): return fail("CORRUPT_FIRE_OWNER", "原 Fire 隊伍命令重複")
			found[group] = true
			moved_orders.append(row)
		else: remaining_orders.append(row)
	for team_id: int in teams:
		if not found.has(team_id): return fail("CORRUPT_FIRE_OWNER", "移交原 Fire owner 缺命令快照：%d" % team_id)
	for row: Dictionary in target_orders:
		if teams.has(int(row.get("group", 0))): return fail("ID_CONFLICT", "目的地已有同一原 Fire 命令 owner")
	var source_cursors: Variant = source_entry.get("member_cursor", [])
	var target_cursors: Variant = target.get("member_cursor", [])
	if source_cursors is Dictionary:
		var rows: Array = []
		for group: Variant in source_cursors: rows.append([int(group), int(source_cursors[group])])
		source_cursors = rows
	if target_cursors is Dictionary:
		var rows: Array = []
		for group: Variant in target_cursors: rows.append([int(group), int(target_cursors[group])])
		target_cursors = rows
	if not source_cursors is Array or not target_cursors is Array: return fail("CORRUPT_FIRE_OWNER", "原 Fire 成員游標格式非法")
	var moved_cursors: Array = []
	var remaining_cursors: Array = []
	for pair: Variant in source_cursors:
		if not pair is Array or pair.size() != 2: return fail("CORRUPT_FIRE_OWNER", "原 Fire 成員游標列格式非法")
		if teams.has(int(pair[0])): moved_cursors.append(pair.duplicate())
		else: remaining_cursors.append(pair.duplicate())
	var target_groups := {}
	for pair: Variant in target_cursors:
		if not pair is Array or pair.size() != 2: return fail("CORRUPT_FIRE_OWNER", "目的 Fire 成員游標列格式非法")
		target_groups[int(pair[0])] = true
	for pair: Array in moved_cursors:
		if target_groups.has(int(pair[0])): return fail("ID_CONFLICT", "目的地已有同一 Fire member cursor")
		target_cursors.append(pair)
	source_entry.orders = remaining_orders
	source_entry.member_cursor = remaining_cursors
	target.orders = target_orders.duplicate(true)
	target.orders.append_array(moved_orders)
	target.member_cursor = target_cursors
	target.release_sequence = maxi(int(source_entry.get("release_sequence", 0)), int(target.get("release_sequence", 0)))
	target.exposure_sequence = maxi(int(source_entry.get("exposure_sequence", 0)), int(target.get("exposure_sequence", 0)))
	if new_target_transport: target.action_cursor = float(source_entry.get("action_cursor", 0.0))
	origin.fire_transport = source_entry
	destination.fire_transport = target
	var clock: Dictionary = control.get("fire_clock", {})
	var checked_clock := validate_fire_clock(clock, control.get("logical_game_seconds"))
	if not checked_clock.ok: return checked_clock
	for index: int in range(2):
		var state: Dictionary = [origin, destination][index]
		var settlement: Variant = state.get("fire_settlement", {})
		if settlement is Dictionary and not settlement.is_empty():
			var settlement_check := validate_fire_settlement(state, clock)
			if not settlement_check.ok: return settlement_check
			var watermark: Dictionary = settlement
			if int(watermark.sequence) != int(clock.sequence) or float(watermark.game_seconds) != float(control.logical_game_seconds):
				return fail("UNSETTLED_FIRE_SITE", "移交前 Site Fire 雙時間尚未共同結算")
		else:
			if index == 1 and destination_can_start_fire_epoch:
				pass
			elif not _fire_history_empty(state):
				return fail("MISSING_FIRE_HISTORY", "跨 Site Fire owner 缺少原雙時間水印")
		if not settlement is Dictionary: return fail("CORRUPT_FIRE_SETTLEMENT", "Site Fire 水印格式非法")
		if settlement.is_empty(): state.fire_transport.action_cursor = float(clock.action_seconds)
		state.fire_settlement = {"version": 1, "epoch": str(clock.epoch), "sequence": int(clock.sequence),
			"action_seconds": float(clock.action_seconds), "game_seconds": float(control.logical_game_seconds)}
	return {"ok": true}

static func _saved_people(state: Dictionary) -> Dictionary:
	var result := {}
	for army: Dictionary in state.get("armies", []):
		for row: Dictionary in army.units: result[int(row.person_id)] = {"body": row, "team": int(army.team_id)}
	for actor: Dictionary in state.get("actors", {}).values(): result[int(actor.person_id)] = {"body": actor, "team": 0}
	return result

func _request(token: String) -> Dictionary:
	if not _safe_part(token): return fail("INVALID", "旅程 token 非法")
	if FileAccess.file_exists(folder.path_join("journeys/%s.cancelled.json" % token)) or _was_cancelled(token): return fail("CANCELLED", "原旅程已取消")
	if _was_committed(token): return fail("ALREADY_COMMITTED", "原旅程已提交；不重放原人物移交")
	if _prepared.has(token): return {"ok": true, "request": _prepared[token]}
	var document := _read_document(folder.path_join("journeys/%s.json" % token))
	if not document.ok: return document
	var record: Dictionary = document.payload
	const FIELDS := ["version", "token", "pin", "from", "to", "boat_ids", "anchor", "facing", "seconds", "departure_game_seconds", "destination_path", "destination_sha256"]
	if not _whole(record.get("version"), 1, 2) or record.size() != FIELDS.size() + int(int(record.get("version", 0)) == 2) or record.get("token") != token \
			or not _same_pin(record.get("pin"), pin) or not record.get("boat_ids") is Array or record.boat_ids.is_empty():
		return fail("CORRUPT_SAVE", "原旅程 prepared 記錄非法")
	if int(record.version) == 2 and record.get("route_mode") != "adjacent_water_seam": return fail("SAVE_VERSION", "未知原船跨圖路線模式")
	for field: String in ["from", "to", "anchor", "facing"]:
		if not record.get(field) is Array or record[field].size() != 2 \
				or not _whole(record[field][0], -10000000, 10000000) or not _whole(record[field][1], -10000000, 10000000):
			return fail("CORRUPT_SAVE", "原旅程 prepared 坐標非法")
	if not Ship.valid_facing(Vector2i(int(record.facing[0]), int(record.facing[1]))) \
			or not record.get("destination_path") is String or not record.get("destination_sha256") is String \
			or not _seconds(record.get("seconds")) or float(record.seconds) <= 0.0 \
			or not _seconds(record.get("departure_game_seconds")):
		return fail("CORRUPT_SAVE", "原旅程 prepared 時間／目的檔案非法")
	_prepared[token] = record
	return {"ok": true, "request": record}

func _was_committed(token: String) -> bool:
	if str(_marker.get("transfer_token", "")) == token: return true
	var commits := DirAccess.open(folder.path_join("commits"))
	if commits == null: return false
	for name: String in commits.get_files():
		if not name.ends_with(".json") or not name.trim_suffix(".json").is_valid_int(): continue
		var document := _read_document(folder.path_join("commits").path_join(name))
		if document.ok and str(document.payload.get("transfer_token", "")) == token: return true
	return false

func _was_cancelled(token: String) -> bool:
	var receipt := "cancelled:" + token
	if str(_marker.get("transfer_token", "")) == receipt: return true
	var commits := DirAccess.open(folder.path_join("commits"))
	if commits == null: return false
	for name: String in commits.get_files():
		if not name.ends_with(".json") or not name.trim_suffix(".json").is_valid_int(): continue
		var document := _read_document(folder.path_join("commits").path_join(name))
		if document.ok and str(document.payload.get("transfer_token", "")) == receipt: return true
	return false

func prepare_ship_transfer(source_data: TerrainData, destination_site: Vector2i, boat_ids: Array[String], destination_anchor: Vector2i, destination_facing: Vector2i, edge_only: bool = false) -> Dictionary:
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	if not _marker.get("journey", {}).is_empty() or not _prepared.is_empty(): return fail("BUSY", "同一存檔槽已有原船旅程")
	var coordinate := _coordinate(source_data)
	if not coordinate.ok: return coordinate
	var from: Vector2i = coordinate.site
	if from == destination_site: return fail("INVALID", "跨 Site 目的地必須不同")
	if not str(control.active_site_id).is_empty() and str(control.active_site_id) != str(source_data.site.id):
		return fail("CONFLICT", "來源不是此存檔槽唯一活動地點")
	var source_window := validate_settlement(source_data.site, control.logical_game_seconds)
	if not source_window.ok or not source_window.legacy and float(source_window.pending) > 0.00001:
		return source_window if not source_window.ok else fail("UNSETTLED_SITE", "原旅程來源尚有補算債")
	var destination := _ship_destination(destination_site, float(control.logical_game_seconds))
	if not destination.ok: return destination
	var token := "ship_" + Crypto.new().generate_random_bytes(16).hex_encode()
	var destination_path := site_path(destination_site)
	var prefix := folder.path_join("prepared/" + token)
	var pair := _transfer_pair(source_data, destination.data, boat_ids, destination_anchor, destination_facing, prefix.path_join("destination.json"), token)
	if not pair.ok: return pair
	var route := _adjacent_ship_route(source_data, pair.destination_data, from, destination_site, boat_ids) if edge_only else {"ok": true, "distance": Vector2(from - destination_site).length() * float(Grid.SITE_CELLS)}
	if not route.ok: return route
	var source_saved := _save_checked(pair.source_data, from, prefix.path_join("source.json"))
	if not source_saved.ok: return source_saved
	var destination_saved := _save_checked(pair.destination_data, destination_site, prefix.path_join("destination.json"))
	if not destination_saved.ok: return destination_saved
	var seconds := float(route.distance) / float(pair.speed)
	var request := {"version": 2 if edge_only else 1, "token": token, "pin": pin.duplicate(true), "from": [from.x, from.y], "to": [destination_site.x, destination_site.y],
		"boat_ids": boat_ids.duplicate(), "anchor": [destination_anchor.x, destination_anchor.y], "facing": [destination_facing.x, destination_facing.y],
		"seconds": seconds, "departure_game_seconds": float(control.logical_game_seconds), "destination_path": destination_path,
		"destination_sha256": FileAccess.get_sha256(destination_path) if FileAccess.file_exists(destination_path) else ""}
	if edge_only: request["route_mode"] = "adjacent_water_seam"
	var journal := _write_new_document(folder.path_join("journeys/%s.json" % token), request)
	if not journal.ok: return journal
	_prepared[token] = request
	return {"ok": true, "token": token, "from": request.from.duplicate(), "to": request.to.duplicate(), "seconds": seconds}

static func _touches_ship_edge(cells: Array[Vector2i], direction: Vector2i) -> bool:
	for cell: Vector2i in cells:
		if direction == Vector2i.UP and cell.y == 0 or direction == Vector2i.DOWN and cell.y == 99 \
			or direction == Vector2i.LEFT and cell.x == 0 or direction == Vector2i.RIGHT and cell.x == 99: return true
	return false

static func _ship_route_edge(origin: TerrainData, destination: TerrainData, from: Vector2i, to: Vector2i, first: Vector2i, second: Vector2i) -> bool:
	# World grid has north-positive Y; original local grid has down-positive Y.
	var direction := Vector2i(second.x - first.x, first.y - second.y)
	var edge := TerrainData.DIRECTIONS.find(direction)
	if edge < 0: return false
	var a_site := Grid.site_from_mm(first.x * Grid.CELL_MM + 1000, first.y * Grid.CELL_MM + 1000)
	var b_site := Grid.site_from_mm(second.x * Grid.CELL_MM + 1000, second.y * Grid.CELL_MM + 1000)
	var a := Grid.local_from_mm(first.x * Grid.CELL_MM + 1000, first.y * Grid.CELL_MM + 1000)
	var b := Grid.local_from_mm(second.x * Grid.CELL_MM + 1000, second.y * Grid.CELL_MM + 1000)
	var a_data: TerrainData = origin if a_site == from else destination if a_site == to else null
	var b_data: TerrainData = origin if b_site == from else destination if b_site == to else null
	if a_data == null or b_data == null or not a_data.can_navigate_water(a) or not b_data.can_navigate_water(b): return false
	if a_data == b_data: return a_data.can_water_step(a, b)
	var a_index := a_data.index(a)
	var b_index := b_data.index(b)
	var a_ramps := a_data.navigation_ramps()
	var b_ramps := b_data.navigation_ramps()
	return a_data.height_levels[a_index] == b_data.height_levels[b_index] \
		and a_ramps.size() == a_data.size.x * a_data.size.y and b_ramps.size() == b_data.size.x * b_data.size.y \
		and (a_ramps[a_index] & (1 << (edge + 4))) == 0 and (b_ramps[b_index] & (1 << ((edge + 2) % 4 + 4))) == 0

func _adjacent_ship_route(origin: TerrainData, destination: TerrainData, from: Vector2i, to: Vector2i, boat_ids: Array[String]) -> Dictionary:
	var delta := to - from
	if delta not in TerrainData.DIRECTIONS: return fail("NO_ROUTE", "首版只接相鄰、正向、明示可航的海上接縫")
	var direction := Vector2i(delta.x, -delta.y)
	var distance := -1
	for identity: String in boat_ids:
		var outgoing: Dictionary = origin.site.vehicles[identity]
		var incoming: Dictionary = destination.site.vehicles[identity]
		var old_anchor := origin.cell_from_index(int(outgoing.cell))
		var new_anchor := destination.cell_from_index(int(incoming.cell))
		var old_facing := Vector2i(int(outgoing.facing[0]), int(outgoing.facing[1]))
		var new_facing := Vector2i(int(incoming.facing[0]), int(incoming.facing[1]))
		if old_facing != direction or new_facing != direction: return fail("NO_ROUTE", "每艘船朝向须对应相邻目的 Site，不在粗段内转船")
		var old_cells: Array[Vector2i] = Ship.footprint(str(outgoing.ship_type), old_anchor, old_facing)
		var new_cells: Array[Vector2i] = Ship.footprint(str(incoming.ship_type), new_anchor, new_facing)
		if not _touches_ship_edge(old_cells, direction) or not _touches_ship_edge(new_cells, -direction): return fail("NO_ROUTE", "船体必须先细步抵达出航边缘，目的船体必须接对向入口")
		var world_start := Vector2i(from.x * 100 + old_anchor.x, from.y * 100 + 99 - old_anchor.y)
		var world_end := Vector2i(to.x * 100 + new_anchor.x, to.y * 100 + 99 - new_anchor.y)
		var shift := world_end - world_start
		var steps := shift.x * delta.x + shift.y * delta.y
		if steps <= 0 or shift != delta * steps or distance >= 0 and distance != steps: return fail("NO_ROUTE", "船队必须沿同一实际全球直行位移接缝，不能横移或瞬移")
		distance = steps
		for step in range(steps + 1):
			var hull := {}
			for old_cell: Vector2i in old_cells:
				var world := Vector2i(from.x * 100 + old_cell.x, from.y * 100 + 99 - old_cell.y) + delta * step
				hull[world] = true
				var east_mm := int(world.x) * Grid.CELL_MM + 1000
				var north_mm := int(world.y) * Grid.CELL_MM + 1000
				var coordinate := Grid.site_from_mm(east_mm, north_mm)
				var cell := Grid.local_from_mm(east_mm, north_mm)
				var data: TerrainData = origin if coordinate == from else destination if coordinate == to else null
				if data == null or not data.can_navigate_water(cell): return fail("NO_ROUTE", "原船体路径碰陆／桥／未知或未许可水域")
				var sample: Dictionary = source.sample_meters(float(east_mm) / 1000.0, float(north_mm) / 1000.0)
				if not sample.ok or int(sample.get("water_kind", -1)) != 2 or str(sample.get("water_id", "")) != "ocean" or int(sample.get("water_body", -1)) != 1:
					return fail("NO_ROUTE", "原 Region 来源未确认同一明示海洋航路")
				if step > 0 and not _ship_route_edge(origin, destination, from, to, world - delta, world): return fail("NO_ROUTE", "原船體前進邊高度或水域通行邊禁止")
			# Every current hull edge must be legal, including the outer beam and
			# a hull straddling the seam; a center path is insufficient.
			for world: Vector2i in hull:
				for adjacent: Vector2i in TerrainData.DIRECTIONS:
					if hull.has(world + adjacent) and not _ship_route_edge(origin, destination, from, to, world, world + adjacent): return fail("NO_ROUTE", "原完整船體內部水域邊禁止")
	return {"ok": true, "distance": float(distance)}

func ship_transfer_status(token: String = "") -> Dictionary:
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	var journey: Dictionary = _marker.get("journey", {})
	if is_region_travel(journey): return {"ok": true, "pending": false} if token.is_empty() else fail("CONFLICT", "目前是陸路旅隊，不是船隊旅程")
	if token.is_empty():
		if not journey.is_empty(): token = str(journey.get("token", ""))
		elif _prepared.size() == 1: token = str(_prepared.keys()[0])
		else: return {"ok": true, "pending": false}
	var requested := _request(token)
	if not requested.ok: return requested
	var status: Dictionary = requested.request.duplicate(true)
	status["pending"] = true
	status["ok"] = true
	status["elapsed_game_seconds"] = maxf(0.0, float(control.logical_game_seconds) - float(status.departure_game_seconds))
	status["elapsed_action_seconds"] = float(journey.get("elapsed_action_seconds", 0.0)) if str(journey.get("token", "")) == token else 0.0
	status["phase"] = str(journey.get("phase", "outbound"))
	status["return_required_action_seconds"] = float(journey.get("return_required_action_seconds", 0.0))
	status["return_elapsed_action_seconds"] = float(journey.get("return_elapsed_action_seconds", 0.0))
	if float(status.elapsed_action_seconds) > float(status.seconds) + 0.000001: return fail("CORRUPT_SAVE", "旅程 ACTION 超過已提交路程")
	return status

func checkpoint_ship_transfer(token: String, source_data: TerrainData, elapsed_action_seconds: float = 0.0, phase: String = "outbound", return_elapsed_action_seconds: float = 0.0) -> Dictionary:
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	var requested := _request(token)
	if not requested.ok: return requested
	var request: Dictionary = requested.request
	if not _seconds(elapsed_action_seconds): return fail("INVALID_TIME", "原旅程 ACTION 進度非法")
	var previous: Dictionary = _marker.get("journey", {})
	if str(previous.get("token", "")) == token and elapsed_action_seconds < float(previous.get("elapsed_action_seconds", 0.0)):
		return fail("INVALID_TIME", "原旅程 ACTION 進度不可倒退")
	if elapsed_action_seconds > float(request.seconds) + 0.000001: return fail("INVALID_TIME", "原旅程 ACTION 進度超過目的地")
	var returning := str(previous.get("phase", "outbound")) == "return"
	if phase not in ["outbound", "return"] or returning and phase != "return" or not returning and phase != "outbound": return fail("INVALID_TIME", "必須由同一原旅程 begin_return 切返航，不能偽造 phase")
	if not _seconds(return_elapsed_action_seconds): return fail("INVALID_TIME", "返航 ACTION 非法")
	var required := float(previous.get("return_required_action_seconds", 0.0))
	if returning and (elapsed_action_seconds != float(previous.elapsed_action_seconds) or return_elapsed_action_seconds < float(previous.return_elapsed_action_seconds) or return_elapsed_action_seconds > required + 0.000001) \
		or not returning and return_elapsed_action_seconds != 0.0: return fail("INVALID_TIME", "返航不能縮短已航距離或倒退")
	var journey := {"version": 1, "token": token, "phase": phase, "elapsed_action_seconds": elapsed_action_seconds, "return_required_action_seconds": required, "return_elapsed_action_seconds": return_elapsed_action_seconds}
	var coordinate := _coordinate(source_data)
	var from := Vector2i(int(request.from[0]), int(request.from[1]))
	if not coordinate.ok or coordinate.site != from: return fail("CONFLICT", "原旅程來源已更換")
	if float(control.logical_game_seconds) < float(request.departure_game_seconds) - 0.00001: return fail("TIME_MISMATCH", "原旅程時鐘倒退")
	var window := validate_settlement(source_data.site, control.logical_game_seconds)
	if not window.ok or not window.legacy and float(window.pending) > 0.00001:
		return window if not window.ok else fail("UNSETTLED_SITE", "原旅程來源尚未完成原步進")
	# Checkpoint keeps original people and ships at the source. Its one marker
	# records the original clock progress, allowing resume without replaying food.
	var path := _generation_path(int(_marker.get("generation", 0)) + 1, from)
	var checked := _save_checked(source_data, from, path)
	if not checked.ok: return checked
	var sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	sites[_site_key(from)] = _file_entry(path)
	var clock := {"logical_game_seconds": float(control.logical_game_seconds), "active_site_id": str(source_data.site.id)}
	var published := _publish(sites, clock, str(_marker.get("transfer_token", "")), journey)
	return {"ok": true, "generation": published.generation, "path": path, "elapsed_game_seconds": float(control.logical_game_seconds) - float(request.departure_game_seconds), "elapsed_action_seconds": elapsed_action_seconds} if published.ok else published

func commit_ship_transfer(token: String, source_data: TerrainData, arrival_preflight: Callable = Callable()) -> Dictionary:
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	var requested := _request(token)
	if not requested.ok: return requested
	var request: Dictionary = requested.request
	var journey: Dictionary = _marker.get("journey", {})
	if str(journey.get("token", "")) != token or str(journey.get("phase", "outbound")) != "outbound" or float(journey.get("elapsed_action_seconds", 0.0)) + 0.000001 < float(request.seconds):
		return fail("INCOMPLETE_JOURNEY", "原 ACTION 旅程尚未完成並 checkpoint，不能零時間轉場")
	var coordinate := _coordinate(source_data)
	var from := Vector2i(int(request.from[0]), int(request.from[1]))
	var to := Vector2i(int(request.to[0]), int(request.to[1]))
	if not coordinate.ok or coordinate.site != from or not str(control.active_site_id).is_empty() and str(control.active_site_id) != str(source_data.site.id):
		return fail("CONFLICT", "原旅程活動來源已變更，未提交")
	var destination_path := site_path(to)
	var destination_hash := FileAccess.get_sha256(destination_path) if FileAccess.file_exists(destination_path) else ""
	if destination_path != str(request.destination_path) or destination_hash != str(request.destination_sha256):
		return fail("CONFLICT", "目的 Site 在準備後已有新保存，未覆寫")
	if float(control.logical_game_seconds) < float(request.departure_game_seconds) - 0.00001: return fail("TIME_MISMATCH", "原旅程遊戲時鐘倒退")
	var window := validate_settlement(source_data.site, control.logical_game_seconds)
	if not window.ok or not window.legacy and float(window.pending) > 0.00001:
		return window if not window.ok else fail("UNSETTLED_SITE", "原旅程來源尚未完成原步進")
	var destination := _ship_destination(to, float(control.logical_game_seconds))
	if not destination.ok: return destination
	var generation := int(_marker.get("generation", 0)) + 1
	var from_path := _generation_path(generation, from)
	var to_path := _generation_path(generation, to)
	var boats: Array[String] = []
	for identity: Variant in request.boat_ids:
		if not identity is String: return fail("CORRUPT_SAVE", "旅程原船 ID 非法")
		boats.append(str(identity))
	# Re-capture after the original clock advanced. Consumption is legitimate;
	# IDs, ownership closure, current life state and the destination are rechecked.
	var pair := _transfer_pair(source_data, destination.data, boats, Vector2i(int(request.anchor[0]), int(request.anchor[1])), Vector2i(int(request.facing[0]), int(request.facing[1])), to_path, str(request.token))
	if not pair.ok: return pair
	var source_checked := _save_checked(pair.source_data, from, from_path)
	if not source_checked.ok: return source_checked
	var destination_checked := _save_checked(pair.destination_data, to, to_path)
	if not destination_checked.ok: return destination_checked
	var fire_clock: Dictionary = control.get("fire_clock", {}).duplicate(true)
	var fire_clock_check := validate_fire_clock(fire_clock, control.get("logical_game_seconds"))
	if not fire_clock_check.ok: return fire_clock_check
	for candidate: Dictionary in [
		{"data": source_checked.data, "site": from}, {"data": destination_checked.data, "site": to}]:
		var candidate_data: TerrainData = candidate.data
		var identity := str(candidate_data.site.id)
		if not candidate_data.site.has("fire_settlement"):
			if Runtime.fire_active(candidate_data) or not candidate_data.site.get("fire", {}).is_empty() \
				or not candidate_data.site.get("fire_owners", {}).is_empty():
				return fail("MISSING_FIRE_HISTORY", "船旅候選 Fire 狀態缺少原雙時間水印")
			continue
		var settlement := validate_fire_settlement(candidate_data.site, fire_clock)
		if not settlement.ok: return settlement
		var watermark: Dictionary = candidate_data.site.fire_settlement
		var previous: Dictionary = fire_clock.get("index", {}).get(identity, {})
		var fire_active := Runtime.fire_active(candidate_data) \
			or bool(previous.get("fire_active", false)) and float(candidate_data.site.get("combat_left", 0.0)) > 0.0
		fire_clock.index[identity] = {"coordinate": [candidate.site.x, candidate.site.y],
			"active": identity == str(destination_checked.data.site.id), "fire_active": fire_active,
			"sequence": int(watermark.sequence), "action_seconds": float(watermark.action_seconds),
			"game_seconds": float(watermark.game_seconds)}
	var prepared := {"ok": true}
	if arrival_preflight.is_valid():
		var candidate: Variant = arrival_preflight.call(destination_checked.data)
		if not candidate is Dictionary or not candidate.get("ok") is bool: return fail("INVALID", "抵達 preflight 未提供原載入合同")
		if not candidate.ok: return candidate
		prepared = candidate
	var sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	sites[_site_key(from)] = _file_entry(from_path)
	sites[_site_key(to)] = _file_entry(to_path)
	var clock := {"logical_game_seconds": float(control.logical_game_seconds), "active_site_id": str(pair.destination_data.site.id),
		"fire_clock": fire_clock}
	var published := _publish(sites, clock, token)
	if not published.ok: return published
	_prepared.erase(token)
	return {"ok": true, "source_data": source_checked.data, "destination_data": destination_checked.data,
		"active_site": request.to.duplicate(), "generation": published.generation, "prepared": prepared}

func begin_return_ship_transfer(token: String, source_data: TerrainData) -> Dictionary:
	var status := ship_transfer_status(token)
	if not status.ok: return status
	var journey: Dictionary = _marker.get("journey", {})
	if str(journey.get("token", "")) != token: return fail("INCOMPLETE_JOURNEY", "返航前須保存原來源旅程")
	if str(journey.phase) == "return": return status
	var checkpoint := checkpoint_ship_transfer(token, source_data, float(journey.elapsed_action_seconds))
	if not checkpoint.ok: return checkpoint
	journey = _marker.journey.duplicate(true)
	journey.phase = "return"
	journey.return_required_action_seconds = float(journey.elapsed_action_seconds)
	journey.return_elapsed_action_seconds = 0.0
	var published := _publish(_marker.sites, control, str(_marker.get("transfer_token", "")), journey)
	return ship_transfer_status(token) if published.ok else published

func cancel_ship_transfer(token: String) -> Dictionary:
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	var requested := _request(token)
	if not requested.ok: return requested
	var journey: Dictionary = _marker.get("journey", {})
	if str(journey.get("token", "")) == token and float(journey.get("elapsed_action_seconds", 0.0)) > 0.0 \
		and (str(journey.get("phase", "outbound")) != "return" or float(journey.get("return_elapsed_action_seconds", 0.0)) + 0.000001 < float(journey.get("return_required_action_seconds", 0.0))):
		return fail("INCOMPLETE_RETURN", "不能瞬移取消，須沿原 ACTION 完成等距返航")
	# The same atomic marker commits completed cancellation first. A crash before
	# it reads the old return job; a crash after it cannot replay this token, even
	# if the optional journal receipt has not yet been flushed.
	var published := _publish(_marker.get("sites", {}), control, "cancelled:" + token)
	if not published.ok: return published
	_prepared.erase(token)
	_write_new_document(folder.path_join("journeys/%s.cancelled.json" % token), {"version": 1, "token": token})
	return {"ok": true}

func attach_active_site(data: TerrainData) -> Dictionary:
	var coordinate := _coordinate(data)
	if not coordinate.ok: return coordinate
	if str(control.active_site_id).is_empty():
		control.logical_game_seconds = maxf(float(control.logical_game_seconds), _site_seconds(data))
	var attached := attach_settlement(data.site, control.logical_game_seconds)
	if not attached.ok: return attached
	if float(attached.pending) > 0.00001: return fail("UNSETTLED_SITE", "先完成原 shared-step 補算再激活地點")
	var fire_clock: Dictionary = control.get("fire_clock", {})
	if int(fire_clock.get("sequence", 0)) == 0 and fire_clock.get("journal", []).is_empty() \
			and float(fire_clock.get("base_game_seconds", -1.0)) != float(control.logical_game_seconds):
		var fire_state: Variant = data.site.get("fire", {})
		if fire_state is Dictionary and not fire_state.is_empty(): return fail("MISSING_FIRE_HISTORY", "已有火攻狀態不能重設雙時鐘 epoch")
		control.fire_clock = _new_fire_clock(float(control.logical_game_seconds))
		data.site.fire_settlement = {"version": 1, "epoch": str(control.fire_clock.epoch), "sequence": 0,
			"action_seconds": 0.0, "game_seconds": float(control.logical_game_seconds)}
	var previous_id := str(control.active_site_id)
	control.active_site_id = str(data.site.id)
	fire_clock = control.fire_clock
	if not previous_id.is_empty() and previous_id != str(data.site.id) and fire_clock.get("index", {}).has(previous_id):
		fire_clock.index[previous_id].active = false
	if data.site.has("fire_settlement"):
		var fire_settlement: Dictionary = data.site.fire_settlement
		var previous_fire_active := bool(fire_clock.get("index", {}).get(str(data.site.id), {}).get("fire_active", false))
		fire_clock.index[str(data.site.id)] = {"coordinate": [coordinate.site.x, coordinate.site.y], "active": true,
			"fire_active": Runtime.fire_active(data) or previous_fire_active and float(data.site.get("combat_left", 0.0)) > 0.0,
			"sequence": int(fire_settlement.sequence), "action_seconds": float(fire_settlement.action_seconds),
			"game_seconds": float(fire_settlement.game_seconds)}
	elif fire_clock.get("index", {}).has(str(data.site.id)):
		fire_clock.index[str(data.site.id)].active = true
	_fire_cold_candidates.erase(str(data.site.id))
	var mode := GameplayClock.activate_mode(region_registry(), str(data.site.id), "committed-unbound",
		int(_marker.get("generation", 0)), "gd", "original_site", float(control.logical_game_seconds),
		float(control.fire_clock.action_seconds), {})
	if not mode.ok: return mode
	return {"ok": true, "at": float(control.logical_game_seconds)}

func record_active_step(state: Dictionary, completed_game_seconds: Variant, permit: Dictionary = {}, fire_step: Dictionary = {}) -> Dictionary:
	return record_completed_active_step(self, state, completed_game_seconds, permit, fire_step)

func begin_active_step(state: Dictionary) -> Dictionary:
	if bool(state.get("paused", false)): return fail("PAUSED", "暫停時不開始原 shared-step")
	if state.get("id") != control.get("active_site_id", ""): return fail("NO_TARGET", "原步進來源不是唯一活動 Site")
	if control.get("fire_clock", {}).is_empty(): control.fire_clock = _new_fire_clock(float(control.logical_game_seconds))
	var synchronized := _sync_cold_fire_sites()
	if not synchronized.ok:
		if str(synchronized.get("code", "")) == "PENDING":
			return {"ok": true, "unpaused": false, "status": "FIRE_SYNC_PENDING",
				"pending": float(synchronized.get("pending", 0.0)), "site_id": str(synchronized.get("site_id", ""))}
		return synchronized
	var checked := validate_settlement(state, control.get("logical_game_seconds"))
	if not checked.ok: return checked
	if checked.legacy or float(checked.pending) != 0.0: return fail("UNSETTLED_SITE", "活動 Site 須先完成原結算")
	var cold_fire_active := false
	for identity: String in control.fire_clock.get("index", {}):
		var row: Dictionary = control.fire_clock.index[identity]
		if identity != str(state.id) and bool(row.get("fire_active", false)):
			cold_fire_active = true
			break
	var result := {"unpaused": true, "state": state, "active_site_id": str(state.id),
		"last_settled_game_seconds": float(checked.last), "world_game_seconds": float(control.logical_game_seconds),
		"fire_epoch": str(control.fire_clock.epoch), "fire_sequence": int(control.fire_clock.sequence),
		"cold_fire_active": cold_fire_active}
	if control.has("region_gameplay"):
		var region_permit := GameplayClock.begin_permit(control.region_gameplay, str(state.id), "live",
			int(_marker.get("generation", 0)), float(control.logical_game_seconds), float(control.fire_clock.action_seconds), "original_site", _region_positive_player_death_ids())
		if not region_permit.ok: return region_permit
		result.region_permit = region_permit
	return result

func _sync_cold_fire_sites() -> Dictionary:
	var clock: Dictionary = control.get("fire_clock", {})
	var identities: Array[String] = []
	for identity: String in clock.get("index", {}):
		var row: Dictionary = clock.index[identity]
		if identity != str(control.get("active_site_id", "")) and not bool(row.get("active", false)) \
				and bool(row.get("fire_active", false)):
			identities.append(identity)
	identities.sort()
	if identities.is_empty():
		_fire_sync_target.clear()
		return {"ok": true}
	var target := float(control.logical_game_seconds)
	var sequence := int(clock.get("sequence", 0))
	var epoch := str(clock.get("epoch", ""))
	if _fire_sync_target.is_empty():
		_fire_sync_target = {"target": target, "sequence": sequence, "epoch": epoch}
	elif float(_fire_sync_target.get("target", -1.0)) != target \
		or int(_fire_sync_target.get("sequence", -1)) != sequence or str(_fire_sync_target.get("epoch", "")) != epoch:
		return fail("CLOCK_CONTRACT", "冷火場同步目標／原時鐘來源已變更")
	for identity: String in identities:
		var row: Dictionary = clock.index[identity]
		var coordinate := Vector2i(int(row.coordinate[0]), int(row.coordinate[1]))
		var candidate: Dictionary = _fire_cold_candidates.get(identity, {})
		if candidate.is_empty():
			var path := site_path(coordinate)
			if not FileAccess.file_exists(path): return fail("MISSING_FIRE_HISTORY", "冷火場索引沒有原 Site 快照")
			var loaded := _load_checked(path, coordinate)
			if not loaded.ok: return loaded
			var data: TerrainData = loaded.data
			if str(data.site.get("id", "")) != identity: return fail("SAVE_VERSION", "冷火場快照與原索引身分不同")
			var boundary := _refresh_boundaries(data, coordinate)
			if not boundary.ok: return boundary
			var fire_settlement := validate_fire_settlement(data.site, clock)
			if not fire_settlement.ok: return fire_settlement
			candidate = {"data": data, "coordinate": coordinate, "target": target, "sequence": sequence, "epoch": epoch}
			_fire_cold_candidates[identity] = candidate
		var settled := _settle_cold_candidate(candidate.data, target)
		if not settled.ok:
			if str(settled.get("code", "")) == "PENDING":
				return {"ok": false, "code": "PENDING", "site_id": identity,
					"pending": float(settled.get("pending", 0.0)), "message": "冷火場沿原 journal 同步中"}
			return settled
		var result_data: TerrainData = settled.data
		var result_settlement: Dictionary = result_data.site.get("fire_settlement", {})
		if str(result_settlement.get("epoch", "")) != epoch or int(result_settlement.get("sequence", -1)) != sequence \
				or absf(float(result_settlement.get("game_seconds", -1.0)) - target) > 0.00000001:
			return fail("CLOCK_CONTRACT", "冷火場候選未到固定共同水印")
		var fire_active := bool(result_data.get_meta(&"region_fire_active", Runtime.fire_active(result_data))) \
			or bool(row.get("fire_active", false)) and float(result_data.site.get("combat_left", 0.0)) > 0.0
		result_data.set_meta(&"region_fire_active", fire_active)
		candidate.data = result_data
		candidate.target = target
		candidate.sequence = sequence
		control.fire_clock.index[identity] = {"coordinate": [coordinate.x, coordinate.y], "active": false,
			"fire_active": fire_active, "sequence": sequence,
			"action_seconds": float(result_settlement.action_seconds), "game_seconds": float(result_settlement.game_seconds)}
		# Extinguished/finished originals remain affected until a JOINT checkpoint.
		# Their accepted volatile result must neither vanish nor be replayed twice.
		_fire_cold_candidates[identity] = candidate
	_fire_sync_target.clear()
	return {"ok": true}

func _collect_cold_checkpoint(generation: int, sites: Dictionary, next_control: Dictionary) -> Dictionary:
	if not _fire_sync_target.is_empty(): return fail("BUSY", "冷原 owner 尚未完成共同區間")
	# Register every actual cached original, including peaceful work Sites.
	# Their actual full graph is captured by _save_checked below.
	for owner: String in _region_original_labs:
		if owner == str(control.active_site_id): continue
		var original: TerrainLab = _region_original_labs[owner]
		if not is_instance_valid(original) or original.terrain == null or str(original.terrain.site.id) != owner:
			return fail("COMMITTED_UNBOUND")
		var coordinate := _coordinate(original.terrain)
		if not coordinate.ok: return coordinate
		_fire_cold_candidates[owner] = {"data": original.terrain, "coordinate": coordinate.site,
			"target": float(control.logical_game_seconds), "sequence": int(control.fire_clock.sequence), "epoch": str(control.fire_clock.epoch)}
	var identities: Array[String] = []
	for identity: String in _fire_cold_candidates: identities.append(identity)
	identities.sort()
	for identity: String in identities:
		var candidate: Dictionary = _fire_cold_candidates[identity]
		var settled := _settle_cold_candidate(candidate.data, float(control.logical_game_seconds))
		if not settled.ok: return settled
		# Retain even a subsequently failed checkpoint's completed original result.
		candidate.data = settled.data
		_fire_cold_candidates[identity] = candidate
		var coordinate: Vector2i = candidate.coordinate
		var path := _generation_path(generation, coordinate)
		var saved := _save_checked(candidate.data, coordinate, path)
		if not saved.ok: return saved
		sites[_site_key(coordinate)] = _file_entry(path)
		if candidate.data.site.has("fire_settlement"):
			var watermark: Dictionary = candidate.data.site.fire_settlement
			next_control.fire_clock.index[identity] = {"coordinate": [coordinate.x, coordinate.y],
				"active": str(next_control.active_site_id) == identity,
				"fire_active": bool(candidate.data.get_meta(&"region_fire_active", Runtime.fire_active(candidate.data))),
				"sequence": int(watermark.sequence), "action_seconds": float(watermark.action_seconds),
				"game_seconds": float(watermark.game_seconds)}
	return {"ok": true, "identities": identities}

func _flush_cold_fire_candidates() -> Dictionary:
	# Kept as a defensive old call boundary. Publication requires the original
	# active snapshot too; never publish cold files one by one ahead of it.
	return {"ok": true} if _fire_cold_candidates.is_empty() else fail("BUSY", "冷結果等待原活動 Site 的共同 checkpoint")

func region_registry() -> Dictionary:
	if not control.has("region_gameplay"): control.region_gameplay = GameplayClock.empty_registry()
	return control.region_gameplay

func queue_region_event(identity: String, kind: String, at: float, owner: String, payload: Dictionary = {}, player: bool = false) -> Dictionary:
	if at < float(control.logical_game_seconds) - 0.00000001: return fail("REGION_EVENT", "新事件不能倒填已完成區間")
	return GameplayClock.queue_event(region_registry(), identity, kind, at, owner, payload, player)

func pending_region_events() -> Array[Dictionary]:
	return GameplayClock.pending_at(region_registry(), float(control.logical_game_seconds))

func complete_region_event(identity: String) -> Dictionary:
	return GameplayClock.complete_event(region_registry(), identity, float(control.logical_game_seconds))

func region_player_barrier() -> Dictionary:
	return GameplayClock.player_barrier(region_registry(), float(control.logical_game_seconds))

func activate_region_mode(owner: String, mode: String, consumer: String, receipt: Dictionary, backend: String = "gd") -> Dictionary:
	return GameplayClock.activate_mode(region_registry(), owner, mode, int(_marker.get("generation", 0)), backend, consumer,
		float(control.logical_game_seconds), float(control.fire_clock.action_seconds), receipt)

func acknowledge_region_bind(data: TerrainData, receipt: Dictionary) -> Dictionary:
	if data == null or str(data.site.get("id", "")) != str(control.active_site_id): return fail("REGION_BIND", "綁定不是已提交活動 owner")
	var getter: Variant = data.get_meta(&"region_bind_receipt", Callable())
	if not getter is Callable or not getter.is_valid(): return fail("REGION_BIND", "缺原 TerrainLab 完整綁定收據")
	var original: Variant = getter.call(data)
	if not original is Dictionary or original != receipt or receipt.get("complete") != true:
		return fail("REGION_BIND", "原 owner 綁定尚未完成")
	var activation := receipt.duplicate(true)
	activation.generation = int(_marker.get("generation", 0))
	var enabled := activate_region_mode(str(data.site.id), "live", "original_site", activation, str(receipt.get("backend", "gd")))
	if not enabled.ok: return enabled
	if data.site.has("region_life_events"):
		var consume: Variant = data.get_meta(&"region_life_consumer", Callable())
		if not consume is Callable or not consume.is_valid(): return fail("REGION_RECOVERY_REQUIRED", "原生命端點尚未接入")
		var consumed: Variant = consume.call()
		if not consumed is Dictionary or not bool(consumed.get("ok", false)): return consumed if consumed is Dictionary else fail("REGION_RECOVERY_REQUIRED", "生命端點出口無回執")
	return enabled

func set_region_tactical_demand(owner: String, action_until: float) -> Dictionary:
	var registry := region_registry()
	if not registry.modes.has(owner) or not GameplayClock.seconds(action_until): return fail("REGION_MODE", "战时需求缺原 owner")
	registry.modes[owner].tactical_until_action = maxf(float(control.fire_clock.action_seconds), action_until)
	return {"ok": true}

func preview_region_interval(elapsed: float, scale: float, local_tactical: float = 0.0) -> Dictionary:
	var proof := _region_player_down_settlement()
	var held: Array[String] = _region_positive_player_death_ids()
	if not proof.is_empty() and not bool(proof.point_pending): elapsed = minf(elapsed, float(proof.remaining_action_seconds))
	var clipped := GameplayClock.clip_interval(region_registry(), float(control.logical_game_seconds),
		float(control.fire_clock.action_seconds), elapsed, scale, local_tactical, held)
	if not clipped.ok or bool(clipped.get("pending", false)): return clipped
	return preview_fire_interval(control.fire_clock, float(control.logical_game_seconds), float(clipped.action_seconds), scale, float(clipped.tactical_seconds))

func _prune_recoverable_fire_journal() -> int:
	if folder.is_empty(): return prune_fire_clock_prefix(control.fire_clock) # Isolated legacy clock tests.
	var clock: Dictionary = control.fire_clock
	var recovery: Dictionary = clock.duplicate(true)
	var durable: Dictionary = _marker.get("control", {}).get("fire_clock", {}).get("index", {})
	for identity: String in recovery.index:
		# Volatile completion is not a restartable snapshot. Keep history through
		# the oldest durable original, including newly registered owners at base.
		var sequence := int(durable.get(identity, {}).get("sequence", clock.get("base_sequence", 0)))
		recovery.index[identity].sequence = mini(int(recovery.index[identity].sequence), sequence)
	var removed := prune_fire_clock_prefix(recovery)
	if removed > 0:
		for field: String in ["base_sequence", "base_action_seconds", "base_game_seconds", "journal"]: clock[field] = recovery[field]
	return removed


# The worker only reads this detached projection. Preparing it is a main-thread
# operation and does not settle time, open a Site, or change the durable marker.
var _region_route_snapshot: Dictionary = {}
var _region_route_snapshot_revision := ""

func prepare_region_route_context(active_data: TerrainData = null, party: Dictionary = {}) -> Dictionary:
	if source == null or pin.is_empty(): return fail("INVALID_SLOT", "原路線來源尚未開啟")
	if not Thread.is_main_thread(): return fail("REGION_ROUTE_THREAD", "原導航快照須在主執行緒準備")
	var snapshots := {}
	var revision := str(_marker.get("generation", 0)) + ":" + str(region_registry().revision)
	for key: String in _marker.get("sites", {}):
		var pair := key.split(":")
		if pair.size() != 2: return fail("SAVE_VERSION", "原 Site 索引非法")
		var coordinate := Vector2i(int(pair[0]), int(pair[1]))
		var original: TerrainData
		if active_data != null and _coordinate(active_data).get("site") == coordinate:
			original = active_data
		else:
			var identity := Grid.site_id(str(pin.atlas_id), coordinate)
			if _fire_cold_candidates.has(identity):
				original = _fire_cold_candidates[identity].data
			else:
				var loaded := _load_checked(site_path(coordinate), coordinate)
				if not loaded.ok: return loaded
				original = loaded.data
		var detached := Env.navigation_for_state(original, original.site.duplicate(true))
		detached.parameters = original.parameters.duplicate(true)
		detached.resource_base = original.resource_base.duplicate(true)
		for meta: StringName in detached.get_meta_list(): detached.remove_meta(meta)
		snapshots[coordinate] = detached
		revision += ":" + key + ":" + str(original.navigation_revision)
	if active_data != null:
		var coordinate := _coordinate(active_data)
		if not coordinate.ok: return coordinate
		var detached := Env.navigation_for_state(active_data, active_data.site.duplicate(true))
		detached.parameters = active_data.parameters.duplicate(true)
		detached.resource_base = active_data.resource_base.duplicate(true)
		for meta: StringName in detached.get_meta_list(): detached.remove_meta(meta)
		snapshots[coordinate.site] = detached
		revision += ":active:" + str(active_data.navigation_revision)
	_region_route_snapshot = snapshots
	_region_route_snapshot_revision = revision
	return {"ok": true, "context": region_route_context(party), "revision": revision}

func effective_route_terrain(site: Vector2i) -> Dictionary:
	# Missing means unvisited geography; it is not a fabricated water override.
	return {"ok": true, "data": _region_route_snapshot.get(site), "revision": _region_route_snapshot_revision}

func region_route_context(party: Dictionary = {}) -> Dictionary:
	# Capture the dictionary itself, not a Callable that can read a later owner.
	var frozen: Dictionary = _region_route_snapshot
	var revision := _region_route_snapshot_revision
	var provider := func(site: Vector2i) -> Dictionary:
		return {"ok": true, "data": frozen.get(site), "revision": revision}
	var content: Dictionary = party.get("content", {})
	var kinds: Array[String] = []
	var vehicles: Array[Dictionary] = []
	for vehicle: Dictionary in content.get("vehicles", {}).values():
		var kind := str(vehicle.get("kind", ""))
		if not kinds.has(kind): kinds.append(kind)
		vehicles.append(vehicle.duplicate(true))
	return {"effective_terrain": provider, "capabilities": {"mode": "sea" if kinds.has("ship") else "land",
		"vehicle_kinds": kinds, "vehicles": vehicles}, "party": party.duplicate(true), "revision": revision}

func effective_site_path(site: Vector2i) -> Dictionary:
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	var path := site_path(site)
	return {"ok": true, "path": path if FileAccess.file_exists(path) else ""}

# Read only the original slot's committed/legacy paths. No Site is opened.
func known_saved_sites() -> Dictionary:
	if pin.is_empty() or source == null: return fail("INVALID_SLOT", "尚未開啟原地圖存檔")
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	var known := {}
	for key: String in _marker.get("sites", {}):
		var pair := key.split(":")
		known[Vector2i(int(pair[0]), int(pair[1]))] = true
	var legacy := DirAccess.open(folder.path_join("sites"))
	if legacy != null:
		for x_name: String in legacy.get_directories():
			if not x_name.is_valid_int() or str(int(x_name)) != x_name: continue
			var column := DirAccess.open(folder.path_join("sites").path_join(x_name))
			if column == null: return fail("SAVE_IO", "原保存地點目錄無法讀取")
			for y_file: String in column.get_files():
				if not y_file.ends_with(".json"): continue
				var y_name := y_file.trim_suffix(".json")
				if y_name.is_valid_int() and str(int(y_name)) == y_name:
					known[Vector2i(int(x_name), int(y_name))] = true
	var sites: Array[Vector2i] = []
	for coordinate: Vector2i in known: sites.append(coordinate)
	sites.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or a.x == b.x and a.y < b.y)
	return {"ok": true, "sites": sites, "generation": int(_marker.get("generation", 0)),
		"scope": str(pin.world_instance_id) + "/" + str(pin.slot_id)}


func building_summary(site: Vector2i) -> Dictionary:
	var effective := effective_site_path(site)
	return read_site_building_summary(self, site, str(effective.path)) if effective.ok else effective

func load_compatible_site(path: String) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(path).simplify_path().replace("\\", "/")
	var slot_absolute := ProjectSettings.globalize_path(folder).simplify_path().replace("\\", "/").trim_suffix("/")
	if OS.has_feature("windows"):
		absolute = absolute.to_lower()
		slot_absolute = slot_absolute.to_lower()
	if not absolute.begins_with(slot_absolute + "/"): return fail("INVALID_SLOT", "家族快照不在目前世界存檔槽")
	var decoded := Store._read(path)
	if not decoded.ok:
		if str(decoded.get("code", "")) != "NO_SAVE": return decoded
		# Family references retain the original logical identity even when the
		# only persisted Site is the marker-selected generation. Missing aliases
		# resolve only here; corrupt files never fall back to another generation.
		var original_absolute: String = ProjectSettings.globalize_path(path).replace("\\", "/")
		if OS.has_feature("windows"): original_absolute = original_absolute.to_lower()
		var logical_prefix: String = slot_absolute + "/sites/"
		if original_absolute != absolute or not absolute.begins_with(logical_prefix): return decoded
		var components: PackedStringArray = absolute.trim_prefix(logical_prefix).split("/", true)
		if components.size() != 2 or not components[1].ends_with(".json"): return decoded
		var x_text: String = components[0]
		var y_text: String = components[1].trim_suffix(".json")
		if not x_text.is_valid_int() or not y_text.is_valid_int() \
				or str(int(x_text)) != x_text or str(int(y_text)) != y_text \
				or not _whole(int(x_text), -10000000, 10000000) or not _whole(int(y_text), -10000000, 10000000):
			return decoded
		var canonical_logical: String = folder.path_join("sites").path_join(x_text).path_join(y_text + ".json").replace("\\", "/")
		var original_path: String = path.replace("\\", "/")
		if OS.has_feature("windows"): canonical_logical = canonical_logical.to_lower(); original_path = original_path.to_lower()
		if original_path != canonical_logical and original_path != logical_prefix + x_text + "/" + y_text + ".json": return decoded
		var coordinate := Vector2i(int(x_text), int(y_text))
		var recovered_logical: Dictionary = _recover_control()
		if not recovered_logical.ok: return recovered_logical
		# No fresh Site / starter Actor can be produced by a family lookup.
		if not FileAccess.file_exists(site_path(coordinate)): return decoded
		return open_site(coordinate)
	var base: Variant = decoded.payload.parameters.get("fixed_base")
	if not base is Dictionary or not base.get("site") is Array or base.site.size() != 2 \
			or not _whole(base.site[0], -10000000, 10000000) or not _whole(base.site[1], -10000000, 10000000):
		return fail("SAVE_VERSION", "家族快照缺少此固定地圖來源")
	var site := Vector2i(int(base.site[0]), int(base.site[1]))
	if not _matches_base(base, site): return fail("SAVE_VERSION", "家族快照使用另一原地圖版本")
	var recovered := _recover_control()
	return open_site(site) if recovered.ok else recovered

const SETTLEMENT_FIELD := "simulation_settlement"

static func _fail(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}

static func _seconds(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0

static func validate_settlement(state: Dictionary, logical_game_seconds: Variant) -> Dictionary:
	if not _seconds(logical_game_seconds):
		return _fail("CORRUPT_SAVE", "世界邏輯時間非法")
	if not state.has(SETTLEMENT_FIELD):
		return {"ok": true, "legacy": true, "last": float(logical_game_seconds), "pending": 0.0}
	var stamp: Variant = state[SETTLEMENT_FIELD]
	if not stamp is Dictionary or stamp.size() != 2 or not stamp.has("version") \
			or not stamp.has("last_settled_game_seconds") \
			or not (stamp.version is int or stamp.version is float) or float(stamp.version) != 1.0 \
			or not _seconds(stamp.last_settled_game_seconds):
		return _fail("CORRUPT_SAVE", "Site 結算時間版本或欄位非法")
	var last := float(stamp.last_settled_game_seconds)
	if last > float(logical_game_seconds):
		return _fail("SAVE_VERSION", "Site 結算時間超前於原世界存檔")
	return {"ok": true, "legacy": false, "last": last, "pending": float(logical_game_seconds) - last}

static func attach_settlement(state: Dictionary, logical_game_seconds: Variant) -> Dictionary:
	var checked := validate_settlement(state, logical_game_seconds)
	if checked.ok and checked.legacy:
		# Legacy has no evidence of earlier shared time: no retrospective production.
		state[SETTLEMENT_FIELD] = {"version": 1, "last_settled_game_seconds": float(logical_game_seconds)}
	return checked

static func record_completed_active_step(slot: Object, state: Dictionary, completed_game_seconds: Variant, permit: Dictionary = {}, fire_step: Dictionary = {}) -> Dictionary:
	# Call once AFTER original Site work, bodies, supply, fatigue and death settlement
	# complete, BEFORE autosave. Do not call from GD and Crowd separately.
	if not _seconds(completed_game_seconds) or not slot.get("control") is Dictionary:
		return _fail("INVALID", "完成步進的遊戲秒或原存檔控制非法")
	var control_value: Dictionary = slot.get("control")
	if not state.get("id") is String or state.id != control_value.get("active_site_id", "") or str(state.id).is_empty():
		return _fail("NO_TARGET", "完成步進的 Site 不是目前活動 Site")
	var checked := validate_settlement(state, control_value.get("logical_game_seconds"))
	if not checked.ok:
		return checked
	if checked.legacy or float(checked.pending) != 0.0:
		return _fail("UNSETTLED_SITE", "活動 Site 必須先沿原模擬完成結算")
	if not permit.is_empty() and (permit.size() not in [8, 9] or permit.size() == 9 and not permit.has("region_permit") or permit.get("unpaused") != true or not is_same(permit.get("state"), state) \
			or permit.get("active_site_id") != state.id or permit.get("last_settled_game_seconds") != checked.last \
			or permit.get("world_game_seconds") != control_value.logical_game_seconds \
			or permit.get("fire_epoch") != control_value.get("fire_clock", {}).get("epoch", "") \
			or permit.get("fire_sequence") != control_value.get("fire_clock", {}).get("sequence", -1) \
			or not permit.get("cold_fire_active") is bool):
		return _fail("CLOCK_CONTRACT", "已完成原 shared-step permit／活動 owner／水印不一致")
	if permit.has("region_permit"):
		var gameplay_checked := GameplayClock.check_permit(control_value.get("region_gameplay", {}), permit.region_permit,
			int(slot.get("_marker").get("generation", 0)), float(control_value.logical_game_seconds), float(control_value.fire_clock.action_seconds))
		if not gameplay_checked.ok: return gameplay_checked
	var delta := float(completed_game_seconds)
	if delta == 0.0:
		return {"ok": true, "advanced": 0.0, "at": float(checked.last)}
	if bool(state.get("paused", false)) and permit.is_empty():
		return _fail("PAUSED", "暫停時不得發布完成步進")
	var expected := float(checked.last) + delta
	if not is_finite(expected) or expected <= float(checked.last):
		return _fail("INVALID", "遊戲時間超出可表示範圍")
	var fire_interval := {}
	var reset_fire_epoch := fire_step.is_empty()
	if reset_fire_epoch:
		var old_fire: Variant = state.get("fire", {})
		var old_clock: Dictionary = control_value.get("fire_clock", {})
		if int(old_clock.get("sequence", 0)) > 0 or not old_clock.get("journal", []).is_empty() \
				or old_fire is Dictionary and not old_fire.is_empty():
			return _fail("CLOCK_CONTRACT", "已有火攻歷程時，原步進必須提供雙時鐘區間")
	else:
		if fire_step.size() != 5 or not fire_step.get("fire_active") is bool \
				or not fire_step.get("coordinate") is Array or fire_step.coordinate.size() != 2 \
				or not _whole(fire_step.coordinate[0], -10000000, 10000000) or not _whole(fire_step.coordinate[1], -10000000, 10000000):
			return _fail("INVALID_FIRE_INTERVAL", "原 Site 火攻時間步進欄位")
		fire_interval = preview_fire_interval(control_value.get("fire_clock", {}), float(control_value.logical_game_seconds),
			float(fire_step.get("action_seconds", -1.0)), float(fire_step.get("scale", -1.0)), float(fire_step.get("tactical_seconds", -1.0)))
		if not fire_interval.ok: return fire_interval
		if absf(float(fire_interval.game_end) - expected) > maxf(0.00000001, expected * 0.000000001):
			return _fail("CLOCK_CONTRACT", "雙時鐘區間與原 shared-step 遊戲秒不一致")
	# advance_world_time is the ship integration's SINGLE in-memory publisher.
	# It must reject invalid delta without mutation, return the new exact control
	# value, and never persist per tick. Checkpoint only on original save/transfer.
	var now: float = slot.advance_world_time(delta)
	var published: Dictionary = slot.get("control")
	if now != expected or float(published.logical_game_seconds) != expected:
		return _fail("CLOCK_CONTRACT", "原時鐘發布結果不符合已完成步進")
	state[SETTLEMENT_FIELD].last_settled_game_seconds = now
	if reset_fire_epoch:
		control_value.fire_clock = _new_fire_clock(now)
		state.fire_settlement = {"version": 1, "epoch": str(control_value.fire_clock.epoch), "sequence": 0,
			"action_seconds": 0.0, "game_seconds": now}
	if not fire_interval.is_empty():
		var fire_clock: Dictionary = control_value.fire_clock
		append_completed_fire_interval(fire_clock, fire_interval)
		state.fire_settlement = {"version": 1, "epoch": str(fire_interval.epoch), "sequence": int(fire_interval.sequence),
			"action_seconds": float(fire_interval.action_end), "game_seconds": now}
		fire_clock.index[str(state.id)] = {"coordinate": fire_step.coordinate.duplicate(), "active": true,
			"fire_active": bool(fire_step.fire_active),
			"sequence": int(fire_interval.sequence), "action_seconds": float(fire_interval.action_end), "game_seconds": now}
		slot._prune_recoverable_fire_journal()
	if permit.has("region_permit"):
		var registry: Dictionary = control_value.region_gameplay
		var mode: Dictionary = registry.modes[str(state.id)]
		mode.game_seconds = now
		mode.action_seconds = float(control_value.fire_clock.action_seconds)
		registry.revision = int(registry.revision) + 1
	return {"ok": true, "advanced": delta, "at": now}

static func replay_window(state: Dictionary, logical_game_seconds: Variant) -> Dictionary:
	# Capture a fixed target BEFORE binding/replaying the original restored people.
	# UI input and ordinary frame progression stay gated until pending reaches zero.
	var checked := attach_settlement(state, logical_game_seconds)
	if not checked.ok:
		return checked
	return {"ok": true, "from": float(checked.last), "target": float(logical_game_seconds),
		"pending": float(checked.pending), "legacy": bool(checked.legacy)}

static func record_completed_replay_step(state: Dictionary, target: Variant, completed_game_seconds: Variant) -> Dictionary:
	# This records an ORIGINAL completed shared step; it performs no simulation.
	# It never calls advance_world_time, writes files, or manufactures elapsed time.
	var checked := validate_settlement(state, target)
	if not checked.ok:
		return checked
	if checked.legacy or not _seconds(completed_game_seconds):
		return _fail("INVALID", "補算步進缺少已附加的 Site 時間")
	var delta := float(completed_game_seconds)
	if delta > float(checked.pending):
		return _fail("INVALID", "補算步進超過原共同時間")
	var next := float(checked.last) + delta
	if not is_finite(next) or next > float(target) or (delta > 0.0 and next <= float(checked.last)):
		return _fail("INVALID", "補算時間超出可表示範圍")
	state[SETTLEMENT_FIELD].last_settled_game_seconds = next
	return {"ok": true, "at": next, "pending": float(target) - next}

static func read_site_building_summary(slot: Object, site: Vector2i, effective_path: String) -> Dictionary:
	# effective_path MUST come from the original highest-complete-generation
	# resolver. Empty means genuinely unvisited. A missing committed file is error.
	var pin_value: Dictionary = slot.get("pin")
	var source_entry: Object = slot.get("source")
	if pin_value.is_empty() or source_entry == null or str(slot.get("folder")).is_empty():
		return _fail("INVALID_SLOT", "存檔尚未開啟")
	var geography: Dictionary = source_entry.get_site_summary(site.x, site.y)
	if not bool(geography.get("ok", false)):
		return geography
	var site_id := Grid.site_id(str(pin_value.atlas_id), site)
	if str(geography.get("site_id", "")) != site_id:
		return _fail("SAVE_VERSION", "摘要地理身分不同")
	var result := {"ok": true, "world_instance_id": str(pin_value.world_instance_id), "slot_id": str(pin_value.slot_id),
		"site_id": site_id, "region_id": Grid.region_id(str(pin_value.atlas_id), Grid.region_of(site)),
		"geography": geography, "visited": false, "source_checksum": "", "buildings": [], "counts": {}}
	if effective_path.is_empty():
		return result
	var folder_path := ProjectSettings.globalize_path(str(slot.get("folder"))).simplify_path().trim_suffix("/")
	var resolved_path := ProjectSettings.globalize_path(effective_path).simplify_path()
	if OS.has_feature("windows"):
		folder_path = folder_path.to_lower()
		resolved_path = resolved_path.to_lower()
	if not resolved_path.begins_with(folder_path + "/"):
		return _fail("INVALID_SLOT", "摘要不能讀取另一世界或存檔的 Site")
	var decoded := Store._read(effective_path)
	if not decoded.ok:
		return decoded
	# Required one-line change in ORIGINAL SiteStore._read return metadata:
	# return Runtime.ok("", {"payload": payload, "checksum": str(envelope.checksum)})
	# Do not read the file twice: another commit could swap it between the reads.
	if not decoded.get("checksum") is String or str(decoded.checksum).length() != 64:
		return _fail("SUMMARY_READER_REQUIRED", "原 SiteStore 尚未回傳已校驗快照的版本")
	var payload: Dictionary = decoded.payload
	var base: Variant = payload.parameters.get("fixed_base")
	if not base is Dictionary or not slot._matches_base(base, site) or payload.state.get("id") != site_id:
		return _fail("SAVE_VERSION", "摘要 Site 與目前固定地理／存檔不同")
	var state: Dictionary = payload.state
	if not state.get("features") is Dictionary or not Store._integer(state.get("next_feature"), 1, 1000000):
		return _fail("CORRUPT_SAVE", "摘要建物身分欄位非法")
	var features: Dictionary = state.features
	for key: Variant in features:
		if not key is String or not key.is_valid_int() or int(key) < 1 or int(key) >= int(state.next_feature):
			return _fail("CORRUPT_SAVE", "摘要建物編號非法")
	var keys: Array = features.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in keys:
		var feature: Variant = features[key]
		if not feature is Dictionary or not Runtime.FEATURES.has(str(feature.get("kind", ""))) \
				or str(feature.get("stage", "")) not in ["planned", "building", "complete"] \
				or not feature.get("cells") is Array or feature.cells.is_empty() or feature.cells.size() > 2500 \
				or not Store._number(feature.get("work"), 0.000000001, 1000000) \
				or not Store._number(feature.get("progress"), 0, float(feature.work)) \
				or not Store._number(feature.get("production"), 0, 1000000) \
				or not feature.get("batch_paid") is bool or not feature.get("status") is String:
			return _fail("CORRUPT_SAVE", "摘要建物內容非法")
		var seen := {}
		for cell: Variant in feature.cells:
			if not Store._integer(cell, 0, Grid.SITE_CELLS * Grid.SITE_CELLS - 1) or seen.has(int(cell)):
				return _fail("CORRUPT_SAVE", "摘要建物占地非法")
			seen[int(cell)] = true
		result.buildings.append({"feature_id": key, "kind": str(feature.kind), "stage": str(feature.stage),
			"cells": feature.cells.size(), "progress": float(feature.progress), "work": float(feature.work),
			"production": float(feature.production), "batch_paid": bool(feature.batch_paid), "status": str(feature.status)})
		var kind := str(feature.kind)
		if not result.counts.has(kind):
			result.counts[kind] = {"planned": 0, "building": 0, "complete": 0}
		result.counts[kind][str(feature.stage)] += 1
	result.visited = true
	result.source_checksum = str(decoded.checksum)
	return result

static func aggregate_building_summaries(summaries: Array[Dictionary]) -> Dictionary:
	# Aggregate the requested visible/visited summaries, not every possible Site.
	# No persisted cache or settlement/building copy exists above SiteStore.
	var scope := ""
	var visited := 0
	var regions := {}
	var versions: Array[String] = []
	var seen := {}
	for summary: Dictionary in summaries:
		if not bool(summary.get("ok", false)):
			return summary
		var current_scope := str(summary.world_instance_id) + "/" + str(summary.slot_id)
		if not scope.is_empty() and scope != current_scope:
			return _fail("INVALID_SLOT", "不可合併不同世界／存檔摘要")
		scope = current_scope
		if seen.has(str(summary.site_id)):
			return _fail("INVALID", "同一 Site 摘要重複")
		seen[str(summary.site_id)] = true
		versions.append(str(summary.site_id) + "=" + str(summary.source_checksum))
		if not bool(summary.visited):
			continue
		visited += 1
		var region_id := str(summary.region_id)
		if not regions.has(region_id):
			regions[region_id] = {"sites": 0, "counts": {}}
		regions[region_id].sites += 1
		for kind: String in summary.counts:
			if not regions[region_id].counts.has(kind):
				regions[region_id].counts[kind] = {"planned": 0, "building": 0, "complete": 0}
			for stage: String in ["planned", "building", "complete"]:
				regions[region_id].counts[kind][stage] += int(summary.counts[kind][stage])
	versions.sort()
	return {"ok": true, "scope": scope, "visited_sites": visited, "regions": regions,
		"source_checksum": JSON.stringify(versions).sha256_text()}


# Original effective surfaces at a Site boundary; query only, never a person handoff.
static func boundary_pair(from_site: Vector2i, from_cell: Vector2i, direction: Vector2i) -> Dictionary:
	if direction not in TerrainData.DIRECTIONS or from_cell.x < 0 or from_cell.y < 0 or from_cell.x >= 100 or from_cell.y >= 100:
		return Runtime.fail("INVALID", "跨界起點或方向非法")
	var outside := from_cell + direction
	if outside.x >= 0 and outside.y >= 0 and outside.x < 100 and outside.y < 100:
		return Runtime.fail("INVALID", "此步仍在原 Site 內")
	# Region northing increases opposite to local map y.
	var to_site := from_site + Vector2i(direction.x, -direction.y)
	return {"ok": true, "site": to_site, "cell": Vector2i(posmod(outside.x, 100), posmod(outside.y, 100))}

static func boundary_surface(data: TerrainData, cell: Vector2i) -> Dictionary:
	if data == null or not data.contains(cell):
		return Runtime.fail("INVALID", "原有效面格位不存在")
	var index := data.index(cell)
	return {"ok": true, "walkable": data.is_walkable(cell), "height": data.effective_height(cell),
		"ramp": int(data.navigation_ramps()[index]), "feature_id": str(data.feature_at[index]) if data.feature_at[index] > 0 else "",
		"navigation_revision": data.navigation_revision}

static func boundary_surfaces_can_step(left: Dictionary, right: Dictionary, direction: Vector2i) -> bool:
	var edge := TerrainData.DIRECTIONS.find(direction)
	if edge < 0 or not bool(left.get("ok", false)) or not bool(right.get("ok", false)) or not bool(left.get("walkable", false)) or not bool(right.get("walkable", false)):
		return false
	var reverse := (edge + 2) % 4
	var a := int(left.ramp)
	var b := int(right.ramp)
	if (a & (1 << (edge + 4))) != 0 or (b & (1 << (reverse + 4))) != 0: return false
	var difference := absi(int(left.height) - int(right.height))
	return difference == 0 or (difference == 1 and (a & (1 << edge)) != 0 and (b & (1 << reverse)) != 0)

func query_boundary_crossing(from_data: TerrainData, from_cell: Vector2i, direction: Vector2i) -> Dictionary:
	var source_position := _coordinate(from_data)
	if not source_position.ok: return source_position
	var pair := boundary_pair(source_position.site, from_cell, direction)
	if not pair.ok: return pair
	var destination: TerrainData
	var path := site_path(pair.site)
	var checksum := ""
	if FileAccess.file_exists(path):
		var loaded := _load_checked(path, pair.site)
		if not loaded.ok: return loaded
		destination = loaded.data
		checksum = FileAccess.get_sha256(path)
	else:
		var fresh: Dictionary = source.make_terrain_data(pair.site.x, pair.site.y)
		if not fresh.get("ok", false): return fresh
		if not _matches_base(fresh.base, pair.site): return Runtime.fail("SAVE_VERSION", "跨界目標版本不同")
		destination = fresh.data
		# An unvisited query projects immutable geography with empty saved changes.
		# It never initializes a Site, inventory, worker, Actor or person.
		destination.site = {}
		Env.rebuild_indexes(destination)
	# Explicitly detach each array and parameters written by boundary refresh.
	# Neither query nor refresh may mutate the active original Site.
	var source_copy := Env.navigation_for_state(from_data, from_data.site)
	source_copy.flags = from_data.flags.duplicate()
	source_copy.ramp_edges = from_data.ramp_edges.duplicate()
	source_copy.cliff_drops = from_data.cliff_drops.duplicate()
	source_copy.parameters = from_data.parameters.duplicate(true)
	var refreshed := _refresh_boundaries(source_copy, source_position.site, destination, pair.site)
	if not refreshed.ok: return refreshed
	refreshed = _refresh_boundaries(destination, pair.site, source_copy, source_position.site)
	if not refreshed.ok: return refreshed
	Env.rebuild_indexes(source_copy)
	Env.rebuild_indexes(destination)
	var left := boundary_surface(source_copy, from_cell)
	var right := boundary_surface(destination, pair.cell)
	if not boundary_surfaces_can_step(left, right, direction):
		return Runtime.fail("UNREACHABLE", "兩側原有效站位、高度或通行邊不相接")
	return {"ok": true, "from_site": source_position.site, "from_cell": from_cell,
		"to_site": pair.site, "to_cell": pair.cell, "source_surface": left, "destination_surface": right,
		"source_site_id": str(from_data.site.id), "destination_site_id": str(destination.parameters.fixed_base.site_id),
		"source_feature_id": str(left.feature_id), "destination_feature_id": str(right.feature_id),
		"destination_path": path if not checksum.is_empty() else "", "destination_checksum": checksum,
		"destination_data": destination}




# Candidate instance methods appended to the EXISTING RegionSaveSlot.
# Requires its effective-boundary methods; no new persistent owner or clock.

func _ground_actor(state: Dictionary, identity: int) -> Dictionary:
	for key: String in state.get("actors", {}):
		var actor: Dictionary = state.actors[key]
		if int(actor.get("person_id", -1)) == identity:
			return {"ok": true, "key": key, "body": actor}
	return fail("NO_TARGET", "原獨立人物不存在")

func _ground_relation_guard(state: Dictionary, identity: int) -> Dictionary:
	if state.has("crowd"): return fail("UNSUPPORTED", "地面跨界首版只接原 GD 獨立人物")
	if state.get("housing", {}).has(str(identity)):
		return fail("RELATION_OPEN", "原人物仍綁定來源住宅，請先離住")
	for key: String in state.get("captivity", {}):
		var relation: Dictionary = state.captivity[key]
		if identity in [int(key), int(relation.captor_id), int(relation.guard_id)]:
			return fail("RELATION_OPEN", "原拘押或看守關係尚未結束")
	for key: String in state.get("escort_orders", {}):
		if int(key) == identity or state.escort_orders[key].captives.has(identity):
			return fail("RELATION_OPEN", "原押送關係尚未結束")
	for actor: Dictionary in state.get("actors", {}).values():
		if int(actor.get("attack_target", 0)) == identity or int(actor.get("rescue_target", 0)) == identity or actor.get("hit_ids", []).has(identity):
			return fail("RELATION_OPEN", "來源仍有攻擊或救助引用")
	for team: Dictionary in state.get("armies", []):
		if int(team.get("player_member", {}).get("id", -1)) == identity or int(team.get("pursuit_target", -1)) == identity or Store._ship_saved_land_references(team, identity):
			return fail("RELATION_OPEN", "原隊伍成員、移動或追擊仍引用此人")
		for row: Dictionary in team.get("units", []):
			if int(row.get("person_id", -1)) == identity or int(row.get("target", -1)) == identity or row.get("hits", []).has(identity):
				return fail("RELATION_OPEN", "原隊伍仍引用此人")
		for rescue: Dictionary in team.get("rescues", []):
			if int(rescue.get("target_id", -1)) == identity:
				return fail("RELATION_OPEN", "原隊伍救助尚未結束")
	for vehicle: Dictionary in state.get("vehicles", {}).values():
		if int(vehicle.get("operator_id", -1)) == identity or vehicle.get("crew_slots", {}).values().has(identity):
			return fail("RELATION_OPEN", "原車船操作或乘員關係尚未結束")
	for corps: Dictionary in state.get("corps", {}).values():
		if int(corps.get("commander_person_id", -1)) == identity:
			return fail("RELATION_OPEN", "原軍團仍引用指揮官")
	for key: String in state.get("person_supply", {}):
		for member: int in Store.Sustain._ids(state.person_supply[key]):
			if int(key) == identity and member != identity or int(key) != identity and member == identity:
				return fail("RELATION_OPEN", "原私人餐份仍與他人共用")
	for supply: Dictionary in state.get("team_supply", {}).values():
		if identity in Store.Sustain._ids(supply.sustain):
			return fail("RELATION_OPEN", "原隊伍餐份仍引用此人")
		var delivery: Dictionary = supply.get("delivery", {})
		if identity in [int(delivery.get("player_id", -1)), int(delivery.get("representative_id", -1))]:
			return fail("RELATION_OPEN", "原補給交付尚未結束")
	return {"ok": true}

func _ground_actor_guard(data: TerrainData, identity: int) -> Dictionary:
	if bool(data.site.get("paused", false)): return fail("PAUSED", "原 Site 暫停時不跨界")
	if identity <= 0 or int(data.site.get("controlled_person_id", -1)) != identity:
		return fail("INVALID", "只允許原受控獨立人物跨界")
	var found := _ground_actor(data.site, identity)
	if not found.ok: return found
	var actor: Dictionary = found.body
	if not TerrainTestCharacter.valid_state(actor, data):
		return fail("CORRUPT_SAVE", "原人物快照非法")
	if float(actor.hp) <= 0.0 or float(actor.knockout_left) > 0.0 or float(actor.movement_left) > 0.0 \
			or bool(actor.get("captive", false)) or bool(actor.get("site_exited", false)) or bool(actor.get("surrender_pending", false)) \
			or bool(actor.get("_getting_up", false)) or bool(actor.appearance.mounted) or actor.has("crowd_handoff") \
			or float(actor.get("action_time", 0.0)) > 0.0 or float(actor.get("_rescue_left", 0.0)) > 0.0 \
			or float(actor.get("_reload_left", 0.0)) > 0.0 or bool(actor.get("guarding", false)) \
			or float(actor.get("guard_transition_left", 0.0)) > 0.0 or float(actor.get("guard_break_left", 0.0)) > 0.0 \
			or float(actor.get("exchange_stagger", 0.0)) > 0.0 or int(actor.get("attack_target", 0)) != 0 \
			or int(actor.get("rescue_target", 0)) != 0 or not actor.get("hit_ids", []).is_empty() \
			or not actor.get("projectiles", []).is_empty() or not str(actor.get("remains_id", "")).is_empty():
		return fail("BUSY", "原獨立人物必須可行動、停穩且沒有未結束作業")
	var activity: Dictionary = data.site.manual if str(found.key) == "player" else data.site.worker
	if not str(activity.get("target", "")).is_empty() or float(activity.get("progress", 0.0)) != 0.0:
		return fail("BUSY", "原人物工作尚未結束")
	var relations := _ground_relation_guard(data.site, identity)
	return found if relations.ok else relations

func _ground_destination(geography: TerrainData, seconds: float) -> Dictionary:
	var data := geography
	if data.site.is_empty():
		if data.spawn_cell == Vector2i(-1, -1): return fail("NO_TARGET", "地面跨界目的地沒有原落腳點")
		# This is an actual visit candidate, never the pure boundary query.
		Env.initialize(data, str(data.parameters.fixed_base.site_id))
		data.site.actor_presence_version = 1
		data.site.actors = {}
		data.site.worker_enabled = false
		var retired := Store.retire_default_worker(data)
		if not retired.ok: return retired
		Runtime.initialize_item_storage(data.site)
	return _settle_cold_candidate(data, seconds)

func _ground_surfaces(source_data: TerrainData, destination_data: TerrainData, request: Dictionary) -> Dictionary:
	var from_data := Env.navigation_for_state(source_data, source_data.site)
	var to_data := Env.navigation_for_state(destination_data, destination_data.site)
	for pair: Array in [[from_data, source_data], [to_data, destination_data]]:
		pair[0].flags = pair[1].flags.duplicate()
		pair[0].ramp_edges = pair[1].ramp_edges.duplicate()
		pair[0].cliff_drops = pair[1].cliff_drops.duplicate()
		pair[0].parameters = pair[1].parameters.duplicate(true)
	var refreshed := _refresh_boundaries(from_data, request.from_site, to_data, request.to_site)
	if not refreshed.ok: return refreshed
	refreshed = _refresh_boundaries(to_data, request.to_site, from_data, request.from_site)
	if not refreshed.ok: return refreshed
	Env.rebuild_indexes(from_data)
	Env.rebuild_indexes(to_data)
	if not boundary_surfaces_can_step(boundary_surface(from_data, request.from_cell), boundary_surface(to_data, request.to_cell), request.direction):
		return fail("UNREACHABLE", "提交時兩側原有效面已不相接")
	for entry: Dictionary in _saved_people(to_data.site).values():
		var body: Dictionary = entry.body
		if body.has("embarked_vehicle_id"): continue
		var cell := Vector2i(int(body.cell[0]), int(body.cell[1]))
		var movement: Array = body.get("movement_from", [-1, -1]) if float(body.get("movement_left", 0.0)) > 0.0 else body.get("destination", [-1, -1])
		var claim := Vector2i(int(movement[0]), int(movement[1]))
		if cell == request.to_cell or claim == request.to_cell:
			return fail("OCCUPIED", "目的格仍由原人物或在途移動保留")
	for vehicle: Dictionary in to_data.site.get("vehicles", {}).values():
		if Store.Vehicles.footprint(to_data, vehicle).has(request.to_cell) or Store.Vehicles.footprint(to_data, vehicle, true).has(request.to_cell):
			return fail("OCCUPIED", "目的格仍由原車船保留")
	return {"ok": true, "source_data": from_data, "destination_data": to_data}

func _ground_transfer_pair(source_data: TerrainData, destination_data: TerrainData, request: Dictionary,
		destination_path: String, live_source: TerrainData = null) -> Dictionary:
	var identity := int(request.person_id)
	var found := _ground_actor_guard(source_data, identity)
	if not found.ok: return found
	if str(found.key) != str(request.actor_key) or Vector2i(int(found.body.cell[0]), int(found.body.cell[1])) != request.from_cell \
			or int(found.body.get("_received_effective_hit", 0)) != int(request.hit_revision):
		return fail("INTERRUPTED", "原人物位置、身分容器或受擊已變")
	if not _safe_part(str(request.get("token", ""))): return fail("INVALID")
	if not is_equal_approx(_site_seconds(source_data), _site_seconds(destination_data)): return fail("TIME_MISMATCH")
	var origin: Dictionary = source_data.site.duplicate(true)
	var fire_capture := _capture_transfer_fire_snapshots(live_source if live_source != null else source_data, origin)
	if not fire_capture.ok: return fire_capture
	var spec := {"person_id": identity, "actor_key": str(found.key), "team_id": 0,
		"controller": "player", "mode": "land", "game_seconds": float(control.logical_game_seconds),
		"family_transfer_guard": region_family_transfer_guard}
	var extracted := RegionTravel.extract(origin, spec, str(request.token))
	if not extracted.ok: return extracted
	if extracted.party.person_ids.size() != 1 or extracted.party.person_ids[0] != identity \
			or not extracted.party.vehicle_ids.is_empty(): return fail("RELATION_OPEN", "原細格跨界僅接單一獨立Actor")
	var nav := Env.navigation_for_state(destination_data, destination_data.site)
	var inserted := RegionTravel.insert(destination_data.site, extracted.party, nav, request.to_cell, destination_path,
		float(control.logical_game_seconds), float(control.logical_game_seconds),
		{"generation": int(_marker.get("generation", 0)) + 1, "family_transfer_guard": region_family_transfer_guard})
	if not inserted.ok: return inserted
	if inserted.leader_cell != request.to_cell: return fail("OCCUPIED", "原細格reservation不允改落其他格")
	var source_candidate := Env.navigation_for_state(source_data, extracted.origin)
	var destination_candidate := Env.navigation_for_state(destination_data, inserted.state)
	source_candidate.set_meta(&"region_bind_source", live_source if live_source != null else source_data)
	destination_candidate.set_meta(&"region_bind_source", destination_data)
	return {"ok": true, "source_data": source_candidate, "destination_data": destination_candidate,
		"mapping": inserted.mapping, "leader_person_id": inserted.leader_person_id, "token": str(request.token)}

# After this replacement _transfer_family is truly unreferenced and removable.
# commit_ground_crossing's return must include pair.mapping/leader_person_id;
# actual bound destination controlled_person_id is the typed mapped identity.
# Neither request.person_id nor historical item.original_owner is rewritten.

func prepare_ground_crossing(source_data: TerrainData, person_id: int, direction: Vector2i) -> Dictionary:
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	if not _marker.get("journey", {}).is_empty() or not _prepared.is_empty(): return fail("BUSY", "同一存檔槽已有原船旅程")
	var coordinate := _coordinate(source_data)
	if not coordinate.ok: return coordinate
	if str(control.active_site_id) != str(source_data.site.id): return fail("CONFLICT", "先綁定此存檔槽唯一活動 Site")
	var window := validate_settlement(source_data.site, control.logical_game_seconds)
	if not window.ok or bool(window.legacy) or float(window.pending) > 0.00001:
		return window if not window.ok else fail("UNSETTLED_SITE", "先完成原活動 Site 時鐘綁定與步進")
	var actor := _ground_actor_guard(source_data, person_id)
	if not actor.ok: return actor
	var cell := Vector2i(int(actor.body.cell[0]), int(actor.body.cell[1]))
	var boundary := query_boundary_crossing(source_data, cell, direction)
	if not boundary.ok: return boundary
	var request := {"token": "ground_" + Crypto.new().generate_random_bytes(16).hex_encode(),
		"person_id": person_id, "actor_key": str(actor.key), "hit_revision": int(actor.body.get("_received_effective_hit", 0)),
		"from_site": coordinate.site, "to_site": boundary.to_site, "from_cell": cell, "to_cell": boundary.to_cell, "direction": direction,
		"generation": int(_marker.get("generation", 0)), "scope": folder, "pin": pin.duplicate(true),
		"departure_game_seconds": float(control.logical_game_seconds), "seconds": TerrainTestCharacter.MOVE_DURATION,
		"destination_path": site_path(boundary.to_site), "destination_checksum": str(boundary.destination_checksum)}
	var destination := _ground_destination(boundary.destination_data, float(control.logical_game_seconds))
	if not destination.ok: return destination
	var surfaces := _ground_surfaces(source_data, destination.data, request)
	if not surfaces.ok: return surfaces
	# Pure ownership preflight. Formal Store validation occurs on latest candidates at commit.
	var pair := _ground_transfer_pair(surfaces.source_data, surfaces.destination_data, request, request.destination_path, source_data)
	if not pair.ok: return pair
	return {"ok": true, "request": request, "seconds": float(request.seconds)}

func commit_ground_crossing(request: Dictionary, source_data: TerrainData, completed_action_seconds: float, bind_guard: Callable) -> Dictionary:
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	if not _safe_part(str(request.get("token", ""))) or str(request.get("scope", "")) != folder or not _same_pin(request.get("pin", {}), pin):
		return fail("INVALID", "地面跨界候選來源非法")
	if _was_committed(str(request.token)): return fail("ALREADY_COMMITTED", "原人物跨界已提交，不重播")
	if not is_finite(completed_action_seconds) or completed_action_seconds + 0.00000001 < TerrainTestCharacter.MOVE_DURATION:
		return fail("INCOMPLETE_JOURNEY", "原 ACTION 跨界一步尚未完成")
	if int(request.get("generation", -1)) != int(_marker.get("generation", 0)) or not _marker.get("journey", {}).is_empty() or not _prepared.is_empty():
		return fail("CONFLICT", "準備後存檔槽已有另一提交或旅程")
	var coordinate := _coordinate(source_data)
	if not coordinate.ok or coordinate.site != request.from_site or str(control.active_site_id) != str(source_data.site.id):
		return fail("CONFLICT", "原跨界來源已更換")
	if float(control.logical_game_seconds) <= float(request.departure_game_seconds):
		return fail("TIME_MISMATCH", "須先記錄已完成的原 shared step，不能零時間跨界")
	var window := validate_settlement(source_data.site, control.logical_game_seconds)
	if not window.ok or bool(window.legacy) or float(window.pending) > 0.00001:
		return window if not window.ok else fail("UNSETTLED_SITE", "來源尚未完成原 shared step")
	var destination_path := site_path(request.to_site)
	var checksum := FileAccess.get_sha256(destination_path) if FileAccess.file_exists(destination_path) else ""
	if destination_path != str(request.destination_path) or checksum != str(request.destination_checksum):
		return fail("CONFLICT", "目的地在準備後已有新保存")
	var boundary := query_boundary_crossing(source_data, request.from_cell, request.direction)
	if not boundary.ok: return boundary
	if boundary.to_site != request.to_site or boundary.to_cell != request.to_cell:
		return fail("INVALID", "候選不是原相鄰邊界")
	var destination := _ground_destination(boundary.destination_data, float(control.logical_game_seconds))
	if not destination.ok: return destination
	var surfaces := _ground_surfaces(source_data, destination.data, request)
	if not surfaces.ok: return surfaces
	var generation := int(_marker.get("generation", 0)) + 1
	var from_path := _generation_path(generation, request.from_site)
	var to_path := _generation_path(generation, request.to_site)
	var pair := _ground_transfer_pair(surfaces.source_data, surfaces.destination_data, request, to_path, source_data)
	if not pair.ok: return pair
	var source_checked := _save_checked(pair.source_data, request.from_site, from_path)
	if not source_checked.ok: return source_checked
	var destination_checked := _save_checked(pair.destination_data, request.to_site, to_path)
	if not destination_checked.ok: return destination_checked
	if not bind_guard.is_valid(): return fail("BIND_GUARD", "缺少原場景完整綁定預檢，未發布")
	var ready: Variant = bind_guard.call(destination_checked.data)
	if not ready is Dictionary or not bool(ready.get("ok", false)):
		return ready if ready is Dictionary else fail("BIND_GUARD", "原場景綁定預檢未完成")
	var sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	sites[_site_key(request.from_site)] = _file_entry(from_path)
	sites[_site_key(request.to_site)] = _file_entry(to_path)
	var clock := {"logical_game_seconds": float(control.logical_game_seconds), "active_site_id": str(pair.destination_data.site.id)}
	var published := _publish(sites, clock, str(request.token))
	if not published.ok: return published
	return {"ok": true, "source_data": source_checked.data, "destination_data": destination_checked.data,
		"active_site": request.to_site, "generation": published.generation, "token": str(request.token),
		"mapping": pair.mapping, "leader_person_id": pair.leader_person_id}

# OUTPUT ONLY / NOT RUN. Append to the ORIGINAL RegionSaveSlot owner.
# Journal records completed original intervals. It never advances simulation.
const FIRE_CLOCK_VERSION := 1
const FIRE_CLOCK_FIELDS := ["version", "epoch", "action_seconds", "sequence", "base_game_seconds", "journal", "index"]
const FIRE_CLOCK_BASE_FIELDS := ["base_sequence", "base_action_seconds"]
const FIRE_CLOCK_SEGMENT_FIELDS := ["first_sequence", "last_sequence", "action_begin", "action_end", "game_begin", "game_end", "scale", "tactical_seconds", "steps"]
const FIRE_SETTLEMENT_FIELDS := ["version", "epoch", "sequence", "action_seconds", "game_seconds"]
var _fire_cold_candidates: Dictionary = {} # Original restored Site candidates, never fuel/person copies.
var _fire_sync_target: Dictionary = {} # Fixed published journal target while original replay is pending.
var _fire_sync_flushing := false

static func validate_fire_clock(value: Variant, world_game: Variant) -> Dictionary:
	if not value is Dictionary or value.size() not in [FIRE_CLOCK_FIELDS.size(), FIRE_CLOCK_FIELDS.size() + FIRE_CLOCK_BASE_FIELDS.size()] \
		or not _seconds(world_game): return _fail("CORRUPT_FIRE_CLOCK", "火攻共同時間欄位")
	for field: String in FIRE_CLOCK_FIELDS:
		if not value.has(field): return _fail("CORRUPT_FIRE_CLOCK", "火攻共同時間欄位")
	var has_base_sequence: bool = value.has("base_sequence")
	var has_base_action: bool = value.has("base_action_seconds")
	if has_base_sequence != has_base_action: return _fail("CORRUPT_FIRE_CLOCK", "火攻歷程基點欄位")
	if has_base_sequence and value.size() != FIRE_CLOCK_FIELDS.size() + FIRE_CLOCK_BASE_FIELDS.size() \
		or not has_base_sequence and value.size() != FIRE_CLOCK_FIELDS.size(): return _fail("CORRUPT_FIRE_CLOCK", "火攻歷程基點欄位")
	if not _whole(value.version, 1, FIRE_CLOCK_VERSION) or not value.epoch is String or value.epoch.is_empty() \
		or not _seconds(value.action_seconds) or not _whole(value.sequence, 0, 2147483647) \
		or not _seconds(value.base_game_seconds) or not value.journal is Array or value.journal.size() > 65536 \
		or not value.index is Dictionary or value.index.size() > 65536: return _fail("CORRUPT_FIRE_CLOCK", "火攻共同時間版本")
	var base_sequence: int = int(value.get("base_sequence", 0))
	var base_action: float = float(value.get("base_action_seconds", 0.0))
	if not _whole(base_sequence, 0, int(value.sequence)) or not _seconds(base_action) or base_action > float(value.action_seconds) \
		or float(value.base_game_seconds) > float(world_game): return _fail("CORRUPT_FIRE_CLOCK", "火攻歷程基點非法")
	var previous_sequence := base_sequence
	var previous_action := base_action
	var previous_game := float(value.base_game_seconds)
	for row: Variant in value.journal:
		if not row is Dictionary or row.size() != FIRE_CLOCK_SEGMENT_FIELDS.size(): return _fail("CORRUPT_FIRE_JOURNAL", "區間欄位")
		for field: String in FIRE_CLOCK_SEGMENT_FIELDS:
			if not row.has(field): return _fail("CORRUPT_FIRE_JOURNAL", "區間欄位")
		for field: String in ["action_begin", "action_end", "game_begin", "game_end", "tactical_seconds", "scale"]:
			if not _seconds(row[field]): return _fail("CORRUPT_FIRE_JOURNAL", "區間非有限秒")
		if not _whole(row.first_sequence, 1, 2147483647) or not _whole(row.last_sequence, 1, 2147483647) \
			or not _whole(row.steps, 1, 2147483647) or int(row.first_sequence) != previous_sequence + 1 \
			or int(row.last_sequence) - int(row.first_sequence) + 1 != int(row.steps) \
			or float(row.action_begin) != previous_action or float(row.game_begin) != previous_game \
			or float(row.action_end) <= previous_action or float(row.game_end) <= previous_game \
			or float(row.scale) not in [0.5, 1.0, 2.0, 4.0] \
			or float(row.tactical_seconds) > float(row.action_end) - previous_action + 0.000000001:
			return _fail("CORRUPT_FIRE_JOURNAL", "區間不連續或倍率非法")
		var expected := (float(row.tactical_seconds) + (float(row.action_end) - previous_action - float(row.tactical_seconds)) * 60.0) * float(row.scale)
		if absf(float(row.game_end) - previous_game - expected) > maxf(0.00000001, expected * 0.000000001): return _fail("CORRUPT_FIRE_JOURNAL", "雙時間不一致")
		previous_sequence = int(row.last_sequence)
		previous_action = float(row.action_end)
		previous_game = float(row.game_end)
	if previous_sequence != int(value.sequence) or previous_action != float(value.action_seconds) or previous_game != float(world_game): return _fail("CORRUPT_FIRE_JOURNAL", "共同完成端點不一致")
	for identity: Variant in value.index:
		var row: Variant = value.index[identity]
		if not identity is String or identity.is_empty() or not row is Dictionary or row.size() not in [5, 6] \
			or not row.get("coordinate") is Array or row.coordinate.size() != 2 \
			or not _whole(row.coordinate[0], -10000000, 10000000) or not _whole(row.coordinate[1], -10000000, 10000000) \
			or not row.get("active") is bool or not _whole(row.get("sequence"), base_sequence, previous_sequence) \
			or row.size() == 6 and not row.get("fire_active") is bool \
			or not _seconds(row.get("action_seconds")) or not _seconds(row.get("game_seconds")) \
			or float(row.action_seconds) > previous_action or float(row.game_seconds) > previous_game:
			return _fail("CORRUPT_FIRE_INDEX", "原 Site 活動索引非法")
	return {"ok": true}

static func validate_fire_settlement(state: Dictionary, clock: Dictionary) -> Dictionary:
	var value: Variant = state.get("fire_settlement")
	if not value is Dictionary or value.size() != FIRE_SETTLEMENT_FIELDS.size(): return _fail("MISSING_FIRE_HISTORY", "火攻地點缺少雙時間水印")
	for field: String in FIRE_SETTLEMENT_FIELDS:
		if not value.has(field): return _fail("CORRUPT_FIRE_SETTLEMENT", "火攻結算欄位")
	if not _whole(value.version, 1, 1) or value.epoch != clock.epoch \
		or not _whole(value.sequence, 0, int(clock.sequence)) or not _seconds(value.action_seconds) or not _seconds(value.game_seconds) \
		or float(value.action_seconds) > float(clock.action_seconds): return _fail("CORRUPT_FIRE_SETTLEMENT", "火攻結算版本或端點")
	var base_sequence := int(clock.get("base_sequence", 0))
	var previous_game := float(clock.base_game_seconds)
	var previous_action := float(clock.get("base_action_seconds", 0.0))
	if int(value.sequence) < base_sequence: return _fail("MISSING_FIRE_HISTORY", "Site 水印早於保留歷程")
	if int(value.sequence) == base_sequence:
		if absf(float(value.action_seconds) - previous_action) > 0.00000001 or absf(float(value.game_seconds) - previous_game) > 0.00000001: return _fail("CORRUPT_FIRE_SETTLEMENT", "原 epoch 基點")
		return {"ok": true}
	for row: Dictionary in clock.journal:
		if int(value.sequence) > int(row.last_sequence): continue
		# Aggregation is permitted only for uniform full tactical/peace segments;
		# every original fixed slice boundary remains recoverable from steps.
		var offset := int(value.sequence) - int(row.first_sequence) + 1
		var ratio := float(offset) / int(row.steps)
		previous_action = lerpf(float(row.action_begin), float(row.action_end), ratio)
		previous_game = lerpf(float(row.game_begin), float(row.game_end), ratio)
		if absf(float(value.action_seconds) - previous_action) > 0.00000001 or absf(float(value.game_seconds) - previous_game) > 0.00000001: return _fail("CORRUPT_FIRE_SETTLEMENT", "水印不在原完成區間")
		return {"ok": true}
	return _fail("MISSING_FIRE_HISTORY", "火攻結算歷程缺失")

static func fire_replay_segments(state: Dictionary, clock: Dictionary, world_game_seconds: float) -> Dictionary:
	var clock_check := validate_fire_clock(clock, world_game_seconds)
	if not clock_check.ok: return clock_check
	var settlement_check := validate_fire_settlement(state, clock)
	if not settlement_check.ok: return settlement_check
	var sequence := int(state.fire_settlement.sequence)
	var segments: Array[Dictionary] = []
	var next_sequence := sequence + 1
	for row: Dictionary in clock.journal:
		if int(row.last_sequence) < next_sequence: continue
		var skip := maxi(0, next_sequence - int(row.first_sequence))
		var steps := int(row.steps) - skip
		if steps <= 0: continue
		var action_per_step := (float(row.action_end) - float(row.action_begin)) / int(row.steps)
		var game_per_step := (float(row.game_end) - float(row.game_begin)) / int(row.steps)
		var tactical_per_step := float(row.tactical_seconds) / int(row.steps)
		var action_begin := float(row.action_begin) + action_per_step * skip
		var game_begin := float(row.game_begin) + game_per_step * skip
		segments.append({"first_sequence": next_sequence, "last_sequence": int(row.last_sequence),
			"action_begin": action_begin, "action_end": float(row.action_end),
			"game_begin": game_begin, "game_end": float(row.game_end), "scale": float(row.scale),
			"tactical_seconds": tactical_per_step * steps, "steps": steps})
		next_sequence = int(row.last_sequence) + 1
	if next_sequence != int(clock.sequence) + 1: return _fail("MISSING_FIRE_HISTORY", "冷地點雙時鐘區間不連續")
	return {"ok": true, "from_sequence": sequence, "to_sequence": int(clock.sequence), "segments": segments}

static func preview_fire_interval(clock: Dictionary, game_begin: float, action_seconds: float, scale: float, tactical_seconds: float) -> Dictionary:
	var clock_check := validate_fire_clock(clock, game_begin)
	if not clock_check.ok: return clock_check
	if not _seconds(action_seconds) or action_seconds <= 0.0 \
		or action_seconds > 1.0 / 30.0 + 0.000000001 or scale not in [0.5, 1.0, 2.0, 4.0] \
		or not _seconds(tactical_seconds) or tactical_seconds > action_seconds or int(clock.sequence) >= 2147483647:
		return _fail("INVALID_FIRE_INTERVAL", "原 shared-step 區間非法")
	var action_end := float(clock.action_seconds) + action_seconds
	var game_delta := (tactical_seconds + (action_seconds - tactical_seconds) * 60.0) * scale
	var game_end := game_begin + game_delta
	if not is_finite(action_end) or action_end <= float(clock.action_seconds) or not is_finite(game_end) or game_end <= game_begin: return _fail("INVALID_FIRE_INTERVAL", "時間不可表示")
	return {"ok": true, "epoch": str(clock.epoch), "sequence": int(clock.sequence) + 1,
		"action_begin": float(clock.action_seconds), "action_end": action_end,
		"game_begin": game_begin, "game_end": game_end, "scale": scale, "tactical_seconds": tactical_seconds}

static func append_completed_fire_interval(clock: Dictionary, interval: Dictionary) -> void:
	# Prevalidated interval only, called immediately AFTER the original game's
	# single publisher succeeds. No callbacks, filesystem writes or second tick.
	var row := {"first_sequence": int(interval.sequence), "last_sequence": int(interval.sequence),
		"action_begin": float(interval.action_begin), "action_end": float(interval.action_end),
		"game_begin": float(interval.game_begin), "game_end": float(interval.game_end),
		"scale": float(interval.scale), "tactical_seconds": float(interval.tactical_seconds), "steps": 1}
	var journal: Array = clock.journal
	if not journal.is_empty():
		var last: Dictionary = journal.back()
		var old_action := (float(last.action_end) - float(last.action_begin)) / int(last.steps)
		var delta := float(interval.action_end) - float(interval.action_begin)
		var old_tactical := float(last.tactical_seconds) / int(last.steps)
		var uniform := (old_tactical == 0.0 and float(interval.tactical_seconds) == 0.0) \
			or (absf(old_tactical - old_action) < 0.0000000001 and absf(float(interval.tactical_seconds) - delta) < 0.0000000001)
		if uniform and float(last.scale) == float(interval.scale) and absf(old_action - delta) < 0.0000000001:
			last.last_sequence = int(interval.sequence)
			last.action_end = float(interval.action_end)
			last.game_end = float(interval.game_end)
			last.tactical_seconds = float(last.tactical_seconds) + float(interval.tactical_seconds)
			last.steps = int(last.steps) + 1
		else: journal.append(row)
	else: journal.append(row)
	clock.action_seconds = float(interval.action_end)
	clock.sequence = int(interval.sequence)

static func prune_fire_clock_prefix(clock: Dictionary) -> int:
	# Every indexed Fire Site must have reached the prefix; a dormant old Site pins it safely.
	if not clock is Dictionary or not clock.get("index") is Dictionary or clock.index.is_empty(): return 0
	var latest := int(clock.sequence)
	var through := latest
	for value: Variant in clock.index.values():
		if not value is Dictionary or not _whole(value.get("sequence"), 0, latest): return 0
		through = mini(through, int(value.sequence))
	var base_sequence := int(clock.get("base_sequence", 0))
	if through <= base_sequence: return 0
	var base_action := float(clock.get("base_action_seconds", 0.0))
	var base_game := float(clock.base_game_seconds)
	var retained: Array = []
	for source_entry: Variant in clock.journal:
		if not source_entry is Dictionary: return 0
		var row: Dictionary = source_entry.duplicate(true)
		if int(row.last_sequence) <= through:
			base_action = float(row.action_end)
			base_game = float(row.game_end)
			continue
		if int(row.first_sequence) <= through:
			var old_steps := int(row.steps)
			var skipped := through - int(row.first_sequence) + 1
			var remaining := old_steps - skipped
			var ratio := float(skipped) / old_steps
			base_action = lerpf(float(row.action_begin), float(row.action_end), ratio)
			base_game = lerpf(float(row.game_begin), float(row.game_end), ratio)
			row.first_sequence = through + 1
			row.action_begin = base_action
			row.game_begin = base_game
			row.steps = remaining
			row.tactical_seconds = float(row.tactical_seconds) / old_steps * remaining
		retained.append(row)
	clock.base_sequence = through
	clock.base_action_seconds = base_action
	clock.base_game_seconds = base_game
	clock.journal = retained
	return through - base_sequence

static func record_completed_fire_replay(state: Dictionary, interval: Dictionary) -> void:
	# The original replay ran all owners already; this stamps its actual result.
	# Cold replay never calls the world's time publisher or appends its journal.
	state.fire_settlement = {"version": 1, "epoch": str(interval.epoch), "sequence": int(interval.sequence),
		"action_seconds": float(interval.action_end), "game_seconds": float(interval.game_end)}
	state[SETTLEMENT_FIELD] = {"version": 1, "last_settled_game_seconds": float(interval.game_end)}


# ---------------------------------------------------------------------------
# Region travel (R1). While a party travels no Site is active; the party's
# records live only in its checksummed party document, the commit record's
# `journey` holds its position/plan, and advance_region_travel is the single
# publisher of logical_game_seconds. See RegionTravel / RegionRoute.
# ---------------------------------------------------------------------------
const TRAVEL_JOURNEY_FIELDS := ["version", "kind", "token", "party_path", "party_sha256", "departure_game_seconds",
	"origin", "position", "plan_path", "plan_sha256", "plan_started_game_seconds", "plans"]
var _travel_party_cache: Dictionary = {}
var _travel_plan_cache: Dictionary = {}
var _travel_party_runtime: Dictionary = {}
var _travel_party_runtime_token := ""

static func is_region_travel(journey: Variant) -> bool:
	return journey is Dictionary and str(journey.get("kind", "")) == RegionTravel.KIND

static func _travel_relative(value: Variant, token: String) -> bool:
	return value is String and (str(value).is_empty() or str(value).begins_with("travel/%s/" % token)) \
		and not str(value).contains("..") and not str(value).contains("\\")

static func _normalize_travel_journey(value: Dictionary) -> Dictionary:
	if value.size() != TRAVEL_JOURNEY_FIELDS.size(): return fail("CORRUPT_SAVE", "旅隊紀錄欄位")
	for field: String in TRAVEL_JOURNEY_FIELDS:
		if not value.has(field): return fail("CORRUPT_SAVE", "旅隊紀錄欄位")
	var token := str(value.token)
	if not _whole(value.version, 1, 1) or not _safe_part(token) or not _travel_relative(value.party_path, token) \
			or str(value.party_path).is_empty() or not _travel_relative(value.plan_path, token) \
			or not value.party_sha256 is String or str(value.party_sha256).length() != 64 \
			or not value.plan_sha256 is String or str(value.plan_path).is_empty() != str(value.plan_sha256).is_empty() \
			or not _seconds(value.departure_game_seconds) or not _seconds(value.plan_started_game_seconds) \
			or float(value.plan_started_game_seconds) < float(value.departure_game_seconds) \
			or not _whole(value.plans, 0, 1000000):
		return fail("CORRUPT_SAVE", "旅隊紀錄版本／檔案／時間")
	if not value.origin is Array or value.origin.size() != 2 or not _whole(value.origin[0], -10000000, 10000000) or not _whole(value.origin[1], -10000000, 10000000):
		return fail("CORRUPT_SAVE", "旅隊出發地")
	var position: Variant = value.position
	if not position is Dictionary or position.size() != 2 or not position.get("site") is Array or position.site.size() != 2 \
			or not _whole(position.site[0], -10000000, 10000000) or not _whole(position.site[1], -10000000, 10000000) \
			or not _whole(position.get("component"), 0, 253):
		return fail("CORRUPT_SAVE", "旅隊位置")
	return {"ok": true, "journey": value.duplicate(true)}

func region_travel_journey() -> Dictionary:
	var journey: Dictionary = _marker.get("journey", {})
	return journey.duplicate(true) if is_region_travel(journey) else {}

func _travel_document(relative: String, sha256: String, cache: Dictionary) -> Dictionary:
	if cache.has(relative) and str(cache[relative].sha) == sha256: return {"ok": true, "payload": cache[relative].payload}
	var path := folder.path_join(relative)
	if FileAccess.get_sha256(path) != sha256: return fail("CORRUPT_SAVE", "旅隊文件缺失或已變更")
	var document := _read_document(path, 64 * 1024 * 1024)
	if not document.ok: return document
	cache[relative] = {"sha": sha256, "payload": document.payload}
	return document

func region_travel_party() -> Dictionary:
	var journey := region_travel_journey()
	if journey.is_empty(): return fail("NO_TARGET", "沒有旅隊")
	if _travel_party_runtime_token == str(journey.token) and not _travel_party_runtime.is_empty():
		return {"ok": true, "party": _travel_party_runtime}
	var document := _travel_document(str(journey.party_path), str(journey.party_sha256), _travel_party_cache)
	if not document.ok: return document
	var payload: Dictionary = document.payload
	if str(payload.get("token", "")) != str(journey.token) or not _same_pin(payload.get("pin"), pin) 			or payload.get("encoding") != "godot_var_v1" or not payload.get("party") is String:
		return fail("CORRUPT_SAVE", "旅隊文件與存檔槽不符")
	# Exact Variant encoding: the party's ints/floats return as the Site held them.
	var party: Variant = bytes_to_var(Marshalls.base64_to_raw(str(payload.party)))
	if not party is Dictionary or str(party.get("party_id", "")) != str(journey.token) or not party.get("content") is Dictionary:
		return fail("CORRUPT_SAVE", "旅隊內容無法解碼")
	_travel_party_runtime = party
	_travel_party_runtime_token = str(journey.token)
	return {"ok": true, "party": party}

func region_travel_plan() -> Dictionary:
	var journey := region_travel_journey()
	if journey.is_empty(): return fail("NO_TARGET", "沒有旅隊")
	if str(journey.plan_path).is_empty(): return {"ok": true, "plan": {}}
	var document := _travel_document(str(journey.plan_path), str(journey.plan_sha256), _travel_plan_cache)
	if not document.ok: return document
	var plan: Dictionary = document.payload
	if str(plan.get("token", "")) != str(journey.token) or not plan.get("steps") is Array or not plan.get("seconds") is Array \
			or plan.steps.size() != plan.seconds.size() or plan.steps.size() < 2:
		return fail("CORRUPT_SAVE", "旅隊路線文件")
	return {"ok": true, "plan": plan}

## Where the party is now: the route step being crossed, or its idle node.
func region_travel_status() -> Dictionary:
	var journey := region_travel_journey()
	if journey.is_empty(): return {"ok": true, "pending": false}
	var planned := region_travel_plan()
	if not planned.ok: return planned
	var loaded := region_travel_party()
	if not loaded.ok: return loaded
	var party: Dictionary = loaded.party
	var plan: Dictionary = planned.plan
	var now := float(control.logical_game_seconds)
	var upkeep: Dictionary = party.get("upkeep", {})
	var pending_life: Array = upkeep.get("events", []).filter(func(event: Dictionary) -> bool: return str(event.get("status", "")) == "pending")
	var status := {"ok": true, "pending": true, "token": str(journey.token), "journey": journey,
		"departure_game_seconds": float(journey.departure_game_seconds), "now": now,
		"elapsed_game_seconds": now - float(journey.departure_game_seconds),
		"site": Vector2i(int(journey.position.site[0]), int(journey.position.site[1])),
		"component": int(journey.position.component), "plan": plan, "moving": false, "arrived": false,
		"step_index": 0, "fraction": 0.0, "remaining_game_seconds": 0.0,
		"barrier": not pending_life.is_empty(), "life_events": pending_life, "resting": bool(upkeep.get("resting", false)),
		"blocked_reason": str(upkeep.get("blocked_reason", "")), "remaining_metres": 0.0}
	if plan.is_empty():
		if status.barrier:
			status.destination = status.site
			status.arrived = true
		return region_mode_stop_status(party, status)
	if str(plan.get("mode", "land")) == "sea":
		status.destination = Vector2i(int(plan.steps.back().site[0]), int(plan.steps.back().site[1]))
		var sea := region_sea_travel_status(plan, party, status)
		if not sea.ok: return sea
		if sea.barrier:
			sea.destination = sea.site
			sea.arrived = true
			sea.moving = false
		return region_mode_stop_status(party, sea)
	var distance := float(upkeep.get("distance", 0.0)) if str(upkeep.get("plan_id", "")) == str(journey.plan_path) else 0.0
	if upkeep.is_empty(): distance = minf(float(plan.metres), maxf(0.0, now - float(journey.plan_started_game_seconds)) * float(plan.speed_mps))
	status.remaining_metres = maxf(0.0, float(plan.metres) - distance)
	status.remaining_game_seconds = status.remaining_metres / maxf(0.000001, float(party.get("speed_mps", RegionTravel.WALK_MPS)))
	status.destination = Vector2i(int(plan.steps.back().site[0]), int(plan.steps.back().site[1]))
	var traversed := 0.0
	for index: int in range(plan.steps.size()):
		var step: Dictionary = plan.steps[index]
		var end := traversed + float(step.metres)
		if distance < end - 0.0000001:
			status.site = Vector2i(int(step.site[0]), int(step.site[1]))
			status.component = int(step.component)
			status.step_index = index
			status.fraction = clampf((distance - traversed) / maxf(0.000001, float(step.metres)), 0.0, 1.0)
			break
		traversed = end
		status.site = Vector2i(int(step.site[0]), int(step.site[1]))
		status.component = int(step.component)
		status.step_index = index
		status.fraction = 1.0
	if status.barrier:
		# Accepted life effects go to the original bodies in this actual Site.
		status.destination = status.site
		status.arrived = true
		return region_mode_stop_status(party, status)
	status.arrived = status.remaining_metres <= 0.0000001
	status.moving = not status.arrived
	return region_mode_stop_status(party, status)

func begin_region_travel(source_data: TerrainData, spec: Dictionary, start_component: int) -> Dictionary:
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	if not _marker.get("journey", {}).is_empty() or not _prepared.is_empty(): return fail("BUSY", "存檔槽已有旅程")
	var coordinate := _coordinate(source_data)
	if not coordinate.ok: return coordinate
	var from: Vector2i = coordinate.site
	if str(control.active_site_id) != str(source_data.site.id): return fail("CONFLICT", "來源不是此存檔槽唯一活動地點")
	var window := validate_settlement(source_data.site, control.logical_game_seconds)
	if not window.ok or bool(window.legacy) or float(window.pending) > 0.00001:
		return window if not window.ok else fail("UNSETTLED_SITE", "來源尚未完成原共同步進")
	if start_component < 0 or start_component > 253: return fail("NO_ROUTE", "出發位置沒有可走出此地的通道")
	for row: Dictionary in control.get("fire_clock", {}).get("index", {}).values():
		if bool(row.get("fire_active", false)): return fail("BUSY", "仍有火場在燃燒；火勢結束前不能整隊出發")
	if Runtime.fire_active(source_data) or not source_data.site.get("fire", {}).is_empty():
		return fail("BUSY", "此地仍有火勢")
	var token := "travel_" + Crypto.new().generate_random_bytes(16).hex_encode()
	var captured := source_data.site.duplicate(true)
	var fire_capture := _capture_transfer_fire_snapshots(source_data, captured)
	if not fire_capture.ok: return fire_capture
	var extraction_spec := spec.duplicate(true)
	extraction_spec.game_seconds = float(control.logical_game_seconds)
	var extracted := RegionTravel.extract(captured, extraction_spec, token)
	if not extracted.ok: return extracted
	var candidate := Env.navigation_for_state(source_data, extracted.origin)
	for hook: StringName in [&"siege_event_guard", &"fire_event_guard", &"fire_transport_snapshot", &"fire_owner_snapshot",
		&"fire_owner_checkpoint", &"fire_pending_projectile_query", &"site_garrison_lab", &"ship_journey_active",
		&"region_operation_pending", &"ship_vehicle_in_journey"]:
		if candidate.has_meta(hook): candidate.remove_meta(hook)
	var generation := int(_marker.get("generation", 0)) + 1
	var from_path := _generation_path(generation, from)
	var checked := _save_checked(candidate, from, from_path)
	if not checked.ok: return checked
	var party_relative := "travel/%s/party.json" % token
	var written := _write_new_document(folder.path_join(party_relative), {"version": 1, "token": token, "pin": pin.duplicate(true),
		"encoding": "godot_var_v1", "party": Marshalls.raw_to_base64(var_to_bytes(extracted.party))})
	if not written.ok: return written
	var next_clock := control.duplicate(true)
	var fire_clock: Dictionary = next_clock.get("fire_clock", {})
	var source_id := str(source_data.site.id)
	if checked.data.site.has("fire_settlement") and fire_clock.get("index") is Dictionary:
		var settlement: Dictionary = checked.data.site.fire_settlement
		fire_clock.index[source_id] = {"coordinate": [from.x, from.y], "active": false, "fire_active": false,
			"sequence": int(settlement.sequence), "action_seconds": float(settlement.action_seconds), "game_seconds": float(settlement.game_seconds)}
	next_clock.active_site_id = ""
	var now := float(control.logical_game_seconds)
	var journey := {"version": 1, "kind": RegionTravel.KIND, "token": token, "party_path": party_relative,
		"party_sha256": FileAccess.get_sha256(folder.path_join(party_relative)), "departure_game_seconds": now,
		"origin": [from.x, from.y], "position": {"site": [from.x, from.y], "component": start_component},
		"plan_path": "", "plan_sha256": "", "plan_started_game_seconds": now, "plans": 0}
	var sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	sites[_site_key(from)] = _file_entry(from_path)
	var published := _publish(sites, next_clock, str(_marker.get("transfer_token", "")), journey)
	if not published.ok: return published
	_travel_party_runtime = extracted.party
	_travel_party_runtime_token = token
	return {"ok": true, "token": token, "party": extracted.party, "source_data": checked.data,
		"vacated_housing": extracted.vacated_housing, "generation": published.generation}

## Commit a new route (only while stopped). Its first step is the party's node.
func set_region_travel_plan(steps: Array) -> Dictionary:
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	var status := region_travel_status()
	if not status.ok: return status
	if not bool(status.get("pending", false)): return fail("NO_TARGET", "沒有旅隊")
	if bool(status.moving): return fail("BUSY", "旅隊行進中；先停下再改目的地")
	if steps.size() < 2: return fail("INVALID", "路線至少要有出發與目的地")
	var first: Dictionary = steps[0]
	if Vector2i(int(first.site[0]), int(first.site[1])) != status.site or int(first.component) != int(status.component) or int(first.edge) != -1:
		return fail("INVALID", "路線必須從旅隊目前位置開始")
	var route_context := prepare_region_route_context(null, region_travel_party().get("party", {}))
	if not route_context.ok: return route_context
	var verified := RegionRoute.verify_steps(source, steps, route_context.context)
	if not verified.ok: return verified
	var party := region_travel_party()
	if not party.ok: return party
	var speed := float(party.party.get("speed_mps", RegionTravel.WALK_MPS))
	if not is_finite(speed) or speed <= 0.0: return fail("CORRUPT_SAVE", "旅隊速度")
	var seconds: Array = []
	var total := 0.0
	var metres := 0.0
	for step: Dictionary in steps:
		if not _seconds(step.get("metres")): return fail("INVALID", "路線距離")
		metres += float(step.metres)
		total += float(step.metres) / speed
		seconds.append(total)
	var journey := region_travel_journey()
	var number := int(journey.plans) + 1
	var relative := "travel/%s/plan_%06d.json" % [str(journey.token), number]
	var last: Dictionary = steps.back()
	var plan := {"version": 1, "token": str(journey.token), "steps": steps.duplicate(true), "seconds": seconds,
		"metres": metres, "speed_mps": speed, "destination": [int(last.site[0]), int(last.site[1])]}
	var written := _write_new_document(folder.path_join(relative), plan)
	if not written.ok: return written
	journey.position = {"site": [status.site.x, status.site.y], "component": int(status.component)}
	journey.plan_path = relative
	journey.plan_sha256 = FileAccess.get_sha256(folder.path_join(relative))
	journey.plan_started_game_seconds = float(control.logical_game_seconds)
	journey.plans = number
	var published := _publish(_marker.get("sites", {}), control, str(_marker.get("transfer_token", "")), journey)
	if not published.ok: return published
	party.party.upkeep["plan_id"] = relative
	party.party.upkeep["distance"] = 0.0
	return {"ok": true, "plan": plan, "game_seconds": total}

## Drop the route at the party's current node (manual stop/reroute).
func stop_region_travel() -> Dictionary:
	var status := region_travel_status()
	if not status.ok or not bool(status.get("pending", false)): return status if not status.ok else fail("NO_TARGET", "沒有旅隊")
	if bool(status.arrived): return {"ok": true, "arrived": true}
	var journey := region_travel_journey()
	journey.position = {"site": [status.site.x, status.site.y], "component": int(status.component)}
	journey.plan_path = ""
	journey.plan_sha256 = ""
	journey.plan_started_game_seconds = float(control.logical_game_seconds)
	return _publish(_marker.get("sites", {}), control, str(_marker.get("transfer_token", "")), journey)

## The only clock publisher while travelling: whole peace-time steps of the
## fire journal (8 game seconds each), never past the route's arrival.
func advance_region_travel(max_steps: int) -> Dictionary:
	var initial := region_travel_status()
	if not initial.ok: return initial
	if not initial.get("pending", false): return fail("NO_TARGET")
	if str(initial.get("mode", "land")) == "sea": return advance_region_sea_travel(max_steps)
	if not region_original_travel_interval.is_valid() or not region_original_party_progress.is_valid():
		return fail("MISSING_REGION_ADAPTER", "缺原所有Site／party共同旅行區間主人")
	var before := float(control.logical_game_seconds)
	var count := 0
	for _index: int in range(clampi(max_steps, 0, 100000)):
		var status := region_travel_status()
		if not status.ok: return status
		if bool(status.arrived) or not bool(status.moving) or not region_player_barrier().is_empty(): break
		var loaded := region_travel_party()
		if not loaded.ok: return loaded
		var party: Dictionary = loaded.party
		var candidate := func(interval: Dictionary) -> Dictionary:
			return _region_player_land_candidate(party, status, interval)
		var accepted: Variant = region_original_travel_interval.call({"token": str(status.token), "party": party,
			"maximum_action_seconds": RegionTravel.STEP_ACTION_SECONDS, "scale": RegionTravel.STEP_SCALE,
			"candidate": candidate, "party_progress": region_original_party_progress})
		if not accepted is Dictionary: return fail("INVALID_REGION_RECEIPT")
		var committed := _region_accept_player_travel_interval(str(status.token), accepted)
		if not committed.ok: return committed
		if committed.get("pending", false): break
		count += 1
		if not committed.outcome.get("events", []).is_empty() or bool(committed.outcome.get("arrived", false)): break
	_prune_recoverable_fire_journal()
	var after := region_travel_status()
	return {"ok": true, "steps": count, "advanced": float(control.logical_game_seconds) - before,
		"arrived": bool(after.get("arrived", false)), "barrier": bool(after.get("barrier", false)),
		"now": float(control.logical_game_seconds)}

func checkpoint_region_travel() -> Dictionary:
	var journey := region_travel_journey()
	if journey.is_empty(): return fail("NO_TARGET", "沒有旅隊")
	var loaded := region_travel_party()
	if not loaded.ok: return loaded
	var relative := "travel/%s/party_g%09d_r%09d.json" % [str(journey.token), int(_marker.get("generation", 0)) + 1, int(region_registry().revision)]
	var written := _write_new_document(folder.path_join(relative), {"version": 1, "token": str(journey.token), "pin": pin.duplicate(true),
		"encoding": "godot_var_v1", "party": Marshalls.raw_to_base64(var_to_bytes(loaded.party))})
	if not written.ok: return written
	journey.party_path = relative
	journey.party_sha256 = FileAccess.get_sha256(folder.path_join(relative))
	var next_control := control.duplicate(true)
	var sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	var cold := _collect_cold_checkpoint(int(_marker.get("generation", 0)) + 1, sites, next_control)
	if not cold.ok: return cold
	return _publish(sites, next_control, str(_marker.get("transfer_token", "")), journey)

func commit_region_arrival(destination_data: TerrainData, bind_guard: Callable = Callable(), endpoint: Dictionary = {}) -> Dictionary:
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	var status := region_travel_status()
	if not status.ok: return status
	if not endpoint.is_empty():
		if not endpoint.get("event") is Dictionary or absf(float(endpoint.event.get("at", -1.0)) - float(control.logical_game_seconds)) > 0.00000001 \
				or not endpoint.get("site") is Vector2i or not endpoint.get("player_location") is Dictionary:
			return fail("INVALID_JOINT_ENDPOINT", "joint入界須原同刻事件／位置證明")
		status.arrived = true
		status.destination = endpoint.site
	if not bool(status.get("pending", false)) or not bool(status.get("arrived", false)):
		return fail("INCOMPLETE_JOURNEY", "原旅隊未達真抵達／事件 materialize 邊界")
	var to: Vector2i = status.destination
	var coordinate := _coordinate(destination_data)
	if not coordinate.ok or coordinate.site != to: return fail("CONFLICT", "入界候選不是此次真原地點")
	var window := validate_settlement(destination_data.site, control.logical_game_seconds)
	if not window.ok or bool(window.legacy) or float(window.pending) > 0.00001:
		return window if not window.ok else fail("UNSETTLED_SITE", "原入界 Site 尚未到同一端點")
	var loaded := region_travel_party()
	if not loaded.ok: return loaded
	var party: Dictionary = loaded.party
	var location: Dictionary = endpoint.get("player_location", {}) if not endpoint.is_empty() else _region_arrival_location(status, party)
	if not location.ok: return location
	var generation := int(_marker.get("generation", 0)) + 1
	var path := _generation_path(generation, to)
	var nav := Env.navigation_for_state(destination_data, destination_data.site)
	var inserted := RegionTravel.insert(destination_data.site, party, nav, location.entry, path,
		float(status.departure_game_seconds), float(control.logical_game_seconds),
		{"generation": generation, "family_transfer_guard": region_family_transfer_guard, "vehicle_poses": location.vehicle_poses})
	if not inserted.ok: return inserted
	var npc: Dictionary = {}
	var npc_mapping: Dictionary = {}
	var npc_token := str(endpoint.get("npc_token", ""))
	if not npc_token.is_empty():
		var loaded_npc := _region_npc_party(npc_token)
		if not loaded_npc.ok: return loaded_npc
		npc = loaded_npc.party
		var npc_location: Dictionary = endpoint.get("npc_location", {})
		if not npc_location.get("ok", false) or not npc_location.get("entry") is Vector2i:
			return fail("INVALID_JOINT_ENDPOINT", "同刻NPC須自己的真入界位置")
		var npc_nav := Env.navigation_for_state(destination_data, inserted.state)
		var placed := RegionTravel.insert(inserted.state, npc, npc_nav, npc_location.entry, path,
			float(region_registry().parties[npc_token].departure_game_seconds), float(control.logical_game_seconds),
			{"generation": generation, "family_transfer_guard": region_family_transfer_guard,
			"vehicle_poses": npc_location.get("vehicle_poses", {})})
		if not placed.ok: return placed
		inserted.state = placed.state
		npc_mapping = placed.mapping
	var life_events: Array = status.get("life_events", []).duplicate(true)
	for event: Dictionary in life_events:
		if not inserted.mapping.maps.person.has(str(int(event.person_id))): return fail("INVALID_LIFE_MAPPING", "原生命端點不屬原到站閉包")
		event.person_id = int(inserted.mapping.maps.person[str(int(event.person_id))])
	if not life_events.is_empty(): inserted.state.region_life_events = life_events
	var candidate := Env.navigation_for_state(destination_data, inserted.state)
	# The original destination, before any transfer, proves the surviving graph.
	# A transformed candidate cannot reuse its former hot graph/body hash.
	candidate.set_meta(&"region_bind_source", destination_data)
	if not bind_guard.is_valid(): return fail("MISSING_REGION_BIND_PREFLIGHT", "原完整 bind 預檢是提交前必要出口")
	var ready: Variant = bind_guard.call(candidate)
	if not ready is Dictionary or not ready.get("ok") is bool: return fail("INVALID", "原完整 bind 預檢缺必要合同")
	if not ready.ok: return ready
	var prepared: Dictionary = ready
	if not prepared.get("data") is TerrainData:
		return fail("MISSING_REGION_BIND_PREFLIGHT", "原完整 bind 未提供 validated graph／封閉發布票據")
	var binding: Dictionary = prepared
	for hook: String in ["can_publish", "save_candidate", "publish"]:
		if not binding.get(hook) is Callable or not binding[hook].is_valid(): return fail("MISSING_REGION_BIND_PREFLIGHT", "原完整 bind 票據缺 " + hook)
	var may_publish: Variant = binding.can_publish.call()
	if not may_publish is bool or not may_publish:
		return fail("STALE_REGION_BIND_TICKET")
	var saved: Variant = binding.save_candidate.call(prepared.data, path)
	if not saved is Dictionary or not bool(saved.get("ok", false)):
		return saved if saved is Dictionary else fail("SAVE_IO", "原完整 owner graph 尚未保存")
	var checked := _load_checked(path, to)
	if not checked.ok: return checked
	var identity := str(checked.data.site.id)
	var next_clock: Dictionary = control.duplicate(true)
	next_clock.active_site_id = identity
	var mapped := _region_arrival_queue_mapping(next_clock, str(status.token), inserted.mapping, identity)
	if not mapped.ok: return mapped
	if not npc_token.is_empty():
		var transferred := _region_joint_npc_reference(next_clock, npc_token, npc_mapping, identity)
		if not transferred.ok: return transferred
	for battle: Dictionary in next_clock.get("region_gameplay", {}).get("battles", {}).values():
		if str(battle.get("site_id", "")) == identity and str(battle.get("phase", "")) != "finished": battle.mode = "live"
	if next_clock.has("region_gameplay"): next_clock.region_gameplay.revision = int(next_clock.region_gameplay.revision) + 1
	var fire_clock: Dictionary = next_clock.fire_clock
	for owner: String in fire_clock.get("index", {}): fire_clock.index[owner].active = false
	if checked.data.site.has("fire_settlement"):
		var settlement := validate_fire_settlement(checked.data.site, fire_clock)
		if not settlement.ok: return settlement
		var watermark: Dictionary = checked.data.site.fire_settlement
		fire_clock.index[identity] = {"coordinate": [to.x, to.y], "active": true, "fire_active": Runtime.fire_active(checked.data),
			"sequence": int(watermark.sequence), "action_seconds": float(watermark.action_seconds), "game_seconds": float(watermark.game_seconds)}
	if next_clock.has("region_gameplay"):
		var activation := GameplayClock.activate_mode(next_clock.region_gameplay, identity, "committed-unbound", generation,
			"gd", "original_site", float(next_clock.logical_game_seconds), float(fire_clock.action_seconds), {})
		if not activation.ok: return activation
	var sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	sites[_site_key(to)] = _file_entry(path)
	var collected := collect_region_party_checkpoint(generation, next_clock)
	if not collected.ok: return collected
	# A saved candidate is still uncommitted. Recheck every original owner
	# immediately before the single marker changes the authoritative Site.
	may_publish = binding.can_publish.call()
	if not may_publish is bool or not may_publish:
		return fail("STALE_REGION_BIND_TICKET")
	var published := _publish(sites, next_clock, str(status.token))
	if not published.ok: return published
	# The marker now owns the arrival exactly once, including failures below.
	_travel_party_cache.clear()
	_travel_plan_cache.clear()
	_travel_party_runtime.clear()
	_travel_party_runtime_token = ""
	_region_arrival_retry.clear()
	if not npc_token.is_empty():
		_region_npc_party_runtime.erase(npc_token)
		_region_npc_plan_runtime.erase(npc_token)
	var bound: Variant = binding.publish.call(checked.data)
	if not bound is Dictionary or not bool(bound.get("ok", false)) or not bool(bound.get("complete", false)):
		return _region_committed_unbound("原到站已共同提交；完整 graph 尚未接妥，僅可重試原提交 bind", {
			"generation": published.generation, "token": str(status.token), "destination_data": checked.data,
			"mapping": inserted.mapping, "bind_result": bound})
	if str(bound.get("owner", "")) != identity or int(bound.get("generation", -1)) != int(published.generation):
		return _region_committed_unbound("原 bind 收據不是剛提交的目的地／generation", {"generation": published.generation, "token": str(status.token)})
	var acknowledged := acknowledge_region_bind(checked.data, bound)
	if not acknowledged.ok: return acknowledged
	return {"ok": true, "destination_data": checked.data, "active_site": [to.x, to.y], "generation": published.generation,
		"prepared": prepared, "leader_cell": inserted.leader_cell, "leader_person_id": inserted.leader_person_id,
		"mapping": inserted.mapping, "npc_mapping": npc_mapping, "npc_token": npc_token,
		"pending_events": life_events, "token": str(status.token), "binding_receipt": bound}

func region_bind_proof(data: TerrainData) -> Dictionary:
	var coordinate := _coordinate(data)
	if not coordinate.ok: return {}
	var entry: Dictionary = _marker.get("sites", {}).get(_site_key(coordinate.site), {})
	if entry.is_empty(): return {}
	return {"generation": int(_marker.get("generation", 0)), "transfer_token": str(_marker.get("transfer_token", "")),
		"site_id": str(data.site.id), "path": str(entry.path), "sha256": str(entry.sha256)}

func validate_region_bind_proof(data: TerrainData, proof: Dictionary) -> Dictionary:
	if proof != region_bind_proof(data) or str(control.active_site_id) != str(data.site.get("id", "")):
		return fail("STALE_REGION_BIND", "候選不是最新完整提交的活動 owner")
	if proof.is_empty() or FileAccess.get_sha256(folder.path_join(str(proof.path))) != str(proof.sha256):
		return fail("CORRUPT_SAVE", "綁定提交檔已變更")
	var coordinate := _coordinate(data)
	var loaded := _load_checked(folder.path_join(str(proof.path)), coordinate.site)
	if not loaded.ok: return loaded
	if RegionCheckpoint.state_hash(loaded.data.site) != RegionCheckpoint.state_hash(data.site):
		return fail("STALE_REGION_BIND", "綁定候選與已提交實物不符")
	return {"ok": true, "complete": true, "proof": proof}

# Original Slot is the sole publisher of the joint internal checkpoint.
func region_checkpoint_context(data: TerrainData, purpose: String, token: String,
		effects_complete: bool = true, endpoint_payload: Dictionary = {}) -> Dictionary:
	if data == null or _region_bound_original_lab(data) == null: return fail("REGION_SOURCE", "非此 Slot 已綁原 TerrainLab owner")
	var registry := region_registry()
	var mode: Dictionary = registry.modes.get(str(data.site.id), {})
	var context := {"purpose": purpose, "mode": str(mode.get("mode", "live")),
		"source_generation": int(_marker.get("generation", 0)), "runtime_revision": int(registry.revision),
		"token": token, "game_seconds": float(control.logical_game_seconds), "action_seconds": float(control.fire_clock.action_seconds),
		"fire_epoch": str(control.fire_clock.epoch), "fire_sequence": int(control.fire_clock.sequence),
		"interval_complete": true, "effects_complete": effects_complete, "mode_revision": int(mode.get("revision", 0)),
		"backend": str(mode.get("backend", "gd")), "events": pending_region_events(), "endpoint_payload": endpoint_payload.duplicate(true)}
	var checked := RegionCheckpoint.validate_context(context)
	if not checked.ok: return checked
	return {"ok": true, "context": context}

func checkpoint_region_site(data: TerrainData, context: Dictionary, owner_states: Dictionary) -> Dictionary:
	var expected := {"source_generation": int(_marker.get("generation", 0)), "runtime_revision": int(region_registry().revision),
		"game_seconds": float(control.logical_game_seconds), "action_seconds": float(control.fire_clock.action_seconds),
		"fire_epoch": str(control.fire_clock.epoch), "fire_sequence": int(control.fire_clock.sequence)}
	var admitted := RegionCheckpoint.validate_context(context, expected)
	if not admitted.ok: return admitted
	var coordinate := _coordinate(data)
	if not coordinate.ok: return coordinate
	if str(data.site.id) != str(control.active_site_id): return fail("REGION_SOURCE", "非活動原 owner 不能單檔發布")
	var generation := int(_marker.get("generation", 0)) + 1
	var path := _generation_path(generation, coordinate.site)
	var saved := Store.save_region_snapshot(data, path, context, owner_states)
	if not saved.ok: return saved
	# Same mode-aware readback as resume; never a normal cold catch-up.
	var loaded := _load_checked(path, coordinate.site)
	if not loaded.ok: return loaded
	var validated := Store.validate_region_snapshot(loaded.data, {}, expected)
	if not validated.ok: return validated
	var next_clock := control.duplicate(true)
	var sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	sites[_site_key(coordinate.site)] = _file_entry(path)
	var collected := _collect_cold_checkpoint(generation, sites, next_clock)
	if not collected.ok: return collected
	var published := _publish(sites, next_clock, str(_marker.get("transfer_token", "")), _marker.get("journey", {}))
	if not published.ok: return published
	return {"ok": true, "path": path, "generation": published.generation, "data": loaded.data, "snapshot": validated.snapshot}


## Technology owner must admit its real unique-holder epoch before any copy.
func region_family_transfer_guard(first: Dictionary, second: Dictionary) -> Dictionary:
	var state := first
	var party: Dictionary = second if second.has("content") else {}
	var families: Array = [state.get("family", {})]
	if not party.is_empty(): families.append(party.content.get("family", {}))
	var needs_original_technology := false
	if not party.is_empty() and party.content.get("family_refs", {}).has("technology"): needs_original_technology = true
	for family: Variant in families:
		if not family is Dictionary: return fail("INVALID_FAMILY", "原家族不是必要 schema")
		if family.is_empty(): continue
		if int(family.get("version", 0)) not in [1, 2, 3]: return fail("INVALID_FAMILY", "未知原家族版本")
		if int(family.version) == 3: needs_original_technology = true
	if not needs_original_technology: return {"ok": true}
	# Original technology API must preflight the same epoch and return its own
	# candidate. It must not copy the mutable holder into both Site and party.
	var admitted: Variant = region_technology_transfer_guard(first, second)
	if not admitted is Dictionary or not admitted.get("ok") is bool:
		return fail("INVALID_FAMILY_TRANSFER", "原族科技移交未回傳必要合同")
	return admitted

func _admit_world_pin(data: TerrainData) -> Dictionary:
	if data == null or data.site.is_empty(): return fail("NO_SITE")
	if not data.site.has("world_pin"):
		if int(pin.get("format", 0)) != 1: return fail("MISSING_WORLD_PIN", "新世界 Site 缺固定科技政策")
		data.site.world_pin = pin.duplicate(true) # Verified old slot only, empty policy.
	if not _same_pin(data.site.world_pin, pin): return fail("TECH_POLICY_CONFLICT", "Site 原世界政策與存檔槽不同")
	return {"ok": true}

func _region_npc_party(token: String) -> Dictionary:
	var reference: Dictionary = region_registry().parties.get(token, {})
	if str(reference.get("controller", "")) != "npc" or str(reference.get("phase", "")) not in ["travelling", "pending_life", "materializing"]:
		return fail("NO_TARGET", "沒有此原 NPC 在途 owner")
	if _region_npc_party_runtime.has(token): return {"ok": true, "party": _region_npc_party_runtime[token]}
	var document := _travel_document(str(reference.party_path), str(reference.party_sha256), _travel_party_cache)
	if not document.ok: return document
	var payload: Dictionary = document.payload
	if str(payload.get("token", "")) != token or not _same_pin(payload.get("pin"), pin) or payload.get("encoding") != "godot_var_v1" or not payload.get("party") is String:
		return fail("CORRUPT_SAVE", "原 NPC party 文件來源不同")
	var party: Variant = bytes_to_var(Marshalls.base64_to_raw(str(payload.party)))
	if not party is Dictionary or str(party.get("party_id", "")) != token or str(party.get("controller", "")) != "npc" or int(party.get("content", {}).get("controlled_person_id", -1)) != -1:
		return fail("CORRUPT_SAVE", "NPC party 不能持玩家控制")
	if not RegionTravel.validate_identity(party.get("content", {}).get("travel_identity")):
		return fail("CORRUPT_SAVE", "原 stable 身分引用非法")
	var admitted := RegionTravel.validate_patients(party.content)
	if not admitted.ok: return admitted
	_region_npc_party_runtime[token] = party
	return {"ok": true, "party": party}

func _region_npc_plan(token: String) -> Dictionary:
	var reference: Dictionary = region_registry().parties.get(token, {})
	if reference.is_empty(): return fail("NO_TARGET", "没有原 NPC 路線引用")
	if _region_npc_plan_runtime.has(token): return {"ok": true, "plan": _region_npc_plan_runtime[token]}
	var document := _travel_document(str(reference.plan_path), str(reference.plan_sha256), _travel_plan_cache)
	if not document.ok: return document
	var plan: Dictionary = document.payload
	if str(plan.get("token", "")) != token or not plan.get("steps") is Array or plan.steps.size() < 2:
		return fail("CORRUPT_SAVE", "原 NPC 路線非法")
	_region_npc_plan_runtime[token] = plan
	return {"ok": true, "plan": plan}

func _region_route_position(plan: Dictionary, distance: float) -> Dictionary:
	var travelled := 0.0
	var position := {"site": [], "component": -1, "step_index": 0, "fraction": 0.0}
	for index: int in plan.steps.size():
		var step: Dictionary = plan.steps[index]
		var next := travelled + float(step.metres)
		position = {"site": step.site.duplicate(), "component": int(step.component), "step_index": index,
			"fraction": clampf((distance - travelled) / maxf(0.000001, float(step.metres)), 0.0, 1.0)}
		if distance < next - 0.0000001: return position
		travelled = next
	return position

# Prepare against actual command/office/intel owners, without moving anyone.
# Source may be a bound cold original or live original. Human control stays put.

func prepare_npc_region_dispatch(lab: TerrainLab, nation_id: String, team_id: int,
		target_coordinate: Vector2i, start_component: int, steps: Array, transfer_token: String = "") -> Dictionary:
	if lab == null or lab.site_controller == null or not region_bind_candidate.is_valid(): return fail("MISSING_REGION_ADAPTER", "缺原完整 bind 預檢")
	if not region_player_barrier().is_empty(): return fail("PLAYER_BARRIER", "先處理同刻玩家事件")
	if not _safe_part(transfer_token) and not transfer_token.is_empty(): return fail("INVALID", "移交號非法")
	var token := transfer_token if not transfer_token.is_empty() else "npc_" + Crypto.new().generate_random_bytes(16).hex_encode()
	if region_registry().parties.has(token): return {"ok": true, "duplicate": true, "token": token, "reference": region_registry().parties[token]}
	var coordinate := _coordinate(lab.terrain)
	if not coordinate.ok: return coordinate
	var window := validate_settlement(lab.terrain.site, control.logical_game_seconds)
	if not window.ok or bool(window.get("legacy", true)) or float(window.get("pending", INF)) > 0.0000001:
		return fail("UNSETTLED_SITE", "派遣前原 Site 須完成同一原區間")
	var captured: Dictionary = lab.site_controller.capture_region_checkpoint("region_barrier", false,
		{"npc_dispatch": true, "token": token, "owner": str(lab.terrain.site.id)}, token)
	if not captured.ok: return captured
	var original: Dictionary = lab.terrain.site.duplicate(true)
	var fire_capture := _capture_transfer_fire_snapshots(lab.terrain, original)
	if not fire_capture.ok: return fire_capture
	var departure_mode := _region_npc_dispatch_mode(original, team_id)
	if not departure_mode.ok: return departure_mode
	if str(departure_mode.spec.mode) == "sea": start_component = 0
	var extracted: Dictionary = {}
	var identity_namespace := str(pin.world_instance_id) + ":" + Crypto.new().generate_random_bytes(16).hex_encode()
	var preflight := func(request: Dictionary) -> Dictionary:
		var spec := {"person_id": int(request.commander), "team_id": int(request.team_id),
			"actor_key": "", "controller": "npc", "game_seconds": float(control.logical_game_seconds),
			"namespace": identity_namespace, "family_transfer_guard": region_family_transfer_guard}
		spec.merge(departure_mode.spec, true)
		var result := RegionTravel.extract(original, spec, str(request.transfer_token))
		extracted.merge(result, true)
		return result
	var target_id := Grid.site_id(str(pin.atlas_id), target_coordinate)
	var context := RegionAI.dispatch_context(lab, nation_id, team_id, target_id, token, preflight)
	if not context.ok: return context
	var authorized := RegionAI.prepare_dispatch(context.context)
	if not authorized.ok: return authorized
	if not extracted.get("ok", false): return fail("DISPATCH_UNAVAILABLE", "原旅行尚未准入")
	# Detached Travel closure proves the exact movers. Never detach an active
	# original research, lesson or work participant; unrelated jobs stay owned.
	for identity: Variant in extracted.party.person_ids:
		if lab.site_controller.person_actions.is_busy(int(identity)):
			return fail("DISPATCH_UNAVAILABLE", "原出發人物尚有已接受作業")
	var route_context := prepare_region_route_context(lab.terrain, extracted.party)
	if not route_context.ok: return route_context
	if steps.is_empty():
		# Strategy has already selected this known target. The original route
		# owner may now read true effective geometry solely as a resolver.
		var search := RegionRoute.Search.new()
		search.source = source
		search.start_site = coordinate.site
		search.start_component = start_component
		search.goal_site = target_coordinate
		search.context = route_context.context
		var found: Dictionary = search.run()
		if not found.get("ok", false): return fail("DISPATCH_UNAVAILABLE", "原已知目標尚未准入合法路線")
		steps = found.steps
	if steps.size() < 2 or steps[0].site != [coordinate.site.x, coordinate.site.y] or int(steps[0].component) != start_component or steps.back().site != [target_coordinate.x, target_coordinate.y]:
		return fail("NO_ROUTE", "路線須從原通道到實際已知目的地")
	var verified := RegionRoute.verify_steps(source, steps, route_context.context)
	if not verified.ok: return verified
	for step: Dictionary in steps:
		if not GameplayClock.seconds(step.get("metres")): return fail("NO_ROUTE", "原路線距離非法")
	var transport := RegionTravel.prepare_transport(extracted.party)
	if not transport.ok: return transport
	var compiled := _region_npc_route_plan(token, steps, extracted.party)
	if not compiled.ok: return compiled
	var candidate := Env.navigation_for_state(lab.terrain, extracted.origin)
	candidate.set_meta(&"region_bind_source", lab.terrain)
	var prepared_bind: Dictionary = region_bind_candidate.call(lab, candidate, "live" if str(control.active_site_id) == str(candidate.site.id) else "cold_exact")
	if not prepared_bind.get("ok", false) or not prepared_bind.get("can_publish") is Callable or not prepared_bind.get("publish") is Callable or not prepared_bind.get("save_candidate") is Callable:
		return fail("MISSING_REGION_ADAPTER", "缺原完整 bind 原子發布收據")
	return {"ok": true, "token": token, "generation": int(_marker.get("generation", 0)),
		"runtime_revision": int(region_registry().revision), "world": float(control.logical_game_seconds),
		"coordinate": coordinate.site, "lab": lab, "candidate": candidate, "party": extracted.party,
		"plan": compiled.plan, "binding": prepared_bind,
		"request": authorized.request, "vacated_housing": extracted.vacated_housing}

# Sole ownership move: original source and exact party document share one marker.
# publish binding is the parent's prevalidated original Lab transaction, not control switching.

func commit_npc_region_dispatch(prepared: Dictionary) -> Dictionary:
	if not prepared.get("ok", false): return fail("INVALID", "派遣候選非法")
	if prepared.get("duplicate", false): return prepared
	if int(prepared.generation) != int(_marker.get("generation", 0)) or int(prepared.runtime_revision) != int(region_registry().revision) or float(prepared.world) != float(control.logical_game_seconds):
		return fail("STALE_REGION_PERMIT", "派遣來源世代已變")
	if not bool(prepared.binding.can_publish.call()): return fail("STALE_BIND", "原人物／位置／任務已變")
	var token := str(prepared.token)
	var generation := int(_marker.get("generation", 0)) + 1
	var source_path := _generation_path(generation, prepared.coordinate)
	var checked: Dictionary = prepared.binding.save_candidate.call(prepared.candidate, source_path)
	if not checked.ok: return checked
	var party_path := "travel/%s/party_g%09d.json" % [token, generation]
	var plan_path := "travel/%s/plan_000001.json" % token
	prepared.party.upkeep.plan_id = plan_path
	if str(prepared.party.get("mode", "land")) == "sea": prepared.party.upkeep.sea_cursor.plan_id = plan_path
	var written := _write_new_document(folder.path_join(party_path), {"version": 1, "token": token, "pin": pin.duplicate(true),
		"encoding": "godot_var_v1", "party": Marshalls.raw_to_base64(var_to_bytes(prepared.party))})
	if not written.ok: return written
	written = _write_new_document(folder.path_join(plan_path), prepared.plan)
	if not written.ok: return written
	var next_control := control.duplicate(true)
	var registry: Dictionary = next_control.region_gameplay
	var owner := "travel:" + token
	registry.parties[token] = {"version": 1, "controller": "npc", "token": token, "phase": "travelling",
		"party_path": party_path, "party_sha256": FileAccess.get_sha256(folder.path_join(party_path)),
		"plan_path": plan_path, "plan_sha256": FileAccess.get_sha256(folder.path_join(plan_path)),
		"departure_game_seconds": float(control.logical_game_seconds), "origin": [prepared.coordinate.x, prepared.coordinate.y],
		"position": {"site": prepared.plan.steps[0].site.duplicate(), "component": int(prepared.plan.steps[0].component)},
		"transfer_receipt": prepared.request.duplicate(true)}
	var reference: Dictionary = registry.parties[token]
	var activation := {"ok": true, "complete": true, "owner": owner, "mode": "cold_exact", "generation": generation,
		"backend": "gd", "consumer": "original_region_travel", "party_path": party_path, "party_sha256": reference.party_sha256, "token": token}
	var activated := GameplayClock.activate_mode(registry, owner, "cold_exact", generation, "gd", "original_region_travel",
		float(control.logical_game_seconds), float(control.fire_clock.action_seconds), activation)
	if not activated.ok: return activated
	registry.revision = int(registry.revision) + 1
	var sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	sites[_site_key(prepared.coordinate)] = _file_entry(source_path)
	var collected := collect_region_party_checkpoint(generation, next_control)
	if not collected.ok: return collected
	var published := _publish(sites, next_control, str(_marker.get("transfer_token", "")), _marker.get("journey", {}))
	if not published.ok: return published
	var bound: Dictionary = prepared.binding.publish.call(checked.data)
	if not bound.get("ok", false) or not bound.get("complete", false):
		var fault := fail("COMMITTED_UNBOUND", "移交已提交，原完整 bind 未完成；凍結至真 bind")
		prepared.lab.site_controller.latch_original_step_fault(fault)
		return fault
	_region_npc_party_runtime[token] = prepared.party
	_region_npc_plan_runtime[token] = prepared.plan
	return {"ok": true, "token": token, "generation": published.generation, "binding": bound}

# Called at the already completed endpoint; inserts the original NPC closure.
# For P0 encounter, Root first supplies the correctly bound original player Site
# (or combines this detached insert in the same original P0 candidate).

func prepare_npc_region_arrival(event: Dictionary) -> Dictionary:
	var token := str(event.get("payload", {}).get("token", ""))
	var reference: Dictionary = region_registry().parties.get(token, {})
	if str(reference.get("controller", "")) != "npc": return fail("NO_TARGET", "沒有此原 NPC 到站引用")
	if str(reference.get("phase", "")) == "entered":
		return {"ok": true, "duplicate": true, "token": token, "reference": reference}
	if not region_owner_lab.is_valid() or not region_bind_candidate.is_valid(): return fail("MISSING_REGION_ADAPTER", "缺原到站 Site 與完整 bind 預檢")
	var loaded := _region_npc_party(token)
	if not loaded.ok: return loaded
	var planned := _region_npc_plan(token)
	if not planned.ok: return planned
	var coordinate_raw: Variant = event.get("payload", {}).get("site", [])
	if not coordinate_raw is Array or coordinate_raw.size() != 2: return fail("INVALID", "到站缺原位置")
	var to := Vector2i(int(coordinate_raw[0]), int(coordinate_raw[1]))
	var identity := Grid.site_id(str(pin.atlas_id), to)
	var requested_mode := "live" if identity == str(control.active_site_id) else "cold_exact"
	var original: Dictionary = region_owner_lab.call(identity, requested_mode)
	if not original.get("ok", false) or not original.get("lab") is TerrainLab: return fail("COMMITTED_UNBOUND", "目的地原 owner 尚未完整 bind")
	var lab: TerrainLab = original.lab
	if str(lab.terrain.site.id) != identity: return fail("WRONG_SITE", "到站原 owner 不同")
	var window := validate_settlement(lab.terrain.site, control.logical_game_seconds)
	if not window.ok or bool(window.get("legacy", true)) or float(window.get("pending", INF)) > 0.00000001:
		return fail("UNSETTLED_SITE", "目的地須先完成同一原區間")
	var party: Dictionary = loaded.party
	if absf(float(party.get("upkeep", {}).get("at", -1.0)) - float(control.logical_game_seconds)) > 0.00000001:
		return fail("UNSETTLED_PARTY", "原到站 party 與世界端點不同")
	var position: Dictionary = _region_npc_sea_position(planned.plan, party) if str(planned.plan.get("mode", "land")) == "sea" else _region_route_position(planned.plan, float(party.upkeep.get("distance", 0.0)))
	if str(planned.plan.get("mode", "land")) == "sea" and not bool(position.get("arrived", false)):
		return fail("INCOMPLETE_JOURNEY", "原船尚有未完成ACTION，不能用靜態距離冒充到站")
	if position.site != coordinate_raw or int(position.component) != int(event.payload.get("component", -1)):
		return fail("STALE_ARRIVAL", "原路線位置與事件不同")
	var entry_step: Dictionary = planned.plan.steps[int(position.step_index)]
	var generation := int(_marker.get("generation", 0)) + 1
	var to_path := _generation_path(generation, to)
	var captured: Dictionary = lab.site_controller.capture_region_checkpoint("region_barrier", false,
		{"npc_arrival": true, "token": token, "event": str(event.id)}, token)
	if not captured.ok: return captured
	var destination := lab.terrain.site.duplicate(true)
	var fire_capture := _capture_transfer_fire_snapshots(lab.terrain, destination)
	if not fire_capture.ok: return fire_capture
	var nav := Env.navigation_for_state(lab.terrain, destination)
	var inserted := RegionTravel.insert(destination, party, nav, RegionRoute.entry_cell(entry_step), to_path,
		float(reference.departure_game_seconds), float(control.logical_game_seconds),
		{"generation": generation, "family_transfer_guard": region_family_transfer_guard, "vehicle_poses": entry_step.get("vehicle_poses", {})})
	if not inserted.ok: return inserted
	var candidate := Env.navigation_for_state(lab.terrain, inserted.state)
	candidate.set_meta(&"region_bind_source", lab.terrain)
	var binding: Dictionary = region_bind_candidate.call(lab, candidate, requested_mode)
	if not binding.get("ok", false) or not binding.get("can_publish") is Callable or not binding.get("publish") is Callable:
		return fail("MISSING_REGION_ADAPTER", "原到站完整 bind 未准入")
	var battle := _region_arrival_battle_candidate(destination, inserted.state, party, inserted.mapping, token, binding, requested_mode == "live")
	if not battle.ok: return battle
	# Hot P0 candidate uses Root's actual RegionCheckpoint context/owner states.
	# The same bind adapter may provide that ORIGINAL Slot save entry.
	var saved: Dictionary
	if binding.get("save_candidate") is Callable:
		saved = binding.save_candidate.call(candidate, to_path)
	else:
		saved = _save_checked(candidate, to, to_path)
	if not saved.get("ok", false): return saved
	return {"ok": true, "token": token, "event_id": str(event.id), "generation": int(_marker.get("generation", 0)),
		"revision": int(region_registry().revision), "world": float(control.logical_game_seconds), "coordinate": to,
		"path": to_path, "lab": lab, "candidate": saved.data, "binding": binding, "mapping": inserted.mapping,
		"destination_site": identity, "mode": requested_mode, "battle": battle.get("battle", {}), "reinforcement": battle.get("reinforcement", "")}

func commit_npc_region_arrival(prepared: Dictionary) -> Dictionary:
	if not prepared.get("ok", false): return fail("INVALID", "原到站候選非法")
	if prepared.get("duplicate", false): return prepared
	if int(prepared.generation) != int(_marker.get("generation", 0)) or int(prepared.revision) != int(region_registry().revision) or float(prepared.world) != float(control.logical_game_seconds):
		return fail("STALE_REGION_PERMIT", "原到站來源世代已變")
	if not bool(prepared.binding.can_publish.call()): return fail("STALE_BIND", "原到站完整 bind 已過期")
	var next_control := control.duplicate(true)
	var registry: Dictionary = next_control.region_gameplay
	var token := str(prepared.token)
	var reference: Dictionary = registry.parties[token]
	reference.phase = "entered"
	reference.destination_site = str(prepared.destination_site)
	reference.arrival_game_seconds = float(control.logical_game_seconds)
	reference.arrival_mapping = prepared.mapping.duplicate(true)
	registry.modes.erase("travel:" + token)
	if not prepared.get("battle", {}).is_empty(): registry.battles[str(prepared.battle.id)] = prepared.battle.duplicate(true)
	if not str(prepared.get("reinforcement", "")).is_empty(): reference.battle_id = str(prepared.reinforcement)
	for pending: Dictionary in registry.events:
		if str(pending.status) != "pending" or str(pending.payload.get("token", "")) != token: continue
		if str(pending.kind) == "life":
			var life: Dictionary = pending.payload.event
			life.person_id = int(prepared.mapping.maps.person.get(str(life.person_id), life.person_id))
			pending.payload.entered_site = str(prepared.destination_site)
			pending.payload.arrival_mapping = prepared.mapping.duplicate(true)
	var completed := GameplayClock.complete_event(registry, str(prepared.event_id), float(control.logical_game_seconds))
	if not completed.ok: return completed
	registry.revision = int(registry.revision) + 1
	var sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	sites[_site_key(prepared.coordinate)] = _file_entry(str(prepared.path))
	var collected := collect_region_party_checkpoint(int(prepared.generation) + 1, next_control)
	if not collected.ok: return collected
	var published := _publish(sites, next_control, str(_marker.get("transfer_token", "")), _marker.get("journey", {}))
	if not published.ok: return published
	var bound: Dictionary = prepared.binding.publish.call(prepared.candidate)
	if not bound.get("ok", false) or not bound.get("complete", false):
		var fault := fail("COMMITTED_UNBOUND", "到站已提交，仍須原完整 bind")
		prepared.lab.site_controller.latch_original_step_fault(fault)
		return fault
	# The real complete graph was restored through cold_exact. Formula/live
	# selects the original consumer only after that receipt and marker exist.
	var final_mode := "live" if str(prepared.mode) == "live" else str(prepared.get("battle", {}).get("mode", "cold_exact"))
	bound.mode = final_mode
	bound.consumer = "original_site" if final_mode == "live" else ("original_formula_site" if final_mode == "formula_active" else "original_replay")
	var activated := activate_region_mode(str(prepared.destination_site), final_mode, str(bound.consumer), bound)
	if not activated.ok: return activated
	_region_npc_party_runtime.erase(token)
	_region_npc_plan_runtime.erase(token)
	return {"ok": true, "token": token, "generation": published.generation, "binding": bound, "mapping": prepared.mapping, "battle": prepared.get("battle", {})}

# Shared-step preview only. No party clock publishes world time. All deltas go
# through original RegionTravel.advance_upkeep, including fatigue-integrated metres.

func _preview_npc_party_to(token: String, end: float, interval: Dictionary = {}) -> Dictionary:
	var loaded := _region_npc_party(token)
	if not loaded.ok: return loaded
	var planned := _region_npc_plan(token)
	if not planned.ok: return planned
	var party: Dictionary = loaded.party
	var plan: Dictionary = planned.plan
	var world := float(control.logical_game_seconds)
	if absf(float(party.get("upkeep", {}).get("at", -1.0)) - world) > 0.0000001: return fail("UNSETTLED_PARTY", "原 NPC 水印不同")
	if plan.get("mode") == "sea":
		var sea := _preview_npc_sea_party_to(token, party, plan, end, interval)
		if sea.ok: sea.source_party = party
		return sea
	var advanced := RegionTravel.advance_upkeep(party, end, {"moving": true, "safe_rest": true})
	if not advanced.ok: return advanced
	var distance := float(party.upkeep.get("distance", 0.0))
	var remaining := maxf(0.0, float(plan.metres) - distance)
	if float(advanced.metres) > remaining + 0.0000001:
		var low := world
		var high := float(advanced.at)
		for iteration: int in range(40):
			var middle := (low + high) * 0.5
			var probe := RegionTravel.advance_upkeep(party, middle, {"moving": true, "safe_rest": true})
			if not probe.ok: return probe
			if float(probe.metres) < remaining: low = middle
			else: high = middle
		advanced = RegionTravel.advance_upkeep(party, high, {"moving": true, "safe_rest": true})
		if not advanced.ok: return advanced
	var candidate: Dictionary = advanced.party
	candidate.upkeep.distance = minf(float(plan.metres), distance + float(advanced.metres))
	candidate.upkeep.plan_id = str(region_registry().parties[token].plan_path)
	return {"ok": true, "at": float(advanced.at), "party": candidate, "source_party": party, "events": advanced.events,
		"position": _region_route_position(plan, float(candidate.upkeep.distance)),
		"arrived": float(candidate.upkeep.distance) >= float(plan.metres) - 0.0000001}

# Route boundaries use the original fatigue-integrated distance. These previews
# are navigation/contact truth only; no strategy observation is created.

func _region_route_breaks(party: Dictionary, plan: Dictionary, to: float, moving: bool) -> Dictionary:
	var begin := float(control.logical_game_seconds)
	var advanced := RegionTravel.advance_upkeep(party, to, {"moving": moving, "safe_rest": true})
	if not advanced.ok: return advanced
	var end := float(advanced.at)
	var initial := float(party.get("upkeep", {}).get("distance", 0.0))
	var final := initial + float(advanced.metres)
	var times: Array[float] = [begin, end]
	var distance := 0.0
	for step: Dictionary in plan.get("steps", []):
		distance += float(step.metres)
		if distance <= initial + 0.0000001 or distance > final + 0.0000001: continue
		var low := begin
		var high := end
		for iteration: int in range(40):
			var middle := (low + high) * 0.5
			var probe := RegionTravel.advance_upkeep(party, middle, {"moving": moving, "safe_rest": true})
			if not probe.ok: return probe
			if initial + float(probe.metres) < distance: low = middle
			else: high = middle
		times.append(high)
	return {"ok": true, "times": times, "until": end}

func _region_route_position_at(party: Dictionary, plan: Dictionary, at: float, moving: bool) -> Dictionary:
	var advanced := RegionTravel.advance_upkeep(party, at, {"moving": moving, "safe_rest": true})
	if not advanced.ok: return advanced
	return {"ok": true, "at": float(advanced.at), "position": _region_route_position(plan,
		float(party.get("upkeep", {}).get("distance", 0.0)) + float(advanced.metres))}

func _region_first_player_route_contact(token: String, to: float, interval: Dictionary = {}) -> Dictionary:
	var npc := _region_npc_party(token)
	if not npc.ok: return npc
	var npc_plan := _region_npc_plan(token)
	if not npc_plan.ok: return npc_plan
	var player_status := region_travel_status()
	if not player_status.ok: return player_status
	var active := {}
	if not bool(player_status.get("pending", false)):
		if str(control.active_site_id).is_empty(): return {"ok": true, "contact": false}
		if not region_contact_active_data.is_valid(): return fail("MISSING_REGION_ADAPTER", "接觸須原玩家即時位置／導航 owner")
		active = region_contact_active_data.call()
		if not active.get("ok", false): return active
		if not active.get("data") is TerrainData or str(active.data.site.get("id", "")) != str(control.active_site_id) \
				or not active.get("cell") is Vector2i or int(active.get("person_id", -1)) <= 0:
			return fail("REGION_SOURCE", "玩家接觸原位置／活動 Site 不一致")
	var prepared := prepare_region_route_context(active.get("data"), npc.party)
	if not prepared.ok: return prepared
	var context: Dictionary = prepared.context
	var cache := {}
	var begin := float(control.logical_game_seconds)
	var npc_reference: Dictionary = region_registry().parties[token]
	var first := _region_contact_sea_points(npc.party, npc_plan.plan, to, context, cache, interval) if npc_plan.plan.get("mode") == "sea" \
		else _region_contact_land_points(npc.party, npc_plan.plan, to, true, npc_reference.position, context, cache)
	if not first.ok: return first
	var second: Dictionary
	if not active.is_empty():
		var coordinate := _coordinate(active.data)
		if not coordinate.ok: return coordinate
		var nav := _region_contact_navigation(coordinate.site, context, str(active.get("mode", "land")), cache)
		if not nav.ok: return nav
		var cell: Vector2i = active.cell
		if cell.x < 0 or cell.x >= 100 or cell.y < 0 or cell.y >= 100: return fail("REGION_SOURCE", "原玩家 cell 超出 Site")
		var label := int(nav.labels[cell.y * 100 + cell.x])
		if label < 0: return fail("REGION_SOURCE", "原玩家缺合法接觸導航位置")
		second = {"ok": true, "points": [{"at": begin, "position": {"site": [coordinate.site.x, coordinate.site.y],
			"component": label, "route_component": -1, "cell": [cell.x, cell.y], "mode": str(active.get("mode", "land"))}}], "until": to}
	else:
		var player := region_travel_party()
		if not player.ok: return player
		var player_plan: Dictionary = player_status.plan
		var idle := {"site": [player_status.site.x, player_status.site.y], "component": int(player_status.component), "step_index": 0}
		second = _region_contact_sea_points(player.party, player_plan, to, context, cache, interval) if player_plan.get("mode") == "sea" \
			else _region_contact_land_points(player.party, player_plan, to, bool(player_status.get("moving", false)), idle, context, cache)
	if not second.ok: return second
	var candidates := RegionRoute.route_contact_candidates(first.points, second.points, begin, minf(float(first.until), float(second.until)))
	if not candidates.ok: return candidates
	for candidate: Dictionary in candidates.candidates:
		var a: Dictionary = candidate.first.position
		var b: Dictionary = candidate.second.position
		if str(a.get("mode", "land")) != str(b.get("mode", "land")): continue # Cross-layer attack needs its original engagement owner.
		if candidate.kind == "reverse_seam":
			var old: Dictionary = candidate.first_before.position
			var from := Vector2i(int(old.site[0]), int(old.site[1]))
			var next := Vector2i(int(a.site[0]), int(a.site[1]))
			var origin := _region_contact_navigation(from, context, str(a.mode), cache)
			var destination := _region_contact_navigation(next, context, str(a.mode), cache)
			if not origin.ok or not destination.ok: return origin if not origin.ok else destination
			if a.mode == "land" and not RegionRoute.seam_step(origin.data, destination.data, int(candidate.edge), int(candidate.offset)): continue
			if a.mode == "sea":
				var shift: Vector2i = TerrainData.DIRECTIONS[int(candidate.edge)] * 100
				var from_cell := RegionRoute.Adapter.boundary_cell(int(candidate.edge), int(candidate.offset))
				if not RegionRoute._water_step(origin.data, destination.data, shift, from_cell, from_cell + TerrainData.DIRECTIONS[int(candidate.edge)]): continue
		# Preserve BOTH true entry/exit references. The original P0 handler must
		# jointly materialize them; a reverse seam cannot use two unrelated final
		# arrival cells or overwrite either party's historical route position.
		var site: Array = b.site.duplicate() if candidate.kind == "reverse_seam" else a.site.duplicate()
		var component := int(b.route_component) if candidate.kind == "reverse_seam" else int(a.route_component)
		return {"ok": true, "contact": true, "at": float(candidate.at), "site": site, "component": component,
			"site_id": Grid.site_id(str(pin.atlas_id), Vector2i(int(site[0]), int(site[1]))), "contact_receipt": candidate}
	return {"ok": true, "contact": false}

# REQUIRED queue call change: payload keeps `contact_receipt` together with
# token/site/component. Root's player consumer freezes both ORIGINAL parties at
# contact.at, resolves this joint proof, full-binds, then consumes same-t effects.
# Never expose this resolver's hidden navigation/positions as NPC strategy intel.
# A sea position.cell is a component reference, not a current hull placement.
# The P0 handler re-reads its now-accepted ORIGINAL sea_cursor/action at contact.at
# and restores that exact partial original action/pose/reservation before bind.

func queue_region_gameplay_endpoints(unclipped_game_end: float, interval: Dictionary = {}) -> Dictionary:
	var registry := region_registry()
	var tokens: Array = registry.parties.keys()
	tokens.sort()
	for token: String in tokens:
		if str(registry.parties[token].get("phase", "")) != "travelling": continue
		var forecast := _preview_npc_party_to(token, unclipped_game_end, interval)
		if not forecast.ok: return forecast
		var contact := _region_first_player_route_contact(token, unclipped_game_end, interval)
		if not contact.ok: return contact
		if bool(contact.get("contact", false)):
			var queued_contact := queue_region_event("npc:%s:player-contact:%s:%d" % [token, str(contact.site_id), int(contact.component)],
				"player_encounter", float(contact.at), str(contact.site_id), {"token": token, "site": contact.site.duplicate(), "component": int(contact.component), "contact_receipt": contact.get("contact_receipt", {}).duplicate(true)}, true)
			if not queued_contact.ok: return queued_contact
		for event: Dictionary in forecast.events:
			var queued := queue_region_event("npc:%s:life:%d" % [token, int(event.sequence)], "life", float(event.at), "travel:" + token,
				{"token": token, "event": event.duplicate(true)})
			if not queued.ok: return queued
		if bool(forecast.arrived):
			var owner := Grid.site_id(str(pin.atlas_id), Vector2i(int(forecast.position.site[0]), int(forecast.position.site[1])))
			var player_present := owner == str(control.active_site_id)
			var queued := queue_region_event("npc:%s:arrival" % token, "player_arrival" if player_present else "arrival", float(forecast.at), owner,
				{"token": token, "site": forecast.position.site.duplicate(), "component": int(forecast.position.component)}, player_present)
			if not queued.ok: return queued
	for id: String in registry.battles:
		var battle: Dictionary = registry.battles[id]
		if str(battle.get("phase", "")) == "finished": continue
		if str(battle.get("site_id", "")) == str(control.active_site_id):
			var queued := queue_region_event("battle:%s:player:%.9f" % [id, float(control.logical_game_seconds)], "player_encounter", float(control.logical_game_seconds), str(battle.site_id), {"battle_id": id}, true)
			if not queued.ok: return queued
			continue
		var endpoint := RegionBattle.next_event(battle)
		if is_finite(endpoint) and endpoint <= unclipped_game_end:
			var queued := queue_region_event("battle:%s:%d" % [id, int(battle.revision)], "battle", endpoint, str(battle.site_id), {"battle_id": id})
			if not queued.ok: return queued
	for report: Dictionary in registry.reports:
		if bool(report.get("delivered", false)) or float(report.due) > unclipped_game_end: continue
		var queued := queue_region_event("report:" + str(report.id), "intel", float(report.due), str(report.receipt.get("receiver_scope", "unscoped")), {"report_id": str(report.id)})
		if not queued.ok: return queued
	return {"ok": true}

func _formula_interval(interval: Dictionary, owner: String) -> Dictionary:
	return {"game_start": float(interval.game_begin), "game_end": float(interval.game_end),
		"action_start": float(interval.action_begin), "action_end": float(interval.action_end),
		"tactical_action": float(interval.tactical_seconds), "time_scale": float(interval.scale),
		"permit_id": "%s:%d:%s" % [str(interval.epoch), int(interval.sequence), owner], "journal_revision": int(interval.sequence)}

# All previews succeed before a single original owner advances. The parent
# original shared-step then completes progress and calls commit below in its
# one synchronous accepted-interval tail, before incrementing registry.revision.

func prepare_region_gameplay_interval(interval: Dictionary) -> Dictionary:
	var held: Array[String] = _region_positive_player_death_ids()
	if not GameplayClock.player_barrier(region_registry(), float(control.logical_game_seconds), held).is_empty(): return fail("PLAYER_BARRIER", "同刻玩家先處理")
	if absf(float(interval.game_begin) - float(control.logical_game_seconds)) > 0.0000001: return fail("CLOCK_CONTRACT", "不是原共同區間")
	var registry := region_registry()
	var parties := {}
	var battles := {}
	var cold_labs := {}
	var permits := {}
	for token: String in registry.parties:
		if str(registry.parties[token].get("phase", "")) != "travelling": continue
		var preview := _preview_npc_party_to(token, float(interval.game_end), interval)
		if not preview.ok: return preview
		if absf(float(preview.at) - float(interval.game_end)) > 0.0000001: return {"ok": false, "code": "EVENT_CLIP_REQUIRED", "next_event": preview.at}
		var owner := "travel:" + token
		var permit := GameplayClock.begin_permit(registry, owner, "cold_exact", int(_marker.get("generation", 0)),
			float(control.logical_game_seconds), float(control.fire_clock.action_seconds), "original_region_travel", held)
		if not permit.ok: return permit
		permits[owner] = permit
		if not region_original_party_progress.is_valid(): return fail("MISSING_REGION_PARTY_PROGRESS")
		var host: Object = region_original_party_progress.get_object()
		if not host is TerrainLab or host.site_controller == null or host.site_controller.region_slot != self: return fail("INVALID_REGION_PARTY_PROGRESS")
		var restored: Dictionary = host.prepare_region_party_original_owner(token, preview.source_party, self)
		if not restored.ok: return restored
		if restored.lab._region_party_original_action_limit(float(interval.action_end) - float(interval.action_begin)) < float(interval.action_end) - float(interval.action_begin) - 0.000000001: return fail("EVENT_CLIP_REQUIRED")
		preview.original_lab = restored.lab
		parties[token] = preview
	for id: String in registry.battles:
		var battle: Dictionary = registry.battles[id]
		if str(battle.get("phase", "")) == "finished": continue
		var owner := str(battle.site_id)
		if owner == str(control.active_site_id):
			# This whole Site belongs to the original main live step. Battle life
			# metadata may remain, but it creates no formula interval or clock.
			if battle.has("prepared_endpoint"): return fail("EFFECTS_PENDING", "先消費原 P0 後同刻戰鬥效果")
			continue
		if battle.has("prepared_endpoint"): return fail("EFFECTS_PENDING", "原戰鬥同刻效果尚未消費")
		if not region_owner_lab.is_valid() or not region_formula_progress.is_valid() or not region_formula_effect_owners.is_valid():
			return fail("MISSING_REGION_ADAPTER", "缺真公式原 owner / endpoint consumer")
		var original: Dictionary = region_owner_lab.call(owner, "formula_active")
		if not original.get("ok", false) or not original.get("lab") is TerrainLab: return fail("COMMITTED_UNBOUND", "原公式 Site 尚未完整 bind")
		var permit := GameplayClock.begin_permit(registry, owner, "formula_active", int(_marker.get("generation", 0)),
			float(control.logical_game_seconds), float(control.fire_clock.action_seconds), "original_formula_site", held)
		if not permit.ok: return permit
		var people := RegionBattle.resolve_people(original.lab, battle)
		if not people.ok: return people
		var prepared := RegionBattle.prepare_interval(battle, _formula_interval(interval, owner), people.people)
		if not prepared.ok: return prepared
		permits[owner] = permit
		battles[id] = {"prepared": prepared, "lab": original.lab, "interval": interval.duplicate(true)}
	for owner: String in _region_original_labs:
		if owner == str(control.active_site_id) or permits.has(owner): continue
		var mode: Dictionary = registry.modes.get(owner, {})
		if str(mode.get("mode", "")) != "cold_exact": continue
		var original: TerrainLab = _region_original_labs[owner]
		if not is_instance_valid(original) or original.terrain == null or str(original.terrain.site.id) != owner:
			return fail("COMMITTED_UNBOUND", "原 cached cold Site 未完整綁定")
		var permit := GameplayClock.begin_permit(registry, owner, "cold_exact", int(_marker.get("generation", 0)),
			float(control.logical_game_seconds), float(control.fire_clock.action_seconds), "original_replay", held)
		if not permit.ok: return permit
		var accepted_action := float(interval.action_end) - float(interval.action_begin)
		var original_limit := original._region_owner_action_limit(accepted_action, float(interval.tactical_seconds))
		if original_limit < accepted_action - 0.000000001:
			return fail("EVENT_CLIP_REQUIRED", "先合併原 cold owner 的最早工作／人物端點")
		permits[owner] = permit
		cold_labs[owner] = original
	return {"ok": true, "generation": int(_marker.get("generation", 0)), "revision": int(registry.revision),
		"parties": parties, "battles": battles, "cold_labs": cold_labs, "permits": permits, "interval": interval.duplicate(true)}

# Called inside Root's all-original progress transaction, AFTER every candidate
# succeeded and BEFORE the one clock record. Each callback uses the exact same
# accepted interval, advances [begin,end), and defers the true endpoint effects.

func advance_prepared_region_formula_progress(prepared: Dictionary) -> Dictionary:
	if not prepared.get("ok", false) or int(prepared.generation) != int(_marker.get("generation", 0)) or int(prepared.revision) != int(region_registry().revision):
		return fail("STALE_REGION_PERMIT", "原 Region progress 候選過期")
	if absf(float(control.logical_game_seconds) - float(prepared.interval.game_begin)) > 0.00000001:
		return fail("CLOCK_CONTRACT", "原 progress 已非共同區間起点")
	for owner: String in prepared.permits:
		var checked := GameplayClock.check_permit(region_registry(), prepared.permits[owner], int(_marker.get("generation", 0)),
			float(prepared.interval.game_begin), float(prepared.interval.action_begin))
		if not checked.ok: return checked
	for id: String in prepared.battles:
		var candidate: Dictionary = prepared.battles[id]
		var progressed: Dictionary = region_formula_progress.call(candidate.lab, region_registry().battles[id], candidate.interval)
		if not progressed.get("ok", false): return progressed
		if not bool(progressed.get("complete", false)):
			return fail("INCOMPLETE_REGION_PROGRESS", "原公式 stages 未完成同一區間")
	for owner: String in prepared.get("cold_labs", {}):
		var original: TerrainLab = prepared.cold_labs[owner]
		var progressed: Dictionary = region_formula_progress.call(original, {}, prepared.interval)
		if not progressed.get("ok", false): return progressed
		if not progressed.get("complete", false): return fail("INCOMPLETE_REGION_PROGRESS", "原 cold stages 未完成共同區間")
	for token: String in prepared.parties:
		var candidate: Dictionary = prepared.parties[token]
		if not region_original_party_progress.is_valid(): return fail("MISSING_REGION_PARTY_PROGRESS")
		var progressed: Variant = region_original_party_progress.call(token, candidate.source_party, candidate.party, prepared.interval)
		if not progressed is Dictionary or not progressed.get("ok", false) or not progressed.get("complete", false) or progressed.get("token") != token or absf(float(progressed.get("game_seconds", -1.0)) - float(prepared.interval.game_end)) > 0.00000001 or absf(float(progressed.get("action_seconds", -1.0)) - float(prepared.interval.action_end)) > 0.00000001:
			return progressed if progressed is Dictionary and not progressed.get("ok", false) else fail("INCOMPLETE_PARTY_PROGRESS")
		candidate.party = progressed.party
	prepared.progress_complete = true
	return {"ok": true, "complete": true}

# AFTER original record_completed_* publishes the sole world/journal endpoint.
# That publisher advances registry revision exactly once. This method adds no
# clock and validates the accepted historical permit against unchanged modes.

func commit_region_gameplay_progress(prepared: Dictionary) -> Dictionary:
	var registry := region_registry()
	if not prepared.get("ok", false) or int(prepared.generation) != int(_marker.get("generation", 0)) or int(registry.revision) != int(prepared.revision) + 1:
		return fail("STALE_REGION_PERMIT", "原 Region consumer 須接同一次原時鐘發布")
	var interval: Dictionary = prepared.interval
	if absf(float(control.logical_game_seconds) - float(interval.game_end)) > 0.00000001 or absf(float(control.fire_clock.action_seconds) - float(interval.action_end)) > 0.00000001 or str(control.fire_clock.epoch) != str(interval.epoch) or int(control.fire_clock.sequence) != int(interval.sequence):
		return fail("CLOCK_CONTRACT", "原 consumer 完成端點與已發布 journal 不同")
	if (not prepared.battles.is_empty() or not prepared.get("cold_labs", {}).is_empty()) and not bool(prepared.get("progress_complete", false)):
		return fail("INCOMPLETE_REGION_PROGRESS", "原公式 progress 尚未完成")
	for owner: String in prepared.permits:
		var permit: Dictionary = prepared.permits[owner]
		var mode: Dictionary = registry.modes.get(owner, {})
		if mode.is_empty() or int(mode.revision) != int(permit.mode_revision) or str(mode.mode) != str(permit.mode) or str(mode.consumer) != str(permit.consumer) or str(mode.backend) != str(permit.backend) or int(mode.generation) != int(prepared.generation):
			return fail("STALE_REGION_PERMIT", "原 consumer mode 在區間中改變")
	# Every cached original reached this same journal endpoint. Synchronize its
	# original Fire watermark before a same-time common checkpoint can publish.
	var fire_updates := {}
	for owner: String in prepared.permits:
		if owner == str(control.active_site_id) or not _region_original_labs.has(owner): continue
		var original: TerrainLab = _region_original_labs[owner]
		if not is_instance_valid(original): return fail("COMMITTED_UNBOUND")
		var fire_check := validate_fire_settlement(original.terrain.site, control.fire_clock)
		if not fire_check.ok: return fire_check
		var watermark: Dictionary = original.terrain.site.fire_settlement
		if int(watermark.sequence) != int(interval.sequence) or absf(float(watermark.action_seconds) - float(interval.action_end)) > 0.00000001 or absf(float(watermark.game_seconds) - float(interval.game_end)) > 0.00000001: return fail("INCOMPLETE_REGION_PROGRESS")
		var coordinate := _coordinate(original.terrain)
		if not coordinate.ok: return coordinate
		var grace := original._fire_activity() or original._fire_replay_keep_tactical and float(original.terrain.site.get("combat_left", 0.0)) > 0.0
		fire_updates[owner] = {"coordinate": [coordinate.site.x, coordinate.site.y], "active": false, "fire_active": grace,
			"sequence": int(watermark.sequence), "action_seconds": float(watermark.action_seconds), "game_seconds": float(watermark.game_seconds)}
	for owner: String in fire_updates:
		control.fire_clock.index[owner] = fire_updates[owner]
		_fire_cold_candidates[owner] = {"data": _region_original_labs[owner].terrain,
			"coordinate": Vector2i(int(fire_updates[owner].coordinate[0]), int(fire_updates[owner].coordinate[1])),
			"target": float(interval.game_end), "sequence": int(interval.sequence), "epoch": str(interval.epoch)}
	for token: String in prepared.parties:
		var candidate: Dictionary = prepared.parties[token]
		_region_npc_party_runtime[token] = candidate.party
		registry.parties[token].position = {"site": candidate.position.site.duplicate(), "component": int(candidate.position.component)}
		registry.parties[token].phase = "pending_life" if not candidate.events.is_empty() else "travelling"
	for id: String in prepared.battles:
		registry.battles[id].prepared_endpoint = prepared.battles[id].prepared.duplicate(true)
		var queued := queue_region_event("battle:%s:interval:%d" % [id, int(interval.sequence)], "battle", float(interval.game_end), str(registry.battles[id].site_id), {"battle_id": id})
		if not queued.ok: return queued
	for owner: String in prepared.permits:
		registry.modes[owner].game_seconds = float(interval.game_end)
		registry.modes[owner].action_seconds = float(interval.action_end)
	return {"ok": true, "complete": true}

# Zero-time dispatcher before Root's positive elapsed guard and once after its
# sole accepted-interval record. Re-read the current registry after every bind
# or dispatch publication; no retained references survive a common marker move.

func consume_due_region_events() -> Dictionary:
	var consumed := 0
	for iteration: int in range(65536):
		var pending := pending_region_events()
		var proof := _region_player_down_settlement()
		var held: Array[String] = []
		if not proof.is_empty(): held.assign(proof.event_ids)
		var actionable: Array[Dictionary] = []
		for candidate: Dictionary in pending:
			if not held.has(str(candidate.id)): actionable.append(candidate)
		pending = actionable
		if pending.is_empty():
			var finished := _finish_original_cold_region_points()
			if not finished.ok: return finished
			return {"ok": true, "complete": held.is_empty(), "consumed": consumed,
				"player_barrier": not held.is_empty(), "restricted_settlement": not held.is_empty()}
		var event: Dictionary = pending[0].duplicate(true)
		if bool(event.player):
			if not region_player_event_consumer.is_valid():
				return fail("MISSING_PLAYER_EVENT_CONSUMER", "缺原 P0 完整 materialize/bind consumer")
			var player_result: Dictionary = region_player_event_consumer.call(event)
			if not player_result.get("ok", false): return player_result
			if not bool(player_result.get("receipt", {}).get("complete", false)):
				if player_result.get("receipt", {}).get("effects_complete") != true: return fail("COMMITTED_UNBOUND", "原 P0 尚未提供完整 bind 收據")
				var down := _region_player_down_settlement()
				if not down.is_empty() and down.event_ids.has(str(event.id)): continue
				return {"ok": true, "complete": false, "player_barrier": true, "consumed": consumed, "event": event, "receipt": player_result.receipt}
			var player_completed := complete_region_event(str(event.id))
			if not player_completed.ok: return player_completed
			consumed += 1
			continue
		# P0 above completes first. Cold exact contacts/work retain their
		# original point ordering before lower-priority arrivals/evaluations.
		var finished := _finish_original_cold_region_points()
		if not finished.ok: return finished
		var registry := region_registry()
		match str(event.kind):
			"intel":
				RegionAI.reports_due(registry, float(event.at))
			"battle":
				var id := str(event.payload.get("battle_id", ""))
				var battle: Dictionary = registry.battles.get(id, {})
				if battle.is_empty(): return fail("NO_TARGET", "原戰鬥引用已失")
				if battle.has("prepared_endpoint"):
					var requested_mode := "live" if str(battle.site_id) == str(control.active_site_id) else "formula_active"
					var mode: Dictionary = registry.modes.get(str(battle.site_id), {})
					if str(mode.get("mode", "")) != requested_mode or not bool(mode.get("activation", {}).get("complete", false)):
						return fail("COMMITTED_UNBOUND", "先以真完整 bind 消費同刻原效果")
					var original: Dictionary = region_owner_lab.call(str(battle.site_id), requested_mode)
					if not original.get("ok", false): return original
					var extras: Dictionary = region_formula_effect_owners.call(original.lab, battle)
					var applied := RegionBattle.apply_pending(battle, battle.prepared_endpoint, RegionBattle.owner_callbacks(original.lab, battle, extras))
					if not applied.ok: return applied
					# The active original consumer finishes its own point after
					# world dispatch. A distinct cold original finishes here.
					if not original.lab._region_point_consuming:
						var cold_effects: Dictionary = original.lab.consume_region_point(false)
						if not cold_effects.get("ok", false) or not cold_effects.get("complete", false): return cold_effects
					battle.erase("prepared_endpoint")
			"life":
				if not event.payload.has("token"):
					return {"ok": true, "complete": false, "event": event, "consumed": consumed}
				if not region_party_life_consumer.is_valid(): return fail("MISSING_REGION_ADAPTER", "缺原 NPC 生命 materialize consumer")
				var token := str(event.payload.token)
				var party := {"ok": true, "party": {"party_id": token, "controller": "npc", "entered": registry.parties.get(token, {}).duplicate(true)}}
				if not event.payload.has("entered_site"):
					party = _region_npc_party(token)
					if not party.ok: return party
				var result: Dictionary = region_party_life_consumer.call(token, event.payload.event, party.party)
				if not result.get("ok", false) or not result.get("party") is Dictionary or not bool(result.get("receipt", {}).get("complete", false)):
					return fail("COMMITTED_UNBOUND", "原生命出口尚未提供真收據")
				if not event.payload.has("entered_site"):
					_region_npc_party_runtime[token] = result.party
					registry.parties[token].phase = "travelling"
			"evaluation":
				var original: Dictionary = region_owner_lab.call(str(event.owner), "live" if str(event.owner) == str(control.active_site_id) else "cold_exact")
				if not original.get("ok", false): return original
				var lab: TerrainLab = original.lab
				lab.review_region_duty(float(event.at), registry)
				var proposed := {"ok": true, "intents": []}
				if region_dispatch_intents.is_valid():
					proposed = region_dispatch_intents.call(lab, scoped_region_intel(lab, float(event.at)), float(event.at))
					if not proposed.get("ok", false): return proposed
				# Complete/queue BEFORE a dispatch common-marker publication.
				var completed_evaluation := complete_region_event(str(event.id))
				if not completed_evaluation.ok: return completed_evaluation
				var queued := queue_region_event("evaluation:%s:%.6f" % [str(event.owner), float(event.at) + REGION_EVALUATION_SECONDS], "evaluation", float(event.at) + REGION_EVALUATION_SECONDS, str(event.owner))
				if not queued.ok: return queued
				for intent: Dictionary in proposed.get("intents", []):
					var candidate := prepare_npc_region_dispatch(lab, str(intent.nation_id), int(intent.team_id), Vector2i(int(intent.target_coordinate[0]), int(intent.target_coordinate[1])), int(intent.start_component), intent.steps)
					if not candidate.ok: continue
					var dispatched := commit_npc_region_dispatch(candidate)
					if not dispatched.ok: return dispatched
				consumed += 1
				continue
			"arrival", "reinforcement":
				var prepared_arrival := prepare_npc_region_arrival(event)
				if not prepared_arrival.ok: return prepared_arrival
				var arrived := commit_npc_region_arrival(prepared_arrival)
				if not arrived.ok: return arrived
				consumed += 1
				continue
			_:
				return {"ok": true, "complete": false, "event": event, "consumed": consumed}
		var completed := complete_region_event(str(event.id))
		if not completed.ok: return completed
		consumed += 1
	return fail("REGION_EVENT_LIMIT", "同刻原事件超過容量，不推新時間")

func consume_region_gameplay_events() -> Dictionary:
	return consume_due_region_events()

# Scope is the current original owner; a same-number person in another Site
# receives no intel. Cross-Site reports must carry its actual stable person ref.

func scoped_region_intel(lab: TerrainLab, at: float) -> Dictionary:
	var result := {}
	var site_id := str(lab.terrain.site.id)
	var present: Array[int] = []
	for actor: TerrainTestCharacter in lab.combat_actors:
		if is_instance_valid(actor) and not lab._combat_target_in_site(actor.person_id).is_empty(): present.append(actor.person_id)
	for team: TerrainArmy in lab.combat_armies:
		for index: int in team.combat_units.size():
			var identity := team.combat_identity(index)
			if not lab._combat_target_in_site(identity).is_empty() and not present.has(identity): present.append(identity)
	for receiver: int in present:
		var known := RegionAI.view(region_registry(), receiver, at, site_id, RegionAI.person_ref(lab.terrain.site, receiver))
		for object: String in known:
			var receipt: Dictionary = known[object]
			result[str(receipt.id)] = receipt
	return result

# Add this to ALL original active/cold/travel checkpoint paths before _publish.
# Files without the common marker remain unreferenced; a BUSY active checkpoint
# must not publish these bodies by itself. No body is embedded in control JSON.

func collect_region_party_checkpoint(generation: int, next_control: Dictionary) -> Dictionary:
	for token: String in _region_npc_party_runtime:
		var reference: Dictionary = next_control.region_gameplay.parties.get(token, {})
		if str(reference.get("phase", "")) not in ["travelling", "pending_life", "materializing"]: continue
		var relative := "travel/%s/party_g%09d_r%09d.json" % [token, generation, int(next_control.region_gameplay.revision)]
		var written := _write_new_document(folder.path_join(relative), {"version": 1, "token": token, "pin": pin.duplicate(true),
			"encoding": "godot_var_v1", "party": Marshalls.raw_to_base64(var_to_bytes(_region_npc_party_runtime[token]))})
		if not written.ok: return written
		reference.party_path = relative
		reference.party_sha256 = FileAccess.get_sha256(folder.path_join(relative))
	return {"ok": true}

func _finish_original_cold_region_points() -> Dictionary:
	for owner: String in _region_original_labs:
		if owner == str(control.active_site_id): continue
		if str(region_registry().modes.get(owner, {}).get("mode", "")) != "cold_exact": continue
		var original: TerrainLab = _region_original_labs[owner]
		if not is_instance_valid(original): return fail("COMMITTED_UNBOUND", "原 cold endpoint owner 已失")
		if original._region_point_pending.is_empty(): continue
		var consumed: Dictionary = original.consume_region_point(false)
		if not consumed.get("ok", false) or not consumed.get("complete", false): return consumed
	if not region_registry().parties.is_empty():
		if not region_original_party_zero.is_valid(): return fail("MISSING_REGION_PARTY_ENDPOINT")
		var settled: Variant = region_original_party_zero.call()
		if not settled is Dictionary or not settled.get("ok", false) or not settled.get("complete", false): return settled if settled is Dictionary else fail("INCOMPLETE_PARTY_ENDPOINT")
	return {"ok": true, "complete": true}

const RegionAI = preload("res://scripts/region_lab/region_gameplay_ai.gd")

const RegionBattle = preload("res://scripts/region_lab/region_gameplay_battle.gd")

const RegionDuties = preload("res://scripts/terrain_lab/site_duty_ai.gd")

const REGION_EVALUATION_SECONDS := 3600.0

var region_owner_lab: Callable

var region_bind_candidate: Callable

var region_formula_progress: Callable

var region_formula_effect_owners: Callable

var region_party_life_consumer: Callable

var region_dispatch_intents: Callable

var region_player_event_consumer: Callable

var _region_original_labs: Dictionary = {} # Site id -> its complete original bound TerrainLab reference.

var _region_npc_party_runtime: Dictionary = {}

var _region_npc_plan_runtime: Dictionary = {}

# Only an actual existing bound original can prepare a new context. Durable
# unbound readbacks may only retain their already validated exact snapshot.
func _region_bound_original_lab(data: TerrainData) -> TerrainLab:
	if data == null or data.site.is_empty(): return null
	var identity := str(data.site.id)
	var original: TerrainLab = _region_original_labs.get(identity)
	if identity == str(control.active_site_id):
		var callback: Variant = data.get_meta(&"region_bind_receipt", Callable())
		if not callback is Callable or not callback.is_valid(): return null
		var owner: Object = callback.get_object()
		if not owner is TerrainLab: return null
		original = owner
	if not is_instance_valid(original) or original.terrain != data or original._region_bound_data != data or original.site_controller == null or original.site_controller.region_slot != self:
		return null
	return original

const RegionTechnology = preload("res://scripts/terrain_lab/site_technology.gd")

var _region_sea_sources: Dictionary = {} # token -> WeakRef to the original active TerrainData.

var _region_arrival_retry: Dictionary = {} # detached placement proof; cleared after commit.

func region_technology_transfer_guard(state: Dictionary, spec_or_party: Dictionary) -> Dictionary:
	if not spec_or_party.has("content"):
		# These fields are filled by RegionTravel only AFTER its real asset/body
		# closure is determined. A guessed team/boat list is insufficient.
		var token := str(spec_or_party.get("transfer_token", ""))
		var source_site_id := str(spec_or_party.get("source_site_id", ""))
		if token.is_empty() or source_site_id != str(state.get("id", "")) \
				or spec_or_party.get("travel_holder_site_id") != "travel:" + token \
				or not spec_or_party.get("region_movers") is Dictionary or spec_or_party.region_movers.is_empty():
			return fail("INVALID_FAMILY_TRANSFER", "族科技出發缺實際 closure／原 source／移交 token")
		return RegionTechnology.prepare_holder_departure(source_site_id, state.get("family", {}),
			spec_or_party.region_movers, str(spec_or_party.get("controller", "player")), token)
	var party: Dictionary = spec_or_party
	var content: Dictionary = party.content
	var reference: Dictionary = content.get("travel_identity", {}).get("refs", {}).get("family", {}).get("controlled", {})
	var incoming: Dictionary = content.get("family", content.get("family_refs", {}))
	var receipt: Dictionary = party.get("arrival_mapping", {})
	if receipt.get("token") != party.get("party_id") or not receipt.get("maps", {}).get("person") is Dictionary \
			or receipt.maps.person.is_empty() or reference.is_empty():
		return fail("INVALID_FAMILY_TRANSFER", "族科技到站缺原移交映射／FamilyRef")
	# RegionTravel intentionally leaves full family/technology history in its
	# original IDs. Only this boundary converts the allocator's new-ID strings
	# to the exact integer values expected by the original technology API.
	var mapping: Dictionary = receipt.duplicate(true)
	var targets := {}
	for original: Variant in receipt.maps.person:
		var target: Variant = receipt.maps.person[original]
		if not original is String or not original.is_valid_int() or str(int(original)) != original \
				or not target is String or not target.is_valid_int() or str(int(target)) != target \
				or int(original) <= 0 or int(target) <= 0 or int(target) == 1000000000 or targets.has(int(target)):
			return fail("INVALID_FAMILY_TRANSFER", "族科技原人物映射不是單射")
		targets[int(target)] = true
		mapping.maps.person[original] = int(target)
	var destination: Dictionary = state.get("family", {})
	var npc := str(party.get("controller", "player")) == "npc"
	# An unrelated NPC presents its immutable holder reference for admission;
	# it does not gain the destination's player family/control registry.
	var same_family: bool = incoming.get("family_id", "") == destination.get("family_id", "") and not destination.is_empty()
	var admitted := RegionTechnology.prepare_holder_arrival(reference, incoming,
		destination if not npc or same_family else {}, str(state.get("id", "")), mapping)
	if not admitted.ok: return admitted
	if npc:
		if not RegionTechnology.is_holder_reference(incoming.get("technology")):
			return fail("INVALID_FAMILY_TRANSFER", "NPC 不能持第二份完整族科技 archive")
		admitted.destination_family = destination.duplicate(true)
	return admitted


func prepare_region_sea_leg(source_data: TerrainData, boat_ids: Array[String], destination_site: Vector2i,
		anchor: Vector2i, facing: Vector2i, options: Dictionary = {}) -> Dictionary:
	var coordinate := _coordinate(source_data)
	if not coordinate.ok: return coordinate
	var delta: Vector2i = destination_site - coordinate.site
	if absi(delta.x) + absi(delta.y) != 1:
		return fail("NOT_ADJACENT", "原海路 leg 必須是相邻 Site；多段由同一原路線逐 leg 提交")
	if options.get("mode", "sea") != "sea": return fail("INVALID", "原船 leg 的旅行模式非法")
	# This runs the original _transfer_pair, full hull/water seam, settlement,
	# prepared checksums and journal. No duration or ACTION completion is forged.
	var prepared := prepare_ship_transfer(source_data, destination_site, boat_ids, anchor, facing, true)
	if not prepared.ok: return prepared
	_region_sea_sources[str(prepared.token)] = weakref(source_data)
	return prepared


func commit_region_mode_transition(token: String, bind_guard: Callable = Callable()) -> Dictionary:
	var requested := _request(token)
	if not requested.ok: return requested
	if int(requested.request.version) != 2 or requested.request.get("route_mode") != "adjacent_water_seam":
		return fail("INVALID", "模式交接 token 不是原相邻海路 leg")
	var source_data: TerrainData
	var handle: Variant = _region_sea_sources.get(token)
	if handle is WeakRef: source_data = handle.get_ref()
	if source_data == null:
		# Reopen may use only the marker-selected ORIGINAL source, with no time
		# rewrite and no replacement of a live active owner by a cached candidate.
		var from := Vector2i(int(requested.request.from[0]), int(requested.request.from[1]))
		var path := effective_site_path(from)
		if not path.ok: return path
		var loaded := _load_checked(str(path.path), from)
		if not loaded.ok: return loaded
		source_data = loaded.data
		var settlement := validate_settlement(source_data.site, control.logical_game_seconds)
		if not settlement.ok or bool(settlement.legacy) or float(settlement.pending) > 0.00001:
			return settlement if not settlement.ok else fail("UNSETTLED_SITE", "重開海路须先恢复並完成原活動 source owner 的步進")
	var committed := commit_ship_transfer(token, source_data, bind_guard)
	if committed.ok: _region_sea_sources.erase(token)
	return committed


func retry_region_arrival(options: Dictionary = {}) -> Dictionary:
	var status := region_travel_status()
	if not status.ok: return status
	if not bool(status.get("pending", false)) or not bool(status.get("arrived", false)):
		return fail("INCOMPLETE_JOURNEY", "只有抵達後受阻的原旅隊能重試入界")
	if not region_player_barrier().is_empty() and not bool(status.get("barrier", false)):
		return fail("PENDING_EVENT", "須先消費目前原事件 barrier")
	var destination := _ship_destination(status.destination, float(control.logical_game_seconds))
	if not destination.ok: return destination
	var loaded := region_travel_party()
	if not loaded.ok: return loaded
	var plan: Dictionary = status.plan
	var step: Dictionary = plan.steps[int(status.step_index)] if bool(status.get("barrier", false)) else plan.steps.back()
	var original_entry := RegionRoute.entry_cell(step)
	var entry: Vector2i = options.get("entry", original_entry)
	var poses: Dictionary = options.get("vehicle_poses", step.get("vehicle_poses", {}))
	# A different boundary or vehicle pose requires the existing route search and
	# its recorded complete geometric proof. Retry cannot teleport to a new cell.
	if entry != original_entry or poses != step.get("vehicle_poses", {}):
		return fail("STALE_ROUTE", "請先用原路線重新規劃所選入界位置／車船姿向")
	var generation := int(_marker.get("generation", 0)) + 1
	var path := _generation_path(generation, status.destination)
	var nav := Env.navigation_for_state(destination.data, destination.data.site)
	var placed := RegionTravel.insert(destination.data.site, loaded.party, nav, entry, path,
		float(status.departure_game_seconds), float(control.logical_game_seconds),
		{"generation": generation, "family_transfer_guard": region_family_transfer_guard, "vehicle_poses": poses})
	if not placed.ok: return placed
	_region_arrival_retry = {"token": str(status.token), "generation": generation, "entry": entry,
		"vehicle_poses": poses.duplicate(true), "mapping": placed.mapping.duplicate(true)}
	# This is a preflight. Original SiteController still opens the candidate,
	# commit_region_arrival publishes, and Lab bind receipt makes it usable.
	return {"ok": true, "ready": true, "generation": generation, "destination": status.destination}

# Existing stop_region_travel's arrived early-return must be removed. The
# current node (including an arrived-but-blocked node) remains the same owner,
# then the existing empty plan fields are published for new planning. Never
# erase the actual party records or alter their upkeep.at/distance/history.
# Existing commit_region_arrival may consume _region_arrival_retry only when
# token and generation still match, then clear it AFTER successful publication.
# A mode UI action first materializes the party at its CURRENT original Site;
# the original Vehicles embark/disembark completes there before extraction of
# the next mode. This fragment deliberately exposes no direct mode-string flip.

# Mandatory original Slot dispatches:
# set_region_travel_plan(steps): if steps[0].mode == "sea", call the setter below.
# region_travel_status(): if loaded plan.mode == "sea", call the status adapter.
# advance_region_travel(max_steps): sea dispatch passes the same max_steps below.
# stop_region_travel(): when a sea leg is incomplete, set upkeep.sea_stop_after_leg
# and return {ok:true,pending:true}; do not discard any original partial action.


func _region_sea_timeline(steps: Array, party: Dictionary) -> Dictionary:
	var prepared := prepare_region_route_context(null, party)
	if not prepared.ok: return prepared
	var checked := RegionRoute.verify_steps(source, steps, prepared.context)
	if not checked.ok: return checked
	var actions: Array = []
	var at := 0.0
	var metres := 0.0
	var content: Dictionary = party.content
	var vehicles: Array = content.get("vehicles", {}).values()
	for leg: int in range(1, steps.size()):
		var from := Vector2i(int(steps[leg - 1].site[0]), int(steps[leg - 1].site[1]))
		var to := Vector2i(int(steps[leg].site[0]), int(steps[leg].site[1]))
		var first := RegionRoute.effective_terrain(source, from, prepared.context)
		var second := RegionRoute.effective_terrain(source, to, prepared.context)
		if not first.ok or not second.ok: return first if not first.ok else second
		var timeline := RegionRoute.sea_action_steps(first.data, second.data, vehicles,
			steps[leg - 1].vehicle_poses, steps[leg].vehicle_paths,
			RegionRoute.opposite(int(steps[leg].edge)), content)
		if not timeline.ok: return timeline
		for raw: Dictionary in timeline.actions:
			var action := raw.duplicate(true)
			action.leg_index = leg - 1
			action.from_site = [from.x, from.y]
			action.to_site = [to.x, to.y]
			action.action_begin = at
			action.action_end = at + float(action.duration)
			at = float(action.action_end)
			metres += float(action.metres)
			actions.append(action)
	return {"ok": true, "actions": actions, "action_seconds": at, "metres": metres}


func set_region_sea_travel_plan(steps: Array) -> Dictionary:
	var status := region_travel_status()
	if not status.ok: return status
	if steps.size() < 2 or not bool(status.get("pending", false)): return fail("INVALID", "海路缺少原旅隊或完整航段")
	if bool(status.get("moving", false)) or not region_player_barrier().is_empty(): return fail("BUSY", "先在原航段安全端點停妥並處理事件")
	var loaded := region_travel_party()
	if not loaded.ok: return loaded
	var candidate: Dictionary = loaded.party.duplicate(true)
	if str(candidate.get("mode", "")) != "sea": return fail("NOT_EMBARKED", "先由原登船 owner 完成全隊上船")
	var timeline := _region_sea_timeline(steps, candidate)
	if not timeline.ok: return timeline
	var journey := region_travel_journey()
	var number := int(journey.plans) + 1
	var relative := "travel/%s/sea_plan_%06d.json" % [str(journey.token), number]
	var seconds: Array = []
	for _step: Dictionary in steps: seconds.append(0.0) # Sea status never uses static game ETA.
	var plan := {"version": 2, "token": str(journey.token), "mode": "sea", "steps": steps.duplicate(true),
		"seconds": seconds, "metres": float(timeline.metres), "speed_mps": 0.0,
		"destination": steps.back().site.duplicate(), "action_steps": timeline.actions,
		"action_seconds": float(timeline.action_seconds)}
	var written := _write_new_document(folder.path_join(relative), plan)
	if not written.ok: return written
	candidate.upkeep.plan_id = relative
	candidate.upkeep.distance = 0.0
	candidate.upkeep.sea_cursor = {"version": 1, "plan_id": relative, "action_index": 0,
		"elapsed": 0.0, "duration": 0.0, "completed_metres": 0.0}
	candidate.upkeep.sea_stop_after_leg = false
	var party_relative := "travel/%s/sea_party_%06d.json" % [str(journey.token), number]
	written = _write_new_document(folder.path_join(party_relative), {"version": 1, "token": str(journey.token),
		"pin": pin.duplicate(true), "encoding": "godot_var_v1", "party": Marshalls.raw_to_base64(var_to_bytes(candidate))})
	if not written.ok: return written
	journey.position = {"site": [status.site.x, status.site.y], "component": 0}
	journey.plan_path = relative
	journey.plan_sha256 = FileAccess.get_sha256(folder.path_join(relative))
	journey.party_path = party_relative
	journey.party_sha256 = FileAccess.get_sha256(folder.path_join(party_relative))
	journey.plan_started_game_seconds = float(control.logical_game_seconds)
	journey.plans = number
	var published := _publish(_marker.get("sites", {}), control, str(_marker.get("transfer_token", "")), journey)
	if not published.ok: return published
	_travel_party_runtime = candidate
	_travel_party_runtime_token = str(journey.token)
	return {"ok": true, "plan": plan, "action_seconds": float(timeline.action_seconds), "game_seconds": 0.0, "eta_pending": true}


func region_sea_travel_status(plan: Dictionary, party: Dictionary, base: Dictionary) -> Dictionary:
	var cursor: Dictionary = party.get("upkeep", {}).get("sea_cursor", {})
	if int(cursor.get("version", 0)) != 1 or cursor.get("plan_id") != region_travel_journey().get("plan_path") \
			or not plan.get("action_steps") is Array or not _whole(cursor.get("action_index"), 0, plan.action_steps.size()) \
			or not _seconds(cursor.get("elapsed")) or not _seconds(cursor.get("duration")) \
			or float(cursor.elapsed) > float(cursor.duration) or float(cursor.duration) == 0.0 and float(cursor.elapsed) != 0.0:
		return fail("CORRUPT_SAVE", "原船 ACTION cursor／plan 不符")
	var index := int(cursor.action_index)
	var complete: bool = index == plan.action_steps.size()
	var leg: int = plan.steps.size() - 1 if complete else int(plan.action_steps[index].leg_index)
	var site := Vector2i(int(plan.steps[leg].site[0]), int(plan.steps[leg].site[1]))
	base.site = site
	base.component = 0
	base.step_index = leg
	base.arrived = complete
	base.moving = not complete
	base.remaining_metres = maxf(0.0, float(plan.metres) - float(party.upkeep.get("distance", 0.0)))
	base.remaining_game_seconds = 0.0
	base.eta_pending = true
	base.sea_action_index = index
	base.sea_action_elapsed = float(cursor.elapsed)
	base.sea_action_duration = float(cursor.duration)
	base.safe_to_materialize = complete or float(cursor.elapsed) == 0.0 and (index == 0 or int(plan.action_steps[index - 1].leg_index) != leg)
	base.vehicle_poses = plan.steps[leg].get("vehicle_poses", {}).duplicate(true)
	return base


func _region_sea_action_duration(party: Dictionary, action: Dictionary) -> Dictionary:
	var vehicle: Dictionary = party.content.vehicles.get(str(action.vehicle_id), {})
	if vehicle.is_empty() or str(vehicle.get("kind", "")) != "ship": return fail("NO_SHIP", "原 ACTION 船已不存在")
	var metrics := RegionTravel.ship_metrics(party.content, vehicle)
	if not bool(metrics.get("driver_ready", false)): return fail("NO_CREW", "原舵手未在有效原掌舵席")
	var kind := str(vehicle.ship_type)
	var speed := Ship.speed(kind, int(metrics.people), float(metrics.load), int(metrics.crew), action.action == "dock", action.action == "reverse")
	var duration := Ship.turn_seconds(kind, int(metrics.crew)) if action.action == "turn" else (1.0 / speed if speed > 0.0 else INF)
	if not is_finite(duration) or duration <= 0.0: return fail("NO_CREW", "原船 crew／載重不容許 ACTION")
	return {"ok": true, "duration": duration}


func region_sea_pose_projection(plan: Dictionary, party: Dictionary) -> Dictionary:
	var cursor: Dictionary = party.get("upkeep", {}).get("sea_cursor", {})
	if not plan.get("steps") is Array or plan.steps.is_empty() or not plan.get("action_steps") is Array \
		or not _whole(cursor.get("action_index"), 0, plan.action_steps.size()) or not _seconds(cursor.get("elapsed")) \
		or not _seconds(cursor.get("duration")) or float(cursor.elapsed) > float(cursor.duration): return fail("CORRUPT_SEA_CURSOR")
	var poses := {}
	var first: Dictionary = plan.steps[0]
	var first_origin := Vector2(int(first.site[0]) * Grid.SITE_CELLS, -int(first.site[1]) * Grid.SITE_CELLS)
	for identity: String in first.get("vehicle_poses", {}):
		var pose: Dictionary = first.vehicle_poses[identity]
		var at := first_origin + Vector2(float(pose.anchor[0]), float(pose.anchor[1]))
		poses[identity] = {"world_anchor": [at.x, at.y], "facing": pose.facing.duplicate(), "moving": false}
	var index := int(cursor.action_index)
	for number: int in range(index):
		var action: Dictionary = plan.action_steps[number]
		var at := Vector2(int(action.from_site[0]) * Grid.SITE_CELLS + float(action.anchor[0]), -int(action.from_site[1]) * Grid.SITE_CELLS + float(action.anchor[1]))
		poses[str(action.vehicle_id)] = {"world_anchor": [at.x, at.y], "facing": action.facing.duplicate(), "moving": false}
	if index < plan.action_steps.size():
		var action: Dictionary = plan.action_steps[index]
		if not poses.has(str(action.vehicle_id)): return fail("CORRUPT_SEA_CURSOR")
		var origin := Vector2(int(action.from_site[0]) * Grid.SITE_CELLS, -int(action.from_site[1]) * Grid.SITE_CELLS)
		var from := origin + Vector2(float(action.from[0]), float(action.from[1]))
		var to := origin + Vector2(float(action.anchor[0]), float(action.anchor[1]))
		var weight := float(cursor.elapsed) / float(cursor.duration) if float(cursor.duration) > 0.0 else 0.0
		var at := from.lerp(to, weight)
		poses[str(action.vehicle_id)] = {"world_anchor": [at.x, at.y], "facing": action.from_facing.duplicate(),
			"moving": float(cursor.elapsed) > 0.0, "action": str(action.action), "from": [from.x, from.y], "to": [to.x, to.y],
			"from_facing": action.from_facing.duplicate(), "to_facing": action.facing.duplicate(), "weight": weight,
			"elapsed_action_seconds": float(cursor.elapsed), "duration_action_seconds": float(cursor.duration)}
	return {"ok": true, "poses": poses, "action_index": index}


func _region_player_sea_candidate(party: Dictionary, plan: Dictionary, action: Dictionary,
		duration: float, moving: bool, interval: Dictionary) -> Dictionary:
	var options := {"moving": moving, "safe_rest": true, "distance_mode": "sea_action", "active_ship_ids": [str(action.vehicle_id)]}
	var endpoint := RegionTravel.next_upkeep_event(party, options.merged({"until": float(interval.game_end)}, true))
	if not endpoint.ok: return endpoint
	var end := minf(float(interval.game_end), float(endpoint.at))
	var outcome := RegionTravel.advance_upkeep(party, end, options)
	if not outcome.ok: return outcome
	var action_delta := GameplayClock.action_for_game(float(outcome.at) - float(interval.game_begin),
		float(interval.scale), float(interval.tactical_seconds))
	var candidate: Dictionary = outcome.party
	var next_cursor: Dictionary = candidate.upkeep.sea_cursor
	var reroute_ready := false
	if moving:
		if duration <= 0.0 or action_delta > duration - float(next_cursor.elapsed) + 0.00000001: return fail("SEA_ACTION_CONTRACT")
		next_cursor.duration = duration
		next_cursor.elapsed = minf(duration, float(next_cursor.elapsed) + action_delta)
		candidate.upkeep.distance = float(candidate.upkeep.distance) + float(action.metres) * action_delta / duration
		if float(next_cursor.elapsed) >= duration - 0.00000001:
			next_cursor.completed_metres = float(candidate.upkeep.distance)
			next_cursor.action_index = int(next_cursor.action_index) + 1
			next_cursor.elapsed = 0.0
			next_cursor.duration = 0.0
			var next_index := int(next_cursor.action_index)
			var leg_finished: bool = next_index == plan.action_steps.size() or int(plan.action_steps[next_index].leg_index) != int(action.leg_index)
			if leg_finished and bool(candidate.upkeep.get("sea_stop_after_leg", false)): reroute_ready = true
	outcome.action_seconds = action_delta
	outcome.reroute_ready = reroute_ready
	outcome.arrived = int(next_cursor.action_index) >= plan.action_steps.size()
	return outcome


func advance_region_sea_travel(max_steps: int) -> Dictionary:
	if not region_original_travel_interval.is_valid() or not region_original_party_progress.is_valid():
		return fail("MISSING_REGION_ADAPTER", "原海路須全部Site／NPC／公式／作業共同區間")
	var before := float(control.logical_game_seconds)
	var count := 0
	var reroute_ready := false
	for _index: int in range(clampi(max_steps, 0, 100000)):
		var status := region_travel_status()
		if not status.ok: return status
		if bool(status.arrived) or not bool(status.moving) or not region_player_barrier().is_empty(): break
		var loaded := region_travel_party()
		if not loaded.ok: return loaded
		var party: Dictionary = loaded.party
		if absf(float(party.upkeep.at) - float(control.logical_game_seconds)) > 0.0000001: return fail("UNSETTLED_PARTY", "海路原人與共同時鐘不同")
		var plan: Dictionary = status.plan
		var cursor: Dictionary = party.upkeep.sea_cursor
		var action: Dictionary = plan.action_steps[int(cursor.action_index)]
		var transport := RegionTravel.prepare_transport(party.duplicate(true))
		if not transport.ok: return transport
		var moving := bool(transport.can_move) and not bool(party.upkeep.resting)
		var duration := float(cursor.duration)
		if duration <= 0.0 and moving:
			var measured := _region_sea_action_duration(party, action)
			if not measured.ok: return measured
			duration = float(measured.duration)
		# Once an original action starts its paid duration is immutable even if
		# a meal changes load mid-step. At the next action speed is remeasured.
		var action_budget := RegionTravel.STEP_ACTION_SECONDS
		if moving: action_budget = minf(action_budget, maxf(0.0, duration - float(cursor.elapsed)))
		var candidate := func(interval: Dictionary) -> Dictionary:
			return _region_player_sea_candidate(party, plan, action, duration, moving, interval)
		var accepted: Variant = region_original_travel_interval.call({"token": str(status.token), "party": party,
			"maximum_action_seconds": action_budget, "scale": RegionTravel.STEP_SCALE,
			"candidate": candidate, "party_progress": region_original_party_progress})
		if not accepted is Dictionary: return fail("INVALID_REGION_RECEIPT")
		var committed := _region_accept_player_travel_interval(str(status.token), accepted)
		if not committed.ok: return committed
		if committed.get("pending", false): break
		reroute_ready = bool(committed.outcome.get("reroute_ready", false))
		count += 1
		if reroute_ready or not committed.outcome.get("events", []).is_empty(): break
	_prune_recoverable_fire_journal()
	var after := region_travel_status()
	return {"ok": true, "steps": count, "advanced": float(control.logical_game_seconds) - before,
		"arrived": bool(after.get("arrived", false)), "barrier": bool(after.get("barrier", false)),
		"resting": bool(_travel_party_runtime.get("upkeep", {}).get("resting", false)),
		"reroute_ready": reroute_ready, "discard_accumulator": reroute_ready or bool(after.get("barrier", false)),
		"now": float(control.logical_game_seconds)}

# Original ship destination initialization must also set:
# data.site.world_pin = pin.duplicate(true)
# before _settle_cold_candidate / Store validation. The pin is immutable policy
# projection, not a new holder. The original Slot creation owns its value.


func prepare_region_mode_stop() -> Dictionary:
	var status := region_travel_status()
	if not status.ok: return status
	if not bool(status.get("pending", false)): return fail("NO_TARGET", "沒有原旅隊")
	if not region_player_barrier().is_empty(): return fail("PENDING_EVENT", "先處理旅隊原生命／玩家事件")
	var loaded := region_travel_party()
	if not loaded.ok: return loaded
	var candidate: Dictionary = loaded.party.duplicate(true)
	if str(candidate.get("mode", "land")) == "sea" and bool(status.get("moving", false)) and not bool(status.get("safe_to_materialize", false)):
		candidate.upkeep.sea_stop_after_leg = true
		candidate.upkeep.mode_stop_pending = true
		_travel_party_runtime = candidate
		_travel_party_runtime_token = str(status.token)
		var checkpoint := checkpoint_region_travel()
		return {"ok": true, "pending": true, "message": "沿原未完航段完成到安全停靠點後，进入原地點上下船。"} if checkpoint.ok else checkpoint
	var step := {}
	if status.get("plan", {}).get("steps") is Array and not status.plan.steps.is_empty(): step = status.plan.steps[int(status.step_index)]
	var entry := RegionRoute.entry_cell(step) if not step.is_empty() and int(step.get("edge", -1)) >= 0 else Vector2i(50, 50)
	if step.is_empty() or int(step.get("edge", -1)) < 0:
		var body: Dictionary = RegionTravel._body_records(candidate.content).get(int(candidate.leader_person_id), {})
		if body.get("cell") is Array: entry = Vector2i(int(body.cell[0]), int(body.cell[1]))
	var poses: Dictionary = status.get("vehicle_poses", step.get("vehicle_poses", {}))
	var destination := _ship_destination(status.site, float(control.logical_game_seconds))
	if not destination.ok: return destination
	var generation := int(_marker.get("generation", 0)) + 1
	var nav := Env.navigation_for_state(destination.data, destination.data.site)
	var admitted := RegionTravel.insert(destination.data.site, candidate, nav, entry, _generation_path(generation, status.site),
		float(status.departure_game_seconds), float(control.logical_game_seconds),
		{"generation": generation, "family_transfer_guard": region_family_transfer_guard, "vehicle_poses": poses})
	if not admitted.ok: return admitted
	candidate.upkeep.mode_stop_pending = false
	candidate.upkeep.materialize_current = true
	candidate.upkeep.mode_stop_site = [status.site.x, status.site.y]
	candidate.upkeep.mode_stop_entry = [entry.x, entry.y]
	candidate.upkeep.mode_stop_vehicle_poses = poses.duplicate(true)
	_travel_party_runtime = candidate
	_travel_party_runtime_token = str(status.token)
	var checkpoint := checkpoint_region_travel()
	return {"ok": true, "ready": true, "site": status.site} if checkpoint.ok else checkpoint


func region_mode_stop_status(party: Dictionary, base: Dictionary) -> Dictionary:
	if not bool(party.get("upkeep", {}).get("materialize_current", false)): return base
	var upkeep: Dictionary = party.upkeep
	if not upkeep.get("mode_stop_site") is Array or upkeep.mode_stop_site.size() != 2 \
			or not upkeep.get("mode_stop_entry") is Array or upkeep.mode_stop_entry.size() != 2:
		return fail("CORRUPT_SAVE", "原停靠／模式入場 proof 非法")
	base.site = Vector2i(int(upkeep.mode_stop_site[0]), int(upkeep.mode_stop_site[1]))
	base.destination = base.site
	base.arrived = true
	base.moving = false
	base.mode_materialize = true
	base.arrival_entry = Vector2i(int(upkeep.mode_stop_entry[0]), int(upkeep.mode_stop_entry[1]))
	base.arrival_vehicle_poses = upkeep.get("mode_stop_vehicle_poses", {}).duplicate(true)
	return base

# region_travel_status's FINAL return must call region_mode_stop_status(party,base).
# commit_region_arrival uses status.arrival_entry / arrival_vehicle_poses when
# mode_materialize is true, including an idle journey with no route plan. The
# original insert/save/readback/preflight/_publish/bind transaction remains the
# ONLY entry. After bind the existing Vehicles UI provides real embark/disembark
# duration and shore space; next departure detects original embarked state.


var region_original_party_endpoint: Callable

var region_original_player_materialize: Callable

var region_original_endpoint_checkpoint: Callable

func _region_committed_unbound(message: String, details: Dictionary) -> Dictionary:
	var result := fail("COMMITTED_UNBOUND", message)
	result.merge(details)
	return result


func _region_arrival_location(status: Dictionary, party: Dictionary) -> Dictionary:
	if bool(status.get("mode_materialize", false)):
		return {"ok": true, "entry": status.arrival_entry, "vehicle_poses": status.get("arrival_vehicle_poses", {})}
	var steps: Array = status.get("plan", {}).get("steps", [])
	var index := int(status.get("step_index", 0)) if bool(status.get("barrier", false)) else steps.size() - 1
	if index >= 0 and index < steps.size():
		var step: Dictionary = steps[index]
		var entry := RegionRoute.entry_cell(step)
		if entry.x >= 0: return {"ok": true, "entry": entry, "vehicle_poses": status.get("vehicle_poses", step.get("vehicle_poses", {}))}
	# A life endpoint in the still-current original origin has no incoming seam.
	# Use its actual original leader position, never a fabricated centre cell.
	var here := Grid.site_id(str(pin.atlas_id), status.site)
	if here != str(party.get("origin_site_id", "")):
		return fail("MISSING_ENTRY_PROOF", "原旅隊此處入界須真 waypoint／停靠 proof")
	var body: Dictionary = RegionTravel._body_records(party.content).get(int(party.leader_person_id), {})
	if not body.get("cell") is Array or body.cell.size() != 2: return fail("MISSING_ENTRY_PROOF", "原領隊 cell 不存在")
	return {"ok": true, "entry": Vector2i(int(body.cell[0]), int(body.cell[1])), "vehicle_poses": status.get("vehicle_poses", {})}


func _region_arrival_queue_mapping(clock: Dictionary, token: String, mapping: Dictionary, destination_site: String) -> Dictionary:
	if not clock.get("region_gameplay") is Dictionary: return {"ok": true}
	var identities: Dictionary = mapping.get("maps", {}).get("person", {})
	for event: Dictionary in clock.region_gameplay.get("events", []):
		if str(event.get("owner", "")) != "travel:" + token or str(event.get("status", "")) == "complete": continue
		var payload: Dictionary = event.get("payload", {})
		if str(event.kind) not in ["life", "player_death"]: continue
		var original := str(int(payload.get("person_id", -1)))
		if not identities.has(original): return fail("INVALID_LIFE_MAPPING", "原玩家端點不屬此次真移交")
		payload.person_id = int(identities[original])
		# Event ID/sequence/owner remain immutable dedup/history. Location is an
		# original reference to the new single Site body, not a second body copy.
		payload.destination_site = destination_site
		payload.arrival_mapping = mapping.duplicate(true)
	return {"ok": true}

# REPLACE the original method, preserving root's exact cold settle/bind flow.


func consume_region_party_endpoint(event: Dictionary) -> Dictionary:
	var wire_payload: Dictionary = event.get("payload", {})
	var payload: Dictionary = wire_payload.get("event", wire_payload)
	var owner := str(event.get("owner", ""))
	if not owner.begins_with("travel:") or absf(float(event.get("at", -1.0)) - float(control.logical_game_seconds)) > 0.00000001:
		return fail("STALE_REGION_EVENT", "不是此刻原旅隊生命端點")
	var token := owner.trim_prefix("travel:")
	var player: bool = region_travel_journey().get("token") == token
	var loaded := region_travel_party() if player else _region_npc_party(token)
	if not loaded.ok: return loaded
	var party: Dictionary = loaded.party
	var original: Dictionary = {}
	for accepted: Dictionary in party.get("upkeep", {}).get("events", []):
		if int(accepted.get("sequence", -1)) == int(payload.get("sequence", -2)): original = accepted
	if original.is_empty() or str(original.get("kind", "")) != str(payload.get("kind", "")) \
			or int(original.get("person_id", -1)) != int(payload.get("person_id", -2)) \
			or float(original.get("at", -1.0)) != float(event.at):
		return fail("STALE_REGION_LIFE_OWNER", "佇列與原供養／KO接受端點不同")
	if not region_original_party_endpoint.is_valid(): return fail("MISSING_REGION_ADAPTER", "缺原旅隊 contact／wake／death／capture 出口")
	var consumed: Variant = region_original_party_endpoint.call(token, party, event)
	if not consumed is Dictionary or not consumed.get("ok", false):
		return consumed if consumed is Dictionary else fail("INVALID_REGION_RECEIPT")
	var after: Variant = consumed.get("party")
	var receipt: Variant = consumed.get("receipt")
	if not after is Dictionary or after.get("party_id") != token or not RegionTravel.validate_identity(after.get("content", {}).get("travel_identity")) \
			or absf(float(after.get("upkeep", {}).get("at", -1.0)) - float(control.logical_game_seconds)) > 0.00000001 \
			or not receipt is Dictionary or receipt.get("token") != token or not bool(receipt.get("effects_complete", false)) \
			or absf(float(receipt.get("game_seconds", -1.0)) - float(control.logical_game_seconds)) > 0.00000001 \
			or absf(float(receipt.get("action_seconds", -1.0)) - float(control.fire_clock.action_seconds)) > 0.00000001:
		return fail("INVALID_REGION_RECEIPT", "原旅隊效果／捕獲不是同一完成 epoch")
	if player:
		_travel_party_runtime = after
		_travel_party_runtime_token = token
	else:
		_region_npc_party_runtime[token] = after
	# Save the actual outcome before clearing the immutable event. Root's
	# checkpoint includes all other original parties/sites on this same marker.
	if not player and not region_original_endpoint_checkpoint.is_valid(): return fail("MISSING_REGION_ADAPTER", "缺含原活動 Lab 的共同端點 checkpoint")
	var checkpoint: Dictionary = checkpoint_region_travel() if player else region_original_endpoint_checkpoint.call()
	if not checkpoint.ok: return checkpoint
	if bool(original.get("controlled", false)) and bool(original.get("death", false)) and not bool(receipt.get("continuity_complete", false)):
		return fail("PLAYER_CONTINUITY_PENDING", "原死亡已保存；須完成原家族接續／選擇或失敗入口")
	if not bool(receipt.get("complete", false)): return fail("REGION_EFFECTS_PENDING", "原旅隊同刻出口仍未完成")
	var completed := complete_region_event(str(event.id))
	if not completed.ok: return completed
	return {"ok": true, "receipt": receipt}


func consume_region_player_event(event: Dictionary) -> Dictionary:
	var at := float(event.get("at", -1.0))
	var world := float(control.logical_game_seconds)
	if at < 0.0 or at > world + 0.00000001: return fail("STALE_REGION_EVENT")
	# A held original controlled-death event keeps its accepted immutable time
	# while the bound body's paid down interval completes at later world points.
	if at < world - 0.00000001 and not _region_mapped_player_death(event):
		return fail("STALE_REGION_EVENT")
	if str(event.get("kind", "")) not in ["player_death", "life", "player_arrival", "player_encounter"]:
		return fail("INVALID_REGION_EVENT")
	if not region_original_player_materialize.is_valid(): return fail("MISSING_REGION_ADAPTER", "缺真joint livebind及原身體／Family消費者")
	var consumed: Variant = region_original_player_materialize.call(event)
	if not consumed is Dictionary or not consumed.get("ok", false): return consumed if consumed is Dictionary else fail("INVALID_REGION_RECEIPT")
	if not consumed.get("receipt") is Dictionary or not bool(consumed.receipt.get("effects_complete", false)):
		return fail("INVALID_REGION_RECEIPT", "P0原身體效果未完成")
	return consumed

var region_contact_active_data: Callable

func _region_contact_navigation(site: Vector2i, context: Dictionary, mode: String, cache: Dictionary) -> Dictionary:
	var key := "%d:%d:%s" % [site.x, site.y, mode]
	if cache.has(key): return cache[key]
	var effective := RegionRoute.effective_terrain(source, site, context)
	if not effective.ok: return effective
	var data: TerrainData = effective.data
	var projected: Dictionary
	if mode == "land":
		projected = RegionRoute.table_from_terrain(data, RegionRoute._cover(source, site), true)
	else:
		# Same original ocean/water-step guards as the full-hull route proof.
		# These labels never alias the ground layer's component numbers.
		var labels := PackedInt32Array()
		labels.resize(10000)
		labels.fill(-1)
		var label := 10000
		for index: int in range(10000):
			if labels[index] >= 0: continue
			var cell := Vector2i(index % 100, index / 100)
			if not RegionRoute._ocean({"data": data, "cell": cell}): continue
			var pending: Array[Vector2i] = [cell]
			labels[index] = label
			var cursor := 0
			while cursor < pending.size():
				var current: Vector2i = pending[cursor]
				cursor += 1
				for direction: Vector2i in TerrainData.DIRECTIONS:
					var next := current + direction
					if next.x < 0 or next.y < 0 or next.x >= 100 or next.y >= 100: continue
					var next_index := next.y * 100 + next.x
					if labels[next_index] >= 0 or not RegionRoute._ocean({"data": data, "cell": next}) \
							or not data.can_water_step(current, next): continue
					labels[next_index] = label
					pending.append(next)
			label += 1
		projected = {"ok": true, "labels": labels, "ids": {}}
	if not projected.ok: return projected
	projected.data = data
	cache[key] = projected
	return projected


func _region_contact_position(party: Dictionary, plan: Dictionary, route_position: Dictionary,
		context: Dictionary, cache: Dictionary) -> Dictionary:
	var site := Vector2i(int(route_position.site[0]), int(route_position.site[1]))
	var mode := str(party.get("mode", "land"))
	var nav := _region_contact_navigation(site, context, mode, cache)
	if not nav.ok: return nav
	var index := int(route_position.get("step_index", 0))
	var step: Dictionary = plan.get("steps", [])[index] if index < plan.get("steps", []).size() else {}
	var cell := RegionRoute.entry_cell(step)
	if mode == "sea":
		var poses: Dictionary = step.get("vehicle_poses", party.upkeep.get("mode_stop_vehicle_poses", {}))
		if not poses.is_empty():
			var keys: Array = poses.keys()
			keys.sort()
			var anchor: Variant = poses[keys[0]].get("anchor")
			if anchor is Array and anchor.size() == 2: cell = Vector2i(int(anchor[0]), int(anchor[1]))
	if cell.x < 0 and Grid.site_id(str(pin.atlas_id), site) == str(party.get("origin_site_id", "")):
		var body: Dictionary = RegionTravel._body_records(party.content).get(int(party.leader_person_id), {})
		if body.get("cell") is Array and body.cell.size() == 2: cell = Vector2i(int(body.cell[0]), int(body.cell[1]))
	var label := -1
	if cell.x >= 0 and cell.x < 100 and cell.y >= 0 and cell.y < 100:
		label = int(nav.labels[cell.y * 100 + cell.x])
	elif mode == "land":
		# An idle/rerouted foot party's existing Slot node is a navigation
		# reference, not a copied body position. Reuse only a still-valid current
		# original component; never select the nearest disconnected component.
		for raw: Variant in nav.ids:
			if int(nav.ids[raw]) == int(route_position.get("component", -1)):
				label = int(raw)
				break
	if label < 0: return fail("STALE_ROUTE", "原接觸位置已無合法導航 component")
	var result: Dictionary = route_position.duplicate(true)
	result.component = label
	result.route_component = int(route_position.get("component", -1))
	result.mode = mode
	result.cell = [cell.x, cell.y]
	return {"ok": true, "position": result}


func _region_contact_land_points(party: Dictionary, plan: Dictionary, to: float, moving: bool,
		idle: Dictionary, context: Dictionary, cache: Dictionary) -> Dictionary:
	var begin := float(control.logical_game_seconds)
	if absf(float(party.get("upkeep", {}).get("at", -1.0)) - begin) > 0.00000001:
		return fail("UNSETTLED_PARTY", "接觸預檢不是共同完成端點")
	if plan.is_empty():
		var located := _region_contact_position(party, {}, idle, context, cache)
		if not located.ok: return located
		return {"ok": true, "points": [{"at": begin, "position": located.position}], "until": to}
	var breaks := _region_route_breaks(party, plan, to, moving)
	if not breaks.ok: return breaks
	var times: Array = breaks.times.duplicate()
	times.sort()
	var points: Array = []
	var previous_index := -1
	for raw: Variant in times:
		var at := float(raw)
		if not points.is_empty() and float(points.back().at) == at: continue
		var original := _region_route_position_at(party, plan, at, moving)
		if not original.ok: return original
		if absf(float(original.at) - at) > 0.00000001: break
		var located := _region_contact_position(party, plan, original.position, context, cache)
		if not located.ok: return located
		var point := {"at": at, "position": located.position}
		var index := int(original.position.step_index)
		if previous_index >= 0 and index != previous_index:
			if index != previous_index + 1: return fail("CONTACT_INTERVAL", "原路段界限預檢漏了中間 Site")
			point.seam = {"edge": RegionRoute.opposite(int(plan.steps[index].edge)), "offset": int(plan.steps[index].offset)}
		points.append(point)
		previous_index = index
	return {"ok": true, "points": points, "until": float(breaks.until)}


func _region_contact_sea_points(party: Dictionary, plan: Dictionary, to: float,
		context: Dictionary, cache: Dictionary, interval: Dictionary) -> Dictionary:
	for field: String in ["game_begin", "game_end", "action_begin", "action_end", "scale", "tactical_seconds"]:
		if not interval.has(field) or not GameplayClock.seconds(interval[field]): return fail("MISSING_REGION_INTERVAL")
	if to > float(interval.game_end) + 0.00000001: return fail("CONTACT_INTERVAL")
	var candidate := party.duplicate(true)
	var now := float(control.logical_game_seconds)
	var action_at := float(control.fire_clock.action_seconds)
	var points: Array = []
	var prior_leg := -1
	for _guard: int in range(100000):
		var cursor: Dictionary = candidate.upkeep.get("sea_cursor", {})
		var index := int(cursor.get("action_index", -1))
		if index < 0 or index > plan.get("action_steps", []).size(): return fail("CORRUPT_SAVE", "海上接觸缺原 ACTION cursor")
		var complete: bool = index == plan.action_steps.size()
		var leg: int = plan.steps.size() - 1 if complete else int(plan.action_steps[index].leg_index)
		var position := {"site": plan.steps[leg].site.duplicate(), "component": 0, "step_index": leg, "fraction": 0.0}
		var located := _region_contact_position(candidate, plan, position, context, cache)
		if not located.ok: return located
		if points.is_empty() or leg != prior_leg:
			var point := {"at": now, "position": located.position}
			if prior_leg >= 0: point.seam = {"edge": RegionRoute.opposite(int(plan.steps[leg].edge)), "offset": int(plan.steps[leg].offset)}
			points.append(point)
			prior_leg = leg
		if complete or now >= to - 0.00000001: return {"ok": true, "points": points, "until": now if now < to else to}
		var action: Dictionary = plan.action_steps[index]
		var transport := RegionTravel.prepare_transport(candidate.duplicate(true))
		if not transport.ok: return transport
		var moving := bool(transport.can_move) and not bool(candidate.upkeep.resting)
		var duration := float(cursor.get("duration", 0.0))
		if moving and duration <= 0.0:
			var measured := _region_sea_action_duration(candidate, action)
			if not measured.ok: return measured
			duration = float(measured.duration)
		var options := {"moving": moving, "safe_rest": true, "distance_mode": "sea_action", "active_ship_ids": [str(action.vehicle_id)]}
		var endpoint := RegionTravel.next_upkeep_event(candidate, options.merged({"until": to}, true))
		if not endpoint.ok: return endpoint
		var end := float(endpoint.at)
		var tactical := maxf(0.0, float(interval.tactical_seconds) - (action_at - float(interval.action_begin)))
		var elapsed := GameplayClock.action_for_game(end - now, float(interval.scale), tactical)
		elapsed = minf(elapsed, float(interval.action_end) - action_at)
		if moving:
			elapsed = minf(elapsed, duration - float(cursor.get("elapsed", 0.0)))
			end = now + Runtime.game_seconds(elapsed, minf(tactical, elapsed)) * float(interval.scale)
		if end <= now + 0.0000000001: return {"ok": true, "points": points, "until": now}
		var advanced := RegionTravel.advance_upkeep(candidate, end, options)
		if not advanced.ok: return advanced
		if absf(float(advanced.at) - end) > 0.00000001:
			return {"ok": true, "points": points, "until": float(advanced.at)}
		candidate = advanced.party
		cursor = candidate.upkeep.sea_cursor
		if moving:
			cursor.duration = duration
			cursor.elapsed = minf(duration, float(cursor.elapsed) + elapsed)
			if float(cursor.elapsed) >= duration - 0.0000001:
				cursor.action_index = index + 1
				cursor.elapsed = 0.0
				cursor.duration = 0.0
		now = end
		action_at += elapsed
		if not advanced.events.is_empty(): return {"ok": true, "points": points, "until": now}
	return fail("CONTACT_BUDGET", "原海路接觸預檢超過 ACTION 界限")


var region_original_travel_interval: Callable

var region_original_party_progress: Callable

func _region_player_land_candidate(party: Dictionary, status: Dictionary, interval: Dictionary) -> Dictionary:
	var world := float(interval.game_begin)
	if absf(float(party.upkeep.at) - world) > 0.00000001: return fail("UNSETTLED_PARTY")
	var options := {"moving": true, "safe_rest": true}
	var endpoint := RegionTravel.next_upkeep_event(party, options.merged({"until": float(interval.game_end)}, true))
	if not endpoint.ok: return endpoint
	var end := minf(float(interval.game_end), float(endpoint.at))
	var outcome := RegionTravel.advance_upkeep(party, end, options)
	if not outcome.ok: return outcome
	if float(outcome.metres) > float(status.remaining_metres) + 0.0000001:
		var low := world
		var high := float(outcome.at)
		for _iteration: int in range(45):
			var middle := (low + high) * 0.5
			var probe := RegionTravel.advance_upkeep(party, middle, options)
			if not probe.ok: return probe
			if float(probe.metres) < float(status.remaining_metres): low = middle
			else: high = middle
		outcome = RegionTravel.advance_upkeep(party, high, options)
		if not outcome.ok: return outcome
	var candidate: Dictionary = outcome.party
	if str(candidate.upkeep.get("plan_id", "")) != str(status.journey.plan_path):
		candidate.upkeep.plan_id = str(status.journey.plan_path)
		candidate.upkeep.distance = 0.0
	candidate.upkeep.distance = minf(float(status.plan.metres), float(candidate.upkeep.distance) + float(outcome.metres))
	candidate.upkeep.blocked_reason = str(outcome.get("reason", ""))
	outcome.action_seconds = GameplayClock.action_for_game(float(outcome.at) - world,
		float(interval.scale), float(interval.tactical_seconds))
	outcome.arrived = float(candidate.upkeep.distance) >= float(status.plan.metres) - 0.0000001
	return outcome


func _region_queue_player_travel_outcome(token: String, outcome: Dictionary, interval: Dictionary) -> Dictionary:
	for event: Dictionary in outcome.get("events", []):
		var identity := "travel:%s:life:%d" % [token, int(event.sequence)]
		var queued := queue_region_event(identity,
			"player_death" if bool(event.get("controlled", false)) and bool(event.get("death", false)) else "life",
			float(interval.game_end), "travel:" + token, event, true)
		if not queued.ok: return queued
	if bool(outcome.get("arrived", false)):
		var status := region_travel_status()
		if not status.ok: return status
		var to: Vector2i = status.destination
		var queued := queue_region_event("travel:%s:arrival:%s" % [token, str(status.journey.plan_path)], "player_arrival",
			float(interval.game_end), Grid.site_id(str(pin.atlas_id), to),
			{"player_token": token, "site": [to.x, to.y], "component": int(status.component)}, true)
		if not queued.ok: return queued
	return {"ok": true}


func _region_accept_player_travel_interval(token: String, accepted: Dictionary) -> Dictionary:
	if not accepted.get("ok", false): return accepted
	if accepted.get("pending", false): return accepted
	if not accepted.get("interval") is Dictionary or not accepted.get("outcome") is Dictionary \
			or not bool(accepted.get("complete", false)): return fail("INCOMPLETE_REGION_PROGRESS")
	var interval: Dictionary = accepted.interval
	var outcome: Dictionary = accepted.outcome
	if not outcome.get("party") is Dictionary or str(outcome.party.party_id) != token \
			or absf(float(outcome.party.upkeep.at) - float(interval.game_end)) > 0.00000001 \
			or absf(float(control.logical_game_seconds) - float(interval.game_end)) > 0.00000001 \
			or absf(float(control.fire_clock.action_seconds) - float(interval.action_end)) > 0.00000001:
		return fail("CLOCK_CONTRACT", "所有真原owner與原旅隊須完成同一世界截段")
	_travel_party_runtime = outcome.party
	_travel_party_runtime_token = token
	var queued := _region_queue_player_travel_outcome(token, outcome, interval)
	if not queued.ok: return queued
	var consumed := consume_due_region_events()
	if not consumed.ok: return consumed
	if not consumed.get("complete", false): accepted.pending = true
	return accepted

# REPLACE original advance_region_travel. No clock assignment or journal append
# is permitted here; the original common Lab host performs it exactly once.


func _region_npc_dispatch_mode(state: Dictionary, team_id: int) -> Dictionary:
	var boats := {}
	var selected: Dictionary = {}
	for team: Dictionary in state.get("armies", []):
		if int(team.team_id) == team_id: selected = team
	if selected.is_empty(): return fail("NO_TARGET")
	for body: Dictionary in selected.units:
		var boat := str(body.get("embarked_vehicle_id", ""))
		if not boat.is_empty(): boats[boat] = true
	if boats.is_empty(): return {"ok": true, "spec": {"mode": "land"}}
	var teams: Array[int] = []
	var people := RegionTravel._body_records(state)
	for team: Dictionary in state.armies:
		var aboard := false
		var complete := true
		for body: Dictionary in team.units:
			var vessel := str(body.get("embarked_vehicle_id", ""))
			aboard = aboard or boats.has(vessel)
			complete = complete and boats.has(vessel)
		if aboard:
			if not complete or not team.get("player_member", {}).is_empty(): return fail("RELATION_OPEN", "原船乘員須保持完整同隊閉包")
			teams.append(int(team.team_id))
	for vessel: String in boats:
		var original: Dictionary = state.get("vehicles", {}).get(vessel, {})
		if str(original.get("kind", "")) != "ship" or not RegionTravel.Ship.is_kind(str(original.get("ship_type", ""))): return fail("INVALID_SHIP_CLOSURE")
		for person: int in people:
			if str(people[person].get("embarked_vehicle_id", "")) != vessel: continue
			var owned := false
			for team: Dictionary in state.armies:
				if int(team.team_id) not in teams: continue
				for body: Dictionary in team.units:
					if int(body.person_id) == person: owned = true
			if not owned: return fail("RELATION_OPEN", "原船另有未選定原Actor／隊外乘員")
	var boat_ids: Array[String] = []
	for vessel: String in boats: boat_ids.append(vessel)
	boat_ids.sort()
	teams.sort()
	return {"ok": true, "spec": {"mode": "sea", "boat_ids": boat_ids, "team_ids": teams}}


func _region_npc_route_plan(token: String, steps: Array, party: Dictionary) -> Dictionary:
	var plan := {"version": 1, "token": token, "steps": steps.duplicate(true), "metres": 0.0,
		"destination": steps.back().site.duplicate()}
	for step: Dictionary in steps: plan.metres = float(plan.metres) + float(step.metres)
	if str(party.get("mode", "land")) == "land": return {"ok": true, "plan": plan}
	var timeline := _region_sea_timeline(steps, party)
	if not timeline.ok: return timeline
	plan.version = 2
	plan.mode = "sea"
	plan.action_steps = timeline.actions
	plan.action_seconds = float(timeline.action_seconds)
	plan.metres = float(timeline.metres)
	party.upkeep.distance = 0.0
	party.upkeep.sea_cursor = {"version": 1, "plan_id": "", "action_index": 0,
		"elapsed": 0.0, "duration": 0.0, "completed_metres": 0.0}
	return {"ok": true, "plan": plan}

# Dispatch commit knows the actual persisted plan_path. Set BOTH original
# upkeep.plan_id and sea_cursor.plan_id to that path before writing party_path.


func _region_npc_sea_position(plan: Dictionary, party: Dictionary) -> Dictionary:
	var index := int(party.upkeep.sea_cursor.action_index)
	var leg: int = plan.steps.size() - 1 if index == plan.action_steps.size() else int(plan.action_steps[index].leg_index)
	return {"site": plan.steps[leg].site.duplicate(), "component": 0, "step_index": leg, "fraction": 0.0}


func _preview_npc_sea_party_to(token: String, party: Dictionary, plan: Dictionary, end: float, interval: Dictionary) -> Dictionary:
	for field: String in ["game_begin", "game_end", "action_begin", "action_end", "scale", "tactical_seconds"]:
		if not interval.has(field) or not GameplayClock.seconds(interval[field]): return fail("MISSING_REGION_INTERVAL", "原NPC船需真ACTION／tactical／scale")
	var world := float(control.logical_game_seconds)
	if absf(float(interval.game_begin) - world) > 0.00000001 or absf(float(interval.action_begin) - float(control.fire_clock.action_seconds)) > 0.00000001:
		return fail("CLOCK_CONTRACT")
	var cursor: Dictionary = party.upkeep.get("sea_cursor", {})
	var index := int(cursor.get("action_index", -1))
	if index < 0 or index > plan.get("action_steps", []).size(): return fail("CORRUPT_SEA_CURSOR")
	if index == plan.action_steps.size(): return {"ok": true, "at": world, "party": party.duplicate(true), "events": [],
		"position": _region_npc_sea_position(plan, party), "arrived": true}
	var action: Dictionary = plan.action_steps[index]
	var transport := RegionTravel.prepare_transport(party.duplicate(true))
	if not transport.ok: return transport
	var moving := bool(transport.can_move) and not bool(party.upkeep.resting)
	var duration := float(cursor.get("duration", 0.0))
	if duration <= 0.0 and moving:
		var measured := _region_sea_action_duration(party, action)
		if not measured.ok: return measured
		duration = float(measured.duration)
	var game_end := minf(end, float(interval.game_end))
	var budget := GameplayClock.action_for_game(game_end - world, float(interval.scale), float(interval.tactical_seconds))
	if moving: budget = minf(budget, duration - float(cursor.elapsed))
	var accepted := interval.duplicate(true)
	accepted.action_end = float(interval.action_begin) + budget
	accepted.tactical_seconds = minf(budget, float(interval.tactical_seconds))
	accepted.game_end = world + Runtime.game_seconds(budget, float(accepted.tactical_seconds)) * float(interval.scale)
	var outcome := _region_player_sea_candidate(party, plan, action, duration, moving, accepted)
	if not outcome.ok: return outcome
	outcome.position = _region_npc_sea_position(plan, outcome.party)
	outcome.party.upkeep.plan_id = str(region_registry().parties[token].plan_path)
	outcome.party.upkeep.sea_cursor.plan_id = str(region_registry().parties[token].plan_path)
	return outcome

# REQUIRED original _preview_npc_party_to signature gains interval:Dictionary={}
# immediately after load/validate-watermark, before the land advance:
# if plan.mode == 'sea': return _preview_npc_sea_party_to(token,party,plan,end,interval)
# queue_region_gameplay_endpoints gains interval:Dictionary={} and forwards it.
# prepare_region_gameplay_interval forwards its exact interval to every preview.


const InitialArtisans = preload("res://scripts/terrain_lab/site_technology_artisans.gd")

var _initialization: Dictionary = {}

var _initial_candidate: Dictionary = {}

static func _initial_context_ok(context: Variant) -> bool:
	return context is Dictionary and context.size() == 2 and context.get("starting_site") is Array and context.starting_site.size() == 2 and _whole(context.starting_site[0], -10000000, 10000000) and _whole(context.starting_site[1], -10000000, 10000000) and context.get("initial_scenario_id") is String and str(context.initial_scenario_id) in ["", InitialArtisans.PRIMARY, InitialArtisans.THREE_FACTIONS]


func _initial_pending_ok(record: Variant, expected: Dictionary) -> bool:
	return record is Dictionary and record.size() == 4 and _whole(record.get("version"), 1, 1) and _same_pin(record.get("pin"), expected) and _initial_context_ok({"starting_site": record.get("starting_site"), "initial_scenario_id": record.get("initial_scenario_id")})


func _initial_complete_ok(record: Variant) -> bool:
	return record is Dictionary and record.size() == 5 and _whole(record.get("version"), 1, 1) and _whole(record.get("first_generation"), 1, 1) and _same_pin(record.get("pin"), pin) and record.get("starting_site") == _initialization.get("starting_site") and record.get("initial_scenario_id") == _initialization.get("initial_scenario_id")


func initialization_pending() -> bool:
	return not _initialization.is_empty()


func _derive_initial_context() -> Dictionary:
	if int(_marker.get("generation", 0)) != 1 or _marker.get("sites", {}).size() != 1: return fail("INVALID_SLOT")
	var key: String = _marker.sites.keys()[0]
	var parts := key.split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int(): return fail("INVALID_SLOT")
	var coordinate := Vector2i(int(parts[0]), int(parts[1]))
	var entry: Dictionary = _marker.sites[key]
	var loaded := _load_checked(folder.path_join(str(entry.path)), coordinate)
	if not loaded.ok: return loaded
	var selected := str(loaded.data.site.get("initial_scenario", {}).get("scenario_id", ""))
	var context := {"version": 1, "pin": pin.duplicate(true), "starting_site": [coordinate.x, coordinate.y], "initial_scenario_id": selected}
	if not _initial_pending_ok(context, pin): return fail("INVALID_INITIAL_SCENARIO")
	_initialization = context
	var checked := _check_initial_record(_marker)
	if not checked.ok: _initialization = {}; return checked
	return {"ok": true, "context": context}


func _check_initial_record(record: Dictionary) -> Dictionary:
	if not _initial_pending_ok(_initialization, pin) or int(record.get("generation", 0)) != 1 or not _same_pin(record.get("pin"), pin) or record.get("sites", {}).size() != 1 or not str(record.get("transfer_token", "")).is_empty() or not record.get("journey", {}).is_empty(): return fail("INVALID_INITIAL_GENERATION")
	var policy := TechnologyPolicy.candidate(pin)
	if not policy.ok or not policy.policy.categories.is_empty(): return fail("TECH_POLICY_CONFLICT")
	var coordinate := Vector2i(int(_initialization.starting_site[0]), int(_initialization.starting_site[1]))
	var key := _site_key(coordinate)
	if not record.sites.has(key) or str(record.get("control", {}).get("active_site_id", "")) != Grid.site_id(str(pin.atlas_id), coordinate) or float(record.control.get("logical_game_seconds", -1.0)) != 0.0: return fail("INVALID_INITIAL_GENERATION")
	var entry: Dictionary = record.sites[key]
	var path := folder.path_join(str(entry.get("path", "")))
	if not str(entry.get("path", "")).begins_with("generations/") or FileAccess.get_sha256(path) != str(entry.get("sha256", "")): return fail("INVALID_INITIAL_GENERATION")
	var loaded := _load_checked(path, coordinate)
	if not loaded.ok: return loaded
	var state: Dictionary = loaded.data.site
	var scenario := str(_initialization.initial_scenario_id)
	if int(state.get("minute", -1)) != 0 or float(state.get("phase", -1.0)) != 0.0 or int(state.get("controlled_person_id", -1)) != 1 or int(state.get("actors", {}).get("player", {}).get("person_id", -1)) != 1 or state.get("actors", {}).size() != 1 or state.has("family") or state.has("crowd"): return fail("INVALID_INITIAL_POPULATION")
	if scenario.is_empty():
		if state.has("initial_scenario") or not state.get("armies", []).is_empty() or state.has("technology_artisans"): return fail("INVALID_INITIAL_POPULATION")
	else:
		if state.get("initial_scenario", {}) != {"version": 1, "scenario_id": scenario, "world_id": str(pin.world_instance_id)}: return fail("INVALID_INITIAL_SCENARIO")
		var teams := 1 if scenario == InitialArtisans.PRIMARY else 3
		if state.get("armies", []).size() != teams: return fail("INVALID_INITIAL_POPULATION")
		for roster: Dictionary in state.armies:
			if roster.get("units", []).size() != 5: return fail("INVALID_INITIAL_POPULATION")
	var settled := validate_settlement(state, 0.0)
	if not settled.ok or settled.legacy or float(settled.pending) != 0.0: return fail("INVALID_INITIAL_GENERATION")
	var fire := validate_fire_settlement(state, record.control.get("fire_clock", {}))
	if not fire.ok or int(record.control.fire_clock.sequence) != 0 or float(record.control.fire_clock.action_seconds) != 0.0: return fail("INVALID_INITIAL_GENERATION")
	return {"ok": true, "data": loaded.data, "coordinate": coordinate, "path": path}


func _finish_initial_manifest() -> Dictionary:
	var checked := _check_initial_record(_marker)
	if not checked.ok: return checked
	var path := folder.path_join("manifest.json")
	if FileAccess.file_exists(path):
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		return {"ok": true, "generation": 1} if _same_pin(raw, pin) else fail("INITIAL_PIN_CONFLICT")
	var absolute := ProjectSettings.globalize_path(path)
	var temporary := absolute + ".tmp"
	var body := JSON.stringify(pin, "\t")
	var output := FileAccess.open(temporary, FileAccess.WRITE)
	if output == null: return fail("SAVE_IO", "原首代已提交，manifest 待同槽恢復")
	output.store_string(body)
	output.flush()
	var error := output.get_error()
	output.close()
	if error != OK or FileAccess.get_file_as_string(temporary) != body or DirAccess.rename_absolute(temporary, absolute) != OK: return fail("SAVE_IO", "原首代已提交，manifest 尚未完成")
	return {"ok": true, "generation": 1}


func initial_site_candidate() -> Dictionary:
	if not initialization_pending(): return fail("NO_TARGET")
	if not _marker.is_empty(): return _check_initial_record(_marker)
	if not _initial_candidate.is_empty():
		if FileAccess.get_sha256(str(_initial_candidate.path)) != str(_initial_candidate.sha256): return fail("STALE_INITIAL_CANDIDATE")
		return {"ok": true, "data": _initial_candidate.data, "coordinate": _initial_candidate.coordinate, "prepared": true}
	return {"ok": true, "prepared": false}


func prepare_initial_site(data: TerrainData) -> Dictionary:
	if not initialization_pending() or not _marker.is_empty() or not _initial_candidate.is_empty(): return fail("INITIAL_ALREADY_PREPARED")
	var coordinate := _coordinate(data)
	if not coordinate.ok: return coordinate
	if [coordinate.site.x, coordinate.site.y] != _initialization.starting_site or str(data.site.get("world_pin", {}).get("world_instance_id", "")) != str(pin.world_instance_id): return fail("INITIAL_PIN_CONFLICT")
	var scenario := str(_initialization.initial_scenario_id)
	if not scenario.is_empty(): data.site.initial_scenario = {"version": 1, "scenario_id": scenario, "world_id": str(pin.world_instance_id)}
	elif data.site.has("initial_scenario"): return fail("INVALID_INITIAL_SCENARIO")
	if float(control.logical_game_seconds) != 0.0 or int(control.fire_clock.sequence) != 0 or float(control.fire_clock.action_seconds) != 0.0: return fail("INVALID_INITIAL_GENERATION")
	data.site.fire_settlement = {"version": 1, "epoch": str(control.fire_clock.epoch), "sequence": 0, "action_seconds": 0.0, "game_seconds": 0.0}
	var original_control := control.duplicate(true)
	var attached := attach_active_site(data)
	if not attached.ok:
		control = original_control
		return attached
	var path := _generation_path(1, coordinate.site)
	var saved := _save_checked(data, coordinate.site, path)
	if not saved.ok:
		control = original_control
		return saved
	var entry := _file_entry(path)
	var record := {"format": 1, "generation": 1, "pin": pin.duplicate(true), "sites": {_site_key(coordinate.site): entry},
		"control": control.duplicate(true), "transfer_token": "", "journey": {}}
	var checked := _check_initial_record(record)
	if not checked.ok:
		control = original_control
		return checked
	_initial_candidate = {"data": checked.data, "coordinate": coordinate.site, "path": path, "sha256": str(entry.sha256), "generation": 1}
	return {"ok": true, "data": checked.data, "coordinate": coordinate.site, "prepared": true}


func commit_initial_site() -> Dictionary:
	if not initialization_pending(): return fail("NO_TARGET")
	if not _marker.is_empty():
		var recovered := _check_initial_record(_marker)
		if not recovered.ok: return recovered
		var manifested := _finish_initial_manifest()
		return recovered if manifested.ok else manifested
	if _initial_candidate.is_empty() or FileAccess.get_sha256(str(_initial_candidate.path)) != str(_initial_candidate.sha256): return fail("STALE_INITIAL_CANDIDATE")
	var sites := {_site_key(_initial_candidate.coordinate): _file_entry(str(_initial_candidate.path))}
	var committed := _publish(sites, control)
	if not committed.ok: return committed
	return _check_initial_record(_marker)


func finish_initial_birth(receipt: Dictionary) -> Dictionary:
	if not initialization_pending(): return {"ok": true}
	var checked := _check_initial_record(_marker)
	if not checked.ok: return checked
	if receipt.get("complete") != true or receipt.get("owner") != str(control.active_site_id) or int(receipt.get("generation", -1)) != 1 or receipt.get("mode") != "live" or receipt.get("backend") != "gd": return fail("COMMITTED_UNBOUND")
	var manifested := _finish_initial_manifest()
	if not manifested.ok: return manifested
	var path := folder.path_join("manifest.initialized.json")
	var record := {"version": 1, "pin": pin.duplicate(true), "first_generation": 1,
		"starting_site": _initialization.starting_site.duplicate(), "initial_scenario_id": str(_initialization.initial_scenario_id)}
	if FileAccess.file_exists(path):
		var prior := _read_document(path, 16384)
		if not prior.ok or prior.payload != record: return fail("INVALID_INITIAL_RECEIPT")
	else:
		var completed := _write_new_document(path, record)
		if not completed.ok: return completed
	_initialization = {}
	_initial_candidate = {}
	return {"ok": true, "generation": 1}

# _publish anchor edits, AFTER constructing record and BEFORE _write_new_document:
# if initialization_pending() and expected == 0:
#     var initial_guard := _check_initial_record(record)
#     if not initial_guard.ok: return initial_guard
#
# _publish anchor edits, AFTER _marker = record and control = next_clock:
# if initialization_pending() and generation == 1:
#     var manifested := _finish_initial_manifest()
#     if not manifested.ok:
#         manifested.committed = true
#         manifested.generation = 1
#         return manifested
# Keep its existing sole marker generation/CAS. No second commit writer.


var region_original_party_zero: Callable

## Same original Slot publisher as active Site progress, with no fabricated
## active Site or separate travel clock. Call once after all original stages.
func record_completed_region_travel_step(token: String, prepared: Dictionary, outcome: Dictionary) -> Dictionary:
	if not str(control.active_site_id).is_empty() or token != str(region_travel_journey().get("token", "")) or not prepared.get("ok", false) or not prepared.get("progress_complete", false) or int(prepared.get("generation", -1)) != int(_marker.get("generation", 0)) or int(prepared.get("revision", -1)) != int(region_registry().revision):
		return fail("STALE_REGION_PERMIT")
	var interval: Dictionary = prepared.interval
	if float(control.logical_game_seconds) != float(interval.game_begin) or float(control.fire_clock.action_seconds) != float(interval.action_begin): return fail("CLOCK_CONTRACT")
	# Endpoints already accepted by the original graph can lose low bits when
	# their ACTION difference is reconstructed. Keep its original interval;
	# use the original graph bounds only to validate this round trip.
	var action_delta := float(interval.action_end) - float(interval.action_begin)
	var tactical_seconds := float(interval.tactical_seconds)
	if not _seconds(action_delta) or action_delta <= 0.0 or action_delta > 1.0 / 30.0 + 0.000000001 \
			or not _seconds(tactical_seconds) or tactical_seconds > action_delta + 0.000000000001:
		return fail("CLOCK_CONTRACT")
	var expected := preview_fire_interval(control.fire_clock, float(control.logical_game_seconds), maxf(action_delta, tactical_seconds), float(interval.scale), tactical_seconds)
	if not expected.ok or not _seconds(interval.action_end) or not _seconds(interval.game_end) \
			or float(interval.game_end) <= float(interval.game_begin) \
			or absf(float(expected.action_end) - float(interval.action_end)) > 0.000000000001 \
			or absf(float(expected.game_end) - float(interval.game_end)) > 0.00000001:
		return fail("CLOCK_CONTRACT")
	expected.action_end = interval.action_end
	expected.game_end = interval.game_end
	if expected != interval: return fail("CLOCK_CONTRACT")
	if not outcome.get("party") is Dictionary or str(outcome.party.get("party_id", "")) != token or absf(float(outcome.party.get("upkeep", {}).get("at", -1.0)) - float(interval.game_end)) > 0.00000001:
		return fail("INCOMPLETE_PARTY_PROGRESS")
	if not region_original_travel_interval.is_valid(): return fail("MISSING_TRAVEL_HOST")
	var host: Object = region_original_travel_interval.get_object()
	if not host is TerrainLab or host.site_controller == null or host.site_controller.region_slot != self or not host.restore_only or _region_original_labs.get(str(host.terrain.site.id)) != host:
		return fail("INVALID_TRAVEL_HOST")
	var originals: Dictionary = prepared.get("cold_labs", {}).duplicate()
	for battle: Dictionary in prepared.battles.values(): originals[str(battle.lab.terrain.site.id)] = battle.lab
	if originals.get(str(host.terrain.site.id)) != host: return fail("INVALID_TRAVEL_HOST")
	for owner: String in prepared.permits:
		var checked := GameplayClock.check_permit(region_registry(), prepared.permits[owner], int(_marker.get("generation", 0)), float(interval.game_begin), float(interval.action_begin))
		if not checked.ok: return checked
	for owner: String in originals:
		var original: TerrainLab = originals[owner]
		if not is_instance_valid(original) or _region_original_labs.get(owner) != original: return fail("COMMITTED_UNBOUND")
		var settled := validate_settlement(original.terrain.site, float(interval.game_end))
		var fire: Dictionary = original.terrain.site.get("fire_settlement", {})
		if not settled.ok or settled.legacy or float(settled.pending) > 0.00000001 or fire.get("epoch") != interval.epoch or int(fire.get("sequence", -1)) != int(interval.sequence) or float(fire.get("action_seconds", -1.0)) != float(interval.action_end) or float(fire.get("game_seconds", -1.0)) != float(interval.game_end) or not original._region_point_pending.get("interval_complete", false):
			return fail("INCOMPLETE_REGION_PROGRESS")
	var delta := float(interval.game_end) - float(interval.game_begin)
	var now := advance_world_time(delta)
	if now != float(interval.game_end): return fail("CLOCK_CONTRACT")
	append_completed_fire_interval(control.fire_clock, interval)
	region_registry().revision = int(region_registry().revision) + 1
	_travel_party_runtime = outcome.party
	_travel_party_runtime_token = token
	_prune_recoverable_fire_journal()
	return {"ok": true, "advanced": delta, "at": now}

func _region_joint_npc_reference(clock: Dictionary, token: String, mapping: Dictionary, destination: String) -> Dictionary:
	var registry: Dictionary = clock.region_gameplay
	var reference: Dictionary = registry.parties.get(token, {})
	if str(reference.get("controller", "")) != "npc" or str(reference.get("phase", "")) != "travelling": return fail("STALE_REGION_PARTY")
	reference.phase = "entered"
	reference.destination_site = destination
	reference.arrival_game_seconds = float(clock.logical_game_seconds)
	reference.arrival_mapping = mapping.duplicate(true)
	registry.modes.erase("travel:" + token)
	for queued: Dictionary in registry.events:
		if str(queued.status) != "pending" or str(queued.payload.get("token", "")) != token: continue
		if str(queued.kind) == "life":
			var life: Dictionary = queued.payload.event
			var key := str(int(life.person_id))
			if not mapping.maps.person.has(key): return fail("INVALID_LIFE_MAPPING")
			life.person_id = int(mapping.maps.person[key])
			queued.payload.entered_site = destination
			queued.payload.arrival_mapping = mapping.duplicate(true)
			# Event owner, ID, sequence and accepted time stay immutable.
		elif str(queued.kind) in ["arrival", "reinforcement", "player_arrival", "player_encounter"]:
			queued.payload.entered_site = destination
	return {"ok": true}

# Travel.life remains the original body outcome until the root's actual body
# consumer has run. Completed-death history is not reapplied while the original
# FamilyContinuity UI finishes its required choice/failure transition.


var region_original_boundary_location: Callable

func _region_player_endpoint_location(status: Dictionary, party: Dictionary, coordinate: Vector2i, event: Dictionary) -> Dictionary:
	if str(party.get("mode", "land")) == "sea":
		return _region_endpoint_sea_location(status.get("plan", {}), party, coordinate)
	var contact: Dictionary = event.get("payload", {}).get("contact_receipt", {})
	if not contact.is_empty():
		if float(contact.get("at", -1.0)) != float(control.logical_game_seconds): return fail("STALE_REGION_CONTACT")
		var position: Dictionary = contact.get("second", {}).get("position", {})
		if position.get("site") != [coordinate.x, coordinate.y] or status.site != coordinate:
			return _region_original_boundary_location("player", status.token, party, coordinate, event)
		if not position.get("cell") is Array or position.cell.size() != 2: return fail("INVALID_JOINT_ENDPOINT")
		return {"ok": true, "entry": Vector2i(int(position.cell[0]), int(position.cell[1])),
			"vehicle_poses": status.get("vehicle_poses", status.get("plan", {}).get("steps", [])[int(status.step_index)].get("vehicle_poses", {}) if not status.get("plan", {}).is_empty() else {})}
	if status.site != coordinate: return fail("STALE_REGION_CONTACT")
	var current := status.duplicate(true)
	current.barrier = true
	return _region_arrival_location(current, party)


func _region_npc_endpoint_location(token: String, coordinate: Vector2i, event: Dictionary) -> Dictionary:
	var loaded := _region_npc_party(token)
	if not loaded.ok: return loaded
	var planned := _region_npc_plan(token)
	if not planned.ok: return planned
	var party: Dictionary = loaded.party
	if absf(float(party.upkeep.at) - float(control.logical_game_seconds)) > 0.00000001: return fail("UNSETTLED_PARTY")
	if str(party.get("mode", "land")) == "sea": return _region_endpoint_sea_location(planned.plan, party, coordinate)
	var position := _region_route_position(planned.plan, float(party.upkeep.get("distance", 0.0)))
	var contact: Dictionary = event.get("payload", {}).get("contact_receipt", {})
	if position.site != [coordinate.x, coordinate.y]:
		return _region_original_boundary_location("npc", token, party, coordinate, event)
	var step: Dictionary = planned.plan.steps[int(position.step_index)]
	var entry := RegionRoute.entry_cell(step)
	if not contact.is_empty():
		if float(contact.get("at", -1.0)) != float(control.logical_game_seconds): return fail("STALE_REGION_CONTACT")
		var accepted: Dictionary = contact.get("first", {}).get("position", {})
		if accepted.get("site") != position.site or not accepted.get("cell") is Array or accepted.cell.size() != 2:
			return fail("STALE_REGION_CONTACT")
		entry = Vector2i(int(accepted.cell[0]), int(accepted.cell[1]))
	if entry.x < 0: return fail("MISSING_ENTRY_PROOF")
	return {"ok": true, "entry": entry, "vehicle_poses": step.get("vehicle_poses", {}).duplicate(true)}


func _region_endpoint_sea_location(plan: Dictionary, party: Dictionary, coordinate: Vector2i) -> Dictionary:
	var projected := region_sea_pose_projection(plan, party)
	if not projected.ok: return projected
	var local_poses := {}
	var entry := Vector2i(-1, -1)
	var origin := Vector2(coordinate.x * Grid.SITE_CELLS, -coordinate.y * Grid.SITE_CELLS)
	for identity: String in projected.poses:
		var pose: Dictionary = projected.poses[identity]
		var local := Vector2(float(pose.world_anchor[0]), float(pose.world_anchor[1])) - origin
		if bool(pose.get("moving", false)) or not is_equal_approx(local.x, floor(local.x)) or not is_equal_approx(local.y, floor(local.y)):
			return _region_original_boundary_location(str(party.get("controller", "player")), str(party.party_id), party, coordinate,
				{"at": float(control.logical_game_seconds), "payload": {"sea_projection": projected, "site": [coordinate.x, coordinate.y]}})
		var cell := Vector2i(int(local.x), int(local.y))
		var vehicle: Dictionary = party.content.vehicles[identity]
		var facing := Vector2i(int(pose.facing[0]), int(pose.facing[1]))
		for occupied: Vector2i in Ship.footprint(str(vehicle.ship_type), cell, facing):
			if occupied.x < 0 or occupied.x >= Grid.SITE_CELLS or occupied.y < 0 or occupied.y >= Grid.SITE_CELLS:
				return _region_original_boundary_location(str(party.get("controller", "player")), str(party.party_id), party, coordinate,
					{"at": float(control.logical_game_seconds), "payload": {"sea_projection": projected, "site": [coordinate.x, coordinate.y]}})
		local_poses[identity] = {"anchor": [cell.x, cell.y], "facing": [facing.x, facing.y]}
		if entry.x < 0: entry = cell
	if entry.x < 0: return fail("MISSING_SHIP_POSE")
	return {"ok": true, "entry": entry, "vehicle_poses": local_poses, "sea_projection": projected}


func _region_original_boundary_location(controller: String, token: String, party: Dictionary, coordinate: Vector2i, event: Dictionary) -> Dictionary:
	if not region_original_boundary_location.is_valid(): return fail("MISSING_ORIGINAL_BOUNDARY_VIEW", "原跨界身體／reservation須完整幾何投影，不改寫已付步驟或塞回舊格")
	return region_original_boundary_location.call(controller, token, party, coordinate, event)


func _region_arrival_factions(state: Dictionary) -> Dictionary:
	var factions := {}
	for army: Dictionary in state.get("armies", []):
		for person: Dictionary in army.get("units", []): factions[int(person.person_id)] = int(army.faction_id)
		var member: Dictionary = army.get("player_member", {})
		if not member.is_empty(): factions[int(member.id)] = int(army.faction_id)
	for actor: Dictionary in state.get("actors", {}).values(): factions[int(actor.person_id)] = int(actor.faction_id)
	return factions


func _region_arrival_battle_candidate(before: Dictionary, after: Dictionary, party: Dictionary,
		mapping: Dictionary, token: String, binding: Dictionary, player_present: bool) -> Dictionary:
	var site_id := str(after.id)
	var factions := _region_arrival_factions(after)
	var incoming: Array[int] = []
	var incoming_factions := {}
	for identity: Variant in party.person_ids:
		var local := int(mapping.maps.person[str(int(identity))])
		if not factions.has(local): return fail("INVALID_BATTLE_OWNER", "到站原人物不在完整候選")
		incoming.append(local)
		incoming_factions[int(factions[local])] = true
	if incoming_factions.size() != 1: return {"ok": true, "battle": {}}
	var faction := int(incoming_factions.keys()[0])
	var original_people := RegionTravel._body_records(before)
	var existing: Dictionary = {}
	for battle: Dictionary in region_registry().battles.values():
		if str(battle.get("site_id", "")) == site_id and str(battle.get("phase", "")) != "finished":
			if not existing.is_empty(): return fail("BATTLE_OWNER_CONFLICT", "同Site多場原戰鬥須原GD完整消費者")
			existing = battle.duplicate(true)
	var seed := existing
	if seed.is_empty():
		var defenders: Array[int] = []
		var defender_factions := {}
		for identity: int in original_people:
			if identity == int(after.get("controlled_person_id", 0)) or not factions.has(identity) or int(factions[identity]) == faction: continue
			defenders.append(identity)
			defender_factions[int(factions[identity])] = true
		# The two-side formula cannot silently make hostile third factions allies.
		# Original cold GD remains the exact owner when that topology is present.
		if defenders.is_empty() or defender_factions.size() != 1 or player_present:
			return {"ok": true, "battle": {}}
		var made := RegionBattle.create({"id": "arrival:" + token, "site_id": site_id,
			"attackers": incoming, "defenders": defenders, "game_time": float(control.logical_game_seconds),
			"rng_state": int(hash(str(pin.world_instance_id) + ":" + token)), "player_site": false,
			"player_party": false, "player_barrier": false})
		if not made.ok: return made
		seed = made.battle
	else:
		if not seed.get("pending", []).is_empty(): return fail("REGION_EFFECTS_PENDING", "原戰鬥未完同刻效果不能被到站重編")
		var sides := {}
		for side: String in ["attackers", "defenders"]:
			var values := {}
			for identity: Variant in seed.get(side, []):
				if factions.has(int(identity)): values[int(factions[int(identity)])] = true
			if values.size() != 1: seed.mode = "cold_exact"; return {"ok": true, "battle": seed}
			sides[side] = int(values.keys()[0])
		var side := "attackers" if int(sides.attackers) == faction else ("defenders" if int(sides.defenders) == faction else "")
		if side.is_empty(): seed.mode = "cold_exact"; return {"ok": true, "battle": seed}
		for identity: int in incoming:
			if not seed[side].has(identity): seed[side].append(identity)
		seed.round_inputs = {}
		seed.mode = "live" if player_present else "formula_active"
		seed.revision = int(seed.revision) + 1
	if player_present:
		seed.mode = "live"
		return {"ok": true, "battle": seed, "reinforcement": str(seed.id)}
	if not binding.get("resolve_battle_people") is Callable or not binding.resolve_battle_people.is_valid():
		return fail("MISSING_ORIGINAL_BATTLE_WITNESS", "完整候選須原隱藏graph接觸證明")
	var witnessed: Variant = binding.resolve_battle_people.call(seed)
	if not witnessed is Dictionary or not bool(witnessed.get("ok", false)) or not witnessed.get("people") is Dictionary:
		return witnessed if witnessed is Dictionary else fail("INVALID_BATTLE_WITNESS")
	var contacts := false
	for person: Dictionary in witnessed.people.values():
		if not person.get("legal_targets", []).is_empty(): contacts = true
	if not contacts:
		return {"ok": true, "battle": existing, "reinforcement": str(existing.get("id", ""))}
	return {"ok": true, "battle": seed, "reinforcement": str(seed.id)}


## The only positive-time exception behind an accepted player barrier is the
## actual original live body's remaining down timer. Nothing sets this proof.
func _region_player_down_settlement() -> Dictionary:
	var owner := str(control.get("active_site_id", ""))
	if owner.is_empty(): return {}
	var mode: Dictionary = region_registry().modes.get(owner, {})
	if mode.get("mode") != "live" or mode.get("backend") != "gd" or mode.get("activation", {}).get("complete") != true or int(mode.get("generation", -1)) != int(_marker.get("generation", 0)):
		return {}
	if not GameplayClock.validate_mode(mode, owner, float(control.logical_game_seconds)).ok or float(mode.game_seconds) != float(control.logical_game_seconds) or float(mode.action_seconds) != float(control.fire_clock.action_seconds) or int(mode.activation.get("generation", -1)) != int(_marker.get("generation", 0)) or str(mode.consumer) != "original_site": return {}
	var original: TerrainLab
	if region_owner_lab.is_valid():
		var candidate: Object = region_owner_lab.get_object()
		if candidate is TerrainLab: original = candidate
	if not is_instance_valid(original) or original.restore_only or original.site_controller == null or original.site_controller.region_slot != self or original.terrain == null or str(original.terrain.site.id) != owner or original._region_bound_data != original.terrain or original._region_bind_receipt_value.get("complete") != true or original._region_bind_receipt_value.get("owners_restored") != true or original.crowd_site != null and original.crowd_site.active:
		return {}
	var bind: Dictionary = original.region_bind_receipt(original.terrain)
	if bind.get("ok") != true or bind.get("complete") != true or str(bind.get("owner", "")) != owner or int(bind.get("generation", -1)) != int(_marker.get("generation", 0)): return {}
	if original.get_tree().paused or bool(original.terrain.site.get("paused", false)): return {}
	var identity := original.controlled_person_id()
	var person := original._original_person_target(identity)
	if person.is_empty(): return {}
	var hp: float = float(person.owner.combat_hot_get(int(person.unit), &"hp")) if int(person.unit) >= 0 else float(person.owner.hp)
	if not original.site_controller._pending_deaths.has(identity): return {}
	var remaining := float(original.site_controller._pending_deaths[identity])
	if hp > 0.0 or not is_finite(remaining) or remaining < 0.0 or remaining > float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) + TerrainLab.ACTION_TIME_EPSILON: return {}
	if remaining <= TerrainLab.ACTION_TIME_EPSILON:
		# An already committed land step may outlast down. Only its actual
		# original movement state supplies that future close, never a new order.
		remaining = _region_player_committed_close_action(person)
		if remaining <= TerrainLab.ACTION_TIME_EPSILON: return {}
	var settlement := validate_settlement(original.terrain.site, float(control.logical_game_seconds))
	if not settlement.ok or settlement.legacy or float(settlement.pending) > 0.00000001: return {}
	var fire: Dictionary = original.terrain.site.get("fire_settlement", {})
	if not validate_fire_settlement(original.terrain.site, control.fire_clock).ok or int(fire.get("sequence", -1)) != int(control.fire_clock.sequence) or float(fire.get("action_seconds", -1.0)) != float(control.fire_clock.action_seconds) or float(fire.get("game_seconds", -1.0)) != float(control.logical_game_seconds): return {}
	var point_pending := not original._region_point_pending.is_empty()
	if point_pending:
		# The owner's running zero-time point may drain its own accepted queue
		# after the real death effect. Positive admissions never enter this arm.
		var point: Dictionary = original._region_point_pending
		var boundary: Dictionary = original.terrain.get_meta(&"fire_boundary", {})
		if not (original._region_point_consuming or original._region_point_dispatching) or point.get("interval_complete") != true or float(point.get("game_end", -1.0)) != float(control.logical_game_seconds) or float(point.get("action_end", -1.0)) != float(control.fire_clock.action_seconds) or float(point.get("fire_action_end", -1.0)) != float(control.fire_clock.action_seconds): return {}
		if absf(original.fire_action_cursor - float(point.get("fire_action_begin", -1.0))) > 0.00000001 and absf(original.fire_action_cursor - float(point.fire_action_end)) > 0.00000001: return {}
		if not boundary.is_empty() and (str(boundary.get("site_id", "")) != owner or absf(float(boundary.get("action_end", -1.0)) - float(control.fire_clock.action_seconds)) > 0.00000001): return {}
	elif absf(original.fire_action_cursor - float(control.fire_clock.action_seconds)) > 0.00000001: return {}
	var allowed: Array[String] = []
	for event: Dictionary in GameplayClock.pending_at(region_registry(), float(control.logical_game_seconds)):
		if not bool(event.player) or str(event.kind) not in ["player_death", "life"]: continue
		var payload: Dictionary = event.payload
		if payload.get("controlled") != true or payload.get("death") != true or int(payload.get("person_id", -1)) != identity or payload.get("destination_site") != owner: continue
		if not _region_player_death_effect_receipt(event): continue
		var token := str(event.owner).trim_prefix("travel:")
		if token.is_empty() or not _region_player_death_mapping(event, original.terrain): continue
		allowed.append(str(event.id))
	if allowed.is_empty(): return {}
	return {"event_ids": allowed, "remaining_action_seconds": remaining, "lab": original, "point_pending": point_pending,
		"generation": int(_marker.get("generation", 0)), "revision": int(region_registry().revision), "person_id": identity}

func _region_player_committed_close_action(person: Dictionary) -> float:
	if not bool(person.get("moving", false)): return 0.0
	if int(person.unit) < 0:
		var actor: TerrainTestCharacter = person.owner
		if not actor.is_moving() or actor.data == null or not actor.data.contains(actor.terrain_cell) or not actor.data.contains(actor.movement_from_cell) or not is_finite(actor._movement_duration) or not is_finite(actor._movement_elapsed): return 0.0
		return maxf(0.0, actor._movement_duration - actor._movement_elapsed)
	var team: TerrainArmy = person.owner
	var unit := int(person.unit)
	if unit < 0 or unit >= team.moving_to.size() or not team._reserved_cells.has(team.moving_to[unit]) or int(team._reserved_cells[team.moving_to[unit]]) != unit: return 0.0
	return maxf(0.0, float(team.move_duration[unit]) * (1.0 - float(team.move_progress[unit])))

## A mapped death remains the immutable accepted event after the down interval.
## Its original destination/body is inspected; old party files are never reborn.
func _region_mapped_player_death(event: Dictionary) -> bool:
	var payload: Dictionary = event.get("payload", {})
	if event.get("player") != true or str(event.get("kind", "")) not in ["player_death", "life"] or payload.get("controlled") != true or payload.get("death") != true or not str(event.get("owner", "")).begins_with("travel:") or not GameplayClock.seconds(event.get("at")) or float(event.at) > float(control.logical_game_seconds) + 0.00000001: return false
	if not _region_player_death_effect_receipt(event): return false
	var token := str(event.owner).trim_prefix("travel:")
	var destination := str(payload.get("destination_site", ""))
	if destination.is_empty(): return false
	var original: TerrainLab = _region_original_labs.get(destination)
	if destination == str(control.active_site_id) and region_owner_lab.is_valid():
		var candidate: Object = region_owner_lab.get_object()
		if candidate is TerrainLab: original = candidate
	if not is_instance_valid(original) or original.site_controller == null or original.site_controller.region_slot != self or original.terrain == null or original._region_bound_data != original.terrain or str(original.terrain.site.id) != destination or original._region_bind_receipt_value.get("owners_restored") != true: return false
	if not _region_player_death_mapping(event, original.terrain): return false
	var person := original._original_person_target(int(payload.get("person_id", -1)))
	if person.is_empty(): return false
	var hp: float = float(person.owner.combat_hot_get(int(person.unit), &"hp")) if int(person.unit) >= 0 else float(person.owner.hp)
	return hp <= 0.0

func _region_player_death_effect_receipt(event: Dictionary) -> bool:
	var payload: Dictionary = event.get("payload", {})
	var receipt: Variant = payload.get("effect_receipt")
	if not receipt is Dictionary or receipt.size() != 5: return false
	for field: String in ["event_id", "person_id", "effects_complete", "game_seconds", "action_seconds"]:
		if not receipt.has(field): return false
	return receipt.event_id == event.get("id") and receipt.person_id == payload.get("person_id") and receipt.effects_complete == true and GameplayClock.seconds(receipt.game_seconds) and float(receipt.game_seconds) == float(event.get("at", -1.0)) and GameplayClock.seconds(receipt.action_seconds) and float(receipt.action_seconds) <= float(control.fire_clock.action_seconds) + 0.00000001

func _region_player_death_mapping(event: Dictionary, data: TerrainData) -> bool:
	if data == null or data.site.is_empty(): return false
	var payload: Dictionary = event.get("payload", {})
	var mapping: Variant = payload.get("arrival_mapping")
	if not RegionTravel.validate_arrival_mapping(mapping) or not str(event.get("owner", "")).begins_with("travel:"): return false
	var token := str(event.owner).trim_prefix("travel:")
	var identity: Dictionary = data.site.get("travel_identity", {})
	if not RegionTravel.validate_identity(identity) or token.is_empty() or mapping.token != token or str(mapping.destination_namespace) != str(identity.namespace) or int(mapping.generation) > int(_marker.get("generation", 0)): return false
	return GameplayClock.whole(payload.get("person_id"), 1) and mapping.maps.person.values().has(str(int(payload.person_id)))

func _region_positive_player_death_ids() -> Array[String]:
	var proof := _region_player_down_settlement()
	var result: Array[String] = []
	if not proof.is_empty() and not bool(proof.point_pending): result.assign(proof.event_ids)
	return result
