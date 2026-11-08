extends "res://scripts/tests/site_ship_crowd_test.gd"
## The real Lab common clock must advance boat, food and original fatigue once.
## Crowd port (2026-11-08): the crew is a live native crowd formation; every timed part runs on
## TerrainLab._advance_action_time, the same shared step the game uses. Run: --crowd --crowd-test <id>.

var team: Variant = null
var people: Array[int] = []

## Pays the shared step until predicate holds (at most MAX_TICKS action steps of DT).
func _clock_until(predicate: Callable) -> bool:
	for tick in range(MAX_TICKS):
		if predicate.call(): return true
		lab._advance_action_time(DT)
	return bool(predicate.call())

## A crowd soldier walks to goal one native step at a time on the common clock.
func _clock_walk(identity: int, goal: Vector2i) -> bool:
	return _clock_until(func() -> bool:
		var person: Dictionary = team.person(int(team.index_for_identity(identity)), false)
		if person.is_empty(): return false
		if person.cell == goal and not bool(person.moving): return true
		if not bool(person.moving): lab.crowd_site.siege_approach_step(identity, goal)
		return false)

func _clock_job(identity: int) -> bool:
	var actions: SitePersonActions = lab.site_controller.person_actions
	return _clock_until(func() -> bool: return not actions.is_busy(identity))

## The formation's one shared fatigue pool: native formation values and its counted members.
func _pool() -> Dictionary:
	var state: Dictionary = lab.crowd_site.formation_state(int(team.formation_index))
	return {"fatigue": float(team.combat_hot_get(int(team.index_for_identity(people[0])), &"fatigue", 0.0)), "count": int(state.get("fatigue_count", 0))}

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void: quit(3))
	var args := OS.get_cmdline_user_args()
	if not check(args.has("--crowd") and args.has("--crowd-test"), "isolated crowd startup required"): return
	lab = load("res://scenes/terrain_lab/TerrainLab.tscn").instantiate()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for person: TerrainTestCharacter in lab.combat_actors: person.set_process(false)
	_water_fixture()
	var deployed: Dictionary = lab.deploy_trial_armies([
		{"faction": 0, "count": 4, "role": "logistics", "attack": false, "ai_enabled": false, "entry": "west"}])
	if not check(deployed.ok, "deploy one logistics crowd team beside the water", deployed): return
	if not check(lab.crowd_site != null and lab.crowd_site.active and lab.exchange_enabled, "live native crowd Site on the exchange clock"): return
	for candidate: Variant in lab.crowd_site.person_owners():
		if candidate is CrowdPersonOwner and candidate.has_army() and candidate.command_members().size() >= 2:
			team = candidate
			break
	if not check(team != null, "a crowd formation with at least two soldiers exists"): return
	for member: int in team.command_members():
		var identity: int = team.combat_identity(member)
		if lab.crowd_site._actor(identity) == null: people.append(identity)
	if not check(people.size() >= 2, "two non-Actor crowd members exist", people): return
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var actions: SitePersonActions = lab.site_controller.person_actions
	var shipped: Dictionary = vehicles.deploy_ship(team, "ferry", Vector2i(30, 20), Vector2i.UP, true)
	if not check(shipped.ok, "a ferry deploys under the crowd Site (test path)", shipped): return
	var boat_id := str(shipped.vehicle_id)
	var boat: Dictionary = vehicles.records()[boat_id]
	var contacts: Array[Vector2i] = vehicles.ship_contacts(boat)
	if not check(contacts.size() >= 1, "the ferry has a land contact cell", contacts): return
	for berth: int in range(2):
		if not check(_clock_walk(people[berth], contacts[0]), "crew %d walks to the contact cell on the common clock" % berth, _cell_of(team, people[berth])): return
		var boarded: Dictionary = actions.begin_ship_board(people[berth], boat_id, people[berth], berth, true)
		if not check(boarded.ok, "crew %d boards berth %d" % [berth, berth], boarded): return
		if not check(_clock_job(people[berth]) and _aboard(team, people[berth]) == [true, int(boat_id)], "crew %d is native aboard after its paid boarding job" % berth, _aboard(team, people[berth])): return
	var helm: Dictionary = actions.begin_ship_helm(people[0], boat_id, people[0], true)
	if not check(helm.ok, "clock fixture helm accepted", helm): return
	if not check(_clock_job(people[0]) and int(boat.operator_id) == people[0], "the helm job finishes on the common clock", boat.operator_id): return
	var shared := _pool()
	if not check(int(shared.count) == 4, "crew retain the formation's one four-person fatigue pool", shared): return
	var fatigue_before := float(shared.fatigue)
	var now_before := Runtime.now(lab.terrain) * 60.0
	if not check(vehicles.ship_order(boat_id, "forward", TerrainArmy.INVALID_CELL, people[0], true).ok, "common clock boat step accepted"): return
	lab._advance_action_time(float(boat.move.duration) * 0.4)
	if not check(not boat.move.is_empty() and float(boat.move.elapsed) > 0.0, "the common clock moves the hull", boat.move): return
	var game_elapsed := Runtime.now(lab.terrain) * 60.0 - now_before
	var after := float(_pool().fatigue)
	var expected := fatigue_before + game_elapsed * PersonFatigue.WORK_RATE / float(shared.count)
	if not check(absf(after - expected) < 0.000001 and after > fatigue_before, "one crew effort is charged once on the common clock",
		{"before": fatigue_before, "after": after, "expected": expected, "game_elapsed": game_elapsed}): return
	var entry: Dictionary = lab.site_controller._supply_entry(team)
	if not check(absf(float(entry.sustain.at) - Runtime.now(lab.terrain) * 60.0) < 0.000001, "food stays on the common Site clock", {"at": entry.sustain.at, "now": Runtime.now(lab.terrain) * 60.0}): return
	var frozen := var_to_bytes([boat, _pool(), entry, lab.terrain.site.minute, lab.terrain.site.phase])
	paused = true
	lab._advance_action_time(1.0)
	paused = false
	if not check(var_to_bytes([boat, _pool(), entry, lab.terrain.site.minute, lab.terrain.site.phase]) == frozen, "pause advances no hull, crew or food"): return
	if not check(vehicles.ship_order(boat_id, "stop", TerrainArmy.INVALID_CELL, people[0], true).ok, "common clock stop accepted"): return
	lab._advance_action_time(float(boat.move.duration) + 0.1)
	if not check(boat.move.is_empty() and boat.command.is_empty() and int(boat.operator_id) == people[0], "the committed step finishes once after stop", {"move": boat.move, "command": boat.command, "operator": boat.operator_id}): return
	print("SITE_SHIP_CLOCK_PASS checks=", checks)
	quit(0)
