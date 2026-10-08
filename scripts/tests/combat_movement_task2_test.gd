extends SceneTree
## Unit test suite for Task 2: SiteCombatMovementCoordinator, SiteRouteBudget,
## and 100-formation scheduler fairness.

const Coordinator = preload("res://scripts/terrain_lab/site_combat_movement_coordinator.gd")
const RouteBudget = preload("res://scripts/terrain_lab/site_route_budget.gd")
const Helper = preload("res://scripts/tests/fixtures/combat_movement_test_helper.gd")

class MockFormation:
	extends RefCounted
	var team_id: int
	var stages_called: Array[String] = []
	var coordinator_ref: Object = null
	
	func _init(p_id: int) -> void:
		team_id = p_id
		
	func set_coordinator(c: Object) -> void:
		coordinator_ref = c
		
	func prepare_combat_movement_tick(_delta: float, _route_budget: Object, _deployment_registry: Object) -> void:
		stages_called.append("prepare")
		
	func propose_combat_moves(_reservation_grid: Object) -> void:
		stages_called.append("propose")
		
	func finalize_combat_movement_tick(_delta: float, _reservation_grid: Object, _deployment_registry: Object) -> void:
		stages_called.append("finalize")
		
	func get_active_members_occupancy() -> Dictionary:
		return { team_id * 1000 + 1: Vector2i(team_id, team_id) }

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("--- Running Task 2 Coordinator & RouteBudget Fairness Test ---")
	
	# 1. Pipeline execution order test
	var coord = Coordinator.new()
	var mock1 = MockFormation.new(1)
	var mock2 = MockFormation.new(2)
	coord.register_formation(mock1)
	coord.register_formation(mock2)
	assert(coord.get_active_formations().size() == 2)
	assert(mock1.coordinator_ref == coord)
	assert(mock2.coordinator_ref == coord)
	
	coord.combat_logic_tick(0.1)
	assert(mock1.stages_called == ["prepare", "propose", "finalize"])
	assert(mock2.stages_called == ["prepare", "propose", "finalize"])
	print("TASK 2: 5-stage pipeline order verified")
	
	# 2. 100-formation round-robin fairness test
	var budget = RouteBudget.new()
	var formations_100: Array = []
	for i in range(1, 101):
		formations_100.append(MockFormation.new(i))
		
	# Tick 1: Formations 1..64 should receive base quantum; 65..100 should be deferred
	budget.begin_tick(formations_100)
	var tick1_served: Array[int] = []
	var tick1_deferred: Array[int] = []
	for i in range(1, 101):
		if budget.is_scheduler_deferred(i):
			tick1_deferred.append(i)
		else:
			tick1_served.append(i)
			
	assert(tick1_served.size() == 64, "Tick 1 must serve exactly 64 formations (8192 / 128)")
	assert(tick1_deferred.size() == 36, "Tick 1 must defer 36 formations")
	assert(tick1_served[0] == 1 and tick1_served[63] == 64)
	assert(tick1_deferred[0] == 65 and tick1_deferred[35] == 100)
	
	# Record searches on served formations
	for fid in tick1_served:
		assert(budget.can_search(fid))
		var call_budget := budget.get_call_budget(fid)
		assert(call_budget == 128, "Base quantum expansion must be 128")
		budget.record_search(fid, 128)
		assert(not budget.can_search(fid), "Formation budget should be exhausted after 128 expansions")
		
	assert(budget.site_expansions_used == 64 * 128)
	assert(budget.site_expansions_used <= RouteBudget.SITE_MAX_EXPANSIONS_PER_TICK)
	
	# Tick 2: Formations 65..100 must be served first!
	budget.begin_tick(formations_100)
	var tick2_served: Array[int] = []
	for i in range(1, 101):
		if not budget.is_scheduler_deferred(i):
			tick2_served.append(i)
			
	assert(tick2_served.size() == 64)
	# Check that 65..100 are all in tick2_served!
	for fid in range(65, 101):
		assert(tick2_served.has(fid), "Formation %d was deferred in tick 1 and must be served in tick 2!" % fid)
	print("TASK 2: 100-formation base quantum coverage in <= 2 ticks verified")
	
	# Long-run fairness test over 20 ticks
	var total_served_counts: Dictionary = {}
	for i in range(1, 101):
		total_served_counts[i] = 0
		
	for tick in range(20):
		budget.begin_tick(formations_100)
		for i in range(1, 101):
			if not budget.is_scheduler_deferred(i):
				total_served_counts[i] = int(total_served_counts[i]) + 1
				
	# In 20 ticks with 64 served per tick = 1280 total slots across 100 formations
	# Average per formation is 12.8, so every formation should be served either 12 or 13 times!
	var min_served := 999
	var max_served := 0
	for i in range(1, 101):
		var count: int = int(total_served_counts[i])
		min_served = mini(min_served, count)
		max_served = maxi(max_served, count)
		
	assert(min_served >= 12 and max_served <= 13, "Strict round-robin fairness failed: min=%d max=%d" % [min_served, max_served])
	print("TASK 2: 20-tick strict fairness verified (min=%d, max=%d served)" % [min_served, max_served])
	
	# 3. TerrainArmy integration test
	var map_info = Helper.build_mountain_platform_map()
	var test_data: TerrainData = map_info["data"]
	var real_army = Helper.create_test_army(test_data, 1, 0, 100, Vector2i(5, 5))
	
	var army_coord = Coordinator.new()
	army_coord.register_formation(real_army)
	assert(real_army.get_coordinator() == army_coord)
	
	var occ: Dictionary = real_army.get_active_members_occupancy()
	assert(occ.size() == 100, "Occupancy must report all 100 active members")
	
	army_coord.combat_logic_tick(0.1)
	print("TASK 2: TerrainArmy coordinator integration verified")
	army_coord.unregister_formation(real_army)
	real_army.free()
	coord.unregister_formation(mock1)
	coord.unregister_formation(mock2)
	
	print("TASK 2 COMPLETE: Coordinator, RouteBudget, and Fairness fully operational!")
	quit(0)
