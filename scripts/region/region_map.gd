class_name RegionMap
extends Node2D

const GlobalTravelPathType = preload("res://scripts/data/global_travel_path.gd")
const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")
const MapArtCatalogType = preload("res://scripts/data/map_art_catalog.gd")
const SiteLayoutGeneratorType = preload("res://scripts/core/site_layout_generator.gd")
const SiteContentTypesType = preload("res://scripts/data/site_content_types.gd")
const BattlePreviewRuntimeType = preload("res://scripts/runtime/battle_preview_runtime.gd")
const RegionConstructionResultType = preload("res://scripts/runtime/region_construction_result.gd")
const RegionRuntimeType = preload("res://scripts/runtime/region_runtime.gd")
const TravelRuntimeType = preload("res://scripts/runtime/travel_runtime.gd")
const TravelFailureReasonType = preload("res://scripts/runtime/travel_failure_reason.gd")
const TravelStatusType = preload("res://scripts/runtime/travel_status.gd")

signal site_enter_requested(region_cell: Vector2i)
signal battle_preview_requested(snapshot: BattleSiteSnapshot)
signal debug_state_changed(state: Dictionary)

enum DebugView {
	NORMAL,
	ELEVATION,
	MOISTURE,
	RIVER,
	POI,
	ROAD,
	TRAVEL,
	GLOBAL_TRAVEL,
}

class PartyMarkerVisual:
	extends Node2D

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 20.0, Color("17233c"))
		draw_circle(Vector2.ZERO, 15.0, Color("4f8cff"))
		draw_line(Vector2(12.0, -10.0), Vector2(12.0, -34.0), Color("d9e7ff"), 3.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(12.0, -34.0),
			Vector2(30.0, -28.0),
			Vector2(12.0, -21.0),
		]), Color("d9e7ff"))

class RegionStaticVisual:
	extends Node2D

	var terrain_texture: Texture2D
	var road_cells: Array[Vector3i] = []
	var travel_debug_view: bool = false

	func configure(
			p_terrain_texture: Texture2D,
			p_road_cells: Array[Vector3i],
			p_travel_debug_view: bool
		) -> void:
		terrain_texture = p_terrain_texture
		road_cells = p_road_cells
		travel_debug_view = p_travel_debug_view
		queue_redraw()

	func _draw() -> void:
		if terrain_texture == null:
			return
		var map_size: Vector2 = Vector2(RegionMap.GRID_SIZE) * RegionMap.CELL_PIXEL_SIZE
		draw_rect(
			Rect2(RegionMap.MAP_ORIGIN - Vector2(12, 12), map_size + Vector2(24, 24)),
			Color("17211e")
		)
		draw_texture_rect(terrain_texture, Rect2(RegionMap.MAP_ORIGIN, map_size), false)
		for x: int in range(RegionMap.GRID_SIZE.x + 1):
			var line_x: float = RegionMap.MAP_ORIGIN.x + float(x) * RegionMap.CELL_PIXEL_SIZE
			draw_line(
				Vector2(line_x, RegionMap.MAP_ORIGIN.y),
				Vector2(line_x, RegionMap.MAP_ORIGIN.y + map_size.y),
				Color(0.17, 0.25, 0.21, 0.10)
			)
		for y: int in range(RegionMap.GRID_SIZE.y + 1):
			var line_y: float = RegionMap.MAP_ORIGIN.y + float(y) * RegionMap.CELL_PIXEL_SIZE
			draw_line(
				Vector2(RegionMap.MAP_ORIGIN.x, line_y),
				Vector2(RegionMap.MAP_ORIGIN.x + map_size.x, line_y),
				Color(0.17, 0.25, 0.21, 0.10)
			)
		for road_cell: Vector3i in road_cells:
			if not travel_debug_view:
				continue
			var road_color: Color = Color("5f9dff") if travel_debug_view else Color("d5a34d")
			if (road_cell.z & RegionRoadOverlay.RIVER_CROSSING) != 0:
				road_color = Color("86f4ff") if travel_debug_view else Color("55e4e8")
			var cell_rect: Rect2 = Rect2(
				RegionMap.MAP_ORIGIN + Vector2(road_cell.x, road_cell.y) * RegionMap.CELL_PIXEL_SIZE,
				Vector2.ONE * RegionMap.CELL_PIXEL_SIZE
			)
			draw_rect(cell_rect.grow(-23.0), road_color.darkened(0.15), true)
			draw_rect(cell_rect.grow(-23.0), road_color, false, 2.0)

const GRID_SIZE: Vector2i = Vector2i(WorldCoordinates.REGION_GRID_SIZE, WorldCoordinates.REGION_GRID_SIZE)
const CELL_PIXEL_SIZE: float = 64.0
const MAP_ORIGIN: Vector2 = Vector2.ZERO
const CAMERA_SPEED: float = 900.0
const VISUAL_STEP_DURATION: float = 0.2
const PLAINS_COLOR: Color = Color("6f9b5b")
const FOREST_COLOR: Color = Color("3f7857")
const MOUNTAIN_COLOR: Color = Color("777b83")
const WATER_COLOR: Color = Color("4d87a1")
const RIVER_COLOR: Color = Color("49a9cf")
const SITE_THUMBNAIL_GRID_SIZE: int = SiteLayoutGeneratorType.THUMBNAIL_GRID_SIZE

@onready var camera: Camera2D = $Camera2D

var static_visual: RegionStaticVisual
var party_marker: PartyMarkerVisual
var region: RegionData
var terrain_data: RegionTerrainData
var site_content_data: RegionSiteContentData
var pois: Array[WorldPOIData] = []
var road_overlay: RegionRoadOverlay = RegionRoadOverlay.new()
var session: GameSession
var region_runtime: RegionRuntime
var resolved_region: RegionStateResolver
var hovered_region_cell: Vector2i = Vector2i(-1, -1)
var debug_view: int = DebugView.NORMAL
var travel_runtime: TravelRuntime
var battle_preview_runtime: BattlePreviewRuntime
var party_in_region: bool = false
var destination_region_cell: Vector2i = Vector2i(-1, -1)
var path_preview: TravelPreviewResult
var preview_error: String = ""
var construction_mode: bool = false
var construction_preview: RegionConstructionResultType
var is_moving: bool = false
var resource_visual_types: PackedInt32Array = PackedInt32Array()
var resource_visual_amounts: PackedInt32Array = PackedInt32Array()
# Region and Site must render the same resolved edge contract.  These caches are
# built once per Region view instead of re-sampling 10,000 cells every draw.
var travel_river_cells: Dictionary = {}
var travel_river_offsets: Dictionary = {}
var travel_road_cells: Dictionary = {}
var travel_road_offsets: Dictionary = {}
var travel_road_crossings: Dictionary = {}

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	static_visual = RegionStaticVisual.new()
	static_visual.name = "StaticVisual"
	static_visual.show_behind_parent = true
	static_visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(static_visual)
	party_marker = PartyMarkerVisual.new()
	party_marker.name = "PartyMarker"
	party_marker.z_index = 10
	party_marker.visible = false
	add_child(party_marker)

func setup(
		p_region: RegionData,
		p_terrain_data: RegionTerrainData,
		p_pois: Array[WorldPOIData],
		p_session: GameSession,
		p_road_overlay: RegionRoadOverlay = null,
		p_runtime: TravelRuntime = null,
		p_region_runtime: RegionRuntime = null,
		p_battle_preview_runtime: BattlePreviewRuntime = null,
		p_preserve_selection: bool = false
	) -> void:
	region = p_region
	terrain_data = p_terrain_data
	pois = p_pois
	road_overlay = p_road_overlay if p_road_overlay != null else RegionRoadOverlay.new()
	session = p_session
	travel_runtime = p_runtime if p_runtime != null else TravelRuntimeType.new(session, WorldData.new())
	travel_runtime.bind(session, travel_runtime.world_data)
	region_runtime = p_region_runtime if p_region_runtime != null else RegionRuntimeType.new(session, travel_runtime.world_data)
	region_runtime.bind(session, region_runtime.world_data)
	battle_preview_runtime = p_battle_preview_runtime if p_battle_preview_runtime != null \
		else BattlePreviewRuntimeType.new(session, travel_runtime.world_data, region_runtime)
	battle_preview_runtime.bind(session, travel_runtime.world_data, region_runtime)
	region_runtime.set_region_context(region, terrain_data, pois, road_overlay)
	resolved_region = region_runtime.query_region(region.world_cell)
	_refresh_travel_visual_contract()
	site_content_data = travel_runtime.world_data.get_or_generate_region_site_content(
		region.world_cell,
		session.world_seed
	) if travel_runtime != null and travel_runtime.world_data != null else null
	party_in_region = session.party.initialized \
		and session.party.get_world_cell() == session.selected_world_cell
	is_moving = session.is_traveling()
	if party_in_region and not p_preserve_selection:
		session.selected_region_cell = session.party.get_region_cell()
	destination_region_cell = Vector2i(-1, -1)
	path_preview = null
	preview_error = ""
	construction_mode = false
	construction_preview = null
	party_marker.position = _cell_center(session.party.get_region_cell()) if party_in_region else Vector2.ZERO
	party_marker.visible = party_in_region
	camera.position = _cell_center(session.selected_region_cell)
	camera.zoom = Vector2.ONE
	_refresh_static_visual()
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
		_set_hovered_region_cell(_cell_from_global_position(get_global_mouse_position()))
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
			var region_cell: Vector2i = _cell_from_global_position(get_global_mouse_position())
			if _is_valid_region_cell(region_cell):
				if construction_mode:
					place_outpost_at(region_cell)
				elif not session.is_traveling() and not session.has_travel_plan():
					if mouse_event.double_click \
						or (path_preview != null and path_preview.has_path() \
							and destination_region_cell == region_cell):
						_try_enter_site_at(region_cell)
					else:
						select_destination(region_cell)
				get_viewport().set_input_as_handled()
		elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed \
			and construction_mode:
			var region_cell: Vector2i = _cell_from_global_position(get_global_mouse_position())
			if _is_valid_region_cell(region_cell):
				remove_outpost_at(region_cell)
				get_viewport().set_input_as_handled()
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_C:
			set_construction_mode(not construction_mode)
			get_viewport().set_input_as_handled()
			return
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_B:
			if _is_valid_region_cell(session.selected_region_cell):
				var battle_global_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
					session.selected_world_cell,
					session.selected_region_cell
				)
				var battle_snapshot: BattleSiteSnapshot = battle_preview_runtime.query_debug_preview(
					battle_global_cell
				)
				if battle_snapshot.has_preview():
					preview_error = ""
					battle_preview_requested.emit(battle_snapshot)
				else:
					preview_error = BattleSiteSnapshot.failure_code(battle_snapshot.failure_reason)
					debug_state_changed.emit(get_debug_state())
			get_viewport().set_input_as_handled()
			return
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F1:
			debug_view = posmod(debug_view + 1, DebugView.GLOBAL_TRAVEL + 1)
			_refresh_static_visual()
			queue_redraw()
			debug_state_changed.emit(get_debug_state())
			get_viewport().set_input_as_handled()
			return
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ENTER:
			if _request_site_entry_at(session.selected_region_cell):
				get_viewport().set_input_as_handled()
			return
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_SPACE:
			if confirm_destination():
				get_viewport().set_input_as_handled()
			return
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE:
			if construction_mode:
				set_construction_mode(false)
				get_viewport().set_input_as_handled()
			elif session.is_traveling():
				return
			elif path_preview != null:
				cancel_path_preview()
				get_viewport().set_input_as_handled()

func set_construction_mode(enabled: bool) -> bool:
	if enabled and path_preview != null:
		cancel_path_preview()
	construction_mode = enabled
	construction_preview = null
	preview_error = ""
	_refresh_construction_preview()
	queue_redraw()
	debug_state_changed.emit(get_debug_state())
	return true

func place_outpost_at(region_cell: Vector2i) -> RegionConstructionResultType:
	var result: RegionConstructionResultType = region_runtime.place_outpost(region.world_cell, region_cell)
	_refresh_resolved_region()
	_refresh_construction_preview()
	preview_error = "" if result.success else RegionConstructionResultType.failure_code(result.failure_reason)
	queue_redraw()
	debug_state_changed.emit(get_debug_state())
	return result

func remove_outpost_at(region_cell: Vector2i) -> RegionConstructionResultType:
	var result: RegionConstructionResultType = region_runtime.remove_outpost(region.world_cell, region_cell)
	_refresh_resolved_region()
	_refresh_construction_preview()
	preview_error = "" if result.success else RegionConstructionResultType.failure_code(result.failure_reason)
	queue_redraw()
	debug_state_changed.emit(get_debug_state())
	return result

func _refresh_resolved_region() -> void:
	if region_runtime != null and region != null:
		resolved_region = region_runtime.query_region(region.world_cell)
		_refresh_travel_visual_contract()

func _refresh_travel_visual_contract() -> void:
	travel_river_cells.clear()
	travel_river_offsets.clear()
	travel_road_cells.clear()
	travel_road_offsets.clear()
	travel_road_crossings.clear()
	if region == null or travel_runtime == null or session == null:
		return
	for y: int in range(GRID_SIZE.y):
		for x: int in range(GRID_SIZE.x):
			var region_cell: Vector2i = Vector2i(x, y)
			var info: Dictionary = _region_travel_info(region_cell)
			if not bool(info.get("valid", false)):
				continue
			var road_offsets: Array[Vector2i] = _cardinal_offsets(
				info.get("road_connection_offsets", [])
			)
			if bool(info.get("road", false)):
				travel_road_cells[region_cell] = true
				travel_road_offsets[region_cell] = road_offsets
				if bool(info.get("river_crossing", false)):
					travel_road_crossings[region_cell] = true
			var river_offsets: Array[Vector2i] = _cardinal_offsets(
				info.get("river_connection_offsets", [])
			)
			if bool(info.get("river", false)) and not river_offsets.is_empty():
				travel_river_cells[region_cell] = true
				travel_river_offsets[region_cell] = river_offsets

func _refresh_construction_preview() -> void:
	if not construction_mode or not _is_valid_region_cell(hovered_region_cell):
		construction_preview = null
		return
	construction_preview = region_runtime.query_outpost_preview(
		region.world_cell,
		hovered_region_cell
	)
	preview_error = "" if construction_preview.success \
		else RegionConstructionResultType.failure_code(construction_preview.failure_reason)

func select_region_cell(region_cell: Vector2i) -> bool:
	if not _is_valid_region_cell(region_cell):
		return false
	session.selected_region_cell = region_cell
	queue_redraw()
	debug_state_changed.emit(get_debug_state())
	return true

func select_destination(region_cell: Vector2i) -> bool:
	if not select_region_cell(region_cell):
		return false
	if session.is_traveling():
		destination_region_cell = Vector2i(-1, -1)
		path_preview = null
		preview_error = ""
		queue_redraw()
		debug_state_changed.emit(get_debug_state())
		return false
	destination_region_cell = region_cell
	var destination_global_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
			session.selected_world_cell,
			region_cell
	)
	path_preview = travel_runtime.query_travel_preview(
			session.party.party_id,
			destination_global_cell
		)
	preview_error = "" if path_preview.has_path() else TravelFailureReasonType.to_code(path_preview.failure_reason)
	queue_redraw()
	debug_state_changed.emit(get_debug_state())
	return path_preview.has_path()

func _try_enter_site_at(region_cell: Vector2i) -> bool:
	return _request_site_entry_at(region_cell)

func _request_site_entry_at(region_cell: Vector2i) -> bool:
	var entry: SiteEntryQueryResult = travel_runtime.query_site_entry_at(
			session.party.party_id,
			session.selected_world_cell,
			region_cell
		)
	if entry.can_enter:
		site_enter_requested.emit(region_cell)
	else:
		preview_error = TravelFailureReasonType.to_code(entry.failure_reason)
		queue_redraw()
		debug_state_changed.emit(get_debug_state())
	return true

func confirm_destination() -> bool:
	if session.is_traveling() or path_preview == null or not path_preview.has_path():
		return false
	var command: TravelCommandResult = travel_runtime.start_travel(
			session.party.party_id,
			path_preview.destination_global_cell
		)
	if not command.success:
		preview_error = TravelFailureReasonType.to_code(command.failure_reason)
		queue_redraw()
		debug_state_changed.emit(get_debug_state())
		return false
	path_preview = null
	destination_region_cell = Vector2i(-1, -1)
	is_moving = true
	queue_redraw()
	debug_state_changed.emit(get_debug_state())
	return true

func cancel_path_preview() -> void:
	if is_moving:
		return
	path_preview = null
	destination_region_cell = Vector2i(-1, -1)
	preview_error = ""
	if party_in_region:
		session.selected_region_cell = session.party.current_region_cell
	queue_redraw()
	debug_state_changed.emit(get_debug_state())

func has_path_preview() -> bool:
	return path_preview != null and path_preview.has_path()

func clear_local_path_preview() -> void:
	path_preview = null
	destination_region_cell = Vector2i(-1, -1)
	preview_error = ""
	is_moving = session.is_traveling()
	if party_in_region:
		session.selected_region_cell = session.party.get_region_cell()
	queue_redraw()

func animate_party_step(next_region_cell: Vector2i, playback_multiplier: float = 1.0) -> void:
	var tween: Tween = create_tween()
	var duration: float = VISUAL_STEP_DURATION / maxf(playback_multiplier, 0.01)
	tween.tween_property(party_marker, "position", _cell_center(next_region_cell), duration)
	await tween.finished

func sync_party_position() -> void:
	party_in_region = session.party.initialized \
		and session.party.get_world_cell() == session.selected_world_cell
	is_moving = session.is_traveling()
	party_marker.visible = party_in_region
	if party_in_region:
		session.selected_region_cell = session.party.get_region_cell()
		party_marker.position = _cell_center(session.party.get_region_cell())
	if not is_moving:
		queue_redraw()
	debug_state_changed.emit(get_debug_state())

func get_debug_state() -> Dictionary:
	var displayed_region_cell: Vector2i = session.selected_region_cell
	if _is_valid_region_cell(hovered_region_cell):
		displayed_region_cell = hovered_region_cell
	var global_region_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
		session.selected_world_cell,
		displayed_region_cell
	)
	var global_meters: Vector2i = WorldCoordinates.world_region_to_global_meters(
		session.selected_world_cell,
		displayed_region_cell
	)
	var base_terrain_type: int = resolved_region.get_base_terrain(displayed_region_cell) if resolved_region != null else -1
	var terrain_type: int = resolved_region.get_terrain(displayed_region_cell) if resolved_region != null else -1
	var elevation: float = resolved_region.get_elevation(displayed_region_cell) if resolved_region != null else 0.0
	var moisture: float = resolved_region.get_moisture(displayed_region_cell) if resolved_region != null else 0.0
	var river_strength: float = resolved_region.get_river_strength(displayed_region_cell) if resolved_region != null else 0.0
	var global_cell_info: TravelCellResult = travel_runtime.query_travel_cell(global_region_cell)
	var base_terrain_name: String = TerrainType.to_display_name(base_terrain_type)
	var resolved_terrain_name: String = TerrainType.to_display_name(terrain_type)
	var final_terrain_name: String = resolved_terrain_name
	if global_cell_info.river:
		final_terrain_name = "River / %s" % resolved_terrain_name
	var hovered_poi: WorldPOIData = _poi_at(displayed_region_cell)
	var road_flags: int = _resolved_road_flags(displayed_region_cell)
	var route_ids: Array[String] = _resolved_route_ids(displayed_region_cell)
	var speed: float = global_cell_info.speed
	var cell_travel_seconds: int = global_cell_info.travel_seconds
	var reached_poi: WorldPOIData = _poi_at(session.party.get_region_cell()) if party_in_region else null
	var region_label: String = "??"
	if region != null:
		region_label = "%s (%s)" % [region.region_name, region.region_id]
	var active_path: GlobalTravelPathType = session.active_global_travel_path
	var path_distance: String = "%.3f km" % (path_preview.total_distance_meters / 1000.0) if path_preview != null else "None"
	var estimated_travel: String = path_preview.estimated_duration() if path_preview != null else "None"
	var path_cells: String = str(path_preview.path.cells.size()) if path_preview != null and path_preview.path != null else "0"
	var destination_global_cell: String = "None"
	var current_path_index: String = "0"
	var total_path_cells: String = "0"
	var remaining_path_cells: String = "0"
	var regions_crossed: String = "0"
	var remaining_distance: String = "None"
	var remaining_eta: String = "None"
	if active_path != null:
		var remaining_distance_meters: float = active_path.remaining_distance_from(session.global_travel_path_index)
		var remaining_duration: String = active_path.remaining_duration_from(session.global_travel_path_index)
		destination_global_cell = _format_cell(active_path.destination_global_cell)
		current_path_index = str(session.global_travel_path_index)
		total_path_cells = str(active_path.cells.size())
		remaining_path_cells = str(maxi(active_path.cells.size() - session.global_travel_path_index - 1, 0))
		path_distance = "%.3f / %.3f km" % [
			active_path.total_distance_meters / 1000.0,
			remaining_distance_meters / 1000.0,
		]
		estimated_travel = "%s / %s" % [
			active_path.estimated_duration(),
			remaining_duration,
		]
		path_cells = "%d / %d" % [session.global_travel_path_index, active_path.cells.size()]
		regions_crossed = str(active_path.regions_crossed)
		remaining_distance = "%.3f km" % (remaining_distance_meters / 1000.0)
		remaining_eta = remaining_duration
	return {
		"layer": "REGION MAP",
		"current_region": region_label,
		"world_seed": session.world_seed,
		"world_time": session.format_world_time(),
		"party_id": session.party.party_id,
		"party_position": "%s / Global %s" % [_format_cell(session.party.get_region_cell()), _format_cell(session.party.current_global_region_cell)] if party_in_region else "Away",
		"party_state": "Moving" if session.is_traveling() else ("Ready" if party_in_region else "Away"),
		"destination": _format_optional_cell(destination_region_cell),
		"path_distance": path_distance,
		"remaining_distance": remaining_distance,
		"estimated_travel": estimated_travel,
		"remaining_eta": remaining_eta,
		"path_cells": path_cells,
		"current_path_index": current_path_index,
		"total_path_cells": total_path_cells,
		"remaining_path_cells": remaining_path_cells,
		"destination_global_cell": destination_global_cell,
		"regions_crossed": regions_crossed,
		"travel_status": _travel_status_label(),
		"travel_error": preview_error if not preview_error.is_empty() else TravelFailureReasonType.to_code(session.travel_failure_reason),
		"travel_speed_multiplier": "%.0fx" % session.travel_speed_multiplier,
		"path_search_time": "%.2f ms" % active_path.path_calculation_milliseconds if active_path != null else "None",
		"preview_error": preview_error,
		"passable": "Yes" if global_cell_info.passable else "No",
		"effective_speed": "%.1f km/h" % speed if speed > 0.0 else "--",
		"cell_travel_time": "%ds" % cell_travel_seconds if cell_travel_seconds > 0 else "--",
		"poi_reached": reached_poi.site_name if reached_poi != null else "No",
		"debug_view": _debug_view_name(),
		"world_cell": _format_cell(session.selected_world_cell),
		"hovered_region_cell": _format_optional_cell(hovered_region_cell),
		"selected_region_cell": _format_cell(session.selected_region_cell),
		"global_region_cell": _format_cell(global_region_cell),
		"global_meter_position": _format_meters(global_meters),
		"base_terrain_type": base_terrain_name,
		"terrain_type": final_terrain_name,
		"elevation": "%.2f" % elevation,
		"moisture": "%.2f" % moisture,
		"river_strength": "%.2f" % river_strength,
		"river_mask": "Yes" if global_cell_info.river else "No",
		"site": _poi_label(session.selected_region_cell),
		"poi_id": hovered_poi.poi_id if hovered_poi != null else "No POI",
		"poi_type": WorldPOIType.to_display_name(hovered_poi.poi_type) if hovered_poi != null else "No POI",
		"poi_name": hovered_poi.site_name if hovered_poi != null else "No POI",
		"poi_candidate_cell": _format_cell(hovered_poi.candidate_cell) if hovered_poi != null else "??",
		"poi_priority": "%.3f" % hovered_poi.deterministic_priority if hovered_poi != null else "??",
		"poi_river_nearby": "Yes" if hovered_poi != null and hovered_poi.river_nearby else "No",
		"road": "Yes" if (road_flags & RegionRoadOverlay.ROAD) != 0 else "No",
		"river_crossing": "Yes" if (road_flags & RegionRoadOverlay.RIVER_CROSSING) != 0 else "No",
		"route_ids": ", ".join(route_ids) if not route_ids.is_empty() else "None",
		"route_details": _route_details(route_ids),
		"construction_mode": "OUTPOST" if construction_mode else "OFF",
		"construction_preview": "AVAILABLE" if construction_preview != null and construction_preview.success else preview_error,
		"instruction": _instruction()
	}

func _instruction() -> String:
	if construction_mode:
		return "OUTPOST MODE   Left Click: Place   Right Click: Remove   ESC: Exit Construction"
	return "WASD: Camera   Wheel: Zoom   Left Click: Select   Same Click / Double Click / Enter: Open Site   Space: Confirm Travel   C: Outpost Mode   B: Test Battle   T: World Map   ESC: Cancel Preview / World   1/2/3: Travel Speed   F1: Debug View"

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
	if region == null or terrain_data == null or resolved_region == null or not resolved_region.is_valid():
		return
	if _is_valid_region_cell(session.selected_region_cell) and not is_moving:
		draw_rect(_cell_rect(session.selected_region_cell), Color("ffe082"), false, 5.0)
	if _is_valid_region_cell(hovered_region_cell):
		draw_rect(_cell_rect(hovered_region_cell).grow(-5.0), Color("ffffff"), false, 3.0)
	_draw_region_rivers()
	_draw_region_relief_contours()
	_draw_region_resources()
	_draw_region_roads()
	_draw_outposts()
	_draw_path_preview()

	for poi: WorldPOIData in pois:
		if resolved_region != null and not resolved_region.is_feature_active(poi.poi_id):
			continue
		var poi_center: Vector2 = _cell_center(poi.region_cell)
		var poi_texture: Texture2D = MapArtCatalogType.poi_texture(poi.poi_type)
		if poi_texture != null:
			draw_texture_rect(
				poi_texture,
				Rect2(poi_center - Vector2.ONE * 24.0, Vector2.ONE * 48.0),
				false
			)
		else:
			draw_circle(poi_center, 22.0, Color("182018"))
			draw_circle(poi_center, 17.0, WorldPOIType.to_color(poi.poi_type))
			draw_circle(poi_center, 7.0, Color("ffffff"))
	_draw_construction_preview()

func _refresh_static_visual() -> void:
	if static_visual == null or resolved_region == null or not resolved_region.is_valid():
		return
	# Contract/runtime tests still need a valid Region map node and terrain data,
	# but they do not inspect the GPU thumbnail. Avoid the 100x100x8x8 GDScript
	# raster in headless mode; visual verification runs without this feature and
	# therefore exercises the full composed Region artwork.
	if OS.has_feature("headless"):
		var headless_image: Image = Image.create(
			GRID_SIZE.x,
			GRID_SIZE.y,
			false,
			Image.FORMAT_RGBA8
		)
		var headless_terrain: PackedByteArray = resolved_region.get_terrain_snapshot()
		for y: int in range(GRID_SIZE.y):
			for x: int in range(GRID_SIZE.x):
				var cell_index: int = y * GRID_SIZE.x + x
				var terrain_type: int = headless_terrain[cell_index]
				headless_image.set_pixel(
					x,
					y,
					_region_visual_cell_color(Vector2i(x, y), terrain_type, cell_index, 0)
				)
		static_visual.configure(ImageTexture.create_from_image(headless_image), [], false)
		return
	var composed_visual: bool = debug_view == DebugView.NORMAL
	var visual_grid_size: Vector2i = GRID_SIZE * SITE_THUMBNAIL_GRID_SIZE if composed_visual else GRID_SIZE
	var image: Image = Image.create(visual_grid_size.x, visual_grid_size.y, false, Image.FORMAT_RGBA8)
	var road_cells: Array[Vector3i] = []
	var resolved_terrain: PackedByteArray = resolved_region.get_terrain_snapshot()
	resource_visual_types.resize(GRID_SIZE.x * GRID_SIZE.y)
	resource_visual_amounts.resize(GRID_SIZE.x * GRID_SIZE.y)
	resource_visual_types.fill(-1)
	resource_visual_amounts.fill(0)
	for y: int in range(GRID_SIZE.y):
		for x: int in range(GRID_SIZE.x):
			var region_cell: Vector2i = Vector2i(x, y)
			var cell_index: int = y * GRID_SIZE.x + x
			var terrain_type: int = resolved_terrain[cell_index]
			if site_content_data != null and site_content_data.is_valid():
				var profile: Dictionary = site_content_data.profile_at(region_cell)
				var amounts: PackedInt32Array = profile.get("resource_amounts", PackedInt32Array())
				var dominant_resource: int = -1
				var dominant_amount: int = 0
				for resource_type: int in range(SiteContentTypesType.RESOURCE_COUNT):
					# Grass and forest are native ground cover, not discrete Region
					# pins. Fruit trees and ores remain explicit resource markers.
					if resource_type in [SiteContentTypesType.RESOURCE_GRASS, SiteContentTypesType.RESOURCE_FOREST]:
						continue
					if resource_type < amounts.size() and int(amounts[resource_type]) > dominant_amount:
						dominant_resource = resource_type
						dominant_amount = int(amounts[resource_type])
				resource_visual_types[cell_index] = dominant_resource
				resource_visual_amounts[cell_index] = dominant_amount
			var base_cell: Dictionary = {
				"global_region_cell": WorldCoordinates.world_region_to_global_region_cell(
					region.world_cell,
					region_cell
				),
				"terrain_type": terrain_type,
				"elevation": resolved_region.get_elevation(region_cell),
				"moisture": resolved_region.get_moisture(region_cell),
				"river_strength": resolved_region.get_river_strength(region_cell),
				# The thumbnail generator is a terrain sampler, not the river
				# renderer.  Draw one continuous channel above the surface below;
				# otherwise every positive noise sample becomes a cyan square.
				"river": false,
				# Roads and crossings are artificial facilities. They are drawn by
				# _draw_region_roads from the authoritative RegionRoadOverlay, never
				# baked into the native terrain thumbnail. This keeps a plain tile
				# from looking like it contains a road just because it is adjacent
				# to a route.
				"road": false,
				"river_crossing": false,
			}
			if not composed_visual:
				image.set_pixel(
					x,
					y,
					_region_visual_cell_color(region_cell, terrain_type, cell_index, 0)
				)
			else:
				var cell_origin: Vector2i = region_cell * SITE_THUMBNAIL_GRID_SIZE
				var cell_visual: PackedByteArray = PackedByteArray()
				cell_visual = SiteLayoutGeneratorType.generate_cell_base_thumbnail(
					session.world_seed,
					base_cell,
					SITE_THUMBNAIL_GRID_SIZE
				)
				for sub_y: int in range(SITE_THUMBNAIL_GRID_SIZE):
					for sub_x: int in range(SITE_THUMBNAIL_GRID_SIZE):
						var visual_code: int = cell_visual[sub_y * SITE_THUMBNAIL_GRID_SIZE + sub_x]
						var cell_color: Color = _region_visual_cell_color(
							region_cell,
							terrain_type,
							cell_index,
							visual_code,
							Vector2i(sub_x, sub_y)
						)
						image.set_pixel(cell_origin.x + sub_x, cell_origin.y + sub_y, cell_color)
			if (road_overlay.flags[cell_index] & RegionRoadOverlay.ROAD) != 0:
				var road_flags: int = _resolved_road_flags(region_cell)
				if (road_flags & RegionRoadOverlay.ROAD) != 0:
					road_cells.append(Vector3i(x, y, road_flags))
	static_visual.configure(
		ImageTexture.create_from_image(image),
		road_cells,
		debug_view == DebugView.TRAVEL or debug_view == DebugView.GLOBAL_TRAVEL
	)

func _region_visual_cell_color(
		region_cell: Vector2i,
		terrain_type: int,
		cell_index: int,
		visual_code: int,
		thumbnail_cell: Vector2i = Vector2i.ZERO
	) -> Color:
	if debug_view == DebugView.NORMAL:
		var base_color: Color = MapArtCatalogType.thumbnail_color(
			terrain_type,
			visual_code,
			thumbnail_cell,
			SITE_THUMBNAIL_GRID_SIZE
		)
		if cell_index < resource_visual_types.size() and resource_visual_types[cell_index] >= 0:
			var resource_amount: int = resource_visual_amounts[cell_index]
			var resource_color: Color = _resource_visual_color(resource_visual_types[cell_index])
			var resource_strength: float = clampf(float(resource_amount) / 120.0, 0.0, 1.0)
			base_color = base_color.lerp(resource_color, 0.08 + resource_strength * 0.12)
		if terrain_data != null and cell_index < terrain_data.elevation_data.size():
			var elevation: float = float(terrain_data.elevation_data[cell_index]) / 255.0
			var relief_strength: float = clampf(absf(elevation - 0.5) * 0.75, 0.0, 0.36)
			var relief_color: Color = Color("c4a96b") if elevation > 0.5 else Color("477c5c")
			base_color = base_color.lerp(relief_color, relief_strength)
		return base_color
	var terrain_color: Color = TerrainType.to_color(terrain_type)
	var cell_color: Color = terrain_color
	match debug_view:
		DebugView.ELEVATION:
			var elevation: float = float(terrain_data.elevation_data[cell_index]) / 255.0
			cell_color = Color(elevation, elevation, elevation)
		DebugView.MOISTURE:
			var moisture: float = float(terrain_data.moisture_data[cell_index]) / 255.0
			cell_color = Color(0.03 + moisture * 0.12, 0.12 + moisture * 0.70, 0.18 + moisture * 0.55)
		DebugView.RIVER:
			cell_color = Color("55c7ff") if terrain_data.river_strength_data[cell_index] > 0 else Color("30343b")
		DebugView.POI:
			cell_color = terrain_color.darkened(0.45)
		DebugView.ROAD:
			cell_color = terrain_color.darkened(0.62)
		DebugView.TRAVEL, DebugView.GLOBAL_TRAVEL:
			cell_color = _travel_cell_color(region_cell)
		_:
			if terrain_data.river_strength_data[cell_index] > 0:
				cell_color = RIVER_COLOR
	return cell_color
func _debug_view_name() -> String:
	match debug_view:
		DebugView.ELEVATION:
			return "ELEVATION"
		DebugView.MOISTURE:
			return "MOISTURE"
		DebugView.RIVER:
			return "RIVER"
		DebugView.POI:
			return "POI"
		DebugView.ROAD:
			return "ROAD"
		DebugView.TRAVEL:
			return "TRAVEL"
		DebugView.GLOBAL_TRAVEL:
			return "GLOBAL_TRAVEL"
		_:
			return "NORMAL"

func _cell_from_global_position(mouse_global_position: Vector2) -> Vector2i:
	var map_position: Vector2 = to_local(mouse_global_position)
	return Vector2i(
		floori((map_position.x - MAP_ORIGIN.x) / CELL_PIXEL_SIZE),
		floori((map_position.y - MAP_ORIGIN.y) / CELL_PIXEL_SIZE)
	)

func _cell_center(region_cell: Vector2i) -> Vector2:
	return MAP_ORIGIN + Vector2(region_cell.x, region_cell.y) * CELL_PIXEL_SIZE + Vector2.ONE * CELL_PIXEL_SIZE * 0.5

func _cell_rect(region_cell: Vector2i) -> Rect2:
	return Rect2(
		MAP_ORIGIN + Vector2(region_cell) * CELL_PIXEL_SIZE,
		Vector2.ONE * CELL_PIXEL_SIZE
	)

func _is_valid_region_cell(region_cell: Vector2i) -> bool:
	return region_cell.x >= 0 and region_cell.y >= 0 \
		and region_cell.x < GRID_SIZE.x and region_cell.y < GRID_SIZE.y

func _set_hovered_region_cell(region_cell: Vector2i) -> void:
	if not _is_valid_region_cell(region_cell):
		region_cell = Vector2i(-1, -1)
	if hovered_region_cell == region_cell:
		return
	hovered_region_cell = region_cell
	_refresh_construction_preview()
	queue_redraw()
	debug_state_changed.emit(get_debug_state())

func _set_zoom(factor: float) -> void:
	var next_zoom: float = clampf(camera.zoom.x * factor, 0.25, 2.0)
	camera.zoom = Vector2.ONE * next_zoom

func _poi_at(region_cell: Vector2i) -> WorldPOIData:
	for poi: WorldPOIData in pois:
		if poi.region_cell == region_cell and (resolved_region == null or resolved_region.is_feature_active(poi.poi_id)):
			return poi
	return null

func _poi_label(region_cell: Vector2i) -> String:
	var poi: WorldPOIData = _poi_at(region_cell)
	if poi == null:
		return "Strategic Site at selected cell"
	return "%s (%s)" % [poi.site_name, WorldPOIType.to_display_name(poi.poi_type)]

func _draw_outposts() -> void:
	for feature: RegionFeatureDelta in resolved_region.get_runtime_features_by_type(
			RegionRuntime.OUTPOST_FEATURE_TYPE
		):
		var center: Vector2 = _cell_center(feature.region_cell)
		var outpost_texture: Texture2D = MapArtCatalogType.outpost_texture()
		if outpost_texture != null:
			draw_texture_rect(
				outpost_texture,
				Rect2(center - Vector2.ONE * 24.0, Vector2.ONE * 48.0),
				false
			)
		else:
			var marker: Rect2 = Rect2(center - Vector2.ONE * 15.0, Vector2.ONE * 30.0)
			draw_rect(marker, Color("d6a84a"))
			draw_rect(marker, Color("fff0b0"), false, 3.0)

func _draw_region_roads() -> void:
	if debug_view != DebugView.NORMAL or road_overlay == null or region == null:
		return
	if travel_road_cells.is_empty():
		return
	# Draw only explicit route edges. Merely touching two road cells is not enough:
	# the reciprocal edge must exist in both cells, otherwise Site would render a
	# different connection at the same global coordinate.
	for cell_variant: Variant in travel_road_cells.keys():
		var cell: Vector2i = cell_variant as Vector2i
		var center: Vector2 = _cell_center(cell)
		var offsets: Array[Vector2i] = travel_road_offsets.get(cell, []) as Array[Vector2i]
		for direction: Vector2i in offsets:
			var neighbor: Vector2i = cell + direction
			if _is_valid_region_cell(neighbor):
				if not travel_road_cells.has(neighbor):
					continue
				var neighbor_offsets: Array[Vector2i] = travel_road_offsets.get(
					neighbor,
					[]
				) as Array[Vector2i]
				if -direction not in neighbor_offsets:
					continue
				# Draw each shared edge once.
				if cell.x > neighbor.x or (cell.x == neighbor.x and cell.y > neighbor.y):
					continue
				_draw_region_road_link(center, _cell_center(neighbor))
			else:
				# The neighboring Region draws its reciprocal half.
				_draw_region_road_link(
					center,
					center + Vector2(direction) * CELL_PIXEL_SIZE * 0.5
				)
	for cell_variant: Variant in travel_road_cells.keys():
		var cell: Vector2i = cell_variant as Vector2i
		var center: Vector2 = _cell_center(cell)
		var road_tile: Rect2 = Rect2(center - Vector2.ONE * 15.0, Vector2.ONE * 30.0)
		draw_rect(road_tile, Color(0.12, 0.09, 0.06, 0.94))
		draw_rect(road_tile.grow(-2.0), Color("d1aa68"))
		if bool(travel_road_crossings.get(cell, false)):
			draw_rect(road_tile.grow(-8.0), Color("75d8df"), false, 3.0)

func _draw_region_road_link(from: Vector2, to: Vector2) -> void:
	draw_line(from, to, Color(0.12, 0.09, 0.06, 0.94), 30.0, true)
	draw_line(from, to, Color("d1aa68"), 26.0, true)

func _draw_region_rivers() -> void:
	if debug_view != DebugView.NORMAL or resolved_region == null:
		return
	if travel_river_cells.is_empty():
		return
	# Use the same reciprocal cardinal edges that CELL_BASE Sites use. Region
	# must not derive a second river centreline from scalar noise strength.
	for cell_variant: Variant in travel_river_cells.keys():
		var cell: Vector2i = cell_variant as Vector2i
		var center: Vector2 = _cell_center(cell)
		var offsets: Array[Vector2i] = travel_river_offsets.get(cell, []) as Array[Vector2i]
		for direction: Vector2i in offsets:
			var neighbor: Vector2i = cell + direction
			if _is_valid_region_cell(neighbor):
				if not travel_river_cells.has(neighbor):
					continue
				var neighbor_offsets: Array[Vector2i] = travel_river_offsets.get(
					neighbor,
					[]
				) as Array[Vector2i]
				if -direction not in neighbor_offsets:
					continue
				# Draw each shared edge once.
				if cell.x > neighbor.x or (cell.x == neighbor.x and cell.y > neighbor.y):
					continue
				_draw_river_segment(center, _cell_center(neighbor))
			else:
				# The adjacent Region draws its reciprocal half.
				_draw_river_segment(
					center,
					center + Vector2(direction) * CELL_PIXEL_SIZE * 0.5
				)
		draw_circle(center, 12.0, Color("24566b"))
		draw_circle(center, 7.0, Color("62cfe2"))

func _draw_river_segment(from: Vector2, to: Vector2) -> void:
	draw_line(from, to, Color("24566b"), 24.0, true)
	draw_line(from, to, Color("62cfe2"), 13.0, true)

func _region_travel_info(region_cell: Vector2i) -> Dictionary:
	if travel_runtime == null or session == null or region == null \
		or not _is_valid_region_cell(region_cell):
		return {"valid": false}
	var global_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
		region.world_cell,
		region_cell
	)
	return travel_runtime._travel_cell_info(global_cell)

func _cardinal_offsets(value: Variant) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not value is Array:
		return result
	for offset: Variant in value as Array:
		if not offset is Vector2i:
			continue
		var direction: Vector2i = offset as Vector2i
		if absi(direction.x) + absi(direction.y) != 1:
			continue
		if not result.has(direction):
			result.append(direction)
	result.sort_custom(Callable(self, "_offset_less"))
	return result

func _offset_less(left: Vector2i, right: Vector2i) -> bool:
	return left.y < right.y or (left.y == right.y and left.x < right.x)

func _draw_region_resources() -> void:
	if debug_view != DebugView.NORMAL or site_content_data == null or not site_content_data.is_valid():
		return
	for y: int in range(1, GRID_SIZE.y, 4):
		for x: int in range(1, GRID_SIZE.x, 4):
			var cell_index: int = y * GRID_SIZE.x + x
			if cell_index >= resource_visual_types.size():
				continue
			var resource_type: int = resource_visual_types[cell_index]
			var amount: int = resource_visual_amounts[cell_index]
			if resource_type < 0 or amount < 8 \
				or not _region_resource_marker_is_peak(Vector2i(x, y), resource_type, amount):
				continue
			var marker_center: Vector2 = _cell_center(Vector2i(x, y))
			draw_circle(marker_center, 18.0, Color("1b2420"))
			draw_circle(marker_center, 11.0, _resource_visual_color(resource_type))
			draw_circle(marker_center - Vector2(3.0, 3.0), 2.5, Color("fff4bd"))

func _region_resource_marker_is_peak(cell: Vector2i, resource_type: int, amount: int) -> bool:
	for offset: Vector2i in [
		Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
		Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)
	]:
		var neighbor: Vector2i = cell + offset
		if not WorldCoordinates.is_valid_region_cell(neighbor):
			continue
		var neighbor_index: int = neighbor.y * GRID_SIZE.x + neighbor.x
		if neighbor_index >= resource_visual_types.size() \
			or resource_visual_types[neighbor_index] != resource_type:
			continue
		var neighbor_amount: int = resource_visual_amounts[neighbor_index]
		if neighbor_amount > amount:
			return false
		if neighbor_amount == amount and (neighbor.y < cell.y \
			or (neighbor.y == cell.y and neighbor.x < cell.x)):
			return false
	return true

func _draw_region_relief_contours() -> void:
	if debug_view != DebugView.NORMAL or resolved_region == null:
		return
	for y: int in range(GRID_SIZE.y):
		for x: int in range(GRID_SIZE.x):
			var cell: Vector2i = Vector2i(x, y)
			var elevation: float = resolved_region.get_elevation(cell)
			if x + 1 < GRID_SIZE.x:
				var east_elevation: float = resolved_region.get_elevation(cell + Vector2i.RIGHT)
				var east_delta: float = east_elevation - elevation
				if absf(east_delta) >= 0.09:
					var boundary_x: float = MAP_ORIGIN.x + float(x + 1) * CELL_PIXEL_SIZE
					draw_line(
						Vector2(boundary_x, MAP_ORIGIN.y + float(y) * CELL_PIXEL_SIZE + 4.0),
						Vector2(boundary_x, MAP_ORIGIN.y + float(y + 1) * CELL_PIXEL_SIZE - 4.0),
						Color(0.18, 0.22, 0.16, clampf(absf(east_delta) * 1.8, 0.12, 0.34)),
						2.0,
						true
					)
			if y + 1 < GRID_SIZE.y:
				var south_elevation: float = resolved_region.get_elevation(cell + Vector2i.DOWN)
				var south_delta: float = south_elevation - elevation
				if absf(south_delta) >= 0.09:
					var boundary_y: float = MAP_ORIGIN.y + float(y + 1) * CELL_PIXEL_SIZE
					draw_line(
						Vector2(MAP_ORIGIN.x + float(x) * CELL_PIXEL_SIZE + 4.0, boundary_y),
						Vector2(MAP_ORIGIN.x + float(x + 1) * CELL_PIXEL_SIZE - 4.0, boundary_y),
						Color(0.18, 0.22, 0.16, clampf(absf(south_delta) * 1.8, 0.12, 0.34)),
						2.0,
						true
					)

func _resource_visual_color(resource_type: int) -> Color:
	match resource_type:
		SiteContentTypesType.RESOURCE_GRASS:
			return Color("9fd36b")
		SiteContentTypesType.RESOURCE_FRUIT_TREE:
			return Color("f2a24b")
		SiteContentTypesType.RESOURCE_FOREST:
			return Color("2c8f58")
		SiteContentTypesType.RESOURCE_STONE_ORE:
			return Color("b8bec4")
		SiteContentTypesType.RESOURCE_IRON_ORE:
			return Color("bd694c")
		SiteContentTypesType.RESOURCE_SILVER_ORE:
			return Color("d7e4ec")
		SiteContentTypesType.RESOURCE_GOLD_ORE:
			return Color("f4d15b")
	return Color("ffffff")

func _draw_construction_preview() -> void:
	if not construction_mode or construction_preview == null:
		return
	var cell_rect: Rect2 = Rect2(
		MAP_ORIGIN + Vector2(construction_preview.region_cell) * CELL_PIXEL_SIZE,
		Vector2.ONE * CELL_PIXEL_SIZE
	).grow(-7.0)
	var color: Color = Color(0.25, 0.9, 0.45, 0.55) if construction_preview.success \
		else Color(0.95, 0.25, 0.25, 0.45)
	draw_rect(cell_rect, color)
	draw_rect(cell_rect, color.lightened(0.25), false, 3.0)

func _travel_cell_color(region_cell: Vector2i) -> Color:
	var global_cell: Vector2i = WorldCoordinates.world_region_to_global_region_cell(
			region.world_cell,
			region_cell
		)
	var info: TravelCellResult = travel_runtime.query_travel_cell(global_cell)
	if not info.passable:
		return Color("111318")
	if info.road:
		return Color("3f8dff")
	var speed: float = info.speed
	if speed <= 2.25:
		return Color("d95757")
	if speed < 4.0:
		return Color("e0a44b")
	return Color("5bbf70")

func _draw_path_preview() -> void:
	if session != null and session.active_global_travel_path != null:
		_draw_global_path_segment()
		return
	if path_preview == null or path_preview.path == null or path_preview.path.cells.is_empty():
		return
	var points: PackedVector2Array = PackedVector2Array()
	for global_cell: Vector2i in path_preview.path.cells:
		var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(global_cell)
		if converted["world_cell"] as Vector2i != region.world_cell:
			continue
		points.append(_cell_center(converted["region_cell"] as Vector2i))
	if points.size() >= 2:
		draw_polyline(points, Color("fff1a8"), 9.0, true)
	for global_cell: Vector2i in path_preview.path.cells:
		var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(global_cell)
		if converted["world_cell"] as Vector2i == region.world_cell:
			draw_circle(_cell_center(converted["region_cell"] as Vector2i), 8.0, Color("fff7c2"))
	var destination_rect: Rect2 = Rect2(
			_cell_center(destination_region_cell) - Vector2.ONE * 24.0,
			Vector2.ONE * 48.0
	)
	draw_rect(destination_rect, Color("fff1a8"), false, 4.0)

func _draw_global_path_segment() -> void:
	var path: GlobalTravelPathType = session.active_global_travel_path
	if path == null or region == null:
		return
	var points: PackedVector2Array = PackedVector2Array()
	for global_cell: Vector2i in path.cells:
		var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(global_cell)
		if converted["world_cell"] as Vector2i != region.world_cell:
			continue
		var local_cell: Vector2i = converted["region_cell"] as Vector2i
		points.append(_cell_center(local_cell))
	if points.size() >= 2:
		draw_polyline(points, Color("fff1a8"), 9.0, true)
	for point: Vector2 in points:
		draw_circle(point, 8.0, Color("fff7c2"))
	var destination_region: Dictionary = WorldCoordinates.global_region_cell_to_world_region(
		path.destination_global_cell
	)
	if destination_region["world_cell"] as Vector2i == region.world_cell:
		var destination_cell: Vector2i = destination_region["region_cell"] as Vector2i
		var destination_rect: Rect2 = Rect2(
				_cell_center(destination_cell) - Vector2.ONE * 24.0,
				Vector2.ONE * 48.0
		)
		draw_rect(destination_rect, Color("fff1a8"), false, 4.0)

func _route_details(route_ids: Array[String]) -> String:
	if route_ids.is_empty():
		return "None"
	var details: Array[String] = []
	for route_id: String in route_ids:
		var route: WorldRoadRoute = road_overlay.get_route(route_id)
		if route != null:
			details.append(route.debug_summary())
	return " || ".join(details)

func _resolved_road_flags(region_cell: Vector2i) -> int:
	if resolved_region == null:
		return 0
	var flags: int = 0
	for route_id: String in road_overlay.get_route_ids(region_cell):
		if not resolved_region.is_feature_active(route_id):
			continue
		flags |= RegionRoadOverlay.ROAD
		if (road_overlay.get_flags(region_cell) & RegionRoadOverlay.RIVER_CROSSING) != 0:
			flags |= RegionRoadOverlay.RIVER_CROSSING
	return flags

func _resolved_route_ids(region_cell: Vector2i) -> Array[String]:
	var result: Array[String] = []
	for route_id: String in road_overlay.get_route_ids(region_cell):
		if resolved_region != null and resolved_region.is_feature_active(route_id):
			result.append(route_id)
	return result

func _format_cell(cell: Vector2i) -> String:
	return "(%d, %d)" % [cell.x, cell.y]

func _format_optional_cell(cell: Vector2i) -> String:
	if not _is_valid_region_cell(cell):
		return "??"
	return _format_cell(cell)

func _format_meters(meters: Vector2i) -> String:
	return "(%dm, %dm)" % [meters.x, meters.y]
