extends SceneTree

const Destination = preload("res://scripts/terrain_lab/formation_destination_planner.gd")
const Transit = preload("res://scripts/terrain_lab/formation_transit_planner.gd")
const Registry = preload("res://scripts/terrain_lab/site_deployment_reservation_registry.gd")

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false

func _flat(size: Vector2i) -> TerrainData:
	var terrain := TerrainData.new()
	terrain.allocate(size)
	terrain.flags.fill(TerrainData.Flag.WALKABLE)
	terrain.height_levels.fill(0)
	terrain.static_blocked.fill(0)
	terrain.ramp_edges.fill(0)
	return terrain

func _run() -> void:
	var terrain := _flat(Vector2i(30, 20))
	var roster: Array[int] = [101, 102, 103, 104, 105, 106, 107, 108, 109]
	var anchor := Vector2i(18, 10)
	var path: Array[Vector2i] = Transit.build_macro_path(terrain, Vector2i(2, 10), anchor)
	var complete := Destination.plan_deployment(1, 1, terrain, anchor, path, roster, null, [], {}, Vector2i.RIGHT, null, "square")
	if not _require(complete != null and complete.platform_slots.size() == 9 and complete.following_member_ids.is_empty() and complete.shape_version == 2, "Open square must retain all exact slots and the v2 contract"): return
	var blocked_slot: Vector2i = complete.platform_slots[0]
	var blocked: Dictionary = {blocked_slot: true}
	var registry := Registry.new()
	var plan := Destination.plan_deployment(1, 1, terrain, anchor, path, roster, registry, [], {}, Vector2i.RIGHT, null, "square", blocked)
	if not _require(plan != null and plan.platform_slots.size() == 8 and plan.following_member_ids.size() == 1 and plan.shape_version == 3, "A blocked template cell must leave one explicit follower"): return
	var follower: int = plan.following_member_ids[0]
	if not _require(not plan.member_slot_map.has(follower) and not plan.member_role_map.has(follower) and not plan.is_platform_member(follower) and not plan.is_queue_member(follower), "Follower must not own a fake slot or deployment role"): return
	var occupied := plan.member_slot_map.duplicate()
	occupied[follower] = Vector2i(2, 10)
	if not _require(not Destination.is_settled(plan, occupied), "A partial deployment must not report all members settled"): return
	var move := CombatMovePlan.new()
	move.destination_plan = plan
	move.formation_id = 1
	move.order_serial = 1
	move.resolved_anchor = anchor
	move.macro_path = path
	move.macro_cursor = 8
	move.current_width = 1
	for mid in plan.member_slot_map.keys():
		plan.mark_platform_member_settled(mid)
	Transit.native_transit_enabled = false
	var transit := Transit.calculate_transit_slots(move, terrain, null, roster, occupied)
	if not _require(transit.has(follower) and terrain.is_walkable(transit[follower]), "Follower must receive a legal original transit soft target"): return
	var target := Destination.resolve_member_target(move, plan, follower, occupied[follower])
	if not _require(target.kind == "transit" and target.target != occupied[follower], "Follower must continue after the assigned front has settled"): return
	move.member_transit_slots[follower] = occupied[follower]
	if not _require(Destination.resolve_member_target(move, plan, follower, occupied[follower]).wait_reason == "WAIT_SPACE", "A stationary follower must expose normal space waiting"): return
	var leases: Array[Vector2i] = []
	leases.assign(plan.member_slot_map.values())
	if not _require(bool(registry.try_replace_reservations(1, 0, 1, leases).ok), "Initial subset leases failed"): return
	if not _require(Destination.refresh_following_members(move, plan, occupied, terrain, registry, blocked) == 0 and plan.is_following_member(follower), "A blocked real slot must not be assigned"): return
	if not _require(bool(registry.try_replace_reservations(2, 0, 1, [blocked_slot]).ok), "Other-team slot fixture failed"): return
	if not _require(Destination.refresh_following_members(move, plan, occupied, terrain, registry) == 0, "A follower must not steal another team's lease"): return
	registry.release_order(2)
	registry.try_replace_reservations(1, 1, 2, leases)
	if not _require(Destination.refresh_following_members(move, plan, occupied, terrain, registry) == 0 and plan.is_following_member(follower) and plan.platform_slots.size() == 8, "Stale lease replacement must preserve the complete partial plan"): return
	plan.order_serial = 2
	move.order_serial = 2
	if not _require(Destination.refresh_following_members(move, plan, occupied, terrain, registry) == 1 and plan.following_member_ids.is_empty() and plan.member_slot_map[follower] == blocked_slot and plan.platform_slots.size() == 9, "Free real template slot must atomically admit the follower"): return
	if not _require(registry.owner_of(blocked_slot).formation_id == 1 and registry.owner_of(blocked_slot).order_serial == 2 and move.member_assignment_epoch.has(follower), "Admission must retain the original lease and route epoch owners"): return
	var small := _flat(Vector2i(8, 4))
	var short_path: Array[Vector2i] = [Vector2i(1, 1), Vector2i(2, 1)]
	var large_roster: Array[int] = []
	for mid in range(40):
		large_roster.append(2000 + mid)
	var partial_auto := Destination.plan_deployment(3, 1, small, Vector2i(2, 1), short_path, large_roster)
	if not _require(partial_auto != null and partial_auto.member_slot_map.size() < large_roster.size() and partial_auto.member_slot_map.size() + partial_auto.following_member_ids.size() == 40, "Auto must accept a destination and approach smaller than the whole roster"): return
	var all_blocked: Dictionary = {}
	for y in range(small.size.y):
		for x in range(small.size.x):
			all_blocked[Vector2i(x, y)] = true
	var waiting := Destination.plan_deployment(4, 1, small, Vector2i(2, 1), short_path, large_roster, null, [], {}, Vector2i.RIGHT, null, "auto", all_blocked)
	if not _require(waiting != null and waiting.member_slot_map.is_empty() and waiting.following_member_ids.size() == 40 and waiting.final_width == 1 and waiting.final_depth == 1 and not Destination.is_settled(waiting, {}), "Zero available slots must retain all explicit followers without a false arrival"): return
	waiting.remove_member(large_roster[0])
	if not _require(not waiting.is_following_member(large_roster[0]) and waiting.following_member_ids.size() == 39, "Original member removal must clear follower state"): return
	print("COMBAT MOVEMENT PARTIAL DESTINATION PASS: fixed subset, follower transit, atomic admission, auto shortfall, zero slots")
	quit(0)
