class_name BattleSiteMap
extends Node2D

signal debug_state_changed(state: Dictionary)
signal formation_move_requested(formation_id: String, target_position_m: Vector2)
signal simple_order_requested(formation_id: String, intent: int)
signal battle_speed_requested(multiplier: float)

const MapArtCatalogType = preload("res://scripts/data/map_art_catalog.gd")
const SiteLayoutDataType = preload("res://scripts/data/site_layout_data.gd")
const BATTLE_PIXELS_PER_METER: float = 4.0
const CAMERA_MARGIN_METERS: float = 60.0
const CAMERA_DRAG_THRESHOLD_PIXELS: float = 3.0
const MIN_ZOOM: float = 0.50
const MAX_ZOOM: float = 16.00
const SOLDIER_CANVAS_SIZE_METERS: Vector2 = BattleFormationData.SOLDIER_CANVAS_SIZE_METERS
const NPC_REFERENCE_SHEET_PATH: String = "res://assets/paper_doll/reference_match/reference_match_body_on_foot_unisex.png"
const NPC_REFERENCE_FRAME: Rect2 = Rect2(0.0, 0.0, 64.0, 64.0)
const NPC_REFERENCE_VISIBLE_BOUNDS: Vector2 = Vector2(38.0, 56.0)
const NPC_SPRITE_SIZE_METERS: Vector2 = MapArtCatalogType.PERSON_REFERENCE_SIZE_METERS
const FORMATION_COLUMNS: int = BattleFormationData.FORMATION_COLUMNS
const FORMATION_ROWS: int = BattleFormationData.FORMATION_ROWS
const RESERVE_STAGING_BAND_METERS: float = 60.0

@onready var camera: Camera2D = $Camera2D
@onready var soldier_instances: MultiMeshInstance2D = $SoldierInstances
@onready var battle_debug_label: Label = $BattleDebugPanel/Panel/Margin/Content/BattleDebugLabel
@onready var command_grid: GridContainer = $BattleDebugPanel/Panel/Margin/Content/CommandGrid

var context: BattleSiteContext
var snapshot: BattleSiteSnapshot
var generated: Dictionary = {}
var active_formations: Array[BattleFormationData] = []
var active_orders: Array[BattleOrderData] = []
var active_dispatches: Array[BattleDispatchData] = []
var selected_formation_id: String = ""
var camera_initialized: bool = false
var soldier_multimesh: MultiMesh
var formation_instance_ranges: Dictionary = {}
var visual_formation_counts: Dictionary = {}
var visual_reserve_counts: Dictionary = {}
var visual_battle_id: String = ""
var visual_revision: int = -1
var visual_total_personnel: int = -1
var command_status: String = ""
var battle_speed_multiplier: float = 1.0
var camera_dragging: bool = false
var camera_drag_moved: bool = false

func _ready() -> void:
	# Match the authored Site scene paintings instead of filtering the 3x3
	# composition into a blurry macro terrain sheet.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var soldier_mesh: QuadMesh = QuadMesh.new()
	# Keep the unit quad; the per-instance transform below supplies the actual
	# 64x64 reference-frame size in canvas pixels.
	soldier_mesh.size = Vector2.ONE
	soldier_multimesh = MultiMesh.new()
	soldier_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	soldier_multimesh.use_colors = true
	soldier_multimesh.mesh = soldier_mesh
	soldier_instances.multimesh = soldier_multimesh
	var reference_sheet: Texture2D = _load_reference_sheet()
	if reference_sheet != null:
		var reference_frame := AtlasTexture.new()
		reference_frame.atlas = reference_sheet
		reference_frame.region = NPC_REFERENCE_FRAME
		soldier_instances.texture = reference_frame
	if soldier_instances.texture == null:
		soldier_instances.texture = load("res://assets/battle/soldier_dot.svg") as Texture2D
	$BattleDebugPanel/Panel/Margin/Content/CommandGrid/AdvanceButton.pressed.connect(
		_emit_simple_command.bind(BattleOrderData.SimpleIntent.ADVANCE)
	)
	$BattleDebugPanel/Panel/Margin/Content/CommandGrid/FallBackButton.pressed.connect(
		_emit_simple_command.bind(BattleOrderData.SimpleIntent.FALL_BACK)
	)
	$BattleDebugPanel/Panel/Margin/Content/CommandGrid/AttackButton.pressed.connect(
		_emit_simple_command.bind(BattleOrderData.SimpleIntent.ATTACK)
	)
	$BattleDebugPanel/Panel/Margin/Content/CommandGrid/WithdrawButton.pressed.connect(
		_emit_simple_command.bind(BattleOrderData.SimpleIntent.WITHDRAW)
	)
	$BattleDebugPanel/Panel/Margin/Content/CommandGrid/FlankRearButton.pressed.connect(
		_emit_simple_command.bind(BattleOrderData.SimpleIntent.FLANK_REAR)
	)
	$BattleDebugPanel/Panel/Margin/Content/SpeedGrid/SpeedHalfButton.pressed.connect(
		_emit_battle_speed.bind(0.5)
	)
	$BattleDebugPanel/Panel/Margin/Content/SpeedGrid/Speed1Button.pressed.connect(
		_emit_battle_speed.bind(1.0)
	)
	$BattleDebugPanel/Panel/Margin/Content/SpeedGrid/Speed2Button.pressed.connect(
		_emit_battle_speed.bind(2.0)
	)
	$BattleDebugPanel/Panel/Margin/Content/SpeedGrid/Speed4Button.pressed.connect(
		_emit_battle_speed.bind(4.0)
	)
	$BattleDebugPanel/Panel/Margin/Content/SpeedGrid/Speed8Button.pressed.connect(
		_emit_battle_speed.bind(8.0)
	)
	$BattleDebugPanel/Panel/Margin/Content/SpeedGrid/Speed16Button.pressed.connect(
		_emit_battle_speed.bind(16.0)
	)
	_update_command_controls()

func _load_reference_sheet() -> Texture2D:
	# Use the same bounded PNG fallback as PaperDollCatalog so a fresh Dropbox
	# checkout does not silently fall back to the old dot marker while imports
	# are still warming up.
	var file: FileAccess = FileAccess.open(NPC_REFERENCE_SHEET_PATH, FileAccess.READ)
	if file == null:
		return null
	var image: Image = Image.new()
	image.load_png_from_buffer(file.get_buffer(file.get_length()))
	if image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

func setup(p_snapshot: BattleSiteSnapshot) -> void:
	if p_snapshot == null or not p_snapshot.has_preview():
		return
	var reset_camera: bool = not camera_initialized or context == null \
		or context.battle_id != p_snapshot.context.battle_id
	snapshot = p_snapshot
	context = snapshot.context
	battle_speed_multiplier = snapshot.battle_speed_multiplier
	generated = {
		"site_layouts": snapshot.site_layouts,
		"footprint_cells": snapshot.footprint_cells,
		"size_meters": snapshot.size_meters,
		"bounds_meters": snapshot.bounds_meters,
		"center_cell": snapshot.center_cell,
		"center_terrain": snapshot.center_terrain,
		"attacker_deployment": snapshot.attacker_deployment,
		"defender_deployment": snapshot.defender_deployment,
		"terrain_debug_representation": snapshot.terrain_debug_representation,
		"terrain_hash": snapshot.terrain_hash,
		"preview_hash": snapshot.preview_hash,
	}
	active_formations = _presentation_formations(snapshot)
	active_orders.clear()
	for order: BattleOrderData in snapshot.orders:
		active_orders.append(order.copy())
	active_dispatches.clear()
	for dispatch: BattleDispatchData in snapshot.dispatches:
		active_dispatches.append(dispatch.copy())
	var rebuild_soldiers: bool = _visual_layout_changed()
	if rebuild_soldiers:
		_rebuild_soldier_instances()
	elif snapshot.revision != visual_revision:
		_sync_active_soldier_instances()
	visual_revision = snapshot.revision
	if reset_camera:
		command_status = ""
		var size_meters: Vector2 = generated["size_meters"] as Vector2
		camera.position = meters_to_pixels(size_meters * 0.5)
		camera.zoom = Vector2(0.85, 0.85)
		camera_initialized = true
	_update_debug_panel()
	_update_command_controls()
	queue_redraw()
	debug_state_changed.emit(get_debug_state())

static func meters_to_pixels(battle_local_meter_position: Vector2) -> Vector2:
	return battle_local_meter_position * BATTLE_PIXELS_PER_METER

static func pixels_to_meters(battle_local_pixel_position: Vector2) -> Vector2:
	return battle_local_pixel_position / BATTLE_PIXELS_PER_METER

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		var simple_intent: int = _simple_intent_for_key(key_event.keycode)
		if simple_intent >= 0:
			_emit_simple_command(simple_intent)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		if not camera_dragging:
			return
		var motion_event: InputEventMouseMotion = event as InputEventMouseMotion
		if motion_event.relative.length() >= CAMERA_DRAG_THRESHOLD_PIXELS:
			camera_drag_moved = true
			camera.position -= motion_event.relative / camera.zoom.x
			_clamp_camera()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton:
		return
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		if not mouse_event.pressed:
			return
		_set_zoom(1.1)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if not mouse_event.pressed:
			return
		_set_zoom(0.9)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
		if mouse_event.pressed:
			camera_dragging = true
			camera_drag_moved = false
		else:
			if camera_dragging and not camera_drag_moved:
				_select_formation(pixels_to_meters(get_local_mouse_position()))
			camera_dragging = false
			camera_drag_moved = false
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT \
			and mouse_event.pressed and not selected_formation_id.is_empty():
		formation_move_requested.emit(
			selected_formation_id,
			pixels_to_meters(get_local_mouse_position())
		)
		get_viewport().set_input_as_handled()

func get_debug_state() -> Dictionary:
	if generated.is_empty():
		return {"layer": "BATTLE SITE", "instruction": "ESC: Return to Region Map"}
	var center: Dictionary = generated["center_cell"] as Dictionary
	var global_cell: Vector2i = center["global_region_cell"] as Vector2i
	return {
		"layer": "BATTLE SITE",
		"debug_view": "TACTICAL PREVIEW",
		"current_region": "Battle at World %s" % _format_cell(context.center_world_cell),
		"world_seed": context.world_seed,
		"world_time": _format_world_time(context.world_time_seconds),
		"party_id": "%s vs %s" % [context.attacker.participant_id, context.defender.participant_id],
		"party_position": "%d active formations / %d personnel" % [
			active_formations.size(),
			context.attacker.total_personnel + context.defender.total_personnel
		],
		"party_state": "Click to select | Right-click to move" if snapshot.active_battle \
			else "Initial deployment / Off-map reserve",
		"person_visual": "reference NPC (64x64 / %.2fm x %.2fm)" % [
			NPC_SPRITE_SIZE_METERS.x,
			NPC_SPRITE_SIZE_METERS.y,
		],
		"battle_speed_multiplier": battle_speed_multiplier,
		"zoom": camera.zoom.x,
		"selected_formation": selected_formation_id,
		"command_status": command_status,
		"order_count": active_orders.size(),
		"dispatch_count": active_dispatches.size(),
		"world_cell": _format_cell(context.center_world_cell),
		"hovered_region_cell": "??",
		"selected_region_cell": _format_cell(context.center_region_cell),
		"global_region_cell": _format_cell(global_cell),
		"global_meter_position": _format_meters(
			WorldCoordinates.global_region_cell_to_global_meters(global_cell)
		),
		"terrain_type": TerrainType.to_display_name(int(center["terrain_type"])),
		"elevation": "%.2f" % float(center["elevation"]),
		"moisture": "%.2f" % float(center["moisture"]),
		"river_mask": "Yes" if bool(center["river"]) else "No",
		"river_strength": "%.2f" % float(center["river_strength"]),
		"road": "Yes" if bool(center["road"]) else "No",
		"river_crossing": "Yes" if bool(center["river_crossing"]) else "No",
		"site": context.battle_id,
		"instruction": "Left drag: Pan   Wheel: Zoom 0.5x-16x   Click: Select   Right-click: Move   1-5: Commands   Speed: 0.5-16x   ESC: Return",
	}

func set_command_result(result: BattleRuntimeResult) -> void:
	if result == null:
		return
	var code: String = BattleRuntimeResult.code_name(result.failure_code)
	if result.order_id.is_empty():
		command_status = code
	else:
		command_status = "%s %s (%s)" % [
			result.order_id,
			BattleOrderData.state_code(result.order_state),
			code,
		]
	_update_debug_panel()
	queue_redraw()
	debug_state_changed.emit(get_debug_state())

func set_battle_speed_result(result: BattleRuntimeResult) -> void:
	if result == null:
		return
	if result.success:
		battle_speed_multiplier = result.battle_speed_multiplier
		command_status = "BATTLE_SPEED %.1fx (%s)" % [
			battle_speed_multiplier,
			BattleRuntimeResult.code_name(result.failure_code),
		]
	else:
		command_status = BattleRuntimeResult.code_name(result.failure_code)
	_update_debug_panel()
	queue_redraw()
	debug_state_changed.emit(get_debug_state())

func _emit_simple_command(intent: int) -> void:
	if selected_formation_id.is_empty():
		command_status = "SELECT_FORMATION_FIRST"
		_update_debug_panel()
		debug_state_changed.emit(get_debug_state())
		return
	simple_order_requested.emit(selected_formation_id, intent)

func _emit_battle_speed(multiplier: float) -> void:
	battle_speed_requested.emit(multiplier)

func _simple_intent_for_key(keycode: Key) -> int:
	match keycode:
		KEY_1:
			return BattleOrderData.SimpleIntent.ADVANCE
		KEY_2:
			return BattleOrderData.SimpleIntent.FALL_BACK
		KEY_3:
			return BattleOrderData.SimpleIntent.ATTACK
		KEY_4:
			return BattleOrderData.SimpleIntent.WITHDRAW
		KEY_5:
			return BattleOrderData.SimpleIntent.FLANK_REAR
		_:
			return -1

func _update_command_controls() -> void:
	if command_grid == null:
		return
	for child: Node in command_grid.get_children():
		if child is BaseButton:
			(child as BaseButton).disabled = selected_formation_id.is_empty()

func preview_marker_count(side: String) -> int:
	var key: String = "attacker_deployment" if side == "attacker" else "defender_deployment"
	if generated.is_empty() or not generated.has(key):
		return 0
	return int((generated[key] as Dictionary).get("marker_count", 0))

func _draw() -> void:
	if generated.is_empty():
		return
	var size_pixels: Vector2 = meters_to_pixels(generated["size_meters"] as Vector2)
	var margin_pixels: Vector2 = meters_to_pixels(Vector2.ONE * CAMERA_MARGIN_METERS)
	draw_rect(
		Rect2(-margin_pixels, size_pixels + margin_pixels * 2.0),
		Color("111820")
	)
	_draw_reserve_staging(generated["size_meters"] as Vector2)
	for cell: Dictionary in generated["footprint_cells"] as Array[Dictionary]:
		_draw_ground_cell(cell)
	_draw_site_boundary_variants()
	for cell: Dictionary in generated["footprint_cells"] as Array[Dictionary]:
		_draw_cell_details(cell)
		_draw_cell_corridors(cell)
	_draw_grid(size_pixels)
	_draw_battle_legend()
	_draw_deployment_preview(generated["attacker_deployment"] as Dictionary, Color("3f8cff"))
	_draw_deployment_preview(generated["defender_deployment"] as Dictionary, Color("e85f62"))
	_draw_dispatches()
	_draw_formations()

func _draw_ground_cell(cell: Dictionary) -> void:
	var origin: Vector2 = meters_to_pixels(cell["local_origin_meters"] as Vector2)
	var cell_pixels: float = float(WorldCoordinates.REGION_CELL_SIZE_METERS) * BATTLE_PIXELS_PER_METER
	var elevation: float = float(cell["elevation"])
	var cell_rect: Rect2 = Rect2(origin, Vector2.ONE * cell_pixels)
	var layout: SiteLayoutDataType = cell.get("site_layout", null) as SiteLayoutDataType
	var scene_texture: Texture2D = MapArtCatalogType.site_scene_texture(layout)
	if scene_texture != null:
		draw_texture_rect(scene_texture, cell_rect, false)
	else:
		var terrain_texture: Texture2D = MapArtCatalogType.terrain_texture(int(cell["terrain_type"]))
		if terrain_texture != null:
			draw_texture_rect(terrain_texture, cell_rect, false)
		else:
			draw_rect(cell_rect, TerrainType.to_color(int(cell["terrain_type"])))
	var elevation_delta: float = (elevation - 0.5) * 0.22
	if scene_texture == null and absf(elevation_delta) > 0.01:
		var elevation_tint: Color = Color(1.0, 1.0, 1.0, elevation_delta) \
			if elevation_delta > 0.0 else Color(0.0, 0.0, 0.0, -elevation_delta)
		draw_rect(cell_rect, elevation_tint)
	if scene_texture == null and int(cell["terrain_type"]) == TerrainType.MOUNTAIN:
		draw_circle(origin + Vector2.ONE * cell_pixels * 0.5, cell_pixels * 0.33, Color(0.25, 0.27, 0.30, 0.22))

func _draw_cell_details(cell: Dictionary) -> void:
	if _cell_has_scene_art(cell):
		return
	var details: Dictionary = cell["details"] as Dictionary
	if details.has("clearing_center_meters"):
		draw_circle(
			meters_to_pixels(details["clearing_center_meters"] as Vector2),
			15.0 * BATTLE_PIXELS_PER_METER,
			Color("6f935d")
		)
	for value: Variant in details.get("grass", []):
		var point: Vector2 = meters_to_pixels(value as Vector2)
		draw_line(point + Vector2(-5.0, 5.0), point + Vector2(0.0, -7.0), Color("b5c96f"), 2.0)
		draw_line(point + Vector2(5.0, 5.0), point + Vector2(0.0, -7.0), Color("91aa55"), 2.0)
	for value: Variant in details.get("rocks", []):
		var point: Vector2 = meters_to_pixels(value as Vector2)
		_draw_battle_detail_texture(
			MapArtCatalogType.site_texture("rock_cluster"),
			point,
			Vector2(26.0, 26.0)
		)
		draw_colored_polygon(PackedVector2Array([
			point + Vector2(-13.0, 8.0),
			point + Vector2(-7.0, -10.0),
			point + Vector2(9.0, -13.0),
			point + Vector2(14.0, 8.0),
		]), Color("4e535b"))
		draw_polyline(PackedVector2Array([
			point + Vector2(-13.0, 8.0),
			point + Vector2(-7.0, -10.0),
			point + Vector2(9.0, -13.0),
			point + Vector2(14.0, 8.0),
			point + Vector2(-13.0, 8.0),
		]), Color("9298a0"), 2.0)
	for value: Variant in details.get("bushes", []):
		var point: Vector2 = meters_to_pixels(value as Vector2)
		_draw_battle_detail_texture(
			MapArtCatalogType.site_texture("dry_bush"),
			point,
			Vector2(22.0, 22.0)
		)
		draw_circle(point, 10.0, Color("25553c"))
		draw_circle(point + Vector2(5.0, -3.0), 7.0, Color("35704e"))
	for value: Variant in details.get("trees", []):
		var point: Vector2 = meters_to_pixels(value as Vector2)
		draw_circle(point, 17.0, Color("173d2e"))
		draw_circle(point + Vector2(-5.0, -5.0), 13.0, Color("245e3f"))
		draw_circle(point + Vector2(6.0, -7.0), 11.0, Color("32734c"))
		draw_circle(point, 4.0, Color("5b4030"))
	# Final texture pass keeps the generated hand-painted objects visible above
	# the compatibility fallback shapes used for debug readability.
	for value: Variant in details.get("rocks", []):
		_draw_battle_detail_texture(
			MapArtCatalogType.site_texture("rock_cluster"),
			meters_to_pixels(value as Vector2),
			Vector2(32.0, 32.0)
		)
	for value: Variant in details.get("bushes", []):
		_draw_battle_detail_texture(
			MapArtCatalogType.site_texture("dry_bush"),
			meters_to_pixels(value as Vector2),
			Vector2(28.0, 28.0)
		)
	for value: Variant in details.get("trees", []):
		_draw_battle_detail_texture(
			MapArtCatalogType.site_texture("tree_cluster"),
			meters_to_pixels(value as Vector2),
			Vector2(40.0, 40.0)
		)

func _draw_battle_detail_texture(texture: Texture2D, center_pixels: Vector2, size_pixels: Vector2) -> void:
	if texture == null:
		return
	draw_texture_rect(texture, Rect2(center_pixels - size_pixels * 0.5, size_pixels), false)

func _draw_cell_corridors(cell: Dictionary) -> void:
	if _cell_has_scene_art(cell):
		_draw_scene_connections(cell)
		return
	var origin_meters: Vector2 = cell["local_origin_meters"] as Vector2
	var center_meters: Vector2 = origin_meters + Vector2.ONE * 50.0
	if bool(cell["river"]):
		_draw_corridor(
			center_meters,
			cell["river_connection_offsets"] as Array,
			Color("2d718e"),
			13.0 * BATTLE_PIXELS_PER_METER
		)
		_draw_corridor(
			center_meters,
			cell["river_connection_offsets"] as Array,
			Color("56a8c5"),
			8.0 * BATTLE_PIXELS_PER_METER
		)
		_draw_corridor_art(
			center_meters,
			cell["river_connection_offsets"] as Array,
			MapArtCatalogType.site_texture("river_straight"),
			10.0
		)
		_draw_corridor_junction_art(
			center_meters,
			cell["river_connection_offsets"] as Array,
			true
		)
	if bool(cell["road"]):
		_draw_corridor(
			center_meters,
			cell["road_connection_offsets"] as Array,
			Color("715238"),
			9.0 * BATTLE_PIXELS_PER_METER
		)
		_draw_corridor(
			center_meters,
			cell["road_connection_offsets"] as Array,
			Color("c49a5c"),
			6.0 * BATTLE_PIXELS_PER_METER
		)
	if bool(cell["river_crossing"]):
		var bridge_texture: Texture2D = MapArtCatalogType.site_texture("bridge")
		var river_axis: int = _river_axis(cell["river_connection_offsets"] as Array)
		draw_set_transform(
			meters_to_pixels(center_meters),
			PI * 0.5 if river_axis == 1 else 0.0,
			Vector2.ONE
		)
		_draw_battle_detail_texture(bridge_texture, Vector2.ZERO, Vector2(88.0, 36.0))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_site_boundary_variants() -> void:
	if generated.is_empty():
		return
	var cells_by_global: Dictionary = {}
	for cell: Dictionary in generated["footprint_cells"] as Array[Dictionary]:
		var global_cell: Vector2i = cell.get("global_region_cell", Vector2i.ZERO) as Vector2i
		cells_by_global[global_cell] = cell
	for cell: Dictionary in generated["footprint_cells"] as Array[Dictionary]:
		var global_cell: Vector2i = cell.get("global_region_cell", Vector2i.ZERO) as Vector2i
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var neighbor_value: Variant = cells_by_global.get(global_cell + direction, null)
			if not neighbor_value is Dictionary:
				continue
			var neighbor: Dictionary = neighbor_value as Dictionary
			if not _cell_has_scene_art(cell) and not _cell_has_scene_art(neighbor):
				continue
			_draw_site_boundary_pair(cell, neighbor, direction)

func _draw_site_boundary_pair(
		cell: Dictionary,
		neighbor: Dictionary,
		direction: Vector2i
	) -> void:
	var origin_meters: Vector2 = cell["local_origin_meters"] as Vector2
	var boundary_center_meters: Vector2 = origin_meters + Vector2.ONE * 50.0
	if direction == Vector2i.RIGHT:
		boundary_center_meters = origin_meters + Vector2(100.0, 50.0)
	elif direction == Vector2i.DOWN:
		boundary_center_meters = origin_meters + Vector2(50.0, 100.0)
	var has_road: bool = _has_connection_pair(
		cell,
		neighbor,
		"road_connection_offsets",
		direction
	)
	var has_river: bool = _has_connection_pair(
		cell,
		neighbor,
		"river_connection_offsets",
		direction
	)
	var elevation_delta: float = absf(
		float(cell.get("elevation", 0.0)) - float(neighbor.get("elevation", 0.0))
	)
	_draw_natural_site_seam(
		cell,
		neighbor,
		boundary_center_meters,
		direction,
		not has_road and not has_river
	)
	if has_road and _should_draw_height_boundary(cell, neighbor, elevation_delta):
		_draw_boundary_overlay(
			boundary_center_meters,
			"site_cliff_horizontal" if direction == Vector2i.DOWN else "site_cliff_vertical"
		)
	# A short seam cap hides a one-pixel alpha gap when two independently
	# generated half-segments meet exactly at the shared Site edge.
	if has_road:
		_draw_boundary_join(boundary_center_meters, direction, false)
	if has_river:
		_draw_river_boundary_transition(cell, neighbor, boundary_center_meters, direction)

func _draw_natural_site_seam(
		cell: Dictionary,
		neighbor: Dictionary,
		center_meters: Vector2,
		direction: Vector2i,
		add_details: bool
	) -> void:
	if not _cell_has_scene_art(cell) and not _cell_has_scene_art(neighbor):
		return
	# Scene paintings are complete 100m compositions, so their raw rectangular
	# edges can read like a 3x3 collage when terrain changes at a shared edge.
	# A low-alpha, deterministic irregular band breaks that artificial straight
	# line; roads, rivers and cliffs are drawn later as stronger joins. Details
	# are omitted from connected edges so they never obstruct a corridor.
	var along_x: bool = direction.y != 0
	var offsets: Array[float] = [0.0, -2.2, 1.6, -1.3, 2.0, -1.1, 0.0]
	var points: PackedVector2Array = PackedVector2Array()
	for index: int in range(offsets.size()):
		var progress: float = float(index) / float(offsets.size() - 1)
		if along_x:
			points.append(Vector2(
				center_meters.x - 50.0 + progress * 100.0,
				center_meters.y + offsets[index]
			))
		else:
			points.append(Vector2(
				center_meters.x + offsets[index],
				center_meters.y - 50.0 + progress * 100.0
			))
	var half_width: float = 5.5
	var seam_polygon: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		seam_polygon.append(meters_to_pixels(point - (Vector2.DOWN if along_x else Vector2.RIGHT) * half_width))
	for index: int in range(points.size() - 1, -1, -1):
		var point: Vector2 = points[index]
		seam_polygon.append(meters_to_pixels(point + (Vector2.DOWN if along_x else Vector2.RIGHT) * half_width))
	draw_colored_polygon(seam_polygon, Color(0.20, 0.18, 0.14, 0.12))
	var seam_pixels: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		seam_pixels.append(meters_to_pixels(point))
	draw_polyline(seam_pixels, Color(0.10, 0.12, 0.10, 0.10), 1.4 * BATTLE_PIXELS_PER_METER, true)
	if not add_details:
		return
	var detail_kind: String = _boundary_detail_kind(cell, neighbor)
	var detail_texture: Texture2D = MapArtCatalogType.site_texture(detail_kind)
	if detail_texture == null:
		return
	for index: int in [1, 4]:
		var point: Vector2 = points[index]
		_draw_battle_detail_texture(
			detail_texture,
			meters_to_pixels(point),
			Vector2.ONE * 5.5 * BATTLE_PIXELS_PER_METER
		)

func _boundary_detail_kind(cell: Dictionary, neighbor: Dictionary) -> String:
	var terrain_types: Array[int] = [
		int(cell.get("terrain_type", TerrainType.PLAINS)),
		int(neighbor.get("terrain_type", TerrainType.PLAINS)),
	]
	if terrain_types.has(TerrainType.MOUNTAIN):
		return "rock_cluster"
	if terrain_types.has(TerrainType.SNOW):
		return "snowdrift"
	if terrain_types.has(TerrainType.SAND):
		return "dry_bush"
	if terrain_types.has(TerrainType.SWAMP):
		return "swamp_reeds"
	if terrain_types.has(TerrainType.FOREST):
		return "tree_cluster"
	if terrain_types.has(TerrainType.WATER) or terrain_types.has(TerrainType.OCEAN):
		return "rock_cluster"
	return "dry_bush"

func _draw_river_boundary_transition(
		cell: Dictionary,
		neighbor: Dictionary,
		center_meters: Vector2,
		direction: Vector2i
	) -> void:
	var horizontal: bool = direction.x != 0
	var width_meters: float = maxf(
		_river_scene_width_meters(cell),
		_river_scene_width_meters(neighbor)
	)
	var length_meters: float = 18.0
	var texture_kind: String = "site_river_horizontal" if horizontal else "site_river_vertical"
	var texture: Texture2D = MapArtCatalogType.site_texture(texture_kind)
	if texture == null:
		return
	var size_meters: Vector2 = Vector2(length_meters, width_meters) \
		if horizontal else Vector2(width_meters, length_meters)
	draw_texture_rect(
		texture,
		Rect2(
			meters_to_pixels(center_meters - size_meters * 0.5),
			meters_to_pixels(size_meters)
		),
		false
	)

func _river_scene_width_meters(cell: Dictionary) -> float:
	var layout: SiteLayoutDataType = cell.get("site_layout", null) as SiteLayoutDataType
	var kind: String = MapArtCatalogType.site_scene_kind(layout)
	if kind.begins_with("river_bridge") or kind.begins_with("strategic_river"):
		return 30.0
	return 10.0

func _draw_scene_connections(cell: Dictionary) -> void:
	var origin_meters: Vector2 = cell["local_origin_meters"] as Vector2
	var center_meters: Vector2 = origin_meters + Vector2.ONE * 50.0
	var road_offsets: Array = cell.get("road_connection_offsets", []) as Array
	_draw_scene_connection_segments(
		center_meters,
		road_offsets,
		false
	)
	_draw_corridor_junction_art(center_meters, road_offsets, false)
	# Authored river scenes already carry their bank, water and bridge through
	# the full 100m tile.  Do not paint a narrow debug-like strip over that
	# water; only non-river scene tiles need a generated river connector.
	if not _cell_has_river_scene(cell):
		var river_offsets: Array = cell.get("river_connection_offsets", []) as Array
		_draw_scene_connection_segments(
			center_meters,
			river_offsets,
			true
		)
		_draw_corridor_junction_art(center_meters, river_offsets, true)

func _draw_scene_connection_segments(
	center_meters: Vector2,
	connection_offsets: Array,
	is_river: bool
) -> void:
	var width_meters: float = 10.0 if is_river else 9.0
	for value: Variant in connection_offsets:
		if not value is Vector2i:
			continue
		var offset: Vector2i = value as Vector2i
		if offset == Vector2i.ZERO:
			continue
		var edge_meters: Vector2 = center_meters + Vector2(offset) * 50.0
		var horizontal: bool = offset.x != 0
		var texture_kind: String
		if is_river:
			texture_kind = "site_river_horizontal" if horizontal else "site_river_vertical"
		else:
			texture_kind = "site_path_horizontal" if horizontal else "site_path_vertical"
		var texture: Texture2D = MapArtCatalogType.site_texture(texture_kind)
		if texture == null:
			continue
		var center_pixels: Vector2 = meters_to_pixels(center_meters)
		var edge_pixels: Vector2 = meters_to_pixels(edge_meters)
		var length_pixels: float = center_pixels.distance_to(edge_pixels)
		var width_pixels: float = width_meters * BATTLE_PIXELS_PER_METER
		var segment_size: Vector2 = Vector2(length_pixels, width_pixels) \
			if horizontal else Vector2(width_pixels, length_pixels)
		draw_texture_rect(
			texture,
			Rect2((center_pixels + edge_pixels) * 0.5 - segment_size * 0.5, segment_size),
			false
		)

func _draw_boundary_overlay(center_meters: Vector2, texture_kind: String) -> void:
	var texture: Texture2D = MapArtCatalogType.site_texture(texture_kind)
	if texture == null:
		return
	var cell_pixels: float = float(WorldCoordinates.REGION_CELL_SIZE_METERS) * BATTLE_PIXELS_PER_METER
	var center_pixels: Vector2 = meters_to_pixels(center_meters)
	draw_texture_rect(
		texture,
		Rect2(center_pixels - Vector2.ONE * cell_pixels * 0.5, Vector2.ONE * cell_pixels),
		false
	)

func _draw_boundary_join(
	center_meters: Vector2,
	direction: Vector2i,
	is_river: bool
) -> void:
	var horizontal: bool = direction.x != 0
	var texture_kind: String
	if is_river:
		texture_kind = "site_river_horizontal" if horizontal else "site_river_vertical"
	else:
		texture_kind = "site_path_horizontal" if horizontal else "site_path_vertical"
	var texture: Texture2D = MapArtCatalogType.site_texture(texture_kind)
	if texture == null:
		return
	var join_length_meters: float = 5.0
	var width_meters: float = 10.0 if is_river else 9.0
	var center_pixels: Vector2 = meters_to_pixels(center_meters)
	var join_size: Vector2 = Vector2(
		join_length_meters * BATTLE_PIXELS_PER_METER,
		width_meters * BATTLE_PIXELS_PER_METER
	) if horizontal else Vector2(
		width_meters * BATTLE_PIXELS_PER_METER,
		join_length_meters * BATTLE_PIXELS_PER_METER
	)
	draw_texture_rect(texture, Rect2(center_pixels - join_size * 0.5, join_size), false)

func _has_connection_pair(
	cell: Dictionary,
	neighbor: Dictionary,
	key: String,
	direction: Vector2i
) -> bool:
	return _has_connection(cell, key, direction) \
		and _has_connection(neighbor, key, -direction)

func _has_connection(cell: Dictionary, key: String, direction: Vector2i) -> bool:
	var values: Array = cell.get(key, []) as Array
	for value: Variant in values:
		if value is Vector2i and (value as Vector2i) == direction:
			return true
	return false

func _should_draw_height_boundary(
	cell: Dictionary,
	neighbor: Dictionary,
	elevation_delta: float
) -> bool:
	if elevation_delta < 0.08:
		return false
	var water_types: Array[int] = [TerrainType.WATER, TerrainType.OCEAN]
	return not water_types.has(int(cell.get("terrain_type", TerrainType.PLAINS))) \
		and not water_types.has(int(neighbor.get("terrain_type", TerrainType.PLAINS)))

func _draw_corridor(
		center_meters: Vector2,
		connection_offsets: Array,
		color: Color,
		width_pixels: float
	) -> void:
	var center_pixels: Vector2 = meters_to_pixels(center_meters)
	for value: Variant in connection_offsets:
		if not value is Vector2i:
			continue
		var offset: Vector2i = value as Vector2i
		var edge_meters: Vector2 = center_meters + Vector2(offset) * 50.0
		draw_line(center_pixels, meters_to_pixels(edge_meters), color, width_pixels, true)

func _draw_corridor_art(
	center_meters: Vector2,
	connection_offsets: Array,
	texture: Texture2D,
	width_meters: float
) -> void:
	if texture == null:
		return
	var center_pixels: Vector2 = meters_to_pixels(center_meters)
	for value: Variant in connection_offsets:
		if not value is Vector2i:
			continue
		var offset: Vector2i = value as Vector2i
		var edge_meters: Vector2 = center_meters + Vector2(offset) * 50.0
		var delta_pixels: Vector2 = meters_to_pixels(edge_meters) - center_pixels
		var length_pixels: float = delta_pixels.length()
		if length_pixels <= 0.1:
			continue
		draw_set_transform(center_pixels + delta_pixels * 0.5, delta_pixels.angle(), Vector2.ONE)
		draw_texture_rect(
			texture,
			Rect2(
				Vector2(-length_pixels * 0.5, -width_meters * BATTLE_PIXELS_PER_METER * 0.5),
				Vector2(length_pixels, width_meters * BATTLE_PIXELS_PER_METER)
			),
			false
		)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_corridor_junction_art(
	center_meters: Vector2,
	connection_offsets: Array,
	is_river: bool
) -> void:
	var count: int = 0
	for value: Variant in connection_offsets:
		if value is Vector2i:
			count += 1
	if count < 2:
		return
	if count == 2 and _connection_offsets_are_straight(connection_offsets):
		return
	var kind: String = "river_bend" if is_river else "road_bend"
	if count == 3:
		kind = "road_t_junction"
	elif count >= 4:
		kind = "road_crossing"
	_draw_battle_detail_texture(
		MapArtCatalogType.site_texture(kind),
		meters_to_pixels(center_meters),
		Vector2(34.0, 34.0)
	)

func _connection_offsets_are_straight(connection_offsets: Array) -> bool:
	var has_up: bool = false
	var has_right: bool = false
	var has_down: bool = false
	var has_left: bool = false
	for value: Variant in connection_offsets:
		if not value is Vector2i:
			continue
		var offset: Vector2i = value as Vector2i
		if offset == Vector2i.UP:
			has_up = true
		elif offset == Vector2i.RIGHT:
			has_right = true
		elif offset == Vector2i.DOWN:
			has_down = true
		elif offset == Vector2i.LEFT:
			has_left = true
	return (has_up and has_down) or (has_left and has_right)

func _river_axis(connection_offsets: Array) -> int:
	for value: Variant in connection_offsets:
		if not value is Vector2i:
			continue
		var offset: Vector2i = value as Vector2i
		if offset.x != 0:
			return 1
		if offset.y != 0:
			return 0
	return 0

func _draw_grid(size_pixels: Vector2) -> void:
	var cell_pixels: float = float(WorldCoordinates.REGION_CELL_SIZE_METERS) * BATTLE_PIXELS_PER_METER
	for index: int in range(1, 3):
		var offset: float = float(index) * cell_pixels
		draw_line(Vector2(offset, 0.0), Vector2(offset, size_pixels.y), Color(0.05, 0.08, 0.10, 0.16), 1.0)
		draw_line(Vector2(0.0, offset), Vector2(size_pixels.x, offset), Color(0.05, 0.08, 0.10, 0.16), 1.0)
	draw_rect(Rect2(Vector2.ZERO, size_pixels), Color(0.90, 0.86, 0.74, 0.35), false, 2.0)

func _cell_has_scene_art(cell: Dictionary) -> bool:
	var layout: SiteLayoutDataType = cell.get("site_layout", null) as SiteLayoutDataType
	return MapArtCatalogType.site_scene_texture(layout) != null

func _cell_has_river_scene(cell: Dictionary) -> bool:
	var layout: SiteLayoutDataType = cell.get("site_layout", null) as SiteLayoutDataType
	var scene_kind: String = MapArtCatalogType.site_scene_kind(layout)
	return scene_kind.begins_with("river_bridge") \
		or scene_kind.begins_with("strategic_river")

func _draw_deployment_preview(deployment: Dictionary, color: Color) -> void:
	var zone_meters: Rect2 = deployment["zone_meters"] as Rect2
	var zone_pixels: Rect2 = Rect2(
		meters_to_pixels(zone_meters.position),
		meters_to_pixels(zone_meters.size)
	)
	var zone_fill: Color = color
	zone_fill.a = 0.17
	draw_rect(zone_pixels, zone_fill)
	draw_rect(zone_pixels, color.lightened(0.25), false, 4.0)
	if snapshot != null and snapshot.active_battle:
		return

func _draw_formations() -> void:
	for formation: BattleFormationData in active_formations:
		if formation.formation_id == selected_formation_id:
			var center: Vector2 = meters_to_pixels(formation.battle_position_m)
			draw_set_transform(center, _formation_rotation(formation), Vector2.ONE)
			var size_pixels: Vector2 = Vector2(formation.width_m, formation.depth_m) * BATTLE_PIXELS_PER_METER
			draw_rect(Rect2(-size_pixels * 0.5, size_pixels), Color.WHITE, false, 2.0)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if formation.formation_id == selected_formation_id and formation.path.size() > 1:
			var path_points: PackedVector2Array = PackedVector2Array()
			for cell: Vector2i in formation.path:
				path_points.append(meters_to_pixels(
					Vector2(cell) * float(SiteLayoutData.CELL_SIZE_METERS) \
					+ Vector2.ONE * float(SiteLayoutData.CELL_SIZE_METERS) * 0.5
				))
			if path_points.size() < 2:
				continue
			draw_polyline(path_points, Color(1.0, 1.0, 1.0, 0.65), 3.0, true)

func _draw_battle_legend() -> void:
	# Minimal canvas legend for the reference NPC sprites.  Side tint is
	# presentation-only; formation/deployment data remains unchanged.
	var origin: Vector2 = meters_to_pixels(Vector2(6.0, 6.0))
	var row_height: float = 22.0
	var entries: Array[Dictionary] = [
		{"label": "ATTACKER", "color": Color("4d98ff")},
		{"label": "DEFENDER", "color": Color("e8646a")},
		{"label": "COMMANDER", "color": Color("ffd166")},
	]
	var panel_size: Vector2 = Vector2(132.0, row_height * entries.size() + 12.0)
	draw_rect(Rect2(origin - Vector2(6.0, 6.0), panel_size), Color(0.03, 0.05, 0.07, 0.78))
	for index: int in range(entries.size()):
		var entry: Dictionary = entries[index]
		var point: Vector2 = origin + Vector2(0.0, float(index) * row_height)
		draw_rect(Rect2(point, Vector2(12.0, 12.0)), entry["color"] as Color)
		draw_string(
			ThemeDB.fallback_font,
			point + Vector2(18.0, 11.0),
			str(entry["label"]),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			12,
			Color("f4ead2")
		)

func _draw_dispatches() -> void:
	for dispatch: BattleDispatchData in active_dispatches:
		var point: Vector2 = meters_to_pixels(dispatch.position_m)
		if dispatch.state == BattleOrderData.State.EN_ROUTE:
			draw_circle(point, 6.0, Color("f8d477"))
			draw_line(point + Vector2(-10.0, 0.0), point + Vector2(10.0, 0.0), Color("fff2b2"), 2.0)
			draw_line(point + Vector2(0.0, -10.0), point + Vector2(0.0, 10.0), Color("fff2b2"), 2.0)
		elif dispatch.state == BattleOrderData.State.INTERCEPTED:
			point = meters_to_pixels(dispatch.intercepted_at_m)
			draw_line(point + Vector2(-12.0, -12.0), point + Vector2(12.0, 12.0), Color("ff5d6c"), 4.0)
			draw_line(point + Vector2(12.0, -12.0), point + Vector2(-12.0, 12.0), Color("ff5d6c"), 4.0)

func _select_formation(position_m: Vector2) -> void:
	selected_formation_id = ""
	for formation: BattleFormationData in active_formations:
		var local: Vector2 = (position_m - formation.battle_position_m).rotated(
			-_formation_rotation(formation)
		)
		if absf(local.x) <= formation.width_m * 0.5 and absf(local.y) <= formation.depth_m * 0.5:
			selected_formation_id = formation.formation_id
			break
	_update_command_controls()
	queue_redraw()

func _presentation_formations(source: BattleSiteSnapshot) -> Array[BattleFormationData]:
	var result: Array[BattleFormationData] = []
	if source.active_battle:
		for formation: BattleFormationData in source.formations:
			result.append(formation.copy())
		return result
	_append_preview_formations(
		result,
		source.attacker_deployment,
		BattleFormationData.Side.ATTACKER
	)
	_append_preview_formations(
		result,
		source.defender_deployment,
		BattleFormationData.Side.DEFENDER
	)
	return result

func _append_preview_formations(
	result: Array[BattleFormationData],
	deployment: Dictionary,
	side: int
) -> void:
	var deployed: int = int(deployment.get("initial_deployed_personnel", 0))
	var positions: Array = deployment.get("marker_positions_meters", []) as Array
	var facing: Vector2 = deployment.get("facing", Vector2.DOWN) as Vector2
	for index: int in range(positions.size()):
		var personnel: int = mini(
			BattleFormationData.DEFAULT_PERSONNEL,
			maxi(deployed - index * BattleFormationData.DEFAULT_PERSONNEL, 0)
		)
		if personnel <= 0:
			continue
		var formation: BattleFormationData = BattleFormationData.new(
			"preview_%s_%03d" % [BattleFormationData.side_code(side), index],
			side,
			personnel,
			positions[index] as Vector2
		)
		formation.facing_direction = facing
		result.append(formation)

func _visual_layout_changed() -> bool:
	if soldier_multimesh == null or context == null:
		return true
	var total: int = context.attacker.total_personnel + context.defender.total_personnel
	if visual_battle_id != context.battle_id or visual_total_personnel != total:
		return true
	if visual_formation_counts.size() != active_formations.size():
		return true
	for formation: BattleFormationData in active_formations:
		if int(visual_formation_counts.get(formation.formation_id, -1)) != formation.personnel_count:
			return true
	var attacker_deployment: Dictionary = generated["attacker_deployment"] as Dictionary
	var defender_deployment: Dictionary = generated["defender_deployment"] as Dictionary
	var attacker_reserve: int = int(attacker_deployment.get("reserve_personnel", 0))
	var defender_reserve: int = int(defender_deployment.get("reserve_personnel", 0))
	return int(visual_reserve_counts.get("attacker", -1)) != attacker_reserve \
		or int(visual_reserve_counts.get("defender", -1)) != defender_reserve

func _rebuild_soldier_instances() -> void:
	if soldier_multimesh == null or context == null:
		return
	var total: int = context.attacker.total_personnel + context.defender.total_personnel
	soldier_multimesh.instance_count = total
	formation_instance_ranges.clear()
	visual_formation_counts.clear()
	var attacker_deployment: Dictionary = generated["attacker_deployment"] as Dictionary
	var defender_deployment: Dictionary = generated["defender_deployment"] as Dictionary
	visual_reserve_counts = {
		"attacker": int(attacker_deployment.get("reserve_personnel", 0)),
		"defender": int(defender_deployment.get("reserve_personnel", 0)),
	}
	var instance_index: int = 0
	for formation: BattleFormationData in active_formations:
		var count: int = maxi(formation.personnel_count, 0)
		formation_instance_ranges[formation.formation_id] = {
			"start": instance_index,
			"count": count,
		}
		visual_formation_counts[formation.formation_id] = count
		_write_formation_instances(formation, instance_index)
		instance_index += count
	instance_index = _write_reserve_instances(
		instance_index,
		attacker_deployment,
		context.attacker_entry_direction,
		Color("4d98ff"),
		generated["size_meters"] as Vector2
	)
	instance_index = _write_reserve_instances(
		instance_index,
		defender_deployment,
		context.defender_entry_direction,
		Color("e8646a"),
		generated["size_meters"] as Vector2
	)
	soldier_multimesh.visible_instance_count = instance_index
	visual_battle_id = context.battle_id
	visual_total_personnel = total

func _sync_active_soldier_instances() -> void:
	for formation: BattleFormationData in active_formations:
		var range_value: Variant = formation_instance_ranges.get(formation.formation_id, null)
		if not range_value is Dictionary:
			continue
		_write_formation_instances(
			formation,
			int((range_value as Dictionary).get("start", 0))
		)

func _write_formation_instances(formation: BattleFormationData, start_index: int) -> void:
	var color: Color = Color("4d98ff") if formation.side == BattleFormationData.Side.ATTACKER \
		else Color("e8646a")
	for index: int in range(maxi(formation.personnel_count, 0)):
		var local_slot: Vector2 = _formation_slot_local(
			index,
			formation.personnel_count,
			formation.width_m,
			formation.depth_m
		)
		var soldier_color: Color = Color("ffd166") if index == 0 else color
		_set_soldier_instance(
			start_index + index,
			_formation_world_position(formation, local_slot),
			soldier_color
		)

func _write_reserve_instances(
	start_index: int,
	deployment: Dictionary,
	entry_direction: int,
	color: Color,
	size_meters: Vector2
) -> int:
	var reserve: int = int(deployment.get("reserve_personnel", 0))
	var reserve_color: Color = color.darkened(0.35)
	reserve_color.a = 0.72
	for index: int in range(reserve):
		_set_soldier_instance(
			start_index + index,
			_reserve_person_position(index, entry_direction, size_meters),
			reserve_color
		)
	return start_index + reserve

func _set_soldier_instance(index: int, position_m: Vector2, color: Color) -> void:
	var instance_transform: Transform2D = Transform2D()
	instance_transform.origin = meters_to_pixels(position_m)
	# The reference sheet includes transparent padding.  Scale the full 64x64
	# frame from its measured 38x56 visible silhouette so the visible NPC, not
	# the transparent canvas, matches the shared 0.60m x 1.80m Site contract.
	var visible_pixels: Vector2 = NPC_SPRITE_SIZE_METERS * BATTLE_PIXELS_PER_METER
	var marker_pixels: Vector2 = Vector2(
		visible_pixels.x * NPC_REFERENCE_FRAME.size.x / NPC_REFERENCE_VISIBLE_BOUNDS.x,
		visible_pixels.y * NPC_REFERENCE_FRAME.size.y / NPC_REFERENCE_VISIBLE_BOUNDS.y
	)
	instance_transform.x = Vector2(marker_pixels.x, 0.0)
	instance_transform.y = Vector2(0.0, marker_pixels.y)
	soldier_multimesh.set_instance_transform_2d(index, instance_transform)
	# Keep the reference palette inspectable while retaining only a light side
	# cue; the sprite must not turn into a red/blue replacement character.
	var sprite_color: Color = Color.WHITE.lerp(color, 0.18)
	sprite_color.a = color.a
	soldier_multimesh.set_instance_color(index, sprite_color)

static func _formation_slot_local(
	index: int,
	personnel_count: int,
	width_m: float,
	depth_m: float
) -> Vector2:
	return BattleFormationData.formation_slot_local(
		index,
		personnel_count,
		width_m,
		depth_m
	)

static func _formation_rotation(formation: BattleFormationData) -> float:
	var facing: Vector2 = formation.facing_direction.normalized()
	if facing == Vector2.ZERO:
		facing = Vector2.DOWN
	return facing.angle() - PI * 0.5

static func _formation_world_position(
	formation: BattleFormationData,
	local_slot: Vector2
) -> Vector2:
	return BattleFormationData.formation_world_position(
		formation.battle_position_m,
		formation.facing_direction,
		local_slot
	)

static func _reserve_person_position(
	index: int,
	entry_direction: int,
	size_meters: Vector2
) -> Vector2:
	var lateral_size: float = size_meters.x if entry_direction == BattleSiteContext.EntryDirection.NORTH \
		or entry_direction == BattleSiteContext.EntryDirection.SOUTH else size_meters.y
	var lateral_slots: int = maxi(floori(lateral_size), 1)
	var lateral_index: int = index % lateral_slots
	var depth_index: int = floori(float(index) / float(lateral_slots))
	var lateral: float = (float(lateral_index) + 0.5) * lateral_size / float(lateral_slots)
	var depth: float = (float(depth_index) + 0.5) * 2.0
	match entry_direction:
		BattleSiteContext.EntryDirection.NORTH:
			return Vector2(lateral, -RESERVE_STAGING_BAND_METERS + depth)
		BattleSiteContext.EntryDirection.SOUTH:
			return Vector2(lateral, size_meters.y + RESERVE_STAGING_BAND_METERS - depth)
		BattleSiteContext.EntryDirection.EAST:
			return Vector2(size_meters.x + RESERVE_STAGING_BAND_METERS - depth, lateral)
		BattleSiteContext.EntryDirection.WEST:
			return Vector2(-RESERVE_STAGING_BAND_METERS + depth, lateral)
		_:
			return Vector2.ZERO

func _draw_reserve_staging(size_meters: Vector2) -> void:
	_draw_reserve_band(
		_reserve_band_rect(size_meters, context.attacker_entry_direction),
		Color(0.18, 0.43, 0.85, 0.10)
	)
	_draw_reserve_band(
		_reserve_band_rect(size_meters, context.defender_entry_direction),
		Color(0.85, 0.25, 0.30, 0.10)
	)

func _draw_reserve_band(rect_meters: Rect2, color: Color) -> void:
	var rect_pixels: Rect2 = Rect2(
		meters_to_pixels(rect_meters.position),
		meters_to_pixels(rect_meters.size)
	)
	draw_rect(rect_pixels, color)
	draw_rect(rect_pixels, color.lightened(0.35), false, 2.0)

static func _reserve_band_rect(size_meters: Vector2, entry_direction: int) -> Rect2:
	match entry_direction:
		BattleSiteContext.EntryDirection.NORTH:
			return Rect2(Vector2(0.0, -RESERVE_STAGING_BAND_METERS), Vector2(size_meters.x, RESERVE_STAGING_BAND_METERS))
		BattleSiteContext.EntryDirection.SOUTH:
			return Rect2(Vector2(0.0, size_meters.y), Vector2(size_meters.x, RESERVE_STAGING_BAND_METERS))
		BattleSiteContext.EntryDirection.EAST:
			return Rect2(Vector2(size_meters.x, 0.0), Vector2(RESERVE_STAGING_BAND_METERS, size_meters.y))
		BattleSiteContext.EntryDirection.WEST:
			return Rect2(Vector2(-RESERVE_STAGING_BAND_METERS, 0.0), Vector2(RESERVE_STAGING_BAND_METERS, size_meters.y))
		_:
			return Rect2()

func _set_zoom(factor: float) -> void:
	var next_zoom: float = clampf(camera.zoom.x * factor, MIN_ZOOM, MAX_ZOOM)
	camera.zoom = Vector2.ONE * next_zoom
	_clamp_camera()

func _clamp_camera() -> void:
	var size_pixels: Vector2 = meters_to_pixels(generated["size_meters"] as Vector2)
	var margin: float = CAMERA_MARGIN_METERS * BATTLE_PIXELS_PER_METER
	camera.position = Vector2(
		clampf(camera.position.x, -margin, size_pixels.x + margin),
		clampf(camera.position.y, -margin, size_pixels.y + margin)
	)

func _update_debug_panel() -> void:
	var center: Dictionary = generated["center_cell"] as Dictionary
	var attacker_deployment: Dictionary = generated["attacker_deployment"] as Dictionary
	var defender_deployment: Dictionary = generated["defender_deployment"] as Dictionary
	battle_debug_label.text = """BATTLE SITE PROTOTYPE

Battle ID: %s
Center Global Cell: %s
Battle Size: 300m x 300m
Center Terrain: %s
Terrain Hash: %s
Command: %s
Battle Speed: %.1fx
Zoom: %.2fx (0.5x-16x)
Road Cells: %d   River Cells: %d

ATTACKER
%s
Total: %d
Initial Deployed: %d
Reserve: %d (%d formations off-map)
Entry: %s
Preview Formations: %d x %d people
Visual: reference NPC (64x64 / %.2fm x %.2fm)

DEFENDER
%s
Total: %d
Initial Deployed: %d
Reserve: %d (%d formations off-map)
Entry: %s
Preview Formations: %d x %d people
Visual: reference NPC (64x64 / %.2fm x %.2fm)

COMMANDS: 1 Advance | 2 Fall Back | 3 Attack | 4 Withdraw | 5 Flank Rear
SPEED: 0.5x | 1x | 2x | 4x | 8x | 16x
Left drag Pan | Wheel Zoom 0.5x-16x | ESC Return""" % [
		context.battle_id,
		_format_cell(context.center_global_region_cell),
		TerrainType.to_display_name(int(center["terrain_type"])).to_upper(),
		str(generated["terrain_hash"]).left(12),
		command_status if not command_status.is_empty() else "NONE",
		battle_speed_multiplier,
		camera.zoom.x,
		_feature_cell_count("road"),
		_feature_cell_count("river"),
		context.attacker.display_name,
		context.attacker.total_personnel,
		int(attacker_deployment["initial_deployed_personnel"]),
		int(attacker_deployment["reserve_personnel"]),
		BattleRules.formation_marker_count(int(attacker_deployment["reserve_personnel"])),
		BattleSiteContext.entry_name(context.attacker_entry_direction),
		int(attacker_deployment["marker_count"]),
		BattleRules.PERSONNEL_PER_FORMATION_MARKER,
		NPC_SPRITE_SIZE_METERS.x,
		NPC_SPRITE_SIZE_METERS.y,
		context.defender.display_name,
		context.defender.total_personnel,
		int(defender_deployment["initial_deployed_personnel"]),
		int(defender_deployment["reserve_personnel"]),
		BattleRules.formation_marker_count(int(defender_deployment["reserve_personnel"])),
		BattleSiteContext.entry_name(context.defender_entry_direction),
		int(defender_deployment["marker_count"]),
		BattleRules.PERSONNEL_PER_FORMATION_MARKER,
		NPC_SPRITE_SIZE_METERS.x,
		NPC_SPRITE_SIZE_METERS.y,
	]

func _feature_cell_count(key: String) -> int:
	var result: int = 0
	for cell: Dictionary in generated["footprint_cells"] as Array[Dictionary]:
		if bool(cell.get(key, false)):
			result += 1
	return result

func _format_cell(cell: Vector2i) -> String:
	return "(%d, %d)" % [cell.x, cell.y]

func _format_meters(meters: Vector2i) -> String:
	return "(%dm, %dm)" % [meters.x, meters.y]

func _format_world_time(seconds: int) -> String:
	if seconds < 0:
		return "??"
	var day: int = floori(float(seconds) / 86400.0)
	var hour: int = floori(float(seconds % 86400) / 3600.0)
	var minute: int = floori(float(seconds % 3600) / 60.0)
	return "Day %d  %02d:%02d" % [day, hour, minute]
