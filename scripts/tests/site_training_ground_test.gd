extends "res://scripts/tests/site_building_ui_test.gd"

const Ground = preload("res://scripts/terrain_lab/site_training_ground.gd")
const CrowdHost = preload("res://scripts/terrain_lab/crowd_site.gd")

func _near(actual: float, expected: float, label: String) -> void:
	assert(absf(actual - expected) < 0.00002, "%s: %.12f != %.12f" % [label, actual, expected])

func _run() -> void:
	deadline = Time.get_ticks_msec() + 180000
	var data := _building_fixture()
	# Only height edits are persistent terrain deltas. Restore the seed's other
	# navigation inputs before applying that same delta used by Store.load_site.
	var base := TerrainGenerator.generate(data.preset, data.seed_value, data.parameters)
	data.flags = base.flags.duplicate()
	data.ramp_edges = base.ramp_edges.duplicate()
	for y: int in range(8, 55):
		for x: int in range(8, 55):
			var cell := Vector2i(x, y)
			data.site.terrain_changes[str(data.index(cell))] = int(data.height_levels[data.index(cell)])
	Runtime.rebuild_terrain_edges(data)
	var lab := _building_lab(data)
	lab.fixed_action_steps_enabled = false # Deterministic fixture consumes all requested steps, independent of GPU preparation time.
	var controller: SiteController = lab.site_controller
	var team: TerrainArmy = lab.army
	team.roster_size = 3
	team.faction_id = 1
	assert(team.deploy_at(data, lab.character, lab.npc, [Vector2i(23, 26), Vector2i(24, 26), Vector2i(25, 26)]))
	assert(team.enable_combat(false))
	team.set_process(false)
	team.settle_combat_command()
	data.site.army_next_team = team.team_id + 1
	var captain := team.combat_identity(team.current_commander)
	var soldier := team.combat_identity(1)
	assert(not controller.order_team_training(team, team.current_commander, true).ok, "An order outside a physical school must fail")
	var field := _formal_feature(data, "training_ground", Vector2i(20, 20), Vector2i(10, 10))
	var feature: Dictionary = data.site.features[field]
	feature.stage = "building"
	assert(not Ground.inspect(controller, team.team_id).ok)
	feature.stage = "complete"
	feature.owner_faction = 2
	assert(not Ground.inspect(controller, team.team_id).ok)
	feature.owner_faction = 1
	assert(not controller.order_team_training(team, 1, true).ok, "An ordinary soldier cannot order training")
	var entry: Dictionary = controller._enable_team_supply(team)
	entry.inventory.grain = 30
	var owner: Variant = team
	var native := "--crowd-test" in OS.get_cmdline_user_args()
	if native:
		assert(DisplayServer.get_name() != "headless")
		var row: Dictionary = team.combat_units[0]
		assert(await CrowdHost.prepare_captivity_recipe(lab, Runtime.equipment_appearance(data, row.item_state, row.appearance)))
		lab.crowd_site = CrowdHost.new()
		lab.add_child(lab.crowd_site)
		lab.crowd_site.setup(lab)
		var imported: Dictionary = lab.deploy_trial_armies([{"faction": 1, "count": 1, "female_percent": 0,
			"attack": false, "ai_enabled": false, "spawn": Vector2i(40, 40)}])
		assert(imported.ok, str(imported))
		owner = lab.crowd_site.person_owner(captain)
		entry = controller._supply_entry(owner)
		# Imported HOLD formations first settle their original physical slots.
		for _step: int in range(90): lab._advance_action_time(TerrainLab.EXCHANGE_ACTION_STEP)
	var checked := Ground.inspect(controller, int(owner.team_id))
	print("TRAINING_GROUND_START ", JSON.stringify({"ok": checked.ok, "message": checked.message, "native": checked.get("native", {})}))
	assert(checked.ok and checked.eligible_ids.size() == 3, str(checked))
	assert(controller.order_team_training(owner, owner.index_for_identity(captain), true).ok)
	assert(entry.version == 2 and entry.training_feature_id == field and entry.training_requester == captain)
	var before := _values(lab, owner)
	var meal_clock := float(entry.sustain.at)
	lab._process(0.1)
	var after := _values(lab, owner)
	print("TRAINING_GROUND_STEP ", JSON.stringify({"before": before, "after": after, "ordered": entry.training_order, "field": Ground.inspect(controller, int(owner.team_id)).get("message", ""), "clock": entry.sustain.at, "before_clock": meal_clock}))
	assert(float(after.training) > float(before.training), str({"before": before, "after": after}))
	_near(float(after.fatigue) - float(before.fatigue), PersonFatigue.WORK_RATE * 6.0, "one common-clock fatigue charge")
	_near(float(entry.sustain.at) - meal_clock, 6.0, "one common supply clock")
	before = _values(lab, owner)
	data.site.paused = true
	lab._process(1.0)
	assert(_values(lab, owner) == before)
	assert(not controller.order_team_training(owner, owner.index_for_identity(captain), true).ok)
	data.site.paused = false
	lab.simulation_speed = 2.0
	lab._process(0.1)
	after = _values(lab, owner)
	_near(float(after.fatigue) - float(before.fatigue), PersonFatigue.WORK_RATE * 12.0, "speed is applied once")
	lab.simulation_speed = 1.0
	assert(controller._capture_for_save().ok)
	var saved := Store.save(data, "res://.godot-temp/site_resources_contract/training_ground_active.json")
	assert(saved.ok, str(saved))
	var loaded := Store.load_site("res://.godot-temp/site_resources_contract/training_ground_active.json")
	assert(loaded.ok, str(loaded))
	var persisted: Dictionary = loaded.data.site.team_supply[str(owner.team_id)]
	assert(persisted.training_order and persisted.training_feature_id == field and persisted.training_requester == captain)
	before = _values(lab, owner)
	data.site.combat_left = 1.0
	lab._process(0.1)
	_near(float(_values(lab, owner).training), float(before.training), "combat pauses training")
	assert(entry.training_order, "Threat pauses the original order rather than erasing it")
	data.site.combat_left = 0.0
	_set_fatigue(lab, owner, 80.0, 0.0)
	before = _values(lab, owner)
	lab._process(0.1)
	_near(float(_values(lab, owner).training), float(before.training), "80 fatigue pauses productive training")
	_near(float(_values(lab, owner).fatigue), 80.0, "one original rest delay at the fatigue boundary")
	_set_fatigue(lab, owner, 50.0, PersonFatigue.REST_DELAY)
	lab._process(0.1)
	assert(float(_values(lab, owner).training) > float(before.training), "50 fatigue resumes the same original order")
	before = _values(lab, owner)
	entry.inventory.clear()
	for cohort: Dictionary in entry.sustain.cohorts:
		cohort.coverage = 0.0
		cohort.meal_until = float(entry.sustain.at) + 60.0
	lab._process(0.1)
	_near(float(_values(lab, owner).training), float(before.training), "missing food pauses productive training")
	assert(entry.training_order)
	if native:
		assert(lab.crowd_site.issue_order(int(owner.team_id), TerrainArmy.CombatOrder.MOVE, Vector2i(26, 28)).ok)
	else:
		assert(team.issue_combat_order(team.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(26, 28)).ok)
	lab._process(0.05)
	assert(not entry.training_order and entry.training_requester == -1 and entry.training_feature_id.is_empty(), "Moving cancels the facility-bound order")
	if not native:
		# A stationary original trainee outside the field must also cancel.
		team.combat_order = TerrainArmy.CombatOrder.HOLD
		for index: int in team.cells.size():
			team.moving_to[index] = TerrainArmy.INVALID_CELL
			team.combat_slots[index] = team.cells[index]
		team.cells[team.index_for_identity(soldier)] = Vector2i(35, 35)
		assert(not Ground.inspect(controller, team.team_id).ok)
	lab.free()
	TerrainArmy.release_contact_source()
	print("SITE_TRAINING_GROUND_PASS: physical completed friendly school, original commander and actual armed trainees, common food/time/pause/speed/fatigue, active save/load, combat pause and movement cancellation; native=", native)
	quit(0)

func _values(lab: TerrainLab, owner: Variant) -> Dictionary:
	if owner is TerrainArmy:
		return {"training": owner.training, "fatigue": PersonFatigue.read(owner.combat_units[1])}
	var state: Dictionary = lab.crowd_site.formation_state(owner.formation_index)
	return {"training": state.training, "fatigue": state.fatigue}

func _set_fatigue(lab: TerrainLab, owner: Variant, value: float, rested: float) -> void:
	if owner is TerrainArmy:
		owner.team_fatigue.fatigue = value
		owner.team_fatigue.fatigue_rest = rested
	else:
		assert(lab.crowd_site.set_formation_fields(owner.formation_index, {"fatigue": value, "fatigue_rest": rested}))
