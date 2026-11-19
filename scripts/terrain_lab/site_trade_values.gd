extends RefCounted
## Versioned valuation data only. Original Runtime owns recipes and item definitions.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const VERSION := 1
const RULE_VERSION := 1
const FOODS := ["grain", "wild_food", "fish", "meat"]
const FIXED := {"grain": 1.0, "wild_food": 1.0, "fish": 1.0, "meat": 1.0,
	"wood": 0.5, "stone": 0.5, "clay": 0.5, "brine": 0.5, "hide": 1.5,
	"iron_ore": 2.0, "herb": 2.0, "seeds": 2.0, "sheep": 25.0, "horse": 100.0}
const DERIVED_ORDER := ["fiber", "fodder", "wool", "salt", "charcoal", "brick", "pottery",
	"iron", "steel", "tools", "leather", "cloth", "rope", "arrow", "bolt", "siege_bolt",
	"siege_stone", "fire_arrow", "camp_tent", "fire_pot", "ballista_spares"]
const RESOURCE_VALUES := {"grain": 1.0, "wild_food": 1.0, "fish": 1.0, "meat": 1.0,
	"wood": 0.5, "stone": 0.5, "clay": 0.5, "brine": 0.5, "hide": 1.5,
	"iron_ore": 2.0, "herb": 2.0, "seeds": 2.0, "sheep": 25.0, "horse": 100.0,
	"fiber": 0.5, "fodder": 0.5, "wool": 0.5, "salt": 1.0, "charcoal": 1.5,
	"brick": 1.0, "pottery": 1.0, "iron": 5.5, "steel": 17.5, "tools": 12.0,
	"leather": 2.0, "cloth": 1.0, "rope": 0.5, "arrow": 1.0, "bolt": 1.0,
	"siege_bolt": 8.0, "siege_stone": 1.5, "fire_arrow": 2.0, "camp_tent": 7.5,
	"fire_pot": 4.5, "ballista_spares": 9.5}
const EQUIPMENT_VALUES := {"weapon:bow_01": 4.0, "weapon:crossbow_01": 17.0,
	"armor:armor_iron_01": 36.5, "armor:armor_light_leather_01": 11.5}
const SLOT_VALUES := {"weapon": 8.0, "shield": 5.0, "helmet": 6.0, "armor": 15.0,
	"outfit": 3.0, "cape": 3.0, "boots": 3.0}

static func half_grid(value: float) -> float:
	return maxf(0.5, floorf(value * 2.0 + 0.5) / 2.0)

static func _recipes() -> Array[Dictionary]:
	var recipes: Array[Dictionary] = []
	for feature: Dictionary in Runtime.FEATURES.values():
		if feature.has("input") and feature.has("output"): recipes.append(feature)
	for options: Dictionary in Runtime.FEATURE_RECIPES.values():
		for recipe: Dictionary in options.values(): recipes.append(recipe)
	for recipe: Dictionary in Runtime.RANGED_RECIPES.values(): recipes.append(recipe)
	return recipes

static func _cost_value(recipe: Dictionary, values: Dictionary) -> float:
	var total: float = 0.0
	var inputs: Dictionary = recipe.get("input", recipe.get("cost", {}))
	for resource: String in inputs:
		if not values.has(resource): return -1.0
		total += float(values[resource]) * int(inputs[resource])
	return total

static func derive_resources() -> Dictionary:
	var values: Dictionary = FIXED.duplicate()
	var recipes: Array[Dictionary] = _recipes()
	for resource: String in DERIVED_ORDER:
		var minimum: float = INF
		for recipe: Dictionary in recipes:
			var output: Dictionary = recipe.get("output", {})
			if int(output.get(resource, 0)) <= 0: continue
			var cost: float = _cost_value(recipe, values)
			if cost < 0.0: return {}
			minimum = minf(minimum, cost / int(output[resource]))
		if not is_finite(minimum): return {}
		values[resource] = half_grid(minimum * 1.25)
	return values

static func derive_equipment() -> Dictionary:
	var values: Dictionary = derive_resources()
	if values.is_empty(): return {}
	var raw: Dictionary = {}
	for recipe: Dictionary in _recipes():
		var products: Array = recipe.get("output_items", []).duplicate()
		if recipe.has("asset"): products.append("weapon:" + str(recipe.asset))
		if products.is_empty(): continue
		var cost: float = _cost_value(recipe, values)
		if cost < 0.0: return {}
		for definition: String in products:
			raw[definition] = minf(float(raw.get(definition, INF)), cost / products.size())
	for definition: String in raw: raw[definition] = half_grid(float(raw[definition]) * 1.25)
	return raw

static func validate_table() -> Dictionary:
	var resources: Array = Runtime.Env.ITEM_NAMES.keys()
	resources.erase("coin")
	if RESOURCE_VALUES.size() != resources.size() or RESOURCE_VALUES.has("coin"): return Runtime.fail("TRADE_VALUES_VERSION")
	for resource: String in resources:
		if not RESOURCE_VALUES.has(resource) or not is_finite(float(RESOURCE_VALUES[resource])) or float(RESOURCE_VALUES[resource]) <= 0.0: return Runtime.fail("TRADE_VALUES_VERSION")
	if derive_resources() != RESOURCE_VALUES or derive_equipment() != EQUIPMENT_VALUES: return Runtime.fail("TRADE_VALUES_RECIPE_MISMATCH")
	return Runtime.ok()

## Nekki 2026-11-19 「好」: a coin is worth one grain when a trade pays in coin. Coin stays out of RESOURCE_VALUES and
## resource_value (the derived goods table, TR-78); only SiteTrade's valuation reads COIN_VALUE.
const COIN_VALUE := 1.0

static func resource_value(resource: String) -> float:
	return float(RESOURCE_VALUES.get(resource, -1.0)) if Runtime.Env.ITEM_NAMES.has(resource) else -1.0

static func item_value(state: Dictionary, identity: String) -> float:
	if not state.get("item_records", {}) is Dictionary or not state.get("item_definitions", {}) is Dictionary: return -1.0
	var record: Variant = state.get("item_records", {}).get(identity)
	if not record is Dictionary: return -1.0
	var definition_id: Variant = record.get("definition")
	if not definition_id is String: return -1.0
	var definition: Variant = state.get("item_definitions", {}).get(definition_id)
	if not Runtime.valid_item_definition(definition_id, definition): return -1.0
	var recipe_id: String = str(definition.slot) + ":" + str(definition.asset)
	return float(EQUIPMENT_VALUES.get(recipe_id, SLOT_VALUES.get(str(definition.slot), -1.0)))
