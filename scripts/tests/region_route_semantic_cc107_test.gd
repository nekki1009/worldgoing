extends SceneTree
## Oracle is the pinned, byte-unchanged original static vehicle_crossing.
const Route = preload("res://scripts/region_lab/region_route.gd")
var failures: Array[String] = []
var checks: int = 0

class ChildTerrain:
	extends TerrainData
	var visits: int = 0
	func is_walkable(cell: Vector2i) -> bool:
		visits += 1
		return super.is_walkable(cell)

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("CC107_SEMANTIC_FAIL: " + message)

func _fill(data: TerrainData, size: Vector2i) -> TerrainData:
	data.allocate(size)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.height_levels.fill(1)
	data.static_blocked.resize(size.x * size.y)
	data.static_blocked.fill(0)
	return data

func _body(size: Vector2i = Vector2i(100, 8)) -> TerrainData:
	return _fill(TerrainData.new(), size)

func _pose(kind: String, operator: Vector2i = Vector2i(95, 3), facing: Vector2i = Vector2i.RIGHT) -> Dictionary:
	return {"operator": operator, "facing": facing, "anchor": SiteVehicleTransport.anchor_from_operator(kind, operator, facing)}

func _compare(search: Route.Search, first: TerrainData, second: TerrainData, vehicle: Dictionary,
		pose: Dictionary, edge: int = 1, offset: int = 3, label: String = "") -> Dictionary:
	var expected: Dictionary = Route.vehicle_crossing(first, second, vehicle, pose, edge, offset)
	var actual: Dictionary = search._land_vehicle_crossing(first, second, vehicle, pose, edge, offset)
	var repeated: Dictionary = search._land_vehicle_crossing(first, second, vehicle, pose, edge, offset)
	_check(var_to_bytes(expected) == var_to_bytes(actual) and var_to_bytes(expected) == var_to_bytes(repeated), label + " complete success/failure/pose/path bytes")
	return actual

func _run() -> void:
	var first: TerrainData = _body()
	var second: TerrainData = _body()
	var search: Route.Search = Route.Search.new()
	var vehicle: Dictionary = {"id": "original_cart", "kind": "cart"}
	var pose: Dictionary = _pose("cart")
	var original: Dictionary = _compare(search, first, second, vehicle, pose, 1, 3, "cold then hit")
	_check(original.ok and search._land_crossings.size() == 1, "Real initial success cached once")
	var changed_vehicle: Dictionary = vehicle.duplicate(true)
	changed_vehicle.id = "different_id"
	changed_vehicle.cargo = {"unused": 9}
	var changed_pose: Dictionary = pose.duplicate(true)
	changed_pose.anchor = Vector2i(-500, -500)
	var returned: Dictionary = _compare(search, _body(), _body(), changed_vehicle, changed_pose, 1, 3, "cross-body semantic reuse")
	_check(search._land_crossings.size() == 1, "Equal geometry and relevant inputs share a complete original proof")
	returned.path[0][0] = -500
	returned.pose.anchor = Vector2i(-500, -500)
	_compare(search, first, second, vehicle, pose, 1, 3, "caller mutation cannot poison proof")
	# Same-object provider mutation: no assumed revision bump is required.
	first.flags[first.index(Vector2i(95, 3))] = 0
	var blocked: Dictionary = _compare(search, first, second, vehicle, pose, 1, 3, "same object changed flags")
	_check(not blocked.ok, "Fresh signature prevents stale previous success")
	first.flags.fill(0)
	first.bridge_walkable.resize(first.flags.size()); first.bridge_walkable.fill(1)
	_compare(search, first, second, vehicle, pose, 1, 3, "bridge walkability")
	first = _body()
	first.static_blocked[first.index(Vector2i(95, 3))] = 1
	_compare(search, first, second, vehicle, pose, 1, 3, "static blocker")
	first = _body()
	first.has_raised_surfaces = true
	first.walk_height_levels = first.height_levels.duplicate()
	first.walk_height_levels[first.index(Vector2i(95, 3))] = 4
	_compare(search, first, second, vehicle, pose, 1, 3, "selected raised heights")
	first = _body()
	first.has_navigation_overrides = true
	first.walk_ramp_edges = first.ramp_edges.duplicate()
	first.walk_ramp_edges[first.index(Vector2i(95, 3))] = 0xF0
	_compare(search, first, second, vehicle, pose, 1, 3, "selected prohibited ramps")
	first = _body()
	second = _body()
	second.height_levels.fill(2)
	for y: int in 8:
		first.ramp_edges[first.index(Vector2i(99, y))] = 1 << 1
		second.ramp_edges[second.index(Vector2i(0, y))] = 1 << 3
	_compare(search, first, second, {"kind": "wagon"}, _pose("wagon"), 1, 3, "reciprocal ramp seam")
	# Byte-identical bodies with different alias relationship are NOT the same input.
	first = _body()
	second = _body()
	search = Route.Search.new()
	var aliased: Dictionary = _compare(search, first, first, vehicle, pose, 1, 3, "aliased pair")
	var cloned: Dictionary = _compare(search, first, second, vehicle, pose, 1, 3, "cloned pair")
	_check(not aliased.ok and cloned.ok and search._land_crossings.size() == 2, "Alias bit distinguishes same-data and seam branches")
	_compare(search, first, _body(Vector2i(100, 10)), {"kind": "wagon"}, _pose("wagon", Vector2i(4, 3), Vector2i.LEFT), 3, 3, "negative shift and asymmetric sizes")
	var child: ChildTerrain = _fill(ChildTerrain.new(), Vector2i(100, 8)) as ChildTerrain
	var before: int = search._land_crossings.size()
	_compare(search, child, _body(), vehicle, pose, 1, 3, "subclass uncached fallback")
	_check(child.visits > 0 and search._land_crossings.size() == before, "Subclass side effects are executed, never reused")
	var malformed: TerrainData = _body()
	malformed.flags.resize(1)
	_check(search._land_geometry(malformed).is_empty(), "Malformed layer sizes decline reuse admission")
	_check(search._land_geometry(_body(Vector2i(257, 256))).is_empty(), "Signature allocation cap declines oversized bodies")
	search._drop_land_crossings(first)
	_check(search._land_crossings.is_empty() and search._land_crossing_points == 0, "Terrain eviction removes all matching strong-owner entries")
	_compare(search, first, second, vehicle, pose, 1, 3, "after terrain eviction")
	var no_source: Dictionary = search.run()
	_check(not no_source.ok and search._land_crossings.is_empty() and search._land_crossing_points == 0, "Search.run clears cache on entry and exit even on failure")
	# Many cheap distinct signatures exercise the fixed cache budget.
	first = _body(); second = _body(); search = Route.Search.new()
	for index: int in range(Route.LAND_CROSS_CACHE_LIMIT + 1):
		first.flags[0] = 1 | ((index % 128) << 1)
		first.flags[1] = 1 | ((index >> 7) << 1)
		search._land_vehicle_crossing(first, second, vehicle, pose, 1, 3)
	_check(search._land_crossings.size() == Route.LAND_CROSS_CACHE_LIMIT and search._land_crossing_points <= Route.LAND_CROSS_CACHE_POINTS, "Entry/path retention remains bounded")
	print("CC107_SEMANTIC_REPORT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty(): print("CC107_SEMANTIC_PASS")
	quit(0 if failures.is_empty() else 1)
