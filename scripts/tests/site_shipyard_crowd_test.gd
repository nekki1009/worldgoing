extends SceneTree
## G2: crowd shipyard ferry batches on a generated coastal map.
## A completed shipyard is built on the natural shore, crowd workers run a paid ferry batch to launch,
## a second batch is cancelled with its unused fraction refunded, and a third batch is saved and
## reloaded mid-batch, keeps its paid cost and total work, and launches after the load.
## Run: --crowd --crowd-test <run_id>. Fails fast: every check quits non-zero at the first failure.
const DT := 1.0 / 30.0

const WORK_TICKS := 4000
const WALK_TICKS := 2400
const SEEDS := [17, 12345, 98761, 76404]
const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Ships = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
var lab: TerrainLab
var checks := 0
var owner: Variant = null
var members: Array[int] = []
var dock: Dictionary = {}
var yard_key := ""
var workers: Array[int] = []
var commander_identity := -1

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String, details: Variant = null) -> bool:
	checks += 1
	print("G2 SHIPYARD ", "OK " if ok else "FAIL ", checks, ": ", label, " ", details)
	if not ok:
		printerr("GATE FAIL: ", label)
		quit(1)
	return ok

# One real frame: TerrainLab._process runs the native shared work window, the crowd step, the site clock
# (work teams and ship builds) and settlement, exactly as in play. A real second of DT is DT * 60 game seconds
# at zero combat time (SiteRuntime.game_seconds). Returns false when the original step latched a fault.
func _tick(count: int) -> bool:
	for step in range(count):
		lab._process(DT)
		lab.site_controller.person_actions.settle_after_contacts()
		if not lab.site_controller._original_step_fault.is_empty():
			printerr("G2 SHIPYARD latched frame fault: ", lab.site_controller._original_step_fault)
			return false
	return true

func _feature() -> Dictionary:
	return lab.terrain.site.features.get(yard_key, {})

func _vehicle_ids() -> Array:
	var keys: Array = lab.terrain.site.get("vehicles", {}).keys()
	keys.sort()
	return keys

func _new_vehicle_id(before: Array) -> String:
	for key: Variant in _vehicle_ids():
		if not before.has(key): return str(key)
	return ""

func _materials() -> Dictionary:
	var result := {}
	for resource: String in Ships.build_cost("ferry"): result[resource] = int(lab.terrain.site.inventory.get(resource, 0))
	return result

# Each worker's native controlled step as its mode (controlled_step_state [mode, goal]); -1 when unavailable.
# The native save refuses any mode >= 3 (World::save, state.cpp:219).
func _step_modes() -> Array:
	var modes: Array = []
	for identity: int in workers:
		var index: int = owner.index_for_identity(identity)
		var state: PackedInt64Array = lab.crowd_site.crowd.controlled_step_state(index)
		modes.append(int(state[0]) if state.size() == 2 else -1)
	return modes

# Ticks real frames until every worker holds no step at or above mode 3, or the bound passes.
func _steps_settled() -> bool:
	for tick in range(WALK_TICKS):
		var settled := true
		for mode: int in _step_modes():
			if mode < 0 or mode >= 3: settled = false
		if settled: return true
		if not _tick(1): return false
	return false

# Ticks real frames until the paid batch has progress (the crowd workers have walked in and worked), or the bound passes.
func _wait_progress(limit: int) -> bool:
	for tick in range(limit):
		if float(_feature().get("production", 0.0)) > 0.0: return true
		if not _tick(1): return false
	return float(_feature().get("production", 0.0)) > 0.0

# Runs crowd work until the paid batch leaves the feature and one more vehicle exists.
func _finish_batch(ships_before: int) -> bool:
	for tick in range(WORK_TICKS):
		if not _feature().has("ship_build"): break
		if not _tick(1): return false
	return not _feature().has("ship_build") and lab.terrain.site.vehicles.size() == ships_before + 1

# Generates a coastal Site per seed, binds it, deploys two crowd teams and picks the dock nearest the first owner.
# Same generator and dock search as site_ship_crowd_reload_test.
func _prepare() -> Dictionary:
	var last: Dictionary = {"ok": false, "message": "no seed produced a crowd deployment with a natural dock"}
	for seed_value: int in SEEDS:
		owner = null
		members = []
		dock = {}
		var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.COASTAL_CLIFF, seed_value, {"max_height": 1})
		Env.initialize(data, "crowd_shipyard_%d" % seed_value)
		var bodies := {}
		for identity: int in data.water_body:
			if identity >= 0: bodies[identity] = true
		data.parameters.navigable_water_version = 1
		data.parameters.navigable_water_bodies = bodies.keys()
		lab.bind_terrain(data)
		lab.site_controller.set_process(false)
		lab.site_controller._auto_save_blocked = true
		var deployed: Dictionary = lab.deploy_trial_armies([
			{"faction": 0, "count": 8, "role": "logistics", "attack": false, "ai_enabled": false, "entry": "west"},
			{"faction": 1, "count": 8, "attack": false, "ai_enabled": false, "entry": "east"}])
		last = deployed
		if not deployed.ok or lab.crowd_site == null or not lab.crowd_site.active: continue
		for candidate: Variant in lab.crowd_site.person_owners():
			if not (candidate is CrowdPersonOwner) or not candidate.has_army(): continue
			var found: Array[int] = _non_actor_members(candidate)
			if found.size() < 3: continue
			owner = candidate
			members = found
			break
		if owner == null: continue
		var near: Vector2i = owner.person(members[0], false).cell
		var found_dock: Dictionary = _find_dock(data, near)
		if found_dock.is_empty(): continue
		dock = found_dock
		# Shipyard materials and storage are the test's own paid stock (site_ship_build_test._ship_fixture).
		data.site.capacity = 100000
		for resource: String in ["wood", "fiber", "iron", "stone", "tools"]: data.site.inventory[resource] = 10000
		var built: String = _build_yard(data, int(owner.faction_id))
		if built == "":
			last = {"ok": false, "message": "seed %d: no shipyard fits the launch rules: %s" % [seed_value, yard_reason]}
			continue
		yard_key = built
		return {"ok": true, "seed": seed_value}
	return last

# Non-Actor roster members of a crowd owner. Actors (player/NPC) cannot board or be assigned here.
func _non_actor_members(candidate: Variant) -> Array[int]:
	var result: Array[int] = []
	var all: Array = candidate.command_members()
	for member: int in all:
		if lab.crowd_site._actor(candidate.combat_identity(member)) == null: result.append(member)
	return result

# The natural dock nearest to near: a water anchor that fits a ferry with a free four-cell shore cluster.
func _find_dock(data: TerrainData, near: Vector2i) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for y in range(4, data.size.y - 4):
		for x in range(4, data.size.x - 4):
			var anchor := Vector2i(x, y)
			var distance := float(anchor.distance_to(near))
			if distance >= best_distance or not data.can_navigate_water(anchor): continue
			for facing: Vector2i in TerrainData.DIRECTIONS:
				if not data.can_place_water_vehicle(Ships.footprint("ferry", anchor, facing)): continue
				for shore: Vector2i in Ships.boarding_cells("ferry", anchor, facing):
					if not data.is_walkable(shore) or absi(data.effective_height(shore) - data.effective_height(anchor)) > 1: continue
					var cells: Array[Vector2i] = _shore_cluster(data, shore)
					if cells.size() == 4:
						best = {"anchor": anchor, "facing": facing, "shore": shore, "cells": cells}
						best_distance = distance
						break
	return best

# Walkable land cells connected to shore, with no Actor and no crowd soldier standing on them.
func _shore_cluster(data: TerrainData, shore: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var pending: Array[Vector2i] = [shore]
	var seen := {shore: true}
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_front()
		if lab.character.occupies_cell(cell) or lab.npc.occupies_cell(cell) or lab.crowd_site.reserves_cell(cell): continue
		result.append(cell)
		if result.size() == 4: return result
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if not seen.has(next) and data.can_step(cell, next) and next.distance_to(shore) <= 5.0:
				seen[next] = true
				pending.append(next)
	return []

# Places one completed shipyard that the real launch rules accept. Rules (site_runtime.gd):
# quarter q gives facing DIRECTIONS[q]; the launch cell is a navigable water anchor; the shore cell
# anchor - facing must be a footprint cell of the yard, walkable and within one height step (validate_waterfront);
# the ferry must fit at the launch cell and the cell ahead (_ship_launch_query). The candidate is probed with the
# real _ship_launch_query on a stub feature before any build. Returns "" and sets yard_reason if none fits.
var yard_reason := ""

func _build_yard(data: TerrainData, faction: int) -> String:
	yard_reason = "no water anchor near the dock passes the ferry launch query"
	var center: Vector2i = dock.anchor
	for radius in range(0, 9):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius: continue
				var anchor := center + Vector2i(dx, dy)
				if not data.contains(anchor) or not data.can_navigate_water(anchor): continue
				for quarter in range(4):
					var facing: Vector2i = TerrainData.DIRECTIONS[quarter]
					var shore := anchor - facing
					if not data.contains(shore): continue
					var stub := {"kind": "shipyard", "waterfront_version": 1, "launch_cell": data.index(anchor), "quarter": quarter, "cells": [data.index(shore)]}
					var probe: Dictionary = SiteRuntime._ship_launch_query(data, stub, "ferry", lab.site_controller.reserves_cell)
					if not probe.ok:
						yard_reason = str(probe.message)
						continue
					# The yard footprint is 4x3 with the shore cell on its edge; origins are tried around that cell.
					for ox in range(4):
						for oy in range(3):
							var origin := shore - Vector2i(ox, oy)
							var options := {"owner_faction": faction, "quarter": quarter, "waterfront_version": 1, "launch_cell": data.index(anchor)}
							var layout: Dictionary = SiteRuntime.building_cells(data, "shipyard", origin, Vector2i(4, 3), options)
							if not layout.ok:
								yard_reason = str(layout.message)
								continue
							if not layout.cells.has(data.index(shore)):
								continue
							var cells: Array[int] = []
							for cell: Variant in layout.cells: cells.append(int(cell))
							var build: Dictionary = SiteRuntime.request_build(data, "shipyard", cells, lab.site_controller.reserves_cell, options)
							if not build.ok:
								yard_reason = str(build.message)
								continue
							var key := str(build.feature)
							var feature: Dictionary = data.site.features[key]
							var worker: Dictionary = data.site.worker
							worker.cell = int(feature.entrance)
							worker.target = "feature:" + key
							worker.action = "construct"
							worker.mode = "work"
							SiteRuntime._feature_work(data, key, float(feature.work), Callable(), Callable(), null, null, SiteRuntime.CARRY_CAPACITY, 0)
							worker.target = ""
							worker.mode = "idle"
							if feature.stage == "complete" and SiteRuntime.validate_feature_layout(data, feature).ok:
								var launch: Dictionary = SiteRuntime._ship_launch_query(data, feature, "ferry", lab.site_controller.reserves_cell)
								if launch.ok: return key
								yard_reason = str(launch.message)
	return ""

func _run() -> void:
	create_timer(300.0).timeout.connect(func() -> void: quit(3))
	var args := OS.get_cmdline_user_args()
	if not check(args.has("--crowd") and args.has("--crowd-test"), "isolated crowd startup required"): return
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	var prepared: Dictionary = _prepare()
	if not check(bool(prepared.get("ok", false)), "generated coastal Site deploys crowd teams with a natural dock", prepared): return
	for person: TerrainTestCharacter in lab.combat_actors: person.set_process(false)
	if not check(lab.crowd_site != null and lab.crowd_site.active, "crowd site active on the generated map"): return
	var data: TerrainData = lab.terrain
	if not check(yard_key != "", "a completed shipyard fits beside the natural dock with the launch cell on the water", yard_reason): return
	if not check(SiteRuntime.validate_feature_layout(data, data.site.features[yard_key]).ok, "the completed shipyard has a legal layout"): return
	commander_identity = owner.combat_identity(owner.current_commander)
	var worker_indices: Array[int] = []
	for index: int in members:
		if index != owner.current_commander and worker_indices.size() < 2: worker_indices.append(index)
	if not check(worker_indices.size() == 2, "the crowd team has two non-commander soldiers to work", worker_indices): return
	for index: int in worker_indices: workers.append(owner.combat_identity(index))

	# Crowd workers are assigned to the shipyard by the original work team (the commander orders the work).
	var assigned: Dictionary = lab.site_controller.work_team.assign(owner, workers, commander_identity)
	if not check(assigned.ok, "the commander assigns two crowd soldiers to the shipyard", assigned): return

	# Materials are paid up front when the ferry batch begins.
	var cost: Dictionary = Ships.build_cost("ferry")
	var paid_before: Dictionary = _materials()
	var begun: Dictionary = SiteRuntime.begin_ship_build(data, yard_key, "ferry", int(owner.team_id), int(owner.faction_id), lab.site_controller.reserves_cell)
	if not check(begun.ok, "a ferry batch begins at the crowd shipyard", begun): return
	for resource: String in cost:
		if not check(int(data.site.inventory[resource]) == int(paid_before[resource]) - int(cost[resource]), "ferry materials are paid up front: %s" % resource): return
	if not check(_feature().has("ship_build") and _feature().batch_paid == true, "the paid batch is recorded on the shipyard"): return

	# Scenario 1: batch 1 is cancelled after crowd progress. Cancelling refunds only the unused fraction.
	if not check(_wait_progress(WALK_TICKS), "crowd workers walk to the shipyard and advance the paid ferry batch", _feature().get("production")): return
	var total_work := float(_feature().ship_build.total_work)
	var unused := maxf(0.0, 1.0 - float(_feature().production) * 60.0 / total_work)
	var expected := {}
	for resource: String in cost: expected[resource] = floori(float(cost[resource]) * unused)
	var preview: Dictionary = SiteRuntime.cancel_ship_build(data, yard_key, int(owner.faction_id), true)
	if not check(preview.ok and preview.refund == expected, "the cancel preview refunds the unused fraction of the paid cost", {"preview": preview, "expected": expected}): return
	var stock_before: Dictionary = _materials()
	var cancelled: Dictionary = SiteRuntime.cancel_ship_build(data, yard_key, int(owner.faction_id))
	if not check(cancelled.ok and not _feature().has("ship_build"), "the cancelled batch leaves the shipyard", cancelled): return
	for resource: String in cost:
		if not check(int(data.site.inventory[resource]) == int(stock_before[resource]) + int(expected[resource]), "the cancel refunds the unused %s" % resource): return

	# Scenario 2: batch 2 is saved and reloaded mid-batch. The berth is still free: no launch has happened yet.
	var begun_second: Dictionary = SiteRuntime.begin_ship_build(data, yard_key, "ferry", int(owner.team_id), int(owner.faction_id), lab.site_controller.reserves_cell)
	if not check(begun_second.ok, "a second ferry batch begins for the save and reload check", begun_second): return
	if not check(_wait_progress(WALK_TICKS), "the save-check batch shows crowd progress before the save", _feature().get("production")): return
	# Legal save point: the native save refuses while a worker holds its work step (escort mode >= 3). The work team
	# stands the workers down (WorkTeam.cancel cancels each controlled step); the batch itself stays on the shipyard.
	for identity: int in workers: lab.site_controller.work_team.cancel(identity)
	if not check(_steps_settled(), "every crowd worker's controlled step settles before the save", _step_modes()): return
	var job_before: Dictionary = _feature().ship_build.duplicate(true)
	var production_before := float(_feature().production)
	if not check(production_before > 0.0 and production_before * 60.0 < float(job_before.total_work), "the save point is mid-batch", production_before): return
	if not check(lab.site_controller._capture_for_save().ok, "capture for save with crowd workers mid-batch"): return
	var written: Dictionary = Store.save(lab.terrain, lab.site_controller.save_path, lab.crowd_site.crowd)
	if not check(written.get("ok", false) == true, "Store.save writes the mid-batch shipyard", written): return
	var loaded: Dictionary = lab.site_controller.load_from(lab.site_controller.save_path)
	if not check(loaded.get("ok", false) == true, "load_from restores the mid-batch shipyard", loaded): return
	# Every reference is re-fetched: the load binds a new terrain, crowd and work team.
	data = lab.terrain
	owner = lab.crowd_site.person_owner(workers[0])
	if not check(owner != null, "the assigned crowd owner survives the reload"): return
	if not check(_feature().has("ship_build") and _feature().batch_paid == true, "the mid-batch shipyard keeps its batch after the reload"): return
	if not check(_feature().ship_build.paid_cost == job_before.paid_cost and _feature().ship_build.ship_type == "ferry", "the reloaded batch keeps its paid cost", _feature().ship_build): return
	if not check(is_equal_approx(float(_feature().ship_build.total_work), float(job_before.total_work)), "the reloaded batch keeps its total work"): return
	if not check(is_equal_approx(float(_feature().production), production_before), "the reloaded batch keeps its progress", _feature().get("production")): return
	# Scenario 3: the workers are reassigned on the reloaded Site and batch 2 runs to completion and launches.
	var commander_after: int = owner.combat_identity(owner.current_commander)
	var reassigned: Dictionary = lab.site_controller.work_team.assign(owner, workers, commander_after)
	if not check(reassigned.ok, "the commander reassigns the crowd workers after the reload", reassigned): return
	var ships_before: int = lab.terrain.site.vehicles.size()
	var ids_before: Array = _vehicle_ids()
	if not check(_finish_batch(ships_before), "the reloaded batch completes and launches under crowd work"): return
	var launched_id := _new_vehicle_id(ids_before)
	var boat: Dictionary = lab.terrain.site.vehicles.get(launched_id, {})
	if not check(launched_id != "" and boat.get("kind") == "ship" and boat.get("ship_type") == "ferry", "the launched ferry exists in vehicles", launched_id): return
	if not check(int(boat.get("team_id", -1)) == int(owner.team_id), "the ferry belongs to the building team"): return
	if not check(int(boat.get("naval", {}).get("version", 0)) == 1 and boat.naval.get("state") == "afloat", "the ferry has a naval v1 afloat record", boat.get("naval", {})): return
	if not check(not _feature().has("ship_build") and not _feature().batch_paid, "the shipyard is free after the launch"): return
	if not check(lab.site_controller.vehicles.records().has(launched_id), "the launched ferry is in the live vehicle records"): return
	print("G2 SHIPYARD DONE checks=", checks, " yard=", yard_key, " launched=", launched_id)
	quit(0)
