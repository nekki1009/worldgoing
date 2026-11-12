extends "res://scripts/tests/site_technology_artisan_g06_siege_gates_base.gd"
## Original fixed-source birth and ORIGINAL whole caller. No replacement clock.
## Isolated accepted category input; default world admission remains [].

func _point_prepare(f: Dictionary, reverse: bool) -> Dictionary:
	var kind: String = "siege_tower" if f.category == "F11" else "counterweight_trebuchet"
	var terms: Dictionary = Runtime.SIEGE_DEFINITIONS[kind]
	var supply: Dictionary = terms.cost.duplicate(true)
	for material: String in supply: supply[material] = int(supply[material]) * 2 + 4
	_finite_stock(f, supply) # Explicit finite inputs; zero authored output/work.
	var anchor: Vector2i = _siege_anchor(f, kind, Vector2i(66, 60))
	var second: Vector2i = _siege_anchor(f, kind, Vector2i(82, 60))
	var inventory: Dictionary = f.data.site.inventory.duplicate(true)
	var begun: Dictionary = await _begin_original_siege_ui(f, kind, anchor)
	_require(begun.ok, "Actual explicit original Builder starts a finite full-cost product", begun)
	var key: String = str(begun.vehicle)
	var vehicle: Dictionary = f.data.site.vehicles[key]
	for material: String in terms.cost:
		_require(int(inventory[material]) - int(f.data.site.inventory[material]) == int(terms.cost[material]), "True product pays full original cost exactly once: " + material)
	var work: SiteWorkTeam = f.lab.site_controller.work_team
	_require(work.cancel(int(f.master)).ok, "Original decider releases initial pending master before explicit reordered assignment")
	var before: PackedByteArray = var_to_bytes([f.data.site, _combat_state(f)])
	var duplicate: Dictionary = work.prepare_assign_vehicle(f.team, [int(f.master), int(f.master)], int(f.commander), key)
	_require(not duplicate.ok and var_to_bytes([f.data.site, _combat_state(f)]) == before, "One original person cannot occupy two engineering slots; pure rejection preserves every original byte", duplicate)
	_park(f, int(f.commander), anchor + Vector2i(-4, 0))
	var selected: Array = [int(f.helper), int(f.master)] if reverse else [int(f.master), int(f.helper)]
	_siege_assign(f, key, selected) # Actual owner picks legal distinct slots.
	var tasks: Array = []
	for identity: int in [int(f.master), int(f.helper)]:
		var row: Dictionary = f.team.combat_units[f.team.index_for_identity(identity)]
		tasks.append(row.work_task)
		_require(row.work_task.target == "vehicle:" + key and row.work_task.action == "construct" and _cell_of(f, identity) == f.data.cell_from_index(int(row.work_task.work_cell)), "SAME true person holds and occupies its original fixed work station")
	_require(int(tasks[0].work_slot) != int(tasks[1].work_slot), "No physical engineering slot is shared")
	before = var_to_bytes([f.data.site, _combat_state(f)])
	var second_order: Dictionary = Runtime.begin_siege_build(f.data, kind, second, Vector2i.RIGHT, int(f.team.team_id), int(f.commander), Callable(f.lab.site_controller, "reserves_cell"), false, {}, {}, int(f.master))
	_require(not second_order.ok and var_to_bytes([f.data.site, _combat_state(f)]) == before, "Current original master already holds actual work; a second independently affordable product refuses before cost or ID allocation", second_order)
	return {"key": key, "vehicle": vehicle, "paid": vehicle.build.paid_cost, "terms": terms, "tasks": tasks, "inventory": f.data.site.inventory.duplicate(true)}

func _point_original_delta(f: Dictionary, action_seconds: float) -> Dictionary:
	var action_begin: float = float(f.lab.fire_action_cursor)
	var game_begin: float = Runtime.now(f.data)
	var logical_begin: float = float(f.slot.control.logical_game_seconds)
	f.lab._advance_action_time(action_seconds) # Same original caller subdivides/retains ALL source seconds.
	var fault: Dictionary = f.lab.site_controller.original_step_fault_guard()
	_require(fault.ok, "Original whole caller did not latch a partial-work/clock fault", fault)
	_require(f.lab._region_point_pending.is_empty() and f.lab._shared_work_plan.is_empty(), "True Region/contact/work point is settled; no hand-cleared prefix")
	_require(absf(float(f.lab._action_time_remainder)) < 0.000000001, "Original caller consumed its exact whole fixed-step input; no discarded backlog", {"remainder": float(f.lab._action_time_remainder), "region_pending": f.lab.site_controller.region_operation_pending(), "crossing": f.lab.site_controller.ground_crossing_blocks_clock(), "paused": bool(f.data.site.get("paused", false))})
	var action: float = float(f.lab.fire_action_cursor) - action_begin
	var game: float = (Runtime.now(f.data) - game_begin) * 60.0
	var logical: float = float(f.slot.control.logical_game_seconds) - logical_begin
	_require(absf(action - action_seconds) < 0.000000001 and absf(game - logical) < 0.00000001, "Original action cursor, Site time and checked Slot time agree exactly on accepted input")
	return {"action": action, "game": game, "logical": logical}

func _point_digest(f: Dictionary, held: Dictionary) -> Dictionary:
	var body: Dictionary = f.team.combat_units[f.team.index_for_identity(int(f.master))]
	return {"progress": float(held.vehicle.build.progress), "fatigue": Fatigue.read(body), "rest": Fatigue.read(body, "fatigue_rest"),
		"paid": held.vehicle.build.paid_cost.duplicate(true), "stock": f.data.site.inventory.duplicate(true),
		"site_time": Runtime.now(f.data) * 60.0, "logical_time": float(f.slot.control.logical_game_seconds),
		"action_time": float(f.lab.fire_action_cursor), "next_vehicle": int(f.data.site.next_vehicle), "next_item": int(f.data.site.next_item),
		"learned": body.get("technology", {}).duplicate(true)}

func _point_case(source: RegionData, name: String, chunks: Array, reverse: bool) -> Dictionary:
	var f: Dictionary = _birth(source, _g06_category())
	_fixed_policy_guard(f)
	var held: Dictionary = await _point_prepare(f, reverse)
	var body: Dictionary = f.team.combat_units[f.team.index_for_identity(int(f.master))]
	# Named genuine existing pool INPUT close to 80. Reaching 80 below must be
	# caused by real work in the whole original caller, never a prepared plan write.
	Fatigue.write(body, "fatigue", 79.999)
	Fatigue.write(body, "fatigue_rest", 0.0)
	_require(not bool(body.get("work_resting", false)), "Original newly born master has not been forced into or out of REST")
	var start_game: float = Runtime.now(f.data)
	var total_action := 0.0
	for count: int in chunks:
		var step: Dictionary = _point_original_delta(f, float(count) * TerrainLab.ACTION_STEP)
		total_action += float(step.action)
	_require(absf(total_action - 30.0 * TerrainLab.ACTION_STEP) < 0.000000001 and Runtime.now(f.data) > start_game, "Long/split inputs consume the same real original interval")
	_require(float(held.vehicle.build.progress) > 0.0 and Fatigue.read(body) == Fatigue.WORK_REST_AT, "Actual qualified master works a positive prefix and reaches the true 80 endpoint DURING this original frame")
	_require(is_same(held.vehicle.build.paid_cost, held.paid) and held.vehicle.build.paid_cost == held.terms.cost and f.data.site.inventory == held.inventory, "Whole-point master REST retains SAME full paid cost and original inventory; no repay/refund/extra product")
	var progress: float = float(held.vehicle.build.progress)
	var fatigue: float = Fatigue.read(body)
	var after: Dictionary = _point_original_delta(f, 6.0 * TerrainLab.ACTION_STEP)
	_require(float(after.game) > 0.0 and float(held.vehicle.build.progress) == progress and Fatigue.read(body) == fatigue, "Same real helpers cannot add work OR pool effort in the subsequent settled point while the final qualified master rests")
	var result: Dictionary = _point_digest(f, held)
	result["name"] = name
	result["input_chunks"] = chunks.duplicate()
	result["assignment_reversed"] = reverse
	result["positive_prefix_then_zero"] = true
	_cold_resume(f, "point_" + name) # Actual save/load/full graph bind; no stripped pin.
	var restored: Dictionary = f.data.site.vehicles[held.key]
	_require(absf(float(restored.build.progress) - progress) < 0.000000001 and restored.build.paid_cost == held.terms.cost and f.data.site.world_pin == f.pin and f.data.parameters.fixed_base == f.fixed_base, "Actual full-pin cold read/bind retains pending paid progress, policy and original source")
	_require(Technology.learned(f.team.combat_units[f.team.index_for_identity(int(f.master))].get("technology", {}), str(f.category)) and not Technology.learned(f.team.combat_units[f.team.index_for_identity(int(f.helper))].get("technology", {}), str(f.category)), "Cold binding preserves original learned master and unlearned helper without regrant")
	f.lab.free()
	return result

func _point_equal(a: Dictionary, b: Dictionary) -> void:
	for key: String in ["progress", "fatigue", "rest", "site_time", "logical_time", "action_time"]:
		_require(absf(float(a[key]) - float(b[key])) < 0.00000001, "Original long/split and legitimate opposite person assignment order agree: " + key, {"a": a[key], "b": b[key]})
	for key: String in ["paid", "stock", "next_vehicle", "next_item", "learned"]:
		_require(a[key] == b[key], "No split/order advantage in actual full cost/product/skill identity: " + key)

func _run() -> void:
	_require(_g06_category() in ["F11", "F12"], "This named source-ready test covers the two fixed-buildable original categories")
	_case = {"category": _g06_category(), "formal_release": false, "default_policy": [], "no_generated_soil_or_clock_override": true}
	var source: RegionData = _g06_source()
	_require(source != null, "Original complete checksummed fixed geographic source")
	var split: Array = []
	for tick: int in 30: split.append(1)
	var a: Dictionary = await _point_case(source, "one_frame", [30], false)
	var b: Dictionary = await _point_case(source, "thirty_frames", split, false)
	var c: Dictionary = await _point_case(source, "irregular_frames", [3, 7, 2, 5, 13], false)
	var d: Dictionary = await _point_case(source, "opposite_assignment", [30], true)
	_point_equal(a, b)
	_point_equal(a, c)
	_point_equal(a, d)
	report[_g06_category()] = {"true_work_to_rest_midframe": true, "original_whole_caller": true, "long_split_and_person_order": [a, b, c, d],
		"full_pin_pending_paid_cold": true, "two_engineering_slots_for_one_person_refused": true,
		"scope_limits": "REST endpoint only; geometric midframe KO/death, first-earned G05, F04/F06 paired land/resource, Native, GPU and full G06 remain separate"}
	_finish()

func _finish(reason: String = "") -> void:
	if finished: return
	finished = true
	if not reason.is_empty(): failures.append(reason)
	for lab: TerrainLab in labs:
		if is_instance_valid(lab): lab.free()
	TerrainArmy.release_contact_source()
	print("TECH_AI_02_G06_POINT_ORDER_REPORT: " + JSON.stringify({"checks": checks, "failures": failures, "cases": report,
		"source_epochs": {"lab": FileAccess.get_sha256("res://scripts/terrain_lab/terrain_lab.gd"), "runtime": FileAccess.get_sha256("res://scripts/terrain_lab/site_runtime.gd"), "work": FileAccess.get_sha256("res://scripts/terrain_lab/site_work_team.gd"), "slot": FileAccess.get_sha256("res://scripts/region_lab/region_save_slot.gd"), "env": FileAccess.get_sha256("res://scripts/terrain_lab/site_environment.gd")},
		"full_G06": "OPEN", "default_policy": []}, "", true, true))
	print("TECH_AI_02_G06_POINT_ORDER_", _g06_category(), "_", "PASS" if failures.is_empty() else "FAILED", " scope=true_original_REST_endpoint_long_split_person_order_paid_pending_fullpin_cold_only")
	quit(0 if failures.is_empty() else 1)
