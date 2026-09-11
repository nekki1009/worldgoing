extends SceneTree

const FRAME_DIR: String = "res://.visual_captures/standard_anime_walk/frames"
const MODEL_PATH: String = "res://assets/characters/human/q35/base_body_series_male_standard_anime_body_only.glb"
const VIEWPORT_SIZE: Vector2i = Vector2i(1024, 768)
const FRAME_TOTAL: int = 24
const WALK_CYCLE_SECONDS: float = 1.0

var character_viewport: SubViewport
var model_root: Node3D
var skeleton: Skeleton3D
var character_sprite: Sprite2D
var hud_canvas: CanvasLayer
var hud_label: Label
var frame_index: int = 0
var animated_bone_count: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_move_to_foreground()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1024, 768))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	OS.low_processor_usage_mode = false
	Engine.max_fps = 0

	var output_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(FRAME_DIR)
	)
	assert(output_error == OK or output_error == ERR_ALREADY_EXISTS, "Frame directory failed")
	_build_character_viewport()
	_build_hud()
	await _settle(4)

	for index: int in range(FRAME_TOTAL):
		var cycle_time: float = float(index) / float(FRAME_TOTAL) * WALK_CYCLE_SECONDS
		_apply_walk_pose(cycle_time)
		_update_hud(cycle_time)
		await process_frame
		_capture_frame()

	assert(animated_bone_count >= 10, "Walk pose did not find enough VRM bones")
	print(
		"STANDARD_ANIME_WALK_PREVIEW_PASS: frames=%d cycle=%.2fs animated_bones=%d model=%s" % [
			frame_index,
			WALK_CYCLE_SECONDS,
			animated_bone_count,
			MODEL_PATH,
		]
	)
	character_sprite.queue_free()
	character_viewport.queue_free()
	hud_canvas.queue_free()
	character_sprite = null
	character_viewport = null
	model_root = null
	skeleton = null
	await _settle(4)
	quit(0)

func _build_character_viewport() -> void:
	character_viewport = SubViewport.new()
	character_viewport.name = "StandardAnimeWalkViewport"
	character_viewport.size = VIEWPORT_SIZE
	character_viewport.transparent_bg = false
	character_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	character_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	character_viewport.handle_input_locally = false
	get_root().add_child(character_viewport)

	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#e8e0d4")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#f0eee4")
	environment.ambient_light_energy = 0.9
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	character_viewport.add_child(environment_node)

	var ground: MeshInstance3D = MeshInstance3D.new()
	ground.name = "WalkPreviewGround"
	var ground_mesh: PlaneMesh = PlaneMesh.new()
	ground_mesh.size = Vector2(8.0, 8.0)
	ground.mesh = ground_mesh
	var ground_material: StandardMaterial3D = StandardMaterial3D.new()
	ground_material.albedo_color = Color("#a99b88")
	ground_material.roughness = 0.92
	ground.material_override = ground_material
	ground.position.y = -0.012
	character_viewport.add_child(ground)

	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	key_light.light_color = Color("#fff0d3")
	key_light.light_energy = 1.15
	character_viewport.add_child(key_light)
	var fill_light: DirectionalLight3D = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-25.0, 145.0, 0.0)
	fill_light.light_color = Color("#9dc9dd")
	fill_light.light_energy = 0.3
	character_viewport.add_child(fill_light)

	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var absolute_model_path: String = ProjectSettings.globalize_path(MODEL_PATH)
	assert(FileAccess.file_exists(absolute_model_path), "Missing model: %s" % MODEL_PATH)
	var parse_error: Error = document.append_from_file(absolute_model_path, state)
	assert(parse_error == OK, "GLTF parse failed: %d" % parse_error)
	var generated: Node = document.generate_scene(state)
	assert(generated != null, "GLTF generated no scene")
	model_root = generated as Node3D
	assert(model_root != null, "GLTF scene root is not Node3D")
	model_root.name = "StandardAnimeMaleWalkModel"
	character_viewport.add_child(model_root)

	var skeletons: Array[Node] = model_root.find_children("*", "Skeleton3D", true, false)
	assert(skeletons.size() == 1, "Expected one VRM Skeleton3D, found %d" % skeletons.size())
	skeleton = skeletons[0] as Skeleton3D
	assert(skeleton != null and skeleton.get_bone_count() >= 80, "VRM Skeleton3D is incomplete")

	var camera: Camera3D = Camera3D.new()
	camera.name = "StandardAnimeWalkCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.25
	camera.near = 0.03
	camera.far = 100.0
	camera.position = Vector3(2.35, 1.18, -4.55)
	character_viewport.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.86, 0.0), Vector3.UP)
	camera.current = true

	character_sprite = Sprite2D.new()
	character_sprite.name = "StandardAnimeWalkSprite"
	character_sprite.texture = character_viewport.get_texture()
	character_sprite.position = Vector2(VIEWPORT_SIZE) * 0.5
	get_root().add_child(character_sprite)

func _build_hud() -> void:
	hud_canvas = CanvasLayer.new()
	hud_canvas.name = "StandardAnimeWalkHUD"
	get_root().add_child(hud_canvas)
	var panel: ColorRect = ColorRect.new()
	panel.position = Vector2(26.0, 24.0)
	panel.size = Vector2(438.0, 82.0)
	panel.color = Color(0.04, 0.05, 0.07, 0.80)
	hud_canvas.add_child(panel)
	hud_label = Label.new()
	hud_label.position = Vector2(44.0, 34.0)
	hud_label.add_theme_font_size_override("font_size", 19)
	hud_label.add_theme_color_override("font_color", Color("#f4ead7"))
	hud_canvas.add_child(hud_label)

func _update_hud(cycle_time: float) -> void:
	if hud_label == null:
		return
	hud_label.text = (
		"WALK CYCLE PREVIEW  /  STANDARD ANIME BASE\n"
		+ "VRM skeleton 91 bones   |   cycle %.2fs   |   frame %02d/%02d"
	) % [cycle_time, frame_index, FRAME_TOTAL]

func _apply_walk_pose(cycle_time: float) -> void:
	if skeleton == null or model_root == null:
		return
	skeleton.reset_bone_poses()
	var phase: float = cycle_time * TAU / WALK_CYCLE_SECONDS
	var stride: float = sin(phase)
	var knee_left: float = maxf(0.0, -stride) * 0.42
	var knee_right: float = maxf(0.0, stride) * 0.42
	var arm_swing: float = sin(phase + PI) * 0.22
	animated_bone_count = 0

	_set_rotation("J_Bip_L_UpperLeg", Vector3(stride * 0.48, 0.0, 0.0))
	_set_rotation("J_Bip_R_UpperLeg", Vector3(-stride * 0.48, 0.0, 0.0))
	_set_rotation("J_Bip_L_LowerLeg", Vector3(knee_left, 0.0, 0.0))
	_set_rotation("J_Bip_R_LowerLeg", Vector3(knee_right, 0.0, 0.0))
	_set_rotation("J_Bip_L_Foot", Vector3(-stride * 0.16 - knee_left * 0.20, 0.0, 0.0))
	_set_rotation("J_Bip_R_Foot", Vector3(stride * 0.16 - knee_right * 0.20, 0.0, 0.0))

	# The imported source is a T-pose. The -1.16 rad drop is the neutral arm
	# position; the small alternating Z component gives the lowered arms a
	# readable forward/back counter-swing without changing the body proportions.
	_set_rotation("J_Bip_L_UpperArm", Vector3(-1.16, 0.0, arm_swing))
	_set_rotation("J_Bip_R_UpperArm", Vector3(-1.16, 0.0, -arm_swing))
	_set_rotation("J_Bip_L_LowerArm", Vector3(0.12, 0.0, arm_swing * 0.25))
	_set_rotation("J_Bip_R_LowerArm", Vector3(0.12, 0.0, -arm_swing * 0.25))
	_set_rotation("J_Bip_C_Chest", Vector3(0.0, 0.0, stride * 0.035))
	_set_rotation("J_Bip_C_Head", Vector3(0.0, 0.0, -stride * 0.025))

	model_root.position.y = absf(sin(phase * 2.0)) * 0.025
	model_root.rotation.z = sin(phase * 2.0) * 0.012
	skeleton.force_update_all_bone_transforms()

func _set_rotation(bone_name: String, euler: Vector3) -> void:
	var bone_index: int = skeleton.find_bone(bone_name)
	if bone_index < 0:
		return
	skeleton.set_bone_pose_rotation(bone_index, Quaternion.from_euler(euler))
	animated_bone_count += 1

func _capture_frame() -> void:
	var image: Image = get_root().get_texture().get_image()
	assert(image != null and not image.is_empty(), "Walk preview viewport is empty")
	var output_path: String = FRAME_DIR.path_join("frame_%03d.png" % frame_index)
	assert(image.save_png(ProjectSettings.globalize_path(output_path)) == OK, "Could not save %s" % output_path)
	frame_index += 1

func _settle(frame_count: int) -> void:
	for _index: int in range(frame_count):
		await process_frame
