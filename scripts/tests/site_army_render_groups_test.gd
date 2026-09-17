extends SceneTree
## Presentation-only order contract; actual main scene is used for FPS.
const Batch = preload("res://scripts/terrain_lab/terrain_army_batch_view.gd")
var kernel: RefCounted
var cases := 0
var rejected := 0

func _initialize() -> void:
	_run.call_deferred()

func _reference(args: Array) -> Array:
	var rows := {}
	var by_index := {}
	for r in range(args[2].size()):
		for index: int in args[3][r]: by_index[index] = args[2][r]
	var prepared := 0
	for index in range(args[0].size()):
		var row: int
		if args[0][index] == 1:
			row = args[1][index]
			prepared += 1
		elif by_index.has(index): row = by_index[index]
		else: continue
		if not rows.has(row): rows[row] = []
		rows[row].append(index)
	var spans := PackedInt32Array()
	for row: int in rows:
		var members: Array = rows[row]
		members.sort()
		var start := 0
		var run := 0
		while start < members.size():
			var page: int = args[4][members[start]]
			var stop := start + 1
			if page >= 0:
				while stop < members.size() and args[4][members[stop]] == page: stop += 1
			spans.append_array(PackedInt32Array([row, run, start, stop, page]))
			start = stop
			run += 1
	return [rows, spans, prepared]

func _accept(args: Array) -> void:
	var before := var_to_bytes(args)
	var expected := _reference(args)
	var actual: Array = kernel.callv("group_render_rows", args)
	assert(var_to_bytes(actual) == var_to_bytes(expected), "Native row/key/run order differs")
	assert(var_to_bytes(args) == before, "Input mutated")
	var retained := var_to_bytes(actual)
	assert(kernel.callv("group_render_rows", args) == actual)
	assert(var_to_bytes(actual) == retained, "Retained packet changed")
	var batch := Batch.new()
	batch._native_mask = args[0]
	batch._native_rows = args[1]
	batch._page = args[4]
	var fallback := {}
	var fallback_rendered := 0
	for r in range(args[2].size()):
		fallback[args[2][r]] = args[3][r].duplicate()
		for index: int in args[3][r]: fallback_rendered += int(args[4][index] >= 0)
	batch._rows = fallback.duplicate(true)
	batch.rendered_count = fallback_rendered
	var exceptions := PackedInt32Array()
	for index in range(args[0].size()):
		if args[0][index] == 0: exceptions.append(index)
	assert(batch.prepared_exceptions() == exceptions)
	assert(batch.can_group_prepared() == (not args[0].is_empty()))
	batch.finish_prepared_groups()
	assert(batch._groups_ready and batch.native_grouped_count == expected[2])
	assert(var_to_bytes(batch._rows) == var_to_bytes(expected[0]) and batch._group_spans == expected[1])
	assert(batch.rendered_count == fallback_rendered + expected[2])
	# Missing/disabled native grouping rebuilds original order without callbacks.
	batch.begin()
	batch.native_grouping_enabled = false
	batch._native_mask = args[0]
	batch._rows = fallback.duplicate(true)
	batch.rendered_count = fallback_rendered
	batch.finish_prepared_groups()
	assert(not batch._groups_ready and batch.native_grouped_count == 0)
	assert(var_to_bytes(batch._rows) == var_to_bytes(expected[0]))
	assert(batch.native_prepared_count == expected[2] and batch.rendered_count == fallback_rendered + expected[2])
	assert(var_to_bytes(args) == before)
	batch.free()
	cases += 1

func _reject(args: Array) -> void:
	var before := var_to_bytes(args)
	assert(kernel.callv("group_render_rows", args).is_empty(), "Malformed grouping input accepted")
	assert(var_to_bytes(args) == before)
	rejected += 1

func _run() -> void:
	create_timer(35.0).timeout.connect(func() -> void: push_error("Grouping test deadline"); quit(1))
	kernel = TerrainArmy._get_idle_kernel()
	assert(kernel != null and kernel.has_method("group_render_rows"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 581
	for count: int in [0, 1, 2, 200, 2500, 10000]:
		for mode in range(4):
			for repeat in range(3):
				var mask := PackedByteArray()
				var rows := PackedInt32Array()
				var pages := PackedInt32Array()
				var fallback := {}
				mask.resize(count); rows.resize(count); pages.resize(count)
				for index in range(count):
					mask[index] = 1 if mode == 0 else (0 if mode == 1 else int(rng.randi_range(0, 3) > 0))
					rows[index] = [-2147483648, 2147483647, -1, 22, 48][index % 5] if repeat == 0 else rng.randi_range(-100, 100)
					pages[index] = 0 if repeat == 1 else rng.randi_range(0, 2)
					if mask[index] == 0:
						if mode == 3 and index % 2 == 0: continue # Rejected draw is absent.
						if index % 3 == 0: pages[index] = -1
						if not fallback.has(rows[index]): fallback[rows[index]] = []
						fallback[rows[index]].append(index)
				# Exception insertion is deliberately reversed; original ordinal wins.
				var keys := fallback.keys()
				keys.reverse()
				var members := []
				for row: int in keys:
					fallback[row].reverse()
					fallback[row].make_read_only()
					members.append(fallback[row])
				keys.make_read_only()
				members.make_read_only()
				_accept([mask, rows, keys, members, pages])
	# Each malformed case is independent and must fail atomically.
	var valid := [PackedByteArray([1, 0, 0]), PackedInt32Array([22, 23, 24]), [22], [[1, 2]], PackedInt32Array([0, -1, 1])]
	_accept(valid)
	for mutation in range(19):
		var args := valid.duplicate(true)
		match mutation:
			0: args[0] = PackedByteArray([1])
			1: args[1] = PackedInt32Array()
			2: args[4] = PackedInt32Array()
			3: args[3] = []
			4: args[0][1] = 2
			5: args[2][0] = 22.0
			6: args[2][0] = 2147483648
			7: args[2][0] = -2147483649
			8: args[3][0] = null
			9: args[3][0][0] = -1
			10: args[3][0][0] = 3
			11: args[3][0][0] = 1.0
			12: args[3][0][0] = null
			13: args[3][0][0] = 0 # Overlaps prepared row.
			14: args[3][0] = [1, 1]
			15: args[2] = [22, 22]; args[3] = [[1], [2]]
			16: args[2] = [22, 23]; args[3] = [[1], [1]]
			17: args[4][0] = -1
			18: args[0].resize(10001); args[1].resize(10001); args[4].resize(10001)
		_reject(args)
	var batch := Batch.new()
	batch._native_mask = PackedByteArray([1])
	batch._native_rows = PackedInt32Array([22])
	batch._page = PackedInt32Array([0])
	batch.finish_prepared_groups()
	assert(batch._groups_ready)
	assert(batch.submit_prepared(0) and not batch._groups_ready)
	batch.free()
	print("ARMY_RENDER_GROUPS_PASS cases=", cases, " rejected=", rejected, " exact rows/key order/page runs, Sprite splits, readonly/COW, fallback, invalidation")
	quit(0)
