extends SceneTree
## Fire ammunition uses the existing craft/job/holder transaction fixture.
## This test does not admit a projectile backend or claim fire simulation support.
const CraftTest = preload("res://scripts/tests/site_ranged_crafting_test.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	_check_commit_and_collection()
	_check_cancel_and_revalidation()
	_check_capacity_and_stack_limit()
	_check_competing_crafters()
	_check_pause()
	_check_sealed_selection()
	print("SITE_FIRE_RANGED_CRAFTING_PASS: original paid fire-arrow recipe, preview/commit/retry conservation, interruptions and source revalidation, capacity/stack bounds, two-person competition, original cargo collection and sealed-ammunition selection")
	quit(0)

func _supply(fixture: Variant, batches: int = 1) -> void:
	var stock: Dictionary = fixture.terrain.site.inventory
	stock.clear()
	stock.merge({"tools": 1, "arrow": 5 * batches, "cloth": batches, "charcoal": batches})

func _check_commit_and_collection() -> void:
	var fixture := CraftTest.Fixture.new()
	_supply(fixture)
	var stock: Dictionary = fixture.terrain.site.inventory
	var depot: Dictionary = fixture.terrain.site.depot_items
	var cargo: Dictionary = fixture.terrain.site.manual.cargo
	var depot_version := int(depot.version)
	var before := var_to_bytes(fixture.terrain.site)
	assert(SiteEnvironment.ITEM_NAMES.get("fire_arrow") == "火箭")
	var preview := SiteRuntime.ranged_craft(fixture.terrain, "fire_arrow", 1, true)
	assert(preview.ok and preview.seconds == 60.0)
	assert(var_to_bytes(fixture.terrain.site) == before, "Preview must not mint or consume ammunition")
	var started := fixture.actions.begin_ranged_craft(1, "fire_arrow")
	assert(started.ok and started.seconds == 60.0)
	assert(not fixture.actions.save_guard().ok and not fixture.actions.begin_ranged_craft(1, "fire_arrow").ok)
	assert(var_to_bytes(fixture.terrain.site) == before, "Starting work leaves original materials in camp")
	fixture.actions.advance(59.99)
	assert(fixture.actions.settle_after_contacts().is_empty() and var_to_bytes(fixture.terrain.site) == before)
	fixture.actions.advance(0.01)
	assert(var_to_bytes(fixture.terrain.site) == before, "Completed work waits for the original contact boundary")
	var results := fixture.actions.settle_after_contacts()
	assert(results.size() == 1 and results[0].ok and fixture.actions.save_guard().ok)
	assert(stock == {"tools": 1, "fire_arrow": 5}, "Exactly five original arrows, one cloth and one charcoal become five fire arrows")
	assert(int(depot.version) == depot_version + 1 and cargo.is_empty())
	assert(depot.item_ids.is_empty() and fixture.terrain.site.item_records.is_empty(), "Ammunition stays in the original resource stack")
	var committed := var_to_bytes(fixture.terrain.site)
	assert(fixture.actions.settle_after_contacts().is_empty() and var_to_bytes(fixture.terrain.site) == committed)
	var holder_version := int(fixture.character.item_state.version)
	var collection := fixture.actions.begin_loot(1, "depot", "depot", {"fire_arrow": 5}, [])
	assert(collection.ok and cargo.is_empty() and stock.fire_arrow == 5)
	fixture.actions.advance(float(collection.seconds))
	assert(cargo.is_empty() and stock.fire_arrow == 5)
	results = fixture.actions.settle_after_contacts()
	assert(results.size() == 1 and results[0].ok)
	assert(stock == {"tools": 1} and cargo == {"fire_arrow": 5})
	assert(is_same(cargo, fixture.character.ammo_inventory) and is_same(depot, fixture.terrain.site.depot_items))
	assert(int(fixture.character.item_state.version) == holder_version + 1 and int(depot.version) == depot_version + 2)
	committed = var_to_bytes(fixture.terrain.site)
	assert(fixture.actions.settle_after_contacts().is_empty() and var_to_bytes(fixture.terrain.site) == committed)
	fixture.close()

func _check_cancel_and_revalidation() -> void:
	for change: String in ["cancel", "move", "hit", "holder_version", "holder", "depot", "stock", "site", "arrow", "cloth", "charcoal", "tools", "capacity", "depot_version"]:
		var fixture := CraftTest.Fixture.new()
		_supply(fixture)
		var stock: Dictionary = fixture.terrain.site.inventory
		assert(fixture.actions.begin_ranged_craft(1, "fire_arrow").ok)
		fixture.actions.advance(60.0)
		match change:
			"cancel": assert(fixture.actions.cancel(1).ok)
			"move": fixture.character.terrain_cell += Vector2i.DOWN
			"hit": fixture.character._received_effective_hit += 1
			"holder_version": fixture.character.item_state.version += 1
			"holder": fixture.character.item_state = fixture.character.item_state.duplicate(true)
			"depot": fixture.terrain.site.depot_items = fixture.terrain.site.depot_items.duplicate(true)
			"stock": fixture.terrain.site.inventory = stock.duplicate(true)
			"site": fixture.terrain.site = fixture.terrain.site.duplicate(true)
			"arrow": stock.arrow = 4
			"cloth": stock.cloth = 0
			"charcoal": stock.charcoal = 0
			"tools": stock.tools = 0
			"capacity": fixture.terrain.site.capacity = 5
			"depot_version": fixture.terrain.site.depot_items.version = 2147483646
		var before := var_to_bytes(fixture.terrain.site)
		var retained := stock.duplicate()
		var results := fixture.actions.settle_after_contacts()
		assert(results.is_empty() if change == "cancel" else results.size() == 1 and not results[0].ok, change)
		assert(var_to_bytes(fixture.terrain.site) == before and stock == retained and not stock.has("fire_arrow"), change)
		assert(fixture.actions.save_guard().ok and fixture.actions.settle_after_contacts().is_empty(), change)
		fixture.close()

func _check_capacity_and_stack_limit() -> void:
	var fixture := CraftTest.Fixture.new()
	_supply(fixture)
	fixture.terrain.site.capacity = 5
	var before := var_to_bytes(fixture.terrain.site)
	assert(not fixture.actions.begin_ranged_craft(1, "fire_arrow").ok)
	assert(var_to_bytes(fixture.terrain.site) == before and fixture.actions.save_guard().ok)
	fixture.terrain.site.capacity = 6 # One unchanged tool plus five finished fire arrows.
	assert(SiteRuntime.ranged_craft(fixture.terrain, "fire_arrow", 1, true).ok)
	assert(SiteRuntime.create_equipment(fixture.terrain, fixture.terrain.site.depot_items, "weapon:bow_01", {"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, 1).ok)
	assert(not SiteRuntime.ranged_craft(fixture.terrain, "fire_arrow", 1, true).ok, "Original depot equipment also consumes capacity")
	fixture.terrain.site.capacity = 7
	assert(SiteRuntime.ranged_craft(fixture.terrain, "fire_arrow", 1, true).ok)
	fixture.terrain.site.capacity = 2000000
	fixture.terrain.site.inventory.fire_arrow = 999996
	before = var_to_bytes(fixture.terrain.site)
	assert(not SiteRuntime.ranged_craft(fixture.terrain, "fire_arrow", 1).ok)
	assert(var_to_bytes(fixture.terrain.site) == before, "Output stack overflow leaves all original materials unchanged")
	fixture.terrain.site.inventory.fire_arrow = 999995
	assert(SiteRuntime.ranged_craft(fixture.terrain, "fire_arrow", 1).ok)
	assert(fixture.terrain.site.inventory.fire_arrow == 1000000 and fixture.terrain.site.inventory.tools == 1)
	fixture.close()

func _check_competing_crafters() -> void:
	for batches: int in [1, 2]:
		var fixture := CraftTest.Fixture.new()
		_supply(fixture, batches)
		assert(fixture.actions.begin_ranged_craft(1, "fire_arrow").ok and fixture.actions.begin_ranged_craft(2, "fire_arrow").ok)
		fixture.actions.advance(60.0)
		var results := fixture.actions.settle_after_contacts()
		assert(results.size() == 2 and results[0].ok)
		assert(bool(results[1].ok) == (batches == 2), "Each completion rechecks the shared original camp stock")
		assert(fixture.terrain.site.inventory == {"tools": 1, "fire_arrow": 5 * batches})
		assert(fixture.actions.save_guard().ok and fixture.actions.settle_after_contacts().is_empty())
		fixture.close()

func _check_pause() -> void:
	var fixture := CraftTest.Fixture.new()
	_supply(fixture)
	assert(fixture.actions.begin_ranged_craft(1, "fire_arrow").ok)
	fixture.terrain.site.paused = true
	fixture.actions.advance(1000.0)
	assert(fixture.actions.job_for(1).elapsed == 0.0 and fixture.actions.settle_after_contacts().is_empty())
	fixture.terrain.site.paused = false
	fixture.actions.advance(60.0)
	fixture.terrain.site.paused = true
	assert(fixture.actions.settle_after_contacts().is_empty() and not fixture.terrain.site.inventory.has("fire_arrow"))
	fixture.terrain.site.paused = false
	assert(fixture.actions.settle_after_contacts()[0].ok)
	fixture.close()

func _check_sealed_selection() -> void:
	var fixture := CraftTest.Fixture.new()
	var cargo: Dictionary = fixture.terrain.site.worker.cargo
	cargo.merge({"arrow": 2, "fire_arrow": 3, "bolt": 4, "wood": 1})
	var before := var_to_bytes(fixture.terrain.site)
	var selection := fixture.actions._sealed_selection(fixture.actions._person(2))
	assert(selection.item_ids.is_empty() and selection.resources == {"arrow": 2, "fire_arrow": 3, "bolt": 4})
	assert(var_to_bytes(fixture.terrain.site) == before and cargo.wood == 1, "Sealed selection only reads the original person cargo")
	cargo.fire_arrow = 0
	selection = fixture.actions._sealed_selection(fixture.actions._person(2))
	assert(selection.resources == {"arrow": 2, "bolt": 4}, "Zero fire ammunition does not become a sealed resource")
	fixture.close()
