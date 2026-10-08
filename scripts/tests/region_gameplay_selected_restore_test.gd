extends "res://scripts/tests/region_travel_test.gd"
## Reuses the original pinned synthetic geography fixture, then exercises the
## real Slot checkpoint/open chain and original selected-marker Lab restore.
const Entry = preload("res://scripts/region_lab/region_entry.gd")
var selected_checks := 0
var selected_failed := false
var selected_finished := false
var selected_scenes: Array[TerrainLab] = []
var selected_last_world_exists := false
var selected_last_world_bytes := PackedByteArray()

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 90000
	selected_last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if selected_last_world_exists: selected_last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	create_timer(90.0, true).timeout.connect(func() -> void: _finish_selected(false, "90-second real Slot selected restore deadline"))
	_run.call_deferred()

func _selected_check(condition: bool, message: String, detail: Variant = null) -> bool:
	selected_checks += 1
	if not condition:
		selected_failed = true
		push_error("REGION_GAMEPLAY_SELECTED_RESTORE_FAIL: " + message + " " + str(detail))
	return condition

func _freeze_scene(scene: TerrainLab) -> void:
	scene.set_process(false)
	scene.set_process_input(false)
	scene.set_process_unhandled_input(false)
	scene.site_controller.set_process(false)
	scene.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in scene.combat_actors: actor.set_process(false)
	for team: TerrainArmy in scene.combat_armies: team.set_process(false)

func _new_actual_scene() -> TerrainLab:
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if packed == null: return null
	var scene := packed.instantiate() as TerrainLab
	if scene == null: return null
	scene.npc = TerrainTestNPC.new()
	scene.pause_when_unfocused = false
	scene.visible = false
	root.add_child(scene)
	_freeze_scene(scene)
	selected_scenes.append(scene)
	return scene

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest(): _finish_selected(false, "Original synthetic manifest"); return
	lab = _new_actual_scene()
	if not _selected_check(lab != null, "Original formal PackedScene starts with its original controller"): _finish_selected(); return
	controller = lab.site_controller
	controller.save_root = OUT.path_join("selected_archive")
	world_id = "r0_selected_%d" % Time.get_ticks_usec()
	var created: Dictionary = controller.open_fixed_world(manifest_path, world_id, SLOT, Vector2i.ZERO, true)
	if not _selected_check(created.ok, "Original Controller publishes and binds one pinned first world", created): _finish_selected(); return
	_freeze_scene(lab)
	var original_slot: RegionSaveSlot = controller.region_slot
	var initial_generation := int(original_slot._marker.generation)
	lab._exchange_phase = 0.375
	lab._exchange_round = 9
	controller._work_elapsed = 0.625
	lab._fatigue_work_seconds[lab.character] = 0.625
	lab._region_point_pending = {"interval_complete": true, "fire_action_begin": lab.fire_action_cursor,
		"fire_action_end": lab.fire_action_cursor}
	var begin: Dictionary = lab._begin_fire_boundary(lab.fire_action_cursor)
	if not _selected_check(begin.ok, "Original active Site creates its pending endpoint", begin): _finish_selected(); return
	var hp_before := lab.character.hp
	lab.character.apply_contact({"result": {"hp": 3.0, "stun": 0.0, "guard_break": false}, "shield": false, "environmental": true})
	if not _selected_check(lab.character.hp == hp_before and lab._region_point_contacts.size() == 1,
		"Original pending sink retains unconsumed actual player contact"): _finish_selected(); return
	var checkpoint: Dictionary = controller.checkpoint_region_internal("region_barrier", false, lab._region_point_pending)
	if not _selected_check(checkpoint.ok and int(original_slot._marker.generation) == initial_generation + 1,
		"Original Slot publishes one real interval-complete/effects-pending generation", checkpoint): _finish_selected(); return
	var selected_generation := int(original_slot._marker.generation)
	var map := RegionData.new()
	var mapped: Dictionary = map.load_manifest(manifest_path)
	if not _selected_check(mapped.ok, "Pinned source is reloaded independently", mapped): _finish_selected(); return
	var reopened := RegionSaveSlot.new()
	var opened: Dictionary = reopened.open_map(map, world_id, SLOT)
	if not _selected_check(opened.ok and int(reopened._marker.generation) == selected_generation,
		"Real Slot open selects the complete pending marker without publishing", opened): _finish_selected(); return
	var stored: Dictionary = reopened.open_site(Vector2i.ZERO)
	if not _selected_check(stored.ok and stored.data.site.has("region_snapshot"),
		"Slot mode-aware open preserves the whole original pending snapshot", stored): _finish_selected(); return
	var loaded_region: Dictionary = Store.validate_region_snapshot(stored.data, {})
	if not _selected_check(loaded_region.ok and stored.data.site.fire_transport.orders is Array
		and stored.data.site.fire_transport.member_cursor is Array and stored.data.site.fire_transport.reservations is Array,
		"Actual hot load keeps authenticated original Fire wire and passes the unchanged snapshot hash", loaded_region.get("code")): _finish_selected(); return
	var altered: Dictionary = stored.data.site.duplicate(true)
	altered.fire_transport.orders[0].serial = int(altered.fire_transport.orders[0].serial) + 1
	var changed_transport: Dictionary = Store.validate_region_snapshot(stored.data, {"state": altered})
	_selected_check(not changed_transport.ok and changed_transport.code == "CORRUPT_REGION_SNAPSHOT",
		"Changing an original Fire serial remains detected before owner restore", changed_transport.get("code"))
	var resumed := _new_actual_scene()
	if not _selected_check(resumed != null, "Reopened original main scene exists"): _finish_selected(); return
	var child_count := resumed.get_child_count()
	var prepared: Dictionary = resumed.prepare_selected_region_owner_restore(stored.data, reopened)
	if not _selected_check(prepared.ok and prepared.selected and prepared.zero_world_only
		and int(reopened._marker.generation) == selected_generation and resumed.get_child_count() == child_count,
		"Selected restore validates real disposable bootstrap then frees it without a marker", prepared): _finish_selected(); return
	var original_resumed_data: TerrainData = resumed.terrain
	var original_resumed_hp := resumed.character.hp
	# Fault injection in the actual Slot object. Disk still selects the complete old
	# marker; the old private permit must reject the changed in-memory generation.
	reopened._marker.generation = selected_generation + 1
	resumed.bind_terrain(prepared.data, prepared)
	_selected_check(resumed.terrain == original_resumed_data and resumed.character.hp == original_resumed_hp,
		"Stale actual Slot generation rejects before old scene/body destruction")
	reopened._marker.generation = selected_generation
	var selected_path := reopened.site_path(Vector2i.ZERO)
	var selected_bytes := FileAccess.get_file_as_bytes(selected_path)
	var file := FileAccess.open(selected_path, FileAccess.WRITE)
	file.store_buffer(selected_bytes)
	file.store_string("\n")
	file.close()
	resumed.bind_terrain(prepared.data, prepared)
	_selected_check(resumed.terrain == original_resumed_data and resumed.character.hp == original_resumed_hp,
		"Changed selected file SHA rejects before mutation even when JSON still parses")
	file = FileAccess.open(selected_path, FileAccess.WRITE)
	file.store_buffer(selected_bytes)
	file.close()
	prepared = resumed.prepare_selected_region_owner_restore(stored.data, reopened)
	if not _selected_check(prepared.ok, "Exact original selected bytes permit a fresh private preflight", prepared): _finish_selected(); return
	resumed.site_controller.region_slot = reopened
	resumed.bind_terrain(prepared.data, prepared)
	_freeze_scene(resumed)
	var receipt: Dictionary = resumed.region_bind_receipt(prepared.data)
	if not _selected_check(receipt.ok and receipt.complete and receipt.owners_restored
		and not receipt.effects_complete and receipt.zero_world_only and int(reopened._marker.generation) == selected_generation,
		"Real selected main bind restores complete original owners at the same durable generation", receipt): _finish_selected(); return
	_selected_check(resumed.character.hp == hp_before and resumed._region_point_contacts.size() == 1
		and is_equal_approx(resumed.site_controller._work_elapsed, 0.625)
		and resumed._fatigue_work_seconds.has(resumed.character)
		and resumed._exchange_round == 9 and is_equal_approx(resumed._exchange_phase, 0.375),
		"Reopened main keeps original queue, P0 progress, cadence and actual Node aliases")
	var game_before := float(reopened.control.logical_game_seconds)
	var action_before := float(reopened.control.fire_clock.action_seconds)
	var done: Dictionary = resumed.consume_region_point(false)
	if not _selected_check(done.ok and done.complete, "Original main consumes restored effects at zero time", done): _finish_selected(); return
	_selected_check(resumed.character.hp == hp_before - 3.0 and float(reopened.control.logical_game_seconds) == game_before
		and float(reopened.control.fire_clock.action_seconds) == action_before and int(reopened._marker.generation) == selected_generation,
		"Accepted damage is applied once without clock advance or hidden checkpoint")
	var retry: Dictionary = resumed.consume_region_point(false)
	_selected_check(retry.ok and resumed.character.hp == hp_before - 3.0, "Same-time consumer retry preserves original HP")
	_finish_selected()

func _finish_selected(ok: bool = true, message: String = "") -> void:
	if selected_finished: return
	selected_finished = true
	selected_failed = selected_failed or not ok
	if not message.is_empty(): print(message)
	for scene: TerrainLab in selected_scenes:
		if is_instance_valid(scene): scene.free()
	# Restore menu preference only if this fixture still owns the exact reference.
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(Entry.LAST_WORLD)) if FileAccess.file_exists(Entry.LAST_WORLD) else null
	if current is Dictionary and current.get("world_id") == world_id:
		if selected_last_world_exists:
			var file := FileAccess.open(Entry.LAST_WORLD, FileAccess.WRITE)
			file.store_buffer(selected_last_world_bytes)
			file.close()
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(Entry.LAST_WORLD))
	TerrainArmy.release_contact_source()
	print("REGION_GAMEPLAY_SELECTED_RESTORE_", "FAILED" if selected_failed else "PASS", " checks=", selected_checks,
		" scope=real_slot_marker_readback_main_selected_bind_stale_generation_sha_point_once")
	quit(1 if selected_failed else 0)