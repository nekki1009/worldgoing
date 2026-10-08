extends "res://scripts/tests/site_building_ui_test.gd"

const Garrison = preload("res://scripts/terrain_lab/site_garrison.gd")

func _make_garrison_team(lab: TerrainLab, team: TerrainArmy, positions: Array[Vector2i]) -> void:
	team.roster_size = positions.size()
	team.faction_id = 1
	assert(team.deploy_at(lab.terrain, lab.character, lab.npc, positions) and team.enable_combat(false))
	team.set_process(false)
	team.settle_combat_command()

func _meal_history(controller: SiteController) -> Dictionary:
	var states: Array = []
	var histories := {}
	for owner: Dictionary in controller.captivity_supply._states(false).values():
		states.append(owner.state)
		for cohort: Dictionary in owner.state.cohorts:
			for identity: int in cohort.ids:
				var history := cohort.duplicate(true)
				history.erase("ids")
				assert(not histories.has(identity))
				histories[identity] = history
	assert(SiteController.Sustain.validate_owners(states, controller.captivity_supply._all_members()))
	return histories

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var key := _formal_feature(data, "barracks", Vector2i(20, 20), Vector2i(10, 10))
	var source: TerrainArmy = lab.army
	var second: TerrainArmy = lab.opposing_army
	_make_garrison_team(lab, source, [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26)])
	_make_garrison_team(lab, second, [Vector2i(24, 27), Vector2i(25, 27)])
	var captain := source.combat_identity(0)
	var soldier := source.combat_identity(1)
	var patient := source.combat_identity(2)
	var second_soldier := second.combat_identity(1)
	var other_captain := second.combat_identity(0)
	var original := {}
	for team: TerrainArmy in [source, second]:
		var entry: Dictionary = controller._enable_team_supply(team)
		assert(not entry.is_empty())
		entry.sustain.open_rations = 0.375
		for row: Dictionary in team.combat_units:
			original[int(row.person_id)] = {"row": row, "holder": row.item_state, "cargo": row.cargo,
				"items": row.item_state.duplicate(true), "cargo_copy": row.cargo.duplicate(true),
				"cell": team.cells[team.index_for_identity(int(row.person_id))]}
	source.combat_hot_set(2, &"hp", 63.0)
	source.combat_hot_set(2, &"ko", 30.0)
	source.combat_hot_set(2, &"pose", "unconscious")
	source._cell_owners.erase(source.cells[2])
	var meals := _meal_history(controller)
	assert(source.military_role(0) == "officer" and source.military_role(1) == "soldier")
	assert(not source.record_officer_service([1], true).ok, "Ordinary abilities do not confer officer qualification")
	var snapshot := source.capture_combat_state()
	var live_reference: Variant = data.get_meta(&"site_garrison_lab") if data.has_meta(&"site_garrison_lab") else null
	assert(live_reference is WeakRef and live_reference.get_ref() == lab and lab.terrain == data, "Original formal bind must supply the current Site context, without test live metadata seeding")
	assert(not Runtime._barracks_in_use(data, key), "Current same-Site empty barracks must remain available before real admission")
	var live_site_before: Dictionary = data.site.duplicate(true)
	var live_environment_before := data.environment_revision
	var live_navigation_before := data.navigation_revision
	var second_before := second.capture_combat_state()
	var actors_before := {}
	for actor: TerrainTestCharacter in lab.combat_actors:
		actors_before[actor.person_id] = {"owner": actor, "holder": actor.item_state, "state": actor.capture_state()}
	var expired_owner: Object = Object.new()
	var expired_reference: WeakRef = weakref(expired_owner)
	expired_owner.free()
	assert(expired_reference.get_ref() == null)
	for context: String in ["invalid", "dead", "stale"]:
		var detached: TerrainData = Env.navigation_for_state(data, data.site.duplicate(true))
		detached.site.armies = [snapshot.duplicate(true), second_before.duplicate(true)]
		if context == "invalid": detached.set_meta(&"site_garrison_lab", 7)
		elif context == "dead": detached.set_meta(&"site_garrison_lab", expired_reference)
		else: detached.set_meta(&"site_garrison_lab", live_reference)
		var fault_reference: Variant = detached.get_meta(&"site_garrison_lab")
		var detached_before: Dictionary = detached.site.duplicate(true)
		var detached_environment_before := detached.environment_revision
		var detached_navigation_before := detached.navigation_revision
		var detached_feature: Dictionary = detached.site.features[key]
		var refused := Runtime.cancel_feature(detached, key, Callable(), 1)
		assert(refused == Runtime.fail("BUSY", "軍營仍有原駐營人物，須先出營"), str({"context": context, "refused": refused}))
		assert(detached.site == detached_before and detached.environment_revision == detached_environment_before and detached.navigation_revision == detached_navigation_before and is_same(detached.site.features[key], detached_feature) and is_same(detached.get_meta(&"site_garrison_lab"), fault_reference), context + " bound context must refuse real demolition atomically even though both full original cold rosters are unregistered")
		assert(data.site == live_site_before and data.environment_revision == live_environment_before and data.navigation_revision == live_navigation_before and is_same(data.get_meta(&"site_garrison_lab"), live_reference) and source.capture_combat_state() == snapshot and second.capture_combat_state() == second_before, "Detached rejection must preserve the original live Site and both complete real rosters")
		assert(lab.combat_actors.size() == actors_before.size())
		for actor: TerrainTestCharacter in lab.combat_actors:
			assert(actors_before.has(actor.person_id) and actors_before[actor.person_id].owner == actor and is_same(actors_before[actor.person_id].holder, actor.item_state) and actor.capture_state() == actors_before[actor.person_id].state, "Detached refusal must preserve original Actor bodies and gear")
		for identity: int in original:
			var person: Dictionary = controller.person_actions._person(identity)
			assert(is_same(person.body, original[identity].row) and is_same(person.holder, original[identity].holder) and is_same(person.cargo, original[identity].cargo) and person.holder == original[identity].items and person.cargo == original[identity].cargo_copy and person.cell == original[identity].cell)
	var legacy := snapshot.duplicate(true)
	for row: Dictionary in legacy.units: row.erase("military_role")
	legacy.officers = [1]
	legacy.officer_service = [1]
	var normalized := TerrainArmy.normalize_roster_snapshot(legacy)
	assert(normalized.units[0].military_role == "officer" and normalized.units[1].military_role == "officer" and normalized.units[2].military_role == "soldier")
	var invalid := Garrison.admit(lab, key, source.team_id, [captain, captain])
	assert(not invalid.ok and source.capture_combat_state() == snapshot and _meal_history(controller) == meals)
	var admitted := Garrison.admit(lab, key, source.team_id)
	assert(admitted.ok, str(admitted))
	assert(Garrison.admit(lab, key, second.team_id).ok)
	assert(Runtime._barracks_in_use(data, key), "Current same-Site real garrison admission must remain in use")
	var cold: TerrainData = Env.navigation_for_state(data, data.site.duplicate(true))
	cold.site.armies = [source.capture_combat_state(), second.capture_combat_state()]
	var cold_before: Dictionary = cold.site.duplicate(true)
	var cold_environment_before := cold.environment_revision
	var cold_navigation_before := cold.navigation_revision
	assert(not cold.has_meta(&"site_garrison_lab") and Runtime._barracks_in_use(cold, key) and cold.site == cold_before and cold.environment_revision == cold_environment_before and cold.navigation_revision == cold_navigation_before, "Genuine absent metadata retains full original registered cold rosters without mutation")
	cold.site.armies = []
	var empty_cold_before: Dictionary = cold.site.duplicate(true)
	assert(not cold.has_meta(&"site_garrison_lab") and not Runtime._barracks_in_use(cold, key) and cold.site == empty_cold_before and cold.environment_revision == cold_environment_before and cold.navigation_revision == cold_navigation_before, "Genuine absent metadata keeps original empty cold roster available without mutation")
	assert(source.garrison_feature_id == key and source.current_commander == -1 and source.formal_commander == -1 and source.officer_order.is_empty())
	assert(source.is_member(0) and source.is_member(1) and source.is_member(2))
	assert(source.combat_hot_get(2, &"hp") == 63.0 and source.combat_hot_get(2, &"ko") == 30.0)
	assert(not bool(source.combat_hot_get(2, &"present")), "Garrisoning must refresh original KO presence without appointing a commander")
	assert(_meal_history(controller) == meals)
	var queried := Garrison.query(lab, key)
	assert(queried.ok and queried.officers.size() == 2 and queried.soldier_count == 3 and queried.people_count == 5, str(queried))
	assert(not controller.person_actions._prison_officer(controller.person_actions._person(captain)).is_empty())
	assert(controller.person_actions._prison_officer(controller.person_actions._person(soldier)).is_empty())
	second.combat_hot_set(1, &"hp", 0.0)
	var dead_query := Garrison.query(lab, key)
	assert(dead_query.people_count == 4 and dead_query.soldier_count == 2 and dead_query.dead_count == 1)
	assert(is_same(second.combat_units[1], original[second_soldier].row) and is_same(second.combat_units[1].item_state, original[second_soldier].holder))
	second.combat_hot_set(1, &"hp", 100.0)
	assert(not source.issue_combat_order(0, TerrainArmy.CombatOrder.MOVE, Vector2i(23, 27)).ok)
	assert(not source._reserve_combat_step(0, Vector2i(23, 27)))
	assert(not source.exchange_initiates(0, 999) and not source.exchange_ready(0))
	source._command_dirty = true
	source.settle_combat_command()
	assert(source.current_commander == -1)
	assert(not Garrison.form(lab, key, [soldier, second_soldier], soldier).ok)
	assert(not Garrison.form(lab, key, [captain, patient], captain).ok)
	assert(_meal_history(controller) == meals)
	assert(Garrison.set_military_role(lab, soldier, "officer").ok)
	assert(source.military_role(source.index_for_identity(soldier)) == "officer")
	assert(Garrison.set_military_role(lab, soldier, "soldier").ok)
	var formed := Garrison.form(lab, key, [captain, soldier, second_soldier], captain)
	assert(formed.ok, str(formed))
	var formed_team: TerrainArmy = Garrison._team(lab, int(formed.team_id))
	assert(formed_team != null and formed_team.garrison_feature_id.is_empty() and formed_team.combat_identity(formed_team.current_commander) == captain)
	assert(formed_team.combat_units.size() == 3 and source.combat_units.size() == 1 and second.combat_units.size() == 1)
	assert(_meal_history(controller) == meals)
	for identity: int in original:
		var person: Dictionary = controller.person_actions._person(identity)
		assert(is_same(person.body, original[identity].row) and is_same(person.holder, original[identity].holder) and is_same(person.cargo, original[identity].cargo))
		assert(person.holder == original[identity].items and person.cargo == original[identity].cargo_copy and person.cell == original[identity].cell)
	assert(Garrison.admit(lab, key, formed_team.team_id).ok)
	queried = Garrison.query(lab, key)
	assert(queried.people_count == 5 and queried.officers.size() == 2 and queried.soldier_count == 3)
	assert(_meal_history(controller) == meals)
	controller._capture_positions()
	var saved: Dictionary = data.site.duplicate(true)
	var checked: Dictionary = Store._validate_state(data, saved)
	if not checked.ok:
		for team: Dictionary in saved.armies:
			print("SITE_GARRISON_SAVE_DIAGNOSTIC ", JSON.stringify({"team_id": team.team_id, "valid": TerrainArmy.valid_combat_state(team, data, {}, saved),
				"garrison": team.garrison_feature_id, "formal": team.formal_commander, "current": team.current_commander, "units": team.units}))
	assert(checked.ok, str(checked))
	var corrupt := saved.duplicate(true)
	corrupt.armies[0].garrison_feature_id = "missing"
	assert(not Store._validate_state(data, corrupt).ok)
	corrupt = saved.duplicate(true)
	corrupt.armies[0].units[0].military_role = "pretend_officer"
	assert(not Store._validate_state(data, corrupt).ok)
	# The original lifecycle keeps progressing while commands are disabled.
	var patient_person: Dictionary = controller.person_actions._person(patient)
	var patient_team: TerrainArmy = patient_person.owner
	var patient_index := int(patient_person.unit)
	var hp_before := float(patient_person.hp)
	var ko_before := float(patient_person.ko)
	var clock_before := Runtime.now(data)
	lab._advance_action_time(TerrainLab.EXCHANGE_ACTION_STEP)
	assert(float(patient_team.combat_hot_get(patient_index, &"ko")) < ko_before and float(patient_team.combat_hot_get(patient_index, &"hp")) == hp_before,
		str({"ko_before": ko_before, "ko_after": patient_team.combat_hot_get(patient_index, &"ko"), "hp_before": hp_before, "hp_after": patient_team.combat_hot_get(patient_index, &"hp"),
			"clock_before": clock_before, "clock_after": Runtime.now(data)}))
	assert(controller.person_actions._person(patient).cell == original[patient].cell)
	assert(controller.person_actions._person(other_captain).cell == original[other_captain].cell)
	for _warmup: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_GARRISON_PASS: original rows, officer qualification, cross-roster formation, no teleport, supply/history/items, stationary live recovery, save and corrupt rejection; current and absent cold barracks predicates plus invalid/dead/stale bound demolition refusal with full original-owner preservation")
	quit(0)
