extends "res://scripts/tests/site_ship_full_transport_test.gd"

# Keeps its own 240 s budget; only the full-transport and roster tests were raised (now 360 s).
func _ship_test_deadline_ms(default_ms: int = 240000) -> int:
	return super(default_ms)
## Real Controller/Slot/UI journey over the original packaged 2m fixed coast.
## All boarding, helm replacement, ACTION/GAME steps and restoration use the
## formal owners. The fixture explicitly creates four original people once.

const JOURNEY_OUT := "res://output/site_ship_close_20261004/formal_journey"
const FROM := Vector2i.ZERO
const TO := Vector2i(-1, 0)
var controller: SiteController
var boat_id := ""
var world_id := ""
var original_items: Array = []
var original_actor_ids: Array[int] = []

func _capture_journey() -> bool:
	_settle_commands()
	return _must(controller._capture_for_save().ok, "Formal journey original capture failed")

func _step(seconds: float) -> bool:
	var before := RegionSaveSlot._site_seconds(lab.terrain)
	var global_before := float(controller.region_slot.control.logical_game_seconds)
	lab._advance_action_time(seconds)
	var completed_game := RegionSaveSlot._site_seconds(lab.terrain) - before
	return _must(completed_game > 0.0 and is_equal_approx(float(controller.region_slot.control.logical_game_seconds) - global_before, completed_game),
		"Formal original shared step did not publish completed GAME exactly once")

func _board_original(index: int) -> bool:
	if not _walk(index, Vector2i(9, 20)): return false
	var result: Dictionary = controller.person_actions.begin_ship_board(people[index], boat_id, people[index], index, true)
	return _must(result.ok, "Formal original boarding rejected: " + str(result)) and _finish_job(people[index])

func _choose_original_ship() -> bool:
	controller._refresh_vehicle_controls()
	var form: Dictionary = controller._vehicle_forms.formal
	for at in range(form.choice.item_count):
		if str(form.choice.get_item_metadata(at)) == boat_id:
			form.choice.select(at)
			return true
	return _must(false, "Formal vehicle UI omitted its original ship")

func _depart_ui() -> bool:
	if not _choose_original_ship(): return false
	controller._region_form.site_x.value = TO.x
	controller._region_form.site_y.value = TO.y
	controller._region_form.anchor_x.value = 99
	controller._region_form.anchor_y.value = 19
	controller._region_form.facing.select(2)
	var button: Button = lab.find_child("DepartShipJourney", true, false)
	if not _must(button != null, "Formal departure button missing"): return false
	button.pressed.emit()
	return _must(controller.ship_journey_active() and controller.ship_journey_status().pending, "Formal departure UI did not begin the original Slot job: " + str(controller.message.text) + " status=" + str(controller.ship_journey_status()))

func _scene_absent() -> bool:
	for identity: int in people:
		if not _must(controller.ship_person_in_journey(identity) and lab._combat_target(identity).is_empty()
			and not lab._original_person_target(identity).is_empty(), "Coarse traveler lost its biological owner or retained a Site combat body"): return false
		if not _must(controller.vehicles.ship_person_cell(identity) == TerrainArmy.INVALID_CELL
			and controller.person_actions._person(identity).moving, "Coarse traveler retained a historical Site cell or lost moving state"): return false
	return _must(team.has_ship_journey() and team.occupied_count() == 0, "Original traveling team retained land claims")

func _preserved_rows() -> bool:
	if not _must(team.combat_units.size() == 4 and team.team_id == team_id, "Formal journey replaced original roster identity"): return false
	for index in range(4):
		if not _must(team.combat_identity(index) == people[index] and float(team.combat_hot_get(index, &"hp", 0.0)) > 0.0
			and str(team.combat_units[index].embarked_vehicle_id) == boat_id, "Formal journey replaced, duplicated or detached its original person"): return false
		var row: Dictionary = team.combat_units[index]
		if not _must(_same_json(row.item_state.item_ids, item_ids[index]) and _same_json(row.item_state.equipped, equipment[index])
			and _same_json(row.cargo, cargo[index]), "Formal journey changed original carried equipment/cargo"): return false
	return _must(lab.terrain.site.item_records.keys().all(func(key: Variant) -> bool: return original_items.has(key)), "Formal journey allocated foreign equipment")

func _resume_ui() -> bool:
	var frozen: Dictionary = controller.ship_journey_status()
	var before_clock := float(controller.region_slot.control.logical_game_seconds)
	var before_food: Dictionary = lab.terrain.site.team_supply.duplicate(true)
	var before_fatigue: float = PersonFatigue.read(team.combat_units[0])
	var before_rest: float = PersonFatigue.read(team.combat_units[0], "fatigue_rest")
	var reopened: Dictionary = controller.open_fixed_world(OUT.path_join("manifest.json"), world_id, "slot", FROM, false)
	if not _must(reopened.ok, "Formal cold resume rejected its original generation: " + str(reopened)): return false
	team = lab.army
	_freeze_processes()
	var restored: Dictionary = controller.ship_journey_status()
	# Diagnose every existing acceptance term without changing its comparison.
	var after_clock: float = float(controller.region_slot.control.logical_game_seconds)
	var before_json_once: Variant = JSON.parse_string(JSON.stringify(before_clock, "", true, true))
	var after_json_once: Variant = JSON.parse_string(JSON.stringify(after_clock, "", true, true))
	var before_json_twice: Variant = JSON.parse_string(JSON.stringify(before_json_once, "", true, true))
	var after_json_twice: Variant = JSON.parse_string(JSON.stringify(after_json_once, "", true, true))
	var resume_checks: Dictionary = {
		"pending": bool(restored.pending),
		"token": restored.token == frozen.token,
		"phase": restored.phase == frozen.phase,
		"elapsed_action_seconds": is_equal_approx(float(restored.elapsed_action_seconds), float(frozen.elapsed_action_seconds)),
		"return_required_action_seconds": is_equal_approx(float(restored.return_required_action_seconds), float(frozen.return_required_action_seconds)),
		"return_elapsed_action_seconds": is_equal_approx(float(restored.return_elapsed_action_seconds), float(frozen.return_elapsed_action_seconds)),
		"game_seconds_exact": after_clock == before_clock,
		"game_seconds_same_json": _same_json(before_clock, after_clock),
		"before_json_second_parse_stable": before_json_once == before_json_twice,
		"after_json_second_parse_stable": after_json_once == after_json_twice,
	}
	var clock_diagnostic: Dictionary = {
		"before_full_precision": JSON.stringify(before_clock, "", true, true),
		"after_full_precision": JSON.stringify(after_clock, "", true, true),
		"delta_full_precision": JSON.stringify(after_clock - before_clock, "", true, true),
		"before_binary64_le": PackedFloat64Array([before_clock]).to_byte_array().hex_encode(),
		"after_binary64_le": PackedFloat64Array([after_clock]).to_byte_array().hex_encode(),
		"before_json_once": JSON.stringify(before_json_once, "", true, true),
		"before_json_twice": JSON.stringify(before_json_twice, "", true, true),
		"after_json_once": JSON.stringify(after_json_once, "", true, true),
		"after_json_twice": JSON.stringify(after_json_twice, "", true, true),
		"marker_generation": controller.region_slot._marker.get("generation", 0),
		"marker_clock_full_precision": JSON.stringify(controller.region_slot._marker.get("control", {}).get("logical_game_seconds"), "", true, true),
		"marker_folder": controller.region_slot.folder,
	}
	var closure_checks: Dictionary = {
		"food_same_json": _same_json(lab.terrain.site.team_supply, before_food),
		"fatigue_exact": PersonFatigue.read(team.combat_units[0]) == before_fatigue,
		"rest_exact": PersonFatigue.read(team.combat_units[0], "fatigue_rest") == before_rest,
		"original_roster": team.combat_units.size() == 4 and team.team_id == team_id,
		"original_shared_count": not team.team_fatigue.is_empty() and int(team.team_fatigue.count) == 4,
		"no_extra_items": lab.terrain.site.item_records.keys().all(func(key: Variant) -> bool: return original_items.has(key)),
		"journey_no_land_claims": team.has_ship_journey() and team.occupied_count() == 0,
	}
	for index in range(mini(4, team.combat_units.size())):
		var row: Dictionary = team.combat_units[index]
		var identity: int = people[index]
		closure_checks["person_%d" % index] = team.combat_identity(index) == identity and float(team.combat_hot_get(index, &"hp", 0.0)) > 0.0 and str(row.embarked_vehicle_id) == boat_id \
			and _same_json(row.item_state.item_ids, item_ids[index]) and _same_json(row.item_state.equipped, equipment[index]) and _same_json(row.cargo, cargo[index]) \
			and is_same(PersonFatigue.pool(row), team.team_fatigue) and controller.ship_person_in_journey(identity) and lab._combat_target(identity).is_empty() \
			and not lab._original_person_target(identity).is_empty() and controller.vehicles.ship_person_cell(identity) == TerrainArmy.INVALID_CELL and controller.person_actions._person(identity).moving
	print("JOURNEY_RESUME_CHECKS: " + str(resume_checks) + " clock=" + str(clock_diagnostic))
	print("JOURNEY_RESUME_ORIGINAL_CLOSURE: " + str(closure_checks))
	# Godot's format supports f rather than g; JSON above keeps all significant digits.
	print("JOURNEY_RESUME_CLOCK: before=%.17f after=%.17f delta=%.17f" % [before_clock, after_clock, after_clock - before_clock])
	return (_must(restored.pending and restored.token == frozen.token and restored.phase == frozen.phase
		and is_equal_approx(float(restored.elapsed_action_seconds), float(frozen.elapsed_action_seconds))
		and is_equal_approx(float(restored.return_required_action_seconds), float(frozen.return_required_action_seconds))
		and is_equal_approx(float(restored.return_elapsed_action_seconds), float(frozen.return_elapsed_action_seconds))
		# Same complete JSON number, as persisted by the original Slot. The real
		# parser changes this particular binary64 clock by one ULP; no epsilon,
		# rounding, timer reset or body/supply/fatigue comparison is introduced.
		and _same_json(float(controller.region_slot.control.logical_game_seconds), before_clock), "Formal cold resume replayed original progress or GAME: " + str({"before": frozen, "restored": restored, "clock_before": before_clock, "clock_after": float(controller.region_slot.control.logical_game_seconds), "checks": resume_checks, "binary_clock": clock_diagnostic}))
		and _must(_same_json(lab.terrain.site.team_supply, before_food)
			and PersonFatigue.read(team.combat_units[0]) == before_fatigue
			and PersonFatigue.read(team.combat_units[0], "fatigue_rest") == before_rest, "Cold resume changed original meal or shared fatigue history")
		and _shared_pool_original() and _preserved_rows() and _scene_absent())

func _shared_pool_original() -> bool:
	if not _must(not team.team_fatigue.is_empty() and int(team.team_fatigue.count) == 4, "Original four-person shared fatigue pool missing"): return false
	for row: Dictionary in team.combat_units:
		if not _must(is_same(PersonFatigue.pool(row), team.team_fatigue), "Journey cloned a personal fatigue authority"): return false
	return true

func _wait_original_ko(waiting_progress: float) -> bool:
	if not _shared_pool_original(): return false
	var initial_ko: float = float(team.combat_hot_get(0, &"ko", 0.0))
	var before_game: float = RegionSaveSlot._site_seconds(lab.terrain)
	var before_fatigue: float = PersonFatigue.read(team.combat_units[0])
	var entry: Dictionary = lab.terrain.site.team_supply[str(team_id)]
	var stock: Dictionary = controller._supply_stock(entry)
	var before_food: float = SiteSustain.rations(entry.sustain, stock)
	var meal_until: float = 0.0
	for cohort: Dictionary in entry.sustain.cohorts:
		meal_until = maxf(meal_until, float(cohort.meal_until))
	var original_speed: float = lab.simulation_speed
	# Only original public speed options; no direct KO/clock/body mutation.
	for choice in range(TerrainLab.SIMULATION_SPEEDS.size()):
		if lab.simulation_speed == TerrainLab.SIMULATION_SPEEDS.back(): break
		lab.change_simulation_speed(1)
	if not _must(lab.simulation_speed == 4.0, "Original public WAIT multiplier unavailable"): return false
	var requested_action: float = 0.0
	for step in range(120):
		if team.combat_can_act(0): break
		if not _step(1.0): return false
		requested_action += 1.0
		if not _must(controller.ship_journey_waiting_for_crew(boat_id) and int(controller.vehicles.records()[boat_id].operator_id) == 0
			and float(controller.ship_journey_status().elapsed_action_seconds) == waiting_progress, "WAIT advanced coarse distance during biological recovery"): return false
	# The recovered original pilot still has operator_id=0. Continue the
	# same WAIT until its next real six-hour meal, using original shared steps.
	# No KO, clock, food, fatigue or journey progress is assigned by this test.
	for meal_step in range(120):
		if RegionSaveSlot._site_seconds(lab.terrain) > meal_until + 0.000001: break
		if not _step(1.0): return false
		requested_action += 1.0
		if not _must(controller.ship_journey_waiting_for_crew(boat_id) and int(controller.vehicles.records()[boat_id].operator_id) == 0
			and float(controller.ship_journey_status().elapsed_action_seconds) == waiting_progress, "Due-meal WAIT advanced distance or accepted a phantom pilot"): return false
	if not _must(RegionSaveSlot._site_seconds(lab.terrain) > meal_until + 0.000001
		and SiteSustain.rations(entry.sustain, controller._supply_stock(entry)) < before_food, "Original coarse WAIT did not consume the next due meal from its actual boat stock"): return false
	for choice in range(TerrainLab.SIMULATION_SPEEDS.size()):
		if lab.simulation_speed == original_speed: break
		lab.change_simulation_speed(-1 if lab.simulation_speed > original_speed else 1)
	if not _must(lab.simulation_speed == original_speed and team.combat_can_act(0), "Original shared biology did not naturally recover its KO pilot"): return false
	var elapsed_game: float = RegionSaveSlot._site_seconds(lab.terrain) - before_game
	var after_food: float = SiteSustain.rations(entry.sustain, controller._supply_stock(entry))
	if not _must(elapsed_game >= initial_ko and is_equal_approx(float(entry.sustain.at), RegionSaveSlot._site_seconds(lab.terrain)), "WAIT skipped KO GAME time or left original feeding clock"): return false
	# Meals are prepaid for six-hour periods. Four hours within a covered meal
	# need not consume again; passing its boundary must use the original stock.
	if not _must(after_food >= 0.0 and after_food <= before_food and (float(entry.sustain.at) <= meal_until or after_food < before_food), "WAIT created food or skipped a due original meal"): return false
	if not _must(PersonFatigue.read(team.combat_units[0]) >= before_fatigue and _shared_pool_original(), "WAIT granted free rest or replaced original fatigue pool"): return false
	print("JOURNEY_REAL_KO_WAIT: requested_ACTION=%.3f GAME=%.3f food_before=%.6f food_after=%.6f" % [requested_action, elapsed_game, before_food, after_food])
	return true

func _run() -> void:
	deadline = Time.get_ticks_msec() + 240000
	if not _must(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(JOURNEY_OUT)) == OK, "Formal journey evidence directory unavailable"): return
	var coast: TerrainData = _fixed_coast()
	if coast == null: return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.bind_terrain(coast)
	_freeze_processes()
	controller = lab.site_controller
	controller.save_root = JOURNEY_OUT
	controller.save_path = JOURNEY_OUT.path_join("initial_original.json")
	if not _must(controller.save_to(controller.save_path).ok, "Original scene archive preflight failed"): return
	var archive := controller._archive_path()
	var old_person := lab.character.person_id
	world_id = "formal_ship_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	controller._region_form.manifest.text = OUT.path_join("manifest.json")
	controller._region_form.world.text = world_id
	controller._region_form.slot.text = "slot"
	controller._region_form.site_x.value = 0
	controller._region_form.site_y.value = 0
	var create_button: Button = lab.find_child("CreateFixedWorld", true, false)
	if not _must(create_button != null, "Formal new fixed-world UI missing"): return
	create_button.pressed.emit()
	_freeze_processes()
	if not _must(controller.get_region_slot() != null and controller.region_slot.control.active_site_id == str(lab.terrain.site.id)
		and FileAccess.file_exists(archive) and controller.get_script() == SiteController, "Formal new world did not preserve original archive and original Controller"): return
	var original_archive: Dictionary = Store._read(archive)
	if not _must(original_archive.ok and int(original_archive.payload.state.actors.player.person_id) == old_person, "Formal new world archive omitted its original person"): return
	for actor: Dictionary in lab.terrain.site.actors.values(): original_actor_ids.append(int(actor.person_id))
	team = lab.army
	team.role = "logistics"
	team.team_id = lab._next_army_identity()
	team.roster_size = 4
	var cells: Array[Vector2i] = [Vector2i(10, 21), Vector2i(11, 21), Vector2i(12, 21), Vector2i(13, 21)]
	if not _must(team.deploy_at(lab.terrain, lab.character, lab.npc, cells) and team.enable_combat(false, 0), "Formal journey original roster fixture rejected"): return
	lab.terrain.site.army_next_team = team.team_id + 1
	lab.terrain.site.army_trial_active = true
	team_id = team.team_id
	for index in range(4):
		team.combat_units[index].logistics = true
		people.append(team.combat_identity(index))
		var row: Dictionary = team.combat_units[index]
		item_ids.append(row.item_state.item_ids.duplicate())
		equipment.append(row.item_state.equipped.duplicate(true))
		cargo.append(row.cargo.duplicate(true))
	var pool: Dictionary = controller._enable_team_supply(team)
	if not _must(not pool.is_empty(), "Formal journey original supply owner unavailable"): return
	pool.inventory.grain = 8
	var deployed: Dictionary = controller.vehicles.deploy_ship(team, "ferry", Vector2i(9, 19), Vector2i.LEFT, true)
	if not _must(deployed.ok, "Formal journey original ferry fixture rejected: " + str(deployed)): return
	boat_id = str(deployed.vehicle_id)
	for index in range(4):
		if not _board_original(index): return
	var food: Dictionary = controller.transfer_ship_supply(team, "shore:%d" % lab.terrain.index(Vector2i(9, 20)), "vehicle:" + boat_id, {"grain": 8}, 0.0, people[0], true)
	if not _must(food.ok, "Formal journey physical food loading failed: " + str(food)): return
	var helm: Dictionary = controller.person_actions.begin_ship_helm(people[0], boat_id, people[0], true)
	if not _must(helm.ok, "Formal journey original helm fixture rejected") or not _finish_job(people[0]): return
	lab.terrain.site.controlled_person_id = people[0]
	var boat: Dictionary = controller.vehicles.records()[boat_id]
	var sailing: Dictionary = controller.vehicles.ship_order(boat_id, "sail", Vector2i(3, 19), people[0], true)
	if not _must(sailing.ok, "Formal edge navigation rejected: " + str(sailing)): return
	for step in range(40):
		if boat.move.is_empty() and boat.command.is_empty(): break
		controller.vehicles.update_ships(5.0)
	if not _must(lab.terrain.cell_from_index(int(boat.cell)) == Vector2i(3, 19) and boat.move.is_empty() and boat.command.is_empty(), "Formal original boat did not reach the outward edge"): return
	if not _capture_journey(): return
	original_items = lab.terrain.site.item_records.keys()
	if not _depart_ui() or not _scene_absent(): return
	var status: Dictionary = controller.ship_journey_status()
	var token := str(status.token)
	var required := float(status.seconds)
	if not _must(required > 0.0 and controller.region_replacement_guard().code == "BUSY", "Formal journey accepted zero distance or scene replacement"): return
	if not _must(controller.vehicles.ship_order(boat_id, "stop", Vector2i.ZERO, people[0], true).code == "BUSY"
		and controller.vehicles.deploy_ship(team, "ferry", Vector2i(30, 10), Vector2i.LEFT, true).code == "BUSY"
		and controller.person_actions.begin_ship_disembark(people[1], boat_id, people[1], Vector2i(9, 20), true).code == "BUSY", "Original source water/deployment/passenger geometry did not freeze"): return
	var before_fatigue := PersonFatigue.read(team.combat_units[0])
	var food_before := SiteSustain.rations(pool.sustain, controller._supply_stock(pool))
	if not _step(required * 0.5): return
	status = controller.ship_journey_status()
	if not _must(float(status.elapsed_action_seconds) > 0.0 and float(status.elapsed_action_seconds) < required
		and PersonFatigue.read(team.combat_units[0]) > before_fatigue, "Formal original ACTION progress or crew fatigue did not advance"): return
	# Original meals are prepaid. A short seam crossing must not charge a
	# second meal; the actual next due meal is tested below in natural crew WAIT.
	if not _must(SiteSustain.rations(pool.sustain, controller._supply_stock(pool)) <= food_before
		and is_equal_approx(float(pool.sustain.at), RegionSaveSlot._site_seconds(lab.terrain)), "Coarse original passengers created food or left the one shared GAME clock"): return
	var old_claim := Vector2i(3, 19)
	if not _must(not controller.vehicles._claims(boat).has(old_claim) and not controller.ship_journey_claims(boat).is_empty(), "Partial departure retained historical hull claims or released the whole hull early"): return
	var paused_status: Dictionary = status.duplicate(true)
	var paused_clock := float(controller.region_slot.control.logical_game_seconds)
	lab.terrain.site.paused = true
	lab._advance_action_time(1.0)
	if not _must(controller.ship_journey_status() == paused_status and float(controller.region_slot.control.logical_game_seconds) == paused_clock, "Paused formal journey advanced original ACTION/GAME"): return
	lab.terrain.site.paused = false
	if not _must(controller._checkpoint_ship_journey().ok, "Formal half-journey checkpoint rejected"): return
	if not _resume_ui(): return
	boat = controller.vehicles.records()[boat_id]
	var waiting_progress := float(controller.ship_journey_status().elapsed_action_seconds)
	team.apply_unit_contact(0, {"result": {"hp": 0.0, "stun": SiteCombatRules.STUN_LIMIT, "guard_break": false}, "shield": false})
	if not _must(float(team.combat_hot_get(0, &"ko", 0.0)) == SiteCombatRules.KNOCKOUT_GAME_SECONDS, "Original contact did not create a real four-hour KO"): return
	if not _step(0.05): return
	if not _must(controller.ship_journey_waiting_for_crew(boat_id) and int(boat.operator_id) == 0
		and float(controller.ship_journey_status().elapsed_action_seconds) == waiting_progress, "Original KO crew did not stop coarse travel or release its duty"): return
	if not _wait_original_ko(waiting_progress): return
	helm = controller.person_actions.begin_ship_helm(people[0], boat_id, people[0], true)
	if not _must(helm.ok, "Original recovered pilot could not resume the finite WAIT helm: " + str(helm)): return
	# The same original person is already in berth 0: this actual retry
	# has zero path length. Check WAIT before commit, then accept duty via
	# the original job. Nonzero deck paths are covered by naval lifecycle.
	if not _must(controller.person_actions.is_busy(people[0]) and int(boat.operator_id) == 0
		and controller.ship_journey_waiting_for_crew(boat_id)
		and float(controller.ship_journey_status().elapsed_action_seconds) == waiting_progress, "WAIT helm accepted duty before its original commit"): return
	if not _finish_job(people[0]): return
	if not _must(int(boat.operator_id) == people[0] and not controller.ship_journey_waiting_for_crew(boat_id), "Original recovered pilot did not regain original helm duty"): return
	var returning: Dictionary = controller.cancel_ship_journey()
	if not _must(returning.ok and str(controller.ship_journey_status().phase) == "return"
		and is_equal_approx(float(controller.ship_journey_status().return_required_action_seconds), waiting_progress), "Formal cancel did not retain a same-token equal-distance return"): return
	if not _must(controller.region_slot.commit_ship_transfer(token, lab.terrain).code == "INCOMPLETE_JOURNEY", "Returning token remained committable to destination"): return
	if not _resume_ui(): return
	for step in range(300):
		if not controller.ship_journey_active(): break
		if not _step(0.05): return
	if not _must(not controller.ship_journey_active() and controller._current_region_site() == FROM
		and controller.region_slot.commit_ship_transfer(token, lab.terrain).code == "CANCELLED", "Real return failed to restore original source or kept a replayable token"): return
	team = lab.army
	if not _preserved_rows(): return
	for identity: int in people:
		if not _must(not lab._combat_target(identity).is_empty() and controller.vehicles.ship_person_cell(identity) != TerrainArmy.INVALID_CELL, "Completed real return did not restore original Site bodies"): return
	if not _depart_ui(): return
	var arrival_token := str(controller.ship_journey_status().token)
	for step in range(600):
		if not controller.ship_journey_active(): break
		lab._advance_action_time(0.05)
	if not _must(not controller.ship_journey_active() and controller._current_region_site() == TO
		and str(controller.region_slot.control.active_site_id) == str(lab.terrain.site.id), "Formal original journey never atomically bound the destination"): return
	team = lab.army
	_freeze_processes()
	if not _preserved_rows(): return
	if not _must(lab.terrain.site.get("actor_presence_version", 0) == 1 and lab.terrain.site.actors.is_empty()
		and not lab.actor_present(lab.character) and not lab.actor_present(lab.npc), "Fresh destination manufactured original starter Actors"): return
	var source: Dictionary = controller.region_slot.open_site(FROM)
	if not _must(source.ok and source.data.site.armies.is_empty() and not source.data.site.vehicles.has(boat_id), "Committed source retained original traveler or hull copies"): return
	for identity: int in original_actor_ids:
		if not _must(RegionSaveSlot._saved_people(source.data.site).has(identity), "Source resident original Actor was transferred or deleted"): return
	if not _must(controller.region_slot.commit_ship_transfer(arrival_token, lab.terrain).code == "ALREADY_COMMITTED", "Committed arrival token remained replayable"): return
	if not _must(controller.save_to(controller.region_slot.site_path(TO)).ok, "Formal arrived original state could not save"): return
	var fire_source := controller.region_slot._load_checked(controller.region_slot.site_path(FROM), FROM)
	if not _must(fire_source.ok, "Committed Fire source snapshot could not reopen: " + str(fire_source)): return
	var source_fire := Store._validate_fire_transport_snapshot(fire_source.data, fire_source.data.site.get("fire", {}), fire_source.data.site.get("fire_transport", {}))
	var destination_fire := Store._validate_fire_transport_snapshot(lab.terrain, lab.terrain.site.get("fire", {}), lab.terrain.site.get("fire_transport", {}))
	if not _must(source_fire.ok and destination_fire.ok and not source_fire.state.orders.has(team_id)
		and destination_fire.state.orders.has(team_id), "Original Fire transport order did not move with its Team owner"): return
	var fire_clock: Dictionary = controller.region_slot.control.fire_clock
	var source_watermark: Dictionary = fire_source.data.site.fire_settlement
	var destination_watermark: Dictionary = lab.terrain.site.fire_settlement
	for pair: Array in [[fire_source.data.site.id, source_watermark], [lab.terrain.site.id, destination_watermark]]:
		var indexed: Dictionary = fire_clock.get("index", {}).get(str(pair[0]), {})
		var settled: Dictionary = pair[1]
		if not _must(not indexed.is_empty() and int(indexed.sequence) == int(settled.sequence)
			and float(indexed.action_seconds) == float(settled.action_seconds)
			and float(indexed.game_seconds) == float(settled.game_seconds), "Ship publication left the original Fire clock index behind its Site watermark"): return
	var before_world := float(controller.region_slot.control.logical_game_seconds)
	var resumed: Dictionary = controller.open_fixed_world(OUT.path_join("manifest.json"), world_id, "slot", FROM, false)
	if not _must(resumed.ok and controller._current_region_site() == TO and not controller.ship_journey_active()
		and float(controller.region_slot.control.logical_game_seconds) == before_world, "Formal arrived reopen changed active ownership or replayed GAME"): return
	team = lab.army
	if not _preserved_rows(): return
	print("SITE_SHIP_JOURNEY_PASS:original_ui:new_world_archive:partial_claims:one_shared_clock:pause:cold_resume:ko_wait_due_meal_real_helm:equal_return:atomic_arrival:no_actor_clone:no_replay")
	quit(0)
