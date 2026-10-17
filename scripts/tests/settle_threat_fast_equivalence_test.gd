extends "res://scripts/tests/site_workflow_test.gd"
## KO94P equivalence: the no-ship gate in the exchange threat tables (TerrainLab._exchange_rest_threat, SETTLE_THREAT_FAST).
## Same fixture and per-row traces as the KO94L test, plus _exchange_rest_threat answers on a grid of cells for both factions.
## The gate is only the settle_threat_fast_test_enabled toggle; the ship-lookup toggle stays on.
## Builds on the KO94L fixture: no-ship fast path for ship crew and embarked lookups (TerrainLab._site_has_ship_records)
## must not change any row state or any per-row ship boolean. Two fresh, identical 20-person knockout fixtures
## with NO ship record run the same exchange quanta with the private toggle off (original per-row lookups) and on.
## Per quantum and per row the test records the original _ship_crew_work and _ship_embarked answers (called from
## the test itself, identically in both runs), plus fatigue, rest, KO, pose, hp and movement, then compares the
## trace bytes and the final site bytes. A ship-present fixture is NOT built here: with any ship record the fast
## path returns true and the unchanged per-row code runs, which the test checks directly.
## On a mismatch the test prints the first differing quantum, row and field.

const STEP := 1.0 / 30.0 # One exchange action quantum per lab._process call, the same constant the lab uses.
const QUANTA := 600 # 20 s of action time.
const PER_TEAM := 10
const FATIGUE_START := 40.0
const FIELDS := ["fatigue", "fatigue_rest", "ko", "pose", "hp", "moving_to", "ship_crew_work", "ship_embarked"]

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 150000
	_run.call_deferred()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() > deadline:
		push_error("SETTLE_THREAT_FAST_EQUIVALENCE deadline")
		quit(1)
	return false

func _run() -> void:
	var off: Dictionary = _simulate(false)
	var on: Dictionary = _simulate(true)
	assert(bool(off.ship_present) == false and bool(on.ship_present) == false, "This fixture must contain no ship record")
	assert(str(off.threat_answers) == str(on.threat_answers), "Exchange threat answers differ with the no-ship gate on")
	print("KO94P_THREAT_ANSWERS count=", off.threat_answers.size(), " true=", str(off.threat_answers).count("true"))
	var difference: String = _first_difference(off.trace, on.trace)
	if difference != "":
		print("SETTLE_THREAT_FAST_EQUIVALENCE_FIRST_DIFFERENCE ", difference)
	assert(difference == "", "Per-row state or ship booleans differ with the fast path on: " + difference)
	if off.site_bytes != on.site_bytes:
		print("SETTLE_THREAT_FAST_EQUIVALENCE_SITE_BYTES off=%d on=%d" % [off.site_bytes.size(), on.site_bytes.size()])
	assert(off.site_bytes == on.site_bytes, "Site save bytes differ with the fast path on")
	print("SETTLE_THREAT_FAST_EQUIVALENCE_PASS ", JSON.stringify({"quanta": QUANTA, "rows": PER_TEAM * 2}))
	quit(0)

## Returns "" when the traces are identical; otherwise names the first quantum, row and field that differ.
func _first_difference(a: Array, b: Array) -> String:
	if a.size() != b.size():
		return "trace length off=%d on=%d" % [a.size(), b.size()]
	for quantum in range(a.size()):
		var rows_a: Array = a[quantum]
		var rows_b: Array = b[quantum]
		for row in range(rows_a.size()):
			var fields_a: Array = rows_a[row]
			var fields_b: Array = rows_b[row]
			for field in range(FIELDS.size()):
				if str(fields_a[field]) != str(fields_b[field]) or typeof(fields_a[field]) != typeof(fields_b[field]):
					return "quantum %d row %d field %s: off=%s on=%s" % [quantum, row, FIELDS[field], str(fields_a[field]), str(fields_b[field])]
	return ""

func _simulate(fast_enabled: bool) -> Dictionary:
	var data := _fixture()
	for y in range(34, 48):
		for x in range(35, 57):
			var cell := Vector2i(x, y)
			var index := data.index(cell)
			data.flags[index] = TerrainData.Flag.WALKABLE
			data.height_levels[index] = 0
			data.ramp_edges[index] = 0
			for key: String in data.resources_at.get(index, []):
				Env.change(data, key, {"cleared": true, "remaining": 0})
	Env.rebuild_indexes(data)
	Runtime.rebuild_terrain_edges(data)
	var lab := TerrainLab.new()
	lab.npc = TerrainTestNPC.new() # Explicit second original Actor before Lab ready, as in the 094G loot test.
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.npc_retaliates = false
	lab.bind_terrain(data)
	var controller: SiteController = lab.site_controller
	controller.release_worker()
	controller._auto_save_blocked = true
	assert(lab.combat_actors.size() == 2 and lab.combat_armies.size() >= 2)
	var teams: Array[TerrainArmy] = [lab.army, lab.opposing_army]
	for which in range(2):
		var team: TerrainArmy = teams[which]
		# deploy_at requires selected.size() == roster_size; the default roster is SOLDIER_COUNT, so set it first.
		team.roster_size = PER_TEAM
		var cells: Array[Vector2i] = []
		for index in range(PER_TEAM):
			cells.append(Vector2i(35 + which * 11 + index, 35))
		var deployed: bool = team.deploy_at(data, lab.character, lab.npc, cells)
		assert(deployed, "deploy_at refused team %d with %d cells" % [which, cells.size()])
		var enabled: bool = team.enable_combat(false)
		assert(enabled, "enable_combat refused team %d" % which)
		assert(team.combat_units.size() == PER_TEAM)
		team.enemy_query = Callable() # Isolated natural wake: no fresh attacks or AI rescues.
		team.set_process(false)
		var actor: TerrainTestCharacter = lab.character if which == 0 else lab.npc
		actor.set_process(false)
		var placed: bool = actor.place(team.cells[1] + Vector2i.UP, true)
		assert(placed, "actor placement refused for team %d" % which)
	for team: TerrainArmy in teams:
		for index in range(PER_TEAM):
			team.apply_unit_contact(index, {"result": {"hp": 0.0, "stun": 100.0, "guard_break": false}, "shield": false})
			team.combat_units[index].fatigue = FATIGUE_START + float(index)
	lab.settle_threat_fast_test_enabled = fast_enabled
	var ship_present: bool = false
	for vehicle: Variant in controller.vehicles.records().values():
		if SiteVehicleTransport.is_ship(vehicle):
			ship_present = true
	var fast_gate_open: bool = not lab._site_has_ship_records()
	var trace: Array = []
	for quantum in range(QUANTA):
		lab._process(STEP)
		var rows: Array = []
		for team: TerrainArmy in teams:
			for index in range(PER_TEAM):
				var unit: Dictionary = team.combat_units[index]
				var identity: int = team.combat_identity(index)
				# Pooled rows keep fatigue in the shared pool, so read through PersonFatigue (pool first, row second).
				rows.append([PersonFatigue.read(unit, "fatigue"), PersonFatigue.read(unit, "fatigue_rest"), float(team.combat_hot_get(index, &"ko")),
					str(team.combat_hot_get(index, &"pose")), float(team.combat_hot_get(index, &"hp")), team.moving_to[index],
					lab._ship_crew_work(identity), lab._ship_embarked(identity)])
		trace.append(rows)
	var threat_answers: Array = []
	for team: TerrainArmy in teams:
		for index in range(0, PER_TEAM, 2):
			var centre: Vector2i = team.cells[index]
			for dx in range(-2, 3):
				for dy in range(-2, 3):
					var probe := centre + Vector2i(dx, dy)
					for faction: int in [teams[0].faction_id, teams[1].faction_id]:
						var answer: bool = lab._exchange_rest_threat(probe, faction, {})
						threat_answers.append(answer)
	var result := {"trace": trace, "site_bytes": var_to_bytes(data.site), "ship_present": ship_present,
		"fast_gate_open": fast_gate_open, "threat_answers": threat_answers}
	lab.free()
	TerrainArmy.release_contact_source()
	return result
