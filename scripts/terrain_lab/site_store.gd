class_name SiteStore
extends RefCounted

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const EquipmentOrders = preload("res://scripts/terrain_lab/site_equipment_orders.gd")
const CaptiveEscort = preload("res://scripts/terrain_lab/site_captive_escort.gd")
const FamilyContinuity = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const WorkTeam = preload("res://scripts/terrain_lab/site_work_team.gd")
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
		return Runtime.fail("BUSY", "軍隊交戰快照尚未接入；請明確結束兩隊近戰測試後保存，避免默默遺失傷亡")
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
	var actor_validation := _validate_actors(data, state)
	if not actor_validation.ok:
		return actor_validation
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
	var validation := _validate_state(data, payload.state)
	if not validation.ok:
		return validation
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
	for key: String in data.site.terrain_changes:
		data.height_levels[int(key)] = int(data.site.terrain_changes[key])
	if not data.site.terrain_changes.is_empty():
		Runtime.rebuild_terrain_edges(data)
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
	if not data.site.get("armies", []).is_empty() and not TerrainArmy.load_combat_bake():
		return Runtime.fail("MISSING_ASSET", "軍隊圖集／碰撞資料缺失；未替換目前地圖")
	# Earlier format-3 deaths may have left real opened food at their private
	# owner. Migrate the validated loaded copy only, never rewrite the source file
	# or rerun the original person's death/animation/equipment initialization.
	var opened_migration := Runtime.migrate_settled_opened_food(data)
	if not opened_migration.ok:
		return opened_migration
	var opened_validation := _validate_settled_opened_food(data.site)
	if not opened_validation.ok:
		return opened_validation
	return Runtime.ok("已載入地圖；接續保存時刻" + ("（舊地圖沒有角色快照，首次使用初始角色狀態）" if bool(payload.get("legacy_actor_state", false)) else ""), {"data": data})

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
	for container: Dictionary in state.ground_loot.values():
		container.cell = int(container.cell)
		container.original_owner = int(container.original_owner)
		for resource: String in container.cargo:
			container.cargo[resource] = int(container.cargo[resource])
		item_holders.append(container)
	for actor: Dictionary in state.get("actors", {}).values():
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
	var actor_validation := _validate_actors(data, state)
	if not actor_validation.ok:
		return actor_validation
	var item_validation := _validate_items(data, state)
	if not item_validation.ok:
		return item_validation
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
	if actors.size() != 2 or not actors.has("player") or not actors.has("npc"):
		return Runtime.fail("CORRUPT_SAVE", "人物快照不完整")
	if not state.get("worker") is Dictionary or not _valid_cell(data, state.worker.get("cell")) or not _valid_cell(data, state.get("player_cell", data.index(data.spawn_cell))):
		return Runtime.fail("CORRUPT_SAVE", "人物地圖格位")
	var identities := {}
	for key: String in ["player", "npc"]:
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
	if not armies is Array or armies.size() > 2:
		return Runtime.fail("CORRUPT_SAVE", "軍隊名冊格式")
	var identities := {}
	var claims := {}
	var maximum_team := 0
	var teams_seen := {}
	var total_rows := 0 # Current Site acceptance remains bounded to 200 actual army rows.
	var live_presenters := 0 # Only the two original army women own live presenters.
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
		if not TerrainArmy.valid_combat_state(original_team, data, member_actor):
			return Runtime.fail("CORRUPT_SAVE", "軍隊人物／動作／指揮關係非法")
		var team := TerrainArmy.normalize_roster_snapshot(original_team)
		if teams_seen.has(int(team.team_id)):
			return Runtime.fail("CORRUPT_SAVE", "重複隊伍身分")
		teams_seen[int(team.team_id)] = true
		total_rows += team.units.size()
		if total_rows > 200:
			return Runtime.fail("CORRUPT_SAVE", "目前 Site 上限為 200 列軍隊人物")
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
			live_presenters += int(str(unit.visual_role) == "female_live")
			if live_presenters > 2:
				return Runtime.fail("CORRUPT_SAVE", "目前 Site 只有兩個原隊長呈現者")
			var cell := Vector2i(int(unit.cell[0]), int(unit.cell[1]))
			var destination := Vector2i(int(unit.destination[0]), int(unit.destination[1]))
			if check_terrain and (not data.is_walkable(cell) or destination != TerrainArmy.INVALID_CELL and not data.can_step(cell, destination)):
				return Runtime.fail("CORRUPT_SAVE", "軍隊格位／移動跨越非法地形")
			var standing := float(unit.hp) > 0.0 and float(unit.ko) <= 0.0 and not bool(unit.departed)
			for claim: Vector2i in ([cell, destination] if destination != TerrainArmy.INVALID_CELL else ([cell] if standing else [])):
				if claims.has(claim):
					return Runtime.fail("CORRUPT_SAVE", "軍隊占位／預約重疊")
				claims[claim] = identity
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
	if not relations is Dictionary or relations.size() > 202:
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
