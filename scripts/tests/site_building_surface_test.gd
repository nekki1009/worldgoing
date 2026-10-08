extends "res://scripts/tests/site_building_ui_test.gd"

const MoveHelper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var wall_key := _formal_feature(data, "palisade", Vector2i(20, 20), Vector2i(3, 1))
	var stairs_key := _formal_feature(data, "wall_stairs", Vector2i(20, 21))
	# Build the shared-step target through the original worker while this fixture is still at peace.
	var clock_wall_key := _formal_feature(data, "palisade", Vector2i(30, 30))
	var wall: Dictionary = data.site.features[wall_key]
	assert(data.site.features.has(stairs_key))
	var surface := Vector2i(20, 20)
	var part := "c:" + str(data.index(surface))
	var original_ground := data.height_levels.duplicate()
	assert(data.effective_height(surface) == 2 and data.height_levels[data.index(surface)] == 0)
	assert(data.can_step(Vector2i(20, 23), Vector2i(20, 22)))
	assert(data.can_step(Vector2i(20, 22), Vector2i(20, 21)))
	assert(data.can_step(Vector2i(20, 21), surface))
	assert(not data.can_step(surface, surface + Vector2i.UP))
	assert(not data.can_step(Vector2i(20, 22), Vector2i(21, 22)))
	assert(data.surface_visual_offset(surface) == Vector2(0, -96))
	var actor := lab.character
	assert(actor.place(Vector2i(20, 23), true))
	for _step: int in range(3):
		assert(actor.step(Vector2i.UP))
		actor._advance_movement(1.0)
	assert(actor.terrain_cell == surface)
	assert(SiteCombatRules.ranged_line_clear(data, surface, Vector2i(20, 15)))
	assert(not SiteCombatRules.ranged_body_intersects(data, surface, Vector2i(20, 15), Vector2i(20, 19)))
	assert(SiteCombatRules.ranged_body_intersects(data, surface, Vector2i(20, 15), Vector2i(20, 16)))
	assert(not Runtime.cancel_feature(data, wall_key, lab.site_controller.reserves_cell, 1).ok)
	var original_hp := actor.hp
	var original_id := actor.person_id
	var holder := actor.item_state
	var cargo: Dictionary = data.site.manual.cargo
	var hit := Runtime.damage_structure_part(data, wall_key, part, 100.0)
	assert(hit.ok and hit.lost_surfaces.has(data.index(surface)))
	lab.resolve_structure_change(hit)
	assert(actor.terrain_cell == surface and not actor.is_moving())
	assert(actor.person_id == original_id and actor.hp == original_hp - 30.0 and actor.knockout_left > 0.0)
	assert(is_same(actor.item_state, holder) and is_same(data.site.manual.cargo, cargo))
	assert(data.height_levels == original_ground and data.effective_height(surface) == 0)
	# A second part can fall while its occupant is already unconscious.
	actor.terrain_cell = Vector2i(21, 20)
	actor.position = (Vector2(actor.terrain_cell) + Vector2.ONE * 0.5) * 64.0
	lab.resolve_structure_change(Runtime.damage_structure_part(data, wall_key, "c:" + str(data.index(actor.terrain_cell)), 100.0))
	assert(actor.hp == original_hp - 60.0 and actor.knockout_left > 0.0)
	assert(actor.terrain_cell == Vector2i(21, 20) and actor.person_id == original_id)
	# A real melee item and the common one-second combat clock own structural hits.
	actor.hp = 100.0
	actor.stun = 0.0
	actor.knockout_left = 0.0
	actor._getting_up = false
	actor.action_time = 0.0
	actor.exchange_cooldown = 0.0
	actor.exchange_stagger = 0.0
	assert(actor.place(Vector2i(22, 19), true))
	var actions: SitePersonActions = lab.site_controller.person_actions
	var remaining_part := "c:" + str(data.index(Vector2i(22, 20)))
	assert(not actions.begin_structure_attack(actor.person_id, wall_key, remaining_part).ok)
	wall.owner_faction = 2
	holder.equipped.erase("weapon") # Fixture retains the old real item in the same holder.
	var weapon := Runtime.create_equipment(data, holder, "building_test_axe", {"slot": "weapon", "asset": "axe_01", "tint": [1.0, 1.0, 1.0, 1.0]}, actor.person_id, "weapon")
	assert(weapon.ok, str(weapon))
	var started := actions.begin_structure_attack(actor.person_id, wall_key, remaining_part)
	assert(started.ok, str(started))
	actions.advance(10.0)
	assert(actions.settle_after_contacts().is_empty() and float(wall.parts[remaining_part].hp) == 100.0)
	actions.advance_structure_attacks(SiteCombatRules.EXCHANGE_ROUND_SECONDS)
	var completed := actions.settle_after_contacts()
	assert(completed.size() == 1 and completed[0].ok, str(completed))
	assert(float(wall.parts[remaining_part].hp) == 100.0 - SiteCombatRules.structure_damage("axe_01", "wood"))
	assert(data.height_levels == original_ground)
	# Candidate geometry is rebuilt before validating a saved repair contact.
	wall.owner_faction = 1
	var repair := Runtime.request_repair(data, wall_key, remaining_part, 1)
	assert(repair.ok, str(repair))
	assert(Runtime.validate_feature_layout(data, wall).ok)
	assert(Store._validate_site_values(data, data.site).ok)
	var bad: Dictionary = data.site.duplicate(true)
	bad.features[wall_key].parts[remaining_part].hp = INF
	assert(not Store._validate_site_values(data, bad).ok)
	_check_shared_structure_attack(lab, clock_wall_key)
	lab.free()
	_check_batch()
	TerrainArmy.release_contact_source()
	await process_frame
	print("SITE_BUILDING_SURFACE_PASS effective navigation/LOS, real stair steps, source-cell collapse/KO/items, weapon combat clock, strict saved layout, atomic batch order retention")
	quit()

func _check_shared_structure_attack(lab: TerrainLab, feature_key: String) -> void:
	# Reuse this fixture's original scene, person and held item; no alternate clock.
	var data := lab.terrain
	var actor := lab.character
	var actions: SitePersonActions = lab.site_controller.person_actions
	assert(lab.exchange_enabled and actor.exchange_enabled and lab.actor_present(actor))
	lab.simulation_speed = 1.0
	actor.reset_combat() # Explicit fixture reset after the preceding collapse/attack cases.
	var holder: Dictionary = actor.item_state
	var cargo: Dictionary = data.site.manual.cargo
	var weapon_id := str(holder.equipped.weapon)
	assert(str(data.site.item_definitions[str(data.site.item_records[weapon_id].definition)].asset) == "axe_01")
	var feature: Dictionary = data.site.features[feature_key]
	assert(str(feature.get("material", "wood")) == "wood")
	feature.owner_faction = 2
	var part_id := "c:" + str(data.index(Vector2i(30, 30)))
	assert(actor.place(Vector2i(30, 29), true))
	lab.site_controller.release_worker()
	var initial_hp := float(feature.parts[part_id].hp)
	var expected_damage := SiteCombatRules.structure_damage("axe_01", "wood")
	assert(expected_damage > 0.0 and expected_damage < initial_hp)
	var started := actions.begin_structure_attack(actor.person_id, feature_key, part_id)
	assert(started.ok, str(started))
	var clock_before := Runtime.now(data)
	assert(SiteCombatRules.EXCHANGE_ROUND_SECONDS == 1.0 and TerrainLab.EXCHANGE_ACTION_STEP == 1.0 / 30.0)
	for tick in range(30):
		var step: Dictionary = lab._advance_original_shared_step(TerrainLab.EXCHANGE_ACTION_STEP)
		assert(step.ok and bool(step.get("completed", false)), str(step))
		assert(is_equal_approx(float(step.action_seconds), TerrainLab.EXCHANGE_ACTION_STEP))
		assert(is_equal_approx(float(step.game_seconds), TerrainLab.EXCHANGE_ACTION_STEP))
		if tick < 29:
			assert(actions.is_busy(actor.person_id) and float(feature.parts[part_id].hp) == initial_hp, "The original structural strike cannot commit before its one-second boundary")
			assert(is_equal_approx(float(actions.job_for(actor.person_id).elapsed), float(tick + 1) * TerrainLab.EXCHANGE_ACTION_STEP))
	assert(not actions.is_busy(actor.person_id))
	assert(float(feature.parts[part_id].hp) == initial_hp - expected_damage, "The controller-present common step commits exactly one original structural hit")
	assert(absf((Runtime.now(data) - clock_before) * 60.0 - 1.0) < 0.00000001, "The original Site clock consumes the same thirty tactical slices")
	var settled_clock := Runtime.now(data)
	for _repeat in range(2):
		assert(actions.settle_after_contacts().is_empty(), "A consumed structural job cannot submit again")
		assert(float(feature.parts[part_id].hp) == initial_hp - expected_damage and Runtime.now(data) == settled_clock)
	assert(is_same(actor.item_state, holder) and is_same(data.site.manual.cargo, cargo))
	assert(str(holder.equipped.weapon) == weapon_id and str(data.site.item_records[weapon_id].holder) == str(holder.holder))
	print("SITE_BUILDING_SHARED_STRUCTURE_CLOCK_PASS: original Controller, thirty 30 Hz tactical slices, one structural commit, repeated settle inert; not a fire or GPU result")

func _check_batch() -> void:
	var data := MoveHelper.build_flat_map(30, 20)
	var army := MoveHelper.create_test_army(data, 1, 0, 3, Vector2i(5, 5))
	var coordinator := SiteCombatMovementCoordinator.new()
	coordinator.register_formation(army)
	assert(army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(15, 5)).ok)
	var serial := army.get_order_serial()
	var destination := army._combat_deployment_plan
	var source: Array[Vector2i] = army.cells.duplicate()
	coordinator._rebuild_occupancy()
	var grid := coordinator.movement_reservation_grid
	grid.begin_tick(coordinator._current_occupancy, data)
	for i: int in range(2, -1, -1):
		grid.propose_move(army.formation_runtime_id, army.combat_identity(i), serial, source[i], source[i] + Vector2i.RIGHT)
	grid.resolve_all()
	grid.commit_all(coordinator._member_lookup, 1)
	coordinator._register_started_batches()
	assert(coordinator._inflight_batches.size() == 1)
	army.prepare_combat(0.072)
	for y: int in range(data.size.y): data.static_blocked[data.index(Vector2i(8, y))] = 1
	data.navigation_revision += 1
	army._preserve_structure_order = true
	coordinator.complete_committed_moves()
	assert(coordinator._inflight_batches.is_empty() and army._combat_batch_members.is_empty())
	assert(army.cells == source and army._reserved_cells.is_empty())
	assert(army.combat_order == TerrainArmy.CombatOrder.MOVE and army.get_order_serial() == serial)
	assert(is_same(destination, army._combat_deployment_plan))
	assert(not coordinator.deployment_registry.get_formation_reserved_slots(1).is_empty())
	# The blocked route has no proposals until a terrain/roster revision permits retry.
	army._wait_for_structure_route()
	grid.begin_tick(coordinator._current_occupancy, data)
	army.propose_combat_moves(grid)
	assert(grid.get_proposals().is_empty())
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(army.capture_combat_state()))
	assert(snapshot.structure_waiting and Store._valid_combat_movement_snapshot(data, snapshot, {}))
	var invalid := snapshot.duplicate(true)
	invalid.erase("structure_waiting")
	assert(not Store._valid_combat_movement_snapshot(data, invalid, {}))
	var restored := TerrainArmy.new()
	restored.restore_combat_state(snapshot, data, null, null)
	assert(restored.combat_order == TerrainArmy.CombatOrder.MOVE and restored.get_order_serial() == serial)
	assert(not restored._refresh_move_terrain_revision() and restored._combat_move_plan.structure_blocked)
	assert(restored._combat_deployment_plan.resolved_anchor == destination.resolved_anchor)
	for y: int in range(data.size.y): data.static_blocked[data.index(Vector2i(8, y))] = 0
	data.navigation_revision += 1
	assert(restored._refresh_move_terrain_revision() and not restored._combat_move_plan.structure_blocked)
	assert(restored.combat_order == TerrainArmy.CombatOrder.MOVE and restored.get_order_serial() == serial)
	restored.free()
	coordinator.unregister_formation(army)
	army.free()
