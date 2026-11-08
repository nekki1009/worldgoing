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
## SHIPCROWD: the live Site's crowd owner converts a crowd team aboard the selected ships into its complete grid army
## snapshot (passenger rows with their boat fields) inside a ship transfer's origin copy. Called as
## (origin: Dictionary, boat_ids: Array) -> {ok, successor}; the origin is edited in place. Unset refuses a crowd Site.
var ship_transfer_crowd_adapter: Callable
var _marker: Dictionary = {}
var _faction_source_cache: Dictionary = {}
var _faction_clock_cache: Dictionary = {}
var _faction_cache_scope := ""
# Exact input bytes catch nested/in-place pin changes, including int vs float.
var _faction_context_inputs: Dictionary = {}
# Independent computed bytes/digests; no mutable summary/clock refs are stored.
var _faction_summary_digest_memo: Dictionary = {}
var _faction_clock_digest_memo: Dictionary = {}
const FACTION_SOURCE_CACHE_LIMIT := 128
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
	if not prepare_new and not initial_context.is_empty(): return fail("INVALID_INITIAL_SCENARIO")
	if map_data == null or map_data.manifest.is_empty(): return fail("MISSING_BASE")
	var author_context: Dictionary = map_data.author_initial_context()
	_opening_author_context = author_context
	if not author_context.is_empty():
		if not author_initial_context_valid(author_context): return fail("INVALID_AUTHOR_CONTEXT")
		# A read-only open of a cross-Site package that was never born keeps the P5B refusal code.
		if not prepare_new and author_context.expected_initial_sites.size() != 1:
			if not _safe_part(world_instance_id) or not _safe_part(slot_id): return fail("INVALID_SLOT")
			var unborn_location: String = "user://region_lab/worlds/%s/slots/%s" % [world_instance_id, slot_id]
			if not FileAccess.file_exists(unborn_location.path_join("manifest.json")) and not FileAccess.file_exists(unborn_location.path_join("manifest.pending.json")) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(unborn_location)): return fail("AUTHOR_MULTI_SITE_UNSUPPORTED")
		# P5C-S2: every expected initial Site projects before any file IO, so a
		# damaged companion never leaves a partial birth behind.
		for coordinate: Vector2i in author_initial_site_order(author_context):
			var projected: Dictionary = map_data.project_terrain(coordinate, "author_initial")
			if not projected.ok: return projected
			# P5C-S3C: every authored resident must name a house that exists on its own Site, refused before any IO.
			var residents: Array = projected.data.site.get("residents", [])
			if not residents.is_empty():
				# Same view the birth roster uses: navigation rebuilds the indexes that house_layout reads.
				var housed: TerrainData = Env.navigation_for_state(projected.data, projected.data.site.duplicate(true))
				for row: Variant in residents:
					if not row is Dictionary or not Runtime.house_layout(housed, str(row.get("house", ""))).ok: return fail("AUTHOR_RESIDENT_HOUSE_MISSING", "居民住宅不存在；未寫入")
		if prepare_new and not same_author_initial_context(initial_context, author_context): return fail("INITIAL_SCENARIO_CONFLICT")
		var start_site: Vector2i = Vector2i(int(author_context.starting_site[0]), int(author_context.starting_site[1]))
		var initial: Dictionary = map_data.project_terrain(start_site, "author_initial")
		if not initial.ok: return initial
		if not initial.data.site.is_empty():
			var buildings: Dictionary = Runtime.validate_author_buildings(initial.data)
			if not buildings.ok: return buildings
		if not initial.data.contains(Vector2i(int(author_context.start.cell[0]), int(author_context.start.cell[1]))) or not initial.data.is_walkable(Vector2i(int(author_context.start.cell[0]), int(author_context.start.cell[1]))): return fail("NO_BIRTH_GROUND")
	elif initial_context.get("mode") == "author": return fail("INITIAL_PIN_CONFLICT")
	# Reject non-creation config before reading a world file or making folders.
	if not prepare_new and not initial_context.is_empty(): return fail("INVALID_INITIAL_SCENARIO")
	if prepare_new and not _initial_context_ok(initial_context): return fail("INVALID_INITIAL_SCENARIO")
	if map_data == null or map_data.manifest.is_empty(): return fail("MISSING_BASE", "尚未載入固定地圖")
	if not _safe_part(world_instance_id) or not _safe_part(slot_id): return fail("INVALID_SLOT")
	var empty_policy := TechnologyPolicy.new_policy(_initial_technology_categories())
	if not empty_policy.ok: return empty_policy
	var expected := {"format": 2, "world_instance_id": world_instance_id, "slot_id": slot_id,
		"technology_policy": empty_policy.policy, "atlas_id": str(map_data.manifest.atlas_id),
		"grid_contract_version": int(map_data.manifest.grid_contract_version), "base_revision": str(map_data.manifest.base_revision),
		"manifest_sha256": map_data.manifest_hash, "ramp_rule_revision": RegionTerrainAdapter.RAMP_RULE_REVISION}
	if not author_context.is_empty():
		expected.format = 3
		expected.merge(map_data.author_identity(), true)
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
	if not prepare_new and not author_context.is_empty() and not manifest_exists and not FileAccess.file_exists(pending_path) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(location)): return fail("INITIALIZATION_REQUIRED")
	var pending_record := {}
	var recover_first_marker := false
	if manifest_exists:
		var file := FileAccess.open(manifest_path, FileAccess.READ)
		if file == null or file.get_length() > 4096: return fail("INVALID_SLOT")
		var recorded: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if not recorded is Dictionary or not _whole(recorded.get("format"), 1, 3): return fail("INVALID_SLOT")
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
		if prepare_new and not _same_initial_request(pending_record, initial_context): return fail("INITIAL_SCENARIO_CONFLICT", "待提交的原開局選擇不可重選")
	elif not manifest_exists:
		# A valid same-pin pending write can be completed after a rename crash.
		if FileAccess.file_exists(pending_path + ".tmp"):
			var pending_read := _read_document(pending_path + ".tmp", 16384)
			if pending_read.ok and _initial_pending_ok(pending_read.get("payload"), expected):
				if prepare_new and not _same_initial_request(pending_read.payload, initial_context): return fail("INITIAL_SCENARIO_CONFLICT")
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
			pending_record = {"version": 1, "pin": expected.duplicate(true), "starting_site": initial_context.starting_site.duplicate(), "initial_scenario_id": str(initial_context.get("initial_scenario_id", ""))}
			if not author_context.is_empty():
				pending_record.version = 2
				pending_record["author_context"] = author_context.duplicate(true)
	if prepare_new and not pending_record.is_empty() and not _same_initial_request(pending_record, initial_context): return fail("INITIAL_SCENARIO_CONFLICT")
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
		if prepare_new and not _same_initial_request(_initialization, initial_context): return fail("INITIAL_SCENARIO_CONFLICT")
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
	var persons: Dictionary = _open_person_allocator(prepare_new)
	if not persons.ok: return persons
	return {"ok": true, "person_upgrade": persons.get("upgrade_refused", {}), "path": manifest_path, "initialization_pending": initialization_pending(), "initialization_committed": not _marker.is_empty()}

static func _same_pin(left: Variant, right: Dictionary) -> bool:
	if not left is Dictionary or left.size() != right.size():
		return false
	for key: String in ["world_instance_id", "slot_id", "atlas_id", "base_revision", "manifest_sha256", "ramp_rule_revision"]:
		if left.get(key) != right.get(key):
			return false
	if not Store._same_resource_pin(left, right):
		return false
	if not _whole(left.get("format"), 1, 3) or not _whole(right.get("format"), 1, 3) or int(left.format) != int(right.format): return false
	var author := int(left.format) == 3
	if author != RegionTerrainAdapter.has_author_identity(left) or author != RegionTerrainAdapter.has_author_identity(right) or not RegionTerrainAdapter.same_author_identity(left, right): return false
	if author:
		var count := 8 + RegionTerrainAdapter.AUTHOR_FIELDS.size() + 1
		if left.has("resource_layer_sha256") or left.has("resource_rule_revision"): count += 2
		if left.size() != count or not left.has("technology_policy") or left.has("effective_environment_sha256") or right.has("effective_environment_sha256"): return false
		for field: String in ["format", "world_instance_id", "slot_id", "atlas_id", "grid_contract_version", "base_revision", "manifest_sha256", "ramp_rule_revision", "technology_policy"]:
			if not left.has(field) or not right.has(field): return false
		if not Store._world_pin_identity(left.world_instance_id) or not Store._world_pin_identity(left.slot_id) or left.atlas_id != Grid.ATLAS_ID or not _whole(right.grid_contract_version, Grid.CONTRACT_VERSION, Grid.CONTRACT_VERSION) or int(left.grid_contract_version) != Grid.CONTRACT_VERSION or not RegionTerrainAdapter.author_digest_valid(left.manifest_sha256): return false
		for field: String in ["base_revision", "ramp_rule_revision"]:
			if not left[field] is String or str(left[field]).is_empty(): return false
	var policy: Dictionary = TechnologyPolicy.same_candidate(left, right, int(left.format) == 1, int(right.format) == 1)
	return policy.ok \
		and _whole(left.get("grid_contract_version"), 1, 1000) \
		and int(left.grid_contract_version) == int(right.grid_contract_version)

func _matches_base(base: Dictionary, site: Vector2i) -> bool:
	return not pin.is_empty() and source != null and source.manifest_hash == str(pin.manifest_sha256) \
		and RegionTerrainAdapter.same_author_identity(base, pin) \
		and RegionTerrainAdapter.valid_author_identity(base, true) \
		and source.author_identity_matches(pin) \
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

## starter=false: an unvisited Site opened as an arriving party's destination
## has no resident Actor or default worker (as _ground_destination). Every other
## caller keeps the standard starter.
func open_site(site: Vector2i, starter: bool = true) -> Dictionary:
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
	var fresh: Dictionary = source.project_terrain(site, "author_initial") if not source.author_identity().is_empty() else source.make_terrain_data(site.x, site.y)
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
	if data.site.is_empty(): Env.initialize(data, str(fresh.base.site_id))
	# Same as the ground-crossing visit: a fresh interactive Site carries item
	# storage, which Core construction payment reads before any first save.
	var storage := Runtime.initialize_item_storage(data.site)
	if not storage.ok: return storage
	if not starter or (person_allocator_enabled() and not _marker.is_empty() and data.site.get("actors", {}).is_empty()):
		data.site.actor_presence_version = 1
		data.site.actors = {}
		data.site.worker_enabled = false
		var retired := Store.retire_default_worker(data)
		if not retired.ok: return retired
	data.site.world_pin = pin.duplicate(true)
	var genesis := _settle_cold_candidate(data, float(control.logical_game_seconds))
	if not genesis.ok: return genesis
	data = genesis.data
	if not _fire_history_empty(data.site): return fail("INVALID_NEW_SITE", "新地點已存在原火攻歷史")
	data.site.fire_settlement = {"version": 1, "epoch": str(control.fire_clock.epoch), "sequence": int(control.fire_clock.sequence),
		"action_seconds": float(control.fire_clock.action_seconds), "game_seconds": float(control.logical_game_seconds)}
	attach_person_allocator(data)
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
		var rebuilt: Dictionary = RegionRoute.fresh_fixed_base(source, site)
		if not bool(rebuilt.get("ok", false)) or not _matches_base(rebuilt.get("base", {}), site) \
				or str(rebuilt.base.terrain_fingerprint) != str(base.get("terrain_fingerprint", "")):
			return fail("SAVE_VERSION", "提交候選的固定來源不可重建")
		return rebuilt, 1, true)
	if not loaded.ok: return loaded
	var policy_guard := _admit_world_pin(loaded.data)
	return loaded if policy_guard.ok else policy_guard

func _save_checked(data: TerrainData, site: Vector2i, path: String, reuse_entry: Dictionary = {}) -> Dictionary:
	return _save_checked_owner_capture(data, site, path, reuse_entry, false)

func _save_checked_owner_capture(data: TerrainData, site: Vector2i, path: String, reuse_entry: Dictionary = {}, read_only: bool = false) -> Dictionary:
	var coordinate := _coordinate(data)
	if not coordinate.ok or coordinate.site != site: return coordinate if not coordinate.ok else fail("SAVE_VERSION", "候選位置不符")
	var original := _region_bound_original_lab(data)
	var saved: Dictionary
	var source_context: Dictionary = {}
	if original != null:
		var effects_complete := original._region_point_pending.is_empty() and not original._region_point_consuming and pending_region_events().is_empty()
		var capture: Dictionary = original.site_controller.capture_region_checkpoint("region_checkpoint" if effects_complete else "region_barrier",
			effects_complete, original._region_point_pending, "", read_only)
		if not capture.ok: return capture
		source_context = capture.context
		if not reuse_entry.is_empty():
			var reused: Dictionary = _reuse_ship_checkpoint_source(site, reuse_entry, capture)
			if not reused.ok: return reused
			if bool(reused.get("reused", false)): return reused
		var durable: TerrainData = data
		if read_only:
			durable = TerrainLab._region_detached_bind_data(data)
			durable.site = capture["state"]
		# Non-read-only: durable is `data`, the bound original's own terrain that
		# capture_region_checkpoint just captured in this same call.
		if not read_only and capture.get("payload") is Dictionary: saved = Store.write_region_capture(durable, path, capture)
		else: saved = Store.save_region_snapshot(durable, path, capture.context, capture.owners)
	elif data.site.has("region_snapshot"):
		var captured := Store.validate_region_snapshot(data, {})
		if not captured.ok:
			if str(captured.get("code", "")) == "CORRUPT_REGION_SNAPSHOT": # Diagnostic tags only.
				captured["source"] = "save_checked"
				captured["site_id"] = str(data.site.get("id", ""))
			return captured
		saved = Store.save_region_snapshot(data, path, captured.context, captured.owners)
	else:
		saved = Store.save(data, path)
	if not saved.ok: return saved
	var source_checksum: String = _faction_file_sha256(path) if not source_context.is_empty() else ""
	var readback := _load_checked(path, site)
	if not readback.ok: return readback
	if not source_context.is_empty():
		var remembered: Dictionary = _faction_remember_captured_source(path, site, source_checksum, readback.data, source_context)
		if not remembered.ok: return remembered
	return {"ok": true, "path": path, "data": readback.data}

## Decision A: a never-visited Site created as an arrival destination becomes a
## selected source before the arrival bind. Only its own settled genesis is
## written; clock, journey, transfer token and every other Site entry carry over.
func publish_region_destination_genesis(data: TerrainData) -> Dictionary:
	var coordinate := _coordinate(data)
	if not coordinate.ok: return coordinate
	if not region_bind_proof(data).is_empty(): return {"ok": true, "generation": int(_marker.get("generation", 0)), "published": false}
	if str(region_travel_journey().get("token", "")).is_empty(): return fail("NO_TARGET", "沒有原玩家旅隊")
	var settlement := validate_settlement(data.site, control.logical_game_seconds)
	if not settlement.ok or bool(settlement.legacy) or float(settlement.pending) > 0.00001: return fail("UNSETTLED_SITE", "目的地 genesis 尚未到同一端點")
	var generation := int(_marker.get("generation", 0)) + 1
	var path := _generation_path(generation, coordinate.site)
	var saved := _save_checked(data, coordinate.site, path)
	if not saved.ok: return saved
	var sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	sites[_site_key(coordinate.site)] = _file_entry(path)
	var next_control := control.duplicate(true)
	if data.site.has("fire_settlement"):
		var fire_settlement: Dictionary = data.site.fire_settlement
		next_control.fire_clock.index[str(data.site.id)] = {"coordinate": [coordinate.site.x, coordinate.site.y],
			"active": false, "fire_active": false, "sequence": int(fire_settlement.sequence),
			"action_seconds": float(fire_settlement.action_seconds), "game_seconds": float(fire_settlement.game_seconds)}
	var published := _publish(sites, next_control, str(_marker.get("transfer_token", "")), _marker.get("journey", {}))
	if published.ok:
		published["published"] = true
		published["data"] = saved.data # The canonical readback is the selected source body.
	return published

func _file_entry(path: String) -> Dictionary:
	return {"path": path.trim_prefix(folder + "/"), "sha256": FileAccess.get_sha256(path)}

func _generation_path(generation: int, site: Vector2i) -> String:
	return folder.path_join("generations/%020d_%d_%d_%d.json" % [generation, site.x, site.y, Time.get_ticks_usec()])

func _read_document(path: String, maximum: int = 1048576) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > maximum: return fail("SAVE_IO", "存檔槽記錄無法讀取")
	var envelope_parser := JSON.new()
	var envelope_error := envelope_parser.parse(file.get_as_text())
	file.close()
	if envelope_error != OK: return fail("CORRUPT_SAVE", "存檔槽記錄格式損毀，原代保留")
	var envelope: Variant = envelope_parser.data
	# A Site file written by SiteStore since 31c352b also carries "crowd_era": 1 in its envelope.
	var era_ok: bool = envelope is Dictionary and (envelope.size() == 2 or envelope.size() == 3 and envelope.has("crowd_era") and int(envelope.crowd_era) == 1)
	if not envelope is Dictionary or not era_ok or not envelope.get("payload") is String \
			or not envelope.get("checksum") is String or str(envelope.payload).sha256_text() != str(envelope.checksum):
		return fail("CORRUPT_SAVE", "存檔槽記錄校驗失敗，原代保留")
	var payload_parser := JSON.new()
	if payload_parser.parse(envelope.payload) != OK: return fail("CORRUPT_SAVE", "存檔槽記錄格式")
	var payload: Variant = payload_parser.data
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
	_faction_static_reading = _faction_static_cold
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
	elif not is_same(_marker, previous_marker) and previous_scope == folder \
			and _whole(previous_marker.get("generation"), 1, 2147483647) \
			and int(previous_marker.generation) == int(_marker.get("generation", -1)) \
			and _faction_marker_same_wire(previous_marker, _marker):
		# Disk/scope/source validation already succeeded. Keep an independent typed
		# snapshot so the specified hot algorithm can match on its next invocation.
		var known_snapshot: Dictionary = _recover_known_commit.get(folder, {})
		if known_snapshot.get("scope") == _faction_cache_scope and int(known_snapshot.get("generation", -1)) == int(previous_marker.generation):
			known_snapshot.recorded = previous_marker.duplicate(true)
		_marker = previous_marker
	_faction_static_reading = false
	_faction_static_cold = false
	return result

# folder -> last fully validated commit, including its faction result.
var _recover_known_commit: Dictionary = {}

## Lists, reads and fully validates the latest commit of this folder.
func _recover_read_latest(preserve_live: bool, live_control: Dictionary) -> Dictionary:
	var commits := DirAccess.open(folder.path_join("commits"))
	if commits == null:
		if preserve_live: control = live_control
		if not control.has("fire_clock"): control.fire_clock = _new_fire_clock(float(control.logical_game_seconds))
		return {"ok": true, "empty": true}
	var files: Array[String] = []
	for name: String in commits.get_files():
		if name.ends_with(".json") and name.trim_suffix(".json").length() == 20 and name.trim_suffix(".json").is_valid_int(): files.append(name)
	if files.is_empty():
		if preserve_live: control = live_control
		if not control.has("fire_clock"): control.fire_clock = _new_fire_clock(float(control.logical_game_seconds))
		return {"ok": true, "empty": true}
	files.sort()
	# A fully renamed marker is a commit. Corruption of its selected generation
	# is an error; falling back would resurrect ownership from an older Site.
	var latest := _read_document(folder.path_join("commits").path_join(files.back()))
	if not latest.ok: return latest
	var recorded: Dictionary = latest.payload
	if recorded.size() != 7 or not _whole(recorded.get("format"), 1, 2) \
			or not _whole(recorded.get("generation"), 1, 2147483647) or not _same_pin(recorded.get("pin"), pin) \
			or int(recorded.generation) != int(files.back().trim_suffix(".json")) \
			or not recorded.get("sites") is Dictionary or not recorded.get("transfer_token") is String \
			or not recorded.get("journey") is Dictionary or not recorded.get("control") is Dictionary:
		return fail("CORRUPT_SAVE", "存檔槽提交版本／來源／欄位")
	var clock: Dictionary = recorded.control
	# bytes_to_var() is the original no-object Variant decoder.
	# Legacy bare JSON clocks still pass the same validators below.
	if clock.has("encoding") or clock.has("value"):
		if clock.size() != 2 or clock.get("encoding") != "godot_var_v1" or not clock.get("value") is String:
			return fail("CORRUPT_SAVE", "存檔槽 control 原 Variant 編碼欄位")
		var decoded: Dictionary = _faction_decode_clock(str(clock.value))
		if not decoded.ok: return decoded
		clock = decoded.clock
		recorded.control = clock
	var clock_fields: Array = ["logical_game_seconds", "active_site_id"]
	for optional: String in ["fire_clock", "region_gameplay", "faction_registry", "person_allocator"]:
		if clock.has(optional): clock_fields.append(optional)
	if int(recorded.format) == 1 and clock.has("faction_registry") or int(recorded.format) == 2 and not clock.has("faction_registry"): return fail("SAVE_VERSION", "faction control marker version")
	if not RegionFactionQuery.keys(clock, clock_fields) or not clock.get("active_site_id") is String \
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
	if clock.has("person_allocator") and not person_allocator_valid(clock.person_allocator, str(pin.world_instance_id)): return fail("CORRUPT_PERSON_ALLOCATOR")
	var active_found: bool = str(clock.active_site_id).is_empty()
	for key: Variant in recorded.sites:
		var components: PackedStringArray = str(key).split(":")
		var entry: Variant = recorded.sites[key]
		if not key is String or components.size() != 2 or not components[0].is_valid_int() or not components[1].is_valid_int() \
				or not entry is Dictionary or entry.size() != 2 or not entry.get("path") is String or not entry.get("sha256") is String:
			return fail("CORRUPT_SAVE", "提交地點／檔案欄位")
		var relative := str(entry.path)
		if not relative.begins_with("generations/") or not relative.ends_with(".json") or relative.contains("..") or relative.contains("\\") \
				or relative.split("/").size() != 2 or not _faction_digest_valid(str(entry.sha256)):
			return fail("CORRUPT_SAVE", "提交地點檔案缺失／變更，拒絕重播舊移交")
		var coordinate := Vector2i(int(components[0]), int(components[1]))
		if _site_key(coordinate) != key: return fail("CORRUPT_SAVE", "提交地點坐標不是唯一格式")
		if clock.has("faction_registry"):
			# The write-once digest selects fully validated facts across generations.
			# A miss still checks the bytes and the original Store/World validator.
			# The faction scan below asks for person sources when the allocator is recorded; the
			# same single validation records them, so a cold reopen reads each Site once.
			var selected: Dictionary = _faction_site_source(folder.path_join(relative), coordinate, str(entry.sha256), clock.has("person_allocator"))
			if not selected.ok: return selected
		elif _faction_file_sha256(folder.path_join(relative)) != str(entry.sha256):
			return fail("CORRUPT_SAVE", "提交地點檔案缺失／變更，拒絕重播舊移交")
		active_found = active_found or str(clock.active_site_id) == Grid.site_id(str(pin.atlas_id), coordinate)
	if not active_found: return fail("CORRUPT_SAVE", "活動地點未包含在同代提交")
	var journey: Dictionary = recorded.journey
	var normalized := _normalize_journey(journey)
	if not normalized.ok: return normalized
	recorded.journey = normalized.journey
	if clock.has("faction_registry"):
		var factions: Variant = RegionFactionQuery.validate(clock.faction_registry, float(clock.logical_game_seconds))
		if not factions.ok: return factions
		var sources: Dictionary = _faction_scan(recorded.sites, clock, recorded.journey, clock.faction_registry, [], false, clock.has("person_allocator"))
		if not sources.ok: return sources
		if clock.has("person_allocator"):
			var persons: Dictionary = person_migration(str(pin.world_instance_id), sources.person_sources, clock.person_allocator)
			if not persons.ok or persons.allocator != clock.person_allocator: return fail("CORRUPT_PERSON_ALLOCATOR")
		if sources.registry.entries != clock.faction_registry.entries or int(sources.registry.next_faction_id) != int(clock.faction_registry.next_faction_id): return fail("CORRUPT_SAVE", "faction marker/source disagreement")
	return {"ok": true, "recorded": recorded, "name": files.back()}

func _recover_control_from_files() -> Dictionary:
	var live_control: Dictionary = control
	# Recovery detaches _marker before validation; retain the original read-only owner.
	var live_marker: Dictionary = _marker
	var live_generation := int(live_marker.get("generation", -1))
	var preserve_live := _control_scope == folder
	_marker = {}
	_control_scope = folder
	# A commit is write-once and generations are strictly sequential: while the last
	# fully validated commit still exists and its successor does not, it is still the
	# latest, with the same bytes and the same write-once Site files. Its validated
	# record is reused; the steps below rebuild marker and control exactly as before.
	var recorded: Dictionary = {}
	var scope := _faction_cache_context()
	var known: Dictionary = _recover_known_commit.get(folder, {})
	var commits_path := folder.path_join("commits")
	if not known.is_empty() and known.get("scope") == scope and FileAccess.file_exists(commits_path.path_join(str(known.name))) \
			and not FileAccess.file_exists(commits_path.path_join("%020d.json" % (int(known.generation) + 1))):
		# The live owner of this same generation equals the validated record: the full
		# path below would keep the live control (same generation) and the RAM marker
		# (equivalent record). Keep both without copying the record first.
		if preserve_live and live_generation == int(known.generation) and live_marker == known.recorded:
			_marker = live_marker
			control = live_control
			return {"ok": true}
		recorded = known.recorded.duplicate(true)
	else:
		# Only the file read can leave this placeholder (an empty folder); the known
		# commit path always replaces control below.
		control = {"logical_game_seconds": 0.0, "active_site_id": "", "fire_clock": _new_fire_clock(0.0)}
		var read := _recover_read_latest(preserve_live, live_control)
		if not read.ok: return read
		if read.get("empty", false): return {"ok": true}
		recorded = read.recorded
		_recover_known_commit[folder] = {"name": str(read.name), "generation": int(recorded.generation), "recorded": recorded.duplicate(true), "scope": scope}
	var clock: Dictionary = recorded.control
	_marker = recorded
	# The live control is kept exactly when it is ahead of, or of the same generation
	# as, the recorded one; only otherwise is the recorded clock copied in.
	if preserve_live and (float(live_control.logical_game_seconds) > float(clock.logical_game_seconds) or live_generation == int(recorded.generation)):
		control = live_control
	else:
		control = clock.duplicate(true)
		if not preserve_live and control.has("region_gameplay"):
			# A persisted activation records history, not a bind in this process.
			for value: Dictionary in control.region_gameplay.modes.values(): value.activation = {}
	# Marker ownership is independent of whether the live clock is ahead of disk.
	# Only a fully validated equivalent same-generation record retains RAM types.
	if preserve_live and live_generation == int(recorded.generation) and live_marker == recorded:
		_marker = live_marker
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

## The control a given commit recorded, decoded and checked as _recover_read_latest
## checks the latest one. Read-only: nothing here touches the live control.
func region_commit_control(generation: int) -> Dictionary:
	var document := _read_document(folder.path_join("commits").path_join("%020d.json" % generation))
	if not document.ok: return document
	var recorded: Dictionary = document.payload
	if not _whole(recorded.get("generation"), 1, 2147483647) or int(recorded.generation) != generation or not _same_pin(recorded.get("pin"), pin) \
			or not recorded.get("sites") is Dictionary or not recorded.get("control") is Dictionary:
		return fail("CORRUPT_SAVE", "存檔槽提交版本／來源／欄位")
	if not _whole(recorded.get("format"), 1, 2): return fail("SAVE_VERSION")
	var clock: Dictionary = recorded.control
	if clock.has("encoding") or clock.has("value"):
		if clock.size() != 2 or clock.get("encoding") != "godot_var_v1" or not clock.get("value") is String:
			return fail("CORRUPT_SAVE", "存檔槽 control 原 Variant 編碼欄位")
		var raw := Marshalls.base64_to_raw(str(clock.value))
		var decoded: Variant = bytes_to_var(raw)
		if raw.is_empty() or Marshalls.raw_to_base64(raw) != str(clock.value) or not decoded is Dictionary or var_to_bytes(decoded) != raw:
			return fail("CORRUPT_SAVE", "存檔槽 control 原 Variant 字節非法")
		clock = decoded
	if clock.has("region_gameplay"):
		var gameplay_check := GameplayClock.validate_registry(clock.region_gameplay, float(clock.get("logical_game_seconds", 0.0)))
		if not gameplay_check.ok: return gameplay_check
	var fields: Array = ["logical_game_seconds", "active_site_id"]
	for optional: String in ["fire_clock", "region_gameplay", "faction_registry", "person_allocator"]:
		if clock.has(optional): fields.append(optional)
	if not RegionFactionQuery.keys(clock, fields): return fail("CORRUPT_SAVE", "unknown control fields")
	if clock.has("person_allocator") and not person_allocator_valid(clock.person_allocator, str(pin.world_instance_id)): return fail("CORRUPT_PERSON_ALLOCATOR")
	if int(recorded.format) == 1 and clock.has("faction_registry") or int(recorded.format) == 2 and not clock.has("faction_registry"): return fail("SAVE_VERSION")
	if clock.has("faction_registry"):
		var factions: Variant = RegionFactionQuery.validate(clock.faction_registry, float(clock.get("logical_game_seconds", 0.0)))
		if not factions.ok: return factions
	return {"ok": true, "control": clock, "sites": recorded.sites}

func _publish(sites: Dictionary, clock: Dictionary, transfer_token: String = "", journey: Dictionary = {}) -> Dictionary:
	var expected := int(_marker.get("generation", 0))
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	if int(_marker.get("generation", 0)) != expected: return fail("CONFLICT", "存檔槽已有新提交，未發布舊候選")
	if not _person_pending.is_empty() and _person_generation != expected: return fail("PERSON_ALLOCATION_CONFLICT")
	if control.has("person_allocator") and not _person_upgrade_error.is_empty(): return _person_upgrade_error
	if float(clock.logical_game_seconds) < float(control.logical_game_seconds) - 0.00001:
		return fail("TIME_MISMATCH", "同一世界遊戲時鐘不可倒退")
	var next_clock := clock.duplicate(true)
	if not next_clock.has("faction_registry") and control.has("faction_registry"):
		next_clock.faction_registry = control.faction_registry.duplicate(true)
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
	var faction_scan: Dictionary = _faction_scan(sites, next_clock, journey, next_clock.get("faction_registry", {}), [], true, person_allocator_enabled() or control.has("person_allocator"))
	if not faction_scan.ok: return faction_scan
	next_clock.faction_registry = faction_scan.registry
	if person_allocator_enabled() or control.has("person_allocator"):
		var prior: Dictionary = _person_pending if person_allocator_enabled() else control.person_allocator
		var persons: Dictionary = person_migration(str(pin.world_instance_id), faction_scan.person_sources, prior)
		if not persons.ok: return persons
		next_clock["person_allocator"] = persons.allocator
	var record: Dictionary = {"format": 2, "generation": generation, "pin": pin.duplicate(true), "sites": sites.duplicate(true),
		"control": next_clock.duplicate(true), "transfer_token": transfer_token, "journey": journey.duplicate(true)}
	if initialization_pending() and expected == 0:
		var initial_guard := _check_initial_record(record)
		if not initial_guard.ok: return initial_guard
	# Keep the logical record in RAM; encode only its persisted control clock.
	var wire_record := record.duplicate(true)
	wire_record.control = {"encoding": "godot_var_v1", "value": Marshalls.raw_to_base64(var_to_bytes(next_clock))}
	var committed := _write_new_document(folder.path_join("commits/%020d.json" % generation), wire_record)
	if not committed.ok: return committed
	_marker = record
	control = next_clock
	if next_clock.has("person_allocator"):
		_person_pending = next_clock.person_allocator.duplicate(true)
		_person_generation = generation
		_person_allocation_owners.clear()
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
	# A completed bound original must keep its actual body/item capture owner.
	# A derived copy cannot stand in for that owner even at the same GAME time.
	# That owner is saved through its full owner graph (_save_checked ->
	# capture_region_checkpoint), exactly like the active Site, and the graph holds
	# its in-progress person jobs; the ordinary-save guard below applies only to a
	# body that is saved without that graph.
	var original := _region_bound_original_lab(data)
	if original != null and original.region_bind_receipt(data).get("complete") == true:
		var completed_original := validate_settlement(data.site, target_seconds)
		if not completed_original.ok: return completed_original
		if not completed_original.legacy and float(completed_original.pending) <= 0.00001:
			return {"ok": true, "data": data}
	var fire_guard := Store.fire_event_guard(data)
	if not fire_guard.ok: return fire_guard
	if data.site.is_empty(): return {"ok": true, "data": data}
	var detached := _detached_cold_copy(data, original)
	if not detached.ok: return detached
	var copy: TerrainData = detached.data
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
	# SHIPCROWD: a crowd Site's team travels as a whole crowd team (crowd_departure). Its passengers' boat fields live in the
	# crowd owner records, so the live owner converts the team first; the extraction then filters the native section.
	var crowd_spec := {}
	if origin.has("crowd"):
		if not ship_transfer_crowd_adapter.is_valid(): return fail("UNSUPPORTED", "群眾船隊旅程缺少原群眾 owner 轉換")
		var adapted: Variant = ship_transfer_crowd_adapter.call(origin, boat_ids)
		if not adapted is Dictionary or not adapted.get("ok") is bool: return fail("INVALID", "原群眾船隊轉換結果非法")
		if not adapted.ok: return adapted
		crowd_spec = {"crowd_departure": true, "crowd_control_successor": adapted.get("successor", {})}
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
	spec.merge(crowd_spec)
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
	var inserted: Dictionary = _insert_people(destination_data.site, extracted.party, navigation, anchor, destination_path,
		float(control.logical_game_seconds), float(control.logical_game_seconds),
		{"generation": int(_marker.get("generation", 0)) + 1, "family_transfer_guard": region_family_transfer_guard, "vehicle_poses": poses})
	if not inserted.ok: return inserted
	# Both candidates are NEW bodies. A region_snapshot inherited from the live or
	# visited Site authenticated the old body only; keep it out of the candidates,
	# as the private bind candidates do.
	extracted.origin.erase("region_snapshot")
	inserted.state.erase("region_snapshot")
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
	if source_data == null: return fail("INVALID", "Original source required")
	var boarding_guard: Dictionary = RegionTravel.boarding_travel_guard(source_data.site, boat_ids)
	if not boarding_guard.ok: return boarding_guard
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

func _ship_selected_source_guard(request: Dictionary) -> Dictionary:
	var from: Vector2i = Vector2i(int(request.from[0]), int(request.from[1]))
	var sites: Dictionary = _marker.get("sites", {})
	var site_key: String = _site_key(from)
	# A first checkpoint may publish this source for the first time.
	if not sites.has(site_key): return {"ok": true}
	var entry: Dictionary = sites[site_key]
	# This boundary checks only the departing selected Site, never the whole world.
	if not entry.get("path") is String or not _faction_digest_valid(str(entry.get("sha256", ""))):
		return fail("CORRUPT_SAVE", "原船旅程 selected Site 記錄非法")
	var path: String = folder.path_join(str(entry.path))
	if FileAccess.file_exists(path) and _faction_file_sha256(path) == str(entry.sha256): return {"ok": true}
	# A changed source cannot retain a known-commit or summary admission.
	_recover_known_commit.erase(folder)
	_faction_source_cache.clear()
	_faction_summary_digest_memo.clear()
	Store.invalidate_faction_summary_path(path)
	return fail("CORRUPT_SAVE", "原船旅程 selected Site 已遺失或 SHA 不符")

func ship_transfer_status(token: String = "") -> Dictionary:
	var previous_control: Dictionary = control
	var previous_marker: Dictionary = _marker
	var previous_scope: String = _control_scope
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	var journey: Dictionary = _marker.get("journey", {})
	if is_region_travel(journey): return {"ok": true, "pending": false} if token.is_empty() else fail("CONFLICT", "目前是陸路旅隊，不是船隊旅程")
	if token.is_empty():
		if not journey.is_empty(): token = str(journey.get("token", ""))
		elif _prepared.size() == 1: token = str(_prepared.keys()[0])
		else: return {"ok": true, "pending": false}
	var had_prepared: bool = _prepared.has(token)
	var requested := _request(token)
	if not requested.ok: return requested
	var selected: Dictionary = _ship_selected_source_guard(requested.request)
	if not selected.ok:
		control = previous_control
		_marker = previous_marker
		_control_scope = previous_scope
		if not had_prepared: _prepared.erase(token)
		return selected
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

func _reuse_ship_checkpoint_source(site: Vector2i, entry: Dictionary, captured: Dictionary) -> Dictionary:
	var selected_path: String = folder.path_join(str(entry.get("path", "")))
	if not str(entry.get("path", "")).begins_with("generations/") or not _faction_digest_valid(str(entry.get("sha256", ""))):
		return fail("CORRUPT_SAVE", "原 checkpoint source entry 非法")
	if FileAccess.get_sha256(selected_path) != str(entry.sha256): return fail("CONFLICT", "原 checkpoint source bytes 已變")
	var selected: Dictionary = _load_checked(selected_path, site)
	if not selected.ok: return selected
	# A Site file uses the SiteStore envelope (crowd_era, and zstd payload_encoding for a crowd section).
	var previous: Dictionary = Store._read(selected_path)
	if not previous.ok: return previous
	if FileAccess.get_sha256(selected_path) != str(entry.sha256): return fail("CONFLICT", "原 checkpoint source 在完整驗證中已變")
	if not captured.get("payload") is Dictionary or not previous.payload.get("state", {}).get("region_snapshot") is Dictionary:
		return {"ok": true, "reused": false}
	var candidate: Variant = JSON.parse_string(JSON.stringify(captured.payload, "", true, true))
	if not candidate is Dictionary: return fail("CORRUPT_SAVE", "原 checkpoint codec candidate 非法")
	var prior_context: Dictionary = previous.payload.state.region_snapshot.context
	var next_context: Dictionary = candidate.state.region_snapshot.context
	if int(prior_context.source_generation) > int(next_context.source_generation): return {"ok": true, "reused": false}
	# These two fields identify a capture attempt, never body/graph progress.
	for payload: Dictionary in [previous.payload, candidate]:
		var snapshot: Dictionary = payload.state.region_snapshot
		var owners: Variant = RegionCheckpoint.unwire(snapshot.owners)
		if not owners is Dictionary: return fail("INVALID_REGION_OWNERS")
		var snapshot_owner: GDScript = preload("res://scripts/terrain_lab/site_region_owner_snapshot.gd")
		var reference_shape: Callable = func(key: String, kind: int) -> bool:
			return not key.is_empty() and kind in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_DICTIONARY, TYPE_ARRAY]
		var graph: Dictionary = snapshot_owner.validate_for_bind(owners.get("scene"), reference_shape, snapshot.context)
		if not graph.ok: return graph
		var scene_context: Dictionary = owners.scene.context
		for field: String in ["source_generation", "token"]:
			if scene_context.get(field) != snapshot.context.get(field): return {"ok": true, "reused": false}
			scene_context.erase(field)
			snapshot.context.erase(field)
		snapshot.owners = RegionCheckpoint.wire(owners)
	if previous.payload != candidate: return {"ok": true, "reused": false}
	return {"ok": true, "reused": true, "path": selected_path, "data": selected.data}

func checkpoint_ship_transfer(token: String, source_data: TerrainData, elapsed_action_seconds: float = 0.0, phase: String = "outbound", return_elapsed_action_seconds: float = 0.0) -> Dictionary:
	var previous_control: Dictionary = control
	var previous_marker: Dictionary = _marker
	var previous_scope: String = _control_scope
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	var had_prepared: bool = _prepared.has(token)
	var requested := _request(token)
	if not requested.ok: return requested
	var selected: Dictionary = _ship_selected_source_guard(requested.request)
	if not selected.ok:
		control = previous_control
		_marker = previous_marker
		_control_scope = previous_scope
		if not had_prepared: _prepared.erase(token)
		return selected
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
	var entry: Dictionary = _marker.get("sites", {}).get(_site_key(from), {})
	var checked: Dictionary = _save_checked(source_data, from, path, entry)
	if not checked.ok: return checked
	var sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	sites[_site_key(from)] = entry.duplicate(true) if bool(checked.get("reused", false)) else _file_entry(str(checked.path))
	var clock := {"logical_game_seconds": float(control.logical_game_seconds), "active_site_id": str(source_data.site.id)}
	var published := _publish(sites, clock, str(_marker.get("transfer_token", "")), journey)
	return {"ok": true, "generation": published.generation, "path": checked.path, "elapsed_game_seconds": float(control.logical_game_seconds) - float(request.departure_game_seconds), "elapsed_action_seconds": elapsed_action_seconds} if published.ok else published

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

## SHIPCROWD: commit_ship_transfer's own checks up to and including the transfer pair, on copies only: nothing is saved
## or published. A crowd fleet runs it before the irreversible native release of its passengers; the live (unreleased) team is
## converted by ship_transfer_crowd_adapter exactly as the commit after the release reads it. PENDING means a cold replay
## of the destination is due first (as the commit would report).
func ship_transfer_commit_preflight(token: String, source_data: TerrainData) -> Dictionary:
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
	var boats: Array[String] = []
	for identity: Variant in request.boat_ids:
		if not identity is String: return fail("CORRUPT_SAVE", "旅程原船 ID 非法")
		boats.append(str(identity))
	var to_path := _generation_path(int(_marker.get("generation", 0)) + 1, to)
	var pair := _transfer_pair(source_data, destination.data, boats, Vector2i(int(request.anchor[0]), int(request.anchor[1])), Vector2i(int(request.facing[0]), int(request.facing[1])), to_path, str(request.token))
	return {"ok": true} if pair.ok else pair

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

func _collect_cold_checkpoint(generation: int, sites: Dictionary, next_control: Dictionary, read_only: bool = false) -> Dictionary:
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
		if read_only and _region_bound_original_lab(candidate.data) != null:
			var aligned: Dictionary = validate_settlement(candidate["data"].site, float(control["logical_game_seconds"]))
			if not aligned.ok or bool(aligned.get("legacy", true)) or float(aligned.get("pending", 1.0)) > 0.00000001:
				return fail("UNSETTLED_SITE", "先循原共同步進完成冷 owner；交接不推進時間")
		var settled := _settle_cold_candidate(candidate.data, float(control.logical_game_seconds))
		if not settled.ok: return settled
		# Retain even a subsequently failed checkpoint's completed original result.
		candidate.data = settled.data
		_fire_cold_candidates[identity] = candidate
		var coordinate: Vector2i = candidate.coordinate
		var path := _generation_path(generation, coordinate)
		var saved: Dictionary = _save_checked_owner_capture(candidate.data, coordinate, path, {}, true) if read_only else _save_checked(candidate.data, coordinate, path)
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

## Read-only view for optional callers. A source-less slot without an admitted
## region_gameplay schema must not acquire one as a side effect (item 20).
func region_registry_view() -> Dictionary:
	if source == null and not control.has("region_gameplay"): return {}
	return region_registry()

## The first admitted endpoint is a typed immutable capsule, not a renewed observation.
func _region_decode_accepted_siege_contact(event: Dictionary) -> Dictionary:
	var checked: Dictionary = GameplayClock.validate_event(event)
	if not checked.ok or event.get("kind") != "player_encounter" or event.get("player") != true: return fail("INVALID_ACCEPTED_SIEGE_CONTACT")
	var payload: Dictionary = event.get("payload", {})
	var encoded: Variant = payload.get("accepted_siege_contact")
	if not encoded is String or encoded.is_empty() or encoded.length() > 131072: return fail("INVALID_ACCEPTED_SIEGE_CONTACT")
	var origin: Variant = bytes_to_var(Marshalls.base64_to_raw(encoded))
	if not origin is Dictionary or origin.get("version") != 1 or not origin.get("payload") is Dictionary or not origin.get("pin") is Dictionary: return fail("INVALID_ACCEPTED_SIEGE_CONTACT")
	for field: String in ["id", "kind", "at", "owner", "player"]:
		if var_to_bytes(origin.get(field)) != var_to_bytes(event.get(field)): return fail("REGION_EVENT_CONFLICT")
	var content: Dictionary = payload.duplicate(true)
	content.erase("accepted_siege_contact")
	if RegionBattle._siege_hash(content) != RegionBattle._siege_hash(origin.payload): return fail("REGION_EVENT_CONFLICT")
	var contact: Dictionary = content.get("contact_receipt", {})
	var witness: Dictionary = contact.get("witness", {})
	if contact.get("kind") != "siege_channel" or contact.get("at") != event.at or contact.get("first", {}).get("at") != event.at or contact.get("second", {}).get("at") != event.at \
		or witness.get("battle_id") != content.get("battle_id") or witness.get("party_token") != content.get("player_token") \
		or not witness.get("party_source") is Dictionary: return fail("INVALID_ACCEPTED_SIEGE_CONTACT")
	return {"ok": true, "origin": origin, "payload": content, "witness": witness}

func _region_accepted_siege_lineage(event: Dictionary, status: Dictionary, party: Dictionary, actual_proof: Dictionary) -> Dictionary:
	var decoded: Dictionary = _region_decode_accepted_siege_contact(event)
	if not decoded.ok: return decoded
	var origin: Dictionary = decoded.origin
	var token: String = str(decoded.payload.player_token)
	var proof: Dictionary = decoded.witness.party_source
	var journey: Dictionary = status.get("journey", {})
	if not _same_pin(origin.pin, pin) or status.get("token") != token or party.get("party_id") != token \
		or origin.get("plan_path") != journey.get("plan_path") or origin.get("plan_sha256") != journey.get("plan_sha256") \
		or str(origin.get("plan_path", "")).is_empty(): return fail("ACCEPTED_SIEGE_ROUTE_CHANGED")
	for field: String in ["token", "owner", "controller", "phase"]:
		if proof.get(field) != actual_proof.get(field): return fail("ACCEPTED_SIEGE_SOURCE_CHANGED")
	if proof.get("token") != token or proof.get("owner") != "travel:" + token or proof.get("controller") != "player" \
		or decoded.witness.get("source_generation") != proof.get("generation") or decoded.witness.get("runtime_revision") != proof.get("revision") \
		or decoded.witness.get("game_seconds") != proof.get("game_seconds") or decoded.witness.get("action_seconds") != proof.get("action_seconds"): return fail("ACCEPTED_SIEGE_SOURCE_CHANGED")
	for field: String in ["generation", "revision", "game_seconds", "action_seconds"]:
		if not proof.get(field) is int and not proof.get(field) is float: return fail("ACCEPTED_SIEGE_SOURCE_CHANGED")
		if not actual_proof.get(field) is int and not actual_proof.get(field) is float: return fail("ACCEPTED_SIEGE_SOURCE_CHANGED")
		if proof[field] > actual_proof[field]: return fail("ACCEPTED_SIEGE_SOURCE_CHANGED")
	var historical: Dictionary = _region_life_party_document(token, str(proof.get("path", "")), str(proof.get("sha256", "")))
	if not historical.ok: return historical
	var reference: Dictionary = party.content.get("travel_identity", {}).get("refs", {}).get("person", {}).get(str(int(party.leader_person_id)), {})
	if reference.is_empty() or reference != origin.get("leader_reference") or historical.party.get("controller") != "player" \
		or _region_life_reference_id(historical.party.content.travel_identity, reference) < 0: return fail("ACCEPTED_SIEGE_SOURCE_CHANGED")
	return {"ok": true, "origin": origin}

func _region_stamp_siege_contact(identity: String, at: float, owner: String, payload: Dictionary) -> Dictionary:
	var token: String = str(payload.get("player_token", ""))
	var status: Dictionary = region_travel_status()
	var selected: Dictionary = region_travel_party()
	if not status.ok or not selected.ok or not status.get("pending", false) or status.get("token") != token: return fail("INVALID_ORIGINAL_PARTY_PROOF")
	var actual: Dictionary = region_original_party_runtime_proof(token, selected.party)
	if not actual.ok: return actual
	var contact: Dictionary = payload.get("contact_receipt", {})
	var witness: Dictionary = contact.get("witness", {})
	if identity != "siege:%s:player:%s:%.9f" % [str(payload.get("battle_id", "")), token, at] or contact.get("at") != at \
		or contact.get("first", {}).get("at") != at or contact.get("second", {}).get("at") != at or witness.get("legal_ground_melee") != true \
		or contact.get("first", {}).get("position", {}).get("site") != payload.get("site") or contact.get("second", {}).get("position", {}).get("site") != payload.get("site") \
		or contact.get("first", {}).get("position", {}).get("cell") != witness.get("person_cell") or contact.get("second", {}).get("position", {}).get("cell") != witness.get("entry"):
		return fail("INVALID_SIEGE_CONTACT")

	if witness.get("party_token") != token or witness.get("battle_id") != payload.get("battle_id") \
		or RegionBattle._siege_hash(witness.get("party_source", {})) != RegionBattle._siege_hash(actual.proof) \
		or witness.get("source_generation") != int(_marker.generation) or witness.get("runtime_revision") != int(region_registry().revision) \
		or witness.get("game_seconds") != float(control.logical_game_seconds) or witness.get("action_seconds") != float(control.fire_clock.action_seconds): return fail("INVALID_ORIGINAL_PARTY_PROOF")
	var battle: Dictionary = region_registry().battles.get(str(payload.get("battle_id", "")), {})
	var original: TerrainLab = _region_original_labs.get(owner)
	if battle.get("kind") != "siege" or battle.get("phase") == "finished" or battle.get("site_id") != owner or not is_instance_valid(original) or _region_bound_original_lab(original.terrain) != original: return fail("COMMITTED_UNBOUND")
	var person: Dictionary = original.site_controller.person_actions._person(int(witness.get("person_id", -1)), false)
	var traveller: Dictionary = actual.lab.site_controller.person_actions._person(int(selected.party.leader_person_id), false)
	if person.is_empty() or traveller.is_empty() or int(person.faction) == int(traveller.faction) or not SiteSettlement._fit(person) or bool(person.moving) \
		or not (battle.attackers + battle.defenders).has(int(witness.get("person_id", -1))) or SiteSettlement._role(person) == "civilian" \
		or original.site_controller.vehicles.is_siege_crew(int(witness.get("person_id", -1))): return fail("INVALID_SIEGE_CONTACT")
	if witness.get("person_cell") != [person.cell.x, person.cell.y] or not witness.get("entry") is Array or witness.entry.size() != 2 \
		or witness.get("navigation_revision") != int(original.terrain.navigation_revision): return fail("INVALID_SIEGE_CONTACT")
	var entry: Vector2i = Vector2i(int(witness.entry[0]), int(witness.entry[1]))
	var route_index: Variant = contact.get("second", {}).get("position", {}).get("step_index")
	if not GameplayClock.whole(route_index, 0) or int(route_index) >= status.plan.get("steps", []).size(): return fail("INVALID_SIEGE_CONTACT")
	var step: Dictionary = status.plan.steps[int(route_index)]
	if payload.get("site") != step.get("site") or Grid.site_id(str(pin.atlas_id), Vector2i(int(step.site[0]), int(step.site[1]))) != owner: return fail("INVALID_SIEGE_CONTACT")
	var route_entry: Vector2i = RegionRoute.entry_cell(step)
	if route_entry.x < 0 and owner == str(selected.party.get("origin_site_id", "")):
		var body: Dictionary = RegionTravel._body_records(selected.party.content).get(int(selected.party.leader_person_id), {})
		if body.get("cell") is Array and body.cell.size() == 2: route_entry = Vector2i(int(body.cell[0]), int(body.cell[1]))
	if route_entry != entry: return fail("INVALID_SIEGE_CONTACT")
	var gap: Vector2i = entry - Vector2i(person.cell)
	var ready: bool = person.owner.exchange_ready(int(person.unit)) if person.owner is TerrainArmy else person.owner.exchange_ready()
	if not ready or absi(gap.x) + absi(gap.y) != 1 or not original.terrain.can_attack_across(person.cell, entry) \
		or original.site_controller.vehicles.blocks_person_step(int(witness.person_id), person.cell, person.cell, entry, entry): return fail("INVALID_SIEGE_CONTACT")
	var reference: Dictionary = selected.party.content.travel_identity.refs.person.get(str(int(selected.party.leader_person_id)), {})
	if reference.is_empty(): return fail("INVALID_ORIGINAL_PARTY_PROOF")
	var origin: Dictionary = {"version": 1, "id": identity, "kind": "player_encounter", "at": at, "owner": owner, "player": true,
		"payload": payload.duplicate(true), "pin": pin.duplicate(true), "plan_path": str(status.journey.plan_path), "plan_sha256": str(status.journey.plan_sha256),
		"leader_reference": reference.duplicate(true), "basis": {"world": float(control.logical_game_seconds), "action": float(control.fire_clock.action_seconds), "distance": selected.party.upkeep.get("distance", 0.0), "route_node": selected.party.upkeep.get("route_node", {}).duplicate(true), "accepted_at": at}}
	var stamped: Dictionary = payload.duplicate(true)
	stamped["accepted_siege_contact"] = Marshalls.raw_to_base64(var_to_bytes(origin))
	return {"ok": true, "payload": stamped}

func queue_region_event(identity: String, kind: String, at: float, owner: String, payload: Dictionary = {}, player: bool = false) -> Dictionary:
	if at < float(control.logical_game_seconds) - 0.00000001: return fail("REGION_EVENT", "新事件不能倒填已完成區間")
	if kind == "player_encounter" and player and payload.get("contact_receipt", {}).get("kind") == "siege_channel" and payload.has("player_token"):
		var prior: Dictionary = {}
		for event: Dictionary in region_registry().events:
			if event.id == identity: prior = event; break
		if payload.has("accepted_siege_contact"):
			if prior.is_empty(): return fail("UNADMITTED_PLAYER_CONTACT")
			var decoded: Dictionary = _region_decode_accepted_siege_contact(prior)
			if not decoded.ok: return decoded
		elif prior.is_empty():
			var stamped: Dictionary = _region_stamp_siege_contact(identity, at, owner, payload)
			if not stamped.ok: return stamped
			payload = stamped.payload
	return GameplayClock.queue_event(region_registry(), identity, kind, at, owner, payload, player)

func pending_region_events() -> Array[Dictionary]:
	if source == null and not control.has("region_gameplay"): return []
	return GameplayClock.pending_at(region_registry(), float(control.logical_game_seconds))

func complete_region_event(identity: String) -> Dictionary:
	return GameplayClock.complete_event(region_registry(), identity, float(control.logical_game_seconds))

func region_player_barrier() -> Dictionary:
	if source == null and not control.has("region_gameplay"): return {}
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
	# The activation mode is the one the original owner really bound in. A restore-only
	# (cold) owner's receipt is cold_exact / original_replay and stays so until the
	# world-open live bind; only a live receipt may activate as live / original_site.
	var bound_mode: String = str(receipt.get("mode", ""))
	var bound_consumer: String = str(receipt.get("consumer", ""))
	var legal_pair: bool = (bound_mode == "live" and bound_consumer == "original_site") or (bound_mode == "cold_exact" and bound_consumer == "original_replay")
	if not legal_pair: return fail("REGION_BIND", "原 owner 綁定模式與 consumer 不合")
	var activation := receipt.duplicate(true)
	activation.generation = int(_marker.get("generation", 0))
	var enabled := activate_region_mode(str(data.site.id), bound_mode, bound_consumer, activation, str(receipt.get("backend", "gd")))
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

func prepare_region_route_context(active_data: TerrainData = null, party: Dictionary = {}, route_sites: Array[Vector2i] = []) -> Dictionary:
	return _prepare_region_route_context(active_data, party, route_sites, true)

## Uncached twin: identical inputs and output, always fresh detached copies.
func prepare_region_route_context_uncached(active_data: TerrainData = null, party: Dictionary = {}, route_sites: Array[Vector2i] = []) -> Dictionary:
	return _prepare_region_route_context(active_data, party, route_sites, false)

## Performance proposal B. A detached navigation snapshot depends only on its
## source body. Live sources (active data, bound cold Lab, fire candidate) are
## keyed by instance and navigation_revision; file sources by marker path and
## SHA-256. A changed key misses and rebuilds; nothing else is cached. Cached
## snapshots are shared read-only by route consumers, exactly like the fresh
## ones they replace. clear_route_context_cache() empties it.
const ROUTE_CONTEXT_CACHE_LIMIT := 32
var _route_context_cache: Dictionary = {} # source key -> detached TerrainData
var _route_context_cache_order: Array[String] = []
var _route_context_file_navigation: Dictionary = {} # file key -> source navigation_revision

## Site fields that move every step and never reach a route snapshot's navigation:
## Env.navigation_for_state and RegionRoute read none of them (only ecology_info
## reads minute/phase). Measured on carried blocked (4,800 calls): phase,
## fire_settlement and simulation_settlement changed on 4,799, minute on 40.
const ROUTE_CONTEXT_CLOCK_FIELDS := ["phase", "minute", "fire_settlement", "simulation_settlement"]

static func _live_route_key(original: TerrainData) -> String:
	var site: Dictionary = original.site.duplicate()
	for field: String in ROUTE_CONTEXT_CLOCK_FIELDS: site.erase(field)
	return "live|%d|%d|%d|%d|%d" % [original.get_instance_id(), original.navigation_revision, hash(site), hash(original.parameters), hash(original.resource_base)]

func clear_route_context_cache() -> void:
	for cached: TerrainData in _route_context_cache.values(): RegionRoute.unregister_readonly_body(cached)
	_route_context_cache.clear()
	_route_context_cache_order.clear()
	_route_context_file_navigation.clear()

func _route_context_detached(original: TerrainData, cache_key: String, use_cache: bool) -> TerrainData:
	if use_cache and _route_context_cache.has(cache_key): return _route_context_cache[cache_key]
	var detached := Env.navigation_for_state(original, original.site.duplicate(true))
	detached.parameters = original.parameters.duplicate(true)
	detached.resource_base = original.resource_base.duplicate(true)
	for meta: StringName in detached.get_meta_list(): detached.remove_meta(meta)
	if use_cache:
		_route_context_cache[cache_key] = detached
		RegionRoute.register_readonly_body(detached, "%d|%s" % [get_instance_id(), cache_key])
		_route_context_cache_order.append(cache_key)
		while _route_context_cache_order.size() > ROUTE_CONTEXT_CACHE_LIMIT:
			var evicted: String = _route_context_cache_order.pop_front()
			RegionRoute.unregister_readonly_body(_route_context_cache.get(evicted))
			_route_context_cache.erase(evicted)
			_route_context_file_navigation.erase(evicted)
	return detached

func _prepare_region_route_context(active_data: TerrainData, party: Dictionary, route_sites: Array[Vector2i], use_cache: bool) -> Dictionary:
	if source == null or pin.is_empty(): return fail("INVALID_SLOT", "原路線來源尚未開啟")
	if not Thread.is_main_thread(): return fail("REGION_ROUTE_THREAD", "原導航快照須在主執行緒準備")
	var snapshots := {}
	var revision := str(_marker.get("generation", 0)) + ":" + str(region_registry().revision)
	for key: String in _marker.get("sites", {}):
		var pair := key.split(":")
		if pair.size() != 2: return fail("SAVE_VERSION", "原 Site 索引非法")
		var coordinate := Vector2i(int(pair[0]), int(pair[1]))
		if not route_sites.is_empty() and coordinate not in route_sites: continue
		var original: TerrainData
		var cache_key := ""
		var file_navigation_revision := -1
		if active_data != null and _coordinate(active_data).get("site") == coordinate:
			original = active_data
		else:
			var identity := Grid.site_id(str(pin.atlas_id), coordinate)
			var actual: TerrainLab = _region_original_labs.get(identity)
			if is_instance_valid(actual):
				if actual.site_controller == null or actual.site_controller.region_slot != self \
						or actual.terrain == null or actual._region_bound_data != actual.terrain \
						or str(actual.terrain.site.id) != identity or not actual.region_bind_receipt(actual.terrain).get("complete", false):
					return fail("COMMITTED_UNBOUND", "原路線的當前 cold Lab 尚未完整綁定")
				original = actual.terrain
			elif _fire_cold_candidates.has(identity):
				original = _fire_cold_candidates[identity].data
			else:
				var entry: Dictionary = _marker.get("sites", {}).get(key, {})
				cache_key = "file|%s|%s" % [str(entry.get("path", "")), str(entry.get("sha256", ""))]
				if use_cache and _route_context_cache.has(cache_key) and not str(entry.get("sha256", "")).is_empty():
					file_navigation_revision = int(_route_context_file_navigation.get(cache_key, -1))
				if file_navigation_revision < 0:
					var loaded := _load_checked(site_path(coordinate), coordinate)
					if not loaded.ok: return loaded
					original = loaded.data
		if original != null:
			if cache_key.is_empty(): cache_key = _live_route_key(original)
			var detached := _route_context_detached(original, cache_key, use_cache)
			if use_cache and cache_key.begins_with("file|"): _route_context_file_navigation[cache_key] = original.navigation_revision
			snapshots[coordinate] = detached
			revision += ":" + key + ":" + str(original.navigation_revision)
		else:
			snapshots[coordinate] = _route_context_cache[cache_key]
			revision += ":" + key + ":" + str(file_navigation_revision)
	if active_data != null:
		var coordinate := _coordinate(active_data)
		if not coordinate.ok: return coordinate
		snapshots[coordinate.site] = _route_context_detached(active_data, _live_route_key(active_data), use_cache)
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
	var node: Dictionary = party.get("upkeep", {}).get("route_node", {})
	if str(party.get("upkeep", {}).get("live", {}).get("upkeep", "")) == "mapBody": node = _region_map_route_reference(party)
	var poses: Dictionary = node.get("vehicle_poses", {})
	var start: Variant = Vector2i(int(node.cell[0]), int(node.cell[1])) if node.get("cell") is Array and node.cell.size() == 2 else null
	return {"projection_mode": "slot_current", "effective_terrain": provider, "capabilities": {"mode": "sea" if kinds.has("ship") else "land",
		"vehicle_kinds": kinds, "vehicles": vehicles, "vehicle_poses": poses.duplicate(true), "start_cell": start}, "party": party.duplicate(true), "revision": revision}

func effective_site_path(site: Vector2i) -> Dictionary:
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	var path := site_path(site)
	return {"ok": true, "path": path if FileAccess.file_exists(path) else ""}

# Read only the original slot's committed/legacy paths. No Site is opened.
# P5C-S4: visited means entered and committed, not merely configured or materialised.
# The birth start is visited. Any other Site is visited only when its marker entry was written by a
# generation after the birth (an arrival or later commit writes a new generation for it). A Site that
# only the birth wrote (generation 1) is configured: present in the marker, never entered.
func is_visited(site: Vector2i) -> bool:
	var entry: Variant = _marker.get("sites", {}).get(_site_key(site))
	if not entry is Dictionary: return FileAccess.file_exists(folder.path_join("sites").path_join(str(site.x)).path_join(str(site.y) + ".json"))
	var start: Vector2i = _birth_start_site()
	if start == site: return true
	return _entry_generation(entry) > 1


func _birth_start_site() -> Vector2i:
	var record: Dictionary = _read_document(folder.path_join("manifest.initialized.json"), 16384)
	if not record.get("ok", false): return Vector2i(-2147483647, -2147483647)
	var start: Variant = record.payload.get("starting_site")
	if not start is Array or start.size() != 2: return Vector2i(-2147483647, -2147483647)
	return Vector2i(int(start[0]), int(start[1]))


static func _entry_generation(entry: Dictionary) -> int:
	var file_name: String = str(entry.get("path", "")).get_file()
	return int(file_name.get_slice("_", 0)) if file_name.get_slice("_", 0).is_valid_int() else 0


func known_saved_sites() -> Dictionary:
	if pin.is_empty() or source == null: return fail("INVALID_SLOT", "尚未開啟原地圖存檔")
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	return _known_saved_sites_current()

func _known_saved_sites_current() -> Dictionary:
	if pin.is_empty() or source == null: return fail("INVALID_SLOT", "尚未開啟原地圖存檔")
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
	# A watermark read back from the saved JSON can exceed the in-memory world
	# clock by its last ulp; within the fire-clock journal tolerance it is that clock.
	if last > float(logical_game_seconds) + maxf(0.00000001, float(logical_game_seconds) * 0.000000001):
		return _fail("SAVE_VERSION", "Site 結算時間超前於原世界存檔")
	last = minf(last, float(logical_game_seconds))
	# The same holds below the clock: a watermark recorded AT the world clock and
	# read back from the Site's saved JSON is exactly that clock's JSON read-back.
	if last < float(logical_game_seconds):
		var read_back: Variant = JSON.parse_string(JSON.stringify(float(logical_game_seconds), "", false, true))
		if (read_back is float or read_back is int) and float(read_back) == last: last = float(logical_game_seconds)
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
	result.visited = bool(slot.call("is_visited", site))
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
	var fresh := data.site.is_empty()
	if fresh:
		if data.spawn_cell == Vector2i(-1, -1): return fail("NO_TARGET", "地面跨界目的地沒有原落腳點")
		# This is an actual visit candidate, never the pure boundary query.
		Env.initialize(data, str(data.parameters.fixed_base.site_id))
		data.site.actor_presence_version = 1
		data.site.actors = {}
		data.site.worker_enabled = false
		var retired := Store.retire_default_worker(data)
		if not retired.ok: return retired
		Runtime.initialize_item_storage(data.site)
		# Same as open_site: a new Site of this slot carries the slot's fixed world pin.
		if not pin.is_empty(): data.site.world_pin = pin.duplicate(true)
	var settled := _settle_cold_candidate(data, seconds)
	# Same as open_site: a new Site starts its Fire settlement at this slot's
	# current dual clock, so a later owner restores the true action cursor.
	# That holds before the slot's first marker too (a single-Site slot that has
	# not published yet): the arriving owner's next original shared step requires
	# this watermark (TerrainLab._region_original_interval_guard). Only a slot
	# that has no dual clock at all has nothing to stamp from.
	if fresh and settled.ok and not control.get("fire_clock", {}).is_empty() and settled.data.site.get("fire_settlement", {}).is_empty() and _fire_history_empty(settled.data.site):
		settled.data.site.fire_settlement = {"version": 1, "epoch": str(control.fire_clock.epoch), "sequence": int(control.fire_clock.sequence),
			"action_seconds": float(control.fire_clock.action_seconds), "game_seconds": float(control.logical_game_seconds)}
	if settled.ok: attach_person_allocator(settled.data)
	return settled

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
	var inserted: Dictionary = _insert_people(destination_data.site, extracted.party, nav, request.to_cell, destination_path,
		float(control.logical_game_seconds), float(control.logical_game_seconds),
		{"generation": int(_marker.get("generation", 0)) + 1, "family_transfer_guard": region_family_transfer_guard})
	if not inserted.ok: return inserted
	if inserted.leader_cell != request.to_cell: return fail("OCCUPIED", "原細格reservation不允改落其他格")
	# Both candidates are NEW bodies. A region_snapshot inherited from the live or
	# visited Site authenticated the old body only; keep it out of the candidates,
	# as the private bind candidates do.
	extracted.origin.erase("region_snapshot")
	inserted.state.erase("region_snapshot")
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
	if not _whole(value.get("base_sequence", 0), 0, int(value.sequence)) or not _seconds(value.get("base_action_seconds", 0.0)):
		return _fail("CORRUPT_FIRE_CLOCK", "火攻歷程基點型別非法")
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
	# A Site watermark read back from its saved JSON can differ from the in-memory
	# clock in the last ulp; index rows use the same tolerance as the journal rows.
	for identity: Variant in value.index:
		var row: Variant = value.index[identity]
		if not identity is String or identity.is_empty() or not row is Dictionary or row.size() not in [5, 6] \
			or not row.get("coordinate") is Array or row.coordinate.size() != 2 \
			or not _whole(row.coordinate[0], -10000000, 10000000) or not _whole(row.coordinate[1], -10000000, 10000000) \
			or not row.get("active") is bool or not _whole(row.get("sequence"), base_sequence, previous_sequence) \
			or row.size() == 6 and not row.get("fire_active") is bool \
			or not _seconds(row.get("action_seconds")) or not _seconds(row.get("game_seconds")) \
			or float(row.action_seconds) > previous_action + maxf(0.00000001, previous_action * 0.000000001) \
			or float(row.game_seconds) > previous_game + maxf(0.00000001, previous_game * 0.000000001):
			return _fail("CORRUPT_FIRE_INDEX", "原 Site 活動索引非法")
	return {"ok": true}

## The Site watermark is written AT the fire clock and read back from the Site's
## saved JSON, which is not last-ulp exact; the clock itself is restored exactly.
## A watermark that is exactly that clock's JSON read-back is that clock, not ahead.
static func _fire_watermark_after_clock(watermark: Variant, clock_action: Variant) -> bool:
	if float(watermark) <= float(clock_action): return false
	var read_back: Variant = JSON.parse_string(JSON.stringify(float(clock_action), "", false, true))
	return not ((read_back is float or read_back is int) and float(read_back) == float(watermark))

static func validate_fire_settlement(state: Dictionary, clock: Dictionary) -> Dictionary:
	var value: Variant = state.get("fire_settlement")
	if not value is Dictionary or value.size() != FIRE_SETTLEMENT_FIELDS.size(): return _fail("MISSING_FIRE_HISTORY", "火攻地點缺少雙時間水印")
	for field: String in FIRE_SETTLEMENT_FIELDS:
		if not value.has(field): return _fail("CORRUPT_FIRE_SETTLEMENT", "火攻結算欄位")
	# Validate the original clock before any typed journal iteration or key read.
	var clock_game: Variant = clock.get("base_game_seconds")
	var journal: Variant = clock.get("journal")
	if journal is Array and not journal.is_empty():
		var last: Variant = journal.back()
		if last is Dictionary: clock_game = last.get("game_end")
	var clock_check: Dictionary = validate_fire_clock(clock, clock_game)
	if not clock_check.ok: return clock_check
	if not _whole(value.version, 1, 1) or value.epoch != clock.epoch \
		or not _whole(value.sequence, 0, int(clock.sequence)) or not _seconds(value.action_seconds) or not _seconds(value.game_seconds) \
		or _fire_watermark_after_clock(value.action_seconds, clock.action_seconds): return _fail("CORRUPT_FIRE_SETTLEMENT", "火攻結算版本或端點")
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
		if uniform and float(last.scale) == float(interval.scale) and _fire_row_width(last, interval) > 0.0:
			last.last_sequence = int(interval.sequence)
			last.action_end = float(interval.action_end)
			last.game_end = float(interval.game_end)
			last.tactical_seconds = float(last.tactical_seconds) + float(interval.tactical_seconds)
			last.steps = int(last.steps) + 1
		else: journal.append(row)
	else: journal.append(row)
	clock.action_seconds = float(interval.action_end)
	clock.sequence = int(interval.sequence)

## The single live step width that extends this journal row bit-exactly, or 0.
## A row holds only steps of one live width w (ACTION_STEP or EXCHANGE_ACTION_STEP)
## whose ends are each the previous end + w, so a replay rebuilds every boundary
## from the row's begin. A one-step row is checked directly; a longer row was
## built under this rule, so its average already names its w.
static func _fire_row_width(last: Dictionary, interval: Dictionary) -> float:
	var steps := int(last.steps)
	for width: float in [TerrainLab.EXCHANGE_ACTION_STEP, TerrainLab.ACTION_STEP]:
		if float(last.action_end) + width != float(interval.action_end): continue
		if steps == 1 and float(last.action_begin) + width != float(last.action_end): continue
		if steps > 1 and absf((float(last.action_end) - float(last.action_begin)) / steps - width) >= 0.0000000001: continue
		return width
	return 0.0

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
# token -> {path, sha256, payload}: the latest selected party document as read and
# verified once. Party documents are write-once, so the same selected path and
# SHA-256 name the same bytes; a new checkpoint selects a new path and replaces it.
var _region_selected_document_cache: Dictionary = {}
# token -> {path, sha256, controller, party, fingerprint, graph}: the decoded and
# fully validated selected document. Pure in its bytes, token, controller and pin.
var _region_selected_decoded_cache: Dictionary = {}
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
		var idle_node: Dictionary = upkeep.get("route_node", {})
		status.vehicle_poses = idle_node.get("vehicle_poses", {}).duplicate(true)
		if idle_node.get("cell") is Array and idle_node.cell.size() == 2: status.route_node_cell = Vector2i(int(idle_node.cell[0]), int(idle_node.cell[1]))
		if status.barrier:
			status.destination = status.site
			status.arrived = true
		return _region_map_status_position(party, region_mode_stop_status(party, status))
	if str(plan.get("mode", "land")) == "sea":
		status.destination = Vector2i(int(plan.steps.back().site[0]), int(plan.steps.back().site[1]))
		var sea := region_sea_travel_status(plan, party, status)
		if not sea.ok: return sea
		if sea.barrier:
			sea.destination = sea.site
			sea.arrived = true
			sea.moving = false
		return region_mode_stop_status(party, sea)
	plan = _region_land_physical_plan(plan)
	status.plan = plan
	var distance := _region_land_physical_distance(plan, upkeep, str(journey.plan_path))
	if upkeep.is_empty(): distance = minf(float(plan.metres), maxf(0.0, now - float(journey.plan_started_game_seconds)) * float(plan.speed_mps))
	var route_blocked: Dictionary = upkeep.get("route_blocked", {})
	var node: Dictionary = upkeep.get("route_node", {})
	if str(node.get("plan_id", "")) == str(journey.plan_path):
		status.vehicle_poses = node.get("vehicle_poses", {}).duplicate(true)
		status.route_node_cell = Vector2i(int(node.cell[0]), int(node.cell[1]))
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
		return _region_map_status_position(party, region_mode_stop_status(party, status))
	status.arrived = status.remaining_metres <= 0.0000001
	if str(route_blocked.get("plan_id", "")) == str(journey.plan_path) and not route_blocked.is_empty():
		status.site = Vector2i(int(node.site[0]), int(node.site[1]))
		status.component = int(node.component)
		status.step_index = int(node.index)
		status.fraction = 1.0
		status.arrived = false
		status.route_blocked = route_blocked.duplicate(true)
	if not status.has("vehicle_poses"):
		status.vehicle_poses = plan.steps[int(status.step_index)].get("vehicle_poses", {}).duplicate(true)
	if str(node.get("plan_id", "")) == str(journey.plan_path) and node.get("site") == [status.site.x, status.site.y]:
		status.component = int(node.component)
	status.moving = not status.arrived
	return _region_map_status_position(party, region_mode_stop_status(party, status))

func _boarding_current_party_guard() -> Dictionary:
	if region_travel_journey().is_empty(): return {"ok": true}
	var original: Dictionary = region_travel_party()
	if not original.ok: return original
	return RegionTravel.boarding_travel_guard(original.party.content)

## G6.4b: every refusal begin_region_travel can decide before it extracts, in the same order. It mutates nothing
## but the control recovery that begin_region_travel also runs first. Crowd departure calls it before any native release.
func region_travel_preflight(source_data: TerrainData, spec: Dictionary, start_component: int) -> Dictionary:
	if source_data == null: return fail("INVALID", "Original source required")
	var boarding_guard: Dictionary = RegionTravel.boarding_departure_guard(source_data.site, spec)
	if not boarding_guard.ok: return boarding_guard
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
	var fire_probe := _capture_transfer_fire_snapshots(source_data, source_data.site.duplicate(true))
	if not fire_probe.ok: return fire_probe
	return {"ok": true, "from": from}

func begin_region_travel(source_data: TerrainData, spec: Dictionary, start_component: int) -> Dictionary:
	var pre := region_travel_preflight(source_data, spec, start_component)
	if not pre.ok: return pre
	var from: Vector2i = pre.from
	var token := "travel_" + Crypto.new().generate_random_bytes(16).hex_encode()
	var captured := source_data.site.duplicate(true)
	var fire_capture := _capture_transfer_fire_snapshots(source_data, captured)
	if not fire_capture.ok: return fire_capture
	var extraction_spec := spec.duplicate(true)
	extraction_spec.game_seconds = float(control.logical_game_seconds)
	var extracted := RegionTravel.extract(captured, extraction_spec, token)
	if not extracted.ok: return extracted
	# Original departure records the already accepted shared ACTION point.
	extracted.party.upkeep.owner_action_seconds = float(control.fire_clock.action_seconds)
	# Ordinary original departure already refused unfinished death transfers.
	extracted.party.upkeep.original_deaths = {}
	# The origin candidate is a NEW body: a region_snapshot inherited from the
	# live Site (e.g. its arrival bind) authenticated the old body only.
	extracted.origin.erase("region_snapshot")
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
		var endpoint: Dictionary = _region_departure_fire_endpoint(checked.data.site.fire_settlement, fire_clock)
		if not endpoint["ok"]: return endpoint
		var settlement: Dictionary = endpoint["watermark"]
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
	# The map handoff must select every current complete original, not old cold files.
	var cold: Dictionary = _collect_cold_checkpoint(generation, sites, next_clock, true)
	if not cold.ok: return cold
	var parties: Dictionary = collect_region_party_checkpoint(generation, next_clock, "", true)
	if not parties.ok: return parties
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
	# SHIPSEA: the mandatory sea dispatch (see "Mandatory original Slot dispatches" below): a sea route (the route
	# producer marks every step of a ship party "sea") is committed by the sea setter, never as a land plan.
	if not steps.is_empty() and steps[0] is Dictionary and str(steps[0].get("mode", "land")) == "sea": return set_region_sea_travel_plan(steps)
	var status := region_travel_status()
	if not status.ok: return status
	if not bool(status.get("pending", false)): return fail("NO_TARGET", "沒有旅隊")
	if bool(status.moving): return fail("BUSY", "旅隊行進中；先停下再改目的地")
	if steps.size() < 2: return fail("INVALID", "路線至少要有出發與目的地")
	var first: Dictionary = steps[0]
	if Vector2i(int(first.site[0]), int(first.site[1])) != status.site or int(first.edge) != -1:
		return fail("INVALID", "路線必須從旅隊目前位置開始")
	var route_context := prepare_region_route_context(null, region_travel_party().get("party", {}))
	if not route_context.ok: return route_context
	var current_leg := RegionRoute.current_land_leg(source, first, route_context.context)
	if not current_leg.ok: return current_leg
	var start_cell: Variant = route_context.context.capabilities.get("start_cell")
	if not start_cell is Vector2i:
		var leader: Dictionary = RegionTravel._body_records(region_travel_party().party.content).get(int(region_travel_party().party.leader_person_id), {})
		if not leader.get("cell") is Array or leader.cell.size() != 2: return fail("MISSING_ROUTE_NODE")
		start_cell = Vector2i(int(leader.cell[0]), int(leader.cell[1]))
	if int(first.component) != RegionRoute.component_of(current_leg.derived, start_cell): return fail("INVALID", "路線須從原旅隊的當前實際入口開始")
	var verified := RegionRoute.verify_steps(source, steps, route_context.context)
	if not verified.ok: return verified
	var party := region_travel_party()
	if not party.ok: return party
	var transport := RegionTravel.prepare_transport(party.party.duplicate(true))
	if not transport.ok: return transport
	var speed := RegionTravel.party_speed(party.party.content) * float(transport.get("carry_factor", 1.0))
	if not is_finite(speed) or speed <= 0.0: return fail("CORRUPT_SAVE", "旅隊速度")
	var seconds: Array = []
	var total := 0.0
	var metres := 0.0
	for step: Dictionary in steps:
		if not _seconds(step.get("metres")): return fail("INVALID", "路線距離")
		metres += float(step.metres)
		total += float(step.metres) / (speed * maxf(0.000001, float(step.get("travel_factor", 1.0))))
		seconds.append(total)
	var journey := region_travel_journey()
	var number := int(journey.plans) + 1
	var relative := "travel/%s/plan_%06d.json" % [str(journey.token), number]
	var last: Dictionary = steps.back()
	var plan := {"version": 1, "token": str(journey.token), "steps": steps.duplicate(true), "seconds": seconds,
		"metres": metres, "physical_metres_version": 1, "speed_mps": speed, "destination": [int(last.site[0]), int(last.site[1])]}
	var written := _write_new_document(folder.path_join(relative), plan)
	if not written.ok: return written
	journey.position = {"site": [status.site.x, status.site.y], "component": int(first.component)}
	journey.plan_path = relative
	journey.plan_sha256 = FileAccess.get_sha256(folder.path_join(relative))
	journey.plan_started_game_seconds = float(control.logical_game_seconds)
	journey.plans = number
	var planned_party: Dictionary = party.party.duplicate(true)
	planned_party.upkeep["plan_id"] = relative
	planned_party.upkeep.route_distance_version = 1
	planned_party.upkeep["distance"] = 0.0
	var capture := _region_capture_party_graph(str(journey.token), planned_party)
	if not capture.ok: return capture
	var actual: Dictionary = capture.get("party", planned_party)
	var document := _region_party_document(str(journey.token), actual, capture.original_live_graph)
	if not document.ok: return document
	var generation := int(_marker.get("generation", 0)) + 1
	var party_relative := "travel/%s/party_plan_%09d_%s.json" % [str(journey.token), generation, Crypto.new().generate_random_bytes(8).hex_encode()]
	var party_written := _write_new_document(folder.path_join(party_relative), document.payload)
	if not party_written.ok: return party_written
	journey.party_path = party_relative
	journey.party_sha256 = FileAccess.get_sha256(folder.path_join(party_relative))
	var next_control := control.duplicate(true)
	var sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	var cold := _collect_cold_checkpoint(generation, sites, next_control)
	if not cold.ok: return cold
	var parties := collect_region_party_checkpoint(generation, next_control)
	if not parties.ok: return parties
	var published := _publish(sites, next_control, str(_marker.get("transfer_token", "")), journey)
	if not published.ok: return published
	_travel_party_runtime = actual
	_travel_party_runtime_token = str(journey.token)
	return {"ok": true, "plan": plan, "game_seconds": total}

## Drop the route at the party's current node (manual stop/reroute).
func stop_region_travel() -> Dictionary:
	var status := region_travel_status()
	if not status.ok or not bool(status.get("pending", false)): return status if not status.ok else fail("NO_TARGET", "沒有旅隊")
	var current: Dictionary = region_travel_party()
	if not current.ok: return current
	if str(current.party.upkeep.get("live", {}).get("upkeep", "")) == "mapBody": return _region_stop_original_map_party(current.party)
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
	var boarding_guard: Dictionary = _boarding_current_party_guard()
	if not boarding_guard.ok: return boarding_guard
	var entry := _region_retry_blocked_land_entry()
	if not entry.ok: return entry
	if entry.get("complete", true) == false: return {"ok": true, "pending": true, "source": entry}
	var initial := region_travel_status()
	if not initial.ok: return initial
	if not initial.get("pending", false): return fail("NO_TARGET")
	# SHIPSEA: the status carries the mode on its plan (region_travel_status has no top-level "mode"), so the sea
	# dispatch reads the loaded plan's mode.
	if str(initial.get("plan", {}).get("mode", "land")) == "sea": return advance_region_sea_travel(max_steps)
	if not region_original_travel_interval.is_valid() or not region_original_party_progress.is_valid():
		return fail("MISSING_REGION_ADAPTER", "缺原所有Site／party共同旅行區間主人")
	var before := float(control.logical_game_seconds)
	var count := 0
	for _index: int in range(clampi(max_steps, 0, 100000)):
		entry = _region_retry_blocked_land_entry()
		if not entry.ok: return entry
		if entry.get("complete", true) == false: break
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

func checkpoint_region_travel(journey_override: Dictionary = {}) -> Dictionary:
	var journey := region_travel_journey()
	if not journey_override.is_empty():
		if journey_override.size() != journey.size(): return fail("STALE_REGION_MAP_RESUME")
		for field: String in journey:
			if not journey_override.has(field) or field not in ["position", "plan_path", "plan_sha256"] and journey[field] != journey_override[field]: return fail("STALE_REGION_MAP_RESUME")
		if journey_override.get("position", {}).keys().size() != 2 or not journey_override.position.get("site") is Array \
				or journey_override.position.site.size() != 2 or not journey_override.position.get("component") is int:
			return fail("INVALID_JOURNEY")
		journey = journey_override.duplicate(true)
	if journey.is_empty(): return fail("NO_TARGET", "沒有原玩家旅隊")
	var loaded := region_travel_party()
	if not loaded.ok: return loaded
	var capture := _region_capture_party_graph(str(journey.token), loaded.party)
	if not capture.ok: return capture
	var actual: Dictionary = capture.get("party", loaded.party)
	var document := _region_party_document(str(journey.token), actual, capture.original_live_graph)
	if not document.ok: return document
	var generation := int(_marker.get("generation", 0)) + 1
	var relative := "travel/%s/party_checkpoint_%09d_%s.json" % [str(journey.token), generation, Crypto.new().generate_random_bytes(8).hex_encode()]
	var written := _write_new_document(folder.path_join(relative), document.payload)
	if not written.ok: return written
	journey.party_path = relative
	journey.party_sha256 = FileAccess.get_sha256(folder.path_join(relative))
	var next_control := control.duplicate(true)
	var sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	var cold := _collect_cold_checkpoint(generation, sites, next_control)
	if not cold.ok: return cold
	var parties := collect_region_party_checkpoint(generation, next_control)
	if not parties.ok: return parties
	var published := _publish(sites, next_control, str(_marker.get("transfer_token", "")), journey)
	if published.ok:
		_travel_party_runtime = actual
		_travel_party_runtime_token = str(journey.token)
	return published

func commit_region_arrival(destination_data: TerrainData, bind_guard: Callable = Callable(), endpoint: Dictionary = {}) -> Dictionary:
	var boarding_guard: Dictionary = _boarding_current_party_guard()
	if not boarding_guard.ok: return boarding_guard
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	var status := region_travel_status()
	if not status.ok: return status
	var own_final_arrival := bool(status.get("arrived", false))
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
	if own_final_arrival and str(party.get("mode", "land")) == "land" and str(party.get("upkeep", {}).get("live", {}).get("upkeep", "")) != "liveBody":
		var planned := region_travel_plan()
		if not planned.ok: return planned
		var guarded := _region_guard_current_land_arrival(str(status.token), party, planned.plan, str(region_travel_journey().plan_path))
		if not guarded.ok: return guarded
		party = guarded.party
		status = region_travel_status()
		if not status.ok: return status
	var location: Dictionary = endpoint.get("player_location", {}) if not endpoint.is_empty() else _region_arrival_location(status, party)
	if not location.ok: return location
	var generation := int(_marker.get("generation", 0)) + 1
	var path := _generation_path(generation, to)
	var nav := Env.navigation_for_state(destination_data, destination_data.site)
	var inserted: Dictionary = _insert_people(destination_data.site, party, nav, location.entry, path,
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
		var placed: Dictionary = _insert_people(inserted.state, npc, npc_nav, npc_location.entry, path,
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
	var mapped_civil := _region_n08_map_player_arrival(next_clock, str(status.token), checked.data.site)
	if not mapped_civil.ok: return mapped_civil
	# The player journey's party owner ends with this arrival, as an NPC party's
	# does in _region_joint_npc_reference. Its travel:<token> mode has no owner
	# Lab from now on; leaving it would keep a stale activation in the registry.
	if next_clock.has("region_gameplay"): next_clock.region_gameplay.modes.erase("travel:" + str(status.token))
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
	# The committed arrival is now the active owner. Its earlier cold candidate
	# (captured while it was a cold original) is superseded by this generation and
	# must not be settled again as an unbound copy at the next common checkpoint.
	_fire_cold_candidates.erase(identity)
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

## `capture`: the same-call capture_region_checkpoint result whose context/owners
## are exactly `context`/`owner_states` (see SiteStore.write_region_capture).
func checkpoint_region_site(data: TerrainData, context: Dictionary, owner_states: Dictionary, faction_candidate: Dictionary = {}, read_only_owners: bool = false, capture: Dictionary = {}) -> Dictionary:
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
	var same_capture: bool = capture.get("payload") is Dictionary and is_same(capture.get("context"), context) and is_same(capture.get("owners"), owner_states)
	var saved: Dictionary = Store.write_region_capture(data, path, capture) if same_capture else Store.save_region_snapshot(data, path, context, owner_states)
	if not saved.ok: return saved
	# Same mode-aware readback as resume; never a normal cold catch-up.
	var source_checksum: String = _faction_file_sha256(path)
	var loaded := _load_checked(path, coordinate.site)
	if not loaded.ok: return loaded
	var validated := Store.validate_region_snapshot(loaded.data, {}, expected)
	if not validated.ok: return validated
	var remembered: Dictionary = _faction_remember_captured_source(path, coordinate.site, source_checksum, loaded.data, context)
	if not remembered.ok: return remembered
	var next_clock := control.duplicate(true)
	if not faction_candidate.is_empty():
		var checked_factions: Variant = RegionFactionQuery.validate(faction_candidate, float(next_clock.logical_game_seconds))
		if not checked_factions.ok: return checked_factions
		next_clock.faction_registry = faction_candidate.duplicate(true)
	var fiefs: Dictionary = _peerage_reconcile_site(next_clock, loaded.data)
	if not fiefs.ok: return fiefs
	var sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	sites[_site_key(coordinate.site)] = _file_entry(path)
	var collected: Dictionary = _collect_cold_checkpoint(generation, sites, next_clock, read_only_owners)
	if not collected.ok: return collected
	# The active checkpoint selects the completed party bodies at this same endpoint.
	var parties: Dictionary = collect_region_party_checkpoint(generation, next_clock, "", read_only_owners)
	if not parties.ok: return parties
	var published := _publish(sites, next_clock, str(_marker.get("transfer_token", "")), _marker.get("journey", {}))
	if not published.ok: return published
	pending_peerage_inheritance.clear()
	pending_battles.clear()
	pending_falls.clear()
	return {"ok": true, "path": path, "generation": published.generation, "data": loaded.data, "snapshot": validated.snapshot}


## Same-Site living control uses the original complete active/cold checkpoint.
func commit_live_family_handover(original: TerrainLab, requester_id: int, person_id: int) -> Dictionary:
	if not is_instance_valid(original) or original.terrain == null or original.site_controller == null \
		or original.site_controller.region_slot != self or _region_bound_original_lab(original.terrain) != original:
		return fail("REGION_SOURCE")
	var prepared: Dictionary = original.site_controller.family_continuity.prepare_live_handover(requester_id, str(original.terrain.site["id"]), person_id)
	if not prepared["ok"]: return prepared
	if str(control["active_site_id"]) != str(original.terrain.site["id"]): return fail("REGION_SOURCE")
	var token: String = "region_live_family_" + Crypto.new().generate_random_bytes(16).hex_encode()
	var request: Dictionary = region_checkpoint_context(original.terrain, "region_family", token)
	if not request["ok"]: return request
	var captured: Dictionary = original.capture_region_owner_state(request["context"])
	if not captured["ok"]: return captured
	var context: Dictionary = request["context"].duplicate(true)
	context["owners"] = captured["owner_states"]
	var snapshot: Dictionary = Store.save(original.terrain, "", null, false, context, true, person_id)
	# The actual original graph is required, never an empty save bypass context.
	# Store receives it through the same original capture contract as checkpoints.
	if not snapshot["ok"]: return snapshot
	var candidate: TerrainData = TerrainLab._region_detached_bind_data(original.terrain)
	candidate.site = snapshot["state"]
	var committed: Dictionary = checkpoint_region_site(candidate, request["context"], snapshot["owners"], {}, true)
	if not committed["ok"]: return committed
	return {"ok": true, "state": committed["data"].site, "generation": committed["generation"]}

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
		if int(family.get("version", 0)) not in [1, 2, 3, 4, 5]: return fail("INVALID_FAMILY", "未知原家族版本")
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
	attach_person_allocator(data)
	return {"ok": true}

## allow_entered reads an entered party's last frozen document (its stable
## references); only callers that inspect an arrived cohort pass it.
func _region_npc_party(token: String, allow_entered: bool = false) -> Dictionary:
	var reference: Dictionary = region_registry().parties.get(token, {})
	var phases := ["travelling", "pending_life", "materializing", "entered"] if allow_entered else ["travelling", "pending_life", "materializing"]
	if str(reference.get("controller", "")) != "npc" or str(reference.get("phase", "")) not in phases:
		return fail("NO_TARGET", "沒有此原 NPC 在途 owner")
	if _region_npc_party_runtime.has(token) and str(reference.phase) != "entered": return {"ok": true, "party": _region_npc_party_runtime[token]}
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
	if str(reference.phase) != "entered": _region_npc_party_runtime[token] = party
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
	var restored := _region_restore_land_plan_integers(plan)
	if not restored.ok: return restored
	plan = restored.plan
	_region_npc_plan_runtime[token] = plan
	return {"ok": true, "plan": plan}

## The committed land plan is stored as JSON, which returns every number as a
## float. The original compiled plan (commit keeps it as the runtime plan) holds
## its route coordinates as ints, and the party's binary route_node copies them.
## Restore exactly those integral fields so a reopened plan equals the plan the
## same process held before the reopen. Non-integral values are corrupt.
static func _region_restore_land_plan_integers(document: Dictionary) -> Dictionary:
	if str(document.get("mode", "land")) == "sea": return {"ok": true, "plan": document}
	var plan: Dictionary = document.duplicate(true)
	var version: Variant = _region_integral(plan.get("version"))
	if version == null: return fail("CORRUPT_SAVE", "原 NPC 路線版本非法")
	plan["version"] = version
	if plan.has("destination"):
		var destination: Variant = _region_integral_pair(plan["destination"])
		if destination == null: return fail("CORRUPT_SAVE", "原 NPC 路線目的地非法")
		plan["destination"] = destination
	for raw: Variant in plan.steps:
		if not raw is Dictionary: return fail("CORRUPT_SAVE", "原 NPC 路線步驟非法")
		var step: Dictionary = raw
		var site: Variant = _region_integral_pair(step.get("site"))
		if site == null: return fail("CORRUPT_SAVE", "原 NPC 路線 Site 非法")
		step["site"] = site
		for field: String in ["component", "edge", "offset"]:
			if not step.has(field): continue
			var value: Variant = _region_integral(step[field])
			if value == null: return fail("CORRUPT_SAVE", "原 NPC 路線入口非法")
			step[field] = value
	return {"ok": true, "plan": plan}

static func _region_integral(value: Variant) -> Variant:
	if value is int: return value
	if value is float and is_finite(value) and value == floorf(value) and absf(value) <= 9007199254740992.0: return int(value)
	return null

static func _region_integral_pair(value: Variant) -> Variant:
	if not value is Array or value.size() != 2: return null
	var first: Variant = _region_integral(value[0])
	var second: Variant = _region_integral(value[1])
	if first == null or second == null: return null
	return [first, second]

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
		target_coordinate: Vector2i, start_component: int, steps: Array, transfer_token: String = "", carried_nation_report: String = "") -> Dictionary:
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
	# This capture writes the current presenters into the Site body (positions and
	# each team's own serialization) that the departure below extracts. It runs
	# before the source probe, so the probe and the publish decision see exactly
	# that body. Run after the probe, it could change the body the probe had
	# accepted, and the bind preflight then refused it as STALE_REGION_SOURCE_BODY.
	var captured: Dictionary = lab.site_controller.capture_region_checkpoint("region_barrier", false,
		{"npc_dispatch": true, "token": token, "owner": str(lab.terrain.site.id)}, token)
	if not captured.ok: return captured
	# A source with progress its selected publication lacks (an earlier frame, or
	# owners changed at this same time) is published at this point first; no clock
	# moves. The probe is the bind preflight's own canonical source check, so the
	# publish decision and the bind decision share one capture rule.
	var source_check: Dictionary = lab._region_selected_bind_source(lab.terrain, self)
	if not source_check.ok and str(source_check.get("code", "")) in ["STALE_REGION_CONTEXT", "STALE_REGION_SOURCE_OWNERS", "STALE_REGION_SOURCE_BODY"]:
		if not region_original_endpoint_checkpoint.is_valid(): return fail("MISSING_REGION_ADAPTER", "缺含原活動 Lab 的共同端點 checkpoint")
		var clocks := [float(control.logical_game_seconds), float(control.fire_clock.action_seconds), int(control.fire_clock.sequence)]
		var published: Variant = region_original_endpoint_checkpoint.call({"region_source_publish": "npc_dispatch", "token": token})
		if not published is Dictionary or not published.get("ok", false): return published if published is Dictionary else fail("INVALID_REGION_RECEIPT")
		if clocks != [float(control.logical_game_seconds), float(control.fire_clock.action_seconds), int(control.fire_clock.sequence)]: return fail("CLOCK_CONTRACT", "派遣前發布不得推進時鐘")
	var original: Dictionary = lab.terrain.site.duplicate(true)
	var fire_capture := _capture_transfer_fire_snapshots(lab.terrain, original)
	if not fire_capture.ok: return fire_capture
	# A crowd Site sends the whole team (R11, 2026-11-08): the converted team and its offline-released native people are
	# swapped into this copy only; the live Site is unchanged until the commit binds the published origin.
	var crowd_spec := {}
	if original.has("crowd"):
		if not lab.site_controller.has_method("crowd_npc_dispatch_origin"): return fail("UNSUPPORTED", "群眾派遣缺少原群眾 owner 轉換")
		var adapted: Dictionary = lab.site_controller.crowd_npc_dispatch_origin(original, team_id)
		if not adapted.ok: return adapted
		crowd_spec = {"crowd_departure": true, "crowd_control_successor": {}}
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
		spec.merge(crowd_spec, true)
		var result := RegionTravel.extract(original, spec, str(request.transfer_token))
		extracted.merge(result, true)
		return result
	var target_id := Grid.site_id(str(pin.atlas_id), target_coordinate)
	var authorized: Dictionary
	if carried_nation_report.is_empty():
		var context := RegionAI.dispatch_context(lab, nation_id, team_id, target_id, token, preflight)
		if not context.ok: return context
		authorized = RegionAI.prepare_dispatch(context.context)
	else:
		authorized = _region_authorize_received_nation_dispatch(lab, team_id, target_id, token, carried_nation_report, preflight)
	if not authorized.ok: return authorized
	if not extracted.get("ok", false): return fail("DISPATCH_UNAVAILABLE", "原旅行尚未准入")
	# Original departure records the already accepted shared ACTION point.
	extracted.party.upkeep.owner_action_seconds = float(control.fire_clock.action_seconds)
	# Internal dispatch retains only actual timers of the transferred people.
	extracted.party.upkeep.original_deaths = {}
	for identity: int in lab.site_controller._pending_deaths:
		if extracted.party.person_ids.has(identity):
			extracted.party.upkeep.original_deaths[str(identity)] = float(lab.site_controller._pending_deaths[identity])
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
	# The origin candidate is a NEW body; an inherited region_snapshot authenticated the old one only.
	extracted.origin.erase("region_snapshot")
	var candidate := Env.navigation_for_state(lab.terrain, extracted.origin)
	candidate.set_meta(&"region_bind_source", lab.terrain)
	var prepared_bind: Dictionary = region_bind_candidate.call(lab, candidate, "live" if str(control.active_site_id) == str(candidate.site.id) else "cold_exact")
	if not prepared_bind.get("ok", false): return prepared_bind # The original bind preflight names its own refusal.
	if not prepared_bind.get("can_publish") is Callable or not prepared_bind.get("publish") is Callable or not prepared_bind.get("save_candidate") is Callable:
		return fail("MISSING_REGION_ADAPTER", "缺原完整 bind 原子發布收據")
	# The bind ticket authenticated its own prepared body (as player departure uses).
	if prepared_bind.get("data") is TerrainData: candidate = prepared_bind.data
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
	var plan_path := str(prepared.get("plan_path", "travel/%s/plan_000001.json" % token))
	if not plan_path.begins_with("travel/" + token + "/") or plan_path.contains("..") or not plan_path.ends_with(".json"):
		return fail("INVALID_REGION_PLAN")
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
	# Route document, physical courier and knowledge ledger share one marker.
	for original_report: Dictionary in prepared.get("carried_reports", []):
		var report: Dictionary = original_report.duplicate(true)
		if str(report.delivery.get("courier_token", "")) != token or str(report.delivery.get("plan_path", "")) != plan_path: return fail("WRONG_DELIVERY_ROUTE")
		report.delivery.plan_sha256 = str(reference.plan_sha256)
		var carried := RegionAI.queue_report(registry, report)
		if not carried.ok: return carried
	var nation_execution := _region_commit_received_nation_execution(registry, prepared, token)
	if not nation_execution.ok: return nation_execution
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

## The cold original has accepted progress its selected publication lacks: it is
## a pending cold candidate, or its snapshot context is older than the world.
func _region_cold_unpublished(original: TerrainLab) -> bool:
	if original == null or original.terrain == null: return false
	if _fire_cold_candidates.has(str(original.terrain.site.id)): return true
	var context: Variant = original.terrain.site.get("region_snapshot", {}).get("context", {})
	if not context is Dictionary or not context.has("game_seconds"): return false
	return float(context.game_seconds) < float(control.logical_game_seconds) - 0.00000001

func prepare_npc_region_arrival(event: Dictionary) -> Dictionary:
	var token := str(event.get("payload", {}).get("token", ""))
	var reference: Dictionary = region_registry().parties.get(token, {})
	if str(reference.get("controller", "")) != "npc": return fail("NO_TARGET", "沒有此原 NPC 到站引用")
	if str(reference.get("phase", "")) == "entered":
		var duplicate_source := _region_validate_npc_arrival_duplicate_event(token, str(event.get("id", "")), event)
		if not duplicate_source.ok: return duplicate_source
		return {"ok": true, "duplicate": true, "token": token, "event_id": str(event.id),
			"reference": duplicate_source.reference.duplicate(true), "event": duplicate_source.event.duplicate(true)}
	if not region_owner_lab.is_valid() or not region_bind_candidate.is_valid(): return fail("MISSING_REGION_ADAPTER", "缺原到站 Site 與完整 bind 預檢")
	var loaded := _region_npc_party(token)
	if not loaded.ok: return loaded
	var boarding_guard: Dictionary = RegionTravel.boarding_travel_guard(loaded.party.content)
	if not boarding_guard.ok: return boarding_guard
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
	# A cold destination advanced by accepted intervals since its last joint
	# publication is published at this same point first; no clock moves. The
	# bind preflight below still requires that exact published frame.
	if requested_mode == "cold_exact" and _region_cold_unpublished(lab):
		if not region_original_endpoint_checkpoint.is_valid(): return fail("MISSING_REGION_ADAPTER", "缺含原活動 Lab 的共同端點 checkpoint")
		var clocks := [float(control.logical_game_seconds), float(control.fire_clock.action_seconds), int(control.fire_clock.sequence)]
		var published: Variant = region_original_endpoint_checkpoint.call({"region_source_publish": "npc_arrival", "event": str(event.get("id", ""))})
		if not published is Dictionary or not published.get("ok", false): return published if published is Dictionary else fail("INVALID_REGION_RECEIPT")
		if clocks != [float(control.logical_game_seconds), float(control.fire_clock.action_seconds), int(control.fire_clock.sequence)]: return fail("CLOCK_CONTRACT", "到站前發布不得推進時鐘")
	var party: Dictionary = loaded.party
	if absf(float(party.get("upkeep", {}).get("at", -1.0)) - float(control.logical_game_seconds)) > 0.00000001:
		return fail("UNSETTLED_PARTY", "原到站 party 與世界端點不同")
	var contact_entry := str(event.get("payload", {}).get("contact_receipt", {}).get("kind", "")) == "npc_siege_channel"
	if contact_entry:
		var channel := _region_validate_npc_siege_contact(event)
		if not channel.ok: return channel
		if not bool(channel.valid): return fail("STALE_NPC_CONTACT")
	if str(planned.plan.get("mode", "land")) == "land" and not contact_entry:
		var guarded := _region_guard_current_land_arrival(token, party, planned.plan, str(reference.plan_path))
		if not guarded.ok: return guarded
		party = guarded.party
	var position: Dictionary = _region_npc_sea_position(planned.plan, party) if str(planned.plan.get("mode", "land")) == "sea" else _region_current_land_position(party, planned.plan, str(region_registry().parties[token].plan_path))
	if str(planned.plan.get("mode", "land")) == "sea" and not bool(position.get("arrived", false)):
		return fail("INCOMPLETE_JOURNEY", "原船尚有未完成ACTION，不能用靜態距離冒充到站")
	if position.site != coordinate_raw or (str(planned.plan.get("mode", "land")) == "sea" and int(position.component) != int(event.payload.get("component", -1))):
		return fail("STALE_ARRIVAL", "原路線位置與事件不同")
	var entry_step: Dictionary = planned.plan.steps[int(position.step_index)]
	var entry: Vector2i = RegionRoute.entry_cell(entry_step)
	var insertion_options := {"generation": int(_marker.get("generation", 0)) + 1, "family_transfer_guard": region_family_transfer_guard, "vehicle_poses": entry_step.get("vehicle_poses", {})}
	if contact_entry:
		var accepted := _region_npc_endpoint_location(token, to, event)
		if not accepted.ok: return accepted
		entry = accepted.entry
		var world := _region_live_party_world(token, party, planned.plan, event, "first")
		if not world.ok: return world
		var frame := {"version": 1, "world_origin": [to.x * 100, -to.y * 100], "size": [100, 100],
			"game_seconds": float(control.logical_game_seconds), "action_seconds": float(control.fire_clock.action_seconds), "people": world.people, "vehicles": world.vehicles}
		var projected := RegionTravel.project_party_frame(party, frame)
		if not projected.ok: return projected
		insertion_options.contact_source = party
		insertion_options.contact_frame = frame
		party = projected.party
	var generation := int(_marker.get("generation", 0)) + 1
	var to_path := _generation_path(generation, to)
	var captured: Dictionary = lab.site_controller.capture_region_checkpoint("region_barrier", false,
		{"npc_arrival": true, "token": token, "event": str(event.id)}, token)
	if not captured.ok: return captured
	var destination := lab.terrain.site.duplicate(true)
	var fire_capture := _capture_transfer_fire_snapshots(lab.terrain, destination)
	if not fire_capture.ok: return fire_capture
	var nav := Env.navigation_for_state(lab.terrain, destination)
	var inserted: Dictionary = _insert_people(destination, party, nav, entry, to_path,
		float(reference.departure_game_seconds), float(control.logical_game_seconds),
		insertion_options)
	if not inserted.ok: return inserted
	var candidate := Env.navigation_for_state(lab.terrain, inserted.state)
	candidate.set_meta(&"region_bind_source", lab.terrain)
	var binding: Dictionary = region_bind_candidate.call(lab, candidate, requested_mode)
	# A refused bind preflight names its own refusal (as dispatch returns it).
	if not binding.get("ok", false) and binding.has("code"): return binding
	if not binding.get("ok", false) or not binding.get("can_publish") is Callable or not binding.get("publish") is Callable:
		return fail("MISSING_REGION_ADAPTER", "原到站完整 bind 未准入")
	# The bind ticket authenticated its own prepared body (as dispatch and player
	# departure use); save and publish exactly that body.
	if binding.get("data") is TerrainData: candidate = binding.data
	var battle := _region_arrival_battle_candidate(destination, inserted.state, party, inserted.mapping, token, binding, requested_mode == "live")
	if not battle.ok: return battle
	if contact_entry and str(battle.get("battle", {}).get("kind", "")) == "siege":
		battle.battle.mode = "live" if requested_mode == "live" else "cold_exact"
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
	if prepared.get("duplicate", false):
		if not prepared.get("event") is Dictionary or not prepared.get("reference") is Dictionary: return fail("STALE_NPC_ARRIVAL", "原重複到站缺真事件／NPC引用快照")
		var duplicate_source := _region_validate_npc_arrival_duplicate_event(str(prepared.get("token", "")), str(prepared.get("event_id", "")), prepared.event)
		if not duplicate_source.ok: return duplicate_source
		if var_to_bytes(prepared.reference) != var_to_bytes(duplicate_source.reference): return fail("STALE_NPC_ARRIVAL", "原已到站NPC引用已變")
		var duplicate_event := complete_region_event(str(duplicate_source.event.id))
		return prepared if duplicate_event.ok else duplicate_event
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
	var deliveries := _region_accept_carried_arrival(next_control, token, str(prepared.destination_site), prepared.mapping)
	if not deliveries.ok: return deliveries
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
	var activated := activate_region_mode(str(prepared.destination_site), final_mode, str(bound.consumer), bound, str(bound.get("backend", "gd")))
	if not activated.ok: return activated
	_region_npc_party_runtime.erase(token)
	_region_npc_plan_runtime.erase(token)
	return {"ok": true, "token": token, "generation": published.generation, "binding": bound, "mapping": prepared.mapping, "battle": prepared.get("battle", {})}

# Shared-step preview only. No party clock publishes world time. All deltas go
# through original RegionTravel.advance_upkeep, including fatigue-integrated metres.


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
	if str(party.upkeep.get("live", {}).get("upkeep", "")) == "liveBody":
		if interval.is_empty(): return {"ok": true, "at": end, "party": party, "source_party": party, "events": [],
			"position": region_registry().parties[token].position.duplicate(true), "arrived": false}
		var live: Dictionary = _region_live_party_candidate(interval, party)
		live.position = region_registry().parties[token].position.duplicate(true)
		return live
	if plan.get("mode") == "sea":
		var sea := _preview_npc_sea_party_to(token, party, plan, end, interval)
		if sea.ok: sea.source_party = party
		return sea
	return _region_land_route_preview(party, plan, str(region_registry().parties[token].plan_path), end)

# Route boundaries use the original fatigue-integrated distance. These previews
# are navigation/contact truth only; no strategy observation is created.

func _region_route_breaks(party: Dictionary, plan: Dictionary, to: float, moving: bool) -> Dictionary:
	var begin := float(control.logical_game_seconds)
	var preview := _region_land_route_preview(party, plan, str(party.get("upkeep", {}).get("plan_id", "")), to, moving)
	if not preview.ok: return preview
	return {"ok": true, "times": [begin, float(preview.at)], "until": float(preview.at)}

func _region_route_position_at(party: Dictionary, plan: Dictionary, at: float, moving: bool) -> Dictionary:
	var preview := _region_land_route_preview(party, plan, str(party.get("upkeep", {}).get("plan_id", "")), at, moving)
	if not preview.ok: return preview
	return {"ok": true, "at": float(preview.at), "position": preview.position}

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
	# The party was just extracted from this Site. While the player stays in that
	# same active Site and the party is still on its departure segment, they are
	# not meeting on the road; any later position or player move is judged as usual.
	var npc_origin: Variant = npc_reference.get("origin", [])
	var departure_site := Grid.site_id(str(pin.atlas_id), Vector2i(int(npc_origin[0]), int(npc_origin[1]))) if npc_origin is Array and npc_origin.size() == 2 else ""
	var player_in_origin := not active.is_empty() and not departure_site.is_empty() and departure_site == str(control.active_site_id)
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
		if player_in_origin and int(a.get("step_index", -1)) == 0 and a.get("site") == npc_origin: continue
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
		var site_id := Grid.site_id(str(pin.atlas_id), Vector2i(int(site[0]), int(site[1])))
		if _region_n08_completed_contact(token, site_id, component): continue
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

## The NPC static siege-contact producer. Queues the earliest contact of this
## travelling party up to `to` under its stable (token, battle, point) id. The
## endpoint producer and the blocked-entry retry share it; both queue it before
## the same-point arrival, so the contact is consumed first.
func _region_queue_npc_siege_contact(token: String, to: float, interval: Dictionary = {}) -> Dictionary:
	var siege := _region_first_npc_siege_contact(token, to, interval)
	if not siege.ok: return siege
	if not bool(siege.get("contact", false)): return {"ok": true, "contact": false}
	var registry := region_registry()
	var contact_id := "npc-siege:" + Marshalls.raw_to_base64(var_to_bytes([token, str(siege.battle_id), float(siege.at)])).sha256_text()
	if not registry.events.any(func(existing_event: Dictionary) -> bool: return str(existing_event.id) == contact_id):
		var queued_siege := queue_region_event(contact_id, "reinforcement", float(siege.at), str(siege.site_id),
			{"token": token, "battle_id": str(siege.battle_id), "site": siege.site.duplicate(),
			"component": int(siege.component), "contact_receipt": siege.contact_receipt.duplicate(true)})
		if not queued_siege.ok: return queued_siege
	return {"ok": true, "contact": true, "id": contact_id}

func queue_region_gameplay_endpoints(unclipped_game_end: float, interval: Dictionary = {}) -> Dictionary:
	var retried := _region_retry_blocked_npc_land_entries()
	if not retried.ok: return retried
	var registry := region_registry()
	var tokens: Array = registry.parties.keys()
	tokens.sort()
	for token: String in tokens:
		if str(registry.parties[token].get("phase", "")) != "travelling": continue
		var forecast := _preview_npc_party_to(token, unclipped_game_end, interval)
		if not forecast.ok: return forecast
		var siege := _region_queue_npc_siege_contact(token, unclipped_game_end, interval)
		if not siege.ok: return siege
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
			var queued := queue_region_event(_region_arrival_attempt_id(token, forecast.party, false), "player_arrival" if player_present else "arrival", float(forecast.at), owner,
				{"token": token, "site": forecast.position.site.duplicate(), "component": int(forecast.position.component)}, player_present)
			if not queued.ok: return queued
	for first_index: int in tokens.size():
		for second_index: int in range(first_index + 1, tokens.size()):
			var first_token := str(tokens[first_index])
			var second_token := str(tokens[second_index])
			var pair := _region_npc_sea_pair_boundary(first_token, second_token)
			if not pair.ok: return pair
			if not pair.get("contact", false): continue
			var receipt: Dictionary = pair.receipt
			var contact_id := "npc-sea:" + Marshalls.raw_to_base64(var_to_bytes(receipt)).sha256_text()
			if registry.events.any(func(old: Dictionary) -> bool: return str(old.id) == contact_id): continue
			var queued_pair := queue_region_event(contact_id, "reinforcement", float(control.logical_game_seconds), "travel:" + second_token,
				{"token": first_token, "contact_receipt": receipt})
			if not queued_pair.ok: return queued_pair
	var siege_contact: Dictionary = _region_first_player_siege_contact(unclipped_game_end, interval)
	if not siege_contact.ok: return siege_contact
	if siege_contact.get("contact", false):
		var contact_event: Dictionary
		if siege_contact.has("accepted_event"):
			var accepted: Dictionary = siege_contact.accepted_event
			contact_event = queue_region_event(str(accepted.id), str(accepted.kind), float(accepted.at), str(accepted.owner), accepted.payload, true)
		else:
			contact_event = queue_region_event("siege:%s:player:%s:%.9f" % [str(siege_contact.battle_id), str(region_travel_journey().token), float(siege_contact.at)], "player_encounter", float(siege_contact.at), str(siege_contact.site_id), {"player_token": str(region_travel_journey().token), "battle_id": str(siege_contact.battle_id), "site": siege_contact.site.duplicate(), "component": int(siege_contact.component), "contact_receipt": siege_contact.contact_receipt.duplicate(true)}, true)
		if not contact_event.ok: return contact_event
	for id: String in registry.battles:
		var battle: Dictionary = registry.battles[id]
		if str(battle.get("phase", "")) == "finished": continue
		if str(battle.get("site_id", "")) == str(control.active_site_id):
			if str(battle.get("mode", "")) == "live": continue
			var queued := queue_region_event("battle:%s:player:%.9f" % [id, float(control.logical_game_seconds)], "player_encounter", float(control.logical_game_seconds), str(battle.site_id), {"battle_id": id}, true)
			if not queued.ok: return queued
			continue
		var endpoint := RegionBattle.next_event(battle)
		if is_finite(endpoint) and endpoint <= unclipped_game_end:
			var queued := queue_region_event("battle:%s:%d" % [id, int(battle.revision)], "battle", endpoint, str(battle.site_id), {"battle_id": id})
			if not queued.ok: return queued
	for report: Dictionary in registry.reports:
		if report.has("delivery"):
			var valid := RegionAI.validate_carried_report(report)
			if not valid.ok: return valid
			if RegionAI.carried_report_terminal(report) or str(report.delivery.phase) == "ready": continue
			var expires := float(report.receipt.expires_at)
			if expires <= unclipped_game_end:
				var expiry := queue_region_event("report:" + str(report.id) + ":expires", "intel", expires, str(report.delivery.receiver_scope), {"report_id": str(report.id), "carried": true})
				if not expiry.ok: return expiry
			continue
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
	# A fresh original prepare starts a new observation call, even at a reused point.
	# Keep already published local zero outcomes; never carry positive provisional rows.
	if _original_food_result_readout:
		for index: int in range(_original_food_results.size() - 1, -1, -1):
			if not _original_food_results[index].interval.is_empty(): _original_food_results.remove_at(index)
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
		var mode: Dictionary = registry.modes.get(owner, {})
		if str(mode.get("consumer", "")) not in ["original_region_travel", "original_party"] or str(mode.get("backend", "")) != "gd": return fail("REGION_PARTY_MODE")
		var permit := GameplayClock.begin_permit(registry, owner, str(mode.get("mode", "")), int(_marker.get("generation", 0)),
			float(control.logical_game_seconds), float(control.fire_clock.action_seconds), str(mode.consumer), held)
		if not permit.ok: return permit
		permits[owner] = permit
		if not region_original_party_progress.is_valid(): return fail("MISSING_REGION_PARTY_PROGRESS")
		var host: Object = region_original_party_progress.get_object()
		if not host is TerrainLab or host.site_controller == null or host.site_controller.region_slot != self: return fail("INVALID_REGION_PARTY_PROGRESS")
		var restored: Dictionary = host.prepare_region_party_original_owner(token, preview.source_party, self)
		if not restored.ok: return restored
		restored.lab.simulation_speed = float(interval.scale)
		var original_guard: Dictionary = restored.lab._region_original_interval_guard(interval)
		if not original_guard.ok: return original_guard
		if restored.lab._region_party_original_action_limit(float(interval.action_end) - float(interval.action_begin)) < float(interval.action_end) - float(interval.action_begin) - 0.000000001: return fail("EVENT_CLIP_REQUIRED")
		preview.original_lab = restored.lab
		parties[token] = preview
	for id: String in registry.battles:
		var battle: Dictionary = registry.battles[id]
		if str(battle.get("phase", "")) == "finished" or str(battle.get("mode", "")) != "formula_active": continue
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
	var reopened_entries: Array[Dictionary] = []
	for token: String in prepared.parties:
		var candidate: Dictionary = prepared.parties[token]
		var planned := _region_npc_plan(token)
		if not planned.ok: return planned
		var entry_was_blocked: bool = candidate.get("party", {}).get("upkeep", {}).has("route_blocked")
		var validated := _region_revalidate_completed_land_outcome(token, candidate, planned.plan, str(registry.parties[token].plan_path))
		if not validated.ok: return validated
		candidate = validated.outcome
		prepared.parties[token] = candidate
		_region_npc_party_runtime[token] = candidate.party
		registry.parties[token].position = {"site": candidate.position.site.duplicate(), "component": int(candidate.position.component)}
		registry.parties[token].phase = "pending_life" if not candidate.events.is_empty() else "travelling"
		if bool(candidate.get("arrived", false)) and candidate.events.is_empty():
			var event_id := _region_arrival_attempt_id(token, candidate.party, false)
			if not registry.events.any(func(event: Dictionary) -> bool: return str(event.id) == event_id):
				var owner := Grid.site_id(str(pin.atlas_id), Vector2i(int(candidate.position.site[0]), int(candidate.position.site[1])))
				var player_present := owner == str(control.active_site_id)
				var arrival_payload := {"token": token, "site": candidate.position.site.duplicate(), "component": int(candidate.position.component)}
				if entry_was_blocked and registry.battles.values().any(func(battle: Dictionary) -> bool: return str(battle.get("kind", "")) == "siege" and str(battle.get("phase", "")) != "finished" and str(battle.get("site_id", "")) == owner):
					# The live seam check admitted a previously blocked entry at this
					# endpoint. The forecast read the published closed entry and could not
					# queue this attempt's static contact, so it is queued below, before
					# this arrival, once every owner mode has reached the endpoint.
					reopened_entries.append({"token": token, "event_id": event_id, "owner": owner, "player": player_present, "payload": arrival_payload})
					continue
				var queued := queue_region_event(event_id, "player_arrival" if player_present else "arrival", float(interval.game_end), owner,
					arrival_payload, player_present)
				if not queued.ok: return queued
	for id: String in prepared.battles:
		registry.battles[id].prepared_endpoint = prepared.battles[id].prepared.duplicate(true)
		var queued := queue_region_event("battle:%s:interval:%d" % [id, int(interval.sequence)], "battle", float(interval.game_end), str(registry.battles[id].site_id), {"battle_id": id})
		if not queued.ok: return queued
	for owner: String in prepared.permits:
		registry.modes[owner].game_seconds = float(interval.game_end)
		registry.modes[owner].action_seconds = float(interval.action_end)
	# A reopened entry's own static contact precedes its same-point arrival, as
	# the endpoint producer and the blocked-entry retry order them.
	for reopened: Dictionary in reopened_entries:
		var static_contact := _region_queue_npc_siege_contact(str(reopened.token), float(interval.game_end))
		if not static_contact.ok: return static_contact
		var reopened_arrival := queue_region_event(str(reopened.event_id), "player_arrival" if bool(reopened.player) else "arrival", float(interval.game_end), str(reopened.owner),
			reopened.payload, bool(reopened.player))
		if not reopened_arrival.ok: return reopened_arrival
	# Only this successful original commit accepts its actual per-call results.
	for token: String in prepared.parties:
		var candidate: Dictionary = prepared.parties[token]
		_observe_original_food_result(candidate.original_lab, "party", token, float(candidate.at), candidate, interval)
	var food_interval := {}
	for field: String in ["epoch", "sequence", "game_begin", "game_end", "action_begin", "action_end"]: food_interval[field] = interval[field]
	for food: Dictionary in _original_food_results:
		if food.interval == food_interval: food.accepted = true
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
			var civil := _region_n08_consume_entered()
			if not civil.ok: return civil
			return {"ok": true, "complete": held.is_empty(), "consumed": consumed,
				"player_barrier": not held.is_empty(), "restricted_settlement": not held.is_empty()}
		var event: Dictionary = pending[0].duplicate(true)
		var navigation := _region_consume_blocked_land_event(event)
		if not navigation.ok: return navigation
		if bool(navigation.get("handled", false)):
			for original: Dictionary in region_registry().events:
				if str(original.id) == str(event.id): original.payload["navigation_result"] = navigation.receipt.duplicate(true)
			var completed := complete_region_event(str(event.id))
			if not completed.ok: return completed
			consumed += 1
			continue
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
		if str(event.kind) == "reinforcement" and str(event.payload.get("contact_receipt", {}).get("kind", "")) == "npc_sea_sweep_boundary":
			if not region_original_party_progress.is_valid(): return fail("MISSING_REGION_PARTY_PROGRESS")
			var host: Object = region_original_party_progress.get_object()
			if not host is TerrainLab or host.site_controller.region_slot != self: return fail("INVALID_REGION_PARTY_PROGRESS")
			var joined: Dictionary = host._region_gameplay_npc_sea_materialize(event)
			if not joined.ok: return joined
			for original: Dictionary in region_registry().events:
				if str(original.id) == str(event.id): original.payload["contact_result"] = joined.get("receipt", {}).duplicate(true)
			var complete := complete_region_event(str(event.id))
			if not complete.ok: return complete
			var checkpoint := _region_checkpoint_carried_delivery(str(event.id))
			if not checkpoint.ok: return checkpoint
			consumed += 1
			continue
		match str(event.kind):
			"intel":
				if bool(event.payload.get("carried", false)):
					var delivery := RegionAI.deliver_carried_report(registry, str(event.payload.get("report_id", "")), float(event.at), float(control.fire_clock.action_seconds), Callable(self, "_region_consume_carried_report"))
					if not delivery.ok: return delivery
				else: RegionAI.reports_due(registry, float(event.at))
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
				if not event.payload.has("entered_site") and not event.payload.has("entered_party"):
					party = _region_npc_party(token)
					if not party.ok: return party
				var result: Dictionary = region_party_life_consumer.call(token, event.payload.event, party.party)
				if not result.get("ok", false) or not result.get("party") is Dictionary or not bool(result.get("receipt", {}).get("complete", false)):
					return fail("COMMITTED_UNBOUND", "原生命出口尚未提供真收據")
				if not event.payload.has("entered_site") and not event.payload.has("entered_party"):
					_region_npc_party_runtime[token] = result.party
					registry.parties[token].phase = "travelling"
			"evaluation":
				var original: Dictionary = region_owner_lab.call(str(event.owner), "live" if str(event.owner) == str(control.active_site_id) else "cold_exact")
				if not original.get("ok", false): return original
				var lab: TerrainLab = original.lab
				var observed_features := record_region_officer_feature_observations(lab)
				if not observed_features.ok: return observed_features
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
				var remote_nation := _region_produce_remote_nation_dispatch(lab)
				if not remote_nation.ok: return remote_nation
				if bool(remote_nation.get("published", false)):
					consumed += 1
					continue
				for intent: Dictionary in proposed.get("intents", []):
					var candidate := prepare_npc_region_dispatch(lab, str(intent.nation_id), int(intent.team_id), Vector2i(int(intent.target_coordinate[0]), int(intent.target_coordinate[1])), int(intent.start_component), intent.steps)
					if not candidate.ok: continue
					# The actual selected known receipt travels with the original captain.
					var standing := prepare_region_carried_command(candidate, str(intent.known_receipt))
					if not standing.ok: return standing
					var dispatched := commit_npc_region_dispatch(candidate)
					if not dispatched.ok: return dispatched
				consumed += 1
				continue
			"arrival", "reinforcement":
				var npc_contact := str(event.payload.get("contact_receipt", {}).get("kind", "")) == "npc_siege_channel"
				if npc_contact:
					var channel := _region_validate_npc_siege_contact(event)
					if not channel.ok: return channel
					if not bool(channel.valid):
						for original_event: Dictionary in registry.events:
							if str(original_event.id) == str(event.id): original_event.payload["contact_result"] = {"complete": true, "no_effect": true, "reason": str(channel.get("reason", "STALE_NPC_CONTACT"))}
						var no_effect := complete_region_event(str(event.id))
						if not no_effect.ok: return no_effect
						consumed += 1
						continue
				var prepared_arrival := prepare_npc_region_arrival(event)
				if not prepared_arrival.ok:
					if not npc_contact or str(prepared_arrival.get("code", "")) not in ["PARTY_FRAME_BOUNDS", "CONTACT_FOOT_UNPLACED", "CONTACT_FOOT_UNSUPPORTED"]: return prepared_arrival
					for original_event: Dictionary in registry.events:
						if str(original_event.id) == str(event.id): original_event.payload["contact_result"] = {"complete": true, "no_effect": true, "reason": str(prepared_arrival.code)}
					var no_placement := complete_region_event(str(event.id))
					if not no_placement.ok: return no_placement
					consumed += 1
					continue
				var arrived := commit_npc_region_arrival(prepared_arrival)
				if not arrived.ok: return arrived
				consumed += 1
				continue
			_:
				return {"ok": true, "complete": false, "event": event, "consumed": consumed}
		var completed := complete_region_event(str(event.id))
		if not completed.ok: return completed
		if str(event.kind) == "intel" and bool(event.payload.get("carried", false)):
			var saved_delivery := _region_checkpoint_carried_delivery(str(event.id))
			if not saved_delivery.ok: return saved_delivery
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

func collect_region_party_checkpoint(generation: int, next_control: Dictionary, composed_token: String = "", read_only: bool = false) -> Dictionary:
	for token: String in _region_npc_party_runtime:
		# Its new complete composed graph is already written by the same commit.
		if token == composed_token: continue
		var reference: Dictionary = next_control.region_gameplay.parties.get(token, {})
		if str(reference.get("phase", "")) not in ["travelling", "pending_life", "materializing"]: continue
		var party: Dictionary = _region_npc_party_runtime[token]
		var upkeep: Dictionary = party.get("upkeep", {})
		if not _seconds(upkeep.get("at")) or not _seconds(upkeep.get("owner_action_seconds")) \
				or absf(float(upkeep.at) - float(next_control.logical_game_seconds)) > 0.00000001 \
				or absf(float(upkeep.owner_action_seconds) - float(next_control.fire_clock.action_seconds)) > 0.00000001:
			var refused := fail("UNSETTLED_PARTY", "共同 checkpoint 不能選定未完成同一雙時間端點的原 party")
			refused.diagnostic = {"token": token, "phase": str(reference.phase), "generation": generation,
				"party_game": upkeep.get("at"), "party_action": upkeep.get("owner_action_seconds"),
				"world_game": next_control.logical_game_seconds, "world_action": next_control.fire_clock.action_seconds}
			return refused
		var capture: Dictionary = _region_capture_party_graph(token, party, {}, read_only)
		if not capture.ok: return capture
		var actual: Dictionary = capture.get("party", party)
		var document := _region_party_document(token, actual, capture.original_live_graph)
		if not document.ok: return document
		var relative := "travel/%s/party_checkpoint_%09d_%s.json" % [token, generation, Crypto.new().generate_random_bytes(8).hex_encode()]
		var written := _write_new_document(folder.path_join(relative), document.payload)
		if not written.ok: return written
		reference.party_path = relative
		reference.party_sha256 = FileAccess.get_sha256(folder.path_join(relative))
		# Capture verifies the same party bytes; checkpoint publication must retain
		# its runtime identity for original callers spanning this common marker.
	return {"ok": true}

func _close_original_cold_region_points() -> Dictionary:
	for owner: String in _region_original_labs:
		if owner == str(control.active_site_id): continue
		if str(region_registry().modes.get(owner, {}).get("mode", "")) != "cold_exact": continue
		var original: TerrainLab = _region_original_labs[owner]
		if not is_instance_valid(original): return fail("COMMITTED_UNBOUND", "原 cold endpoint owner 已失")
		if original._region_point_pending.is_empty(): continue
		var consumed: Dictionary = original.consume_region_point(false)
		if not consumed.get("ok", false) or not consumed.get("complete", false): return consumed
	return {"ok": true, "complete": true}

func _finish_original_cold_region_points() -> Dictionary:
	var closed: Dictionary = _close_original_cold_region_points()
	if not closed.get("ok", false) or not closed.get("complete", false): return closed
	if not region_registry().parties.is_empty():
		if not region_original_party_zero.is_valid(): return fail("MISSING_REGION_PARTY_ENDPOINT")
		var settled: Variant = region_original_party_zero.call()
		if not settled is Dictionary or not settled.get("ok", false) or not settled.get("complete", false): return settled if settled is Dictionary else fail("INCOMPLETE_PARTY_ENDPOINT")
	var deliveries := _region_check_carried_deliveries()
	if not deliveries.ok: return deliveries
	if bool(deliveries.get("changed", false)):
		var saved_delivery := _region_checkpoint_carried_delivery("original_party_endpoint")
		if not saved_delivery.ok: return saved_delivery
	var nation_commands := _region_finalize_received_nation_commands()
	if not nation_commands.ok: return nation_commands
	if bool(nation_commands.get("changed", false)) and not bool(nation_commands.get("published", false)):
		var saved_nation := _region_checkpoint_carried_delivery("original_nation_command_endpoint")
		if not saved_nation.ok: return saved_nation
	# New metadata is admitted only after ALL actual original cold/party points.
	for owner: String in _region_original_labs:
		var cold_siege: Dictionary = refresh_original_region_siege_battle(_region_original_labs[owner])
		if not cold_siege.ok: return cold_siege
		if str(region_registry().modes.get(owner, {}).get("mode", "")) != "cold_exact": continue
		var admitted := admit_original_region_contact_battle(_region_original_labs[owner])
		if not admitted.ok: return admitted
	if region_contact_active_data.is_valid() and not str(control.active_site_id).is_empty():
		var active: Variant = region_contact_active_data.call()
		if active is Dictionary and active.get("ok", false) and active.get("data") is TerrainData:
			var active_original: TerrainLab = _region_bound_original_lab(active.data)
			if active_original != null:
				var active_siege: Dictionary = refresh_original_region_siege_battle(active_original)
				if not active_siege.ok: return active_siege
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
	var placed: Dictionary = _insert_people(destination.data.site, loaded.party, nav, entry, path,
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
	if str(party.get("upkeep", {}).get("live", {}).get("upkeep", "")) == "liveBody": return _region_live_party_candidate(interval, party)
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
	var boarding_guard: Dictionary = _boarding_current_party_guard()
	if not boarding_guard.ok: return boarding_guard
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
	var admitted: Dictionary = _insert_people(destination.data.site, candidate, nav, entry, _generation_path(generation, status.site),
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
	var siege_contact: Dictionary = _region_validate_player_siege_contact(event)
	if not siege_contact.ok: return siege_contact
	if not siege_contact.valid:
		return {"ok": true, "receipt": {"effects_complete": true, "complete": true, "skipped_contact": true, "reason": str(siege_contact.get("reason", "")), "game_seconds": float(control.logical_game_seconds), "action_seconds": float(control.fire_clock.action_seconds)}}
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
		projected = RegionRoute.sea_contact_labels(data)
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
	result["component"] = label
	result["route_component"] = int(route_position.get("component", -1))
	result["mode"] = mode
	result["cell"] = [cell.x, cell.y]
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
			point["seam"] = {"edge": RegionRoute.opposite(int(plan.steps[index].edge)), "offset": int(plan.steps[index].offset)}
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
			if prior_leg >= 0: point["seam"] = {"edge": RegionRoute.opposite(int(plan.steps[leg].edge)), "offset": int(plan.steps[leg].offset)}
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
	if str(party.get("upkeep", {}).get("live", {}).get("upkeep", "")) == "liveBody": return _region_live_party_candidate(interval, party)
	var outcome := _region_land_route_preview(party, status.plan, str(status.journey.plan_path), float(interval.game_end))
	if not outcome.ok: return outcome
	outcome.action_seconds = GameplayClock.action_for_game(float(outcome.at) - float(interval.game_begin),
		float(interval.scale), float(interval.tactical_seconds))
	return _region_prepare_map_motion_outcome(party, status, outcome)


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
		var queued := queue_region_event(_region_arrival_attempt_id(token, region_travel_party().party, true, str(status.journey.plan_path)), "player_arrival",
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
	var planned := region_travel_plan()
	if not planned.ok: return planned
	var validated := _region_revalidate_completed_land_outcome(token, outcome, planned.plan, str(region_travel_journey().plan_path))
	if not validated.ok: return validated
	outcome = validated.outcome
	accepted.outcome = outcome
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
	return {"site": plan.steps[leg].site.duplicate(), "component": 0, "step_index": leg, "fraction": 0.0, "arrived": index == plan.action_steps.size()}




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

var _opening_author_context: Dictionary = {}

var _initialization: Dictionary = {}

var _initial_candidate: Dictionary = {}
# P5C-S2 test seam (default invalid = no fault). Called before each companion
# Site file is written with its canonical index (start is index 0); returning
# true makes that write fail with SAVE_IO and leaves the candidate unset.
var initial_write_fault: Callable
# P5C-S3: populated companion bodies supplied by the controller (key "x:y" -> TerrainData).
var _companion_births: Dictionary = {}

static func _initial_site_same(left: Variant, right: Variant) -> bool:
	if not left is Array or not right is Array or left.size() != 2 or right.size() != 2: return false
	for index: int in 2:
		if not _whole(left[index], -10000000, 10000000) or not _whole(right[index], -10000000, 10000000) or int(left[index]) != int(right[index]): return false
	return true


static func _initial_context_ok(context: Variant) -> bool:
	if author_initial_context_valid(context): return true
	return context is Dictionary and context.size() == 2 and context.get("starting_site") is Array and context.starting_site.size() == 2 and _whole(context.starting_site[0], -10000000, 10000000) and _whole(context.starting_site[1], -10000000, 10000000) and context.get("initial_scenario_id") is String and str(context.initial_scenario_id) in ["", InitialArtisans.PRIMARY, InitialArtisans.THREE_FACTIONS]

# P5C-S1: schema cap for one authored birth package. open_map still admits
# exactly one Site until the P5C-S2 birth transaction lands.
const AUTHOR_INITIAL_SITE_LIMIT := 16

static func author_initial_context_valid(context: Variant) -> bool:
	# This schema is admitted only with the same loaded package identity and start.
	if not context is Dictionary or context.size() != 6 or not _whole(context.get("version"), 2, 2) or context.get("mode") != "author": return false
	var identity: Variant = context.get("author_identity")
	if not identity is Dictionary or identity.size() != RegionTerrainAdapter.AUTHOR_FIELDS.size() or not RegionTerrainAdapter.has_author_identity(identity) or not RegionTerrainAdapter.valid_author_identity(identity): return false
	if not RegionTerrainAdapter.author_pair_valid(context.get("starting_site"), -10000000, 10000000) or not RegionTerrainAdapter.author_start_valid(context.get("start")): return false
	if not _initial_site_same(context.starting_site, context.start.site): return false
	var sites: Variant = context.get("expected_initial_sites")
	if not sites is Array or sites.is_empty() or sites.size() > AUTHOR_INITIAL_SITE_LIMIT: return false
	var seen := {}
	var found := false
	for pair: Variant in sites:
		if not RegionTerrainAdapter.author_pair_valid(pair, -10000000, 10000000): return false
		var key := "%d:%d" % [int(pair[0]), int(pair[1])]
		if seen.has(key): return false
		seen[key] = true
		found = found or _initial_site_same(pair, context.starting_site)
	return found

static func same_author_initial_context(left: Variant, right: Variant) -> bool:
	if not author_initial_context_valid(left) or not author_initial_context_valid(right): return false
	if not RegionTerrainAdapter.same_author_identity(left.author_identity, right.author_identity) or not _initial_site_same(left.starting_site, right.starting_site): return false
	if left.start.mode != right.start.mode or not _initial_site_same(left.start.site, right.start.site) or not _initial_site_same(left.start.cell, right.start.cell): return false
	if left.start.mode == "existing_person" and int(left.start.person_id) != int(right.start.person_id): return false
	# P5C-S2: the birth set is a set. Compare canonical order, not the stored list order.
	return author_initial_site_order(left) == author_initial_site_order(right)

# P5C-S1: canonical birth order. The starting Site comes first, then every other
# expected Site in x,y order. An invalid context yields an empty order.
static func author_initial_site_order(context: Variant) -> Array:
	var ordered: Array = []
	if not author_initial_context_valid(context): return ordered
	var start: Array = context.get("starting_site")
	var rest: Array = []
	for pair: Variant in context.get("expected_initial_sites"):
		if _initial_site_same(pair, start): continue
		rest.append(Vector2i(int(pair[0]), int(pair[1])))
	rest.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	ordered.append(Vector2i(int(start[0]), int(start[1])))
	ordered.append_array(rest)
	return ordered


static func _same_initial_request(record: Dictionary, context: Dictionary) -> bool:
	if record.has("author_context") or context.get("mode") == "author": return same_author_initial_context(record.get("author_context"), context)
	return _initial_site_same(record.get("starting_site"), context.get("starting_site")) and record.get("initial_scenario_id") == context.get("initial_scenario_id")

func _initial_pending_ok(record: Variant, expected: Dictionary) -> bool:
	if not record is Dictionary or not _same_pin(record.get("pin"), expected): return false
	if int(expected.get("format", 0)) == 3:
		return record.size() == 5 and author_initial_context_valid(record.get("author_context")) and _whole(record.get("version"), 2, 2) and record.get("initial_scenario_id") == "" and _initial_site_same(record.get("starting_site"), record.get("author_context", {}).get("starting_site")) and same_author_initial_context(record.get("author_context"), _opening_author_context)
	return record.size() == 4 and _whole(record.get("version"), 1, 1) and _initial_context_ok({"starting_site": record.get("starting_site"), "initial_scenario_id": record.get("initial_scenario_id")})

func _initial_complete_ok(record: Variant) -> bool:
	if not record is Dictionary or not _whole(record.get("first_generation"), 1, 1) or not _same_pin(record.get("pin"), pin) or not _initial_site_same(record.get("starting_site"), _initialization.get("starting_site")) or record.get("initial_scenario_id") != _initialization.get("initial_scenario_id"): return false
	if _initialization.has("author_context"): return record.size() == 6 and _whole(record.get("version"), 2, 2) and same_author_initial_context(record.get("author_context"), _initialization.author_context)
	return record.size() == 5 and _whole(record.get("version"), 1, 1)


func initialization_pending() -> bool:
	return not _initialization.is_empty()


func _derive_initial_context() -> Dictionary:
	if int(pin.format) == 3:
		# P5C-S2: the authored context names the start and every companion Site.
		var authored: Dictionary = source.author_initial_context()
		if not author_initial_context_valid(authored): return fail("INVALID_AUTHOR_CONTEXT")
		var derived_context: Dictionary = {"version": 2, "pin": pin.duplicate(true), "starting_site": authored.starting_site.duplicate(), "initial_scenario_id": "", "author_context": authored.duplicate(true)}
		if not _initial_pending_ok(derived_context, pin): return fail("INVALID_INITIAL_SCENARIO")
		_initialization = derived_context
		var author_checked: Dictionary = _check_initial_record(_marker)
		if not author_checked.ok:
			_initialization = {}
			return author_checked
		return {"ok": true, "context": derived_context}
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
	if int(pin.format) == 3:
		context.version = 2
		context.initial_scenario_id = ""
		context["author_context"] = source.author_initial_context()
	if not _initial_pending_ok(context, pin): return fail("INVALID_INITIAL_SCENARIO")
	_initialization = context
	var checked := _check_initial_record(_marker)
	if not checked.ok: _initialization = {}; return checked
	return {"ok": true, "context": context}


func _check_initial_record(record: Dictionary) -> Dictionary:
	if not _initial_pending_ok(_initialization, pin) or int(record.get("generation", 0)) != 1 or not _same_pin(record.get("pin"), pin) or record.get("sites", {}).size() != _initial_site_coordinates().size() or not str(record.get("transfer_token", "")).is_empty() or not record.get("journey", {}).is_empty(): return fail("INVALID_INITIAL_GENERATION")
	var policy := TechnologyPolicy.candidate(pin)
	if not policy.ok or not TechnologyPolicy.birth_categories_admitted(policy.policy): return fail("TECH_POLICY_CONFLICT")
	var coordinate := Vector2i(int(_initialization.starting_site[0]), int(_initialization.starting_site[1]))
	var key := _site_key(coordinate)
	if not record.sites.has(key) or str(record.get("control", {}).get("active_site_id", "")) != Grid.site_id(str(pin.atlas_id), coordinate) or float(record.control.get("logical_game_seconds", -1.0)) != 0.0: return fail("INVALID_INITIAL_GENERATION")
	var entry: Dictionary = record.sites[key]
	var path := folder.path_join(str(entry.get("path", "")))
	if not str(entry.get("path", "")).begins_with("generations/") or FileAccess.get_sha256(path) != str(entry.get("sha256", "")): return fail("INVALID_INITIAL_GENERATION")
	var loaded := _load_checked(path, coordinate)
	if not loaded.ok: return loaded
	var state: Dictionary = loaded.data.site
	if _initialization.has("author_context"):
		# P5C-S2: every companion must be present and valid before the start is accepted.
		for other: Vector2i in _initial_site_coordinates():
			if other != coordinate and not record.sites.has(_site_key(other)): return fail("INVALID_INITIAL_GENERATION")
		var started: Dictionary = _check_author_initial_state(loaded.data, record, coordinate, path)
		if not started.ok: return started
		# P5C-S3: person ids are unique across every Site of the birth transaction.
		var people: Dictionary = {}
		for start_person: int in RegionTravel._body_records(loaded.data.site).keys(): people[int(start_person)] = true
		for companion_site: Vector2i in _initial_site_coordinates():
			if companion_site == coordinate: continue
			var companion: Dictionary = _check_author_companion_state(record, companion_site)
			if not companion.ok: return companion
			for companion_person: int in RegionTravel._body_records(companion.data.site).keys():
				if people.has(int(companion_person)): return fail("INVALID_INITIAL_POPULATION", "人物編號跨地點重複")
				people[int(companion_person)] = true
		return started
	var scenario := str(_initialization.initial_scenario_id)
	# Neutral part 2: a fresh (no scenario) birth holds the player only as its one-person neutral team; a scenario birth keeps the actor.
	var player_shape_ok: bool = (state.get("actors", {}).is_empty() and _created_player_team(state, 1)) if scenario.is_empty() else (int(state.get("actors", {}).get("player", {}).get("person_id", -1)) == 1 and state.get("actors", {}).size() == 1)
	if int(state.get("minute", -1)) != 0 or float(state.get("phase", -1.0)) != 0.0 or int(state.get("controlled_person_id", -1)) != 1 or not player_shape_ok or state.has("family") or state.has("crowd"): return fail("INVALID_INITIAL_POPULATION")
	if scenario.is_empty():
		if state.has("initial_scenario") or state.get("armies", []).size() != 1 or state.has("technology_artisans"): return fail("INVALID_INITIAL_POPULATION")
	else:
		var receipt: Variant = state.get("initial_scenario")
		if not receipt is Dictionary or receipt.size() != 3 or not _whole(receipt.get("version"), 1, 1) or receipt.get("scenario_id") != scenario or receipt.get("world_id") != str(pin.world_instance_id): return fail("INVALID_INITIAL_SCENARIO")
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
		for companion: Dictionary in _initial_candidate.get("companions", []):
			if FileAccess.get_sha256(str(companion.path)) != str(companion.sha256): return fail("STALE_INITIAL_CANDIDATE")
		return {"ok": true, "data": _initial_candidate.data, "coordinate": _initial_candidate.coordinate, "prepared": true}
	return {"ok": true, "prepared": false}


func prepare_initial_site(data: TerrainData) -> Dictionary:
	if not initialization_pending() or not _marker.is_empty() or not _initial_candidate.is_empty(): return fail("INITIAL_ALREADY_PREPARED")
	var coordinate := _coordinate(data)
	if not coordinate.ok: return coordinate
	if not _initial_site_same([coordinate.site.x, coordinate.site.y], _initialization.starting_site) or str(data.site.get("world_pin", {}).get("world_instance_id", "")) != str(pin.world_instance_id): return fail("INITIAL_PIN_CONFLICT")
	var scenario := str(_initialization.initial_scenario_id)
	if not scenario.is_empty(): data.site.initial_scenario = {"version": 1, "scenario_id": scenario, "world_id": str(pin.world_instance_id)}
	elif data.site.has("initial_scenario"): return fail("INVALID_INITIAL_SCENARIO")
	if float(control.logical_game_seconds) != 0.0 or int(control.fire_clock.sequence) != 0 or float(control.fire_clock.action_seconds) != 0.0: return fail("INVALID_INITIAL_GENERATION")
	data.site.fire_settlement = {"version": 1, "epoch": str(control.fire_clock.epoch), "sequence": 0, "action_seconds": 0.0, "game_seconds": 0.0}
	# P5C-S2: every companion is projected and validated in memory before the
	# start is attached or any file is written.
	var companions: Array = []
	if _initialization.has("author_context"):
		for other: Vector2i in _initial_site_coordinates():
			if other == coordinate.site: continue
			var companion: Dictionary = _author_companion_candidate(other)
			if not companion.ok: return companion
			companions.append(companion)
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
	var sites: Dictionary = {_site_key(coordinate.site): entry}
	var written: Array = []
	for index: int in range(companions.size()):
		# Index 0 is the start Site already written above; companion writes start at 1.
		if initial_write_fault.is_valid() and bool(initial_write_fault.call(index + 1)):
			control = original_control
			return fail("SAVE_IO", "原作者初始化寫入故障（測試注入）")
		var prepared_companion: Dictionary = companions[index]
		var companion_path: String = _generation_path(1, prepared_companion.coordinate)
		var companion_saved: Dictionary = _save_checked(prepared_companion.data, prepared_companion.coordinate, companion_path)
		if not companion_saved.ok:
			control = original_control
			return companion_saved
		var companion_entry: Dictionary = _file_entry(companion_path)
		sites[_site_key(prepared_companion.coordinate)] = companion_entry
		written.append({"coordinate": prepared_companion.coordinate, "path": companion_path, "sha256": str(companion_entry.sha256),
			"id": str(prepared_companion.data.site.id), "fire": prepared_companion.data.site.fire_settlement.duplicate(true)})
	var record: Dictionary = {"format": 1, "generation": 1, "pin": pin.duplicate(true), "sites": sites,
		"control": control.duplicate(true), "transfer_token": "", "journey": {}}
	var checked := _check_initial_record(record)
	if not checked.ok:
		control = original_control
		return checked
	_initial_candidate = {"data": checked.data, "coordinate": coordinate.site, "path": path, "sha256": str(entry.sha256), "generation": 1, "companions": written}
	return {"ok": true, "data": checked.data, "coordinate": coordinate.site, "prepared": true}


# P5C-S3: the controller hands in a populated companion body before the first commit.
func set_companion_birth(site: Vector2i, data: TerrainData) -> Dictionary:
	if not initialization_pending() or not _marker.is_empty() or not _initial_candidate.is_empty(): return fail("INITIAL_ALREADY_PREPARED")
	if not _initialization.has("author_context"): return fail("INVALID_COMPANION_SITE", "no authored birth is pending")
	var start: Vector2i = Vector2i(int(_initialization.starting_site[0]), int(_initialization.starting_site[1]))
	if site == start: return fail("INVALID_COMPANION_SITE", "companion birth offered for the start Site %s" % str(site))
	if not site in _initial_site_coordinates(): return fail("INVALID_COMPANION_SITE", "Site %s is not an expected initial Site of this birth" % str(site))
	if data == null or data.site.is_empty(): return fail("INVALID_COMPANION_SITE", "companion birth state is empty for %s" % str(site))
	# The populated body comes from the roster birth on a projection, which carries no world pin yet.
	# Set it the way _author_companion_candidate does before the shared coordinate check.
	if not data.site.has("world_pin"): data.site.world_pin = pin.duplicate(true)
	var coordinate: Dictionary = _coordinate(data)
	if not coordinate.ok: return fail("INVALID_COMPANION_SITE", "companion %s fails the coordinate/world-pin check: %s %s" % [str(site), str(coordinate.get("code", "")), str(coordinate.get("message", ""))])
	if coordinate.site != site: return fail("INVALID_COMPANION_SITE", "companion birth addresses %s, expected %s" % [str(coordinate.site), str(site)])
	_companion_births[_site_key(site)] = data
	return {"ok": true}


# P5C-S3: every expected Site except the start, in canonical order.
func initial_companion_sites() -> Array:
	var result: Array = []
	if not _initialization.has("author_context"): return result
	var start: Vector2i = Vector2i(int(_initialization.starting_site[0]), int(_initialization.starting_site[1]))
	for site: Vector2i in _initial_site_coordinates():
		if site != start: result.append(site)
	return result


# P5C-S2: canonical list of every Site this birth must publish (start first).
func _initial_site_coordinates() -> Array:
	if _initialization.has("author_context"): return author_initial_site_order(_initialization.author_context)
	return [Vector2i(int(_initialization.starting_site[0]), int(_initialization.starting_site[1]))]


# P5C-S2: companion birth state. Terrain only; any authored population is refused
# here and waits for P5C-S3. Mirrors open_site's fresh genesis for an uncontrolled Site.
func _author_companion_candidate(site: Vector2i) -> Dictionary:
	var projected: Dictionary = source.project_terrain(site, "author_initial")
	if not projected.ok: return projected
	if not _matches_base(projected.base, site): return fail("SAVE_VERSION", "固定地圖版本已變更")
	var data: TerrainData = projected.data
	var supplied: bool = _companion_births.has(_site_key(site))
	if supplied: data = _companion_births[_site_key(site)]
	if not Store._resource_base_matches(data, projected.base): return fail("SAVE_VERSION", "固定資源內容與來源版本不同")
	if data.site.is_empty(): return fail("AUTHOR_INITIAL_EMPTY_SITE", "作者初始地點缺少內容")
	# Population is admitted only as a controller-supplied birth (P5C-S3); bare authored residents are refused.
	if not supplied and (not RegionTravel._body_records(data.site).is_empty() or not data.site.get("armies", []).is_empty() or not data.site.get("residents", []).is_empty()):
		return fail("AUTHOR_POPULATION_UNSUPPORTED", "非起點作者地點的人口須由原出生流程提供")
	if data.site.has("initial_scenario") or data.site.has("crowd") or data.site.has("family"):
		return fail("AUTHOR_POPULATION_UNSUPPORTED", "非起點地點不支援情境、群眾或家族欄位")
	var refreshed: Dictionary = _refresh_boundaries(data, site)
	if not refreshed.ok: return refreshed
	data.site.world_pin = pin.duplicate(true)
	var genesis: Dictionary = _settle_cold_candidate(data, float(control.logical_game_seconds))
	if not genesis.ok: return genesis
	data = genesis.data
	if not _fire_history_empty(data.site): return fail("INVALID_NEW_SITE", "新地點已存在原火攻歷史")
	# Explicit actor presence, as a fresh non-starter Site has it (open_site starter=false, region_save_slot.gd:885-889,
	# site_controller.gd:9574): no resident Actor. terrain_lab.gd cold replay refuses a snapshot with neither the
	# presence version nor a stated empty Actor set (its 5591 guard is not loosened here). Bodies stay in armies.
	if data.site.get("actors", {}).is_empty():
		data.site.actor_presence_version = 1
		data.site.actors = {}
	data.site.fire_settlement = {"version": 1, "epoch": str(control.fire_clock.epoch), "sequence": 0, "action_seconds": 0.0, "game_seconds": float(control.logical_game_seconds)}
	return {"ok": true, "coordinate": site, "data": data}


# P5C-S2: checks one companion file of the generation-1 record.
func _check_author_companion_state(record: Dictionary, coordinate: Vector2i) -> Dictionary:
	var key: String = _site_key(coordinate)
	if not record.sites.has(key): return fail("INVALID_INITIAL_GENERATION")
	var entry: Dictionary = record.sites[key]
	var path: String = folder.path_join(str(entry.get("path", "")))
	if not str(entry.get("path", "")).begins_with("generations/") or FileAccess.get_sha256(path) != str(entry.get("sha256", "")): return fail("INVALID_INITIAL_GENERATION")
	var loaded: Dictionary = _load_checked(path, coordinate)
	if not loaded.ok: return loaded
	var state: Dictionary = loaded.data.site
	if state.has("initial_scenario") or state.has("crowd") or state.has("family") or int(state.get("minute", -1)) != 0 or float(state.get("phase", -1.0)) != 0.0: return fail("INVALID_INITIAL_POPULATION")
	for body: Dictionary in RegionTravel._body_records(state).values():
		if not RegionTravel._able(body): return fail("INVALID_INITIAL_POPULATION", "非起點原人物須可行動")
	var settled: Dictionary = validate_settlement(state, 0.0)
	if not settled.ok or float(settled.pending) != 0.0: return fail("INVALID_INITIAL_GENERATION")
	var fire: Dictionary = validate_fire_settlement(state, record.control.get("fire_clock", {}))
	if not fire.ok or int(state.get("fire_settlement", {}).get("sequence", -1)) != 0: return fail("INVALID_INITIAL_GENERATION")
	return {"ok": true, "data": loaded.data}


func commit_initial_site() -> Dictionary:
	if not initialization_pending(): return fail("NO_TARGET")
	if not _marker.is_empty():
		var recovered := _check_initial_record(_marker)
		if not recovered.ok: return recovered
		var manifested := _finish_initial_manifest()
		return recovered if manifested.ok else manifested
	if _initial_candidate.is_empty() or FileAccess.get_sha256(str(_initial_candidate.path)) != str(_initial_candidate.sha256): return fail("STALE_INITIAL_CANDIDATE")
	var sites := {_site_key(_initial_candidate.coordinate): _file_entry(str(_initial_candidate.path))}
	# P5C-S2: all companions publish in the same generation as the start.
	var clock: Dictionary = control.duplicate(true)
	for companion: Dictionary in _initial_candidate.get("companions", []):
		if FileAccess.get_sha256(str(companion.path)) != str(companion.sha256): return fail("STALE_INITIAL_CANDIDATE")
		sites[_site_key(companion.coordinate)] = _file_entry(str(companion.path))
		var fire: Dictionary = companion.fire
		clock.fire_clock.index[str(companion.id)] = {"coordinate": [companion.coordinate.x, companion.coordinate.y], "active": false, "fire_active": false,
			"sequence": int(fire.sequence), "action_seconds": float(fire.action_seconds), "game_seconds": float(fire.game_seconds)}
	var committed: Dictionary = _publish(sites, clock)
	if not committed.ok: return committed
	return _check_initial_record(_marker)


func finish_initial_birth(receipt: Dictionary) -> Dictionary:
	if not initialization_pending(): return {"ok": true}
	var checked := _check_initial_record(_marker)
	if not checked.ok: return checked
	if receipt.get("complete") != true or receipt.get("owner") != str(control.active_site_id) or int(receipt.get("generation", -1)) != 1 or receipt.get("mode") != "live" or not (receipt.get("backend") in ["gd", "native"]): return fail("COMMITTED_UNBOUND") # Option C: the start Site may open as crowd.
	var manifested := _finish_initial_manifest()
	if not manifested.ok: return manifested
	var path := folder.path_join("manifest.initialized.json")
	var record := {"version": 1, "pin": pin.duplicate(true), "first_generation": 1,
		"starting_site": _initialization.starting_site.duplicate(), "initial_scenario_id": str(_initialization.initial_scenario_id)}
	if _initialization.has("author_context"):
		record.version = 2
		record["author_context"] = _initialization.author_context.duplicate(true)
	if FileAccess.file_exists(path):
		var prior := _read_document(path, 16384)
		if not prior.ok or not _initial_complete_ok(prior.payload): return fail("INVALID_INITIAL_RECEIPT")
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
	var party_host: bool = host is TerrainLab and host.terrain != null and host.terrain.has_meta(&"region_party_owner")
	if not host is TerrainLab or host.site_controller == null or host.site_controller.region_slot != self or prepared.get("travel_host") != host or not party_host and (not host.restore_only or _region_original_labs.get(str(host.terrain.site.id)) != host):
		return fail("INVALID_TRAVEL_HOST")
	var originals: Dictionary = prepared.get("cold_labs", {}).duplicate()
	for battle: Dictionary in prepared.battles.values(): originals[str(battle.lab.terrain.site.id)] = battle.lab
	if not party_host and originals.get(str(host.terrain.site.id)) != host: return fail("INVALID_TRAVEL_HOST")
	var party_original: TerrainLab = prepared.get("travel_party")
	var fingerprint := Marshalls.raw_to_base64(var_to_bytes(outcome.party)).sha256_text()
	if not is_instance_valid(party_original) or party_original.terrain == null or party_original._region_bound_data != party_original.terrain \
			or get_meta(&"region_party_owner_labs", {}).get(token) != party_original or party_original._region_party_token != token \
			or _travel_party_runtime_token != token or str(party_original.terrain.site.id) != "travel:" + token \
			or party_original._region_party_input_hash != fingerprint \
			or party_original.terrain.get_meta(&"region_party_owner", {}).get("party_hash") != fingerprint: return fail("INCOMPLETE_PARTY_PROGRESS")
	if party_host and (party_original != host or not host._region_point_pending.get("interval_complete", false)): return fail("INCOMPLETE_PARTY_PROGRESS")
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
	var deliveries := _region_accept_carried_arrival(clock, token, destination, mapping)
	if not deliveries.ok: return deliveries
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

# A loaded JSON joint position is a float pair ([1.0, 0.0]). Typed Array equality
# treats 1.0 and 1 as different, so joint positions are checked as integral
# numbers and then compared in the integer domain. Int-valued pairs keep their result.
static func joint_integral_pair(value: Variant) -> bool:
	if not value is Array or value.size() != 2: return false
	for axis: int in range(2):
		var number: Variant = value[axis]
		if not (number is int or number is float) or not is_finite(float(number)) or float(number) != floorf(float(number)): return false
	return true

static func joint_pair_equals(value: Variant, coordinate: Vector2i) -> bool:
	return joint_integral_pair(value) and int(value[0]) == coordinate.x and int(value[1]) == coordinate.y

func _region_player_endpoint_location(status: Dictionary, party: Dictionary, coordinate: Vector2i, event: Dictionary) -> Dictionary:
	if str(party.get("mode", "land")) == "sea":
		return _region_endpoint_sea_location(status.get("plan", {}), party, coordinate)
	var contact: Dictionary = event.get("payload", {}).get("contact_receipt", {})
	if not contact.is_empty():
		if float(contact.get("at", -1.0)) != float(control.logical_game_seconds): return fail("STALE_REGION_CONTACT")
		var position: Dictionary = contact.get("second", {}).get("position", {})
		if not joint_pair_equals(position.get("site"), coordinate) or status.site != coordinate:
			return _region_original_boundary_location("player", status.token, party, coordinate, event)
		var cell: Variant = position.get("cell")
		if not joint_integral_pair(cell): return fail("INVALID_JOINT_ENDPOINT")
		return {"ok": true, "entry": Vector2i(int(cell[0]), int(cell[1])),
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
	var position := _region_current_land_position(party, planned.plan, str(region_registry().parties[token].plan_path))
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
	var seed: Dictionary = existing.duplicate(true)
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
		# An ordinary arrival cannot replace the existing exact siege consumer.
		seed.mode = "live" if player_present else ("cold_exact" if str(seed.get("kind", "")) == "siege" else "formula_active")
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
	var party_owner := owner.is_empty()
	if party_owner:
		var token := str(region_travel_journey().get("token", ""))
		if not _safe_part(token): return {}
		owner = "travel:" + token
	var mode: Dictionary = region_registry().modes.get(owner, {})
	if mode.get("mode") != "live" or mode.get("backend") != "gd" or mode.get("activation", {}).get("complete") != true or int(mode.get("generation", -1)) != int(_marker.get("generation", 0)):
		return {}
	if not GameplayClock.validate_mode(mode, owner, float(control.logical_game_seconds)).ok or float(mode.game_seconds) != float(control.logical_game_seconds) or float(mode.action_seconds) != float(control.fire_clock.action_seconds) or int(mode.activation.get("generation", -1)) != int(_marker.get("generation", 0)) or str(mode.consumer) != ("original_party" if party_owner else "original_site"): return {}
	var original: TerrainLab
	var party: Dictionary = {}
	if party_owner:
		var selected := _region_life_current_party(owner.trim_prefix("travel:"))
		if not selected.ok: return {}
		original = selected.lab
		party = selected.party
	elif region_owner_lab.is_valid():
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
	var point_pending := not original._region_point_pending.is_empty()
	if remaining <= TerrainLab.ACTION_TIME_EPSILON:
		# An already committed land step may outlast down. Only its actual
		# original movement state supplies that future close, never a new order.
		remaining = _region_player_committed_close_action(person)
		if remaining <= TerrainLab.ACTION_TIME_EPSILON and not point_pending: return {}
	if party_owner:
		if absf(float(party.upkeep.get("at", -1.0)) - float(control.logical_game_seconds)) > TerrainLab.ACTION_TIME_EPSILON \
				or absf(float(party.upkeep.get("owner_action_seconds", -1.0)) - float(control.fire_clock.action_seconds)) > TerrainLab.ACTION_TIME_EPSILON:
			return {}
	else:
		var settlement := validate_settlement(original.terrain.site, float(control.logical_game_seconds))
		if not settlement.ok or settlement.legacy or float(settlement.pending) > 0.00000001: return {}
		var fire: Dictionary = original.terrain.site.get("fire_settlement", {})
		if not validate_fire_settlement(original.terrain.site, control.fire_clock).ok or int(fire.get("sequence", -1)) != int(control.fire_clock.sequence) or float(fire.get("action_seconds", -1.0)) != float(control.fire_clock.action_seconds) or float(fire.get("game_seconds", -1.0)) != float(control.logical_game_seconds): return {}
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
		if payload.get("controlled") != true or payload.get("death") != true or payload.has("family_control_transition"): continue
		if party_owner:
			var target := _region_life_original_owner(event)
			if not target.ok or target.lab != original or int(target.person_id) != identity: continue
		elif int(payload.get("person_id", -1)) != identity or payload.get("destination_site") != owner: continue
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
	if payload.has("family_control_transition"):
		var family := _region_family_life_source(event)
		return family.ok and family.get("family_complete", false)
	if payload.has("entered_party") or str(control.active_site_id).is_empty() and str(event.owner).trim_prefix("travel:") == str(region_travel_journey().get("token", "")):
		var target := _region_life_original_owner(event)
		return target.ok and not target.get("family_complete", false) and float(target.person.hp) <= 0.0
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
	if data.has_meta(&"region_party_owner"):
		var target := _region_life_original_owner(event)
		return target.ok and not target.get("family_complete", false) and target.lab.terrain == data
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

func _region_capture_party_graph(token: String, party: Dictionary, endpoint_payload: Dictionary = {}, read_only: bool = false) -> Dictionary:
	var originals: Dictionary = get_meta(&"region_party_owner_labs", {})
	var original: TerrainLab = originals.get(token)
	if not is_instance_valid(original):
		return fail("COMMITTED_UNBOUND", "live party 原完整 Lab 不在，不能丟棄已接受 graph") if party.upkeep.has("live") else {"ok": true, "original_live_graph": {}}
	if not original.has_method("capture_region_party_owner_graph"): return fail("MISSING_ORIGINAL_PARTY_GRAPH")
	var complete: bool = pending_region_events().is_empty() and original._region_point_pending.is_empty() and original.site_controller._pending_deaths.is_empty()
	var context := region_party_checkpoint_context(token, "region_checkpoint" if complete else "region_barrier", complete,
		endpoint_payload if not endpoint_payload.is_empty() else {"party_checkpoint": token})
	if not context.ok: return context
	return original.capture_region_party_owner_graph(token, party, self, context.context, read_only)

func _region_join_npc_party_reference(clock: Dictionary, token: String, destination_token: String,
		mapping: Dictionary, source_proof: Dictionary) -> Dictionary:
	var registry: Dictionary = clock.region_gameplay
	var reference: Dictionary = registry.parties.get(token, {})
	if reference.get("controller") != "npc" or reference.get("phase") != "travelling" \
			or reference.get("party_path") != source_proof.get("path") or reference.get("party_sha256") != source_proof.get("sha256"):
		return fail("STALE_REGION_PARTY")
	reference.phase = "joined"
	reference.entered_party = destination_token
	reference.arrival_mapping = mapping.duplicate(true)
	reference.arrival_game_seconds = float(clock.logical_game_seconds)
	registry.modes.erase("travel:" + token)
	for queued: Dictionary in registry.events:
		if queued.status != "pending" or queued.payload.get("token", "") != token: continue
		if str(queued.kind) == "life":
			var key := str(int(queued.payload.get("event", {}).get("person_id", -1)))
			if not mapping.maps.person.has(key): return fail("INVALID_LIFE_MAPPING")
			var source_file := _region_life_party_document(token, str(source_proof.path), str(source_proof.sha256))
			if not source_file.ok: return source_file
			var person_ref: Dictionary = source_file.party.content.travel_identity.refs.person.get(key, {})
			if person_ref.is_empty(): return fail("INVALID_LIFE_MAPPING")
			queued.payload.person_reference = person_ref.duplicate(true)
			queued.payload.party_source_proof = source_proof.duplicate(true)
			queued.payload.arrival_mapping = mapping.duplicate(true)
		queued.payload.entered_party = destination_token
	# The original event owner, accepted time, ID and sequence are preserved.
	return {"ok": true}

func _region_life_canonical(event: Dictionary) -> Dictionary:
	for current: Dictionary in region_registry().events:
		if current.id != event.get("id"): continue
		if current.status != "pending" or var_to_bytes(current) != var_to_bytes(event):
			return fail("STALE_REGION_EVENT")
		if current.kind not in ["life", "player_death"] or not current.payload is Dictionary:
			return fail("INVALID_REGION_LIFE_EVENTS")
		return {"ok": true, "event": current}
	return fail("STALE_REGION_EVENT")

func _region_life_current_party(token: String) -> Dictionary:
	var selected := region_travel_party() if str(region_travel_journey().get("token", "")) == token else _region_npc_party(token)
	if not selected.ok: return selected
	return region_original_party_runtime_proof(token, selected.party)

func _region_life_effect_receipt(event: Dictionary) -> bool:
	var payload: Dictionary = event.get("payload", {})
	var record: Dictionary = payload.get("event", payload)
	var receipt: Variant = payload.get("effect_receipt")
	if not receipt is Dictionary or receipt.size() != 5: return false
	for field: String in ["event_id", "person_id", "effects_complete", "game_seconds", "action_seconds"]:
		if not receipt.has(field): return false
	return receipt.event_id == event.get("id") and receipt.person_id == record.get("person_id") \
		and receipt.effects_complete == true and GameplayClock.seconds(receipt.game_seconds) \
		and float(receipt.game_seconds) == float(event.get("at", -1.0)) and GameplayClock.seconds(receipt.action_seconds) \
		and float(receipt.action_seconds) <= float(control.fire_clock.action_seconds) + TerrainLab.ACTION_TIME_EPSILON

func _region_life_original_owner(event: Dictionary) -> Dictionary:
	var canonical := _region_life_canonical(event)
	if not canonical.ok: return canonical
	var payload: Dictionary = canonical.event.payload
	if payload.has("family_control_transition"): return _region_family_life_source(canonical.event)
	var record: Variant = payload.get("event", payload)
	if not record is Dictionary or not GameplayClock.whole(record.get("person_id"), 1):
		return fail("INVALID_REGION_LIFE_EVENTS")
	var token := str(payload.get("entered_party", str(event.owner).trim_prefix("travel:")))
	if not str(event.owner).begins_with("travel:") or not _safe_part(token):
		return fail("INVALID_REGION_LIFE_OWNER")
	var current := _region_life_current_party(token)
	if not current.ok: return current
	var source_ref: Dictionary = {}
	if payload.has("party_source_proof"):
		if not payload.party_source_proof is Dictionary: return fail("INVALID_REGION_LIFE_SOURCE")
		var source_party := _region_life_source_proof(event, payload.party_source_proof)
		if not source_party.ok: return source_party
		source_ref = source_party.party.content.travel_identity.refs.person.get(str(int(record.person_id)), {})
	else:
		if str(event.owner) != "travel:" + token or payload.has("entered_party") and str(payload.entered_party) != token:
			return fail("MISSING_REGION_LIFE_SOURCE")
		source_ref = current.party.content.travel_identity.refs.person.get(str(int(record.person_id)), {})
	var reference: Variant = payload.get("person_reference", source_ref)
	if not reference is Dictionary or reference != source_ref:
		var diagnostic_proof: Dictionary = payload.get("party_source_proof", {})
		var refused := fail("INVALID_REGION_LIFE_REFERENCE")
		refused.diagnostic = {"actual_reference": reference.duplicate(true) if reference is Dictionary else reference,
			"expected_reference": source_ref.duplicate(true), "reference_type": typeof(reference),
			"actual_lineage_type": typeof(reference.get("lineage")) if reference is Dictionary else TYPE_NIL,
			"expected_lineage_type": typeof(source_ref.get("lineage")), "person_id": record.person_id,
			"person_id_type": typeof(record.person_id), "source_ref_keys": source_ref.keys(),
			"event_id": str(canonical.event.id), "token": token,
			"source_path": str(diagnostic_proof.get("path", "")), "source_sha256": str(diagnostic_proof.get("sha256", ""))}
		return refused
	var identity := _region_life_reference_id(current.party.content.travel_identity, reference)
	if identity <= 0: return fail("STALE_REGION_LIFE_OWNER")
	var original: TerrainLab = current.lab
	var person := original._original_person_target(identity)
	if person.is_empty(): return fail("STALE_REGION_LIFE_OWNER")
	return {"ok": true, "lab": original, "party": current.party, "proof": current.proof, "person_id": identity,
		"person_reference": reference, "person": person, "event": canonical.event, "family_complete": false}

func _region_life_party_context(document: Dictionary) -> Dictionary:
	var raw: Variant = document.get("payload", {}).get("original_live_graph")
	if not raw is Dictionary or raw.size() != 2 or raw.get("encoding") != "godot_var_v1" or not raw.get("value") is String:
		return fail("INVALID_FAMILY_TRANSITION")
	var graph: Variant = bytes_to_var(Marshalls.base64_to_raw(str(raw.value)))
	if not graph is Dictionary or graph.size() != 5 or graph.get("version") != 1 \
			or graph.get("token") != document.party.get("party_id") \
			or graph.get("party_hash") != Marshalls.raw_to_base64(var_to_bytes(document.party)).sha256_text() \
			or not graph.get("owners") is Dictionary or not graph.owners.get("scene") is Dictionary:
		return fail("INVALID_FAMILY_TRANSITION")
	var checked := RegionCheckpoint.validate_context(graph.get("context"))
	if not checked.ok or graph.owners.scene.get("context") != graph.context:
		return fail("INVALID_FAMILY_TRANSITION")
	if absf(float(document.party.upkeep.get("at", -1.0)) - float(graph.context.game_seconds)) > TerrainLab.ACTION_TIME_EPSILON \
			or absf(float(document.party.upkeep.get("owner_action_seconds", -1.0)) - float(graph.context.action_seconds)) > TerrainLab.ACTION_TIME_EPSILON:
		return fail("INVALID_FAMILY_TRANSITION")
	return {"ok": true, "context": checked.context}

func _region_life_party_document(token: String, relative: String, sha: String) -> Dictionary:
	if not _safe_part(token) or not _travel_relative(relative, token) or relative.is_empty() or sha.length() != 64:
		return fail("INVALID_REGION_LIFE_SOURCE")
	var document := _travel_document(relative, sha, {})
	if not document.ok: return document
	var payload: Dictionary = document.payload
	if payload.get("version") != 1 or payload.get("token") != token or not _same_pin(payload.get("pin"), pin) \
			or payload.get("encoding") != "godot_var_v1" or not payload.get("party") is String:
		return fail("INVALID_REGION_LIFE_SOURCE")
	var body: Variant = bytes_to_var(Marshalls.base64_to_raw(str(payload.party)))
	if not body is Dictionary or body.get("party_id") != token \
			or not RegionTravel.validate_identity(body.get("content", {}).get("travel_identity")):
		return fail("INVALID_REGION_LIFE_SOURCE")
	return {"ok": true, "party": body, "payload": payload}

static func _region_life_reference_id(identity: Dictionary, reference: Dictionary) -> int:
	if not RegionTravel.validate_identity(identity) or reference.size() != 3 \
			or reference.get("type") != "person" or not reference.get("namespace") is String \
			or str(reference.namespace).is_empty() or not GameplayClock.whole(reference.get("lineage"), 1):
		return -1
	var found := -1
	for key: String in identity.refs.person:
		if identity.refs.person[key] != reference: continue
		if found != -1: return -1
		found = int(key)
	return found

func _region_life_source_proof(event: Dictionary, proof: Dictionary) -> Dictionary:
	const FIELDS := ["version", "token", "owner", "generation", "revision", "path", "sha256", "party_hash",
		"game_seconds", "action_seconds", "controller", "phase"]
	if proof.size() != FIELDS.size(): return fail("INVALID_REGION_LIFE_SOURCE")
	for field: String in FIELDS:
		if not proof.has(field): return fail("INVALID_REGION_LIFE_SOURCE")
	if proof.version != 1 or proof.owner != event.owner or proof.owner != "travel:" + str(proof.token) \
			or not GameplayClock.whole(proof.generation, 0) or int(proof.generation) > int(_marker.get("generation", 0)) \
			or not GameplayClock.whole(proof.revision, 0) or int(proof.revision) > int(region_registry().revision) \
			or proof.controller not in ["player", "npc"] \
			or not GameplayClock.seconds(proof.game_seconds) or not GameplayClock.seconds(proof.action_seconds) \
			or float(proof.game_seconds) < float(event.at) - TerrainLab.ACTION_TIME_EPSILON \
			or float(proof.game_seconds) > float(control.logical_game_seconds) + TerrainLab.ACTION_TIME_EPSILON \
			or float(proof.action_seconds) > float(control.fire_clock.action_seconds) + TerrainLab.ACTION_TIME_EPSILON:
		return fail("INVALID_REGION_LIFE_SOURCE")
	var document := _region_life_party_document(str(proof.token), str(proof.path), str(proof.sha256))
	if not document.ok: return document
	var party: Dictionary = document.party
	if party.controller != proof.controller or Marshalls.raw_to_base64(var_to_bytes(party)).sha256_text() != proof.party_hash \
			or absf(float(party.upkeep.get("at", -1.0)) - float(proof.game_seconds)) > TerrainLab.ACTION_TIME_EPSILON \
			or absf(float(party.upkeep.get("owner_action_seconds", -1.0)) - float(proof.action_seconds)) > TerrainLab.ACTION_TIME_EPSILON:
		return fail("INVALID_REGION_LIFE_SOURCE")
	return document

func _region_live_party_candidate(interval: Dictionary, party: Dictionary) -> Dictionary:
	if absf(float(party.get("upkeep", {}).get("at", -1.0)) - float(interval.get("game_begin", -2.0))) > 0.00000001:
		return fail("UNSETTLED_PARTY")
	var candidate: Dictionary = party.duplicate(true)
	candidate.upkeep.at = float(interval.game_end)
	candidate.upkeep.owner_action_seconds = float(interval.action_end)
	return {"ok": true, "party": candidate, "source_party": party, "at": float(interval.game_end),
		"action_seconds": float(interval.action_end) - float(interval.action_begin), "metres": 0.0,
		"consumed_rations": 0.0, "events": [], "arrived": false, "reroute_ready": false}

func _region_live_party_world(token: String, party: Dictionary, plan: Dictionary, event: Dictionary, contact_role: String) -> Dictionary:
	var people := RegionTravel._body_records(party.content)
	var refs: Dictionary = party.content.travel_identity.refs
	var world_people := {}
	var world_vehicles := {}
	var previous: Dictionary = party.get("upkeep", {}).get("live", {}).get("frame", {})
	if not previous.is_empty():
		if not RegionTravel._frame_pair(previous.get("world_origin")) or not RegionTravel._frame_pair(previous.get("size")): return fail("INVALID_PARTY_FRAME")
		var origin := Vector2i(int(previous.world_origin[0]), int(previous.world_origin[1]))
		for identity: Variant in people:
			var raw: Variant = people[identity].get("cell")
			if not RegionTravel._frame_pair(raw): return fail("MISSING_ORIGINAL_POSITION")
			var at := origin + Vector2i(int(raw[0]), int(raw[1]))
			world_people[str(identity)] = {"reference": refs.person[str(identity)].duplicate(), "world_cell": [at.x, at.y]}
		for identity: String in party.content.get("vehicles", {}):
			var vehicle: Dictionary = party.content.vehicles[identity]
			var cell := int(vehicle.cell)
			var at := origin + Vector2i(cell % int(previous.size[0]), cell / int(previous.size[0]))
			world_vehicles[identity] = {"reference": refs.vehicle[identity].duplicate(), "world_cell": [at.x, at.y],
				"pose": previous.vehicles.get(identity, {}).get("pose", {}).duplicate(true)}
		return {"ok": true, "people": world_people, "vehicles": world_vehicles}
	if str(party.get("mode", "land")) == "sea":
		var current := region_sea_pose_projection(plan, party)
		if not current.ok: return current
		for identity: String in party.content.vehicles:
			var vehicle: Dictionary = party.content.vehicles[identity]
			var pose: Dictionary = current.poses.get(identity, {}).duplicate(true)
			if str(vehicle.get("kind", "")) != "ship" or not pose.get("world_anchor") is Array or pose.world_anchor.size() != 2: return fail("CORRUPT_SEA_CURSOR")
			# Original Vector2 pose query returns floats, and a plan read back from its
			# saved JSON document carries its facings as JSON numbers. Only validated
			# integral grid endpoints and facings become typed pairs; the interpolated
			# anchor stays exact.
			for field: String in ["from", "to", "facing", "from_facing", "to_facing"]:
				if not pose.has(field): continue
				var endpoint: Variant = pose[field]
				if not endpoint is Array or endpoint.size() != 2 or not Store._integer(endpoint[0], -2147483648, 2147483647) or not Store._integer(endpoint[1], -2147483648, 2147483647): return fail("CORRUPT_SEA_CURSOR")
				pose[field] = [int(endpoint[0]), int(endpoint[1])]
			# The cursor may name the next action before it starts (duration 0). That Ship
			# rests at the action's start pose and owns no move, exactly as the original Lab
			# frame later records it, so the frame carries no action for it either.
			if float(pose.get("duration_action_seconds", 0.0)) <= 0.0:
				for field: String in ["action", "from", "to", "from_facing", "to_facing", "weight", "elapsed_action_seconds", "duration_action_seconds"]: pose.erase(field)
			var accepted: Array = pose.get("from", pose.world_anchor) if float(pose.get("duration_action_seconds", 0.0)) > 0.0 else pose.world_anchor
			if accepted.size() != 2 or not Store._integer(accepted[0], -2147483648, 2147483647) or not Store._integer(accepted[1], -2147483648, 2147483647): return fail("CORRUPT_SEA_CURSOR")
			var at := Vector2i(int(accepted[0]), int(accepted[1]))
			world_vehicles[identity] = {"reference": refs.vehicle[identity].duplicate(), "world_cell": [at.x, at.y], "pose": pose.duplicate(true)}
		for identity: Variant in people:
			var body: Dictionary = people[identity]
			var boat_id := str(body.get("embarked_vehicle_id", ""))
			var boat: Dictionary = party.content.vehicles.get(boat_id, {})
			var vehicle: Dictionary = world_vehicles.get(boat_id, {})
			if boat.is_empty() or vehicle.is_empty(): return fail("NOT_EMBARKED")
			var pose: Dictionary = vehicle.pose
			var anchor := Vector2(float(pose.world_anchor[0]), float(pose.world_anchor[1]))
			var facing := Vector2(float(pose.facing[0]), float(pose.facing[1]))
			if pose.has("action"):
				var next := Vector2(float(pose.to_facing[0]), float(pose.to_facing[1]))
				facing = facing.rotated(facing.angle_to(next) * float(pose.get("weight", 0.0)))
			var local := RegionTravel.Ship.local_position(str(boat.ship_type), int(body.get("berth_id", -1)))
			var saved: Variant = body.get("ship_deck_position")
			if saved is Array and saved.size() == 2: local = Vector2(float(saved[0]), float(saved[1]))
			if not local.is_finite(): return fail("NOT_EMBARKED")
			var at := Vector2i((anchor + Vector2(-facing.y, facing.x) * local.x + facing * local.y + Vector2.ONE * 0.5).floor())
			world_people[str(identity)] = {"reference": refs.person[str(identity)].duplicate(), "world_cell": [at.x, at.y]}
		return {"ok": true, "people": world_people, "vehicles": world_vehicles}
	var position: Dictionary = event.get("payload", {}).get("contact_receipt", {}).get(contact_role, {}).get("position", {})
	var context := _region_party_frame_context(party)
	if not context.ok: return context
	if position.is_empty():
		var idle: Dictionary = region_travel_journey().get("position", {}) if str(region_travel_journey().get("token", "")) == token \
			else region_registry().parties.get(token, {}).get("position", {})
		var route: Dictionary = _region_current_land_position(party, plan, str(party.upkeep.get("plan_id", ""))) if not plan.is_empty() else idle
		var located := _region_contact_position(party, plan, route, context.context, {})
		if not located.ok: return located
		position = located.position
	# Selected route/contact documents use JSON numbers; validate exact
	# integers at this wire boundary before constructing the typed frame.
	var position_site: Variant = position.get("site")
	var position_cell: Variant = position.get("cell")
	if not position_site is Array or position_site.size() != 2 or not position_cell is Array or position_cell.size() != 2:
		return fail("MISSING_ORIGINAL_POSITION")
	for axis: int in range(2):
		if not Store._integer(position_site[axis], -2147483648, 2147483647) or not Store._integer(position_cell[axis], 0, 99):
			return fail("MISSING_ORIGINAL_POSITION")
	var raw_leader: Variant = people.get(int(party.leader_person_id), {}).get("cell")
	if not RegionTravel._frame_pair(raw_leader): return fail("MISSING_ORIGINAL_POSITION")
	var origin := Vector2i(int(position.site[0]) * 100, -int(position.site[1]) * 100)
	var leader := origin + Vector2i(int(position.cell[0]), int(position.cell[1]))
	var translation := leader - Vector2i(int(raw_leader[0]), int(raw_leader[1]))
	for identity: Variant in people:
		var raw: Variant = people[identity].get("cell")
		if not RegionTravel._frame_pair(raw): return fail("MISSING_ORIGINAL_POSITION")
		var at := translation + Vector2i(int(raw[0]), int(raw[1]))
		world_people[str(identity)] = {"reference": refs.person[str(identity)].duplicate(), "world_cell": [at.x, at.y]}
	var step: Dictionary = plan.get("steps", [])[int(position.step_index)] if not plan.is_empty() else {}
	for identity: String in party.content.get("vehicles", {}):
		var vehicle: Dictionary = party.content.vehicles[identity]
		var pose: Dictionary = step.get("vehicle_poses", {}).get(identity, {})
		var at := translation + Vector2i(int(vehicle.cell) % 100, int(vehicle.cell) / 100)
		if RegionTravel._frame_pair(pose.get("anchor")): at = origin + Vector2i(int(pose.anchor[0]), int(pose.anchor[1]))
		world_vehicles[identity] = {"reference": refs.vehicle[identity].duplicate(), "world_cell": [at.x, at.y], "pose": pose.duplicate(true)}
	return {"ok": true, "people": world_people, "vehicles": world_vehicles}

func _region_party_base_proof(proof: Dictionary) -> Dictionary:
	const FIELDS := ["version", "token", "owner", "generation", "revision", "path", "sha256", "party_hash",
		"game_seconds", "action_seconds", "controller", "phase"]
	var base := {}
	for field: String in FIELDS:
		if not proof.has(field): return {}
		base[field] = proof[field]
	return base

func _region_party_document(token: String, party: Dictionary, graph: Dictionary = {}) -> Dictionary:
	if not party.get("content") is Dictionary: return fail("CORRUPT_SAVE", "Original party content")
	var boarding: Dictionary = preload("res://scripts/terrain_lab/site_boarding_link_contract.gd").save_guard(party.content)
	if not boarding.ok: return boarding
	var payload := {"version": 1, "token": token, "pin": pin.duplicate(true), "encoding": "godot_var_v1",
		"party": Marshalls.raw_to_base64(var_to_bytes(party))}
	if not graph.is_empty():
		if graph.get("token") != token or graph.get("party_hash") != Marshalls.raw_to_base64(var_to_bytes(party)).sha256_text() \
				or not RegionCheckpoint.validate_context(graph.get("context")).ok:
			return fail("INVALID_REGION_GRAPH", "原 graph 未指向即將共同提交的唯一 party body")
		payload.original_live_graph = {"encoding": "godot_var_v1", "value": Marshalls.raw_to_base64(var_to_bytes(graph))}
	return {"ok": true, "payload": payload}

func _region_party_frame_context(party: Dictionary) -> Dictionary:
	var prepared := prepare_region_route_context(null, party)
	if not prepared.ok: return prepared
	var source_context: Dictionary = prepared.context
	var selected_generation := int(_marker.get("generation", 0))
	var selected_revision := int(region_registry().revision)
	var selected_sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	var provider := func(site: Vector2i) -> Dictionary:
		if selected_generation != int(_marker.get("generation", 0)) or selected_revision != int(region_registry().revision): return fail("STALE_PARTY_GEOMETRY")
		var value: Variant = source_context.effective_terrain.call(site)
		if not value is Dictionary or not value.get("ok", false): return value if value is Dictionary else fail("INVALID_PROVIDER")
		var selected: Dictionary = selected_sites.get(_site_key(site), {})
		if selected.is_empty():
			if value.get("data") != null: return fail("UNSELECTED_PARTY_GEOMETRY", "原 visited geometry 未被共同 marker 選定")
			return {"ok": true, "data": null, "visited": false}
		if value.get("data") == null or FileAccess.get_sha256(folder.path_join(str(selected.path))) != str(selected.sha256): return fail("CORRUPT_SAVE")
		return {"ok": true, "data": value.data, "revision": str(value.revision), "visited": true,
			"proof": {"generation": selected_generation, "revision": selected_revision, "site": [site.x, site.y],
				"path": str(selected.path), "sha256": str(selected.sha256)}}
	return {"ok": true, "context": {"effective_terrain": provider}}

## The selected party document payload. The original proof reads it several
## times per shared step; hashing, reading and parsing the same write-once file
## each time dominated the step. Every caller still validates and decodes the
## payload itself, so each result is built fresh from the same verified bytes.
func _region_selected_document(token: String, relative: String, sha256: String) -> Dictionary:
	var cached: Dictionary = _region_selected_document_cache.get(token, {})
	if str(cached.get("path", "")) == relative and str(cached.get("sha256", "")) == sha256:
		return {"ok": true, "payload": cached.payload}
	var document := _travel_document(relative, sha256, {})
	if document.ok: _region_selected_document_cache[token] = {"path": relative, "sha256": sha256, "payload": document.payload}
	return document

## shared: a cache hit returns the cached validated values themselves, not copies.
## Only a caller that never mutates the returned party or graph may pass it.
func _region_selected_party_document(token: String, require_current: bool = true, shared: bool = false) -> Dictionary:
	var recovered := _recover_control()
	if not recovered.ok: return recovered
	var reference: Dictionary
	var controller := ""
	var journey := region_travel_journey()
	if not journey.is_empty() and str(journey.token) == token:
		reference = journey
		controller = "player"
	else:
		reference = region_registry().parties.get(token, {})
		controller = str(reference.get("controller", ""))
	if controller not in ["player", "npc"] or not _travel_relative(reference.get("party_path"), token) \
			or str(reference.get("party_path", "")).is_empty() or str(reference.get("party_sha256", "")).length() != 64:
		return fail("STALE_REGION_PARTY", "真 marker 未選定原 party 文件")
	# A document already decoded and fully validated under the same selected path,
	# SHA-256 and controller yields fresh copies of the same values; only the clock
	# check, which depends on the current endpoint, runs again in its own place.
	var decoded_cache: Dictionary = _region_selected_decoded_cache.get(token, {})
	if str(decoded_cache.get("path", "")) == str(reference.party_path) and str(decoded_cache.get("sha256", "")) == str(reference.party_sha256) \
			and str(decoded_cache.get("controller", "")) == controller and _same_pin(decoded_cache.get("pin"), pin):
		if shared:
			return _region_selected_party_result(token, reference, controller, decoded_cache.party, str(decoded_cache.fingerprint), decoded_cache.graph, require_current)
		return _region_selected_party_result(token, reference, controller, decoded_cache.party.duplicate(true),
			str(decoded_cache.fingerprint), decoded_cache.graph.duplicate(true), require_current)
	var document := _region_selected_document(token, str(reference.party_path), str(reference.party_sha256))
	if not document.ok: return document
	var payload: Dictionary = document.payload
	if payload.get("version") != 1 or payload.get("token") != token or not _same_pin(payload.get("pin"), pin) \
			or payload.get("encoding") != "godot_var_v1" or not payload.get("party") is String:
		return fail("CORRUPT_SAVE", "真 party 文件不是此世界原 selected owner")
	var party: Variant = bytes_to_var(Marshalls.base64_to_raw(str(payload.party)))
	if not party is Dictionary or party.get("party_id") != token or party.get("controller") != controller \
			or not RegionTravel.validate_identity(party.get("content", {}).get("travel_identity")):
		return fail("CORRUPT_SAVE", "真 party 閉包非法")
	if require_current and (absf(float(party.get("upkeep", {}).get("at", -1.0)) - float(control.logical_game_seconds)) > 0.00000001 \
			or absf(float(party.upkeep.get("owner_action_seconds", control.fire_clock.action_seconds)) - float(control.fire_clock.action_seconds)) > 0.00000001):
		return fail("UNSETTLED_PARTY", "真 selected party 尚未完成同一共同雙時間端點")
	var boarding: Dictionary = preload("res://scripts/terrain_lab/site_boarding_link_contract.gd").save_guard(party.content)
	if not boarding.ok: return boarding
	var fingerprint := Marshalls.raw_to_base64(var_to_bytes(party)).sha256_text()
	var graph := {}
	if payload.has("original_live_graph"):
		var encoded: Variant = payload.original_live_graph
		if not encoded is Dictionary or encoded.size() != 2 or encoded.get("encoding") != "godot_var_v1" or not encoded.get("value") is String:
			return fail("CORRUPT_REGION_GRAPH")
		var decoded: Variant = bytes_to_var(Marshalls.base64_to_raw(str(encoded.value)))
		if not decoded is Dictionary or decoded.size() != 5 or decoded.get("version") != 1 or decoded.get("token") != token \
				or decoded.get("party_hash") != fingerprint or not decoded.get("context") is Dictionary or not decoded.get("owners") is Dictionary \
				or not RegionCheckpoint.validate_context(decoded.context).ok:
			return fail("CORRUPT_REGION_GRAPH", "party body 與完整原 graph 不是同一份提交")
		graph = decoded
	_region_selected_decoded_cache[token] = {"path": str(reference.party_path), "sha256": str(reference.party_sha256), "controller": controller,
		"pin": pin.duplicate(true), "party": party.duplicate(true), "fingerprint": fingerprint, "graph": graph.duplicate(true)}
	return _region_selected_party_result(token, reference, controller, party, fingerprint, graph, false)

## The selected proof result from validated values. require_current repeats the
## same clock check for a cached document; the miss path already ran it.
func _region_selected_party_result(token: String, reference: Dictionary, controller: String, party: Dictionary,
		fingerprint: String, graph: Dictionary, require_current: bool) -> Dictionary:
	if require_current and (absf(float(party.get("upkeep", {}).get("at", -1.0)) - float(control.logical_game_seconds)) > 0.00000001 \
			or absf(float(party.upkeep.get("owner_action_seconds", control.fire_clock.action_seconds)) - float(control.fire_clock.action_seconds)) > 0.00000001):
		return fail("UNSETTLED_PARTY", "真 selected party 尚未完成同一共同雙時間端點")
	var phase := str(party.upkeep.get("live", {}).get("phase", reference.get("phase", "travelling")))
	var proof := {"version": 1, "token": token, "owner": "travel:" + token, "generation": int(_marker.get("generation", 0)),
		"revision": int(region_registry().revision), "path": str(reference.party_path), "sha256": str(reference.party_sha256),
		"party_hash": fingerprint, "game_seconds": float(party.upkeep.at), "action_seconds": float(party.upkeep.get("owner_action_seconds", control.fire_clock.action_seconds)),
		"controller": controller, "phase": phase}
	return {"ok": true, "proof": proof, "party": party, "original_live_graph": graph}

func commit_region_live_party(token: String, party: Dictionary, source_proof: Dictionary,
		binding: Dictionary, incoming: Dictionary = {}) -> Dictionary:
	# The raw candidate is proved before original runtime IDs are composed. Both
	# transformations are pure and repeatable from these exact selected sources.
	var selected := region_live_party_candidate_proof(token, party, source_proof)
	if not selected.ok: return selected
	if not binding.get("ok", false) or not binding.get("original_live_graph") is Dictionary \
			or not binding.get("party") is Dictionary or not binding.get("runtime_mapping") is Dictionary:
		return fail("MISSING_ORIGINAL_PARTY_GRAPH")
	for hook: String in ["can_publish", "publish", "discard"]:
		if not binding.get(hook) is Callable or not binding[hook].is_valid(): return fail("MISSING_ORIGINAL_PARTY_BIND")
	if binding.can_publish.call() != true: return fail("STALE_REGION_BIND_TICKET")
	var runtime_owner: GDScript = load("res://scripts/terrain_lab/site_region_party_runtime_mapping.gd")
	if runtime_owner == null: return fail("MISSING_ORIGINAL_PARTY_RUNTIME_MAPPING")
	var runtime_sources: Array = []
	for original: Dictionary in selected.sources:
		runtime_sources.append({"party": original.party, "projected": original.projected_party, "maps": original.maps})
	var composed: Dictionary = runtime_owner.compose_candidate(party, runtime_sources, binding.runtime_mapping)
	if not composed.ok: return composed
	if var_to_bytes(composed.party) != var_to_bytes(binding.party):
		return fail("PARTY_RUNTIME_CLOSURE", "原完整 runtime mapping 必須精確重建同一真 body 候選")
	var actual: Dictionary = binding.party
	var document := _region_party_document(token, actual, binding.original_live_graph)
	if not document.ok: return document
	var player_source: Dictionary = selected.sources[0]
	var npc_primary: bool = player_source.party.get("controller") == "npc"
	var generation := int(player_source.proof.generation) + 1
	var npc_token := str(selected.sources[1].party.party_id) if selected.sources.size() == 2 else ""
	var relative := "travel/%s/party_live_%09d_%s.json" % [token, generation, Crypto.new().generate_random_bytes(8).hex_encode()]
	var written := _write_new_document(folder.path_join(relative), document.payload)
	if not written.ok: return written
	var next_control := control.duplicate(true)
	for queued: Dictionary in next_control.region_gameplay.events:
		if queued.status != "pending" or queued.owner != "travel:" + token or str(queued.kind) not in ["life", "player_death"]: continue
		var person := str(int(queued.payload.get("event", queued.payload).get("person_id", -1)))
		var reference: Dictionary = player_source.party.content.travel_identity.refs.person.get(person, {})
		if reference.is_empty() or actual.content.travel_identity.refs.person.get(person) != reference:
			return fail("INVALID_LIFE_MAPPING", "原玩家生命端點必須仍引用同一真 typed body")
		queued.payload.entered_party = token
		queued.payload.person_reference = reference.duplicate(true)
		queued.payload.party_source_proof = player_source.proof.duplicate(true)
	if not npc_token.is_empty():
		var retired := _region_join_npc_party_reference(next_control, npc_token, token, selected.mapping, selected.sources[1].proof)
		if not retired.ok: return retired
	if not npc_primary: next_control.active_site_id = ""
	next_control.region_gameplay.revision = int(next_control.region_gameplay.revision) + 1
	var mode := GameplayClock.activate_mode(next_control.region_gameplay, "travel:" + token, "committed-unbound", generation,
		"gd", "original_party", float(next_control.logical_game_seconds), float(next_control.fire_clock.action_seconds), {})
	if not mode.ok: return mode
	var sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	var cold := _collect_cold_checkpoint(generation, sites, next_control)
	if not cold.ok: return cold
	var parties := collect_region_party_checkpoint(generation, next_control, token if npc_primary else "")
	if not parties.ok: return parties
	var checked := region_live_party_candidate_proof(token, party, source_proof)
	if not checked.ok: return checked
	if binding.can_publish.call() != true: return fail("STALE_REGION_BIND_TICKET")
	var journey := region_travel_journey()
	if npc_primary:
		next_control.region_gameplay.parties[token].party_path = relative
		next_control.region_gameplay.parties[token].party_sha256 = FileAccess.get_sha256(folder.path_join(relative))
	else:
		journey.party_path = relative
		journey.party_sha256 = FileAccess.get_sha256(folder.path_join(relative))
	var published := _publish(sites, next_control, str(_marker.get("transfer_token", "")), journey)
	if not published.ok: return published
	if npc_primary: _region_npc_party_runtime[token] = actual
	else:
		_travel_party_runtime = actual
		_travel_party_runtime_token = token
	if not npc_token.is_empty():
		_region_npc_party_runtime.erase(npc_token)
		_region_npc_plan_runtime.erase(npc_token)
	var proof := region_live_party_proof(token)
	if not proof.ok: return _region_committed_unbound("真 party 與完整 graph 已提交，待重讀原 selected 文件", {"generation": generation, "token": token, "bind_result": proof})
	var bound: Variant = binding.publish.call(proof.proof)
	if not bound is Dictionary or not bound.get("ok", false) or bound.get("complete") != true \
			or bound.get("owner") != "travel:" + token or int(bound.get("generation", -1)) != generation:
		return _region_committed_unbound("真 party 與完整 graph 已共同提交；只允重試原 bind", {"generation": generation, "token": token, "bind_result": bound})
	var enabled := activate_region_mode("travel:" + token, "live", "original_party", bound, "gd")
	if not enabled.ok: return enabled
	return {"ok": true, "complete": true, "generation": generation, "token": token,
		"party": actual, "receipt": bound, "proof": proof.proof, "incoming": incoming}

func prepare_region_live_party(event: Dictionary) -> Dictionary:
	var npc_pair := str(event.get("payload", {}).get("contact_receipt", {}).get("kind", "")) == "npc_sea_sweep_boundary"
	if npc_pair:
		var guarded := _region_validate_npc_sea_pair_event(event)
		if not guarded.ok or not guarded.get("valid", false): return guarded if not guarded.ok else fail("STALE_REGION_CONTACT")
	var checkpoint := _region_checkpoint_carried_delivery(str(event.id)) if npc_pair else checkpoint_region_travel()
	if not checkpoint.ok: return checkpoint
	var journey := region_travel_journey()
	var token := str(event.payload.contact_receipt.primary_token) if npc_pair else str(journey.get("token", ""))
	var player := region_live_party_proof(token)
	if not player.ok: return player
	var planned := _region_npc_plan(token) if npc_pair else region_travel_plan()
	if not planned.ok: return planned
	var player_world := _region_live_party_world(token, player.party, planned.plan, event, "second")
	if not player_world.ok: return player_world
	var npc_token := str(event.get("payload", {}).get("token", ""))
	var npc := {}
	var npc_world := {}
	if not npc_token.is_empty() and npc_token != token and str(region_registry().parties.get(npc_token, {}).get("phase", "")) == "travelling":
		npc = region_live_party_proof(npc_token)
		if not npc.ok: return npc
		var npc_plan := _region_npc_plan(npc_token)
		if not npc_plan.ok: return npc_plan
		npc_world = _region_live_party_world(npc_token, npc.party, npc_plan.plan, event, "first")
		if not npc_world.ok: return npc_world
	var minimum := Vector2i(2147483647, 2147483647)
	var maximum := Vector2i(-2147483647, -2147483647)
	for group: Dictionary in [player_world] + ([npc_world] if not npc.is_empty() else []):
		for record: Dictionary in group.people.values() + group.vehicles.values():
			var at := Vector2i(int(record.world_cell[0]), int(record.world_cell[1]))
			minimum = Vector2i(mini(minimum.x, at.x), mini(minimum.y, at.y))
			maximum = Vector2i(maxi(maximum.x, at.x), maxi(maximum.y, at.y))
		for identity: String in group.vehicles:
			var original: Dictionary = player.party.content.vehicles.get(identity, {}) if group == player_world else npc.party.content.vehicles.get(identity, {})
			if str(original.get("kind", "")) != "ship": continue
			var record: Dictionary = group.vehicles[identity]
			var pose: Dictionary = record.pose
			var heading := Vector2i(int(pose.facing[0]), int(pose.facing[1]))
			var swept := RegionTravel.Ship.footprint(str(original.ship_type), Vector2i(int(record.world_cell[0]), int(record.world_cell[1])), heading)
			if float(pose.get("duration_action_seconds", 0.0)) > 0.0:
				swept = Ship.swept_footprint(str(original.ship_type), Vector2i(int(pose.from[0]), int(pose.from[1])),
					Vector2i(int(pose.from_facing[0]), int(pose.from_facing[1])), Vector2i(int(pose.to[0]), int(pose.to[1])),
					Vector2i(int(pose.to_facing[0]), int(pose.to_facing[1])))
			for cell: Vector2i in swept:
				minimum = Vector2i(mini(minimum.x, cell.x), mini(minimum.y, cell.y))
				maximum = Vector2i(maxi(maximum.x, cell.x), maxi(maximum.y, cell.y))
	var origin := Vector2i(Grid.floor_div(minimum.x, 100), Grid.floor_div(minimum.y, 100)) * 100
	var size := (Vector2i(Grid.floor_div(maximum.x, 100), Grid.floor_div(maximum.y, 100)) + Vector2i.ONE) * 100 - origin
	if size.x not in [100, 200] or size.y not in [100, 200]: return fail("PARTY_FRAME_TOO_WIDE", "原 shared body closure 超過本次連續 frame 範圍")
	var frame := {"version": 1, "world_origin": [origin.x, origin.y], "size": [size.x, size.y],
		"game_seconds": float(control.logical_game_seconds), "action_seconds": float(control.fire_clock.action_seconds),
		"people": player_world.people, "vehicles": player_world.vehicles}
	var projected := RegionTravel.project_party_frame(player.party, frame)
	if not projected.ok: return projected
	var original_ship := _region_install_live_ship_moves(projected.party, player_world, frame)
	if not original_ship.ok: return original_ship
	projected.party = original_ship.party
	var incoming := {}
	var candidate: Dictionary = projected.party
	var proof: Dictionary = player.proof.duplicate(true)
	proof.coordinate_projection = projected.projection
	proof.sources = [player.proof.duplicate(true)]
	proof.sources[0].coordinate_projection = projected.projection.duplicate(true)
	if not npc.is_empty():
		var npc_frame := frame.duplicate(true)
		npc_frame.people = npc_world.people
		npc_frame.vehicles = npc_world.vehicles
		var npc_projected := RegionTravel.project_party_frame(npc.party, npc_frame)
		if not npc_projected.ok: return npc_projected
		original_ship = _region_install_live_ship_moves(npc_projected.party, npc_world, npc_frame)
		if not original_ship.ok: return original_ship
		npc_projected.party = original_ship.party
		var joined: Dictionary = RegionTravel.join_party(candidate, npc_projected.party, int(player.proof.generation) + 1, person_allocator_enabled())
		if not joined.ok: return joined
		candidate = joined.party
		incoming = {"token": npc_token, "source_party": npc.party, "proof": npc.proof, "mapping": joined.mapping,
			"coordinate_projection": npc_projected.projection, "incoming_events": joined.incoming_events, "player_source": player.party}
		proof.mapping = joined.mapping
		proof.sources.append(npc.proof.duplicate(true))
		proof.sources[1].coordinate_projection = npc_projected.projection.duplicate(true)
		for old: String in npc_world.people: frame.people[str(joined.mapping.maps.person[old])] = npc_world.people[old]
		for old: String in npc_world.vehicles: frame.vehicles[str(joined.mapping.maps.vehicle[old])] = npc_world.vehicles[old]
	candidate.upkeep.live = {"version": 1, "phase": "live", "upkeep": "liveBody", "event_id": str(event.id), "frame": frame}
	var geometry := region_live_party_geometry(candidate)
	if not geometry.ok: return geometry
	candidate.upkeep.live.geometry_proof = geometry.geometry_proof
	proof.candidate_hash = Marshalls.raw_to_base64(var_to_bytes(candidate)).sha256_text()
	return {"ok": true, "token": token, "party": candidate, "source_party": player.party, "source_proof": player.proof,
		"proof": proof, "incoming": incoming, "coordinate_projection": projected.projection, "geometry": geometry}

func region_live_party_candidate_proof(token: String, candidate: Dictionary, proof: Dictionary) -> Dictionary:
	if not proof.get("sources") is Array or proof.sources.size() not in [1, 2] or proof.get("candidate_hash") != Marshalls.raw_to_base64(var_to_bytes(candidate)).sha256_text():
		return fail("INVALID_PARTY_SOURCE_PROOF")
	var frame: Dictionary = candidate.get("upkeep", {}).get("live", {}).get("frame", {})
	var event_id := str(candidate.get("upkeep", {}).get("live", {}).get("event_id", ""))
	var event := {}
	for queued: Dictionary in region_registry().events:
		if str(queued.id) == event_id and str(queued.status) == "pending": event = queued
	if event.is_empty() or float(event.at) > float(control.logical_game_seconds) + 0.00000001:
		return fail("STALE_REGION_EVENT", "live materialize 須真同刻待點事件")
	var sources := []
	var expected := {}
	var mapping := {}
	for index: int in proof.sources.size():
		var raw: Variant = proof.sources[index]
		if not raw is Dictionary or not raw.get("coordinate_projection") is Dictionary: return fail("INVALID_PARTY_SOURCE_PROOF")
		var base := _region_party_base_proof(raw)
		var selected := region_live_party_proof(str(base.get("token", "")))
		if not selected.ok or base != selected.get("proof"): return selected if not selected.ok else fail("STALE_REGION_PARTY_PROOF")
		var npc_pair := str(event.payload.get("contact_receipt", {}).get("kind", "")) == "npc_sea_sweep_boundary"
		if npc_pair:
			var guarded := _region_validate_npc_sea_pair_event(event)
			if not guarded.ok or not guarded.get("valid", false) or proof.sources.size() != 2: return guarded if not guarded.ok else fail("STALE_REGION_CONTACT")
		if index == 0 and (str(base.token) != token or base.controller != ("npc" if npc_pair else "player")) or index == 1 and (base.controller != "npc" or str(base.token) == token):
			return fail("INVALID_PARTY_SOURCE_PROOF")
		if npc_pair and str(base.token) != str(event.payload.contact_receipt.primary_token if index == 0 else event.payload.token): return fail("INVALID_PARTY_SOURCE_PROOF")
		var planned: Dictionary = region_travel_plan() if index == 0 and base.controller == "player" else _region_npc_plan(str(base.token))
		if not planned.ok: return planned
		var world := _region_live_party_world(str(base.token), selected.party, planned.plan, event, "second" if index == 0 else "first")
		if not world.ok: return world
		var projection: Dictionary = raw.coordinate_projection
		if projection.get("world_origin") != frame.get("world_origin") or projection.get("size") != frame.get("size"): return fail("PARTY_FRAME_COORDINATE")
		var projected := RegionTravel.project_party_coordinates(selected.party, projection)
		if not projected.ok: return projected
		var ship_candidate := _region_install_live_ship_moves(projected.party, world, frame)
		if not ship_candidate.ok: return ship_candidate
		projected.party = ship_candidate.party
		for kind: String in ["people", "vehicles"]:
			if projection[kind].size() != world[kind].size(): return fail("PARTY_FRAME_CLOSURE")
			for key: String in world[kind]:
				var record: Dictionary = projection[kind].get(key, {})
				var at := [int(record.to[0]) + int(frame.world_origin[0]), int(record.to[1]) + int(frame.world_origin[1])]
				if record.get("reference") != world[kind][key].reference or at != world[kind][key].world_cell:
					return fail("PARTY_FRAME_COORDINATE", "投影位置必須是原 contact／cursor 的真 World cell")
				var body_key := str(proof.get("mapping", {}).get("maps", {}).get("person" if kind == "people" else "vehicle", {}).get(key, key)) if index == 1 else key
				var frame_record: Dictionary = frame.get(kind, {}).get(body_key, {})
				if frame_record.get("reference") != world[kind][key].reference or frame_record.get("world_cell") != world[kind][key].world_cell \
						or kind == "vehicles" and frame_record.get("pose", {}) != world[kind][key].get("pose", {}):
					return fail("PARTY_FRAME_COORDINATE", "唯一frame不得變造原真body／paid Ship pose")
		if index == 0:
			expected = projected.party
		else:
			var joined: Dictionary = RegionTravel.join_party(expected, projected.party, int(base.generation) + 1, person_allocator_enabled())
			if not joined.ok: return joined
			mapping = joined.mapping
			if mapping != proof.get("mapping"): return fail("INVALID_PARTY_JOIN_MAPPING")
			expected = joined.party
		sources.append({"party": selected.party, "proof": base, "original_live_graph": selected.original_live_graph,
			"coordinate_projection": projection, "projected_party": projected.party, "maps": {} if index == 0 else mapping.maps})
	for field: String in ["person_ids", "team_ids", "vehicle_ids", "leader_person_id", "controller", "content"]:
		if var_to_bytes(expected.get(field)) != var_to_bytes(candidate.get(field)): return fail("PARTY_BODY_CLOSURE", "候選必須由真 selected sources 原 projection／typed closure 精確重建")
	var upkeep: Dictionary = candidate.upkeep.duplicate(true)
	upkeep.erase("live")
	var expected_upkeep: Dictionary = expected.upkeep.duplicate(true)
	expected_upkeep.erase("live")
	if var_to_bytes(upkeep) != var_to_bytes(expected_upkeep): return fail("PARTY_CLOCK_CLOSURE", "候選不可變造原 upkeep／life／距離／雙時間")
	var geometry := region_live_party_geometry(candidate, candidate.upkeep.live.get("geometry_proof", {}))
	if not geometry.ok: return geometry
	return {"ok": true, "sources": sources, "mapping": mapping, "party": candidate, "geometry": geometry}

func region_live_party_geometry(party: Dictionary, expected_geometry: Dictionary = {}) -> Dictionary:
	var frame: Dictionary = party.get("upkeep", {}).get("live", {}).get("frame", {})
	if frame.get("game_seconds") != control.logical_game_seconds or frame.get("action_seconds") != control.fire_clock.action_seconds:
		return fail("STALE_PARTY_FRAME", "原 body frame 不在共同双時間端點")
	var context := _region_party_frame_context(party)
	if not context.ok: return context
	var geometry := RegionRoute.party_frame_geometry(source, frame, context.context)
	if not geometry.ok: return geometry
	if not expected_geometry.is_empty():
		if expected_geometry.get("version") != 1 or expected_geometry.get("world_origin") != geometry.geometry_proof.world_origin \
				or expected_geometry.get("size") != geometry.geometry_proof.size or not expected_geometry.get("sources") is Array \
				or expected_geometry.sources.size() != geometry.geometry_proof.sources.size(): return fail("STALE_PARTY_GEOMETRY")
		for index: int in expected_geometry.sources.size():
			var before: Dictionary = expected_geometry.sources[index]
			var current: Dictionary = geometry.geometry_proof.sources[index]
			for field: String in ["site", "offset", "visited", "navigation_hash"]:
				if before.get(field) != current.get(field): return fail("STALE_PARTY_GEOMETRY", "真 selected geometry 已變，須原 graph 重驗")
			# A common checkpoint may renew the selected generation while keeping
			# exactly the same derived geometry. Its new proof is always re-read.
	return geometry

func region_live_party_proof(token: String) -> Dictionary:
	return _region_selected_party_document(token, true)

func region_live_party_required(event: Dictionary, status: Dictionary) -> Dictionary:
	if not bool(status.get("pending", false)): return {"ok": true, "required": false}
	var player := region_travel_party()
	if not player.ok: return player
	if not player.party.get("upkeep", {}).get("live", {}).is_empty(): return {"ok": true, "required": true}
	var raw: Variant = event.get("payload", {}).get("site", [status.site.x, status.site.y])
	if not joint_integral_pair(raw): return fail("INVALID_JOINT_ENDPOINT")
	var coordinate := Vector2i(int(raw[0]), int(raw[1]))
	var player_location := _region_player_endpoint_location(status, player.party, coordinate, event)
	if not player_location.ok:
		return {"ok": true, "required": true} if player_location.get("code") == "MISSING_ORIGINAL_BOUNDARY_VIEW" else player_location
	var npc_token := str(event.get("payload", {}).get("token", ""))
	if not npc_token.is_empty() and npc_token != str(player.party.party_id) \
			and str(region_registry().parties.get(npc_token, {}).get("phase", "")) == "travelling":
		var npc_location := _region_npc_endpoint_location(npc_token, coordinate, event)
		if not npc_location.ok:
			return {"ok": true, "required": true} if npc_location.get("code") == "MISSING_ORIGINAL_BOUNDARY_VIEW" else npc_location
	return {"ok": true, "required": false}

func region_original_party_runtime_proof(token: String, party: Dictionary) -> Dictionary:
	var actual: Dictionary = {}
	var journey: Dictionary = region_travel_journey()
	if not journey.is_empty() and str(journey.get("token", "")) == token:
		if _travel_party_runtime_token != token or not is_same(_travel_party_runtime, party): return fail("STALE_REGION_PARTY_OWNER")
		actual = _travel_party_runtime
	else:
		if not _region_npc_party_runtime.has(token) or not is_same(_region_npc_party_runtime[token], party): return fail("STALE_REGION_PARTY_OWNER")
		actual = _region_npc_party_runtime[token]
	var originals: Dictionary = get_meta(&"region_party_owner_labs", {})
	var original: TerrainLab = originals.get(token)
	var fingerprint := Marshalls.raw_to_base64(var_to_bytes(actual)).sha256_text()
	if not is_instance_valid(original) or original.site_controller == null or original.site_controller.region_slot != self \
			or original.terrain == null or original._region_bound_data != original.terrain \
			or original._region_party_token != token or original._region_party_input_hash != fingerprint \
			or str(original.terrain.site.get("id", "")) != "travel:" + token \
			or original.terrain.get_meta(&"region_party_owner", {}).get("party_hash") != fingerprint:
		return fail("COMMITTED_UNBOUND", "原 runtime party 必須指向同一完整原 Lab")
	var receipt: Dictionary = original.region_bind_receipt(original.terrain)
	if not receipt.get("complete", false) or not receipt.get("owners_restored", false): return fail("COMMITTED_UNBOUND")
	if actual.get("party_id") != token or not RegionTravel.validate_identity(actual.get("content", {}).get("travel_identity")) \
			or absf(float(actual.get("upkeep", {}).get("at", -1.0)) - float(control.logical_game_seconds)) > 0.00000001 \
			or absf(float(actual.upkeep.get("owner_action_seconds", -1.0)) - float(control.fire_clock.action_seconds)) > 0.00000001:
		return fail("UNSETTLED_PARTY")
	var mode: Dictionary = region_registry().modes.get("travel:" + token, {})
	if not GameplayClock.validate_mode(mode, "travel:" + token, float(control.logical_game_seconds)).ok \
			or str(mode.get("consumer", "")) not in ["original_region_travel", "original_party"] \
			or str(mode.get("backend", "")) != "gd" \
			or int(mode.get("generation", -1)) != int(_marker.get("generation", 0)) \
			or absf(float(mode.get("game_seconds", -1.0)) - float(control.logical_game_seconds)) > 0.00000001 \
			or absf(float(mode.get("action_seconds", -1.0)) - float(control.fire_clock.action_seconds)) > 0.00000001:
		return fail("STALE_REGION_PARTY_MODE")
	# This proof only reads the selected document. Its selected_party and
	# original_live_graph are the cached validated values; callers read them only.
	var durable: Dictionary = _region_selected_party_document(token, false, true)
	if not durable.ok: return durable
	if int(durable.proof.generation) != int(mode.generation) or int(durable.proof.revision) != int(region_registry().revision):
		return fail("STALE_REGION_PARTY_MODE")
	if durable.party.get("controller") != actual.get("controller") \
			or durable.party.content.travel_identity.namespace != actual.content.travel_identity.namespace:
		return fail("STALE_REGION_PARTY_PROOF")
	var proof: Dictionary = durable.proof.duplicate(true)
	proof.party_hash = fingerprint
	proof.game_seconds = float(control.logical_game_seconds)
	proof.action_seconds = float(control.fire_clock.action_seconds)
	proof.phase = str(actual.upkeep.get("live", {}).get("phase", proof.phase))
	return {"ok": true, "party": actual, "lab": original, "proof": proof,
		"selected_party": durable.party, "original_live_graph": durable.original_live_graph}

func region_party_checkpoint_context(token: String, purpose: String, effects_complete: bool,
		endpoint_payload: Dictionary = {}) -> Dictionary:
	if not _safe_part(token): return fail("INVALID_PARTY_OWNER")
	var registry := region_registry()
	var mode: Dictionary = registry.modes.get("travel:" + token, {})
	var context := {"purpose": purpose, "mode": "live", "source_generation": int(_marker.get("generation", 0)),
		"runtime_revision": int(registry.revision), "token": "party_capture_" + Crypto.new().generate_random_bytes(16).hex_encode(),
		"game_seconds": float(control.logical_game_seconds), "action_seconds": float(control.fire_clock.action_seconds),
		"fire_epoch": str(control.fire_clock.epoch), "fire_sequence": int(control.fire_clock.sequence),
		"interval_complete": true, "effects_complete": effects_complete, "mode_revision": int(mode.get("revision", 0)),
		"backend": "gd", "events": pending_region_events().duplicate(true), "endpoint_payload": endpoint_payload.duplicate(true)}
	var checked := RegionCheckpoint.validate_context(context)
	return {"ok": true, "context": context} if checked.ok else checked

func validate_region_live_party_proof(token: String, party: Dictionary, proof: Dictionary) -> Dictionary:
	var selected := region_live_party_proof(token)
	if not selected.ok: return selected
	if selected.proof != proof or party.get("party_id") != token \
			or Marshalls.raw_to_base64(var_to_bytes(party)).sha256_text() != str(proof.get("party_hash", "")):
		return fail("STALE_REGION_PARTY_PROOF", "原 party 文件／G／revision／雙時間已變")
	return selected

func _region_checkpoint_carried_delivery(event_id: String) -> Dictionary:
	if not region_original_endpoint_checkpoint.is_valid(): return fail("MISSING_REGION_CHECKPOINT_CONSUMER")
	var result: Variant = region_original_endpoint_checkpoint.call({"carried_delivery": event_id, "effects_complete": true})
	if not result is Dictionary or not result.get("ok", false): return result if result is Dictionary else fail("INVALID_REGION_CHECKPOINT_CONSUMER")
	return {"ok": true}

func _commit_region_party_family_remote(token: String, reference: Dictionary, observed: Dictionary,
		family: Dictionary) -> Dictionary:
	# Settle/persist original bodies before deriving either candidate. The final
	# source and target remain jointly selected by just one subsequent marker.
	var authority := _region_family_player_authority()
	if not authority.ok or authority.token != token: return authority if not authority.ok else fail("WRONG_FAMILY_OWNER")
	if var_to_bytes(authority.family) != var_to_bytes(family): return fail("STALE_FAMILY")
	var checkpoint := checkpoint_region_travel()
	if not checkpoint.ok: return checkpoint
	var selected := region_live_party_proof(token)
	if not selected.ok: return selected
	var target := resolve_region_family_owner(reference)
	if not target.ok: return target
	if target.owner == "travel:" + token or target.person_reference != observed.person_reference: return fail("STALE_FAMILY_PERSON")
	var target_ready := _region_family_target_ready(target)
	if not target_ready.ok: return target_ready
	var candidate := _region_family_remote_candidates(selected.party, target, target_ready.state, reference)
	if not candidate.ok: return candidate
	var transition := {"version": 1, "source_person_id": int(selected.party.content.get("controlled_person_id", selected.party.leader_person_id)),
		"target": reference.duplicate(true), "person_reference": target.person_reference.duplicate(true),
		"source_party_hash": str(selected.proof.party_hash), "destination_owner": str(target.owner),
		"destination_source_hash": str(target_ready.hash)}
	var authorized := validate_region_family_departure_transition(token, candidate.party, selected.proof, transition)
	if not authorized.ok: return authorized
	var host: TerrainLab = authority.lab
	if not is_instance_valid(host) or not host.has_method("prepare_region_party_family_depart_bind"):
		return fail("MISSING_ORIGINAL_PARTY_BIND")
	var source_binding: Dictionary = host.prepare_region_party_family_depart_bind(token, candidate.party, self, selected.proof, transition)
	if not source_binding.ok: return source_binding
	var bindings: Array = [source_binding]
	var target_binding := {}
	var target_candidate: Dictionary = {}
	var target_token := ""
	var target_site := Vector2i.ZERO
	var target_data: TerrainData
	if str(target.owner).begins_with("travel:"):
		target_token = str(target.owner).trim_prefix("travel:")
		var target_selected: Dictionary = target_ready.selected
		target_candidate = target_selected.party.duplicate(true)
		target_candidate.controller = "player"
		target_candidate.leader_person_id = int(target.person_id)
		target_candidate.content = candidate.destination_state.duplicate(true)
		if not host.has_method("prepare_region_party_family_takeover_bind"):
			return _region_family_discard_bindings(bindings, fail("MISSING_ORIGINAL_PARTY_BIND"))
		target_binding = host.prepare_region_party_family_takeover_bind(target_token, target_candidate, self, target_selected.proof, transition)
	else:
		var coordinate := _coordinate(target.data)
		if not coordinate.ok: return _region_family_discard_bindings(bindings, coordinate)
		target_site = coordinate.site
		target_data = Env.navigation_for_state(target.data, candidate.destination_state)
		target_data.set_meta(&"region_bind_source", target.data)
		target_binding = host.prepare_region_owner_bind(target_data, "live", self)
	if not target_binding.get("ok", false): return _region_family_discard_bindings(bindings, target_binding)
	bindings.append(target_binding)
	for binding: Dictionary in bindings:
		for hook: String in ["can_publish", "publish", "discard"]:
			if not binding.get(hook) is Callable or not binding[hook].is_valid():
				return _region_family_discard_bindings(bindings, fail("MISSING_ORIGINAL_PARTY_BIND"))
		if binding.can_publish.call() != true: return _region_family_discard_bindings(bindings, fail("STALE_REGION_BIND_TICKET"))
	if not source_binding.get("party") is Dictionary or var_to_bytes(source_binding.party) != var_to_bytes(candidate.party):
		return _region_family_discard_bindings(bindings, fail("FAMILY_BODY_CLOSURE"))
	var generation := int(_marker.get("generation", 0)) + 1
	var source_relative := "travel/%s/party_family_source_%09d_%s.json" % [token, generation, Crypto.new().generate_random_bytes(8).hex_encode()]
	var source_document := _region_party_document(token, source_binding.party, source_binding.original_live_graph)
	if not source_document.ok: return _region_family_discard_bindings(bindings, source_document)
	var written := _write_new_document(folder.path_join(source_relative), source_document.payload)
	if not written.ok: return _region_family_discard_bindings(bindings, written)
	var source_sha := FileAccess.get_sha256(folder.path_join(source_relative))
	var next_control := control.duplicate(true)
	var next_journey := {}
	var target_relative := ""
	var target_sha := ""
	var sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	var target_original_reference: Dictionary = {}
	if not target_token.is_empty():
		target_original_reference = region_registry().parties[target_token].duplicate(true)
		next_control.region_gameplay.parties[target_token].phase = "controlled"
		next_control.active_site_id = ""
	else:
		next_control.active_site_id = str(target.owner)
	next_control.region_gameplay.revision = int(next_control.region_gameplay.revision) + 1
	var cold := _collect_cold_checkpoint(generation, sites, next_control)
	if not cold.ok: return _region_family_discard_bindings(bindings, cold)
	var parties := collect_region_party_checkpoint(generation, next_control)
	if not parties.ok: return _region_family_discard_bindings(bindings, parties)
	if not target_token.is_empty():
		if not target_binding.get("party") is Dictionary or var_to_bytes(target_binding.party) != var_to_bytes(target_candidate):
			return _region_family_discard_bindings(bindings, fail("FAMILY_BODY_CLOSURE"))
		target_relative = "travel/%s/party_family_target_%09d_%s.json" % [target_token, generation, Crypto.new().generate_random_bytes(8).hex_encode()]
		var document := _region_party_document(target_token, target_binding.party, target_binding.original_live_graph)
		if not document.ok: return _region_family_discard_bindings(bindings, document)
		written = _write_new_document(folder.path_join(target_relative), document.payload)
		if not written.ok: return _region_family_discard_bindings(bindings, written)
		target_sha = FileAccess.get_sha256(folder.path_join(target_relative))
		var journey := _region_family_target_journey(target_token, target_original_reference, target_candidate, target_relative, target_sha)
		if not journey.ok: return _region_family_discard_bindings(bindings, journey)
		next_journey = journey.journey
		next_control.region_gameplay.parties[target_token].party_path = target_relative
		next_control.region_gameplay.parties[target_token].party_sha256 = target_sha
	else:
		if not target_binding.get("data") is TerrainData or not target_binding.get("save_candidate") is Callable:
			return _region_family_discard_bindings(bindings, fail("MISSING_REGION_BIND_PREFLIGHT"))
		var path := _generation_path(generation, target_site)
		var saved: Dictionary = target_binding.save_candidate.call(target_binding.data, path)
		if not saved.ok: return _region_family_discard_bindings(bindings, saved)
		var readback := _load_checked(path, target_site)
		if not readback.ok: return _region_family_discard_bindings(bindings, readback)
		target_data = readback.data
		sites[_site_key(target_site)] = _file_entry(path)
		target_relative = str(sites[_site_key(target_site)].path)
		target_sha = str(sites[_site_key(target_site)].sha256)
		for owner: String in next_control.fire_clock.index: next_control.fire_clock.index[owner].active = false
		var fire: Dictionary = target_data.site.get("fire_settlement", {})
		if not fire.is_empty():
			next_control.fire_clock.index[str(target.owner)] = {"coordinate": [target_site.x, target_site.y], "active": true,
				"fire_active": Runtime.fire_active(target_data), "sequence": int(fire.sequence),
				"action_seconds": float(fire.action_seconds), "game_seconds": float(fire.game_seconds)}
	var old_journey := region_travel_journey()
	next_control.region_gameplay.parties[token] = _region_family_source_npc_reference(candidate.party,
		old_journey, source_relative, source_sha, transition)
	var source_mode := GameplayClock.activate_mode(next_control.region_gameplay, "travel:" + token, "committed-unbound", generation,
		"gd", "original_party", float(next_control.logical_game_seconds), float(next_control.fire_clock.action_seconds), {})
	if not source_mode.ok: return _region_family_discard_bindings(bindings, source_mode)
	var target_mode := GameplayClock.activate_mode(next_control.region_gameplay, str(target.owner), "committed-unbound", generation,
		"gd", "original_party" if not target_token.is_empty() else "original_site",
		float(next_control.logical_game_seconds), float(next_control.fire_clock.action_seconds), {})
	if not target_mode.ok: return _region_family_discard_bindings(bindings, target_mode)
	var queued := _region_family_transfer_queue(next_control, selected.party, transition, generation,
		source_relative, source_sha, target_relative, target_sha, int(target.person_id))
	if not queued.ok: return _region_family_discard_bindings(bindings, queued)
	# Revalidate selected originals and BOTH prepared graph tickets last. A
	# failure above leaves the old marker/body/control solely authoritative.
	authorized = validate_region_family_departure_transition(token, candidate.party, selected.proof, transition)
	if not authorized.ok: return _region_family_discard_bindings(bindings, authorized)
	for binding: Dictionary in bindings:
		if binding.can_publish.call() != true: return _region_family_discard_bindings(bindings, fail("STALE_REGION_BIND_TICKET"))
	var committed := _publish(sites, next_control, str(_marker.get("transfer_token", "")), next_journey)
	if not committed.ok: return _region_family_discard_bindings(bindings, committed)
	_travel_party_runtime.clear()
	_travel_party_runtime_token = ""
	_travel_party_cache.clear()
	_travel_plan_cache.clear()
	_region_npc_party_runtime[token] = candidate.party
	var source_selected := region_live_party_proof(token)
	if not source_selected.ok: return _region_committed_unbound("原source NPC完整graph已提交，待真private bind", {"generation": generation, "token": token})
	var source_bound: Dictionary = source_binding.publish.call(source_selected.proof)
	if not source_bound.get("ok", false) or source_bound.get("complete") != true:
		return _region_committed_unbound("原source NPC唯一body已提交，完整graph待private bind", {"generation": generation, "token": token, "bind_result": source_bound})
	var activation := source_bound.duplicate(true)
	activation.mode = "cold_exact"
	activation.consumer = "original_party"
	var source_enabled := activate_region_mode("travel:" + token, "cold_exact", "original_party", activation, "gd")
	if not source_enabled.ok: return source_enabled
	var target_bound := {}
	if not target_token.is_empty():
		_region_npc_party_runtime.erase(target_token)
		_region_npc_plan_runtime.erase(target_token)
		_travel_party_runtime = target_candidate
		_travel_party_runtime_token = target_token
		var target_selected := region_live_party_proof(target_token)
		if not target_selected.ok: return _region_committed_unbound("真heir原party完整graph待綁定", {"generation": generation, "token": target_token})
		target_bound = target_binding.publish.call(target_selected.proof)
	else:
		target_bound = target_binding.publish.call(target_data)
	if not target_bound.get("ok", false) or target_bound.get("complete") != true \
			or target_bound.get("owner") != str(target.owner) or int(target_bound.get("generation", -1)) != generation:
		return _region_committed_unbound("真heir控制已共同提交，完整graph待綁定", {"generation": generation, "owner": str(target.owner), "bind_result": target_bound})
	var actual: TerrainLab = host
	if not target_token.is_empty():
		actual = get_meta(&"region_party_owner_labs", {}).get(target_token)
	else:
		_region_original_labs[str(target.owner)] = host
	if not is_instance_valid(actual): return _region_committed_unbound("真heir bind缺原Lab", {"generation": generation, "owner": str(target.owner)})
	var controlled: Dictionary = actual.site_controller._control_family_person(null, int(target.person_id))
	if not controlled.ok: return _region_committed_unbound("真heir graph已提交，原Controller待接續", {"generation": generation, "owner": str(target.owner), "control_result": controlled})
	var enabled := activate_region_mode(str(target.owner), "live", "original_party" if not target_token.is_empty() else "original_site", target_bound, "gd")
	if not enabled.ok: return enabled
	if target_token.is_empty():
		var wired := actual._wire_region_gameplay_adapters(self)
		if not wired.ok: return wired
	return {"ok": true, "complete": true, "person_id": int(target.person_id), "person_reference": target.person_reference.duplicate(true),
		"owner": str(target.owner), "generation": generation, "receipt": target_bound,
		"source_receipt": source_bound, "family_control_transition": queued.receipt}

func _region_family_control_ready(original: TerrainLab, person_id: int) -> Dictionary:
	if not is_instance_valid(original) or original.site_controller == null or original.terrain == null \
			or original.site_controller.region_slot != self or original._region_point_consuming \
			or not original.site_controller._pending_deaths.is_empty(): return fail("BUSY", "先完成原死亡結算")
	var body := original._original_person_target(person_id)
	if body.is_empty() or float(body.hp) > 0.0: return fail("NOT_DEAD")
	if _region_player_committed_close_action(body) > TerrainLab.ACTION_TIME_EPSILON:
		return fail("BUSY", "原死者已接受的移動尚未收束")
	# The original technology archive can move only after its real Scene jobs
	# have settled. A hot graph is not permission to bypass original P1 BUSY.
	for job: Dictionary in original.site_controller.person_actions._jobs.values():
		if job.has("technology_project") or str(job.get("kind", "")).begins_with("technology_"):
			return fail("BUSY", "先沿原科技 owner 收束已接受的研究／教學")
	return {"ok": true}

func _region_family_current_party_owner(reference: Dictionary) -> Dictionary:
	if reference.is_empty(): return {"ok": true, "owner": ""}
	var sources := {}
	var journey := region_travel_journey()
	if not journey.is_empty():
		var player := region_travel_party()
		if not player.ok: return player
		sources[str(journey.token)] = player.party
	for token: String in region_registry().parties:
		var registered: Dictionary = region_registry().parties[token]
		if str(registered.get("phase", "")) not in ["travelling", "pending_life", "materializing"]: continue
		var npc := _region_npc_party(token)
		if not npc.ok: return npc
		if sources.has(token): return fail("DUPLICATE_OWNER", "同一token不能有兩個原party控制者")
		sources[token] = npc.party
	var selected := {"ok": true, "owner": ""}
	var originals: Dictionary = get_meta(&"region_party_owner_labs", {})
	for token: String in sources:
		var party: Dictionary = sources[token]
		var original: TerrainLab = originals.get(token)
		var content: Dictionary = party.content
		if is_instance_valid(original):
			var current: Dictionary = region_original_party_runtime_proof(token, party)
			if not current.ok: return current
			content = current.lab.terrain.site
		var identity: Dictionary = content.get("travel_identity", {})
		if not RegionTravel.validate_identity(identity): return fail("INVALID_IDENTITY")
		var people := RegionTravel._body_records(content)
		for local: String in identity.refs.person:
			if not people.has(int(local)) or RegionTravel.stable_key(identity.refs.person[local]) != RegionTravel.stable_key(reference): continue
			if not str(selected.owner).is_empty(): return fail("DUPLICATE_OWNER", "已登錄PersonRef有兩個真party body擁有者")
			selected = {"ok": true, "owner": "travel:" + token, "person_id": int(local)}
	return selected

func _region_family_discard_bindings(bindings: Array, result: Dictionary) -> Dictionary:
	for binding: Dictionary in bindings:
		if binding.get("discard") is Callable and binding.discard.is_valid(): binding.discard.call()
	return result

func _region_family_life_source(event: Dictionary) -> Dictionary:
	const FIELDS := ["version", "generation", "source_owner", "source_person_id", "source_person_reference",
		"source_party_path", "source_party_sha256", "target_owner", "target_person_id", "target_person_reference",
		"target_path", "target_sha256"]
	var receipt: Variant = event.payload.get("family_control_transition")
	if not receipt is Dictionary or receipt.size() != FIELDS.size() or not _region_player_death_effect_receipt(event):
		return fail("INVALID_FAMILY_TRANSITION")
	for field: String in FIELDS:
		if not receipt.has(field): return fail("INVALID_FAMILY_TRANSITION")
	if receipt.version != 1 or not GameplayClock.whole(receipt.generation, 1) \
			or int(receipt.generation) > int(_marker.get("generation", 0)) or receipt.source_owner != event.owner \
			or int(receipt.source_person_id) != int(event.payload.get("person_id", -1)) \
			or not receipt.source_person_reference is Dictionary or not receipt.target_person_reference is Dictionary \
			or not GameplayClock.whole(receipt.target_person_id, 1) \
			or event.player != true or event.payload.get("controlled") != true or event.payload.get("death") != true:
		return fail("INVALID_FAMILY_TRANSITION")
	var source_token := str(receipt.source_owner).trim_prefix("travel:")
	var source := _region_life_party_document(source_token, str(receipt.source_party_path), str(receipt.source_party_sha256))
	if not source.ok: return source
	var local := str(receipt.source_owner) == str(receipt.target_owner)
	var source_context := _region_life_party_context(source)
	if not source_context.ok: return source_context
	if int(source_context.context.source_generation) >= int(receipt.generation) \
			or source.party.controller != ("player" if local else "npc") \
			or int(source.party.content.get("controlled_person_id", source.party.leader_person_id)) != (int(receipt.source_person_id) if local else -1):
		return fail("INVALID_FAMILY_TRANSITION")
	if not local and (not str(receipt.source_party_path).begins_with("travel/%s/party_family_source_%09d_" % [source_token, int(receipt.generation)]) \
			or not _region_family_new_generation(source_context.context, int(receipt.generation))):
		return fail("INVALID_FAMILY_TRANSITION")
	var source_id := _region_life_reference_id(source.party.content.travel_identity, receipt.source_person_reference)
	var source_bodies := RegionTravel._body_records(source.party.content)
	if source_id != int(receipt.source_person_id) or not source_bodies.has(source_id) \
			or float(source_bodies[source_id].get("hp", 1.0)) > 0.0:
		return fail("INVALID_FAMILY_TRANSITION")
	var actual_source := _region_life_current_party(source_token)
	if not actual_source.ok: return actual_source
	var actual_source_id := _region_life_reference_id(actual_source.party.content.travel_identity, receipt.source_person_reference)
	var source_lab: TerrainLab = actual_source.lab
	var dead := source_lab._original_person_target(actual_source_id)
	if dead.is_empty() or float(dead.hp) > 0.0 or source_lab.site_controller._pending_deaths.has(actual_source_id) \
			or _region_player_committed_close_action(dead) > TerrainLab.ACTION_TIME_EPSILON:
		return fail("INVALID_FAMILY_TRANSITION")
	var target_owner := str(receipt.target_owner)
	var target_lab: TerrainLab
	var target_state: Dictionary
	var historical_target: Dictionary
	var target_context: Dictionary = {}
	if target_owner.begins_with("travel:"):
		var target_token := target_owner.trim_prefix("travel:")
		var target_file := _region_life_party_document(target_token, str(receipt.target_path), str(receipt.target_sha256))
		if not target_file.ok: return target_file
		var target_graph := _region_life_party_context(target_file)
		if not target_graph.ok: return target_graph
		target_context = target_graph.context
		var prefix := "travel/%s/party_family_%09d_" if local else "travel/%s/party_family_target_%09d_"
		if not str(receipt.target_path).begins_with(prefix % [target_token, int(receipt.generation)]) \
				or target_file.party.controller != "player" \
				or int(target_file.party.content.get("controlled_person_id", target_file.party.leader_person_id)) != int(receipt.target_person_id):
			return fail("INVALID_FAMILY_TRANSITION")
		historical_target = target_file.party.content
		var actual_target := _region_life_current_party(target_token)
		if not actual_target.ok: return actual_target
		target_lab = actual_target.lab
		target_state = actual_target.party.content
	else:
		var prefix := str(pin.atlas_id) + ":"
		if not target_owner.begins_with(prefix) or not str(receipt.target_path).begins_with("generations/%020d_" % int(receipt.generation)) \
				or str(receipt.target_path).contains("..") or str(receipt.target_path).contains("\\") \
				or str(receipt.target_sha256).length() != 64 \
				or FileAccess.get_sha256(folder.path_join(str(receipt.target_path))) != str(receipt.target_sha256):
			return fail("INVALID_FAMILY_TRANSITION")
		var parts := target_owner.trim_prefix(prefix).split(":")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int(): return fail("INVALID_FAMILY_TRANSITION")
		var historical := _load_checked(folder.path_join(str(receipt.target_path)), Vector2i(int(parts[0]), int(parts[1])))
		if not historical.ok or str(historical.data.site.id) != target_owner: return historical if not historical.ok else fail("WRONG_SITE")
		historical_target = historical.data.site
		var snapshot := Store.validate_region_snapshot(historical.data, {})
		if not snapshot.ok: return snapshot
		target_context = snapshot.context
		if int(historical_target.get("controlled_person_id", -1)) != int(receipt.target_person_id):
			return fail("INVALID_FAMILY_TRANSITION")
		target_lab = _region_original_labs.get(target_owner)
		if target_owner == str(control.active_site_id) and region_owner_lab.is_valid():
			var main: Object = region_owner_lab.get_object()
			if main is TerrainLab and main.terrain != null and str(main.terrain.site.id) == target_owner: target_lab = main
		if not is_instance_valid(target_lab): return fail("COMMITTED_UNBOUND")
		target_state = target_lab.terrain.site
	# Both existing producers save a newly captured target before the ONE
	# transfer marker. Only the local source is an older selected file.
	if not _region_family_new_generation(target_context, int(receipt.generation)) \
			or absf(float(target_context.game_seconds) - float(source_context.context.game_seconds)) > TerrainLab.ACTION_TIME_EPSILON \
			or absf(float(target_context.action_seconds) - float(source_context.context.action_seconds)) > TerrainLab.ACTION_TIME_EPSILON \
			or target_context.fire_epoch != source_context.context.fire_epoch \
			or int(target_context.fire_sequence) != int(source_context.context.fire_sequence):
		return fail("INVALID_FAMILY_TRANSITION")
	var old_target_id := _region_life_reference_id(historical_target.get("travel_identity", {}), receipt.target_person_reference)
	var old_targets := RegionTravel._body_records(historical_target)
	if old_target_id != int(receipt.target_person_id) or not old_targets.has(old_target_id) \
			or float(old_targets[old_target_id].get("hp", 0.0)) <= 0.0:
		return fail("INVALID_FAMILY_TRANSITION")
	var target_id := _region_life_reference_id(target_state.get("travel_identity", {}), receipt.target_person_reference)
	if not is_instance_valid(target_lab) or target_lab.terrain == null or target_lab._region_bound_data != target_lab.terrain \
			or target_lab.site_controller.region_slot != self or str(target_lab.terrain.site.id) != target_owner \
			or target_lab.controlled_person_id() != target_id:
		return fail("INVALID_FAMILY_TRANSITION")
	var bound := target_lab.region_bind_receipt(target_lab.terrain)
	var living := target_lab._original_person_target(target_id)
	if bound.get("complete") != true or bound.get("owners_restored") != true or bound.get("owner") != target_owner \
			or int(bound.get("generation", -1)) != int(_marker.get("generation", 0)) or living.is_empty() or float(living.hp) <= 0.0:
		return fail("INVALID_FAMILY_TRANSITION")
	return {"ok": true, "family_complete": true, "lab": target_lab, "source_lab": source_lab,
		"person_id": actual_source_id, "person_reference": receipt.source_person_reference, "person": dead,
		"target_person_id": target_id, "event": event, "receipt": bound}

func _region_family_local_candidate(source: Dictionary, reference: Dictionary, target_id: int,
		person_reference: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	if result.content.travel_identity.refs.person.get(str(target_id)) != person_reference:
		return fail("STALE_FAMILY_PERSON")
	var owner := "travel:" + str(result.party_id)
	var old_key := JSON.stringify([str(reference.site_id), int(reference.person_id)])
	var new_key := JSON.stringify([owner, target_id])
	var found := false
	for member: Dictionary in result.content.family.members:
		if var_to_bytes(member) != var_to_bytes(reference): continue
		found = true
		member.site_id = owner
		member.person_id = target_id
		member.path = ""
	if not found: return fail("NO_HEIR")
	if old_key != new_key and result.content.travel_identity.get("family_members", {}).has(new_key):
		return fail("DUPLICATE_FAMILY_PERSON")
	if not result.content.travel_identity.has("family_members"): result.content.travel_identity.family_members = {}
	result.content.travel_identity.family_members.erase(old_key)
	result.content.travel_identity.family_members[new_key] = person_reference.duplicate(true)
	result.content.controlled_person_id = target_id
	result.leader_person_id = target_id
	if not RegionTravel.Family.validate_family(result.content.family, owner) or not RegionTravel.validate_identity(result.content.travel_identity):
		return fail("INVALID_FAMILY")
	return {"ok": true, "party": result}

static func _region_family_new_generation(context: Dictionary, generation: int) -> bool:
	return generation > 0 and RegionCheckpoint.validate_context(context).ok \
		and int(context.source_generation) == generation - 1

func _region_family_player_authority() -> Dictionary:
	var journey := region_travel_journey()
	if journey.is_empty(): return fail("NO_TARGET", "沒有原玩家party family owner")
	var token := str(journey.token)
	var selected := region_travel_party()
	if not selected.ok: return selected
	var original: TerrainLab = get_meta(&"region_party_owner_labs", {}).get(token)
	var content: Dictionary = original.terrain.site if is_instance_valid(original) and original.terrain != null else selected.party.content
	var family: Variant = content.get("family")
	var identity: Variant = content.get("travel_identity")
	if not RegionTravel.Family.validate_family(family, "travel:" + token) or not RegionTravel.validate_identity(identity):
		return fail("INVALID_FAMILY")
	return {"ok": true, "token": token, "party": selected.party, "family": family, "identity": identity, "lab": original}

func _region_family_reference_guard(reference: Dictionary) -> Dictionary:
	var authority := _region_family_player_authority()
	if not authority.ok: return authority
	var registered := false
	for member: Dictionary in authority.family.members:
		if var_to_bytes(member) == var_to_bytes(reference): registered = true
	if not registered: return fail("NO_HEIR", "須是原family已明確登錄的完整引用")
	var key := JSON.stringify([str(reference.site_id), int(reference.person_id)])
	return {"ok": true, "authority": authority, "person_reference": authority.identity.get("family_members", {}).get(key, {}).duplicate(true)}

func _region_family_relocate_reference(state: Dictionary, reference: Dictionary, owner: String,
		person_id: int, person_reference: Dictionary) -> Dictionary:
	var candidate := state.duplicate(true)
	if not candidate.get("family") is Dictionary or not RegionTravel.validate_identity(candidate.get("travel_identity")):
		return fail("INVALID_FAMILY")
	var old_key := JSON.stringify([str(reference.site_id), int(reference.person_id)])
	var new_key := JSON.stringify([owner, person_id])
	var found := false
	for member: Dictionary in candidate.family.members:
		if var_to_bytes(member) != var_to_bytes(reference): continue
		found = true
		member.site_id = owner
		member.person_id = person_id
		member.path = "" # Only the Slot's current selected owner resolves this body.
	if not found: return fail("NO_HEIR")
	var index: Dictionary = candidate.travel_identity.get("family_members", {})
	if old_key != new_key and index.has(new_key): return fail("DUPLICATE_FAMILY_PERSON")
	index.erase(old_key)
	index[new_key] = person_reference.duplicate(true)
	candidate.travel_identity.family_members = index
	return {"ok": true, "state": candidate}

func _region_family_remote_candidates(source: Dictionary, target: Dictionary, destination: Dictionary,
		reference: Dictionary) -> Dictionary:
	var source_owner := "travel:" + str(source.party_id)
	var target_owner := str(target.owner)
	var moved := _region_family_relocate_reference(source.content, reference, target_owner,
		int(target.person_id), target.person_reference)
	if not moved.ok: return moved
	var source_state: Dictionary = moved.state
	var source_family: Dictionary = source_state.family
	var family_reference: Dictionary = source_state.travel_identity.refs.family.get("controlled", {})
	if family_reference.is_empty() or not RegionTravel.Family.validate_family(source_family, source_owner): return fail("INVALID_FAMILY")
	var destination_state := destination.duplicate(true)
	if not RegionTravel.validate_identity(destination_state.get("travel_identity")) \
			or destination_state.travel_identity.refs.person.get(str(int(target.person_id))) != target.person_reference:
		return fail("STALE_FAMILY_PERSON")
	var destination_family: Dictionary = destination_state.get("family", {})
	var portable_family: Dictionary = destination_state.get("family_refs", {})
	if not portable_family.is_empty() and portable_family.get("reference") != family_reference: return fail("DIFFERENT_FAMILY")
	if not destination_family.is_empty():
		if destination_state.travel_identity.refs.family.get("controlled") != family_reference \
				or not RegionTravel.Family.validate_family(destination_family, target_owner): return fail("DIFFERENT_FAMILY")
		# The explicit player registry follows control. Existing destination
		# offices remain exactly theirs; conflicting old memberships are refused.
		var retained := destination_family.duplicate(true)
		retained.members = source_family.members.duplicate(true)
		retained.complete = source_family.complete
		destination_family = retained
	else:
		destination_family = source_family.duplicate(true)
		if int(destination_family.version) >= 2:
			SiteOffices.vacate_unless(destination_family.offices, func(_id: int) -> bool: return false)
		if destination_family.has("technology"):
			destination_family.technology = RegionTravel.Technology._holder_reference(source_family.technology)
	if not RegionTravel.Family.validate_family(destination_family, target_owner): return fail("FAMILY_REGISTRY_CONFLICT")
	var technology_script: Variant = RegionTravel.Technology
	if not technology_script.has_method("prepare_holder_control_transition"): return fail("MISSING_TECHNOLOGY_CONTROL_TRANSFER")
	var technology: Dictionary = technology_script.call("prepare_holder_control_transition", family_reference,
		source_family, destination_family, source_owner, target_owner)
	if not technology.ok: return technology
	source_state.family = technology.source_family
	destination_state.family = technology.destination_family
	destination_state.travel_identity.refs.family["controlled"] = family_reference.duplicate(true)
	var family_index: Dictionary = source_state.travel_identity.get("family_members", {}).duplicate(true)
	for member: Dictionary in destination_state.family.members:
		if str(member.site_id) != target_owner: continue
		var local := str(int(member.person_id))
		var typed: Dictionary = destination_state.travel_identity.refs.person.get(local, {})
		if typed.is_empty(): return fail("UNKNOWN_FAMILY_PERSON")
		var key := JSON.stringify([target_owner, int(member.person_id)])
		if family_index.has(key) and family_index[key] != typed: return fail("STALE_FAMILY_PERSON")
		family_index[key] = typed.duplicate(true)
	destination_state.travel_identity.family_members = family_index
	destination_state.controlled_person_id = int(target.person_id)
	var source_candidate := source.duplicate(true)
	source_candidate.controller = "npc"
	source_state.controlled_person_id = -1
	source_candidate.content = source_state
	if not RegionTravel.Family.validate_family(source_candidate.content.family, source_owner) \
			or not RegionTravel.validate_identity(source_candidate.content.travel_identity) \
			or not RegionTravel.Family.validate_family(destination_state.family, target_owner) \
			or not RegionTravel.validate_identity(destination_state.travel_identity): return fail("INVALID_FAMILY_TRANSITION")
	return {"ok": true, "party": source_candidate, "destination_state": destination_state}

func _region_family_source_npc_reference(source: Dictionary, journey: Dictionary, relative: String,
		sha256: String, transition: Dictionary) -> Dictionary:
	return {"version": 1, "controller": "npc", "token": str(source.party_id), "phase": "travelling",
		"party_path": relative, "party_sha256": sha256, "plan_path": str(journey.plan_path),
		"plan_sha256": str(journey.plan_sha256), "departure_game_seconds": float(journey.departure_game_seconds),
		"origin": journey.origin.duplicate(), "position": journey.position.duplicate(true),
		"transfer_receipt": {"version": 1, "kind": "family_control", "transition": transition.duplicate(true)}}

func _region_family_target_journey(token: String, reference: Dictionary, candidate: Dictionary,
		relative: String, sha256: String) -> Dictionary:
	var journey := {"version": 1, "kind": RegionTravel.KIND, "token": token, "party_path": relative,
		"party_sha256": sha256, "departure_game_seconds": float(reference.departure_game_seconds),
		"origin": reference.origin.duplicate(), "position": reference.position.duplicate(true),
		"plan_path": str(reference.plan_path), "plan_sha256": str(reference.plan_sha256),
		"plan_started_game_seconds": float(reference.departure_game_seconds), "plans": 1 if not str(reference.plan_path).is_empty() else 0}
	var body: Dictionary = candidate.get("upkeep", {}).get("live", {}).get("frame", {}).get("people", {}).get(str(int(candidate.leader_person_id)), {})
	if RegionTravel._frame_pair(body.get("world_cell")):
		journey.position = {"site": [Grid.floor_div(int(body.world_cell[0]), 100), -Grid.floor_div(int(body.world_cell[1]), 100)], "component": 0}
	return _normalize_travel_journey(journey)

func _region_family_target_ready(target: Dictionary) -> Dictionary:
	var original: TerrainLab = target.get("lab")
	if not is_instance_valid(original) or original.site_controller == null or original.terrain == null \
			or original.site_controller.region_slot != self or original._region_point_consuming \
			or not original.site_controller._pending_deaths.is_empty(): return fail("BUSY", "真接續 owner 尚未完成原端點")
	var body := original._original_person_target(int(target.person_id))
	if body.is_empty() or float(body.hp) <= 0.0: return fail("NO_HEIR")
	for job: Dictionary in original.site_controller.person_actions._jobs.values():
		if job.has("technology_project") or str(job.get("kind", "")).begins_with("technology_"):
			return fail("BUSY", "原接續科技 owner 有已接受工作")
	if str(target.owner).begins_with("travel:"):
		var token := str(target.owner).trim_prefix("travel:")
		var selected := region_live_party_proof(token)
		if not selected.ok: return selected
		if selected.party.controller != "npc" or selected.original_live_graph.is_empty(): return fail("MISSING_ORIGINAL_PARTY_GRAPH")
		return {"ok": true, "state": selected.party.content, "hash": str(selected.proof.party_hash), "selected": selected}
	var window := validate_settlement(original.terrain.site, float(control.logical_game_seconds))
	var fire: Dictionary = original.terrain.site.get("fire_settlement", {})
	if not window.ok or window.legacy or float(window.pending) > 0.00000001 \
			or fire.get("epoch") != control.fire_clock.epoch or int(fire.get("sequence", -1)) != int(control.fire_clock.sequence) \
			or float(fire.get("action_seconds", -1.0)) != float(control.fire_clock.action_seconds): return fail("UNSETTLED_SITE")
	var proof := region_bind_proof(original.terrain)
	if proof.is_empty() or FileAccess.get_sha256(folder.path_join(str(proof.path))) != str(proof.sha256): return fail("STALE_REGION_BIND_SOURCE")
	return {"ok": true, "state": original.terrain.site, "hash": RegionCheckpoint.state_hash(original.terrain.site), "selected": {"proof": proof}}

func _region_family_transfer_queue(next_control: Dictionary, source: Dictionary, transition: Dictionary,
		generation: int, source_relative: String, source_sha: String, target_relative: String, target_sha: String,
		target_person_id: int) -> Dictionary:
	var source_owner := "travel:" + str(source.party_id)
	var old_id := int(source.content.get("controlled_person_id", source.leader_person_id))
	var reference: Dictionary = source.content.travel_identity.refs.person.get(str(old_id), {})
	if reference.is_empty(): return fail("INVALID_FAMILY_TRANSITION")
	var receipt := {"version": 1, "generation": generation, "source_owner": source_owner,
		"source_person_id": old_id, "source_person_reference": reference.duplicate(true),
		"source_party_path": source_relative, "source_party_sha256": source_sha,
		"target_owner": str(transition.destination_owner), "target_person_id": target_person_id,
		"target_person_reference": transition.person_reference.duplicate(true),
		"target_path": target_relative, "target_sha256": target_sha}
	for event: Dictionary in next_control.region_gameplay.events:
		if event.status != "pending" or event.owner != source_owner or event.player != true: continue
		if event.kind not in ["life", "player_death"] or event.payload.get("controlled") != true or event.payload.get("death") != true: continue
		if int(event.payload.get("person_id", -1)) != old_id or not _region_player_death_effect_receipt(event):
			return fail("INVALID_REGION_RECEIPT", "接續不能修改原死亡事件／已付效果回執")
		event.payload.family_control_transition = receipt.duplicate(true)
	return {"ok": true, "receipt": receipt}

func _region_gameplay_family_life_complete(event: Dictionary) -> Dictionary:
	var canonical := _region_life_canonical(event)
	if not canonical.ok: return canonical
	var source := _region_family_life_source(canonical.event)
	if not source.ok: return source
	return {"ok": true, "receipt": {"complete": true, "effects_complete": true, "continuity_complete": true,
		"owner": str(source.lab.terrain.site.id), "generation": int(_marker.get("generation", 0)),
		"game_seconds": float(control.logical_game_seconds), "action_seconds": float(control.fire_clock.action_seconds)}}

func commit_region_party_family_control(token: String, reference: Dictionary, source_owner: Dictionary,
		family: Dictionary) -> Dictionary:
	var authority := _region_family_player_authority()
	if not authority.ok or authority.token != token: return authority if not authority.ok else fail("WRONG_FAMILY_OWNER")
	if var_to_bytes(authority.family) != var_to_bytes(family): return fail("STALE_FAMILY")
	var refreshed := resolve_region_family_owner(reference)
	if not refreshed.ok: return refreshed
	if refreshed.person_reference != source_owner.get("person_reference", refreshed.person_reference): return fail("STALE_FAMILY_PERSON")
	if refreshed.owner != "travel:" + token:
		return _commit_region_party_family_remote(token, reference, refreshed, family)
	var checkpoint := checkpoint_region_travel()
	if not checkpoint.ok: return checkpoint
	var selected := region_live_party_proof(token)
	if not selected.ok: return selected
	var local_candidate := _region_family_local_candidate(selected.party, reference, int(refreshed.person_id), refreshed.person_reference)
	if not local_candidate.ok: return local_candidate
	var candidate: Dictionary = local_candidate.party
	var transition := {"version": 1, "source_person_id": int(selected.party.content.get("controlled_person_id", selected.party.leader_person_id)),
		"target": reference.duplicate(true), "person_reference": refreshed.person_reference.duplicate(true), "source_party_hash": str(selected.proof.party_hash)}
	var checked := validate_region_family_party_transition(token, candidate, selected.proof, transition)
	if not checked.ok: return checked
	var original: TerrainLab = get_meta(&"region_party_owner_labs", {}).get(token)
	var binding: Dictionary = original.prepare_region_party_family_bind(token, candidate, self, selected.proof, transition)
	if not binding.ok: return binding
	for hook: String in ["can_publish", "publish", "discard"]:
		if not binding.get(hook) is Callable or not binding[hook].is_valid(): return fail("MISSING_ORIGINAL_PARTY_BIND")
	if not binding.get("party") is Dictionary or var_to_bytes(binding.party) != var_to_bytes(candidate) or binding.can_publish.call() != true:
		return fail("FAMILY_BODY_CLOSURE")
	var document := _region_party_document(token, candidate, binding.original_live_graph)
	if not document.ok: return document
	var generation := int(selected.proof.generation) + 1
	var relative := "travel/%s/party_family_%09d_%s.json" % [token, generation, Crypto.new().generate_random_bytes(8).hex_encode()]
	var written := _write_new_document(folder.path_join(relative), document.payload)
	if not written.ok: return written
	var next_control := control.duplicate(true)
	next_control.region_gameplay.revision = int(next_control.region_gameplay.revision) + 1
	var mode := GameplayClock.activate_mode(next_control.region_gameplay, "travel:" + token, "committed-unbound", generation,
		"gd", "original_party", float(next_control.logical_game_seconds), float(next_control.fire_clock.action_seconds), {})
	if not mode.ok: return mode
	var sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	var cold := _collect_cold_checkpoint(generation, sites, next_control)
	if not cold.ok: return cold
	var parties := collect_region_party_checkpoint(generation, next_control)
	if not parties.ok: return parties
	checked = validate_region_family_party_transition(token, candidate, selected.proof, transition)
	if not checked.ok or binding.can_publish.call() != true: return checked if not checked.ok else fail("STALE_REGION_BIND_TICKET")
	var family_event_transition := {"destination_owner": "travel:" + token, "person_reference": refreshed.person_reference}
	var family_queue := _region_family_transfer_queue(next_control, selected.party, family_event_transition, generation,
		str(selected.proof.path), str(selected.proof.sha256), relative, FileAccess.get_sha256(folder.path_join(relative)), int(refreshed.person_id))
	if not family_queue.ok: return family_queue
	var journey := region_travel_journey()
	journey.party_path = relative
	journey.party_sha256 = FileAccess.get_sha256(folder.path_join(relative))
	var committed := _publish(sites, next_control, str(_marker.get("transfer_token", "")), journey)
	if not committed.ok: return committed
	_travel_party_runtime = candidate
	_travel_party_runtime_token = token
	var proof := region_live_party_proof(token)
	if not proof.ok: return _region_committed_unbound("原family控制候選已提交；完整graph待重綁", {"generation": generation, "token": token})
	var bound: Variant = binding.publish.call(proof.proof)
	if not bound is Dictionary or not bound.get("ok", false) or bound.get("complete") != true:
		return _region_committed_unbound("原family控制已提交；完整graph待重綁", {"generation": generation, "token": token, "bind_result": bound})
	var actual: TerrainLab = get_meta(&"region_party_owner_labs", {}).get(token)
	if not is_instance_valid(actual): return _region_committed_unbound("原family身體綁定收據缺真Lab", {"generation": generation, "token": token})
	var controlled: Dictionary = actual.site_controller._control_family_person(null, int(refreshed.person_id))
	if not controlled.ok: return _region_committed_unbound("原family完整graph已提交；原Controller待接續", {"generation": generation, "token": token, "control_result": controlled})
	var enabled := activate_region_mode("travel:" + token, "live", "original_party", bound, "gd")
	if not enabled.ok: return enabled
	return {"ok": true, "complete": true, "person_id": int(refreshed.person_id), "owner": "travel:" + token,
		"generation": generation, "person_reference": refreshed.person_reference.duplicate(true), "receipt": bound}

func resolve_region_family_owner(reference: Dictionary) -> Dictionary:
	var guarded := _region_family_reference_guard(reference)
	if not guarded.ok: return guarded
	var expected: Dictionary = guarded.person_reference
	var owner := str(reference.site_id)
	var target_id := int(reference.person_id)
	# Historical registered locators can precede a legal departure/join. Only
	# their already-authenticated stable PersonRef resolves a current party.
	var current := _region_family_current_party_owner(expected)
	if not current.ok: return current
	if not str(current.get("owner", "")).is_empty():
		owner = str(current.owner)
		target_id = int(current.person_id)
	var original: TerrainLab
	var selected := {}
	if owner.begins_with("travel:"):
		var token := owner.trim_prefix("travel:")
		var record: Dictionary = region_registry().parties.get(token, {})
		if record.get("phase") == "joined":
			if expected.is_empty(): return fail("UNKNOWN_FAMILY_PERSON", "歷史NPC引用缺原typed PersonRef，不能用同號重生")
			token = str(record.get("entered_party", ""))
			owner = "travel:" + token
		elif record.get("phase") == "entered":
			if expected.is_empty(): return fail("UNKNOWN_FAMILY_PERSON")
			owner = str(record.get("destination_site", ""))
		if owner.begins_with("travel:"):
			selected = region_live_party_proof(token)
			if not selected.ok: return selected
			original = get_meta(&"region_party_owner_labs", {}).get(token)
			if not is_instance_valid(original):
				if not region_original_party_progress.is_valid(): return fail("MISSING_ORIGINAL_PARTY_OWNER")
				var host: Object = region_original_party_progress.get_object()
				if not host is TerrainLab: return fail("MISSING_ORIGINAL_PARTY_OWNER")
				var restored: Dictionary = host.prepare_region_party_original_owner(token, selected.party, self)
				if not restored.ok: return restored
				original = restored.lab
	if not owner.begins_with("travel:"):
		if not region_owner_lab.is_valid(): return fail("MISSING_FAMILY_OWNER")
		selected = region_owner_lab.call(owner, "live" if owner == str(control.active_site_id) else "cold_exact")
		if not selected.get("ok", false) or not selected.get("lab") is TerrainLab: return selected
		original = selected.lab
	if not is_instance_valid(original) or original.terrain == null or original.site_controller.region_slot != self:
		return fail("COMMITTED_UNBOUND")
	var identity: Dictionary = original.terrain.site.get("travel_identity", {})
	if not RegionTravel.validate_identity(identity): return fail("INVALID_IDENTITY")
	if not expected.is_empty():
		target_id = -1
		for local: String in identity.refs.person:
			if identity.refs.person[local] == expected:
				if target_id > 0: return fail("DUPLICATE_OWNER")
				target_id = int(local)
		if target_id <= 0: return fail("STALE_FAMILY_PERSON", "原typed PersonRef不在目前真擁有者")
	else:
		expected = identity.refs.person.get(str(target_id), {}).duplicate(true)
		if expected.is_empty(): return fail("NO_PERSON")
	var person := original._original_person_target(target_id)
	if person.is_empty(): return fail("NO_PERSON")
	var observed: Dictionary = original.site_controller.family_continuity._current_person(target_id)
	if observed.is_empty(): return fail("NO_PERSON")
	return {"ok": true, "local": owner == "travel:" + str(guarded.authority.token), "person": observed,
		"lab": original, "data": original.terrain, "owner": owner, "person_id": target_id,
		"person_reference": expected, "selected": selected, "reference": reference.duplicate(true)}

func validate_region_family_departure_transition(token: String, candidate: Dictionary,
		source_proof: Dictionary, transition: Dictionary) -> Dictionary:
	const FIELDS := ["version", "source_person_id", "target", "person_reference", "source_party_hash", "destination_owner", "destination_source_hash"]
	if transition.size() != FIELDS.size() or transition.get("version") != 1: return fail("INVALID_FAMILY_TRANSITION")
	for field: String in FIELDS:
		if not transition.has(field): return fail("INVALID_FAMILY_TRANSITION")
	if not transition.get("target") is Dictionary or not transition.get("person_reference") is Dictionary \
			or not GameplayClock.whole(transition.get("source_person_id"), 1) \
			or not transition.get("destination_owner") is String or not transition.get("destination_source_hash") is String:
		return fail("INVALID_FAMILY_TRANSITION")
	var selected := region_live_party_proof(token)
	if not selected.ok: return selected
	if selected.proof != source_proof or transition.source_party_hash != selected.proof.party_hash:
		return fail("STALE_REGION_PARTY_PROOF")
	var source: Dictionary = selected.party
	var old_id := int(source.content.get("controlled_person_id", source.leader_person_id))
	if old_id != int(transition.source_person_id) or source.controller != "player" \
			or token != str(region_travel_journey().get("token", "")): return fail("INVALID_FAMILY_TRANSITION")
	var bodies := RegionTravel._body_records(source.content)
	if not bodies.has(old_id) or float(bodies[old_id].get("hp", 0.0)) > 0.0: return fail("NOT_DEAD")
	var target := resolve_region_family_owner(transition.target)
	if not target.ok: return target
	if target.owner == "travel:" + token or target.owner != transition.destination_owner \
			or target.person_reference != transition.person_reference: return fail("WRONG_FAMILY_OWNER")
	var originals: Dictionary = get_meta(&"region_party_owner_labs", {})
	var ready := _region_family_control_ready(originals.get(token), old_id)
	if not ready.ok: return ready
	var destination := _region_family_target_ready(target)
	if not destination.ok: return destination
	if destination.hash != transition.destination_source_hash: return fail("STALE_REGION_BIND_SOURCE")
	var expected := _region_family_remote_candidates(source, target, destination.state, transition.target)
	if not expected.ok: return expected
	if var_to_bytes(candidate) != var_to_bytes(expected.party):
		return fail("FAMILY_BODY_CLOSURE", "只准原party卸除玩家控制／原科技holder移交，原body及完整graph保留")
	return {"ok": true, "source_party": source, "source_proof": selected.proof, "party": expected.party,
		"original_live_graph": selected.original_live_graph, "person_id": int(target.person_id),
		"person_reference": target.person_reference, "destination_owner": str(target.owner),
		"destination_state": expected.destination_state, "destination_source_hash": destination.hash,
		"destination_selected": destination.selected, "target": target}

func validate_region_family_party_transition(token: String, candidate: Dictionary,
		source_proof: Dictionary, transition: Dictionary) -> Dictionary:
	const FIELDS := ["version", "source_person_id", "target", "person_reference", "source_party_hash"]
	if transition.size() != FIELDS.size() or transition.get("version") != 1:
		return fail("INVALID_FAMILY_TRANSITION")
	for field: String in FIELDS:
		if not transition.has(field): return fail("INVALID_FAMILY_TRANSITION")
	if not transition.get("target") is Dictionary or not transition.get("person_reference") is Dictionary \
			or not GameplayClock.whole(transition.get("source_person_id"), 1): return fail("INVALID_FAMILY_TRANSITION")
	var selected := region_live_party_proof(token)
	if not selected.ok: return selected
	if selected.proof != source_proof or transition.source_party_hash != selected.proof.party_hash:
		return fail("STALE_REGION_PARTY_PROOF")
	var source: Dictionary = selected.party
	var old_id := int(source.content.get("controlled_person_id", source.leader_person_id))
	if old_id != int(transition.source_person_id) or source.controller != "player" or token != str(region_travel_journey().get("token", "")):
		return fail("INVALID_FAMILY_TRANSITION")
	var target := resolve_region_family_owner(transition.target)
	if not target.ok: return target
	if target.owner != "travel:" + token or target.person_reference != transition.person_reference:
		return fail("WRONG_FAMILY_OWNER")
	var target_id := int(target.person_id)
	var bodies := RegionTravel._body_records(source.content)
	if target_id == old_id or not bodies.has(old_id) or not bodies.has(target_id) \
			or float(bodies[old_id].get("hp", 0.0)) > 0.0 or float(bodies[target_id].get("hp", 0.0)) <= 0.0:
		return fail("NO_HEIR")
	var original: TerrainLab = get_meta(&"region_party_owner_labs", {}).get(token)
	if not is_instance_valid(original) or not original.site_controller._pending_deaths.is_empty() or original._region_point_consuming:
		return fail("BUSY", "先完成原死亡結算")
	var old_body := original._original_person_target(old_id)
	if old_body.is_empty() or float(old_body.hp) > 0.0 or _region_player_committed_close_action(old_body) > TerrainLab.ACTION_TIME_EPSILON:
		return fail("BUSY", "原死者已接受的移動尚未收束")
	var expected := _region_family_local_candidate(source, transition.target, target_id, target.person_reference)
	if not expected.ok: return expected
	if var_to_bytes(candidate) != var_to_bytes(expected.party):
		return fail("FAMILY_BODY_CLOSURE", "接續候選只能選擇同一原family真body，不改生命／職位／財物／graph／時間")
	return {"ok": true, "source_party": source, "source_proof": selected.proof, "party": candidate,
		"original_live_graph": selected.original_live_graph, "person_id": target_id, "person_reference": target.person_reference}

func validate_region_family_takeover_transition(token: String, candidate: Dictionary,
		source_proof: Dictionary, transition: Dictionary) -> Dictionary:
	var player_token := str(region_travel_journey().get("token", ""))
	if player_token.is_empty() or token == player_token or transition.get("destination_owner") != "travel:" + token:
		return fail("WRONG_FAMILY_OWNER")
	var player := region_live_party_proof(player_token)
	if not player.ok: return player
	var target := resolve_region_family_owner(transition.get("target", {}))
	if not target.ok: return target
	var prepared := _region_family_target_ready(target)
	if not prepared.ok: return prepared
	var remote := _region_family_remote_candidates(player.party, target, prepared.state, transition.target)
	if not remote.ok: return remote
	var authorized := validate_region_family_departure_transition(player_token, remote.party, player.proof, transition)
	if not authorized.ok: return authorized
	var selected := region_live_party_proof(token)
	if not selected.ok: return selected
	if selected.proof != source_proof or selected.party.controller != "npc" \
			or selected.proof.party_hash != transition.destination_source_hash: return fail("STALE_REGION_PARTY_PROOF")
	var expected: Dictionary = selected.party.duplicate(true)
	expected.controller = "player"
	expected.leader_person_id = int(target.person_id)
	expected.content = authorized.destination_state.duplicate(true)
	if var_to_bytes(candidate) != var_to_bytes(expected): return fail("FAMILY_BODY_CLOSURE")
	return {"ok": true, "source_party": selected.party, "source_proof": selected.proof, "party": expected,
		"original_live_graph": selected.original_live_graph, "person_id": int(target.person_id),
		"person_reference": target.person_reference}

func _region_install_live_ship_moves(party: Dictionary, world: Dictionary, frame: Dictionary) -> Dictionary:
	var result := party.duplicate(true)
	var origin := Vector2i(int(frame.world_origin[0]), int(frame.world_origin[1]))
	var width := int(frame.size[0])
	var height := int(frame.size[1])
	for identity: String in result.content.get("vehicles", {}):
		var vehicle: Dictionary = result.content.vehicles[identity]
		if str(vehicle.get("kind", "")) != "ship": continue
		var pose: Dictionary = world.vehicles.get(identity, {}).get("pose", {})
		if pose.is_empty(): return fail("MISSING_ORIGINAL_SHIP_POSE")
		# An already-live original Ship owns this accepted move. Only its frame
		# coordinates are projected; its elapsed/duration/command are unchanged.
		if not party.get("upkeep", {}).get("live", {}).is_empty(): continue
		if not RegionTravel._frame_pair(pose.get("facing")): return fail("CORRUPT_SEA_CURSOR")
		vehicle.facing = pose.facing.duplicate()
		var duration := float(pose.get("duration_action_seconds", 0.0))
		if duration <= 0.0:
			if not vehicle.get("move", {}).is_empty(): return fail("DUPLICATE_SHIP_MOVEMENT")
			continue
		if not RegionTravel._frame_pair(pose.get("from")) or not RegionTravel._frame_pair(pose.get("to")) \
				or not RegionTravel._frame_pair(pose.get("from_facing")) or not RegionTravel._frame_pair(pose.get("to_facing")) \
				or not is_finite(duration) or duration > 1000000.0 or pose.get("action") not in ["forward", "reverse", "dock", "turn"]:
			return fail("CORRUPT_SEA_CURSOR")
		var elapsed := float(pose.get("elapsed_action_seconds", -1.0))
		if not is_finite(elapsed) or elapsed < 0.0 or elapsed >= duration: return fail("CORRUPT_SEA_CURSOR")
		var from := Vector2i(int(pose.from[0]), int(pose.from[1])) - origin
		var to := Vector2i(int(pose.to[0]), int(pose.to[1])) - origin
		var before := Vector2i(int(pose.from_facing[0]), int(pose.from_facing[1]))
		var after := Vector2i(int(pose.to_facing[0]), int(pose.to_facing[1]))
		if int(vehicle.cell) != from.y * width + from.x or not vehicle.get("move", {}).is_empty(): return fail("DUPLICATE_SHIP_MOVEMENT")
		var cells := Ship.swept_footprint(str(vehicle.ship_type), from, before, to, after)
		if cells.is_empty(): return fail("CORRUPT_SHIP_SWEEP")
		var sweep: Array[int] = []
		for cell: Vector2i in cells:
			if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height: return fail("PARTY_FRAME_TOO_NARROW")
			sweep.append(cell.y * width + cell.x)
		vehicle.facing = pose.from_facing.duplicate()
		vehicle.move = {"from_cell": int(vehicle.cell), "from_facing": vehicle.facing.duplicate(),
			"cell": to.y * width + to.x, "facing": pose.to_facing.duplicate(), "elapsed": elapsed,
			"duration": duration, "sweep": sweep, "action": str(pose.action)}
		vehicle.stop_pending = true # Finish this paid step; next movement needs its original command.
		vehicle.command = {}
	return {"ok": true, "party": result}

func _region_current_land_position(party: Dictionary, plan: Dictionary, path: String) -> Dictionary:
	var view := _region_land_physical_plan(plan)
	var position := _region_route_position(view, _region_land_physical_distance(view, party.upkeep, path))
	var node: Dictionary = party.upkeep.get("route_node", {})
	var blocked: Dictionary = party.upkeep.get("route_blocked", {})
	if str(node.get("plan_id", "")) == path:
		if str(blocked.get("plan_id", "")) == path and not blocked.is_empty():
			position = {"site": node.site.duplicate(), "component": int(node.component), "step_index": int(node.index), "fraction": 1.0}
		elif int(node.get("index", -1)) == int(position.step_index) and node.get("site") == position.site:
			position.component = int(node.component)
	return position

func _region_land_physical_distance(plan: Dictionary, upkeep: Dictionary, path: String) -> float:
	if str(upkeep.get("plan_id", "")) != path: return 0.0
	var distance := float(upkeep.get("distance", 0.0))
	if int(upkeep.get("route_distance_version", 0)) == 1 or not plan.has("legacy_metres"): return distance
	var old_begin := 0.0
	var physical_begin := 0.0
	for index: int in range(plan.steps.size()):
		var old := float(plan.legacy_metres[index])
		var physical := float(plan.steps[index].metres)
		if old > 0.0 and distance < old_begin + old - 0.00000001:
			return physical_begin + physical * clampf((distance - old_begin) / old, 0.0, 1.0)
		old_begin += old
		physical_begin += physical
	return minf(float(plan.metres), physical_begin)

func _region_land_physical_plan(plan: Dictionary) -> Dictionary:
	if plan.is_empty() or str(plan.get("mode", "land")) == "sea": return plan
	if int(plan.get("physical_metres_version", 0)) == 1: return plan
	var view := plan.duplicate(true)
	var legacy: Array[float] = []
	var current: bool = plan.steps.all(func(step: Dictionary) -> bool: return step.has("travel_factor"))
	var total := 0.0
	for index: int in range(view.steps.size()):
		var step: Dictionary = view.steps[index]
		var old := float(step.metres)
		var physical := 0.0 if index == view.steps.size() - 1 else RegionRoute.SITE_METRES * (0.5 if index == 0 else 1.0)
		legacy.append(old)
		step.metres = physical
		if not current: step.travel_factor = physical / maxf(0.000001, old) if physical > 0.0 else 1.0
		total += physical
	view.metres = total
	view.physical_metres_version = 1
	if not current: view.legacy_metres = legacy
	return view

func _region_npc_sea_boundary_body(token: String) -> Dictionary:
	# Derived admission query. It advances no original body, time or sea cursor.
	var reference: Dictionary = region_registry().parties.get(token, {})
	if reference.get("controller") != "npc" or reference.get("phase") != "travelling": return {"ok": true, "eligible": false}
	var selected := _region_npc_party(token)
	if not selected.ok: return selected
	var party: Dictionary = selected.party
	if party.get("mode") != "sea" or not party.upkeep.get("live", {}).is_empty(): return {"ok": true, "eligible": false}
	if not party.content.get("actors", {}).is_empty() or int(party.content.get("controlled_person_id", -1)) != -1: return fail("NPC_PARTY_AUTHORITY")
	if not region_original_party_progress.is_valid(): return fail("MISSING_REGION_PARTY_PROGRESS")
	var host: Object = region_original_party_progress.get_object()
	if not host is TerrainLab or host.site_controller.region_slot != self: return fail("INVALID_REGION_PARTY_PROGRESS")
	var restored: Dictionary = host.prepare_region_party_original_owner(token, party, self)
	if not restored.ok: return restored
	var proved := region_original_party_runtime_proof(token, party)
	if not proved.ok: return proved
	var planned := _region_npc_plan(token)
	if not planned.ok: return planned
	if planned.plan.get("mode") != "sea": return fail("CORRUPT_ROUTE")
	var projection := region_sea_pose_projection(planned.plan, party)
	if not projection.ok: return projection
	var cursor: Dictionary = party.upkeep.sea_cursor
	var moving := false
	var next_action: Dictionary = {}
	if int(cursor.action_index) < planned.plan.action_steps.size():
		var transport := RegionTravel.prepare_transport(party.duplicate(true))
		if not transport.ok: return transport
		moving = bool(transport.can_move) and not bool(party.upkeep.resting)
		next_action = planned.plan.action_steps[int(cursor.action_index)]
	var boats := {}
	for identity: String in party.content.vehicles:
		var boat: Dictionary = party.content.vehicles[identity]
		if str(boat.get("kind", "")) != "ship": return fail("PARTY_BODY_CLOSURE")
		var pose: Dictionary = projection.poses.get(identity, {})
		var anchor: Array = pose.get("from", pose.get("world_anchor", [])) if float(pose.get("duration_action_seconds", 0.0)) > 0.0 else pose.get("world_anchor", [])
		if anchor.size() != 2 or not _whole(anchor[0], -2147483648, 2147483647) or not _whole(anchor[1], -2147483648, 2147483647): return fail("CORRUPT_SEA_CURSOR")
		var at := Vector2i(int(anchor[0]), int(anchor[1]))
		var facing := Vector2i(int(pose.facing[0]), int(pose.facing[1]))
		var occupied := Ship.footprint(str(boat.ship_type), at, facing)
		var claims: Array[Vector2i] = occupied.duplicate()
		var proposed: Array[Vector2i] = []
		if float(pose.get("duration_action_seconds", 0.0)) > 0.0:
			claims = Ship.swept_footprint(str(boat.ship_type), at, Vector2i(int(pose.from_facing[0]), int(pose.from_facing[1])),
				Vector2i(int(pose.to[0]), int(pose.to[1])), Vector2i(int(pose.to_facing[0]), int(pose.to_facing[1])))
		elif moving and not next_action.is_empty() and str(next_action.vehicle_id) == identity:
			var origin := Vector2i(int(next_action.from_site[0]) * 100, -int(next_action.from_site[1]) * 100)
			var start := origin + Vector2i(int(next_action.from[0]), int(next_action.from[1]))
			if start != at or next_action.from_facing != pose.facing: return fail("SEA_ACTION_CONTRACT")
			var measured := _region_sea_action_duration(party, next_action)
			if not measured.ok: return measured
			proposed = Ship.swept_footprint(str(boat.ship_type), start, facing, origin + Vector2i(int(next_action.anchor[0]), int(next_action.anchor[1])), Vector2i(int(next_action.facing[0]), int(next_action.facing[1])))
		if occupied.is_empty() or claims.is_empty(): return fail("CORRUPT_SHIP_SWEEP")
		boats[identity] = {"reference": party.content.travel_identity.refs.vehicle[identity].duplicate(true), "occupied": occupied, "claims": claims, "proposed": proposed}
	var crew := {}
	for person_id: int in party.person_ids:
		var person: Dictionary = proved.lab.site_controller.vehicles.ship_person(person_id)
		if person.is_empty() or not person.owner.combat_can_act(int(person.unit)) or bool(person.captive): continue
		var boat_id := str(person.row.get("embarked_vehicle_id", ""))
		var boat: Dictionary = party.content.vehicles.get(boat_id, {})
		if boat.is_empty() or not SiteVehicleTransport.ship_afloat(boat): continue
		var pose: Dictionary = projection.poses.get(boat_id, {})
		var local: Vector2 = proved.lab.site_controller.vehicles.ship_local_position(person_id)
		if not local.is_finite(): return fail("NOT_EMBARKED")
		var direction := Vector2(float(pose.facing[0]), float(pose.facing[1]))
		if pose.has("action"):
			var ending := Vector2(float(pose.to_facing[0]), float(pose.to_facing[1]))
			direction = direction.rotated(direction.angle_to(ending) * float(pose.get("weight", 0.0)))
		var ground := Vector2(float(pose.world_anchor[0]), float(pose.world_anchor[1])) + Vector2(-direction.y, direction.x) * local.x + direction * local.y + Vector2.ONE * 0.5
		crew[str(person_id)] = {"reference": party.content.travel_identity.refs.person[str(person_id)].duplicate(true),
			"world_ground": [ground.x, ground.y], "faction": int(person.owner.faction_id), "boat": boat_id}
	return {"ok": true, "eligible": true, "party": party, "proof": proved.proof, "boats": boats, "crew": crew}

func _region_npc_sea_pair_boundary(incoming_token: String, primary_token: String) -> Dictionary:
	if incoming_token.is_empty() or primary_token.is_empty() or incoming_token == primary_token: return fail("INVALID_PARTY_JOIN")
	var first := _region_npc_sea_boundary_body(incoming_token)
	if not first.ok or not first.get("eligible", false): return first if not first.ok else {"ok": true, "contact": false}
	var second := _region_npc_sea_boundary_body(primary_token)
	if not second.ok or not second.get("eligible", false): return second if not second.ok else {"ok": true, "contact": false}
	for a: String in first.boats:
		for b: String in second.boats:
			var left: Dictionary = first.boats[a]
			var right: Dictionary = second.boats[b]
			if left.occupied.any(func(cell: Vector2i) -> bool: return right.occupied.has(cell)): return fail("NPC_SEA_ACCEPTED_HULL_OVERLAP", "保留已接受反例；不能強制完成或倒退修船體")
			var conflict: bool = left.proposed.any(func(cell: Vector2i) -> bool: return right.claims.has(cell)) or right.proposed.any(func(cell: Vector2i) -> bool: return left.claims.has(cell)) \
				or left.proposed.any(func(cell: Vector2i) -> bool: return right.proposed.has(cell))
			var near := {}
			for first_id: String in first.crew:
				var first_person: Dictionary = first.crew[first_id]
				if first_person.boat != a: continue
				for second_id: String in second.crew:
					var second_person: Dictionary = second.crew[second_id]
					if second_person.boat != b or int(first_person.faction) == int(second_person.faction): continue
					var first_ground := Vector2(float(first_person.world_ground[0]), float(first_person.world_ground[1]))
					var second_ground := Vector2(float(second_person.world_ground[0]), float(second_person.world_ground[1]))
					if first_ground.distance_to(second_ground) <= 1.05:
						near = {"first": first_person.duplicate(true), "second": second_person.duplicate(true)}
						break
				if not near.is_empty(): break
			if not conflict and near.is_empty(): continue
			return {"ok": true, "contact": true, "receipt": {"kind": "npc_sea_sweep_boundary", "incoming_token": incoming_token, "primary_token": primary_token,
				"at": float(control.logical_game_seconds), "action_seconds": float(control.fire_clock.action_seconds),
				"first_vehicle": a, "second_vehicle": b, "first": left.duplicate(true), "second": right.duplicate(true),
				"motion_admission_conflict": conflict, "current_original_crew_contact": near}}
	return {"ok": true, "contact": false}

func _region_validate_npc_sea_pair_event(event: Dictionary) -> Dictionary:
	var queued := {}
	for original: Dictionary in region_registry().events:
		if str(original.id) == str(event.get("id", "")): queued = original
	if queued.is_empty() or queued.status != "pending" or var_to_bytes(queued) != var_to_bytes(event): return fail("STALE_REGION_EVENT")
	if queued.kind != "reinforcement" or bool(queued.player) or float(queued.at) != float(control.logical_game_seconds): return fail("STALE_REGION_CONTACT")
	var receipt: Dictionary = queued.payload.get("contact_receipt", {})
	if receipt.get("kind") != "npc_sea_sweep_boundary" or str(queued.payload.get("token", "")) != str(receipt.get("incoming_token", "")): return fail("INVALID_REGION_CONTACT")
	var current := _region_npc_sea_pair_boundary(str(receipt.incoming_token), str(receipt.get("primary_token", "")))
	if not current.ok: return current
	return {"ok": true, "valid": current.get("contact", false) and var_to_bytes(current.get("receipt", {})) == var_to_bytes(receipt)}

func _region_land_route_node(party: Dictionary, plan: Dictionary, path: String, index: int, component: int = -1) -> Dictionary:
	var step: Dictionary = plan.steps[index]
	var cell := RegionRoute.entry_cell(step)
	if cell.x < 0:
		var retained: Dictionary = party.get("upkeep", {}).get("route_node", {})
		if retained.get("site") == step.site and retained.get("cell") is Array and retained.cell.size() == 2:
			cell = Vector2i(int(retained.cell[0]), int(retained.cell[1]))
		else:
			var body: Dictionary = RegionTravel._body_records(party.content).get(int(party.leader_person_id), {})
			if body.get("cell") is Array and body.cell.size() == 2: cell = Vector2i(int(body.cell[0]), int(body.cell[1]))
	return {"version": 1, "plan_id": path, "index": index, "site": step.site.duplicate(),
		"component": int(step.component) if component < 0 else component, "cell": [cell.x, cell.y],
		"vehicle_poses": step.get("vehicle_poses", {}).duplicate(true)}

func _region_land_route_preview(party: Dictionary, plan: Dictionary, path: String, to: float, moving: bool = true) -> Dictionary:
	var world := float(control.logical_game_seconds)
	if absf(float(party.get("upkeep", {}).get("at", -1.0)) - world) > 0.00000001: return fail("UNSETTLED_PARTY")
	if not plan.get("steps") is Array or plan.steps.size() < 2 or not _seconds(to) or to < world: return fail("CORRUPT_ROUTE")
	plan = _region_land_physical_plan(plan)
	var input: Dictionary = party.duplicate(true)
	var distance := _region_land_physical_distance(plan, input.upkeep, path)
	input.upkeep.plan_id = path
	input.upkeep.distance = distance
	input.upkeep.route_distance_version = 1
	input.upkeep.erase("pending_route_entry")
	var position := _region_route_position(plan, distance)
	var index := int(position.step_index)
	var blocked: Dictionary = input.upkeep.get("route_blocked", {})
	if str(blocked.get("plan_id", "")) == path:
		index = int(blocked.get("from_index", -1))
	else:
		blocked = {}
		input.upkeep.erase("route_blocked")
	if index < 0 or index >= plan.steps.size(): return fail("CORRUPT_ROUTE")
	var node: Dictionary = input.upkeep.get("route_node", {})
	if str(node.get("plan_id", "")) != path or int(node.get("index", -1)) != index:
		node = _region_land_route_node(input, plan, path, index)
	input.upkeep.route_node = node
	if index == plan.steps.size() - 1:
		return {"ok": true, "party": input, "source_party": party, "at": world, "metres": 0.0,
			"events": [], "consumed_rations": 0.0, "arrived": true,
			"position": {"site": node.site.duplicate(), "component": int(node.component), "step_index": index, "fraction": 1.0}}
	var coordinates: Array[Vector2i] = [Vector2i(int(plan.steps[index].site[0]), int(plan.steps[index].site[1]))]
	if index + 1 < plan.steps.size(): coordinates.append(Vector2i(int(plan.steps[index + 1].site[0]), int(plan.steps[index + 1].site[1])))
	var prepared := prepare_region_route_context(null, input, coordinates)
	if not prepared.ok: return prepared
	var context: Dictionary = prepared.context
	context.capabilities.start_cell = Vector2i(int(node.cell[0]), int(node.cell[1]))
	context.capabilities.vehicle_poses = node.vehicle_poses.duplicate(true)
	var entry := {"ok": true}
	if index + 1 < plan.steps.size(): entry = RegionRoute.revalidate_land_entry(source, plan.steps, index, context)
	if not blocked.is_empty() and str(blocked.get("plan_id", "")) == path and entry.ok:
		input.upkeep.pending_route_entry = {"version": 1, "plan_id": path, "from_index": index, "to_index": index + 1,
			"source_node": node.duplicate(true), "distance": distance, "at": world}
		index += 1
		node = _region_land_route_node(input, plan, path, index, int(entry.component))
		input.upkeep.route_node = node
		input.upkeep.erase("route_blocked")
		input.upkeep.blocked_reason = ""
		blocked = {}
		if index == plan.steps.size() - 1:
			return {"ok": true, "party": input, "source_party": party, "at": world, "metres": 0.0,
				"events": [], "consumed_rations": 0.0, "arrived": true, "entry_ready": true,
				"position": {"site": node.site.duplicate(), "component": int(node.component), "step_index": index, "fraction": 1.0}}
		coordinates = [Vector2i(int(plan.steps[index].site[0]), int(plan.steps[index].site[1])),
			Vector2i(int(plan.steps[index + 1].site[0]), int(plan.steps[index + 1].site[1]))]
		prepared = prepare_region_route_context(null, input, coordinates)
		if not prepared.ok: return prepared
		context = prepared.context
		context.capabilities.start_cell = Vector2i(int(node.cell[0]), int(node.cell[1]))
		context.capabilities.vehicle_poses = node.vehicle_poses.duplicate(true)
		entry = RegionRoute.revalidate_land_entry(source, plan.steps, index, context)
	var leg := RegionRoute.current_land_leg(source, plan.steps[index], context)
	if not leg.ok: return leg
	var source_component := RegionRoute.component_of(leg.derived, Vector2i(int(node.cell[0]), int(node.cell[1])))
	if source_component >= 0: node.component = source_component
	input.upkeep.route_node = node
	var options := {"moving": moving and blocked.is_empty() and source_component >= 0, "safe_rest": true, "speed_multiplier": float(leg.speed_multiplier)}
	var endpoint := RegionTravel.next_upkeep_event(input, options.merged({"until": to}, true))
	if not endpoint.ok: return endpoint
	var end := minf(to, float(endpoint.at))
	var outcome := RegionTravel.advance_upkeep(input, end, options)
	if not outcome.ok: return outcome
	var boundary := 0.0
	for step_index: int in range(index + 1): boundary += float(plan.steps[step_index].metres)
	var remaining := maxf(0.0, boundary - distance)
	if bool(options.moving) and float(outcome.metres) > remaining + 0.00000001:
		var low := world
		var high := float(outcome.at)
		for _iteration: int in 45:
			var middle := (low + high) * 0.5
			var probe := RegionTravel.advance_upkeep(input, middle, options)
			if not probe.ok: return probe
			if float(probe.metres) < remaining: low = middle
			else: high = middle
		outcome = RegionTravel.advance_upkeep(input, high, options)
		if not outcome.ok: return outcome
	var candidate: Dictionary = outcome.party
	candidate.upkeep.distance = minf(float(plan.metres), distance + float(outcome.metres))
	candidate.upkeep.plan_id = path
	var crossing: bool = bool(options.moving) and candidate.upkeep.distance >= boundary - 0.00000001 and index + 1 < plan.steps.size()
	if crossing:
		candidate.upkeep.distance = boundary
		candidate.upkeep.pending_route_entry = {"version": 1, "plan_id": path, "from_index": index, "to_index": index + 1,
			"source_node": node.duplicate(true), "distance": boundary, "at": float(candidate.upkeep.at)}
		if entry.ok:
			candidate.upkeep.route_node = _region_land_route_node(candidate, plan, path, index + 1, int(entry.component))
			candidate.upkeep.erase("route_blocked")
			candidate.upkeep.blocked_reason = str(outcome.get("reason", ""))
		else:
			candidate.upkeep.route_node = node.duplicate(true)
			candidate.upkeep.route_blocked = {"version": 1, "plan_id": path, "from_index": index,
				"to_index": index + 1, "code": str(entry.get("code", "WALL_EDGE")),
				"message": str(entry.get("message", "原路線下一 Site 入口已受阻"))}
			candidate.upkeep.blocked_reason = candidate.upkeep.route_blocked.message
	elif not blocked.is_empty(): candidate.upkeep.blocked_reason = str(entry.get("message", blocked.get("message", "原路線入口受阻")))
	else: candidate.upkeep.blocked_reason = "原旅隊目前 node 已無可達出口" if source_component < 0 else str(outcome.get("reason", ""))
	var actual: Dictionary = candidate.upkeep.route_node
	var before_node := 0.0
	for step_index: int in range(int(actual.index)): before_node += float(plan.steps[step_index].metres)
	outcome.source_party = party
	outcome.position = {"site": actual.site.duplicate(), "component": int(actual.component),
		"step_index": int(actual.index), "fraction": clampf((float(candidate.upkeep.distance) - before_node) / maxf(0.000001, float(plan.steps[int(actual.index)].metres)), 0.0, 1.0)}
	outcome.arrived = candidate.upkeep.distance >= float(plan.metres) - 0.00000001 and not candidate.upkeep.has("route_blocked")
	return outcome

func _region_map_actual_world_target(party: Dictionary) -> Dictionary:
	var frame: Dictionary = party.upkeep.live.frame
	var leader: Dictionary = frame.people.get(str(int(party.leader_person_id)), {})
	if not RegionTravel._frame_pair(leader.get("world_cell")): return fail("MISSING_ORIGINAL_POSITION")
	var poses := {}
	for identity: String in party.content.get("vehicles", {}):
		if not RegionTravel._frame_pair(frame.vehicles.get(identity, {}).get("world_cell")):
			return fail("MISSING_ORIGINAL_POSITION")
		poses[identity] = {"world_anchor": frame.vehicles[identity].world_cell.duplicate(), "facing": party.content.vehicles[identity].facing.duplicate()}
	return {"ok": true, "world_cell": leader.world_cell.duplicate(), "vehicle_poses": poses}

func _region_map_motion_target(before: Dictionary, plan: Dictionary, outcome: Dictionary) -> Dictionary:
	if plan.is_empty(): return _region_map_actual_world_target(before)
	if not outcome.get("position") is Dictionary: return fail("MISSING_ORIGINAL_POSITION")
	var position: Dictionary = outcome.position
	var index := int(position.get("step_index", -1))
	if index < 0 or index >= plan.steps.size(): return fail("CORRUPT_ROUTE")
	var step: Dictionary = plan.steps[index]
	var site := Vector2i(int(step.site[0]), int(step.site[1]))
	var base := Vector2i(site.x * 100, -site.y * 100)
	var start := RegionRoute.entry_cell(step)
	if index == 0:
		var node: Dictionary = before.upkeep.get("route_node", {})
		if node.get("site") != step.site or not RegionTravel._frame_pair(node.get("cell")): return fail("MISSING_ROUTE_NODE")
		start = Vector2i(int(node.cell[0]), int(node.cell[1]))
	if start.x < 0: return fail("MISSING_ORIGINAL_POSITION")
	var finish := start
	if index + 1 < plan.steps.size():
		var next: Dictionary = plan.steps[index + 1]
		finish = RegionRoute.Adapter.boundary_cell(RegionRoute.opposite(int(next.edge)), int(next.offset))
		if not outcome.party.upkeep.has("route_blocked"):
			finish += TerrainData.DIRECTIONS[RegionRoute.opposite(int(next.edge))]
	var world := base + Vector2i((Vector2(start).lerp(Vector2(finish), clampf(float(position.get("fraction", 0.0)), 0.0, 1.0))).floor())
	var poses := {}
	for identity: String in before.content.get("vehicles", {}):
		var vehicle: Dictionary = before.content.vehicles[identity]
		var pose: Dictionary = step.get("vehicle_poses", {}).get(identity, {})
		var at := Vector2i(-1, -1)
		var facing := Vector2i.ZERO
		if index + 1 < plan.steps.size():
			var path: Variant = plan.steps[index + 1].get("vehicle_paths", {}).get(identity)
			if not path is Array or path.is_empty(): return fail("MISSING_ORIGINAL_VEHICLE_PATH")
			var point: Variant = path[clampi(floori(float(position.get("fraction", 0.0)) * float(path.size() - 1)), 0, path.size() - 1)]
			if not point is Array or point.size() != 4: return fail("CORRUPT_VEHICLE_PATH")
			facing = Vector2i(int(point[2]), int(point[3]))
			var operator := Vector2i(int(point[0]), int(point[1]))
			at = base + (operator - facing * 2 if str(vehicle.kind) == "wagon" else operator + facing)
		elif RegionTravel._frame_pair(pose.get("anchor")) and RegionTravel._frame_pair(pose.get("facing")):
			at = base + Vector2i(int(pose.anchor[0]), int(pose.anchor[1]))
			facing = Vector2i(int(pose.facing[0]), int(pose.facing[1]))
		else: return fail("MISSING_ORIGINAL_VEHICLE_PATH")
		poses[identity] = {"world_anchor": [at.x, at.y], "facing": [facing.x, facing.y]}
	return {"ok": true, "world_cell": [world.x, world.y], "vehicle_poses": poses}

func _region_map_route_reference(party: Dictionary) -> Dictionary:
	if str(party.get("upkeep", {}).get("live", {}).get("upkeep", "")) != "mapBody": return {}
	var actual := _region_map_actual_world_target(party)
	if not actual.ok: return {}
	var world := Vector2i(int(actual.world_cell[0]), int(actual.world_cell[1]))
	var site := Vector2i(Grid.floor_div(world.x, 100), -Grid.floor_div(world.y, 100))
	var base := Vector2i(site.x * 100, -site.y * 100)
	var local := world - base
	var poses := {}
	for identity: String in party.content.get("vehicles", {}):
		var vehicle: Dictionary = party.content.vehicles[identity]
		var operator: Dictionary = party.upkeep.live.frame.people.get(str(int(vehicle.operator_id)), {})
		if not RegionTravel._frame_pair(operator.get("world_cell")): return {}
		var at: Array = actual.vehicle_poses[identity].world_anchor
		var anchor := Vector2i(int(at[0]), int(at[1])) - base
		var person := Vector2i(int(operator.world_cell[0]), int(operator.world_cell[1])) - base
		poses[identity] = {"anchor": [anchor.x, anchor.y], "operator": [person.x, person.y], "facing": vehicle.facing.duplicate()}
	return {"site": [site.x, site.y], "cell": [local.x, local.y], "vehicle_poses": poses}

func _region_map_status_position(party: Dictionary, status: Dictionary) -> Dictionary:
	var actual := _region_map_route_reference(party)
	if actual.is_empty() or not status.get("ok", false): return status
	status.site = Vector2i(int(actual.site[0]), int(actual.site[1]))
	status.route_node_cell = Vector2i(int(actual.cell[0]), int(actual.cell[1]))
	status.vehicle_poses = actual.vehicle_poses.duplicate(true)
	return status

func _region_prepare_map_motion_outcome(before: Dictionary, status: Dictionary, outcome: Dictionary) -> Dictionary:
	if str(before.upkeep.get("live", {}).get("upkeep", "")) != "mapBody": return outcome
	var original := region_original_party_runtime_proof(str(before.party_id), before)
	if not original.ok: return original
	var target := _region_map_motion_target(before, status.plan, outcome)
	if not target.ok: return target
	var motion: Dictionary = original.lab.prepare_region_party_map_motion(before, outcome.party, target)
	if not motion.ok:
		if str(motion.get("code", "")) not in ["WALL_EDGE", "NONRIGID_ORIGINAL_FORMATION", "ORIGINAL_VEHICLE_MOTION_REQUIRED"]: return motion
		# The same original clock/food/life owner still accepts an incapable or
		# geometrically blocked group. The failed physical proposal spends no
		# distance, and the native body remains at its accepted physical pose.
		var resting: Dictionary = RegionTravel.advance_upkeep(before, float(outcome.at), {"moving": false, "safe_rest": true})
		if not resting.ok: return resting
		resting.party.upkeep.distance = float(before.upkeep.get("distance", 0.0))
		resting.party.upkeep.blocked_reason = str(motion.get("code", "WALL_EDGE"))
		resting.arrived = false
		resting.action_seconds = float(outcome.action_seconds)
		resting.position = _region_route_position(status.plan, float(resting.party.upkeep.distance))
		var frame: Dictionary = before.upkeep.live.frame
		var leader: Dictionary = frame.people[str(int(before.leader_person_id))]
		var hold_poses := {}
		for identity: String in before.content.get("vehicles", {}):
			hold_poses[identity] = {"world_anchor": frame.vehicles[identity].world_cell.duplicate(),
				"facing": before.content.vehicles[identity].facing.duplicate()}
		var hold: Dictionary = original.lab.prepare_region_party_map_motion(before, resting.party,
			{"world_cell": leader.world_cell.duplicate(), "vehicle_poses": hold_poses})
		if not hold.ok: return hold
		return resting
	return outcome

func _region_publish_land_candidate(token: String, candidate: Dictionary, expected_hash: String) -> Dictionary:
	if not region_original_party_progress.is_valid(): return fail("MISSING_REGION_PARTY_PROGRESS")
	var host: Object = region_original_party_progress.get_object()
	var original: TerrainLab = get_meta(&"region_party_owner_labs", {}).get(token)
	if not host is TerrainLab or host.site_controller == null or host.site_controller.region_slot != self \
			or not is_instance_valid(original) or original.site_controller == null or original.site_controller.region_slot != self \
			or original._region_party_token != token or original.terrain == null or original._region_bound_data != original.terrain \
			or not original.region_bind_receipt(original.terrain).get("complete", false): return fail("COMMITTED_UNBOUND")
	if expected_hash.is_empty() or original._region_party_input_hash != expected_hash \
			or original.terrain.get_meta(&"region_party_owner", {}).get("party_hash") != expected_hash \
			or absf(float(candidate.upkeep.at) - float(control.logical_game_seconds)) > 0.00000001 \
			or absf(float(candidate.upkeep.owner_action_seconds) - float(control.fire_clock.action_seconds)) > 0.00000001:
		return fail("STALE_REGION_PARTY_OWNER")
	var old_hash := str(original._region_party_input_hash)
	var old_owner: Dictionary = original.terrain.get_meta(&"region_party_owner", {}).duplicate(true)
	var captured: Dictionary = host._region_capture_original_party(original, candidate, self,
		float(candidate.upkeep.at), float(candidate.upkeep.owner_action_seconds))
	if not captured.ok: return captured
	if var_to_bytes(captured.party.content) != var_to_bytes(candidate.content):
		original._region_party_input_hash = old_hash
		original.terrain.set_meta(&"region_party_owner", old_owner)
		return fail("ROUTE_BODY_CHANGED", "原路線後驗只能發布同一已完成原身體")
	return {"ok": true, "party": captured.party, "lab": original}

func _region_revalidate_completed_land_outcome(token: String, outcome: Dictionary,
		plan: Dictionary, path: String) -> Dictionary:
	var party: Dictionary = outcome.get("party", {})
	if str(party.get("mode", "land")) != "land" or str(party.get("upkeep", {}).get("live", {}).get("upkeep", "")) == "liveBody": return {"ok": true, "outcome": outcome}
	var expected_hash := Marshalls.raw_to_base64(var_to_bytes(party)).sha256_text()
	var proof: Dictionary = party.get("upkeep", {}).get("pending_route_entry", {})
	if proof.is_empty() and party.upkeep.has("route_blocked"):
		var blocked: Dictionary = party.upkeep.route_blocked
		proof = {"version": 1, "plan_id": path, "from_index": int(blocked.get("from_index", -1)),
			"to_index": int(blocked.get("to_index", -1)), "source_node": party.upkeep.get("route_node", {}).duplicate(true),
			"distance": float(party.upkeep.get("distance", 0.0)), "at": float(party.upkeep.at)}
	elif proof.is_empty() and plan.get("steps") is Array and plan.steps.size() >= 2:
		var view := _region_land_physical_plan(plan)
		var distance := _region_land_physical_distance(view, party.upkeep, path)
		if distance >= float(view.metres) - 0.00000001:
			var from_index: int = plan.steps.size() - 2
			proof = {"version": 1, "plan_id": path, "from_index": from_index, "to_index": from_index + 1,
				"source_node": _region_land_route_node(party, plan, path, from_index), "distance": distance, "at": float(party.upkeep.at)}
			party = party.duplicate(true)
			party.upkeep.distance = distance
			party.upkeep.route_distance_version = 1
			party.upkeep.pending_route_entry = proof
	if proof.is_empty(): return {"ok": true, "outcome": outcome}
	var index := int(proof.get("from_index", -1))
	var node: Dictionary = proof.get("source_node", {})
	if proof.get("version") != 1 or str(proof.get("plan_id", "")) != path or index < 0 or index + 1 >= plan.steps.size() \
			or int(proof.get("to_index", -1)) != index + 1 or node.get("version") != 1 \
			or str(node.get("plan_id", "")) != path or int(node.get("index", -1)) != index \
			or node.get("site") != plan.steps[index].site or not RegionTravel._frame_pair(node.get("cell")) \
			or not node.get("vehicle_poses") is Dictionary or not _seconds(proof.get("at")) \
			or absf(float(proof.at) - float(party.upkeep.at)) > 0.00000001 \
			or not _seconds(proof.get("distance")) or absf(float(proof.distance) - float(party.upkeep.distance)) > 0.00000001:
		return fail("CORRUPT_ROUTE_ENTRY", "已付原入口缺同一 source node／端點 proof")
	var coordinates: Array[Vector2i] = [Vector2i(int(plan.steps[index].site[0]), int(plan.steps[index].site[1])),
		Vector2i(int(plan.steps[index + 1].site[0]), int(plan.steps[index + 1].site[1]))]
	# This seam check is the authority for a paid entry, so it reads every Site's
	# current body. Cold Sites already come from their bound original Labs. With a
	# null active_data the active Site came from its last publication instead, so a
	# paid change there (a gate closed after the last checkpoint) was invisible until
	# a later publication in the same point flipped the verdict.
	var prepared := prepare_region_route_context(_region_live_active_route_data(coordinates), party, coordinates)
	if not prepared.ok: return prepared
	var context: Dictionary = prepared.context
	context.capabilities.start_cell = Vector2i(int(node.cell[0]), int(node.cell[1]))
	context.capabilities.vehicle_poses = node.vehicle_poses.duplicate(true)
	var entry := RegionRoute.revalidate_land_entry(source, plan.steps, index, context)
	if not entry.ok and str(entry.get("code", "")) not in ["WALL_EDGE", "VEHICLE_BLOCKED", "VEHICLE_POLICY"]: return entry
	var result := outcome.duplicate(true)
	result.party = party.duplicate(true)
	var accepted: Dictionary = result.party
	if entry.ok:
		accepted.upkeep.route_node = _region_land_route_node(accepted, plan, path, index + 1, int(entry.component))
		accepted.upkeep.erase("route_blocked")
		accepted.upkeep.blocked_reason = str(result.get("reason", ""))
		result.arrived = float(accepted.upkeep.distance) >= float(_region_land_physical_plan(plan).metres) - 0.00000001
	else:
		var retained := node.duplicate(true)
		var current_leg := RegionRoute.current_land_leg(source, plan.steps[index], context)
		if not current_leg.ok: return current_leg
		var current_component := RegionRoute.component_of(current_leg.derived, Vector2i(int(node.cell[0]), int(node.cell[1])))
		if current_component >= 0: retained.component = current_component
		accepted.upkeep.route_node = retained
		accepted.upkeep.route_blocked = {"version": 1, "plan_id": path, "from_index": index, "to_index": index + 1,
			"code": str(entry.code), "message": str(entry.get("message", "原已付入口目前受阻"))}
		accepted.upkeep.blocked_reason = accepted.upkeep.route_blocked.message
		result.arrived = false
	var captured := _region_publish_land_candidate(token, accepted, expected_hash)
	if not captured.ok: return captured
	result.party = captured.party
	if outcome.has("source_party"): result.source_party = outcome.source_party
	result.position = _region_current_land_position(captured.party, plan, path)
	return {"ok": true, "outcome": result, "blocked": not entry.ok, "entry": entry}

## The active Site's live original body when one of `coordinates` is that Site and
## its original Lab is bound, through the same owner adapter the dispatchers use.
## With no active Site (a player journey) or no wired adapter there is no live
## active body, and the route context keeps the selected publication as before.
func _region_live_active_route_data(coordinates: Array[Vector2i]) -> TerrainData:
	var active_id := str(control.get("active_site_id", ""))
	if active_id.is_empty() or not region_owner_lab.is_valid(): return null
	var active_coordinate: Variant = null
	for coordinate: Vector2i in coordinates:
		if Grid.site_id(str(pin.atlas_id), coordinate) == active_id: active_coordinate = coordinate
	if active_coordinate == null: return null
	var selected: Variant = region_owner_lab.call(active_id, "live")
	if not selected is Dictionary or not bool(selected.get("ok", false)) or not selected.get("lab") is TerrainLab: return null
	var lab: TerrainLab = selected.lab
	if lab.terrain == null or str(lab.terrain.site.get("id", "")) != active_id or lab.site_controller == null or lab.site_controller.region_slot != self: return null
	return lab.terrain

func acknowledge_region_original_party_bind(token: String, party: Dictionary, original: TerrainLab, receipt: Dictionary) -> Dictionary:
	var selected := region_live_party_proof(token)
	if not selected.ok: return selected
	var checked := validate_region_live_party_proof(token, party, selected.proof)
	if not checked.ok: return checked
	if not selected.original_live_graph.is_empty() or party.upkeep.has("live"):
		return fail("REGION_PARTY_MODE", "專用 party graph 須走原 selected bind")
	var fingerprint := str(selected.proof.party_hash)
	var owner := "travel:" + token
	if not is_instance_valid(original) or not original.is_inside_tree() or original.site_controller == null \
			or original.site_controller.region_slot != self or original.terrain == null \
			or original._region_bound_data != original.terrain or str(original.terrain.site.id) != owner \
			or original._region_party_token != token or original._region_party_input_hash != fingerprint \
			or original.terrain.get_meta(&"region_party_owner", {}).get("party_hash") != fingerprint \
			or original.region_bind_receipt(original.terrain) != receipt or receipt.get("ok") != true \
			or receipt.get("complete") != true or receipt.get("owners_restored") != true:
		return fail("REGION_BIND", "原 party 完整 body／綁定收據不同")
	var prior: Dictionary = region_registry().modes.get(owner, {})
	if not prior.is_empty():
		var valid := GameplayClock.validate_mode(prior, owner, float(control.logical_game_seconds))
		if not valid.ok: return valid
		if prior.mode != "cold_exact" or prior.backend != "gd" or prior.consumer != "original_region_travel" \
				or int(prior.generation) != int(_marker.generation): return fail("REGION_PARTY_MODE")
		if prior.activation.get("complete") == true: return {"ok": true, "mode": prior}
	var activation := receipt.duplicate(true)
	activation.owner = owner
	activation.mode = "cold_exact"
	activation.generation = int(_marker.generation)
	activation.backend = "gd"
	activation.consumer = "original_region_travel"
	return activate_region_mode(owner, "cold_exact", "original_region_travel", activation, "gd")

func _detached_cold_copy(data: TerrainData, original: TerrainLab) -> Dictionary:
	if original == null or not data.site.has("region_snapshot"):
		if data.site.has("region_snapshot"):
			var stored := Store.validate_region_snapshot(data, {})
			if not stored.ok:
				if str(stored.get("code", "")) == "CORRUPT_REGION_SNAPSHOT":
					stored["source"] = "cold_detach_unbound"
					stored["site_id"] = str(data.site.get("id", ""))
				return stored
		return {"ok": true, "data": Env.navigation_for_state(data, data.site.duplicate(true))}
	var before_hash := RegionCheckpoint.state_hash(data.site)
	var stored_snapshot: Variant = data.site.get("region_snapshot")
	if stored_snapshot is Dictionary: stored_snapshot = stored_snapshot.duplicate(true)
	var effects_complete: bool = original._region_point_pending.is_empty() and not original._region_point_consuming and pending_region_events().is_empty()
	var capture: Dictionary = original.site_controller.capture_region_checkpoint("region_checkpoint" if effects_complete else "region_barrier",
		effects_complete, original._region_point_pending)
	var after_hash := RegionCheckpoint.state_hash(data.site)
	if before_hash != after_hash or data.site.get("region_snapshot") != stored_snapshot:
		return {"ok": false, "code": "REGION_DETACH_MUTATED_ORIGINAL", "message": "原 owner 擷取改變了原 Lab 狀態；拒絕分離副本",
			"source": "cold_detach", "site_id": str(data.site.get("id", "")), "before_hash": before_hash, "after_hash": after_hash}
	if not capture.ok: return capture
	if not capture.get("state") is Dictionary or not capture.state.has("region_snapshot"):
		return fail("MISSING_FRESH_REGION_SNAPSHOT", "原 owner 未產生新的 region snapshot；拒絕用舊快照分離")
	var state: Dictionary = capture.state.duplicate(true)
	# Hash-excluded transient fields return to the copy exactly as the original held them.
	for field: String in ["water_links", "water_status", "notices"]:
		if data.site.has(field): state[field] = data.site[field].duplicate(true) if data.site[field] is Dictionary or data.site[field] is Array else data.site[field]
		else: state.erase(field)
	var copy := Env.navigation_for_state(data, state)
	var fresh := Store.validate_region_snapshot(copy, {})
	if not fresh.ok:
		if str(fresh.get("code", "")) == "CORRUPT_REGION_SNAPSHOT":
			fresh["source"] = "cold_detach_fresh"
			fresh["site_id"] = str(data.site.get("id", ""))
		return fresh
	return {"ok": true, "data": copy, "before_hash": before_hash, "after_hash": after_hash}


func _initial_technology_categories() -> Array:
	# POSITIVE-ONLY RELEASE CANDIDATE: Root may publish this method only AFTER
	# the named four-category birth/pin/first-earned/manufacture/master-loss/
	# cold/UI/contact/source + Eco/Region release gates have actually passed.
	# Default existing method [] is retained until that explicit publication.
	var catalog: Script = load("res://scripts/terrain_lab/site_technology_catalog.gd")
	var result: Array = []
	for identity: String in ["F04", "F06", "F11", "F12"]:
		var node: Dictionary = catalog.call("get_node", identity) if catalog != null else {}
		if node.get("id") != identity or node.get("scope") != "family" or node.get("enabled") != true or node.get("status") != "implemented" or node.get("tuning_confirmed") != true: return []
		result.append(identity)
	return result # Original new_policy validates and freezes this original pin.


func _region_guard_current_land_arrival(token: String, party: Dictionary, plan: Dictionary, path: String) -> Dictionary:
	if str(party.get("mode", "land")) != "land" or str(party.get("upkeep", {}).get("live", {}).get("upkeep", "")) == "liveBody":
		return {"ok": true, "party": party}
	if not region_original_party_progress.is_valid(): return fail("MISSING_REGION_PARTY_PROGRESS")
	var host: Object = region_original_party_progress.get_object()
	if not host is TerrainLab or host.site_controller == null or host.site_controller.region_slot != self: return fail("INVALID_REGION_PARTY_PROGRESS")
	var restored: Dictionary = host.prepare_region_party_original_owner(token, party, self)
	if not restored.ok: return restored
	var runtime := region_original_party_runtime_proof(token, party)
	if not runtime.ok: return runtime
	var validated := _region_revalidate_completed_land_outcome(token, {"ok": true, "party": party, "arrived": true}, plan, path)
	if not validated.ok: return validated
	var accepted: Dictionary = validated.outcome.party
	var player := str(region_travel_journey().get("token", "")) == token
	if player:
		_travel_party_runtime = accepted
		_travel_party_runtime_token = token
	else:
		_region_npc_party_runtime[token] = accepted
		if validated.outcome.has("position"):
			region_registry().parties[token].position = {"site": validated.outcome.position.site.duplicate(), "component": int(validated.outcome.position.component)}
	if bool(validated.get("blocked", false)) or accepted.upkeep.has("route_blocked"):
		return fail("REGION_ENTRY_BLOCKED", "已付原到站入口目前受阻，保留同一 source node")
	var position := _region_current_land_position(accepted, plan, path)
	if int(position.step_index) != plan.steps.size() - 1 or not bool(validated.outcome.get("arrived", false)):
		return fail("INCOMPLETE_JOURNEY", "原旅隊尚未完成同一實際路線")
	return {"ok": true, "party": accepted, "position": position}

## A navigation-only forecast can legitimately fail at its paid point. The
## ORIGINAL event completes once with a genuine current-owner no-effect
## receipt. Its ID/time/sequence stay immutable; retry uses a new attempt ID.


func _region_land_event_committed_endpoint(event: Dictionary) -> Dictionary:
	var payload: Dictionary = event.get("payload", {})
	var owner := str(event.get("owner", ""))
	if owner.is_empty() or owner != str(control.active_site_id) or not region_travel_journey().is_empty():
		return {"ok": true, "committed": false}
	var player_token := str(payload.get("player_token", ""))
	var npc_token := str(payload.get("token", ""))
	var player_published := not player_token.is_empty() and str(_marker.get("transfer_token", "")) == player_token
	var npc_published := false
	if not npc_token.is_empty():
		var reference: Dictionary = region_registry().parties.get(npc_token, {})
		npc_published = str(reference.get("controller", "")) == "npc" and str(reference.get("phase", "")) == "entered" \
			and str(reference.get("destination_site", "")) == owner \
			and absf(float(reference.get("arrival_game_seconds", -1.0)) - float(event.at)) < 0.00000001 \
			and str(payload.get("entered_site", owner)) == owner
	if not player_published and not npc_published: return {"ok": true, "committed": false}
	if not player_token.is_empty() and not player_published or not npc_token.is_empty() and not npc_published:
		return fail("STALE_REGION_ENDPOINT", "原已提交 joint 端點引用不同")
	var mode: Dictionary = region_registry().modes.get(owner, {})
	if not GameplayClock.validate_mode(mode, owner, float(control.logical_game_seconds)).ok \
			or int(mode.get("generation", -1)) != int(_marker.generation): return fail("COMMITTED_UNBOUND")
	if not region_owner_lab.is_valid(): return fail("MISSING_REGION_ADAPTER")
	var selected: Dictionary = region_owner_lab.call(owner, "live")
	if not selected.get("ok", false) or not selected.get("lab") is TerrainLab: return selected
	var actual: TerrainLab = selected.lab
	if actual.site_controller == null or actual.site_controller.region_slot != self or actual.terrain == null \
			or actual._region_bound_data != actual.terrain or str(actual.terrain.site.id) != owner: return fail("COMMITTED_UNBOUND")
	var coordinate := _coordinate(actual.terrain)
	if not coordinate.ok or not _marker.sites.has(_site_key(coordinate.site)): return fail("COMMITTED_UNBOUND")
	var receipt := actual.region_bind_receipt(actual.terrain)
	if not receipt.get("complete", false) or not receipt.get("owners_restored", false) \
			or str(receipt.get("owner", "")) != owner or int(receipt.get("generation", -1)) != int(_marker.generation):
		return fail("COMMITTED_UNBOUND")
	return {"ok": true, "committed": true, "receipt": receipt}


func _region_consume_blocked_land_event(event: Dictionary) -> Dictionary:
	if str(event.get("kind", "")) not in ["arrival", "reinforcement", "player_arrival", "player_encounter"]: return {"ok": true, "handled": false}
	var payload: Dictionary = event.get("payload", {})
	if str(event.kind) == "reinforcement":
		if str(payload.get("contact_receipt", {}).get("kind", "")) != "npc_siege_channel" or str(region_registry().parties.get(str(payload.get("token", "")), {}).get("phase", "")) != "travelling": return {"ok": true, "handled": false}
	if str(event.kind) == "player_encounter" and (not payload.has("contact_receipt") or payload.has("battle_id")):
		return {"ok": true, "handled": false}
	# The same-point static contact is consumed before its arrival. Once the NPC
	# party has entered, its arrival event is that entry's duplicate (validated by
	# prepare_npc_region_arrival), not a navigation attempt.
	if str(event.kind) == "arrival" and str(payload.get("player_token", "")).is_empty() \
			and str(region_registry().parties.get(str(payload.get("token", "")), {}).get("phase", "")) == "entered":
		return {"ok": true, "handled": false}
	var published := _region_land_event_committed_endpoint(event)
	if not published.ok: return published
	if bool(published.get("committed", false)): return {"ok": true, "handled": false}
	var tokens: Array[String] = []
	var npc_token := str(payload.get("token", ""))
	if not npc_token.is_empty(): tokens.append(npc_token)
	var player_token := str(payload.get("player_token", ""))
	if str(event.kind) == "player_encounter": player_token = str(region_travel_journey().get("token", ""))
	if not player_token.is_empty() and player_token not in tokens: tokens.append(player_token)
	var blocked := false
	var receipts: Array = []
	for token: String in tokens:
		var player := str(region_travel_journey().get("token", "")) == token
		var loaded := region_travel_party() if player else _region_npc_party(token)
		if not loaded.ok: return loaded
		var party: Dictionary = loaded.party
		if str(party.get("mode", "land")) != "land" or str(party.get("upkeep", {}).get("live", {}).get("upkeep", "")) == "liveBody": continue
		if not region_original_party_progress.is_valid(): return fail("MISSING_REGION_PARTY_PROGRESS")
		var host: Object = region_original_party_progress.get_object()
		if not host is TerrainLab or host.site_controller == null or host.site_controller.region_slot != self: return fail("INVALID_REGION_PARTY_PROGRESS")
		var restored: Dictionary = host.prepare_region_party_original_owner(token, party, self)
		if not restored.ok: return restored
		var runtime := region_original_party_runtime_proof(token, party)
		if not runtime.ok: return runtime
		var planned := region_travel_plan() if player else _region_npc_plan(token)
		if not planned.ok: return planned
		var path := str(region_travel_journey().plan_path) if player else str(region_registry().parties[token].plan_path)
		var outcome := {"ok": true, "party": party, "arrived": true}
		var validated := _region_revalidate_completed_land_outcome(token, outcome, planned.plan, path)
		if not validated.ok: return validated
		party = validated.outcome.party
		if player:
			_travel_party_runtime = party
			_travel_party_runtime_token = token
		else:
			_region_npc_party_runtime[token] = party
			region_registry().parties[token].position = {"site": validated.outcome.position.site.duplicate(), "component": int(validated.outcome.position.component)} if validated.outcome.has("position") else region_registry().parties[token].position
		if not bool(validated.get("blocked", false)) and not party.upkeep.has("route_blocked"): continue
		blocked = true
		var changed := party.duplicate(true)
		changed.upkeep.route_entry_attempt = int(changed.upkeep.get("route_entry_attempt", 0)) + 1
		var captured := _region_publish_land_candidate(token, changed, Marshalls.raw_to_base64(var_to_bytes(party)).sha256_text())
		if not captured.ok: return captured
		if player: _travel_party_runtime = captured.party
		else: _region_npc_party_runtime[token] = captured.party
		var completed_owner := region_original_party_runtime_proof(token, captured.party)
		if not completed_owner.ok: return completed_owner
		var receipt: Dictionary = runtime.lab.region_bind_receipt(runtime.lab.terrain).duplicate(true)
		receipt.merge({"complete": true, "effects_complete": true, "no_effect": true, "navigation_blocked": true,
			"event_id": str(event.id), "event_at": float(event.at), "event_sequence": int(event.sequence),
			"owner": "travel:" + token, "generation": int(_marker.generation), "game_seconds": float(control.logical_game_seconds),
			"action_seconds": float(control.fire_clock.action_seconds), "source_epoch": completed_owner.proof.duplicate(true),
			"source_node": captured.party.upkeep.route_node.duplicate(true)}, true)
		receipts.append(receipt)
	return {"ok": true, "handled": blocked, "receipt": {"complete": blocked, "effects_complete": blocked,
		"no_effect": blocked, "navigation_blocked": blocked, "owners": receipts}}


func _region_arrival_attempt_id(token: String, party: Dictionary, player: bool, path: String = "") -> String:
	var original := "travel:%s:arrival:%s" % [token, path] if player else "npc:%s:arrival" % token
	var attempt := int(party.get("upkeep", {}).get("route_entry_attempt", 0))
	return original if attempt == 0 else original + ":retry:%d" % attempt

## The original route owns this derived node/pose reference. It never creates
## another body, relocates a person row, or rewrites an original vehicle pose.


func _region_retry_blocked_npc_land_entries() -> Dictionary:
	var tokens: Array = region_registry().parties.keys()
	tokens.sort()
	for token: String in tokens:
		var reference: Dictionary = region_registry().parties[token]
		if str(reference.get("controller", "")) != "npc" or str(reference.get("phase", "")) != "travelling": continue
		var loaded := _region_npc_party(token)
		if not loaded.ok: return loaded
		var party: Dictionary = loaded.party
		if str(party.get("mode", "land")) != "land" or not party.get("upkeep", {}).has("route_blocked"): continue
		var planned := _region_npc_plan(token)
		if not planned.ok: return planned
		var resumed := _region_land_route_preview(party, planned.plan, str(reference.plan_path), float(control.logical_game_seconds))
		if not resumed.ok: return resumed
		if not bool(resumed.get("entry_ready", false)): continue
		if not region_original_party_progress.is_valid(): return fail("MISSING_REGION_PARTY_PROGRESS")
		var host: Object = region_original_party_progress.get_object()
		if not host is TerrainLab or host.site_controller == null or host.site_controller.region_slot != self: return fail("INVALID_REGION_PARTY_PROGRESS")
		var original: Dictionary = host.prepare_region_party_original_owner(token, party, self)
		if not original.ok: return original
		var runtime := region_original_party_runtime_proof(token, party)
		if not runtime.ok: return runtime
		if var_to_bytes(resumed.party.content) != var_to_bytes(party.content): return fail("ROUTE_BODY_CHANGED")
		var captured := _region_publish_land_candidate(token, resumed.party, Marshalls.raw_to_base64(var_to_bytes(party)).sha256_text())
		if not captured.ok: return captured
		_region_npc_party_runtime[token] = captured.party
		reference.position = {"site": resumed.position.site.duplicate(), "component": int(resumed.position.component)}
		# A blocked attempt's contact completed as a navigation no-effect at its own
		# point. This retry is a new paid attempt at the same entry, so its own
		# contact (if the static body still holds the channel) is a new event, and it
		# is queued before the arrival so the same-point contact is consumed first.
		var static_contact := _region_queue_npc_siege_contact(token, float(control.logical_game_seconds))
		if not static_contact.ok: return static_contact
		var owner := Grid.site_id(str(pin.atlas_id), Vector2i(int(resumed.position.site[0]), int(resumed.position.site[1])))
		var player_present := owner == str(control.active_site_id)
		var queued := queue_region_event(_region_arrival_attempt_id(token, captured.party, false), "player_arrival" if player_present else "arrival",
			float(control.logical_game_seconds), owner, {"token": token, "site": resumed.position.site.duplicate(), "component": int(resumed.position.component)}, player_present)
		if not queued.ok: return queued
	return {"ok": true}


## A restored entry at the final node is a zero-time P0 admission. Capture the
## SAME actual original body through its existing capture hook, then let the
## existing queued-arrival consumer own the Site handoff. No extra world step.


func _region_retry_blocked_land_entry() -> Dictionary:
	if not region_player_barrier().is_empty(): return {"ok": true}
	var loaded := region_travel_party()
	if not loaded.ok: return loaded
	var party: Dictionary = loaded.party
	if str(party.get("mode", "land")) != "land" or not party.get("upkeep", {}).has("route_blocked"): return {"ok": true}
	var planned := region_travel_plan()
	if not planned.ok: return planned
	var journey := region_travel_journey()
	var resumed := _region_land_route_preview(party, planned.plan, str(journey.plan_path), float(control.logical_game_seconds))
	if not resumed.ok: return resumed
	if not bool(resumed.get("entry_ready", false)): return {"ok": true}
	if not region_original_party_progress.is_valid(): return fail("MISSING_REGION_PARTY_PROGRESS")
	var host: Object = region_original_party_progress.get_object()
	if not host is TerrainLab or host.site_controller == null or host.site_controller.region_slot != self: return fail("INVALID_REGION_PARTY_PROGRESS")
	if var_to_bytes(resumed.party.content) != var_to_bytes(party.content): return fail("ROUTE_BODY_CHANGED")
	var original: Dictionary = host.prepare_region_party_original_owner(str(journey.token), party, self)
	if not original.ok: return original
	var captured := _region_publish_land_candidate(str(journey.token), resumed.party, Marshalls.raw_to_base64(var_to_bytes(party)).sha256_text())
	if not captured.ok: return captured
	_travel_party_runtime = captured.party
	_travel_party_runtime_token = str(journey.token)
	var interval := {"game_end": float(control.logical_game_seconds)}
	var queued := _region_queue_player_travel_outcome(str(journey.token), resumed, interval)
	if not queued.ok: return queued
	return consume_due_region_events()


func prepare_region_party_map_resume(original: TerrainLab) -> Dictionary:
	if original == null or not str(control.active_site_id).is_empty() or not _prepared.is_empty():
		return fail("INVALID_TRAVEL_HOST")
	var selected := region_travel_party()
	if not selected.ok: return selected
	var party: Dictionary = selected.party
	var token := str(party.party_id)
	if str(party.get("controller", "")) != "player" or str(party.get("mode", "")) != "land" \
			or party.upkeep.get("live", {}).is_empty(): return fail("NO_TARGET")
	var source := region_original_party_runtime_proof(token, party)
	if not source.ok or source.get("lab") != original: return source if not source.ok else fail("INVALID_TRAVEL_HOST")
	var guarded: Dictionary = original.region_party_map_resume_guard(party)
	if not guarded.ok: return guarded
	var leader: Dictionary = party.upkeep.live.frame.people.get(str(int(party.leader_person_id)), {})
	if not RegionTravel._frame_pair(leader.get("world_cell")): return fail("MISSING_ORIGINAL_POSITION")
	var world := Vector2i(int(leader.world_cell[0]), int(leader.world_cell[1]))
	var site := Vector2i(Grid.floor_div(world.x, 100), -Grid.floor_div(world.y, 100))
	var local := world - Vector2i(site.x * 100, -site.y * 100)
	var prepared := prepare_region_route_context(null, party)
	if not prepared.ok: return prepared
	var navigation := RegionRoute.effective_terrain(self.source, site, prepared.context)
	if not navigation.ok: return navigation
	var cover: Dictionary = self.source.site_resource_cover(site)
	var derived := RegionRoute.table_from_terrain(navigation.data, cover.get("cover", PackedByteArray()), true)
	if not derived.ok: return derived
	var component := RegionRoute.component_of(derived, local)
	if component < 0: return fail("WALL_EDGE")
	var poses := {}
	for identity: String in party.content.get("vehicles", {}):
		var vehicle: Dictionary = party.content.vehicles[identity]
		if str(vehicle.kind) not in ["cart", "wagon"] or not vehicle.get("move", {}).is_empty():
			return fail("ORIGINAL_VEHICLE_MOTION_REQUIRED")
		var at: Dictionary = party.upkeep.live.frame.vehicles.get(identity, {})
		var operator: Dictionary = party.upkeep.live.frame.people.get(str(int(vehicle.operator_id)), {})
		if not RegionTravel._frame_pair(at.get("world_cell")) or not RegionTravel._frame_pair(operator.get("world_cell")):
			return fail("MISSING_ORIGINAL_POSITION")
		var base := Vector2i(site.x * 100, -site.y * 100)
		var anchor := Vector2i(int(at.world_cell[0]), int(at.world_cell[1])) - base
		var person := Vector2i(int(operator.world_cell[0]), int(operator.world_cell[1])) - base
		if not navigation.data.contains(anchor) or not navigation.data.contains(person):
			return fail("STRADDLED_ORIGINAL_VEHICLE", "原載體仍跨界；保留同一原實體與已付點，不能改到中心")
		poses[identity] = {"anchor": [anchor.x, anchor.y], "operator": [person.x, person.y], "facing": vehicle.facing.duplicate()}
	return {"ok": true, "token": token, "original": original, "source_party": party,
		"source_proof": source.proof.duplicate(true), "source_graph": source.original_live_graph,
		"native_references": guarded.native_references, "bind_token": guarded.bind_token,
		"game_seconds": float(control.logical_game_seconds), "action_seconds": float(control.fire_clock.action_seconds),
		"journey": region_travel_journey().duplicate(true), "site": site, "cell": local, "component": component,
		"vehicle_poses": poses, "world_cell": world, "already_map": str(party.upkeep.live.get("upkeep", "")) == "mapBody"}


func resume_region_party_map(original: TerrainLab, prepared: Dictionary = {}) -> Dictionary:
	if prepared.is_empty(): prepared = prepare_region_party_map_resume(original)
	if not prepared.get("ok", false): return prepared
	var current := prepare_region_party_map_resume(original)
	if not current.ok: return current
	if prepared.get("original") != original or prepared.get("source_proof") != current.source_proof \
			or prepared.get("bind_token") != current.bind_token or not is_same(prepared.get("source_party"), current.source_party) \
			or prepared.get("game_seconds") != current.game_seconds or prepared.get("action_seconds") != current.action_seconds:
		return fail("STALE_REGION_MAP_RESUME")
	if current.already_map: return {"ok": true, "token": current.token, "complete": true, "same_original_body": true, "idempotent": true}
	var prior: Dictionary = current.source_party
	var candidate: Dictionary = prior.duplicate(true)
	candidate.upkeep.live.upkeep = "mapBody"
	candidate.upkeep.map_resume = {"version": 1, "game_seconds": current.game_seconds, "action_seconds": current.action_seconds,
		"source_generation": int(current.source_proof.generation), "source_revision": int(current.source_proof.revision),
		"accepted_world_cell": [current.world_cell.x, current.world_cell.y], "source_party_sha256": str(current.source_proof.sha256)}
	# Retain the historical paid distance/cursor. A new plan gets its own distance
	# domain through the existing set_region_travel_plan consumer.
	candidate.upkeep.route_node = {"version": 1, "plan_id": "", "index": 0, "site": [current.site.x, current.site.y],
		"component": current.component, "cell": [current.cell.x, current.cell.y], "vehicle_poses": current.vehicle_poses.duplicate(true)}
	candidate.upkeep.erase("route_blocked")
	var journey: Dictionary = current.journey.duplicate(true)
	journey.position = {"site": [current.site.x, current.site.y], "component": current.component}
	journey.plan_path = ""; journey.plan_sha256 = ""
	var old_hash := original._region_party_input_hash
	var old_meta: Dictionary = original.terrain.get_meta(&"region_party_owner").duplicate(true)
	_travel_party_runtime = candidate; _travel_party_runtime_token = current.token
	original._region_party_input_hash = TerrainLab._region_party_hash(candidate)
	var owner: Dictionary = old_meta.duplicate(true)
	owner.party_hash = original._region_party_input_hash
	original.terrain.set_meta(&"region_party_owner", owner)
	var generation := int(_marker.generation)
	var saved := checkpoint_region_travel(journey)
	if not saved.ok:
		if int(_marker.generation) == generation:
			_travel_party_runtime = prior
			original._region_party_input_hash = old_hash; original.terrain.set_meta(&"region_party_owner", old_meta)
		return saved
	var proof := region_original_party_runtime_proof(current.token, _travel_party_runtime)
	if not proof.ok: return fail("COMMITTED_UNBOUND", "已提交同一原 graph；依共同 marker 重開，不重付已接受点")
	return {"ok": true, "token": current.token, "complete": true, "same_original_body": true,
		"generation": int(_marker.generation), "site": current.site, "body_hash": original._region_party_input_hash}


## Returning the input to the original visible action mode retains the same
## party/native aliases and every accepted point. It creates no P0 event.


func return_original_mode(original: TerrainLab) -> Dictionary:
	var current := prepare_region_party_map_resume(original)
	if not current.ok: return current
	if not current.already_map: return {"ok": true, "complete": true, "same_original_body": true, "idempotent": true}
	var prior: Dictionary = current.source_party
	var candidate: Dictionary = prior.duplicate(true)
	candidate.upkeep.live.upkeep = "liveBody"
	var old_hash := original._region_party_input_hash
	var old_meta: Dictionary = original.terrain.get_meta(&"region_party_owner").duplicate(true)
	var generation := int(_marker.generation)
	_travel_party_runtime = candidate
	original._region_party_input_hash = TerrainLab._region_party_hash(candidate)
	var owner: Dictionary = old_meta.duplicate(true); owner.party_hash = original._region_party_input_hash
	original.terrain.set_meta(&"region_party_owner", owner)
	var saved := checkpoint_region_travel()
	if not saved.ok:
		if int(_marker.generation) == generation:
			_travel_party_runtime = prior; original._region_party_input_hash = old_hash
			original.terrain.set_meta(&"region_party_owner", old_meta)
		return saved
	original._region_map_motion_proposal = {}
	return {"ok": true, "complete": true, "token": current.token, "same_original_body": true, "generation": int(_marker.generation)}


## The retained plan supplies the true entry/exit. The initial accepted native
## position supplies the start; the map never moves the body back to a center.


func _region_stop_original_map_party(party: Dictionary) -> Dictionary:
	var source := region_original_party_runtime_proof(str(party.party_id), party)
	if not source.ok: return source
	var current := prepare_region_party_map_resume(source.lab)
	if not current.ok: return current
	var candidate: Dictionary = party.duplicate(true)
	var node: Dictionary = _region_map_route_reference(party)
	if node.is_empty(): return fail("MISSING_ORIGINAL_POSITION")
	node.merge({"version": 1, "plan_id": "", "index": 0, "component": int(current.component)})
	candidate.upkeep.route_node = node
	candidate.upkeep.erase("route_blocked")
	candidate.upkeep.erase("pending_route_entry")
	var journey: Dictionary = current.journey.duplicate(true)
	journey.position = {"site": node.site.duplicate(), "component": int(current.component)}
	journey.plan_path = ""; journey.plan_sha256 = ""
	var original: TerrainLab = source.lab
	var old_hash := original._region_party_input_hash
	var old_meta: Dictionary = original.terrain.get_meta(&"region_party_owner").duplicate(true)
	var generation := int(_marker.generation)
	_travel_party_runtime = candidate
	original._region_party_input_hash = TerrainLab._region_party_hash(candidate)
	var owner: Dictionary = old_meta.duplicate(true); owner.party_hash = original._region_party_input_hash
	original.terrain.set_meta(&"region_party_owner", owner)
	var saved := checkpoint_region_travel(journey)
	if not saved.ok:
		if int(_marker.generation) == generation:
			_travel_party_runtime = party; original._region_party_input_hash = old_hash
			original.terrain.set_meta(&"region_party_owner", old_meta)
		return saved
	original._region_map_motion_proposal = {}
	return {"ok": true, "complete": true, "same_original_body": true, "token": str(party.party_id)}


const OFFICER_FEATURE_INTEL_GAME_SECONDS := 3600.0

const DeliverySight = preload("res://scripts/terrain_lab/site_army_ai.gd")


func record_region_officer_feature_observation(original: TerrainLab, observer_id: int, feature_id: String) -> Dictionary:
	if not is_instance_valid(original) or original.site_controller == null or original.site_controller.region_slot != self \
		or _region_bound_original_lab(original.terrain) != original: return fail("MISSING_ORIGINAL_OBSERVER")
	var bind := original.region_bind_receipt(original.terrain)
	var settled := validate_settlement(original.terrain.site, float(control.logical_game_seconds))
	var fire: Dictionary = original.terrain.site.get("fire_settlement", {})
	if not bind.get("complete", false) or int(bind.get("generation", -1)) != int(_marker.generation) \
		or not settled.ok or settled.legacy or float(settled.pending) > 0.00000001 \
		or not validate_fire_settlement(original.terrain.site, control.fire_clock).ok \
		or int(fire.get("sequence", -1)) != int(control.fire_clock.sequence) \
		or float(fire.get("action_seconds", -1.0)) != float(control.fire_clock.action_seconds): return fail("STALE_ORIGINAL_OBSERVER")
	var reference := RegionAI.person_ref(original.terrain.site, observer_id)
	var person := _region_delivery_person(original, reference)
	if person.is_empty() or not SiteSettlement._fit(person) or _region_delivery_office(original, observer_id).is_empty(): return fail("NO_OBSERVER_OFFICE")
	var feature: Dictionary = original.terrain.site.get("features", {}).get(feature_id, {})
	if feature.is_empty() or not feature.get("cells") is Array: return fail("NO_VISIBLE_FEATURE")
	var visible := TerrainArmy.INVALID_CELL
	var observers: Array = [{"cell": person.cell}]
	for index: Variant in feature.cells:
		var cell := original.terrain.cell_from_index(int(index))
		if DeliverySight._observed_cell(original, observers, cell, DeliverySight.THREAT_DISTANCE):
			visible = cell
			break
	if visible == TerrainArmy.INVALID_CELL: return fail("NO_VISIBLE_FEATURE")
	var scope := str(original.terrain.site.id)
	var now := float(control.logical_game_seconds)
	var value := {"kind": str(feature.get("kind", "")), "owner_faction": int(feature.get("owner_faction", 0)), "cell": [visible.x, visible.y]}
	var object := "feature:" + feature_id
	var key := scope + "/" + object
	var known := RegionAI.view(region_registry(), observer_id, now, scope, reference)
	var prior: Dictionary = known.get(key, {})
	if prior.get("observation_kind") == "officer_visible_feature" and prior.get("source") == "site_observation" \
		and prior.get("observer_ref") == reference and prior.get("value") == value:
		# The same last-known fact retains its original age and expiry. There
		# is no every-evaluation timestamp refresh or unbounded duplicate stream.
		return {"ok": true, "duplicate": true, "receipt": prior.duplicate(true)}
	var receipt := {"id": "officer-feature:%s:%s:%s:%.6f" % [scope, RegionTravel.stable_key(reference), feature_id, now],
		"source": "site_observation", "observation_kind": "officer_visible_feature", "observer": observer_id, "receiver": observer_id,
		"observer_scope": scope, "receiver_scope": scope, "object_scope": scope,
		"observer_ref": reference.duplicate(true), "receiver_ref": reference.duplicate(true), "object": object, "value": value,
		"game_time": now, "expires_at": now + OFFICER_FEATURE_INTEL_GAME_SECONDS, "confidence": 1.0}
	var recorded := RegionAI.observe(region_registry(), receipt)
	if not recorded.ok: return recorded
	return {"ok": true, "receipt": receipt.duplicate(true)}

## The existing Region evaluation caller supplies a fully settled local owner.
## Only its current officers perceive their own visible structures. Nothing
## is shared to another same-faction person without a physical carried report.


func record_region_officer_feature_observations(original: TerrainLab) -> Dictionary:
	var officers: Array[int] = []
	for team: Variant in original.team_owners():
		if team.combat_enabled and team.current_commander >= 0:
			var identity: int = team.combat_identity(team.current_commander)
			if identity > 0 and not officers.has(identity): officers.append(identity)
	for nation: Dictionary in original.terrain.site.get("equipment_nations", {}).values():
		if not SiteOffices.validate(nation.get("offices", {}), "nation"): continue
		for position: Dictionary in nation.offices.positions:
			var holder := int(position.holder)
			if holder > 0 and not officers.has(holder): officers.append(holder)
	var count := 0
	for officer: int in officers:
		for feature_id: String in original.terrain.site.get("features", {}):
			var observed := record_region_officer_feature_observation(original, officer, feature_id)
			if not observed.ok:
				if str(observed.get("code", "")) in ["NO_OBSERVER_OFFICE", "NO_VISIBLE_FEATURE"]: continue
				return observed
			if not observed.get("duplicate", false): count += 1
	return {"ok": true, "observed": count}

## One original NPC dispatch carries the immutable report/standing command.
## This prepares the same original dispatch candidate; its single marker owns
## departure, party document and reports ledger together.


## Original route duration of a courier party (game seconds): a stored player
## plan keeps cumulative seconds; an NPC land plan keeps steps/metres and uses the
## same party speed rule as set_region_travel_plan.
func _region_courier_plan_seconds(plan: Dictionary, party: Dictionary) -> Dictionary:
	if plan.get("seconds") is Array and not plan.seconds.is_empty(): return {"ok": true, "seconds": float(plan.seconds.back())}
	if str(plan.get("mode", "land")) != "land": return fail("UNSUPPORTED_DELIVERY_ROUTE", "原海路信使的到達時間由航段 timeline 決定")
	var transport := RegionTravel.prepare_transport(party)
	if not transport.ok: return transport
	var speed := RegionTravel.party_speed(party.content) * float(transport.get("carry_factor", 1.0))
	if not is_finite(speed) or speed <= 0.0: return fail("INVALID", "原信使速度")
	var total := 0.0
	for step: Dictionary in plan.get("steps", []):
		if not _seconds(step.get("metres")): return fail("INVALID", "路線距離")
		total += float(step.metres) / (speed * maxf(0.000001, float(step.get("travel_factor", 1.0))))
	return {"ok": true, "seconds": total}

func prepare_region_carried_report(dispatch: Dictionary, source_receipt_id: String,
		receiver_scope: String, receiver_id: int, command: Dictionary = {}, courier_id: int = 0) -> Dictionary:
	if not dispatch.get("ok", false) or dispatch.get("duplicate", false) or not dispatch.get("lab") is TerrainLab \
		or int(dispatch.get("generation", -1)) != int(_marker.generation) or int(dispatch.get("runtime_revision", -1)) != int(region_registry().revision) \
		or float(dispatch.get("world", -1.0)) != float(control.logical_game_seconds): return fail("STALE_REGION_PERMIT")
	var source_lab: TerrainLab = dispatch.lab
	if source_lab.site_controller.region_slot != self or _region_bound_original_lab(source_lab.terrain) != source_lab: return fail("STALE_DELIVERY_SOURCE")
	var source_receipt: Dictionary = region_registry().get("observations", {}).get(source_receipt_id, {})
	var commander := int(dispatch.request.decider)
	var source_scope := str(source_lab.terrain.site.id)
	var issuer_ref := RegionAI.person_ref(source_lab.terrain.site, commander)
	if source_receipt.is_empty() or issuer_ref.is_empty() or not RegionAI.receiver_matches(source_receipt, commander, source_scope, issuer_ref) \
		or maxf(float(source_receipt.get("game_time", INF)), float(source_receipt.get("received_at", -INF))) > float(control.logical_game_seconds) \
		or float(source_receipt.get("expires_at", -INF)) < float(control.logical_game_seconds): return fail("UNKNOWN_REPORT_SOURCE")
	if not RegionAI.valid_person_ref(source_receipt.get("observer_ref")): return fail("UNTYPED_REPORT_SOURCE")
	if not region_owner_lab.is_valid(): return fail("MISSING_REGION_ADAPTER")
	var current_mode := "live" if receiver_scope == str(control.active_site_id) else str(region_registry().modes.get(receiver_scope, {}).get("mode", "cold_exact"))
	var receiver_owner: Dictionary = region_owner_lab.call(receiver_scope, current_mode)
	if not receiver_owner.get("ok", false) or not receiver_owner.get("lab") is TerrainLab: return receiver_owner
	var receiver_lab: TerrainLab = receiver_owner.lab
	var receiver_ref := RegionAI.person_ref(receiver_lab.terrain.site, receiver_id)
	var receiver_person := _region_delivery_person(receiver_lab, receiver_ref)
	var issuer := _region_delivery_person(source_lab, issuer_ref)
	var courier := int(dispatch.request.commander) if courier_id <= 0 else courier_id
	var courier_ref: Dictionary = dispatch.party.content.travel_identity.refs.person.get(str(courier), {})
	var team_ref: Dictionary = dispatch.party.content.travel_identity.refs.team.get(str(int(dispatch.request.team_id)), {})
	if issuer.is_empty() or receiver_person.is_empty() or not SiteSettlement._fit(issuer) or float(receiver_person.hp) <= 0.0 \
		or int(receiver_person.faction) != int(issuer.faction) or receiver_ref.is_empty() \
		or not RegionAI.delivery_reference(courier_ref, "person") or not RegionAI.delivery_reference(team_ref, "team"): return fail("INVALID_DELIVERY_PERSON")
	var office := _region_delivery_office(receiver_lab, receiver_id)
	if office.is_empty(): return fail("NO_RECEIVER_OFFICE")
	var destination: Array = dispatch.plan.steps.back().site
	if receiver_scope != Grid.site_id(str(pin.atlas_id), Vector2i(int(destination[0]), int(destination[1]))): return fail("WRONG_DELIVERY_ROUTE")
	var id := "carried:%s:%s:%s" % [str(dispatch.token), source_receipt_id, "command" if not command.is_empty() else "report"]
	var receipt: Dictionary = source_receipt.duplicate(true)
	receipt.id = id
	receipt.source = "report"
	receipt.receiver = receiver_id
	receipt.receiver_scope = receiver_scope
	receipt.receiver_ref = receiver_ref.duplicate(true)
	receipt.erase("received_at")
	var duration := _region_courier_plan_seconds(dispatch.plan, dispatch.party)
	if not duration.ok: return duration
	var forecast := float(control.logical_game_seconds) + float(duration.seconds)
	var delivery := {"version": RegionAI.DELIVERY_VERSION, "kind": "report", "phase": "in_transit", "source_scope": source_scope,
		"source_game_seconds": float(control.logical_game_seconds), "source_action_seconds": float(control.fire_clock.action_seconds),
		"source_receipt_sha256": RegionAI.delivery_hash(source_receipt), "issuer_ref": issuer_ref.duplicate(true), "team_ref": team_ref.duplicate(true),
		"courier_token": str(dispatch.token), "courier_ref": courier_ref.duplicate(true), "receiver_scope": receiver_scope,
		"receiver_ref": receiver_ref.duplicate(true), "receiver_office": office.duplicate(true), "plan_path": "travel/%s/plan_000001.json" % str(dispatch.token)}
	if not command.is_empty():
		return fail("WRONG_STANDING_COMMAND_RECEIVER", "跨 Site 隊長原 standing command 沿 prepare_region_carried_command，收件者是同一原到站隊長")
	var report := {"id": id, "due": forecast, "receipt": receipt, "source_receipt": source_receipt.duplicate(true), "delivery": delivery}
	var checked := RegionAI.validate_carried_report(report)
	if not checked.ok: return checked
	var preview := RegionAI.queue_report({"observations": {}, "reports": [], "evaluation": {}}, report)
	if not preview.ok: return preview
	if not dispatch.has("carried_reports"): dispatch.carried_reports = []
	dispatch.carried_reports.append(report)
	return {"ok": true, "dispatch": dispatch, "report": report.duplicate(true)}

## A standing command belongs to the SAME original captain/team during their
## real travel. Its target is the actual destination entry, not a guessed enemy.
## It reaches the receiving scope only through that original arrival marker.


func prepare_region_carried_command(dispatch: Dictionary, source_receipt_id: String,
		order: int = TerrainArmy.CombatOrder.HOLD, goal: Vector2i = TerrainArmy.INVALID_CELL) -> Dictionary:
	if not dispatch.get("ok", false) or not dispatch.get("lab") is TerrainLab or order not in [TerrainArmy.CombatOrder.HOLD, TerrainArmy.CombatOrder.MOVE]: return fail("INVALID_CARRIED_COMMAND")
	var source_lab: TerrainLab = dispatch.lab
	var commander := int(dispatch.request.commander)
	var source_scope := str(source_lab.terrain.site.id)
	var original: Dictionary = region_registry().get("observations", {}).get(source_receipt_id, {})
	var issuer_ref: Dictionary = dispatch.party.content.travel_identity.refs.person.get(str(commander), {})
	var team_ref: Dictionary = dispatch.party.content.travel_identity.refs.team.get(str(int(dispatch.request.team_id)), {})
	if int(dispatch.get("generation", -1)) != int(_marker.generation) or int(dispatch.get("runtime_revision", -1)) != int(region_registry().revision) \
		or source_lab.site_controller.region_slot != self or _region_bound_original_lab(source_lab.terrain) != source_lab \
		or not RegionAI.delivery_reference(issuer_ref, "person") or not RegionAI.delivery_reference(team_ref, "team") \
		or str(dispatch.request.get("known_receipt", "")) != source_receipt_id or not RegionAI.valid_person_ref(original.get("observer_ref")): return fail("UNKNOWN_COMMAND_SOURCE")
	var decider := int(dispatch.request.decider)
	var decision_ref := RegionAI.person_ref(source_lab.terrain.site, decider)
	if not RegionAI.receiver_matches(original, decider, source_scope, decision_ref) \
		or not RegionAI.view(region_registry(), decider, float(control.logical_game_seconds), source_scope, decision_ref).has(RegionAI.observation_object_key(original)): return fail("UNKNOWN_COMMAND_SOURCE")
	var team: TerrainArmy = _region_delivery_team(source_lab, team_ref)
	if team == null or team.combat_identity(team.current_commander) != commander or not team.command_eligible(team.current_commander): return fail("NO_COMMANDER")
	var last: Dictionary = dispatch.plan.steps.back()
	var destination := Grid.site_id(str(pin.atlas_id), Vector2i(int(last.site[0]), int(last.site[1])))
	var entry := RegionRoute.entry_cell(last)
	if order == TerrainArmy.CombatOrder.MOVE and goal != entry: return fail("UNKNOWN_COMMAND_GOAL", "首版原 standing MOVE 只到此真 route 入界格")
	var id := "carried:%s:%s:command" % [str(dispatch.token), source_receipt_id]
	var receipt := original.duplicate(true)
	receipt.id = id
	receipt.source = "report"
	receipt.receiver = commander
	receipt.receiver_scope = destination
	receipt.receiver_ref = issuer_ref.duplicate(true)
	receipt.erase("received_at")
	var duration := _region_courier_plan_seconds(dispatch.plan, dispatch.party)
	if not duration.ok: return duration
	var forecast := float(control.logical_game_seconds) + float(duration.seconds)
	var delivery := {"version": RegionAI.DELIVERY_VERSION, "kind": "army_command", "phase": "in_transit", "source_scope": source_scope,
		"source_game_seconds": float(control.logical_game_seconds), "source_action_seconds": float(control.fire_clock.action_seconds),
		"source_receipt_sha256": RegionAI.delivery_hash(original), "issuer_ref": issuer_ref.duplicate(true), "team_ref": team_ref.duplicate(true),
		"courier_token": str(dispatch.token), "courier_ref": issuer_ref.duplicate(true), "receiver_scope": destination,
		"receiver_ref": issuer_ref.duplicate(true), "receiver_office": {"kind": "team", "team_ref": team_ref.duplicate(true), "holder_ref": issuer_ref.duplicate(true)},
		"plan_path": "travel/%s/plan_000001.json" % str(dispatch.token),
		"command": {"version": RegionAI.DELIVERY_VERSION, "order": order, "goal": [goal.x, goal.y], "commander_ref": issuer_ref.duplicate(true), "source_order_serial": int(team.get_order_serial())}}
	var report := {"id": id, "due": forecast, "receipt": receipt, "source_receipt": original.duplicate(true), "delivery": delivery}
	var valid := RegionAI.validate_carried_report(report)
	if not valid.ok: return valid
	if not dispatch.has("carried_reports"): dispatch.carried_reports = []
	dispatch.carried_reports.append(report)
	return {"ok": true, "dispatch": dispatch, "report": report.duplicate(true)}


func _region_delivery_team(original: TerrainLab, reference: Dictionary) -> TerrainArmy:
	for team: TerrainArmy in original.combat_armies:
		if original.terrain.site.get("travel_identity", {}).get("refs", {}).get("team", {}).get(str(team.team_id), {}) == reference: return team
	return null


## ORDSERIAL: the receiving team of a Region nation command. Under an active crowd it is that crowd's command owner
## (RegionAI.command_team_owners: one CrowdPersonOwner per native formation with an army record); the disabled
## TerrainArmy slot of a crowd team never stands in for it. Otherwise the original TerrainArmy (_region_delivery_team).
## _region_delivery_team itself stays the grid team of the army command paths (prepare_region_carried_command and its receive).
func _region_nation_team(original: TerrainLab, reference: Dictionary) -> Variant:
	if original.crowd_site == null or not original.crowd_site.active: return _region_delivery_team(original, reference)
	var refs: Dictionary = original.terrain.site.get("travel_identity", {}).get("refs", {}).get("team", {})
	for team: Variant in RegionAI.command_team_owners(original):
		if refs.get(str(int(team.team_id)), {}) == reference: return team
	return null


## ORDSERIAL: the original order preparation still to pay: TerrainArmy._order_delay, or the native formation's
## order_delay for a crowd team (the same D77 rule; a crowd HOLD starts it in World::host_order).
static func _region_team_order_delay(team: Variant) -> float:
	if team is CrowdPersonOwner: return float(team.crowd_site.formation_state(int(team.formation_index)).get("order_delay", 0.0))
	return float(team._order_delay)


## ORDSERIAL: the captain's own public HOLD. A crowd team takes it through crowd_site.issue_order with source "ui":
## the formation leaves its tactical AI like TerrainArmy.issue_combat_order pauses the policy, and the accepted
## order adds one to the native order serial.
static func _region_team_hold(team: Variant) -> Dictionary:
	if team is CrowdPersonOwner: return team.crowd_site.issue_order(int(team.team_id), TerrainArmy.CombatOrder.HOLD, Vector2i(-1, -1), -1, "ui")
	return team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.HOLD)


## ORDSERIAL: the captain restores the tactical policy it had before the command (crowd: the formation's AI owner).
static func _region_team_restore_policy(team: Variant) -> Dictionary:
	if team is CrowdPersonOwner: return team.crowd_site.set_team_ai(int(team.team_id), true)
	return team.set_tactical_ai_enabled(team.current_commander, true)


func _region_delivery_person(original: TerrainLab, reference: Dictionary) -> Dictionary:
	for key: String in original.terrain.site.get("travel_identity", {}).get("refs", {}).get("person", {}):
		if RegionAI.person_ref(original.terrain.site, int(key)) != reference: continue
		var person: Dictionary = original.site_controller.person_actions._person(int(key), false)
		if person.is_empty(): continue
		if person.owner is TerrainArmy:
			if bool(person.owner.combat_hot_get(int(person.unit), &"departed", false)) or bool(person.owner.combat_hot_get(int(person.unit), &"site_exited", false)): continue
		elif person.owner is CrowdPersonOwner:
			# G6: a crowd person is present while it is a native member that has not left the map (departed or off-map absent).
			if person.owner.member_gone(int(person.unit)) or bool(person.owner.combat_hot_get(int(person.unit), &"site_exited", false)): continue
		elif not original.actor_present(person.owner) or bool(person.owner.site_exited): continue
		return person
	return {}


func _region_delivery_office(original: TerrainLab, person: int) -> Dictionary:
	# G6: team_owners() is the crowd command owners while a crowd is active, else the original TerrainArmy slots.
	for team: Variant in original.team_owners():
		if not team.combat_enabled or team.current_commander < 0 or team.combat_identity(team.current_commander) != person: continue
		var reference: Dictionary = original.terrain.site.get("travel_identity", {}).get("refs", {}).get("team", {}).get(str(team.team_id), {})
		if not RegionAI.delivery_reference(reference, "team"): return {}
		return {"kind": "team", "team_ref": reference.duplicate(true), "holder_ref": RegionAI.person_ref(original.terrain.site, person)}
	for nation_id: String in original.terrain.site.get("equipment_nations", {}):
		var nation: Dictionary = original.terrain.site.equipment_nations[nation_id]
		var office := SiteOffices.position_of(nation.get("offices", {}), person)
		if office.is_empty(): continue
		var reference: Dictionary = original.terrain.site.get("travel_identity", {}).get("refs", {}).get("nation", {}).get(nation_id, {})
		if not RegionAI.delivery_reference(reference, "nation"): return {}
		return {"kind": "nation", "nation_ref": reference.duplicate(true), "position": str(office.id), "holder_ref": RegionAI.person_ref(original.terrain.site, person)}
	return {}

## Called while the ORIGINAL arrival candidate still owns next_control. The
## original nominal due/observation time remain immutable; ready_at is the true
## accepted physical boundary. Queue and mapping share the same single marker.


func _region_accept_carried_arrival(next_clock: Dictionary, token: String, destination: String, mapping: Dictionary) -> Dictionary:
	var registry: Dictionary = next_clock.region_gameplay
	for report: Dictionary in registry.get("reports", []):
		if not report.has("delivery") or str(report.delivery.get("courier_token", "")) != token or RegionAI.carried_report_terminal(report): continue
		var valid := RegionAI.validate_carried_report(report)
		if not valid.ok: return valid
		if destination != str(report.delivery.receiver_scope):
			var rejected := RegionAI.carried_report_result(report, float(next_clock.logical_game_seconds), float(next_clock.fire_clock.action_seconds), {"code": "WRONG_DELIVERY_DESTINATION", "effects_complete": true, "complete": true})
			if not rejected.ok: return rejected
			continue
		report.delivery.phase = "ready"
		report.delivery.ready_at = float(next_clock.logical_game_seconds)
		report.delivery.result_at = float(next_clock.logical_game_seconds)
		report.delivery.arrival_mapping_sha256 = RegionAI.delivery_hash(mapping)
		var queued := GameplayClock.queue_event(registry, "report:" + str(report.id) + ":received", "intel", float(next_clock.logical_game_seconds), destination, {"report_id": str(report.id), "carried": true})
		if not queued.ok: return queued
	return {"ok": true}


func _region_consume_carried_report(report: Dictionary) -> Dictionary:
	var transfer: Dictionary = report.delivery
	var reference: Dictionary = region_registry().parties.get(str(transfer.courier_token), {})
	if str(reference.get("phase", "")) != "entered" or str(reference.get("destination_site", "")) != str(transfer.receiver_scope) \
		or str(reference.get("plan_path", "")) != str(transfer.plan_path) or str(reference.get("plan_sha256", "")) != str(transfer.get("plan_sha256", "")) \
		or float(reference.get("arrival_game_seconds", -1.0)) != float(transfer.ready_at) \
		or RegionAI.delivery_hash(reference.get("arrival_mapping", {})) != str(transfer.get("arrival_mapping_sha256", "")): return fail("STALE_DELIVERY_ARRIVAL")
	var mode := "live" if str(transfer.receiver_scope) == str(control.active_site_id) else str(region_registry().modes.get(str(transfer.receiver_scope), {}).get("mode", "cold_exact"))
	var owner: Dictionary = region_owner_lab.call(str(transfer.receiver_scope), mode)
	if not owner.get("ok", false) or not owner.get("lab") is TerrainLab: return owner
	var original: TerrainLab = owner.lab
	var bind := original.region_bind_receipt(original.terrain)
	if original.site_controller.region_slot != self or _region_bound_original_lab(original.terrain) != original or not bind.get("complete", false) \
		or int(bind.get("generation", -1)) != int(_marker.generation): return fail("COMMITTED_UNBOUND")
	var courier := _region_delivery_person(original, transfer.courier_ref)
	var receiver := _region_delivery_person(original, transfer.receiver_ref)
	var code := ""
	if courier.is_empty(): code = "COURIER_MISSING"
	elif float(courier.hp) <= 0.0: code = "COURIER_DEAD"
	elif bool(courier.captive): code = "COURIER_CAPTIVE"
	elif not SiteSettlement._fit(courier): code = "COURIER_UNAVAILABLE"
	elif receiver.is_empty(): code = "RECEIVER_MISSING"
	elif float(receiver.hp) <= 0.0: code = "RECEIVER_DEAD"
	elif bool(receiver.captive): code = "RECEIVER_CAPTIVE"
	elif not SiteSettlement._fit(receiver): code = "RECEIVER_UNAVAILABLE"
	elif _region_delivery_office(original, int(receiver.person_id)) != transfer.receiver_office: code = "RECEIVER_AUTHORITY_CHANGED"
	if not code.is_empty(): return {"ok": true, "delivered": false, "receipt": {"code": code, "complete": true, "effects_complete": true, "courier_token": str(transfer.courier_token), "source_generation": int(_marker.generation)}}
	var observation_preview: Dictionary = report.receipt.duplicate(true)
	observation_preview.receiver = int(receiver.person_id)
	observation_preview.received_at = float(control.logical_game_seconds)
	var observation_guard := RegionAI.observe(region_registry().duplicate(true), observation_preview)
	if not observation_guard.ok: return observation_guard
	var actual_effect := {}
	if str(transfer.kind) == "nation_dispatch":
		var received_nation := _region_receive_nation_command(report, original, receiver)
		if not received_nation.ok or not received_nation.get("delivered", false): return received_nation
		actual_effect = received_nation.effect
	if str(transfer.kind) == "army_command":
		var team := _region_delivery_team(original, transfer.team_ref)
		# G6: a crowd-owned team's TerrainArmy slot is a disabled command source; it never takes a Region order.
		if team != null and original.crowd_site != null and original.crowd_site.active and original.crowd_site.owns_original_team(team): team = null
		if team == null or team.current_commander < 0 or team.combat_identity(team.current_commander) != int(receiver.person_id) \
			or not team.command_eligible(team.current_commander): return {"ok": true, "delivered": false, "receipt": {"code": "COMMAND_AUTHORITY_CHANGED", "complete": true, "effects_complete": true}}
		var command: Dictionary = transfer.command
		var before_serial := int(team.get_order_serial())
		var before_ranged_serial := int(team.ranged_order_serial)
		var ordered := team.issue_combat_order(team.current_commander, int(command.order), Vector2i(int(command.goal[0]), int(command.goal[1])))
		if not ordered.ok: return {"ok": true, "delivered": false, "receipt": {"code": "ORIGINAL_COMMAND_REJECTED", "complete": true, "effects_complete": true}}
		actual_effect = {"kind": "original_army_order", "team_ref": transfer.team_ref.duplicate(true), "commander_ref": transfer.receiver_ref.duplicate(true),
			"source_order_serial": int(command.source_order_serial), "before_order_serial": before_serial, "accepted_order_serial": int(team.get_order_serial()),
			"before_ranged_order_serial": before_ranged_serial, "accepted_ranged_order_serial": int(team.ranged_order_serial), "original_order_delay": float(team._order_delay)}
	return {"ok": true, "delivered": true, "receiver": int(receiver.person_id), "receipt": {"code": "DELIVERED", "courier_token": str(transfer.courier_token),
		"source_generation": int(_marker.generation), "arrival_mapping_sha256": str(transfer.arrival_mapping_sha256), "receiver_ref": transfer.receiver_ref.duplicate(true), "effect": actual_effect}}

## Called after original party life/contact endpoints. A report never claims a
## disappearance/KO/capture from a preview or rewrites its signed source time.


func _region_check_carried_deliveries() -> Dictionary:
	var changed := false
	for report: Dictionary in region_registry().get("reports", []):
		if not report.has("delivery") or str(report.delivery.get("phase", "")) != "in_transit": continue
		var valid := RegionAI.validate_carried_report(report)
		if not valid.ok: return valid
		var token := str(report.delivery.courier_token)
		var reference: Dictionary = region_registry().parties.get(token, {})
		if str(reference.get("phase", "")) == "entered": continue
		var loaded := _region_npc_party(token)
		if not loaded.ok: return loaded
		var host: Object = region_original_party_progress.get_object() if region_original_party_progress.is_valid() else null
		if not host is TerrainLab or host.site_controller == null or host.site_controller.region_slot != self: return fail("MISSING_ORIGINAL_PARTY_PROGRESS")
		var hydrated: Dictionary = host.prepare_region_party_original_owner(token, loaded.party, self)
		if not hydrated.ok: return hydrated
		var actual := region_original_party_runtime_proof(token, loaded.party)
		if not actual.ok: return actual
		var courier := _region_delivery_person(actual.lab, report.delivery.courier_ref)
		var code := ""
		if courier.is_empty(): code = "COURIER_MISSING"
		elif float(courier.hp) <= 0.0: code = "COURIER_DEAD"
		elif bool(courier.captive): code = "COURIER_CAPTIVE"
		elif str(report.delivery.kind) == "army_command":
			var team := _region_delivery_team(actual.lab, report.delivery.team_ref)
			if team == null or team.current_commander < 0 or team.combat_identity(team.current_commander) != int(courier.person_id): code = "COMMAND_AUTHORITY_CHANGED"
		if not code.is_empty():
			var rejected := RegionAI.carried_report_result(report, float(control.logical_game_seconds), float(control.fire_clock.action_seconds), {"code": code, "complete": true, "effects_complete": true, "courier_token": token, "source_epoch": actual.proof.duplicate(true)})
			if not rejected.ok: return rejected
			changed = true
		elif loaded.party.upkeep.has("route_blocked"):
			var navigation := {"code": "DELIVERY_ROUTE_BLOCKED", "courier_token": token, "game_seconds": float(control.logical_game_seconds),
				"action_seconds": float(control.fire_clock.action_seconds), "source_node": loaded.party.upkeep.get("route_node", {}).duplicate(true)}
			var prior: Dictionary = report.delivery.get("last_navigation_result", {})
			if prior.get("code") != navigation.code or prior.get("source_node") != navigation.source_node:
				report.delivery.last_navigation_result = navigation
				changed = true
	return {"ok": true, "changed": changed}


func region_known_intel_label(receipt: Dictionary) -> String:
	return RegionAI.known_intel_label(receipt)


func region_player_known_intel() -> Dictionary:
	var current := _region_player_intel_identity()
	if current.is_empty(): return {}
	return RegionAI.view(region_registry(), int(current.identity), float(control.logical_game_seconds), str(current.scope), current.reference)



## Read the same current original owner as ordinary control/family continuity.
## A travelling leader is a route role and does not own another member's intel.


func _region_player_intel_identity() -> Dictionary:
	var selected := region_travel_party()
	if selected.ok and not region_travel_journey().is_empty():
		var token := str(region_travel_journey().token)
		var current := region_original_party_runtime_proof(token, selected.party)
		if not current.ok or not current.get("lab") is TerrainLab: return {}
		var original: TerrainLab = current.lab
		var identity := int(original.controlled_person_id())
		var reference := RegionAI.person_ref(original.terrain.site, identity)
		if not RegionAI.valid_person_ref(reference) or not selected.party.person_ids.has(identity) \
			or int(selected.party.content.get("controlled_person_id", -1)) != identity: return {}
		return {"identity": identity, "reference": reference, "scope": str(selected.party.get("origin_site_id", ""))}
	var owner: TerrainLab = _region_original_labs.get(str(control.active_site_id))
	if region_owner_lab.is_valid():
		var candidate: Object = region_owner_lab.get_object()
		if candidate is TerrainLab and candidate.terrain != null and str(candidate.terrain.site.id) == str(control.active_site_id): owner = candidate
	if not is_instance_valid(owner) or _region_bound_original_lab(owner.terrain) != owner: return {}
	var active_identity := int(owner.controlled_person_id())
	var active_reference := RegionAI.person_ref(owner.terrain.site, active_identity)
	if not RegionAI.valid_person_ref(active_reference): return {}
	return {"identity": active_identity, "reference": active_reference, "scope": str(owner.terrain.site.id)}



## A registered Atlas is public geography. This original officer producer
## records no Site save, hidden army, weapon, garrison, HP or battle registry.
## A source fact is stamped once by the already settled original World.


const OFFICER_GEOGRAPHY_GAME_SECONDS := 86400.0


func record_region_officer_geography_observation(original: TerrainLab, observer_id: int, coordinate: Vector2i) -> Dictionary:
	if not is_instance_valid(original) or original.site_controller == null or original.site_controller.region_slot != self \
		or _region_bound_original_lab(original.terrain) != original: return fail("MISSING_ORIGINAL_OBSERVER")
	var bind := original.region_bind_receipt(original.terrain)
	var settled := validate_settlement(original.terrain.site, float(control.logical_game_seconds))
	if not bind.get("complete", false) or int(bind.get("generation", -1)) != int(_marker.generation) \
		or not settled.ok or settled.legacy or float(settled.pending) > 0.00000001: return fail("STALE_ORIGINAL_OBSERVER")
	var reference := RegionAI.person_ref(original.terrain.site, observer_id)
	var person := _region_delivery_person(original, reference)
	if person.is_empty() or not SiteSettlement._fit(person) or _region_delivery_office(original, observer_id).is_empty(): return fail("NO_OBSERVER_OFFICE")
	var geography := source.get_site_summary(coordinate.x, coordinate.y)
	if not geography.ok or not geography.get("has_terrain", false): return fail("UNKNOWN_GEOGRAPHY")
	var scope := str(original.terrain.site.id)
	var object := str(geography.site_id)
	var now := float(control.logical_game_seconds)
	var value := {"geography_status": str(geography.geography_status), "has_terrain": bool(geography.has_terrain), "atlas_manifest_sha256": str(source.manifest_hash)}
	var known := RegionAI.view(region_registry(), observer_id, now, scope, reference)
	var prior: Dictionary = known.get(object, {})
	if prior.get("observation_kind") == "officer_public_geography" and prior.get("source") == "site_observation" and prior.get("value") == value:
		return {"ok": true, "duplicate": true, "receipt": prior.duplicate(true)}
	var receipt := {"id": "officer-geography:%s:%s:%s:%.6f" % [scope, RegionTravel.stable_key(reference), object, now],
		"source": "site_observation", "observation_kind": "officer_public_geography", "observer": observer_id, "receiver": observer_id,
		"observer_scope": scope, "receiver_scope": scope, "object_scope": object,
		"observer_ref": reference.duplicate(true), "receiver_ref": reference.duplicate(true), "object": object, "value": value,
		"game_time": now, "expires_at": now + OFFICER_GEOGRAPHY_GAME_SECONDS, "confidence": 1.0}
	var recorded := RegionAI.observe(region_registry(), receipt)
	if not recorded.ok: return recorded
	return {"ok": true, "receipt": receipt.duplicate(true)}

## Existing control/journey and stable refs supply P0 scope. A cold local ID
## with the same number never acquires the selected player's authority.


func _region_carried_ref_is_player(reference: Dictionary) -> bool:
	var current := _region_player_intel_identity()
	return not current.is_empty() and current.reference == reference


func _region_remote_nation_source(command: Dictionary) -> Dictionary:
	if not region_owner_lab.is_valid(): return fail("MISSING_REGION_ADAPTER")
	var scope := str(command.source_scope)
	var mode := "live" if scope == str(control.active_site_id) else str(region_registry().modes.get(scope, {}).get("mode", "cold_exact"))
	var owner: Dictionary = region_owner_lab.call(scope, mode)
	if not owner.get("ok", false) or not owner.get("lab") is TerrainLab: return owner
	var original: TerrainLab = owner.lab
	var bind := original.region_bind_receipt(original.terrain)
	if _region_bound_original_lab(original.terrain) != original or original.site_controller.region_slot != self \
		or not bind.get("complete", false) or int(bind.get("generation", -1)) != int(_marker.generation): return fail("COMMITTED_UNBOUND")
	# ORDSERIAL: an active crowd source is admitted; its issuer and nation offices resolve through the crowd-aware person paths.
	var issuer := _region_delivery_person(original, command.issuer_ref)
	if issuer.is_empty(): return fail("SOURCE_COMMANDER_MISSING")
	if float(issuer.hp) <= 0.0: return fail("SOURCE_COMMANDER_DEAD")
	if bool(issuer.captive): return fail("SOURCE_COMMANDER_CAPTIVE")
	var nation: Dictionary = original.terrain.site.get("equipment_nations", {}).get(str(command.nation_id), {})
	var reference: Dictionary = original.terrain.site.get("travel_identity", {}).get("refs", {}).get("nation", {}).get(str(command.nation_id), {})
	if nation.is_empty() or reference != command.nation_ref or not SiteOffices.validate(nation.get("offices", {}), "nation") \
		or int(nation.offices.revision) != int(command.offices_revision): return fail("SOURCE_AUTHORITY_CHANGED")
	var resolved: Dictionary = original.site_controller.equipment_orders.nation_duty_resolve(nation, "nation.dispatch")
	if not resolved.get("ok", false): return fail("SOURCE_COMMANDER_UNAVAILABLE")
	if RegionAI.person_ref(original.terrain.site, int(resolved.decider)) != command.issuer_ref or int(resolved.revision) != int(command.offices_revision): return fail("SOURCE_AUTHORITY_CHANGED")
	if _region_carried_ref_is_player(command.issuer_ref): return fail("PLAYER_HOLDER")
	return {"ok": true, "lab": original, "nation": nation, "nation_ref": reference, "issuer": issuer, "resolved": resolved}

## The original foreign membership references identify this exact remote
## cohort. Nation authority remains in its sole original source record.


## G6.4: an active crowd team is a CrowdPersonOwner of this exact crowd. A stale disabled
## TerrainArmy never stands in for a crowd team, and a crowd team never stands in for a TerrainArmy.
func _region_remote_team_membership(source_owner: Dictionary, original: TerrainLab, team: Variant, nation_ref: Dictionary) -> Dictionary:
	var crowd_active: bool = original.crowd_site != null and original.crowd_site.active
	if team == null or crowd_active != (team is CrowdPersonOwner) or team is CrowdPersonOwner and team.crowd_site != original.crowd_site \
		or not SiteEquipmentOrders.valid_organization_refs(original.terrain.site): return fail("INVALID_REMOTE_MEMBERSHIP")
	if not team.combat_enabled or team.current_commander < 0 or not team.command_eligible(team.current_commander): return fail("NO_COMMANDER")
	var source_refs: Dictionary = source_owner.lab.terrain.site.get("travel_identity", {}).get("refs", {}).get("person", {})
	var commander_ref := RegionAI.person_ref(original.terrain.site, team.combat_identity(team.current_commander))
	# Crowd combat_units keys are World indices and need not be 0..size-1.
	var indices: Array = team.combat_units.keys() if team is CrowdPersonOwner else range(team.combat_units.size())
	for index: int in indices:
		if not team.is_member(index): continue
		var person_ref := RegionAI.person_ref(original.terrain.site, team.combat_identity(index))
		if not RegionAI.valid_person_ref(person_ref) or _region_carried_ref_is_player(person_ref): return fail("PLAYER_PARTY")
		var actual_source_member := false
		for member: Variant in source_owner.nation.get("members", []):
			if source_refs.get(str(int(member)), {}) == person_ref: actual_source_member = true; break
		var actual_portable_member := false
		for membership: Dictionary in original.terrain.site.get("organization_refs", {}).get("nation_memberships", []):
			if membership.person == person_ref and membership.nation == nation_ref \
				and str(membership.source_site_id) == str(source_owner.lab.terrain.site.id): actual_portable_member = true; break
		if not actual_source_member or not actual_portable_member: return fail("REMOTE_MEMBERSHIP_CHANGED")
	return {"ok": true, "commander_ref": commander_ref}

## A true local courier dispatch carries a signed strategic instruction for
## another original team. It grants no tactical command power to the Nation.


func prepare_region_carried_nation_command(courier_dispatch: Dictionary, source_receipt_id: String,
		receiver_scope: String, receiver_team_ref: Dictionary, target_coordinate: Vector2i) -> Dictionary:
	if not courier_dispatch.get("ok", false) or not courier_dispatch.get("lab") is TerrainLab or not RegionAI.delivery_reference(receiver_team_ref, "team"): return fail("INVALID_NATION_COMMAND")
	var source_lab: TerrainLab = courier_dispatch.lab
	var nation_id := str(courier_dispatch.request.nation_id)
	var nation: Dictionary = source_lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	var nation_ref: Dictionary = source_lab.terrain.site.get("travel_identity", {}).get("refs", {}).get("nation", {}).get(nation_id, {})
	var issuer_ref := RegionAI.person_ref(source_lab.terrain.site, int(courier_dispatch.request.decider))
	var source_command := {"source_scope": str(source_lab.terrain.site.id), "nation_id": nation_id, "nation_ref": nation_ref.duplicate(true),
		"issuer_ref": issuer_ref.duplicate(true), "offices_revision": int(courier_dispatch.request.offices_revision)}
	var authority := _region_remote_nation_source(source_command)
	if not authority.ok or not bool(nation.get("offices", {}).get("duty_ai", false)): return authority if not authority.ok else fail("DUTY_AI_DISABLED")
	var known: Dictionary = region_registry().observations.get(source_receipt_id, {})
	var target_id := Grid.site_id(str(pin.atlas_id), target_coordinate)
	if str(known.get("object", "")) != target_id or not RegionAI.receiver_matches(known, int(authority.issuer.person_id), str(source_lab.terrain.site.id), issuer_ref) \
		or not RegionAI.view(region_registry(), int(authority.issuer.person_id), float(control.logical_game_seconds), str(source_lab.terrain.site.id), issuer_ref).has(target_id): return fail("UNKNOWN_COMMAND_TARGET")
	var requested_mode := "live" if receiver_scope == str(control.active_site_id) else str(region_registry().modes.get(receiver_scope, {}).get("mode", "cold_exact"))
	var actual_receiver: Dictionary = region_owner_lab.call(receiver_scope, requested_mode)
	if not actual_receiver.get("ok", false) or not actual_receiver.get("lab") is TerrainLab: return actual_receiver
	var receiver_lab: TerrainLab = actual_receiver.lab
	var receiver_team: Variant = _region_nation_team(receiver_lab, receiver_team_ref)
	var membership := _region_remote_team_membership(authority, receiver_lab, receiver_team, nation_ref)
	if not membership.ok: return membership
	var receiver_id: int = receiver_team.combat_identity(receiver_team.current_commander)
	var prepared := prepare_region_carried_report(courier_dispatch, source_receipt_id, receiver_scope, receiver_id)
	if not prepared.ok: return prepared
	var report: Dictionary = courier_dispatch.carried_reports.pop_back()
	var id := "carried:%s:%s:nation:%s" % [str(courier_dispatch.token), source_receipt_id, RegionTravel.stable_key(receiver_team_ref).sha256_text().substr(0, 16)]
	report.id = id
	report.receipt.id = id
	report.delivery.kind = "nation_dispatch"
	source_command.merge({"version": RegionAI.DELIVERY_VERSION, "duty": "nation.dispatch", "receiver_team_ref": receiver_team_ref.duplicate(true),
		"target_site": target_id, "target_coordinate": [target_coordinate.x, target_coordinate.y],
		"receiver_order_serial": int(receiver_team.get_order_serial()), "receiver_ranged_order_serial": int(receiver_team.ranged_order_serial)}, true)
	report.delivery.command = source_command
	var valid := RegionAI.validate_carried_report(report)
	if not valid.ok: return valid
	courier_dispatch.carried_reports.append(report)
	return {"ok": true, "report": report.duplicate(true), "dispatch": courier_dispatch}


func _region_receive_nation_command(report: Dictionary, original: TerrainLab, receiver: Dictionary) -> Dictionary:
	var command: Dictionary = report.delivery.command
	var authority := _region_remote_nation_source(command)
	if not authority.ok:
		if str(authority.get("code", "")) in ["COMMITTED_UNBOUND", "MISSING_REGION_ADAPTER", "UNSUPPORTED_BACKEND"]: return authority
		return {"ok": true, "delivered": false, "receipt": {"code": str(authority.get("code", "SOURCE_AUTHORITY_CHANGED")), "complete": true, "effects_complete": true}}
	var team: Variant = _region_nation_team(original, command.receiver_team_ref)
	var membership := _region_remote_team_membership(authority, original, team, command.nation_ref)
	if not membership.ok or membership.get("commander_ref") != report.delivery.receiver_ref: return {"ok": true, "delivered": false, "receipt": {"code": "REMOTE_MEMBERSHIP_CHANGED", "complete": true, "effects_complete": true}}
	if int(team.get_order_serial()) != int(command.receiver_order_serial) or int(team.ranged_order_serial) != int(command.receiver_ranged_order_serial):
		return {"ok": true, "delivered": false, "receipt": {"code": "COMMAND_SUPERSEDED", "complete": true, "effects_complete": true}}
	var before_serial := int(team.get_order_serial())
	var before_ranged := int(team.ranged_order_serial)
	var prior_tactical_policy := bool(team.tactical_ai_enabled)
	var accepted := _region_team_hold(team)
	if not accepted.ok: return {"ok": true, "delivered": false, "receipt": {"code": "ORIGINAL_COMMAND_REJECTED", "complete": true, "effects_complete": true}}
	var effect := {"kind": "original_nation_dispatch", "execution": "pending", "nation_ref": command.nation_ref.duplicate(true),
		"receiver_team_ref": command.receiver_team_ref.duplicate(true), "receiver_ref": report.delivery.receiver_ref.duplicate(true),
		"before_order_serial": before_serial, "accepted_order_serial": int(team.get_order_serial()),
		"before_ranged_order_serial": before_ranged, "accepted_ranged_order_serial": int(team.ranged_order_serial),
		"prior_tactical_ai_enabled": prior_tactical_policy,
		"original_order_delay": _region_team_order_delay(team), "received_action_seconds": float(control.fire_clock.action_seconds),
		"received_game_seconds": float(control.logical_game_seconds)}
	return {"ok": true, "delivered": true, "effect": effect}


func _region_authorize_received_nation_dispatch(original: TerrainLab, team_id: int, target_site: String, token: String, report_id: String, preflight: Callable) -> Dictionary:
	var report: Dictionary = {}
	for candidate: Dictionary in region_registry().reports:
		if str(candidate.get("id", "")) == report_id: report = candidate
	if report.is_empty() or report.get("delivery", {}).get("kind") != "nation_dispatch" or report.delivery.phase != "delivered" \
		or report.delivery.get("result", {}).get("effect", {}).get("execution") != "pending" \
		or str(report.delivery.receiver_scope) != str(original.terrain.site.id) or str(report.delivery.command.target_site) != target_site: return fail("INVALID_NATION_COMMAND")
	var command: Dictionary = report.delivery.command
	var authority := _region_remote_nation_source(command)
	if not authority.ok: return authority
	var team: Variant = _region_nation_team(original, command.receiver_team_ref)
	var membership := _region_remote_team_membership(authority, original, team, command.nation_ref)
	if not membership.ok: return membership
	var effect: Dictionary = report.delivery.result.effect
	if int(team.team_id) != team_id or membership.commander_ref != report.delivery.receiver_ref \
		or int(team.get_order_serial()) != int(effect.accepted_order_serial) or int(team.ranged_order_serial) != int(effect.accepted_ranged_order_serial): return fail("COMMAND_SUPERSEDED")
	if _region_team_order_delay(team) > TerrainLab.ACTION_TIME_EPSILON: return fail("ORIGINAL_COMMAND_DELAY")
	if float(report.receipt.expires_at) <= float(control.logical_game_seconds): return fail("SOURCE_COMMAND_EXPIRED")
	if not RegionAI.receiver_matches(report.delivered_receipt, team.combat_identity(team.current_commander), str(original.terrain.site.id), membership.commander_ref) \
		or not RegionAI.view(region_registry(), team.combat_identity(team.current_commander), float(control.logical_game_seconds), str(original.terrain.site.id), membership.commander_ref).has(target_site): return fail("UNKNOWN_COMMAND_TARGET")
	var request := {"nation_id": str(command.nation_id), "nation_ref": command.nation_ref.duplicate(true), "nation_scope": str(command.source_scope),
		"decider": int(authority.issuer.person_id), "decider_ref": command.issuer_ref.duplicate(true), "commander": team.combat_identity(team.current_commander),
		"team_id": team_id, "target_site": target_site, "transfer_token": token, "offices_revision": int(command.offices_revision), "known_receipt": report_id,
		"carried_nation_command": report_id}
	var checked: Dictionary = preflight.call(request)
	if not checked.get("ok", false): return checked
	return {"ok": true, "request": request, "owner_preview": checked}


func _region_nation_execution_failed(report: Dictionary, code: String) -> void:
	report.delivery.result.effect.execution = "failed"
	report.delivery.result.effect.execution_receipt = {"code": code, "complete": true, "effects_complete": true,
		"game_seconds": float(control.logical_game_seconds), "action_seconds": float(control.fire_clock.action_seconds), "source_generation": int(_marker.generation)}

## Original commit calls this only on its detached next registry, after the
## real new party/route files exist. No live ledger is marked dispatched while
## that party is absent; a pre-publication failure leaves the old command pending.


func _region_commit_received_nation_execution(registry: Dictionary, prepared: Dictionary, token: String) -> Dictionary:
	var id := str(prepared.request.get("carried_nation_command", ""))
	if id.is_empty(): return {"ok": true}
	if token != "npc_command_" + id.sha256_text().substr(0, 32): return fail("INVALID_NATION_COMMAND")
	var report: Dictionary = {}
	for candidate: Dictionary in registry.reports:
		if str(candidate.get("id", "")) == id: report = candidate
	if report.is_empty() or report.delivery.kind != "nation_dispatch" or report.delivery.phase != "delivered" \
		or report.delivery.result.effect.execution != "pending": return fail("INVALID_NATION_COMMAND")
	var command: Dictionary = report.delivery.command
	if prepared.request.get("nation_ref") != command.nation_ref or prepared.request.get("nation_scope") != command.source_scope \
		or prepared.request.get("target_site") != command.target_site or str(prepared.lab.terrain.site.id) != str(report.delivery.receiver_scope) \
		or prepared.party.content.get("travel_identity", {}).get("refs", {}).get("team", {}).get(str(int(prepared.request.team_id)), {}) != command.receiver_team_ref: return fail("INVALID_NATION_COMMAND")
	var original: TerrainLab = prepared.lab
	var authority := _region_remote_nation_source(command)
	if not authority.ok: return authority
	var team: Variant = _region_nation_team(original, command.receiver_team_ref)
	var membership := _region_remote_team_membership(authority, original, team, command.nation_ref)
	if not membership.ok or membership.get("commander_ref") != report.delivery.receiver_ref: return fail("REMOTE_MEMBERSHIP_CHANGED")
	var effect: Dictionary = report.delivery.result.effect
	if _region_team_order_delay(team) > TerrainLab.ACTION_TIME_EPSILON or int(team.get_order_serial()) != int(effect.accepted_order_serial) \
		or int(team.ranged_order_serial) != int(effect.accepted_ranged_order_serial): return fail("COMMAND_SUPERSEDED")
	effect.execution = "dispatched"
	effect.execution_receipt = {"code": "DISPATCHED", "complete": true, "effects_complete": true, "transfer_token": token,
		"source_generation": int(_marker.generation), "game_seconds": float(control.logical_game_seconds), "action_seconds": float(control.fire_clock.action_seconds),
		"paid_original_delay_action": float(control.fire_clock.action_seconds) - float(effect.received_action_seconds)}
	return {"ok": true}

## Called only after the actual original party/Site endpoints. Original Army
## _order_delay is the waiting authority; no second timer or dispatch queue.


func _region_finalize_received_nation_commands() -> Dictionary:
	var changed := false
	for report: Dictionary in region_registry().reports:
		if report.get("delivery", {}).get("kind") != "nation_dispatch": continue
		var command: Dictionary = report.delivery.command
		if report.delivery.phase == "in_transit":
			var source_authority := _region_remote_nation_source(command)
			if not source_authority.ok:
				var source_code := str(source_authority.get("code", ""))
				# A temporary KO does not forge permanent withdrawal. Recheck
				# fit at actual receipt/execution; death/capture/revision is final.
				if source_code == "SOURCE_COMMANDER_UNAVAILABLE": continue
				if source_code in ["COMMITTED_UNBOUND", "MISSING_REGION_ADAPTER", "UNSUPPORTED_BACKEND"]: return source_authority
				var failed_source := RegionAI.carried_report_result(report, float(control.logical_game_seconds), float(control.fire_clock.action_seconds), {"code": source_code, "complete": true, "effects_complete": true})
				if not failed_source.ok: return failed_source
				changed = true
			continue
		if report.delivery.phase != "delivered" or report.delivery.result.get("effect", {}).get("execution") != "pending": continue
		if float(report.receipt.expires_at) <= float(control.logical_game_seconds):
			_region_nation_execution_failed(report, "SOURCE_COMMAND_EXPIRED")
			changed = true
			continue
		var scope := str(report.delivery.receiver_scope)
		var mode := "live" if scope == str(control.active_site_id) else str(region_registry().modes.get(scope, {}).get("mode", "cold_exact"))
		var owner: Dictionary = region_owner_lab.call(scope, mode)
		if not owner.get("ok", false) or not owner.get("lab") is TerrainLab: return owner
		var original: TerrainLab = owner.lab
		var team: Variant = _region_nation_team(original, command.receiver_team_ref)
		if team == null:
			_region_nation_execution_failed(report, "RECEIVER_TEAM_MISSING")
			changed = true
			continue
		if _region_team_order_delay(team) > TerrainLab.ACTION_TIME_EPSILON: continue
		var authority := _region_remote_nation_source(command)
		if not authority.ok:
			if str(authority.get("code", "")) in ["COMMITTED_UNBOUND", "MISSING_REGION_ADAPTER", "UNSUPPORTED_BACKEND"]: return authority
			_region_nation_execution_failed(report, str(authority.get("code", "SOURCE_AUTHORITY_CHANGED")))
			changed = true
			continue
		var membership := _region_remote_team_membership(authority, original, team, command.nation_ref)
		var accepted_effect: Dictionary = report.delivery.result.effect
		if not membership.ok or membership.get("commander_ref") != report.delivery.receiver_ref \
			or int(team.get_order_serial()) != int(accepted_effect.accepted_order_serial) \
			or int(team.ranged_order_serial) != int(accepted_effect.accepted_ranged_order_serial):
			_region_nation_execution_failed(report, "COMMAND_SUPERSEDED")
			changed = true
			continue
		# The captain accepts the strategic departure through its own original
		# order API. That API pauses tactical policy; restore the pre-existing
		# policy through its original public caller after the paid delay.
		if bool(report.delivery.result.effect.prior_tactical_ai_enabled) and not team.tactical_ai_enabled:
			var restored_policy := _region_team_restore_policy(team)
			if not restored_policy.ok:
				_region_nation_execution_failed(report, "ORIGINAL_POLICY_REJECTED")
				changed = true
				continue
			changed = true
		var transfer_token := "npc_command_" + str(report.id).sha256_text().substr(0, 32)
		var commander := _region_delivery_person(original, report.delivery.receiver_ref)
		if commander.is_empty():
			_region_nation_execution_failed(report, "RECEIVER_MISSING")
			changed = true
			continue
		var component := RegionTravelSite.start_component(self, _coordinate(original.terrain).site, commander.cell, original.terrain)
		var prepared := prepare_npc_region_dispatch(original, str(command.nation_id), int(team.team_id),
			Vector2i(int(command.target_coordinate[0]), int(command.target_coordinate[1])), component, [], transfer_token, str(report.id))
		if not prepared.ok:
			if str(prepared.get("code", "")) in ["BUSY", "NOT_READY", "PLAYER_BARRIER", "ORIGINAL_COMMAND_DELAY", "RELATION_OPEN"]: continue
			if str(prepared.get("code", "")) in ["COMMITTED_UNBOUND", "UNSETTLED_SITE", "MISSING_REGION_ADAPTER"]: return prepared
			_region_nation_execution_failed(report, str(prepared.get("code", "NATION_DISPATCH_REJECTED")))
			changed = true
			continue
		var dispatched := commit_npc_region_dispatch(prepared)
		if not dispatched.ok: return dispatched
		# The existing common publication already persisted the command result,
		# exact new party and source closure together. Restart with fresh aliases.
		return {"ok": true, "changed": true, "published": true}
	return {"ok": true, "changed": changed, "published": false}

## The existing evaluation event remains the only strategy cadence. It may
## send a local original NPC cohort to carry a strategic MOVE-to-known-Site
## instruction. Geography supplies no enemy strength or tactical attack order.
## Targets and own-cohort readiness reuse the existing dispatch policy helpers.


func _region_produce_remote_nation_dispatch(source_lab: TerrainLab) -> Dictionary:
	var source_scope := str(source_lab.terrain.site.id)
	var now := float(control.logical_game_seconds)
	var nations: Array = source_lab.terrain.site.get("equipment_nations", {}).keys()
	nations.sort()
	for nation_id: String in nations:
		var nation: Dictionary = source_lab.terrain.site.equipment_nations[nation_id]
		if not nation.get("offices") is Dictionary or not nation.offices.get("duty_ai", false): continue
		var resolved: Dictionary = source_lab.site_controller.equipment_orders.nation_duty_resolve(nation, "nation.dispatch")
		if not resolved.get("ok", false): continue
		var issuer_ref := RegionAI.person_ref(source_lab.terrain.site, int(resolved.decider))
		var nation_ref: Dictionary = source_lab.terrain.site.get("travel_identity", {}).get("refs", {}).get("nation", {}).get(nation_id, {})
		var authority := _region_remote_nation_source({"source_scope": source_scope, "nation_id": nation_id,
			"nation_ref": nation_ref, "issuer_ref": issuer_ref, "offices_revision": int(resolved.revision)})
		if not authority.ok: continue
		var known := RegionAI.view(region_registry(), int(resolved.decider), now, source_scope, issuer_ref)
		var targets := RegionAI.dispatch_known_targets(source_lab, known, int(resolved.decider), now)
		# Public officer geography also authorizes a movement goal. It never
		# invents zero enemy power to pass an attack-strength comparison.
		for receipt: Dictionary in known.values():
			if receipt.get("observation_kind") != "officer_public_geography" or receipt.get("value", {}).get("has_terrain") != true: continue
			var prefix := str(pin.atlas_id) + ":"
			var site_id := str(receipt.get("object", ""))
			if not site_id.begins_with(prefix) or site_id == source_scope: continue
			var coordinate := site_id.trim_prefix(prefix).split(":")
			if coordinate.size() != 2 or not coordinate[0].is_valid_int() or not coordinate[1].is_valid_int(): continue
			targets.append({"site_id": site_id, "coordinate": [coordinate[0].to_int(), coordinate[1].to_int()], "receipt": str(receipt.id), "geography_only": true})
		targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.site_id) < str(b.site_id) or a.site_id == b.site_id and str(a.receipt) < str(b.receipt))
		var thresholds := RegionAI.military_thresholds(RegionDuties.personality(int(resolved.decider), null, source_lab))
		var tokens: Array = region_registry().parties.keys()
		tokens.sort()
		for remote_token: String in tokens:
			var reference: Dictionary = region_registry().parties[remote_token]
			if reference.get("phase") != "entered" or reference.get("controller") != "npc": continue
			var request: Dictionary = reference.get("transfer_receipt", {})
			if request.get("nation_id") != nation_id or str(request.get("nation_scope", Grid.site_id(str(pin.atlas_id), Vector2i(int(reference.origin[0]), int(reference.origin[1]))))) != source_scope: continue
			var receiver_scope := str(reference.get("destination_site", ""))
			if receiver_scope.is_empty() or receiver_scope == source_scope: continue
			var mode := "live" if receiver_scope == str(control.active_site_id) else str(region_registry().modes.get(receiver_scope, {}).get("mode", "cold_exact"))
			var receiver_owner: Dictionary = region_owner_lab.call(receiver_scope, mode)
			if not receiver_owner.get("ok", false) or not receiver_owner.get("lab") is TerrainLab: return receiver_owner
			var original: TerrainLab = receiver_owner.lab
			var party := _region_npc_party(remote_token, true) # An entered cohort: read its frozen stable references.
			if not party.ok: return party
			var remote_ref: Dictionary = party.party.content.get("travel_identity", {}).get("refs", {}).get("team", {}).get(str(int(request.team_id)), {})
			var remote_team: Variant = _region_nation_team(original, remote_ref)
			var membership := _region_remote_team_membership(authority, original, remote_team, nation_ref)
			if not membership.ok: continue
			var own := RegionAI.dispatch_ready_summary(remote_team, original, thresholds)
			if own.is_empty(): continue
			var pending := false
			for report: Dictionary in region_registry().reports:
				if report.get("delivery", {}).get("kind") == "nation_dispatch" and report.delivery.command.nation_ref == nation_ref \
					and report.delivery.command.receiver_team_ref == remote_ref \
					and (report.delivery.phase in ["in_transit", "ready"] or report.delivery.phase == "delivered" and report.delivery.result.effect.execution == "pending"): pending = true; break
			if pending: continue
			for target: Dictionary in targets:
				if str(target.site_id) == receiver_scope: continue
				if not target.get("geography_only", false) and float(own.power) / maxf(0.1, float(target.power)) < float(thresholds.pursuit) + float(thresholds.hold) - 0.65: continue
				var receiver_coordinate := _coordinate(original.terrain)
				if not receiver_coordinate.ok: return receiver_coordinate
				var receiver_known := record_region_officer_geography_observation(source_lab, int(resolved.decider), receiver_coordinate.site)
				if not receiver_known.ok: return receiver_known
				for courier: TerrainArmy in source_lab.combat_armies:
					if not courier.combat_enabled or courier.index_for_identity(int(resolved.decider)) >= 0 \
						or not courier.command_eligible(courier.current_commander) or not source_lab.site_controller.equipment_orders._member(nation, courier.combat_identity(courier.current_commander)): continue
					var person: Dictionary = source_lab.site_controller.person_actions._person(courier.combat_identity(courier.current_commander), false)
					if person.is_empty(): continue
					var component := RegionTravelSite.start_component(self, _coordinate(source_lab.terrain).site, person.cell, source_lab.terrain)
					var token := "npc_courier_" + Crypto.new().generate_random_bytes(16).hex_encode()
					var candidate := prepare_npc_region_dispatch(source_lab, nation_id, courier.team_id, receiver_coordinate.site, component, [], token)
					if not candidate.ok: continue
					var signed := prepare_region_carried_nation_command(candidate, str(target.receipt), receiver_scope, remote_ref, Vector2i(int(target.coordinate[0]), int(target.coordinate[1])))
					if not signed.ok: return signed
					var committed := commit_npc_region_dispatch(candidate)
					if not committed.ok: return committed
					return {"ok": true, "published": true, "token": token, "report_id": str(signed.report.id)}
	return {"ok": true, "published": false}


## Append to ORIGINAL RegionSaveSlot. These opaque tickets are disposable
## preflights, never a second route, freight, person, item or research ledger.


var _region_n08_transfer_permits: Dictionary = {}


func nation_n08_driver_consent_context(lab: TerrainLab, nation_id: String, identity: int, purpose: String) -> Dictionary:
	if lab == null or lab.site_controller == null or lab.site_controller.region_slot != self: return fail("WRONG_SLOT")
	var technology: GDScript = load("res://scripts/terrain_lab/site_technology.gd")
	var nation: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(nation_id, {})
	var record: Dictionary = nation.get("technology", {})
	if not technology.valid_scope_record(record, "nation") or record.holder_site_id != str(lab.terrain.site.id): return fail("STALE_SCOPE")
	var project: Dictionary = technology.active_project(record)
	var phase: Dictionary = technology.scope_next_phase(project, project.get("executor", {}))
	if project.get("tech_id") != "N08" or project.get("purpose") != purpose or phase.get("binding") != "public_route" \
		or project.get("executor") != {"site_id": str(lab.terrain.site.id), "person_id": identity}: return fail("STALE_PROJECT")
	var orders: Variant = lab.site_controller.equipment_orders
	var operations: Dictionary = nation.get("technology_operations", {})
	if not orders.valid_nation_operation_record(operations, lab.terrain.site.item_definitions, {}): return fail("CORRUPT_STATE")
	for order: Dictionary in operations.public_orders.values():
		if order.tech_id != "N08" or int(order.project_id) != int(project.id) or int(order.payload.driver_id) != identity \
			or order.status in ["complete", "revoked"] or order.scope_site_id != str(lab.terrain.site.id) \
			or order.scope_nation_id != nation_id or not order.payload.travel_token.is_empty(): continue
		if not orders._nation_duty_ok(int(order.authorizer_id), nation, "nation.transport", true): return fail("NO_AUTHORITY")
		var route := _region_n08_route(lab, str(order.payload.destination_site_id), str(order.payload.vehicle_id),
			identity, str(order.payload.destination_holder), str(order.payload.route_id))
		if not route.ok or route.get("route_ref") != order.payload.route_ref: return route if not route.ok else fail("STALE_ROUTE")
		return {"ok": true, "team": route.carrier.team, "order": order}
	return fail("NO_TARGET")


func _region_n08_actor_state(lab: TerrainLab) -> Dictionary:
	var state := lab.terrain.site.duplicate(true)
	state.armies = []
	for army: TerrainArmy in lab.combat_armies:
		if army.combat_enabled: state.armies.append(army.capture_combat_state())
	for actor: TerrainTestCharacter in lab.combat_actors:
		var key := ""
		for identity: String in state.get("actors", {}):
			if int(state.actors[identity].person_id) == actor.person_id: key = identity; break
		if not key.is_empty(): state.actors[key] = actor.capture_state()
	return state


func _region_n08_wagon(lab: TerrainLab, vehicle_id: String, driver_id: int) -> Dictionary:
	if lab == null or lab.terrain == null or lab.site_controller == null or lab.site_controller.region_slot != self:
		return fail("WRONG_SLOT")
	if lab.site_controller._crowd_active(): return fail("REGION_BACKEND_UNADMITTED")
	var transport: Variant = lab.site_controller.vehicles
	var vehicle: Dictionary = transport.records().get(vehicle_id, {})
	if vehicle.is_empty() or str(vehicle.kind) != "wagon" or int(vehicle.operator_id) != driver_id:
		return fail("NO_DRIVER", "本原入口僅接目前真 NPC 馬車及其操作人")
	var driver: Dictionary = transport._operator(driver_id)
	if driver.is_empty() or not driver.owner is TerrainArmy or not transport._available(driver): return fail("NO_DRIVER")
	var team: TerrainArmy = driver.owner
	if not team.combat_enabled or not lab.combat_armies.has(team) or not team.is_member(team.current_commander) \
		or team.combat_identity(team.current_commander) != driver_id or is_instance_valid(team.player_member) \
		or driver_id == int(lab.controlled_person_id()): return fail("NO_CIVIL_COHORT", "須保留原 NPC 指揮／車輛整閉包及當前玩家人物")
	if not vehicle.move.is_empty() or team.combat_order != TerrainArmy.CombatOrder.HOLD or team.moving_member_count() != 0:
		return fail("BUSY")
	for index: int in team.combat_units.size():
		var person := team.combat_identity(index)
		if person == int(lab.controlled_person_id()) or lab.site_controller.person_actions.is_busy(person) \
			or lab.site_controller.person_actions.is_guarding(person) or lab.site_controller.work_team.is_assigned(person) \
			or lab.site_controller._is_delivering_person(person): return fail("BUSY")
	return {"ok": true, "transport": transport, "vehicle": vehicle, "driver": driver, "team": team}


func _region_n08_known_destination(destination_site_id: String) -> Dictionary:
	var known := known_saved_sites()
	if not known.ok: return known
	for coordinate: Vector2i in known.sites:
		if Grid.site_id(str(pin.atlas_id), coordinate) != destination_site_id: continue
		var original: TerrainLab = _region_original_labs.get(destination_site_id)
		if is_instance_valid(original) and original.terrain != null:
			return {"ok": true, "coordinate": coordinate, "data": original.terrain}
		var loaded := _load_checked(site_path(coordinate), coordinate)
		if not loaded.ok: return loaded
		return {"ok": true, "coordinate": coordinate, "data": loaded.data}
	return fail("UNKNOWN_DESTINATION", "公共路線只接同原世界／存檔槽的真已保存目的地")


func _region_n08_route(lab: TerrainLab, destination_site_id: String, vehicle_id: String,
		driver_id: int, destination_holder: String, route_id: String = "") -> Dictionary:
	var carrier := _region_n08_wagon(lab, vehicle_id, driver_id)
	if not carrier.ok: return carrier
	var coordinate := _coordinate(lab.terrain)
	if not coordinate.ok: return coordinate
	if not destination_holder.begins_with("feature:"): return fail("NO_WAREHOUSE")
	var destination := _region_n08_known_destination(destination_site_id)
	if not destination.ok: return destination
	if destination.coordinate == coordinate.site: return fail("SAME_SITE")
	var feature_id := destination_holder.trim_prefix("feature:")
	var feature: Dictionary = destination.data.site.get("features", {}).get(feature_id, {})
	var stocks: GDScript = load("res://scripts/terrain_lab/site_stockpiles.gd")
	var stock: Dictionary = stocks.stock_endpoint(destination.data, feature_id)
	if feature.get("kind") != "warehouse" or stock.is_empty() or bool(stock.get("withdraw_only", true)) \
		or int(stock.faction) != int(carrier.team.faction_id) \
		or Runtime.carried_load(destination.data.site, stock.cargo, stock.holder) + 4 > int(stock.capacity):
		return fail("NO_WAREHOUSE", "目的須是同管理方可進料且有真容量的原倉庫")
	var state := _region_n08_actor_state(lab)
	var spec := {"person_id": driver_id, "actor_key": "", "team_id": int(carrier.team.team_id), "mode": "land",
		"controller": "npc", "game_seconds": float(control.logical_game_seconds),
		"namespace": str(pin.world_instance_id) + ":" + str(lab.terrain.site.id), "family_transfer_guard": region_family_transfer_guard}
	var preview_token := "civil_query_" + str(driver_id)
	var extracted := RegionTravel.extract(state, spec, preview_token)
	if not extracted.ok: return extracted
	# A partial original Nation remains at its original Source holder. A public
	# logistics query cannot move that institution or duplicate its research.
	var route_context := prepare_region_route_context(lab.terrain, extracted.party)
	if not route_context.ok: return route_context
	var table := RegionRoute.table_from_terrain(lab.terrain, PackedByteArray(), true)
	if not table.ok: return table
	var start_component := RegionRoute.component_of(table, carrier.driver.cell)
	if start_component < 0: return fail("NO_ROUTE")
	var search := RegionRoute.Search.new()
	search.source = source; search.start_site = coordinate.site
	search.start_component = start_component; search.goal_site = destination.coordinate
	search.context = route_context.context
	var found := search.run()
	if not found.ok: return found
	var verified := RegionRoute.verify_steps(source, found.steps, route_context.context)
	if not verified.ok: return verified
	var identity := "civil_" + JSON.stringify([str(pin.world_instance_id), str(pin.slot_id), str(lab.terrain.site.id),
		destination_site_id, vehicle_id, driver_id, destination_holder, found.steps], "", true, true).sha256_text().substr(0, 40)
	if not route_id.is_empty() and route_id != identity: return fail("STALE_ROUTE")
	var route_ref := {"world_instance_id": str(pin.world_instance_id), "slot_id": str(pin.slot_id),
		"source_site_id": str(lab.terrain.site.id), "destination_site_id": destination_site_id, "route_id": identity}
	return {"ok": true, "route_ref": route_ref, "route_id": identity, "destination": destination.coordinate,
		"destination_data": destination.data, "destination_holder": destination_holder, "vehicle_id": vehicle_id,
		"driver_id": driver_id, "carrier": carrier, "steps": found.steps, "start_component": start_component}


func nation_route_options(lab: TerrainLab) -> Dictionary:
	if lab == null or lab.site_controller == null or lab.site_controller.region_slot != self: return fail("WRONG_SLOT")
	var known := known_saved_sites()
	if not known.ok: return known
	var routes: Array[Dictionary] = []
	var vehicle_ids: Array = lab.site_controller.vehicles.records().keys()
	vehicle_ids.sort()
	for coordinate: Vector2i in known.sites:
		var identity := Grid.site_id(str(pin.atlas_id), coordinate)
		if identity == str(lab.terrain.site.id): continue
		var destination := _region_n08_known_destination(identity)
		if not destination.ok: continue
		var feature_ids: Array = destination.data.site.get("stockpiles", {}).keys()
		feature_ids.sort()
		for feature: String in feature_ids:
			if destination.data.site.features.get(feature, {}).get("kind") != "warehouse": continue
			for vehicle: String in vehicle_ids:
				var record: Dictionary = lab.site_controller.vehicles.records()[vehicle]
				if record.get("kind") != "wagon": continue
				var checked := _region_n08_route(lab, identity, vehicle, int(record.operator_id), "feature:" + feature)
				if not checked.ok: continue
				routes.append({"route_id": checked.route_id, "destination_site_id": identity, "destination_holder": "feature:" + feature,
					"vehicle_id": vehicle, "driver_id": int(record.operator_id),
					"label": "%s → %s／%s · 馬車 %s · 操作人 #%d" % [str(lab.terrain.site.id), identity, feature, vehicle, int(record.operator_id)]})
				if routes.size() >= 32: return {"ok": true, "routes": routes, "bounded": true}
	return {"ok": true, "routes": routes, "bounded": false}


func nation_route_query(lab: TerrainLab, route_id: String, destination_site_id: String, vehicle_id: String,
		driver_id: int, destination_holder: String) -> Dictionary:
	return _region_n08_route(lab, destination_site_id, vehicle_id, driver_id, destination_holder, route_id)


func _region_n08_order(lab: TerrainLab, nation_id: String, order_id: String, expected: Dictionary) -> Dictionary:
	if lab == null or lab.site_controller == null or lab.site_controller.region_slot != self: return fail("WRONG_SLOT")
	var orders: Variant = lab.site_controller.equipment_orders
	var checked: Dictionary = orders._public_context(nation_id, order_id, "public_route", true)
	if not checked.ok: return checked
	var order: Dictionary = checked.order
	if order.tech_id != "N08" or order != expected or int(order.authorizer_id) != int(lab.controlled_person_id()) \
		or order.scope_site_id != str(lab.terrain.site.id) or order.scope_nation_id != nation_id:
		return fail("STALE_ORDER")
	if not orders._public_source_paid(order): return fail("NO_BUDGET")
	return {"ok": true, "orders": orders, "nation": checked.nation, "order": order, "nation_id": nation_id, "order_id": order_id}


func _region_n08_transfer_permit(source_lab: TerrainLab, context: Dictionary, carrier_lab: TerrainLab,
		vehicle_id: String, driver_id: int, source_holder: String, destination_holder: String) -> Dictionary:
	var carrier := _region_n08_wagon(carrier_lab, vehicle_id, driver_id)
	if not carrier.ok: return carrier
	var permit := {"nonce": Crypto.new().generate_random_bytes(16).hex_encode(), "source_lab": source_lab, "carrier_lab": carrier_lab,
		"source_site_state": source_lab.terrain.site, "carrier_site_state": carrier_lab.terrain.site,
		"nation_ref": context.nation, "order_ref": context.order, "order_snapshot": context.order.duplicate(true),
		"nation_id": str(context.nation_id), "order_id": str(context.order_id),
		"team_ref": carrier.team, "team_id": int(carrier.team.team_id), "driver_id": driver_id,
		"driver_body": carrier.driver.row, "vehicle_ref": carrier.vehicle, "vehicle_id": vehicle_id,
		"source_holder": source_holder, "destination_holder": destination_holder,
		"generation": int(_marker.get("generation", 0)), "revision": int(region_registry().revision),
		"world": float(control.logical_game_seconds)}
	_region_n08_transfer_permits[str(permit.nonce)] = permit
	return {"ok": true, "permit": permit}


func discard_nation_route_transfer_permit(permit: Dictionary) -> void:
	var nonce := str(permit.get("nonce", ""))
	if is_same(_region_n08_transfer_permits.get(nonce), permit): _region_n08_transfer_permits.erase(nonce)


func validate_nation_route_transfer_permit(transport: Variant, permit: Dictionary, source_holder: String,
		destination_holder: String, resources: Dictionary, item_ids: Array, driver_id: int) -> Dictionary:
	if not is_same(_region_n08_transfer_permits.get(str(permit.get("nonce", ""))), permit) \
		or transport == null or not is_same(transport.lab, permit.get("carrier_lab")) \
		or transport.controller.region_slot != self or resources != {"grain": 4} or not item_ids.is_empty() \
		or source_holder != permit.get("source_holder") or destination_holder != permit.get("destination_holder") \
		or driver_id != int(permit.get("driver_id", -1)): return fail("NO_AUTHORITY", "須為同原 Slot 的真具名四糧移交票據")
	if int(permit.generation) != int(_marker.get("generation", 0)) or int(permit.revision) != int(region_registry().revision) \
		or float(permit.world) != float(control.logical_game_seconds): return fail("STALE_REGION_PERMIT")
	var source_lab: TerrainLab = permit.source_lab
	var carrier_lab: TerrainLab = permit.carrier_lab
	if not is_instance_valid(source_lab) or not is_instance_valid(carrier_lab) \
		or not is_same(source_lab.terrain.site, permit.source_site_state) or not is_same(carrier_lab.terrain.site, permit.carrier_site_state): return fail("STALE_SOURCE")
	var nation: Dictionary = source_lab.terrain.site.get("equipment_nations", {}).get(str(permit.nation_id), {})
	var order: Dictionary = nation.get("technology_operations", {}).get("public_orders", {}).get(str(permit.order_id), {})
	if not is_same(nation, permit.nation_ref) or not is_same(order, permit.order_ref) or order != permit.order_snapshot \
		or order.tech_id != "N08" or order.status in ["complete", "revoked"]: return fail("STALE_ORDER")
	var authority := _region_n08_current_authority(source_lab, nation, int(order.authorizer_id))
	if not authority.ok: return authority
	var vehicle: Dictionary = transport.records().get(str(permit.vehicle_id), {})
	var driver: Dictionary = transport._operator(driver_id)
	if not is_same(vehicle, permit.vehicle_ref) or int(vehicle.get("operator_id", -1)) != driver_id \
		or driver.is_empty() or not is_same(driver.row, permit.driver_body) or not is_same(driver.owner, permit.team_ref): return fail("STALE_SOURCE")
	return {"ok": true}


func prepare_nation_route_load(lab: TerrainLab, nation_id: String, order_id: String, expected: Dictionary) -> Dictionary:
	var context := _region_n08_order(lab, nation_id, order_id, expected)
	if not context.ok: return context
	var order: Dictionary = context.order
	if order.payload.loaded or not order.payload.travel_token.is_empty(): return fail("NO_CHANGE")
	var route := _region_n08_route(lab, str(order.payload.destination_site_id), str(order.payload.vehicle_id),
		int(order.payload.driver_id), str(order.payload.destination_holder), str(order.payload.route_id))
	if not route.ok or route.route_ref != order.payload.route_ref: return route if not route.ok else fail("STALE_ROUTE")
	var phase: Dictionary = lab.site_controller.person_actions.prepare_nation_route_load_phase(nation_id, order_id, order)
	if not phase.ok: return phase
	var ticket := _region_n08_transfer_permit(lab, context, lab, str(order.payload.vehicle_id), int(order.payload.driver_id),
		"feature:" + str(order.payload.reserve_feature_id), str(order.payload.vehicle_id))
	if not ticket.ok: return ticket
	var transfer: Dictionary = route.carrier.transport.prepare_nation_route_transfer(ticket.permit)
	if not transfer.ok: discard_nation_route_transfer_permit(ticket.permit); return transfer
	return {"ok": true, "transfer": transfer, "phase": phase, "permit": ticket.permit}


func _region_n08_paid_token(lab: TerrainLab, nation_id: String, order_id: String, order: Dictionary) -> Dictionary:
	var technology: GDScript = load("res://scripts/terrain_lab/site_technology.gd")
	var nation: Dictionary = lab.terrain.site.equipment_nations[nation_id]
	if technology.scope_known(nation.get("technology", {}), "N08"): return {"ok": true, "token": {}}
	var record: Dictionary = nation.technology
	var project: Dictionary = technology.active_project(record)
	var phase: Dictionary = technology.scope_next_phase(project, project.get("executor", {}), record.get("person_links", []))
	if project.is_empty() or project.tech_id != "N08" or int(project.id) != int(order.project_id) \
		or phase.get("binding") != "public_route" or int(project.executor.get("person_id", -1)) != int(order.payload.driver_id): return fail("STALE_PROJECT")
	var paid: Array[Dictionary] = []
	for payment: Dictionary in project.budget.get("payments", []):
		if payment.phase_id == phase.id and payment.target_id == order.payload.destination_holder \
			and technology.same_person_ref(payment.person, project.executor, record.get("person_links", [])) \
			and technology.material_equal(payment.materials, {"grain": 4}): paid.append(payment)
	if paid.size() != 1: return fail("NO_PAYMENT")
	return {"ok": true, "payment_id": str(paid[0].payment_id), "token": {"scope": "nation", "scope_id": nation_id,
		"project_id": int(project.id), "epoch": int(record.epoch), "purpose": str(project.purpose), "tech_id": "N08",
		"phase_id": str(phase.id), "attempt": int(paid[0].attempt), "person": project.executor.duplicate(),
		"binding": "public_route", "target_id": str(order.payload.destination_holder), "materials": {"grain": 4}}}


func begin_nation_transport_route(lab: TerrainLab, nation_id: String, order_id: String, expected: Dictionary) -> Dictionary:
	var context := _region_n08_order(lab, nation_id, order_id, expected)
	if not context.ok: return context
	var order: Dictionary = context.order
	if not order.payload.loaded or not order.payload.travel_token.is_empty(): return fail("NO_CHANGE")
	if not region_player_barrier().is_empty(): return fail("PLAYER_BARRIER")
	var route := _region_n08_route(lab, str(order.payload.destination_site_id), str(order.payload.vehicle_id),
		int(order.payload.driver_id), str(order.payload.destination_holder), str(order.payload.route_id))
	if not route.ok or route.route_ref != order.payload.route_ref: return route if not route.ok else fail("STALE_ROUTE")
	var paid := _region_n08_paid_token(lab, nation_id, order_id, order)
	if not paid.ok: return paid
	var prepared := _region_n08_prepare_departure(lab, context, route, paid)
	if not prepared.ok: return prepared
	return commit_npc_region_dispatch(prepared)


func _region_n08_current_authority(lab: TerrainLab, nation: Dictionary, authorizer_id: int) -> Dictionary:
	if lab == null or lab.site_controller == null or lab.site_controller.region_slot != self: return fail("WRONG_SLOT")
	var orders: Variant = lab.site_controller.equipment_orders
	if orders._nation_duty_ok(authorizer_id, nation, "nation.transport", true): return {"ok": true}
	# An already accepted civil order survives an original holder's Region move.
	# Re-resolve the SAME original office and true typed body; the source office
	# remains its sole authority and a changed/KO/dead holder does not qualify.
	var offices: Dictionary = orders.nation_offices(nation, true)
	var office_owner: GDScript = load("res://scripts/terrain_lab/site_offices.gd")
	if not office_owner.validate(offices, "nation"): return fail("NO_AUTHORITY")
	var eligible := func(person_id: int) -> bool:
		if not orders._member(nation, person_id): return false
		var reference: Dictionary = lab.terrain.site.get("travel_identity", {}).get("refs", {}).get("person", {}).get(str(person_id), {})
		return _region_n08_original_person_can_act(lab, person_id, reference)
	var head := int(office_owner.head_position(offices).get("holder", -1))
	var resolved: Dictionary = office_owner.resolve(offices, "nation.transport", head if eligible.call(head) else -1, eligible)
	return {"ok": true} if resolved.ok and int(resolved.decider) == authorizer_id else fail("NO_AUTHORITY", "本具名公共運輸仍須原國家現任 civil transport 職責有效")


func _region_n08_original_person_can_act(source_lab: TerrainLab, source_person_id: int, reference: Dictionary) -> bool:
	var local: Dictionary = source_lab.site_controller.person_actions._person(source_person_id)
	if not local.is_empty() and not source_lab.site_controller.equipment_orders.is_remote_organization_person(source_lab.terrain.site, source_person_id):
		return float(local.hp) > 0.0 and (local.owner.combat_can_act(int(local.unit)) if int(local.unit) >= 0 else local.owner.can_act())
	if reference.get("type") != "person": return false
	var wanted := RegionTravel.stable_key(reference)
	for original: TerrainLab in _region_original_labs.values():
		if not is_instance_valid(original) or original.terrain == null or original.site_controller == null or original.site_controller.region_slot != self: continue
		for identity: String in original.terrain.site.get("travel_identity", {}).get("refs", {}).get("person", {}):
			if RegionTravel.stable_key(original.terrain.site.travel_identity.refs.person[identity]) != wanted: continue
			var person: Dictionary = original.site_controller.person_actions._person(int(identity))
			if person.is_empty(): continue # The original source's remote alias owns no body.
			return float(person.hp) > 0.0 and (person.owner.combat_can_act(int(person.unit)) if int(person.unit) >= 0 else person.owner.can_act())
	var selected := region_travel_party()
	if selected.get("ok", false):
		var party: Dictionary = selected.party
		for identity: String in party.content.travel_identity.refs.get("person", {}):
			if RegionTravel.stable_key(party.content.travel_identity.refs.person[identity]) != wanted: continue
			var proof := region_original_party_runtime_proof(str(party.party_id), party)
			if not proof.ok or not proof.get("lab") is TerrainLab: return false
			var person: Dictionary = proof.lab.site_controller.person_actions._person(int(identity))
			return not person.is_empty() and float(person.hp) > 0.0 and (person.owner.combat_can_act(int(person.unit)) if int(person.unit) >= 0 else person.owner.can_act())
	# The original abstract NPC party is itself the accepted body/clock owner.
	# Read its published, current body rather than replaying or inventing one.
	for token: String in region_registry().parties:
		if region_registry().parties[token].get("phase") != "travelling": continue
		var selected_npc := _region_npc_party(token)
		if not selected_npc.ok or absf(float(selected_npc.party.upkeep.at) - float(control.logical_game_seconds)) > 0.00000001: continue
		for identity: String in selected_npc.party.content.travel_identity.refs.get("person", {}):
			if RegionTravel.stable_key(selected_npc.party.content.travel_identity.refs.person[identity]) != wanted: continue
			var bodies := RegionTravel._body_records(selected_npc.party.content)
			var body: Dictionary = bodies.get(int(identity), {})
			return not body.is_empty() and float(body.get("hp", 0.0)) > 0.0 and float(body.get("ko", 0.0)) <= 0.0 \
				and not bool(body.get("captive", false)) and str(body.get("pose", "idle")) == "idle"
	return false


func _region_n08_prepare_departure(lab: TerrainLab, context: Dictionary, route: Dictionary, paid: Dictionary) -> Dictionary:
	if not region_bind_candidate.is_valid(): return fail("MISSING_REGION_ADAPTER")
	var window := validate_settlement(lab.terrain.site, control.logical_game_seconds)
	if not window.ok or bool(window.get("legacy", true)) or float(window.get("pending", INF)) > 0.00000001:
		return fail("UNSETTLED_SITE")
	var token := "civil_" + Crypto.new().generate_random_bytes(16).hex_encode()
	var captured: Dictionary = lab.site_controller.capture_region_checkpoint("region_barrier", false,
		{"civil_transport": true, "token": token, "nation_id": context.nation_id, "order_id": context.order_id}, token)
	if not captured.ok: return captured
	# As the NPC dispatch does: a source whose selected publication lags this frame
	# (the loaded wagon, the funded warehouse) is published first; no clock moves.
	var source_check: Dictionary = lab._region_selected_bind_source(lab.terrain, self)
	if not source_check.ok and str(source_check.get("code", "")) in ["STALE_REGION_CONTEXT", "STALE_REGION_SOURCE_OWNERS", "STALE_REGION_SOURCE_BODY"]:
		if not region_original_endpoint_checkpoint.is_valid(): return fail("MISSING_REGION_ADAPTER", "缺含原活動 Lab 的共同端點 checkpoint")
		var clocks := [float(control.logical_game_seconds), float(control.fire_clock.action_seconds), int(control.fire_clock.sequence)]
		var published: Variant = region_original_endpoint_checkpoint.call({"region_source_publish": "civil_transport", "token": token})
		if not published is Dictionary or not published.get("ok", false): return published if published is Dictionary else fail("INVALID_REGION_RECEIPT")
		if clocks != [float(control.logical_game_seconds), float(control.fire_clock.action_seconds), int(control.fire_clock.sequence)]: return fail("CLOCK_CONTRACT", "派遣前發布不得推進時鐘")
	var original: Dictionary = lab.terrain.site.duplicate(true)
	var fire_capture := _capture_transfer_fire_snapshots(lab.terrain, original)
	if not fire_capture.ok: return fire_capture
	var spec := {"person_id": int(context.order.payload.driver_id), "team_id": int(route.carrier.team.team_id),
		"actor_key": "", "mode": "land", "controller": "npc", "game_seconds": float(control.logical_game_seconds),
		"namespace": str(pin.world_instance_id) + ":" + Crypto.new().generate_random_bytes(16).hex_encode(),
		"family_transfer_guard": region_family_transfer_guard}
	var extracted := RegionTravel.extract(original, spec, token)
	if not extracted.ok: return extracted
	var nation_id := str(context.nation_id)
	var order_id := str(context.order_id)
	if not extracted.origin.get("equipment_nations", {}).has(nation_id) \
		or extracted.party.content.get("equipment_nations", {}).has(nation_id):
		return fail("WHOLE_NATION", "公共車隊只帶原 NPC／人貨；本原國家及其科技須留原 Source holder")
	var source_nation: Dictionary = extracted.origin.equipment_nations[nation_id]
	var order: Dictionary = source_nation.get("technology_operations", {}).get("public_orders", {}).get(order_id, {})
	if order != context.order or int(order.payload.driver_id) != int(route.driver_id): return fail("STALE_ORDER")
	var vehicle_id := str(order.payload.vehicle_id)
	var vehicle: Dictionary = extracted.party.content.vehicles.get(vehicle_id, {})
	if vehicle.is_empty() or int(vehicle.operator_id) != int(order.payload.driver_id) or int(vehicle.cargo.get("grain", 0)) < 4:
		return fail("NO_CARGO")
	order.payload.travel_token = token
	order.status = "active"
	order.revision = int(order.revision) + 1
	if not context.orders.valid_nation_operation_record(source_nation.technology_operations, extracted.origin.item_definitions, {}): return fail("INVALID")
	var identity: Dictionary = extracted.party.content.travel_identity
	var driver_ref: Dictionary = identity.refs.person.get(str(int(order.payload.driver_id)), {})
	var vehicle_ref: Dictionary = identity.refs.vehicle.get(vehicle_id, {})
	if driver_ref.is_empty() or vehicle_ref.is_empty(): return fail("CORRUPT_TRAVEL_IDENTITY")
	extracted.party.upkeep.owner_action_seconds = float(control.fire_clock.action_seconds)
	extracted.party.upkeep.original_deaths = {}
	for person: int in lab.site_controller._pending_deaths:
		if extracted.party.person_ids.has(person): extracted.party.upkeep.original_deaths[str(person)] = float(lab.site_controller._pending_deaths[person])
	var route_context := prepare_region_route_context(lab.terrain, extracted.party)
	if not route_context.ok: return route_context
	var verified := RegionRoute.verify_steps(source, route.steps, route_context.context)
	if not verified.ok: return verified
	var compiled := _region_npc_route_plan(token, route.steps, extracted.party)
	if not compiled.ok: return compiled
	var candidate := Env.navigation_for_state(lab.terrain, extracted.origin)
	candidate.set_meta(&"region_bind_source", lab.terrain)
	var binding: Dictionary = region_bind_candidate.call(lab, candidate, "live" if str(control.active_site_id) == str(candidate.site.id) else "cold_exact")
	if not binding.get("ok", false) and binding.has("code"): return binding # The bind preflight's own refusal, not a missing adapter.
	for hook: String in ["can_publish", "publish", "save_candidate"]:
		if not binding.get("ok", false) or not binding.get(hook) is Callable or not binding[hook].is_valid(): return fail("MISSING_REGION_ADAPTER")
	var coordinate := _coordinate(lab.terrain)
	if not coordinate.ok: return coordinate
	var receipt := {"kind": "nation_public_route", "source_site_id": str(lab.terrain.site.id), "scope_nation_id": nation_id,
		"order_id": order_id, "order_revision": int(order.revision), "route_ref": order.payload.route_ref.duplicate(true),
		"driver_id": int(order.payload.driver_id), "vehicle_id": vehicle_id,
		"person_reference": driver_ref.duplicate(true), "vehicle_reference": vehicle_ref.duplicate(true),
		"phase_token": paid.token.duplicate(true), "payment_id": str(paid.get("payment_id", ""))}
	return {"ok": true, "token": token, "generation": int(_marker.get("generation", 0)),
		"runtime_revision": int(region_registry().revision), "world": float(control.logical_game_seconds),
		"coordinate": coordinate.site, "lab": lab, "candidate": candidate, "party": extracted.party,
		"plan": compiled.plan, "binding": binding, "request": receipt, "vacated_housing": extracted.vacated_housing}


func _region_n08_local_reference(state: Dictionary, kind: String, reference: Dictionary) -> Dictionary:
	if reference.get("type") != kind: return fail("INVALID_IDENTITY")
	var wanted := RegionTravel.stable_key(reference)
	var local := ""
	for identity: String in state.get("travel_identity", {}).get("refs", {}).get(kind, {}):
		if RegionTravel.stable_key(state.travel_identity.refs[kind][identity]) != wanted: continue
		if not local.is_empty(): return fail("DUPLICATE_IDENTITY")
		local = identity
	return {"ok": true, "identity": local} if not local.is_empty() else fail("NO_ORIGINAL_BODY")


func _region_n08_map_player_arrival(next_control: Dictionary, party_token: String, destination: Dictionary) -> Dictionary:
	# P0 joins retain the SAME Source NPC token/order/typed body metadata in
	# registry.parties. A later real player arrival maps those original carriers.
	for token: String in next_control.region_gameplay.parties:
		var reference: Dictionary = next_control.region_gameplay.parties[token]
		var receipt: Dictionary = reference.get("transfer_receipt", {})
		if receipt.get("kind") != "nation_public_route" or reference.get("phase") != "joined" \
			or reference.get("entered_party") != party_token: continue
		var person := _region_n08_local_reference(destination, "person", receipt.get("person_reference", {}))
		var vehicle := _region_n08_local_reference(destination, "vehicle", receipt.get("vehicle_reference", {}))
		if not person.ok or not vehicle.ok: return fail("N08_BODY_CLOSURE", "原遇合馬車／操作人須一起真到站")
		reference.phase = "entered"
		reference.destination_site = str(destination.id)
		reference.arrival_game_seconds = float(next_control.logical_game_seconds)
		reference.nation_route_arrival = {"site_id": str(destination.id), "operator_id": int(person.identity),
			"vehicle_id": str(vehicle.identity), "person_reference": receipt.person_reference.duplicate(true),
			"vehicle_reference": receipt.vehicle_reference.duplicate(true), "party_token": party_token}
	return {"ok": true}


func _region_n08_entered_context(token: String) -> Dictionary:
	var reference: Dictionary = region_registry().parties.get(token, {})
	var receipt: Dictionary = reference.get("transfer_receipt", {})
	if receipt.get("kind") != "nation_public_route" or reference.get("phase") != "entered": return fail("NO_TARGET")
	if receipt.get("route_ref", {}).get("world_instance_id") != str(pin.world_instance_id) \
		or receipt.route_ref.get("slot_id") != str(pin.slot_id) or receipt.route_ref.get("source_site_id") != receipt.get("source_site_id"):
		return fail("WRONG_SLOT")
	if not region_owner_lab.is_valid(): return fail("MISSING_REGION_ADAPTER")
	var source_id := str(receipt.source_site_id)
	var source_owner: Dictionary = region_owner_lab.call(source_id, "live" if source_id == str(control.active_site_id) else "cold_exact")
	if not source_owner.get("ok", false) or not source_owner.get("lab") is TerrainLab: return fail("COMMITTED_UNBOUND")
	var source_lab: TerrainLab = source_owner.lab
	var nation: Dictionary = source_lab.terrain.site.get("equipment_nations", {}).get(str(receipt.scope_nation_id), {})
	var order: Dictionary = nation.get("technology_operations", {}).get("public_orders", {}).get(str(receipt.order_id), {})
	if order.is_empty() or order.get("tech_id") != "N08" or order.get("status") in ["complete", "revoked"] \
		or order.scope_site_id != source_id or order.scope_nation_id != receipt.scope_nation_id \
		or order.payload.travel_token != token or not order.payload.loaded or order.payload.route_ref != receipt.route_ref \
		or int(order.payload.driver_id) != int(receipt.driver_id) or str(order.payload.vehicle_id) != str(receipt.vehicle_id): return fail("STALE_ORDER")
	var original_ref: Dictionary = source_lab.terrain.site.get("travel_identity", {}).get("refs", {}).get("person", {}).get(str(int(receipt.driver_id)), {})
	if original_ref != receipt.person_reference: return fail("N08_BODY_CLOSURE")
	var authority := _region_n08_current_authority(source_lab, nation, int(order.authorizer_id))
	if not authority.ok: return authority
	var destination_id := str(reference.get("destination_site", ""))
	var destination_owner: Dictionary = region_owner_lab.call(destination_id, "live" if destination_id == str(control.active_site_id) else "cold_exact")
	if not destination_owner.get("ok", false) or not destination_owner.get("lab") is TerrainLab: return fail("COMMITTED_UNBOUND")
	var destination_lab: TerrainLab = destination_owner.lab
	var driver := _region_n08_local_reference(destination_lab.terrain.site, "person", receipt.person_reference)
	var vehicle := _region_n08_local_reference(destination_lab.terrain.site, "vehicle", receipt.vehicle_reference)
	if not driver.ok or not vehicle.ok: return fail("N08_BODY_CLOSURE")
	return {"ok": true, "token": token, "reference": reference, "transfer_receipt": receipt,
		"source_lab": source_lab, "destination_lab": destination_lab, "nation": nation, "order": order,
		"nation_id": str(receipt.scope_nation_id), "order_id": str(receipt.order_id),
		"driver_id": int(driver.identity), "vehicle_id": str(vehicle.identity)}


func _region_n08_completed_contact(token: String, site_id: String, component: int) -> bool:
	var reference: Dictionary = region_registry().parties.get(token, {})
	if reference.get("transfer_receipt", {}).get("kind") != "nation_public_route": return false
	var identity := "npc:%s:player-contact:%s:%d" % [token, site_id, component]
	for event: Dictionary in region_registry().events:
		if event.id == identity and event.kind == "player_encounter" and event.status == "complete" and event.player == true \
			and event.owner == site_id and event.payload.get("token") == token and int(event.payload.get("component", -1)) == component:
			return true
	return false


func _region_n08_resume_carrier(context: Dictionary) -> Dictionary:
	# The first real P0 materializes through the original player handler. Resume
	# only its already accepted original carrier, at its actual current position.
	var lab: TerrainLab = context.destination_lab
	var carrier := _region_n08_wagon(lab, str(context.vehicle_id), int(context.driver_id))
	if not carrier.ok: return carrier
	if not region_player_barrier().is_empty(): return fail("PLAYER_BARRIER")
	var captured: Dictionary = lab.site_controller.capture_region_checkpoint("region_barrier", false,
		{"civil_transport_resume": str(context.token)}, str(context.token))
	if not captured.ok: return captured
	var coordinate := _coordinate(lab.terrain)
	if not coordinate.ok: return coordinate
	var destination := _region_n08_known_destination(str(context.order.payload.destination_site_id))
	if not destination.ok: return destination
	var state: Dictionary = lab.terrain.site.duplicate(true)
	var fire := _capture_transfer_fire_snapshots(lab.terrain, state)
	if not fire.ok: return fire
	var spec := {"person_id": int(context.driver_id), "team_id": int(carrier.team.team_id), "actor_key": "",
		"mode": "land", "controller": "npc", "game_seconds": float(control.logical_game_seconds),
		"namespace": str(pin.world_instance_id) + ":" + Crypto.new().generate_random_bytes(16).hex_encode(),
		"family_transfer_guard": region_family_transfer_guard}
	var extracted := RegionTravel.extract(state, spec, str(context.token))
	if not extracted.ok: return extracted
	var driver_ref: Dictionary = extracted.party.content.travel_identity.refs.person.get(str(int(context.driver_id)), {})
	var vehicle_ref: Dictionary = extracted.party.content.travel_identity.refs.vehicle.get(str(context.vehicle_id), {})
	if driver_ref != context.transfer_receipt.person_reference or vehicle_ref != context.transfer_receipt.vehicle_reference:
		return fail("N08_BODY_CLOSURE")
	if extracted.party.content.get("equipment_nations", {}).has(str(context.nation_id)): return fail("WHOLE_NATION")
	extracted.party.upkeep.owner_action_seconds = float(control.fire_clock.action_seconds)
	extracted.party.upkeep.original_deaths = {}
	for identity: int in lab.site_controller._pending_deaths:
		if extracted.party.person_ids.has(identity): extracted.party.upkeep.original_deaths[str(identity)] = float(lab.site_controller._pending_deaths[identity])
	var route_context := prepare_region_route_context(lab.terrain, extracted.party)
	if not route_context.ok: return route_context
	var table := RegionRoute.table_from_terrain(lab.terrain, PackedByteArray(), true)
	if not table.get("ok", false): return table
	var component := RegionRoute.component_of(table, carrier.driver.cell)
	if component < 0: return fail("UNREACHABLE")
	var search := RegionRoute.Search.new()
	search.source = source; search.start_site = coordinate.site
	search.start_component = component; search.goal_site = destination.coordinate
	search.context = route_context.context
	var found: Dictionary = search.run()
	if not found.get("ok", false): return found
	var verified := RegionRoute.verify_steps(source, found.steps, route_context.context)
	if not verified.ok: return verified
	var compiled := _region_npc_route_plan(str(context.token), found.steps, extracted.party)
	if not compiled.ok: return compiled
	var candidate := Env.navigation_for_state(lab.terrain, extracted.origin)
	candidate.set_meta(&"region_bind_source", lab.terrain)
	var binding: Dictionary = region_bind_candidate.call(lab, candidate, "live" if str(control.active_site_id) == str(candidate.site.id) else "cold_exact")
	if not binding.get("ok", false) and binding.has("code"): return binding # The bind preflight's own refusal, not a missing adapter.
	for hook: String in ["can_publish", "publish", "save_candidate"]:
		if not binding.get("ok", false) or not binding.get(hook) is Callable or not binding[hook].is_valid(): return fail("MISSING_REGION_ADAPTER")
	return commit_npc_region_dispatch({"ok": true, "token": str(context.token), "generation": int(_marker.get("generation", 0)),
		"runtime_revision": int(region_registry().revision), "world": float(control.logical_game_seconds),
		"coordinate": coordinate.site, "lab": lab, "candidate": candidate, "party": extracted.party,
		"plan": compiled.plan, "plan_path": "travel/%s/plan_resume_%09d_%s.json" % [str(context.token), int(_marker.get("generation", 0)) + 1, Crypto.new().generate_random_bytes(8).hex_encode()],
		"binding": binding, "request": context.transfer_receipt.duplicate(true), "vacated_housing": extracted.vacated_housing})


func _region_n08_remount(lab: TerrainLab, vehicle_id: String, driver_id: int) -> Dictionary:
	var transport: Variant = lab.site_controller.vehicles
	var vehicle: Dictionary = transport.records().get(vehicle_id, {})
	if vehicle.is_empty() or str(vehicle.kind) != "wagon" or int(vehicle.operator_id) != 0: return fail("NO_DRIVER")
	var driver: Dictionary = transport._operator(driver_id)
	if driver.is_empty() or not driver.owner is TerrainArmy or int(driver.owner.team_id) != int(vehicle.team_id): return fail("NO_DRIVER")
	var team: TerrainArmy = driver.owner
	if team.moving_member_count() != 0 or team.get_active_move_plan() != null: return {"ok": true, "mounted": false, "moving": true}
	var boarded: Dictionary = transport.region_route_reboard(vehicle_id, driver_id)
	if boarded.ok: return {"ok": true, "mounted": true}
	if boarded.get("code") != "UNREACHABLE": return boarded
	# Walk to a legal cell beside the horse through the true team order; no cell write.
	var horse: Vector2i = transport.operator_cell(vehicle)
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var beside := horse + direction
		if not lab.terrain.contains(beside) or not lab.terrain.can_step(beside, horse) or beside == driver.cell: continue
		var moved: Dictionary = team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, beside)
		if moved.ok: return {"ok": true, "mounted": false, "moving": true}
	return fail("UNREACHABLE", "車伕無法走回馬格旁")

func _region_n08_last_mile(context: Dictionary) -> Dictionary:
	var lab: TerrainLab = context.destination_lab
	var carrier := _region_n08_wagon(lab, str(context.vehicle_id), int(context.driver_id))
	if not carrier.ok and carrier.get("code") == "NO_DRIVER":
		# Arrival parks the wagon without an operator. The named driver walks back
		# to the horse cell and remounts through the original operator step.
		var remount := _region_n08_remount(lab, str(context.vehicle_id), int(context.driver_id))
		if not remount.ok or not bool(remount.get("mounted", false)): return remount
		carrier = _region_n08_wagon(lab, str(context.vehicle_id), int(context.driver_id))
	if not carrier.ok: return carrier
	var holder := str(context.order.payload.destination_holder)
	var stock: Dictionary = carrier.transport._stock(holder, true)
	if stock.is_empty() or lab.terrain.site.features.get(str(stock.get("feature_id", "")), {}).get("kind") != "warehouse": return fail("NO_WAREHOUSE")
	if bool(stock.get("withdraw_only", true)) or int(stock.faction) != int(carrier.team.faction_id): return fail("NO_AUTHORITY")
	if Runtime.carried_load(lab.terrain.site, stock.cargo, stock.holder) + 4 > int(stock.capacity): return fail("STORAGE_FULL")
	var ticket := _region_n08_transfer_permit(context.source_lab, context, lab, str(context.vehicle_id), int(context.driver_id), str(context.vehicle_id), holder)
	if not ticket.ok: return ticket
	var transfer: Dictionary = carrier.transport.prepare_nation_route_transfer(ticket.permit)
	discard_nation_route_transfer_permit(ticket.permit)
	if transfer.ok: return {"ok": true, "at_holder": true}
	if transfer.get("code") != "UNREACHABLE": return transfer
	# The true original commander/formation/reservation/vehicle step consumes
	# this movement. No distance counter, timer or direct cell write can finish it.
	var moved: Dictionary = carrier.team.issue_combat_order(carrier.team.current_commander,
		TerrainArmy.CombatOrder.MOVE, stock.cell)
	if not moved.ok: return moved
	return {"ok": true, "at_holder": false, "moving": true}


func _region_n08_research_candidate(context: Dictionary, candidate_nation: Dictionary, event_id: String) -> Dictionary:
	var technology: GDScript = load("res://scripts/terrain_lab/site_technology.gd")
	var token: Dictionary = context.transfer_receipt.get("phase_token", {})
	if token.is_empty():
		return {"ok": true} if technology.scope_known(candidate_nation.get("technology", {}), "N08") else fail("STALE_PROJECT")
	var paid := _region_n08_paid_token(context.source_lab, str(context.nation_id), str(context.order_id), context.order)
	if not paid.ok or paid.token != token or str(paid.get("payment_id", "")) != str(context.transfer_receipt.get("payment_id", "")):
		return paid if not paid.ok else fail("STALE_PROJECT")
	var source_ref: Dictionary = context.source_lab.terrain.site.get("travel_identity", {}).get("refs", {}).get("person", {}).get(str(int(token.person.person_id)), {})
	if str(token.person.site_id) != str(context.order.scope_site_id) or int(token.person.person_id) != int(context.order.payload.driver_id) \
		or source_ref != context.transfer_receipt.person_reference: return fail("N08_BODY_CLOSURE")
	# Research keeps its Source historical Scope PersonRef. The immutable real
	# Region work event separately records the Destination body, resolved above
	# by the injective original typed PersonRef; the two numeric ids are not equated.
	var receipt := {"site_id": str(token.person.site_id), "person_id": int(token.person.person_id),
		"attempt": int(token.attempt), "phase_id": str(token.phase_id), "event_id": event_id,
		"work_seconds": 0.0, "payment_id": str(paid.payment_id)}
	var researched: Dictionary = technology.scope_receipt_candidate(candidate_nation.technology, "nation", receipt)
	if not researched.ok or not researched.get("complete", false): return researched if not researched.ok else fail("INCOMPLETE")
	candidate_nation.technology = researched.state
	return {"ok": true}


func _region_n08_publish_delivery(token: String) -> Dictionary:
	# As the NPC dispatch and arrival do: a Source or Destination whose selected
	# publication lags this frame is published at this same point first (no clock
	# moves); the bind preflight below requires that exact published frame.
	var lagging := _region_n08_entered_context(token)
	if not lagging.ok: return lagging
	for owner_lab: TerrainLab in [lagging.source_lab, lagging.destination_lab]:
		var source_check: Dictionary = owner_lab._region_selected_bind_source(owner_lab.terrain, self)
		if source_check.ok or str(source_check.get("code", "")) not in ["STALE_REGION_CONTEXT", "STALE_REGION_SOURCE_OWNERS", "STALE_REGION_SOURCE_BODY"]: continue
		if not region_original_endpoint_checkpoint.is_valid(): return fail("MISSING_REGION_ADAPTER", "缺含原活動 Lab 的共同端點 checkpoint")
		var clocks := [float(control.logical_game_seconds), float(control.fire_clock.action_seconds), int(control.fire_clock.sequence)]
		var published: Variant = region_original_endpoint_checkpoint.call({"region_source_publish": "civil_delivery", "token": token})
		if not published is Dictionary or not published.get("ok", false): return published if published is Dictionary else fail("INVALID_REGION_RECEIPT")
		if clocks != [float(control.logical_game_seconds), float(control.fire_clock.action_seconds), int(control.fire_clock.sequence)]: return fail("CLOCK_CONTRACT", "交貨前發布不得推進時鐘")
		break # One joint publication covers every original owner.
	var generation := int(_marker.get("generation", 0)) + 1
	var next_control := control.duplicate(true)
	var sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	# Preserve every other original cold owner in this same generation. Capture
	# first, before preparing graph tickets or retaining a physical transfer.
	var cold := _collect_cold_checkpoint(generation, sites, next_control)
	if not cold.ok: return cold
	var context := _region_n08_entered_context(token)
	if not context.ok: return context
	var source_lab: TerrainLab = context.source_lab
	var destination_lab: TerrainLab = context.destination_lab
	if str(destination_lab.terrain.site.id) != str(context.order.payload.destination_site_id): return fail("WRONG_SITE")
	var ticket := _region_n08_transfer_permit(source_lab, context, destination_lab,
		str(context.vehicle_id), int(context.driver_id), str(context.vehicle_id), str(context.order.payload.destination_holder))
	if not ticket.ok: return ticket
	var actual: Dictionary = destination_lab.site_controller.vehicles.prepare_nation_route_transfer(ticket.permit)
	if not actual.ok: discard_nation_route_transfer_permit(ticket.permit); return actual
	# The collector already captures every cold original, including the true
	# last-mile destination. Active Source also captures its current full graph
	# through the same Controller before cloning; its head may have moved.
	var source_capture: Dictionary = source_lab.site_controller.capture_region_checkpoint("region_checkpoint", true)
	if not source_capture.ok: discard_nation_route_transfer_permit(ticket.permit); return source_capture
	var source_state: Dictionary = source_lab.terrain.site.duplicate(true)
	var destination_state: Dictionary = destination_lab.terrain.site.duplicate(true)
	var source_fire := _capture_transfer_fire_snapshots(source_lab.terrain, source_state)
	var destination_fire := _capture_transfer_fire_snapshots(destination_lab.terrain, destination_state)
	if not source_fire.ok or not destination_fire.ok:
		discard_nation_route_transfer_permit(ticket.permit)
		return source_fire if not source_fire.ok else destination_fire
	var destination_candidate := Env.navigation_for_state(destination_lab.terrain, destination_state)
	var wagon: Dictionary = destination_state.vehicles.get(str(context.vehicle_id), {})
	var stocks: GDScript = load("res://scripts/terrain_lab/site_stockpiles.gd")
	var warehouse: Dictionary = stocks.stock_endpoint(destination_candidate, str(context.order.payload.destination_holder).trim_prefix("feature:"))
	if wagon.is_empty() or warehouse.is_empty(): discard_nation_route_transfer_permit(ticket.permit); return fail("NO_TARGET")
	var transfer := Runtime.prepare_item_transfer(destination_candidate, wagon.holder, wagon.cargo, warehouse.holder, warehouse.cargo,
		{"grain": 4}, [], int(actual.source_version), int(actual.destination_version), int(warehouse.capacity))
	if not transfer.ok: discard_nation_route_transfer_permit(ticket.permit); return transfer
	# Publication below affects only the detached ORIGINAL candidate. Live cargo
	# remains unchanged until BOTH full Site payloads and the sole marker commit.
	var moved := Runtime.publish_item_transfer(transfer)
	var source_nation: Dictionary = source_state.equipment_nations[str(context.nation_id)]
	var operations: Dictionary = source_nation.technology_operations
	var order: Dictionary = operations.public_orders[str(context.order_id)]
	var event_id: String = context.source_lab.site_controller.equipment_orders._public_event_id(context.order, str(context.order_id), "public_route", token)
	if not order.receipts.is_empty(): discard_nation_route_transfer_permit(ticket.permit); return fail("REPLAY")
	order.receipts.append({"id": event_id, "site_id": str(destination_state.id), "binding": "public_route",
		"operator_id": int(context.driver_id), "source_operator_id": int(context.order.payload.driver_id),
		"operator_reference": context.transfer_receipt.person_reference.duplicate(true), "transfer_token": token,
		"target_id": str(order.payload.destination_holder), "work_seconds": 0.0, "item_ids": []})
	order.status = "complete"
	order.revision = int(order.revision) + 1
	var researched := _region_n08_research_candidate(context, source_nation, event_id)
	if not researched.ok: discard_nation_route_transfer_permit(ticket.permit); return researched
	var source_candidate := Env.navigation_for_state(source_lab.terrain, source_state)
	source_candidate.set_meta(&"region_bind_source", source_lab.terrain)
	destination_candidate.set_meta(&"region_bind_source", destination_lab.terrain)
	var bindings: Array[Dictionary] = []
	for pair: Array in [[source_lab, source_candidate], [destination_lab, destination_candidate]]:
		var lab: TerrainLab = pair[0]
		var candidate: TerrainData = pair[1]
		var binding: Dictionary = region_bind_candidate.call(lab, candidate, "live" if str(candidate.site.id) == str(control.active_site_id) else "cold_exact")
		if not binding.get("ok", false): discard_nation_route_transfer_permit(ticket.permit); return _region_family_discard_bindings(bindings, binding)
		bindings.append(binding)
		for hook: String in ["data", "can_publish", "save_candidate", "publish", "discard"]:
			if not binding.has(hook): discard_nation_route_transfer_permit(ticket.permit); return _region_family_discard_bindings(bindings, fail("MISSING_REGION_ADAPTER"))
	var data_candidates: Array[TerrainData] = []
	for binding: Dictionary in bindings:
		var coordinate := _coordinate(binding.data)
		if not coordinate.ok: discard_nation_route_transfer_permit(ticket.permit); return _region_family_discard_bindings(bindings, coordinate)
		var path := _generation_path(generation, coordinate.site)
		var saved: Dictionary = binding.save_candidate.call(binding.data, path)
		if not saved.ok: discard_nation_route_transfer_permit(ticket.permit); return _region_family_discard_bindings(bindings, saved)
		var checked := _load_checked(path, coordinate.site)
		if not checked.ok: discard_nation_route_transfer_permit(ticket.permit); return _region_family_discard_bindings(bindings, checked)
		data_candidates.append(checked.data)
		sites[_site_key(coordinate.site)] = _file_entry(path)
	var payload := {"kind": "nation_public_route_delivery", "token": token, "world_instance_id": str(pin.world_instance_id), "slot_id": str(pin.slot_id),
		"source_site_id": str(source_state.id), "destination_site_id": str(destination_state.id), "nation_id": str(context.nation_id), "order_id": str(context.order_id),
		"route_ref": context.order.payload.route_ref.duplicate(true), "source_driver_id": int(context.order.payload.driver_id), "operator_id": int(context.driver_id),
		"person_reference": context.transfer_receipt.person_reference.duplicate(true), "vehicle_reference": context.transfer_receipt.vehicle_reference.duplicate(true),
		"vehicle_id": str(context.vehicle_id), "destination_holder": str(context.order.payload.destination_holder), "resources": {"grain": 4},
		"source_version": int(actual.source_version), "destination_version": int(actual.destination_version),
		"published_source_version": int(moved.source_version), "published_destination_version": int(moved.destination_version),
		"phase_token": context.transfer_receipt.phase_token.duplicate(true), "payment_id": str(context.transfer_receipt.payment_id), "generation": generation}
	var queued := GameplayClock.queue_event(next_control.region_gameplay, event_id, "work", float(control.logical_game_seconds), str(destination_state.id), payload)
	if not queued.ok or queued.get("duplicate", false): discard_nation_route_transfer_permit(ticket.permit); return _region_family_discard_bindings(bindings, queued if not queued.ok else fail("REPLAY"))
	var completed := GameplayClock.complete_event(next_control.region_gameplay, event_id, float(control.logical_game_seconds))
	if not completed.ok: discard_nation_route_transfer_permit(ticket.permit); return _region_family_discard_bindings(bindings, completed)
	var reference: Dictionary = next_control.region_gameplay.parties[token]
	reference.nation_delivery_event = event_id
	next_control.region_gameplay.revision = int(next_control.region_gameplay.revision) + 1
	for lab: TerrainLab in [source_lab, destination_lab]:
		var owner := str(lab.terrain.site.id)
		var activation := GameplayClock.activate_mode(next_control.region_gameplay, owner, "committed-unbound", generation,
			"gd", "original_site", float(control.logical_game_seconds), float(control.fire_clock.action_seconds), {})
		if not activation.ok: discard_nation_route_transfer_permit(ticket.permit); return _region_family_discard_bindings(bindings, activation)
	var parties := collect_region_party_checkpoint(generation, next_control)
	if not parties.ok: discard_nation_route_transfer_permit(ticket.permit); return _region_family_discard_bindings(bindings, parties)
	var admitted := validate_nation_route_transfer_permit(destination_lab.site_controller.vehicles, ticket.permit,
		str(context.vehicle_id), str(context.order.payload.destination_holder), {"grain": 4}, [], int(context.driver_id))
	var stable := Runtime.validate_prepared_item_transfer(actual)
	if not admitted.ok or not stable.ok:
		discard_nation_route_transfer_permit(ticket.permit)
		return _region_family_discard_bindings(bindings, admitted if not admitted.ok else stable)
	for binding: Dictionary in bindings:
		if binding.can_publish.call() != true: discard_nation_route_transfer_permit(ticket.permit); return _region_family_discard_bindings(bindings, fail("STALE_REGION_BIND_TICKET"))
	var published := _publish(sites, next_control, str(_marker.get("transfer_token", "")), _marker.get("journey", {}))
	discard_nation_route_transfer_permit(ticket.permit)
	if not published.ok: return _region_family_discard_bindings(bindings, published)
	# Marker owns all material, body, research and receipt effects once. Bind
	# faults can only restore selected complete payloads; they never rerun unload.
	for index: int in bindings.size():
		var binding: Dictionary = bindings[index]
		var bound: Dictionary = binding.publish.call(data_candidates[index])
		if not bound.get("ok", false) or bound.get("complete") != true:
			var fault := fail("COMMITTED_UNBOUND", "本四糧與Scope同marker已提交；只允原完整bind恢復")
			source_lab.site_controller.latch_original_step_fault(fault)
			destination_lab.site_controller.latch_original_step_fault(fault)
			return fault
		var mode := "live" if str(data_candidates[index].site.id) == str(control.active_site_id) else "cold_exact"
		var activated := activate_region_mode(str(data_candidates[index].site.id), mode, "original_site" if mode == "live" else "original_replay", bound, str(bound.get("backend", "gd")))
		if not activated.ok: return activated
	return {"ok": true, "complete": true, "event_id": event_id, "token": token, "generation": int(published.generation)}


func region_nation_route_receipt(lab: TerrainLab, target_id: String, event_id: String) -> Dictionary:
	if lab == null or lab.site_controller == null or lab.site_controller.region_slot != self: return fail("WRONG_SLOT")
	for event: Dictionary in region_registry().events:
		if event.id != event_id or event.kind != "work" or event.status != "complete": continue
		var payload: Dictionary = event.payload
		if payload.get("kind") != "nation_public_route_delivery" or payload.get("source_site_id") != str(lab.terrain.site.id) \
			or payload.get("world_instance_id") != str(pin.world_instance_id) or payload.get("slot_id") != str(pin.slot_id) \
			or payload.get("destination_holder") != target_id or payload.get("resources") != {"grain": 4}: return fail("INVALID_RECEIPT")
		var order: Dictionary = lab.terrain.site.get("equipment_nations", {}).get(str(payload.nation_id), {}).get("technology_operations", {}).get("public_orders", {}).get(str(payload.order_id), {})
		var reference: Dictionary = region_registry().parties.get(str(payload.token), {})
		if order.get("status") != "complete" or reference.get("nation_delivery_event") != event_id \
			or order.get("payload", {}).get("travel_token") != payload.token or order.payload.route_ref != payload.route_ref \
			or int(order.payload.driver_id) != int(payload.source_driver_id) or order.payload.destination_site_id != payload.destination_site_id \
			or lab.terrain.site.get("travel_identity", {}).get("refs", {}).get("person", {}).get(str(int(payload.source_driver_id)), {}) != payload.person_reference:
			return fail("INVALID_RECEIPT")
		for receipt: Dictionary in order.receipts:
			if receipt.id != event_id: continue
			if receipt.site_id != payload.destination_site_id or int(receipt.operator_id) != int(payload.operator_id) \
				or receipt.operator_reference != payload.person_reference or receipt.transfer_token != payload.token: return fail("INVALID_RECEIPT")
			return {"ok": true, "receipt": receipt.duplicate(true), "token": payload.phase_token.duplicate(true),
				"physical_event": event.duplicate(true), "source_person": {"site_id": str(payload.source_site_id), "person_id": int(payload.source_driver_id)}}
	return fail("NO_TARGET")


func _region_n08_consume_entered() -> Dictionary:
	var held: Array[Dictionary] = []
	var tokens: Array = region_registry().parties.keys()
	tokens.sort()
	for token: String in tokens:
		var reference: Dictionary = region_registry().parties.get(token, {})
		if reference.get("transfer_receipt", {}).get("kind") != "nation_public_route" or reference.get("phase") != "entered" \
			or not str(reference.get("nation_delivery_event", "")).is_empty(): continue
		var context := _region_n08_entered_context(token)
		if not context.ok:
			if context.get("code") == "COMMITTED_UNBOUND": return context
			held.append({"token": token, "code": str(context.get("code", "INVALID"))})
			continue
		if str(context.destination_lab.terrain.site.id) != str(context.order.payload.destination_site_id):
			var resumed := _region_n08_resume_carrier(context)
			if not resumed.ok:
				if resumed.get("code") == "COMMITTED_UNBOUND": return resumed
				held.append({"token": token, "code": str(resumed.get("code", "INVALID"))})
			continue
		var contact := _region_n08_last_mile(context)
		if not contact.ok:
			held.append({"token": token, "code": str(contact.get("code", "INVALID"))})
			continue
		if not contact.get("at_holder", false): continue
		var delivered := _region_n08_publish_delivery(token)
		if not delivered.ok:
			if delivered.get("code") == "COMMITTED_UNBOUND": return delivered
			held.append({"token": token, "code": str(delivered.get("code", "INVALID"))})
	return {"ok": true, "complete": true, "held": held}


## Called only after original point consumers. One existing Battle registry
## entry references the whole original siege; every body/work/action stays in
## the same complete Site graph and common checkpoint publication.


func admit_original_region_contact_battle(original: TerrainLab) -> Dictionary:
	if not is_instance_valid(original) or original.terrain == null or original.site_controller == null or original.site_controller.region_slot != self:
		return fail("MISSING_ORIGINAL_BATTLE_OWNER")
	var owner := str(original.terrain.site.get("id", ""))
	if owner.is_empty() or _region_original_labs.get(owner) != original or original._region_bound_data != original.terrain or not original.restore_only:
		return fail("STALE_ORIGINAL_BATTLE_OWNER")
	if owner == str(control.active_site_id) or not region_player_barrier().is_empty():
		return {"ok": true, "admitted": false, "reason": "PLAYER_BARRIER"}
	var mode: Dictionary = region_registry().modes.get(owner, {})
	if str(mode.get("mode", "")) != "cold_exact": return {"ok": true, "admitted": false, "reason": "OTHER_ORIGINAL_CONSUMER"}
	if str(mode.get("backend", "")) != original.region_backend_expected():
		return {"ok": true, "admitted": false, "reason": "EXACT_BACKEND_UNADMITTED"}
	if original.get_tree().paused or bool(original.terrain.site.get("paused", false)):
		return {"ok": true, "admitted": false, "reason": "PAUSED_ORIGINAL"}
	if not original._region_point_pending.is_empty() or not original._region_point_contacts.is_empty() or not original._region_point_wakes.is_empty() or original._region_point_consuming or original._region_point_dispatching or not original._combat_contacts.is_empty() or not original.terrain.get_meta(&"fire_boundary", {}).is_empty():
		return {"ok": true, "admitted": false, "reason": "ORIGINAL_EFFECTS_PENDING"}
	# Siege and Fire continue through their original exact owners until their
	# own calibrated admission exists. An ordinary label cannot open that gate.
	if original._siege_tactical_active() or original._fire_activity():
		return {"ok": true, "admitted": false, "reason": "EXACT_SIEGE_FIRE_OWNER"}
	var bind: Dictionary = original.region_bind_receipt(original.terrain)
	if bind.get("ok") != true or bind.get("complete") != true or bind.get("owners_restored") != true or str(bind.get("backend", "")) != original.region_backend_expected() or int(bind.get("generation", -1)) != int(_marker.get("generation", 0)):
		return fail("COMMITTED_UNBOUND")
	var world := float(control.logical_game_seconds)
	var action := float(control.fire_clock.action_seconds)
	var settled := validate_settlement(original.terrain.site, world)
	var fire: Dictionary = original.terrain.site.get("fire_settlement", {})
	if not settled.ok or settled.legacy or float(settled.pending) > 0.00000001 or fire.get("epoch") != control.fire_clock.epoch or int(fire.get("sequence", -1)) != int(control.fire_clock.sequence) or absf(float(fire.get("game_seconds", -1.0)) - world) > 0.00000001 or absf(float(fire.get("action_seconds", -1.0)) - action) > 0.00000001 or absf(original.fire_action_cursor - action) > 0.00000001 or int(mode.get("generation", -1)) != int(_marker.generation) or absf(float(mode.get("game_seconds", -1.0)) - world) > 0.00000001 or absf(float(mode.get("action_seconds", -1.0)) - action) > 0.00000001:
		return fail("INCOMPLETE_ORIGINAL_BATTLE_POINT")
	for existing: Dictionary in region_registry().battles.values():
		if str(existing.get("site_id", "")) == owner and str(existing.get("phase", "")) != "finished":
			return {"ok": true, "admitted": false, "reason": "EXISTING_ORIGINAL_BATTLE", "battle_id": str(existing.id)}
	var factions: Dictionary = {}
	var participants: Dictionary = {}
	var control_scope := RegionBattle.scoped_controlled_person(original)
	if not control_scope.get("ok", false): return control_scope
	var controlled := int(control_scope.person_id)
	for actor: TerrainTestCharacter in original.combat_actors:
		if not is_instance_valid(actor) or not original.actor_present(actor) or actor.person_id == controlled or actor.site_exited: continue
		if actor.person_id <= 0 or participants.has(actor.person_id): return fail("INVALID_ORIGINAL_BATTLE_ROSTER")
		participants[actor.person_id] = actor.faction_id
	for team: TerrainArmy in original.combat_armies:
		if not team.combat_enabled: continue
		for index: int in team.combat_units.size():
			var identity := team.combat_identity(index)
			if identity == controlled or bool(team.combat_hot_get(index, &"departed")) or bool(team.combat_hot_get(index, &"site_exited", false)): continue
			if identity <= 0 or participants.has(identity) or original._original_person_target(identity).is_empty(): return fail("INVALID_ORIGINAL_BATTLE_ROSTER")
			participants[identity] = team.faction_id
	for identity: int in participants:
		var faction := int(participants[identity])
		if faction < 0: return {"ok": true, "admitted": false, "reason": "EXACT_UNKNOWN_FACTION"}
		if not factions.has(faction): factions[faction] = []
		factions[faction].append(identity)
	if factions.size() != 2:
		return {"ok": true, "admitted": false, "reason": "EXACT_FACTION_TOPOLOGY", "faction_count": factions.size()}
	var faction_ids: Array = factions.keys()
	faction_ids.sort()
	for ids: Array in factions.values(): ids.sort()
	var identifier := "contact:%s:%d" % [owner, int(control.fire_clock.sequence)]
	if region_registry().battles.has(identifier): return fail("ORIGINAL_BATTLE_ID_CONFLICT")
	var made := RegionBattle.create({"id": identifier, "site_id": owner, "attackers": factions[faction_ids[0]],
		"defenders": factions[faction_ids[1]], "game_time": world,
		"rng_state": int(hash(str(pin.world_instance_id) + ":" + identifier))})
	if not made.ok: return made
	var resolved := RegionBattle.resolve_people(original, made.battle)
	if not resolved.ok: return resolved
	var actual_contacts: Array[Dictionary] = []
	for identity: int in resolved.people:
		var person: Dictionary = resolved.people[identity]
		for target: int in person.get("legal_targets", []):
			if not participants.has(target) or int(participants[target]) == int(participants[identity]): return fail("INVALID_ORIGINAL_BATTLE_CONTACT")
			actual_contacts.append({"source": identity, "target": target, "source_cell": person.contact_cell.duplicate(), "target_cell": resolved.people[target].contact_cell.duplicate()})
	if actual_contacts.is_empty(): return {"ok": true, "admitted": false, "reason": "NO_ORIGINAL_CONTACT"}
	var candidate: Dictionary = region_registry().duplicate(true)
	candidate.battles[identifier] = made.battle
	var activation: Dictionary = bind.duplicate(true)
	activation.mode = "formula_active"
	activation.consumer = "original_formula_site"
	var activated := GameplayClock.activate_mode(candidate, owner, "formula_active", int(_marker.generation), str(bind.backend), "original_formula_site", world, action, activation)
	if not activated.ok: return activated
	candidate.revision = int(candidate.revision) + 1
	var valid := GameplayClock.validate_registry(candidate, world)
	if not valid.ok: return valid
	# Retain this original registry object, including a consumer's live alias.
	# Its next common checkpoint publishes the exact body and metadata together.
	var registry: Dictionary = region_registry()
	registry.clear()
	registry.merge(candidate, true)
	return {"ok": true, "admitted": true, "battle_id": identifier, "battle": registry.battles[identifier],
		"original_participants": participants, "actual_contacts": actual_contacts,
		"game_seconds": world, "action_seconds": action, "generation": int(_marker.generation)}


func _region_first_player_siege_contact(to: float, interval: Dictionary = {}) -> Dictionary:
	var battle_ids: Array = []
	for id: String in region_registry().battles:
		var battle: Dictionary = region_registry().battles[id]
		if str(battle.get("kind", "")) == "siege" and str(battle.get("phase", "")) != "finished": battle_ids.append(id)
	if battle_ids.is_empty(): return {"ok": true, "contact": false}
	battle_ids.sort()
	var status: Dictionary = region_travel_status()
	if not status.ok: return status
	if not status.get("pending", false) or not status.get("moving", false) or str(status.get("mode", "land")) != "land": return {"ok": true, "contact": false}
	var selected: Dictionary = region_travel_party()
	if not selected.ok: return selected
	var party: Dictionary = selected.party
	if not has_method("region_original_party_runtime_proof"): return fail("MISSING_ORIGINAL_PARTY_PROOF")
	var raw_proof: Variant = call("region_original_party_runtime_proof", str(status.token), party)
	if not raw_proof is Dictionary or not raw_proof.get("ok", false) or not raw_proof.get("lab") is TerrainLab:
		return raw_proof if raw_proof is Dictionary else fail("INVALID_ORIGINAL_PARTY_PROOF")
	for accepted: Dictionary in region_registry().events:
		if accepted.get("status") != "pending" or accepted.get("kind") != "player_encounter" or accepted.get("payload", {}).get("player_token") != str(status.token) 			or accepted.get("payload", {}).get("contact_receipt", {}).get("kind") != "siege_channel": continue
		var lineage: Dictionary = _region_accepted_siege_lineage(accepted, status, party, raw_proof.proof)
		if not lineage.ok: return lineage
		if float(accepted.at) > to: return {"ok": true, "contact": false}
		var saved: Dictionary = accepted.payload
		return {"ok": true, "contact": true, "at": float(accepted.at), "site": saved.site.duplicate(), "component": int(saved.component),
			"route_component": int(saved.contact_receipt.second.position.get("route_component", saved.component)), "site_id": str(accepted.owner),
			"battle_id": str(saved.battle_id), "contact_receipt": saved.contact_receipt.duplicate(true), "accepted_event": accepted.duplicate(true)}
	var party_lab: TerrainLab = raw_proof.lab
	var traveller: Dictionary = party_lab.site_controller.person_actions._person(int(party.leader_person_id), false)
	if traveller.is_empty(): return fail("INVALID_ORIGINAL_SIEGE_TRAVELLER")
	var prepared: Dictionary = prepare_region_route_context(null, party)
	if not prepared.ok: return prepared
	var cache := {}
	var idle := {"site": [status.site.x, status.site.y], "component": int(status.component), "step_index": 0}
	var points: Dictionary = _region_contact_land_points(party, status.plan, to, true, idle, prepared.context, cache)
	if not points.ok: return points
	for point: Dictionary in points.points:
		var location: Dictionary = point.position
		var site := Vector2i(int(location.site[0]), int(location.site[1]))
		var owner := Grid.site_id(str(pin.atlas_id), site)
		var entry := Vector2i(int(location.cell[0]), int(location.cell[1]))
		if entry.x < 0 or entry.y < 0: continue
		for id: String in battle_ids:
			var battle: Dictionary = region_registry().battles[id]
			if str(battle.get("kind", "")) != "siege" or str(battle.get("site_id", "")) != owner or str(battle.get("phase", "")) == "finished": continue
			var original: TerrainLab = _region_original_labs.get(owner)
			if not is_instance_valid(original) or _region_bound_original_lab(original.terrain) != original: return fail("COMMITTED_UNBOUND")
			if not original.terrain.contains(entry): continue
			for identity: Variant in battle.attackers + battle.defenders:
				var person: Dictionary = original.site_controller.person_actions._person(int(identity), false)
				if person.is_empty() or int(person.faction) == int(traveller.faction) or not SiteSettlement._fit(person) or bool(person.moving) \
					or SiteSettlement._role(person) == "civilian" or original.site_controller.vehicles.is_siege_crew(int(identity)): continue
				var body_owner: Variant = person.owner
				var unit := int(person.unit)
				var ready: bool = body_owner.exchange_ready(unit) if body_owner is TerrainArmy else body_owner.exchange_ready()
				var gap: Vector2i = entry - Vector2i(person.cell)
				if not ready or absi(gap.x) + absi(gap.y) != 1 or not original.terrain.can_attack_across(person.cell, entry): continue
				if original.site_controller.vehicles.blocks_person_step(int(identity), person.cell, person.cell, entry, entry): continue
				var cell: Vector2i = person.cell
				var witness := {"battle_id": id, "source_generation": int(_marker.generation), "runtime_revision": int(region_registry().revision),
					"navigation_revision": int(original.terrain.navigation_revision), "person_id": int(identity), "person_cell": [cell.x, cell.y],
					"entry": [entry.x, entry.y], "party_token": str(status.token), "party_source": raw_proof.get("proof", {}).duplicate(true),
					"game_seconds": float(control.logical_game_seconds), "action_seconds": float(control.fire_clock.action_seconds), "legal_ground_melee": true}
				var contact := {"kind": "siege_channel", "at": float(point.at),
					"first": {"at": float(point.at), "position": {"site": location.site.duplicate(), "component": int(location.component), "cell": [cell.x, cell.y], "mode": "land"}},
					"second": point.duplicate(true), "witness": witness}
				return {"ok": true, "contact": true, "at": float(point.at), "site": location.site.duplicate(),
					"component": int(location.route_component), "site_id": owner, "battle_id": id, "contact_receipt": contact}
	return {"ok": true, "contact": false}

## Re-read the accepted ORIGINAL point before the existing materializer. The
## preview witness never overrides a body that moved, died, or lost its legal
## channel while the common interval was paid. A stale contact is an original
## no-effect event; any true arrival still follows its own existing queue.


func _region_validate_player_siege_contact(event: Dictionary) -> Dictionary:
	var contact: Dictionary = event.get("payload", {}).get("contact_receipt", {})
	if str(contact.get("kind", "")) != "siege_channel": return {"ok": true, "valid": true}
	var witness: Variant = contact.get("witness")
	if not witness is Dictionary or not witness.get("person_cell") is Array or witness.person_cell.size() != 2 \
		or not witness.get("entry") is Array or witness.entry.size() != 2 or str(witness.get("battle_id", "")) != str(event.get("payload", {}).get("battle_id", "")):
		return fail("INVALID_SIEGE_CONTACT")
	var battle: Dictionary = region_registry().battles.get(str(witness.battle_id), {})
	if battle.is_empty() or str(battle.get("kind", "")) != "siege" or str(battle.get("phase", "")) == "finished": return {"ok": true, "valid": false, "reason": "SIEGE_CHANNEL_ENDED"}
	var owner := str(battle.site_id)
	var original: TerrainLab = _region_original_labs.get(owner)
	# A Slot reopened by the visible world-open owns its active Site through the
	# bound main lab (as the family transition target resolves it), not a cached cold entry.
	if not is_instance_valid(original) and owner == str(control.active_site_id) and region_owner_lab.is_valid():
		var main_owner: Object = region_owner_lab.get_object()
		if main_owner is TerrainLab and main_owner.terrain != null and str(main_owner.terrain.site.id) == owner: original = main_owner
	if not is_instance_valid(original) or _region_bound_original_lab(original.terrain) != original: return fail("COMMITTED_UNBOUND")
	var bind: Dictionary = original.region_bind_receipt(original.terrain)
	if bind.get("complete") != true or bind.get("owners_restored") != true: return fail("COMMITTED_UNBOUND")
	# A retry after the actual joint publication belongs to its genuine live
	# owner; the existing materializer owns its immutable idempotent receipt.
	if str(control.active_site_id) == owner and str(battle.get("mode", "")) == "live": return {"ok": true, "valid": true}
	var status: Dictionary = region_travel_status()
	if not status.ok: return status
	if not status.get("pending", false) or str(status.get("token", "")) != str(witness.get("party_token", "")): return {"ok": true, "valid": false, "reason": "PLAYER_ROUTE_CHANGED"}
	var selected: Dictionary = region_travel_party()
	if not selected.ok: return selected
	var party: Dictionary = selected.party
	if not has_method("region_original_party_runtime_proof"): return fail("MISSING_ORIGINAL_PARTY_PROOF")
	var raw_proof: Variant = call("region_original_party_runtime_proof", str(status.token), party)
	if not raw_proof is Dictionary or not raw_proof.get("ok", false) or not raw_proof.get("lab") is TerrainLab: return raw_proof if raw_proof is Dictionary else fail("INVALID_ORIGINAL_PARTY_PROOF")
	var party_lab: TerrainLab = raw_proof.lab
	var traveller: Dictionary = party_lab.site_controller.person_actions._person(int(party.leader_person_id), false)
	var identity := int(witness.get("person_id", -1))
	if not (battle.attackers + battle.defenders).has(identity): return {"ok": true, "valid": false, "reason": "SIEGE_ROSTER_CHANGED"}
	var person: Dictionary = original.site_controller.person_actions._person(identity, false)
	if traveller.is_empty() or person.is_empty() or int(person.faction) == int(traveller.faction) or not SiteSettlement._fit(person) or bool(person.moving) \
		or SiteSettlement._role(person) == "civilian" or original.site_controller.vehicles.is_siege_crew(identity): return {"ok": true, "valid": false, "reason": "SIEGE_BODY_CHANGED"}
	var location: Dictionary = _coordinate(original.terrain)
	if not location.ok: return location
	var accepted: Dictionary = _region_player_endpoint_location(status, party, location.site, event)
	if not accepted.ok: return accepted
	var entry: Vector2i = accepted.entry
	var cell: Vector2i = person.cell
	var body_owner: Variant = person.owner
	var unit := int(person.unit)
	var ready: bool = body_owner.exchange_ready(unit) if body_owner is TerrainArmy else body_owner.exchange_ready()
	var gap: Vector2i = entry - cell
	if [cell.x, cell.y] != witness.person_cell or [entry.x, entry.y] != witness.entry or not ready or absi(gap.x) + absi(gap.y) != 1 \
		or not original.terrain.can_attack_across(cell, entry) or original.site_controller.vehicles.blocks_person_step(identity, cell, cell, entry, entry):
		return {"ok": true, "valid": false, "reason": "SIEGE_CHANNEL_CHANGED"}
	return {"ok": true, "valid": true}


func prepare_region_player_departure(controller: SiteController, nonce: String) -> Dictionary:
	if controller == null or controller.region_slot != self or controller.lab == null: return fail("REGION_SOURCE")
	var lab: TerrainLab = controller.lab
	var selected := controller._region_departure_capability(nonce)
	if not selected.ok: return selected
	if bool(selected.waiting): return fail("NOT_READY")
	if _region_bound_original_lab(lab.terrain) != lab or str(control.active_site_id) != str(lab.terrain.site.id): return fail("REGION_SOURCE")
	if not _marker.get("journey", {}).is_empty() or not _prepared.is_empty(): return fail("BUSY")
	var mode: Dictionary = region_registry().modes.get(str(lab.terrain.site.id), {})
	var bind := lab.region_bind_receipt(lab.terrain)
	if str(mode.get("mode", "")) != "live" or str(mode.get("backend", "")) != lab.region_backend_expected() or bind.get("complete") != true or bind.get("owners_restored") != true or str(bind.get("mode", "")) != "live": return fail("COMMITTED_UNBOUND")
	var siege := RegionBattle.prepare_original_siege(lab)
	if not siege.ok or not siege.get("present", false): return fail("IN_COMBAT")
	# Keep the original fire/transport admission; no generic combat or BUSY waiver.
	for row: Dictionary in control.get("fire_clock", {}).get("index", {}).values():
		if bool(row.get("fire_active", false)): return fail("BUSY")
	if Runtime.fire_active(lab.terrain) or not lab.terrain.site.get("fire", {}).is_empty(): return fail("BUSY")
	var coordinate := _coordinate(lab.terrain)
	if not coordinate.ok: return coordinate
	var settled := validate_settlement(lab.terrain.site, control.logical_game_seconds)
	if not settled.ok or bool(settled.get("legacy", true)) or float(settled.get("pending", INF)) > 0.00000001: return fail("UNSETTLED_SITE")
	# Canonical selected source authentication uses the existing SAME-point checkpoint.
	var checkpoint: Dictionary = controller.checkpoint_region_internal("region_barrier", true, {}, nonce)
	if not checkpoint.ok: return checkpoint
	selected = controller._region_departure_capability(nonce)
	if not selected.ok or bool(selected.get("waiting", true)): return fail("STALE_REGION_INTENT")
	var original: Dictionary = lab.terrain.site.duplicate(true)
	var fire_capture := _capture_transfer_fire_snapshots(lab.terrain, original)
	if not fire_capture.ok: return fire_capture
	var spec: Dictionary = selected.spec.duplicate(true)
	spec.game_seconds = float(control.logical_game_seconds)
	var token := "travel_" + Crypto.new().generate_random_bytes(16).hex_encode()
	var extracted := RegionTravel.extract(original, spec, token)
	if not extracted.ok: return extracted
	var actual_people: Array = extracted.party.person_ids.duplicate()
	actual_people.sort()
	if actual_people != selected.people: return fail("REGION_ACTIVE_DEPENDENCY", "原完整 closure 與受控選擇不一致")
	extracted.party.upkeep.owner_action_seconds = float(control.fire_clock.action_seconds)
	extracted.party.upkeep.original_deaths = {}
	# The origin candidate is a NEW body: a region_snapshot inherited from the
	# live Site (e.g. its arrival bind) authenticated the old body only.
	extracted.origin.erase("region_snapshot")
	var candidate := Env.navigation_for_state(lab.terrain, extracted.origin)
	candidate.set_meta(&"region_bind_source", lab.terrain)
	if not region_bind_candidate.is_valid(): return fail("MISSING_REGION_ADAPTER")
	var binding: Dictionary = region_bind_candidate.call(lab, candidate, "cold_exact")
	if not binding.get("ok", false): return binding
	if not binding.get("data") is TerrainData or not binding.get("can_publish") is Callable or not binding.get("save_candidate") is Callable or not binding.get("publish") is Callable or not binding.get("discard") is Callable: return fail("MISSING_REGION_ADAPTER")
	return {"ok": true, "nonce": nonce, "controller": controller, "lab": lab, "source": lab.terrain,
		"generation": int(_marker.generation), "runtime_revision": int(region_registry().revision),
		"world": float(control.logical_game_seconds), "action": float(control.fire_clock.action_seconds), "fire_sequence": int(control.fire_clock.sequence),
		"coordinate": coordinate.site, "component": int(selected.component), "token": token,
		"candidate": binding.data, "binding": binding, "party": extracted.party, "vacated_housing": extracted.vacated_housing}


func commit_region_player_departure(prepared: Dictionary) -> Dictionary:
	if not prepared.get("ok", false) or not prepared.get("controller") is SiteController: return fail("INVALID")
	var controller: SiteController = prepared.controller
	if controller.region_slot != self or controller.lab != prepared.lab or controller.lab.terrain != prepared.source: return fail("STALE_REGION_INTENT")
	var selected := controller._region_departure_capability(str(prepared.nonce))
	if not selected.ok or bool(selected.get("waiting", true)): return fail("STALE_REGION_INTENT")
	if int(prepared.generation) != int(_marker.generation) or int(prepared.runtime_revision) != int(region_registry().revision) \
		or float(prepared.world) != float(control.logical_game_seconds) or float(prepared.action) != float(control.fire_clock.action_seconds) \
		or int(prepared.fire_sequence) != int(control.fire_clock.sequence) or not bool(prepared.binding.can_publish.call()): return fail("STALE_BIND")
	if not _marker.get("journey", {}).is_empty() or not _prepared.is_empty(): return fail("BUSY")
	var generation := int(_marker.generation) + 1
	var source_path := _generation_path(generation, prepared.coordinate)
	var checked: Dictionary = prepared.binding.save_candidate.call(prepared.candidate, source_path)
	if not checked.ok: return checked
	var token := str(prepared.token)
	var party_path := "travel/%s/party.json" % token
	var written := _write_new_document(folder.path_join(party_path), {"version": 1, "token": token, "pin": pin.duplicate(true),
		"encoding": "godot_var_v1", "party": Marshalls.raw_to_base64(var_to_bytes(prepared.party))})
	if not written.ok: return written
	var next_control := control.duplicate(true)
	var owner := str(prepared.source.site.id)
	next_control.active_site_id = ""
	var registry: Dictionary = next_control.region_gameplay
	# The selected marker is resumable even when the actual postcommit bind fails.
	var pending_mode := GameplayClock.activate_mode(registry, owner, "committed-unbound", generation, "gd", "original_replay",
		float(control.logical_game_seconds), float(control.fire_clock.action_seconds), {})
	if not pending_mode.ok: return pending_mode
	for battle: Dictionary in registry.battles.values():
		if str(battle.get("site_id", "")) == owner and str(battle.get("phase", "")) != "finished": battle.mode = "committed-unbound"
	registry.revision = int(registry.revision) + 1
	var sites: Dictionary = _marker.get("sites", {}).duplicate(true)
	var cold := _collect_cold_checkpoint(generation, sites, next_control)
	if not cold.ok: return cold
	var parties := collect_region_party_checkpoint(generation, next_control)
	if not parties.ok: return parties
	sites[_site_key(prepared.coordinate)] = _file_entry(source_path)
	var now := float(control.logical_game_seconds)
	var journey := {"version": 1, "kind": RegionTravel.KIND, "token": token, "party_path": party_path,
		"party_sha256": FileAccess.get_sha256(folder.path_join(party_path)), "departure_game_seconds": now,
		"origin": [prepared.coordinate.x, prepared.coordinate.y], "position": {"site": [prepared.coordinate.x, prepared.coordinate.y], "component": int(prepared.component)},
		"plan_path": "", "plan_sha256": "", "plan_started_game_seconds": now, "plans": 0}
	var published := _publish(sites, next_control, str(_marker.get("transfer_token", "")), journey)
	if not published.ok: return published
	_travel_party_runtime = prepared.party
	_travel_party_runtime_token = token
	var lab: TerrainLab = prepared.lab
	lab.restore_only = true # Only the committed selected generation may retire live input.
	_region_original_labs[owner] = lab
	var bound: Dictionary = prepared.binding.publish.call(checked.data)
	if not bound.get("ok", false) or bound.get("complete") != true or bound.get("owners_restored") != true \
		or str(bound.get("mode", "")) != "cold_exact" or str(bound.get("consumer", "")) != "original_replay":
		var fault := fail("COMMITTED_UNBOUND", "已提交完整 marker；須由最高完整世代重開原 owner")
		fault.committed = true
		controller.latch_original_step_fault(fault)
		return fault
	var cold_receipt := lab.region_bind_receipt(lab.terrain)
	var activated := activate_region_mode(owner, "cold_exact", "original_replay", cold_receipt, str(cold_receipt.get("backend", "gd")))
	if not activated.ok:
		activated.committed = true
		controller.latch_original_step_fault(activated)
		return activated
	# Metadata follows only the real producer activation, never a forged receipt.
	for battle: Dictionary in region_registry().battles.values():
		if str(battle.get("site_id", "")) == owner and str(battle.get("phase", "")) != "finished": battle.mode = "cold_exact"
	var refreshed := refresh_original_region_siege_battle(lab)
	if not refreshed.ok:
		refreshed.committed = true
		controller.latch_original_step_fault(refreshed)
		return refreshed
	var cold_checkpoint := checkpoint_region_travel()
	if not cold_checkpoint.ok:
		cold_checkpoint.committed = true
		controller.latch_original_step_fault(cold_checkpoint)
		return cold_checkpoint
	controller._auto_save_blocked = true
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies: team.set_process(false)
	return {"ok": true, "token": token, "generation": int(_marker.generation), "ownership_generation": published.generation, "binding": bound, "source_data": checked.data,
		"party": prepared.party, "vacated_housing": prepared.vacated_housing}


func refresh_original_region_siege_battle(original: TerrainLab) -> Dictionary:
	if not is_instance_valid(original) or original.terrain == null or original.site_controller == null or original.site_controller.region_slot != self:
		return fail("MISSING_ORIGINAL_SIEGE_OWNER")
	var owner := str(original.terrain.site.id)
	if _region_bound_original_lab(original.terrain) != original: return fail("STALE_ORIGINAL_SIEGE_OWNER")
	var mode: Dictionary = region_registry().modes.get(owner, {})
	if str(mode.get("mode", "")) not in ["live", "cold_exact", "formula_active"]: return {"ok": true, "changed": false, "reason": "ORIGINAL_MODE_PENDING"}
	if str(mode.get("backend", "")) != original.region_backend_expected(): return fail("REGION_BACKEND_UNADMITTED")
	var world := float(control.logical_game_seconds)
	var action := float(control.fire_clock.action_seconds)
	var settled: Dictionary = validate_settlement(original.terrain.site, world)
	var fire: Dictionary = original.terrain.site.get("fire_settlement", {})
	# A world-accepted point whose original effects are still pending (GD mesh contacts) has not yet
	# published its fire cursor: the cursor still sits at that SAME point's begin. That is the pending
	# case below, not an incomplete point.
	var pending_point: Dictionary = original._region_point_pending
	var cursor_deferred: bool = not pending_point.is_empty() and not original._region_point_consuming \
		and absf(original.fire_action_cursor - float(pending_point.get("fire_action_begin", -1.0))) <= 0.00000001 \
		and absf(float(pending_point.get("fire_action_end", -1.0)) - action) <= 0.00000001
	if not settled.ok or settled.get("legacy", true) or float(settled.get("pending", INF)) > 0.00000001 \
		or str(fire.get("epoch", "")) != str(control.fire_clock.epoch) or int(fire.get("sequence", -1)) != int(control.fire_clock.sequence) \
		or absf(float(fire.get("game_seconds", -1.0)) - world) > 0.00000001 or absf(float(fire.get("action_seconds", -1.0)) - action) > 0.00000001 \
		or absf(original.fire_action_cursor - action) > 0.00000001 and not cursor_deferred or int(mode.get("generation", -1)) != int(_marker.get("generation", 0)) \
		or absf(float(mode.get("game_seconds", -1.0)) - world) > 0.00000001 or absf(float(mode.get("action_seconds", -1.0)) - action) > 0.00000001:
		return fail("INCOMPLETE_ORIGINAL_SIEGE_POINT")
	if not region_player_barrier().is_empty() or not original._region_point_pending.is_empty() or original._region_point_consuming or original._region_point_dispatching \
		or not original._region_point_contacts.is_empty() or not original._region_point_wakes.is_empty() or not original._combat_contacts.is_empty() \
		or not original.terrain.get_meta(&"fire_boundary", {}).is_empty(): return {"ok": true, "changed": false, "reason": "ORIGINAL_EFFECTS_PENDING"}
	var existing := {}
	for battle: Dictionary in region_registry().battles.values():
		if str(battle.get("site_id", "")) != owner or str(battle.get("phase", "")) == "finished": continue
		if not existing.is_empty(): return fail("BATTLE_OWNER_CONFLICT")
		existing = battle
	if not existing.get("pending", []).is_empty() or existing.has("prepared_endpoint"): return {"ok": true, "changed": false, "reason": "BATTLE_EFFECTS_PENDING"}
	var result := RegionBattle.prepare_original_siege(original, existing)
	if not result.ok: return result
	if not result.get("present", false): return {"ok": true, "changed": false, "reason": str(result.get("reason", "NO_ORIGINAL_SIEGE"))}
	var bind := original.region_bind_receipt(original.terrain)
	if bind.get("complete") != true or bind.get("owners_restored") != true or str(bind.get("backend", "")) != original.region_backend_expected(): return fail("COMMITTED_UNBOUND")
	var siege: Dictionary = result.siege
	var identifier := str(existing.get("id", "siege:%s:%s:%d" % [owner, str(siege.center_id), int(control.fire_clock.sequence)]))
	var battle := existing.duplicate(true)
	if battle.is_empty():
		var made := RegionBattle.create({"id": identifier, "site_id": owner, "attackers": result.attackers, "defenders": result.defenders,
			"game_time": float(control.logical_game_seconds), "rng_state": int(hash(str(pin.world_instance_id) + ":" + identifier))})
		if not made.ok: return made
		battle = made.battle
	# Raw owner signatures change only at actual points; never replay a phase
	# transition or reset already accepted damage/fatigue/contact receipts.
	var same_point: bool = not battle.get("siege", {}).is_empty()
	if same_point:
		var previous: Dictionary = battle.siege
		same_point = float(previous.source.game_seconds) == float(siege.source.game_seconds) and float(previous.source.action_seconds) == float(siege.source.action_seconds) \
			and str(previous.source.fire_epoch) == str(siege.source.fire_epoch) and int(previous.source.fire_sequence) == int(siege.source.fire_sequence)
		for field: String in RegionBattle.SIEGE_FIELDS:
			if field not in ["source", "source_sha256"] and previous[field] != siege[field]: same_point = false
	if same_point: return {"ok": true, "changed": false, "battle_id": identifier}
	battle.kind = "siege"
	battle.phase = str(siege.phase)
	battle["siege"] = siege
	battle.attackers = result.attackers
	battle.defenders = result.defenders
	battle.mode = "live" if owner == str(control.active_site_id) else "cold_exact"
	battle.completed_game_time = float(control.logical_game_seconds)
	battle.round_inputs = {}
	battle.revision = int(battle.revision) + 1
	var candidate: Dictionary = region_registry().duplicate(true)
	candidate.battles[identifier] = battle
	var activation := bind.duplicate(true)
	activation.mode = str(battle.mode)
	activation.consumer = "original_site" if battle.mode == "live" else "original_replay"
	var activated := GameplayClock.activate_mode(candidate, owner, str(battle.mode), int(_marker.get("generation", 0)), str(bind.backend), str(activation.consumer),
		float(control.logical_game_seconds), float(control.fire_clock.action_seconds), activation)
	if not activated.ok: return activated
	candidate.revision = int(candidate.revision) + 1
	var valid := GameplayClock.validate_registry(candidate, float(control.logical_game_seconds))
	if not valid.ok: return valid
	var registry := region_registry()
	registry.clear()
	registry.merge(candidate, true)
	return {"ok": true, "changed": true, "battle_id": identifier, "phase": str(battle.phase), "mode": str(battle.mode), "source": siege.source}


func _region_first_npc_siege_contact(token: String, to: float, interval: Dictionary = {}) -> Dictionary:
	var battle_ids: Array = []
	for id: String in region_registry().battles:
		var battle: Dictionary = region_registry().battles[id]
		if str(battle.get("kind", "")) == "siege" and str(battle.get("phase", "")) != "finished": battle_ids.append(id)
	if battle_ids.is_empty(): return {"ok": true, "contact": false}
	battle_ids.sort()
	var reference: Dictionary = region_registry().parties.get(token, {})
	if str(reference.get("controller", "")) != "npc" or str(reference.get("phase", "")) != "travelling": return {"ok": true, "contact": false}
	var selected := _region_npc_party(token)
	if not selected.ok: return selected
	var planned := _region_npc_plan(token)
	if not planned.ok: return planned
	var party: Dictionary = selected.party
	if str(party.get("mode", "land")) != "land" or not party.content.get("vehicles", {}).is_empty() or not party.content.get("actors", {}).is_empty() or not party.upkeep.get("live", {}).is_empty(): return {"ok": true, "contact": false}
	if not region_original_party_progress.is_valid(): return fail("MISSING_REGION_PARTY_PROGRESS")
	var host: Object = region_original_party_progress.get_object()
	if not host is TerrainLab or host.site_controller == null or host.site_controller.region_slot != self: return fail("INVALID_REGION_PARTY_PROGRESS")
	var restored: Dictionary = host.prepare_region_party_original_owner(token, party, self)
	if not restored.ok: return restored
	if not has_method("region_original_party_runtime_proof"): return fail("MISSING_ORIGINAL_PARTY_PROOF")
	var raw_proof: Variant = call("region_original_party_runtime_proof", token, party)
	if not raw_proof is Dictionary or not raw_proof.get("ok", false) or not raw_proof.get("lab") is TerrainLab:
		return raw_proof if raw_proof is Dictionary else fail("INVALID_ORIGINAL_PARTY_PROOF")
	var party_lab: TerrainLab = raw_proof.lab
	var traveller: Dictionary = party_lab.site_controller.person_actions._person(int(party.leader_person_id), false)
	if traveller.is_empty() or not SiteSettlement._fit(traveller): return {"ok": true, "contact": false}
	# Extraction indexes every departing body; a leader without its stable
	# reference is an invalid party, never a contact without a witness.
	var party_reference: Variant = party.content.get("travel_identity", {}).get("refs", {}).get("person", {}).get(str(int(party.leader_person_id)))
	if not party_reference is Dictionary: return fail("INVALID_IDENTITY", "原 NPC 隊長缺穩定身分")
	var prepared: Dictionary = prepare_region_route_context(null, party)
	if not prepared.ok: return prepared
	var cache := {}
	var points: Dictionary = _region_contact_land_points(party, planned.plan, to, true, reference.position, prepared.context, cache)
	if not points.ok: return points
	for point: Dictionary in points.points:
		var location: Dictionary = point.position
		var site := Vector2i(int(location.site[0]), int(location.site[1]))
		var owner := Grid.site_id(str(pin.atlas_id), site)
		var entry := Vector2i(int(location.cell[0]), int(location.cell[1]))
		if entry.x < 0 or entry.y < 0: continue
		for id: String in battle_ids:
			var battle: Dictionary = region_registry().battles[id]
			if str(battle.get("kind", "")) != "siege" or str(battle.get("site_id", "")) != owner or str(battle.get("phase", "")) == "finished": continue
			var original: TerrainLab = _region_original_labs.get(owner)
			if not is_instance_valid(original) or _region_bound_original_lab(original.terrain) != original: return fail("COMMITTED_UNBOUND")
			if not original.terrain.contains(entry): continue
			for identity: Variant in battle.attackers + battle.defenders:
				var person: Dictionary = original.site_controller.person_actions._person(int(identity), false)
				if person.is_empty() or int(person.faction) == int(traveller.faction) or not SiteSettlement._fit(person) or bool(person.moving) \
					or SiteSettlement._role(person) == "civilian" or original.site_controller.vehicles.is_siege_crew(int(identity)): continue
				var body_owner: Variant = person.owner
				var unit := int(person.unit)
				var ready: bool = body_owner.exchange_ready(unit) if body_owner is TerrainArmy or body_owner is CrowdPersonOwner else body_owner.exchange_ready()
				var gap: Vector2i = entry - Vector2i(person.cell)
				if not ready or absi(gap.x) + absi(gap.y) != 1 or not original.terrain.can_attack_across(person.cell, entry): continue
				if original.site_controller.vehicles.blocks_person_step(int(identity), person.cell, person.cell, entry, entry): continue
				# Site stable references are issued only by the original travel identity
				# allocator; this read-only probe never issues one. The NPC consumer
				# requires the witnessed body's reference, so an unindexed body is not
				# an NPC channel candidate.
				var static_reference: Variant = original.terrain.site.get("travel_identity", {}).get("refs", {}).get("person", {}).get(str(int(identity)))
				if not static_reference is Dictionary: continue
				var cell: Vector2i = person.cell
				var witness := {"battle_id": id, "source_generation": int(_marker.generation), "runtime_revision": int(region_registry().revision),
					"navigation_revision": int(original.terrain.navigation_revision), "person_id": int(identity), "person_cell": [cell.x, cell.y],
					"entry": [entry.x, entry.y], "party_token": token, "party_source": raw_proof.get("proof", {}).duplicate(true),
					"party_reference": party_reference.duplicate(),
					"static_reference": static_reference.duplicate(),
					"game_seconds": float(control.logical_game_seconds), "action_seconds": float(control.fire_clock.action_seconds), "legal_ground_melee": true}
				var contact := {"kind": "npc_siege_channel", "at": float(point.at),
					"first": point.duplicate(true),
					"second": {"at": float(point.at), "position": {"site": location.site.duplicate(), "component": int(location.component), "cell": [cell.x, cell.y], "mode": "land"}}, "witness": witness}
				return {"ok": true, "contact": true, "at": float(point.at), "site": location.site.duplicate(),
					"component": int(location.route_component), "site_id": owner, "battle_id": id, "contact_receipt": contact}
	return {"ok": true, "contact": false}



func _region_validate_npc_siege_contact(event: Dictionary) -> Dictionary:
	var contact: Dictionary = event.get("payload", {}).get("contact_receipt", {})
	if str(contact.get("kind", "")) != "npc_siege_channel" or str(event.get("kind", "")) != "reinforcement": return fail("INVALID_NPC_CONTACT")
	var queued := false
	for original_event: Dictionary in region_registry().events:
		if str(original_event.get("id", "")) == str(event.get("id", "")) and str(original_event.get("status", "")) == "pending" and var_to_bytes(original_event) == var_to_bytes(event): queued = true
	if not queued: return fail("INVALID_NPC_CONTACT")
	var witness: Variant = contact.get("witness")
	if not witness is Dictionary or not RegionTravel._frame_pair(witness.get("person_cell")) or not RegionTravel._frame_pair(witness.get("entry")) or not witness.get("party_reference") is Dictionary or not witness.get("static_reference") is Dictionary or str(witness.get("battle_id", "")) != str(event.get("payload", {}).get("battle_id", "")) or str(witness.get("party_token", "")) != str(event.get("payload", {}).get("token", "")):
		return fail("INVALID_NPC_CONTACT")
	if float(contact.get("at", -1.0)) != float(event.get("at", -2.0)) or float(event.at) != float(control.logical_game_seconds): return fail("STALE_NPC_CONTACT")
	var token := str(witness.party_token)
	var reference: Dictionary = region_registry().parties.get(token, {})
	if str(reference.get("controller", "")) != "npc" or str(reference.get("phase", "")) != "travelling": return {"ok": true, "valid": false, "reason": "NPC_ROUTE_CHANGED"}
	var battle: Dictionary = region_registry().battles.get(str(witness.battle_id), {})
	if battle.is_empty() or str(battle.get("kind", "")) != "siege" or str(battle.get("phase", "")) == "finished": return {"ok": true, "valid": false, "reason": "SIEGE_CHANNEL_ENDED"}
	var owner := str(battle.site_id)
	if owner != str(event.get("owner", "")): return fail("INVALID_NPC_CONTACT")
	var original: TerrainLab = _region_original_labs.get(owner)
	if not is_instance_valid(original) or _region_bound_original_lab(original.terrain) != original: return fail("COMMITTED_UNBOUND")
	var bind: Dictionary = original.region_bind_receipt(original.terrain)
	if bind.get("complete") != true or bind.get("owners_restored") != true: return fail("COMMITTED_UNBOUND")
	var selected := _region_npc_party(token)
	if not selected.ok: return selected
	var party: Dictionary = selected.party
	if str(party.get("mode", "land")) != "land" or not party.content.get("actors", {}).is_empty() or not party.content.get("vehicles", {}).is_empty() or not party.upkeep.get("live", {}).is_empty(): return {"ok": true, "valid": false, "reason": "NPC_CLOSURE_CHANGED"}
	if party.content.travel_identity.refs.person.get(str(int(party.leader_person_id))) != witness.party_reference: return {"ok": true, "valid": false, "reason": "NPC_REFERENCE_CHANGED"}
	var runtime := region_original_party_runtime_proof(token, party)
	if not runtime.ok: return runtime
	var traveller: Dictionary = runtime.lab.site_controller.person_actions._person(int(party.leader_person_id), false)
	var identity := int(witness.get("person_id", -1))
	if not (battle.attackers + battle.defenders).has(identity): return {"ok": true, "valid": false, "reason": "SIEGE_ROSTER_CHANGED"}
	if original.terrain.site.get("travel_identity", {}).get("refs", {}).get("person", {}).get(str(identity)) != witness.static_reference: return {"ok": true, "valid": false, "reason": "SIEGE_REFERENCE_CHANGED"}
	var person: Dictionary = original.site_controller.person_actions._person(identity, false)
	if traveller.is_empty() or not SiteSettlement._fit(traveller) or person.is_empty() or int(person.faction) == int(traveller.faction) or not SiteSettlement._fit(person) or bool(person.moving) or SiteSettlement._role(person) == "civilian" or original.site_controller.vehicles.is_siege_crew(identity): return {"ok": true, "valid": false, "reason": "SIEGE_BODY_CHANGED"}
	var coordinate := _coordinate(original.terrain)
	if not coordinate.ok: return coordinate
	var planned := _region_npc_plan(token)
	if not planned.ok: return planned
	var position := _region_current_land_position(party, planned.plan, str(reference.plan_path))
	if position.site != [coordinate.site.x, coordinate.site.y] or event.payload.get("site") != position.site: return {"ok": true, "valid": false, "reason": "NPC_ROUTE_CHANGED"}
	var entry := RegionRoute.entry_cell(planned.plan.steps[int(position.step_index)])
	var cell: Vector2i = person.cell
	var body_owner: Variant = person.owner
	var unit := int(person.unit)
	var ready: bool = body_owner.exchange_ready(unit) if body_owner is TerrainArmy or body_owner is CrowdPersonOwner else body_owner.exchange_ready()
	var gap: Vector2i = entry - cell
	var first: Dictionary = contact.get("first", {}).get("position", {})
	if first.get("site") != position.site or first.get("cell") != [entry.x, entry.y] or [entry.x, entry.y] != witness.entry or [cell.x, cell.y] != witness.person_cell or not original.terrain.contains(entry) or not ready or absi(gap.x) + absi(gap.y) != 1 or not original.terrain.can_attack_across(cell, entry) or original.site_controller.vehicles.blocks_person_step(identity, cell, cell, entry, entry): return {"ok": true, "valid": false, "reason": "SIEGE_CHANNEL_CHANGED"}
	return {"ok": true, "valid": true}



func _region_validate_npc_arrival_duplicate_event(token: String, event_id: String, event: Dictionary) -> Dictionary:
	# Reread the original registry; a duplicate flag is not an event authority.
	var reference: Dictionary = region_registry().parties.get(token, {})
	if token.is_empty() or reference.get("controller") != "npc" or reference.get("phase") != "entered": return fail("STALE_NPC_ARRIVAL", "原NPC尚未實際到站")
	var actual := {}
	for queued: Dictionary in region_registry().events:
		if str(queued.id) == event_id: actual = queued
	if actual.is_empty() or not GameplayClock.validate_event(actual).ok or actual.kind not in ["arrival", "player_arrival", "reinforcement"] \
			or str(actual.payload.get("token", "")) != token or float(actual.at) > float(control.logical_game_seconds) + 0.00000001 \
			or var_to_bytes(actual) != var_to_bytes(event): return fail("STALE_NPC_ARRIVAL", "原重複到站不是同一NPC的當前真事件")
	return {"ok": true, "reference": reference, "event": actual}


var _original_food_results: Array[Dictionary] = []
var _original_food_result_readout := false

func _observe_original_food_result(original: TerrainLab, kind: String, identity: String, at_game_seconds: float, result: Dictionary, interval: Dictionary = {}) -> void:
	# Ephemeral readout; never part of control, Site, Party or saved food state.
	if not _original_food_result_readout: return
	if source == null or pin.is_empty() or not is_instance_valid(original) or original.site_controller == null or original.site_controller.region_slot != self: return
	var consumed: Variant = result.get("consumed_rations", 0.0)
	if not result.get("ok", false) or not (consumed is float or consumed is int) or not is_finite(float(consumed)) or float(consumed) <= 0.0: return
	var point: Dictionary = interval if not interval.is_empty() else original._region_point_pending
	var identity_interval := {}
	if point.has("epoch") and point.has("sequence"):
		for field: String in ["epoch", "sequence", "game_begin", "game_end", "action_begin", "action_end"]: identity_interval[field] = point[field]
	var accepted := identity_interval.is_empty()
	if not accepted and bool(original._region_point_pending.get("interval_complete", false)):
		# The common clocks reach the endpoint by their own accumulation; like every other
		# endpoint proof here, they are that endpoint within the shared clock tolerance.
		accepted = str(control.fire_clock.epoch) == str(point.epoch) and int(control.fire_clock.sequence) == int(point.sequence) \
			and absf(float(control.logical_game_seconds) - float(point.game_end)) <= 0.00000001 and absf(float(control.fire_clock.action_seconds) - float(point.action_end)) <= 0.00000001
	_original_food_results.append({"site_id": str(original.terrain.site.id), "owner_kind": kind, "owner_id": identity, "at_game_seconds": at_game_seconds, "consumed_rations": float(consumed), "interval": identity_interval, "accepted": accepted})

func take_original_food_results() -> Array[Dictionary]:
	# The reader opts into subsequent original results; ordinary play queues none.
	_original_food_result_readout = true
	var results: Array[Dictionary] = []
	for food: Dictionary in _original_food_results:
		if not bool(food.accepted): continue
		var result := food.duplicate(true)
		result.erase("accepted")
		results.append(result)
	_original_food_results.clear()
	return results


func _region_npc_live_ship_action(original: TerrainLab, vehicle: Dictionary) -> Dictionary:
	# Query the committed Nation route only inside this real positive body slice.
	# Original Vehicle remains the sole reservation, speed and movement producer.
	if original == null or original.site_controller == null or original.site_controller.region_slot != self \
			or not original._region_owner_interval_active or original.terrain == null:
		return {"ok": true, "eligible": false}
	var token := str(original._region_party_token)
	if region_registry().parties.get(token, {}).get("controller") != "npc": return {"ok": true, "eligible": false}
	var selected := _region_npc_party(token)
	if not selected.ok: return selected
	var party: Dictionary = selected.party
	if party.get("controller") != "npc" or party.get("mode") != "sea" \
			or str(party.upkeep.get("live", {}).get("upkeep", "")) != "liveBody" \
			or not party.content.actors.is_empty() or int(party.content.controlled_person_id) != -1:
		return {"ok": true, "eligible": false}
	var proved := region_original_party_runtime_proof(token, party)
	if not proved.ok or proved.get("lab") != original: return proved if not proved.ok else fail("STALE_REGION_PARTY_OWNER")
	var identity := str(vehicle.get("id", ""))
	if not is_same(original.site_controller.vehicles.records().get(identity), vehicle): return fail("STALE_SHIP")
	var actual_ref: Dictionary = original.terrain.site.travel_identity.refs.vehicle.get(identity, {})
	if actual_ref.is_empty() or party.content.travel_identity.refs.vehicle.get(identity) != actual_ref: return fail("PARTY_BODY_CLOSURE")
	var team: Variant = original.site_controller.vehicles._siege_team(vehicle)
	if not team is TerrainArmy or not team.command_eligible(team.current_commander) or team.is_sustain_routed(): return {"ok": true, "eligible": false}
	# A true current hostile crew contact retains the original defensive stop.
	for own: Dictionary in original.site_controller.vehicles.ship_people(vehicle):
		var own_id := int(own.id)
		if not original.site_controller.vehicles.ship_can_attack(own_id): continue
		for other_id: int in party.person_ids:
			var other: Dictionary = original.site_controller.vehicles.ship_person(other_id)
			if not other.is_empty() and int(other.faction) != int(team.faction_id) and not bool(other.captive) \
					and other.owner.combat_can_act(int(other.unit)) and original.site_controller.vehicles.ship_combat_contact(own_id, other_id):
				return {"ok": true, "eligible": false}
	var tokens: Array = region_registry().parties.keys()
	tokens.sort()
	for source_token: String in tokens:
		var reference: Dictionary = region_registry().parties[source_token]
		if reference.get("controller") != "npc" or not (source_token == token and reference.get("phase") == "travelling" \
				or reference.get("phase") == "joined" and reference.get("entered_party") == token): continue
		var request: Dictionary = reference.get("transfer_receipt", {})
		if request.get("transfer_token") != source_token or str(request.get("nation_id", "")).is_empty(): continue
		var source_party: Dictionary = proved.selected_party
		if source_token != token:
			var document := _region_life_party_document(source_token, str(reference.party_path), str(reference.party_sha256))
			if not document.ok: return document
			source_party = document.party
		var source_team := str(int(request.get("team_id", -1)))
		if source_party.content.travel_identity.refs.team.get(source_team, {}) != original.terrain.site.travel_identity.refs.team.get(str(int(vehicle.team_id)), {}) \
				or source_party.content.travel_identity.refs.team.get(source_team, {}).is_empty(): continue
		var source_boats: Array[String] = []
		for source_id: String in source_party.content.vehicles:
			if int(source_party.content.vehicles[source_id].get("team_id", -1)) == int(request.team_id): source_boats.append(source_id)
		# The first physical lane has one committed hull per Nation fleet. A
		# Multi-hull LIVE resumption is not admitted by this bounded producer.
		if source_boats.size() != 1: continue
		var source_id := source_boats[0]
		if source_party.content.travel_identity.refs.vehicle.get(source_id) != actual_ref: continue
		var planned := _travel_document(str(reference.plan_path), str(reference.plan_sha256), _travel_plan_cache)
		if not planned.ok: return planned
		var plan: Dictionary = planned.payload
		if plan.get("token") != source_token or plan.get("mode") != "sea" or not plan.get("action_steps") is Array: return fail("CORRUPT_ROUTE")
		var frame: Dictionary = party.upkeep.live.frame
		var origin := Vector2i(int(frame.world_origin[0]), int(frame.world_origin[1]))
		var at: Vector2i = original.terrain.cell_from_index(int(vehicle.cell)) + origin
		var chosen := {}
		var lower := int(source_party.upkeep.get("sea_cursor", {}).get("action_index", -1))
		if lower < 0 or lower > plan.action_steps.size(): return fail("CORRUPT_SEA_CURSOR")
		for index: int in range(lower, plan.action_steps.size()):
			var action: Dictionary = plan.action_steps[index]
			if str(action.get("vehicle_id", "")) != source_id: continue
			for field: String in ["from_site", "from", "anchor", "from_facing", "facing"]:
				if not action.get(field) is Array or action[field].size() != 2 \
						or not _whole(action[field][0], -2147483648, 2147483647) or not _whole(action[field][1], -2147483648, 2147483647): return fail("CORRUPT_ROUTE")
			var base := Vector2i(int(action.from_site[0]) * 100, -int(action.from_site[1]) * 100)
			var from := base + Vector2i(int(action.from[0]), int(action.from[1]))
			if from != at or Vector2i(int(action.from_facing[0]), int(action.from_facing[1])) != Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1])): continue
			var facing := Vector2i(int(action.facing[0]), int(action.facing[1]))
			var destination := base + Vector2i(int(action.anchor[0]), int(action.anchor[1])) - origin
			var kind := str(action.get("action", ""))
			var old_facing := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
			var delta := destination - original.terrain.cell_from_index(int(vehicle.cell))
			if kind not in ["forward", "reverse", "dock", "turn"] or not Ship.valid_facing(facing) \
					or kind == "turn" and (delta != Vector2i.ZERO or old_facing.x * facing.x + old_facing.y * facing.y != 0) \
					or kind != "turn" and (facing != old_facing or delta != (-old_facing if kind == "reverse" else old_facing)): return fail("CORRUPT_ROUTE")
			var next := {"ok": true, "eligible": true, "destination": destination, "facing": facing, "action": kind, "docking": kind == "dock", "source_token": source_token, "plan_sha256": str(reference.plan_sha256), "action_index": index}
			if not chosen.is_empty() and (chosen.destination != destination or chosen.facing != facing or chosen.action != kind): return fail("AMBIGUOUS_REGION_SHIP_STEP")
			chosen = next
		return chosen if not chosen.is_empty() else {"ok": true, "eligible": false}
	return {"ok": true, "eligible": false}


func _region_entered_npc_ship_unload_authorized(original: TerrainLab, team: TerrainArmy, requester_id: int, vehicle: Dictionary, existing_job: Dictionary = {}) -> bool:
	# Read current original arrival/command owners; this query issues no permit.
	if not is_instance_valid(original) or original.terrain == null or original.site_controller == null \
			or original.site_controller.region_slot != self or _region_bound_original_lab(original.terrain) != original \
			or original.crowd_site != null and original.crowd_site.active: return false
	var bound: Dictionary = original._region_bind_receipt_value
	if bound.get("complete") != true or bound.get("owners_restored") != true or str(bound.get("backend", "")) != "gd" \
			or team == null or not original.combat_armies.has(team) or team.current_commander < 0 \
			or not team.command_eligible(team.current_commander) or team.combat_identity(team.current_commander) != requester_id \
			or requester_id == original.controlled_person_id() or team.is_sustain_routed(): return false
	var vehicles: SiteVehicleTransport = original.site_controller.vehicles
	var person: Dictionary = vehicles.ship_person(requester_id)
	var own_job: bool = not existing_job.is_empty() and int(existing_job.get("executor_id", 0)) == requester_id \
			and is_same(original.site_controller.person_actions._jobs.get(str(requester_id), {}), existing_job)
	if person.is_empty() or person.owner != team or not vehicles._ship_capable(person, own_job) \
			or not SiteVehicleTransport.is_ship(vehicle) or not is_same(vehicles.records().get(str(vehicle.get("id", ""))), vehicle) \
			or int(vehicle.team_id) != team.team_id or not vehicles.ship_afloat(vehicle) or not vehicle.move.is_empty() \
			or vehicles._ship_in_journey(str(vehicle.id)) or not vehicle.get("naval", {}).get("repair", {}).is_empty(): return false
	var state: Dictionary = original.terrain.site
	var refs: Dictionary = state.get("travel_identity", {}).get("refs", {})
	var team_ref: Dictionary = refs.get("team", {}).get(str(team.team_id), {})
	var person_ref: Dictionary = refs.get("person", {}).get(str(requester_id), {})
	var vehicle_ref: Dictionary = refs.get("vehicle", {}).get(str(vehicle.id), {})
	if team_ref.is_empty() or person_ref.is_empty() or vehicle_ref.is_empty(): return false
	var matched := false
	for token: String in region_registry().parties:
		var reference: Dictionary = region_registry().parties[token]
		var request: Dictionary = reference.get("transfer_receipt", {})
		var mapping: Dictionary = reference.get("arrival_mapping", {})
		if reference.get("controller") != "npc" or reference.get("phase") != "entered" \
				or reference.get("destination_site") != str(state.id) or request.get("transfer_token") != token \
				or str(request.get("nation_id", "")).is_empty() or str(request.get("known_receipt", "")).is_empty() \
				or int(request.get("decider", 0)) <= 0 or request.get("target_site") != str(state.id) \
				or not RegionTravel.validate_arrival_mapping(mapping) or mapping.token != token \
				or int(mapping.generation) > int(_marker.generation): continue
		var source_team := str(int(request.get("team_id", -1)))
		var source_person := str(int(request.get("commander", -1)))
		if mapping.maps.team.get(source_team) != str(team.team_id) or mapping.maps.person.get(source_person) != str(requester_id): continue
		var source_vehicle := ""
		for identity: String in mapping.maps.vehicle:
			if mapping.maps.vehicle[identity] == str(vehicle.id): source_vehicle = identity
		if source_vehicle.is_empty(): continue
		var selected: Dictionary = _region_life_party_document(token, str(reference.get("party_path", "")), str(reference.get("party_sha256", "")))
		var planned: Dictionary = _travel_document(str(reference.get("plan_path", "")), str(reference.get("plan_sha256", "")), {})
		if not selected.ok or not planned.ok: return false
		var party: Dictionary = selected.party
		var plan: Dictionary = planned.payload
		if party.get("controller") != "npc" or party.get("mode") != "sea" \
				or not party.content.actors.is_empty() or int(party.content.controlled_person_id) != -1 \
				or plan.get("token") != token or plan.get("mode") != "sea" or not plan.get("action_steps") is Array \
				or not plan.get("steps") is Array or plan.steps.size() < 2: return false
		var source_refs: Dictionary = party.content.travel_identity.refs
		if source_refs.team.get(source_team) != team_ref or source_refs.person.get(source_person) != person_ref \
				or source_refs.vehicle.get(source_vehicle) != vehicle_ref \
				or int(party.content.vehicles.get(source_vehicle, {}).get("team_id", -1)) != int(request.team_id): return false
		var cursor: Dictionary = party.upkeep.get("sea_cursor", {})
		if cursor.get("plan_id") != reference.plan_path or not _whole(cursor.get("action_index"), 0, plan.action_steps.size()) \
				or int(cursor.action_index) != plan.action_steps.size() or not _seconds(cursor.get("elapsed")) \
				or not _seconds(cursor.get("duration")) or float(cursor.elapsed) != 0.0 or float(cursor.duration) != 0.0 \
				or not _region_npc_sea_position(plan, party).arrived: return false
		var arrival: Variant = reference.get("arrival_game_seconds")
		if not _seconds(arrival) or float(arrival) > float(control.logical_game_seconds): return false
		var completed := false
		for event: Dictionary in region_registry().events:
			if event.get("status") == "complete" and event.get("kind") in ["arrival", "player_arrival", "reinforcement"] \
					and event.get("owner") == str(state.id) and event.get("payload", {}).get("token") == token \
					and float(event.get("at", -1.0)) == float(arrival) and GameplayClock.validate_event(event).ok:
				completed = true
		if not completed or matched: return false
		matched = true
	return matched

## F1a uses the existing common marker, never a second persistence owner.
func faction_registry_view() -> Dictionary:
	return control.get("faction_registry", {}).duplicate(true)

func active_faction(faction_id: int) -> Dictionary:
	return RegionFactionQuery.active(control.get("faction_registry", {}), faction_id)

# Source I/O seam: regressions count real hashing without replacing validation.
func _faction_file_sha256(path: String) -> String:
	return FileAccess.get_sha256(path)

func _faction_digest_valid(checksum: String) -> bool:
	return checksum.length() == 64 and checksum == checksum.to_lower() and checksum.is_valid_hex_number(false)

func _faction_scope_digest(inputs: Array) -> String:
	return var_to_bytes(inputs).hex_encode().sha256_text()

func _faction_digest_bytes(bytes: PackedByteArray) -> String:
	return bytes.hex_encode().sha256_text()

func _faction_digest_matches(memo: Dictionary, key: String, value: Dictionary, expected: String) -> bool:
	var bytes: PackedByteArray = var_to_bytes(value)
	var known: Variant = memo.get(key)
	if known is Dictionary and known.get("bytes") is PackedByteArray and known.get("digest") is String \
			and known.bytes == bytes and known.digest == expected:
		return true
	var actual: String = _faction_digest_bytes(bytes)
	if actual != expected:
		memo.erase(key)
		return false
	if memo.size() >= FACTION_SOURCE_CACHE_LIMIT and not memo.has(key): memo.erase(memo.keys()[0])
	memo[key] = {"bytes": bytes, "digest": actual}
	return true

func _faction_cache_context() -> String:
	if _faction_source_cache.is_empty(): _faction_summary_digest_memo.clear()
	if _faction_clock_cache.is_empty(): _faction_clock_digest_memo.clear()
	var source_id: int = source.get_instance_id() if source != null else 0
	var manifest_hash: String = source.manifest_hash if source != null else ""
	var pin_bytes: PackedByteArray = var_to_bytes(pin)
	if _faction_context_inputs.get("folder") is String and _faction_context_inputs.get("source_id") is int \
			and _faction_context_inputs.get("manifest_hash") is String and _faction_context_inputs.get("pin_bytes") is PackedByteArray \
			and _faction_context_inputs.get("scope") is String and _faction_context_inputs.folder == folder \
			and _faction_context_inputs.source_id == source_id and _faction_context_inputs.manifest_hash == manifest_hash \
			and _faction_context_inputs.pin_bytes == pin_bytes and _faction_context_inputs.scope == _faction_cache_scope:
		return _faction_cache_scope
	var current: String = _faction_scope_digest([folder, pin, source_id, manifest_hash])
	if current != _faction_cache_scope:
		_faction_source_cache.clear()
		_faction_clock_cache.clear()
		_faction_summary_digest_memo.clear()
		_faction_clock_digest_memo.clear()
		_faction_cache_scope = current
	_faction_context_inputs = {"folder": folder, "source_id": source_id, "manifest_hash": manifest_hash,
		"pin_bytes": pin_bytes, "scope": current}
	return current

func _faction_cached(key: String) -> Dictionary:
	var raw: Variant = _faction_source_cache.get(key, {})
	if not raw is Dictionary:
		_faction_source_cache.erase(key)
		_faction_summary_digest_memo.erase(key)
		return {}
	var cached: Dictionary = raw
	if cached.is_empty():
		_faction_summary_digest_memo.erase(key)
		return {}
	if not cached.get("summary") is Dictionary or not cached.get("digest") is String \
			or not _faction_digest_matches(_faction_summary_digest_memo, key, cached.summary, cached.digest):
		_faction_source_cache.erase(key)
		_faction_summary_digest_memo.erase(key)
		return {}
	return {"ok": true, "summary": cached.summary.duplicate(true)}

func _faction_remember(key: String, summary: Dictionary) -> Dictionary:
	if _faction_source_cache.is_empty(): _faction_summary_digest_memo.clear()
	if _faction_source_cache.size() >= FACTION_SOURCE_CACHE_LIMIT and not _faction_source_cache.has(key):
		var evicted: Variant = _faction_source_cache.keys()[0]
		_faction_source_cache.erase(evicted)
		if evicted is String: _faction_summary_digest_memo.erase(evicted)
	var bytes: PackedByteArray = var_to_bytes(summary)
	var digest: String = _faction_digest_bytes(bytes)
	_faction_source_cache[key] = {"summary": summary.duplicate(true), "digest": digest}
	if _faction_summary_digest_memo.size() >= FACTION_SOURCE_CACHE_LIMIT and not _faction_summary_digest_memo.has(key):
		_faction_summary_digest_memo.erase(_faction_summary_digest_memo.keys()[0])
	_faction_summary_digest_memo[key] = {"bytes": bytes, "digest": digest}
	return {"ok": true, "summary": summary}

func _faction_summary(state: Dictionary, owner: String, at: Variant, runtime_revision: Variant = null) -> Dictionary:
	var ids := {}
	var scanned: Variant = RegionFactionQuery.collect_ids(state, ids)
	if not scanned.ok: return scanned
	var historical := {"historical_factions": []}
	for id: String in ids: historical.historical_factions.append({"faction_id": int(id)})
	var live: Dictionary = historical.duplicate(true)
	live.equipment_nations = {}
	live.travel_identity = {"refs": {"nation": {}}}
	for nation_id: String in state.get("equipment_nations", {}):
		var nation: Dictionary = state.equipment_nations[nation_id]
		if not RegionFactionQuery.nation_schema(nation, nation_id): return fail("CORRUPT_SAVE", "nation faction schema")
		if not nation.has("faction_id"): continue
		var ref: Variant = state.get("travel_identity", {}).get("refs", {}).get("nation", {}).get(nation_id)
		if not RegionFactionQuery.ref_valid(ref, "nation"): return fail("CORRUPT_SAVE", "bound nation lacks original typed ref")
		live.equipment_nations[nation_id] = {"faction_version": nation.faction_version, "faction_id": nation.faction_id}
		live.travel_identity.refs.nation[nation_id] = ref.duplicate(true)
	return {"ok": true, "summary": {"live": live, "historical": historical, "owner": owner, "at": at, "runtime_revision": runtime_revision}}

func _faction_site_key(checksum: String, site: Vector2i, path: String) -> String:
	return _faction_cache_context() + ":site:" + _site_key(site) + ":" + path + ":" + checksum

func _faction_site_source(path: String, site: Vector2i, checksum: String, with_persons: bool = false) -> Dictionary:
	var key: String = _faction_site_key(checksum, site, path)
	var present: bool = _faction_source_cache.has(key)
	var cached: Dictionary = _faction_cached(key)
	if not cached.is_empty() and (not with_persons or _person_source_cache.has(key)): return cached
	if not _faction_digest_valid(checksum): return fail("CORRUPT_SAVE", "faction source checksum")
	if not FileAccess.file_exists(path):
		Store.invalidate_faction_summary_path(path)
		return fail("CORRUPT_SAVE", "faction source file missing")
	var shared_record: Dictionary = _faction_static_site_record(path, site, checksum) if _faction_static_original_validator() else {}
	if _faction_static_reading and not present and not shared_record.is_empty():
		var shared: Dictionary = _faction_static_site_cached(shared_record)
		# Person-allocator worlds also need the Site's person projection; only a process entry that
		# carries the digest-checked projection of the same validated file can stand in for the load.
		if not shared.is_empty() and (not with_persons or shared.get("persons") is Dictionary):
			if _faction_file_sha256(path) != checksum:
				Store.invalidate_faction_summary_path(path)
				return fail("CORRUPT_SAVE", "faction source changed during validation")
			if Store.faction_summary_serial() == int(shared_record.serial):
				if with_persons: _remember_person_source(key, shared.persons)
				return _faction_remember(key, shared.summary)
	var loaded: Dictionary = _load_checked(path, site)
	if _faction_file_sha256(path) != checksum:
		Store.invalidate_faction_summary_path(path)
		return fail("CORRUPT_SAVE", "faction source changed during validation")
	if not loaded.ok:
		Store.invalidate_faction_summary_path(path)
		return loaded
	var persons: Variant = person_projection(loaded.data.site) if with_persons else null
	if with_persons: _remember_person_source(key, persons)
	var summarized: Dictionary = _faction_site_summary(loaded.data)
	if not summarized.ok:
		Store.invalidate_faction_summary_path(path)
		return summarized
	if not shared_record.is_empty(): _faction_static_site_remember(shared_record, summarized.summary, persons)
	return _faction_remember(key, summarized.summary)

func _faction_site_summary(data: TerrainData) -> Dictionary:
	var context: Dictionary = data.site.get("region_snapshot", {}).get("context", {})
	var fire: Dictionary = data.site.get("fire_settlement", {})
	# Departure removes the old body snapshot; its paid fire receipt still owns time.
	var at: float = float(context.game_seconds) if not context.is_empty() else (float(fire.game_seconds) if not fire.is_empty() else _site_seconds(data))
	var summarized: Dictionary = _faction_summary(data.site, str(data.site.id), at, RegionFactionQuery.whole_or_null(context.get("runtime_revision")))
	if not summarized.ok: return summarized
	if not context.is_empty():
		summarized.summary["source_clock"] = {"fire_epoch": context.fire_epoch, "fire_sequence": context.fire_sequence,
			"game_seconds": context.game_seconds, "action_seconds": context.action_seconds}
	elif not fire.is_empty():
		summarized.summary["source_clock"] = {"fire_epoch": fire.epoch, "fire_sequence": fire.sequence,
			"game_seconds": fire.game_seconds, "action_seconds": fire.action_seconds}
	return summarized

func _faction_remember_captured_source(path: String, site: Vector2i, checksum: String, data: TerrainData, context: Dictionary) -> Dictionary:
	if not _faction_digest_valid(checksum) or _faction_file_sha256(path) != checksum:
		return fail("CONFLICT", "faction captured source changed during readback")
	if not _seconds(context.get("game_seconds")) or not _seconds(context.get("action_seconds")):
		return fail("CORRUPT_SAVE", "faction captured source time")
	var recorded: Dictionary = data.site.get("region_snapshot", {}).get("context", {})
	for field: String in ["game_seconds", "action_seconds", "fire_epoch", "fire_sequence", "source_generation", "runtime_revision"]:
		# Context clocks are decoded from their original full-precision literals.
		# Do not send those exact values through the lossy JSON number reader again.
		var encoded: Variant = context.get(field) if field in ["game_seconds", "action_seconds"] else JSON.parse_string(JSON.stringify(context.get(field), "", false, true))
		if recorded.get(field) != encoded: return fail("CORRUPT_SAVE", "faction captured source context")
	# This immutable file was just validated; retain its actual capture clock.
	var summarized: Dictionary = _faction_summary(data.site, str(data.site.id), context.game_seconds, RegionFactionQuery.whole_or_null(context.get("runtime_revision")))
	if not summarized.ok: return summarized
	if person_allocator_enabled(): _remember_person_source(_faction_site_key(checksum, site, path), person_projection(data.site))
	return _faction_remember(_faction_site_key(checksum, site, path), summarized.summary)

func _faction_source_receipt_seconds(summary: Dictionary, checksum: String, generation: Variant, previous: Dictionary, clock: Dictionary) -> Variant:
	# A committed receipt binds this same immutable owner/source after reopen.
	var coverage: Variant = previous.get("coverage")
	if coverage is Dictionary and coverage.get("sources") is Array:
		for raw: Variant in coverage.sources:
			if not raw is Dictionary or str(raw.get("owner", "")) != str(summary.owner) or raw.get("checksum") != checksum \
				or raw.get("source_generation") != generation or raw.get("runtime_revision") != summary.get("runtime_revision"): continue
			var accepted: Variant = raw.get("as_of_game_seconds")
			if not _seconds(accepted) or not _seconds(summary.at): continue
			var encoded: Variant = JSON.parse_string(JSON.stringify(float(accepted), "", false, true))
			var recorded: Variant = JSON.parse_string(JSON.stringify(float(summary.at), "", false, true))
			if encoded == recorded: return accepted
	return _faction_source_game_seconds(summary, clock)

func _faction_source_game_seconds(summary: Dictionary, clock: Dictionary) -> Variant:
	var stamp: Dictionary = summary.get("source_clock", {})
	if stamp.is_empty(): return summary.at
	var fire: Dictionary = clock.get("fire_clock", {})
	var indexed: Dictionary = fire.get("index", {}).get(str(summary.owner), {})
	if indexed.is_empty() or str(stamp.fire_epoch) != str(fire.get("epoch", "")) \
		or int(stamp.fire_sequence) != int(indexed.sequence): return summary.at
	# The saved JSON stamp identifies this exact original indexed endpoint.
	# Return its existing binary clock, never a rounded time or a substitute now.
	for field: String in ["game_seconds", "action_seconds"]:
		var original: Variant = indexed.get(field)
		if not _seconds(original): return summary.at
		var encoded: Variant = JSON.parse_string(JSON.stringify(float(original), "", false, true))
		if encoded != stamp.get(field): return summary.at
	return indexed.game_seconds

func _faction_read_party(path: String) -> Dictionary:
	var document: Dictionary = _read_document(path, 64 * 1024 * 1024)
	if not document.ok: return document
	var payload: Dictionary = document.payload
	if not _whole(payload.get("version"), 1, 1): return fail("SAVE_VERSION", "unknown party document schema")
	if payload.get("encoding") != "godot_var_v1" or not payload.get("party") is String or not _same_pin(payload.get("pin"), pin): return fail("CORRUPT_SAVE", "faction party version/pin")
	var raw: Variant = Marshalls.base64_to_raw(payload.party)
	var party: Variant = bytes_to_var(raw)
	if raw.is_empty() or Marshalls.raw_to_base64(raw) != payload.party or not party is Dictionary or var_to_bytes(party) != raw or not party.get("content") is Dictionary or not RegionTravel.validate_identity(party.content.get("travel_identity")): return fail("CORRUPT_SAVE", "faction party stable identity")
	if not _whole(party.get("version"), 1, RegionTravel.VERSION): return fail("SAVE_VERSION", "unknown party schema")
	if str(payload.get("token", "")) != str(party.get("party_id", "")): return fail("CORRUPT_SAVE", "faction party token")
	var patients: Variant = RegionTravel.validate_patients(party.content)
	if not patients.ok: return patients
	if party.get("kind") != "travel_party" or party.get("controller") not in ["player", "npc"]: return fail("CORRUPT_SAVE", "party original controller/kind")
	return {"ok": true, "party": party}

func _faction_party_source(path: String, checksum: String, with_persons: bool = false) -> Dictionary:
	var key: String = _faction_cache_context() + ":party:" + path + ":" + checksum
	var cached: Dictionary = _faction_cached(key)
	if not cached.is_empty() and (not with_persons or _person_source_cache.has(key)): return cached
	if not _faction_digest_valid(checksum): return fail("CORRUPT_SAVE", "faction source checksum")
	if not FileAccess.file_exists(path): return fail("CORRUPT_SAVE", "faction source file missing")
	var loaded: Dictionary = _faction_read_party(path)
	if _faction_file_sha256(path) != checksum: return fail("CORRUPT_SAVE", "faction party changed during validation")
	if not loaded.ok: return loaded
	var party: Dictionary = loaded.party
	if with_persons:
		var projection: Dictionary = person_projection(party.content)
		for local: String in party.get("arrival_mapping", {}).get("maps", {}).get("person", {}):
			if int(local) != int(party.arrival_mapping.maps.person[local]): projection["pending_remap"] = true
		_remember_person_source(key, projection)
	var summarized: Dictionary = _faction_summary(party.content, str(party.party_id), party.get("upkeep", {}).get("at"))
	if not summarized.ok: return summarized
	summarized.summary.controller = str(party.controller)
	return _faction_remember(key, summarized.summary)

func _faction_decode_clock(encoded: String) -> Dictionary:
	_faction_cache_context()
	var key: Variant = encoded.sha256_text()
	var cached: Variant = _faction_clock_cache.get(key, {})
	if cached is Dictionary and not cached.is_empty() and cached.get("clock") is Dictionary and cached.get("digest") is String and _faction_digest_matches(_faction_clock_digest_memo, str(key), cached.clock, cached.digest):
		return {"ok": true, "clock": cached.clock.duplicate(true)}
	var raw: Variant = Marshalls.base64_to_raw(encoded)
	if raw.is_empty() or Marshalls.raw_to_base64(raw) != encoded: return fail("CORRUPT_SAVE", "存檔槽 control 原 Variant Base64 非唯一格式")
	var decoded: Variant = bytes_to_var(raw)
	if not decoded is Dictionary or var_to_bytes(decoded) != raw: return fail("CORRUPT_SAVE", "存檔槽 control 原 Variant 字節非法")
	_faction_clock_cache.clear()
	_faction_clock_digest_memo.clear()
	var digest: String = _faction_digest_bytes(raw)
	_faction_clock_cache[key] = {"clock": decoded.duplicate(true), "digest": digest}
	_faction_clock_digest_memo[key] = {"bytes": raw, "digest": digest}
	return {"ok": true, "clock": decoded}

func _faction_joined_destination(token: String, clock: Dictionary, journey: Dictionary) -> Dictionary:
	var seen := {}
	var parties: Dictionary = clock.get("region_gameplay", {}).get("parties", {})
	for step in range(parties.size() + 1):
		if seen.has(token): return fail("FACTION_SCAN_INCOMPLETE", "joined party cycle")
		seen[token] = true
		var reference: Dictionary = parties.get(token, {})
		if journey.get("kind") == RegionTravel.KIND and str(journey.get("token", "")) == token: return {"ok": true}
		if reference.get("phase") != "joined":
			return {"ok": true} if reference.get("phase") in ["travelling", "pending_life", "materializing", "controlled", "entered"] else fail("FACTION_SCAN_INCOMPLETE", "joined destination missing")
		var next: Variant = reference.get("entered_party")
		if not next is String or next.is_empty(): return fail("FACTION_SCAN_INCOMPLETE", "joined destination missing")
		token = next
	return fail("FACTION_SCAN_INCOMPLETE", "joined destination chain")

func _faction_scan(sites: Dictionary, clock: Dictionary, journey: Dictionary, previous: Dictionary, reserved: Array = [], include_legacy: bool = true, with_persons: bool = false, with_organization_sources: bool = false) -> Dictionary:
	var states: Array[Dictionary] = []
	var person_sources: Array = []
	var organization_sources: Array = []
	var receipts: Array[Dictionary] = []
	var coordinates := {}
	if include_legacy:
		var known := _known_saved_sites_current()
		if not known.ok: return known
		for site: Vector2i in known.sites: coordinates[_site_key(site)] = site
	for key: String in sites:
		var pair: Variant = key.split(":")
		if pair.size() != 2 or not pair[0].is_valid_int() or not pair[1].is_valid_int(): return fail("CORRUPT_SAVE", "faction source coordinate")
		coordinates[key] = Vector2i(int(pair[0]), int(pair[1]))
	for key: String in coordinates:
		var coordinate: Vector2i = coordinates[key]
		var entry: Dictionary = sites.get(key, _marker.get("sites", {}).get(key, {}))
		var path: Variant = folder.path_join(str(entry.path)) if not entry.is_empty() else site_path(coordinate)
		# Recorded immutable digests are authoritative cache selectors. Only
		# unrecorded legacy Sites require a fresh digest before lookup.
		var checksum: String = str(entry.get("sha256", "")) if not entry.is_empty() else _faction_file_sha256(path)
		if not _faction_digest_valid(checksum): return fail("CORRUPT_SAVE", "faction source checksum")
		if not entry.is_empty() and (not str(entry.get("path", "")).begins_with("generations/") or not str(entry.path).ends_with(".json") or str(entry.path).contains("..") or str(entry.path).contains("\\") or str(entry.path).split("/").size() != 2): return fail("CORRUPT_SAVE", "faction source path")
		var loaded: Dictionary = _faction_site_source(path, coordinate, checksum, with_persons)
		if not loaded.ok: return loaded
		states.append(loaded.summary.live)
		if with_persons: person_sources.append({"projection": _person_source_cache[_faction_site_key(checksum, coordinate, path)], "location": {"kind": "site", "id": str(loaded.summary.owner)}})
		var prefix: Variant = path.get_file().split("_")[0]
		var source_generation: Variant = int(prefix) if not entry.is_empty() and prefix.length() == 20 and prefix.is_valid_int() else 0 if entry.is_empty() else null
		receipts.append({"owner": str(loaded.summary.owner), "source_generation": RegionFactionQuery.whole_or_null(source_generation), "runtime_revision": RegionFactionQuery.whole_or_null(loaded.summary.runtime_revision), "checksum": checksum, "as_of_game_seconds": _faction_source_receipt_seconds(loaded.summary, checksum, source_generation, previous, clock), "complete": true})
		if with_organization_sources: organization_sources.append({"kind": "site", "owner": str(loaded.summary.owner), "site": coordinate, "path": path, "checksum": checksum, "historical": false, "phase": "selected" if not entry.is_empty() else "legacy", "original_receipt": receipts.back().duplicate(true)})
	var references: Array[Dictionary] = []
	if journey.get("kind") == RegionTravel.KIND: references.append(journey)
	for token: String in clock.get("region_gameplay", {}).get("parties", {}):
		var reference: Dictionary = clock.region_gameplay.parties[token]
		if str(journey.get("token", "")) == token and journey.get("kind") == RegionTravel.KIND: continue # Journey selects this party's current document.
		if reference.get("phase") not in ["travelling", "pending_life", "materializing", "controlled", "entered", "joined"] or reference.get("party_path", "") == "": return fail("FACTION_SCAN_INCOMPLETE", "party owner/source unavailable")
		if reference.get("phase") == "joined":
			var destination: Dictionary = _faction_joined_destination(token, clock, journey)
			if not destination.ok: return destination
		references.append(reference)
	var seen := {}
	for reference: Dictionary in references:
		var path: String = str(reference.get("party_path", ""))
		var checksum: String = str(reference.get("party_sha256", ""))
		if not path.begins_with("travel/") or path.contains("..") or path.contains("\\") or not _faction_digest_valid(checksum): return fail("CORRUPT_SAVE", "faction party checksum/path")
		var loaded: Dictionary = _faction_party_source(folder.path_join(path), checksum, with_persons)
		if not loaded.ok: return loaded
		var summary: Dictionary = loaded.summary
		if str(reference.get("token", summary.owner)) != str(summary.owner): return fail("CORRUPT_SAVE", "faction party token")
		var historical: bool = reference.get("phase") in ["entered", "joined"]
		# Check each reference before dedupe; conflicting phase/owner cannot hide
		# behind another reference to the same bytes.
		var selected_key: Variant = checksum + (":history" if historical else ":live")
		if seen.has(selected_key): continue
		seen[selected_key] = true
		states.append(summary.historical if historical else summary.live)
		if with_persons:
			var person_key: String = _faction_cache_context() + ":party:" + folder.path_join(path) + ":" + checksum
			var persons: Dictionary = _person_source_cache[person_key]
			if not historical:
				for local: String in reference.get("arrival_mapping", {}).get("maps", {}).get("person", {}):
					if int(local) != int(reference.arrival_mapping.maps.person[local]):
						persons = persons.duplicate(true)
						persons["pending_remap"] = true
			if historical:
				persons = persons.duplicate(true)
				persons.bodies = []
				persons.erase("pending_remap")
			person_sources.append({"projection": persons, "location": {"kind": "party", "id": str(summary.owner)}})
		receipts.append({"owner": "party:" + str(summary.owner), "source_generation": null, "runtime_revision": null, "checksum": checksum, "as_of_game_seconds": summary.at, "complete": true})
		if with_organization_sources: organization_sources.append({"kind": "party", "owner": str(summary.owner), "path": folder.path_join(path), "checksum": checksum, "historical": historical, "phase": str(reference.get("phase", "travelling")), "original_receipt": receipts.back().duplicate(true)})
	# Battle participant fields and remote claims are projected by their original registry/Sites.
	var political_ids := {}
	var battle_ids: Variant = RegionFactionQuery.collect_ids(clock.get("region_gameplay", {}).get("battles", {}), political_ids)
	if not battle_ids.ok: return battle_ids
	var all_reserved: Array = reserved.duplicate()
	for id: String in political_ids: all_reserved.append(int(id))
	var result: Dictionary = RegionFactionQuery.migration(states, receipts, all_reserved, previous, float(clock.logical_game_seconds), true)
	if result.ok:
		result["person_sources"] = person_sources
		if with_organization_sources: result["organization_sources"] = organization_sources
	return result

## Explicit mapping only. Optional original nation record creates a new nation;
## existing legacy records are bound without changing membership or offices.
func prepare_faction_nation(data: TerrainData, nation_id: String, faction_id: int, original_nation: Dictionary = {}) -> Dictionary:
	if data == null or str(data.site.get("id", "")) != str(control.active_site_id): return fail("REGION_SOURCE")
	var registry := faction_registry_view()
	var checked: Variant = RegionFactionQuery.validate(registry, float(control.logical_game_seconds))
	if not checked.ok: return checked
	var selected: Dictionary = active_faction(faction_id)
	if not selected.ok: return selected
	if selected.entry.nation_ref != null: return fail("FACTION_ALREADY_BOUND")
	if nation_id.begins_with("trial_team_"): return fail("LEGACY_TRIAL_UNSUPPORTED")
	var source_hash: String = var_to_bytes(data.site).hex_encode().sha256_text()
	var prepared: Variant = SiteEquipmentOrders.prepare_faction_nation(data.site, nation_id, faction_id, original_nation)
	if not prepared.ok: return prepared
	var identity: Variant = RegionTravel.prepare_identity(prepared.state)
	if not identity.ok: return identity
	var ref: Dictionary = identity.state.travel_identity.refs.nation[nation_id]
	var candidate: Variant = registry.duplicate(true)
	candidate.entries[str(faction_id)].nation_ref = ref.duplicate(true)
	candidate.entries[str(faction_id)].leader_ref = null
	candidate.entries[str(faction_id)].erase("duty_ai")
	if int(candidate.revision) >= RegionFactionQuery.MAX_REVISION: return fail("FACTION_REVISION_EXHAUSTED")
	candidate.revision = int(candidate.revision) + 1
	var valid: Variant = RegionFactionQuery.validate(candidate, float(control.logical_game_seconds))
	if not valid.ok: return valid
	return {"ok": true, "source_generation": int(_marker.get("generation", 0)), "registry_revision": int(registry.revision), "source_hash": source_hash, "nation_id": nation_id, "faction_id": faction_id, "original_nation": original_nation.duplicate(true), "state": identity.state, "registry": candidate}

## The caller captures original scene owners first. No live nation mutation occurs
## until the exact common checkpoint has succeeded; returned data is its admitted candidate.
func checkpoint_faction_nation(data: TerrainData, prepared: Dictionary, context: Dictionary, owners: Dictionary) -> Dictionary:
	if data == null or not prepared.get("ok", false) or not prepared.get("original_nation") is Dictionary or not prepared.get("nation_id") is String or not RegionFactionQuery.whole(prepared.get("faction_id"), 0, RegionFactionQuery.MAX_ID) or int(prepared.get("source_generation", -1)) != int(_marker.get("generation", 0)) or int(prepared.get("registry_revision", -1)) != int(control.get("faction_registry", {}).get("revision", -2)) or prepared.get("source_hash") != var_to_bytes(data.site).hex_encode().sha256_text(): return fail("CONFLICT")
	var current: Dictionary = prepare_faction_nation(data, str(prepared.get("nation_id", "")), int(prepared.get("faction_id", -1)), prepared.get("original_nation", {}))
	if not current.ok: return current
	if current.state != prepared.get("state") or current.registry != prepared.get("registry"): return fail("CONFLICT", "binding candidate changed")
	var candidate: Variant = Env.navigation_for_state(data, current.state)
	return checkpoint_region_site(candidate, context, owners, prepared.registry)

## Explicit scenario reservations participate in the same detached full scan.
func prepare_faction_migration(reserved_ids: Array = []) -> Dictionary:
	var recovered: Dictionary = _recover_control()
	if not recovered.ok: return recovered
	var candidate: Dictionary = _faction_scan(_marker.get("sites", {}), control, _marker.get("journey", {}), faction_registry_view(), reserved_ids)
	if not candidate.ok: return candidate
	candidate.source_generation = int(_marker.get("generation", 0))
	candidate.registry_revision = int(control.get("faction_registry", {}).get("revision", 0))
	candidate.reserved_ids = reserved_ids.duplicate()
	return candidate

func checkpoint_faction_migration(data: TerrainData, prepared: Dictionary, context: Dictionary, owners: Dictionary) -> Dictionary:
	if not prepared.get("ok", false) or int(prepared.get("source_generation", -1)) != int(_marker.get("generation", 0)) or int(prepared.get("registry_revision", -1)) != int(control.get("faction_registry", {}).get("revision", 0)): return fail("CONFLICT")
	var current: Dictionary = prepare_faction_migration(prepared.get("reserved_ids", []))
	if not current.ok: return current
	if current.registry != prepared.get("registry"): return fail("CONFLICT", "migration sources changed")
	return checkpoint_region_site(data, context, owners, current.registry)

func prepare_faction_creation(data: TerrainData, expected_revision: int, reserved_ids: Array = [], fields: Dictionary = {}) -> Dictionary:
	if data == null or str(data.site.get("id", "")) != str(control.active_site_id): return fail("REGION_SOURCE")
	if int(control.get("faction_registry", {}).get("revision", 0)) != expected_revision: return fail("CONFLICT")
	var all_reserved: Array = reserved_ids.duplicate()
	var current_ids := {}
	var scanned: Variant = RegionFactionQuery.collect_ids(data.site, current_ids)
	if not scanned.ok: return scanned
	for id: String in current_ids: all_reserved.append(int(id))
	var migration: Dictionary = prepare_faction_migration(all_reserved)
	if not migration.ok: return migration
	var allocated: Variant = RegionFactionQuery.allocate(migration.registry, int(migration.registry.revision), float(control.logical_game_seconds), fields)
	if not allocated.ok: return allocated
	return {"ok": true, "source_generation": int(_marker.get("generation", 0)), "registry_revision": expected_revision, "source_hash": var_to_bytes(data.site).hex_encode().sha256_text(), "reserved_ids": reserved_ids.duplicate(), "registry": allocated.registry, "faction_id": allocated.faction_id}

func checkpoint_faction_creation(data: TerrainData, prepared: Dictionary, context: Dictionary, owners: Dictionary) -> Dictionary:
	if data == null or not prepared.get("ok", false) or int(prepared.get("source_generation", -1)) != int(_marker.get("generation", 0)) or prepared.get("source_hash") != var_to_bytes(data.site).hex_encode().sha256_text(): return fail("CONFLICT")
	var current: Dictionary = prepare_faction_creation(data, int(prepared.get("registry_revision", -1)), prepared.get("reserved_ids", []))
	if not current.ok: return current
	if current.registry != prepared.get("registry") or current.faction_id != prepared.get("faction_id"): return fail("CONFLICT", "allocator source changed")
	return checkpoint_region_site(data, context, owners, current.registry)

func nation_faction(state: Dictionary, nation_id: String) -> Dictionary:
	return RegionFactionQuery.bound_faction(control.get("faction_registry", {}), state, nation_id)

func faction_display(faction_id: int) -> Dictionary:
	return RegionFactionQuery.display(control.get("faction_registry", {}), faction_id)

# No admission authority: compare only AFTER complete original record validation.
# Typed control bytes remain exact; only JSON outer numeric coercion is tolerated.
func _faction_marker_same_wire(original: Dictionary, recorded: Dictionary) -> bool:
	const FIELDS: Array[String] = ["format", "generation", "pin", "sites", "control", "transfer_token", "journey"]
	if original.size() != FIELDS.size() or recorded.size() != FIELDS.size(): return false
	for key: Variant in original:
		if not key is String or key not in FIELDS: return false
	for key: Variant in recorded:
		if not key is String or key not in FIELDS: return false
	if not original.get("control") is Dictionary or not recorded.get("control") is Dictionary: return false
	if var_to_bytes(original.control) != var_to_bytes(recorded.control): return false
	var budget: Array[int] = [1048576]
	for field: String in FIELDS:
		if field != "control" and not _faction_json_outer_equal(original[field], recorded[field], budget, 0): return false
	return true

func _faction_json_outer_equal(original: Variant, recorded: Variant, budget: Array[int], depth: int) -> bool:
	budget[0] -= 1
	if budget[0] < 0 or depth > 128: return false
	var left_type: int = typeof(original)
	var right_type: int = typeof(recorded)
	if left_type != right_type:
		if left_type not in [TYPE_INT, TYPE_FLOAT] or right_type not in [TYPE_INT, TYPE_FLOAT]: return false
		return is_finite(float(original)) and is_finite(float(recorded)) and absf(float(original)) <= 9007199254740991.0 and absf(float(recorded)) <= 9007199254740991.0 and float(original) == float(recorded)
	if left_type == TYPE_DICTIONARY:
		if original.size() != recorded.size(): return false
		for key: Variant in original:
			if not key is String or not recorded.has(key) or not _faction_json_outer_equal(original[key], recorded[key], budget, depth + 1): return false
		for key: Variant in recorded:
			if not key is String: return false
		return true
	if left_type == TYPE_ARRAY:
		if original.size() != recorded.size(): return false
		for index: int in original.size():
			if not _faction_json_outer_equal(original[index], recorded[index], budget, depth + 1): return false
		return true
	if left_type == TYPE_FLOAT: return is_finite(float(original)) and is_finite(float(recorded)) and original == recorded
	return original == recorded if left_type in [TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING] else false

# Derived facts only. Custom Slot validators retain their original complete path.
var _faction_static_cold: bool = true
var _faction_static_reading: bool = false
static var _faction_static_site_cache: Dictionary:
	get:
		return Store.faction_summary_cache
static var _faction_static_site_memo: Dictionary:
	get:
		return Store.faction_summary_memo
static var _faction_static_site_metadata: Dictionary:
	get:
		return Store.faction_summary_metadata
static var _faction_static_site_mutex: Mutex:
	get:
		return Store._faction_summary_mutex

static func clear_faction_static_site_cache() -> void:
	Store.clear_faction_summary_cache()

func _faction_static_original_validator() -> bool:
	var original_script: Script = get_script()
	return original_script != null and original_script.resource_path == "res://scripts/region_lab/region_save_slot.gd" \
		and source != null and source.manifest_hash == str(pin.get("manifest_sha256", "")) \
		and source.author_identity_matches(pin) \
		and source.resource_manifest_hash == str(pin.get("resource_layer_sha256", "")) \
		and source.resource_rule_revision == str(pin.get("resource_rule_revision", ""))

func _faction_static_site_record(path: String, site: Vector2i, checksum: String) -> Dictionary:
	var serial: int = Store.faction_summary_serial()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var size: int = file.get_length()
	file.close()
	var modified: int = FileAccess.get_modified_time(path)
	var metadata: Dictionary = {"slot_path": folder, "site_path": Store.faction_summary_path(path), "record_path": path,
		"site": [site.x, site.y], "sha256": checksum, "scope": _faction_cache_scope, "mtime": modified, "size": size}
	return {"key": JSON.stringify(metadata, "", true, true), "metadata": metadata, "serial": serial}

func _faction_static_site_cached(record: Dictionary) -> Dictionary:
	var key: String = str(record.key)
	_faction_static_site_mutex.lock()
	var raw: Variant = _faction_static_site_cache.get(key)
	var known: Variant = _faction_static_site_memo.get(key)
	var stored_metadata: Variant = _faction_static_site_metadata.get(key)
	var current: bool = int(record.serial) == Store._faction_summary_serial
	var cached: Dictionary = raw.duplicate(true) if raw is Dictionary else {}
	var memo: Dictionary = known.duplicate(true) if known is Dictionary else {}
	var metadata: Dictionary = stored_metadata.duplicate(true) if stored_metadata is Dictionary else {}
	_faction_static_site_mutex.unlock()
	if not current: return {}
	if cached.is_empty() or var_to_bytes(metadata) != var_to_bytes(record.metadata):
		_faction_static_site_drop(key)
		return {}
	if not cached.get("summary") is Dictionary or not cached.get("digest") is String \
			or not memo.get("bytes") is PackedByteArray or not memo.get("digest") is String:
		_faction_static_site_drop(key)
		return {}
	var bytes: PackedByteArray = var_to_bytes(cached.summary)
	if bytes != memo.bytes or cached.digest != memo.digest or _faction_digest_bytes(bytes) != cached.digest:
		_faction_static_site_drop(key)
		return {}
	var result: Dictionary = {"ok": true, "summary": cached.summary}
	if cached.has("persons") or memo.has("persons_bytes"):
		# Optional person projection of the same validated file; checked like the summary.
		if not cached.get("persons") is Dictionary or not cached.get("persons_digest") is String or not memo.get("persons_bytes") is PackedByteArray:
			_faction_static_site_drop(key)
			return {}
		var person_bytes: PackedByteArray = var_to_bytes(cached.persons)
		if person_bytes != memo.persons_bytes or _faction_digest_bytes(person_bytes) != cached.persons_digest:
			_faction_static_site_drop(key)
			return {}
		result["persons"] = cached.persons
	return result

func _faction_static_site_remember(record: Dictionary, summary: Dictionary, persons: Variant = null) -> void:
	var key: String = str(record.key)
	var bytes: PackedByteArray = var_to_bytes(summary)
	var digest: String = _faction_digest_bytes(bytes)
	var cached: Dictionary = {"summary": summary.duplicate(true), "digest": digest}
	var memo: Dictionary = {"bytes": bytes, "digest": digest}
	if persons is Dictionary:
		var person_bytes: PackedByteArray = var_to_bytes(persons)
		cached["persons"] = persons.duplicate(true)
		cached["persons_digest"] = _faction_digest_bytes(person_bytes)
		memo["persons_bytes"] = person_bytes
	_faction_static_site_mutex.lock()
	if int(record.serial) != Store._faction_summary_serial:
		_faction_static_site_mutex.unlock()
		return
	if _faction_static_site_cache.size() >= FACTION_SOURCE_CACHE_LIMIT and not _faction_static_site_cache.has(key):
		var evicted: Variant = _faction_static_site_cache.keys()[0]
		_faction_static_site_cache.erase(evicted)
		_faction_static_site_memo.erase(evicted)
		_faction_static_site_metadata.erase(evicted)
	_faction_static_site_cache[key] = cached
	_faction_static_site_memo[key] = memo
	_faction_static_site_metadata[key] = record.metadata.duplicate(true)
	_faction_static_site_mutex.unlock()

func _faction_static_site_drop(key: String) -> void:
	_faction_static_site_mutex.lock()
	_faction_static_site_cache.erase(key)
	_faction_static_site_memo.erase(key)
	_faction_static_site_metadata.erase(key)
	_faction_static_site_mutex.unlock()

## Neutral part 2: exactly one saved army holds the created player, as its only unit and formal commander, in the neutral faction.
static func _created_player_team(state: Dictionary, identity: int) -> bool:
	var found := 0
	for army: Variant in state.get("armies", []):
		if not army is Dictionary or not army.get("units") is Array: continue
		for unit: Variant in army.units:
			if unit is Dictionary and int(unit.get("person_id", -1)) == identity:
				found += 1
				# The player is unit 0 and formal captain of the neutral start team (with its cadres, Nekki 2026-11-03).
				if int(army.units[0].get("person_id", -1)) != identity or int(army.get("formal_commander", -1)) != 0 or int(army.get("faction_id", -1)) != RegionFactionQuery.NEUTRAL_FACTION_ID: return false
	return found == 1

func _check_author_initial_state(data: TerrainData, record: Dictionary, coordinate: Vector2i, path: String) -> Dictionary:
	var state: Dictionary = data.site
	var context: Dictionary = _initialization.author_context
	var bodies: Dictionary = RegionTravel._body_records(state)
	var controlled: int = int(state.get("controlled_person_id", -1))
	if not bodies.has(controlled) or not RegionTravel._able(bodies[controlled]) or not _initial_site_same(bodies[controlled].get("cell"), context.start.cell) or state.has("initial_scenario") or state.has("crowd") or int(state.minute) != 0 or float(state.phase) != 0.0: return fail("INVALID_INITIAL_POPULATION")
	if context.start.mode == "created_player":
		# Neutral part 2: the created player is roster unit 0 and formal commander of a one-person neutral team, not an actor.
		if controlled != 1 or not state.get("actors", {}).is_empty() or not _created_player_team(state, controlled): return fail("INVALID_INITIAL_POPULATION")
	elif controlled != int(context.start.person_id): return fail("INVALID_INITIAL_POPULATION")
	var rows: Array = state.get("residents", [])
	var housing: Dictionary = state.get("housing", {})
	if not rows.is_empty():
		var matched: Dictionary = {}
		for row: Dictionary in rows:
			var found: bool = false
			for army: Dictionary in state.get("armies", []):
				if army.get("role") != "work": continue
				for unit: Dictionary in army.units:
					var id: String = str(int(unit.person_id))
					var home: Dictionary = housing.get(id, {})
					if matched.has(id) or unit.get("name", "") != row.name or int(army.faction_id) != int(row.faction_id) or home.get("house_id") != row.house: continue
					var layout: Dictionary = Runtime.house_layout(data, str(row.house))
					if not layout.ok or not layout.slots.has(int(home.get("cell", -1))): return fail("INVALID_INITIAL_POPULATION")
					matched[id] = true
					found = true
					break
				if found: break
			if not found: return fail("INVALID_INITIAL_POPULATION")
	var settled: Dictionary = validate_settlement(state, 0.0)
	var fire: Dictionary = validate_fire_settlement(state, record.control.get("fire_clock", {}))
	if not settled.ok or settled.legacy or float(settled.pending) != 0.0 or not fire.ok or int(record.control.fire_clock.sequence) != 0 or float(record.control.fire_clock.action_seconds) != 0.0: return fail("INVALID_INITIAL_GENERATION")
	return {"ok": true, "data": data, "coordinate": coordinate, "path": path}

# World identity is an index over original Site/party bodies, never a second body store.
const PERSON_ID_LIMIT := 2147483647
const PERSON_RESERVED_ID := 1000000000
var _person_pending: Dictionary = {}
var _person_upgrade_error: Dictionary = {}
var _person_allocation_owners: Array[String] = []
var _person_scope := ""
var _person_nonce := ""
var _person_generation: int = -1
var _person_source_cache: Dictionary = {}

func _remember_person_source(key: String, projection: Dictionary) -> void:
	if _person_source_cache.size() >= FACTION_SOURCE_CACHE_LIMIT and not _person_source_cache.has(key): _person_source_cache.erase(_person_source_cache.keys()[0])
	_person_source_cache[key] = projection

static func person_allocator_empty(world: String) -> Dictionary:
	return {"version": 1, "world_instance_id": world, "next_person_id": 1, "aliases": {}, "locations": {}}

static func person_allocator_valid(value: Variant, world: String) -> bool:
	if not value is Dictionary or value.size() != 5 or not _whole(value.get("version"), 1, 1) or world.is_empty() or value.get("world_instance_id") != world or not _whole(value.get("next_person_id"), 1, PERSON_ID_LIMIT) or int(value.next_person_id) == PERSON_RESERVED_ID or not value.get("aliases") is Dictionary or not value.get("locations") is Dictionary: return false
	var inverse: Dictionary = {}
	for key: Variant in value.aliases:
		if not key is String or not _whole(value.aliases[key], 1, PERSON_ID_LIMIT - 1) or int(value.aliases[key]) == PERSON_RESERVED_ID or int(value.aliases[key]) >= int(value.next_person_id): return false
		var parsed: Variant = JSON.parse_string(key)
		if not parsed is Array or parsed.size() != 3 or parsed[0] != "person" or not parsed[1] is String or str(parsed[1]).is_empty() or not RegionTravel._identity_integer(parsed[2], 1, RegionTravel.MAX_IDENTITY_SEQUENCE): return false
		if RegionTravel.stable_key({"type": "person", "namespace": parsed[1], "lineage": parsed[2]}) != key or inverse.has(str(int(value.aliases[key]))): return false
		inverse[str(int(value.aliases[key]))] = key
	for key: Variant in value.locations:
		if not key is String or not key.is_valid_int() or str(int(key)) != key or int(key) < 1 or int(key) >= int(value.next_person_id) or int(key) == PERSON_RESERVED_ID: return false
		var location: Variant = value.locations[key]
		if not location is Dictionary or location.size() != 2 or location.get("kind") not in ["site", "party"] or not location.get("id") is String or str(location.id).is_empty(): return false
	return true

static func person_range(value: Dictionary, count: int, floor_id: int = 1) -> Dictionary:
	if not person_allocator_valid(value, str(value.get("world_instance_id", ""))) or count < 0 or count > PERSON_ID_LIMIT or floor_id < 1 or floor_id > PERSON_ID_LIMIT: return fail("INVALID_PERSON_ALLOCATOR")
	var begin: int = maxi(int(value.next_person_id), floor_id)
	if begin <= PERSON_RESERVED_ID and begin + count > PERSON_RESERVED_ID or begin == PERSON_RESERVED_ID: begin = PERSON_RESERVED_ID + 1
	if begin + count > PERSON_ID_LIMIT: return fail("PERSON_ID_EXHAUSTED")
	var ids: Array[int] = []
	for offset: int in count: ids.append(begin + offset)
	var candidate: Dictionary = value.duplicate(true)
	candidate.next_person_id = begin + count
	if int(candidate.next_person_id) == PERSON_RESERVED_ID: candidate.next_person_id = PERSON_RESERVED_ID + 1
	if not person_allocator_valid(candidate, str(value.world_instance_id)): return fail("INVALID_PERSON_ALLOCATOR")
	return {"ok": true, "allocator": candidate, "ids": ids}

static func person_projection(state: Dictionary) -> Dictionary:
	var bodies: Dictionary = RegionTravel._body_records(state)
	var refs: Dictionary = state.get("travel_identity", {}).get("refs", {}).get("person", {})
	var rows: Array[Dictionary] = []
	for id: int in bodies:
		rows.append({"id": id, "alias": RegionTravel.stable_key(refs[str(id)]) if refs.has(str(id)) else ""})
	var aliases: Dictionary = {}
	for id: String in refs: aliases[RegionTravel.stable_key(refs[id])] = int(id)
	return {"bodies": rows, "aliases": aliases, "next_person_id": int(state.get("next_person_id", 1))}

static func person_migration(world: String, sources: Array, previous: Dictionary = {}) -> Dictionary:
	var candidate: Dictionary = person_allocator_empty(world) if previous.is_empty() else previous.duplicate(true)
	if not person_allocator_valid(candidate, world): return fail("INVALID_PERSON_ALLOCATOR")
	for raw: Variant in sources:
		if not raw is Dictionary: return fail("PERSON_SCAN_INCOMPLETE")
	var inverse: Dictionary = {}
	for key: String in candidate.aliases: inverse[str(int(candidate.aliases[key]))] = key
	candidate.locations = {}
	# Current bodies establish the number; historical local numbers never overwrite that alias.
	for source_record: Dictionary in sources:
		if not source_record.get("projection") is Dictionary or not source_record.get("location") is Dictionary: return fail("PERSON_SCAN_INCOMPLETE")
		var projection: Dictionary = source_record.projection
		if projection.get("pending_remap", false): return fail("PERSON_MIGRATION_PENDING")
		if not _whole(projection.get("next_person_id"), 1, PERSON_ID_LIMIT) or not projection.get("bodies") is Array or not projection.get("aliases") is Dictionary: return fail("PERSON_SCAN_INCOMPLETE")
		candidate.next_person_id = maxi(int(candidate.next_person_id), int(projection.get("next_person_id", 1)))
		for raw: Variant in projection.bodies:
			if not raw is Dictionary or not raw.get("alias", "") is String: return fail("PERSON_SCAN_INCOMPLETE")
			var row: Dictionary = raw
			if not _whole(row.get("id"), 1, PERSON_ID_LIMIT - 1) or int(row.id) == PERSON_RESERVED_ID: return fail("INVALID_PERSON_ID")
			var id: String = str(int(row.id))
			var alias: String = str(row.get("alias", ""))
			if candidate.locations.has(id): return fail("PERSON_ID_COLLISION", id)
			if alias.is_empty() and inverse.has(id): return fail("PERSON_ALIAS_UNRESOLVED", id)
			if not alias.is_empty():
				if candidate.aliases.has(alias) and int(candidate.aliases[alias]) != int(id): return fail("PERSON_ID_REMAP_REQUIRED", alias)
				if inverse.has(id) and inverse[id] != alias: return fail("PERSON_ID_COLLISION", id)
				candidate.aliases[alias] = int(id)
				inverse[id] = alias
			candidate.locations[id] = source_record.location.duplicate(true)
			candidate.next_person_id = maxi(int(candidate.next_person_id), int(id) + 1)
	for source_record: Dictionary in sources:
		for alias: Variant in source_record.projection.aliases:
			if not alias is String or not _whole(source_record.projection.aliases[alias], 1, PERSON_ID_LIMIT - 1): return fail("INVALID_PERSON_ID")
			if candidate.aliases.has(alias): continue
			var id: int = int(source_record.projection.aliases[alias])
			if candidate.locations.has(str(id)) and not inverse.has(str(id)): return fail("PERSON_ALIAS_UNRESOLVED", str(id))
			if inverse.has(str(id)) and inverse[str(id)] != alias: return fail("PERSON_ID_COLLISION", str(id))
			candidate.aliases[alias] = id
			inverse[str(id)] = alias
			candidate.next_person_id = maxi(int(candidate.next_person_id), id + 1)
	if int(candidate.next_person_id) == PERSON_RESERVED_ID: candidate.next_person_id = PERSON_RESERVED_ID + 1
	if not person_allocator_valid(candidate, world): return fail("INVALID_PERSON_ALLOCATOR")
	return {"ok": true, "allocator": candidate}

func person_allocator_enabled() -> bool:
	return not _person_pending.is_empty() and _person_upgrade_error.is_empty()

func person_allocator_view() -> Dictionary:
	return _person_pending.duplicate(true)

func prepare_person_migration() -> Dictionary:
	var scan: Dictionary = _faction_scan(_marker.get("sites", {}), control, _marker.get("journey", {}), faction_registry_view(), [], true, true)
	if not scan.ok: return scan
	return person_migration(str(pin.world_instance_id), scan.person_sources, control.get("person_allocator", {}))

func _open_person_allocator(prepare_new: bool) -> Dictionary:
	var scope: String = folder + ":" + str(pin.world_instance_id)
	if _person_scope != scope:
		_person_scope = scope
		_person_nonce = Crypto.new().generate_random_bytes(16).hex_encode()
		_person_pending = {}
		_person_generation = -1
		_person_source_cache.clear()
		_person_upgrade_error = {}
		_person_allocation_owners.clear()
	var generation: int = int(_marker.get("generation", 0))
	if not _person_pending.is_empty() and _person_generation != generation:
		if not _person_allocation_owners.is_empty():
			_person_upgrade_error = fail("PERSON_ALLOCATION_CONFLICT")
			return _person_upgrade_error
		_person_pending = {}
		_person_upgrade_error = {}
	if person_allocator_enabled(): return {"ok": true}
	var prepared: Dictionary
	if _marker.is_empty() and prepare_new:
		var sources: Array = []
		for pair: Array in source.author_initial_context().get("expected_initial_sites", []):
			var initial: Dictionary = source.project_terrain(Vector2i(int(pair[0]), int(pair[1])), "author_initial")
			if not initial.ok: return initial
			var projection: Dictionary = person_projection(initial.data.site)
			if projection.bodies.is_empty(): projection.next_person_id = 1
			sources.append({"projection": projection, "location": {"kind": "site", "id": str(initial.data.site.get("id", initial.base.site_id))}})
		prepared = person_migration(str(pin.world_instance_id), sources)
	else: prepared = prepare_person_migration()
	if not prepared.ok:
		_person_upgrade_error = prepared.duplicate(true)
		# Legacy collision refuses only upgrade; its original world still opens.
		return prepared if prepare_new or control.has("person_allocator") else {"ok": true, "upgrade_refused": prepared}
	_person_pending = prepared.allocator
	_person_generation = generation
	_person_upgrade_error = {}
	return {"ok": true}

func attach_person_allocator(data: TerrainData) -> void:
	if data == null: return
	if data.site.has("world_pin") and not _same_pin(data.site.world_pin, pin): return
	var ticket: Dictionary = {"scope": _person_scope, "world_instance_id": str(pin.world_instance_id), "nonce": _person_nonce}
	data.set_meta(&"world_person_allocator", Callable(self, "allocate_person_ids").bind(ticket))

func allocate_person_ids(count: int, data: TerrainData, floor_id: int = 1, ticket: Dictionary = {}) -> Array[int]:
	var empty: Array[int] = []
	if ticket.get("scope") != _person_scope or ticket.get("world_instance_id") != pin.get("world_instance_id") or ticket.get("nonce") != _person_nonce: return empty
	if data != null and data.site.has("world_pin") and not _same_pin(data.site.world_pin, pin): return empty
	if not person_allocator_enabled() or data == null: return empty
	var base: Variant = data.parameters.get("fixed_base")
	if not base is Dictionary or not base.get("site") is Array or base.site.size() != 2 or not _whole(base.site[0], -2147483648, 2147483647) or not _whole(base.site[1], -2147483648, 2147483647): return empty
	if not _matches_base(base, Vector2i(int(base.site[0]), int(base.site[1]))): return empty
	var generation: int = int(_marker.get("generation", 0))
	var recovered: Dictionary = _recover_control()
	if not recovered.ok or int(_marker.get("generation", 0)) != generation or _person_generation != generation:
		_person_upgrade_error = fail("PERSON_ALLOCATION_CONFLICT")
		return empty
	var prepared: Dictionary = person_range(_person_pending, count, floor_id)
	if not prepared.ok: return empty
	_person_pending = prepared.allocator
	_person_allocation_owners.append(str(data.site.id))
	return prepared.ids

func person_allocation_checkpoint() -> Dictionary:
	return {"scope": folder, "nonce": _person_nonce, "generation": int(_marker.get("generation", 0)), "pending_generation": _person_generation, "allocator": _person_pending.duplicate(true), "owners": _person_allocation_owners.size()}

func rollback_person_allocation(checkpoint: Dictionary, allowed_owners: Array = []) -> bool:
	if checkpoint.get("scope") != folder or checkpoint.get("nonce") != _person_nonce or int(checkpoint.get("generation", -1)) != int(_marker.get("generation", 0)) or int(checkpoint.get("pending_generation", -2)) != _person_generation or (not _person_pending.is_empty() and _person_generation != int(_marker.get("generation", 0))) or not checkpoint.get("allocator") is Dictionary: return false
	var begin: int = int(checkpoint.get("owners", -1))
	if begin < 0 or begin > _person_allocation_owners.size(): return false
	for owner: String in _person_allocation_owners.slice(begin):
		if not allowed_owners.is_empty() and owner not in allowed_owners: return false
	_person_pending = checkpoint.allocator.duplicate(true)
	_person_allocation_owners.resize(begin)
	return true

## Peerage step 3: the fief index of the faction registry follows this Site's settlement (head seat holder, level and
## owner faction) at every checkpoint. A registry without peerage is left alone.
## Titles of people who died in the active Site: [{dead_ref, heir_ref or null}], applied (family rule) at the next
## checkpoint and cleared once it publishes.
var pending_peerage_inheritance: Array = []
## Closed battles of the active Site (RegionBattleLog), joined to the registry at the next checkpoint.
var pending_battles: Array = []
## Settlement falls of the active Site (RegionDiplomacy.record_fall), applied at the next checkpoint.
var pending_falls: Array = []

func _peerage_reconcile_site(next_clock: Dictionary, data: TerrainData) -> Dictionary:
	var registry: Variant = next_clock.get("faction_registry", {})
	if registry is Dictionary and not pending_battles.is_empty() and registry.get("version") == RegionFactionQuery.VERSION:
		for battle: Dictionary in pending_battles:
			var logged: Dictionary = RegionBattleLog.add(registry, battle, float(next_clock.logical_game_seconds))
			if logged.ok: registry = logged.registry
		next_clock.faction_registry = registry
	if registry is Dictionary and not pending_falls.is_empty() and registry.get("version") == RegionFactionQuery.VERSION:
		for fall: Dictionary in pending_falls:
			var noted: Dictionary = RegionDiplomacy.record_fall(registry, str(fall.site_id), int(fall.from), int(fall.to), float(next_clock.logical_game_seconds))
			if noted.ok: registry = noted.registry
		next_clock.faction_registry = registry
	if not registry is Dictionary or not registry.get("peerage") is Dictionary: return {"ok": true}
	for death: Dictionary in pending_peerage_inheritance:
		if RegionPeerage.record_of(registry, death.dead_ref).is_empty(): continue
		var inherited: Dictionary = RegionPeerage.inherit(registry, death.dead_ref, death.heir_ref, float(next_clock.logical_game_seconds))
		if inherited.ok: registry = inherited.registry
	next_clock.faction_registry = registry
	var settlement: Dictionary = data.site.get("settlement", {})
	var level := 0
	var owner := -1
	var holder_ref: Variant = null
	if not settlement.is_empty():
		level = int(settlement.get("level", 0))
		owner = int(settlement.get("owner_faction", -1))
		var holder := int(SiteOffices.head_position(settlement.get("offices", {})).get("holder", 0))
		if holder > 0: holder_ref = peerage_person_ref(holder)
	var reconciled: Dictionary = RegionPeerage.reconcile_site(registry, str(data.site.get("id", "")), level, holder_ref, owner, float(next_clock.logical_game_seconds))
	if not reconciled.ok: return reconciled
	if reconciled.changed: next_clock.faction_registry = reconciled.registry
	return {"ok": true}

## The typed person ref the peerage uses: a historical alias when one exists, else the world-scoped live ref.
func peerage_person_ref(person_id: int) -> Variant:
	var resolved: Dictionary = resolve_person_reference(person_reference(person_id))
	if not resolved.get("ok", false): return null
	if RegionFactionQuery.ref_valid(resolved.get("typed_ref", {}), "person"): return resolved.typed_ref
	if resolved.get("status") == "current": return RegionPeerage.world_person_ref(str(pin.world_instance_id), person_id)
	return null

func person_reference(person_id: int) -> Dictionary:
	if not person_allocator_enabled() or not _person_pending.locations.has(str(person_id)): return {}
	return {"world_instance_id": str(pin.world_instance_id), "person_id": person_id}

func resolve_person_reference(reference: Dictionary) -> Dictionary:
	if reference.size() != 2 or reference.get("world_instance_id") != pin.get("world_instance_id") or not _whole(reference.get("person_id"), 1, PERSON_ID_LIMIT - 1) or int(reference.person_id) == PERSON_RESERVED_ID or not person_allocator_enabled(): return fail("INVALID_PERSON_REF")
	var id: String = str(int(reference.person_id))
	var typed: Dictionary = {}
	for key: String in _person_pending.aliases:
		if int(_person_pending.aliases[key]) != int(reference.person_id): continue
		var parts: Array = JSON.parse_string(key)
		typed = {"type": parts[0], "namespace": parts[1], "lineage": int(parts[2])}
		break
	if not _person_pending.locations.has(id) and typed.is_empty(): return fail("UNKNOWN_PERSON_REF")
	return {"ok": true, "status": "current" if _person_pending.locations.has(id) else "historical", "reference": reference.duplicate(true), "typed_ref": typed, "location": _person_pending.locations.get(id, {}).duplicate(true)}

func _insert_people(state: Dictionary, party: Dictionary, nav: TerrainData, entry: Vector2i, path: String, departure: float, arrival: float, options: Dictionary = {}) -> Dictionary:
	var settings: Dictionary = options.duplicate(true)
	settings["preserve_person_ids"] = person_allocator_enabled()
	return RegionTravel.insert(state, party, nav, entry, path, departure, arrival, settings)

## P6-B1 read-only preflight. All recovery/cache work belongs to a disposable
## original Slot reader; no live control, allocator or source file is replaced.
func prepare_organization_migration(expected: Dictionary = {}) -> Dictionary:
	var organizations: GDScript = preload("res://scripts/region_lab/region_organization_registry.gd")
	var generation: int = int(_marker.get("generation", 0))
	if generation < 1 or source == null or not _same_pin(pin, pin): return fail("ORGANIZATION_SOURCE_REQUIRED")
	if not expected.is_empty() and (expected.size() != 2 or not _same_pin(expected.get("pin"), pin) or not _whole(expected.get("generation"), generation, generation)): return fail("ORGANIZATION_PREFLIGHT_CONFLICT")
	var snapshot: Dictionary = {"generation": generation, "pin": pin.duplicate(true), "folder": folder,
		"control": var_to_bytes(control), "marker": var_to_bytes(_marker)}
	var probe: RegionSaveSlot = RegionSaveSlot.new()
	probe.source = source
	probe.pin = pin.duplicate(true)
	probe.folder = folder
	probe.control = control.duplicate(true)
	probe._marker = _marker.duplicate(true)
	var commit_path: String = folder.path_join("commits/%020d.json" % generation)
	snapshot["commit_sha256"] = _faction_file_sha256(commit_path)
	if not _faction_digest_valid(snapshot.commit_sha256): return fail("ORGANIZATION_SOURCE_CHANGED")
	var latest: Dictionary = probe._recover_read_latest(false, {})
	if not latest.ok: return latest
	if latest.get("empty", false) or int(latest.recorded.generation) != generation: return fail("ORGANIZATION_PREFLIGHT_CONFLICT")
	probe._marker = latest.recorded
	probe.control = latest.recorded.control.duplicate(true)
	if _faction_file_sha256(commit_path) != snapshot.commit_sha256: return fail("ORGANIZATION_SOURCE_CHANGED")
	var scanned: Dictionary = probe._faction_scan(probe._marker.sites, probe.control, probe._marker.journey, probe.faction_registry_view(), [], true, true, true)
	if not scanned.ok: return scanned
	var persons: Dictionary = person_migration(str(pin.world_instance_id), scanned.person_sources, probe.control.get("person_allocator", {}))
	if not persons.ok: return persons
	var sources: Array = []
	var provenance: Array = []
	var site_keys: Array[String] = []
	for descriptor: Dictionary in scanned.organization_sources:
		if _faction_file_sha256(descriptor.path) != descriptor.checksum: return fail("ORGANIZATION_SOURCE_CHANGED")
		var state: Dictionary
		if descriptor.kind == "site":
			site_keys.append(_site_key(descriptor.site))
			var loaded: Dictionary = probe._load_checked(descriptor.path, descriptor.site)
			if not loaded.ok: return loaded
			state = loaded.data.site.duplicate(true)
			if not _same_pin(state.get("world_pin"), pin): return fail("ORGANIZATION_PIN_MISMATCH")
		else:
			var loaded: Dictionary = probe._faction_read_party(descriptor.path)
			if not loaded.ok: return loaded
			state = loaded.party.content.duplicate(true)
			if not loaded.party.get("origin_site_id") is String or loaded.party.origin_site_id.is_empty(): return fail("ORGANIZATION_PARTY_BODY_CONTEXT_REQUIRED")
			state["id"] = loaded.party.origin_site_id
		if _faction_file_sha256(descriptor.path) != descriptor.checksum: return fail("ORGANIZATION_SOURCE_CHANGED")
		sources.append({"kind": descriptor.kind, "owner": str(descriptor.kind) + ":" + str(descriptor.owner), "historical": descriptor.historical, "state": state})
		var receipt: Dictionary = descriptor.duplicate(true)
		if receipt.has("site"): receipt.site = [descriptor.site.x, descriptor.site.y]
		receipt["pin"] = pin.duplicate(true)
		receipt["selected_generation"] = generation
		provenance.append(receipt)
	site_keys.sort()
	snapshot["site_keys"] = site_keys
	var prepared: Dictionary = organizations.migrate_sources(str(pin.world_instance_id), generation, sources, persons.allocator, person_allocator_valid)
	if not prepared.ok: return prepared
	var unchanged: Dictionary = _organization_preflight_unchanged(snapshot, provenance)
	if not unchanged.ok: return unchanged
	prepared["pin"] = pin.duplicate(true)
	prepared["base_generation"] = generation
	prepared["commit_sha256"] = snapshot.commit_sha256
	prepared["source_receipts"] = provenance
	prepared["person_allocator"] = persons.allocator
	return prepared

func _organization_preflight_unchanged(snapshot: Dictionary, receipts: Array) -> Dictionary:
	if folder != snapshot.folder or not _same_pin(pin, snapshot.pin) or int(_marker.get("generation", 0)) != int(snapshot.generation) or var_to_bytes(control) != snapshot.control or var_to_bytes(_marker) != snapshot.marker: return fail("ORGANIZATION_PREFLIGHT_CONFLICT")
	var known: Dictionary = _known_saved_sites_current()
	if not known.ok: return known
	var coordinates: Dictionary = {}
	for coordinate: Vector2i in known.sites: coordinates[_site_key(coordinate)] = true
	for key: String in _marker.get("sites", {}): coordinates[key] = true
	var site_keys: Array = coordinates.keys()
	site_keys.sort()
	if site_keys != snapshot.site_keys: return fail("ORGANIZATION_SOURCE_CHANGED")
	var directory: DirAccess = DirAccess.open(folder.path_join("commits"))
	if directory == null: return fail("ORGANIZATION_SOURCE_CHANGED")
	var latest: int = 0
	for name: String in directory.get_files():
		var stem: String = name.trim_suffix(".json")
		if name.ends_with(".json") and stem.length() == 20 and stem.is_valid_int(): latest = maxi(latest, int(stem))
	if latest != int(snapshot.generation): return fail("ORGANIZATION_PREFLIGHT_CONFLICT")
	if _faction_file_sha256(folder.path_join("commits/%020d.json" % latest)) != snapshot.commit_sha256: return fail("ORGANIZATION_SOURCE_CHANGED")
	for receipt: Dictionary in receipts:
		if _faction_file_sha256(receipt.path) != receipt.checksum: return fail("ORGANIZATION_SOURCE_CHANGED")
	return {"ok": true}

## P6-B2: one private prepared proposal per original Slot. No Site aliases,
## live writer, record editing or durable organization authority is installed.
var _organization_stage: Dictionary = {}

func _organization_stage_owner(data: TerrainData, lab: TerrainLab) -> Dictionary:
	if data == null or lab == null or not _same_pin(data.site.get("world_pin"), pin): return fail("ORGANIZATION_STAGE_BIND_REQUIRED")
	if lab.terrain != data or lab._region_bound_data != data or lab.site_controller == null or lab.site_controller.region_slot != self or _region_bound_original_lab(data) != lab: return fail("ORGANIZATION_STAGE_BIND_REQUIRED")
	var receipt: Dictionary = lab.region_bind_receipt(data)
	if lab.restore_only or not receipt.get("complete", false) or receipt.get("mode") != "live" or receipt.get("consumer") != "original_site": return fail("ORGANIZATION_STAGE_BIND_REQUIRED")
	return {"ok": true}

func _organization_stage_body_digest(data: TerrainData) -> String:
	var registry: GDScript = preload("res://scripts/region_lab/region_organization_registry.gd")
	return registry.digest({"family": data.site.get("family"), "nations": data.site.get("equipment_nations", {}), "identity": data.site.get("travel_identity", {})})

## Admission always reruns original B1 provenance, never accepts caller-supplied
## registry bodies. A successful replacement revokes the previous capability.
func stage_organization_registry(data: TerrainData, lab: TerrainLab) -> Dictionary:
	var owner: Dictionary = _organization_stage_owner(data, lab)
	if not owner.ok: return owner
	var before: String = _organization_stage_body_digest(data)
	if before.is_empty(): return fail("UNSUPPORTED_ORGANIZATION_TYPE")
	var proposal: Dictionary = prepare_organization_migration({"pin": pin.duplicate(true), "generation": int(_marker.get("generation", 0))})
	if not proposal.ok: return proposal
	owner = _organization_stage_owner(data, lab)
	if not owner.ok: return owner
	if _organization_stage_body_digest(data) != before: return fail("ORGANIZATION_STAGE_STALE")
	var token: Dictionary = {"nonce": Crypto.new().generate_random_bytes(16).hex_encode(),
		"slot_instance_id": get_instance_id(), "lab_instance_id": lab.get_instance_id(), "data_instance_id": data.get_instance_id(),
		"folder": folder, "generation": int(proposal.base_generation), "pin": pin.duplicate(true)}
	_organization_stage = {"ticket": token.duplicate(true), "proposal": proposal.duplicate(true), "lab": weakref(lab), "data": weakref(data), "body_digest": before}
	return {"ok": true, "ticket": token, "state": "prepared_only", "snapshot_kind": "committed_sources", "live_authority": false,
		"read": Callable(self, "read_organization_stage").bind(token.duplicate(true))}

func _organization_stage_guard(ticket: Dictionary) -> Dictionary:
	var lifecycle: GDScript = preload("res://scripts/region_lab/region_organization_stage.gd")
	var admitted: Dictionary = lifecycle.authenticate(ticket, _organization_stage.get("ticket", {}))
	if not admitted.ok: return admitted
	var data: TerrainData = _organization_stage.data.get_ref()
	var lab: TerrainLab = _organization_stage.lab.get_ref()
	var owner: Dictionary = _organization_stage_owner(data, lab)
	if not owner.ok: return owner
	var current: Dictionary = {"slot_instance_id": get_instance_id(), "lab_instance_id": lab.get_instance_id(), "data_instance_id": data.get_instance_id(),
		"folder": folder, "generation": int(_marker.get("generation", 0)), "pin": pin}
	admitted = lifecycle.guard(ticket, _organization_stage.ticket, current)
	if not admitted.ok: return admitted
	if _organization_stage_body_digest(data) != _organization_stage.body_digest: return fail("ORGANIZATION_STAGE_STALE")
	var proposal: Dictionary = _organization_stage.proposal
	var site_keys: Array[String] = []
	for receipt: Dictionary in proposal.source_receipts:
		if receipt.kind == "site": site_keys.append(_site_key(Vector2i(int(receipt.site[0]), int(receipt.site[1]))))
	site_keys.sort()
	# Original B1 guard verifies the immutable sources and selected generation.
	# Live time may advance between explicit reads without changing that epoch.
	var snapshot: Dictionary = {"generation": int(proposal.base_generation), "pin": proposal.pin, "folder": folder,
		"control": var_to_bytes(control), "marker": var_to_bytes(_marker), "commit_sha256": proposal.commit_sha256, "site_keys": site_keys}
	return _organization_preflight_unchanged(snapshot, proposal.source_receipts)

func read_organization_stage(ticket: Dictionary) -> Dictionary:
	var admitted: Dictionary = _organization_stage_guard(ticket)
	if not admitted.ok: return admitted
	return {"ok": true, "state": "prepared_only", "snapshot_kind": "committed_sources", "live_authority": false, "proposal": _organization_stage.proposal.duplicate(true)}

## Closing remains available after a world/owner change, but requires the exact
## capability. No live body or original archive is touched by cleanup.
func release_organization_stage(ticket: Dictionary) -> Dictionary:
	var lifecycle: GDScript = preload("res://scripts/region_lab/region_organization_stage.gd")
	var admitted: Dictionary = lifecycle.authenticate(ticket, _organization_stage.get("ticket", {}))
	if not admitted.ok: return admitted
	_organization_stage = {}
	return {"ok": true}

func activate_organization_registry(ticket: Dictionary, data: TerrainData, lab: TerrainLab) -> Dictionary:
	var admitted: Dictionary = _organization_stage_guard(ticket)
	if not admitted.ok: return admitted
	var owner: Dictionary = _organization_stage_owner(data, lab)
	if not owner.ok: return owner
	if _organization_stage.data.get_ref() != data or _organization_stage.lab.get_ref() != lab: return fail("ORGANIZATION_STAGE_BIND_REQUIRED")
	# Domain writers and Store/CAS must migrate together before any live alias.
	return fail("ORGANIZATION_ACTIVATION_REQUIRES_MIGRATION", "原領域寫入與 Store/CAS 正文遷移尚未完成；保留原 Site 權威")

## P6-B3 record transactions remain inside the B2 private stage. Replacing or
## releasing that stage releases its draft, views and opaque checkpoints too.
func begin_organization_edit(ticket: Dictionary) -> Dictionary:
	var admitted: Dictionary = _organization_stage_guard(ticket)
	if not admitted.ok: return admitted
	if _organization_stage.has("edit"): return read_organization_edit(ticket)
	var proposal: Dictionary = _organization_stage.proposal
	var contexts: Dictionary = {}
	for receipt: Dictionary in proposal.source_receipts:
		var owner: String = str(receipt.kind) + ":" + str(receipt.owner)
		if receipt.kind != "site" or not proposal.bindings.has(owner): continue
		var refs: Dictionary = proposal.bindings[owner]
		if refs.nation_refs.is_empty() and refs.family_ref == null: continue
		var loaded: Dictionary = _load_checked(receipt.path, Vector2i(int(receipt.site[0]), int(receipt.site[1])))
		if not loaded.ok: return loaded
		contexts[owner] = loaded.data.site.duplicate(true)
	var operations: GDScript = preload("res://scripts/region_lab/region_organization_edit.gd")
	var valid: Dictionary = operations.validate(proposal.registry, proposal.registry, contexts, proposal.bindings, proposal.identities, proposal.person_allocator)
	if not valid.ok: return valid
	admitted = _organization_stage_guard(ticket)
	if not admitted.ok: return admitted
	_organization_stage["edit"] = operations.create(proposal.registry, contexts)
	return _organization_edit_snapshot()

func _organization_edit_guard(ticket: Dictionary, revision: int = -1) -> Dictionary:
	var admitted: Dictionary = _organization_stage_guard(ticket)
	if not admitted.ok: return admitted
	if not _organization_stage.has("edit"): return fail("ORGANIZATION_EDIT_REQUIRED")
	if revision >= 0 and revision != int(_organization_stage.edit.revision): return fail("ORGANIZATION_EDIT_CONFLICT")
	return {"ok": true}

func read_organization_edit(ticket: Dictionary) -> Dictionary:
	var admitted: Dictionary = _organization_edit_guard(ticket)
	if not admitted.ok: return admitted
	return _organization_edit_snapshot()

func _organization_edit_snapshot() -> Dictionary:
	return {"ok": true, "state": "private_edit", "live_authority": false, "publishable": false, "validation": "record_schema_only",
		"revision": int(_organization_stage.edit.revision), "registry": _organization_stage.edit.registry.duplicate(true)}

func _organization_edit_key(kind: String, reference: Dictionary) -> Dictionary:
	var registry: GDScript = preload("res://scripts/region_lab/region_organization_registry.gd")
	if kind not in ["nation", "family"] or not registry.reference_valid(reference, kind): return fail("ORGANIZATION_EDIT_IDENTITY")
	var key: String = RegionTravel.stable_key(reference)
	var records: Dictionary = _organization_stage.edit.registry.nations if kind == "nation" else _organization_stage.edit.registry.families
	if not records.has(key): return fail("ORGANIZATION_RECORD_RETIRED")
	return {"ok": true, "key": key}

func organization_edit_record(ticket: Dictionary, kind: String, reference: Dictionary) -> Dictionary:
	var admitted: Dictionary = _organization_edit_guard(ticket)
	if not admitted.ok: return admitted
	var selected: Dictionary = _organization_edit_key(kind, reference)
	if not selected.ok: return selected
	var edit: Dictionary = _organization_stage.edit
	if not edit.views.has(selected.key):
		var view_script: GDScript = preload("res://scripts/region_lab/region_organization_record_view.gd")
		edit.views[selected.key] = view_script.new(self, ticket, kind, selected.key, int(edit.epochs.get(selected.key, 0)))
	return {"ok": true, "view": edit.views[selected.key], "state": "private_edit", "live_authority": false}

func _read_organization_edit_record(ticket: Dictionary, kind: String, key: String, epoch: int) -> Dictionary:
	var admitted: Dictionary = _organization_edit_guard(ticket)
	if not admitted.ok: return admitted
	var edit: Dictionary = _organization_stage.edit
	var records: Dictionary = edit.registry.nations if kind == "nation" else edit.registry.families
	if not records.has(key) or int(edit.epochs.get(key, 0)) != epoch: return fail("ORGANIZATION_RECORD_RETIRED")
	return {"ok": true, "state": "private_edit", "live_authority": false, "revision": int(edit.revision), "reference": records[key].reference.duplicate(true), "record": records[key].record.duplicate(true)}

## No external validator or validation flag is accepted. Record schemas and
## Person membership come from original owners and captured immutable sources.
func mutate_organization_edit(ticket: Dictionary, revision: int, kind: String, reference: Dictionary, candidate: Dictionary = {}, remove: bool = false) -> Dictionary:
	var admitted: Dictionary = _organization_edit_guard(ticket, revision)
	if not admitted.ok: return admitted
	if revision < 0 or revision >= 2147483647: return fail("ORGANIZATION_EDIT_CONFLICT")
	var selected: Dictionary = _organization_edit_key(kind, reference)
	if not selected.ok: return selected
	var edit: Dictionary = _organization_stage.edit
	var proposed: Dictionary = edit.registry.duplicate(true)
	var operations: GDScript = preload("res://scripts/region_lab/region_organization_edit.gd")
	var records: Dictionary = operations.table(proposed, kind)
	if remove:
		proposed.retired[selected.key] = records[selected.key].reference.duplicate(true)
		records.erase(selected.key)
	else: records[selected.key].record = candidate.duplicate(true)
	var original: Dictionary = _organization_stage.proposal
	var valid: Dictionary = operations.validate(proposed, edit.base, edit.contexts, original.bindings, original.identities, original.person_allocator)
	if not valid.ok: return valid
	if remove: operations.delete_record(edit, kind, selected.key)
	else: operations.replace_record(edit, kind, selected.key, candidate)
	return _organization_edit_snapshot()

func checkpoint_organization_edit(ticket: Dictionary, revision: int) -> Dictionary:
	var admitted: Dictionary = _organization_edit_guard(ticket, revision)
	if not admitted.ok: return admitted
	if revision < 0: return fail("ORGANIZATION_EDIT_CONFLICT")
	var operations: GDScript = preload("res://scripts/region_lab/region_organization_edit.gd")
	var identity: String = Crypto.new().generate_random_bytes(16).hex_encode()
	_organization_stage.edit.checkpoints[identity] = operations.checkpoint(_organization_stage.edit)
	return {"ok": true, "checkpoint": identity, "revision": revision, "state": "private_edit", "publishable": false}

func rollback_organization_edit(ticket: Dictionary, revision: int, checkpoint_identity: String) -> Dictionary:
	var admitted: Dictionary = _organization_edit_guard(ticket, revision)
	if not admitted.ok: return admitted
	if revision < 0 or revision >= 2147483647: return fail("ORGANIZATION_EDIT_CONFLICT")
	var edit: Dictionary = _organization_stage.edit
	if not edit.checkpoints.has(checkpoint_identity): return fail("ORGANIZATION_EDIT_CHECKPOINT")
	var checkpoint_value: Dictionary = edit.checkpoints[checkpoint_identity]
	var operations: GDScript = preload("res://scripts/region_lab/region_organization_edit.gd")
	var original: Dictionary = _organization_stage.proposal
	var valid: Dictionary = operations.validate(checkpoint_value.snapshot, edit.base, edit.contexts, original.bindings, original.identities, original.person_allocator)
	if not valid.ok: return valid
	operations.rollback(edit, checkpoint_value)
	return _organization_edit_snapshot()

## The first domain writer may target only its actual bound Site/family.
## This resolves identity; caller/physical eligibility stays in Family.
func organization_family_edit_target(ticket: Dictionary, revision: int, data: TerrainData, family_owner: RefCounted) -> Dictionary:
	var admitted: Dictionary = _organization_edit_guard(ticket, revision)
	if not admitted.ok: return admitted
	var original: TerrainLab = _organization_stage.lab.get_ref()
	if data == null or original == null or _organization_stage.data.get_ref() != data or original.terrain != data or original.site_controller.family_continuity != family_owner or data.has_meta(&"region_party_owner"): return fail("ORGANIZATION_FAMILY_SITE_REQUIRED")
	var owner: String = "site:" + str(data.site.id)
	var saved: Dictionary = _organization_stage.proposal
	if not saved.bindings.has(owner) or saved.bindings[owner].family_ref == null: return fail("ORGANIZATION_SAVED_FAMILY_REQUIRED")
	var key: String = str(saved.bindings[owner].family_ref)
	if not _organization_stage.edit.registry.families.has(key): return fail("ORGANIZATION_RECORD_RETIRED")
	var live: Variant = data.site.get("family")
	var family_schema: GDScript = preload("res://scripts/terrain_lab/site_family_continuity.gd")
	if not family_schema.validate_family(live, str(data.site.id)): return fail("UNREGISTERED")
	var operations: GDScript = preload("res://scripts/region_lab/region_organization_edit.gd")
	if not operations.identity_same("family", saved.registry.families[key].record, live): return fail("ORGANIZATION_FAMILY_IDENTITY_CHANGED")
	# Original issuer runs only on a detached state, never commits a new sequence.
	var identity: Dictionary = RegionTravel.prepare_identity(data.site)
	if not identity.ok: return identity
	if RegionTravel.stable_key(identity.state.travel_identity.refs.family.get("controlled", {})) != key: return fail("ORGANIZATION_FAMILY_IDENTITY_CHANGED")
	return {"ok": true, "family": _organization_stage.edit.registry.families[key].record.duplicate(true), "reference": saved.registry.families[key].reference.duplicate(true)}


## Same B4 saved Site binding rule for the original EquipmentOrders nation owner.
func organization_nation_edit_target(ticket: Dictionary, revision: int, data: TerrainData, nation_owner: RefCounted, nation_id: String) -> Dictionary:
	var admitted: Dictionary = _organization_edit_guard(ticket, revision)
	if not admitted.ok: return admitted
	var original: TerrainLab = _organization_stage.lab.get_ref()
	if data == null or original == null or _organization_stage.data.get_ref() != data or original.terrain != data or original.site_controller.equipment_orders != nation_owner or data.has_meta(&"region_party_owner"): return fail("ORGANIZATION_NATION_SITE_REQUIRED")
	var owner: String = "site:" + str(data.site.id)
	var saved: Dictionary = _organization_stage.proposal
	if not saved.bindings.has(owner) or not saved.bindings[owner].nation_refs.has(nation_id): return fail("ORGANIZATION_SAVED_NATION_REQUIRED")
	var key: String = str(saved.bindings[owner].nation_refs[nation_id])
	if not _organization_stage.edit.registry.nations.has(key): return fail("ORGANIZATION_RECORD_RETIRED")
	var nations: Variant = data.site.get("equipment_nations", {})
	if not nations is Dictionary or not nations.get(nation_id) is Dictionary: return fail("ORGANIZATION_NATION_IDENTITY_CHANGED")
	var schema: GDScript = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
	if not schema.valid_nations(nations, data.site.get("item_definitions", {}), RegionTravel._body_records(data.site), data.site): return fail("INVALID_ORIGINAL_NATIONS")
	var operations: GDScript = preload("res://scripts/region_lab/region_organization_edit.gd")
	if not operations.identity_same("nation", saved.registry.nations[key].record, nations[nation_id]): return fail("ORGANIZATION_NATION_IDENTITY_CHANGED")
	var identity: Dictionary = RegionTravel.prepare_identity(data.site)
	if not identity.ok: return identity
	if RegionTravel.stable_key(identity.state.travel_identity.refs.nation.get(nation_id, {})) != key: return fail("ORGANIZATION_NATION_IDENTITY_CHANGED")
	return {"ok": true, "nation": _organization_stage.edit.registry.nations[key].record.duplicate(true), "reference": saved.registry.nations[key].reference.duplicate(true)}

## Departure strips the former body snapshot. Its JSON fire stamp still names
## the original journal point; preserve that binary point in the new index.
static func _region_departure_fire_endpoint(watermark: Dictionary, clock: Dictionary) -> Dictionary:
	var checked: Dictionary = validate_fire_settlement({"fire_settlement": watermark}, clock)
	if not checked.ok: return checked
	var sequence: int = int(watermark.sequence)
	var original: Dictionary = {}
	if sequence == int(clock.get("base_sequence", 0)):
		original = {"game_seconds": clock.get("base_game_seconds"), "action_seconds": clock.get("base_action_seconds", 0.0)}
	else:
		for row: Dictionary in clock.get("journal", []):
			if int(row.last_sequence) == sequence:
				original = {"game_seconds": row.game_end, "action_seconds": row.action_end}
				break
	# An interior compressed point has no exact binary endpoint here. Do not
	# interpolate, clamp, or substitute the current world's time.
	for field: String in ["game_seconds", "action_seconds"]:
		if not _seconds(original.get(field)): return {"ok": true, "watermark": watermark}
		var encoded: Variant = JSON.parse_string(JSON.stringify(float(original[field]), "", false, true))
		if encoded != watermark.get(field): return {"ok": true, "watermark": watermark}
	var exact: Dictionary = watermark.duplicate(true)
	for field: String in ["game_seconds", "action_seconds"]: exact[field] = float(original[field])
	return {"ok": true, "watermark": exact}
