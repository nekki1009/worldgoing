extends SceneTree

const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")
const SiteLayoutGeneratorType = preload("res://scripts/core/site_layout_generator.gd")
const SiteTransitionDataType = preload("res://scripts/data/site_transition_data.gd")
const MapArtCatalogType = preload("res://scripts/data/map_art_catalog.gd")

class FixtureWorldData:
	extends WorldData

	var fixture: SiteData

	func get_site_definition_by_id(site_id: String, _world_seed: int) -> SiteData:
		return fixture if fixture != null and fixture.site_id == site_id else null

var fixture_world: FixtureWorldData = FixtureWorldData.new()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_height_generation_is_deterministic()
	_test_castle_walls_and_stairs()
	_test_mountain_pass_stairs_are_traversable()
	_test_bridge_and_water_rules()
	_test_runtime_site_path_uses_transitions()
	_test_detail_surface_contract()
	print("Site detailed scene tests passed: 6 cases")
	quit()

func _test_height_generation_is_deterministic() -> void:
	var definition: SiteData = _fixture(
		"detail_mountain",
		WorldPOIType.VILLAGE,
		TerrainType.MOUNTAIN
	)
	var first: SiteLayoutDataType = SiteLayoutGeneratorType.generate(definition)
	var second: SiteLayoutDataType = SiteLayoutGeneratorType.generate(definition)
	assert(first != null and second != null and first.is_valid(), "Mountain detail layout is invalid")
	assert(first.has_height_base(), "Mountain layout has no height base")
	assert(first.elevation_levels == second.elevation_levels, "Height generation is not deterministic")
	assert(first.surface_flags == second.surface_flags, "Surface generation is not deterministic")
	assert(first.height_edge_flags == second.height_edge_flags, "Height edge generation is not deterministic")
	assert(_transition_signature(first) == _transition_signature(second), "Transition generation is not deterministic")
	var minimum: int = 999
	var maximum: int = -999
	for level: int in first.elevation_levels:
		minimum = mini(minimum, level)
		maximum = maxi(maximum, level)
	assert(minimum == 0 and maximum >= 1, "Mountain sample did not produce visible 0/1-level height difference")
	assert(first.transitions.size() >= 2, "Mountain sample did not produce two boundary stairs")
	for transition: SiteTransitionData in first.transitions:
		assert(transition.height_delta() > 0, "Mountain sample contains a flat stair transition")
		assert(
			SiteLayoutDataType.is_valid_cell(transition.from_cell)
				and SiteLayoutDataType.is_valid_cell(transition.to_cell),
			"Transition escaped the 50x50 Site"
		)
		assert(
			absi(transition.from_cell.x - transition.to_cell.x) <= 1
				and absi(transition.from_cell.y - transition.to_cell.y) <= 1,
			"Transition endpoints are not adjacent"
		)
		assert(
			transition.from_level == first.elevation_level_at(transition.from_cell)
				and transition.to_level == first.elevation_level_at(transition.to_cell),
			"Transition level metadata drifted from the height base"
		)
		assert(
			first.can_traverse(transition.from_cell, transition.to_cell)
				and first.can_traverse(transition.to_cell, transition.from_cell),
			"Generated transition is not traversable in both directions"
		)
	var detached: SiteLayoutDataType = first.copy()
	detached.elevation_levels[0] = 99
	detached.transitions.clear()
	assert(first.elevation_levels[0] != 99 and not first.transitions.is_empty(), "Layout copy leaked height state")
	print("SITE DETAIL TEST 1 PASS: deterministic levels, edges, transitions, and detached copy")

func _test_castle_walls_and_stairs() -> void:
	var definition: SiteData = _fixture(
		"detail_castle",
		WorldPOIType.CASTLE,
		TerrainType.PLAINS
	)
	var layout: SiteLayoutDataType = SiteLayoutGeneratorType.generate(definition)
	assert(layout != null and layout.is_valid(), "Castle detail layout is invalid")
	var wall_found: bool = false
	for y: int in range(SiteLayoutDataType.GRID_SIZE.y):
		for x: int in range(SiteLayoutDataType.GRID_SIZE.x):
			var cell: Vector2i = Vector2i(x, y)
			if (layout.surface_flags_at(cell) & SiteLayoutDataType.SURFACE_WALL) != 0:
				wall_found = true
				assert(
					(layout.navigation_flags_at(cell) & SiteLayoutDataType.NAV_BLOCKED) != 0,
					"Castle wall cell is not blocked"
				)
				break
		if wall_found:
			break
	assert(wall_found, "Castle template did not produce a wall ring")
	var stair_found: bool = false
	for transition: SiteTransitionData in layout.transitions:
		if transition.kind != SiteTransitionDataType.Kind.STAIR or transition.height_delta() <= 0:
			continue
		stair_found = true
		assert(
			layout.can_traverse(transition.from_cell, transition.to_cell),
			"Castle stair cannot be entered"
		)
		break
	assert(stair_found, "Castle template did not produce a height-changing stair")
	print("SITE DETAIL TEST 2 PASS: castle wall blocking and courtyard stair transition")

func _test_mountain_pass_stairs_are_traversable() -> void:
	var definition: SiteData = _fixture(
		"detail_pass",
		WorldPOIType.VILLAGE,
		TerrainType.MOUNTAIN
	)
	definition.site_landform = SiteLayoutDataType.Landform.MOUNTAIN_PASS
	definition.travel_exit_mask = SiteLayoutDataType.EXIT_EAST | SiteLayoutDataType.EXIT_WEST
	var layout: SiteLayoutDataType = SiteLayoutGeneratorType.generate(definition)
	assert(layout != null and layout.is_valid(), "Mountain Pass detail layout is invalid")
	var stair: SiteTransitionData = null
	for transition: SiteTransitionData in layout.transitions:
		if transition.kind == SiteTransitionDataType.Kind.STAIR and transition.height_delta() > 0:
			stair = transition
			break
	assert(stair != null, "Mountain Pass did not produce a route stair")
	assert(
		layout.can_traverse(stair.from_cell, stair.to_cell)
			and layout.can_traverse(stair.to_cell, stair.from_cell),
		"Mountain Pass route stair is blocked by the passage mask"
	)
	print("SITE DETAIL TEST 3 PASS: mountain pass stairs connect the corridor and raised landing")

func _test_bridge_and_water_rules() -> void:
	var definition: SiteData = _fixture(
		"detail_bridge",
		WorldPOIType.VILLAGE,
		TerrainType.PLAINS,
		SiteLayoutDataType.LayoutKind.CELL_BASE
	)
	definition.source_road = true
	definition.source_river_nearby = true
	definition.source_river_crossing = true
	var layout: SiteLayoutDataType = SiteLayoutGeneratorType.generate(definition)
	assert(layout != null and layout.is_valid(), "Bridge detail layout is invalid")
	var bridge_found: bool = false
	var water_found: bool = false
	for y: int in range(SiteLayoutDataType.GRID_SIZE.y):
		for x: int in range(SiteLayoutDataType.GRID_SIZE.x):
			var cell: Vector2i = Vector2i(x, y)
			var surface: int = layout.surface_flags_at(cell)
			if (surface & SiteLayoutDataType.SURFACE_BRIDGE) != 0:
				bridge_found = true
				assert(
					(layout.navigation_flags_at(cell) & SiteLayoutDataType.NAV_BLOCKED) == 0,
					"Bridge cell is blocked"
				)
			if (surface & SiteLayoutDataType.SURFACE_WATER) != 0 \
				and (surface & SiteLayoutDataType.SURFACE_BRIDGE) == 0:
				water_found = true
				assert(
					(layout.navigation_flags_at(cell) & SiteLayoutDataType.NAV_BLOCKED) != 0,
					"Open water cell is traversable"
				)
	assert(bridge_found and water_found, "Bridge fixture did not produce both bridge and water cells")
	var bridge_transition_found: bool = false
	for transition: SiteTransitionData in layout.transitions:
		if transition.kind == SiteTransitionDataType.Kind.BRIDGE:
			bridge_transition_found = true
			assert(
				absi(transition.from_cell.x - transition.to_cell.x) <= 1
					and absi(transition.from_cell.y - transition.to_cell.y) <= 1,
				"Bridge transition endpoints are not adjacent"
			)
	assert(bridge_transition_found, "Bridge fixture has no bridge transition record")
	assert((layout.details.get("bridge_cells", []) as Array).size() >= 2, "Bridge footprint lost its width")
	print("SITE DETAIL TEST 4 PASS: bridge cells cross water while open water stays blocked")

func _test_runtime_site_path_uses_transitions() -> void:
	var definition: SiteData = _fixture(
		"detail_runtime",
		WorldPOIType.VILLAGE,
		TerrainType.MOUNTAIN
	)
	fixture_world.fixture = definition
	var session: GameSession = GameSession.new()
	var runtime: TravelRuntime = TravelRuntime.new(session, fixture_world)
	var layout: SiteLayoutDataType = fixture_world.get_site_layout(definition)
	var stair: SiteTransitionData = null
	for transition: SiteTransitionData in layout.transitions:
		if transition.kind == SiteTransitionDataType.Kind.STAIR and transition.height_delta() > 0:
			stair = transition
			break
	assert(stair != null, "Runtime fixture has no height-changing stair")
	var path: PartyPathResult = runtime.query_site_path(
		definition.site_id,
		stair.from_cell,
		stair.to_cell
	)
	assert(path.has_path(), "Runtime Site A* could not use a stair transition")
	assert(path.cells.front() == stair.from_cell and path.cells.back() == stair.to_cell, "Runtime Site path endpoints changed")
	for index: int in range(path.cells.size() - 1):
		assert(layout.can_traverse(path.cells[index], path.cells[index + 1]), "Runtime path crossed a forbidden height edge")
	print("SITE DETAIL TEST 5 PASS: Runtime Site A* reuses height transition rules")

func _test_detail_surface_contract() -> void:
	assert(MapArtCatalogType.SITE_ART_SURFACE_PIXELS == 256, "Baseline Site surface changed unexpectedly")
	assert(MapArtCatalogType.SITE_DETAIL_TILE_PIXELS == 16, "Detail tile pixel contract changed")
	assert(MapArtCatalogType.SITE_DETAIL_SURFACE_PIXELS == 800, "Detail surface is not 800px")
	var layout: SiteLayoutDataType = SiteLayoutGeneratorType.generate(_fixture(
		"detail_art",
		WorldPOIType.CASTLE,
		TerrainType.PLAINS
	))
	var image: Image = MapArtCatalogType.build_layout_base_image(
		layout,
		MapArtCatalogType.SITE_DETAIL_SURFACE_PIXELS
	)
	assert(image != null and image.get_width() == 800 and image.get_height() == 800, "Detail image did not use the 800px surface")
	print("SITE DETAIL TEST 6 PASS: 256px baseline and 800px near-camera surface contracts")

func _fixture(
		site_id: String,
		site_type: int,
		terrain_type: int,
		layout_kind: int = SiteLayoutDataType.LayoutKind.POI
	) -> SiteData:
	var definition: SiteData = SiteData.new(
		site_id,
		site_id,
		site_type,
		Vector2i(2, 2),
		Vector2i(25, 25),
		Vector2i(125, 125)
	)
	definition.layout_kind = layout_kind
	definition.site_seed = 987654321
	definition.entrance_local_meters = Vector2i.ZERO
	definition.source_terrain_type = terrain_type
	definition.source_elevation = 1.0
	definition.source_moisture = 0.4
	definition.source_candidate_cell = Vector2i(25, 25)
	return definition

func _transition_signature(layout: SiteLayoutDataType) -> String:
	var values: Array[String] = []
	for transition: SiteTransitionData in layout.transitions:
		values.append("%s>%s:%d/%d/%d/%d" % [
			str(transition.from_cell),
			str(transition.to_cell),
			transition.from_level,
			transition.to_level,
			transition.kind,
			transition.width_cells,
		])
	return ";".join(values)
