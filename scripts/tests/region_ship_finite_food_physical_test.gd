extends "res://scripts/tests/region_siege_cold_action_epoch_test.gd"
## NEW Source-only physical fixture. Each runtime assertion is NOT_RUN until Root.
## Explicit test-only boat genesis is separate from false-dispatch public work.
## Crowd port (2026-11-08, Option C batch 1): since the 11/03 neutral team-row player a new world binds straight
## into a live native crowd, so the fixture is built from crowd teams (region_crowd_ship_sea_departure_test pattern):
## - the player's start person (ship_actor_id) stays ashore at (30,21) as the source person, in its own team;
## - a two-person ship team stands on the two boat contacts; control moves to its captain (ship_commander_id) for the
##   public ship, cargo and food work, as the old Actor Captain held it;
## - a one-person resident team stands at (31,24), as the old recipient team did;
## - the closure returns control to the shore person; the ship team, whole and aboard, leaves as an NPC crowd party.
## The grid PLAYER_MEMBER join/leave and serving-cadre succession checks have no crowd form (a crowd person changes
## teams only through a cadre split); crowd cadre rules are covered by region_crowd_cadre_split_test.
const ShipCoastGenesis = preload("res://scripts/tests/region_ship_coast_legal_named_genesis.gd")
const ShipGarrison = preload("res://scripts/terrain_lab/site_garrison.gd")
const PhysicalSustain = preload("res://scripts/terrain_lab/site_sustain.gd")
var ship_faction := 0 # The shore side's authored faction; a subclass may set another in _initialize.
var ship_team_id := 0
var ship_actor_id := 0 # The shore (start) person; controlled again after the closure.
var ship_commander_id := 0 # The controlled ship-team captain during the public ship work.
var ship_resident_team_id := 0
var ship_people: Array[int] = []
var ship_ids: Array[String] = []
var ship_barriers: Array[String] = []
var ship_observation := "settled"
var ship_cold_evidence: Array[Dictionary] = []
var ship_food_initial := 8.0
var ship_consumed_rations := 0.0
var ship_food_party_token := ""
var ship_food_source_site := ""
var ship_food_results: Array[Dictionary] = []

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 300000
	out = "res://.godot-temp/region_c06_ship_physical/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if last_world_exists: last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	action_speed = 1.0
	action_fault = "none"
	action_coordinate = Vector2i.ZERO
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not finished and Time.get_ticks_msec() > deadline: _finish(false, "300-second original ship physical deadline")
	return false

func _write_manifest() -> bool:
	return ShipCoastGenesis.write(self)

## The ship team's crowd person owner (CrowdPersonOwner), or null.
func _ship_team() -> Variant:
	if action_owner.crowd_site == null or not action_owner.crowd_site.active: return null
	for owner: Variant in action_owner.crowd_site.person_owners():
		if owner is CrowdPersonOwner and int(owner.team_id) == ship_team_id: return owner
	return null

## A subclass's further authored owners (Nations, destination Sites), born before the first paid interval.
func _ship_more_genesis() -> bool:
	return true

## Further crowd teams ({"side", "cells"}) a subclass deploys together with the ship and resident teams: a live crowd
## deploys only whole, so every authored team is born in the same deploy.
func _ship_extra_teams() -> Array:
	return []

## The crowd person owner whose living member stands at cell on the action owner, or null.
func _crowd_owner_at(cell: Vector2i) -> Variant:
	if action_owner.crowd_site == null or not action_owner.crowd_site.active: return null
	for owner: Variant in action_owner.crowd_site.person_owners():
		if not owner is CrowdPersonOwner: continue
		for index: int in owner.records:
			var person: Dictionary = owner.person(index, false)
			if not person.is_empty() and person.cell == cell: return owner
	return null

## Failure evidence only: up to `cap` differing paths between two fact trees.
func _ship_differences(first: Variant, second: Variant, path: String, cap: int, found: Array = []) -> Array:
	if found.size() >= cap: return found
	if typeof(first) != typeof(second):
		found.append("%s type %d != %d" % [path, typeof(first), typeof(second)])
		return found
	if first is Dictionary:
		for key: Variant in first:
			if not second.has(key): found.append("%s/%s missing after" % [path, str(key)])
			else: _ship_differences(first[key], second[key], path + "/" + str(key), cap, found)
		for key: Variant in second:
			if not first.has(key): found.append("%s/%s added after" % [path, str(key)])
		return found
	if first is Array:
		if first.size() != second.size(): found.append("%s size %d != %d" % [path, first.size(), second.size()]); return found
		for index: int in first.size(): _ship_differences(first[index], second[index], "%s[%d]" % [path, index], cap, found)
		return found
	if first != second: found.append("%s %s != %s" % [path, str(first).left(120), str(second).left(120)])
	return found

var ship_position_trace: Array = []

## Failure evidence only: the person dict cell, the record's cell and the native position.
func _ship_position_fact(identity: int, label: String) -> Dictionary:
	var owner: Variant = _ship_team()
	if owner == null: return {"label": label}
	var person: Dictionary = owner.person(int(owner.index_for_identity(identity)), false)
	var index := int(action_owner.crowd_site.crowd.soldier_index(identity))
	var state: Dictionary = action_owner.crowd_site.soldier_state(index) if index >= 0 else {}
	return {"label": label, "cell": person.get("cell"), "record_cell": person.get("body", {}).get("cell"), "px": state.get("px"), "py": state.get("py"),
		"embarked": person.get("body", {}).get("embarked_vehicle_id", ""), "aboard": owner.native_aboard(int(owner.index_for_identity(identity)))}

## Failure evidence only: which delivery job fields are registered Region owner references (by key), or inline.
func _ship_delivery_ref_facts() -> Dictionary:
	var job: Dictionary = _ship_supply().get("delivery", {})
	if job.is_empty(): return {}
	var refs: Dictionary = action_owner._region_owner_references()
	var result := {}
	for field: Variant in job:
		var value: Variant = job[field]
		if not (value is Dictionary or value is Array or value is Object): continue
		var found := "inline"
		for key: String in refs:
			if is_same(refs[key], value): found = key; break
		result[str(field)] = found
	return result

## Failure evidence only: which ship-supply admission check refuses (prepare_ship_supply's version-3 branch).
func _ship_sustain_diag() -> Dictionary:
	var controller_ref: SiteController = action_owner.site_controller
	var entry: Dictionary = controller_ref._supply_entry(_ship_team())
	if entry.is_empty(): return {"entry": "none"}
	var checked: Dictionary = entry.sustain.duplicate(true)
	var aligned: bool = controller_ref._align_supply_clock(checked, SiteRuntime.now(action_owner.terrain) * 60.0)
	var location_keys: Array = entry.get("locations", {}).keys()
	var per_location := {}
	for key: Variant in location_keys: per_location[str(key)] = controller_ref._supply_location_valid(_ship_team(), str(key))
	return {"version": entry.get("version"), "delivery_empty": entry.delivery.is_empty(), "aligned": aligned, "sustain_at": entry.sustain.get("at"),
		"site_now": SiteRuntime.now(action_owner.terrain) * 60.0, "locations_valid": controller_ref._supply_locations_valid(_ship_team(), entry.get("locations", {})),
		"per_location": per_location, "sustain_valid": PhysicalSustain.validate(checked, controller_ref.captivity_supply._all_members())}

## Failure evidence only: who may order this person now.
func _ship_authority_facts(identity: int) -> Dictionary:
	var team: Variant = _ship_team()
	if team == null: return {"team": null}
	var state: Dictionary = action_owner.crowd_site.formation_state(int(team.formation_index))
	return {"controlled": action_owner.controlled_person_id(), "commander_id": ship_commander_id, "person": identity,
		"current_person": int(state.get("current_person", -1)), "eligible": action_owner.crowd_site._command_eligible(state),
		"formation": state, "people": ship_people}

## A ship person's saved row: the crowd record (its body) for a crowd soldier.
func _ship_row_fact(person: Dictionary) -> Dictionary:
	if person.owner is TerrainArmy: return person.owner.materialized_combat_rows()[int(person.unit)].duplicate(true)
	# A crowd record's cell and crowd_position are the projection its last capture wrote; the live body is the native
	# soldier. Both sides of every comparison read the live native position, as the GD row is always current.
	var row: Dictionary = person.row.duplicate(true)
	var index := int(action_owner.crowd_site.crowd.soldier_index(int(person.id)))
	if index >= 0:
		var state: Dictionary = action_owner.crowd_site.soldier_state(index)
		row["cell"] = [int(person.cell.x), int(person.cell.y)]
		row["crowd_position"] = [float(state.px), float(state.py)]
		# Fatigue lives in the formation's native pool; the record holds the last capture's copy.
		for field: StringName in [&"fatigue", &"fatigue_rest"]:
			if row.has(String(field)): row[String(field)] = float(person.owner.combat_hot_get(int(person.unit), field, row[String(field)]))
	return row

## A crowd team side as region_crowd_journey_test builds it.
func _ship_side(count: int) -> Dictionary:
	var parsed: Dictionary = lab._trial_side_settings({"friendly_count": count, "friendly_training": 0,
		"friendly_female_percent": 0, "friendly_attack": false, "friendly_ai_enabled": false}, "friendly")
	if not _check(parsed.ok, "original crowd side settings accepted", parsed): return {}
	var side: Dictionary = parsed.side
	side["faction"] = ship_faction
	return side

## The origin Site after an extraction still holds this person in one of its team rosters.
func _ship_origin_holds(origin: Dictionary, person_id: int) -> bool:
	for army: Variant in origin.get("armies", []):
		if not army is Dictionary: continue
		for unit: Variant in army.get("units", []):
			if unit is Dictionary and int(unit.get("person_id", -1)) == person_id: return true
	return false

## Moves control between two crowd persons, as region_crowd_ship_sea_departure_test does.
func _ship_control(from_id: int, to_id: int) -> bool:
	var switched: Dictionary = action_owner.crowd_site.on_control_changed(from_id, to_id)
	if not _check(switched.ok, "crowd control moves to the named person", {"from": from_id, "to": to_id, "result": switched}): return false
	action_owner.terrain.site["controlled_person_id"] = to_id
	return _check(action_owner.controlled_person_id() == to_id, "the Site controls the named person", to_id)

## A crowd Site restores natively; the inherited selected restore admits only the GD backend. A Site saved with
## no crowd section (no people) still binds through GD.
func _restore_selected(data: TerrainData, reopened: RegionSaveSlot, cold_mode: bool) -> TerrainLab:
	var crowd_saved := data.site.has("crowd")
	var scene := _shell()
	if not _check(scene != null, "fresh actual original restore scene exists"): return null
	# The restored main owner stands for the game's main Lab, whose _ready requests the crowd unless --grid (as the
	# first shell in _setup_action_world); a cold owner stays a restore owner.
	if not cold_mode: scene.crowd_startup_requested = not OS.get_cmdline_user_args().has("--grid")
	var prepared := scene.prepare_selected_region_owner_restore(data, reopened)
	if not _check(prepared.ok, "original selected private preflight validates whole actual owner graph", prepared): return null
	scene.restore_only = cold_mode
	scene.site_controller.region_slot = reopened
	scene.bind_terrain(prepared.data, prepared)
	_freeze(scene)
	var actual := scene.region_bind_receipt(prepared.data)
	var native_ok: bool = str(actual.get("backend", "")) == "native" and scene.crowd_site != null and scene.crowd_site.active
	if not _check(actual.ok and actual.complete and actual.owners_restored and actual.effects_complete
		and (native_ok if crowd_saved else str(actual.get("backend", "")) == "gd"), "positive selected bind restores every actual owner (a saved crowd natively)", actual): return null
	return scene

func _ship_vehicle(index: int) -> Dictionary:
	return action_owner.terrain.site.vehicles.get(ship_ids[index], {})

func _action_vehicle() -> Dictionary:
	return {} if ship_ids.is_empty() else _ship_vehicle(0)

func _ship_supply() -> Dictionary:
	return action_owner.site_controller._supply_entry(_ship_team())

func _ship_build_barrier(anchor: Vector2i, length: int) -> bool:
	var data := action_owner.terrain
	# A 1-wide north-south wall faces its work entrance east (quarter 3), on the
	# ship side the builder stands on. The default south quarter offers only the cell
	# below a segment's end, which for the last segment (ending at y 99) is off the map.
	var options := {"owner_faction": ship_faction, "quarter": 3}
	var layout: Dictionary = SiteRuntime.building_cells(data, "stone_wall", anchor, Vector2i(1, length), options)
	if not _check(layout.ok, "original legal land barrier layout respects per-request limits", layout): return false
	var cells: Array[int] = []; cells.assign(layout.cells)
	var before: Dictionary = data.site.inventory.duplicate(true)
	var built: Dictionary = SiteRuntime.request_build(data, "stone_wall", cells, Callable(), options)
	if not _check(built.ok, "GENESIS original wall request pays finite materials once", built): return false
	var key := str(built.feature)
	var feature: Dictionary = data.site.features[key]
	for resource: String in feature.cost:
		if not _check(int(data.site.inventory.get(resource, 0)) == int(before.get(resource, 0)) - int(feature.cost[resource]), "GENESIS wall material debit is exact", resource): return false
	var task := {"version": 2, "zone": -1, "target": "feature:" + key, "action": "construct", "work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
	SiteRuntime._feature_work(data, key, float(feature.work), Callable(), Callable(), task, {}, 20, ship_faction)
	if not _check(str(feature.stage) == "complete", "GENESIS original structural work finishes without terrain or HP rewriting", key): return false
	ship_barriers.append(key)
	return true

func _setup_action_world() -> bool:
	lab = _shell()
	if not _check(lab != null, "original restore shell exists"): return false
	# The shell enters the tree as a restore owner (no crowd startup). The live main Lab of the game starts as an
	# ordinary scene, whose _ready requests the crowd unless --grid; this live owner does the same before its bind.
	lab.crowd_startup_requested = not OS.get_cmdline_user_args().has("--grid")
	controller = lab.site_controller
	var archive := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(32, 32)})
	Env.initialize(archive, "c06-ship-original:archive")
	lab.bind_terrain(archive)
	lab.restore_only = false
	controller.save_root = out.path_join("archive")
	world_id = "r0_siege_action_%d_ship_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened: Dictionary = controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "original Controller creates one named fixed coast World", opened): return false
	_freeze(lab)
	slot = controller.region_slot
	action_owner = lab
	lab.simulation_speed = action_speed
	var wired: Dictionary = lab._wire_region_gameplay_adapters(slot)
	if not _check(wired.ok, "original common Slot adapters wire the actual active owner", wired): return false
	var data := lab.terrain
	for key: String in data.resource_base: Env.change(data, key, {"cleared": true, "remaining": 0})
	data.site.capacity = 100000
	for resource: String in Env.ITEM_NAMES: data.site.inventory[resource] = 1000
	# The authored genesis food is finite grain only. Every other original food would
	# be taken first (Sustain.FOODS order: fish, meat, wild_food, grain) by a Depot fill.
	for food: String in PhysicalSustain.FOODS: data.site.inventory[food] = 0
	data.site.inventory.grain = int(ship_food_initial)
	data.site.depot_cell = data.index(Vector2i(30, 20))
	if not _check(SiteRuntime.initialize_item_storage(data.site).ok, "original Depot owns the finite authored genesis grain and building stock"): return false
	# Neutral part 2: the bind opens the Site as the player's live native one-person team.
	var bound: Dictionary = lab.region_bind_receipt(data)
	if not _check(bound.get("complete") == true and str(bound.get("backend", "")) == "native" and lab.crowd_site != null and lab.crowd_site.active and float(data.site.get("combat_left", 0.0)) <= 0.0,
		"a new world binds straight into the player's live native crowd team", bound): return false
	ship_actor_id = lab.controlled_person_id()
	# region_crowd_offscreen_step_test: clear the player's crowd team back to its holder before the test sides deploy,
	# and give it the test faction (neutral is hostile to everyone). The shore person stands at the dry shore (30,21).
	var cleared: Dictionary = lab.crowd_site.clear()
	if not _check(cleared.get("ok", false) == true and not lab.crowd_site.active, "the player's crowd team returns to its holder before the test sides deploy", cleared): return false
	var start_team: TerrainArmy = null
	for team: TerrainArmy in lab.combat_armies:
		if team.has_army() and team.combat_identity(0) == ship_actor_id: start_team = team
	if not _check(start_team != null and start_team.combat_units.size() == 1 + TerrainLab.INITIAL_CADRES, "the player's start team holds the shore person and its cadres", start_team.combat_units.size() if start_team != null else -1): return false
	start_team.faction_id = ship_faction
	# The shore person and its start cadres stand on dry land east of both boat contacts and their walks.
	var shore_cells: Array[Vector2i] = [Vector2i(38, 23), Vector2i(39, 23), Vector2i(40, 23), Vector2i(41, 23), Vector2i(42, 23), Vector2i(43, 23)]
	for index: int in start_team.combat_units.size():
		if not _check(data.is_walkable(shore_cells[index]), "a dry shore cell holds each start-team person", shore_cells[index]): return false
		start_team.cells[index] = shore_cells[index]
		start_team.moving_to[index] = TerrainArmy.INVALID_CELL
	var ship_side := _ship_side(2)
	var resident_side := _ship_side(1)
	if ship_side.is_empty() or resident_side.is_empty(): return false
	# region_crowd_ship_sea_departure_test: the ship team deploys inland (a crowd team on the contacts would block the
	# hull deploy) and walks to the two genuine shore contacts after the boats exist.
	var ship_cells: Array[Vector2i] = [Vector2i(30, 20), Vector2i(35, 20)]
	var inland_cells: Array[Vector2i] = [Vector2i(30, 23), Vector2i(35, 23)]
	var resident_cells: Array[Vector2i] = [Vector2i(31, 25)]
	var sides: Array = [ship_side, resident_side]
	var formations: Array = [inland_cells, resident_cells]
	for extra: Dictionary in _ship_extra_teams():
		sides.append(extra.side)
		formations.append(extra.cells)
	var entered: Dictionary = lab.crowd_site.deploy(sides, formations)
	if not _check(entered.get("ok", false) == true and lab.crowd_site.active, "the ship and resident crowd teams deploy with the shore person", entered): return false
	var ship_owner: Variant = _crowd_owner_at(inland_cells[0])
	var resident_owner: Variant = _crowd_owner_at(resident_cells[0])
	if ship_owner != null: ship_team_id = int(ship_owner.team_id)
	if resident_owner != null: ship_resident_team_id = int(resident_owner.team_id)
	var source: Variant = _ship_team()
	if not _check(source != null and ship_resident_team_id > 0, "the two-person ship team and the resident team have crowd owners"): return false
	for cell: Vector2i in inland_cells:
		for index: int in source.records:
			if source.person(index, false).cell == cell: ship_people.append(source.combat_identity(index))
	ship_commander_id = source.combat_identity(int(source.current_commander))
	if not _check(ship_people.size() == 2 and ship_people.has(ship_commander_id) and source.command_eligible(int(source.current_commander)), "the two ship bodies stand inland and their captain is eligible", ship_people): return false
	if not _ship_control(ship_actor_id, ship_commander_id): return false
	if not _check(lab.crowd_site.person_owner(ship_actor_id) != null and not ship_people.has(ship_actor_id), "the shore person stays ashore in its own team"): return false
	for anchor: Vector2i in [Vector2i(30, 19), Vector2i(35, 19)]:
		var boat: Dictionary = controller.vehicles.deploy_ship(source, "ferry", anchor, Vector2i.LEFT, true)
		if not _check(boat.ok, "explicit original TEST_ONLY boat genesis admits complete hull and unique owner; production is outside scope", boat): return false
		ship_ids.append(str(boat.vehicle_id))
	if not _check(ship_ids.size() == 2 and ship_ids[0] != ship_ids[1] and controller.vehicles.ship_contacts(_ship_vehicle(0)).has(ship_cells[0]) and controller.vehicles.ship_contacts(_ship_vehicle(1)).has(ship_cells[1]), "two original full hulls have their genuine distinct shore contacts"): return false
	var person: Dictionary = controller.vehicles.ship_person(ship_people[0])
	var stocked: Dictionary = SiteRuntime.transfer_items(data, data.site.depot_items, data.site.inventory, person.holder, person.cargo, {"wood": 2}, [], int(data.site.depot_items.version), int(person.holder.version), SiteRuntime.CARRY_CAPACITY)
	if not _check(stocked.ok and int(person.cargo.get("wood", 0)) == 2, "GENESIS existing finite Depot stock transfers to the true row holder once", stocked): return false
	for segment: Vector2i in [Vector2i(20, 36), Vector2i(56, 36), Vector2i(92, 8)]:
		if not _ship_build_barrier(Vector2i(25, segment.x), segment.y): return false
	if not _check(data.path_between(Vector2i(30, 21), Vector2i(20, 21)).is_empty(), "original completed barrier closes the entire ground approach while source ocean stays open"): return false
	action_context = {"key": ship_ids[0], "crew": ship_people.duplicate(), "commander": ship_commander_id}
	if not _check(action_paid == 0.0 and action_game_paid == 0.0, "all named geography, body/boat birth and initial material work precede paid simulation"): return false
	var saved: Dictionary = controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(saved.ok, "original joint publisher stores authored owner graph and initial holders", saved): return false
	var due: Dictionary = slot.consume_due_region_events()
	if not _check(due.ok and due.get("complete", false), "original same-point owners settle before actual positive intervals", due): return false
	if not _ship_more_genesis(): return false
	# Each ship body walks to its own boat's contact through paid shared steps (crowd siege approach step). This is the
	# first paid interval: every authored owner, Nation and Site above is born before it.
	for index: int in ship_people.size():
		if not await _ship_walk_to_contact(ship_people[index], ship_cells[index]): return false
	return true

func _ship_walk_to_contact(identity: int, contact: Vector2i) -> bool:
	var owner: Variant = _ship_team()
	var arrived := func() -> bool:
		var person: Dictionary = owner.person(int(owner.index_for_identity(identity)), false)
		if person.is_empty(): return false
		if person.cell == contact and not bool(person.moving): return true
		if not bool(person.moving): action_owner.crowd_site.siege_approach_step(identity, contact)
		return false
	return await _ship_until(arrived, "the ship body walks to its genuine shore contact")

## Failure evidence only: the world clock, the due events and every bound owner's fire watermark and cursor.
func _ship_clock_diag() -> Dictionary:
	var clock: Dictionary = slot.control.fire_clock
	var journal: Array = clock.get("journal", [])
	var owners := {}
	for site_id: Variant in slot._region_original_labs:
		var owner: Variant = slot._region_original_labs[site_id]
		if not is_instance_valid(owner) or not owner is TerrainLab or owner.terrain == null: continue
		owners[str(site_id)] = {"fire": owner.terrain.site.get("fire_settlement", {}).duplicate(true), "cursor": owner.fire_action_cursor,
			"pending": owner._region_point_pending.duplicate(true), "restore_only": owner.restore_only, "native": owner.crowd_site != null and owner.crowd_site.active}
	var due: Array = []
	for event: Dictionary in slot.region_registry().events:
		if str(event.get("status", "")) != "complete": due.append({"id": event.id, "kind": event.kind, "at": event.at, "status": event.status})
	return {"world": slot.control.logical_game_seconds, "clock": {"epoch": clock.get("epoch"), "sequence": clock.get("sequence"), "action": clock.get("action_seconds"),
		"base_sequence": clock.get("base_sequence"), "journal_tail": journal.slice(maxi(0, journal.size() - 2))},
		"main": {"site": str(lab.terrain.site.id), "fire": lab.terrain.site.get("fire_settlement", {}).duplicate(true), "cursor": lab.fire_action_cursor, "pending": lab._region_point_pending.duplicate(true)},
		"owners": owners, "open_events": due}

func _paid_ship_step(request: float = TerrainLab.EXCHANGE_ACTION_STEP) -> bool:
	if not _observe_ship_food_results(): return false
	var before_clock := _ship_clock_diag()
	var result: Dictionary = lab._advance_original_shared_step(request)
	if not _check(result.get("ok", false), "original common producer accepts actual ship/body/food work or due zero endpoint",
		result if result.get("ok", false) else {"result": result, "before": before_clock, "after": _ship_clock_diag()}): return false
	if result.get("completed", false):
		if not _check(float(result.action_seconds) > 0.0 and float(result.game_seconds) > 0.0 and float(result.action_seconds) <= request + EPS, "one accepted original bounded positive interval owns both clocks", result): return false
		action_paid += float(result.action_seconds); action_game_paid += float(result.game_seconds)
		if action_trace.size() < 4000: action_trace.append({"action": result.action_seconds, "game": result.game_seconds, "observation": ship_observation, "world": slot.control.logical_game_seconds, "action_at": slot.control.fire_clock.action_seconds})
	else:
		if not _check(float(result.get("action_seconds", 0.0)) == 0.0 and float(result.get("game_seconds", 0.0)) == 0.0, "original due endpoint consumes zero elapsed work", result): return false
	return _observe_ship_food_results()

func _action_step() -> bool:
	return _paid_ship_step()

func _ship_until(predicate: Callable, label: String) -> bool:
	for count: int in range(18000):
		if predicate.call(): return _check(true, label)
		if Time.get_ticks_msec() > deadline: return _check(false, label + " exceeded deadline", {"jobs": _ship_job_facts(), "observation": ship_observation, "paid": action_paid,
			"positions": [_ship_position_fact(ship_people[0], "p0"), _ship_position_fact(ship_people[1], "p1")]})
		if not _paid_ship_step(): return false
		if count % 60 == 0: await process_frame
	return _check(false, label + " exceeded bounded original caller attempts", {"jobs": _ship_job_facts(), "observation": ship_observation, "paid": action_paid, "world": slot.control.logical_game_seconds})

func _ship_job_facts() -> Dictionary:
	var result := {}
	for identity: int in ship_people:
		var job: Dictionary = action_owner.site_controller.person_actions._jobs.get(str(identity), {})
		var fields := {}
		for field: String in ["kind", "executor_id", "requester_id", "vehicle_id", "berth_id", "duration", "elapsed", "shore", "path", "test_dispatch", "retreat"]:
			if job.has(field): fields[field] = job[field]
		result[str(identity)] = fields
	return result

func _action_facts() -> Dictionary:
	var bodies := {}
	for identity: int in ship_people:
		var person: Dictionary = action_owner.site_controller.vehicles.ship_person(identity)
		if person.is_empty(): bodies[str(identity)] = {"missing": true}; continue
		bodies[str(identity)] = {"row": _ship_row_fact(person), "cell": person.cell, "moving": person.moving, "holder": person.holder.duplicate(true), "cargo": person.cargo.duplicate(true)}
	var supply := _ship_supply()
	var delivery := {}
	for field: String in ["requester_id", "player_id", "representative_id", "quantity", "left", "pending", "target_location", "source_version", "source_cell", "target_cell"]:
		if supply.get("delivery", {}).has(field): delivery[field] = supply.delivery[field]
	return {"vehicles": action_owner.terrain.site.vehicles.duplicate(true), "people": bodies, "jobs": _ship_job_facts(), "sustain": supply.get("sustain", {}).duplicate(true), "locations": supply.get("locations", {}).duplicate(true), "supply_revision": int(supply.get("revision", 0)), "delivery": delivery, "depot": action_owner.terrain.site.inventory.duplicate(true), "depot_holder": action_owner.terrain.site.depot_items.duplicate(true), "items": action_owner.terrain.site.item_records.duplicate(true), "captain": _ship_team().combat_identity(_ship_team().current_commander), "controlled": action_owner.controlled_person_id()}

func _partial_ready() -> bool:
	if ship_observation == "delivery":
		var job: Dictionary = _ship_supply().get("delivery", {})
		return not job.is_empty() and float(job.left) > EPS and float(job.left) < 2.0 + 0.2 * float(job.quantity) - EPS
	if ship_observation == "move":
		var move: Dictionary = _ship_vehicle(0).move
		return not move.is_empty() and float(move.elapsed) > EPS and float(move.elapsed) < float(move.duration) - EPS
	if ship_observation in ["board", "helm"]:
		for job: Dictionary in action_owner.site_controller.person_actions._jobs.values():
			if str(job.kind) in ["ship_board", "ship_helm"] and float(job.elapsed) > EPS and float(job.elapsed) < float(job.duration) - EPS: return true
		return false
	return true

func _reopen_actual_partial() -> bool:
	if not _observe_ship_food_results(): return false
	var facts := _action_facts()
	var clock := [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]
	var refs_before := _ship_delivery_ref_facts()
	var saved: Dictionary = controller.checkpoint_region_internal("region_checkpoint", true)
	if not saved.ok: print("SHIP_DIAG delivery refs before=", refs_before, " after=", _ship_delivery_ref_facts())
	var after_facts := _action_facts()
	# Crowd records read back from a saved JSON carry whole numbers as floats until a capture rewrites them; the facts are
	# compared in the Store's own saved JSON domain, as every reopen comparison here does.
	if not _check(saved.ok and _saved_json_domain(facts) == _saved_json_domain(after_facts) and clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "joint fullgraph checkpoint consumes no additional job, food, transfer or time",
		{"saved": saved.get("code", "OK"), "differences": _ship_differences(facts, after_facts, "facts", 12), "clock": [clock, [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence]]}): return false
	var graph := _action_graph()
	if graph.is_empty(): return false
	var proof := slot.region_bind_proof(action_owner.terrain)
	var generation := int(slot._marker.generation)
	var reopened := RegionSaveSlot.new()
	var opened: Dictionary = reopened.open_map(slot.source, world_id, "main")
	if not _check(opened.ok and int(reopened._marker.generation) == generation, "fresh original Slot selects the exact same whole epoch", opened): return false
	var read: Dictionary = reopened.open_site(Vector2i.ZERO)
	if not _check(read.ok and read.data.site.has("region_snapshot"), "mode-aware original open retains complete active physical owner graph", read.get("code")): return false
	var restored := _restore_selected(read.data, reopened, false)
	if restored == null: return false
	lab = restored; controller = lab.site_controller; slot = reopened; action_owner = lab
	lab.simulation_speed = action_speed
	var next_graph := _action_graph()
	# The facts cross a saved JSON round trip and a fresh original Lab: the restored
	# rows read back whole-number ids as floats (person_id 3.0, target -1.0). Compare
	# them in the store's own saved JSON domain, as the inherited helper does. The
	# owner graph is stored in that same JSON (its floats are plain JSON numbers), so
	# it is compared in that domain too, exactly as the inherited reopen compares it;
	# partial job, bind proof and clocks stay exact.
	if not _check(not next_graph.is_empty() and _saved_json_domain(facts) == _saved_json_domain(_action_facts()) and _saved_json_domain(graph) == _saved_json_domain(next_graph) and _partial_ready() and proof == slot.region_bind_proof(action_owner.terrain) and clock == [slot.control.logical_game_seconds, slot.control.fire_clock.action_seconds, slot.control.fire_clock.sequence], "true cold bind restores every original body/boat/job/holder alias and both clocks", ship_observation): return false
	# A manual fresh-Slot reopen wires the restored main original as the common
	# adapter host, as the original controller did for the first Slot (the inherited
	# reopen does the same after its own graph comparison).
	var rewired := lab._wire_region_gameplay_adapters(slot)
	if not _check(rewired.ok, "fresh Slot adapters wire to the positively restored main original", rewired): return false
	if not _observe_ship_food_results(): return false
	var before := var_to_bytes([slot.control, _action_facts(), next_graph])
	var retry: Dictionary = slot.consume_due_region_events()
	var retry_graph := _action_graph()
	if not _check(retry.ok and retry.get("complete", false) and before == var_to_bytes([slot.control, _action_facts(), retry_graph]), "same selected endpoint retry replays no work, meal or load/unload", retry): return false
	if not _observe_ship_food_results(): return false
	ship_cold_evidence.append({"observation": ship_observation, "proof": proof, "generation": generation, "clock": clock, "graph_sha256": SiegeCheckpoint.state_hash(graph), "whole_graph_equal": true, "facts": facts})
	return true

func _ship_public_cargo() -> bool:
	var owner: SiteController = action_owner.site_controller
	var person: Dictionary = owner.vehicles.ship_person(ship_people[0])
	var boat := _ship_vehicle(0)
	var before := [int(person.holder.version), int(boat.holder.version)]
	var loaded: Dictionary = owner.vehicles.transfer("person:" + str(ship_people[0]), ship_ids[0], {"wood": 2}, [], before[0], before[1], ship_commander_id, false)
	if not _check(loaded.ok and int(person.cargo.get("wood", 0)) == 0 and int(boat.cargo.get("wood", 0)) == 2 and int(person.holder.version) == before[0] + 1 and int(boat.holder.version) == before[1] + 1, "false-dispatch public LOAD moves the finite actual person stack and both versions exactly once", loaded): return false
	var source := var_to_bytes([person.cargo, person.holder, boat.cargo, boat.holder, slot.control])
	var empty: Dictionary = owner.vehicles.transfer("person:" + str(ship_people[0]), ship_ids[0], {"wood": 2}, [], int(person.holder.version), int(boat.holder.version), ship_commander_id, false)
	if not _check(not empty.ok and source == var_to_bytes([person.cargo, person.holder, boat.cargo, boat.holder, slot.control]), "actual empty source refuses a second finite LOAD without extra stock/version/time", empty): return false
	var unloaded: Dictionary = owner.vehicles.transfer(ship_ids[0], "person:" + str(ship_people[0]), {"wood": 2}, [], int(boat.holder.version), int(person.holder.version), ship_commander_id, false)
	return _check(unloaded.ok and int(person.cargo.get("wood", 0)) == 2 and int(boat.cargo.get("wood", 0)) == 0 and int(person.holder.version) == before[0] + 2 and int(boat.holder.version) == before[1] + 2, "false-dispatch public UNLOAD returns the same finite stack through real shore contact", unloaded)

func _ship_board(index: int, cold_partial: bool) -> bool:
	ship_observation = "board"
	var begun: Dictionary = action_owner.site_controller.person_actions.begin_ship_board(ship_people[index], ship_ids[index], ship_commander_id, 1, false)
	if not _check(begun.ok and not action_owner.site_controller.vehicles.is_embarked(ship_people[index]), "false-dispatch public boarding creates a pending true job without premature attachment", {"result": begun, "authority": _ship_authority_facts(ship_people[index])}): return false
	if cold_partial:
		if not await _ship_until(func() -> bool: return _partial_ready(), "actual paid boarding obtains a true partial interval"): return false
		if not await _reopen_actual_partial(): return false
	# The job ends either committed (embarked) or refused; a refusal is reported at once, not at the deadline.
	if not await _ship_until(func() -> bool: return not action_owner.site_controller.person_actions.is_busy(ship_people[index]), "original paid boarding job ends"): return false
	if not _check(action_owner.site_controller.vehicles.is_embarked(ship_people[index]), "original paid boarding commits its actual berth exactly once",
		{"refusal": action_owner.get_meta(&"last_refused_result", {}), "position": _ship_position_fact(ship_people[index], "after_board"), "sustain": _ship_sustain_diag()}): return false
	ship_position_trace.append(_ship_position_fact(ship_people[index], "boarded_%d" % index))
	var person: Dictionary = action_owner.site_controller.vehicles.ship_person(ship_people[index])
	return _check(str(person.row.embarked_vehicle_id) == ship_ids[index] and int(person.row.berth_id) == 1, "true body attachment uses the requested original boat and berth", person.row)

func _ship_public_food() -> bool:
	ship_observation = "delivery"
	var before_depot := int(action_owner.terrain.site.inventory.grain)
	var before_holder := int(action_owner.terrain.site.depot_items.version)
	ship_food_source_site = str(action_owner.terrain.site.id)
	if not _observe_ship_food_results(): return false
	var before_food := ship_consumed_rations
	ship_position_trace.append(_ship_position_fact(ship_people[0], "food_begin"))
	var begun: Dictionary = action_owner.site_controller.begin_team_food(_ship_team(), 4.0, ship_people[0], {"kind": "depot"})
	if not _check(begun.ok and not _ship_supply().delivery.is_empty() and int(action_owner.terrain.site.inventory.grain) == before_depot, "public finite Depot fill starts an actual productive-time job with no immediate debit", begun): return false
	for attempt: int in range(12):
		if _partial_ready(): break
		if not _paid_ship_step(0.001): return false
	if not _check(_partial_ready(), "food partial contains actual paid GAME work with positive retained left",
		{"delivery": _ship_supply().get("delivery", {}), "crowd_delivery_steps": action_owner.site_controller.crowd_delivery_steps,
		"crowd_delivery_last": action_owner.site_controller.crowd_delivery_last, "settle": action_owner.site_controller.supply_settle_last,
		"valid": action_owner.site_controller.food_delivery.valid_breakdown(_ship_team(), _ship_supply()) if not _ship_supply().get("delivery", {}).is_empty() else "no delivery",
		"paid": action_paid, "positions": ship_position_trace + [_ship_position_fact(ship_people[0], "after")]}): return false
	if not await _reopen_actual_partial(): return false
	if not await _ship_until(func() -> bool: return _ship_supply().delivery.is_empty(), "same real cold delivery continues and commits finite food once"): return false
	var supply := _ship_supply()
	var boat_key := "vehicle:" + ship_ids[0]
	if not _check(int(action_owner.terrain.site.inventory.grain) == before_depot - 4 and int(action_owner.terrain.site.depot_items.version) == before_holder + 1 and supply.locations.has(boat_key), "real completed Depot fill debits exactly four finite units and creates only the actual receiving boat pool"): return false
	var held := 0.0
	for stock: Dictionary in supply.locations.values(): held += PhysicalSustain.rations(stock, stock.inventory)
	var consumed := ship_consumed_rations - before_food
	if not _check(absf(held + consumed - 4.0) <= EPS, "finite original held plus consumed meal conserves the four actual delivered rations", {"held": held, "consumed": consumed}): return false
	var shore_key := "shore:%d" % action_owner.terrain.index(Vector2i(30, 20))
	var revision := int(supply.revision)
	# The original transfer resupplies the team at its new food locations: a member
	# who had no food location this period eats the unpaid part of the current meal
	# from the unloaded stack (opening one whole grain). Every quantity below is the
	# actual value read back; together they conserve the one unloaded grain.
	var boat_before: Dictionary = _ship_supply().locations[boat_key].duplicate(true)
	var boat_rations_before := PhysicalSustain.rations(boat_before, boat_before.inventory)
	var eaten_before := ship_consumed_rations
	var unloaded: Dictionary = action_owner.site_controller.transfer_ship_supply(_ship_team(), boat_key, shore_key, {"grain": 1}, 0.0, ship_commander_id, false)
	var unload_meal := float(unloaded.get("consumed_rations", -1.0))
	var after_unload: Dictionary = _ship_supply()
	var shore_after: Dictionary = after_unload.locations.get(shore_key, {"inventory": {}, "open_rations": 0.0})
	var shore_rations := PhysicalSustain.rations(shore_after, shore_after.inventory)
	var boat_after: Dictionary = after_unload.locations[boat_key]
	var unload_facts := {"meal": unload_meal, "shore_rations": shore_rations, "shore": shore_after, "boat_before": boat_before, "boat_after": boat_after, "revision": [revision, after_unload.revision]}
	if not _check(unloaded.ok and int(after_unload.revision) == revision + 1 and is_finite(unload_meal) and unload_meal >= 0.0
		and int(boat_after.inventory.get("grain", 0)) == int(boat_before.inventory.get("grain", 0)) - 1 and absf(float(boat_after.open_rations) - float(boat_before.open_rations)) <= EPS
		and absf(shore_rations + unload_meal - 1.0) <= EPS, "false-dispatch public food UNLOAD moves one actual grain through the real boat/shore contact and version once; the shore stack plus the meal it paid conserve it", unload_facts): return false
	if not _observe_ship_food_results(): return false
	if not _check(absf(ship_consumed_rations - eaten_before - unload_meal) <= EPS, "the UNLOAD meal is the one accepted original food result", {"observed": ship_consumed_rations - eaten_before, "meal": unload_meal}): return false
	# LOAD returns exactly what actually remains on the shore stack.
	var shore_items: Dictionary = shore_after.inventory.duplicate(true)
	var shore_open := float(shore_after.open_rations)
	var loaded: Dictionary = action_owner.site_controller.transfer_ship_supply(_ship_team(), shore_key, boat_key, shore_items, shore_open, ship_commander_id, false)
	var load_meal := float(loaded.get("consumed_rations", -1.0))
	var after_load: Dictionary = _ship_supply()
	var shore_final: Dictionary = after_load.locations.get(shore_key, {"inventory": {}, "open_rations": 0.0})
	var boat_final: Dictionary = after_load.locations[boat_key]
	var boat_rations_final := PhysicalSustain.rations(boat_final, boat_final.inventory)
	var load_facts := {"meal": load_meal, "shore": shore_final, "boat": boat_final, "boat_rations": [boat_rations_before, boat_rations_final], "revision": after_load.revision}
	if not _check(loaded.ok and int(after_load.revision) == revision + 2 and is_finite(load_meal) and load_meal >= 0.0
		and PhysicalSustain.rations(shore_final, shore_final.inventory) <= EPS and absf(boat_rations_final + unload_meal + load_meal - boat_rations_before) <= EPS,
		"false-dispatch public food LOAD returns the actual remaining shore stack without minting a meal", load_facts): return false
	eaten_before = ship_consumed_rations
	if not _observe_ship_food_results(): return false
	if not _check(absf(ship_consumed_rations - eaten_before - load_meal) <= EPS, "the LOAD meal, if any, is the one accepted original food result", {"observed": ship_consumed_rations - eaten_before, "meal": load_meal}): return false
	var facts := var_to_bytes([_ship_supply().locations, _ship_supply().sustain, _ship_supply().revision, slot.control])
	var empty: Dictionary = action_owner.site_controller.transfer_ship_supply(_ship_team(), shore_key, boat_key, {"grain": 1}, 0.0, ship_commander_id, false)
	if not _check(slot.take_original_food_results().is_empty(), "rejected original transfer publishes no accepted food result"): return false
	return _check(not empty.ok and facts == var_to_bytes([_ship_supply().locations, _ship_supply().sustain, _ship_supply().revision, slot.control]), "the actual empty shore pool refuses another LOAD without food, hunger, version or clock drift", empty)

func _ship_helm(index: int, cold_partial: bool) -> bool:
	ship_observation = "helm"
	var begun: Dictionary = action_owner.site_controller.person_actions.begin_ship_helm(ship_people[index], ship_ids[index], ship_commander_id, false)
	if not _check(begun.ok and int(_ship_vehicle(index).operator_id) == 0, "false-dispatch public helm job keeps the true uncommitted operator empty", begun): return false
	if cold_partial:
		if not await _ship_until(_partial_ready, "original paid helm job obtains real retained partial progress"): return false
		if not await _reopen_actual_partial(): return false
	if not await _ship_until(func() -> bool: return int(_ship_vehicle(index).operator_id) == ship_people[index] and not action_owner.site_controller.person_actions.is_busy(ship_people[index]), "original helm path completes and seats the true body as operator"): return false
	return _check(action_owner.site_controller.vehicles.ship_driver_ready(_ship_vehicle(index)) and action_owner.site_controller.vehicles.ship_crew_count(_ship_vehicle(index)) == 1, "each genuine ferry has its original one capable crew at actual helm")

func _ship_open_sea_positive() -> bool:
	ship_observation = "move"
	var data := action_owner.terrain
	if not _check(data.path_between(Vector2i(30, 21), Vector2i(20, 21)).is_empty(), "closed original land approach remains closed after genuine loading and boarding"): return false
	var source_cell := int(_ship_vehicle(0).cell)
	var begun: Dictionary = action_owner.site_controller.vehicles.ship_order(ship_ids[0], "sail", Vector2i(23, 19), ship_commander_id, false)
	if not _check(begun.ok, "false-dispatch original sail command takes the actual open sea route beside the closed land barrier", begun): return false
	if not await _ship_until(_partial_ready, "original whole-hull reservation obtains actual paid sea displacement"): return false
	if not await _reopen_actual_partial(): return false
	var paid_before := action_paid
	if not await _ship_until(func() -> bool: return int(_ship_vehicle(0).cell) == action_owner.terrain.index(Vector2i(23, 19)) and _ship_vehicle(0).move.is_empty() and _ship_vehicle(0).command.is_empty(), "same restored original whole hull completes the positive sea crossing"): return false
	return _check(source_cell != int(_ship_vehicle(0).cell) and action_paid > paid_before and action_owner.terrain.path_between(Vector2i(30, 21), Vector2i(20, 21)).is_empty(), "true accepted hull movement crosses the barrier's ocean end while ground stays blocked")

func _ship_original_two_boat_closure() -> bool:
	ship_observation = "settled"
	var team: Variant = _ship_team()
	if not _check(team != null and team.combat_identity(int(team.current_commander)) == ship_commander_id and team.command_eligible(int(team.current_commander)) and action_owner.controlled_person_id() == ship_commander_id, "the controlled ship captain commands both boats before control returns ashore"): return false
	# Control returns to the shore person; the ship team keeps its own captain, now an NPC.
	if not _ship_control(ship_commander_id, ship_actor_id): return false
	team = _ship_team()
	if not _check(team != null and team.combat_identity(int(team.current_commander)) == ship_commander_id and team.command_eligible(int(team.current_commander)) and not ship_people.has(action_owner.controlled_person_id()), "the ship team keeps the same eligible captain, now an NPC, after control returns ashore"): return false
	if not await _reopen_actual_partial(): return false
	var captured: Dictionary = action_owner.site_controller._capture_for_save()
	if not _check(captured.ok, "original capture derives departure bytes from the actual restored physical owners", captured): return false
	var state: Dictionary = action_owner.terrain.site
	var source := var_to_bytes(state)
	var closure: Dictionary = Travel.extract(state, {"mode": "sea", "controller": "npc", "team_id": ship_team_id, "person_id": ship_commander_id, "crowd_departure": true, "game_seconds": float(slot.control.logical_game_seconds)}, "c06_physical_source_closure_%d" % OS.get_process_id())
	if not _check(closure.ok and source == var_to_bytes(state), "original NPC sea extraction accepts genuine full two-boat crowd closure and preserves its physical source", closure.get("code")): return false
	var party: Dictionary = closure.party
	var party_people: Array = party.person_ids.duplicate(); party_people.sort()
	var expected_people: Array = ship_people.duplicate(); expected_people.sort()
	var party_boats: Array = party.vehicle_ids.duplicate(); party_boats.sort()
	var expected_boats: Array = ship_ids.duplicate(); expected_boats.sort()
	if not _check(party_people == expected_people and party_boats == expected_boats and party.content.actors.is_empty() and not party.person_ids.has(ship_actor_id) and _ship_origin_holds(closure.origin, ship_actor_id) and int(closure.origin.get("controlled_person_id", -1)) == ship_actor_id,
		"true crowd closure carries exactly two actual bodies/boats and leaves the same controlled shore person at source", {"people": party.person_ids, "boats": party.vehicle_ids}): return false
	var owners: Array[Dictionary] = Travel._feeding(party.content, Travel._body_records(party.content))
	var food_key := "vehicle:" + ship_ids[0]
	if not _check(owners.size() == 1 and owners[0].stock.has(food_key) and not owners[0].stock.has("vehicle:" + ship_ids[1]) and str(owners[0].context.food_locations[ship_people[0]]) == food_key and str(owners[0].context.food_locations[ship_people[1]]) == "", "actual boarded/filled/unloaded original closure uses own boat pool and empty access on the missing second pool"): return false
	var transport: Dictionary = Travel.prepare_transport(party.duplicate(true))
	if not _check(transport.ok and transport.can_move and Travel.party_speed(party.content) > 0.0, "original true two-helm closure remains sea-capable with a missing food pool", transport.get("code")): return false
	report["physical_source_closure"] = {"people": party.person_ids, "boats": party.vehicle_ids, "captain": ship_commander_id, "source_actor": ship_actor_id, "food_locations": owners[0].context.food_locations, "party": party, "formal_world_departure": "OPEN_NOT_RUN", "npc_dispatch_and_region_route": "OPEN_NOT_RUN"}
	return true

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest() or not await _setup_action_world(): _finish(); return
	if not _ship_public_cargo(): _finish(); return
	if not await _ship_board(0, true): _finish(); return
	if not await _ship_public_food(): _finish(); return
	if not await _ship_board(1, false): _finish(); return
	if not _check(not _ship_supply().locations.has("vehicle:" + ship_ids[1]), "second real boarding does not mint a missing own boat pool"): _finish(); return
	if not await _ship_helm(0, false) or not await _ship_helm(1, true): _finish(); return
	if not await _ship_open_sea_positive(): _finish(); return
	if not await _ship_original_two_boat_closure(): _finish(); return
	report["physical_cold_epochs"] = ship_cold_evidence
	report["actual_positive_action"] = action_paid
	report["actual_positive_game"] = action_game_paid
	_finish()

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	finished = true
	failed = failed or not ok
	if not message.is_empty(): printerr(message)
	paused = false
	for scene: TerrainLab in capture_scenes:
		if is_instance_valid(scene): scene.free()
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(Entry.LAST_WORLD)) if FileAccess.file_exists(Entry.LAST_WORLD) else null
	if current is Dictionary and str(current.get("world_id", "")) == world_id:
		if last_world_exists:
			var restored := FileAccess.open(Entry.LAST_WORLD, FileAccess.WRITE); restored.store_buffer(last_world_bytes); restored.close()
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(Entry.LAST_WORLD))
	TerrainArmy.release_contact_source()
	var receipt := {"failed": failed, "checks": checks, "report": report, "checks_evidence": action_evidence, "actual_interval_trace": action_trace, "scope": "original public finite cargo/food work, two physical boat attachments/helms, active whole owner graph cold bind, ground barrier/open local sea and actual physical-source NPC extraction; named/test-only genesis; no formal World NPC dispatch/sea Party bind, full six cases, parser/native/performance/release acceptance"}
	var file := FileAccess.open(out.path_join("ship_finite_food_physical_receipt.json"), FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(receipt, "\t", true, true)); file.close()
	print("REGION_SHIP_FINITE_FOOD_PHYSICAL_", "FAILED" if failed else "PASS", " checks=", checks)
	quit(1 if failed else 0)
func _observe_ship_food_results() -> bool:
	for result: Dictionary in slot.take_original_food_results():
		var local_team: bool = result.owner_kind == "team" and result.owner_id == str(ship_team_id) and result.site_id == ship_food_source_site
		var actual_party: bool = not ship_food_party_token.is_empty() and result.owner_kind == "party" and result.owner_id == ship_food_party_token
		if not local_team and not actual_party: continue
		var consumed := float(result.consumed_rations)
		if not _check(is_finite(consumed) and consumed > 0.0, "observed food consumption is the positive original accepted per-call return", result): return false
		ship_consumed_rations += consumed
		ship_food_results.append(result.duplicate(true))
	return _check(slot.take_original_food_results().is_empty(), "original accepted result readout drains once and retries replay no consumption")
