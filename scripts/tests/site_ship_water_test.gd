extends SceneTree

const Data = preload("res://scripts/terrain_lab/terrain_data.gd")
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 10000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("Ship water query deadline")
		quit(1)
	return false

func _fixture() -> TerrainData:
	var data := Data.new()
	data.allocate(Vector2i(16, 16))
	data.flags.fill(Data.Flag.WALKABLE)
	var count := data.size.x * data.size.y
	data.water_kind.resize(count)
	data.water_body.resize(count)
	data.water_body.fill(-1)
	data.static_blocked.resize(count)
	data.feature_at.resize(count)
	for y in range(3, 6):
		for x in range(2, 8):
			var i := data.index(Vector2i(x, y))
			data.surface_types[i] = Data.Surface.WATER
			data.flags[i] = Data.Flag.BLOCKED | Data.Flag.WET
			data.water_kind[i] = 1 if x < 5 else 2
			data.water_body[i] = 10 if x < 5 else 20
	return data

func _run() -> void:
	var data := _fixture()
	var start := Vector2i(2, 3)
	var goal := Vector2i(7, 3)
	var a := Vector2i(3, 3)
	var b := a + Vector2i.RIGHT
	var square: Array[Vector2i] = [a, b, a + Vector2i.DOWN, b + Vector2i.DOWN]
	assert(not data.can_navigate_water(start), "Unmarked water is unknown, not deep navigable water")
	data.parameters = {"navigable_water_version": 2, "navigable_water_bodies": [10, 20]}
	assert(not data.can_navigate_water(start), "Unknown permission versions are rejected")
	data.parameters.navigable_water_version = true
	assert(not data.can_navigate_water(start), "A boolean is not a source version")
	data.parameters.navigable_water_version = 1
	data.parameters.navigable_water_bodies = [10]
	assert(data.can_navigate_water(start) and not data.can_navigate_water(goal))
	assert(not data.can_water_step(Vector2i(4, 3), Vector2i(5, 3)), "Both sides need explicit permission")
	data.parameters.navigable_water_bodies = [10, 20]
	assert(data.can_water_step(Vector2i(4, 3), Vector2i(5, 3)), "A legal edge may cross body IDs and salinity")
	assert(not data.is_walkable(start) and not data.can_step(start, start + Vector2i.RIGHT), "Permission never makes water walkable")
	assert(not data.can_navigate_water(Vector2i(2, 2)) and not data.can_navigate_water(Vector2i(-1, 3)))
	assert(not data.can_water_step(start, start + Vector2i(1, 1)))
	assert(data.can_place_water_vehicle(square))
	assert(not data.can_place_water_vehicle([]))
	assert(not data.can_place_water_vehicle([a, a]), "Duplicate footprint cells are rejected")
	assert(not data.can_place_water_vehicle([a, a + Vector2i.RIGHT * 2]), "Footprint must be connected")
	assert(not data.can_place_water_vehicle([start, start + Vector2i.UP]), "Every footprint cell must be water")
	data.height_levels[data.index(b)] = 1
	assert(not data.can_water_step(a, b) and not data.can_place_water_vehicle(square), "Different water levels are not a legal crossing")
	data.height_levels[data.index(b)] = 0
	data.walk_ramp_edges = data.ramp_edges.duplicate()
	data.has_navigation_overrides = true
	data.walk_ramp_edges[data.index(a)] = 1 << 5
	assert(not data.can_place_water_vehicle(square), "An illegal internal edge cannot hide behind another connected route")
	data.walk_ramp_edges[data.index(a)] = 0
	data.static_blocked[data.index(b)] = 1
	assert(not data.can_place_water_vehicle(square), "An off-center obstacle blocks the whole hull")
	data.static_blocked[data.index(b)] = 0
	data.feature_at[data.index(b)] = 3
	assert(not data.can_navigate_water(b), "An existing bridge/pier feature requires a clearance contract")
	data.feature_at[data.index(b)] = 0
	data.walk_height_levels = data.height_levels.duplicate()
	data.walk_height_levels[data.index(b)] = 1
	data.has_raised_surfaces = true
	assert(not data.can_navigate_water(b), "Raised decks are rejected even without a solid blocker")
	data.has_raised_surfaces = false
	var parameters_before := data.parameters.duplicate(true)
	var fingerprint_before := data.fingerprint()
	var path := data.path_water_between(start, goal)
	assert(path.size() == 5 and path[0] == start + Vector2i.RIGHT and path[-1] == goal)
	var previous := start
	for cell: Vector2i in path:
		assert(data.can_water_step(previous, cell))
		previous = cell
	assert(data.path_water_between(start, goal, Callable(), 1).is_empty(), "Search budget is enforced")
	assert(data.path_water_between(start, goal, Callable(), 0).is_empty())
	assert(data.path_water_between(start, start).is_empty(), "A path excludes its starting cell")
	var blocked := func(cell: Vector2i) -> bool: return cell.x == 4
	assert(data.path_water_between(start, goal, blocked).is_empty(), "Original caller blockers also constrain water search")
	assert(data.parameters == parameters_before and data.fingerprint() == fingerprint_before, "Queries do not mutate terrain or source rules")
	# Original parameters JSON roundtrip preserves integer permissions as numbers.
	data.parameters = JSON.parse_string(JSON.stringify(data.parameters))
	assert(data.can_navigate_water(start) and data.can_place_water_vehicle(square))
	data.parameters = {"navigable_water_version": 1, "navigable_water_cells": [data.index(start), data.index(start + Vector2i.RIGHT)]}
	data.water_body = PackedInt32Array()
	assert(data.can_navigate_water(start) and data.can_water_step(start, start + Vector2i.RIGHT), "An explicit cell fixture needs no inferred body/depth")
	assert(not data.can_navigate_water(goal))
	data.parameters.navigable_water_cells = [str(data.index(start))]
	assert(not data.can_navigate_water(start), "String cell IDs are not source permissions")
	print("SITE_SHIP_WATER_PASS")
	quit(0)
