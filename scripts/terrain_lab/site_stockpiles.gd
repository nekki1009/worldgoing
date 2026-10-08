class_name SiteStockpiles
extends RefCounted

# Only storage locations for the original Site resources and item records.
# People, transport, production and construction retain their existing owners.
const Runtime := preload("res://scripts/terrain_lab/site_runtime.gd")

static func eligible(feature: Dictionary) -> bool:
	var kind := str(feature.get("kind", ""))
	return kind == "warehouse" or Runtime.FEATURES.has(kind) and Runtime.FEATURES[kind].has("input")

static func capacity(feature: Dictionary) -> int:
	if not eligible(feature): return 0
	var grade := int(feature.get("building_grade", 1))
	if grade < 1 or grade > 3: return 0
	return (60 if str(feature.kind) == "warehouse" else 20) * (grade + 1)

static func identity(key: String) -> String:
	return "feature:" + key

static func storage(data: TerrainData, key: String) -> Dictionary:
	return data.site.get("stockpiles", {}).get(key, {})

static func ensure_storage(data: TerrainData, key: String, faction: int) -> Dictionary:
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	if not eligible(feature) or str(feature.get("stage", "")) != "complete": return Runtime.fail("NO_TARGET")
	if int(feature.get("owner_faction", -1)) < 0 or int(feature.owner_faction) != faction: return Runtime.fail("NO_AUTHORITY")
	if feature.has("pending_build") or feature.has("repair"): return Runtime.fail("BUSY")
	if int(data.site.get("item_storage_version", 0)) != Runtime.ITEM_STORAGE_VERSION: return Runtime.fail("INVALID", "原實物持有資料尚未初始化")
	if not data.site.has("stockpiles"): data.site.stockpiles = {}
	if not data.site.stockpiles.has(key):
		data.site.stockpiles[key] = {"version": 1, "cargo": {}, "holder": Runtime.new_item_state(identity(key))}
		data.environment_revision += 1
	return Runtime.ok("已啟用原設施的現場庫存", {"stock": data.site.stockpiles[key]})

static func set_local_supply(data: TerrainData, key: String, enabled: bool, faction: int) -> Dictionary:
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	if not eligible(feature) or str(feature.get("kind", "")) == "warehouse": return Runtime.fail("NO_TARGET")
	if bool(feature.get("batch_paid", false)) or float(feature.get("production", 0.0)) != 0.0 or Runtime._feature_has_work(data, key):
		return Runtime.fail("BUSY", "先停止原加工工作並領出已付批次")
	for zone: Dictionary in data.site.get("zones", []):
		if str(zone.get("feature", "")) == key and str(zone.get("action", "")) == "operate" and bool(zone.get("active", false)):
			return Runtime.fail("BUSY", "先停止原加工工作區，才可切換供料位置")
	var checked := ensure_storage(data, key, faction)
	if not checked.ok: return checked
	if enabled: feature.supply_mode = "local"
	else: feature.erase("supply_mode")
	data.environment_revision += 1
	return Runtime.ok("加工由本人實際卸入的現場物資供料" if enabled else "加工沿原營地供料")

static func removal_guard(data: TerrainData, key: String) -> Dictionary:
	var stock := storage(data, key)
	if not stock.is_empty() and (Runtime.inventory_size(stock.cargo) != 0 or not stock.holder.item_ids.is_empty()):
		return Runtime.fail("BUSY", "先沿原装卸入口取出設施全部原物資")
	return Runtime.ok()

static func stock_endpoint(data: TerrainData, key: String) -> Dictionary:
	var feature: Dictionary = data.site.get("features", {}).get(key, {})
	var stock := storage(data, key)
	if not eligible(feature) or str(feature.get("stage", "")) != "complete" or stock.is_empty(): return {}
	return {"holder": stock.holder, "cargo": stock.cargo,
		"cell": data.cell_from_index(int(feature.entrance)), "capacity": capacity(feature),
		"team_id": 0, "feature_id": key, "faction": int(feature.get("owner_faction", -1)),
		"withdraw_only": not Runtime.feature_usable(feature, "intake")}

static func validate(state: Dictionary) -> Dictionary:
	var stockpiles: Variant = state.get("stockpiles", {})
	if not stockpiles is Dictionary: return Runtime.fail("CORRUPT_SAVE", "設施庫存欄位")
	for key: Variant in stockpiles:
		if not key is String or not state.features.has(key): return Runtime.fail("CORRUPT_SAVE", "設施庫存引用不存在")
		if not state.features[key] is Dictionary: return Runtime.fail("CORRUPT_SAVE", "設施庫存引用格式")
		var feature: Dictionary = state.features[key]
		var stock: Variant = stockpiles[key]
		if not eligible(feature) or str(feature.get("stage", "")) != "complete" or not stock is Dictionary or stock.size() != 3 \
			or not Runtime._building_integer(stock.get("version"), 1, 1) or not stock.get("cargo") is Dictionary \
			or not stock.get("holder") is Dictionary or stock.holder.size() != 4 \
			or not stock.holder.get("holder") is String or stock.holder.holder != identity(key) \
			or not Runtime._building_integer(stock.holder.get("version"), 0, 2147483647) \
			or not stock.holder.get("item_ids") is Array or not stock.holder.get("equipped") is Dictionary \
			or not stock.holder.equipped.is_empty():
			return Runtime.fail("CORRUPT_SAVE", "設施庫存版本／原持物位置")
		for item: Variant in stock.cargo:
			if not item is String or not Runtime.Env.ITEM_NAMES.has(item) or not Runtime._building_integer(stock.cargo[item], 0, 1000000):
				return Runtime.fail("CORRUPT_SAVE", "設施庫存資源數量")
		if Runtime.carried_size(stock.cargo, stock.holder) > capacity(feature):
			return Runtime.fail("CORRUPT_SAVE", "設施資源與實物合計超過容量")
	for key: Variant in state.features:
		if not state.features[key] is Dictionary: return Runtime.fail("CORRUPT_SAVE", "設施格式")
		var feature: Dictionary = state.features[key]
		if feature.has("supply_mode") and (feature.supply_mode != "local" or str(feature.kind) == "warehouse" \
			or not eligible(feature) or not stockpiles.has(key)):
			return Runtime.fail("CORRUPT_SAVE", "加工現場供料引用不合法")
	return Runtime.ok()

static func normalize(state: Dictionary) -> void:
	for stock: Dictionary in state.get("stockpiles", {}).values():
		stock.version = int(stock.version)
		stock.holder.version = int(stock.holder.version)
		for item: Variant in stock.cargo: stock.cargo[item] = int(stock.cargo[item])
