extends "res://scripts/tests/region_travel_test.gd"
## E3/ECO15 v2 bounded source proposal. NOT RUN; sole Tech runner owns Godot.
## Reuses original pinned manifest, route producer, freeze and saved-state helpers.
## No source stock, inventory, person, ecology schema or clock is fabricated.
const E3Entry = preload("res://scripts/region_lab/region_entry.gd")
const E3_IDLE_SECONDS := 900.0
const E3_LIMIT := 20000
const E3_EPS := 0.00001
# A fixed-geography load rebuilds resource_base from the pinned base and the
# synthetic travel manifest has no resource layer, so a source only survives
# checkpoints if the pinned base supplies it. Use the pinned Taiwan pair: the
# original legal start site and its all-forest east neighbour.
const START_SITE := Vector2i(1170, 13252)
const DEST_SITE := Vector2i(1171, 13252)
var e3_reference: TerrainLab
var e3_key := ""
var e3_cell := Vector2i.ZERO
var e3_person := -1
var e3_holder_ids: Array = []
var e3_source: TerrainData
var e3_source_bytes := PackedByteArray()
var e3_last_exists := false
var e3_last_bytes := PackedByteArray()
var e3_finished := false
var e3_failed := false
var e3_saw_cold := false
var e3_out := ""
var e3_journeys: Array[Dictionary] = []

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	e3_out = "res://.godot-temp/site_ecology_longrun_owner/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	e3_last_exists = FileAccess.file_exists(E3Entry.LAST_WORLD)
	if e3_last_exists: e3_last_bytes = FileAccess.get_file_as_bytes(E3Entry.LAST_WORLD)
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if not e3_finished and Time.get_ticks_msec() > deadline: _finish_e3(false, "E3 deadline")
	return false

func _must(condition: bool, message: String) -> bool:
	if not condition:
		e3_failed = true
		push_error("SITE_ECOLOGY_LONGRUN_OWNER_FAIL: " + message)
	return condition

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest(): _finish_e3(false); return
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	if not _must(packed != null, "Actual original PackedScene"): _finish_e3(false); return
	lab = packed.instantiate() as TerrainLab
	lab.restore_only = true
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	lab.visible = false
	root.add_child(lab)
	controller = lab.site_controller
	_freeze()
	var archive := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(32, 32)})
	Env.initialize(archive, "ecology-e3:archive")
	lab.bind_terrain(archive)
	lab.restore_only = false
	controller.save_root = e3_out.path_join("archive")
	world_id = "ecology_e3_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened := controller.open_fixed_world(manifest_path, world_id, SLOT, START_SITE, true)
	if not _must(opened.ok and Env.ecology_active(lab.terrain), "Original world admission supplies modern ecology: " + str(opened)): _finish_e3(false); return
	_freeze()
	lab.simulation_speed = 4.0
	lab.exchange_enabled = true
	# A fixed-geography Site starts with an empty inventory; harvest requires one
	# tool to be present (it is not consumed). Stock it before the first batch.
	if int(lab.terrain.site.inventory.get("tools", 0)) < 1: lab.terrain.site.inventory["tools"] = 1
	var keys := lab.terrain.resource_base.keys()
	keys.sort()
	for key: String in keys:
		var resource := Env.resource(lab.terrain, key)
		var cells := Env.work_cells(lab.terrain, key)
		# Medicine cannot disappear through the ordinary food consumer while away.
		if int(resource.kind) == Env.Kind.HERB and bool(resource.discovered) and not cells.is_empty() and int(Env.ecology_info(lab.terrain, key).takeable) >= 2 * int(Env.BATCH[Env.Kind.HERB]):
			e3_key = key; e3_cell = cells[0]; break
	if not _must(not e3_key.is_empty(), "Pinned original source has a discovered accessible herb with two paid batches"): _finish_e3(false); return
	e3_person = lab.controlled_person_id()
	e3_holder_ids = lab.character.item_state.get("item_ids", []).duplicate()
	var first := _paid_batch(lab)
	if not _must(first.ok and int(first.produced) > 0, "Initial original paid manual batch: " + str(first)): _finish_e3(false); return
	var saved := controller.checkpoint_region_internal("region_checkpoint", true)
	if not _must(saved.ok, "Actual original source checkpoint: " + str(saved)): _finish_e3(false); return
	var loaded := controller.region_slot._load_checked(controller.region_slot.site_path(START_SITE), START_SITE)
	if not _must(loaded.ok, "Original selected source readback: " + str(loaded)): _finish_e3(false); return
	e3_source = loaded.data
	e3_source_bytes = var_to_bytes([e3_source.site, e3_source.resource_base, e3_source.parameters])
	var child := lab._region_new_bind_child(e3_source)
	if not _must(child.ok, "Original reference shell: " + str(child)): _finish_e3(false); return
	e3_reference = child.child
	var restored := e3_reference.restore_original_site(e3_source)
	if not _must(restored.ok and restored.get("owners_restored", false), "Reference restores actual full owners: " + str(restored)): _finish_e3(false); return
	if not _journey_to(DEST_SITE): _finish_e3(false); return
	var until := float(controller.region_slot.control.logical_game_seconds) + E3_IDLE_SECONDS
	for _step: int in range(E3_LIMIT):
		if float(controller.region_slot.control.logical_game_seconds) + E3_EPS >= until: break
		if not _alive(): _finish_e3(false); return
		var requested := minf(lab.EXCHANGE_ACTION_STEP, (until - float(controller.region_slot.control.logical_game_seconds)) / (60.0 * lab.simulation_speed))
		var step := lab._advance_original_shared_step(requested)
		if not _must(step.ok and step.get("completed", false), "Original idle world step: " + str(step)): _finish_e3(false); return
	if not _must(absf(float(controller.region_slot.control.logical_game_seconds) - until) <= E3_EPS, "Fixed 900-second idle interval completes"): _finish_e3(false); return
	if not _return_to_visited(): _finish_e3(false); return
	_finish_e3(true)

func _write_manifest() -> bool:
	manifest_path = RegionData.DEFAULT_MANIFEST
	var source := RegionData.new()
	return _must(source.load_manifest(manifest_path).ok and not source.resource_manifest_hash.is_empty(), "Pinned geography/resource pair loads")

func _alive() -> bool:
	return _must(Time.get_ticks_msec() <= deadline and not e3_finished, "Bounded E3 pump")

func _journey_to(destination: Vector2i) -> bool:
	var slot: RegionSaveSlot = controller.region_slot
	var from := controller._current_region_site()
	var begin_game := float(slot.control.logical_game_seconds)
	var begin_generation := int(slot._marker.generation)
	var departed := RegionTravelSite.depart(controller)
	if not _must(departed.ok, "Actual departure: " + str(departed)): return false
	var departure := slot.region_travel_status()
	if not _must(departure.ok and departure.get("pending", false) and str(slot.control.active_site_id).is_empty() and int(slot._marker.generation) > begin_generation and float(slot.control.logical_game_seconds) == begin_game, "Departure receipt publishes one selected party without added game time"): return false
	var selected_origin := slot._load_checked(slot.site_path(START_SITE), START_SITE)
	if not _must(selected_origin.ok and int(selected_origin.data.site.total_produced) == int(e3_source.site.total_produced), "The actually selected origin source retains the paid production total while away"): return false
	var selected_origin_hash := FileAccess.get_sha256(slot.site_path(START_SITE))
	var selected_origin_at := Runtime.now(selected_origin.data) * 60.0
	var published := 0.0
	var router := RegionData.new()
	if not _must(router.load_manifest(manifest_path).ok, "Original pinned route source"): return false
	var route := _original_party_route(slot, router, controller._current_region_site(), int(slot.region_travel_status().component), destination)
	if not _must(route.ok, "Original party route: " + str(route)): return false
	var planned := slot.set_region_travel_plan(route.steps)
	if not _must(planned.ok, "Original accepted route: " + str(planned)): return false
	var arrived := false
	for _pump: int in range(E3_LIMIT):
		if not _alive(): return false
		var advanced := slot.advance_region_travel(37)
		if not _must(advanced.ok, "Original travel clock: " + str(advanced)): return false
		published += float(advanced.get("advanced", 0.0))
		if not _must(absf(float(slot.control.logical_game_seconds) - begin_game - published) <= E3_EPS, "Actual travel receipts account for every published game second"): return false
		if advanced.get("arrived", false): arrived = true; break
		if advanced.get("barrier", false):
			var consumed := slot.consume_due_region_events()
			if not _must(consumed.ok and consumed.get("complete", false), "Original travel endpoint: " + str(consumed)): return false
		if not _must(float(advanced.get("advanced", 0.0)) > 0.0, "Travel must make bounded progress"): return false
	if not _must(arrived, "Bounded route reaches original arrival"): return false
	var checkpoint := slot.checkpoint_region_travel()
	if not _must(checkpoint.ok, "Original travel checkpoint: " + str(checkpoint)): return false
	var arrived_game := float(slot.control.logical_game_seconds)
	var checkpoint_generation := int(slot._marker.generation)
	var result := controller.open_fixed_world(manifest_path, world_id, SLOT, Vector2i(-1, -1), false)
	for _resume: int in range(E3_LIMIT):
		if is_instance_valid(lab._cold_replay_lab): e3_saw_cold = true
		if str(result.get("code", "")) != "PENDING" and not controller.region_operation_pending(): break
		if not _alive(): return false
		result = controller.resume_region_operation()
	if not _must(result.ok and controller._current_region_site() == destination and controller.region_slot.region_travel_journey().is_empty(), "Original settled arrival bind: " + str(result)): return false
	var bound_slot: RegionSaveSlot = controller.region_slot
	var bind := lab.region_bind_receipt(lab.terrain)
	var settled := RegionSaveSlot.validate_settlement(lab.terrain.site, float(bound_slot.control.logical_game_seconds))
	if not _must(bind.get("complete", false) and bind.get("owners_restored", false) and bind.get("owner") == str(lab.terrain.site.id) and int(bind.get("generation", -1)) == int(bound_slot._marker.generation), "Arrival restored complete original owners at the selected generation"): return false
	if not _must(float(bound_slot.control.logical_game_seconds) == arrived_game and settled.ok and not settled.get("legacy", true) and float(settled.pending) <= E3_EPS, "Arrival binds the completed original state with zero added time and no debt"): return false
	e3_journeys.append({"from": [from.x, from.y], "to": [destination.x, destination.y], "departure_game": begin_game, "published_travel_seconds": published, "arrival_game": arrived_game, "departure_generation": begin_generation, "checkpoint_generation": checkpoint_generation, "bound_generation": int(bound_slot._marker.generation), "selected_origin_sha256": selected_origin_hash, "selected_origin_game": selected_origin_at, "actual_retained_cold_observed": e3_saw_cold, "bind_receipt": bind.duplicate(true), "settlement": settled.duplicate(true)})
	_freeze()
	return true

func _return_to_visited() -> bool:
	e3_saw_cold = false
	if not _journey_to(START_SITE): return false
	# A legitimate original cold_exact checkpoint may already have settled the
	# origin. Retained replay is observed, never artificially required or induced.
	var target := float(controller.region_slot.control.logical_game_seconds)
	var settlement := RegionSaveSlot.validate_settlement(lab.terrain.site, target)
	if not _must(settlement.ok and not settlement.get("legacy", true) and float(settlement.pending) <= E3_EPS, "Original return has no unsettled debt"): return false
	var reference_done := false
	for _pump: int in range(E3_LIMIT):
		if not _alive(): return false
		var replay := e3_reference.replay_site_to(target, 4000, 128)
		if not _must(replay.ok, "Original uninterrupted reference clock: " + str(replay)): return false
		if replay.status == "COMPLETE": reference_done = true; break
	if not _must(reference_done, "Reference reaches the same actual world endpoint"): return false
	if not _must(int(lab.terrain.site.total_produced) == int(e3_source.site.total_produced) and int(e3_reference.terrain.site.total_produced) == int(e3_source.site.total_produced), "Neither original path harvests during the away interval"): return false
	if not _must(_same_ecology_state(lab.terrain, e3_reference.terrain), "Before post-return work: ecology source, latch, deadline, stock and produced total equal"): return false
	if not _must(absf(Runtime.now(lab.terrain) - Runtime.now(e3_reference.terrain)) <= E3_EPS, "Same original minute/phase endpoint"): return false
	if not _must(lab.controlled_person_id() == e3_person and lab.character.item_state.get("item_ids", []) == e3_holder_ids, "Same original person and equipment holder restored"): return false
	if not _must(int(lab.terrain.site.manual.cargo.get("herb", 0)) == int(e3_reference.terrain.site.manual.cargo.get("herb", 0)), "Departure/return preserves the actual previously paid herb cargo"): return false
	var paired := _paired_return_batch()
	if not _must(paired.ok, "After bind, paired paid manual result: " + str(paired)): return false
	if not _must(var_to_bytes([e3_source.site, e3_source.resource_base, e3_source.parameters]) == e3_source_bytes, "Reference never edits the original saved source"): return false
	report.e3 = {"source": e3_key, "person_id": e3_person, "fixed_idle_game_seconds": E3_IDLE_SECONDS, "returned_game_seconds": target, "actual_retained_cold_observed": e3_saw_cold, "journeys": e3_journeys, "paired_paid": paired, "scope": "one real departure/original cold owner/return bind calibration; retained replay is optional; not 90-day full-scene equivalence"}
	return true

func _paired_return_batch() -> Dictionary:
	var starts: Array[Dictionary] = []
	var begin := Runtime.now(lab.terrain) * 60.0
	for scene: TerrainLab in [lab, e3_reference]:
		if not _must(scene.actor_present(scene.character) and scene.controlled_person_id() == e3_person and scene.character.place(e3_cell, true), "Paired original person at actual source cell"): return {"ok": false}
		starts.append({"cargo": scene.terrain.site.manual.cargo.duplicate(true), "produced": int(scene.terrain.site.total_produced)})
		scene.site_controller.source_key = e3_key
		scene.site_controller.manual_work("harvest")
		if not _must(scene.terrain.site.manual.target == e3_key and scene.terrain.site.manual.action == "harvest", "Both original controllers admit the same paid batch"): return {"ok": false}
	for _step: int in range(E3_LIMIT):
		if str(lab.terrain.site.manual.target).is_empty(): break
		if not _alive(): return {"ok": false}
		var stepped := lab._advance_original_shared_step(lab.EXCHANGE_ACTION_STEP)
		if not _must(stepped.ok and stepped.get("completed", false), "Paired live original clock: " + str(stepped)): return {"ok": false}
	var target := float(controller.region_slot.control.logical_game_seconds)
	if not _must(str(lab.terrain.site.manual.target).is_empty() and target > begin, "Live paid batch completes with positive actual time"): return {"ok": false}
	var complete := false
	for _pump: int in range(E3_LIMIT):
		if not _alive(): return {"ok": false}
		var replay := e3_reference.replay_site_to(target, 4000, 128)
		if not _must(replay.ok, "Paired reference consumes the SAME actual target: " + str(replay)): return {"ok": false}
		if replay.status == "COMPLETE": complete = true; break
	if not _must(complete and str(e3_reference.terrain.site.manual.target).is_empty() and absf(Runtime.now(lab.terrain) - Runtime.now(e3_reference.terrain)) <= E3_EPS, "Reference paid batch completes at the identical time endpoint"): return {"ok": false}
	var results: Array[Dictionary] = []
	for index: int in range(2):
		var scene: TerrainLab = lab if index == 0 else e3_reference
		var cargo: Dictionary = scene.terrain.site.manual.cargo
		var delta := {}
		for key: String in cargo:
			var amount := int(cargo[key]) - int(starts[index].cargo.get(key, 0))
			if amount != 0: delta[key] = amount
		results.append({"produced": int(scene.terrain.site.total_produced) - int(starts[index].produced), "cargo_delta": delta})
	if not _must(results[0] == results[1] and int(results[0].produced) > 0 and _same_ecology_state(lab.terrain, e3_reference.terrain), "Paired batch conserves equal real yield and final source state"): return {"ok": false}
	return {"ok": true, "begin_game": begin, "end_game": target, "actual": results[0], "reference": results[1]}

func _ecology_state(data: TerrainData) -> Dictionary:
	# Arrival may legitimately discover other cells. Compare this same paid source.
	return {"base": data.resource_base, "source": Env.resource(data, e3_key), "ecology": Env.ecology_info(data, e3_key), "ecology_version": data.site.get("ecology_version"), "produced": data.site.total_produced}

func _same_ecology_state(first: TerrainData, second: TerrainData) -> bool:
	var left := _ecology_state(first)
	var right := _ecology_state(second)
	# Only the query's derived floating countdown uses clock epsilon. Saved
	# deadlines, source fields, latch, stock, base and production stay exact.
	var countdown_equal := absf(float(left.ecology.wait_minutes) - float(right.ecology.wait_minutes)) <= E3_EPS
	left.ecology.erase("wait_minutes")
	right.ecology.erase("wait_minutes")
	return countdown_equal and left == right

func _paid_batch(scene: TerrainLab) -> Dictionary:
	if not _must(scene.actor_present(scene.character) and scene.controlled_person_id() == e3_person and scene.character.place(e3_cell, true), "Original controlled body occupies the real source work cell"): return {"ok": false}
	var cargo: Dictionary = scene.terrain.site.manual.cargo
	var before := cargo.duplicate(true)
	var produced := int(scene.terrain.site.total_produced)
	scene.site_controller.source_key = e3_key
	scene.site_controller.manual_work("harvest")
	if not _must(str(scene.terrain.site.manual.target) == e3_key and str(scene.terrain.site.manual.action) == "harvest", "Original controller admits paid harvest without free survey/refill"): return {"ok": false}
	for _step: int in range(E3_LIMIT):
		if str(scene.terrain.site.manual.target).is_empty(): break
		if not _alive(): return {"ok": false}
		if scene.restore_only:
			var step := scene.replay_site_to(Runtime.now(scene.terrain) * 60.0 + 1.0, 0, 128)
			if not _must(step.ok and step.status == "COMPLETE", "Original reference paid work: " + str(step)): return {"ok": false}
		else:
			var step := scene._advance_original_shared_step(scene.EXCHANGE_ACTION_STEP)
			if not _must(step.ok and step.get("completed", false), "Original live paid work: " + str(step)): return {"ok": false}
	if not _must(str(scene.terrain.site.manual.target).is_empty(), "Bounded one-batch completion"): return {"ok": false}
	var delta := {}
	for key: String in cargo:
		var amount := int(cargo[key]) - int(before.get(key, 0))
		if amount != 0: delta[key] = amount
	return {"ok": true, "produced": int(scene.terrain.site.total_produced) - produced, "cargo_delta": delta}

func _finish_e3(ok: bool, message: String = "") -> void:
	if e3_finished: return
	e3_finished = true
	e3_failed = e3_failed or not ok
	if not message.is_empty(): push_error(message)
	if is_instance_valid(lab): lab.free()
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(E3Entry.LAST_WORLD)) if FileAccess.file_exists(E3Entry.LAST_WORLD) else null
	if current is Dictionary and current.get("world_id") == world_id:
		if e3_last_exists:
			var original := FileAccess.open(E3Entry.LAST_WORLD, FileAccess.WRITE)
			original.store_buffer(e3_last_bytes); original.close()
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(E3Entry.LAST_WORLD))
	TerrainArmy.release_contact_source()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(e3_out))
	var evidence := FileAccess.open(e3_out.path_join("ECO15_RECEIPT.json"), FileAccess.WRITE)
	if evidence != null:
		evidence.store_string(JSON.stringify({"failed": e3_failed, "report": report, "source": "accepted C original APIs; staged proposal requires sole runner validation"}, "\t")); evidence.close()
	print("SITE_ECOLOGY_LONGRUN_OWNER_", "FAIL" if e3_failed else "PASS", " ", JSON.stringify(report))
	quit(1 if e3_failed else 0)
