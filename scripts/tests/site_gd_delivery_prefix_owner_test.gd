extends "res://scripts/tests/fixtures/site_food_delivery_first_error_test.gd"
## Original delivery owner / original fixed ACTION_STEP caller. Canonical visual.
## Explicit stationary starting geometry/finite food/fatigue inputs; no movement,
## fixed World birth, Native, real-contact or release-performance claim.
const Fatigue = preload("res://scripts/terrain_lab/person_fatigue.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")

func _initialize() -> void:
	_install_first_error_guard()
	deadline = Time.get_ticks_msec() + 180000
	_run.call_deferred()


func _delivery_lab() -> Dictionary:
	var lab := TerrainLab.new()
	lab.restore_only = true # Build original owners without the implicit map/save boot.
	if not _guard(): return {}
	lab.npc = TerrainTestNPC.new() # Explicit original fixture NPC; formal Lab has no default worker.
	if not _guard(): return {}
	lab.exchange_enabled = false
	lab.fixed_action_steps_enabled = true # This fixture compares the original fixed ACTION_STEP caller.
	lab.pause_when_unfocused = false
	root.add_child(lab)
	if not _guard(): return {}
	if not _require(lab.terrain == null and lab.site_controller.region_slot == null and lab.crowd_site == null, "Explicit fixture boot has no default map/save/Region/Crowd owner"): return {}
	assert(lab.terrain == null and lab.site_controller.region_slot == null and lab.crowd_site == null, "Explicit fixture boot has no default map/save/Region/Crowd owner")
	lab.restore_only = false # Explicit bind and subsequent original live clock/contact ownership stay active.
	lab.visible = true
	var fixture_owners: Array[Node] = [lab, lab.character, lab.npc, lab.site_controller, lab.army, lab.opposing_army]
	for owner: Node in fixture_owners:
		if not _guard(): return {}
		if not _require(is_instance_valid(owner), "Original fixture owner is missing"): return {}
		owner.set_process(false)
		if not _guard(): return {}
	lab.site_controller._auto_save_blocked = true
	var data: TerrainData = _fixture()
	if not _guard(): return {}
	lab.bind_terrain(data)
	if not _guard(): return {}
	lab.site_controller.release_worker()
	if not _guard(): return {}
	lab.npc.faction_id = lab.character.faction_id
	lab.npc.issue_command(TerrainTestNPC.Command.STOP)
	if not _guard(): return {}
	var _delivery_check_1: bool = lab.character.place(Vector2i(21, 22), true) and lab.npc.place(Vector2i(35, 35), true)
	if not _require(_delivery_check_1, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_delivery_lab:29 assertion"): return {}
	assert(_delivery_check_1, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_delivery_lab:29 assertion")
	if not _require(lab.fixed_action_steps_enabled and not lab.exchange_enabled, "Original fixed GD ACTION_STEP mode is explicit"): return {}
	assert(lab.fixed_action_steps_enabled and not lab.exchange_enabled, "Original fixed GD ACTION_STEP mode is explicit")
	var team: TerrainArmy = lab.army
	team.roster_size = 4
	var cells: Array[Vector2i] = [Vector2i(22, 22), Vector2i(23, 22), Vector2i(22, 23), Vector2i(23, 23)]
	if not _guard(): return {}
	var _delivery_check_2: bool = team.deploy_at(data, lab.character, lab.npc, cells) and team.enable_combat(false)
	if not _require(_delivery_check_2, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_delivery_lab:33 assertion"): return {}
	assert(_delivery_check_2, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_delivery_lab:33 assertion")
	team.faction_id = lab.character.faction_id
	team.settle_combat_command()
	if not _guard(): return {}
	data.site.army_next_team = team.team_id + 1 # Explicit deployment's original allocator checkpoint.
	var controller: SiteController = lab.site_controller
	controller.initialize_team_items(team)
	if not _guard(): return {}
	data.site.manual.cargo.clear()
	if not _guard(): return {}
	Runtime.add_items(data.site.manual.cargo, {"grain": 8}) # Finite starting private food only.
	if not _guard(): return {}
	var receiver: int = team.combat_identity(0)
	if not _guard(): return {}
	var _delivery_check_3: bool = lab.controlled_person_id() == lab.character.person_id
	if not _require(_delivery_check_3, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_delivery_lab:42 assertion"): return {}
	assert(_delivery_check_3, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_delivery_lab:42 assertion")
	Fatigue.write(lab.character, "fatigue", 40.0)
	if not _guard(): return {}
	Fatigue.write(team.combat_units[0], "fatigue", 40.003)
	if not _guard(): return {}
	var begun: Dictionary = controller.begin_team_food(team, 4, receiver)
	if not _guard(): return {}
	var _delivery_check_4: bool = begun.ok
	if not _require(_delivery_check_4, str(begun)): return {}
	assert(_delivery_check_4, str(begun))
	var entry: Dictionary = controller._supply_entry(team)
	if not _guard(): return {}
	var _delivery_check_5: bool = entry.delivery.player_id == lab.character.person_id and entry.delivery.representative_id == receiver
	if not _require(_delivery_check_5, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_delivery_lab:48 assertion"): return {}
	assert(_delivery_check_5, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_delivery_lab:48 assertion")
	var _delivery_check_6: bool = is_same(entry.delivery.source_cargo, data.site.manual.cargo) and is_same(entry.delivery.receiver_body, team.combat_units[0])
	if not _require(_delivery_check_6, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_delivery_lab:49 assertion"): return {}
	assert(_delivery_check_6, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_delivery_lab:49 assertion")
	return {"lab": lab, "data": data, "controller": controller, "team": team, "entry": entry, "job": entry.delivery, "receiver": receiver}

func _close(f: Dictionary) -> bool:
	var _delivery_check_7: bool = f.lab._region_point_pending.is_empty() and f.lab._shared_work_plan.is_empty()
	if not _require(_delivery_check_7, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_close:53 assertion"): return false
	assert(_delivery_check_7, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_close:53 assertion")
	f.controller.work_team.discard_prepared_interval()
	if not _guard(): return false
	f.lab.free()
	if not _guard(): return false
	return true

func _digest(f: Dictionary) -> Dictionary:
	return {"source": f.data.site.manual.cargo.duplicate(true), "stock": f.controller._supply_stock(f.entry).duplicate(true),
		"state": f.entry.sustain.duplicate(true), "revision": int(f.entry.revision), "player_fatigue": Fatigue.read(f.lab.character),
		"team_fatigue": Fatigue.read(f.team.combat_units[0]), "at": Runtime.now(f.data), "remaining": f.entry.delivery.duplicate(true)}

func _case(chunks: Array[float]) -> Dictionary:
	var f: Dictionary = _delivery_lab()
	if not _guard(): return {}
	var source: PackedByteArray = var_to_bytes([f.data.site.manual.cargo, f.entry, f.team.capture_combat_state()])
	if not _guard(): return {}
	var projected: Dictionary = f.controller.food_delivery.prepare_completion(f.team, f.entry)
	if not _guard(): return {}
	var _delivery_check_8: bool = projected.ok and f.controller.food_delivery.validate_prepared_completion(projected)
	if not _require(_delivery_check_8, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_case:67 assertion"): return {}
	assert(_delivery_check_8, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_case:67 assertion")
	var _delivery_check_9: bool = var_to_bytes([f.data.site.manual.cargo, f.entry, f.team.capture_combat_state()]) == source
	if not _require(_delivery_check_9, "Original resupply preparation changes no food/life/job/pool"): return {}
	assert(_delivery_check_9, "Original resupply preparation changes no food/life/job/pool")
	var _delivery_check_10: bool = f.controller.food_delivery.prepare_completion(f.team, f.entry, true).code == "INCOMPLETE"
	if not _require(_delivery_check_10, "A source projection is no completed timer witness"): return {}
	assert(_delivery_check_10, "A source projection is no completed timer witness")
	var forged: Dictionary = projected.duplicate(false)
	if not _guard(): return {}
	forged.state = projected.state.duplicate(true)
	if not _guard(): return {}
	forged.state.morale = float(forged.state.morale) + 1.0
	if not _guard(): return {}
	var _delivery_check_11: bool = not f.controller.food_delivery.validate_prepared_completion(forged) and var_to_bytes([f.data.site.manual.cargo, f.entry, f.team.capture_combat_state()]) == source
	if not _require(_delivery_check_11, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_case:73 assertion"): return {}
	assert(_delivery_check_11, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_case:73 assertion")
	forged = projected.duplicate(false)
	if not _guard(): return {}
	forged.entry = f.entry.duplicate(false)
	if not _guard(): return {}
	var _delivery_check_12: bool = not f.controller.food_delivery.validate_prepared_completion(forged)
	if not _require(_delivery_check_12, "Equal amount entry clones are not the original supply owner"): return {}
	assert(_delivery_check_12, "Equal amount entry clones are not the original supply owner")
	var clock_fields: Dictionary = TerrainLab._region_fields(f.lab, TerrainLab.REGION_LAB_FIELDS)
	if not _require(clock_fields.has("_action_step_remaining") and clock_fields._action_step_remaining == f.lab._action_step_remaining,
		"Original Region owner snapshot captures the same fixed-quantum tail"): return {}
	var before: float = Runtime.now(f.data)
	if not _guard(): return {}
	for seconds: float in chunks:
		print("DIAG_ONLY FOOD_CLOCK_INPUT ", {"delta": seconds, "before_minutes": Runtime.now(f.data), "pending_before": f.lab._action_time_remainder})
		if not _guard(): return {}
		f.lab._advance_action_time(seconds)
		if not _guard(): return {}
		if seconds < TerrainLab.ACTION_STEP and chunks[0] == seconds:
			if not _require(Runtime.now(f.data) == before and is_equal_approx(f.lab._action_time_remainder, seconds),
				"A sub-quantum input alone retains its real remainder without advancing the clock"): return {}
		print("DIAG_ONLY FOOD_CLOCK_OUTPUT ", {"after_minutes": Runtime.now(f.data), "pending_after": f.lab._action_time_remainder})
		if not _guard(): return {}
		var _delivery_check_13: bool = f.controller.original_step_fault_guard().ok and f.lab._region_point_pending.is_empty()
		if not _require(_delivery_check_13, "Original complete point leaves no fault/pending checkpoint"): return {}
		assert(_delivery_check_13, "Original complete point leaves no fault/pending checkpoint")
	if not _require(f.lab._action_step_remaining == 0.0, "Every admitted fixed quantum finishes its own unrounded tail"): return {}
	var _delivery_check_14: bool = f.entry.delivery.is_empty() and f.data.site.manual.cargo.grain == 4
	if not _require(_delivery_check_14, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_case:81 assertion"): return {}
	assert(_delivery_check_14, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_case:81 assertion")
	var _delivery_check_15: bool = not f.controller.food_delivery.validate_prepared_completion(projected)
	if not _require(_delivery_check_15, "Original transfer changed the source/version; prospective old candidate cannot be replayed"): return {}
	assert(_delivery_check_15, "Original transfer changed the source/version; prospective old candidate cannot be replayed")
	print("DIAG_ONLY FOOD_CLOCK_BALANCE ", {"requested_actual_seconds": 0.1, "observed_game_seconds": (Runtime.now(f.data) - before) * 60.0, "retained_actual_seconds": f.lab._action_time_remainder, "fixed": f.lab.fixed_action_steps_enabled, "exchange": f.lab.exchange_enabled, "combat_left": f.data.site.combat_left})
	if not _near((Runtime.now(f.data) - before) * 60.0, 6.0, "Original peace clock consumes .1 actual seconds once"): return {}
	var result: Dictionary = _digest(f)
	if not _guard(): return {}
	var repeated: PackedByteArray = var_to_bytes([f.data.site.manual.cargo, f.entry])
	if not _guard(): return {}
	f.controller.settle_supply_deliveries()
	if not _guard(): return {}
	var _delivery_check_16: bool = var_to_bytes([f.data.site.manual.cargo, f.entry]) == repeated
	if not _require(_delivery_check_16, "Actual original terminal repeats with no food/revision effects"): return {}
	assert(_delivery_check_16, "Actual original terminal repeats with no food/revision effects")
	if not _close(f): return {}
	return result

func _state_leaf(value: Variant) -> Dictionary:
	var info: Dictionary = {"type_id": typeof(value), "type": type_string(typeof(value)), "display": str(value), "variant_hex": var_to_bytes(value).hex_encode()}
	if typeof(value) == TYPE_FLOAT:
		var bits: PackedByteArray = PackedByteArray()
		bits.resize(8)
		bits.encode_double(0, float(value))
		info["float64_le"] = bits.hex_encode()
	return info

func _first_state_difference(left: Variant, right: Variant, path: String = "state") -> Dictionary:
	var left_comparison: Dictionary = {"value": left}
	var right_comparison: Dictionary = {"value": right}
	if left_comparison == right_comparison: return {} # Keep Dictionary equality semantics at every nested value.
	if typeof(left) != typeof(right): return {"path": path, "reason": "type", "left": _state_leaf(left), "right": _state_leaf(right)}
	if left is Dictionary:
		var left_keys: Array = left.keys()
		var right_keys: Array = right.keys()
		left_keys.sort_custom(func(a: Variant, b: Variant) -> bool: return var_to_bytes(a).hex_encode() < var_to_bytes(b).hex_encode())
		right_keys.sort_custom(func(a: Variant, b: Variant) -> bool: return var_to_bytes(a).hex_encode() < var_to_bytes(b).hex_encode())
		for right_key: Variant in right_keys:
			if not left.has(right_key): return {"path": path, "reason": "extra_key", "key": _state_leaf(right_key)}
		for key: Variant in left_keys:
			if not right.has(key): return {"path": path, "reason": "missing_key", "key": _state_leaf(key)}
			var dict_difference: Dictionary = _first_state_difference(left[key], right[key], path + "[" + str(key) + "]")
			if not dict_difference.is_empty(): return dict_difference
	elif left is Array:
		if left.size() != right.size(): return {"path": path, "reason": "array_size", "left_size": left.size(), "right_size": right.size()}
		for index: int in left.size():
			var array_difference: Dictionary = _first_state_difference(left[index], right[index], path + "[" + str(index) + "]")
			if not array_difference.is_empty(): return array_difference
	return {"path": path, "reason": "unequal_leaf_or_container", "left": _state_leaf(left), "right": _state_leaf(right)}

func _state_diagnostic_self_check() -> bool:
	var left: Dictionary = {"nested": [{"amount": 1.0}]}
	var right: Dictionary = {"nested": [{"amount": 2.0}]}
	var difference: Dictionary = _first_state_difference(left, right)
	return _require(_first_state_difference(left, left.duplicate(true)).is_empty() and difference.get("path") == "state[nested][0][amount]"
		and difference.left.float64_le != difference.right.float64_le, "Private DIAG finds a real nested float mismatch without changing acceptance")

func _clock_owner_validator_self_check() -> bool:
	var partial: Dictionary = {"_action_time_remainder": 0.006, "_action_step_remaining": 0.004}
	var before: Dictionary = partial.duplicate(true)
	if not _require(TerrainLab._region_action_clock_valid(partial) and partial == before,
		"Real Region clock validator accepts a retained partial quantum without rewriting time"): return false
	if not _require(TerrainLab._region_action_clock_valid({"_action_time_remainder": 0.0})
		and TerrainLab._region_action_clock_valid({"_action_time_remainder": -TerrainLab.ACTION_TIME_EPSILON * 0.5, "_action_step_remaining": 0.0}),
		"Real Region clock validator accepts legacy missing tail and a completed boundary's tiny negative remainder"): return false
	for invalid: Dictionary in [{"_action_time_remainder": 0.0, "_action_step_remaining": 0.02},
		{"_action_time_remainder": 0.01, "_action_step_remaining": 0.02},
		{"_action_time_remainder": 1.0, "_action_step_remaining": TerrainLab.EXCHANGE_ACTION_STEP * 2.0},
		{"_action_time_remainder": 1.0, "_action_step_remaining": -0.001},
		{"_action_time_remainder": 1.0, "_action_step_remaining": NAN},
		{"_action_time_remainder": "0.02", "_action_step_remaining": 0.01},
		{"_action_time_remainder": -TerrainLab.ACTION_TIME_EPSILON * 2.0, "_action_step_remaining": 0.0}]:
		if not _require(not TerrainLab._region_action_clock_valid(invalid), "Real Region clock validator rejects unretained or invalid time"): return false
	return true

func _uncut_original_window_self_check() -> bool:
	var f: Dictionary = _delivery_lab()
	if not _guard(): return false
	var at: float = Runtime.now(f.data)
	for requested: float in [0.0033333333333333375, TerrainLab.ACTION_STEP]:
		var game: float = Runtime.game_seconds(requested, 0.0)
		var collected: Dictionary = f.lab._collect_original_shared_work_requests(requested, game, 0.0)
		f.lab._clear_shared_work_step() # Original owner releases every prospective plan, not a committed step.
		if not _require(collected.ok and collected.action_seconds == requested and collected.game_seconds == game,
			"The real uncut collector preserves the exact action window without inverse-clock residue"): return false
		if not _require(Runtime.now(f.data) == at and f.data.site.manual.cargo.grain == 8,
			"Uncut-window preparation does not spend the original clock or finite food"): return false
	if not _close(f): return false
	return true

func _run() -> void:
	if not _uncut_original_window_self_check(): return
	if not _clock_owner_validator_self_check(): return
	if not _state_diagnostic_self_check(): return
	var whole: Dictionary = _case([0.1])
	if not _guard(): return
	var split: Dictionary = _case([0.04, 0.06])
	if not _guard(): return
	var _delivery_check_17: bool = whole.source == split.source and whole.stock == split.stock and whole.state == split.state and whole.revision == split.revision and whole.remaining.is_empty() and split.remaining.is_empty()
	if not _delivery_check_17:
		print("PREFIX94_FIRST_STATE_DIFFERENCE: ", _first_state_difference(whole.state, split.state))
		print("PREFIX94_STATE_KEY_CONTEXT: ", {"whole": _state_leaf(whole.state.keys()), "split": _state_leaf(split.state.keys())})
		print("PREFIX94_COMPONENTS: ", {"source": whole.source == split.source, "stock": whole.stock == split.stock,
			"state": whole.state == split.state, "revision": whole.revision == split.revision,
			"whole_remaining_empty": whole.remaining.is_empty(), "split_remaining_empty": split.remaining.is_empty()})
		print("PREFIX94_WHOLE: ", whole)
		print("PREFIX94_SPLIT: ", split)
	if not _require(_delivery_check_17, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_run:94 assertion"): return
	assert(_delivery_check_17, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_run:94 assertion")
	if not _near(float(whole.player_fatigue), float(split.player_fatigue), "Source person's real once fatigue is partition invariant"): return
	if not _near(float(whole.team_fatigue), float(split.team_fatigue), "Receiver's original shared pool is partition invariant"): return
	if not _near(float(whole.at), float(split.at), "Once common Site timer"): return
	var fine: Dictionary = _case([0.002, 0.098])
	if not _guard(): return
	if not _require(whole.source == fine.source and whole.stock == fine.stock and whole.state == fine.state and whole.revision == fine.revision,
		"A real sub-quantum input followed by its remainder preserves the same complete delivery result"): return
	var quarters: Dictionary = _case([0.025, 0.025, 0.05])
	if not _guard(): return
	if not _require(whole.source == quarters.source and whole.stock == quarters.stock and whole.state == quarters.state and whole.revision == quarters.revision and quarters.remaining.is_empty(),
		"Original whole and three caller partitions retain the exact food state"): return
	var cancelled: Dictionary = _delivery_lab()
	if not _guard(): return
	cancelled.lab._advance_action_time(TerrainLab.ACTION_STEP)
	if not _guard(): return
	var _delivery_check_18: bool = not cancelled.entry.delivery.is_empty() and float(cancelled.entry.delivery.left) < 2.8 and cancelled.data.site.manual.cargo.grain == 8
	if not _require(_delivery_check_18, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_run:100 assertion"): return
	assert(_delivery_check_18, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_run:100 assertion")
	var _delivery_check_19: bool = cancelled.controller.cancel_team_food().ok
	if not _require(_delivery_check_19, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_run:101 assertion"): return
	assert(_delivery_check_19, "scripts/tests/site_gd_delivery_prefix_owner_test.gd:_run:101 assertion")
	cancelled.lab._advance_action_time(0.1)
	if not _guard(): return
	var _delivery_check_20: bool = cancelled.entry.delivery.is_empty() and cancelled.data.site.manual.cargo.grain == 8
	if not _require(_delivery_check_20, "True cancel consumes no food and never creates a replacement delivery"): return
	assert(_delivery_check_20, "True cancel consumes no food and never creates a replacement delivery")
	if not _close(cancelled): return
	TerrainArmy.release_contact_source()
	if not _guard(): return
	await _finish_pass("GD_CONTACT_DELIVERY_OWNER_PASS scope=original_finite_source_projection_real_joint_maincaller_partition_cancel_once_only contact_native_world_not_claimed")
