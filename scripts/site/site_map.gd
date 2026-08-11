class_name SiteMap
extends Node2D

const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")

signal debug_state_changed(state: Dictionary)
signal move_requested(direction: Vector2i)

var runtime_snapshot: SiteRuntimeSnapshot
var site_texture: Texture2D

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func setup(p_runtime_snapshot: SiteRuntimeSnapshot) -> void:
	runtime_snapshot = p_runtime_snapshot
	site_texture = _build_layout_texture(runtime_snapshot.layout if runtime_snapshot != null else null)
	var camera: Camera2D = get_node_or_null("Camera2D") as Camera2D
	if camera != null and runtime_snapshot != null and runtime_snapshot.layout != null:
		camera.position = Vector2(runtime_snapshot.layout.bounds_meters.position) \
			+ Vector2(runtime_snapshot.layout.bounds_meters.size) * 0.5
		camera.zoom = Vector2(8.0, 8.0)
	queue_redraw()
	debug_state_changed.emit(get_debug_state())

func get_debug_state() -> Dictionary:
	if runtime_snapshot == null:
		return {"layer": "SITE MAP", "instruction": "Site snapshot unavailable"}
	var region_label: String = "World %s" % _format_cell(runtime_snapshot.parent_world_cell)
	if not runtime_snapshot.parent_region_name.is_empty():
		region_label = "%s (%s)" % [
			runtime_snapshot.parent_region_name,
			runtime_snapshot.parent_region_id,
		]
	return {
		"layer": "SITE MAP",
		"current_region": region_label,
		"world_seed": runtime_snapshot.world_seed,
		"world_time": _format_world_time(runtime_snapshot.world_time_seconds),
		"party_id": runtime_snapshot.party_id,
		"party_position": "Site %s / Global %s" % [
			_format_cell(runtime_snapshot.party_site_local_cell),
			_format_cell(runtime_snapshot.party_global_region_cell),
		] if SiteLayoutDataType.is_valid_cell(runtime_snapshot.party_site_local_cell) \
			else "Global %s" % _format_cell(runtime_snapshot.party_global_region_cell),
		"party_state": "At POI" if runtime_snapshot.party_at_site else "Away",
		"world_cell": _format_cell(runtime_snapshot.parent_world_cell),
		"hovered_region_cell": "??",
		"selected_region_cell": _format_cell(runtime_snapshot.parent_region_cell),
		"global_region_cell": _format_cell(runtime_snapshot.global_region_cell),
		"global_meter_position": _format_meters(runtime_snapshot.entrance_global_meters),
		"terrain_type": TerrainType.to_display_name(runtime_snapshot.source_terrain_type),
		"elevation": "%.2f" % runtime_snapshot.source_elevation,
		"moisture": "%.2f" % runtime_snapshot.source_moisture,
		"river_mask": "Yes" if runtime_snapshot.source_river_nearby else "No",
		"river_strength": "nearby" if runtime_snapshot.source_river_nearby else "0.00",
		"poi_id": runtime_snapshot.source_poi_id,
		"site_id": runtime_snapshot.site_id,
		"site_seed": runtime_snapshot.site_seed,
		"site_base_version": runtime_snapshot.base_generation_version,
		"site_entrance_local_meters": _format_meters(runtime_snapshot.entrance_local_meters),
		"site_entrance_global_meters": _format_meters(runtime_snapshot.entrance_global_meters),
		"site_layout_version": runtime_snapshot.layout.generation_version if runtime_snapshot.layout != null else 0,
		"site_layout_bounds": str(runtime_snapshot.layout.bounds_meters) if runtime_snapshot.layout != null else "unavailable",
		"site_layout_path_points": runtime_snapshot.layout.primary_path_meters.size() if runtime_snapshot.layout != null else 0,
		"site_layout_landmarks": runtime_snapshot.layout.landmark_points_meters.size() if runtime_snapshot.layout != null else 0,
		"site_revision": runtime_snapshot.revision,
		"site_runtime_allocated": runtime_snapshot.runtime_allocated,
		"site_test_flag": runtime_snapshot.architecture_test_flag,
		"site_feature_ids": _feature_ids(),
		"poi_type": WorldPOIType.to_display_name(runtime_snapshot.site_type),
		"poi_name": runtime_snapshot.site_name,
		"poi_candidate_cell": _format_cell(runtime_snapshot.source_candidate_cell),
		"poi_priority": "%.3f" % runtime_snapshot.source_priority,
		"poi_river_nearby": "Yes" if runtime_snapshot.source_river_nearby else "No",
		"site": "%s (%s)" % [
			runtime_snapshot.site_name,
			WorldPOIType.to_display_name(runtime_snapshot.site_type),
		],
		"instruction": "WASD / Arrows: Move   ESC / T: Return to Region Map"
	}

func _feature_ids() -> Array[String]:
	var ids: Array[String] = []
	for feature: SiteFeatureState in runtime_snapshot.added_features:
		if feature.enabled:
			ids.append(feature.feature_id)
	return ids

func _draw() -> void:
	if runtime_snapshot == null or runtime_snapshot.layout == null \
		or not runtime_snapshot.layout.is_valid():
		return
	var layout: SiteLayoutDataType = runtime_snapshot.layout
	var bounds: Rect2 = Rect2(Vector2(layout.bounds_meters.position), Vector2(layout.bounds_meters.size))
	draw_rect(bounds.grow(8.0), Color("211d2b"))
	if site_texture != null:
		draw_texture_rect(site_texture, bounds, false)
	else:
		draw_rect(bounds, TerrainType.to_color(runtime_snapshot.source_terrain_type).darkened(0.18))
	for grid: int in range(0, SiteLayoutDataType.GRID_SIZE.x + 1, 5):
		var grid_x: float = bounds.position.x + float(grid * SiteLayoutDataType.CELL_SIZE_METERS)
		var grid_y: float = bounds.position.y + float(grid * SiteLayoutDataType.CELL_SIZE_METERS)
		draw_line(Vector2(grid_x, bounds.position.y), Vector2(grid_x, bounds.end.y), Color(1.0, 1.0, 1.0, 0.10), 0.35)
		draw_line(Vector2(bounds.position.x, grid_y), Vector2(bounds.end.x, grid_y), Color(1.0, 1.0, 1.0, 0.10), 0.35)
	var path: PackedVector2Array = PackedVector2Array()
	for point: Vector2i in layout.primary_path_meters:
		path.append(Vector2(point))
	draw_polyline(path, Color("caa66b"), 3.0, true)
	var landmark_color: Color = WorldPOIType.to_color(runtime_snapshot.site_type).darkened(0.22)
	for point: Vector2i in layout.landmark_points_meters:
		draw_circle(Vector2(point), 3.0, landmark_color)
	draw_circle(Vector2(layout.hub_local_meters), 5.0, WorldPOIType.to_color(runtime_snapshot.site_type))
	draw_circle(Vector2(layout.entrance_local_meters), 2.0, Color("e8f0f2"))
	if SiteLayoutDataType.is_valid_cell(runtime_snapshot.party_site_local_cell):
		draw_circle(layout.cell_center_meters(runtime_snapshot.party_site_local_cell), 2.5, Color("ffe066"))

func _build_layout_texture(layout: SiteLayoutDataType) -> Texture2D:
	if layout == null or not layout.has_visual_base():
		return null
	var image: Image = Image.create(
		SiteLayoutDataType.GRID_SIZE.x,
		SiteLayoutDataType.GRID_SIZE.y,
		false,
		Image.FORMAT_RGBA8
	)
	for y: int in range(SiteLayoutDataType.GRID_SIZE.y):
		for x: int in range(SiteLayoutDataType.GRID_SIZE.x):
			var cell: Vector2i = Vector2i(x, y)
			var code: int = layout.visual_code_at(cell)
			image.set_pixel(x, y, SiteLayoutDataType.visual_color(code))
	return ImageTexture.create_from_image(image)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var direction: Vector2i = Vector2i.ZERO
	match key_event.keycode:
		KEY_W, KEY_UP:
			direction = Vector2i.UP
		KEY_A, KEY_LEFT:
			direction = Vector2i.LEFT
		KEY_S, KEY_DOWN:
			direction = Vector2i.DOWN
		KEY_D, KEY_RIGHT:
			direction = Vector2i.RIGHT
	if direction == Vector2i.ZERO:
		return
	move_requested.emit(direction)
	get_viewport().set_input_as_handled()

func _format_cell(cell: Vector2i) -> String:
	return "(%d, %d)" % [cell.x, cell.y]

func _format_meters(meters: Vector2i) -> String:
	return "(%dm, %dm)" % [meters.x, meters.y]

func _format_world_time(seconds: int) -> String:
	var day: int = floori(float(seconds) / 86400.0)
	var hour: int = floori(float(seconds % 86400) / 3600.0)
	var minute: int = floori(float(seconds % 3600) / 60.0)
	return "Day %d  %02d:%02d" % [day, hour, minute]
