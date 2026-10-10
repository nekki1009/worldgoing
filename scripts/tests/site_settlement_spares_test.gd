extends "res://scripts/tests/site_building_ui_test.gd"
## Named actual owner test. Run only in Root's reviewed S08 activated source
## cohort; disabled production source is a separate byte-equivalent negative.
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Technology = preload("res://scripts/terrain_lab/site_technology.gd")
const Catalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")

func _spares_fixture() -> Dictionary:
	var data = _building_fixture()
	var lab = _building_lab(data)
	var control = lab.controlled_person_id()
	assert(lab.character.place(Vector2i(9, 10), true)) # Real original camp adjacency, not diagonal.
	var placement = Runtime.building_cells(data, "settlement_center", Vector2i(18, 10), Vector2i(5, 5), {"layout_version": 1, "quarter": 0, "owner_faction": 1})
	var cells: Array[int] = []
	cells.assign(placement.cells)
	var founded = Settlement.found(lab, control, cells)
	assert(founded.ok, str(founded))
	_complete_key(data, str(founded.feature))
	data.site.settlement.version = 2
	data.site.settlement.technology = Technology.empty_scope_record(str(data.site.id))
	data.site.settlement.technology.known = ["S07", "S08"] # Legitimate saved-world precondition; no claim of research proof.
	var team: TerrainArmy = lab.army
	team.faction_id = 1
	team.roster_size = 2
	assert(team.deploy_at(data, lab.character, lab.npc, [Vector2i(12, 12), Vector2i(13, 12)]) and team.enable_combat(false))
	team.set_process(false)
	team.settle_combat_command()
	if not lab.combat_armies.has(team): lab.combat_armies.append(team)
	team.controlled_person_query = lab.controlled_person_id
	team.person_busy_query = lab.site_controller.person_actions.is_busy
	assert(team.join_player(lab.character).ok)
	# A legitimate starting office appointment delegates work to the actual
	# joined Actor. Runtime still obtains every manual consent from that person.
	var offices: Dictionary = team.team_offices()
	var appointment = team.apply_office_plan(team.combat_identity(team.formal_commander), int(offices.revision), [
		{"op": "add", "name": "施工主持", "office_class": "civil", "ref": "fixture_work"},
		{"op": "appoint", "position_id": "fixture_work", "person_id": control},
		{"op": "assign", "position_id": "fixture_work", "duty_id": "team.work"}])
	assert(appointment.ok, str(appointment))
	assert(team.duty_resolve_readonly("team.work").get("decider") == control)
	var built = Runtime.begin_siege_build(data, "ballista", Vector2i(20, 20), Vector2i.RIGHT, int(team.team_id), control)
	assert(built.ok, str(built))
	var vehicle: Dictionary = data.site.vehicles[str(built.vehicle)]
	var slot: Dictionary = Runtime.siege_work_slots(data, vehicle)[0]
	assert(Runtime.advance_siege_work(data, str(vehicle.id), "construct", 5400.0, data.cell_from_index(int(slot.cell)), 0, int(team.team_id)).ok)
	assert(Runtime.damage_siege_vehicle(data, str(vehicle.id), 40.0).ok)
	return {"data": data, "lab": lab, "team": team, "control": control, "vehicle": vehicle, "actions": lab.site_controller.person_actions}

func _run() -> void:
	var f = _spares_fixture()
	var data: TerrainData = f.data
	var vehicle: Dictionary = f.vehicle
	var before = var_to_bytes(data.site)
	if Catalog.get_node("S08").get("enabled") != true:
		assert(not Runtime.request_settlement_spare_repair(data, str(vehicle.id), int(f.control), true).ok)
		assert(var_to_bytes(data.site) == before, "Disabled S08 changed original state")
		assert(Runtime.request_siege_repair(data, str(vehicle.id), int(f.team.team_id)).ok, "Original basic repair remains available")
		print("S08_DISABLED_BOUNDARY_PASS; S08_NAMED_PRODUCTIVE_CASES_NOT_RUN_ACTIVATION_REQUIRED")
		f.lab.queue_free()
		quit(2)
		return
	var inventory: Dictionary = data.site.inventory
	var wood = int(inventory.wood)
	var iron = int(inventory.iron)
	var fiber = int(inventory.fiber)
	var kits = int(inventory.get("ballista_spares", 0))
	assert(f.actions.begin_ranged_craft(int(f.control), "ballista_spares").ok)
	# Existing PA/Runtime direct interval seam, without claiming shared clock/Native/GPU proof.
	f.actions.advance(120.0)
	assert(int(inventory.wood) == wood - 3 and int(inventory.iron) == iron - 1 and int(inventory.fiber) == fiber - 1)
	assert(int(inventory.ballista_spares) == kits + 1 and not f.actions.is_busy(int(f.control)))
	var npc = int(f.team.combat_identity(1))
	var row: Dictionary = f.team.combat_units[1]
	before = var_to_bytes([data.site, row])
	assert(Runtime.request_settlement_spare_repair(data, str(vehicle.id), npc, true).ok)
	assert(var_to_bytes([data.site, row]) == before, "Repair preview debited materials or installed work")
	assert(Runtime.request_settlement_spare_repair(data, str(vehicle.id), npc).ok)
	assert(int(inventory.ballista_spares) == kits and Runtime.valid_settlement_spare_repair_storage(data, vehicle))
	var task: Dictionary = row.work_task
	assert(task.action == "repair" and task.target == "vehicle:" + str(vehicle.id) and task.named == true)
	f.team.cells[1] = data.cell_from_index(int(task.work_cell))
	task.cell = int(task.work_cell)
	task.mode = "work"
	var hp = float(vehicle.hp)
	assert(Runtime.advance_siege_work(data, str(vehicle.id), "repair", 150.0, f.team.cells[1], int(task.work_slot), int(f.team.team_id), task, npc).ok)
	assert(is_equal_approx(float(vehicle.hp), hp + 10.0) and is_equal_approx(float(vehicle.repair.progress), 150.0))
	assert(Runtime.release_settlement_spare_repair(data, str(vehicle.id), int(f.control)).ok)
	assert(is_equal_approx(float(vehicle.hp), hp + 10.0) and int(inventory.ballista_spares) == kits)
	assert(Runtime.valid_settlement_spare_repair_storage(data, vehicle) and vehicle.technology_spare_repair.released)
	f.lab.site_controller._capture_positions()
	var saved = Store.save(data, "res://.godot-temp/site_settlement_spares_v1/repair.json")
	assert(saved.ok, str(saved))
	var loaded = Store.load_site("res://.godot-temp/site_settlement_spares_v1/repair.json")
	assert(loaded.ok, str(loaded))
	var restored: Dictionary = loaded.data.site.vehicles[str(vehicle.id)]
	assert(Runtime.valid_settlement_spare_repair_storage(loaded.data, restored) and restored.technology_spare_repair.released)
	assert(is_equal_approx(float(restored.hp), hp + 10.0) and is_equal_approx(float(restored.repair.progress), 150.0) and int(loaded.data.site.inventory.ballista_spares) == kits)
	var malformed: Dictionary = vehicle.duplicate(true)
	malformed.technology_spare_repair.initial_hp = NAN
	assert(not Runtime.valid_settlement_spare_repair_storage(data, malformed))
	# Released paid work continues the original basic repair, without extra kit payment.
	var slot: Dictionary = Runtime.siege_work_slots(data, vehicle)[int(task.work_slot)]
	assert(Runtime.advance_siege_work(data, str(vehicle.id), "repair", 150.0, data.cell_from_index(int(slot.cell)), int(slot.slot), int(f.team.team_id)).ok)
	assert(is_equal_approx(float(vehicle.hp), hp + 20.0) and vehicle.repair.is_empty() and not vehicle.has("technology_spare_repair"))
	assert(Runtime.damage_siege_vehicle(data, str(vehicle.id), 10000.0).ok)
	before = var_to_bytes(data.site)
	assert(not Runtime.request_settlement_spare_repair(data, str(vehicle.id), npc).ok and var_to_bytes(data.site) == before)
	f.lab.queue_free()
	print("S08_ACTIVATED_ORIGINAL_PRODUCT_REPAIR_PASS; direct GD owner intervals only, no Scope research/shared-clock/Native/GPU acceptance")
	quit(0)
