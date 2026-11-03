class_name SiteCombatMovementCoordinator
extends RefCounted
## Authoritative Site-level combat movement coordinator.
## Manages shared route search budgets, dynamic movement reservations,
## persistent deployment registries, and executes the 5-stage logic tick pipeline:
## Prepare -> Propose -> Resolve -> Commit -> Finalize.

const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const RouteBudgetScript = preload("res://scripts/terrain_lab/site_route_budget.gd")
const MovementReservationGridScript = preload("res://scripts/terrain_lab/site_movement_reservation_grid.gd")
const DeploymentReservationRegistryScript = preload("res://scripts/terrain_lab/site_deployment_reservation_registry.gd")

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
var shared_blocker_index_enabled := true # A/B: original per-team blocker readers remain the fallback.
var shared_blocker_index_attempts := 0
var shared_blocker_index_builds := 0
var shared_blocker_index_copied_maps := 0
var profile_enabled := false # Optional diagnostics only; never a movement budget.
var profile_usec: Dictionary = {}

func _profile_stage(stage: String, started: int) -> int:
	if not profile_enabled:
		return 0
	var now := Time.get_ticks_usec()
	profile_usec[stage] = int(profile_usec.get(stage, 0)) + now - started
	return now

func _init() -> void:
	route_budget = RouteBudgetScript.new()
	movement_reservation_grid = MovementReservationGridScript.new()
	deployment_registry = DeploymentReservationRegistryScript.new()

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
	movement_reservation_grid = MovementReservationGridScript.new()
	deployment_registry = DeploymentReservationRegistryScript.new()

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

## Local rollback for a synchronous same-Site handoff. Formation body state and
## deployment leases are captured by their existing owners separately.
func capture_handoff_state() -> Dictionary:
	return {"active_formations": _active_formations.duplicate(),
		"registered_formations": _registered_formations.duplicate(), "formation_by_id": _formation_by_id.duplicate(),
		"next_formation_runtime_id": _next_formation_runtime_id,
		"member_lookup": _member_lookup.duplicate(true), "current_occupancy": _current_occupancy.duplicate(),
		"retained_occupancy": _retained_occupancy.duplicate(), "inflight_batches": _inflight_batches.duplicate(),
		"egress_search_states": _egress_search_states.duplicate(), "egress_retry_queue": _egress_retry_queue.duplicate(),
		"occupancy_rebuild_pending": _occupancy_rebuild_pending,
		"grid_committed_occupancy": movement_reservation_grid.committed_occupancy.duplicate()}

func validate_handoff_formations(returning_formations: Array) -> Dictionary:
	# A physical batch may cross formation boundaries. The ordinary per-team
	# restorer removes whole groups, so never split a foreign in-flight batch.
	for group: Array in _inflight_batches:
		var returning := false
		var foreign := false
		for entry: Dictionary in group:
			if returning_formations.has(entry.formation): returning = true
			else: foreign = true
		if returning and foreign:
			return {"ok": false, "reason": "RETURN_BATCH_CONFLICT"}
	return {"ok": true}

func restore_handoff_state(snapshot: Dictionary) -> void:
	# No tick/proposal processing occurs between capture and rollback. Keep the
	# same Grid and registry, including every foreign proposal, batch and lease.
	for formation: Variant in _active_formations:
		if not is_instance_valid(formation) or snapshot.active_formations.has(formation): continue
		if formation.has_method("set_coordinator"): formation.set_coordinator(null)
		if formation.has_method("set_formation_id"): formation.set_formation_id(0)
	_active_formations.assign(snapshot.active_formations)
	_registered_formations.clear()
	_registered_formations.merge(snapshot.registered_formations)
	_formation_by_id.clear()
	_formation_by_id.merge(snapshot.formation_by_id)
	_next_formation_runtime_id = int(snapshot.next_formation_runtime_id)
	for formation: Variant in _active_formations:
		register_formation(formation)
	_member_lookup.clear()
	_member_lookup.merge(snapshot.member_lookup.duplicate(true))
	_current_occupancy.clear()
	_current_occupancy.merge(snapshot.current_occupancy)
	_retained_occupancy.clear()
	_retained_occupancy.merge(snapshot.retained_occupancy)
	_inflight_batches.assign(snapshot.inflight_batches)
	_egress_search_states.clear()
	_egress_search_states.merge(snapshot.egress_search_states)
	_egress_retry_queue.assign(snapshot.egress_retry_queue)
	_occupancy_rebuild_pending = bool(snapshot.occupancy_rebuild_pending)
	movement_reservation_grid.committed_occupancy.clear()
	movement_reservation_grid.committed_occupancy.merge(snapshot.grid_committed_occupancy)

func resolve_occupancy_rebuild_checked() -> Dictionary:
	# Validate in locals first. The legacy barrier reports duplicates only after
	# clearing live occupancy; a handoff must be able to reject without doing so.
	var members: Dictionary = {}
	var cells: Dictionary = {}
	for formation: Variant in _active_formations:
		if not is_instance_valid(formation) or not formation.has_method("get_active_members_occupancy"): continue
		var occupancy: Dictionary = formation.get_active_members_occupancy()
		for mid: int in occupancy:
			var cell: Vector2i = occupancy[mid]
			if members.has(mid):
				return {"ok": false, "reason": "DUPLICATE_MEMBER", "member_id": mid}
			if cells.has(cell):
				return {"ok": false, "reason": "CELL_CONFLICT", "cell": cell, "member_ids": [cells[cell], mid]}
			members[mid] = {"formation": formation, "cell": cell}
			cells[cell] = mid
	var retained: Dictionary = {}
	var retained_ids: Dictionary = {}
	for cell: Vector2i in _retained_occupancy:
		var mid: int = int(_retained_occupancy[cell])
		if members.has(mid): continue # Rejoined members release their old retained cell.
		if retained_ids.has(mid):
			return {"ok": false, "reason": "DUPLICATE_MEMBER", "member_id": mid}
		if cells.has(cell):
			return {"ok": false, "reason": "CELL_CONFLICT", "cell": cell, "member_ids": [cells[cell], mid]}
		retained[cell] = mid
		retained_ids[mid] = true
		cells[cell] = mid
	var all_cells: Dictionary = {}
	for cell: Vector2i in cells:
		all_cells[cells[cell]] = cell
	_member_lookup.clear()
	_member_lookup.merge(members)
	_current_occupancy.clear()
	_current_occupancy.merge(cells)
	_retained_occupancy.clear()
	_retained_occupancy.merge(retained)
	movement_reservation_grid.rebuild_occupancy_from_authoritative(all_cells)
	_occupancy_rebuild_pending = false
	return {"ok": true}

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

func combat_logic_tick_if_needed(delta: float, external_blocked_cells: Dictionary = {}) -> void:
	for transport: Object in _siege_transports():
		if transport.has_pending_siege_compounds():
			combat_logic_tick(delta, external_blocked_cells)
			return
	# The live battle may have thousands of soldiers but no formation MOVE.
	# Rebuild occupancy on the first active tick, after all idle movement has settled.
	if not idle_tick_skip_enabled or _occupancy_rebuild_pending or not _egress_retry_queue.is_empty():
		combat_logic_tick(delta, external_blocked_cells)
		return
	for formation in _active_formations:
		if is_instance_valid(formation) and (formation.has_pending_suppress_approach() or formation.has_pending_fire_navigation()):
			combat_logic_tick(delta, external_blocked_cells)
			return
		if not is_instance_valid(formation) or not formation.has_method("get_active_move_plan") or not formation.has_method("get_active_deployment_plan"):
			combat_logic_tick(delta, external_blocked_cells)
			return
		if formation.get_active_move_plan() != null or formation.get_active_deployment_plan() != null \
			or (formation.has_method("has_pending_retreat_pair") and formation.has_pending_retreat_pair()):
			combat_logic_tick(delta, external_blocked_cells)
			return
	current_logic_tick += 1

func _siege_transports() -> Array[Object]:
	var result: Array[Object] = []
	for formation: Object in _active_formations:
		if is_instance_valid(formation) and "vehicle_transport" in formation and formation.vehicle_transport != null and not result.has(formation.vehicle_transport):
			result.append(formation.vehicle_transport)
	return result

## Option C gate: an empty or combat-disabled grid team (the Lab's default army) holds no simulation to refuse.
func _has_member_formation() -> bool:
	for formation: Object in _active_formations:
		if is_instance_valid(formation) and formation is TerrainArmy and formation.combat_enabled and not formation.combat_units.is_empty(): return true
	return false

func combat_logic_tick(delta: float, external_blocked_cells: Dictionary = {}) -> void:
	if (_has_member_formation() or not _inflight_batches.is_empty() or not _egress_retry_queue.is_empty()) and TerrainArmy.grid_simulation_retired("SiteCombatMovementCoordinator.combat_logic_tick"): return
	var stage_started := Time.get_ticks_usec() if profile_enabled else 0
	if _occupancy_rebuild_pending:
		_resolve_occupancy_rebuild_barrier()
		stage_started = _profile_stage("barrier", stage_started)

	# 1. Prune invalid/freed formations
	var valid_formations: Array = []
	for f in _active_formations:
		if is_instance_valid(f):
			valid_formations.append(f)
	_active_formations = valid_formations
	stage_started = _profile_stage("setup", stage_started)

	# 2. Rebuild current occupancy snapshot
	_rebuild_occupancy()
	stage_started = _profile_stage("occupancy", stage_started)

	# Step egress planning for any retry requests
	step_egress_planning(MAX_SITE_PLANNING_EXPANSIONS_PER_TICK)
	stage_started = _profile_stage("egress", stage_started)

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
	for cell in external_blocked_cells:
		claims[cell] = true
	movement_reservation_grid.begin_tick(_current_occupancy, terrain, claims)
	deployment_registry.begin_tick(delta)

	current_logic_tick += 1
	stage_started = _profile_stage("begin", stage_started)

	# Stage 1: Prepare
	for formation in _active_formations:
		if formation.has_method("begin_combat_movement_read_scope"):
			formation.begin_combat_movement_read_scope()
	var blocker_started := Time.get_ticks_usec() if profile_enabled else 0
	_publish_shared_blocker_index()
	if profile_enabled:
		_profile_stage("shared_blocker_index", blocker_started)
	for formation in _active_formations:
		if formation.has_method("prepare_combat_movement_tick"):
			formation.prepare_combat_movement_tick(delta, route_budget, deployment_registry)
	stage_started = _profile_stage("prepare", stage_started)

	# Stage 2: Propose
	_propose_head_on_side_pocket_yield()
	for formation in _active_formations:
		if formation.has_method("propose_combat_moves"):
			formation.propose_combat_moves(movement_reservation_grid)
	for transport: Object in _siege_transports():
		transport.propose_siege_compounds(movement_reservation_grid)
	stage_started = _profile_stage("propose", stage_started)
	# Resolve/Commit may change the original claims. The shared view ends before
	# that boundary even though the member-roster read scope lasts through Finalize.
	for formation in _active_formations:
		if formation.has_method("clear_shared_movement_blockers"):
			formation.clear_shared_movement_blockers()

	# Stage 3: Resolve (authoritative conflict arbitration)
	movement_reservation_grid.resolve_all()
	stage_started = _profile_stage("resolve", stage_started)

	# Stage 4: Commit (atomic cell commitment)
	movement_reservation_grid.commit_all(_member_lookup, current_logic_tick)
	_register_started_batches()
	stage_started = _profile_stage("commit_register", stage_started)

	# Stage 5: Finalize
	for formation in _active_formations:
		if formation.has_method("finalize_combat_movement_tick"):
			formation.finalize_combat_movement_tick(delta, movement_reservation_grid, deployment_registry)
	for formation in _active_formations:
		if formation.has_method("end_combat_movement_read_scope"):
			formation.end_combat_movement_read_scope()
	stage_started = _profile_stage("finalize", stage_started)

	# Check barrier at tick boundary after Finalize
	if _occupancy_rebuild_pending:
		_resolve_occupancy_rebuild_barrier()
		_profile_stage("barrier", stage_started)

func _publish_shared_blocker_index() -> void:
	# The original Grid/Army maps remain authoritative. This is a disposable
	# read-only view for the synchronous Prepare -> Propose window only.
	shared_blocker_index_attempts += 1
	if not shared_blocker_index_enabled or _active_formations.size() < 3:
		return
	var lab: TerrainLab = null
	var terrain: TerrainData = null
	var teams: Array[TerrainArmy] = []
	for formation: Variant in _active_formations:
		if not formation is TerrainArmy or formation.get_script() != TerrainArmy:
			return
		var team: TerrainArmy = formation
		if team.get_coordinator() != self or team.data == null or team.data.get_script() != TerrainData \
			or not team._common_route_pure_readers() \
			or team.vehicle_transport != null and not team.vehicle_transport.records().is_empty():
			return
		var blocker: Callable = team.external_blocker
		var owner: Object = blocker.get_object() if blocker.is_valid() else null
		if not owner is TerrainLab or owner.get_script() != TerrainLab \
			or blocker.get_method() != &"_armies_block_cell" or blocker.get_bound_arguments() != [team]:
			return
		if lab == null:
			lab = owner as TerrainLab
			terrain = team.data
		elif owner != lab or team.data != terrain:
			return
		teams.append(team)
	if lab == null or lab.terrain != terrain or lab.combat_armies.size() != teams.size():
		return
	for index in range(teams.size()):
		if lab.combat_armies[index] != teams[index]:
			return
	var counts: Dictionary = {}
	var owned: Array[Dictionary] = []
	for team: TerrainArmy in teams:
		var own: Dictionary = {}
		for cell: Vector2i in team._cell_owners:
			own[cell] = true
		for cell: Vector2i in team._reserved_cells:
			own[cell] = true
		owned.append(own)
		for cell: Vector2i in own:
			counts[cell] = int(counts.get(cell, 0)) + 1
	for index in range(teams.size()):
		if teams[index].get_active_move_plan() == null and teams[index].get_active_deployment_plan() == null:
			continue # Planless teams keep the original exact external-blocker reader.
		var others: Dictionary = counts.duplicate()
		for cell: Vector2i in owned[index]:
			if int(counts[cell]) == 1:
				others.erase(cell)
		teams[index].set_shared_movement_blockers(others, current_logic_tick)
		shared_blocker_index_copied_maps += 1
	shared_blocker_index_builds += 1

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
		if not p.compound_id.is_empty():
			var key: String = "compound:" + p.compound_id
			if not groups.has(key): groups[key] = []
			var owner: Object = movement_reservation_grid.compound_proposals[p.compound_id].owner
			groups[key].append({"formation": _member_lookup[p.member_id].formation, "member_id": p.member_id, "compound_id": p.compound_id, "compound_owner": owner})
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
	if TerrainArmy.grid_simulation_retired("SiteCombatMovementCoordinator.complete_committed_moves"): return
	var pending: Array[Array] = []
	for group: Array in _inflight_batches:
		var compound_id := str(group[0].get("compound_id", "")) if not group.is_empty() else ""
		var compound_owner: Object = group[0].get("compound_owner") if not compound_id.is_empty() else null
		var frozen := false
		for entry: Dictionary in group:
			if is_instance_valid(entry.formation) and not entry.formation.combat_enabled:
				frozen = true
				break
		if frozen:
			pending.append(group)
			continue
		var terrain_invalid := false
		if compound_owner != null: terrain_invalid = compound_owner.siege_compound_terrain_invalid(compound_id)
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
					var preserve_main: bool = not formation.committed_move_can_change_main_order(entry.member_id)
					formation.cancel_committed_move_to_source(entry.member_id)
					affected_formations[formation] = bool(affected_formations.get(formation, false)) or not preserve_main
			if compound_owner != null:
				compound_owner.cancel_siege_compound(compound_id)
			else:
				for formation in affected_formations.keys():
					if bool(affected_formations[formation]): formation.hold_after_invalid_committed_batch()
			_occupancy_rebuild_pending = true
			continue
		var ready := true
		if compound_owner != null: ready = compound_owner.can_finish_siege_compound(compound_id)
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
		if compound_owner != null: compound_owner.commit_siege_compound_pose(compound_id)
		for entry: Dictionary in group:
			entry.formation.finish_committed_move(entry.member_id)
		if compound_owner != null: compound_owner.finish_siege_compound(compound_id)
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
	var formation_occupancies: Dictionary = {}
	for formation in _active_formations:
		if formation != null and is_instance_valid(formation) and formation.has_method("get_active_members_occupancy"):
			var occ: Dictionary = formation.get_active_members_occupancy()
			formation_occupancies[formation] = occ
			for mid in occ.keys():
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
			var occ: Dictionary = formation_occupancies[formation]
			for mid in occ.keys():
				var cell: Vector2i = occ[mid]
				if seen_cells.has(cell):
					push_error("Duplicate cell occupancy detected at " + str(cell) + " for member " + str(mid))
					continue
				seen_cells[cell] = mid
				_current_occupancy[cell] = mid
				_member_lookup[mid] = { "formation": formation, "cell": cell }
