extends SceneTree
const Batch = preload("res://scripts/terrain_lab/terrain_army_batch_view.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var kernel := TerrainArmy._get_idle_kernel()
	assert(kernel != null and kernel.has_method("pack_instances"))
	var batch := Batch.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 58429
	var checked := 0
	for count in [1, 2, 100, 2500, 10000]:
		batch._positions.resize(count)
		batch._sequence.resize(count)
		batch._frames.resize(count)
		batch._palette.resize(count)
		var members: Array = []
		for i in range(count):
			batch._positions[i] = Vector2(rng.randf_range(-6543, 8654), rng.randf_range(-192, 7240))
			batch._sequence[i] = rng.randi_range(0, 128)
			batch._frames[i] = rng.randi_range(0, 63)
			batch._palette[i] = rng.randi_range(0, 10000)
			members.append(count - i - 1)
		var before := var_to_bytes([members, batch._positions, batch._sequence, batch._frames, batch._palette])
		for scale in [0.125, 0.731, 1.0, -1.25]:
			for start in [0, count - 1]:
				var reference := batch._pack_run_gd(members, start, count, scale)
				var actual := batch._pack_run(members, start, count, scale)
				assert(var_to_bytes(actual) == var_to_bytes(reference), "Buffer/bounds changed: %s/%s" % [count, start])
				assert(before == var_to_bytes([members, batch._positions, batch._sequence, batch._frames, batch._palette]))
				checked += 1
		assert(batch.native_buffer_instances > 0)
	assert(kernel.pack_instances([], 0, 0, PackedVector2Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), 1.0).is_empty())
	for bad_members: Array in [[-1], [10000], [0.5], [null]]:
		assert(kernel.pack_instances(bad_members, 0, 1, batch._positions, batch._sequence, batch._frames, batch._palette, 1.0).is_empty())
	assert(kernel.pack_instances([0], 0, 1, batch._positions, PackedInt32Array(), batch._frames, batch._palette, 1.0).is_empty())
	assert(kernel.pack_instances([0], 0, 1, batch._positions, batch._sequence, batch._frames, batch._palette, INF).is_empty())
	batch._positions[0] = Vector2(NAN, 0)
	assert(kernel.pack_instances([0], 0, 1, batch._positions, batch._sequence, batch._frames, batch._palette, 1.0).is_empty())
	batch.free()
	print("ARMY_BUFFER_PACK_PASS exact bytes and repeated Rect2 bounds: ", checked, " cases, 1..10000 columns, invalid input rejection; original columns unchanged")
	quit(0)
