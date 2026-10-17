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
