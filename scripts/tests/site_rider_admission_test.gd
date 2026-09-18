extends SceneTree
const Rider = preload("res://scripts/terrain_lab/site_vehicle_rider_atlas.gd")
const Recipe = preload("res://scripts/terrain_lab/site_wagon_rider_recipe.gd")
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 35000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Rider admission deadline")
		quit(1)
	return false

func _snapshot(lab: TerrainLab) -> Dictionary:
	var teams := []
	for team: TerrainArmy in lab.combat_armies:
		teams.append({"people": team.combat_units.duplicate(true), "cells": team.cells.duplicate(),
			"destinations": team.moving_to.duplicate(), "team_id": team.team_id,
			"occupied": team._cell_owners.duplicate(), "reserved": team._reserved_cells.duplicate()})
	return {"site": lab.terrain.site.duplicate(true), "teams": teams}

func _run() -> void:
	assert(DisplayServer.get_name() == "headless")
	var lab := TerrainLab.new()
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	var ui: SiteController = lab.site_controller
	ui.set_process(false)
	ui._auto_save_blocked = true
	for actor: TerrainTestCharacter in lab.combat_actors: actor.set_process(false)
	for army: TerrainArmy in lab.combat_armies: army.set_process(false)
	var deployed := lab.start_melee_trial({"friendly_role": "logistics", "friendly_count": 3,
		"friendly_wagon_count": 1, "friendly_female_percent": 0, "enemy_role": "work", "enemy_count": 1})
	assert(deployed.ok, str(deployed))
	var team := lab.army
	var identity := team.combat_identity(0)
	var vehicle: Dictionary = ui.vehicles.records().values()[0]
	var row: Dictionary = team.combat_units[0]
	assert(int(vehicle.operator_id) == identity and Rider.supports(team.equipment_appearance(0)))
	var appearance := team.equipment_appearance(0)
	assert(not Recipe.matches(appearance) and appearance.parts.weapon == "longsword_01")
	var original_frame := Rider.frame(appearance, "down", false, 0.0)
	var fixed_frame := Rider.frame(Recipe.appearance(0), "down", false, 0.0)
	assert(not original_frame.is_empty() and original_frame.texture == fixed_frame.texture)
	var valid_other := appearance.duplicate(true)
	valid_other.parts.armor = "armor_mingguang_01"
	valid_other.parts.helmet = "helmet_cloth_chinese_01"
	valid_other.equipment_dyes = {"armor": "ff0000ff"}
	var valid_before := valid_other.duplicate(true)
	assert(HumanCharacter3DEditor.valid_appearance(valid_other) and Rider.supports(valid_other))
	assert(Rider.frame(valid_other, "down", false, 0.0).texture == fixed_frame.texture and valid_other == valid_before)
	assert(not Rider.supports({}) and Rider.frame({}, "down", false, 0.0).is_empty())
	var invalid := appearance.duplicate(true)
	invalid.parts.armor = "nonexistent_armor"
	assert(not Rider.supports(invalid) and Rider.frame(invalid, "down", false, 0.0).is_empty())
	# The mounted adapter is not authority to bypass the original ordinary foot
	# recipe guard. This real extra bag item must remain unequipped on rejection.
	var ordinary: Dictionary = team.combat_units[1]
	var cloth_hat := SiteRuntime.create_equipment(lab.terrain, ordinary.item_state, "helmet:helmet_cloth_chinese_01",
		{"slot": "helmet", "asset": "helmet_cloth_chinese_01", "tint": [1.0, 1.0, 1.0, 1.0]}, team.combat_identity(1))
	assert(cloth_hat.ok)
	var proposal: Dictionary = ordinary.item_state.equipped.duplicate()
	proposal.helmet = cloth_hat.item_id
	var before := _snapshot(lab)
	assert(ui.equipment_apply_guard(team.combat_identity(1), proposal).code == "UNSUPPORTED")
	assert(_snapshot(lab) == before, "Rider support cannot bypass unsupported foot gear or mutate any inventory")
	# A real accepted equipment transaction can change the captain's loadout;
	# boarding itself must leave that loadout and its real bag items untouched.
	lab.terrain.site.controlled_person_id = identity
	var sword := str(row.item_state.equipped.weapon)
	var items_before: Dictionary = lab.terrain.site.item_records.duplicate(true)
	var version := int(row.item_state.version)
	var prepared := ui.equipment_orders.prepare(identity, {"mode": "personal", "slot": "weapon", "item_id": ""})
	assert(prepared.ok, str(prepared))
	assert(ui.equipment_orders.commit(prepared.order).ok)
	assert(not row.item_state.equipped.has("weapon") and row.item_state.item_ids.has(sword))
	assert(int(row.item_state.version) == version + 1 and lab.terrain.site.item_records == items_before)
	assert(team.equipment_appearance(0).parts.weapon == "none" and Rider.supports(team.equipment_appearance(0)))
	assert(Rider.frame(team.equipment_appearance(0), "down", false, 0.0).texture == fixed_frame.texture)
	assert(ui.vehicles.unassign_operator(str(vehicle.id), identity, true).ok)
	for tick in range(30): team.prepare_combat(1.0 / 30.0)
	assert(team.moving_to[0] == TerrainArmy.INVALID_CELL and int(vehicle.operator_id) == 0)
	var held_after_change: Dictionary = row.item_state.duplicate(true)
	assert(ui.vehicles.assign_operator(str(vehicle.id), identity, identity, true).ok)
	for tick in range(30): team.prepare_combat(1.0 / 30.0)
	assert(int(vehicle.operator_id) == identity and row.item_state == held_after_change and lab.terrain.site.item_records == items_before)
	assert(ui.vehicles.unassign_operator(str(vehicle.id), identity, true).ok)
	for tick in range(30): team.prepare_combat(1.0 / 30.0)
	# Adversarial corrupt-holder fixture: the cached published visual is valid,
	# but equipped references a nonexistent item. No rendering fallback may make
	# that invalid physical record eligible to board or spawn another vehicle.
	var real_armor := str(row.item_state.equipped.armor)
	row.item_state.equipped.armor = "nonexistent_item"
	assert(Rider.supports(row.appearance) and Rider.supports(team.equipment_appearance(0)))
	assert(SiteRuntime.equipment_appearance(lab.terrain, row.item_state, row.appearance).is_empty())
	var site_alias := lab.terrain.site
	var holder_alias: Dictionary = row.item_state
	var cargo_alias: Dictionary = vehicle.cargo
	before = _snapshot(lab)
	var assigned: Dictionary = ui.vehicles.assign_operator(str(vehicle.id), identity, identity, true)
	assert(assigned.code == "MISSING_ASSET", "Corrupt actual holder admitted: " + str(assigned))
	assert(_snapshot(lab) == before, "Boarding must consult true holder and leave the whole original state unchanged on rejection")
	var direction := Vector2i.RIGHT
	var anchor: Vector2i = ui.vehicles.anchor_from_operator("wagon", team.cells[0], direction)
	var plan := [{"kind": "wagon", "team_id": team.team_id, "cell": lab.terrain.index(anchor),
		"facing": [direction.x, direction.y], "operator_index": 0}]
	assert(ui.vehicles.deploy_plan(team, plan).code == "MISSING_ASSET")
	assert(_snapshot(lab) == before and is_same(site_alias, lab.terrain.site) and is_same(holder_alias, row.item_state) and is_same(cargo_alias, vehicle.cargo))
	row.item_state.equipped.armor = real_armor
	assert(row.item_state == held_after_change and lab.terrain.site.item_records == items_before)
	print("SITE_RIDER_ADMISSION_PASS: real team gear retained; valid different kit maps to fixed cloth without mutation; original unsupported foot gear remains rejected; real equipment transaction preserves bag items; native dismount/reboard of valid changed kit; corrupt holder rejected despite valid cached visual; no inventory/version/allocator/alias changes from boarding rejection")
	lab.queue_free()
	await process_frame
	quit(0)
