extends SceneTree
## Region travel R1 contract (headless).
##  A. Captain takes the whole team (people, cart, wagon, carried items) across a
##     synthetic pinned map whose sea channel forces a detour; mid-journey
##     checkpoint + reopen; arrival through the real SiteController world open.
##  B. A non-captain leaves the team (existing 退隊) and travels alone.
##  C. Departure refused in combat, with a downed member, or with an enemy near.
##  D. Return to a VISITED Site: exact cold replay of the original Site; timed.
##  E. Real Taiwan map: Yushan routes; every crossing re-proved by the original
##     boundary_surfaces_can_step rule and every Site leg by path_between.
## World clock: monotonic and equal to departure + published travel time.

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Grid = preload("res://scripts/region_lab/region_grid.gd")
const Adapter = preload("res://scripts/region_lab/region_terrain_adapter.gd")
const OUT := "res://.godot-temp/region_travel_test"
const SLOT := "main"

var deadline := 0
var lab: TerrainLab
var controller: SiteController
var manifest_path := ""
var world_id := ""
var report: Dictionary = {}
var reopen_extra := 0.0 # Steps the reopen check publishes outside the main loop.

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 540000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("REGION_TRAVEL_TEST deadline")
		quit(1)
	return false

func _must(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("REGION_TRAVEL_FAIL: " + message)
	quit(1)
	return false

func _freeze() -> void:
	lab.set_process(false)
	controller.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)

func _asset(name: String, bytes: PackedByteArray) -> Dictionary:
	var path := OUT.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	return {"path": name, "sha256": FileAccess.get_sha256(path)}

## Flat level-2 land, 20 m posts, with a north-south sea channel at easting
## 400–440 m for northing < 400 m: Sites (2,-1..1) cannot be crossed westward.
func _write_manifest() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var summary := PackedByteArray()
	summary.resize(9 * 6)
	summary.fill(2)
	var summary_record := _asset("summary.u8", summary)
	summary_record.merge({"size": [9, 6], "site_origin": [-2, -2], "encoding": "u8", "row_order": "north_to_south", "nodata": 0})
	var width := 90
	var height := 60
	var elevation := PackedByteArray()
	var levels := PackedByteArray()
	var water := PackedByteArray()
	elevation.resize(width * height * 2)
	levels.resize(width * height)
	water.resize(width * height)
	for y in range(height):
		var north := -400 + (height - 1 - y) * 20 + 10
		for x in range(width):
			var east := -400 + x * 20 + 10
			var index := y * width + x
			var sea := east >= 400 and east < 440 and north < 400
			elevation.encode_s16(index * 2, -32767 if sea else 40)
			levels[index] = 0 if sea else 2
			water[index] = 2 if sea else 0
	var height_record := _asset("travel.height.zlib", elevation.compress(FileAccess.COMPRESSION_DEFLATE))
	var level_record := _asset("travel.levels.zlib", levels.compress(FileAccess.COMPRESSION_DEFLATE))
	var water_record := _asset("travel.water.zlib", water.compress(FileAccess.COMPRESSION_DEFLATE))
	height_record.merge({"id": "travel_plain", "origin": [-400, -400], "size": [width, height], "spacing_m": 20,
		"encoding": "int16_le_zlib", "row_order": "north_to_south", "nodata": -32767,
		"derived": {"encoding": "u8_zlib", "levels_path": level_record.path, "levels_sha256": level_record.sha256,
			"water_path": water_record.path, "water_sha256": water_record.sha256}})
	var manifest := {"format": 1, "synthetic_fixture": true, "atlas_id": Grid.ATLAS_ID, "grid_contract_version": 1,
		"base_revision": "region-travel-r1-fixture-v1", "crs": "EPSG:3826",
		"grid": {"origin": [0, 0], "cell_m": 2, "site_cells": 100, "region_sites": 100},
		"summary": summary_record, "elevation_tiles": [height_record], "sources": [{"title": "Synthetic Region travel fixture only"}]}
	manifest_path = OUT.path_join("manifest.json")
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "", true, true))
	file.close()
	var probe := RegionData.new()
	return _must(probe.load_manifest(manifest_path).ok, "Synthetic travel manifest rejected")

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest(): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	controller = lab.site_controller
	_freeze()
	controller.save_root = OUT.path_join("archive")
	world_id = "travel_%d" % Time.get_ticks_msec()
	var opened := controller.open_fixed_world(manifest_path, world_id, SLOT, Vector2i(0, 0), true)
	if not _must(opened.ok, "Fixed world did not open: " + str(opened)): return
	_freeze()
	if not _make_original_test_npc(): return
	if not _captain_trip(): return
	if not _solo_trip(): return
	if not _return_to_visited(): return
	if not _yushan_routes(): return
	TerrainArmy.release_contact_source()
	print("REGION_TRAVEL_REPORT: " + JSON.stringify(report))
	print("REGION_TRAVEL_TEST_PASS: captain whole-team and non-captain solo trips, people/items/vehicles conserved, combat/downed/enemy departure refused, sea-channel detour and Yushan crossings re-proved by the original Site rule, mid-journey reopen, clock monotonic and equal to travel time, visited-Site exact cold replay")
	quit(0)

# --- fixture -------------------------------------------------------------------

func _free_cells(around: Vector2i, count: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for radius in range(2, 30):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				var cell := around + Vector2i(x, y)
				if result.size() >= count: return result
				if maxi(absi(x), absi(y)) != radius or not lab.terrain.is_walkable(cell) or result.has(cell): continue
				var taken := false
				for actor: TerrainTestCharacter in lab.combat_actors:
					taken = taken or actor.occupies_cell(cell)
				if not taken: result.append(cell)
	return result

## Explicit test birth uses the original Actor, allocator, equipment owner and
## bind. A hidden absent NPC template cannot witness a nearby enemy refusal.
func _make_original_test_npc() -> bool:
	var candidate := Env.navigation_for_state(lab.terrain, lab.terrain.site.duplicate(true))
	var cells := _free_cells(lab.character.terrain_cell, 1)
	if not _must(cells.size() == 1 and not candidate.site.actors.has("npc"), "Original test NPC needs an unused real cell and actor slot"): return false
	var ids: Array[int] = lab._allocate_army_person_ids_for(1, candidate, lab.combat_actors, lab.combat_armies)
	if not _must(ids.size() == 1, "Original person allocator did not reserve the test NPC"): return false
	var original := TerrainTestNPC.new()
	original.person_id = ids[0]
	original.data = candidate
	original.faction_id = lab.character.faction_id
	original.visible = false
	lab.add_child(original)
	original.set_process(false)
	original.initialize_visual()
	if not _must(original.place(cells[0], true), "Original NPC could not occupy the actual fixture cell"):
		original.free(); return false
	var body := original.capture_state()
	body.appearance.parts.cape = "none"
	original.restore_state(body)
	var items: Dictionary = Runtime.seed_person_equipment(candidate, original.item_state, original.person_id, body.appearance)
	if not _must(items.ok, "Original NPC equipment birth failed: " + str(items)):
		original.free(); return false
	candidate.site.actors["npc"] = original.capture_state()
	candidate.site.worker.cell = candidate.index(cells[0])
	original.free()
	for checked: Dictionary in [Store._validate_actors(candidate, candidate.site), Store._validate_person_allocator(candidate.site),
		Store._validate_items(candidate, candidate.site), Store._validate_cape_roles(candidate.site)]:
		if not _must(checked.ok, "Original NPC candidate failed original save validation: " + str(checked)): return false
	lab.bind_terrain(candidate)
	_freeze()
	return _must(lab.terrain == candidate and lab.actor_present(lab.npc) and lab.npc.person_id == ids[0]
		and lab.npc.can_act() and lab.npc.terrain_cell == cells[0], "Original bind did not publish the real living NPC")

func _make_team() -> TerrainArmy:
	var team: TerrainArmy = lab.army
	team.faction_id = lab.character.faction_id
	team.team_id = lab._next_army_identity()
	team.roster_size = 4
	var cells := _free_cells(lab.character.terrain_cell, 4)
	if not _must(team.deploy_at(lab.terrain, lab.character, lab.npc, cells) and team.enable_combat(false, 0), "Team deployment failed"): return null
	lab.terrain.site.army_next_team = team.team_id + 1
	lab.terrain.site.army_trial_active = true
	_freeze()
	var joined: Dictionary = lab.join_player_army()
	if not _must(joined.ok, "Player could not join: " + str(joined)): return null
	# A captain needs the officer role and command abilities (original rule).
	lab.character.military_role = "officer"
	lab.character.command_abilities = {"tactics": 60, "leadership": 60, "coach": 40}
	team.formal_commander = TerrainArmy.PLAYER_MEMBER
	team.current_commander = TerrainArmy.PLAYER_MEMBER
	team.acting_commander = -1
	team.player_present = true
	team._command_dirty = true
	team.settle_combat_command()
	if not _must(team.formal_commander == TerrainArmy.PLAYER_MEMBER, "Player did not stay captain: %d" % team.formal_commander): return null
	var plan: Dictionary = controller.vehicles.plan_team(team.team_id, 1, 1, cells)
	if not _must(plan.ok, "Vehicle plan failed: " + str(plan)): return null
	var deployed: Dictionary = controller.vehicles.deploy_plan(team, plan.plan)
	if not _must(deployed.ok, "Vehicle deploy failed: " + str(deployed)): return null
	for vehicle: Dictionary in controller.vehicles.records().values():
		if int(vehicle.team_id) == team.team_id and str(vehicle.kind) == "wagon": vehicle.cargo = {"wood": 7}
	lab.terrain.site.manual.cargo = {"grain": 3}
	lab.character.ammo_inventory = lab.terrain.site.manual.cargo
	return team

func _state_census(state: Dictionary, people: Array, vehicles: Array) -> Dictionary:
	var found_people: Array = []
	for army: Dictionary in state.get("armies", []):
		for row: Dictionary in army.get("units", []):
			if people.has(int(row.person_id)): found_people.append(int(row.person_id))
	for actor: Dictionary in state.get("actors", {}).values():
		if people.has(int(actor.person_id)): found_people.append(int(actor.person_id))
	found_people.sort()
	var items: Array = []
	for key: String in state.get("item_records", {}):
		var holder := str(state.item_records[key].holder)
		for identity: Variant in people:
			if holder == "person:%d" % int(identity): items.append(key)
		for identity: Variant in vehicles:
			if holder == "vehicle:" + str(identity): items.append(key)
	items.sort()
	var found_vehicles: Array = []
	var cargo := {}
	for key: String in state.get("vehicles", {}):
		if vehicles.has(key):
			found_vehicles.append(key)
			cargo[key] = state.vehicles[key].get("cargo", {})
	found_vehicles.sort()
	return {"people": found_people, "items": items, "vehicles": found_vehicles, "cargo": cargo}

func _saved_state(slot: RegionSaveSlot, site: Vector2i) -> Dictionary:
	var decoded := Store._read(slot.site_path(site))
	return decoded.payload.state if decoded.ok else {}

# --- route checks ---------------------------------------------------------------

# Match RegionTravelPanel's real route producer: capture the marker-selected party
# and effective navigation on the main thread before the Search reads them.
func _original_party_route(slot: RegionSaveSlot, source: RegionData, from: Vector2i, component: int, to: Vector2i) -> Dictionary:
	var selected := slot.region_travel_party()
	if not selected.ok: return selected
	var prepared := slot.prepare_region_route_context(null, selected.party)
	if not prepared.ok: return prepared
	var context: Dictionary = prepared.context
	var current := slot.region_travel_status()
	if not current.get("vehicle_poses", {}).is_empty():
		context.capabilities.vehicle_poses = current.vehicle_poses.duplicate(true)
	return _route(source, from, component, to, context)

func _route(source: RegionData, from: Vector2i, component: int, to: Vector2i, context: Dictionary = {}) -> Dictionary:
	var search := RegionRoute.Search.new()
	search.source = source
	search.start_site = from
	search.start_component = component
	search.goal_site = to
	search.context = context
	var started := Time.get_ticks_usec()
	var result := search.run()
	result["wall_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	return result

## Independent oracle: original boundary rule between two real Site builds and
## original path_between inside each leg Site.
func _prove_route(source: RegionData, steps: Array, label: String) -> bool:
	var built := {}
	var fetch := func(site: Vector2i) -> TerrainData:
		if not built.has(site):
			var made: Dictionary = source.make_terrain_data(site.x, site.y)
			if made.ok:
				Env.rebuild_indexes(made.data) # Same projection as the original unvisited boundary query.
			built[site] = made.data if made.ok else null
		return built[site]
	var entry := Vector2i(-1, -1)
	for index: int in range(1, steps.size()):
		var a: Dictionary = steps[index - 1]
		var b: Dictionary = steps[index]
		var from := Vector2i(int(a.site[0]), int(a.site[1]))
		var to := Vector2i(int(b.site[0]), int(b.site[1]))
		var exit_edge := RegionRoute.opposite(int(b.edge))
		var left: TerrainData = fetch.call(from)
		var right: TerrainData = fetch.call(to)
		if not _must(left != null and right != null, label + " route Site could not be built"): return false
		var out_cell := Adapter.boundary_cell(exit_edge, int(b.offset))
		var in_cell := Adapter.boundary_cell(int(b.edge), int(b.offset))
		var direction: Vector2i = TerrainData.DIRECTIONS[exit_edge]
		var pair := RegionSaveSlot.boundary_pair(from, out_cell, direction)
		if not _must(pair.ok and pair.site == to and pair.cell == in_cell, label + " crossing is not an original boundary pair"): return false
		if not _must(RegionSaveSlot.boundary_surfaces_can_step(RegionSaveSlot.boundary_surface(left, out_cell), RegionSaveSlot.boundary_surface(right, in_cell), direction),
			label + " crossing %s→%s at offset %d is a wall under the original rule" % [from, to, int(b.offset)]): return false
		if entry != Vector2i(-1, -1) and entry != out_cell:
			if not _must(not left.path_between(entry, out_cell).is_empty(), label + " leg inside %s has no original path" % from): return false
		entry = in_cell
	return true

# --- A. captain whole-team trip ------------------------------------------------------

func _captain_trip() -> bool:
	var team := _make_team()
	if team == null: return false
	var slot: RegionSaveSlot = controller.region_slot
	var initial_save := controller.save_to(controller.save_path)
	if not _must(initial_save.ok, "Initial save failed: " + str(initial_save)): return false
	var people: Array = []
	for index: int in range(team.combat_units.size()): people.append(team.combat_identity(index))
	people.append(lab.character.person_id)
	people.sort()
	var vehicles: Array = []
	for vehicle: Dictionary in controller.vehicles.records().values():
		if int(vehicle.team_id) == team.team_id: vehicles.append(str(vehicle.id))
	vehicles.sort()
	var initial := _state_census(lab.terrain.site, people, vehicles)
	if not _must(initial.people == people and initial.vehicles.size() == 2 and not initial.items.is_empty(), "Fixture census incomplete: " + str(initial)): return false
	# C. Refusals (no file or person changes).
	var generation := int(slot._marker.get("generation", 0))
	lab.terrain.site.combat_left = 5.0
	var refused := RegionTravelSite.depart(controller)
	lab.terrain.site.combat_left = 0.0
	if not _must(not refused.ok and refused.code == "IN_COMBAT", "Departure in combat was not refused: " + str(refused)): return false
	team.combat_hot_set(1, &"ko", 30.0)
	refused = RegionTravelSite.depart(controller)
	team.combat_hot_set(1, &"ko", 0.0)
	if not _must(not refused.ok and refused.code == "NOT_READY", "Departure with a downed member was not refused: " + str(refused)): return false
	var npc_faction := lab.npc.faction_id
	lab.npc.faction_id = npc_faction + 77
	var enemy_cell := lab.character.terrain_cell + Vector2i(6, 0)
	if not _must(lab.npc.place(enemy_cell, true) and lab.actor_present(lab.npc) and lab.npc.can_act()
		and lab.npc.terrain_cell == enemy_cell and lab.npc.faction_id != lab.character.faction_id, "Enemy refusal requires a real present living hostile body in range"): return false
	refused = RegionTravelSite.depart(controller)
	lab.npc.faction_id = npc_faction
	if not _must(not refused.ok and refused.code == "IN_COMBAT", "Departure beside an enemy was not refused: " + str(refused)): return false
	if not _must(int(slot._marker.get("generation", 0)) == generation and slot.region_travel_journey().is_empty(), "A refused departure published a commit"): return false
	# Departure.
	var from: Vector2i = controller._current_region_site()
	var departed := RegionTravelSite.depart(controller)
	if not _must(departed.ok, "Captain departure failed: " + str(departed)): return false
	var status := slot.region_travel_status()
	if not _must(status.ok and status.pending and not status.moving and str(slot.control.active_site_id).is_empty(), "Departure did not leave a stopped party and no active Site"): return false
	var party: Dictionary = slot.region_travel_party().party
	var party_census := RegionTravel.census(party)
	if not _must(party_census.people == people and party_census.vehicles == vehicles and party_census.items == initial.items, "Party census differs from the team: " + str(party_census)): return false
	var origin_left := _state_census(_saved_state(slot, from), people, vehicles)
	if not _must(origin_left.people.is_empty() and origin_left.items.is_empty() and origin_left.vehicles.is_empty(), "Departed people/items/vehicles remain in the origin save"): return false
	var departure := float(status.departure_game_seconds)
	# Route around the channel.
	var router := RegionData.new()
	router.load_manifest(manifest_path)
	var to := Vector2i(4, 0)
	var route := _original_party_route(slot, router, from, int(status.component), to)
	if not _must(route.ok, "Synthetic route failed: " + str(route)): return false
	var detour := false
	for step: Dictionary in route.steps:
		detour = detour or int(step.site[1]) == 2
		if not _must(not (int(step.site[0]) == 2 and int(step.site[1]) in [-1, 0, 1] and int(step.edge) == 3), "Route crossed the sea channel"): return false
	if not _must(detour, "Route did not detour around the channel: " + str(route.steps)): return false
	if not _prove_route(router, route.steps, "Synthetic") : return false
	report["synthetic_route"] = {"sites": route.steps.size(), "metres": route.metres, "site_builds": route.site_builds, "wall_ms": route.wall_ms}
	var planned := slot.set_region_travel_plan(route.steps)
	if not _must(planned.ok, "Plan rejected: " + str(planned)): return false
	var total_seconds := float(planned.game_seconds)
	# Travel: clock monotonic, equal to departure + published steps.
	var published := 0.0
	var last := float(slot.control.logical_game_seconds)
	var halfway := false
	while true:
		var advanced := slot.advance_region_travel(37)
		if not _must(advanced.ok, "Travel step failed: " + str(advanced)): return false
		var now := float(slot.control.logical_game_seconds)
		if not _must(now >= last, "World clock went backwards"): return false
		published += float(advanced.advanced)
		last = now
		if not _must(is_equal_approx(now - departure, published) and is_equal_approx(float(slot.region_travel_status().elapsed_game_seconds), published), "World clock differs from travel time: now=%.6f departure=%.6f published=%.6f status=%s" % [now, departure, published, str(slot.region_travel_status().get("elapsed_game_seconds"))]): return false
		if not halfway and published > total_seconds * 0.5:
			halfway = true
			if not _reopen_mid_journey(slot, people): return false
			published += reopen_extra
			last = float(slot.control.logical_game_seconds)
		if bool(advanced.arrived): break
	if not _must(published + 0.000001 >= total_seconds and published < total_seconds + RegionTravel.step_game_seconds() + 0.000001, "Arrival time is not the route time"): return false
	if not _must(slot.checkpoint_region_travel().ok, "Arrival checkpoint failed"): return false
	report["captain_trip"] = {"game_seconds": published, "route_seconds": total_seconds, "speed_mps": float(party.speed_mps)}
	# Arrival through the real world-open path.
	var arrived := controller.open_fixed_world(manifest_path, world_id, SLOT, Vector2i(-1, -1), false)
	if not _must(arrived.ok and bool(arrived.get("arrived", false)), "Arrival failed: " + str(arrived)): return false
	_freeze()
	var destination_slot: RegionSaveSlot = controller.region_slot
	if not _must(controller._current_region_site() == to and destination_slot.region_travel_journey().is_empty(), "Arrival did not bind the destination"): return false
	if not _must(float(destination_slot.control.logical_game_seconds) == departure + published, "Arrival changed the world clock"): return false
	var landed := _state_census(lab.terrain.site, people, vehicles)
	if not _must(landed.people == people and landed.items == initial.items and landed.vehicles == vehicles and landed.cargo == initial.cargo, "Arrival lost or changed people/items/vehicles: " + str(landed)): return false
	var origin_after := _state_census(_saved_state(destination_slot, from), people, vehicles)
	if not _must(origin_after.people.is_empty() and origin_after.items.is_empty(), "Origin save gained a duplicate"): return false
	if not _must(lab.terrain.site.manual.cargo == {"grain": 3}, "Hand cargo changed"): return false
	var arrived_team: TerrainArmy = lab.player_army()
	if not _must(arrived_team != null and arrived_team.combat_units.size() == 4 and arrived_team.formal_commander == TerrainArmy.PLAYER_MEMBER, "Team or captaincy not restored"): return false
	var entry := RegionRoute.entry_cell(route.steps.back())
	var leader := lab.character.terrain_cell
	if not _must(absi(leader.x - entry.x) + absi(leader.y - entry.y) <= 6, "Party did not land beside the entry pass %s (leader %s)" % [entry, leader]): return false
	var replay := destination_slot.commit_region_arrival(lab.terrain)
	if not _must(not replay.ok, "A committed arrival could be replayed"): return false
	report["captain_landing"] = {"entry": [entry.x, entry.y], "leader": [leader.x, leader.y]}
	return true

func _reopen_mid_journey(slot: RegionSaveSlot, people: Array) -> bool:
	var saved := slot.checkpoint_region_travel()
	if not _must(saved.ok, "Mid-journey checkpoint failed: " + str(saved)): return false
	var before := slot.region_travel_status()
	var source := RegionData.new()
	source.load_manifest(manifest_path)
	var reopened := RegionSaveSlot.new()
	if not _must(reopened.open_map(source, world_id, SLOT).ok, "Reopen failed"): return false
	var after := reopened.region_travel_status()
	if not _must(after.ok and after.pending and float(after.now) == float(before.now) and after.site == before.site
		and int(after.step_index) == int(before.step_index) and is_equal_approx(float(after.fraction), float(before.fraction)), "Reopened journey differs: %s vs %s" % [after, before]): return false
	var party_census := RegionTravel.census(reopened.region_travel_party().party)
	if not _must(party_census.people == people, "Reopened party lost people"): return false
	# Unsaved progress is not resurrected by a reopen: the commit is the truth.
	reopen_extra = float(slot.advance_region_travel(3).advanced)
	var again := RegionSaveSlot.new()
	again.open_map(source, world_id, SLOT)
	if not _must(float(again.region_travel_status().now) == float(before.now), "Reopen saw unpublished time"): return false
	report["mid_journey_reopen"] = {"site": [after.site.x, after.site.y], "step": int(after.step_index), "now": float(after.now)}
	return slot.checkpoint_region_travel().ok

# --- B. non-captain solo trip --------------------------------------------------------

func _solo_trip() -> bool:
	var team: TerrainArmy = lab.player_army()
	team.formal_commander = 0
	team.current_commander = 0
	team.combat_units[0].military_role = "officer"
	var team_people: Array = []
	for index: int in range(team.combat_units.size()): team_people.append(team.combat_identity(index))
	team_people.sort()
	var me := lab.character.person_id
	var from: Vector2i = controller._current_region_site()
	var slot: RegionSaveSlot = controller.region_slot
	var departed := RegionTravelSite.depart(controller)
	if not _must(departed.ok, "Solo departure failed: " + str(departed)): return false
	var party: Dictionary = slot.region_travel_party().party
	var census := RegionTravel.census(party)
	if not _must(census.people == [me] and census.vehicles.is_empty() and party.team_ids.is_empty(), "Solo party carried the team: " + str(census)): return false
	var stayed := _state_census(_saved_state(slot, from), team_people, [])
	if not _must(stayed.people == team_people, "Team did not stay behind"): return false
	for army: Dictionary in _saved_state(slot, from).armies:
		if not _must(army.get("player_member", {}).is_empty(), "Solo traveller is still a team member"): return false
	var router := RegionData.new()
	router.load_manifest(manifest_path)
	var to := Vector2i(5, 0)
	var route := _original_party_route(slot, router, from, int(slot.region_travel_status().component), to)
	if not _must(route.ok and _prove_route(router, route.steps, "Solo"), "Solo route failed: " + str(route)): return false
	if not _must(slot.set_region_travel_plan(route.steps).ok, "Solo plan rejected"): return false
	while not bool(slot.advance_region_travel(1000).arrived): pass
	slot.checkpoint_region_travel()
	var arrived := controller.open_fixed_world(manifest_path, world_id, SLOT, Vector2i(-1, -1), false)
	if not _must(arrived.ok, "Solo arrival failed: " + str(arrived)): return false
	_freeze()
	var here := _state_census(lab.terrain.site, [me] + team_people, [])
	if not _must(here.people == [me] and lab.player_army() == null, "Solo arrival brought the team or lost the player"): return false
	report["solo_trip"] = {"from": [from.x, from.y], "to": [to.x, to.y], "game_seconds": float(route.metres) / RegionTravel.WALK_MPS}
	return true

# --- D. back to a visited Site (exact cold replay) --------------------------------

func _return_to_visited() -> bool:
	var slot: RegionSaveSlot = controller.region_slot
	var departed := RegionTravelSite.depart(controller)
	if not _must(departed.ok, "Return departure failed: " + str(departed)): return false
	var router := RegionData.new()
	router.load_manifest(manifest_path)
	var to := Vector2i(0, 0)
	var route := _original_party_route(slot, router, controller._current_region_site(), int(slot.region_travel_status().component), to)
	if not _must(route.ok and slot.set_region_travel_plan(route.steps).ok, "Return route failed"): return false
	var origin_state := _saved_state(slot, to)
	var behind := float(slot.control.logical_game_seconds) - float(origin_state.get(RegionSaveSlot.SETTLEMENT_FIELD, {}).get("last_settled_game_seconds", 0.0))
	while not bool(slot.advance_region_travel(1000).arrived): pass
	slot.checkpoint_region_travel()
	behind = float(slot.control.logical_game_seconds) - float(origin_state.get(RegionSaveSlot.SETTLEMENT_FIELD, {}).get("last_settled_game_seconds", 0.0))
	var started := Time.get_ticks_msec()
	var result := controller.open_fixed_world(manifest_path, world_id, SLOT, Vector2i(-1, -1), false)
	var frames := 0
	while str(result.get("code", "")) == "PENDING" or controller.region_operation_pending():
		frames += 1
		if not _must(frames < 200000, "Cold replay did not finish"): return false
		result = controller.resume_region_operation()
		if controller.region_operation_pending(): continue
		if not result.ok and str(result.get("code", "")) != "PENDING": break
	if not _must(controller._current_region_site() == to and controller.region_slot.region_travel_journey().is_empty(), "Return arrival failed: " + str(result)): return false
	_freeze()
	var settled := RegionSaveSlot.validate_settlement(lab.terrain.site, controller.region_slot.control.logical_game_seconds)
	if not _must(settled.ok and float(settled.pending) <= 0.00001, "Visited Site not settled to the world clock"): return false
	report["visited_return_replay"] = {"behind_game_seconds": behind, "wall_ms": Time.get_ticks_msec() - started, "frames": frames}
	return true

# --- E. real Taiwan map: Yushan --------------------------------------------------------

func _yushan_routes() -> bool:
	var source := RegionData.new()
	if not _must(source.load_manifest().ok, "Taiwan manifest missing"): return false
	var samples := [[Vector2i(1228, 12981), Vector2i(1233, 12981)], [Vector2i(1228, 12981), Vector2i(1228, 12986)]]
	var results: Array = []
	var first_component := -1
	for pair: Array in samples:
		var from: Vector2i = pair[0]
		var built: Dictionary = source.make_terrain_data(from.x, from.y)
		if not _must(built.ok, "Yushan start Site unavailable"): return false
		var derived := RegionRoute.table_from_terrain(built.data)
		var component := -1
		for edge: int in range(4):
			for offset: int in range(100):
				var value := RegionRoute.edge_value(derived.table, edge, offset)
				if value != RegionRoute.CLOSED and component < 0: component = value
		if first_component < 0: first_component = component
		var route := _route(source, from, component, pair[1])
		if not _must(route.ok, "Yushan route failed: " + str(route)): return false
		if not _prove_route(source, route.steps, "Yushan"): return false
		var closed := 0
		var open := 0
		for edge: int in range(4):
			for offset: int in range(100):
				if RegionRoute.edge_value(derived.table, edge, offset) == RegionRoute.CLOSED: closed += 1
				else: open += 1
		results.append({"from": [from.x, from.y], "to": [pair[1].x, pair[1].y], "sites": route.steps.size(), "metres": route.metres,
			"site_builds": route.site_builds, "wall_ms": route.wall_ms, "start_edge_open": open, "start_edge_closed": closed})
	# The cached tables answer a second search without new Site builds.
	var cached := _route(source, samples[0][0], first_component, samples[0][1])
	if not _must(cached.ok and int(cached.site_builds) == 0, "Cached Yushan route rebuilt Sites"): return false
	report["yushan"] = results
	report["yushan_cached_rerun_ms"] = cached.get("wall_ms", -1.0)
	return true
