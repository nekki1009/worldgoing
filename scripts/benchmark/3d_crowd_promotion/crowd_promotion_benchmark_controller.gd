class_name CrowdPromotionBenchmarkController
extends Node3D

const BattleCrowdSimulationType = preload("res://scripts/benchmark/3d_crowd/battle_crowd_simulation.gd")
const CrowdRenderer3DType = preload("res://scripts/benchmark/3d_crowd/crowd_renderer_3d.gd")
const CrowdPromotionPolicyType = preload("res://scripts/benchmark/3d_crowd/crowd_promotion_policy.gd")
const CrowdSpecialActorPoolType = preload("res://scripts/benchmark/3d_crowd/crowd_special_actor_pool.gd")
const SpecialRegistryType = preload("res://scripts/benchmark/3d_special/special_character_visual_registry.gd")
const SpecialAnimationLibraryType = preload("res://scripts/benchmark/3d_special/special_human_animation_library.gd")
const SpecialRenderModeType = preload("res://scripts/benchmark/3d_special/special_character_render_mode.gd")
const SpecialShadowBudgetType = preload("res://scripts/benchmark/3d_special/special_shadow_budget.gd")

const DEFAULT_SEED: int = 123456789
const TOTAL_SOLDIERS: int = 10000
const INITIAL_NEAR_BUDGET: int = 64
const MAX_NEAR_ACTORS: int = 128
const VALID_NEAR_BUDGETS: Array[int] = [0, 16, 32, 64, 128]

@onready var crowd_renderer: CrowdRenderer3D = $CrowdRenderer3D
@onready var actor_pool: CrowdSpecialActorPool = $CrowdSpecialActorPool
@onready var hud: CrowdPromotionBenchmarkHUD = $CrowdPromotionHUD

var simulation: BattleCrowdSimulation
var promotion_policy: CrowdPromotionPolicy
var special_registry: SpecialCharacterVisualRegistry
var shared_special_animation_library: AnimationLibrary
var camera: Camera3D
var camera_target: Vector3 = Vector3.ZERO
var selected_near_budget: int = INITIAL_NEAR_BUDGET
var deterministic_seed: int = DEFAULT_SEED
var simulation_paused: bool = false
var near_animation_enabled: bool = true
var near_equipment_visible: bool = true
var near_shadows_enabled: bool = true
var near_animation_stride: int = 1
var special_render_mode: int = SpecialRenderModeType.Mode.MODULAR
var special_lod0_distance: float = 42.0
var max_special_lod0: int = 24
var special_rigid_batch_enabled: bool = false
var special_rigid_material_consolidation: bool = false
var special_shadow_budget_mode: int = SpecialShadowBudgetType.Mode.ALL
var special_max_full_shadow_actors: int = 24
var special_rigid_socket_update_stride: int = 1
var deterministic_camera_motion_enabled: bool = false
var deterministic_camera_motion_time: float = 0.0
var spike_threshold_ms: float = 33.0
var selected_crowd_render_path: int = CrowdRenderer3DType.RenderPath.CURRENT_PER_INSTANCE

var last_frame_ms: float = 0.0
var last_simulation_ms: float = 0.0
var last_policy_ms: float = 0.0
var last_pool_ms: float = 0.0
var last_animation_ms: float = 0.0
var last_promotion_ms: float = 0.0
var last_renderer_ms: float = 0.0
var last_draw_calls: int = 0
var last_triangles: int = 0
var worst_frame_ms: float = 0.0
var sample_frame_times: Array[float] = []
var spike_trace: Array[Dictionary] = []
var spike_count: int = 0

var _sample_active: bool = false
var _sample_frames: int = 0
var _sample_frame_ms: float = 0.0
var _sample_fps: float = 0.0
var _sample_simulation_ms: float = 0.0
var _sample_policy_ms: float = 0.0
var _sample_pool_ms: float = 0.0
var _sample_animation_ms: float = 0.0
var _sample_promotion_ms: float = 0.0
var _sample_renderer_ms: float = 0.0
var _sample_near: float = 0.0
var _sample_promotions: float = 0.0
var _sample_demotions: float = 0.0
var _sample_draw_calls: float = 0.0
var _sample_triangles: float = 0.0
var _sample_visible_chunks: float = 0.0
var _sample_visible_crowd_instances: float = 0.0
var _sample_visible_soldiers: float = 0.0
var _sample_updated_chunks: float = 0.0
var _sample_updated_transform_instances: float = 0.0
var _sample_updated_custom_instances: float = 0.0
var _sample_formation_transform_updates: float = 0.0
var _sample_instance_transform_updates: float = 0.0
var _sample_instance_transform_constructions: float = 0.0
var _sample_instance_basis_constructions: float = 0.0
var _sample_formation_custom_updates: float = 0.0
var _sample_formation_slot_rebuilds: float = 0.0
var _sample_formation_slot_transform_writes: float = 0.0
var _sample_formation_structural_changes: float = 0.0
var _sample_formation_transform_cpu_ms: float = 0.0
var _sample_gdscript_crowd_loop_cpu_ms: float = 0.0
var _sample_transform_preparation_cpu_ms: float = 0.0
var _sample_transform_preparation_frames: int = 0
var _sample_simulation_world_position_updates: float = 0.0
var _sample_lazy_world_position_queries: float = 0.0
var _sample_simulation_formation_updates: float = 0.0
var _sample_simulation_basis_constructions: float = 0.0
var _sample_rigid_batch_cpu_ms: float = 0.0
var _sample_rigid_transform_updates: float = 0.0
var _sample_rigid_upload_calls: float = 0.0
var _sample_rigid_buffer_upload_calls: float = 0.0
var _sample_rigid_bytes_uploaded: float = 0.0
var _sample_rigid_structural_changes: float = 0.0
var _sample_lod_transitions: float = 0.0
var _sample_shadow_transitions: float = 0.0

func _ready() -> void:
	_build_world()
	simulation = BattleCrowdSimulationType.new()
	simulation.initialize(deterministic_seed)
	simulation.set_active_soldiers(TOTAL_SOLDIERS)
	simulation.set_mode(BattleCrowdSimulationType.BenchmarkMode.HUMANOID_LOD)
	promotion_policy = CrowdPromotionPolicyType.new()
	promotion_policy.prepare(simulation, MAX_NEAR_ACTORS)
	special_registry = SpecialRegistryType.new()
	shared_special_animation_library = SpecialAnimationLibraryType.build_library()
	var cold_bundle_cache: bool = OS.get_cmdline_user_args().has("--cold-cache")
	actor_pool.initialize(
		 special_registry, shared_special_animation_library, MAX_NEAR_ACTORS,
		 not cold_bundle_cache, cold_bundle_cache
	)
	actor_pool.set_render_lod_parameters(special_lod0_distance, max_special_lod0)
	actor_pool.set_rigid_render_options(
		special_rigid_batch_enabled,
		special_rigid_material_consolidation,
		special_shadow_budget_mode,
		special_max_full_shadow_actors,
		special_rigid_socket_update_stride
	)
	# The legacy Crowd pool stays disabled here. The new SPECIAL pool is the
	# only Near representation, while the external mask removes its ids from
	# the existing MultiMesh groups without changing simulation ownership.
	crowd_renderer.initialize(simulation)
	crowd_renderer.set_near_actor_budget(0)
	if hud != null:
		hud.setup(self)
	set_near_actor_budget(INITIAL_NEAR_BUDGET)
	focus_on_soldier(0, 42.0)

func _process(delta: float) -> void:
	_handle_camera_pan(delta)
	if deterministic_camera_motion_enabled:
		_apply_deterministic_camera_motion(delta)
	var simulation_started_usec: int = Time.get_ticks_usec()
	simulation.reset_world_position_query_count()
	if not simulation_paused:
		simulation.step(delta)
	last_simulation_ms = float(Time.get_ticks_usec() - simulation_started_usec) / 1000.0

	var desired_slots: PackedInt32Array
	var policy_started_usec: int = Time.get_ticks_usec()
	desired_slots = promotion_policy.resolve(
		simulation,
		camera.global_position if camera != null else Vector3.ZERO,
		actor_pool.get_slot_soldier_ids()
	)
	last_policy_ms = float(Time.get_ticks_usec() - policy_started_usec) / 1000.0

	var pool_started_usec: int = Time.get_ticks_usec()
	actor_pool.sync_from_simulation(
		desired_slots,
		simulation,
		camera.global_position if camera != null else Vector3.ZERO
	)
	last_pool_ms = float(Time.get_ticks_usec() - pool_started_usec) / 1000.0
	last_animation_ms = actor_pool.last_animation_cpu_ms
	last_promotion_ms = actor_pool.last_transition_cpu_ms

	# This is the only bridge into the existing crowd renderer: promoted ids
	# are omitted from its MultiMesh layout in the same frame that actors show.
	crowd_renderer.set_external_near_soldiers(desired_slots, selected_near_budget)
	var renderer_started_usec: int = Time.get_ticks_usec()
	crowd_renderer.sync_from_simulation(camera)
	last_renderer_ms = float(Time.get_ticks_usec() - renderer_started_usec) / 1000.0

	last_frame_ms = maxf(delta * 1000.0, 0.001)
	worst_frame_ms = maxf(worst_frame_ms, last_frame_ms)
	if _sample_active:
		sample_frame_times.append(last_frame_ms)
	if last_frame_ms >= spike_threshold_ms:
		spike_count += 1
		if spike_trace.size() < 32:
			spike_trace.append({
				"frame_ms": last_frame_ms,
				"promotions": actor_pool.promotions_this_frame,
				"demotions": actor_pool.demotions_this_frame,
				"bundle_cache_misses": actor_pool.bundle_cache_misses,
				"rigid_structural_changes": actor_pool.rigid_structural_changes_this_frame,
				"lod_transitions": actor_pool.lod_transitions_this_frame,
				"shadow_transitions": actor_pool.shadow_transitions_this_frame,
				"pool_ms": last_pool_ms,
				"rigid_batch_ms": actor_pool.last_rigid_batch_cpu_ms
			})
	var viewport_fps: float = 1000.0 / last_frame_ms
	last_draw_calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	last_triangles = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if hud != null:
		hud.update_metrics(_metrics_dictionary(viewport_fps))
	if _sample_active:
		_sample_frames += 1
		_sample_frame_ms += last_frame_ms
		_sample_fps += viewport_fps
		_sample_simulation_ms += last_simulation_ms
		_sample_policy_ms += last_policy_ms
		_sample_pool_ms += last_pool_ms
		_sample_animation_ms += last_animation_ms
		_sample_promotion_ms += last_promotion_ms
		_sample_renderer_ms += last_renderer_ms
		_sample_near += float(actor_pool.active_actor_count)
		_sample_promotions += float(actor_pool.promotions_this_frame)
		_sample_demotions += float(actor_pool.demotions_this_frame)
		_sample_draw_calls += float(last_draw_calls)
		_sample_triangles += float(last_triangles)
		_sample_visible_chunks += float(crowd_renderer.visible_chunk_count)
		_sample_visible_crowd_instances += float(crowd_renderer.visible_crowd_instance_count)
		_sample_visible_soldiers += float(crowd_renderer.visible_soldier_count)
		_sample_updated_chunks += float(crowd_renderer.last_updated_chunk_count)
		_sample_updated_transform_instances += float(crowd_renderer.last_updated_transform_instances)
		_sample_updated_custom_instances += float(crowd_renderer.last_updated_custom_instances)
		_sample_formation_transform_updates += float(crowd_renderer.last_formation_transform_updates)
		_sample_instance_transform_updates += float(crowd_renderer.last_instance_transform_updates)
		_sample_instance_transform_constructions += float(crowd_renderer.last_instance_transform_constructions)
		_sample_instance_basis_constructions += float(crowd_renderer.last_instance_basis_constructions)
		_sample_formation_custom_updates += float(crowd_renderer.last_formation_custom_data_updates)
		_sample_formation_slot_rebuilds += float(crowd_renderer.last_formation_local_slot_rebuilds)
		_sample_formation_slot_transform_writes += float(crowd_renderer.last_formation_slot_transform_writes)
		_sample_formation_structural_changes += float(crowd_renderer.last_formation_structural_changes)
		_sample_formation_transform_cpu_ms += crowd_renderer.last_formation_transform_cpu_ms
		_sample_gdscript_crowd_loop_cpu_ms += crowd_renderer.last_gdscript_crowd_loop_cpu_ms
		if crowd_renderer.last_transform_preparation_cpu_ms >= 0.0:
			_sample_transform_preparation_cpu_ms += crowd_renderer.last_transform_preparation_cpu_ms
			_sample_transform_preparation_frames += 1
		_sample_simulation_world_position_updates += float(simulation.last_world_position_updates)
		_sample_lazy_world_position_queries += float(simulation.lazy_world_position_queries)
		_sample_simulation_formation_updates += float(simulation.last_formation_transform_updates)
		_sample_simulation_basis_constructions += float(simulation.last_basis_constructions)
		_sample_rigid_batch_cpu_ms += actor_pool.last_rigid_batch_cpu_ms
		_sample_rigid_transform_updates += float(actor_pool.last_rigid_transform_updates)
		_sample_rigid_upload_calls += float(actor_pool.last_rigid_upload_calls)
		_sample_rigid_buffer_upload_calls += float(actor_pool.last_rigid_buffer_upload_calls)
		_sample_rigid_bytes_uploaded += float(actor_pool.last_rigid_bytes_uploaded)
		_sample_rigid_structural_changes += float(actor_pool.rigid_structural_changes_this_frame)
		_sample_lod_transitions += float(actor_pool.lod_transitions_this_frame)
		_sample_shadow_transitions += float(actor_pool.shadow_transitions_this_frame)

func set_near_actor_budget(requested_budget: int) -> void:
	var nearest_budget: int = VALID_NEAR_BUDGETS[0]
	for candidate: int in VALID_NEAR_BUDGETS:
		if abs(candidate - requested_budget) < abs(nearest_budget - requested_budget):
			nearest_budget = candidate
	selected_near_budget = nearest_budget
	if promotion_policy != null:
		promotion_policy.max_near_actors = selected_near_budget
		promotion_policy.prepare(simulation, selected_near_budget)
	if hud != null:
		hud.set_budget_selection(selected_near_budget)

func set_crowd_mode(next_mode: int) -> void:
	if simulation == null:
		return
	simulation.set_mode(next_mode)
	crowd_renderer.invalidate_layout()

func set_crowd_render_path(next_path: int) -> void:
	selected_crowd_render_path = clampi(
		next_path,
		CrowdRenderer3DType.RenderPath.CURRENT_PER_INSTANCE,
		CrowdRenderer3DType.RenderPath.FORMATION_PARENT_TRANSFORM
	)
	if crowd_renderer != null:
		crowd_renderer.set_render_path(selected_crowd_render_path)
	if simulation != null:
		simulation.set_world_position_cache_enabled(
			selected_crowd_render_path != CrowdRenderer3DType.RenderPath.FORMATION_PARENT_TRANSFORM
		)

func set_near_render_options(
	animation_enabled: bool,
	equipment_visible: bool,
	shadows_enabled: bool,
	animation_stride: int = 1
) -> void:
	near_animation_enabled = animation_enabled
	near_equipment_visible = equipment_visible
	near_shadows_enabled = shadows_enabled
	near_animation_stride = clampi(animation_stride, 0, 4)
	if actor_pool == null:
		return
	actor_pool.set_animation_enabled(near_animation_enabled)
	actor_pool.set_animation_update_stride(near_animation_stride)
	actor_pool.set_equipment_visible(near_equipment_visible)
	actor_pool.set_shadows_enabled(near_shadows_enabled)

func set_special_render_mode(next_mode: int) -> void:
	special_render_mode = clampi(next_mode, SpecialRenderModeType.Mode.MODULAR, SpecialRenderModeType.Mode.BUNDLE_LOD)
	if actor_pool != null:
		actor_pool.set_render_mode(special_render_mode)
		actor_pool.set_render_lod_parameters(special_lod0_distance, max_special_lod0)

func set_special_lod_parameters(lod0_distance: float, max_lod0: int) -> void:
	special_lod0_distance = maxf(lod0_distance, 0.0)
	max_special_lod0 = maxi(max_lod0, 0)
	if actor_pool != null:
		actor_pool.set_render_lod_parameters(special_lod0_distance, max_special_lod0)

func set_special_rigid_render_options(
	use_batch: bool,
	use_material_consolidation: bool,
	shadow_mode: int = SpecialShadowBudgetType.Mode.ALL,
	max_full_shadow_actors: int = 24,
	socket_update_stride: int = 1
) -> void:
	special_rigid_batch_enabled = use_batch
	special_rigid_material_consolidation = use_material_consolidation
	special_shadow_budget_mode = shadow_mode
	special_max_full_shadow_actors = maxi(max_full_shadow_actors, 0)
	special_rigid_socket_update_stride = clampi(socket_update_stride, 1, 4)
	if actor_pool != null:
		actor_pool.set_rigid_render_options(
			special_rigid_batch_enabled,
			special_rigid_material_consolidation,
			special_shadow_budget_mode,
			special_max_full_shadow_actors,
			special_rigid_socket_update_stride
		)

func set_deterministic_camera_motion(enabled: bool) -> void:
	deterministic_camera_motion_enabled = enabled
	deterministic_camera_motion_time = 0.0

func get_near_render_stats() -> Dictionary:
	return actor_pool.render_stats() if actor_pool != null else {}

func set_simulation_paused(paused: bool) -> void:
	simulation_paused = paused

func focus_on_soldier(soldier_id: int, orthographic_size: float = 42.0) -> void:
	if simulation == null or camera == null:
		return
	var bounded_id: int = clampi(soldier_id, 0, maxi(simulation.active_soldier_count - 1, 0))
	var target: Vector3 = simulation.get_soldier_world_position(bounded_id)
	set_camera_state(target + Vector3(12.0, 16.0, 12.0), target, orthographic_size)

func set_camera_state(new_position: Vector3, new_target: Vector3, orthographic_size: float) -> void:
	if camera == null:
		return
	camera.position = new_position
	camera_target = new_target
	camera.size = clampf(orthographic_size, 18.0, 420.0)
	camera.look_at(camera_target, Vector3.UP)

func reset_deterministic_state() -> void:
	simulation.initialize(deterministic_seed)
	simulation.set_active_soldiers(TOTAL_SOLDIERS)
	simulation.set_mode(BattleCrowdSimulationType.BenchmarkMode.HUMANOID_LOD)
	simulation.set_world_position_cache_enabled(
		selected_crowd_render_path != CrowdRenderer3DType.RenderPath.FORMATION_PARENT_TRANSFORM
	)
	actor_pool.clear_all()
	actor_pool.set_render_mode(special_render_mode)
	actor_pool.set_rigid_render_options(
		special_rigid_batch_enabled,
		special_rigid_material_consolidation,
		special_shadow_budget_mode,
		special_max_full_shadow_actors,
		special_rigid_socket_update_stride
	)
	promotion_policy.prepare(simulation, selected_near_budget)
	crowd_renderer.set_render_path(selected_crowd_render_path)
	crowd_renderer.invalidate_layout()
	focus_on_soldier(0, 42.0)

func begin_measurement() -> void:
	_sample_active = true
	_sample_frames = 0
	_sample_frame_ms = 0.0
	_sample_fps = 0.0
	_sample_simulation_ms = 0.0
	_sample_policy_ms = 0.0
	_sample_pool_ms = 0.0
	_sample_animation_ms = 0.0
	_sample_promotion_ms = 0.0
	_sample_renderer_ms = 0.0
	_sample_near = 0.0
	_sample_promotions = 0.0
	_sample_demotions = 0.0
	_sample_draw_calls = 0.0
	_sample_triangles = 0.0
	_sample_visible_chunks = 0.0
	_sample_visible_crowd_instances = 0.0
	_sample_visible_soldiers = 0.0
	_sample_updated_chunks = 0.0
	_sample_updated_transform_instances = 0.0
	_sample_updated_custom_instances = 0.0
	_sample_formation_transform_updates = 0.0
	_sample_instance_transform_updates = 0.0
	_sample_instance_transform_constructions = 0.0
	_sample_instance_basis_constructions = 0.0
	_sample_formation_custom_updates = 0.0
	_sample_formation_slot_rebuilds = 0.0
	_sample_formation_slot_transform_writes = 0.0
	_sample_formation_structural_changes = 0.0
	_sample_formation_transform_cpu_ms = 0.0
	_sample_gdscript_crowd_loop_cpu_ms = 0.0
	_sample_transform_preparation_cpu_ms = 0.0
	_sample_transform_preparation_frames = 0
	_sample_simulation_world_position_updates = 0.0
	_sample_lazy_world_position_queries = 0.0
	_sample_simulation_formation_updates = 0.0
	_sample_simulation_basis_constructions = 0.0
	_sample_rigid_batch_cpu_ms = 0.0
	_sample_rigid_transform_updates = 0.0
	_sample_rigid_upload_calls = 0.0
	_sample_rigid_buffer_upload_calls = 0.0
	_sample_rigid_bytes_uploaded = 0.0
	_sample_rigid_structural_changes = 0.0
	_sample_lod_transitions = 0.0
	_sample_shadow_transitions = 0.0
	sample_frame_times.clear()
	spike_trace.clear()
	spike_count = 0
	worst_frame_ms = 0.0

func end_measurement() -> Dictionary:
	_sample_active = false
	var divisor: float = float(maxi(_sample_frames, 1))
	var sorted_frame_times: Array[float] = sample_frame_times.duplicate()
	sorted_frame_times.sort()
	var percentile_index: int = clampi(ceili(float(sorted_frame_times.size()) * 0.95) - 1, 0, maxi(sorted_frame_times.size() - 1, 0))
	var percentile_95: float = sorted_frame_times[percentile_index] if not sorted_frame_times.is_empty() else 0.0
	var measured_seconds: float = _sample_frame_ms / 1000.0
	var near_stats: Dictionary = actor_pool.render_stats()
	return {
		"frames": _sample_frames,
		"fps": _sample_fps / divisor,
		"frame_ms": _sample_frame_ms / divisor,
		"worst_frame_ms": worst_frame_ms,
		"p95_frame_ms": percentile_95,
		"simulation_ms": _sample_simulation_ms / divisor,
		"policy_ms": _sample_policy_ms / divisor,
		"pool_ms": _sample_pool_ms / divisor,
		"animation_ms": _sample_animation_ms / divisor,
		"promotion_ms": _sample_promotion_ms / divisor,
		"renderer_ms": _sample_renderer_ms / divisor,
		"near": _sample_near / divisor,
		"promotions_per_frame": _sample_promotions / divisor,
		"demotions_per_frame": _sample_demotions / divisor,
		"draw_calls": int(_sample_draw_calls / divisor),
		"triangles": int(_sample_triangles / divisor),
		"visible_chunks": _sample_visible_chunks / divisor,
		"visible_crowd_instances": _sample_visible_crowd_instances / divisor,
		"visible_soldiers": _sample_visible_soldiers / divisor,
		"allocated_actors": actor_pool.allocated_actors.size(),
		"allocated_skeletons": actor_pool.allocated_skeleton_count(),
		"active_skeletons": actor_pool.active_skeleton_count(),
		"allocated_animation_players": actor_pool.allocated_animation_player_count(),
		"active_animation_players": actor_pool.active_actor_count,
		"crowd_instances": crowd_renderer.multimesh_instance_count,
		"crowd_groups": crowd_renderer.multimesh_group_count,
		"active_near": actor_pool.active_actor_count,
		"total_promotions": actor_pool.total_promotions,
		"total_demotions": actor_pool.total_demotions,
		"updated_chunks": _sample_updated_chunks / divisor,
		"updated_transform_instances": _sample_updated_transform_instances / divisor,
		"updated_custom_instances": _sample_updated_custom_instances / divisor,
		"render_path": crowd_renderer.render_path_name(),
		"formation_gpu_transform_supported": crowd_renderer.formation_gpu_transform_supported(),
		"formation_culling": crowd_renderer.formation_culling_mode_name(),
		"formation_batch_nodes": crowd_renderer.formation_batch_node_count,
		"visible_formations": crowd_renderer.visible_formation_count,
		"formation_transform_updates": _sample_formation_transform_updates / divisor,
		"instance_transform_updates": _sample_instance_transform_updates / divisor,
		"instance_transform_constructions": _sample_instance_transform_constructions / divisor,
		"instance_basis_constructions": _sample_instance_basis_constructions / divisor,
		"formation_custom_data_updates": _sample_formation_custom_updates / divisor,
		"formation_slot_rebuilds": _sample_formation_slot_rebuilds / divisor,
		"formation_slot_transform_writes": _sample_formation_slot_transform_writes / divisor,
		"formation_structural_changes": _sample_formation_structural_changes / divisor,
		"formation_transform_cpu_ms": _sample_formation_transform_cpu_ms / divisor,
		"gdscript_crowd_loop_cpu_ms": _sample_gdscript_crowd_loop_cpu_ms / divisor,
		"transform_preparation_cpu_ms": (
			_sample_transform_preparation_cpu_ms / float(_sample_transform_preparation_frames)
			if _sample_transform_preparation_frames > 0
			else -1.0
		),
		"simulation_world_position_updates": _sample_simulation_world_position_updates / divisor,
		"lazy_world_position_queries": _sample_lazy_world_position_queries / divisor,
		"simulation_formation_updates": _sample_simulation_formation_updates / divisor,
		"simulation_basis_constructions": _sample_simulation_basis_constructions / divisor,
		"near_render_stats": near_stats,
		"special_render_mode": SpecialRenderModeType.name_for(special_render_mode),
		"bundle_lod0_active": actor_pool.bundle_lod0_active,
		"bundle_lod1_active": actor_pool.bundle_lod1_active,
		"bundle_cache_misses": actor_pool.bundle_cache_misses,
		"pool_initialization_ms": actor_pool.initialization_cpu_ms,
		"rigid_batch_cpu_ms": _sample_rigid_batch_cpu_ms / divisor,
		"rigid_transform_updates": _sample_rigid_transform_updates / divisor,
		"rigid_upload_calls": _sample_rigid_upload_calls / divisor,
		"rigid_buffer_upload_calls": _sample_rigid_buffer_upload_calls / divisor,
		"rigid_bytes_uploaded": _sample_rigid_bytes_uploaded / divisor,
		"rigid_structural_changes": _sample_rigid_structural_changes / divisor,
		"lod_transitions": _sample_lod_transitions / divisor,
		"shadow_transitions": _sample_shadow_transitions / divisor,
		"promotions_per_second": _sample_promotions / maxf(measured_seconds, 0.001),
		"demotions_per_second": _sample_demotions / maxf(measured_seconds, 0.001),
		"spike_count": spike_count,
		"spike_trace": spike_trace.duplicate(),
		"rigid_equipment_audit": actor_pool.rigid_equipment_audit()
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

func _metrics_dictionary(viewport_fps: float) -> Dictionary:
	return {
		"fps": viewport_fps,
		"frame_ms": last_frame_ms,
		"worst_frame_ms": worst_frame_ms,
		"total_soldiers": simulation.active_soldier_count,
		"formations": simulation.active_formation_count,
		"near": actor_pool.active_actor_count,
		"near_budget": selected_near_budget,
		"capacity": actor_pool.capacity,
		"promotions": actor_pool.promotions_this_frame,
		"demotions": actor_pool.demotions_this_frame,
		"total_promotions": actor_pool.total_promotions,
		"total_demotions": actor_pool.total_demotions,
		"mid": crowd_renderer.mid_soldier_count,
		"far": crowd_renderer.far_soldier_count,
		"visible_chunks": crowd_renderer.visible_chunk_count,
		"visible_crowd_instances": crowd_renderer.visible_crowd_instance_count,
		"visible_soldiers": crowd_renderer.visible_soldier_count,
		"crowd_instances": crowd_renderer.multimesh_instance_count,
		"simulation_ms": last_simulation_ms,
		"policy_ms": last_policy_ms,
		"pool_ms": last_pool_ms,
		"animation_ms": last_animation_ms,
		"promotion_ms": last_promotion_ms,
		"renderer_ms": last_renderer_ms,
		"updated_chunks": crowd_renderer.last_updated_chunk_count,
		"updated_transform_instances": crowd_renderer.last_updated_transform_instances,
		"updated_custom_instances": crowd_renderer.last_updated_custom_instances,
		"render_path": crowd_renderer.render_path_name(),
		"formation_batch_nodes": crowd_renderer.formation_batch_node_count,
		"formation_culling": crowd_renderer.formation_culling_mode_name(),
		"visible_formations": crowd_renderer.visible_formation_count,
		"policy_candidate_formations": promotion_policy.last_candidate_formation_count,
		"policy_candidate_soldiers": promotion_policy.last_candidate_soldier_count,
		"policy_position_queries": promotion_policy.last_candidate_position_queries,
		"formation_transform_updates": crowd_renderer.last_formation_transform_updates,
		"instance_transform_updates": crowd_renderer.last_instance_transform_updates,
		"instance_transform_constructions": crowd_renderer.last_instance_transform_constructions,
		"instance_basis_constructions": crowd_renderer.last_instance_basis_constructions,
		"formation_custom_data_updates": crowd_renderer.last_formation_custom_data_updates,
		"formation_slot_rebuilds": crowd_renderer.last_formation_local_slot_rebuilds,
		"formation_slot_transform_writes": crowd_renderer.last_formation_slot_transform_writes,
		"formation_structural_changes": crowd_renderer.last_formation_structural_changes,
		"formation_transform_cpu_ms": crowd_renderer.last_formation_transform_cpu_ms,
		"gdscript_crowd_loop_cpu_ms": crowd_renderer.last_gdscript_crowd_loop_cpu_ms,
		"transform_preparation_cpu_ms": crowd_renderer.last_transform_preparation_cpu_ms,
		"simulation_world_position_updates": simulation.last_world_position_updates,
		"lazy_world_position_queries": simulation.lazy_world_position_queries,
		"simulation_formation_updates": simulation.last_formation_transform_updates,
		"simulation_basis_constructions": simulation.last_basis_constructions,
		"draw_calls": last_draw_calls,
		"triangles": last_triangles,
		"skeletons": actor_pool.allocated_skeleton_count(),
		"animation_players": actor_pool.allocated_animation_player_count(),
		"near_animation_enabled": near_animation_enabled,
		"near_equipment_visible": near_equipment_visible,
		"near_shadows_enabled": near_shadows_enabled,
		"near_animation_stride": near_animation_stride,
		"special_render_mode": SpecialRenderModeType.name_for(special_render_mode),
		"bundle_lod0_active": actor_pool.bundle_lod0_active,
		"bundle_lod1_active": actor_pool.bundle_lod1_active,
		"bundle_cache_misses": actor_pool.bundle_cache_misses,
		"rigid_batch_enabled": actor_pool.rigid_batch_enabled,
		"rigid_batch_cpu_ms": actor_pool.last_rigid_batch_cpu_ms,
		"rigid_transform_updates": actor_pool.last_rigid_transform_updates,
		"rigid_upload_calls": actor_pool.last_rigid_upload_calls,
		"rigid_buffer_upload_calls": actor_pool.last_rigid_buffer_upload_calls,
		"rigid_bytes_uploaded": actor_pool.last_rigid_bytes_uploaded,
		"rigid_structural_changes": actor_pool.rigid_structural_changes_this_frame,
		"lod_transitions": actor_pool.lod_transitions_this_frame,
		"shadow_transitions": actor_pool.shadow_transitions_this_frame,
		"shadow_budget": actor_pool.rigid_shadow_mode_name(),
		"seed": deterministic_seed,
		"paused": simulation_paused
	}

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
	camera.size = 42.0
	camera.near = 0.1
	camera.far = 1000.0
	camera.position = Vector3(18.0, 24.0, 18.0)
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
	var pan_speed: float = maxf(camera.size * 0.8, 24.0)
	var movement: Vector3 = (right * input.x + forward * input.y).normalized() * pan_speed * delta
	camera.position += movement
	camera_target += movement
	camera.look_at(camera_target, Vector3.UP)

func _apply_deterministic_camera_motion(delta: float) -> void:
	if camera == null:
		return
	deterministic_camera_motion_time += delta
	var t: float = deterministic_camera_motion_time
	var target := Vector3(sin(t * 0.37) * 52.0, 0.0, cos(t * 0.29) * 44.0)
	var position := target + Vector3(12.0 + sin(t * 0.19) * 5.0, 16.0, 12.0 + cos(t * 0.23) * 5.0)
	set_camera_state(position, target, camera.size)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and camera != null:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.size = clampf(camera.size * 0.85, 18.0, 420.0)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.size = clampf(camera.size * 1.18, 18.0, 420.0)
