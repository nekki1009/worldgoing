extends "res://scripts/tests/site_siege_store_roundtrip_test.gd"
## CANDIDATE / NOT_RUN. Reuses the original persistent fixture and actual
## Controller save/load. Requires --site-test-ui for original formation input.
const LOAD_OUT := "res://output/fire_implementation_20261006/p1_coverage_candidate"
const LOAD_STEP := 1.0 / 30.0
const LOAD_GOAL := Vector2i(34, 26)
var load_checks := 0
var load_failed := false
var load_finished := false
var load_evidence: Array[Dictionary] = []

func _initialize() -> void:
	roundtrip_deadline = Time.get_ticks_msec() + 120000
	_run.call_deferred()

func _load_check(ok: bool, label: String, detail: Variant = null) -> bool:
	load_checks += 1
	if not ok:
		load_failed = true
		push_error("FIRE_LOAD_GUARD_FAIL: " + label + " " + str(detail))
	return ok

func _roundtrip_require(ok: bool, message: String) -> bool:
	return _load_check(ok, message)

func _load_finish(ok: bool, reason: String = "") -> void:
	if load_finished: return
	load_finished = true
	if is_instance_valid(roundtrip_lab):
		roundtrip_lab.terrain.remove_meta(&"fire_event_guard")
		roundtrip_lab.free()
	TerrainArmy.release_contact_source()
	var file := FileAccess.open(LOAD_OUT + "/load_guard_result.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": ok and not load_failed, "checks": load_checks,
			"reason": reason, "evidence": load_evidence,
			"scope": "P1 actual headless load_from with valid original save; GPU _load_path is static-only, no GPU/Native/restoration acceptance"}, "\t"))
		file.close()
	print("SITE_FIRE_LOAD_GUARD_", "PASS" if ok and not load_failed else "FAIL", ": checks=", load_checks, " ", reason)
	await process_frame
	quit(0 if ok and not load_failed else 1)

func _source_bytes() -> Dictionary:
	var result := {}
	for path: String in ["res://scripts/terrain_lab/site_controller.gd", "res://scripts/terrain_lab/site_store.gd",
		"res://scripts/terrain_lab/terrain_lab.gd", "res://scripts/terrain_lab/terrain_test_character.gd", "res://scripts/terrain_lab/terrain_army.gd"]:
		result[path] = FileAccess.get_sha256(path)
	return result

func _input_bytes() -> PackedByteArray:
	var ui: SiteController = roundtrip_lab.site_controller
	var values: Array = []
	for property: String in ["_active_formation_view", "_crowd_facing", "_facing_order_source", "_facing_order_anchor",
		"_facing_preview_direction", "_facing_preview_pending", "_facing_team_id", "_facing_requester_identity",
		"_facing_preset_id", "_facing_order_serial", "_facing_roster_hash", "_facing_navigation_revision",
		"_formation_candidate_id", "_formation_candidate_source", "_formation_candidate_team_id",
		"_formation_candidate_requester_identity", "_formation_preview_signature", "_formation_preview_note"]:
		values.append(ui.get(property))
	for property: String in ["_facing_team", "_facing_terrain", "_formation_candidate_team", "_formation_candidate_terrain"]:
		var owner: Variant = ui.get(property)
		values.append(owner.get_instance_id() if is_instance_valid(owner) else 0)
	values.append([ui.view.combat_preview_facing, ui.view.combat_preview_platform_slots, ui.view.combat_preview_queue_slots])
	return var_to_bytes(values)

func _live_bytes() -> PackedByteArray:
	var lab := roundtrip_lab
	var reservations := {}
	for identity: int in lab.fire_reservations:
		var reservation: Dictionary = lab.fire_reservations[identity].duplicate(true)
		reservation.person.owner = reservation.person.owner.get_instance_id()
		reservations[identity] = reservation
	var rosters: Array = []
	for team: TerrainArmy in lab.combat_armies:
		rosters.append([team.get_instance_id(), team.capture_combat_state(), team.cells, team.moving_to,
			team.move_progress, team.move_duration, team.move_curve, team.facing, team._reserved_cells])
	return var_to_bytes([lab.terrain.get_instance_id(), lab.terrain.site, lab.terrain.flags, lab.terrain.height_levels,
		lab.terrain.static_blocked, lab.terrain.navigation_revision, lab.character.get_instance_id(), lab.character.capture_state(),
		lab.character.ammo_inventory, lab.character.item_state, lab.npc.capture_state(), lab.npc.ammo_inventory,
		rosters, reservations, lab.fire_projectiles, lab.fire_impact_recorder, lab.fire_action_cursor,
		lab._fire_release_sequence, lab.ranged_shots, lab.ranged_resolutions, lab._fire_unsaved, _input_bytes()])

func _shared_load_step() -> bool:
	var result := roundtrip_lab._advance_original_shared_step(LOAD_STEP)
	return _load_check(result.ok and result.get("completed", false), "Original complete shared step", result)

func _arm_original_input() -> bool:
	var lab := roundtrip_lab
	var ui := lab.site_controller
	var team := lab.army
	var move := team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, LOAD_GOAL)
	if not _load_check(move.ok, "Original Army accepts the live MOVE that load must preserve", move): return false
	var committed := false
	for tick in range(12):
		if not _shared_load_step(): return false
		for index in range(team.cells.size()):
			if team.moving_to[index] != TerrainArmy.INVALID_CELL and float(team.move_progress[index]) > 0.0 and float(team.move_progress[index]) < 1.0:
				committed = true
		if committed: break
	if not _load_check(committed and lab.terrain.site.combat_left == 0.0,
		"Original live half-step exists without combat time; no fabricated movement state"): return false
	ui._use_formation_controls("test")
	if not _load_check(ui.formation_command_source != null, "Original test formation controls are present"): return false
	ui.formation_command_source.select(1)
	ui._formation_context_changed()
	ui.formation_preset_choice.select(1)
	ui._select_formation_candidate(1)
	if not _load_check(not ui._formation_candidate_id.is_empty(), "Original formation candidate is pending before rejection"): return false
	lab.camera.position = lab.renderer.cell_center(LOAD_GOAL)
	lab.camera.force_update_scroll()
	ui._layout()
	ui._begin_facing_move("test")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = lab.get_viewport().get_canvas_transform() * lab.renderer.cell_center(LOAD_GOAL)
	if not _load_check(ui.camera_usable_rect().has_point(press.position) and ui.handle_input(press), "Original map press establishes facing MOVE anchor"): return false
	var drag := InputEventMouseMotion.new()
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	drag.position = lab.get_viewport().get_canvas_transform() * lab.renderer.cell_center(LOAD_GOAL + Vector2i.UP * 2)
	return _load_check(ui.handle_input(drag) and ui._facing_order_source == "test"
		and ui._facing_order_anchor == LOAD_GOAL and ui._facing_preview_direction == Vector2i.UP
		and not ui._formation_candidate_id.is_empty(), "Original facing gesture, formation candidate and live Army MOVE coexist")

func _reject_valid_load(path: String, stage: String, save_bytes: PackedByteArray) -> bool:
	var lab := roundtrip_lab
	var ui := lab.site_controller
	var direct := lab.fire_save_guard()
	var original := SiteStore.fire_event_guard(lab.terrain)
	if not _load_check(lab.terrain.site.combat_left == 0.0 and not direct.ok and direct.code == "BUSY"
		and not original.ok and original.code == "BUSY", "Fire guard itself rejects while the old combat timer is zero", stage): return false
	var before := _live_bytes()
	var source_before := _source_bytes()
	var rejected: Dictionary = ui.load_from(path) # Same original save_path: no archive substitute.
	if not _load_check(not rejected.ok and rejected.code == "BUSY" and _live_bytes() == before
		and FileAccess.get_file_as_bytes(path) == save_bytes and _source_bytes() == source_before,
		"Actual Controller load preserves pending facing/move/formation, owners, cargo, source files and valid save bytes", {"stage": stage, "result": rejected}): return false
	load_evidence.append({"case": stage, "combat_left": lab.terrain.site.combat_left,
		"reservations": lab.fire_reservations.size(), "flights": lab.fire_projectiles.size(), "unsaved": lab._fire_unsaved,
		"fire_guard": direct, "result": rejected, "live_sha256": before.hex_encode().sha256_text(),
		"save_sha256": FileAccess.get_sha256(path), "sources": source_before})
	return true

func _load_case(cooled: bool) -> bool:
	roundtrip_lab = TerrainLab.new()
	roundtrip_lab.npc = TerrainTestNPC.new()
	roundtrip_lab.pause_when_unfocused = false
	root.add_child(roundtrip_lab)
	roundtrip_lab.set_process(false)
	roundtrip_lab.set_process_unhandled_input(false)
	var ui := roundtrip_lab.site_controller
	ui.set_process(false)
	ui._auto_save_blocked = true
	for actor: TerrainTestCharacter in roundtrip_lab.combat_actors: actor.set_process(false)
	var data := _persistent_fixture()
	if data == null or load_failed: return false
	roundtrip_lab.bind_terrain(data)
	roundtrip_lab.physical_ranged_enabled = true
	roundtrip_lab.exchange_enabled = true
	roundtrip_lab.character.exchange_enabled = true
	roundtrip_lab.npc_retaliates = false
	ui.release_worker()
	var actor := roundtrip_lab.character
	if not _load_check(actor.place(Vector2i(8, 8), true), "Original saved archer occupies its real clear cell"): return false
	actor.item_state.equipped.erase("weapon")
	var made := SiteRuntime.create_equipment(data, actor.item_state, "load_guard_bow", {"slot": "weapon", "asset": "bow_01", "tint": [1.0, 1.0, 1.0, 1.0]}, actor.person_id, "weapon")
	if not _load_check(made.ok, "Original registry owns the fixture bow", made): return false
	actor.ammo_inventory.fire_arrow = 1
	var team := roundtrip_lab.army
	team.team_id = 1
	team.roster_size = 3
	var positions: Array[Vector2i] = [Vector2i(16, 20), Vector2i(19, 20), Vector2i(19, 21)]
	if not _load_check(team.deploy_at(data, actor, roundtrip_lab.npc, positions) and team.enable_combat(false, 0, &"bow"), "Original saved three-person roster is admitted"): return false
	team.set_process(false)
	data.site.army_next_team = 2
	var path := LOAD_OUT + ("/cooled_valid.json" if cooled else "/preparing_valid.json")
	ui.save_root = LOAD_OUT
	ui.save_path = path
	var saved: Dictionary = ui.save_to(path)
	if not _load_check(saved.ok, "Actual Controller creates valid pre-fire saved bytes", saved): return false
	ui._auto_save_blocked = true
	var readable := SiteStore.load_site(path)
	if not _load_check(readable.ok and readable.data is TerrainData, "Original Store independently accepts the unmodified actual saved file", readable.get("code", "")): return false
	var save_bytes := FileAccess.get_file_as_bytes(path)
	await process_frame
	var target := {"type": "ground", "cell": [14, 8]}
	if cooled:
		if not _load_check(roundtrip_lab.issue_fire_order(actor.person_id, actor, target, "FIRE_ARROW").ok, "Original finite fire order"): return false
		for tick in range(120):
			if not _shared_load_step(): return false
			if roundtrip_lab.ranged_shots == 1: break
		if not _load_check(roundtrip_lab.ranged_shots == 1 and actor.ammo_inventory.fire_arrow == 0, "Actual original release consumes the one held arrow"): return false
		if not _load_check(roundtrip_lab.stop_fire_order(actor.person_id, actor).ok
			and roundtrip_lab.issue_fire_order(actor.person_id, actor, target, "NORMAL").ok
			and roundtrip_lab.stop_fire_order(actor.person_id, actor).ok, "Original commands return to inactive NORMAL without deleting the paid flight"): return false
		for tick in range(420):
			if not _shared_load_step(): return false
			if roundtrip_lab.fire_projectiles.is_empty() and data.site.combat_left == 0.0: break
		if not _load_check(roundtrip_lab.ranged_resolutions == 1 and roundtrip_lab.fire_reservations.is_empty()
			and roundtrip_lab.fire_projectiles.is_empty() and roundtrip_lab._fire_unsaved and not actor.ranged_enabled
			and actor.ranged_ammo_mode == "NORMAL" and data.site.combat_left == 0.0,
			"Real terminal and original grace expiry leave only unsaved fire history, with no typed mode or combat timer substitute"): return false
	if not _arm_original_input(): return false
	if not cooled:
		if not _load_check(roundtrip_lab.issue_fire_order(actor.person_id, actor, target, "FIRE_ARROW").ok, "Original prepare-only command"): return false
		var person := {"owner": actor, "unit": -1, "id": actor.person_id, "cell": actor.terrain_cell, "faction": actor.faction_id}
		var prepared := roundtrip_lab.request_fire_release(person, target)
		if not _load_check(prepared.ok and roundtrip_lab.fire_reservations.size() == 1 and roundtrip_lab.ranged_shots == 0
			and actor.ammo_inventory.fire_arrow == 1 and not roundtrip_lab._fire_unsaved and data.site.combat_left == 0.0,
			"Actual unpaid preparation blocks replacement before combat_event or any debit", prepared): return false
	if not _reject_valid_load(path, "cooled_unsaved_combat_zero" if cooled else "preparing_combat_zero", save_bytes): return false
	data.remove_meta(&"fire_event_guard")
	roundtrip_lab.free()
	roundtrip_lab = null
	return true

func _run() -> void:
	if not _load_check(DisplayServer.get_name() == "headless" and OS.get_cmdline_user_args().has("--site-test-ui"), "Use headless with explicit --site-test-ui; no GPU acceptance"): _load_finish(false); return
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOAD_OUT))
	if not await _load_case(false): _load_finish(false, "preparing original load"); return
	if not await _load_case(true): _load_finish(false, "cooled original load"); return
	_load_finish(true, "actual original load_from rejects both fire-only BUSY states before input cancellation or candidate commit")
