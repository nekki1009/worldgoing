extends SceneTree
## A queue/platform target exchange changes destination roles, not physical cells.
## The commander tactical marker follows its member through JSON save/load.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Transit = preload("res://scripts/terrain_lab/formation_transit_planner.gd")
const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

const COMMANDER := 2000

func _initialize() -> void:
	call_deferred("_run")

func _require(ok: bool, message: String) -> bool:
	if ok:
		return true
	push_error("COMMANDER QUEUE ROLE ROUNDTRIP FAIL: " + message)
	quit(1)
	return false

func _check_plan(plan: CombatDeploymentPlan, queue_id: int, commander_slot: Vector2i, queue_slot: Vector2i, roster: Array[int]) -> bool:
	if not _require(plan.is_queue_member(COMMANDER) and plan.is_platform_member(queue_id)
		and plan.get_slot_for_member(COMMANDER) == queue_slot and plan.get_slot_for_member(queue_id) == commander_slot,
		"The exchanged commander and queue member must carry their new destination roles and targets"): return false
	if not _require(plan.queue_member_ids.size() == 40 and plan.queue_member_ids[0] == COMMANDER
		and plan.pending_platform_member_ids.size() == 60 and plan.pending_platform_member_ids.has(queue_id)
		and not plan.pending_platform_member_ids.has(COMMANDER),
		"Queue and pending-platform lists must match the exchanged destination roles"): return false
	if not _require(int(plan.slot_tactical_roles.get(queue_slot, Types.TacticalSlotRole.FLEX)) == Types.TacticalSlotRole.COMMANDER
		and int(plan.slot_tactical_roles.get(commander_slot, Types.TacticalSlotRole.FLEX)) == Types.TacticalSlotRole.FLEX,
		"The tactical marker must follow the commander into its queue target"): return false
	if not _require(plan.member_slot_map.size() == roster.size() and plan.slot_owner_map.size() == roster.size(),
		"The exchange must retain exactly one target per member and owner per target"): return false
	var seen: Dictionary = {}
	var commander_markers := 0
	for mid in roster:
		var slot: Vector2i = plan.get_slot_for_member(mid)
		if not _require(not seen.has(slot) and int(plan.slot_owner_map.get(slot, -1)) == mid,
			"Slot ownership must be bijective for the entire real deployment plan"): return false
		seen[slot] = true
		if int(plan.slot_tactical_roles.get(slot, Types.TacticalSlotRole.FLEX)) == Types.TacticalSlotRole.COMMANDER:
			commander_markers += 1
			if not _require(mid == COMMANDER, "No other member may inherit command through its target cell"): return false
		if not _require((plan.is_platform_member(mid) and plan.platform_slots.has(slot))
			or (plan.is_queue_member(mid) and plan.approach_queue_slots.has(slot)),
			"Every destination role must match its platform or queue slot"): return false
	return _require(commander_markers == 1, "Exactly one commander tactical marker must survive")

func _run() -> void:
	var fixture: Dictionary = Helper.build_exact_60_platform_map()
	var terrain: TerrainData = fixture.data
	var path: Array[Vector2i] = Transit.build_macro_path(terrain, fixture.start, fixture.anchor)
	if not _require(not path.is_empty(), "The real 60-platform fixture must have a legal route"): return
	var roster: Array[int] = []
	for i in range(100):
		roster.append(COMMANDER + i)
	var plan: CombatDeploymentPlan = Destination.plan_deployment(1, 1, terrain, fixture.anchor, path, roster, null, [COMMANDER])
	if not _require(plan != null and plan.platform_slots.size() == 60 and plan.queue_member_ids.size() == 40
		and plan.is_platform_member(COMMANDER) and plan.pending_platform_member_ids.has(COMMANDER)
		and not plan.is_slot_locked(COMMANDER),
		"The real deployment must start with an unlocked commander platform final and forty queue members"): return
	var queue_id: int = plan.queue_member_ids[0]
	var commander_slot: Vector2i = plan.get_slot_for_member(COMMANDER)
	var queue_slot: Vector2i = plan.get_slot_for_member(queue_id)
	if not _require(int(plan.slot_tactical_roles.get(commander_slot, Types.TacticalSlotRole.FLEX)) == Types.TacticalSlotRole.COMMANDER
		and int(plan.slot_tactical_roles.get(queue_slot, Types.TacticalSlotRole.FLEX)) == Types.TacticalSlotRole.FLEX,
		"The initial commander and queue targets must have different tactical markers"): return
	var initial_epoch: int = plan.assignment_epoch
	var initial_promotions: int = plan.promotion_count
	if not _require(plan.exchange_queue_platform_roles(queue_id, COMMANDER)
		and plan.assignment_epoch == initial_epoch + 1 and plan.promotion_count == initial_promotions + 1,
		"An unlocked commander must be eligible for the same queue/platform target exchange"): return
	if not _check_plan(plan, queue_id, commander_slot, queue_slot, roster): return
	var army := TerrainArmy.new()
	var serialized: Dictionary = army._serialize_deployment_plan(plan)
	var json: String = JSON.stringify(serialized)
	var parsed: Variant = JSON.parse_string(json)
	if not _require(parsed is Dictionary, "The exchanged deployment must serialize as valid JSON"): return
	var restored: CombatDeploymentPlan = army._deserialize_deployment_plan(parsed)
	if not _require(restored.assignment_epoch == plan.assignment_epoch and restored.promotion_count == plan.promotion_count,
		"The exchange epoch and promotion count must survive save/load"): return
	if not _check_plan(restored, queue_id, commander_slot, queue_slot, roster): return
	if not _require(restored.member_slot_map == plan.member_slot_map and restored.slot_owner_map == plan.slot_owner_map
		and restored.member_role_map == plan.member_role_map and restored.slot_tactical_roles == plan.slot_tactical_roles,
		"JSON restore must reproduce every role, target owner, and tactical marker exactly"): return
	army.free()
	print("COMBAT MOVEMENT COMMANDER QUEUE ROLE ROUNDTRIP PASS")
	quit(0)
