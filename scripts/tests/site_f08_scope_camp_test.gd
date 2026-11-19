extends "res://scripts/tests/site_f07_cold_jobs_test.gd"
## Original two Actors, genuine Family registry/head and original camp ItemSeq.
## F07 archive is an explicit prerequisite fixture, never earned F08 evidence.
## Original Fatigue planner and each real body apply once. NOT_RUN; excludes
## complete TerrainLab/Region replay/Native/visual/full40 proof.
const F08Catalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")
var f08_deadline := 0
var f08_project_id := 0

func _f08_fixture() -> Fixture:
	var f := Fixture.new()
	var family: Dictionary = f.actions._technology_candidate()
	family.technology = Technology.empty_scope_record(str(f.terrain.site.id))
	family.technology.known = ["F07"]
	f.terrain.site.family = family
	check(F08Catalog.get_node("F08").enabled, "Only isolated guarded F08 candidate may run this positive fixture")
	check(f.actions.prepare_scope_technology(1, 2, "F08").ok, "Actual head prepares the unlearned original NPC's real F08 project")
	check(f.actions.grant_scope_technology_budget(1, "family", str(family.family_id), {"wood": 12, "iron": 6, "fiber": 3}).ok, "Real camp grants only three actual full crossbow inputs")
	check(f.actions.request_scope_technology_consent(1, "family", str(family.family_id), 2).ok, "Independent real NPC needs no fabricated team consent")
	return f

func _f08_begin(f: Fixture) -> void:
	check(f.actions.begin_scope_technology_phase(1, "family", str(f.terrain.site.family.family_id), "crossbow", "ranged:2").ok, "Public Scope phase binds this one original crossbow job")
	near(float(f.actions.job_for(2).duration), 180.0, "Unlearned F08 research preserves original 180-second duration")

func _f08_finish_effort(f: Fixture) -> void:
	var intervals := 0
	while float(f.actions.job_for(2).get("elapsed", 0.0)) < 180.0 and intervals < 200:
		check(Time.get_ticks_msec() < f08_deadline, "F08 fixture stays within its internal90second deadline")
		if Time.get_ticks_msec() >= f08_deadline: break
		f.step(30.0)
		intervals += 1
	check(intervals < 200 and is_equal_approx(float(f.actions.job_for(2).elapsed), 180.0), "Bounded original work/REST planner reaches the true endpoint")

func _f08_item_count(f: Fixture) -> int:
	var count := 0
	for item: Dictionary in f.terrain.site.item_records.values():
		if item.definition == "weapon:crossbow_01": count += 1
	return count

func _three_true_crossbows() -> void:
	var f := _f08_fixture()
	f08_project_id = int(f.terrain.site.family.technology.get("active", 0))
	var original_stock: Dictionary = f.terrain.site.inventory.duplicate()
	for index: int in 3:
		_f08_begin(f)
		_f08_finish_effort(f)
		var job: Dictionary = f.actions._jobs["2"]
		if index == 2:
			var capacity := int(f.terrain.site.capacity)
			f.terrain.site.capacity = 0
			var before := f.snapshot()
			check(not f.actions._commit_scope_ranged_craft(job).ok and f.snapshot() == before, "Failed third actual output cannot debit materials or award a third phase/knowledge")
			check(not Technology.scope_known(f.terrain.site.family.technology, "F08") and not Technology.learned(f.npc.technology, "F08"), "Two actual results are insufficient for either F08 owner")
			f.terrain.site.capacity = capacity
		var completed: Array = f.actions.settle_after_contacts()
		check(completed.size() == 1 and completed[0].ok and _f08_item_count(f) == index + 1, "One actual unique original crossbow and Scope result commit together")
		# The third result teaches F08 and archives the project; read the same one by id.
		var project: Dictionary = {}
		for candidate: Dictionary in f.terrain.site.family.technology.get("projects", []):
			if int(candidate.id) == f08_project_id: project = candidate
		check(project.receipts.size() == index + 1 and project.budget.payments.size() == index + 1, "Each real paid attempt contributes exactly one personal receipt")
		var before := f.snapshot()
		check(not f.actions._commit_scope_ranged_craft(job).ok and f.snapshot() == before, "Original completed job cannot replay payment or evidence")
	check(Technology.scope_known(f.terrain.site.family.technology, "F08") and Technology.learned(f.npc.technology, "F08"), "Only three true same-person original products teach F08 and archive its family knowledge")
	check(int(f.terrain.site.inventory.wood) == int(original_stock.wood) - 12 and int(f.terrain.site.inventory.iron) == int(original_stock.iron) - 6 and int(f.terrain.site.inventory.fiber) == int(original_stock.fiber) - 3 and int(f.terrain.site.inventory.tools) == int(original_stock.tools), "Actual total12/6/3 debit; original tool is not consumed")
	check(f.actions.begin_ranged_craft(2, "crossbow").ok and is_equal_approx(float(f.actions.job_for(2).duration), 162.0), "New ordinary learned crossbow uses162 without a research token")
	f.actions.cancel(2)
	f.close()

func _f08_cold_original_checkpoint() -> void:
	var f := _f08_fixture()
	_f08_begin(f)
	f.restore_only = true
	f.step(120.0)
	near(float(f.actions.job_for(2).elapsed), 60.0, "Cold NPC work improves only half as fast while fatigue remains actual")
	check(_f08_item_count(f) == 0 and Technology.active_project(f.terrain.site.family.technology).receipts.is_empty(), "A partial cold real job creates no product or knowledge")
	var exported := f.actions.export_cold_technology_jobs()
	check(exported.ok and exported.state.version == 2, "Original v2 cold owner serializes the actual F08 job")
	var wire: Dictionary = JSON.parse_string(JSON.stringify(exported.state))
	check(f.actions.cancel(2).ok, "Retire only transient original job before true restore preparation")
	var before := f.snapshot()
	var restored := f.actions.prepare_restore_cold_technology_jobs(wire)
	check(restored.ok and f.snapshot() == before, "Strict JSON candidate rebinds same actual body/source without effort or payment")
	check(f.actions.publish_restore_cold_technology_jobs(restored).ok and not f.actions.publish_restore_cold_technology_jobs(restored).ok, "Original prepared job publishes once")
	_f08_finish_effort(f)
	var result: Array = f.actions.settle_after_contacts()
	check(result.size() == 1 and result[0].ok and _f08_item_count(f) == 1, "True resumed NPC produces one actual crossbow only at the completed endpoint")
	var project: Dictionary = Technology.active_project(f.terrain.site.family.technology)
	check(project.receipts.size() == 1 and project.budget.spent == {"wood": 4, "iron": 2, "fiber": 1}, "Cold resume preserves the exact single original paid attempt")
	check(not Technology.learned(f.npc.technology, "F08"), "One cold crossbow does not teach a three-product skill")
	f.close()

func run() -> void:
	f08_deadline = Time.get_ticks_msec() + 90000
	_three_true_crossbows()
	_f08_cold_original_checkpoint()
	print("SITE_F08_SCOPE_CAMP_%s: checks=%d failures=%d; realoriginal3items/cost/failedthird/coldcheckpoint; fullLab/Native/Region excluded" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
