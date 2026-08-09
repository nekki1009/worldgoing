class_name DebugUI
extends CanvasLayer

@onready var layer_label: Label = $Panel/Margin/VBox/Layer
@onready var debug_view_label: Label = $Panel/Margin/VBox/DebugView
@onready var current_region_label: Label = $Panel/Margin/VBox/CurrentRegion
@onready var world_seed_label: Label = $Panel/Margin/VBox/WorldSeed
@onready var world_time_label: Label = $Panel/Margin/VBox/WorldTime
@onready var party_label: Label = $Panel/Margin/VBox/Party
@onready var party_position_label: Label = $Panel/Margin/VBox/PartyPosition
@onready var party_state_label: Label = $Panel/Margin/VBox/PartyState
@onready var world_cell_label: Label = $Panel/Margin/VBox/WorldCell
@onready var hovered_region_cell_label: Label = $Panel/Margin/VBox/HoveredRegionCell
@onready var selected_region_cell_label: Label = $Panel/Margin/VBox/SelectedRegionCell
@onready var global_region_cell_label: Label = $Panel/Margin/VBox/GlobalRegionCell
@onready var global_meter_label: Label = $Panel/Margin/VBox/GlobalMeter
@onready var elevation_label: Label = $Panel/Margin/VBox/Elevation
@onready var moisture_label: Label = $Panel/Margin/VBox/Moisture
@onready var river_label: Label = $Panel/Margin/VBox/River
@onready var terrain_type_label: Label = $Panel/Margin/VBox/TerrainType
@onready var poi_id_label: Label = $Panel/Margin/VBox/POIId
@onready var poi_type_label: Label = $Panel/Margin/VBox/POIType
@onready var poi_name_label: Label = $Panel/Margin/VBox/POIName
@onready var poi_candidate_label: Label = $Panel/Margin/VBox/POICandidate
@onready var poi_priority_label: Label = $Panel/Margin/VBox/POIPriority
@onready var poi_river_label: Label = $Panel/Margin/VBox/POIRiver
@onready var road_label: Label = $Panel/Margin/VBox/Road
@onready var river_crossing_label: Label = $Panel/Margin/VBox/RiverCrossing
@onready var route_ids_label: Label = $Panel/Margin/VBox/RouteIDs
@onready var route_details_label: Label = $Panel/Margin/VBox/RouteDetails
@onready var destination_label: Label = $Panel/Margin/VBox/Destination
@onready var path_distance_label: Label = $Panel/Margin/VBox/PathDistance
@onready var estimated_travel_label: Label = $Panel/Margin/VBox/EstimatedTravel
@onready var path_cells_label: Label = $Panel/Margin/VBox/PathCells
@onready var travel_label: Label = $Panel/Margin/VBox/Travel
@onready var poi_reached_label: Label = $Panel/Margin/VBox/POIReached
@onready var site_label: Label = $Panel/Margin/VBox/Site
@onready var instruction_label: Label = $Panel/Margin/VBox/Instruction

func _process(_delta: float) -> void:
	$FPS.text = "FPS: %d" % Engine.get_frames_per_second()

func update_state(state: Dictionary) -> void:
	layer_label.text = "Layer: %s" % state.get("layer", "??")
	debug_view_label.text = "Debug View: %s" % state.get("debug_view", "??")
	current_region_label.text = "Current Region: %s" % state.get("current_region", "??")
	world_seed_label.text = "World Seed: %s" % state.get("world_seed", "??")
	world_time_label.text = "World Time: %s" % state.get("world_time", "??")
	party_label.text = "Party: %s" % state.get("party_id", "??")
	party_position_label.text = "Party Position: %s" % state.get("party_position", "??")
	party_state_label.text = "Party State: %s" % state.get("party_state", "??")
	world_cell_label.text = "World Cell: %s" % state.get("world_cell", "??")
	hovered_region_cell_label.text = "Hovered Region Cell: %s" % state.get("hovered_region_cell", "??")
	selected_region_cell_label.text = "Selected Region Cell: %s" % state.get("selected_region_cell", "??")
	global_region_cell_label.text = "Global Region Cell: %s" % state.get("global_region_cell", "??")
	global_meter_label.text = "Hovered Global Meter Position: %s" % state.get("global_meter_position", "??")
	elevation_label.text = "Elevation: %s" % state.get("elevation", "??")
	moisture_label.text = "Moisture: %s" % state.get("moisture", "??")
	river_label.text = "River: %s (Strength %s)" % [state.get("river_mask", "??"), state.get("river_strength", "??")]
	terrain_type_label.text = "Terrain: %s" % state.get("terrain_type", "??")
	poi_id_label.text = "POI ID: %s" % state.get("poi_id", "??")
	poi_type_label.text = "POI Type: %s" % state.get("poi_type", "??")
	poi_name_label.text = "POI Name: %s" % state.get("poi_name", "??")
	poi_candidate_label.text = "POI Candidate Cell: %s" % state.get("poi_candidate_cell", "??")
	poi_priority_label.text = "POI Priority: %s" % state.get("poi_priority", "??")
	poi_river_label.text = "POI River Nearby: %s" % state.get("poi_river_nearby", "??")
	road_label.text = "Road: %s" % state.get("road", "??")
	river_crossing_label.text = "River Crossing: %s" % state.get("river_crossing", "??")
	route_ids_label.text = "Route IDs: %s" % state.get("route_ids", "??")
	route_details_label.text = "Route: %s" % state.get("route_details", "??")
	destination_label.text = "Destination: %s" % state.get("destination_global_cell", state.get("destination", "??"))
	path_distance_label.text = "Path Distance: %s (Remaining %s)" % [state.get("path_distance", "??"), state.get("remaining_distance", "??")]
	estimated_travel_label.text = "Estimated Travel: %s (ETA %s)" % [state.get("estimated_travel", "??"), state.get("remaining_eta", "??")]
	path_cells_label.text = "Path Cells: %s | Remaining %s | Search %s" % [state.get("path_cells", "??"), state.get("remaining_path_cells", "??"), state.get("path_search_time", "??")]
	travel_label.text = "Travel: %s | Regions %s | Multiplier %s | Speed %s | 100m %s | %s" % [
		state.get("passable", "??"),
		state.get("regions_crossed", "0"),
		state.get("travel_speed_multiplier", "1x"),
		state.get("effective_speed", "??"),
		state.get("cell_travel_time", "??"),
		state.get("travel_status", ""),
	]
	poi_reached_label.text = "POI Reached: %s" % state.get("poi_reached", "??")
	site_label.text = "Site: %s" % state.get("site", "??")
	instruction_label.text = str(state.get("instruction", ""))
