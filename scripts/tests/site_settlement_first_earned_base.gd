extends "res://scripts/tests/site_family_first_earned_base.gd"
## True unknown Settlement research through public PA commands and the actual
## local TerrainLab shared caller. Physical fixture station placement excludes
## travel; fixed land/Native/performance acceptance remain separate.
const EarnedSettlement = preload("res://scripts/terrain_lab/site_settlement.gd")

func _settlement_earned_id() -> String:
	return ""

func _settlement_points(f: Dictionary, partial: bool = false) -> void:
	var points = 0
	while f.actions.is_busy(int(f.control)):
		_check(Time.get_ticks_msec() < deadline and points < 10000, "Original productive points stay within the real deadline")
		var accepted: Dictionary = f.lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		_check(accepted.get("ok", false) and accepted.get("completed", false)
			and float(accepted.get("action_seconds", 0.0)) > 0.0
			and float(accepted.get("action_seconds", 0.0)) <= TerrainLab.ACTION_STEP + 0.00000001
			and float(accepted.get("game_seconds", 0.0)) > 0.0, "Original body/work/supply/contact caller accepts one bounded point: " + str(accepted))
		points += 1
		if partial and points >= 8: return
		if points % 64 == 0: await process_frame

func _settlement_fixture() -> Dictionary:
	var identity = _settlement_earned_id()
	_check(identity in ["S07", "S08", "S09", "S10"], "This fixture names one concrete target")
	var data = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345)
	Env.initialize(data, "settlement-first-earned-natural-" + identity)
	for material: String in Env.ITEM_NAMES: data.site.inventory[material] = 10000
	data.site.capacity = 1000000
	var lab = _earned_natural_lab(data)
	lab.restore_only = false
	lab.simulation_speed = 4.0
	var control = lab.controlled_person_id()
	var actions: SitePersonActions = lab.site_controller.person_actions
	_check(lab.character.place(data.cell_from_index(int(data.site.depot_cell)), true), "Actual Actor stands at the original camp source contact")
	var placement = _settlement_center_placement(data)
	_check(placement.ok, "Original planner supplies the true settlement center footprint")
	var cells: Array[int] = []
	cells.assign(placement.cells)
	var founded = EarnedSettlement.found(lab, control, cells)
	_check(founded.ok, "Original controlled founder establishes the current Settlement head: " + str(founded))
	_complete_key(data, str(founded.feature))
	data.site.worker.cell = int(data.site.depot_cell) # Explicit idle original fixture worker at its real generated camp.
	var team = _settlement_natural_team(lab, data)
	_check(team.join_player(lab.character).ok, "Original living Army accepts the existing Actor without spawning another person")
	var offices: Dictionary = team.team_offices()
	var appointment = team.apply_office_plan(team.combat_identity(team.formal_commander), int(offices.revision), [
		{"op": "add", "name": "原施工主持", "office_class": "civil", "ref": "earned_work"},
		{"op": "appoint", "position_id": "earned_work", "person_id": control},
		{"op": "assign", "position_id": "earned_work", "duty_id": "team.work"}])
	_check(appointment.ok and int(team.duty_resolve_readonly("team.work").get("decider", -1)) == control,
		"Living original captain explicitly delegates work; no controlled switching or fake head")
	var refs: Array = []
	for person_id: int in [control, int(lab.npc.person_id)]:
		refs.append({"site_id": str(data.site.id), "person_id": person_id, "path": "", "label": "原具名工人", "age_years": -1})
	_check(lab.site_controller.family_continuity.register_members(refs, true, control).ok
		and lab.site_controller.family_continuity.appoint_head(control, control).ok, "Original Family registration establishes any real prerequisite archive")
	# Upgrade only this explicitly registered prerequisite-bearing fixture using
	# the original pure candidate. Never graft technology onto strict Family v2.
	data.site.family = actions._technology_candidate()
	_check(Family.validate_family(data.site.family, str(data.site.id)), "Original strict Family v3 with stable ID remains valid")
	if identity == "S09":
		# A version-1 family record admits only F07 as known (Technology.IDS). The F10 prerequisite archive needs the
		# scope record that holds any family node, as an accepted F10 family would have.
		data.site.family.technology = Technology.empty_scope_record(str(data.site.id))
		data.site.family.technology.known = ["F10"] # Explicit prerequisite archive, never the tested target.
		_check(Family.validate_family(data.site.family, str(data.site.id)), "The F10 prerequisite archive keeps the strict family valid")
	var settlement: Dictionary = data.site.settlement
	if identity in ["S08", "S10"]:
		settlement.version = 2
		settlement.technology = Technology.empty_scope_record(str(data.site.id))
		settlement.technology.known = ["S07" if identity == "S08" else "S09"]
	var keys: Dictionary = {}
	if identity == "S07": keys.smithy = _settlement_completed_host(data, "smithy")
	if identity == "S08":
		# A genuine original ordinary completed/damaged ballista is an explicit
		# physical starting-world fixture, not a researched output or skill grant.
		var built = _settlement_ordinary_ballista(lab, team, control)
		_check(built.ok, "Original ordinary owner builds the fixture target: " + str(built))
		keys.ballista = str(built.vehicle)
		var vehicle: Dictionary = data.site.vehicles[keys.ballista]
		var slot: Dictionary = Runtime.siege_work_slots(data, vehicle)[0]
		_check(Runtime.advance_siege_work(data, keys.ballista, "construct", 5400.0, data.cell_from_index(int(slot.cell)), 0, int(team.team_id)).ok
			and Runtime.damage_siege_vehicle(data, keys.ballista, 40.0).ok, "Original ordinary physical target completes then receives real damage")
	_check(EarnedSettlement.status(lab).effective, "Current original center/head/faction make this Settlement effective")
	_check(not Technology.scope_known(settlement.get("technology", {}), identity)
		and not Technology.learned(lab.character.technology, identity), "Target starts unknown and is never injected into a person")
	return {"data": data, "lab": lab, "controller": lab.site_controller, "actions": actions, "team": team,
		"control": control, "settlement_id": str(settlement.settlement_id), "keys": keys, "tech_id": identity, "cold_count": 0,
		"initial_kits": int(data.site.inventory.get("ballista_spares", 0))}

func _settlement_f07_prerequisite(f: Dictionary) -> void:
	var contact_ok := _earned_depot_contact(f.lab)
	_check(contact_ok, "Original future workshop operator reaches the real F07 trial contact")
	if not contact_ok: _earned_authorization_failed = true; return
	var prepared: Dictionary = f.actions.prepare_technology(int(f.control), int(f.control))
	var consent: Dictionary = f.actions.request_technology_consent(int(f.control), int(f.control)) if prepared.ok else {"ok":false,"code":"NOT_RUN"}
	var grant: Dictionary = f.actions.grant_technology_budget(int(f.control), {"wood": 12, "fiber": 6}) if prepared.ok and consent.ok else {"ok":false,"code":"NOT_RUN"}
	if not prepared.ok or not consent.ok or not grant.ok: _earned_grant_failure(f.lab, "family", prepared, consent, grant)
	_check(prepared.ok and consent.ok and grant.ok, "Original F07 first research has finite source and genuine consent")
	if not prepared.ok or not consent.ok or not grant.ok: _earned_authorization_failed = true; return
	for index: int in 3:
		_check(f.actions.begin_technology_trial(int(f.control), int(f.control)).ok, "Original F07 trial explicitly starts")
		await _settlement_points(f)
		_check(Technology.stages(f.data.site.family.technology.projects[0], {"site_id": str(f.data.site.id), "person_id": int(f.control)}, f.data.site.family.technology.get("person_links", [])) == index + 1,
			"Each actual completed bow teaches one original prerequisite trial")
	_check(Technology.scope_known(f.data.site.family.technology, "F07") and Technology.learned(f.lab.character.technology, "F07"), "Real three bow trials establish the actual workshop operator prerequisite")

func _settlement_project(f: Dictionary) -> Dictionary:
	return Technology.active_project(f.data.site.settlement.technology)

func _settlement_token(f: Dictionary, target: String) -> Dictionary:
	var record: Dictionary = f.data.site.settlement.technology
	var project = _settlement_project(f)
	var phase = Technology.scope_next_phase(project, project.executor)
	return {"scope": "settlement", "scope_id": str(f.settlement_id), "project_id": int(project.id), "epoch": int(record.epoch),
		"purpose": str(project.purpose), "tech_id": str(project.tech_id), "phase_id": str(phase.id), "attempt": int(project.next_attempt),
		"person": project.executor.duplicate(), "binding": str(phase.binding), "target_id": target, "materials": phase.materials.duplicate(true)}

func _settlement_target(f: Dictionary, phase: Dictionary) -> Dictionary:
	var binding = str(phase.binding)
	if binding == "workshop_bow":
		var key = str(f.keys.smithy)
		_check(f.lab.character.place(f.data.cell_from_index(int(f.data.site.features[key].entrance)), true), "Actual workshop operator reaches the original smithy entrance")
		_settlement_team_with_actor(f)
		return {"target": "feature:" + key, "work_target": {}}
	if binding == "spares":
		# Manual craft needs the craftsman one legal step beside the camp, not on the camp cell.
		var camp: Vector2i = f.data.cell_from_index(int(f.data.site.depot_cell))
		var contact := Vector2i(-1, -1)
		for side: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
			var cell: Vector2i = camp + side
			if contact.x < 0 and f.data.contains(cell) and f.data.is_walkable(cell) and int(f.data.feature_at[f.data.index(cell)]) == 0 and f.data.can_step(cell, camp): contact = cell
		_check(contact.x >= 0 and f.lab.character.place(contact, true), "Actual craftsman reaches the original camp source contact")
		_settlement_team_with_actor(f)
		return {"target": "depot", "work_target": {}}
	if binding == "spare_repair":
		var key = str(f.keys.ballista)
		var slots = Runtime.siege_work_slots(f.data, f.data.site.vehicles[key])
		_check(not slots.is_empty() and f.lab.character.place(f.data.cell_from_index(int(slots[0].cell)), true), "Actual repair operator reaches one real original ballista work slot")
		_settlement_team_with_actor(f)
		return {"target": "vehicle:" + key, "work_target": {}}
	return _settlement_natural_geometry(f, binding)

# The Actor works as a member of its original team, which accompanies it: team
# consent counts only members present within command radius. Explicit fixture
# stations beside the Actor, then a real command event (unchanged tactical-AI
# confirmation) refreshes presence. Travel is covered by the movement tests.
## `avoid`: cell indexes the team must not stand on (an unbuilt footprint the Actor is about to work on).
func _settlement_team_with_actor(f: Dictionary, avoid: Array = []) -> void:
	var team: TerrainArmy = f.team
	var data: TerrainData = f.data
	var actor_cell: Vector2i = f.lab.character.terrain_cell
	var taken: Array[Vector2i] = [actor_cell]
	for index: int in team.combat_units.size():
		if not team.is_member(index) or team.member_gone(index): continue
		_check(team.moving_to[index] == TerrainArmy.INVALID_CELL, "No committed step survives an explicit team fixture station")
		var station := Vector2i(-1, -1)
		for radius: int in range(1, 6):
			for y: int in range(-radius, radius + 1):
				for x: int in range(-radius, radius + 1):
					if station.x >= 0 or absi(x) + absi(y) != radius: continue
					var cell := actor_cell + Vector2i(x, y)
					if not data.contains(cell) or not data.is_walkable(cell) or int(data.feature_at[data.index(cell)]) != 0 or f.controller.reserves_cell(cell) or cell in taken or avoid.has(data.index(cell)): continue
					var occupied: bool = f.lab.npc != null and f.lab.npc.terrain_cell == cell
					for other: int in team.cells.size(): occupied = occupied or other != index and team.cells[other] == cell
					if not occupied: station = cell
		_check(station.x >= 0, "A free natural station exists beside the working Actor for each original team member")
		if station.x < 0: return
		taken.append(station)
		team.cells[index] = station
		team.combat_slots[index] = station
	team._rebuild_ground_cell_owners()
	team.set_tactical_ai_enabled(team.current_commander, team.tactical_ai_enabled)
	_check(team._member_can_serve(TerrainArmy.PLAYER_MEMBER), "The working Actor stays present with its accompanying original team")

func _settlement_cold(f: Dictionary, complete: bool) -> void:
	var old_data: TerrainData = f.data
	var actor: TerrainTestCharacter = f.lab.character
	var old_owner: Dictionary = old_data.site.settlement
	var prior: Dictionary = old_owner.technology.duplicate(true)
	var fingerprint = old_data.fingerprint()
	var conditions = _earned_source_bytes(old_data)
	var personal: Dictionary = actor.technology.duplicate(true)
	var cargo: Dictionary = f.actions._person(int(f.control)).cargo.duplicate(true)
	var ammo: Dictionary = actor.ammo_inventory.duplicate(true)
	# Under an isolated --crowd-test run the Controller admits saves only inside its own crowd_test save root.
	var save_dir: String = str(f.controller.save_root) if not str(f.controller.crowd_test_run_id).is_empty() else "user://"
	var path = save_dir.path_join("settlement_first_earned_" + str(f.tech_id) + "_" + str(f.cold_count) + "_" + str(Time.get_ticks_usec()) + ".json")
	f.controller.save_path = path
	var saved: Dictionary = f.controller.save_to(path)
	_check(saved.ok, "Actual Controller captures original bodies and strict Store saves the real paid project: " + str(saved))
	var restored: Dictionary = f.controller.load_from(path)
	_check(restored.ok and not is_same(f.lab.terrain, old_data), "Actual Controller cold load binds a distinct graph: " + str(restored))
	f.data = f.lab.terrain
	f.actions = f.controller.person_actions
	f.team = f.actions._technology_team(f.actions._person(int(f.control)))
	f.cold_count += 1
	_check(is_same(f.lab.character, actor) and int(f.lab.controlled_person_id()) == int(f.control)
		and actor.technology == personal and f.actions._person(int(f.control)).cargo == cargo
		and actor.ammo_inventory == ammo, "Original Actor reuse preserves personal knowledge, true person cargo and ammunition separately")
	_check(not is_same(f.data.site.settlement, old_owner) and f.data.site.settlement.technology == prior
		and str(f.data.site.settlement.settlement_id) == str(f.settlement_id), "Distinct cold Settlement preserves original ID/purpose/payment/attempt/receipt history")
	_check(f.data.fingerprint() == fingerprint and _earned_source_bytes(f.data) == conditions, "Original natural source and five land-condition arrays survive cold without a fixture-only patch")
	_check(Technology.scope_known(f.data.site.settlement.technology, str(f.tech_id)) == complete
		and not Technology.learned(actor.technology, str(f.tech_id)), "Settlement knowledge never fabricates an individual skill")

func _settlement_earned() -> void:
	var f = _settlement_fixture()
	var identity = str(f.tech_id)
	var before = var_to_bytes([f.data.site, f.lab.character.technology, f.actions._jobs])
	if not bool(EarnedCatalog.get_node(identity).get("enabled", false)):
		var disabled: Dictionary = f.actions.prepare_scope_technology(int(f.control), int(f.control), identity, str(f.settlement_id))
		_check(not disabled.ok and disabled.code == "UNIMPLEMENTED" and var_to_bytes([f.data.site, f.lab.character.technology, f.actions._jobs]) == before,
			"Disabled target refuses before allocating a project/job/payment/product/knowledge")
		_cleanup_fixture(f.lab, f.team)
		await process_frame
		print(identity, "_ORIGINAL_SETTLEMENT_FIRST_EARNED_DISABLED_PASS checks=", checks)
		return
	if identity == "S07": await _settlement_f07_prerequisite(f)
	if _earned_authorization_failed: return
	var contact_ok := _earned_depot_contact(f.lab)
	_check(contact_ok, "Original head explicitly reaches the finite camp grant source")
	if not contact_ok: _earned_authorization_failed = true; return
	var prepared: Dictionary = f.actions.prepare_scope_technology(int(f.control), int(f.control), identity, str(f.settlement_id))
	if not prepared.ok: _earned_grant_failure(f.lab, "settlement", prepared, {"code":"NOT_RUN"}, {"code":"NOT_RUN"})
	_check(prepared.ok, "Public original command prepares an unknown Settlement target")
	if not prepared.ok: _earned_authorization_failed = true; return
	var cap: Dictionary = {}
	var count = 0
	for phase: Dictionary in EarnedCatalog.get_node(identity).research.routes[0].phases:
		count += int(phase.repeat)
		for resource: String in phase.materials: cap[resource] = int(cap.get(resource, 0)) + int(phase.materials[resource]) * int(phase.repeat)
	var consent: Dictionary = f.actions.request_scope_technology_consent(int(f.control), "settlement", str(f.settlement_id), int(f.control))
	var grant: Dictionary = f.actions.grant_scope_technology_budget(int(f.control), "settlement", str(f.settlement_id), cap) if consent.ok else {"ok":false,"code":"NOT_RUN"}
	if not consent.ok or not grant.ok: _earned_grant_failure(f.lab, "settlement", prepared, consent, grant)
	_check(consent.ok and grant.ok, "Actual team/head/person approve this purpose and exact finite cumulative budget")
	if not consent.ok or not grant.ok: _earned_authorization_failed = true; return
	var sequence = 0
	var cold_done = false
	while not _settlement_project(f).is_empty():
		var project = _settlement_project(f)
		var phase = Technology.scope_next_phase(project, project.executor)
		var selection = _settlement_target(f, phase)
		var token = _settlement_token(f, str(selection.target))
		before = var_to_bytes([f.data.site, f.lab.character.technology, f.actions._jobs])
		var foreign = token.duplicate(true)
		foreign.person.person_id = int(f.lab.npc.person_id)
		_check(not Runtime.begin_technology_operation(f.data, foreign, true, selection.work_target).ok
			and var_to_bytes([f.data.site, f.lab.character.technology, f.actions._jobs]) == before, "Borrowed person cannot approve, pay or earn this original project")
		var preview = Runtime.begin_technology_operation(f.data, token, true, selection.work_target)
		_check(preview.ok and var_to_bytes([f.data.site, f.lab.character.technology, f.actions._jobs]) == before, "True operation previews the same source/station without any effects: " + str(preview))
		var started: Dictionary = f.actions.begin_scope_technology_phase(int(f.control), "settlement", str(f.settlement_id), str(phase.binding), str(selection.target), selection.work_target)
		_check(started.ok and f.actions.is_busy(int(f.control)), "Public phase command publishes one actual original held job: " + str(started))
		var geometry = str(phase.binding) in ["house_build", "wall_build", "stairs_build"]
		if not cold_done and phase.binding != "spares":
			await _settlement_points(f, true)
			_check(f.actions.is_busy(int(f.control)) and not Technology.scope_known(f.data.site.settlement.technology, identity), "A positive actual prefix cannot grant target knowledge")
			_check(f.actions.cancel(int(f.control)).ok, "Original cancellation parks the paid target without a refund")
			var paid: Dictionary = _settlement_project(f).budget.duplicate(true)
			var attempt = int(_settlement_project(f).next_attempt)
			var retained: Dictionary = (f.data.site.vehicles[str(selection.target).trim_prefix("vehicle:")] if phase.binding == "spare_repair" else f.data.site.features[str(selection.target).trim_prefix("feature:")]).duplicate(true)
			await _settlement_cold(f, false)
			var current: Dictionary = f.data.site.vehicles[str(selection.target).trim_prefix("vehicle:")] if phase.binding == "spare_repair" else f.data.site.features[str(selection.target).trim_prefix("feature:")]
			_check(current == retained, "Cold parked actual target retains its exact paid geometry/production/repair state")
			started = f.actions.begin_scope_technology_phase(int(f.control), "settlement", str(f.settlement_id), str(phase.binding), str(selection.target))
			_check(started.ok and started.resumed and f.actions.is_busy(int(f.control)) and _settlement_project(f).budget == paid
				and int(_settlement_project(f).next_attempt) == attempt, "Cold paid resume actually republishes the SAME job with no second payment/attempt")
			cold_done = true
		await _settlement_points(f)
		var historical: Dictionary = f.data.site.settlement.technology.projects[0]
		_check(historical.receipts.size() == sequence + 1 and historical.budget.payments.size() == sequence + 1, "Each actual phase commits one original payment and receipt")
		var receipt: Dictionary = historical.receipts[sequence]
		_check(receipt.site_id == project.executor.site_id and int(receipt.person_id) == int(f.control) and receipt.phase_id == phase.id
			and float(receipt.work_seconds) + 0.00000001 >= float(phase.seconds), "Only the true named participant receives the full original phase work receipt")
		if geometry:
			var feature: Dictionary = f.data.site.features[str(selection.target).trim_prefix("feature:")]
			_check(feature.stage == "complete" and not feature.has("tech_trial"), "Original geometry actually completes before Settlement knowledge")
		elif phase.binding == "workshop_bow":
			var output: Dictionary = f.data.site.features[str(f.keys.smithy)].technology_output.receipts[0]
			_check(output.item_ids.size() == 1 and f.data.site.item_records[str(output.item_ids[0])].definition == "weapon:bow_01", "Original ItemSeq creates the actual workshop bow")
		elif phase.binding == "spares": _check(int(f.data.site.inventory.get("ballista_spares", 0)) == int(f.initial_kits) + 1, "Original camp owner creates exactly one actual spare kit")
		else: _check(is_equal_approx(float(f.data.site.vehicles[str(f.keys.ballista)].hp), float(Runtime.SIEGE_DEFINITIONS.ballista.max_hp) - 20.0)
			and f.data.site.vehicles[str(f.keys.ballista)].repair.is_empty() and int(f.data.site.inventory.get("ballista_spares", 0)) == int(f.initial_kits), "Actual kit is consumed once for the true 20HP/300-second repair")
		sequence += 1
	_check(cold_done and sequence == count and Technology.scope_known(f.data.site.settlement.technology, identity)
		and not Technology.learned(f.lab.character.technology, identity), "All genuine Settlement phases earn knowledge once without teaching a person an institution")
	var completed: Dictionary = f.data.site.settlement.technology.projects[0]
	_check(completed.budget.spent == cap and completed.budget.payments.size() == count, "All actual full materials balance the finite original budget exactly once")
	await _settlement_cold(f, true)
	before = var_to_bytes([f.data.site, f.lab.character.technology, f.actions._jobs])
	var duplicate: Dictionary = f.actions.prepare_scope_technology(int(f.control), int(f.control), identity, str(f.settlement_id))
	_check(not duplicate.ok and var_to_bytes([f.data.site, f.lab.character.technology, f.actions._jobs]) == before, "Cold completed first research cannot be replayed, repaid or duplicated")
	_cleanup_fixture(f.lab, f.team)
	await process_frame
	print(identity, "_ORIGINAL_SETTLEMENT_FIRST_EARNED_SHARED_COLD_PASS checks=", checks)

func _run() -> void:
	deadline = Time.get_ticks_msec() + 210000
	await _settlement_earned()
	quit(1 if _earned_authorization_failed else 0)

func _settlement_center_placement(data: TerrainData) -> Dictionary:
	var camp = data.cell_from_index(int(data.site.depot_cell))
	var options = {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	for index: int in range(data.size.x * data.size.y):
		var anchor = data.cell_from_index(index)
		var shape = Runtime.building_cells(data, "settlement_center", anchor, Vector2i(5, 5), options)
		if not shape.ok or EarnedSettlement._distance_to_rect(Runtime._cell_bounds(data, shape.cells), camp) > EarnedSettlement.radius(1): continue
		var preview = Runtime.preview_build(data, "settlement_center", shape.cells, Callable(), options)
		if preview.ok and preview.get("clearing", []).is_empty(): return shape
	_check(false, "Original generated camp must have one naturally legal center within its real level-one jurisdiction")
	return {}

func _settlement_natural_team(lab: TerrainLab, data: TerrainData) -> TerrainArmy:
	var camp = data.cell_from_index(int(data.site.depot_cell))
	var cells: Array[Vector2i] = []
	for index: int in range(data.size.x * data.size.y):
		var cell = data.cell_from_index(index)
		if absi(cell.x - camp.x) + absi(cell.y - camp.y) > 4 or not data.is_walkable(cell) or lab.site_controller.reserves_cell(cell): continue
		cells.append(cell)
		if cells.size() == 2: break
	_check(cells.size() == 2, "Two distinct natural original NPC stations exist")
	var team = TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = 301
	team.roster_size = 2
	team.faction_id = 1
	_check(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false), "Original Army owner initializes its finite two real NPCs")
	for row: Dictionary in team.combat_units:
		row.cargo = {}
		row.item_state = Runtime.new_item_state("person:" + str(row.person_id))
	lab.combat_armies.append(team)
	team.controlled_person_query = lab.controlled_person_id
	team.person_busy_query = lab.site_controller.person_actions.is_busy
	team.settle_combat_command()
	_check(team.set_duty_ai_enabled(team.combat_identity(team.formal_commander), true).ok, "Actual original captain explicitly enables duty AI")
	return team

func _settlement_completed_host(data: TerrainData, kind: String) -> String:
	var options = {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	for index: int in range(data.size.x * data.size.y):
		var anchor = data.cell_from_index(index)
		var shape = Runtime.building_cells(data, kind, anchor, Vector2i.ONE, options)
		if not shape.ok: continue
		var local = true
		for value: int in shape.cells: local = local and EarnedSettlement.cell_in_jurisdiction(data, data.cell_from_index(value))
		if not local: continue
		var preview = Runtime.preview_build(data, kind, shape.cells, Callable(), options)
		if not preview.ok or not preview.get("clearing", []).is_empty(): continue
		var key = _formal_feature(data, kind, anchor, Vector2i.ONE, options)
		data.site.worker.cell = int(data.site.depot_cell)
		return key
	_check(false, "Finite natural scan supplies the actual original qualified Settlement host")
	return ""

func _settlement_ordinary_ballista(lab: TerrainLab, team: TerrainArmy, control: int) -> Dictionary:
	var data = lab.terrain
	for index: int in range(data.size.x * data.size.y):
		var anchor = data.cell_from_index(index)
		var proposed = {"kind": "ballista", "cell": index, "facing": [1, 0]}
		var local = true
		for cell: Vector2i in Runtime.siege_cells(data, proposed): local = local and EarnedSettlement.cell_in_jurisdiction(data, cell)
		if not local: continue
		var preview = Runtime.begin_siege_build(data, "ballista", anchor, Vector2i.RIGHT, int(team.team_id), control, lab.site_controller.reserves_cell, true)
		if preview.ok: return Runtime.begin_siege_build(data, "ballista", anchor, Vector2i.RIGHT, int(team.team_id), control, lab.site_controller.reserves_cell)
	_check(false, "Natural Settlement source supplies a genuine ordinary paid ballista fixture")
	return {}

func _settlement_natural_geometry(f: Dictionary, binding: String) -> Dictionary:
	var data: TerrainData = f.data
	var kind = "house" if binding == "house_build" else "stone_wall" if binding == "wall_build" else "wall_stairs"
	var options = {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	var target = "feature:" + str(int(data.site.next_feature))
	for index: int in range(data.size.x * data.size.y):
		var anchor = data.cell_from_index(index)
		if binding == "stairs_build" and anchor != f.keys.wall_anchor + Vector2i.DOWN: continue
		var shape = Runtime.building_cells(data, kind, anchor, Vector2i.ONE, options)
		if not shape.ok: continue
		var cells: Array[int] = []
		cells.assign(shape.cells)
		var local = true
		for value: int in cells: local = local and EarnedSettlement.cell_in_jurisdiction(data, data.cell_from_index(value))
		if not local: continue
		if binding == "wall_build":
			# The actual wall remains unbuilt. These are finite true ground facts
			# for its subsequent adjacent original stair; no hypothetical feature
			# is adopted, and the later stair still needs a fresh real preview.
			for offset: int in [1, 2, 3]:
				var next = anchor + Vector2i(0, offset)
				local = local and data.contains(next) and data.is_walkable(next)
				if not local: break
				local = local and int(data.height_levels[data.index(next)]) == int(data.height_levels[index]) and int(data.foundation[data.index(next)]) >= 35
			if not local: continue
		var preview = Runtime.preview_build(data, kind, cells, f.controller.reserves_cell, options, {}, {"token": _settlement_token(f, target)})
		if not preview.ok or not preview.get("clearing", []).is_empty(): continue
		_check(f.lab.character.place(data.cell_from_index(int(preview.entrance)), true), "Actual Actor reaches this pure original natural geometry station")
		_settlement_team_with_actor(f, cells) # the team stands clear of the footprint it is about to build
		if binding == "wall_build": f.keys.wall_anchor = anchor
		return {"target": target, "work_target": {"cells": cells, "options": options}}
	_check(false, "Original natural scan finds the legal current Settlement trial geometry")
	return {}
