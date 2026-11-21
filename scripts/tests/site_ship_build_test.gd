extends "res://scripts/tests/site_workflow_test.gd"
## P3 original feature batch, resources, worker clock, launch and cancellation.
const Ships = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
const BuildingFixture = preload("res://scripts/tests/site_building_runtime_contract_test.gd")
var run_completed := false

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 60000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not run_completed and Time.get_ticks_msec() > deadline:
		push_error("SITE SHIP BUILD did not complete")
		quit(1)
	return false

func _ship_fixture() -> TerrainData:
	var data := _fixture()
	data.site.capacity = 100000
	for resource: String in ["wood", "fiber", "iron", "stone", "tools"]: data.site.inventory[resource] = 10000
	# Source-authorized test geography, not a command that grants real water.
	data.parameters.navigable_water_version = 1
	data.parameters.navigable_water_bodies = [900]
	for y: int in range(15, 35):
		for x: int in range(15, 55):
			var index := data.index(Vector2i(x, y))
			data.surface_types[index] = TerrainData.Surface.WATER
			data.flags[index] = TerrainData.Flag.BLOCKED | TerrainData.Flag.WET
			data.water_kind[index] = 1
			data.water_body[index] = 900
	data.site.depot_cell = data.index(Vector2i(20, 45))
	data.site.worker.cell = data.index(Vector2i(19, 45))
	Env.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)
	assert(Runtime.initialize_item_storage(data.site).ok)
	data.site.vehicles = {}
	data.site.next_vehicle = 1
	return data

func _yard(data: TerrainData, x: int, launch_x: int = -1) -> String:
	var options := {"owner_faction": 0, "quarter": 0, "waterfront_version": 1,
		"launch_cell": data.index(Vector2i(x if launch_x < 0 else launch_x, 34))}
	var layout := Runtime.building_cells(data, "shipyard", Vector2i(x, 35), Vector2i(4, 3), options)
	assert(layout.ok, str(layout))
	var build := Runtime.request_build(data, "shipyard", layout.cells, Callable(), options)
	assert(build.ok, str(build))
	var key := str(build.feature)
	var feature: Dictionary = data.site.features[key]
	var worker: Dictionary = data.site.worker
	worker.cell = int(feature.entrance)
	worker.target = "feature:" + key
	worker.action = "construct"
	worker.mode = "work"
	Runtime._feature_work(data, key, float(feature.work), Callable(), Callable(), null, null, Runtime.CARRY_CAPACITY, 0)
	assert(feature.stage == "complete" and feature.progress == feature.work)
	assert(Runtime.validate_feature_layout(data, feature).ok)
	return key

func _work(data: TerrainData, key: String, seconds: float, occupied: Callable = Callable(), work_time: Callable = Callable()) -> void:
	var feature: Dictionary = data.site.features[key]
	var worker: Dictionary = data.site.worker
	worker.cell = int(feature.entrance)
	worker.target = "feature:" + key
	worker.action = "operate"
	worker.mode = "work"
	Runtime._feature_work(data, key, seconds / 60.0, occupied, work_time, null, null, Runtime.CARRY_CAPACITY, 0)

func _run() -> void:
	_launch_and_wait()
	_cancel_and_atomic_rejection()
	_recipe_and_layout_guards()
	_pause_and_clock()
	_two_yards_same_berth()
	_original_army_worker()
	TerrainArmy.release_contact_source()
	run_completed = true
	print("SITE_SHIP_BUILD_PASS")
	quit(0)

func _launch_and_wait() -> void:
	var data := _ship_fixture()
	var key := _yard(data, 25)
	var feature: Dictionary = data.site.features[key]
	var cost := Ships.build_cost("ferry")
	var original: Dictionary = data.site.inventory.duplicate()
	var before := var_to_bytes(data.site)
	assert(Runtime.begin_ship_build(data, key, "ferry", 1, 0, Callable(), true).ok)
	assert(var_to_bytes(data.site) == before, "Preview never pays, books a job or increments a vehicle ID")
	assert(Runtime.begin_ship_build(data, key, "ferry", 1, 0).ok)
	assert(Runtime.ship_build_uses_team(data, 1))
	for resource: String in cost: assert(data.site.inventory[resource] == original[resource] - cost[resource])
	assert(data.site.vehicles.is_empty() and data.site.next_vehicle == 1, "An unfinished job is not a duplicate boat")
	before = var_to_bytes(data.site)
	assert(not Runtime.begin_ship_build(data, key, "ferry", 1, 0).ok)
	assert(var_to_bytes(data.site) == before, "A duplicate order never pays twice")
	var busy := func(_cell: Vector2i) -> bool: return true
	var work := float(Ships.build_work_seconds("ferry"))
	_work(data, key, work, busy)
	assert(feature.has("ship_build") and feature.batch_paid and is_equal_approx(float(feature.production) * 60.0, work))
	assert(data.site.vehicles.is_empty() and data.site.next_vehicle == 1)
	assert(Runtime.validate_feature_layout(data, feature).ok, "Dynamic berth blockage remains a legal persistent completed batch")
	var receipt := var_to_bytes(feature.ship_build)
	var inventory := var_to_bytes(data.site.inventory)
	var work_calls := [0]
	var should_not_work := func(_manual: bool, minutes: float) -> float:
		work_calls[0] += 1
		return minutes
	_work(data, key, work, busy, should_not_work)
	Runtime.advance(data, 1.0, false, false, busy)
	assert(work_calls[0] == 0, "Waiting for a berth consumes no extra work/fatigue")
	assert(var_to_bytes(feature.ship_build) == receipt and var_to_bytes(data.site.inventory) == inventory)
	Runtime.advance(data, 1.0)
	assert(data.site.vehicles.size() == 1 and data.site.next_vehicle == 2)
	var boat: Dictionary = data.site.vehicles["1"]
	assert(boat.kind == "ship" and boat.ship_type == "ferry" and boat.team_id == 1 and boat.operator_id == 0)
	assert(boat.cargo.is_empty() and boat.holder.item_ids.is_empty())
	assert(not feature.has("ship_build") and not feature.batch_paid and feature.production == 0.0 and not Runtime.ship_build_uses_team(data, 1))
	Runtime.advance(data, 5.0)
	assert(data.site.vehicles.size() == 1 and data.site.next_vehicle == 2, "Clock retries never mint a second boat")
	boat.cargo.wood = 7
	assert(Runtime.cancel_feature(data, key, Callable(), 0).ok)
	assert(data.site.vehicles.size() == 1 and boat.cargo.wood == 7, "Demolishing the yard never deletes a launched hull or cargo")

func _cancel_and_atomic_rejection() -> void:
	var data := _ship_fixture()
	var key := _yard(data, 25)
	var original: Dictionary = data.site.inventory.duplicate()
	assert(Runtime.begin_ship_build(data, key, "river", 1, 0).ok)
	var feature: Dictionary = data.site.features[key]
	var cost := Ships.build_cost("river")
	var before := var_to_bytes(data.site)
	assert(not Runtime.cancel_feature(data, key, Callable(), 0).ok)
	assert(var_to_bytes(data.site) == before, "Paid ship work must be cancelled explicitly before facility removal")
	assert(not Runtime.cancel_ship_build(data, key, 1).ok)
	assert(var_to_bytes(data.site) == before, "An enemy cannot cancel an original paid job")
	assert(Runtime.cancel_ship_build(data, key, 0).ok)
	assert(data.site.inventory == original, "No effective work returns every original paid material")
	assert(Runtime.begin_ship_build(data, key, "river", 1, 0).ok)
	var work := float(Ships.build_work_seconds("river"))
	_work(data, key, work * 0.25)
	assert(is_equal_approx(feature.production * 60.0, work * 0.25))
	var expected := {}
	for resource: String in cost: expected[resource] = floori(float(cost[resource]) * 0.75)
	data.site.capacity = Runtime.inventory_size(data.site.inventory)
	before = var_to_bytes(data.site)
	assert(not Runtime.cancel_ship_build(data, key, 0).ok)
	assert(var_to_bytes(data.site) == before, "A full depot rejects the whole refund, keeping receipt, progress and resources")
	data.site.capacity = 100000
	before = var_to_bytes(data.site)
	var preview := Runtime.cancel_ship_build(data, key, 0, true)
	assert(preview.ok and preview.refund == expected and var_to_bytes(data.site) == before)
	var paid_inventory: Dictionary = data.site.inventory.duplicate()
	var cancelled := Runtime.cancel_ship_build(data, key, 0)
	assert(cancelled.ok and cancelled.refund == expected)
	for resource: String in cost: assert(data.site.inventory[resource] == paid_inventory[resource] + expected[resource])
	assert(not feature.has("ship_build") and not feature.batch_paid and feature.production == 0.0 and data.site.vehicles.is_empty())

func _recipe_and_layout_guards() -> void:
	var data := _ship_fixture()
	var key := _yard(data, 25)
	var feature: Dictionary = data.site.features[key]
	var before := var_to_bytes(data.site)
	assert(not Runtime.begin_ship_build(data, key, "unknown", 1, 0).ok and var_to_bytes(data.site) == before)
	for kind: String in Ships.KINDS:
		assert(not Ships.build_cost(kind).is_empty() and Ships.build_work_seconds(kind) > 0.0)
		assert(Runtime.begin_ship_build(data, key, kind, 1, 0).ok, kind)
		assert(Runtime.validate_feature_layout(data, feature).ok)
		var bad: Dictionary = feature.duplicate(true)
		bad.ship_build.recipe_version = 2
		assert(not Runtime.validate_feature_layout(data, bad).ok)
		bad = feature.duplicate(true)
		bad.ship_build.paid_cost.wood += 1
		assert(not Runtime.validate_feature_layout(data, bad).ok)
		bad = feature.duplicate(true)
		bad.production = float(bad.ship_build.total_work) / 60.0 + 1.0
		assert(not Runtime.validate_feature_layout(data, bad).ok)
		assert(Runtime.cancel_ship_build(data, key, 0).ok)
	var layout_bad: Dictionary = feature.duplicate(true)
	layout_bad.launch_cell = data.index(Vector2i(20, 20))
	assert(not Runtime.validate_feature_layout(data, layout_bad).ok)
	layout_bad = feature.duplicate(true)
	layout_bad.erase("waterfront_version")
	assert(not Runtime.validate_feature_layout(data, layout_bad).ok)
	var options := {"owner_faction": 0, "quarter": 0, "waterfront_version": 1, "launch_cell": data.index(Vector2i(40, 34))}
	var layout := Runtime.building_cells(data, "dock", Vector2i(40, 35), Vector2i(2, 2), options)
	assert(layout.ok)
	var dock := Runtime.request_build(data, "dock", layout.cells, Callable(), options)
	assert(dock.ok)
	before = var_to_bytes(data.site)
	assert(not Runtime.begin_ship_build(data, str(dock.feature), "ferry", 1, 0).ok and var_to_bytes(data.site) == before)

func _pause_and_clock() -> void:
	var data := _ship_fixture()
	var key := _yard(data, 25)
	assert(Runtime.begin_ship_build(data, key, "ferry", 1, 0).ok)
	var feature: Dictionary = data.site.features[key]
	data.site.paused = true
	var before := var_to_bytes(data.site)
	Runtime.advance(data, 10.0, true)
	Runtime.advance_ship_builds(data)
	assert(var_to_bytes(data.site) == before, "Pause freezes both original construction time and launch retries")
	data.site.paused = false
	data.site.combat_left = 1.0
	var worker: Dictionary = data.site.worker
	worker.cell = int(feature.entrance)
	worker.target = "feature:" + key
	worker.action = "operate"
	worker.mode = "work"
	var calls := [0.0]
	var effective := func(_manual: bool, minutes: float) -> float:
		calls[0] += minutes
		return minutes * 0.5
	# 1 action/combat second + 1 peaceful real second is 61 game seconds.
	Runtime.advance(data, 2.0, true, false, Callable(), effective, Callable(), Runtime.CARRY_CAPACITY, Runtime.CARRY_CAPACITY, 1.0, 0)
	assert(is_equal_approx(calls[0], 61.0 / 60.0))
	assert(is_equal_approx(float(feature.production), 61.0 / 120.0), "The original effective work callback is applied once")
	assert(data.site.vehicles.is_empty())

func _two_yards_same_berth() -> void:
	var data := _ship_fixture()
	# Distinct shoreline facilities can share a water footprint without a second
	# navigation owner. Launch must check the newly committed boat again.
	var first := _yard(data, 25)
	var second := _yard(data, 29)
	assert(Runtime.begin_ship_build(data, first, "tower", 1, 0).ok)
	assert(Runtime.begin_ship_build(data, second, "ferry", 2, 0).ok)
	var busy := func(_cell: Vector2i) -> bool: return true
	_work(data, first, Ships.build_work_seconds("tower"), busy)
	_work(data, second, Ships.build_work_seconds("ferry"), busy)
	Runtime.advance_ship_builds(data)
	assert(data.site.vehicles.size() == 1 and data.site.vehicles["1"].ship_type == "tower")
	assert(data.site.features[second].has("ship_build"), "The second overlapping launch waits without minting a boat")
	assert(Runtime.validate_feature_layout(data, data.site.features[second]).ok)
	data.site.vehicles["1"].cell = data.index(Vector2i(16, 34))
	Runtime.advance_ship_builds(data)
	assert(data.site.vehicles.size() == 2 and data.site.vehicles["2"].ship_type == "ferry")
	assert(not data.site.features[second].has("ship_build"))

func _original_army_worker() -> void:
	var data := _ship_fixture()
	var key := _yard(data, 25)
	assert(Runtime.begin_ship_build(data, key, "ferry", 1, 0).ok)
	var feature: Dictionary = data.site.features[key]
	# Reuse the original building/siege fixture's real Army and WorkTeam.
	var fixture := BuildingFixture.CrewFixture.new()
	var entry := data.cell_from_index(int(feature.entrance))
	var positions: Array[Vector2i] = [entry + Vector2i.DOWN, entry]
	fixture.setup(root, data, positions)
	fixture.army.faction_id = 0
	var worker_id := fixture.army.combat_identity(1)
	var row: Dictionary = fixture.army.combat_units[1]
	var original_row: Dictionary = row
	var original_holder: Dictionary = row.item_state
	var ids: Array[int] = [worker_id]
	assert(fixture.crew.assign(fixture.army, ids, fixture.army.combat_identity(0)).ok)
	var result := fixture.crew.advance(60.0)
	assert(result.handled_seconds.size() == 1 and is_equal_approx(float(result.handled_seconds[worker_id]), 60.0))
	assert(is_equal_approx(float(feature.production), 1.0), "A real original Army worker advances the paid feature batch")
	assert(row.work_task.target == "feature:" + key and row.work_task.action == "operate")
	assert(SiteWorkTeam.valid_task(data, data.site, row.work_task))
	assert(is_equal_approx(PersonFatigue.read(row), 1.0 / 6.0), "Original worker fatigue is updated once")
	feature.production = float(feature.ship_build.total_work) / 60.0 - 1.0 / 60.0
	result = fixture.crew.advance(10.0)
	assert(data.site.vehicles.size() == 1 and not feature.has("ship_build"))
	assert(row.work_task.target == "" and row.work_task.work_slot == -1, "Launch clears the original saved worker reference in the same slice")
	assert(float(result.handled_seconds[worker_id]) <= 1.0 + 0.000001, "The completion slice only charges remaining effective work")
	assert(is_same(row, original_row) and is_same(row.item_state, original_holder))
	fixture.close()
