extends "res://scripts/tests/site_fire_projectile_pipeline_test.gd"
## Candidate only: original fixtures, owners, Grid, release and Lab action path.
## No replacement hitbox, fabricated flight/result or alternate simulation clock.
## Inherits the base's 120-second wall timer; the canonical outer timeout is still required.
const GEOMETRY_OUTPUT := "res://output/fire_implementation_20261006/geometry_candidate"
const BODY_CHORD_PIXELS := 0.25 # Existing Lab refinement threshold, not a relaxed acceptance.
const CONTACT_REFINEMENT_STEPS := 256.0 # Original Collision.contact eight refinements.
var geometry_case := "all"

func _candidate_close(f: Fixture) -> void:
	if is_instance_valid(f.lab) and f.lab.combat_movement_coordinator != null:
		for team: TerrainArmy in f.teams:
			f.lab.combat_movement_coordinator.unregister_formation(team)
		f.lab.combat_movement_coordinator = null
	_close(f)

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Fixture in fixtures.duplicate(): _candidate_close(f)
	TerrainArmy.release_contact_source()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GEOMETRY_OUTPUT))
	var sources := {}
	for path: String in ["res://scripts/tests/site_fire_projectile_pipeline_test.gd", "res://scripts/terrain_lab/terrain_lab.gd",
		"res://scripts/terrain_lab/terrain_army.gd", "res://scripts/terrain_lab/site_combat_rules.gd",
		"res://scripts/terrain_lab/terrain_weapon_collision.gd", "res://scripts/terrain_lab/terrain_data.gd",
		"res://scripts/tests/site_fire_geometry_test.gd"]:
		sources[path] = FileAccess.get_sha256(path)
	var file := FileAccess.open(GEOMETRY_OUTPUT + "/geometry_result.json", FileAccess.WRITE)
	if file == null:
		push_error("Cannot write the separate geometry_result.json")
		ok = false
	else:
		file.store_string(JSON.stringify({"ok": ok and not failed, "case": geometry_case, "checks": checks,
			"reason": reason, "evidence": evidence, "sources": sources,
			"scope": "Candidate GD original-body graze, legal raw/raised slopes, real Grid half-step/contact cadence and NORMAL automatic discipline; no GPU/FPS/Native/persistence/phase acceptance"}, "\t"))
		file.close()
	print("SITE_FIRE_GEOMETRY_CANDIDATE_", "PASS" if ok and not failed else "FAIL", ": case=", geometry_case, " checks=", checks, " ", reason)
	await process_frame
	quit(0 if ok and not failed else 1)

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--geometry-case="): geometry_case = argument.trim_prefix("--geometry-case=")
	var actions := {"discipline": _normal_discipline, "cross_height": _cross_height,
		"motion": _committed_motion, "graze": _real_graze_scout}
	if not _check(geometry_case == "all" or actions.has(geometry_case), "Known candidate case", geometry_case):
		_finish(false, "unknown case")
		return
	for name: String in actions:
		if geometry_case != "all" and geometry_case != name: continue
		print("FIRE_GEOMETRY_CASE_BEGIN: ", name)
		var action: Callable = actions[name]
		var ok: bool = await action.call()
		if finished: return
		if not ok or failed:
			_finish(false, name)
			return
		await process_frame
		if finished: return
	_finish(true)

func _observe_contacts(f: Fixture) -> Array[Dictionary]:
	var observed: Array[Dictionary] = []
	f.lab.ranged_resolved.connect(func(source: int, target: int, result: Dictionary) -> void:
		if f.lab.fire_impact_recorder.is_empty(): return
		var payload: Dictionary = f.lab.fire_impact_recorder.back().duplicate(true)
		var sample := {"source": source, "target": target, "result": result.duplicate(true), "payload": payload}
		for original: Dictionary in f.lab.fire_projectiles:
			if int(original.projectile_id) != int(payload.projectile_id): continue
			# This is a read-only query of the real just-settled flight and the same
			# synchronous original geometry batch. It supplies no result to gameplay.
			var before_bytes := var_to_bytes(original)
			var delta := float(f.lab._fire_motion_delta)
			var begin := maxf(0.0, float(f.lab.fire_action_cursor) - float(original.spawn_action))
			var end := minf(float(original.life), begin + delta)
			if delta > 0.0:
				var replay := f.lab._fire_first_contact(original, SiteCombatRules.fire_position(original, begin),
					SiteCombatRules.fire_position(original, end), 0.0, (end - begin) / delta)
				sample["query_stable"] = str(replay.get("stable", ""))
				sample["incidence"] = float(replay.get("incidence", -1.0))
				sample["shield"] = bool(replay.get("shield", false))
				if replay.has("person"):
					var person: Dictionary = replay.person
					var at := clampf((float(payload.action_time) - float(f.lab.fire_action_cursor)) / delta, 0.0, 1.0)
					var ground := f.lab._fire_motion_ground(person, at)
					var low := maxf(0.0, at - 0.0001)
					var high := minf(1.0, at + 0.0001)
					var low_point := SiteCombatRules.fire_position(original, begin + delta * low)
					var high_point := SiteCombatRules.fire_position(original, begin + delta * high)
					var velocity := (f.lab._fire_relative_screen(person, high_point, high) - f.lab._fire_relative_screen(person, low_point, low)) / (delta * (high - low))
					sample["normal_speed_pixels"] = velocity.length() * absf(float(replay.incidence))
					sample["ground"] = ground
					sample["surface"] = f.lab._fire_surface_height(ground)
					sample["motion"] = person.motion.duplicate(true)
					sample["body_count"] = person.geometry.body.size()
					sample["body_sha256"] = var_to_bytes(person.geometry.body).hex_encode().sha256_text()
					sample["owner_cell"] = person.owner.cells[int(person.unit)] if int(person.unit) >= 0 else person.owner.terrain_cell
					if not person.motion.is_empty():
						sample["progress"] = TerrainArmy.CombatTimings.advance_movement_progress(float(person.motion.progress), delta * at, float(person.motion.duration))
			_check(before_bytes == var_to_bytes(original), "Geometry observer never changes the original emitted flight")
			sample["flight"] = {"origin": original.origin, "velocity": original.velocity, "total": original.total,
				"elapsed": original.elapsed, "spawn_action": original.spawn_action, "aim_key": original.aim_key,
				"gravity": original.gravity, "shooter": original.shooter.duplicate(true)}
			break
		observed.append(sample))
	return observed

func _make_ramp(f: Fixture, low: Vector2i, high: Vector2i, raised: bool) -> bool:
	var direction := TerrainData.DIRECTIONS.find(high - low)
	if not _check(direction >= 0, "Ramp fixture has adjacent original navigation cells"): return false
	if raised:
		f.data.walk_height_levels = f.data.height_levels.duplicate()
		f.data.walk_height_levels[f.data.index(high)] = 1
		f.data.walk_ramp_edges = f.data.ramp_edges.duplicate()
		f.data.walk_ramp_edges[f.data.index(low)] |= 1 << direction
		f.data.walk_ramp_edges[f.data.index(high)] |= 1 << ((direction + 2) % 4)
		f.data.has_raised_surfaces = true
		f.data.has_navigation_overrides = true
	else:
		f.data.height_levels[f.data.index(high)] = 1
		f.data.ramp_edges[f.data.index(low)] |= 1 << direction
		f.data.ramp_edges[f.data.index(high)] |= 1 << ((direction + 2) % 4)
	return _check(f.data.can_step(low, high) and f.data.can_step(high, low)
		and f.data.effective_height(low) == 0 and f.data.effective_height(high) == 1,
		"Cross-height fixture uses a legal original bidirectional ramp", {"raised": raised, "low": low, "high": high})

func _cross_height() -> bool:
	for raised: bool in [false, true]:
		var f := _fixture()
		if not _make_ramp(f, Vector2i(15, 10), Vector2i(16, 10), raised): return false
		var source := _team(f, [Vector2i(10, 10)])
		var target := _team(f, [Vector2i(16, 10)], 2, 1)
		if failed: return false
		source.combat_units[0].cargo.arrow = 1
		var observations := _observe_contacts(f)
		var aim := f.lab._fire_target_aim({"type": "person", "person_id": target.combat_identity(0)})
		if not _check(not target.incoming_geometry(0).body.is_empty() and not aim.is_empty()
			and is_equal_approx(float(aim.point.z), 2.0) and f.data.effective_height(source.cells[0]) == 0,
			"Original cross-height body and nominal target eye are present", {"raised": raised, "aim": aim}): return false
		if not _order(f, source, {"type": "person", "person_id": target.combat_identity(0)}): return false
		if not _await_release(f) or not _stop(f, source): return false
		if not _check(f.lab.fire_projectiles.size() == 1 and is_equal_approx(float(f.lab.fire_projectiles[0].origin.z), 1.0), "Cross-height shot leaves the original source eye"): return false
		_step(f, 1.4)
		var actual := _flight_result(f)
		evidence.append({"case": "cross_height_raised" if raised else "cross_height_raw", "seed": f.data.seed_value, "result": actual, "observations": observations})
		if not _check(f.contacts.size() == 1 and int(f.contacts[0].target) == target.combat_identity(0)
			and str(f.contacts[0].result.kind) in ["hit", "graze"] and observations.size() == 1
			and str(observations[0].query_stable) == str(observations[0].payload.target_key)
			and is_equal_approx(100.0 - float(target.combat_units[0].hp), float(f.contacts[0].result.hp))
			and f.lab.ranged_shots == 1 and f.lab.ranged_resolutions == 1 and int(source.combat_units[0].cargo.arrow) == 0,
			"A real single-debit cross-height shot reaches the original body with one matching packet", actual): return false
		_candidate_close(f)
		await process_frame
		if finished: return false
	return true

func _real_graze_scout() -> bool:
	var trials: Array[Dictionary] = []
	for seed in range(48):
		var f := _fixture()
		f.data.seed_value = seed
		var source := _team(f, [Vector2i(10, 10)])
		var target := _team(f, [Vector2i(16, 10)], 2, 1, &"bow")
		if failed: return false
		target.facing[0] = Vector2i.LEFT
		source.combat_units[0].cargo.arrow = 1
		var observations := _observe_contacts(f)
		if not _geometry_preflight(f, source, target): return false
		var original_geometry := target.incoming_geometry(0)
		if not _check(not original_geometry.body.is_empty() and original_geometry.shield.is_empty(), "Graze scout uses the actual original body with no shield"): return false
		if not _order(f, source, {"type": "person", "person_id": target.combat_identity(0)}): return false
		if not _await_release(f) or not _stop(f, source): return false
		_step(f, 1.4)
		var trial := {"seed": seed, "source_id": source.combat_identity(0), "target_id": target.combat_identity(0),
			"source_cell": Vector2i(10, 10), "target_cell": Vector2i(16, 10), "target_facing": Vector2i.LEFT,
			"source_appearance": source.equipment_appearance(0), "target_appearance": target.equipment_appearance(0),
			"observations": observations.duplicate(true), "result": _flight_result(f)}
		trials.append(trial)
		var body := not observations.is_empty() and int(observations[0].target) == target.combat_identity(0) and not bool(observations[0].get("shield", true))
		if body and float(observations[0].get("incidence", -1.0)) >= 0.0 and float(observations[0].incidence) < 0.35:
			var ok := _check(f.contacts.size() == 1 and str(f.contacts[0].result.kind) == "graze"
				and int(f.contacts[0].target) == target.combat_identity(0) and f.lab.ranged_shots == 1
				and f.lab.ranged_resolutions == 1 and int(source.combat_units[0].cargo.arrow) == 0
				and str(observations[0].query_stable) == str(observations[0].payload.target_key)
				and is_equal_approx(100.0 - float(target.combat_units[0].hp), float(f.contacts[0].result.hp)),
				"Actual original-body incidence below .35 settles one real graze", trial)
			evidence.append({"case": "real_body_graze_scout", "bounded_seeds": 48, "selected_seed_for_pinning": seed, "trials": trials})
			_candidate_close(f)
			return ok
		_candidate_close(f)
		await process_frame
		if finished: return false
	evidence.append({"case": "real_body_graze_scout", "bounded_seeds": 48, "selected_seed_for_pinning": null, "trials": trials})
	return _check(false, "Bounded 48-seed original-flight scout found no actual graze; gap remains", trials.size())

func _motion_fixture(raised: bool) -> Dictionary:
	var f := _fixture()
	# Descend toward the shot, so the arrow remains above the original raw ground.
	if not _make_ramp(f, Vector2i(15, 10), Vector2i(16, 10), raised): return {}
	var source := _team(f, [Vector2i(10, 10)])
	var target := _team(f, [Vector2i(16, 10)], 2, 1)
	if failed: return {}
	source.combat_units[0].cargo.arrow = 1
	f.lab.combat_movement_coordinator = SiteCombatMovementCoordinator.new()
	for team: TerrainArmy in f.teams: f.lab.combat_movement_coordinator.register_formation(team)
	var observations := _observe_contacts(f)
	if not _order(f, source, {"type": "person", "person_id": target.combat_identity(0)}): return {}
	if not _await_release(f) or not _stop(f, source): return {}
	if not _check(f.lab.fire_projectiles.size() == 1, "Motion fixture has an actual original emitted flight"): return {}
	return {"fixture": f, "source": source, "target": target, "observations": observations,
		"flight": f.lab.fire_projectiles[0], "trajectory": var_to_bytes([f.lab.fire_projectiles[0].origin, f.lab.fire_projectiles[0].velocity, f.lab.fire_projectiles[0].total])}

func _admit_motion(entry: Dictionary, delay: float) -> bool:
	var f: Fixture = entry.fixture
	var target: TerrainArmy = entry.target
	var desired := float(entry.flight.spawn_action) + delay
	_step(f, maxf(0.0, desired - float(f.lab.fire_action_cursor)))
	var requested_action := float(f.lab.fire_action_cursor)
	var accepted := target.issue_combat_order(target.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(15, 10))
	if not _check(accepted.ok, "Original MOVE orders the real ramp step", accepted): return false
	for tick in range(12):
		_step(f, STEP)
		if target.moving_to[0] != TerrainArmy.INVALID_CELL: break
	entry["admission"] = {"requested_action": requested_action, "observed_action": f.lab.fire_action_cursor,
		"flight_pending": not f.lab.fire_projectiles.is_empty(), "progress": float(target.move_progress[0]),
		"order_serial": target.get_order_serial(), "order_delay": target._order_delay}
	return _check(target.moving_to[0] == Vector2i(15, 10) and target.cells[0] == Vector2i(16, 10)
		and target._cell_owners.get(Vector2i(16, 10), -1) == 0 and target._reserved_cells.get(Vector2i(15, 10), -1) == 0
		and f.lab.combat_movement_coordinator.get_inflight_batches_for_formation(target).size() == 1
		and float(target.move_progress[0]) > 0.0 and float(target.move_progress[0]) < 1.0,
		"Original Grid admitted a reserved, physically in-flight ramp step", {"cells": target.cells, "to": target.moving_to, "progress": target.move_progress})

func _motion_pair(raised: bool, delay: float) -> Dictionary:
	var coarse := _motion_fixture(raised)
	var fine := _motion_fixture(raised)
	if coarse.is_empty() or fine.is_empty(): return {}
	if not _admit_motion(coarse, delay) or not _admit_motion(fine, delay): return {}
	var a: Fixture = coarse.fixture
	var b: Fixture = fine.fixture
	var target_a: TerrainArmy = coarse.target
	var target_b: TerrainArmy = fine.target
	if not _check(absf(float(a.lab.fire_action_cursor) - float(b.lab.fire_action_cursor)) < 0.000000001
		and coarse.trajectory == fine.trajectory and target_a.combat_ground(0).distance_to(target_b.combat_ground(0)) < 0.000001,
		"Matched fixtures begin the half-step oracle with identical real state"): return {}
	var samples: Array[Dictionary] = []
	var curved_midpoint := false
	var crossed_boundary := false
	for tick in range(60):
		var before := target_a.combat_ground(0)
		var snapshot := {}
		# Read the same original pre-step projector. The next original Lab step
		# recaptures it itself; this query changes no owner or physical clock.
		if not a.lab.fire_projectiles.is_empty():
			a.lab._capture_fire_motion()
			if a.lab._fire_motion.has(target_a.combat_identity(0)):
				snapshot = a.lab._fire_motion[target_a.combat_identity(0)].duplicate(true)
		_step(a, STEP)
		_step(b, STEP * 0.5)
		var actual_half := target_b.combat_ground(0)
		if not snapshot.is_empty() and not snapshot.motion.is_empty():
			var predicted_half := a.lab._fire_motion_ground(snapshot, 0.5)
			var actual_end := target_a.combat_ground(0)
			var curvature := predicted_half.distance_to(before.lerp(actual_end, 0.5))
			curved_midpoint = curved_midpoint or curvature > 0.0001
			var surface := a.lab._fire_surface_height(predicted_half)
			var crossed := floori(predicted_half.x / TerrainRenderer.CELL_PIXELS) == 15 and surface > 0.0 and surface < 1.0
			crossed_boundary = crossed_boundary or crossed
			var sample := {"action_end": a.lab.fire_action_cursor, "predicted_half": predicted_half, "actual_fine_half": actual_half,
				"coarse_start": before, "coarse_end": actual_end, "curvature_pixels": curvature, "surface_half": surface,
				"visual_surface_half": a.data.surface_visual_offset_at(predicted_half), "crossed_boundary": crossed}
			samples.append(sample)
			if not _check(predicted_half.distance_to(actual_half) < 0.000001,
				"Original coarse curve midpoint equals independently advanced original fine owner", sample): return {}
		_step(b, STEP * 0.5)
		if not _check(target_a.combat_ground(0).distance_to(target_b.combat_ground(0)) < 0.000001
			and absf(float(a.lab.fire_action_cursor) - float(b.lab.fire_action_cursor)) < 0.000000001,
			"Original coarse/fine bodies and action clocks reconverge at interval end"): return {}
		if not a.contacts.is_empty() and not b.contacts.is_empty(): break
	var unchanged: bool = coarse.trajectory == var_to_bytes([coarse.flight.origin, coarse.flight.velocity, coarse.flight.total])
	unchanged = unchanged and fine.trajectory == var_to_bytes([fine.flight.origin, fine.flight.velocity, fine.flight.total])
	if not _check(unchanged, "A real moving target never rewrites either emitted trajectory"): return {}
	var trial := {"raised": raised, "delay": delay, "seed": a.data.seed_value, "samples": samples,
		"curved_midpoint": curved_midpoint, "crossed_boundary": crossed_boundary,
		"coarse_admission": coarse.admission, "fine_admission": fine.admission,
		"coarse_observations": coarse.observations.duplicate(true), "fine_observations": fine.observations.duplicate(true),
		"coarse_result": _flight_result(a), "fine_result": _flight_result(b), "qualified": false,
		"qualification_reason": "No actual cross-cell mid-ramp body contact in both cadences"}
	if not _check(coarse.observations.size() == 1 and fine.observations.size() == 1,
		"Each cadence settles exactly one original flight", trial): return {}
	var first: Dictionary = coarse.observations[0]
	var second: Dictionary = fine.observations[0]
	if not _check(int(first.target) == int(second.target) and str(first.result.kind) == str(second.result.kind)
		and str(first.payload.target_key) == str(second.payload.target_key),
		"Coarse/fine original first-contact identity, key and effect kind agree", trial): return {}
	# Timing inputs are a bounded scout of actual original commands. Admission
	# may be too late, or the trajectory may miss the descending body. Those
	# inputs remain recorded, and cannot count as the cross-cell acceptance.
	# First-contact identity/kind above is mandatory even for such inputs.
	var real_mid_ramp := true
	for observation: Dictionary in [first, second]:
		real_mid_ramp = real_mid_ramp and int(observation.target) == target_a.combat_identity(0)
		real_mid_ramp = real_mid_ramp and not observation.get("motion", {}).is_empty()
		real_mid_ramp = real_mid_ramp and float(observation.get("progress", 0.0)) > 0.0 and float(observation.get("progress", 1.0)) < 1.0
		real_mid_ramp = real_mid_ramp and float(observation.get("surface", 0.0)) > 0.0 and float(observation.get("surface", 1.0)) < 1.0
		if observation.get("ground") is Vector2:
			real_mid_ramp = real_mid_ramp and floori((observation.ground as Vector2).x / TerrainRenderer.CELL_PIXELS) == 15
		else:
			real_mid_ramp = false
	if real_mid_ramp:
		if not _check(curved_midpoint and crossed_boundary and not samples.is_empty(),
			"Qualified contact oracle actually distinguishes original curved motion and crosses the original cell boundary", trial): return {}
		var normal_speed := minf(float(first.get("normal_speed_pixels", 0.0)), float(second.get("normal_speed_pixels", 0.0)))
		var gravity := float(coarse.flight.gravity)
		var chord_error := 2.0 * BODY_CHORD_PIXELS + 48.0 * gravity * (STEP * STEP + pow(STEP * 0.5, 2)) / 8.0
		var time_tolerance := (STEP + STEP * 0.5) / CONTACT_REFINEMENT_STEPS + chord_error / maxf(normal_speed, 0.000001)
		trial["sweep_time_tolerance"] = time_tolerance
		trial["normal_speed_pixels"] = normal_speed
		var error := absf(float(first.payload.action_time) - float(second.payload.action_time))
		trial["contact_time_error"] = error
		if not _check(time_tolerance < STEP * 0.25 and error <= time_tolerance
			and is_equal_approx(float(first.result.hp), float(second.result.hp))
			and is_equal_approx(float(target_a.combat_units[0].hp), float(target_b.combat_units[0].hp)),
			"Contact timing uses the original sweep/chord bound, with the same original owner damage", trial): return {}
		trial.qualified = true
		trial.qualification_reason = "Both original cadences contacted the actual moving body after crossing into cell 15, with curve and strict timing/damage oracle"
	if not _check(a.lab.ranged_shots == 1 and b.lab.ranged_shots == 1 and int(coarse.source.combat_units[0].cargo.arrow) == 0
		and int(fine.source.combat_units[0].cargo.arrow) == 0, "Both motion cadences own one real release and debit"): return {}
	_candidate_close(a)
	_candidate_close(b)
	return trial

func _committed_motion() -> bool:
	for raised: bool in [false, true]:
		var trials: Array[Dictionary] = []
		var selected := -1.0
		# Natural original order delay/admission is retained; earlier requests give
		# the real 0.38-second step time to cross the cell boundary before impact.
		for delay: float in [0.0, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30]:
			var trial := _motion_pair(raised, delay)
			if trial.is_empty(): return false
			trials.append(trial)
			if bool(trial.qualified):
				selected = delay
				break
			await process_frame
			if finished: return false
		evidence.append({"case": "committed_raised_ramp" if raised else "committed_raw_ramp",
			"selected_delay_for_pinning": selected, "trials": trials})
		if not _check(selected >= 0.0, "Bounded real movement inputs produce a true cross-cell mid-ramp body contact", {"raised": raised, "trials": trials}): return false
	return true

func _automatic_decision(f: Fixture) -> void:
	f.lab._resolve_ranged_fire(f.lab._exchange_people(false))

func _assert_reserved_target(f: Fixture, source: TerrainArmy, target: TerrainArmy, label: String) -> bool:
	var identity := source.combat_identity(0)
	if not _check(f.lab.fire_reservations.has(identity) and int(f.lab.fire_reservations[identity].target.person_id) == target.combat_identity(0)
		and int(source.combat_units[0].cargo.arrow) == 1 and f.lab.ranged_shots == 0, label + " selects the original target before debit", f.lab.fire_scheduler_result): return false
	_step(f, STEP)
	return _check(f.lab.ranged_shots == 1 and int(source.combat_units[0].cargo.arrow) == 0
		and f.lab.fire_projectiles.size() == 1 and str(f.lab.fire_projectiles[0].aim_key) == "person:%d" % target.combat_identity(0)
		and source.projectiles.is_empty(), label + " commits through the real NORMAL physical pipeline")

func _normal_friendly_discipline() -> bool:
	for state: String in ["standing", "hidden_presentation", "unconscious"]:
		var f := _fixture()
		var source := _team(f, [Vector2i(10, 10)])
		var friend := _team(f, [Vector2i(13, 10)], 2, 0)
		var target := _team(f, [Vector2i(16, 10)], 3, 1)
		if failed: return false
		source.combat_units[0].cargo.arrow = 1
		if state == "hidden_presentation": friend.visible = false
		if state == "unconscious":
			# Explicit fixture genesis, not a fabricated impact: the original living
			# owner starts KO, and its actual body remains on the firing lane.
			friend.combat_hot_set(0, &"ko", SiteCombatRules.KNOCKOUT_GAME_SECONDS)
			friend.combat_hot_set(0, &"pose", "unconscious")
		if not _check(source.start_unit_attack(0, target.cells[0], target.combat_identity(0)) and source.exchange_ready(0), "Original controlled NORMAL attack is authorized and stationary"): return false
		_automatic_decision(f)
		if not _check(f.lab.fire_reservations.is_empty() and f.lab.ranged_shots == 0 and int(source.combat_units[0].cargo.arrow) == 1,
			"Existing living/KO ally vetoes a NORMAL shot before admission or debit", state): return false
		_step(f, STEP)
		if not _check(f.lab.ranged_shots == 0 and int(source.combat_units[0].cargo.arrow) == 1, "A veto has no deferred debit on the next original interval", state): return false
		evidence.append({"case": "normal_friend_" + state, "result": _flight_result(f), "scheduler": f.lab.fire_scheduler_result.duplicate(true)})
		_candidate_close(f)
	return true

func _normal_selection() -> bool:
	for choice: String in ["nearer_later", "blocked_nearest", "stable_tie", "reversed_tie", "out_of_range"]:
		var f := _fixture()
		var source := _team(f, [Vector2i(10, 10), Vector2i(3, 3)])
		var far_cell := Vector2i(14, 10) if choice in ["stable_tie", "reversed_tie"] else Vector2i(17, 10)
		var near_cell := Vector2i(10, 14) if choice in ["stable_tie", "reversed_tie"] else Vector2i(14, 10)
		if choice == "out_of_range": far_cell = Vector2i(19, 10); near_cell = Vector2i(10, 19)
		var far := _team(f, [far_cell], 2, 1)
		var near := _team(f, [near_cell], 3, 1)
		var other := _team(f, [Vector2i(10, 16) if choice == "blocked_nearest" else Vector2i(25, 10)], 4, 1)
		if choice == "blocked_nearest": _team(f, [Vector2i(12, 10)], 5, 0)
		if failed: return false
		# The original second friendly row is controlled; the original captain
		# follows its normal ATTACK order and can select any authorized hostile.
		f.data.site.controlled_person_id = source.combat_identity(1)
		source.combat_units[0].cargo.arrow = 1
		if not _check(source.issue_combat_order(source.current_commander, TerrainArmy.CombatOrder.ATTACK).ok
			and source.exchange_ready(0) and source.moving_to[0] == TerrainArmy.INVALID_CELL, "Original auto archer is ready before target selection"): return false
		if choice == "reversed_tie": f.lab.combat_armies.assign([source, near, far, other])
		_automatic_decision(f)
		if choice == "out_of_range":
			if not _check(f.lab.fire_reservations.is_empty() and f.lab.ranged_shots == 0 and int(source.combat_units[0].cargo.arrow) == 1,
				"Out-of-range enemies never reserve or consume NORMAL ammunition"): return false
		else:
			var expected: TerrainArmy = other if choice == "blocked_nearest" else (far if choice == "stable_tie" else near)
			if not _assert_reserved_target(f, source, expected, "NORMAL " + choice): return false
			_step(f, 1.4)
			if not _check(f.lab.ranged_resolutions == 1 and f.lab.fire_projectiles.is_empty(), "The automatically selected NORMAL flight settles once"): return false
		evidence.append({"case": "normal_selection_" + choice, "result": _flight_result(f)})
		_candidate_close(f)
	return true

func _normal_orders_and_melee() -> bool:
	for order: int in [TerrainArmy.CombatOrder.ATTACK, TerrainArmy.CombatOrder.PURSUE]:
		var order_fixture := _fixture()
		var order_source := _team(order_fixture, [Vector2i(10, 10), Vector2i(3, 3)])
		var order_target := _team(order_fixture, [Vector2i(16, 10)], 2, 1)
		if failed: return false
		order_fixture.data.site.controlled_person_id = order_source.combat_identity(1)
		order_source.combat_units[0].cargo.arrow = 1
		var accepted := order_source.issue_combat_order(order_source.current_commander, order, TerrainArmy.INVALID_CELL,
			order_target.combat_identity(0) if order == TerrainArmy.CombatOrder.PURSUE else -1)
		if not _check(accepted.ok and order_source.exchange_ready(0) and order_source.moving_to[0] == TerrainArmy.INVALID_CELL,
			"Original ATTACK/PURSUE archer can be stationary and ready", accepted): return false
		_automatic_decision(order_fixture)
		if not _assert_reserved_target(order_fixture, order_source, order_target, "Stationary original order %d" % order): return false
		_step(order_fixture, 1.4)
		if not _check(order_fixture.lab.ranged_resolutions == 1, "Stationary ATTACK/PURSUE produces one real contact"): return false
		evidence.append({"case": "normal_stationary_order", "order": order, "result": _flight_result(order_fixture)})
		_candidate_close(order_fixture)
	# A late adjacent enemy vetoes an earlier legal ranged candidate even while
	# that enemy is cooling down. No readiness change substitutes for this gate.
	var f := _fixture()
	var source := _team(f, [Vector2i(10, 10), Vector2i(3, 3)])
	_team(f, [Vector2i(16, 10)], 2, 1)
	var close_enemy := _team(f, [Vector2i(10, 11)], 3, 1, TerrainArmy.TROOP_TYPE_ID)
	if failed: return false
	f.data.site.controlled_person_id = source.combat_identity(1)
	source.combat_units[0].cargo.arrow = 1
	close_enemy.combat_hot_set(0, &"exchange_cooldown", 0.8) # Fixture starts in an original cooldown.
	if not _check(source.issue_combat_order(source.current_commander, TerrainArmy.CombatOrder.ATTACK).ok and source.exchange_ready(0), "Original archer is ready for late-threat veto"): return false
	_automatic_decision(f)
	if not _check(f.lab.fire_reservations.is_empty() and f.lab.ranged_shots == 0 and int(source.combat_units[0].cargo.arrow) == 1
		and close_enemy.combat_can_act(0) and not close_enemy.exchange_ready(0), "A later adjacent cooling enemy forces close-combat discipline without ammo debit"): return false
	evidence.append({"case": "normal_late_adjacent_cooldown_veto", "scheduler": f.lab.fire_scheduler_result.duplicate(true)})
	_candidate_close(f)
	# A separate original-authority case demonstrates real close defense rather
	# than authoring an attack target for a passive controlled archer.
	f = _fixture()
	source = _team(f, [Vector2i(10, 10)])
	close_enemy = _team(f, [Vector2i(10, 11)], 2, 1, TerrainArmy.TROOP_TYPE_ID)
	if failed: return false
	source.combat_units[0].cargo.arrow = 1
	if not _check(close_enemy.issue_combat_order(close_enemy.current_commander, TerrainArmy.CombatOrder.ATTACK).ok
		and close_enemy.start_unit_attack(0, source.cells[0], source.combat_identity(0)), "Original adjacent enemy explicitly initiates melee"): return false
	f.lab._resolve_exchanges()
	if not _check(f.lab.exchange_count == 1 and f.lab.ranged_shots == 0 and int(source.combat_units[0].cargo.arrow) == 1
		and int(source.combat_units[0].target) == -1, "Original passive controlled archer defends in melee without ranged debit or invented target"): return false
	evidence.append({"case": "normal_original_close_defense", "exchanges": f.lab.exchange_count, "result": _flight_result(f)})
	_candidate_close(f)
	return true

func _normal_discipline() -> bool:
	return _normal_friendly_discipline() and _normal_selection() and _normal_orders_and_melee()
