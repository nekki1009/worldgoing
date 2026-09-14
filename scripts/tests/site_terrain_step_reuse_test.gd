extends SceneTree
## Original can_step short-circuit versus reusing its existing terrain guard.
## Pure original TerrainData/Generator, no replacement graph or gameplay clock.

func _initialize() -> void:
	run.call_deferred()

func _original(data: TerrainData, from: Vector2i, to: Vector2i) -> bool:
	if not data.is_walkable(from) or not data.is_walkable(to):
		return false
	return data.can_terrain_step(from, to)

func run() -> void:
	var deadline := Time.get_ticks_usec() + 17000000
	var data := TerrainGenerator.generate(0, 581, {"size": Vector2i(48, 48)})
	var checks := 0
	var directions := TerrainData.DIRECTIONS.duplicate()
	directions.append_array([Vector2i.ZERO, Vector2i.ONE, Vector2i(2, 0), Vector2i(-2, 0)])
	for mode in range(3):
		data.static_blocked = PackedByteArray()
		if mode > 0:
			data.static_blocked.resize(data.size.x * data.size.y)
			for index in range(data.static_blocked.size()):
				data.static_blocked[index] = int(mode == 2 and index % 7 == 0)
		for y in range(-1, data.size.y + 1):
			for x in range(-1, data.size.x + 1):
				var from := Vector2i(x, y)
				for direction: Vector2i in directions:
					var to := from + direction
					assert(data.can_step(from, to) == _original(data, from, to), "Original bounds/flags/cliffs/ramps/static obstacles must agree")
					checks += 1
		assert(Time.get_ticks_usec() < deadline)
	# Explicit reciprocal ramp/nonwalkable/blocked combinations at real cells.
	var a := Vector2i(20, 20)
	var b := a + Vector2i.RIGHT
	for flags_a in [0, TerrainData.Flag.WALKABLE]:
		for flags_b in [0, TerrainData.Flag.WALKABLE]:
			data.flags[data.index(a)] = flags_a
			data.flags[data.index(b)] = flags_b
			for delta in range(3):
				data.height_levels[data.index(a)] = delta
				data.height_levels[data.index(b)] = 0
				for ramp_a in [0, 2]:
					for ramp_b in [0, 8]:
						data.ramp_edges[data.index(a)] = ramp_a
						data.ramp_edges[data.index(b)] = ramp_b
						for blocked in range(4):
							data.static_blocked[data.index(a)] = blocked & 1
							data.static_blocked[data.index(b)] = (blocked >> 1) & 1
							assert(data.can_step(a, b) == _original(data, a, b) and data.can_step(b, a) == _original(data, b, a))
							checks += 2
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.height_levels.fill(0)
	data.static_blocked.fill(0)
	var old_usec := 0
	var new_usec := 0
	for repeat in range(3):
		var started := Time.get_ticks_usec()
		for index in range(100000):
			assert(_original(data, a, b))
		old_usec += Time.get_ticks_usec() - started
		started = Time.get_ticks_usec()
		for index in range(100000):
			assert(data.can_step(a, b))
		new_usec += Time.get_ticks_usec() - started
		assert(Time.get_ticks_usec() < deadline)
	print("SITE TERRAIN STEP REUSE PASS: checks=", checks, " original_usec=", old_usec, " reused_usec=", new_usec, "; local 300000 open-edge calls only, not FPS")
	quit(0)
