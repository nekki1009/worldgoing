extends "res://scripts/tests/site_shared_step_replay_test.gd"
## R2 S01/S02 calibration. Every consumer is the actual original PackedScene.
## No fake original-step callback, progress bool, clock or saved people mirror.
const R2_TARGETS := [7200.0, 86400.0, 604800.0, 2592000.0]
const R2_CASES := ["empty", "resident", "army_105", "settlement", "production", "captivity", "fire", "army_max"]
const R2_BUDGET_USEC := 4000
const R2_STEPS := 128
var r2_output := ""
var r2_evidence: Array[Dictionary] = []
var r2_failed: Array[String] = []
var r2_source_files: Dictionary = {}

func _process(_delta: float) -> bool:
	if not _finished and Time.get_ticks_msec() > deadline:
		print("REGION_COLD_ORIGINAL_MATRIX_FAIL: bounded test deadline")
		quit(1)
	return false

func _r2_check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		r2_failed.append(message)
		push_error(message)
	return value

func _r2_scene(with_npc: bool = false) -> TerrainLab:
	var packed: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn")
	assert(packed != null)
	var lab := packed.instantiate() as TerrainLab
	if with_npc: lab.npc = TerrainTestNPC.new()
	lab.restore_only = true
	lab.exchange_enabled = true
	lab.pause_when_unfocused = false
	lab.visible = false
	root.add_child(lab)
	assert(lab.terrain == null)
	lab.site_controller._auto_save_blocked = true
	return lab

func _r2_data(name: String) -> TerrainData:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 77319, {"size": Vector2i(100, 100)})
	SiteEnvironment.initialize(data, "r2-original-" + name)
	# Authored initial geometry; every replay later uses this exact saved base.
	for index: int in range(data.height_levels.size()):
		data.height_levels[index] = 0
		data.site.terrain_changes[str(index)] = 0
	for key: String in data.resource_base: SiteEnvironment.change(data, key, {"cleared": true, "remaining": 0})
	data.site.capacity = 100000
	for item: String in SiteEnvironment.ITEM_NAMES: data.site.inventory[item] = 1000
	data.site.depot_cell = data.index(Vector2i(6, 6))
	data.site.worker.cell = data.index(Vector2i(6, 7))
	data.site.worker_enabled = false
	assert(SiteRuntime.initialize_item_storage(data.site).ok)
	SiteRuntime.rebuild_terrain_edges(data)
	SiteEnvironment.rebuild_indexes(data)
	return data

func _r2_fixture(name: String) -> Dictionary:
	var data := _r2_data(name)
	var lab: TerrainLab = null
	if name != "empty":
		lab = _r2_scene(name in ["production", "captivity"])
		# Explicit newborn fixture through original Actor capture/restore and
		# original equipment creation. Clothing is chosen before any gear exists.
		_r2_birth(data, 1, false)
		if is_instance_valid(lab.npc): _r2_birth(data, 2, true)
		lab.bind_terrain(data)
		if is_instance_valid(lab.npc): data.site.next_person_id = maxi(3, int(data.site.get("next_person_id", 2)))
		assert(lab.terrain == data and lab.actor_present(lab.character))
		assert(lab.character.place(Vector2i(6, 6), true))
		lab.character.faction_id = 1
		lab.character.fatigue = 43.0 if name == "resident" else 0.0
		var supply: Dictionary = SiteStore.Sustain.create(0.0)
		assert(SiteStore.Sustain.add_members(supply, {1: {"hp": lab.character.hp}}, [1]).ok)
		data.site.person_supply = {"1": supply}
		data.site.manual.cargo.grain = 1000
		if name in ["army_105", "army_max"]:
			var total_rows := SiteStore.MAX_ARMY_ROWS if name == "army_max" else 105
			var team_count := ceili(float(total_rows) / TerrainArmy.MAX_ROSTER_SIZE)
			lab._ensure_army_slots(team_count)
			var positions: Array[Vector2i] = []
			for y: int in range(10, 99):
				for x: int in range(1, 99):
					if positions.size() < total_rows: positions.append(Vector2i(x, y))
			assert(positions.size() == total_rows)
			var offset := 0
			for team_index: int in range(team_count):
				var team: TerrainArmy = lab.combat_armies[team_index]
				team.roster_size = mini(TerrainArmy.MAX_ROSTER_SIZE, total_rows - offset)
				team.faction_id = 1
				var selected: Array[Vector2i] = []
				selected.assign(positions.slice(offset, offset + team.roster_size))
				if not team.deploy_at(data, null, null, selected) or not team.enable_combat(false):
					lab.free()
					return {"ok": false, "case": name, "stage": "actual_original_deployment", "code": "ORIGINAL_DEPLOYMENT_DENIED",
						"requested_total_rows": total_rows, "per_team_limit": TerrainArmy.MAX_ROSTER_SIZE, "source_saved": false}
				team.set_process(false)
				lab.site_controller.initialize_team_items(team)
				var stocked: Dictionary = lab.site_controller._enable_team_supply(team)
				assert(not stocked.is_empty())
				stocked.inventory.grain = 1000
				offset += team.roster_size
			assert(offset == total_rows)
			data.site.army_next_team = lab._next_army_identity()
		elif name == "settlement":
			var options := {"layout_version": 1, "quarter": 0, "owner_faction": 1}
			var layout := SiteRuntime.building_cells(data, "settlement_center", Vector2i(10, 10), Vector2i.ONE, options)
			assert(layout.ok, str(layout))
			var cells: Array[int] = []
			cells.assign(layout.cells)
			var founded := SiteSettlement.found(lab, 1, cells, options, Callable(), "R2 original center")
			assert(founded.ok, str(founded))
			var feature: Dictionary = data.site.features[founded.feature]
			var task := {"version": 2, "zone": -1, "target": "feature:" + str(founded.feature), "action": "construct",
				"work_cell": int(feature.entrance), "cell": int(feature.entrance), "mode": "work", "progress": 0.0, "status": "", "work_slot": -1}
			SiteRuntime._feature_work(data, str(founded.feature), float(feature.work), Callable(), Callable(), task, {}, 20, 1)
			assert(str(feature.stage) == "complete" and data.site.settlement.level == 1)
		elif name == "production":
			var farm := _build(data, "farm", Vector2i(10, 30), Vector2i(12, 6))
			_build(data, "well", Vector2i(8, 32))
			_build(data, "well", Vector2i(24, 32))
			assert(SiteRuntime.operate_feature(data, farm).ok)
			lab.npc.faction_id = 1
			lab.npc.issue_command(TerrainTestNPC.Command.STOP)
			var work_slots: Array = SiteRuntime.feature_work_slots(data, data.site.features[farm])
			assert(lab.npc.place(data.cell_from_index(int(work_slots[0].cell)), true))
			data.site.worker.cell = int(work_slots[0].cell)
			data.site.worker_enabled = true
			SiteRuntime.assign_task(data, SiteRuntime.ok("R2 paid original farm", {"target": "feature:" + farm,
				"action": "operate", "cell": int(work_slots[0].cell), "work_slot": int(work_slots[0].slot)}))
			data.site.worker.mode = "work"
			lab.restore_only = false
			lab.movement_input_enabled = false
			lab._advance_action_time(0.5)
			lab.restore_only = true
			assert(data.site.features[farm].batch_paid and float(data.site.features[farm].production) > 0.0)
		elif name == "captivity":
			lab.npc.faction_id = 2
			lab.npc.issue_command(TerrainTestNPC.Command.STOP)
			assert(lab.npc.place(Vector2i(7, 6), true))
			lab.npc.knockout_left = 30.0 # Authored initial KO; the actual PA owns capture.
			var binding: Dictionary = lab.site_controller.person_actions.begin_capture(1, 2, 1)
			assert(binding.ok, str(binding))
			lab.site_controller.person_actions.advance(lab.site_controller.person_actions.BIND_SECONDS)
			lab.site_controller.person_actions.settle_after_contacts()
			assert(data.site.captivity.has("2") and lab.npc.captive)
		elif name == "fire":
			var cell := Vector2i(20, 20)
			SiteEnvironment._add_resource(data, SiteEnvironment.Kind.TIMBER, data.index(cell), 4, 0)
			SiteEnvironment.rebuild_indexes(data)
			var contact := SiteRuntime.fire_receive_impact(data, {"site_id": str(data.site.id), "projectile_id": 1,
				"event_id": "arrow:1", "action_time": lab.fire_action_cursor, "type": "ground", "cell": cell,
				"remaining_heat_budget": 20.0, "heat_rate": 100.0, "max_seconds": 0.2, "heat_transfer": 1.0, "contact_scale": 1.0})
			assert(contact.ok and contact.accepted, str(contact))
		assert(lab.site_controller._capture_for_save().ok)
		data.site = _capture(lab)
	data.site.actor_presence_version = 1
	var at := SiteRuntime.now(data) * 60.0
	assert(RegionSaveSlot.attach_settlement(data.site, at).ok)
	var path := r2_output.path_join(name + "_source.json")
	var saved := SiteStore.save(data, path)
	if is_instance_valid(lab): lab.free()
	if not saved.ok:
		return {"ok": false, "code": str(saved.get("code", "")), "message": str(saved.get("message", "")), "case": name, "stage": "actual_source_save"}
	var loaded := SiteStore.load_site(path, Callable(), 1, true)
	if not loaded.ok: return loaded
	r2_source_files[name] = {"path": path, "sha256": FileAccess.get_sha256(path)}
	return {"ok": true, "data": loaded.data, "at": at, "path": path}

func _r2_birth(data: TerrainData, identity: int, is_npc: bool) -> void:
	var body: TerrainTestCharacter = TerrainTestNPC.new() if is_npc else TerrainTestCharacter.new()
	body.person_id = identity
	body.data = data
	root.add_child(body)
	body.set_process(false)
	body.initialize_visual()
	assert(body.place(Vector2i(7 if is_npc else 6, 6), true))
	var initial := body.capture_state()
	assert(body.item_state.is_empty(), "Newborn has no existing equipment to delete")
	initial.appearance.parts.cape = "none"
	body.restore_state(initial)
	var seeded := SiteRuntime.seed_person_equipment(data, body.item_state, identity, initial.appearance)
	assert(seeded.ok, str(seeded))
	data.site.actors["npc" if is_npc else "player"] = body.capture_state()
	data.site.next_person_id = maxi(identity + 1, int(data.site.get("next_person_id", 1)))
	data.site.controlled_person_id = 1
	body.free()

func _r2_source_bytes(data: TerrainData) -> PackedByteArray:
	var all: Array = [data.site, data.parameters, data.resource_base]
	for field: String in ["height_levels", "surface_types", "flags", "cliff_drops", "ramp_edges", "detail_variation", "fertility", "moisture", "drainage", "foundation", "groundwater", "water_kind", "water_body"]:
		all.append(data.get(field))
	return var_to_bytes(all)

func _r2_restore(source: TerrainData) -> TerrainLab:
	var frozen := _r2_source_bytes(source)
	var lab := _r2_scene(source.site.actors.has("npc"))
	var restored := lab.restore_original_site(source)
	assert(restored.ok and lab.terrain != source, str(restored))
	assert(_r2_source_bytes(source) == frozen)
	return lab

func _r2_differences(actual: Variant, expected: Variant, path: String = "state") -> Array[String]:
	var result: Array[String] = []
	if (actual is int or actual is float) and (expected is int or expected is float):
		if absf(float(actual) - float(expected)) > 0.00001: result.append("%s actual=%s expected=%s" % [path, str(actual), str(expected)])
	elif actual is Dictionary and expected is Dictionary:
		if actual.size() != expected.size(): result.append(path + " dictionary size differs")
		for key: Variant in actual:
			if not expected.has(key): result.append(path + "." + str(key) + " missing")
			else: result.append_array(_r2_differences(actual[key], expected[key], path + "." + str(key)))
			if result.size() >= 20: break
	elif actual is Array and expected is Array:
		if actual.size() != expected.size(): result.append(path + " array size differs")
		for index: int in range(mini(actual.size(), expected.size())):
			result.append_array(_r2_differences(actual[index], expected[index], path + "[%d]" % index))
			if result.size() >= 20: break
	elif actual != expected:
		result.append("%s actual=%s expected=%s" % [path, str(actual), str(expected)])
	return result

func _r2_actual_owner_graph(scene: TerrainLab) -> Dictionary:
	var actual: Dictionary = scene.call("region_cold_actual_progress")
	var fire: Dictionary = scene.terrain.site.get("fire_settlement", {})
	# Context is derived from these completed original consumers. An isolated
	# body without a Slot has no Fire epoch/sequence; neither is invented here.
	var context := {"purpose": "region_checkpoint", "mode": "cold_exact", "source_generation": int(actual.owner_generation),
		"runtime_revision": 0, "token": "r2_same_original_comparison", "game_seconds": float(actual.game_seconds),
		"action_seconds": float(actual.action_seconds), "fire_epoch": str(fire.get("epoch", "")),
		"fire_sequence": int(fire.get("sequence", 0)), "interval_complete": true, "effects_complete": true,
		"mode_revision": 0, "backend": "gd", "events": [], "endpoint_payload": {}}
	var captured := scene.capture_region_owner_state(context)
	if not _r2_check(captured.ok, "actual original hot-owner graph capture: " + str(captured)): return {}
	return captured.state

func _r2_pump(lab: TerrainLab, source: TerrainData, target: float, hybrid: bool, max_work_usec: int = 2000000,
		max_total_steps: int = 12000) -> Dictionary:
	var frozen := _r2_source_bytes(source)
	var original_data := lab.terrain
	var original_bodies: Dictionary = {}
	for actor: TerrainTestCharacter in lab.combat_actors:
		if lab.actor_present(actor): original_bodies[actor.person_id] = actor
	var duty_before := TerrainLab._region_capture_duty_cache()
	var work_usec := 0
	var steps := 0
	var calls := 0
	var latest := {}
	while work_usec < max_work_usec and steps < max_total_steps:
		var begin := Time.get_ticks_usec()
		latest = lab.call("advance_isolated_region_cold", target, R2_BUDGET_USEC, R2_STEPS, 7200.0) if hybrid \
			else lab.replay_site_to(target, R2_BUDGET_USEC, R2_STEPS)
		work_usec += Time.get_ticks_usec() - begin
		steps += int(latest.get("steps", 0))
		calls += 1
		assert(_r2_source_bytes(source) == frozen and lab.terrain == original_data)
		for actor: TerrainTestCharacter in lab.combat_actors:
			if original_bodies.has(actor.person_id): assert(original_bodies[actor.person_id] == actor)
		if not latest.get("ok", false) or str(latest.get("status", "")) == "COMPLETE": break
		await process_frame
	TerrainLab._region_restore_duty_cache(duty_before)
	var progress: Dictionary = lab.call("region_cold_actual_progress")
	return {"ok": latest.get("ok", false), "complete": latest.get("ok", false) and str(latest.get("status", "")) == "COMPLETE",
		"status": str(latest.get("status", latest.get("code", ""))), "target": target, "pending": maxf(0.0, target - float(progress.game_seconds)),
		"processing_usec": work_usec, "steps": steps, "calls": calls, "per_call_budget_usec": R2_BUDGET_USEC,
		"per_call_step_limit": R2_STEPS, "process_cpu_seconds": null, "process_cpu_source": "external canonical host required",
		"method": str(latest.get("method", "original_shared_exact")), "prefix_steps": int(latest.get("prefix_steps", 0)),
		"exact_steps": int(latest.get("exact_steps", steps)), "fallback": str(latest.get("fallback", "")),
		"error": str(latest.get("code", "")), "progress": progress}

func _r2_compare(name: String, fixture: Dictionary, seconds: float, positive_gate: bool = false) -> Dictionary:
	var source: TerrainData = fixture.data
	var normal := _r2_restore(source)
	var hybrid := _r2_restore(source)
	var target := float(fixture.at) + seconds
	var limit := 20000000 if positive_gate else 2000000
	var expected: Dictionary = await _r2_pump(normal, source, target, false, limit)
	var candidate: Dictionary = await _r2_pump(hybrid, source, target, true, limit)
	var equal := false
	var differences: Array[String] = []
	if expected.complete and candidate.complete:
		differences.append_array(_r2_differences(_capture(hybrid), _capture(normal)))
		differences.append_array(_r2_differences(candidate.progress, expected.progress, "actual_owner_progress"))
		differences.append_array(_r2_differences(_r2_actual_owner_graph(hybrid), _r2_actual_owner_graph(normal), "actual_complete_owner_graph"))
		equal = differences.is_empty()
		_r2_check(equal, name + " actual original completed state differs: " + str(differences))
	if positive_gate:
		_r2_check(expected.complete and candidate.complete, name + " S01 requires both actual original consumers COMPLETE")
		_r2_check(equal and int(candidate.prefix_steps) > 0, name + " S01 requires full original equality and a consumed quiet prefix")
	if name not in ["empty", "resident"]:
		_r2_check(int(candidate.prefix_steps) == 0, name + " unsupported original owner must remain exact")
	var row := {"case": name, "seconds": seconds, "baseline": expected, "candidate": candidate,
		"comparison": "FULL_ORIGINAL_EQUAL" if equal else ("ORIGINAL_STATE_DIFFERS" if not differences.is_empty() else "PENDING_UNVERIFIED"),
		"differences": differences, "source": r2_source_files[name],
		"same_saved_source": true, "scope": "isolated calibration; formal Slot admission is a separate gate"}
	normal.free()
	hybrid.free()
	return row

func _r2_cancel(source: TerrainData) -> Dictionary:
	var host := _r2_scene()
	var frozen := _r2_source_bytes(source)
	var target := SiteRuntime.now(source) * 60.0 + 2592000.0
	var first := host.advance_cold_site(source, target)
	_r2_check(not first.ok and str(first.get("code", "")) == "PENDING", "actual host cancellation fixture must have original work remaining")
	var retained := host._cold_replay_lab
	var signature := str(first.get("source_sha256", ""))
	var before: PackedByteArray = var_to_bytes([retained.terrain.site, retained.fire_action_cursor]) if is_instance_valid(retained) else PackedByteArray()
	var wrong := host.cancel_cold_site_replay("wrong-source")
	_r2_check(not wrong.ok and wrong.code == "STALE_SOURCE" and host._cold_replay_lab == retained, "wrong source cannot retire actual pending owner")
	if is_instance_valid(retained): _r2_check(var_to_bytes([retained.terrain.site, retained.fire_action_cursor]) == before, "wrong-source cancellation is pure")
	var cancelled := host.cancel_cold_site_replay(signature)
	_r2_check(cancelled.ok and not is_instance_valid(host._cold_replay_lab) and _r2_source_bytes(source) == frozen, "actual cancellation leaves saved bodies/base/time untouched")
	var retry := host.advance_cold_site(source, target)
	_r2_check(not retry.ok and retry.code == "PENDING" and str(retry.source_sha256) == signature and _r2_source_bytes(source) == frozen,
		"cancelled fixed source restarts through its original consumer without committing progress")
	if is_instance_valid(host._cold_replay_lab): host.cancel_cold_site_replay(str(retry.get("source_sha256", "")))
	host.free()
	return {"case": "cancel_resume", "source_sha256": signature, "first_status": str(first.get("code", "")),
		"retry_status": str(retry.get("code", "")), "source_unchanged": _r2_source_bytes(source) == frozen, "world_published": false}

func _run() -> void:
	_started = true
	deadline = Time.get_ticks_msec() + 360000
	r2_output = "res://.godot-temp/region_cold_original_matrix/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(r2_output)) == OK)
	var probe := _r2_scene()
	assert(probe.has_method("advance_isolated_region_cold") and probe.has_method("region_cold_actual_progress"), "install staged original bridge before calibration")
	probe.free()
	for name: String in R2_CASES:
		var fixture := _r2_fixture(name)
		if not fixture.ok:
			r2_evidence.append(fixture)
			_r2_check(false, name + " actual original fixture unavailable: " + str(fixture))
			continue
		if name in ["empty", "resident"]: r2_evidence.append(await _r2_compare(name, fixture, 10800.0, true))
		for seconds: float in R2_TARGETS:
			r2_evidence.append(await _r2_compare(name, fixture, seconds))
		if name == "army_105": r2_evidence.append(_r2_cancel(fixture.data))
	var sources := {}
	for path: String in ["res://scripts/terrain_lab/terrain_lab.gd", "res://scripts/terrain_lab/site_controller.gd",
		"res://scripts/terrain_lab/site_region_cold.gd", "res://scripts/terrain_lab/site_sustain.gd", "res://scripts/region_lab/region_save_slot.gd"]:
		sources[path] = FileAccess.get_sha256(path)
	var out := FileAccess.open(r2_output.path_join("result.json"), FileAccess.WRITE)
	assert(out != null)
	out.store_string(JSON.stringify({"scope": "R2 S01/S02 isolated original calibration only", "checks": checks,
		"failed": r2_failed, "sources": sources, "rows": r2_evidence, "formal_slot_admitted": false,
		"performance_complete": false, "process_cpu_seconds": null}, "\t"))
	out.close()
	TerrainArmy.release_contact_source()
	_finished = true
	print("REGION_COLD_ORIGINAL_MATRIX_", "CALIBRATION_PASS" if r2_failed.is_empty() else "FAIL", ": checks=", checks,
		" actual PackedScene owners; retained whole saved sources; 2h/day/week/month measured work and explicit PENDING; ",
		"same-original full-state calibration; actual cancel/restart; no formal Slot/R2/performance/GPU/release close; evidence=", r2_output)
	quit(0 if r2_failed.is_empty() else 1)
