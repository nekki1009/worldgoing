extends SceneTree
## Six enabled types: one original hundred-person roster, real jobs and JSON.
## Terrain is an explicitly synthetic, pinned 2m fixed coast. The original
## RegionData/Adapter and Store reconstruct the same source after every load.

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Ship = preload("res://scripts/terrain_lab/site_vehicle_ship_definitions.gd")
const Atlas = preload("res://scripts/region_lab/region_data.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const HULL_COUNTS := {"ferry": 10, "river": 5, "coastal": 4, "troop": 2, "patrol": 4, "tower": 1}
const OUT := "res://output/site_ship_close_20261004/full_transport"
const BASELINE := OUT + "/hundred_shore.json"
# Crowd port (2026-11-08): the shared action clock and one native step per tick, as site_ship_crowd_test.
const DT := 1.0 / 30.0
const MAX_WALK_TICKS := 1200

var deadline := 0
var lab: TerrainLab
var team: Variant # The native crowd formation owner (CrowdPersonOwner); the grid TerrainArmy is retired.
var people: Array[int] = []
var parking: Array[Vector2i] = []
var item_ids: Array[Array] = []
var equipment: Array[Dictionary] = []
var cargo: Array[Dictionary] = []
var team_id := 0
var fingerprint := ""
var initial_next_person := 0
var initial_q := 0.0
var completed := 0
var layouts: Dictionary = {}
var atlas: RegionData

class FixtureController extends SiteController:
	var fixed_fixture_source: RegionData

	func _load_compatible_site(path: String) -> Dictionary:
		# Only provide the original fixed-source callback missing from procedural
		# Controller loads. All save/load/life/Army admission remains inherited.
		var result: Dictionary = Store.load_site(path, fixed_fixture_base, clampi(OS.get_processor_count(), 1, 8))
		if result.ok:
			var guard: Dictionary = lab.exchange_snapshot_guard(result.data)
			if not guard.ok: return guard
		return result

	func fixed_fixture_base(saved: Dictionary) -> Dictionary:
		if not saved.get("site") is Array or saved.site.size() != 2: return Runtime.fail("SAVE_VERSION")
		var rebuilt: Dictionary = fixed_fixture_source.make_terrain_data(int(saved.site[0]), int(saved.site[1]))
		if not rebuilt.ok or not Store._same_fixed_base(rebuilt.get("base"), saved): return Runtime.fail("SAVE_VERSION")
		return rebuilt

# Nekki 2026-10-15 02:22Z (decision card, option A): 300 s for this test; raised to 360 s by
# Nekki 2026-10-15 10:37Z (direct confirmation); assertions unchanged.
# Recorded in output/acceptance_efficiency_20261012/timeout/timeout_adjustments_20261015_nekki.json.
func _ship_test_deadline_ms(default_ms: int = 360000) -> int:
	# Same user argument in headless/GPU runs; subclasses can reuse this helper.
	# An explicit budget never reduces real walking/jobs/JSON acceptance.
	var budget: int = default_ms
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--ship-test-deadline-ms="): continue
		var value: String = argument.trim_prefix("--ship-test-deadline-ms=")
		if not value.is_valid_int() or int(value) <= 0 or int(value) > 600000:
			push_error("Ship test deadline must be an explicit integer in 1..600000ms")
			quit(1)
			return 0
		budget = int(value)
	return budget

func _initialize() -> void:
	var budget: int = _ship_test_deadline_ms()
	if budget <= 0: return
	deadline = Time.get_ticks_msec() + budget
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Six-type real hundred-person transport deadline")
		quit(1)
	return false

func _must(condition: bool, message: String) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Hundred-person transport bounded deadline: " + message)
		quit(1)
		return false
	if condition: return true
	push_error(message)
	quit(1)
	return false

func _freeze_processes() -> void:
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)

func _anchor(kind: String, hull: int) -> Vector2i:
	return layouts[kind][hull].anchor

func _facing(kind: String, hull: int) -> Vector2i:
	return layouts[kind][hull].facing

func _target(kind: String, hull: int, steps: int) -> Vector2i:
	return _anchor(kind, hull) + _facing(kind, hull) * steps

func _shore(kind: String, hull: int, steps: int = 0) -> Vector2i:
	return layouts[kind][hull].shore if steps == 0 else layouts[kind][hull].destination_shore

func _find_layout(data: TerrainData, kind: String) -> Array[Dictionary]:
	var selected: Array[Dictionary] = []
	var claimed := {}
	var distance := 13 if kind == "troop" else 3
	var starts: Dictionary = {"ferry": [9, 17, 25, 33, 41, 49, 57, 65, 73, 81], "river": [12, 30, 48, 66, 84],
		"coastal": [20, 42, 64, 86], "troop": [30, 70], "patrol": [20, 42, 64, 86], "tower": [40]}
	for x: int in starts[kind]:
		var anchor := Vector2i(x, 19)
		var direction := Vector2i.LEFT
		var port := anchor + Vector2i.DOWN
		var arrival := port + direction * 3
		if not data.is_walkable(port) or not data.is_walkable(arrival) \
			or not Ship.boarding_cells(kind, anchor, direction).has(port) \
			or not Ship.boarding_cells(kind, anchor + direction * 3, direction).has(arrival): return []
		var reserved := {}
		for step in range(distance + 1):
			var footprint: Array[Vector2i] = Ship.footprint(kind, anchor + direction * step, direction)
			if not data.can_place_water_vehicle(footprint): return []
			for cell: Vector2i in footprint:
				if claimed.has(cell): return []
				reserved[cell] = true
			if step > 0 and not data.can_place_water_vehicle(Ship.swept_footprint(kind, anchor + direction * (step - 1), direction, anchor + direction * step, direction)): return []
		selected.append({"anchor": anchor, "facing": direction, "shore": port, "destination_shore": arrival})
		claimed.merge(reserved)
	if selected.size() == int(HULL_COUNTS[kind]): return selected
	var none: Array[Dictionary] = [] # Typed empty result, not an untyped ternary literal.
	return none

func _asset(name: String, bytes: PackedByteArray) -> Dictionary:
	var path := OUT.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not _must(file != null, "Cannot write original fixed-coast source asset"): return {}
	file.store_buffer(bytes)
	file.close()
	return {"path": name, "sha256": FileAccess.get_sha256(path)}

func _fixed_coast() -> TerrainData:
	if not _must(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT)) == OK, "Fixed coast evidence directory failed"): return null
	var summary := PackedByteArray()
	summary.resize(25)
	summary.fill(2)
	var summary_record := _asset("summary.u8", summary)
	summary_record.merge({"size": [5, 5], "site_origin": [-2, -2], "encoding": "u8", "row_order": "north_to_south", "nodata": 0})
	# The source covers the origin and adjacent Sites, including THEIR geographic halos.
	# Water is an ocean mask with unknown seabed elevation; land is measured 0.
	var elevation := PackedByteArray()
	var levels := PackedByteArray()
	var water := PackedByteArray()
	elevation.resize(500 * 500 * 2)
	levels.resize(500 * 500)
	water.resize(500 * 500)
	for y in range(500):
		var north := -400 + (499 - y) * 2 + 1
		for x in range(500):
			var index := y * 500 + x
			var ocean := north >= 160
			elevation.encode_s16(index * 2, -32767 if ocean else 0)
			water[index] = 2 if ocean else 0
	var height_record := _asset("coast.height.zlib", elevation.compress(FileAccess.COMPRESSION_DEFLATE))
	var level_record := _asset("coast.levels.zlib", levels.compress(FileAccess.COMPRESSION_DEFLATE))
	var water_record := _asset("coast.water.zlib", water.compress(FileAccess.COMPRESSION_DEFLATE))
	height_record.merge({"id": "straight_coast", "origin": [-400, -400], "size": [500, 500], "spacing_m": 2,
		"encoding": "int16_le_zlib", "row_order": "north_to_south", "nodata": -32767,
		"derived": {"encoding": "u8_zlib", "levels_path": level_record.path, "levels_sha256": level_record.sha256, "water_path": water_record.path, "water_sha256": water_record.sha256}})
	var manifest := {"format": 1, "synthetic_fixture": true, "atlas_id": Grid.ATLAS_ID, "grid_contract_version": 1,
		"base_revision": "ship-full-fixed-coast-v2-halo", "crs": "EPSG:3826",
		"grid": {"origin": [0, 0], "cell_m": 2, "site_cells": 100, "region_sites": 100},
		"summary": summary_record, "elevation_tiles": [height_record], "sources": [{"title": "Synthetic straight-coast transport fixture only"}]}
	var file := FileAccess.open(OUT.path_join("manifest.json"), FileAccess.WRITE)
	if not _must(file != null, "Cannot write fixed-coast manifest"): return null
	file.store_string(JSON.stringify(manifest, "", true, true))
	file.close()
	atlas = Atlas.new()
	if not _must(atlas.load_manifest(OUT.path_join("manifest.json")).ok, "Original fixed-coast manifest rejected"): return null
	var built: Dictionary = atlas.make_terrain_data(0, 0)
	if not _must(built.ok and built.data.size == Vector2i(100, 100), "Original fixed-coast 100x100 adapter rejected"): return null
	var data: TerrainData = built.data
	Env.initialize(data, str(built.base.site_id))
	return data

func _fixture() -> bool:
	var accepted := _fixed_coast()
	if accepted == null: return false
	layouts.clear()
	for kind: String in Ship.KINDS:
		var arrangement := _find_layout(accepted, kind)
		if not _must(not arrangement.is_empty(), "Original pinned 100x100 coast rejected a complete legal fleet/route: " + kind): return false
		layouts[kind] = arrangement
	# Reuse the same original Controller node and all its already-wired owners.
	# This test-only subclass supplies immutable base loading, not a new ledger,
	# alternate save validator, movement owner or person/ship representation.
	var controller: SiteController = lab.site_controller
	var original_properties := {}
	for property: Dictionary in controller.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE: original_properties[property.name] = controller.get(property.name)
	controller.set_script(FixtureController)
	for property: StringName in original_properties: controller.set(property, original_properties[property])
	controller.set("fixed_fixture_source", atlas)
	lab.bind_terrain(accepted)
	_freeze_processes()
	var shore: Vector2i = _shore("ferry", 0)
	var ports: Dictionary = {}
	for kind: String in layouts:
		for entry: Dictionary in layouts[kind]:
			ports[entry.shore] = true
			ports[entry.destination_shore] = true
	for port: Vector2i in ports:
		if not _must(not lab.character.occupies_cell(port) and not lab.npc.occupies_cell(port), "Original Actor occupies a required fleet shore contact"): return false
	parking.clear()
	# One initial 10x10 grid, two-cell pitch: one empty row/column between
	# neighbours and two clear shoreline rows. Select a grid phase that avoids
	# the original Actors; never relocate a deployed person or clear a blocker.
	for row_phase: int in range(2):
		for column_phase: int in range(2):
			var origin: Vector2i = Vector2i(10 + column_phase, 22 + row_phase)
			var staged: Array[Vector2i] = []
			var occupied: Dictionary = {}
			var legal: bool = true
			for row: int in range(10):
				for column: int in range(10):
					var cell: Vector2i = origin + Vector2i(column * 2, row * 2)
					if not accepted.is_walkable(cell) or ports.has(cell) or lab.character.occupies_cell(cell) or lab.npc.occupies_cell(cell): legal = false
					staged.append(cell)
					occupied[cell] = true
			if not legal: continue
			# Preflight original navigation with ALL the other initial positions
			# occupied. The same open lanes also remain when people return in order.
			for cell: Vector2i in staged:
				var blocked: Callable = func(next: Vector2i) -> bool:
					return occupied.has(next) and next != cell or lab.character.occupies_cell(next) or lab.npc.occupies_cell(next)
				if accepted.path_between(cell, shore, blocked).is_empty() or accepted.path_between(shore, cell, blocked).is_empty(): legal = false; break
			if not legal: continue
			var blocked_ports: Callable = func(next: Vector2i) -> bool:
				return occupied.has(next) or lab.character.occupies_cell(next) or lab.npc.occupies_cell(next)
			for port: Vector2i in ports:
				if port == shore: continue
				if accepted.path_between(shore, port, blocked_ports).is_empty() or accepted.path_between(port, shore, blocked_ports).is_empty(): legal = false; break
			if not legal: continue
			parking.assign(staged)
			print("SITE_SHIP_INITIAL_STAGING:people=100:grid=10x10:pitch=2:origin=%s:original_port_routes=connected" % str(origin))
			return true
	return _must(false, "Could not reserve a sparse hundred-person initial grid connected to every original shore contact")

## Fixture move, as the grid fixture did (no gameplay time is synthesized while setting up this explicit fixture): the
## route must exist on the real terrain, then the native soldier is placed on the destination cell (the crowd test
## placement, crowd_b_dr_roundtrip) and must stand there, stopped. Walking 600 boarders on the real 30 Hz clock took
## about 11 s of wall time per person (PORT_P1_FT_v2).
func _walk(index: int, destination: Vector2i) -> bool:
	var walker: Dictionary = team.person(index, false)
	if not _must(not walker.is_empty(), "Crowd shore walker #%d vanished" % people[index]): return false
	if walker.cell == destination and not bool(walker.moving): return true
	var path: Array[Vector2i] = lab.terrain.path_between(walker.cell, destination, func(cell: Vector2i) -> bool: return lab.character.occupies_cell(cell) or lab.npc.occupies_cell(cell))
	if not _must(not path.is_empty(), "Original shore route missing for #%d to %s" % [people[index], str(destination)]): return false
	var native := int(lab.crowd_site.crowd.soldier_index(people[index]))
	if not _must(native >= 0 and lab.crowd_site.set_soldier_fields(native, {"px": destination.x + 0.5, "py": destination.y + 0.5}), "Crowd fixture placement refused for #%d" % people[index]): return false
	walker = team.person(index, false)
	return _must(not walker.is_empty() and walker.cell == destination and not bool(walker.moving), "Original shore step did not commit exactly once")

## Native boarding state: [aboard, vehicle_id] from the crowd, optionally on one vehicle.
func _crowd_aboard(index: int, vehicle_id: int = -1) -> bool:
	var state: Array = team.native_aboard(index)
	return state.size() == 2 and bool(state[0]) and (vehicle_id < 0 or int(state[1]) == vehicle_id)

## The berth a passenger holds on this hull, read from the vehicle's own passenger rows (-1 if absent).
func _berth_of(identity: int, boat: Dictionary) -> int:
	for passenger: Dictionary in lab.site_controller.vehicles.ship_people(boat):
		if int(passenger.id) == identity: return int(passenger.row.berth_id)
	return -1

## Crowd stop: an explicit HOLD order on the native formation, the crowd counterpart of the grid settle before boarding.
## It then settles on the shared action clock (formation drift after a walk) until the same stop predicate as the boarding guard holds.
func _stop_team() -> bool:
	var held: Dictionary = lab.crowd_site.issue_order(team_id, TerrainArmy.CombatOrder.HOLD, Vector2i(-1, -1), -1, "test")
	if not _must(held.ok or team.combat_order == TerrainArmy.CombatOrder.HOLD, "Crowd formation refused its HOLD stop: " + str(held)): return false
	for tick in range(MAX_WALK_TICKS):
		if lab.site_controller._team_stopped(team, false, {}): return true
		lab._advance_action_time(DT)
	return _must(false, "Crowd formation did not settle to a stop before boarding")

## Crowd HOLD without waiting for the whole formation to settle (boarding after the first one checks only the order).
func _hold_team() -> bool:
	var held: Dictionary = lab.crowd_site.issue_order(team_id, TerrainArmy.CombatOrder.HOLD, Vector2i(-1, -1), -1, "test")
	return _must(held.ok or team.combat_order == TerrainArmy.CombatOrder.HOLD, "Crowd formation refused its HOLD order: " + str(held))

## The one native formation this test owns (the lab's grid TerrainArmy stays a retired roster container).
func _crowd_owner() -> Variant:
	for candidate: Variant in lab.crowd_site.person_owners():
		if candidate is CrowdPersonOwner and candidate.has_army() and candidate.team_id == team_id: return candidate
	return null

func _finish_job(identity: int) -> bool:
	var observed_job_start: int = Time.get_ticks_msec()
	var actions: SitePersonActions = lab.site_controller.person_actions
	if not _must(actions.is_busy(identity), "Expected the original timed person job"): return false
	var job: Dictionary = actions._jobs[str(identity)]
	var observed_job_kind: String = str(job.get("kind", ""))
	if not _must(actions.save_guard().code == "BUSY", "Real person job must keep the original save guard busy"): return false
	actions.advance_ship_jobs(maxf(0.01, float(job.duration) - float(job.elapsed) + 0.01))
	actions.settle_after_contacts()
	print("SITE_SHIP_FULL_JOB_WALL:person=%d:kind=%s:wall_ms=%d:busy=%s" % [identity, observed_job_kind, Time.get_ticks_msec() - observed_job_start, str(actions.is_busy(identity))])
	return _must(not actions.is_busy(identity), "Original person job failed to settle")

func _same_json(left: Variant, right: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(left, "", true, true)) == JSON.parse_string(JSON.stringify(right, "", true, true))

func _people_intact(aboard: bool, expected_next_person: int) -> bool:
	if not _must(team.team_id == team_id and team.command_members().size() == 100,
		"Full transport changed the original hundred-person team"): return false
	if not _must(int(lab.terrain.site.next_person_id) == expected_next_person, "Boats or jobs allocated extra persons"): return false
	var seen := {}
	for index in range(100):
		var row: Dictionary = team.person(index, true)
		if not _must(not row.is_empty() and int(row.person_id) == people[index] and not seen.has(people[index]) and team.is_member(index), "Full transport replaced, duplicated or retired an original person"): return false
		seen[people[index]] = true
		if not _must(_same_json(row.cargo, cargo[index]) and _same_json(row.holder.item_ids, item_ids[index]) and _same_json(row.holder.equipped, equipment[index]), "Full transport changed original cargo/equipment for #%d" % people[index]): return false
		if not _must(float(row.hp) == 100.0 and not bool(row.moving), "Full transport changed life or retained a committed land step"): return false
		if aboard:
			if not _must(_crowd_aboard(index) and lab.site_controller.vehicles.is_embarked(people[index]), "Passenger has no real native berth"): return false
		else:
			if not _must(not _crowd_aboard(index) and not lab.site_controller.vehicles.is_embarked(people[index]) and row.cell == parking[index], "Original disembarked person did not regain their own shore position"): return false
	return _must(seen.size() == 100 and lab.terrain.fingerprint() == fingerprint, "Full transport changed terrain or roster identity")

func _load(path: String) -> bool:
	var controller: SiteController = lab.site_controller
	controller.save_path = path # Isolated tests never create a formal/extra archive.
	var loaded: Dictionary = controller.load_from(path)
	if not _must(loaded.ok, "True full-transport Controller load rejected: %s" % str(loaded)): return false
	team = _crowd_owner()
	if not _must(team != null, "Crowd original team missing after the Controller load"): return false
	_freeze_processes()
	return true

## Crowd: the native formation commits every step on the shared clock, so there is no grid command queue to settle.
func _settle_commands() -> void:
	pass

func _fleet(kind: String) -> bool:
	var started := Time.get_ticks_msec()
	print("SITE_SHIP_FULL_PROGRESS:kind=%s:phase=begin:completed=0:wall_ms=0" % kind)
	if not _load(BASELINE): return false
	if not _people_intact(false, initial_next_person): return false
	var controller: SiteController = lab.site_controller
	var vehicles: SiteVehicleTransport = controller.vehicles
	var actions: SitePersonActions = controller.person_actions
	var spec: Dictionary = Ship.definition(kind)
	var seats := int(spec.max_people)
	var boat_ids: Array[String] = []
	var hulls := int(HULL_COUNTS[kind])
	for hull in range(hulls):
		var deployed: Dictionary = vehicles.deploy_ship(team, kind, _anchor(kind, hull), _facing(kind, hull), true)
		if not _must(deployed.ok, "%s original boat deployment rejected: %s" % [kind, str(deployed)]): return false
		boat_ids.append(str(deployed.vehicle_id))
	for index in range(100):
		var hull := floori(float(index) / seats)
		var id := boat_ids[hull]
		var shore := _shore(kind, hull)
		if not _walk(index, shore): return false
		# Crowd: boarding needs the formation at HOLD (the walk just set MOVE). Only the first boarding of a fleet converts the
		# abstract team stock to a shore location, and only that one needs the whole team stopped (prepare_ship_supply).
		if not (_stop_team() if index == 0 else _hold_team()): return false
		var boarded: Dictionary = actions.begin_ship_board(people[index], id, people[index], index % seats, true)
		if not _must(boarded.ok, "%s person %d original boarding rejected: %s" % [kind, index, str(boarded)]): return false
		if not _must(not _crowd_aboard(index) and team.person(index, false).cell == shore, "Pending real boarding committed before its timed job"): return false
		if not _finish_job(people[index]): return false
		if not _must(_crowd_aboard(index, int(id)) and _berth_of(people[index], vehicles.records()[id]) == index % seats, "Real boarding replaced a person or chose a different berth"): return false
		if index % seats == 0:
			var helm: Dictionary = actions.begin_ship_helm(people[index], id, people[index], true)
			if not _must(helm.ok, "%s original helm job rejected: %s" % [kind, str(helm)]) or not _finish_job(people[index]): return false
		if (index + 1) % 10 == 0: print("SITE_SHIP_FULL_PROGRESS:kind=%s:phase=board_and_helm:completed=%d:wall_ms=%d" % [kind, index + 1, Time.get_ticks_msec() - started])
	if not _people_intact(true, initial_next_person): return false
	# Crowd: team_vehicle_count is typed to the retired TerrainArmy, so count this formation's hull claims directly.
	var deducted := 0
	for vehicle: Dictionary in vehicles.records().values():
		deducted += int(int(vehicle.team_id) == team_id and not vehicles.is_siege(vehicle) and not vehicles.is_ship(vehicle))
	if not _must(deducted == 0 and vehicles.records().size() == hulls, "Real hulls deducted roster slots or created extra boats"): return false
	var q_by_boat := {}
	var total_q := 0.0
	for hull in range(hulls):
		var id := boat_ids[hull]
		var boat: Dictionary = vehicles.records()[id]
		var count := mini(seats, 100 - hull * seats)
		if not _must(vehicles.ship_people(boat).size() == count and vehicles.ship_crew_count(boat) == int(spec.standard_crew) and int(boat.operator_id) == people[hull * seats], "Real fleet did not retain its original people/crew/operator"): return false
		q_by_boat[id] = vehicles.ship_load(id)
		total_q += float(q_by_boat[id])
		if not _must(float(q_by_boat[id]) <= float(spec.capacity), "Full fleet illegally admitted actual original equipment load"): return false
		var sailing: Dictionary = vehicles.ship_order(id, "sail", _target(kind, hull, 2), people[hull * seats], true)
		if not _must(sailing.ok, "%s real fleet sail rejected: %s" % [kind, str(sailing)]): return false
	if not _must(is_equal_approx(total_q, initial_q), "Real fleet lost or counted original Q twice"): return false
	vehicles.update_ships(0.25) # Original command owner starts each committed step.
	var moves := {}
	var commands := {}
	for id: String in boat_ids:
		var boat: Dictionary = vehicles.records()[id]
		if not _must(not boat.move.is_empty(), "Real fleet command never created a ship step"): return false
	vehicles.update_ships(0.25)
	for id: String in boat_ids:
		var boat: Dictionary = vehicles.records()[id]
		if not _must(float(boat.move.elapsed) > 0.0 and float(boat.move.elapsed) < float(boat.move.duration), "Fleet JSON must capture every boat genuinely mid-step"): return false
		moves[id] = boat.move.duplicate(true)
		commands[id] = boat.command.duplicate(true)
	_settle_commands()
	var food: Dictionary = lab.terrain.site.team_supply.duplicate(true)
	var path := OUT + "/%s_hundred_half_step.json" % kind
	var saved: Dictionary = controller.save_to(path)
	if not _must(saved.ok, "%s true hundred-person Controller save rejected: %s" % [kind, str(saved)]): return false
	var candidate: Dictionary = Store.load_site(path, Callable(controller, "fixed_fixture_base"))
	if not _must(candidate.ok and candidate.data.fingerprint() == fingerprint, "%s original Store hundred-person reconstruction rejected: %s" % [kind, str(candidate)]): return false
	if not _load(path) or not _people_intact(true, initial_next_person): return false
	controller = lab.site_controller
	vehicles = controller.vehicles
	actions = controller.person_actions
	if not _must(_same_json(lab.terrain.site.team_supply, food), "Hundred-person JSON changed original supply locations/history"): return false
	for id: String in boat_ids:
		var boat: Dictionary = vehicles.records()[id]
		if not _must(_same_json(boat.move, moves[id]) and _same_json(boat.command, commands[id]) and is_equal_approx(vehicles.ship_load(id), float(q_by_boat[id])), "Hundred-person JSON rewrote an original half-step, command or Q"): return false
	for tick in range(512):
		vehicles.update_ships(0.25)
		var finished := true
		for id: String in boat_ids:
			var boat: Dictionary = vehicles.records()[id]
			finished = finished and boat.move.is_empty() and boat.command.is_empty()
		if finished: break
	for hull in range(hulls):
		var id := boat_ids[hull]
		var boat: Dictionary = vehicles.records()[id]
		if not _must(boat.move.is_empty() and boat.command.is_empty() and lab.terrain.cell_from_index(int(boat.cell)) == _target(kind, hull, 2), "Loaded fleet did not finish its real original route"): return false
		var docked: Dictionary = vehicles.ship_order(id, "dock", _target(kind, hull, 3), people[hull * seats], true)
		if not _must(docked.ok, "%s real hundred-person dock rejected: %s" % [kind, str(docked)]): return false
	vehicles.update_ships(0.01)
	for id: String in boat_ids:
		var boat: Dictionary = vehicles.records()[id]
		if not _must(not boat.move.is_empty() and str(boat.move.action) == "dock" and float(boat.move.duration) >= 2.0, "Actual final docking did not preserve its 0.5-cell/s cap"): return false
	vehicles.update_ships(4.0)
	vehicles.update_ships(0.01) # Original command owner clears its reached goal next tick.
	for hull in range(hulls):
		var boat: Dictionary = vehicles.records()[boat_ids[hull]]
		if not _must(boat.move.is_empty() and boat.command.is_empty() and vehicles.ship_contacts(boat).has(_shore(kind, hull, 3)), "Actual fleet docking failed its legal shore contact"): return false
	for index in range(100):
		var hull := floori(float(index) / seats)
		var shore := _shore(kind, hull, 3)
		var left: Dictionary = actions.begin_ship_disembark(people[index], boat_ids[hull], people[index], shore, true)
		if not _must(left.ok, "%s person %d real disembark rejected: %s" % [kind, index, str(left)]) or not _finish_job(people[index]): return false
		if not _must(team.person(index, false).cell == shore, "Real disembark did not reacquire the original shore claim"): return false
		if not _walk(index, parking[index]): return false
		if (index + 1) % 10 == 0: print("SITE_SHIP_FULL_PROGRESS:kind=%s:phase=disembark_and_return:completed=%d:wall_ms=%d" % [kind, index + 1, Time.get_ticks_msec() - started])
	if not _people_intact(false, initial_next_person): return false
	for id: String in boat_ids:
		var boat: Dictionary = vehicles.records()[id]
		if not _must(vehicles.ship_people(boat).is_empty() and int(boat.operator_id) == 0 and is_equal_approx(vehicles.ship_load(id), 0.0), "Empty real boat retained a passenger, operator or vanished cargo"): return false
	# _formation_change_pending is grid-only state and is not checked in crowd mode (no grid formation queue exists).
	if not _must(actions._jobs.is_empty() and team.combat_order == TerrainArmy.CombatOrder.HOLD and not team.tactical_ai_enabled, "Last real passenger restored an obsolete command/AI/formation"): return false
	_settle_commands()
	var final_path := OUT + "/%s_hundred_disembarked.json" % kind
	var final_saved: Dictionary = controller.save_to(final_path)
	if not _must(final_saved.ok, "%s true post-disembark save rejected: %s" % [kind, str(final_saved)]): return false
	if not _load(final_path) or not _people_intact(false, initial_next_person): return false
	completed += 1
	print("SITE_SHIP_FULL_TRANSPORT_KIND_PASS:%s:people=100:boats=%d:real_board=100:real_disembark=100:Q=%.2f:wall_ms=%d" % [kind, hulls, total_q, Time.get_ticks_msec() - started])
	return true

func _run() -> void:
	if not _must(DisplayServer.get_name() == "headless", "Full hundred-person transport uses the bounded headless verifier"): return
	var args := OS.get_cmdline_user_args()
	if not _must(args.has("--crowd") and args.has("--crowd-test"), "isolated crowd startup required"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	_freeze_processes()
	if not _fixture(): return
	# Crowd deployment: the same logistics side, admitted through the lab's trial path onto the staged sparse parking cells.
	var setup: Dictionary = lab._trial_side_settings({"friendly_count": 100, "friendly_role": "logistics", "friendly_attack": false, "friendly_ai_enabled": false}, "friendly")
	if not _must(setup.ok, "Hundred-person side rejected: %s" % str(setup)): return
	var sides: Array[Dictionary] = [setup.side]
	var deployed: Dictionary = lab._deploy_trial_teams(sides, [parking.duplicate()], 0)
	if not _must(deployed.ok, "Original hundred-person full-transport deployment failed: %s" % str(deployed)): return
	team = null
	for candidate: Variant in lab.crowd_site.person_owners():
		if candidate is CrowdPersonOwner and candidate.has_army() and candidate.command_members().size() == 100: team = candidate
	if not _must(team != null, "Crowd formation did not hold the hundred original people"): return
	team_id = team.team_id
	lab.terrain.site.army_next_team = team.team_id + 1
	lab.terrain.site.army_trial_active = true
	for index in range(100):
		var row: Dictionary = team.person(index, true)
		if not _must(not row.is_empty(), "Crowd person %d has no item holder" % index): return
		people.append(int(row.person_id))
		item_ids.append(row.holder.item_ids.duplicate())
		equipment.append(row.holder.equipped.duplicate(true))
		cargo.append(row.cargo.duplicate(true))
		initial_q += Runtime.carried_load(lab.terrain.site, row.cargo, row.holder) + float(row.holder.equipped.size())
	initial_next_person = int(lab.terrain.site.next_person_id)
	fingerprint = lab.terrain.fingerprint()
	_settle_commands()
	var controller: SiteController = lab.site_controller
	controller.save_root = OUT
	controller.save_path = BASELINE
	var baseline: Dictionary = controller.save_to(BASELINE)
	if not _must(baseline.ok, "True hundred-person shore baseline rejected: %s" % str(baseline)): return
	var requested := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--ship-type="): requested = argument.trim_prefix("--ship-type=")
	if not _must(requested.is_empty() or Ship.is_kind(requested), "Unknown requested full-transport ship type"): return
	for kind: String in Ship.KINDS:
		if not requested.is_empty() and requested != kind: continue
		if not _fleet(kind): return
	if not _must(completed == (6 if requested.is_empty() else 1), "The requested enabled ship types were not all exercised"): return
	print("SITE_SHIP_FULL_TRANSPORT_PASS:types=%d:original_people=100:real_board=%d:real_disembark=%d" % [completed, completed * 100, completed * 100])
	quit(0)
