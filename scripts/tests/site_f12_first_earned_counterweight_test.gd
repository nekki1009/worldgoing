extends "res://scripts/tests/site_settlement_first_earned_base.gd"
## Crowd port (2026-11-12): extends the settlement base for its crowd team/stand-still fixture helpers only.
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
	_check(_f12_place(lab, data.spawn_cell), "Original Actor reaches the generated camp source")
	var npc_cell := Vector2i(-1, -1)
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var cell := data.spawn_cell + direction
		if data.contains(cell) and data.is_walkable(cell): npc_cell = cell; break
	_check(npc_cell.x >= 0 and lab.npc.place(npc_cell, true), "Second actual original Actor occupies a legal distinct generated cell")
	lab.site_controller.release_worker()
	return lab

func _f12_team(lab: TerrainLab) -> TerrainArmy:
	var cells: Array[Vector2i] = []
	# Deploy beside the controlled Actor: a joined member counts as present only
	# within the formation's command radius.
	var origin: Vector2i = lab.character.terrain_cell
	for radius: int in range(1, 20):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if absi(x) + absi(y) != radius or cells.size() == 2: continue
				var cell := origin + Vector2i(x, y)
				if lab.terrain.contains(cell) and lab.terrain.is_walkable(cell) and not lab.site_controller.reserves_cell(cell): cells.append(cell)
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

var _f12_last_named := ""
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
		_check(_f12_place(lab, station), "Actual named Actor occupies this pure original station")
		if lab.crowd_site != null and lab.crowd_site.active:
			# Crowd: the controlled worker must stand ready on its station (a placement changes no velocity until real points).
			await _settlement_stand_still({"lab": lab, "data": data, "control": control}, "on the candidate station")
		before = var_to_bytes([data.site, lab.site_controller.person_actions._jobs, lab.character.technology])
		preview = Runtime.begin_siege_build(data, kind, anchor, Vector2i.RIGHT, int(team.team_id), control,
			lab.site_controller.reserves_cell, true, {}, {}, control)
		_check(var_to_bytes([data.site, lab.site_controller.person_actions._jobs, lab.character.technology]) == before,
			"Actual named-person construction preview performs no payment or job publication")
		if preview.ok: return {"anchor": anchor, "facing": Vector2i.RIGHT, "team_id": int(team.team_id), "station": station}
		_f12_last_named = str(preview).left(300) + " at " + str(station)
	var authority := ""
	if lab.crowd_site != null and lab.crowd_site.active:
		var physical: Variant = lab.crowd_site.person_owner(control)
		var original: Variant = physical._command_owner(physical.index_for_identity(control)) if physical != null else null
		authority = " order=%s physical_team=%s original=%s owns=%s duty=%s" % [str(physical.combat_order) if physical != null else "-", str(physical.team_id) if physical != null else "-",
			str(original.team_id) if original is TerrainArmy else str(original), str(lab.crowd_site.owns_original_team(original)) if original is TerrainArmy else "-",
			str(original.duty_resolve_readonly("team.work", physical)).left(300) if original is TerrainArmy else "-"]
	_check(false, "Original generated source must contain a legal full vehicle, crew and worksite footprint; last named preview: " + _f12_last_named + authority)
	return {}

func _f12_fixture() -> Dictionary:
	_check(bool(EarnedCatalog.get_node("F12").get("enabled", false)), "Separately admitted isolated positive Catalog is required")
	var lab := _f12_lab()
	var data := lab.terrain
	var team := _f12_team(lab)
	var control := lab.controlled_person_id()
	# The ordinary vehicle work admission needs the controlled person as the team's work head.
	var offices := team.team_offices()
	# 文武官 W2: a 文官 seat needs a 文吏 (a 武官 seat an officer); the fixture qualifies its holder first.
	team.set_civil_role(control, "clerk")
	_check(team.apply_office_plan(team.combat_identity(team.formal_commander), int(offices.revision), [{"op": "appoint", "position_id": str(offices.duties["team.work"]), "person_id": control}]).ok
		and team.duty_resolve_readonly("team.work", team).decider == control, "Actual living captain delegates team.work to the joined controlled Actor")
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
	# Crowd port (2026-11-12): the hand-built team with the joined Actor enters the native crowd as a legacy grid Site does
	# on bind (the settlement first-earned rule); --grid keeps the old path.
	if not OS.get_cmdline_user_args().has("--grid") and lab.crowd_site != null and not lab.crowd_site.active:
		var converted: Dictionary = lab.crowd_site.convert_existing()
		_check(converted.ok, "The original team and its Actor enter the native crowd: " + str(converted))
	return {"data": data, "lab": lab, "controller": lab.site_controller, "actions": actions, "team": team,
		"control": control, "family_id": str(data.site.family.family_id), "tech_id": "F12", "cold_count": 0}

## Crowd: before a named job the team stands beside the working head and settles by real points (settlement base rule).
func _f12_crowd_settle(f: Dictionary, label: String) -> void:
	if f.lab.crowd_site == null or not f.lab.crowd_site.active: return
	_settlement_team_with_actor(f, [])
	await _settlement_stand_still(f, label)
	# The settle centre beside the head can fall on the built engine; native set_goal snaps the HOLD goal to the nearest
	# walkable route cell while the centre stays, so the team would later walk there and void the research consent. The
	# fixture settles the team around the snapped goal instead.
	var owner: Variant = f.lab.crowd_site.person_owner(int(f.control))
	var settled: Dictionary = f.lab.crowd_site.formation_state(int(owner.formation_index))
	if absf(float(settled.goal_x) - float(settled.cx)) > 0.01 or absf(float(settled.goal_y) - float(settled.cy)) > 0.01:
		_settlement_centre = Vector2i(floori(float(settled.goal_x)), floori(float(settled.goal_y)))
		await _settlement_stand_still(f, label + " (around the restored formation goal)")

func _f12_first_earned() -> void:
	var f := _f12_fixture()
	await _f12_crowd_settle(f, "before the ordinary geometry scan")
	var ordinary: Dictionary = await _f12_geometry(f.lab, f.team, "traction_trebuchet")
	var key := str(int(f.data.site.get("next_vehicle", 1)))
	var inventory: Dictionary = f.data.site.inventory.duplicate(true)
	var begun := Runtime.begin_siege_build(f.data, "traction_trebuchet", ordinary.anchor, ordinary.facing,
		int(f.team.team_id), int(f.control), f.controller.reserves_cell, false, {}, {}, int(f.control))
	_check(begun.ok and f.actions.is_busy(int(f.control)), "Original paid ordinary traction publishes the actual controlled construction job: " + str(begun).left(300))
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
	_check(_f12_camp_contact(f.lab), "Actual grantor returns to original generated camp contact")
	await _f12_crowd_settle(f, "at the camp contact")
	_check(f.actions.prepare_scope_technology(int(f.control), int(f.control), "F12").ok, "Actual traction witness now admits first F12 preparation")
	var phase: Dictionary = EarnedCatalog.get_node("F12").research.routes[0].phases[0]
	var cap: Dictionary = phase.materials.duplicate(true)
	_check(f.actions.request_scope_technology_consent(int(f.control), "family", str(f.family_id), int(f.control)).ok
		and f.actions.grant_scope_technology_budget(int(f.control), "family", str(f.family_id), cap).ok, "Original executor consents to one finite full counterweight budget")
	var geometry: Dictionary = await _f12_geometry(f.lab, f.team, "counterweight_trebuchet")
	key = str(int(f.data.site.next_vehicle))
	var target := "vehicle:" + key
	var request := {"anchor": geometry.anchor, "facing": geometry.facing, "team_id": geometry.team_id}
	var before := var_to_bytes([f.data.site, f.actions._jobs, f.lab.character.technology])
	var preview := Runtime.begin_technology_operation(f.data, _token(f.lab, int(f.control), target), true, request)
	_check(preview.ok and var_to_bytes([f.data.site, f.actions._jobs, f.lab.character.technology]) == before,
		"Actual original first counterweight preview is pure and uses the full original geometry: " + str(preview).left(300))
	begun = f.actions.begin_scope_technology_phase(int(f.control), "family", str(f.family_id), "counterweight_build", target, request)
	_check(begun.ok and f.actions.is_busy(int(f.control)) and f.data.site.vehicles[key].build.total_work == 21600.0,
		"First genuine counterweight phase pays and publishes actual unchanged full-duration construction: " + str(begun).left(300))
	await _earned_points(f, true)
	_check(f.actions.is_busy(int(f.control)) and float(f.data.site.vehicles[key].build.progress) > 0.0
		and not Technology.learned(f.lab.character.technology, "F12"), "Actual admitted positive prefix remains an incomplete original trial")
	_check(f.actions.cancel(int(f.control)).ok, "Original cancellation parks its actual paid vehicle job")
	var paid: Dictionary = _earned_project(f).budget.duplicate(true)
	var parked: Dictionary = f.data.site.vehicles[key].duplicate(true)
	await _earned_cold(f, false)
	_check(f.data.site.vehicles[key] == parked and f.data.site.family.technology.siege_history == history,
		"Cold original graph preserves the paid construction and genuine traction prerequisite history")
	await _f12_crowd_settle(f, "before the resumed counterweight phase")
	begun = f.actions.begin_scope_technology_phase(int(f.control), "family", str(f.family_id), "counterweight_build", target)
	_check(begun.ok and begun.resumed and _earned_project(f).budget == paid,
		"Same cold purpose resumes real construction with no second materials, attempt or analysis allowance")
	if f.lab.crowd_site != null and f.lab.crowd_site.active:
		_check(f.actions.is_busy(int(f.control)), "Crowd: the resumed counterweight job is the controlled worker's live job: " + str(begun).left(300))
	await _earned_points(f)
	var vehicle: Dictionary = f.data.site.vehicles[key]
	var project: Dictionary = f.data.site.family.technology.projects[0]
	_check(vehicle.phase == "idle" and vehicle.build.is_empty() and not vehicle.has("tech_trial")
		and project.receipts.size() == 1 and project.budget.payments.size() == 1 and project.budget.spent == cap,
		"Full actual counterweight completion commits one physical vehicle and one balanced first-research payment: phase=%s build=%s receipts=%d payments=%d spent=%s busy=%s" % [str(vehicle.get("phase")),
			str(vehicle.get("build", {})).left(200), project.receipts.size(), project.budget.payments.size(), str(project.budget.spent), str(f.actions.is_busy(int(f.control)))])
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


## The joined Actor is present (and keeps any delegated office) only within the
## formation's command radius; the fixture keeps the small team beside it.
func _f12_place(lab: TerrainLab, cell: Vector2i) -> bool:
	if lab.crowd_site != null and lab.crowd_site.active:
		return lab.character.place(cell, true) and _earned_crowd_place(lab, int(lab.controlled_person_id()), cell)
	# Move the team beside the target first, so none of it stands on the target cell.
	for team: TerrainArmy in lab.combat_armies:
		if int(team.team_id) != 301: continue
		var used := {cell: true}
		for index: int in team.combat_units.size():
			if not team.is_member(index): continue
			var placed := false
			for radius: int in range(7, 9): # Clear of a whole engine footprint/crew, still within the command radius.
				for y: int in range(-radius, radius + 1):
					for x: int in range(-radius, radius + 1):
						if placed or absi(x) + absi(y) != radius: continue
						var near := cell + Vector2i(x, y)
						if used.has(near) or not lab.terrain.contains(near) or not lab.terrain.is_walkable(near) or lab.site_controller.reserves_cell(near): continue
						team.cells[index] = near
						team.moving_to[index] = TerrainArmy.INVALID_CELL
						used[near] = true
						placed = true
	if not lab.character.place(cell, true): return false
	for team: TerrainArmy in lab.combat_armies:
		if int(team.team_id) == 301: team._refresh_reference_presence()
	return true


## Camp contact is a walkable side cell of the depot (the depot cell itself is not adjacent).
func _f12_camp_contact(lab: TerrainLab) -> bool:
	var depot: Vector2i = lab.terrain.cell_from_index(int(lab.terrain.site.depot_cell))
	for side: Vector2i in TerrainData.DIRECTIONS:
		var cell := depot + side
		if lab.terrain.contains(cell) and lab.terrain.is_walkable(cell) and lab.terrain.can_step(cell, depot) and _f12_place(lab, cell): return true
	return false
