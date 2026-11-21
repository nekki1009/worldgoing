extends RefCounted
## Display-only pixels from the same TerrainData used when entering a Site.

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const SIDE_CELLS := 100
const CELL_PIXELS := 3
const SIDE_PIXELS := SIDE_CELLS * CELL_PIXELS
const SURFACE_COLORS := [Color("65854e"), Color("405e2e"), Color("92704d"),
	Color("72766d"), Color("c4b780"), Color("51806c"), Color("4f97a8")]
const SEA_COLOR := Color("38687c")
const INLAND_WATER_COLOR := Color("4f97a8")
const CLIFF_COLOR := Color("625d49")
const RAMP_LOW_COLOR := Color("806b49")
const RAMP_COLOR := Color("c3b17b")
const SHORE_COLOR := Color("b9b78b")

static func bake(source: RefCounted, site: Vector2i, context: Dictionary = {}) -> Dictionary:
	var result: Dictionary = source.make_terrain_data(site.x, site.y)
	if not bool(result.get("ok", false)):
		result["context"] = context.duplicate()
		return result
	var data: TerrainData = result.get("data") as TerrainData
	var pixels := from_terrain(data)
	if pixels.is_empty():
		return {"ok": false, "code": "INVALID_PREVIEW_TERRAIN", "message": "地形縮圖需要完整的 100×100 Site", "context": context.duplicate()}
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	if not result.data.water_body.is_empty():
		hasher.update(result.data.water_body.to_byte_array())
	return {"ok": true, "context": context.duplicate(), "site": site, "pixels": pixels,
		"size": Vector2i(SIDE_PIXELS, SIDE_PIXELS), "terrain_result": result,
		"water_body_sha256": hasher.finish().hex_encode(),
		"resource_counts": visible_resource_counts(data)}

static func from_terrain(data: TerrainData, show_resources: bool = true) -> PackedByteArray:
	var pixels := PackedByteArray()
	var count := SIDE_CELLS * SIDE_CELLS
	if data == null or data.size != Vector2i(SIDE_CELLS, SIDE_CELLS) \
			or data.height_levels.size() != count or data.surface_types.size() != count \
			or data.cliff_drops.size() != count * 4 or data.ramp_edges.size() != count \
			or not data.water_kind.is_empty() and data.water_kind.size() != count:
		return pixels
	pixels.resize(SIDE_PIXELS * SIDE_PIXELS * 4)
	for y: int in range(SIDE_CELLS):
		for x: int in range(SIDE_CELLS):
			var cell := Vector2i(x, y)
			var index := data.index(cell)
			var surface := int(data.surface_types[index])
			if surface < 0 or surface >= SURFACE_COLORS.size() or data.height_levels[index] > 5:
				return PackedByteArray()
			var water := surface == TerrainData.Surface.WATER
			var color: Color = SURFACE_COLORS[surface]
			if water:
				color = SEA_COLOR if not data.water_kind.is_empty() and data.water_kind[index] == 2 else INLAND_WATER_COLOR
			else:
				# Same warm terrace tint as the original renderer; levels are not metres.
				color = color.lerp(Color(0.96, 0.91, 0.63), minf(0.20, float(data.height_levels[index]) * 0.04))
			var origin := cell * CELL_PIXELS
			for py: int in range(CELL_PIXELS):
				for px: int in range(CELL_PIXELS):
					_put(pixels, origin + Vector2i(px, py), color)
			for direction: int in range(4):
				var normal: Vector2i = TerrainData.DIRECTIONS[direction]
				var adjacent := cell + normal
				var cliff := data.cliff_drops[index * 4 + direction] > 0
				var shore := not water and data.contains(adjacent) \
					and data.surface_types[data.index(adjacent)] == TerrainData.Surface.WATER
				var edge := origin + Vector2i.ONE + normal
				if cliff or shore:
					var tangent := Vector2i(-normal.y, normal.x)
					var edge_color := CLIFF_COLOR if cliff else SHORE_COLOR
					for offset: int in range(-1, 2):
						_put(pixels, edge + tangent * offset, edge_color)
			if not water and data.ramp_edges[index] != 0:
				_draw_ramp_pixels(pixels, data, cell, index)
	if show_resources:
		_draw_resource_marks(pixels, data)
	return pixels

static func visible_resource_counts(data: TerrainData) -> Array[int]:
	var counts: Array[int] = []
	counts.resize(Env.NAMES.size())
	counts.fill(0)
	if data == null:
		return counts
	for entry: Dictionary in _visible_resource_entries(data):
		counts[int(entry.kind)] += 1
	return counts

static func _visible_resource_entries(data: TerrainData) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var keys: Array = data.resource_base.keys()
	keys.sort()
	for key: Variant in keys:
		var base: Variant = data.resource_base[key]
		if not base is Dictionary:
			continue
		var kind: Variant = base.get("kind")
		var cell: Variant = base.get("cell")
		if not kind is int or not cell is int or kind < 0 or kind >= Env.NAMES.size() \
				or kind == Env.Kind.IRON or cell < 0 or cell >= SIDE_CELLS * SIDE_CELLS:
			continue # Undiscovered iron is not a visible map claim.
		entries.append({"kind": kind, "cell": cell})
	return entries

static func _draw_resource_marks(pixels: PackedByteArray, data: TerrainData) -> void:
	for entry: Dictionary in _visible_resource_entries(data):
		var center := data.cell_from_index(int(entry.cell)) * CELL_PIXELS + Vector2i.ONE
		var color: Color = Env.COLORS[int(entry.kind)].lightened(0.25)
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				_put(pixels, center + Vector2i(dx, dy), color if dx == 0 or dy == 0 else Color("17251e"))

static func _draw_ramp_pixels(pixels: PackedByteArray, data: TerrainData, cell: Vector2i, index: int) -> void:
	var level := float(data.height_levels[index])
	for py: int in range(-1, 2):
		for px: int in range(-1, 2):
			var point := Vector2i(px, py)
			var covered := false
			var edge_sum := 0.0
			var edge_count := 0
			for direction: int in range(4):
				if (data.ramp_edges[index] & (1 << direction)) == 0:
					continue
				var normal: Vector2i = TerrainData.DIRECTIONS[direction]
				var tangent := Vector2i(-normal.y, normal.x)
				var along := point.x * normal.x + point.y * normal.y
				var across := float(point.x * tangent.x + point.y * tangent.y) * TerrainRenderer.CELL_PIXELS / float(CELL_PIXELS)
				var span := TerrainRenderer.ramp_span(data, cell, direction)
				if span == Vector2.ZERO:
					continue
				if along < 0 or across < span.x or across > span.y:
					continue
				covered = true
				if along > 0:
					var difference := -1.0 if data.cliff_drops[index * 4 + direction] > 0 else 1.0
					edge_sum += level + difference * 0.5
					edge_count += 1
			if covered:
				# A perpendicular arm cannot overwrite the colour of a shared edge.
				var shade := (edge_sum / float(edge_count) if edge_count > 0 else level) / 5.0
				_put(pixels, cell * CELL_PIXELS + Vector2i.ONE + point,
					RAMP_LOW_COLOR.lerp(RAMP_COLOR, clampf(shade, 0.0, 1.0)))

static func _put(pixels: PackedByteArray, point: Vector2i, color: Color) -> void:
	var offset := (point.y * SIDE_PIXELS + point.x) * 4
	pixels[offset] = color.r8
	pixels[offset + 1] = color.g8
	pixels[offset + 2] = color.b8
	pixels[offset + 3] = 255
