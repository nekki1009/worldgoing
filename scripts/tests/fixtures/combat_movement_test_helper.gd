class_name CombatMovementTestHelper
extends RefCounted
## Deterministic test fixtures and synthetic map helpers for combat movement,
## formation corridor transit, reservation arbitration, and platform deployment.

const TerrainArmyScript = preload("res://scripts/terrain_lab/terrain_army.gd")

## Builds a flat, fully walkable test grid of the given size.
static func build_flat_map(width: int = 50, height: int = 50) -> TerrainData:
	var data := TerrainData.new()
	data.allocate(Vector2i(width, height))
	SiteEnvironment.initialize(data, "flat-fixture")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	return data

## Builds a map with an open start zone, a narrow bottleneck corridor of specified
## width and length, and an open destination zone.
static func build_bottleneck_map(grid_size: Vector2i = Vector2i(80, 40), corridor_y: int = 20, corridor_x_start: int = 25, corridor_x_end: int = 45, corridor_width: int = 1) -> Dictionary:
	var data := TerrainData.new()
	data.allocate(grid_size)
	SiteEnvironment.initialize(data, "bottleneck-fixture")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	
	# Block a vertical wall at x in [corridor_x_start, corridor_x_end] except for corridor rows
	var wall_x_start := corridor_x_start
	var wall_x_end := corridor_x_end
	var corridor_y_min := corridor_y
	var corridor_y_max := corridor_y + corridor_width - 1
	
	for y in range(grid_size.y):
		if y >= corridor_y_min and y <= corridor_y_max:
			continue
		for x in range(wall_x_start, wall_x_end + 1):
			var idx := data.index(Vector2i(x, y))
			data.flags[idx] = 0 # Non-walkable obstacle
			data.static_blocked[idx] = 1
			
	return {
		"data": data,
		"corridor_start": Vector2i(wall_x_start, corridor_y),
		"corridor_end": Vector2i(wall_x_end, corridor_y),
		"corridor_width": corridor_width,
		"corridor_length": wall_x_end - wall_x_start + 1
	}

## Builds a map with a U-shaped barrier forcing long-distance macro pathing.
static func build_u_turn_map(grid_size: Vector2i = Vector2i(60, 60)) -> Dictionary:
	var data := TerrainData.new()
	data.allocate(grid_size)
	SiteEnvironment.initialize(data, "u-turn-fixture")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	
	# Horizontal barrier across the middle from x=10 to x=50 at y=30
	for x in range(10, 50):
		var idx := data.index(Vector2i(x, 30))
		data.flags[idx] = 0
		data.static_blocked[idx] = 1
		
	# Vertical walls at x=10 extending up to y=15 and x=50 extending up to y=15
	for y in range(15, 30):
		var idx_left := data.index(Vector2i(10, y))
		var idx_right := data.index(Vector2i(49, y))
		data.flags[idx_left] = 0
		data.static_blocked[idx_left] = 1
		data.flags[idx_right] = 0
		data.static_blocked[idx_right] = 1
		
	return {
		"data": data,
		"start_area": Vector2i(30, 20),
		"goal_area": Vector2i(30, 40)
	}

## Builds a synthetic elevated mountaintop platform:
## - Exactly platform_capacity walkable cells at height level 2
## - Exactly 1-tile ramp approach leading up from height 0
## - Surrounded by non-walkable cliff edges
static func build_mountain_platform_map(grid_size: Vector2i = Vector2i(60, 60), platform_center: Vector2i = Vector2i(30, 30), platform_radius: int = 4, _ramp_direction: Vector2i = Vector2i.DOWN) -> Dictionary:
	var data := TerrainData.new()
	data.allocate(grid_size)
	SiteEnvironment.initialize(data, "platform-fixture")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	
	# Platform cells around platform_center
	var platform_cells: Array[Vector2i] = []
	for dy in range(-platform_radius, platform_radius + 1):
		for dx in range(-platform_radius, platform_radius + 1):
			var cell := platform_center + Vector2i(dx, dy)
			if dx * dx + dy * dy <= platform_radius * platform_radius:
				platform_cells.append(cell)
				var idx := data.index(cell)
				data.height_levels[idx] = 2
				
	# Surrounding cliff ring (height 2 but non-walkable, except at ramp ingress)
	# Connect northern ingress at platform_center + Vector2i(0, -platform_radius)
	var ingress_top := platform_center + Vector2i(0, -platform_radius)
	var ramp_step1 := platform_center + Vector2i(0, -platform_radius - 1)
	var ramp_step0 := platform_center + Vector2i(0, -platform_radius - 2)
	
	var idx_top := data.index(ingress_top)
	var idx_step1 := data.index(ramp_step1)
	var idx_step0 := data.index(ramp_step0)
	
	data.height_levels[idx_top] = 2
	data.height_levels[idx_step1] = 1
	data.height_levels[idx_step0] = 0
	
	# Moving DOWN (dir 2): step0 (h0) -> step1 (h1) -> top (h2)
	data.ramp_edges[idx_step0] |= (1 << 2)
	data.ramp_edges[idx_step1] |= (1 << 0)
	data.ramp_edges[idx_step1] |= (1 << 2)
	data.ramp_edges[idx_top] |= (1 << 0)
	
	var ramp_mouth := ramp_step0
	var ramp_cells: Array[Vector2i] = [ramp_step0, ramp_step1, ingress_top]
		
	return {
		"data": data,
		"platform_center": platform_center,
		"platform_cells": platform_cells,
		"platform_capacity": platform_cells.size(),
		"ramp_mouth": ramp_mouth,
		"ramp_cells": ramp_cells
	}

## A single-entrance plateau with 60 final cells and a separate ingress cell.
## The existing circular fixture above has 49 or 81 high cells, never 60.
static func build_exact_60_platform_map() -> Dictionary:
	var data := build_flat_map(80, 60)
	var final_cells: Array[Vector2i] = []
	for y in range(25, 35):
		for x in range(45, 51):
			var cell := Vector2i(x, y)
			data.height_levels[data.index(cell)] = 2
			final_cells.append(cell)
	var ingress := Vector2i(44, 30)
	var ramp := Vector2i(43, 30)
	var foot := Vector2i(42, 30)
	data.height_levels[data.index(ingress)] = 2
	data.height_levels[data.index(ramp)] = 1
	data.ramp_edges[data.index(foot)] |= 1 << 1
	data.ramp_edges[data.index(ramp)] |= (1 << 3) | (1 << 1)
	data.ramp_edges[data.index(ingress)] |= 1 << 3
	assert(final_cells.size() == 60)
	assert(data.can_step(foot, ramp) and data.can_step(ramp, ingress))
	return {
		"data": data,
		"anchor": Vector2i(48, 30),
		"ingress": ingress,
		"ramp": ramp,
		"final_cells": final_cells,
		"start": Vector2i(2, 30),
	}

## Creates a deterministic 100-person TerrainArmy instance on the given map
## configured for headless tests without GPU presentation.
static func create_test_army(data: TerrainData, team_id: int = 1, faction_id: int = 0, soldier_count: int = 100, origin: Vector2i = Vector2i(5, 5)) -> TerrainArmy:
	var army: TerrainArmy = TerrainArmyScript.new()
	army.team_id = team_id
	army.faction_id = faction_id
	army.roster_size = soldier_count
	army.exchange_enabled = true
	# Like TerrainLab's dynamic team slots (_ensure_army_slots), the captain uses
	# the shared pooled geometry instead of a private live presenter per army.
	army.defer_captain_presenter = true
	# Production armies live in the scene tree, and their live presenters build
	# their UI in _ready, so the fixture army joins the tree before it deploys.
	(Engine.get_main_loop() as SceneTree).root.add_child(army)
	# READY re-enables an overridden _process; fixtures step the army explicitly.
	army.set_process(false)
	
	var placement_cells: Array[Vector2i] = []
	var cols := 10
	for i in range(soldier_count):
		placement_cells.append(origin + Vector2i(i % cols, floori(float(i) / float(cols))))
		
	var deployed := army.deploy_at(data, null, null, placement_cells)
	assert(deployed, "Test army deploy_at must succeed")
	var combat_ok := army.enable_combat(false)
	assert(combat_ok, "Test army enable_combat must succeed")
	return army
