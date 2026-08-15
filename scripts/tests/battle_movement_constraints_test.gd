extends SceneTree

const BattlePreviewRuntimeType = preload("res://scripts/runtime/battle_preview_runtime.gd")
const BattleRuntimeStateType = preload("res://scripts/runtime/battle_runtime_state.gd")
const BattleSiteSnapshotType = preload("res://scripts/runtime/battle_site_snapshot.gd")
const SiteTransitionDataType = preload("res://scripts/data/site_transition_data.gd")

const TEST_SEED: int = 987654321

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("Battle movement constraints: start")
	var session: GameSession = GameSession.new()
	session.world_seed = TEST_SEED
	var runtime: BattlePreviewRuntime = BattlePreviewRuntimeType.new(
		session,
		null,
		null
	)

	print("Battle movement constraints: runtime bound")
	_test_contact_and_march(runtime, session)
	print("Battle movement constraints: contact and march pass")
	_test_friendly_repath(runtime, session)
	print("Battle movement constraints: friendly repath pass")
	_test_obstacle_and_height_edges(runtime, session)
	print("Battle movement constraints: obstacle and height pass")
	print("Battle movement constraints passed: contact, marching, obstacle and height edges")
	quit()

func _test_contact_and_march(
		runtime: BattlePreviewRuntime,
	session: GameSession
	) -> void:
	print("Battle movement constraints: contact setup")
	var state: BattleRuntimeState = _activate(runtime, session)
	var attacker_id: String = str(state.commander_formation_ids[BattleFormationData.Side.ATTACKER])
	var defender_id: String = str(state.commander_formation_ids[BattleFormationData.Side.DEFENDER])
	var attacker: BattleFormationData = state.find_formation(attacker_id)
	var defender: BattleFormationData = state.find_formation(defender_id)
	assert(attacker != null and defender != null, "Both commander formations must exist")
	attacker.battle_position_m = Vector2(150.0, 90.0)
	defender.battle_position_m = Vector2(150.0, 210.0)
	attacker.clear_path()
	defender.clear_path()
	var attacker_start: Vector2 = attacker.battle_position_m
	var defender_start: Vector2 = defender.battle_position_m
	var attacker_order: BattleRuntimeResult = runtime.issue_fine_order(
		session.party.party_id,
		attacker_id,
		BattleOrderData.FineIntent.FOCUS_TARGET,
		Vector2.ZERO,
		Vector2.DOWN,
		defender_id
	)
	var defender_order: BattleRuntimeResult = runtime.issue_fine_order(
		"defender",
		defender_id,
		BattleOrderData.FineIntent.FOCUS_TARGET,
		Vector2.ZERO,
		Vector2.UP,
		attacker_id
	)
	assert(attacker_order.success and attacker_order.path.size() > 1,
		"Attacker order must create a march path")
	assert(defender_order.success and defender_order.path.size() > 1,
		"Defender order must create a march path")
	print("Battle movement constraints: both orders created")
	for _step: int in range(240):
		runtime.advance_battle(1.0)
		if attacker.autonomy_state == BattleFormationData.AutonomyState.ENGAGED \
				and defender.autonomy_state == BattleFormationData.AutonomyState.ENGAGED:
			break
	assert(attacker.battle_position_m != attacker_start and defender.battle_position_m != defender_start,
		"Both formations must march along their paths")
	assert(attacker.autonomy_state == BattleFormationData.AutonomyState.ENGAGED \
			and defender.autonomy_state == BattleFormationData.AutonomyState.ENGAGED,
		"Opposing formations did not enter mutual contact")
	runtime.leave_battle()

func _test_friendly_repath(
	runtime: BattlePreviewRuntime,
	session: GameSession
	) -> void:
	var state: BattleRuntimeState = _activate(runtime, session)
	var attacker_id: String = str(state.commander_formation_ids[BattleFormationData.Side.ATTACKER])
	var attacker: BattleFormationData = state.find_formation(attacker_id)
	var friendly: BattleFormationData = BattleFormationData.new(
		"friendly_blocker",
		BattleFormationData.Side.ATTACKER,
		100,
		Vector2(150.0, 150.0)
	)
	state.add_formation(friendly)
	attacker.battle_position_m = Vector2(70.0, 150.0)
	attacker.clear_path()
	var order: BattleRuntimeResult = runtime.issue_move(
		attacker_id,
		Vector2(230.0, 150.0)
	)
	assert(order.success and order.path.size() > 1, "Friendly-blocked march must start")
	runtime.advance_battle(20.0)
	var left_direct_row: bool = not is_equal_approx(attacker.battle_position_m.y, 150.0)
	for value: Variant in attacker.path:
		if value is Vector2i and (value as Vector2i).y != 75:
			left_direct_row = true
			break
	assert(left_direct_row, "Formation did not re-route around a friendly blocker")
	assert(attacker.battle_position_m.distance_to(friendly.battle_position_m) \
			>= minf(attacker.width_m, attacker.depth_m) - 0.001,
		"Formation overlapped its friendly blocker")
	runtime.leave_battle()

func _test_obstacle_and_height_edges(
	runtime: BattlePreviewRuntime,
	session: GameSession
	) -> void:
	var state: BattleRuntimeState = _activate(runtime, session)
	var center: SiteLayoutData = state.base_snapshot.site_layouts[0]
	for y: int in range(20, 31):
		var wall_cell: Vector2i = Vector2i(25, y)
		var wall_index: int = wall_cell.y * SiteLayoutData.GRID_SIZE.x + wall_cell.x
		center.navigation_flags[wall_index] = int(center.navigation_flags[wall_index]) \
			| SiteLayoutData.NAV_BLOCKED
	runtime._build_clearance_mask(state)
	var detour: Dictionary = runtime._find_path(
		Vector2i(10, 25),
		Vector2i(40, 25),
		Callable(runtime, "_battle_step_cost")
	)
	var detour_path: Array = detour.get("path", []) as Array
	assert(detour_path.size() > 1, "A* should route around a blocking wall")
	for value: Variant in detour_path:
		if value is Vector2i:
			var cell: Vector2i = value as Vector2i
			assert(cell.x != 25 or cell.y < 20 or cell.y > 30,
				"A* crossed the blocked wall instead of detouring")

	var low: Vector2i = Vector2i(10, 20)
	var high: Vector2i = Vector2i(11, 20)
	var low_index: int = low.y * SiteLayoutData.GRID_SIZE.x + low.x
	var high_index: int = high.y * SiteLayoutData.GRID_SIZE.x + high.x
	center.elevation_levels[high_index] = 1
	center.surface_flags[low_index] = SiteLayoutData.SURFACE_PLATFORM
	center.surface_flags[high_index] = SiteLayoutData.SURFACE_PLATFORM
	var blocked_step: float = runtime._battle_step_cost(
		low,
		high,
		Vector2i.RIGHT,
		runtime._battle_cell_info(low),
		runtime._battle_cell_info(high)
	)
	assert(not is_finite(blocked_step), "Height change without a stair must be blocked")
	center.surface_flags[low_index] = int(center.surface_flags[low_index]) \
		| SiteLayoutData.SURFACE_STAIR
	center.surface_flags[high_index] = int(center.surface_flags[high_index]) \
		| SiteLayoutData.SURFACE_STAIR
	center.transitions.append(SiteTransitionDataType.new(
		low,
		high,
		0,
		1,
		SiteTransitionData.Kind.STAIR
	))
	var stair_step: float = runtime._battle_step_cost(
		low,
		high,
		Vector2i.RIGHT,
		runtime._battle_cell_info(low),
		runtime._battle_cell_info(high)
	)
	assert(is_finite(stair_step), "A generated stair must allow the height change")
	runtime.leave_battle()

func _activate(
	runtime: BattlePreviewRuntime,
	session: GameSession
	) -> BattleRuntimeState:
	var snapshot: BattleSiteSnapshot = _flat_snapshot()
	var state: BattleRuntimeState = BattleRuntimeStateType.new(snapshot)
	runtime._build_clearance_mask(state)
	assert(runtime._create_formations(state), "Flat test battle must create both sides")
	assert(session.set_active_battle_state(state), "Test battle state was not accepted")
	return state

func _flat_snapshot() -> BattleSiteSnapshot:
	var snapshot: BattleSiteSnapshot = BattleSiteSnapshotType.new()
	snapshot.context = BattleSiteContext.create(
		TEST_SEED,
		Vector2i(100, 100),
		BattleParticipantData.new(
			"attacker",
			"Attacker",
			100,
			"party_1",
			BattleParticipantData.CommanderKind.PLAYER
		),
		BattleParticipantData.new("defender", "Defender", 100),
		BattleSiteContext.EntryDirection.SOUTH,
		BattleSiteContext.EntryDirection.NORTH
	)
	snapshot.size_meters = Vector2(300.0, 300.0)
	snapshot.bounds_meters = Rect2(Vector2.ZERO, snapshot.size_meters)
	snapshot.center_terrain = TerrainType.PLAINS
	snapshot.center_cell = {"terrain_type": TerrainType.PLAINS}
	snapshot.attacker_deployment = BattleRules.deployment_preview(
		snapshot.context.attacker,
		TerrainType.PLAINS,
		snapshot.size_meters,
		BattleSiteContext.EntryDirection.SOUTH
	)
	snapshot.defender_deployment = BattleRules.deployment_preview(
		snapshot.context.defender,
		TerrainType.PLAINS,
		snapshot.size_meters,
		BattleSiteContext.EntryDirection.NORTH
	)
	for index: int in range(9):
		snapshot.site_layouts.append(_flat_layout(index))
		snapshot.footprint_cells.append({})
	snapshot.terrain_debug_representation = "flat"
	snapshot.terrain_hash = "flat"
	snapshot.preview_hash = "flat"
	snapshot.success = true
	return snapshot

func _flat_layout(index: int) -> SiteLayoutData:
	var layout: SiteLayoutData = SiteLayoutData.new()
	layout.site_id = "flat_%d" % index
	layout.layout_kind = SiteLayoutData.LayoutKind.CELL_BASE
	layout.generation_version = 1
	layout.site_seed = TEST_SEED + index
	layout.global_region_cell = Vector2i(index % 3, floori(float(index) / 3.0))
	layout.bounds_meters = Rect2i(-50, -50, 100, 100)
	layout.terrain_type = TerrainType.PLAINS
	layout.native_surface_cells.resize(SiteLayoutData.NAVIGATION_CELL_COUNT)
	layout.native_surface_cells.fill(SiteContentTypes.NativeSurface.DIRT)
	layout.navigation_flags.resize(SiteLayoutData.NAVIGATION_CELL_COUNT)
	layout.navigation_flags.fill(0)
	layout.visual_cells.resize(SiteLayoutData.NAVIGATION_CELL_COUNT)
	layout.visual_cells.fill(0)
	layout.elevation_levels.resize(SiteLayoutData.NAVIGATION_CELL_COUNT)
	layout.elevation_levels.fill(0)
	layout.surface_flags.resize(SiteLayoutData.NAVIGATION_CELL_COUNT)
	layout.surface_flags.fill(0)
	layout.height_edge_flags.resize(SiteLayoutData.NAVIGATION_CELL_COUNT)
	layout.height_edge_flags.fill(0)
	return layout
