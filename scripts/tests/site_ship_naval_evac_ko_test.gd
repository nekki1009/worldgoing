extends "res://scripts/tests/site_ship_naval_lifecycle_test.gd"
## Additional original-owner case. No source edit, fake attachment or teleport.
const EVAC_KO_OUT := "res://output/site_ship_close_20261004/naval_evac_ko"

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 120000
	_run.call_deferred()

func _evac_ko_case(settle_first: bool) -> bool:
	if not _generate(false): return false
	team = lab.army
	team.team_id = lab._next_army_identity()
	team.role = "logistics"
	team.roster_size = 2
	var cells: Array[Vector2i] = [native_dock.cells[0], native_dock.cells[1]]
	if not _must(team.deploy_at(lab.terrain, lab.character, lab.npc, cells) and team.enable_combat(false, 0), "EVAC_KO_ORIGINAL_TWO_ROSTER"): return false
	people.clear()
	for index in range(2):
		people.append(team.combat_identity(index))
		team.combat_units[index].logistics = true
	# Explicit initial stock in the original holders; subsequent movement is real transfer.
	team.combat_units[0].cargo.grain = 3
	lab.terrain.site.army_next_team = team.team_id + 1
	lab.terrain.site.army_trial_active = true
	var controller: SiteController = lab.site_controller
	var vehicles: SiteVehicleTransport = controller.vehicles
	var actions: SitePersonActions = controller.person_actions
	var supplied: Dictionary = controller.captivity_supply.enable_team(team)
	if not _must(supplied.ok, "EVAC_KO_ORIGINAL_SUPPLY_ENABLE: " + str(supplied)): return false
	supplied.entry.inventory.grain = 7
	supplied.entry.sustain.open_rations = 0.75
	var result: Dictionary = vehicles.deploy_ship(team, "ferry", native_dock.anchor, native_dock.facing, true)
	if not _must(result.ok, "EVAC_KO_ORIGINAL_HULL: " + str(result)): return false
	boat_id = str(result.vehicle_id)
	for index in range(2):
		if not _board(index, index): return false
	var boat: Dictionary = vehicles.records()[boat_id]
	result = controller.transfer_ship_supply(team, "shore:%d" % lab.terrain.index(native_dock.shore), "vehicle:" + boat_id, {"grain": 2}, 0.25, people[0], true)
	if not _must(result.ok, "EVAC_KO_ORIGINAL_COMMON_FOOD_TRANSFER: " + str(result)): return false
	result = vehicles.transfer("person:%d" % people[0], boat_id, {"grain": 1}, [], int(team.combat_units[0].item_state.version), int(boat.holder.version), people[0], true)
	if not _must(result.ok and int(boat.cargo.grain) == 1 and int(team.combat_units[0].cargo.grain) == 2, "EVAC_KO_ORIGINAL_CARGO_TRANSFER: " + str(result)): return false
	result = actions.begin_ship_helm(people[0], boat_id, people[0], true)
	if not _must(result.ok, "EVAC_KO_ORIGINAL_HELM") or not _job(people[0]): return false
	var personal_holder: Dictionary = team.combat_units[0].item_state
	var holder_before: Dictionary = personal_holder.duplicate(true)
	var personal_cargo: Dictionary = team.combat_units[0].cargo.duplicate(true)
	var hull_before: Dictionary = boat.holder.duplicate(true)
	var hull_cargo: Dictionary = boat.cargo.duplicate(true)
	var food_before := _supply_locations()
	var q_before := vehicles.ship_load(boat_id)
	result = Runtime.damage_ship_vehicle(lab.terrain, boat_id, Ship.hull_hp("ferry"))
	if not _must(result.ok, "EVAC_KO_TRUE_HULL_DAMAGE"): return false
	vehicles.update_ships(0.01)
	# job_for is a read-only snapshot; retain the original job reference so
	# subsequent progress and removal are checked against the real authority.
	var job: Dictionary = actions._jobs.get(str(people[0]), {})
	if not _must(str(boat.naval.state) == "wrecked" and str(job.get("kind", "")) == "ship_evac" and job.path.size() >= 2, "EVAC_KO_TRUE_ORIGINAL_ESCAPE_JOB"): return false
	var goal: Vector2 = (job.path.back() + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	var ground_start := vehicles.ship_person_ground(people[0])
	actions.advance_ship_jobs(float(job.duration) * 0.35)
	var ground_before_ko := vehicles.ship_person_ground(people[0])
	var elapsed_before := float(job.elapsed)
	var local_before: Dictionary = vehicles.ship_death_location(people[0]).duplicate(true)
	if not _must(elapsed_before > 0.0 and elapsed_before < float(job.duration) and not ground_before_ko.is_equal_approx(ground_start) and not ground_before_ko.is_equal_approx(goal) and team.moving_to[0] == TerrainArmy.INVALID_CELL, "EVAC_KO_REAL_PARTIAL_WORLD_PROGRESS: " + str({"elapsed": elapsed_before, "duration": job.duration, "start": ground_start, "current": ground_before_ko, "goal": goal, "moving_to": team.moving_to[0], "paused": lab.terrain.site.paused, "can_act": team.combat_can_act(0), "hp": team.combat_hot_get(0, &"hp"), "ko": team.combat_hot_get(0, &"ko"), "kind": job.kind})): return false
	team.apply_unit_contact(0, {"shield": false, "result": {"hp": 0.0, "stun": 1000.0, "guard_break": false}})
	if not _must(float(team.combat_hot_get(0, &"hp")) > 0.0 and float(team.combat_hot_get(0, &"ko")) > 0.0, "EVAC_KO_ORIGINAL_CONTACT_KNOCKOUT"): return false
	# This same ACTION dispatch must kill and commit death at existing progress.
	if settle_first:
		actions.settle_after_contacts()
	else:
		actions.advance_ship_jobs(0.05)
		actions.settle_after_contacts()
	if not _must(float(team.combat_hot_get(0, &"hp")) == 0.0 and float(job.elapsed) == elapsed_before and not actions.is_busy(people[0]), "EVAC_KO_DIES_NOW_AND_FREEZES_JOB_PROGRESS"): return false
	var body: Dictionary = team.combat_units[0]
	if not _must(body.get("ship_death_local", []) == local_before.get("local_position", []) and vehicles.is_embarked(people[0]) and controller.supply_save_guard().code == "BUSY", "EVAC_KO_ORIGINAL_PENDING_DEATH_LOCATION_AND_SAVE_GUARD"): return false
	var frozen_ground := vehicles.ship_person_ground(people[0])
	actions.advance_ship_jobs(float(job.duration) + 1.0)
	actions.settle_after_contacts()
	if not _must(float(job.elapsed) == elapsed_before and vehicles.ship_person_ground(people[0]).is_equal_approx(frozen_ground) and not frozen_ground.is_equal_approx(goal) and team.moving_to[0] == TerrainArmy.INVALID_CELL and team._cell_owners.get(Vector2i((job.path.back() as Vector2).round()), -1) != 0, "EVAC_KO_NEVER_CONTINUES_TO_SHORE_OR_RESERVES_LAND"): return false
	if not _must(is_equal_approx(vehicles.ship_load(boat_id), q_before) and is_same(personal_holder, body.item_state), "EVAC_KO_PENDING_ORIGINAL_HOLDER_Q_UNCHANGED"): return false
	controller.settle_person_deaths(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"down"]) + 0.2)
	var remains: Dictionary = lab.terrain.site.ground_loot.get(str(body.get("remains_id", "")), {})
	if not _must(body.get("ship_death_settled", false) and not vehicles.is_embarked(people[0]) and not remains.is_empty() and str(remains.vehicle_id) == boat_id and remains.local_position == local_before.local_position, "EVAC_KO_ONE_ORIGINAL_WRECK_CONTAINER"): return false
	if not _must(remains.item_ids == holder_before.item_ids and remains.equipped == holder_before.equipped and remains.cargo == personal_cargo and vehicles.ship_people(boat, false).size() == 1 and is_equal_approx(vehicles.ship_load(boat_id), q_before), "EVAC_KO_N_RELEASE_ALL_ITEMS_AND_CARGO_Q_CONSERVED"): return false
	if not _must(boat.holder == hull_before and boat.cargo == hull_cargo and _supply_locations() == food_before, "EVAC_KO_HULL_CARGO_COMMON_FOOD_UNCHANGED"): return false
	# Remaining survivor finishes another real original job; no fake attachment.
	var survivor_load := Runtime.carried_load(lab.terrain.site, team.combat_units[1].cargo, team.combat_units[1].item_state) + float(team.combat_units[1].item_state.equipped.size())
	vehicles.update_ships(0.01)
	if not _must(str(actions.job_for(people[1]).get("kind", "")) == "ship_evac", "EVAC_KO_SECOND_ORIGINAL_SURVIVOR_JOB"): return false
	if not _job(people[1]): return false
	if not _must(team.combat_can_act(1) and not vehicles.is_embarked(people[1]) and lab.terrain.is_walkable(team.cells[1]) and team._cell_owners.get(team.cells[1], -1) == 1 and vehicles.ship_people(boat, false).is_empty() and is_equal_approx(vehicles.ship_load(boat_id), q_before - survivor_load), "EVAC_KO_SURVIVOR_REAL_SHORE_REMAINS_IN_WRECK"): return false
	team.settle_combat_command()
	lab.terrain.site.combat_left = 0.0
	controller._capture_positions()
	var filename := EVAC_KO_OUT + ("/wreck_evac_midway_ko_settle.json" if settle_first else "/wreck_evac_midway_ko_advance.json")
	result = controller.save_to(filename)
	if not _must(result.ok, "EVAC_KO_GENERATED_FULL_SAVE: " + str(result)): return false
	result = Store.load_site(filename)
	if not _must(result.ok, "EVAC_KO_GENERATED_FULL_STORE_VALIDATION: " + str(result)): return false
	result = controller.load_from(filename)
	if not _must(result.ok, "EVAC_KO_GENERATED_FULL_LOAD: " + str(result)): return false
	team = lab.army
	if not _must(team.combat_identity(0) == people[0] and team.combat_identity(1) == people[1] and float(team.combat_hot_get(0, &"hp")) == 0.0 and float(team.combat_hot_get(1, &"hp")) > 0.0 and _supply_locations() == food_before and is_equal_approx(vehicles.ship_load(boat_id), q_before - survivor_load), "EVAC_KO_ORIGINAL_IDS_HP_GOODS_ROUNDTRIP"): return false
	return true

func _run() -> void:
	if not _must(DisplayServer.get_name() == "headless", "EVAC_KO_CANONICAL_HEADLESS_REQUIRED"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for owner: TerrainArmy in lab.combat_armies: owner.set_process(false)
	lab.site_controller.save_root = EVAC_KO_OUT
	if not _evac_ko_case(false) or not _evac_ko_case(true): return
	lab.queue_free()
	await process_frame
	print("SITE_SHIP_NAVAL_EVAC_KO_PASS true board, partial original evacuation, contact KO, immediate death/frozen progress, original wreck N/Q and generated JSON")
	quit(0)
