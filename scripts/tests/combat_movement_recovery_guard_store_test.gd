extends SceneTree
## A rotated final-slot target must not reverse immediately after real SiteStore I/O.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const SAVE := "res://.godot-temp/site_combat/recovery-guard.json"
const CORRUPT := SAVE + ".corrupt"
const LEGACY := SAVE + ".legacy"

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if ok: return true
	push_error(message)
	quit(1)
	return false

func _write_envelope(path: String, payload: Dictionary) -> bool:
	var body := JSON.stringify(payload, "", true, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify({"checksum": body.sha256_text(), "payload": body}, "\t"))
	file.close()
	return true

func _run() -> void:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	SiteEnvironment.initialize(data, "recovery-guard-fixture")
	for index in range(data.height_levels.size()):
		data.height_levels[index] = 0
		data.site.terrain_changes[str(index)] = 0
	SiteRuntime.rebuild_terrain_edges(data)
	var room := TerrainArmy.INVALID_CELL
	for y in range(2, data.size.y - 8):
		for x in range(2, data.size.x - 35):
			var legal := true
			for dy in range(7):
				for dx in range(35):
					if not data.is_walkable(Vector2i(x + dx, y + dy)):
						legal = false
						break
				if not legal: break
			if legal:
				room = Vector2i(x, y)
				break
		if room != TerrainArmy.INVALID_CELL: break
	if not _require(room != TerrainArmy.INVALID_CELL, "No persistent recovery fixture room"): return
	var source: TerrainArmy = Helper.create_test_army(data, 1, 0, 4, room + Vector2i(1, 3))
	var coordinator := Coordinator.new()
	coordinator.register_formation(source)
	if not _require(bool(source.issue_combat_order(source.current_commander, TerrainArmy.CombatOrder.MOVE, room + Vector2i(29, 3), -1, Vector2i.RIGHT).get("ok", false)), "Recovery fixture MOVE rejected"): return
	var plan: CombatDeploymentPlan = source.get_active_deployment_plan()
	var move_plan: CombatMovePlan = source.get_active_move_plan()
	var pair: Array[int] = []
	for a in plan.member_slot_map.keys():
		if not plan.is_platform_member(a) or plan.is_slot_locked(a) or int(plan.slot_tactical_roles.get(plan.get_slot_for_member(a), -1)) != Types.TacticalSlotRole.FLEX: continue
		for b in plan.member_slot_map.keys():
			if a == b or not plan.is_platform_member(b) or plan.is_slot_locked(b) or int(plan.slot_tactical_roles.get(plan.get_slot_for_member(b), -1)) != Types.TacticalSlotRole.FLEX: continue
			var ca: Vector2i = plan.get_slot_for_member(a)
			var cb: Vector2i = plan.get_slot_for_member(b)
			if absi(ca.x - cb.x) + absi(ca.y - cb.y) == 1:
				pair.assign([int(a), int(b)])
				break
		if not pair.is_empty(): break
	if not _require(pair.size() == 2, "Need adjacent unlocked FLEX platform targets"): return
	var old_a: Vector2i = plan.get_slot_for_member(pair[0])
	var old_b: Vector2i = plan.get_slot_for_member(pair[1])
	var changed: Array[int] = Destination._rotate_platform_vacancy_chain(move_plan, plan, pair, [old_b, old_a])
	if not _require(changed.size() == 2 and move_plan.member_recovery_vacated_cell.get(pair[0]) == old_a and move_plan.member_recovery_vacated_cell.get(pair[1]) == old_b, "Real recovery rotation must latch old final cells"): return
	# Historical settled count can exceed the current count after a rotation.
	move_plan.platform_settled_highwater = maxi(1, plan.settled_platform_member_ids.size())
	data.site.armies = [source.capture_combat_state()]
	data.site.army_trial_active = true
	data.site.army_next_team = 2
	data.site.actors = {}
	data.site.combat_left = 0.0
	if not _require(bool(Store.save(data, SAVE).get("ok", false)), "Real recovery-guard save rejected"): return
	var original_text := FileAccess.get_file_as_string(SAVE)
	var loaded: Dictionary = Store.load_site(SAVE)
	if not _require(bool(loaded.get("ok", false)), "Real recovery-guard load rejected: " + str(loaded)): return
	var restored_data: TerrainData = loaded.data
	var restored := TerrainArmy.new()
	# Production armies live in the scene tree; fixtures step them explicitly.
	root.add_child(restored)
	restored.set_process(false)
	restored.roster_size = 4
	restored.exchange_enabled = true
	var restored_coordinator := Coordinator.new()
	restored_coordinator.register_formation(restored)
	restored.restore_combat_state(restored_data.site.armies[0], restored_data, null, null)
	var restored_move: CombatMovePlan = restored.get_active_move_plan()
	var restored_plan: CombatDeploymentPlan = restored.get_active_deployment_plan()
	if not _require(restored_move.member_recovery_vacated_cell == move_plan.member_recovery_vacated_cell and restored_move.platform_settled_highwater == move_plan.platform_settled_highwater, "Anti-reversal guard and highwater must round-trip exactly"): return
	restored_coordinator.combat_logic_tick(0.05)
	restored.prepare_combat(0.05)
	restored_coordinator.complete_committed_moves()
	if not _require(restored_move.member_recovery_vacated_cell == move_plan.member_recovery_vacated_cell, "First resumed tick must not erase the recovery guard"): return
	if not _require(Destination._rotate_platform_vacancy_chain(restored_move, restored_plan, pair, [old_a, old_b]).is_empty(), "Saved recovery chain must refuse immediate inverse target rotation"): return
	var envelope: Dictionary = JSON.parse_string(original_text)
	var payload: Dictionary = JSON.parse_string(envelope.payload)
	payload.state.armies[0].combat_move_plan.member_recovery_vacated_cell[str(pair[0])] = [0, 0]
	if not _require(_write_envelope(CORRUPT, payload), "Cannot write malformed guard fixture"): return
	var live_site: Dictionary = restored_data.site.duplicate(true)
	var live_army: Dictionary = restored.capture_combat_state()
	var rejected: Dictionary = Store.load_site(CORRUPT)
	if not _require(not bool(rejected.get("ok", false)) and str(rejected.get("code", "")) == "CORRUPT_SAVE" and restored_data.site == live_site and restored.capture_combat_state() == live_army and FileAccess.get_file_as_string(SAVE) == original_text, "Non-platform vacated cell must fail without replacing live state"): return
	var legacy_payload: Dictionary = JSON.parse_string(envelope.payload)
	legacy_payload.state.armies[0].combat_move_plan.erase("member_recovery_vacated_cell")
	legacy_payload.state.armies[0].combat_move_plan.erase("platform_settled_highwater")
	if not _require(_write_envelope(LEGACY, legacy_payload), "Cannot write legacy guard fixture"): return
	var legacy_loaded: Dictionary = Store.load_site(LEGACY)
	if not _require(bool(legacy_loaded.get("ok", false)), "Legacy guard fields must remain optional"): return
	var legacy_army := TerrainArmy.new()
	# Production armies live in the scene tree; fixtures step them explicitly.
	root.add_child(legacy_army)
	legacy_army.set_process(false)
	legacy_army.roster_size = 4
	legacy_army.exchange_enabled = true
	legacy_army.restore_combat_state(legacy_loaded.data.site.armies[0], legacy_loaded.data, null, null)
	if not _require(legacy_army.get_active_move_plan().member_recovery_vacated_cell.is_empty() and legacy_army.get_active_move_plan().platform_settled_highwater >= legacy_army.get_active_deployment_plan().settled_platform_member_ids.size(), "Legacy guard must default empty with a safe settled highwater"): return
	legacy_army.free()
	print("COMBAT MOVEMENT RECOVERY GUARD STORE PASS rotated=2 persisted=2 first_tick=retained inverse=blocked corrupt=refused legacy=loaded")
	restored_coordinator.unregister_formation(restored)
	restored.free()
	coordinator.unregister_formation(source)
	source.free()
	quit(0)
