extends SceneTree
## 產出三成歸戶 (reports/scenario-village-livelihood-plan.md V0.4; civilian plan §4.4, Nekki 2026-11-15 Q4 A): a household
## working its own main job keeps 30% of the food of each batch, the hundredths carried; the share waits in the Site's
## `food_share` section and goes into the house's pantry with the day's rations, up to 30 days a member; what does not
## fit goes to the camp. Data only.
const ResidentLife = preload("res://scripts/terrain_lab/site_resident_life.gd")

var checks := 0

func _initialize() -> void:
	_run()

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	if condition:
		checks += 1
		return true
	push_error("SITE_FOOD_SHARE_FAIL: %s %s" % [message, JSON.stringify(detail) if detail != null else ""])
	quit(1)
	return false

func _state() -> Dictionary:
	return {"settlement": {"meals": 1, "owner_faction": 1}, "inventory": {},
		"housing": {"11": {"house_id": "1"}, "12": {"house_id": "1"}, "21": {"house_id": "2"}},
		"households": {"1": {"version": 1, "head": 11, "job": {"feature": "farm_a", "since_day": 0}},
			"2": {"version": 1, "head": 21, "job": {"feature": "", "since_day": 0}}},
		"team_supply": {"5": {"version": 3, "revision": 1, "locations": {"house:1": {"inventory": {}, "open_rations": 0.0}, "house:2": {"inventory": {}, "open_rations": 0.0}}}}}

func _sum(output: Dictionary, item: String) -> int:
	return int(output.get(item, 0))

func _run() -> void:
	var state := _state()
	# Ten batches of 8 grain by a member of the house whose job the field is: 24 to the house, 56 on.
	var on := 0
	for batch: int in range(10):
		on += _sum(ResidentLife.share_batch(state, "farm_a", 11, {"grain": 8}), "grain")
	if not _ok(on == 56 and int(state.food_share["1"].pending.grain) == 24 and not state.food_share["1"].carry.has("grain"), "ten batches of 8: 24 to the house, 56 on", [on, state.get("food_share")]): return
	# One batch more leaves hundredths behind.
	var one: Dictionary = ResidentLife.share_batch(state, "farm_a", 12, {"grain": 8, "seeds": 2})
	if not _ok(_sum(one, "grain") == 6 and _sum(one, "seeds") == 2 and int(state.food_share["1"].pending.grain) == 26 and int(state.food_share["1"].carry.grain) == 40, "8 grain: 2 to the house, 40 hundredths kept; seeds untouched", [one, state.food_share]): return
	# Not shared: someone without a house, another feature, nothing to eat, a settlement that does not feed its people.
	var before: Dictionary = state.food_share.duplicate(true)
	if not _ok(_sum(ResidentLife.share_batch(state, "farm_a", 99, {"grain": 8}), "grain") == 8, "a stranger's batch is not shared"): return
	if not _ok(_sum(ResidentLife.share_batch(state, "farm_b", 11, {"grain": 8}), "grain") == 8, "another feature's batch is not shared"): return
	if not _ok(_sum(ResidentLife.share_batch(state, "farm_a", 11, {"tools": 3}), "tools") == 3, "no food, no share"): return
	if not _ok(_sum(ResidentLife.share_batch(state, "farm_a", 0, {"grain": 8}), "grain") == 8, "the camp worker's batch is not shared"): return
	var plain := _state()
	plain.settlement.erase("meals")
	if not _ok(_sum(ResidentLife.share_batch(plain, "farm_a", 11, {"grain": 8}), "grain") == 8 and not plain.has("food_share"), "without meals nothing is shared"): return
	if not _ok(state.food_share == before, "refused batches leave the record as it was", state.food_share): return
	# The record saves.
	if not _ok(ResidentLife.validate_shares(state).ok, "the record is valid", ResidentLife.validate_shares(state)): return
	var floats: Dictionary = JSON.parse_string(JSON.stringify(state))
	ResidentLife.normalize_shares(floats)
	if not _ok(floats.food_share["1"].pending.grain is int and ResidentLife.validate_shares(floats).ok, "it loads back with whole numbers"): return
	for wrong: Variant in [{}, {"1": {"carry": {}, "pending": {}}}, {"1": {"carry": {"grain": 100}, "pending": {}}}, {"1": {"carry": {}, "pending": {"seeds": 1}}},
			{"x": {"carry": {}, "pending": {"grain": 1}}}, {"1": {"carry": {}, "pending": {"grain": 0}}}, {"1": {"pending": {"grain": 1}}}]:
		var bad := state.duplicate(true)
		bad["food_share"] = wrong
		if not _ok(not ResidentLife.validate_shares(bad).ok, "refused: %s" % JSON.stringify(wrong)): return
	# Into the pantry: room for 2 members x 30 days.
	var pantry: Dictionary = state.team_supply["5"].locations["house:1"].inventory
	var moved := ResidentLife.flush_share(state, "1", pantry, 0.0)
	if not _ok(moved == 26 and int(pantry.grain) == 26 and int(state.food_share["1"].carry.grain) == 40 and state.food_share["1"].pending.is_empty(), "26 go into the pantry, the hundredths stay", [moved, pantry, state.food_share]): return
	# A full pantry: what does not fit goes to the camp.
	for batch: int in range(20): ResidentLife.share_batch(state, "farm_a", 11, {"grain": 10})
	var waiting := int(state.food_share["1"].pending.grain)
	moved = ResidentLife.flush_share(state, "1", pantry, 50.0)
	if not _ok(waiting == 60 and moved == 10 and int(pantry.grain) == 36 and int(state.inventory.grain) == 50, "with 50 held only 10 more fit; 50 go to the camp", [waiting, moved, pantry, state.inventory]): return
	# A house nobody lives in any more: its waiting share goes to the camp.
	ResidentLife.share_batch(state, "farm_a", 11, {"grain": 10})
	state.housing.erase("11")
	state.housing.erase("12")
	if not _ok(ResidentLife.drop_lost_shares(state) and int(state.inventory.grain) == 53 and not state.has("food_share"), "the share of an empty house goes to the camp", [state.inventory, state.get("food_share")]): return
	print("SITE_FOOD_SHARE_PASS: ", checks, " checks")
	quit(0)
