extends SceneTree
## Original people/cart/work owners and real feature holders. Isolated candidate until integration.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Stocks = preload("res://scripts/terrain_lab/site_stockpiles.gd")
const TentTest = preload("res://scripts/tests/site_tent_logistics_test.gd")
const OUT := "res://.godot-temp/site_building_close_20261004/stockpile"
var completed := 0

class CrowdFixture extends TentTest.CrowdFixture:
	var original_identity := -1
	func contains_person(identity: int) -> bool: return identity == original_identity

class Fixture extends TentTest.Fixture:

	func setup(tree_root: Node, data: TerrainData) -> void:
		# Reuse the original actor/action/controller fixture; deploy full original
		# Army arrays so every route step uses the production reservation owner.
		terrain = data
		source.terrain = data
		character.data = data
		npc.data = data
		assert(character.place(Vector2i(3, 2), true) and npc.place(Vector2i(4, 2), true))
		character.ammo_inventory = data.site.manual.cargo
		npc.ammo_inventory = data.site.worker.cargo
		army.free()
		army = TerrainArmy.new()
		source.army = army
		combat_armies.assign([army])
		tree_root.add_child(army)
		army.set_process(false)
		army.team_id = 1
		army.faction_id = 0
		army.role = "logistics"
		army.roster_size = 2
		var positions: Array[Vector2i] = [Vector2i(4, 5), Vector2i(4, 6)]
		assert(army.deploy_at(data, null, null, positions) and army.enable_combat(false))
		for row: Dictionary in army.combat_units:
			row.cargo = {}
			row.item_state = Runtime.new_item_state("person:" + str(row.person_id))
		army.combat_units[0].logistics = true
		source.controlled_id = army.combat_identity(0)
		army.vehicle_transport = site_controller.vehicles
		army.controlled_person_query = controlled_person_id
		# This setup replaces the original fixture's TerrainData; bind the same
		# vehicle owner to that Site before deploying its original vehicle plan.
		site_controller.vehicles.init(site_controller)
		site_controller.work_team.init(self)
		actions.init(self)

	func tick(seconds: float) -> void:
		Runtime.advance(terrain, seconds / 60.0, false, false, Callable(), Callable(),
			func(elapsed: float) -> void: site_controller.work_team.advance(elapsed))
		army.prepare_combat(TerrainArmy.MOVE_DURATION + 0.00001)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(55.0).timeout.connect(func() -> void: quit(1))
	assert(DirAccess.make_dir_recursive_absolute(OUT) == OK)
	_check_real_courier_cart_and_work()
	if completed != 1:
		push_error("STOCKPILE_SYNC_FAILURE: physical phase aborted; retained bounded timer is not success")
		quit(1)
		return
	_check_storage_jobs_and_json()
	if completed != 2:
		push_error("STOCKPILE_SYNC_FAILURE: persistence phase aborted; retained bounded timer is not success")
		quit(1)
		return
	TerrainArmy.release_contact_source()
	assert(completed == 2, "Every physical storage phase must finish")
	await process_frame
	print("SITE_STOCKPILE_TRANSPORT_PASS: two real feature stocks; original person and cart transfers/continuous reserved movement/equipment holder conservation; pottery, steel, rope and wool-cloth local inputs to original workers/cycles/depot; stale versions after processing, KO/faction/range/capacity/active-Crowd refusal with original values intact; stocked demolition refusal and grade/repair cancellation preservation; paid-batch and mixed cargo/item JSON roundtrip, raw integral-float holder versions, checksum-valid invalid references/counts/versions/duplicates and failed-save original-file preservation. No active Native logistics, GPU or performance claim.")
	quit(0)

func _data() -> TerrainData:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.FOREST, 12345, {"size": Vector2i(48, 48)})
	Env.initialize(data, "stockpile-physical-contract")
	for key: String in data.resource_base: Env.change(data, key, {"cleared": true, "remaining": 0})
	for y: int in range(2, 46):
		for x: int in range(2, 46):
			var index := data.index(Vector2i(x, y))
			data.height_levels[index] = 0
			data.site.terrain_changes[str(index)] = 0
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.ramp_edges.fill(0)
	data.water_kind.fill(0)
	data.water_body.fill(-1)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.foundation.fill(80)
	data.groundwater.fill(80)
	data.site.inventory = {"wood": 300, "stone": 300, "clay": 100, "tools": 4, "rope": 30,
		"pottery": 20, "brick": 20, "steel": 20, "fiber": 100, "wool": 100, "iron": 100, "charcoal": 100}
	data.site.capacity = 5000
	data.site.depot_cell = data.index(Vector2i(4, 4))
	data.site.worker.cell = data.index(Vector2i(3, 4))
	data.site.worker_enabled = false
	assert(Runtime.initialize_item_storage(data.site).ok)
	Runtime.rebuild_terrain_edges(data)
	Env.rebuild_indexes(data)
	return data

func _task(feature: Dictionary, action: String) -> Dictionary:
	return {"target": "", "action": action,
		"cell": int(feature.repair.work_cell) if action == "repair" else int(feature.get("pending_build", feature).entrance),
		"mode": "work", "status": "", "progress": 0.0, "work_slot": -1}

func _build(data: TerrainData, kind: String, anchor: Vector2i) -> String:
	var options := {"owner_faction": 0}
	var layout := Runtime.building_cells(data, kind, anchor, Vector2i.ONE, options)
	assert(layout.ok, str(layout))
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var built := Runtime.request_build(data, kind, cells, Callable(), options)
	assert(built.ok, str(built))
	var key := str(built.feature)
	var feature: Dictionary = data.site.features[key]
	Runtime._feature_work(data, key, float(feature.work), Callable(), Callable(), _task(feature, "construct"), {}, 20, 0)
	assert(feature.stage == "complete" and Runtime.validate_feature_layout(data, feature).ok)
	return key

func _door(data: TerrainData, key: String) -> Vector2i:
	return data.cell_from_index(int(data.site.features[key].entrance))

func _depot_contact(f: Fixture) -> Vector2i:
	var depot: Vector2i = f.terrain.cell_from_index(int(f.terrain.site.depot_cell))
	# The original transport permits same-cell contact only for feature entrances.
	# Depot transfers require an actual adjacent original person and legal edge.
	var candidates: Array[Vector2i] = []
	for direction: Vector2i in TerrainData.DIRECTIONS: candidates.append(depot + direction)
	for cell: Vector2i in candidates:
		if not f.terrain.can_step(cell, depot): continue
		if cell == f.army.cells[0]: return cell
		if not f.terrain.is_walkable(cell) or f.army._cell_owners.has(cell) or f.army._reserved_cells.has(cell) \
				or f.site_controller.vehicles.blocks_cell(cell, f.controlled_person_id()) or f.character.occupies_cell(cell) or f.npc.occupies_cell(cell): continue
		var route: Array[Vector2i] = f.terrain.path_between(f.army.cells[0], cell,
			func(step: Vector2i) -> bool: return f.army._cell_owners.has(step) or f.army._reserved_cells.has(step) or f.site_controller.vehicles.blocks_cell(step, f.controlled_person_id()) or f.character.occupies_cell(step) or f.npc.occupies_cell(step))
		if not route.is_empty(): return cell
	assert(false, "No legal original depot contact after another worker's delivery")
	return TerrainArmy.INVALID_CELL

func _live_state(f: Fixture) -> String:
	return JSON.stringify([f.terrain.site, f.army.combat_units, f.army.cells, f.army.moving_to], "", true, true)

func _walk(f: Fixture, goal: Vector2i) -> bool:
	if f.army.cells[0] == goal: return true
	var route := f.terrain.path_between(f.army.cells[0], goal,
		func(cell: Vector2i) -> bool: return f.army._cell_owners.has(cell) or f.army._reserved_cells.has(cell) or f.site_controller.vehicles.blocks_cell(cell, f.army.combat_identity(0)) or f.character.occupies_cell(cell) or f.npc.occupies_cell(cell))
	assert(not route.is_empty(), "Original connected walking route absent: " + str(_movement_diag(f, goal, f.army.combat_identity(0))))
	for next: Vector2i in route:
		var from: Vector2i = f.army.cells[0]
		var goods := [f.cargo().duplicate(true), f.holder().duplicate(true)]
		var plan: Dictionary = f.site_controller.vehicles._step_plan(f.army, 0, next)
		assert(f.terrain.can_step(from, next) and f.army._reserve_combat_step(0, next), str({"from": from, "next": next, "goal": goal, "vehicle_plan": plan, "owner": _movement_diag(f, goal, f.army.combat_identity(0))}))
		f.army.prepare_combat(0.1)
		assert(f.army.cells[0] == from and f.army.moving_to[0] == next, "A reservation teleported its original person")
		f.army.prepare_combat(TerrainArmy.MOVE_DURATION + 0.00001)
		assert(f.army.cells[0] == next and f.army.moving_to[0] == TerrainArmy.INVALID_CELL)
		assert(goods == [f.cargo(), f.holder()], "Original movement minted or dropped personal goods")
	return true

func _transfer(f: Fixture, source: String, destination: String, resources: Dictionary, items: Array = []) -> Dictionary:
	var vehicles := f.site_controller.vehicles
	var left := vehicles._stock(source, true)
	var right := vehicles._stock(destination, true)
	assert(not left.is_empty() and not right.is_empty(), str([source, destination]))
	var result: Dictionary = vehicles.transfer(source, destination, resources, items, int(left.holder.version), int(right.holder.version), f.controlled_person_id())
	if not result.ok:
		var person: Dictionary = f.actions._person(f.controlled_person_id())
		print("STOCKPILE_TRANSFER_REJECTED: ", str({"result": result, "source": source, "destination": destination,
			"person_cell": person.get("cell"), "source_cell": left.cell, "destination_cell": right.cell,
			"source_version": left.holder.version, "destination_version": right.holder.version}))
	return result

func _actor_walk(f: Fixture, goal: Vector2i) -> bool:
	if f.character.terrain_cell == goal: return true
	var route := f.terrain.path_between(f.character.terrain_cell, goal,
		func(cell: Vector2i) -> bool: return f.army.blocks_cell(cell) or f.npc.occupies_cell(cell))
	assert(not route.is_empty(), "Original Actor route absent: " + str(_movement_diag(f, goal, f.character.person_id)))
	for next: Vector2i in route:
		assert(f.character.step(next - f.character.terrain_cell), "Original Actor step refused: " + str(_movement_diag(f, next, f.character.person_id)))
		assert(f.character.is_moving())
		f.character._advance_movement(2.0)
		assert(not f.character.is_moving() and f.character.terrain_cell == next)
	return true

func _movement_diag(f: Fixture, goal: Vector2i, identity: int) -> Dictionary:
	var person: Dictionary = f.actions._person(identity)
	var start: Vector2i = person.get("cell", TerrainArmy.INVALID_CELL)
	return {"person_id": identity, "start": start, "goal": goal, "start_height": f.terrain.effective_height(start) if f.terrain.contains(start) else -1,
		"goal_height": f.terrain.effective_height(goal) if f.terrain.contains(goal) else -1, "walkable": f.terrain.is_walkable(goal), "person": person,
		"army_cells": f.army.cells, "army_steps": f.army.moving_to, "army_reserved": f.army._reserved_cells, "actor_cell": f.character.terrain_cell,
		"actor_moving": f.character.is_moving(), "npc_cell": f.npc.terrain_cell, "vehicles": f.site_controller.vehicles.records()}

func _actor_contact(f: Fixture, key: String) -> Vector2i:
	var entrance: Vector2i = _door(f.terrain, key)
	for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]:
		var cell: Vector2i = entrance + offset
		if not f.terrain.is_walkable(cell) or cell != entrance and not f.terrain.can_step(cell, entrance) or f.army.blocks_cell(cell) or f.npc.occupies_cell(cell): continue
		if cell == f.character.terrain_cell or not f.terrain.path_between(f.character.terrain_cell, cell, func(step: Vector2i) -> bool: return f.army.blocks_cell(step) or f.npc.occupies_cell(step)).is_empty(): return cell
	return TerrainArmy.INVALID_CELL

func _cart_straight(f: Fixture, destination: Vector2i) -> bool:
	var origin: Vector2i = f.army.cells[0]
	assert(origin.y == destination.y and destination.x > origin.x, "Fixture must author the two-door straight east cart route")
	for x: int in range(origin.x + 1, destination.x + 1):
		assert(_walk(f, Vector2i(x, origin.y)))
	return true

func _check_real_courier_cart_and_work() -> void:
	var data := _data()
	var first := _build(data, "warehouse", Vector2i(8, 8))
	var second := _build(data, "warehouse", Vector2i(26, 8))
	var weaver := _build(data, "weaver", Vector2i(12, 16))
	var kiln := _build(data, "kiln", Vector2i(20, 16))
	var smelter := _build(data, "smelter", Vector2i(28, 16))
	_build(data, "well", Vector2i(17, 12))
	_build(data, "well", Vector2i(30, 12))
	for key: String in [first, second, weaver, kiln, smelter]: assert(Stocks.ensure_storage(data, key, 0).ok)
	assert(not is_same(Stocks.storage(data, first).cargo, Stocks.storage(data, second).cargo))
	assert(Stocks.capacity(data.site.features[first]) == 120 and Stocks.capacity(data.site.features[weaver]) == 40)
	var f := Fixture.new()
	root.add_child(f)
	f.setup(root, data)
	var vehicles := f.site_controller.vehicles
	var person := "person:" + str(f.controlled_person_id())
	var original_holder := f.holder()
	var original_cargo := f.cargo()
	var made := Runtime.create_equipment(data, data.site.depot_items, "storage:test-sword",
		{"slot": "weapon", "asset": "longsword_01", "tint": [1.0, 1.0, 1.0, 1.0]}, f.controlled_person_id())
	assert(made.ok)
	assert(_transfer(f, "depot", person, {"wood": 1}, [made.item_id]).ok)
	assert(_walk(f, _door(data, first)))
	assert(_transfer(f, person, Stocks.identity(first), {"wood": 1}, [made.item_id]).ok)
	assert(data.site.item_records[made.item_id].holder == Stocks.identity(first))
	var stock: Dictionary = Stocks.storage(data, first)
	var snapshot := _live_state(f)
	assert(not Runtime.cancel_feature(data, first, Callable(), 0).ok and _live_state(f) == snapshot)
	assert(vehicles.transfer(Stocks.identity(first), person, {"wood": 1}, [], int(stock.holder.version) - 1, int(f.holder().version), f.controlled_person_id()).code == "STALE_SOURCE")
	assert(_live_state(f) == snapshot)
	f.army.combat_hot_set(0, &"ko", 10.0)
	snapshot = _live_state(f)
	assert(not _transfer(f, Stocks.identity(first), person, {"wood": 1}).ok and _live_state(f) == snapshot)
	f.army.combat_hot_set(0, &"ko", 0.0)
	data.site.features[first].owner_faction = 1
	snapshot = _live_state(f)
	assert(not _transfer(f, Stocks.identity(first), person, {"wood": 1}).ok and _live_state(f) == snapshot)
	data.site.features[first].owner_faction = 0
	var active_crowd := CrowdFixture.new()
	active_crowd.original_identity = f.controlled_person_id()
	f.crowd_site = active_crowd
	snapshot = _live_state(f)
	assert(_transfer(f, Stocks.identity(first), person, {"wood": 1}).code == "CROWD_ACTIVE" and _live_state(f) == snapshot)
	f.crowd_site = null
	f.cargo().wood = 20
	snapshot = _live_state(f)
	assert(_transfer(f, Stocks.identity(first), person, {"wood": 1}).code == "STORAGE_FULL" and _live_state(f) == snapshot)
	f.cargo().erase("wood")
	# The new independent-person endpoint is the original controlled Actor itself,
	# with its original manual cargo and item_state; no temporary Army member.
	assert(_walk(f, _door(data, first) + Vector2i.DOWN))
	f.source.controlled_id = f.character.person_id
	var actor_stop: Vector2i = _actor_contact(f, first)
	assert(actor_stop != TerrainArmy.INVALID_CELL, "No free original legal Actor facility contact: " + str(_movement_diag(f, _door(data, first), f.character.person_id)))
	assert(_actor_walk(f, actor_stop))
	assert(f.character.terrain_cell != f.army.cells[0] and data.can_step(f.character.terrain_cell, _door(data, first)), "Independent Actor contact must be physically separate and legal")
	var actor_holder := f.character.item_state
	var actor_cargo: Dictionary = data.site.manual.cargo
	var actor_receive: Dictionary = _transfer(f, Stocks.identity(first), "person:1", {"wood": 1})
	assert(actor_receive.ok, str({"result": actor_receive, "contact": _movement_diag(f, _door(data, first), f.character.person_id)}))
	assert(actor_cargo.wood == 1 and is_same(actor_holder, f.character.item_state))
	var actor_return: Dictionary = _transfer(f, "person:1", Stocks.identity(first), {"wood": 1})
	assert(actor_return.ok and actor_cargo.is_empty(), str({"result": actor_return, "contact": _movement_diag(f, _door(data, first), f.character.person_id)}))
	assert(_actor_walk(f, Vector2i(3, 2)))
	f.source.controlled_id = f.army.combat_identity(0)
	assert(_walk(f, _door(data, second)))
	snapshot = _live_state(f)
	assert(not _transfer(f, Stocks.identity(first), person, {"wood": 1}).ok and _live_state(f) == snapshot)
	assert(_walk(f, _door(data, first)))
	# The original cart is deployed explicitly in the fixture. No storage UI generates one.
	var plan := [{"kind": "cart", "team_id": f.army.team_id,
		"cell": data.index(f.army.cells[0] + Vector2i.RIGHT), "facing": [1, 0], "operator_index": 0}]
	assert(vehicles.deploy_plan(f.army, plan).ok)
	var cart: Dictionary = vehicles.records().values()[0]
	assert(_transfer(f, Stocks.identity(first), str(cart.id), {"wood": 1}, [made.item_id]).ok)
	assert(data.site.item_records[made.item_id].holder == cart.holder.holder)
	assert(stock.holder.item_ids.is_empty() and Runtime.inventory_size(stock.cargo) == 0)
	assert(_cart_straight(f, _door(data, second)))
	assert(cart.move.is_empty() and data.cell_from_index(int(cart.cell)) == f.army.cells[0] + Vector2i.RIGHT)
	assert(_transfer(f, str(cart.id), Stocks.identity(second), {"wood": 1}, [made.item_id]).ok)
	assert(cart.cargo.is_empty() and cart.holder.item_ids.is_empty())
	assert(vehicles.unassign_operator(str(cart.id), f.controlled_person_id()).ok)
	assert(_transfer(f, Stocks.identity(second), person, {"wood": 1}, [made.item_id]).ok)
	assert(Stocks.storage(data, second).holder.item_ids.is_empty() and Runtime.inventory_size(Stocks.storage(data, second).cargo) == 0)
	assert(_walk(f, _depot_contact(f)))
	var depot_return: Dictionary = _transfer(f, person, "depot", {"wood": 1}, [made.item_id])
	assert(depot_return.ok, str(depot_return))
	assert(data.site.item_records[made.item_id].holder == "depot" and data.site.depot_items.item_ids == [made.item_id],
		str({"record": data.site.item_records[made.item_id], "depot": data.site.depot_items, "expected_item": made.item_id}))
	assert(is_same(original_holder, f.holder()) and is_same(original_cargo, f.cargo()))
	# Four actual alternate material inputs travel from camp to the first warehouse,
	# then on the original courier to each local workshop. One original worker
	# alone owns work, fatigue, completed output cargo and the return to camp.
	for recipe: Array in [[weaver, "rope"], [weaver, "wool_cloth"], [kiln, "pottery"], [smelter, "steel"]]:
		var key := str(recipe[0])
		var feature: Dictionary = data.site.features[key]
		Runtime._stop_feature_zones(data, key, "operate")
		assert(Runtime.request_feature_recipe(data, key, str(recipe[1]), 0).ok)
		assert(Stocks.set_local_supply(data, key, true, 0).ok)
		var definition := Runtime.feature_recipe(feature)
		assert(_walk(f, _depot_contact(f)))
		assert(_transfer(f, "depot", person, definition.input).ok)
		assert(_walk(f, _door(data, first)))
		assert(_transfer(f, person, Stocks.identity(first), definition.input).ok)
		assert(_transfer(f, Stocks.identity(first), person, definition.input).ok)
		assert(_walk(f, _door(data, key)))
		assert(_transfer(f, person, Stocks.identity(key), definition.input).ok)
		assert(_walk(f, _door(data, key) + Vector2i(0, 2)))
		var local: Dictionary = Stocks.storage(data, key)
		var old_version := int(local.holder.version)
		var camp_before: Dictionary = data.site.inventory.duplicate(true)
		assert(Runtime.operate_feature(data, key).ok)
		snapshot = _live_state(f)
		assert(not Stocks.set_local_supply(data, key, false, 0).ok and _live_state(f) == snapshot,
			"An enabled original work zone changed supply ownership before worker arrival")
		var worker_id := f.army.combat_identity(1)
		assert(f.site_controller.work_team.assign(f.army, [worker_id], f.controlled_person_id()).ok)
		var row: Dictionary = f.army.combat_units[1]
		var output_at_camp := false
		var carried := false
		var arrived := false
		for _step: int in range(220):
			f.tick(30.0)
			arrived = arrived or f.army.cells[1] == _door(data, key)
			carried = carried or Runtime.can_pay(row.cargo, definition.output)
			output_at_camp = Runtime.can_pay(data.site.inventory, _plus(camp_before, definition.output))
			if output_at_camp: break
		assert(arrived and carried and output_at_camp, "Original local cycle/worker/return incomplete: " + str(recipe))
		assert(Runtime.inventory_size(local.cargo) == 0 and int(local.holder.version) == old_version + 1)
		assert(data.site.inventory == _plus(camp_before, definition.output) and row.cargo.is_empty())
		assert(PersonFatigue.read(row) > 0.0)
		assert(f.site_controller.work_team.cancel(worker_id).ok)
		Runtime._stop_feature_zones(data, key, "operate")
		assert(_walk(f, _door(data, key)))
		snapshot = _live_state(f)
		assert(vehicles.transfer(Stocks.identity(key), person, {"wood": 1}, [], old_version, int(f.holder().version), f.controlled_person_id()).code == "STALE_SOURCE")
		assert(_live_state(f) == snapshot, "A stale UI version passed after original processing")
	f.close()
	completed += 1

func _plus(left: Dictionary, right: Dictionary) -> Dictionary:
	var result := left.duplicate(true)
	Runtime.add_items(result, right)
	return result

func _check_storage_jobs_and_json() -> void:
	var data := _data()
	var first := _build(data, "warehouse", Vector2i(8, 8))
	var second := _build(data, "warehouse", Vector2i(26, 8))
	var weaver := _build(data, "weaver", Vector2i(14, 16))
	for key: String in [first, second, weaver]: assert(Stocks.ensure_storage(data, key, 0).ok)
	var stock: Dictionary = Stocks.storage(data, first)
	var created := Runtime.create_equipment(data, data.site.depot_items, "storage:saved-sword",
		{"slot": "weapon", "asset": "longsword_01", "tint": [1.0, 1.0, 1.0, 1.0]}, 1)
	assert(created.ok)
	assert(Runtime.transfer_items(data, data.site.depot_items, data.site.inventory, stock.holder, stock.cargo,
		{"wood": 3}, [created.item_id], int(data.site.depot_items.version), int(stock.holder.version), Stocks.capacity(data.site.features[first])).ok)
	var goods := stock.duplicate(true)
	assert(Runtime.request_upgrade(data, first, 0).ok)
	var feature: Dictionary = data.site.features[first]
	Runtime._feature_work(data, first, float(feature.pending_build.work) * 0.5, Callable(), Callable(), _task(feature, "construct"), {}, 20, 0)
	assert(Runtime.cancel_feature(data, first, Callable(), 0).ok and Stocks.storage(data, first) == goods)
	assert(Runtime.request_upgrade(data, first, 0).ok)
	Runtime._feature_work(data, first, float(feature.pending_build.work), Callable(), Callable(), _task(feature, "construct"), {}, 20, 0)
	assert(Stocks.storage(data, first) == goods and Stocks.capacity(feature) == 180)
	assert(Runtime.damage_structure_part(data, first, "body", 50.0).ok)
	assert(Runtime.request_repair(data, first, "body", 0).ok)
	Runtime._feature_work(data, first, float(feature.repair.work) * 0.5, Callable(), Callable(), _task(feature, "repair"), {}, 20, 0)
	assert(Runtime.cancel_feature(data, first, Callable(), 0).ok and Stocks.storage(data, first) == goods)
	assert(Runtime.request_feature_recipe(data, weaver, "rope", 0).ok and Stocks.set_local_supply(data, weaver, true, 0).ok)
	var local: Dictionary = Stocks.storage(data, weaver)
	assert(Runtime.transfer_items(data, data.site.depot_items, data.site.inventory, local.holder, local.cargo,
		{"fiber": 2}, [], int(data.site.depot_items.version), int(local.holder.version), Stocks.capacity(data.site.features[weaver])).ok)
	var work: Dictionary = data.site.features[weaver]
	var task := _task(work, "operate")
	var valid_version := int(local.holder.version)
	local.holder.version = 2147483646
	var exhausted_state := JSON.stringify(data.site, "", true, true)
	Runtime._feature_work(data, weaver, 4.0, Callable(), Callable(), task, {}, 20, 0)
	assert(JSON.stringify(data.site, "", true, true) == exhausted_state and not work.batch_paid,
		"An exhausted original stock version debited materials or began a batch")
	local.holder.version = valid_version
	Runtime._feature_work(data, weaver, 4.0, Callable(), Callable(), task, {}, 20, 0)
	assert(work.batch_paid and float(work.production) == 4.0 and Runtime.inventory_size(local.cargo) == 0 and int(local.holder.version) == valid_version + 1)
	assert(Store.save(data, OUT + "/good.json").ok)
	var raw_text := FileAccess.get_file_as_string(OUT + "/good.json")
	var envelope: Dictionary = JSON.parse_string(raw_text)
	var payload: Dictionary = JSON.parse_string(envelope.payload)
	assert(payload.state.stockpiles[first].holder.version is float)
	var normalized := Store.load_site(OUT + "/good.json")
	assert(normalized.ok, str(normalized))
	assert(normalized.data.site.stockpiles[first].holder.version is int)
	assert(normalized.data.site.stockpiles[first] == stock and normalized.data.site.stockpiles[second].cargo.is_empty())
	var resumed: TerrainData = normalized.data
	var resumed_stock := Stocks.storage(resumed, weaver).duplicate(true)
	var output := {}
	Runtime._feature_work(resumed, weaver, 4.0, Callable(), Callable(), _task(resumed.site.features[weaver], "operate"), output, 20, 0)
	assert(output == {"rope": 2} and Stocks.storage(resumed, weaver) == resumed_stock)
	assert(Runtime.deposit(resumed, output, resumed.cell_from_index(int(resumed.site.depot_cell))).ok)
	for kind: String in ["unknown_ref", "wrong_holder", "future_stock_version", "fractional_holder_version", "negative_cargo", "fractional_cargo", "unknown_resource", "over_capacity", "missing_local_ref", "remote_supply", "duplicate_item", "wearing_storage"]:
		var bad: Dictionary = payload.duplicate(true)
		match kind:
			"unknown_ref": bad.state.stockpiles["999999"] = bad.state.stockpiles[first].duplicate(true)
			"wrong_holder": bad.state.stockpiles[first].holder.holder = Stocks.identity(second)
			"future_stock_version": bad.state.stockpiles[first].version = 2
			"fractional_holder_version": bad.state.stockpiles[first].holder.version = 1.25
			"negative_cargo": bad.state.stockpiles[first].cargo.wood = -1
			"fractional_cargo": bad.state.stockpiles[first].cargo.wood = 1.5
			"unknown_resource": bad.state.stockpiles[first].cargo.magic = 1
			"over_capacity": bad.state.stockpiles[first].cargo.wood = 180
			"missing_local_ref": bad.state.stockpiles.erase(weaver)
			"remote_supply": bad.state.features[weaver].supply_mode = Stocks.identity(first)
			"duplicate_item": bad.state.stockpiles[second].holder.item_ids.append(created.item_id)
			"wearing_storage": bad.state.stockpiles[first].holder.equipped.weapon = created.item_id
		var body := JSON.stringify(bad, "", true, true)
		var path := OUT + "/bad_" + kind + ".json"
		var file := FileAccess.open(path, FileAccess.WRITE)
		assert(file != null)
		file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}))
		file.close()
		var original := JSON.stringify(data.site, "", true, true)
		var refused := Store.load_site(path)
		assert(not refused.ok and refused.code == "CORRUPT_SAVE", str([kind, refused]))
		assert(FileAccess.get_file_as_string(OUT + "/good.json") == raw_text and JSON.stringify(data.site, "", true, true) == original)
	# Saving invalid live values may not overwrite the last valid original file.
	stock.cargo.wood = -1
	var invalid_original := JSON.stringify(data.site, "", true, true)
	assert(not Store.save(data, OUT + "/good.json").ok)
	assert(FileAccess.get_file_as_string(OUT + "/good.json") == raw_text and JSON.stringify(data.site, "", true, true) == invalid_original)
	stock.cargo.wood = 3
	completed += 1
