extends RefCounted
## Resident household pantries (平民行為 C1b, reports/civilian-site-behavior-plan.md §4.4; Q4 A: household food plus
## warehouse rations). Each household's food is the "house:<id>" food location of its residents team's supply ledger
## (version 3 locations, the same mechanism ships use), so meals, hunger and hunger damage keep their one authority
## (SiteSustain) on the grid and the native shared step alike. A member eats from his own house's location while he
## stands on his registered door rest cell; elsewhere he eats nothing from it (shore/vehicle rules unchanged).
## open_pantries converts the team's ledger once (an old abstract stock moves to the lowest house), later calls add the
## houses that appeared. stock_pantry moves real food from the Site camp stock (site.inventory) into a house.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Households = preload("res://scripts/terrain_lab/site_households.gd")
const Housing = preload("res://scripts/terrain_lab/site_housing.gd")

## Houses of the team's registered members, sorted by id.
static func team_houses(controller: Variant, team: Variant) -> Array:
	var houses := {}
	var state: Dictionary = controller.lab.terrain.site
	for index: int in _indices(team):
		var house_id := Households.house_of(state, team.combat_identity(index))
		if not house_id.is_empty(): houses[house_id] = true
	var result: Array = houses.keys()
	result.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	return result

static func _indices(team: Variant) -> Array:
	return team.combat_units.keys() if team.combat_units is Dictionary else range(team.combat_units.size())

## Bandit-free, plan-free first step of C1: the residents team's ledger gains one food location per household. Refuses
## while the team moves or delivers food; nothing changes on a refusal.
static func open_pantries(controller: Variant, team: Variant) -> Dictionary:
	var lab: Variant = controller.lab
	if team == null or not team.combat_enabled: return Runtime.fail("NO_TARGET", "居民隊不在此地")
	Households.reconcile(lab.terrain.site)
	var houses := team_houses(controller, team)
	if houses.is_empty(): return Runtime.fail("NO_HOUSEHOLD", "這支隊伍沒有登記住宅的居民")
	var entry: Dictionary = controller._supply_entry(team)
	if not entry.is_empty() and int(entry.get("version", 0)) == 3:
		var added := 0
		for house_id: String in houses:
			var key := Households.food_key(house_id)
			if entry.locations.has(key): continue
			entry.locations[key] = {"inventory": {}, "open_rations": 0.0}
			added += 1
		if added > 0:
			if not controller._supply_locations_valid(team, entry.locations): return Runtime.fail("INVALID_SUSTAIN", "戶糧存放點無效")
			entry["revision"] = int(entry.revision) + 1
		return Runtime.ok("已開 %d 戶戶糧" % added, {"added": added})
	if not controller._team_stopped(team): return Runtime.fail("BUSY", "居民隊須全隊停止並收束原動作")
	var supplied: Dictionary = controller.captivity_supply.enable_team(team, true)
	if not supplied.ok: return supplied
	var draft: Dictionary = supplied.entry
	if not draft.delivery.is_empty() or int(draft.revision) >= 2147483646: return Runtime.fail("BUSY", "先完成或取消原交糧")
	var state: Dictionary = draft.sustain.duplicate(true)
	var at := Runtime.now(lab.terrain) * 60.0
	if not controller._align_supply_clock(state, at) or not Runtime._resource_stack(draft.inventory): return Runtime.fail("INVALID_SUSTAIN", "原供養時段／口糧未同步")
	var locations := {}
	for house_id: String in houses: locations[Households.food_key(house_id)] = {"inventory": {}, "open_rations": 0.0}
	var first: Dictionary = locations[Households.food_key(houses[0])]
	first.inventory = draft.inventory.duplicate(true)
	first.open_rations = float(state.get("open_rations", 0.0))
	state["version"] = 2
	state.erase("open_rations")
	if not controller._supply_locations_valid(team, locations): return Runtime.fail("INVALID_SUSTAIN", "戶糧存放點無效")
	if entry.is_empty():
		var enabled: Dictionary = controller.captivity_supply.enable_team(team)
		if not enabled.ok: return enabled
		entry = enabled.entry
	entry.sustain.clear()
	entry.sustain.merge(state)
	entry.erase("inventory")
	entry["locations"] = locations
	entry["version"] = 3
	entry["revision"] = int(entry.revision) + 1
	return Runtime.ok("已開 %d 戶戶糧" % houses.size(), {"added": houses.size()})

## Moves `count` of a food item from the Site camp stock (site.inventory) into a house's pantry. Real items only.
static func stock_pantry(controller: Variant, team: Variant, house_id: String, item: String, count: int) -> Dictionary:
	var lab: Variant = controller.lab
	if item not in SiteSustain.FOODS or count <= 0: return Runtime.fail("INVALID", "只能存放食物")
	var entry: Dictionary = controller._supply_entry(team)
	var key := Households.food_key(house_id)
	if entry.is_empty() or int(entry.get("version", 0)) != 3 or not entry.locations.has(key): return Runtime.fail("NO_TARGET", "這一戶還沒有戶糧")
	if not entry.get("delivery", {}).is_empty(): return Runtime.fail("BUSY", "交糧進行中")
	var source: Dictionary = lab.terrain.site.get("inventory", {})
	if int(source.get(item, 0)) < count: return Runtime.fail("INSUFFICIENT", "營地存量不足")
	var pantry: Dictionary = entry.locations[key].inventory
	if int(pantry.get(item, 0)) + count > 1000000: return Runtime.fail("CAPACITY", "戶糧已滿")
	source[item] = int(source[item]) - count
	pantry[item] = int(pantry.get(item, 0)) + count
	entry["revision"] = int(entry.revision) + 1
	return Runtime.ok("已存入 %d %s" % [count, item], {"count": int(pantry[item])})

static func pantry(controller: Variant, team: Variant, house_id: String) -> Dictionary:
	var entry: Dictionary = controller._supply_entry(team)
	if entry.is_empty() or int(entry.get("version", 0)) != 3: return {}
	return entry.locations.get(Households.food_key(house_id), {})

# --- 居民吃飯 F1 (reports/scenario-village-livelihood-plan.md; the rations of civilian plan §4.4, Q4 A) -----------------
## Where a settlement's record says `meals` (the settlements of a new scenario world), its people are fed once a game day
## from its own stock, the camp's first, then its warehouses': every household's pantry is filled up to PANTRY_DAYS rations
## a member, and the stock of its teams without houses (the militia, a garrison) the same. Real food only; what is not
## there is not given, and hunger follows its one authority (SiteSustain).
const PANTRY_DAYS := 3
const FOOD_ORDER := ["grain", "wild_food", "fish", "meat"]

## Where a settlement feeds its people they take their ration along (a field is worked over two meals, and at a fast clock
## the way home is hours of it: asking for the doorstep starved whoever worked, found 2026-11-26). In a fight only who is
## home eats.
static func meals_anywhere(state: Dictionary) -> bool:
	return meals_on(state) and float(state.get("combat_left", 0.0)) <= 0.0

static func meals_on(state: Dictionary) -> bool:
	var settlement: Variant = state.get("settlement", {})
	return settlement is Dictionary and int(settlement.get("meals", 0)) == 1

## One day's rations. {moved, short, refused: [codes]}; a team that cannot open its ledger now (it is moving) is in `refused`.
static func ration_day(controller: Variant) -> Dictionary:
	var lab: Variant = controller.lab
	var result := {"moved": 0, "short": 0, "shared": 0, "refused": []}
	if lab == null or lab.terrain == null or not meals_on(lab.terrain.site): return result
	# A travelling party's own Lab views its origin Site's state (settlement included) on the party's people; the
	# settlement feeds only on its Site. Rationing there wrote a team ledger on the origin Site's clock into the party,
	# whose upkeep counts world time: a tax team its settlement fed was refused INVALID_SUSTAIN on its first road step.
	if lab.terrain.has_meta(&"region_party_owner"): return result
	var state: Dictionary = lab.terrain.site
	var owner := int(state.settlement.owner_faction)
	_choose_recipes(state, owner)
	for team: Variant in lab.team_owners():
		if team == null or not team.combat_enabled or int(team.faction_id) != owner: continue
		var living: Array[int] = []
		var homeless := 0
		for index: int in _indices(team):
			var identity: int = team.combat_identity(index)
			if not team.is_member(index) or float(team.combat_hot_get(index, &"hp", 0.0)) <= 0.0 or bool(team.combat_hot_get(index, &"captive", false)): continue
			living.append(identity)
			if Households.house_of(state, identity).is_empty(): homeless += 1
		if living.is_empty(): continue
		if homeless < living.size():
			# A resident without a house has no pantry to eat from: such a team is not put on household food at all.
			if homeless > 0:
				result.refused.append("HOMELESS")
				continue
			var opened := open_pantries(controller, team)
			if not opened.ok:
				result.refused.append(str(opened.get("code", "")))
				continue
			var entry: Dictionary = controller._supply_entry(team)
			var people := {}
			for identity: int in living:
				var house_id := Households.house_of(state, identity)
				people[house_id] = int(people.get(house_id, 0)) + 1
			var before := int(result.moved)
			var lived := team_houses(controller, team)
			# What a house nobody of the team lives in any more still holds goes back to the camp.
			for key: String in entry.locations.keys():
				if not key.begins_with("house:") or lived.has(key.trim_prefix("house:")): continue
				for food: String in entry.locations[key].inventory:
					state["inventory"][food] = int(state.get("inventory", {}).get(food, 0)) + int(entry.locations[key].inventory[food])
				entry.locations.erase(key)
				entry["revision"] = int(entry.revision) + 1
			var shared := int(result.shared)
			for house_id: String in lived:
				var location: Dictionary = entry.locations.get(Households.food_key(house_id), {})
				if location.is_empty(): continue
				# 產出三成歸戶: the house's own share of its harvest goes in first; the rations make up the rest.
				result.shared = int(result.shared) + flush_share(state, house_id, location.inventory, held_rations(location))
				_fill(state, owner, location.inventory, float(location.open_rations), int(people.get(house_id, 0)) * PANTRY_DAYS, result)
			if int(result.moved) != before or int(result.shared) != shared: entry["revision"] = int(entry.revision) + 1
			continue
		var fed: Dictionary = controller._supply_entry(team)
		if fed.is_empty():
			var enabled: Dictionary = controller.captivity_supply.enable_team(team)
			if not enabled.ok:
				result.refused.append(str(enabled.get("code", "")))
				continue
			fed = enabled.entry
		if int(fed.get("version", 0)) != 2 or not fed.get("delivery", {}).is_empty(): continue
		var had := int(result.moved)
		_fill(state, owner, fed.inventory, float(fed.sustain.get("open_rations", 0.0)), living.size() * PANTRY_DAYS, result)
		if int(result.moved) != had: fed["revision"] = int(fed.revision) + 1
	if drop_lost_shares(state): result.shared = int(result.shared) + 1
	if int(result.moved) > 0 or int(result.shared) > 0: lab.terrain.environment_revision += 1
	return result

static func held_rations(location: Dictionary) -> float:
	var held := float(location.get("open_rations", 0.0))
	for food: String in SiteSustain.FOODS: held += float(location.get("inventory", {}).get(food, 0))
	return held

# --- 產出三成歸戶 (civilian plan §4.4, Q4 A; reports/scenario-village-livelihood-plan.md V0.4) ----------------------------
## Where a settlement feeds its people a household keeps SHARE_PERCENT of the food its own main job yields; the rest goes
## on to the stock as before and pays the production tax. The share waits in the Site's `food_share` section
## {house: {carry: {food: hundredths}, pending: {food: n}}} (a batch is published inside a step, where the pantry ledger
## must not change) and goes into the house's pantry with the day's rations, up to SHARE_DAYS rations a member; what does
## not fit goes to the camp stock.
const SECTION := "food_share"
const SHARE_PERCENT := 30
const SHARE_DAYS := 30

## A batch of the feature `feature_key` that `identity` delivered: what goes on to the stock (and its tax).
static func share_batch(state: Dictionary, feature_key: String, identity: int, output: Dictionary) -> Dictionary:
	if identity <= 0 or output.is_empty() or feature_key.is_empty() or not meals_on(state): return output
	var house_id := Households.house_of(state, identity)
	if house_id.is_empty() or str(state.get("households", {}).get(house_id, {}).get("job", {}).get("feature", "")) != feature_key: return output
	return share_house(state, house_id, output)

## The household's part of a batch of its own main job (the hundredths carried, as the production tax counts).
static func share_house(state: Dictionary, house_id: String, output: Dictionary) -> Dictionary:
	if house_id.is_empty() or not meals_on(state): return output
	var foods: Array = []
	for item: String in output:
		if item in SiteSustain.FOODS and int(output[item]) > 0: foods.append(item)
	if foods.is_empty(): return output
	foods.sort()
	var table: Dictionary = state.get(SECTION, {})
	var share: Dictionary = (table.get(house_id, {"carry": {}, "pending": {}}) as Dictionary).duplicate(true)
	var kept := output.duplicate()
	for item: String in foods:
		var total := int(share.carry.get(item, 0)) + int(output[item]) * SHARE_PERCENT
		var units := mini(total / 100, int(output[item]))
		if total % 100 == 0: share.carry.erase(item)
		else: share.carry[item] = total % 100
		if units <= 0: continue
		share.pending[item] = int(share.pending.get(item, 0)) + units
		kept[item] = int(output[item]) - units
		if int(kept[item]) <= 0: kept.erase(item)
	if share.carry.is_empty() and share.pending.is_empty(): table.erase(house_id)
	else: table[house_id] = share
	if table.is_empty(): state.erase(SECTION)
	else: state[SECTION] = table
	return kept

## Moves the house's waiting share into its pantry `inventory`, which holds `held` rations, up to SHARE_DAYS rations a
## member; the rest goes to the camp stock. Returns what went into the pantry.
static func flush_share(state: Dictionary, house_id: String, inventory: Dictionary, held: float) -> int:
	var table: Variant = state.get(SECTION, {})
	if not table is Dictionary or not table.has(house_id) or table[house_id].pending.is_empty(): return 0
	var room := Households.members(state, house_id).size() * SHARE_DAYS - ceili(held)
	var moved := 0
	var pending: Dictionary = table[house_id].pending
	if not state.get("inventory") is Dictionary: state["inventory"] = {}
	for food: String in FOOD_ORDER:
		var n := int(pending.get(food, 0))
		if n <= 0: continue
		var into := clampi(room, 0, n)
		if into > 0: inventory[food] = int(inventory.get(food, 0)) + into
		if n > into: state.inventory[food] = int(state.inventory.get(food, 0)) + n - into
		room -= into
		moved += into
	pending.clear()
	if table[house_id].carry.is_empty(): table.erase(house_id)
	if table.is_empty(): state.erase(SECTION)
	return moved

## The waiting share of a house nobody lives in any more goes to the camp stock. Returns whether any did.
static func drop_lost_shares(state: Dictionary) -> bool:
	var table: Variant = state.get(SECTION, {})
	if not table is Dictionary or table.is_empty(): return false
	var lived := Households.membership(state)
	var dropped := false
	for house_id: String in table.keys():
		if lived.has(house_id) and not lived[house_id].is_empty(): continue
		if not table[house_id].pending.is_empty(): dropped = true
		flush_share(state, house_id, {}, 0.0) # no members: no room, all to the camp
		table.erase(house_id)
	if table.is_empty(): state.erase(SECTION)
	return dropped

static func validate_shares(state: Dictionary) -> Dictionary:
	if not state.has(SECTION): return Runtime.ok()
	var table: Variant = state[SECTION]
	if not table is Dictionary or table.is_empty() or table.size() > 4096: return Runtime.fail("CORRUPT_SAVE", "戶糧分成")
	for house_id: Variant in table:
		var entry: Variant = table[house_id]
		if not house_id is String or not str(house_id).is_valid_int() or not entry is Dictionary or entry.size() != 2 or not entry.get("carry") is Dictionary or not entry.get("pending") is Dictionary:
			return Runtime.fail("CORRUPT_SAVE", "戶糧分成")
		if entry.carry.is_empty() and entry.pending.is_empty(): return Runtime.fail("CORRUPT_SAVE", "戶糧分成")
		for part: String in ["carry", "pending"]:
			for item: Variant in entry[part]:
				var value: Variant = entry[part][item]
				var high := 99 if part == "carry" else 1000000
				if not item is String or item not in SiteSustain.FOODS or not (value is int or value is float) or float(value) != floorf(float(value)) or float(value) < 1.0 or float(value) > float(high):
					return Runtime.fail("CORRUPT_SAVE", "戶糧分成")
	return Runtime.ok()

static func normalize_shares(state: Dictionary) -> void:
	var table: Variant = state.get(SECTION, {})
	if not table is Dictionary: return
	for entry: Variant in table.values():
		if not entry is Dictionary: continue
		for part: String in ["carry", "pending"]:
			if not entry.get(part) is Dictionary: continue
			for item: Variant in entry[part]:
				if entry[part][item] is float: entry[part][item] = int(entry[part][item])

## The settlement's fields keep seed while little is left (the 留種 recipe, 1 seed -> 6 grain and 2 seeds) and grow plain
## grain (1 -> 8) when there is plenty; a batch already begun is finished first.
const SEEDS_LOW := 20
const SEEDS_PLENTY := 60
static func _choose_recipes(state: Dictionary, owner: int) -> void:
	var seeds := int(state.get("inventory", {}).get("seeds", 0))
	if seeds >= SEEDS_LOW and seeds < SEEDS_PLENTY: return
	for key: Variant in state.get("features", {}):
		var farm: Dictionary = state.features[key]
		if str(farm.get("kind", "")) != "farm" or str(farm.get("stage", "")) != "complete" or int(farm.get("owner_faction", -1)) != owner: continue
		if int(farm.get("layout_version", 0)) != Runtime.BUILDING_LAYOUT_VERSION or bool(farm.get("batch_paid", false)) or float(farm.get("production", 0.0)) > 0.0 or farm.has("pending_build"): continue
		if seeds < SEEDS_LOW: farm["recipe_id"] = "retain_seed"
		else: farm.erase("recipe_id")

## Moves food from the settlement's stock into `pantry` until it holds `want` rations (an opened one counts).
static func _fill(state: Dictionary, owner: int, pantry: Dictionary, open_rations: float, want: int, result: Dictionary) -> void:
	var need := ceili(float(want) - open_rations)
	for food: String in SiteSustain.FOODS: need -= int(pantry.get(food, 0))
	if need <= 0: return
	var holders: Array = [state.get("inventory", {})]
	var keys: Array[String] = _warehouses(state, owner)
	for key: String in keys: holders.append(state.stockpiles[key].cargo)
	for food: String in FOOD_ORDER:
		for at: int in holders.size():
			if need <= 0: return
			var holder: Dictionary = holders[at]
			var n := mini(need, int(holder.get(food, 0)))
			if n <= 0: continue
			holder[food] = int(holder[food]) - n
			if int(holder[food]) <= 0: holder.erase(food)
			pantry[food] = int(pantry.get(food, 0)) + n
			if at > 0: state.stockpiles[keys[at - 1]].holder["version"] = int(state.stockpiles[keys[at - 1]].holder.version) + 1
			need -= n
			result.moved = int(result.moved) + n
	if need > 0: result.short = int(result.short) + need

## The owner's complete warehouses with a stockpile, sorted (as SiteBanditAftermath.warehouses).
static func _warehouses(state: Dictionary, owner: int) -> Array[String]:
	var keys: Array[String] = []
	for key: Variant in state.get("stockpiles", {}):
		var feature: Variant = state.get("features", {}).get(key, {})
		if feature is Dictionary and str(feature.get("kind", "")) == "warehouse" and str(feature.get("stage", "")) == "complete" and int(feature.get("owner_faction", -1)) == owner: keys.append(str(key))
	keys.sort()
	return keys

## The food location a member eats from in his own house: his registered house's key while he stands on its door rest
## cell, else "" (ship_food_locations then tries the shore rules).
static func member_house_key(controller: Variant, identity: int, cell: Vector2i, locations: Dictionary) -> String:
	var registered: Dictionary = Housing.relation(controller.lab, identity)
	if registered.is_empty(): return ""
	var key := Households.food_key(str(registered.house_id))
	if not locations.has(key): return ""
	if controller.lab.terrain.index(cell) != int(registered.cell) and not meals_anywhere(controller.lab.terrain.site): return ""
	return key
