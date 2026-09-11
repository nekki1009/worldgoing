class_name SiteStore
extends RefCounted

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const FORMAT := 1
const TERRAIN_VERSION := 1
const DEFAULT_PATH := "user://sites/current.json"
const MAX_BYTES := 8 * 1024 * 1024

static func save(data: TerrainData, path: String = DEFAULT_PATH) -> Dictionary:
	if data == null or data.site.is_empty():
		return Runtime.fail("NO_TARGET")
	if float(data.site.combat_left) > 0.0:
		return Runtime.fail("BUSY", "地圖保存會等到脫戰；本版不保存戰鬥中的角色與投射物")
	var state: Dictionary = data.site.duplicate(true)
	state.erase("water_links")
	state.erase("water_status")
	state["notices"] = []
	var params: Dictionary = data.parameters.duplicate()
	params["size"] = [data.size.x, data.size.y]
	var payload := {"format": FORMAT, "terrain_version": TERRAIN_VERSION, "environment_version": Env.VERSION,
		"preset": data.preset, "seed": data.seed_value, "parameters": params, "state": state}
	var body := JSON.stringify(payload, "", true, true)
	var envelope := JSON.stringify({"checksum": body.sha256_text(), "payload": body}, "\t")
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
	if not data.is_walkable(data.cell_from_index(int(data.site.worker.cell))) or not data.is_walkable(data.cell_from_index(int(data.site.get("player_cell", data.site.depot_cell)))):
		return Runtime.fail("CORRUPT_SAVE", "角色位於阻擋格")
	return Runtime.ok("已載入地圖；接續保存時刻", {"data": data})

static func _normalize_state(state: Dictionary) -> void:
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
	if int(payload.get("format", -1)) != FORMAT or int(payload.get("terrain_version", -1)) != TERRAIN_VERSION or int(payload.get("environment_version", -1)) != Env.VERSION:
		return Runtime.fail("SAVE_VERSION", "生成／存檔版本不同，原檔保留")
	if not payload.get("state") is Dictionary or not payload.get("parameters") is Dictionary:
		return Runtime.fail("CORRUPT_SAVE")
	if not _integer(payload.get("seed"), -2147483648, 2147483647) or not _integer(payload.get("preset"), 0, TerrainPreset.NAMES.size() - 1):
		return Runtime.fail("CORRUPT_SAVE", "seed／地貌非法")
	var size_value: Variant = payload.parameters.get("size")
	if not size_value is Array or size_value.size() != 2 or not _integer(size_value[0], 16, 128) or not _integer(size_value[1], 16, 128):
		return Runtime.fail("CORRUPT_SAVE", "地圖大小非法")
	if not _number(payload.parameters.get("max_height"), 1, 5) or not _number(payload.parameters.get("micro_strength"), 0, 0.04):
		return Runtime.fail("CORRUPT_SAVE", "生成參數非法")
	return Runtime.ok("", {"payload": payload})

static func _validate_state(data: TerrainData, state: Dictionary) -> Dictionary:
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
	if state.has("player_cell") and not _valid_cell(data, state.player_cell):
		return Runtime.fail("CORRUPT_SAVE", "玩家格位")
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

static func _valid_cell(data: TerrainData, value: Variant) -> bool:
	return _integer(value, 0, data.size.x * data.size.y - 1)

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value, minimum, maximum) and float(value) == floorf(float(value))

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum
