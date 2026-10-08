extends SceneTree

const SimulationType = preload("res://scripts/benchmark/3d_crowd/battle_crowd_simulation.gd")
const PolicyType = preload("res://scripts/benchmark/3d_crowd/crowd_promotion_policy.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var simulation: BattleCrowdSimulation = SimulationType.new()
	simulation.initialize(123456789)
	simulation.set_active_soldiers(100)
	simulation.soldier_alive.fill(0)
	simulation.soldier_alive[0] = 1
	simulation.soldier_alive[1] = 1
	simulation.formations[0].center_position = Vector3.ZERO
	# The lower ID is slightly farther. An approximate tie followed by an exact
	# distance comparison used to replace these two candidates forever.
	simulation.soldier_world_positions[0] = Vector3(sqrt(2025.005), 0.0, 0.0)
	simulation.soldier_world_positions[1] = Vector3(45.0, 0.0, 0.0)
	var farther_distance: float = simulation.soldier_world_positions[0].length_squared()
	var nearer_distance: float = simulation.soldier_world_positions[1].length_squared()
	if farther_distance <= nearer_distance or farther_distance - nearer_distance >= 0.01:
		_fail("Regression fixture did not retain close but strictly ordered float32 distances")
		return
	var policy: CrowdPromotionPolicy = PolicyType.new()
	policy.promote_distance = 46.0
	policy.prepare(simulation, 1)
	var selected: PackedInt32Array = policy.resolve(simulation, Vector3.ZERO, PackedInt32Array([1]))
	if selected.size() != 1 or selected[0] != 1:
		_fail("Nearer higher-ID incumbent was replaced by a farther lower-ID candidate")
		return
	for iteration: int in range(32):
		selected = policy.resolve(simulation, Vector3.ZERO, selected)
		if selected.size() != 1 or selected[0] != 1:
			_fail("Near slot oscillated at iteration %d" % iteration)
			return
	selected = policy.resolve(simulation, Vector3.ZERO, PackedInt32Array([0]))
	if selected.size() != 1 or selected[0] != 1:
		_fail("A nearer candidate failed to replace the farther incumbent")
		return
	print("CROWD_PROMOTION_NEAR_TIE_PASS farther_d2=%.6f nearer_d2=%.6f selected=%d repeats=32" % [
		farther_distance, nearer_distance, selected[0]
	])
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	print("CROWD_PROMOTION_NEAR_TIE_FAIL " + message)
	quit(1)
