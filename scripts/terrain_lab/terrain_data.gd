class_name TerrainData
extends RefCounted

enum Surface { GRASS, FOREST_GROUND, DIRT, ROCK, SAND, WETLAND, WATER }
enum Flag { WALKABLE = 1, CLIFF = 2, RAMP = 4, SHORE = 8, WET = 16, BLOCKED = 32 }
const SURFACE_NAMES: Array[String] = ["GRASS", "FOREST_GROUND", "DIRT", "ROCK", "SAND", "WETLAND", "WATER"]
const DIRECTIONS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

var size := Vector2i(100, 100)
var height_levels := PackedByteArray()
var surface_types := PackedByteArray()
var flags := PackedByteArray()
# Four positive high-to-low drops per cell, N/E/S/W. Zero does not mean a ramp.
var cliff_drops := PackedByteArray()
# Reciprocal N/E/S/W bits mark legal one-level crossings, independently of art.
var ramp_edges := PackedByteArray()
var detail_variation := PackedByteArray()
var spawn_cell := Vector2i(-1, -1)
var preset: int = 0
var seed_value: int = 0
var parameters: Dictionary = {}

# Generated environment and sparse Site changes share this map owner.
var fertility := PackedByteArray()
var moisture := PackedByteArray()
var drainage := PackedByteArray()
var foundation := PackedByteArray()
var groundwater := PackedByteArray()
var water_kind := PackedByteArray() # 0 none, 1 fresh, 2 sea, 3 brine, 4 mapped water of unknown salinity.
var water_body := PackedInt32Array()
var resource_base: Dictionary = {}
var resources_at: Dictionary = {}
var site: Dictionary = {}
# Rebuildable indexes; never serialized as a second authority.
var static_blocked := PackedByteArray()
var feature_at := PackedInt32Array()
# Feature surfaces are rebuilt from the original natural ground and Site features.
# Ramp bytes use N/E/S/W in bits 0..3; bits 4..7 prohibit those edges.
var walk_height_levels := PackedByteArray()
var bridge_walkable := PackedByteArray() # Derived only by SiteEnvironment from complete bridges.
var bridge_navigation_flags := PackedByteArray() # Derived flags for original native/navigation consumers.
var walk_ramp_edges := PackedByteArray()
var facility_cells := PackedByteArray()
var has_raised_surfaces := false
var has_navigation_overrides := false
var navigation_revision := 0
var environment_revision := 0
var ground_loot_at: Dictionary = {} # Rebuilt from site.ground_loot; never a second item owner.
var ground_loot_dirty_rows: Dictionary = {} # Event-only presentation invalidation, never saved.
# Original live owners register pure preflight/reference cleanup callbacks.
# They are never serialized or adopted as a second inventory owner.
var item_transfer_guard: Callable
var ground_loot_removed: Callable

func allocate(grid_size: Vector2i) -> void:
	size = grid_size
	var count: int = size.x * size.y
	height_levels.resize(count)
	surface_types.resize(count)
	flags.resize(count)
	cliff_drops.resize(count * 4)
	ramp_edges.resize(count)
	detail_variation.resize(count)

func contains(terrain_cell: Vector2i) -> bool:
	return terrain_cell.x >= 0 and terrain_cell.y >= 0 and terrain_cell.x < size.x and terrain_cell.y < size.y

func index(terrain_cell: Vector2i) -> int:
	return terrain_cell.y * size.x + terrain_cell.x

func is_walkable(terrain_cell: Vector2i) -> bool:
	return is_terrain_walkable(terrain_cell) and (static_blocked.is_empty() or static_blocked[index(terrain_cell)] == 0)

func is_terrain_walkable(terrain_cell: Vector2i) -> bool:
	if not contains(terrain_cell): return false
	var i := index(terrain_cell)
	return (flags[i] & Flag.WALKABLE) != 0 or (bridge_walkable.size() == flags.size() and bridge_walkable[i] != 0)

func navigation_flags() -> PackedByteArray:
	return bridge_navigation_flags if bridge_navigation_flags.size() == flags.size() else flags

func navigation_heights() -> PackedByteArray:
	return walk_height_levels if has_raised_surfaces and walk_height_levels.size() == height_levels.size() else height_levels

func navigation_ramps() -> PackedByteArray:
	return walk_ramp_edges if has_navigation_overrides and walk_ramp_edges.size() == ramp_edges.size() else ramp_edges

func effective_height(terrain_cell: Vector2i) -> int:
	return int(navigation_heights()[index(terrain_cell)]) if contains(terrain_cell) else -1

func surface_visual_offset(terrain_cell: Vector2i) -> Vector2:
	if not has_raised_surfaces or not contains(terrain_cell): return Vector2.ZERO
	return Vector2(0.0, -48.0 * (effective_height(terrain_cell) - int(height_levels[index(terrain_cell)])))

func surface_visual_offset_at(ground_pixels: Vector2) -> Vector2:
	if not has_raised_surfaces: return Vector2.ZERO
	var grid := ground_pixels / TerrainRenderer.CELL_PIXELS
	var cell := Vector2i(floori(grid.x), floori(grid.y))
	if not contains(cell): return Vector2.ZERO
	var result := surface_visual_offset(cell)
	var local := grid - Vector2(cell) - Vector2.ONE * 0.5
	# Interpolate only across legal edges; a neighbouring wall side is not a slope.
	for offset: Vector2i in [Vector2i(int(signf(local.x)), 0), Vector2i(0, int(signf(local.y)))]:
		if offset != Vector2i.ZERO and can_step(cell, cell + offset):
			var weight := absf(local.x) if offset.x != 0 else absf(local.y)
			result += (surface_visual_offset(cell + offset) - surface_visual_offset(cell)) * weight
	return result

func can_step(from: Vector2i, to: Vector2i) -> bool:
	return can_step_static(from, to, null)

func can_step_static(from: Vector2i, to: Vector2i, profile: Object = null) -> bool:
	if not can_navigation_step(from, to):
		return false
	if not static_blocked.is_empty() and (static_blocked[index(from)] != 0 or static_blocked[index(to)] != 0):
		return false
	if profile != null and "max_step_height" in profile:
		var max_step: int = int(profile.max_step_height)
		var a: int = index(from)
		var b: int = index(to)
		var heights := navigation_heights()
		if absi(int(heights[a]) - int(heights[b])) > max_step:
			return false
	return true

func can_navigation_step(from: Vector2i, to: Vector2i) -> bool:
	if not is_terrain_walkable(from) or not is_terrain_walkable(to): return false
	var direction := DIRECTIONS.find(to - from)
	if direction < 0: return false
	var a := index(from)
	var b := index(to)
	var reverse := (direction + 2) % 4
	var ramps := navigation_ramps()
	if (ramps[a] & (1 << (direction + 4))) != 0 or (ramps[b] & (1 << (reverse + 4))) != 0:
		return false
	var heights := navigation_heights()
	var difference := absi(int(heights[a]) - int(heights[b]))
	return difference == 0 or (difference == 1 and (ramps[a] & (1 << direction)) != 0 and (ramps[b] & (1 << reverse)) != 0)

func get_geometric_adjacent_cells(center: Vector2i, _profile: Object = null) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in DIRECTIONS:
		var next := center + d
		if contains(next):
			result.append(next)
	return result

func can_terrain_step(from: Vector2i, to: Vector2i) -> bool:
	if not is_terrain_walkable(from) or not is_terrain_walkable(to):
		return false
	var direction: int = DIRECTIONS.find(to - from)
	if direction < 0:
		return false
	var a: int = index(from)
	var b: int = index(to)
	var difference: int = absi(int(height_levels[a]) - int(height_levels[b]))
	if difference == 0:
		return true
	return difference == 1 and (ramp_edges[a] & (1 << direction)) != 0 \
		and (ramp_edges[b] & (1 << ((direction + 2) % 4))) != 0

func can_attack_across(from: Vector2i, to: Vector2i) -> bool:
	# Current tall resource/building obstacles block both travel and weapons.
	# Low plants, underground deposits and fields do neither.
	return can_navigation_step(from, to) and (static_blocked.is_empty() \
		or (static_blocked[index(from)] == 0 and static_blocked[index(to)] == 0))

func cell_from_index(cell_index: int) -> Vector2i:
	return Vector2i(cell_index % size.x, floori(float(cell_index) / float(size.x)))

func can_navigate_water(terrain_cell: Vector2i) -> bool:
	# Versioned gameplay permission, not water depth inferred from salinity/height.
	var version: Variant = parameters.get("navigable_water_version")
	if not (version is int or version is float) or float(version) != 1.0 or not contains(terrain_cell):
		return false
	var i := index(terrain_cell)
	var count := size.x * size.y
	if surface_types.size() != count or height_levels.size() != count or flags.size() != count \
			or surface_types[i] != Surface.WATER or (flags[i] & Flag.WALKABLE) != 0:
		return false
	if not static_blocked.is_empty() and (static_blocked.size() != count or static_blocked[i] != 0):
		return false
	# A v1 bridge owns this single XY surface with zero ship clearance.
	# Planned/complete bridge footprint remains unavailable to the water owner.
	if not feature_at.is_empty() and (feature_at.size() != count or feature_at[i] != 0):
		return false
	if has_raised_surfaces and (walk_height_levels.size() != count or walk_height_levels[i] != height_levels[i]):
		return false
	if parameters.get("author_water_rule") == "author_water_rule_v1":
		var permission: Dictionary = parameters.get("author_water_permissions", {})
		if _water_rule_has(permission.get("cells"), i) or water_body.size() == count and _water_rule_has(permission.get("bodies"), water_body[i]): return true
		if _water_rule_has(parameters.get("author_water_changed_cells"), i): return false
	if _water_rule_has(parameters.get("navigable_water_cells"), i):
		return true
	return water_body.size() == count and water_body[i] >= 0 \
		and _water_rule_has(parameters.get("navigable_water_bodies"), water_body[i])

func _water_rule_has(values: Variant, expected: int) -> bool:
	if not values is Array: return false
	# Native lookup instead of a GDScript loop over the whole Site ocean list
	# (up to ~10^4 cells), which ran on every can_navigate_water call. A stored
	# number matches when it equals the int or the float of expected; the same
	# test as the former loop over int/float elements.
	var list: Array = values
	return list.has(expected) or list.has(float(expected))

func can_water_step(from: Vector2i, to: Vector2i) -> bool:
	if not can_navigate_water(from) or not can_navigate_water(to): return false
	var direction := DIRECTIONS.find(to - from)
	if direction < 0: return false
	var a := index(from)
	var b := index(to)
	if height_levels[a] != height_levels[b]: return false
	var ramps := navigation_ramps()
	if ramps.size() != size.x * size.y: return false
	var reverse := (direction + 2) % 4
	return (ramps[a] & (1 << (direction + 4))) == 0 and (ramps[b] & (1 << (reverse + 4))) == 0

func can_place_water_vehicle(cells: Array[Vector2i]) -> bool:
	if cells.is_empty(): return false
	var footprint: Dictionary = {}
	for cell: Vector2i in cells:
		if footprint.has(cell) or not can_navigate_water(cell): return false
		footprint[cell] = true
	# Validate every internal edge, including edges outside the spanning path.
	for cell: Vector2i in cells:
		for direction: Vector2i in DIRECTIONS:
			var next := cell + direction
			if footprint.has(next) and not can_water_step(cell, next): return false
	var reached := {cells[0]: true}
	var pending: Array[Vector2i] = [cells[0]]
	var head := 0
	while head < pending.size():
		var current := pending[head]
		head += 1
		for direction: Vector2i in DIRECTIONS:
			var next := current + direction
			if footprint.has(next) and not reached.has(next):
				reached[next] = true
				pending.append(next)
	return reached.size() == footprint.size()

func path_water_between(start: Vector2i, goal: Vector2i, blocked: Callable = Callable(), max_expansions: int = 4096) -> Array[Vector2i]:
	# Same original cell BFS shape; vehicle pose/sweep legality stays with Vehicles.
	var result: Array[Vector2i] = []
	var budget := clampi(max_expansions, 0, size.x * size.y)
	if budget == 0 or start == goal or not can_navigate_water(start) or not can_navigate_water(goal):
		return result
	if blocked.is_valid() and bool(blocked.call(goal)): return result
	var previous := {start: start}
	var pending: Array[Vector2i] = [start]
	var head := 0
	while head < pending.size() and head < budget and not previous.has(goal):
		var current := pending[head]
		head += 1
		for direction: Vector2i in DIRECTIONS:
			var next := current + direction
			if previous.has(next) or not can_water_step(current, next): continue
			if blocked.is_valid() and bool(blocked.call(next)): continue
			previous[next] = current
			pending.append(next)
	if not previous.has(goal): return result
	var cursor := goal
	while cursor != start:
		result.append(cursor)
		cursor = previous[cursor]
	result.reverse()
	return result

func path_between(start: Vector2i, goal: Vector2i, blocked: Callable = Callable(), step_blocked: Callable = Callable()) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not is_walkable(start) or not is_walkable(goal) or start == goal:
		return result
	var previous := {start: start}
	var pending: Array[Vector2i] = [start]
	var head := 0
	while head < pending.size():
		var current := pending[head]
		head += 1
		if current == goal:
			break
		for direction: Vector2i in DIRECTIONS:
			var next := current + direction
			if previous.has(next) or not can_step(current, next):
				continue
			if step_blocked.is_valid() and bool(step_blocked.call(current, next)):
				continue
			if blocked.is_valid() and bool(blocked.call(next)):
				continue
			previous[next] = current
			pending.append(next)
	if not previous.has(goal):
		return result
	var cursor := goal
	while cursor != start:
		result.append(cursor)
		cursor = previous[cursor]
	result.reverse()
	return result

func fingerprint() -> String:
	var bytes := PackedByteArray()
	for field: PackedByteArray in [height_levels, surface_types, flags, cliff_drops, ramp_edges, detail_variation]:
		bytes.append_array(field)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
