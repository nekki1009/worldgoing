extends "res://scripts/tests/site_building_ui_test.gd"

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var guard: TerrainTestCharacter = lab.character
	var captive: TerrainTestNPC = lab.npc
	var actions: SitePersonActions = controller.person_actions
	var prison_key := _formal_feature(data, "prison", Vector2i(35, 35))
	assert(guard.place(Vector2i(35, 38), true) and captive.place(Vector2i(34, 38), true))
	captive.faction_id = 2
	captive.hp = 63.0
	captive.knockout_left = 30.0
	captive.issue_command(TerrainTestNPC.Command.STOP)
	assert(actions.begin_capture(guard.person_id, captive.person_id, guard.person_id).ok)
	actions.advance(4.0)
	var captured := actions.settle_after_contacts()
	assert(captured.size() == 1 and captured[0].ok and captive.captive)
	# Recovery is fixture setup. Admission itself must neither wake nor heal.
	captive.knockout_left = 0.0
	captive.stun = 0.0
	captive._getting_up = false
	captive.action_time = 0.0
	var original_holder := captive.item_state
	var original_cargo: Dictionary = data.site.worker.cargo
	var holder_copy := original_holder.duplicate(true)
	var cargo_copy := original_cargo.duplicate(true)
	var relation_copy: Dictionary = data.site.captivity[str(captive.person_id)].duplicate(true)
	var layout := Runtime.prison_layout(data, prison_key)
	assert(layout.ok and layout.slots.size() == 1)
	var slot: Dictionary = layout.slots[0]
	var started := controller.captive_escort.begin_prison(guard.person_id, guard.person_id, prison_key)
	assert(started.ok, str(started))
	var starting_cell := captive.terrain_cell
	data.site.paused = true
	controller.captive_escort.advance(3.0)
	assert(captive.terrain_cell == starting_cell)
	data.site.paused = false
	var moved := false
	for _frame: int in range(3600):
		var previous := captive.terrain_cell
		var previous_guard := guard.terrain_cell
		lab._advance_action_time(TerrainLab.ACTION_STEP)
		assert(previous == captive.terrain_cell or data.can_step(previous, captive.terrain_cell))
		assert(previous_guard == guard.terrain_cell or data.can_step(previous_guard, guard.terrain_cell))
		moved = moved or previous != captive.terrain_cell
		assert(captive.hp == 63.0 and captive.knockout_left == 0.0 and captive.captive)
		if captive.terrain_cell == slot.cell and guard.terrain_cell == slot.contact_cell \
			and actions._prison_stopped(actions._person(captive.person_id)) and actions._prison_stopped(actions._person(guard.person_id)): break
	assert(moved and captive.terrain_cell != starting_cell)
	assert(captive.terrain_cell == slot.cell and guard.terrain_cell == slot.contact_cell)
	assert(str(data.site.captivity[str(captive.person_id)].get("prison_id", "")).is_empty())
	# The original game clock legitimately consumes supplies during walking.
	# Compare the actual admission transaction, after both original moves settle.
	var supply_copy: Dictionary = data.site.person_supply.duplicate(true)
	assert(actions.admit_prison(guard.person_id, captive.person_id, prison_key).ok)
	assert(controller.captive_escort.cancel(guard.person_id).ok)
	var admitted := actions.prison_slot(captive.person_id)
	assert(admitted.ok and str(admitted.prison_id) == prison_key, str(admitted))
	assert(guard.terrain_cell == admitted.slot.contact_cell and captive.terrain_cell == admitted.slot.cell)
	assert(is_same(captive.item_state, original_holder) and is_same(data.site.worker.cargo, original_cargo))
	assert(captive.item_state == holder_copy)
	assert(original_cargo == cargo_copy)
	assert(data.site.person_supply == supply_copy)
	assert(int(admitted.relation.captor_id) == int(relation_copy.captor_id) and int(admitted.relation.guard_id) == int(relation_copy.guard_id))
	assert(not actions.is_guarding(guard.person_id), "Admission releases standing guard work, not captive ownership")
	assert(not captive.step(Vector2i.DOWN) and not actions.begin_escape(captive.person_id).ok)
	var query := actions.prison_query(guard.person_id, prison_key)
	assert(query.ok and query.inmates.size() == 1 and query.free_slots.is_empty())
	controller._capture_positions()
	assert(Store._validate_captivity(data, data.site).ok)
	# F02 / plan 6.1: capture and admission game seconds are saved in the
	# captivity record (v3) with a capture episode; an in-prison record without a
	# real admission time is corrupt; a v2 record migrates once, marked legacy.
	var stored: Dictionary = data.site.captivity[str(captive.person_id)]
	var site_seconds := Runtime.now(data) * 60.0
	assert(int(stored.version) == 3 and not bool(stored.legacy_observed) and int(stored.episode.person_id) == captive.person_id and int(stored.episode.seq) == 1, str(stored))
	assert(int(captive.social_state.capture_seq) == 1, "The person's own capture sequence advanced (social_state v1)")
	assert(str(stored.rank_snapshot) in ["commoner", "officer", "head"] and int(stored.settled_days) == 0, str(stored))
	assert(float(stored.captured_at_game_seconds) <= float(stored.admitted_at_game_seconds) and float(stored.admitted_at_game_seconds) <= site_seconds, str(stored))
	var kept_relation := stored.duplicate()
	stored.admitted_at_game_seconds = -1.0
	assert(not Store._validate_captivity(data, data.site).ok, "An inmate needs a real admission time")
	data.site.captivity[str(captive.person_id)] = kept_relation
	var legacy_state: Dictionary = data.site.duplicate(true)
	for field: String in ["captured_at_game_seconds", "admitted_at_game_seconds", "episode", "loyal_org", "rank_snapshot", "settled_days", "legacy_observed"]:
		legacy_state.captivity[str(captive.person_id)].erase(field)
	legacy_state.captivity[str(captive.person_id)].version = 2
	assert(Store._validate_captivity(data, legacy_state).ok, "v2 in-prison record still loads")
	Store._normalize_state(legacy_state)
	var migrated: Dictionary = legacy_state.captivity[str(captive.person_id)]
	var load_seconds := (float(legacy_state.minute) + float(legacy_state.phase)) * 60.0
	assert(int(migrated.version) == 3 and bool(migrated.legacy_observed) and migrated.loyal_org == null and str(migrated.rank_snapshot) == "unknown" and is_equal_approx(float(migrated.admitted_at_game_seconds), load_seconds) and is_equal_approx(float(migrated.captured_at_game_seconds), load_seconds), str(migrated))
	assert(str(migrated.episode) != str(kept_relation.episode), "Migration draws a new episode")
	assert(Store._validate_captivity(data, legacy_state).ok)
	Store._normalize_state(legacy_state)
	assert(legacy_state.captivity[str(captive.person_id)] == migrated, "Migration runs once")
	for pool: Dictionary in data.site.person_supply.values():
		assert(is_equal_approx(float(pool.at), Runtime.now(data) * 60.0), str({"supply_at": pool.at, "site_at": Runtime.now(data) * 60.0}))
	# Same-frame effective contact must win over a completed four-second release.
	var release_started := actions.begin_prison_release(guard.person_id, captive.person_id)
	assert(release_started.ok, str(release_started))
	actions.advance(4.0)
	guard.apply_contact({"result": {"hp": 1.0, "stun": 0.0, "guard_break": false}, "shield": false})
	var interrupted := actions.settle_after_contacts()
	assert(interrupted.size() == 1 and not interrupted[0].ok and captive.captive)
	assert(data.site.person_supply == supply_copy and data.site.captivity.has(str(captive.person_id)))
	var hp_before := captive.hp
	var ko_before := captive.knockout_left
	var cell_before := captive.terrain_cell
	var version_before := int(captive.item_state.version)
	release_started = actions.begin_prison_release(guard.person_id, captive.person_id)
	assert(release_started.ok, str(release_started))
	actions.advance(4.0)
	var released := actions.settle_after_contacts()
	assert(released.size() == 1 and released[0].ok, str(released))
	assert(not captive.captive and not data.site.captivity.has(str(captive.person_id)))
	assert(captive.hp == hp_before and captive.knockout_left == ko_before and captive.terrain_cell == cell_before)
	assert(int(captive.item_state.version) == version_before + 1 and is_same(captive.item_state, original_holder))
	assert(original_cargo == cargo_copy and is_same(data.site.worker.cargo, original_cargo))
	assert(actions.settle_after_contacts().is_empty())
	print("SITE_PRISON_ACTIONS_PASS original capture/supply owners, actual escorted edges, pause, admission, saved capture/admission seconds + episode (v3), one-time legacy_observed migration, retained HP/items, confinement, final-contact rejection, one release")
	lab.free()
	quit()
