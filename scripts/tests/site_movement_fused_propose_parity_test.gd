extends "res://scripts/tests/site_movement_batch_parity_test.gd"
## Same-source r2/R1 proposal parity; Grid, physical completion and HotStore are real.

const OUT := "res://output/site_movement_plan_revision3_20260928/implementation/r1/parity.json"

func _fixture(fused: bool) -> Dictionary:
	var world := super._fixture(true)
	for army: TerrainArmy in world.armies:
		army.r3_fused_propose_enabled = fused
	return world

func _check(hot: bool) -> Dictionary:
	var baseline := _fixture(false)
	var candidate := _fixture(true)
	if hot:
		for world: Dictionary in [baseline, candidate]:
			for army: TerrainArmy in world.armies:
				army.native_hot_enabled = true
				assert(army._try_install_combat_hot_store())
	var mismatch := ""
	var failed_step := -1
	var failed_stage := ""
	for step in range(120):
		var blocked := {}
		if step >= 45 and step < 65:
			blocked[baseline.armies[0].cells[0] + Vector2i.RIGHT] = true
		for world: Dictionary in [baseline, candidate]:
			world.coordinator.combat_logic_tick_if_needed(STEP, blocked)
		mismatch = _first_difference(_state(baseline), _state(candidate))
		if not mismatch.is_empty():
			failed_step = step
			failed_stage = "coordinator"
			break
		for world: Dictionary in [baseline, candidate]:
			for army: TerrainArmy in world.armies:
				army.prepare_combat(STEP, STEP)
			world.coordinator.complete_committed_moves()
			for army: TerrainArmy in world.armies:
				army.settle_combat_command()
		mismatch = _first_difference(_state(baseline), _state(candidate))
		if not mismatch.is_empty():
			failed_step = step
			failed_stage = "physical_completion"
			break
	var hits := 0
	var fallbacks := 0
	for army: TerrainArmy in candidate.armies:
		hits += army.r3_fused_propose_hits
		fallbacks += army.r3_fused_propose_fallbacks
	_dispose(baseline)
	_dispose(candidate)
	return {"hot": hot, "passed": failed_step < 0 and hits > 0 and fallbacks == 0,
		"failed_step": failed_step, "failed_stage": failed_stage, "first_difference": mismatch,
		"hits": hits, "fallbacks": fallbacks}

func _run() -> void:
	var kernel: RefCounted = ClassDB.instantiate(&"ArmyIdleKernel")
	assert(kernel != null and kernel.has_method("movement_propose"))
	assert(kernel.movement_propose([]).is_empty())
	var results := [_check(false), _check(true)]
	TerrainArmy.release_contact_source()
	var passed := true
	for row: Dictionary in results:
		passed = passed and bool(row.passed)
	var absolute := ProjectSettings.globalize_path(OUT)
	assert(DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) == OK)
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"status": "PASS" if passed else "FAIL", "cases": results,
		"source": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"),
		"native": FileAccess.get_sha256("res://native/army_idle/movement_core.inc"),
		"dll": FileAccess.get_sha256("res://native/army_idle/bin/army_idle.windows.x86_64.dll")}, "\t"))
	file.close()
	if not passed:
		push_error("R3 FUSED PROPOSE PARITY FAIL: " + str(results))
	print("R3 FUSED PROPOSE PARITY ", "PASS" if passed else "FAIL", " ", OUT)
	quit(0 if passed else 1)
