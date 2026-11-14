extends "res://scripts/tests/region_cold_original_matrix_test.gd"
## ECO11 focused calibration through existing real source, Store and Lab owners.
## Reuses original R2 scene/Actor/pump/capture; does not run its whole matrix.
const EcologyCold = preload("res://scripts/terrain_lab/site_region_cold.gd")
const ECOLOGY_REPLAY_SECONDS := 10800.125
const ECOLOGY_SHORT_SECONDS := 135.125
var ecology_groups := 0
var ecology_rows: Array[Dictionary] = []

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	r2_output = "res://.godot-temp/site_ecology_replay/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_run.call_deferred()

func _history_file(resting: bool) -> Dictionary:
	var chosen := {}
	for preset: int in [TerrainPreset.Kind.PLAINS, TerrainPreset.Kind.ISLAND, TerrainPreset.Kind.RIVER_VALLEY]:
		for seed_value: int in [12345, 71, 581, 91, 7, 23]:
			var candidate := TerrainGenerator.generate(preset, seed_value, {"size": Vector2i(64, 64)})
			SiteEnvironment.initialize(candidate, "ecology-replay-" + str(resting))
			if not candidate.is_walkable(Vector2i(6, 6)): continue
			var keys := candidate.resource_base.keys()
			keys.sort()
			for key: String in keys:
				var info := SiteEnvironment.ecology_info(candidate, key)
				if int(info.kind) == SiteEnvironment.Kind.FISH and int(info.capacity) == 20 and not SiteEnvironment.work_cells(candidate, key).is_empty():
					chosen = {"data": candidate, "key": key}
					break
			if not chosen.is_empty(): break
		if not chosen.is_empty(): break
	assert(not chosen.is_empty(), "Generated immutable source must provide actual K20 Fish and the original R2 Actor birth cell")
	var data: TerrainData = chosen.data
	var key: String = chosen.key
	var base_bytes := var_to_bytes(data.resource_base)
	data.site.inventory.tools = 100
	data.site.worker_enabled = false
	assert(SiteRuntime.initialize_item_storage(data.site).ok)
	var work_cell: Vector2i = SiteEnvironment.work_cells(data, key)[0]
	assert(SiteRuntime.ecology_set_modes(data, [key], "general").ok)
	# Both histories produce exactly 18 fish through original accepted batches.
	# General mode retains the latch: true must first cross the actual reserve.
	for _batch: int in range(9 if resting else 5):
		var taken := SiteRuntime.harvest(data, key, work_cell, data.site.manual.cargo)
		assert(taken.ok and int(taken.taken) == 2)
	assert(int(SiteEnvironment.resource(data, key).remaining) == (2 if resting else 10))
	assert(SiteRuntime.ecology_set_modes(data, [key], "sustainable").ok)
	SiteRuntime.advance(data, 7.0 * float(SiteEnvironment.RECOVERY[SiteEnvironment.Kind.FISH]))
	assert(int(SiteEnvironment.resource(data, key).remaining) == (9 if resting else 17))
	if not resting:
		for _batch: int in range(4):
			var taken := SiteRuntime.harvest(data, key, work_cell, data.site.manual.cargo)
			assert(taken.ok and int(taken.taken) == 2)
	SiteRuntime.advance(data, 0.375)
	assert(var_to_bytes(data.resource_base) == base_bytes, "History creation must never replace the generated resource base")
	assert(_assert_history(data, key, resting))
	assert(int(data.site.total_produced) == 18 and int(data.site.manual.cargo.fish) == 18)
	var path := r2_output.path_join("history_%s.json" % str(resting))
	var saved := SiteStore.save(data, path)
	assert(saved.ok, str(saved))
	var loaded := SiteStore.load_site(path, Callable(), 1, true)
	assert(loaded.ok, str(loaded))
	assert(_assert_history(loaded.data, key, resting))
	assert(var_to_bytes(loaded.data.resource_base) == base_bytes)
	return {"data": loaded.data, "key": key, "resting": resting, "path": path, "sha256": FileAccess.get_sha256(path)}

func _ecology_near(actual: float, expected: float) -> bool:
	assert(absf(actual - expected) < 0.000001, "%s != %s" % [actual, expected])
	return true

func _ecology_same_original(actual: Variant, expected: Variant, path: String = "state") -> bool:
	if (actual is int or actual is float) and (expected is int or expected is float):
		assert(absf(float(actual) - float(expected)) < 0.000001,
			"%s actual=%s expected=%s" % [path, str(actual), str(expected)])
	elif actual is Dictionary and expected is Dictionary:
		assert(actual.size() == expected.size(), path)
		for key: Variant in actual:
			assert(expected.has(key), path + "." + str(key))
			assert(_ecology_same_original(actual[key], expected[key], path + "." + str(key)))
	elif actual is Array and expected is Array:
		assert(actual.size() == expected.size(), path)
		for index: int in range(actual.size()): assert(_ecology_same_original(actual[index], expected[index], path + "[%d]" % index))
	elif actual is String and expected is String and path.ends_with(".bytes") and actual != expected:
		# The owner graph wraps typed values as base64 var_to_bytes; the wrapped numbers follow the same 1e-6 rule as
		# every other number here (found 2026-11-14: a resident-prefix float differed from the exact tail by ~1e-15).
		var decoded_actual: Variant = bytes_to_var(Marshalls.base64_to_raw(actual))
		var decoded_expected: Variant = bytes_to_var(Marshalls.base64_to_raw(expected))
		assert(typeof(decoded_actual) == typeof(decoded_expected), "%s decoded types differ" % path)
		assert(_ecology_same_original(decoded_actual, decoded_expected, path + "(decoded)"))
	else:
		assert(actual == expected, "%s actual=%s expected=%s" % [path, str(actual), str(expected)])
	return true

const GRID_TICK_KEY := "current_logic_tick"

func _without_grid_tick(graph: Dictionary) -> Dictionary:
	var result := graph.duplicate(true)
	for node: Variant in result.get("nodes", []):
		if not node is Dictionary or node.get("kind") != "dictionary" or not node.get("entries") is Array: continue
		var kept: Array = []
		for entry: Variant in node.entries:
			var key: Variant = null
			if entry is Array and entry.size() == 2 and entry[0] is Dictionary and entry[0].get("kind") == "atom":
				key = bytes_to_var(Marshalls.base64_to_raw(str(entry[0].bytes)))
			if not (key is String or key is StringName) or str(key) != GRID_TICK_KEY: kept.append(entry)
		node["entries"] = kept
	return result

func _assert_history(data: TerrainData, key: String, resting: bool) -> bool:
	var info := SiteEnvironment.ecology_info(data, key)
	assert(int(info.capacity) == 20 and int(info.remaining) == 9 and str(info.mode) == "sustainable")
	assert(info.resting is bool and bool(info.resting) == resting)
	assert(data.site.changes[key].get("eco_resting") is bool and bool(data.site.changes[key].eco_resting) == resting, "The saved history itself must carry its original Boolean latch")
	assert(int(SiteEnvironment.resource(data, key).next_recovery) == 960)
	assert(int(data.site.minute) == 840)
	assert(_ecology_near(float(data.site.phase), 0.375))
	return true

func _event_helper(source: TerrainData, key: String, resting: bool) -> bool:
	var frozen := _r2_source_bytes(source)
	var normal := SiteEnvironment.navigation_for_state(source, source.site.duplicate(true))
	var cold := SiteEnvironment.navigation_for_state(source, source.site.duplicate(true))
	var start := SiteRuntime.now(source) * 60.0
	var seconds := 259200.125
	var target := start + seconds
	var prepared := EcologyCold.prepare(cold, {"start": start, "end": target})
	assert(prepared.ok and prepared.plan.capabilities.has("resource_events"))
	var first := EcologyCold.advance(cold, target, Callable(), 1)
	assert(first.ok and not bool(first.interval_complete), "Actual due events must retain work at the bounded first receipt")
	var retained := var_to_bytes(cold.site)
	var backward := EcologyCold.advance(cold, float(first.game_seconds) - 1.0)
	assert(not backward.ok and var_to_bytes(cold.site) == retained)
	var latest := first
	for _attempt: int in range(64):
		if bool(latest.interval_complete): break
		assert(Time.get_ticks_msec() <= deadline)
		latest = EcologyCold.advance(cold, target, Callable(), 2)
		assert(latest.ok, str(latest))
	assert(bool(latest.interval_complete) and bool(latest.effects_complete))
	SiteRuntime.advance(normal, seconds / 60.0)
	assert(_ecology_same_original(cold.site, normal.site))
	assert(_r2_source_bytes(source) == frozen and int(cold.site.ecology_version) == 1)
	ecology_rows.append({"case": "resource_events", "resting_at_source": resting, "target": target,
		"steps": latest.total_steps, "phase": cold.site.phase, "source_untouched": true})
	ecology_groups += 1
	return true

func _resident_file(history: Dictionary) -> Dictionary:
	var data: TerrainData = history.data
	var original := _r2_scene()
	# The existing R2 helper creates and captures this one initial real Actor.
	# Every consumer below restores that saved body instead of inventing people.
	_r2_birth(data, 1, false)
	assert(data.site.actors.get("player") is Dictionary, "The original birth helper must publish its actual player body")
	var born: Dictionary = data.site.actors.player
	assert(TerrainTestCharacter.valid_state(born, data) and int(born.person_id) == 1 and born.cell == [6, 6] and born.movement_from == [6, 6] and is_zero_approx(float(born.movement_left)), "Original birth retains the successful instant placement at its original cell")
	assert(str(born.appearance.parts.cape) == "none", "The original newborn outfit retains its authored absent cape")
	assert(born.get("item_state") is Dictionary and not born.item_state.is_empty(), "Original equipment seeding must publish an actual holder")
	assert(SiteRuntime._item_holder_shape(born.item_state) and str(born.item_state.holder) == "person:1")
	var equipment := SiteRuntime.equipment_appearance(data, born.item_state, born.appearance)
	assert(not equipment.is_empty() and equipment.parts == born.appearance.parts and born.item_state.item_ids.size() == born.item_state.equipped.size(), "Every original seeded outfit part must resolve to its actual held and equipped item")
	assert(int(data.site.next_person_id) >= 2 and int(data.site.controlled_person_id) == 1)
	original.bind_terrain(data)
	assert(original.actor_present(original.character))
	original.character.faction_id = 1
	original.character.fatigue = 43.0
	var at := SiteRuntime.now(data) * 60.0
	var supply: Dictionary = SiteStore.Sustain.create(at)
	assert(SiteStore.Sustain.add_members(supply, {1: {"hp": original.character.hp}}, [1]).ok)
	data.site.person_supply = {"1": supply}
	data.site.manual.cargo.grain = 2
	data.site.actor_presence_version = 1
	assert(RegionSaveSlot.attach_settlement(data.site, at).ok)
	data.site = _capture(original)
	var path := r2_output.path_join("resident_%s.json" % str(history.resting))
	var saved := SiteStore.save(data, path)
	assert(saved.ok, str(saved))
	original.free()
	var loaded := SiteStore.load_site(path, Callable(), 1, true)
	assert(loaded.ok, str(loaded))
	assert(_assert_history(loaded.data, str(history.key), bool(history.resting)))
	assert(loaded.data.site.actors.size() == 1 and int(loaded.data.site.manual.cargo.fish) == 18)
	ecology_groups += 1
	return {"data": loaded.data, "key": history.key, "resting": history.resting,
		"at": at, "path": path, "sha256": FileAccess.get_sha256(path)}

func _short_shared(fixture: Dictionary) -> bool:
	var source: TerrainData = fixture.data
	var frozen := _r2_source_bytes(source)
	var normal := _r2_restore(source)
	var cold := _r2_restore(source)
	var target := float(fixture.at) + ECOLOGY_SHORT_SECONDS
	var pending := cold.replay_site_to(target, 0, 1)
	assert(pending.ok and pending.status == "PENDING" and float(pending.pending) > 0.0)
	var retained := _capture(cold)
	var retained_progress := cold.region_cold_actual_progress()
	var wrong := cold.replay_site_to(target + 1.0, 0, 1)
	assert(not wrong.ok and wrong.code == "BUSY")
	assert(_ecology_same_original(_capture(cold), retained))
	assert(_ecology_same_original(cold.region_cold_actual_progress(), retained_progress))
	while pending.ok and pending.status == "PENDING":
		assert(Time.get_ticks_msec() <= deadline)
		pending = cold.replay_site_to(target, 0, 17)
	assert(pending.ok and pending.status == "COMPLETE" and float(pending.pending) == 0.0)
	var expected := normal.replay_site_to(target)
	assert(expected.ok and expected.status == "COMPLETE")
	assert(_ecology_same_original(_capture(cold), _capture(normal)))
	assert(_ecology_same_original(cold.region_cold_actual_progress(), normal.region_cold_actual_progress()))
	var info := SiteEnvironment.ecology_info(cold.terrain, str(fixture.key))
	assert(int(info.remaining) == 9 and bool(info.resting) == bool(fixture.resting), "Shared partial replay must retain the actual N9 history before its next due event")
	assert(_ecology_near(float(cold.terrain.site.phase), fposmod(0.375 + ECOLOGY_SHORT_SECONDS / 60.0, 1.0)))
	var settled := _capture(cold)
	var progress := cold.region_cold_actual_progress()
	var zero := cold.replay_site_to(target, 0, 1)
	assert(zero.ok and zero.steps == 0 and zero.pending == 0.0)
	assert(_ecology_same_original(_capture(cold), settled))
	assert(_ecology_same_original(cold.region_cold_actual_progress(), progress))
	assert(_r2_source_bytes(source) == frozen)
	ecology_rows.append({"case": "shared_pending_zero", "resting_at_source": fixture.resting,
		"target": target, "phase": cold.terrain.site.phase, "source_sha256": fixture.sha256,
		"pending_completed": true, "wrong_target_refused": true, "zero_time_unchanged": true})
	normal.free()
	cold.free()
	ecology_groups += 1
	return true

func _resident_prefix(fixture: Dictionary) -> bool:
	var source: TerrainData = fixture.data
	var normal := _r2_restore(source)
	var hybrid := _r2_restore(source)
	var target := float(fixture.at) + ECOLOGY_REPLAY_SECONDS
	var expected: Dictionary = await _r2_pump(normal, source, target, false, 30000000)
	var candidate: Dictionary = await _r2_pump(hybrid, source, target, true, 30000000)
	assert(expected.complete and candidate.complete, "Both actual original consumers must reach COMPLETE inside the bounded work budget")
	assert(int(candidate.prefix_steps) > 0 and int(candidate.exact_steps) > 0, "A resident prefix and the original exact tail are both required; fallback-only is not PASS")
	assert(EcologyCold._resident_inputs(hybrid.terrain).ok, "Resident helper inputs come from the actual original Lab owner admission")
	assert(_ecology_same_original(_capture(hybrid), _capture(normal)))
	assert(_ecology_same_original(candidate.progress, expected.progress))
	# Nekki 2026-11-14 A: the retired grid movement coordinator's idle step counter (current_logic_tick, and the copy
	# TerrainArmy keeps) is not part of the equality: the exact tail counts every idle step, the resident prefix
	# summarises them, and no crowd behaviour reads it. Every other owner field is still compared.
	assert(_ecology_same_original(_without_grid_tick(_r2_actual_owner_graph(hybrid)), _without_grid_tick(_r2_actual_owner_graph(normal))))
	assert(_ecology_near(float(hybrid.terrain.site.phase), fposmod(0.375 + ECOLOGY_REPLAY_SECONDS / 60.0, 1.0)))
	ecology_rows.append({"case": "actual_resident_prefix", "resting_at_source": fixture.resting,
		"target": target, "source_sha256": fixture.sha256, "prefix_steps": candidate.prefix_steps,
		"exact_steps": candidate.exact_steps, "method": candidate.method,
		"phase": hybrid.terrain.site.phase, "full_state_owner_graph_equal": true})
	normal.free()
	hybrid.free()
	ecology_groups += 1
	return true

func _run() -> void:
	_started = true
	root.gui_embed_subwindows = true
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(r2_output)) == OK)
	for resting: bool in [false, true]:
		var history := _history_file(resting)
		assert(_event_helper(history.data, str(history.key), resting))
		var resident := _resident_file(history)
		assert(_short_shared(resident))
		assert(await _resident_prefix(resident))
	assert(ecology_groups == 8 and r2_failed.is_empty() and Time.get_ticks_msec() <= deadline)
	var evidence := FileAccess.open(r2_output.path_join("ECO11_RECEIPT.json"), FileAccess.WRITE)
	assert(evidence != null)
	evidence.store_string(JSON.stringify({"scope": "focused ECO11 isolated original consumers", "rows": ecology_rows,
		"pinned_slot_journal": "separate original regression", "godot_gpu_fps_release": "not claimed"}, "\t"))
	evidence.close()
	TerrainArmy.release_contact_source()
	_finished = true
	print("SITE_ECOLOGY_REPLAY_PASS groups=8 actual_generated_K20=true histories_N9_false_true=true physical_harvest_each=18 store_roundtrip=true resource_events_pending_phase_equal=true actual_shared_pending_fixed_target_zero_equal=true actual_resident_prefix_and_exact_tail=true full_original_state_progress_graph_equal=true; no pinned Slot journal, GPU, FPS, release or all16ECO claim")
	quit(0)
