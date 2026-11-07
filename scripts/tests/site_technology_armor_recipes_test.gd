extends "res://scripts/tests/site_technology_nation_material_test.gd"
## Real original 40-person Army, Housing, two paid Settlement upgrades, workshop
## tasks, material ledger and ItemSeq. Direct setup/production intervals exclude
## travel, full Lab clock, Native and render acceptance. Catalog S13 must be
## enabled by the guarded original-owner implementation candidate before launch.

func _armor_fixture(known: bool, upgrade_to_three: bool = true) -> Dictionary:
	var specs: Array = [
		{"kind": "settlement_center", "anchor": Vector2i(27, 27), "extent": Vector2i(5, 5)},
		{"kind": "well", "anchor": Vector2i(24, 21), "extent": Vector2i.ONE},
		{"kind": "farm", "anchor": Vector2i(15, 24), "extent": Vector2i(2, 2)},
		{"kind": "warehouse", "anchor": Vector2i(34, 25), "extent": Vector2i.ONE},
		{"kind": "smithy", "anchor": Vector2i(21, 25), "extent": Vector2i.ONE},
		{"kind": "tannery", "anchor": Vector2i(34, 29), "extent": Vector2i.ONE},
		{"kind": "charcoal", "anchor": Vector2i(15, 29), "extent": Vector2i.ONE},
		{"kind": "weaver", "anchor": Vector2i(24, 32), "extent": Vector2i.ONE}, # Its south entrance stays clear of the house row at y=36.
		{"kind": "training_ground", "anchor": Vector2i(21, 41), "extent": Vector2i(10, 10)},
	]
	# The south row sits one row higher so its doors and rest cells stay north of the 10x10 yard (row 41).
	for y: int in [15, 36]:
		for x: int in [15, 21, 27, 33, 39]: specs.append({"kind": "house", "anchor": Vector2i(x, y), "extent": Vector2i.ONE, "options": {"variant": "large"}})
	var extras: Array[Vector2i] = [Vector2i(9, 9), Vector2i(9, 10), Vector2i(9, 8), Vector2i(40, 24)]
	for x: int in range(9, 49): extras.append(Vector2i(x, 49))
	# Select actual natural adjacent ground for the existing movement component.
	var paths: Array = []
	for y: int in range(41, 52):
		var path: Array[Vector2i] = []
		for x: int in range(21, 39): path.append(Vector2i(x, y))
		paths.append(path)
	var selected := _cold_natural_template(specs, "technology-armor-natural", extras, 1, paths)
	var data: TerrainData = selected.data
	var offset: Vector2i = selected.offset
	data.site.depot_cell = data.index(Vector2i(9, 9) + offset)
	var lab := _material_natural_lab(data)
	var control := lab.controlled_person_id()
	var actions = lab.site_controller.person_actions
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = 401
	team.roster_size = 40
	team.faction_id = 1
	team.person_id_allocator = Callable(lab, "_allocate_army_person_ids")
	var cells: Array[Vector2i] = []
	for x: int in range(9, 49): cells.append(Vector2i(x, 49) + offset)
	_check(team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false), "Original Army creates exactly 40 actual original residents")
	lab.combat_armies.append(team)
	team.controlled_person_query = lab.controlled_person_id
	team.person_busy_query = actions.is_busy
	team.settle_combat_command()
	_check(team.set_duty_ai_enabled(team.combat_identity(team.formal_commander), true).ok, "Original captain enables the actual duty AI for named work requests")
	for row: Dictionary in team.combat_units:
		row.cargo = {}
		row.item_state = Runtime.new_item_state("person:" + str(row.person_id))
	var executor := team.combat_identity(1)
	var row: Dictionary = team.combat_units[1]
	row.technology = Technology.learned_candidate(Technology.learned_candidate({}, "F04"), "F14")
	var refs: Array = []
	for identity: int in [control, executor]: refs.append({"site_id": str(data.site.id), "person_id": identity, "path": "", "label": "真原成員", "age_years": -1})
	_check(lab.site_controller.family_continuity.register_members(refs, true, control).ok and lab.site_controller.family_continuity.appoint_head(control, control).ok, "Actual original registry and head duty establish the family")
	data.site.family = actions._technology_candidate()
	data.site.family.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.family.technology.known = ["F04", "F14"]
	_check(Family.validate_family(data.site.family, str(data.site.id)) and Technology.valid_person(row.technology), "Pre-existing prerequisites use strict real Family/person schemas")
	_check(lab.character.place(data.cell_from_index(int(selected.plans[0].preview.entrance)), true), "Actual founder stands within the original center jurisdiction")
	var proposed := Runtime.building_cells(data, "settlement_center", Vector2i(27, 27) + offset, Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	var center_cells: Array[int] = []
	center_cells.assign(proposed.cells)
	for key: String in selected.plans[0].preview.get("clearing", []): Env.change(data, key, {"cleared": true, "remaining": 0})
	var founded := Settlement.found(lab, control, center_cells)
	_check(founded.ok, "Original Settlement owner establishes its actual center")
	_complete_key(data, str(founded.feature))
	var houses: Array[String] = []
	# The south row sits one row higher so its doors and rest cells stay north of the 10x10 yard (row 41).
	for y: int in [15, 36]:
		for x: int in [15, 21, 27, 33, 39]: houses.append(_cold_natural_feature(data, "house", Vector2i(x, y) + offset, Vector2i.ONE, {"variant": "large"}))
	var housing_slots: Array[Dictionary] = []
	# Fixture worlds carry generated natural resources; clear any on each house's
	# entrance row (as for the center clearing) so its real slots are counted.
	for fixture_house: String in houses:
		var fixture_feature: Dictionary = data.site.features[fixture_house]
		for fixture_pair: Dictionary in Runtime._building_entrances(data, fixture_feature.cells, int(fixture_feature.quarter)):
			for fixture_key: String in Env.resources_in(data, Rect2i(fixture_pair.cell, Vector2i.ONE)): Env.change(data, fixture_key, {"cleared": true, "remaining": 0})
	Env.rebuild_indexes(data)
	for house: String in houses:
		var layout := Runtime.house_layout(data, house)
		_check(layout.ok, "A true original completed house supplies its real housing slots")
		for cell: int in layout.slots: housing_slots.append({"house_id": house, "cell": cell})
	_check(housing_slots.size() >= 40, "The ten genuine houses have enough unique original slots for all forty actual people")
	var people := {}
	data.site.housing = {}
	for index: int in range(40):
		var identity := team.combat_identity(index)
		people[identity] = {"hp": float(team.combat_units[index].hp), "faction_id": 1}
		data.site.housing[str(identity)] = {"version": 1, "house_id": str(housing_slots[index].house_id), "cell": int(housing_slots[index].cell)}
	_check(Homes.validate(data, data.site, people).ok and Settlement.residents(lab).size() == 40, "True Housing validator resolves forty original same-faction residents, without fake population")
	_cold_natural_feature(data, "well", Vector2i(24, 21) + offset)
	_cold_natural_feature(data, "farm", Vector2i(15, 24) + offset, Vector2i(2, 2))
	var warehouse := _cold_natural_feature(data, "warehouse", Vector2i(34, 25) + offset)
	var smithy := _cold_natural_feature(data, "smithy", Vector2i(21, 25) + offset)
	var tannery := _cold_natural_feature(data, "tannery", Vector2i(34, 29) + offset)
	if upgrade_to_three:
		for target: int in [2, 3]:
			var upgraded := Settlement.request_upgrade(lab, control)
			_check(upgraded.ok, "True original settlement requirements and finite payment admit level %d" % target)
			_complete_key(data, str(founded.feature))
			_check(int(Settlement.status(lab).level) == target and Settlement.status(lab).effective, "Original center completion establishes the actual effective upgraded level")
	data.site.settlement.version = 2
	data.site.settlement.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.settlement.technology.known = ["S13"] if known else []
	return {"data": data, "lab": lab, "team": team, "row": row, "executor": executor, "control": control, "actions": actions, "smithy": smithy, "tannery": tannery, "warehouse": warehouse, "settlement_id": str(data.site.settlement.settlement_id), "center": str(founded.feature), "natural_offset": offset}

func _ordinary_armor(fixture: Dictionary, key: String, recipe: String, expected_item: String) -> void:
	var data: TerrainData = fixture.data
	var lab: TerrainLab = fixture.lab
	var feature: Dictionary = data.site.features[key]
	var row: Dictionary = fixture.row
	var workers = lab.site_controller.work_team
	_check(Runtime.request_feature_recipe(data, key, recipe, 1).ok and Runtime.operate_feature(data, key).ok, "Original recipe/window operation opens the real armor host")
	# workers is untyped (4.7.2 relaxation), so pass an explicit Array[int] to SiteWorkTeam.assign.
	var armor_assignees: Array[int] = [int(fixture.executor)]
	_check(workers.assign(fixture.team, armor_assignees, fixture.team.duty_decider("team.work")).ok, "Actual team duty assigns its real armor craftsman")
	workers.prepare_work_requests(1.0)
	var task: Dictionary = row.work_task
	_check(task.get("target") == "feature:" + key, "The original selector chooses the actual armor work zone")
	fixture.team.cells[1] = data.cell_from_index(int(task.work_cell))
	# Assignment started a real walk; the fixture places the craftsman, so it must
	# also settle him there (no pending move, idle pose) as an arrived worker is.
	fixture.team.moving_to[1] = TerrainArmy.INVALID_CELL
	fixture.team.combat_hot_set(1, &"pose", "idle")
	task.cell = int(task.work_cell)
	task.mode = "work"
	var learned_before: Dictionary = row.technology
	row.technology = {}
	var refused_before := var_to_bytes([data.site, row])
	_check(not Runtime.work_preflight(data, task, row.cargo, Runtime.CARRY_CAPACITY, 1, int(fixture.executor)).ok and var_to_bytes([data.site, row]) == refused_before, "An actual unlearned original worker is rejected before effort or materials")
	row.technology = learned_before
	var inputs: Dictionary = Runtime.feature_recipe(feature).input.duplicate(true)
	var cost_before = data.site.inventory.duplicate(true)
	var next_item := int(data.site.next_item)
	var archive := var_to_bytes(data.site.settlement.technology)
	Runtime._feature_work(data, key, float(Runtime.feature_recipe(feature).cycle), Callable(), Callable(), task, row.cargo, Runtime.CARRY_CAPACITY, 1, int(fixture.executor))
	_check(int(data.site.next_item) == next_item + 1 and data.site.item_records[str(next_item)].definition == expected_item and row.item_state.item_ids.has(str(next_item)), "One real armor instance enters its sole original person holder")
	for material: String in inputs: _check(int(data.site.inventory.get(material, 0)) == int(cost_before.get(material, 0)) - int(inputs[material]), "Original armor manufacturing consumes actual %s once" % material)
	_check(feature.technology_output.receipts.size() == 1 and feature.technology_output.receipts[0].item_ids == [str(next_item)] and Runtime.valid_technology_output_state(feature.technology_output, data, key), "Actual output generates one strict current canonical producer receipt")
	_check(var_to_bytes(data.site.settlement.technology) == archive, "Ordinary known armor creates neither a new research project nor a false phase")
	_check(workers.cancel(int(fixture.executor)).ok, "Original task owner stops ordinary operation before the next named recipe")
	Runtime._stop_feature_zones(data, key, "operate")

func _known_armor_and_guards() -> void:
	var fixture := _armor_fixture(true)
	var data: TerrainData = fixture.data
	var row: Dictionary = fixture.row
	var before := var_to_bytes(data.site)
	_check(Runtime.technology_armor_workshop_context(data, str(fixture.smithy), "iron_armor").ok and var_to_bytes(data.site) == before, "True original level-three workshop context is a readonly query")
	_ordinary_armor(fixture, str(fixture.tannery), "leather_armor", "armor:armor_light_leather_01")
	_ordinary_armor(fixture, str(fixture.smithy), "iron_armor", "armor:armor_iron_01")
	var saved_housing: Dictionary = data.site.housing.duplicate(true)
	data.site.housing.clear()
	before = var_to_bytes(data.site)
	_check(not Runtime.technology_armor_workshop_context(data, str(fixture.smithy), "iron_armor").ok and var_to_bytes(data.site) == before and Technology.scope_known(data.site.settlement.technology, "S13"), "Loss of actual residents suspends new operation without deleting known knowledge")
	data.site.housing = saved_housing
	var original_faction := int(data.site.features[fixture.tannery].owner_faction)
	data.site.features[fixture.tannery].owner_faction = 2
	before = var_to_bytes(data.site)
	_check(not Runtime.technology_armor_workshop_context(data, str(fixture.smithy), "iron_armor").ok and var_to_bytes(data.site) == before, "A foreign tannery cannot count as the required same-owner original workshop")
	data.site.features[fixture.tannery].owner_faction = original_faction
	_check(not row.item_state.item_ids.is_empty(), "Earlier legitimate equipment remains in its original holder through suspension")
	_known_arsenal_armor(fixture)
	_cleanup_fixture(fixture.lab, fixture.team)
	await process_frame

func _known_arsenal_armor(fixture: Dictionary) -> void:
	var data: TerrainData = fixture.data
	var lab: TerrainLab = fixture.lab
	var orders = lab.site_controller.equipment_orders
	var nation := Technology.empty_scope_record(str(data.site.id))
	nation.known = ["N01", "N02", "N04", "N11"]
	data.site.equipment_nations = {"n1": {"offices": SiteOffices.default_offices("nation", int(fixture.control)), "members": [int(fixture.control), int(fixture.executor)], "standards": {}, "technology": nation}}
	_check(Stocks.ensure_storage(data, str(fixture.warehouse), 1).ok, "Actual original Warehouse owns the finite private arsenal source")
	_check(lab.character.place(data.cell_from_index(int(data.site.features[fixture.warehouse].entrance)), true), "Actual grantor reaches the true Warehouse contact")
	var labor_ids: Array[int] = [int(fixture.executor)]
	_check(orders.register_nation_labor(int(fixture.control), "n1", labor_ids).ok, "Original national duty and actual team consent name the real armor worker")
	orders.nation_arsenal_request = func(nation_id: String, selected_order: String, prospective_order: Dictionary, preview_only: bool) -> Dictionary:
		if preview_only and not data.site.equipment_nations[nation_id].technology_operations.public_orders.has(selected_order): return orders._arsenal_workshop_context(prospective_order)
		return Runtime.begin_nation_technology_operation(data, nation_id, selected_order, preview_only)
	var issued = orders.request_arsenal_order(int(fixture.control), "n1", "armor", str(fixture.smithy), int(fixture.executor), str(fixture.warehouse))
	_check(issued.ok, "True N11 original owner registers one bounded armor order in the genuinely effective level-three settlement")
	var reserve := _fund(lab, str(issued.order_id), {"iron": 4, "leather": 2, "charcoal": 2}, str(fixture.warehouse))
	var camp = data.site.inventory.duplicate(true)
	var next_item := int(data.site.next_item)
	var started := Runtime.begin_nation_technology_operation(data, "n1", str(issued.order_id))
	# Core technology debits subtract to zero and keep the key (Tech 12:37 = D),
	# so the funded reserve is spent when no positive amount remains.
	_check(started.ok and data.site.inventory == camp and reserve.cargo.values().all(func(amount: Variant) -> bool: return int(amount) == 0), "One actual private Warehouse payment starts N11 without silently taking any camp material")
	_check(Runtime.validate_technology_target_storage(data, str(fixture.smithy), data.site.features[fixture.smithy]).ok, "Strict original target validator accepts the real bounded source/order ledger")
	_finish_feature(lab, fixture.team, int(fixture.executor), str(fixture.smithy), 15.0)
	var order: Dictionary = data.site.equipment_nations.n1.technology_operations.public_orders[issued.order_id]
	_check(int(data.site.next_item) == next_item + 1 and data.site.item_records[str(next_item)].definition == "armor:armor_iron_01" and order.receipts.size() == 1, "Actual original N11 output emits exactly one iron armor and its first order receipt")
	# N11 completes on its second receipt: the original public acceptance job
	# (administration, the "arsenal" binding) by the same operator on that item.
	var admin_actions: SitePersonActions = lab.site_controller.person_actions
	var admin_before := var_to_bytes([data.site, admin_actions._jobs.keys()])
	# Command authority is unchanged: a requester other than the controlled head is refused.
	_check(not admin_actions.begin_nation_administration(int(fixture.executor), "n1", str(issued.order_id), "arsenal").ok and var_to_bytes([data.site, admin_actions._jobs.keys()]) == admin_before, "A requester without command authority cannot start the arsenal acceptance")
	# The worker is the named operator: if he cannot work, no other person is substituted.
	var operator_index: int = fixture.team.index_for_identity(int(fixture.executor))
	var operator_hp: float = float(fixture.team.combat_hot_get(operator_index, &"hp"))
	fixture.team.combat_hot_set(operator_index, &"hp", 0.0)
	_check(not lab.site_controller._nation_ui_command("n1", "administration", {"order": str(issued.order_id)}).ok and var_to_bytes([data.site, admin_actions._jobs.keys()]) == admin_before, "With its named operator unable to work, acceptance is refused rather than run by another person")
	fixture.team.combat_hot_set(operator_index, &"hp", operator_hp)
	var accepted: Dictionary = lab.site_controller._nation_ui_command("n1", "administration", {"order": str(issued.order_id)})
	_check(accepted.ok, "Actual public acceptance form begins the original arsenal job: " + str(accepted))
	_check(admin_actions._jobs.has(str(int(fixture.executor))) and not admin_actions._jobs.has(str(int(lab.controlled_person_id()))), "The arsenal acceptance job runs on the named operator, not on the requester")
	var acceptance_steps := 0
	while lab.site_controller.person_actions.is_busy(int(fixture.executor)) and acceptance_steps < 2000:
		var point: Dictionary = lab._advance_original_shared_step(TerrainLab.EXCHANGE_ACTION_STEP if lab.exchange_enabled else TerrainLab.ACTION_STEP)
		if not point.ok: break
		acceptance_steps += 1
	_check(order.receipts.size() == 2 and order.status == "complete" and int(data.site.next_item) == next_item + 1, "Actual original N11 acceptance adds the arsenal receipt and completes the order without a second item")
	var before := var_to_bytes(data.site)
	_check(not Runtime.begin_nation_technology_operation(data, "n1", str(issued.order_id)).ok and var_to_bytes(data.site) == before, "The completed original arsenal order cannot buy or fabricate a second armor")
	_check(not Technology.learned(fixture.row.technology, "F06"), "An ordinary known order creates equipment without teaching the armor skill")

func _fresh_armor_research() -> void:
	var fixture := _armor_fixture(false)
	var data: TerrainData = fixture.data
	var lab: TerrainLab = fixture.lab
	var actions = fixture.actions
	var scope_id := str(fixture.settlement_id)
	_check(actions.prepare_scope_technology(int(fixture.control), int(fixture.executor), "S13", scope_id).ok, "Original head and actual learned worker prepare this real S13 project")
	_check(lab.character.place(Vector2i(9, 10) + Vector2i(fixture.natural_offset), true) and actions.grant_scope_technology_budget(int(fixture.control), "settlement", scope_id, {"leather": 6, "fiber": 2, "iron": 4, "charcoal": 2}).ok and actions.request_scope_technology_consent(int(fixture.control), "settlement", scope_id, int(fixture.executor)).ok, "True camp grant and actual original team consent authorize only the exact finite armor stages")
	for phase: Dictionary in [{"binding": "leather_armor", "key": fixture.tannery, "item": "armor:armor_light_leather_01"}, {"binding": "iron_armor", "key": fixture.smithy, "item": "armor:armor_iron_01"}]:
		var next_item := int(data.site.next_item)
		_check(actions.begin_scope_technology_phase(int(fixture.control), "settlement", scope_id, str(phase.binding), "feature:" + str(phase.key)).ok, "Original phase API starts this genuine physical armor trial before S13 known")
		if str(phase.binding) == "leather_armor":
			var task := _at_feature(lab, fixture.team, int(fixture.executor), str(phase.key))
			var feature: Dictionary = data.site.features[phase.key]
			Runtime._feature_work(data, str(phase.key), float(Runtime.feature_recipe(feature).cycle), Callable(), Callable(), task, fixture.row.cargo, 0, 1, int(fixture.executor))
			var pending := Technology.active_project(data.site.settlement.technology)
			_check(int(data.site.next_item) == next_item and feature.batch_paid and float(feature.production) == float(Runtime.feature_recipe(feature).cycle) and pending.receipts.is_empty() and not Technology.scope_known(data.site.settlement.technology, "S13"), "Real output capacity failure preserves paid completed work and grants no fabricated item or phase")
		_finish_feature(lab, fixture.team, int(fixture.executor), str(phase.key), float(Runtime.feature_recipe(data.site.features[phase.key]).cycle))
		_check(int(data.site.next_item) == next_item + 1 and data.site.item_records[str(next_item)].definition == str(phase.item), "The actual research stage emits the original unique armor instance")
	var record: Dictionary = data.site.settlement.technology
	var project: Dictionary = record.projects[0]
	_check(Technology.scope_known(record, "S13") and project.receipts.size() == 2 and project.budget.payments.size() == 2 and project.budget.spent == {"leather": 6, "fiber": 2, "iron": 4, "charcoal": 2}, "Two actual outputs and exact true payments close S13 on its original settlement owner")
	_check(not Technology.learned(fixture.row.technology, "S13"), "Settlement knowledge does not masquerade as an individual family skill")
	_cleanup_fixture(lab, fixture.team)
	await process_frame

func _level_one_rejects() -> void:
	var fixture := _armor_fixture(true, false)
	var data: TerrainData = fixture.data
	var before := var_to_bytes(data.site)
	_check(not Runtime.technology_armor_workshop_context(data, str(fixture.smithy), "iron_armor").ok and var_to_bytes(data.site) == before, "A genuinely effective level-one settlement cannot use known archive alone to admit a new level-three armor work order")
	_cleanup_fixture(fixture.lab, fixture.team)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	await _known_armor_and_guards()
	await _fresh_armor_research()
	await _level_one_rejects()
	TerrainArmy.release_contact_source()
	print("SITE_TECHNOLOGY_ARMOR_RECIPES_PASS: %d checks; real forty-person housing/paid levels, ordinary original leather+iron items, strict physical guards, two original S13 paid phases and finite N11 private output; travel/sharedclock/Native/render/full40 excluded" % checks)
	quit(0)

# Fixture-only unchanged natural source helpers; no research or clock owner.
func _cold_natural_template(specs: Array, site_id: String, extra: Array[Vector2i] = [], stride: int = 1, paths: Array = []) -> Dictionary:
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345)
	Env.initialize(data, site_id)
	# Bound/loaded/visited Sites carry item storage; Core building payment reads its depot.
	var fixture_item_storage = Runtime.initialize_item_storage(data.site)
	assert(fixture_item_storage.ok, "Fixture natural world carries original item storage")
	for item: String in Env.ITEM_NAMES: data.site.inventory[item] = 10000
	data.site.capacity = 1000000
	# Only translate fixture infrastructure on the unchanged source. Every
	# candidate uses the original geometry/material/soil preview before adoption.
	for radius: int in range(101):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if absi(x) + absi(y) != radius or posmod(x, stride) != 0 or posmod(y, stride) != 0: continue
				var offset := Vector2i(x, y)
				var valid := true
				for original: Vector2i in extra:
					var cell := original + offset
					if not data.contains(cell) or not data.is_walkable(cell): valid = false; break
				if not valid: continue
				for path: Array in paths:
					var cells: Array[int] = []
					var level := -1
					for original: Vector2i in path:
						var cell := original + offset
						if not data.contains(cell): valid = false; break
						var index := data.index(cell)
						if level < 0: level = int(data.height_levels[index])
						if data.ramp_edges[index] != 0 or int(data.height_levels[index]) != level or data.foundation[index] < 35: valid = false; break
						cells.append(index)
					if not valid or not Runtime._irrigation_path(data, cells): valid = false; break
				if not valid: continue
				var plans: Array[Dictionary] = []
				var used := {}
				for spec: Dictionary in specs:
					var options := {"layout_version": 1, "quarter": 0, "owner_faction": 1}
					options.merge(spec.get("options", {}), true)
					var geometry := Runtime.building_cells(data, str(spec.kind), Vector2i(spec.anchor) + offset, Vector2i(spec.extent), options)
					if not geometry.ok: valid = false; break
					for cell: int in geometry.cells:
						if used.has(cell): valid = false; break
						used[cell] = true
					if not valid: break
					var preview := Runtime.preview_build(data, str(spec.kind), geometry.cells, Callable(), options)
					if not preview.ok: valid = false; break
					plans.append({"kind": str(spec.kind), "anchor": Vector2i(spec.anchor) + offset, "extent": Vector2i(spec.extent), "options": options, "geometry": geometry, "preview": preview})
				if valid:
					return {"data": data, "offset": offset, "plans": plans}
	assert(false, "Original natural source must admit the finite fixture template without modifying terrain/soil")
	return {}

func _cold_natural_feature(data: TerrainData, kind: String, anchor: Vector2i, extent: Vector2i = Vector2i.ONE, options: Dictionary = {}) -> String:
	var settings := {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	settings.merge(options, true)
	var geometry := Runtime.building_cells(data, kind, anchor, extent, settings)
	assert(geometry.ok, str(geometry))
	var preview := Runtime.preview_build(data, kind, geometry.cells, Callable(), settings)
	assert(preview.ok, str(preview))
	for key: String in preview.get("clearing", []): Env.change(data, key, {"cleared": true, "remaining": 0})
	return _formal_feature(data, kind, anchor, extent, settings)

func _cold_natural_conditions(data: TerrainData) -> PackedByteArray:
	return var_to_bytes([data.fertility, data.moisture, data.drainage, data.foundation, data.groundwater])

