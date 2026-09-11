class_name CrowdBenchmarkController
extends Node3D

const BattleCrowdSimulationType = preload("res://scripts/benchmark/3d_crowd/battle_crowd_simulation.gd")
const CrowdRenderer3DType = preload("res://scripts/benchmark/3d_crowd/crowd_renderer_3d.gd")

const DEFAULT_SEED: int = 123456789
const INITIAL_SOLDIER_COUNT: int = 10000
const INITIAL_MODE: int = BattleCrowdSimulationType.BenchmarkMode.HUMANOID_LOD
const INITIAL_NEAR_ACTOR_BUDGET: int = 64

@onready var crowd_renderer: CrowdRenderer3D = $CrowdRenderer3D
@onready var hud: CrowdBenchmarkHUD = $CrowdBenchmarkHUD

var simulation: BattleCrowdSimulation
var camera: Camera3D
var camera_target: Vector3 = Vector3.ZERO
var selected_soldier_count: int = INITIAL_SOLDIER_COUNT
var selected_mode: int = INITIAL_MODE
var selected_near_actor_budget: int = INITIAL_NEAR_ACTOR_BUDGET
var deterministic_camera_motion: bool = false
var _camera_motion_time: float = 0.0

var _last_frame_ms: float = 0.0
var _last_simulation_ms: float = 0.0
var _last_renderer_ms: float = 0.0
var _last_draw_calls: int = 0
var _last_triangles: int = 0
var _sample_active: bool = false
var _sample_frames: int = 0
var _sample_frame_ms: float = 0.0
var _sample_fps: float = 0.0
var _sample_simulation_ms: float = 0.0
var _sample_renderer_ms: float = 0.0
var _sample_near_actor_cpu_ms: float = 0.0
var _sample_draw_calls: float = 0.0
var _sample_triangles: float = 0.0
var _sample_near: float = 0.0
var _sample_mid: float = 0.0
var _sample_far: float = 0.0
var _sample_visible_chunks: float = 0.0
var _sample_visible_soldiers: float = 0.0
var _sample_skeletons: float = 0.0
var _sample_animation_players: float = 0.0
var _sample_multimesh_groups: float = 0.0
var _sample_multimesh_instances: float = 0.0
var _sample_dirty_chunks: float = 0.0
var _sample_transform_dirty_instances: float = 0.0
var _sample_animation_dirty_instances: float = 0.0
var _sample_visual_dirty_instances: float = 0.0
var _sample_structural_changes: float = 0.0
var _sample_upload_calls: float = 0.0
var _sample_instances_uploaded: float = 0.0
var _sample_bytes_uploaded: float = 0.0
var _sample_bulk_upload_calls: float = 0.0
var _sample_chunk_migrations: float = 0.0
var _sample_multimesh_upload_cpu_ms: float = 0.0
var _sample_buffer_prepare_cpu_ms: float = 0.0
var _sample_buffer_prepare_frames: int = 0
var _worst_frame_ms: float = 0.0

func _ready() -> void:
	_build_world()
	simulation = BattleCrowdSimulationType.new()
	simulation.initialize(DEFAULT_SEED)
	crowd_renderer.initialize(simulation)
	hud.count_requested.connect(set_soldier_count)
	hud.mode_requested.connect(set_benchmark_mode)
	hud.near_budget_requested.connect(set_near_actor_budget)
	hud.reset_requested.connect(reset_deterministic_state)
	set_soldier_count(INITIAL_SOLDIER_COUNT)
	set_benchmark_mode(INITIAL_MODE)
	set_near_actor_budget(INITIAL_NEAR_ACTOR_BUDGET)
	hud.set_count_selection(selected_soldier_count)
	hud.set_mode_selection(selected_mode)
	hud.set_near_budget_selection(selected_near_actor_budget)

func _process(delta: float) -> void:
	if deterministic_camera_motion:
		_camera_motion_time += delta
		var orbit_angle: float = _camera_motion_time * 0.16
		set_camera_state(
			Vector3(cos(orbit_angle) * 30.0, 20.0, sin(orbit_angle) * 30.0),
			Vector3.ZERO,
			110.0
		)
	_handle_camera_pan(delta)
	var simulation_started_usec: int = Time.get_ticks_usec()
	simulation.step(delta)
	_last_simulation_ms = float(Time.get_ticks_usec() - simulation_started_usec) / 1000.0
	var renderer_started_usec: int = Time.get_ticks_usec()
	crowd_renderer.sync_from_simulation(camera)
	_last_renderer_ms = float(Time.get_ticks_usec() - renderer_started_usec) / 1000.0
	_last_frame_ms = maxf(delta * 1000.0, 0.001)
	_worst_frame_ms = maxf(_worst_frame_ms, _last_frame_ms)
	var viewport_fps: float = 1000.0 / _last_frame_ms
	_last_draw_calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_last_triangles = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	hud.update_metrics(
		viewport_fps,
		_last_frame_ms,
		simulation.active_soldier_count,
		simulation.active_formation_count,
		crowd_renderer.near_actor_count,
		crowd_renderer.mid_soldier_count,
		crowd_renderer.far_soldier_count,
		crowd_renderer.visible_chunk_count,
		crowd_renderer.visible_soldier_count,
		crowd_renderer.allocated_skeleton_count(),
		crowd_renderer.active_skeleton_count(),
		crowd_renderer.allocated_animation_player_count(),
		crowd_renderer.multimesh_group_count,
		crowd_renderer.multimesh_instance_count,
		_last_simulation_ms,
		_last_renderer_ms,
		crowd_renderer.last_near_actor_cpu_ms,
		crowd_renderer.last_dirty_chunk_count,
		crowd_renderer.last_transform_dirty_instances,
		crowd_renderer.last_animation_dirty_instances,
		crowd_renderer.last_visual_dirty_instances,
		crowd_renderer.last_structural_change_count,
		crowd_renderer.last_multimesh_upload_calls,
		crowd_renderer.last_instances_uploaded,
		crowd_renderer.last_bytes_uploaded,
		_last_draw_calls,
		_last_triangles,
		_mode_name(selected_mode),
		simulation.seed,
		CrowdRenderer3DType.CROWD_CHUNK_SIZE,
		selected_near_actor_budget
	)
	if _sample_active:
		_sample_frames += 1
		_sample_frame_ms += _last_frame_ms
		_sample_fps += viewport_fps
		_sample_simulation_ms += _last_simulation_ms
		_sample_renderer_ms += _last_renderer_ms
		_sample_near_actor_cpu_ms += crowd_renderer.last_near_actor_cpu_ms
		_sample_draw_calls += float(_last_draw_calls)
		_sample_triangles += float(_last_triangles)
		_sample_near += float(crowd_renderer.near_actor_count)
		_sample_mid += float(crowd_renderer.mid_soldier_count)
		_sample_far += float(crowd_renderer.far_soldier_count)
		_sample_visible_chunks += float(crowd_renderer.visible_chunk_count)
		_sample_visible_soldiers += float(crowd_renderer.visible_soldier_count)
		_sample_skeletons += float(crowd_renderer.allocated_skeleton_count())
		_sample_animation_players += float(crowd_renderer.allocated_animation_player_count())
		_sample_multimesh_groups += float(crowd_renderer.multimesh_group_count)
		_sample_multimesh_instances += float(crowd_renderer.multimesh_instance_count)
		_sample_dirty_chunks += float(crowd_renderer.last_dirty_chunk_count)
		_sample_transform_dirty_instances += float(crowd_renderer.last_transform_dirty_instances)
		_sample_animation_dirty_instances += float(crowd_renderer.last_animation_dirty_instances)
		_sample_visual_dirty_instances += float(crowd_renderer.last_visual_dirty_instances)
		_sample_structural_changes += float(crowd_renderer.last_structural_change_count)
		_sample_upload_calls += float(crowd_renderer.last_multimesh_upload_calls)
		_sample_instances_uploaded += float(crowd_renderer.last_instances_uploaded)
		_sample_bytes_uploaded += float(crowd_renderer.last_bytes_uploaded)
		_sample_bulk_upload_calls += float(crowd_renderer.last_bulk_upload_calls)
		_sample_chunk_migrations += float(crowd_renderer.last_chunk_migration_count)
		_sample_multimesh_upload_cpu_ms += crowd_renderer.last_multimesh_upload_cpu_ms
		if crowd_renderer.last_transform_preparation_cpu_ms >= 0.0:
			_sample_buffer_prepare_cpu_ms += crowd_renderer.last_transform_preparation_cpu_ms
			_sample_buffer_prepare_frames += 1

func set_soldier_count(requested_count: int) -> void:
	var valid_counts: Array[int] = [1000, 2500, 5000, 10000]
	var nearest_count: int = valid_counts[0]
	for candidate: int in valid_counts:
		if abs(candidate - requested_count) < abs(nearest_count - requested_count):
			nearest_count = candidate
	selected_soldier_count = nearest_count
	if simulation != null:
		simulation.set_active_soldiers(selected_soldier_count)
		crowd_renderer.invalidate_layout()
	if hud != null:
		hud.set_count_selection(selected_soldier_count)

func set_benchmark_mode(next_mode: int) -> void:
	selected_mode = clampi(next_mode, BattleCrowdSimulationType.BenchmarkMode.PLACEHOLDER, BattleCrowdSimulationType.BenchmarkMode.HUMANOID_LOD)
	if simulation != null:
		simulation.set_mode(selected_mode)
		crowd_renderer.invalidate_layout()
	if hud != null:
		hud.set_mode_selection(selected_mode)

func set_near_actor_budget(next_budget: int) -> void:
	var valid_budgets: Array[int] = [0, 64, 128, 256]
	var nearest_budget: int = valid_budgets[0]
	for candidate: int in valid_budgets:
		if abs(candidate - next_budget) < abs(nearest_budget - next_budget):
			nearest_budget = candidate
	selected_near_actor_budget = nearest_budget
	if crowd_renderer != null:
		crowd_renderer.set_near_actor_budget(selected_near_actor_budget)
	if hud != null:
		hud.set_near_budget_selection(selected_near_actor_budget)

func reset_deterministic_state() -> void:
	simulation.initialize(DEFAULT_SEED)
	set_soldier_count(INITIAL_SOLDIER_COUNT)
	set_benchmark_mode(INITIAL_MODE)
	set_near_actor_budget(INITIAL_NEAR_ACTOR_BUDGET)
	crowd_renderer.invalidate_layout()
	_camera_motion_time = 0.0

func set_renderer_profile(profile: String) -> void:
	match profile.to_lower():
		"baseline":
			crowd_renderer.configure_update_profile(false, false, false, false)
		"dirty_transform":
			crowd_renderer.configure_update_profile(true, false, false, false)
		"dirty_event":
			crowd_renderer.configure_update_profile(true, true, false, false)
		"stable_event", "stable_slots":
			crowd_renderer.configure_update_profile(true, true, false, true)
		"combined", "combined_bulk", "bulk":
			crowd_renderer.configure_update_profile(true, true, true, true)
		_:
			crowd_renderer.configure_update_profile(true, true, false, true)

func set_deterministic_camera_motion(enabled: bool) -> void:
	deterministic_camera_motion = enabled
	_camera_motion_time = 0.0

func set_camera_state(new_position: Vector3, new_target: Vector3, orthographic_size: float) -> void:
	if camera == null:
		return
	camera.position = new_position
	camera_target = new_target
	camera.size = clampf(orthographic_size, 18.0, 420.0)
	camera.look_at(camera_target, Vector3.UP)

func begin_measurement() -> void:
	_sample_frames = 0
	_sample_frame_ms = 0.0
	_sample_fps = 0.0
	_sample_simulation_ms = 0.0
	_sample_renderer_ms = 0.0
	_sample_near_actor_cpu_ms = 0.0
	_sample_draw_calls = 0.0
	_sample_triangles = 0.0
	_sample_near = 0.0
	_sample_mid = 0.0
	_sample_far = 0.0
	_sample_visible_chunks = 0.0
	_sample_visible_soldiers = 0.0
	_sample_skeletons = 0.0
	_sample_animation_players = 0.0
	_sample_multimesh_groups = 0.0
	_sample_multimesh_instances = 0.0
	_sample_dirty_chunks = 0.0
	_sample_transform_dirty_instances = 0.0
	_sample_animation_dirty_instances = 0.0
	_sample_visual_dirty_instances = 0.0
	_sample_structural_changes = 0.0
	_sample_upload_calls = 0.0
	_sample_instances_uploaded = 0.0
	_sample_bytes_uploaded = 0.0
	_sample_bulk_upload_calls = 0.0
	_sample_chunk_migrations = 0.0
	_sample_multimesh_upload_cpu_ms = 0.0
	_sample_buffer_prepare_cpu_ms = 0.0
	_sample_buffer_prepare_frames = 0
	_worst_frame_ms = 0.0
	_sample_active = true

func end_measurement() -> Dictionary:
	_sample_active = false
	var divisor: float = float(maxi(_sample_frames, 1))
	return {
		"mode": _mode_name(selected_mode),
		"soldiers": selected_soldier_count,
		"formations": simulation.active_formation_count,
		"frames": _sample_frames,
		"fps": _sample_fps / divisor,
		"frame_ms": _sample_frame_ms / divisor,
		"worst_frame_ms": _worst_frame_ms,
		"simulation_ms": _sample_simulation_ms / divisor,
		"renderer_ms": _sample_renderer_ms / divisor,
		"near_actor_cpu_ms": _sample_near_actor_cpu_ms / divisor,
		"near": _sample_near / divisor,
		"mid": _sample_mid / divisor,
		"far": _sample_far / divisor,
		"visible_chunks": _sample_visible_chunks / divisor,
		"visible_soldiers": _sample_visible_soldiers / divisor,
		"skeletons": _sample_skeletons / divisor,
		"animation_players": _sample_animation_players / divisor,
		"multimesh_groups": _sample_multimesh_groups / divisor,
		"multimesh_instances": _sample_multimesh_instances / divisor,
		"dirty_chunks": _sample_dirty_chunks / divisor,
		"transform_dirty_instances": _sample_transform_dirty_instances / divisor,
		"animation_dirty_instances": _sample_animation_dirty_instances / divisor,
		"visual_dirty_instances": _sample_visual_dirty_instances / divisor,
		"structural_changes": _sample_structural_changes / divisor,
		"chunk_migrations": _sample_chunk_migrations / divisor,
		"upload_calls": _sample_upload_calls / divisor,
		"instances_uploaded": _sample_instances_uploaded / divisor,
		"bytes_uploaded": _sample_bytes_uploaded / divisor,
		"bulk_upload_calls": _sample_bulk_upload_calls / divisor,
		"multimesh_upload_cpu_ms": _sample_multimesh_upload_cpu_ms / divisor,
		"buffer_prepare_cpu_ms": (
			_sample_buffer_prepare_cpu_ms / float(_sample_buffer_prepare_frames)
			if _sample_buffer_prepare_frames > 0
			else -1.0
		),
		"update_profile": crowd_renderer.update_profile_name(),
		"draw_calls": int(_sample_draw_calls / divisor),
		"triangles": int(_sample_triangles / divisor)
	}

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

func _build_world() -> void:
	var environment_node := WorldEnvironment.new()
	environment_node.name = "BenchmarkEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("101b29")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("8ca8b5")
	environment.ambient_light_energy = 0.7
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
	ground_mesh.size = Vector2(420.0, 420.0)
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
	camera.size = 350.0
	camera.near = 0.1
	camera.far = 1000.0
	camera.position = Vector3(180.0, 230.0, 210.0)
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
	var pan_speed: float = maxf(camera.size * 0.8, 40.0)
	var movement: Vector3 = (right * input.x + forward * input.y).normalized() * pan_speed * delta
	camera.position += movement
	camera_target += movement
	camera.look_at(camera_target, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.size = clampf(camera.size * 0.85, 18.0, 420.0)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.size = clampf(camera.size * 1.18, 18.0, 420.0)

func _mode_name(mode: int) -> String:
	match mode:
		BattleCrowdSimulationType.BenchmarkMode.PLACEHOLDER:
			return "Placeholder"
		BattleCrowdSimulationType.BenchmarkMode.HUMANOID_STATIC:
			return "Humanoid Static"
		BattleCrowdSimulationType.BenchmarkMode.HUMANOID_ANIMATED:
			return "Humanoid Animated"
		_:
			return "Humanoid LOD"
