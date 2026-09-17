extends SceneTree
## Native column counts must match the former loops without touching owners.
class CustomArmy extends TerrainArmy:
	var predicate_calls := 0
	func _unit_has_cleared_passages(_index: int) -> bool:
		predicate_calls += 1
		return true

func _initialize() -> void:
	_run.call_deferred()

func _snapshot(army: TerrainArmy) -> PackedByteArray:
	return var_to_bytes([army.roster_size, army.movement_state, army._unit_passage_phase,
		army._unit_passage_exit_clear, army._unit_completed_exits, army._unit_passage,
		army._passage_descriptors, army.command_rng.state])

func _run() -> void:
	var script := load("res://scripts/terrain_lab/terrain_army.gd") as GDScript
	var old := FileAccess.get_file_as_string("res://scripts/tests/fixtures/terrain_army_counts_original.gd.txt")
	script.source_code += "\n" + old.replace("func moving_count(", "func _reference_moving_count(").replace("func passage_summary(", "func _reference_passage_summary(")
	assert(script.reload(true) == OK)
	var army := TerrainArmy.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 9162026
	var cases := 0
	for size in [0, 1, 2, 99, 200, 2500, 5000]:
		army.movement_state.resize(size)
		army._unit_passage_phase.resize(size)
		army._unit_passage_exit_clear.resize(size)
		army._unit_completed_exits.resize(size)
		army._unit_passage.resize(size)
		for trial in range(40):
			army.roster_size = size if trial % 3 != 0 else size + 1
			army._passage_descriptors.assign([] if trial % 2 == 0 else [{}, {}])
			for index in size:
				army.movement_state[index] = rng.randi_range(0, 255)
				army._unit_passage_phase[index] = TerrainArmy.PassagePhase.NONE if trial % 4 == 0 else rng.randi_range(0, 7)
				army._unit_passage_exit_clear[index] = rng.randi_range(0, 1)
				army._unit_completed_exits[index] = rng.randi_range(0, 2)
				army._unit_passage[index] = rng.randi_range(-1, 2)
			var before := _snapshot(army)
			assert(army.moving_count() == army.call("_reference_moving_count"))
			assert(army.passage_summary() == army.call("_reference_passage_summary"))
			assert(before == _snapshot(army), "Counts must not mutate owner state")
			cases += 1
	# Every byte value, including unknown values, and a captain-only passage.
	army.movement_state.resize(256)
	for index in 256: army.movement_state[index] = index
	assert(army.moving_count() == 2)
	army._unit_passage_phase = PackedByteArray([TerrainArmy.PassagePhase.IN_PASSAGE])
	assert(army.passage_summary() == {"waiting": 0, "clearing": 0, "completed": 0})
	var custom := CustomArmy.new()
	custom._unit_passage_phase.resize(9)
	custom._unit_passage_phase.fill(TerrainArmy.PassagePhase.NONE)
	assert(custom.passage_summary() == {"waiting": 0, "clearing": 0, "completed": 8})
	assert(custom.predicate_calls == 8, "Subclass completion callbacks must still run")
	custom.free()
	army.roster_size = 2500
	army.movement_state.resize(2500)
	army.movement_state.fill(TerrainArmy.UnitState.MOVING)
	army._unit_passage_phase.resize(2500)
	army._unit_passage_phase.fill(TerrainArmy.PassagePhase.NONE)
	var timings := []
	for round_index in 6:
		var record := {}
		for reference in ([true, false] if round_index % 2 == 0 else [false, true]):
			var started := Time.get_ticks_usec()
			var total := 0
			for iteration in 1000:
				if reference:
					total += int(army.call("_reference_moving_count"))
					assert(army.call("_reference_passage_summary").completed == 0)
				else:
					total += army.moving_count()
					assert(army.passage_summary().completed == 0)
			assert(total == 2500000)
			record["reference_usec" if reference else "candidate_usec"] = Time.get_ticks_usec() - started
		timings.append(record)
	var path := "res://output/site_army_cache_spikes_20260916/counts.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases": cases + 3, "exact": true, "timings": timings,
		"note": "Headless local count cost only; NOT whole-scene FPS"}, "\t"))
	file.close()
	print("ARMY_COUNTS_PASS exact_cases=", cases + 3, " timings=", timings)
	army.free()
	quit(0)
