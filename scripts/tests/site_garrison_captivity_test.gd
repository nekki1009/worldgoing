extends "res://scripts/tests/site_garrison_test.gd"

const CaptivityCrowdHost = preload("res://scripts/terrain_lab/crowd_site.gd")

func _native_mode() -> bool:
	return false

func _complete_key(data: TerrainData, key: String) -> void:
	var feature: Dictionary = data.site.features[key]
	Runtime.assign_task(data, Runtime.ok("", {"target": "feature:" + key, "action": "construct", "cell": feature.entrance}))
	data.site.worker.cell = feature.entrance
	data.site.worker.mode = "work"
	# This fixture builds for two factions; use the actual owner's worker.
	Runtime.advance(data, float(feature.get("pending_build", feature).work) + 1.0, true, false, Callable(), Callable(), Callable(),
		Runtime.CARRY_CAPACITY, Runtime.CARRY_CAPACITY, 1.0, int(feature.owner_faction))
	assert(str(feature.stage) == "complete" and not feature.has("pending_build"), str(feature))
	data.site.worker.cell = data.index(Vector2i(10, 9))
	data.site.worker.mode = "idle"

func _check_captivity_save(lab: TerrainLab, stage: String) -> void:
	var captured: Dictionary = lab.site_controller._capture_for_save()
	assert(captured.ok, str({"stage": stage, "capture": captured}))
	var valid: Dictionary = Store._validate_state(lab.terrain, lab.terrain.site)
	assert(valid.ok, str({"stage": stage, "validation": valid}))
	if not _native_mode(): return
	var one: Dictionary = Store._validate_crowd(lab.terrain, lab.terrain.site, 1)
	var four: Dictionary = Store._validate_crowd(lab.terrain, lab.terrain.site, 4)
	assert(one.ok and four.ok, str({"stage": stage, "one": one, "four": four}))
	assert(one.native.save_state() == lab.crowd_site.crowd.save_state() and four.native.save_state() == lab.crowd_site.crowd.save_state())
	for _frame: int in range(15):
		assert(one.native.step_clock(TerrainLab.EXCHANGE_ACTION_STEP, TerrainLab.EXCHANGE_ACTION_STEP, 0.0))
		assert(four.native.step_clock(TerrainLab.EXCHANGE_ACTION_STEP, TerrainLab.EXCHANGE_ACTION_STEP, 0.0))
		assert(one.native.state_hash() == four.native.state_hash())

func _run() -> void:
	deadline = Time.get_ticks_msec() + (220000 if _native_mode() else 90000)
	if _native_mode():
		var args := OS.get_cmdline_user_args()
		assert(args.has("--crowd-test") and args.has("--crowd-atlas-root") and not args.has("--crowd"))
		assert(DisplayServer.get_name() != "headless")
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var guard: TerrainTestCharacter = lab.character
	var guard_id := int(guard.person_id)
	var key := _formal_feature(data, "barracks", Vector2i(20, 20), Vector2i(10, 10), {"owner_faction": 2})
	var prison := _formal_feature(data, "prison", Vector2i(35, 35))
	var home := Vector2i(25, 26)
	var source: TerrainArmy = lab.army
	source.roster_size = 1
	source.faction_id = 2
	assert(source.deploy_at(data, lab.character, lab.npc, [home]) and source.enable_combat(false, 0))
	source.set_process(false)
	source.settle_combat_command()
	var identity := source.combat_identity(0)
	var row: Dictionary = source.combat_units[0]
	var holder: Dictionary = row.item_state
	var cargo: Dictionary = row.cargo
	assert(not controller._enable_team_supply(source).is_empty())
	data.site.army_next_team = lab._next_army_identity()
	guard.faction_id = 2
	assert(Garrison.admit(lab, key, source.team_id).ok)
	guard.faction_id = 1
	assert(guard.place(Vector2i(26, 26), true))
	assert(source.combat_slots[0] == home and source.military_role(0) == "officer")
	source.combat_hot_set(0, &"hp", 63.0)
	source.combat_hot_set(0, &"ko", 30.0)
	assert(actions.begin_capture(guard_id, identity, guard_id).ok)
	actions.advance(4.0)
	var capture_result: Array[Dictionary] = actions.settle_after_contacts()
	assert(capture_result.size() == 1 and capture_result[0].ok, str(capture_result))
	# Recovery is a fixture boundary. All subsequent travel uses the real owner.
	source.combat_hot_set(0, &"ko", 0.0)
	source.combat_hot_set(0, &"stun", 0.0)
	source.combat_hot_set(0, &"pose", "idle")
	source.combat_hot_set(0, &"age", 0.0)
	source._command_dirty = true
	source.settle_combat_command()
	var captured_holder := holder.duplicate(true)
	var captured_cargo := cargo.duplicate(true)
	var query := Garrison.query(lab, key)
	assert(query.registered_count == 1 and query.people_count == 0 and query.captive_count == 1 and query.officers.is_empty(), str(query))
	if _native_mode():
		var appearance := Runtime.equipment_appearance(data, holder, row.appearance)
		var started := Time.get_ticks_msec()
		var prepared: bool = await CaptivityCrowdHost.prepare_captivity_recipe(lab, appearance)
		print("SITE_GARRISON_CAPTIVITY_PREPARATION ", JSON.stringify({"ok": prepared, "seconds": (Time.get_ticks_msec() - started) / 1000.0}))
		assert(prepared)
		lab.crowd_site = CaptivityCrowdHost.new()
		lab.add_child(lab.crowd_site)
		lab.crowd_site.setup(lab)
		var deployed: Dictionary = lab.deploy_trial_armies([{"faction": 1, "count": 1, "female_percent": 0,
			"attack": false, "ai_enabled": false, "spawn": Vector2i(42, 42)}])
		assert(deployed.ok, str(deployed))
		assert(is_same(lab.crowd_site._records[identity], row))
	_check_captivity_save(lab, "captured_registered")
	var begun: Dictionary = controller.captive_escort.begin_prison(guard_id, guard_id, prison)
	assert(begun.ok, str(begun))
	var guard_start: Vector2i = actions._person(guard_id).cell
	var last_guard_cell := guard_start
	var guard_edges := 0
	for frame: int in range(1800):
		lab._advance_action_time(TerrainLab.EXCHANGE_ACTION_STEP)
		var guard_cell: Vector2i = actions._person(guard_id).cell
		if guard_cell != last_guard_cell:
			assert(data.can_step(last_guard_cell, guard_cell), "The original escort guard must move by legal neighbouring edges")
			last_guard_cell = guard_cell
			guard_edges += 1
		if str(data.site.captivity.get(str(identity), {}).get("prison_id", "")) == prison: break
		if frame % 180 == 0:
			print("SITE_GARRISON_CAPTIVITY_ESCORT ", JSON.stringify({"frame": frame, "person": str(actions._person(identity).cell), "guard": str(actions._person(guard_id).cell)}))
		await process_frame
	print("SITE_GARRISON_ESCORT_GUARD_WALK ", JSON.stringify({"start": str(guard_start), "end": str(last_guard_cell), "legal_edges": guard_edges, "native": _native_mode()}))
	assert(str(data.site.captivity.get(str(identity), {}).get("prison_id", "")) == prison, str(data.site.escort_orders))
	assert(guard_edges > 0 and last_guard_cell != guard_start, "Admission must include the original guard's physical travel")
	query = Garrison.query(lab, key)
	assert(query.registered_count == 1 and query.people_count == 0 and query.captive_count == 1 and query.away_count == 0)
	assert(not actions._prison_officer(actions._person(identity)).is_empty(), "Officer qualification survives loss of current appointment and captivity")
	assert(holder == captured_holder and cargo == captured_cargo)
	_check_captivity_save(lab, "confined_registered")
	var release_cell: Vector2i = actions._person(identity).cell
	var release_meals := _meal_history(controller)
	var release_started: Dictionary = actions.begin_prison_release(guard_id, identity)
	assert(release_started.ok, str(release_started))
	# Settle the original four-second transaction at this boundary so its exact
	# preservation can be checked before the next simulation step starts walking.
	actions.advance(4.0)
	var released: Array[Dictionary] = actions.settle_after_contacts()
	assert(released.size() == 1 and released[0].ok, str(released))
	assert(not data.site.captivity.has(str(identity)))
	var freed: Dictionary = actions._person(identity)
	assert(not freed.captive and freed.hp == 63.0 and freed.ko == 0.0 and freed.cell == release_cell)
	assert(is_same(freed.holder, holder) and is_same(freed.cargo, cargo) and int(holder.version) == int(captured_holder.version) + 1)
	assert(_meal_history(controller) == release_meals, "Release transfers original meal history exactly once")
	query = Garrison.query(lab, key)
	assert(query.registered_count == 1 and query.people_count == 0 and query.captive_count == 0 and query.away_count == 1)
	assert(actions.settle_after_contacts().is_empty() and int(holder.version) == int(captured_holder.version) + 1)
	_check_captivity_save(lab, "released_away")
	var prison_layout := Runtime.prison_layout(data, prison)
	var contact: Vector2i = prison_layout.slots[0].contact_cell
	assert(actions._person(guard_id).cell == contact and data.can_step(release_cell, contact))
	for direction: Vector2i in TerrainData.DIRECTIONS:
		if release_cell + direction != contact: assert(not data.can_step(release_cell, release_cell + direction))
	# The releasing guard still occupies the only physical exit. The original
	# route must wait, then resume once that guard actually walks out of the way.
	for _frame: int in range(20):
		lab._advance_action_time(TerrainLab.EXCHANGE_ACTION_STEP)
		assert(actions._person(identity).cell == release_cell and not actions._person(identity).moving)
	for _edge: int in range(3):
		var guard_person: Dictionary = actions._person(guard_id)
		var next_guard := Vector2i(guard_person.cell) + Vector2i.RIGHT
		assert(controller.captive_escort._step(guard_person, next_guard, 0))
		controller.captive_escort._cancel_native(guard_id)
		for _frame: int in range(180):
			lab._advance_action_time(TerrainLab.EXCHANGE_ACTION_STEP)
			if actions._person(guard_id).cell == next_guard and actions._prison_stopped(actions._person(guard_id)): break
			await process_frame
		assert(actions._person(guard_id).cell == next_guard and actions._prison_stopped(actions._person(guard_id)))
	var checked_moving := false
	var entered := false
	var last_cell: Vector2i = actions._person(identity).cell
	var layout := Runtime.military_layout(data, key)
	for frame: int in range(1800):
		lab._advance_action_time(TerrainLab.EXCHANGE_ACTION_STEP)
		var person: Dictionary = actions._person(identity)
		assert(is_same(person.holder, holder) and is_same(person.cargo, cargo) and person.hp == 63.0)
		assert(absi(person.cell.x - last_cell.x) + absi(person.cell.y - last_cell.y) <= 1, "The original body returns by committed neighbouring edges")
		last_cell = person.cell
		if not checked_moving and person.moving:
			_check_captivity_save(lab, "returning_committed_edge")
			checked_moving = true
		if layout.walkable_cells.has(data.index(person.cell)) and actions._prison_stopped(person):
			entered = true
			break
		if frame % 180 == 0:
			print("SITE_GARRISON_CAPTIVITY_RETURN ", JSON.stringify({"frame": frame, "person": str(person.cell), "moving": person.moving}))
		await process_frame
	assert(checked_moving and entered, str({"moving_saved": checked_moving, "entered": entered, "person": str(last_cell)}))
	query = Garrison.query(lab, key)
	assert(query.registered_count == 1 and query.people_count == 1 and query.officers.size() == 1 and query.captive_count == 0 and query.away_count == 0)
	assert(int(query.officers[0].person_id) == identity and source.combat_slots[0] == home)
	_check_captivity_save(lab, "returned_original_officer")
	for _warmup: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_GARRISON_CAPTIVITY_%s_PASS: original capture, registration/capacity/attendance, prison, release, exact boundary items/meals, physical return, moving-save and original officer qualification" % ("CROWD" if _native_mode() else "GD"))
	quit(0)
