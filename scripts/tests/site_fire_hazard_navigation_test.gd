extends SceneTree
## UNRUN output candidate. Runtime heat is deterministic fixture genesis;
## every asserted movement afterward uses original Coordinator/Grid/Army.
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const STEP := 1.0 / 30.0
var checks := 0
var finished := false
var fixtures: Array[Dictionary] = []

class BudgetFormation extends RefCounted:
	var id: int
	func _init(value: int) -> void: id = value
	func get_formation_id() -> int: return id

func _initialize() -> void:
	create_timer(120.0).timeout.connect(func() -> void: _finish(false, "internal deadline"))
	_run.call_deferred()

func _check(ok: bool, label: String, detail: Variant = null) -> bool:
	checks += 1
	if not ok: push_error("FIRE_HAZARD_NAV_FAIL: " + label + " " + str(detail))
	return ok

func _fixture(count: int = 2, size: Vector2i = Vector2i(26, 24)) -> Dictionary:
	var data := Helper.build_flat_map(size.x, size.y)
	# This is a synthetic empty-ground fixture. The shared helper masks
	# generated resources only in static_blocked; later original Runtime
	# rebuilds would correctly restore those unrelated tree obstacles.
	# Remove their genesis before any person, heat unit, or Grid exists.
	data.resource_base.clear()
	data.site.changes.clear()
	SiteEnvironment.rebuild_indexes(data)
	var army := Helper.create_test_army(data, 7, 0, count, Vector2i(3, 3))
	var coordinator := SiteCombatMovementCoordinator.new()
	coordinator.register_formation(army)
	var result := {"data": data, "army": army, "coordinator": coordinator, "now": 0.0}
	fixtures.append(result)
	return result

func _close(f: Dictionary) -> void:
	if not is_instance_valid(f.army): return
	f.coordinator.unregister_formation(f.army)
	f.army.clear()
	f.army.free()
	fixtures.erase(f)

func _finish(ok: bool, reason: String = "") -> void:
	if finished: return
	finished = true
	for f: Dictionary in fixtures.duplicate(): _close(f)
	TerrainArmy.release_contact_source()
	print("SITE_FIRE_HAZARD_NAVIGATION_", "PASS" if ok else "FAIL", ": checks=", checks, " ", reason)
	await process_frame
	quit(0 if ok else 1)

func _heat(f: Dictionary, cell: Vector2i, risk: float = 1.0) -> Dictionary:
	var key := "%d:%d" % [SiteEnvironment.Kind.TIMBER, f.data.index(cell)]
	SiteEnvironment._add_resource(f.data, SiteEnvironment.Kind.TIMBER, f.data.index(cell), 256, 0)
	var state := SiteRuntime._fire_state(f.data, float(f.now))
	var unit := SiteRuntime._fire_unit(f.data, state, SiteRuntime._fire_resource_descriptor(f.data, key))
	SiteEnvironment.change(f.data, key, {"remaining": 0, "cleared": true})
	SiteEnvironment.rebuild_indexes(f.data)
	unit.merge({"profile": "TEST_HEAT_100", "heat": 0.0, "state": "BURNING", "intensity": risk,
		"moisture": 0.0, "residue_q": 256 * SiteRuntime.FIRE_Q}, true)
	state.active["resource:" + key] = true
	SiteRuntime.fire_hazard_invalidate(f.data)
	return unit

func _tick(f: Dictionary) -> void:
	f.now += STEP
	f.data.set_meta(&"fire_completed_action_end", f.now)
	f.coordinator.combat_logic_tick_if_needed(STEP)
	f.army.prepare_combat(STEP, STEP)
	f.coordinator.complete_committed_moves()

func _large_capacity(enough_queue: bool = true) -> bool:
	var f := _fixture(100, Vector2i(16, 206))
	var army: TerrainArmy = f.army
	var plan := CombatDeploymentPlan.new()
	var move := CombatMovePlan.new()
	plan.formation_id = army.team_id
	plan.order_serial = army.get_order_serial()
	plan.structural_platform_capacity = 60
	plan.available_platform_capacity = 60
	plan.requested_count = 100
	plan.ingress_cell = Vector2i(5, 0)
	plan.resolved_anchor = Vector2i(6, 2)
	move.formation_id = army.get_formation_id()
	move.order_serial = plan.order_serial
	move.destination_plan = plan
	move.terrain_revision = f.data.navigation_revision
	move.macro_path.assign([Vector2i(5, 0), Vector2i(6, 0)])
	var targets: Array[Vector2i] = []
	var starts: Array[Vector2i] = []
	var roles := {}
	army._cell_owners.clear()
	for index in range(100):
		var mid := army.combat_identity(index)
		var source := Vector2i(3, index * 2 + 2)
		var target := Vector2i(6, index * 2 + 2) if index < 60 else source
		var role := Types.CombatDestinationRole.PLATFORM if index < 60 else Types.CombatDestinationRole.APPROACH_QUEUE
		starts.append(source)
		targets.append(target)
		army.cells[index] = source
		army.combat_slots[index] = target
		army._cell_owners[source] = index
		plan.member_slot_map[mid] = target
		plan.slot_owner_map[target] = mid
		plan.member_role_map[mid] = role
		roles[target] = role
		if index < 60:
			plan.platform_footprint.append(target)
			plan.platform_slots.append(target)
			plan.pending_platform_member_ids.append(mid)
		else:
			plan.queue_member_ids.append(mid)
		# Exactly 60 safe approach candidates in the positive case: the 40
		# existing queue cells plus 20 vacant queue destinations beside entry.
		if index >= 60 or enough_queue and index >= 40:
			plan.approach_queue_slots.append(source)
		elif index >= 40:
			# Negative genesis removes those 20 final waiting cells by retaining
			# them as the original plan's protected ingress lane. A body may be
			# passing through it; it cannot be counted as a final queue lease.
			plan.ingress_buffer_cells.append(source)
	plan.queue_capacity = plan.approach_queue_slots.size()
	army._combat_move_plan = move
	army._combat_deployment_plan = plan
	army.combat_order = TerrainArmy.CombatOrder.MOVE
	if not _check(plan.structural_platform_capacity == 60 and plan.available_platform_capacity == 60
		and plan.platform_slots.size() == 60 and plan.pending_platform_member_ids.size() == 60
		and plan.queue_member_ids.size() == 40 and plan.approach_queue_slots.size() == (60 if enough_queue else 40),
		"FM05/AT04 exact original genesis: 60 platform members, 40 queued, conditional safe approach capacity"): return false
	if not _check(f.coordinator.deployment_registry.try_replace_reservations(army.team_id, 0, plan.order_serial, targets, roles).ok,
		"Original leases cover 60 platform and 40 actual queue members"): return false
	var retained := {}
	for index in range(100):
		if index < 40 or index >= 60:
			retained[index] = f.coordinator.deployment_registry.owner_of(targets[index])
	# Only now publish deterministic heat on 20 of the original 60 platform
	# obligations. There is no movement, slot rewrite, or re-genesis afterward.
	for index in range(40, 60): _heat(f, targets[index])
	var genesis_snapshot := SiteRuntime.fire_hazard_snapshot(f.data)
	var genesis_failures: Array[Dictionary] = []
	for index in range(100):
		var target := targets[index]
		var risk := SiteRuntime.fire_exposure_at(genesis_snapshot, target, float(f.data.effective_height(target)) + 0.5)
		var expected_risk := 1.0 if index >= 40 and index < 60 else 0.0
		if army.is_controlled_person(index) or not army.combat_can_act(index) or not f.data.is_walkable(starts[index]) \
			or not f.data.is_walkable(target) or risk != expected_risk:
			genesis_failures.append({"index":index,"controlled":army.is_controlled_person(index),
				"can_act":army.combat_can_act(index),"source":starts[index],"target":target,
				"source_walkable":f.data.is_walkable(starts[index]),"target_walkable":f.data.is_walkable(target),"risk":risk})
	if not _check(genesis_failures.is_empty(), "100 autonomous living members; legal physical cells; exactly 20 of 60 platform obligations hot", genesis_failures): return false
	f.coordinator.request_occupancy_rebuild()
	_tick(f)
	var expected_queue := 60 if enough_queue else 40
	var expected_trapped := 0 if enough_queue else 20
	if not _check(plan.platform_slots.size() == 40 and plan.queue_member_ids.size() == expected_queue
		and plan.fire_safe_platform_capacity == 40 and plan.fire_suspended_members.size() == expected_trapped,
		"Only 20 unsafe platform obligations replaced when actual safe queue capacity exists", army.fire_threat_summary()): return false
	if not _check(is_same(army._combat_move_plan, move) and is_same(army._combat_deployment_plan, plan) and not army._is_stall_clock_eligible(),
		"Same original plans retained; avoidance does not accrue ordinary MOVE stall"): return false
	for raw_index: Variant in retained:
		var index := int(raw_index)
		if not _check(is_same(retained[index], f.coordinator.deployment_registry.owner_of(targets[index])),
			"All 80 original safe platform/queue lease identities retained %d" % index): return false
	for index in range(40, 60):
		var mid := army.combat_identity(index)
		if enough_queue:
			var lease: Variant = f.coordinator.deployment_registry.owner_of(starts[index])
			if not _check(plan.member_slot_map.get(mid, TerrainArmy.INVALID_CELL) == starts[index]
				and plan.get_role_for_member(mid) == Types.CombatDestinationRole.APPROACH_QUEUE
				and lease != null and lease.formation_id == army.team_id and lease.order_serial == army.get_order_serial(),
				"Displaced member owns a distinct legal safe queue lease %d" % index): return false
		else:
			var entry: Dictionary = army._fire_navigation.members[mid]
			if not _check(not plan.member_slot_map.has(mid) and f.coordinator.deployment_registry.owner_of(starts[index]) == null
				and entry.target == TerrainArmy.INVALID_CELL and entry.category == "trapped"
				and entry.reason == "NO_SAFE_CAPACITY" and army.moving_to[index] == TerrainArmy.INVALID_CELL,
				"Protected ingress cannot become fictitious safe queue capacity %d" % index, entry): return false
	for tick in range(180): _tick(f)
	var arrived := 0
	var held := 0
	var occupied := {}
	for index in range(100):
		if index < 40 and army.cells[index] == targets[index] and army.moving_to[index] == TerrainArmy.INVALID_CELL: arrived += 1
		if index >= 40 and army.cells[index] == starts[index] and army.moving_to[index] == TerrainArmy.INVALID_CELL: held += 1
		occupied[army.cells[index]] = true
	var summary := army.fire_threat_summary()
	var classified := int(summary.safe_platform) + int(summary.safe_queue) + int(summary.relocating) + int(summary.working) + int(summary.trapped)
	if not _check(arrived == 40 and held == 60 and occupied.size() == 100 and army._reserved_cells.is_empty()
		and summary.safe_platform == 40 and summary.safe_queue == expected_queue and summary.trapped == expected_trapped
		and classified == 100 and summary.active == 100 and army.combat_order == TerrainArmy.CombatOrder.MOVE,
		"Actual 40 safe arrivals; 60 distinct held bodies; capacity-aware mutually exclusive classification",
		{"arrived":arrived,"held":held,"enough_queue":enough_queue,"summary":summary}): return false
	for raw_index: Variant in retained:
		var index := int(raw_index)
		if not _check(is_same(retained[index], f.coordinator.deployment_registry.owner_of(targets[index])),
			"Original safe lease remains identical after actual movement %d" % index): return false
	_close(f)
	return true

func _leases_and_budget() -> bool:
	var registry := SiteDeploymentReservationRegistry.new()
	registry.try_replace_reservations(7, 0, 2, [Vector2i(1, 1), Vector2i(2, 1)])
	registry.try_replace_reservations(8, 0, 3, [Vector2i(4, 1)])
	var safe: Variant = registry.owner_of(Vector2i(1, 1))
	var unsafe: Variant = registry.owner_of(Vector2i(2, 1))
	if not _check(registry.release_fire_unsafe_leases(7, 2, [unsafe]).ok, "Exact unsafe release succeeds"): return false
	var before := registry.capture_handoff_state()
	var failed := registry.try_replace_hazard_subset(7, 2, [], [{"member_id":71,"cell":Vector2i(4,1),"role":0}])
	if not _check(not failed.ok and registry.capture_handoff_state() == before and registry.owner_of(Vector2i(2,1)) == null
		and is_same(safe, registry.owner_of(Vector2i(1,1))), "Replacement conflict never restores old unsafe lease or disturbs safe owner"): return false
	var stale := registry.release_fire_unsafe_leases(7, 2, [unsafe])
	if not _check(not stale.ok and registry.capture_handoff_state() == before, "Stale unsafe handle cannot erase a later owner"): return false
	var budget := SiteRouteBudget.new()
	var formations: Array = []
	for fid in range(1, 66): formations.append(BudgetFormation.new(fid))
	budget.begin_tick(formations)
	if not _check(budget.fire_aging_partition(65, true).calls == 0 and budget.is_scheduler_deferred(65), "Original Site exhaustion gives zero allocation, not no-route"): return false
	budget._formation_allocations[1] = {"remaining_calls":3,"remaining_expansions":101,"calls_used":0,"expansions_used":0,"deferred":false}
	var split := budget.fire_aging_partition(1, true)
	if not _check(split.aging_calls == 2 and split.aging_expansions == 51 and split.other_calls == 1 and split.other_expansions == 50,
		"Odd allocation reserves at least half of both calls and expansions", split): return false
	return true

func _escape_and_generation() -> bool:
	var f := _fixture()
	var army: TerrainArmy = f.army
	var index := 1
	var mid := army.combat_identity(index)
	var source: Vector2i = army.cells[index]
	_heat(f, source)
	var serial := army.get_order_serial()
	var ranged_serial := army.ranged_order_serial
	_tick(f)
	if not _check(army.moving_to[index] != TerrainArmy.INVALID_CELL and army._committed_intent_order(mid) == army.FIRE_HAZARD_STEP
		and army.cells[index] == source and army._reserved_cells.has(army.moving_to[index]) and army._cell_owners.has(source),
		"HOLD fire escape commits through original Grid and retains half-step claims"): return false
	var destination: Vector2i = army.moving_to[index]
	var half := army.move_progress[index]
	# A later original main epoch cannot be rewritten by the old physical edge.
	army._current_order_serial += 1
	army.ranged_order_serial += 1
	army.combat_order = TerrainArmy.CombatOrder.HOLD
	army.combat_slots[index] = destination
	army._fire_nav_reset()
	if not _check(half > 0.0 and half < 1.0 and not army.committed_move_can_change_main_order(mid), "Old inflight provenance detached from new main/ranged epochs"): return false
	for tick in range(20): _tick(f)
	if not _check(army.cells[index] == destination and army.moving_to[index] == TerrainArmy.INVALID_CELL
		and army.get_order_serial() == serial + 1 and army.ranged_order_serial == ranged_serial + 1 and army.combat_order == TerrainArmy.CombatOrder.HOLD,
		"Already committed old edge finishes physically without restoring old command", {"cell":army.cells[index],"expected_cell":destination,"moving":army.moving_to[index],"serial":army.get_order_serial(),"expected_serial":serial+1,"ranged_serial":army.ranged_order_serial,"expected_ranged_serial":ranged_serial+1,"order":army.combat_order,"inflight":f.coordinator.get_inflight_batches_for_formation(army)}): return false
	_close(f)
	return true

func _trapped_and_weighted() -> bool:
	var f := _fixture()
	var army: TerrainArmy = f.army
	var source: Vector2i = army.cells[1]
	_heat(f, source)
	for direction: Vector2i in TerrainData.DIRECTIONS:
		f.data.static_blocked[f.data.index(source + direction)] = 1
	f.data.navigation_revision += 1
	_tick(f)
	var mid := army.combat_identity(1)
	var entry: Dictionary = army._fire_navigation.members[mid]
	if not _check(entry.reason == "NO_SAFE_ROUTE" and entry.category == "trapped" and army.moving_to[1] == TerrainArmy.INVALID_CELL
		and army.combat_order == TerrainArmy.CombatOrder.HOLD, "Exhausted static escape becomes TRAPPED without changing HOLD to RETREAT", entry): return false
	_close(f)
	f = _fixture()
	army = f.army
	var start := Vector2i(10,10)
	var goal := Vector2i(14,10)
	var weighted := func(_from: Vector2i, to: Vector2i) -> int: return 64 if to == Vector2i(12,10) else 0
	var status := {}
	var route := army._find_local_route(start, goal, 256, false, -1, 0, false, null, false, status, weighted)
	if not _check(route.size() == 7 and not route.has(Vector2i(12,10)) and status.outcome == "success", "Original weighted A* chooses the cheaper six-step detour", route): return false
	status = {}
	var capped := army._find_local_route(start, goal, 1, false, -1, 0, false, null, false, status, weighted)
	if not _check(capped.is_empty() and status.capped, "Weighted capped discovery never reports an unproved terminal route"): return false
	_close(f)
	return true

func _inflight_heat_and_hurt(kind: String) -> bool:
	var f := _fixture()
	var army: TerrainArmy = f.army
	var mid := army.combat_identity(1)
	var source: Vector2i = army.cells[1]
	_heat(f, source)
	_tick(f)
	var endpoint: Vector2i = army.moving_to[1]
	if not _check(endpoint != TerrainArmy.INVALID_CELL and army.move_progress[1] > 0.0 and army.move_progress[1] < 1.0, "Original half-step before " + kind): return false
	if kind == "heat":
		_heat(f, endpoint)
		if not _check(not army.committed_move_terrain_invalid(mid), "New heat never invalidates a legal committed terrain edge"): return false
	else:
		army.apply_unit_contact(1, {"environmental":true,"shield":false,"result":{
			"hp":float(army.combat_hot_get(1,&"hp")) + 1.0 if kind == "death" else 0.0,
			"stun":SiteCombatRules.STUN_LIMIT if kind == "ko" else 0.0,"guard_break":false}})
	if not _check(army.cells[1] == source and army._cell_owners.get(source) == 1 and army._reserved_cells.get(endpoint) == 1,
		"Interruption preserves both original half-step claims: " + kind): return false
	# Body-only advance isolates completion from a legitimate next escape step.
	for tick in range(20):
		army.prepare_combat(STEP, STEP)
		f.coordinator.complete_committed_moves()
	if not _check(army.cells[1] == endpoint and army.moving_to[1] == TerrainArmy.INVALID_CELL
		and not army._reserved_cells.has(endpoint) and f.coordinator.get_inflight_batches_for_formation(army).is_empty()
		and army._cell_owners.has(endpoint) == (kind == "heat"), "Original barrier finishes once then releases KO/death occupancy: " + kind): return false
	_close(f)
	return true

func _run() -> void:
	var ok := _leases_and_budget() and _escape_and_generation() and _trapped_and_weighted() and _exposure_summary_endpoint()
	for kind: String in ["heat","ko","death"]:
		if ok: ok = _inflight_heat_and_hurt(kind)
	if ok: ok = _large_capacity()
	if ok: ok = _large_capacity(false)
	_finish(ok)

func _exposure_summary_endpoint() -> bool:
	var f := _fixture()
	var army: TerrainArmy = f.army
	# Actual original damage/death owner; metadata intentionally remains at the
	# previous Runtime boundary while A has finished this exposure interval.
	army.combat_hot_set(0, &"hp", 0.001)
	var hp_before := float(army.combat_hot_get(0,&"hp")) + float(army.combat_hot_get(1,&"hp"))
	var segments: Array[Dictionary] = [{"begin":0.0,"end":STEP,"risk":1.0,"wet":false}]
	for index in range(2):
		var exposure := army.advance_fire_exposure(index,0,0.0,STEP,segments)
		if not _check(exposure.ok, "Original exposure interval accepted for summary"): return false
	var actual_loss := hp_before - float(army.combat_hot_get(0,&"hp")) - float(army.combat_hot_get(1,&"hp"))
	var explicit_summary := army.fire_threat_summary(STEP)
	if not _check(actual_loss > 0.001 and absf(float(explicit_summary.fire_hp_loss) - actual_loss) < 0.00001
		and explicit_summary.fire_deaths == 1 and explicit_summary.action_end == STEP,
		"Explicit completed exposure endpoint reports actual applied HP and one death before P2 finish", explicit_summary): return false
	if not _check(army.fire_threat_summary().fire_hp_loss == 0.0, "Default UI query still uses original completed Runtime cursor"): return false
	var notices: Array[Dictionary] = []
	army.fire_threat_summary_changed.connect(func(summary: Dictionary) -> void: notices.append(summary.duplicate(true)))
	army._publish_fire_threat_summary(STEP)
	army._publish_fire_threat_summary(STEP)
	if not _check(notices.size() == 1 and notices[0].fire_deaths == 1
		and absf(float(notices[0].fire_hp_loss)-actual_loss) < 0.00001,
		"Formation interval summary publishes actual loss exactly once without another clock", notices): return false
	_close(f)
	return true
