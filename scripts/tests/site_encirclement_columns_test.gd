extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _reference(xs: PackedInt32Array, ys: PackedInt32Array, factions: PackedInt64Array, owners: PackedInt32Array, owner: int, faction: int) -> Array:
	var enemies := {}
	for i in range(xs.size()):
		if factions[i] != faction: enemies[Vector2i(xs[i], ys[i])] = true
	var front := PackedInt32Array()
	for i in range(xs.size()):
		if owners[i] != owner: continue
		for direction: Vector2i in TerrainData.DIRECTIONS:
			if enemies.has(Vector2i(xs[i], ys[i]) + direction):
				front.append(i)
				break
	return [enemies, front]

func _run() -> void:
	var kernel := TerrainArmy._get_idle_kernel()
	assert(kernel != null and kernel.has_method("encirclement_front"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 81487
	var cases := 0
	for count in [0, 1, 200, 5000, 10000]:
		for trial in range(12):
			var xs := PackedInt32Array()
			var ys := PackedInt32Array()
			var factions := PackedInt64Array()
			var owners := PackedInt32Array()
			for i in range(count):
				xs.append(rng.randi_range(-50, 50))
				ys.append(rng.randi_range(-50, 50))
				var owner := rng.randi_range(0, 3)
				owners.append(owner)
				# Same-cell mixed factions, same-faction different owners, 64-bit IDs.
				factions.append(9223372036854775700 if owner < 2 else -9007199254740993)
			var args := [xs, ys, factions, owners, trial % 4, 9223372036854775700 if trial % 4 < 2 else -9007199254740993]
			var original := var_to_bytes(args)
			var reference: Array = _reference.callv(args)
			var actual: Array = kernel.callv("encirclement_front", args)
			assert(var_to_bytes(actual) == var_to_bytes(reference), "Changed enemy key order or candidate ordinal")
			assert(var_to_bytes(args) == original, "Mutated input columns")
			var retained := var_to_bytes(actual)
			if count > 0:
				args[0][0] += 100
				kernel.callv("encirclement_front", args)
				assert(var_to_bytes(actual) == retained, "Later call mutated retained output")
			cases += 1
	var valid := [PackedInt32Array([-10000, -9999, 10000, 9999]), PackedInt32Array([0, 0, 1, 1]), PackedInt64Array([1, 2, 1, 2]), PackedInt32Array([0, 1, 0, 1]), 0, 1]
	assert(var_to_bytes(kernel.callv("encirclement_front", valid)) == var_to_bytes(_reference.callv(valid)))
	for invalid in range(7):
		var args: Array = valid.duplicate(true)
		match invalid:
			0: args[0][0] = 2147483647
			1: args[1][0] = -2147483648
			2: args[2] = PackedInt64Array()
			3: args[3][0] = -1
			4: args[4] = -1
			5: args[2][0] = 2
			6: args[0].resize(10001)
		var original := var_to_bytes(args)
		assert(kernel.callv("encirclement_front", args).is_empty())
		assert(var_to_bytes(args) == original)
	print("ENCIRCLEMENT_COLUMNS_PASS cases=", cases + 1, " rejected=7 exact key/ordinal/int64, input/COW preservation")
	quit(0)
