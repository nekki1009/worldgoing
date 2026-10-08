extends SceneTree
## Real original SceneTree + Store JSON + private original bootstrap. No alternate clock.
## Fixture seeds pre-existing original counter progress; original methods admit movement,
## defer an original contact and open/finish the original Fire boundary.
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Checkpoint = preload("res://scripts/terrain_lab/site_region_checkpoint.gd")
var checks := 0
var failures: Array[String] = []
var finished := false
var labs: Array[TerrainLab] = []
var paths: Array[String] = []

func _initialize() -> void:
	create_timer(60.0, true).timeout.connect(func() -> void: _finish("deadline"))
	_run.call_deferred()

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if not condition:
		failures.append(message)
		push_error("REGION_GAMEPLAY_SCENE_RESTORE_FAIL: " + message + " " + str(detail))
	return condition

func _context(data: TerrainData, pending: bool) -> Dictionary:
	var site_id := str(data.site.id)
	return {"purpose": "region_barrier" if pending else "region_checkpoint", "mode": "cold_exact",
		"source_generation": 3, "runtime_revision": 4, "token": "fixture:" + site_id,
		"game_seconds": 0.0, "action_seconds": 0.0, "fire_epoch": "fixture:fire", "fire_sequence": 0,
		"interval_complete": true, "effects_complete": not pending, "mode_revision": 6, "backend": "gd",
		"events": [{"id": "point:" + site_id, "kind": "attack", "at": 0.0, "sequence": 1,
			"player": false, "owner": site_id, "status": "pending", "payload": {}}] if pending else [],
		"endpoint_payload": {}}

func _original_scene() -> TerrainLab:
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _check(packed != null, "Original formal TerrainLab scene exists"): return null
	var lab := packed.instantiate() as TerrainLab
	if not _check(lab != null, "Formal scene creates its original Lab"): return null
	lab.restore_only = true
	lab.pause_when_unfocused = false
	lab.visible = false
	root.add_child(lab)
	lab.set_process(false)
	lab.set_process_input(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)
	labs.append(lab)
	return lab

func _source(site_id: String, progress: float) -> TerrainLab:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(32, 32)})
	SiteEnvironment.initialize(data, site_id)
	var lab := _original_scene()
	if lab == null: return null
	lab.bind_terrain(data)
	if not _check(lab.terrain == data and lab._region_bound_data == data, "Original guarded bind creates one actual source", lab.site_controller.message.text): return null
	lab._action_time_remainder = 0.0125
	lab._exchange_phase = 0.375
	lab._exchange_round = 7
	lab.site_controller._work_elapsed = progress
	lab.site_controller._settlement_elapsed = 0.125
	lab._fatigue_work_seconds[lab.character] = progress
	# Every edge is admitted by the original Actor, rather than copying movement fields.
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var goal := lab.character.terrain_cell + direction
		if lab.character.place(goal, false, 0.5):
			lab.character._advance_movement(0.125)
			break
	if not _check(lab.character.is_moving(), "Original Actor admits a partially completed edge"): return null
	return lab

func _save_actual(lab: TerrainLab, pending: bool) -> Dictionary:
	var captured: Dictionary = lab.site_controller._capture_for_save()
	if not _check(captured.ok, "Original Controller captures original Actor/Army bodies", captured): return captured
	var context := _context(lab.terrain, pending)
	var owners: Dictionary = lab.capture_region_owner_state(context)
	if not _check(owners.ok, "Original Lab captures all original transient owner roots", owners): return owners
	var path := "user://region_scene_%s_%d.json" % [str(lab.terrain.site.id).validate_filename(), Time.get_ticks_usec()]
	paths.append(path)
	var saved: Dictionary = Store.save_region_snapshot(lab.terrain, path, context, owners.owner_states)
	if not _check(saved.ok, "Original Store atomically writes a real complete owner checkpoint", saved): return saved
	var loaded := Store.load_site(path)
	if not _check(loaded.ok, "Real JSON readback validates original body plus all transient roots", loaded): return loaded
	_check(loaded.get("owners_restored") == false and loaded.get("bind_complete") == false,
		"A validated file emits neither an owner-restored nor a bound receipt")
	return loaded

func _roundtrip_pending() -> void:
	var source := _source("region:scene:A", 0.625)
	if source == null: return
	var original_hp := source.character.hp
	source._region_point_pending = {"interval_complete": true, "fire_action_begin": 0.0, "fire_action_end": 0.0}
	var boundary: Dictionary = source._begin_fire_boundary(0.0)
	if not _check(boundary.ok, "Original Lab opens the exact pending Fire endpoint", boundary): return
	var packet := {"result": {"hp": 3.0, "stun": 0.0, "guard_break": false}, "shield": false, "environmental": true}
	source.character.apply_contact(packet)
	if not _check(source.character.hp == original_hp and source._region_point_contacts.size() == 1,
		"Original contact sink defers actual damage to the pending endpoint"): return
	var ordinary: Dictionary = Store.save(source.terrain, "user://region_scene_forbidden.json")
	_check(not ordinary.ok and ordinary.code == "BUSY", "Ordinary save retains its original pending-boundary BUSY guard", ordinary)
	var loaded := _save_actual(source, true)
	if not loaded.ok: return
	var restored := _original_scene()
	if restored == null: return
	var bound: Dictionary = restored._region_bootstrap_bind_child(restored, loaded.data)
	if not _check(bound.ok, "Original private bootstrap positively restores a durable pending checkpoint", bound): return
	_check(restored.terrain == loaded.data and restored._region_bound_data == loaded.data,
		"The actual original hidden scene owns the loaded body")
	_check(restored._region_bind_receipt_value.get("owners_restored") == true
		and restored._region_bind_receipt_value.get("effects_complete") == false
		and restored._region_bind_receipt_value.get("zero_world_only") == true,
		"Restore receipt separates original owners from unconsumed same-time effects")
	_check(restored._exchange_round == 7 and is_equal_approx(restored._exchange_phase, 0.375)
		and is_equal_approx(restored._action_time_remainder, 0.0125)
		and is_equal_approx(restored.site_controller._work_elapsed, 0.625),
		"Original cadence/P0 counters retain exact partial progress")
	_check(restored._fatigue_work_seconds.has(restored.character) and not restored._fatigue_work_seconds.has(source.character)
		and is_equal_approx(float(restored._fatigue_work_seconds[restored.character]), 0.625),
		"Reference codec rebinds the fatigue account to the actual restored Actor Node")
	_check(restored.character.is_moving() and is_equal_approx(restored.character._movement_elapsed, 0.125),
		"Accepted original partial edge survives positive restore")
	var hp_before := restored.character.hp
	var movement_before := restored.character._movement_elapsed
	var minute_before := int(restored.terrain.site.minute)
	var phase_before := float(restored.terrain.site.phase)
	var complete: Dictionary = restored.consume_region_point(false)
	if not _check(complete.ok and complete.complete, "Original endpoint consumer positively completes the restored same-time queue", complete): return
	_check(restored.character.hp == hp_before - 3.0 and source.character.hp == original_hp,
		"Original restored body consumes its own accepted damage exactly once")
	_check(restored.fire_action_cursor == 0.0 and restored.character._movement_elapsed == movement_before
		and int(restored.terrain.site.minute) == minute_before and float(restored.terrain.site.phase) == phase_before,
		"Zero-time endpoint consumption advances neither world/action clock nor committed movement")
	var repeated: Dictionary = restored.consume_region_point(false)
	_check(repeated.ok and restored.character.hp == hp_before - 3.0 and restored._region_point_contacts.is_empty(),
		"Retry cannot replay an already-consumed original contact")
	var stale_context := _context(restored.terrain, true)
	var snapshot: Dictionary = Store.validate_region_snapshot(loaded.data, {})
	stale_context.source_generation = 4
	var before_hash := Checkpoint.state_hash(restored.terrain.site)
	var before_hp := restored.character.hp
	var rejected: Dictionary = restored.prepare_restore_region_owner_state(snapshot.owners, stale_context)
	_check(not rejected.ok and restored.character.hp == before_hp and Checkpoint.state_hash(restored.terrain.site) == before_hash,
		"A changed original epoch rejects full owner preparation before any actual mutation", rejected)

func _two_original_owners() -> void:
	var first := _source("region:scene:B", 1.75)
	var second := _source("region:scene:C", 2.25)
	if first == null or second == null: return
	var a := _save_actual(first, false)
	var b := _save_actual(second, false)
	if not a.ok or not b.ok: return
	var restored_a := _original_scene()
	var restored_b := _original_scene()
	if restored_a == null or restored_b == null: return
	var ba: Dictionary = restored_a._region_bootstrap_bind_child(restored_a, a.data)
	var bb: Dictionary = restored_b._region_bootstrap_bind_child(restored_b, b.data)
	if not _check(ba.ok and bb.ok, "Two separately persisted actual original Site owners positively bootstrap", [ba, bb]): return
	_check(restored_a.terrain != restored_b.terrain and restored_a.character != restored_b.character,
		"Equal local person IDs retain distinct actual SceneTree owners")
	_check(is_equal_approx(restored_a.site_controller._work_elapsed, 1.75) and is_equal_approx(restored_b.site_controller._work_elapsed, 2.25),
		"Both durable original full graphs retain their own work progress")
	_check(restored_a._fatigue_work_seconds.has(restored_a.character)
		and not restored_a._fatigue_work_seconds.has(restored_b.character)
		and restored_b._fatigue_work_seconds.has(restored_b.character)
		and not restored_b._fatigue_work_seconds.has(restored_a.character),
		"All restored original references remain local to the matching Site")
	_check(restored_a._region_bind_receipt_value.get("effects_complete") == true
		and restored_b._region_bind_receipt_value.get("effects_complete") == true,
		"Completed original owners emit activation-ready effects receipts")

func _run() -> void:
	_roundtrip_pending()
	_two_original_owners()
	_pending_additive_projection()
	_finish()

func _finish(reason: String = "") -> void:
	if finished: return
	finished = true
	if not reason.is_empty(): failures.append(reason)
	for lab: TerrainLab in labs:
		if is_instance_valid(lab): lab.free()
	for path: String in paths:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".bak"))
	print("REGION_GAMEPLAY_SCENE_RESTORE_", "PASS" if failures.is_empty() else "FAILED", " checks=", checks,
		" scope=real_scene_store_readback_private_bootstrap_point_consume_two_owners")
	quit(0 if failures.is_empty() else 1)
func _pending_additive_projection() -> void:
	var source := _source("region:scene:additive", 0.75)
	if source == null: return
	source._region_point_pending = {"interval_complete": true, "fire_action_begin": 0.0, "fire_action_end": 0.0}
	var opened: Dictionary = source._begin_fire_boundary(0.0)
	if not _check(opened.ok, "Pending additive source opens the original Fire boundary", opened): return
	var hp_before := source.character.hp
	source.character.apply_contact({"result": {"hp": 3.0, "stun": 0.0, "guard_break": false}, "shield": false, "environmental": true})
	source.site_controller._capture_positions()
	var target := source._region_detached_bind_data(source.terrain)
	var cells: Array[Vector2i] = []
	for index: int in target.size.x * target.size.y:
		var cell := target.cell_from_index(index)
		if target.is_walkable(cell) and not source.character.occupies_cell(cell) and cell.distance_to(source.character.terrain_cell) > 3.0:
			cells.append(cell)
			if cells.size() == 2: break
	if not _check(cells.size() == 2, "Actual terrain provides two unoccupied original deployment cells"): return
	var imported := TerrainArmy.new()
	root.add_child(imported)
	imported.set_process(false)
	imported.team_id = int(target.site.army_next_team)
	imported.faction_id = source.character.faction_id
	imported.roster_size = 2
	var admitted := imported.deploy_at(target, null, null, cells) and imported.enable_combat(false, 0, TerrainArmy.TROOP_TYPE_ID)
	if not _check(admitted, "Additional bodies are genesis-admitted by the original Army"): imported.free(); return
	for row: Dictionary in imported.combat_units:
		var equipment: Dictionary = SiteRuntime.seed_person_equipment(target, row.item_state, int(row.person_id), row.appearance)
		if not _check(equipment.ok, "Each added original row owns registered original equipment", equipment): imported.free(); return
	target.site.army_next_team = imported.team_id + 1
	target.site.armies.append(imported.capture_combat_state())
	var imported_team_id := imported.team_id
	imported.free()
	var context := _context(source.terrain, true)
	var projected: Dictionary = source._region_project_original_bind_child(source, target, context)
	if not _check(projected.ok, "Actual pending projection positively adds an original admitted Army before effects", projected): return
	var actual: TerrainArmy = null
	for team: TerrainArmy in source.combat_armies:
		if team.combat_enabled and team.team_id == imported_team_id: actual = team
	_check(actual != null and actual.combat_units.size() == 2, "Added formation is the actual original core binder's Army")
	_check(source.character.hp == hp_before and source._region_point_contacts.size() == 1
		and not source._region_point_pending.is_empty() and source.terrain.has_meta(&"fire_boundary"),
		"Positive additive bind keeps accepted contact plus Fire/P0 boundary unconsumed")
	_check(source._region_owner_restore_receipt.get("effects_complete") == false
		and is_equal_approx(source.site_controller._work_elapsed, 0.75)
		and source.character.is_moving() and is_equal_approx(source.character._movement_elapsed, 0.125),
		"Merged full graph retains original pending fence, P0 progress and committed edge")
	var old_game := float(source.terrain.site.minute) * 60.0 + float(source.terrain.site.phase) * 60.0
	var completed: Dictionary = source.consume_region_point(false)
	_check(completed.ok and completed.complete and source.character.hp == hp_before - 3.0
		and source.fire_action_cursor == 0.0
		and float(source.terrain.site.minute) * 60.0 + float(source.terrain.site.phase) * 60.0 == old_game,
		"After actual additive restore the original zero-time consumer settles the preserved contact once", completed)