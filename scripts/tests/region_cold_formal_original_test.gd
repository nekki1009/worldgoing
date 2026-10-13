extends "res://scripts/tests/region_controlled_death_restriction_test.gd"
## Separate R2 formal gate. Reuses only the original pinned-manifest/freeze
## fixture helpers; it does not execute or claim controlled-death acceptance.
var formal_expected: Dictionary = {}
var formal_result: Dictionary = {}
var formal_source: TerrainData
var formal_source_hash := ""
var formal_marker := 0
var formal_sequence := 0
var formal_world := 0.0
var formal_action := 0.0
## "exact" (default): this build's journal. "legacy": the same live journal
## re-merged by the older 1e-10 rule, as an older save holds it.
var journal_case := "exact"
var legacy_rows := {}

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	for argument: String in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if argument.begins_with("--journal-case="): journal_case = argument.trim_prefix("--journal-case=")
	out = "res://.godot-temp/region_cold_formal_original/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	last_world_exists = FileAccess.file_exists(Entry.LAST_WORLD)
	if last_world_exists: last_world_bytes = FileAccess.get_file_as_bytes(Entry.LAST_WORLD)
	_run.call_deferred()

func _formal_capture(original: TerrainLab, context: Dictionary) -> Dictionary:
	var position_capture: Dictionary = original.site_controller._capture_for_save()
	if not _check(position_capture.ok, "Actual original position/item snapshot", position_capture): return {}
	var owners := original.capture_region_owner_state(context)
	if not _check(owners.ok, "Actual original full hot graph", owners): return {}
	var captured := SiteStore.capture_region_snapshot(original.terrain, context, owners.owner_states)
	if not _check(captured.ok, "Actual original Store region payload", captured): return {}
	return captured.state

func _formal_same(first: Variant, second: Variant, path: String = "full_original_state") -> bool:
	if (first is int or first is float) and (second is int or second is float):
		return _check(absf(float(first) - float(second)) <= 0.00001, path, [first, second])
	if first is Dictionary and second is Dictionary:
		if not _check(first.size() == second.size(), path + " dictionary size"): return false
		for key: Variant in first:
			if not _check(second.has(key), path + "." + str(key)): return false
			if not _formal_same(first[key], second[key], path + "." + str(key)): return false
		return true
	if first is Array and second is Array:
		if not _check(first.size() == second.size(), path + " array size"): return false
		for index: int in range(first.size()):
			if not _formal_same(first[index], second[index], path + "[%d]" % index): return false
		return true
	return _check(first == second, path, [first, second])

func _run() -> void:
	RegionTravelSite.scene_handoff = false
	RegionRoute.clear_memory_cache()
	if not _write_manifest(): _finish(false); return
	var packed := load("res://scenes/terrain_lab/TerrainLab.tscn") as PackedScene
	lab = packed.instantiate() as TerrainLab
	lab.restore_only = true
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	lab.visible = false
	root.add_child(lab)
	controller = lab.site_controller
	_freeze(lab)
	var archived := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"size": Vector2i(32, 32)})
	Env.initialize(archived, "r2-formal:archive")
	lab.bind_terrain(archived)
	lab.restore_only = false
	controller.save_root = out.path_join("archive")
	world_id = "r2_formal_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var opened := controller.open_fixed_world(manifest_path, world_id, "main", Vector2i.ZERO, true)
	if not _check(opened.ok, "Actual original first-world publication", opened): _finish(false); return
	_freeze(lab)
	lab.simulation_speed = 4.0 # Actual supported speed; no clock assignment.
	lab.exchange_enabled = true
	slot = controller.region_slot
	var wired := lab._wire_region_gameplay_adapters(slot)
	if not _check(wired.ok, "Same actual Slot adapters", wired): _finish(false); return
	cold_id = Grid.site_id(str(slot.pin.atlas_id), Vector2i(1, 0))
	var owner := lab._region_gameplay_owner_lab(cold_id, "cold_exact")
	if not _check(owner.ok and owner.lab is TerrainLab, "Actual original cold factory", owner): _finish(false); return
	cold = owner.lab
	_freeze(cold)
	var committed := controller.checkpoint_region_internal("region_checkpoint", true)
	if not _check(committed.ok, "Actual joint selected generation stores the cold genesis", committed): _finish(false); return
	owner = lab._region_gameplay_owner_lab(cold_id, "cold_exact")
	if not _check(owner.ok, "Cold mode derives the selected current generation", owner): _finish(false); return
	var source_path := slot.site_path(Vector2i(1, 0))
	var loaded := slot._load_checked(source_path, Vector2i(1, 0))
	if not _check(loaded.ok, "Selected canonical original genesis readback", loaded): _finish(false); return
	formal_source = loaded.data
	formal_source_hash = FileAccess.get_sha256(source_path)
	var source_bytes := var_to_bytes([formal_source.site, formal_source.fingerprint(), formal_source.parameters])
	if not _check(formal_source.site.fire_settlement.sequence == 0 and formal_source.site.has("region_snapshot"),
		"A real selected genesis carries Fire and full original owner context"): _finish(false); return
	var steps := 0
	while float(slot.control.logical_game_seconds) + EPS < 10800.0 and steps < 5000:
		var stepped := lab._advance_original_shared_step(lab.EXCHANGE_ACTION_STEP)
		if not _check(stepped.ok, "Actual Main produces original journal and both true owners", stepped): _finish(false); return
		if stepped.get("completed", false): steps += 1
		if steps % 64 == 0: await process_frame
	if not _check(absf(float(slot.control.logical_game_seconds) - 10800.0) <= EPS, "Actual 3h quiet journal endpoint"): _finish(false); return
	var due := slot.consume_due_region_events()
	if not _check(due.ok and due.get("complete") == true, "Actual original world endpoint is consumed before cold calibration", due): _finish(false); return
	formal_marker = int(slot._marker.generation)
	formal_sequence = int(slot.control.fire_clock.sequence)
	formal_world = float(slot.control.logical_game_seconds)
	formal_action = float(slot.control.fire_clock.action_seconds)
	var actual_context := slot.region_checkpoint_context(cold.terrain, "region_checkpoint", "r2_same_formal_context", true, {})
	if not _check(actual_context.ok, "Comparison context comes from actual Slot clocks", actual_context): _finish(false); return
	formal_expected = _formal_capture(cold, actual_context.context)
	if failed: _finish(false); return
	if not _check(journal_case in ["exact", "legacy"], "one bounded journal case", journal_case): _finish(false); return
	if journal_case == "legacy" and not _formal_legacy_journal(): _finish(false); return
	var first := lab.advance_cold_site(formal_source, formal_world)
	if not _check(not first.ok and first.get("code") == "PENDING" and is_instance_valid(lab._cold_replay_lab),
		"The actual fixed-target cold caller retains its original candidate", first): _finish(false); return
	var replay: TerrainLab = lab._cold_replay_lab
	if not _check(replay.has_method("advance_region_cold_actual_fixed"), "Formal original bridge is installed"): _finish(false); return
	var actual := replay._region_cold_formal_admission()
	if not _check(actual.ok, "Selected same-Slot/mode/G/current private restore prove formal quiet", actual): _finish(false); return
	var progressed := {}
	for pump: int in range(5000):
		progressed = replay.advance_region_cold_actual_fixed(formal_source, formal_world, 4000, 128, 7200.0)
		if not _check(progressed.ok, "Actual formal original replay pump", progressed): _finish(false); return
		if progressed.status == "COMPLETE": break
		await process_frame
	if journal_case == "legacy":
		if not _check(progressed.get("status") == "COMPLETE" and int(progressed.get("prefix_steps", -1)) == 0 and str(progressed.get("fallback", "")) == "COLD_EXACT_JOURNAL",
			"Legacy tolerance-merged rows replay on the exact path without a quiet prefix", progressed): _finish(false); return
	elif not _check(progressed.get("status") == "COMPLETE" and int(progressed.get("prefix_steps", 0)) > 0,
		"Formal positive requires a consumed actual quiet prefix and complete exact tail", progressed): _finish(false); return
	var candidate := _formal_capture(replay, actual_context.context)
	if failed: _finish(false); return
	if journal_case == "legacy":
		# Older merged rows no longer hold each live step width, so the exact path
		# cannot promise bit equality there; the case asserts the safe fallback above
		# and records whether the replay still happened to equal the original.
		legacy_rows["full_original_equal"] = JSON.stringify(candidate, "", true, true) == JSON.stringify(formal_expected, "", true, true)
		legacy_rows["exchange_equal"] = var_to_bytes([replay._exchange_phase, replay._exchange_round]) == var_to_bytes([cold._exchange_phase, cold._exchange_round])
	else:
		if not _formal_same(candidate, formal_expected): _finish(false); return
		# The exchange cadence is not in the captured graph; the quiet prefix must leave
		# it bit-identical to the original that ran every live step.
		if not _check(var_to_bytes([replay._exchange_phase, replay._exchange_round]) == var_to_bytes([cold._exchange_phase, cold._exchange_round]),
			"Quiet prefix and exact tail leave the exchange phase and round bit-identical to the original", [replay._exchange_phase, cold._exchange_phase, replay._exchange_round, cold._exchange_round]): _finish(false); return
	var finalized := lab.advance_cold_site(formal_source, formal_world)
	if not _check(finalized.ok and not is_instance_valid(lab._cold_replay_lab), "Actual parent registers the completed body before retirement", finalized): _finish(false); return
	var source_receipt := lab._region_selected_bind_source(finalized.data, slot)
	if not _check(source_receipt.ok and source_receipt.get("replayed") == true, "Actual completed body has original selected-source provenance", source_receipt): _finish(false); return
	if not _check(int(slot._marker.generation) == formal_marker and int(slot.control.fire_clock.sequence) == formal_sequence
		and float(slot.control.logical_game_seconds) == formal_world and float(slot.control.fire_clock.action_seconds) == formal_action,
		"Cold candidate publishes no extra marker, world clock or journal interval"): _finish(false); return
	if not _check(FileAccess.get_sha256(source_path) == formal_source_hash
		and var_to_bytes([formal_source.site, formal_source.fingerprint(), formal_source.parameters]) == source_bytes,
		"Saved actual source remains immutable across prefix/tail/retirement"): _finish(false); return
	formal_result = {"main_steps": steps, "game_seconds": formal_world, "action_seconds": formal_action,
		"sequence": formal_sequence, "generation": formal_marker, "prefix_steps": int(progressed.prefix_steps),
		"exact_steps": int(progressed.exact_steps), "processing_usec_last_pump": int(progressed.processing_usec),
		"full_original_equal": journal_case == "exact", "source_sha256": formal_source_hash, "world_published_by_cold": false,
		"journal_case": journal_case, "journal_rows": slot.control.fire_clock.journal.size(), "legacy_rows": legacy_rows}
	_finish()

## Re-merge the actual live journal by the older rule (same scale, same tactical
## shape, average widths within 1e-10). The live run must have produced at least
## one row split the older rule would merge, or there is no legacy case to test.
func _formal_legacy_journal() -> bool:
	var journal: Array = slot.control.fire_clock.journal
	var merged: Array = []
	for source: Dictionary in journal:
		var row := source.duplicate(true)
		if not merged.is_empty():
			var last: Dictionary = merged.back()
			var old_action := (float(last.action_end) - float(last.action_begin)) / int(last.steps)
			var delta := (float(row.action_end) - float(row.action_begin)) / int(row.steps)
			var old_tactical := float(last.tactical_seconds) / int(last.steps)
			var new_tactical := float(row.tactical_seconds) / int(row.steps)
			var uniform := (old_tactical == 0.0 and new_tactical == 0.0) \
				or (absf(old_tactical - old_action) < 0.0000000001 and absf(new_tactical - delta) < 0.0000000001)
			if uniform and float(last.scale) == float(row.scale) and absf(old_action - delta) < 0.0000000001 \
				and float(last.action_end) == float(row.action_begin) and int(last.last_sequence) + 1 == int(row.first_sequence):
				last.last_sequence = int(row.last_sequence)
				last.action_end = float(row.action_end)
				last.game_end = float(row.game_end)
				last.tactical_seconds = float(last.tactical_seconds) + float(row.tactical_seconds)
				last.steps = int(last.steps) + int(row.steps)
				continue
		merged.append(row)
	legacy_rows = {"exact": journal.size(), "legacy": merged.size()}
	if not _check(merged.size() < journal.size(), "the live journal holds rows the older 1e-10 rule would merge", legacy_rows): return false
	slot.control.fire_clock.journal = merged
	return true

func _finish(ok: bool = true, message: String = "") -> void:
	if finished: return
	finished = true
	failed = failed or not ok
	paused = false
	if is_instance_valid(lab): lab.free()
	var current: Variant = JSON.parse_string(FileAccess.get_file_as_string(Entry.LAST_WORLD)) if FileAccess.file_exists(Entry.LAST_WORLD) else null
	if current is Dictionary and current.get("world_id") == world_id:
		if last_world_exists:
			var previous := FileAccess.open(Entry.LAST_WORLD, FileAccess.WRITE)
			previous.store_buffer(last_world_bytes)
			previous.close()
		else: DirAccess.remove_absolute(ProjectSettings.globalize_path(Entry.LAST_WORLD))
	TerrainArmy.release_contact_source()
	var file := FileAccess.open(out.path_join("formal_receipt.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"checks": checks, "failed": failed, "result": formal_result,
			"scope": "actual_selected_slot_genesis_original_main_journal_retained_child_quiet_prefix_exact_tail_full_owner_equality", "message": message}, "\t"))
		file.close()
	print("REGION_COLD_FORMAL_ORIGINAL_", "FAIL" if failed else "PASS", ": ", JSON.stringify(formal_result), " ", message)
	quit(1 if failed else 0)
