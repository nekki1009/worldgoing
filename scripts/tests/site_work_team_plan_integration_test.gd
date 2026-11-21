extends SceneTree

# Actual original Army / Runtime / WorkTeam consumption, separate from the pure
# mathematical contract. This fixture does not claim TerrainLab/native closure.
var checks := 0
var failures := 0

class Fixture extends RefCounted:
	var terrain: TerrainData
	var army := TerrainArmy.new()
	var combat_armies: Array[TerrainArmy] = []
	var combat_actors: Array[TerrainTestCharacter] = []
	var crew := SiteWorkTeam.new()
	var threatened := false
	func setup(tree_root: Node, data: TerrainData, positions: Array[Vector2i]) -> void:
		terrain = data
		tree_root.add_child(army)
		army.set_process(false)
		army.team_id = 1
		army.faction_id = 1
		army.roster_size = positions.size()
		assert(army.deploy_at(terrain, null, null, positions))
		assert(army.enable_combat(false))
		army.exchange_enabled = true
		army.sync_shared_fatigue(true)
		combat_armies.append(army)
		for row: Dictionary in army.combat_units:
			row["cargo"] = {}
			row["item_state"] = SiteRuntime.new_item_state("person:" + str(row.person_id))
			row["work_resting"] = false
		crew.init(self)
	func _combat_target(identity: int) -> Dictionary:
		var index := army.index_for_identity(identity)
		return {"owner": army, "unit": index, "cell": army.cells[index], "hp": army.combat_units[index].hp} if index >= 0 else {}
	func _fatigue_threat(_cell: Vector2i, _faction: int, _owner: Variant, _unit: int, _candidates: Dictionary) -> bool:
		return threatened
	func controlled_person_id() -> int:
		return -1
	func ids() -> Array[int]:
		return [army.combat_identity(1), army.combat_identity(2)]
	func close() -> void:
		# These call-local witnesses include occupancy callables bound to crew.
		# Drop the fixture's last interval before releasing its original owners.
		crew._prepared_work.clear()
		crew._prepared_ladders.clear()
		crew._prepared_retry.clear()
		crew.lab = null
		army.free()

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String, detail: Variant = "") -> bool:
	checks += 1
	if not condition:
		failures += 1
		push_error(message + " " + str(detail))
	return condition

func _near(actual: float, expected: float, message: String) -> bool:
	return _check(is_finite(actual) and absf(actual - expected) < 0.0000001, message, [actual, expected])

func _run() -> void:
	create_timer(35.0).timeout.connect(func() -> void: quit(1))
	_shared_weighted_batch()
	_material_quota_and_guards()
	_external_quota_water()
	_retry_and_retime()
	TerrainArmy.release_contact_source()
	print("SITE_WORK_TEAM_PLAN_INTEGRATION_" + ("PASS" if failures == 0 else "FAIL") + ": " + str(checks) + " checks; actual Army shared pool, real Runtime stations/materials, weighted batch, short completion/no second batch, preflight and consume guards, start-only retry and one consume; no Lab/native/UI/save/performance claim")
	quit(0 if failures == 0 else 1)

func _data() -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(72, 72))
	data.spawn_cell = Vector2i(3, 3)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	SiteEnvironment.initialize(data, "work-team-plan-owner")
	data.resource_base.clear()
	data.site.changes.clear()
	data.height_levels.fill(0)
	data.ramp_edges.fill(0)
	data.water_kind.fill(0)
	data.water_body.fill(-1)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.foundation.fill(80)
	data.fertility.fill(60)
	data.moisture.fill(70)
	data.groundwater.fill(80)
	data.drainage.fill(70)
	data.site.depot_cell = data.index(Vector2i(3, 3))
	for item: String in SiteEnvironment.ITEM_NAMES: data.site.inventory[item] = 1000
	data.site.capacity = 100000
	assert(SiteRuntime.initialize_item_storage(data.site).ok)
	SiteEnvironment.rebuild_indexes(data)
	return data

func _build(data: TerrainData, kind: String, anchor: Vector2i, size: Vector2i = Vector2i.ONE) -> String:
	var options := {"owner_faction": 1}
	var layout := SiteRuntime.building_cells(data, kind, anchor, size, options)
	assert(layout.ok, str(layout))
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var created := SiteRuntime.request_build(data, kind, cells, Callable(), options)
	assert(created.ok, str(created))
	var key := str(created.feature)
	var feature: Dictionary = data.site.features[key]
	var task := {"version": 2, "zone": -1, "target": "feature:" + key, "action": "construct", "work_cell": int(feature.entrance), "cell": int(feature.entrance), "work_slot": -1, "mode": "work", "progress": 0.0, "status": ""}
	SiteRuntime._feature_work(data, key, float(feature.work), Callable(), Callable(), task, {}, 20, 1)
	assert(str(feature.stage) == "complete", str(task))
	return key

func _farm_fixture() -> Dictionary:
	var data := _data()
	var key := _build(data, "farm", Vector2i(10, 40), Vector2i(12, 6))
	_build(data, "well", Vector2i(8, 42))
	_build(data, "well", Vector2i(24, 42))
	assert(SiteRuntime.operate_feature(data, key).ok)
	var slots := SiteRuntime.feature_work_slots(data, data.site.features[key])
	assert(slots.size() == 2)
	for index: int in slots[0].service_cells: data.fertility[index] = 30
	for index: int in slots[1].service_cells: data.fertility[index] = 90
	var fixture := Fixture.new()
	fixture.setup(root, data, [Vector2i(7, 40), data.cell_from_index(int(slots[0].cell)), data.cell_from_index(int(slots[1].cell))])
	assert(fixture.crew.assign(fixture.army, fixture.ids(), fixture.army.combat_identity(0)).ok)
	return {"fixture": fixture, "key": key, "feature": data.site.features[key]}

func _commit_original_pool(fixture: Fixture, plan: Dictionary) -> void:
	# The fixture supplies the collector's ONE publication to the actual Army
	# pool; WorkTeam must consume the allocation without any additional charge.
	for group: Dictionary in plan.pools:
		assert(is_same(group.original_pool, fixture.army.team_fatigue))
		var original: Dictionary = group.original_pool
		original.fatigue = float(group.fatigue)
		original.fatigue_rest = float(group.fatigue_rest)
		original.active = float(group.effort_seconds) > 0.0

func _shared_weighted_batch() -> void:
	var setup := _farm_fixture()
	var fixture: Fixture = setup.fixture
	var feature: Dictionary = setup.feature
	var ids := fixture.ids()
	var first: Dictionary = fixture.army.combat_units[1]
	var second: Dictionary = fixture.army.combat_units[2]
	var pool: Dictionary = fixture.army.team_fatigue
	pool.fatigue = 40.0
	pool.fatigue_rest = 12.0
	var seeds := int(fixture.terrain.site.inventory.seeds)
	var cargo: Dictionary = first.cargo
	var requests := fixture.crew.prepare_work_requests(60.0, 1.0)
	if not _check(requests.size() == 1 and requests[0].productive_kind == "sum" and requests[0].participants.size() == 2, "True two-station farm produces one original shared request", requests): fixture.close(); return
	_check(is_same(first._fatigue_pool, pool) and is_same(second._fatigue_pool, pool) and int(pool.count) == 3, "Both original workers and original commander borrow one original Army pool")
	_near(float(requests[0].participants[0].progress_multiplier), 18.0, "First actual station has 36 cells at fertility 30")
	_near(float(requests[0].participants[1].progress_multiplier), 54.0, "Second actual station has 36 cells at fertility 90")
	_check(not feature.batch_paid and float(feature.production) == 0.0 and int(fixture.terrain.site.inventory.seeds) == seeds, "Prepare does not prepay or progress")
	_near(float(pool.fatigue), 40.0, "Prepare does not charge original fatigue")
	var plan := PersonFatigue.plan_work_interval(requests, 60.0)
	if not _check(bool(plan.ok), "True original-body full-pool plan is legal", plan): fixture.close(); return
	var job: Dictionary = plan.jobs.work_team[requests[0].key]
	var rate := 2.0 * PersonFatigue.WORK_RATE / 3.0
	var base := PersonFatigue.work_seconds(40.0, 60.0, rate)
	_near(float(job.participant_effective_seconds[ids[0]]), base, "First receives base integral before station weight")
	_near(float(job.participant_effective_seconds[ids[1]]), base, "Second receives same base integral from the real shared pool")
	_commit_original_pool(fixture, plan)
	var admitted := float(pool.fatigue)
	var consumed := fixture.crew.advance(60.0, plan)
	_check(consumed.handled_seconds.size() == 2 and consumed.handled_seconds[ids[0]] == 60.0 and consumed.handled_seconds[ids[1]] == 60.0, "True owner records both participants' actual seconds", consumed)
	_near(float(feature.production), base * 72.0 / 60.0, "Runtime applies each physical station weight exactly once")
	_check(bool(feature.batch_paid) and int(fixture.terrain.site.inventory.seeds) == seeds - 1, "Two work stations prepay one original batch")
	_check(is_same(first.cargo, cargo), "Original cargo identity is preserved")
	# 技能 K1a: each worker's effective seconds train farming, pending until the day's settlement.
	_check(int(first.get("skills", {}).get("pending", {}).get("farming", 0)) == roundi(base * 1000000.0) and int(second.get("skills", {}).get("pending", {}).get("farming", 0)) == roundi(base * 1000000.0), "Both farm workers' effective seconds train farming", [first.get("skills"), second.get("skills"), base])
	_near(float(pool.fatigue), admitted, "Plan consumer does not charge fatigue again")
	var produced := float(feature.production)
	_check(fixture.crew.advance(60.0, plan).handled_seconds.is_empty(), "Same accepted allocation cannot be consumed twice")
	_near(float(feature.production), produced, "Duplicate consume cannot progress")
	# This batch was actually paid above. Move its original progress close to
	# the real recipe endpoint to exercise clipping without another setup clock.
	feature.production = float(SiteRuntime.feature_recipe(feature).cycle) - 1.0
	requests = fixture.crew.prepare_work_requests(60.0, 1.0)
	plan = PersonFatigue.plan_work_interval(requests, 60.0)
	if not _check(bool(plan.ok) and requests.size() == 1, "Nearly completed original paid batch prepares once", plan): fixture.close(); return
	job = plan.jobs.work_team[requests[0].key]
	var endpoint := float(job.actual_seconds)
	if not _check(endpoint > 0.0 and endpoint < 60.0, "Shared completion has a true short endpoint", endpoint): fixture.close(); return
	_check(fixture.crew.retime_prepared_interval(endpoint, endpoint / 60.0).ok, "Prepared original work retimes without another selection")
	plan = PersonFatigue.plan_work_interval(requests, endpoint)
	_commit_original_pool(fixture, plan)
	admitted = float(pool.fatigue)
	consumed = fixture.crew.advance(endpoint, plan)
	_check(consumed.handled_seconds.size() == 2, "Short prefix is consumed by both original participants")
	_check(int(first.cargo.get("grain", 0)) + int(second.cargo.get("grain", 0)) == 8, "Only one real batch output is collected")
	_check(not feature.batch_paid and absf(float(feature.production)) < 0.0000001 and int(fixture.terrain.site.inventory.seeds) == seeds - 1, "Completion cannot pay or work a future batch in this prepared interval", feature)
	_near(float(pool.fatigue), admitted, "Completion consumption adds no duplicate fatigue")
	_check(not fixture.crew.retime_prepared_interval(endpoint / 2.0, endpoint / 120.0).ok, "Consumed interval refuses retime")
	fixture.close()

func _material_quota_and_guards() -> void:
	var setup := _farm_fixture()
	var fixture: Fixture = setup.fixture
	var feature: Dictionary = setup.feature
	fixture.terrain.site.inventory.tools = 0
	var before: Dictionary = fixture.terrain.site.inventory.duplicate(true)
	var requests := fixture.crew.prepare_work_requests(60.0, 1.0)
	_check(requests.is_empty(), "Missing original tools admits zero work requests")
	var plan := PersonFatigue.plan_work_interval(requests, 60.0)
	_check(fixture.crew.advance(60.0, plan).handled_seconds.is_empty(), "Missing-tools original consume admits zero effort")
	_check(not feature.batch_paid and float(feature.production) == 0.0 and fixture.terrain.site.inventory == before, "Guard refuses before real materials/progress")
	_near(float(fixture.army.team_fatigue.fatigue), 0.0, "Rejected preflight does not charge shared pool")
	fixture.terrain.site.inventory.tools = 4
	requests = fixture.crew.prepare_work_requests(60.0, 1.0)
	plan = PersonFatigue.plan_work_interval(requests, 60.0)
	if not _check(bool(plan.ok) and not requests.is_empty(), "Original tools restored; fresh plan can prepare", plan): fixture.close(); return
	fixture.threatened = true
	_check(fixture.crew.advance(60.0, plan).handled_seconds.is_empty(), "Post-prepare actual threat is rechecked before work_time")
	_check(not feature.batch_paid and float(feature.production) == 0.0, "Threat changes consume no original materials/progress")
	fixture.close()
	# Two DISTINCT unpaid features share ONE original stock. Sorted original
	# person IDs reserve its one seed in a transient ledger without spending it.
	var data := _data()
	var left := _build(data, "farm", Vector2i(10, 40), Vector2i(6, 6))
	var right := _build(data, "farm", Vector2i(30, 40), Vector2i(6, 6))
	_build(data, "well", Vector2i(8, 42))
	_build(data, "well", Vector2i(28, 42))
	assert(SiteRuntime.operate_feature(data, left).ok and SiteRuntime.operate_feature(data, right).ok)
	var left_slots := SiteRuntime.feature_work_slots(data, data.site.features[left])
	var right_slots := SiteRuntime.feature_work_slots(data, data.site.features[right])
	fixture = Fixture.new()
	fixture.setup(root, data, [Vector2i(7, 40), data.cell_from_index(int(left_slots[0].cell)), data.cell_from_index(int(right_slots[0].cell))])
	assert(fixture.crew.assign(fixture.army, fixture.ids(), fixture.army.combat_identity(0)).ok)
	data.site.inventory.seeds = 1
	requests = fixture.crew.prepare_work_requests(1.0, 1.0 / 60.0)
	if not _check(requests.size() == 1, "One original seed admits one of two distinct unpaid batches", requests): fixture.close(); return
	_check(int(data.site.inventory.seeds) == 1 and is_same(requests[0].payment_source, data.site.inventory), "Material reservation is read-only and retains exact original source")
	plan = PersonFatigue.plan_work_interval(requests, 1.0)
	_commit_original_pool(fixture, plan)
	var result := fixture.crew.advance(1.0, plan)
	_check(result.handled_seconds.size() == 1 and int(data.site.inventory.seeds) == 0, "Only actually admitted original worker consumes one seed/effort", result)
	var paid := int(bool(data.site.features[left].batch_paid)) + int(bool(data.site.features[right].batch_paid))
	_check(paid == 1, "Distinct feature quota cannot prepay both batches")
	fixture.close()

func _external_quota_water() -> void:
	var data := _data()
	var left := _build(data, "farm", Vector2i(10, 40), Vector2i(6, 6))
	var right := _build(data, "farm", Vector2i(16, 40), Vector2i(6, 6))
	_build(data, "well", Vector2i(14, 38)) # One real two-unit water budget serves both slots.
	assert(SiteRuntime.operate_feature(data, left).ok and SiteRuntime.operate_feature(data, right).ok)
	var left_slots := SiteRuntime.feature_work_slots(data, data.site.features[left])
	var right_slots := SiteRuntime.feature_work_slots(data, data.site.features[right])
	var fixture := Fixture.new()
	fixture.setup(root, data, [Vector2i(7, 40), data.cell_from_index(int(left_slots[0].cell)), data.cell_from_index(int(right_slots[0].cell))])
	assert(fixture.crew.assign(fixture.army, fixture.ids(), fixture.army.combat_identity(0)).ok)
	var requests := fixture.crew.prepare_work_requests(1.0, 1.0 / 60.0)
	if not _check(requests.size() == 2, "Original scarce-water start still admits both real held work groups", requests): fixture.close(); return
	var denied: Dictionary = {}
	var admitted: Dictionary = {}
	for request: Dictionary in requests:
		if str(request.key) == "feature:" + left + ":operate": denied = request
		if str(request.key) == "feature:" + right + ":operate": admitted = request
	if not _check(not denied.is_empty() and not admitted.is_empty(), "Both prepared original feature IDs remain held", requests): fixture.close(); return
	var original_task: Dictionary = fixture.army.combat_units[2].work_task
	var before_weight := float(admitted.participants[0].progress_multiplier)
	_check(before_weight > 0.0 and before_weight < 36.0, "Second slot initially shares the real limited water budget", before_weight)
	denied["paused"] = "MATERIALS" # Actual external all-provider ledger decision.
	var refreshed := fixture.crew.apply_shared_preflight(requests)
	_check(refreshed.size() == requests.size() and is_same(refreshed[0], requests[0]), "Refresh preserves the same held request objects")
	_near(float(admitted.participants[0].progress_multiplier), 36.0, "Quota-rejected slot releases water before the plan")
	_check(int(SiteRuntime.feature_production_info(data, left).workers) == 0 and int(SiteRuntime.feature_production_info(data, right).workers) == 1, "Only admitted WorkTeam slot remains in the original water projection")
	_check(is_same(fixture.army.combat_units[2].work_task, original_task) and float(data.site.features[right].production) == 0.0 and not data.site.features[right].batch_paid, "Refresh does not select, progress or pay original tasks")
	_near(float(fixture.army.team_fatigue.fatigue), 0.0, "Shared preflight writes no original fatigue")
	# The actual optional camp worker can independently retain this service
	# slot. Its exact original task is an admission sideband, never a new worker.
	var camp: Dictionary = data.site.worker
	camp.merge({"target": "feature:" + left, "action": "operate", "work_slot": 0, "work_cell": int(left_slots[0].cell), "cell": int(left_slots[0].cell), "mode": "work"}, true)
	var camp_request := {"provider": "runtime", "key": "worker", "task": camp, "paused": ""}
	var all_requests: Array = requests.duplicate()
	all_requests.append(camp_request)
	fixture.crew.apply_shared_preflight(all_requests)
	_check(is_same(data.get_meta(&"site_camp_operating_task", {}), camp) and int(SiteRuntime.feature_production_info(data, left).workers) == 1, "True admitted camp task keeps its own original water slot")
	_near(float(admitted.participants[0].progress_multiplier), before_weight, "Camp's legitimate water use remains in the same admission calculation")
	camp_request.paused = "MATERIALS"
	fixture.crew.apply_shared_preflight(all_requests)
	_check(data.get_meta(&"site_camp_operating_task", {}).is_empty() and int(SiteRuntime.feature_production_info(data, left).workers) == 0, "Quota-rejected camp task also releases its original slot")
	_near(float(admitted.participants[0].progress_multiplier), 36.0, "Final accepted productivity is restored before fatigue planning")
	var seeds := int(data.site.inventory.seeds)
	var plan := PersonFatigue.plan_work_interval(requests, 1.0)
	if not _check(bool(plan.ok), "Final material/water admission produces a valid pure plan", plan): fixture.close(); return
	_check(str(plan.jobs.work_team[denied.key].paused) == "MATERIALS" and float(plan.jobs.work_team[denied.key].actual_seconds) == 0.0, "Denied held group retains explicit zero-effort materials pause")
	_commit_original_pool(fixture, plan)
	var fatigue := float(fixture.army.team_fatigue.fatigue)
	var result := fixture.crew.advance(1.0, plan)
	_check(result.handled_seconds.size() == 1 and result.handled_seconds.has(fixture.ids()[1]), "Only final admitted real worker consumes effort", result)
	_near(float(data.site.features[right].production), 0.6, "Consume uses final one-second/36-cell rate without later dilution")
	_check(not data.site.features[left].batch_paid and float(data.site.features[left].production) == 0.0 and int(data.site.inventory.seeds) == seeds - 1, "Quota-rejected group consumes no stock/progress; admitted group pays once")
	_near(float(fixture.army.team_fatigue.fatigue), fatigue, "Water refresh and owner consume do not double-charge fatigue")
	fixture.close()

func _retry_and_retime() -> void:
	var data := _data()
	var cell := data.index(Vector2i(12, 9))
	data.resource_base["retry_timber"] = {"kind": SiteEnvironment.Kind.TIMBER, "cell": cell, "cells": [cell], "capacity": 4, "variant": 0, "water": -1, "blocks": true, "recover": 0}
	SiteEnvironment.rebuild_indexes(data)
	assert(SiteRuntime.add_zone(data, Rect2i(11, 8, 3, 4), SiteEnvironment.Kind.TIMBER).ok)
	var fixture := Fixture.new()
	fixture.setup(root, data, [Vector2i(10, 10), Vector2i(12, 10), Vector2i(20, 10)])
	var identity := fixture.ids()[0]
	assert(fixture.crew.assign(fixture.army, [identity], fixture.army.combat_identity(0)).ok)
	var row: Dictionary = fixture.army.combat_units[1]
	var task: Dictionary = row.work_task
	fixture.crew._retry_left[identity] = 30.0
	_near(fixture.crew.next_work_event_seconds(), 30.0, "Original pending retry is a pre-prepare endpoint")
	var requests := fixture.crew.prepare_work_requests(60.0, 1.0)
	_check(requests.is_empty() and str(task.target).is_empty() and fixture.army.moving_to[1] == TerrainArmy.INVALID_CELL, "Large prepare cannot select or move a future retry")
	_near(float(fixture.crew._retry_left[identity]), 30.0, "Preparation does not decrement retry")
	_near(fixture.crew.prepared_retry_endpoint(), 30.0, "Same prepared retry retains original endpoint")
	_check(not fixture.crew.retime_prepared_interval(61.0, 61.0 / 60.0).ok, "Retime refuses enlargement")
	_check(not fixture.crew.retime_prepared_interval(1.0, 1.0).ok, "Retime refuses changed game/action ratio")
	_check(fixture.crew.retime_prepared_interval(1.0, 1.0 / 60.0).ok, "Proportional clipping is accepted")
	_check(is_same(row.work_task, task) and str(task.target).is_empty(), "Retime preserves original task identity and selection")
	var plan := PersonFatigue.plan_work_interval(requests, 1.0)
	_check(fixture.crew.advance(1.0, plan).handled_seconds.is_empty(), "Retry waiting consumes zero productive/effort seconds")
	_near(float(fixture.crew._retry_left[identity]), 29.0, "Only accepted short elapsed decrements original retry")
	fixture.crew.advance(1.0, plan)
	_near(float(fixture.crew._retry_left[identity]), 29.0, "Duplicate consumption cannot decrement again")
	requests = fixture.crew.prepare_work_requests(29.0, 29.0 / 60.0)
	_check(requests.is_empty(), "Retry expiry is an endpoint, not work at interval start")
	plan = PersonFatigue.plan_work_interval(requests, 29.0)
	fixture.crew.advance(29.0, plan)
	_near(float(fixture.crew._retry_left[identity]), 0.0, "True endpoint reaches zero once")
	requests = fixture.crew.prepare_work_requests(1.0, 1.0 / 60.0)
	_check(requests.size() == 1 and str(task.target) == "retry_timber", "Original selector can choose in the next interval at true retry expiry", requests)
	_near(float(task.progress), 0.0, "Selection preparation still grants no work")
	_near(float(fixture.army.team_fatigue.fatigue), 0.0, "Waiting and selection grant no fatigue")
	fixture.crew.cancel(identity)
	data.site.zones.clear()
	assert(fixture.crew.assign(fixture.army, [identity], fixture.army.combat_identity(0)).ok)
	requests = fixture.crew.prepare_work_requests(60.0, 1.0)
	_check(requests.is_empty(), "No original target admits zero work")
	_near(fixture.crew.prepared_retry_endpoint(), 30.0, "Prepare's new failed selection establishes a positive retry endpoint")
	_check(fixture.crew.retime_prepared_interval(1.0, 1.0 / 60.0).ok, "New retry can clip without selecting twice")
	plan = PersonFatigue.plan_work_interval(requests, 1.0)
	fixture.crew.advance(1.0, plan)
	_near(float(fixture.crew._retry_left[identity]), 29.0, "New failed retry consumes only its accepted waiting prefix")
	fixture.close()
