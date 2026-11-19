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

## The food location a member eats from in his own house: his registered house's key while he stands on its door rest
## cell, else "" (ship_food_locations then tries the shore rules).
static func member_house_key(controller: Variant, identity: int, cell: Vector2i, locations: Dictionary) -> String:
	var registered: Dictionary = Housing.relation(controller.lab, identity)
	if registered.is_empty(): return ""
	var key := Households.food_key(str(registered.house_id))
	if not locations.has(key) or controller.lab.terrain.index(cell) != int(registered.cell): return ""
	return key
