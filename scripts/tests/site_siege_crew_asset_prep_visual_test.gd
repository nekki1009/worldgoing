extends "res://scripts/tests/site_siege_work_original_gpu_test.gd"
## Real non-UI dispatch, with an explicitly unpublished original equipment fixture.
var assignment_results: Array[Dictionary] = []

func _report() -> void:
	if folder.is_empty(): return
	var file := FileAccess.open(folder.path_join("report.json"), FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({"status": "FAIL" if visual_failed else ("PASS" if visual_finished else "INCOMPLETE"),
		"case": "crew_asset_prep", "mode": work_mode, "checks": checks, "check_count": visual_checks,
		"captures": captures, "crew_ids": crew_ids, "assignment_results": assignment_results,
		"shared_steps": shared_steps, "manual_visual_review": "PENDING",
		"scope": "Actual original NPC crew, non-UI assignment, real equipment publication/work atlas admission, pending deduplication, authorization and slot revalidation, ready original stations and GPU pixels. Grid cold-publication fixture or native original-owner fixture selected explicitly. No combat, FPS, save/load or full-release proof."}, "\t"))
	file.close()

func _assignment_finished(request: Dictionary, result: Dictionary) -> void:
	assignment_results.append({"request": request, "result": result})

func _run() -> void:
	if not _preflight() or not _scene() or not _paid_vehicle("ram"): return
	var vehicle: Dictionary = lab.terrain.site.vehicles[key]
	var positions: Array[Vector2i] = [anchor - Vector2i(6, 0), ui.vehicles.crew_cell(vehicle, "0"), ui.vehicles.crew_cell(vehicle, "1")]
	if not _army(positions): return
	commander_id = original_ids[0]
	crew_ids = [original_ids[1], original_ids[2]]
	work_id = crew_ids[0]
	if work_mode == "native_soldier":
		if not _expect(OS.get_cmdline_user_args().has("--crowd"), "explicit native fixture"): return
		var parsed: Dictionary = lab._trial_side_settings({"friendly_count": 1, "friendly_training": 0, "friendly_female_percent": 0, "friendly_attack": false, "friendly_ai_enabled": false}, "friendly")
		if not _expect(parsed.ok, "native fixture settings admitted", parsed): return
		var settings: Dictionary = parsed.side
		settings.faction = 2
		var entered: Dictionary = lab.crowd_site.deploy([settings], [[Vector2i(65, 65)]])
		if not _expect(entered.ok and lab.crowd_site.active and lab.crowd_site.contains_person(work_id), "native owner retains exact original crew IDs", entered): return
		var controlled: Dictionary = ui._control_family_person(null, commander_id)
		if not _expect(controlled.ok, "original native commander controlled before shared steps", controlled): return
	else:
		if not _expect(OS.get_cmdline_user_args().has("--grid"), "explicit grid fixture"): return
		# Cold publication fixture only: retain real bodies/items and let the command publish them.
		for identity: int in crew_ids: ui._equipment_appearances.erase(identity)
		if not _expect(ui.person_appearance(crew_ids[0]).is_empty(), "no prepublished crew appearance"): return
	if not _expect(WorkAppend._directories.is_empty(), "no preadmitted work atlas in this process"): return
	ui.vehicles.crew_assignment_finished.connect(_assignment_finished)
	var denied: Dictionary = ui.vehicles.assign_crew(key, crew_ids[0], "0", -1, true)
	if not _expect(not denied.ok and denied.code == "NO_AUTHORITY" and ui.vehicles._crew_asset_queue.is_empty(), "invalid authority never queues capture", denied): return
	var pending: Dictionary = ui.vehicles.assign_crew(key, crew_ids[0], "0", commander_id, true)
	if not _expect(not pending.ok and pending.code == "SIEGE_ASSET_PENDING" and pending.pending and vehicle.crew_slots.is_empty(), "non-UI command waits without premature assignment or MISSING_ASSET", pending): return
	ui.vehicles.assign_crew(key, crew_ids[0], "0", commander_id, true)
	if not _expect(ui.vehicles._crew_asset_queue.size() == 1, "same pending command deduplicates"): return
	var competing: Dictionary = ui.vehicles.assign_crew(key, crew_ids[1], "0", commander_id, true)
	if not _expect(competing.get("pending", false), "second legal command waits for common preparation", competing): return
	while assignment_results.size() < 2 and not visual_failed:
		await process_frame
	if visual_failed: return
	if not _expect(assignment_results[0].result.ok and not assignment_results[1].result.ok and assignment_results[1].result.code == "BUSY", "completion revalidates slot conflict instead of overwriting", assignment_results): return
	if not _expect(int(vehicle.crew_slots["0"]) == crew_ids[0] and not ui.person_appearance(crew_ids[0]).is_empty() and WorkAppend.ready(ui.person_appearance(crew_ids[0])), "queue publishes real equipment and admits work atlas before commit"): return
	var assigned: Dictionary = ui.vehicles.assign_crew(key, crew_ids[1], "1", commander_id, true)
	if not _expect(assigned.ok, "prepared second worker assigns synchronously to free slot", assigned): return
	if not await _until_work(func() -> bool: return ui.vehicles.crew_ready(vehicle), 30.0, "actual original crew reach stations"): return
	_focus()
	if not await _capture("crew_asset_prep", {"assignment_results": assignment_results}): return
	visual_finished = true
	_report()
	lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_CREW_ASSET_PREP_VISUAL_PASS")
	quit(0)
