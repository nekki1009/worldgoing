class_name FormationRecoveryController
extends RefCounted
## Manages meaningful progress detection, stall clock accumulation,
## staged obstacle recovery, and combat engagement overlays.

const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const TransitPlanner = preload("res://scripts/terrain_lab/formation_transit_planner.gd")

const WAIT_GRACE_SEC := 0.6
const SLOT_ADJUST_OBSERVE_SEC := 0.6
const SINGLE_FILE_OBSERVE_SEC := 0.8
const REANCHOR_OBSERVE_SEC := 1.0
const REPLAN_OBSERVE_SEC := 1.0
const MACRO_REPLAN_COOLDOWN_SEC := 3.0
const MAX_MACRO_REPLANS := 3
const CONGESTION_ABORT_SEC := 12.0
const PHYSICAL_CHECKPOINT_SPACING := 4

## Checks whether the formation made meaningful progress this tick
static func check_meaningful_progress(
	plan: CombatMovePlan,
	current_median_s: float,
	settled_platform: int,
	settled_queue: int,
	promotion_count: int
) -> bool:
	if plan == null:
		return false

	var progressed := false
	# A long single-file convoy can keep feeding real soldiers through the
	# passage while its median and front quartile are stationary. Each member's
	# checkpoint is earned only after a legal physical cell change in Army.
	var checkpoint_count := 0
	for best_k in plan.member_checkpoint_best_k.values():
		checkpoint_count += floori(float(best_k) / float(PHYSICAL_CHECKPOINT_SPACING))
	if plan.previous_checkpoint_count < 0:
		plan.previous_checkpoint_count = checkpoint_count
	elif checkpoint_count > plan.previous_checkpoint_count:
		progressed = true
		plan.previous_checkpoint_count = checkpoint_count

	# 1. Median path_s advanced by at least 0.5
	if plan.previous_median_path_s == -INF:
		plan.previous_median_path_s = current_median_s
	elif current_median_s >= plan.previous_median_path_s + 0.5:
		progressed = true
		plan.previous_median_path_s = current_median_s
	# On a long single-file route, the front quarter can make real longitudinal
	# progress while the median waits behind it. Use current observations only;
	# the high-water comparison rejects local back-and-forth motion.
	if plan.phase == Types.CombatMovePhase.TRANSIT:
		var upper_quartile: float = plan.get_upper_quartile_path_s()
		if upper_quartile > -INF:
			if plan.previous_upper_quartile_path_s == -INF:
				plan.previous_upper_quartile_path_s = upper_quartile
			elif upper_quartile >= plan.previous_upper_quartile_path_s + 0.5:
				progressed = true
				plan.previous_upper_quartile_path_s = upper_quartile

	# 2. Platform settled count increased
	if settled_platform > plan.previous_platform_settled:
		progressed = true
		plan.previous_platform_settled = settled_platform
		plan.verified_chain_arrival_members.clear()
		plan.verified_chain_arrival_pending = false
	elif plan.verified_chain_arrival_pending:
		# Destination marked a first-time physical arrival at a rotated final.
		# Assignment changes and repeat arrivals by the same actor give no credit.
		progressed = true
		plan.verified_chain_arrival_pending = false

	# 3. Queue settled count increased
	if settled_queue > plan.previous_queue_settled:
		progressed = true
		plan.previous_queue_settled = settled_queue

	# Assignment changes are not physical progress.
	plan.previous_promotion_count = promotion_count

	# 5. Macro cursor advanced
	if plan.previous_macro_cursor < 0:
		plan.previous_macro_cursor = plan.macro_cursor
	elif plan.macro_cursor > plan.previous_macro_cursor:
		progressed = true
		plan.previous_macro_cursor = plan.macro_cursor

	if progressed:
		# Reset stall clock and recovery stage
		plan.active_stall_total_sec = 0.0
		plan.stage_elapsed_sec = 0.0
		plan.recovery_stage = 0

	return progressed

## Updates the stall clock if the formation is eligible
static func update_stall_clock(plan: CombatMovePlan, delta: float) -> void:
	if plan == null:
		return

	# Check eligibility according to invariant
	var eligible: bool = (
		plan.phase != Types.CombatMovePhase.COMPLETE
		and plan.phase != Types.CombatMovePhase.FAILED
		and plan.tactical_overlay != Types.TacticalOverlay.ENGAGING
		and plan.eligible_member_count > 0
		and not plan.waiting_animation_only
		and not plan.scheduler_deferred
	)

	if not eligible:
		# Stall clock is paused while waiting for animation, scheduler, or during combat
		return

	plan.stage_elapsed_sec += delta
	plan.active_stall_total_sec += delta

## Advances recovery through stages 0 to 4 and final static check
static func process_recovery(
	plan: CombatMovePlan,
	current_medoid: Vector2i,
	terrain: Object,
	profile: Object,
	current_time_sec: float = 0.0
) -> int:
	if plan == null:
		return Types.RuntimeMoveFailureCode.NONE

	# Final check: active stall exceeds CONGESTION_ABORT_SEC (12.0s)
	if plan.active_stall_total_sec >= CONGESTION_ABORT_SEC:
		var static_path := TransitPlanner.build_macro_path(terrain, current_medoid, plan.resolved_anchor, profile)
		if static_path.is_empty():
			plan.phase = Types.CombatMovePhase.FAILED
			return Types.RuntimeMoveFailureCode.BLOCKED
		else:
			plan.phase = Types.CombatMovePhase.FAILED
			return Types.RuntimeMoveFailureCode.CONGESTED

	# Stage 0: Initial wait grace (0.6s)
	if plan.recovery_stage == 0:
		if plan.stage_elapsed_sec >= WAIT_GRACE_SEC:
			plan.recovery_stage = 1
			plan.stage_elapsed_sec = 0.0
			# Stage 1 action: Clear blocked member path caches to force local adjustment
			plan.member_paths.clear()
		return Types.RuntimeMoveFailureCode.NONE

	# Stage 1: Slot adjustment observe (0.6s)
	if plan.recovery_stage == 1:
		if plan.stage_elapsed_sec >= SLOT_ADJUST_OBSERVE_SEC:
			plan.recovery_stage = 2
			plan.stage_elapsed_sec = 0.0
			# Stage 2 action: Force single file column (width = 1)
			plan.current_width = 1
			plan.pending_width = 1
			plan.width_confirm_counter = 0
		return Types.RuntimeMoveFailureCode.NONE

	# Stage 2: Single file observe (0.8s)
	if plan.recovery_stage == 2:
		if plan.stage_elapsed_sec >= SINGLE_FILE_OBSERVE_SEC:
			plan.recovery_stage = 3
			plan.stage_elapsed_sec = 0.0
			# Stage 3 action: Local re-anchor to nearest centerline node
			TransitPlanner.update_macro_cursor(plan, current_medoid)
		return Types.RuntimeMoveFailureCode.NONE

	# Stage 3: Re-anchor observe (1.0s)
	if plan.recovery_stage == 3:
		if plan.stage_elapsed_sec >= REANCHOR_OBSERVE_SEC:
			plan.recovery_stage = 4
			plan.stage_elapsed_sec = 0.0
		return Types.RuntimeMoveFailureCode.NONE

	# Stage 4: Macro replan
	if plan.recovery_stage == 4:
		# Once members have entered a valid final deployment, rebuilding the
		# centerline from the rear medoid changes every transit coordinate and
		# pulls the remaining queue backward. Local route/slot recovery still
		# runs, and the unchanged stall clock still reaches CONGESTED below.
		var final_plan: CombatDeploymentPlan = plan.destination_plan
		if plan.phase in [Types.CombatMovePhase.PLATFORM_INGRESS, Types.CombatMovePhase.QUEUE_SETTLING] \
			and final_plan != null and terrain != null and "navigation_revision" in terrain \
			and int(terrain.navigation_revision) == plan.terrain_revision \
			and final_plan.terrain_revision == plan.terrain_revision \
			and not final_plan.member_slot_map.is_empty():
			var final_slots_legal := true
			for slot: Vector2i in final_plan.member_slot_map.values():
				if not terrain.contains(slot) or not terrain.is_walkable(slot):
					final_slots_legal = false
					break
			if final_slots_legal:
				return Types.RuntimeMoveFailureCode.NONE
		var can_replan: bool = (
			plan.macro_replan_count < MAX_MACRO_REPLANS
			and (current_time_sec - plan.last_macro_replan_time_sec >= MACRO_REPLAN_COOLDOWN_SEC)
		)
		if can_replan:
			var new_path := TransitPlanner.build_macro_path(terrain, current_medoid, plan.resolved_anchor, profile)
			if not new_path.is_empty():
				plan.reset_path_coordinates(new_path)
				plan.macro_replan_count += 1
				plan.last_macro_replan_time_sec = current_time_sec
				plan.stage_elapsed_sec = 0.0
				plan.member_paths.clear()
				return Types.RuntimeMoveFailureCode.NONE

	# Final check: active stall exceeds CONGESTION_ABORT_SEC (12.0s)
	if plan.active_stall_total_sec >= CONGESTION_ABORT_SEC:
		# Check if static path still exists
		var static_path := TransitPlanner.build_macro_path(terrain, current_medoid, plan.resolved_anchor, profile)
		if static_path.is_empty():
			plan.phase = Types.CombatMovePhase.FAILED
			return Types.RuntimeMoveFailureCode.BLOCKED
		else:
			plan.phase = Types.CombatMovePhase.FAILED
			return Types.RuntimeMoveFailureCode.CONGESTED

	return Types.RuntimeMoveFailureCode.NONE

## Sets the tactical overlay (ENGAGING freezes stall clock, preserving plan)
static func set_engaging_overlay(plan: CombatMovePlan, engaging: bool) -> void:
	if plan == null:
		return
	if engaging:
		plan.tactical_overlay = Types.TacticalOverlay.ENGAGING
	else:
		if plan.tactical_overlay == Types.TacticalOverlay.ENGAGING:
			plan.tactical_overlay = Types.TacticalOverlay.NONE
