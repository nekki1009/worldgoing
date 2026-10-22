extends "res://scripts/tests/site_n04_workshop_earned_test.gd"
## Genuine first N05: real ordinary sample/certificate, real military funding,
## real Scope manufacture, real transfer of its specific bow to camp, and the
## original appearance-checked five-second equipment exchange. No fake output.

func _military_earned_fixture() -> Dictionary:
	var data := _building_fixture()
	var home := _formal_feature(data, "house", Vector2i(13, 18), Vector2i(2, 2))
	var smithy := _formal_feature(data, "smithy", Vector2i(25, 18))
	var lab := _building_lab(data)
	var team := _army(lab, data)
	var control := int(lab.controlled_person_id())
	var executor := team.combat_identity(1)
	var row: Dictionary = team.combat_units[1]
	var actions = lab.site_controller.person_actions
	var orders = lab.site_controller.equipment_orders
	_check(team.join_player(lab.character).ok, "Original living captain admits the actual controlled Actor through the true Army owner")
	# The logistics post is a military office (office_class rules): its holder must be an officer.
	# The original role writer may seat a new officer in a vacant cadre post; the plan moves that
	# member to logistics in one whole-plan revision.
	var promoted: Dictionary = team.set_military_role(control, "officer")
	_check(promoted.ok, "Original role writer makes the actual controlled member an officer: " + str(promoted))
	var offices := team.team_offices()
	var ops: Array = []
	var seated: Dictionary = SiteOffices.position_of(offices, control)
	if not seated.is_empty(): ops.append({"op": "dismiss", "position_id": str(seated.id)})
	ops.append({"op": "appoint", "position_id": str(offices.duties["team.logistics"]), "person_id": control})
	var delegated: Dictionary = team.apply_office_plan(team.combat_identity(team.formal_commander), int(offices.revision), ops)
	_check(delegated.ok and str(SiteOffices.position_of(team.team_offices(), control).get("id", "")) == str(offices.duties["team.logistics"]),
		"Actual living original captain delegates only the existing logistics office to the actual member: " + str(delegated))
	var center := Runtime.building_cells(data, "settlement_center", Vector2i(18, 10), Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	var cells: Array[int] = []
	cells.assign(center.cells)
	var founded := Settlement.found(lab, control, cells)
	_check(center.ok and founded.ok, "Original founder creates the actual settlement center")
	_complete_key(data, str(founded.feature))
	var lodging := Runtime.house_layout(data, home)
	data.site.housing = {str(executor): {"version": 1, "house_id": home, "cell": int(lodging.slots[0])}}
	_check(Homes.validate(data, data.site, {executor: {"hp": float(row.hp), "faction_id": 1}}).ok, "The real original NPC has legitimate original housing")
	data.site.settlement.version = 2
	data.site.settlement.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.settlement.technology.known = ["S07"]
	row.technology = Technology.learned_candidate({}, "F07")
	var nation := {"offices": SiteOffices.default_offices("nation", control), "members": [control, executor], "standards": {},
		"technology": Technology.empty_scope_record(str(data.site.id))}
	nation.technology.known = ["N04"]
	data.site.equipment_nations = {"n1": nation}
	_check(bool(NationCatalog.get_node("N05").get("enabled", false)) and Settlement.status(lab).effective and Technology.valid_person(row.technology),
		"Only legitimate N04/S07/personal F07 inputs exist; the isolated N05 test starts unknown")
	_check(orders.set_nation_culture(control, "n1", "chinese").ok, "The true current original cultural duty explicitly fixes the real equipment culture")
	var f := {"data": data, "lab": lab, "team": team, "control": control, "executor": executor, "row": row,
		"actions": actions, "orders": orders, "smithy": smithy, "feature": data.site.features[smithy]}
	_check(Runtime.request_feature_recipe(data, smithy, "bow", 1).ok and Runtime.operate_feature(data, smithy).ok,
		"Existing ordinary S07 recipe and original work-zone APIs start a true sample operation")
	var workers = lab.site_controller.work_team
	var sample_workers: Array[int] = [executor] # WorkTeam.assign takes a typed Array[int].
	_check(workers.assign(team, sample_workers, team.duty_decider("team.work")).ok, "Actual original work duty assigns the real ordinary sample producer")
	workers.prepare_work_requests(30.0)
	var task: Dictionary = row.work_task
	_check(task.get("target") == "feature:" + smithy and task.get("action") == "operate", "Original WT selector chooses the genuine workshop task")
	# The ordinary (version 2) WorkTeam task re-plans travel from the worker's real position on every
	# prepare, so a direct hot-cell write does not hold. Let the worker walk on original shared steps.
	var walk_step := TerrainLab.EXCHANGE_ACTION_STEP if lab.exchange_enabled else TerrainLab.ACTION_STEP
	var walk_calls := 0
	while str(task.get("mode", "")) != "work" and walk_calls < 3000:
		walk_calls += 1
		var walked: Dictionary = lab._advance_original_shared_step(walk_step)
		if not walked.get("ok", false): break
		task = row.work_task
	_check(str(task.get("mode", "")) == "work" and str(task.get("target", "")) == "feature:" + smithy, "The real worker reaches the genuine workshop slot on original shared steps")
	var next_item := int(data.site.next_item)
	var points := 0
	while int(data.site.next_item) == next_item and points < 10:
		_workshop_named_point(f, 30.0)
		points += 1
	_check(points < 10 and data.site.item_records[str(next_item)].definition == "weapon:bow_01"
		and f.feature.technology_output.receipts[0].item_ids == [str(next_item)], "True original work creates the real certification sample and current exact8 producer receipt")
	if workers.is_assigned(executor): _check(workers.cancel(executor).ok, "Original WT releases the genuine ordinary sample task")
	workers.discard_prepared_interval()
	Runtime._stop_feature_zones(data, smithy, "operate")
	_check(Runtime.request_feature_recipe(data, smithy, "", 1).ok and Stocks.set_local_supply(data, smithy, true, 1).ok,
		"The idle true original workshop chooses its existing localstock owner")
	_check(orders.certify_workshop(control, "n1", "cert", smithy, "S07", int(f.feature.technology_output.receipts[0].id)).ok,
		"Legitimate known N04 certifies only the actual sample; no fake fixture certificate")
	_check(orders.set_standard(control, "n1", "bow_line", "原有限弓標準", {"weapon": {"definition": "weapon:bow_01", "alternatives": []}}).ok,
		"Original national standard names the original admitted bow definition")
	# The sample walk left the executor outside the NPC captain's command radius; the team consent
	# needs a present member, so it walks back to the captain's reference on real route edges.
	var exec_index: int = team.index_for_identity(executor)
	if not bool(team.combat_hot_get(exec_index, &"present", false)) and team.command_reference_valid:
		var back: Array[Vector2i] = []
		for direction: Vector2i in TerrainData.DIRECTIONS:
			back = team._find_local_route(team.cells[exec_index], Vector2i(team.command_reference) + direction * 2, 256, false, exec_index)
			if not back.is_empty(): break
		_check(not back.is_empty() and back[0] == team.cells[exec_index], "Original executor route back to the captain retains its source vertex")
		for edge: int in range(1, back.size()):
			var reserved: bool = team._reserve_combat_step(exec_index, back[edge])
			_check(reserved, "Original Army admits each genuine executor movement edge")
			if not reserved: break
			var landing := 0
			while team.moving_to[exec_index] != TerrainArmy.INVALID_CELL and landing < 600:
				lab._advance_action_time(TerrainLab.ACTION_STEP)
				landing += 1
		team._refresh_command_presence()
	_check(bool(team.combat_hot_get(exec_index, &"present", false)), "The executor is present under the unchanged ordinary-member rule before the team consent")
	_check(actions.prepare_scope_technology(control, executor, "N05", "n1").ok and actions.request_scope_technology_consent(control, "nation", "n1", executor).ok,
		"The true national research duty and NPC team explicitly accept first N05")
	var before := var_to_bytes([data.site, row])
	_check(not orders.request_military_production_order(control, "n1", "cert", executor, control, "bow_line").ok and var_to_bytes([data.site, row]) == before,
		"Unknown first research cannot substitute another actual recipient for its original maker")
	var requested = orders.request_military_production_order(control, "n1", "cert", executor, executor, "bow_line")
	var other = orders.request_military_production_order(control, "n1", "cert", executor, executor, "bow_line")
	_check(requested.ok and other.ok, "Original finite production map admits actual named orders; an unfunded second order grants no source authority")
	f.order_id = str(requested.order_id)
	f.other_order_id = str(other.order_id)
	var stock := Stocks.stock_endpoint(data, smithy)
	var donor = actions._person(control)
	donor.cargo.wood = 4
	donor.cargo.fiber = 2
	_check(lab.character.place(stock.cell, true) and orders.authorize_military_materials(control, "n1", f.order_id, {"wood": 4, "fiber": 2}).ok,
		"Actual original donor explicitly grants only this single batch")
	before = var_to_bytes([data.site, row, donor.holder, donor.cargo])
	_check(not orders.supply_military_production(control, "n1", f.order_id, {"wood": 4, "fiber": 2}, int(donor.holder.version) + 1, int(stock.holder.version)).ok
		and var_to_bytes([data.site, row, donor.holder, donor.cargo]) == before, "Stale actual donor CAS refuses before source funding, manufacturing materials, original order or Scope changes")
	_check(not orders.supply_military_production(control, "n1", f.order_id, {"wood": 4, "fiber": 2}, int(donor.holder.version), int(stock.holder.version) + 1).ok
		and var_to_bytes([data.site, row, donor.holder, donor.cargo]) == before, "Stale actual localstock CAS refuses the same original transfer atomically")
	_check(orders.supply_military_production(control, "n1", f.order_id, {"wood": 4, "fiber": 2}, int(donor.holder.version), int(stock.holder.version)).ok,
		"Original source transfer funds this true localstock without manufacturing yet")
	# The donor stands on the sole original workshop station after the transfer; it steps off on one
	# legal Actor edge so the named worker can reach that station (as the military production test does).
	var vacated := false
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var destination: Vector2i = stock.cell + direction
		if not data.can_step(stock.cell, destination) or not lab.character.can_enter_cell(destination) or lab.npc.occupies_cell(destination): continue
		var stepped: bool = lab.character.step(direction)
		_check(stepped, "Original donor accepts one legal Actor edge off the workshop station")
		if not stepped: break
		lab.character.advance_combat(lab.character.get_move_interval() + 0.00001)
		vacated = lab.character.terrain_cell == destination and not lab.character.is_moving()
		break
	_check(vacated and not lab.site_controller.work_team._occupied(stock.cell, team, team.index_for_identity(executor)), "Original donor genuinely vacates the sole workshop station")
	f.stock = stock
	return f

func _n05_real_issue() -> void:
	var f := _military_earned_fixture()
	var data: TerrainData = f.data
	var lab: TerrainLab = f.lab
	var actions: SitePersonActions = f.actions
	var orders: SiteEquipmentOrders = f.orders
	var nation: Dictionary = data.site.equipment_nations.n1
	var production: Dictionary = nation.technology_operations.orders[f.order_id]
	var camp = data.site.inventory.duplicate()
	var donor_spent = production.source.spent.duplicate()
	var next_item := int(data.site.next_item)
	_check(actions.begin_scope_technology_phase(f.control, "nation", "n1", "workshop_bow", "feature:" + f.smithy).ok,
		"First true N05 phase starts from the actual finite military source")
	_at_feature(lab, f.team, f.executor, f.smithy)
	var points := 0
	while f.feature.get("batch_paid", false) and points < 10:
		_check(Time.get_ticks_msec() < deadline, "True N05 manufacturing stays inside the internal deadline")
		_workshop_named_point(f, 30.0)
		points += 1
	_check(points < 10 and production.status == "complete" and production.accepted_receipts.size() == 1
		and production.accepted_receipts[0].item_ids == [str(next_item)] and data.site.next_item == next_item + 1,
		"True original paid work creates exactly the order's genuine bow and accepted receipt")
	var project := Technology.active_project(nation.technology)
	_check(project.receipts.size() == 1 and project.budget.payments.size() == 1 and project.budget.spent == {"wood": 4, "fiber": 2}
		and not Technology.scope_known(nation.technology, "N05"), "One real manufactured phase alone does not earn N05")
	# Actual fixture positions exclude travel acceptance. The genuine original
	# transfer still checks both contacts, logistics duty and original holder CAS.
	f.team.cells[1] = Vector2i(10, 9)
	_check(lab.character.place(Vector2i(9, 9), true), "Actual delegated logistics member contacts the true original camp and maker")
	# A person endpoint of the original transfer must be a dedicated logistics member; the actual
	# logistics duty holder assigns the maker through the original team-logistics order.
	var carriers: Array[int] = [f.executor]
	var carried: Dictionary = lab.site_controller.order_team_logistics(f.team, carriers, f.control, true)
	_check(carried.ok, "Actual logistics duty holder assigns the maker as a dedicated carrier: " + str(carried))
	var person := actions._person(f.executor)
	# Transfer authority stays with the captain or the carrier itself (office plan: only the
	# logistics designation is delegated). The maker, now a dedicated carrier, delivers its own
	# bow through the original NPC test dispatch.
	_check(lab.site_controller.vehicles.transfer("person:" + str(f.executor), "depot", {}, [str(next_item)], int(person.holder.version), int(data.site.depot_items.version), f.executor, true).ok,
		"True original logistics transaction transfers the specific order bow to actual camp, with no item clone")
	_check(data.site.item_records[str(next_item)].holder == "depot" and data.site.depot_items.item_ids.has(str(next_item)), "The actual camp holds the exact original output before issue")
	# A dedicated logistics member cannot serve the research consent; the same duty holder releases
	# the maker back to ordinary service before the issue phase.
	var released: Dictionary = lab.site_controller.order_team_logistics(f.team, carriers, f.control, false)
	_check(released.ok and not bool(f.team.combat_units[1].get("logistics", false)), "Actual logistics duty holder releases the maker from dedicated carrying: " + str(released))
	var before := var_to_bytes([data.site, f.row, actions._jobs.keys()])
	_check(not actions.prepare_nation_military_issue_binding({"military_production_id": 0}).ok 
		and not actions.nation_military_issue_receipt_query({"person": 7}, {}).ok 
		and var_to_bytes([data.site, f.row, actions._jobs.keys()]) == before, "Malformed original adapter inputs refuse before typed field access or any source/Scope/job change")
	_check(not orders.begin_military_issue(f.control, "n1", f.other_order_id).ok and var_to_bytes([data.site, f.row, actions._jobs.keys()]) == before,
		"A different real unfunded production order cannot borrow the paid output or start issue")
	_check(not actions.begin_equipment(f.control, {"mode": "issue", "nation_id": "n1", "standard_id": "bow_line", "military_production_id": f.order_id}).ok
		and var_to_bytes([data.site, f.row, actions._jobs.keys()]) == before, "A different original recipient cannot wear the research maker's actual order product")
	_check(lab.site_controller._nation_ui_command("n1", "issue_military", {"order": f.order_id}).ok,
		"The real original public form begins the existing five-second equipment job")
	var job: Dictionary = actions._jobs[str(f.executor)]
	var frames := 0
	while bool(job.get("preparing", false)) and frames < 10000:
		_check(Time.get_ticks_msec() < deadline, "The real original appearance preparation is bounded")
		await process_frame
		frames += 1
	_check(not job.preparing and job.kind == "equipment" and job.duration == 5.0 and job.elapsed == 0.0
		and is_same(job.nation_issue_order_ref, production), "Only the original real appearance pipeline prepares the SAME five-second issue job; no fake visual guard")
	_check(not actions.save_guard().ok, "Pending original equipment work keeps the original BUSY save boundary, without a new saved queue")
	project = Technology.active_project(nation.technology)
	_check(project.budget.payments.size() == 2 and project.budget.payments[1].materials.is_empty() and data.site.inventory == camp,
		"Issue reserves one new attempt and zero-material accounting without recharging manufacturing")
	# Negative fault injection changes only true original owner/CAS inputs. Every
	# positive guard above and below still uses the unmodified original callbacks.
	var visual_guard: Callable = orders.equipment_apply_guard
	orders.equipment_apply_guard = Callable()
	before = var_to_bytes([data.site, f.row, actions._jobs.keys()])
	_check(not orders.commit(job.order).ok and var_to_bytes([data.site, f.row, actions._jobs.keys()]) == before, "Lost original appearance guard rejects before stock, issue status and Scope receipt changes")
	orders.equipment_apply_guard = visual_guard
	var depot_version := int(data.site.depot_items.version)
	data.site.depot_items.version = depot_version + 1
	before = var_to_bytes([data.site, f.row, actions._jobs.keys()])
	_check(not orders.commit(job.order).ok and var_to_bytes([data.site, f.row, actions._jobs.keys()]) == before, "Changed original camp CAS rejects all prospective issue/Scope mutations")
	data.site.depot_items.version = depot_version
	var person_version := int(person.holder.version)
	person.holder.version = person_version + 1
	before = var_to_bytes([data.site, f.row, actions._jobs.keys()])
	_check(not orders.commit(job.order).ok and var_to_bytes([data.site, f.row, actions._jobs.keys()]) == before, "Changed original recipient CAS rejects before equipment and Scope publication")
	person.holder.version = person_version
	var standard: Dictionary = nation.standards.bow_line
	var standard_version := int(standard.revision)
	standard.revision = standard_version + 1
	before = var_to_bytes([data.site, f.row, actions._jobs.keys()])
	_check(not orders.commit(job.order).ok and var_to_bytes([data.site, f.row, actions._jobs.keys()]) == before, "Current original standard mismatch cannot issue or grant research")
	standard.revision = standard_version
	_original_admin_point(lab, 4.0) # Original helper consumes PA allocations, including equipment/raw.
	_check(actions.is_busy(f.executor) and job.elapsed == 4.0 and production.status == "complete" and not Technology.scope_known(nation.technology, "N05"),
		"Four genuine original seconds leave the bow in camp and N05 unknown")
	_original_admin_point(lab, 1.0)
	_check(not actions.is_busy(f.executor) and production.status == "issued" and production.issued_item_ids == [str(next_item)]
		and person.holder.equipped.weapon == str(next_item) and data.site.item_records[str(next_item)].holder == person.holder.holder,
		"Exactly five actual original seconds atomically wear the same true bow and complete the original production issue")
	_check(Technology.scope_known(nation.technology, "N05") and nation.technology.projects[0].receipts.size() == 2
		and nation.technology.projects[0].receipts[1].work_seconds == 5.0, "True first manufacture plus genuine five-second issue earns first N05")
	_check(data.site.inventory == camp and production.source.spent == donor_spent and data.site.next_item == next_item + 1,
		"Issue creates no product and repeats no donor/localstock/camp material debit")
	_check(Orders.validate_nation_operations(data, data.site, {f.control: true, f.executor: true, f.team.combat_identity(f.team.formal_commander): true}).ok, "Completed true order/accepted history and Scope receipts retain the actual living original consent decider in strict cold validation")
	before = var_to_bytes([data.site, f.row, actions._jobs.keys()])
	_check(not orders.begin_military_issue(f.control, "n1", f.order_id).ok and var_to_bytes([data.site, f.row, actions._jobs.keys()]) == before,
		"Already-issued true product cannot be reissued or replayed as another Scope receipt")
	var accepted_scope = nation.technology.duplicate(true)
	var ordinary := orders.request_military_production_order(f.control, "n1", "cert", f.executor, f.control, "bow_line")
	_check(ordinary.ok and nation.technology == accepted_scope and nation.technology_operations.orders[ordinary.order_id].recipient_id == f.control 
		and nation.technology_operations.orders[ordinary.order_id].operator_id == f.executor 
		and nation.technology_operations.orders[ordinary.order_id].source.is_empty(), "After genuine first-known completion, original ordinary military orders still admit different maker/recipient without Scope evidence or imputed material grants")
	_earned_nation_cleanup(lab, f.team)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	await _n05_real_issue()
	TerrainArmy.release_contact_source()
	print("N05_ORIGINAL_MANUFACTURE_AND_FIVE_SECOND_ISSUE_EARNED_FIXTURE_PASS: checks=", checks, "; true holders/visual bridge/Scope; no Native/whole-Lab/Region/full40 acceptance")
	quit(0)

# Original parent _army is NPC-only. This child performs a real join_player,
# so its original deployment must retain the SAME original Actor/NPC refs.
func _army(lab: TerrainLab, data: TerrainData) -> TerrainArmy:
	_check(is_same(data, lab.terrain), "Joining fixture Army deploys into the same actual Lab source")
	return _material_army(lab, 2)
