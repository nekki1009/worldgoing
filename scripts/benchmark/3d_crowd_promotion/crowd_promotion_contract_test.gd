extends SceneTree

const SimulationType = preload("res://scripts/benchmark/3d_crowd/battle_crowd_simulation.gd")
const PolicyType = preload("res://scripts/benchmark/3d_crowd/crowd_promotion_policy.gd")
const PoolType = preload("res://scripts/benchmark/3d_crowd/crowd_special_actor_pool.gd")
const SpecialRegistryType = preload("res://scripts/benchmark/3d_special/special_character_visual_registry.gd")
const SpecialAnimationLibraryType = preload("res://scripts/benchmark/3d_special/special_human_animation_library.gd")
const RenderModeType = preload("res://scripts/benchmark/3d_special/special_character_render_mode.gd")
const ControllerType = preload("res://scripts/benchmark/3d_crowd_promotion/crowd_promotion_benchmark_controller.gd")
const ScenePath: String = "res://scenes/benchmark/3d_crowd_promotion/CrowdPromotionBenchmark3D.tscn"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var first: BattleCrowdSimulation = SimulationType.new()
	var second: BattleCrowdSimulation = SimulationType.new()
	first.initialize(424242)
	second.initialize(424242)
	assert(first.soldier_world_positions == second.soldier_world_positions, "Seeded crowd positions differ")
	assert(first.soldier_animation_phase == second.soldier_animation_phase, "Seeded animation phases differ")
	assert(first.soldier_visual_variant == second.soldier_visual_variant, "Seeded visual variants differ")
	assert(first.formations[0].destination == second.formations[0].destination, "Seeded destinations differ")
	assert(first.active_soldier_count == 10000, "Promotion contract requires 10,000 Crowd soldiers")

	var policy: CrowdPromotionPolicy = PolicyType.new()
	policy.prepare(first, 64)
	var first_camera: Vector3 = first.soldier_world_positions[0] + Vector3(10.0, 12.0, 10.0)
	var first_slots: PackedInt32Array = policy.resolve(first, first_camera, PackedInt32Array())
	var first_slots_copy: PackedInt32Array = first_slots.duplicate()
	assert(first_slots.size() == 64, "Promotion policy did not expose 64 fixed slots")
	assert(policy.slots_are_unique_and_valid(first, first_slots), "Initial promotion slots are not unique and valid")
	var repeat_slots: PackedInt32Array = policy.resolve(first, first_camera, first_slots_copy)
	assert(repeat_slots == first_slots_copy, "Same seed/camera did not produce the same promotion slots")

	var pool := PoolType.new()
	pool.name = "ContractSpecialActorPool"
	get_root().add_child(pool)
	pool.initialize(SpecialRegistryType.new(), SpecialAnimationLibraryType.build_library(), 64)
	await process_frame
	assert(pool.allocated_actors.size() == 64, "Actor Pool did not preallocate 64 actors")
	assert(pool.allocation_count == 64, "Actor Pool allocation count is not fixed")
	assert(pool.render_bundle_cache.bundle_count() > 0, "RenderBundle cache was not prewarmed")
	assert(pool.render_bundle_cache.build_count == pool.render_bundle_cache.bundle_count(), "RenderBundle cache build accounting mismatch")

	var positions_before: PackedVector3Array = first.soldier_world_positions.duplicate()
	var facing_before: PackedFloat32Array = first.soldier_facing.duplicate()
	var states_before: PackedInt32Array = first.soldier_animation_state.duplicate()
	pool.sync_from_simulation(first_slots_copy, first)
	await process_frame
	assert(pool.active_actor_count == 64, "Pool did not activate 64 Near actors")
	assert(pool.promotions_this_frame == 64, "Initial promotion count is not 64")
	assert(pool.demotions_this_frame == 0, "Initial promotion unexpectedly demoted actors")
	assert(first.soldier_world_positions == positions_before, "Pool changed authoritative positions")
	assert(first.soldier_facing == facing_before, "Pool changed authoritative facing")
	assert(first.soldier_animation_state == states_before, "Pool changed authoritative animation state")
	var modular_stats: Dictionary = pool.render_stats()
	assert(modular_stats.get("mesh_instances", 0) > 0, "Modular render stats are empty")
	pool.set_render_mode(RenderModeType.Mode.SKINNED_BUNDLE)
	pool.sync_from_simulation(first_slots_copy, first, first_camera)
	await process_frame
	assert(pool.bundle_cache_misses == 0, "Promotion caused a RenderBundle cache miss")
	assert(pool.bundle_lod0_active == 64, "Fixed bundle mode did not activate LOD0 for all Near actors")
	var bundle_stats: Dictionary = pool.render_stats()
	assert(bundle_stats.get("skinned_meshes", 0) == 64, "RenderBundle did not reduce to one skinned mesh per actor")
	assert(bundle_stats.get("surfaces", 0) < modular_stats.get("surfaces", 0), "RenderBundle did not reduce surfaces")
	assert(pool.component_breakdown().has(&"SkinnedBundle"), "Skinned RenderBundle component is missing")

	var actor_instance_ids: Array[int] = []
	for slot: int in range(64):
		var actor: SpecialCharacterVisual3D = pool.get_actor_for_slot(slot)
		assert(actor != null and actor.visible, "Promoted actor is not visible")
		assert(actor.soldier_id == first_slots_copy[slot], "Actor soldier identity mismatch")
		actor_instance_ids.append(actor.get_instance_id())
	var stable_promotions: int = pool.total_promotions
	pool.sync_from_simulation(first_slots_copy, first)
	assert(pool.total_promotions == stable_promotions, "Stable frame re-promoted actors")
	for slot: int in range(64):
		assert(pool.get_actor_for_slot(slot).get_instance_id() == actor_instance_ids[slot], "Pool slot actor was recreated")

	var second_camera: Vector3 = first.soldier_world_positions[9999] + Vector3(10.0, 12.0, 10.0)
	var second_slots: PackedInt32Array = policy.resolve(first, second_camera, first_slots_copy)
	assert(policy.slots_are_unique_and_valid(first, second_slots), "Second promotion slots are not unique and valid")
	pool.sync_from_simulation(second_slots, first)
	await process_frame
	assert(pool.active_actor_count == 64, "Pool lost actors after camera transition")
	assert(pool.promotions_this_frame > 0, "Camera transition did not promote new actors")
	assert(pool.demotions_this_frame > 0, "Camera transition did not demote old actors")
	assert(pool.allocated_actors.size() == 64, "Camera transition changed pool capacity")
	assert(pool.allocation_count == 64, "Camera transition allocated new actors")
	assert(first.soldier_world_positions == positions_before, "Demotion/promotion changed authoritative positions")
	assert(first.soldier_facing == facing_before, "Demotion/promotion changed authoritative facing")
	assert(first.soldier_animation_state == states_before, "Demotion/promotion changed authoritative animation state")
	for slot: int in range(64):
		var promoted_actor: SpecialCharacterVisual3D = pool.get_actor_for_slot(slot)
		assert(promoted_actor.soldier_id == second_slots[slot], "Post-transition soldier identity mismatch")
		assert(promoted_actor.global_position.is_equal_approx(first.soldier_world_positions[second_slots[slot]]), "Actor did not sync world position")

	var empty_slots := PackedInt32Array()
	empty_slots.resize(64)
	empty_slots.fill(-1)
	pool.sync_from_simulation(empty_slots, first)
	assert(pool.active_actor_count == 0, "Pool did not demote all actors")
	assert(pool.demotions_this_frame == 64, "Full demotion count is not 64")
	assert(pool.allocated_actors.size() == 64 and pool.allocation_count == 64, "Demotion released/reallocated pool actors")
	for actor: SpecialCharacterVisual3D in pool.allocated_actors:
		assert(not actor.visible, "Demoted actor remained visible")

	var scene: PackedScene = load(ScenePath) as PackedScene
	assert(scene != null, "Promotion benchmark scene missing")
	var instance: CrowdPromotionBenchmarkController = scene.instantiate() as CrowdPromotionBenchmarkController
	assert(instance != null, "Promotion benchmark controller type mismatch")
	get_root().add_child(instance)
	await process_frame
	await process_frame
	instance.set_simulation_paused(true)
	instance.set_near_actor_budget(64)
	instance.focus_on_soldier(0, 42.0)
	await process_frame
	await process_frame
	assert(instance.actor_pool.active_actor_count == 64, "Integrated pool did not promote 64 actors")
	assert(instance.actor_pool.allocated_skeleton_count() == 128, "Integrated SPECIAL stress pool skeleton count mismatch")
	assert(instance.actor_pool.allocation_count == 128, "Integrated SPECIAL stress pool allocation changed")
	assert(instance.crowd_renderer.near_actor_count == 0, "Legacy Crowd Near pool was not disabled")
	assert(instance.crowd_renderer.external_near_count() == 64, "Crowd external Near mask count mismatch")
	var integrated_ids: PackedInt32Array = instance.actor_pool.get_slot_soldier_ids()
	assert(instance.crowd_renderer.is_external_near_soldier(integrated_ids[0]), "Promoted id was not masked from MultiMesh")
	assert(instance.crowd_renderer.multimesh_instance_count == 9936, "Crowd MultiMesh did not exclude promoted soldiers")
	assert(instance.crowd_renderer.multimesh_instance_count + instance.actor_pool.active_actor_count == 10000, "Crowd + Near representations do not cover all soldiers")

	print(
		"CROWD_PROMOTION_CONTRACT_PASS: formations=100 soldiers=10000 max_near=64 "
		+ "allocated_actors=%d allocated_skeletons=%d stable_slots=64 transitions=%d/%d masked=%d" % [
			pool.allocated_actors.size(), pool.allocated_skeleton_count(),
			pool.total_promotions, pool.total_demotions, instance.crowd_renderer.external_near_count()
		]
	)
	pool.queue_free()
	instance.queue_free()
	await process_frame
	quit(0)
