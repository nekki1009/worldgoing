extends SceneTree

const SimulationType = preload("res://scripts/benchmark/3d_crowd/battle_crowd_simulation.gd")
const RigType = preload("res://scripts/benchmark/3d_crowd/human_rig_v1.gd")
const AnimationLibraryType = preload("res://scripts/benchmark/3d_crowd/human_animation_library.gd")
const RegistryType = preload("res://scripts/benchmark/3d_crowd/soldier_visual_registry.gd")
const ScenePath: String = "res://scenes/benchmark/3d_crowd/CrowdBenchmark3D.tscn"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var first: BattleCrowdSimulation = SimulationType.new()
	first.initialize(424242)
	assert(first.formations.size() == 100, "Expected 100 formations")
	assert(first.soldier_world_positions.size() == 10000, "Expected 10,000 soldier rows")
	assert(first.soldier_id.size() == 10000, "Soldier ID column is not packed")
	assert(first.soldier_animation_time.size() == 10000, "Animation time column is missing")
	assert(first.soldier_visual_archetype.size() == 10000, "Archetype column is missing")
	assert(first.soldier_color_variant.size() == 10000, "Color variant column is missing")
	assert(first.soldier_equipment_variant.size() == 10000, "Equipment variant column is missing")
	assert(first.active_soldier_count == 10000, "Initial active soldier count mismatch")
	for formation_id: int in range(100):
		assert(first.formations[formation_id].formation_id == formation_id, "Formation ID mismatch")
	var first_slot: Vector3 = CrowdFormationSlotGenerator.local_position(0)
	var last_slot: Vector3 = CrowdFormationSlotGenerator.local_position(99)
	assert(is_equal_approx(first_slot.x, -5.625) and is_equal_approx(first_slot.z, -5.625), "10x10 first slot mismatch")
	assert(is_equal_approx(last_slot.x, 5.625) and is_equal_approx(last_slot.z, 5.625), "10x10 last slot mismatch")
	assert(first.soldier_slot_index[99] == 99, "Slot index column mismatch")

	var second: BattleCrowdSimulation = SimulationType.new()
	second.initialize(424242)
	assert(first.soldier_world_positions == second.soldier_world_positions, "Seeded positions differ")
	assert(first.soldier_visual_archetype == second.soldier_visual_archetype, "Seeded archetypes differ")
	assert(first.soldier_color_variant == second.soldier_color_variant, "Seeded color variants differ")
	assert(first.soldier_equipment_variant == second.soldier_equipment_variant, "Seeded equipment variants differ")
	assert(first.soldier_animation_phase == second.soldier_animation_phase, "Seeded phases differ")
	assert(first.formations[0].destination == second.formations[0].destination, "Seeded destinations differ")
	var archetype_seen: PackedByteArray = PackedByteArray()
	archetype_seen.resize(4)
	archetype_seen.fill(0)
	for soldier_index: int in range(first.active_soldier_count):
		archetype_seen[first.soldier_visual_archetype[soldier_index]] = 1
	for archetype_id: int in range(4):
		assert(archetype_seen[archetype_id] == 1, "Archetype is not represented")

	var before: Vector3 = first.soldier_world_positions[0]
	first.set_mode(SimulationType.BenchmarkMode.HUMANOID_ANIMATED)
	first.step(0.25)
	assert(first.soldier_world_positions[0] != before, "Formation did not move its slots")
	assert(first.soldier_animation_state[0] == SimulationType.AnimationState.WALK or first.soldier_animation_state[0] == SimulationType.AnimationState.ATTACK, "Animated state did not advance")
	assert(first.soldier_animation_time[0] > 0.0, "Animation time did not advance")
	var attack_seen: bool = false
	for soldier_index: int in range(first.active_soldier_count):
		if first.soldier_animation_state[soldier_index] == SimulationType.AnimationState.ATTACK:
			attack_seen = true
			break
	assert(attack_seen, "Attack state was never scheduled")

	var skeleton: Skeleton3D = RigType.build_skeleton()
	assert(RigType.validate(skeleton), "HumanRig_v1 contract mismatch")
	assert(skeleton.find_bone("weapon_socket_r") >= 0, "Weapon socket missing")
	assert(skeleton.find_bone("shield_socket_l") >= 0, "Shield socket missing")
	assert(skeleton.find_bone("head_socket") >= 0, "Head socket missing")
	assert(skeleton.find_bone("back_socket") >= 0, "Back socket missing")
	var animation_library: AnimationLibrary = AnimationLibraryType.build_library()
	for clip_name: StringName in [&"idle", &"walk", &"attack_1h", &"attack_spear", &"dead"]:
		assert(animation_library.has_animation(clip_name), "Shared animation clip missing: %s" % clip_name)
	var registry: SoldierVisualRegistry = RegistryType.new()
	assert(registry.entries.size() == 4, "Expected four regular visual archetypes")
	for spec: SoldierVisualArchetype in registry.entries:
		assert(spec.mid_mesh != null and spec.far_mesh != null, "Archetype mesh compilation failed")
	assert(registry.placeholder_mesh != null, "Placeholder mesh missing")

	var scene: PackedScene = load(ScenePath) as PackedScene
	assert(scene != null, "Benchmark scene missing")
	var instance: Node = scene.instantiate()
	get_root().add_child(instance)
	await process_frame
	await process_frame
	assert(instance.find_children("*", "CharacterBody3D", true, false).is_empty(), "Per-soldier CharacterBody3D found")
	assert(instance.find_children("*", "NavigationAgent3D", true, false).is_empty(), "Per-soldier NavigationAgent3D found")
	var skeleton_count: int = instance.find_children("*", "Skeleton3D", true, false).size()
	var animation_player_count: int = instance.find_children("*", "AnimationPlayer", true, false).size()
	assert(skeleton_count <= 256, "Near actor Skeleton3D pool exceeded MAX_FULL_ACTORS")
	assert(animation_player_count <= 256, "Near actor AnimationPlayer pool exceeded MAX_FULL_ACTORS")
	var renderer: CrowdRenderer3D = instance.get_node("CrowdRenderer3D") as CrowdRenderer3D
	assert(renderer.chunks.size() == 144, "Expected 144 spatial crowd chunks")
	assert(renderer.multimesh_instance_count > 0, "Crowd MultiMesh groups were not populated")
	var seen_soldiers := PackedByteArray()
	seen_soldiers.resize(10000)
	seen_soldiers.fill(0)
	var assigned_soldiers: int = 0
	for group_index: int in range(renderer._group_soldiers.size()):
		var group_indices: PackedInt32Array = renderer._group_soldiers[group_index]
		for slot: int in range(group_indices.size()):
			var soldier_index: int = group_indices[slot]
			assert(seen_soldiers[soldier_index] == 0, "Stable crowd slot duplicated a soldier")
			seen_soldiers[soldier_index] = 1
			assert(renderer._soldier_group_index[soldier_index] == group_index, "Soldier group index drifted")
			assert(renderer._soldier_group_slot[soldier_index] == slot, "Soldier stable slot drifted")
			assigned_soldiers += 1
	assert(assigned_soldiers == renderer.multimesh_instance_count, "Crowd slot count mismatch")
	print("SOLDIER_VISUAL_CONTRACT_PASS: formations=100 soldiers=10000 archetypes=4 chunks=144 skeletons=%d animation_players=%d" % [skeleton_count, animation_player_count])
	skeleton.free()
	instance.queue_free()
	await process_frame
	quit(0)
