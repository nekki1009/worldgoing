class_name NavigationController
extends Node

const GlobalTravelPathType = preload("res://scripts/data/global_travel_path.gd")
const BattlePreviewRuntimeType = preload("res://scripts/runtime/battle_preview_runtime.gd")
const RegionRuntimeType = preload("res://scripts/runtime/region_runtime.gd")
const TravelRuntimeType = preload("res://scripts/runtime/travel_runtime.gd")
const TravelFailureReasonType = preload("res://scripts/runtime/travel_failure_reason.gd")
const BattleRuntimeResultType = preload("res://scripts/runtime/battle_runtime_result.gd")

enum MapLayer {
	WORLD,
	REGION,
	SITE,
	BATTLE_SITE,
}

signal debug_state_changed(state: Dictionary)

const WORLD_MAP_SCENE: PackedScene = preload("res://scenes/world/WorldMap.tscn")
const REGION_MAP_SCENE: PackedScene = preload("res://scenes/region/RegionMap.tscn")
const SITE_MAP_SCENE: PackedScene = preload("res://scenes/site/SiteMap.tscn")
const BATTLE_SITE_SCENE: PackedScene = preload("res://scenes/site/BattleSite.tscn")

var session: GameSession = GameSession.new()
var world_data: WorldData = WorldData.new()
var current_layer: int = MapLayer.WORLD
var map_root: Node2D
var current_map: Node2D
var region_runtime: RegionRuntime
var travel_runtime: TravelRuntime
var battle_preview_runtime: BattlePreviewRuntime
var pending_global_destination: Vector2i = Vector2i(-1, -1)
var pending_global_poi_id: String = ""
var travel_loop_running: bool = false

func _init() -> void:
	region_runtime = RegionRuntimeType.new(session, world_data)
	travel_runtime = TravelRuntimeType.new(session, world_data)
	battle_preview_runtime = BattlePreviewRuntimeType.new(session, world_data, region_runtime)
	travel_runtime.travel_started.connect(_on_travel_started)

func setup(p_map_root: Node2D) -> void:
	map_root = p_map_root
	_sync_runtime()

func start() -> void:
	_sync_runtime()
	world_data.get_or_generate_world_overview(session.world_seed)
	show_world()

func get_current_layer() -> int:
	return current_layer

func get_current_map() -> Node2D:
	return current_map

func get_session() -> GameSession:
	return session

func replace_session(p_session: GameSession) -> bool:
	if p_session == null or p_session.party == null:
		return false
	var global_cell: Vector2i = p_session.party.current_global_region_cell
	var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(global_cell)
	var world_cell: Vector2i = converted["world_cell"] as Vector2i
	if not world_data.is_valid_world_cell(world_cell):
		return false
	session = p_session
	session.selected_world_cell = world_cell
	session.selected_region_cell = converted["region_cell"] as Vector2i
	pending_global_destination = Vector2i(-1, -1)
	pending_global_poi_id = ""
	_sync_runtime()
	if map_root != null:
		show_region()
	return true

func show_world() -> void:
	_sync_runtime()
	if session.has_active_battle():
		battle_preview_runtime.leave_battle()
	current_layer = MapLayer.WORLD
	travel_runtime.leave_site(session.party.party_id)
	var world_map: WorldMap = _replace_map(WORLD_MAP_SCENE) as WorldMap
	world_map.region_enter_requested.connect(enter_region)
	world_map.debug_state_changed.connect(_on_map_debug_state_changed)
	world_map.setup(world_data, session, travel_runtime)

func show_region(preserve_selection: bool = false) -> void:
	_sync_runtime()
	if session.has_active_battle():
		battle_preview_runtime.leave_battle()
	var region: RegionData = world_data.get_region(session.selected_world_cell)
	if region == null:
		return
	current_layer = MapLayer.REGION
	travel_runtime.leave_site(session.party.party_id)
	session.current_region_id = region.region_id
	var terrain_data: RegionTerrainData = world_data.get_or_generate_region_terrain(
		session.selected_world_cell,
		session.world_seed
	)
	# Region Site profiles are packed strategic-cell data.  Materialise them at
	# Region entry so every later Site (POI or ordinary tile) reads the same
	# deterministic allocation instead of falling back to a second formula.
	world_data.get_or_generate_region_site_content(
		session.selected_world_cell,
		session.world_seed
	)
	var road_overlay: RegionRoadOverlay = world_data.get_roads_for_region(
		session.selected_world_cell,
		session.world_seed
	)
	travel_runtime.ensure_party_spawn(session.selected_world_cell, session.selected_region_cell)
	var region_map: RegionMap = _replace_map(REGION_MAP_SCENE) as RegionMap
	region_map.site_enter_requested.connect(enter_site_at)
	region_map.battle_preview_requested.connect(show_battle_site)
	region_map.debug_state_changed.connect(_on_map_debug_state_changed)
	region_map.setup(
		region,
		terrain_data,
		world_data.get_pois_for_region(session.selected_world_cell, session.world_seed),
		session,
		road_overlay,
		travel_runtime,
		region_runtime,
		battle_preview_runtime,
		preserve_selection
	)

func show_site(
		poi: WorldPOIData,
		definition: SiteData = null,
		snapshot: SiteRuntimeSnapshot = null
	) -> void:
	_sync_runtime()
	if poi == null:
		return
	var site_definition: SiteData = definition if definition != null else world_data.get_site_definition(poi)
	if site_definition == null:
		return
	show_site_definition(site_definition, snapshot)

func show_site_definition(
		definition: SiteData,
		snapshot: SiteRuntimeSnapshot = null
	) -> void:
	_sync_runtime()
	if definition == null:
		return
	var begin_result: SiteRuntimeCommandResult = travel_runtime.begin_site_visit(
		session.party.party_id,
		definition.site_id
	)
	if not begin_result.success:
		return
	var site_snapshot: SiteRuntimeSnapshot = snapshot
	if site_snapshot == null:
		var query_result: SiteRuntimeQueryResult = travel_runtime.query_site_snapshot(definition.site_id)
		if not query_result.success:
			return
		site_snapshot = query_result.snapshot
	current_layer = MapLayer.SITE
	var site_map: SiteMap = _replace_map(SITE_MAP_SCENE) as SiteMap
	site_map.move_requested.connect(_on_site_move_requested)
	site_map.debug_state_changed.connect(_on_map_debug_state_changed)
	site_map.setup(site_snapshot)

func show_battle_site(snapshot: BattleSiteSnapshot) -> void:
	_sync_runtime()
	if snapshot == null or not snapshot.has_preview():
		return
	var begin_result: BattleRuntimeResult = battle_preview_runtime.begin_battle(snapshot)
	if not begin_result.success or begin_result.snapshot == null:
		return
	current_layer = MapLayer.BATTLE_SITE
	travel_runtime.leave_site(session.party.party_id)
	var battle_site: BattleSiteMap = _replace_map(BATTLE_SITE_SCENE) as BattleSiteMap
	battle_site.debug_state_changed.connect(_on_map_debug_state_changed)
	battle_site.formation_move_requested.connect(_on_battle_formation_move_requested)
	battle_site.simple_order_requested.connect(_on_battle_simple_order_requested)
	battle_site.battle_speed_requested.connect(_on_battle_speed_requested)
	battle_site.setup(begin_result.snapshot)

func _process(delta: float) -> void:
	if current_layer != MapLayer.BATTLE_SITE or not session.has_active_battle():
		return
	var advance_result: BattleRuntimeResult = battle_preview_runtime.advance_battle(delta)
	if advance_result.success and advance_result.changed:
		_refresh_battle_site()

func _refresh_battle_site() -> void:
	if current_map is BattleSiteMap:
		var snapshot: BattleSiteSnapshot = battle_preview_runtime.active_snapshot()
		if snapshot != null:
			(current_map as BattleSiteMap).setup(snapshot)

func _on_battle_formation_move_requested(
		formation_id: String,
		target_position_m: Vector2
	) -> void:
	_sync_runtime()
	var result: BattleRuntimeResult = battle_preview_runtime.issue_move(
		formation_id,
		target_position_m
	)
	if current_map is BattleSiteMap:
		(current_map as BattleSiteMap).set_command_result(result)
	if result.success:
		_refresh_battle_site()

func _on_battle_simple_order_requested(formation_id: String, intent: int) -> void:
	_sync_runtime()
	var result: BattleRuntimeResult = battle_preview_runtime.issue_simple_order(
		session.party.party_id,
		formation_id,
		intent
	)
	if current_map is BattleSiteMap:
		(current_map as BattleSiteMap).set_command_result(result)
	if result.success:
		_refresh_battle_site()

func _on_battle_speed_requested(multiplier: float) -> void:
	_sync_runtime()
	var result: BattleRuntimeResult = battle_preview_runtime.set_battle_speed_multiplier(multiplier)
	if current_map is BattleSiteMap:
		(current_map as BattleSiteMap).set_battle_speed_result(result)
	if result.success:
		_refresh_battle_site()

func _replace_map(scene: PackedScene) -> Node2D:
	if is_instance_valid(current_map):
		current_map.queue_free()
	current_map = scene.instantiate(PackedScene.GEN_EDIT_STATE_DISABLED) as Node2D
	map_root.add_child(current_map)
	return current_map

func enter_region(world_cell: Vector2i) -> void:
	_sync_runtime()
	if not world_data.is_valid_world_cell(world_cell):
		return
	session.selected_world_cell = world_cell
	travel_runtime.ensure_party_spawn(world_cell, session.selected_region_cell)
	show_region()

func enter_site_at(region_cell: Vector2i) -> void:
	_sync_runtime()
	var entry: SiteEntryQueryResult = travel_runtime.query_site_entry_at(
			session.party.party_id,
			session.selected_world_cell,
			region_cell
		)
	if not entry.can_enter:
		return
	session.selected_region_cell = region_cell
	show_site_definition(entry.site_definition)

func can_enter_site_at(region_cell: Vector2i) -> bool:
	_sync_runtime()
	return travel_runtime.query_site_entry_at(
			session.party.party_id,
			session.selected_world_cell,
			region_cell
		).can_enter

func plan_travel_to_global_cell(destination_global_cell: Vector2i, destination_poi_id: String = "") -> bool:
	_sync_runtime()
	if session.is_traveling():
		return false
	travel_runtime.ensure_party_ready()
	var preview: TravelPreviewResult = travel_runtime.query_travel_preview(
			session.party.party_id,
			destination_global_cell,
			destination_poi_id
		)
	if not preview.has_path():
		pending_global_destination = Vector2i(-1, -1)
		pending_global_poi_id = ""
		session.travel_failure_reason = preview.failure_reason
		_emit_current_debug_state()
		return false
	pending_global_destination = destination_global_cell
	pending_global_poi_id = destination_poi_id
	_emit_current_debug_state()
	return true

func confirm_global_travel() -> bool:
	_sync_runtime()
	if pending_global_destination == Vector2i(-1, -1):
		return false
	var command: TravelCommandResult = travel_runtime.start_travel(
			session.party.party_id,
		pending_global_destination,
		pending_global_poi_id
		)
	pending_global_destination = Vector2i(-1, -1)
	pending_global_poi_id = ""
	return command.success

func cancel_travel() -> void:
	_sync_runtime()
	travel_runtime.cancel_travel(session.party.party_id)

func _start_travel_loop() -> void:
	if travel_loop_running:
		return
	_prewarm_active_travel_regions()
	travel_loop_running = true
	call_deferred("_run_travel_loop")

func _prewarm_active_travel_regions() -> void:
	var path: GlobalTravelPathType = session.active_global_travel_path
	if path == null:
		return
	var warmed_regions: Dictionary = {}
	for global_cell: Vector2i in path.cells:
		var converted: Dictionary = WorldCoordinates.global_region_cell_to_world_region(global_cell)
		var world_cell: Vector2i = converted["world_cell"] as Vector2i
		if warmed_regions.has(world_cell):
			continue
		warmed_regions[world_cell] = true
		world_data.get_or_generate_region_terrain(world_cell, session.world_seed)

func _run_travel_loop() -> void:
	var path: GlobalTravelPathType = session.active_global_travel_path
	while session.is_traveling() and path != null and session.global_travel_path_index < path.cells.size() - 1:
		if session.travel_cancel_requested:
			break
		var step: TravelStepResult = travel_runtime.get_next_travel_step()
		if not step.success:
			break
		if current_map != null and is_instance_valid(current_map) \
			and current_map.has_method("animate_party_step") \
			and step.previous_world_cell == step.next_world_cell:
			await current_map.call("animate_party_step", step.next_region_cell, session.travel_speed_multiplier)
		else:
			await get_tree().process_frame
		var committed: TravelStepResult = travel_runtime.commit_travel_step(step.path_index)
		if not committed.success:
			break
		if committed.previous_world_cell != committed.next_world_cell:
			print("Region Transition: %s -> %s | Global Cell: %s -> %s" % [
				_format_cell(committed.previous_world_cell),
				_format_cell(committed.next_world_cell),
				_format_cell(committed.from_global_cell),
				_format_cell(committed.next_global_cell),
			])
			show_region()
		else:
			if current_map != null and is_instance_valid(current_map) \
				and current_map.has_method("sync_party_position"):
				current_map.call("sync_party_position")
	if path != null and session.is_traveling():
		if not travel_runtime.finish_travel():
			travel_runtime.fail_travel(TravelFailureReasonType.Code.TRAVEL_STEP_FAILED)
		if current_map != null and is_instance_valid(current_map) \
			and current_map.has_method("sync_party_position"):
			current_map.call("sync_party_position")
	travel_loop_running = false

func _emit_current_debug_state() -> void:
	if current_map != null and is_instance_valid(current_map) and current_map.has_method("get_debug_state"):
		debug_state_changed.emit(current_map.get_debug_state())

func _on_travel_started(_result: TravelCommandResult) -> void:
	_sync_runtime()
	var party_world_cell: Vector2i = session.party.get_world_cell()
	var region_tracks_party: bool = current_layer == MapLayer.REGION \
		and session.selected_world_cell == party_world_cell
	if not region_tracks_party and map_root != null:
		session.selected_world_cell = party_world_cell
		session.selected_region_cell = session.party.get_region_cell()
		show_region()
	_start_travel_loop()

func _sync_runtime() -> void:
	if region_runtime == null:
		region_runtime = RegionRuntimeType.new(session, world_data)
	region_runtime.bind(session, world_data)
	if travel_runtime == null:
		travel_runtime = TravelRuntimeType.new(session, world_data)
		travel_runtime.travel_started.connect(_on_travel_started)
	travel_runtime.bind(session, world_data)
	if battle_preview_runtime == null:
		battle_preview_runtime = BattlePreviewRuntimeType.new(session, world_data, region_runtime)
	else:
		battle_preview_runtime.bind(session, world_data, region_runtime)

func _on_map_debug_state_changed(state: Dictionary) -> void:
	debug_state_changed.emit(state)

func _on_site_move_requested(direction: Vector2i) -> void:
	_sync_runtime()
	if current_layer != MapLayer.SITE or session.current_site_id.is_empty():
		return
	var command: SiteRuntimeCommandResult = travel_runtime.move_party_in_site(
		session.party.party_id,
		session.current_site_id,
		direction
	)
	if not command.success:
		return
	var query: SiteRuntimeQueryResult = travel_runtime.query_site_snapshot(session.current_site_id)
	if query.success and current_map is SiteMap:
		(current_map as SiteMap).setup(query.snapshot)

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	_sync_runtime()
	if session.is_traveling():
		match key_event.keycode:
			KEY_ESCAPE:
				travel_runtime.cancel_travel(session.party.party_id)
				get_viewport().set_input_as_handled()
			KEY_1:
				travel_runtime.set_travel_speed_multiplier(session.party.party_id, 1.0)
				_emit_current_debug_state()
				get_viewport().set_input_as_handled()
			KEY_2:
				travel_runtime.set_travel_speed_multiplier(session.party.party_id, 4.0)
				_emit_current_debug_state()
				get_viewport().set_input_as_handled()
			KEY_3:
				travel_runtime.set_travel_speed_multiplier(session.party.party_id, 16.0)
				_emit_current_debug_state()
				get_viewport().set_input_as_handled()
		return
	if pending_global_destination != Vector2i(-1, -1) and key_event.keycode == KEY_ENTER:
		confirm_global_travel()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode != KEY_T and key_event.keycode != KEY_ESCAPE:
		return
	match current_layer:
		MapLayer.SITE:
			show_region()
		MapLayer.BATTLE_SITE:
			battle_preview_runtime.leave_battle()
			show_region(true)
		MapLayer.REGION:
			show_world()
		MapLayer.WORLD:
			return
	get_viewport().set_input_as_handled()

func _format_cell(cell: Vector2i) -> String:
	return "(%d, %d)" % [cell.x, cell.y]
