extends SceneTree

const Env = preload("res://scripts/terrain_lab/site_environment.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
var deadline := 0

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 15000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("SITE ARMY NAVIGATION did not complete")
		quit(1)
	return false

func _run() -> void:
	var data := TerrainData.new()
	data.allocate(Vector2i(40, 30))
	data.height_levels.fill(0)
	data.surface_types.fill(TerrainData.Surface.GRASS)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.spawn_cell = Vector2i(10, 15)
	Env.initialize(data, "army-navigation-fixture")
	data.resource_base.clear()
	Env.rebuild_indexes(data)
	var player := TerrainTestCharacter.new()
	player.data = data
	assert(player.place(data.spawn_cell, true))
	var npc := TerrainTestNPC.new()
	npc.data = data
	assert(npc.place(Vector2i(9, 15), true))
	var army := TerrainArmy.new()
	assert(army.deploy(data, player, npc))
	assert(player.place(Vector2i(30, 15), true))
	assert(army.issue_command(TerrainArmy.Command.FOLLOW_PLAYER))
	var previous := army.cells.duplicate()
	var revised := false
	var original_revision := army._structure_revision
	for frame: int in range(220):
		army.advance_frame(0.1)
		if not revised and army.moving_count() > 0:
			var obstacle := Vector2i(-1, -1)
			for y: int in range(8, 22):
				for x: int in range(23, 30):
					var candidate := Vector2i(x, y)
					if not army.reserves_terrain_cell(candidate) and not player.occupies_cell(candidate) and not npc.occupies_cell(candidate):
						obstacle = candidate
						break
				if obstacle.x >= 0:
					break
			assert(obstacle.x >= 0, "No unclaimed construction fixture")
			Env._add_resource(data, Env.Kind.STONE, data.index(obstacle), 100, 0)
			Env.rebuild_indexes(data)
			army.notify_terrain_changed()
			revised = true
		var unique := {}
		for unit: int in range(army.cells.size()):
			var cell := army.cells[unit]
			assert(data.is_walkable(cell) and not unique.has(cell), "Army entered a new blocker or duplicated an occupant")
			unique[cell] = true
			if cell != previous[unit]:
				assert(data.can_step(previous[unit], cell), "Army committed an illegal edge after terrain change")
		previous = army.cells.duplicate()
	assert(revised and army._structure_revision > original_revision and army.completed_steps() > 100)
	var old_descriptors := army._passage_descriptors.duplicate()
	var protected_cell := Vector2i(20, 5)
	army._passage_descriptors = [{"protected": [protected_cell]}]
	assert(army.reserves_terrain_cell(protected_cell))
	var footprint: Array[int] = [data.index(protected_cell)]
	assert(not Runtime.preview_build(data, "house", footprint, army.reserves_terrain_cell).ok)
	army._passage_descriptors = old_descriptors
	print("SITE ARMY NAVIGATION PASS: 100 unique occupants, moving-command drain, new blocker replan, passage construction guard; steps=", army.completed_steps())
	army.free()
	npc.free()
	player.free()
	quit(0)
