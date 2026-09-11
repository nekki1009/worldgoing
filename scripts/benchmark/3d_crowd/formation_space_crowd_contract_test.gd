extends SceneTree

const BatchType = preload("res://scripts/benchmark/3d_crowd/formation_render_batch.gd")
const SimulationType = preload("res://scripts/benchmark/3d_crowd/battle_crowd_simulation.gd")
const PolicyType = preload("res://scripts/benchmark/3d_crowd/crowd_promotion_policy.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var batch: FormationRenderBatch = BatchType.new()
	var mesh := BoxMesh.new()
	var material := StandardMaterial3D.new()
	batch.setup(7, 2, mesh, mesh, mesh, material, material, material, 100)
	get_root().add_child(batch)
	assert(batch.local_slot_cache.size() == 100, "Formation local slot cache must contain 100 slots")
	assert(batch.local_slot_transform_writes == 100, "Formation setup must write static slot transforms once")
	batch.begin_frame()
	assert(batch.set_formation_transform(Vector3(12.0, 0.0, -8.0), 0.5), "Formation transform should update")
	assert(not batch.set_formation_transform(Vector3(12.0, 0.0, -8.0), 0.5), "Unchanged formation transform should be skipped")
	assert(batch.set_slot_active(3, false), "Promotion mask should deactivate a stable local slot")
	assert(not batch.is_slot_active(3), "Promotion mask did not deactivate the slot")
	assert(batch.active_instance_count() == 99, "Inactive slot must not count as a crowd instance")
	assert(not batch.rebuild_local_slots(1.25), "Unchanged spacing should reuse the local slot buffer")
	assert(batch.rebuild_local_slots(1.5), "Changed spacing should rebuild the local slot buffer")
	assert(batch.culling_radius() > 0.0, "Formation culling radius was not compiled")

	var simulation: BattleCrowdSimulation = SimulationType.new()
	simulation.initialize(123456789)
	simulation.set_mode(SimulationType.BenchmarkMode.HUMANOID_LOD)
	var cached_position: Vector3 = simulation.soldier_world_positions[0]
	simulation.set_world_position_cache_enabled(false)
	simulation.reset_world_position_query_count()
	simulation.step(1.0 / 60.0)
	assert(simulation.last_world_position_updates == 0, "Lazy Formation path still wrote all world positions")
	var lazy_position: Vector3 = simulation.get_soldier_world_position(0)
	assert(simulation.lazy_world_position_queries == 1, "Lazy world-position resolver was not used")
	assert(lazy_position != cached_position, "Lazy test formation did not move")
	var lazy_resolver_queries: int = simulation.lazy_world_position_queries
	var policy: CrowdPromotionPolicy = PolicyType.new()
	policy.prepare(simulation, 64)
	simulation.reset_world_position_query_count()
	var policy_slots: PackedInt32Array = policy.resolve(
		simulation, lazy_position + Vector3(10.0, 12.0, 10.0), PackedInt32Array()
	)
	if policy_slots.size() != 64:
		_fail("Formation-aware policy did not fill 64 Near slots")
		return
	if policy.last_candidate_formation_count <= 0:
		_fail("Formation-aware policy found no candidate Formation")
		return
	if simulation.lazy_world_position_queries != policy.last_candidate_position_queries:
		_fail("Promotion policy re-resolved candidate positions during slot selection")
		return
	var policy_queries: int = simulation.lazy_world_position_queries
	simulation.set_world_position_cache_enabled(true)
	assert(simulation.last_world_position_updates == 10000, "Cache re-enable did not refresh all compatibility positions")
	assert(simulation.soldier_world_positions[0].is_equal_approx(lazy_position), "Lazy and cached positions diverged")

	print("FORMATION_SPACE_CONTRACT_PASS: batch_nodes=1 slots=100 active=99 formation_updates=%d slot_writes=%d lazy_updates=0 lazy_queries=%d policy_queries=%d candidate_formations=%d candidate_soldiers=%d culling_radius=%.2f" % [
		batch.formation_transform_updates,
		batch.local_slot_transform_writes,
		lazy_resolver_queries,
		policy_queries,
		policy.last_candidate_formation_count,
		policy.last_candidate_soldier_count,
		batch.culling_radius()
	])
	batch.queue_free()
	await process_frame
	quit(0)

func _fail(message: String) -> void:
	push_error(message)
	quit(1)
