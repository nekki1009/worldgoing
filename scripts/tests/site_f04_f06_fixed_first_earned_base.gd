extends "res://scripts/tests/site_technology_artisan_fixed_processing_base.gd"
## Real paired Taiwan source + original first birth/full pin/Family/paid work.
## Four-category release remains an ISOLATED accepted test precondition.
## Original component construction helpers supply hosts; research and lesson
## use the actual whole Lab point. No authored output/work/target knowledge.
const PAIRED_MANIFEST := "res://assets/region_lab/earth_tw_tm2_121_v1_r4/manifest.terrain_mapped_potential_v1.json"
const PAIRED_GEO_SHA := "cdf59e3247c9db3eb1e5399f7346014f8dec5c2f90bb977fd41ea35bc3444446"
const PAIRED_RESOURCE_SHA := "9acfdc50025eac0c296880102af57cc9d1faef34cc24486eef1594fcc07bd5ef"
const PRODUCTION_SITE := Vector2i(1170, 13252) # Original released forest sample.
var _earned_deadline = 0
var _earned_points = 0

func _g06_source() -> RegionData:
	var source = RegionData.new()
	_require(FileAccess.get_sha256(PAIRED_MANIFEST) == PAIRED_GEO_SHA, "Exact immutable paired geography candidate installed in isolated cohort")
	var result: Dictionary = source.load_manifest(PAIRED_MANIFEST)
	_require(result.ok and source.manifest_hash == PAIRED_GEO_SHA and source.resource_manifest_hash == PAIRED_RESOURCE_SHA and source.manifest.land_condition_rule == LAND_RULE, "Actual original Taiwan reader accepts both complete original-source pairs", result)
	manifest_path = PAIRED_MANIFEST
	return source

func _birth(source: RegionData, category: String) -> Dictionary:
	var lab = _source_lab("first_earned_" + category)
	_require(lab != null, "Actual formal original TerrainLab")
	var world = _world("first_earned_" + category)
	var slot = CandidatePolicySlot.new()
	slot.candidate_categories = [category] # Explicit hypothetical category only.
	slot.folder = "user://region_lab/worlds/%s/slots/%s" % [world, SLOT]
	lab.site_controller._initial_world_candidate = slot
	# Crowd port: the live main shell requests the crowd (restore_only was true at _ready); --grid keeps the retired army.
	lab.crowd_startup_requested = not OS.get_cmdline_user_args().has("--grid")
	var result: Dictionary = lab.site_controller.open_fixed_world(manifest_path, world, SLOT, PRODUCTION_SITE, true, Artisans.PRIMARY)
	_require(result.ok, "True paired source enters original first-world transaction", result)
	_freeze(lab)
	var data: TerrainData = lab.terrain
	_require(int(birth_counts[lab.get_instance_id()]) == 1 and int(slot._marker.generation) == 1 and lab.region_bind_receipt(data).get("complete", false), "One original initial transaction and complete actual bind")
	_require(data.parameters.fixed_base.land_condition_rule == LAND_RULE and data.site.world_pin.manifest_sha256 == PAIRED_GEO_SHA and data.site.world_pin.resource_layer_sha256 == PAIRED_RESOURCE_SHA and Artisans.validate_receipt(data.site.technology_artisans, data.site), "Full original source/resource/policy pin and original birth receipt")
	var team = _team_view(lab)
	_require(team.combat_units.size() == 5 and not data.site.has("family"), "Finite independent original people; no invented knowledge archive")
	var master = team.combat_identity(Artisans.CATEGORIES.find(category) + 1)
	var commander = team.combat_identity(team.current_commander)
	var executor = team.combat_identity(2 if category == "F04" else 1)
	_require(executor != master and executor != commander and not Technology.learned(team.combat_units[team.index_for_identity(executor)].get("technology", {}), category), "The original named research executor is truly unlearned")
	_require(lab.site_controller._control_family_person(null, commander).ok, "Original control selects the true original work decider")
	return {"kind": "fixed_birth", "lab": lab, "data": data, "source": source, "world": world, "slot": slot, "team": team,
		"master": master, "helper": executor, "executor": executor, "commander": commander, "category": category, "coordinate": PRODUCTION_SITE,
		"birth": data.site.technology_artisans.duplicate(true), "fixed_base": data.parameters.fixed_base.duplicate(true), "pin": data.site.world_pin.duplicate(true),
		"next_person": int(data.site.next_person_id), "next_item_birth": int(data.site.next_item), "geography": data.fingerprint()}

func _cold_resume(f: Dictionary, label: String) -> void:
	_idle_all(f)
	var controller: SiteController = f.lab.site_controller
	_require(controller.save_to(controller.save_path).ok, "Original full-pin productive checkpoint: " + label)
	var saved: Dictionary = controller.region_slot._load_checked(controller.region_slot.site_path(f.coordinate), f.coordinate)
	_require(saved.ok and saved.data.site.world_pin == f.pin and saved.data.parameters.fixed_base == f.fixed_base and saved.data.site.technology_artisans == f.birth, "Actual Store validates full paired pin and immutable birth history", saved)
	var expected = _normalized(saved.data.site.family.technology) if saved.data.site.has("family") else ""
	var lab = _source_lab("earned_cold_" + label)
	lab.crowd_startup_requested = not OS.get_cmdline_user_args().has("--grid")
	_require(lab.site_controller.open_fixed_world(manifest_path, str(f.world), SLOT, Vector2i(-1, -1), false).ok, "True Slot/Controller fullgraph cold reopen")
	_freeze(lab)
	_require(int(birth_counts[lab.get_instance_id()]) == 0 and lab.region_bind_receipt(lab.terrain).get("complete", false) and (not lab.terrain.site.has("family") or _normalized(lab.terrain.site.family.technology) == expected), "Cold bind never reissues birth, project receipt or knowledge")
	f.lab.free()
	f.lab = lab
	f.data = lab.terrain
	f.team = _team_view(lab)
	f.slot = lab.site_controller.region_slot
	_require(lab.site_controller._control_family_person(null, int(f.commander)).ok, "Same original current head is explicitly controlled after cold bind")
	# Crowd: research consent needs the whole team standing (the game rule); the fixture stations idle members on their
	# formation slots (_park), so the loaded team must still be standing.
	_stand_still(f, "after the cold bind")

func _earned_project(f: Dictionary) -> Dictionary:
	for project: Dictionary in f.data.site.family.technology.projects:
		if project.purpose == str(f.category) + ":first": return project
	return {}

func _earned_bytes(f: Dictionary) -> PackedByteArray:
	return var_to_bytes([f.data.site, _combat_state(f), f.lab.site_controller.person_actions._jobs])

func _earned_point(f: Dictionary) -> Dictionary:
	_require(Time.get_ticks_msec() < _earned_deadline, "Bounded real point fixture deadline")
	var result: Dictionary = f.lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
	_require(result.ok and result.get("completed", false) and f.lab._region_point_pending.is_empty(), "Original whole Lab point settles actual work/fatigue/clock/contacts", result)
	_earned_points += 1
	return result

func _earned_setup(f: Dictionary) -> Array:
	_finite_stock(f, {"iron_ore": 3, "charcoal": 5, "fiber": 3, "wool": 9})
	var well = _build(f, "well", Vector2i(58, 58))
	f.water_origin = f.data.cell_from_index(int(f.data.site.features[well].cells[0]))
	var hosts: Array = []
	if f.category == "F04":
		hosts = [_build(f, "smelter", Vector2i(60, 58)), _build(f, "smithy", Vector2i(66, 58))]
	else: hosts = [_build(f, "weaver", Vector2i(60, 58))]
	_idle_all(f)
	var refs: Array = []
	for id: int in [int(f.commander), int(f.executor)]:
		refs.append({"site_id": str(f.data.site.id), "person_id": id, "path": "", "label": "首研具名原人", "age_years": -1})
	var owner: Variant = f.lab.site_controller.family_continuity
	_require(owner.register_members(refs, true, int(f.commander)).ok and owner.appoint_head(int(f.commander), int(f.commander)).ok, "Actual original Family register/head; background master remains independent")
	var actions: SitePersonActions = f.lab.site_controller.person_actions
	f.data.site.family = actions._technology_candidate()
	f.data.site.family.technology = Technology.empty_scope_record(str(f.data.site.id))
	f.data.site.family.technology.known = ["F03"] if f.category == "F04" else ["F05"]
	_require(Family.validate_family(f.data.site.family, str(f.data.site.id)) and not Technology.scope_known(f.data.site.family.technology, str(f.category)), "Only explicit prerequisite archive input; target never preset")
	var depot: Vector2i = f.data.cell_from_index(int(f.data.site.depot_cell))
	# Camp contact needs one of the four side cells; the right one may already be taken.
	var camp_side := depot + Vector2i.RIGHT
	for side: Vector2i in TerrainData.DIRECTIONS:
		var candidate := depot + side
		var taken := false
		for index in _team_units(f.team):
			if f.team.combat_identity(index) != int(f.commander) and _cell_of(f, f.team.combat_identity(index)) == candidate: taken = true
		for actor: TerrainTestCharacter in f.lab.combat_actors:
			if actor.person_id != int(f.commander) and actor.terrain_cell == candidate: taken = true
		if not taken and f.data.is_walkable(candidate) and int(f.data.feature_at[f.data.index(candidate)]) == 0: camp_side = candidate; break
	_park(f, int(f.commander), camp_side)
	_require(actions._ranged_craft_context(actions._person(int(f.commander))).ok, "Current controlled original person truly contacts the original camp source")
	var prepared_research: Dictionary = actions.prepare_scope_technology(int(f.commander), int(f.executor), str(f.category))
	_require(prepared_research.ok, "Public original Family prepares unknown first research", prepared_research)
	f.family_id = str(f.data.site.family.family_id)
	var cap: Dictionary = {"iron_ore": 3, "charcoal": 5, "iron": 2, "steel": 1, "wood": 1} if f.category == "F04" else {"fiber": 3, "wool": 9}
	var granted: Dictionary = actions.grant_scope_technology_budget(int(f.commander), "family", str(f.family_id), cap)
	var consented: Dictionary = actions.request_scope_technology_consent(int(f.commander), "family", str(f.family_id), int(f.executor)) if granted.ok else {"ok": false, "code": "NOT_ASKED"}
	_require(granted.ok and consented.ok, "True finite source grant and original team's explicit named consent", {"grant": granted, "consent": consented})
	return hosts

func _earned_partial_cold(f: Dictionary, key: String, binding: String) -> void:
	var feature: Dictionary = f.data.site.features[key]
	for point: int in 120:
		if float(feature.production) > 0.0: break
		_earned_point(f)
	_require(float(feature.production) > 0.0 and feature.batch_paid and _earned_project(f).receipts.is_empty(), "Real partial paid work creates no output or knowledge")
	var project: Dictionary = _earned_project(f)
	var id = int(project.id)
	var attempt = int(project.next_attempt)
	var budget = _normalized(project.budget)
	var progress = float(feature.production)
	var token: Dictionary = feature.tech_trial.duplicate(true)
	var actions: SitePersonActions = f.lab.site_controller.person_actions
	_require(actions.stop_scope_technology(int(f.commander), "family", str(f.family_id)).ok, "Original named stop retains paid incomplete physical work")
	_cold_resume(f, "unknown_partial_" + str(f.category))
	feature = f.data.site.features[key]
	project = _earned_project(f)
	_require(int(project.id) == id and int(project.next_attempt) == attempt and _normalized(project.budget) == budget and float(feature.production) == progress and feature.tech_trial == token and not Technology.learned(f.team.combat_units[f.team.index_for_identity(int(f.executor))].get("technology", {}), str(f.category)), "Full-pin cold preserves the one actual unpaid-completion attempt, spent and original unlearned executor")
	actions = f.lab.site_controller.person_actions
	var reactivated: Dictionary = actions.prepare_scope_technology(int(f.commander), int(f.executor), str(f.category))
	_require(reactivated.ok, "Reactivate SAME original retained purpose", reactivated)
	_place(f, int(f.executor), f.data.cell_from_index(int(feature.entrance)))
	var result: Dictionary = actions.begin_scope_technology_phase(int(f.commander), "family", str(f.family_id), binding, "feature:" + key)
	_require(result.ok and result.get("resumed", false) and _normalized(_earned_project(f).budget) == budget and int(_earned_project(f).next_attempt) == attempt, "True original paid resume does not charge or issue a new attempt", result)

func _earned_phase(f: Dictionary, key: String, binding: String, expected: Dictionary, ordinal: int, total: int) -> void:
	var actions: SitePersonActions = f.lab.site_controller.person_actions
	var feature: Dictionary = f.data.site.features[key]
	var station: Vector2i = f.data.cell_from_index(int(feature.entrance))
	_clear_station(f, int(f.executor), station) # The builder may still stand at the new host's doorway.
	_place(f, int(f.executor), station)
	_park(f, int(f.commander), station + Vector2i(0, 3))
	var before_stock: Dictionary = f.data.site.inventory.duplicate(true)
	var body: Dictionary = f.team.combat_units[f.team.index_for_identity(int(f.executor))]
	var before_cargo: Dictionary = body.cargo.duplicate(true)
	var started: Dictionary = actions.begin_scope_technology_phase(int(f.commander), "family", str(f.family_id), binding, "feature:" + key)
	_require(started.ok and feature.batch_paid and _earned_project(f).budget.payments.size() == ordinal + 1, "One true full original phase input pays and binds exactly once", started)
	_require(Runtime.feature_recipe(feature).input == expected.input and Runtime.feature_recipe(feature).output == expected.output and is_equal_approx(float(Runtime.feature_recipe(feature).cycle) * 60.0, float(expected.seconds)), "Research has exact original material/output/work terms")
	for material: String in expected.input: _require(int(before_stock.get(material, 0)) - int(f.data.site.inventory.get(material, 0)) == int(expected.input[material]), "Actual original phase full debit: " + material)
	var token: Dictionary = feature.tech_trial
	var ledger: Dictionary = feature.tech_batch
	var unchanged = _earned_bytes(f)
	var no_op: Dictionary = actions.begin_scope_technology_phase(int(f.commander), "family", str(f.family_id), binding, "feature:" + key)
	_require(no_op.ok and no_op.get("already_working", false) and _earned_bytes(f) == unchanged, "Actual active task repeat is an immutable no-op")
	_require(Runtime.technology_recipe_guard(f.data, key, feature, int(f.executor), token).ok, "D10 admits only this true current project/phase's unlearned executor")
	if binding in ["steel", "steel_tools", "wool_cloth"]:
		var ordinary: Dictionary = Runtime.technology_recipe_guard(f.data, key, feature, int(f.executor))
		_require(not ordinary.ok and ordinary.code == "NO_TECHNOLOGY", "Identical original unlearned body has no ordinary manufacture bypass")
	if ordinal == 0:
		_earned_partial_cold(f, key, binding)
		feature = f.data.site.features[key]
		token = feature.tech_trial
		ledger = feature.tech_batch
		body = f.team.combat_units[f.team.index_for_identity(int(f.executor))]
	for point: int in 20000:
		if _earned_project(f).receipts.size() == ordinal + 1: break
		_earned_point(f)
	var project: Dictionary = _earned_project(f)
	_require(project.receipts.size() == ordinal + 1 and project.budget.payments.size() == ordinal + 1 and not feature.has("tech_trial") and not feature.has("tech_batch"), "Completed true original product yields exactly one successful same-person phase")
	var receipt: Dictionary = project.receipts[ordinal]
	_require(int(receipt.person_id) == int(f.executor) and receipt.phase_id == token.phase_id and float(receipt.work_seconds) >= float(expected.seconds) - 0.00001 and receipt.payment_id == ledger.payment_id, "Personal effort credit is actual original unweighted full work, never background master/assistant")
	var canonical: Dictionary = feature.technology_output.receipts[0]
	_require(canonical.operator_id == int(f.executor) and canonical.resources == expected.output and is_equal_approx(float(canonical.work_seconds), float(receipt.work_seconds)), "Canonical real producer and finite Scope history agree")
	for product: String in expected.output: _require(int(body.cargo.get(product, 0)) - int(before_cargo.get(product, 0)) == int(expected.output[product]), "Unique actual phase cargo: " + product)
	_require(Technology.learned(body.get("technology", {}), str(f.category)) == (ordinal + 1 == total) and Technology.scope_known(f.data.site.family.technology, str(f.category)) == (ordinal + 1 == total), "Target knowledge appears only after all named phases")
	unchanged = _earned_bytes(f)
	var replay: Dictionary = Runtime.begin_technology_operation(f.data, token, false)
	_require(not replay.ok and _earned_bytes(f) == unchanged, "Completed actual token cannot replay materials, product, attempt or personal credit", replay)

func _earned_lesson(f: Dictionary) -> void:
	_idle_all(f)
	var actions: SitePersonActions = f.lab.site_controller.person_actions
	var depot: Vector2i = f.data.cell_from_index(int(f.data.site.depot_cell))
	var units := _team_units(f.team)
	for n: int in units.size(): _park(f, f.team.combat_identity(units[n]), depot + Vector2i(0, 8 + n))
	var cells: Array[Vector2i] = []
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var cell = depot + direction
		if f.data.is_walkable(cell) and f.data.can_step(cell, depot) and not f.lab.combat_actors.any(func(actor: TerrainTestCharacter) -> bool: return actor.terrain_cell == cell): cells.append(cell)
	_require(cells.size() >= 2, "Actual original camp has distinct valid teacher/student contacts")
	_place(f, int(f.executor), cells[0])
	_place(f, int(f.commander), cells[1])
	for point: int in 16000:
		if actions._ready(actions._person(int(f.executor))) and Fatigue.read(f.team.combat_units[f.team.index_for_identity(int(f.executor))]) <= Fatigue.WORK_RESUME_AT: break
		_earned_point(f)
	# Crowd: while the fixture waited for the teacher's fatigue to recover, both walked back to their formation slots by the
	# real rules (a grid row stays where it is put). They stand still now; the fixture stations them at the camp again.
	if _crowd(f):
		_place(f, int(f.executor), cells[0])
		_place(f, int(f.commander), cells[1])
		# Fixture station: both hold their camp contacts with the same native step hold the lesson itself takes, while the
		# rest of the team settles (lesson consent needs the whole team standing).
		for identity: int in [int(f.executor), int(f.commander)]:
			_require(f.lab.crowd_site.siege_approach_step(identity, _cell_of(f, identity)), "Crowd fixture holds a camp station", identity)
		_stationed = {}
		_stand_still(f, "before the lesson")
		_require(_cell_of(f, int(f.executor)) == cells[0] and _cell_of(f, int(f.commander)) == cells[1], "Teacher and student still stand at the camp")
	var student: Dictionary = f.team.combat_units[f.team.index_for_identity(int(f.commander))]
	_require(not Technology.learned(student.get("technology", {}), str(f.category)), "Actual original head/student has not acquired target knowledge")
	var stock: Dictionary = f.data.site.inventory.duplicate(true)
	var items: Dictionary = f.data.site.item_records.duplicate(true)
	_require(actions.begin_technology_lesson(int(f.commander), int(f.executor), int(f.commander), str(f.category)).ok, "First-earned executor teaches via actual original Family 300-second lesson")
	var job: Dictionary = actions._jobs[actions._job_key_for(int(f.executor))]
	_require(float(job.duration) == 300.0, "Full real lesson duration; no taught receipt authored")
	for point: int in 16000:
		if not actions.is_busy(int(f.executor)): break
		_earned_point(f)
	_require(not actions.is_busy(int(f.executor)) and is_equal_approx(float(job.elapsed), 300.0) and Technology.learned(student.get("technology", {}), str(f.category)), "Actual whole Lab work completes all 300 teaching seconds and only then learns")
	for resource: String in stock:
		if resource != "grain": _require(int(f.data.site.inventory.get(resource, 0)) == int(stock[resource]), "Lesson charges no manufacturing materials: " + resource)
	_require(int(f.data.site.inventory.get("grain", 0)) <= int(stock.get("grain", 0)) and f.data.site.item_records == items, "No lesson product; actual original food consumption remains permitted")
	var unchanged = _earned_bytes(f)
	_require(not actions.begin_technology_lesson(int(f.commander), int(f.executor), int(f.commander), str(f.category)).ok and _earned_bytes(f) == unchanged, "Already learned student cannot replay a course")

func _run() -> void:
	# Crowd: construction and research advance by real whole-Lab points (about 6500 points for the three hosts), not by the
	# grid harness's direct 60 s work prefixes, so the bounded fixture budget is 480 s (outer 600); grid keeps 180 s.
	_earned_deadline = Time.get_ticks_msec() + (180000 if OS.get_cmdline_user_args().has("--grid") else 480000)
	var category = _g06_category()
	_require(category in ["F04", "F06"] and bool(Catalog.get_node(category).get("enabled", false)), "Explicit isolated accepted catalog; no test activation override")
	var f: Dictionary = _birth(_g06_source(), category)
	var hosts: Array = _earned_setup(f)
	var stages: Array = [
		{"host": hosts[0], "binding": "iron", "input": {"iron_ore": 3, "charcoal": 2}, "output": {"iron": 2}, "seconds": 900.0},
		{"host": hosts[0], "binding": "steel", "input": {"iron": 2, "charcoal": 2}, "output": {"steel": 1}, "seconds": 1200.0},
		{"host": hosts[1], "binding": "steel_tools", "input": {"steel": 1, "charcoal": 1, "wood": 1}, "output": {"tools": 2}, "seconds": 720.0}
	] if category == "F04" else [
		{"host": hosts[0], "binding": "plant_cloth", "input": {"fiber": 3}, "output": {"cloth": 2}, "seconds": 720.0},
		{"host": hosts[0], "binding": "wool_cloth", "input": {"wool": 3}, "output": {"cloth": 2}, "seconds": 900.0},
		{"host": hosts[0], "binding": "wool_cloth", "input": {"wool": 3}, "output": {"cloth": 2}, "seconds": 900.0},
		{"host": hosts[0], "binding": "wool_cloth", "input": {"wool": 3}, "output": {"cloth": 2}, "seconds": 900.0}
	]
	for index: int in stages.size():
		var stage: Dictionary = stages[index]
		_earned_phase(f, str(stage.host), str(stage.binding), stage, index, stages.size())
		if category == "F04" and index < 2:
			var depot: Vector2i = f.data.cell_from_index(int(f.data.site.depot_cell))
			_transfer(f, int(f.executor), "person:" + str(f.executor), "depot", stage.output, depot + Vector2i.RIGHT)
	var project: Dictionary = _earned_project(f)
	_require(project.budget.spent == project.budget.cap and project.receipts.size() == stages.size() and Technology.valid_scope_record(f.data.site.family.technology, "family"), "Finite complete original project balances all actual phase transactions")
	_cold_resume(f, "first_earned_final_" + category)
	_require(Technology.scope_known(f.data.site.family.technology, category) and Technology.learned(f.team.combat_units[f.team.index_for_identity(int(f.executor))].get("technology", {}), category), "True complete cold read/bind preserves earned target")
	var unchanged = _earned_bytes(f)
	var replay: Dictionary = f.lab.site_controller.person_actions.prepare_scope_technology(int(f.commander), int(f.executor), category)
	_require(not replay.ok and replay.code == "ALREADY_LEARNED" and _earned_bytes(f) == unchanged, "Complete project cannot allocate another first-purpose attempt")
	_earned_lesson(f)
	_cold_resume(f, "earned_student_" + category)
	_require(Technology.learned(f.team.combat_units[f.team.index_for_identity(int(f.commander))].get("technology", {}), category) and f.data.site.technology_artisans == f.birth, "Cold saved true student learns without reissuing initial artisans")
	report[category] = {"first_earned": true, "real_paired_source": PAIRED_GEO_SHA, "resource_pair": PAIRED_RESOURCE_SHA, "research_executor": f.executor, "background_master_not_research_executor": f.master,
		"true_original_phases": stages, "whole_research_lesson_points": _earned_points, "component_construction_setup_only": true, "station_placement_is_fixture_not_travel": true, "partial_final_cold_and_replay": true, "public_release_and_FULL_G06": "OPEN"}
	_finish()

func _finish(reason: String = "") -> void:
	if finished: return
	finished = true
	if not reason.is_empty(): failures.append(reason)
	for lab: TerrainLab in labs:
		if is_instance_valid(lab): lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_FIXED_FIRST_EARNED_REPORT: " + JSON.stringify({"checks": checks, "failures": failures, "cases": report}, "", true, true))
	print("SITE_%s_FIXED_FIRST_EARNED_%s: checks=%d original source/birth/fullpin/Family/real paid phases/wholepoint lesson/cold/replay; NOT formal release or FULL G06" % [_g06_category(), "PASS" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)

# Crowd port helpers. The team holding the commander is the native CrowdPersonOwner; cells come from the
# original person read (both modes), never from grid cell arrays.
func _team_view(lab: TerrainLab) -> Variant:
	var army: TerrainArmy = lab.army
	if lab.crowd_site != null and lab.crowd_site.active:
		var holder: Variant = lab.crowd_site.person_owner(army.combat_identity(army.current_commander))
		if holder != null: return holder
	return army

func _team_units(team: Variant) -> Array:
	return team.combat_units.keys() if team.combat_units is Dictionary else range(team.combat_units.size())

func _cell_of(f: Dictionary, identity: int) -> Vector2i:
	return f.lab._original_person_target(identity).get("cell", Vector2i(-1, -1))

func _crowd(f: Dictionary) -> bool:
	return f.team is CrowdPersonOwner

func _occupied_by_other(f: Dictionary, identity: int, cell: Vector2i) -> bool:
	for index in _team_units(f.team):
		var other: int = f.team.combat_identity(index)
		if other != identity and _cell_of(f, other) == cell: return true
	for actor: TerrainTestCharacter in f.lab.combat_actors:
		if actor.person_id != identity and actor.terrain_cell == cell: return true
	return false

func _clear_station(f: Dictionary, identity: int, cell: Vector2i) -> void:
	for index in _team_units(f.team):
		var other: int = f.team.combat_identity(index)
		if other != identity and _cell_of(f, other) == cell: _park(f, other, cell + Vector2i(0, 4))

var _stationed := {} # Crowd: the last person the fixture put on an explicit station (not a parking cell).
var _parking := false
func _place(f: Dictionary, identity: int, cell: Vector2i) -> void:
	if not _crowd(f):
		super._place(f, identity, cell)
		return
	if not _parking: _stationed = {"identity": identity, "cell": cell}
	var native: int = int(f.lab.crowd_site.crowd.soldier_index(identity))
	_require(native >= 0 and f.data.is_walkable(cell) and not _occupied_by_other(f, identity, cell), "Actual crowd person can occupy an unoccupied fixture station")
	_require(f.lab.crowd_site.set_soldier_fields(native, {"px": cell.x + 0.5, "py": cell.y + 0.5}), "Crowd fixture placement of the same native person")
	_require(_cell_of(f, identity) == cell, "Crowd person reads the explicit fixture station")

func _park(f: Dictionary, identity: int, near: Vector2i) -> void:
	_park_at(f, identity, near)
	# Crowd: a commander is present only within the command radius of its team's reference member (native
	# refresh_presence, about 8 cells), and an absent head pauses team.work (found 2026-11-11: the fixture moved only the
	# commander beside the worker, 15 cells from the three idle artisans, and no work progressed). In play the idle members
	# of a team stand in formation with their commander, so the fixture stations them with the commander.
	if _crowd(f) and identity == int(f.commander):
		var head_cell := _cell_of(f, identity)
		# The formation's HOLD centre moves with the fixture too; otherwise the idle members walk back to the old centre
		# and the commander (the controlled person, who does not auto-walk) is left outside the command radius.
		_require(f.lab.crowd_site.set_formation_fields(int(f.team.formation_index), {"cx": head_cell.x + 0.5, "cy": head_cell.y + 1.5,
			"origin_x": head_cell.x + 0.5, "origin_y": head_cell.y + 1.5}), "Crowd fixture moves the team's hold centre with its commander")
		for index in _team_units(f.team):
			var other: int = f.team.combat_identity(index)
			if other == identity or not f.team._cold_get(index, "work_task", {}).is_empty(): continue
			var gap := _cell_of(f, other) - head_cell
			if absi(gap.x) + absi(gap.y) > 4: _park_at(f, other, head_cell + Vector2i(0, 1))
		_stand_still(f, "after the fixture stationed the commander")

## Crowd: work assignment and research consent need the whole team standing (the game rule), and a fixture placement keeps
## each member's last native velocity until the next step. The idle members walk to their formation slots by the real
## rules; the fixture waits for that with real points, as a player would. Nothing is assigned or paid while it waits.
func _stand_still(f: Dictionary, label: String) -> void:
	if not _crowd(f): return
	for settle: int in 1800:
		if _team_still(f): break
		_earned_point(f)
	_require(_team_still(f), "Crowd team stands still in formation " + label, _motion_facts(f))
	# The person stationed just before (an idle member walks to its slot while the team settles) returns to that station,
	# now with no native velocity left.
	var again: Dictionary = _stationed
	_stationed = {}
	if not again.is_empty() and int(again.identity) != int(f.commander) and _cell_of(f, int(again.identity)) != Vector2i(again.cell):
		_place(f, int(again.identity), Vector2i(again.cell))
		_stationed = {}

func _team_still(f: Dictionary) -> bool:
	if f.team.moving_member_count() > 0: return false
	for index in _team_units(f.team):
		if bool(f.team.person(int(index), false).get("moving", true)) and f.team._cold_get(int(index), "work_task", {}).is_empty(): return false
	return true

func _motion_facts(f: Dictionary) -> Array:
	var motion: Array = []
	for index in _team_units(f.team):
		motion.append({"id": f.team.combat_identity(int(index)), "walking": f.team.is_walking(int(index)), "speed": snappedf(f.team.drift_speed(int(index)), 0.0001),
			"raw_moving": bool(f.team.person(int(index), false).get("moving", true)), "cell": str(_cell_of(f, f.team.combat_identity(int(index))))})
	return motion

func _park_at(f: Dictionary, identity: int, near: Vector2i) -> void:
	_parking = true
	_park_cell(f, identity, near)
	_parking = false

func _park_cell(f: Dictionary, identity: int, near: Vector2i) -> void:
	# Station placement is explicit fixture input; never original navigation proof.
	for radius: int in range(0, 12):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if absi(x) + absi(y) != radius: continue
				var cell := near + Vector2i(x, y)
				if not f.data.is_walkable(cell) or int(f.data.feature_at[f.data.index(cell)]) != 0: continue
				if not _occupied_by_other(f, identity, cell):
					_place(f, identity, cell)
					return
	_require(false, "Original generated ground has a free explicit person station")

func _transfer(f: Dictionary, identity: int, source_id: String, destination_id: String, resources: Dictionary, cell: Vector2i) -> void:
	_idle_all(f)
	_clear_station(f, identity, cell)
	_place(f, identity, cell)
	_park(f, int(f.commander), cell + Vector2i(0, 3))
	var logistics_people: Array[int] = [identity] # The controller API takes a typed array.
	_require(f.lab.site_controller.order_team_logistics(f.team, logistics_people, int(f.commander), true).ok, "Actual current logistics decider names original person")
	var vehicles: SiteVehicleTransport = f.lab.site_controller.vehicles
	var source: Dictionary = vehicles._stock(source_id, source_id.begins_with("feature:") or destination_id.begins_with("feature:"))
	var destination: Dictionary = vehicles._stock(destination_id, source_id.begins_with("feature:") or destination_id.begins_with("feature:"))
	_require(not source.is_empty() and not destination.is_empty(), "True original physical cargo endpoints")
	var result := vehicles.transfer(source_id, destination_id, resources, [], int(source.holder.version), int(destination.holder.version), int(f.commander))
	_require(result.ok, "True original full-version adjacent resource transfer", result)
	_require(f.lab.site_controller.order_team_logistics(f.team, logistics_people, int(f.commander), false).ok, "Original person ends logistics without new owner")

# Crowd work clock: the grid harness drove SiteWorkTeam's shared prefix directly, which a native crowd cannot (its work is
# planned inside the native begin window). The crowd interval is the same amount of GAME time advanced by real whole-Lab
# points; effective work is what those points actually applied to the features (construction progress is kept in minutes;
# a build that completes inside a point applied the rest of its work).
func _feature_work_state(f: Dictionary) -> Dictionary:
	var state := {}
	for key: String in f.data.site.features:
		var feature: Dictionary = f.data.site.features[key]
		state[key] = [str(feature.get("stage", "")), float(feature.get("progress", 0.0)), float(feature.get("work", 0.0)), float(feature.get("production", 0.0))]
	return state

func _interval(f: Dictionary, seconds: float = 60.0) -> Dictionary:
	if not _crowd(f): return super._interval(f, seconds)
	var effective := 0.0
	var advanced := 0.0
	while advanced < seconds - 0.000001:
		var before := _feature_work_state(f)
		var point := _earned_point(f)
		advanced += float(point.game_seconds)
		var after := _feature_work_state(f)
		for key: String in before:
			if not after.has(key): continue
			if before[key][0] != "complete" and after[key][0] == "complete": effective += maxf(0.0, float(before[key][2]) - float(before[key][1])) * 60.0
			else: effective += maxf(0.0, float(after[key][1]) - float(before[key][1])) * 60.0 + maxf(0.0, float(after[key][3]) - float(before[key][3])) * 60.0
	_work_effective += effective
	_work_actual += effective
	_work_intervals += 1
	return {"effective": effective, "actual": effective, "handled": {}}
