extends "res://scripts/tests/site_boarding_contract_test.gd"
## B2S3: player-side begin of the original 4.0 s boarding action. Commit is B2S4.
## Reuses the B0 lab fixture (two real ferries, one person aboard the first).
const B2Contract = preload("res://scripts/terrain_lab/site_boarding_link_contract.gd")

func _run() -> void:
	deadline = Time.get_ticks_msec() + 120000
	if not _must(DisplayServer.get_name() == "headless", "B2S3_CANONICAL_HEADLESS"): return
	lab = TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.site_controller.set_process(false)
	lab.site_controller._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for owner: TerrainArmy in lab.combat_armies: owner.set_process(false)
	if not _fixture() or not _cases_b2s3(): return
	print("SITE_BOARDING_B2S3_PASS: " + get_script().resource_path)
	await _cleanup(0)

func _no_link_b2s3() -> bool:
	var records: Dictionary = lab.site_controller.vehicles.records()
	for identity: String in [boat_id, enemy_boat]:
		if records[identity].naval.has("boarding_link"): return false
	return true

func _cases_b2s3() -> bool:
	var vehicles: Variant = lab.site_controller.vehicles
	var actions: Variant = lab.site_controller.person_actions
	var aboard: int = people[0]
	if not _must(str(vehicles.ship_person(aboard).row.get("embarked_vehicle_id", "")) == boat_id, "B2S3_PREMISE_EMBARKED"): return false
	# Refusals leave the original records and the job table untouched.
	var before_records: PackedByteArray = var_to_bytes(vehicles.records())
	var wrong_side: Dictionary = actions.begin_boarding_link(aboard, enemy_boat, boat_id, aboard)
	if not _must(not wrong_side.ok and wrong_side.code == "NO_TARGET", "B2S3_REFUSE_NOT_ABOARD: " + str(wrong_side)): return false
	var same_hull: Dictionary = actions.begin_boarding_link(aboard, boat_id, boat_id, aboard)
	if not _must(not same_hull.ok and same_hull.code == "NO_TARGET", "B2S3_REFUSE_SAME_HULL: " + str(same_hull)): return false
	var unauthorised: Dictionary = actions.begin_boarding_link(aboard, boat_id, enemy_boat, people[1])
	if not _must(not unauthorised.ok, "B2S3_REFUSE_UNAUTHORISED: " + str(unauthorised)): return false
	if not _must(var_to_bytes(vehicles.records()) == before_records, "B2S3_REFUSALS_LEAVE_RECORDS"): return false
	if not _must(actions._jobs.is_empty(), "B2S3_REFUSALS_LEAVE_NO_JOB"): return false

	# An already unconscious living original cannot create a new paid job.
	var b2_ko_row: int = team.index_for_identity(aboard)
	var b2_ko_before: float = float(team.combat_hot_get(b2_ko_row, &"ko", 0.0))
	team.combat_hot_set(b2_ko_row, &"ko", 1.0)
	var b2_ko_refused: Dictionary = actions.begin_boarding_link(aboard, boat_id, enemy_boat, aboard)
	team.combat_hot_set(b2_ko_row, &"ko", b2_ko_before)
	if not _must(not b2_ko_refused.ok and b2_ko_refused.code == "BUSY" and actions._jobs.is_empty(), "B2_KO_BEGIN_REFUSED_WITHOUT_JOB"): return false
	if not _must(var_to_bytes(vehicles.records()) == before_records, "B2_KO_REFUSAL_PRESERVES_HULLS"): return false

	# The real begin: one original job with the B0 action duration.
	var began: Dictionary = actions.begin_boarding_link(aboard, boat_id, enemy_boat, aboard)
	if not _must(began.ok and float(began.seconds) == B2Contract.LINK_ACTION_SECONDS, "B2S3_BEGIN: " + str(began)): return false
	var job: Dictionary = actions._jobs.get(str(aboard), {})
	if not _must(str(job.get("kind", "")) == "boarding_cross" and int(job.executor_id) == aboard and float(job.duration) == B2Contract.LINK_ACTION_SECONDS, "B2S3_JOB_SHAPE"): return false

	# While open: the same person is busy, and both save paths refuse.
	var again: Dictionary = actions.begin_boarding_link(aboard, boat_id, enemy_boat, aboard)
	if not _must(not again.ok and again.code == "BUSY", "B2S3_SECOND_BEGIN_BUSY: " + str(again)): return false
	if not _must(not vehicles.boarding_save_guard().ok, "B2S3_VEHICLE_SAVE_BUSY_WHILE_OPEN"): return false
	var capture: Dictionary = lab.site_controller._capture_for_save()
	if not _must(not capture.ok, "B2S3_CAPTURE_BUSY_WHILE_OPEN"): return false

	# The action clock advances the original job; the finished action holds, unwritten.
	actions.advance_ship_jobs(2.0)
	job = actions._jobs.get(str(aboard), {})
	if not _must(not job.is_empty() and is_equal_approx(float(job.elapsed), 2.0) and str(job.paused) == "", "B2S3_ADVANCE_HALF: " + str(job)): return false
	actions.advance_ship_jobs(2.5)
	job = actions._jobs.get(str(aboard), {})
	if not _must(not job.is_empty() and float(job.elapsed) == B2Contract.LINK_ACTION_SECONDS and str(job.paused) == "AWAIT_COMMIT", "B2S3_ADVANCE_FINISHES_AND_HOLDS"): return false
	if not _must(_no_link_b2s3(), "B2S3_FINISHED_ACTION_WRITES_NO_LINK"): return false
	if not _must(not vehicles.boarding_save_guard().ok, "B2S3_HOLD_STAYS_BUSY"): return false

	# Cancel releases the job and restores the save gate, with no link written.
	var cancelled: Dictionary = actions.cancel(aboard)
	if not _must(cancelled.ok and actions._jobs.is_empty(), "B2S3_CANCEL_CLEARS_JOB: " + str(cancelled)): return false
	if not _must(vehicles.boarding_save_guard().ok and _no_link_b2s3(), "B2S3_CANCEL_RESTORES_SAVE"): return false

	# A changed executor during the action interrupts it without committing.
	var restarted: Dictionary = actions.begin_boarding_link(aboard, boat_id, enemy_boat, aboard)
	if not _must(restarted.ok, "B2S3_RESTART: " + str(restarted)): return false
	actions._jobs[str(aboard)].executor_hit = -999
	actions.advance_ship_jobs(0.5)
	if not _must(actions._jobs.is_empty(), "B2S3_INTERRUPT_DROPS_JOB"): return false
	if not _must(not actions._results.is_empty() and str(actions._results.back().code) == "INTERRUPTED", "B2S3_INTERRUPT_CODE"): return false
	return _must(_no_link_b2s3(), "B2S3_INTERRUPT_WRITES_NO_LINK")
