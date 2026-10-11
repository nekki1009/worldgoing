extends "res://scripts/tests/site_technology_armor_recipes_test.gd"
## Physical S12 slice only: original level-two settlement, actual two Army
## workers, original local holder/contact transfers and strict Store roundtrip.
## Requires the guarded S12 enabled integration candidate; no all40/Native/
## travel/finite ship-cooperation-order or F13 time-effect acceptance.

const ShipStore = preload("res://scripts/terrain_lab/site_store.gd")

func _shipyard_natural_geometry(data: TerrainData, kind: String, near: Vector2i, extent: Vector2i = Vector2i.ONE, settings: Dictionary = {}, max_radius: int = 24) -> Dictionary:
	var options := {"layout_version": 1, "quarter": 0, "owner_faction": 1}
	options.merge(settings, true)
	for radius: int in range(max_radius + 1):
		for y: int in range(-radius, radius + 1):
			for x: int in range(-radius, radius + 1):
				if absi(x) + absi(y) != radius: continue
				var anchor := near + Vector2i(x, y)
				var geometry := Runtime.building_cells(data, kind, anchor, extent, options)
				if not geometry.ok: continue
				if data.site.has("settlement"):
					var in_domain := false
					for cell: int in geometry.cells: in_domain = in_domain or Settlement.cell_in_jurisdiction(data,data.cell_from_index(cell))
					if not in_domain: continue
				var preview := Runtime.preview_build(data, kind, geometry.cells, Callable(), options)
				if not preview.ok: continue
				return {"anchor":anchor,"cells":geometry.cells,"options":options,"preview":preview}
	return {}

func _shipyard_natural_host(data: TerrainData, kind: String, near: Vector2i, extent: Vector2i = Vector2i.ONE, options: Dictionary = {}) -> String:
	var geometry := _shipyard_natural_geometry(data, kind, near, extent, options)
	_check(not geometry.is_empty(), "Pure finite natural scan supplies original " + kind)
	for key: String in geometry.preview.get("clearing", []): Env.change(data, key, {"cleared":true,"remaining":0})
	return _formal_feature(data, kind, geometry.anchor, extent, geometry.options)

func _shipyard_natural_shore(data: TerrainData) -> Dictionary:
	# True generated shoreline and original full waterfront/launch guards.
	# No surface/flag/water/height/soil field is patched by this fixture.
	for index: int in range(data.size.x * data.size.y):
		var anchor := data.cell_from_index(index)
		if anchor.x < 8 or anchor.y < 8 or anchor.x >= data.size.x - 8 or anchor.y >= data.size.y - 8: continue
		for quarter: int in range(4):
			var geometry := Runtime.building_cells(data, "shipyard", anchor, Vector2i(4,3), {"layout_version":1,"quarter":quarter,"owner_faction":1})
			if not geometry.ok: continue
			for shore_index: int in geometry.cells:
				var launch := data.cell_from_index(shore_index) + TerrainData.DIRECTIONS[quarter]
				if not data.contains(launch) or not data.can_place_water_vehicle(Runtime.Ships.footprint("ferry",launch,TerrainData.DIRECTIONS[quarter])): continue
				var options := {"layout_version":1,"quarter":quarter,"owner_faction":1,"waterfront_version":1,"launch_cell":data.index(launch)}
				var preview := Runtime.preview_build(data,"shipyard",geometry.cells,Callable(),options)
				if not preview.ok: continue
				return {"anchor":anchor,"cells":geometry.cells,"options":options,"preview":preview}
	return {}

func _shipyard_natural_team(lab: TerrainLab, center: Vector2i) -> TerrainArmy:
	var team := TerrainArmy.new()
	root.add_child(team)
	team.set_process(false)
	team.team_id = 401
	team.roster_size = 40
	team.faction_id = 1
	team.person_id_allocator = Callable(lab, "_allocate_army_person_ids")
	var cells: Array[Vector2i] = []
	for radius: int in range(32):
		for y: int in range(-radius,radius+1):
			for x: int in range(-radius,radius+1):
				if absi(x)+absi(y)!=radius or cells.size()>=40: continue
				var cell := center + Vector2i(x,y)
				if lab.terrain.contains(cell) and lab.terrain.is_walkable(cell) and cell not in [lab.character.terrain_cell,lab.npc.terrain_cell]: cells.append(cell)
	_check(cells.size()==40 and team.deploy_at(lab.terrain,lab.character,lab.npc,cells) and team.enable_combat(false), "Original finite Army/allocator owns exactly forty real NPCs on generated legal cells")
	lab.combat_armies.append(team)
	team.controlled_person_query = lab.controlled_person_id
	team.person_busy_query = lab.site_controller.person_actions.is_busy
	team.settle_combat_command()
	_check(team.set_duty_ai_enabled(team.combat_identity(team.formal_commander),true).ok, "Living original captain explicitly enables the actual duty AI")
	for row: Dictionary in team.combat_units:
		row.cargo={}
		row.item_state=Runtime.new_item_state("person:"+str(row.person_id))
	return team

func _shipyard_source_bytes(data: TerrainData) -> PackedByteArray:
	return var_to_bytes([data.fertility,data.moisture,data.drainage,data.foundation,data.groundwater])

func _shipyard_fixture() -> Dictionary:
	var data: TerrainData
	var shore := {}
	for seed_value: int in [17,12345,98761]:
		data=TerrainGenerator.generate(TerrainPreset.Kind.COASTAL_CLIFF,seed_value,{"max_height":1,"micro_strength":0})
		Env.initialize(data,"technology-s12-natural-shore-"+str(seed_value))
		# Bound/loaded/visited Sites carry item storage; Core building payment reads its depot.
		var fixture_item_storage = Runtime.initialize_item_storage(data.site)
		assert(fixture_item_storage.ok, "Fixture natural world carries original item storage")
		for material: String in Env.ITEM_NAMES: data.site.inventory[material]=10000
		data.site.capacity=1000000
		shore=_shipyard_natural_shore(data)
		if not shore.is_empty(): break
	_check(not shore.is_empty(), "Existing natural coastal source admits one legal original shipyard launch")
	var lab:=_shipyard_natural_lab(data)
	var control:=lab.controlled_person_id()
	var actions: SitePersonActions=lab.site_controller.person_actions
	# Prior physical infrastructure uses original request/completion only.
	for key: String in shore.preview.get("clearing",[]): Env.change(data,key,{"cleared":true,"remaining":0})
	var yard:=_formal_feature(data,"shipyard",shore.anchor,Vector2i(4,3),shore.options)
	var center_plan:=_shipyard_natural_geometry(data,"settlement_center",shore.anchor,Vector2i(5,5),{},18)
	_check(not center_plan.is_empty(), "Original coastal dry ground admits the same-owner center within the original jurisdiction")
	_check(lab.character.place(data.cell_from_index(int(center_plan.preview.entrance)),true), "Actual founder reaches the pure original founding station")
	for key: String in center_plan.preview.get("clearing",[]): Env.change(data,key,{"cleared":true,"remaining":0})
	var center_cells: Array[int]=[]
	center_cells.assign(center_plan.cells)
	var founded:=Settlement.found(lab,control,center_cells,center_plan.options)
	_check(founded.ok, "Original founding owner creates the true coastal Settlement")
	_complete_key(data,str(founded.feature))
	var center =center_plan.anchor
	var houses: Array[String]=[]
	for index: int in range(10):
		houses.append(_shipyard_natural_host(data,"house",center+Vector2i((index%5-2)*6,(floori(float(index)/5.0)*2-1)*12),Vector2i.ONE,{"variant":"large"}))
	var team:=_shipyard_natural_team(lab,center)
	var slots: Array[Dictionary]=[]
	# Fixture worlds carry generated natural resources; clear any on each house's
	# entrance row (as for the center clearing) so its real slots are counted.
	for fixture_house: String in houses:
		var fixture_feature: Dictionary = data.site.features[fixture_house]
		for fixture_pair: Dictionary in Runtime._building_entrances(data, fixture_feature.cells, int(fixture_feature.quarter)):
			for fixture_key: String in Env.resources_in(data, Rect2i(fixture_pair.cell, Vector2i.ONE)): Env.change(data, fixture_key, {"cleared": true, "remaining": 0})
	Env.rebuild_indexes(data)
	for house: String in houses:
		var layout:=Runtime.house_layout(data,house)
		_check(layout.ok,"Original completed natural house resolves its true resident slots")
		for cell: int in layout.slots: slots.append({"house_id":house,"cell":cell})
	if slots.size() < 40:
		# Ten houses fell short on this generated world (height step / edge overlap);
		# one more genuine large house keeps a real house slot for every resident.
		var extra_house: String = _shipyard_natural_host(data, "house", center + Vector2i(12, 0), Vector2i.ONE, {"variant": "large"})
		var extra_feature: Dictionary = data.site.features[extra_house]
		for fixture_pair: Dictionary in Runtime._building_entrances(data, extra_feature.cells, int(extra_feature.quarter)):
			for fixture_key: String in Env.resources_in(data, Rect2i(fixture_pair.cell, Vector2i.ONE)): Env.change(data, fixture_key, {"cleared": true, "remaining": 0})
		Env.rebuild_indexes(data)
		houses.append(extra_house)
		# The new house can take cells from a neighbour's entrance row: recount all.
		slots.clear()
		for recount_house: String in houses:
			for cell: int in Runtime.house_layout(data, recount_house).slots: slots.append({"house_id": recount_house, "cell": cell})
	_check(slots.size()>=40,"True original houses hold forty separate original residents")
	data.site.housing={}
	var people: Dictionary={}
	for index: int in range(40):
		var identity:=team.combat_identity(index)
		data.site.housing[str(identity)]={"version":1,"house_id":str(slots[index].house_id),"cell":int(slots[index].cell)}
		people[identity]={"hp":float(team.combat_units[index].hp),"faction_id":1}
	_check(Homes.validate(data,data.site,people).ok and Settlement.residents(lab).size()==40,"Unchanged original Housing admits the real forty-person prior-world population")
	var warehouse:=_shipyard_natural_host(data,"warehouse",center)
	_shipyard_natural_host(data,"well",center)
	_shipyard_natural_host(data,"farm",center,Vector2i(2,2))
	_check(Settlement.request_upgrade(lab,control).ok,"Original actual prerequisites and payment permit the genuine level-two upgrade")
	_complete_key(data,str(founded.feature))
	_check(Settlement.status(lab).effective and int(Settlement.status(lab).level)==2,"True same-owner settlement is effective at level two")
	data.site.settlement.version=2
	data.site.settlement.technology=Technology.empty_scope_record(str(data.site.id))
	data.site.settlement.technology.known=["S12"]
	var executor:=team.combat_identity(1)
	var row: Dictionary=team.combat_units[1]
	row.technology=Technology.learned_candidate({},"F13")
	var refs: Array=[]
	for identity: int in [control,executor]: refs.append({"site_id":str(data.site.id),"person_id":identity,"path":"","label":"Original artisan","age_years":-1})
	_check(lab.site_controller.family_continuity.register_members(refs,true,control).ok and lab.site_controller.family_continuity.appoint_head(control,control).ok,"Actual registry/head establish the original prerequisite archive")
	data.site.family=actions._technology_candidate()
	# A v1 family technology record admits only F07; F13 lives in the scope record.
	data.site.family.technology=Technology.empty_scope_record(str(data.site.id))
	data.site.family.technology.known=["F13"]
	_check(Family.validate_family(data.site.family,str(data.site.id)),"Original pure candidate yields valid Family v3 before explicit prerequisite knowledge")
	var feature: Dictionary=data.site.features[yard]
	# Adoption requires the named F13 master inside the shipyard footprint, not at its entrance.
	var master_cell:=int(feature.entrance)
	for fixture_cell: int in feature.cells:
		if data.is_walkable(data.cell_from_index(fixture_cell)): master_cell=fixture_cell; break
	team.cells[1]=data.cell_from_index(master_cell)
	return {"data":data,"lab":lab,"team":team,"row":row,"executor":executor,"control":control,"actions":actions,"warehouse":warehouse,"settlement_id":str(data.site.settlement.settlement_id),"center":str(founded.feature),"yard":yard}

func _shipyard_natural_lab(data: TerrainData) -> TerrainLab:
	var lab := TerrainLab.new()
	lab.npc = TerrainTestNPC.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.character.set_process(false)
	lab.npc.set_process(false)
	lab.site_controller._auto_save_blocked = true
	lab.bind_terrain(data)
	lab.character.faction_id = 1
	lab.npc.faction_id = 1
	var camp := data.cell_from_index(int(data.site.depot_cell))
	_check(lab.character.place(camp, true), "Actual Actor stands at the original generated camp")
	var npc_cell := Vector2i(-1, -1)
	for direction: Vector2i in TerrainData.DIRECTIONS:
		var cell := camp + direction
		if data.contains(cell) and data.is_walkable(cell) and data.can_step(camp, cell):
			npc_cell = cell
			break
	_check(npc_cell.x >= 0 and lab.npc.place(npc_cell, true), "Second original Actor has a distinct legal generated camp contact")
	lab.site_controller.release_worker()
	return lab

func _shipyard_guards_and_true_local_holder() -> void:
	var fixture := _shipyard_fixture()
	var data: TerrainData = fixture.data
	var lab: TerrainLab = fixture.lab
	var feature: Dictionary = data.site.features[fixture.yard]
	var before := var_to_bytes([data.site, fixture.row])
	_check(Runtime.configure_shipyard_work(data, str(fixture.yard), int(fixture.control), int(fixture.executor), true, true).ok and var_to_bytes([data.site, fixture.row]) == before, "True original head/F13 adoption preview is entirely readonly")
	_check(not Runtime.configure_shipyard_work(data, str(fixture.yard), int(fixture.executor), int(fixture.executor)).ok and var_to_bytes([data.site, fixture.row]) == before, "A real non-head cannot obtain two stations by caller identity")
	var learned: Dictionary = fixture.row.technology
	fixture.row.technology = {}
	before = var_to_bytes([data.site, fixture.row])
	_check(not Runtime.configure_shipyard_work(data, str(fixture.yard), int(fixture.control), int(fixture.executor)).ok and var_to_bytes([data.site, fixture.row]) == before, "Unlearned true artisan is rejected without config/material/effort changes")
	fixture.row.technology = learned
	_check(Runtime.configure_shipyard_work(data, str(fixture.yard), int(fixture.control), int(fixture.executor)).ok, "Actual original head explicitly adopts the genuine shore feature")
	var context := Runtime.technology_shipyard_work_context(data, str(fixture.yard))
	_check(context.ok and is_same(context.feature, feature) and is_same(context.settlement, data.site.settlement) and context.slots.size() == 2 and context.slots[0].cell != context.slots[1].cell, "Readonly geometry and current eligibility resolve the same true shipyard and two distinct dry original cells")
	before = var_to_bytes(data.site)
	_check(not Runtime.cancel_feature(data, str(fixture.yard), Callable(), 1).ok and var_to_bytes(data.site) == before, "Generic faction demolition cannot bypass original-head revocation or leave invalid saved station refs")
	var malformed := feature.duplicate(true)
	malformed.technology_shipyard_work.extra = true
	_check(not Runtime.valid_technology_shipyard_work(malformed) and not Stocks.eligible(malformed), "Malformed config fails both original layout and local-holder admission")
	_check(Stocks.ensure_storage(data, str(fixture.warehouse), 1).ok and Stocks.ensure_storage(data, str(fixture.yard), 1).ok, "Only original Stockpiles creates the actual Warehouse and shipyard holders")
	_check(Stocks.capacity(feature) == 660 and Stocks.capacity(feature) >= Runtime.inventory_size(Runtime.Ships.build_cost("ferry")), "One original holder accommodates one complete largest existing hull recipe without creating supply rights")
	var actor: Dictionary = fixture.actions._person(int(fixture.control))
	var cost := Runtime.Ships.build_cost("ferry")
	# Explicit starting-world resources belong to the real original Actor. Both
	# subsequent transfers use actual owner/contact/version permission, no mock.
	actor.cargo.clear()
	for item: String in cost: actor.cargo[item] = int(cost[item])
	var source := Stocks.storage(data, str(fixture.warehouse))
	var destination := Stocks.storage(data, str(fixture.yard))
	var vehicles = lab.site_controller.vehicles
	# The warehouse host scan ignores fixture army positions, so a member can stand on
	# its entrance; step him to a free cell so the real carrier reaches the contact.
	var contact_cell: Vector2i = data.cell_from_index(int(data.site.features[fixture.warehouse].entrance))
	var fixture_team: TerrainArmy = fixture.team
	for unit_index: int in fixture_team.cells.size():
		if fixture_team.cells[unit_index] != contact_cell: continue
		var moved := false
		for radius: int in range(1, 6):
			for offset: Vector2i in [Vector2i(radius, 0), Vector2i(-radius, 0), Vector2i(0, radius), Vector2i(0, -radius)]:
				var spot: Vector2i = contact_cell + offset
				if data.contains(spot) and data.is_walkable(spot) and data.feature_at[data.index(spot)] == 0 and not fixture_team.cells.has(spot) and spot != lab.character.terrain_cell:
					fixture_team._cell_owners.erase(contact_cell)
					fixture_team.cells[unit_index] = spot
					fixture_team._cell_owners[spot] = unit_index
					moved = true
					break
			if moved: break
	_check(lab.character.place(data.cell_from_index(int(data.site.features[fixture.warehouse].entrance)), true), "Actual carrier reaches original Warehouse contact")
	_check(vehicles.transfer("person:" + str(fixture.control), "feature:" + str(fixture.warehouse), cost, [], int(actor.holder.version), int(source.holder.version), int(fixture.control)).ok, "True original Actor deposits its starting materials once into the real source holder")
	var depot = data.site.inventory.duplicate(true)
	_check(vehicles.transfer("feature:" + str(fixture.warehouse), "person:" + str(fixture.control), cost, [], int(source.holder.version), int(actor.holder.version), int(fixture.control)).ok, "At the first true contact the existing original carrier takes the actual cargo")
	_check(source.cargo.is_empty() and actor.cargo == cost and destination.cargo.is_empty(), "The first transfer has one real holder owner and no virtual remote delivery")
	before = var_to_bytes([data.site, actor.cargo, actor.holder])
	_check(not vehicles.transfer("person:" + str(fixture.control), "feature:" + str(fixture.yard), cost, [], int(actor.holder.version), int(destination.holder.version), int(fixture.control)).ok and var_to_bytes([data.site, actor.cargo, actor.holder]) == before, "Remote second contact fails byte-equivalently before any cargo mutation")
	_check(lab.character.place(data.cell_from_index(int(feature.entrance)), true), "The same actual carrier reaches the original destination contact")
	_check(vehicles.transfer("person:" + str(fixture.control), "feature:" + str(fixture.yard), cost, [], int(actor.holder.version), int(destination.holder.version), int(fixture.control)).ok, "Second true contact delivers to the same original shipyard local holder once")
	_check(actor.cargo.is_empty() and destination.cargo == cost and data.site.inventory == depot and Stocks.validate(data.site).ok, "Actual two-contact delivery never copies stock or debits camp manufacture")
	_check(Stocks.set_local_supply(data, str(fixture.yard), true, 1).ok and feature.supply_mode == "local", "Original current source selection explicitly names the real shipyard local holder")
	_check(Runtime.configure_shipyard_work(data, str(fixture.yard), int(fixture.control), 0, false).ok and not feature.has("technology_shipyard_work") and Stocks.storage(data, str(fixture.yard)).cargo == cost, "Lawful clear revocation preserves original material property and restores the existing one-station feature")
	_cleanup_fixture(lab, fixture.team)
	await process_frame

func _shipyard_work_point(fixture: Dictionary, seconds: float) -> Dictionary:
	var lab: TerrainLab = fixture.lab
	var workers = lab.site_controller.work_team
	lab._shared_work_requests = workers.prepare_work_requests(seconds)
	_check(lab._refresh_shared_work_preflight().ok, "Original WorkTeam final requests revalidate both true shore stations")
	var captured = workers.prepare_shared_work_prefix(seconds)
	var planned := PersonFatigue.plan_work_interval(lab._shared_work_requests, seconds)
	_check(captured.ok and planned.ok, "Original two-person references and Fatigue planner capture the actual interval")
	var priors: Array = []
	var before := var_to_bytes([lab.terrain.site, fixture.team.capture_combat_state()])
	var admitted = workers.validate_shared_work_prefix(captured, planned, priors)
	_check(admitted.ok and var_to_bytes([lab.terrain.site, fixture.team.capture_combat_state()]) == before, "All same-target physical prefix candidates are pure before material/fatigue mutation")
	lab._shared_work_plan = planned
	lab.site_controller._shared_work_plan = planned
	lab._shared_work_pools_committed = false
	lab._commit_shared_work_pools()
	workers.publish_shared_work_prefix(admitted)
	var progress: Dictionary = lab.terrain.site.features[fixture.yard].duplicate(true)
	var fatigue: Dictionary = fixture.team.team_fatigue.duplicate(true)
	workers.publish_shared_work_prefix(admitted)
	lab._commit_shared_work_pools()
	_check(lab.terrain.site.features[fixture.yard] == progress and fixture.team.team_fatigue == fatigue, "The same actual registered interval spends work and pooled fatigue only once")
	workers.finish_shared_work_prefix(admitted)
	return admitted

func _two_true_workers_and_suspended_save() -> void:
	var fixture := _shipyard_fixture()
	var data: TerrainData = fixture.data
	var lab: TerrainLab = fixture.lab
	var team: TerrainArmy = fixture.team
	var feature: Dictionary = data.site.features[fixture.yard]
	_check(Runtime.configure_shipyard_work(data, str(fixture.yard), int(fixture.control), int(fixture.executor)).ok, "The original head adopts the same actual two-slot hull workplace")
	var stock = data.site.inventory.duplicate(true)
	var cost := Runtime.Ships.build_cost("ferry")
	_check(Runtime.begin_ship_build(data, str(fixture.yard), "ferry", int(team.team_id), 1).ok, "Existing original hull manufacture still pays its true complete original cost")
	for item: String in cost: _check(int(data.site.inventory[item]) == int(stock[item]) - int(cost[item]), "Original hull material %s is debited once" % item)
	var workers = lab.site_controller.work_team
	var identities: Array[int] = [int(fixture.executor), team.combat_identity(2)]
	_check(workers.assign(team, identities, team.duty_decider("team.work")).ok, "True current original team duty assigns its actual artisan and actual helper")
	workers.prepare_work_requests(30.0)
	var claims := {}
	for identity: int in identities:
		var index := team.index_for_identity(identity)
		var task: Dictionary = team.combat_units[index].work_task
		_check(task.target == "feature:" + str(fixture.yard) and task.action == "operate" and not claims.has(int(task.work_slot)), "Original selector gives each true person a different actual shipyard work cell")
		claims[int(task.work_slot)] = true
		team.cells[index] = data.cell_from_index(int(task.work_cell))
		task.cell = int(task.work_cell)
		task.mode = "work"
		_check(SiteWorkTeam.valid_task(data, data.site, task), "Original task validator admits the same actual shore station")
	_check(claims.has(0) and claims.has(1), "Both original physical shore stations are held by true separate people")
	var archive := var_to_bytes([data.site.family.technology, data.site.settlement.technology])
	var admitted := _shipyard_work_point(fixture, 30.0)
	_check(admitted.runtime.size() == 2 and is_equal_approx(float(feature.production), 1.0), "Two actual thirty-second contributions advance one real hull by sixty physical seconds")
	_check(var_to_bytes([data.site.family.technology, data.site.settlement.technology]) == archive, "Ordinary physical collaboration never fabricates a research phase or individual skill")
	var housing: Dictionary = data.site.housing
	data.site.housing = {}
	_check(Runtime.feature_work_slots(data, feature).size() == 2 and not Runtime.technology_shipyard_work_context(data, str(fixture.yard)).ok, "Loss of effective settlement suspends work while preserving paid progress and both saved physical stations")
	lab.site_controller._capture_positions()
	_check(ShipStore.save(data, "user://technology_s12_physical_suspended.json").ok, "Original Store saves the true suspended hull with actual two-person tasks")
	var source_fingerprint := data.fingerprint()
	var source_conditions := _shipyard_source_bytes(data)
	var loaded := ShipStore.load_site("user://technology_s12_physical_suspended.json")
	_check(loaded.ok, "Original strict loader accepts the original suspended two-station feature")
	var restored: TerrainData = loaded.get("data", loaded.get("terrain"))
	_check(restored != null and restored.fingerprint()==source_fingerprint and _shipyard_source_bytes(restored)==source_conditions,"Cold restores the same natural Generator/Env source and all five original land conditions")
	_check(restored != null and Runtime.feature_work_slots(restored, restored.site.features[fixture.yard]).size() == 2 and restored.site.features[fixture.yard].ship_build == feature.ship_build, "True original load preserves station geometry and original paid hull job without granting effect")
	for row: Dictionary in restored.site.armies[0].units:
		if row.get("work_task", {}).get("target") == "feature:" + str(fixture.yard): _check(SiteWorkTeam.valid_task(restored, restored.site, row.work_task), "Restored true task resolves its original candidate-state station")
	data.site.housing = housing
	for identity: int in identities: _check(workers.cancel(identity).ok, "Original task owner stops its own physical work before cleanup")
	_check(Runtime.cancel_ship_build(data, str(fixture.yard), 1).ok, "Existing original camp-paid hull cancellation remains on its original payment owner")
	_check(Runtime.configure_shipyard_work(data, str(fixture.yard), int(fixture.control), 0, false).ok, "Actual original head can revoke the genuinely clear shore workplace")
	_cleanup_fixture(lab, team)
	await process_frame

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	await _shipyard_guards_and_true_local_holder()
	await _two_true_workers_and_suspended_save()
	TerrainArmy.release_contact_source()
	print("SITE_TECHNOLOGY_SHIPYARD_PHYSICAL_PASS: %d checks; original level2/two true shore workers/SAME holder two-contact transfers/suspended Store; finite S12 orders/F13 effect/Native/travel/all40 excluded" % checks)
	quit(0)
