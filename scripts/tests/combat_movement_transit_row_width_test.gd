extends SceneTree

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const Transit = preload("res://scripts/terrain_lab/formation_transit_planner.gd")
const LAB_SCENE = preload("res://scenes/terrain_lab/TerrainLab.tscn")

func _initialize() -> void:
	call_deferred("_run")

func _require(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error(message)
	quit(1)
	return false

func _run_case(bend: bool, crossed_count: int, physical_case: int = 0) -> bool:
	var terrain := Helper.build_flat_map(70, 35)
	var plan := CombatMovePlan.new()
	var first_choke_k := 15
	var after_choke_k := 20
	if bend:
		for x in range(5, 19):
			plan.macro_path.append(Vector2i(x, 10))
		for y in range(11, 19):
			plan.macro_path.append(Vector2i(18, y))
		for x in range(19, 61):
			plan.macro_path.append(Vector2i(x, 18))
		for y in range(12, 16):
			for x in [17, 19]:
				terrain.static_blocked[terrain.index(Vector2i(x, y))] = 1
		plan.macro_cursor = 23
	else:
		for x in range(5, 61):
			plan.macro_path.append(Vector2i(x, 10))
		for x in range(20, 25):
			for y in range(35):
				if y != 10:
					terrain.static_blocked[terrain.index(Vector2i(x, y))] = 1
		plan.macro_cursor = 21
	plan.current_width = 4
	plan.pending_width = 4
	var mids: Array[int] = []
	var cells: Dictionary = {}
	for i in range(10):
		var mid := i + 1
		mids.append(mid)
		var crossed := i < crossed_count
		plan.member_checkpoint_path_k[mid] = after_choke_k if crossed else first_choke_k - 1
		plan.member_observed_path_s[mid] = float(after_choke_k if crossed else first_choke_k - 1)
		cells[mid] = plan.macro_path[after_choke_k] + Vector2i(i, 0) if crossed else Vector2i(12, i + 5)
		if i == 0 and physical_case == 1:
			cells[mid] = plan.macro_path[first_choke_k]
		elif i == 0 and physical_case == 2:
			cells[mid] = Vector2i(17, 11) if bend else Vector2i(19, 11)
	var slots := Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	var label := ("bend" if bend else "straight") + " crossed=" + str(crossed_count) + " physical_case=" + str(physical_case)
	if not _require(slots.size() == mids.size(), label + " every soldier needs a transit slot"): return false
	var used: Dictionary = {}
	var beyond := 0
	var rear_row := 0
	for mid in mids:
		var slot: Vector2i = slots[mid]
		if not _require(not used.has(slot), label + " transit slots must be unique"): return false
		used[slot] = true
		if not _require(terrain.contains(slot) and terrain.is_walkable(slot) and terrain.static_blocked[terrain.index(slot)] == 0, label + " slot must be walkable"): return false
		var assigned_k := floori(float(plan.member_path_s[mid]))
		if assigned_k > first_choke_k:
			beyond += 1
			if not _require(int(plan.member_checkpoint_path_k[mid]) >= first_choke_k or physical_case == 1 and mid == 1, label + " only a physically crossed soldier can target beyond the choke"): return false
		if assigned_k == first_choke_k - 1:
			rear_row += 1
	if not _require(beyond <= crossed_count + (1 if physical_case == 1 else 0), label + " beyond-choke capacity must equal physical crossings"): return false
	if physical_case == 1 and not _require(float(plan.member_path_s[1]) > float(first_choke_k), label + " exact physical path cell must release the stalled entrant"): return false
	if physical_case == 2 and not _require(beyond == 0, label + " adjacent off-path cell is not crossing proof"): return false
	if crossed_count == 3 and not _require(rear_row >= 3, label + " open ground behind the choke must use a wide row"): return false
	if crossed_count == 3 and physical_case == 0:
		var first_slots := slots.duplicate()
		var first_epochs := plan.member_soft_assignment_epoch.duplicate()
		plan.macro_cursor += 1
		for mid in mids:
			plan.member_observed_path_s[mid] = float(plan.member_observed_path_s[mid]) - 0.25
		var shifted := Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
		var shifted_used: Dictionary = {}
		for mid in mids:
			var shifted_slot: Vector2i = shifted[mid]
			if not _require(not shifted_used.has(shifted_slot), label + " shifted frontier keeps unique slots"): return false
			shifted_used[shifted_slot] = true
			if not _require(terrain.contains(shifted_slot) and terrain.is_walkable(shifted_slot) and terrain.static_blocked[terrain.index(shifted_slot)] == 0, label + " shifted slot stays legal"): return false
			if floori(float(plan.member_path_s[mid])) > first_choke_k and not _require(int(plan.member_checkpoint_path_k[mid]) >= first_choke_k, label + " shifted frontier cannot send an uncrossed soldier beyond gate"): return false
		if not _require(shifted.size() == mids.size(), label + " keeps full legal gate throughput despite prior soft slots"): return false
		var shifted_s := plan.member_path_s.duplicate()
		var shifted_lanes := plan.member_lane_map.duplicate()
		var shifted_ranks := plan.member_sequence_rank.duplicate()
		var held_rear := 0
		for mid in mids:
			if floori(float(shifted_s[mid])) <= first_choke_k - 2 and shifted[mid] == first_slots[mid] and int(plan.member_soft_assignment_epoch[mid]) == int(first_epochs.get(mid, -1)):
				held_rear += 1
		if not _require(held_rear > 0, label + " stationary wide-row rear needs stable target and epoch while a choke is active"): return false
		plan.set_meta("_transit_soft_key", [])
		var baseline := Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
		for mid in mids:
			var gated_shifted := floori(float(shifted_s[mid])) >= first_choke_k - 1 and floori(float(shifted_s[mid])) <= after_choke_k
			var gated_baseline := floori(float(plan.member_path_s[mid])) >= first_choke_k - 1 and floori(float(plan.member_path_s[mid])) <= after_choke_k
			if gated_shifted or gated_baseline:
				if not _require(shifted[mid] == baseline[mid] and float(shifted_s[mid]) == float(plan.member_path_s[mid]) and int(shifted_lanes[mid]) == int(plan.member_lane_map[mid]) and int(shifted_ranks[mid]) == int(plan.member_sequence_rank[mid]), label + " gate, adjacent rows, and member order must match zipper without inertia"): return false
	print("TRANSIT ROW WIDTH ", label, " beyond=", beyond, " rear_row=", rear_row)
	return true

func _run_admitted_case() -> bool:
	var terrain := Helper.build_flat_map(70, 35)
	for x in range(20, 25):
		for y in range(35):
			if y != 10:
				terrain.static_blocked[terrain.index(Vector2i(x, y))] = 1
	var plan := CombatMovePlan.new()
	for x in range(5, 61):
		plan.macro_path.append(Vector2i(x, 10))
	plan.macro_cursor = 21
	plan.current_width = 4
	plan.pending_width = 4
	plan.destination_plan = CombatDeploymentPlan.new()
	var mids: Array[int] = []
	var cells: Dictionary = {}
	for i in range(10):
		var mid := i + 1
		mids.append(mid)
		plan.destination_plan.member_role_map[mid] = CombatMovementTypes.CombatDestinationRole.PLATFORM
		plan.member_checkpoint_path_k[mid] = 20 if i < 3 else 14
		plan.member_observed_path_s[mid] = 20.0 if i < 3 else 14.0
		cells[mid] = Vector2i(30, 9 + i) if i < 3 else Vector2i(18, i + 4)
		if i < 3:
			plan.destination_plan.admitted_platform_member_ids.append(mid)
	var slots := Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	if not _require(slots.size() == 7, "Only seven pending soldiers need transit slots after three admissions"): return false
	var used: Dictionary = {}
	var beyond := 0
	var entry := 0
	for mid in slots.keys():
		var slot: Vector2i = slots[mid]
		if not _require(not used.has(slot), "Admitted case transit slots must be unique"): return false
		used[slot] = true
		if not _require(terrain.contains(slot) and terrain.is_walkable(slot), "Admitted case slot must be walkable"): return false
		for admitted in [1, 2, 3]:
			if not _require(slot != cells[admitted], "Transit slot cannot overlap an admitted soldier"): return false
		if float(plan.member_path_s[mid]) > 15.0:
			beyond += 1
		if floori(float(plan.member_path_s[mid])) == 15:
			entry += 1
	if not _require(beyond == 0 and entry == 1, "Finished admissions must not send uncrossed entrants beyond the narrow entry row"): return false
	if not _require(float(plan.member_path_s[4]) >= float(plan.member_path_s[10]), "Front-ranked pending soldier must retain forward priority"): return false
	print("TRANSIT ROW WIDTH admitted crossed=3 beyond=", beyond, " entry=", entry)
	return true

func _run_admitted_before_handoff_case() -> bool:
	var terrain := Helper.build_flat_map(70, 35)
	for x in range(20, 25):
		for y in range(35):
			if y != 10:
				terrain.static_blocked[terrain.index(Vector2i(x, y))] = 1
	var plan := CombatMovePlan.new()
	for x in range(5, 61):
		plan.macro_path.append(Vector2i(x, 10))
	plan.macro_cursor = 28
	plan.current_width = 4
	plan.pending_width = 4
	plan.destination_plan = CombatDeploymentPlan.new()
	plan.destination_plan.ingress_cell = Vector2i(24, 10)
	plan.destination_plan.resolved_anchor = Vector2i(45, 10)
	var mids: Array[int] = []
	var cells: Dictionary = {}
	for i in range(10):
		var mid := i + 1
		mids.append(mid)
		plan.destination_plan.member_role_map[mid] = CombatMovementTypes.CombatDestinationRole.PLATFORM
		plan.destination_plan.member_slot_map[mid] = Vector2i(50, i + 5)
		var admitted := i < 3
		plan.member_checkpoint_path_k[mid] = 28 if admitted else 14
		plan.member_observed_path_s[mid] = 28.0 if admitted else 14.0
		cells[mid] = Vector2i(33, i + 9) if admitted else Vector2i(18, i + 4)
		if admitted:
			plan.destination_plan.admitted_platform_member_ids.append(mid)
			plan.destination_plan.platform_footprint.append(cells[mid])
	var slots := Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	if not _require(plan.destination_plan.approach_bottlenecked == 1, "Real choke must keep destination handoff at anchor"): return false
	if not _require(slots.size() == 10, "Admitted soldiers before handoff still need transit soft goals"): return false
	var used: Dictionary = {}
	for mid in mids:
		var slot: Vector2i = slots[mid]
		if not _require(not used.has(slot) and terrain.is_walkable(slot), "Handoff transit slots must be unique and legal"): return false
		used[slot] = true
	for mid in [1, 2, 3]:
		if not _require(float(plan.member_path_s[mid]) > 28.0 and slots[mid] != cells[mid], "Admitted front must keep moving until actual handoff"): return false
	print("TRANSIT ROW WIDTH admitted-before-handoff PASS")
	return true

func _run_gate_owner_case() -> bool:
	var terrain := Helper.build_flat_map(70, 35)
	for x in range(25, 32):
		for y in range(35):
			if y != 20:
				terrain.static_blocked[terrain.index(Vector2i(x, y))] = 1
	var plan := CombatMovePlan.new()
	for x in range(5, 61):
		plan.macro_path.append(Vector2i(x, 20))
	plan.macro_cursor = 30
	plan.current_width = 4
	plan.pending_width = 4
	var center_mid := 1
	var side_mid := 2
	plan.member_checkpoint_path_k[center_mid] = 14
	plan.member_checkpoint_path_k[side_mid] = 20
	plan.member_observed_path_s[center_mid] = 14.0
	plan.member_observed_path_s[side_mid] = 20.0
	var cells := {center_mid: Vector2i(24, 20), side_mid: Vector2i(24, 21)}
	var mids: Array[int] = [center_mid, side_mid]
	var slots := Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	if not _require(slots.size() == 2, "Both entrance soldiers need unique soft slots"): return false
	if not _require(slots[center_mid] == Vector2i(25, 20), "Centerline predecessor must own the single legal gate step"): return false
	if not _require(slots[side_mid] != Vector2i(25, 20) and float(plan.member_path_s[side_mid]) <= 19.0, "Blocked side soldier cannot reserve the gate or a post-gate row"): return false
	plan.member_transit_slots[side_mid] = Vector2i(25, 20)
	plan.set_meta("_transit_soft_key", [plan.path_epoch, plan.terrain_revision, 0])
	var next_slots := Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	if not _require(next_slots[center_mid] == Vector2i(25, 20) and next_slots[side_mid] != Vector2i(25, 20), "An old soft reservation cannot steal a live one-cell gate from its physical predecessor"): return false
	print("TRANSIT ROW WIDTH GATE OWNER PASS")
	return true

func _run_equal_checkpoint_queue_case() -> bool:
	var terrain := Helper.build_flat_map(70, 35)
	for x in range(20, 25):
		for y in range(35):
			if y != 10:
				terrain.static_blocked[terrain.index(Vector2i(x, y))] = 1
	var plan := CombatMovePlan.new()
	for x in range(5, 61):
		plan.macro_path.append(Vector2i(x, 10))
	plan.macro_cursor = 21
	plan.current_width = 4
	plan.pending_width = 4
	var mids: Array[int] = [1, 2]
	var cells := {1: Vector2i(18, 9), 2: Vector2i(18, 11)}
	for mid in mids:
		plan.member_checkpoint_path_k[mid] = 13
	plan.member_observed_path_s[1] = 13.25
	plan.member_observed_path_s[2] = 13.0
	var first := Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	var first_s := plan.member_path_s.duplicate()
	var first_epoch := plan.member_soft_assignment_epoch.duplicate()
	if not _require(first[1] != first[2], "Equal-checkpoint gate queue needs unique legal slots"): return false
	plan.member_observed_path_s[1] = 12.75
	plan.member_observed_path_s[2] = 13.5
	var jittered := Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	for mid in mids:
		if not _require(jittered[mid] == first[mid] and float(plan.member_path_s[mid]) == float(first_s[mid]) and int(plan.member_soft_assignment_epoch[mid]) == int(first_epoch[mid]), "Projection jitter at equal physical checkpoint must not swap established gate queue targets"): return false
	print("TRANSIT EQUAL CHECKPOINT QUEUE PASS")
	return true

func _run_moving_wide_behind_gate_case() -> bool:
	var terrain := Helper.build_flat_map(70, 35)
	for x in range(20, 25):
		for y in range(35):
			if y != 10:
				terrain.static_blocked[terrain.index(Vector2i(x, y))] = 1
	var plan := CombatMovePlan.new()
	for x in range(5, 61):
		plan.macro_path.append(Vector2i(x, 10))
	plan.macro_cursor = 21
	plan.current_width = 4
	plan.pending_width = 4
	var mids: Array[int] = [1, 2, 3, 4, 5, 6]
	var cells := {1: Vector2i(19, 10), 2: Vector2i(17, 5), 3: Vector2i(17, 6),
		4: Vector2i(17, 7), 5: Vector2i(17, 12), 6: Vector2i(16, 8)}
	for mid in mids:
		plan.member_checkpoint_path_k[mid] = 14 if mid == 1 else (0 if mid == 6 else 13)
		plan.member_observed_path_s[mid] = float(plan.member_checkpoint_path_k[mid])
	var first := Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	if not _require(first.size() == mids.size() and floori(float(plan.member_path_s[6])) <= 13, "Moving rear fixture must place all members and rear soldier in a wide pre-gate row"): return false
	var first_gate: Vector2i = first[1]
	var rear_k := floori(float(plan.member_path_s[6]))
	var rows: Array = Transit._get_static_row_sections(plan, terrain, null)
	var alternative := Vector2i(-1, -1)
	for slot: Vector2i in rows[rear_k]:
		if slot != first[6] and not first.values().has(slot):
			alternative = slot
			break
	if not _require(alternative != Vector2i(-1, -1), "Moving rear fixture needs a spare legal same-row candidate"): return false
	plan.member_transit_slots[6] = alternative
	cells[6] = Vector2i(17, 8)
	if not _require(terrain.can_step_static(Vector2i(16, 8), cells[6], null), "Moving rear fixture physical step must be legal"): return false
	var moved := Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	if not _require(moved[1] == first_gate, "Rear wide-section inertia must not change gate ownership"): return false
	if not _require(moved[6] == alternative and floori(float(plan.member_path_s[6])) == rear_k, "One legal rear physical step retains a still-legal target in its same wide row"): return false
	print("TRANSIT MOVING WIDE BEHIND GATE PASS")
	return true

func _run_moving_wide_row_advance_case() -> bool:
	var terrain := Helper.build_flat_map(70, 35)
	for x in range(20, 25):
		for y in range(35):
			if y != 10:
				terrain.static_blocked[terrain.index(Vector2i(x, y))] = 1
	var plan := CombatMovePlan.new()
	for x in range(5, 61):
		plan.macro_path.append(Vector2i(x, 10))
	plan.macro_cursor = 21
	plan.current_width = 4
	plan.pending_width = 4
	var mids: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
	var cells := {1: Vector2i(19, 10), 2: Vector2i(17, 5), 3: Vector2i(17, 6),
		4: Vector2i(17, 7), 5: Vector2i(17, 12), 6: Vector2i(17, 13),
		7: Vector2i(16, 6), 8: Vector2i(16, 7), 9: Vector2i(16, 9), 10: Vector2i(16, 8)}
	for mid in mids:
		plan.member_checkpoint_path_k[mid] = 14 if mid == 1 else (0 if mid == 10 else 13)
		plan.member_observed_path_s[mid] = float(plan.member_checkpoint_path_k[mid])
	var first := Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	if not _require(first.size() == mids.size() and floori(float(plan.member_path_s[10])) <= 12, "Rear moving member starts at least two wide rows behind the gate"): return false
	var first_gate: Vector2i = first[1]
	var rear_k := floori(float(plan.member_path_s[10]))
	var rows: Array = Transit._get_static_row_sections(plan, terrain, null)
	var prior_target: Vector2i = first[10]
	if not _require(rows[rear_k].has(prior_target), "Rear member starts with a legal target in its wide row"): return false
	mids.erase(8)
	mids.erase(9)
	cells[10] = Vector2i(17, 8)
	if not _require(terrain.can_step_static(Vector2i(16, 8), cells[10], null), "Rear member physical step is legal"): return false
	var moved := Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	if not _require(moved[1] == first_gate, "A rear wide target cannot steal the physical gate owner"): return false
	if not _require(moved[10] == prior_target and floori(float(plan.member_path_s[10])) == rear_k, "Moving rear member retains a legal target across wide rows"): return false
	plan.set_meta("_transit_soft_key", [])
	var fresh := Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	if not _require(fresh[10] != prior_target and floori(float(plan.member_path_s[10])) > rear_k, "Without inertia the smaller queue advances rear default row"): return false
	print("TRANSIT MOVING WIDE ROW ADVANCE PASS")
	return true

func _run_row_cache_case() -> bool:
	var terrain := Helper.build_flat_map(32, 15)
	var plan := CombatMovePlan.new()
	for x in range(4, 25):
		plan.macro_path.append(Vector2i(x, 7))
	plan.terrain_revision = terrain.navigation_revision
	var profile := FormationMovementProfile.default_infantry()
	for y in range(15):
		if y != 7:
			terrain.height_levels[terrain.index(Vector2i(15, y))] = 1
	var ramp_center := terrain.index(Vector2i(15, 7))
	var ramp_above := terrain.index(Vector2i(15, 6))
	var ramp_below := terrain.index(Vector2i(15, 8))
	terrain.ramp_edges[ramp_center] = (1 << 0) | (1 << 2)
	terrain.ramp_edges[ramp_above] = 1 << 2
	terrain.ramp_edges[ramp_below] = 1 << 0
	var open_rows: Array = Transit._get_static_row_sections(plan, terrain, profile)
	for k in range(plan.macro_path.size()):
		if not _require(open_rows[k] == Transit._get_row_cross_section(plan, k, terrain, profile, 4), "Cached open row must exactly match uncached legal candidates"): return false
	if not _require(open_rows[6].size() == 4, "Before terrain change, row x10 must be four wide"): return false
	for x in range(10, 13):
		for y in range(15):
			if y != 7:
				terrain.static_blocked[terrain.index(Vector2i(x, y))] = 1
	terrain.navigation_revision += 1
	plan.terrain_revision = terrain.navigation_revision
	var narrow_rows: Array = Transit._get_static_row_sections(plan, terrain, profile)
	if not _require(narrow_rows[6].size() == 1, "Terrain revision must invalidate cached row width"): return false
	for k in range(plan.macro_path.size()):
		if not _require(narrow_rows[k] == Transit._get_row_cross_section(plan, k, terrain, profile, 4), "Revised rows must match uncached legal candidates"): return false
	profile.set("max_step_height", 0)
	profile.call("recompute_hash")
	var restricted_rows: Array = Transit._get_static_row_sections(plan, terrain, profile)
	if not _require(restricted_rows[11].size() == 1 and narrow_rows[11].size() == 4, "Profile hash change must invalidate cached height reach"): return false
	print("TRANSIT ROW CACHE EQUIVALENCE PASS")
	return true

func _run_soft_inertia_case() -> bool:
	var terrain := Helper.build_flat_map(45, 21)
	var plan := CombatMovePlan.new()
	for x in range(4, 41):
		plan.macro_path.append(Vector2i(x, 10))
	plan.macro_cursor = 20
	plan.terrain_revision = terrain.navigation_revision
	var mids: Array[int] = [1]
	var cells := {1: Vector2i(9, 10)}
	plan.member_checkpoint_path_k[1] = 5
	plan.member_observed_path_s[1] = 5.0
	var first := Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	var old_slot: Vector2i = first[1]
	if not _require(old_slot.y == 10, "A partially filled open row defaults to its center cell"): return false
	var old_epoch: int = int(plan.member_soft_assignment_epoch[1])
	plan.macro_cursor += 1
	plan.member_observed_path_s[1] = 4.75
	var held := Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	if not _require(held[1] == old_slot and int(plan.member_soft_assignment_epoch[1]) == old_epoch, "Stationary soldier keeps a legal unfinished soft target through frontier/observed jitter"): return false
	cells[1] = Vector2i(10, 10)
	var moving_open := Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	if not _require(moving_open[1] == old_slot and int(plan.member_soft_assignment_epoch[1]) == old_epoch, "Open route retains its previous legal soft target while a soldier takes a physical step"): return false
	plan.member_route_retry_count[1] = 3
	var retry_released := Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	if not _require(retry_released[1] != old_slot, "Bounded route retries release a retained soft target"): return false
	var retry_slot: Vector2i = retry_released[1]
	plan.path_epoch += 1
	plan.macro_cursor += 1
	var epoch_released := Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	if not _require(epoch_released[1] != retry_slot, "Path epoch invalidates soft-target inertia"): return false
	var epoch_slot: Vector2i = epoch_released[1]
	terrain.navigation_revision += 1
	plan.terrain_revision = terrain.navigation_revision
	plan.macro_cursor += 1
	var terrain_released := Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	if not _require(terrain_released[1] != epoch_slot, "Terrain revision invalidates soft-target inertia"): return false
	var restored := CombatMovePlan.new()
	restored.macro_path = plan.macro_path.duplicate()
	restored.macro_cursor = plan.macro_cursor + 1
	restored.terrain_revision = plan.terrain_revision
	restored.member_checkpoint_path_k[1] = 5
	restored.member_observed_path_s[1] = 5.0
	restored.member_transit_slots[1] = terrain_released[1]
	var fresh := Transit.calculate_transit_slots(restored, terrain, null, mids, cells)
	if not _require(fresh[1] != terrain_released[1], "Restored plan cannot retain a slot without live inertia metadata"): return false
	print("TRANSIT SOFT INERTIA PASS")
	return true

func _run_soft_reject_counter_case() -> bool:
	var capacity_counts := {}
	for stationary in [false, true]:
		for gate in [false, true]:
			Transit._count_capacity_reject(capacity_counts, 0, 1, 3, stationary, gate)
			Transit._count_capacity_reject(capacity_counts, 4, 1, 3, stationary, gate)
			for detail in ["capacity_behind_prefix", "capacity_tail_reservation"]:
				var key: String = detail + ("_stationary" if stationary else "_moving") + ("_gate" if gate else "_open")
				if not _require(int(capacity_counts.get(key, 0)) == 1, "Capacity rejection breakdown must classify each movement and gate state once: " + key): return false
	if not _require(int(capacity_counts.get("capacity_bound", 0)) == 8 \
			and int(capacity_counts.get("capacity_behind_prefix", 0)) == 4 \
			and int(capacity_counts.get("capacity_tail_reservation", 0)) == 4,
			"Capacity diagnostics preserve the aggregate and reason totals"): return false
	var terrain := Helper.build_flat_map(45, 21)
	var plan := CombatMovePlan.new()
	for x in range(4, 41):
		plan.macro_path.append(Vector2i(x, 10))
	plan.macro_cursor = 20
	plan.terrain_revision = terrain.navigation_revision
	plan.member_checkpoint_path_k[1] = 5
	plan.member_observed_path_s[1] = 5.0
	var mids: Array[int] = [1]
	var cells := {1: Vector2i(9, 10)}
	Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	if not _require(not plan.has_meta("_transit_soft_reject_counts"), "Transit rejection counters stay disabled by default"): return false
	plan.set_meta("_transit_soft_debug_enabled", true)
	plan.member_transit_slots[1] = Vector2i(0, 0)
	plan.macro_cursor += 1
	Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	var counts: Dictionary = plan.get_meta("_transit_soft_reject_counts", {})
	if not _require(int(counts.get("old_index_absent", 0)) == 1, "A prior slot outside current candidates counts as old-index absence"): return false
	plan.macro_cursor += 1
	plan.member_route_retry_count[1] = 3
	Transit.calculate_transit_slots(plan, terrain, null, mids, cells)
	counts = plan.get_meta("_transit_soft_reject_counts", {})
	if not _require(int(counts.get("retry_defer", 0)) == 1 and int(counts.get("old_index_absent", 0)) == 1, "A bounded retry counts once without double-counting old-index absence"): return false
	print("TRANSIT SOFT REJECT COUNTERS PASS")
	return true

func _run_formal_width_profile() -> bool:
	# Construct the actual formal order, then inspect its accepted path without
	# advancing a simulation tick. A direct map route can differ from Army's.
	var lab := LAB_SCENE.instantiate() as TerrainLab
	lab.pause_when_unfocused = false
	root.add_child(lab)
	current_scene = lab
	lab.set_process(false)
	lab.site_controller.set_process(false)
	for actor: TerrainTestCharacter in lab.combat_actors:
		actor.set_process(false)
	for team: TerrainArmy in lab.combat_armies:
		team.set_process(false)
	var terrain := TerrainGenerator.generate(TerrainPreset.Kind.TERRACED_HIGHLAND, 12345)
	SiteEnvironment.initialize(terrain, "transit-formal-width-probe")
	lab.bind_terrain(terrain)
	var layout: Dictionary = lab.find_melee_trial_layout(100, 100)
	if not _require(not layout.is_empty(), "Width probe needs the formal default 100-person layout"): return false
	var friendly_cells: Array[Vector2i] = layout.friendly
	if not _require(friendly_cells[0] == Vector2i(81, 1), "Width probe friendly deployment changed from formal fixture"): return false
	var config := {"friendly_count": 100, "enemy_count": 100, "friendly_attack": false,
		"enemy_attack": false, "enemy_role": "logistics", "friendly_spawn": friendly_cells[0],
		"enemy_spawn": Vector2i(24, 90)}
	var trial: Dictionary = lab.start_melee_trial(config)
	if not _require(bool(trial.get("ok", false)), "Width probe could not start the formal trial"): return false
	var army: TerrainArmy = lab.army
	var order: Dictionary = army.issue_combat_order(army.current_commander, TerrainArmy.CombatOrder.MOVE, Vector2i(49, 37), -1, Vector2i.UP)
	if not _require(bool(order.get("ok", false)), "Width probe could not issue the formal MOVE"): return false
	var profile: FormationMovementProfile = army.get_formation_movement_profile()
	var path: Array[Vector2i] = army.get_active_move_plan().macro_path
	print("TRANSIT FORMAL PROBE ROUTE size=", path.size(), " first=", path.slice(0, mini(12, path.size())), " last=", path.slice(maxi(0, path.size() - 12)), " profile=", profile.profile_hash, "/", profile.max_step_height, "/", profile.can_use_ramp)
	if not _require(path.size() == 372, "Width probe must use the same 372-cell formal mountain route"): return false
	var move_plan := CombatMovePlan.new()
	move_plan.macro_path = path
	move_plan.terrain_revision = terrain.navigation_revision
	var rows: Array = Transit._get_static_row_sections(move_plan, terrain, profile)
	var early_runs: Array[String] = []
	var late_runs: Array[String] = []
	var start_k := 0
	var previous_width: int = rows[0].size()
	for k in range(1, rows.size() + 1):
		var current_width: int = rows[k].size() if k < rows.size() else -1
		if current_width != previous_width:
			if start_k <= 170:
				early_runs.append("%d-%d:%d" % [start_k, k - 1, previous_width])
			if k >= 170 and start_k <= 270:
				late_runs.append("%d-%d:%d" % [start_k, k - 1, previous_width])
			start_k = k
			previous_width = current_width
	print("TRANSIT FORMAL WIDTH PROFILE k0-170 ", early_runs)
	print("TRANSIT FORMAL WIDTH PROFILE k170-270 ", late_runs)
	lab.clear_army()
	lab.queue_free()
	return true

func _run() -> void:
	for bend in [false, true]:
		for crossed_count in [0, 1, 3]:
			if not _run_case(bend, crossed_count):
				return
		if not _run_case(bend, 0, 1) or not _run_case(bend, 0, 2):
			return
	if not _run_admitted_case():
		return
	if not _run_admitted_before_handoff_case():
		return
	if not _run_gate_owner_case():
		return
	if not _run_equal_checkpoint_queue_case():
		return
	if not _run_moving_wide_behind_gate_case():
		return
	if not _run_moving_wide_row_advance_case():
		return
	if not _run_row_cache_case():
		return
	if not _run_soft_inertia_case():
		return
	if not _run_soft_reject_counter_case():
		return
	if not _run_formal_width_profile():
		return
	print("COMBAT MOVEMENT TRANSIT ROW WIDTH PASS")
	quit(0)
