extends SceneTree
## Same-source A/B oracle for the guarded encirclement geometry prefilter.
## The 5k case proves the real SiteController branch is reached; guard probes
## each change one mutable alias or owner while all other admission stays live.

const Oracle = preload("res://scripts/tests/fixtures/site_army_logical_state_oracle.gd")
const MAIN := "res://scenes/terrain_lab/TerrainLab.tscn"
const STEP := 1.0 / 30.0
const DEADLINE_MS := 600000

var _deadline: int

class CustomWorkTeam extends SiteWorkTeam:
	pass


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_deadline = Time.get_ticks_msec() + DEADLINE_MS
	# A and B share one runtime source. The disk product stays untouched.
	var army_script := load("res://scripts/terrain_lab/terrain_army.gd") as GDScript
	var army_source := army_script.source_code.replace("\r\n", "\n")
	if TerrainArmy.MAX_ROSTER_SIZE < 2500:
		var guard := "selected.size() > MAX_ROSTER_SIZE"
		if army_source.count(guard) != 1:
			push_error("5k deployment guard drifted")
			quit(1)
			return
		army_source = army_source.replace(guard, "selected.size() > 2500")
	# Test-only field capacity exposes the 624/625/626 branch without a second scene.
	var switch := "var geometry_prefilter_enabled := true"
	var field_start := army_source.find("func _try_exchange_encirclement() -> bool:")
	var field_end := army_source.find("\nfunc ", field_start + 1)
	if army_source.count(switch) != 1 or field_start < 0 or field_end < 0:
		push_error("Geometry boundary source anchors drifted")
		quit(1)
		return
	var field_body := army_source.substr(field_start, field_end - field_start)
	var field_start_anchor := "\tvar distance := {}\n"
	var threshold_anchor := "\tvar filter_origins := distance.size() * TerrainData.DIRECTIONS.size() < combat_units.size()"
	if field_body.count("ENCIRCLEMENT_CELLS") != 3 or field_body.count(field_start_anchor) != 1 or field_body.count(threshold_anchor) != 1:
		push_error("Encirclement field source anchors drifted")
		quit(1)
		return
	field_body = field_body.replace("ENCIRCLEMENT_CELLS", "field_limit")
	field_body = field_body.replace(field_start_anchor, field_start_anchor + "\tvar field_limit := ENCIRCLEMENT_CELLS if geometry_prefilter_test_limit < 0 else geometry_prefilter_test_limit\n")
	field_body = field_body.replace(threshold_anchor, "\tgeometry_prefilter_test_field_size = distance.size()\n" + threshold_anchor)
	army_source = army_source.substr(0, field_start) + field_body + army_source.substr(field_end)
	army_source = army_source.replace(switch, switch + "\nvar geometry_prefilter_test_limit := -1\nvar geometry_prefilter_test_field_size := -1")
	army_script.source_code = army_source
	if army_script.reload(true) != OK:
		push_error("Could not load the test-only 5k and field boundary source")
		quit(1)
		return
	if not _compare_pair(2500, 36, true):
		quit(1)
		return
	print("ARMY_GEOMETRY_PREFILTER_PASS current-source A/B, formal SiteController, 5k branch, one-at-a-time guards and custom callback order")
	quit(0)


func _formal_scene(per_team: int, geometry_enabled: bool) -> TerrainLab:
	var lab := (load(MAIN) as PackedScene).instantiate() as TerrainLab
	if lab == null:
		push_error("Formal TerrainLab scene did not instantiate")
		return null
	lab.pause_when_unfocused = false
	root.add_child(lab)
	lab.set_process(false)
	lab.set_process_unhandled_input(false)
	lab.site_controller._auto_save_blocked = true
	var data := TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 581)
	SiteEnvironment.initialize(data, "geometry-prefilter-581")
	lab.bind_terrain(data)
	lab.site_controller.release_worker()
	data.site.paused = false
	paused = false
	# The inactive third slot never calls enable_combat, so give both scenes the
	# same explicit seed before including its RNG in the complete owner oracle.
	lab.third_army.command_rng.seed = data.seed_value * 1009 + lab.third_army.team_id
	for side in range(2):
		var team: TerrainArmy = lab.combat_armies[side]
		team.geometry_prefilter_enabled = geometry_enabled
		team.roster_size = per_team
		var selected: Array[Vector2i] = []
		var columns: Array[int] = []
		if per_team == 2500:
			# Correctness-only layout: the original BFS has a real open band
			# behind a contacting front, so its field can exceed 625 cells.
			columns.append(49 if side == 0 else 50)
			for x in range(1, 41) if side == 0 else range(60, 99):
				columns.append(x)
		else:
			for depth in range(50):
				columns.append(49 - depth if side == 0 else 50 + depth)
		for x in columns:
			for y in range(1, 99):
				var cell := Vector2i(x, y)
				if data.is_walkable(cell) and not lab.character.occupies_cell(cell) and (lab.npc == null or not lab.npc.occupies_cell(cell)):
					selected.append(cell)
				if selected.size() == per_team:
					break
			if selected.size() == per_team:
				break
		if selected.size() != per_team or not team.deploy_at(data, lab.character, lab.npc, selected) or not team.enable_combat():
			push_error("Formal geometry fixture could not deploy side %d with %d people" % [side, per_team])
			lab.free()
			return null
		for index in range(per_team):
			team.facing[index] = Vector2i.RIGHT if side == 0 else Vector2i.LEFT
		team._visual_dirty = true
		var controller := lab.site_controller as SiteController
		if controller == null or team.person_busy_query.get_object() != controller or team.person_busy_query.get_method() != &"_person_has_duty" \
			or team.equipment_appearance_query.get_object() != controller or team.equipment_appearance_query.get_method() != &"person_appearance" \
			or team.controlled_person_query.get_object() != lab or team.controlled_person_query.get_method() != &"controlled_person_id" \
			or team.exchange_people_query.get_object() != lab or team.exchange_people_query.get_method() != &"_exchange_people" or team.exchange_people_query.get_bound_arguments() != [false]:
			push_error("Formal SiteController/Lab callback wiring changed on side %d" % side)
			lab.free()
			return null
	data.site.army_trial_active = true
	return lab


func _compare_pair(per_team: int, ticks: int, custom_fallback: bool) -> bool:
	var setup_started := Time.get_ticks_msec()
	var original := _formal_scene(per_team, false)
	var candidate := _formal_scene(per_team, true)
	if original == null or candidate == null:
		_dispose(original, candidate)
		return false
	var original_events: Array = []
	var candidate_events: Array = []
	_attach_events(original, original_events)
	_attach_events(candidate, candidate_events)
	if not _same(original, candidate, "initial %d" % per_team, original_events, candidate_events):
		_dispose(original, candidate)
		return false
	if per_team == 2500 and not _guard_shapes(candidate):
		_dispose(original, candidate)
		return false
	var tick_started := Time.get_ticks_msec()
	print("ARMY_GEOMETRY_PREFILTER_TIMING roster=", per_team * 2, " setup_ms=", tick_started - setup_started)
	for replay_tick in range(ticks):
		if Time.get_ticks_msec() >= _deadline:
			push_error("Geometry oracle exceeded 600 seconds at roster %d tick %d" % [per_team, replay_tick])
			_dispose(original, candidate)
			return false
		original._process(STEP)
		candidate._process(STEP)
		if not _same(original, candidate, "roster %d tick %d" % [per_team, replay_tick + 1], original_events, candidate_events):
			_dispose(original, candidate)
			return false
	print("ARMY_GEOMETRY_PREFILTER_TIMING roster=", per_team * 2, " ticks=", ticks, " elapsed_ms=", Time.get_ticks_msec() - tick_started)
	if custom_fallback:
		var reviews := 0
		var skipped := 0
		for side in range(2):
			var baseline_side: TerrainArmy = original.combat_armies[side]
			var candidate_side: TerrainArmy = candidate.combat_armies[side]
			if baseline_side.geometry_prefilter_reviews != 0 or baseline_side.geometry_prefilter_skipped != 0:
				push_error("Original-A unexpectedly entered G on side %d" % side)
				_dispose(original, candidate)
				return false
			reviews += candidate_side.geometry_prefilter_reviews
			skipped += candidate_side.geometry_prefilter_skipped
		if reviews <= 0 or skipped <= 0:
			push_error("Correctness-only 5k field did not enter and reject rows in G: reviews=%d skipped=%d encirclement=%d/%d" % [reviews, skipped,
				original.combat_armies[0].encirclement_reviews, original.combat_armies[1].encirclement_reviews])
			_dispose(original, candidate)
			return false
		var old_log: Array = []
		var new_log: Array = []
		var baseline_probe_team: TerrainArmy = original.combat_armies[0]
		var candidate_probe_team: TerrainArmy = candidate.combat_armies[0]
		var baseline_busy: Callable = baseline_probe_team.person_busy_query
		var candidate_busy: Callable = candidate_probe_team.person_busy_query
		_install_busy_probe(baseline_probe_team, old_log)
		_install_busy_probe(candidate_probe_team, new_log)
		var review_before := candidate_probe_team.geometry_prefilter_reviews
		var original_review_before := baseline_probe_team.encirclement_reviews
		var callback_calls := 0
		for fallback_tick in range(36):
			if Time.get_ticks_msec() >= _deadline:
				push_error("Geometry callback replay exceeded 600 seconds")
				_dispose(original, candidate)
				return false
			original._process(STEP)
			candidate._process(STEP)
			if not _same(original, candidate, "custom callback tick %d" % [fallback_tick + 1], original_events, candidate_events):
				_dispose(original, candidate)
				return false
			var mismatch: String = Oracle.first_mismatch(old_log, new_log)
			if not mismatch.is_empty():
				push_error("Custom callback order changed at tick %d: %s" % [fallback_tick + 1, mismatch])
				_dispose(original, candidate)
				return false
			callback_calls += old_log.size()
			old_log.clear()
			new_log.clear()
		if callback_calls == 0 or baseline_probe_team.encirclement_reviews <= original_review_before or candidate_probe_team.geometry_prefilter_reviews != review_before:
			push_error("Custom busy callback did not exercise original-order G fallback")
			_dispose(original, candidate)
			return false
		print("ARMY_GEOMETRY_PREFILTER_5K_PASS G reviews=", reviews, " skipped=", skipped, " custom calls=", callback_calls)
		baseline_probe_team.person_busy_query = baseline_busy
		candidate_probe_team.person_busy_query = candidate_busy
		if not _field_boundaries(original, candidate, original_events, candidate_events):
			_dispose(original, candidate)
			return false
	else:
		print("ARMY_GEOMETRY_PREFILTER_FULL_FLOW_PASS 2x", per_team, " action_ticks=", ticks,
			" exchange_count=", original.exchange_count)
	_dispose(original, candidate)
	return true


func _field_boundaries(original: TerrainLab, candidate: TerrainLab, original_events: Array, candidate_events: Array) -> bool:
	var baseline_team: TerrainArmy = original.combat_armies[0]
	var candidate_team: TerrainArmy = candidate.combat_armies[0]
	for limit: int in [624, 625, 626]:
		baseline_team.set("geometry_prefilter_test_limit", limit)
		candidate_team.set("geometry_prefilter_test_limit", limit)
		var previous_reviews := candidate_team.geometry_prefilter_reviews
		var previous_old := baseline_team.encirclement_reviews
		var previous_new := candidate_team.encirclement_reviews
		var old_result := baseline_team._try_exchange_encirclement()
		var new_result := candidate_team._try_exchange_encirclement()
		var old_size := int(baseline_team.get("geometry_prefilter_test_field_size"))
		var new_size := int(candidate_team.get("geometry_prefilter_test_field_size"))
		var expected_g := 0 if limit == 624 else 1
		if not old_result or new_result != old_result or old_size != limit or new_size != limit \
				or baseline_team.encirclement_reviews != previous_old + 1 \
				or candidate_team.encirclement_reviews != previous_new + 1 \
				or candidate_team.geometry_prefilter_reviews != previous_reviews + expected_g:
			push_error("Field threshold %d failed: result=%s/%s field=%d/%d G delta=%d" % [limit,
				old_result, new_result, old_size, new_size, candidate_team.geometry_prefilter_reviews - previous_reviews])
			return false
		if not _same(original, candidate, "field threshold %d" % limit, original_events, candidate_events):
			return false
	baseline_team.set("geometry_prefilter_test_limit", -1)
	candidate_team.set("geometry_prefilter_test_limit", -1)
	print("ARMY_GEOMETRY_PREFILTER_BOUNDARY_PASS field sizes 624/625/626 and complete A/B owner state")
	return true


func _install_busy_probe(team: TerrainArmy, trace: Array) -> void:
	var original: Callable = team.person_busy_query
	team.person_busy_query = func(identity: int) -> bool:
		trace.append(identity)
		return bool(original.call(identity))


func _guard_shapes(lab: TerrainLab) -> bool:
	var team: TerrainArmy = lab.combat_armies[0]
	var controller: SiteController = lab.site_controller
	if not team._canonical_geometry_prefilter_safe(lab):
		push_error("Canonical hot/Controller/publication proof did not admit the untouched formal scene")
		return false
	var busy: Callable = team.person_busy_query
	team.person_busy_query = func(_identity: int) -> bool: return false
	var rejected := not team._canonical_geometry_prefilter_safe(lab)
	team.person_busy_query = busy
	if not rejected or not team._canonical_geometry_prefilter_safe(lab):
		push_error("Custom callback guard failed or did not restore")
		return false
	var owner: SiteWorkTeam = controller.work_team
	var custom := CustomWorkTeam.new()
	custom.init(lab)
	controller.work_team = custom
	rejected = not team._canonical_geometry_prefilter_safe(lab)
	controller.work_team = owner
	if not rejected or not team._canonical_geometry_prefilter_safe(lab):
		push_error("Child-owner script guard failed or did not restore")
		return false
	var hot: RefCounted = team._combat_hot_store
	team._combat_hot_store = RefCounted.new()
	rejected = not team._canonical_geometry_prefilter_safe(lab)
	team._combat_hot_store = hot
	if not rejected or not team._canonical_geometry_prefilter_safe(lab):
		push_error("Replacement hot-store guard failed or did not restore")
		return false
	var last_cell: Vector2i = team.cells.pop_back()
	rejected = not team._canonical_geometry_prefilter_safe(lab)
	team.cells.append(last_cell)
	if not rejected or not team._canonical_geometry_prefilter_safe(lab):
		push_error("Truncated cell-array guard failed or did not restore")
		return false
	var original_terrain: TerrainData = team.data
	team.data = TerrainData.new()
	rejected = not team._canonical_geometry_prefilter_safe(lab)
	team.data = original_terrain
	if not rejected or not team._canonical_geometry_prefilter_safe(lab):
		push_error("Lab terrain identity guard failed or did not restore")
		return false
	var original_player: Variant = team.player
	team.player = null
	rejected = not team._canonical_geometry_prefilter_safe(lab)
	team.player = original_player
	if not rejected or not team._canonical_geometry_prefilter_safe(lab):
		push_error("Lab character identity guard failed or did not restore")
		return false
	var identity: int = team.combat_identity(1)
	var publications: Dictionary = controller._equipment_appearances
	var old_appearance: Variant = publications.get(identity, {})
	var typed: Dictionary[String, Variant] = {"parts": {"weapon": "longsword_01"}}
	publications[identity] = typed
	rejected = not team._canonical_geometry_prefilter_safe(lab)
	publications[identity] = old_appearance
	if not rejected or not team._canonical_geometry_prefilter_safe(lab):
		push_error("Typed publication guard failed or did not restore")
		return false
	var row: Dictionary = team.combat_units[1]
	var previous: Variant = row.get("work_task", {})
	var had_task := row.has("work_task")
	row["work_task"] = RefCounted.new()
	rejected = not team._canonical_geometry_prefilter_safe(lab)
	if had_task: row["work_task"] = previous
	else: row.erase("work_task")
	if not rejected or not team._canonical_geometry_prefilter_safe(lab):
		push_error("Mutable row alias guard failed or did not restore")
		return false
	print("ARMY_GEOMETRY_PREFILTER_GUARDS_PASS canonical admission, callback, child owner, hot store, cell length, terrain/character identity, typed publication, mutable row")
	return true


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


func _same(original: TerrainLab, candidate: TerrainLab, stage: String, original_events: Array, candidate_events: Array) -> bool:
	for side in range(original.combat_armies.size()):
		var first: TerrainArmy = original.combat_armies[side]
		var second: TerrainArmy = candidate.combat_armies[side]
		var mismatch: String = Oracle.first_mismatch(first.combat_units, second.combat_units)
		if not mismatch.is_empty():
			push_error("%s team %d %s" % [stage, side, mismatch])
			return false
	var other_mismatch: String = Oracle.first_mismatch([_aux(original), original_events], [_aux(candidate), candidate_events])
	if not other_mismatch.is_empty():
		push_error("%s %s" % [stage, other_mismatch])
		return false
	original_events.clear()
	candidate_events.clear()
	return true


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


func _dispose(original: TerrainLab, candidate: TerrainLab) -> void:
	if original != null:
		original.free()
	if candidate != null:
		candidate.free()
