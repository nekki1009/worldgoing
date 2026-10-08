extends SceneTree
## Test B: Egress contiguous prefix scan & static BFS distance field ranking
## Verifies that:
## 1. Hairpin curves passing near the camp do not teleport exit_k forward.
## 2. Distance field ranking accounts for cliffs and traversability instead of Manhattan distance.

const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")
const ArmyScript = preload("res://scripts/terrain_lab/terrain_army.gd")
const Profile = preload("res://scripts/terrain_lab/formation_movement_profile.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Running Test B: Contiguous Egress & Topological Distance Field Test ---")
	
	var data := Helper.build_flat_map(50, 50)
	var army = ArmyScript.new()
	army.data = data
	army._formation_movement_profile = Profile.default_infantry()
	
	# 1. Hairpin Macro Path
	# Starts at (10, 10), moves right to (15, 10) [nodes 0..5]
	# Then loops far away and curves back to (10, 8) at node 30 [near camp (10, 9)]
	var macro_path: Array[Vector2i] = []
	for x in range(10, 16):
		macro_path.append(Vector2i(x, 10)) # nodes 0..5
	for y in range(11, 25):
		macro_path.append(Vector2i(15, y)) # nodes 6..19
	for x in range(14, 9, -1):
		macro_path.append(Vector2i(x, 24)) # nodes 20..24
	for y in range(23, 7, -1):
		macro_path.append(Vector2i(10, y)) # nodes 25..40, reaches (10, 8) at node 40
		
	# Camp occupancy at (10, 9) and (9, 9)
	var occ: Dictionary = {
		1: Vector2i(10, 9),
		2: Vector2i(9, 9)
	}
	
	# Node 0 (10, 10) is adjacent to (10, 9)
	# Node 40 (10, 8) is also adjacent to (10, 9)!
	var exit_k: int = army._find_contiguous_egress_cursor(macro_path, occ)
	print("Calculated exit_k with hairpin: %d (node cell=%s)" % [exit_k, str(macro_path[exit_k])])
	assert(exit_k <= 2, "exit_k must remain at the contiguous camp exit (node <= 2), not jump to hairpin curve node 40!")
	
	# 2. Cliff-separated ranking test
	# Place a height 3 cliff between (8, 9) and (9, 9)
	# Unit 1 is at (9, 9), distance 1 to exit node (10, 9)
	# Unit 2 is at (8, 9), Manhattan distance to (10, 9) is 2, but has cliff height 3!
	var idx_cliff := data.index(Vector2i(8, 9))
	data.height_levels[idx_cliff] = 3
	
	var dist_field: Dictionary = army._build_egress_distance_field(macro_path, exit_k, army._formation_movement_profile)
	var cost_unit1: int = int(dist_field.get(Vector2i(9, 9), 999999))
	var cost_unit2: int = int(dist_field.get(Vector2i(8, 9), 999999))
	
	print("Unit 1 (flat) cost: %d, Unit 2 (behind cliff) cost: %d" % [cost_unit1, cost_unit2])
	assert(cost_unit1 < cost_unit2, "Flat-ground unit must have lower BFS cost than unit behind cliff")
	assert(cost_unit2 == 999999 or cost_unit2 > 10, "Unit behind height 3 cliff must not receive direct cliff-crossing distance")
	
	# 3. Distant outlier test: member 3 is far ahead at (15, 20)
	var occ_with_outlier: Dictionary = {
		1: Vector2i(10, 9),
		2: Vector2i(9, 9),
		3: Vector2i(15, 20) # Outlier on path loop
	}
	var exit_k_outlier: int = army._find_contiguous_egress_cursor(macro_path, occ_with_outlier)
	print("Calculated exit_k with outlier: %d" % exit_k_outlier)
	assert(exit_k_outlier <= 2, "Distant outlier member must NOT extend egress exit_k!")
	
	# 4. Asymmetric directional can_step test:
	# Verifies distance field checks can_step(neighbor, current) [member -> egress]
	# and NOT can_step(current, neighbor) [egress -> member]
	var dir_army = ArmyScript.new()
	var mock_terrain = RefCounted.new()
	# Create script with custom can_step
	var mock_script = GDScript.new()
	mock_script.source_code = """
extends "res://scripts/terrain_lab/terrain_data.gd"
func _init():
	allocate(Vector2i(50, 50))
	flags.fill(1) # WALKABLE
func index(c: Vector2i) -> int:
	return c.y * 50 + c.x
func contains(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < 50 and c.y < 50
func is_walkable(c: Vector2i) -> bool:
	return contains(c)
func can_step(from: Vector2i, to: Vector2i) -> bool:
	# One-way ramp: can ONLY step from (10, 11) to (10, 10), cannot step from (10, 10) to (10, 11)
	if from == Vector2i(10, 11) and to == Vector2i(10, 10):
		return true
	if from == Vector2i(10, 10) and to == Vector2i(10, 11):
		return false
	return true
"""
	mock_script.reload()
	var mock_data = mock_script.new()
	dir_army.data = mock_data
	dir_army._formation_movement_profile = army._formation_movement_profile
	
	var dir_dist_field = dir_army._build_egress_distance_field([Vector2i(10, 10)], 0, dir_army._formation_movement_profile)
	assert(dir_dist_field.has(Vector2i(10, 11)), "Distance field MUST reach (10, 11) because member at (10, 11) can step to (10, 10)!")
	print("Verified: reverse can_step(neighbor, current) correctly evaluates member->egress direction!")
	
	# 5. Unequal seed costs test (Dial's Dijkstra vs FIFO BFS):
	# Macro path: k=0 at (20, 20) with seed cost 5; k=5 at (25, 20) with seed cost 0.
	# Query cell Q = (22, 21) is 3 grid steps from k=0 (cost 5 + 3 = 8)
	# and 4 grid steps from k=5 (cost 0 + 4 = 4).
	# A naive FIFO multi-source BFS would visit Q from k=0 first and assign cost 8.
	# Dijkstra/Dial's algorithm must find the true mathematical minimum cost 4.
	var dijkstra_macro_path: Array[Vector2i] = []
	for x in range(20, 26):
		dijkstra_macro_path.append(Vector2i(x, 20))
	var dijkstra_field: Dictionary = army._build_egress_distance_field(dijkstra_macro_path, 5, army._formation_movement_profile)
	var q_cost: int = int(dijkstra_field.get(Vector2i(22, 21), 999999))
	print("Unequal seed cost query cell (22, 21) cost: %d (expected 4, FIFO BFS would give 8)" % q_cost)
	assert(q_cost == 4, "Dijkstra must find true minimal cost (4) rather than FIFO arrival cost (8)!")

	# 6. Dynamic ally occupancy immunity test:
	# Verifies that _build_egress_distance_field relies exclusively on can_step_static,
	# so ally units standing between camp members and the egress do NOT block the distance field.
	var occ_army = ArmyScript.new()
	var occ_script = GDScript.new()
	occ_script.source_code = """
extends "res://scripts/terrain_lab/terrain_data.gd"
var dynamic_occupancy: Dictionary = {}
func _init():
	allocate(Vector2i(50, 50))
	flags.fill(1) # WALKABLE
func index(c: Vector2i) -> int:
	return c.y * 50 + c.x
func contains(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < 50 and c.y < 50
func is_walkable(c: Vector2i) -> bool:
	return contains(c)
func can_step(from: Vector2i, to: Vector2i) -> bool:
	# Standard dynamic can_step blocks if ally occupies either cell
	if dynamic_occupancy.has(from) or dynamic_occupancy.has(to):
		return false
	return true
func can_step_static(from: Vector2i, to: Vector2i, profile: Object = null) -> bool:
	# can_step_static evaluates static terrain only, ignoring dynamic occupancy
	return contains(from) and contains(to)
"""
	occ_script.reload()
	var occ_data = occ_script.new()
	# Place allies blocking (21, 20), (22, 20), (23, 20), (24, 20)
	for x in range(21, 25):
		occ_data.dynamic_occupancy[Vector2i(x, 20)] = true
	occ_army.data = occ_data
	occ_army._formation_movement_profile = army._formation_movement_profile

	var static_dist_field = occ_army._build_egress_distance_field(dijkstra_macro_path, 5, occ_army._formation_movement_profile)
	var q_cost_with_allies: int = int(static_dist_field.get(Vector2i(22, 21), 999999))
	print("Distance field cost at (22, 21) with allies blocking macro path in can_step: %d" % q_cost_with_allies)
	assert(q_cost_with_allies == 4, "can_step_static must bypass dynamic ally occupancy and compute static distance 4!")

	army.free()
	dir_army.free()
	occ_army.free()
	TerrainArmy.release_contact_source()
	print("TEST B PASSED: Egress prefix and topological distance field verified!")
	quit(0)
