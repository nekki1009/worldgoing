extends RefCounted
## P4 S5 (author data part): the static civilian resident roster rows an author places in a
## draft's initial state (plan 11.2, 11.3). A row holds display data only: no person id, no body,
## no military field. Person ids come from the original allocator and bodies from a runtime
## consumer that does not exist yet (S5_DESIGN.md). This file never creates a person.

const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")

## Key of the roster list inside a Site state (the draft initial state).
const STATE_KEY := "residents"
const ROW_KEYS := ["faction_id", "house", "name"]
const NAME_MAX := 32
const HOUSE_MAX := 64
const FACTION_MAX := 100000000
## Same cap as one TerrainArmy roster (terrain_army.gd MAX_ROSTER_SIZE = 200).
const ROSTER_MAX := 200

static func _integer(value: Variant, lower: int, upper: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= lower and float(value) <= upper and float(value) == floorf(float(value))

## One row: exactly name, faction_id and house. JSON numbers arrive as floats, so whole floats pass.
static func valid_row(value: Variant) -> bool:
	if not value is Dictionary or value.size() != ROW_KEYS.size(): return false
	for key: String in ROW_KEYS:
		if not value.has(key): return false
	var display_name: Variant = value.get("name")
	if not display_name is String or display_name.strip_edges().is_empty() or display_name.length() > NAME_MAX: return false
	if not _integer(value.get("faction_id"), 0, FACTION_MAX): return false
	var house: Variant = value.get("house")
	if not house is String or house.is_empty() or house.length() > HOUSE_MAX: return false
	return true

## The complete roster list. Zero rows is valid (an author may clear the roster).
static func valid_rows(value: Variant) -> bool:
	if not value is Array or value.size() > ROSTER_MAX: return false
	for row: Variant in value:
		if not valid_row(row): return false
	return true

## A state with no roster key is valid; a present key must hold valid rows.
static func valid_state(state: Variant) -> bool:
	if not state is Dictionary: return false
	if not state.has(STATE_KEY): return true
	return valid_rows(state.get(STATE_KEY))

## Pure: the candidate state with `rows` as the complete new roster. Never writes the input.
## The caller commits the candidate through the draft path, as the family panel does.
static func roster_candidate(state: Dictionary, rows: Variant) -> Dictionary:
	if not valid_rows(rows): return Runtime.fail("INVALID_RESIDENT_ROSTER", "居民名冊格式或人數不合法；未改變")
	var candidate_state: Dictionary = state.duplicate(true)
	candidate_state[STATE_KEY] = rows.duplicate(true)
	return Runtime.ok("居民名冊候選已備妥", {"state": candidate_state})

## Pure precheck for the S5b consumer (D-P5b-2): the whole roster or nothing. Creates no person
## and changes nothing. `capacity` maps a house feature key to its bed count; the caller computes
## it from Runtime.house_layout, so this file never reads terrain data. Refuses the first bad row,
## a settlement that cannot hold residents, and any house over its capacity.
static func plan(state: Dictionary, rows: Variant, capacity: Dictionary) -> Dictionary:
	if not valid_rows(rows): return Runtime.fail("INVALID_RESIDENT_ROSTER", "居民名冊格式或人數不合法；未改變")
	var settlement: Variant = state.get("settlement", {})
	if not settlement is Dictionary or int(settlement.get("level", 0)) <= 0 or not _integer(settlement.get("owner_faction"), 0, FACTION_MAX):
		return Runtime.fail("NO_SETTLEMENT", "聚落須已設立且有管理方；未改變")
	var owner: int = int(settlement.get("owner_faction"))
	var features: Variant = state.get("features", {})
	if not features is Dictionary: return Runtime.fail("NO_SETTLEMENT", "聚落建築資料不存在；未改變")
	var needed: Dictionary = {}
	for row: Variant in rows:
		var row_data: Dictionary = row
		if int(row_data.get("faction_id")) != owner: return Runtime.fail("RESIDENT_FACTION", "居民陣營須與聚落管理方相同；未改變")
		var house_id: String = str(row_data.get("house"))
		var feature: Variant = features.get(house_id, {})
		if not feature is Dictionary or str(feature.get("kind", "")) != "house" or str(feature.get("stage", "")) != "complete" or int(feature.get("owner_faction", -1)) != owner:
			return Runtime.fail("RESIDENT_HOUSE", "居民須分配到同一管理方的完工住宅；未改變")
		needed[house_id] = int(needed.get(house_id, 0)) + 1
	for house_id: String in needed:
		var room: int = int(capacity.get(house_id, 0))
		if int(needed[house_id]) > room:
			return Runtime.fail("NO_BEDS", "住宅「%s」床位不足：需要 %d、只有 %d；未改變" % [house_id, int(needed[house_id]), room])
	return Runtime.ok("居民名冊可分配", {"counts": needed, "total": rows.size()})

## P4 S5c: the draft-side check (editor and load). A state with no roster or an empty roster is
## valid. Otherwise every row must fit the settlement and its houses, using the bed counts of the
## candidate terrain (`data.site` is the state). Creates nothing.
static func draft_refusal(data: TerrainData, state: Dictionary) -> Dictionary:
	if not valid_state(state): return Runtime.fail("INVALID_RESIDENT_ROSTER", "居民名冊格式或人數不合法；未改變")
	var rows: Variant = state.get(STATE_KEY, [])
	if not rows is Array or rows.is_empty(): return Runtime.ok("無居民名冊")
	return plan(state, rows, capacity_for(data, rows))

## Bed count per house key for the rows (house_layout capacity; 0 when the house has no known layout).
static func capacity_for(data: TerrainData, rows: Array) -> Dictionary:
	var capacity: Dictionary = {}
	for row: Dictionary in rows:
		var key: String = str(row.get("house", ""))
		if capacity.has(key): continue
		var layout: Dictionary = Runtime.house_layout(data, key)
		if layout.ok: capacity[key] = int(layout.capacity)
		else: capacity[key] = 0
	return capacity
