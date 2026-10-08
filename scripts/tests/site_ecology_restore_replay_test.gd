extends "res://scripts/tests/site_ecology_replay_test.gd"
## ECO06/ECO12 use saved original Actors and the original shared-step consumers.

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	r2_output = "res://.godot-temp/site_ecology_restore_replay/run_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	_run.call_deferred()

func _restore_file(resident: Dictionary) -> Dictionary:
	var original := _r2_restore(resident.data)
	var data: TerrainData = original.terrain
	var key := ""
	var work_cell := Vector2i(-1, -1)
	var keys := data.resource_base.keys()
	keys.sort()
	for candidate: String in keys:
		var resource := SiteEnvironment.resource(data, candidate)
		var cells := SiteEnvironment.work_cells(data, candidate)
		if int(resource.kind) == SiteEnvironment.Kind.HERB and not bool(resource.cleared) and not cells.is_empty():
			key = candidate
			work_cell = cells[0]
			break
	assert(not key.is_empty(), "The original generated map requires one accessible plant source")
	var depot := data.cell_from_index(int(data.site.depot_cell))
	assert(original.character.place(depot, true))
	assert(SiteRuntime.deposit(data, data.site.manual.cargo, original.character.terrain_cell).ok)
	assert(original.character.place(work_cell, true))
	original.character.fatigue = 0.0
	var resource := SiteEnvironment.resource(data, key)
	if not bool(resource.discovered): assert(SiteRuntime.harvest(data, key, work_cell, data.site.manual.cargo, "survey").ok)
	for _batch: int in range(64):
		if bool(SiteEnvironment.resource(data, key).cleared): break
		var cleared := SiteRuntime.harvest(data, key, work_cell, data.site.manual.cargo, "clear")
		if not cleared.ok and cleared.code == "STORAGE_FULL":
			assert(original.character.place(depot, true))
			assert(SiteRuntime.deposit(data, data.site.manual.cargo, original.character.terrain_cell).ok)
			assert(original.character.place(work_cell, true))
			cleared = SiteRuntime.harvest(data, key, work_cell, data.site.manual.cargo, "clear")
		assert(cleared.ok, str(cleared))
	assert(bool(SiteEnvironment.resource(data, key).cleared))
	assert(SiteSettlement.set_ecology_modes(original, original.character.person_id, [key], "protected").ok)
	original.site_controller.source_key = key
	original.site_controller.manual_work("restore")
	assert(data.site.manual.action == "restore" and data.site.manual.target == key)
	var started := original.region_cold_actual_progress()
	var partial := original.replay_site_to(float(started.game_seconds) + 420.0)
	assert(partial.ok and partial.status == "COMPLETE", str(partial))
	assert(bool(SiteEnvironment.resource(data, key).cleared) and float(data.site.manual.progress) > 0.0 and float(data.site.manual.progress) < 60.0)
	var progress := float(data.site.manual.progress)
	var cargo := var_to_bytes(data.site.manual.cargo)
	var produced := int(data.site.total_produced)
	data.site = _capture(original)
	var path := r2_output.path_join("partial_restore.json")
	assert(SiteStore.save(data, path).ok)
	var loaded := SiteStore.load_site(path, Callable(), 1, true)
	assert(loaded.ok, str(loaded))
	assert(loaded.data.site.manual.action == "restore" and loaded.data.site.manual.target == key)
	assert(_ecology_near(float(loaded.data.site.manual.progress), progress))
	assert(bool(SiteEnvironment.resource(loaded.data, key).cleared) and int(SiteEnvironment.resource(loaded.data, key).next_recovery) == -1)
	assert(var_to_bytes(loaded.data.site.manual.cargo) == cargo and int(loaded.data.site.total_produced) == produced)
	original.free()
	return {"data": loaded.data, "key": key, "progress": progress, "cargo": cargo, "produced": produced, "sha256": FileAccess.get_sha256(path)}

func _resume_original_restoration(fixture: Dictionary) -> bool:
	var source: TerrainData = fixture.data
	var frozen := _r2_source_bytes(source)
	var normal := _r2_restore(source)
	var bounded := _r2_restore(source)
	var target := float(normal.region_cold_actual_progress().game_seconds) + 3600.0
	var pending := bounded.replay_site_to(target, 0, 1)
	assert(pending.ok and pending.status == "PENDING")
	var retained := _capture(bounded)
	assert(bounded.replay_site_to(target + 1.0, 0, 1).code == "BUSY")
	assert(_ecology_same_original(_capture(bounded), retained))
	while pending.ok and pending.status == "PENDING":
		assert(Time.get_ticks_msec() <= deadline)
		pending = bounded.replay_site_to(target, 0, 97)
	assert(pending.ok and pending.status == "COMPLETE", str(pending))
	var expected := normal.replay_site_to(target)
	assert(expected.ok and expected.status == "COMPLETE", str(expected))
	assert(_ecology_same_original(_capture(bounded), _capture(normal)))
	assert(_ecology_same_original(bounded.region_cold_actual_progress(), normal.region_cold_actual_progress()))
	assert(_ecology_same_original(_r2_actual_owner_graph(bounded), _r2_actual_owner_graph(normal)))
	var key := str(fixture.key)
	var resource := SiteEnvironment.resource(bounded.terrain, key)
	assert(not bool(resource.cleared) and int(resource.remaining) == 0 and int(resource.next_recovery) > SiteRuntime.now(bounded.terrain))
	assert(str(bounded.terrain.site.manual.target).is_empty() and str(resource.eco_mode) == "protected")
	assert(var_to_bytes(bounded.terrain.site.manual.cargo) == fixture.cargo and int(bounded.terrain.site.total_produced) == int(fixture.produced))
	var settled := _capture(bounded)
	var zero := bounded.replay_site_to(target, 0, 1)
	assert(zero.ok and zero.steps == 0)
	assert(_ecology_same_original(_capture(bounded), settled))
	assert(_r2_source_bytes(source) == frozen)
	normal.free()
	bounded.free()
	return true

func _pause_speed_and_combat(resident: Dictionary) -> bool:
	var source: TerrainData = resident.data
	var frozen := _r2_source_bytes(source)
	var first := _r2_restore(source)
	var second := _r2_restore(source)
	first.restore_only = false
	second.restore_only = false
	first.simulation_speed = 4.0
	second.simulation_speed = 4.0
	first.terrain.site.paused = true
	var retained := _capture(first)
	assert(first._advance_original_shared_step(first.EXCHANGE_ACTION_STEP).code == "PAUSED_SITE")
	assert(_ecology_same_original(_capture(first), retained))
	first.terrain.site.paused = false
	paused = true
	retained = _capture(first)
	assert(first._advance_original_shared_step(first.EXCHANGE_ACTION_STEP).code == "PAUSED_WORLD")
	assert(_ecology_same_original(_capture(first), retained))
	paused = false
	var key := str(resident.key)
	var initial := SiteEnvironment.resource(first.terrain, key)
	var deadline_minute := int(initial.next_recovery)
	var marked := false
	for index: int in range(10000):
		assert(Time.get_ticks_msec() <= deadline)
		if index == 10:
			SiteRuntime.mark_combat(first.terrain, SiteRuntime.COMBAT_GRACE)
			SiteRuntime.mark_combat(second.terrain, SiteRuntime.COMBAT_GRACE)
			assert(float(first.terrain.site.combat_left) > 0.0 and float(second.terrain.site.combat_left) > 0.0)
			marked = true
		var a := first._advance_original_shared_step(first.EXCHANGE_ACTION_STEP)
		var b := second._advance_original_shared_step(second.EXCHANGE_ACTION_STEP)
		assert(a.ok and a.completed and b.ok and b.completed, str([a, b]))
		if index == 0:
			assert(_ecology_near(float(a.game_seconds), float(a.action_seconds) * 60.0 * first.simulation_speed))
			assert(_ecology_near(float(b.game_seconds), float(b.action_seconds) * 60.0 * second.simulation_speed))
		if index == 10:
			assert(_ecology_near(float(a.game_seconds), float(a.action_seconds) * first.simulation_speed))
			assert(_ecology_near(float(b.game_seconds), float(b.action_seconds) * second.simulation_speed))
		if SiteRuntime.now(first.terrain) >= float(deadline_minute): break
	assert(marked and SiteRuntime.now(first.terrain) >= float(deadline_minute))
	assert(float(first.terrain.site.combat_left) == 0.0 and float(second.terrain.site.combat_left) == 0.0)
	assert(int(SiteEnvironment.resource(first.terrain, key).remaining) == 10, "The original due event fires once after pauses, speed and combat inputs")
	var quantity := int(SiteEnvironment.resource(first.terrain, key).remaining)
	assert(first._advance_original_shared_step(first.EXCHANGE_ACTION_STEP).ok)
	assert(second._advance_original_shared_step(second.EXCHANGE_ACTION_STEP).ok)
	assert(int(SiteEnvironment.resource(first.terrain, key).remaining) == quantity)
	assert(_ecology_same_original(_capture(first), _capture(second)))
	assert(_ecology_same_original(_r2_actual_owner_graph(first), _r2_actual_owner_graph(second)))
	assert(_r2_source_bytes(source) == frozen)
	first.free()
	second.free()
	return true

func _run() -> void:
	_started = true
	root.gui_embed_subwindows = true
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(r2_output)) == OK)
	var history := _history_file(false)
	var resident := _resident_file(history)
	var restoring := _restore_file(resident)
	assert(_resume_original_restoration(restoring))
	assert(_pause_speed_and_combat(resident))
	TerrainArmy.release_contact_source()
	_finished = true
	print("SITE_ECOLOGY_RESTORE_REPLAY_PASS original_partial_manual_file_roundtrip=true bounded_pending_resume_equal=true owner_graph_equal=true no_immediate_stock_cargo_or_repeated_completion=true actual_shared_pause_speed_combat_deterministic=true; no GPU, performance or all16ECO claim")
	quit(0)
