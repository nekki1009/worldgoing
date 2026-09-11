extends SceneTree

const AssetScenePath: String = "res://assets/characters/human/v1/human_base_v1.tscn"
const RigType = preload("res://scripts/benchmark/3d_crowd/human_rig_v1.gd")
const HumanBaseType = preload("res://scripts/characters/human/human_base_v1.gd")
const AnimationStateType = preload("res://scripts/benchmark/3d_special/special_character_animation_state.gd")
const BundleType = preload("res://scripts/benchmark/3d_special/special_character_render_bundle.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load(AssetScenePath) as PackedScene
	assert(packed != null, "HumanBase_v1 asset scene missing")
	var base: HumanBaseV1 = packed.instantiate() as HumanBaseV1
	assert(base != null, "HumanBase_v1 root script missing")
	root.add_child(base)
	await process_frame
	await process_frame

	assert(base.skeleton != null and RigType.validate(base.skeleton), "HumanRig_v1 names changed")
	assert(base.skeleton.get_bone_count() == 22, "HumanRig_v1 bone count changed")
	assert(base.mesh_instance != null, "HumanBase_v1 mesh instance missing")
	assert(base.mesh_instance.skin != null, "HumanBase_v1 Skin resource missing")
	assert(base.mesh_instance.skeleton != NodePath(""), "HumanBase_v1 Skeleton3D path missing")
	assert(base.body_mesh != null and base.body_mesh.get_surface_count() == 1, "Body must be one surface")
	assert(base.body_material != null, "HumanBase_v1 body material missing")
	assert(base.region_vertex_ranges.size() == 15, "Body Region Contract is incomplete")
	assert(base.get_body_region_names().size() == 15, "Body Region names are incomplete")
	assert(base.validate_weights(), "Skin weights are invalid")
	assert(base.validate_topology(), "Body topology has open or degenerate edges")

	var stats: Dictionary = base.get_stats()
	var height: float = float(stats["height"])
	var aabb_min_y: float = float(stats["aabb_min_y"])
	var triangles: int = int(stats["triangles"])
	print("HUMAN_BASE_V1_STATS: height=%.6f aabb_min_y=%.6f vertices=%d triangles=%d" % [height, aabb_min_y, int(stats["vertices"]), triangles])
	assert(absf(height - HumanBaseType.HEIGHT_M) < 0.02, "HumanBase_v1 height is outside 1.78m contract")
	assert(absf(aabb_min_y) < 0.01, "HumanBase_v1 feet do not meet ground origin")
	assert(triangles >= HumanBaseType.TRIANGLE_MIN and triangles <= HumanBaseType.TRIANGLE_MAX, "Triangle budget exceeded")
	assert(int(stats["vertices"]) > 0, "HumanBase_v1 has no vertices")
	assert(int(stats["surfaces"]) == 1, "HumanBase_v1 surface count changed")
	assert(int(stats["materials"]) == 1, "HumanBase_v1 material count changed")
	assert(int(stats["skinned_meshes"]) == 1, "HumanBase_v1 skinned mesh count changed")
	assert(base.global_position == Vector3.ZERO, "HumanBase_v1 root origin changed")
	assert(base.scale == Vector3.ONE, "HumanBase_v1 root scale changed")
	assert(String(stats["forward_axis"]) == "-Z", "HumanBase_v1 forward axis changed")
	assert(base.wireframe_instance != null and base.wireframe_instance.mesh != null, "Wireframe debug mesh missing")
	assert(base.region_debug_instance != null and base.region_debug_instance.mesh != null, "Body Region debug mesh missing")
	base.set_debug_mode(HumanBaseType.DebugMode.SKELETON)
	assert(base.skeleton_gizmo_instance.visible, "Skeleton debug mode did not enable")
	base.set_debug_mode(HumanBaseType.DebugMode.WIREFRAME)
	assert(base.wireframe_instance.visible, "Wireframe debug mode did not enable")
	base.set_debug_mode(HumanBaseType.DebugMode.BODY_REGIONS)
	assert(base.region_debug_instance.visible, "Body Region debug mode did not enable")
	base.set_debug_mode(HumanBaseType.DebugMode.SOCKETS)
	assert(base.get_socket_transform(&"head_socket") != Transform3D.IDENTITY, "Socket debug mode has no socket")
	base.set_debug_mode(HumanBaseType.DebugMode.MESH)

	for socket_name: StringName in [&"weapon_socket_r", &"shield_socket_l", &"head_socket", &"back_socket"]:
		assert(base.get_socket_bone_name(socket_name) == socket_name, "Socket bone mismatch: %s" % socket_name)
		assert(base.get_socket_transform(socket_name) != Transform3D.IDENTITY, "Socket transform missing: %s" % socket_name)

	var library: AnimationLibrary = base.animation_player.get_animation_library(&"")
	assert(library != null, "HumanRig_v1 AnimationPlayer library missing")
	for clip_name: StringName in [&"idle", &"walk", &"run", &"attack_sword_1h", &"block"]:
		assert(library.has_animation(clip_name), "Animation clip missing: %s" % clip_name)

	var idle_weapon: Transform3D = base.get_socket_transform(&"weapon_socket_r")
	var idle_shield: Transform3D = base.get_socket_transform(&"shield_socket_l")
	for state: int in range(AnimationStateType.State.BLOCK + 1):
		base.set_animation_state(state, 0.35, 0.17)
		await process_frame
		assert(RigType.validate(base.skeleton), "Skeleton changed during animation state %d" % state)
		assert(base.validate_weights(), "Skin weights changed during animation state %d" % state)
	base.set_animation_state(AnimationStateType.State.IDLE, 0.0, 0.0)
	await process_frame
	assert(base.get_socket_transform(&"weapon_socket_r") == idle_weapon, "Idle weapon socket is not deterministic")
	assert(base.get_socket_transform(&"shield_socket_l") == idle_shield, "Idle shield socket is not deterministic")
	base.set_animation_state(AnimationStateType.State.ATTACK_SWORD, 0.35, 0.0)
	await process_frame
	assert(base.get_socket_transform(&"weapon_socket_r") != idle_weapon, "Weapon socket did not follow attack pose")
	base.set_animation_state(AnimationStateType.State.BLOCK, 0.35, 0.0)
	await process_frame
	assert(base.get_socket_transform(&"shield_socket_l") != idle_shield, "Shield socket did not follow block pose")

	var bundle := BundleType.new()
	assert(base.populate_render_bundle(bundle), "RenderBundle payload rejected HumanBase_v1")
	var bundle_stats: Dictionary = bundle.render_stats()
	assert(bundle.skinned_mesh == base.body_mesh, "RenderBundle did not retain the canonical body mesh")
	assert(bundle.skinned_material == base.body_material, "RenderBundle did not retain the canonical body material")
	assert(int(bundle_stats["skinned_meshes"]) == 1, "RenderBundle body submission count changed")
	assert(int(bundle_stats["surfaces"]) == 1, "RenderBundle body surfaces changed")
	assert(int(bundle_stats["triangles"]) == triangles, "RenderBundle triangle count changed")

	print(
		"HUMAN_BASE_V1_CONTRACT_PASS: height=%.3f vertices=%d triangles=%d surfaces=%d materials=%d bones=%d skinned_meshes=%d regions=%d sockets=%d animations=5 topology=true weights=true render_bundle=true" % [
			height, int(stats["vertices"]), triangles, int(stats["surfaces"]), int(stats["materials"]),
			int(stats["bones"]), int(stats["skinned_meshes"]), int(stats["regions"]), int(stats["sockets"])
		]
	)
	base.queue_free()
	await process_frame
	quit(0)
