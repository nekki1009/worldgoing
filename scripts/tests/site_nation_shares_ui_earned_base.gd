extends "res://scripts/tests/site_technology_nation_material_test.gd"
## Actual original Nation window buttons, finite physical holder transfers,
## original TerrainLab shared steps and Controller Store save/load.
## N01/N02 and S06 are explicit prior archives, never target earned evidence.
const SharesCatalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")

func _target_id() -> String:
	return ""

func _after_nation_infrastructure(f: Dictionary) -> void:
	# The starting background needs the finished Warehouse, so it runs after the
	# parent infrastructure; the forty prior residents (team 402) stay as built.
	var team: TerrainArmy = _army(f.lab, f.data)
	var captain_id: int = team.combat_identity(0)
	var captain: Dictionary = f.actions._person(captain_id)
	_check(not captain.is_empty() and float(captain.hp) <= 0.0 and team.formal_commander == TerrainArmy.PLAYER_MEMBER
		and team.combat_identity(team.current_commander) == int(f.control),
		"The starting captain is truly dead and the original succession seated the controlled Actor before any settlement check")
	f.team = team
	f.executor = team.combat_identity(1)
	f.row = team.combat_units[1]

func _army(lab: TerrainLab, data: TerrainData) -> TerrainArmy:
	# Explicit starting background, not combat/route acceptance: use the actual
	# scene Army, its original person allocator, equipment and lifecycle hooks.
	var team: TerrainArmy = lab.army
	_check(team != null and not team.has_army() and lab.combat_armies.has(team), "The initial Army is already owned by the actual Lab")
	team.set_process(false)
	team.roster_size = 3
	team.faction_id = int(lab.character.faction_id)
	var warehouses: Array[String] = []
	for key: String in data.site.features:
		if str(data.site.features[key].get("kind", "")) == "warehouse": warehouses.append(key)
	_check(warehouses.size() == 1, "Starting fixture has one true completed Warehouse")
	var entrance: Vector2i = data.cell_from_index(int(data.site.features[warehouses[0]].entrance))
	_check(lab.character.place(entrance, true), "Actual prospective captain starts at the true Warehouse door")
	var contacts: Array[Vector2i] = []
	for direction: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
		var cell: Vector2i = entrance + direction
		if data.is_walkable(cell) and data.can_step(cell, entrance) and not lab.npc.occupies_cell(cell): contacts.append(cell)
		if contacts.size() == 2: break
	_check(contacts.size() == 2, "Two distinct actual neighboring stations can contact the original Warehouse")
	var captain_cell: Vector2i = TerrainArmy.INVALID_CELL
	for offset: Vector2i in [Vector2i(2, 0), Vector2i(0, -2), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(-2, -2), Vector2i(2, 2)]:
		var cell: Vector2i = entrance + offset
		if data.is_walkable(cell) and not contacts.has(cell) and not lab.npc.occupies_cell(cell):
			captain_cell = cell
			break
	_check(captain_cell != TerrainArmy.INVALID_CELL, "The living initial captain has a distinct legal nearby station")
	var cells: Array[Vector2i] = [captain_cell, contacts[0], contacts[1]]
	_check(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false), "Original deploy and equipment/lifecycle initialization create three genuine NPCs")
	var captain_id: int = team.combat_identity(team.formal_commander)
	var control: int = lab.controlled_person_id()
	_check(team.formal_commander == 0 and float(team.combat_hot_get(0, &"hp")) > 0.0, "A genuine living original captain starts in office")
	_check(team.join_player(lab.character).ok, "The same controlled Actor joins through original membership and supply guards")
	_check(team.set_military_role(control, "officer").ok, "Original role transaction qualifies the actual player member")
	var offices: Dictionary = team.team_offices()
	var seat: Dictionary = SiteOffices.position_of(offices, control)
	_check(not seat.is_empty() and not bool(seat.head) and SiteOffices.needs_officer(offices, seat), "Original auto-seating supplies an actual non-head military post")
	_check(team.apply_office_plan(captain_id, int(offices.revision), [
		{"op": "dismiss", "position_id": str(seat.id)},
		{"op": "appoint", "position_id": str(seat.id), "person_id": control}]).ok,
		"The living true captain explicitly accepts the real successor's non-head appointment")
	# Head appointment is forbidden by original SiteOffices. This explicit
	# historical environmental casualty is settled by the original life owner.
	# No captain index, death flag, combat grace, clock or consent is fabricated.
	team.apply_unit_contact(0, {"result": {"hp": float(team.combat_hot_get(0, &"hp")), "stun": 0.0, "guard_break": false}, "shield": false, "environmental": true})
	team.settle_combat_command()
	_check(team.formal_commander == TerrainArmy.PLAYER_MEMBER and team.current_commander == TerrainArmy.PLAYER_MEMBER
		and team.combat_identity(team.current_commander) == control and team.command_eligible(team.current_commander),
		"Original permanent vacancy succession seats the true controlled Actor")
	_check(team.duty_decider("team.work") == control and team.duty_decider("team.logistics") == control,
		"Original current captain actually exercises work and logistics authority")
	for index: int in [1, 2]:
		_check(team.is_member(index) and team.combat_can_act(index) and not bool(team.combat_hot_get(index, &"logistics", false)), "Both true original recipient NPCs remain alive, ordinary and unassigned")
	return team

func _shares_settle_starting_death(f: Dictionary) -> void:
	var captain_id: int = f.team.combat_identity(0)
	var points: int = 0
	while f.controller._pending_deaths.has(captain_id) or float(f.data.site.get("combat_left", 0.0)) > 0.0:
		_check(Time.get_ticks_msec() < deadline and points < 1000, "Original historical death/grace endpoints settle within a bounded legal caller")
		var step: Dictionary = f.lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		_check(step.get("ok", false) and step.get("completed", false) and float(step.get("game_seconds", 0.0)) > 0.0,
			"Original shared caller advances the starting life endpoint without fake clock: " + str(step))
		points += 1
		if points % 32 == 0: await process_frame
	var dead: Dictionary = f.actions._person(captain_id)
	_check(not dead.is_empty() and float(dead.hp) <= 0.0 and dead.body.get("loot_settled") == true
		and dead.cargo.is_empty() and dead.holder.item_ids.is_empty(), "Original death owner settles all original belongings and counters")
	var remains_id: String = str(dead.body.get("remains_id", ""))
	_check(remains_id.is_empty() or f.data.site.ground_loot.has(remains_id)
		and int(f.data.site.ground_loot[remains_id].original_owner) == captain_id, "Any actual remains keep the true deceased original owner")
	_check(f.team.formal_commander == TerrainArmy.PLAYER_MEMBER and f.team.current_commander == TerrainArmy.PLAYER_MEMBER,
		"True succession survives original corpse/endpoint settlement before target research")

func _shares_capture_people(f: Dictionary, identities: Array[int]) -> Dictionary:
	var captured: Dictionary = {}
	for identity: int in identities:
		var person: Dictionary = f.actions._person(identity)
		_check(not person.is_empty() and person.owner is TerrainArmy and person.unit >= 0
			and float(person.hp) > 0.0 and person.owner.is_member(int(person.unit)), "Cold capture witnesses the actual living original recipient")
		captured[identity] = {"owner": person.owner, "body": person.body, "cargo": person.cargo, "holder": person.holder,
			"cargo_values": person.cargo.duplicate(true), "holder_values": person.holder.duplicate(true), "grain": int(person.cargo.get("grain", 0)),
			"cell": person.cell, "team_id": int(person.owner.team_id), "logistics": bool(person.body.get("logistics", false))}
	return captured

func _shares_bytes(f: Dictionary) -> PackedByteArray:
	return var_to_bytes([f.data.site, f.lab.character.capture_state(), f.team.combat_units, f.actions._jobs])

func _shares_dialog(f: Dictionary) -> AcceptDialog:
	f.controller._open_nation_operations("n1", null, _target_id())
	var entry: Dictionary = f.controller._ui_dialogs.get("nation_operations", {})
	_check(entry.get("dialog") is AcceptDialog, "Original dialog registry owns the real Nation window")
	var dialog: AcceptDialog = entry.dialog
	_check(dialog.name == "NationOperationsDialog" and dialog.is_inside_tree(), "Original window is attached to its true UI host")
	return dialog

func _shares_choice(dialog: AcceptDialog, key: String, value: Variant) -> void:
	var choice = dialog.find_child("NationOperation_" + key, true, false) as OptionButton
	_check(choice != null, "Actual Nation window exposes the original " + key + " selection")
	var found = false
	for index: int in range(choice.item_count):
		var metadata: Variant = choice.get_item_metadata(index)
		# The window's placeholder item carries "" metadata; compare like types only.
		if typeof(metadata) == typeof(value) and metadata == value:
			choice.select(index)
			found = true
			break
	_check(found, "Real original selection contains the requested current target: " + key)

func _shares_press(dialog: AcceptDialog, action: String) -> void:
	var button = dialog.find_child("NationOperation_" + action, true, false) as Button
	_check(button != null and not button.disabled, "Actual original window owns an enabled " + action + " button")
	button.pressed.emit()

func _shares_refresh(dialog: AcceptDialog, order_id: String) -> void:
	var button = dialog.find_child("RefreshNationOperations", true, false) as Button
	_check(button != null, "Actual Nation refresh re-queries the same original owner")
	button.pressed.emit()
	_shares_choice(dialog, "order", order_id)

func _shares_quantity(dialog: AcceptDialog, quantity: int) -> void:
	var inputs = dialog.find_children("*", "SpinBox", true, false)
	_check(inputs.size() == 1 and inputs[0] is SpinBox, "This original aid/tax form exposes exactly its one grain quantity")
	inputs[0].value = quantity

func _shares_job_steps(f: Dictionary, stop_at_seconds: float = -1.0) -> void:
	var points = 0
	while f.actions.is_busy(f.control):
		_check(Time.get_ticks_msec() < deadline and points < 4000, "Original shared-step job finishes within the bounded real deadline")
		var step: Dictionary = f.lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
		_check(step.get("ok", false) and step.get("completed", false) and float(step.get("game_seconds", 0.0)) > 0.0,
			"Actual original body/work/food/contact endpoint accepts one legal positive shared step: " + str(step))
		points += 1
		if stop_at_seconds > 0.0 and f.actions.is_busy(f.control) and float(f.actions._jobs[str(f.control)].elapsed) >= stop_at_seconds:
			return
		if points % 32 == 0: await process_frame

func _shares_clean(f: Dictionary) -> Array[WeakRef]:
	# Clear actual current owner transients after cold bind, including rebuilt
	# Armies. Scene children are freed by their original Lab, once.
	var nodes: Array[WeakRef] = [weakref(f.lab)]
	for identity: int in f.controller.work_team.active_ids(): f.controller.work_team.cancel(identity)
	f.controller.work_team.discard_prepared_interval()
	f.controller.work_team.unavailable = Callable()
	f.controller.work_team.vehicle_blocked = Callable()
	f.controller.equipment_orders.nation_arsenal_request = Callable()
	f.controller.equipment_orders.nation_owner_receipt_query = Callable()
	for team: TerrainArmy in f.lab.combat_armies:
		if not is_instance_valid(team): continue
		nodes.append(weakref(team))
		team.controlled_person_query = Callable()
		team.person_busy_query = Callable()
		if team.get_parent() != f.lab: team.queue_free()
	if is_instance_valid(f.team) and not f.lab.combat_armies.has(f.team):
		nodes.append(weakref(f.team))
		f.team.controlled_person_query = Callable()
		f.team.person_busy_query = Callable()
		f.team.queue_free()
	f.lab.queue_free()
	return nodes

func _shares_earned() -> void:
	var tech_id = _target_id()
	_check(tech_id in ["N03", "N09"] and bool(SharesCatalog.get_node(tech_id).get("enabled", false)), "Positive fixture requires Root's separately frozen isolated Catalog admission")
	var f = _nation_fixture(["N01", "N02"])
	f.lab.restore_only = false # Real active mode; original initializer is restoration-only.
	f.lab.simulation_speed = 4.0 # Existing public simulation control; no saved clock mutation.
	await _shares_settle_starting_death(f)
	var recipients: Array[int] = [int(f.executor), int(f.team.combat_identity(2))]
	_check(f.controller.order_team_logistics(f.team, recipients, int(f.control), true).ok,
		"Actual controlled captain explicitly orders both living original recipients to logistics")
	for identity: int in recipients:
		var actual: Dictionary = f.actions._person(identity)
		_check(actual.owner == f.team and actual.body.get("logistics") == true and f.data.can_step(actual.cell, f.entrance)
			and absi(actual.cell.x - f.entrance.x) + absi(actual.cell.y - f.entrance.y) == 1,
			"Original recipient actually stands at its distinct legal Warehouse contact; route acceptance is excluded")
	var nation: Dictionary = f.data.site.equipment_nations.n1
	_check(not Technology.scope_known(nation.technology, tech_id), "Target knowledge is absent before every real operation")
	_check(f.actions.prepare_scope_technology(f.control, f.control, tech_id, "n1").ok
		and f.actions.request_scope_technology_consent(f.control, "nation", "n1", f.control).ok,
		"Original current national duty prepares the actual first project and original controlled executor")
	var person = f.actions._person(f.control)
	var stock = Stocks.storage(f.data, f.warehouse)
	var amount = 4 if tech_id == "N03" else 1
	person.cargo.clear() # Explicit finite initial donor stock; all following movement uses the real transfer.
	person.cargo.grain = amount
	stock.cargo.clear()
	var recipient_ids: Array[int] = recipients.duplicate()
	if tech_id != "N03": recipient_ids = [int(f.executor)] # Typed assignment, not an untyped ternary literal.
	for identity: int in recipient_ids:
		_check(f.actions._person(identity).cargo.is_empty(), "Actual receiving original NPC starts with an empty holder")
	var dialog = _shares_dialog(f)
	_shares_choice(dialog, "reserve", f.warehouse)
	if tech_id == "N03":
		var list = dialog.find_child("NationOperation_people", true, false) as ItemList
		_check(list != null, "Actual aid window exposes the true multi-recipient list")
		for index: int in range(list.item_count):
			if recipient_ids.has(int(list.get_item_metadata(index))): list.select(index, false)
		_check(list.get_selected_items().size() == 2, "Exactly two actual living original recipients are selected")
	else:
		_shares_choice(dialog, "recipient", recipient_ids[0])
	_shares_press(dialog, "aid" if tech_id == "N03" else "tax")
	var order_ids: Array[String] = []
	var ops: Dictionary = nation.technology_operations
	for key: String in ops.public_orders:
		if ops.public_orders[key].tech_id == tech_id: order_ids.append(key)
	_check(order_ids.size() == 1, "True original window creates exactly one finite target order")
	var order_id = order_ids[0]
	var order: Dictionary = ops.public_orders[order_id]
	_shares_refresh(dialog, order_id)
	_shares_quantity(dialog, amount)
	var before = _shares_bytes(f)
	_shares_press(dialog, "administration")
	_check(_shares_bytes(f) == before and not f.actions.is_busy(f.control), "UI refuses research before actual required transfers with zero body/source/job changes")
	_shares_press(dialog, "fund")
	_check(_shares_bytes(f) == before, "UI cannot transfer an unconsented finite source")
	_shares_press(dialog, "grant_source")
	_shares_press(dialog, "fund")
	_check(is_same(nation.technology_operations, ops) and is_same(ops.public_orders[order_id], order), "Original order and operations refs survive authorization and true funding")
	_check(int(person.cargo.get("grain", 0)) == 0 and int(stock.cargo.get("grain", 0)) == amount, "Actual original donor-to-Warehouse transaction conserves this finite grain")
	_check(not Technology.scope_known(nation.technology, tech_id) and not f.actions.is_busy(f.control), "Funding cannot award target knowledge or fake administrative work")
	for identity: int in recipient_ids:
		var receiving: Dictionary = f.actions._person(identity)
		var transfer_before: PackedByteArray = _shares_bytes(f)
		var physical: Dictionary = f.controller.vehicles.prepare_transfer("feature:" + str(f.warehouse), "person:" + str(identity),
			{"grain": 2 if tech_id == "N03" else 1}, [], int(stock.holder.version), int(receiving.holder.version), int(f.control))
		_check(physical.ok and _shares_bytes(f) == transfer_before, "Pure original transfer checks actual captain/logistics/contact/refs before the real UI commit: " + str(physical))
		_shares_choice(dialog, "recipient", identity)
		_shares_press(dialog, "share")
		_check(int(f.actions._person(identity).cargo.get("grain", 0)) == (2 if tech_id == "N03" else 1), "Original Warehouse delivers the exact physical share to the selected living holder")
		before = _shares_bytes(f)
		_shares_press(dialog, "share")
		_check(_shares_bytes(f) == before, "Same original share cannot replay or duplicate physical grain")
	_check(int(stock.cargo.get("grain", 0)) == 0 and order.status == "complete" and Orders._public_order_complete(order), "Only the actual required transfers complete this original order")
	_shares_press(dialog, "administration")
	_check(f.actions.is_busy(f.control), "Actual original administrative button starts the real 300-second PA job")
	var project = Technology.active_project(nation.technology)
	_check(project.budget.payments.size() == 1 and project.budget.spent == {"grain": amount}, "One original Scope payment witnesses already transferred grain without a second debit")
	await _shares_job_steps(f, 2.0)
	_check(f.actions.is_busy(f.control) and not Technology.scope_known(nation.technology, tech_id), "A true positive shared prefix advances actual work without early target knowledge")
	_check(f.actions.cancel(f.control).ok, "Original cancellation stops the real job while keeping the paid transfer history")
	_shares_press(dialog, "administration")
	_check(f.actions.is_busy(f.control) and Technology.active_project(nation.technology).budget.payments.size() == 1,
		"Actual original UI resumes the paid operation with an empty donor and no second payment")
	await _shares_job_steps(f)
	_check(Technology.scope_known(nation.technology, tech_id), "Only genuine full original effective work earns the initially unknown target")
	var completed: Dictionary = nation.technology.projects.back()
	_check(completed.receipts.size() == 1 and is_equal_approx(float(completed.receipts[0].work_seconds), 300.0)
		and completed.budget.payments.size() == 1 and completed.budget.spent == {"grain": amount}, "Historical Scope has exactly one complete 300-second receipt and its original finite payment")
	before = _shares_bytes(f)
	_shares_press(dialog, "administration")
	_check(_shares_bytes(f) == before and not f.actions.is_busy(f.control), "Completed first research cannot repeat its old transfers or reward")
	dialog.queue_free()
	await process_frame
	var path = "user://nation_shares_earned_" + tech_id + "_" + str(Time.get_ticks_usec()) + ".json"
	f.controller.save_path = path
	var saved: Dictionary = f.controller.save_to(path)
	_check(saved.ok, "Actual Controller captures current hot originals and strict Store accepts the completed state: " + str(saved))
	var old_people: Dictionary = _shares_capture_people(f, recipient_ids)
	var actor: TerrainTestCharacter = f.lab.character
	var actor_id: int = actor.person_id
	var actor_cargo: Dictionary = f.actions._person(actor_id).cargo.duplicate(true)
	var old_army_snapshot: Dictionary = f.team.capture_combat_state()
	var cold: Dictionary = f.controller.load_from(path)
	_check(cold.ok and not is_same(f.lab.terrain, f.data), "Actual Controller full load and original TerrainLab bind rebuild a distinct cold graph: " + str(cold))
	var restored_actions: SitePersonActions = f.controller.person_actions
	for identity: int in recipient_ids:
		var current: Dictionary = restored_actions._person(identity)
		var prior: Dictionary = old_people[identity]
		_check(not current.is_empty() and current.owner is TerrainArmy and f.lab.combat_armies.has(current.owner)
			and int(current.person_id) == identity and int(current.owner.team_id) == int(prior.team_id)
			and is_same(current.body, current.owner.combat_units[int(current.unit)]) and current.owner.is_member(int(current.unit))
			and float(current.hp) > 0.0, "Actual cold query resolves the same saved identity in the current original Army graph")
		_check(not is_same(current.body, prior.body) and not is_same(current.cargo, prior.cargo) and not is_same(current.holder, prior.holder),
			"Cold bind rebuilds original Army row/body, cargo and holder refs rather than retaining the old hot graph")
		_check(current.cargo == prior.cargo_values and current.holder == prior.holder_values
			and int(current.cargo.get("grain", 0)) == int(prior.grain) and current.cell == prior.cell
			and bool(current.body.get("logistics", false)) == bool(prior.logistics),
			"Cold original recipients preserve actual saved grain, items, logistics and physical stations")
		_check(current.owner.player_member == actor and current.owner.formal_commander == TerrainArmy.PLAYER_MEMBER
			and current.owner.combat_identity(current.owner.formal_commander) == actor_id,
			"Original restored membership and captaincy refer to the SAME reused actual Actor")
	_check(is_same(f.lab.character, actor) and int(f.lab.controlled_person_id()) == actor_id
		and restored_actions._person(actor_id).cargo == actor_cargo,
		"Cold Actor restore legitimately reuses its original Node and preserves true current inventory")
	var deceased_id: int = int(old_army_snapshot.units[0].person_id)
	var deceased: Dictionary = restored_actions._person(deceased_id)
	_check(not deceased.is_empty() and float(deceased.hp) <= 0.0 and deceased.body.get("loot_settled") == true
		and str(deceased.body.get("remains_id", "")) == str(old_army_snapshot.units[0].get("remains_id", "")),
		"Actual cold life owner preserves the settled initial captain's corpse/remains history")
	var restored: Dictionary = f.lab.terrain.site.equipment_nations.n1
	_check(Technology.scope_known(restored.technology, tech_id) and restored.technology.projects.back().receipts.size() == 1
		and restored.technology.projects.back().budget.spent == {"grain": amount}, "Original cold restore preserves unique knowledge, work receipt and finite payment")
	var restored_order: Dictionary = restored.technology_operations.public_orders[order_id]
	_check(restored_order.status == "complete" and Orders._public_order_complete(restored_order), "Original strict cold order retains its true physical-transfer lineage")
	var cold_before = var_to_bytes(f.lab.terrain.site)
	_check(not f.controller.person_actions.begin_nation_administration(f.lab.controlled_person_id(), "n1", order_id, "aid_order" if tech_id == "N03" else "tax").ok
		and var_to_bytes(f.lab.terrain.site) == cold_before, "Cold rebuilt original owner refuses historical work replay without state mutation")
	_check(DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK, "Remove only this fixture's exact unique user-save path")
	var cleanup: Array[WeakRef] = _shares_clean(f)
	await process_frame
	await process_frame
	for reference: WeakRef in cleanup:
		_check(reference.get_ref() == null, "Actual current cold Lab/Army Nodes release after original scene teardown")

func _run() -> void:
	_check(DisplayServer.get_name() != "headless", "This real UI/Army/cold fixture requires canonicalVisual; headless dummy-material ERROR is not accepted")
	deadline = Time.get_ticks_msec() + 180000
	await _shares_earned()
	TerrainArmy.release_contact_source()
	print(_target_id(), "_ORIGINAL_UI_TRANSFERS_SHARED_WORK_COLD_EARNED_PASS: checks=", checks,
		"; target absent initially; real original UI/holders/local shared caller/cold bind; no pinned Region/Native/route/performance/full40 proof")
	quit(0)
