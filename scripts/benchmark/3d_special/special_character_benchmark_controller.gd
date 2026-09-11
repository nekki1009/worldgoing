class_name SpecialCharacterBenchmarkController
extends Node3D

const AppearanceType = preload("res://scripts/benchmark/3d_special/special_character_appearance.gd")
const AnimationStateType = preload("res://scripts/benchmark/3d_special/special_character_animation_state.gd")
const RegistryType = preload("res://scripts/benchmark/3d_special/special_character_visual_registry.gd")
const VisualType = preload("res://scripts/benchmark/3d_special/special_character_visual_3d.gd")
const AnimationLibraryType = preload("res://scripts/benchmark/3d_special/special_human_animation_library.gd")
const HudType = preload("res://scripts/benchmark/3d_special/special_character_benchmark_hud.gd")

const DEFAULT_SEED: int = 7132901
const INITIAL_SPECIAL_COUNT: int = 4
const VALID_COUNTS: Array[int] = [1, 4, 16, 32, 64, 128]

@onready var hud: SpecialCharacterBenchmarkHUD = $SpecialCharacterHUD

var registry: SpecialCharacterVisualRegistry
var shared_animation_library: AnimationLibrary
var characters: Array[SpecialCharacterVisual3D] = []
var camera: Camera3D
var camera_target: Vector3 = Vector3.ZERO
var selected_character_index: int = 0
var selected_animation_state: int = AnimationStateType.State.IDLE
var selected_special_count: int = INITIAL_SPECIAL_COUNT
var animation_clock: float = 0.0
var deterministic_seed: int = DEFAULT_SEED
var randomizer := RandomNumberGenerator.new()

var last_frame_ms: float = 0.0
var last_animation_cpu_ms: float = 0.0
var last_draw_calls: int = 0
var last_triangles: int = 0
var worst_frame_ms: float = 0.0
var sample_active: bool = false
var sample_frames: int = 0
var sample_frame_ms: float = 0.0
var sample_fps: float = 0.0
var sample_animation_cpu_ms: float = 0.0
var sample_draw_calls: float = 0.0
var sample_triangles: float = 0.0
var sample_nodes: float = 0.0
var sample_skeletons: float = 0.0
var sample_skinned_meshes: float = 0.0

func _ready() -> void:
	_build_world()
	registry = RegistryType.new()
	shared_animation_library = AnimationLibraryType.build_library()
	_build_characters(INITIAL_SPECIAL_COUNT)
	if hud != null:
		hud.setup(self, registry)
		_refresh_hud_appearance()

func _process(delta: float) -> void:
	_handle_camera_pan(delta)
	animation_clock += delta
	var animation_started_usec: int = Time.get_ticks_usec()
	for index: int in range(characters.size()):
		var character := characters[index]
		character.apply_animation_state(
			selected_animation_state,
			animation_clock,
			float(index) * 0.173 + float(deterministic_seed % 97) * 0.001
		)
	last_animation_cpu_ms = float(Time.get_ticks_usec() - animation_started_usec) / 1000.0
	last_frame_ms = maxf(delta * 1000.0, 0.001)
	worst_frame_ms = maxf(worst_frame_ms, last_frame_ms)
	var viewport_fps: float = 1000.0 / last_frame_ms
	last_draw_calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	last_triangles = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if hud != null:
		hud.update_metrics(
			viewport_fps, last_frame_ms, worst_frame_ms, selected_special_count,
			_count_skeletons(), _count_skinned_meshes(), _count_nodes(),
			last_animation_cpu_ms, last_draw_calls, last_triangles,
			_animation_name(selected_animation_state), registry.material_count()
		)
	if sample_active:
		sample_frames += 1
		sample_frame_ms += last_frame_ms
		sample_fps += viewport_fps
		sample_animation_cpu_ms += last_animation_cpu_ms
		sample_draw_calls += float(last_draw_calls)
		sample_triangles += float(last_triangles)
		sample_nodes += float(_count_nodes())
		sample_skeletons += float(_count_skeletons())
		sample_skinned_meshes += float(_count_skinned_meshes())

func set_active_special_count(requested_count: int) -> void:
	var nearest_count: int = VALID_COUNTS[0]
	for candidate: int in VALID_COUNTS:
		if abs(candidate - requested_count) < abs(nearest_count - requested_count):
			nearest_count = candidate
	selected_special_count = nearest_count
	_build_characters(selected_special_count)
	if hud != null:
		hud.set_count_selection(selected_special_count)

func set_animation_state(next_state: int) -> void:
	selected_animation_state = clampi(next_state, AnimationStateType.State.IDLE, AnimationStateType.State.BLOCK)
	if hud != null:
		hud.set_animation_selection(selected_animation_state)

func set_target_character(index: int) -> void:
	selected_character_index = clampi(index, 0, maxi(characters.size() - 1, 0))
	_refresh_hud_appearance()

func apply_target_appearance(appearance: SpecialCharacterAppearance) -> bool:
	if characters.is_empty() or appearance == null:
		return false
	var applied := characters[selected_character_index].set_appearance(appearance)
	if applied:
		_refresh_hud_appearance()
	return applied

func randomize_target_appearance() -> void:
	if characters.is_empty() or registry == null:
		return
	randomizer.seed = deterministic_seed + selected_character_index * 101
	var appearance := AppearanceType.new()
	appearance.armor_id = _random_optional_id(DefinitionTypeSlot.ARMOR)
	appearance.helmet_id = _random_optional_id(DefinitionTypeSlot.HELMET)
	appearance.weapon_id = _random_optional_id(DefinitionTypeSlot.WEAPON)
	appearance.shield_id = _random_optional_id(DefinitionTypeSlot.SHIELD)
	var hair_ids := registry.ids_for_slot(DefinitionTypeSlot.HAIR)
	appearance.hair_id = hair_ids[randomizer.randi_range(0, hair_ids.size() - 1)]
	apply_target_appearance(appearance)

func begin_measurement() -> void:
	sample_frames = 0
	sample_frame_ms = 0.0
	sample_fps = 0.0
	sample_animation_cpu_ms = 0.0
	sample_draw_calls = 0.0
	sample_triangles = 0.0
	sample_nodes = 0.0
	sample_skeletons = 0.0
	sample_skinned_meshes = 0.0
	worst_frame_ms = 0.0
	sample_active = true

func end_measurement() -> Dictionary:
	sample_active = false
	var divisor: float = float(maxi(sample_frames, 1))
	return {
		"count": selected_special_count,
		"frames": sample_frames,
		"fps": sample_fps / divisor,
		"frame_ms": sample_frame_ms / divisor,
		"worst_frame_ms": worst_frame_ms,
		"animation_cpu_ms": sample_animation_cpu_ms / divisor,
		"draw_calls": int(sample_draw_calls / divisor),
		"triangles": int(sample_triangles / divisor),
		"character_nodes": sample_nodes / divisor,
		"skeletons": sample_skeletons / divisor,
		"skinned_meshes": sample_skinned_meshes / divisor,
		"materials": registry.material_count() if registry != null else 0
	}

func set_camera_state(new_position: Vector3, new_target: Vector3, orthographic_size: float) -> void:
	if camera == null:
		return
	camera.position = new_position
	camera_target = new_target
	camera.size = clampf(orthographic_size, 8.0, 180.0)
	camera.look_at(camera_target, Vector3.UP)

func capture_view(output_path: String) -> bool:
	var viewport_texture: ViewportTexture = get_viewport().get_texture()
	if viewport_texture == null:
		return false
	var image: Image = viewport_texture.get_image()
	if image == null or image.is_empty():
		return false
	var absolute_dir: String = ProjectSettings.globalize_path(output_path.get_base_dir())
	var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		return false
	return image.save_png(output_path) == OK

func get_character(index: int) -> SpecialCharacterVisual3D:
	if index < 0 or index >= characters.size():
		return null
	return characters[index]

func _build_characters(count: int) -> void:
	for character: SpecialCharacterVisual3D in characters:
		character.free()
	characters.clear()
	var columns: int = maxi(1, ceili(sqrt(float(count))))
	var spacing: float = 3.4
	for index: int in range(count):
		var character := VisualType.new()
		character.name = "SpecialCharacter_%03d" % index
		character.setup(registry, shared_animation_library)
		var column: int = index % columns
		var row: int = index / columns
		character.position = Vector3(
			(float(column) - float(columns - 1) * 0.5) * spacing,
			0.0,
			(float(row) - float((count + columns - 1) / columns - 1) * 0.5) * spacing
		)
		character.set_appearance(_appearance_for_index(index))
		add_child(character)
		characters.append(character)
	selected_character_index = clampi(selected_character_index, 0, maxi(characters.size() - 1, 0))

func _appearance_for_index(index: int) -> SpecialCharacterAppearance:
	var appearance := AppearanceType.new()
	match index % 4:
		0:
			appearance.armor_id = &"cloth_01"
			appearance.hair_id = &"hair_short_01"
			appearance.weapon_id = &"sword_01"
		1:
			appearance.armor_id = &"leather_01"
			appearance.hair_id = &"hair_long_01"
			appearance.weapon_id = &"sword_01"
			appearance.shield_id = &"shield_01"
		2:
			appearance.armor_id = &"plate_01"
			appearance.helmet_id = &"helmet_01"
			appearance.weapon_id = &"sword_01"
			appearance.shield_id = &"shield_01"
		_:
			appearance.armor_id = &"plate_01"
			appearance.hair_id = &"hair_long_01"
			appearance.weapon_id = &"sword_01"
			appearance.shield_id = &"shield_01"
	return appearance

func _random_optional_id(slot: int) -> StringName:
	var ids := registry.ids_for_slot(slot)
	if ids.is_empty() or randomizer.randi_range(0, 3) == 0:
		return &""
	return ids[randomizer.randi_range(0, ids.size() - 1)]

func _refresh_hud_appearance() -> void:
	if hud == null or characters.is_empty():
		return
	hud.set_target_character(selected_character_index, characters[selected_character_index].current_appearance)

func _count_nodes() -> int:
	var total := 0
	for character: SpecialCharacterVisual3D in characters:
		total += character.get_character_node_count()
	return total

func _count_skeletons() -> int:
	var total := 0
	for character: SpecialCharacterVisual3D in characters:
		total += character.get_skeleton_count()
	return total

func _count_skinned_meshes() -> int:
	var total := 0
	for character: SpecialCharacterVisual3D in characters:
		total += character.get_skinned_mesh_count()
	return total

func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	environment_node.name = "BenchmarkEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101b29")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8ca8b5")
	environment.ambient_light_energy = 0.75
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	add_child(environment_node)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-58.0, -32.0, 0.0)
	sun.light_color = Color("fff4d6")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	ground.name = "BenchmarkGround"
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(120.0, 120.0)
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("263c36")
	ground_material.roughness = 1.0
	ground_mesh.material = ground_material
	ground.mesh = ground_mesh
	ground.position.y = -0.08
	add_child(ground)

	camera = Camera3D.new()
	camera.name = "TacticalCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 24.0
	camera.near = 0.1
	camera.far = 400.0
	camera.position = Vector3(15.0, 19.0, 17.0)
	add_child(camera)
	camera.look_at(camera_target, Vector3.UP)
	camera.current = true

func _handle_camera_pan(delta: float) -> void:
	if camera == null:
		return
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		input.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input.x += 1.0
	if Input.is_key_pressed(KEY_W):
		input.y += 1.0
	if Input.is_key_pressed(KEY_S):
		input.y -= 1.0
	if input.length_squared() <= 0.0:
		return
	var forward: Vector3 = -camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var pan_speed: float = maxf(camera.size * 0.8, 8.0)
	var movement: Vector3 = (right * input.x + forward * input.y).normalized() * pan_speed * delta
	camera.position += movement
	camera_target += movement
	camera.look_at(camera_target, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and camera != null:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.size = clampf(camera.size * 0.85, 8.0, 180.0)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.size = clampf(camera.size * 1.18, 8.0, 180.0)

func _animation_name(state: int) -> StringName:
	return AnimationStateType.state_name(state)

enum DefinitionTypeSlot { BODY, HEAD, HAIR, ARMOR, HELMET, WEAPON, SHIELD }
