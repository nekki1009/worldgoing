class_name CombatMovePlan
extends RefCounted
## Movement execution plan for a formation under CombatOrder.MOVE.
## Tracks macro path centerline, longitudinal path_s progress, dynamic width hysteresis,
## short-path caching, and stall detection metrics. Keyed strictly by member_id.

const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

var formation_id: int = 0
var order_serial: int = 0
var requested_goal: Vector2i = Vector2i(-1, -1)
var resolved_anchor: Vector2i = Vector2i(-1, -1)
var movement_profile_hash: int = 0

var macro_path: Array[Vector2i] = []
var macro_cursor: int = 0
var phase: int = Types.CombatMovePhase.TRANSIT
var short_translation: bool = false # One legal orthogonal step per member; Grid still commits the batch.
var tactical_overlay: int = Types.TacticalOverlay.NONE
var terrain_revision: int = 0
var roster_revision: int = 0
var path_epoch: int = 0
var assignment_epoch: int = 0
var member_assignment_epoch: Dictionary = {} # member_id -> int
var member_soft_assignment_epoch: Dictionary = {} # member_id -> int

# Dynamic formation width (1 to 4 columns) with hysteresis confirmation
var current_width: int = 4
var pending_width: int = 4
var width_confirm_counter: int = 0

# Member mappings strictly keyed by member_id (int)
var member_sequence_rank: Dictionary = {} # member_id -> int (0 to N-1)
var member_lane_map: Dictionary = {}      # member_id -> int
var member_row_map: Dictionary = {}       # member_id -> int
var member_path_s: Dictionary = {}        # member_id -> float
var member_transit_slots: Dictionary = {} # member_id -> Vector2i
var member_recovery_hold: Dictionary = {} # member_id -> wait for an in-flight step before target rotation
var pre_route_staging_slots: Dictionary = {} # member_id -> Vector2i

# Short path cache & status
var member_paths: Dictionary = {}         # member_id -> Array[Vector2i]
var member_route_status: Dictionary = {}  # member_id -> Types.LocalRouteStatus
var member_defer_count: Dictionary = {}   # member_id -> int (consecutive ticks deferred)
var member_route_retry_count: Dictionary = {} # member_id -> int
var egress_rank_needs_retry: bool = false
var member_projected_path_k: Dictionary = {} # member_id -> int (monotonic path projection index)
var member_observed_path_k: Dictionary = {}  # member_id -> int (current projection, can fluctuate)
var member_observed_path_s: Dictionary = {}  # member_id -> float (current track progress, can fluctuate)
var member_best_path_s: Dictionary = {}      # member_id -> float (monotonic historical best progress)
var member_checkpoint_cell: Dictionary = {} # member_id -> last physical cell sampled
var member_checkpoint_path_k: Dictionary = {} # member_id -> capped current physical progress
var member_checkpoint_best_k: Dictionary = {} # member_id -> physical high-water progress
var member_best_path_k: Dictionary = {}      # member_id -> int (monotonic history progress)
var member_pending_proposal_id: Dictionary = {} # member_id -> int (active proposal ID in reservation grid)
var member_pending_from_cell: Dictionary = {}    # member_id -> Vector2i (proposed step origin)
var member_pending_to_cell: Dictionary = {}      # member_id -> Vector2i (proposed step destination)
var member_route_target: Dictionary = {} # member_id -> Vector2i
var member_route_epoch: Dictionary = {} # member_id -> [path, assignment, terrain, order]
var member_reservation_wait_age: Dictionary = {} # member_id -> rejected reservation count
var member_swap_cooldown_until_sec: Dictionary = {} # member_id -> simulation time
var member_entry_hold: Dictionary = {} # member_id -> true while side slots need the entry lane
var member_crossed_swap_hold: Dictionary = {} # transient two-cycle hold until current proposals finish
var member_entry_waypoint: Dictionary = {} # member_id -> temporary legal step, never a final assignment
var member_vacancy_chain_target: Dictionary = {} # affected member_id -> reserved final target until the physical chain clears
var active_vacancy_chain_actors: Array[int] = [] # occupants that must take one legal step toward a vacancy
var queued_vacancy_steps: Array[Dictionary] = [] # remaining edge-to-vacancy steps, dispatched one physical arrival at a time
var vacancy_waiting_id: int = -1
var vacancy_chain_started_sec: float = 0.0
var vacancy_chain_last_progress_sec: float = 0.0
var vacancy_chain_arrived_count: int = 0
var member_vacancy_chain_start_cell: Dictionary = {} # member_id -> physical cell when the active chain was assigned
var verified_chain_arrival_members: Dictionary = {} # member_id -> credited physical arrival since the last settled highwater
var verified_chain_arrival_pending: bool = false
var member_queue_egress_waypoint: Dictionary = {} # member_id -> one adjacent step off the single ramp
var planning_time_sec: float = 0.0
var next_late_swap_time_sec: float = 0.0
var last_platform_progress_time_sec: float = 0.0
var next_platform_recovery_time_sec: float = 0.0
var platform_settled_highwater: int = 0
var queue_settled_highwater: int = 0
var last_queue_progress_time_sec: float = 0.0
var next_queue_recovery_time_sec: float = 0.0
var member_recovery_vacated_cell: Dictionary = {} # member_id -> last cell yielded to the chain

# Progress metrics & staged recovery
var previous_median_path_s: float = -INF
var previous_upper_quartile_path_s: float = -INF
var previous_macro_cursor: int = -1
var previous_checkpoint_count: int = -1
var previous_platform_settled: int = 0
var previous_queue_settled: int = 0
var previous_promotion_count: int = 0
var stage_elapsed_sec: float = 0.0
var active_stall_total_sec: float = 0.0
var recovery_stage: int = 0
var macro_replan_count: int = 0
var last_macro_replan_time_sec: float = -INF

# Scheduler slice state
var received_scheduler_slice: bool = false
var scheduler_deferred: bool = false
var eligible_member_count: int = 0
var waiting_animation_only: bool = false

var destination_plan: CombatDeploymentPlan = null

## Cleans up all cached paths, slots, and mappings for a departed or killed member.
func remove_member(member_id: int, reason: int = Types.SlotVacancyReason.MEMBER_DEAD) -> void:
	member_sequence_rank.erase(member_id)
	member_lane_map.erase(member_id)
	member_row_map.erase(member_id)
	member_assignment_epoch.erase(member_id)
	member_soft_assignment_epoch.erase(member_id)
	member_path_s.erase(member_id)
	member_transit_slots.erase(member_id)
	member_recovery_hold.erase(member_id)
	pre_route_staging_slots.erase(member_id)
	member_paths.erase(member_id)
	member_route_status.erase(member_id)
	member_defer_count.erase(member_id)
	member_projected_path_k.erase(member_id)
	member_observed_path_k.erase(member_id)
	member_observed_path_s.erase(member_id)
	member_best_path_k.erase(member_id)
	member_best_path_s.erase(member_id)
	member_checkpoint_cell.erase(member_id)
	member_checkpoint_path_k.erase(member_id)
	member_checkpoint_best_k.erase(member_id)
	previous_checkpoint_count = -1
	member_route_retry_count.erase(member_id)
	member_route_target.erase(member_id)
	member_route_epoch.erase(member_id)
	member_reservation_wait_age.erase(member_id)
	member_swap_cooldown_until_sec.erase(member_id)
	member_entry_hold.erase(member_id)
	member_crossed_swap_hold.erase(member_id)
	member_entry_waypoint.erase(member_id)
	member_vacancy_chain_target.erase(member_id)
	active_vacancy_chain_actors.erase(member_id)
	if vacancy_waiting_id == member_id:
		vacancy_waiting_id = -1
		queued_vacancy_steps.clear()
	else:
		for step in queued_vacancy_steps:
			if int(step.get("actor", -1)) == member_id:
				queued_vacancy_steps.clear()
				member_recovery_hold.erase(vacancy_waiting_id)
				vacancy_waiting_id = -1
				break
	member_vacancy_chain_start_cell.erase(member_id)
	verified_chain_arrival_members.erase(member_id)
	member_queue_egress_waypoint.erase(member_id)
	member_recovery_vacated_cell.erase(member_id)
	member_pending_proposal_id.erase(member_id)
	member_pending_from_cell.erase(member_id)
	member_pending_to_cell.erase(member_id)
	if destination_plan != null:
		destination_plan.remove_member(member_id, reason)

## Computes current median longitudinal progress (path_s) across active route members.
func calculate_median_path_s() -> float:
	var source_dict: Dictionary = member_observed_path_s if not member_observed_path_s.is_empty() else member_path_s
	if source_dict.is_empty():
		return 0.0
	var values: Array[float] = []
	for s: float in source_dict.values():
		if s >= 0.0:
			values.append(s)
	if values.is_empty():
		for s: float in source_dict.values():
			values.append(s)
	if values.is_empty():
		return 0.0
	values.sort()
	var mid := floori(float(values.size()) / 2.0)
	if values.size() % 2 == 1:
		return values[mid]
	else:
		return (values[mid - 1] + values[mid]) * 0.5

func get_median_path_s() -> float:
	return calculate_median_path_s()

## Current observed progress of the front quarter, excluding soft targets and
## historical per-member bests. A long single-file convoy can advance while
## its median remains behind the choke.
func get_upper_quartile_path_s() -> float:
	var values: Array[float] = []
	for s: float in member_observed_path_s.values():
		if s >= 0.0:
			values.append(s)
	if values.is_empty():
		return -INF
	values.sort()
	return values[clampi(floori(float(values.size() - 1) * 0.75), 0, values.size() - 1)]

func invalidate_member_route(member_id: int) -> void:
	member_paths.erase(member_id)
	member_route_target.erase(member_id)
	member_route_epoch.erase(member_id)

func stamp_member_route(member_id: int, target: Vector2i) -> void:
	member_route_target[member_id] = target
	member_route_epoch[member_id] = [path_epoch, int(member_assignment_epoch.get(member_id, 0)), terrain_revision, order_serial]

func is_member_route_current(member_id: int, target: Vector2i) -> bool:
	return member_paths.has(member_id) and member_route_target.get(member_id, Vector2i(-1, -1)) == target and member_route_epoch.get(member_id, []) == [path_epoch, int(member_assignment_epoch.get(member_id, 0)), terrain_revision, order_serial]

func note_assignment_change(member_id: int) -> void:
	assignment_epoch += 1
	member_assignment_epoch[member_id] = int(member_assignment_epoch.get(member_id, 0)) + 1
	invalidate_member_route(member_id)

func reset_path_coordinates(new_path: Array[Vector2i]) -> void:
	if macro_path == new_path:
		return
	macro_path = new_path.duplicate()
	macro_cursor = 0
	path_epoch += 1
	member_path_s.clear()
	member_projected_path_k.clear()
	member_observed_path_k.clear()
	member_observed_path_s.clear()
	member_best_path_s.clear()
	member_checkpoint_cell.clear()
	member_checkpoint_path_k.clear()
	member_checkpoint_best_k.clear()
	member_best_path_k.clear()
	member_transit_slots.clear()
	member_recovery_hold.clear()
	queued_vacancy_steps.clear()
	vacancy_waiting_id = -1
	member_crossed_swap_hold.clear()
	member_soft_assignment_epoch.clear()
	assignment_epoch += 1
	pre_route_staging_slots.clear()
	member_paths.clear()
	member_route_target.clear()
	member_route_epoch.clear()
	previous_median_path_s = -INF
	previous_upper_quartile_path_s = -INF
	previous_macro_cursor = -1
	previous_checkpoint_count = -1
