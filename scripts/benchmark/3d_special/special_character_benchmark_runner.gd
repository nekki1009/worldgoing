extends SceneTree

const RigType = preload("res://scripts/benchmark/3d_crowd/human_rig_v1.gd")
const DefinitionType = preload("res://scripts/benchmark/3d_special/special_visual_definition.gd")
const AnimationStateType = preload("res://scripts/benchmark/3d_special/special_character_animation_state.gd")
const ControllerType = preload("res://scripts/benchmark/3d_special/special_character_benchmark_controller.gd")

const SCENE_PATH: String = "res://scenes/benchmark/3d_special/SpecialCharacter3DTest.tscn"
const CLOSE_CAPTURE_PATH: String = "res://.visual_captures/special_character_3d/special_character_close.png"
const TACTICAL_CAPTURE_PATH: String = "res://.visual_captures/special_character_3d/special_character_tactical.png"
const WARMUP_FRAMES: int = 45
const SAMPLE_FRAMES: int = 120
const COUNTS: Array[int] = [1, 16, 32, 64, 128]

var benchmark: SpecialCharacterBenchmarkController

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	Engine.max_fps = 0
	var scene: PackedScene = load(SCENE_PATH) as PackedScene
	assert(scene != null, "SPECIAL character scene could not be loaded")
	benchmark = scene.instantiate() as SpecialCharacterBenchmarkController
	assert(benchmark != null, "SPECIAL character controller root type mismatch")
	get_root().add_child(benchmark)
	await _settle(WARMUP_FRAMES)

	if OS.get_cmdline_user_args().has("--special-character-capture"):
		benchmark.set_active_special_count(1)
		benchmark.set_animation_state(AnimationStateType.State.ATTACK_SWORD)
		var close_target := Vector3(0.0, 1.0, 0.0)
		benchmark.set_camera_state(close_target + Vector3(5.0, 4.5, 5.5), close_target, 4.0)
		await _settle(75)
		assert(benchmark.capture_view(CLOSE_CAPTURE_PATH), "SPECIAL close capture could not be saved")
		benchmark.set_active_special_count(4)
		benchmark.set_animation_state(AnimationStateType.State.BLOCK)
		benchmark.set_camera_state(Vector3(15.0, 22.0, 18.0), Vector3.ZERO, 22.0)
		await _settle(75)
		assert(benchmark.capture_view(TACTICAL_CAPTURE_PATH), "SPECIAL tactical capture could not be saved")
		print("SPECIAL_CHARACTER_CAPTURE_PASS close=%s tactical=%s" % [
			ProjectSettings.globalize_path(CLOSE_CAPTURE_PATH),
			ProjectSettings.globalize_path(TACTICAL_CAPTURE_PATH)
		])
		quit(0)
		return

	print("SPECIAL_CHARACTER_ENV: godot=%s renderer=%s driver=%s rig_bones=%d" % [
		Engine.get_version_info().get("string", "unknown"),
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"),
		RenderingServer.get_video_adapter_name(), RigType.BONE_NAMES.size()
	])
	_print_asset_summary()
	benchmark.set_camera_state(Vector3(30.0, 42.0, 34.0), Vector3.ZERO, 52.0)
	var case_count := 0
	for count: int in COUNTS:
		benchmark.set_active_special_count(count)
		benchmark.set_animation_state(AnimationStateType.State.RUN)
		await _settle(WARMUP_FRAMES)
		benchmark.begin_measurement()
		await _settle(SAMPLE_FRAMES)
		var result: Dictionary = benchmark.end_measurement()
		var result_format: String = (
			"SPECIAL_CHARACTER_RESULT count=%d frames=%d fps=%.3f frame_ms=%.3f worst_frame_ms=%.3f "
			+ "animation_cpu_ms=%.3f character_nodes=%.1f skeletons=%.1f skinned_meshes=%.1f materials=%d "
			+ "draw_calls=%d triangles=%d"
		)
		print(result_format % [
			result.count, result.frames, result.fps, result.frame_ms, result.worst_frame_ms,
			result.animation_cpu_ms, result.character_nodes, result.skeletons,
			result.skinned_meshes, result.materials, result.draw_calls, result.triangles
		])
		case_count += 1
		await process_frame
	print("SPECIAL_CHARACTER_BENCHMARK_PASS cases=%d" % case_count)
	benchmark.queue_free()
	await process_frame
	quit(0)

func _print_asset_summary() -> void:
	var registry: SpecialCharacterVisualRegistry = benchmark.registry
	var body := registry.resolve(DefinitionType.Slot.BODY, &"human_body_01")
	var head := registry.resolve(DefinitionType.Slot.HEAD, &"head_01")
	var hair_short := registry.resolve(DefinitionType.Slot.HAIR, &"hair_short_01")
	var hair_long := registry.resolve(DefinitionType.Slot.HAIR, &"hair_long_01")
	var cloth := registry.resolve(DefinitionType.Slot.ARMOR, &"cloth_01")
	var leather := registry.resolve(DefinitionType.Slot.ARMOR, &"leather_01")
	var plate := registry.resolve(DefinitionType.Slot.ARMOR, &"plate_01")
	var helmet := registry.resolve(DefinitionType.Slot.HELMET, &"helmet_01")
	var sword := registry.resolve(DefinitionType.Slot.WEAPON, &"sword_01")
	var shield := registry.resolve(DefinitionType.Slot.SHIELD, &"shield_01")
	print("SPECIAL_CHARACTER_ASSETS: body_triangles=%s head_triangles=%d hair_triangles=[%d,%d] " % [
		_region_triangle_counts(body), _triangle_count(head.mesh), _triangle_count(hair_short.mesh), _triangle_count(hair_long.mesh)
	])
	print("SPECIAL_CHARACTER_ASSETS_ARMOR: cloth=%d leather=%d plate=%d helmet=%d sword=%d shield=%d materials=%d" % [
		_triangle_count(cloth.mesh), _triangle_count(leather.mesh), _triangle_count(plate.mesh),
		_triangle_count(helmet.mesh), _triangle_count(sword.mesh), _triangle_count(shield.mesh), registry.material_count()
	])
	print("SPECIAL_CHARACTER_STRUCTURE: per_character_nodes=%d skeletons=%d skinned_meshes=%d" % [
		benchmark.characters[0].get_character_node_count(), benchmark.characters[0].get_skeleton_count(),
		benchmark.characters[0].get_skinned_mesh_count()
	])

func _region_triangle_counts(definition: SpecialVisualDefinition) -> String:
	var counts: Array[int] = []
	for mesh: Mesh in definition.region_meshes:
		counts.append(_triangle_count(mesh))
	return str(counts)

func _triangle_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var triangle_count := 0
	for surface_index: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var index_data: Variant = arrays[Mesh.ARRAY_INDEX]
		if index_data is PackedInt32Array and not (index_data as PackedInt32Array).is_empty():
			triangle_count += (index_data as PackedInt32Array).size() / 3
		else:
			triangle_count += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return triangle_count

func _settle(frame_count: int) -> void:
	for _frame: int in range(frame_count):
		await process_frame
