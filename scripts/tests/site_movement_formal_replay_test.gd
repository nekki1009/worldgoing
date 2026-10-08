extends "res://scripts/tests/site_movement_batch_parity_test.gd"
## S0 CPU replay of the actual PLAINS 581 / 100 x 3 UI deployment.
## Oracle and single-world timing are separate processes, never FPS evidence.

const FormalFixture = preload("res://scripts/tests/site_tactical_ai_formal_visual_test.gd")
const REPLAY_OUT := "res://output/site_movement_batch_implementation_20260928/revision2/replay"
const WARMUP_STEPS := 30
const CANDIDATE_SWITCHES := ["native_move_intent_enabled", "native_local_route_enabled", "native_movement_projection_enabled"]
const EXTRA_SOURCES := ["res://scripts/tests/site_movement_formal_replay_test.gd",
	"res://scripts/tests/site_movement_batch_parity_test.gd",
	"res://scripts/terrain_lab/site_route_budget.gd",
	"res://scripts/terrain_lab/formation_recovery_controller.gd",
	"res://scripts/terrain_lab/terrain_army_batch_view.gd",
	"res://native/army_idle/movement_core.inc", "res://native/army_idle/movement_transit.inc",
	"res://native/army_idle/movement_projection.inc"]

var _output_path := ""
var _deadline_usec := 0
var _faults: Array[String] = []
var _started_usec := 0
var _serialization_stack := {}

func _initialize() -> void:
	assert(OS.get_cmdline_user_args().has("--site-test-ui"), "This UI deployment replay requires --site-test-ui")
	_started_usec = Time.get_ticks_usec()
	print("FORMAL_REPLAY_PROGRESS initialize usec=", _started_usec)
	_deadline_usec = Time.get_ticks_usec() + 115000000
	_run.call_deferred()

func _mark(stage: String, detail: Dictionary = {}) -> void:
	var progress := {"stage": stage, "elapsed_ms": (Time.get_ticks_usec() - _started_usec) / 1000.0, "detail": detail}
	print("FORMAL_REPLAY_PROGRESS ", JSON.stringify(progress))
	if not _output_path.is_empty():
		var file := FileAccess.open(_output_path + ".progress.json", FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(progress))
			file.close()

func _checkpoint(result: Dictionary) -> void:
	var file := FileAccess.open(_output_path + ".partial.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result))
		file.close()

func _sources() -> Dictionary:
	var result := {}
	for path: String in FormalFixture.SOURCES + EXTRA_SOURCES:
		result[path] = FileAccess.get_sha256(path)
		if str(result[path]).length() != 64:
			_faults.append("Missing source hash: " + path)
	return result

func _fixture(native_enabled: bool) -> Dictionary:
	var label := "candidate" if native_enabled else "reference"
	_mark("fixture.load.begin", {"world": label})
	seed(581)
	FormationTransitPlanner.native_transit_enabled = native_enabled
	var scene: PackedScene = load("res://scenes/terrain_lab/TerrainLab.tscn")
	var owner: TerrainLab = scene.instantiate()
	_mark("fixture.add_child.begin", {"world": label})
	owner.pause_when_unfocused = false
	root.add_child(owner)
	_mark("fixture.add_child.end", {"world": label})
	owner.set_process(false)
	owner.set_process_unhandled_input(false)
	var ui: SiteController = owner.site_controller
	ui._auto_save_blocked = true
	ui.save_path = _output_path + ".isolated_ui_save.json"
	_mark("fixture.generate.begin", {"world": label})
	owner.generate_terrain(TerrainPreset.Kind.PLAINS, 581)
	_mark("fixture.generate.end", {"world": label})
	ui._auto_save_blocked = true
	if owner.terrain.preset != TerrainPreset.Kind.PLAINS or owner.terrain.seed_value != 581:
		_faults.append("Normal Generate did not produce PLAINS 581: " + ui.message.text)
	ui.trial_third_enabled.button_pressed = true
	ui.trial_third_faction.select(2)
	for prefix: String in ["friendly", "enemy", "third"]:
		ui.trial_roles[prefix].select(0)
		ui._trial_role_changed(prefix)
		ui.trial_ai_enabled[prefix].button_pressed = true
	for count: SpinBox in [ui.trial_friendly_count, ui.trial_enemy_count, ui.trial_third_count]:
		count.value = 100
	var button := owner.find_child("StartMeleeTrial", true, false) as Button
	if button == null:
		_faults.append("Original StartMeleeTrial button missing")
	else:
		_mark("fixture.deploy.begin", {"world": label})
		button.pressed.emit()
		_mark("fixture.deploy.end", {"world": label})
	for side in range(3):
		var army: TerrainArmy = owner.combat_armies[side]
		if not army.has_army() or army.combat_units.size() != 100 or not army.tactical_ai_enabled or army.faction_id != side:
			_faults.append("Original UI deployment failed: " + ui.message.text)
		for property: String in CANDIDATE_SWITCHES:
			if not property in army:
				_faults.append("Candidate switch missing: " + property)
			else:
				army.set(property, native_enabled)
		army.combat_profile_enabled = true
		army.combat_profile_usec.clear()
		army.profiled_scheduler_metrics.clear()
	owner.combat_profile_enabled = true
	owner.combat_profile_usec.clear()
	owner.combat_movement_coordinator.profile_enabled = true
	owner.combat_movement_coordinator.profile_usec.clear()
	# No automatic render/physics callbacks interleave the fixed original steps.
	owner.process_mode = Node.PROCESS_MODE_DISABLED
	_mark("fixture.ready", {"world": label, "faults": _faults})
	return {"root": owner, "lab": owner, "coordinator": owner.combat_movement_coordinator,
		"armies": owner.combat_armies, "native": native_enabled, "transit_calls": 0, "transit_fallbacks": 0,
		"terrain_hash": _hash([owner.terrain.height_levels, owner.terrain.static_blocked,
			owner.terrain.ramp_edges, owner.terrain.flags, owner.terrain.surface_types])}

func _script_state(owner: Object) -> Dictionary:
	if owner == null:
		return {}
	var instance := owner.get_instance_id()
	if _serialization_stack.has(instance):
		_faults.append("Oracle serializer found an object cycle: " + str(owner.get_script()))
		return {"serialization_cycle": str(owner.get_script())}
	_serialization_stack[instance] = true
	var result := {}
	# These owners contain scalar/cell containers; engine deep-copy keeps their
	# complete metadata without a GDScript call for every distance-field cell.
	var scalar_containers := owner is CombatMovePlan or owner is CombatDeploymentPlan or owner is SiteRouteBudget
	for property: Dictionary in owner.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0:
			var property_name := str(property.name)
			var property_value: Variant = owner.get(property_name)
			result[property_name] = property_value.duplicate(true) if scalar_containers and (property_value is Dictionary or property_value is Array) else _plain(property_value)
	for meta_name: StringName in owner.get_meta_list():
		var meta_value: Variant = owner.get_meta(meta_name)
		result["@" + str(meta_name)] = meta_value.duplicate(true) if scalar_containers and (meta_value is Dictionary or meta_value is Array) else _plain(meta_value)
	_serialization_stack.erase(instance)
	return result

func _plain(value: Variant, depth: int = 0) -> Variant:
	if depth > 64:
		_faults.append("Oracle serializer found a cyclic or unexpectedly deep container")
		return "SERIALIZATION_DEPTH_FAILURE"
	if value is TerrainArmy:
		return {"formation_id": value.try_get_formation_id()}
	if value is TerrainTestCharacter:
		return {"person_id": value.person_id}
	if value is Object:
		return _script_state(value)
	if value is Dictionary:
		var dictionary_copy := {}
		for key: Variant in value:
			dictionary_copy[key] = _plain(value[key], depth + 1)
		return dictionary_copy
	if value is Array:
		var array_copy := []
		for element: Variant in value:
			array_copy.append(_plain(element, depth + 1))
		return array_copy
	return value

func _state(world: Dictionary) -> Dictionary:
	var result := super._state(world)
	var owner: TerrainLab = world.lab
	var coordinator: SiteCombatMovementCoordinator = world.coordinator
	result["registry"] = _script_state(coordinator.deployment_registry)
	result["budget"] = _script_state(coordinator.route_budget)
	result["egress_states"] = _plain(coordinator._egress_search_states)
	result["egress_queue"] = _plain(coordinator._egress_retry_queue)
	result["all_inflight_batches"] = _plain(coordinator._inflight_batches)
	result["occupancy_rebuild_pending"] = coordinator._occupancy_rebuild_pending
	result["proposal_next_id"] = coordinator.movement_reservation_grid._next_proposal_id
	result["action"] = {"round": owner._exchange_round, "phase": owner._exchange_phase,
		"pending": owner._action_time_remainder, "ai_elapsed": owner._tactical_ai_elapsed,
		"exchange_count": owner.exchange_count, "exchange_results": owner.exchange_results.duplicate(),
		"site_clock": owner.terrain.site.get("combat_left", 0.0)}
	var actors := []
	for actor: TerrainTestCharacter in owner.combat_actors:
		var row := {}
		for property: String in ["person_id", "faction_id", "terrain_cell", "movement_from_cell",
			"_movement_duration", "_movement_elapsed", "hp", "knockout_left", "stun", "fatigue",
			"exchange_cooldown", "exchange_stagger", "ranged_cooldown", "action_time", "facing"]:
			row[property] = actor.get(property)
		actors.append(row)
	result["actors"] = actors
	for side in range(3):
		var army: TerrainArmy = world.armies[side]
		var move_plan := army.get_active_move_plan()
		if move_plan != null and move_plan.has_meta("_transit_exact_path_indices"):
			var cache: Dictionary = move_plan.get_meta("_transit_exact_path_indices")
			if not is_same(cache.get("path"), move_plan.macro_path):
				_faults.append("Path-index cache detached from original macro_path")
		var row: Dictionary = result.teams[side]
		row["hot_people"] = []
		for index in range(army.combat_units.size()):
			var person := {"id": army.combat_identity(index)}
			for field: StringName in TerrainArmy.COMBAT_HOT_FIELDS:
				person[field] = _plain(army.combat_hot_get(index, field))
			row.hot_people.append(person)
		for property: String in ["combat_goal", "team_fatigue", "current_commander", "needs_attack_order",
			"command_reference", "command_reference_valid", "desired_cells",
			"_command_elapsed", "_move_landed_members", "_retreat_pairs_used", "tactical_ai_enabled",
			"tactical_ai_recovering", "tactical_ai_order_cooldown", "tactical_ai_chase_cooldown",
			"tactical_ai_target_id", "tactical_ai_decisions", "tactical_ai_orders",
			"_follower_routes", "_follower_route_goals", "_follower_route_cursors"]:
			row[property] = _plain(army.get(property))
	return result

func _hash(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()

func _advance(world: Dictionary) -> int:
	FormationTransitPlanner.native_transit_enabled = bool(world.native)
	var calls_before := FormationTransitPlanner.native_transit_calls
	var fallbacks_before := FormationTransitPlanner.native_transit_fallbacks
	var started := Time.get_ticks_usec()
	world.lab._advance_action_time(STEP)
	var elapsed := Time.get_ticks_usec() - started
	world.transit_calls += FormationTransitPlanner.native_transit_calls - calls_before
	world.transit_fallbacks += FormationTransitPlanner.native_transit_fallbacks - fallbacks_before
	return elapsed

func _coverage(world: Dictionary) -> Dictionary:
	var result := {"transit_calls": world.transit_calls, "transit_fallbacks": world.transit_fallbacks}
	for army: TerrainArmy in world.armies:
		var row := {"field_intent_hits": army.native_move_intent_hits,
			"local_route_hits": army.native_local_route_hits,
			"roster_calls": army.native_movement_roster_calls,
			"cursor_projection_calls": army.native_movement_projection_calls,
			"scheduler": army.profiled_scheduler_metrics.duplicate(true),
			"stage_usec": army.combat_profile_usec.duplicate(), "switches": {}}
		for property: String in CANDIDATE_SWITCHES:
			row.switches[property] = army.get(property)
		result[str(army.team_id)] = row
	return result

func _oracle(reference_only: bool) -> Dictionary:
	var reference := _fixture(false)
	var candidate := _fixture(not reference_only)
	var oracle_kernel := TerrainArmy._get_idle_kernel()
	if oracle_kernel == null or not oracle_kernel.has_method("exact_value_equal"):
		_faults.append("Existing exact native oracle unavailable")
	var result := {"mode": "oracle_reference" if reference_only else "oracle", "steps": [],
		"first_difference": "", "terrain_reference": reference.terrain_hash,
		"terrain_candidate": candidate.terrain_hash, "timings_are_not_performance_evidence": true}
	for step in range(STEPS + 1):
		if not _faults.is_empty() or Time.get_ticks_usec() >= _deadline_usec:
			_faults.append("Oracle aborted or exceeded bounded deadline at step " + str(step))
			break
		if step > 0:
			_advance(reference)
			_advance(candidate)
		var trace_state := step <= 2 or step % 50 == 0
		if trace_state:
			_mark("oracle.state.reference.begin", {"step": step})
		var left := _state(reference)
		if trace_state:
			_mark("oracle.state.candidate.begin", {"step": step})
		var right := _state(candidate)
		if trace_state:
			_mark("oracle.state.compare.begin", {"step": step})
		var exact: int = int(oracle_kernel.exact_value_equal(left, right))
		var difference := ""
		if exact == 0:
			difference = _first_difference(left, right)
			if difference.is_empty():
				difference = "state exact scalar bits or typed-container metadata"
		elif exact != 1:
			difference = "state contains an unsupported oracle value"
		result.steps.append({"step": step, "reference_hash": _hash(left), "candidate_hash": _hash(right)})
		if trace_state:
			_mark("oracle.step.complete", {"step": step, "difference": difference})
			_checkpoint(result)
		if not difference.is_empty():
			result.first_difference = difference
			result["first_difference_step"] = step
			# One pair only: enough to inspect the first failure without 450 full dumps.
			var evidence := FileAccess.open(_output_path + ".first_difference.txt", FileAccess.WRITE)
			if evidence != null:
				evidence.store_string("REFERENCE\n" + var_to_str(left) + "\nCANDIDATE\n" + var_to_str(right))
				evidence.close()
			_faults.append("Owner parity differs: step %d, %s" % [step, difference])
			break
	result["reference_coverage"] = _coverage(reference)
	result["candidate_coverage"] = _coverage(candidate)
	_checkpoint(result)
	_mark("dispose.reference.begin")
	_dispose(reference)
	_mark("dispose.candidate.begin")
	_dispose(candidate)
	_mark("dispose.complete")
	return result

func _timing(native_enabled: bool) -> Dictionary:
	var world := _fixture(native_enabled)
	var owner: TerrainLab = world.lab
	_mark("timing.initial_state.begin")
	var result := {"mode": "candidate" if native_enabled else "reference", "steps": [],
		"terrain_hash": world.terrain_hash, "initial_state_hash": _hash(_state(world)),
		"warmup_steps": WARMUP_STEPS, "state_hashing_inside_timed_steps": false}
	_mark("timing.initial_state.end")
	for step in range(1, STEPS + 1):
		if not _faults.is_empty() or Time.get_ticks_usec() >= _deadline_usec:
			_faults.append("Timing aborted or exceeded bounded deadline at step " + str(step))
			break
		var coordinator_before := int(owner.combat_profile_usec.get("movement_coordinator", 0))
		var elapsed := _advance(world)
		result.steps.append({"step": step, "warmup": step <= WARMUP_STEPS,
			"action_usec": elapsed, "coordinator_usec": int(owner.combat_profile_usec.get("movement_coordinator", 0)) - coordinator_before})
		if step == WARMUP_STEPS:
			# Keep raw warmup steps, but exclude them from stage aggregates as well.
			owner.combat_profile_usec.clear()
			world.coordinator.profile_usec.clear()
			for army: TerrainArmy in owner.combat_armies:
				army.combat_profile_usec.clear()
		if step % 50 == 0:
			_mark("timing.step.complete", {"step": step})
			_checkpoint(result)
	_mark("timing.final_state.begin")
	result["final_state_hash"] = _hash(_state(world))
	_mark("timing.final_state.end")
	result["coverage"] = _coverage(world)
	result["lab_stage_usec"] = owner.combat_profile_usec.duplicate()
	result["coordinator_stage_usec"] = world.coordinator.profile_usec.duplicate()
	_checkpoint(result)
	_mark("dispose.begin")
	_dispose(world)
	_mark("dispose.complete")
	return result

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var valid: bool = args == PackedStringArray(["--oracle"]) or args == PackedStringArray(["--oracle-reference"]) \
		or args == PackedStringArray(["--timing", "--reference"]) or args == PackedStringArray(["--timing", "--candidate"])
	if not valid:
		push_error("Use --oracle, --oracle-reference, or --timing --reference/--candidate")
		quit(1)
		return
	if ProjectSettings.get_setting("application/run/main_scene") != "res://scenes/terrain_lab/TerrainLab.tscn":
		push_error("Formal TerrainLab entry changed")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPLAY_OUT))
	_output_path = "%s/%s_%d_%d.json" % [REPLAY_OUT, "_".join(args).replace("--", ""), int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
	_mark("run.begin")
	var sources_before := _sources()
	var result := _oracle(args.has("--oracle-reference")) if args.has("--oracle") or args.has("--oracle-reference") else _timing(args.has("--candidate"))
	var sources_after := _sources()
	if sources_before != sources_after:
		_faults.append("Source changed during replay")
	result.merge({"revision": 2, "steps_requested": STEPS, "step_seconds": STEP,
		"scope": "Formal TerrainLab UI PLAINS 581, 100 x 3, fixed original action CPU replay; not FPS",
		"sources_before": sources_before, "sources_after": sources_after,
		"engine": Engine.get_version_info(), "cpu": OS.get_processor_name(), "arguments": args,
		"faults": _faults, "passed": _faults.is_empty()}, true)
	var file := FileAccess.open(_output_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write replay evidence")
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	TerrainArmy.release_contact_source()
	print("FORMAL_MOVEMENT_REPLAY ", "PASS" if _faults.is_empty() else "FAIL", " ", _output_path)
	if not _faults.is_empty():
		push_error(str(_faults))
	quit(0 if _faults.is_empty() else 1)
