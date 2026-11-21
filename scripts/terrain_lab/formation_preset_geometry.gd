extends RefCounted
## Pure formation preset geometry: the preset whitelist, fixed slot templates and
## footprint radius. No TerrainArmy or planner dependency. Loaded by preload, not class_name.

const MAX_PLATFORM_RADIUS := 12
const MAX_PRESET_RADIUS := 24
const PRESET_IDS := ["auto", "square", "wedge", "goose", "circle", "hook", "loose"]

static func is_valid_preset(preset_id: String) -> bool:
	return PRESET_IDS.has(preset_id)

## Fixed local cells are centered once, then rotated by integer basis vectors.
static func shape_slots(preset_id: String, count: int, anchor: Vector2i, facing: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if preset_id == "auto" or not is_valid_preset(preset_id) or count < 1 or count > 200 or facing not in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		return result
	var local: Array[Vector2i] = []
	var width := ceili(sqrt(float(count)))
	match preset_id:
		"square", "loose", "goose":
			for row in range(ceili(float(count) / float(width))):
				var row_count: int = mini(width, count - local.size())
				var left: int = floori(float(width - row_count) / 2.0)
				for column in range(row_count):
					var u: int = column + left + (row if preset_id == "goose" else 0)
					local.append(Vector2i(u, -row))
		"wedge":
			var row := 0
			while local.size() < count:
				var row_width: int = row * 2 + 1
				var row_count: int = mini(row_width, count - local.size())
				var left: int = floori(float(row_width - row_count) / 2.0)
				for column in range(row_count):
					local.append(Vector2i(column + left - row, -row))
				row += 1
		"circle":
			var radius: int = width
			for v in range(-radius, radius + 1):
				for u in range(-radius, radius + 1):
					local.append(Vector2i(u, v))
			local.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
				var da: int = a.length_squared()
				var db: int = b.length_squared()
				if da != db:
					return da < db
				var outer_a: int = maxi(absi(a.x), absi(a.y))
				var outer_b: int = maxi(absi(b.x), absi(b.y))
				if outer_a != outer_b:
					return outer_a < outer_b
				var quadrant_a: int = (0 if a.x >= 0 else 2) + (0 if a.y >= 0 else 1)
				var quadrant_b: int = (0 if b.x >= 0 else 2) + (0 if b.y >= 0 else 1)
				if quadrant_a != quadrant_b:
					return quadrant_a < quadrant_b
				return a.x < b.x if a.x != b.x else a.y < b.y
			)
			local.resize(count)
		"hook":
			var thickness: int = maxi(1, ceili(sqrt(float(count)) / 4.0))
			var length: int = maxi(thickness, ceili(float(count + 2 * thickness * thickness) / float(3 * thickness)))
			for row in range(length):
				var columns: Array[int] = []
				if row < thickness:
					for column in range(length):
						columns.append(column)
					columns.sort_custom(func(a: int, b: int) -> bool:
						var da: int = absi(2 * a - length + 1)
						var db: int = absi(2 * b - length + 1)
						return da < db if da != db else a < b
					)
				else:
					for column in range(thickness):
						columns.append(column)
						if length - 1 - column != column:
							columns.append(length - 1 - column)
				for column in columns:
					if local.size() >= count:
						break
					local.append(Vector2i(column, -row))
				if local.size() >= count:
					break
	if local.size() != count:
		return result
	if preset_id == "loose":
		for i in range(local.size()):
			local[i] *= 2
	if preset_id != "circle":
		var min_u := local[0].x
		var max_u := local[0].x
		var min_v := local[0].y
		var max_v := local[0].y
		for cell in local:
			min_u = mini(min_u, cell.x)
			max_u = maxi(max_u, cell.x)
			min_v = mini(min_v, cell.y)
			max_v = maxi(max_v, cell.y)
		var center := Vector2i(floori(float(min_u + max_u) / 2.0), floori(float(min_v + max_v) / 2.0))
		for i in range(local.size()):
			local[i] -= center
	var side := Vector2i(-facing.y, facing.x)
	for cell in local:
		result.append(anchor + side * cell.x + facing * cell.y)
	return result

static func preset_footprint_radius(preset_id: String, count: int) -> int:
	if preset_id == "auto":
		return MAX_PLATFORM_RADIUS
	var offsets := shape_slots(preset_id, count, Vector2i.ZERO, Vector2i.RIGHT)
	if offsets.is_empty():
		return -1
	var radius := MAX_PLATFORM_RADIUS
	for offset in offsets:
		radius = maxi(radius, maxi(absi(offset.x), absi(offset.y)) + 1)
	return radius if radius <= MAX_PRESET_RADIUS else -1
