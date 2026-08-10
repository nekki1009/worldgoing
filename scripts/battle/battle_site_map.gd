class_name BattleSiteMap
extends Node2D

signal debug_state_changed(state: Dictionary)
signal formation_move_requested(formation_id: String, target_position_m: Vector2)

const BATTLE_PIXELS_PER_METER: float = 4.0
const CAMERA_SPEED_PIXELS: float = 900.0
const CAMERA_MARGIN_METERS: float = 60.0
const MIN_ZOOM: float = 0.50
const MAX_ZOOM: float = 2.50
const SOLDIER_MARKER_SIZE_METERS: float = 0.60
const FORMATION_COLUMNS: int = 20
const FORMATION_ROWS: int = 5
const RESERVE_STAGING_BAND_METERS: float = 60.0

@onready var camera: Camera2D = $Camera2D
@onready var soldier_instances: MultiMeshInstance2D = $SoldierInstances
@onready var battle_debug_label: Label = $BattleDebugPanel/Panel/Margin/BattleDebugLabel

var context: BattleSiteContext
var snapshot: BattleSiteSnapshot
var generated: Dictionary = {}
var active_formations: Array[BattleFormationData] = []
var selected_formation_id: String = ""
var camera_initialized: bool = false
var soldier_multimesh: MultiMesh
var formation_instance_ranges: Dictionary = {}
var visual_formation_counts: Dictionary = {}
var visual_reserve_counts: Dictionary = {}
var visual_battle_id: String = ""
var visual_revision: int = -1
var visual_total_personnel: int = -1

func _ready() -> void:
	var soldier_mesh: QuadMesh = QuadMesh.new()
	soldier_mesh.size = Vector2.ONE
	soldier_multimesh = MultiMesh.new()
	soldier_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	soldier_multimesh.use_colors = true
	soldier_multimesh.mesh = soldier_mesh
	soldier_instances.multimesh = soldier_multimesh

func setup(p_snapshot: BattleSiteSnapshot) -> void:
	if p_snapshot == null or not p_snapshot.has_preview():
		return
	var reset_camera: bool = not camera_initialized or context == null \
		or context.battle_id != p_snapshot.context.battle_id
	snapshot = p_snapshot
	context = snapshot.context
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
	var rebuild_soldiers: bool = _visual_layout_changed()
	if rebuild_soldiers:
		_rebuild_soldier_instances()
	elif snapshot.revision != visual_revision:
		_sync_active_soldier_instances()
	visual_revision = snapshot.revision
	if reset_camera:
		var size_meters: Vector2 = generated["size_meters"] as Vector2
		camera.position = meters_to_pixels(size_meters * 0.5)
		camera.zoom = Vector2(0.85, 0.85)
		camera_initialized = true
	_update_debug_panel()
	queue_redraw()
	debug_state_changed.emit(get_debug_state())

static func meters_to_pixels(battle_local_meter_position: Vector2) -> Vector2:
	return battle_local_meter_position * BATTLE_PIXELS_PER_METER

static func pixels_to_meters(battle_local_pixel_position: Vector2) -> Vector2:
	return battle_local_pixel_position / BATTLE_PIXELS_PER_METER

func _process(delta: float) -> void:
	if generated.is_empty():
		return
	var direction: Vector2 = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if Input.is_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_W):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		direction.y += 1.0
	if direction != Vector2.ZERO:
		camera.position += direction.normalized() * CAMERA_SPEED_PIXELS * delta / camera.zoom.x
		_clamp_camera()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_set_zoom(1.1)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_set_zoom(0.9)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
		_select_formation(pixels_to_meters(get_local_mouse_position()))
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT and not selected_formation_id.is_empty():
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
		"instruction": "WASD: Camera   Wheel: Zoom   Click: Select   Right-click: Move   ESC: Return",
	}

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
	for cell: Dictionary in generated["footprint_cells"] as Array[Dictionary]:
		_draw_cell_details(cell)
		_draw_cell_corridors(cell)
	_draw_grid(size_pixels)
	_draw_deployment_preview(generated["attacker_deployment"] as Dictionary, Color("3f8cff"))
	_draw_deployment_preview(generated["defender_deployment"] as Dictionary, Color("e85f62"))
	_draw_formations()

func _draw_ground_cell(cell: Dictionary) -> void:
	var origin: Vector2 = meters_to_pixels(cell["local_origin_meters"] as Vector2)
	var cell_pixels: float = float(WorldCoordinates.REGION_CELL_SIZE_METERS) * BATTLE_PIXELS_PER_METER
	var elevation: float = float(cell["elevation"])
	var color: Color = TerrainType.to_color(int(cell["terrain_type"]))
	color = color.lightened((elevation - 0.5) * 0.16) if elevation >= 0.5 \
		else color.darkened((0.5 - elevation) * 0.16)
	draw_rect(Rect2(origin, Vector2.ONE * cell_pixels), color)
	if int(cell["terrain_type"]) == TerrainType.MOUNTAIN:
		draw_circle(origin + Vector2.ONE * cell_pixels * 0.5, cell_pixels * 0.33, Color(0.25, 0.27, 0.30, 0.22))

func _draw_cell_details(cell: Dictionary) -> void:
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
		draw_circle(point, 10.0, Color("25553c"))
		draw_circle(point + Vector2(5.0, -3.0), 7.0, Color("35704e"))
	for value: Variant in details.get("trees", []):
		var point: Vector2 = meters_to_pixels(value as Vector2)
		draw_circle(point, 17.0, Color("173d2e"))
		draw_circle(point + Vector2(-5.0, -5.0), 13.0, Color("245e3f"))
		draw_circle(point + Vector2(6.0, -7.0), 11.0, Color("32734c"))
		draw_circle(point, 4.0, Color("5b4030"))

func _draw_cell_corridors(cell: Dictionary) -> void:
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
	if bool(cell["road"]):
		_draw_corridor(
			center_meters,
			cell["road_connection_offsets"] as Array,
			Color("493c2b"),
			9.0 * BATTLE_PIXELS_PER_METER
		)
		_draw_corridor(
			center_meters,
			cell["road_connection_offsets"] as Array,
			Color("b7925d"),
			6.0 * BATTLE_PIXELS_PER_METER
		)
	if bool(cell["river_crossing"]):
		var bridge_size: Vector2 = Vector2(22.0, 9.0) * BATTLE_PIXELS_PER_METER
		draw_rect(Rect2(meters_to_pixels(center_meters) - bridge_size * 0.5, bridge_size), Color("d0ad73"))

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

func _draw_grid(size_pixels: Vector2) -> void:
	var cell_pixels: float = float(WorldCoordinates.REGION_CELL_SIZE_METERS) * BATTLE_PIXELS_PER_METER
	for index: int in range(4):
		var offset: float = float(index) * cell_pixels
		draw_line(Vector2(offset, 0.0), Vector2(offset, size_pixels.y), Color(0.07, 0.10, 0.12, 0.78), 3.0)
		draw_line(Vector2(0.0, offset), Vector2(size_pixels.x, offset), Color(0.07, 0.10, 0.12, 0.78), 3.0)
	draw_rect(Rect2(Vector2.ZERO, size_pixels), Color("e6dcc5"), false, 5.0)

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
	var facing: Vector2 = deployment["facing"] as Vector2
	for value: Variant in deployment["marker_positions_meters"] as Array:
		var marker: Vector2 = meters_to_pixels(value as Vector2)
		draw_circle(marker, 13.0, Color("152132"))
		draw_circle(marker, 9.0, color)
		draw_line(marker, marker + facing * 18.0, Color.WHITE, 3.0, true)

func _draw_formations() -> void:
	for formation: BattleFormationData in active_formations:
		var center: Vector2 = meters_to_pixels(formation.battle_position_m)
		var color: Color = Color("4d98ff") if formation.side == BattleFormationData.Side.ATTACKER \
			else Color("e8646a")
		var fill_color: Color = color
		fill_color.a = 0.26 if formation.formation_id == selected_formation_id else 0.10
		if formation.formation_id == selected_formation_id:
			color = color.lightened(0.30)
		draw_set_transform(center, _formation_rotation(formation), Vector2.ONE)
		var size_pixels: Vector2 = Vector2(formation.width_m, formation.depth_m) * BATTLE_PIXELS_PER_METER
		draw_rect(Rect2(-size_pixels * 0.5, size_pixels), fill_color)
		draw_rect(Rect2(-size_pixels * 0.5, size_pixels), Color.WHITE, false, 2.0)
		draw_line(
			Vector2(0.0, 0.0),
			Vector2(0.0, formation.depth_m * BATTLE_PIXELS_PER_METER * 0.65),
			Color.WHITE,
			3.0
		)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if formation.formation_id == selected_formation_id and formation.path.size() > 1:
			var path_points: PackedVector2Array = PackedVector2Array()
			for cell: Vector2i in formation.path:
				path_points.append(meters_to_pixels(
					Vector2(cell) * float(SiteLayoutData.CELL_SIZE_METERS) \
					+ Vector2.ONE * float(SiteLayoutData.CELL_SIZE_METERS) * 0.5
				))
			draw_polyline(path_points, Color(1.0, 1.0, 1.0, 0.65), 3.0, true)

func _select_formation(position_m: Vector2) -> void:
	selected_formation_id = ""
	for formation: BattleFormationData in active_formations:
		var local: Vector2 = (position_m - formation.battle_position_m).rotated(
			-_formation_rotation(formation)
		)
		if absf(local.x) <= formation.width_m * 0.5 and absf(local.y) <= formation.depth_m * 0.5:
			selected_formation_id = formation.formation_id
			break
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
	var transform: Transform2D = Transform2D()
	transform.origin = meters_to_pixels(position_m)
	var marker_pixels: float = SOLDIER_MARKER_SIZE_METERS * BATTLE_PIXELS_PER_METER
	transform.x = Vector2(marker_pixels, 0.0)
	transform.y = Vector2(0.0, marker_pixels)
	soldier_multimesh.set_instance_transform_2d(index, transform)
	soldier_multimesh.set_instance_color(index, color)

static func _formation_slot_local(
	index: int,
	personnel_count: int,
	width_m: float,
	depth_m: float
) -> Vector2:
	var count: int = clampi(personnel_count, 1, FORMATION_COLUMNS * FORMATION_ROWS)
	var rows_used: int = ceili(float(count) / float(FORMATION_COLUMNS))
	var row: int = index / FORMATION_COLUMNS
	var slot: int = index % FORMATION_COLUMNS
	var count_in_row: int = mini(FORMATION_COLUMNS, count - row * FORMATION_COLUMNS)
	var row_offset: int = (FORMATION_ROWS - rows_used) / 2
	var actual_row: int = row_offset + row
	var column: int = _center_out_column(slot, count_in_row)
	var x: float = -width_m * 0.5 + width_m * (float(column) + 0.5) / float(FORMATION_COLUMNS)
	var row_step: float = depth_m / float(FORMATION_ROWS)
	var y: float = depth_m * 0.5 - row_step * (float(actual_row) + 0.5)
	return Vector2(x, y)

static func _center_out_column(slot: int, count: int) -> int:
	var left: int = floori(float(count - 1) * 0.5)
	var right: int = ceili(float(count - 1) * 0.5)
	if slot == 0:
		return left
	if slot == 1:
		return right
	var offset: int = floori(float(slot) * 0.5)
	return left - offset if slot % 2 == 0 else right + offset

static func _formation_rotation(formation: BattleFormationData) -> float:
	var facing: Vector2 = formation.facing_direction.normalized()
	if facing == Vector2.ZERO:
		facing = Vector2.DOWN
	return facing.angle() - PI * 0.5

static func _formation_world_position(
	formation: BattleFormationData,
	local_slot: Vector2
) -> Vector2:
	var facing: Vector2 = formation.facing_direction.normalized()
	if facing == Vector2.ZERO:
		facing = Vector2.DOWN
	var lateral: Vector2 = Vector2(facing.y, -facing.x)
	return formation.battle_position_m + lateral * local_slot.x + facing * local_slot.y

static func _reserve_person_position(
	index: int,
	entry_direction: int,
	size_meters: Vector2
) -> Vector2:
	var lateral_size: float = size_meters.x if entry_direction == BattleSiteContext.EntryDirection.NORTH \
		or entry_direction == BattleSiteContext.EntryDirection.SOUTH else size_meters.y
	var lateral_slots: int = maxi(floori(lateral_size), 1)
	var lateral_index: int = index % lateral_slots
	var depth_index: int = index / lateral_slots
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
Road Cells: %d   River Cells: %d

ATTACKER
%s
Total: %d
Initial Deployed: %d
Reserve: %d (%d formations off-map)
Entry: %s
Preview Markers: %d x %d personnel

DEFENDER
%s
Total: %d
Initial Deployed: %d
Reserve: %d (%d formations off-map)
Entry: %s
Preview Markers: %d x %d personnel

WASD Camera | Wheel Zoom | ESC Return""" % [
		context.battle_id,
		_format_cell(context.center_global_region_cell),
		TerrainType.to_display_name(int(center["terrain_type"])).to_upper(),
		str(generated["terrain_hash"]).left(12),
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
		context.defender.display_name,
		context.defender.total_personnel,
		int(defender_deployment["initial_deployed_personnel"]),
		int(defender_deployment["reserve_personnel"]),
		BattleRules.formation_marker_count(int(defender_deployment["reserve_personnel"])),
		BattleSiteContext.entry_name(context.defender_entry_direction),
		int(defender_deployment["marker_count"]),
		BattleRules.PERSONNEL_PER_FORMATION_MARKER,
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
