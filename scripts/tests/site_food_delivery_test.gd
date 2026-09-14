extends "res://scripts/tests/site_workflow_test.gd"
## Original Controller common fatigue/food entry, actual source references and
## post-contact commit. Headless 20 / internal inherited 15 s; not visual/FPS.
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
const OUTPUT := "res://output/site_food_delivery"

func _near(actual: float, expected: float, label: String = "") -> void:
	assert(absf(actual - expected) < 0.000001, "%s: %.12f != %.12f" % [label, actual, expected])

func _food(lab: TerrainLab) -> float:
	var total := 0.0
	var stock: Array[Dictionary] = [lab.terrain.site.inventory, lab.terrain.site.manual.cargo, lab.terrain.site.worker.cargo]
	for team: TerrainArmy in lab.combat_armies:
		for row: Dictionary in team.combat_units:
			stock.append(row.cargo)
	for entry: Dictionary in lab.terrain.site.team_supply.values():
		stock.append(entry.inventory)
		total += float(entry.sustain.open_rations)
	for state: Dictionary in lab.terrain.site.get("person_supply", {}).values():
		total += float(state.open_rations)
	for container: Dictionary in lab.terrain.site.ground_loot.values():
		stock.append(container.cargo)
		total += float(container.get("open_rations", 0.0))
	for cargo: Dictionary in stock:
		for food: String in Sustain.FOODS:
			total += int(cargo.get(food, 0))
	return total

func _work(lab: TerrainLab, seconds: float, commit: bool = true) -> void:
	# Isolated original action owner, with Site.at kept in lockstep. No original
	# combat contact is suppressed: this fixture explicitly issues only food work.
	var at := Runtime.now(lab.terrain) + seconds / 60.0
	lab._advance_fatigue(seconds)
	lab.terrain.site.minute = floori(at)
	lab.terrain.site.phase = at - floorf(at)
	if commit:
		lab.site_controller.settle_supply_deliveries()

func _run() -> void:
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	for owner: Node in [lab, lab.character, lab.npc, lab.site_controller, lab.army, lab.opposing_army]:
		owner.set_process(false)
	lab.site_controller._auto_save_blocked = true
	var data := _fixture()
	lab.bind_terrain(data)
	lab.site_controller.release_worker()
	lab.npc.faction_id = lab.character.faction_id
	assert(lab.character.place(Vector2i(17, 17), true) and lab.npc.place(Vector2i(15, 15), true))
	var first: TerrainArmy = lab.army
	var second: TerrainArmy = lab.opposing_army
	first.roster_size = 4
	second.roster_size = 4
	var a: Array[Vector2i] = [Vector2i(22, 22), Vector2i(23, 22), Vector2i(22, 23), Vector2i(23, 23)]
	var b: Array[Vector2i] = [Vector2i(24, 22), Vector2i(25, 22), Vector2i(24, 23), Vector2i(25, 23)]
	assert(first.deploy_at(data, lab.character, lab.npc, a) and first.enable_combat(false))
	assert(second.deploy_at(data, lab.character, lab.npc, b) and second.enable_combat(false))
	first.faction_id = lab.character.faction_id
	second.faction_id = first.faction_id
	first.settle_combat_command()
	second.settle_combat_command()
	data.site.army_next_team = maxi(first.team_id, second.team_id) + 1 # Direct fixture deployment, same allocator boundary as Lab.
	var controller: SiteController = lab.site_controller
	var first_id := first.combat_identity(0)
	var source_id := first.combat_identity(1)
	var second_id := second.combat_identity(0)
	data.site.controlled_person_id = first_id # Explicit test authority, not a succession claim.
	var first_row: Dictionary = first.combat_units[0]
	var first_cargo: Dictionary = first_row.cargo
	first_cargo.grain = 4
	var source: Dictionary = controller._enable_team_supply(first)
	var destination: Dictionary = controller._enable_team_supply(second)
	assert(not source.is_empty() and not destination.is_empty())
	# Explicit fixture food, then actual first meals. Later transfers must not
	# create new food or reset coverage; all operations stay within this meal.
	source.inventory.grain = 10
	destination.inventory.grain = 1
	assert(Sustain.resupply(source.sustain, controller._team_members(first), source.inventory).ok)
	assert(Sustain.resupply(destination.sustain, controller._team_members(second), destination.inventory).ok)
	var conserved := _food(lab)
	assert(controller.begin_team_food(first, 2, source_id).ok)
	assert(not controller.supply_save_guard().ok)
	_work(lab, 2.0)
	assert(first_cargo.grain == 4)
	var pending_before: Dictionary = source.delivery.duplicate(true)
	data.site.paused = true
	controller.advance_team_sustain(first, 50.0)
	assert(source.delivery == pending_before and first_cargo.grain == 4)
	data.site.paused = false
	_work(lab, 1.0, false)
	assert(source.delivery.pending and first_cargo.grain == 4)
	controller.settle_supply_deliveries()
	assert(first_cargo.grain == 2 and source.delivery.is_empty())
	_near(_food(lab), conserved, "Private original row donation")
	controller.settle_supply_deliveries()
	_near(_food(lab), conserved, "Repeated commit")
	assert(controller.begin_team_food(first, 1, source_id).ok)
	_work(lab, 3.0, false)
	first.apply_unit_contact(1, {"result": {"hp": 1.0, "stun": 0.0, "guard_break": false}, "shield": false})
	controller.settle_supply_deliveries()
	assert(source.delivery.is_empty() and first_cargo.grain == 2)
	assert(controller.begin_team_food(first, 1, source_id).ok)
	first_row.cargo = first_cargo.duplicate() # Equal contents are not the same owner reference.
	_work(lab, 0.01)
	assert(source.delivery.is_empty() and first_row.cargo.grain == 2)
	first_row.cargo = first_cargo
	assert(controller.begin_team_food(first, 1, source_id).ok)
	data.site.controlled_person_id = lab.character.person_id
	assert(controller.cancel_team_food().code == "NO_AUTHORITY" and not source.delivery.is_empty())
	data.site.controlled_person_id = first_id
	assert(controller.cancel_team_food().ok and first_cargo.grain == 2)
	assert(not controller.begin_team_food(first, 31, source_id).ok)
	# Dedicated role is an explicit original-row assignment, not work_task.kind.
	assert(not controller.order_team_logistics(first, [source_id], source_id, true).ok)
	assert(controller.order_team_logistics(first, [source_id], first_id, true).ok)
	_near(controller.team_food_capacity(first), 15.0)
	assert(controller._work_person_unavailable(source_id))
	assert(first.combat_units[1].get("work_task", {}).is_empty())
	assert(not controller.begin_team_food(first, 3, first_id, {"kind": "depot"}).ok)
	data.site.depot_cell = data.index(Vector2i(21, 22))
	var depot_before := int(data.site.inventory.fish)
	assert(controller.begin_team_food(first, 3, first_id, {"kind": "depot"}).ok)
	_work(lab, 3.0)
	assert(source.delivery.is_empty() and data.site.inventory.fish == depot_before - 3)
	_near(_food(lab), conserved, "Actual adjacent camp stock")
	assert(controller.order_team_logistics(first, [source_id], first_id, false).code == "STORAGE_FULL")
	assert(first.combat_units[1].logistics, "Do not remove capacity while silently retaining an overloaded stock")
	var team_source := {"kind": "team", "team_id": first.team_id, "representative_id": source_id}
	data.site.controlled_person_id = lab.character.person_id
	assert(not controller.begin_team_food(second, 4, second_id, team_source).ok)
	data.site.controlled_person_id = first_id
	assert(controller.begin_team_food(second, 4, second_id, team_source).ok)
	_work(lab, 3.5)
	assert(destination.delivery.is_empty())
	_near(_food(lab), conserved, "Two real adjacent representatives, original stocks")
	source.sustain.open_rations = 0.75
	destination.sustain.open_rations = 0.75 # Explicit two original opened-food fixtures.
	conserved = _food(lab)
	assert(not controller.begin_team_food(second, 0.25, second_id, team_source).ok)
	assert(controller.begin_team_food(second, 0.75, second_id, team_source).ok)
	_work(lab, 3.0)
	_near(float(source.sustain.open_rations), 0.0)
	_near(float(destination.sustain.open_rations), 1.5, "Do not invent grain from combined open food")
	_near(_food(lab), conserved)
	# NPC 80/50 pauses this SAME job without transferring or charging rest as work.
	first.combat_units[1].fatigue = 79.999
	assert(controller.begin_team_food(second, 1, second_id, team_source).ok)
	var stock_before: Dictionary = source.inventory.duplicate()
	_work(lab, 5.0)
	assert(not destination.delivery.is_empty() and first.combat_units[1].work_resting)
	assert(source.inventory == stock_before)
	var work_left := float(destination.delivery.left)
	_work(lab, 5430.0)
	assert(float(destination.delivery.left) == work_left and source.inventory == stock_before)
	assert(float(first.combat_units[1].fatigue) <= 50.0)
	_work(lab, 5.0)
	assert(destination.delivery.is_empty() and not first.combat_units[1].work_resting)
	_near(_food(lab), conserved)
	# A real foreign person's opened food uses the same ground container. It is
	# public at its physical cell, not routed to victor stock or rounded away.
	var personal := Sustain.create(Runtime.now(data) * 60.0)
	personal.open_rations = 0.375
	if not data.site.has("person_supply"):
		data.site.person_supply = {}
	data.site.person_supply[str(lab.npc.person_id)] = personal
	data.site.worker.cargo.grain = 1
	lab.npc.faction_id = first.faction_id + 1
	var left := Runtime.leave_ground_loot(data, lab.npc.item_state, data.site.worker.cargo, lab.npc.person_id,
		Vector2i(21, 22), "cargo", {"grain": 1}, [], int(lab.npc.item_state.version), personal, 0.375)
	assert(left.ok)
	var container: Dictionary = data.site.ground_loot[left.container_id]
	assert(not Runtime.clear_empty_ground_loot(data, left.container_id).ok)
	conserved = _food(lab)
	assert(controller.begin_team_food(first, 0.375, first_id, {"kind": "ground", "container_id": left.container_id}).ok)
	_work(lab, 3.0)
	_near(float(container.open_rations), 0.0)
	_near(_food(lab), conserved)
	assert(controller.begin_team_food(first, 1, first_id, {"kind": "ground", "container_id": left.container_id}).ok)
	_work(lab, 3.0)
	assert(not data.site.ground_loot.has(left.container_id))
	_near(_food(lab), conserved)
	# Rout fixture: actual later deaths reduce 3/6 capacity; shared food drops
	# once per newly excess amount, not once per body. Original life path fires.
	source.sustain.routed = true
	source.sustain.morale = 20.0
	first.apply_unit_contact(1, {"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false})
	controller.settle_supply_deliveries()
	_near(Sustain.rations(source.sustain, source.inventory), controller.team_food_capacity(first))
	var containers: int = data.site.ground_loot.size()
	controller.settle_supply_deliveries()
	assert(data.site.ground_loot.size() == containers)
	_near(_food(lab), conserved)
	source.sustain.routed = false
	source.sustain.morale = 100.0
	first.combat_order = TerrainArmy.CombatOrder.HOLD
	for index: int in [0, 2, 3]:
		first.apply_unit_contact(index, {"result": {"hp": 100.0, "stun": 0.0, "guard_break": false}, "shield": false})
	controller.settle_supply_deliveries()
	assert(Sustain.rations(source.sustain, source.inventory) > 0.0, "All original landing bodies pending; keep food, do not choose a centroid")
	controller.settle_person_deaths(10.0)
	controller.settle_supply_deliveries()
	assert(not source.sustain.routed, "Total loss drops its true shared stock even without a morale rout")
	_near(Sustain.rations(source.sustain, source.inventory), 0.0)
	_near(_food(lab), conserved, "Last real carrier death, all shared stock remains on map")
	containers = data.site.ground_loot.size()
	controller.settle_supply_deliveries()
	assert(data.site.ground_loot.size() == containers)
	assert(is_same(first.combat_units[0], first_row) and is_same(first_row.cargo, first_cargo))
	# Retreat with living carriers, then non-routed all-KO: no fabricated deaths.
	for index: int in [1, 2, 3]:
		second.apply_unit_contact(index, {"result": {"hp": 0.0, "stun": 110.0, "guard_break": false}, "shield": false})
	second.combat_order = TerrainArmy.CombatOrder.RETREAT
	assert(not destination.sustain.routed)
	controller.settle_supply_deliveries()
	_near(Sustain.rations(destination.sustain, destination.inventory), 3.0)
	second.combat_order = TerrainArmy.CombatOrder.HOLD
	second.apply_unit_contact(0, {"result": {"hp": 0.0, "stun": 110.0, "guard_break": false}, "shield": false})
	controller.settle_supply_deliveries()
	assert(not destination.sustain.routed)
	_near(Sustain.rations(destination.sustain, destination.inventory), 0.0)
	_near(_food(lab), conserved, "Retreat and all-KO transfer only the remaining actual food")
	# No ongoing job is serialized. Original rows/real ground opened pool remain.
	data.site.controlled_person_id = lab.character.person_id
	data.site.combat_left = 0.0 # Explicit isolated-test exit, not a combat save bypass claim.
	first.settle_combat_command()
	second.settle_combat_command()
	controller._capture_positions()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	assert(controller.supply_save_guard().ok)
	var saved := Store.save(data, OUTPUT + "/logistics.json")
	assert(saved.ok, str(saved))
	var loaded := Store.load_site(OUTPUT + "/logistics.json")
	assert(loaded.ok, str(loaded))
	assert(loaded.data.site.armies[0].units[1].logistics)
	assert(loaded.data.site.ground_loot == data.site.ground_loot)
	print("SITE_FOOD_DELIVERY_PASS: actual camp/team/person/ground stocks + opened pools, 30 cap, original contact-before-commit, cancellation/source ownership, dedicated 3/6 role, original 80/50, routed later/last carrier drops and full Store roundtrip; not GPU/FPS")
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
