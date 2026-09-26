class_name SiteStore
extends RefCounted

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const EquipmentOrders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const CaptiveEscort = preload("res://scripts/terrain_lab/site_captive_escort.gd")
const FamilyContinuity = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const WorkTeam = preload("res://scripts/terrain_lab/site_work_team.gd")
const Vehicles = preload("res://scripts/terrain_lab/site_vehicle_transport.gd")
const RiderAtlas = preload("res://scripts/terrain_lab/site_vehicle_rider_atlas.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const FORMAT := 3
const TERRAIN_VERSION := 1
const DEFAULT_PATH := "user://sites/current.json"
const MAX_BYTES := 8 * 1024 * 1024

static func save(data: TerrainData, path: String = DEFAULT_PATH) -> Dictionary:
	if data == null or data.site.is_empty():
		return Runtime.fail("NO_TARGET")
	if not data.site.get("armies", []) is Array:
		return Runtime.fail("CORRUPT_SAVE", "軍隊快照格式")
	if bool(data.site.get("army_trial_active", false)) and data.site.get("armies", []).is_empty():
		return Runtime.fail("BUSY", "軍隊交戰快照尚未接入；請明確結束近戰測試後保存，避免默默遺失傷亡")
	if float(data.site.combat_left) > 0.0:
		return Runtime.fail("BUSY", "地圖保存會等到脫戰；本版不保存戰鬥中的角色與投射物")
	var state: Dictionary = data.site.duplicate(true)
	if not state.has("actors"):
		state["actors"] = {}
	if not state.has("armies"):
		state["armies"] = []
	var item_migration := Runtime.initialize_item_storage(state)
	if not item_migration.ok:
		return item_migration
	var item_validation := _validate_items(data, state)
	if not item_validation.ok:
		return item_validation
	var army_validation := _validate_armies(data, state, true)
	if not army_validation.ok:
		return army_validation
	var vehicle_validation := _validate_vehicles(data, state, true)
	if not vehicle_validation.ok:
		return vehicle_validation
	var army_assets := _validate_army_assets(data, state)
	if not army_assets.ok:
		return army_assets
	var actor_validation := _validate_actors(data, state)
	if not actor_validation.ok:
		return actor_validation
	var cape_validation := _validate_cape_roles(state)
	if not cape_validation.ok: return cape_validation
	var allocator_validation := _validate_person_allocator(state)
	if not allocator_validation.ok:
		return allocator_validation
	var supply_validation := _validate_supply(state)
	if not supply_validation.ok:
		return supply_validation
	var opened_validation := _validate_settled_opened_food(state)
	if not opened_validation.ok:
		return opened_validation
	state.erase("water_links")
	state.erase("water_status")
	state["notices"] = []
	var params: Dictionary = data.parameters.duplicate()
	params["size"] = [data.size.x, data.size.y]
	var payload := {"format": FORMAT, "terrain_version": TERRAIN_VERSION, "environment_version": Env.VERSION,
		"preset": data.preset, "seed": data.seed_value, "parameters": params, "state": state}
	var body := JSON.stringify(payload, "", true, true)
	var envelope := JSON.stringify({"checksum": body.sha256_text(), "payload": body}, "\t")
	if envelope.to_utf8_buffer().size() > MAX_BYTES:
		return Runtime.fail("SAVE_TOO_LARGE", "存檔超過 8 MiB，原存檔保留；未刪除任何現場物資")
	var absolute := ProjectSettings.globalize_path(path)
	var result := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if result != OK:
		return Runtime.fail("SAVE_IO", error_string(result))
	var temp_path := absolute + ".tmp"
	var backup_path := absolute + ".bak"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return Runtime.fail("SAVE_IO", error_string(FileAccess.get_open_error()))
	file.store_string(envelope)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK or FileAccess.get_file_as_string(temp_path) != envelope:
		return Runtime.fail("SAVE_IO", "暫存檔寫入校驗失敗，原存檔保留")
	var had_original := FileAccess.file_exists(absolute)
	if had_original:
		if FileAccess.file_exists(backup_path):
			result = DirAccess.remove_absolute(backup_path)
			if result != OK:
				return Runtime.fail("SAVE_IO", error_string(result))
		result = DirAccess.rename_absolute(absolute, backup_path)
		if result != OK:
			return Runtime.fail("SAVE_IO", error_string(result))
	result = DirAccess.rename_absolute(temp_path, absolute)
	if result != OK:
		if had_original:
			DirAccess.rename_absolute(backup_path, absolute)
		return Runtime.fail("SAVE_IO", "替換失敗，保留／恢復上一份存檔")
	return Runtime.ok("地圖已保存", {"path": path})

static func load_site(path: String = DEFAULT_PATH) -> Dictionary:
	var decoded := _read(path)
	if not decoded.ok:
		return decoded
	var payload: Dictionary = decoded.payload
	if not payload.state.get("id") is String:
		return Runtime.fail("CORRUPT_SAVE", "地圖身分")
	var params: Dictionary = payload.parameters.duplicate(true)
	params["size"] = Vector2i(int(params.size[0]), int(params.size[1]))
	var data := TerrainGenerator.generate(int(payload.preset), int(payload.seed), params)
	Env.initialize(data, str(payload.state.id))
	# Army paths and final slots must be checked against the terrain that was
	# actually saved. Validate the delta before applying it to this new data.
	var saved_terrain_changes: Variant = payload.state.get("terrain_changes", {})
	if not saved_terrain_changes is Dictionary:
		return Runtime.fail("CORRUPT_SAVE", "整地差異")
	for key: Variant in saved_terrain_changes.keys():
		if not key is String or not key.is_valid_int() or not _valid_cell(data, int(key)) or not _integer(saved_terrain_changes[key], 0, 5):
			return Runtime.fail("CORRUPT_SAVE", "整地差異")
		data.height_levels[int(key)] = int(saved_terrain_changes[key])
	if not saved_terrain_changes.is_empty():
		Runtime.rebuild_terrain_edges(data)
	var validation := _validate_state(data, payload.state)
	if not validation.ok:
		return validation
	var legacy_ko_clock := false
	for actor: Dictionary in payload.state.get("actors", {}).values():
		legacy_ko_clock = legacy_ko_clock or actor.get("schema") == 1
	for team: Dictionary in payload.state.get("armies", []):
		legacy_ko_clock = legacy_ko_clock or team.get("schema") == 1
	data.site = payload.state.duplicate(true)
	# JSON numbers are normalized at the boundary; generated base is not in the save.
	_normalize_state(data.site)
	data.site.minute = int(data.site.minute)
	data.site.next_feature = int(data.site.next_feature)
	data.site.depot_cell = int(data.site.depot_cell)
	data.site.capacity = int(data.site.capacity)
	data.site.worker.cell = int(data.site.worker.cell)
	data.site.worker.progress = float(data.site.worker.progress)
	data.site.worker.mode = "idle" if str(data.site.worker.target).is_empty() else "travel"
	data.site.combat_left = 0.0
	data.site.water_links = {}
	data.site.water_status = {}
	data.site.notices = []
	Env.rebuild_indexes(data)
	Runtime.rebuild_water(data)
	Runtime.rebuild_loot_index(data)
	if not data.is_walkable(data.cell_from_index(int(data.site.worker.cell))) or not data.is_walkable(data.cell_from_index(int(data.site.get("player_cell", data.site.depot_cell)))):
		return Runtime.fail("CORRUPT_SAVE", "角色位於阻擋格")
	var actors: Dictionary = data.site.get("actors", {})
	for key: String in actors:
		var actor_cell := Vector2i(int(actors[key].cell[0]), int(actors[key].cell[1]))
		if not data.is_walkable(actor_cell):
			return Runtime.fail("CORRUPT_SAVE", "人物快照位於阻擋格")
	var army_validation := _validate_armies(data, data.site, true)
	if not army_validation.ok:
		return army_validation
	var vehicle_validation := _validate_vehicles(data, data.site, true)
	if not vehicle_validation.ok:
		return vehicle_validation
	var army_assets := _validate_army_assets(data, data.site, true)
	if not army_assets.ok:
		return army_assets
	# Earlier format-3 deaths may have left real opened food at their private
	# owner. Migrate the validated loaded copy only, never rewrite the source file
	# or rerun the original person's death/animation/equipment initialization.
	var opened_migration := Runtime.migrate_settled_opened_food(data)
	if not opened_migration.ok:
		return opened_migration
	var opened_validation := _validate_settled_opened_food(data.site)
	if not opened_validation.ok:
		return opened_validation
	return Runtime.ok("已載入地圖；接續保存時刻" + ("（舊地圖沒有角色快照，首次使用初始角色狀態）" if bool(payload.get("legacy_actor_state", false)) else "") + ("（舊版昏迷剩餘秒數已按比例一次轉為遊戲秒）" if legacy_ko_clock else ""), {"data": data})

static func retire_default_worker(data: TerrainData) -> Dictionary:
	# The removed startup fixture must not respawn from an older save. This is
	# the same ground-stock departure contract as before_clear_team_items: retain
	# every physical item, and refuse to erase an established person's relations.
	# Generic snapshot reads and explicit NPC fixtures retain their original owner.
	if not data.site.get("actors", {}).has("npc") and Runtime.inventory_size(data.site.worker.cargo) == 0:
		return Runtime.ok()
	var original: Dictionary = data.site
	data.site = original.duplicate(true)
	var result := _retire_default_worker_copy(data)
	if not result.ok:
		data.site = original
		Runtime.rebuild_loot_index(data)
	return result

static func _retire_default_worker_copy(data: TerrainData) -> Dictionary:
	var state: Dictionary = data.site
	var actors: Dictionary = state.get("actors", {})
	var body: Dictionary = actors.get("npc", {})
	var identity := int(body.get("person_id", 2))
	var cargo: Dictionary = state.worker.cargo
	if body.is_empty():
		# Format-1 worker cargo has no actor snapshot. Its original fixed identity
		# may be used only when no surviving person already owns that identity.
		for actor: Dictionary in actors.values():
			if int(actor.person_id) == identity: return Runtime.fail("BUSY", "舊工人物資的原身分已被占用；原存檔保留")
		for team: Dictionary in state.get("armies", []):
			for unit: Dictionary in team.units:
				if int(unit.person_id) == identity: return Runtime.fail("BUSY", "舊工人物資的原身分已被占用；原存檔保留")
	if not body.is_empty():
		if int(state.get("controlled_person_id", -1)) == identity:
			return Runtime.fail("BUSY", "舊工人仍是受控人物；原存檔保留，不能自動刪除原人物")
		for relative: Dictionary in state.get("family", {}).get("members", []):
			if str(relative.site_id) == str(state.id) and int(relative.person_id) == identity:
				return Runtime.fail("BUSY", "舊工人已列家族名單；原存檔保留，不能自動刪除家人")
		for nation: Dictionary in state.get("equipment_nations", {}).values():
			if nation.members.has(identity) or int(nation.military_head) == identity:
				return Runtime.fail("BUSY", "舊工人仍有國別／職務引用；原存檔保留")
		if bool(body.captive):
			return Runtime.fail("BUSY", "舊工人仍受拘押；原存檔保留")
		for key: String in state.get("captivity", {}):
			var relation: Dictionary = state.captivity[key]
			if int(key) == identity or int(relation.captor_id) == identity or int(relation.guard_id) == identity:
				return Runtime.fail("BUSY", "舊工人仍有俘虜／看守關係；原存檔保留")
		for key: String in state.get("escort_orders", {}):
			if int(key) == identity or state.escort_orders[key].captives.has(identity):
				return Runtime.fail("BUSY", "舊工人仍有押送關係；原存檔保留")
		for actor: Dictionary in actors.values():
			if float(actor._rescue_left) > 0.0 and (int(actor.person_id) == identity or int(actor.rescue_target) == identity):
				return Runtime.fail("BUSY", "舊工人仍有救助關係；原存檔保留")
		for team: Dictionary in state.get("armies", []):
			if int(team.get("player_member", {}).get("id", -1)) == identity or int(team.get("pursuit_target", -1)) == identity:
				return Runtime.fail("BUSY", "舊工人仍有隊伍／追擊關係；原存檔保留")
		for vehicle: Dictionary in state.get("vehicles", {}).values():
			if int(vehicle.get("operator_id", -1)) == identity:
				return Runtime.fail("BUSY", "舊工人仍是原車輛操作人；原存檔保留")
		for key: String in state.get("person_supply", {}):
			for member: int in Sustain._ids(state.person_supply[key]):
				if int(key) == identity and member != identity or int(key) != identity and member == identity:
					return Runtime.fail("BUSY", "舊工人仍與他人共用餐份歷史；原存檔保留")
		for supply: Dictionary in state.get("team_supply", {}).values():
			if identity in Sustain._ids(supply.sustain):
				return Runtime.fail("BUSY", "舊工人仍屬原隊伍供養；原存檔保留")
	var holder: Dictionary = body.get("item_state", {})
	if holder.is_empty():
		if body.is_empty():
			holder = Runtime.new_item_state("person:%d" % identity)
		else:
			var seeded := Runtime.seed_person_equipment(data, holder, identity, body.appearance)
			if not seeded.ok: return seeded
	var pool: Dictionary = state.get("person_supply", {}).get(str(identity), {})
	var dropped := Runtime.leave_ground_loot(data, holder, cargo, identity, data.cell_from_index(int(state.worker.cell)), "cargo", cargo, holder.item_ids.duplicate(), int(holder.version), pool, float(pool.get("open_rations", 0.0)))
	if not dropped.ok and str(dropped.code) != "EMPTY": return dropped
	state.get("person_supply", {}).erase(str(identity))
	actors.erase("npc")
	for actor: Dictionary in actors.values():
		if int(actor.get("attack_target", 0)) == identity: actor.attack_target = 0
		actor.hit_ids.erase(identity)
	for team: Dictionary in state.get("armies", []):
		for unit: Dictionary in team.units:
			if int(unit.get("target", -1)) == identity: unit.target = -1
			unit.hits.erase(identity)
	if state.has("next_person_id"):
		state.next_person_id = maxi(int(state.next_person_id), identity + 1)
	state.worker_enabled = false
	state.worker.merge({"target": "", "action": "harvest", "progress": 0.0, "mode": "idle", "status": "開場測試工人已移除", "zone": -1, "manual_control": false}, true)
	return _validate_state(data, state)

static func _validate_army_assets(data: TerrainData, state: Dictionary, fresh: bool = false) -> Dictionary:
	if state.get("armies", []).is_empty(): return Runtime.ok()
	if not TerrainArmy.load_combat_bake():
		return Runtime.fail("MISSING_ASSET", "軍隊圖集／碰撞資料缺失；未替換目前地圖")
	if fresh:
		TerrainArmy.EquipmentAtlas.refresh_female_sources()
	var checked := {}
	for original: Dictionary in state.armies:
		for unit: Dictionary in TerrainArmy.normalize_roster_snapshot(original).units:
			if str(unit.visual_role).ends_with("live") or not unit.has("appearance"):
				continue # Legacy rows without equipment retain the admitted baseline.
			var appearance: Dictionary = unit.appearance
			if unit.has("item_state"):
				var holder: Dictionary = unit.item_state
				if float(unit.hp) <= 0.0 and bool(unit.get("loot_settled", false)):
					holder = state.ground_loot.get(str(unit.get("remains_id", "")), Runtime.new_item_state("empty-remains"))
				appearance = Runtime.equipment_appearance(data, holder, appearance, state)
			var key := JSON.stringify(appearance)
			if checked.has(key): continue
			var baseline: bool = not appearance.is_empty() and appearance.get("body") == 0 and HumanCharacter3DEditor.EquipmentDye.geometry_appearance(appearance) == TerrainArmy._combat_bake.manifest.appearance and TerrainArmy.EquipmentAtlas.DyeAtlas.supports(appearance)
			if not baseline and not TerrainArmy.EquipmentAtlas.supports(appearance):
				return Runtime.fail("MISSING_ASSET", "人物 #%d 的實際配裝缺少完整圖集／染色；未替換目前地圖或存檔" % int(unit.person_id))
			checked[key] = true
	return Runtime.ok()

static func _validate_cape_roles(state: Dictionary) -> Dictionary:
	# Called only after existing people, roster and item validation. Read original
	# identities/holders, including legacy appearance-only people; never mint ranks
	# or rewrite the incoming save to make an unsupported costume appear valid.
	var people: Dictionary = {}
	var permitted := {}
	for actor: Dictionary in state.get("actors", {}).values():
		people[int(actor.person_id)] = actor
	for nation: Dictionary in state.get("equipment_nations", {}).values():
		var identity := int(nation.military_head)
		if EquipmentOrders._member(nation, identity): permitted[identity] = true
	for original: Dictionary in state.get("armies", []):
		var team := TerrainArmy.normalize_roster_snapshot(original)
		var service: Array = team.get("officer_service", team.officers)
		for index in range(team.units.size()):
			var row: Dictionary = team.units[index]
			var identity := int(row.person_id)
			people[identity] = row
			if bool(row.get("member", true)) and not bool(row.get("departed", false)) and EquipmentOrders.rank_grants_cape(index, int(team.formal_commander), service, team.officers):
				permitted[identity] = true
		if not team.get("player_member", {}).is_empty() and EquipmentOrders.rank_grants_cape(TerrainArmy.PLAYER_MEMBER, int(team.formal_commander), service, team.officers):
			permitted[int(team.player_member.id)] = true
	for identity: int in people:
		var person: Dictionary = people[identity]
		if float(person.hp) <= 0.0 or permitted.has(identity): continue
		var wears_cape: bool = person.item_state.equipped.has("cape") if person.has("item_state") else str(person.get("appearance", {}).get("parts", {}).get("cape", "none")) != "none"
		if wears_cape:
			return Runtime.fail("CAPE_ROLE_RESTRICTED", "原人物 %d 並非現任軍官以上；披風須先卸回本人行囊，未替換現場或改寫存檔" % identity)
	return Runtime.ok()

static func _normalize_state(state: Dictionary) -> void:
	if state.has("controlled_person_id"):
		state.controlled_person_id = int(state.controlled_person_id)
	if state.has("family"):
		state.family.version = int(state.family.version)
		for member: Dictionary in state.family.members:
			member.person_id = int(member.person_id)
			member.age_years = int(member.age_years)
	if state.has("next_person_id"):
		state.next_person_id = int(state.next_person_id)
	if not state.has("team_supply"):
		state["team_supply"] = {}
	if not state.has("person_supply"):
		state["person_supply"] = {}
	for sustain: Dictionary in state.person_supply.values():
		_normalize_sustain(sustain)
	for supply: Dictionary in state.team_supply.values():
		for field: String in ["version", "training_requester", "revision"]:
			supply[field] = int(supply[field])
		_normalize_sustain(supply.sustain)
		for resource: String in supply.inventory:
			supply.inventory[resource] = int(supply.inventory[resource])
		for identity: String in supply.life_checkpoint:
			supply.life_checkpoint[identity] = int(supply.life_checkpoint[identity])
	for field: String in ["item_storage_version", "next_loot", "next_item"]:
		state[field] = int(state[field])
	var item_holders: Array = [state.depot_items]
	if not state.has("vehicles"): state.vehicles = {}
	state.next_vehicle = int(state.get("next_vehicle", 1))
	for vehicle: Dictionary in state.vehicles.values():
		for field: String in ["cell", "team_id", "operator_id"]: vehicle[field] = int(vehicle[field])
		vehicle.facing = _int_array(vehicle.facing)
		if not vehicle.move.is_empty():
			for field: String in ["cell", "operator_from", "operator_to"]: vehicle.move[field] = int(vehicle.move[field])
			vehicle.move.facing = _int_array(vehicle.move.facing)
			vehicle.move.sweep = _int_array(vehicle.move.sweep)
		for resource: String in vehicle.cargo: vehicle.cargo[resource] = int(vehicle.cargo[resource])
		item_holders.append(vehicle.holder)
	for container: Dictionary in state.ground_loot.values():
		container.cell = int(container.cell)
		container.original_owner = int(container.original_owner)
		for resource: String in container.cargo:
			container.cargo[resource] = int(container.cargo[resource])
		item_holders.append(container)
	for actor: Dictionary in state.get("actors", {}).values():
		if actor.get("schema") == 1:
			var normalized_actor := TerrainTestCharacter.normalize_saved_state(actor)
			actor.clear()
			actor.merge(normalized_actor)
		if actor.has("item_state"):
			item_holders.append(actor.item_state)
	for team_index in range(state.get("armies", []).size()):
		state.armies[team_index] = TerrainArmy.normalize_roster_snapshot(state.armies[team_index])
		for unit: Dictionary in state.armies[team_index].units:
			if unit.has("work_task"):
				unit.work_task = WorkTeam.normalize_task(unit.work_task)
			if unit.has("item_state"):
				item_holders.append(unit.item_state)
			for resource: String in unit.get("cargo", {}):
				unit.cargo[resource] = int(unit.cargo[resource])
	for holder: Dictionary in item_holders:
		holder.version = int(holder.version)
	for record: Dictionary in state.item_records.values():
		record.original_owner = int(record.original_owner)
	for relation: Dictionary in state.get("captivity", {}).values():
		for field: String in ["version", "captor_id", "guard_id", "captor_faction"]:
			relation[field] = int(relation[field])
	for nation: Dictionary in state.get("equipment_nations", {}).values():
		nation.military_head = int(nation.military_head)
		for index in range(nation.members.size()):
			nation.members[index] = int(nation.members[index])
		for standard: Dictionary in nation.standards.values():
			standard.revision = int(standard.revision)
	for order: Dictionary in state.get("escort_orders", {}).values():
		order.destination = int(order.destination)
		for index in range(order.captives.size()):
			order.captives[index] = int(order.captives[index])
	for item: String in state.inventory:
		state.inventory[item] = int(state.inventory[item])
	for key: String in state.changes:
		for field: String in ["remaining", "next_recovery", "used_minute"]:
			if state.changes[key].has(field):
				state.changes[key][field] = int(state.changes[key][field])
	for key: String in state.terrain_changes:
		state.terrain_changes[key] = int(state.terrain_changes[key])
	for actor_key: String in ["worker", "manual"]:
		var actor: Dictionary = state[actor_key]
		for field: String in ["zone", "cell", "work_cell"]:
			if actor.has(field):
				actor[field] = int(actor[field])
		for item: String in actor.cargo:
			actor.cargo[item] = int(actor.cargo[item])
	for key: String in state.features:
		var feature: Dictionary = state.features[key]
		feature.cells = _int_array(feature.cells)
		feature.entrance = int(feature.entrance)
		feature.level = int(feature.level)
		if feature.has("residents"):
			feature.residents = int(feature.residents)
		for item: String in feature.cost:
			feature.cost[item] = int(feature.cost[item])
	for zone: Dictionary in state.zones:
		zone.cells = _int_array(zone.cells)
		zone.kind = int(zone.kind)
	state.total_produced = int(state.total_produced)
	if state.has("player_cell"):
		state.player_cell = int(state.player_cell)

static func _int_array(values: Array) -> Array[int]:
	var result: Array[int] = []
	for value: Variant in values:
		result.append(int(value))
	return result

static func _normalize_sustain(state: Dictionary) -> void:
	state.version = int(state.version)
	state.last_combat_event = int(state.last_combat_event)
	for cohort: Dictionary in state.cohorts:
		cohort.ids = _int_array(cohort.ids)

static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return Runtime.fail("NO_SAVE", "尚無保存地圖")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return Runtime.fail("SAVE_IO", error_string(FileAccess.get_open_error()))
	if file.get_length() > MAX_BYTES or file.get_length() < 10:
		file.close()
		return Runtime.fail("CORRUPT_SAVE", "檔案大小不合法")
	var text := file.get_as_text()
	file.close()
	var envelope_parser := JSON.new()
	if envelope_parser.parse(text) != OK:
		return Runtime.fail("CORRUPT_SAVE", "檔案不是有效 JSON，原檔保留")
	var envelope: Variant = envelope_parser.data
	if not envelope is Dictionary or not envelope.get("payload") is String or not envelope.get("checksum") is String:
		return Runtime.fail("CORRUPT_SAVE", "格式損壞；可嘗試上一份 .bak")
	if str(envelope.payload).sha256_text() != str(envelope.checksum):
		return Runtime.fail("CORRUPT_SAVE", "校驗失敗，未修改目前地圖")
	var payload_parser := JSON.new()
	if payload_parser.parse(str(envelope.payload)) != OK:
		return Runtime.fail("CORRUPT_SAVE", "內容不是有效 JSON，原檔保留")
	var payload: Variant = payload_parser.data
	if not payload is Dictionary:
		return Runtime.fail("CORRUPT_SAVE")
	if not _integer(payload.get("format"), 1, FORMAT) or int(payload.get("terrain_version", -1)) != TERRAIN_VERSION or int(payload.get("environment_version", -1)) != Env.VERSION:
		return Runtime.fail("SAVE_VERSION", "生成／存檔版本不同，原檔保留")
	if not payload.get("state") is Dictionary or not payload.get("parameters") is Dictionary:
		return Runtime.fail("CORRUPT_SAVE")
	if int(payload.format) == 1:
		# Explicit migration of this Site format only; no retired World saves.
		payload.state["actors"] = {}
		payload["legacy_actor_state"] = true
	elif not payload.state.get("actors") is Dictionary:
		return Runtime.fail("CORRUPT_SAVE", "缺少人物快照欄位")
	if int(payload.format) < 3:
		payload.state["armies"] = []
		payload.state["army_trial_active"] = false
	elif not payload.state.get("armies") is Array:
		return Runtime.fail("CORRUPT_SAVE", "缺少軍隊快照欄位")
	var item_migration := Runtime.initialize_item_storage(payload.state)
	if not item_migration.ok:
		return item_migration
	if not _integer(payload.get("seed"), -2147483648, 2147483647) or not _integer(payload.get("preset"), 0, TerrainPreset.NAMES.size() - 1):
		return Runtime.fail("CORRUPT_SAVE", "seed／地貌非法")
	var size_value: Variant = payload.parameters.get("size")
	if not size_value is Array or size_value.size() != 2 or not _integer(size_value[0], 16, 128) or not _integer(size_value[1], 16, 128):
		return Runtime.fail("CORRUPT_SAVE", "地圖大小非法")
	if not _number(payload.parameters.get("max_height"), 1, 5) or not _number(payload.parameters.get("micro_strength"), 0, 0.04):
		return Runtime.fail("CORRUPT_SAVE", "生成參數非法")
	return Runtime.ok("", {"payload": payload})

static func _validate_state(data: TerrainData, state: Dictionary) -> Dictionary:
	var army_validation := _validate_armies(data, state)
	if not army_validation.ok:
		return army_validation
	var vehicle_validation := _validate_vehicles(data, state)
	if not vehicle_validation.ok:
		return vehicle_validation
	var actor_validation := _validate_actors(data, state)
	if not actor_validation.ok:
		return actor_validation
	var item_validation := _validate_items(data, state)
	if not item_validation.ok:
		return item_validation
	var cape_validation := _validate_cape_roles(state)
	if not cape_validation.ok: return cape_validation
	var allocator_validation := _validate_person_allocator(state)
	if not allocator_validation.ok:
		return allocator_validation
	var supply_validation := _validate_supply(state)
	if not supply_validation.ok:
		return supply_validation
	for key: String in ["changes", "features", "terrain_changes", "inventory", "worker", "manual"]:
		if not state.get(key) is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", key)
	if not state.get("id") is String or str(state.id).is_empty() or not state.get("zones") is Array or not state.get("paused") is bool:
		return Runtime.fail("CORRUPT_SAVE", "地圖身分／工作區")
	if state.has("worker_enabled") and not state.worker_enabled is bool:
		return Runtime.fail("CORRUPT_SAVE", "工人啟用狀態")
	if not _integer(state.get("minute"), 0, 1000000000) or not _number(state.get("phase"), 0, 0.999999999) or not _integer(state.get("next_feature"), 1, 1000000):
		return Runtime.fail("CORRUPT_SAVE", "時間／編號")
	if not _integer(state.get("capacity"), 1, 1000000) or not _valid_cell(data, state.get("depot_cell")):
		return Runtime.fail("CORRUPT_SAVE", "營地")
	for key: String in state.inventory:
		if not Env.ITEM_NAMES.has(key) or not _integer(state.inventory[key], 0, 1000000):
			return Runtime.fail("CORRUPT_SAVE", "存貨")
	var occupied := {}
	for key: String in state.features:
		var feature: Variant = state.features[key]
		if not key.is_valid_int() or int(key) < 1 or int(key) >= int(state.next_feature) or not feature is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "建物身分")
		if not Runtime.FEATURES.has(str(feature.get("kind", ""))) or not _valid_cells(data, feature.get("cells"), 36):
			return Runtime.fail("CORRUPT_SAVE", "建物占地")
		if not _valid_cell(data, feature.get("entrance")) or str(feature.get("stage", "")) not in ["planned", "building", "complete"]:
			return Runtime.fail("CORRUPT_SAVE", "建物入口／階段")
		for field: String in ["progress", "production", "work"]:
			if not _number(feature.get(field), 0, 1000000):
				return Runtime.fail("CORRUPT_SAVE", "工作進度")
		if float(feature.work) <= 0.0 or not feature.get("batch_paid") is bool or not feature.get("solid") is bool or not feature.get("cost") is Dictionary or not feature.get("clearing") is Array:
			return Runtime.fail("CORRUPT_SAVE", "建物工作資料")
		if bool(feature.solid) != bool(Runtime.FEATURES[str(feature.kind)].solid) or float(feature.progress) > float(feature.work):
			return Runtime.fail("CORRUPT_SAVE", "建物規格")
		if str(feature.kind) in ["pasture", "horse_ranch"]:
			var species := "horse" if str(feature.kind) == "horse_ranch" else "sheep"
			if str(feature.get("species", "")) != species or not _integer(feature.get("residents"), 1, 36):
				return Runtime.fail("CORRUPT_SAVE", "畜種與種畜")
		elif feature.has("species") or feature.has("residents"):
			return Runtime.fail("CORRUPT_SAVE", "非牧場含有牲畜")
		if not feature.get("source") is String or not feature.get("status") is String or not _integer(feature.get("level"), 0, 5):
			return Runtime.fail("CORRUPT_SAVE", "建物來源")
		for i: Variant in feature.cells:
			if occupied.has(int(i)):
				return Runtime.fail("CORRUPT_SAVE", "占地重疊")
			occupied[int(i)] = true
		for resource_key: Variant in feature.clearing:
			if not resource_key is String or not data.resource_base.has(resource_key):
				return Runtime.fail("CORRUPT_SAVE", "清理來源")
		for item: Variant in feature.cost:
			if not item is String or not Env.ITEM_NAMES.has(item) or not _integer(feature.cost[item], 0, 1000000):
				return Runtime.fail("CORRUPT_SAVE", "施工投入")
	for key: String in state.changes:
		if not data.resource_base.has(key) or not state.changes[key] is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "資源 ID")
		var fields: Dictionary = state.changes[key]
		for field: String in fields:
			if field not in ["remaining", "next_recovery", "cleared", "discovered", "used", "used_minute"]:
				return Runtime.fail("CORRUPT_SAVE", "不支援的資源差異")
		if fields.has("remaining") and not _integer(fields.remaining, 0, int(data.resource_base[key].capacity)):
			return Runtime.fail("CORRUPT_SAVE", "資源儲量")
		for flag: String in ["cleared", "discovered"]:
			if fields.has(flag) and not fields[flag] is bool:
				return Runtime.fail("CORRUPT_SAVE", "資源狀態")
		if fields.has("next_recovery") and not _integer(fields.next_recovery, -1, 1100000000):
			return Runtime.fail("CORRUPT_SAVE", "恢復期限")
		if fields.has("used") and not _number(fields.used, 0, 1000000):
			return Runtime.fail("CORRUPT_SAVE", "來源使用量")
		if fields.has("used_minute") and not _integer(fields.used_minute, 0, 1000000000):
			return Runtime.fail("CORRUPT_SAVE", "來源時間")
	for key: String in state.terrain_changes:
		if not key.is_valid_int() or not _valid_cell(data, int(key)) or not _integer(state.terrain_changes[key], 0, 5):
			return Runtime.fail("CORRUPT_SAVE", "整地差異")
	for zone: Variant in state.zones:
		if not zone is Dictionary or not _valid_cells(data, zone.get("cells"), 1600) or not zone.get("active") is bool:
			return Runtime.fail("CORRUPT_SAVE", "工作區資料")
		if str(zone.get("action", "")) not in ["harvest", "clear", "survey", "construct", "operate"] or not _integer(zone.get("kind"), -1, 8):
			return Runtime.fail("CORRUPT_SAVE", "工作區命令")
		if str(zone.action) in ["construct", "operate"] and not zone.get("feature") is String:
			return Runtime.fail("CORRUPT_SAVE", "工作區建物")
	for actor_key: String in ["worker", "manual"]:
		var actor: Dictionary = state[actor_key]
		if not actor.get("target") is String or not _number(actor.get("progress"), 0, 1000000) or not actor.get("cargo") is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "作業狀態")
		var target := str(actor.target)
		if not target.is_empty():
			if not data.resource_base.has(target) and target != "depot" and not (target.begins_with("feature:") and state.features.has(target.trim_prefix("feature:"))):
				return Runtime.fail("CORRUPT_SAVE", "作業目標")
			if str(actor.get("action", "")) not in ["harvest", "clear", "survey", "construct", "operate", "deposit"]:
				return Runtime.fail("CORRUPT_SAVE", "作業行為")
			if actor_key == "worker" and not _valid_cell(data, actor.get("work_cell")):
				return Runtime.fail("CORRUPT_SAVE", "工作目的地")
			if actor_key == "manual" and (not data.resource_base.has(target) or not _valid_cell(data, actor.get("cell")) or str(actor.action) not in ["harvest", "survey", "clear"]):
				return Runtime.fail("CORRUPT_SAVE", "手動作業")
		for item: String in actor.cargo:
			if not Env.ITEM_NAMES.has(item) or not _integer(actor.cargo[item], 0, Runtime.CARRY_CAPACITY):
				return Runtime.fail("CORRUPT_SAVE", "攜帶物")
		if Runtime.inventory_size(actor.cargo) > Runtime.CARRY_CAPACITY:
			return Runtime.fail("CORRUPT_SAVE", "攜帶超量")
		for cell_key: String in ["cell", "work_cell"]:
			if actor.has(cell_key) and not _valid_cell(data, actor[cell_key]):
				return Runtime.fail("CORRUPT_SAVE", "作業格位")
	if not _valid_cell(data, state.worker.get("cell")) or str(state.worker.get("mode", "")) not in ["idle", "travel", "work"] or not state.worker.get("status") is String or not _integer(state.worker.get("zone"), -1, state.zones.size() - 1):
		return Runtime.fail("CORRUPT_SAVE", "工人")
	if not state.manual.get("action") is String or not _number(state.get("total_produced"), 0, 1000000000):
		return Runtime.fail("CORRUPT_SAVE", "產量")
	if not state.worker.get("manual_control", false) is bool:
		return Runtime.fail("CORRUPT_SAVE", "原工人手動作業欄位")
	if state.has("player_cell") and not _valid_cell(data, state.player_cell):
		return Runtime.fail("CORRUPT_SAVE", "玩家格位")
	return Runtime.ok()

static func _validate_actors(data: TerrainData, state: Dictionary) -> Dictionary:
	var actors: Variant = state.get("actors", {})
	if not actors is Dictionary:
		return Runtime.fail("CORRUPT_SAVE", "人物快照格式")
	if actors.is_empty():
		return Runtime.ok() # Generated map / format-1 migration has no actor snapshot yet.
	if not actors.has("player") or actors.size() > 2 or (actors.size() == 2 and not actors.has("npc")):
		return Runtime.fail("CORRUPT_SAVE", "人物快照不完整")
	if not state.get("worker") is Dictionary or not _valid_cell(data, state.worker.get("cell")) or not _valid_cell(data, state.get("player_cell", data.index(data.spawn_cell))):
		return Runtime.fail("CORRUPT_SAVE", "人物地圖格位")
	var identities := {}
	for key: String in actors:
		var actor: Variant = actors[key]
		if not TerrainTestCharacter.valid_state(actor, data):
			return Runtime.fail("CORRUPT_SAVE", "人物狀態／實裝非法：" + key)
		var identity := int(actor.person_id)
		if identities.has(identity):
			return Runtime.fail("CORRUPT_SAVE", "重複人物身分")
		identities[identity] = actor
		var expected_cell := int(state.get("player_cell", data.index(data.spawn_cell))) if key == "player" else int(state.worker.cell)
		if data.index(Vector2i(int(actor.cell[0]), int(actor.cell[1]))) != expected_cell:
			return Runtime.fail("CORRUPT_SAVE", "人物與地圖格位不一致")
	var hit_identities := identities.duplicate()
	var rescuers := {}
	for original_team: Dictionary in state.get("armies", []):
		var team := TerrainArmy.normalize_roster_snapshot(original_team)
		for index in range(team.units.size()):
			var identity := int(team.units[index].person_id)
			var unit: Dictionary = team.units[index]
			hit_identities[identity] = true
			identities[identity] = {"hp": unit.hp, "knockout_left": unit.ko, "faction_id": team.faction_id, "cell": unit.cell,
				"movement_left": 0.0 if Vector2(float(unit.destination[0]), float(unit.destination[1])) == Vector2(-1, -1) else 1.0}
		for entry: Dictionary in team.get("rescues", []):
			var patient := int(entry.patient)
			var identity := int(team.player_member.id) if patient == TerrainArmy.PLAYER_MEMBER else int(team.units[patient].person_id)
			if rescuers.has(identity):
				return Runtime.fail("CORRUPT_SAVE", "重複施救者")
			rescuers[identity] = true
	for key: String in actors:
		var actor: Dictionary = actors[key]
		var attack_target := int(actor.get("attack_target", 0))
		if attack_target != 0 and (not hit_identities.has(attack_target) or attack_target == int(actor.person_id)):
			return Runtime.fail("CORRUPT_SAVE", "攻擊目標指向未知人物")
		for identity: Variant in actor.hit_ids:
			if not hit_identities.has(int(identity)) or int(identity) == int(actor.person_id):
				return Runtime.fail("CORRUPT_SAVE", "命中去重指向未知人物")
		if float(actor._rescue_left) <= 0.0:
			if int(actor.rescue_target) != 0:
				return Runtime.fail("CORRUPT_SAVE", "失效的救助關係")
			continue
		var target_id := int(actor.rescue_target)
		if not identities.has(target_id) or target_id == int(actor.person_id) or rescuers.has(target_id):
			return Runtime.fail("CORRUPT_SAVE", "救助關係重複／失效")
		var target: Dictionary = identities[target_id]
		if float(actor.hp) <= 0.0 or float(actor.knockout_left) > 0.0 or bool(actor.captive) or float(target.hp) <= 0.0 or float(target.knockout_left) <= 0.0 or int(actor.faction_id) != int(target.faction_id):
			return Runtime.fail("CORRUPT_SAVE", "救助資格失效")
		var from_cell := Vector2i(int(actor.cell[0]), int(actor.cell[1]))
		var target_cell := Vector2i(int(target.cell[0]), int(target.cell[1]))
		var offset := target_cell - from_cell
		if float(actor.movement_left) > 0.0 or float(target.movement_left) > 0.0 or absi(offset.x) + absi(offset.y) != 1 or not data.can_step(from_cell, target_cell):
			return Runtime.fail("CORRUPT_SAVE", "救助位置失效")
		rescuers[target_id] = int(actor.person_id)
	if not actors.has("npc"):
		return Runtime.ok()
	var navigation: Variant = actors.npc.get("navigation")
	if not navigation is Dictionary or not _integer(navigation.get("command"), 0, 2) or not navigation.get("status") is String or str(navigation.status).length() > 256 or not navigation.get("path") is Array or navigation.path.size() > data.size.x * data.size.y:
		return Runtime.fail("CORRUPT_SAVE", "NPC 命令快照")
	if not TerrainTestCharacter._saved_vector(navigation.get("target")):
		return Runtime.fail("CORRUPT_SAVE", "NPC 目標快照")
	if int(navigation.command) != TerrainTestNPC.Command.STOP and not TerrainTestCharacter._saved_cell(navigation.target, data):
		return Runtime.fail("CORRUPT_SAVE", "NPC 目標格位")
	for cell: Variant in navigation.path:
		if not TerrainTestCharacter._saved_cell(cell, data):
			return Runtime.fail("CORRUPT_SAVE", "NPC 路線快照")
	return Runtime.ok()

static func _validate_armies(data: TerrainData, state: Dictionary, check_terrain: bool = false) -> Dictionary:
	var armies: Variant = state.get("armies", [])
	if not armies is Array or armies.size() > 3:
		return Runtime.fail("CORRUPT_SAVE", "軍隊名冊格式")
	var identities := {}
	var claims := {}
	var source_claims := {}
	var destination_claims := {}
	var batch_groups := {}
	var deployment_claims := {}
	var maximum_team := 0
	var teams_seen := {}
	var total_rows := 0 # Three test teams, bounded to 300 actual army rows.
	var live_presenters := 0 # At most one original live captain per test team.
	var actors: Variant = state.get("actors", {})
	if not actors is Dictionary or not actors.get("player", {}) is Dictionary:
		return Runtime.fail("CORRUPT_SAVE", "人物名冊格式")
	var memberships := {}
	var work_claims := {}
	for activity: Variant in [state.get("worker", {}), state.get("manual", {})]:
		if not activity is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "原作業資料格式")
		if not str(activity.get("target", "")).is_empty():
			if work_claims.has(str(activity.target)):
				return Runtime.fail("CORRUPT_SAVE", "原作業來源重複")
			work_claims[str(activity.target)] = true
	for original_team: Variant in armies:
		var member_actor: Dictionary = actors.get("player", {})
		if original_team is Dictionary and original_team.get("player_member") is Dictionary and not original_team.player_member.is_empty():
			member_actor = {}
			for actor: Dictionary in actors.values():
				if int(actor.get("person_id", 0)) == int(original_team.player_member.get("id", -1)):
					member_actor = actor
		if not TerrainArmy.valid_combat_state(original_team, data, member_actor, state):
			return Runtime.fail("CORRUPT_SAVE", "軍隊人物／動作／指揮關係非法")
		var team := TerrainArmy.normalize_roster_snapshot(original_team)
		if not _valid_combat_movement_snapshot(data, team, batch_groups):
			return Runtime.fail("CORRUPT_SAVE", "軍隊行軍／部署／在途依賴非法")
		var deployment: Variant = team.get("combat_deployment_plan", null)
		if deployment is Dictionary:
			for pair: Array in deployment.get("member_slot_map", {}).values():
				var slot := Vector2i(int(pair[0]), int(pair[1]))
				if deployment_claims.has(slot) and deployment_claims[slot] != int(team.team_id):
					return Runtime.fail("CORRUPT_SAVE", "跨隊部署槽位重疊")
				deployment_claims[slot] = int(team.team_id)
			for key: String in deployment.get("slot_lease_timers", {}).keys():
				var parts := key.split(",")
				var leased_slot := Vector2i(int(parts[0]), int(parts[1]))
				if deployment_claims.has(leased_slot) and deployment_claims[leased_slot] != int(team.team_id):
					return Runtime.fail("CORRUPT_SAVE", "跨隊部署槽位重疊")
				deployment_claims[leased_slot] = int(team.team_id)
		if teams_seen.has(int(team.team_id)):
			return Runtime.fail("CORRUPT_SAVE", "重複隊伍身分")
		teams_seen[int(team.team_id)] = true
		total_rows += team.units.size()
		if total_rows > 300:
			return Runtime.fail("CORRUPT_SAVE", "目前 Site 上限為 300 列軍隊人物")
		if not team.get("player_member", {}).is_empty():
			var member_id := int(team.player_member.id)
			if memberships.has(member_id):
				return Runtime.fail("CORRUPT_SAVE", "同一玩家不能加入兩隊")
			memberships[member_id] = true
		maximum_team = maxi(maximum_team, int(team.team_id))
		for index in range(team.units.size()):
			var identity := int(team.units[index].person_id)
			if identities.has(identity):
				return Runtime.fail("CORRUPT_SAVE", "重複軍隊人物身分")
			identities[identity] = true
			var unit: Dictionary = team.units[index]
			var work: Variant = unit.get("work_task", {})
			if not WorkTeam.valid_task(data, state, work):
				return Runtime.fail("CORRUPT_SAVE", "原隊員作業引用／欄位")
			if not bool(unit.get("member", true)) and not work.is_empty() and not bool(work.get("manual", false)):
				return Runtime.fail("CORRUPT_SAVE", "獨立原人物不能帶回原隊伍的自動派工令")
			if not work.is_empty() and str(work.mode) not in ["paused", "rest"] and not str(work.target).is_empty():
				if work_claims.has(str(work.target)):
					return Runtime.fail("CORRUPT_SAVE", "同一來源由多名原人物重複作業")
				work_claims[str(work.target)] = true
			live_presenters += int(str(unit.visual_role) in ["female_live", "male_live"])
			if live_presenters > 3:
				return Runtime.fail("CORRUPT_SAVE", "目前 Site 只有三個原隊長呈現者")
			var cell := Vector2i(int(unit.cell[0]), int(unit.cell[1]))
			var destination := Vector2i(int(unit.destination[0]), int(unit.destination[1]))
			if check_terrain and (not data.is_walkable(cell) or destination != TerrainArmy.INVALID_CELL and not data.can_step(cell, destination)):
				return Runtime.fail("CORRUPT_SAVE", "軍隊格位／移動跨越非法地形")
			var standing := float(unit.hp) > 0.0 and float(unit.ko) <= 0.0 and not bool(unit.departed)
			if standing or destination != TerrainArmy.INVALID_CELL:
				if source_claims.has(cell):
					return Runtime.fail("CORRUPT_SAVE", "軍隊來源占位重疊")
				source_claims[cell] = identity
			if destination != TerrainArmy.INVALID_CELL:
				if destination_claims.has(destination):
					return Runtime.fail("CORRUPT_SAVE", "軍隊目的格預約重疊")
				destination_claims[destination] = identity
	for cell: Vector2i in destination_claims.keys():
		if source_claims.has(cell):
			var source_id: int = source_claims[cell]
			var moving_id: int = destination_claims[cell]
			if not batch_groups.has(source_id) or batch_groups.get(source_id) != batch_groups.get(moving_id):
				return Runtime.fail("CORRUPT_SAVE", "未宣告的軍隊來源／目的格重疊")
	claims = source_claims.duplicate()
	for cell: Vector2i in destination_claims.keys():
		claims[cell] = destination_claims[cell]
	if state.has("army_next_team") and not _integer(state.army_next_team, maximum_team + 1, 999999):
		return Runtime.fail("CORRUPT_SAVE", "軍隊身分序號失效")
	for actor: Variant in actors.values():
		if not actor is Dictionary or not TerrainTestCharacter.valid_state(actor, data):
			return Runtime.fail("CORRUPT_SAVE", "人物狀態非法")
		if identities.has(int(actor.person_id)):
			return Runtime.fail("CORRUPT_SAVE", "軍隊與人物身分重複")
		identities[int(actor.person_id)] = true
		if not armies.is_empty() and (float(actor.hp) > 0.0 and float(actor.knockout_left) <= 0.0 or float(actor.movement_left) > 0.0):
			var cell := Vector2i(int(actor.cell[0]), int(actor.cell[1]))
			var previous := Vector2i(int(actor.movement_from[0]), int(actor.movement_from[1]))
			if claims.has(cell) or float(actor.movement_left) > 0.0 and claims.has(previous):
				return Runtime.fail("CORRUPT_SAVE", "人物與軍隊占位重疊")
	for original_team: Dictionary in armies:
		var team := TerrainArmy.normalize_roster_snapshot(original_team)
		if int(team.combat_order) == TerrainArmy.CombatOrder.PURSUE and (float(team.pursuit_left) <= 0.0 or not identities.has(int(team.pursuit_target))):
			return Runtime.fail("CORRUPT_SAVE", "追擊目標／倒數失效")
		for index in range(team.units.size()):
			for identity: Variant in team.units[index].hits:
				if not identities.has(int(identity)) or int(identity) == int(team.units[index].person_id):
					return Runtime.fail("CORRUPT_SAVE", "軍隊命中去重指向未知人物")
	return Runtime.ok()

static func _valid_combat_movement_snapshot(data: TerrainData, team: Dictionary, batch_groups: Dictionary) -> bool:
	var people: Dictionary = {}
	for unit: Dictionary in team.units:
		people[int(unit.person_id)] = unit
	var team_preset: Variant = team.get("formation_preset_id", "auto")
	if not team_preset is String or not Destination.is_valid_preset(team_preset): return false
	var deployment: Variant = team.get("combat_deployment_plan", null)
	var movement: Variant = team.get("combat_move_plan", null)
	var absent_slots: Variant = team.get("combat_absent_slots", {})
	if not absent_slots is Dictionary or absent_slots.size() > team.units.size() or (deployment == null or movement == null) and not absent_slots.is_empty(): return false
	var deployment_anchor: Variant = null
	if deployment != null:
		if not deployment is Dictionary:
			return false
		var saved_version: Variant = deployment.get("shape_version", 1)
		if not _integer(saved_version, 1, 2): return false
		var legacy_deployment: bool = int(saved_version) == 1
		if legacy_deployment:
			if deployment.has("formation_preset_id") or team_preset != "auto": return false
		else:
			var plan_preset: Variant = deployment.get("formation_preset_id", null)
			if not team.has("formation_preset_id") or not plan_preset is String or not Destination.is_valid_preset(plan_preset) or plan_preset != team_preset: return false
		deployment_anchor = deployment.get("resolved_anchor")
		if not _valid_walkable_pair(data, deployment_anchor):
			if not legacy_deployment or not movement is Dictionary or not _valid_walkable_pair(data, movement.get("resolved_anchor")):
				return false
			deployment_anchor = movement.resolved_anchor
		if not legacy_deployment and not _valid_xy_pair(data, deployment.get("final_facing")):
			return false
		if deployment.has("final_facing"):
			if not _valid_xy_pair(data, deployment.final_facing):
				return false
			var facing := Vector2i(int(deployment.final_facing[0]), int(deployment.final_facing[1]))
			if facing not in TerrainData.DIRECTIONS:
				return false
		if not _integer(deployment.get("order_serial"), 1, 2147483647):
			return false
		if not legacy_deployment and (not _integer(team.get("combat_order_serial"), 1, 2147483647) \
			or int(team.combat_order_serial) != int(deployment.order_serial)):
			return false
		var platform: Variant = deployment.get("platform_slots", [])
		var queue: Variant = deployment.get("approach_queue_slots", [])
		var member_slots: Variant = deployment.get("member_slot_map", {})
		var member_roles: Variant = deployment.get("member_role_map", {})
		if not platform is Array or not queue is Array or not member_slots is Dictionary or not member_roles is Dictionary \
			or platform.size() > data.size.x * data.size.y or queue.size() > data.size.x * data.size.y or member_slots.size() > team.units.size() or member_roles.size() != member_slots.size():
			return false
		var platform_set: Dictionary = {}
		var queue_set: Dictionary = {}
		for pair: Variant in platform:
			if not _valid_walkable_pair(data, pair): return false
			var cell := Vector2i(int(pair[0]), int(pair[1]))
			if platform_set.has(cell): return false
			platform_set[cell] = true
		for pair: Variant in queue:
			if not _valid_walkable_pair(data, pair): return false
			var cell := Vector2i(int(pair[0]), int(pair[1]))
			if platform_set.has(cell) or queue_set.has(cell): return false
			queue_set[cell] = true
		if not legacy_deployment:
			var requested: Variant = deployment.get("requested_count")
			if not _integer(requested, 1, 200) or int(requested) > team.units.size(): return false
			var facing := Vector2i(int(deployment.final_facing[0]), int(deployment.final_facing[1]))
			var side := Vector2i(-facing.y, facing.x)
			var width: Variant = deployment.get("final_width")
			var depth: Variant = deployment.get("final_depth")
			var anchor := Vector2i(int(deployment_anchor[0]), int(deployment_anchor[1]))
			if not _integer(width, 1, maxi(data.size.x, data.size.y)) or not _integer(depth, 1, maxi(data.size.x, data.size.y)): return false
			if team_preset == "auto":
				var columns: Dictionary = {}
				for cell: Vector2i in platform_set.keys():
					columns[(cell.x - anchor.x) * side.x + (cell.y - anchor.y) * side.y] = true
				var auto_width := mini(10, maxi(1, columns.size()))
				if int(width) != auto_width or int(depth) != ceili(float(platform.size()) / float(auto_width)): return false
			else:
				if platform.size() != int(requested): return false
				var expected: Array[Vector2i] = Destination.shape_slots(team_preset, int(requested), anchor, facing)
				if expected.size() != int(requested): return false
				var min_side := 2147483647
				var max_side := -2147483647
				var min_front := 2147483647
				var max_front := -2147483647
				for cell: Vector2i in expected:
					if not platform_set.has(cell): return false
					var offset := cell - anchor
					var lateral := offset.x * side.x + offset.y * side.y
					var axial := offset.x * facing.x + offset.y * facing.y
					min_side = mini(min_side, lateral)
					max_side = maxi(max_side, lateral)
					min_front = mini(min_front, axial)
					max_front = maxi(max_front, axial)
				if int(width) != max_side - min_side + 1 or int(depth) != max_front - min_front + 1: return false
		var assigned: Dictionary = {}
		for key: Variant in member_slots.keys():
			if not str(key).is_valid_int() or str(int(key)) != str(key) or not people.has(int(key)) or not member_roles.has(key) or not _valid_walkable_pair(data, member_slots[key]):
				return false
			var cell := Vector2i(int(member_slots[key][0]), int(member_slots[key][1]))
			var role: Variant = member_roles[key]
			if assigned.has(cell) or not _integer(role, 0, 1) or (int(role) == 0 and not platform_set.has(cell)) or (int(role) == 1 and not queue_set.has(cell)) \
				or (not legacy_deployment and team_preset != "auto" and int(role) != 0):
				return false
			assigned[cell] = true
		var list_sets: Dictionary = {}
		for field: String in ["queue_member_ids", "pending_platform_member_ids", "admitted_platform_member_ids", "settled_platform_member_ids", "settled_queue_member_ids"]:
			if not legacy_deployment and not deployment.has(field): return false
			var mids: Variant = deployment.get(field, [])
			if not mids is Array or mids.size() > member_slots.size(): return false
			var seen: Dictionary = {}
			for value: Variant in mids:
				if not _integer(value, 1, 2147483647): return false
				var id: int = int(value)
				var member_key := str(id)
				if seen.has(id) or not member_slots.has(member_key): return false
				if field == "queue_member_ids" or field == "settled_queue_member_ids":
					if int(member_roles[member_key]) != 1: return false
				elif int(member_roles[member_key]) != 0:
					return false
				seen[id] = true
			list_sets[field] = seen
		for key: Variant in member_roles.keys():
			if int(member_roles[key]) == 1 and not list_sets["queue_member_ids"].has(int(key)): return false
		for id: int in list_sets["settled_queue_member_ids"].keys():
			if not list_sets["queue_member_ids"].has(id): return false
		for id: int in list_sets["settled_platform_member_ids"].keys():
			if deployment.has("admitted_platform_member_ids") and not list_sets["admitted_platform_member_ids"].has(id): return false
		var ever_admitted: Variant = deployment.get("ever_admitted_platform_member_ids", deployment.get("admitted_platform_member_ids", []))
		if not ever_admitted is Array or ever_admitted.size() > team.units.size(): return false
		var ever_seen: Dictionary = {}
		for value: Variant in ever_admitted:
			if not _integer(value, 1, 2147483647): return false
			var id: int = int(value)
			if ever_seen.has(id) or not people.has(id) or (not member_slots.has(str(id)) and not absent_slots.has(str(id))): return false
			ever_seen[id] = true
		for id: int in list_sets["admitted_platform_member_ids"].keys():
			if not ever_seen.has(id): return false
		if not legacy_deployment:
			for id: int in list_sets["pending_platform_member_ids"].keys():
				if list_sets["admitted_platform_member_ids"].has(id): return false
		if deployment.has("queue_released") and not deployment.queue_released is bool: return false
		if not legacy_deployment and not deployment.has("queue_released"): return false
		var locks: Variant = deployment.get("member_slot_locked", {})
		if not locks is Dictionary: return false
		for key: Variant in locks.keys():
			if not member_slots.has(key) or not locks[key] is bool: return false
		var tactical: Variant = deployment.get("slot_tactical_roles", {})
		if not tactical is Dictionary: return false
		for key: Variant in tactical.keys():
			if not _valid_grid_key(data, key) or not _integer(tactical[key], 0, 4): return false
		var timers: Variant = deployment.get("slot_lease_timers", {})
		var owners: Variant = deployment.get("slot_lease_owner_map", {})
		var lease_roles: Variant = deployment.get("slot_lease_role_map", {})
		var queue_indexes: Variant = deployment.get("slot_lease_queue_index_map", {})
		if not timers is Dictionary or not owners is Dictionary or not lease_roles is Dictionary or not queue_indexes is Dictionary or timers.size() != owners.size() or timers.size() != lease_roles.size(): return false
		for key: Variant in timers.keys():
			if not _valid_grid_key(data, key) or not owners.has(key) or not lease_roles.has(key) or not _number(timers[key], 0.0, 60.0) or not _integer(owners[key], 1, 2147483647) or not _integer(lease_roles[key], 0, 1): return false
			var parts: PackedStringArray = str(key).split(",")
			var lease_cell := Vector2i(int(parts[0]), int(parts[1]))
			var owner_id: int = int(owners[key])
			var owner_key := str(owner_id)
			if key != "%d,%d" % [lease_cell.x, lease_cell.y] or assigned.has(lease_cell) or not people.has(owner_id) or not absent_slots.has(owner_key) or not _valid_walkable_pair(data, absent_slots[owner_key]): return false
			if lease_cell != Vector2i(int(absent_slots[owner_key][0]), int(absent_slots[owner_key][1])): return false
			var person: Dictionary = people[owner_id]
			if float(person.hp) <= 0.0 or bool(person.departed) or not bool(person.get("member", true)): return false
			var lease_role: int = int(lease_roles[key])
			if (lease_role == 0 and (not platform_set.has(lease_cell) or queue_indexes.has(key))) or (lease_role == 1 and (not queue_set.has(lease_cell) or not queue_indexes.has(key))): return false
		for key: Variant in lease_roles.keys():
			if not timers.has(key) or not _integer(lease_roles[key], 0, 1): return false
		for key: Variant in queue_indexes.keys():
			if not timers.has(key) or not _integer(queue_indexes[key], 0, team.units.size()): return false
		if not _integer(deployment.get("available_platform_capacity", platform.size()), platform.size(), data.size.x * data.size.y) \
			or not _integer(deployment.get("queue_capacity", queue.size()), queue.size(), data.size.x * data.size.y): return false
	for key: Variant in absent_slots.keys():
		if not str(key).is_valid_int() or str(int(key)) != str(key) or not people.has(int(key)) or not _valid_walkable_pair(data, absent_slots[key]): return false
		var person: Dictionary = people[int(key)]
		if float(person.hp) <= 0.0 or bool(person.departed) or not bool(person.get("member", true)) or deployment.member_slot_map.has(key): return false
		var cell := Vector2i(int(absent_slots[key][0]), int(absent_slots[key][1]))
		var in_final_set := false
		for pair: Variant in deployment.get("platform_slots", []) + deployment.get("approach_queue_slots", []):
			if cell == Vector2i(int(pair[0]), int(pair[1])):
				in_final_set = true
				break
		if not in_final_set: return false
		var lease_key := "%d,%d" % [cell.x, cell.y]
		var lease_owners: Dictionary = deployment.get("slot_lease_owner_map", {})
		if lease_owners.has(lease_key) and int(lease_owners[lease_key]) != int(key): return false
	if movement != null:
		if not movement is Dictionary or deployment == null or not _integer(movement.get("order_serial"), 1, 2147483647) \
			or int(movement.order_serial) != int(deployment.order_serial) or not _valid_walkable_pair(data, movement.get("resolved_anchor")) \
			or movement.resolved_anchor != deployment_anchor or not _integer(movement.get("phase"), 0, 5):
			return false
		if movement.has("platform_settled_highwater") and not _integer(movement.platform_settled_highwater, deployment.settled_platform_member_ids.size(), team.units.size()): return false
		if movement.has("vacancy_chain_state") and not _valid_vacancy_chain_state(data, deployment, movement.vacancy_chain_state, people): return false
		var vacated_cells: Variant = movement.get("member_recovery_vacated_cell", {})
		if not vacated_cells is Dictionary or vacated_cells.size() > deployment.member_slot_map.size(): return false
		for key: Variant in vacated_cells.keys():
			if not key is String or not key.is_valid_int() or str(int(key)) != key or not deployment.member_slot_map.has(key) \
				or int(deployment.member_role_map.get(key, -1)) != 0 or not _valid_walkable_pair(data, vacated_cells[key]):
				return false
			var vacated_cell := Vector2i(int(vacated_cells[key][0]), int(vacated_cells[key][1]))
			var is_platform_slot := false
			for pair: Array in deployment.platform_slots:
				if vacated_cell == Vector2i(int(pair[0]), int(pair[1])):
					is_platform_slot = true
					break
			if not is_platform_slot: return false
		var path: Variant = movement.get("macro_path", [])
		if not path is Array or path.is_empty() or path.size() > data.size.x * data.size.y or not _integer(movement.get("macro_cursor"), 0, path.size() - 1): return false
		var previous := Vector2i(-1, -1)
		for pair: Variant in path:
			if not _valid_walkable_pair(data, pair): return false
			var cell := Vector2i(int(pair[0]), int(pair[1]))
			if previous != Vector2i(-1, -1) and not data.can_step(previous, cell): return false
			previous = cell
	var batches: Variant = team.get("combat_batches", [])
	if not batches is Array or batches.size() > team.units.size(): return false
	var retreat_members: Variant = team.get("combat_batch_retreat_members", [])
	if not retreat_members is Array or retreat_members.size() > team.units.size(): return false
	var retreat_member_set: Dictionary = {}
	for value: Variant in retreat_members:
		if not _integer(value, 1, 2147483647) or not people.has(int(value)) or retreat_member_set.has(int(value)): return false
		retreat_member_set[int(value)] = true
	var move_members: Variant = team.get("combat_batch_move_members", [])
	if not move_members is Array or move_members.size() > team.units.size(): return false
	var move_member_set: Dictionary = {}
	for value: Variant in move_members:
		if not _integer(value, 1, 2147483647) or not people.has(int(value)) or move_member_set.has(int(value)) or retreat_member_set.has(int(value)): return false
		move_member_set[int(value)] = true
	var seen_batch_members: Dictionary = {}
	for group_index in range(batches.size()):
		var group: Variant = batches[group_index]
		if not group is Array or group.is_empty() or group.size() > team.units.size(): return false
		var sources: Dictionary = {}
		var destinations: Dictionary = {}
		var direction := Vector2i.ZERO
		var same_direction := true
		var retreat_count := 0
		var move_count := 0
		for value: Variant in group:
			if not _integer(value, 1, 2147483647) or not people.has(int(value)) or seen_batch_members.has(int(value)): return false
			var unit: Dictionary = people[int(value)]
			var source := Vector2i(int(unit.cell[0]), int(unit.cell[1]))
			var destination := Vector2i(int(unit.destination[0]), int(unit.destination[1]))
			var step := destination - source
			if destination == TerrainArmy.INVALID_CELL or step not in TerrainData.DIRECTIONS or sources.has(source) or destinations.has(destination): return false
			if direction != Vector2i.ZERO and direction != step: same_direction = false
			direction = step
			sources[source] = true
			destinations[destination] = true
			retreat_count += int(retreat_member_set.has(int(value)))
			move_count += int(move_member_set.has(int(value)))
			seen_batch_members[int(value)] = true
			batch_groups[int(value)] = "%d:%d" % [int(team.team_id), group_index]
		var empty_tails := 0
		for destination: Vector2i in destinations.keys():
			if not sources.has(destination): empty_tails += 1
		# A committed reciprocal pair keeps its starting order when a new combat
		# order arrives before the physical completion barrier.
		if empty_tails == 0:
			if group.size() != 2 or (move_count != 2 and retreat_count != 2): return false
		elif not same_direction or empty_tails != 1:
			return false
	for mid: int in retreat_member_set:
		if not seen_batch_members.has(mid): return false
	for mid: int in move_member_set:
		if not seen_batch_members.has(mid): return false
	return true

static func _valid_vacancy_chain_state(data: TerrainData, deployment: Dictionary, value: Variant, people: Dictionary) -> bool:
	if not value is Dictionary:
		return false
	for field: String in ["planning_time_sec", "last_platform_progress_time_sec", "next_platform_recovery_time_sec", "started_sec", "last_progress_sec"]:
		if not _number(value.get(field), 0.0, 1000000000.0):
			return false
	var now: float = float(value.planning_time_sec)
	if float(value.started_sec) > now or float(value.last_progress_sec) > now or float(value.last_platform_progress_time_sec) > now:
		return false
	var active: Variant = value.get("active")
	var queued: Variant = value.get("queued")
	var hold: Variant = value.get("hold")
	var verified: Variant = value.get("verified")
	var starts: Variant = value.get("start_cells")
	var targets: Variant = value.get("targets")
	if not active is Array or not queued is Array or not hold is Array or not verified is Array or not starts is Dictionary or not targets is Dictionary \
		or active.size() > people.size() or queued.size() > people.size() or hold.size() > people.size() or verified.size() > people.size() \
		or starts.size() != active.size() or targets.size() != active.size() or not value.get("verified_pending") is bool \
		or not _integer(value.get("arrived_count"), 0, active.size()) or not _integer(value.get("waiting"), -1, 2147483647):
		return false
	var assigned: Dictionary = deployment.member_slot_map
	var roles: Dictionary = deployment.member_role_map
	var active_ids: Dictionary = {}
	for member: Variant in active:
		if not _integer(member, 1, 2147483647):
			return false
		var id: int = int(member)
		var key := str(id)
		if active_ids.has(id) or id == int(value.waiting) or not people.has(id) or not assigned.has(key) or int(roles.get(key, -1)) != 0 \
			or not starts.has(key) or not targets.has(key) or not _valid_walkable_pair(data, starts[key]) or not _valid_walkable_pair(data, targets[key]):
			return false
		var start := Vector2i(int(starts[key][0]), int(starts[key][1]))
		var target := Vector2i(int(targets[key][0]), int(targets[key][1]))
		var physical := Vector2i(int(people[id].cell[0]), int(people[id].cell[1]))
		if target != Vector2i(int(assigned[key][0]), int(assigned[key][1])) or physical != start and physical != target or not data.can_step(start, target):
			return false
		active_ids[id] = true
	for field_map: Dictionary in [starts, targets]:
		for key: Variant in field_map:
			if not key is String or not key.is_valid_int() or str(int(key)) != key or not active_ids.has(int(key)):
				return false
	var held_ids: Dictionary = {}
	for member: Variant in hold:
		if not _integer(member, 1, 2147483647) or held_ids.has(int(member)) or not assigned.has(str(int(member))):
			return false
		held_ids[int(member)] = true
	var verified_ids: Dictionary = {}
	for member: Variant in verified:
		if not _integer(member, 1, 2147483647) or verified_ids.has(int(member)) or not assigned.has(str(int(member))):
			return false
		verified_ids[int(member)] = true
	var waiting: int = int(value.waiting)
	if waiting >= 0 and (not assigned.has(str(waiting)) or int(roles.get(str(waiting), -1)) != 0 or not held_ids.has(waiting)):
		return false
	if not queued.is_empty() and (active.size() != 1 or waiting < 0):
		return false
	var expected := Vector2i(-1, -1)
	if waiting >= 0:
		expected = Vector2i(int(assigned[str(waiting)][0]), int(assigned[str(waiting)][1]))
	var queued_ids: Dictionary = {}
	for i in range(queued.size() - 1, -1, -1):
		var step: Variant = queued[i]
		if not step is Dictionary or step.size() != 3 or not _integer(step.get("actor"), 1, 2147483647) \
			or not _valid_walkable_pair(data, step.get("from")) or not _valid_walkable_pair(data, step.get("to")):
			return false
		var id: int = int(step.actor)
		var key := str(id)
		var source := Vector2i(int(step["from"][0]), int(step["from"][1]))
		var target := Vector2i(int(step["to"][0]), int(step["to"][1]))
		if queued_ids.has(id) or active_ids.has(id) or id == waiting or not people.has(id) or not assigned.has(key) \
			or int(roles.get(key, -1)) != 0 or source != Vector2i(int(assigned[key][0]), int(assigned[key][1])) \
			or source != Vector2i(int(people[id].cell[0]), int(people[id].cell[1])) or target != expected or not data.can_step(source, target):
			return false
		queued_ids[id] = true
		expected = source
	if not queued.is_empty() and Vector2i(int(starts[str(int(active[0]))][0]), int(starts[str(int(active[0]))][1])) != Vector2i(int(assigned[str(waiting)][0]), int(assigned[str(waiting)][1])):
		return false
	if waiting < 0 and (not queued.is_empty() or not active.is_empty()):
		return false
	return true

static func _valid_xy_pair(data: TerrainData, value: Variant) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0], -1, data.size.x - 1) and _integer(value[1], -1, data.size.y - 1)

static func _valid_walkable_pair(data: TerrainData, value: Variant) -> bool:
	return _valid_xy_pair(data, value) and data.contains(Vector2i(int(value[0]), int(value[1]))) and data.is_walkable(Vector2i(int(value[0]), int(value[1])))

static func _valid_grid_key(data: TerrainData, key: Variant) -> bool:
	if not key is String: return false
	var parts: PackedStringArray = key.split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int(): return false
	return _valid_walkable_pair(data, [int(parts[0]), int(parts[1])])

static func _validate_vehicles(data: TerrainData, state: Dictionary, check_terrain: bool = false) -> Dictionary:
	var vehicles: Variant = state.get("vehicles", {})
	if not vehicles is Dictionary or vehicles.size() > data.size.x * data.size.y or not _integer(state.get("next_vehicle", 1), 1, 2147483647):
		return Runtime.fail("CORRUPT_SAVE", "車輛資料／序號")
	if vehicles.is_empty(): return Runtime.ok() # Legacy no-vehicle snapshots retain their original validation.
	var people := {}
	var team_counts := {}
	var claims := {}
	var total := 0
	for original_team: Dictionary in state.get("armies", []):
		var team := TerrainArmy.normalize_roster_snapshot(original_team)
		team_counts[int(team.team_id)] = team.units.size()
		total += team.units.size()
		for unit: Dictionary in team.units:
			people[int(unit.person_id)] = {"team": int(team.team_id), "body": unit}
	for actor: Dictionary in state.get("actors", {}).values(): people[int(actor.person_id)] = {"team": 0, "body": actor}
	for identity: int in people:
		var body: Dictionary = people[identity].body
		var cell := Vector2i(int(body.cell[0]), int(body.cell[1]))
		var destination: Array = body.get("destination", [-1, -1])
		var moving := Vector2i(int(destination[0]), int(destination[1])) != TerrainArmy.INVALID_CELL
		if body.has("movement_left") and float(body.movement_left) > 0.0:
			destination = body.movement_from
			moving = true
		if float(body.hp) > 0.0 and float(body.get("ko", body.get("knockout_left", 0.0))) <= 0.0 and not bool(body.get("departed", false)) or moving:
			claims[cell] = identity
			if moving: claims[Vector2i(int(destination[0]), int(destination[1]))] = identity
	var operators := {}
	var guards := {}
	if not state.get("captivity", {}) is Dictionary: return Runtime.fail("CORRUPT_SAVE", "原看守職務格式")
	for relation: Variant in state.get("captivity", {}).values():
		if not relation is Dictionary or not _integer(relation.get("guard_id"), 1, 2147483647): return Runtime.fail("CORRUPT_SAVE", "原看守職務引用")
		guards[int(relation.guard_id)] = true
	for identity: Variant in vehicles:
		var vehicle: Variant = vehicles[identity]
		if not _serial(identity, int(state.get("next_vehicle", 1))) or not vehicle is Dictionary or vehicle.size() != 10 or vehicle.get("id") != identity or not vehicle.get("kind") is String or not Vehicles.CAPACITY.has(vehicle.kind):
			return Runtime.fail("CORRUPT_SAVE", "車輛種類／身分")
		if not _integer(vehicle.get("team_id"), 0, 999999) or not _integer(vehicle.get("operator_id"), 0, 2147483647) or not _valid_cell(data, vehicle.get("cell")) or not vehicle.get("stop_pending") is bool or not vehicle.get("move") is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "車輛所屬／操作人／格位")
		if not _vehicle_facing(vehicle.get("facing")): return Runtime.fail("CORRUPT_SAVE", "車輛方向")
		var team_id := int(vehicle.team_id)
		var operator_id := int(vehicle.operator_id)
		if team_id > 0:
			if not team_counts.has(team_id): return Runtime.fail("CORRUPT_SAVE", "車輛所屬隊伍不存在")
			team_counts[team_id] = int(team_counts[team_id]) + 1
			total += 1
			if int(team_counts[team_id]) > 100: return Runtime.fail("CORRUPT_SAVE", "車隊人物與車輛超過100名額")
		elif operator_id > 0 or not vehicle.move.is_empty(): return Runtime.fail("CORRUPT_SAVE", "停泊無所屬車輛不能自行移動")
		var occupied := {}
		for cell: Vector2i in Vehicles.footprint(data, vehicle): occupied[cell] = true
		var body := {}
		if operator_id > 0:
			if operators.has(operator_id) or guards.has(operator_id) or not people.has(operator_id) or int(people[operator_id].team) != team_id:
				return Runtime.fail("CORRUPT_SAVE", "操作人重複或不屬於原隊")
			operators[operator_id] = true
			body = people[operator_id].body
			# Runtime holder projections require boundary-normalized integer versions.
			# This exact check runs on save and again after load normalization/terrain rebuild.
			if check_terrain and str(vehicle.kind) == "wagon" and not RiderAtlas.supports(Runtime.equipment_appearance(data, body.get("item_state", {}), body.get("appearance", {}), state)):
				return Runtime.fail("MISSING_ASSET", "原馬車騎手資料或固定布裝騎姿素材未就緒")
			var cell := Vector2i(int(body.cell[0]), int(body.cell[1]))
			var direction := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
			if not bool(vehicle.move.get("boarding", false)) and data.cell_from_index(int(vehicle.cell)) != Vehicles.anchor_from_operator(str(vehicle.kind), cell, direction): return Runtime.fail("CORRUPT_SAVE", "人車相對格位失效")
			var moving := Vector2i(int(body.destination[0]), int(body.destination[1])) != TerrainArmy.INVALID_CELL
			if moving == vehicle.move.is_empty(): return Runtime.fail("CORRUPT_SAVE", "原人物與車輛必須共用同一步預約")
			var incapable := float(body.hp) <= 0.0 or float(body.ko) > 0.0 or str(body.pose) == "get_up" or bool(body.captive) or bool(body.departed) or not bool(body.get("member", true))
			var resting_rider: bool = str(vehicle.kind) == "wagon" and float(body.hp) > 0.0 and (float(body.ko) > 0.0 or str(body.pose) == "get_up") and not bool(body.captive) and not bool(body.departed) and bool(body.get("member", true)) and vehicle.move.is_empty() and bool(vehicle.stop_pending)
			if incapable and (vehicle.move.is_empty() or not bool(vehicle.stop_pending)) and not resting_rider: return Runtime.fail("CORRUPT_SAVE", "失能操作人不能開始新車步")
			if vehicle.move.is_empty() and bool(vehicle.stop_pending) and not resting_rider: return Runtime.fail("CORRUPT_SAVE", "停止旗標僅限在途步進或原馬背昏迷者")
			if not body.get("work_task", {}).is_empty(): return Runtime.fail("CORRUPT_SAVE", "操作人不能兼任工作")
		elif not vehicle.move.is_empty() or bool(vehicle.stop_pending): return Runtime.fail("CORRUPT_SAVE", "無真人操作卻有車步")
		if not vehicle.move.is_empty():
			var move: Dictionary = vehicle.move
			var boarding := bool(move.get("boarding", false))
			var dismount := bool(move.get("dismount", false))
			if move.size() != 5 + int(boarding) + int(dismount) or boarding and dismount or not move.get("boarding", false) is bool or not move.get("dismount", false) is bool or not _valid_cell(data, move.get("cell")) or not _valid_cell(data, move.get("operator_from")) or not _valid_cell(data, move.get("operator_to")) or not _vehicle_facing(move.get("facing")) or not move.get("sweep") is Array:
				return Runtime.fail("CORRUPT_SAVE", "人車預約欄位")
			var from := data.cell_from_index(int(move.operator_from))
			var to := data.cell_from_index(int(move.operator_to))
			var direction := Vector2i(int(move.facing[0]), int(move.facing[1]))
			var previous_direction := Vector2i(int(vehicle.facing[0]), int(vehicle.facing[1]))
			var expected_direction := previous_direction if to - from == -previous_direction else to - from
			if from != Vector2i(int(body.cell[0]), int(body.cell[1])) or to != Vector2i(int(body.destination[0]), int(body.destination[1])) or absi(to.x - from.x) + absi(to.y - from.y) != 1:
				return Runtime.fail("CORRUPT_SAVE", "車步未引用原人物預約")
			if boarding or dismount:
				var horse_cell := data.cell_from_index(int(vehicle.cell)) + previous_direction * 2
				if str(vehicle.kind) != "wagon" or int(move.cell) != int(vehicle.cell) or direction != previous_direction or boarding and to != horse_cell or dismount and (from != horse_cell or Vehicles.footprint(data, vehicle).has(to) or not bool(vehicle.stop_pending)):
					return Runtime.fail("CORRUPT_SAVE", "上下馬必须引用原馬格與真人一步，車體保持停止")
			elif direction != expected_direction or data.cell_from_index(int(move.cell)) != Vehicles.anchor_from_operator(str(vehicle.kind), to, direction):
				return Runtime.fail("CORRUPT_SAVE", "原騎乘／推車位置不符")
			var minimum := from
			var maximum := from
			for cell: Vector2i in Vehicles.footprint(data, vehicle) + Vehicles.footprint(data, vehicle, true) + [to]:
				minimum = Vector2i(mini(minimum.x, cell.x), mini(minimum.y, cell.y))
				maximum = Vector2i(maxi(maximum.x, cell.x), maxi(maximum.y, cell.y))
			var expected := {}
			for y in range(minimum.y, maximum.y + 1):
				for x in range(minimum.x, maximum.x + 1): expected[data.index(Vector2i(x, y))] = true
			var actual := {}
			for value: Variant in move.sweep:
				if not _valid_cell(data, value) or actual.has(int(value)): return Runtime.fail("CORRUPT_SAVE", "車輛掃掠預約重複／越界")
				actual[int(value)] = true
				occupied[data.cell_from_index(int(value))] = true
			if expected != actual: return Runtime.fail("CORRUPT_SAVE", "車輛轉彎掃掠預約不完整")
		for cell: Vector2i in occupied:
			if not data.contains(cell) or check_terrain and not data.is_walkable(cell) or claims.has(cell) and claims[cell] != operator_id:
				return Runtime.fail("CORRUPT_SAVE", "車輛與人物／車輛占格預約衝突")
			if check_terrain:
				for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
					if occupied.has(cell + direction) and not data.can_step(cell, cell + direction): return Runtime.fail("CORRUPT_SAVE", "車輛跨越非法地勢")
			claims[cell] = "vehicle:" + str(identity)
	if total > 300: return Runtime.fail("CORRUPT_SAVE", "三隊人物與車輛合計超過300名額")
	return Runtime.ok()

static func _vehicle_facing(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _integer(value[0], -1, 1) and _integer(value[1], -1, 1) and absi(int(value[0])) + absi(int(value[1])) == 1

static func _valid_cells(data: TerrainData, value: Variant, maximum: int) -> bool:
	if not value is Array or value.is_empty() or value.size() > maximum:
		return false
	var seen := {}
	for cell: Variant in value:
		if not _valid_cell(data, cell) or seen.has(int(cell)):
			return false
		seen[int(cell)] = true
	return true

static func _validate_supply(state: Dictionary) -> Dictionary:
	var supplies: Variant = state.get("team_supply", {})
	var personal: Variant = state.get("person_supply", {})
	if not supplies is Dictionary or not personal is Dictionary:
		return Runtime.fail("CORRUPT_SAVE", "隊伍供養資料")
	if supplies.is_empty() and personal.is_empty():
		return Runtime.ok() # Legacy snapshots have no institutional state to regenerate.
	if not _integer(state.get("minute"), 0, 1000000000) or not _number(state.get("phase"), 0, 0.999999999):
		return Runtime.fail("CORRUPT_SAVE", "供養時鐘")
	var site_seconds := (float(state.minute) + float(state.phase)) * 60.0
	var members := {}
	var teams := {}
	if not state.get("actors", {}) is Dictionary or not state.get("armies", []) is Array:
		return Runtime.fail("CORRUPT_SAVE", "供養人物名冊")
	for actor: Variant in state.get("actors", {}).values():
		if not actor is Dictionary or not _integer(actor.get("person_id"), 1, 2147483647):
			return Runtime.fail("CORRUPT_SAVE", "供養人物引用")
		members[int(actor.person_id)] = actor
	for original_team: Variant in state.get("armies", []):
		if not original_team is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "供養隊伍引用")
		var team := TerrainArmy.normalize_roster_snapshot(original_team)
		if not team.get("units") is Array or not _integer(team.get("team_id"), 1, 999999):
			return Runtime.fail("CORRUPT_SAVE", "供養隊伍引用")
		teams[int(team.team_id)] = true
		for unit: Variant in team.units:
			if not unit is Dictionary or not _integer(unit.get("person_id"), 1, 2147483647):
				return Runtime.fail("CORRUPT_SAVE", "供養軍隊人物引用")
			members[int(unit.person_id)] = unit
	var feeding: Array = []
	var maximum_supply_team := 0
	for key: Variant in supplies:
		var supply: Variant = supplies[key]
		if not _serial(key, 1000000) or not supply is Dictionary or supply.size() != 8 or not _integer(supply.get("version"), 1, 1):
			return Runtime.fail("CORRUPT_SAVE", "隊伍供養版本／身分")
		maximum_supply_team = maxi(maximum_supply_team, int(key))
		if not supply.get("sustain") is Dictionary or not Sustain.validate(supply.sustain, members):
			return Runtime.fail("CORRUPT_SAVE", "供餐／缺糧／士氣歷史")
		if float(supply.sustain.at) > site_seconds + 0.00001:
			return Runtime.fail("CORRUPT_SAVE", "供養時鐘超前 Site")
		if not supply.sustain.cohorts.is_empty() and float(supply.sustain.at) < site_seconds - 0.00001:
			return Runtime.fail("CORRUPT_SAVE", "有成員的供養時鐘落後 Site，不能跳過缺糧或餐份時段")
		if not _saved_resource_stack(supply.get("inventory")) or not supply.get("training_order") is bool or not _integer(supply.get("training_requester"), -1, 2147483647) or not _integer(supply.get("revision"), 0, 2147483647):
			return Runtime.fail("CORRUPT_SAVE", "隊伍庫存／訓練指令")
		for resource: String in supply.inventory:
			if resource not in Sustain.FOODS:
				return Runtime.fail("CORRUPT_SAVE", "隊伍口糧含非食物")
		if not supply.get("delivery") is Dictionary or not supply.get("life_checkpoint") is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "隊伍交付／生死事件")
		if not supply.delivery.is_empty():
			return Runtime.fail("BUSY", "口糧交付尚未完成；物資仍在原處，本版等動作結束後保存")
		var supplied := {}
		for cohort: Dictionary in supply.sustain.cohorts:
			for identity: Variant in cohort.ids:
				supplied[str(int(identity))] = true
		if supply.life_checkpoint.size() != supplied.size():
			return Runtime.fail("CORRUPT_SAVE", "供養生死事件名單不符")
		for identity: Variant in supply.life_checkpoint:
			if not identity is String or not supplied.has(identity) or not _integer(supply.life_checkpoint[identity], 0, 2):
				return Runtime.fail("CORRUPT_SAVE", "供養生死事件引用")
		if not teams.has(int(key)) and not supplied.is_empty():
			return Runtime.fail("CORRUPT_SAVE", "已移除隊伍仍供養人物")
		if bool(supply.training_order):
			if not supplied.has(str(int(supply.training_requester))):
				return Runtime.fail("CORRUPT_SAVE", "訓練下令人已不在供養名冊")
		elif int(supply.training_requester) != -1:
			return Runtime.fail("CORRUPT_SAVE", "無訓練命令卻保留下令人")
		feeding.append(supply.sustain)
	if not supplies.is_empty() and not _integer(state.get("army_next_team"), maximum_supply_team + 1, 999999):
		return Runtime.fail("CORRUPT_SAVE", "供糧庫存的原隊伍身分不可重新使用")
	for key: Variant in personal:
		var sustain: Variant = personal[key]
		if not _serial(key, 2147483648) or not members.has(int(key)) or not sustain is Dictionary or not Sustain.validate(sustain, members):
			return Runtime.fail("CORRUPT_SAVE", "私人供養必須引用原人物及有效餐份歷史")
		if float(sustain.at) > site_seconds + 0.00001:
			return Runtime.fail("CORRUPT_SAVE", "私人供養時鐘超前 Site")
		if not sustain.cohorts.is_empty() and float(sustain.at) < site_seconds - 0.00001:
			return Runtime.fail("CORRUPT_SAVE", "有成員的私人供養時鐘落後 Site，不能跳過缺糧或餐份時段")
		for cohort: Dictionary in sustain.cohorts:
			for identity: Variant in cohort.ids:
				if int(identity) != int(key):
					var relation: Dictionary = state.get("captivity", {}).get(str(int(identity)), {})
					if float(members[int(identity)].hp) > 0.0 and int(relation.get("captor_id", -1)) != int(key):
						return Runtime.fail("CORRUPT_SAVE", "私人餐份只能供養本人及實際由本人拘押的原俘虜")
		feeding.append(sustain)
	if not Sustain.validate_owners(feeding, members):
		return Runtime.fail("CORRUPT_SAVE", "同一人物有重複供養來源")
	return Runtime.ok()

static func _validate_person_allocator(state: Dictionary) -> Dictionary:
	if not state.has("next_person_id"):
		return Runtime.ok() # Original-owner initialization performs the explicit legacy scan.
	if not _integer(state.next_person_id, 1, 2147483647) or int(state.next_person_id) == TerrainArmy.PLAYER_MEMBER:
		return Runtime.fail("CORRUPT_SAVE", "人物身分序號")
	var maximum := 0
	for actor: Dictionary in state.get("actors", {}).values():
		maximum = maxi(maximum, int(actor.person_id))
	for original_team: Dictionary in state.get("armies", []):
		for identity: Variant in TerrainArmy.snapshot_person_ids(original_team):
			maximum = maxi(maximum, int(identity))
	for record: Dictionary in state.get("item_records", {}).values():
		maximum = maxi(maximum, int(record.original_owner))
	for container: Dictionary in state.get("ground_loot", {}).values():
		maximum = maxi(maximum, int(container.original_owner))
	for relation: Dictionary in state.get("captivity", {}).values():
		maximum = maxi(maximum, maxi(int(relation.captor_id), int(relation.guard_id)))
	if int(state.next_person_id) <= maximum:
		return Runtime.fail("CORRUPT_SAVE", "人物身分序號會重用現有人物或遺留物原物主")
	return Runtime.ok()

static func _validate_items(data: TerrainData, state: Dictionary) -> Dictionary:
	if not _integer(state.get("item_storage_version"), Runtime.ITEM_STORAGE_VERSION, Runtime.ITEM_STORAGE_VERSION):
		return Runtime.fail("CORRUPT_SAVE", "物品資料版本")
	for field: String in ["item_definitions", "item_records", "ground_loot", "depot_items"]:
		if not state.get(field) is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "物品欄位：" + field)
	for field: String in ["next_item", "next_loot"]:
		if not _integer(state.get(field), 1, 2147483647):
			return Runtime.fail("CORRUPT_SAVE", "物品序號")
	for identity: Variant in state.item_definitions:
		if not Runtime.valid_item_definition(identity, state.item_definitions[identity]):
			return Runtime.fail("CORRUPT_SAVE", "共用裝備定義")
	for identity: Variant in state.item_records:
		var record: Variant = state.item_records[identity]
		if not _serial(identity, int(state.next_item)) or not record is Dictionary or record.size() != 3 + int(record.has("dye_color")):
			return Runtime.fail("CORRUPT_SAVE", "裝備身分")
		if not record.get("definition") is String or not state.item_definitions.has(record.definition) or not _integer(record.get("original_owner"), 1, 2147483647) or not record.get("holder") is String:
			return Runtime.fail("CORRUPT_SAVE", "裝備定義／物主引用")
		if record.has("dye_color") and (not Runtime.EquipmentDye.valid_color(record.dye_color) or str(state.item_definitions[record.definition].slot) not in Runtime.EquipmentDye.SLOTS):
			return Runtime.fail("CORRUPT_SAVE", "裝備染色格式／槽位")
	var locations := {}
	var result := _validate_item_holder(state.depot_items, "depot", state, locations, state.get("inventory", {}), int(state.get("capacity", 0)))
	if not result.ok:
		return result
	if not state.get("vehicles", {}) is Dictionary:
		return Runtime.fail("CORRUPT_SAVE", "車輛持物資料")
	for identity: Variant in state.get("vehicles", {}):
		var vehicle: Variant = state.vehicles[identity]
		if not vehicle is Dictionary or not vehicle.get("kind") is String or not Vehicles.CAPACITY.has(vehicle.kind):
			return Runtime.fail("CORRUPT_SAVE", "車輛種類／持物資料")
		result = _validate_item_holder(vehicle.get("holder"), "vehicle:" + str(identity), state, locations, vehicle.get("cargo"), int(Vehicles.CAPACITY[vehicle.kind]))
		if not result.ok: return result
		if not vehicle.holder.equipped.is_empty(): return Runtime.fail("CORRUPT_SAVE", "車輛不能穿戴裝備，所有實物均占載量")
	for identity: Variant in state.ground_loot:
		var container: Variant = state.ground_loot[identity]
		if not _serial(identity, int(state.next_loot)) or not container is Dictionary or container.size() != 8 + int(container.has("open_rations")):
			return Runtime.fail("CORRUPT_SAVE", "遺留物身分")
		if not _number(container.get("open_rations", 0.0), 0.0, 1000000.0):
			return Runtime.fail("CORRUPT_SAVE", "現場開封口糧數量")
		if container.get("kind") not in ["remains", "sealed", "cargo"] or not _integer(container.get("original_owner"), 1, 2147483647) or not _valid_cell(data, container.get("cell")):
			return Runtime.fail("CORRUPT_SAVE", "遺留物種類／位置")
		result = _validate_item_holder(container, "ground:" + identity, state, locations, container.get("cargo"), 1000000)
		if not result.ok:
			return result
		if float(Runtime.carried_size(container.cargo, container)) + float(container.get("open_rations", 0.0)) > 1000000.0:
			return Runtime.fail("CORRUPT_SAVE", "現場物資與開封口糧合計超量")
	var actors: Variant = state.get("actors", {})
	var armies: Variant = state.get("armies", [])
	if not actors is Dictionary or not armies is Array:
		return Runtime.fail("CORRUPT_SAVE", "物品持有人名冊")
	for key: Variant in actors:
		var actor: Variant = actors[key]
		if not actor is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "物品持有人")
		var death_validation := _validate_remains(actor, state, state.get("manual" if key == "player" else "worker", {}).get("cargo", {}))
		if not death_validation.ok:
			return death_validation
		if not actor.has("item_state"):
			continue # Explicit legacy body migration is owned by the original person.
		var worker: Variant = state.get("manual" if key == "player" else "worker", {})
		if not worker is Dictionary or not _integer(actor.get("person_id"), 1, 2147483647):
			return Runtime.fail("CORRUPT_SAVE", "物品持有人引用")
		result = _validate_item_holder(actor.item_state, "person:" + str(int(actor.person_id)), state, locations, worker.get("cargo"), Runtime.CARRY_CAPACITY)
		if not result.ok:
			return result
	for original_team: Variant in armies:
		if not original_team is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "軍隊物品名冊")
		var team := TerrainArmy.normalize_roster_snapshot(original_team)
		if not team.get("units") is Array:
			return Runtime.fail("CORRUPT_SAVE", "軍隊物品名冊")
		for unit: Variant in team.units:
			if not unit is Dictionary:
				return Runtime.fail("CORRUPT_SAVE", "軍隊物品持有人")
			if unit.has("appearance") and not HumanCharacter3DEditor.valid_appearance(unit.appearance):
				return Runtime.fail("CORRUPT_SAVE", "原軍隊人物外觀")
			var death_validation := _validate_remains(unit, state, unit.get("cargo", {}))
			if not death_validation.ok:
				return death_validation
			if not unit.has("item_state"):
				if unit.has("cargo") and not _saved_resource_stack(unit.cargo):
					return Runtime.fail("CORRUPT_SAVE", "軍隊隨身資源")
				continue
			if not _integer(unit.get("person_id"), 1, 2147483647):
				return Runtime.fail("CORRUPT_SAVE", "軍隊物品持有人引用")
			result = _validate_item_holder(unit.item_state, "person:" + str(int(unit.person_id)), state, locations, unit.get("cargo", {}), Runtime.CARRY_CAPACITY)
			if not result.ok:
				return result
	if locations.size() != state.item_records.size():
		return Runtime.fail("CORRUPT_SAVE", "裝備沒有唯一實際位置")
	return _validate_captivity(data, state)

static func _validate_captivity(data: TerrainData, state: Dictionary) -> Dictionary:
	var relations: Variant = state.get("captivity", {})
	if not relations is Dictionary or relations.size() > 302:
		return Runtime.fail("CORRUPT_SAVE", "拘押關係欄位")
	var people := {}
	for actor: Dictionary in state.get("actors", {}).values():
		people[int(actor.person_id)] = actor
	for team: Dictionary in state.get("armies", []):
		for unit: Dictionary in TerrainArmy.normalize_roster_snapshot(team).units:
			people[int(unit.person_id)] = unit
	if not EquipmentOrders.valid_nations(state.get("equipment_nations", {}), state.item_definitions, people):
		return Runtime.fail("CORRUPT_SAVE", "原國別／軍事首長／正式配裝標準")
	if state.has("controlled_person_id") and (not _integer(state.controlled_person_id, 1, 2147483647) or not people.has(int(state.controlled_person_id))):
		return Runtime.fail("CORRUPT_SAVE", "受控原人物不存在")
	if state.has("family") and not FamilyContinuity.validate_family(state.family):
		return Runtime.fail("CORRUPT_SAVE", "家族原人物引用名單")
	if not CaptiveEscort.valid_orders(state.get("escort_orders", {}), data.size.x * data.size.y, people, relations):
		return Runtime.fail("CORRUPT_SAVE", "原人押送命令／拘押引用")
	var guarded := {}
	for key: Variant in relations:
		var relation: Variant = relations[key]
		if not _serial(key, 2147483648) or not relation is Dictionary or relation.size() != 5 or not _integer(relation.get("version"), 1, 1):
			return Runtime.fail("CORRUPT_SAVE", "拘押身分／版本")
		for field: String in ["captor_id", "guard_id"]:
			if not _integer(relation.get(field), 1, 2147483647) or int(relation[field]) == int(key) or int(relation[field]) == TerrainArmy.PLAYER_MEMBER:
				return Runtime.fail("CORRUPT_SAVE", "拘押者／看守原人物引用")
		if not _integer(relation.get("captor_faction"), 0, 100000000) or not relation.get("sealed_container") is String:
			return Runtime.fail("CORRUPT_SAVE", "拘押陣營／封存包")
		var target: Dictionary = people.get(int(key), {})
		if target.is_empty() or not _number(target.get("hp"), 0.000000001, 100.0) or target.get("captive") != true:
			return Runtime.fail("CORRUPT_SAVE", "拘押關係必須引用原存活被俘人物")
		var sealed := str(relation.sealed_container)
		if not sealed.is_empty():
			if not _serial(sealed, int(state.next_loot)):
				return Runtime.fail("CORRUPT_SAVE", "封存包序號")
			var container: Dictionary = state.ground_loot.get(sealed, {})
			if not container.is_empty() and (container.kind != "sealed" or int(container.original_owner) != int(key)):
				return Runtime.fail("CORRUPT_SAVE", "封存包不是原受俘者的實物")
		var guard_id := int(relation.guard_id)
		guarded[guard_id] = int(guarded.get(guard_id, 0)) + 1
		if int(guarded[guard_id]) > 4:
			return Runtime.fail("CORRUPT_SAVE", "同一原看守超過四位俘虜")
	return Runtime.ok()

static func _validate_settled_opened_food(state: Dictionary) -> Dictionary:
	# Saves use the new invariant; load permits old format-3 shape first and
	# invokes the idempotent migration before enforcing this same guard.
	var people: Array = state.get("actors", {}).values()
	for team: Dictionary in state.get("armies", []):
		people.append_array(team.units)
	for person: Dictionary in people:
		if bool(person.get("loot_settled", false)) and float(state.get("person_supply", {}).get(str(int(person.person_id)), {}).get("open_rations", 0.0)) != 0.0:
			return Runtime.fail("CORRUPT_SAVE", "已結算死者仍持有未轉存的私人開封口糧")
	return Runtime.ok()

static func _validate_remains(person: Dictionary, state: Dictionary, cargo: Variant) -> Dictionary:
	if not person.get("loot_settled", false) is bool or not person.get("remains_id", "") is String:
		return Runtime.fail("CORRUPT_SAVE", "人物遺物結算欄位")
	var settled: bool = person.get("loot_settled", false)
	var remains_reference := str(person.get("remains_id", ""))
	if not settled:
		return Runtime.ok() if remains_reference.is_empty() else Runtime.fail("CORRUPT_SAVE", "未結算卻引用遺物")
	if not person.has("item_state") or not _number(person.get("hp"), 0, 0) or not cargo is Dictionary or Runtime.inventory_size(cargo) != 0 or not person.item_state.get("item_ids", []).is_empty():
		return Runtime.fail("CORRUPT_SAVE", "已轉存死者仍持有物品／非死亡")
	if not remains_reference.is_empty():
		if not _serial(remains_reference, int(state.next_loot)):
			return Runtime.fail("CORRUPT_SAVE", "遺物引用序號")
		var container: Dictionary = state.ground_loot.get(remains_reference, {})
		# Empty containers may have been reclaimed; IDs are never reused.
		if not container.is_empty() and (container.kind != "remains" or int(container.original_owner) != int(person.person_id)):
			return Runtime.fail("CORRUPT_SAVE", "遺物引用不是原死者")
	return Runtime.ok()

static func _validate_item_holder(holder: Variant, expected: String, state: Dictionary, locations: Dictionary, cargo: Variant, capacity: int) -> Dictionary:
	if not holder is Dictionary or holder.get("holder") != expected or not _integer(holder.get("version"), 0, 2147483647) or not holder.get("item_ids") is Array or not holder.get("equipped") is Dictionary or not _saved_resource_stack(cargo):
		return Runtime.fail("CORRUPT_SAVE", "物品持有欄位")
	if not expected.begins_with("ground:") and holder.size() != 4:
		return Runtime.fail("CORRUPT_SAVE", "物品持有欄位")
	var worn := {}
	for identity: Variant in holder.item_ids:
		if not identity is String or locations.has(identity) or not state.item_records.has(identity) or str(state.item_records[identity].holder) != expected:
			return Runtime.fail("CORRUPT_SAVE", "同件裝備重複／不存在／持有人不符")
		locations[identity] = expected
	for slot: Variant in holder.equipped:
		var identity: Variant = holder.equipped[slot]
		if not slot is String or not identity is String or not holder.item_ids.has(identity) or worn.has(identity):
			return Runtime.fail("CORRUPT_SAVE", "實裝引用不存在／同物重複穿戴")
		var definition: Dictionary = state.item_definitions[state.item_records[identity].definition]
		if slot != str(definition.slot):
			return Runtime.fail("CORRUPT_SAVE", "裝備槽不符")
		worn[identity] = true
	if Runtime.carried_size(cargo, holder) > capacity:
		return Runtime.fail("CORRUPT_SAVE", "資源及裝備合計攜帶超量")
	if expected.begins_with("person:"):
		var personal: Variant = state.get("person_supply", {})
		if not personal is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "原私人餐份欄位")
		var pool: Variant = personal.get(expected.trim_prefix("person:"), {})
		if not pool is Dictionary or not _number(pool.get("open_rations", 0.0), 0.0, 1000000.0):
			return Runtime.fail("CORRUPT_SAVE", "原私人開封口糧")
		if float(Runtime.carried_size(cargo, holder)) + float(pool.get("open_rations", 0.0)) > capacity:
			return Runtime.fail("CORRUPT_SAVE", "私人開封口糧與原行囊合計超量")
	return Runtime.ok()

static func _saved_resource_stack(cargo: Variant) -> bool:
	if not cargo is Dictionary:
		return false
	for resource: Variant in cargo:
		if not (resource is String or resource is StringName) or not Env.ITEM_NAMES.has(str(resource)) or not _integer(cargo[resource], 0, 1000000):
			return false
	return true

static func _serial(value: Variant, next_value: int) -> bool:
	return value is String and value.is_valid_int() and str(int(value)) == value and int(value) > 0 and int(value) < next_value

static func _valid_cell(data: TerrainData, value: Variant) -> bool:
	return _integer(value, 0, data.size.x * data.size.y - 1)

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value, minimum, maximum) and float(value) == floorf(float(value))

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum
