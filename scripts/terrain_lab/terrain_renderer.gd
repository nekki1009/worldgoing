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
	# Water is a ground surface; it must not paint over shore or cliff faces.
	move_child(layers[2], 1)

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
			# Higher terraces get a warmer, lighter surface, distinct from the shaded face.
			var height: int = data.height_levels[i]
			if height > 0:
				canvas.draw_rect(rect, Color(0.96, 0.91, 0.63, minf(0.20, float(height) * 0.04)), true)

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
		# Retain the existing 64px low-side visual strip and the actual ramp opening.
		# Relief shading never changes the standing cells or their legal crossings.
		var depth: float = CELL_PIXELS if drop > 0 else 8.0
		var cuts: Array[Vector2] = [Vector2(-32, 32)]
		if (data.ramp_edges[i] & (1 << d)) != 0:
			cuts = [Vector2(-32, -18), Vector2(18, 32)]
		for span: Vector2 in cuts:
			var a: Vector2 = edge + tangent * span.x
			var b: Vector2 = edge + tangent * span.y
			var upper: Color = Color("8c8974") if drop > 0 else Color("b9b78b")
			var lower: Color = Color("383d3c") if drop > 0 else Color("86b2b2")
			if drop > 0:
				var foot_a := a + normal * depth
				var foot_b := b + normal * depth
				# Fade a narrow contact shadow onto the lower terrace, with the ramp gap intact.
				canvas.draw_polygon(PackedVector2Array([foot_a, foot_b, foot_b + normal * 10, foot_a + normal * 10]),
					PackedColorArray([Color(0.04, 0.07, 0.04, 0.42), Color(0.04, 0.07, 0.04, 0.42), Color(0.04, 0.07, 0.04, 0.0), Color(0.04, 0.07, 0.04, 0.0)]))
				_draw_cliff_texture(canvas, a, b, normal, depth)
				canvas.draw_polygon(PackedVector2Array([a, b, foot_b, foot_a]),
					PackedColorArray([Color(0.95, 0.88, 0.65, 0.08), Color(0.95, 0.88, 0.65, 0.08), Color(0.025, 0.045, 0.045, 0.30), Color(0.025, 0.045, 0.045, 0.30)]))
				# The bright high-side lip and dark underside identify which side is up.
				canvas.draw_line(a + normal * 1.5, b + normal * 1.5, Color(0.09, 0.12, 0.06, 0.9), 5.0)
				var lip := PackedVector2Array([a, a.lerp(b, 0.2) - normal * 1.1, a.lerp(b, 0.4) + normal * 0.3,
					a.lerp(b, 0.6) - normal * 1.4, a.lerp(b, 0.8) - normal * 0.5, b])
				canvas.draw_polyline(lip, Color(0.69, 0.73, 0.47, 0.78), 2.0, true)
				# Multi-level drops carry strata inside the same face, never a false walkable shelf.
				for level: int in range(1, drop):
					var band := normal * depth * float(level) / float(drop)
					canvas.draw_line(a + band, b + band, Color(0.04, 0.05, 0.04, 0.65), 3.0)
					canvas.draw_line(a + band - normal * 2, b + band - normal * 2, Color(0.72, 0.73, 0.62, 0.4), 1.5)
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
		var light: float = 1.08 + normal.dot(Vector2(-0.14, -0.18))
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
		var a: Vector2 = cell_center(cell) - axis * 12.0
		var b: Vector2 = cell_center(neighbor) + axis * 8.0
		var ramp := PackedVector2Array([a - side * 16, a + side * 16, b + side * 16, b - side * 16])
		canvas.draw_polygon(ramp, PackedColorArray([Color("806b49"), Color("806b49"), Color("c3a678"), Color("c3a678")]))
		var midpoint: Vector2 = (a + b) * 0.5
		canvas.draw_set_transform(midpoint, axis.angle(), Vector2.ONE)
		_draw_texture_region(canvas, sand_texture, Rect2(-a.distance_to(b) * 0.5, -16, a.distance_to(b), 32), cell, Color(0.78, 0.64, 0.42, 0.76))
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		canvas.draw_line(a - side * 16, b - side * 16, Color(0.23, 0.22, 0.13, 0.6), 2.0)
		canvas.draw_line(a + side * 16, b + side * 16, Color(0.81, 0.72, 0.51, 0.65), 1.5)
		var arrow := PackedVector2Array([midpoint - side * 7, midpoint + axis * 10, midpoint + side * 7])
		canvas.draw_line(midpoint - axis * 10, midpoint + axis * 10, Color("493b24"), 5.0)
		canvas.draw_polyline(arrow, Color("493b24"), 5.0)
		canvas.draw_line(midpoint - axis * 10, midpoint + axis * 10, Color("fff0bc"), 2.5)
		canvas.draw_polyline(arrow, Color("fff0bc"), 2.5)
