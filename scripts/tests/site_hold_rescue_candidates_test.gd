extends "res://scripts/tests/site_army_scale_rules_test.gd"
## Small original-owner contract; existing rescue/ship suites retain their own deadlines.
class OriginalScan extends TerrainArmy:
	pass
class LoaderOnlyController extends SiteController:
	func _load_compatible_site(_path: String) -> Dictionary:
		return {"ok": false} # Unrelated loader override, like the hundred-person fixture.
class ChangedReaderController extends SiteController:
	func _person_has_duty(identity: int) -> bool:
		lab.set_meta("unexpected_reader_callback", identity)
		return false

func _must(value: bool, reason: String) -> bool:
	if not value:
		push_error("HOLD_RESCUE_CANDIDATES_FAIL: " + reason)
		quit(1)
	return value

func _world(original: bool, scenario: String) -> TerrainLab:
	var kind: GDScript = OriginalScan if original else TerrainArmy
	var lab: TerrainLab = _fixture(false, 8, false, kind)
	var team: TerrainArmy = lab.combat_armies[0]
	team.native_idle_enabled = false
	team.hold_empty_rescue_skip_enabled = false # Exercise this candidate independently of the old absence gate.
	team.combat_order = TerrainArmy.CombatOrder.HOLD
	team.enemy_query = lab._nearest_unit_enemy
	for army: TerrainArmy in lab.combat_armies:
		for row: Dictionary in army.combat_units:
			row.hp = 100.0; row.ko = 0.0; row.stun = 0.0; row.grace = 0.0
			row.pose = "idle"; row.age = 0.0; row.think = 0.0
	if scenario in ["member", "claimed_cancel", "ordered"]:
		team.combat_hot_set(3, &"ko", SiteCombatRules.KNOCKOUT_GAME_SECONDS)
		team.combat_hot_set(3, &"pose", "unconscious")
		team._cell_owners.erase(team.cells[3])
		if scenario == "ordered":
			team.combat_hot_set(1, &"ko", SiteCombatRules.KNOCKOUT_GAME_SECONDS)
			team.combat_hot_set(1, &"pose", "unconscious")
			team._cell_owners.erase(team.cells[1])
		if scenario == "claimed_cancel":
			# Existing rescue now out of reach: the original row1 cancellation frees row3 for row2.
			team._unit_rescues[1] = {"patient": 3, "revision": 0}
			team.combat_hot_set(1, &"pose", "rescue")
	elif scenario == "wake_callback":
		team.combat_hot_set(1, &"ko", 0.001)
		team.combat_hot_set(1, &"pose", "unconscious")
		team._cell_owners.erase(team.cells[1])
		team.set_meta(&"region_wake_sink", func(_identity: int) -> bool:
			team.combat_hot_set(3, &"ko", SiteCombatRules.KNOCKOUT_GAME_SECONDS)
			team.combat_hot_set(3, &"pose", "unconscious")
			team._cell_owners.erase(team.cells[3])
			return false)
	elif scenario == "move_callback":
		team.audio_step_sink = func(_identity: int, _ground: Vector2, _duration: float, _running: bool, _mounted: bool) -> void:
			team.combat_hot_set(3, &"ko", SiteCombatRules.KNOCKOUT_GAME_SECONDS)
			team.combat_hot_set(3, &"pose", "unconscious")
			team._cell_owners.erase(team.cells[3])
		var reserved: bool = team._reserve_combat_step(1, team.cells[1] + Vector2i.DOWN)
		if not _must(reserved, "real move reserved before callback interleaving"): return lab
		team.move_progress[1] = 0.999999
	if scenario in ["player", "ordered"]:
		var actor: TerrainTestCharacter = TerrainTestCharacter.new()
		actor.person_id = 900001; actor.faction_id = team.faction_id
		actor.terrain_cell = team.cells[0] + Vector2i.UP
		actor.position = (Vector2(actor.terrain_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
		actor.knockout_left = SiteCombatRules.KNOCKOUT_GAME_SECONDS
		team.player_member = actor
	return lab

func _close(lab: TerrainLab) -> void:
	var team: TerrainArmy = lab.combat_armies[0]
	if is_instance_valid(team.player_member): team.player_member.free(); team.player_member = null
	_dispose(lab)

func _run() -> void:
	for scenario: String in ["none", "member", "claimed_cancel", "wake_callback", "move_callback", "player", "ordered"]:
		var reference: TerrainLab = _world(true, scenario)
		var candidate: TerrainLab = _world(false, scenario)
		var team: TerrainArmy = candidate.combat_armies[0]
		if not _must(team._hold_rescue_candidate_cache_admitted(), "ordinary original read closure admitted"): return
		for lab: TerrainLab in [reference, candidate]: lab.combat_armies[0].prepare_combat(1.0 / 30.0)
		var original_team: TerrainArmy = reference.combat_armies[0]
		if not _must(var_to_bytes([_state(reference), original_team._unit_rescues, original_team.facing, original_team._cell_owners, original_team._reserved_cells]) == var_to_bytes([_state(candidate), team._unit_rescues, team.facing, team._cell_owners, team._reserved_cells]), "full original rows/claims/facing/reservations and first patient parity: " + scenario): return
		if scenario in ["member", "claimed_cancel", "wake_callback", "move_callback"]:
			if not _must(team._unit_rescues.get(2, {}).get("patient", -99) == 3, "real row2 gets the same available original patient after " + scenario): return
		elif scenario == "ordered":
			if not _must(team._unit_rescues.get(0, {}).get("patient", -99) == 1 and team._hold_rescue_candidates() == [1, 3, TerrainArmy.PLAYER_MEMBER], "command_members order and first success precede PLAYER_MEMBER"): return
		elif scenario == "player":
			if not _must(team._unit_rescues.get(0, {}).get("patient", 0) == TerrainArmy.PLAYER_MEMBER, "PLAYER_MEMBER kept in original command order"): return
		_close(reference); _close(candidate)
	var probe: TerrainLab = _world(false, "none")
	var team: TerrainArmy = probe.combat_armies[0]
	var controller: SiteController = LoaderOnlyController.new()
	controller.lab = probe; probe.add_child(controller); probe.site_controller = controller
	controller.vehicles.init(controller); controller.person_actions.init(probe); controller.work_team.init(probe)
	team.person_busy_query = controller._person_has_duty
	if not _must(team._hold_rescue_candidate_cache_admitted(), "inherited read methods admit unrelated loader-only Controller subclass"): return
	# A canonical disabled EMPTY spare is outside the data/transport reader closure.
	var spare: TerrainArmy = TerrainArmy.new()
	spare.vehicle_transport = controller.vehicles
	probe.combat_armies.append(spare)
	if not _must(team._hold_rescue_candidate_cache_admitted(), "unbound disabled empty original spare has no reachable foreign data/transport reader"): return
	spare.combat_enabled = true
	if not _must(not team._hold_rescue_candidate_cache_admitted(), "active unbound original spare still rejects data/transport mismatch"): return
	spare.combat_enabled = false
	spare.combat_units.append(team.combat_units[0])
	if not _must(not team._hold_rescue_candidate_cache_admitted(), "disabled populated original owner still requires the original data/transport proof"): return
	spare.combat_units.clear()
	spare.player_member = TerrainTestCharacter.new()
	if not _must(not team._hold_rescue_candidate_cache_admitted(), "disabled original owner with PLAYER still requires identity-reader admission"): return
	spare.player_member.free()
	spare.player_member = null
	probe.combat_armies.erase(spare)
	spare.free()
	var unknown_spare: TerrainArmy = OriginalScan.new()
	probe.combat_armies.append(unknown_spare)
	if not _must(not team._hold_rescue_candidate_cache_admitted(), "unknown script still falls back even on an empty disabled spare"): return
	probe.combat_armies.erase(unknown_spare)
	unknown_spare.free()
	team.person_busy_query = Callable()
	probe.combat_armies[1].vehicle_transport = controller.vehicles
	if not _must(not team._hold_rescue_candidate_cache_admitted(), "source without transport cannot admit another team's unproved provider"): return
	probe.combat_armies[1].vehicle_transport = null
	probe.site_controller = null; controller.free()
	controller = ChangedReaderController.new(); controller.lab = probe; probe.add_child(controller); probe.site_controller = controller
	controller.vehicles.init(controller); controller.person_actions.init(probe); controller.work_team.init(probe)
	team.person_busy_query = controller._person_has_duty
	if not _must(not team._hold_rescue_candidate_cache_admitted() and not probe.has_meta("unexpected_reader_callback"), "reader override falls back without invoking it in admission"): return
	team.person_busy_query = Callable(); probe.site_controller = null; controller.free()
	# Threshold and membership remain live; healthy rows never enter the superset.
	team.combat_hot_set(0, &"ko", SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS)
	team.combat_hot_set(1, &"ko", SiteCombatRules.RESCUED_KNOCKOUT_GAME_SECONDS + 0.001)
	team.combat_hot_set(2, &"ko", SiteCombatRules.KNOCKOUT_GAME_SECONDS)
	team.combat_hot_set(2, &"member", false)
	if not _must(team._hold_rescue_candidates() == [1], "exact threshold excluded, above threshold retained, nonmember excluded in original order"): return
	for index: int in range(team.combat_units.size()):
		team.combat_hot_set(index, &"ko", 0.0)
		team.combat_hot_set(index, &"member", true)
	team.native_hot_enabled = true
	var hot: bool = team._try_install_combat_hot_store()
	if hot:
		team._borrow_combat_hot_row(1)
		team.combat_units[1].ko = SiteCombatRules.KNOCKOUT_GAME_SECONDS
		var patients: Array[int] = team._hold_rescue_candidates()
		team._return_combat_hot_row()
		if not _must(patients == [1], "borrowed live KO overrides stored native column"): return
	else: print("HOLD_RESCUE_NATIVE_BORROW_NOT_EXERCISED")
	_close(probe)
	print("HOLD_RESCUE_CANDIDATES_PASS original first-patient/state, PLAYER, same-call cancel/wake/move, inherited/unknown readers")
	TerrainArmy.release_contact_source()
	quit(0)
