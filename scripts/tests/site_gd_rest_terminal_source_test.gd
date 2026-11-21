extends "res://scripts/tests/site_building_ui_test.gd"
## Canonical visual, internal 180 / external 210.
## Actual registered original Lab/Actor/Controller/PA and ordinary NPC craft.
## Finite stock and an original-valid fatigue checkpoint are explicit starting
## backgrounds. All job work below uses the actual Lab ACTION_STEP caller.
## The final capture is a pure source-component check, not a mesh/contact,
## Native, World birth, public Scope or full40 acceptance claim.

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	_run.call_deferred()

func _run() -> void:
	var data: TerrainData = _building_fixture()
	var lab: TerrainLab = _building_lab(data)
	data.site.inventory.clear()
	data.site.inventory.merge({"wood": 1, "iron": 1, "tools": 1}, true)
	var identity: int = int(lab.npc.person_id)
	var saved: Dictionary = lab.npc.capture_state()
	saved.fatigue = 79.805
	saved.fatigue_rest = 0.0
	saved.work_resting = false
	assert(TerrainTestCharacter.valid_state(saved, data))
	lab.npc.restore_state(saved)
	var actions: SitePersonActions = lab.site_controller.person_actions
	assert(actions.begin_ranged_craft(identity, "arrow").ok)
	var points := 0
	while not PersonFatigue.needs_work_rest(lab.npc.fatigue, lab.npc.work_resting) and points < 500:
		assert(Time.get_ticks_msec() < deadline)
		var point: Dictionary = lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		assert(point.ok and float(point.get("game_seconds", 0.0)) > 0.0)
		points += 1
	var job: Dictionary = actions.job_for(identity)
	assert(not job.is_empty() and PersonFatigue.needs_work_rest(lab.npc.fatigue, lab.npc.work_resting))
	var remaining: float = float(job.duration) - float(job.elapsed)
	assert(remaining > 0.0 and remaining < 5.0)
	var requests: Array[Dictionary] = actions.work_requests(5.0)
	assert(requests.size() == 1 and requests[0].paused == "REST")
	var before: PackedByteArray = var_to_bytes(data.site)
	var elapsed_before: float = float(job.elapsed)
	var fatigue_before: float = lab.npc.fatigue
	var captured: Dictionary = actions.prepare_gd_contact_job_prefix(requests, 5.0)
	assert(captured.ok, "Zero-effort REST cannot require a future material endpoint or reject another legal provider")
	assert(var_to_bytes(data.site) == before and float(job.elapsed) == elapsed_before and lab.npc.fatigue == fatigue_before)
	actions.finish_gd_contact_job_prefix()
	assert(actions.cancel(identity).ok)
	assert(data.site.inventory == {"wood": 1, "iron": 1, "tools": 1}, "Original unpaid near-terminal craft has zero material/output cost")

	# A second authentic source component reaches the exact original REST/work
	# completion boundary through the real Fatigue integral and PA.advance.
	# Completion is intentionally unsettled. No fixture writes job.elapsed,
	# duration, pause, holder versions, or a fabricated contact/World clock.
	var rate: float = PersonFatigue.effort_rate(lab.npc)
	assert(rate > 0.0)
	var low := 79.0
	var high := PersonFatigue.WORK_REST_AT
	var goal: float = float(Runtime.RANGED_RECIPES.arrow.duration) + 2.0 * PersonFatigue.WORK_PLAN_EPS
	for iteration: int in 64:
		var middle: float = (low + high) * 0.5
		var until_rest: float = (PersonFatigue.WORK_REST_AT - middle) / rate
		if PersonFatigue.work_seconds(middle, until_rest, rate) >= goal: low = middle
		else: high = middle
	saved = lab.npc.capture_state()
	saved.fatigue = low
	saved.fatigue_rest = 0.0
	saved.work_resting = false
	assert(TerrainTestCharacter.valid_state(saved, data))
	lab.npc.restore_state(saved)
	assert(actions.begin_ranged_craft(identity, "arrow").ok)
	var until_rest: float = (PersonFatigue.WORK_REST_AT - PersonFatigue.read(lab.npc)) / PersonFatigue.effort_rate(lab.npc)
	actions.advance(until_rest)
	job = actions.job_for(identity)
	assert(not job.is_empty() and float(job.elapsed) == float(job.duration))
	assert(PersonFatigue.needs_work_rest(lab.npc.fatigue, lab.npc.work_resting))
	requests = actions.work_requests(0.5)
	assert(requests.size() == 1 and requests[0].paused == "REST" and float(requests[0].remaining) == 0.0)
	before = var_to_bytes(data.site)
	elapsed_before = float(job.elapsed)
	fatigue_before = lab.npc.fatigue
	captured = actions.prepare_gd_contact_job_prefix(requests, 0.5)
	assert(captured.ok, "Already productive-complete REST retains the genuine source candidate before a zero endpoint")
	var source: Dictionary = captured.prepared.held[str(identity)].ranged_source
	assert(Runtime.validate_prepared_ranged_source(source) and not Runtime.validate_prepared_ranged_craft(source), "A prospective source is never a product/receipt publisher")
	assert(var_to_bytes(data.site) == before and float(job.elapsed) == elapsed_before and lab.npc.fatigue == fatigue_before)
	var version: int = int(data.site.depot_items.version)
	actions.finish_gd_contact_job_prefix()
	var results: Array[Dictionary] = actions.settle_after_contacts()
	assert(results.size() == 1 and results[0].ok)
	assert(data.site.inventory == {"tools": 1, "arrow": 10} and int(data.site.depot_items.version) == version + 1)
	assert(lab.npc.fatigue == fatigue_before and actions.job_for(identity).is_empty())
	before = var_to_bytes(data.site)
	assert(actions.settle_after_contacts().is_empty() and var_to_bytes(data.site) == before)
	lab.free()
	print("GD_CONTACT_REST_TERMINAL_SOURCE_PASS original Lab work/80 checkpoint, SAME job/request REST capture, no elapsed/fatigue/material/output mutation; CONTACT_SOURCE_COMPONENT_ONLY; ALREADY_DUE_REST_TRUE_SOURCE_ONCE_ENDPOINT")
	quit(0)
