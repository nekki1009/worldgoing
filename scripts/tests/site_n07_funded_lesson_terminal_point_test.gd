extends "res://scripts/tests/site_technology_nation_material_test.gd"
const SiteFamilyContinuity = preload("res://scripts/terrain_lab/site_family_continuity.gd") # D/Tech declare no global class_name for it.
## First N07 is absent; F07 teacher/Family and unrelated institutional archives
## are explicit strict starting prerequisites, not N07 research/birth evidence.

func _building_fixture() -> TerrainData:
	var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 18373, {"size": Vector2i(96, 96), "max_height": 0})
	SiteEnvironment.initialize(data, "nation_n07_earned_generated")
	# Finite original setup supplies for original paid existing buildings only.
	data.site.inventory = {"wood": 200, "stone": 200, "clay": 40, "tools": 4, "grain": 10}
	data.site.capacity = 800
	for y: int in range(8, 52):
		for x: int in range(8, 52):
			for key: String in data.resources_at.get(data.index(Vector2i(x,y)), []): SiteEnvironment.change(data,key,{"cleared":true,"remaining":0})
	SiteEnvironment.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)
	return data # No terrain/soil/water/fixed-base field writes.


func _earned_place(f: Dictionary, identity: int, cell: Vector2i) -> void:
	# SAME original GD hot person fixture endpoint, excludes navigation proof.
	var team: TerrainArmy = f.team
	var index: int = team.index_for_identity(identity)
	assert(index >= 0 and f.data.is_walkable(cell) and team.moving_to[index] == TerrainArmy.INVALID_CELL)
	for at: int in team.cells.size(): assert(at == index or team.cells[at] != cell)
	for actor: TerrainTestCharacter in f.lab.combat_actors: assert(actor.person_id == identity or actor.terrain_cell != cell)
	team.cells[index] = cell
	team.combat_slots[index] = cell
	team._rebuild_ground_cell_owners()
	team.settle_combat_command()


func _run() -> void:
	deadline = Time.get_ticks_msec()+120000
	_check_actual_completed_lesson_candidate_forgeries()
	var f: Dictionary = _nation_fixture(["N01","N02"])
	var data: TerrainData = f.data
	var actual_lab: TerrainLab = f.lab
	var actions: SitePersonActions = f.actions
	var orders: SiteEquipmentOrders = f.orders
	var teacher: int = int(f.control)
	var students: Array[int] = [f.team.combat_identity(0),f.team.combat_identity(1)]
	var refs: Array = []
	for identity: int in [teacher,students[0],students[1]]:
		refs.append({"site_id":str(data.site.id),"person_id":identity,"path":"","label":"原國家兩有限技藝名額","age_years":-1})
	assert(actual_lab.site_controller.family_continuity.register_members(refs,true,teacher).ok)
	assert(actual_lab.site_controller.family_continuity.appoint_head(teacher,teacher).ok)
	data.site.family = actions._technology_candidate()
	data.site.family.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.family.technology.known = ["F07"] # Named prior cold teaching archive.
	actual_lab.character.technology = {"version":1,"learned":["F07"]} # Named existing actual teacher, not the earned target.
	assert(SiteFamilyContinuity.validate_family(data.site.family,str(data.site.id)) and Technology.valid_person(actual_lab.character.technology))
	var nation: Dictionary = data.site.equipment_nations.n1
	assert(not Technology.scope_known(nation.technology,"N07"))
	assert(actions.prepare_scope_technology(teacher,teacher,"N07","n1").ok, "True original first N07 prepare, never initial known")
	var opened: Dictionary = orders.request_funded_course(teacher,"n1",str(f.warehouse),teacher,students,"F07")
	assert(opened.ok,str(opened))
	var order_id: String = str(opened.order_id)
	var reserve: Dictionary = _fund(actual_lab,order_id,{"grain":4},str(f.warehouse))
	var order: Dictionary = nation.technology_operations.public_orders[order_id]
	assert(order.payload.source.cap == {"grain":4} and order.payload.source.spent == {"grain":4} and int(reserve.cargo.get("grain",0)) == 4, "Original donor funds only these finite two seats into actual Warehouse")
	var teacher_cargo: int = int(actions._person(teacher).cargo.get("grain",0))
	var inventory: Dictionary = data.site.inventory.duplicate(true)
	var next_item: int = int(data.site.next_item)
	var elapsed: Array = []
	for at: int in students.size():
		var identity: int = students[at]
		var camp: Vector2i = data.cell_from_index(int(data.site.depot_cell))
		for other: int in students:
			if other != identity: _earned_place(f,other,camp+Vector2i(0,3+students.find(other)))
		_earned_place(f,identity,camp)
		assert(not Technology.learned(f.team.combat_units[f.team.index_for_identity(identity)].get("technology",{}),"F07"))
		var before: PackedByteArray = var_to_bytes([data.site,actual_lab.character.capture_state(),f.team.capture_combat_state()])
		var refused: Dictionary = orders.begin_funded_course(identity,"n1",order_id,identity)
		assert(not refused.ok and refused.code == "NO_AUTHORITY" and var_to_bytes([data.site,actual_lab.character.capture_state(),f.team.capture_combat_state()]) == before, "Actual control restriction before stipend/job mutation")
		var started: Dictionary = orders.begin_funded_course(teacher,"n1",order_id,identity)
		assert(started.ok,str(started))
		assert(not Technology.scope_known(nation.technology,"N07") if at == 0 else Technology.scope_known(nation.technology,"N07"), "Only true first completed original course may earn institution")
		elapsed.append(_earned_component_job(actual_lab,teacher,"technology_lesson"))
		assert(Technology.learned(f.team.combat_units[f.team.index_for_identity(identity)].get("technology",{}),"F07") and Technology.scope_known(nation.technology,"N07"))
		assert(int(reserve.cargo.get("grain",0)) == 4-2*(at+1) and int(actions._person(teacher).cargo.get("grain",0)) == teacher_cargo+2*(at+1), "Exactly two true grain per actual completed original 300s lesson")
		before = var_to_bytes([data.site,actual_lab.character.capture_state(),f.team.capture_combat_state()])
		assert(not orders.begin_funded_course(teacher,"n1",order_id,identity).ok and var_to_bytes([data.site,actual_lab.character.capture_state(),f.team.capture_combat_state()]) == before, "Same accepted seat cannot replay payment/learning/research")
	assert(order.status == "complete" and order.receipts.size() == 2 and int(data.site.next_item) == next_item and data.site.inventory == inventory)
	var project: Dictionary = nation.technology.projects[0]
	assert(project.closed and project.receipts.size() == 1 and project.budget.payments.size() == 1 and project.budget.cap == {"grain":4} and project.budget.spent == {"grain":2}, "C45 requires one first true funded course; second ordinary seat uses same finite original order, never fake second research phase")
	_earned_cold(actual_lab,"n1","N07","funded_course")
	print("N07_FUNDED_LESSON_TRUE_POINT_TERMINAL_PASS: named prior F07 master/archive; never initial N07; one actual first phase plus remaining ordinary seat; original two students/300 each/2 grain each/private finite source; true NoCombat original shared ACTION_STEP joint pool/clock/payment/oncecompletion plus pure terminal source component/rejection; cold/rebind/replay; not Native/FULL40/default-policy")
	actual_lab.free()
	quit(0)
func _nation_fixture(known: Array[String]) -> Dictionary:
	var data := _building_fixture()
	var warehouse := _formal_feature(data, "warehouse", Vector2i(13, 13))
	var home := _formal_feature(data, "house", Vector2i(13, 18), Vector2i(2, 2))
	var smithy := _formal_feature(data, "smithy", Vector2i(25, 18))
	# Initial generated fixture places camp next to the actual Warehouse door.
	# This is not a runtime camp relocation, public treasury, or cost bypass.
	var stock_door: Vector2i = data.cell_from_index(int(data.site.features[warehouse].entrance))
	var initial_camp: Vector2i = stock_door + Vector2i.RIGHT
	assert(data.is_walkable(initial_camp) and data.can_step(initial_camp, stock_door))
	data.site.depot_cell = data.index(initial_camp)
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var orders: SiteEquipmentOrders = controller.equipment_orders
	var control := lab.controlled_person_id()
	var team := _army(lab, data)
	var executor := team.combat_identity(1)
	var row: Dictionary = team.combat_units[1]
	var center := Runtime.building_cells(data, "settlement_center", Vector2i(18, 10), Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	_check(center.ok, "Original geometry admits this true settlement center")
	var center_cells: Array[int] = []
	center_cells.assign(center.cells)
	var founded := Settlement.found(lab, control, center_cells)
	_check(founded.ok, "Original founder/office transaction creates the actual Settlement")
	_complete_key(data, str(founded.feature))
	var lodging := Runtime.house_layout(data, home)
	data.site.housing = {str(executor): {"version": 1, "house_id": home, "cell": int(lodging.slots[0])}}
	_check(Homes.validate(data, data.site, {executor: {"hp": float(row.hp), "faction_id": 1}}).ok and Settlement.residents(lab).has(executor), "Explicit initial housing references a real living NPC and real completed house, using the true Housing validator")
	var settlement_tech := Technology.empty_scope_record(str(data.site.id))
	settlement_tech.known = ["S01", "S06", "S09", "S13"]
	data.site.settlement.version = 2 # Strict optional-technology packet, not v1 with extra fields.
	data.site.settlement.technology = settlement_tech
	var nation_tech := Technology.empty_scope_record(str(data.site.id))
	nation_tech.known = known.duplicate()
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", control), "members": [control, executor, team.combat_identity(0)], "standards": {}, "technology": nation_tech}}
	_check(Stocks.ensure_storage(data, warehouse, 1).ok, "Original Warehouse owns its actual cargo and holder")
	var entrance := data.cell_from_index(int(data.site.features[warehouse].entrance))
	_check(lab.character.place(entrance, true), "Actual donor reaches the original Warehouse contact")
	var labor := orders.register_nation_labor(control, "n1", [executor])
	_check(labor.ok, "Actual national duty registers this real housed NPC after its real team accepts the finite purpose: " + str(labor))
	return {"data": data, "lab": lab, "warehouse": warehouse, "smithy": smithy, "controller": controller,
		"actions": actions, "orders": orders, "control": control, "team": team, "executor": executor, "row": row,
		"labor": labor, "nation_tech": nation_tech, "entrance": entrance}

func _earned_component_job(actual_lab: TerrainLab, identity: int, kind: String) -> float:
	var actions: SitePersonActions = actual_lab.site_controller.person_actions
	var orders: SiteEquipmentOrders = actual_lab.site_controller.equipment_orders
	var job: Dictionary = actions._jobs.get(actions._job_key_for(identity), {})
	assert(not job.is_empty() and job.kind == kind and job.kind == "technology_lesson" and is_equal_approx(float(job.duration),300.0))
	var before: PackedByteArray = var_to_bytes([actual_lab.terrain.site, actual_lab.character.capture_state(), actions._person(int(job.target_id)).body])
	var source: Dictionary = orders.prepare_funded_course_source(str(job.nation_course_nation),str(job.nation_course_id),job)
	assert(source.ok and orders.validate_funded_course_source(source).ok and var_to_bytes([actual_lab.terrain.site,actual_lab.character.capture_state(),actions._person(int(job.target_id)).body]) == before, "Source-only candidate keeps all actual owners byte equivalent")
	assert(not actions._prepare_technology_lesson_completion(job).ok and float(job.elapsed) == 0.0, "A prospective held source never invents completed300 seconds, student skill or receipt")
	var guard: Callable = actual_lab.terrain.item_transfer_guard
	actual_lab.terrain.item_transfer_guard = func(_s:Dictionary,_d:Dictionary,_r:Dictionary,_i:Array)->Dictionary:return Runtime.fail("TEST_STIPEND")
	var rejected: Dictionary = orders.prepare_funded_course_source(str(job.nation_course_nation),str(job.nation_course_id),job)
	assert(not rejected.ok and rejected.code == "TEST_STIPEND" and var_to_bytes([actual_lab.terrain.site,actual_lab.character.capture_state(),actions._person(int(job.target_id)).body]) == before, "Original item guard refuses before clock/material/knowledge mutation")
	actual_lab.terrain.item_transfer_guard = guard
	var teacher: Dictionary = actions._person(identity)
	var student: Dictionary = actions._person(int(job.target_id))
	var teacher_fatigue: float = float(actions._body_get(teacher,"fatigue"))
	var student_fatigue: float = float(actions._body_get(student,"fatigue"))
	var elapsed: float = 0.0
	var game_seconds: float = 0.0
	var points: int = 0
	var source_seen: bool = false
	while actions.is_busy(identity):
		assert(Time.get_ticks_msec()<deadline and points<5000)
		var old: float = float(job.elapsed)
		var window: float = Runtime.game_seconds(TerrainLab.ACTION_STEP,float(actual_lab.terrain.site.get("combat_left",0.0)))*actual_lab.simulation_speed
		if 300.0-old<=window+PersonFatigue.WORK_PLAN_EPS:
			var requests: Array[Dictionary] = actions.work_requests(window)
			var state_before: PackedByteArray = var_to_bytes([actual_lab.terrain.site,actual_lab.character.capture_state(),actions._person(int(job.target_id)).body])
			var captured: Dictionary = actions.prepare_gd_contact_job_prefix(requests,window)
			assert(captured.ok and orders.validate_funded_course_source(captured.prepared.held[str(identity)].funded_source).ok)
			assert(actions.gd_contact_job_person_ready(identity) and actions.gd_contact_job_person_ready(int(job.target_id)))
			assert(var_to_bytes([actual_lab.terrain.site,actual_lab.character.capture_state(),actions._person(int(job.target_id)).body])==state_before,"True held terminal source capture is pure; no earned state/cost is published")
			actions.finish_gd_contact_job_prefix()
			source_seen = true
		var point: Dictionary = actual_lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		assert(point.ok and float(point.get("game_seconds",0.0))>0.0, "True original whole shared point advances the real joint lesson: "+str(point))
		game_seconds += float(point.game_seconds)
		points += 1
		elapsed += (float(job.elapsed)-old) if actions.is_busy(identity) else (300.0-old)
	assert(source_seen and elapsed>=300.0-0.0001 and game_seconds>=300.0-0.0001 and points>1)
	assert(float(actions._body_get(actions._person(identity),"fatigue"))>teacher_fatigue and float(actions._body_get(actions._person(int(job.target_id)),"fatigue"))>student_fatigue, "Both original fatigue pools receive full real joint effort")
	assert(not orders.validate_funded_course_source(source).ok, "Actual one payment makes the held source stale; it cannot replay")
	return elapsed

func _earned_cold(actual_lab: TerrainLab, nation_id: String, technology_id: String, label: String) -> void:
	var controller: SiteController = actual_lab.site_controller
	assert(controller._capture_for_save().ok, "Actual original Actor/Army/vehicle/item owners capture")
	var before: String = JSON.stringify(actual_lab.terrain.site.equipment_nations[nation_id], "", true, true)
	var source_fingerprint: String = actual_lab.terrain.fingerprint()
	var path: String = "user://nation_"+label+"_first_earned_"+str(Time.get_ticks_usec())+".json"
	controller.save_path = path
	assert(controller.save_to(path).ok, "Original strict Store saves completed actual source, not a minimal/erased pin")
	var read: Dictionary = SiteStore.load_site(path)
	assert(read.ok, "True original generated source/strict technology/operations/ship cold reader: "+str(read))
	assert(JSON.stringify(read.data.site.equipment_nations[nation_id], "", true, true) == before, "True cold read keeps exact accepted owner history and knowledge")
	var loaded: Dictionary = controller.load_from(path)
	assert(loaded.ok and actual_lab.terrain.fingerprint() == source_fingerprint, "Actual Controller rebind preserves original generated terrain/source: "+str(loaded))
	assert(JSON.stringify(actual_lab.terrain.site.equipment_nations[nation_id], "", true, true) == before and SiteTechnology.scope_known(actual_lab.terrain.site.equipment_nations[nation_id].technology, technology_id), "Original load/bind neither reissues nor discards earned owner state")
	assert(FileAccess.file_exists(path), "Good original cold file persists")

func _army(lab: TerrainLab, data: TerrainData) -> TerrainArmy:
	assert(is_same(lab.terrain,data))
	return _material_army(lab,2) # Original allocator and SAME actual Actor/NPC refs.

func _check_actual_completed_lesson_candidate_forgeries() -> void:
	# Separate honest component boundary: original joint requests/pool debit/
	# PA.advance produce a genuinely due300s job, without settling it. It does
	# not claim World/Region/contact clock publication. No elapsed/receipt writes.
	var f: Dictionary = _nation_fixture(["N01","N02"])
	var actual_lab: TerrainLab = f.lab
	var actions: SitePersonActions = f.actions
	var orders: SiteEquipmentOrders = f.orders
	var teacher: int = int(f.control)
	var student: int = f.team.combat_identity(0)
	var refs: Array = []
	for identity: int in [teacher,student,f.team.combat_identity(1)]:
		refs.append({"site_id":str(f.data.site.id),"person_id":identity,"path":"","label":"原完成候選純邊界","age_years":-1})
	assert(actual_lab.site_controller.family_continuity.register_members(refs,true,teacher).ok)
	assert(actual_lab.site_controller.family_continuity.appoint_head(teacher,teacher).ok)
	f.data.site.family=actions._technology_candidate()
	f.data.site.family.technology=Technology.empty_scope_record(str(f.data.site.id))
	f.data.site.family.technology.known=["F07"] # Named prior archive, never N07 earned target.
	actual_lab.character.technology={"version":1,"learned":["F07"]}
	assert(actions.prepare_scope_technology(teacher,teacher,"N07","n1").ok)
	var opened: Dictionary=orders.request_funded_course(teacher,"n1",str(f.warehouse),teacher,[student,f.team.combat_identity(1)],"F07")
	assert(opened.ok,str(opened))
	_fund(actual_lab,str(opened.order_id),{"grain":4},str(f.warehouse))
	var camp: Vector2i=f.data.cell_from_index(int(f.data.site.depot_cell))
	_earned_place(f,f.team.combat_identity(1),camp+Vector2i(0,4))
	_earned_place(f,student,camp)
	assert(orders.begin_funded_course(teacher,"n1",str(opened.order_id),student).ok)
	var job: Dictionary=actions._jobs[str(teacher)]
	for tick: int in range(400):
		if float(job.elapsed)>=300.0-PersonFatigue.WORK_PLAN_EPS:break
		var requests: Array[Dictionary]=actions.work_requests(30.0)
		var plan: Dictionary=PersonFatigue.plan_work_interval(requests,30.0)
		assert(plan.ok)
		actual_lab._shared_work_plan=plan
		actual_lab._shared_work_pools_committed=false
		actual_lab.site_controller._shared_work_plan=plan
		actual_lab._advance_fatigue(30.0)
		actual_lab._clear_shared_work_step()
	assert(float(job.elapsed)==float(job.duration) and actions.is_busy(teacher))
	var prepared: Dictionary=actions._prepare_technology_lesson_completion(job)
	assert(prepared.ok and actions._validate_technology_lesson_completion(prepared).ok and not prepared.funding.phase.is_empty())
	var before: PackedByteArray=var_to_bytes([f.data.site,actual_lab.character.capture_state(),f.team.capture_combat_state()])
	var forged: Dictionary=prepared.duplicate(false)
	forged.state=prepared.state.duplicate(true)
	forged.state.known.append("F14")
	assert(Technology.valid_family_tech(forged.state) and not actions._validate_technology_lesson_completion(forged).ok)
	assert(var_to_bytes([f.data.site,actual_lab.character.capture_state(),f.team.capture_combat_state()])==before,"Schema-valid unrelated family knowledge cannot replace this lesson candidate")
	forged=prepared.duplicate(false)
	forged.funding=prepared.funding.duplicate(false)
	forged.funding.phase=prepared.funding.phase.duplicate(false)
	forged.funding.phase.state=prepared.funding.phase.state.duplicate(true)
	forged.funding.phase.state.known.append("N12")
	assert(Technology.valid_scope_record(forged.funding.phase.state,"nation") and not actions._validate_technology_lesson_completion(forged).ok)
	assert(var_to_bytes([f.data.site,actual_lab.character.capture_state(),f.team.capture_combat_state()])==before,"Schema-valid unrelated Scope knowledge cannot impersonate the true course event")
	forged=prepared.duplicate(false)
	forged.funding=prepared.funding.duplicate(false)
	forged.funding.phase=prepared.funding.phase.duplicate(false)
	forged.funding.phase.person_candidate=Technology.learned_candidate(actual_lab.character.technology,"F04")
	assert(not forged.funding.phase.person_candidate.is_empty() and not actions._validate_technology_lesson_completion(forged).ok)
	assert(var_to_bytes([f.data.site,actual_lab.character.capture_state(),f.team.capture_combat_state()])==before,"Institutional course cannot inject another personal skill")
	assert(actions._validate_technology_lesson_completion(prepared).ok)
	actions._publish_technology_lesson_completion(prepared)
	assert(Technology.learned(actions._body_get(actions._person(student),"technology"),"F07") and Technology.scope_known(f.data.site.equipment_nations.n1.technology,"N07"))
	assert(actions.cancel(teacher).ok and not orders.validate_funded_course_source(prepared.funding.payment.course_source).ok)
	actual_lab.free()
