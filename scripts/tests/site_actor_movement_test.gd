extends SceneTree
## Actual original actor movement, not visual Tween or fabricated frame positions.
const Timings = preload("res://scripts/terrain_lab/character_combat_timings.gd")

class MovementLab extends TerrainLab:
	func _ready() -> void:
		set_process(false)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var map := TerrainGenerator.generate(0, 581)
	SiteEnvironment.initialize(map, "actor-movement-fixture")
	map.height_levels.fill(0)
	map.flags.fill(TerrainData.Flag.WALKABLE)
	map.static_blocked.fill(0)
	map.ramp_edges.fill(0)
	var lab := MovementLab.new()
	root.add_child(lab)
	lab.terrain = map
	var actors: Array[TerrainTestCharacter] = [TerrainTestCharacter.new(), TerrainTestNPC.new()]
	for index in range(actors.size()):
		var actor := actors[index]
		root.add_child(actor)
		actor.set_process(false)
		actor.data = map
		actor.person_id = index + 1
		actor.combat_driven_by_lab = true
		lab.combat_actors.append(actor)
	for running: bool in [false, true]:
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var duration := TerrainTestCharacter.RUN_DURATION if running else TerrainTestCharacter.MOVE_DURATION
			for actor: TerrainTestCharacter in actors:
				assert(actor.place(Vector2i(20, 20), true))
				assert(actor.step(direction, running))
				assert(actor.is_moving() and actor.occupies_cell(Vector2i(20, 20)))
			lab._advance_combat(duration * 0.25)
			var origin := (Vector2(20, 20) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
			var expected := origin + Vector2(direction) * TerrainRenderer.CELL_PIXELS * Timings.movement_weight(0.25)
			for actor: TerrainTestCharacter in actors:
				assert(actor.position.distance_to(expected) < 0.001)
				var snapshot := actor.capture_state()
				assert(TerrainTestCharacter.valid_state(snapshot, map))
				var wire: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
				assert(TerrainTestCharacter.valid_state(wire, map))
				actor.restore_state(wire)
				assert(actor.position.distance_to(expected) < 0.001)
				var malformed := wire.duplicate(true)
				malformed.movement.elapsed = -1.0
				assert(not TerrainTestCharacter.valid_state(malformed, map))
			var before := actors[0].capture_state()
			paused = true
			lab._advance_combat(1.0)
			assert(not actors[0].step(direction))
			paused = false
			assert(actors[0].capture_state() == before)
			map.site.paused = true
			lab._advance_combat(1.0)
			map.site.paused = false
			assert(actors[0].capture_state() == before)
			lab._advance_combat(duration * 0.25)
			expected = origin + Vector2(direction) * TerrainRenderer.CELL_PIXELS * Timings.movement_weight(0.5)
			for actor: TerrainTestCharacter in actors:
				assert(actor.position.distance_to(expected) < 0.001, "Loading changed the original quadratic curve")
				actor.hp = 0.0 # Death cannot cancel an already reserved legal step.
			lab._advance_combat(duration * 0.5)
			for actor: TerrainTestCharacter in actors:
				assert(not actor.is_moving())
				assert(actor.position.distance_to(origin + Vector2(direction) * TerrainRenderer.CELL_PIXELS) < 0.001)
				actor.reset_combat()
	# Legacy save keeps the previous loader's linear remainder once, then new
	# movement is quadratic. Do not infer missing elapsed time from a visual.
	var player := actors[0]
	assert(player.place(Vector2i(20, 20), true) and player.step(Vector2i.RIGHT))
	lab._advance_combat(0.1)
	var legacy := player.capture_state()
	legacy.erase("movement")
	assert(TerrainTestCharacter.valid_state(legacy, map))
	player.restore_state(legacy)
	var old_start := player.position
	var destination := (Vector2(player.terrain_cell) + Vector2.ONE * 0.5) * TerrainRenderer.CELL_PIXELS
	lab._advance_combat(float(legacy.movement_left) * 0.5)
	assert(player.position.distance_to(old_start.lerp(destination, 0.5)) < 0.001)
	# NPC multi-step navigation must not depend on the number of rendered frames.
	var npc := actors[1] as TerrainTestNPC
	var results: Array[Dictionary] = []
	for chunks: int in [1, 120]:
		assert(npc.place(Vector2i(30, 30), true))
		assert(npc.issue_command(TerrainTestNPC.Command.MOVE_TO_CELL, Vector2i(34, 30)))
		for part in range(chunks):
			lab._advance_combat(1.0 / chunks)
		results.append(npc.capture_state())
	assert(results[0].cell == results[1].cell and results[0].navigation == results[1].navigation)
	assert(Vector2(results[0].position[0], results[0].position[1]).distance_to(Vector2(results[1].position[0], results[1].position[1])) < 0.001)
	lab.free()
	for actor: TerrainTestCharacter in actors:
		actor.queue_free()
	await process_frame
	print("SITE ACTOR MOVEMENT PASS: original player/NPC four directions walk/run; shared action clock, pause, curved save continuation, legacy remainder, KO/death step and slow-frame navigation")
	quit(0)
