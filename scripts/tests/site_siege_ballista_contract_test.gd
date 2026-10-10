extends "res://scripts/tests/site_siege_runtime_contract_test.gd"

const Controller = preload("res://scripts/terrain_lab/site_controller.gd")
const Collision = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")

# Only the incoming geometry query is supplied by this headless fixture. The
# actual Actor owns HP, reactions, death, identity and position throughout.
class ProjectedActor extends TerrainTestCharacter:
	var fixture_shield := false
	func incoming_geometry(_ranged: bool = false) -> Dictionary:
		var center := position - Vector2(0.0, 48.0)
		var bodies: Array[PackedVector2Array] = [_box(center + Vector2(-8.0, -24.0), Vector2(16.0, 48.0))]
		var shields: Array[PackedVector2Array] = []
		if fixture_shield: shields.append(_box(center + Vector2(-14.0, -24.0), Vector2(4.0, 48.0)))
		return {"body": bodies, "shield": shields, "parry": []}
	func contact_protection(_hit: Dictionary, _profile: Dictionary) -> Vector2:
		return Vector2.ZERO
	func _box(origin: Vector2, size: Vector2) -> PackedVector2Array:
		return PackedVector2Array([origin, origin + Vector2(size.x, 0.0), origin + size, origin + Vector2(0.0, size.y)])

class QueryLab extends TerrainLab:
	# The test exposes its original target Actors. Crew geometry is deliberately
	# outside this query test; crew readiness still uses the actual Army/Transport.
	func _siege_people() -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		for actor: TerrainTestCharacter in combat_actors:
			if actor.hp <= 0.0 or actor.site_exited: continue
			result.append({"owner": actor, "unit": -1, "id": actor.person_id, "faction": actor.faction_id,
				"ground": actor.position, "cell": actor.terrain_cell})
		return result

class ClockController extends Controller:
	var work_seconds := 0.0
	var tick_count := 0
	func tick(delta: float, _accepted_game_seconds: float = -1.0) -> void:
		# Exercise the real calendar/work integrator without constructing its UI.
		tick_count += 1
		SiteRuntime.advance(lab.terrain, delta, false, false, Callable(), Callable(), _record_work)
	func _record_work(seconds: float) -> void:
		work_seconds += seconds

class ClockLab extends QueryLab:
	var received_game_seconds := 0.0
	var received_action_seconds := 0.0
	var combat_calls := 0
	func _advance_combat(delta: float, combat_clock: float = -1.0) -> void:
		# Observe the production common-step handoff, not a copied siege clock guard.
		assert(combat_clock >= 0.0)
		combat_calls += 1
		received_action_seconds += delta
		received_game_seconds += SiteRuntime.game_seconds(delta, combat_clock) * simulation_speed
		_advance_siege(delta)

func _run() -> void:
	create_timer(75.0).timeout.connect(func() -> void: quit(1))
	_check_ballista_cycle(2)
	_check_ballista_cycle(1)
	_check_ballista_cancellation()
	_check_ballista_flight_ownership_and_contacts()
	_check_original_ranges_and_prism()
	_check_first_attack_common_clock()
	TerrainArmy.release_contact_source()
	assert(completed == 6, "A ballista contract group stopped before completion")
	print("SITE_SIEGE_BALLISTA_CONTRACT_PASS: original Army crew, 8/16-second complete cycles, single release payment, windup/recovery stop, stale-ammo cancellation, source-independent flights/save guard, projected real-Actor shield/body and three-person friendly penetration, original bow/crossbow range and continuous prism boundary, first peaceful attack shares calendar/work/combat clock in exchange and legacy common steps; headless query and clock-boundary fixtures only, no GPU or real mesh claim")
	quit(0)

func _ballista_fixture(crew_count: int = 2, clock_probe: bool = false) -> Dictionary:
	var data := _fixture()
	var key := _new_ballista(data)
	_finish_siege(data, key)
	var lab: QueryLab = ClockLab.new() if clock_probe else QueryLab.new()
	lab.terrain = data
	var controller: Controller = ClockController.new() if clock_probe else Controller.new()
	controller.lab = lab
	lab.site_controller = controller
	controller.person_actions.init(lab)
	controller.vehicles.init(controller)
	var fixture := CrewFixture.new()
	fixture.setup(root, data, [Vector2i(16, 20), Vector2i(19, 20), Vector2i(19, 21)])
	lab.army = fixture.army
	lab.combat_armies.append(fixture.army)
	fixture.army.vehicle_transport = controller.vehicles
	fixture.army.exchange_enabled = true
	controller.work_team.init(lab)
	var vehicle: Dictionary = data.site.vehicles[key]
	var commander := fixture.army.combat_identity(0)
	for slot in range(crew_count):
		var result := controller.vehicles.assign_crew(key, fixture.army.combat_identity(slot + 1), str(slot), commander, true)
		assert(result.ok, str(result))
	assert(controller.vehicles.crew_count(vehicle, true) == crew_count)
	vehicle.cargo.siege_bolt = 4 # Explicit fixture stock in the original cargo.
	vehicle.holder.version = int(vehicle.holder.version) + 1
	return {"data": data, "key": key, "lab": lab, "controller": controller,
		"fixture": fixture, "vehicle": vehicle, "commander": commander}

func _close_ballista(context: Dictionary) -> void:
	var lab: QueryLab = context.lab
	for actor: TerrainTestCharacter in lab.combat_actors: actor.free()
	lab.combat_actors.clear()
	lab.siege_projectiles.clear()
	lab.combat_armies.clear()
	context.fixture.close()
	context.controller.free()
	lab.free()

func _attack(context: Dictionary) -> void:
	var result: Dictionary = context.controller.vehicles.order_siege(context.key, "attack",
		{"type": "ground", "cell": [45, 20]}, int(context.commander), true)
	assert(result.ok, str(result))

func _tick(context: Dictionary, seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.000000001:
		var step := minf(0.02, remaining)
		context.lab._advance_siege(step)
		remaining -= step

func _check_ballista_cycle(count: int) -> void:
	var context := _ballista_fixture(count)
	var vehicle: Dictionary = context.vehicle
	var scale := 1.0 if count == 2 else 2.0
	var version := int(vehicle.holder.version)
	_attack(context)
	_tick(context, 7.0 * scale - 0.02)
	assert(context.lab.siege_shots == 0 and int(vehicle.cargo.siege_bolt) == 4)
	_tick(context, 0.02)
	assert(context.lab.siege_shots == 1 and int(vehicle.cargo.siege_bolt) == 3)
	assert(int(vehicle.holder.version) == version + 1 and int(vehicle.next_attack_seq) == 2)
	assert(str(vehicle.phase) == "recovering" and not context.lab.siege_save_guard().ok)
	_tick(context, scale)
	assert(context.lab.siege_shots == 1 and vehicle.action.is_empty() and str(vehicle.phase) == "ready",
		"5+2+1 seconds at full crew, or twice that at one crew, must finish exactly one cycle")
	_close_ballista(context)
	completed += 1

func _check_ballista_cancellation() -> void:
	var context := _ballista_fixture()
	var vehicle: Dictionary = context.vehicle
	_attack(context)
	_tick(context, 6.0)
	assert(context.controller.vehicles.order_siege(context.key, "stop", {}, int(context.commander), true).ok)
	_tick(context, 2.0)
	assert(context.lab.siege_shots == 0 and int(vehicle.cargo.siege_bolt) == 4 and vehicle.action.is_empty())
	_attack(context)
	_tick(context, 4.0)
	vehicle.holder.version = int(vehicle.holder.version) + 1
	_tick(context, 0.02)
	assert(vehicle.action.is_empty() and context.lab.siege_shots == 0 and int(vehicle.cargo.siege_bolt) == 4,
		"Changed original ammo holder cancels the uncommitted round without payment")
	assert(context.controller.vehicles.order_siege(context.key, "stop", {}, int(context.commander), true).ok)
	_attack(context)
	_tick(context, 7.0)
	assert(context.lab.siege_shots == 1)
	assert(context.controller.vehicles.order_siege(context.key, "stop", {}, int(context.commander), true).ok)
	assert(not context.controller.vehicles.order_siege(context.key, "attack", {"type": "ground", "cell": [45, 20]}, int(context.commander), true).ok,
		"Stop cannot skip a committed recovery and immediately restart firing")
	_tick(context, 0.98)
	assert(not vehicle.action.is_empty() and str(vehicle.phase) == "recovering")
	_tick(context, 0.02)
	assert(vehicle.action.is_empty() and str(vehicle.phase) == "idle", "Stopped recovery must settle instead of blocking saves forever")
	_tick(context, 1.0)
	assert(context.lab.siege_shots == 1 and context.lab.siege_save_guard().ok)
	_close_ballista(context)
	completed += 1

func _add_projected_actor(context: Dictionary, cell: Vector2i, identity: int, shield: bool = false) -> ProjectedActor:
	var actor := ProjectedActor.new()
	actor.data = context.data
	actor.exchange_enabled = true
	actor.person_id = identity
	actor.faction_id = 1 # Same as the actual crew; friendly hits are not exempt.
	actor.fixture_shield = shield
	assert(actor.place(cell, true))
	context.lab.combat_actors.append(actor)
	context.controller._equipment_appearances[identity] = {"parts": {"shield": "round_shield_wood" if shield else "none"}}
	return actor

func _check_ballista_flight_ownership_and_contacts() -> void:
	var context := _ballista_fixture()
	var first := _add_projected_actor(context, Vector2i(28, 20), 90001, true)
	# This fixture intentionally fires past a friend to exercise D62 at impact.
	_attack(context)
	_tick(context, 7.0)
	assert(context.lab.has_siege_projectiles())
	var flight: Dictionary = context.lab.siege_projectiles[0]
	context.data.site.vehicles.erase(context.key) # Simulate source retirement after the irreversible release.
	assert(not context.lab.siege_save_guard().ok,
		"An in-flight source snapshot must guard saving even after its vehicle is gone")
	_tick(context, 2.0)
	assert(first.hp < 100.0 and context.lab.siege_contacts == 1)
	assert(flight.shields.has(first.person_id) and flight.bodies.has(first.person_id) and flight.people.size() == 1,
		"A real shield contact followed by the same original body is one person and one HP settlement")
	assert(not context.lab.has_siege_projectiles() and context.lab.siege_save_guard().ok)
	_close_ballista(context)
	context = _ballista_fixture()
	var targets: Array[ProjectedActor] = []
	for ordinal in range(4): targets.append(_add_projected_actor(context, Vector2i(28 + ordinal * 3, 20), 90100 + ordinal))
	_attack(context)
	_tick(context, 7.0)
	flight = context.lab.siege_projectiles[0]
	assert(context.controller.vehicles.order_siege(context.key, "stop", {}, int(context.commander), true).ok)
	_tick(context, 2.0)
	assert(targets[0].hp < targets[1].hp and targets[1].hp < targets[2].hp and targets[2].hp < 100.0)
	assert(targets[3].hp == 100.0 and flight.people.size() == 3 and context.lab.siege_contacts == 3,
		"Three different friendly original people can be hit once, with remaining-power decay; the fourth cannot")
	_close_ballista(context)
	completed += 1

func _check_original_ranges_and_prism() -> void:
	assert(float(SiteCombatRules.ranged_profile("bow_01").range) == 8.0)
	assert(float(SiteCombatRules.ranged_profile("crossbow_01").range) == 10.0 and SiteCombatRules.RANGED_MAX_RANGE == 10.0)
	var original := SiteCombatRules.exchange_hp("longsword_01", "none")
	assert(is_equal_approx(SiteCombatRules.structure_damage("longsword_01", "wood"), original * 0.25))
	assert(is_equal_approx(SiteCombatRules.structure_damage("longsword_01", "stone"), original * 0.05))
	var box := Rect2(Vector2(5.0, 2.0), Vector2.ONE)
	var hit := Collision.segment_prism_contact(Vector3(0.0, 2.5, 1.0), Vector3(10.0, 2.5, 1.0), box, 0.0, 2.0)
	assert(not hit.is_empty() and is_equal_approx(float(hit.fraction), 0.5), "A long step must intersect the actual thin obstacle")
	assert(Collision.segment_prism_contact(Vector3(0.0, 2.5, 3.0), Vector3(10.0, 2.5, 3.0), box, 0.0, 2.0).is_empty())
	assert(Collision.segment_prism_contact(Vector3(0.0, 4.0, 1.0), Vector3(10.0, 4.0, 1.0), box, 0.0, 2.0).is_empty())
	completed += 1

func _check_first_attack_common_clock() -> void:
	for exchange_mode: bool in [true, false]:
		var context := _ballista_fixture(2, true)
		var lab: ClockLab = context.lab
		var controller: ClockController = context.controller
		var data: TerrainData = context.data
		lab.exchange_enabled = exchange_mode
		lab.fixed_action_steps_enabled = true
		lab.simulation_speed = 1.0
		lab.movement_input_enabled = false
		data.site.combat_left = 0.0
		data.site.phase = 0.25
		_attack(context)
		# Also covers an existing attack becoming ready after peaceful crew arrival
		# or resupply: the common-step guard must not rely only on the order caller.
		data.site.combat_left = 0.0
		var before := (float(data.site.minute) + float(data.site.phase)) * 60.0
		var step := TerrainLab.EXCHANGE_ACTION_STEP
		lab._advance_action_time(step)
		var calendar_seconds := (float(data.site.minute) + float(data.site.phase)) * 60.0 - before
		assert(absf(calendar_seconds - step) < 0.000001, "First siege step advanced calendar at peaceful 60x speed")
		assert(absf(controller.work_seconds - step) < 0.000001, "Site work must receive the same first wartime slice")
		assert(absf(lab.received_game_seconds - step) < 0.000001, "Combat handoff must receive the same clock as Site work")
		assert(absf(lab.received_action_seconds - step) < 0.000001)
		assert(controller.tick_count == (1 if exchange_mode else 4) and lab.combat_calls == controller.tick_count)
		assert(str(context.vehicle.action.get("stage", "")) == "loading" and absf(float(context.vehicle.action.elapsed) - step) < 0.000001)
		assert(lab.siege_shots == 0 and int(context.vehicle.cargo.siege_bolt) == 4)
		_close_ballista(context)
	completed += 1
