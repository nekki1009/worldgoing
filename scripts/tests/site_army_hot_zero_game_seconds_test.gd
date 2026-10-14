extends "res://scripts/tests/site_army_scale_rules_test.gd"
## prepare_combat(delta, 0.0) ("no game time"): the native hot owner admits the call,
## KO timers do not count down, nobody wakes, and the hot owner's rows equal the GD owner's.

const FIELDS: Array[StringName] = [&"hp", &"ko", &"age", &"think", &"stun", &"grace", &"pose", &"attack"]

func _world(native: bool) -> TerrainLab:
	var lab := _fixture(false, 8)
	for team: TerrainArmy in lab.combat_armies:
		team.combat_order = TerrainArmy.CombatOrder.HOLD
		team.combat_attacking = false
		team.combat_hot_diagnostics_enabled = true
		team.native_hot_enabled = native
		if native:
			var installed := team._try_install_combat_hot_store()
			assert(installed and team.combat_hot_active(), "Native hot store must install")
	var holding: TerrainArmy = lab.combat_armies[0]
	# A long KO and a KO shorter than one action step: neither may change or wake
	# when no game time passes.
	for entry: Array in [[1, 5.0], [2, 0.01]]:
		holding.combat_hot_set(int(entry[0]), &"ko", float(entry[1]))
		holding.combat_hot_set(int(entry[0]), &"pose", "unconscious")
	return lab

func _rows(lab: TerrainLab) -> Array:
	var rows := []
	for team: TerrainArmy in lab.combat_armies:
		for index in range(team.combat_units.size()):
			var row := []
			for field: StringName in FIELDS: row.append(team.combat_hot_get(index, field))
			rows.append(row)
	return rows

func _run() -> void:
	var gd := _world(false)
	var hot := _world(true)
	for step in range(6):
		for lab: TerrainLab in [gd, hot]:
			for team: TerrainArmy in lab.combat_armies:
				team.prepare_combat(1.0 / 30.0, 0.0)
		assert(str(_rows(gd)) == str(_rows(hot)), "Hot and GD owners differ after zero-game-second step %d" % step)
	for lab: TerrainLab in [gd, hot]:
		var holding: TerrainArmy = lab.combat_armies[0]
		assert(float(holding.combat_hot_get(1, &"ko")) == 5.0 and float(holding.combat_hot_get(2, &"ko")) == 0.01,
			"Zero game seconds must not count KO down")
		assert(str(holding.combat_hot_get(1, &"pose")) == "unconscious" and str(holding.combat_hot_get(2, &"pose")) == "unconscious",
			"Zero game seconds must not wake anyone")
	var native_rows := 0
	for team: TerrainArmy in hot.combat_armies:
		native_rows += team._combat_hot_native_rows
		assert(not team._combat_hot_owner_reasons.has("input_invalid"), "Native hot owner must admit game_seconds == 0: " + str(team._combat_hot_owner_reasons))
	assert(native_rows > 0, "Native hot owner must process rows when game_seconds == 0")
	print("ARMY_HOT_ZERO_GAME_SECONDS_PASS native_rows=", native_rows)
	_dispose(gd)
	_dispose(hot)
	# Headless skips the production release at tree exit; free the static contact rigs
	# before the first draw (as round 62).
	TerrainArmy.release_contact_source()
	quit(0)
