extends SceneTree
## Local T2 APIs on real original Actor/Family owners. This is not the Region
## fixed-target replay, world-clock, full-pool collector or persistence close.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")

class Fixture extends RefCounted:
	var terrain := TerrainData.new()
	var character := TerrainTestCharacter.new()
	var npc := TerrainTestNPC.new()
	var actions := SitePersonActions.new()
	var site_controller := SiteController.new()
	var combat_armies: Array[TerrainArmy] = []
	var crowd_site: Variant = null
	var restore_only := false
	var threatened := false
	var old_bodies: Array[Node] = []

	func _init() -> void:
		terrain.allocate(Vector2i(12, 12))
		terrain.flags.fill(TerrainData.Flag.WALKABLE)
		terrain.site = {"id": "f07-cold-original-actors", "minute": 0, "phase": 0.0, "paused": false,
			"controlled_person_id": 1, "combat_left": 0.0, "depot_cell": terrain.index(Vector2i(5, 4)),
			"capacity": 800, "inventory": {"wood": 80, "iron": 20, "fiber": 40, "cloth": 8, "tools": 1},
			"manual": {"target": "", "cargo": {}}, "worker": {"target": "", "cargo": {}}}
		assert(Runtime.initialize_item_storage(terrain.site).ok)
		character.person_id = 1
		npc.person_id = 2
		character.data = terrain
		npc.data = terrain
		character.terrain_cell = Vector2i(4, 4)
		npc.terrain_cell = Vector2i(5, 5)
		character.item_state = Runtime.new_item_state("person:1")
		npc.item_state = Runtime.new_item_state("person:2")
		character.ammo_inventory = terrain.site.manual.cargo
		npc.ammo_inventory = terrain.site.worker.cargo
		site_controller.family_continuity.init(self)
		actions.init(self)
		var refs: Array = []
		for identity: int in [1, 2]:
			refs.append({"site_id": terrain.site.id, "person_id": identity, "path": "", "label": "Original #%d" % identity, "age_years": -1})
		assert(site_controller.family_continuity.register_members(refs, true, 1).ok)
		assert(site_controller.family_continuity.appoint_head(1, 1).ok)

	func controlled_person_id() -> int:
		return 1

	func _combat_target(identity: int) -> Dictionary:
		for actor: TerrainTestCharacter in [character, npc]:
			if actor.person_id == identity: return {"owner": actor, "unit": -1, "cell": actor.terrain_cell, "hp": actor.hp}
		return {}

	func _original_person_target(identity: int, _with_bodies: bool = false) -> Dictionary:
		return _combat_target(identity)

	func _fatigue_threat(_cell: Vector2i, _faction: int, _owner: Variant, _unit: int, _candidates: Dictionary) -> bool:
		return threatened

	func prepare(identity: int = 2) -> void:
		assert(actions.prepare_technology(1, identity).ok)
		assert(actions.request_technology_consent(1, identity).ok)
		assert(actions.grant_technology_budget(1, {"wood": 12, "fiber": 6}).ok)

	func step(seconds: float) -> Dictionary:
		var plan := Fatigue.plan_work_interval(actions.work_requests(seconds), seconds)
		assert(plan.ok, str(plan))
		for group: Dictionary in plan.pools:
			Fatigue.write(group.body, "fatigue", float(group.fatigue))
			Fatigue.write(group.body, "fatigue_rest", float(group.fatigue_rest))
		var consumed := actions.advance(seconds, {"jobs": plan.jobs.get("person_actions", {})})
		return {"plan": plan, "consumed": consumed}

	func project() -> Dictionary:
		return Technology.active_project(terrain.site.family.technology)

	func snapshot() -> PackedByteArray:
		return var_to_bytes([terrain.site, character.technology, npc.technology, npc.fatigue, npc.fatigue_rest, npc.work_resting])

	func bow_count() -> int:
		var count := 0
		for record: Dictionary in terrain.site.item_records.values():
			if str(record.definition) == "weapon:bow_01": count += 1
		return count

	func close() -> void:
		actions.cancel(1)
		actions.cancel(2)
		site_controller.family_continuity.lab = null
		actions.lab = null
		site_controller.free()
		character.free()
		npc.free()
		for actor: Node in old_bodies: actor.free()

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SITE_F07_COLD_JOBS_FAIL: " + message)

func near(value: float, expected: float, message: String) -> void:
	check(is_finite(value) and absf(value - expected) <= 0.000001, message)

func run() -> void:
	check_restore_and_completion()
	check_rest_checkpoint_and_resume()
	check_restore_source_guards()
	check_prepared_clock_guards()
	check_cold_admission_boundaries()
	print("SITE_F07_COLD_JOBS_%s: checks=%d failures=%d; local original NPC T2 APIs only; Region replay/L01 close remains separate" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)

func check_restore_and_completion() -> void:
	var f := Fixture.new()
	f.prepare()
	check(f.actions.begin_technology_trial(1, 2).ok, "The original NPC trial starts through the formal command")
	check(not f.actions.export_cold_technology_jobs().ok and not f.actions.save_guard().ok, "Loaded/manual in-flight saves retain BUSY")
	f.restore_only = true
	var stepped := f.step(120.0)
	near(float(f.actions.job_for(2).elapsed), 60.0, "120 cold actual seconds produce 60 research seconds")
	near(float(f.npc.fatigue), 120.0 * Fatigue.WORK_RATE, "Cold NPC effort is not halved")
	near(float(stepped.consumed.handled_seconds[2]), 120.0, "Original actor is handled exactly for its actual effort")
	check(f.project().budget.spent == {"wood": 0, "fiber": 0} and f.bow_count() == 0, "A partial cold job pays and produces nothing")
	var captured := f.actions.export_cold_technology_jobs()
	check(captured.ok and captured.state.jobs.size() == 1, "Mid-work cold checkpoint contains the one original NPC job")
	if not captured.ok: f.close(); return
	var raw: Dictionary = JSON.parse_string(JSON.stringify(captured.state))
	check(f.actions.cancel(2).ok, "Fixture retires the transient job before restore staging")
	var before := f.snapshot()
	var prepared := f.actions.prepare_restore_cold_technology_jobs(raw)
	check(prepared.ok and f.actions.can_publish_restore_cold_technology_jobs(prepared), "JSON integer checkpoint prepares against real original owners")
	check(f.snapshot() == before and not f.actions.is_busy(2), "Preparation neither charges effort nor publishes a job")
	if not prepared.ok: f.close(); return
	check(is_same(prepared.jobs["2"].technology_executor_body, f.npc) and is_same(prepared.jobs["2"].executor_holder, f.npc.item_state), "Prepared work uses the original body and holder")
	check(f.actions.publish_restore_cold_technology_jobs(prepared).ok and f.snapshot() == before, "Publish restores only the original job without costs or time")
	check(not f.actions.publish_restore_cold_technology_jobs(prepared).ok, "The same restore candidate cannot publish twice")
	near(float(f.actions.job_for(2).elapsed), 60.0, "Restore retains exactly the partial effective progress")
	f.step(121.0)
	var completed := f.actions.job_for(2)
	near(float(completed.elapsed), 120.0, "Cold completion ends at the genuine 240-second actual boundary")
	near(float(f.npc.fatigue), 240.0 * Fatigue.WORK_RATE, "Overlong frame adds no effort after completion")
	check(f.bow_count() == 0 and not f.actions.export_cold_technology_jobs().ok, "Pending completion must settle after contacts before checkpoint")
	var results := f.actions.settle_after_contacts()
	check(results.size() == 1 and results[0].ok and f.bow_count() == 1, "One original paid bow settles once")
	check(f.project().receipts.size() == 1 and f.project().budget.spent == {"wood": 4, "fiber": 2}, "Original receipt and finite budget spend share the real item commit")
	check(f.terrain.site.inventory.wood == 76 and f.terrain.site.inventory.fiber == 38, "Only one trial's real materials were consumed")
	before = f.snapshot()
	check(not f.actions._commit_technology_trial(completed).ok and f.snapshot() == before, "Duplicate completion cannot spend or publish another bow")
	check(not f.actions.prepare_restore_cold_technology_jobs(raw).ok, "A committed attempt cannot restore its old partial clock")
	check(f.actions.begin_technology_trial(1, 2).ok, "Next stage can start with the original project and NPC")
	near(float(f.actions.job_for(2).elapsed), 0.0, "The next accepted stage starts at zero progress")
	f.close()

func check_rest_checkpoint_and_resume() -> void:
	var f := Fixture.new()
	f.prepare()
	f.restore_only = true
	f.npc.fatigue = 79.9
	check(f.actions.begin_technology_trial(1, 2).ok, "Near-REST NPC work starts")
	var stepped := f.step(100.0)
	near(float(stepped.consumed.handled_seconds[2]), 36.0, "Only the actual interval to original 80 is charged")
	near(float(f.actions.job_for(2).elapsed), 0.5 * Fatigue.work_seconds(79.9, 36.0), "REST preserves the genuine cold partial output")
	check(f.npc.work_resting and str(f.actions.job_for(2).paused) == "REST", "NPC work remains occupied at its original REST boundary")
	var captured := f.actions.export_cold_technology_jobs()
	check(captured.ok and str(captured.state.jobs[0].paused) == "REST", "A fixed endpoint during REST admits a partial cold checkpoint")
	if not captured.ok: f.close(); return
	f.actions.cancel(2)
	var prepared := f.actions.prepare_restore_cold_technology_jobs(captured.state)
	check(prepared.ok and f.actions.publish_restore_cold_technology_jobs(prepared).ok, "REST checkpoint restores without dropping work")
	var elapsed := float(f.actions.job_for(2).elapsed)
	f.step(300.0)
	near(float(f.actions.job_for(2).elapsed), elapsed, "The pure work adapter gives no productive work during REST")
	near(float(f.npc.fatigue), 80.0, "The planner itself grants no idle recovery")
	# Simulate only the original owner's legitimate recovery, keeping the
	# original work latch true so the API must acknowledge resumed work.
	f.npc.fatigue = 50.0
	f.npc.fatigue_rest = 30.0
	f.step(1.0)
	check(not f.npc.work_resting, "Positive resumed work clears the original person's REST latch")
	var resumed := float(f.actions.job_for(2).elapsed)
	f.step(100.0)
	check(float(f.actions.job_for(2).elapsed) > resumed and str(f.actions.job_for(2).paused).is_empty(), "A split next interval resumes toward 80 rather than re-stopping above 50")
	check(f.project().budget.spent == {"wood": 0, "fiber": 0} and f.bow_count() == 0, "REST/resume does not fabricate a success or free item")
	f.close()

func check_restore_source_guards() -> void:
	for mutation: String in ["body", "holder", "holder_version", "cargo", "depot", "stock", "site", "family_epoch", "executor_cell", "executor_hit"]:
		var f := Fixture.new()
		f.prepare()
		f.restore_only = true
		assert(f.actions.begin_technology_trial(1, 2).ok)
		f.step(40.0)
		var captured := f.actions.export_cold_technology_jobs()
		assert(captured.ok)
		f.actions.cancel(2)
		var prepared := f.actions.prepare_restore_cold_technology_jobs(captured.state)
		assert(prepared.ok)
		match mutation:
			"body":
				var old := f.npc
				var replacement := TerrainTestNPC.new()
				replacement.person_id = old.person_id
				replacement.data = f.terrain
				replacement.terrain_cell = old.terrain_cell
				replacement.item_state = old.item_state
				replacement.ammo_inventory = old.ammo_inventory
				f.old_bodies.append(old)
				f.npc = replacement
			"holder": f.npc.item_state = f.npc.item_state.duplicate(true)
			"holder_version": f.npc.item_state.version = int(f.npc.item_state.version) + 1
			"cargo": f.terrain.site.worker.cargo = f.terrain.site.worker.cargo.duplicate()
			"depot": f.terrain.site.depot_items = f.terrain.site.depot_items.duplicate(true)
			"stock": f.terrain.site.inventory = f.terrain.site.inventory.duplicate()
			"site": f.terrain.site = f.terrain.site.duplicate(true)
			"family_epoch": f.terrain.site.family.technology.epoch = int(f.terrain.site.family.technology.epoch) + 1
			"executor_cell": f.npc.terrain_cell = Vector2i(5, 6)
			"executor_hit": f.npc._received_effective_hit += 1
		var before := f.snapshot()
		check(not f.actions.can_publish_restore_cold_technology_jobs(prepared), "Original restore source changed: " + mutation)
		check(not f.actions.publish_restore_cold_technology_jobs(prepared).ok and f.snapshot() == before and not f.actions.is_busy(2), "Stale restore is atomic and cannot advance or occupy: " + mutation)
		f.close()

func check_prepared_clock_guards() -> void:
	for mutation: String in ["progress", "complete", "negative", "nonfinite", "duration", "paused"]:
		var f := Fixture.new()
		f.prepare()
		f.restore_only = true
		assert(f.actions.begin_technology_trial(1, 2).ok)
		f.step(20.0)
		var captured := f.actions.export_cold_technology_jobs()
		assert(captured.ok)
		f.actions.cancel(2)
		var prepared := f.actions.prepare_restore_cold_technology_jobs(captured.state)
		assert(prepared.ok)
		match mutation:
			"progress": prepared.jobs["2"].elapsed = 11.0
			"complete": prepared.jobs["2"].elapsed = 120.0
			"negative": prepared.jobs["2"].elapsed = -1.0
			"nonfinite": prepared.jobs["2"].elapsed = NAN
			"duration": prepared.jobs["2"].duration = 240.0
			"paused": prepared.jobs["2"].paused = "CLOCK_NOT_READY"
		var before := f.snapshot()
		check(not f.actions.can_publish_restore_cold_technology_jobs(prepared), "Publish rechecks the prepared original clock: " + mutation)
		check(not f.actions.publish_restore_cold_technology_jobs(prepared).ok and f.snapshot() == before and not f.actions.is_busy(2), "Invalid prepared clock cannot publish time or costs: " + mutation)
		f.close()

func check_cold_admission_boundaries() -> void:
	var f := Fixture.new()
	f.prepare()
	f.restore_only = true
	assert(f.actions.begin_technology_trial(1, 2).ok)
	f.step(20.0)
	var captured := f.actions.export_cold_technology_jobs()
	assert(captured.ok)
	f.actions.cancel(2)
	# A canceled partial clock cannot be revived after a newer job accepted
	# even though the original body, holder, budget and project are unchanged.
	assert(f.actions.begin_technology_trial(1, 2).ok)
	f.actions.cancel(2)
	check(not f.actions.prepare_restore_cold_technology_jobs(captured.state).ok, "Only next_attempt-1 may restore; canceled earlier clock is stale")
	var current = captured.state.duplicate(true)
	current.jobs[0].technology_attempt = int(f.project().next_attempt) - 1
	for field: String in ["elapsed", "duration", "recipe", "executor_version", "technology_epoch", "technology_family_id", "technology_purpose", "paused"]:
		var bad = current.duplicate(true)
		match field:
			"elapsed": bad.jobs[0].elapsed = 120.0
			"duration": bad.jobs[0].duration = 240.0
			"recipe": bad.jobs[0].recipe = "arrow"
			"executor_version": bad.jobs[0].executor_version = int(bad.jobs[0].executor_version) + 1
			"technology_epoch": bad.jobs[0].technology_epoch = int(bad.jobs[0].technology_epoch) + 1
			"technology_family_id": bad.jobs[0].technology_family_id = "ffffffffffffffffffffffffffffffff"
			"technology_purpose": bad.jobs[0].technology_purpose = "F07:other"
			"paused": bad.jobs[0].paused = "CLOCK_NOT_READY"
		var before := f.snapshot()
		check(not f.actions.prepare_restore_cold_technology_jobs(bad).ok and f.snapshot() == before and not f.actions.is_busy(2), "Malformed or stale cold row rejects atomically: " + field)
	check(f.actions.begin_ranged_craft(2, "bow").ok and not f.actions.export_cold_technology_jobs().ok, "Ordinary handcraft remains outside the cold research checkpoint exception")
	f.actions.cancel(2)
	f.close()
	var player := Fixture.new()
	player.prepare(1)
	player.restore_only = true
	assert(player.actions.begin_technology_trial(1, 1).ok)
	check(float(player.actions.work_requests(120.0)[0].progress_multiplier) == 1.0, "A controlled player's work is never granted the cold NPC multiplier")
	check(not player.actions.export_cold_technology_jobs().ok, "Controlled in-flight research stays outside cold admission")
	player.close()
