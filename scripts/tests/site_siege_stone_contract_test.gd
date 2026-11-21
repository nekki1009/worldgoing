extends "res://scripts/tests/site_siege_ballista_contract_test.gd"
## Paid original engine/action paths plus explicit trajectory/geometry fixtures.
## This is not GPU, raw-mesh, native or performance acceptance.
const ArmyAI = preload("res://scripts/terrain_lab/site_army_ai.gd")

class StoneLab extends TerrainLab:
	var resolve_calls := 0
	func _siege_people() -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		for actor: TerrainTestCharacter in combat_actors:
			if actor.hp <= 0.0 or actor.site_exited: continue
			result.append({"owner": actor, "unit": -1, "id": actor.person_id, "faction": actor.faction_id,
				"ground": actor.position, "cell": actor.terrain_cell})
		return result
	func resolve_structure_change(result: Dictionary) -> void:
		resolve_calls += 1
		super.resolve_structure_change(result)

func _run() -> void:
	create_timer(90.0).timeout.connect(func() -> void: quit(1))
	_check_stone_rules_and_exact_contacts()
	_check_stone_cycle_and_cancellation("traction_trebuchet", 12.0)
	_check_stone_cycle_and_cancellation("counterweight_trebuchet", 20.0)
	_check_stone_actual_contact_and_source_retirement()
	_check_stone_first_impact_parts()
	_check_ai_pending_friendly_line()
	TerrainArmy.release_contact_source()
	assert(completed == 6, "A stone contract group stopped before completion")
	print("SITE_SIEGE_STONE_CONTRACT_PASS: exact rounded-corner sphere and parabolic prism contacts, original paid 12/20-second cycles, atomic ammunition/RNG/sequence, canceled/stale/small-crew windup, original Actor multi-person friendly contact outside three-person limit, source-independent first floor, first-impact part set and one batch resolution, paused AI windup preserves progress/RNG; headless projection/trajectory fixtures only")
	quit(0)

func _stone_fixture(kind: String, count: int = 8) -> Dictionary:
	var data := _fixture()
	var built := SiteRuntime.begin_siege_build(data, kind, Vector2i(20, 20), Vector2i.RIGHT, 1, 1)
	assert(built.ok, str(built))
	var key := str(built.vehicle)
	var vehicle: Dictionary = data.site.vehicles[key]
	var definition: Dictionary = SiteRuntime.SIEGE_DEFINITIONS[kind]
	var station: Dictionary = SiteRuntime.siege_work_slots(data, vehicle)[0]
	assert(SiteRuntime.advance_siege_work(data, key, "construct", float(definition.work_seconds), data.cell_from_index(int(station.cell)), 0, 1).ok)
	var lab := StoneLab.new()
	lab.terrain = data
	var controller := Controller.new()
	controller.lab = lab
	lab.site_controller = controller
	controller.person_actions.init(lab)
	controller.vehicles.init(controller)
	var positions: Array[Vector2i] = [Vector2i(16, 18)] # Original commander stays present even in the three-person insufficient-crew fixture.
	for slot in range(count): positions.append(controller.vehicles.crew_cell(vehicle, str(slot)))
	var people := CrewFixture.new()
	people.setup(root, data, positions)
	lab.army = people.army
	lab.combat_armies.append(people.army)
	people.army.vehicle_transport = controller.vehicles
	people.army.exchange_enabled = true
	controller.work_team.init(lab)
	data.set_meta(&"site_garrison_lab", weakref(lab))
	var commander := people.army.combat_identity(0)
	assert(people.army.command_eligible(people.army.current_commander), "The original fixture commander must be present and command eligible")
	for slot in range(count):
		var assigned := controller.vehicles.assign_crew(key, people.army.combat_identity(slot + 1), str(slot), commander, true)
		assert(assigned.ok, str(assigned))
	assert(controller.vehicles.crew_count(vehicle, true) == count)
	controller.vehicles.update_siege(0.001) # Settle the original assigned/approach command before policy review.
	vehicle.cargo.siege_stone = 4 # Explicit original-cargo fixture supply.
	vehicle.holder.version = int(vehicle.holder.version) + 1
	return {"data": data, "key": key, "lab": lab, "controller": controller, "fixture": people, "vehicle": vehicle, "commander": commander}

func _close_stone(context: Dictionary) -> void:
	for actor: TerrainTestCharacter in context.lab.combat_actors: actor.free()
	context.lab.combat_actors.clear()
	context.lab.siege_projectiles.clear()
	context.lab.combat_armies.clear()
	context.fixture.close()
	context.controller.free()
	context.lab.free()

func _stone_actor(context: Dictionary, cell: Vector2i, identity: int, shield: bool = false) -> ProjectedActor:
	var actor := ProjectedActor.new()
	actor.data = context.data
	actor.person_id = identity
	actor.faction_id = 1
	actor.exchange_enabled = true
	actor.terrain_cell = cell
	actor.position = (Vector2(cell) + Vector2.ONE * 0.5) * 64.0
	actor.fixture_shield = shield
	context.lab.combat_actors.append(actor)
	context.controller._equipment_appearances[identity] = {"parts": {"shield": "round_shield_wood" if shield else "none"}}
	return actor

func _stone_tick(context: Dictionary, seconds: float, step: float = 0.02) -> void:
	var remaining := seconds
	while remaining > 0.000000001:
		var elapsed := minf(step, remaining)
		context.lab._advance_siege(elapsed)
		remaining -= elapsed

func _stone_attack(context: Dictionary) -> void:
	var target := {"type": "ground", "cell": [55, 21]}
	var ordered: Dictionary = context.controller.vehicles.order_siege(context.key, "attack", target, int(context.commander), true)
	assert(ordered.ok, str(ordered))

func _check_stone_rules_and_exact_contacts() -> void:
	for kind: String in ["traction_trebuchet", "counterweight_trebuchet"]:
		var rule := SiteCombatRules.siege_attack(kind)
		assert(str(rule.ammo) == "siege_stone" and str(rule.kind) == "blunt")
		assert(SiteCombatRules.siege_in_range(Vector2.ZERO, Vector2(float(rule.minimum), 0), Vector2i.RIGHT, kind))
		assert(SiteCombatRules.siege_in_range(Vector2.ZERO, Vector2(float(rule.range), 0), Vector2i.RIGHT, kind))
		assert(not SiteCombatRules.siege_in_range(Vector2.ZERO, Vector2(float(rule.range) + 0.01, 0), Vector2i.RIGHT, kind))
		assert(not SiteCombatRules.siege_in_range(Vector2.ZERO, Vector2(float(rule.minimum) - 0.01, 0), Vector2i.RIGHT, kind))
	assert(SiteCombatRules.RANGED_MAX_RANGE == 10.0)
	var box := Rect2(Vector2(5, 5), Vector2.ONE)
	# Both expanded AABB axes overlap, but the sphere misses the real corner.
	assert(Collision.segment_prism_contact(Vector3(4.8, 4.8, 1), Vector3(4.8, 4.8, 1), box, 0, 2, 0.25).size() > 0)
	assert(Collision.sphere_prism_contact(Vector3(4.8, 4.8, 1), Vector3(4.8, 4.8, 1), box, 0, 2, 0.25).is_empty())
	assert(not Collision.sphere_prism_contact(Vector3(4.9, 4.9, 1), Vector3(4.9, 4.9, 1), box, 0, 2, 0.25).is_empty())
	var wall := Rect2(Vector2(4.99, 0), Vector2(0.02, 1))
	var origin := Vector3(0, 0.5, 1)
	var goal := Vector3(10, 0.5, 0.25)
	assert(Collision.arc_prism_contact(origin, goal, 5, 0, 1, wall, 0, 2, 0.25).is_empty(), "The real parabola clears a low wall")
	var high := Collision.arc_prism_contact(origin, goal, 5, 0, 1, wall, 0, 8, 0.25)
	assert(not high.is_empty() and float(high.fraction) < 0.5, "A slow whole-flight step must still hit a thin high wall")
	var sliced := Collision.arc_prism_contact(origin, goal, 5, 0.4, 0.6, wall, 0, 8, 0.25)
	assert(absf(float(sliced.fraction) - float(high.fraction)) < 0.000000001, "Prism contact cannot depend on frame partition")
	completed += 1

func _check_stone_cycle_and_cancellation(kind: String, cycle: float) -> void:
	var context := _stone_fixture(kind)
	var vehicle: Dictionary = context.vehicle
	var rule := SiteCombatRules.siege_attack(kind)
	var version := int(vehicle.holder.version)
	var rng := int(vehicle.rng_state)
	_stone_attack(context)
	_stone_tick(context, float(rule.loading) + float(rule.aiming) - 0.02)
	assert(context.lab.siege_shots == 0 and int(vehicle.cargo.siege_stone) == 4 and int(vehicle.rng_state) == rng)
	_stone_tick(context, 0.02)
	assert(context.lab.siege_shots == 1 and int(vehicle.cargo.siege_stone) == 3 and int(vehicle.holder.version) == version + 1)
	assert(int(vehicle.next_attack_seq) == 2 and int(vehicle.rng_state) != rng)
	assert(str(vehicle.phase) == "recovering")
	_stone_tick(context, cycle - float(rule.loading) - float(rule.aiming))
	assert(vehicle.action.is_empty() and str(vehicle.phase) == "ready")
	context.controller.vehicles.order_siege(context.key, "stop", {}, int(context.commander), true)
	_stone_tick(context, 10.0)
	assert(not context.lab.has_siege_projectiles())
	var stable := _siege_values(vehicle)
	_stone_attack(context)
	_stone_tick(context, 1.0)
	context.controller.vehicles.order_siege(context.key, "stop", {}, int(context.commander), true)
	assert(_siege_values(vehicle) == stable, "Canceled windup changed ammunition, sequence or RNG")
	_stone_attack(context)
	_stone_tick(context, 1.0)
	vehicle.holder.version = int(vehicle.holder.version) + 1
	_stone_tick(context, 0.02)
	assert(vehicle.action.is_empty() and int(vehicle.rng_state) == int(stable.rng) and int(vehicle.next_attack_seq) == int(stable.seq))
	_close_stone(context)
	var insufficient := _stone_fixture(kind, 3)
	var insufficient_order: Dictionary = insufficient.controller.vehicles.order_siege(insufficient.key, "attack", {"type": "ground", "cell": [55, 21]}, int(insufficient.commander), true)
	assert(not insufficient_order.ok or not insufficient.controller.vehicles.crew_ready(insufficient.vehicle))
	_stone_tick(insufficient, cycle * 2.0)
	assert(insufficient.lab.siege_shots == 0 and int(insufficient.vehicle.cargo.siege_stone) == 4)
	_close_stone(insufficient)
	completed += 1

func _siege_values(vehicle: Dictionary) -> Dictionary:
	return {"cargo": vehicle.cargo.duplicate(), "rng": int(vehicle.rng_state), "seq": int(vehicle.next_attack_seq)}

func _check_stone_actual_contact_and_source_retirement() -> void:
	var context := _stone_fixture("traction_trebuchet")
	var targets: Array[ProjectedActor] = []
	for index in range(4): targets.append(_stone_actor(context, Vector2i(57 + index, 21), 91000 + index))
	var outside := _stone_actor(context, Vector2i(59, 24), 91999)
	context.lab._launch_siege_projectile(context.vehicle, {"point": Vector2(60.5, 21.5), "height": 1.0}, "stone-contact-fixture", Vector2.ZERO)
	var flight: Dictionary = context.lab.siege_projectiles[0]
	context.data.site.vehicles.erase(context.key)
	assert(not context.lab.siege_save_guard().ok)
	_stone_tick(context, 10.0, 0.5) # Deliberately slow input; curved sweep still sees people.
	assert(not context.lab.has_siege_projectiles() and flight.people.size() == 4, str(flight))
	for actor: ProjectedActor in targets: assert(actor.hp < 100.0, "A visible friendly body along the stone sweep was skipped")
	assert(outside.hp == 100.0, "An off-stone body took invisible radius damage")
	var hp := targets[0].hp
	_stone_tick(context, 1.0)
	assert(targets[0].hp == hp and context.lab.siege_contacts == 4)
	_close_stone(context)
	completed += 1

func _check_stone_first_impact_parts() -> void:
	var context := _stone_fixture("traction_trebuchet")
	var wall := _build(context.data, "stone_wall", Vector2i(45, 20), Vector2i(1, 2))
	var behind := _build(context.data, "stone_wall", Vector2i(47, 20), Vector2i(1, 2))
	var first: Dictionary = context.data.site.features[wall]
	var second: Dictionary = context.data.site.features[behind]
	context.lab._launch_siege_projectile(context.vehicle, {"point": Vector2(45.5, 21), "height": 1.0}, "stone-multiple-parts-fixture", Vector2.ZERO)
	# Explicit straight-XY trajectory is tangent to two real adjacent part faces.
	var flight: Dictionary = context.lab.siege_projectiles[0]
	flight.origin.y = 21.0
	flight.screen_origin.y = 21.0 * 64.0 - 48.0
	flight.position = flight.screen_origin
	_stone_tick(context, 8.0, 0.5)
	for part: Dictionary in first.parts.values(): assert(float(part.hp) == 260.0)
	for part: Dictionary in second.parts.values(): assert(float(part.hp) == 300.0, "A stopped stone penetrated behind its first impact")
	assert(context.lab.resolve_calls == 1, "First-impact parts triggered several same-step terrain responses")
	assert(flight.parts.size() == 2)
	_close_stone(context)
	completed += 1

func _check_ai_pending_friendly_line() -> void:
	var context := _ballista_fixture()
	var friend := _add_projected_actor(context, Vector2i(28, 20), 93001)
	_attack(context)
	_tick(context, 1.0)
	context.vehicle.command.ai = true
	var elapsed := float(context.vehicle.action.elapsed)
	var stable := _siege_values(context.vehicle)
	_tick(context, 3.0)
	assert(float(context.vehicle.action.elapsed) == elapsed and _siege_values(context.vehicle) == stable)
	friend.terrain_cell = Vector2i(28, 25)
	friend.position = (Vector2(friend.terrain_cell) + Vector2.ONE * 0.5) * 64.0
	_tick(context, 6.0)
	assert(context.lab.siege_shots == 1 and int(context.vehicle.cargo.siege_bolt) == 3)
	_close_ballista(context)
	completed += 1
