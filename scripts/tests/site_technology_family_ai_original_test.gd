extends "res://scripts/tests/site_building_ui_test.gd"
## Ordinary single-Site TECH-AI-01. Original Lab owns every positive step;
## original Family/PA owns permissions, finite budgets, work and all receipts.
## Explicit saved-world geography/body setup is not a Region/Native/FPS proof.
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const Family = preload("res://scripts/terrain_lab/site_family_continuity.gd")
const DutyAI = preload("res://scripts/terrain_lab/site_duty_ai.gd")
const Personality = preload("res://scripts/terrain_lab/person_personality.gd")
const AI_SAVE := "res://.godot-temp/site_technology_ai_original/two_of_three.v1.json"
var checks := 0

func _check(condition: bool, message: String) -> void:
	checks += 1
	assert(condition, message)

func _ai_fixture(prepared: bool = true) -> Dictionary:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var control: int = lab.controlled_person_id()
	var executor: int = lab.npc.person_id
	_check(control != executor and executor > 0, "Two actual original actors have distinct original identities")
	_check(lab.character.place(Vector2i(9, 10), true) and lab.npc.place(Vector2i(10, 9), true), "Both original actors are cardinally adjacent to the true camp")
	lab.simulation_speed = 1.0
	lab.restore_only = false
	lab.npc.personality = Personality.neutral()
	data.site.inventory.wood = 80
	data.site.inventory.fiber = 40
	controller.release_worker()
	data.site.worker.target = ""
	data.site.manual.target = ""
	var members: Array = []
	for identity: int in [control, executor]:
		members.append({"site_id": str(data.site.id), "person_id": identity, "path": "", "label": "原族人 #%d" % identity, "age_years": -1})
	_check(controller.family_continuity.register_members(members, true, control).ok and controller.family_continuity.appoint_head(control, control).ok, "The true controlled original head explicitly registers only the actual local people")
	if prepared:
		_check(actions.prepare_technology(control, executor).ok and actions.request_technology_consent(control, executor).ok, "One manual arrangement names the original NPC and acquires the original scope consent")
		_check(actions.grant_technology_budget(control, {"wood": 12, "fiber": 6}).ok, "The true camp user explicitly grants the finite cumulative 12/6 authorization")
	else:
		# Install the original public duty catalog through the same owner resolver;
		# no research project, source grant or permission is created by this query.
		actions.technology_query()
	var offices: Dictionary = Family.family_offices(data.site.family)
	var plan: Array = [{"op": "add", "name": "研習職", "ref": "research"},
		{"op": "assign", "duty_id": "family.research", "position_id": "research"},
		{"op": "appoint", "position_id": "research", "person_id": executor}]
	var appointed: Dictionary = controller.family_continuity.apply_office_plan(control, int(offices.revision), plan)
	_check(appointed.ok and int(controller.family_continuity.duty_resolve("family.research").get("decider", -1)) == executor, "The original head gives the NPC a genuine distinct research seat")
	_check(controller.family_continuity.set_duty_ai_enabled(control, true).ok, "The original head explicitly enables the original Family duty AI")
	return {"data": data, "lab": lab, "actions": actions, "control": control, "executor": executor,
		"wood": int(data.site.inventory.wood), "fiber": int(data.site.inventory.fiber), "bows": _bow_count(data)}

func _project(fixture: Dictionary) -> Dictionary:
	var record: Dictionary = fixture.data.site.family.get("technology", {})
	return record.get("projects", [{}])[0] if not record.get("projects", []).is_empty() else {}

func _bow_count(data: TerrainData) -> int:
	var count := 0
	for item: Dictionary in data.site.get("item_records", {}).values():
		if item.get("definition") == "weapon:bow_01": count += 1
	return count

func _snapshot(fixture: Dictionary) -> PackedByteArray:
	return var_to_bytes([fixture.data.site, fixture.lab.character.capture_state(), fixture.lab.npc.capture_state(), fixture.actions.job_for(int(fixture.executor))])

func _step(fixture: Dictionary) -> void:
	var lab: TerrainLab = fixture.lab
	var before := Runtime.now(fixture.data)
	var result := lab._advance_original_shared_step(lab.EXCHANGE_ACTION_STEP if lab.exchange_enabled else lab.ACTION_STEP)
	_check(result.ok and result.get("completed", false) and float(result.game_seconds) > 0.0, "The actual original common step completes a positive interval: " + str(result))
	_check(is_equal_approx(Runtime.now(fixture.data) - before, float(result.game_seconds) / 60.0), "Original minute/phase advances by the accepted shared interval once")

func _drive_stages(fixture: Dictionary, stages: int, limit_game_seconds: float = 900.0) -> void:
	var end := Runtime.now(fixture.data) + limit_game_seconds / 60.0
	var iterations := 0
	while _project(fixture).get("receipts", []).size() < stages:
		_check(Runtime.now(fixture.data) < end and Time.get_ticks_msec() < deadline, "Original autonomous research reaches its finite stage deadline")
		_step(fixture)
		iterations += 1
		if iterations % 32 == 0: await process_frame

func _close_ai(fixture: Dictionary) -> void:
	var lab: TerrainLab = fixture.lab
	for identity: String in fixture.actions._jobs.keys().duplicate(): fixture.actions.cancel(int(identity))
	lab.site_controller.work_team.discard_prepared_interval()
	lab._clear_shared_work_step()
	lab.queue_free()

func _automatic_three_paid_bows() -> void:
	var fixture := _ai_fixture()
	_check(not fixture.actions.is_busy(int(fixture.executor)) and _project(fixture).receipts.is_empty(), "Arrangement and finite grant produce no work or item")
	await _drive_stages(fixture, 3)
	var project: Dictionary = _project(fixture)
	_check(project.closed and project.receipts.size() == 3 and project.budget.spent == {"wood": 12, "fiber": 6}, "NPC independently completes the three original accepted stages with the original cumulative budget")
	_check(int(fixture.data.site.inventory.wood) == int(fixture.wood) - 12 and int(fixture.data.site.inventory.fiber) == int(fixture.fiber) - 6 and _bow_count(fixture.data) == int(fixture.bows) + 3, "Exactly three true bows cost exactly twelve wood and six fiber")
	_check(Technology.learned(fixture.lab.npc.technology) and not Technology.learned(fixture.lab.character.technology) and fixture.data.site.family.technology.known == ["F07"], "The actual NPC and its original Family learn in the third successful commit; another person does not")
	_check(not fixture.actions.is_busy(int(fixture.executor)), "Closed autonomous research releases the genuine person")
	var committed := var_to_bytes([project, fixture.data.site.inventory, fixture.data.site.item_records, fixture.lab.npc.technology])
	var stop := Runtime.now(fixture.data) + 3.0
	while Runtime.now(fixture.data) < stop: _step(fixture)
	_check(var_to_bytes([_project(fixture), fixture.data.site.inventory, fixture.data.site.item_records, fixture.lab.npc.technology]) == committed and not fixture.actions.is_busy(int(fixture.executor)), "Subsequent real AI reviews issue no fourth bow, new payment, duplicate receipt or repeated job")
	_close_ai(fixture)
	await process_frame

func _two_of_three_store_and_resume() -> void:
	var fixture := _ai_fixture()
	await _drive_stages(fixture, 2)
	_check(not fixture.actions.is_busy(int(fixture.executor)) and bool(fixture.data.site.family.offices.duty_ai), "Between real stages, two settled receipts are saveable with the original AI still enabled")
	var before := var_to_bytes([_project(fixture), fixture.data.site.inventory, fixture.data.site.item_records])
	var captured: Dictionary = fixture.lab.site_controller._capture_for_save()
	_check(captured.ok, "The original Controller admits and captures the actual idle 2/3 endpoint: " + str(captured))
	var saved := Store.save(fixture.data, AI_SAVE)
	_check(saved.ok, "Original Store persists the genuine 2/3 project, original people and duty AI: " + str(saved))
	var loaded := Store.load_site(AI_SAVE)
	_check(loaded.ok and bool(loaded.data.site.family.offices.duty_ai) and loaded.data.site.family.technology.projects[0].receipts.size() == 2, "Original cold validation and load preserve the enabled original AI and paid history")
	fixture.lab.bind_terrain(loaded.data)
	fixture.data = loaded.data
	fixture.actions = fixture.lab.site_controller.person_actions
	_check(var_to_bytes([_project(fixture), fixture.data.site.inventory, fixture.data.site.item_records]) == before, "Actual original bind reestablishes source refs without replaying prior goods or spent quota")
	await _drive_stages(fixture, 3)
	_check(_bow_count(fixture.data) == int(fixture.bows) + 3 and _project(fixture).budget.spent == {"wood": 12, "fiber": 6} and Technology.learned(fixture.lab.npc.technology), "Loaded original NPC autonomously completes only the remaining paid stage")
	_close_ai(fixture)
	await process_frame

func _current_permission_and_source_refusals() -> void:
	for failure: String in ["off", "player", "busy", "combat", "rest", "stock", "quota", "revoked", "away", "captive"]:
		var fixture := _ai_fixture()
		var lab: TerrainLab = fixture.lab
		var continuity: Variant = lab.site_controller.family_continuity
		match failure:
			"off": _check(continuity.set_duty_ai_enabled(int(fixture.control), false).ok, "The original head turns off new NPC duty decisions")
			"player":
				var offices: Dictionary = fixture.data.site.family.offices
				var head := str(SiteOffices.head_position(offices).id)
				var research := str(offices.duties["family.research"])
				_check(continuity.apply_office_plan(int(fixture.control), int(offices.revision), [{"op": "dismiss", "position_id": research}, {"op": "assign", "duty_id": "family.research", "position_id": head}, {"op": "abolish", "position_id": research}]).ok, "Original authority returns research to the actual player")
			"busy": _check(fixture.actions.begin_ranged_craft(int(fixture.executor), "arrow").ok, "An actual unrelated original job occupies the proposed NPC")
			"combat": Runtime.mark_combat(fixture.data)
			"rest": lab.npc.fatigue = 90.0
			"stock": fixture.data.site.inventory.wood = 0
			"quota": _check(fixture.actions.grant_technology_budget(int(fixture.control), {"wood": 3, "fiber": 1}).ok, "Explicit original finite authorization is too small for one trial")
			"revoked": _check(fixture.actions.grant_technology_budget(int(fixture.control), {}, "revoke").ok, "True original camp grantor revokes its own source")
			"away": _check(lab.npc.place(Vector2i(12, 9), true), "The actual NPC leaves original camp contact")
			"captive": lab.npc.captive = true
		var before := _snapshot(fixture)
		var result: Dictionary = DutyAI.review_family_research(lab, int(fixture.control))
		_check(not result.ok and _snapshot(fixture) == before, "Current invalid " + failure + " denies new automatic work without materials, time, items, knowledge or jobs: " + str(result))
		_close_ai(fixture)
		await process_frame
	var empty := _ai_fixture(false)
	var before := _snapshot(empty)
	var result: Dictionary = DutyAI.review_family_research(empty.lab, int(empty.control))
	_check(not result.ok and _snapshot(empty) == before and not empty.data.site.family.has("technology"), "No prepared original project never causes the AI to invent a project, consent or source grant")
	_close_ai(empty)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 210000
	await _automatic_three_paid_bows()
	await _two_of_three_store_and_resume()
	await _current_permission_and_source_refusals()
	TerrainArmy.release_contact_source()
	print("SITE_TECHNOLOGY_FAMILY_AI_ORIGINAL_PASS: %d checks; true ordinary Lab automatic 0/3-3/3, original finite 12/6 and three bows, original enabled-AI Store/bind 2/3 continuation, original current permission/source refusals; Region/Native/other autonomous research excluded" % checks)
	quit(0)
