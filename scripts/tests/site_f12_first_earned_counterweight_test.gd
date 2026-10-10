extends "res://scripts/tests/site_family_first_earned_base.gd"
## Genuine ordinary traction completion precedes first counterweight research.
## Generated source parameters and sparse original state survive both cold loads.
## This local caller fixture excludes fixed World policy, UI, travel and Native.

func _earned_id() -> String:
	return "F12"

func _f12_lab() -> TerrainLab:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345, {"max_height": 1, "micro_strength": 0.0})
	Env.initialize(data, "f12-original-first-earned")
	for item: String in Env.ITEM_NAMES: data.site.inventory[item] = 10000
	data.site.capacity = 1000000
	var lab := TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.site_controller._auto_save_blocked = true
	lab.bind_terrain(data)
	lab.restore_only = false
	lab.simulation_speed = 4.0
	lab.character.faction_id = 1
	lab.npc.faction_id = 1
	_check(lab.character.place(data.spawn_cell, true), "Original Actor reaches the generated camp source")
	var npc_cell := Vector2i(-1, -1)
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var cell := data.spawn_cell + direction
		if data.contains(cell) and data.is_walkable(cell): npc_cell = cell; break
	_check(npc_cell.x >= 0 and lab.npc.place(npc_cell, true), "Second actual original Actor occupies a legal distinct generated cell")
	lab.site_controller.release_worker()
	return lab

func _f12_team(lab: TerrainLab) -> TerrainArmy:
	var cells: Array[Vector2i] = []
	for index: int in range(lab.terrain.flags.size()):
		var cell := lab.terrain.cell_from_index(index)
		if lab.terrain.is_walkable(cell) and not lab.site_controller.reserves_cell(cell): cells.append(cell)
		if cells.size() == 2: break
	_check(cells.size() == 2, "Generated source supplies two legal original Army deployment cells")
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = 301
	team.roster_size = 2
	team.faction_id = 1
	_check(team.deploy_at(lab.terrain, lab.character, lab.npc, cells) and team.enable_combat(false), "Original Army deployment creates real rows and original combat bodies")
	for row: Dictionary in team.combat_units:
		row.cargo = {}
		row.item_state = Runtime.new_item_state("person:" + str(row.person_id))
	lab.combat_armies.append(team)
	team.controlled_person_query = lab.controlled_person_id
	team.person_busy_query = lab.site_controller.person_actions.is_busy
	team.settle_combat_command()
	_check(team.set_duty_ai_enabled(team.combat_identity(team.formal_commander), true).ok
		and team.join_player(lab.character).ok, "Actual Actor legally joins the original duty-enabled team")
	return team

func _f12_geometry(lab: TerrainLab, team: TerrainArmy, kind: String) -> Dictionary:
	var data := lab.terrain
	var control := lab.controlled_person_id()
	for index: int in range(data.flags.size()):
		var anchor := data.cell_from_index(index)
		var proposed := {"kind": kind, "cell": index, "facing": [1, 0]}
		var slots := Runtime.siege_work_slots(data, proposed)
		if slots.size() != 4: continue
		var station := data.cell_from_index(int(slots[0].cell))
		var before := var_to_bytes([data.site, lab.site_controller.person_actions._jobs, lab.character.technology])
		var preview := Runtime.begin_siege_build(data, kind, anchor, Vector2i.RIGHT, int(team.team_id), control,
			lab.site_controller.reserves_cell, true)
		_check(var_to_bytes([data.site, lab.site_controller.person_actions._jobs, lab.character.technology]) == before,
			"Original prospective geometry remains pure for each real generated site candidate")
		if not preview.ok: continue
		_check(lab.character.place(station, true), "Actual named Actor occupies this pure original station")
		before = var_to_bytes([data.site, lab.site_controller.person_actions._jobs, lab.character.technology])
		preview = Runtime.begin_siege_build(data, kind, anchor, Vector2i.RIGHT, int(team.team_id), control,
			lab.site_controller.reserves_cell, true, {}, {}, control)
		_check(var_to_bytes([data.site, lab.site_controller.person_actions._jobs, lab.character.technology]) == before,
			"Actual named-person construction preview performs no payment or job publication")
		if preview.ok: return {"anchor": anchor, "facing": Vector2i.RIGHT, "team_id": int(team.team_id), "station": station}
	_check(false, "Original generated source must contain a legal full vehicle, crew and worksite footprint")
	return {}

func _f12_fixture() -> Dictionary:
	_check(bool(EarnedCatalog.get_node("F12").get("enabled", false)), "Separately admitted isolated positive Catalog is required")
	var lab := _f12_lab()
	var data := lab.terrain
	var team := _f12_team(lab)
	var control := lab.controlled_person_id()
	var refs: Array = []
	for person_id: int in [control, int(lab.npc.person_id), team.combat_identity(0), team.combat_identity(1)]:
		refs.append({"site_id": str(data.site.id), "person_id": person_id, "path": "", "label": "原配重首研人物", "age_years": -1})
	_check(lab.site_controller.family_continuity.register_members(refs, true, control).ok
		and lab.site_controller.family_continuity.appoint_head(control, control).ok, "Original registry and office establish the real Family")
	var actions = lab.site_controller.person_actions
	data.site.family = actions._technology_candidate()
	data.site.family.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.family.technology.known = ["F11"] # Explicit prerequisite only; no fabricated traction history or target skill.
	_check(Family.validate_family(data.site.family, str(data.site.id))
		and not Technology.family_traction_recorded(data.site.family.technology)
		and not Technology.learned(lab.character.technology, "F12"), "Strict Family has only prerequisite archive and no traction witness or F12 skill")
	var before := var_to_bytes([data.site, actions._jobs, lab.character.technology])
	var refused = actions.prepare_scope_technology(control, control, "F12")
	_check(not refused.ok and refused.code == "PREREQUISITE"
		and var_to_bytes([data.site, actions._jobs, lab.character.technology]) == before, "F11 archive alone cannot begin F12 or synthesize a traction receipt")
	return {"data": data, "lab": lab, "controller": lab.site_controller, "actions": actions, "team": team,
		"control": control, "family_id": str(data.site.family.family_id), "tech_id": "F12", "cold_count": 0}

func _f12_first_earned() -> void:
	var f := _f12_fixture()
	var ordinary := _f12_geometry(f.lab, f.team, "traction_trebuchet")
	var key := str(int(f.data.site.get("next_vehicle", 1)))
	var inventory: Dictionary = f.data.site.inventory.duplicate(true)
	var begun := Runtime.begin_siege_build(f.data, "traction_trebuchet", ordinary.anchor, ordinary.facing,
		int(f.team.team_id), int(f.control), f.controller.reserves_cell, false, {}, {}, int(f.control))
	_check(begun.ok and f.actions.is_busy(int(f.control)), "Original paid ordinary traction publishes the actual controlled construction job")
	for resource: String in Runtime.SIEGE_DEFINITIONS.traction_trebuchet.cost:
		_check(int(f.data.site.inventory[resource]) == int(inventory[resource]) - int(Runtime.SIEGE_DEFINITIONS.traction_trebuchet.cost[resource]),
			"Actual ordinary traction pays its full original material once: " + resource)
	await _earned_points(f)
	var traction: Dictionary = f.data.site.vehicles[key]
	var history: Array = f.data.site.family.technology.siege_history
	_check(traction.phase == "idle" and traction.build.is_empty() and history.size() == 1
		and history[0].vehicle_id == key and history[0].binding == "traction_build" and int(history[0].person_id) == int(f.control)
		and Technology.family_traction_recorded(f.data.site.family.technology), "Only true complete paid original traction supplies the required original named Family history")
	_check(not Technology.scope_known(f.data.site.family.technology, "F12") and not Technology.learned(f.lab.character.technology, "F12"),
		"Ordinary traction completion earns neither target project nor F12 skill")
	_check(f.lab.character.place(f.data.spawn_cell, true), "Actual grantor returns to original generated camp contact")
	_check(f.actions.prepare_scope_technology(int(f.control), int(f.control), "F12").ok, "Actual traction witness now admits first F12 preparation")
	var phase: Dictionary = EarnedCatalog.get_node("F12").research.routes[0].phases[0]
	var cap: Dictionary = phase.materials.duplicate(true)
	_check(f.actions.request_scope_technology_consent(int(f.control), "family", str(f.family_id), int(f.control)).ok
		and f.actions.grant_scope_technology_budget(int(f.control), "family", str(f.family_id), cap).ok, "Original executor consents to one finite full counterweight budget")
	var geometry := _f12_geometry(f.lab, f.team, "counterweight_trebuchet")
	key = str(int(f.data.site.next_vehicle))
	var target := "vehicle:" + key
	var request := {"anchor": geometry.anchor, "facing": geometry.facing, "team_id": geometry.team_id}
	var before := var_to_bytes([f.data.site, f.actions._jobs, f.lab.character.technology])
	var preview := Runtime.begin_technology_operation(f.data, _token(f.lab, int(f.control), target), true, request)
	_check(preview.ok and var_to_bytes([f.data.site, f.actions._jobs, f.lab.character.technology]) == before,
		"Actual original first counterweight preview is pure and uses the full original geometry")
	begun = f.actions.begin_scope_technology_phase(int(f.control), "family", str(f.family_id), "counterweight_build", target, request)
	_check(begun.ok and f.actions.is_busy(int(f.control)) and f.data.site.vehicles[key].build.total_work == 21600.0,
		"First genuine counterweight phase pays and publishes actual unchanged full-duration construction")
	await _earned_points(f, true)
	_check(f.actions.is_busy(int(f.control)) and float(f.data.site.vehicles[key].build.progress) > 0.0
		and not Technology.learned(f.lab.character.technology, "F12"), "Actual admitted positive prefix remains an incomplete original trial")
	_check(f.actions.cancel(int(f.control)).ok, "Original cancellation parks its actual paid vehicle job")
	var paid: Dictionary = _earned_project(f).budget.duplicate(true)
	var parked: Dictionary = f.data.site.vehicles[key].duplicate(true)
	await _earned_cold(f, false)
	_check(f.data.site.vehicles[key] == parked and f.data.site.family.technology.siege_history == history,
		"Cold original graph preserves the paid construction and genuine traction prerequisite history")
	begun = f.actions.begin_scope_technology_phase(int(f.control), "family", str(f.family_id), "counterweight_build", target)
	_check(begun.ok and begun.resumed and _earned_project(f).budget == paid,
		"Same cold purpose resumes real construction with no second materials, attempt or analysis allowance")
	await _earned_points(f)
	var vehicle: Dictionary = f.data.site.vehicles[key]
	var project: Dictionary = f.data.site.family.technology.projects[0]
	_check(vehicle.phase == "idle" and vehicle.build.is_empty() and not vehicle.has("tech_trial")
		and project.receipts.size() == 1 and project.budget.payments.size() == 1 and project.budget.spent == cap,
		"Full actual counterweight completion commits one physical vehicle and one balanced first-research payment")
	_check(float(project.receipts[0].work_seconds) + 0.00000001 >= 21600.0
		and int(project.receipts[0].person_id) == int(f.control)
		and f.data.site.family.technology.siege_history.size() == 2
		and Technology.scope_known(f.data.site.family.technology, "F12") and Technology.learned(f.lab.character.technology, "F12"),
		"The actual named original executor completes all 21600 required seconds before learning F12 exactly once")
	await _earned_cold(f, true)
	before = var_to_bytes([f.data.site, f.actions._jobs, f.lab.character.technology])
	var duplicate: Dictionary = f.actions.prepare_scope_technology(int(f.control), int(f.control), "F12")
	_check(not duplicate.ok and var_to_bytes([f.data.site, f.actions._jobs, f.lab.character.technology]) == before,
		"Cold completed first F12 cannot restart, repay or reteach")
	f.lab.queue_free()
	for team: TerrainArmy in f.lab.combat_armies:
		if is_instance_valid(team): team.queue_free()
	await process_frame
	await process_frame
	TerrainArmy.release_contact_source()

func _run() -> void:
	deadline = Time.get_ticks_msec() + 540000
	await _f12_first_earned()
	print("F12_ORIGINAL_FIRST_EARNED_TRACTION_COUNTERWEIGHT_SHARED_COLD_PASS checks=", checks,
		"; actual ordinary traction prerequisite, full 21600 named work, original cold/resume; fixed World policy/UI/travel/contact geometry/Native/full40 excluded")
	quit(0)
