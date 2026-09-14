extends "res://scripts/tests/site_work_team_clock_test.gd"
## Same original Lab/people, restored through Store for each flag. This is an
## exact common-step regression and scoped counter measurement, not an FPS test.

class ObservedLab extends TerrainLab:
	var after_fatigue := Callable()
	func _advance_fatigue(seconds: float) -> void:
		super._advance_fatigue(seconds)
		if after_fatigue.is_valid():
			after_fatigue.call(seconds)

var _lab: ObservedLab
var _stage := ""
var _samples: Array[Dictionary] = []
var _reference: Array[Dictionary] = []
var _mismatch := ""
var _candidate := false

func _initialize() -> void:
	deadline = Time.get_ticks_msec() + 18000
	_run.call_deferred()

func _bits(value: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, value)
	return bytes.hex_encode()

func _body(body: Variant, identity: int) -> Dictionary:
	return {"id": identity, "fatigue": _bits(float(body.fatigue)),
		"fatigue_type": typeof(body.fatigue), "rest": _bits(float(body.fatigue_rest)),
		"rest_type": typeof(body.fatigue_rest), "hp": float(body.hp)}

func _snapshot() -> Dictionary:
	var actors: Array[Dictionary] = []
	for actor: TerrainTestCharacter in _lab.combat_actors:
		var state := _body(actor, actor.person_id)
		state.merge({"cell": actor.terrain_cell, "moving": actor.is_moving(),
			"ko": actor.knockout_left, "stun": actor.stun,
			"attack": actor.action_time, "guard": actor.guarding,
			"transition": actor.guard_transition_left})
		actors.append(state)
	var team: TerrainArmy = _lab.army
	var rows: Array[Dictionary] = []
	for index: int in team.combat_units.size():
		var row: Dictionary = team.combat_units[index]
		var state := _body(row, team.combat_identity(index))
		state.merge({"cell": team.cells[index], "destination": team.moving_to[index],
			"progress": team.move_progress[index], "ko": row.ko, "stun": row.stun,
			"pose": row.pose, "age": row.age, "attack": row.attack,
			"work": row.get("work_task", {}).duplicate(true), "cargo": row.cargo.duplicate(true),
			"items": row.item_state.duplicate(true), "hit_revision": row.get("hit_revision", 0)})
		rows.append(state)
	var site: Dictionary = _lab.terrain.site
	return {"actors": actors, "rows": rows, "training": team.training,
		"clock": [site.minute, site.phase, site.combat_left],
		"supply": site.get("team_supply", {}).duplicate(true),
		"stock": site.inventory.duplicate(true), "manual": site.manual.duplicate(true),
		"items": site.item_records.duplicate(true)}

func _sample(seconds: float) -> void:
	var sample := {"stage": _stage, "seconds": seconds, "state": _snapshot()}
	if _candidate and _mismatch.is_empty():
		var index := _samples.size()
		if index >= _reference.size() or var_to_bytes(sample) != var_to_bytes(_reference[index]):
			_mismatch = "Exact common-step state differs at %s sample %d" % [_stage, index]
	_samples.append(sample)

func _frame(label: String, delta: float) -> void:
	_stage = label
	_lab._process(delta) # Original controller/120 Hz owner; no replacement clock.

func _exercise() -> Dictionary:
	var team: TerrainArmy = _lab.army
	var actor: TerrainTestCharacter = _lab.character
	var npc: TerrainTestCharacter = _lab.npc
	var controller: SiteController = _lab.site_controller
	var data: TerrainData = _lab.terrain
	var negative_zero := PackedByteArray([0, 0, 0, 0, 0, 0, 0, 128]).decode_double(0)
	assert(_bits(negative_zero) != _bits(0.0), "Construct genuine IEEE negative zero, not a folded literal")
	team.combat_units[0].fatigue = 0 # Legacy integer -> float must still occur.
	team.combat_units[0].fatigue_rest = 29.5
	team.combat_units[1].fatigue = negative_zero
	team.combat_units[1].fatigue_rest = negative_zero
	team.combat_units[2].fatigue = 40.0
	team.combat_units[2].fatigue_rest = 30.0
	actor.fatigue = negative_zero
	actor.fatigue_rest = 12.0
	npc.fatigue = 50.0
	npc.fatigue_rest = 30.0
	_lab.after_fatigue = _sample
	_stage = "zero elapsed keeps original values and types"
	_lab._advance_fatigue(0.0)
	assert(typeof(team.combat_units[0].fatigue) == TYPE_INT)
	var before := var_to_bytes(_snapshot())
	data.site.paused = true
	_frame("Site pause", 0.1)
	data.site.paused = false
	assert(var_to_bytes(_snapshot()) == before, "Pause must freeze all original person and provider state")
	# The optional counters must stay untouched when profiling is disabled.
	_lab.combat_profile_enabled = false
	_frame("unprofiled exact zero and safe positive recovery", 1.0 / 120.0)
	assert(_lab.fatigue_zero_eligible_rows == 0 and _lab.fatigue_zero_skipped_advances == 0)
	assert(typeof(team.combat_units[0].fatigue) == TYPE_FLOAT)
	assert(_bits(float(team.combat_units[1].fatigue)) == _bits(negative_zero))
	assert(_bits(float(team.combat_units[1].fatigue_rest)) == _bits(0.0))
	assert(_bits(actor.fatigue) == _bits(negative_zero), "Actor stays on the original path")
	_lab.combat_profile_enabled = true
	_frame("profiled zero and existing safe-rest recovery", 0.025)
	assert(float(team.combat_units[2].fatigue) < 40.0 and npc.fatigue < 50.0)
	# Real delivered food and qualified original commander; all time handled by
	# training must be removed before this candidate sees an available row.
	for row: Dictionary in team.combat_units:
		row.fatigue = 0.0
		row.fatigue_rest = 12.0
	assert(controller.order_team_training(team, team.current_commander, true).ok)
	var eligible_before := _lab.fatigue_zero_eligible_rows
	var training_before := team.training
	_frame("actual fed training consumes the whole shared interval", 1.0 / 120.0)
	assert(team.training > training_before and _lab.fatigue_zero_eligible_rows == eligible_before)
	var expected_training_fatigue := 0.5 * PersonFatigue.WORK_RATE
	assert(_bits(float(team.combat_units[1].fatigue)) == _bits(expected_training_fatigue), "Exactly one training charge per original half-game-second step")
	assert(float(team.combat_units[1].fatigue_rest) == 0.0)
	assert(controller.order_team_training(team, team.current_commander, false).ok)
	# Reuse the actual generated-resource work fixture and original assignment.
	var worker_id := team.combat_identity(1)
	assert(controller._control_family_person(null, team.combat_identity(team.current_commander)).ok)
	team.combat_units[1].fatigue = 0.0
	team.combat_units[1].fatigue_rest = 12.0
	assert(controller.work_team.assign(team, [worker_id], team.combat_identity(team.current_commander)).ok)
	_frame("original assigned resource work", 1.0 / 60.0)
	var worker: Dictionary = team.combat_units[1]
	assert(worker.work_task.mode == "work" and float(worker.work_task.progress) > 0.0 and float(worker.fatigue) > 0.0)
	assert(float(worker.fatigue_rest) == 0.0, "Work cannot double-rest")
	var progress_before := float(worker.work_task.progress)
	var tools_before := int(data.site.inventory.tools)
	data.site.inventory.tools = 0
	worker.fatigue = negative_zero
	worker.fatigue_rest = 12.0
	# Original Runtime._work rejects missing tools, clears the target, and
	# keeps progress for that first step. On the next step WorkTeam chooses the
	# same real resource again; Runtime.assign_task then resets progress because
	# the prior target was cleared. Do not invent a retained-target wait model.
	_frame("assigned zero-fatigue input rejection is still duty", 1.0 / 120.0)
	print("FATIGUE ZERO BLOCKED FIRST: ", JSON.stringify({"candidate": _candidate,
		"before_progress": progress_before, "task": worker.work_task,
		"fatigue_bits": _bits(float(worker.fatigue)), "rest_bits": _bits(float(worker.fatigue_rest))}))
	assert(float(worker.work_task.progress) == progress_before and worker.work_task.target == "" and worker.work_task.mode == "idle", "Original first missing-tool rejection clears only the target, not progress")
	assert(_bits(float(worker.fatigue)) == _bits(negative_zero) and _bits(float(worker.fatigue_rest)) == _bits(0.0), "No work callback: original unsafe-rest branch preserves incoming negative zero and returns positive-zero rest")
	_frame("original input retry reassigns and resets progress", 1.0 / 120.0)
	assert(float(worker.work_task.progress) == 0.0 and not worker.work_task.is_empty() and worker.work_task.target == "", "Original re-selection resets progress before the next missing-tool rejection")
	assert(_bits(float(worker.fatigue)) == _bits(negative_zero) and _bits(float(worker.fatigue_rest)) == _bits(0.0), "Retry without productive work must keep the same exact fatigue bytes")
	data.site.inventory.tools = tools_before
	assert(controller.work_team.cancel(worker_id).ok)
	# Positive guard effort must not enter the zero branch, even starting at zero.
	worker.fatigue = 0.0
	actor.fatigue = 0.0
	actor.set_guard(true)
	assert(team.set_unit_guard(1, true))
	_frame("original Actor and row guard raise and hold", 0.175)
	assert(actor.fatigue > 0.0 and float(worker.fatigue) > 0.0)
	actor.set_guard(false)
	assert(team.set_unit_guard(1, false))
	_frame("original guard lowering effort", 0.175)
	assert(worker.pose == "idle")
	# The original reservation permits RUN only for the actually controlled
	# person; running=true on another row intentionally remains WALK. The third
	# argument is an escort identity, not duration. Bind the original row first.
	var runner: Dictionary = team.combat_units[2]
	assert(controller._control_family_person(null, team.combat_identity(2)).ok)
	assert(team.is_controlled_person(2) and not team.is_controlled_person(1))
	runner.fatigue = 0.0
	var reserved := false
	for direction: Vector2i in TerrainData.DIRECTIONS:
		if team._reserve_combat_step(2, team.cells[2] + direction, 0, true):
			reserved = true
			break
	assert(reserved, "Original running reservation must find a legal adjacent cell")
	assert(team.move_duration[2] == TerrainArmy.RUN_DURATION and runner.pose == "run" and team.move_progress[2] == 0.0, "The original owner must have reserved a real, not-yet-advanced run")
	_frame("original committed run effort", 1.0 / 120.0)
	assert(float(runner.fatigue) > 0.0 and team.moving_to[2] != TerrainArmy.INVALID_CELL and team.move_progress[2] > 0.0, "The actual running interval incurs effort before its legal destination commit")
	# Attack starts through the real owner. Stop in windup: this test makes no
	# claim about fabricated contact geometry or the later active hit window.
	worker.fatigue = 0.0
	var attacking := false
	for direction: Vector2i in TerrainData.DIRECTIONS:
		if team.start_unit_attack(1, team.cells[1] + direction):
			attacking = true
			break
	assert(attacking)
	_frame("original attack windup effort", 1.0 / 120.0)
	var attack_events: Dictionary = TerrainArmy.CombatTimings.events(team.attack_clip(1))
	var sampled_attack_time: float = TerrainArmy.CombatTimings.sample_time(team.attack_clip(1), float(worker.age), float(worker.attack_reduction), float(worker.attack_fatigue))
	assert(bool(worker.attack) and float(worker.fatigue) > 0.0 and sampled_attack_time < float(attack_events.active_start), "The original positive-rate attack remains in pre-contact windup")
	# Real received-damage entrypoints, explicitly not a geometry accuracy test.
	assert(float(worker.hp) == 100.0 and npc.hp == 100.0, "No attack reached an active collision interval in this fixture")
	var worker_revision := int(worker.get("hit_revision", 0))
	var npc_revision := npc._received_effective_hit
	var hit := {"result": {"hp": 1.0, "stun": SiteCombatRules.STUN_LIMIT, "guard_break": false}, "shield": false}
	team.apply_unit_contact(1, hit)
	npc.apply_contact(hit)
	assert(not bool(worker.attack) and worker.pose == "down" and float(worker.ko) == SiteCombatRules.KNOCKOUT_SECONDS and npc.knockout_left == SiteCombatRules.KNOCKOUT_SECONDS, "The original effective hit starts KO and cancels the row attack")
	assert(int(worker.get("hit_revision", 0)) == worker_revision + 1 and npc._received_effective_hit == npc_revision + 1, "Exactly one real received-impact revision for each original owner")
	worker.fatigue = negative_zero
	worker.fatigue_rest = 12.0
	_frame("actual effective hit and unconscious no-rest", 1.0 / 120.0)
	assert(float(worker.hp) == 99.0 and float(worker.ko) > 0.0 and npc.hp == 99.0 and npc.knockout_left > 0.0)
	assert(_bits(float(worker.fatigue)) == _bits(negative_zero) and _bits(float(worker.fatigue_rest)) == _bits(0.0))
	_lab.after_fatigue = Callable()
	return {"samples": _samples.size(), "eligible_rows": _lab.fatigue_zero_eligible_rows,
		"skipped_advances": _lab.fatigue_zero_skipped_advances,
		"fatigue_people_usec": _lab.combat_profile_usec.get("fatigue_people_inclusive", 0),
		"fatigue_threat_usec": _lab.combat_profile_usec.get("fatigue_threat", 0)}

func _run() -> void:
	# GDScript assertions stop only their own function. Always collect the
	# checked function's result, clean up, and exit now rather than waiting for
	# the inherited 18-second watchdog after an inner fixture assertion.
	var completed: Variant = _run_checked()
	if is_instance_valid(_lab):
		_lab.after_fatigue = Callable()
		_lab.queue_free()
	await process_frame
	TerrainArmy.release_contact_source()
	if completed != true:
		push_error("SITE FATIGUE ZERO FAST FAIL: fixture aborted; stage=" + _stage + "; " + _mismatch)
		quit(1)
		return
	quit(0)

func _run_checked() -> bool:
	_lab = ObservedLab.new()
	_lab.pause_when_unfocused = false
	root.add_child(_lab)
	_lab.set_process(false)
	_lab.character.set_process(false)
	_lab.npc.set_process(false)
	_lab.npc_retaliates = false
	_lab.site_controller._auto_save_blocked = true
	assert(not _lab.fatigue_zero_fast_path_enabled, "Candidate must remain off by default until validation")
	var fixture := _work_fixture()
	var data: TerrainData = fixture.data
	_lab.bind_terrain(data)
	_lab.npc.faction_id = _lab.character.faction_id
	var team: TerrainArmy = _lab.army
	team.roster_size = 3
	var cells: Array[Vector2i] = []
	cells.assign(fixture.cells)
	assert(team.deploy_at(data, _lab.character, _lab.npc, cells) and team.enable_combat(false))
	team.set_process(false)
	team.faction_id = _lab.character.faction_id
	team.settle_combat_command()
	data.site.army_next_team = team.team_id + 1
	var occupied: Array[Vector2i] = cells.duplicate()
	occupied.append(_lab.npc.terrain_cell)
	var donor_cell := _nearby_free(data, cells[0], occupied, 1, 1)
	assert(donor_cell != TerrainArmy.INVALID_CELL and _lab.character.place(donor_cell, true))
	# Explicit fixture food in the original private cargo, moved by the original
	# adjacent timed operation; never borrowed from the shared depot implicitly.
	data.site.manual.cargo = {"grain": 4}
	_lab.character.ammo_inventory = data.site.manual.cargo
	assert(_lab.site_controller.begin_team_food(team, 4, team.combat_identity(0)).ok)
	_lab._process(0.1)
	assert(_lab.site_controller._supply_entry(team).delivery.is_empty())
	assert(int(data.site.manual.cargo.get("grain", 0)) == 0)
	var save_path := "res://.godot-temp/site_resources_contract/fatigue_zero_%d.json" % Time.get_ticks_usec()
	_lab.site_controller._capture_positions()
	var saved := Store.save(data, save_path)
	assert(saved.ok, str(saved))
	var results: Array[Dictionary] = []
	for enabled: bool in [false, true]:
		var restored := Store.load_site(save_path)
		assert(restored.ok, str(restored))
		_lab.bind_terrain(restored.data)
		_lab.army.set_process(false)
		_lab.character.set_process(false)
		_lab.npc.set_process(false)
		_lab.fatigue_zero_fast_path_enabled = enabled
		_lab.combat_profile_enabled = false
		_lab.combat_profile_usec.clear()
		_lab.fatigue_zero_eligible_rows = 0
		_lab.fatigue_zero_skipped_advances = 0
		_candidate = enabled
		_samples = []
		var result := _exercise()
		assert(not result.is_empty(), "Scenario aborted before all original-owner cases completed")
		assert(_mismatch.is_empty(), _mismatch)
		results.append(result)
		if not enabled:
			_reference = _samples.duplicate(true)
	assert(_samples.size() == _reference.size() and not _samples.is_empty())
	assert(results[0].eligible_rows > 0 and results[0].eligible_rows == results[1].eligible_rows)
	assert(results[0].skipped_advances == 0 and results[1].skipped_advances == results[1].eligible_rows)
	var report := {"exact": true, "original": results[0], "candidate": results[1],
		"people": 5, "army_rows": 3, "same_original_ids": true,
		"scope": "common-step fatigue/rest IEEE bytes, type normalization, actual training/work/damage/rates; not collision geometry or FPS",
		"lab_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_lab.gd")}
	var output := "res://output/site_combat_performance_20260913/fatigue_zero_fast/%d_%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) == OK)
	var file := FileAccess.open(output + "/measurements.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SITE FATIGUE ZERO FAST PASS: ", JSON.stringify(report), "; output=", output)
	return true
