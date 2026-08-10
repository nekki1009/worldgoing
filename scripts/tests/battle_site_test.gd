extends SceneTree

const TEST_SEED: int = 123456789
const EXAMPLE_CENTER: Vector2i = Vector2i(352, 431)
const TEST_WORLD_CELL: Vector2i = Vector2i(3, 4)
const INVALID_CELL: Vector2i = Vector2i(2_147_483_647, 2_147_483_647)

class FastWorldData:
	extends WorldData

	var road_overlays: Dictionary = {}

	func get_roads_for_region(world_cell: Vector2i, _world_seed: int) -> RegionRoadOverlay:
		var stored: Variant = road_overlays.get(world_cell, null)
		return stored as RegionRoadOverlay if stored is RegionRoadOverlay else RegionRoadOverlay.new()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	assert(load("res://scenes/Main.tscn") is PackedScene, "Main scene could not be loaded")
	assert(load("res://scenes/site/BattleSite.tscn") is PackedScene, "Battle Site scene could not be loaded")
	var world_data: FastWorldData = FastWorldData.new()
	var session: GameSession = _test_session(EXAMPLE_CENTER)
	var region_runtime: RegionRuntime = RegionRuntime.new(session, world_data)
	var runtime: BattlePreviewRuntime = BattlePreviewRuntime.new(session, world_data, region_runtime)
	var context: BattleSiteContext = _test_context(EXAMPLE_CENTER)

	_test_context_and_footprint(context)
	_test_context_validation()
	print("TEST 1-2 PASS: deterministic identity, exact footprint and trust-boundary validation")

	var snapshot: BattleSiteSnapshot = runtime.query_debug_preview(EXAMPLE_CENTER)
	assert(snapshot.has_preview(), "Battle preview query returned no snapshot")
	assert(snapshot.size_meters == Vector2(300.0, 300.0), "3 x 100m did not produce a 300m preview")
	assert(snapshot.footprint_cells.size() == 9, "Battle preview did not project exactly nine cells")
	assert(snapshot.site_layouts.size() == 9, "Battle preview did not compose nine Site bases")
	for layout: SiteLayoutData in snapshot.site_layouts:
		assert(layout.layout_kind == SiteLayoutData.LayoutKind.CELL_BASE)
		assert(layout.has_navigation_base())
	print("TEST 3 PASS: typed BattleSiteSnapshot represents nine Site bases in a 300m x 300m preview")

	_test_frontage()
	print("TEST 4 PASS: terrain frontage splits deployment from reserve")

	_test_cross_region_border(world_data)
	print("TEST 5 PASS: resolved footprint crosses into the adjacent Region")

	_test_negative_runtime_boundary(runtime)
	print("TEST 6 PASS: negative coordinates convert correctly and finite Runtime rejects out-of-world preview")

	_test_entry_directions()
	print("TEST 7 PASS: deployment zones and facing are correct")

	_test_terrain_orientation(world_data)
	print("TEST 8 PASS: resolved cells preserve north/east/south/west orientation")

	_test_road_and_river_projection()
	print("TEST 9 PASS: resolved Road and River data project into corridor data")

	_test_determinism(runtime)
	print("TEST 10 PASS: repeated Runtime preview queries are deterministic")

	_test_query_is_read_only(world_data)
	print("TEST 11 PASS: Battle preview query does not mutate gameplay state")

	_test_region_delta_projection()
	print("TEST 12 PASS: Region Delta terrain override is reflected in Battle preview")

	_test_typed_failure()
	print("TEST 13 PASS: invalid and impassable destinations return typed failure reasons")

	_test_snapshot_is_detached(runtime)
	print("TEST 14 PASS: Presentation snapshot mutation cannot change Runtime data")
	_test_active_battle_runtime(runtime, snapshot, session)
	print("TEST 15 PASS: active Battle Runtime owns formations, path commands, movement, and detached snapshots")

	_test_dependency_boundary()
	print("TEST 16 PASS: Navigation and BattleSiteMap are orchestration/presentation only")

	await _test_region_battle_return()
	print("TEST 17 PASS: Region -> Battle Preview -> Region replaces the Scene without losing selection")
	print("TEST 18 PASS: preview uses draw data, not soldier or AI Nodes")
	_test_formation_visual_contract()
	print("TEST 19 PASS: 100-person Formation geometry and 5-column ranks are deterministic")
	await _test_max_personnel_visual()
	print("TEST 20 PASS: 9,000 personnel render as 9,000 GPU instances without Soldier Nodes")
	print("Battle preview boundary tests passed: 20 cases")
	quit()

func _test_context_and_footprint(context: BattleSiteContext) -> void:
	assert(context != null, "BattleSiteContext creation failed")
	assert(context.center_world_cell == Vector2i(3, 4), "Center World Cell conversion failed")
	assert(context.center_region_cell == Vector2i(52, 31), "Center Region Cell conversion failed")
	assert(context.footprint_size == Vector2i(3, 3), "Battle footprint metadata is not 3x3")
	var expected: Array[Vector2i] = [
		Vector2i(351, 430), Vector2i(352, 430), Vector2i(353, 430),
		Vector2i(351, 431), Vector2i(352, 431), Vector2i(353, 431),
		Vector2i(351, 432), Vector2i(352, 432), Vector2i(353, 432),
	]
	assert(BattleSiteGenerator.footprint_global_cells(EXAMPLE_CENTER) == expected, "3x3 global footprint is incorrect")
	var duplicate: BattleSiteContext = _test_context(EXAMPLE_CENTER)
	assert(context.battle_id == duplicate.battle_id, "Deterministic Battle ID changed")
	assert(context.battle_seed == duplicate.battle_seed, "Deterministic Battle Seed changed")

func _test_context_validation() -> void:
	var valid_attacker: BattleParticipantData = BattleParticipantData.new("a", "A", 10)
	var valid_defender: BattleParticipantData = BattleParticipantData.new("d", "D", 10)
	assert(BattleSiteContext.create(TEST_SEED, EXAMPLE_CENTER, null, valid_defender, 0, 2) == null)
	assert(BattleSiteContext.create(TEST_SEED, EXAMPLE_CENTER, BattleParticipantData.new("", "A", 10), valid_defender, 0, 2) == null)
	assert(BattleSiteContext.create(TEST_SEED, EXAMPLE_CENTER, valid_attacker, BattleParticipantData.new("a", "D", 10), 0, 2) == null)
	assert(BattleSiteContext.create(TEST_SEED, EXAMPLE_CENTER, BattleParticipantData.new("a", "A", 0), valid_defender, 0, 2) == null)
	assert(BattleSiteContext.create(TEST_SEED, EXAMPLE_CENTER, valid_attacker, valid_defender, 0, 2, -1) == null)
	assert(BattleSiteContext.create(
		TEST_SEED,
		EXAMPLE_CENTER,
		BattleParticipantData.new("a", "A", 4_501),
		BattleParticipantData.new("d", "D", 4_500),
		0,
		2
	) == null)
	var context: BattleSiteContext = BattleSiteContext.create(TEST_SEED, EXAMPLE_CENTER, valid_attacker, valid_defender, 0, 2)
	valid_attacker.participant_id = "changed"
	assert(context != null and context.attacker.participant_id == "a", "Context retained mutable caller participant data")

func _test_frontage() -> void:
	var forest: Dictionary = BattleRules.deployment(1000, TerrainType.FOREST)
	assert(forest["initial_deployed_personnel"] == 500 and forest["reserve_personnel"] == 500)
	var plains: Dictionary = BattleRules.deployment(1000, TerrainType.PLAINS)
	assert(plains["initial_deployed_personnel"] == 1000 and plains["reserve_personnel"] == 0)
	var mountain: Dictionary = BattleRules.deployment(1000, TerrainType.MOUNTAIN)
	assert(mountain["initial_deployed_personnel"] == 250 and mountain["reserve_personnel"] == 750)
	var water: Dictionary = BattleRules.deployment(1000, TerrainType.WATER)
	assert(water["initial_deployed_personnel"] == 0 and water["reserve_personnel"] == 1000)

func _test_cross_region_border(world_data: FastWorldData) -> void:
	var center: Vector2i = _find_passable_border_center(world_data)
	assert(center != INVALID_CELL, "No passable Region-border center was found")
	var runtime: BattlePreviewRuntime = _runtime_for(world_data, _test_session(center))
	var snapshot: BattleSiteSnapshot = runtime.query_debug_preview(center)
	assert(snapshot.has_preview(), "Cross-Region preview query failed")
	var seen_adjacent_region: bool = false
	for cell: Dictionary in snapshot.footprint_cells:
		if cell["world_cell"] == Vector2i(4, 4):
			seen_adjacent_region = true
			assert((cell["region_cell"] as Vector2i).x == 0, "Adjacent Region local x is not zero")
	assert(seen_adjacent_region, "Right-hand adjacent Region was not resolved")

func _test_negative_runtime_boundary(runtime: BattlePreviewRuntime) -> void:
	var footprint: Array[Vector2i] = BattleSiteGenerator.footprint_global_cells(Vector2i(-1, -1))
	assert(footprint.front() == Vector2i(-2, -2) and footprint.back() == Vector2i.ZERO)
	for global_cell: Vector2i in footprint:
		var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(global_cell)
		assert(WorldCoordinates.is_valid_region_cell(converted["region_cell"] as Vector2i))
	var rejected: BattleSiteSnapshot = runtime.query_debug_preview(Vector2i(-1, -1))
	assert(not rejected.success and rejected.failure_reason == BattleSiteSnapshot.FailureReason.INVALID_DESTINATION)

func _test_entry_directions() -> void:
	var size: Vector2 = Vector2(300.0, 300.0)
	var north: Rect2 = BattleRules.deployment_zone(size, BattleSiteContext.EntryDirection.NORTH)
	var south: Rect2 = BattleRules.deployment_zone(size, BattleSiteContext.EntryDirection.SOUTH)
	var west: Rect2 = BattleRules.deployment_zone(size, BattleSiteContext.EntryDirection.WEST)
	var east: Rect2 = BattleRules.deployment_zone(size, BattleSiteContext.EntryDirection.EAST)
	assert(north == Rect2(0.0, 0.0, 300.0, 60.0))
	assert(south == Rect2(0.0, 240.0, 300.0, 60.0))
	assert(west == Rect2(0.0, 0.0, 60.0, 300.0))
	assert(east == Rect2(240.0, 0.0, 60.0, 300.0))
	assert(BattleRules.facing_vector(BattleSiteContext.EntryDirection.SOUTH) == Vector2.UP)
	assert(BattleRules.facing_vector(BattleSiteContext.EntryDirection.NORTH) == Vector2.DOWN)
	assert(BattleRules.facing_vector(BattleSiteContext.EntryDirection.WEST) == Vector2.RIGHT)
	assert(BattleRules.facing_vector(BattleSiteContext.EntryDirection.EAST) == Vector2.LEFT)

func _test_terrain_orientation(world_data: FastWorldData) -> void:
	var center: Vector2i = _find_terrain_boundary(world_data)
	assert(center != INVALID_CELL, "No passable mixed-terrain footprint was found")
	var snapshot: BattleSiteSnapshot = _runtime_for(world_data, _test_session(center)).query_debug_preview(center)
	assert(snapshot.has_preview(), "Orientation preview query failed")
	var cells: Array[Dictionary] = snapshot.footprint_cells
	assert(cells[1]["global_region_cell"] == center + Vector2i.UP)
	assert(cells[1]["local_origin_meters"] == Vector2(100.0, 0.0))
	assert(cells[5]["global_region_cell"] == center + Vector2i.RIGHT)
	assert(cells[5]["local_origin_meters"] == Vector2(200.0, 100.0))
	assert(cells[7]["global_region_cell"] == center + Vector2i.DOWN)
	assert(cells[7]["local_origin_meters"] == Vector2(100.0, 200.0))
	assert(cells[3]["global_region_cell"] == center + Vector2i.LEFT)
	assert(cells[3]["local_origin_meters"] == Vector2(0.0, 100.0))

func _test_road_and_river_projection() -> void:
	var road_world: FastWorldData = FastWorldData.new()
	road_world.road_overlays[TEST_WORLD_CELL] = _test_road_overlay()
	var road_snapshot: BattleSiteSnapshot = _runtime_for(
		road_world,
		_test_session(EXAMPLE_CENTER)
	).query_debug_preview(EXAMPLE_CENTER)
	assert(road_snapshot.has_preview(), "Road preview query failed")
	var road_center: Dictionary = road_snapshot.center_cell
	assert(bool(road_center["road"]), "Resolved Road disappeared from preview")
	var road_offsets: Array = road_center["road_connection_offsets"] as Array
	assert(road_offsets.has(Vector2i.LEFT) and road_offsets.has(Vector2i.RIGHT), "Road direction changed")

	var river_world: FastWorldData = FastWorldData.new()
	var river_center: Vector2i = _find_passable_center_near_river(river_world)
	assert(river_center != INVALID_CELL, "No passable center near a River was found")
	var river_snapshot: BattleSiteSnapshot = _runtime_for(
		river_world,
		_test_session(river_center)
	).query_debug_preview(river_center)
	assert(river_snapshot.has_preview(), "River preview query failed")
	var river_seen: bool = false
	for cell: Dictionary in river_snapshot.footprint_cells:
		if bool(cell["river"]):
			river_seen = true
			assert(not (cell["river_connection_offsets"] as Array).is_empty(), "River corridor has no direction")
	assert(river_seen, "Resolved River disappeared from preview")

func _test_determinism(runtime: BattlePreviewRuntime) -> void:
	var first: BattleSiteSnapshot = runtime.query_debug_preview(EXAMPLE_CENTER)
	var second: BattleSiteSnapshot = runtime.query_debug_preview(EXAMPLE_CENTER)
	assert(first.terrain_hash == second.terrain_hash, "Battle terrain changed on regeneration")
	assert(first.preview_hash == second.preview_hash, "Deployment preview changed on regeneration")
	assert(first.terrain_debug_representation == second.terrain_debug_representation)

func _test_query_is_read_only(world_data: FastWorldData) -> void:
	var session: GameSession = _test_session(EXAMPLE_CENTER)
	var runtime: BattlePreviewRuntime = _runtime_for(world_data, session)
	var position_before: Vector2i = session.party.current_global_region_cell
	var time_before: int = session.world_time_seconds
	var path_before: GlobalTravelPath = session.active_global_travel_path
	var region_state_count_before: int = session.region_runtime_states.size()
	var snapshot: BattleSiteSnapshot = runtime.query_debug_preview(EXAMPLE_CENTER)
	assert(snapshot.has_preview())
	assert(session.party.current_global_region_cell == position_before)
	assert(session.world_time_seconds == time_before)
	assert(session.active_global_travel_path == path_before)
	assert(session.region_runtime_states.size() == region_state_count_before)

func _test_region_delta_projection() -> void:
	var world_data: FastWorldData = FastWorldData.new()
	var center: Vector2i = _find_plain_or_forest_center(world_data)
	assert(center != INVALID_CELL, "No Delta test center found")
	var session: GameSession = _test_session(center)
	var region_runtime: RegionRuntime = RegionRuntime.new(session, world_data)
	var runtime: BattlePreviewRuntime = BattlePreviewRuntime.new(session, world_data, region_runtime)
	var before: BattleSiteSnapshot = runtime.query_debug_preview(center)
	assert(before.has_preview())
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(center)
	var replacement: int = TerrainType.FOREST if before.center_terrain == TerrainType.PLAINS else TerrainType.PLAINS
	assert(region_runtime.apply_test_terrain_override(
		converted["world_cell"] as Vector2i,
		converted["region_cell"] as Vector2i,
		replacement
	))
	var after: BattleSiteSnapshot = runtime.query_debug_preview(center)
	assert(after.has_preview() and after.center_terrain == replacement)
	assert(after.terrain_hash != before.terrain_hash, "Delta did not change resolved terrain hash")

func _test_typed_failure() -> void:
	var world_data: FastWorldData = FastWorldData.new()
	var center: Vector2i = _find_plain_or_forest_center(world_data)
	var session: GameSession = _test_session(center)
	var region_runtime: RegionRuntime = RegionRuntime.new(session, world_data)
	var runtime: BattlePreviewRuntime = BattlePreviewRuntime.new(session, world_data, region_runtime)
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(center)
	assert(region_runtime.apply_test_terrain_override(
		converted["world_cell"] as Vector2i,
		converted["region_cell"] as Vector2i,
		TerrainType.WATER
	))
	var impassable: BattleSiteSnapshot = runtime.query_debug_preview(center)
	assert(not impassable.success and impassable.failure_reason == BattleSiteSnapshot.FailureReason.IMPASSABLE)
	var invalid: BattleSiteSnapshot = runtime.query_debug_preview(Vector2i(-1000, -1000))
	assert(not invalid.success and invalid.failure_reason == BattleSiteSnapshot.FailureReason.INVALID_DESTINATION)
	var invalid_participant: BattleSiteSnapshot = runtime.query_preview(
		center,
		BattleParticipantData.new("", "Invalid", 10),
		BattleParticipantData.new("defender", "Defender", 10),
		BattleSiteContext.EntryDirection.SOUTH,
		BattleSiteContext.EntryDirection.NORTH
	)
	assert(not invalid_participant.success \
		and invalid_participant.failure_reason == BattleSiteSnapshot.FailureReason.INVALID_PARTICIPANT)
	session.active_global_travel_path = GlobalTravelPath.new()
	var travelling: BattleSiteSnapshot = runtime.query_debug_preview(center)
	assert(not travelling.success \
		and travelling.failure_reason == BattleSiteSnapshot.FailureReason.TRAVEL_IN_PROGRESS)

func _test_snapshot_is_detached(runtime: BattlePreviewRuntime) -> void:
	var snapshot: BattleSiteSnapshot = runtime.query_debug_preview(EXAMPLE_CENTER)
	var original_terrain: int = snapshot.center_terrain
	snapshot.center_cell["terrain_type"] = TerrainType.WATER
	snapshot.footprint_cells.clear()
	var queried_again: BattleSiteSnapshot = runtime.query_debug_preview(EXAMPLE_CENTER)
	assert(queried_again.has_preview() and queried_again.center_terrain == original_terrain)

func _test_active_battle_runtime(
		runtime: BattlePreviewRuntime,
		preview: BattleSiteSnapshot,
		session: GameSession
	) -> void:
	var begin: BattleRuntimeResult = runtime.begin_battle(preview)
	assert(begin.success and begin.snapshot != null, "Active Battle Runtime did not begin")
	assert(session.has_active_battle(), "GameSession did not own active Battle state")
	var state: BattleRuntimeState = session.active_battle_state
	assert(state.formations.size() == 18, "Deployment did not create deterministic formations")
	var attacker_id: String = ""
	for key: Variant in state.formations.keys():
		var formation: BattleFormationData = state.formations[key] as BattleFormationData
		if formation != null and formation.side == BattleFormationData.Side.ATTACKER:
			attacker_id = formation.formation_id
			break
	assert(not attacker_id.is_empty(), "Attacker formation was not created")
	var move: BattleRuntimeResult = runtime.issue_move(attacker_id, Vector2(150.0, 150.0))
	assert(move.success and move.path.size() > 1, "Formation move command did not produce a path")
	var before: Vector2 = state.find_formation(attacker_id).battle_position_m
	var advance: BattleRuntimeResult = runtime.advance_battle(1.0)
	assert(advance.success and advance.changed, "Battle time did not advance formation movement")
	var after: Vector2 = state.find_formation(attacker_id).battle_position_m
	assert(after != before, "Formation position did not change continuously")
	var active_snapshot: BattleSiteSnapshot = runtime.active_snapshot()
	assert(active_snapshot != null and active_snapshot.active_battle)
	assert(active_snapshot.formations.size() == state.formations.size())
	active_snapshot.formations[0].battle_position_m = Vector2.ZERO
	assert(state.formations[active_snapshot.formations[0].formation_id].battle_position_m != Vector2.ZERO)
	var elapsed_before_speed: float = state.elapsed_seconds
	for option: float in BattleRules.BATTLE_SPEED_OPTIONS:
		var speed_result: BattleRuntimeResult = runtime.set_battle_speed_multiplier(option)
		assert(speed_result.success and speed_result.failure_code == BattleRuntimeResult.Code.SPEED_CHANGED)
		assert(is_equal_approx(state.battle_speed_multiplier, option))
	var invalid_speed: BattleRuntimeResult = runtime.set_battle_speed_multiplier(3.0)
	assert(not invalid_speed.success and invalid_speed.failure_code == BattleRuntimeResult.Code.INVALID_SPEED)
	var speed_advance: BattleRuntimeResult = runtime.advance_battle(1.0)
	assert(speed_advance.success and is_equal_approx(
		state.elapsed_seconds,
		elapsed_before_speed + 16.0
	))
	assert(runtime.set_battle_speed_multiplier(1.0).success)
	_test_command_authority(runtime, preview, session)
	assert(runtime.leave_battle().success and not session.has_active_battle())

func _test_command_authority(
		runtime: BattlePreviewRuntime,
		preview: BattleSiteSnapshot,
		session: GameSession
	) -> void:
	var state: BattleRuntimeState = session.active_battle_state
	var commander_id: String = str(
		state.commander_formation_ids[BattleFormationData.Side.ATTACKER]
	)
	var subordinate_id: String = ""
	for key: Variant in state.formations.keys():
		var formation: BattleFormationData = state.formations[key] as BattleFormationData
		if formation != null and formation.side == BattleFormationData.Side.ATTACKER \
			and formation.formation_id != commander_id:
			subordinate_id = formation.formation_id
			break
	assert(not commander_id.is_empty() and not subordinate_id.is_empty())
	assert(state.find_formation(commander_id).is_commander_formation)
	assert(state.find_formation(subordinate_id).is_controllable() == false)
	var simple: BattleRuntimeResult = runtime.issue_simple_order(
		session.party.party_id,
		subordinate_id,
		BattleOrderData.SimpleIntent.ADVANCE
	)
	assert(simple.success and simple.failure_code == BattleRuntimeResult.Code.ORDER_QUEUED)
	assert(simple.order_state == BattleOrderData.State.QUEUED)
	runtime.advance_battle(simple.cost_seconds * 0.5)
	assert(runtime.query_order(simple.order_id).order_state == BattleOrderData.State.QUEUED)
	runtime.advance_battle(simple.cost_seconds)
	var simple_status: BattleRuntimeResult = runtime.query_order(simple.order_id)
	assert(simple_status.success and simple_status.order_state == BattleOrderData.State.DELIVERED)
	assert(state.find_formation(subordinate_id).intent == BattleFormationData.Intent.ADVANCE)
	var before_simple_move: Vector2 = state.find_formation(subordinate_id).battle_position_m
	runtime.advance_battle(10.0)
	assert(state.find_formation(subordinate_id).battle_position_m != before_simple_move,
		"Delivered ADVANCE order did not move the subordinate Formation")
	var fine: BattleRuntimeResult = runtime.issue_fine_order(
		session.party.party_id,
		subordinate_id,
		BattleOrderData.FineIntent.MOVE_TO,
		state.find_formation(subordinate_id).battle_position_m + Vector2(30.0, 0.0)
	)
	assert(fine.success and fine.failure_code == BattleRuntimeResult.Code.DISPATCH_CREATED)
	assert(runtime.query_order(fine.order_id).order_state == BattleOrderData.State.EN_ROUTE)
	runtime.advance_battle(100.0)
	assert(runtime.query_order(fine.order_id).success, "Fine dispatch was not delivered")
	assert(runtime.query_order(fine.order_id).order_state == BattleOrderData.State.DELIVERED)

	runtime.leave_battle()
	var restarted: BattleRuntimeResult = runtime.begin_battle(preview)
	assert(restarted.success)
	state = session.active_battle_state
	commander_id = str(state.commander_formation_ids[BattleFormationData.Side.ATTACKER])
	subordinate_id = ""
	for key: Variant in state.formations.keys():
		var formation: BattleFormationData = state.formations[key] as BattleFormationData
		if formation != null and formation.side == BattleFormationData.Side.ATTACKER \
			and formation.formation_id != commander_id:
			subordinate_id = formation.formation_id
			break
	var intercepted: BattleRuntimeResult = runtime.issue_fine_order(
		session.party.party_id,
		subordinate_id,
		BattleOrderData.FineIntent.MOVE_TO,
		state.find_formation(subordinate_id).battle_position_m + Vector2(30.0, 0.0)
	)
	assert(intercepted.success and intercepted.failure_code == BattleRuntimeResult.Code.DISPATCH_CREATED)
	var dispatch: BattleDispatchData = state.find_dispatch(intercepted.order_id)
	assert(dispatch != null and dispatch.path.size() > 2)
	var defender_id: String = ""
	for key: Variant in state.formations.keys():
		var formation: BattleFormationData = state.formations[key] as BattleFormationData
		if formation != null and formation.side == BattleFormationData.Side.DEFENDER:
			defender_id = formation.formation_id
			break
	var intercept_cell: Vector2i = dispatch.path[dispatch.path.size() / 2]
	state.find_formation(defender_id).battle_position_m = Vector2(intercept_cell) * float(SiteLayoutData.CELL_SIZE_METERS) \
		+ Vector2.ONE * float(SiteLayoutData.CELL_SIZE_METERS) * 0.5
	runtime.advance_battle(100.0)
	var intercepted_status: BattleRuntimeResult = runtime.query_order(intercepted.order_id)
	assert(not intercepted_status.success \
		and intercepted_status.failure_code == BattleRuntimeResult.Code.MESSENGER_INTERCEPTED)
	assert(state.find_dispatch(intercepted.order_id).state == BattleOrderData.State.INTERCEPTED)
	runtime.leave_battle()

	var npc_attacker: BattleParticipantData = BattleParticipantData.new(
		"npc_attacker",
		"NPC Army",
		1000,
		"npc_commander",
		BattleParticipantData.CommanderKind.NPC,
		0
	)
	var npc_defender: BattleParticipantData = BattleParticipantData.new("npc_defender", "NPC Enemy", 800)
	var npc_preview: BattleSiteSnapshot = runtime.query_preview(
		preview.context.center_global_region_cell,
		npc_attacker,
		npc_defender,
		BattleSiteContext.EntryDirection.SOUTH,
		BattleSiteContext.EntryDirection.NORTH
	)
	assert(npc_preview.has_preview() and npc_preview.context.attacker.commander_kind == BattleParticipantData.CommanderKind.NPC)
	assert(runtime.begin_battle(npc_preview).success)
	state = session.active_battle_state
	commander_id = str(state.commander_formation_ids[BattleFormationData.Side.ATTACKER])
	var npc_direct: BattleRuntimeResult = runtime.issue_fine_order(
		"npc_commander",
		commander_id,
		BattleOrderData.FineIntent.SET_FACING,
		Vector2.ZERO,
		Vector2.LEFT
	)
	assert(npc_direct.success and npc_direct.failure_code == BattleRuntimeResult.Code.ORDER_APPLIED)
	assert(state.find_formation(commander_id).facing_direction == Vector2.LEFT)

func _test_dependency_boundary() -> void:
	var region_source: String = FileAccess.get_file_as_string("res://scripts/region/region_map.gd")
	var navigation_source: String = FileAccess.get_file_as_string("res://scripts/core/navigation_controller.gd")
	var map_source: String = FileAccess.get_file_as_string("res://scripts/battle/battle_site_map.gd")
	var runtime_source: String = FileAccess.get_file_as_string("res://scripts/runtime/battle_preview_runtime.gd")
	var session_source: String = FileAccess.get_file_as_string("res://scripts/core/game_session.gd")
	assert(region_source.find("BattleSiteGenerator") == -1 and region_source.find("BattleRules") == -1)
	assert(region_source.find("BATTLE_CELL_IMPASSABLE") == -1)
	assert(navigation_source.find("BattleParticipantData.new") == -1)
	assert(navigation_source.find("active_battle_context") == -1)
	assert(map_source.find("WorldData") == -1 and map_source.find("GameSession") == -1)
	assert(map_source.find("BattleSiteGenerator") == -1)
	assert(runtime_source.find("RegionMap") == -1 and runtime_source.find("BattleSiteMap") == -1)
	assert(runtime_source.find("Camera2D") == -1 and runtime_source.find("TileMapLayer") == -1)
	assert(session_source.find("active_battle_context") == -1)

func _test_region_battle_return() -> void:
	var world_data: FastWorldData = FastWorldData.new()
	var navigation: NavigationController = NavigationController.new()
	var map_root: Node2D = Node2D.new()
	get_root().add_child(map_root)
	get_root().add_child(navigation)
	navigation.world_data = world_data
	navigation.session = _test_session(EXAMPLE_CENTER)
	navigation.setup(map_root)
	navigation.show_region()
	await process_frame
	var selected_local: Vector2i = _find_passable_local(world_data)
	assert(selected_local != Vector2i(-1, -1), "No passable Battle preview cell found")
	var selected_world: Vector2i = navigation.session.selected_world_cell
	navigation.session.selected_region_cell = selected_local
	var region_map: RegionMap = navigation.get_current_map() as RegionMap
	var battle_key: InputEventKey = InputEventKey.new()
	battle_key.keycode = KEY_B
	battle_key.pressed = true
	region_map._unhandled_input(battle_key)
	await process_frame
	assert(navigation.get_current_layer() == NavigationController.MapLayer.BATTLE_SITE, "B did not enter Battle preview")
	var battle_site: BattleSiteMap = navigation.get_current_map() as BattleSiteMap
	assert(battle_site != null and battle_site.snapshot.has_preview(), "Battle preview Scene received no snapshot")
	var first_battle_id: String = battle_site.snapshot.context.battle_id
	var first_terrain_hash: String = battle_site.snapshot.terrain_hash
	var first_preview_hash: String = battle_site.snapshot.preview_hash
	assert(battle_site.preview_marker_count("attacker") == 5)
	assert(battle_site.preview_marker_count("defender") == 5)
	assert(battle_site.soldier_multimesh.instance_count == 1_800)
	assert(battle_site.soldier_multimesh.visible_instance_count == 1_800)
	assert(_descendant_count(battle_site) < 30, "Battle preview instantiated a large Node population")
	assert(not _has_soldier_nodes(battle_site), "Battle preview instantiated soldier/AI Nodes")
	var selected_attacker: BattleFormationData = null
	for formation: BattleFormationData in battle_site.active_formations:
		if formation.side == BattleFormationData.Side.ATTACKER:
			selected_attacker = formation
			break
	assert(selected_attacker != null, "Battle preview has no selectable attacker Formation")
	battle_site._select_formation(selected_attacker.battle_position_m)
	var advance_button: Button = battle_site.get_node(
		"BattleDebugPanel/Panel/Margin/Content/CommandGrid/AdvanceButton"
	) as Button
	assert(advance_button != null and not advance_button.disabled,
		"Advance command button is not available after Formation selection")
	advance_button.emit_signal("pressed")
	assert(battle_site.active_orders.size() == 1, "Command button did not reach Battle Runtime")
	var advance_key: InputEventKey = InputEventKey.new()
	advance_key.keycode = KEY_1
	advance_key.pressed = true
	battle_site._unhandled_input(advance_key)
	assert(battle_site.selected_formation_id == selected_attacker.formation_id)
	assert(battle_site.active_orders.size() == 2, "Command shortcut did not reach Battle Runtime")
	assert(str(battle_site.get_debug_state()["instruction"]).find("1-5") >= 0)
	var speed_button: Button = battle_site.get_node(
		"BattleDebugPanel/Panel/Margin/Content/SpeedGrid/Speed16Button"
	) as Button
	assert(speed_button != null, "Battle speed controls are missing")
	speed_button.emit_signal("pressed")
	assert(is_equal_approx(battle_site.battle_speed_multiplier, 16.0))
	assert(is_equal_approx(navigation.session.active_battle_state.battle_speed_multiplier, 16.0))
	battle_site._set_zoom(100.0)
	assert(is_equal_approx(battle_site.camera.zoom.x, BattleSiteMap.MAX_ZOOM))
	battle_site._set_zoom(0.001)
	assert(is_equal_approx(battle_site.camera.zoom.x, BattleSiteMap.MIN_ZOOM))
	assert(str(battle_site.get_debug_state()["instruction"]).find("0.5x-16x") >= 0)
	var camera_before_drag: Vector2 = battle_site.camera.position
	var drag_press: InputEventMouseButton = InputEventMouseButton.new()
	drag_press.button_index = MOUSE_BUTTON_LEFT
	drag_press.pressed = true
	drag_press.position = Vector2(500.0, 500.0)
	battle_site._unhandled_input(drag_press)
	var drag_motion: InputEventMouseMotion = InputEventMouseMotion.new()
	drag_motion.position = Vector2(560.0, 500.0)
	drag_motion.relative = Vector2(60.0, 0.0)
	battle_site._unhandled_input(drag_motion)
	var drag_release: InputEventMouseButton = InputEventMouseButton.new()
	drag_release.button_index = MOUSE_BUTTON_LEFT
	drag_release.pressed = false
	drag_release.position = Vector2(560.0, 500.0)
	battle_site._unhandled_input(drag_release)
	assert(battle_site.camera.position.x < camera_before_drag.x, "Left drag did not pan the Battle camera")
	assert(battle_site.selected_formation_id == selected_attacker.formation_id,
		"Camera drag changed Formation selection")
	var escape_key: InputEventKey = InputEventKey.new()
	escape_key.keycode = KEY_ESCAPE
	escape_key.pressed = true
	navigation._unhandled_input(escape_key)
	await process_frame
	assert(navigation.get_current_layer() == NavigationController.MapLayer.REGION)
	assert(navigation.session.selected_world_cell == selected_world)
	assert(navigation.session.selected_region_cell == selected_local)
	var returned_map: RegionMap = navigation.get_current_map() as RegionMap
	returned_map._unhandled_input(battle_key)
	await process_frame
	var second_site: BattleSiteMap = navigation.get_current_map() as BattleSiteMap
	assert(second_site.snapshot.context.battle_id == first_battle_id)
	assert(second_site.snapshot.terrain_hash == first_terrain_hash)
	assert(second_site.snapshot.preview_hash == first_preview_hash)
	navigation._unhandled_input(escape_key)
	await process_frame
	map_root.queue_free()
	navigation.queue_free()
	await process_frame

func _test_formation_visual_contract() -> void:
	assert(BattleFormationData.DEFAULT_PERSONNEL == 100)
	assert(BattleRules.PERSONNEL_PER_FORMATION_MARKER == 100)
	assert(BattleRules.FORMATIONS_PER_RANK == 5)
	var deployment_zone: Rect2 = BattleRules.deployment_zone(
		Vector2(300.0, 300.0),
		BattleSiteContext.EntryDirection.SOUTH
	)
	var positions: Array[Vector2] = BattleRules.formation_marker_positions(
		deployment_zone,
		BattleSiteContext.EntryDirection.SOUTH,
		10
	)
	assert(positions.size() == 10)
	assert(positions[0].y != positions[5].y and positions[0].x == positions[5].x)
	var formation: BattleFormationData = BattleFormationData.new(
		"visual_test",
		BattleFormationData.Side.ATTACKER,
		100,
		Vector2(100.0, 100.0)
	)
	formation.facing_direction = Vector2.UP
	var full_size: Vector2 = BattleFormationData.formation_size_for_personnel(100)
	assert(is_equal_approx(formation.width_m, full_size.x))
	assert(is_equal_approx(formation.depth_m, full_size.y))
	var partial_size: Vector2 = BattleFormationData.formation_size_for_personnel(37)
	assert(is_equal_approx(partial_size.x, full_size.x) and partial_size.y < full_size.y)
	var small_size: Vector2 = BattleFormationData.formation_size_for_personnel(7)
	assert(small_size.x < full_size.x and small_size.y < full_size.y)
	assert(BattleSiteMap._formation_world_position(formation, Vector2(0.0, 4.0)) == Vector2(100.0, 96.0))
	assert(BattleSiteMap._formation_world_position(formation, Vector2(1.0, 0.0)) == Vector2(99.0, 100.0))
	var first_slot: Vector2 = BattleSiteMap._formation_slot_local(0, 100, full_size.x, full_size.y)
	assert(is_equal_approx(first_slot.x, -16.15))
	assert(is_equal_approx(first_slot.y, 6.40))
	var second_slot: Vector2 = BattleSiteMap._formation_slot_local(1, 100, full_size.x, full_size.y)
	var next_row_slot: Vector2 = BattleSiteMap._formation_slot_local(20, 100, full_size.x, full_size.y)
	assert(is_equal_approx(second_slot.x - first_slot.x, 1.70))
	assert(is_equal_approx(first_slot.y - next_row_slot.y, 3.20))

func _test_max_personnel_visual() -> void:
	var world_data: FastWorldData = FastWorldData.new()
	var center: Vector2i = _find_plain_or_forest_center(world_data)
	assert(center != INVALID_CELL, "No maximum-personnel test center found")
	var session: GameSession = _test_session(center)
	var runtime: BattlePreviewRuntime = _runtime_for(world_data, session)
	var preview: BattleSiteSnapshot = runtime.query_preview(
		center,
		BattleParticipantData.new("max_attacker", "Max Army A", 4_500),
		BattleParticipantData.new("max_defender", "Max Army B", 4_500),
		BattleSiteContext.EntryDirection.SOUTH,
		BattleSiteContext.EntryDirection.NORTH
	)
	assert(preview.has_preview())
	var begin: BattleRuntimeResult = runtime.begin_battle(preview)
	assert(begin.success and begin.snapshot != null)
	var battle_site: BattleSiteMap = load("res://scenes/site/BattleSite.tscn").instantiate() as BattleSiteMap
	get_root().add_child(battle_site)
	await process_frame
	battle_site.setup(begin.snapshot)
	await process_frame
	assert(battle_site.soldier_multimesh.instance_count == 9_000)
	assert(battle_site.soldier_multimesh.visible_instance_count == 9_000)
	assert(battle_site.soldier_instances.texture != null, "Person dot texture is missing")
	var active_personnel: int = 0
	var active_visual_instances: int = 0
	for formation: BattleFormationData in battle_site.active_formations:
		active_personnel += formation.personnel_count
		var range_value: Dictionary = battle_site.formation_instance_ranges[formation.formation_id]
		active_visual_instances += int(range_value["count"])
	assert(active_visual_instances == active_personnel,
		"Formation personnel is not mapped one-dot-per-person")
	assert(battle_site.get_debug_state()["person_visual"] == "1 rectangle per person (1.20m x 2.40m)")
	assert(_descendant_count(battle_site) < 30)
	assert(not _has_soldier_nodes(battle_site))
	battle_site.queue_free()
	runtime.leave_battle()
	await process_frame

func _runtime_for(world_data: WorldData, session: GameSession) -> BattlePreviewRuntime:
	var region_runtime: RegionRuntime = RegionRuntime.new(session, world_data)
	return BattlePreviewRuntime.new(session, world_data, region_runtime)

func _test_session(center: Vector2i) -> GameSession:
	var session: GameSession = GameSession.new()
	session.world_seed = TEST_SEED
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(center)
	session.selected_world_cell = converted["world_cell"] as Vector2i
	session.selected_region_cell = converted["region_cell"] as Vector2i
	session.party.set_global_region_cell(center)
	session.party.initialized = true
	return session

func _test_context(center: Vector2i) -> BattleSiteContext:
	return BattleSiteContext.create(
		TEST_SEED,
		center,
		BattleParticipantData.new("test_attacker", "Army A", 1000),
		BattleParticipantData.new("test_defender", "Army B", 800),
		BattleSiteContext.EntryDirection.SOUTH,
		BattleSiteContext.EntryDirection.NORTH,
		0,
		GameSession.INITIAL_WORLD_TIME_SECONDS
	)

func _test_road_overlay() -> RegionRoadOverlay:
	var overlay: RegionRoadOverlay = RegionRoadOverlay.new()
	var route: WorldRoadRoute = WorldRoadRoute.new(
		"road_battle_projection_test",
		"test_west",
		"test_east",
		EXAMPLE_CENTER + Vector2i.LEFT,
		EXAMPLE_CENTER + Vector2i.RIGHT
	)
	route.path = [EXAMPLE_CENTER + Vector2i.LEFT, EXAMPLE_CENTER, EXAMPLE_CENTER + Vector2i.RIGHT]
	route.path_generated = true
	for global_cell: Vector2i in route.path:
		var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(global_cell)
		overlay.add_route_cell(converted["region_cell"] as Vector2i, RegionRoadOverlay.ROAD, route)
	return overlay

func _find_passable_border_center(world_data: WorldData) -> Vector2i:
	for y: int in range(1, 99):
		var global_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(TEST_WORLD_CELL, Vector2i(99, y))
		if _base_cell_passable(world_data, global_cell):
			return global_cell
	return INVALID_CELL

func _find_terrain_boundary(world_data: WorldData) -> Vector2i:
	for y: int in range(401, 499):
		for x: int in range(301, 399):
			var center: Vector2i = Vector2i(x, y)
			if not _base_cell_passable(world_data, center):
				continue
			var terrain_types: Dictionary = {}
			for global_cell: Vector2i in BattleSiteGenerator.footprint_global_cells(center):
				terrain_types[_base_terrain(world_data, global_cell)] = true
			if terrain_types.size() >= 2:
				return center
	return INVALID_CELL

func _find_passable_center_near_river(world_data: WorldData) -> Vector2i:
	for y: int in range(401, 499):
		for x: int in range(301, 399):
			var center: Vector2i = Vector2i(x, y)
			if not _base_cell_passable(world_data, center):
				continue
			for global_cell: Vector2i in BattleSiteGenerator.footprint_global_cells(center):
				if world_data.terrain_generator.macro_sampler.is_river(TEST_SEED, global_cell):
					return center
	return INVALID_CELL

func _find_plain_or_forest_center(world_data: WorldData) -> Vector2i:
	for y: int in range(401, 499):
		for x: int in range(301, 399):
			var center: Vector2i = Vector2i(x, y)
			var terrain: int = _base_terrain(world_data, center)
			if (terrain == TerrainType.PLAINS or terrain == TerrainType.FOREST) \
					and _base_cell_passable(world_data, center):
				return center
	return INVALID_CELL

func _find_passable_local(world_data: WorldData) -> Vector2i:
	for radius: int in range(50):
		for y: int in range(50 - radius, 50 + radius + 1):
			for x: int in range(50 - radius, 50 + radius + 1):
				if maxi(absi(x - 50), absi(y - 50)) != radius:
					continue
				var local_cell: Vector2i = Vector2i(x, y)
				if not WorldCoordinates.is_valid_region_cell(local_cell):
					continue
				var global_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(TEST_WORLD_CELL, local_cell)
				var sample: Vector3 = world_data.terrain_generator.macro_sampler.sample(TEST_SEED, global_cell)
				if world_data.terrain_generator.classify_sample(sample) == TerrainType.FOREST \
						and sample.z <= 0.0:
					return local_cell
	return Vector2i(-1, -1)

func _base_cell_passable(world_data: WorldData, global_cell: Vector2i) -> bool:
	var sample: Vector3 = world_data.terrain_generator.macro_sampler.sample(TEST_SEED, global_cell)
	return TravelCostConfig.is_passable(
		world_data.terrain_generator.classify_sample(sample),
		sample.z > 0.0,
		false
	)

func _base_terrain(world_data: WorldData, global_cell: Vector2i) -> int:
	return world_data.terrain_generator.classify_sample(
		world_data.terrain_generator.macro_sampler.sample(TEST_SEED, global_cell)
	)

func _descendant_count(node: Node) -> int:
	var count: int = 0
	for child: Node in node.get_children():
		count += 1 + _descendant_count(child)
	return count

func _has_soldier_nodes(node: Node) -> bool:
	for child: Node in node.get_children():
		if child is CharacterBody2D or child is NavigationAgent2D or _has_soldier_nodes(child):
			return true
	return false
