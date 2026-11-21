extends "res://scripts/tests/site_ship_build_test.gd"
## Candidate regression, reuses original geography, facilities, Army and WorkTeam.
const SHIP_REPAIR_SAVE: String = "res://output/site_ship_close_20261004/repair_test/natural_active_repair.json"

func _run() -> void:
	_material_and_cancel()
	_guards_and_saved_receipt()
	_fixed_budget_and_sink()
	_original_repair_worker()
	TerrainArmy.release_contact_source()
	run_completed = true
	print("SITE_SHIP_REPAIR_PASS")
	quit(0)

func _repair_fixture() -> Dictionary:
	var data: TerrainData = _ship_fixture()
	var feature_id: String = _yard(data, 25)
	# Port side against the original facility, not a fake stern contact.
	var vehicle: Dictionary = Ships.make_record("1", 1, "ferry", data.index(Vector2i(25, 34)), Vector2i.LEFT)
	vehicle.naval.hp = Ships.hull_hp("ferry") * 0.5
	data.site.vehicles["1"] = vehicle
	data.site.next_vehicle = 2
	return {"data": data, "vehicle": vehicle, "feature_id": feature_id}

func _q(data: TerrainData) -> Callable:
	# Fixture has no passengers/shared supply/loot; only original hull cargo.
	return func(identity: String) -> Dictionary:
		var vehicle: Dictionary = data.site.vehicles[identity]
		return Runtime.ok("Fixture original cargo", {"load": Runtime.carried_load(data.site, vehicle.cargo, vehicle.holder), "capacity": float(Ships.definition(str(vehicle.ship_type)).capacity)})

func _start(fixture: Dictionary) -> void:
	var result: Dictionary = Runtime.request_ship_repair(fixture.data, "1", fixture.feature_id, 1, false, _q(fixture.data))
	assert(result.ok, str(result))
	assert(fixture.vehicle.naval.repair.size() == 7)
	assert(Runtime.validate_ship_repair(fixture.data, fixture.vehicle).ok)

func _material_and_cancel() -> void:
	var fixture: Dictionary = _repair_fixture()
	var data: TerrainData = fixture.data
	var vehicle: Dictionary = fixture.vehicle
	var before: PackedByteArray = var_to_bytes(data.site)
	assert(Runtime.request_ship_repair(data, "1", fixture.feature_id, 1, true, _q(data)).ok)
	assert(var_to_bytes(data.site) == before, "Preview is wholly pure")
	var depot: Dictionary = data.site.inventory.duplicate()
	_start(fixture)
	var cost: Dictionary = vehicle.naval.repair.paid_cost.duplicate()
	for resource: String in cost:
		assert(int(vehicle.cargo[resource]) == int(cost[resource]))
		assert(int(data.site.inventory[resource]) + int(vehicle.cargo[resource]) == int(depot[resource]), "Begin transfers existing resources exactly once")
	assert(int(vehicle.holder.version) == 1)
	before = var_to_bytes(data.site)
	assert(not Runtime.request_ship_repair(data, "1", fixture.feature_id, 1, false, _q(data)).ok and var_to_bytes(data.site) == before)
	var job: Dictionary = vehicle.naval.repair
	var stations: Array[Dictionary] = Runtime.ship_repair_work_slots(data, vehicle)
	var station: Dictionary = stations[0]
	var progress: float = float(job.total_work) * 0.25
	assert(Runtime.advance_ship_repair_work(data, "1", progress, data.cell_from_index(int(station.cell)), int(station.slot), 1).ok)
	for resource: String in cost: assert(int(vehicle.cargo.get(resource, 0)) == int(cost[resource]) - floori(float(cost[resource]) * 0.25))
	assert(is_equal_approx(float(vehicle.naval.hp), Ships.hull_hp("ferry") * 0.625))
	before = var_to_bytes(data.site)
	var preview: Dictionary = Runtime.cancel_ship_repair(data, "1", 1, true)
	assert(preview.ok and var_to_bytes(data.site) == before)
	assert(Runtime.cancel_ship_repair(data, "1", 1).ok)
	for resource: String in cost:
		assert(int(vehicle.cargo.get(resource, 0)) == floori(float(cost[resource]) * 0.75), "Cancellation applies original floor remaining without remote refunds")
		assert(int(data.site.inventory[resource]) == int(depot[resource]) - int(cost[resource]))
	assert(vehicle.naval.repair.is_empty() and int(vehicle.holder.version) == 3)
	# An arbitrarily short job must still pay for nonzero restoration on release.
	var tiny: Dictionary = _repair_fixture()
	_start(tiny)
	var tiny_job: Dictionary = tiny.vehicle.naval.repair
	var tiny_cost: Dictionary = tiny_job.paid_cost.duplicate()
	var tiny_station: Dictionary = Runtime.ship_repair_work_slots(tiny.data, tiny.vehicle)[0]
	assert(Runtime.advance_ship_repair_work(tiny.data, "1", 0.001, tiny.data.cell_from_index(int(tiny_station.cell)), int(tiny_station.slot), 1).ok)
	assert(Runtime.cancel_ship_repair(tiny.data, "1", 1).ok)
	for resource: String in tiny_cost: assert(int(tiny.vehicle.cargo.get(resource, 0)) == int(tiny_cost[resource]) - 1, "Start/work/cancel cannot create free HP")

func _guards_and_saved_receipt() -> void:
	var fixture: Dictionary = _repair_fixture()
	var data: TerrainData = fixture.data
	var vehicle: Dictionary = fixture.vehicle
	var before: PackedByteArray = var_to_bytes(data.site)
	assert(not Runtime.request_ship_repair(data, "1", fixture.feature_id, 1).ok and var_to_bytes(data.site) == before, "Whole boat Q owner is required")
	var full: Callable = func(_identity: String) -> Dictionary: return Runtime.ok("full", {"load": float(Ships.definition("ferry").capacity), "capacity": float(Ships.definition("ferry").capacity)})
	assert(not Runtime.request_ship_repair(data, "1", fixture.feature_id, 1, false, full).ok and var_to_bytes(data.site) == before)
	assert(not Runtime.request_ship_repair(data, "1", fixture.feature_id, 2, false, _q(data)).ok and var_to_bytes(data.site) == before)
	_start(fixture)
	var station: Dictionary = Runtime.ship_repair_work_slots(data, vehicle)[0]
	before = var_to_bytes(data.site)
	assert(not Runtime.advance_ship_repair_work(data, "1", 10.0, Vector2i(20, 45), int(station.slot), 1).ok and var_to_bytes(data.site) == before)
	data.site.paused = true
	before = var_to_bytes(data.site)
	assert(not Runtime.advance_ship_repair_work(data, "1", 10.0, data.cell_from_index(int(station.cell)), int(station.slot), 1).ok and var_to_bytes(data.site) == before)
	data.site.paused = false
	assert(Runtime.ship_repair_uses_team(data, 1) and Runtime.ship_repair_uses_feature(data, fixture.feature_id))
	before = var_to_bytes(data.site)
	assert(not Runtime.cancel_feature(data, fixture.feature_id, Callable(), 0).ok and var_to_bytes(data.site) == before)
	var restored: Dictionary = bytes_to_var(var_to_bytes(data.site))
	assert(Runtime.validate_ship_repair(data, restored.vehicles["1"], restored).ok)
	var parsed: Variant = JSON.parse_string(JSON.stringify(restored))
	assert(parsed is Dictionary)
	var parsed_before: PackedByteArray = var_to_bytes(parsed)
	assert(Runtime.validate_ship_repair(data, parsed.vehicles["1"], parsed).ok, "Pure receipt validation accepts original raw JSON integral holder/cargo numbers")
	assert(var_to_bytes(parsed) == parsed_before, "Receipt validation never normalizes or mutates the original saved owner")
	var fractional_holder: Dictionary = parsed.duplicate(true)
	fractional_holder.vehicles["1"].holder.version = 1.5
	assert(not Runtime.validate_ship_repair(data, fractional_holder.vehicles["1"], fractional_holder).ok, "Fractional holder versions remain invalid")
	var fractional_cargo: Dictionary = parsed.duplicate(true)
	fractional_cargo.vehicles["1"].cargo.wood = 10.5
	assert(not Runtime.validate_ship_repair(data, fractional_cargo.vehicles["1"], fractional_cargo).ok, "Fractional original resource quantities remain invalid")
	var oversized_cargo: Dictionary = parsed.duplicate(true)
	oversized_cargo.vehicles["1"].cargo.wood = 1000001.0
	assert(not Runtime.validate_ship_repair(data, oversized_cargo.vehicles["1"], oversized_cargo).ok, "Original resource stack bound remains strict")
	for field: String in ["total_work", "amount", "applied", "progress"]:
		var bad: Dictionary = restored.duplicate(true)
		bad.vehicles["1"].naval.repair[field] = -1.0
		assert(not Runtime.validate_ship_repair(data, bad.vehicles["1"], bad).ok)
	var finished: Dictionary = restored.duplicate(true)
	finished.vehicles["1"].naval.repair.progress = float(finished.vehicles["1"].naval.repair.total_work)
	finished.vehicles["1"].naval.repair.applied = float(finished.vehicles["1"].naval.repair.amount)
	finished.vehicles["1"].cargo = {}
	assert(not Runtime.validate_ship_repair(data, finished.vehicles["1"], finished).ok, "Completed receipts are cleared, not saved")
	var fake_hp: Dictionary = restored.duplicate(true)
	fake_hp.vehicles["1"].naval.hp = Ships.hull_hp("ferry")
	assert(not Runtime.validate_ship_repair(data, fake_hp.vehicles["1"], fake_hp).ok, "Unfinished receipt cannot pretend the original damage was already healed")
	var fatal: Dictionary = restored.duplicate(true)
	fatal.vehicles["1"].naval.hp = 0.0
	fatal.vehicles["1"].naval.state = "sinking"
	assert(not Runtime.validate_ship_repair(data, fatal.vehicles["1"], fatal).ok)
	assert(Runtime.validate_ship_repair(data, fatal.vehicles["1"], fatal, true).ok, "Only internal wreck settlement accepts a fatal unfinished receipt")
	var missing: Dictionary = restored.duplicate(true)
	missing.vehicles["1"].cargo.wood = 0
	assert(not Runtime.validate_ship_repair(data, missing.vehicles["1"], missing).ok)

func _fixed_budget_and_sink() -> void:
	var fixture: Dictionary = _repair_fixture()
	var data: TerrainData = fixture.data
	var vehicle: Dictionary = fixture.vehicle
	_start(fixture)
	var total: float = float(vehicle.naval.repair.total_work)
	var station: Dictionary = Runtime.ship_repair_work_slots(data, vehicle)[0]
	assert(Runtime.advance_ship_repair_work(data, "1", total * 0.5, data.cell_from_index(int(station.cell)), int(station.slot), 1).ok)
	assert(Runtime.damage_ship_vehicle(data, "1", 10.0).ok)
	assert(Runtime.advance_ship_repair_work(data, "1", total * 10.0, data.cell_from_index(int(station.cell)), int(station.slot), 1).ok)
	assert(is_equal_approx(float(vehicle.naval.hp), Ships.hull_hp("ferry") - 10.0), "New damage never increases the original paid HP budget")
	assert(vehicle.naval.repair.is_empty() and Runtime.inventory_size(vehicle.cargo) == 0)
	var sink: Dictionary = _repair_fixture()
	_start(sink)
	var receipt: Dictionary = sink.vehicle.naval.repair.duplicate(true)
	var sink_station: Dictionary = Runtime.ship_repair_work_slots(sink.data, sink.vehicle)[0]
	assert(Runtime.advance_ship_repair_work(sink.data, "1", float(receipt.total_work) * 0.25, sink.data.cell_from_index(int(sink_station.cell)), int(sink_station.slot), 1).ok)
	assert(Runtime.damage_ship_vehicle(sink.data, "1", 100000.0).ok)
	assert(sink.vehicle.naval.repair.is_empty(), "Fatal damage settles accrued materials atomically before strict same-frame persistence")
	assert(Runtime.settle_ship_repair_damage(sink.data, "1").ok)
	assert(sink.vehicle.naval.repair.is_empty() and float(sink.vehicle.naval.hp) == 0.0)
	for resource: String in receipt.paid_cost: assert(int(sink.vehicle.cargo.get(resource, 0)) == floori(float(receipt.paid_cost[resource]) * 0.75), "Sink keeps unused materials physically on the original wreck")
	var before: PackedByteArray = var_to_bytes(sink.data.site)
	assert(not Runtime.request_ship_repair(sink.data, "1", sink.feature_id, 1, false, _q(sink.data)).ok and var_to_bytes(sink.data.site) == before)
	assert(Runtime.settle_ship_repair_damage(sink.data, "1").ok and var_to_bytes(sink.data.site) == before, "Repeated settlement never charges twice")

func _natural_repair_fixture() -> Dictionary:
	# Full Store roundtrip uses an unchanged generated water/soil source. The
	# three isolated material/receipt tests keep their original controlled plot.
	for seed_value: int in [17, 12345, 98761, 76404]:
		var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.COASTAL_CLIFF, seed_value, {"max_height": 1})
		Env.initialize(data, "ship_repair_natural_%d" % seed_value)
		var bodies: Dictionary = {}
		for water_id: int in data.water_body:
			if water_id >= 0: bodies[water_id] = true
		data.parameters.navigable_water_version = 1
		data.parameters.navigable_water_bodies = bodies.keys()
		data.site.capacity = 100000
		for resource: String in ["wood", "fiber", "iron", "stone", "tools"]: data.site.inventory[resource] = 10000
		assert(Runtime.initialize_item_storage(data.site).ok)
		data.site.vehicles = {}
		data.site.next_vehicle = 1
		var original_ground: PackedByteArray = var_to_bytes([data.height_levels, data.flags, data.surface_types, data.ramp_edges, data.foundation, data.water_kind, data.water_body])
		for y: int in range(4, data.size.y - 4):
			for x: int in range(4, data.size.x - 4):
				var shore: Vector2i = Vector2i(x, y)
				if not data.is_walkable(shore): continue
				for quarter: int in range(4):
					var water_facing: Vector2i = TerrainData.DIRECTIONS[quarter]
					var anchor: Vector2i = shore + water_facing
					if not data.can_navigate_water(anchor) or not data.can_water_step(anchor, anchor + water_facing): continue
					var boat_facing: Vector2i = TerrainData.DIRECTIONS[(quarter + 3) % 4]
					if not data.can_place_water_vehicle(Ships.footprint("ferry", anchor, boat_facing)): continue
					# Put the original full port edge along the original facility.
					var offsets: Array[Vector2i] = [Vector2i(3, 0), Vector2i(2, 3), Vector2i(0, 2), Vector2i.ZERO]
					var options: Dictionary = {"owner_faction": 0, "quarter": quarter, "waterfront_version": 1, "launch_cell": data.index(anchor)}
					var layout: Dictionary = Runtime.building_cells(data, "shipyard", shore - offsets[quarter], Vector2i(4, 3), options)
					if not layout.ok: continue
					var cells: Array[int] = []
					cells.assign(layout.cells)
					var preview: Dictionary = Runtime.preview_build(data, "shipyard", cells, Callable(), options)
					if not preview.ok or not preview.clearing.is_empty(): continue
					assert(data.surface_types[data.index(shore)] == TerrainData.Surface.SAND and int(data.foundation[data.index(shore)]) == 32, "The original natural sand shore admits the original waterfront build rule")
					# The rejection probe has its own generated source. It never changes
					# the natural terrain that is about to undergo full persistence.
					var inadequate: TerrainData = TerrainGenerator.generate(data.preset, data.seed_value, data.parameters)
					Env.initialize(inadequate, str(data.site.id))
					inadequate.site.inventory = data.site.inventory.duplicate()
					inadequate.foundation[data.index(shore)] = 24
					var inadequate_before: PackedByteArray = var_to_bytes(inadequate.site)
					var rejected: Dictionary = Runtime.preview_build(inadequate, "shipyard", cells, Callable(), options)
					assert(not rejected.ok and rejected.code == "TERRAIN", "Waterfront construction still rejects foundation below 25")
					assert(var_to_bytes(inadequate.site) == inadequate_before, "Insufficient waterfront foundation never spends original resources")
					var build: Dictionary = Runtime.request_build(data, "shipyard", cells, Callable(), options)
					assert(build.ok, str(build))
					var feature_id: String = str(build.feature)
					var feature: Dictionary = data.site.features[feature_id]
					var worker: Dictionary = data.site.worker
					worker.cell = int(feature.entrance)
					worker.target = "feature:" + feature_id
					worker.action = "construct"
					worker.mode = "work"
					Runtime._feature_work(data, feature_id, float(feature.work), Callable(), Callable(), null, null, Runtime.CARRY_CAPACITY, 0)
					assert(feature.stage == "complete" and feature.progress == feature.work)
					assert(Runtime.validate_feature_layout(data, feature).ok)
					assert(var_to_bytes([data.height_levels, data.flags, data.surface_types, data.ramp_edges, data.foundation, data.water_kind, data.water_body]) == original_ground, "Natural repair fixture never rewrites ground, soil or water to admit the shipyard")
					var vehicle: Dictionary = Ships.make_record("1", 1, "ferry", data.index(anchor), boat_facing)
					vehicle.naval.hp = Ships.hull_hp("ferry") * 0.5
					data.site.vehicles["1"] = vehicle
					data.site.next_vehicle = 2
					print("SITE_SHIP_REPAIR_NATURAL_SOURCE:seed=%d:quarter=%d:launch=%d:fingerprint=%s" % [seed_value, quarter, int(vehicle.cell), data.fingerprint()])
					return {"data": data, "vehicle": vehicle, "feature_id": feature_id, "ground": original_ground}
	assert(false, "No genuine generated coastline admits the original shipyard, full ferry hull and shore repair station")
	return {}

func _original_repair_worker() -> void:
	var fixture: Dictionary = _natural_repair_fixture()
	var data: TerrainData = fixture.data
	var vehicle: Dictionary = fixture.vehicle
	_start(fixture)
	var station: Dictionary = Runtime.ship_repair_work_slots(data, vehicle)[0]
	var cell: Vector2i = data.cell_from_index(int(station.cell))
	var crew_fixture: BuildingFixture.CrewFixture = BuildingFixture.CrewFixture.new()
	var captain_cell: Vector2i = Vector2i(-1, -1)
	for direction: Vector2i in TerrainData.DIRECTIONS:
		if data.can_step(cell, cell + direction): captain_cell = cell + direction; break
	assert(data.contains(captain_cell), "Original captain needs a legal shore cell adjoining the original repair station")
	var positions: Array[Vector2i] = [captain_cell, cell]
	crew_fixture.setup(root, data, positions)
	crew_fixture.army.faction_id = 0
	var identity: int = crew_fixture.army.combat_identity(1)
	var row: Dictionary = crew_fixture.army.combat_units[1]
	var holder: Dictionary = row.item_state
	var ids: Array[int] = [identity]
	assert(crew_fixture.crew.assign(crew_fixture.army, ids, crew_fixture.army.combat_identity(0)).ok)
	var result: Dictionary = crew_fixture.crew.advance(60.0)
	assert(row.work_task.target == "vehicle:1" and row.work_task.action == "repair")
	assert(is_equal_approx(float(vehicle.naval.repair.progress), 60.0))
	assert(is_equal_approx(float(result.handled_seconds[identity]), 60.0))
	assert(is_equal_approx(PersonFatigue.read(row), 1.0 / 6.0), "Original fatigue owner charges shore work once")
	assert(SiteWorkTeam.valid_task(data, data.site, row.work_task))
	var snapshot: Dictionary = bytes_to_var(var_to_bytes(data.site))
	snapshot.armies = [crew_fixture.army.capture_combat_state()]
	assert(Runtime.validate_ship_repair(data, snapshot.vehicles["1"], snapshot).ok)
	assert(Store._validate_vehicles(data, snapshot, true).ok, "Stationary original worker repair survives vehicle persistence validation")
	assert(SiteWorkTeam.valid_task(data, snapshot, snapshot.armies[0].units[1].work_task), "Original saved worker points to its legal repair station")
	var parsed_snapshot: Variant = JSON.parse_string(JSON.stringify(snapshot))
	assert(parsed_snapshot is Dictionary)
	var raw_snapshot_before: PackedByteArray = var_to_bytes(parsed_snapshot)
	assert(SiteWorkTeam.valid_task(data, parsed_snapshot, parsed_snapshot.armies[0].units[1].work_task), "Original worker and strict receipt survive raw JSON before Store normalization")
	assert(var_to_bytes(parsed_snapshot) == raw_snapshot_before, "Work reference validation preserves the complete raw snapshot")
	data.site.actors = {}
	data.site.army_trial_active = true
	data.site.army_next_team = 2
	data.site.armies = [crew_fixture.army.capture_combat_state()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHIP_REPAIR_SAVE).get_base_dir())
	var saved: Dictionary = Store.save(data, SHIP_REPAIR_SAVE)
	assert(saved.ok, str(saved))
	var loaded: Dictionary = Store.load_site(SHIP_REPAIR_SAVE)
	assert(loaded.ok, str(loaded))
	assert(var_to_bytes([loaded.data.height_levels, loaded.data.flags, loaded.data.surface_types, loaded.data.ramp_edges, loaded.data.foundation, loaded.data.water_kind, loaded.data.water_body]) == fixture.ground, "Store reconstructs the same genuine ground, soil and water source")
	assert(Runtime.validate_ship_repair(loaded.data, loaded.data.site.vehicles["1"]).ok)
	assert(SiteWorkTeam.valid_task(loaded.data, loaded.data.site, loaded.data.site.armies[0].units[1].work_task))
	assert(float(loaded.data.site.vehicles["1"].naval.repair.progress) == float(vehicle.naval.repair.progress))
	assert(loaded.data.site.vehicles["1"].cargo == vehicle.cargo, "Full save/load never duplicates or drops the original reserved cargo")
	assert(Runtime.cancel_ship_repair(data, "1", 1).ok)
	assert(row.work_task.target == "" and row.work_task.work_slot == -1)
	assert(is_same(holder, row.item_state), "No new worker/person/item owner")
	crew_fixture.close()
