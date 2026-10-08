extends "res://scripts/tests/site_building_runtime_contract_test.gd"

class LadderCrewFixture extends CrewFixture:
	var site_controller: Variant
	func reserves_cell(cell: Vector2i) -> bool:
		return army.reserves_terrain_cell(cell)
	func _siege_people_occupied(cell: Vector2i) -> bool:
		return army.reserves_terrain_cell(cell)
	func close() -> void:
		site_controller = null
		super.close()

func _run() -> void:
	create_timer(70.0).timeout.connect(func() -> void: quit(1))
	_check_ladder_four_directions()
	_check_ladder_original_people()
	_check_tower_four_directions()
	_check_tower_invalid_support_and_exit()
	_check_tower_candidate_validation()
	TerrainArmy.release_contact_source()
	assert(completed == 5, "A landing contract stopped before completion")
	print("SITE_SIEGE_LANDING_CONTRACT_PASS: original two-part 80 HP ladders, 30 person-minute build plus two original workers with 12/8 action-second deploy/retract, four-direction derived tower surfaces, physical/person-purpose separation, stable crewless roofs, support invalidation, original-cell multi-step wreck exit, detached candidate projection and strict pose input; no GPU/native/performance/full Store integration claim")
	quit(0)

func _empty(_cell: Vector2i) -> bool:
	return false

func _ladder_fixture(quarter: int = 0) -> Dictionary:
	var data := _fixture()
	var anchor := Vector2i(24, 24)
	var support := SiteRuntime._layout_cell(Vector2i(0, -1), Vector2i(1, 2), quarter, anchor)
	var wall := _build(data, "palisade", support)
	var key := _build(data, "siege_ladder", anchor, Vector2i.ONE, {"quarter": quarter})
	return {"data": data, "key": key, "wall": wall, "feature": data.site.features[key]}

func _ladder_workers(data: TerrainData, feature: Dictionary) -> Array[Dictionary]:
	var slots := SiteRuntime.siege_ladder_work_slots(data, feature)
	var result: Array[Dictionary] = []
	for index: int in range(slots.size()): result.append({"person_id": 11 + index, "cell": data.cell_from_index(int(slots[index].cell))})
	return result

func _check_ladder_four_directions() -> void:
	for quarter: int in range(4):
		var fixture := _ladder_fixture(quarter)
		var data: TerrainData = fixture.data
		var feature: Dictionary = fixture.feature
		assert(float(feature.work) == 30.0 and feature.cost == {"wood": 12, "fiber": 6})
		assert(str(feature.stage) == "complete" and str(feature.ladder.phase) == "folded")
		var geometry := SiteRuntime.feature_geometry(data, feature)
		assert(geometry.heights.is_empty() and geometry.parts.size() == 2)
		for part: Dictionary in geometry.parts.values(): assert(float(part.hp) == 80.0 and float(part.max_hp) == 80.0)
		var before := JSON.stringify(data.site)
		assert(SiteRuntime.request_siege_ladder_action(data, fixture.key, "deploy", [11, 12], 1, _empty, true).ok)
		assert(JSON.stringify(data.site) == before)
		assert(not SiteRuntime.request_siege_ladder_action(data, fixture.key, "deploy", [11, 11], 1, _empty).ok)
		assert(JSON.stringify(data.site) == before)
		assert(SiteRuntime.request_siege_ladder_action(data, fixture.key, "deploy", [11, 12], 1, _empty).ok)
		var workers := _ladder_workers(data, feature)
		assert(not SiteRuntime.advance_siege_ladder_action(data, fixture.key, 12.0, [workers[0]], _empty).ok)
		assert(float(feature.ladder.progress) == 0.0)
		assert(SiteRuntime.advance_siege_ladder_action(data, fixture.key, 11.0, workers, _empty).ok)
		assert(SiteRuntime.feature_geometry(data, feature).heights.is_empty())
		assert(SiteRuntime.advance_siege_ladder_action(data, fixture.key, 1.0, workers, _empty).complete)
		geometry = SiteRuntime.feature_geometry(data, feature)
		assert(data.can_step(geometry.external_lower.cell, geometry.stair_lower.cell))
		assert(data.can_step(geometry.stair_lower.cell, geometry.stair_upper.cell))
		assert(data.can_step(geometry.stair_upper.cell, geometry.external_upper.cell))
		var blocked: Vector2i = geometry.stair_upper.cell
		before = JSON.stringify(data.site)
		assert(not SiteRuntime.request_siege_ladder_action(data, fixture.key, "retract", [11, 12], 1, func(cell: Vector2i) -> bool: return cell == blocked).ok)
		assert(JSON.stringify(data.site) == before, "Occupied ladder retract partially mutated state")
		var lower_id := "c:" + str(data.index(geometry.stair_lower.cell))
		var upper_id := "c:" + str(data.index(geometry.stair_upper.cell))
		assert(SiteRuntime.damage_structure_part(data, fixture.key, lower_id, 80.0).ok)
		assert(float(feature.parts[lower_id].hp) == 0.0 and float(feature.parts[upper_id].hp) == 80.0)
		assert(not data.can_step(geometry.stair_lower.cell, geometry.stair_upper.cell))
		assert(SiteRuntime.validate_feature_layout(data, feature).ok)
		var corrupt := feature.duplicate(true)
		corrupt.parts[upper_id].hp = 81.0
		assert(not SiteRuntime.validate_feature_layout(data, corrupt).ok)
	# Ordinary original stairs keep their original 100 HP per segment.
	var data := _fixture()
	_build(data, "palisade", Vector2i(20, 19))
	var ordinary := _build(data, "wall_stairs", Vector2i(20, 20))
	for part: Dictionary in SiteRuntime.feature_geometry(data, data.site.features[ordinary]).parts.values(): assert(float(part.max_hp) == 100.0)
	completed += 1

func _check_ladder_original_people() -> void:
	var fixture := _ladder_fixture()
	var data: TerrainData = fixture.data
	var feature: Dictionary = fixture.feature
	var slots := SiteRuntime.siege_ladder_work_slots(data, feature)
	var people := LadderCrewFixture.new()
	var a := data.cell_from_index(int(slots[0].cell))
	var b := data.cell_from_index(int(slots[1].cell))
	people.setup(root, data, [a + Vector2i(-2, 1), a, b])
	people.site_controller = people
	var identities: Array[int] = [people.army.combat_identity(1), people.army.combat_identity(2)]
	var requester := people.army.combat_identity(0)
	var original_cells := people.army.cells.duplicate()
	var original_ids := [people.army.combat_identity(0), identities[0], identities[1]]
	assert(people.crew.request_ladder_action(fixture.key, identities, requester, "deploy").ok)
	assert(SiteStore.siege_save_guard(data).code == "BUSY")
	assert(SiteWorkTeam.valid_task(data, data.site, people.army.combat_units[1].work_task))
	assert(SiteWorkTeam.valid_task(data, data.site, people.army.combat_units[2].work_task))
	people.crew.advance(600.0)
	assert(float(feature.ladder.progress) == 0.0, "Game seconds incorrectly advanced a ladder action")
	people.crew.advance_ladder_actions(11.0, 660.0)
	assert(float(feature.ladder.progress) == 11.0 and str(feature.ladder.phase) == "folded")
	people.crew.cancel(identities[0])
	assert(str(feature.ladder.pending).is_empty() and float(feature.ladder.progress) == 0.0)
	assert(people.army.combat_units[1].work_task.is_empty() and people.army.combat_units[2].work_task.is_empty())
	assert(people.crew.request_ladder_action(fixture.key, identities, requester, "deploy").ok)
	people.crew.advance(0.01)
	people.crew.advance_ladder_actions(11.0, 0.0)
	assert(str(feature.ladder.phase) == "folded")
	people.crew.advance_ladder_actions(1.0, 0.0)
	assert(str(feature.ladder.phase) == "deployed")
	assert(people.army.combat_units[1].work_task.is_empty() and people.army.combat_units[2].work_task.is_empty())
	assert(people.crew.request_ladder_action(fixture.key, identities, requester, "retract").ok)
	people.crew.advance(0.01)
	people.crew.advance_ladder_actions(7.0, 0.0)
	assert(str(feature.ladder.phase) == "deployed")
	people.crew.advance_ladder_actions(1.0, 0.0)
	assert(str(feature.ladder.phase) == "folded" and people.army.cells == original_cells)
	assert([people.army.combat_identity(0), people.army.combat_identity(1), people.army.combat_identity(2)] == original_ids)
	assert(SiteStore.siege_save_guard(data).ok)
	people.close()
	completed += 1

func _tower_fixture(facing: Vector2i = Vector2i.RIGHT) -> Dictionary:
	var data := _fixture()
	var built := SiteRuntime.begin_siege_build(data, "siege_tower", Vector2i(24, 24), facing, 1, 1)
	assert(built.ok, str(built))
	var key := str(built.vehicle)
	var vehicle: Dictionary = data.site.vehicles[key]
	var station: Dictionary = SiteRuntime.siege_work_slots(data, vehicle)[0]
	assert(SiteRuntime.advance_siege_work(data, key, "construct", float(SiteRuntime.SIEGE_DEFINITIONS.siege_tower.work_seconds), data.cell_from_index(int(station.cell)), 0, 1).ok)
	vehicle.deployed_pose = SiteRuntime.siege_tower_pose(data, vehicle)
	var support := SiteRuntime._siege_tower_cell(data, vehicle, 5, 0)
	var extent := Vector2i(1, 3) if facing.x != 0 else Vector2i(3, 1)
	var end := SiteRuntime._siege_tower_cell(data, vehicle, 5, 2)
	var wall := _build(data, "palisade", Vector2i(mini(support.x, end.x), mini(support.y, end.y)), extent)
	vehicle.phase = "deployed"
	SiteEnvironment.rebuild_indexes(data)
	return {"data": data, "key": key, "vehicle": vehicle, "wall": wall}

func _check_tower_four_directions() -> void:
	for facing: Vector2i in TerrainData.DIRECTIONS:
		var fixture := _tower_fixture(facing)
		var data: TerrainData = fixture.data
		var vehicle: Dictionary = fixture.vehicle
		var geometry := SiteRuntime.siege_tower_geometry(data, vehicle)
		assert(geometry.active and geometry.top.size() == 12 and geometry.entry.size() == 2 and geometry.bridge.size() == 3 and geometry.physical.size() == 17)
		for forward: int in range(-3, 5):
			var from := SiteRuntime._siege_tower_cell(data, vehicle, forward, 1)
			var to := SiteRuntime._siege_tower_cell(data, vehicle, forward + 1, 1)
			assert(data.can_step(from, to), "Missing real tower step %s -> %s" % [from, to])
			assert(SiteRuntime.siege_person_step_allowed(data, vehicle, from, from, to, to))
		var roof := SiteRuntime._siege_tower_cell(data, vehicle, 1, 1)
		assert(data.effective_height(roof) == 2 and int(data.height_levels[data.index(roof)]) == 0)
		assert(SiteRuntime._siege_vehicle_claims(data, roof))
		assert(SiteRuntime._siege_vehicle_claims(data, geometry.bridge[0]))
		assert(not SiteRuntime.siege_tower_surface_guard(data, vehicle, func(cell: Vector2i) -> bool: return cell == geometry.bridge[0]).ok)
		assert(SiteRuntime.siege_tower_surface_guard(data, vehicle, _empty).ok)
		vehicle.crew_slots = {}
		SiteEnvironment.rebuild_indexes(data)
		assert(str(vehicle.phase) == "deployed" and data.effective_height(roof) == 2)
		assert(SiteRuntime.siege_tower_saved_person_allowed(data, vehicle, {"cell": [roof.x, roof.y], "destination": [-1, -1]}, roof))
		var old_pose: Dictionary = vehicle.deployed_pose.duplicate(true)
		for phase: String in ["building", "idle", "ready", "moving", "turning", "deploying", "disabled"]:
			vehicle.phase = phase
			vehicle.deployed_pose = {}
			SiteEnvironment.rebuild_indexes(data)
			assert(data.effective_height(roof) == 0 and SiteRuntime.siege_tower_physical_cells(data, vehicle).size() == 12)
			assert(not SiteRuntime.siege_person_step_allowed(data, vehicle, roof - facing, roof - facing, roof, roof))
		vehicle.phase = "deployed"
		vehicle.deployed_pose = old_pose
	completed += 1

func _check_tower_invalid_support_and_exit() -> void:
	var fixture := _tower_fixture()
	var data: TerrainData = fixture.data
	var vehicle: Dictionary = fixture.vehicle
	var origin := SiteRuntime._siege_tower_cell(data, vehicle, 1, 1)
	var first := origin + Vector2i.UP
	var goal := origin + Vector2i.UP * 2
	var support := SiteRuntime._siege_tower_cell(data, vehicle, 5, 1)
	var hp := float(vehicle.hp)
	assert(SiteRuntime.damage_structure_part(data, fixture.wall, "c:" + str(data.index(support)), 100.0).ok)
	assert(data.effective_height(origin) == 0)
	assert(SiteRuntime.invalidate_siege_tower_supports(data) == [fixture.key])
	assert(str(vehicle.phase) == "disabled" and float(vehicle.hp) == hp and not vehicle.deployed_pose.is_empty())
	assert(SiteRuntime.siege_person_step_allowed(data, vehicle, origin, origin, first, goal))
	assert(SiteRuntime.siege_person_step_allowed(data, vehicle, origin, first, goal, goal))
	assert(data.can_step(origin, first) and data.can_step(first, goal))
	assert(not SiteRuntime.siege_person_step_allowed(data, vehicle, goal, goal, first, origin))
	assert(not SiteRuntime.siege_person_step_allowed(data, vehicle, origin, goal, first, goal))
	assert(not SiteRuntime.siege_person_step_allowed(data, vehicle, origin, origin, first, first))
	var body := {"cell": [origin.x, origin.y], "destination": [-1, -1], "hp": 70.0, "ko": 5.0}
	assert(SiteRuntime.siege_tower_saved_person_allowed(data, vehicle, body, origin))
	body.destination = [first.x, first.y]
	assert(not SiteRuntime.siege_tower_saved_person_allowed(data, vehicle, body, origin))
	vehicle.hp = 0.0
	vehicle.ever_hp_damaged = true
	vehicle.phase = "wrecked"
	SiteEnvironment.rebuild_indexes(data)
	assert(SiteRuntime.siege_tower_physical_cells(data, vehicle).size() == 17)
	assert(not SiteRuntime.siege_tower_surface_guard(data, vehicle, func(cell: Vector2i) -> bool: return cell == origin).ok)
	completed += 1

func _check_tower_candidate_validation() -> void:
	var fixture := _tower_fixture()
	var data: TerrainData = fixture.data
	var vehicle: Dictionary = fixture.vehicle
	var source_state := JSON.stringify(data.site)
	var source_heights := data.navigation_heights().duplicate()
	assert(SiteStore._validate_siege_surface_inputs(data, data.site).ok)
	var candidate := SiteEnvironment.navigation_for_state(data, data.site.duplicate(true))
	assert(candidate.navigation_heights() == source_heights)
	assert(SiteStore._validate_siege_tower_layouts(candidate, candidate.site).ok)
	assert(JSON.stringify(data.site) == source_state and data.navigation_heights() == source_heights)
	for invalid: Variant in [null, [], {"version": 1, "cell": -1, "facing": [1, 0], "level": 0}, {"version": 1, "cell": int(vehicle.cell), "facing": [1, 1], "level": 0}]:
		var bad := data.site.duplicate(true)
		bad.vehicles[fixture.key].deployed_pose = invalid
		assert(not SiteStore._validate_siege_surface_inputs(data, bad).ok)
		assert(JSON.stringify(data.site) == source_state)
	var bad := data.site.duplicate(true)
	bad.vehicles[fixture.key].phase = "disabled"
	var bad_data := SiteEnvironment.navigation_for_state(data, bad)
	# Repairing an old support does not raise a fallen person automatically.
	assert(SiteStore._validate_siege_tower_layouts(bad_data, bad).ok)
	assert(not SiteRuntime.siege_tower_geometry(bad_data, bad.vehicles[fixture.key]).active)
	var overlapping := data.site.duplicate(true)
	var entry: Vector2i = SiteRuntime.siege_tower_geometry(data, vehicle).entry[0]
	overlapping.vehicles["999"] = {"id": "999", "kind": "cart", "cell": data.index(entry), "facing": [1, 0], "move": {}}
	assert(SiteStore._validate_siege_surface_inputs(data, overlapping).ok)
	var overlap_data := SiteEnvironment.navigation_for_state(data, overlapping)
	assert(not SiteStore._validate_siege_tower_layouts(overlap_data, overlapping).ok)
	assert(JSON.stringify(data.site) == source_state)
	completed += 1
