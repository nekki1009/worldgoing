class_name TerrainRenderer
extends Node2D

const CELL_PIXELS: float = 64.0
const LayerScript = preload("res://scripts/terrain_lab/terrain_render_layer.gd")
var data: TerrainData
var debug_enabled: bool = false
var layers: Array[Node2D] = []
var grass_texture: Texture2D
var cliff_texture: Texture2D
var water_texture: Texture2D
var sand_texture: Texture2D

func _ready() -> void:
	grass_texture = _load_texture("res://assets/map/terrain_lab/terrain_lab_grass_v2.png")
	cliff_texture = _load_texture("res://assets/map/site/cliffs/cliff_face_inland_highres_v2.png")
	water_texture = _load_texture("res://assets/map/terrain_lab/terrain_lab_water_v2.png")
	sand_texture = _load_texture("res://assets/map/terrain_lab/terrain_lab_sand_v2.png")
	for layer_name: String in ["GroundTop", "CliffFaces", "Water", "TerrainDetail"]:
		var layer := Node2D.new()
		layer.set_script(LayerScript)
		layer.name = layer_name
		layer.set("renderer", self)
		layer.set("kind", layers.size())
		add_child(layer)
		layers.append(layer)

func _load_texture(path: String) -> Texture2D:
	var texture: Texture2D = ResourceLoader.load(path, "Texture2D") as Texture2D
	if texture == null:
		push_warning("Terrain Lab could not load art: %s" % path)
		return null
	return texture

func display(terrain: TerrainData) -> void:
	data = terrain
	redraw()

func redraw() -> void:
	for layer: Node2D in layers:
		layer.queue_redraw()

func cell_center(terrain_cell: Vector2i) -> Vector2:
	return (Vector2(terrain_cell) + Vector2.ONE * 0.5) * CELL_PIXELS

func pick_cell(viewport_position: Vector2) -> Vector2i:
	var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * viewport_position
	return Vector2i(floori(local.x / CELL_PIXELS), floori(local.y / CELL_PIXELS))

func draw_layer(canvas: Node2D, kind: int) -> void:
	if data == null:
		return
	if kind == 0:
		_draw_ground(canvas)
		return
	for y: int in range(data.size.y):
		for x: int in range(data.size.x):
			var cell := Vector2i(x, y)
			var i: int = data.index(cell)
			var rect := Rect2(Vector2(cell) * CELL_PIXELS, Vector2.ONE * CELL_PIXELS)
			var water: bool = data.surface_types[i] == TerrainData.Surface.WATER
			match kind:
				1:
					_draw_cliffs(canvas, cell, i, rect)
				2:
					if water:
						_draw_texture_region(canvas, water_texture, rect, cell, Color(1.0, 1.0, 1.0, 0.94))
						var wave_y: float = rect.position.y + 18.0 + float((x * 7 + y * 3) % 24)
						canvas.draw_line(Vector2(rect.position.x + 8.0, wave_y), Vector2(rect.end.x - 9.0, wave_y), Color(0.75, 0.95, 0.97, 0.16), 2.0)
				3:
					if not water:
						# Brush marks are surface variation, not trees, stones or resources.
						var shade: float = float(data.detail_variation[i]) / 255.0
						var dot: Vector2 = rect.position + Vector2(22.0 + shade * 18.0, 24.0 + fmod(shade * 73.0, 16.0))
						canvas.draw_line(dot, dot + Vector2(7.0, -2.0), Color(1.0, 1.0, 0.8, 0.09), 2.0)
						_draw_ramps(canvas, cell, i)
					if debug_enabled:
						canvas.draw_rect(rect, Color(0.06, 0.1, 0.08, 0.3), false, 1.0)
						canvas.draw_string(ThemeDB.fallback_font, rect.position + Vector2(5.0, 21.0), str(data.height_levels[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.9))

func _draw_ground(canvas: Node2D) -> void:
	var map_rect := Rect2(Vector2.ZERO, Vector2(data.size) * CELL_PIXELS)
	if grass_texture != null:
		canvas.draw_texture_rect(grass_texture, map_rect, true, Color(1.0, 1.0, 1.0, 0.96))
	else:
		canvas.draw_rect(map_rect, Color("65854e"), true)
	for y: int in range(data.size.y):
		for x: int in range(data.size.x):
			var cell := Vector2i(x, y)
			var i: int = data.index(cell)
			var surface: int = data.surface_types[i]
			if surface == TerrainData.Surface.WATER:
				continue
			var rect := Rect2(Vector2(cell) * CELL_PIXELS, Vector2.ONE * CELL_PIXELS)
			match surface:
				TerrainData.Surface.FOREST_GROUND:
					canvas.draw_rect(rect, Color(0.25, 0.39, 0.18, 0.26))
				TerrainData.Surface.DIRT:
					_draw_texture_region(canvas, sand_texture, rect, cell, Color(0.72, 0.54, 0.34, 0.76))
				TerrainData.Surface.ROCK:
					canvas.draw_rect(rect, Color(0.24, 0.27, 0.25, 0.46))
				TerrainData.Surface.SAND:
					_draw_texture_region(canvas, sand_texture, rect, cell, Color(1.0, 0.92, 0.67, 0.9))
				TerrainData.Surface.WETLAND:
					canvas.draw_rect(rect, Color(0.28, 0.49, 0.39, 0.34))
			# Height tint keeps the discrete platform levels readable without a grid.
			var height: int = data.height_levels[i]
			if height > 0:
				canvas.draw_rect(rect, Color(0.09, 0.12, 0.08, minf(0.16, float(height) * 0.025)), true)

func _draw_texture_region(canvas: Node2D, texture: Texture2D, rect: Rect2, cell: Vector2i, tint: Color) -> void:
	if texture == null:
		canvas.draw_rect(rect, tint, true)
		return
	var texture_size := texture.get_size()
	var source_tile := texture_size / 4.0
	var quadrant := Vector2i(posmod(cell.x, 4), posmod(cell.y, 4))
	var source_rect := Rect2(Vector2(quadrant) * source_tile, source_tile)
	canvas.draw_texture_rect_region(texture, rect, source_rect, tint)

func _draw_cliffs(canvas: Node2D, cell: Vector2i, i: int, rect: Rect2) -> void:
	for d: int in range(4):
		var drop: int = data.cliff_drops[i * 4 + d]
		var shore: bool = false
		var neighbor: Vector2i = cell + TerrainData.DIRECTIONS[d]
		if data.contains(neighbor):
			shore = data.surface_types[i] != TerrainData.Surface.WATER \
				and data.surface_types[data.index(neighbor)] == TerrainData.Surface.WATER
		if drop == 0 and not shore:
			continue
		var normal := Vector2(TerrainData.DIRECTIONS[d])
		var tangent := Vector2(-normal.y, normal.x)
		var edge: Vector2 = rect.get_center() + normal * CELL_PIXELS * 0.5
		# Make the face legible even at the Lab's fit-to-map zoom.  It is still
		# presentation-only geometry; the standing cell remains a 64px square.
		# A cliff face owns the entire low-side cell.  The ground platform stays
		# exactly one 64px cell; only its presentation face extends into the
		# neighbouring low cell. Ramps retain their explicit opening spans.
		var depth: float = CELL_PIXELS if drop > 0 else 8.0
		# Low-side overlap stays below half a cell, leaving its standing centre clear.
		var cuts: Array[Vector2] = [Vector2(-32, 32)]
		if (data.ramp_edges[i] & (1 << d)) != 0:
			cuts = [Vector2(-32, -18), Vector2(18, 32)]
		for span: Vector2 in cuts:
			var a: Vector2 = edge + tangent * span.x
			var b: Vector2 = edge + tangent * span.y
			var upper: Color = Color("8c8974") if drop > 0 else Color("b9b78b")
			var lower: Color = Color("383d3c") if drop > 0 else Color("86b2b2")
			if drop > 0:
				_draw_cliff_texture(canvas, a, b, normal, depth)
				# Let the source art supply grass and stone detail; only add foot shade.
				canvas.draw_line(a + normal * depth, b + normal * depth, Color(0.035, 0.045, 0.04, 0.45), 2.0)
			else:
				canvas.draw_polygon(PackedVector2Array([a + normal * depth, b + normal * depth, b, a]),
					PackedColorArray([upper, upper, lower, lower]))
				canvas.draw_line(a, b, Color(0.88, 0.82, 0.54, 0.8), 2.0)
			canvas.draw_line(a + normal * depth, b + normal * depth, Color(0.12, 0.18, 0.17, 0.7), 2.0)

func _draw_cliff_texture(canvas: Node2D, a: Vector2, b: Vector2, normal: Vector2, depth: float) -> void:
	var tangent := (b - a).normalized()
	var length := a.distance_to(b)
	var midpoint := (a + b) * 0.5 + normal * depth * 0.5
	# The generated texture's grassy lip is at its top edge, which is the
	# high-side edge after rotating the strip toward the lower platform.
	canvas.draw_set_transform(midpoint, tangent.angle() + PI, Vector2.ONE)
	if cliff_texture != null:
		# Sample a straight interior strip. Never squash the entire source and
		# its end caps into each edge, or squeeze a full strip into ramp ends.
		var source_width: float = length * 4.0
		var source_x: float = 256.0 + fposmod(a.dot(tangent) * 4.0, 256.0)
		var source := Rect2(source_x, 120.0, source_width, 280.0)
		var light: float = 0.9 + normal.dot(Vector2(-0.08, 0.1))
		canvas.draw_texture_rect_region(cliff_texture, Rect2(-length * 0.5, -depth * 0.5, length, depth), source, Color(light, light, light, 1.0))
	else:
		canvas.draw_rect(Rect2(-length * 0.5, -depth * 0.5, length, depth), Color("45413c"), true)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_ramps(canvas: Node2D, cell: Vector2i, i: int) -> void:
	for d: int in range(4):
		if (data.ramp_edges[i] & (1 << d)) == 0:
			continue
		var neighbor: Vector2i = cell + TerrainData.DIRECTIONS[d]
		if data.height_levels[i] >= data.height_levels[data.index(neighbor)]:
			continue
		var axis := Vector2(TerrainData.DIRECTIONS[d])
		var side := Vector2(-axis.y, axis.x)
		var a: Vector2 = cell_center(cell) + axis * 13.0
		var b: Vector2 = cell_center(neighbor) - axis * 13.0
		canvas.draw_polygon(PackedVector2Array([a - side * 17, a + side * 17, b + side * 17, b - side * 17]),
			PackedColorArray([Color("747c58"), Color("747c58"), Color("b0bb82"), Color("b0bb82")]))
		var midpoint: Vector2 = (a + b) * 0.5
		canvas.draw_line(midpoint - axis * 9, midpoint + axis * 9, Color("e0e9b0"), 3.0)
		canvas.draw_polyline(PackedVector2Array([midpoint - side * 6, midpoint + axis * 9, midpoint + side * 6]), Color("e0e9b0"), 2.0)
