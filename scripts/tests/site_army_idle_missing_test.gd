extends "res://scripts/tests/site_army_scale_rules_test.gd"
const Phase6 = preload("res://scripts/tests/fixtures/terrain_army_prepare_phase6.gd")
const LabPhase6 = preload("res://scripts/tests/fixtures/terrain_lab_fatigue_phase6.gd")

func _run() -> void:
	# Exercise the production missing-file branch in this process only. Never
	# rename/delete a DLL that another game/editor may currently have loaded.
	var army_script := load("res://scripts/terrain_lab/terrain_army.gd") as GDScript
	var binary := "res://native/army_idle/bin/army_idle.windows.x86_64.dll"
	var absent := "res://.godot-temp/army-idle-intentionally-absent.dll"
	assert(not FileAccess.file_exists(absent) and army_script.source_code.count(binary) == 1)
	army_script.source_code = army_script.source_code.replace(binary, absent)
	assert(army_script.reload(true) == OK)
	assert(TerrainArmy._get_idle_kernel() == null)
	var before := _fixture(false, 100, true, Phase6, LabPhase6)
	var after := _fixture(false, 100, true)
	for step in range(60):
		for lab: TerrainLab in [before, after]:
			for army: TerrainArmy in lab.combat_armies: army.combat_order = TerrainArmy.CombatOrder.ATTACK
			lab._advance_combat(1.0 / 30.0)
		assert(var_to_bytes(_state(before)) == var_to_bytes(_state(after)))
	for team: TerrainArmy in after.combat_armies:
		assert(team.native_idle_enabled and team.native_idle_rows == 0 and team.native_fatigue_rows == 0)
		assert(team.native_queries_enabled and team.native_query_rows == 0)
		assert(team.native_front_enabled and team.native_front_cells == 0)
		assert(team.native_presence_enabled and team.native_presence_rows == 0)
		assert(team.native_recovery_enabled and team.native_recovery_rows == 0)
	_dispose(before); _dispose(after)
	print("ARMY_NATIVE_MISSING_FILE_PASS production file-exists branch, in-memory path only, exact 200 people/60 steps fallback")
	quit(0)
