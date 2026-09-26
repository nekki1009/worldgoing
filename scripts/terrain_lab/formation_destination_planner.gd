class_name FormationDestinationPlanner
extends RefCounted
## Destination and footprint planner for adaptive army deployment.
## Handles platform flood-filling, 60-platform + 40-approach queue partitioning,
## deep-to-shallow slot assignment, and the Ingress Admission Gate.

const Types = preload("res://scripts/terrain_lab/combat_movement_types.gd")
const TransitPlanner = preload("res://scripts/terrain_lab/formation_transit_planner.gd")

const MAX_PLATFORM_RADIUS := 12
const MAX_PRESET_RADIUS := 24
const PRESET_IDS := ["auto", "square", "wedge", "goose", "circle", "hook", "loose"]
const INGRESS_BUFFER_LENGTH := 3
const PLATFORM_RECOVERY_STALL_SEC := 1.75
const PLATFORM_RECOVERY_COOLDOWN_SEC := 0.5

static func is_valid_preset(preset_id: String) -> bool:
	return PRESET_IDS.has(preset_id)

## Fixed local cells are centered once, then rotated by integer basis vectors.
static func shape_slots(preset_id: String, count: int, anchor: Vector2i, facing: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if preset_id == "auto" or not is_valid_preset(preset_id) or count < 1 or count > 200 or facing not in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		return result
	var local: Array[Vector2i] = []
	var width := ceili(sqrt(float(count)))
	match preset_id:
		"square", "loose", "goose":
			for row in range(ceili(float(count) / float(width))):
				var row_count: int = mini(width, count - local.size())
				var left: int = floori(float(width - row_count) / 2.0)
				for column in range(row_count):
					var u: int = column + left + (row if preset_id == "goose" else 0)
					local.append(Vector2i(u, -row))
		"wedge":
			var row := 0
			while local.size() < count:
				var row_width: int = row * 2 + 1
				var row_count: int = mini(row_width, count - local.size())
				var left: int = floori(float(row_width - row_count) / 2.0)
				for column in range(row_count):
					local.append(Vector2i(column + left - row, -row))
				row += 1
		"circle":
			var radius: int = width
			for v in range(-radius, radius + 1):
				for u in range(-radius, radius + 1):
					local.append(Vector2i(u, v))
			local.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
				var da: int = a.length_squared()
				var db: int = b.length_squared()
				if da != db:
					return da < db
				var outer_a: int = maxi(absi(a.x), absi(a.y))
				var outer_b: int = maxi(absi(b.x), absi(b.y))
				if outer_a != outer_b:
					return outer_a < outer_b
				var quadrant_a: int = (0 if a.x >= 0 else 2) + (0 if a.y >= 0 else 1)
				var quadrant_b: int = (0 if b.x >= 0 else 2) + (0 if b.y >= 0 else 1)
				if quadrant_a != quadrant_b:
					return quadrant_a < quadrant_b
				return a.x < b.x if a.x != b.x else a.y < b.y
			)
			local.resize(count)
		"hook":
			var thickness: int = maxi(1, ceili(sqrt(float(count)) / 4.0))
			var length: int = maxi(thickness, ceili(float(count + 2 * thickness * thickness) / float(3 * thickness)))
			for row in range(length):
				var columns: Array[int] = []
				if row < thickness:
					for column in range(length):
						columns.append(column)
					columns.sort_custom(func(a: int, b: int) -> bool:
						var da: int = absi(2 * a - length + 1)
						var db: int = absi(2 * b - length + 1)
						return da < db if da != db else a < b
					)
				else:
					for column in range(thickness):
						columns.append(column)
						if length - 1 - column != column:
							columns.append(length - 1 - column)
				for column in columns:
					if local.size() >= count:
						break
					local.append(Vector2i(column, -row))
				if local.size() >= count:
					break
	if local.size() != count:
		return result
	if preset_id == "loose":
		for i in range(local.size()):
			local[i] *= 2
	if preset_id != "circle":
		var min_u := local[0].x
		var max_u := local[0].x
		var min_v := local[0].y
		var max_v := local[0].y
		for cell in local:
			min_u = mini(min_u, cell.x)
			max_u = maxi(max_u, cell.x)
			min_v = mini(min_v, cell.y)
			max_v = maxi(max_v, cell.y)
		var center := Vector2i(floori(float(min_u + max_u) / 2.0), floori(float(min_v + max_v) / 2.0))
		for i in range(local.size()):
			local[i] -= center
	var side := Vector2i(-facing.y, facing.x)
	for cell in local:
		result.append(anchor + side * cell.x + facing * cell.y)
	return result

static func preset_footprint_radius(preset_id: String, count: int) -> int:
	if preset_id == "auto":
		return MAX_PLATFORM_RADIUS
	var offsets := shape_slots(preset_id, count, Vector2i.ZERO, Vector2i.RIGHT)
	if offsets.is_empty():
		return -1
	var radius := MAX_PLATFORM_RADIUS
	for offset in offsets:
		radius = maxi(radius, maxi(absi(offset.x), absi(offset.y)) + 1)
	return radius if radius <= MAX_PRESET_RADIUS else -1

static func _height_of(terrain: Object, cell: Vector2i) -> int:
	if terrain == null or not terrain.contains(cell):
		return 0
	if "height_levels" in terrain:
		var idx: int = terrain.index(cell)
		return int(terrain.height_levels[idx])
	return 0

## Discovers platform footprint starting from anchor
static func build_platform_footprint(
	terrain: Object,
	anchor: Vector2i,
	macro_path: Array[Vector2i],
	max_radius: int = MAX_PLATFORM_RADIUS,
	profile: Object = null
) -> Dictionary:
	var empty: Dictionary = {
		"platform_cells": [],
		"ingress_cell": anchor,
		"ingress_path_buffer": []
	}
	if terrain == null or not terrain.contains(anchor):
		return empty

	var anchor_h := _height_of(terrain, anchor)

	# Flood-fill platform cells of the same height level
	var platform_cells: Array[Vector2i] = []
	var open_set: Array[Vector2i] = [anchor]
	var visited: Dictionary = { anchor: true }

	var neighbors: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

	while not open_set.is_empty():
		var curr: Vector2i = open_set.pop_front()
		platform_cells.append(curr)

		for d in neighbors:
			var n: Vector2i = curr + d
			if visited.has(n) or not terrain.contains(n):
				continue
			if absi(n.x - anchor.x) > max_radius or absi(n.y - anchor.y) > max_radius:
				continue
			if not terrain.is_walkable(n):
				continue
			if _height_of(terrain, n) != anchor_h:
				continue
			if not TransitPlanner._can_profile_step(terrain, curr, n, profile):
				continue

			visited[n] = true
			open_set.append(n)

	# Identify ingress_cell: first cell on macro_path that enters platform footprint
	var footprint_set: Dictionary = {}
	for c in platform_cells:
		footprint_set[c] = true

	var ingress_cell := anchor
	var ingress_path_idx := -1
	for i in range(macro_path.size()):
		if footprint_set.has(macro_path[i]):
			ingress_cell = macro_path[i]
			ingress_path_idx = i
			break

	# Ingress buffer cells (up to INGRESS_BUFFER_LENGTH cells immediately preceding ingress)
	var ingress_buffer: Array[Vector2i] = []
	if ingress_path_idx > 0:
		var buf_start := maxi(0, ingress_path_idx - INGRESS_BUFFER_LENGTH)
		for i in range(buf_start, ingress_path_idx):
			ingress_buffer.append(macro_path[i])

	return {
		"platform_cells": platform_cells,
		"ingress_cell": ingress_cell,
		"ingress_path_buffer": ingress_buffer,
		"ingress_path_index": ingress_path_idx
	}

static func refresh_derived_ingress(plan: CombatDeploymentPlan, terrain: Object, macro_path: Array[Vector2i], profile: Object = null) -> bool:
	if plan == null or terrain == null or macro_path.is_empty():
		return false
	var radius := preset_footprint_radius(plan.formation_preset_id, plan.requested_count)
	if radius < 0:
		return false
	var footprint := build_platform_footprint(terrain, plan.resolved_anchor, macro_path, radius, profile)
	var cells: Array = footprint.get("platform_cells", [])
	if cells.is_empty():
		return false
	for slot in plan.platform_slots:
		if not cells.has(slot):
			return false
	for slot in plan.member_slot_map.values():
		if not terrain.contains(slot) or not terrain.is_walkable(slot):
			return false
	plan.platform_footprint.clear()
	for cell in cells:
		plan.platform_footprint.append(cell)
	plan.ingress_cell = footprint["ingress_cell"]
	plan.ingress_buffer_cells.clear()
	for cell in footprint.get("ingress_path_buffer", []):
		plan.ingress_buffer_cells.append(cell)
	plan.queue_hold_path_s = float(maxi(0, int(footprint.get("ingress_path_index", -1)) - INGRESS_BUFFER_LENGTH - 1))
	plan.queue_hold_cross_section.clear()
	if not plan.approach_queue_slots.is_empty():
		plan.queue_hold_cross_section.append(plan.approach_queue_slots[0])
	else:
		plan.queue_hold_cross_section.append(plan.ingress_cell)
	return true

## Creates a full 60+40 CombatDeploymentPlan
static func plan_deployment(
	formation_id: int,
	order_serial: int,
	terrain: Object,
	anchor: Vector2i,
	macro_path: Array[Vector2i],
	member_ids: Array[int],
	registry: Object = null,
	preferred_officers: Array[int] = [],
	current_cells: Dictionary = {},
	existing_facing: Vector2i = Vector2i.ZERO,
	profile: Object = null,
	preset_id: String = "auto"
) -> CombatDeploymentPlan:
	if not is_valid_preset(preset_id) or member_ids.is_empty() or member_ids.size() > 200:
		return null
	var radius := preset_footprint_radius(preset_id, member_ids.size())
	if radius < 0:
		return null
	var plan = CombatDeploymentPlan.new()
	plan.formation_id = formation_id
	plan.order_serial = order_serial
	plan.formation_preset_id = preset_id
	plan.shape_version = 2
	plan.requested_count = member_ids.size()
	plan.resolved_anchor = anchor
	plan.final_facing = existing_facing
	if plan.final_facing == Vector2i.ZERO:
		plan.final_facing = Vector2i.RIGHT
		for k in range(macro_path.size() - 1, 0, -1):
			var step: Vector2i = macro_path[k] - macro_path[k - 1]
			if step != Vector2i.ZERO:
				plan.final_facing = step
				break
	if plan.final_facing not in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		return null

	var fp_info := build_platform_footprint(terrain, anchor, macro_path, radius, profile)
	var raw_platform_cells: Array = fp_info["platform_cells"]
	for c in raw_platform_cells:
		plan.platform_footprint.append(c)
	var footprint_set: Dictionary = {}
	for c in raw_platform_cells:
		footprint_set[c] = true
	var ingress_cell: Vector2i = fp_info["ingress_cell"]
	var ingress_buffer: Array = fp_info["ingress_path_buffer"]
	var ingress_idx: int = int(fp_info.get("ingress_path_index", -1))

	plan.ingress_cell = ingress_cell
	plan.queue_hold_path_s = float(maxi(0, ingress_idx - INGRESS_BUFFER_LENGTH - 1))
	for b in ingress_buffer:
		plan.ingress_buffer_cells.append(b)

	# 1. Fixed presets must fit every requested cell. Auto keeps its original
	# platform/approach split and compact-area selection.
	var available_platform: Array[Vector2i] = []
	if preset_id == "auto":
		for c in raw_platform_cells:
			var cell: Vector2i = c
			# Keep the entry open while any other final slot is available.
			if cell == ingress_cell and raw_platform_cells.size() > 1:
				continue
			if registry != null and registry.has_method("is_slot_reserved"):
				if registry.is_slot_reserved(cell, formation_id):
					continue
			available_platform.append(cell)
		if available_platform.is_empty() and raw_platform_cells.has(ingress_cell):
			if registry == null or not registry.has_method("is_slot_reserved") or not registry.is_slot_reserved(ingress_cell, formation_id):
				available_platform.append(ingress_cell)
	else:
		available_platform = shape_slots(preset_id, member_ids.size(), anchor, plan.final_facing)
		if available_platform.size() != member_ids.size():
			return null
		for cell in available_platform:
			if not footprint_set.has(cell) or (registry != null and registry.has_method("is_slot_reserved") and registry.is_slot_reserved(cell, formation_id)):
				return null

	plan.structural_platform_capacity = raw_platform_cells.size()
	plan.available_platform_capacity = available_platform.size()

	# Keep a full-sized formation near its command anchor. On broad flat ground,
	# depth-first selection across the entire footprint makes a very thin wall
	# that can interleave with another formation's destination. Expand a square
	# only as far as the legal capacity requires; a narrow plateau still uses its
	# entire available footprint.
	var side := Vector2i(-plan.final_facing.y, plan.final_facing.x)
	var final_count := mini(member_ids.size(), available_platform.size())
	if preset_id == "auto" and final_count > 0:
		var selected_radius := 0
		var candidate_count := 0
		while candidate_count < final_count:
			candidate_count = 0
			for cell in available_platform:
				var offset: Vector2i = cell - anchor
				var axial: int = absi(offset.x * plan.final_facing.x + offset.y * plan.final_facing.y)
				var lateral: int = absi(offset.x * side.x + offset.y * side.y)
				if maxi(axial, lateral) <= selected_radius:
					candidate_count += 1
			if candidate_count < final_count:
				selected_radius += 1
		var compact_platform: Array[Vector2i] = []
		for cell in available_platform:
			var offset: Vector2i = cell - anchor
			var axial: int = absi(offset.x * plan.final_facing.x + offset.y * plan.final_facing.y)
			var lateral: int = absi(offset.x * side.x + offset.y * side.y)
			if maxi(axial, lateral) <= selected_radius:
				compact_platform.append(cell)
		available_platform = compact_platform
	# Fill the selected area from its deep edge, with a stable tie break.
	available_platform.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var da: int = (a.x - ingress_cell.x) * plan.final_facing.x + (a.y - ingress_cell.y) * plan.final_facing.y
		var db: int = (b.x - ingress_cell.x) * plan.final_facing.x + (b.y - ingress_cell.y) * plan.final_facing.y
		if da != db:
			return da > db
		var la: int = absi((a.x - anchor.x) * side.x + (a.y - anchor.y) * side.y)
		var lb: int = absi((b.x - anchor.x) * side.x + (b.y - anchor.y) * side.y)
		if la != lb:
			return la < lb
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	for i in range(final_count):
		plan.platform_slots.append(available_platform[i])
		plan.slot_tactical_roles[available_platform[i]] = Types.TacticalSlotRole.FLEX
	var lateral_columns: Dictionary = {}
	for cell in plan.platform_slots:
		lateral_columns[(cell.x - anchor.x) * side.x + (cell.y - anchor.y) * side.y] = true
	if preset_id == "auto":
		plan.final_width = mini(10, maxi(1, lateral_columns.size()))
		plan.final_depth = ceili(float(final_count) / float(plan.final_width))
	else:
		var min_side := 2147483647
		var max_side := -2147483647
		var min_forward := 2147483647
		var max_forward := -2147483647
		for cell in plan.platform_slots:
			var offset: Vector2i = cell - anchor
			var lateral: int = offset.x * side.x + offset.y * side.y
			var axial: int = offset.x * plan.final_facing.x + offset.y * plan.final_facing.y
			min_side = mini(min_side, lateral)
			max_side = maxi(max_side, lateral)
			min_forward = mini(min_forward, axial)
			max_forward = maxi(max_forward, axial)
		plan.final_width = max_side - min_side + 1
		plan.final_depth = max_forward - min_forward + 1
	var last_narrow_cell := Vector2i(-1, -1)
	for k in range(macro_path.size() - 1, -1, -1):
		var forward: Vector2i = Vector2i.RIGHT
		if k + 1 < macro_path.size():
			forward = macro_path[k + 1] - macro_path[k]
		elif k > 0:
			forward = macro_path[k] - macro_path[k - 1]
		if TransitPlanner.detect_corridor_width(terrain, macro_path[k], forward, profile) <= 1:
			last_narrow_cell = macro_path[k]
			break
	plan.set_approach_bottlenecked(last_narrow_cell != Vector2i(-1, -1), last_narrow_cell)

	# 2. Build approach queue slots along macro_path leading up to ingress buffer
	var buffer_set: Dictionary = {}
	for b in ingress_buffer:
		buffer_set[b] = true
	buffer_set[ingress_cell] = true

	var centerline_slots: Array[Vector2i] = []
	var queue_start_idx := (ingress_idx - INGRESS_BUFFER_LENGTH - 1) if ingress_idx > INGRESS_BUFFER_LENGTH else -1

	if queue_start_idx >= 0:
		for i in range(queue_start_idx, -1, -1):
			var qc: Vector2i = macro_path[i]
			if not buffer_set.has(qc):
				if registry == null or not registry.is_slot_reserved(qc, formation_id):
					centerline_slots.append(qc)
					if centerline_slots.size() >= 100:
						break

	# Queue members wait beside the transit centerline whenever reachable space
	# permits it, so a settled queue cannot seal the ramp for platform members.
	var queue_needed: int = maxi(0, member_ids.size() - final_count)
	var queue_slots: Array[Vector2i] = centerline_slots.duplicate()
	if queue_needed > 0:
		var approach_dir := Vector2i.RIGHT
		if not ingress_buffer.is_empty():
			approach_dir = ingress_cell - ingress_buffer[-1]
		elif ingress_idx > 0:
			approach_dir = ingress_cell - macro_path[ingress_idx - 1]
		if approach_dir == Vector2i.ZERO:
			approach_dir = Vector2i.RIGHT
		var hold_cell: Vector2i = macro_path[queue_start_idx] if queue_start_idx >= 0 else ingress_cell - approach_dir * (INGRESS_BUFFER_LENGTH + 1)
		if queue_slots.is_empty() and terrain.contains(hold_cell) and terrain.is_walkable(hold_cell) and not footprint_set.has(hold_cell) and not buffer_set.has(hold_cell) and (registry == null or not registry.has_method("is_slot_reserved") or not registry.is_slot_reserved(hold_cell, formation_id)):
			centerline_slots.append(hold_cell)
		var seen_queue: Dictionary = {}
		var frontier: Array[Vector2i] = []
		for cell in centerline_slots:
			seen_queue[cell] = true
			frontier.append(cell)
		var path_set: Dictionary = {}
		for cell in macro_path:
			path_set[cell] = true
		var side_slots: Array[Vector2i] = []
		var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
		var visited := 0
		while not frontier.is_empty() and side_slots.size() < queue_needed and visited < 4096:
			var source: Vector2i = frontier.pop_front()
			visited += 1
			for direction in directions:
				var next_cell := source + direction
				if seen_queue.has(next_cell):
					continue
				seen_queue[next_cell] = true
				var offset: Vector2i = next_cell - hold_cell
				if offset.x * approach_dir.x + offset.y * approach_dir.y > 0 or not terrain.contains(next_cell) or not terrain.is_walkable(next_cell):
					continue
				if buffer_set.has(next_cell) or footprint_set.has(next_cell) or not TransitPlanner._can_profile_step(terrain, source, next_cell, profile):
					continue
				if registry != null and registry.has_method("is_slot_reserved") and registry.is_slot_reserved(next_cell, formation_id):
					continue
				frontier.append(next_cell)
				if not path_set.has(next_cell):
					side_slots.append(next_cell)
					if side_slots.size() >= queue_needed:
						break
		side_slots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da: int = absi(a.x - hold_cell.x) + absi(a.y - hold_cell.y)
			var db: int = absi(b.x - hold_cell.x) + absi(b.y - hold_cell.y)
			if da != db:
				return da < db
			return a.x < b.x if a.x != b.x else a.y < b.y
		)
		queue_slots = side_slots
		for cell in centerline_slots:
			if queue_slots.size() >= queue_needed:
				break
			if not queue_slots.has(cell):
				queue_slots.append(cell)

	for q in queue_slots:
		plan.approach_queue_slots.append(q)
	plan.queue_capacity = queue_slots.size()

	# Set queue hold cross section (the first queue slot before ingress buffer)
	plan.queue_hold_cross_section.clear()
	if not centerline_slots.is_empty():
		plan.queue_hold_cross_section.append(centerline_slots[0])
	elif not ingress_buffer.is_empty():
		plan.queue_hold_cross_section.append(ingress_buffer[0])
	else:
		plan.queue_hold_cross_section.append(ingress_cell)

	# 3. Capacity verification
	if final_count + plan.queue_capacity < member_ids.size():
		return null # Insufficient space!

	# 4. Physical arrival order fills deep cells first. Officers retain dedicated
	# rear cells, so a commander starting behind the vanguard never has to pass it.
	var ordered_members: Array[int] = []
	for mid in member_ids:
		ordered_members.append(mid)
	if not current_cells.is_empty():
		ordered_members.sort_custom(func(a: int, b: int) -> bool:
			var ca: Vector2i = current_cells.get(a, macro_path[0] if not macro_path.is_empty() else anchor)
			var cb: Vector2i = current_cells.get(b, macro_path[0] if not macro_path.is_empty() else anchor)
			var da: int = absi(ca.x - ingress_cell.x) + absi(ca.y - ingress_cell.y)
			var db: int = absi(cb.x - ingress_cell.x) + absi(cb.y - ingress_cell.y)
			return da < db if da != db else a < b
		)
	var officer_members: Array[int] = []
	for off in preferred_officers:
		if ordered_members.has(off) and not officer_members.has(off):
			officer_members.append(off)
	# Reserve accessible rear positions for officers before member ownership is fixed.
	# The commander receives the rear slot closest to the ingress centerline.
	var officer_slots: Array[Vector2i] = []
	for off in officer_members:
		if officer_slots.size() >= plan.platform_slots.size():
			break
		var selected := Vector2i(-1, -1)
		var selected_depth := 999999
		var selected_lateral := 999999
		for slot in plan.platform_slots:
			if officer_slots.has(slot):
				continue
			var depth: int = (slot.x - ingress_cell.x) * plan.final_facing.x + (slot.y - ingress_cell.y) * plan.final_facing.y
			var lateral: int = absi((slot.x - ingress_cell.x) * side.x + (slot.y - ingress_cell.y) * side.y)
			if depth < selected_depth or (depth == selected_depth and lateral < selected_lateral):
				selected = slot
				selected_depth = depth
				selected_lateral = lateral
		if selected != Vector2i(-1, -1):
			officer_slots.append(selected)
	for slot in officer_slots:
		plan.platform_slots.erase(slot)
		plan.platform_slots.append(slot)
	var platform_limit := mini(plan.platform_slots.size(), ordered_members.size())
	var regular_limit := maxi(0, platform_limit - officer_members.size())
	var platform_members: Array[int] = []
	for mid in ordered_members:
		if not officer_members.has(mid) and platform_members.size() < regular_limit:
			platform_members.append(mid)
	for off in officer_members:
		if platform_members.size() < platform_limit:
			platform_members.append(off)
	for i in range(platform_members.size()):
		var mid: int = platform_members[i]
		plan.member_role_map[mid] = Types.CombatDestinationRole.PLATFORM
		plan.member_slot_map[mid] = plan.platform_slots[i]
		plan.slot_owner_map[plan.platform_slots[i]] = mid
		plan.pending_platform_member_ids.append(mid)
		if officer_members.has(mid):
			plan.slot_tactical_roles[plan.platform_slots[i]] = Types.TacticalSlotRole.COMMANDER if mid == officer_members[0] else Types.TacticalSlotRole.OFFICER
	var queue_members: Array[int] = []
	for mid in ordered_members:
		if not platform_members.has(mid):
			queue_members.append(mid)
	for q_idx in range(queue_members.size()):
		var mid: int = queue_members[q_idx]
		plan.member_role_map[mid] = Types.CombatDestinationRole.APPROACH_QUEUE
		if q_idx < plan.approach_queue_slots.size():
			plan.member_slot_map[mid] = plan.approach_queue_slots[q_idx]
		else:
			return null
		plan.slot_owner_map[plan.member_slot_map[mid]] = mid
		plan.queue_member_ids.append(mid)

	return plan

## Updates ingress admission gate progress
static func update_ingress_gate(plan: CombatDeploymentPlan, current_cells: Dictionary) -> void:
	if plan == null:
		return
	var platform_set: Dictionary = {}
	for c in plan.platform_footprint:
		platform_set[c] = true
	if platform_set.is_empty():
		for c in plan.platform_slots:
			platform_set[c] = true

	var still_pending: Array[int] = []
	var admitted: Array[int] = []
	for mid in plan.member_role_map.keys():
		if not plan.is_platform_member(mid):
			continue
		var cell: Vector2i = current_cells.get(mid, Vector2i(-1, -1))
		if platform_set.has(cell):
			plan.ever_admitted_platform_member_ids[mid] = true
			admitted.append(mid)
		else:
			still_pending.append(mid)
	plan.admitted_platform_member_ids = admitted
	plan.pending_platform_member_ids = still_pending
	plan.queue_released = plan.pending_platform_member_ids.is_empty()

static func _is_prior_platform_entrant_beyond_handoff(plan: CombatDeploymentPlan, mid: int, current_cells: Dictionary) -> bool:
	# Admission history remains true when an entrant detours outside and behind
	# the routing handoff; its current side of that waypoint is not a new entry.
	return plan.ever_admitted_platform_member_ids.has(mid) and current_cells.has(mid)

static func _never_crossed_platform_count(plan: CombatDeploymentPlan, current_cells: Dictionary) -> int:
	var count := 0
	for mid in plan.pending_platform_member_ids:
		if not _is_prior_platform_entrant_beyond_handoff(plan, mid, current_cells):
			count += 1
	return count

static func update_movement_phase(move_plan: CombatMovePlan, plan: CombatDeploymentPlan, current_cells: Dictionary, terrain: Object = null, delta_sec: float = 0.0, registry: Object = null, blocked_destinations: Dictionary = {}) -> void:
	if move_plan == null or plan == null or move_plan.phase == Types.CombatMovePhase.FAILED:
		return
	move_plan.planning_time_sec += maxf(0.0, delta_sec)
	if not move_plan.active_vacancy_chain_actors.is_empty():
		var chain_complete := true
		var chain_blocked := false
		var arrived_count := 0
		var occupant_at: Dictionary = {}
		for occupant_id in current_cells.keys():
			occupant_at[current_cells[occupant_id]] = occupant_id
		for chain_mid in move_plan.active_vacancy_chain_actors:
			if current_cells.has(chain_mid) and current_cells[chain_mid] == plan.get_slot_for_member(chain_mid):
				arrived_count += 1
				# A new chain target is earned only by a real occupant reaching it.
				# Credit each actor once until an independent settled highwater gain;
				# repeated ownership rotations cannot keep a stalled team alive.
				if move_plan.member_vacancy_chain_start_cell.has(chain_mid) and current_cells[chain_mid] != move_plan.member_vacancy_chain_start_cell[chain_mid] and not move_plan.verified_chain_arrival_members.has(chain_mid):
					move_plan.verified_chain_arrival_members[chain_mid] = true
					move_plan.verified_chain_arrival_pending = true
					move_plan.last_platform_progress_time_sec = move_plan.planning_time_sec
			else:
				chain_complete = false
				var blocker: int = int(occupant_at.get(plan.get_slot_for_member(chain_mid), -1))
				if blocker >= 0 and not move_plan.active_vacancy_chain_actors.has(blocker) and not move_plan.member_pending_proposal_id.has(blocker):
					chain_blocked = true
		if arrived_count > move_plan.vacancy_chain_arrived_count:
			move_plan.vacancy_chain_arrived_count = arrived_count
			move_plan.vacancy_chain_last_progress_sec = move_plan.planning_time_sec
		var chain_stale: bool = move_plan.planning_time_sec - move_plan.vacancy_chain_last_progress_sec >= 2.0
		if chain_complete or (chain_blocked and move_plan.planning_time_sec - move_plan.vacancy_chain_started_sec >= 1.0) or chain_stale:
			if (chain_blocked or chain_stale) and not chain_complete:
				for chain_mid in move_plan.active_vacancy_chain_actors:
					move_plan.note_assignment_change(chain_mid)
			move_plan.active_vacancy_chain_actors.clear()
			move_plan.member_vacancy_chain_target.clear()
			move_plan.member_vacancy_chain_start_cell.clear()
			move_plan.vacancy_chain_arrived_count = 0
			if chain_complete and not move_plan.queued_vacancy_steps.is_empty():
				_advance_queued_vacancy_step(move_plan, plan, current_cells, terrain, blocked_destinations)
			elif move_plan.vacancy_waiting_id >= 0:
				_clear_queued_vacancy_steps(move_plan)
	# A recovery hold only bridges one in-flight physical step into its own
	# vacancy rotation. Never park a stationary soldier behind another chain or
	# while the global recovery clock is not eligible.
	if not move_plan.active_vacancy_chain_actors.is_empty() or move_plan.planning_time_sec < move_plan.next_platform_recovery_time_sec or move_plan.planning_time_sec - move_plan.last_platform_progress_time_sec < PLATFORM_RECOVERY_STALL_SEC or _never_crossed_platform_count(plan, current_cells) > 1:
		for held_mid in move_plan.member_recovery_hold.keys():
			if held_mid == move_plan.vacancy_waiting_id:
				continue
			if not move_plan.member_pending_proposal_id.has(held_mid):
				move_plan.member_recovery_hold.erase(held_mid)
	var admitted_before: Array[int] = plan.admitted_platform_member_ids.duplicate()
	update_ingress_gate(plan, current_cells)
	move_plan.member_queue_egress_waypoint.clear()
	if exchange_front_queue_role(move_plan, plan, current_cells):
		update_ingress_gate(plan, current_cells)
	elif terrain != null:
		assign_queue_egress_waypoints(move_plan, plan, current_cells, terrain, registry)
	var new_admission := false
	for mid in plan.admitted_platform_member_ids:
		if not admitted_before.has(mid):
			new_admission = true
	if terrain != null:
		late_bind_ingress_target(move_plan, plan, current_cells, terrain, registry)
	resolve_crossed_provisional_targets(move_plan, plan, current_cells)
	if plan.queue_released:
		bind_queue_member_on_provisional_slot(move_plan, plan, current_cells)
	var occupied_now: Dictionary = {}
	for cell in current_cells.values():
		occupied_now[cell] = true
	var entry_lane_now: Dictionary = {}
	for cell in move_plan.macro_path:
		if plan.platform_footprint.has(cell):
			entry_lane_now[cell] = true
	for mid in plan.member_slot_map.keys():
		if plan.is_platform_member(mid) and current_cells.get(mid, Vector2i(-1, -1)) == plan.get_slot_for_member(mid):
			var final_cell: Vector2i = plan.get_slot_for_member(mid)
			if not plan.pending_platform_member_ids.is_empty() and entry_lane_now.has(final_cell) and _has_vacant_side_slot(plan, final_cell, entry_lane_now, occupied_now):
				plan.member_slot_locked.erase(mid)
				plan.settled_platform_member_ids.erase(mid)
			else:
				plan.mark_platform_member_settled(mid)
		elif plan.settled_platform_member_ids.has(mid):
			plan.settled_platform_member_ids.erase(mid)
		if plan.is_queue_member(mid):
			if current_cells.get(mid, Vector2i(-1, -1)) == plan.get_slot_for_member(mid):
				if not plan.settled_queue_member_ids.has(mid):
					plan.settled_queue_member_ids.append(mid)
				plan.lock_member_slot(mid)
			else:
				plan.settled_queue_member_ids.erase(mid)
	if new_admission or plan.settled_platform_member_ids.size() > move_plan.platform_settled_highwater:
		move_plan.member_recovery_vacated_cell.clear()
	if plan.admitted_platform_member_ids.size() > admitted_before.size() or plan.settled_platform_member_ids.size() > move_plan.platform_settled_highwater:
		move_plan.last_platform_progress_time_sec = move_plan.planning_time_sec
	move_plan.platform_settled_highwater = maxi(move_plan.platform_settled_highwater, plan.settled_platform_member_ids.size())
	if plan.settled_queue_member_ids.size() > move_plan.queue_settled_highwater:
		move_plan.queue_settled_highwater = plan.settled_queue_member_ids.size()
		move_plan.last_queue_progress_time_sec = move_plan.planning_time_sec
	if terrain != null and move_plan.active_vacancy_chain_actors.is_empty():
		if not recover_stalled_platform_slots(move_plan, plan, current_cells, terrain, blocked_destinations):
			rebalance_provisional_slots(move_plan, plan, current_cells, terrain, new_admission)
		if plan.queue_released:
			recover_stalled_queue_slots(move_plan, plan, current_cells, terrain)
	if is_settled(plan, current_cells):
		move_plan.phase = Types.CombatMovePhase.COMPLETE
	elif plan.queue_released:
		move_plan.phase = Types.CombatMovePhase.QUEUE_SETTLING
	elif not plan.admitted_platform_member_ids.is_empty():
		move_plan.phase = Types.CombatMovePhase.PLATFORM_INGRESS
	else:
		var near_ingress := false
		for mid in current_cells.keys():
			if float(move_plan.member_observed_path_s.get(mid, -INF)) >= plan.queue_hold_path_s - 10.0:
				near_ingress = true
				break
		move_plan.phase = Types.CombatMovePhase.INGRESS_STAGING if near_ingress else Types.CombatMovePhase.TRANSIT

static func exchange_front_queue_role(move_plan: CombatMovePlan, plan: CombatDeploymentPlan, current_cells: Dictionary) -> bool:
	if move_plan == null or plan == null or plan.pending_platform_member_ids.is_empty() or plan.ingress_buffer_cells.is_empty():
		return false
	if move_plan.vacancy_waiting_id >= 0:
		return false
	var approach_dir: Vector2i = plan.ingress_cell - plan.ingress_buffer_cells[-1]
	if approach_dir == Vector2i.ZERO:
		return false
	var choke_cells: Dictionary = {plan.ingress_cell: true}
	for i in range(maxi(0, plan.ingress_buffer_cells.size() - 2), plan.ingress_buffer_cells.size()):
		choke_cells[plan.ingress_buffer_cells[i]] = true
	var ingress_index: int = move_plan.macro_path.find(plan.ingress_cell)
	if ingress_index < 0:
		ingress_index = move_plan.macro_path.size() - 1
	for i in range(maxi(0, ingress_index - 10), ingress_index + 1):
		choke_cells[move_plan.macro_path[i]] = true
	for queue_id in plan.queue_member_ids:
		if plan.is_slot_locked(queue_id) or not current_cells.has(queue_id) or move_plan.member_pending_proposal_id.has(queue_id):
			continue
		var queue_cell: Vector2i = current_cells[queue_id]
		if not choke_cells.has(queue_cell):
			continue
		var best_member := -1
		var best_rear_projection := 0
		for platform_id in plan.pending_platform_member_ids:
			if not current_cells.has(platform_id) or plan.is_slot_locked(platform_id) or move_plan.member_pending_proposal_id.has(platform_id):
				continue
			var platform_cell: Vector2i = current_cells[platform_id]
			var rear_projection: int = (platform_cell.x - queue_cell.x) * approach_dir.x + (platform_cell.y - queue_cell.y) * approach_dir.y
			if rear_projection >= 0:
				continue
			if best_member < 0 or rear_projection < best_rear_projection or (rear_projection == best_rear_projection and platform_id < best_member):
				best_member = platform_id
				best_rear_projection = rear_projection
		if best_member >= 0 and plan.exchange_queue_platform_roles(queue_id, best_member):
			move_plan.note_assignment_change(queue_id)
			move_plan.note_assignment_change(best_member)
			move_plan.member_entry_hold.erase(queue_id)
			return true
	return false

## Two members occupying one another's compatible final slots exchange ownership,
## never physical cells. This is deliberately narrower than arbitrary occupied-slot binding.
static func resolve_crossed_provisional_targets(move_plan: CombatMovePlan, plan: CombatDeploymentPlan, current_cells: Dictionary) -> bool:
	move_plan.member_crossed_swap_hold.clear()
	for a in plan.admitted_platform_member_ids:
		if not current_cells.has(a):
			continue
		var a_cell: Vector2i = current_cells[a]
		var b: int = int(plan.slot_owner_map.get(a_cell, -1))
		if b == a or not plan.admitted_platform_member_ids.has(b) or not current_cells.has(b):
			continue
		if move_plan.member_recovery_hold.has(a) or move_plan.member_recovery_hold.has(b):
			continue
		if current_cells[b] != plan.get_slot_for_member(a) or plan.get_role_for_member(a) != plan.get_role_for_member(b):
			continue
		if move_plan.member_pending_proposal_id.has(a) or move_plan.member_pending_proposal_id.has(b):
			move_plan.member_crossed_swap_hold[a] = true
			move_plan.member_crossed_swap_hold[b] = true
			continue
		# A live vacancy handoff protects its target owner until the physical
		# chain finishes. Legacy crossed-slot repair remains available otherwise.
		if move_plan.vacancy_waiting_id >= 0 and (move_plan.member_vacancy_chain_target.has(a) or move_plan.member_vacancy_chain_target.has(b)):
			continue
		# Only an exact A/B crossing may release a stale final-slot lock.
		# Unrelated settled owners keep their committed slot ownership.
		var locked_a: bool = plan.is_slot_locked(a)
		var locked_b: bool = plan.is_slot_locked(b)
		if locked_a:
			plan.member_slot_locked.erase(a)
		if locked_b:
			plan.member_slot_locked.erase(b)
		if not plan.swap_member_slots(a, b):
			if locked_a:
				plan.lock_member_slot(a)
			if locked_b:
				plan.lock_member_slot(b)
			continue
		move_plan.note_assignment_change(a)
		move_plan.note_assignment_change(b)
		if move_plan.member_vacancy_chain_target.has(a):
			move_plan.member_vacancy_chain_target[a] = plan.get_slot_for_member(a)
		if move_plan.member_vacancy_chain_target.has(b):
			move_plan.member_vacancy_chain_target[b] = plan.get_slot_for_member(b)
		move_plan.member_entry_hold.erase(a)
		move_plan.member_entry_hold.erase(b)
		move_plan.member_entry_waypoint.erase(a)
		move_plan.member_entry_waypoint.erase(b)
		move_plan.member_swap_cooldown_until_sec[a] = move_plan.planning_time_sec + PLATFORM_RECOVERY_COOLDOWN_SEC
		move_plan.member_swap_cooldown_until_sec[b] = move_plan.planning_time_sec + PLATFORM_RECOVERY_COOLDOWN_SEC
		return true
	return false

## Once every platform member has entered, a queue soldier standing on another
## unlocked queue final takes that target instead of asking both soldiers to pass.
static func bind_queue_member_on_provisional_slot(move_plan: CombatMovePlan, plan: CombatDeploymentPlan, current_cells: Dictionary) -> bool:
	for a in plan.queue_member_ids:
		if plan.is_slot_locked(a) or not current_cells.has(a) or move_plan.member_pending_proposal_id.has(a):
			continue
		var occupied_slot: Vector2i = current_cells[a]
		if not plan.approach_queue_slots.has(occupied_slot):
			continue
		var b: int = int(plan.slot_owner_map.get(occupied_slot, -1))
		if b == a or not plan.is_queue_member(b) or plan.is_slot_locked(b) or move_plan.member_pending_proposal_id.has(b):
			continue
		if not plan.swap_member_slots(a, b):
			continue
		move_plan.note_assignment_change(a)
		move_plan.note_assignment_change(b)
		return true
	return false

static func assign_queue_egress_waypoints(move_plan: CombatMovePlan, plan: CombatDeploymentPlan, current_cells: Dictionary, terrain: Object, registry: Object = null) -> void:
	if move_plan == null or plan == null or terrain == null or plan.pending_platform_member_ids.is_empty() or plan.ingress_buffer_cells.is_empty():
		return
	var approach_dir: Vector2i = plan.ingress_cell - plan.ingress_buffer_cells[-1]
	var side := Vector2i(-signi(approach_dir.y), signi(approach_dir.x))
	if side == Vector2i.ZERO:
		return
	var choke_cells: Dictionary = {plan.ingress_cell: true}
	for i in range(maxi(0, plan.ingress_buffer_cells.size() - 2), plan.ingress_buffer_cells.size()):
		choke_cells[plan.ingress_buffer_cells[i]] = true
	var approach_lane: Dictionary = choke_cells.duplicate()
	var ingress_index: int = move_plan.macro_path.find(plan.ingress_cell)
	if ingress_index < 0:
		ingress_index = move_plan.macro_path.size() - 1
	for i in range(maxi(0, ingress_index - 10), ingress_index + 1):
		var center_cell: Vector2i = move_plan.macro_path[i]
		approach_lane[center_cell] = true
		choke_cells[center_cell] = true
		choke_cells[center_cell + side] = true
		choke_cells[center_cell - side] = true
	var occupied: Dictionary = {}
	for cell in current_cells.values():
		occupied[cell] = true
	for queue_id in plan.queue_member_ids:
		if plan.is_slot_locked(queue_id) or not current_cells.has(queue_id) or move_plan.member_pending_proposal_id.has(queue_id):
			continue
		var current_cell: Vector2i = current_cells[queue_id]
		if not choke_cells.has(current_cell):
			continue
		var side_steps: Array[Vector2i] = [current_cell + side, current_cell - side]
		var final_slot: Vector2i = plan.get_slot_for_member(queue_id)
		side_steps.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			if approach_lane.has(a) != approach_lane.has(b):
				return not approach_lane.has(a)
			var da: int = absi(a.x - final_slot.x) + absi(a.y - final_slot.y)
			var db: int = absi(b.x - final_slot.x) + absi(b.y - final_slot.y)
			return da < db if da != db else a.x < b.x if a.x != b.x else a.y < b.y
		)
		for waypoint in side_steps:
			if not occupied.has(waypoint) and terrain.contains(waypoint) and terrain.is_walkable(waypoint) and terrain.can_step(current_cell, waypoint) and not plan.platform_footprint.has(waypoint) and (registry == null or not registry.has_method("is_slot_reserved") or not registry.is_slot_reserved(waypoint, plan.formation_id)):
				move_plan.member_queue_egress_waypoint[queue_id] = waypoint
				break

static func late_bind_ingress_target(move_plan: CombatMovePlan, plan: CombatDeploymentPlan, current_cells: Dictionary, terrain: Object, registry: Object = null) -> bool:
	if move_plan == null or plan == null or terrain == null or plan.ingress_buffer_cells.is_empty():
		return false
	move_plan.member_entry_hold.clear()
	move_plan.member_entry_waypoint.clear()
	# Every eligible non-broad entrant is on the ingress buffer or inside the
	# footprint; every eligible broad entrant is at most six cells from a final.
	# Avoid scanning every final for every soldier on a long, distant detour.
	var nearby_cells: Array[Vector2i] = plan.platform_footprint.duplicate()
	nearby_cells.append_array(plan.platform_slots)
	nearby_cells.append_array(plan.ingress_buffer_cells)
	nearby_cells.append(plan.ingress_cell)
	var min_x := 2147483647
	var min_y := 2147483647
	var max_x := -2147483647
	var max_y := -2147483647
	for nearby_cell in nearby_cells:
		min_x = mini(min_x, nearby_cell.x)
		min_y = mini(min_y, nearby_cell.y)
		max_x = maxi(max_x, nearby_cell.x)
		max_y = maxi(max_y, nearby_cell.y)
	var anyone_near := false
	for member_id in plan.member_slot_map.keys():
		if not plan.is_platform_member(member_id) or not current_cells.has(member_id):
			continue
		var member_cell: Vector2i = current_cells[member_id]
		if member_cell.x >= min_x - 6 and member_cell.x <= max_x + 6 and member_cell.y >= min_y - 6 and member_cell.y <= max_y + 6:
			anyone_near = true
			break
	if not anyone_near:
		return false
	var ramp_cell: Vector2i = plan.ingress_buffer_cells[-1]
	var approach_cell: Vector2i = plan.ingress_buffer_cells[-2] if plan.ingress_buffer_cells.size() >= 2 else ramp_cell
	var occupied: Dictionary = {}
	for mid in current_cells.keys():
		var cell: Vector2i = current_cells[mid]
		occupied[cell] = true
	var free_platform: Dictionary = {}
	for cell in plan.platform_footprint:
		if not occupied.has(cell):
			free_platform[cell] = true
	var entry_lane: Dictionary = {}
	for cell in move_plan.macro_path:
		if plan.platform_footprint.has(cell):
			entry_lane[cell] = true
	var final_min_x := 2147483647
	var final_max_x := -2147483647
	var final_min_y := 2147483647
	var final_max_y := -2147483647
	for slot in plan.platform_slots:
		final_min_x = mini(final_min_x, slot.x)
		final_max_x = maxi(final_max_x, slot.x)
		final_min_y = mini(final_min_y, slot.y)
		final_max_y = maxi(final_max_y, slot.y)
	var changed := false
	for a in plan.member_slot_map.keys():
		if not plan.is_platform_member(a) or not current_cells.has(a) or move_plan.member_pending_proposal_id.has(a) or move_plan.member_vacancy_chain_target.has(a) or move_plan.member_recovery_hold.has(a):
			continue
		var ca: Vector2i = current_cells[a]
		var own_slot: Vector2i = plan.get_slot_for_member(a)
		# A friendly already standing on another unlocked final takes its
		# ownership, including on the entrance lane. This changes targets only;
		# the reservation grid remains the sole owner of physical cell movement.
		if plan.slot_owner_map.has(ca):
			var occupying_owner: int = int(plan.slot_owner_map[ca])
			if occupying_owner != a and plan.admitted_platform_member_ids.has(occupying_owner) and not plan.is_slot_locked(a) and not plan.is_slot_locked(occupying_owner) and not move_plan.member_pending_proposal_id.has(occupying_owner) and not move_plan.member_recovery_hold.has(occupying_owner) and not move_plan.member_vacancy_chain_target.has(occupying_owner) and move_plan.planning_time_sec >= float(move_plan.member_swap_cooldown_until_sec.get(a, 0.0)) and move_plan.planning_time_sec >= float(move_plan.member_swap_cooldown_until_sec.get(occupying_owner, 0.0)) and plan.swap_member_slots(a, occupying_owner):
				move_plan.note_assignment_change(a)
				move_plan.note_assignment_change(occupying_owner)
				move_plan.member_swap_cooldown_until_sec[a] = move_plan.planning_time_sec + 0.5
				move_plan.member_swap_cooldown_until_sec[occupying_owner] = move_plan.planning_time_sec + 0.5
				changed = true
				continue
		var broad_destination: bool = absi(own_slot.x - plan.ingress_cell.x) + absi(own_slot.y - plan.ingress_cell.y) > 8
		var outer_approach_exhausted := false
		if broad_destination:
			if not plan.is_slot_locked(a) and plan.platform_footprint.has(ca) and (ca.x < final_min_x or ca.x > final_max_x or ca.y < final_min_y or ca.y > final_max_y) and int(move_plan.member_route_retry_count.get(a, 0)) >= 12:
				var approach_waypoint: Vector2i = _outer_approach_waypoint(move_plan, plan, ca, own_slot, occupied, entry_lane, terrain, registry)
				if approach_waypoint != ca:
					move_plan.member_entry_waypoint[a] = approach_waypoint
					continue
				outer_approach_exhausted = true
			# On a large flat footprint, bind by actual reachability near the final
			# slots, after the column has left the narrow approach.
			var nearest_final := 999999
			for slot in plan.platform_slots:
				nearest_final = mini(nearest_final, absi(ca.x - slot.x) + absi(ca.y - slot.y))
			if nearest_final > 6:
				continue
		elif ca != approach_cell and ca != ramp_cell and ca != plan.ingress_cell and not entry_lane.has(ca):
			continue
		# With no later platform entrant, there is no pending slot owner to
		# exchange with and no entrance to clear. Keep the direct occupied-slot
		# exchange and outer detour above, then use the normal final route.
		if plan.pending_platform_member_ids.is_empty():
			continue
		var physically_free_side := _has_vacant_side_slot(plan, own_slot, entry_lane, occupied)
		if plan.is_slot_locked(a):
			if plan.pending_platform_member_ids.is_empty() or ca != own_slot or not entry_lane.has(ca) or not physically_free_side:
				continue
			plan.member_slot_locked.erase(a)
			plan.settled_platform_member_ids.erase(a)
		var path_start: Vector2i = ca
		if ca == approach_cell and ca != ramp_cell:
			if not occupied.has(ramp_cell) and TransitPlanner._can_profile_step(terrain, ca, ramp_cell, null):
				path_start = ramp_cell
		if ca == ramp_cell and not occupied.has(plan.ingress_cell) and TransitPlanner._can_profile_step(terrain, ca, plan.ingress_cell, null):
			path_start = plan.ingress_cell
		var reachable_cells: Dictionary = free_platform.duplicate()
		reachable_cells[path_start] = true
		var own_depth: int = (own_slot.x - plan.ingress_cell.x) * plan.final_facing.x + (own_slot.y - plan.ingress_cell.y) * plan.final_facing.y
		var best_owner := -1
		var best_depth := -999999
		var best_distance := 999999
		var reachable_distances: Dictionary = {}
		var distances_ready := false
		for slot in plan.platform_slots:
			if occupied.has(slot) or (physically_free_side and entry_lane.has(slot)):
				continue
			var owner: int = int(plan.slot_owner_map.get(slot, -1))
			if owner < 0:
				continue
			if owner != a and (not plan.pending_platform_member_ids.has(owner) or plan.is_slot_locked(owner) or move_plan.member_pending_proposal_id.has(owner) or move_plan.member_recovery_hold.has(owner) or move_plan.member_vacancy_chain_target.has(owner) or move_plan.planning_time_sec < float(move_plan.member_swap_cooldown_until_sec.get(owner, 0.0))):
				continue
			var depth: int = (slot.x - plan.ingress_cell.x) * plan.final_facing.x + (slot.y - plan.ingress_cell.y) * plan.final_facing.y
			# An owner still outside the platform must not inherit a deeper final
			# merely because an earlier entrant can reach their shallower slot.
			if (plan.approach_bottlenecked != 0 and owner != a and plan.pending_platform_member_ids.has(owner) and depth < own_depth) or depth < best_depth:
				continue
			if not distances_ready:
				reachable_distances = _platform_distances(path_start, terrain, reachable_cells)
				distances_ready = true
			var distance: int = int(reachable_distances.get(slot, -1))
			if distance < 0 or (depth == best_depth and distance >= best_distance):
				continue
			best_owner = owner
			best_depth = depth
			best_distance = distance
		if best_owner >= 0 and best_owner != a and move_plan.planning_time_sec >= float(move_plan.member_swap_cooldown_until_sec.get(a, 0.0)) and plan.swap_member_slots(a, best_owner):
			move_plan.note_assignment_change(a)
			move_plan.note_assignment_change(best_owner)
			move_plan.member_swap_cooldown_until_sec[a] = move_plan.planning_time_sec + 0.5
			move_plan.member_swap_cooldown_until_sec[best_owner] = move_plan.planning_time_sec + 0.5
			changed = true
		if broad_destination and not plan.platform_footprint.has(ca):
			# A route around the settled edge may briefly leave the footprint.
			# Never strand that soldier there with a self-target hold.
			continue
		# Clear the entrance only while another platform member still needs it.
		# Once everyone has entered, a lateral waypoint can make the last
		# soldiers oscillate beside their own finals instead of settling.
		if not plan.pending_platform_member_ids.is_empty() and physically_free_side and (entry_lane.has(plan.get_slot_for_member(a)) or best_owner < 0):
			var waypoint := _entry_lane_waypoint(ca, plan, entry_lane, occupied, terrain, registry)
			if waypoint != ca and outer_approach_exhausted:
				var final_slot: Vector2i = plan.get_slot_for_member(a)
				var step: Vector2i = waypoint - ca
				var toward_final: Vector2i = final_slot - ca
				if step.x * toward_final.x + step.y * toward_final.y < 0:
					waypoint = ca
			if waypoint != ca:
				move_plan.member_entry_waypoint[a] = waypoint
			# A distant vacant side slot is not a reason to stop on the entrance
			# when no legal local waypoint exists. The normal target/recovery path
			# must remain live so the soldier can clear the lane.
	return changed

static func _outer_approach_waypoint(move_plan: CombatMovePlan, plan: CombatDeploymentPlan, current_cell: Vector2i, final_slot: Vector2i, occupied: Dictionary, entry_lane: Dictionary, terrain: Object, registry: Object = null) -> Vector2i:
	var walkable: Dictionary = {}
	var free: Dictionary = {}
	for x in range(mini(current_cell.x, final_slot.x) - 4, maxi(current_cell.x, final_slot.x) + 5):
		for y in range(mini(current_cell.y, final_slot.y) - 4, maxi(current_cell.y, final_slot.y) + 5):
			var cell := Vector2i(x, y)
			if not terrain.contains(cell) or not terrain.is_walkable(cell):
				continue
			walkable[cell] = true
			if not occupied.has(cell) or cell == current_cell:
				free[cell] = true
	var distance: int = _platform_distance(current_cell, final_slot, terrain, walkable, 512)
	if distance < 0 or (not occupied.has(final_slot) and _platform_distance(current_cell, final_slot, terrain, free, 512) >= 0):
		return current_cell
	var best: Vector2i = current_cell
	var best_distance: int = distance
	for direction in [Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP, Vector2i.RIGHT]:
		var candidate: Vector2i = current_cell + direction
		if not free.has(candidate) or not plan.platform_footprint.has(candidate) or plan.platform_slots.has(candidate) or plan.approach_queue_slots.has(candidate) or plan.slot_owner_map.has(candidate) or plan.slot_lease_timers.has(candidate) or entry_lane.has(candidate) or plan.ingress_buffer_cells.has(candidate) or move_plan.member_entry_waypoint.values().has(candidate) or (registry != null and registry.has_method("is_slot_reserved") and registry.is_slot_reserved(candidate, move_plan.formation_id)) or not TransitPlanner._can_profile_step(terrain, current_cell, candidate, null):
			continue
		var candidate_distance: int = _platform_distance(candidate, final_slot, terrain, walkable, 512)
		if candidate_distance >= 0 and candidate_distance < best_distance:
			best = candidate
			best_distance = candidate_distance
	return best

static func _has_vacant_side_slot(plan: CombatDeploymentPlan, own_slot: Vector2i, entry_lane: Dictionary, occupied: Dictionary) -> bool:
	for slot in plan.platform_slots:
		if not entry_lane.has(slot) and not occupied.has(slot):
			return true
	return false

static func _entry_lane_waypoint(current_cell: Vector2i, plan: CombatDeploymentPlan, entry_lane: Dictionary, occupied: Dictionary, terrain: Object, registry: Object = null) -> Vector2i:
	var approach_dir: Vector2i = plan.ingress_cell - plan.ingress_buffer_cells[-1]
	approach_dir = Vector2i(signi(approach_dir.x), signi(approach_dir.y))
	var side: Vector2i = Vector2i(-approach_dir.y, approach_dir.x)
	var directions: Array[Vector2i] = [approach_dir, side, -side]
	for direction in directions:
		var next_cell: Vector2i = current_cell + direction
		if occupied.has(next_cell) or (registry != null and registry.has_method("is_slot_reserved") and registry.is_slot_reserved(next_cell, plan.formation_id)) or not terrain.contains(next_cell) or not terrain.is_walkable(next_cell) or not TransitPlanner._can_profile_step(terrain, current_cell, next_cell, null):
			continue
		if entry_lane.has(next_cell) or plan.platform_footprint.has(next_cell) or plan.ingress_buffer_cells.has(next_cell):
			return next_cell
	return current_cell

static func recover_stalled_platform_slots(move_plan: CombatMovePlan, plan: CombatDeploymentPlan, current_cells: Dictionary, terrain: Object, blocked_destinations: Dictionary = {}) -> bool:
	if move_plan == null or plan == null or terrain == null or plan.settled_platform_member_ids.size() >= plan.platform_slots.size():
		return false
	if move_plan.planning_time_sec < move_plan.next_platform_recovery_time_sec or not move_plan.active_vacancy_chain_actors.is_empty():
		return false
	var occupied: Dictionary = {}
	for cell in current_cells.values():
		occupied[cell] = true
	var allowed: Dictionary = {}
	for cell in plan.platform_footprint:
		allowed[cell] = true
	if move_plan.planning_time_sec - move_plan.last_platform_progress_time_sec < PLATFORM_RECOVERY_STALL_SEC:
		# Progress elsewhere must not starve one physically isolated, high-retry
		# final owner. Keep the ordinary recovery gate for every other member.
		if plan.platform_slots.size() < 20 or plan.settled_platform_member_ids.size() * 5 < plan.platform_slots.size() * 3 or not plan.pending_platform_member_ids.is_empty():
			return false
		for waiting in plan.admitted_platform_member_ids:
			if not current_cells.has(waiting) or plan.is_slot_locked(waiting) or move_plan.member_pending_proposal_id.has(waiting) or int(move_plan.member_route_retry_count.get(waiting, 0)) < 12 or move_plan.planning_time_sec < float(move_plan.member_swap_cooldown_until_sec.get(waiting, 0.0)):
				continue
			var vacancy: Vector2i = plan.get_slot_for_member(waiting)
			if current_cells[waiting] == vacancy or occupied.has(vacancy) or blocked_destinations.has(vacancy):
				continue
			if _prior_entrant_final_isolated(plan, waiting, current_cells, terrain, occupied):
				return _recover_isolated_final_vacancy(move_plan, plan, current_cells, terrain, occupied, allowed, blocked_destinations, waiting)
		return false
	if _recover_compact_exterior_slot(move_plan, plan, current_cells, terrain, occupied):
		return true
	if _recover_isolated_final_vacancy(move_plan, plan, current_cells, terrain, occupied, allowed, blocked_destinations):
		return true
	if _recover_broad_final_vacancy(move_plan, plan, current_cells, terrain, occupied, blocked_destinations):
		return true
	var entry_lane: Dictionary = {}
	for cell in move_plan.macro_path:
		if allowed.has(cell):
			entry_lane[cell] = true
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	# First free an admitted ingress blocker by giving it a presently reachable
	# side target. The pending owner receives the old provisional target.
	for a in plan.admitted_platform_member_ids:
		if plan.is_slot_locked(a) or not current_cells.has(a) or move_plan.member_pending_proposal_id.has(a) or move_plan.planning_time_sec < float(move_plan.member_swap_cooldown_until_sec.get(a, 0.0)):
			continue
		var ca: Vector2i = current_cells[a]
		if absi(ca.x - plan.ingress_cell.x) + absi(ca.y - plan.ingress_cell.y) > 4:
			continue
		var free_allowed: Dictionary = allowed.duplicate()
		for occupied_cell in occupied.keys():
			if occupied_cell != ca:
				free_allowed.erase(occupied_cell)
		var own_slot: Vector2i = plan.get_slot_for_member(a)
		var own_depth: int = (own_slot.x - plan.ingress_cell.x) * plan.final_facing.x + (own_slot.y - plan.ingress_cell.y) * plan.final_facing.y
		if _platform_distance(ca, own_slot, terrain, free_allowed) >= 0 and int(move_plan.member_route_retry_count.get(a, 0)) < 3:
			continue
		var best_owner := -1
		var best_distance := 999999
		var best_depth := -999999
		for slot in plan.platform_slots:
			if occupied.has(slot) or entry_lane.has(slot):
				continue
			if move_plan.member_recovery_vacated_cell.get(a, Vector2i(-1, -1)) == slot:
				continue
			var b: int = int(plan.slot_owner_map.get(slot, -1))
			if b == a or not plan.is_platform_member(b) or plan.is_slot_locked(b) or move_plan.member_pending_proposal_id.has(b) or move_plan.planning_time_sec < float(move_plan.member_swap_cooldown_until_sec.get(b, 0.0)):
				continue
			var depth: int = (slot.x - plan.ingress_cell.x) * plan.final_facing.x + (slot.y - plan.ingress_cell.y) * plan.final_facing.y
			if plan.approach_bottlenecked != 0 and plan.pending_platform_member_ids.has(b) and depth < own_depth:
				continue
			var distance := _platform_distance(ca, slot, terrain, free_allowed)
			if distance < 0:
				continue
			if distance < best_distance or (distance == best_distance and depth > best_depth):
				best_owner = b
				best_distance = distance
				best_depth = depth
		if best_owner >= 0 and plan.swap_member_slots(a, best_owner):
			move_plan.note_assignment_change(a)
			move_plan.note_assignment_change(best_owner)
			move_plan.member_swap_cooldown_until_sec[a] = move_plan.planning_time_sec + PLATFORM_RECOVERY_COOLDOWN_SEC
			move_plan.member_swap_cooldown_until_sec[best_owner] = move_plan.planning_time_sec + PLATFORM_RECOVERY_COOLDOWN_SEC
			move_plan.next_platform_recovery_time_sec = move_plan.planning_time_sec + PLATFORM_RECOVERY_COOLDOWN_SEC
			return true
	# If settled soldiers separate the entrance from a vacant final cell,
	# move one blocker one legal step into that vacancy. Grid performs the step.
	var reachable_empty: Dictionary = {}
	var frontier: Array[Vector2i] = []
	if not occupied.has(plan.ingress_cell) and not blocked_destinations.has(plan.ingress_cell):
		reachable_empty[plan.ingress_cell] = true
		frontier.append(plan.ingress_cell)
	else:
		for direction in directions:
			var near_entry: Vector2i = plan.ingress_cell + direction
			if allowed.has(near_entry) and not occupied.has(near_entry) and not blocked_destinations.has(near_entry) and terrain.can_step(plan.ingress_cell, near_entry):
				reachable_empty[near_entry] = true
				frontier.append(near_entry)
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_front()
		for direction in directions:
			var next_cell: Vector2i = cell + direction
			if reachable_empty.has(next_cell) or occupied.has(next_cell) or blocked_destinations.has(next_cell) or not allowed.has(next_cell) or not terrain.can_step(cell, next_cell):
				continue
			reachable_empty[next_cell] = true
			frontier.append(next_cell)
	var entry_lane_open := true
	for lane_cell in entry_lane.keys():
		if occupied.has(lane_cell):
			entry_lane_open = false
			break
	if entry_lane_open:
		move_plan.next_platform_recovery_time_sec = move_plan.planning_time_sec + PLATFORM_RECOVERY_COOLDOWN_SEC
		return false
	var movable_at: Dictionary = {}
	var seeds: Array[int] = []
	for mid in plan.admitted_platform_member_ids:
		if not current_cells.has(mid) or move_plan.member_pending_proposal_id.has(mid) or move_plan.planning_time_sec < float(move_plan.member_swap_cooldown_until_sec.get(mid, 0.0)):
			continue
		var cell: Vector2i = current_cells[mid]
		if cell != plan.get_slot_for_member(mid) or not allowed.has(cell):
			continue
		movable_at[cell] = mid
		if entry_lane.has(cell):
			seeds.append(mid)
	seeds.sort_custom(func(a: int, b: int) -> bool:
		var ca: Vector2i = current_cells[a]
		var cb: Vector2i = current_cells[b]
		var da: int = absi(ca.x - plan.ingress_cell.x) + absi(ca.y - plan.ingress_cell.y)
		var db: int = absi(cb.x - plan.ingress_cell.x) + absi(cb.y - plan.ingress_cell.y)
		return da < db if da != db else a < b
	)
	for seed in seeds:
		var seed_cell: Vector2i = current_cells[seed]
		var chain_frontier: Array[Vector2i] = [seed_cell]
		var predecessor: Dictionary = {seed_cell: seed_cell}
		while not chain_frontier.is_empty():
			var chain_cell: Vector2i = chain_frontier.pop_front()
			for direction in directions:
				var neighbor: Vector2i = chain_cell + direction
				if not allowed.has(neighbor) or not plan.slot_owner_map.has(neighbor) or not TransitPlanner._can_profile_step(terrain, chain_cell, neighbor, null):
					continue
				if occupied.has(neighbor):
					if movable_at.has(neighbor) and not predecessor.has(neighbor):
						predecessor[neighbor] = chain_cell
						chain_frontier.append(neighbor)
					continue
				if reachable_empty.has(neighbor) or blocked_destinations.has(neighbor):
					continue
				var chain_cells: Array[Vector2i] = [neighbor]
				var back: Vector2i = chain_cell
				while back != seed_cell:
					chain_cells.push_front(back)
					back = predecessor[back]
				chain_cells.push_front(seed_cell)
				var actors: Array[int] = []
				var targets: Array[Vector2i] = []
				var safe := true
				for i in range(chain_cells.size() - 1):
					var actor: int = int(movable_at[chain_cells[i]])
					var target: Vector2i = chain_cells[i + 1]
					var owner: int = int(plan.slot_owner_map[target])
					if move_plan.member_pending_proposal_id.has(owner) or (plan.is_slot_locked(owner) and not movable_at.values().has(owner)):
						safe = false
						break
					actors.append(actor)
					targets.append(target)
				if not safe:
					continue
				if not _start_platform_vacancy_chain(move_plan, plan, actors, targets, current_cells):
					continue
				return true
	move_plan.next_platform_recovery_time_sec = move_plan.planning_time_sec + PLATFORM_RECOVERY_COOLDOWN_SEC
	return false

## On an open compact final block, an earlier entrant can be routed around the
## settled edge while still owning a deep, vacant final. Exchange two compatible
## provisional targets only when both resulting physical routes are free and
## their combined distance strictly improves. Grid performs every later step.
static func _recover_compact_exterior_slot(move_plan: CombatMovePlan, plan: CombatDeploymentPlan, current_cells: Dictionary, terrain: Object, occupied: Dictionary) -> bool:
	if plan.platform_slots.size() < 20 or plan.settled_platform_member_ids.size() * 5 < plan.platform_slots.size() * 3 or _never_crossed_platform_count(plan, current_cells) > 1:
		return false
	var entry_lane: Dictionary = {}
	for cell in move_plan.macro_path:
		if plan.platform_footprint.has(cell):
			entry_lane[cell] = true
	var min_x := 2147483647
	var max_x := -2147483647
	var min_y := 2147483647
	var max_y := -2147483647
	for slot in plan.platform_slots:
		min_x = mini(min_x, slot.x)
		max_x = maxi(max_x, slot.x)
		min_y = mini(min_y, slot.y)
		max_y = maxi(max_y, slot.y)
	var best_a := -1
	var best_b := -1
	var best_gain := 3
	var exterior_candidates: Array[int] = plan.admitted_platform_member_ids.duplicate()
	for mid in plan.pending_platform_member_ids:
		if _is_prior_platform_entrant_beyond_handoff(plan, mid, current_cells):
			exterior_candidates.append(mid)
	for a in exterior_candidates:
		if not current_cells.has(a) or plan.is_slot_locked(a) or move_plan.member_pending_proposal_id.has(a) or move_plan.planning_time_sec < float(move_plan.member_swap_cooldown_until_sec.get(a, 0.0)):
			continue
		var ca: Vector2i = current_cells[a]
		if plan.platform_footprint.has(ca) or ca.x < min_x - 12 or ca.x > max_x + 12 or ca.y < min_y - 12 or ca.y > max_y + 12:
			continue
		var sa: Vector2i = plan.get_slot_for_member(a)
		if occupied.has(sa) or entry_lane.has(sa) or int(move_plan.member_route_retry_count.get(a, 0)) < 3:
			continue
		var free_cells: Dictionary = {}
		for x in range(mini(min_x, ca.x) - 4, maxi(max_x, ca.x) + 5):
			for y in range(mini(min_y, ca.y) - 4, maxi(max_y, ca.y) + 5):
				var cell := Vector2i(x, y)
				if terrain.contains(cell) and terrain.is_walkable(cell) and not occupied.has(cell):
					free_cells[cell] = true
		free_cells[ca] = true
		for b in plan.admitted_platform_member_ids:
			if a == b or not current_cells.has(b) or plan.is_slot_locked(b) or move_plan.member_pending_proposal_id.has(b) or move_plan.planning_time_sec < float(move_plan.member_swap_cooldown_until_sec.get(b, 0.0)):
				continue
			var sb: Vector2i = plan.get_slot_for_member(b)
			if occupied.has(sb) or entry_lane.has(sb):
				continue
			var cb: Vector2i = current_cells[b]
			var old_cost: int = absi(ca.x - sa.x) + absi(ca.y - sa.y) + absi(cb.x - sb.x) + absi(cb.y - sb.y)
			var new_cost: int = absi(ca.x - sb.x) + absi(ca.y - sb.y) + absi(cb.x - sa.x) + absi(cb.y - sa.y)
			var gain: int = old_cost - new_cost
			if gain <= best_gain:
				continue
			free_cells[cb] = true
			var a_reachable: bool = _platform_distance(ca, sb, terrain, free_cells, 512) >= 0
			var b_reachable: bool = a_reachable and _platform_distance(cb, sa, terrain, free_cells, 512) >= 0
			free_cells.erase(cb)
			if not b_reachable:
				continue
			best_a = a
			best_b = b
			best_gain = gain
	if best_a < 0 or not plan.swap_member_slots(best_a, best_b):
		return false
	for mid in [best_a, best_b]:
		move_plan.note_assignment_change(mid)
		move_plan.member_swap_cooldown_until_sec[mid] = move_plan.planning_time_sec + PLATFORM_RECOVERY_COOLDOWN_SEC
	move_plan.next_platform_recovery_time_sec = move_plan.planning_time_sec + PLATFORM_RECOVERY_COOLDOWN_SEC
	return true

static func _rotate_platform_vacancy_chain(move_plan: CombatMovePlan, plan: CombatDeploymentPlan, actors: Array[int], targets: Array[Vector2i]) -> Array[int]:
	for i in range(actors.size()):
		if move_plan.member_recovery_vacated_cell.get(actors[i], Vector2i(-1, -1)) == targets[i]:
			return []
	var old_slots: Dictionary = {}
	for actor in actors:
		old_slots[actor] = plan.get_slot_for_member(actor)
	for target in targets:
		var owner: int = int(plan.slot_owner_map.get(target, -1))
		if owner >= 0 and not old_slots.has(owner):
			old_slots[owner] = plan.get_slot_for_member(owner)
	var changed: Array[int] = plan.rotate_vacancy_chain_targets(actors, targets)
	for mid in changed:
		move_plan.member_recovery_vacated_cell[mid] = old_slots[mid]
	return changed

static func _begin_vacancy_chain(move_plan: CombatMovePlan, actors: Array[int], current_cells: Dictionary) -> void:
	move_plan.active_vacancy_chain_actors = actors
	move_plan.vacancy_chain_started_sec = move_plan.planning_time_sec
	move_plan.vacancy_chain_last_progress_sec = move_plan.planning_time_sec
	move_plan.vacancy_chain_arrived_count = 0
	move_plan.member_vacancy_chain_start_cell.clear()
	for mid in actors:
		move_plan.member_vacancy_chain_start_cell[mid] = current_cells.get(mid, Vector2i(-1, -1))

## A physical vacancy must pass through actual owners of adjacent final cells.
## Grid can commit the whole chain only when every step has one direction;
## a turn uses the same tail-first queue as isolated final recovery.
static func _start_platform_vacancy_chain(move_plan: CombatMovePlan, plan: CombatDeploymentPlan, actors: Array[int], targets: Array[Vector2i], current_cells: Dictionary) -> bool:
	if actors.is_empty() or actors.size() != targets.size():
		return false
	var first_direction: Vector2i = targets[0] - current_cells.get(actors[0], Vector2i(-1, -1))
	var straight := true
	for i in range(actors.size()):
		var actor: int = actors[i]
		if not current_cells.has(actor) or current_cells[actor] != plan.get_slot_for_member(actor) or move_plan.member_pending_proposal_id.has(actor):
			return false
		var step: Vector2i = targets[i] - current_cells[actor]
		if absi(step.x) + absi(step.y) != 1 or (i + 1 < actors.size() and targets[i] != current_cells[actors[i + 1]]):
			return false
		straight = straight and step == first_direction
	var vacancy: Vector2i = targets.back()
	if current_cells.values().has(vacancy):
		return false
	var waiting: int = int(plan.slot_owner_map.get(vacancy, -1))
	if waiting < 0 or move_plan.member_pending_proposal_id.has(waiting) or plan.is_slot_locked(waiting):
		return false
	var moving_actors: Array[int] = []
	var moving_targets: Array[Vector2i] = []
	if straight:
		moving_actors = actors
		moving_targets = targets
	else:
		moving_actors.append(actors.back())
		moving_targets.append(vacancy)
	var changed: Array[int] = _rotate_platform_vacancy_chain(move_plan, plan, moving_actors, moving_targets)
	if changed.is_empty():
		return false
	move_plan.vacancy_waiting_id = waiting
	move_plan.member_recovery_hold[waiting] = true
	if not straight:
		move_plan.queued_vacancy_steps.clear()
		for i in range(actors.size() - 1):
			move_plan.queued_vacancy_steps.append({"actor": actors[i], "from": current_cells[actors[i]], "to": targets[i]})
	_begin_vacancy_chain(move_plan, moving_actors, current_cells)
	for mid in changed:
		move_plan.note_assignment_change(mid)
		if moving_actors.has(mid):
			move_plan.member_vacancy_chain_target[mid] = plan.get_slot_for_member(mid)
		move_plan.member_swap_cooldown_until_sec[mid] = move_plan.planning_time_sec + PLATFORM_RECOVERY_COOLDOWN_SEC
	move_plan.next_platform_recovery_time_sec = move_plan.planning_time_sec + PLATFORM_RECOVERY_COOLDOWN_SEC
	return true

static func _clear_queued_vacancy_steps(move_plan: CombatMovePlan) -> void:
	move_plan.queued_vacancy_steps.clear()
	move_plan.member_recovery_hold.erase(move_plan.vacancy_waiting_id)
	move_plan.vacancy_waiting_id = -1

## The isolated-vacancy path may turn corners. Only assign the occupant next to
## the actual empty cell; the next target changes after that physical step ends.
static func _advance_queued_vacancy_step(move_plan: CombatMovePlan, plan: CombatDeploymentPlan, current_cells: Dictionary, terrain: Object, blocked_destinations: Dictionary) -> void:
	if move_plan.queued_vacancy_steps.is_empty() or terrain == null:
		_clear_queued_vacancy_steps(move_plan)
		return
	var step: Dictionary = move_plan.queued_vacancy_steps.pop_back()
	var actor: int = int(step.get("actor", -1))
	var from: Vector2i = step.get("from", Vector2i(-1, -1))
	var target: Vector2i = step.get("to", Vector2i(-1, -1))
	var waiting: int = move_plan.vacancy_waiting_id
	if actor < 0 or waiting < 0 or not current_cells.has(actor) or current_cells[actor] != from or plan.get_slot_for_member(actor) != from or plan.get_slot_for_member(waiting) != target or move_plan.member_pending_proposal_id.has(actor) or blocked_destinations.has(target) or not TransitPlanner._can_profile_step(terrain, from, target, null):
		_clear_queued_vacancy_steps(move_plan)
		return
	for occupant in current_cells.keys():
		if current_cells[occupant] == target:
			_clear_queued_vacancy_steps(move_plan)
			return
	var changed: Array[int] = _rotate_platform_vacancy_chain(move_plan, plan, [actor], [target])
	if changed.is_empty():
		_clear_queued_vacancy_steps(move_plan)
		return
	_begin_vacancy_chain(move_plan, [actor], current_cells)
	for mid in changed:
		move_plan.note_assignment_change(mid)
		if mid == actor:
			move_plan.member_vacancy_chain_target[mid] = plan.get_slot_for_member(mid)

## At the very end, an empty final can be enclosed by settled soldiers.
## Move one adjacent settled owner into it, giving the stranded soldier the
## newly exposed edge slot. This exchanges targets only; Grid moves both later.
static func _recover_isolated_final_vacancy(move_plan: CombatMovePlan, plan: CombatDeploymentPlan, current_cells: Dictionary, terrain: Object, occupied: Dictionary, allowed: Dictionary, blocked_destinations: Dictionary = {}, preferred_waiting: int = -1) -> bool:
	# Once the last entrant is approaching a mostly occupied final block, a
	# vacant interior slot can already be sealed behind settled FLEX soldiers.
	# Waiting for all but three to settle leaves those earlier stranded owners
	# outside the block with no legal first step toward their targets.
	if (plan.platform_slots.size() < 20 and plan.formation_preset_id == "auto") or plan.settled_platform_member_ids.size() * 5 < plan.platform_slots.size() * 3 or _never_crossed_platform_count(plan, current_cells) > 1:
		return false
	var movable_at: Dictionary = {}
	for mid in plan.settled_platform_member_ids:
		if not current_cells.has(mid) or move_plan.member_pending_proposal_id.has(mid):
			continue
		var cell: Vector2i = current_cells[mid]
		if cell == plan.get_slot_for_member(mid):
			movable_at[cell] = mid
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	var waiting_order: Array[int] = []
	for waiting in plan.admitted_platform_member_ids:
		if move_plan.member_recovery_hold.has(waiting):
			waiting_order.append(waiting)
	for waiting in plan.admitted_platform_member_ids:
		if not move_plan.member_recovery_hold.has(waiting):
			waiting_order.append(waiting)
	# A former entrant can detour beyond the footprint and be classified pending
	# again. It still owns a platform final and may need the same vacancy chain.
	var prior_entrants: Array[int] = []
	for waiting in plan.pending_platform_member_ids:
		if _is_prior_platform_entrant_beyond_handoff(plan, waiting, current_cells) and int(move_plan.member_route_retry_count.get(waiting, 0)) >= 12 and _prior_entrant_final_isolated(plan, waiting, current_cells, terrain, occupied):
			prior_entrants.append(waiting)
	# A soldier that already entered but detoured outside cannot settle through
	# ordinary admission; serve its reachable vacancy before interior waiters.
	for i in range(prior_entrants.size() - 1, -1, -1):
		waiting_order.push_front(prior_entrants[i])
	# An in-flight soldier cannot have its committed final changed. Try a
	# stationary stranded owner first, so one recurring proposal cannot starve
	# every other reachable vacancy chain in a compact final block.
	var original_waiting_rank: Dictionary = {}
	for i in range(waiting_order.size()):
		original_waiting_rank[waiting_order[i]] = i
	waiting_order.sort_custom(func(a: int, b: int) -> bool:
		var a_in_flight: bool = move_plan.member_pending_proposal_id.has(a)
		var b_in_flight: bool = move_plan.member_pending_proposal_id.has(b)
		if a_in_flight != b_in_flight:
			return not a_in_flight
		return int(original_waiting_rank[a]) < int(original_waiting_rank[b])
	)
	for waiting in waiting_order:
		if preferred_waiting >= 0 and waiting != preferred_waiting:
			continue
		if not current_cells.has(waiting) or plan.is_slot_locked(waiting):
			move_plan.member_recovery_hold.erase(waiting)
			continue
		var vacancy: Vector2i = plan.get_slot_for_member(waiting)
		if occupied.has(vacancy) or blocked_destinations.has(vacancy):
			move_plan.member_recovery_hold.erase(waiting)
			continue
		var start: Vector2i = current_cells[waiting]
		# The waiting soldier may have detoured several cells outside the broad
		# footprint. Search a bounded exterior apron around that soldier and the
		# final block; otherwise an interior vacancy chain has no visible exit.
		var min_x: int = start.x
		var max_x: int = start.x
		var min_y: int = start.y
		var max_y: int = start.y
		for slot in plan.platform_slots:
			min_x = mini(min_x, slot.x)
			max_x = maxi(max_x, slot.x)
			min_y = mini(min_y, slot.y)
			max_y = maxi(max_y, slot.y)
		var free_cells: Dictionary = {}
		for x in range(min_x - 4, max_x + 5):
			for y in range(min_y - 4, max_y + 5):
				var candidate := Vector2i(x, y)
				if terrain.contains(candidate) and terrain.is_walkable(candidate):
					free_cells[candidate] = true
		for cell in occupied.keys():
			if cell != start:
				free_cells.erase(cell)
		free_cells[start] = true
		var reachable: Dictionary = {start: true}
		var free_distance: Dictionary = {start: 0}
		var free_frontier: Array[Vector2i] = [start]
		while not free_frontier.is_empty() and reachable.size() <= 512:
			var free_cell: Vector2i = free_frontier.pop_front()
			for direction in directions:
				var next_free: Vector2i = free_cell + direction
				if not reachable.has(next_free) and free_cells.has(next_free) and TransitPlanner._can_profile_step(terrain, free_cell, next_free, null):
					reachable[next_free] = true
					free_distance[next_free] = int(free_distance[free_cell]) + 1
					free_frontier.append(next_free)
		if reachable.has(vacancy):
			var free_steps: int = int(free_distance[vacancy])
			var direct_steps: int = absi(start.x - vacancy.x) + absi(start.y - vacancy.y)
			# A technically reachable final can still require a long lap around a
			# settled wall. After repeated failed physical routes, bring the vacancy
			# to the free edge instead of sending its owner around that wall again.
			var failed_routes: int = int(move_plan.member_route_retry_count.get(waiting, 0))
			# A short free-only detour is not proof that the bounded live route can
			# use it. Repeated failures after a genuine platform stall justify the
			# same target-only vacancy rotation used for an enclosed final.
			if failed_routes < 3 or (failed_routes < 12 and free_steps <= maxi(18, direct_steps + 6)):
				move_plan.member_recovery_hold.erase(waiting)
				continue
		# Keep the existing physical batch intact. Stop queuing another step so
		# the next planning tick sees a stationary owner and can rotate targets.
		if move_plan.member_pending_proposal_id.has(waiting):
			move_plan.member_recovery_hold[waiting] = true
			return true
		# Walk the vacancy backwards through occupied final-slot owners
		# until it reaches a face of the free area accessible to this soldier.
		var predecessor: Dictionary = {vacancy: vacancy}
		var depth: Dictionary = {vacancy: 0}
		var vacancy_frontier: Array[Vector2i] = [vacancy]
		var edge: Vector2i = Vector2i(-1, -1)
		var best_total_distance := 999999
		var best_free_distance := 999999
		var best_chain_depth := 999999
		var waiting_inside_footprint: bool = plan.platform_footprint.has(start)
		while not vacancy_frontier.is_empty() and predecessor.size() <= 128:
			var opening: Vector2i = vacancy_frontier.pop_front()
			for direction in directions:
				var blocker_cell: Vector2i = opening + direction
				if predecessor.has(blocker_cell) or not movable_at.has(blocker_cell) or not TransitPlanner._can_profile_step(terrain, blocker_cell, opening, null):
					continue
				# A recently vacated target would make this chain an immediate reversal.
				# Keep searching the other physical edge instead of selecting a chain
				# that rotate_vacancy_chain_targets must reject later.
				if move_plan.member_recovery_vacated_cell.get(int(movable_at[blocker_cell]), Vector2i(-1, -1)) == opening:
					continue
				predecessor[blocker_cell] = opening
				depth[blocker_cell] = int(depth[opening]) + 1
				for free_direction in directions:
					var adjacent_free: Vector2i = blocker_cell + free_direction
					if reachable.has(adjacent_free) and TransitPlanner._can_profile_step(terrain, adjacent_free, blocker_cell, null):
						var distance_to_waiting: int = int(free_distance[adjacent_free])
						var total_distance: int = distance_to_waiting + int(depth[blocker_cell])
						var chain_depth: int = int(depth[blocker_cell])
						var better_tie: bool = chain_depth < best_chain_depth or (chain_depth == best_chain_depth and distance_to_waiting < best_free_distance)
						if waiting_inside_footprint:
							better_tie = distance_to_waiting < best_free_distance or (distance_to_waiting == best_free_distance and chain_depth < best_chain_depth)
						if total_distance < best_total_distance or (total_distance == best_total_distance and better_tie):
							edge = blocker_cell
							best_total_distance = total_distance
							best_free_distance = distance_to_waiting
							best_chain_depth = chain_depth
				if int(depth[blocker_cell]) < 32:
					vacancy_frontier.append(blocker_cell)
		if edge == Vector2i(-1, -1):
			continue
		var actors: Array[int] = []
		var targets: Array[Vector2i] = []
		var chain_cell: Vector2i = edge
		while chain_cell != vacancy:
			actors.append(int(movable_at[chain_cell]))
			var next_cell: Vector2i = predecessor[chain_cell]
			targets.append(next_cell)
			chain_cell = next_cell
		var owner_in_flight := false
		for target in targets:
			if move_plan.member_pending_proposal_id.has(int(plan.slot_owner_map[target])):
				owner_in_flight = true
				break
		if owner_in_flight:
			continue
		# A turning chain cannot be committed as one Grid batch. Keep the
		# assignment changes in vacancy order and issue only its last step.
		var changed: Array[int] = _rotate_platform_vacancy_chain(move_plan, plan, [actors.back()], [targets.back()])
		if changed.is_empty():
			continue
		move_plan.queued_vacancy_steps.clear()
		for i in range(actors.size() - 1):
			move_plan.queued_vacancy_steps.append({"actor": actors[i], "from": current_cells[actors[i]], "to": targets[i]})
		move_plan.vacancy_waiting_id = waiting
		move_plan.member_recovery_hold[waiting] = true
		_begin_vacancy_chain(move_plan, [actors.back()], current_cells)
		for mid in changed:
			move_plan.note_assignment_change(mid)
			if mid == actors.back():
				move_plan.member_vacancy_chain_target[mid] = plan.get_slot_for_member(mid)
		move_plan.next_platform_recovery_time_sec = move_plan.planning_time_sec + PLATFORM_RECOVERY_COOLDOWN_SEC
		return true
	return false

static func _prior_entrant_final_isolated(plan: CombatDeploymentPlan, waiting: int, current_cells: Dictionary, terrain: Object, occupied: Dictionary) -> bool:
	var start: Vector2i = current_cells[waiting]
	var goal: Vector2i = plan.get_slot_for_member(waiting)
	var min_x: int = start.x
	var max_x: int = start.x
	var min_y: int = start.y
	var max_y: int = start.y
	for slot in plan.platform_slots:
		min_x = mini(min_x, slot.x)
		max_x = maxi(max_x, slot.x)
		min_y = mini(min_y, slot.y)
		max_y = maxi(max_y, slot.y)
	var free_cells: Dictionary = {}
	for x in range(min_x - 4, max_x + 5):
		for y in range(min_y - 4, max_y + 5):
			var candidate := Vector2i(x, y)
			if terrain.contains(candidate) and terrain.is_walkable(candidate) and (not occupied.has(candidate) or candidate == start):
				free_cells[candidate] = true
	return _platform_distance(start, goal, terrain, free_cells, 512) < 0

## Late in a broad deployment, a wall of settled ordinary slots can hide a
## vacant final cell from its owner. Rotate only target ownership along one
## adjacent vacancy-terminated chain; Grid still performs every physical step.
static func _recover_broad_final_vacancy(move_plan: CombatMovePlan, plan: CombatDeploymentPlan, current_cells: Dictionary, terrain: Object, occupied: Dictionary, blocked_destinations: Dictionary = {}) -> bool:
	if plan.settled_platform_member_ids.size() < 8:
		return false
	var nearest_entry_slot := 999999
	for slot in plan.platform_slots:
		nearest_entry_slot = mini(nearest_entry_slot, absi(slot.x - plan.ingress_cell.x) + absi(slot.y - plan.ingress_cell.y))
	if nearest_entry_slot < 8:
		return false
	var movable_at: Dictionary = {}
	for mid in plan.admitted_platform_member_ids:
		if not current_cells.has(mid) or move_plan.member_pending_proposal_id.has(mid):
			continue
		var cell: Vector2i = current_cells[mid]
		if cell == plan.get_slot_for_member(mid):
			movable_at[cell] = mid
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for blocked_mid in plan.admitted_platform_member_ids:
		if not current_cells.has(blocked_mid) or plan.is_slot_locked(blocked_mid) or move_plan.member_pending_proposal_id.has(blocked_mid):
			continue
		var blocked_cell: Vector2i = current_cells[blocked_mid]
		var desired: Vector2i = plan.get_slot_for_member(blocked_mid)
		if blocked_cell == desired or occupied.has(desired):
			continue
		var seeds: Array[Vector2i] = []
		for direction in directions:
			var near: Vector2i = blocked_cell + direction
			if movable_at.has(near) and TransitPlanner._can_profile_step(terrain, blocked_cell, near, null):
				seeds.append(near)
		for seed in seeds:
			var frontier: Array[Vector2i] = [seed]
			var predecessor: Dictionary = {}
			predecessor[seed] = seed
			var chosen: Array[Vector2i] = []
			while not frontier.is_empty() and predecessor.size() <= 128:
				var cell: Vector2i = frontier.pop_front()
				for direction in directions:
					var next_cell: Vector2i = cell + direction
					if not plan.slot_owner_map.has(next_cell) or not TransitPlanner._can_profile_step(terrain, cell, next_cell, null):
						continue
					if occupied.has(next_cell):
						if movable_at.has(next_cell) and not predecessor.has(next_cell):
							predecessor[next_cell] = cell
							frontier.append(next_cell)
						continue
					if blocked_destinations.has(next_cell):
						continue
					var candidate: Array[Vector2i] = [next_cell]
					var back: Vector2i = cell
					while back != seed:
						candidate.push_front(back)
						back = predecessor[back]
					candidate.push_front(seed)
					if next_cell == desired:
						chosen = candidate
						break
				if not chosen.is_empty():
					break
			if chosen.is_empty():
				continue
			var actors: Array[int] = []
			var targets: Array[Vector2i] = []
			for i in range(chosen.size() - 1):
				actors.append(int(movable_at[chosen[i]]))
				targets.append(chosen[i + 1])
			if not _start_platform_vacancy_chain(move_plan, plan, actors, targets, current_cells):
				continue
			return true
	return false

## During queue settling, shift one locked side-slot owner into its adjacent
## vacancy, then let the waiting queue owner use the newly opened cell.
static func recover_stalled_queue_slots(move_plan: CombatMovePlan, plan: CombatDeploymentPlan, current_cells: Dictionary, terrain: Object) -> bool:
	if not plan.queue_released or plan.settled_queue_member_ids.size() >= plan.queue_member_ids.size() or move_plan.planning_time_sec - move_plan.last_queue_progress_time_sec < PLATFORM_RECOVERY_STALL_SEC or move_plan.planning_time_sec < move_plan.next_queue_recovery_time_sec:
		return false
	var occupied: Dictionary = {}
	for mid in current_cells.keys():
		occupied[current_cells[mid]] = mid
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for waiting in plan.queue_member_ids:
		if plan.is_slot_locked(waiting) or not current_cells.has(waiting) or move_plan.member_pending_proposal_id.has(waiting):
			continue
		var vacancy: Vector2i = plan.get_slot_for_member(waiting)
		if occupied.has(vacancy):
			continue
		var waiting_cell: Vector2i = current_cells[waiting]
		for direction in directions:
			var blocker_cell: Vector2i = vacancy + direction
			var blocker: int = int(occupied.get(blocker_cell, -1))
			if blocker < 0 or not plan.is_queue_member(blocker) or not plan.is_slot_locked(blocker) or not plan.settled_queue_member_ids.has(blocker) or move_plan.member_pending_proposal_id.has(blocker):
				continue
			if not terrain.can_step(blocker_cell, vacancy) or plan.get_slot_for_member(blocker) != blocker_cell:
				continue
			var free_route: Dictionary = {waiting_cell: true, blocker_cell: true}
			for x in range(mini(waiting_cell.x, blocker_cell.x) - 2, maxi(waiting_cell.x, blocker_cell.x) + 3):
				for y in range(mini(waiting_cell.y, blocker_cell.y) - 2, maxi(waiting_cell.y, blocker_cell.y) + 3):
					var probe := Vector2i(x, y)
					if not occupied.has(probe) and terrain.contains(probe) and terrain.is_walkable(probe):
						free_route[probe] = true
			if _platform_distance(waiting_cell, blocker_cell, terrain, free_route) < 0:
				continue
			plan.member_slot_locked.erase(blocker)
			if not plan.swap_member_slots(blocker, waiting):
				plan.lock_member_slot(blocker)
				continue
			plan.settled_queue_member_ids.erase(blocker)
			move_plan.note_assignment_change(blocker)
			move_plan.note_assignment_change(waiting)
			move_plan.next_queue_recovery_time_sec = move_plan.planning_time_sec + PLATFORM_RECOVERY_COOLDOWN_SEC
			return true
	move_plan.next_queue_recovery_time_sec = move_plan.planning_time_sec + PLATFORM_RECOVERY_COOLDOWN_SEC
	return false

static func rebalance_provisional_slots(move_plan: CombatMovePlan, plan: CombatDeploymentPlan, current_cells: Dictionary, terrain: Object, admission_changed: bool = false) -> bool:
	if move_plan == null or plan == null or terrain == null:
		return false
	if not admission_changed and move_plan.planning_time_sec < move_plan.next_late_swap_time_sec:
		return false
	move_plan.next_late_swap_time_sec = move_plan.planning_time_sec + 0.5
	var mids: Array[int] = []
	for mid in plan.admitted_platform_member_ids:
		if not plan.is_slot_locked(mid) and current_cells.has(mid) and not move_plan.member_pending_proposal_id.has(mid):
			mids.append(mid)
	mids.sort_custom(func(a: int, b: int) -> bool:
		var ra: int = int(move_plan.member_sequence_rank.get(a, 9999))
		var rb: int = int(move_plan.member_sequence_rank.get(b, 9999))
		return ra < rb if ra != rb else a < b
	)
	var allowed: Dictionary = {}
	for cell in plan.platform_footprint:
		allowed[cell] = true
	var entry_lane: Dictionary = {}
	if not plan.pending_platform_member_ids.is_empty():
		for cell in move_plan.macro_path:
			if allowed.has(cell):
				entry_lane[cell] = true
	for i in range(maxi(0, mini(mids.size() - 1, 16))):
		var a: int = mids[i]
		var b: int = mids[i + 1]
		if move_plan.planning_time_sec < float(move_plan.member_swap_cooldown_until_sec.get(a, 0.0)) or move_plan.planning_time_sec < float(move_plan.member_swap_cooldown_until_sec.get(b, 0.0)):
			continue
		var ca: Vector2i = current_cells[a]
		var cb: Vector2i = current_cells[b]
		var sa: Vector2i = plan.get_slot_for_member(a)
		var sb: Vector2i = plan.get_slot_for_member(b)
		var depth_a: int = (sa.x - plan.ingress_cell.x) * plan.final_facing.x + (sa.y - plan.ingress_cell.y) * plan.final_facing.y
		var depth_b: int = (sb.x - plan.ingress_cell.x) * plan.final_facing.x + (sb.y - plan.ingress_cell.y) * plan.final_facing.y
		if not plan.pending_platform_member_ids.is_empty() and depth_a != depth_b:
			continue
		if entry_lane.has(sa) or entry_lane.has(sb):
			continue
		if not allowed.has(ca) or not allowed.has(cb):
			continue
		var own_a := _platform_distance(ca, sa, terrain, allowed)
		var own_b := _platform_distance(cb, sb, terrain, allowed)
		var swap_a := _platform_distance(ca, sb, terrain, allowed)
		var swap_b := _platform_distance(cb, sa, terrain, allowed)
		if mini(mini(own_a, own_b), mini(swap_a, swap_b)) < 0 or own_a + own_b - swap_a - swap_b < 2:
			continue
		if plan.swap_member_slots(a, b):
			move_plan.note_assignment_change(a)
			move_plan.note_assignment_change(b)
			move_plan.member_swap_cooldown_until_sec[a] = move_plan.planning_time_sec + 0.5
			move_plan.member_swap_cooldown_until_sec[b] = move_plan.planning_time_sec + 0.5
			return true
	# Earlier entrants may take a compatible free-side target still provisionally
	# assigned to someone who has not crossed the entrance. Preserve the entry lane.
	for a in mids.slice(0, mini(mids.size(), 8)):
		if move_plan.planning_time_sec < float(move_plan.member_swap_cooldown_until_sec.get(a, 0.0)):
			continue
		var ca: Vector2i = current_cells[a]
		var sa: Vector2i = plan.get_slot_for_member(a)
		var own_distance := _platform_distance(ca, sa, terrain, allowed)
		if own_distance < 0:
			continue
		var best_member := -1
		var best_gain := 1
		var best_depth_gain := 0
		var own_depth: int = (sa.x - plan.ingress_cell.x) * plan.final_facing.x + (sa.y - plan.ingress_cell.y) * plan.final_facing.y
		for b in plan.pending_platform_member_ids:
			if plan.is_slot_locked(b) or move_plan.member_pending_proposal_id.has(b) or move_plan.planning_time_sec < float(move_plan.member_swap_cooldown_until_sec.get(b, 0.0)):
				continue
			var sb: Vector2i = plan.get_slot_for_member(b)
			if entry_lane.has(sb):
				continue
			var candidate_depth: int = (sb.x - plan.ingress_cell.x) * plan.final_facing.x + (sb.y - plan.ingress_cell.y) * plan.final_facing.y
			var depth_gain: int = candidate_depth - own_depth
			if depth_gain < 0:
				continue
			var candidate_distance := _platform_distance(ca, sb, terrain, allowed)
			var gain := own_distance - candidate_distance
			if candidate_distance >= 0 and (depth_gain > best_depth_gain or (depth_gain == best_depth_gain and gain > best_gain)):
				best_depth_gain = depth_gain
				best_gain = gain
				best_member = b
		if best_member >= 0 and plan.swap_member_slots(a, best_member):
			move_plan.note_assignment_change(a)
			move_plan.note_assignment_change(best_member)
			move_plan.member_swap_cooldown_until_sec[a] = move_plan.planning_time_sec + 0.5
			move_plan.member_swap_cooldown_until_sec[best_member] = move_plan.planning_time_sec + 0.5
			return true
	return false

static func _platform_distance(start: Vector2i, goal: Vector2i, terrain: Object, allowed: Dictionary, max_cells: int = 128) -> int:
	if start == goal:
		return 0
	var frontier: Array[Vector2i] = [start]
	var distances: Dictionary = {start: 0}
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	while not frontier.is_empty() and distances.size() <= max_cells:
		var cell: Vector2i = frontier.pop_front()
		for direction in directions:
			var next_cell := cell + direction
			if distances.has(next_cell) or not allowed.has(next_cell) or not terrain.can_step(cell, next_cell):
				continue
			if next_cell == goal:
				return int(distances[cell]) + 1
			distances[next_cell] = int(distances[cell]) + 1
			frontier.append(next_cell)
	return -1

## The same bounded search as _platform_distance, shared by many candidate goals.
## Record each cell when discovered, including neighbors of the final popped cell.
static func _platform_distances(start: Vector2i, terrain: Object, allowed: Dictionary, max_cells: int = 128) -> Dictionary:
	var frontier: Array[Vector2i] = [start]
	var distances: Dictionary = {start: 0}
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	while not frontier.is_empty() and distances.size() <= max_cells:
		var cell: Vector2i = frontier.pop_front()
		for direction in directions:
			var next_cell := cell + direction
			if distances.has(next_cell) or not allowed.has(next_cell) or not terrain.can_step(cell, next_cell):
				continue
			distances[next_cell] = int(distances[cell]) + 1
			frontier.append(next_cell)
	return distances

static func _platform_handoff_cell(plan: CombatDeploymentPlan) -> Vector2i:
	return plan.get_platform_handoff_cell()

static func resolve_member_target(move_plan: CombatMovePlan, plan: CombatDeploymentPlan, member_id: int, current_cell: Vector2i) -> Dictionary:
	var invalid := {"target": current_cell, "kind": "invalid", "wait_reason": "NO_ACTIVE_PLAN", "assignment_epoch": 0}
	if move_plan == null or plan == null or not plan.member_slot_map.has(member_id):
		return invalid
	var epoch: int = int(move_plan.member_assignment_epoch.get(member_id, 0)) + int(move_plan.member_soft_assignment_epoch.get(member_id, 0)) + plan.assignment_epoch
	var final_slot: Vector2i = plan.get_slot_for_member(member_id)
	if move_plan.member_crossed_swap_hold.has(member_id):
		return {"target": current_cell, "kind": "crossed_swap_hold", "wait_reason": "TARGET_EXCHANGE_WAIT", "assignment_epoch": epoch}
	if move_plan.member_vacancy_chain_target.has(member_id):
		return {"target": final_slot, "kind": "vacancy_chain", "wait_reason": "", "assignment_epoch": epoch}
	if move_plan.member_recovery_hold.has(member_id):
		return {"target": current_cell, "kind": "recovery_hold", "wait_reason": "VACANCY_CHAIN_WAIT", "assignment_epoch": epoch}
	# A former entrant that detoured outside the footprint still owns its final.
	# This must win over any stale entry waypoint from before the detour.
	if plan.is_platform_member(member_id) and plan.ever_admitted_platform_member_ids.has(member_id) and not plan.platform_footprint.has(current_cell):
		return {"target": final_slot, "kind": "platform_return", "wait_reason": "", "assignment_epoch": epoch}
	if move_plan.member_entry_waypoint.has(member_id):
		return {"target": move_plan.member_entry_waypoint[member_id], "kind": "entry_waypoint", "wait_reason": "KEEP_INGRESS_OPEN", "assignment_epoch": epoch}
	if current_cell == final_slot:
		return {"target": final_slot, "kind": "settled", "wait_reason": "", "assignment_epoch": epoch}
	# Admission is the handoff from shared transit to individual deployment.
	# A soldier already inside the footprint must not keep chasing a stale
	# macro-route soft target while the rest of the platform is filling.
	if plan.is_platform_member(member_id) and plan.admitted_platform_member_ids.has(member_id) and plan.platform_footprint.has(current_cell):
		return {"target": final_slot, "kind": "platform", "wait_reason": "", "assignment_epoch": epoch}
	# The broad-footprint staging waypoint is only an approach aid. Once a
	# soldier is beside its own final cell, do not send it back to the handoff.
	if plan.is_platform_member(member_id) and plan.platform_footprint.has(current_cell) and absi(current_cell.x - final_slot.x) + absi(current_cell.y - final_slot.y) <= 2:
		return {"target": final_slot, "kind": "platform", "wait_reason": "", "assignment_epoch": epoch}
	if plan.is_platform_member(member_id) and not move_plan.macro_path.is_empty():
		var far_final: bool = absi(final_slot.x - plan.ingress_cell.x) + absi(final_slot.y - plan.ingress_cell.y) > 8
		var broad_destination: bool = plan.platform_footprint.size() >= plan.platform_slots.size() * 2
		if far_final and (not broad_destination or _platform_handoff_cell(plan) == plan.resolved_anchor):
			var handoff: Vector2i = move_plan.macro_path[-1]
			var approach: Vector2i = handoff - plan.ingress_cell
			var stage: Vector2i = handoff + plan.final_facing * 2
			var progress: int = (current_cell.x - handoff.x) * approach.x + (current_cell.y - handoff.y) * approach.y
			var stage_progress: int = (stage.x - handoff.x) * approach.x + (stage.y - handoff.y) * approach.y
			if current_cell in plan.platform_footprint and progress < stage_progress and plan.platform_footprint.has(stage):
				return {"target": stage, "kind": "platform_stage", "wait_reason": "", "assignment_epoch": epoch}
	if move_plan.member_entry_hold.has(member_id):
		return {"target": current_cell, "kind": "ingress_wait", "wait_reason": "SIDE_SLOT_WAIT", "assignment_epoch": epoch}
	var observed_s: float = float(move_plan.member_observed_path_s.get(member_id, -INF))
	var on_ingress_route := current_cell in plan.queue_hold_cross_section or current_cell in plan.ingress_buffer_cells or current_cell in plan.platform_footprint
	# A broad, flat footprint may begin well before its actual final slots. Sending a
	# soldier at a one-cell choke directly to a distant slot makes the bounded local
	# search fail and leaves the entire column motionless. Keep transit waypoints
	# until the macro route reaches its destination-side handoff.
	if on_ingress_route and not move_plan.macro_path.is_empty():
		var final_distance_from_entry: int = absi(final_slot.x - plan.ingress_cell.x) + absi(final_slot.y - plan.ingress_cell.y)
		if final_distance_from_entry > 8:
			var handoff: Vector2i = plan.get_platform_handoff_cell()
			var approach: Vector2i = handoff - plan.ingress_cell
			var passed_handoff: bool = (current_cell.x - handoff.x) * approach.x + (current_cell.y - handoff.y) * approach.y >= 0
			on_ingress_route = current_cell in plan.platform_footprint and passed_handoff and not plan.needs_transit_soft_target(member_id, current_cell)
	if plan.is_platform_member(member_id) and on_ingress_route:
		return {"target": final_slot, "kind": "platform", "wait_reason": "", "assignment_epoch": epoch}
	if plan.is_queue_member(member_id):
		if move_plan.member_queue_egress_waypoint.has(member_id):
			return {"target": move_plan.member_queue_egress_waypoint[member_id], "kind": "queue_egress", "wait_reason": "CLEAR_INGRESS", "assignment_epoch": epoch}
		return {"target": final_slot, "kind": "queue", "wait_reason": "" if plan.queue_released else "QUEUE_HOLD", "assignment_epoch": epoch}
	var soft_slot: Vector2i = move_plan.member_transit_slots.get(member_id, current_cell)
	var target_s: float = float(move_plan.member_path_s.get(member_id, -INF))
	if target_s < observed_s - 0.5 and current_cell in move_plan.macro_path:
		soft_slot = current_cell
	return {"target": soft_slot, "kind": "transit", "wait_reason": "" if soft_slot != current_cell else "FLOW_WAIT", "assignment_epoch": epoch}

## Returns the current target destination for a member based on ingress gate status
static func get_member_current_target(plan: CombatDeploymentPlan, member_id: int) -> Vector2i:
	if plan == null or not plan.member_role_map.has(member_id):
		return Vector2i(-1, -1)

	var role = plan.member_role_map[member_id]
	if role == Types.CombatDestinationRole.PLATFORM:
		return plan.member_slot_map.get(member_id, plan.ingress_cell)

	# APPROACH_QUEUE member
	var fallback_hold: Vector2i = plan.queue_hold_cross_section[0] if not plan.queue_hold_cross_section.is_empty() else plan.ingress_cell
	return plan.member_slot_map.get(member_id, fallback_hold) if plan.queue_released else fallback_hold

## Checks if all members have reached their final assigned deployment slots
static func is_settled(plan: CombatDeploymentPlan, current_cells: Dictionary) -> bool:
	if plan == null:
		return false
	for mid in plan.member_slot_map.keys():
		var assigned: Vector2i = plan.member_slot_map[mid]
		var curr: Vector2i = current_cells.get(mid, Vector2i(-1, -1))
		if curr != assigned:
			return false
	return true
