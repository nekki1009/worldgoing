extends RefCounted
## Households (平民行為 C0, reports/civilian-site-behavior-plan.md §4.1; Q1 A: one resident team per settlement, the
## household is a grouping inside it). A household is the set of residents registered to one house in `site.housing`.
## `site.households[house_id] = {version, head, stock, job}`:
## - members are never stored: they are derived from `site.housing` (one authority);
## - head: the household head's person id (the lowest id at first, kept while he stays a member), or -1 for a house that
##   only keeps leftover stock;
## - stock: the household's own goods {item: positive count} (real items; later stages move them in and out);
## - job: {feature, since_day}: the household's main work place ("" = none) and the Site day it was set.
## An old save without the table gets it on load (normalize); houses gain and lose entries as people register and leave.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const VERSION := 1
const FIELDS := ["version", "head", "stock", "job"]
const STOCK_MAX := 1000000

static func _integer(value: Variant, lower: int, upper: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= lower and float(value) <= upper and float(value) == floorf(float(value))

## House id -> sorted member ids, from the housing registrations.
static func membership(state: Dictionary) -> Dictionary:
	var result := {}
	var housing: Variant = state.get("housing", {})
	if not housing is Dictionary: return result
	for identity: Variant in housing:
		var registered: Variant = housing[identity]
		if not registered is Dictionary: continue
		var house_id := str(registered.get("house_id", ""))
		if not result.has(house_id): result[house_id] = []
		result[house_id].append(int(str(identity)))
	for house_id: String in result: result[house_id].sort()
	return result

static func members(state: Dictionary, house_id: String) -> Array:
	return membership(state).get(house_id, [])

static func _empty(head: int, day: int) -> Dictionary:
	return {"version": VERSION, "head": head, "stock": {}, "job": {"feature": "", "since_day": day}}

static func _day(state: Dictionary) -> int:
	return int(floorf(float(state.get("minute", 0)) / 1440.0))

## Brings the table in line with the housing registrations. Returns true when anything changed. A household whose head
## left passes to its lowest-id member; a house without members keeps its entry only while it still holds stock.
static func reconcile(state: Dictionary) -> bool:
	var changed := false
	if not state.get("households") is Dictionary:
		state["households"] = {}
		changed = true
	var table: Dictionary = state.households
	var houses := membership(state)
	for house_id: String in houses:
		var people: Array = houses[house_id]
		if not table.has(house_id):
			table[house_id] = _empty(int(people[0]), _day(state))
			changed = true
		elif not people.has(int(table[house_id].head)):
			table[house_id]["head"] = int(people[0])
			changed = true
	for house_id: Variant in table.keys():
		if houses.has(house_id): continue
		if table[house_id].stock.is_empty():
			table.erase(house_id)
			changed = true
		elif int(table[house_id].head) != -1:
			table[house_id]["head"] = -1
			changed = true
	return changed

## JSON numbers load as floats; an old save gets its households here.
static func normalize(state: Dictionary) -> void:
	if state.get("households") is Dictionary:
		for entry: Variant in state.households.values():
			if not entry is Dictionary: continue
			for field: String in ["version", "head"]:
				if entry.get(field) is float: entry[field] = int(entry[field])
			if entry.get("stock") is Dictionary:
				for item: Variant in entry.stock:
					if entry.stock[item] is float: entry.stock[item] = int(entry.stock[item])
			if entry.get("job") is Dictionary and entry.job.get("since_day") is float: entry.job.since_day = int(entry.job.since_day)
	reconcile(state)

## Structural rules. A state without the table is valid (an old save, or a source captured before its first load). A
## house whose registrations changed through an owner that has not reconciled yet may lack an entry or keep a head who
## left; both are repaired by the next reconcile, so only impossible values are refused here.
static func validate(state: Dictionary) -> Dictionary:
	if not state.has("households"): return Runtime.ok()
	var table: Variant = state.get("households", {})
	if not table is Dictionary: return Runtime.fail("CORRUPT_SAVE", "戶表")
	var houses := membership(state)
	for house_id: Variant in table:
		var entry: Variant = table[house_id]
		if not house_id is String or not entry is Dictionary or entry.size() != FIELDS.size(): return Runtime.fail("CORRUPT_SAVE", "戶欄位")
		for field: String in FIELDS:
			if not entry.has(field): return Runtime.fail("CORRUPT_SAVE", "戶欄位")
		if not _integer(entry.version, VERSION, VERSION): return Runtime.fail("CORRUPT_SAVE", "戶版本")
		if not entry.stock is Dictionary or not entry.job is Dictionary or entry.job.size() != 2 or not entry.job.get("feature") is String or not _integer(entry.job.get("since_day"), 0, 2147483647): return Runtime.fail("CORRUPT_SAVE", "戶糧或主業")
		for item: Variant in entry.stock:
			if not item is String or str(item).is_empty() or not _integer(entry.stock[item], 1, STOCK_MAX): return Runtime.fail("CORRUPT_SAVE", "戶糧數量")
		var feature_id := str(entry.job.feature)
		if not feature_id.is_empty() and not state.get("features", {}).has(feature_id): return Runtime.fail("CORRUPT_SAVE", "戶主業須引用現存建物")
		if not _integer(entry.head, -1, 2147483647) or int(entry.head) == 0: return Runtime.fail("CORRUPT_SAVE", "戶長")
	return Runtime.ok()

## Is the table exactly in line with the registrations (every registered house has an entry headed by a member, an
## empty house only keeps stock)? Tests and owners that just reconciled use it.
static func in_sync(state: Dictionary) -> bool:
	var table: Variant = state.get("households")
	if not table is Dictionary: return false
	var houses := membership(state)
	for house_id: String in houses:
		if not table.has(house_id) or not houses[house_id].has(int(table[house_id].head)): return false
	for house_id: Variant in table:
		if not houses.has(house_id) and (int(table[house_id].head) != -1 or table[house_id].stock.is_empty()): return false
	return true

static func household(state: Dictionary, house_id: String) -> Dictionary:
	var table: Variant = state.get("households", {})
	return table.get(house_id, {}) if table is Dictionary else {}

## The house id of the household a person belongs to, or "".
static func house_of(state: Dictionary, identity: int) -> String:
	return str(state.get("housing", {}).get(str(identity), {}).get("house_id", ""))

## §4.1 "戶長可改": the new head must be a member of the household.
static func set_head(state: Dictionary, house_id: String, identity: int) -> Dictionary:
	var entry: Dictionary = household(state, house_id)
	if entry.is_empty(): return Runtime.fail("NO_TARGET", "沒有這一戶")
	if not members(state, house_id).has(identity): return Runtime.fail("NOT_MEMBER", "戶長須是本戶登記居民")
	if int(entry.head) == identity: return Runtime.ok("", {"changed": false})
	entry["head"] = identity
	return Runtime.ok("已更換戶長", {"changed": true})

## The household's main work place ("" clears it); the caller (C2 派工) checks the place is workable.
static func set_job(state: Dictionary, house_id: String, feature_id: String) -> Dictionary:
	var entry: Dictionary = household(state, house_id)
	if entry.is_empty(): return Runtime.fail("NO_TARGET", "沒有這一戶")
	if not feature_id.is_empty() and not state.get("features", {}).has(feature_id): return Runtime.fail("NO_TARGET", "主業須是現存建物")
	if str(entry.job.feature) == feature_id: return Runtime.ok("", {"changed": false})
	entry["job"] = {"feature": feature_id, "since_day": _day(state)}
	return Runtime.ok("", {"changed": true})

## Adds (`delta` > 0) or takes (`delta` < 0) household goods; never below zero, never created from nothing by callers
## that do not hold the matching source (C1 moves real stock).
static func change_stock(state: Dictionary, house_id: String, item: String, delta: int) -> Dictionary:
	var entry: Dictionary = household(state, house_id)
	if entry.is_empty() or item.is_empty(): return Runtime.fail("NO_TARGET", "沒有這一戶")
	var next := int(entry.stock.get(item, 0)) + delta
	if next < 0: return Runtime.fail("INSUFFICIENT", "戶糧不足")
	if next > STOCK_MAX: return Runtime.fail("CAPACITY", "戶糧已滿")
	if next == 0: entry.stock.erase(item)
	else: entry.stock[item] = next
	return Runtime.ok("", {"count": next})
