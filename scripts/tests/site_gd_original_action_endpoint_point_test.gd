extends "res://scripts/tests/site_building_ui_test.gd"
## Explicit warm initial structure/engine/weapon stock; no earned technology proof.
const ActionRules = preload("res://scripts/terrain_lab/site_combat_rules.gd")
const ActionFatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 180000
	_run.call_deferred()

func _run() -> void:
	create_timer(180.0).timeout.connect(func() -> void: quit(1))
	await _structure_point()
	await _vehicle_point()
	# Nekki 11/14 A: the siege takeover point deployed a GD trial army (retired grid simulation) and was removed.
	TerrainArmy.release_contact_source()
	print("GD_ORIGINAL_ACTION_ENDPOINTS_POINT_PASS")
	quit(0)

func _action_point(lab: TerrainLab) -> void:
	assert(Time.get_ticks_msec() < deadline)
	var step: Dictionary = lab._advance_original_shared_step(TerrainLab.ACTION_STEP)
	assert(step.ok and bool(step.get("completed", false)), str(step))
	assert(lab.site_controller.original_step_fault_guard().ok)

func _finish_action(lab: TerrainLab, identity: int, maximum: float) -> void:
	var steps := ceili(maximum / TerrainLab.ACTION_STEP)
	for index in range(steps):
		if not lab.site_controller.person_actions.is_busy(identity): return
		_action_point(lab)
		if index % 120 == 0: await process_frame
	assert(not lab.site_controller.person_actions.is_busy(identity), "Original action failed to settle in its true shared clock")

func _close_action_lab(lab: TerrainLab) -> void:
	lab.queue_free()
	await process_frame

func _arm_actor(lab: TerrainLab) -> void:
	var actor: TerrainTestCharacter = lab.character
	if actor.item_state.get("equipped", {}).has("weapon"):
		# The controlled person is now seeded with gear: the seeded weapon goes to the bag so the axe fixture can take the slot.
		actor.item_state.equipped.erase("weapon")
		actor.item_state.version = int(actor.item_state.version) + 1
	var made := Runtime.create_equipment(lab.terrain, actor.item_state, "action_endpoint_axe", {"slot": "weapon", "asset": "axe_01", "tint": [1.0, 1.0, 1.0, 1.0]}, actor.person_id, "weapon")
	assert(made.ok, str(made))
	lab.site_controller.equipment_changed(actor.person_id)

func _assert_not_work(lab: TerrainLab, identity: int) -> void:
	for request: Dictionary in lab.site_controller.person_actions.work_requests(60.0):
		assert(str(request.key) != str(identity), "Original ACTION job was incorrectly projected as productive WORK")

func _structure_point() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	# A worker may build only its own faction's feature: build the wall as faction 1, then make it the foreign target.
	var key := _formal_feature(data, "stone_wall", Vector2i(20, 20), Vector2i.ONE)
	data.site.features[key].owner_faction = 2
	var part := "c:" + str(data.index(Vector2i(20, 20)))
	assert(lab.character.place(Vector2i(19, 20), true))
	_arm_actor(lab)
	var actions: SitePersonActions = lab.site_controller.person_actions
	var person := actions._person(lab.character.person_id)
	var hp := float(Runtime.feature_geometry(data, data.site.features[key]).parts[part].hp)
	var fatigue := ActionFatigue.read(person.body)
	var charged := ActionFatigue.effort_rate(person.body, ActionRules.EXCHANGE_FATIGUE)
	var begun := actions.begin_structure_attack(lab.character.person_id, key, part)
	assert(begun.ok, str(begun))
	assert(is_equal_approx(ActionFatigue.read(person.body), fatigue + charged))
	_assert_not_work(lab, lab.character.person_id)
	var before_action := lab.fire_action_cursor
	await _finish_action(lab, lab.character.person_id, 2.0)
	var after_hp := float(Runtime.feature_geometry(data, data.site.features[key]).parts[part].hp)
	assert(is_equal_approx(after_hp, hp - ActionRules.structure_damage("axe_01", "stone")))
	assert(absf(lab.fire_action_cursor - before_action - ActionRules.EXCHANGE_ROUND_SECONDS) <= TerrainLab.ACTION_STEP + 0.000001)
	for index in range(10): _action_point(lab)
	assert(float(Runtime.feature_geometry(data, data.site.features[key]).parts[part].hp) == after_hp)
	await _close_action_lab(lab)

func _initial_engine(lab: TerrainLab) -> Dictionary:
	var started := Runtime.begin_siege_build(lab.terrain, "ballista", Vector2i(25, 20), Vector2i.RIGHT, 1, 1)
	assert(started.ok, str(started))
	var vehicle: Dictionary = lab.terrain.site.vehicles[str(started.vehicle)]
	var slot: Dictionary = Runtime.siege_work_slots(lab.terrain, vehicle)[0]
	var completed := Runtime.advance_siege_work(lab.terrain, str(started.vehicle), "construct", float(Runtime.SIEGE_DEFINITIONS.ballista.work_seconds), lab.terrain.cell_from_index(int(slot.cell)), 0, 1)
	assert(completed.ok and vehicle.build.is_empty(), str(completed))
	vehicle.team_id = 0 # Explicit initial neutral, finished, empty original engine.
	return vehicle

func _vehicle_point() -> void:
	var lab := _building_lab(_building_fixture())
	var vehicle := _initial_engine(lab)
	assert(lab.character.place(Vector2i(24, 20), true))
	_arm_actor(lab)
	var actions: SitePersonActions = lab.site_controller.person_actions
	var hp := float(vehicle.hp)
	var holder: Dictionary = vehicle.holder
	var version := int(holder.version)
	assert(actions.begin_vehicle_attack(lab.character.person_id, str(vehicle.id)).ok)
	_assert_not_work(lab, lab.character.person_id)
	await _finish_action(lab, lab.character.person_id, 2.0)
	assert(is_equal_approx(float(vehicle.hp), hp - ActionRules.structure_damage("axe_01", "wood")))
	assert(is_same(vehicle.holder, holder) and int(holder.version) == version)
	# Wait only through the original action clock until the next genuine attack is ready.
	for index in range(240):
		if lab.character.exchange_ready(): break
		_action_point(lab)
	assert(lab.character.exchange_ready())
	assert(actions.begin_vehicle_attack(lab.character.person_id, str(vehicle.id)).ok)
	_action_point(lab)
	var accepted_hp := float(vehicle.hp)
	assert(actions.cancel(lab.character.person_id).ok)
	for index in range(150): _action_point(lab)
	assert(float(vehicle.hp) == accepted_hp and int(holder.version) == version)
	await _close_action_lab(lab)
