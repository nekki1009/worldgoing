class_name FormationTransitPlanner
extends RefCounted
## Long-distance macro navigation, path_s progression, dynamic corridor width
## hysteresis, and unique transit slot generation for army formations.

const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")

const WIDTH_CHANGE_CONFIRM_TICKS := 3
const MAX_TRANSIT_WIDTH := 4
const MEMBER_SPACING := 1.0
const REANCHOR_DISTANCE := 6.0
const MIN_TRANSIT_LOOKAHEAD_ROWS := 2
const MAX_TRANSIT_LOOKAHEAD_ROWS := 4

static func _count_capacity_reject(counts: Dictionary, old_index: int, next_candidate: int, max_index: int, stationary: bool, gate: bool) -> void:
	counts["capacity_bound"] = int(counts.get("capacity_bound", 0)) + 1
	var detail := ""
	if old_index < next_candidate:
		detail = "capacity_behind_prefix"
	elif old_index > max_index:
		detail = "capacity_tail_reservation"
	if not detail.is_empty():
		counts[detail] = int(counts.get(detail, 0)) + 1
		var breakdown := detail + ("_stationary" if stationary else "_moving") + ("_gate" if gate else "_open")
		counts[breakdown] = int(counts.get(breakdown, 0)) + 1

static func _height_of(terrain: Object, cell: Vector2i) -> int:
	if terrain == null or not terrain.contains(cell):
		return 0
	if "height_levels" in terrain:
		var idx: int = terrain.index(cell)
		return int(terrain.height_levels[idx])
	return 0

static func _can_profile_step(terrain: Object, from_cell: Vector2i, to_cell: Vector2i, profile: Object) -> bool:
	if terrain == null:
		return false
	var legal: bool = terrain.can_step_static(from_cell, to_cell, profile) if terrain.has_method("can_step_static") else bool(terrain.call("can_step", from_cell, to_cell))
	if not legal:
		return false
	if profile != null:
		var height_delta := absi(_height_of(terrain, from_cell) - _height_of(terrain, to_cell))
		return height_delta <= int(profile.get("max_step_height")) and (height_delta == 0 or bool(profile.get("can_use_ramp")))
	return true

## Builds the static macro path centerline from start to goal across terrain
## using FormationMovementProfile. Dynamic unit occupancy is ignored.
static func build_macro_path(terrain: Object, start: Vector2i, goal: Vector2i, profile: Object = null) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if terrain == null or not terrain.contains(start) or not terrain.contains(goal):
		return empty
	if start == goal:
		var single: Array[Vector2i] = [start]
		return single

	var max_step := 1
	var can_ramp := true
	if profile != null:
		max_step = int(profile.get("max_step_height"))
		can_ramp = bool(profile.get("can_use_ramp"))

	# A* static pathfinding using 4 cardinal directions
	var open_set: Array[Vector2i] = [start]
	var came_from: Dictionary = {}
	var g_score: Dictionary = { start: 0 }
	var f_score: Dictionary = { start: _heuristic(start, goal) }
	var closed_set: Dictionary = {}

	var neighbors: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

	var expansions := 0
	const MAX_MACRO_EXPANSIONS := 10000

	while not open_set.is_empty():
		var best_idx := 0
		var best_val: int = int(f_score.get(open_set[0], 999999))
		for i in range(1, open_set.size()):
			var val: int = int(f_score.get(open_set[i], 999999))
			if val < best_val:
				best_val = val
				best_idx = i

		var current: Vector2i = open_set[best_idx]
		if current == goal:
			var path: Array[Vector2i] = [current]
			var curr_trace := current
			while came_from.has(curr_trace):
				curr_trace = came_from[curr_trace]
				path.append(curr_trace)
			path.reverse()
			return path

		open_set.remove_at(best_idx)
		closed_set[current] = true
		expansions += 1
		if expansions > MAX_MACRO_EXPANSIONS:
			break

		for d in neighbors:
			var neighbor: Vector2i = current + d
			if not terrain.contains(neighbor) or closed_set.has(neighbor):
				continue

			# Check step legality
			if not _can_profile_step(terrain, current, neighbor, profile):
				continue

			# Height difference and ramp check
			var curr_h := _height_of(terrain, current)
			var next_h := _height_of(terrain, neighbor)
			var h_diff := absi(next_h - curr_h)
			if h_diff > max_step:
				continue
			if h_diff > 0 and not can_ramp:
				continue

			var step_cost := 10
			var tentative_g: int = int(g_score[current]) + step_cost

			if not g_score.has(neighbor) or tentative_g < int(g_score[neighbor]):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				f_score[neighbor] = tentative_g + _heuristic(neighbor, goal)
				if not open_set.has(neighbor):
					open_set.append(neighbor)

	return empty

## One shared static distance field for the transit leg. A physical step may
## only decrease this value; transient unit occupancy stays with the Grid.
static func get_transit_distance_field(move_plan: CombatMovePlan, terrain: Object, profile: Object) -> Dictionary:
	if move_plan == null or terrain == null or move_plan.macro_path.is_empty():
		return {}
	var goal: Vector2i = move_plan.macro_path[-1]
	var key := [move_plan.path_epoch, move_plan.terrain_revision, terrain.navigation_revision,
		int(profile.get("profile_hash")) if profile != null else 0, goal]
	if move_plan.get_meta("_transit_distance_key", []) == key:
		return move_plan.get_meta("_transit_distance_field", {})
	var distances: Dictionary = {goal: 0}
	var queue: Array[Vector2i] = [goal]
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		for direction: Vector2i in TerrainData.DIRECTIONS:
			var neighbor := cell + direction
			if distances.has(neighbor) or not terrain.contains(neighbor) or not _can_profile_step(terrain, neighbor, cell, profile):
				continue
			distances[neighbor] = int(distances[cell]) + 1
			queue.append(neighbor)
	move_plan.set_meta("_transit_distance_key", key)
	move_plan.set_meta("_transit_distance_field", distances)
	return distances

static func _heuristic(a: Vector2i, b: Vector2i) -> int:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return 10 * (dx + dy)

## Detects available corridor width perpendicular to the motion direction
static func detect_corridor_width(terrain: Object, center_cell: Vector2i, forward_dir: Vector2i, profile: Object = null) -> int:
	if terrain == null or not terrain.contains(center_cell):
		return 1

	var normal := Vector2i(-forward_dir.y, forward_dir.x)
	if normal == Vector2i.ZERO:
		normal = Vector2i(0, 1)
	elif normal.x != 0 and normal.y != 0:
		normal = Vector2i(-forward_dir.y, 0) if absi(forward_dir.x) >= absi(forward_dir.y) else Vector2i(0, forward_dir.x)
		if normal == Vector2i.ZERO:
			normal = Vector2i(0, 1)

	var max_step: int = int(profile.get("max_step_height")) if profile != null else 1
	var center_h := _height_of(terrain, center_cell)

	# Scan positive and negative normal directions
	var left_span := 0
	var prev_c := center_cell
	for step in range(1, MAX_TRANSIT_WIDTH):
		var test_cell := center_cell + normal * step
		if not terrain.contains(test_cell) or not terrain.is_walkable(test_cell) or absi(_height_of(terrain, test_cell) - center_h) > max_step:
			break
		if not _can_profile_step(terrain, prev_c, test_cell, profile):
			break
		prev_c = test_cell
		left_span += 1

	var right_span := 0
	prev_c = center_cell
	for step in range(1, MAX_TRANSIT_WIDTH):
		var test_cell := center_cell - normal * step
		if not terrain.contains(test_cell) or not terrain.is_walkable(test_cell) or absi(_height_of(terrain, test_cell) - center_h) > max_step:
			break
		if not _can_profile_step(terrain, prev_c, test_cell, profile):
			break
		prev_c = test_cell
		right_span += 1

	var total_width := 1 + left_span + right_span
	return clampi(total_width, 1, MAX_TRANSIT_WIDTH)

## Updates dynamic width with 3-tick hysteresis confirmation
static func update_width_hysteresis(move_plan: CombatMovePlan, detected_width: int) -> int:
	if move_plan == null:
		return 1
	var target_w := clampi(detected_width, 1, MAX_TRANSIT_WIDTH)
	if target_w == move_plan.current_width:
		move_plan.pending_width = target_w
		move_plan.width_confirm_counter = 0
	else:
		if target_w == move_plan.pending_width:
			move_plan.width_confirm_counter += 1
			if move_plan.width_confirm_counter >= WIDTH_CHANGE_CONFIRM_TICKS:
				move_plan.current_width = target_w
				move_plan.width_confirm_counter = 0
		else:
			move_plan.pending_width = target_w
			move_plan.width_confirm_counter = 1
	return move_plan.current_width

## Projects current lead position onto macro path monotonically
static func update_macro_cursor(move_plan: CombatMovePlan, current_lead_cell: Vector2i) -> int:
	if move_plan == null or move_plan.macro_path.is_empty():
		return 0
	var path_size := move_plan.macro_path.size()
	var search_start := maxi(0, move_plan.macro_cursor - 1)
	var search_end := mini(path_size - 1, move_plan.macro_cursor + 6)

	var best_idx := move_plan.macro_cursor
	var best_dist := 999999
	for i in range(search_start, search_end + 1):
		var pt := move_plan.macro_path[i]
		var dist: int = absi(pt.x - current_lead_cell.x) + absi(pt.y - current_lead_cell.y)
		if dist < best_dist:
			best_dist = dist
			best_idx = i

	move_plan.macro_cursor = maxi(move_plan.macro_cursor, best_idx)
	return move_plan.macro_cursor

static func _get_row_cross_section(
	move_plan: CombatMovePlan,
	s_idx: int,
	terrain: Object,
	profile: Object,
	lane_count: int
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var path_size := move_plan.macro_path.size()
	if s_idx < 0 or s_idx >= path_size:
		return result
	var center_cell: Vector2i = move_plan.macro_path[s_idx]
	if terrain != null and (not terrain.contains(center_cell) or not terrain.is_walkable(center_cell)):
		return result

	var f_dir := Vector2i(1, 0)
	if s_idx < path_size - 1:
		f_dir = move_plan.macro_path[s_idx + 1] - center_cell
	elif s_idx > 0:
		f_dir = center_cell - move_plan.macro_path[s_idx - 1]

	var normal := Vector2i(-f_dir.y, f_dir.x)
	if normal == Vector2i.ZERO:
		normal = Vector2i(0, 1)
	elif normal.x != 0 and normal.y != 0:
		normal = Vector2i(-f_dir.y, 0) if absi(f_dir.x) >= absi(f_dir.y) else Vector2i(0, f_dir.x)
		if normal == Vector2i.ZERO:
			normal = Vector2i(0, 1)

	var max_step: int = int(profile.get("max_step_height")) if profile != null else 1
	var valid_offsets: Array[int] = [0]
	var center_h := _height_of(terrain, center_cell)
	var p_c := center_cell
	for step in range(1, MAX_TRANSIT_WIDTH):
		var cand_c := center_cell + normal * step
		if terrain != null and terrain.contains(cand_c) and terrain.is_walkable(cand_c) and absi(_height_of(terrain, cand_c) - center_h) <= max_step and _can_profile_step(terrain, p_c, cand_c, profile):
			valid_offsets.append(step)
			p_c = cand_c
		else:
			break
	p_c = center_cell
	for step in range(1, MAX_TRANSIT_WIDTH):
		var cand_c := center_cell - normal * step
		if terrain != null and terrain.contains(cand_c) and terrain.is_walkable(cand_c) and absi(_height_of(terrain, cand_c) - center_h) <= max_step and _can_profile_step(terrain, p_c, cand_c, profile):
			valid_offsets.append(-step)
			p_c = cand_c
		else:
			break

	valid_offsets.sort_custom(func(a: int, b: int) -> bool:
		var aa := absi(a)
		var ab := absi(b)
		if aa != ab:
			return aa < ab
		return a > b
	)
	var count_for_row := mini(lane_count, valid_offsets.size())
	for oi in range(count_for_row):
		result.append(center_cell + normal * valid_offsets[oi])
	return result

static func _get_static_row_sections(move_plan: CombatMovePlan, terrain: Object, profile: Object) -> Array:
	var profile_hash: int = int(profile.get("profile_hash")) if profile != null else 0
	var cache_key := [move_plan.path_epoch, move_plan.terrain_revision, profile_hash, move_plan.macro_path.size()]
	var cached: Array = move_plan.get_meta("_transit_row_sections", [])
	if move_plan.get_meta("_transit_row_sections_key", []) == cache_key and cached.size() == move_plan.macro_path.size():
		return cached
	var sections: Array = []
	sections.resize(move_plan.macro_path.size())
	for k in range(sections.size()):
		sections[k] = _get_row_cross_section(move_plan, k, terrain, profile, MAX_TRANSIT_WIDTH)
	move_plan.set_meta("_transit_row_sections", sections)
	move_plan.set_meta("_transit_row_sections_key", cache_key)
	return sections

static func _find_furthest_verified_head_s(
	start_k: int,
	requested_k: int,
	move_plan: CombatMovePlan,
	terrain: Object,
	profile: Object
) -> float:
	if move_plan == null or move_plan.macro_path.is_empty():
		return float(start_k)
	var path_size := move_plan.macro_path.size()
	var safe_start_k := clampi(start_k, 0, path_size - 1)
	var safe_req_k := clampi(requested_k, safe_start_k, path_size - 1)
	if safe_req_k <= safe_start_k:
		return float(safe_start_k)

	var lane_count := clampi(move_plan.current_width, 1, MAX_TRANSIT_WIDTH)
	var prev_slots := _get_row_cross_section(move_plan, safe_start_k, terrain, profile, lane_count)
	if prev_slots.is_empty():
		return float(safe_start_k)

	var verified_k := safe_start_k
	for k in range(safe_start_k + 1, safe_req_k + 1):
		# 1. Path node validity / terrain revision check
		var center_cell: Vector2i = move_plan.macro_path[k]
		if terrain != null:
			if not terrain.contains(center_cell) or not terrain.is_walkable(center_cell):
				break
			var prev_center: Vector2i = move_plan.macro_path[k - 1]
			if not _can_profile_step(terrain, prev_center, center_cell, profile):
				break

		# 2. Width hysteresis confirmation check
		if move_plan.pending_width != move_plan.current_width and move_plan.width_confirm_counter > 0:
			var fwd := Vector2i(1, 0)
			if k < path_size - 1:
				fwd = move_plan.macro_path[k + 1] - center_cell
			var w_at_k := detect_corridor_width(terrain, center_cell, fwd, profile)
			if w_at_k != move_plan.current_width:
				break

		# Queue admission is resolved per member; a global stop line traps platform members.
		# Cross-section generation & legal predecessor connectivity check
		var cur_slots := _get_row_cross_section(move_plan, k, terrain, profile, lane_count)
		if cur_slots.is_empty():
			break

		var has_legal_transition := false
		for cand in cur_slots:
			if _has_legal_predecessor(prev_slots, cand, terrain, profile):
				has_legal_transition = true
				break
		if not has_legal_transition:
			break

		# 5. Check for duplicate slots across adjacent rows at tight turns
		var has_overlap := false
		for cand in cur_slots:
			if prev_slots.has(cand):
				has_overlap = true
				break
		if has_overlap and cur_slots.size() == 1 and prev_slots.size() == 1:
			break

		prev_slots = cur_slots
		verified_k = k

	return float(verified_k)

## Generates unique transit slots along macro path for each member
static func calculate_transit_slots(
	move_plan: CombatMovePlan,
	terrain: Object,
	profile: Object,
	member_ids: Array[int],
	current_cells: Dictionary
) -> Dictionary:
	var result: Dictionary = {}
	if move_plan == null or move_plan.macro_path.is_empty() or member_ids.is_empty():
		return result
	if move_plan.destination_plan != null:
		var plan: CombatDeploymentPlan = move_plan.destination_plan
		var scan_key := Vector2i(move_plan.path_epoch, move_plan.terrain_revision)
		if plan.approach_bottlenecked < 0 or plan.get_meta("_transit_bottleneck_scan_key", Vector2i(-1, -1)) != scan_key:
			var has_choke := false
			var last_choke_cell := Vector2i(-1, -1)
			for k in range(move_plan.macro_path.size() - 1, -1, -1):
				var center: Vector2i = move_plan.macro_path[k]
				var forward := Vector2i.RIGHT
				if k + 1 < move_plan.macro_path.size():
					forward = move_plan.macro_path[k + 1] - center
				elif k > 0:
					forward = center - move_plan.macro_path[k - 1]
				if detect_corridor_width(terrain, center, forward, profile) == 1:
					has_choke = true
					last_choke_cell = center
					break
			plan.set_approach_bottlenecked(has_choke, last_choke_cell)
			plan.set_meta("_transit_bottleneck_scan_key", scan_key)
	var flow_mids: Array[int] = []
	var other_mids: Array[int] = []
	for mid in member_ids:
		if move_plan.destination_plan == null or (move_plan.destination_plan.member_role_map.has(mid) and move_plan.destination_plan.is_platform_member(mid) and (not move_plan.destination_plan.admitted_platform_member_ids.has(mid) or move_plan.destination_plan.needs_transit_soft_target(mid, current_cells.get(mid, Vector2i(-1, -1))))):
			flow_mids.append(mid)
		else:
			other_mids.append(mid)
	if flow_mids.is_empty():
		move_plan.member_transit_slots.clear()
		return result

	var path_size := move_plan.macro_path.size()
	var static_rows := _get_static_row_sections(move_plan, terrain, profile)
	var prior_slots: Dictionary = move_plan.member_transit_slots.duplicate()
	var inertia_key := [move_plan.path_epoch, move_plan.terrain_revision, int(profile.get("profile_hash")) if profile != null else 0]
	var inertia_valid: bool = move_plan.get_meta("_transit_soft_key", []) == inertia_key
	var prior_retry: Dictionary = move_plan.get_meta("_transit_soft_retry", {}) if inertia_valid else {}
	var prior_cells: Dictionary = move_plan.get_meta("_transit_soft_cells", {}) if inertia_valid else {}
	var debug_soft_rejects: bool = bool(move_plan.get_meta("_transit_soft_debug_enabled", false))
	var soft_reject_counts: Dictionary = move_plan.get_meta("_transit_soft_reject_counts", {}) if debug_soft_rejects else {}
	var lane_count := clampi(move_plan.current_width, 1, MAX_TRANSIT_WIDTH)
	var requested_lookahead := clampi(
		maxi(MIN_TRANSIT_LOOKAHEAD_ROWS, lane_count),
		MIN_TRANSIT_LOOKAHEAD_ROWS,
		MAX_TRANSIT_LOOKAHEAD_ROWS
	)
	var requested_head_s := mini(move_plan.macro_cursor + requested_lookahead, path_size - 1)
	var head_s := _find_furthest_verified_head_s(move_plan.macro_cursor, requested_head_s, move_plan, terrain, profile)
	var allocated_cells: Dictionary = {} # cell -> member_id
	var prior_sequence_rank: Dictionary = move_plan.member_sequence_rank.duplicate()

	# Observe current physical order before assigning rows. Historical best_s is only
	# progress evidence and must never move a soldier ahead of someone now in front.
	for i in range(flow_mids.size()):
		var mid := flow_mids[i]
		if not move_plan.member_sequence_rank.has(mid):
			move_plan.member_sequence_rank[mid] = i
		if not move_plan.member_observed_path_s.has(mid) and current_cells.has(mid):
			var c: Vector2i = current_cells[mid]
			var nearest_k := 0
			var nearest_dist := 999999
			for k in range(path_size):
				var d: int = absi(move_plan.macro_path[k].x - c.x) + absi(move_plan.macro_path[k].y - c.y)
				if d < nearest_dist:
					nearest_dist = d
					nearest_k = k
			move_plan.member_observed_path_s[mid] = float(nearest_k) - float(nearest_dist) * 0.25

	var sorted_mids: Array[int] = flow_mids.duplicate()
	sorted_mids.sort_custom(func(a: int, b: int) -> bool:
		var sa: float = float(move_plan.member_observed_path_s.get(a, -9999.0))
		var sb: float = float(move_plan.member_observed_path_s.get(b, -9999.0))
		if sa != sb:
			return sa > sb
		var ra: int = int(move_plan.member_sequence_rank.get(a, 9999))
		var rb: int = int(move_plan.member_sequence_rank.get(b, 9999))
		return ra < rb if ra != rb else a < b
	)
	for i in range(sorted_mids.size()):
		move_plan.member_sequence_rank[sorted_mids[i]] = i
	# Each row uses its own legal width. A soldier may only receive a slot
	# beyond a one-cell passage after physically crossing it; one extra slot
	# on the narrow row admits the next soldier. Checkpoints exclude soft-target
	# projection, which can run far ahead of the actual occupied cell.
	var tail_k: int = int(head_s)
	var crossed_by_k := PackedInt32Array()
	crossed_by_k.resize(path_size)
	var exact_path_k: Dictionary = {}
	var physical_path_k: Dictionary = {}
	var exact_on_path: Dictionary = {}
	for k in range(path_size):
		exact_path_k[move_plan.macro_path[k]] = k
	for mid in sorted_mids:
		var checkpoint_k: int = clampi(int(move_plan.member_checkpoint_path_k.get(mid, 0)), 0, path_size - 1)
		if current_cells.has(mid):
			var cell: Vector2i = current_cells[mid]
			var center_k: int = int(exact_path_k.get(cell, -1))
			if center_k >= 0:
				# An occupied centerline cell is direct physical evidence, even
				# when the conservative +1-per-step checkpoint still lags.
				checkpoint_k = center_k
				exact_on_path[mid] = true
			else:
				var adjacent_k := -1
				for direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
					var adjacent: Vector2i = cell + direction
					if exact_path_k.has(adjacent) and _can_profile_step(terrain, cell, adjacent, profile):
						adjacent_k = maxi(adjacent_k, int(exact_path_k[adjacent]))
				if adjacent_k >= 0:
					# A lateral cell may have an older high checkpoint, but it has
					# not physically passed the adjacent centerline cell today.
					checkpoint_k = mini(checkpoint_k, adjacent_k)
		physical_path_k[mid] = checkpoint_k
		tail_k = mini(tail_k, checkpoint_k)
		crossed_by_k[checkpoint_k] += 1
	var crossed := 0
	for k in range(path_size - 1, -1, -1):
		crossed += crossed_by_k[k]
		crossed_by_k[k] = crossed
	var choke_ks: Array[int] = []
	for k in range(maxi(0, tail_k), int(head_s) + 1):
		if static_rows[k].size() == 1:
			choke_ks.append(k)
	if not choke_ks.is_empty():
		sorted_mids.sort_custom(func(a: int, b: int) -> bool:
			var ka: int = int(physical_path_k.get(a, 0))
			var kb: int = int(physical_path_k.get(b, 0))
			if ka != kb:
				return ka > kb
			if exact_on_path.has(a) != exact_on_path.has(b):
				return exact_on_path.has(a)
			# Equal physical checkpoints do not prove a pass. Keep the established
			# queue order instead of letting fractional path projection jitter swap
			# their gate and rear targets every planning tick.
			if prior_sequence_rank.has(a) and prior_sequence_rank.has(b):
				var ra: int = int(prior_sequence_rank[a])
				var rb: int = int(prior_sequence_rank[b])
				if ra != rb:
					return ra < rb
			var sa: float = float(move_plan.member_observed_path_s.get(a, -9999.0))
			var sb: float = float(move_plan.member_observed_path_s.get(b, -9999.0))
			if sa != sb:
				return sa > sb
			return a < b
		)
		for i in range(sorted_mids.size()):
			move_plan.member_sequence_rank[sorted_mids[i]] = i
	other_mids.sort_custom(func(a: int, b: int) -> bool:
		var ra: int = int(move_plan.member_sequence_rank.get(a, 9999))
		var rb: int = int(move_plan.member_sequence_rank.get(b, 9999))
		return ra < rb if ra != rb else a < b
	)
	for i in range(other_mids.size()):
		move_plan.member_sequence_rank[other_mids[i]] = sorted_mids.size() + i

	# Build capacity sequence along macro_path from head_s downwards
	var available_slots: Array[Dictionary] = [] # Array of {"slot": Vector2i, "s": float}
	var row_slot_groups: Array[Array] = [] # Array of Array[Dictionary] per row
	var prev_row_slots: Array[Vector2i] = []
	var occupied_nonflow: Dictionary = {}
	for mid in other_mids:
		if current_cells.has(mid):
			occupied_nonflow[current_cells[mid]] = true
	var choke_cursor := choke_ks.size() - 1

	var r := 0
	while true:
		var cur_s := head_s - float(r) * MEMBER_SPACING
		if cur_s < 0.0:
			break
		var s_idx := clampi(floori(cur_s), 0, path_size - 1)
		var row_candidates: Array = static_rows[s_idx]
		var cur_row_slots: Array[Vector2i] = []
		var cur_row_slot_items: Array[Dictionary] = []
		while choke_cursor >= 0 and choke_ks[choke_cursor] > s_idx:
			choke_cursor -= 1
		var count_for_row := row_candidates.size()
		if choke_cursor >= 0:
			var choke_k := choke_ks[choke_cursor]
			var allowed_across := crossed_by_k[choke_k]
			if s_idx == choke_k:
				allowed_across += 1
				if choke_cursor > 0:
					allowed_across = mini(allowed_across, crossed_by_k[choke_ks[choke_cursor - 1]])
			count_for_row = mini(count_for_row, maxi(0, allowed_across - available_slots.size()))
		for oi in range(count_for_row):
			var cand_slot: Vector2i = row_candidates[oi]
			if not allocated_cells.has(cand_slot) and not occupied_nonflow.has(cand_slot) and _has_legal_predecessor(prev_row_slots, cand_slot, terrain, profile):
				allocated_cells[cand_slot] = -1
				cur_row_slots.append(cand_slot)
				var item := {"slot": cand_slot, "s": cur_s, "row": row_slot_groups.size()}
				available_slots.append(item)
				cur_row_slot_items.append(item)

		if not cur_row_slots.is_empty():
			prev_row_slots = cur_row_slots
			row_slot_groups.append(cur_row_slot_items)
		else:
			prev_row_slots.clear()
		r += 1
		if available_slots.size() >= sorted_mids.size() + MAX_TRANSIT_WIDTH:
			break

	# Spatial Zipper Merge assignment (row-by-row to preserve vanguard order and prevent lateral crossover)
	var member_cursor := 0
	for row_idx in range(row_slot_groups.size()):
		var row_slots: Array = row_slot_groups[row_idx]
		var k_row := row_slots.size()
		if member_cursor >= sorted_mids.size():
			break
		var end_idx := mini(sorted_mids.size(), member_cursor + k_row)
		var row_mids: Array[int] = sorted_mids.slice(member_cursor, end_idx)

		if row_mids.size() > 1:
			var s_idx := clampi(floori(float(row_slots[0]["s"])), 0, path_size - 1)
			var fwd_row := Vector2i(1, 0)
			if s_idx < path_size - 1:
				fwd_row = move_plan.macro_path[s_idx + 1] - move_plan.macro_path[s_idx]
			elif s_idx > 0:
				fwd_row = move_plan.macro_path[s_idx] - move_plan.macro_path[s_idx - 1]
			var side_row := Vector2i(-fwd_row.y, fwd_row.x)
			if side_row == Vector2i.ZERO:
				side_row = Vector2i(0, 1)
			elif side_row.x != 0 and side_row.y != 0:
				side_row = Vector2i(-fwd_row.y, 0) if absi(fwd_row.x) >= absi(fwd_row.y) else Vector2i(0, fwd_row.x)
				if side_row == Vector2i.ZERO:
					side_row = Vector2i(0, 1)

			row_mids.sort_custom(func(a: int, b: int) -> bool:
				var ca: Vector2i = current_cells.get(a, move_plan.macro_path[0])
				var cb: Vector2i = current_cells.get(b, move_plan.macro_path[0])
				var sa := ca.x * side_row.x + ca.y * side_row.y
				var sb := cb.x * side_row.x + cb.y * side_row.y
				if sa != sb:
					return sa < sb
				return int(move_plan.member_sequence_rank.get(a, 9999)) < int(move_plan.member_sequence_rank.get(b, 9999))
			)
			row_slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var sa_slot: Vector2i = a["slot"]
				var sb_slot: Vector2i = b["slot"]
				var sa := sa_slot.x * side_row.x + sa_slot.y * side_row.y
				var sb := sb_slot.x * side_row.x + sb_slot.y * side_row.y
				if sa != sb:
					return sa < sb
				return float(a.get("s", 0.0)) > float(b.get("s", 0.0))
			)

		for i in range(row_mids.size()):
			var mid: int = row_mids[i]
			var slot: Vector2i = row_slots[i]["slot"]
			var s_val: float = float(row_slots[i]["s"])
			result[mid] = slot
			allocated_cells[slot] = mid
			move_plan.member_path_s[mid] = s_val
			move_plan.member_row_map[mid] = row_idx
			move_plan.member_lane_map[mid] = i
			move_plan.pre_route_staging_slots.erase(mid)

		member_cursor = end_idx

	# Remaining members beyond path slots get staging slots
	for i in range(member_cursor, sorted_mids.size()):
		var mid: int = sorted_mids[i]
		var rank: int = int(move_plan.member_sequence_rank.get(mid, 0))
		var row_idx := floori(float(rank) / float(lane_count))
		var desired_s := -1.0 - float(row_idx) * MEMBER_SPACING
		move_plan.member_path_s[mid] = desired_s
		move_plan.member_row_map[mid] = row_idx
		move_plan.member_lane_map[mid] = rank % lane_count

		var staging_candidate: Vector2i = move_plan.pre_route_staging_slots.get(
			mid,
			current_cells.get(mid, move_plan.macro_path[0])
		)
		var legal_staging := _legalize_staging_slot(staging_candidate, terrain, profile, allocated_cells)
		move_plan.pre_route_staging_slots[mid] = legal_staging
		allocated_cells[legal_staging] = mid
		result[mid] = legal_staging

	# Retain a legal soft target only inside its own wide section. A one-cell
	# passage and its adjacent rows keep the zipper output exactly: shifting a
	# gate assignment can strand the physically front soldier behind a side one.
	# With no active choke, keep the earlier open-ground behavior unchanged.
	var active_gate := not choke_ks.is_empty()
	var default_slot_owner: Dictionary = {}
	for mid in result.keys():
		default_slot_owner[result[mid]] = mid
	var wide_segment_at_k := PackedInt32Array()
	wide_segment_at_k.resize(path_size)
	var gates_ahead := 0
	if active_gate:
		for k in range(head_s, -1, -1):
			wide_segment_at_k[k] = gates_ahead
			if static_rows[k].size() == 1:
				gates_ahead += 1
	var segment_candidates: Dictionary = {}
	for row_slots in row_slot_groups:
		if row_slots.is_empty():
			continue
		var row_s_idx := clampi(floori(float(row_slots[0]["s"])), 0, path_size - 1)
		var segment_id: int = wide_segment_at_k[row_s_idx] if active_gate else 0
		var gate_adjacent: bool = active_gate and (static_rows[row_s_idx].size() == 1 \
			or row_s_idx > 0 and static_rows[row_s_idx - 1].size() == 1 \
			or row_s_idx < head_s and static_rows[row_s_idx + 1].size() == 1)
		if gate_adjacent:
			if debug_soft_rejects and inertia_valid:
				for item: Dictionary in row_slots:
					var owner: int = int(default_slot_owner.get(item["slot"], -1))
					if owner >= 0 and prior_slots.has(owner) and prior_slots[owner] != item["slot"]:
						soft_reject_counts["gate_adjacency"] = int(soft_reject_counts.get("gate_adjacency", 0)) + 1
			continue
		var row_dir := Vector2i.RIGHT
		if row_s_idx < path_size - 1:
			row_dir = move_plan.macro_path[row_s_idx + 1] - move_plan.macro_path[row_s_idx]
		elif row_s_idx > 0:
			row_dir = move_plan.macro_path[row_s_idx] - move_plan.macro_path[row_s_idx - 1]
		var row_side := Vector2i(-row_dir.y, row_dir.x)
		row_slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ac: Vector2i = a["slot"]
			var bc: Vector2i = b["slot"]
			var assigned_a: bool = default_slot_owner.has(ac)
			var assigned_b: bool = default_slot_owner.has(bc)
			if assigned_a != assigned_b:
				return assigned_a
			if assigned_a:
				return int(move_plan.member_lane_map[default_slot_owner[ac]]) < int(move_plan.member_lane_map[default_slot_owner[bc]])
			return ac.x * row_side.x + ac.y * row_side.y < bc.x * row_side.x + bc.y * row_side.y
		)
		var candidates: Array = segment_candidates.get(segment_id, [])
		for lane_i in range(row_slots.size()):
			var candidate: Dictionary = row_slots[lane_i]
			candidate["lane"] = lane_i
			candidates.append(candidate)
		segment_candidates[segment_id] = candidates
	for segment_id in segment_candidates.keys():
		var ordered_candidates: Array = segment_candidates[segment_id]
		var candidate_index: Dictionary = {}
		for i in range(ordered_candidates.size()):
			candidate_index[ordered_candidates[i]["slot"]] = i
		var ordered_mids: Array[int] = []
		for mid in sorted_mids:
			if result.has(mid) and candidate_index.has(result[mid]):
				ordered_mids.append(mid)
		ordered_mids.sort_custom(func(a: int, b: int) -> bool:
			var ar: int = int(move_plan.member_row_map.get(a, 9999))
			var br: int = int(move_plan.member_row_map.get(b, 9999))
			if ar != br:
				return ar < br
			return int(move_plan.member_lane_map.get(a, 9999)) < int(move_plan.member_lane_map.get(b, 9999))
		)
		var next_candidate := 0
		for i in range(ordered_mids.size()):
			var mid: int = ordered_mids[i]
			var chosen := next_candidate
			var old_slot: Vector2i = prior_slots.get(mid, Vector2i(-1, -1))
			var old_index: int = int(candidate_index.get(old_slot, -1))
			var retry_now: int = int(move_plan.member_route_retry_count.get(mid, 0))
			var retry_then: int = int(prior_retry.get(mid, retry_now))
			var physically_past: bool = old_index >= 0 and int(physical_path_k.get(mid, 0)) > floori(float(ordered_candidates[old_index]["s"]))
			var retrying: bool = retry_now - retry_then >= 3 or int(move_plan.member_defer_count.get(mid, 0)) >= 8
			# A moving member may keep a legal target within its current wide
			# section; a one-cell gate still separates the queue on either side.
			var same_wide_section: bool = old_index >= 0 and wide_segment_at_k[int(physical_path_k.get(mid, 0))] == segment_id
			var retained: bool = inertia_valid and old_index >= next_candidate and old_index <= ordered_candidates.size() - (ordered_mids.size() - i) \
					and (not active_gate or same_wide_section or current_cells.get(mid, Vector2i(-1, -1)) == prior_cells.get(mid, Vector2i(-2, -2))) \
					and current_cells.get(mid, Vector2i(-1, -1)) != old_slot and not physically_past and not retrying
			if retained:
				chosen = old_index
			elif debug_soft_rejects and inertia_valid and prior_slots.has(mid) and old_slot != result[mid]:
				var reason := ""
				if old_index < 0:
					reason = "old_index_absent"
				elif old_index < next_candidate or old_index > ordered_candidates.size() - (ordered_mids.size() - i):
					_count_capacity_reject(soft_reject_counts, old_index, next_candidate, ordered_candidates.size() - (ordered_mids.size() - i), current_cells.get(mid, Vector2i(-1, -1)) == prior_cells.get(mid, Vector2i(-2, -2)), active_gate)
				elif active_gate and not same_wide_section and current_cells.get(mid, Vector2i(-1, -1)) != prior_cells.get(mid, Vector2i(-2, -2)):
					reason = "section_mismatch"
				elif physically_past:
					reason = "physical_past"
				elif retrying:
					reason = "retry_defer"
				if not reason.is_empty():
					soft_reject_counts[reason] = int(soft_reject_counts.get(reason, 0)) + 1
			var kept: Dictionary = ordered_candidates[chosen]
			result[mid] = kept["slot"]
			move_plan.member_path_s[mid] = float(kept["s"])
			move_plan.member_row_map[mid] = int(kept["row"])
			move_plan.member_lane_map[mid] = int(kept["lane"])
			next_candidate = chosen + 1

	for mid in result.keys():
		if move_plan.member_transit_slots.get(mid, Vector2i(-1, -1)) != result[mid]:
			move_plan.assignment_epoch += 1
			move_plan.member_soft_assignment_epoch[mid] = int(move_plan.member_soft_assignment_epoch.get(mid, 0)) + 1
	var next_retry: Dictionary = {}
	var next_cells: Dictionary = {}
	for mid in result.keys():
		var retry_now: int = int(move_plan.member_route_retry_count.get(mid, 0))
		next_retry[mid] = int(prior_retry.get(mid, retry_now)) if inertia_valid and prior_slots.get(mid, Vector2i(-1, -1)) == result[mid] else retry_now
		next_cells[mid] = current_cells.get(mid, Vector2i(-1, -1))
	move_plan.set_meta("_transit_soft_key", inertia_key)
	move_plan.set_meta("_transit_soft_retry", next_retry)
	move_plan.set_meta("_transit_soft_cells", next_cells)
	if debug_soft_rejects:
		move_plan.set_meta("_transit_soft_reject_counts", soft_reject_counts)
	move_plan.member_transit_slots = result
	return result

static func _has_legal_predecessor(prev_slots: Array[Vector2i], cand: Vector2i, terrain: Object, profile: Object) -> bool:
	if prev_slots.is_empty():
		return true
	var max_step: int = int(profile.get("max_step_height")) if profile != null else 1
	var cand_h := _height_of(terrain, cand)
	for p in prev_slots:
		var diff := p - cand
		var dist := absi(diff.x) + absi(diff.y)
		if dist <= 2:
			if terrain == null:
				return true
			if absi(_height_of(terrain, p) - cand_h) <= max_step:
				if dist == 1:
					if terrain.has_method("can_step_static"):
						if terrain.can_step_static(cand, p, profile):
							return true
					elif _can_profile_step(terrain, cand, p, profile):
						return true
				else:
					var mid1 := Vector2i(cand.x, p.y)
					var mid2 := Vector2i(p.x, cand.y)
					if terrain.has_method("can_step_static"):
						if terrain.contains(mid1) and terrain.is_walkable(mid1) and terrain.can_step_static(cand, mid1, profile) and terrain.can_step_static(mid1, p, profile):
							return true
						if terrain.contains(mid2) and terrain.is_walkable(mid2) and terrain.can_step_static(cand, mid2, profile) and terrain.can_step_static(mid2, p, profile):
							return true
					else:
						if terrain.contains(mid1) and terrain.is_walkable(mid1) and _can_profile_step(terrain, cand, mid1, profile) and _can_profile_step(terrain, mid1, p, profile):
							return true
						if terrain.contains(mid2) and terrain.is_walkable(mid2) and _can_profile_step(terrain, cand, mid2, profile) and _can_profile_step(terrain, mid2, p, profile):
							return true
	return false

static func _legalize_staging_slot(
	ideal: Vector2i,
	terrain: Object,
	profile: Object,
	allocated: Dictionary
) -> Vector2i:
	if not allocated.has(ideal) and (terrain == null or (terrain.contains(ideal) and terrain.is_walkable(ideal))):
		return ideal
	var queue: Array[Vector2i] = [ideal]
	var visited: Dictionary = { ideal: true }
	var head := 0
	var max_step: int = int(profile.get("max_step_height")) if profile != null else 1
	var root_h := _height_of(terrain, ideal)
	const NEIGHBORS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

	while head < queue.size() and head < 60:
		var curr := queue[head]
		head += 1
		for d in NEIGHBORS:
			var n := curr + d
			if visited.has(n):
				continue
			visited[n] = true
			if absi(n.x - ideal.x) + absi(n.y - ideal.y) > 6:
				continue
			if terrain != null:
				if not terrain.contains(n) or not terrain.is_walkable(n):
					continue
				if not _can_profile_step(terrain, curr, n, profile):
					continue
				if absi(_height_of(terrain, n) - root_h) > max_step:
					continue
			if not allocated.has(n):
				return n
			queue.append(n)
	return ideal

static func _legalize_unique_slot(
	ideal: Vector2i,
	terrain: Object,
	profile: Object,
	allocated: Dictionary,
	fallback_center: Vector2i = Vector2i(-1, -1)
) -> Vector2i:
	if _is_legal_slot(ideal, terrain, profile, allocated, fallback_center):
		return ideal

	if fallback_center != Vector2i(-1, -1) and _is_legal_slot(fallback_center, terrain, profile, allocated, fallback_center):
		return fallback_center

	# Connected BFS expansion: only search traversable ground connected to fallback_center or ideal
	var root: Vector2i = fallback_center if (fallback_center != Vector2i(-1, -1) and terrain != null and terrain.contains(fallback_center)) else ideal
	var queue: Array[Vector2i] = [root]
	var visited: Dictionary = { root: true }
	var head := 0
	var max_step: int = int(profile.get("max_step_height")) if profile != null else 1
	var root_h := _height_of(terrain, root)
	const NEIGHBORS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

	while head < queue.size() and queue.size() < 300:
		var curr := queue[head]
		head += 1
		for d in NEIGHBORS:
			var n := curr + d
			if visited.has(n):
				continue
			visited[n] = true
			if terrain != null:
				if not terrain.contains(n) or not terrain.is_walkable(n):
					continue
				if not _can_profile_step(terrain, curr, n, profile):
					continue
				if absi(_height_of(terrain, n) - root_h) > max_step:
					continue
			if not allocated.has(n):
				return n
			queue.append(n)

	return ideal

static func _is_legal_slot(cell: Vector2i, terrain: Object, profile: Object, allocated: Dictionary, base_ref: Vector2i = Vector2i(-1, -1)) -> bool:
	if allocated.has(cell):
		return false
	if terrain != null:
		if not terrain.contains(cell):
			return false
		if not terrain.is_walkable(cell):
			return false
		var max_step: int = int(profile.get("max_step_height")) if profile != null else 1
		if base_ref != Vector2i(-1, -1) and base_ref != cell:
			var diff := cell - base_ref
			if (absi(diff.x) + absi(diff.y) == 1):
				if not _can_profile_step(terrain, base_ref, cell, profile):
					return false
			else:
				if absi(_height_of(terrain, cell) - _height_of(terrain, base_ref)) > max_step:
					return false
	return true
