extends "res://scripts/tests/site_building_ui_test.gd"
## Requires the T5 fragment merged into ORIGINAL PA and the original Lab idle
## hook. Real Lab/capture/supply/prison owners; this PA-only clock adapter is
## NOT the complete TerrainLab collector/native/performance closure.
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")

func _plan_step(lab: TerrainLab, seconds: float) -> Dictionary:
	var actions: SitePersonActions = lab.site_controller.person_actions
	var planned := Fatigue.plan_work_interval(actions.work_requests(seconds), seconds)
	assert(planned.ok, str(planned))
	for group: Dictionary in planned.pools:
		if float(group.effort_seconds) <= 0.0: continue
		Fatigue.write(group.body, "fatigue", float(group.fatigue))
		Fatigue.write(group.body, "fatigue_rest", float(group.fatigue_rest))
	actions.advance(seconds, {"jobs": planned.jobs.get("person_actions", {})})
	return planned

func _bows(data: TerrainData) -> int:
	var count := 0
	for record: Dictionary in data.site.item_records.values():
		if str(record.definition) == "weapon:bow_01": count += 1
	return count

func _technology_bytes(lab: TerrainLab) -> PackedByteArray:
	return var_to_bytes([lab.terrain.site.family.get("technology", {}), lab.character.technology, lab.npc.technology])

func _learn_original_npc(lab: TerrainLab) -> void:
	var data: TerrainData = lab.terrain
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	data.site.depot_cell = data.index(Vector2i(9, 10))
	assert(lab.character.place(Vector2i(8, 10), true) and lab.npc.place(Vector2i(9, 9), true))
	var refs: Array = []
	for actor: TerrainTestCharacter in [lab.character, lab.npc]:
		refs.append({"site_id": str(data.site.id), "person_id": actor.person_id, "path": "", "label": "原人 #%d" % actor.person_id, "age_years": -1})
	assert(controller.family_continuity.register_members(refs, true, lab.character.person_id).ok)
	assert(controller.family_continuity.appoint_head(lab.character.person_id, lab.character.person_id).ok)
	assert(actions.prepare_technology(lab.character.person_id, lab.npc.person_id).ok)
	assert(actions.request_technology_consent(lab.character.person_id, lab.npc.person_id).ok)
	assert(actions.grant_technology_budget(lab.character.person_id, {"wood": 12, "fiber": 6}).ok)
	for _trial: int in 3:
		var started := actions.begin_technology_trial(lab.character.person_id, lab.npc.person_id)
		assert(started.ok and is_equal_approx(float(started.seconds), 120.0), str(started))
		_plan_step(lab, 120.0)
		var results := actions.settle_after_contacts()
		assert(results.size() == 1 and results[0].ok, str(results))
	assert(Technology.learned(lab.npc.technology, "F07"))
	assert(data.site.family.technology.known.has("F07"))

func _capture_original(lab: TerrainLab, guard_cell: Vector2i = Vector2i(8, 9), captive_cell: Vector2i = Vector2i(9, 9)) -> void:
	var actions: SitePersonActions = lab.site_controller.person_actions
	assert(lab.character.place(guard_cell, true) and lab.npc.place(captive_cell, true))
	lab.npc.faction_id = 2
	lab.npc.knockout_left = 30.0
	lab.npc.issue_command(TerrainTestNPC.Command.STOP)
	assert(actions.begin_capture(lab.character.person_id, lab.npc.person_id, lab.character.person_id).ok)
	actions.advance(4.0)
	var results := actions.settle_after_contacts()
	assert(results.size() == 1 and results[0].ok and lab.npc.captive, str(results))
	var relation: Dictionary = lab.terrain.site.captivity[str(lab.npc.person_id)]
	assert(int(relation.version) == 3 and not str(relation.episode).is_empty())
	# Physical recovery is original prison-fixture setup, not an authority or
	# learned-skill/captivity fabrication. Capture itself used real callbacks.
	lab.npc.knockout_left = 0.0
	lab.npc.stun = 0.0
	lab.npc._getting_up = false
	lab.npc.action_time = 0.0
	assert(not lab.npc.can_act() and actions.has_effective_guard(lab.npc.person_id))

func _begin(lab: TerrainLab) -> Dictionary:
	return lab.site_controller.person_actions.begin_captive_craft(lab.character.person_id, lab.npc.person_id)

func _check_field_production() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	_learn_original_npc(lab)
	_capture_original(lab)
	var actions: SitePersonActions = lab.site_controller.person_actions
	var tech_before := _technology_bytes(lab)
	var relation: Dictionary = data.site.captivity[str(lab.npc.person_id)].duplicate(true)
	var holder := lab.npc.item_state
	var holder_before := holder.duplicate(true)
	var original_bows := _bows(data)
	var stock_before: Dictionary = data.site.inventory.duplicate(true)
	var before := var_to_bytes(data.site)
	var started := _begin(lab)
	assert(started.ok and is_equal_approx(float(started.seconds), 108.0), str(started))
	assert(var_to_bytes(data.site) == before, "Beginning supervised work reserves no stock")
	assert(actions.is_busy(lab.character.person_id) and actions.is_busy(lab.npc.person_id))
	assert(str(actions.save_guard().code) == "BUSY")
	assert(not actions.begin_ranged_craft(lab.npc.person_id, "bow").ok)
	assert(not actions.begin_technology_trial(lab.character.person_id, lab.npc.person_id).ok)
	assert(not actions.begin_technology_lesson(lab.character.person_id, lab.npc.person_id, lab.character.person_id).ok)
	assert(not actions.stop_technology(lab.character.person_id, lab.npc.person_id).ok, "Research stop cannot cancel a supervised production task")
	var guard_fatigue := lab.character.fatigue
	var captive_fatigue := lab.npc.fatigue
	var plan := _plan_step(lab, 108.0)
	assert(plan.pools.size() == 2 and lab.character.fatigue > guard_fatigue and lab.npc.fatigue > captive_fatigue)
	assert(_bows(data) == original_bows, "Completion awaits original contact settlement")
	var results := actions.settle_after_contacts()
	assert(results.size() == 1 and results[0].ok and _bows(data) == original_bows + 1, str(results))
	assert(int(data.site.inventory.wood) == int(stock_before.wood) - 4 and int(data.site.inventory.fiber) == int(stock_before.fiber) - 2)
	assert(data.site.captivity[str(lab.npc.person_id)] == relation and lab.npc.captive and not lab.npc.can_act())
	assert(is_same(lab.npc.item_state, holder) and holder == holder_before)
	assert(_technology_bytes(lab) == tech_before, "Manufacture creates no trial/analysis/lesson/knowledge evidence")
	assert(actions.save_guard().ok and actions.settle_after_contacts().is_empty())
	assert(_begin(lab).ok)
	assert(actions.stop_captive_craft(lab.character.person_id, lab.npc.person_id).ok)
	assert(not actions.is_busy(lab.character.person_id) and not actions.is_busy(lab.npc.person_id))
	lab.free()

func _check_failures_and_rest() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	_learn_original_npc(lab)
	_capture_original(lab)
	var actions: SitePersonActions = lab.site_controller.person_actions
	var tech_before := _technology_bytes(lab)
	for fault: String in ["guard_ko", "captive_ko", "guard_hit", "captive_hit", "guard_cell", "depot_cell", "episode", "holder", "stock", "materials", "allocation"]:
		assert(_begin(lab).ok, fault)
		_plan_step(lab, 108.0)
		var original_cell := lab.character.terrain_cell
		var original_depot := int(data.site.depot_cell)
		var original_relation: Dictionary = data.site.captivity[str(lab.npc.person_id)].duplicate(true)
		var original_holder := lab.npc.item_state
		var original_stock: Dictionary = data.site.inventory
		var wood := int(original_stock.wood)
		var original_combat_left := float(data.site.get("combat_left", 0.0))
		match fault:
			"guard_ko": lab.character.knockout_left = 1.0
			"captive_ko": lab.npc.knockout_left = 1.0
			"guard_hit": lab.character.apply_contact({"result": {"hp": 1.0, "stun": 0.0, "guard_break": false}, "shield": false})
			"captive_hit": lab.npc.apply_contact({"result": {"hp": 1.0, "stun": 0.0, "guard_break": false}, "shield": false})
			"guard_cell": assert(lab.character.place(Vector2i(8, 8), true))
			"depot_cell": data.site.depot_cell = data.index(Vector2i(9, 8))
			"episode": data.site.captivity[str(lab.npc.person_id)].episode = "different-original-episode"
			"holder": lab.npc.item_state = original_holder.duplicate(true)
			"stock": data.site.inventory = original_stock.duplicate(true)
			"materials": original_stock.wood = 0
			"allocation": data.item_transfer_guard = func(_source: Dictionary, _destination: Dictionary, _resources: Dictionary, _items: Array) -> Dictionary: return Runtime.fail("TEST_ALLOCATION")
		var before := var_to_bytes(data.site)
		var bow_count := _bows(data)
		var results := actions.settle_after_contacts()
		assert(results.size() == 1 and not results[0].ok, fault + ": " + str(results))
		assert(var_to_bytes(data.site) == before and _bows(data) == bow_count and lab.npc.captive, fault)
		assert(_technology_bytes(lab) == tech_before and not actions.is_busy(lab.character.person_id), fault)
		lab.character.knockout_left = 0.0
		lab.npc.knockout_left = 0.0
		assert(lab.character.place(original_cell, true))
		data.site.depot_cell = original_depot
		data.site.captivity[str(lab.npc.person_id)] = original_relation
		lab.npc.item_state = original_holder
		data.site.inventory = original_stock
		original_stock.wood = wood
		data.item_transfer_guard = Callable()
		# A real contact opens the original Site combat clock; restore it with the other fixture fields.
		data.site.combat_left = original_combat_left
	# A real original third Actor is a guard-side threat; captive's retained
	# faction alone must neither invent an enemy nor hide an actionable enemy.
	var enemy := TerrainTestCharacter.new()
	enemy.person_id = 993004
	enemy.data = data
	enemy.faction_id = 2
	enemy.item_state = Runtime.new_item_state("person:993004")
	lab.add_child(enemy)
	enemy.set_process(false)
	assert(enemy.place(Vector2i(8, 8), true))
	lab.combat_actors.append(enemy)
	assert(str(_begin(lab).code) == "THREAT")
	enemy.knockout_left = 30.0
	assert(_begin(lab).ok)
	_plan_step(lab, 108.0)
	enemy.knockout_left = 0.0
	var threatened := actions.settle_after_contacts()
	assert(threatened.size() == 1 and str(threatened[0].code) == "THREAT" and lab.npc.captive)
	lab.combat_actors.erase(enemy)
	enemy.free()
	assert(not actions.begin_captive_craft(lab.character.person_id, lab.npc.person_id, -1, "crossbow").ok)
	lab.npc.fatigue = 79.99
	lab.npc.work_resting = false
	assert(_begin(lab).ok)
	_plan_step(lab, 100.0)
	var partial := float(actions.job_for(lab.npc.person_id).elapsed)
	assert(partial > 0.0 and partial < 108.0 and str(actions.job_for(lab.npc.person_id).paused) == "REST")
	assert(lab.npc.work_resting and actions.captive_work_rest_allowed(lab.npc.person_id))
	assert(not actions.blocks_fatigue_rest(lab.npc.person_id) and not lab.npc.can_act())
	var bows := _bows(data)
	_plan_step(lab, 10.0)
	assert(is_equal_approx(float(actions.job_for(lab.npc.person_id).elapsed), partial) and _bows(data) == bows)
	var at_rest := lab.npc.fatigue
	# Idle recovery runs on the original shared step: its work plan keeps the REST
	# latch; a bare _advance_fatigue() call has no plan and parks the job CLOCK_NOT_READY.
	var speed := lab.simulation_speed
	lab.simulation_speed = TerrainLab.SIMULATION_SPEEDS[-1]
	var step := TerrainLab.EXCHANGE_ACTION_STEP if lab.exchange_enabled else TerrainLab.ACTION_STEP
	var rest_start := Runtime.now(data) * 60.0
	var rest_calls := 0
	while Runtime.now(data) * 60.0 - rest_start < 60.0 and rest_calls < 4000:
		rest_calls += 1
		var rest_step: Dictionary = lab._advance_original_shared_step(step)
		assert(bool(rest_step.get("ok", false)), str(rest_step))
	lab.simulation_speed = speed
	assert(lab.npc.fatigue < at_rest and lab.npc.work_resting and lab.npc.captive, "Original idle recovery must not see its legal guard as an enemy")
	# The adapter does not pretend to own complete idle recovery: fixture brings
	# the ORIGINAL pool to the 50 boundary while preserving the genuine latch.
	lab.npc.fatigue = 50.0
	_plan_step(lab, 1.0)
	assert(float(actions.job_for(lab.npc.person_id).elapsed) > partial and not lab.npc.work_resting)
	# Fatigue slowdown (original work_seconds) makes the remaining 108 s of work take
	# longer than 108 s; keep supplying original plan intervals until the job completes.
	var finish_steps := 0
	while float(actions.job_for(lab.npc.person_id).get("elapsed", 108.0)) < 108.0 - 0.00000001 and finish_steps < 4:
		finish_steps += 1
		_plan_step(lab, 108.0)
	var results := actions.settle_after_contacts()
	assert(results.size() == 1 and results[0].ok and lab.npc.captive and _bows(data) == bows + 1, str(results))
	assert(_technology_bytes(lab) == tech_before)
	lab.free()
	var novice_data := _building_fixture()
	var novice_lab := _building_lab(novice_data)
	novice_data.site.depot_cell = novice_data.index(Vector2i(9, 10))
	_capture_original(novice_lab)
	assert(str(_begin(novice_lab).code) == "NO_SKILL")
	novice_lab.free()

func _check_real_prison_authority() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var actions: SitePersonActions = lab.site_controller.person_actions
	var player_id := lab.character.person_id
	var team: TerrainArmy = lab.army
	team.roster_size = 3
	team.faction_id = lab.character.faction_id
	assert(team.deploy_at(data, null, null, [Vector2i(28, 30), Vector2i(29, 30), Vector2i(30, 30)]))
	assert(team.enable_combat(false))
	team.set_process(false)
	team.settle_combat_command()
	var warden := team.combat_identity(1)
	var placement := Runtime.building_cells(data, "settlement_center", Vector2i(20, 20), Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	assert(placement.ok and lab.character.place(Vector2i(26, 22), true))
	var cells: Array[int] = []
	cells.assign(placement.cells)
	var founded := Settlement.found(lab, player_id, cells, {"layout_version": 1, "quarter": 0}, Callable(), "原俘虜工坊驗收聚落")
	assert(founded.ok, str(founded))
	_complete_key(data, str(founded.feature))
	var prison_key := _formal_feature(data, "prison", Vector2i(35, 35))
	assert(Settlement.prison_governed(lab, prison_key))
	_learn_original_npc(lab)
	_capture_original(lab, Vector2i(35, 38), Vector2i(34, 38))
	assert(lab.site_controller.captive_escort.begin_prison(player_id, player_id, prison_key).ok)
	var slot: Dictionary = Runtime.prison_layout(data, prison_key).slots[0]
	for _frame: int in 3600:
		lab._advance_action_time(TerrainLab.ACTION_STEP)
		if lab.npc.terrain_cell == slot.cell and lab.character.terrain_cell == slot.contact_cell \
			and actions._prison_stopped(actions._person(lab.npc.person_id)) and actions._prison_stopped(actions._person(player_id)): break
	assert(lab.npc.terrain_cell == slot.cell and lab.character.terrain_cell == slot.contact_cell)
	if str(data.site.captivity[str(lab.npc.person_id)].get("prison_id", "")).is_empty():
		assert(actions.admit_prison(player_id, lab.npc.person_id, prison_key).ok)
	assert(lab.site_controller.captive_escort.cancel(player_id).ok)
	assert(actions.prison_slot(lab.npc.person_id).ok)
	# Physical fixture layout: existing camp at actual prison contact, no remote
	# materials or invented workshop/store owner. No active job is relocated.
	data.site.depot_cell = data.index(slot.contact_cell)
	var offices := Settlement.offices(lab)
	var prison_position := str(offices.duties["settlement.prison"])
	assert(Settlement.apply_office_plan(lab, player_id, int(offices.revision), [{"op": "appoint", "position_id": prison_position, "person_id": warden}]).ok)
	assert(str(_begin(lab).code) == "NO_AUTHORITY", "Original current warden defeats guard/faction-only authority")
	assert(Settlement.apply_office_plan(lab, player_id, int(Settlement.offices(lab).revision), [{"op": "dismiss", "position_id": prison_position}]).ok)
	var tech_before := _technology_bytes(lab)
	assert(_begin(lab).ok)
	_plan_step(lab, 108.0)
	var results := actions.settle_after_contacts()
	assert(results.size() == 1 and results[0].ok and lab.npc.captive and actions.prison_slot(lab.npc.person_id).ok, str(results))
	assert(_technology_bytes(lab) == tech_before)
	# True original release, not a fixture captive=false assignment.
	assert(actions.begin_prison_release(player_id, lab.npc.person_id).ok)
	actions.advance(4.0)
	results = actions.settle_after_contacts()
	assert(results.size() == 1 and results[0].ok and not lab.npc.captive, str(results))
	assert(str(_begin(lab).code) == "NO_AUTHORITY")
	assert(Technology.learned(lab.npc.technology, "F07"))
	assert(actions.begin_ranged_craft(lab.npc.person_id, "bow").ok)
	assert(actions.cancel(lab.npc.person_id).ok)
	lab.free()
	TerrainArmy.release_contact_source()

func _run() -> void:
	deadline = Time.get_ticks_msec() + 240000
	_check_field_production()
	_check_failures_and_rest()
	_check_real_prison_authority()
	print("SITE_T5_CAPTIVE_PRODUCTION_PASS genuine learned F07 + real capture/supply/escort/admission; supervised joint busy/fatigue, atomic paid original bow, no research evidence, late original source/authority failure, REST latch, original warden priority and actual release; complete collector/native/UI closure separate")
	quit(0)
