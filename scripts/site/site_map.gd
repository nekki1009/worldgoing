class_name SiteMap
extends Node2D

signal debug_state_changed(state: Dictionary)

var poi: WorldPOIData
var region: RegionData
var session: GameSession

func setup(p_poi: WorldPOIData, p_region: RegionData, p_session: GameSession) -> void:
	poi = p_poi
	region = p_region
	session = p_session
	queue_redraw()
	debug_state_changed.emit(get_debug_state())

func get_debug_state() -> Dictionary:
	var global_region_cell: Vector2i = poi.global_region_cell
	var global_meters: Vector2i = WorldCoordinates.global_region_cell_to_global_meters(global_region_cell)
	return {
		"layer": "SITE MAP",
		"current_region": "%s (%s)" % [region.region_name, region.region_id],
		"world_seed": session.world_seed,
		"world_time": session.format_world_time(),
		"party_id": session.party.party_id,
		"party_position": "%s / Global %s" % [_format_cell(session.party.get_region_cell()), _format_cell(session.party.current_global_region_cell)],
		"party_state": "At POI" if session.party.is_at(poi.world_cell, poi.region_cell) else "Away",
		"world_cell": _format_cell(poi.world_cell),
		"hovered_region_cell": "??",
		"selected_region_cell": _format_cell(poi.region_cell),
		"global_region_cell": _format_cell(global_region_cell),
		"global_meter_position": _format_meters(global_meters),
		"terrain_type": TerrainType.to_display_name(poi.terrain_type),
		"elevation": "%.2f" % poi.elevation,
		"moisture": "%.2f" % poi.moisture,
		"river_mask": "Yes" if poi.river_nearby else "No",
		"river_strength": "nearby" if poi.river_nearby else "0.00",
		"poi_id": poi.poi_id,
		"poi_type": WorldPOIType.to_display_name(poi.poi_type),
		"poi_name": poi.site_name,
		"poi_candidate_cell": _format_cell(poi.candidate_cell),
		"poi_priority": "%.3f" % poi.deterministic_priority,
		"poi_river_nearby": "Yes" if poi.river_nearby else "No",
		"site": "%s (%s)" % [poi.site_name, WorldPOIType.to_display_name(poi.poi_type)],
		"instruction": "Placeholder Site Map   ESC: Return to Region Map"
	}

func _draw() -> void:
	draw_rect(Rect2(-1100, -600, 2200, 1200), Color("211d2b"))
	draw_rect(Rect2(-900, -400, 1800, 800), Color("3d5260"))
	draw_rect(Rect2(-760, -300, 1520, 600), Color("577667"))
	draw_circle(Vector2.ZERO, 170.0, Color("d79b55"))
	draw_circle(Vector2.ZERO, 120.0, Color("7b4c3b"))
	draw_rect(Rect2(-260, 180, 520, 56), Color("263541"))

func _format_cell(cell: Vector2i) -> String:
	return "(%d, %d)" % [cell.x, cell.y]

func _format_meters(meters: Vector2i) -> String:
	return "(%dm, %dm)" % [meters.x, meters.y]
