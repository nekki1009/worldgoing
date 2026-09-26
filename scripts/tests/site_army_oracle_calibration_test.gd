extends SceneTree
## Test-only A/A timing through the formal TerrainLab owners.

const Oracle = preload("res://scripts/tests/fixtures/site_army_logical_state_oracle.gd")
const MAIN := "res://scenes/terrain_lab/TerrainLab.tscn"
const STEP := 1.0 / 30.0
const TICKS := 8
const PER_TEAM := 2500
const OUTPUT_DIR := "res://output/site_army_5k_event_update_20260926"
var _setup_error := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var started := Time.get_ticks_usec()
	var deadline := started + 110000000
	var report := {"status": "SETUP", "scene": MAIN, "preset": "PLAINS", "seed": 581,
		"output": "%s/aa_%d_%d.json" % [OUTPUT_DIR, int(Time.get_unix_time_from_system()), OS.get_process_id()],
		"per_team": PER_TEAM, "scenes": 2, "ticks": TICKS, "step": STEP,
		"army_sha256": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_army.gd"),
		"oracle_sha256": FileAccess.get_sha256("res://scripts/tests/fixtures/site_army_logical_state_oracle.gd"),
		"setup_usec": 0, "a_process_usec": 0, "b_process_usec": 0,
		"snapshot_assembly_usec": 0, "compare_usec": 0, "snapshots_compared": 0}
	if str(ProjectSettings.get_setting("application/run/main_scene")) != MAIN:
		_finish(report, "Main scene changed", 1)
		return
	# Match the formal 5k fixture's deployment-only, in-memory capacity override.
	if TerrainArmy.MAX_ROSTER_SIZE < PER_TEAM:
		var army_script := load("res://scripts/terrain_lab/terrain_army.gd") as GDScript
		var guard := "selected.size() > MAX_ROSTER_SIZE"
		if army_script.source_code.count(guard) != 1:
			_finish(report, "Deployment guard drifted", 1)
			return
		army_script.source_code = army_script.source_code.replace(guard, "selected.size() > %d" % PER_TEAM)
		if army_script.reload(true) != OK:
			_finish(report, "In-memory deployment override failed", 1)
			return
		report["deployment_only_memory_override"] = guard + " -> selected.size() > %d" % PER_TEAM
		report["army_runtime_sha256"] = army_script.source_code.sha256_text()
	var a := _formal_scene()
	report["a_setup"] = "PASS" if a != null else _setup_error
	var b := _formal_scene()
	report["b_setup"] = "PASS" if b != null else _setup_error
	if a == null or b == null:
		_dispose(a, b)
		_finish(report, "Formal A/A setup failed", 1)
		return
	if is_same(a.terrain.site, b.terrain.site) or is_same(a.combat_armies[0].command_rng, b.combat_armies[0].command_rng):
		_dispose(a, b)
		_finish(report, "A/A sites or RNG objects are shared", 1)
		return
	report["visual_modes_before_render_warmup"] = [a.combat_armies[0].visual_mode(), a.combat_armies[1].visual_mode(),
		b.combat_armies[0].visual_mode(), b.combat_armies[1].visual_mode()]
	var a_events: Array = []
	var b_events: Array = []
	_attach_events(a, a_events)
	_attach_events(b, b_events)
	report.setup_usec = Time.get_ticks_usec() - started
	for tick in range(TICKS + 1):
		if Time.get_ticks_usec() >= deadline:
			report["first_unfinished_tick"] = tick
			_dispose(a, b)
			_finish(report, "Internal 110-second budget reached", 1)
			return
		var begin: int
		if tick > 0:
			begin = Time.get_ticks_usec()
			a._process(STEP)
			report.a_process_usec += Time.get_ticks_usec() - begin
			begin = Time.get_ticks_usec()
			b._process(STEP)
			report.b_process_usec += Time.get_ticks_usec() - begin
		begin = Time.get_ticks_usec()
		var a_snapshot := _snapshot(a, a_events)
		var b_snapshot := _snapshot(b, b_events)
		report.snapshot_assembly_usec += Time.get_ticks_usec() - begin
		begin = Time.get_ticks_usec()
		var mismatch: String = Oracle.first_mismatch(a_snapshot, b_snapshot)
		report.compare_usec += Time.get_ticks_usec() - begin
		report.snapshots_compared += 1
		if not mismatch.is_empty():
			report["first_mismatch_tick"] = tick
			report["first_mismatch"] = mismatch
			_dispose(a, b)
			_finish(report, "A/A mismatch", 1)
			return
		a_events.clear()
		b_events.clear()
	_dispose(a, b)
	report["elapsed_usec_before_write"] = Time.get_ticks_usec() - started
	_finish(report, "PASS", 0)


func _formal_scene() -> TerrainLab:
	var lab := (load(MAIN) as PackedScene).instantiate() as TerrainLab
	if lab == null:
		_setup_error = "TerrainLab scene did not instantiate"
		return null
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller._auto_save_blocked = true
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	SiteEnvironment.initialize(data, "oracle-calibration-581")
	lab.bind_terrain(data)
	lab.site_controller.release_worker()
	data.site.paused = false
	paused = false
	lab.third_army.command_rng.seed = data.seed_value * 1009 + lab.third_army.team_id
	for side in range(2):
		var team: TerrainArmy = lab.combat_armies[side]
		team.periodic_review_stagger_enabled = true
		team.shared_fatigue_enabled = true
		team.batch_render_enabled = true
		team.roster_size = PER_TEAM
		var selected: Array[Vector2i] = []
		for depth in range(50):
			for y in range(1, 99):
				var cell := Vector2i(49 - depth if side == 0 else 50 + depth, y)
				if data.is_walkable(cell) and not lab.character.occupies_cell(cell) and (lab.npc == null or not lab.npc.occupies_cell(cell)):
					selected.append(cell)
				if selected.size() == PER_TEAM:
					break
			if selected.size() == PER_TEAM:
				break
		if selected.size() != PER_TEAM:
			_setup_error = "side %d selected %d legal cells, expected %d" % [side, selected.size(), PER_TEAM]
			lab.free()
			return null
		if not team.deploy_at(data, lab.character, lab.npc, selected):
			_setup_error = "side %d deploy_at failed with %d cells" % [side, selected.size()]
			lab.free()
			return null
		if not team.enable_combat():
			_setup_error = "side %d enable_combat failed: rows=%d mode=%s" % [side, team.combat_units.size(), team.visual_mode()]
			lab.free()
			return null
		if team.combat_units.size() != PER_TEAM or not team.exchange_enabled:
			_setup_error = "side %d invalid after enable: rows=%d exchange=%s mode=%s" % [side, team.combat_units.size(), team.exchange_enabled, team.visual_mode()]
			lab.free()
			return null
		for index in range(PER_TEAM):
			team.facing[index] = Vector2i.RIGHT if side == 0 else Vector2i.LEFT
		team._visual_dirty = true
	data.site.army_trial_active = true
	return lab


func _snapshot(lab: TerrainLab, events: Array) -> Array:
	var all_units: Array = []
	for team: TerrainArmy in lab.combat_armies:
		all_units.append(team.combat_units)
	return [all_units, _aux(lab), events]


func _aux(lab: TerrainLab) -> Dictionary:
	var result := {"site": lab.terrain.site, "action_remainder": lab._action_time_remainder,
		"exchange_round": lab._exchange_round, "exchange_phase": lab._exchange_phase,
		"exchange_count": lab.exchange_count, "exchange_results": lab.exchange_results,
		"ranged_shots": lab.ranged_shots, "ranged_resolutions": lab.ranged_resolutions,
		"ranged_results": lab.ranged_results, "contacts": _contacts(lab),
		"controller_work_elapsed": lab.site_controller._work_elapsed,
		"controller_save_elapsed": lab.site_controller._save_elapsed,
		"character": _actor(lab.character), "npc": _actor(lab.npc), "teams": []}
	for team: TerrainArmy in lab.combat_armies:
		result.teams.append({"rng": team.command_rng.state, "cells": team.cells, "slots": team.combat_slots,
			"facing": team.facing, "moving_to": team.moving_to, "move_progress": team.move_progress,
			"move_duration": team.move_duration, "cell_owners": team._cell_owners,
			"reserved_cells": team._reserved_cells, "rescues": team._unit_rescues,
			"vacancies": team._vacancy_assignments, "batch_members": team._combat_batch_members,
			"order": team.combat_order, "command_dirty": team._command_dirty,
			"visual_dirty": team._visual_dirty, "abilities": team.command_abilities,
			"encirclement_reviews": team.encirclement_reviews, "encirclement_steps": team.encirclement_steps,
			"proposal_count": team.proposal_count, "accepted_count": team.accepted_count,
			"rejected_dependency_count": team.rejected_dependency_count,
			"projectiles": team.projectiles})
	return result


func _actor(actor: TerrainTestCharacter) -> Variant:
	if actor == null:
		return null
	return [actor.person_id, actor.terrain_cell, actor.position, actor.hp, actor.knockout_left,
		actor.fatigue, actor.fatigue_rest, actor.faction_id]


func _owner_id(owner: Variant, unit: int) -> Array:
	if owner is TerrainArmy:
		return ["army", owner.team_id, unit]
	if owner is TerrainTestCharacter:
		return ["actor", owner.person_id, unit]
	assert(false, "Unexpected contact owner")
	return ["unexpected", typeof(owner), unit]


func _contacts(lab: TerrainLab) -> Array:
	var result: Array = []
	for packet: Dictionary in lab._combat_contacts:
		var values := packet.duplicate()
		values.attacker = _owner_id(packet.attacker, int(packet.get("attacker_unit", -1)))
		values.target = _owner_id(packet.target, int(packet.get("target_unit", -1)))
		result.append(values)
	return result


func _attach_events(lab: TerrainLab, events: Array) -> void:
	for side in range(lab.combat_armies.size()):
		var team: TerrainArmy = lab.combat_armies[side]
		team.combat_event.connect(Callable(self, "_record_event").bind(events, "team", side, "combat"))
		team.died.connect(Callable(self, "_record_event").bind(events, "team", side, "died"))
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.combat_event.connect(Callable(self, "_record_event").bind(events, "actor", actor.person_id, "combat"))
		actor.died.connect(Callable(self, "_record_event").bind(events, "actor", actor.person_id, "died"))


func _record_event(value: Variant, events: Array, owner: String, identity: int, kind: String) -> void:
	events.append([owner, identity, kind, value])


func _dispose(a: TerrainLab, b: TerrainLab) -> void:
	if a != null:
		a.free()
	if b != null:
		b.free()


func _finish(report: Dictionary, status: String, exit_code: int) -> void:
	report["status"] = status
	var output: String = report.output
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Could not write A/A calibration report")
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	if exit_code != 0:
		push_error("SITE_ARMY_ORACLE_CALIBRATION_FAIL " + status + " output=" + output)
	else:
		print("SITE_ARMY_ORACLE_CALIBRATION_PASS output=", output)
	quit(exit_code)
