class_name SiteCombatMovementCoordinator
extends RefCounted
## Authoritative Site-level combat movement coordinator.
## Manages shared route search budgets, dynamic movement reservations,
## persistent deployment registries, and executes the 5-stage logic tick pipeline:
## Prepare -> Propose -> Resolve -> Commit -> Finalize.

const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const SiteRouteBudget = preload("res://scripts/terrain_lab/site_route_budget.gd")
const SiteMovementReservationGrid = preload("res://scripts/terrain_lab/site_movement_reservation_grid.gd")
const SiteDeploymentReservationRegistry = preload("res://scripts/terrain_lab/site_deployment_reservation_registry.gd")

const MAX_EGRESS_FIELD_EXPANSIONS := 4096
const MAX_SITE_PLANNING_EXPANSIONS_PER_TICK := 8192

var route_budget: SiteRouteBudget
var movement_reservation_grid: SiteMovementReservationGrid
var deployment_registry: SiteDeploymentReservationRegistry

var _active_formations: Array = []
var _registered_formations: Dictionary = {} # instance_id (int) -> runtime_id (int)
var _formation_by_id: Dictionary = {}       # runtime_id (int) -> formation (Object)
var _next_formation_runtime_id: int = 1

var _member_lookup: Dictionary = {} # member_id -> { "formation": army, "cell": cell }
var _current_occupancy: Dictionary = {} # cell -> member_id
var _retained_occupancy: Dictionary = {} # cell -> member_id (from dissolved formations)

var _egress_search_states: Dictionary = {} # formation_id -> EgressSearchState
var _egress_retry_queue: Array = []        # Array of EgressRetryRequest

var _occupancy_rebuild_pending: bool = false
var _inflight_batches: Array[Array] = [] # Owner and member ID only; cells/progress remain in TerrainArmy.
var current_logic_tick: int = 0
var idle_tick_skip_enabled := true

func _init() -> void:
	route_budget = SiteRouteBudget.new()
	movement_reservation_grid = SiteMovementReservationGrid.new()
	deployment_registry = SiteDeploymentReservationRegistry.new()

func reset_for_site_replacement() -> void:
	# Registered Army nodes survive TerrainLab.set_site; their old cells and
	# leases do not. Restore will repopulate the same coordinator from new rows.
	_retained_occupancy.clear()
	_current_occupancy.clear()
	_member_lookup.clear()
	_inflight_batches.clear()
	_egress_search_states.clear()
	_egress_retry_queue.clear()
	_occupancy_rebuild_pending = true
	movement_reservation_grid = SiteMovementReservationGrid.new()
	deployment_registry = SiteDeploymentReservationRegistry.new()

func register_formation(formation: Object) -> int:
	if formation == null or not is_instance_valid(formation):
		return 0
	var inst_id := formation.get_instance_id()
	var runtime_id: int = 0
	if _registered_formations.has(inst_id):
		runtime_id = _registered_formations[inst_id]
	else:
		runtime_id = _next_formation_runtime_id
		_next_formation_runtime_id += 1
		_registered_formations[inst_id] = runtime_id
		_formation_by_id[runtime_id] = formation
		if not _active_formations.has(formation):
			_active_formations.append(formation)

	if "formation_runtime_id" in formation:
		formation.formation_runtime_id = runtime_id
	if formation.has_method("set_formation_id"):
		formation.set_formation_id(runtime_id)
	if formation.has_method("set_coordinator"):
		formation.set_coordinator(self)

	return runtime_id

func unregister_formation(formation: Object, reason: int = Types.FormationUnregisterReason.LEAVE_SITE) -> void:
	if formation == null:
		return
	restore_inflight_batches_for_formation(formation, [])
	if deployment_registry != null and "team_id" in formation:
		deployment_registry.release_order(int(formation.team_id))
	var inst_id := formation.get_instance_id()
	var runtime_id: int = _registered_formations.get(inst_id, 0)

	if reason == Types.FormationUnregisterReason.LEAVE_SITE or reason == Types.FormationUnregisterReason.SITE_UNLOAD:
		# Clean occupancy: remove this formation's members
		if formation.has_method("get_active_members_occupancy"):
			var occ: Dictionary = formation.get_active_members_occupancy()
			for mid in occ.keys():
				var cell: Vector2i = occ[mid]
				if _current_occupancy.get(cell) == mid:
					_current_occupancy.erase(cell)
				if movement_reservation_grid.committed_occupancy.get(cell) == mid:
					movement_reservation_grid.committed_occupancy.erase(cell)
				_member_lookup.erase(mid)
	elif reason == Types.FormationUnregisterReason.FORMATION_DISSOLVED or reason == Types.FormationUnregisterReason.TRANSFER_MEMBERS:
		# Retain occupancy so remaining soldiers do not become passable ghosts!
		if formation.has_method("get_active_members_occupancy"):
			var occ: Dictionary = formation.get_active_members_occupancy()
			for mid in occ.keys():
				var cell: Vector2i = occ[mid]
				_retained_occupancy[cell] = mid
				_current_occupancy[cell] = mid
				movement_reservation_grid.committed_occupancy[cell] = mid

	if runtime_id > 0:
		invalidate_egress_search_state(runtime_id)
		movement_reservation_grid.cancel_proposals_for_formation(runtime_id)
		_formation_by_id.erase(runtime_id)
	_registered_formations.erase(inst_id)
	_active_formations.erase(formation)

	if formation.has_method("set_coordinator"):
		formation.set_coordinator(null)

func get_active_formations() -> Array:
	return _active_formations

func get_formation_by_id(fid: int) -> Object:
	return _formation_by_id.get(fid, null)

func get_retained_occupancy() -> Dictionary:
	return _retained_occupancy

func request_occupancy_rebuild() -> void:
	_occupancy_rebuild_pending = true

func is_occupancy_rebuild_pending() -> bool:
	return _occupancy_rebuild_pending

func get_egress_search_state(formation_id: int) -> Types.EgressSearchState:
	return _egress_search_states.get(formation_id, null)

func save_egress_search_state(formation_id: int, state: Types.EgressSearchState) -> void:
	if state == null:
		_egress_search_states.erase(formation_id)
	else:
		_egress_search_states[formation_id] = state

func invalidate_egress_search_state(formation_id: int) -> void:
	_egress_search_states.erase(formation_id)
	var filtered: Array = []
	for req in _egress_retry_queue:
		if req.formation_id != formation_id:
			filtered.append(req)
	_egress_retry_queue = filtered

func queue_egress_retry(req: Types.EgressRetryRequest) -> void:
	for r in _egress_retry_queue:
		if r.formation_id == req.formation_id and r.order_serial == req.order_serial:
			return
	_egress_retry_queue.append(req)

func step_egress_planning(max_expansions: int = MAX_SITE_PLANNING_EXPANSIONS_PER_TICK) -> void:
	if _egress_retry_queue.is_empty():
		return
	var expansions_budget := max_expansions
	var processed_count := 0
	var max_formations := 2
	while not _egress_retry_queue.is_empty() and processed_count < max_formations and expansions_budget > 0:
		var req: Types.EgressRetryRequest = _egress_retry_queue.pop_front()
		var formation = _formation_by_id.get(req.formation_id, null)
		if formation != null and is_instance_valid(formation) and formation.has_method("step_egress_search"):
			var used: int = int(formation.step_egress_search(req, expansions_budget))
			expansions_budget -= used
			processed_count += 1

func combat_logic_tick_if_needed(delta: float) -> void:
	# The live battle may have thousands of soldiers but no formation MOVE.
	# Rebuild occupancy on the first active tick, after all idle movement has settled.
	if not idle_tick_skip_enabled or _occupancy_rebuild_pending or not _egress_retry_queue.is_empty():
		combat_logic_tick(delta)
		return
	for formation in _active_formations:
		if not is_instance_valid(formation) or not formation.has_method("get_active_move_plan") or not formation.has_method("get_active_deployment_plan"):
			combat_logic_tick(delta)
			return
		if formation.get_active_move_plan() != null or formation.get_active_deployment_plan() != null \
			or (formation.has_method("has_pending_retreat_pair") and formation.has_pending_retreat_pair()):
			combat_logic_tick(delta)
			return
	current_logic_tick += 1

func combat_logic_tick(delta: float) -> void:
	if _occupancy_rebuild_pending:
		_resolve_occupancy_rebuild_barrier()

	# 1. Prune invalid/freed formations
	var valid_formations: Array = []
	for f in _active_formations:
		if is_instance_valid(f):
			valid_formations.append(f)
	_active_formations = valid_formations

	# 2. Rebuild current occupancy snapshot
	_rebuild_occupancy()

	# Step egress planning for any retry requests
	step_egress_planning(MAX_SITE_PLANNING_EXPANSIONS_PER_TICK)

	# 3. Begin tick for budget, reservation grid, and registry
	route_budget.begin_tick(_active_formations)
	var terrain: Object = null
	var claims: Dictionary = {}
	for formation in _active_formations:
		if "data" in formation and terrain == null:
			terrain = formation.data
		if formation.has_method("get_active_movement_claims"):
			for cell in formation.get_active_movement_claims():
				claims[cell] = true
	movement_reservation_grid.begin_tick(_current_occupancy, terrain, claims)
	deployment_registry.begin_tick(delta)

	current_logic_tick += 1

	# Stage 1: Prepare
	for formation in _active_formations:
		if formation.has_method("prepare_combat_movement_tick"):
			formation.prepare_combat_movement_tick(delta, route_budget, deployment_registry)

	# Stage 2: Propose
	_propose_head_on_side_pocket_yield()
	for formation in _active_formations:
		if formation.has_method("propose_combat_moves"):
			formation.propose_combat_moves(movement_reservation_grid)

	# Stage 3: Resolve (authoritative conflict arbitration)
	movement_reservation_grid.resolve_all()

	# Stage 4: Commit (atomic cell commitment)
	movement_reservation_grid.commit_all(_member_lookup, current_logic_tick)
	_register_started_batches()

	# Stage 5: Finalize
	for formation in _active_formations:
		if formation.has_method("finalize_combat_movement_tick"):
			formation.finalize_combat_movement_tick(delta, movement_reservation_grid, deployment_registry)

	# Check barrier at tick boundary after Finalize
	if _occupancy_rebuild_pending:
		_resolve_occupancy_rebuild_barrier()

func _propose_head_on_side_pocket_yield() -> void:
	# One-person formations can deadlock head-on in a one-cell corridor. Offer
	# one of them a physical perpendicular step before ordinary proposals.
	var candidates: Array[Dictionary] = []
	for formation in _active_formations:
		if not formation.has_method("combat_head_on_single_member_state"):
			continue
		var state: Dictionary = formation.combat_head_on_single_member_state()
		if not state.is_empty():
			state["formation"] = formation
			candidates.append(state)
	for i in range(candidates.size()):
		for j in range(i + 1, candidates.size()):
			var a: Dictionary = candidates[i]
			var b: Dictionary = candidates[j]
			if a.terrain != b.terrain or a.team_id == b.team_id:
				continue
			var toward_b: Vector2i = b.cell - a.cell
			var a_goal_delta: Vector2i = a.final - a.cell
			var b_goal_delta: Vector2i = b.final - b.cell
			if toward_b not in TerrainData.DIRECTIONS \
				or a_goal_delta.x * toward_b.x + a_goal_delta.y * toward_b.y <= 0 \
				or b_goal_delta.x * toward_b.x + b_goal_delta.y * toward_b.y >= 0:
				continue
			var first: Dictionary = b if int(b.team_id) > int(a.team_id) else a
			var second: Dictionary = a if int(b.team_id) > int(a.team_id) else b
			for yielder: Dictionary in [first, second]:
				var other: Dictionary = second if yielder == first else first
				if yielder.formation.propose_combat_side_pocket_yield(
					movement_reservation_grid, other.cell - yielder.cell, deployment_registry
				):
					return

func _register_started_batches() -> void:
	var groups: Dictionary = {}
	for p in movement_reservation_grid.get_proposals():
		if p.status != Types.MoveProposalStatus.ACCEPTED:
			continue
		var root = p
		if movement_reservation_grid.is_same_formation_pair_swap(p):
			# A reciprocal pair has no empty-tail root. Give both participants the
			# same batch so their source cells are cleared at one finish barrier.
			root = movement_reservation_grid.proposal_lookup.get(mini(p.proposal_id, p.dependency_proposal_id))
		else:
			var visited: Dictionary = {}
			while root != null and root.dependency_proposal_id >= 0:
				if visited.has(root.proposal_id):
					root = null
					break
				visited[root.proposal_id] = true
				root = movement_reservation_grid.proposal_lookup.get(root.dependency_proposal_id)
		if root == null:
			continue
		if not groups.has(root.proposal_id):
			groups[root.proposal_id] = []
		groups[root.proposal_id].append({"formation": _member_lookup[p.member_id].formation, "member_id": p.member_id})
	for group in groups.values():
		_inflight_batches.append(group)

func complete_committed_moves() -> void:
	if _inflight_batches.is_empty():
		return
	var pending: Array[Array] = []
	for group: Array in _inflight_batches:
		var terrain_invalid := false
		for entry: Dictionary in group:
			var formation = entry.formation
			if is_instance_valid(formation) and formation.committed_move_terrain_invalid(entry.member_id):
				terrain_invalid = true
				break
		if terrain_invalid:
			var affected_formations: Dictionary = {}
			for entry: Dictionary in group:
				var formation = entry.formation
				if is_instance_valid(formation):
					formation.cancel_committed_move_to_source(entry.member_id)
					affected_formations[formation] = true
			for formation in affected_formations.keys():
				formation.hold_after_invalid_committed_batch()
			_occupancy_rebuild_pending = true
			continue
		var ready := true
		var source_owners: Dictionary = {}
		for entry: Dictionary in group:
			var formation = entry.formation
			var mid: int = entry.member_id
			if not is_instance_valid(formation) or not formation.can_finish_committed_move(mid):
				ready = false
				break
			var index: int = formation.index_for_identity(mid)
			source_owners[formation.cells[index]] = mid
		if not ready:
			pending.append(group)
			continue
		for entry: Dictionary in group:
			var formation = entry.formation
			var index: int = formation.index_for_identity(entry.member_id)
			var destination: Vector2i = formation.moving_to[index]
			var occupant: int = int(_current_occupancy.get(destination, -1))
			if occupant >= 0 and not source_owners.has(destination):
				ready = false
				break
		if not ready:
			push_error("MOVE_BATCH_COMMIT_DESYNC: destination changed during physical step")
			pending.append(group)
			continue
		for entry: Dictionary in group:
			var formation = entry.formation
			var index: int = formation.index_for_identity(entry.member_id)
			formation._cell_owners.erase(formation.cells[index])
		for entry: Dictionary in group:
			entry.formation.finish_committed_move(entry.member_id)
		_occupancy_rebuild_pending = true
	_inflight_batches = pending
	if _occupancy_rebuild_pending:
		_resolve_occupancy_rebuild_barrier()

func get_inflight_batches_for_formation(formation: Object) -> Array:
	var result: Array = []
	for group: Array in _inflight_batches:
		var members: Array[int] = []
		for entry: Dictionary in group:
			if entry.formation == formation:
				members.append(int(entry.member_id))
		if not members.is_empty():
			result.append(members)
	return result

func restore_inflight_batches_for_formation(formation: Object, batches: Array) -> void:
	var retained: Array[Array] = []
	for group: Array in _inflight_batches:
		var owned := false
		for entry: Dictionary in group:
			if entry.formation == formation:
				owned = true
				break
		if not owned:
			retained.append(group)
	_inflight_batches = retained
	for mids: Array in batches:
		var group: Array = []
		for mid: int in mids:
			group.append({"formation": formation, "member_id": mid})
		if not group.is_empty():
			_inflight_batches.append(group)
	request_occupancy_rebuild()

func _resolve_occupancy_rebuild_barrier() -> void:
	_rebuild_occupancy()
	var all_cells: Dictionary = {}
	for mid in _member_lookup.keys():
		all_cells[mid] = _member_lookup[mid]["cell"]
	for cell in _retained_occupancy.keys():
		all_cells[_retained_occupancy[cell]] = cell
	movement_reservation_grid.rebuild_occupancy_from_authoritative(all_cells)
	_occupancy_rebuild_pending = false

func _rebuild_occupancy() -> void:
	_current_occupancy.clear()
	_member_lookup.clear()
	var active_ids: Dictionary = {}
	for formation in _active_formations:
		if formation != null and is_instance_valid(formation) and formation.has_method("get_active_members_occupancy"):
			for mid in formation.get_active_members_occupancy().keys():
				active_ids[mid] = true
	for cell in _retained_occupancy.keys():
		if active_ids.has(_retained_occupancy[cell]):
			_retained_occupancy.erase(cell)

	for cell in _retained_occupancy.keys():
		_current_occupancy[cell] = _retained_occupancy[cell]

	var seen_cells: Dictionary = {}
	for c in _retained_occupancy.keys():
		seen_cells[c] = _retained_occupancy[c]

	for formation in _active_formations:
		if formation == null or not is_instance_valid(formation):
			continue
		if formation.has_method("get_active_members_occupancy"):
			var occ: Dictionary = formation.get_active_members_occupancy()
			for mid in occ.keys():
				var cell: Vector2i = occ[mid]
				if seen_cells.has(cell):
					push_error("Duplicate cell occupancy detected at " + str(cell) + " for member " + str(mid))
					continue
				seen_cells[cell] = mid
				_current_occupancy[cell] = mid
				_member_lookup[mid] = { "formation": formation, "cell": cell }
