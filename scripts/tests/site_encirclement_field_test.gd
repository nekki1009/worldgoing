extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _reference(data: TerrainData, enemies: Array, near: PackedByteArray, occupied: Dictionary, limit: int, reach: int) -> Dictionary:
	var distance := {}
	var pending: Array[Vector2i] = []
	for i in range(enemies.size()):
		if near[i] == 0: continue
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var goal: Vector2i = enemies[i] + direction
			if distance.has(goal) or pending.size() >= limit or occupied.has(goal) or not data.can_attack_across(goal, enemies[i]): continue
			distance[goal] = 0
			pending.append(goal)
	var head := 0
	while head < pending.size():
		var cell := pending[head]
		head += 1
		if int(distance[cell]) >= reach - 1: continue
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var next := cell + direction
			if distance.has(next) or pending.size() >= limit or not data.can_step(next, cell) or occupied.has(next): continue
			distance[next] = int(distance[cell]) + 1
			pending.append(next)
	return distance

func _run() -> void:
	var kernel := TerrainArmy._get_idle_kernel()
	assert(kernel != null and kernel.has_method("encirclement_field"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 520495
	for trial in range(160):
		var data := TerrainData.new()
		data.allocate(Vector2i(100, 100) if trial < 16 else Vector2i(21, 23))
		data.static_blocked.resize(data.flags.size())
		var occupied := {}
		for i in range(data.flags.size()):
			data.flags[i] = 1 if trial < 16 or rng.randf() > .1 else 0
			data.height_levels[i] = 0 if trial < 16 else rng.randi_range(0, 2)
			data.ramp_edges[i] = rng.randi_range(0, 15)
			data.static_blocked[i] = int(trial >= 16 and rng.randf() < .05)
			if rng.randf() < .05: occupied[data.cell_from_index(i)] = false # Presence, not value.
		var enemies: Array = []
		var near := PackedByteArray()
		for i in range(60):
			enemies.append(Vector2i(rng.randi_range(-1, data.size.x), rng.randi_range(-1, data.size.y)))
			near.append(int(rng.randf() > .2))
		var limit: int = [1, 2, 16, 1024][trial % 4]
		var reach: int = [1, 2, 8, 32][(trial / 4) as int % 4]
		var args := [enemies, near, data.size, data.flags, data.height_levels, data.ramp_edges, data.static_blocked, occupied, limit, reach]
		var original := var_to_bytes(args)
		var result: Array = kernel.callv("encirclement_field", args)
		assert(result.size() == 1 and var_to_bytes(result[0]) == var_to_bytes(_reference(data, enemies, near, occupied, limit, reach)), "Field/order changed trial=" + str(trial))
		assert(var_to_bytes(args) == original)
		var retained := var_to_bytes(result)
		data.flags.fill(0)
		kernel.callv("encirclement_field", args)
		assert(var_to_bytes(result) == retained)
	var base := [[], PackedByteArray(), Vector2i.ONE, PackedByteArray([1]), PackedByteArray([0]), PackedByteArray([0]), PackedByteArray(), {}, 1024, 32]
	assert(kernel.callv("encirclement_field", base) == [{}])
	for invalid in range(9):
		var args: Array = base.duplicate(true)
		match invalid:
			0: args[0] = [Vector2i.ZERO]
			1: args[1] = PackedByteArray([1])
			2: args[2] = Vector2i(101, 100)
			3: args[3] = PackedByteArray()
			4: args[4] = PackedByteArray()
			5: args[5] = PackedByteArray()
			6: args[6] = PackedByteArray([0, 0])
			7: args[8] = 1025
			8: args[9] = 33
		assert(kernel.callv("encirclement_field", args).is_empty())
	print("ENCIRCLEMENT_FIELD_PASS exact=160 rejected=9 seeded terrain/ramps/obstacles/limits/order/input/COW")
	quit(0)
