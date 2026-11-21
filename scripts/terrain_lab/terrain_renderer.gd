class_name TerrainRenderer
extends Node2D

const CELL_PIXELS: float = 64.0
const GRASS_TEXTURE_PERIOD: float = CELL_PIXELS * 20.0 # Five complete repeats per 100-cell Site.
const LayerScript = preload("res://scripts/terrain_lab/terrain_render_layer.gd")
const DISPLAY_SLICE_ROWS := 5
const DISPLAY_DETAIL_ROWS := 1
const DISPLAY_DETAIL_COLUMNS := 25
const DISPLAY_JOBS_PER_FRAME := 10
signal display_completed
var progressive_display := false # Opt in before _ready; RegionLab's fixed 100-row preview only.
var display_pending := false
var display_samples: Array[Dictionary] = []
var _display_slices: Array[Node2D] = []
var _display_jobs: Array[Array] = []
var _cliff_slice_batches: Dictionary = {}
var _ramp_shape_cache: Dictionary = {} # Local merged outlines only; no terrain or gameplay state.
var _display_generation := 0
var _display_next := 0
var _display_remaining := 0
var data: TerrainData
var debug_enabled: bool = false
var brush_enabled: bool = true
var layers: Array[Node2D] = []
var grass_texture: Texture2D
var cliff_texture: Texture2D
var water_texture: Texture2D
var sand_texture: Texture2D
var _ramp_texture: CanvasTexture
var _repeating_grass: CanvasTexture
var r3_render_profile_enabled := false # Formal-entry diagnostic only.
var r3_render_process_usec := 0
var r3_render_process_calls := 0

func _ready() -> void:
	grass_texture = _load_texture("res://assets/map/terrain_lab/terrain_lab_grass_v2.png")
	cliff_texture = _load_texture("res://assets/map/site/cliffs/cliff_face_inland_highres_v2.png")
	water_texture = _load_texture("res://assets/map/terrain_lab/terrain_lab_water_v2.png")
	sand_texture = _load_texture("res://assets/map/terrain_lab/terrain_lab_sand_v2.png")
	_ramp_texture = CanvasTexture.new()
	_ramp_texture.diffuse_texture = sand_texture
	_ramp_texture.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_repeating_grass = CanvasTexture.new()
	_repeating_grass.diffuse_texture = grass_texture
	_repeating_grass.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
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
	if progressive_display:
		# A fixed, reusable presentation pool; no terrain or gameplay state is copied.
		for kind: int in [0, 2, 1, 3]:
			var pass_parents: Array[Node2D] = [layers[kind]]
			if kind == 1:
				pass_parents.clear()
				# Preserve the original whole-map order even where shadows/faces
				# cross a row boundary: all shadows, faces, overlays, then lines.
				for pass_name: String in ["Shadows", "Faces", "Overlays", "Lines"]:
					var group := Node2D.new()
					group.name = pass_name
					layers[kind].add_child(group)
					pass_parents.append(group)
			var rows := DISPLAY_DETAIL_ROWS if kind == 3 else DISPLAY_SLICE_ROWS
			var columns := DISPLAY_DETAIL_COLUMNS if kind == 3 else 100
			for row: int in range(0, 100, rows):
				var job: Array[Node2D] = []
				for pass_index: int in range(pass_parents.size()):
					for column: int in range(0, 100, columns):
						var slice := Node2D.new()
						slice.set_script(LayerScript)
						slice.set("renderer", self)
						slice.set("kind", kind)
						slice.set("row_start", row)
						slice.set("row_end", mini(row + rows, 100))
						slice.set("column_start", column)
						slice.set("column_end", mini(column + columns, 100))
						slice.set("cliff_pass", pass_index if kind == 1 else -1)
						slice.set("paint_enabled", false)
						pass_parents[pass_index].add_child(slice)
						_display_slices.append(slice)
						job.append(slice)
				_display_jobs.append(job)
		set_process(true)

func _process(_delta: float) -> void:
	if not display_pending:
		return
	var started := Time.get_ticks_usec() if r3_render_profile_enabled else 0
	# Keep the heavier cliff jobs bounded; cached surface/detail work can finish sooner.
	var jobs_this_frame := DISPLAY_JOBS_PER_FRAME
	if _display_next < _display_jobs.size() and int(_display_jobs[_display_next][0].get("kind")) != 1:
		jobs_this_frame *= 2
	for _part: int in range(jobs_this_frame):
		if _display_next >= _display_jobs.size():
			break
		var job: Array = _display_jobs[_display_next]
		_display_next += 1
		for slice: Node2D in job:
			slice.set("paint_enabled", true)
			slice.queue_redraw()
	if r3_render_profile_enabled:
		r3_render_process_usec += Time.get_ticks_usec() - started
		r3_render_process_calls += 1

func slice_submitted(slice: Node2D, generation: int, elapsed_usec: int) -> void:
	if not display_pending or generation != _display_generation \
			or int(slice.get("submitted_generation")) == generation:
		return
	slice.set("submitted_generation", generation)
	display_samples.append({"kind": int(slice.get("kind")), "row_start": int(slice.get("row_start")),
		"row_end": int(slice.get("row_end")), "column_start": int(slice.get("column_start")),
		"column_end": int(slice.get("column_end")), "cliff_pass": int(slice.get("cliff_pass")), "usec": elapsed_usec})
	_display_remaining -= 1
	if _display_remaining == 0:
		display_pending = false
		display_completed.emit()

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
	_ramp_shape_cache.clear()
	if progressive_display:
		_display_generation += 1
		_display_next = 0
		_display_remaining = _display_slices.size() if data != null else 0
		display_pending = _display_remaining > 0
		display_samples.clear()
		_cliff_slice_batches.clear()
		for slice: Node2D in _display_slices:
			slice.set("generation", _display_generation)
			slice.set("paint_enabled", false)
			RenderingServer.canvas_item_clear(slice.get_canvas_item())
			slice.queue_redraw() # Clear the prior Site's retained commands, including cancelled work.
	for layer: Node2D in layers:
		layer.queue_redraw()

func cell_center(terrain_cell: Vector2i) -> Vector2:
	return (Vector2(terrain_cell) + Vector2.ONE * 0.5) * CELL_PIXELS

func pick_cell(viewport_position: Vector2) -> Vector2i:
	var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * viewport_position
	return Vector2i(floori(local.x / CELL_PIXELS), floori(local.y / CELL_PIXELS))

func draw_layer(canvas: Node2D, kind: int, row_start: int = -1, row_end: int = -1, cliff_pass: int = -1, column_start: int = -1, column_end: int = -1) -> void:
	if data == null or (progressive_display and row_start < 0):
		return
	if kind == 0:
		_draw_ground(canvas, row_start, row_end)
		return
	if kind == 1:
		var batch_cliffs: bool = not debug_enabled and get_script() == TerrainRenderer and data.get_script() == TerrainData
		if batch_cliffs:
			_draw_cliffs_batched(canvas, row_start, row_end, cliff_pass)
			return
	# Only merge consecutive brush primitives. Ramps and debug/custom renderers
	# retain their original painter order and callbacks.
	var batch_brushes: bool = kind == 3 and brush_enabled and not debug_enabled and get_script() == TerrainRenderer and data.get_script() == TerrainData
	var brush_points := PackedVector2Array()
	var brush_indices := PackedInt32Array()
	for y: int in range(maxi(row_start, 0), data.size.y if row_end < 0 else mini(row_end, data.size.y)):
		for x: int in range(maxi(column_start, 0), data.size.x if column_end < 0 else mini(column_end, data.size.x)):
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
						if not brush_enabled:
							_draw_ramps(canvas, cell, i)
							continue
						# Brush marks are surface variation, not trees, stones or resources.
						var shade: float = float(data.detail_variation[i]) / 255.0
						var dot: Vector2 = rect.position + Vector2(22.0 + shade * 18.0, 24.0 + fmod(shade * 73.0, 16.0))
						if batch_brushes:
							var end := dot + Vector2(7.0, -2.0)
							# Match the original non-antialiased width-2 line quad.
							var offset := (dot - end).orthogonal().normalized() * 2.0 * 0.5
							var first := brush_points.size()
							brush_points.append_array(PackedVector2Array([dot + offset, dot - offset, end - offset, end + offset]))
							brush_indices.append_array(PackedInt32Array([first, first + 1, first + 2, first, first + 2, first + 3]))
							if data.ramp_edges[i] != 0:
								_draw_brush_batch(canvas, brush_points, brush_indices)
								brush_points.clear()
								brush_indices.clear()
								_draw_ramps(canvas, cell, i)
						else:
							canvas.draw_line(dot, dot + Vector2(7.0, -2.0), Color(1.0, 1.0, 0.8, 0.09), 2.0)
							_draw_ramps(canvas, cell, i)
					if debug_enabled:
						canvas.draw_rect(rect, Color(0.06, 0.1, 0.08, 0.3), false, 1.0)
						canvas.draw_string(ThemeDB.fallback_font, rect.position + Vector2(5.0, 21.0), str(data.height_levels[i]), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.9))
	_draw_brush_batch(canvas, brush_points, brush_indices)

func _draw_brush_batch(canvas: Node2D, points: PackedVector2Array, indices: PackedInt32Array) -> void:
	if not points.is_empty():
		RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, points, PackedColorArray([Color(1.0, 1.0, 0.8, 0.09)]))

func _draw_ground(canvas: Node2D, row_start: int = -1, row_end: int = -1) -> void:
	var map_rect := Rect2(Vector2.ZERO, Vector2(data.size) * CELL_PIXELS)
	# One original full-map base under every row's overlays; later slices must
	# not repaint grass over already submitted terrain or restart its UVs.
	if row_start <= 0:
		if grass_texture != null:
			var source := Rect2(Vector2.ZERO, map_rect.size / GRASS_TEXTURE_PERIOD * grass_texture.get_size())
			canvas.draw_texture_rect_region(_repeating_grass, map_rect, source, Color(1.0, 1.0, 1.0, 0.96), false, false)
		else:
			canvas.draw_rect(map_rect, Color("65854e"), true)
	for y: int in range(maxi(row_start, 0), data.size.y if row_end < 0 else mini(row_end, data.size.y)):
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
		for span: Vector2 in _cliff_spans(cell, d):
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

func _draw_cliffs_batched(canvas: Node2D, row_start: int = -1, row_end: int = -1, cliff_pass: int = -1) -> void:
	var slice_key := Vector2i(row_start, row_end)
	if cliff_pass >= 0 and _cliff_slice_batches.has(slice_key):
		_submit_cliff_batch(canvas, _cliff_slice_batches[slice_key], cliff_pass)
		if cliff_pass == 3:
			_cliff_slice_batches.erase(slice_key)
		return
	var shadow_points := PackedVector2Array()
	var shadow_colors := PackedColorArray()
	var shadow_indices := PackedInt32Array()

	var face_points := PackedVector2Array()
	var face_colors := PackedColorArray()
	var face_uvs := PackedVector2Array()
	var face_indices := PackedInt32Array()

	var overlay_points := PackedVector2Array()
	var overlay_colors := PackedColorArray()
	var overlay_indices := PackedInt32Array()

	var line_points := PackedVector2Array()
	var line_colors := PackedColorArray()
	var line_indices := PackedInt32Array()

	var tex_size := cliff_texture.get_size() if cliff_texture != null else Vector2(1024.0, 512.0)
	var tex_inv_w: float = 1.0 / tex_size.x
	var tex_inv_h: float = 1.0 / tex_size.y

	for y: int in range(maxi(row_start, 0), data.size.y if row_end < 0 else mini(row_end, data.size.y)):
		for x: int in range(data.size.x):
			var cell := Vector2i(x, y)
			var i: int = data.index(cell)
			var rect := Rect2(Vector2(cell) * CELL_PIXELS, Vector2.ONE * CELL_PIXELS)
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
				var depth: float = CELL_PIXELS if drop > 0 else 8.0
				for span: Vector2 in _cliff_spans(cell, d):
					var a: Vector2 = edge + tangent * span.x
					var b: Vector2 = edge + tangent * span.y
					var upper: Color = Color("8c8974") if drop > 0 else Color("b9b78b")
					var lower: Color = Color("383d3c") if drop > 0 else Color("86b2b2")
					if drop > 0:
						var foot_a := a + normal * depth
						var foot_b := b + normal * depth
						# 1. Contact shadow quad
						var s_idx: int = shadow_points.size()
						shadow_points.append(foot_a)
						shadow_points.append(foot_b)
						shadow_points.append(foot_b + normal * 10.0)
						shadow_points.append(foot_a + normal * 10.0)
						shadow_colors.append(Color(0.04, 0.07, 0.04, 0.42))
						shadow_colors.append(Color(0.04, 0.07, 0.04, 0.42))
						shadow_colors.append(Color(0.04, 0.07, 0.04, 0.0))
						shadow_colors.append(Color(0.04, 0.07, 0.04, 0.0))
						shadow_indices.append(s_idx)
						shadow_indices.append(s_idx + 1)
						shadow_indices.append(s_idx + 2)
						shadow_indices.append(s_idx)
						shadow_indices.append(s_idx + 2)
						shadow_indices.append(s_idx + 3)

						# 2. Textured cliff face quad
						var length := a.distance_to(b)
						var f_idx: int = face_points.size()
						face_points.append(b)
						face_points.append(a)
						face_points.append(foot_a)
						face_points.append(foot_b)
						if cliff_texture != null:
							var source_width: float = length * 4.0
							var source_x: float = 256.0 + fposmod(a.dot(tangent) * 4.0, 256.0)
							var light: float = 1.08 + normal.dot(Vector2(-0.14, -0.18))
							var col := Color(light, light, light, 1.0)
							face_colors.append(col)
							face_colors.append(col)
							face_colors.append(col)
							face_colors.append(col)
							face_uvs.append(Vector2(source_x * tex_inv_w, 120.0 * tex_inv_h))
							face_uvs.append(Vector2((source_x + source_width) * tex_inv_w, 120.0 * tex_inv_h))
							face_uvs.append(Vector2((source_x + source_width) * tex_inv_w, 400.0 * tex_inv_h))
							face_uvs.append(Vector2(source_x * tex_inv_w, 400.0 * tex_inv_h))
						else:
							var col := Color("45413c")
							face_colors.append(col)
							face_colors.append(col)
							face_colors.append(col)
							face_colors.append(col)
							face_uvs.append(Vector2.ZERO)
							face_uvs.append(Vector2.ZERO)
							face_uvs.append(Vector2.ZERO)
							face_uvs.append(Vector2.ZERO)
						face_indices.append(f_idx)
						face_indices.append(f_idx + 1)
						face_indices.append(f_idx + 2)
						face_indices.append(f_idx)
						face_indices.append(f_idx + 2)
						face_indices.append(f_idx + 3)

						# 3. Shading overlay quad
						var o_idx: int = overlay_points.size()
						overlay_points.append(a)
						overlay_points.append(b)
						overlay_points.append(foot_b)
						overlay_points.append(foot_a)
						overlay_colors.append(Color(0.95, 0.88, 0.65, 0.08))
						overlay_colors.append(Color(0.95, 0.88, 0.65, 0.08))
						overlay_colors.append(Color(0.025, 0.045, 0.045, 0.30))
						overlay_colors.append(Color(0.025, 0.045, 0.045, 0.30))
						overlay_indices.append(o_idx)
						overlay_indices.append(o_idx + 1)
						overlay_indices.append(o_idx + 2)
						overlay_indices.append(o_idx)
						overlay_indices.append(o_idx + 2)
						overlay_indices.append(o_idx + 3)

						# 4. Lines: lip line, lip polyline, strata lines
						_append_line_quad(line_points, line_colors, line_indices, a + normal * 1.5, b + normal * 1.5, Color(0.09, 0.12, 0.06, 0.9), 5.0)
						var lip_col := Color(0.69, 0.73, 0.47, 0.78)
						var lip_pts := [
							a,
							a.lerp(b, 0.2) - normal * 1.1,
							a.lerp(b, 0.4) + normal * 0.3,
							a.lerp(b, 0.6) - normal * 1.4,
							a.lerp(b, 0.8) - normal * 0.5,
							b
						]
						for seg: int in range(5):
							_append_line_quad(line_points, line_colors, line_indices, lip_pts[seg], lip_pts[seg + 1], lip_col, 2.0)

						for level: int in range(1, drop):
							var band := normal * depth * float(level) / float(drop)
							_append_line_quad(line_points, line_colors, line_indices, a + band, b + band, Color(0.04, 0.05, 0.04, 0.65), 3.0)
							_append_line_quad(line_points, line_colors, line_indices, a + band - normal * 2.0, b + band - normal * 2.0, Color(0.72, 0.73, 0.62, 0.4), 1.5)
					else:
						# Shore face quad
						var o_idx: int = overlay_points.size()
						overlay_points.append(a + normal * depth)
						overlay_points.append(b + normal * depth)
						overlay_points.append(b)
						overlay_points.append(a)
						overlay_colors.append(upper)
						overlay_colors.append(upper)
						overlay_colors.append(lower)
						overlay_colors.append(lower)
						overlay_indices.append(o_idx)
						overlay_indices.append(o_idx + 1)
						overlay_indices.append(o_idx + 2)
						overlay_indices.append(o_idx)
						overlay_indices.append(o_idx + 2)
						overlay_indices.append(o_idx + 3)

						_append_line_quad(line_points, line_colors, line_indices, a, b, Color(0.88, 0.82, 0.54, 0.8), 2.0)

					# Foot line for all cliffs
					_append_line_quad(line_points, line_colors, line_indices, a + normal * depth, b + normal * depth, Color(0.12, 0.18, 0.17, 0.7), 2.0)

	if cliff_pass < 0:
		# Keep the original default renderer's submission path and ordering.
		var ci := canvas.get_canvas_item()
		if not shadow_points.is_empty():
			RenderingServer.canvas_item_add_triangle_array(ci, shadow_indices, shadow_points, shadow_colors)
		if not face_points.is_empty():
			RenderingServer.canvas_item_add_triangle_array(ci, face_indices, face_points, face_colors, face_uvs, PackedInt32Array(), PackedFloat32Array(), cliff_texture.get_rid() if cliff_texture != null else RID())
		if not overlay_points.is_empty():
			RenderingServer.canvas_item_add_triangle_array(ci, overlay_indices, overlay_points, overlay_colors)
		if not line_points.is_empty():
			RenderingServer.canvas_item_add_triangle_array(ci, line_indices, line_points, line_colors)
		return
	var batch := {"shadow_points": shadow_points, "shadow_colors": shadow_colors, "shadow_indices": shadow_indices,
		"face_points": face_points, "face_colors": face_colors, "face_uvs": face_uvs, "face_indices": face_indices,
		"overlay_points": overlay_points, "overlay_colors": overlay_colors, "overlay_indices": overlay_indices,
		"line_points": line_points, "line_colors": line_colors, "line_indices": line_indices}
	_cliff_slice_batches[slice_key] = batch
	_submit_cliff_batch(canvas, batch, cliff_pass)
	if cliff_pass == 3:
		_cliff_slice_batches.erase(slice_key)

func _submit_cliff_batch(canvas: Node2D, batch: Dictionary, cliff_pass: int) -> void:
	var ci := canvas.get_canvas_item()
	if cliff_pass == 0 and not batch.shadow_points.is_empty():
		RenderingServer.canvas_item_add_triangle_array(ci, batch.shadow_indices, batch.shadow_points, batch.shadow_colors)
	if cliff_pass == 1 and not batch.face_points.is_empty():
		RenderingServer.canvas_item_add_triangle_array(ci, batch.face_indices, batch.face_points, batch.face_colors, batch.face_uvs, PackedInt32Array(), PackedFloat32Array(), cliff_texture.get_rid() if cliff_texture != null else RID())
	if cliff_pass == 2 and not batch.overlay_points.is_empty():
		RenderingServer.canvas_item_add_triangle_array(ci, batch.overlay_indices, batch.overlay_points, batch.overlay_colors)
	if cliff_pass == 3 and not batch.line_points.is_empty():
		RenderingServer.canvas_item_add_triangle_array(ci, batch.line_indices, batch.line_points, batch.line_colors)

static func _append_line_quad(
	points: PackedVector2Array,
	colors: PackedColorArray,
	indices: PackedInt32Array,
	from: Vector2,
	to: Vector2,
	col: Color,
	width: float
) -> void:
	var delta := to - from
	var offset := delta.orthogonal().normalized() * (width * 0.5)
	var first: int = points.size()
	points.append(from + offset)
	points.append(from - offset)
	points.append(to - offset)
	points.append(to + offset)
	colors.append(col)
	colors.append(col)
	colors.append(col)
	colors.append(col)
	indices.append(first)
	indices.append(first + 1)
	indices.append(first + 2)
	indices.append(first)
	indices.append(first + 2)
	indices.append(first + 3)


static func ramp_span(terrain: TerrainData, cell: Vector2i, direction: int) -> Vector2:
	# Reject stale natural ramp flags, then use the original bounded entrance and cliff shoulders.
	if str(terrain.parameters.get("composition", "")) == "fixed_geography":
		var here := terrain.index(cell)
		var adjacent := cell + TerrainData.DIRECTIONS[direction]
		if terrain.surface_types[here] == TerrainData.Surface.WATER or (terrain.ramp_edges[here] & (1 << direction)) == 0:
			return Vector2.ZERO
		if terrain.contains(adjacent):
			var other := terrain.index(adjacent)
			if terrain.surface_types[other] == TerrainData.Surface.WATER \
					or absi(int(terrain.height_levels[here]) - int(terrain.height_levels[other])) != 1 \
					or (terrain.ramp_edges[other] & (1 << ((direction + 2) % 4))) == 0:
				return Vector2.ZERO
		else:
			var halo: Dictionary = terrain.parameters.get("ramp_visual_halo", {})
			var sample: Array = halo.get("%d:%d" % [adjacent.x, adjacent.y], [])
			if sample.size() != 2 or int(sample[1]) != 0 or absi(int(sample[0]) - int(terrain.height_levels[here])) != 1:
				return Vector2.ZERO
		# A sparse natural pass is one bounded entrance. Height-only halo evidence
		# cannot prove that a parallel neighbour was selected as another pass.
		return Vector2(-18.0, 18.0)
	# The same opening serves the slope surface and both cliff submission paths.
	var span := Vector2(-18.0, 18.0)
	var i := terrain.index(cell)
	var normal: Vector2i = TerrainData.DIRECTIONS[direction]
	var tangent := Vector2i(-normal.y, normal.x)
	for side: int in [-1, 1]:
		var adjacent := cell + tangent * side
		if not terrain.contains(adjacent):
			var halo: Dictionary = terrain.parameters.get("ramp_visual_halo", {})
			var beyond := adjacent + normal
			var start: Array = halo.get("%d:%d" % [adjacent.x, adjacent.y], [])
			var end: Array = halo.get("%d:%d" % [beyond.x, beyond.y], [])
			var other_level := int(terrain.height_levels[i]) + (-1 if terrain.cliff_drops[i * 4 + direction] > 0 else 1)
			if start.size() == 2 and end.size() == 2 and int(start[1]) == 0 and int(end[1]) == 0 \
					and int(start[0]) == int(terrain.height_levels[i]) and int(end[0]) == other_level:
				if side < 0:
					span.x = -CELL_PIXELS * 0.5
				else:
					span.y = CELL_PIXELS * 0.5
			continue
		var other := terrain.index(adjacent)
		if terrain.height_levels[other] == terrain.height_levels[i] \
				and terrain.surface_types[other] != TerrainData.Surface.WATER \
				and (terrain.ramp_edges[other] & (1 << direction)) != 0 \
				and terrain.cliff_drops[other * 4 + direction] == terrain.cliff_drops[i * 4 + direction]:
			if side < 0:
				span.x = -CELL_PIXELS * 0.5
			else:
				span.y = CELL_PIXELS * 0.5
	return span

func _cliff_spans(cell: Vector2i, direction: int) -> Array[Vector2]:
	if (data.ramp_edges[data.index(cell)] & (1 << direction)) == 0:
		return [Vector2(-32, 32)]
	var opening := ramp_span(data, cell, direction)
	if opening == Vector2.ZERO:
		return [Vector2(-32, 32)]
	var spans: Array[Vector2] = []
	if opening.x > -32.0:
		spans.append(Vector2(-32.0, opening.x))
	if opening.y < 32.0:
		spans.append(Vector2(opening.y, 32.0))
	return spans

func _draw_ramps(canvas: Node2D, cell: Vector2i, i: int) -> void:
	if data.ramp_edges[i] == 0:
		return
	var spans: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var ramp_mask := 0
	var shape_key := 0
	var approaches: Array[bool] = [false, false, false, false]
	for d: int in range(4):
		if (data.ramp_edges[i] & (1 << d)) == 0:
			continue
		var span := ramp_span(data, cell, d)
		if span == Vector2.ZERO:
			continue
		ramp_mask |= 1 << d
		spans[d] = span
		var opposite := cell - TerrainData.DIRECTIONS[d]
		var blocked_behind := false
		if data.contains(opposite):
			var behind := data.index(opposite)
			blocked_behind = data.height_levels[behind] > data.height_levels[i] \
				and ((data.ramp_edges[behind] & (1 << d)) == 0 \
				or int(data.height_levels[behind]) - int(data.height_levels[i]) > 1 \
				or (data.ramp_edges[i] & (1 << ((d + 2) % 4))) == 0)
		else:
			var halo: Dictionary = data.parameters.get("ramp_visual_halo", {})
			var sample: Array = halo.get("%d:%d" % [opposite.x, opposite.y], [])
			blocked_behind = sample.size() == 2 and int(sample[0]) > int(data.height_levels[i]) \
				and (int(sample[0]) - int(data.height_levels[i]) > 1 \
				or (data.ramp_edges[i] & (1 << ((d + 2) % 4))) == 0)
		approaches[d] = data.cliff_drops[i * 4 + d] == 0 and not blocked_behind
		if approaches[d]:
			shape_key |= 1 << (12 + d) # Lower approach reaches the foot of the existing cliff.
		# ramp_span only extends a side from 18 to 32 px; these bits fully
		# identify local geometry without involving height, water, or map origin.
		if progressive_display and span.x == -CELL_PIXELS * 0.5:
			shape_key |= 1 << (4 + d * 2)
		if progressive_display and span.y == CELL_PIXELS * 0.5:
			shape_key |= 1 << (5 + d * 2)
	if ramp_mask == 0:
		return
	shape_key |= ramp_mask
	var outline: PackedVector2Array
	if progressive_display and _ramp_shape_cache.has(shape_key):
		outline = _ramp_shape_cache[shape_key]
	else:
		# Union the arms once per local shape so turns have one surface.
		var hub_min := Vector2(-18, -18)
		var hub_max := Vector2(18, 18)
		var arms: Array[PackedVector2Array] = []
		for d: int in range(4):
			if (ramp_mask & (1 << d)) == 0:
				continue
			var axis := Vector2(TerrainData.DIRECTIONS[d])
			var side := Vector2(-axis.y, axis.x)
			var shape_span: Vector2 = spans[d]
			var edge := axis * CELL_PIXELS * 0.5
			# On the low side, fill the original gap all the way to the cliff foot.
			# On the high side, keep the short landing blending into the terrace.
			var approach := -edge if approaches[d] else Vector2.ZERO
			arms.append(PackedVector2Array([approach + side * shape_span.x, approach + side * shape_span.y,
				edge + side * shape_span.y, edge + side * shape_span.x]))
			# A parallel band shares its landing too, not just its outer half.
			hub_min = hub_min.min(side * shape_span.x).min(side * shape_span.y)
			hub_max = hub_max.max(side * shape_span.x).max(side * shape_span.y)
		outline = PackedVector2Array([hub_min, Vector2(hub_max.x, hub_min.y), hub_max, Vector2(hub_min.x, hub_max.y)])
		for arm: PackedVector2Array in arms:
			outline = Geometry2D.merge_polygons(outline, arm)[0]
		outline = _round_ramp_shoulders(outline)
		# Keep the centre of a shared side fully opaque while its closed end fades.
		var rim := PackedVector2Array()
		for vertex: int in range(outline.size()):
			var a := outline[vertex]
			var b := outline[(vertex + 1) % outline.size()]
			rim.append(a)
			if is_equal_approx(a.x, b.x) and a.y * b.y < 0.0:
				rim.append(Vector2(a.x, 0.0))
			elif is_equal_approx(a.y, b.y) and a.x * b.x < 0.0:
				rim.append(Vector2(0.0, a.y))
		outline = rim
		if progressive_display:
			_ramp_shape_cache[shape_key] = outline
	var center := cell_center(cell)
	# The existing exposed-earth art makes the traversable incline legible
	# between the unchanged stone shoulders. This is presentation only.
	var surface_texture: Texture2D = sand_texture
	var repeating_texture: CanvasTexture = _ramp_texture
	var period := CELL_PIXELS * 4.0
	var texture_center := Vector2(fposmod(center.x, period), fposmod(center.y, period))
	var points := PackedVector2Array([center])
	var colors := PackedColorArray([_ramp_vertex_color(i, Vector2.ZERO, ramp_mask)])
	var uvs := PackedVector2Array([texture_center / period])
	var indices := PackedInt32Array()
	for point: Vector2 in outline:
		# An opaque interior and narrow soft shoulder read as one inclined
		# surface, rather than a transparent fan darkening most of each tile.
		var inner := point * 0.72
		points.append(center + inner)
		points.append(center + point)
		colors.append(_ramp_vertex_color(i, inner, ramp_mask))
		uvs.append((texture_center + inner) / period)
		var tint := _ramp_vertex_color(i, point, ramp_mask)
		# Fade only closed shoulders. Shared cell edges remain fully connected.
		tint.a = 0.0
		for d: int in range(4):
			if (ramp_mask & (1 << d)) == 0:
				continue
			var axis := Vector2(TerrainData.DIRECTIONS[d])
			var along := point.dot(axis)
			if is_equal_approx(along, CELL_PIXELS * 0.5):
				tint.a = 1.0
			var across := point.dot(Vector2(-axis.y, axis.x))
			var span := spans[d]
			if is_equal_approx(across, -32.0) and span.x == -32.0 or is_equal_approx(across, 32.0) and span.y == 32.0:
				tint.a = maxf(tint.a, clampf(1.0 + along / 18.0, 0.0, 1.0))
		colors.append(tint)
		uvs.append((texture_center + point) / period)
	for vertex: int in range(outline.size()):
		var inside := vertex * 2 + 1
		var following := ((vertex + 1) % outline.size()) * 2 + 1
		indices.append_array(PackedInt32Array([0, inside, following,
			inside, inside + 1, following + 1, inside, following + 1, following]))
	RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, points, colors, uvs,
		PackedInt32Array(), PackedFloat32Array(), repeating_texture.get_rid() if surface_texture != null else RID())

static func _round_ramp_shoulders(outline: PackedVector2Array) -> PackedVector2Array:
	var area := 0.0
	for vertex: int in range(outline.size()):
		area += outline[vertex].cross(outline[(vertex + 1) % outline.size()])
	var rounded := PackedVector2Array()
	for vertex: int in range(outline.size()):
		var point := outline[vertex]
		var previous := outline[(vertex - 1 + outline.size()) % outline.size()]
		var following := outline[(vertex + 1) % outline.size()]
		# Shared map edges and concave junctions must keep their exact opening.
		if absf(point.x) >= CELL_PIXELS * 0.5 or absf(point.y) >= CELL_PIXELS * 0.5 \
				or (point - previous).cross(following - point) * area <= 0.0:
			rounded.append(point)
			continue
		var radius := minf(8.0, minf(point.distance_to(previous), point.distance_to(following)) * 0.25)
		var entry := point.move_toward(previous, radius)
		var exit_point := point.move_toward(following, radius)
		rounded.append(entry)
		rounded.append((entry + point * 2.0 + exit_point) * 0.25)
		rounded.append(exit_point)
	return rounded

func _ramp_vertex_color(i: int, point: Vector2, ramp_mask: int = -1) -> Color:
	if ramp_mask < 0:
		ramp_mask = int(data.ramp_edges[i])
	var tint := _ramp_tint(_ramp_point_level(i, point, ramp_mask))
	var light := ramp_light(data, i, point, ramp_mask)
	var landing := 0.0
	var count := 0
	var reach := 0.0
	for d: int in range(4):
		if (ramp_mask & (1 << d)) == 0:
			continue
		landing += 1.0 if data.cliff_drops[i * 4 + d] > 0 else -1.0
		count += 1
		reach = maxf(reach, point.dot(Vector2(TerrainData.DIRECTIONS[d])) / (CELL_PIXELS * 0.5))
	# A darker foot and lighter upper landing reveal the rise. Both halves
	# meet at the same colour across the opening, including turns and Sites.
	light *= 1.0 + landing / float(maxi(count, 1)) * 0.12 * (1.0 - clampf(reach, 0.0, 1.0))
	return Color(tint.r * light, tint.g * light, tint.b * light, 1.0)

static func ramp_light(terrain: TerrainData, i: int, point: Vector2, ramp_mask: int = -1) -> float:
	if ramp_mask < 0:
		ramp_mask = int(terrain.ramp_edges[i])
	# Shared edges use the same uphill normal from either side. Blend toward
	# the landing normal inside a turn, rather than lighting each tile flat.
	var centre_gradient := Vector2.ZERO
	var gradient := Vector2.ZERO
	var edge_gradient := Vector2.ZERO
	var ramp_count := 0
	var edge_count := 0
	var weight := 0.0
	for d: int in range(4):
		if (ramp_mask & (1 << d)) == 0:
			continue
		var axis := Vector2(TerrainData.DIRECTIONS[d])
		var difference := -1.0 if terrain.cliff_drops[i * 4 + d] > 0 else 1.0
		var uphill := axis * difference
		var reach := maxf(0.0, point.dot(axis) / (CELL_PIXELS * 0.5))
		centre_gradient += uphill
		ramp_count += 1
		gradient += uphill * reach
		weight += reach
		if is_equal_approx(reach, 1.0):
			edge_gradient += uphill
			edge_count += 1
	if ramp_count == 0:
		return 1.0
	centre_gradient /= float(ramp_count)
	if edge_count > 0:
		gradient = edge_gradient / float(edge_count)
	elif weight > 0.0:
		gradient = centre_gradient.lerp(gradient / weight, minf(weight, 1.0))
	else:
		gradient = centre_gradient
	# Fixed north-west daylight reveals incline without arrows or changing
	# the authoritative height, ramp openings, picking, or actor positions.
	var normal := Vector3(-gradient.x, -gradient.y, 0.85).normalized()
	var sunlight := Vector3(-0.45, -0.65, 0.9).normalized()
	return clampf(0.90 + 0.20 * normal.dot(sunlight), 0.78, 1.10)

func _ramp_point_level(i: int, point: Vector2, ramp_mask: int = -1) -> float:
	if ramp_mask < 0:
		ramp_mask = int(data.ramp_edges[i])
	var change := 0.0
	var weight := 0.0
	var edge_change := 0.0
	var edge_count := 0
	for d: int in range(4):
		if (ramp_mask & (1 << d)) == 0:
			continue
		var reach := maxf(0.0, point.dot(Vector2(TerrainData.DIRECTIONS[d])) / (CELL_PIXELS * 0.5))
		var difference := -1.0 if data.cliff_drops[i * 4 + d] > 0 else 1.0
		change += difference * reach * 0.5
		weight += reach
		if is_equal_approx(reach, 1.0):
			edge_change += difference * 0.5
			edge_count += 1
	# A reciprocal edge meets at the same half-level even across a Site boundary.
	return float(data.height_levels[i]) + (edge_change / float(edge_count) if edge_count > 0 else change / maxf(1.0, weight))

static func _ramp_tint(level: float) -> Color:
	var light := 0.86 + level * 0.025
	return Color(light, light, light).lerp(Color(0.96, 0.91, 0.63), level * 0.04)
