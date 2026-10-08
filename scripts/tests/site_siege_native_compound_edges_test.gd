extends "res://scripts/tests/site_siege_native_integration_test.gd"
## Original Transport -> Native World group, then original contact/stop entry.
## KO is a controlled original hit injection; this does not prove shot geometry.

const NATIVE_KO_BLEED_PER_GAME_HOUR := 25.0 # Original native/crowd10k/src/rules.hpp.

var compound_case := "ko"
var compound_evidence: Dictionary = {}
var observed_clock_steps := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--siege-compound-case")
	if at >= 0 and at + 1 < args.size(): compound_case = args[at + 1]
	suite = "native_compound_edges"
	case_name = compound_case
	output_root = "res://output/site_siege_close_20261004/native_compound_edges"
	at = args.find("--siege-output")
	if at >= 0 and at + 1 < args.size(): output_root = args[at + 1]
	_run.call_deferred()

func _write_result() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_root))
	var file := FileAccess.open(output_root.path_join(compound_case + ".json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"ok": not failed, "case": compound_case, "checks": checks,
			"action_seconds": action_seconds, "observed_clock_steps": observed_clock_steps,
			"evidence": compound_evidence, "results": results,
			"scope": "original formal Native RAM compound interrupted at actual partial progress by original siege hit injection or authorized stop; same token/duration, actual all-member positions and common endpoint acknowledgment, conserved original IDs/holders/cargo/roles; no real projectile geometry, RETREAT, terrain abort, save/load, GPU/FPS or whole siege acceptance claim"}, "\t"))
		file.close()

func _step(combat: bool = true) -> bool:
	var before_steps: int = int(lab.crowd_site._steps)
	var before_game := SiteRuntime.now(lab.terrain) * 60.0
	var before_action := action_seconds
	if not super._step(combat): return false
	var delta_game := SiteRuntime.now(lab.terrain) * 60.0 - before_game
	if int(lab.crowd_site._steps) != before_steps + 1 or absf(delta_game - DT) > EPS or absf(action_seconds - before_action - DT) > EPS:
		return _check(false, "one original shared slice advances exactly one World/action/game clock", {"before_steps": before_steps, "after_steps": lab.crowd_site._steps, "game_delta": delta_game, "action_delta": action_seconds - before_action})
	observed_clock_steps += 1
	return true

func _run() -> void:
	create_timer(120.0).timeout.connect(func() -> void:
		failed = true; _write_result(); printerr("NATIVE_COMPOUND_EDGE deadline"); quit(3))
	if not _check(compound_case in ["ko", "stop"], "one exact original native interruption case", compound_case): return
	if not _preflight(): return
	var context := _make_context("ram", 2, true, "wood")
	if failed or context.is_empty(): return
	var vehicle := _vehicle(context)
	if not await _until(func() -> bool: return lab.site_controller.vehicles.crew_ready(vehicle), 40.0, "original minimum crew walks to its actual RAM stations"): return
	var references := _original_references(context)
	if failed: return
	var ordered: Dictionary = lab.site_controller.vehicles.order_siege(context.key, "move", {"type": "ground", "cell": [context.goal.x, context.goal.y]}, int(context.commander), true)
	if not _check(ordered.ok, "original authorized move command admits real Native RAM compound", ordered): return
	if not await _until(func() -> bool: return int(vehicle.move.get("native_token", 0)) > 0, 20.0, "original Transport admits an actual World group", true, func() -> Dictionary: return _ram_admission_probe(context)): return
	var token := int(vehicle.move.native_token)
	var plan: Dictionary = vehicle.move.duplicate(true)
	var state: Dictionary = lab.crowd_site.siege_group_state(token)
	if not _check(not state.is_empty() and float(state.duration) > DT * 3.0 and plan.participants.size() == 2, "real minimum-crew group has an observable partial interval", {"plan": plan, "state": state}): return
	if not await _until(func() -> bool:
		var current: Dictionary = lab.crowd_site.siege_group_state(token)
		return not current.is_empty() and float(current.elapsed) / float(current.duration) >= 0.30,
		float(state.duration), "original shared clock reaches actual partial group progress"): return
	state = lab.crowd_site.siege_group_state(token)
	var progress := float(state.elapsed) / float(state.duration)
	if not _check(progress > 0.0 and progress < 0.80 and not bool(state.complete) and not bool(state.cancelled) and not bool(state.aborted), "interruption occurs inside the actual uncancelled original group", state): return
	if not _observe_group(vehicle, plan, token, state, false): return
	var victim := int(context.crew[0])
	var original: Dictionary = lab.crowd_site.siege_original_person(victim)
	var hp_before := float(original.hp)
	var hit_before := int(original.hit)
	var positions_before := _member_positions(plan)
	var clocks_before := {"world_steps": int(lab.crowd_site._steps), "game_seconds": SiteRuntime.now(lab.terrain) * 60.0, "action_seconds": action_seconds}
	compound_evidence = {"token": token, "plan": _json_value(plan), "half_state": state.duplicate(true),
		"half_positions": _json_value(positions_before), "case": compound_case, "victim": victim,
		"initial_hp": hp_before, "initial_hit": hit_before, "clock_before_interrupt": clocks_before,
		"original_person_ids": references.ids, "original_roles": references.roles, "original_native_roles": references.native_roles, "samples": []}
	if compound_case == "ko":
		original.owner.ranged_apply_hit(int(original.unit), lab.terrain.cell_from_index(int(plan.from)), {"siege": true, "result": {"hp": 10.0, "stun": 100.0, "stagger": 0.35}})
		original = lab.crowd_site.siege_original_person(victim)
		var marks: PackedInt64Array = original.owner.native_siege_state(int(original.unit))
		if not _check(float(original.hp) == hp_before - 10.0 and float(original.ko) > 0.0 and int(original.hit) == hit_before + 1 and not original.owner.combat_can_act(int(original.unit))
			and marks.size() == 8 and int(marks[1]) == 6 and int(marks[3]) == token,
			"original siege contact creates actual KO and mode 6 without replacing the committed member", {"person": original, "marks": marks}): return
	else:
		var stopped: Dictionary = lab.site_controller.vehicles.order_siege(context.key, "stop", {}, int(context.commander), true)
		if not _check(stopped.ok and int(vehicle.move.get("native_token", 0)) == token and bool(vehicle.stop_pending), "authorized original stop retains that actual World commitment", stopped): return
	if not _check(_member_positions(plan) == positions_before and int(lab.crowd_site._steps) == int(clocks_before.world_steps)
		and SiteRuntime.now(lab.terrain) * 60.0 == float(clocks_before.game_seconds) and action_seconds == float(clocks_before.action_seconds),
		"original interruption entry changes no actual member position or clock"): return
	var elapsed_before := float(state.elapsed)
	var steps_after_interrupt := 0
	var maximum_steps := ceili((float(state.duration) - elapsed_before) / DT) + 2
	while not vehicle.move.is_empty() and steps_after_interrupt < maximum_steps:
		if not _step(): return
		steps_after_interrupt += 1
		if not _same_original_references(context, references): return
		if vehicle.move.is_empty(): break
		state = lab.crowd_site.siege_group_state(token)
		if not _check(not state.is_empty() and int(vehicle.move.get("native_token", 0)) == token
			and is_equal_approx(float(state.duration), float(plan.duration)) and bool(state.cancelled) and not bool(state.complete) and not bool(state.aborted)
			and absf(float(state.elapsed) - elapsed_before - steps_after_interrupt * DT) <= EPS,
			"cancelled original group retains one token/duration and monotonic original elapsed", state): return
		if not _observe_group(vehicle, plan, token, state, true): return
		compound_evidence.samples.append({"step": steps_after_interrupt, "state": state.duplicate(true), "positions": _json_value(_member_positions(plan))})
		if compound_case == "ko":
			if not _check(vehicle.crew_slots.values().has(victim) and str(vehicle.command.get("type", "")) == "release"
				and vehicle.command.get("people", []).has(victim), "KO member remains in its original slot until common acknowledgment", vehicle.command): return
		if steps_after_interrupt % 120 == 0: await process_frame
	if not _check(vehicle.move.is_empty() and lab.crowd_site.siege_group_state(token).is_empty() and not bool(lab.crowd_site.crowd.siege_busy())
		and int(vehicle.cell) == int(plan.cell) and vehicle.facing == plan.facing
		and absf(elapsed_before + steps_after_interrupt * DT - float(plan.duration)) <= DT + EPS,
		"all members and body reach the same original endpoint before one real acknowledgment", {"steps_after_interrupt": steps_after_interrupt, "duration": plan.duration, "vehicle": vehicle}): return
	if not _endpoint_members(plan, compound_case == "ko", victim): return
	if not _same_original_references(context, references): return
	if compound_case == "ko":
		original = lab.crowd_site.siege_original_person(victim)
		var bleed_game_seconds := SiteRuntime.now(lab.terrain) * 60.0 - float(clocks_before.game_seconds)
		var expected_hp := hp_before - 10.0 - NATIVE_KO_BLEED_PER_GAME_HOUR / 3600.0 * bleed_game_seconds
		compound_evidence["completion_bleeding"] = {"game_seconds": bleed_game_seconds, "expected_hp": expected_hp, "actual_hp": original.hp, "rule_hp_per_game_hour": NATIVE_KO_BLEED_PER_GAME_HOUR}
		if not _check(not vehicle.crew_slots.values().has(victim) and not lab.site_controller.vehicles.is_siege_crew(victim)
			and vehicle.crew_slots.size() == 1 and not lab.site_controller.vehicles.crew_ready(vehicle)
			and absf(float(original.hp) - expected_hp) <= EPS and not bool(original.owner.combat_hot_get(int(original.unit), &"bandaged", false))
			and float(original.ko) > 0.0 and int(original.hit) == hit_before + 1,
			"actual KO and original clock-based bleeding persist; only unavailable member safely releases below minimum", {"person": original, "vehicle": vehicle, "bleeding": compound_evidence.completion_bleeding}): return
		var rejected: Dictionary = lab.site_controller.vehicles.order_siege(context.key, "move", {"type": "ground", "cell": [context.goal.x, context.goal.y]}, int(context.commander), true)
		# The completion slice still publishes its true last-step velocity. The
		# original movement guard precedes the minimum-crew gate until next slice.
		if not _check(rejected == SiteRuntime.fail("BUSY") and lab.site_controller.vehicles._crew_moving(vehicle)
			and vehicle.move.is_empty() and vehicle.action.is_empty() and str(vehicle.command.type) == "stop",
			"actual last-step velocity retains the original earlier busy guard at common acknowledgment", {"result": rejected, "vehicle": vehicle.duplicate(true), "admission": _ram_admission_probe(context)}): return
	else:
		if not _check(vehicle.crew_slots == references.slots and str(vehicle.command.get("type", "")) == "stop" and not bool(vehicle.stop_pending), "original stop retains original healthy slots and starts no next transaction", vehicle): return
	for slice in range(6):
		if not _step(): return
		if not _check(vehicle.move.is_empty() and int(vehicle.cell) == int(plan.cell) and not bool(lab.crowd_site.crowd.siege_busy()), "original later slices cannot restart the cancelled compound", slice): return
		if not _endpoint_members(plan, compound_case == "ko", victim): return
		if not _same_original_references(context, references): return
	if compound_case == "ko":
		var before_retry := vehicle.duplicate(true)
		var rejected: Dictionary = lab.site_controller.vehicles.order_siege(context.key, "move", {"type": "ground", "cell": [context.goal.x, context.goal.y]}, int(context.commander), true)
		if not _check(not rejected.ok and str(rejected.code) == "UNREACHABLE" and vehicle == before_retry
			and not lab.site_controller.vehicles._crew_moving(vehicle), "original minimum-crew gate refuses the next compound after true last-step velocity settles", rejected): return
	compound_evidence["final_positions"] = _json_value(_member_positions(plan))
	compound_evidence["final_vehicle_cell"] = int(vehicle.cell)
	compound_evidence["final_slots"] = vehicle.crew_slots.duplicate(true)
	compound_evidence["final_victim"] = {"hp": lab.crowd_site.siege_original_person(victim).hp, "ko": lab.crowd_site.siege_original_person(victim).ko, "hit": lab.crowd_site.siege_original_person(victim).hit}
	compound_evidence["completion_action_seconds"] = steps_after_interrupt * DT
	if not _check(observed_clock_steps > 0, "every scenario slice used one observed original action/game/World clock", observed_clock_steps): return
	_write_result()
	await _close_lab()
	TerrainArmy.release_contact_source()
	print("SITE_SIEGE_NATIVE_COMPOUND_EDGES_PASS: ", compound_case, " / ", checks, " checks; original group interruption and common acknowledgment only")
	quit(0)

func _member_positions(plan: Dictionary) -> Dictionary:
	var positions := {}
	for movement: Dictionary in plan.participants:
		var original: Dictionary = lab.crowd_site.siege_original_person(int(movement.person_id))
		positions[str(movement.person_id)] = Vector2(original.position) / 64.0 if not original.is_empty() else Vector2.INF
	return positions

func _observe_group(vehicle: Dictionary, plan: Dictionary, token: int, state: Dictionary, cancelled: bool) -> bool:
	var progress := float(state.elapsed) / float(state.duration)
	var valid: bool = int(vehicle.cell) == int(plan.from) and vehicle.facing == plan.facing
	var participants: Array = []
	for movement: Dictionary in plan.participants:
		var original: Dictionary = lab.crowd_site.siege_original_person(int(movement.person_id))
		if original.is_empty(): return _check(false, "original committed member remains available by its same ID", movement)
		var marks: PackedInt64Array = original.owner.native_siege_state(int(original.unit))
		var source := Vector2(lab.terrain.cell_from_index(int(movement.from))) + Vector2.ONE * 0.5
		var target := Vector2(lab.terrain.cell_from_index(int(movement.to))) + Vector2.ONE * 0.5
		var actual: Vector2 = Vector2(original.position) / 64.0
		var expected := source.lerp(target, progress)
		valid = valid and marks.size() == 8 and int(marks[0]) == 1 and int(marks[1]) == (6 if cancelled else 5) and int(marks[2]) == int(movement.to)
		valid = valid and int(marks[3]) == token and int(marks[4]) == int(movement.from) and int(marks[5]) == int(movement.to) and int(marks[6]) == 0 and int(marks[7]) == 0
		valid = valid and actual.distance_to(expected) <= EPS and vehicle.crew_slots.get(str(movement.slot), -1) == int(movement.person_id)
		participants.append({"id": movement.person_id, "actual": actual, "expected": expected, "marks": marks})
	return _check(valid and progress > 0.0 and progress < 1.0, "all actual original member positions follow the same committed fraction while body/source/slots remain uncommitted", {"token": token, "progress": progress, "cancelled": cancelled, "participants": participants})

func _endpoint_members(plan: Dictionary, ko_case: bool, victim: int) -> bool:
	var valid := true
	var participants: Array = []
	for movement: Dictionary in plan.participants:
		var original: Dictionary = lab.crowd_site.siege_original_person(int(movement.person_id))
		if original.is_empty(): return _check(false, "all original endpoint members retain their IDs", movement)
		var marks: PackedInt64Array = original.owner.native_siege_state(int(original.unit))
		var actual: Vector2 = Vector2(original.position) / 64.0
		var expected := Vector2(lab.terrain.cell_from_index(int(movement.to))) + Vector2.ONE * 0.5
		var assigned := not (ko_case and int(movement.person_id) == victim)
		valid = valid and actual.distance_to(expected) <= EPS and marks.size() == 8 and int(marks[0]) == (1 if assigned else 0) and int(marks[1]) == 0 and int(marks[2]) == -1 and int(marks[3]) == 0
		participants.append({"id": movement.person_id, "actual": actual, "expected": expected, "marks": marks})
	return _check(valid, "every original member reaches its own committed endpoint and releases the same group claims", participants)

func _original_references(context: Dictionary) -> Dictionary:
	var vehicle := _vehicle(context)
	var references := {"people": {}, "ids": lab.crowd_site.crowd.person_ids(), "roles": {}, "native_roles": {}, "slots": vehicle.crew_slots.duplicate(true),
		"vehicle_holder": vehicle.holder, "vehicle_cargo": vehicle.cargo, "vehicle_holder_value": vehicle.holder.duplicate(true), "vehicle_cargo_value": vehicle.cargo.duplicate(true),
		"vehicle_hp": float(vehicle.hp), "vehicle_rng": int(vehicle.rng_state), "vehicle_seq": int(vehicle.next_attack_seq),
		"source_facing": vehicle.facing.duplicate(), "target_hp": _part_hp(context.target)}
	for identity: int in references.ids:
		var original: Dictionary = lab.crowd_site.siege_original_person(identity)
		if not _check(not original.is_empty(), "original initial participant/observer has a real native body and holder", identity): return {}
		var native: PackedFloat64Array = lab.crowd_site.crowd.get_soldier_state(int(original.unit))
		if not _check(native.size() > 13, "original native role exists in its authoritative hot row", identity): return {}
		references.people[identity] = {"holder": original.holder, "cargo": original.cargo, "holder_value": original.holder.duplicate(true), "cargo_value": original.cargo.duplicate(true), "body": original.body}
		references.roles[identity] = str(original.row.get("military_role", ""))
		references.native_roles[identity] = int(native[13])
	return references

func _same_original_references(context: Dictionary, references: Dictionary) -> bool:
	var vehicle := _vehicle(context)
	var valid: bool = lab.crowd_site.crowd.person_ids() == references.ids and is_same(vehicle.holder, references.vehicle_holder) and is_same(vehicle.cargo, references.vehicle_cargo)
	valid = valid and vehicle.holder == references.vehicle_holder_value and vehicle.cargo == references.vehicle_cargo_value and float(vehicle.hp) == float(references.vehicle_hp)
	valid = valid and int(vehicle.rng_state) == int(references.vehicle_rng) and int(vehicle.next_attack_seq) == int(references.vehicle_seq) and vehicle.facing == references.source_facing and _part_hp(context.target) == float(references.target_hp)
	for identity: int in references.people:
		var original: Dictionary = lab.crowd_site.siege_original_person(identity)
		var saved: Dictionary = references.people[identity]
		var native: PackedFloat64Array = lab.crowd_site.crowd.get_soldier_state(int(original.unit)) if not original.is_empty() else PackedFloat64Array()
		valid = valid and not original.is_empty() and is_same(original.body, saved.body) and is_same(original.holder, saved.holder) and is_same(original.cargo, saved.cargo)
		valid = valid and original.holder == saved.holder_value and original.cargo == saved.cargo_value and str(original.row.get("military_role", "")) == str(references.roles[identity])
		valid = valid and native.size() > 13 and int(native[13]) == int(references.native_roles[identity])
	return _check(valid, "same original IDs/body/holder/cargo aliases/items/cold military and native hot roles/source HP/RNG/sequence survive the interruption")
