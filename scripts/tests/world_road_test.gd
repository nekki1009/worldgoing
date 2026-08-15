extends SceneTree

const TEST_SEED: int = 123456789
const DIFFERENT_SEED: int = 987654321

func _init() -> void:
	assert(load("res://scenes/Main.tscn") is PackedScene, "Main scene could not be loaded")
	var world_data: WorldData = WorldData.new()
	var test_region: Vector2i = _find_region_with_routes(world_data, TEST_SEED)
	var graph_a: Array[WorldRoadRoute] = world_data.get_route_edges_for_region(test_region, TEST_SEED)
	assert(not graph_a.is_empty(), "No deterministic settlement road graph was generated")

	_test_deterministic_graph(world_data, test_region, graph_a)
	_test_query_order_independence(world_data)
	_test_stable_route_id(graph_a[0])
	var path_info: Dictionary = _find_path_route(world_data, TEST_SEED, test_region)
	assert(not path_info.is_empty(), "No generated route path was found")
	_test_deterministic_path(world_data, TEST_SEED, path_info)
	_test_orthogonal_path(path_info)
	_test_cross_region_border(world_data, TEST_SEED, test_region)
	_test_pass_through_region(world_data, TEST_SEED, test_region)
	_test_terrain_avoidance(world_data, TEST_SEED, path_info)
	_test_river_crossing(world_data, TEST_SEED, test_region)
	_test_negative_coordinate(world_data)
	_test_cache_independence(world_data, TEST_SEED, test_region)
	_test_no_duplicate_edges(world_data, TEST_SEED, test_region)
	_test_reaches_settlement(world_data, TEST_SEED, test_region)
	_test_mountain_pass_profile(world_data)

	var different_seed_routes: Array[WorldRoadRoute] = world_data.get_route_edges_for_region(
		test_region,
		DIFFERENT_SEED
	)
	assert(_route_signature(graph_a) != _route_signature(different_seed_routes), "Different seed kept identical road graph")
	print("Road test region: %s" % test_region)
	print("World road tests passed: 14 cases")
	quit()

func _test_deterministic_graph(
		world_data: WorldData,
		region: Vector2i,
		expected: Array[WorldRoadRoute]
	) -> void:
	world_data.clear_road_cache()
	var regenerated: Array[WorldRoadRoute] = world_data.get_route_edges_for_region(region, TEST_SEED)
	assert(_route_signature(expected) == _route_signature(regenerated), "Road graph changed after cache clear")
	print("TEST 1 PASS: deterministic graph")

func _test_query_order_independence(world_data: WorldData) -> void:
	world_data.clear_road_cache()
	var first_a: String = _overlay_signature(world_data.get_roads_for_region(Vector2i(0, 0), TEST_SEED))
	var first_b: String = _overlay_signature(world_data.get_roads_for_region(Vector2i(1, 0), TEST_SEED))
	world_data.clear_road_cache()
	var second_b: String = _overlay_signature(world_data.get_roads_for_region(Vector2i(1, 0), TEST_SEED))
	var second_a: String = _overlay_signature(world_data.get_roads_for_region(Vector2i(0, 0), TEST_SEED))
	assert(first_a == second_a and first_b == second_b, "Road overlay depends on query order")
	print("TEST 2 PASS: Region query order does not change roads")

func _test_stable_route_id(route: WorldRoadRoute) -> void:
	assert(
		route.route_id == WorldRoadGenerator.stable_route_id(route.start_poi_id, route.end_poi_id),
		"Route ID is not canonical"
	)
	assert(
		route.route_id == WorldRoadGenerator.stable_route_id(route.end_poi_id, route.start_poi_id),
		"Reverse endpoint order produced a different route ID"
	)
	assert(route.start_poi_id < route.end_poi_id, "Route endpoints were not canonicalized")
	assert(
		is_equal_approx(
			route.straight_distance_cells(),
			float(absi(route.end_global_cell.x - route.start_global_cell.x) + absi(route.end_global_cell.y - route.start_global_cell.y))
		),
		"Straight Route distance is not tile-Manhattan"
	)
	print("TEST 3 PASS: stable route ID and A-B/B-A dedupe")

func _test_deterministic_path(
		world_data: WorldData,
		world_seed: int,
		path_info: Dictionary
	) -> void:
	var first_route: WorldRoadRoute = path_info["route"] as WorldRoadRoute
	var first_signature: String = _path_signature(first_route)
	world_data.clear_road_cache()
	var second_info: Dictionary = _find_route_by_id(world_data, world_seed, first_route.route_id, path_info["region"] as Vector2i)
	assert(not second_info.is_empty(), "Route disappeared after path cache clear")
	var second_route: WorldRoadRoute = second_info["route"] as WorldRoadRoute
	assert(first_signature == _path_signature(second_route), "Route path changed after cache clear")
	print("TEST 4 PASS: deterministic terrain-aware path")

func _test_orthogonal_path(path_info: Dictionary) -> void:
	var route: WorldRoadRoute = path_info["route"] as WorldRoadRoute
	for index: int in range(1, route.path.size()):
		var delta: Vector2i = route.path[index] - route.path[index - 1]
		assert(absi(delta.x) + absi(delta.y) == 1, "World Route contains a diagonal step")
	assert(is_equal_approx(route.path_length_cells(), float(maxi(route.path.size() - 1, 0))), "Orthogonal route length is incorrect")
	print("TEST 5 PASS: World Route uses only cardinal tile edges")

func _test_cross_region_border(
		world_data: WorldData,
		world_seed: int,
		region: Vector2i
	) -> void:
	var info: Dictionary = _find_route_crossing_region_border(world_data, world_seed, region)
	assert(not info.is_empty(), "No Route Path crossed a Region border")
	var route: WorldRoadRoute = info["route"] as WorldRoadRoute
	for index: int in range(1, route.path.size()):
		var previous_region: Vector2i = _world_cell_for_global(route.path[index - 1])
		var current_region: Vector2i = _world_cell_for_global(route.path[index])
		if previous_region != current_region:
			assert(abs((route.path[index] - route.path[index - 1]).x) <= 1, "Border step jumped in x")
			assert(abs((route.path[index] - route.path[index - 1]).y) <= 1, "Border step jumped in y")
			print("TEST 6 PASS: global path is continuous across Region border")
			return
	assert(false, "Route did not contain a Region border transition")

func _test_pass_through_region(
		world_data: WorldData,
		world_seed: int,
		region: Vector2i
	) -> void:
	var info: Dictionary = _find_pass_through_route(world_data, world_seed, region)
	assert(not info.is_empty(), "No pass-through Region route was found")
	var route: WorldRoadRoute = info["route"] as WorldRoadRoute
	var start_region: Vector2i = _world_cell_for_global(route.start_global_cell)
	var end_region: Vector2i = _world_cell_for_global(route.end_global_cell)
	for global_cell: Vector2i in route.path:
		var middle_region: Vector2i = _world_cell_for_global(global_cell)
		if middle_region == start_region or middle_region == end_region:
			continue
		var overlay: RegionRoadOverlay = world_data.get_roads_for_region(middle_region, world_seed)
		var local_cell: Vector2i = _region_cell_for_global(global_cell)
		assert(overlay.has_road(local_cell), "Pass-through road was missing from its Region overlay")
		print("TEST 7 PASS: pass-through Region query includes endpoint-external road")
		return
	assert(false, "Route did not pass through an endpoint-external Region")

func _test_terrain_avoidance(
		world_data: WorldData,
		world_seed: int,
		path_info: Dictionary
	) -> void:
	var route: WorldRoadRoute = path_info["route"] as WorldRoadRoute
	var mountain_cells: int = 0
	for global_cell: Vector2i in route.path:
		var sample: Vector4 = world_data.terrain_generator.macro_sampler.sample(world_seed, global_cell)
		var terrain_type: int = world_data.terrain_generator.classify_sample(sample)
		assert(not TerrainType.is_water_like(terrain_type), "Road crossed impassable water")
		if terrain_type == TerrainType.MOUNTAIN:
			mountain_cells += 1
	var overlay_region: Vector2i = Vector2i.ZERO
	var before: PackedByteArray = world_data.get_or_generate_region_terrain(overlay_region, world_seed).terrain_array
	world_data.get_roads_for_region(overlay_region, world_seed)
	var after: PackedByteArray = world_data.get_or_generate_region_terrain(
			overlay_region,
			world_seed
		).terrain_array
	assert(before == after, "Road overlay modified base terrain data")
	assert(route.estimated_cost >= route.path_length_cells(), "Terrain weights were not applied")
	print("TEST 8 PASS: water avoided, terrain weights applied, overlay is separate (%d mountain cells)" % mountain_cells)

func _test_river_crossing(
		world_data: WorldData,
		world_seed: int,
		region: Vector2i
	) -> void:
	var info: Dictionary = _find_river_route(world_data, world_seed, region)
	assert(not info.is_empty(), "No deterministic river-crossing Route Path was found")
	var route: WorldRoadRoute = info["route"] as WorldRoadRoute
	assert(route.crosses_river(), "River route did not record crossing cells")
	var crossing_seen: bool = false
	for cell: Vector2i in route.river_crossing_cells:
		var route_region: Vector2i = _world_cell_for_global(cell)
		var overlay: RegionRoadOverlay = world_data.get_roads_for_region(route_region, world_seed)
		if overlay.has_river_crossing(_region_cell_for_global(cell)):
			crossing_seen = true
			break
	assert(crossing_seen, "River crossing flag was not copied to Region overlay")
	print("TEST 9 PASS: river crossing is passable and flagged")

func _test_negative_coordinate(world_data: WorldData) -> void:
	var overlay: RegionRoadOverlay = world_data.get_roads_for_region(Vector2i(-1, 0), TEST_SEED)
	assert(overlay.flags.size() == RegionRoadOverlay.CELL_COUNT, "Negative Region overlay has invalid size")
	var routes: Array[WorldRoadRoute] = world_data.get_route_edges_for_region(Vector2i(-1, 0), TEST_SEED)
	for route: WorldRoadRoute in routes:
		assert(route.route_id == WorldRoadGenerator.stable_route_id(route.start_poi_id, route.end_poi_id), "Negative route ID is unstable")
	print("TEST 10 PASS: negative World Cell road query")

func _test_cache_independence(
		world_data: WorldData,
		world_seed: int,
		region: Vector2i
	) -> void:
	var first: String = _overlay_signature(world_data.get_roads_for_region(region, world_seed))
	world_data.clear_road_cache()
	var second: String = _overlay_signature(world_data.get_roads_for_region(region, world_seed))
	assert(first == second, "Clearing route and overlay caches changed roads")
	print("TEST 11 PASS: graph/path cache only affects performance")

func _test_no_duplicate_edges(
		world_data: WorldData,
		world_seed: int,
		region: Vector2i
	) -> void:
	var seen: Dictionary = {}
	for route: WorldRoadRoute in world_data.get_route_edges_for_region(region, world_seed):
		assert(not seen.has(route.route_id), "Duplicate Route Edge was generated")
		seen[route.route_id] = true
		assert(route.start_poi_id < route.end_poi_id, "Route Edge is not canonical")
		assert(not route.start_poi_id.contains("ruins") and not route.end_poi_id.contains("ruins"), "Ruins entered road graph")
		assert(not route.start_poi_id.contains("cave") and not route.end_poi_id.contains("cave"), "Cave entered road graph")
	print("TEST 12 PASS: no duplicate edges and no Ruins/Cave endpoints")

func _test_reaches_settlement(
		world_data: WorldData,
		world_seed: int,
		region: Vector2i
	) -> void:
	var info: Dictionary = _find_path_route(world_data, world_seed, region)
	assert(not info.is_empty(), "No route available for endpoint test")
	var route: WorldRoadRoute = info["route"] as WorldRoadRoute
	assert(route.path.front() == route.start_global_cell, "Route path does not start at settlement cell")
	assert(route.path.back() == route.end_global_cell, "Route path does not end at settlement cell")
	print("TEST 13 PASS: Route Path reaches both settlement POI cells")

func _test_mountain_pass_profile(world_data: WorldData) -> void:
	var global_cell: Vector2i = Vector2i(1832, 38)
	var info: Dictionary = world_data.sample_travel_data(TEST_SEED, global_cell)
	assert(int(info["terrain_type"]) == TerrainType.MOUNTAIN, "Mountain Pass fixture left Mountain terrain")
	assert(
		int(info["site_landform"]) == SiteLayoutData.Landform.MOUNTAIN_PASS,
		"Mountain Road did not resolve to a Site pass"
	)
	var exit_mask: int = int(info["travel_exit_mask"])
	assert((exit_mask & (exit_mask - 1)) != 0, "Mountain Pass has fewer than two exits")
	assert((info["road_connection_offsets"] as Array).size() >= 2, "Mountain Pass lost Road topology")
	print("TEST 14 PASS: actual Mountain Road Site exposes a directional pass profile")

func _find_region_with_routes(world_data: WorldData, world_seed: int) -> Vector2i:
	for y: int in range(0, 6):
		for x: int in range(0, 6):
			var region: Vector2i = Vector2i(x, y)
			if not world_data.get_route_edges_for_region(region, world_seed).is_empty():
				return region
	assert(false, "No test Region contains a settlement road graph")
	return Vector2i.ZERO

func _find_path_route(world_data: WorldData, world_seed: int, region: Vector2i) -> Dictionary:
	var search_regions: Array[Vector2i] = _nearby_regions(region)
	for search_region: Vector2i in search_regions:
		var overlay: RegionRoadOverlay = world_data.get_roads_for_region(search_region, world_seed)
		for y: int in range(WorldCoordinates.REGION_GRID_SIZE):
			for x: int in range(WorldCoordinates.REGION_GRID_SIZE):
				var routes: Array[WorldRoadRoute] = overlay.get_routes(Vector2i(x, y))
				for route: WorldRoadRoute in routes:
					if route.path.size() > 1:
						return {"route": route, "overlay": overlay, "region": search_region}
	return {}

func _find_route_by_id(
		world_data: WorldData,
		world_seed: int,
		route_id: String,
		center: Vector2i
	) -> Dictionary:
	for region: Vector2i in _nearby_regions(center):
		var overlay: RegionRoadOverlay = world_data.get_roads_for_region(region, world_seed)
		var route: WorldRoadRoute = overlay.get_route(route_id)
		if route != null and route.path.size() > 1:
			return {"route": route, "overlay": overlay, "region": region}
	return {}

func _find_route_crossing_region_border(
		world_data: WorldData,
		world_seed: int,
		region: Vector2i
	) -> Dictionary:
	for search_region: Vector2i in _nearby_regions(region):
		var overlay: RegionRoadOverlay = world_data.get_roads_for_region(search_region, world_seed)
		for route: WorldRoadRoute in _routes_in_overlay(overlay):
			for index: int in range(1, route.path.size()):
				if _world_cell_for_global(route.path[index - 1]) != _world_cell_for_global(route.path[index]):
					return {"route": route, "overlay": overlay, "region": search_region}
	return {}

func _find_pass_through_route(
		world_data: WorldData,
		world_seed: int,
		region: Vector2i
	) -> Dictionary:
	for search_region: Vector2i in _nearby_regions(region):
		var overlay: RegionRoadOverlay = world_data.get_roads_for_region(search_region, world_seed)
		for route: WorldRoadRoute in _routes_in_overlay(overlay):
			var endpoint_regions: Dictionary = {}
			endpoint_regions[_world_cell_for_global(route.start_global_cell)] = true
			endpoint_regions[_world_cell_for_global(route.end_global_cell)] = true
			var path_regions: Dictionary = {}
			for cell: Vector2i in route.path:
				path_regions[_world_cell_for_global(cell)] = true
			for path_region_value: Variant in path_regions.keys():
				var path_region: Vector2i = path_region_value as Vector2i
				if not endpoint_regions.has(path_region):
					return {"route": route, "overlay": overlay, "region": search_region}
	return {}

func _find_river_route(
		world_data: WorldData,
		world_seed: int,
		region: Vector2i
	) -> Dictionary:
	for search_region: Vector2i in _nearby_regions(region):
		var overlay: RegionRoadOverlay = world_data.get_roads_for_region(search_region, world_seed)
		for route: WorldRoadRoute in _routes_in_overlay(overlay):
			if route.crosses_river():
				return {"route": route, "overlay": overlay, "region": search_region}
	return {}

func _routes_in_overlay(overlay: RegionRoadOverlay) -> Array[WorldRoadRoute]:
	var by_id: Dictionary = {}
	for y: int in range(WorldCoordinates.REGION_GRID_SIZE):
		for x: int in range(WorldCoordinates.REGION_GRID_SIZE):
			for route: WorldRoadRoute in overlay.get_routes(Vector2i(x, y)):
				by_id[route.route_id] = route
	var ids: Array[String] = []
	for route_id: Variant in by_id.keys():
		ids.append(str(route_id))
	ids.sort()
	var result: Array[WorldRoadRoute] = []
	for route_id: String in ids:
		result.append(by_id[route_id] as WorldRoadRoute)
	return result

func _nearby_regions(center: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y: int in range(center.y - 2, center.y + 3):
		for x: int in range(center.x - 2, center.x + 3):
			result.append(Vector2i(x, y))
	return result

func _overlay_signature(overlay: RegionRoadOverlay) -> String:
	var entries: Array[String] = []
	for y: int in range(WorldCoordinates.REGION_GRID_SIZE):
		for x: int in range(WorldCoordinates.REGION_GRID_SIZE):
			var cell: Vector2i = Vector2i(x, y)
			var flags: int = overlay.get_flags(cell)
			if flags == 0:
				continue
			entries.append("%d,%d=%d:%s" % [x, y, flags, ",".join(overlay.get_route_ids(cell))])
	return "|".join(entries)

func _route_signature(routes: Array[WorldRoadRoute]) -> String:
	var entries: Array[String] = []
	for route: WorldRoadRoute in routes:
		entries.append("%s|%s|%s|%s|%s" % [
			route.route_id,
			route.start_poi_id,
			route.end_poi_id,
			route.start_global_cell,
			route.end_global_cell,
		])
	entries.sort()
	return "|".join(entries)

func _path_signature(route: WorldRoadRoute) -> String:
	var entries: Array[String] = []
	for cell: Vector2i in route.path:
		entries.append("%d,%d" % [cell.x, cell.y])
	return ";".join(entries)

func _world_cell_for_global(global_cell: Vector2i) -> Vector2i:
	return WorldCoordinates.global_region_cell_to_world_region(global_cell)["world_cell"] as Vector2i

func _region_cell_for_global(global_cell: Vector2i) -> Vector2i:
	return WorldCoordinates.global_region_cell_to_world_region(global_cell)["region_cell"] as Vector2i
