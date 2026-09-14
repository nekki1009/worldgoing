extends SceneTree

class Fixture extends RefCounted:
	var terrain := TerrainData.new()
	var character := TerrainTestCharacter.new()
	var npc := TerrainTestNPC.new()
	var actions := SitePersonActions.new()
	var equipment := SiteEquipmentOrders.new()
	var controlled_id := 1
	var threatened := false
	var changed: Array[int] = []
	func _init() -> void:
		terrain.allocate(Vector2i(12, 12))
		terrain.flags.fill(TerrainData.Flag.WALKABLE)
		terrain.site = {"id": "ranged-craft-test", "minute": 0, "phase": 0.0, "paused": false, "combat_left": 0.0,
			"depot_cell": terrain.index(Vector2i(5, 4)), "capacity": 800,
			"inventory": {"wood": 40, "iron": 20, "fiber": 10, "tools": 1},
			"manual": {"target": "", "cargo": {}}, "worker": {"target": "", "cargo": {}}}
		assert(SiteRuntime.initialize_item_storage(terrain.site).ok)
		character.person_id = 1
		npc.person_id = 2
		character.data = terrain
		npc.data = terrain
		character.terrain_cell = Vector2i(4, 4)
		npc.terrain_cell = Vector2i(5, 5)
		character.item_state = SiteRuntime.new_item_state("person:1")
		npc.item_state = SiteRuntime.new_item_state("person:2")
		character.ammo_inventory = terrain.site.manual.cargo
		npc.ammo_inventory = terrain.site.worker.cargo
		actions.init(self)
		actions.equipment_changed = func(identity: int) -> void: changed.append(identity)
		equipment.init(self, actions)
		equipment.equipment_apply_guard = func(identity: int, planned: Dictionary) -> Dictionary:
			# This headless fixture admits only its actually crafted bow recipe;
			# render/atlas publication is tested separately, never bypassed in production.
			if planned.size() != 1 or not planned.has("weapon"):
				return SiteRuntime.fail("UNSUPPORTED")
			var person := actions._person(identity)
			var holder: Dictionary = person.holder.duplicate(true)
			holder.equipped = planned.duplicate()
			var appearance := SiteRuntime.equipment_appearance(terrain, holder, HumanCharacter3DEditor.default_appearance())
			return SiteRuntime.ok() if not appearance.is_empty() and appearance.parts.weapon == "bow_01" else SiteRuntime.fail("UNSUPPORTED")
	func controlled_person_id() -> int:
		return controlled_id
	func _combat_target(identity: int) -> Dictionary:
		for actor: TerrainTestCharacter in [character, npc]:
			if actor.person_id == identity:
				return {"owner": actor, "unit": -1, "cell": actor.terrain_cell, "hp": actor.hp}
		return {}
	func _fatigue_threat(_cell: Vector2i, _faction: int, _owner: Variant, _unit: int, _candidates: Dictionary) -> bool:
		return threatened
	func close() -> void:
		actions.cancel(1)
		actions.cancel(2)
		actions.lab = null
		actions.equipment_changed = Callable()
		actions.equipment_orders = null
		equipment.lab = null
		equipment.actions = null
		equipment.equipment_apply_guard = Callable()
		character.free()
		npc.free()

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	_check_products_and_collection()
	_check_controlled_npc_equipment()
	_check_interruptions()
	_check_revalidation_and_work()
	print("SITE_RANGED_CRAFTING_PASS: four paid recipes, actual depot collection -> original five-second personal equipment -> real-ammo ranged shot, controlled-NPC personal authority, pause/contact/site/holder cancellation, materials/tools/capacity/definition recheck, fatigue and simultaneous completion conservation")
	quit(0)

func _check_products_and_collection() -> void:
	var fixture := Fixture.new()
	var actions := fixture.actions
	var stock: Dictionary = fixture.terrain.site.inventory
	var depot: Dictionary = fixture.terrain.site.depot_items
	var cargo: Dictionary = fixture.terrain.site.manual.cargo
	var original_stock := stock.duplicate()
	for recipe: String in SiteRuntime.RANGED_RECIPES:
		var before := var_to_bytes(fixture.terrain.site)
		assert(SiteRuntime.ranged_craft(fixture.terrain, recipe, 1, true).ok)
		assert(var_to_bytes(fixture.terrain.site) == before, "Recipe preview never creates stock or registry entries")
		var started := actions.begin_ranged_craft(1, recipe)
		assert(started.ok and started.seconds == SiteRuntime.RANGED_RECIPES[recipe].duration)
		assert(not actions.save_guard().ok and not fixture.terrain.site.has("person_actions"))
		assert(not actions.begin_ranged_craft(1, recipe).ok)
		assert(var_to_bytes(fixture.terrain.site) == before, "Beginning work does not reserve or consume materials")
		actions.advance(float(started.seconds) - 0.01)
		assert(actions.settle_after_contacts().is_empty() and var_to_bytes(fixture.terrain.site) == before)
		actions.advance(0.01)
		assert(var_to_bytes(fixture.terrain.site) == before, "Even finished work waits for contact settlement")
		var results := actions.settle_after_contacts()
		assert(results.size() == 1 and results[0].ok and actions.save_guard().ok)
		assert(actions.settle_after_contacts().is_empty(), "Repeated settlement cannot produce twice")
	assert(stock.wood == original_stock.wood - 10 and stock.iron == original_stock.iron - 4 and stock.fiber == original_stock.fiber - 3)
	assert(stock.tools == 1 and stock.arrow == 10 and stock.bolt == 10)
	assert(is_same(stock, fixture.terrain.site.inventory) and is_same(depot, fixture.terrain.site.depot_items) and cargo.is_empty())
	assert(depot.item_ids.size() == 2 and depot.equipped.is_empty() and fixture.character.fatigue > 0.0)
	var bow_id := ""
	for identity: String in depot.item_ids:
		var record: Dictionary = fixture.terrain.site.item_records[identity]
		assert(record.holder == "depot" and record.original_owner == 1)
		if str(record.definition) == "weapon:bow_01":
			bow_id = identity
	assert(not bow_id.is_empty() and fixture.terrain.site.item_definitions.has("weapon:crossbow_01"))
	var source := actions._source("depot", "depot")
	assert(is_same(source.holder, depot) and is_same(source.cargo, stock) and source.cell == Vector2i(5, 4))
	assert(actions._source("depot", "other").is_empty())
	var collection := actions.begin_loot(1, "depot", "depot", {"arrow": 10}, [bow_id])
	assert(collection.ok and is_equal_approx(float(collection.seconds), 4.2), "Existing loose-item duration owns eleven actual pieces")
	actions.advance(4.2)
	assert(depot.item_ids.has(bow_id) and not cargo.has("arrow"))
	assert(actions.settle_after_contacts()[0].ok)
	assert(cargo.arrow == 10 and is_same(cargo, fixture.character.ammo_inventory) and not stock.has("arrow"))
	assert(fixture.character.item_state.item_ids == [bow_id] and fixture.character.item_state.equipped.is_empty())
	assert(fixture.terrain.site.item_records[bow_id].holder == "person:1" and fixture.changed.count(1) == 1)
	_wear_crafted_bow(fixture, fixture.character, bow_id)
	fixture.character.exchange_enabled = true
	fixture.npc.terrain_cell = Vector2i(8, 4)
	fixture.npc.faction_id = 1
	assert(fixture.character.start_attack(fixture.npc), "The original attack command selects the actual target")
	var actual_records := var_to_bytes(fixture.terrain.site.item_records)
	var depot_before_shot := var_to_bytes(depot)
	assert(fixture.character.ranged_fire(fixture.npc.terrain_cell, 1))
	assert(fixture.character.projectiles.size() == 1 and fixture.character.projectiles[0].visual == "arrow")
	assert(fixture.character.projectiles[0].shooter_id == 1 and fixture.character.projectiles[0].target_cell == fixture.npc.terrain_cell)
	assert(cargo.arrow == 9 and is_same(cargo, fixture.character.ammo_inventory) and stock.bolt == 10)
	assert(var_to_bytes(fixture.terrain.site.item_records) == actual_records and var_to_bytes(depot) == depot_before_shot,
		"Firing consumes exactly one carried arrow, never the bow or remaining depot stock")
	assert(not fixture.character.ranged_fire(fixture.npc.terrain_cell, 2) and cargo.arrow == 9)
	fixture.close()

func _wear_crafted_bow(fixture: Fixture, person: TerrainTestCharacter, item_id: String) -> void:
	var held: Dictionary = person.item_state
	var cargo: Dictionary = person.ammo_inventory
	var equipped := fixture.equipment.begin_personal(person.person_id, "weapon", item_id)
	assert(equipped.ok and equipped.seconds == 5.0)
	fixture.actions.advance(4.999)
	assert(fixture.actions.settle_after_contacts().is_empty() and held.equipped.is_empty())
	fixture.actions.advance(0.001)
	assert(held.equipped.is_empty(), "Finished equipment work still waits for original post-contact settlement")
	assert(fixture.actions.settle_after_contacts()[0].ok)
	assert(is_same(held, person.item_state) and is_same(cargo, person.ammo_inventory))
	assert(held.equipped.weapon == item_id and person.ranged_profile().ammo == "arrow")
	assert(fixture.actions.settle_after_contacts().is_empty())

func _check_controlled_npc_equipment() -> void:
	var fixture := Fixture.new()
	assert(fixture.actions.begin_ranged_craft(2, "bow").ok)
	fixture.actions.advance(120.0)
	var crafted := fixture.actions.settle_after_contacts()
	assert(crafted.size() == 1 and crafted[0].ok)
	var item_id := str(crafted[0].item_id)
	assert(fixture.actions.begin_loot(2, "depot", "depot", {}, [item_id]).ok)
	fixture.actions.advance(2.2)
	assert(fixture.actions.settle_after_contacts()[0].ok)
	assert(fixture.equipment.begin_personal(2, "weapon", item_id).code == "NO_AUTHORITY")
	fixture.controlled_id = 2 # The original NPC becomes the controlled person; no surrogate body or nationality.
	_wear_crafted_bow(fixture, fixture.npc, item_id)
	assert(not fixture.terrain.site.has("equipment_nations") and fixture.terrain.site.item_records[item_id].holder == "person:2")
	fixture.close()

func _check_interruptions() -> void:
	for interruption: String in ["cancel", "hit", "move", "death", "captive", "stagger", "combat", "holder", "cargo", "depot", "stock", "site"]:
		var fixture := Fixture.new()
		var stock: Dictionary = fixture.terrain.site.inventory
		var depot: Dictionary = fixture.terrain.site.depot_items
		var original_stock := stock.duplicate()
		assert(fixture.actions.begin_ranged_craft(1, "arrow").ok)
		fixture.actions.advance(60.0)
		match interruption:
			"cancel": assert(fixture.actions.cancel(1).ok)
			"hit": fixture.character._received_effective_hit += 1
			"move": fixture.character.terrain_cell += Vector2i.DOWN
			"death": fixture.character.hp = 0.0
			"captive": fixture.character.captive = true
			"stagger": fixture.character.exchange_stagger = 0.3
			"combat": fixture.terrain.site.combat_left = 10.0
			"holder": fixture.character.item_state = fixture.character.item_state.duplicate(true)
			"cargo": fixture.terrain.site.manual.cargo = fixture.terrain.site.manual.cargo.duplicate(true)
			"depot": fixture.terrain.site.depot_items = depot.duplicate(true)
			"stock": fixture.terrain.site.inventory = stock.duplicate(true)
			"site": fixture.terrain.site = fixture.terrain.site.duplicate(true)
		var results := fixture.actions.settle_after_contacts()
		assert(results.is_empty() if interruption == "cancel" else results.size() == 1 and not results[0].ok, interruption)
		assert(stock == original_stock and depot.item_ids.is_empty() and fixture.actions.save_guard().ok, interruption)
		fixture.close()
	var paused := Fixture.new()
	assert(paused.actions.begin_ranged_craft(1, "arrow").ok)
	paused.terrain.site.paused = true
	paused.actions.advance(1000.0)
	assert(paused.actions.job_for(1).elapsed == 0.0 and paused.actions.settle_after_contacts().is_empty())
	paused.terrain.site.paused = false
	paused.actions.advance(60.0)
	paused.terrain.site.paused = true
	assert(paused.actions.settle_after_contacts().is_empty() and not paused.terrain.site.inventory.has("arrow"))
	paused.terrain.site.paused = false
	assert(paused.actions.settle_after_contacts()[0].ok)
	paused.close()

func _check_revalidation_and_work() -> void:
	var invalid := Fixture.new()
	var original := var_to_bytes(invalid.terrain.site)
	assert(not invalid.actions.begin_ranged_craft(1, "unknown").ok)
	invalid.character.terrain_cell = Vector2i(2, 2)
	assert(not invalid.actions.begin_ranged_craft(1, "bow").ok)
	assert(var_to_bytes(invalid.terrain.site) == original and invalid.actions.save_guard().ok)
	invalid.close()
	for change: String in ["tools", "materials", "capacity", "definition"]:
		var fixture := Fixture.new()
		assert(fixture.actions.begin_ranged_craft(1, "bow").ok)
		fixture.actions.advance(120.0)
		match change:
			"tools": fixture.terrain.site.inventory.tools = 0
			"materials": fixture.terrain.site.inventory.wood = 0
			"capacity": fixture.terrain.site.capacity = 0
			"definition": fixture.terrain.site.item_definitions["weapon:bow_01"] = {"slot": "weapon", "asset": "bow_01", "tint": [0.0, 0.0, 0.0, 1.0]}
		var state := var_to_bytes(fixture.terrain.site)
		assert(not fixture.actions.settle_after_contacts()[0].ok and var_to_bytes(fixture.terrain.site) == state, change)
		fixture.close()
	var capacity := Fixture.new()
	var stock: Dictionary = capacity.terrain.site.inventory
	var depot: Dictionary = capacity.terrain.site.depot_items
	assert(SiteRuntime.create_equipment(capacity.terrain, depot, "weapon:bow_01", {"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, 1).ok)
	capacity.terrain.site.capacity = SiteRuntime.inventory_size(stock) + 8
	assert(not SiteRuntime.ranged_craft(capacity.terrain, "arrow", 1, true).ok, "Existing actual depot equipment consumes capacity too")
	capacity.terrain.site.capacity += 1
	assert(SiteRuntime.ranged_craft(capacity.terrain, "arrow", 1, true).ok, "Capacity accounts for material consumption before output")
	capacity.close()
	var race := Fixture.new()
	race.terrain.site.inventory = {"wood": 1, "iron": 1, "tools": 1}
	assert(race.actions.begin_ranged_craft(1, "arrow").ok and race.actions.begin_ranged_craft(2, "arrow").ok)
	race.actions.advance(60.0)
	var results := race.actions.settle_after_contacts()
	assert(results.size() == 2 and results[0].ok and not results[1].ok)
	assert(race.terrain.site.inventory.arrow == 10 and race.terrain.site.inventory.tools == 1)
	race.close()
	var tired := Fixture.new()
	tired.character.fatigue = 70.0
	assert(tired.actions.begin_ranged_craft(1, "arrow").ok)
	tired.actions.advance(60.0)
	assert(tired.actions.job_for(1).elapsed < 60.0 and tired.actions.settle_after_contacts().is_empty(), "Craft uses the original fatigue productivity integral")
	tired.actions.advance(20.0)
	assert(tired.actions.settle_after_contacts()[0].ok)
	tired.close()
