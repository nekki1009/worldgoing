class_name BattleSiteMap
extends Node2D

signal debug_state_changed(state: Dictionary)

const BATTLE_PIXELS_PER_METER: float = 4.0
const CAMERA_SPEED_PIXELS: float = 900.0
const CAMERA_MARGIN_METERS: float = 50.0
const MIN_ZOOM: float = 0.50
const MAX_ZOOM: float = 2.50

@onready var camera: Camera2D = $Camera2D
@onready var battle_debug_label: Label = $BattleDebugPanel/Panel/Margin/BattleDebugLabel

var context: BattleSiteContext
var snapshot: BattleSiteSnapshot
var generated: Dictionary = {}

func setup(p_snapshot: BattleSiteSnapshot) -> void:
	if p_snapshot == null or not p_snapshot.has_preview():
		return
	snapshot = p_snapshot
	context = snapshot.context
	generated = {
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
	var size_meters: Vector2 = generated["size_meters"] as Vector2
	camera.position = meters_to_pixels(size_meters * 0.5)
	camera.zoom = Vector2(0.85, 0.85)
	_update_debug_panel()
	queue_redraw()
	debug_state_changed.emit(get_debug_state())

static func meters_to_pixels(battle_local_meter_position: Vector2) -> Vector2:
	return battle_local_meter_position * BATTLE_PIXELS_PER_METER

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
		"party_position": "Formation preview only",
		"party_state": "Initial deployment / Off-map reserve",
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
		"instruction": "WASD: Camera   Wheel: Zoom   ESC: Return to Region Map",
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
	draw_rect(
		Rect2(-Vector2.ONE * 120.0, size_pixels + Vector2.ONE * 240.0),
		Color("111820")
	)
	for cell: Dictionary in generated["footprint_cells"] as Array[Dictionary]:
		_draw_ground_cell(cell)
	for cell: Dictionary in generated["footprint_cells"] as Array[Dictionary]:
		_draw_cell_details(cell)
		_draw_cell_corridors(cell)
	_draw_grid(size_pixels)
	_draw_deployment_preview(generated["attacker_deployment"] as Dictionary, Color("3f8cff"))
	_draw_deployment_preview(generated["defender_deployment"] as Dictionary, Color("e85f62"))

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
	var facing: Vector2 = deployment["facing"] as Vector2
	for value: Variant in deployment["marker_positions_meters"] as Array:
		var marker: Vector2 = meters_to_pixels(value as Vector2)
		draw_circle(marker, 13.0, Color("152132"))
		draw_circle(marker, 9.0, color)
		draw_line(marker, marker + facing * 18.0, Color.WHITE, 3.0, true)

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
