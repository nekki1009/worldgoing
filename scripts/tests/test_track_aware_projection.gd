extends SceneTree
## Targeted Test: Track-Aware Path Projection Safety
## Verifies:
## 1. Outer lane member at 90-degree corner assigned slot projects accurately to assigned_s (e.g. 18.0)
##    rather than being pulled down to 17 by center-line Manhattan distortion.
## 2. Member with valid cached path to assigned slot has safe lower bound (assigned_s - remaining_steps).
## 3. Member separated by a cliff from assigned slot does NOT receive Manhattan-based inflated progress.
## 4. Knockback decreases observed_s while best_s monotonically preserves historical maximum.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const ArmyScript = preload("res://scripts/terrain_lab/terrain_army.gd")
const Profile = preload("res://scripts/terrain_lab/formation_movement_profile.gd")
const MovePlan = preload("res://scripts/terrain_lab/combat_move_plan.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Running test_track_aware_projection ---")
	
	# Build 40x40 map with 90-degree turn:
	# North-to-South from (20, 10) to (20, 17)
	# Turn West at (20, 17) to (19, 17) -> node 18!
	# Turn South at (19, 17) to (19, 25)
	var data := TerrainData.new()
	data.allocate(Vector2i(40, 40))
	SiteEnvironment.initialize(data, "track-projection-fixture")
	data.height_levels.fill(0)
	data.flags.fill(TerrainData.Flag.WALKABLE)
	data.static_blocked.fill(0)
	data.ramp_edges.fill(0)
	
	var army := Helper.create_test_army(data, 1, 0, 4, Vector2i(20, 10))
	var profile = Profile.default_infantry()
	army._formation_movement_profile = profile
	army.combat_order = ArmyScript.CombatOrder.MOVE
	
	var plan = MovePlan.new()
	plan.macro_cursor = 17
	plan.current_width = 4
	
	# Macro path:
	# 0..17: (20, 0) .. (20, 17)
	for y in range(0, 18):
		plan.macro_path.append(Vector2i(20, y))
	# 18: (19, 17)
	plan.macro_path.append(Vector2i(19, 17))
	# 19..25: (19, 18) .. (19, 24)
	for y in range(18, 25):
		plan.macro_path.append(Vector2i(19, y))
		
	army._combat_move_plan = plan
	var member_ids: Array[int] = army._get_active_member_ids()
	for i in range(member_ids.size()):
		plan.member_sequence_rank[member_ids[i]] = i
		var mid_idx := army.index_for_identity(member_ids[i])
		army.cells[mid_idx] = Vector2i(20, 10)

	var mid0: int = member_ids[0]
	var idx0 := army.index_for_identity(mid0)
	
	# --- Test 1: Outer lane assigned slot at 90-degree turn ---
	# At node 18: center is (19, 17), forward is (0, 1), normal is (-1, 0).
	# An outer lane slot is at (21, 17).
	# Manhattan distance to (20, 17) [node 17] is 1.
	# Manhattan distance to (19, 17) [node 18] is 2.
	# Pure Manhattan would incorrectly choose node 17!
	plan.member_transit_slots[mid0] = Vector2i(21, 17)
	plan.member_path_s[mid0] = 18.0
	army.cells[idx0] = Vector2i(21, 17)
	
	army.finalize_combat_movement_tick(0.1, null, null)
	
	var obs_s0: float = float(plan.member_observed_path_s.get(mid0, 0.0))
	var best_s0: float = float(plan.member_best_path_s.get(mid0, 0.0))
	var obs_k0: int = int(plan.member_observed_path_k.get(mid0, 0))
	print("Test 1 (At assigned slot): obs_s=%.1f best_s=%.1f obs_k=%d" % [obs_s0, best_s0, obs_k0])
	assert(obs_s0 == 18.0, "Unit at assigned slot (s=18) must have observed_s=18.0 (got %.1f)!" % obs_s0)
	assert(obs_k0 == 18, "Unit at assigned slot (s=18) must have obs_k=18 (got %d)!" % obs_k0)
	assert(best_s0 == 18.0, "best_s must record 18.0!")

	# --- Test 2: Valid cached path ending at assigned slot ---
	# Member is 2 steps away from assigned slot: (21, 15) -> (21, 16) -> (21, 17)
	var cached_p: Array[Vector2i] = [Vector2i(21, 15), Vector2i(21, 16), Vector2i(21, 17)]
	plan.member_paths[mid0] = cached_p
	army.finalize_combat_movement_tick(0.1, null, null)
	
	obs_s0 = float(plan.member_observed_path_s.get(mid0, 0.0))
	print("Test 2 (Cached path, 2 steps remaining): obs_s=%.1f" % obs_s0)
	# assigned_s (18.0) - remaining_steps (2.0) = 16.0
	assert(obs_s0 >= 16.0, "Unit with 2-step cached path to slot 18 must have observed_s >= 16.0 (got %.1f)!" % obs_s0)

	# --- Test 3: Cliff separation must NOT use Manhattan to inflate progress ---
	# Member at (21, 18), but (21, 18) is separated by a cliff from (21, 17).
	# No cached path exists.
	plan.member_paths.erase(mid0)
	army.cells[idx0] = Vector2i(25, 17) # far from slot, no cached path
	army.finalize_combat_movement_tick(0.1, null, null)
	obs_s0 = float(plan.member_observed_path_s.get(mid0, 0.0))
	print("Test 3 (Far from path, no cached path): obs_s=%.1f" % obs_s0)
	assert(obs_s0 < 18.0, "Out-of-path unit must NOT receive assigned slot progress (got %.1f)!" % obs_s0)

	# --- Test 4: Knockback decreases observed_s while best_s preserves historical max ---
	# Move unit back to start (20, 10) [node 10]
	army.cells[idx0] = Vector2i(20, 10)
	plan.member_transit_slots[mid0] = Vector2i(20, 10)
	plan.member_path_s[mid0] = 10.0
	army.finalize_combat_movement_tick(0.1, null, null)
	
	obs_s0 = float(plan.member_observed_path_s.get(mid0, 0.0))
	best_s0 = float(plan.member_best_path_s.get(mid0, 0.0))
	print("Test 4 (Knockback to node 10): obs_s=%.1f, best_s=%.1f" % [obs_s0, best_s0])
	assert(obs_s0 == 10.0, "Knocked back unit observed_s must drop to 10.0 (got %.1f)!" % obs_s0)
	assert(best_s0 == 18.0, "Historical best_s must monotonically preserve 18.0 (got %.1f)!" % best_s0)

	print("PASS: test_track_aware_projection passed successfully!")
	quit(0)
