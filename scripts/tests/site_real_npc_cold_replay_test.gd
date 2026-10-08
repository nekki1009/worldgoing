extends "res://scripts/tests/site_shared_step_replay_test.gd"
## Independent scope: an exact saved real NPC, not the empty-ground test.
var npc_output: String = ""

func _npc_scene() -> TerrainLab:
	var scene: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	assert(scene != null)
	var lab: TerrainLab = scene.instantiate() as TerrainLab
	lab.npc = TerrainTestNPC.new() # Existing presenter receives the saved original body.
	lab.restore_only = true
	lab.pause_when_unfocused = false
	root.add_child(lab)
	assert(lab.terrain == null and is_instance_valid(lab.npc))
	return lab

func _npc_source_bytes(data: TerrainData) -> PackedByteArray:
	var values: Array = [data.site, data.parameters, data.resource_base]
	for field: String in ["height_levels", "surface_types", "flags", "cliff_drops", "ramp_edges", "detail_variation",
		"fertility", "moisture", "drainage", "foundation", "groundwater", "water_kind", "water_body"]:
		values.append(data.get(field))
	return var_to_bytes(values)

func _npc_initial() -> Dictionary:
	var lab: TerrainLab = _npc_scene()
	var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.FOREST, 12345, {"size": Vector2i(72, 72)})
	SiteEnvironment.initialize(data, "original-real-npc-cold-replay")
	for y: int in range(5, 70):
		for x: int in range(5, 70):
			var index: int = data.index(Vector2i(x, y))
			data.site.terrain_changes[str(index)] = 0
			data.height_levels[index] = 0
	for key: String in data.resource_base: SiteEnvironment.change(data, key, {"cleared": true, "remaining": 0})
	data.site.depot_cell = data.index(Vector2i(6, 6))
	data.site.worker.cell = data.index(Vector2i(6, 7))
	data.site.capacity = 100000
	for item: String in SiteEnvironment.ITEM_NAMES: data.site.inventory[item] = 1000
	assert(SiteRuntime.initialize_item_storage(data.site).ok)
	SiteRuntime.rebuild_terrain_edges(data)
	SiteEnvironment.rebuild_indexes(data)
	var farm: String = _build(data, "farm", Vector2i(10, 30), Vector2i(12, 6))
	_build(data, "well", Vector2i(8, 32))
	_build(data, "well", Vector2i(24, 32))
	assert(SiteRuntime.operate_feature(data, farm).ok)
	lab.npc.person_id = 2027
	lab.bind_terrain(data)
	assert(lab.actor_present(lab.npc) and lab.npc.person_id == 2027)
	data.site.next_person_id = maxi(2028, int(data.site.get("next_person_id", 2)))
	lab.npc.hp = 63.0
	lab.npc.fatigue = 17.0
	lab.npc.training = 37.0
	lab.npc.faction_id = 1
	lab.npc.issue_command(TerrainTestNPC.Command.STOP)
	var slots: Array = SiteRuntime.feature_work_slots(data, data.site.features[farm])
	var slot: Dictionary = slots[0]
	assert(lab.npc.place(data.cell_from_index(int(slot.cell)), true))
	data.site.worker.cell = int(slot.cell)
	data.site.worker_enabled = true
	SiteRuntime.assign_task(data, SiteRuntime.ok("原 NPC 延續農場工作", {"target": "feature:" + farm,
		"action": "operate", "cell": int(slot.cell), "work_slot": int(slot.slot)}))
	data.site.worker.mode = "work"
	data.site.worker.cargo = {"grain": 6, "wood": 2}
	lab.npc.ammo_inventory = data.site.worker.cargo
	var pool: Dictionary = SiteStore.Sustain.create(0.0)
	assert(SiteStore.Sustain.add_members(pool, {2027: {"hp": lab.npc.hp}}, [2027]).ok)
	data.site.person_supply = {"2027": pool}
	lab.restore_only = false
	lab.movement_input_enabled = false
	lab.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	lab._advance_action_time(0.5)
	assert(data.site.features[farm].batch_paid and float(data.site.features[farm].production) > 0.0)
	assert(lab.npc.fatigue > 17.0 and lab.npc.hp != 100.0)
	assert(float(pool.at) > 0.0 and not pool.cohorts.is_empty() and int(data.site.worker.cargo.grain) < 6)
	assert(lab.site_controller._capture_for_save().ok)
	data.site.actor_presence_version = 1
	var at: float = SiteRuntime.now(data) * 60.0
	assert(RegionSaveSlot.attach_settlement(data.site, at).ok)
	var saved: Dictionary = SiteStore.save(data, npc_output.path_join("source.json"))
	assert(saved.ok, str(saved))
	return {"lab": lab, "farm": farm, "at": at}

func _npc_restore(data: TerrainData) -> TerrainLab:
	var original: PackedByteArray = _npc_source_bytes(data)
	var lab: TerrainLab = _npc_scene()
	var restored: Dictionary = lab.restore_original_site(data)
	assert(restored.ok, str(restored))
	assert(lab.terrain != data and _npc_source_bytes(data) == original)
	assert(lab.actor_present(lab.npc) and lab.npc.person_id == 2027)
	var bound_guard: Variant = lab.terrain.get_meta(&"siege_event_guard")
	assert(bound_guard is Callable and bound_guard.is_valid() and bound_guard.get_object() == lab)
	_same_original(lab.npc.capture_state(), data.site.actors.npc)
	_same_original(lab.terrain.site.worker, data.site.worker)
	assert(lab.terrain.site.worker_enabled and str(lab.terrain.site.worker.target).begins_with("feature:"))
	return lab

func _npc_saved_shapes(path: String) -> void:
	var read: Dictionary = SiteStore._read(path)
	assert(read.ok, str(read))
	var state: Dictionary = read.payload.state
	for domain: String in ["actors", "features", "terrain_changes", "changes", "person_supply", "item_records", "item_definitions"]:
		for key: Variant in state.get(domain, {}): assert(key is String, domain + " saved key must be a string")
	assert(state.actors.npc.cell is Array and state.actors.npc.cell.size() == 2)
	assert(state.actors.npc.movement_from is Array and state.actors.npc.movement_from.size() == 2)
	assert(state.actors.npc.item_state.item_ids is Array)
	assert(state.person_supply["2027"].cohorts is Array)
	assert(state.person_supply["2027"].cohorts[0].ids is Array)

func _run() -> void:
	_started = true
	deadline = Time.get_ticks_msec() + 90000
	root.gui_embed_subwindows = true
	npc_output = "res://output/site_building_close_20261004/ground_caller_candidate/npc_cold_followup/runs/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(npc_output)) == OK)
	var initial: Dictionary = _npc_initial()
	var loaded: Dictionary = SiteStore.load_site(npc_output.path_join("source.json"), Callable(), 1, true)
	assert(loaded.ok, str(loaded))
	var source: TerrainData = loaded.data
	var original: PackedByteArray = _npc_source_bytes(source)
	_npc_saved_shapes(npc_output.path_join("source.json"))
	var missing: TerrainLab = _scene()
	var refused: Dictionary = missing.restore_original_site(source)
	assert(not refused.ok and refused.code == "RESTORE_PRESENTER" and missing.terrain == null)
	assert(_npc_source_bytes(source) == original)
	checks += 1

	var live: TerrainLab = _npc_restore(source)
	var slot: RegionSaveSlot = RegionSaveSlot.new()
	slot.pin = {"world_instance_id": "original-npc-cold-replay", "slot_id": "synthetic-live-clock"}
	slot.control = {"logical_game_seconds": float(initial.at), "active_site_id": str(source.site.id)}
	live.site_controller.region_slot = slot
	live.restore_only = false
	live.movement_input_enabled = false
	live._advance_action_time(8.0)
	var target: float = float(slot.control.logical_game_seconds)
	var expected: Dictionary = _capture(live)
	assert(float(expected.person_supply["2027"].at) > float(source.site.person_supply["2027"].at))
	assert(float(expected.actors.npc.fatigue) != float(source.site.actors.npc.fatigue))
	assert(float(expected.features[initial.farm].production) != float(source.site.features[initial.farm].production))
	assert(expected.actors.npc.item_state.item_ids == source.site.actors.npc.item_state.item_ids)
	assert(int(expected.actors.npc.person_id) == 2027 and str(expected.actors.npc.item_state.holder) == "person:2027")
	var cold: TerrainLab = _npc_restore(source)
	var replay: Dictionary = cold.replay_site_to(target, 0, 1)
	assert(replay.ok and replay.status == "PENDING")
	while replay.ok and replay.status == "PENDING":
		assert(Time.get_ticks_msec() <= deadline)
		replay = cold.replay_site_to(target, 0, 17)
	assert(replay.ok and replay.status == "COMPLETE", str(replay))
	_same_original(_capture(cold), expected)
	assert(_npc_source_bytes(source) == original)
	checks += 1

	# Production adapter must construct the existing presenter before _ready,
	# then restore this saved original ID/body/items instead of retiring it.
	var host: TerrainLab = _scene()
	var adapted: Dictionary = host.advance_cold_site(source, target)
	while not adapted.ok and adapted.code == "PENDING":
		assert(Time.get_ticks_msec() <= deadline)
		assert(is_instance_valid(host._cold_replay_lab.npc) and host._cold_replay_lab.npc.person_id == 2027)
		assert(_npc_source_bytes(source) == original)
		adapted = host.advance_cold_site(source, target)
	assert(adapted.ok and adapted.data != source, str(adapted))
	for hook: StringName in [&"siege_event_guard", &"fire_event_guard", &"fire_pending_projectile_query", &"ship_journey_active", &"region_operation_pending", &"ship_vehicle_in_journey"]:
		assert(not adapted.data.has_meta(hook), "A completed cold candidate must not retain its retired scene callback: " + str(hook))
	_same_original(adapted.data.site, expected)
	assert(not is_instance_valid(host._cold_replay_lab) and _npc_source_bytes(source) == original)
	checks += 1

	var settled_path: String = npc_output.path_join("settled.json")
	var settled_save: Dictionary = SiteStore.save(adapted.data, settled_path)
	assert(settled_save.ok, str(settled_save))
	_npc_saved_shapes(settled_path)
	var reopened: Dictionary = SiteStore.load_site(settled_path, Callable(), 1, true)
	assert(reopened.ok, str(reopened))
	var revisit: TerrainLab = _npc_restore(reopened.data)
	var before_zero: Dictionary = _capture(revisit)
	# Loader water/notices caches use detached original rebuilds; last-slice
	# operating metadata is never a saved job/person/material authority.
	var settled_original: PackedByteArray = _npc_source_bytes(adapted.data)
	_same_original(_persistent_original_projection(revisit.terrain), _persistent_original_projection(adapted.data))
	assert(_npc_source_bytes(adapted.data) == settled_original)
	_same_original(revisit.terrain.site.water_status, _persistent_original_projection(revisit.terrain).water_status)
	var zero: Dictionary = revisit.replay_site_to(target, 0, 1)
	assert(zero.ok and zero.steps == 0 and zero.pending == 0.0)
	_same_original(_capture(revisit), before_zero)
	_same_original(_persistent_original_projection(revisit.terrain), _persistent_original_projection(adapted.data))
	assert(_npc_source_bytes(source) == original)
	checks += 1
	for lab: TerrainLab in [initial.lab, missing, live, cold, host, revisit]: lab.free()
	TerrainArmy.release_contact_source()
	assert(checks == 4)
	_finished = true
	print("SITE_REAL_NPC_COLD_REPLAY_PASS: actual original PackedScene and saved NPC 2027; pure missing-presenter refusal; original body/HP/fatigue/training/items/private meal/cargo/worker task retained, paid partial farm live-vs-cold full-state equality, actual production cold adapter restores same original NPC, all mutable source arrays untouched, saved array/string-key shapes, zero-game-time reopen; no native/GPU/performance/release claim")
	quit(0)
