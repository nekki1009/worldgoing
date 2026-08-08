class_name NavigationController
extends Node

const GlobalTravelPathType = preload("res://scripts/data/global_travel_path.gd")

enum MapLayer {
	WORLD,
	REGION,
	SITE,
}

signal debug_state_changed(state: Dictionary)

const WORLD_MAP_SCENE: PackedScene = preload("res://scenes/world/WorldMap.tscn")
const REGION_MAP_SCENE: PackedScene = preload("res://scenes/region/RegionMap.tscn")
const SITE_MAP_SCENE: PackedScene = preload("res://scenes/site/SiteMap.tscn")

var session: GameSession = GameSession.new()
var world_data: WorldData = WorldData.new()
var current_layer: int = MapLayer.WORLD
var map_root: Node2D
var current_map: Node2D
var party_pathfinder: PartyPathfinder = PartyPathfinder.new()
var travel_loop_running: bool = false

func setup(p_map_root: Node2D) -> void:
	map_root = p_map_root

func start() -> void:
	show_world()

func get_current_layer() -> int:
	return current_layer

func get_current_map() -> Node2D:
	return current_map

func get_session() -> GameSession:
	return session

func show_world() -> void:
	current_layer = MapLayer.WORLD
	var world_map: WorldMap = _replace_map(WORLD_MAP_SCENE) as WorldMap
	world_map.region_enter_requested.connect(enter_region)
	world_map.travel_plan_requested.connect(plan_travel_to_global_cell)
	world_map.travel_confirm_requested.connect(confirm_global_travel)
	world_map.debug_state_changed.connect(_on_map_debug_state_changed)
	world_map.setup(world_data, session)

func show_region() -> void:
	var region: RegionData = world_data.get_region(session.selected_world_cell)
	if region == null:
		return
	current_layer = MapLayer.REGION
	session.current_region_id = region.region_id
	var terrain_data: RegionTerrainData = world_data.get_or_generate_region_terrain(
		session.selected_world_cell,
		session.world_seed
	)
	var road_overlay: RegionRoadOverlay = world_data.get_roads_for_region(
		session.selected_world_cell,
		session.world_seed
	)
	_ensure_party_spawn(terrain_data, road_overlay)
	var region_map: RegionMap = _replace_map(REGION_MAP_SCENE) as RegionMap
	region_map.site_enter_requested.connect(enter_site_at)
	region_map.local_travel_confirm_requested.connect(begin_local_travel)
	region_map.global_travel_confirm_requested.connect(confirm_global_travel)
	region_map.debug_state_changed.connect(_on_map_debug_state_changed)
	region_map.setup(
		region,
		terrain_data,
		world_data.get_pois_for_region(session.selected_world_cell, session.world_seed),
		session,
		road_overlay
	)

func show_site(poi: WorldPOIData) -> void:
	var region: RegionData = world_data.get_region(session.selected_world_cell)
	if region == null:
		return
	current_layer = MapLayer.SITE
	session.current_site_id = poi.poi_id
	var site_map: SiteMap = _replace_map(SITE_MAP_SCENE) as SiteMap
	site_map.debug_state_changed.connect(_on_map_debug_state_changed)
	site_map.setup(poi, region, session)

func _replace_map(scene: PackedScene) -> Node2D:
	if is_instance_valid(current_map):
		current_map.queue_free()
	current_map = scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) as Node2D
	map_root.add_child(current_map)
	return current_map

func enter_region(world_cell: Vector2i) -> void:
	if not world_data.is_valid_world_cell(world_cell):
		return
	session.selected_world_cell = world_cell
	show_region()

func enter_site_at(region_cell: Vector2i) -> void:
	if not can_enter_site_at(region_cell):
		return
	session.selected_region_cell = region_cell
	var poi: WorldPOIData = world_data.find_poi_at(
		session.selected_world_cell,
		region_cell,
		session.world_seed
	)
	if poi != null:
		show_site(poi)

func can_enter_site_at(region_cell: Vector2i) -> bool:
	if session.is_traveling() or session.party.get_world_cell() != session.selected_world_cell:
		return false
	if not session.party.is_at(session.party.get_world_cell(), region_cell):
		return false
	return world_data.find_poi_at(
			session.selected_world_cell,
			region_cell,
			session.world_seed
		) != null

func _ensure_party_spawn(terrain_data: RegionTerrainData, road_overlay: RegionRoadOverlay) -> void:
	if session.party.initialized:
		return
	var center: Vector2i = session.selected_region_cell
	var chosen: Vector2i = Vector2i(-1, -1)
	for radius: int in range(0, WorldCoordinates.REGION_GRID_SIZE * 2):
		var min_x: int = maxi(0, center.x - radius)
		var max_x: int = mini(WorldCoordinates.REGION_GRID_SIZE - 1, center.x + radius)
		var min_y: int = maxi(0, center.y - radius)
		var max_y: int = mini(WorldCoordinates.REGION_GRID_SIZE - 1, center.y + radius)
		for y: int in range(min_y, max_y + 1):
			for x: int in range(min_x, max_x + 1):
				var candidate: Vector2i = Vector2i(x, y)
				if maxi(absi(candidate.x - center.x), absi(candidate.y - center.y)) != radius:
					continue
				if _is_party_cell_passable(terrain_data, road_overlay, candidate):
					chosen = candidate
					break
			if chosen != Vector2i(-1, -1):
				break
		if chosen != Vector2i(-1, -1):
			break
	if chosen == Vector2i(-1, -1):
		chosen = Vector2i(50, 50)
	session.party.set_global_region_cell(WorldCoordinates.world_region_to_global_region_cell(
		session.selected_world_cell,
		chosen
	))
	session.party.initialized = true
	session.selected_region_cell = chosen

func plan_travel_to_global_cell(destination_global_cell: Vector2i, destination_poi_id: String = "") -> bool:
	if session.is_traveling():
		return false
	_ensure_party_ready()
	var path: GlobalTravelPathType = party_pathfinder.find_global_path(
			world_data,
			session.party.current_global_region_cell,
			destination_global_cell,
			session.world_seed,
			session.party.base_walk_speed_kmh
		)
	if not path.has_path():
		session.clear_travel()
		session.travel_error = path.error_message
		session.last_travel_message = path.error_message
		_emit_current_debug_state()
		return false
	session.set_travel_plan(path, destination_poi_id)
	session.last_travel_message = "Global travel planned"
	_emit_current_debug_state()
	if current_map != null and current_map.has_method("queue_redraw"):
		current_map.queue_redraw()
	return true

func confirm_global_travel() -> bool:
	if session.is_traveling() or not session.confirm_travel():
		return false
	session.last_travel_message = "Global travel started"
	if session.party.initialized:
		session.selected_world_cell = session.party.get_world_cell()
		session.selected_region_cell = session.party.get_region_cell()
	show_region()
	_start_travel_loop()
	return true

func begin_local_travel(local_path: PartyPathResult) -> bool:
	if local_path == null or not local_path.has_path() or session.is_traveling():
		return false
	var travel_path: GlobalTravelPathType = GlobalTravelPathType.new()
	travel_path.start_global_cell = session.party.current_global_region_cell
	for local_cell: Vector2i in local_path.cells:
		travel_path.cells.append(WorldCoordinates.world_region_to_global_region_cell(
			session.party.get_world_cell(),
			local_cell
		))
	travel_path.destination_global_cell = travel_path.cells.back()
	travel_path.step_travel_seconds = local_path.step_travel_seconds.duplicate()
	travel_path.total_distance_meters = local_path.total_distance_meters
	travel_path.estimated_travel_seconds = local_path.estimated_travel_seconds
	travel_path.regions_crossed = 1
	session.set_travel_plan(travel_path)
	session.confirm_travel()
	if current_map != null and current_map.has_method("clear_local_path_preview"):
		current_map.clear_local_path_preview()
	_start_travel_loop()
	return true

func cancel_travel() -> void:
	if not session.has_travel_plan():
		return
	if session.is_traveling():
		session.travel_cancel_requested = true
		return
	session.clear_travel()
	session.last_travel_message = "Travel plan cancelled"
	_emit_current_debug_state()

func _ensure_party_ready() -> void:
	if session.party.initialized:
		return
	var selected_before_spawn: Vector2i = session.selected_world_cell
	var spawn_world_cell: Vector2i = session.party.get_world_cell()
	session.selected_world_cell = spawn_world_cell
	var terrain_data: RegionTerrainData = world_data.get_or_generate_region_terrain(
			spawn_world_cell,
			session.world_seed
		)
	var road_overlay: RegionRoadOverlay = world_data.get_roads_for_region(
			spawn_world_cell,
			session.world_seed
		)
	_ensure_party_spawn(terrain_data, road_overlay)
	session.selected_world_cell = selected_before_spawn

func _start_travel_loop() -> void:
	if travel_loop_running:
		return
	travel_loop_running = true
	call_deferred("_run_travel_loop")

func _run_travel_loop() -> void:
	var path: GlobalTravelPathType = session.active_global_travel_path
	while session.is_traveling() and path != null and session.global_travel_path_index < path.cells.size() - 1:
		if session.travel_cancel_requested:
			break
		var path_index: int = session.global_travel_path_index
		var from_global_cell: Vector2i = path.cells[path_index]
		var next_global_cell: Vector2i = path.cells[path_index + 1]
		var previous_world_cell: Vector2i = session.party.get_world_cell()
		var next_world_region: Dictionary = WorldCoordinates.global_region_cell_to_world_region(next_global_cell)
		var next_world_cell: Vector2i = next_world_region["world_cell"] as Vector2i
		var next_region_cell: Vector2i = next_world_region["region_cell"] as Vector2i
		if current_map != null and is_instance_valid(current_map) \
			and current_map.has_method("animate_party_step") \
			and previous_world_cell == next_world_cell:
			await current_map.call("animate_party_step", next_region_cell, session.travel_speed_multiplier)
		else:
			await get_tree().process_frame
		session.party.set_global_region_cell(next_global_cell)
		session.global_travel_path_index = path_index + 1
		session.advance_world_time(path.step_travel_seconds[path_index] if path_index < path.step_travel_seconds.size() else 0)
		session.selected_world_cell = next_world_cell
		session.selected_region_cell = next_region_cell
		if previous_world_cell != next_world_cell:
			print("Region Transition: %s -> %s | Global Cell: %s -> %s" % [
				_format_cell(previous_world_cell),
				_format_cell(next_world_cell),
				_format_cell(from_global_cell),
				_format_cell(next_global_cell),
			])
			show_region()
		else:
			if current_map != null and is_instance_valid(current_map) \
				and current_map.has_method("sync_party_position"):
				current_map.call("sync_party_position")
		_emit_current_debug_state()
	if path != null and session.is_traveling():
		var cancelled: bool = session.travel_cancel_requested
		if cancelled:
			session.last_travel_message = "Travel cancelled after current step"
		else:
			session.last_travel_message = _arrival_message(path)
		session.clear_travel()
		if current_map != null and is_instance_valid(current_map) \
			and current_map.has_method("sync_party_position"):
			current_map.call("sync_party_position")
		_emit_current_debug_state()
	travel_loop_running = false

func _arrival_message(path: GlobalTravelPathType) -> String:
	if path.destination_poi_id.is_empty():
		return "Arrived at %s" % _format_cell(path.destination_global_cell)
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(path.destination_global_cell)
	var pois: Array[WorldPOIData] = world_data.get_pois_for_region(
			converted["world_cell"] as Vector2i,
			session.world_seed
		)
	for poi: WorldPOIData in pois:
		if poi.poi_id == path.destination_poi_id:
			return "Arrived at %s" % poi.site_name
	return "Arrived at %s" % _format_cell(path.destination_global_cell)

func _emit_current_debug_state() -> void:
	if current_map != null and is_instance_valid(current_map) and current_map.has_method("get_debug_state"):
		debug_state_changed.emit(current_map.get_debug_state())

func _is_party_cell_passable(
		terrain_data: RegionTerrainData,
		road_overlay: RegionRoadOverlay,
		region_cell: Vector2i
	) -> bool:
	if terrain_data == null or not WorldCoordinates.is_valid_region_cell(region_cell):
		return false
	var terrain_type: int = terrain_data.get_terrain(region_cell)
	return TravelCostConfig.is_passable(
			terrain_type,
			terrain_data.has_river(region_cell),
			road_overlay != null and road_overlay.has_river_crossing(region_cell)
		)

func _on_map_debug_state_changed(state: Dictionary) -> void:
	debug_state_changed.emit(state)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if session.is_traveling():
		match key_event.keycode:
			KEY_ESCAPE:
				session.travel_cancel_requested = true
				get_viewport().set_input_as_handled()
			KEY_1:
				session.travel_speed_multiplier = 1.0
				_emit_current_debug_state()
				get_viewport().set_input_as_handled()
			KEY_2:
				session.travel_speed_multiplier = 4.0
				_emit_current_debug_state()
				get_viewport().set_input_as_handled()
			KEY_3:
				session.travel_speed_multiplier = 16.0
				_emit_current_debug_state()
				get_viewport().set_input_as_handled()
		return
	if session.has_travel_plan() and key_event.keycode == KEY_ENTER:
		confirm_global_travel()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode != KEY_T and key_event.keycode != KEY_ESCAPE:
		return
	match current_layer:
		MapLayer.SITE:
			show_region()
		MapLayer.REGION:
			show_world()
		MapLayer.WORLD:
			return
	get_viewport().set_input_as_handled()

func _format_cell(cell: Vector2i) -> String:
	return "(%d, %d)" % [cell.x, cell.y]
