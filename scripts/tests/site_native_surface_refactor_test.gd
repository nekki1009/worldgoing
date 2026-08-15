extends SceneTree

const TEST_SEED: int = 123456789

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_world_overview_budget_and_lazy_regions()
	_test_world_startup_is_overview_only()
	_test_manifest_edges_are_shared()
	_test_region_resource_conservation()
	_test_native_surface_and_resource_placements()
	_test_site_habitat_rules()
	_test_facility_delta_changes_navigation()
	_test_stair_removal_restores_height_block()
	_test_minimum_building_footprint_and_door()
	_test_runtime_resource_and_player_facility_delta()
	print("Site native surface refactor tests passed: 10 cases")
	quit()

func _test_world_overview_budget_and_lazy_regions() -> void:
	var world: WorldData = WorldData.new()
	var overview: WorldOverviewData = world.get_or_generate_world_overview(TEST_SEED)
	assert(overview != null and overview.is_valid(), "World Overview is invalid")
	assert(world.regions.is_empty(), "World Overview eagerly allocated RegionData")
	assert(overview.payload_bytes() <= 4 * 1024 * 1024, "World Overview exceeded 4 MiB")
	assert(overview.generation_milliseconds <= 1000.0, "World Overview exceeded 1 second")
	var signature: int = overview.signature()
	world.clear_generated_cache()
	var rebuilt: WorldOverviewData = world.get_or_generate_world_overview(TEST_SEED)
	assert(rebuilt.signature() == signature, "World Overview changed after cache clear")
	print(
		"P1 TEST PASS: packed Overview is deterministic, bounded, and Region-lazy " \
			+ "(payload=%d bytes generation=%.2f ms)" % [
				overview.payload_bytes(),
				overview.generation_milliseconds,
			]
	)

func _test_world_startup_is_overview_only() -> void:
	var host: Node2D = Node2D.new()
	var map_root: Node2D = Node2D.new()
	var navigation: NavigationController = NavigationController.new()
	host.add_child(map_root)
	host.add_child(navigation)
	get_root().add_child(host)
	navigation.setup(map_root)
	navigation.start()
	assert(navigation.world_data.world_overview != null, "World startup did not build Overview")
	assert(navigation.world_data.regions.is_empty(), "World startup generated RegionData before Region entry")
	host.free()
	print("P1 TEST PASS: actual World startup allocates Overview and zero Regions")

func _test_manifest_edges_are_shared() -> void:
	var world: WorldData = WorldData.new()
	var left: RegionGenerationManifest = world.get_or_generate_region_manifest(Vector2i(3, 4), TEST_SEED)
	var right: RegionGenerationManifest = world.get_or_generate_region_manifest(Vector2i(4, 4), TEST_SEED)
	assert(left != null and right != null and left.is_valid() and right.is_valid(), "Manifest is invalid")
	assert(left.edge_contracts["east"] == right.edge_contracts["west"], "East/west edge contract drifted")
	var detached_endpoint: int = int(left.edge_contracts["east"]["endpoint"])
	left.edge_contracts["east"]["endpoint"] = -1
	var refreshed: RegionGenerationManifest = world.get_or_generate_region_manifest(Vector2i(3, 4), TEST_SEED)
	assert(int(refreshed.edge_contracts["east"]["endpoint"]) == detached_endpoint, "Manifest cache leaked a mutable query")
	print("P1 TEST PASS: adjacent Manifest edges are shared and detached")

func _test_region_resource_conservation() -> void:
	var world: WorldData = WorldData.new()
	var world_cell: Vector2i = _first_land_region(world)
	var manifest: RegionGenerationManifest = world.get_or_generate_region_manifest(world_cell, TEST_SEED)
	var content: RegionSiteContentData = world.get_or_generate_region_site_content(world_cell, TEST_SEED)
	assert(content != null and content.is_valid(), "Region Site content is invalid")
	assert(content.payload_bytes() < 512 * 1024, "Region Site content is not compact")
	for resource_type: int in range(SiteContentTypes.RESOURCE_COUNT):
		assert(
			content.resource_total(resource_type) == manifest.resource_budgets[resource_type],
			"Region resource budget was not conserved for %s" % SiteContentTypes.resource_name(resource_type)
		)
	assert(GameSession.new().site_runtime_states.is_empty(), "Generated Region content allocated Site Runtime")
	print(
		"P2 TEST PASS: packed Region profiles conserve all seven resource budgets " \
			+ "(payload=%d bytes)" % content.payload_bytes()
	)

func _test_native_surface_and_resource_placements() -> void:
	var world: WorldData = WorldData.new()
	var world_cell: Vector2i = _first_land_region(world)
	var content: RegionSiteContentData = world.get_or_generate_region_site_content(world_cell, TEST_SEED)
	var region_cell: Vector2i = _richest_resource_cell(content)
	var definition: SiteData = world.get_site_definition_at(world_cell, region_cell, TEST_SEED)
	var layout: SiteLayoutData = world.get_site_layout(definition)
	assert(layout != null and layout.is_valid() and layout.has_native_surface_base(), "Site native surface base is invalid")
	for native_surface: int in layout.native_surface_cells:
		assert(
			native_surface >= SiteContentTypes.NativeSurface.DIRT \
				and native_surface < SiteContentTypes.NativeSurface.COUNT,
			"Site contains an invalid native surface"
		)
	var amounts: PackedInt32Array = definition.resource_amounts
	for resource_type: int in range(SiteContentTypes.RESOURCE_COUNT):
		var placed: int = 0
		for placement: Dictionary in layout.resource_placements:
			if int(placement.get("type", -1)) == resource_type:
				placed += int(placement.get("quantity", 0))
		assert(
			placed + int(layout.details.get("resource_unplaced_%d" % resource_type, 0)) == amounts[resource_type],
			"Site resource placement changed the Profile amount"
		)
	var expected_surfaces: Dictionary = {
		TerrainType.PLAINS: SiteContentTypes.NativeSurface.DIRT,
		TerrainType.MOUNTAIN: SiteContentTypes.NativeSurface.ROCK,
		TerrainType.WATER: SiteContentTypes.NativeSurface.RIVER_WATER,
		TerrainType.OCEAN: SiteContentTypes.NativeSurface.SEA_WATER,
	}
	var fixture_index: int = 0
	for terrain_type: int in expected_surfaces:
		var expected_surface: int = int(expected_surfaces[terrain_type])
		var surface_layout: SiteLayoutData = SiteLayoutGenerator.generate_cell_base(TEST_SEED, {
			"global_region_cell": Vector2i(700 + fixture_index, 700),
			"terrain_type": terrain_type,
			"site_landform": SiteLayoutData.Landform.NONE,
			"travel_exit_mask": SiteLayoutData.EXIT_ALL,
			"elevation": 0.5,
			"moisture": 0.5,
			"river_strength": 1.0 if terrain_type == TerrainType.WATER else 0.0,
			"river": terrain_type == TerrainType.WATER,
			"native_surface_hint": expected_surface,
			"rock_ratio": 1.0 if terrain_type == TerrainType.MOUNTAIN else 0.0,
			"resource_amounts": PackedInt32Array([0, 0, 0, 0, 0, 0, 0]),
		})
		assert(surface_layout != null and surface_layout.is_valid(), "Native surface fixture is invalid")
		var matching_cells: int = 0
		for native_surface: int in surface_layout.native_surface_cells:
			if native_surface == expected_surface:
				matching_cells += 1
		assert(
			matching_cells >= SiteLayoutData.NAVIGATION_CELL_COUNT - 1,
			"Native surface fixture did not generate %s" % expected_surface
		)
		fixture_index += 1
	print("P3/P4 TEST PASS: four native surfaces and stable resource placements preserve Profile totals")

func _test_site_habitat_rules() -> void:
	var sand: SiteLayoutData = SiteLayoutGenerator.generate_cell_base(TEST_SEED, {
		"global_region_cell": Vector2i(810, 700),
		"terrain_type": TerrainType.SAND,
		"site_landform": SiteLayoutData.Landform.NONE,
		"travel_exit_mask": SiteLayoutData.EXIT_ALL,
		"elevation": 0.2,
		"moisture": 0.15,
		"native_surface_hint": SiteContentTypes.NativeSurface.DIRT,
		"rock_ratio": 0.0,
		"resource_amounts": PackedInt32Array([0, 12, 12, 0, 0, 0, 0]),
	})
	assert(sand != null and sand.is_valid(), "Sand habitat fixture is invalid")
	assert(sand.resource_placements.is_empty(), "Fruit/forest resources leaked onto Sand")
	assert(int(sand.details.get("resource_unplaced_1", 0)) == 12, "Sand fruit budget was not deferred")
	assert(int(sand.details.get("resource_unplaced_2", 0)) == 12, "Sand forest budget was not deferred")

	var forest: SiteLayoutData = SiteLayoutGenerator.generate_cell_base(TEST_SEED, {
		"global_region_cell": Vector2i(811, 700),
		"terrain_type": TerrainType.FOREST,
		"site_landform": SiteLayoutData.Landform.NONE,
		"travel_exit_mask": SiteLayoutData.EXIT_ALL,
		"elevation": 0.35,
		"moisture": 0.75,
		"native_surface_hint": SiteContentTypes.NativeSurface.DIRT,
		"rock_ratio": 0.0,
		"resource_amounts": PackedInt32Array([0, 0, 12, 0, 0, 0, 0]),
	})
	assert(forest != null and forest.is_valid(), "Forest habitat fixture is invalid")
	assert(not forest.resource_placements.is_empty(), "Forest resource did not find a valid cluster")
	for placement: Dictionary in forest.resource_placements:
		assert(
			int(placement.get("type", -1)) == SiteContentTypes.RESOURCE_FOREST,
			"Forest fixture placed an unrelated resource"
		)

	var ocean: SiteLayoutData = SiteLayoutGenerator.generate_cell_base(TEST_SEED, {
		"global_region_cell": Vector2i(812, 700),
		"terrain_type": TerrainType.OCEAN,
		"site_landform": SiteLayoutData.Landform.NONE,
		"travel_exit_mask": SiteLayoutData.EXIT_ALL,
		"elevation": 0.0,
		"moisture": 1.0,
		"native_surface_hint": SiteContentTypes.NativeSurface.SEA_WATER,
		"rock_ratio": 0.0,
		"resource_amounts": PackedInt32Array([12, 2, 2, 2, 2, 2, 2]),
	})
	assert(ocean != null and ocean.is_valid(), "Ocean habitat fixture is invalid")
	assert(ocean.resource_placements.is_empty(), "Land resources leaked onto Ocean")
	print("P4 TEST PASS: terrain habitat hard limits and deterministic cluster priorities agree")

func _test_facility_delta_changes_navigation() -> void:
	var fixture: Dictionary = {
		"global_region_cell": Vector2i(350, 450),
		"terrain_type": TerrainType.PLAINS,
		"site_landform": SiteLayoutData.Landform.NONE,
		"travel_exit_mask": SiteLayoutData.EXIT_ALL,
		"elevation": 0.4,
		"moisture": 0.5,
		"river_strength": 0.8,
		"river": true,
		"river_crossing": true,
		"road": true,
		"road_connection_offsets": [Vector2i.LEFT, Vector2i.RIGHT],
		"river_connection_offsets": [Vector2i.UP, Vector2i.DOWN],
		"native_surface_hint": SiteContentTypes.NativeSurface.DIRT,
		"resource_amounts": PackedInt32Array([20, 2, 8, 0, 0, 0, 0]),
	}
	var layout: SiteLayoutData = SiteLayoutGenerator.generate_cell_base(TEST_SEED, fixture)
	assert(layout != null and not layout.facility_placements.is_empty(), "Bridge facility was not generated")
	var bridge: Dictionary = {}
	for facility: Dictionary in layout.facility_placements:
		if int(facility.get("type", -1)) == SiteContentTypes.Facility.BRIDGE:
			bridge = facility
			break
	assert(not bridge.is_empty(), "Bridge placement is missing")
	var bridge_id: String = str(bridge["id"])
	var removed: SiteLayoutData = layout.resolved_without([bridge_id])
	var origin: Vector2i = bridge["origin"] as Vector2i
	assert(
		SiteContentTypes.is_water_surface(removed.native_surface_at(origin)) \
			and (removed.surface_flags_at(origin) & SiteLayoutData.SURFACE_BRIDGE) == 0 \
			and (removed.navigation_flags_at(origin) & SiteLayoutData.NAV_BLOCKED) != 0,
		"Removing the bridge did not restore blocked water"
	)
	var session: GameSession = GameSession.new()
	var definition: SiteData = SiteData.from_region_cell(TEST_SEED, Vector2i(3, 4), Vector2i(50, 50), fixture)
	var runtime_state: SiteRuntimeState = session.ensure_site_runtime_state(definition)
	assert(runtime_state != null and runtime_state.mark_generated_feature_removed(bridge_id) == SiteRuntimeFailureReason.Code.NONE, "Facility sparse Delta failed")
	assert(runtime_state.removed_feature_ids == [bridge_id], "Facility Delta stored more than the stable ID")
	print("P5 TEST PASS: bridge is cardinal placement and sparse removal restores blocked water")

func _test_stair_removal_restores_height_block() -> void:
	var definition: SiteData = SiteData.new(
		"p5_stair_removal",
		"P5 stair removal",
		WorldPOIType.CAVE,
		Vector2i(3, 4),
		Vector2i(50, 50),
		Vector2i(350, 450)
	)
	definition.site_seed = 975_310
	definition.source_terrain_type = TerrainType.MOUNTAIN
	definition.native_surface_hint = SiteContentTypes.NativeSurface.ROCK
	definition.rock_ratio = 0.82
	definition.resource_amounts = PackedInt32Array([0, 0, 0, 8, 0, 0, 0])
	var layout: SiteLayoutData = SiteLayoutGenerator.generate(definition)
	assert(layout != null and layout.is_valid(), "Stair removal fixture is invalid")
	var stair: Dictionary = {}
	for facility: Dictionary in layout.facility_placements:
		if int(facility.get("type", -1)) in [
			SiteContentTypes.Facility.WOOD_STAIR,
			SiteContentTypes.Facility.STONE_STAIR,
		]:
			stair = facility
			break
	assert(not stair.is_empty(), "Generated height fixture has no stair facility")
	var from_cell: Vector2i = stair.get("origin", SiteLayoutData.INVALID_CELL) as Vector2i
	var to_cell: Vector2i = stair.get("target", SiteLayoutData.INVALID_CELL) as Vector2i
	assert(
		layout.elevation_level_at(from_cell) != layout.elevation_level_at(to_cell)
			and layout.can_traverse(from_cell, to_cell),
		"Generated stair does not connect a traversable height change"
	)
	var removed: SiteLayoutData = layout.resolved_without([str(stair.get("id", ""))])
	assert(
		removed.transition_between(from_cell, to_cell) == null
			and not removed.can_traverse(from_cell, to_cell),
		"Removing a stair did not restore the blocked height edge"
	)
	print("P5 TEST PASS: sparse stair removal restores the blocked height edge")

func _test_minimum_building_footprint_and_door() -> void:
	var definition: SiteData = SiteData.new(
		"p5_minimum_building",
		"P5 minimum building",
		WorldPOIType.VILLAGE,
		Vector2i(3, 4),
		Vector2i(51, 50),
		Vector2i(351, 450)
	)
	definition.site_seed = 975_311
	definition.source_terrain_type = TerrainType.PLAINS
	definition.native_surface_hint = SiteContentTypes.NativeSurface.DIRT
	definition.resource_amounts = PackedInt32Array([12, 0, 0, 0, 0, 0, 0])
	var layout: SiteLayoutData = SiteLayoutGenerator.generate(definition)
	assert(layout != null and layout.is_valid(), "Minimum building fixture is invalid")
	var building: Dictionary = {}
	for facility: Dictionary in layout.facility_placements:
		if int(facility.get("type", -1)) == SiteContentTypes.Facility.BUILDING:
			building = facility
			break
	assert(not building.is_empty(), "Village did not generate a minimum building")
	var origin: Vector2i = building.get("origin", SiteLayoutData.INVALID_CELL) as Vector2i
	var size: Vector2i = building.get("size", Vector2i.ZERO) as Vector2i
	assert(
		size == Vector2i(7, 5)
			and str(building.get("definition_id", "")) == "rectangular_wood_house",
		"Minimum building lost its 7x5 data-driven footprint"
	)
	var door_inside: Vector2i = Vector2i(origin.x + size.x / 2, origin.y + size.y - 1)
	var door_outside: Vector2i = door_inside + Vector2i.DOWN
	assert(
		layout.can_traverse(door_inside, door_outside),
		"Minimum building door is not a real traversable opening"
	)
	var blocked_wall_found: bool = false
	for x: int in range(origin.x, origin.x + size.x):
		if x == door_inside.x:
			continue
		var wall_inside: Vector2i = Vector2i(x, origin.y + size.y - 1)
		var wall_outside: Vector2i = wall_inside + Vector2i.DOWN
		if not layout.can_traverse(wall_inside, wall_outside):
			blocked_wall_found = true
			break
	assert(blocked_wall_found, "Minimum building perimeter does not block traversal")
	print("P5 TEST PASS: 7x5 building footprint, walls, and door agree")

func _test_runtime_resource_and_player_facility_delta() -> void:
	var world: WorldData = WorldData.new()
	var world_cell: Vector2i = _first_land_region(world)
	var content: RegionSiteContentData = world.get_or_generate_region_site_content(world_cell, TEST_SEED)
	var region_cell: Vector2i = _richest_resource_cell(content)
	var definition: SiteData = world.get_site_definition_at(world_cell, region_cell, TEST_SEED)
	var base_layout: SiteLayoutData = world.get_site_layout(definition)
	assert(definition != null and base_layout != null, "Runtime Delta fixture is invalid")
	var session: GameSession = GameSession.new()
	session.world_seed = TEST_SEED
	var runtime: TravelRuntime = TravelRuntime.new(session, world)
	if not base_layout.resource_placements.is_empty():
		var resource_id: String = str(base_layout.resource_placements[0].get("id", ""))
		var harvest: SiteRuntimeCommandResult = runtime.harvest_site_resource(definition.site_id, resource_id)
		assert(harvest.success, "Harvest command rejected a generated resource")
		assert(
			runtime.get_site_snapshot(definition.site_id).layout.generated_resource(resource_id).is_empty(),
			"Harvested resource remained in the resolved Site"
		)
	var pair: Array[Vector2i] = _open_equal_height_pair(base_layout)
	assert(pair.size() == 2 and base_layout.can_traverse(pair[0], pair[1]), "No wall test pair was found")
	var add_wall: SiteRuntimeCommandResult = runtime.add_site_facility(
		definition.site_id,
		"player:%s:wood_wall:0" % definition.site_id,
		SiteContentTypes.Facility.WOOD_WALL,
		pair[0],
		Vector2i.ONE,
		SiteContentTypes.Orientation.VERTICAL if pair[0].x != pair[1].x \
			else SiteContentTypes.Orientation.HORIZONTAL,
		pair[1]
	)
	assert(add_wall.success, "Player wall command failed")
	assert(
		not runtime.get_site_snapshot(definition.site_id).layout.can_traverse(pair[0], pair[1]),
		"Player wall did not block Site traversal"
	)
	var remove_wall: SiteRuntimeCommandResult = runtime.remove_site_facility(
		definition.site_id,
		"player:%s:wood_wall:0" % definition.site_id
	)
	assert(remove_wall.success, "Player wall removal failed")
	assert(
		runtime.get_site_snapshot(definition.site_id).layout.can_traverse(pair[0], pair[1]),
		"Removing the player wall did not restore traversal"
	)
	var state: SiteRuntimeState = session.find_site_runtime_state(definition.site_id)
	assert(state != null and state.added_features.is_empty(), "Removed player facility left non-sparse placement state")
	print("P4/P5 TEST PASS: harvest and player facility commands resolve through sparse Site Delta")

func _open_equal_height_pair(layout: SiteLayoutData) -> Array[Vector2i]:
	for y: int in range(1, SiteLayoutData.GRID_SIZE.y - 1):
		for x: int in range(1, SiteLayoutData.GRID_SIZE.x - 2):
			var left: Vector2i = Vector2i(x, y)
			var right: Vector2i = left + Vector2i.RIGHT
			if not SiteContentTypes.is_water_surface(layout.native_surface_at(left)) \
				and not SiteContentTypes.is_water_surface(layout.native_surface_at(right)) \
				and layout.elevation_level_at(left) == layout.elevation_level_at(right) \
				and layout.can_traverse(left, right):
				return [left, right]
	return []

func _richest_resource_cell(content: RegionSiteContentData) -> Vector2i:
	var best: Vector2i = Vector2i.ZERO
	var best_total: int = -1
	for y: int in range(WorldCoordinates.REGION_GRID_SIZE):
		for x: int in range(WorldCoordinates.REGION_GRID_SIZE):
			var cell: Vector2i = Vector2i(x, y)
			var profile: Dictionary = content.profile_at(cell)
			var amounts: PackedInt32Array = profile["resource_amounts"] as PackedInt32Array
			var total: int = 0
			for amount: int in amounts:
				total += amount
			if total > best_total:
				best_total = total
				best = cell
	return best

func _first_land_region(world: WorldData) -> Vector2i:
	var overview: WorldOverviewData = world.get_or_generate_world_overview(TEST_SEED)
	for y: int in range(WorldData.WORLD_CELLS.y):
		for x: int in range(WorldData.WORLD_CELLS.x):
			var cell: Vector2i = Vector2i(x, y)
			if not TerrainType.is_water_like(overview.biome_at(cell)):
				return cell
	return Vector2i.ZERO
