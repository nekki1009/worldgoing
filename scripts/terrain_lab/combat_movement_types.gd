class_name CombatMovementTypes
extends RefCounted
## Core enumerations and data transfer records for combat movement,
## pathfinding, multi-phase ingress, and site-level reservation arbitration.

enum CombatOrderResultCode {
	OK,
	INVALID_TARGET,
	BLOCKED,
	INSUFFICIENT_SPACE,
	RESERVATION_CONFLICT,
	FORMATION_INCOMPATIBLE,
	NO_ACTIVE_MEMBERS
}

enum LocalRouteStatus {
	FOUND,
	ALREADY_THERE,
	BUDGET_EXHAUSTED,
	SCHEDULER_DEFERRED,
	TEMPORARILY_BLOCKED,
	LOCAL_NO_ROUTE,
	INVALID_TARGET
}

enum CombatDestinationRole {
	PLATFORM,
	APPROACH_QUEUE
}

enum TacticalSlotRole {
	FLEX,
	COMMANDER,
	OFFICER,
	FRONT,
	REAR
}

enum CombatMovePhase {
	TRANSIT,
	INGRESS_STAGING,
	PLATFORM_INGRESS,
	QUEUE_SETTLING,
	COMPLETE,
	FAILED
}

enum TacticalOverlay {
	NONE,
	ENGAGING
}

enum SlotVacancyReason {
	MEMBER_DEAD,
	MEMBER_REMOVED,
	MEMBER_RETREATED,
	TEMPORARY_ABSENCE
}

enum MoveProposalStatus {
	PENDING,
	ACCEPTED,
	REJECTED_STATIC,
	REJECTED_CONFLICT,
	REJECTED_DEPENDENCY,
	REJECTED_CYCLE,
	REJECTED_INVALID_MEMBER,
	CANCELED_STALE_ORDER
}

enum FormationUnregisterReason {
	LEAVE_SITE,
	FORMATION_DISSOLVED,
	TRANSFER_MEMBERS,
	SITE_UNLOAD
}

enum EgressReachability {
	REACHABLE,
	DISCONNECTED,
	UNRESOLVED_BUDGET
}

enum RuntimeMoveFailureCode {
	NONE,
	BLOCKED,
	CONGESTED,
	DESTINATION_INVALIDATED
}

class LocalRouteResult:
	var status: LocalRouteStatus = LocalRouteStatus.LOCAL_NO_ROUTE
	var path: Array[Vector2i] = []
	var expansions_used: int = 0
	var terminal_candidate: Vector2i = Vector2i(-1, -1)
	var blocked_by_member_id: int = 0

	func _init(p_status: LocalRouteStatus = LocalRouteStatus.LOCAL_NO_ROUTE, p_path: Array[Vector2i] = [], p_expansions: int = 0) -> void:
		status = p_status
		path = p_path
		expansions_used = p_expansions

class MoveProposal:
	var proposal_id: int = 0
	var formation_id: int = 0
	var member_id: int = 0
	var order_serial: int = 0
	var from_cell: Vector2i = Vector2i(-1, -1)
	var to_cell: Vector2i = Vector2i(-1, -1)
	var emergency_priority: int = 0
	var wait_age_ticks: int = 0
	var formation_rr_rank: int = 0
	var front_rank: int = 0
	var formation_persistent_serial: int = 0
	var status: MoveProposalStatus = MoveProposalStatus.PENDING
	var dependency_proposal_id: int = -1

	func _init(p_formation_id: int = 0, p_member_id: int = 0, p_from: Vector2i = Vector2i(-1, -1), p_to: Vector2i = Vector2i(-1, -1)) -> void:
		formation_id = p_formation_id
		member_id = p_member_id
		from_cell = p_from
		to_cell = p_to

class MoveCommitRecord:
	var proposal_id: int = 0
	var formation_id: int = 0
	var member_id: int = 0
	var order_serial: int = 0
	var from_cell: Vector2i = Vector2i(-1, -1)
	var to_cell: Vector2i = Vector2i(-1, -1)
	var commit_tick: int = 0
	var result: MoveProposalStatus = MoveProposalStatus.ACCEPTED

	func _init(
		p_proposal_id: int = 0,
		p_formation_id: int = 0,
		p_member_id: int = 0,
		p_order_serial: int = 0,
		p_from: Vector2i = Vector2i(-1, -1),
		p_to: Vector2i = Vector2i(-1, -1),
		p_commit_tick: int = 0,
		p_result: MoveProposalStatus = MoveProposalStatus.ACCEPTED
	) -> void:
		proposal_id = p_proposal_id
		formation_id = p_formation_id
		member_id = p_member_id
		order_serial = p_order_serial
		from_cell = p_from
		to_cell = p_to
		commit_tick = p_commit_tick
		result = p_result

class EgressSearchState:
	var formation_id: int = 0
	var order_serial: int = 0
	var terrain_revision: int = 0
	var profile_hash: int = 0
	var buckets: Dictionary = {} # cost (int) -> Array[Vector2i]
	var min_cost: int = 0
	var max_cost: int = 0
	var distances: Dictionary = {} # cell (Vector2i) -> int
	var settled_cells: Dictionary = {} # cell (Vector2i) -> bool
	var target_member_cells: Dictionary = {} # member_id (int) -> cell (Vector2i)
	var total_expansions: int = 0
	var completed: bool = false
	var reachability: Dictionary = {} # member_id (int) -> EgressReachability

	func is_valid_for(p_fid: int, p_order_serial: int, p_revision: int, p_hash: int = 0) -> bool:
		if formation_id != p_fid or order_serial != p_order_serial or terrain_revision != p_revision:
			return false
		if profile_hash != 0 and p_hash != 0 and profile_hash != p_hash:
			return false
		return true

class EgressRetryRequest:
	var formation_id: int = 0
	var order_serial: int = 0
	var terrain_revision: int = 0

	func _init(p_fid: int = 0, p_serial: int = 0, p_rev: int = 0) -> void:
		formation_id = p_fid
		order_serial = p_serial
		terrain_revision = p_rev

class DeploymentSlotLease:
	var formation_id: int = 0
	var order_serial: int = 0
	var member_id: int = 0
	var role: CombatDestinationRole = CombatDestinationRole.PLATFORM
	var cell: Vector2i = Vector2i(-1, -1)
	var temporary_absence_remaining_sec: float = 0.0

	func _init(p_formation_id: int = 0, p_member_id: int = 0, p_role: CombatDestinationRole = CombatDestinationRole.PLATFORM, p_cell: Vector2i = Vector2i(-1, -1)) -> void:
		formation_id = p_formation_id
		member_id = p_member_id
		role = p_role
		cell = p_cell
