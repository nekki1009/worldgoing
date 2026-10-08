class_name SiteMovementReservationGrid
extends RefCounted
## Authoritative grid-level movement reservation manager.
## Manages proposal submission, conflict arbitration, anti-swap edge checks,
## dependency resolution, longer-cycle rejection, and atomic commit.

const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

var initial_occupancy: Dictionary = {} # cell (Vector2i) -> member_id (int)
var committed_occupancy: Dictionary = {} # cell (Vector2i) -> member_id (int)
var proposals: Array = [] # Array of MoveProposal
var proposal_lookup: Dictionary = {} # proposal_id (int) -> MoveProposal
var member_proposal_map: Dictionary = {} # member_id (int) -> proposal_id (int)
var cell_proposal_map: Dictionary = {} # to_cell (Vector2i) -> Array[MoveProposal]
var _next_proposal_id: int = 1
var terrain_data: Object = null
var blocked_destinations: Dictionary = {} # In-flight claims and borrowed external actor cells, separate from member occupancy.
var compound_proposals: Dictionary = {} # Tick-local owner/plan references, never a physical clock.

func begin_tick(current_occupancy: Dictionary, p_terrain: Object = null, p_blocked_destinations: Dictionary = {}) -> void:
	initial_occupancy = current_occupancy.duplicate()
	committed_occupancy = current_occupancy.duplicate()
	proposals.clear()
	proposal_lookup.clear()
	member_proposal_map.clear()
	cell_proposal_map.clear()
	compound_proposals.clear()
	_next_proposal_id = 1
	terrain_data = p_terrain
	blocked_destinations = p_blocked_destinations.duplicate()

func propose_move(
	formation_id: int,
	member_id: int,
	order_serial: int,
	from_cell: Vector2i,
	to_cell: Vector2i,
	emergency_priority: int = 0,
	wait_age_ticks: int = 0,
	formation_rr_rank: int = 0,
	front_rank: int = 0,
	formation_persistent_serial: int = 0
) -> int:
	var proposal = Types.MoveProposal.new(formation_id, member_id, from_cell, to_cell)
	proposal.order_serial = order_serial
	proposal.emergency_priority = emergency_priority
	proposal.wait_age_ticks = wait_age_ticks
	proposal.formation_rr_rank = formation_rr_rank
	proposal.front_rank = front_rank
	proposal.formation_persistent_serial = formation_persistent_serial
	proposal.status = Types.MoveProposalStatus.PENDING
	return add_proposal(proposal)

func propose_compound(owner: Object, plan: Dictionary, member_moves: Array) -> String:
	var identity := str(plan.get("compound_id", ""))
	if identity.is_empty() or compound_proposals.has(identity) or owner == null or not owner.has_method("can_commit_siege_compound") or not owner.has_method("begin_siege_compound"):
		return ""
	var seen := {}
	for movement: Dictionary in member_moves:
		var mid := int(movement.get("member_id", 0))
		if mid <= 0 or seen.has(mid) or member_proposal_map.has(mid): return ""
		seen[mid] = true
	var ids: Array[int] = []
	var priority = Types.MoveProposal.new(int(plan.get("formation_id", 0)), int(plan.get("priority_member", 0)))
	priority.formation_persistent_serial = int(plan.get("formation_serial", 0))
	priority.wait_age_ticks = int(plan.get("wait_age", 0))
	for movement: Dictionary in member_moves:
		var proposal = Types.MoveProposal.new(int(plan.formation_id), int(movement.member_id), movement.from_cell, movement.to_cell)
		proposal.compound_id = identity
		proposal.formation_persistent_serial = priority.formation_persistent_serial
		proposal.wait_age_ticks = priority.wait_age_ticks
		ids.append(add_proposal(proposal))
	compound_proposals[identity] = {"owner": owner, "plan": plan, "proposal_ids": ids, "priority": priority, "accepted": false}
	return identity

func _reject_compound(identity: String, reason: int) -> void:
	var group: Dictionary = compound_proposals.get(identity, {})
	if group.is_empty(): return
	group.accepted = false
	for pid: int in group.proposal_ids:
		var proposal = proposal_lookup.get(pid)
		if proposal != null and proposal.status in [Types.MoveProposalStatus.PENDING, Types.MoveProposalStatus.ACCEPTED]: proposal.status = reason

func _compound_claim_cells(plan: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if terrain_data == null: return result
	for value: int in plan.get("sweep", []): result.append(terrain_data.cell_from_index(value))
	for movement: Dictionary in plan.get("participants", []):
		for value: int in [int(movement.from), int(movement.to)]:
			var cell: Vector2i = terrain_data.cell_from_index(value)
			if not result.has(cell): result.append(cell)
	return result

func _resolve_compound_claims() -> void:
	var candidates: Array = compound_proposals.values()
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _compare_proposals(a.priority, b.priority))
	var claimed := {}
	for group: Dictionary in candidates:
		var plan: Dictionary = group.plan
		var identity := str(plan.compound_id)
		if not is_instance_valid(group.owner) or not group.owner.can_commit_siege_compound(plan, initial_occupancy, blocked_destinations):
			_reject_compound(identity, Types.MoveProposalStatus.REJECTED_STATIC)
			continue
		var cells := _compound_claim_cells(plan)
		var rejected := false
		for cell: Vector2i in cells:
			if claimed.has(cell): rejected = true; break
			for proposal in cell_proposal_map.get(cell, []):
				if proposal.compound_id == identity or proposal.status != Types.MoveProposalStatus.PENDING: continue
				if _compare_proposals(proposal, group.priority): rejected = true; break
			if rejected: break
		if rejected:
			_reject_compound(identity, Types.MoveProposalStatus.REJECTED_CONFLICT)
			continue
		group.accepted = true
		for cell: Vector2i in cells:
			claimed[cell] = identity
			for proposal in cell_proposal_map.get(cell, []):
				if proposal.compound_id != identity and proposal.status == Types.MoveProposalStatus.PENDING: proposal.status = Types.MoveProposalStatus.REJECTED_CONFLICT

func _cascade_compound_rejections() -> void:
	var changed := true
	while changed:
		changed = false
		for identity: String in compound_proposals:
			var group: Dictionary = compound_proposals[identity]
			if not bool(group.accepted): continue
			for pid: int in group.proposal_ids:
				if proposal_lookup[pid].status != Types.MoveProposalStatus.ACCEPTED:
					_reject_compound(identity, Types.MoveProposalStatus.REJECTED_DEPENDENCY)
					changed = true
					break
		for proposal in proposals:
			if proposal.status != Types.MoveProposalStatus.ACCEPTED or proposal.dependency_proposal_id < 0: continue
			var dependency = proposal_lookup.get(proposal.dependency_proposal_id)
			if dependency == null or dependency.status != Types.MoveProposalStatus.ACCEPTED:
				proposal.status = Types.MoveProposalStatus.REJECTED_DEPENDENCY
				changed = true

func add_proposal(proposal: Variant) -> int:
	if proposal == null:
		return -1
	if member_proposal_map.has(proposal.member_id):
		return -1
	var pid: int = _next_proposal_id
	_next_proposal_id += 1
	proposal.proposal_id = pid
	proposals.append(proposal)
	proposal_lookup[pid] = proposal
	member_proposal_map[proposal.member_id] = pid

	if not cell_proposal_map.has(proposal.to_cell):
		cell_proposal_map[proposal.to_cell] = []
	cell_proposal_map[proposal.to_cell].append(proposal)
	return pid

## Sort comparator for same-cell competition
## Ordering tuple:
## 1. emergency_priority (descending)
## 2. wait_age_ticks (descending)
## 3. front_rank (ascending)
## 4. formation_persistent_serial (ascending)
## 5. formation_rr_rank (ascending)
## 6. member_id (ascending)
static func _compare_proposals(a: Variant, b: Variant) -> bool:
	if a.emergency_priority != b.emergency_priority:
		return a.emergency_priority > b.emergency_priority
	if a.wait_age_ticks != b.wait_age_ticks:
		return a.wait_age_ticks > b.wait_age_ticks
	if a.front_rank != b.front_rank:
		return a.front_rank < b.front_rank
	if a.formation_persistent_serial != b.formation_persistent_serial:
		return a.formation_persistent_serial < b.formation_persistent_serial
	if a.formation_rr_rank != b.formation_rr_rank:
		return a.formation_rr_rank < b.formation_rr_rank
	return a.member_id < b.member_id

## Only two adjacent members of one formation and order may exchange occupied
## cells. Longer cycles and exchanges between formations still have no open tail.
func is_same_formation_pair_swap(proposal: Variant) -> bool:
	if proposal == null or proposal.dependency_proposal_id < 0 or proposal.formation_id <= 0:
		return false
	var partner = proposal_lookup.get(proposal.dependency_proposal_id)
	if partner == null or partner.proposal_id == proposal.proposal_id:
		return false
	var edge: Vector2i = proposal.to_cell - proposal.from_cell
	return absi(edge.x) + absi(edge.y) == 1 \
		and proposal.formation_id == partner.formation_id \
		and proposal.order_serial == partner.order_serial \
		and proposal.from_cell == partner.to_cell and proposal.to_cell == partner.from_cell \
		and partner.dependency_proposal_id == proposal.proposal_id

func resolve_all() -> void:
	_resolve_compound_claims()
	# --- Stage 1: Static validation & same-cell competition ---
	for p in proposals:
		if p.status != Types.MoveProposalStatus.PENDING: continue
		# Check from_cell matches tick-start occupancy
		if initial_occupancy.get(p.from_cell, -1) != p.member_id:
			p.status = Types.MoveProposalStatus.REJECTED_INVALID_MEMBER
			continue
		if blocked_destinations.has(p.to_cell):
			p.status = Types.MoveProposalStatus.REJECTED_DEPENDENCY
			continue
		# Must be step distance 1 (Chebyshev or Manhattan)
		var diff: Vector2i = p.to_cell - p.from_cell
		if p.from_cell == p.to_cell or maxi(absi(diff.x), absi(diff.y)) > 1:
			p.status = Types.MoveProposalStatus.REJECTED_STATIC
			continue
		# Terrain legality if available
		if terrain_data != null:
			if not terrain_data.contains(p.to_cell) or not terrain_data.can_step(p.from_cell, p.to_cell):
				p.status = Types.MoveProposalStatus.REJECTED_STATIC
				continue

	# Same to_cell arbitration
	for target_cell in cell_proposal_map.keys():
		var candidates: Array = []
		for p in cell_proposal_map[target_cell]:
			if p.status == Types.MoveProposalStatus.PENDING:
				candidates.append(p)
		if candidates.size() > 1:
			candidates.sort_custom(_compare_proposals)
			# Winner is candidates[0], all others rejected with REJECTED_CONFLICT
			for i in range(1, candidates.size()):
				candidates[i].status = Types.MoveProposalStatus.REJECTED_CONFLICT

	# --- Stage 2: Dependency Graph Construction ---
	# For each surviving pending proposal P:
	# target_cell = P.to_cell
	# If target_cell has occupant B in initial_occupancy:
	#   Does B have a surviving proposal P_B with status PENDING?
	#     Yes: P.dependency_proposal_id = P_B.proposal_id
	#     No: P cannot move because B is not vacating! Mark P as REJECTED_DEPENDENCY
	# Else:
	#   target_cell is empty at tick start. P has dependency_proposal_id = -1 (open tail).
	for p in proposals:
		if p.status != Types.MoveProposalStatus.PENDING:
			continue
		if initial_occupancy.has(p.to_cell):
			var occupant_b: int = initial_occupancy[p.to_cell]
			if occupant_b == p.member_id:
				# Unit proposed to its own cell
				p.status = Types.MoveProposalStatus.REJECTED_STATIC
				continue
			if member_proposal_map.has(occupant_b):
				var dep_pid: int = member_proposal_map[occupant_b]
				var dep_prop = proposal_lookup.get(dep_pid)
				if dep_prop != null and dep_prop.status == Types.MoveProposalStatus.PENDING:
					p.dependency_proposal_id = dep_pid
				else:
					p.status = Types.MoveProposalStatus.REJECTED_DEPENDENCY
			else:
				# Occupant B has no proposal -> blocked
				p.status = Types.MoveProposalStatus.REJECTED_DEPENDENCY
		else:
			p.dependency_proposal_id = -1

	# --- Stage 3: Cycle Detection & Dependency Propagation ---
	# Detect cycles: For each proposal, follow dependency chain using visited set
	var in_cycle: Dictionary = {} # proposal_id -> bool
	for p in proposals:
		if p.status != Types.MoveProposalStatus.PENDING:
			continue
		var visited_in_path: Dictionary = {}
		var curr = p
		while curr != null and curr.status == Types.MoveProposalStatus.PENDING and curr.dependency_proposal_id != -1:
			visited_in_path[curr.proposal_id] = true
			var next_prop = proposal_lookup.get(curr.dependency_proposal_id)
			if next_prop == null or next_prop.status != Types.MoveProposalStatus.PENDING:
				break
			if visited_in_path.has(next_prop.proposal_id):
				# Cycle detected! Mark all proposals in this loop as in_cycle
				var cycle_node = next_prop
				while not in_cycle.has(cycle_node.proposal_id):
					in_cycle[cycle_node.proposal_id] = true
					cycle_node = proposal_lookup.get(cycle_node.dependency_proposal_id)
					if cycle_node == null:
						break
				break
			curr = next_prop

	# Admit only same-formation reciprocal pairs. All longer or foreign cycles
	# keep their original rejection and do not reach the completion barrier.
	for pid in in_cycle.keys():
		var cp = proposal_lookup.get(pid)
		if cp != null and cp.status == Types.MoveProposalStatus.PENDING:
			cp.status = Types.MoveProposalStatus.ACCEPTED if is_same_formation_pair_swap(cp) else Types.MoveProposalStatus.REJECTED_CYCLE

	# Dependency resolution & acceptance propagation:
	# Build reverse adjacency: dep_pid -> Array of proposals depending on dep_pid
	var dependents_of: Dictionary = {} # proposal_id -> Array[MoveProposal]
	var open_tail_proposals: Array = []
	for p in proposals:
		if p.status != Types.MoveProposalStatus.PENDING:
			continue
		if p.dependency_proposal_id == -1:
			open_tail_proposals.append(p)
		else:
			if not dependents_of.has(p.dependency_proposal_id):
				dependents_of[p.dependency_proposal_id] = []
			dependents_of[p.dependency_proposal_id].append(p)

	# BFS / Queue to mark accepted proposals from open tails backwards
	var queue: Array = []
	for p in open_tail_proposals:
		p.status = Types.MoveProposalStatus.ACCEPTED
		queue.append(p)

	while not queue.is_empty():
		var parent = queue.pop_front()
		if dependents_of.has(parent.proposal_id):
			for child in dependents_of[parent.proposal_id]:
				if child.status == Types.MoveProposalStatus.PENDING:
					child.status = Types.MoveProposalStatus.ACCEPTED
					queue.append(child)

	# Any remaining PENDING proposals failed their dependency chain
	for p in proposals:
		if p.status == Types.MoveProposalStatus.PENDING:
			p.status = Types.MoveProposalStatus.REJECTED_DEPENDENCY
	_cascade_compound_rejections()


func commit_all(member_lookup: Dictionary, current_tick: int = 0) -> Array:
	# A whole vehicle group must still exist before any original person starts.
	for identity: String in compound_proposals:
		var group: Dictionary = compound_proposals[identity]
		if not bool(group.accepted): continue
		var valid: bool = is_instance_valid(group.owner) and group.owner.can_commit_siege_compound(group.plan, initial_occupancy, blocked_destinations)
		for pid: int in group.proposal_ids:
			var proposal = proposal_lookup[pid]
			var info: Dictionary = member_lookup.get(proposal.member_id, {})
			if proposal.status != Types.MoveProposalStatus.ACCEPTED or info.is_empty() or info.get("cell") != proposal.from_cell or not is_instance_valid(info.get("formation")):
				valid = false
		if not valid: _reject_compound(identity, Types.MoveProposalStatus.REJECTED_INVALID_MEMBER)
	_cascade_compound_rejections()
	# Pass 0: Preflight validation + cascade dependency invalidation
	var invalidated_pids: Dictionary = {}
	var participants: Dictionary = {}
	for p in proposals:
		if p.status == Types.MoveProposalStatus.ACCEPTED:
			participants[p.member_id] = true
	for p in proposals:
		if p.status == Types.MoveProposalStatus.ACCEPTED:
			if not p.compound_id.is_empty(): continue # Above whole-group preflight owns this step.
			var valid := true
			if not member_lookup.has(p.member_id):
				valid = false
			else:
				var info: Dictionary = member_lookup[p.member_id]
				var actual_cell: Vector2i = info.get("cell", Vector2i(-1, -1))
				var formation = info.get("formation")
				if actual_cell != p.from_cell or formation == null or not is_instance_valid(formation) \
					or not formation.has_method("can_begin_committed_move") \
					or not formation.can_begin_committed_move(p.member_id, p.from_cell, p.to_cell, participants):
					valid = false
				else:
					if formation.has_method("get_order_serial") and p.order_serial > 0 and formation.get_order_serial() != p.order_serial:
						valid = false
						p.status = Types.MoveProposalStatus.CANCELED_STALE_ORDER
			if not valid and p.status == Types.MoveProposalStatus.ACCEPTED:
				p.status = Types.MoveProposalStatus.REJECTED_INVALID_MEMBER
			if not valid:
				invalidated_pids[p.proposal_id] = true
			elif p.dependency_proposal_id >= 0:
				var dependency = proposal_lookup.get(p.dependency_proposal_id)
				if dependency == null or dependency.formation_id != p.formation_id \
					or (not is_same_formation_pair_swap(p) and dependency.to_cell - dependency.from_cell != p.to_cell - p.from_cell):
					p.status = Types.MoveProposalStatus.REJECTED_DEPENDENCY
					invalidated_pids[p.proposal_id] = true

	# Cascade dependency invalidation
	if not invalidated_pids.is_empty():
		var changed := true
		while changed:
			changed = false
			for p in proposals:
				if p.status == Types.MoveProposalStatus.ACCEPTED:
					if invalidated_pids.has(p.dependency_proposal_id):
						p.status = Types.MoveProposalStatus.REJECTED_DEPENDENCY
						invalidated_pids[p.proposal_id] = true
						changed = true

	# Collect all surviving accepted proposals
	_cascade_compound_rejections()
	var accepted_proposals: Array = []
	for p in proposals:
		if p.status == Types.MoveProposalStatus.ACCEPTED:
			accepted_proposals.append(p)

	# Start the original physical step. The source cell stays authoritative until
	# the coordinator completes the whole dependency chain after interpolation.
	for p in accepted_proposals:
		if not p.compound_id.is_empty(): continue
		var info: Dictionary = member_lookup[p.member_id]
		info.formation.begin_committed_move(p.member_id, p.from_cell, p.to_cell)
	for group: Dictionary in compound_proposals.values():
		if bool(group.accepted): group.owner.begin_siege_compound(group.plan)

	# Pass 4: Generate immutable MoveCommitRecord for all proposals
	var records: Array = []
	for p in proposals:
		var rec = Types.MoveCommitRecord.new(
			p.proposal_id,
			p.formation_id,
			p.member_id,
			p.order_serial,
			p.from_cell,
			p.to_cell,
			current_tick,
			p.status
		)
		records.append(rec)

	return records

func cancel_proposals_for_formation(formation_id: int) -> void:
	var canceled_pids: Dictionary = {}
	for p in proposals:
		if p.formation_id == formation_id:
			p.status = Types.MoveProposalStatus.CANCELED_STALE_ORDER
			canceled_pids[p.proposal_id] = true

	var changed := true
	while changed:
		changed = false
		for p in proposals:
			if (p.status == Types.MoveProposalStatus.ACCEPTED or p.status == Types.MoveProposalStatus.PENDING) and canceled_pids.has(p.dependency_proposal_id):
				p.status = Types.MoveProposalStatus.REJECTED_DEPENDENCY
				canceled_pids[p.proposal_id] = true
				changed = true

func rebuild_occupancy_from_authoritative(member_cells: Dictionary) -> void:
	committed_occupancy.clear()
	var seen: Dictionary = {}
	for mid in member_cells.keys():
		var cell: Vector2i = member_cells[mid]
		assert(not seen.has(cell), "Duplicate cell occupancy detected at " + str(cell) + " for member " + str(mid))
		seen[cell] = mid
		committed_occupancy[cell] = mid

func get_proposals() -> Array:
	return proposals

func get_committed_occupancy() -> Dictionary:
	return committed_occupancy
