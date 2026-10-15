extends "res://scripts/tests/site_ship_full_transport_test.gd"
## Original UI/count guards plus real two-ship hundred-person command geometry.

const TestWindow = preload("res://scripts/terrain_lab/site_test_window.gd")

# Nekki 2026-10-14 23:28Z (decision card, option A): this test's own budget is
# 300 s instead of the shared 240 s; raised to 360 s by Nekki 2026-10-15 10:37Z.
# Its 0.51 s fixture step and fixture
# controller send all 100 rows through the GD HOLD review every step; the
# assertions are unchanged. Recorded in
# output/acceptance_efficiency_20261012/timeout/timeout_adjustments_20261015_nekki.json.
func _ship_test_deadline_ms(default_ms: int = 360000) -> int:
	return super(default_ms)

func _ui_boundary() -> bool:
	var controller: SiteController = lab.site_controller
	if not is_instance_valid(lab.site_test_window):
		lab.site_test_window = TestWindow.new()
		lab.add_child(lab.site_test_window)
		lab.site_test_window.call("setup", lab)
	for field: String in ["trial_friendly_count", "trial_enemy_count", "trial_third_count"]:
		var input: SpinBox = controller.get(field)
		if not _must(is_instance_valid(input) and input.max_value == 100.0 and not input.allow_greater, "Original %s UI no longer enforces its hundred-person boundary" % field): return false
		input.value = 101.0
		if not _must(input.value == 100.0, "Original UI allowed a 101st roster slot"): return false
	var ui: Dictionary = controller._trial_setup()
	if not _must(int(ui.friendly_count) == 100 and int(ui.enemy_count) == 100 and int(ui.third_count) == 100, "Actual original UI setup did not retain its clamped counts"): return false
	var before: PackedByteArray = var_to_bytes(lab.terrain.site)
	var invalid: Dictionary = lab.start_melee_trial({"friendly_count": 101, "enemy_count": 1, "friendly_role": "logistics"})
	if not _must(not invalid.ok and invalid.code == "INVALID" and var_to_bytes(lab.terrain.site) == before, "Original public deployment did not atomically reject 101 real people"): return false
	var parsed: Dictionary = lab._trial_side_settings({"friendly_count": 100, "friendly_role": "logistics"}, "friendly")
	if not _must(parsed.ok and int(parsed.side.count) == 100 and int(parsed.side.slot_count) == 100, "Original hundred-person entry unexpectedly deducted boat slots"): return false
	print("SITE_SHIP_ROSTER_UI_101_PASS")
	return true

func _geometry(label: String, native_calls: int) -> bool:
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var positions: Array[Vector2] = []
	var historical: Array[Vector2] = []
	var identities: Array[int] = []
	var previous: Array[bool] = []
	for index in range(100):
		positions.append(vehicles.ship_person_ground(people[index]) / TerrainRenderer.CELL_PIXELS)
		historical.append((Vector2(team.cells[index]) + Vector2.ONE * 0.5))
		identities.append(people[index])
		previous.append(bool(team.combat_hot_get(index, &"present", false)))
	var expected: Vector2 = TerrainArmy._command_reference_from_positions(positions, identities)
	var old_reference: Vector2 = TerrainArmy._command_reference_from_positions(historical, identities)
	_settle_commands()
	if not _must(team.command_reference_valid and team.command_reference.is_equal_approx(expected) and not expected.is_equal_approx(old_reference), "Effective hundred-person command reference disagrees with physical boats: " + label): return false
	var free_members: Array[int] = []
	for member: int in team.command_members():
		if member >= 0 and member < 100 and not team.member_gone(member) and not bool(team.combat_hot_get(member, &"captive")): free_members.append(member)
	for index in range(100):
		var radius := team.command_radius + (2.0 if previous[index] else 0.0)
		var present := team.combat_can_act(index) and expected.distance_to(positions[index]) <= radius
		# Nekki 2026-10-13 (commander presence, option 1): the formal and acting commanders
		# are also present within the radius of any other free member of their formation.
		if not present and team.combat_can_act(index) and (index == team.formal_commander or index == team.acting_commander):
			for member: int in free_members:
				if member != index and positions[member].distance_to(positions[index]) <= radius:
					present = true
					break
		if not _must(bool(team.combat_hot_get(index, &"present", false)) == present and team.combat_ground(index).is_equal_approx(vehicles.ship_person_ground(people[index])), "Effective original presence disagrees at #%d: %s" % [people[index], label]): return false
		if not _must(not team._cell_owners.values().has(index) and team.moving_to[index] == TerrainArmy.INVALID_CELL, "Geometry refresh published a historical shore claim: " + label): return false
	return _must(team.native_presence_delta_calls == native_calls and team._presence_geometry_cache.is_empty(), "Aboard hundred-person presence reused native historical cells: " + label)

func _move_boat(id: String, action: String, target: Vector2i, requester: int, native_calls: int, label: String) -> bool:
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var ordered: Dictionary = vehicles.ship_order(id, action, target, requester, true)
	if not _must(ordered.ok, "Original geometry route rejected: %s: %s" % [label, str(ordered)]): return false
	var boat: Dictionary = vehicles.records()[id]
	var samples := 0
	for tick in range(512):
		vehicles.update_ships(0.25)
		if not boat.move.is_empty() and tick % 4 == 0:
			if not _geometry(label + ":moving", native_calls): return false
			samples += 1
		if boat.move.is_empty() and boat.command.is_empty(): break
	if not _must(samples > 0 and boat.move.is_empty() and boat.command.is_empty() and lab.terrain.cell_from_index(int(boat.cell)) == target, "Original geometry route did not physically complete: " + label): return false
	return _geometry(label + ":stopped", native_calls)

func _run() -> void:
	if not _must(DisplayServer.get_name() == "headless", "Roster/command integration uses the bounded headless verifier"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	_freeze_processes()
	if not _fixture() or not _ui_boundary(): return
	team = lab.army
	team.role = "logistics"
	team.team_id = lab._next_army_identity()
	team.roster_size = 100
	if not _must(team.deploy_at(lab.terrain, lab.character, lab.npc, parking) and team.enable_combat(false, 0), "Original hundred-person command fixture deployment rejected"): return
	lab.terrain.site.army_next_team = team.team_id + 1
	lab.terrain.site.army_trial_active = true
	team_id = team.team_id
	for index in range(100):
		var row: Dictionary = team.combat_units[index]
		row.logistics = true
		people.append(team.combat_identity(index))
		item_ids.append(row.item_state.item_ids.duplicate())
		equipment.append(row.item_state.equipped.duplicate(true))
		cargo.append(row.cargo.duplicate(true))
		initial_q += Runtime.carried_load(lab.terrain.site, row.cargo, row.item_state) + float(row.item_state.equipped.size())
	initial_next_person = int(lab.terrain.site.next_person_id)
	fingerprint = lab.terrain.fingerprint()
	var promoted: Dictionary = team.set_military_role(people[50], "officer")
	var officers: Array[int] = [50]
	if not _must(promoted.ok and team.record_officer_service(officers, true).ok, "Original deputy appointment failed"): return
	# Explicit valid radius inputs exercise proximity and unambiguous KO takeover.
	team.command_radius = 40.0
	var vehicles: SiteVehicleTransport = lab.site_controller.vehicles
	var actions: SitePersonActions = lab.site_controller.person_actions
	var boat_ids: Array[String] = []
	for hull in range(2):
		var deployed: Dictionary = vehicles.deploy_ship(team, "troop", _anchor("troop", hull), _facing("troop", hull), true)
		if not _must(deployed.ok, "Original command boat deployment rejected: " + str(deployed)): return
		boat_ids.append(str(deployed.vehicle_id))
	for index in range(100):
		var hull := floori(float(index) / 50.0)
		if not _walk(index, _shore("troop", hull)): return
		var begun: Dictionary = actions.begin_ship_board(people[index], boat_ids[hull], people[index], index % 50, true)
		if not _must(begun.ok, "Original hundred-person command boarding rejected: " + str(begun)) or not _finish_job(people[index]): return
		if index % 50 == 0:
			var helm: Dictionary = actions.begin_ship_helm(people[index], boat_ids[hull], people[index], true)
			if not _must(helm.ok, "Original command captain helm rejected: " + str(helm)) or not _finish_job(people[index]): return
	if not _people_intact(true, initial_next_person): return
	if not _must(vehicles.team_vehicle_count(team) == 0 and vehicles.records().size() == 2, "Two real ships consumed hundred-person roster slots"): return
	var before: PackedByteArray = var_to_bytes(lab.terrain.site)
	var invalid: Dictionary = lab._trial_side_settings({"friendly_count": 101, "friendly_role": "logistics"}, "friendly")
	if not _must(not invalid.ok and invalid.code == "INVALID" and var_to_bytes(lab.terrain.site) == before, "Already embarked ships let the original 101-person guard mutate or accept"): return
	_settle_commands()
	var native_calls := team.native_presence_delta_calls
	if not _must(team.formal_commander == 0 and team.current_commander == 0, "Original formal commander did not retain broad-range eligibility"): return
	team.command_radius = 8.0
	if not _geometry("initial_two_ships", native_calls): return
	if not _move_boat(boat_ids[1], "sail", _target("troop", 1, 10), people[50], native_calls, "separated"): return
	if not _move_boat(boat_ids[1], "sail", _anchor("troop", 1), people[50], native_calls, "reconverged"): return
	team.command_radius = 40.0
	if not _geometry("before_KO", native_calls): return
	var q0: float = vehicles.ship_load(boat_ids[0])
	var q1: float = vehicles.ship_load(boat_ids[1])
	team.apply_unit_contact(0, {"result": {"hp": 0.0, "stun": 1000.0, "guard_break": false}, "shield": false})
	if not _geometry("commander_KO", native_calls): return
	if not _must(float(team.combat_hot_get(0, &"ko", 0.0)) > 0.0 and not team.command_eligible(0) and team.formal_commander == 0 and team.acting_commander == 50 and team.current_commander == 50,
		"Original aboard KO did not select the appointed living deputy without replacing the formal commander"): return
	if not _must(vehicles.ship_people(vehicles.records()[boat_ids[0]]).size() == 50 and vehicles.ship_people(vehicles.records()[boat_ids[1]]).size() == 50
		and is_equal_approx(vehicles.ship_load(boat_ids[0]), q0) and is_equal_approx(vehicles.ship_load(boat_ids[1]), q1), "Command KO changed real passengers or Q"): return
	var knocked := float(team.combat_hot_get(0, &"ko", 0.0))
	team.prepare_combat(0.01, knocked + 0.1)
	team.prepare_combat(float(TerrainArmy.CombatTimings.POSE_SECONDS[&"get_up"]) + 0.1, 0.0)
	if not _geometry("commander_recovered", native_calls): return
	if not _must(team.combat_can_act(0) and team.formal_commander == 0 and team.current_commander == 0 and team.acting_commander == -1, "Original recovered commander failed to resume the existing appointment"): return
	for index in range(100):
		var hull := floori(float(index) / 50.0)
		var shore := _shore("troop", hull)
		var left: Dictionary = actions.begin_ship_disembark(people[index], boat_ids[hull], people[index], shore, true)
		if not _must(left.ok, "Original command fixture disembark rejected: " + str(left)) or not _finish_job(people[index]) or not _walk(index, parking[index]): return
	if not _people_intact(false, initial_next_person): return
	# Every passenger has left; the original qualified native projection may rebuild.
	team._refresh_command_presence()
	if not _must(not vehicles.team_has_embarked(team.team_id) and team.native_presence_delta_calls > native_calls and not team._presence_geometry_cache.is_empty(), "Last real disembark did not rebuild/reactivate native ground presence"): return
	if not _must(actions._jobs.is_empty() and team.combat_order == TerrainArmy.CombatOrder.HOLD and not team.tactical_ai_enabled, "Final command fixture retained ship jobs or resumed old orders"): return
	print("SITE_SHIP_ROSTER_COMMAND_PASS:people=100:real_board=100:real_disembark=100:ships=2:101_UI_guard:split_rejoin:KO_deputy:GD_native_handoff")
	quit(0)
