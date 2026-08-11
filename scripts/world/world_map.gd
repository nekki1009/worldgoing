class_name WorldMap
extends Node2D

const GlobalTravelPathType = preload("res://scripts/data/global_travel_path.gd")
const TravelRuntimeType = preload("res://scripts/runtime/travel_runtime.gd")
const TravelFailureReasonType = preload("res://scripts/runtime/travel_failure_reason.gd")
const TravelStatusType = preload("res://scripts/runtime/travel_status.gd")

signal region_enter_requested(world_cell: Vector2i)
signal debug_state_changed(state: Dictionary)

const GRID_SIZE: Vector2i = WorldData.WORLD_CELLS
const CELL_PIXEL_SIZE: float = 64.0
const MAP_ORIGIN: Vector2 = Vector2(900, 400)
const CAMERA_SPEED: float = 900.0

@onready var camera: Camera2D = $Camera2D

var world_data: WorldData
var session: GameSession
var travel_runtime: TravelRuntime
var hovered_world_cell: Vector2i = Vector2i(-1, -1)
var selected_poi: WorldPOIData
var travel_preview: TravelPreviewResult
var preview_error: String = ""
var world_texture: Texture2D
var world_texture_rect: Rect2 = Rect2()
var world_texture_cells: Rect2i = Rect2i()

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func setup(p_world_data: WorldData, p_session: GameSession, p_runtime: TravelRuntime = null) -> void:
	world_data = p_world_data
	session = p_session
	travel_runtime = p_runtime if p_runtime != null else TravelRuntimeType.new(session, world_data)
	travel_runtime.bind(session, world_data)
	selected_poi = null
	travel_preview = null
	preview_error = ""
	world_texture = null
	world_texture_rect = Rect2()
	world_texture_cells = Rect2i()
	camera.position = MAP_ORIGIN + Vector2(GRID_SIZE.x, GRID_SIZE.y) * CELL_PIXEL_SIZE * 0.5
	camera.zoom = Vector2.ONE
	queue_redraw()
	debug_state_changed.emit(get_debug_state())

func _process(delta: float) -> void:
	if session == null:
		return
	var direction: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_W):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		direction.y += 1.0
	if direction != Vector2.ZERO:
		camera.position += direction.normalized() * CAMERA_SPEED * delta / camera.zoom.x

func _unhandled_input(event: InputEvent) -> void:
	if session == null:
		return
	if event is InputEventMouseMotion:
		_set_hovered_world_cell(_cell_from_global_position(get_global_mouse_position()))
		return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			_set_zoom(1.1)
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			_set_zoom(0.9)
			get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var world_cell: Vector2i = _cell_from_global_position(get_global_mouse_position())
			if _is_valid_world_cell(world_cell):
				selected_poi = _poi_at_map_position(get_global_mouse_position())
				if selected_poi != null:
					world_cell = selected_poi.world_cell
				session.selected_world_cell = world_cell
				queue_redraw()
				debug_state_changed.emit(get_debug_state())
				if mouse_event.double_click:
					region_enter_requested.emit(world_cell)
				get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_P:
			if session.is_traveling():
				return
			var destination_global_cell: Vector2i = selected_poi.global_region_cell \
				if selected_poi != null else travel_runtime.resolve_world_destination(session.selected_world_cell)
			travel_preview = travel_runtime.query_travel_preview(
					session.party.party_id,
					destination_global_cell,
					selected_poi.poi_id if selected_poi != null else ""
				)
			preview_error = "" if travel_preview.has_path() else TravelFailureReasonType.to_code(travel_preview.failure_reason)
			queue_redraw()
			debug_state_changed.emit(get_debug_state())
			get_viewport().set_input_as_handled()
			return
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ENTER:
			if travel_preview != null and travel_preview.has_path():
				var command: TravelCommandResult = travel_runtime.start_travel(
						session.party.party_id,
						travel_preview.destination_global_cell,
						travel_preview.destination_poi_id
					)
				if command.success:
					travel_preview = null
					preview_error = ""
				else:
					preview_error = TravelFailureReasonType.to_code(command.failure_reason)
				queue_redraw()
				debug_state_changed.emit(get_debug_state())
				get_viewport().set_input_as_handled()
				return
			if _is_valid_world_cell(session.selected_world_cell):
				region_enter_requested.emit(session.selected_world_cell)
				get_viewport().set_input_as_handled()
				return
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			if travel_preview != null:
				travel_preview = null
				preview_error = ""
				queue_redraw()
				debug_state_changed.emit(get_debug_state())
				get_viewport().set_input_as_handled()

func get_debug_state() -> Dictionary:
	var selected_region: RegionData = world_data.get_region(session.selected_world_cell)
	var region_label: String = "??"
	var terrain_type_name: String = "??"
	if selected_region != null:
		region_label = "%s (%s)" % [selected_region.region_name, selected_region.region_id]
		terrain_type_name = selected_region.terrain_type
		var thumbnail: PackedByteArray = world_data.get_or_generate_region_thumbnail(
			session.selected_world_cell,
			session.world_seed
		)
		if thumbnail.size() == RegionTerrainGenerator.THUMBNAIL_CELL_COUNT:
			var center_index: int = 4 * RegionTerrainGenerator.THUMBNAIL_GRID_SIZE + 4
			var packed_center: int = thumbnail[center_index]
			terrain_type_name = TerrainType.to_display_name(
				RegionTerrainGenerator.thumbnail_terrain(packed_center)
			)
			if RegionTerrainGenerator.thumbnail_has_river(packed_center):
				terrain_type_name = "River / %s" % terrain_type_name
	var active_path: GlobalTravelPathType = session.active_global_travel_path
	var party_global_cell: Vector2i = session.party.current_global_region_cell
	var party_global_meters: Vector2i = WorldCoordinates.global_region_cell_to_global_meters(party_global_cell)
	var path_distance: String = "None"
	var estimated_travel: String = "None"
	var path_cells: String = "0"
	var destination_global_cell: String = "None"
	var remaining_distance: String = "None"
	var remaining_eta: String = "None"
	var current_path_index: String = "0"
	var total_path_cells: String = "0"
	var remaining_path_cells: String = "0"
	var regions_crossed: String = "0"
	var path_search_time: String = "None"
	if travel_preview != null and travel_preview.has_path():
		path_distance = "%.3f km" % (travel_preview.total_distance_meters / 1000.0)
		estimated_travel = travel_preview.estimated_duration()
		path_cells = str(travel_preview.path.cells.size())
		destination_global_cell = _format_cell(travel_preview.destination_global_cell)
		regions_crossed = str(travel_preview.regions_crossed)
		path_search_time = "%.2f ms" % travel_preview.path.path_calculation_milliseconds
	if active_path != null:
		path_distance = "%.3f / %.3f km" % [
			active_path.total_distance_meters / 1000.0,
			active_path.remaining_distance_from(session.global_travel_path_index) / 1000.0,
		]
		estimated_travel = "%s / %s" % [
			active_path.estimated_duration(),
			active_path.remaining_duration_from(session.global_travel_path_index),
		]
		path_cells = "%d / %d" % [session.global_travel_path_index, active_path.cells.size()]
		destination_global_cell = _format_cell(active_path.destination_global_cell)
		remaining_distance = "%.3f km" % (active_path.remaining_distance_from(session.global_travel_path_index) / 1000.0)
		remaining_eta = active_path.remaining_duration_from(session.global_travel_path_index)
		current_path_index = str(session.global_travel_path_index)
		total_path_cells = str(active_path.cells.size())
		remaining_path_cells = str(maxi(active_path.cells.size() - session.global_travel_path_index - 1, 0))
		regions_crossed = str(active_path.regions_crossed)
		path_search_time = "%.2f ms" % active_path.path_calculation_milliseconds
	return {
		"layer": "WORLD MAP",
		"current_region": region_label,
		"world_seed": session.world_seed,
		"world_time": session.format_world_time(),
		"party_id": session.party.party_id,
		"party_position": "Global %s / Region %s" % [
			_format_cell(party_global_cell),
			_format_cell(session.party.get_region_cell()),
		],
		"party_state": "Moving" if session.is_traveling() else ("Ready" if session.party.initialized else "Not Spawned"),
		"world_cell": _format_cell(session.selected_world_cell),
		"hovered_region_cell": "??",
		"selected_region_cell": "??",
		"global_region_cell": _format_cell(party_global_cell),
		"global_meter_position": "(%dm, %dm)" % [party_global_meters.x, party_global_meters.y],
		"terrain_type": terrain_type_name,
		"site": "??",
		"destination": destination_global_cell,
		"destination_global_cell": destination_global_cell,
		"path_distance": path_distance,
		"remaining_distance": remaining_distance,
		"estimated_travel": estimated_travel,
		"remaining_eta": remaining_eta,
		"path_cells": path_cells,
		"current_path_index": current_path_index,
		"total_path_cells": total_path_cells,
		"remaining_path_cells": remaining_path_cells,
		"regions_crossed": regions_crossed,
		"travel_status": _travel_status_label(),
		"travel_error": preview_error if not preview_error.is_empty() else TravelFailureReasonType.to_code(session.travel_failure_reason),
		"travel_speed_multiplier": "%.0fx" % session.travel_speed_multiplier,
		"path_search_time": path_search_time,
		"poi_name": selected_poi.site_name if selected_poi != null else "No POI",
		"instruction": "WASD: Move   Wheel: Zoom   Left Click: Select Region/POI   P: Plan Travel   Enter: Confirm / Enter Region   1/2/3: Travel Speed"
	}

func _travel_status_label() -> String:
	match session.last_travel_status:
		TravelStatusType.Code.STARTED:
			return "Travel started"
		TravelStatusType.Code.CANCEL_REQUESTED:
			return "Travel cancelling"
		TravelStatusType.Code.CANCELLED:
			return "Travel cancelled"
		TravelStatusType.Code.ARRIVED:
			return "Arrived"
		TravelStatusType.Code.FAILED:
			return "Travel failed"
		_:
			return ""

func _draw() -> void:
	if world_data == null:
		return
	var map_size: Vector2 = Vector2(GRID_SIZE.x, GRID_SIZE.y) * CELL_PIXEL_SIZE
	draw_rect(Rect2(MAP_ORIGIN - Vector2(16, 16), map_size + Vector2(32, 32)), Color("18202a"))
	var visible_cells: Rect2i = _visible_world_cells()
	_ensure_world_texture(visible_cells)
	if world_texture != null:
		draw_texture_rect(world_texture, world_texture_rect, false)
	for y: int in range(visible_cells.position.y, visible_cells.end.y):
		for x: int in range(visible_cells.position.x, visible_cells.end.x):
			var world_cell: Vector2i = Vector2i(x, y)
			var cell_rect: Rect2 = Rect2(
				MAP_ORIGIN + Vector2(x, y) * CELL_PIXEL_SIZE,
				Vector2.ONE * CELL_PIXEL_SIZE
			)
			draw_rect(cell_rect, Color("283746"), false, 2.0)
			if world_cell == session.selected_world_cell:
				draw_rect(cell_rect, Color("ffe082"), false, 5.0)
			if world_cell == hovered_world_cell:
				draw_rect(cell_rect.grow(-5.0), Color("ffffff"), false, 3.0)
	_draw_party_marker()
	_draw_travel_preview()
	if selected_poi != null:
		var selected_position: Vector2 = _poi_map_position(selected_poi)
		draw_circle(selected_position, 9.0, Color("fff1a8"), false, 3.0)

func _ensure_world_texture(visible_cells: Rect2i) -> void:
	if world_data == null or session == null or visible_cells == world_texture_cells and world_texture != null:
		return
	var thumbnail_size: int = RegionTerrainGenerator.THUMBNAIL_GRID_SIZE
	var image: Image = Image.create(
		visible_cells.size.x * thumbnail_size,
		visible_cells.size.y * thumbnail_size,
		false,
		Image.FORMAT_RGBA8
	)
	for local_y: int in range(visible_cells.size.y):
		for local_x: int in range(visible_cells.size.x):
			var world_cell: Vector2i = visible_cells.position + Vector2i(local_x, local_y)
			var thumbnail: PackedByteArray = world_data.get_or_generate_region_thumbnail(
				world_cell,
				session.world_seed
			)
			for sub_y: int in range(thumbnail_size):
				for sub_x: int in range(thumbnail_size):
					var packed_cell: int = thumbnail[sub_y * thumbnail_size + sub_x]
					var color: Color = TerrainType.to_color(RegionTerrainGenerator.thumbnail_terrain(packed_cell))
					if RegionTerrainGenerator.thumbnail_has_river(packed_cell):
						color = Color("49a9cf")
					image.set_pixel(
						local_x * thumbnail_size + sub_x,
						local_y * thumbnail_size + sub_y,
						color
					)
			for poi: WorldPOIData in world_data.get_pois_for_region(world_cell, session.world_seed):
				var marker: Vector2i = Vector2i(
					local_x * thumbnail_size + clampi(poi.region_cell.x * thumbnail_size / WorldCoordinates.REGION_GRID_SIZE, 0, thumbnail_size - 1),
					local_y * thumbnail_size + clampi(poi.region_cell.y * thumbnail_size / WorldCoordinates.REGION_GRID_SIZE, 0, thumbnail_size - 1)
				)
				image.set_pixel(marker.x, marker.y, WorldPOIType.to_color(poi.poi_type))
	world_texture = ImageTexture.create_from_image(image)
	world_texture_cells = visible_cells
	world_texture_rect = Rect2(
		MAP_ORIGIN + Vector2(visible_cells.position) * CELL_PIXEL_SIZE,
		Vector2(visible_cells.size) * CELL_PIXEL_SIZE
	)

func _draw_party_marker() -> void:
	if not session.party.initialized:
		return
	var party_world_cell: Vector2i = session.party.get_world_cell()
	if not _is_valid_world_cell(party_world_cell):
		return
	var center: Vector2 = MAP_ORIGIN + Vector2(party_world_cell.x, party_world_cell.y) * CELL_PIXEL_SIZE + Vector2.ONE * CELL_PIXEL_SIZE * 0.5
	draw_circle(center, 10.0, Color("4f8cff"))
	draw_circle(center, 13.0, Color("d9e7ff"), false, 2.0)

func _draw_travel_preview() -> void:
	if travel_preview == null or not travel_preview.has_path():
		return
	var points: PackedVector2Array = PackedVector2Array()
	for global_cell: Vector2i in travel_preview.path.cells:
		points.append(_global_cell_map_position(global_cell))
	if points.size() >= 2:
		draw_polyline(points, Color("fff1a8"), 7.0, true)
	for point: Vector2 in points:
		draw_circle(point, 5.0, Color("fff7c2"))

func _poi_at_map_position(mouse_global_position: Vector2) -> WorldPOIData:
	var nearest: WorldPOIData
	var nearest_distance: float = 12.0
	var visible_cells: Rect2i = _visible_world_cells().grow(2)
	for y: int in range(visible_cells.position.y, visible_cells.end.y):
		for x: int in range(visible_cells.position.x, visible_cells.end.x):
			for poi: WorldPOIData in world_data.get_pois_for_region(Vector2i(x, y), session.world_seed):
				var distance: float = _poi_map_position(poi).distance_to(to_local(mouse_global_position))
				if distance < nearest_distance:
					nearest = poi
					nearest_distance = distance
	return nearest

func _poi_map_position(poi: WorldPOIData) -> Vector2:
	return MAP_ORIGIN + Vector2(poi.world_cell.x, poi.world_cell.y) * CELL_PIXEL_SIZE \
		+ (Vector2(poi.region_cell.x, poi.region_cell.y) + Vector2.ONE * 0.5) \
		* (CELL_PIXEL_SIZE / float(WorldCoordinates.REGION_GRID_SIZE))

func _global_cell_map_position(global_cell: Vector2i) -> Vector2:
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(global_cell)
	var world_cell: Vector2i = converted["world_cell"] as Vector2i
	var region_cell: Vector2i = converted["region_cell"] as Vector2i
	return MAP_ORIGIN + Vector2(world_cell.x, world_cell.y) * CELL_PIXEL_SIZE \
		+ (Vector2(region_cell.x, region_cell.y) + Vector2.ONE * 0.5) \
		* (CELL_PIXEL_SIZE / float(WorldCoordinates.REGION_GRID_SIZE))

func _draw_region_thumbnail(cell_rect: Rect2, thumbnail: PackedByteArray) -> void:
	if thumbnail.size() != RegionTerrainGenerator.THUMBNAIL_CELL_COUNT:
		return
	var thumbnail_cell_size: float = CELL_PIXEL_SIZE / float(RegionTerrainGenerator.THUMBNAIL_GRID_SIZE)
	for y: int in range(RegionTerrainGenerator.THUMBNAIL_GRID_SIZE):
		for x: int in range(RegionTerrainGenerator.THUMBNAIL_GRID_SIZE):
			var thumbnail_index: int = y * RegionTerrainGenerator.THUMBNAIL_GRID_SIZE + x
			var packed_cell: int = thumbnail[thumbnail_index]
			var color: Color = TerrainType.to_color(RegionTerrainGenerator.thumbnail_terrain(packed_cell))
			if RegionTerrainGenerator.thumbnail_has_river(packed_cell):
				color = Color("49a9cf")
			var thumbnail_rect: Rect2 = Rect2(
				cell_rect.position + Vector2(x, y) * thumbnail_cell_size,
				Vector2.ONE * thumbnail_cell_size
			)
			draw_rect(thumbnail_rect, color)

func _cell_from_global_position(mouse_global_position: Vector2) -> Vector2i:
	var map_position: Vector2 = to_local(mouse_global_position)
	return Vector2i(
		floori((map_position.x - MAP_ORIGIN.x) / CELL_PIXEL_SIZE),
		floori((map_position.y - MAP_ORIGIN.y) / CELL_PIXEL_SIZE)
	)

func _is_valid_world_cell(world_cell: Vector2i) -> bool:
	return world_cell.x >= 0 and world_cell.y >= 0 \
		and world_cell.x < GRID_SIZE.x and world_cell.y < GRID_SIZE.y

func _visible_world_cells() -> Rect2i:
	if camera == null:
		return Rect2i(Vector2i.ZERO, GRID_SIZE)
	var half_view: Vector2 = get_viewport_rect().size / (2.0 * camera.zoom.x)
	var minimum: Vector2 = camera.position - half_view
	var maximum: Vector2 = camera.position + half_view
	var min_cell: Vector2i = Vector2i(
		floori((minimum.x - MAP_ORIGIN.x) / CELL_PIXEL_SIZE) - 1,
		floori((minimum.y - MAP_ORIGIN.y) / CELL_PIXEL_SIZE) - 1
	)
	var max_cell: Vector2i = Vector2i(
		ceili((maximum.x - MAP_ORIGIN.x) / CELL_PIXEL_SIZE) + 1,
		ceili((maximum.y - MAP_ORIGIN.y) / CELL_PIXEL_SIZE) + 1
	)
	min_cell.x = clampi(min_cell.x, 0, GRID_SIZE.x)
	min_cell.y = clampi(min_cell.y, 0, GRID_SIZE.y)
	max_cell.x = clampi(max_cell.x, min_cell.x, GRID_SIZE.x)
	max_cell.y = clampi(max_cell.y, min_cell.y, GRID_SIZE.y)
	return Rect2i(min_cell, max_cell - min_cell)

func _set_hovered_world_cell(world_cell: Vector2i) -> void:
	if not _is_valid_world_cell(world_cell):
		world_cell = Vector2i(-1, -1)
	if hovered_world_cell == world_cell:
		return
	hovered_world_cell = world_cell
	queue_redraw()
	debug_state_changed.emit(get_debug_state())

func _set_zoom(factor: float) -> void:
	var next_zoom: float = clampf(camera.zoom.x * factor, 0.5, 2.0)
	camera.zoom = Vector2.ONE * next_zoom

func _format_cell(cell: Vector2i) -> String:
	return "(%d, %d)" % [cell.x, cell.y]
