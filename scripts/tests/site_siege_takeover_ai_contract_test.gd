extends "res://scripts/tests/site_siege_stone_contract_test.gd"
## Original public PersonActions jobs and original 0.5-second tactical review.

func _run() -> void:
	create_timer(90.0).timeout.connect(func() -> void: quit(1))
	_check_takeover_clock_and_assets()
	_check_takeover_interruptions()
	_check_takeover_admission_and_competition()
	_check_original_ai_review_and_manual_command()
	_check_ai_ammunition_and_friendly_wait()
	TerrainArmy.release_contact_source()
	if completed != 5:
		push_error("A takeover/AI contract group stopped before completion")
		quit(1)
		return
	print("SITE_SIEGE_TAKEOVER_AI_CONTRACT_PASS: original public ten-action-second takeover, game-clock separation, paused/struck/moved/stale/source-replaced/faction/threat/busy admission and stable competing submit, original holders/cargo/identity/ammunition/RNG preserved, original 0.5-second tactical-review hook, manual command preservation, original crew/ammo and friendly-line waiting; headless query fixtures only, no GPU/native/performance claim")
	quit(0)

func _takeover_fixture() -> Dictionary:
	var context := _ballista_fixture(0)
	context.vehicle.team_id = 0 # Explicit neutral original engine; no surrogate.
	context.data.set_meta(&"site_garrison_lab", weakref(context.lab))
	context["executor"] = context.fixture.army.combat_identity(1)
	context["second"] = context.fixture.army.combat_identity(2)
	return context

func _begin_takeover(context: Dictionary, identity: int = -1) -> Dictionary:
	return context.controller.person_actions.begin_siege_takeover(int(context.executor) if identity < 0 else identity, str(context.key), int(context.commander), true)

func _settle_takeover(context: Dictionary, action_seconds: float) -> Array[Dictionary]:
	context.controller.person_actions.advance_structure_attacks(action_seconds)
	return context.controller.person_actions.settle_after_contacts()

func _check_takeover_clock_and_assets() -> void:
	var context := _takeover_fixture()
	var vehicle: Dictionary = context.vehicle
	var original := vehicle.duplicate(true)
	var original_max_hp: float = float(SiteRuntime.SIEGE_DEFINITIONS[str(vehicle.kind)].max_hp)
	var holder: Dictionary = vehicle.holder
	var cargo: Dictionary = vehicle.cargo
	var people: Dictionary = context.fixture.army.capture_combat_state()
	assert(_begin_takeover(context).ok)
	context.controller.person_actions.advance(600.0)
	assert(context.controller.person_actions.settle_after_contacts().is_empty() and int(vehicle.team_id) == 0)
	assert(_settle_takeover(context, 9.99).is_empty() and int(vehicle.team_id) == 0)
	context.data.site.paused = true
	assert(_settle_takeover(context, 10.0).is_empty() and int(vehicle.team_id) == 0)
	context.data.site.paused = false
	var result := _settle_takeover(context, 0.01)
	assert(result.size() == 1 and result[0].ok, str(result))
	assert(int(vehicle.team_id) == context.fixture.army.team_id and int(holder.version) == int(original.holder.version) + 1)
	assert(is_same(context.data.site.vehicles[context.key], vehicle) and is_same(vehicle.holder, holder) and is_same(vehicle.cargo, cargo))
	for field: String in ["id", "kind", "definition_version", "cell", "facing", "hp", "ever_hp_damaged", "cargo", "next_attack_seq", "rng_state"]: assert(vehicle[field] == original[field], field)
	assert(float(SiteRuntime.SIEGE_DEFINITIONS[str(vehicle.kind)].max_hp) == original_max_hp)
	assert(holder.holder == original.holder.holder and holder.item_ids == original.holder.item_ids and holder.equipped == original.holder.equipped)
	assert(context.fixture.army.capture_combat_state() == people, "Takeover replaced or moved original people")
	_close_ballista(context)
	completed += 1

func _check_takeover_interruptions() -> void:
	for cause: String in ["hit", "move", "holder", "source", "pose", "hp", "team"]:
		var context := _takeover_fixture()
		assert(_begin_takeover(context).ok)
		assert(_settle_takeover(context, 5.0).is_empty())
		var army: TerrainArmy = context.fixture.army
		var before := _siege_values(context.vehicle)
		var expected: Dictionary = context.controller.person_actions._jobs[str(context.executor)].expected.duplicate(true)
		match cause:
			"hit": army.combat_units[1].hit_revision = int(army.combat_units[1].get("hit_revision", 0)) + 1
			"move": army.cells[1] += Vector2i.DOWN
			"holder": context.vehicle.holder.version = int(context.vehicle.holder.version) + 1
			"source": context.data.site.vehicles[context.key] = context.vehicle.duplicate(true)
			"pose": context.vehicle.facing = [0, 1]
			"hp": army.combat_hot_set(1, &"hp", 99.0)
			"team": army.team_id = 2
		var result := _settle_takeover(context, 5.0)
		assert(result.size() == 1 and not result[0].ok and not context.controller.person_actions.is_busy(int(context.executor)), str(result))
		assert(int(context.data.site.vehicles[context.key].team_id) == int(expected.old_team))
		assert(_siege_values(context.vehicle) == before and int(context.vehicle.next_attack_seq) == int(expected.next_attack_seq) and int(context.vehicle.rng_state) == int(expected.rng_state))
		_close_ballista(context)
	completed += 1

func _check_takeover_admission_and_competition() -> void:
	var context := _takeover_fixture()
	var actions: SitePersonActions = context.controller.person_actions
	assert(not actions.begin_siege_takeover(int(context.executor), context.key, int(context.second), true).ok)
	context.vehicle.team_id = 1
	assert(not _begin_takeover(context).ok)
	context.vehicle.team_id = 0
	context.vehicle.crew_slots = {"0": int(context.executor)}
	assert(not _begin_takeover(context).ok)
	context.vehicle.crew_slots = {}
	context.vehicle.action = {"stage": "recovering"}
	assert(not _begin_takeover(context).ok)
	context.vehicle.action = {}
	var actor := _add_projected_actor(context, Vector2i(23, 21), 94001)
	actor.faction_id = 2
	assert(not _begin_takeover(context).ok, "An actionable enemy two cells from the original footprint must deny takeover")
	actor.knockout_left = 5.0
	assert(_begin_takeover(context).ok, "An unconscious enemy cannot contest the original takeover")
	assert(_begin_takeover(context, int(context.second)).ok)
	var version := int(context.vehicle.holder.version)
	var result := _settle_takeover(context, 10.0)
	assert(result.size() == 2, str(result))
	var successful := 0
	for row: Dictionary in result:
		if row.ok: successful += 1
	assert(successful == 1 and int(context.vehicle.holder.version) == version + 1)
	assert(int(context.vehicle.team_id) == 1 and not actions.is_busy(int(context.executor)) and not actions.is_busy(int(context.second)))
	_close_ballista(context)
	completed += 1

func _ai_wall(context: Dictionary) -> Dictionary:
	var key := _build(context.data, "stone_wall", Vector2i(50, 21))
	context.data.site.features[key].owner_faction = 2
	return {"type": "structure", "feature_id": key, "part_id": "c:" + str(context.data.index(Vector2i(50, 21)))}

func _check_original_ai_review_and_manual_command() -> void:
	var context := _stone_fixture("traction_trebuchet")
	var target := _ai_wall(context)
	var army: TerrainArmy = context.fixture.army
	army.tactical_ai_enabled = true
	var decisions := army.tactical_ai_decisions
	context.lab._advance_tactical_ai(0.49)
	assert(army.tactical_ai_decisions == decisions and context.vehicle.command.get("type", "") != "attack")
	context.lab._advance_tactical_ai(0.01)
	assert(army.tactical_ai_decisions == decisions + 1 and str(context.vehicle.command.type) == "attack" and bool(context.vehicle.command.ai))
	assert(context.vehicle.command.target == target and context.controller.vehicles.crew_ready(context.vehicle))
	assert(context.controller.vehicles.order_siege(context.key, "stop", {}, int(context.commander), true).ok)
	var manual := {"type": "ground", "cell": [55, 21]}
	assert(context.controller.vehicles.order_siege(context.key, "attack", manual, int(context.commander), true).ok)
	context.lab._advance_tactical_ai(0.5)
	assert(context.vehicle.command.target == manual and not bool(context.vehicle.command.get("ai", false)), "AI overwrote an original manual attack command")
	_close_stone(context)
	completed += 1

func _check_ai_ammunition_and_friendly_wait() -> void:
	var context := _stone_fixture("traction_trebuchet")
	_ai_wall(context)
	context.fixture.army.tactical_ai_enabled = true
	context.vehicle.cargo.siege_stone = 0
	var stable := _siege_values(context.vehicle)
	context.lab._advance_tactical_ai(0.5)
	assert(str(context.vehicle.command.type) == "stop" and "彈藥" in str(context.vehicle.command.reason) and _siege_values(context.vehicle) == stable)
	context.vehicle.cargo.siege_stone = 4
	context.vehicle.holder.version = int(context.vehicle.holder.version) + 1
	# The projected body lies in the deterministic end segment; scatter warning
	# widens only preview, while actual contact continues to use the visible stone.
	var friend := _stone_actor(context, Vector2i(49, 21), 95001)
	context.lab._advance_tactical_ai(0.5)
	assert(str(context.vehicle.command.type) == "stop" and "友軍" in str(context.vehicle.command.reason))
	friend.terrain_cell = Vector2i(49, 30)
	friend.position = (Vector2(friend.terrain_cell) + Vector2.ONE * 0.5) * 64.0
	context.lab._advance_tactical_ai(0.5)
	assert(str(context.vehicle.command.type) == "attack" and bool(context.vehicle.command.ai))
	_stone_tick(context, 1.0)
	assert(float(context.vehicle.action.elapsed) > 0.0 and context.lab.siege_shots == 0)
	_close_stone(context)
	completed += 1
