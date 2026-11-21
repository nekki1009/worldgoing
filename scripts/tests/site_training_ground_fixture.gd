extends RefCounted
## Explicit fixture setup only. Real training still uses the original controller,
## people, supply, fatigue and Site clock; natural work sources stay untouched.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Env = preload("res://scripts/terrain_lab/site_environment.gd")

static func build(data: TerrainData, origin: Vector2i, size: Vector2i, faction: int) -> String:
	var stock: Dictionary = data.site.inventory.duplicate(true)
	data.site.inventory.wood = maxi(int(data.site.inventory.get("wood", 0)), size.x * size.y)
	data.site.inventory.tools = maxi(int(data.site.inventory.get("tools", 0)), 1)
	var layout := Runtime.building_cells(data, "training_ground", origin, size)
	assert(layout.ok, str(layout))
	var cells: Array[int] = []
	cells.assign(layout.cells)
	var result := Runtime.request_build(data, "training_ground", cells, Callable(), {"owner_faction": faction})
	assert(result.ok, str(result))
	var key := str(result.feature)
	var feature: Dictionary = data.site.features[key]
	assert(feature.clearing.is_empty(), "Fixture must explicitly clear its own plot before construction")
	var task := {"target": "feature:" + key, "action": "construct", "cell": int(feature.entrance), "mode": "work", "status": ""}
	Runtime._feature_work(data, key, float(feature.work), Callable(), Callable(), task, {}, 20, faction)
	assert(str(feature.stage) == "complete")
	data.site.inventory.clear()
	data.site.inventory.merge(stock)
	return key

static func natural(lab: TerrainLab) -> String:
	var data: TerrainData = lab.terrain
	var protected := {}
	for zone: Dictionary in data.site.zones:
		for index: int in zone.cells: protected[int(index)] = true
	for team: TerrainArmy in lab.combat_armies:
		for cell: Vector2i in team.cells: protected[data.index(cell)] = true
	for actor: TerrainTestCharacter in lab.combat_actors:
		protected[data.index(actor.terrain_cell)] = true
	protected[int(data.site.depot_cell)] = true
	protected[data.index(data.spawn_cell)] = true
	for y: int in range(1, data.size.y - 11):
		for x: int in range(1, data.size.x - 11):
			var plot := Rect2i(Vector2i(x, y), Vector2i(10, 10))
			var border := plot.grow(1)
			var valid := true
			for cy: int in range(border.position.y, border.end.y):
				for cx: int in range(border.position.x, border.end.x):
					var cell := Vector2i(cx, cy)
					var index := data.index(cell)
					if protected.has(index) or not data.is_terrain_walkable(cell) or int(data.foundation[index]) < 35 or data.feature_at[index] != 0:
						valid = false
			if not valid: continue
			for cy: int in range(border.position.y, border.end.y):
				for cx: int in range(border.position.x, border.end.x):
					var index := data.index(Vector2i(cx, cy))
					data.height_levels[index] = 0
					data.site.terrain_changes[str(index)] = 0
					for source: String in data.resources_at.get(index, []):
						Env.change(data, source, {"cleared": true, "remaining": 0})
			Runtime.rebuild_terrain_edges(data)
			Env.rebuild_indexes(data)
			return build(data, plot.position, plot.size, lab.army.faction_id)
	assert(false, "Natural fixture needs a separate legal school plot outside all original work zones")
	return ""

static func enter(lab: TerrainLab, key: String = "") -> Dictionary:
	var data: TerrainData = lab.terrain
	if key.is_empty():
		for id: String in data.site.features:
			if str(data.site.features[id].kind) == "training_ground": key = id; break
	assert(not key.is_empty())
	var team: TerrainArmy = lab.army
	var spaces := Runtime.military_walkable_cells(data, data.site.features[key])
	assert(spaces.size() > team.cells.size())
	var original := {"cells": team.cells.duplicate(), "desired": team.desired_cells.duplicate(), "slots": team.combat_slots.duplicate(), "actor_id": -1, "actor_cell": TerrainArmy.INVALID_CELL}
	for index: int in team.cells.size():
		team.cells[index] = data.cell_from_index(spaces[index])
		team.desired_cells[index] = team.cells[index]
		team.combat_slots[index] = team.cells[index]
	_refresh(lab, team)
	if is_instance_valid(team.player_member):
		original.actor_id = team.player_member.person_id
		original.actor_cell = team.player_member.terrain_cell
		assert(team.player_member.place(data.cell_from_index(spaces[team.cells.size()]), true))
	return original

static func leave(lab: TerrainLab, original: Dictionary) -> void:
	var team: TerrainArmy = lab.army
	team.cells.assign(original.cells)
	team.desired_cells.assign(original.desired)
	team.combat_slots.assign(original.slots)
	_refresh(lab, team)
	if int(original.actor_id) >= 0:
		for actor: TerrainTestCharacter in lab.combat_actors:
			if actor.person_id == int(original.actor_id): assert(actor.place(original.actor_cell, true))

static func _refresh(lab: TerrainLab, team: TerrainArmy) -> void:
	team._cell_owners.clear()
	for index: int in team.cells.size():
		assert(team.moving_to[index] == TerrainArmy.INVALID_CELL)
		if team.combat_can_act(index): team._cell_owners[team.cells[index]] = index
		team._mark_visual_row(index)
	if lab.combat_movement_coordinator != null: lab.combat_movement_coordinator.request_occupancy_rebuild()
