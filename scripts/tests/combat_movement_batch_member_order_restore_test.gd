extends SceneTree
## Starting-order markers must roundtrip independently of completion-group order.
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Sustain = preload("res://scripts/terrain_lab/site_sustain.gd")
var checks: int = 0
var owners: Array[TerrainArmy] = []
var coordinators: Array[SiteCombatMovementCoordinator] = []

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, label: String, details: Variant = null) -> bool:
	checks += 1
	if not ok:
		printerr("BATCH MEMBER ORDER FAIL: ", label, " ", details)
	return ok

func _transport(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value, "", true, true))

func _restore(map: TerrainData, saved: Dictionary, expected_move: Array, expected_retreat: Array) -> bool:
	var valid: Dictionary = Store._validate_armies(map, {"actors": {}, "armies": [saved]}, true)
	if not _check(valid.ok and TerrainArmy.valid_combat_state(saved, map), "complete original validators admit the saved owner"): return false
	var restored := TerrainArmy.new()
	# Production armies live in the scene tree; fixtures step them explicitly.
	root.add_child(restored)
	restored.set_process(false)
	restored.roster_size = saved.units.size()
	restored.exchange_enabled = true
	owners.append(restored)
	var coordinator := Coordinator.new()
	coordinators.append(coordinator)
	coordinator.register_formation(restored)
	restored.restore_combat_state(saved.duplicate(true), map, null, null)
	var actual: Dictionary = _transport(restored.capture_combat_state())
	if not _check(actual.get("combat_batch_move_members", []) == expected_move
		and actual.get("combat_batch_retreat_members", []) == expected_retreat,
		"restore preserves exact saved marker sequence and starting orders"): return false
	if not _check(actual.combat_batches == saved.combat_batches
		and _transport(coordinator.get_inflight_batches_for_formation(restored)) == saved.combat_batches,
		"restore preserves every true completion group in its original order"): return false
	if not _check(Store._validate_armies(map, {"actors": {}, "armies": [actual]}, true).ok,
		"the complete recaptured owner remains valid"): return false
	for index in range(saved.units.size()):
		for field: String in ["person_id", "cell", "destination", "progress", "duration", "move_curve"]:
			if not _check(actual.units[index][field] == saved.units[index][field], "physical edge retains " + field): return false
	restored.prepare_combat(0.30)
	coordinator.complete_committed_moves()
	for index in range(saved.units.size()):
		var target: Array = saved.units[index].destination
		if not _check(restored.cells[index] == Vector2i(int(target[0]), int(target[1]))
			and restored.moving_to[index] == TerrainArmy.INVALID_CELL, "the original barrier finishes every restored edge"): return false
	return _check(restored._combat_batch_members.is_empty()
		and coordinator.get_inflight_batches_for_formation(restored).is_empty(), "completion releases all markers and groups")

func _case(order: int) -> bool:
	var map: TerrainData = Helper.build_flat_map(40, 24)
	var count: int = 6 if order == TerrainArmy.CombatOrder.MOVE else 4
	var army: TerrainArmy = Helper.create_test_army(map, 1, 0, count, Vector2i(10, 10))
	owners.append(army)
	var coordinator := Coordinator.new()
	coordinators.append(coordinator)
	coordinator.register_formation(army)
	if order == TerrainArmy.CombatOrder.RETREAT:
		# Explicit initial routed data belongs to the original Site supply owner.
		var members: Dictionary = {}
		var checkpoints: Dictionary = {}
		for row: Dictionary in army.combat_units:
			members[int(row.person_id)] = row
			checkpoints[str(row.person_id)] = 0
		var sustain: Dictionary = Sustain.create(SiteRuntime.now(map) * 60.0)
		if not _check(Sustain.add_members(sustain, members, members.keys()).ok, "original Sustain admits the declared retreat members"): return false
		sustain.morale = 0.0
		sustain.routed = true
		if not map.site.has("team_supply"): map.site.team_supply = {}
		map.site.team_supply[str(army.team_id)] = {"version": 1, "sustain": sustain, "inventory": {},
			"training_order": false, "training_requester": -1, "revision": 0, "delivery": {}, "life_checkpoint": checkpoints}
		army.sustain_routed_query = func(original: TerrainArmy) -> bool:
			return bool(original.data.site.team_supply[str(original.team_id)].sustain.routed)
		if not _check(Sustain.validate(sustain, members) and army.is_sustain_routed(), "declared original routed state passes its unchanged validator"): return false
	var goal := Vector2i(25, 10) if order == TerrainArmy.CombatOrder.MOVE else Vector2i(army.command_reference.floor()) + Vector2i.LEFT
	var issued: Dictionary = army.issue_combat_order(army.current_commander, order, goal)
	if not _check(issued.ok, "original command accepts the declared movement fixture", {"order": order, "result": issued}): return false
	coordinator._rebuild_occupancy()
	var grid: SiteMovementReservationGrid = coordinator.movement_reservation_grid
	grid.begin_tick(coordinator._current_occupancy, map)
	# Both chains/pairs use the real Grid and retain its accepted completion groups.
	var indices: Array = [0, 3, 1, 4, 2, 5] if order == TerrainArmy.CombatOrder.MOVE else [0, 2, 1, 3]
	for index: int in indices:
		var mid: int = army.combat_identity(index)
		var destination: Vector2i = army.cells[index] + (Vector2i.LEFT if index < 3 else Vector2i.RIGHT)
		if order == TerrainArmy.CombatOrder.RETREAT: destination = army.cells[index ^ 1]
		grid.propose_move(army.formation_runtime_id, mid, army.get_order_serial(), army.cells[index], destination)
	grid.resolve_all()
	grid.commit_all(coordinator._member_lookup, 1)
	coordinator._register_started_batches()
	army.prepare_combat(0.10)
	var field: String = "combat_batch_move_members" if order == TerrainArmy.CombatOrder.MOVE else "combat_batch_retreat_members"
	var batches: Array = coordinator.get_inflight_batches_for_formation(army)
	var flattened: Array = []
	for group: Array in batches: flattened.append_array(group)
	if not _check(batches.size() == 2 and flattened.size() == count
		and army._combat_batch_members.size() == count, "real Grid starts all members in two original completion groups"): return false
	# Declare only the live membership-map insertion order. Runtime consumers use
	# membership and starting-order values; the true Grid batches stay untouched.
	var before_members: Dictionary = army._combat_batch_members.duplicate()
	var expected: Array = flattened.duplicate()
	expected.push_front(expected.pop_back())
	var reordered: Dictionary = {}
	for mid: int in expected: reordered[mid] = before_members[mid]
	army._combat_batch_members = reordered
	if not _check(army._combat_batch_members == before_members
		and coordinator.get_inflight_batches_for_formation(army) == batches,
		"declared live marker order changes no identity, starting order, or true batch"): return false
	var saved: Dictionary = _transport(army.capture_combat_state())
	var expected_saved: Array = _transport(expected)
	var flattened_saved: Array = _transport(flattened)
	if not _check(saved.get(field, []) == expected_saved and flattened_saved != expected_saved,
		"actual capture exposes the declared marker order independently of completion-group order",
		{"saved": saved.get(field, []), "expected": expected_saved, "batches_flattened": flattened_saved}): return false
	var unknown: Dictionary = saved.duplicate(true)
	unknown[field].append(999999)
	if not _check(not Store._valid_combat_movement_snapshot(map, unknown, {}), "the original validator rejects a phantom marker identity"): return false
	if not _restore(map, saved, expected_saved if order == TerrainArmy.CombatOrder.MOVE else [], expected_saved if order == TerrainArmy.CombatOrder.RETREAT else []): return false
	if order == TerrainArmy.CombatOrder.MOVE:
		# One-tail chains existed before explicit starting-order marker arrays.
		var legacy: Dictionary = saved.duplicate(true)
		legacy.erase("combat_batch_move_members")
		legacy.erase("combat_batch_retreat_members")
		if not _restore(map, legacy, flattened_saved, []): return false
		var partial: Dictionary = saved.duplicate(true)
		partial.combat_batch_move_members = [expected_saved[1]]
		var fallback: Array = partial.combat_batch_move_members.duplicate()
		for mid: Variant in flattened_saved:
			if not fallback.has(mid): fallback.append(mid)
		if not _restore(map, partial, fallback, []): return false
	return true

func _run() -> void:
	var ok: bool = _case(TerrainArmy.CombatOrder.MOVE) and _case(TerrainArmy.CombatOrder.RETREAT)
	for index in range(owners.size()):
		coordinators[index].unregister_formation(owners[index])
		owners[index].free()
	if ok: print("COMBAT_MOVEMENT_BATCH_MEMBER_ORDER_RESTORE_PASS checks=", checks)
	quit(0 if ok else 1)
