class_name WorldMap
extends Node2D

const GlobalTravelPathType = preload("res://scripts/data/global_travel_path.gd")
const MapArtCatalogType = preload("res://scripts/data/map_art_catalog.gd")
const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")
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
var travel_preview: TravelPreviewResult
var preview_error: String = ""
var world_texture: Texture2D
var world_texture_rect: Rect2 = Rect2()
var world_texture_cells: Rect2i = Rect2i()
var overview: WorldOverviewData

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

func setup(p_world_data: WorldData, p_session: GameSession, p_runtime: TravelRuntime = null) -> void:
	world_data = p_world_data
	session = p_session
	travel_runtime = p_runtime if p_runtime != null else TravelRuntimeType.new(session, world_data)
	travel_runtime.bind(session, world_data)
	overview = world_data.get_or_generate_world_overview(session.world_seed)
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
				# World is an Overview-only layer. POIs are resolved after Region entry.
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
			travel_runtime.ensure_party_ready()
			var destination_global_cell: Vector2i = travel_runtime.resolve_world_destination(
				session.selected_world_cell
			)
			travel_preview = travel_runtime.query_travel_preview(
					session.party.party_id,
				destination_global_cell,
				""
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
	var region_label: String = "Region %03d,%03d (lazy)" % [session.selected_world_cell.x, session.selected_world_cell.y]
	var terrain_type_name: String = TerrainType.to_display_name(overview.biome_at(session.selected_world_cell)) \
		if overview != null else "??"
	if overview != null and (overview.features_at(session.selected_world_cell) & WorldOverviewData.FEATURE_RIVER) != 0:
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
		"poi_name": "Generated on Region entry",
		"instruction": "WASD: Move   Wheel: Zoom   Left Click: Select Region   P: Plan Travel   Enter: Confirm / Enter Region   1/2/3: Travel Speed"
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
			draw_rect(cell_rect, Color(0.18, 0.24, 0.30, 0.42), false, 2.0)
			if world_cell == session.selected_world_cell:
				draw_rect(cell_rect, Color("ffe082"), false, 5.0)
			if world_cell == hovered_world_cell:
				draw_rect(cell_rect.grow(-5.0), Color("ffffff"), false, 3.0)
	_draw_world_features(visible_cells)
	_draw_party_marker()
	_draw_travel_preview()

func _ensure_world_texture(visible_cells: Rect2i) -> void:
	if world_data == null or session == null or overview == null \
		or visible_cells == world_texture_cells and world_texture != null:
		return
	var thumbnail_size: int = 8
	var image: Image = Image.create(
		visible_cells.size.x * thumbnail_size,
		visible_cells.size.y * thumbnail_size,
		false,
		Image.FORMAT_RGBA8
	)
	for local_y: int in range(visible_cells.size.y):
		for local_x: int in range(visible_cells.size.x):
			var world_cell: Vector2i = visible_cells.position + Vector2i(local_x, local_y)
			var biome: int = overview.biome_at(world_cell)
			var features: int = overview.features_at(world_cell)
			var resource_total: int = 0
			for resource_type: int in range(SiteContentTypes.RESOURCE_COUNT):
				resource_total += overview.resource_budget_at(world_cell, resource_type)
			for sub_y: int in range(thumbnail_size):
				for sub_x: int in range(thumbnail_size):
					var pixel_terrain: int = biome
					var pixel_visual_code: int = 0
					var color: Color = MapArtCatalogType.thumbnail_color(
						pixel_terrain,
						pixel_visual_code,
						Vector2i(sub_x, sub_y),
						thumbnail_size
					)
					var river_horizontal: bool = _river_runs_horizontal(world_cell)
					if (features & WorldOverviewData.FEATURE_RIVER) != 0 \
						and ((river_horizontal and abs(sub_y - 3) <= 1) \
						or (not river_horizontal and abs(sub_x - 3) <= 1)):
						color = color.lerp(Color("3b9ab2"), 0.82)
					elif (features & WorldOverviewData.FEATURE_RIDGE) != 0 \
						and sub_y in [2, 3]:
						color = color.darkened(0.20)
					if (features & WorldOverviewData.FEATURE_COAST) != 0 \
						and (sub_x == 0 or sub_x == thumbnail_size - 1 \
						or sub_y == 0 or sub_y == thumbnail_size - 1):
						color = color.lerp(Color("e6cf8e"), 0.36)
					var resource_tint: float = clampf(float(resource_total) / 24000.0, 0.0, 1.0)
					color = color.lightened(resource_tint * 0.15)
					image.set_pixel(
						local_x * thumbnail_size + sub_x,
						local_y * thumbnail_size + sub_y,
						color
					)
	world_texture = ImageTexture.create_from_image(image)
	world_texture_cells = visible_cells
	world_texture_rect = Rect2(
		MAP_ORIGIN + Vector2(visible_cells.position) * CELL_PIXEL_SIZE,
		Vector2(visible_cells.size) * CELL_PIXEL_SIZE
	)

func _draw_world_features(visible_cells: Rect2i) -> void:
	if overview == null:
		return
	for y: int in range(visible_cells.position.y, visible_cells.end.y):
		for x: int in range(visible_cells.position.x, visible_cells.end.x):
			var world_cell: Vector2i = Vector2i(x, y)
			var cell_rect: Rect2 = Rect2(
				MAP_ORIGIN + Vector2(x, y) * CELL_PIXEL_SIZE,
				Vector2.ONE * CELL_PIXEL_SIZE
			)
			var center: Vector2 = cell_rect.position + cell_rect.size * 0.5
			var features: int = overview.features_at(world_cell)
			if (features & WorldOverviewData.FEATURE_RIVER) != 0:
				var horizontal: bool = _river_runs_horizontal(world_cell)
				var start: Vector2 = cell_rect.position + (Vector2(0.0, 32.0) if horizontal else Vector2(32.0, 0.0))
				var finish: Vector2 = cell_rect.position + (Vector2(64.0, 32.0) if horizontal else Vector2(32.0, 64.0))
				draw_line(start, finish, Color("1b526a"), 13.0, true)
				draw_line(start, finish, Color("67d5e5"), 7.0, true)
			if (features & WorldOverviewData.FEATURE_COAST) != 0:
				draw_rect(cell_rect.grow(-4.0), Color("f1d998"), false, 3.0)
			if (features & WorldOverviewData.FEATURE_RIDGE) != 0:
				draw_line(
					cell_rect.position + Vector2(10.0, 47.0),
					cell_rect.position + Vector2(54.0, 17.0),
					Color("303840"),
					6.0,
					true
				)
				draw_line(
					cell_rect.position + Vector2(12.0, 39.0),
					cell_rect.position + Vector2(51.0, 13.0),
					Color("b7c0c0"),
					2.0,
					true
				)
			_draw_world_resource_marker(world_cell, center)
			_draw_world_passage(world_cell, cell_rect)

func _draw_world_resource_marker(world_cell: Vector2i, center: Vector2) -> void:
	if overview == null:
		return
	var dominant_resource: int = -1
	var dominant_amount: int = 0
	for resource_type: int in range(SiteContentTypes.RESOURCE_COUNT):
		# Grass and forest are native ground cover on the strategic overview, not
		# discrete pins.  The old rule selected them in most cells, producing a
		# misleading dotted grid.  Rare resources remain explicit markers.
		if resource_type in [SiteContentTypes.RESOURCE_GRASS, SiteContentTypes.RESOURCE_FOREST]:
			continue
		var amount: int = overview.resource_budget_at(world_cell, resource_type)
		if amount > dominant_amount:
			dominant_amount = amount
			dominant_resource = resource_type
	if dominant_resource < 0 or dominant_amount < 500 or not _world_resource_marker_is_peak(
		world_cell,
		dominant_resource,
		dominant_amount
	):
		return
	var marker_color: Color = _resource_color(dominant_resource)
	draw_circle(center + Vector2(21.0, -20.0), 8.0, Color(0.06, 0.08, 0.09, 0.85))
	draw_circle(center + Vector2(21.0, -20.0), 5.0, marker_color)

func _world_resource_marker_is_peak(world_cell: Vector2i, resource_type: int, amount: int) -> bool:
	if overview == null:
		return false
	for offset: Vector2i in [
		Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)
	]:
		var neighbor: Vector2i = world_cell + offset
		var neighbor_amount: int = overview.resource_budget_at(neighbor, resource_type)
		if neighbor_amount > amount:
			return false
		if neighbor_amount == amount and (neighbor.y < world_cell.y \
			or (neighbor.y == world_cell.y and neighbor.x < world_cell.x)):
			return false
	return true

func _draw_world_passage(world_cell: Vector2i, cell_rect: Rect2) -> void:
	if overview == null:
		return
	var mask: int = overview.passage_mask_at(world_cell)
	if mask == SiteLayoutDataType.EXIT_ALL or mask == 0:
		return
	var center: Vector2 = cell_rect.position + cell_rect.size * 0.5
	var endpoints: PackedVector2Array = PackedVector2Array()
	if (mask & SiteLayoutDataType.EXIT_NORTH) != 0:
		endpoints.append(cell_rect.position + Vector2(32.0, 2.0))
	if (mask & SiteLayoutDataType.EXIT_EAST) != 0:
		endpoints.append(cell_rect.position + Vector2(62.0, 32.0))
	if (mask & SiteLayoutDataType.EXIT_SOUTH) != 0:
		endpoints.append(cell_rect.position + Vector2(32.0, 62.0))
	if (mask & SiteLayoutDataType.EXIT_WEST) != 0:
		endpoints.append(cell_rect.position + Vector2(2.0, 32.0))
	for endpoint: Vector2 in endpoints:
		draw_line(center, endpoint, Color("4b3422"), 8.0, true)
		draw_line(center, endpoint, Color("d7a968"), 4.0, true)

func _resource_color(resource_type: int) -> Color:
	match resource_type:
		SiteContentTypes.RESOURCE_GRASS:
			return Color("9fd36b")
		SiteContentTypes.RESOURCE_FRUIT_TREE:
			return Color("f2a24b")
		SiteContentTypes.RESOURCE_FOREST:
			return Color("2c8f58")
		SiteContentTypes.RESOURCE_STONE_ORE:
			return Color("b8bec4")
		SiteContentTypes.RESOURCE_IRON_ORE:
			return Color("bd694c")
		SiteContentTypes.RESOURCE_SILVER_ORE:
			return Color("d7e4ec")
		SiteContentTypes.RESOURCE_GOLD_ORE:
			return Color("f4d15b")
	return Color("ffffff")

func _river_runs_horizontal(world_cell: Vector2i) -> bool:
	if overview == null:
		return false
	var horizontal: int = 0
	var vertical: int = 0
	for neighbor: Vector2i in [world_cell + Vector2i.LEFT, world_cell + Vector2i.RIGHT]:
		if _is_valid_world_cell(neighbor) and (overview.features_at(neighbor) & WorldOverviewData.FEATURE_RIVER) != 0:
			horizontal += 1
	for neighbor: Vector2i in [world_cell + Vector2i.UP, world_cell + Vector2i.DOWN]:
		if _is_valid_world_cell(neighbor) and (overview.features_at(neighbor) & WorldOverviewData.FEATURE_RIVER) != 0:
			vertical += 1
	return horizontal >= vertical

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

func _global_cell_map_position(global_cell: Vector2i) -> Vector2:
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(global_cell)
	var world_cell: Vector2i = converted["world_cell"] as Vector2i
	var region_cell: Vector2i = converted["region_cell"] as Vector2i
	return MAP_ORIGIN + Vector2(world_cell.x, world_cell.y) * CELL_PIXEL_SIZE \
		+ (Vector2(region_cell.x, region_cell.y) + Vector2.ONE * 0.5) \
		* (CELL_PIXEL_SIZE / float(WorldCoordinates.REGION_GRID_SIZE))

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
