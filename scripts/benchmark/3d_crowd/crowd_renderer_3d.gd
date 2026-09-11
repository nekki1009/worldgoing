class_name CrowdRenderer3D
extends Node3D

const BattleCrowdSimulationType = preload("res://scripts/benchmark/3d_crowd/battle_crowd_simulation.gd")
const CrowdChunk3DType = preload("res://scripts/benchmark/3d_crowd/crowd_chunk_3d.gd")
const CrowdNearActorPoolType = preload("res://scripts/benchmark/3d_crowd/crowd_near_actor_pool.gd")
const CrowdLodInterfaceType = preload("res://scripts/benchmark/3d_crowd/crowd_lod_interface.gd")
const SoldierVisualRegistryType = preload("res://scripts/benchmark/3d_crowd/soldier_visual_registry.gd")
const FormationRenderBatchType = preload("res://scripts/benchmark/3d_crowd/formation_render_batch.gd")

const CROWD_CHUNK_SIZE: float = 32.0
const BATTLEFIELD_MIN: float = -192.0
const BATTLEFIELD_MAX: float = 192.0
const CHUNK_COLUMNS: int = 12
const CHUNK_ROWS: int = 12
const CHUNK_COUNT: int = CHUNK_COLUMNS * CHUNK_ROWS
const ARCHETYPE_COUNT: int = 4
const MAX_FULL_ACTORS: int = 256
const LOD_NEAR_DISTANCE: float = CrowdLodInterfaceType.LOD_NEAR_DISTANCE
const LOD_MID_DISTANCE: float = CrowdLodInterfaceType.LOD_MID_DISTANCE
const LOD_FAR_DISTANCE: float = CrowdLodInterfaceType.LOD_FAR_DISTANCE
const FAR_UPDATE_INTERVAL: int = 3

enum RenderLod { NEAR, MID, FAR, PLACEHOLDER }
enum RenderPath { CURRENT_PER_INSTANCE, FORMATION_PARENT_TRANSFORM }

var chunks: Array[CrowdChunk3D] = []
var visible_chunk_count: int = 0
var visible_crowd_instance_count: int = 0
var visible_external_near_count: int = 0
var visible_soldier_count: int = 0
var near_actor_count: int = 0
var mid_soldier_count: int = 0
var far_soldier_count: int = 0
var placeholder_soldier_count: int = 0
var multimesh_group_count: int = 0
var multimesh_instance_count: int = 0
var last_update_cpu_ms: float = 0.0
var last_near_actor_cpu_ms: float = 0.0
var last_updated_chunk_count: int = 0
var last_updated_transform_instances: int = 0
var last_updated_custom_instances: int = 0
var last_dirty_chunk_count: int = 0
var last_dirty_visible_chunk_count: int = 0
var last_transform_dirty_instances: int = 0
var last_animation_dirty_instances: int = 0
var last_visual_dirty_instances: int = 0
var last_structural_change_count: int = 0
var last_chunk_migration_count: int = 0
var last_multimesh_upload_calls: int = 0
var last_transform_upload_calls: int = 0
var last_custom_upload_calls: int = 0
var last_bulk_upload_calls: int = 0
var last_instances_uploaded: int = 0
var last_bytes_uploaded: int = 0
var last_transform_preparation_cpu_ms: float = -1.0
var last_custom_preparation_cpu_ms: float = -1.0
var last_multimesh_upload_cpu_ms: float = 0.0
var last_formation_dirty_count: int = 0
var last_gdscript_crowd_loop_cpu_ms: float = 0.0
var last_formation_transform_cpu_ms: float = 0.0
var last_formation_transform_updates: int = 0
var last_instance_transform_updates: int = 0
var last_instance_transform_constructions: int = 0
var last_instance_basis_constructions: int = 0
var last_formation_custom_data_updates: int = 0
var last_formation_local_slot_rebuilds: int = 0
var last_formation_slot_transform_writes: int = 0
var last_formation_structural_changes: int = 0
var formation_batch_node_count: int = 0
var visible_formation_count: int = 0

# Update profiles are intentionally simple switches so benchmark runs can compare
# the old path with each optimization without duplicating the renderer.
var dirty_buffer_enabled: bool = true
var event_driven_custom_data_enabled: bool = true
var bulk_buffer_upload_enabled: bool = false
var stable_instance_slots_enabled: bool = true
var render_path: int = RenderPath.CURRENT_PER_INSTANCE

var lod_interface: CrowdLodInterface
var registry: SoldierVisualRegistry
var near_actor_pool: CrowdNearActorPool

var _simulation: BattleCrowdSimulation
var _near_actor_budget: int = 64
var _layout_ready: bool = false
var _last_active_soldier_count: int = -1
var _last_mode: int = -1
var _last_material_mode: int = -1
var _frame_index: int = 0

var _group_soldiers: Array[PackedInt32Array] = []
var _group_buffers: Array[PackedFloat32Array] = []
var _soldier_group_index: PackedInt32Array = PackedInt32Array()
var _soldier_group_slot: PackedInt32Array = PackedInt32Array()
var _slot_dirty: PackedByteArray = PackedByteArray()
var _structural_group_dirty: PackedByteArray = PackedByteArray()
var _render_lod: PackedInt32Array = PackedInt32Array()
var _render_archetype: PackedInt32Array = PackedInt32Array()
var _render_chunk: PackedInt32Array = PackedInt32Array()
var _near_flags: PackedByteArray = PackedByteArray()
var _previous_near_flags: PackedByteArray = PackedByteArray()
var _near_soldier_ids: PackedInt32Array = PackedInt32Array()
var _near_count: int = 0
var _external_near_flags: PackedByteArray = PackedByteArray()
var _external_near_slot_ids: PackedInt32Array = PackedInt32Array()
var _external_near_count: int = 0
var _chunk_total_counts: PackedInt32Array = PackedInt32Array()
var _chunk_crowd_counts: PackedInt32Array = PackedInt32Array()
var _formation_center_cache: PackedVector3Array = PackedVector3Array()
var _formation_facing_cache: PackedFloat32Array = PackedFloat32Array()
var _formation_transform_dirty: PackedByteArray = PackedByteArray()
var _formation_cache_valid: bool = false
var _uploaded_animation_state: PackedInt32Array = PackedInt32Array()
var _uploaded_packed_variant: PackedInt32Array = PackedInt32Array()
var _formation_batches: Array[FormationRenderBatch] = []
var _formation_layout_ready: bool = false
var _formation_last_active_count: int = -1
var _formation_last_mode: int = -1

var _shader: Shader
var _mid_materials: Array[ShaderMaterial] = []
var _far_materials: Array[ShaderMaterial] = []
var _placeholder_material: ShaderMaterial
var _formation_mid_materials: Array[ShaderMaterial] = []
var _formation_far_materials: Array[ShaderMaterial] = []
var _formation_placeholder_material: ShaderMaterial

func initialize(simulation: BattleCrowdSimulation) -> void:
	_simulation = simulation
	lod_interface = CrowdLodInterfaceType.new()
	registry = SoldierVisualRegistryType.new()
	_build_shared_resources()
	_build_chunks()
	near_actor_pool = CrowdNearActorPoolType.new()
	near_actor_pool.name = "NearActorPool"
	add_child(near_actor_pool)
	near_actor_pool.initialize(registry)
	var total_soldiers: int = simulation.soldier_world_positions.size()
	_render_lod.resize(total_soldiers)
	_render_archetype.resize(total_soldiers)
	_render_chunk.resize(total_soldiers)
	_soldier_group_index.resize(total_soldiers)
	_soldier_group_slot.resize(total_soldiers)
	_slot_dirty.resize(total_soldiers)
	_near_flags.resize(total_soldiers)
	_previous_near_flags.resize(total_soldiers)
	_external_near_flags.resize(total_soldiers)
	for index: int in range(total_soldiers):
		_render_lod[index] = -1
		_render_archetype[index] = -1
		_render_chunk[index] = -1
		_soldier_group_index[index] = -1
		_soldier_group_slot[index] = -1
		_slot_dirty[index] = 1
		_near_flags[index] = 0
		_previous_near_flags[index] = 0
		_external_near_flags[index] = 0
	_near_soldier_ids.resize(MAX_FULL_ACTORS)
	_external_near_slot_ids.resize(MAX_FULL_ACTORS)
	_external_near_slot_ids.fill(-1)
	_chunk_total_counts.resize(CHUNK_COUNT)
	_chunk_crowd_counts.resize(CHUNK_COUNT)
	_formation_center_cache.resize(BattleCrowdSimulationType.FORMATION_COUNT)
	_formation_facing_cache.resize(BattleCrowdSimulationType.FORMATION_COUNT)
	_formation_transform_dirty.resize(BattleCrowdSimulationType.FORMATION_COUNT)
	_formation_transform_dirty.fill(1)
	_formation_cache_valid = false
	_uploaded_animation_state.resize(total_soldiers)
	_uploaded_animation_state.fill(-1)
	_uploaded_packed_variant.resize(total_soldiers)
	_uploaded_packed_variant.fill(-1)
	for chunk_id: int in range(CHUNK_COUNT):
		_chunk_total_counts[chunk_id] = 0
		_chunk_crowd_counts[chunk_id] = 0
	_layout_ready = false

func invalidate_layout() -> void:
	_layout_ready = false
	_formation_cache_valid = false
	_formation_layout_ready = false

func set_render_path(next_path: int) -> void:
	var bounded_path: int = clampi(next_path, RenderPath.CURRENT_PER_INSTANCE, RenderPath.FORMATION_PARENT_TRANSFORM)
	if render_path == bounded_path:
		return
	render_path = bounded_path
	_layout_ready = false
	_formation_layout_ready = false
	_formation_cache_valid = false
	if render_path == RenderPath.FORMATION_PARENT_TRANSFORM:
		_teardown_chunks()
		_build_formation_batches()
	else:
		_teardown_formation_batches()
		_build_chunks()

func render_path_name() -> String:
	return "FORMATION_PARENT_TRANSFORM" if render_path == RenderPath.FORMATION_PARENT_TRANSFORM else "CURRENT_PER_INSTANCE"

func formation_culling_mode_name() -> String:
	return "HYBRID_FORMATION_AABB"

func formation_gpu_transform_supported() -> bool:
	# Godot 4.6.2 does not expose a small, standard MultiMesh shader buffer
	# contract for arbitrary per-instance formation matrix lookup.
	return false

func configure_update_profile(
	enable_dirty_buffer: bool,
	enable_event_custom_data: bool,
	enable_bulk_buffer: bool,
	enable_stable_slots: bool = true
) -> void:
	dirty_buffer_enabled = enable_dirty_buffer
	event_driven_custom_data_enabled = enable_event_custom_data
	bulk_buffer_upload_enabled = enable_bulk_buffer
	stable_instance_slots_enabled = enable_stable_slots
	_layout_ready = false
	_uploaded_animation_state.fill(-1)
	_uploaded_packed_variant.fill(-1)

func update_profile_name() -> String:
	if not dirty_buffer_enabled:
		return "baseline"
	if bulk_buffer_upload_enabled:
		return "combined_bulk"
	if not stable_instance_slots_enabled:
		return "dirty_event_full_rebuild"
	if event_driven_custom_data_enabled:
		return "stable_event"
	return "dirty_transform"

func set_near_actor_budget(requested_budget: int) -> void:
	var bounded_budget: int = clampi(requested_budget, 0, MAX_FULL_ACTORS)
	if bounded_budget == _near_actor_budget:
		return
	_near_actor_budget = bounded_budget
	_layout_ready = false

func get_near_actor_budget() -> int:
	return _near_actor_budget

func set_external_near_soldiers(ids: PackedInt32Array, count: int) -> bool:
	var bounded_count: int = clampi(count, 0, MAX_FULL_ACTORS)
	var changed: bool = bounded_count != _external_near_count
	for slot: int in range(MAX_FULL_ACTORS):
		var next_id: int = -1
		if slot < bounded_count and slot < ids.size():
			next_id = ids[slot]
		var previous_id: int = _external_near_slot_ids[slot]
		if previous_id == next_id:
			continue
		changed = true
		if previous_id >= 0 and previous_id < _external_near_flags.size():
			_external_near_flags[previous_id] = 0
			_set_formation_soldier_active(previous_id)
		if next_id >= 0 and next_id < _external_near_flags.size():
			_external_near_flags[next_id] = 1
			_set_formation_soldier_active(next_id)
		_external_near_slot_ids[slot] = next_id
	_external_near_count = bounded_count
	if changed:
		_layout_ready = false
	return changed

func external_near_count() -> int:
	return _external_near_count

func is_external_near_soldier(soldier_id: int) -> bool:
	return (
		soldier_id >= 0
		and soldier_id < _external_near_flags.size()
		and _external_near_flags[soldier_id] != 0
	)

func sync_from_simulation(view_camera: Camera3D) -> void:
	var started_usec: int = Time.get_ticks_usec()
	if _simulation == null:
		return
	_frame_index += 1
	_reset_formation_frame_metrics()
	if render_path == RenderPath.FORMATION_PARENT_TRANSFORM:
		_sync_formation_parent_transform(view_camera, started_usec)
		return
	_update_formation_dirty()
	var near_changed: bool = _resolve_near_candidates(view_camera)
	if _last_material_mode != int(_simulation.mode):
		_apply_material_mode()
		_last_material_mode = int(_simulation.mode)
	var layout_rebuilt: bool = _rebuild_layout_if_needed(view_camera, near_changed)
	near_actor_pool.update_near_soldiers(_near_soldier_ids, _near_count, _simulation)
	near_actor_count = _near_count
	last_near_actor_cpu_ms = near_actor_pool.last_update_cpu_ms
	_update_visibility(view_camera)
	var crowd_loop_started_usec: int = Time.get_ticks_usec()
	_sync_crowd_groups(layout_rebuilt)
	last_gdscript_crowd_loop_cpu_ms = float(Time.get_ticks_usec() - crowd_loop_started_usec) / 1000.0
	last_instance_transform_updates = last_updated_transform_instances
	formation_batch_node_count = 0
	last_update_cpu_ms = float(Time.get_ticks_usec() - started_usec) / 1000.0

func _reset_formation_frame_metrics() -> void:
	last_gdscript_crowd_loop_cpu_ms = 0.0
	last_formation_transform_cpu_ms = 0.0
	last_formation_transform_updates = 0
	last_instance_transform_updates = 0
	last_instance_transform_constructions = 0
	last_instance_basis_constructions = 0
	last_formation_custom_data_updates = 0
	last_formation_local_slot_rebuilds = 0
	last_formation_slot_transform_writes = 0
	last_formation_structural_changes = 0
	visible_formation_count = 0

func _sync_formation_parent_transform(view_camera: Camera3D, started_usec: int) -> void:
	if _formation_batches.is_empty():
		_build_formation_batches()
	if _formation_batches.is_empty():
		return
	visible_external_near_count = 0
	visible_soldier_count = 0
	_update_formation_dirty()
	if _near_actor_budget > 0:
		_resolve_near_candidates(view_camera)
	if _last_material_mode != int(_simulation.mode):
		_apply_material_mode()
		_last_material_mode = int(_simulation.mode)
	if _near_actor_budget > 0:
		near_actor_pool.update_near_soldiers(_near_soldier_ids, _near_count, _simulation)
	near_actor_count = _near_count
	last_near_actor_cpu_ms = near_actor_pool.last_update_cpu_ms

	for batch: FormationRenderBatch in _formation_batches:
		batch.begin_frame()
	var layout_rebuilt: bool = (
		not _formation_layout_ready
		or _formation_last_active_count != _simulation.active_formation_count
		or _formation_last_mode != int(_simulation.mode)
	)
	var formation_loop_started_usec: int = Time.get_ticks_usec()
	var total_crowd_instances: int = 0
	var visible_crowd_instances: int = 0
	var visible_formations: int = 0
	var updated_formations: int = 0
	var changed_formations: int = 0
	var viewport_size: Vector2 = view_camera.get_viewport().get_visible_rect().size if view_camera != null else Vector2(1600.0, 900.0)
	var aspect: float = maxf(viewport_size.x / maxf(viewport_size.y, 1.0), 0.1)
	var half_height: float = view_camera.size * 0.5 if view_camera != null else 210.0
	var half_width: float = half_height * aspect
	mid_soldier_count = 0
	far_soldier_count = 0
	placeholder_soldier_count = 0
	for formation_id: int in range(BattleCrowdSimulationType.FORMATION_COUNT):
		var batch: FormationRenderBatch = _formation_batches[formation_id]
		if formation_id >= _simulation.active_formation_count:
			batch.set_formation_active(false)
			continue
		var formation: CrowdFormationState = _simulation.formations[formation_id]
		var transform_changed: bool = layout_rebuilt or _formation_transform_dirty[formation_id] != 0
		if transform_changed and batch.set_formation_transform(formation.center_position, formation.facing):
			updated_formations += 1
		if batch.rebuild_local_slots(formation.spacing):
			last_formation_local_slot_rebuilds += 1
		var next_lod: int = _formation_lod_for(formation.center_position, view_camera)
		if batch.set_lod(next_lod):
			changed_formations += 1
		if layout_rebuilt:
			for slot_index: int in range(BattleCrowdSimulationType.SOLDIERS_PER_FORMATION):
				var soldier_index: int = formation_id * BattleCrowdSimulationType.SOLDIERS_PER_FORMATION + slot_index
				batch.set_slot_data(
					slot_index,
					_simulation.soldier_animation_phase[soldier_index],
					_simulation.soldier_animation_state[soldier_index],
					_packed_variant_id(soldier_index),
					_is_formation_soldier_render_active(soldier_index)
				)
		batch.set_formation_active(formation.active)
		var is_visible: bool = view_camera == null or (
			formation.active and _is_world_position_visible(
				view_camera, formation.center_position, aspect, half_width, half_height, batch.culling_radius()
			)
		)
		batch.visible = is_visible
		var active_instances: int = batch.active_instance_count()
		total_crowd_instances += active_instances
		if batch.lod == RenderLod.MID:
			mid_soldier_count += active_instances
		elif batch.lod == RenderLod.FAR:
			far_soldier_count += active_instances
		elif batch.lod == RenderLod.PLACEHOLDER:
			placeholder_soldier_count += active_instances
		if is_visible:
			visible_formations += 1
			visible_crowd_instances += active_instances

	if not layout_rebuilt:
		for event_index: int in range(_simulation.animation_dirty_count):
			var soldier_index: int = _simulation.soldier_animation_dirty_ids[event_index]
			if soldier_index < 0 or soldier_index >= _simulation.active_soldier_count:
				continue
			var formation_id: int = _simulation.soldier_formation_id[soldier_index]
			var batch: FormationRenderBatch = _formation_batches[formation_id]
			batch.set_slot_animation_state(
				_simulation.soldier_slot_index[soldier_index],
				_simulation.soldier_animation_state[soldier_index]
			)

	last_formation_transform_cpu_ms = float(Time.get_ticks_usec() - formation_loop_started_usec) / 1000.0
	last_gdscript_crowd_loop_cpu_ms = last_formation_transform_cpu_ms
	last_formation_transform_updates = updated_formations
	formation_batch_node_count = _simulation.active_formation_count
	visible_formation_count = visible_formations
	visible_chunk_count = visible_formations
	visible_crowd_instance_count = visible_crowd_instances
	visible_soldier_count = visible_crowd_instances
	multimesh_group_count = _simulation.active_formation_count
	multimesh_instance_count = total_crowd_instances
	last_updated_chunk_count = updated_formations
	last_dirty_chunk_count = changed_formations
	last_dirty_visible_chunk_count = changed_formations
	last_transform_dirty_instances = 0
	last_animation_dirty_instances = 0
	last_visual_dirty_instances = 0
	last_structural_change_count = changed_formations
	last_chunk_migration_count = 0
	last_multimesh_upload_calls = 0
	last_transform_upload_calls = 0
	last_custom_upload_calls = 0
	last_bulk_upload_calls = 0
	last_instances_uploaded = 0
	last_bytes_uploaded = 0
	last_transform_preparation_cpu_ms = last_formation_transform_cpu_ms
	last_custom_preparation_cpu_ms = 0.0
	last_multimesh_upload_cpu_ms = 0.0
	for batch: FormationRenderBatch in _formation_batches:
		last_instance_transform_updates += batch.local_slot_transform_writes
		last_formation_custom_data_updates += batch.custom_data_updates
		last_formation_slot_transform_writes += batch.local_slot_transform_writes
		last_formation_structural_changes += batch.structural_changes
		last_animation_dirty_instances += batch.custom_data_updates
		last_multimesh_upload_calls += batch.local_slot_transform_writes + batch.custom_data_updates
		last_transform_upload_calls += batch.local_slot_transform_writes
		last_custom_upload_calls += batch.custom_data_updates
		last_instances_uploaded += batch.local_slot_transform_writes + batch.custom_data_updates
		last_bytes_uploaded += batch.local_slot_transform_writes * 48 + batch.custom_data_updates * 16
	last_updated_transform_instances = last_instance_transform_updates
	last_updated_custom_instances = last_formation_custom_data_updates
	last_structural_change_count = last_formation_structural_changes
	_formation_layout_ready = true
	_formation_last_active_count = _simulation.active_formation_count
	_formation_last_mode = int(_simulation.mode)
	_update_formation_near_visibility(view_camera, visible_crowd_instances)
	last_update_cpu_ms = float(Time.get_ticks_usec() - started_usec) / 1000.0

func _formation_lod_for(center: Vector3, view_camera: Camera3D) -> int:
	if _simulation.mode == BattleCrowdSimulationType.BenchmarkMode.PLACEHOLDER:
		return RenderLod.PLACEHOLDER
	if _simulation.mode != BattleCrowdSimulationType.BenchmarkMode.HUMANOID_LOD or view_camera == null:
		return RenderLod.MID
	return RenderLod.MID if view_camera.global_position.distance_to(center) <= lod_interface.mid_distance else RenderLod.FAR

func _is_formation_soldier_render_active(soldier_index: int) -> bool:
	return (
		soldier_index >= 0
		and soldier_index < _simulation.soldier_alive.size()
		and _simulation.soldier_alive[soldier_index] != 0
		and not is_external_near_soldier(soldier_index)
		and (_near_flags.size() <= soldier_index or _near_flags[soldier_index] == 0)
	)

func _set_formation_soldier_active(soldier_index: int) -> void:
	if render_path != RenderPath.FORMATION_PARENT_TRANSFORM or _formation_batches.is_empty():
		return
	if soldier_index < 0 or soldier_index >= _simulation.active_soldier_count:
		return
	var formation_id: int = _simulation.soldier_formation_id[soldier_index]
	if formation_id < 0 or formation_id >= _formation_batches.size():
		return
	var batch: FormationRenderBatch = _formation_batches[formation_id]
	batch.set_slot_active(
		_simulation.soldier_slot_index[soldier_index],
		_is_formation_soldier_render_active(soldier_index)
	)

func _update_formation_near_visibility(view_camera: Camera3D, visible_crowd_instances: int) -> void:
	var viewport_size: Vector2 = view_camera.get_viewport().get_visible_rect().size if view_camera != null else Vector2(1600.0, 900.0)
	var aspect: float = maxf(viewport_size.x / maxf(viewport_size.y, 1.0), 0.1)
	var half_height: float = view_camera.size * 0.5 if view_camera != null else 210.0
	var half_width: float = half_height * aspect
	for slot: int in range(_near_count):
		var soldier_index: int = _near_soldier_ids[slot]
		var is_visible: bool = view_camera == null or _is_world_position_visible(
			view_camera, _simulation.get_soldier_world_position(soldier_index), aspect, half_width, half_height, 2.0
		)
		near_actor_pool.set_actor_visible(slot, is_visible)
		if is_visible:
			visible_soldier_count += 1
	for slot: int in range(_external_near_count):
		var soldier_index: int = _external_near_slot_ids[slot]
		if soldier_index < 0 or soldier_index >= _simulation.active_soldier_count:
			continue
		var is_visible: bool = view_camera == null or _is_world_position_visible(
			view_camera, _simulation.get_soldier_world_position(soldier_index), aspect, half_width, half_height, 2.0
		)
		if is_visible:
			visible_external_near_count += 1
			visible_soldier_count += 1

func allocated_skeleton_count() -> int:
	if near_actor_pool == null:
		return 0
	return near_actor_pool.allocated_skeleton_count()

func active_skeleton_count() -> int:
	return near_actor_count

func allocated_animation_player_count() -> int:
	if near_actor_pool == null:
		return 0
	return near_actor_pool.allocated_animation_player_count()

func crowd_material_count() -> int:
	return _mid_materials.size() + _far_materials.size() + 1

func near_material_count() -> int:
	return registry.entries.size() * 2

func _build_shared_resources() -> void:
	_shader = Shader.new()
	_shader.code = """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;

uniform vec4 archetype_color : source_color = vec4(0.3, 0.5, 0.4, 1.0);
uniform float animation_strength = 1.0;
uniform float far_tint = 0.0;
uniform bool use_active_mask = false;

varying float v_variant;
varying float v_active;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * 6.2831853;
	float state = INSTANCE_CUSTOM.y;
	// ponytail: derive continuous animation on GPU; custom z is no longer a per-frame clock upload.
	float animation_time = TIME;
	float walk = step(0.5, state) * (1.0 - step(1.5, state));
	float attack = step(1.5, state) * (1.0 - step(2.5, state));
	float cycle = animation_time * 7.5 + phase;
	float lower_body = 1.0 - smoothstep(0.72, 1.55, VERTEX.y);
	float upper_body = smoothstep(0.72, 1.25, VERTEX.y);
	VERTEX.y += sin(cycle * 2.0) * 0.025 * lower_body * animation_strength * walk;
	VERTEX.x += sin(cycle + VERTEX.y * 3.0) * 0.025 * lower_body * animation_strength * walk;
	VERTEX.z += cos(cycle + VERTEX.y * 2.0) * 0.018 * upper_body * animation_strength * attack;
	v_variant = INSTANCE_CUSTOM.w;
	v_active = INSTANCE_CUSTOM.z;
}

void fragment() {
	if (use_active_mask && v_active < 0.5) {
		discard;
	}
	float packed_variant = floor(v_variant * 12.0 + 0.5);
	float color_variant = floor(packed_variant / 3.0);
	float equipment_variant = mod(packed_variant, 3.0);
	vec3 tint = archetype_color.rgb;
	if (color_variant > 0.5) {
		tint *= 0.86;
	}
	if (color_variant > 1.5) {
		tint = mix(tint, vec3(0.82, 0.78, 0.58), 0.22);
	}
	if (color_variant > 2.5) {
		tint = mix(tint, vec3(0.42, 0.50, 0.62), 0.18);
	}
	tint *= 1.0 + equipment_variant * 0.035;
	tint = mix(tint, vec3(0.62, 0.66, 0.70), far_tint);
	ALBEDO = tint;
	ROUGHNESS = 0.86;
}
"""
	_mid_materials.clear()
	_far_materials.clear()
	_formation_mid_materials.clear()
	_formation_far_materials.clear()
	for spec: SoldierVisualArchetype in registry.entries:
		_mid_materials.append(_make_material(spec.base_color, 1.0, 0.0))
		_far_materials.append(_make_material(spec.base_color, 0.35, 0.22))
		_formation_mid_materials.append(_make_material(spec.base_color, 1.0, 0.0, true))
		_formation_far_materials.append(_make_material(spec.base_color, 0.35, 0.22, true))
	_placeholder_material = _make_material(Color("70908b"), 0.0, 0.0)
	_formation_placeholder_material = _make_material(Color("70908b"), 0.0, 0.0, true)

func _make_material(
	base_color: Color,
	animation_strength: float,
	far_tint: float,
	use_active_mask: bool = false
) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("archetype_color", base_color)
	material.set_shader_parameter("animation_strength", animation_strength)
	material.set_shader_parameter("far_tint", far_tint)
	material.set_shader_parameter("use_active_mask", use_active_mask)
	return material

func _apply_material_mode() -> void:
	if _simulation == null:
		return
	var mid_strength: float = 1.0
	var far_strength: float = 0.35
	if _simulation.mode == BattleCrowdSimulationType.BenchmarkMode.PLACEHOLDER:
		mid_strength = 0.0
		far_strength = 0.0
	elif _simulation.mode == BattleCrowdSimulationType.BenchmarkMode.HUMANOID_STATIC:
		mid_strength = 0.0
		far_strength = 0.0
	for material: ShaderMaterial in _mid_materials:
		material.set_shader_parameter("animation_strength", mid_strength)
	for material: ShaderMaterial in _far_materials:
		material.set_shader_parameter("animation_strength", far_strength)
	for material: ShaderMaterial in _formation_mid_materials:
		material.set_shader_parameter("animation_strength", mid_strength)
	for material: ShaderMaterial in _formation_far_materials:
		material.set_shader_parameter("animation_strength", far_strength)
	_placeholder_material.set_shader_parameter("animation_strength", 0.0)
	_formation_placeholder_material.set_shader_parameter("animation_strength", 0.0)

func _build_chunks() -> void:
	chunks.clear()
	var mid_meshes: Array[Mesh] = registry.mid_meshes()
	var far_meshes: Array[Mesh] = registry.far_meshes()
	for chunk_id: int in range(CHUNK_COUNT):
		var column: int = posmod(chunk_id, CHUNK_COLUMNS)
		var row: int = floori(float(chunk_id) / float(CHUNK_COLUMNS))
		var chunk: CrowdChunk3D = CrowdChunk3DType.new()
		chunk.name = "CrowdChunk_%d_%d" % [column, row]
		var center := Vector3(
			BATTLEFIELD_MIN + (float(column) + 0.5) * CROWD_CHUNK_SIZE,
			0.0,
			BATTLEFIELD_MIN + (float(row) + 0.5) * CROWD_CHUNK_SIZE
		)
		chunk.setup(
			mid_meshes,
			far_meshes,
			_mid_materials,
			_far_materials,
			registry.placeholder_mesh,
			_placeholder_material,
			center,
			CROWD_CHUNK_SIZE
		)
		add_child(chunk)
		chunks.append(chunk)
	_group_soldiers.clear()
	_group_buffers.clear()
	_structural_group_dirty.resize(CHUNK_COUNT * CrowdChunk3D.GROUP_COUNT)
	_structural_group_dirty.fill(0)
	for _group_index: int in range(CHUNK_COUNT * CrowdChunk3D.GROUP_COUNT):
		_group_soldiers.append(PackedInt32Array())
		_group_buffers.append(PackedFloat32Array())

func _teardown_chunks() -> void:
	for chunk: CrowdChunk3D in chunks:
		remove_child(chunk)
		chunk.queue_free()
	chunks.clear()
	_group_soldiers.clear()
	_group_buffers.clear()
	_structural_group_dirty = PackedByteArray()

func _build_formation_batches() -> void:
	if _simulation == null:
		return
	_formation_batches.clear()
	var mid_meshes: Array[Mesh] = registry.mid_meshes()
	var far_meshes: Array[Mesh] = registry.far_meshes()
	for formation_id: int in range(BattleCrowdSimulationType.FORMATION_COUNT):
		var archetype_id: int = posmod(formation_id, ARCHETYPE_COUNT)
		var batch: FormationRenderBatch = FormationRenderBatchType.new()
		batch.setup(
			formation_id,
			archetype_id,
			mid_meshes[archetype_id],
			far_meshes[archetype_id],
			registry.placeholder_mesh,
			_formation_mid_materials[archetype_id],
			_formation_far_materials[archetype_id],
			_formation_placeholder_material,
			BattleCrowdSimulationType.SOLDIERS_PER_FORMATION
		)
		batch.visible = false
		add_child(batch)
		_formation_batches.append(batch)
	formation_batch_node_count = _formation_batches.size()
	_formation_last_active_count = -1
	_formation_last_mode = -1

func _teardown_formation_batches() -> void:
	for batch: FormationRenderBatch in _formation_batches:
		remove_child(batch)
		batch.queue_free()
	_formation_batches.clear()
	formation_batch_node_count = 0

func _update_formation_dirty() -> void:
	last_formation_dirty_count = 0
	for formation_id: int in range(BattleCrowdSimulationType.FORMATION_COUNT):
		if formation_id >= _simulation.active_formation_count:
			_formation_transform_dirty[formation_id] = 0
			continue
		var formation: CrowdFormationState = _simulation.formations[formation_id]
		var changed: bool = not _formation_cache_valid
		if not changed:
			changed = (
				_formation_center_cache[formation_id].distance_squared_to(formation.center_position) > 0.000001
				or absf(angle_difference(_formation_facing_cache[formation_id], formation.facing)) > 0.00001
			)
		_formation_center_cache[formation_id] = formation.center_position
		_formation_facing_cache[formation_id] = formation.facing
		_formation_transform_dirty[formation_id] = 1 if changed else 0
		if changed:
			last_formation_dirty_count += 1
	_formation_cache_valid = true

func _resolve_near_candidates(view_camera: Camera3D) -> bool:
	var active_count: int = _simulation.active_soldier_count
	var layout_changed: bool = false
	for index: int in range(active_count):
		_near_flags[index] = 0
	var can_promote: bool = (
		view_camera != null
		and _simulation.mode == BattleCrowdSimulationType.BenchmarkMode.HUMANOID_LOD
		and _near_actor_budget > 0
	)
	_near_count = 0
	if can_promote:
		var near_distance_squared: float = lod_interface.near_distance * lod_interface.near_distance
		for soldier_index: int in range(active_count):
			var distance_squared: float = view_camera.global_position.distance_squared_to(
				_simulation.soldier_world_positions[soldier_index]
			)
			if distance_squared > near_distance_squared:
				continue
			if _near_count < _near_actor_budget:
				_near_soldier_ids[_near_count] = soldier_index
				_near_flags[soldier_index] = 1
				_near_count += 1
				continue
			var farthest_slot: int = 0
			var farthest_distance_squared: float = -1.0
			for candidate_slot: int in range(_near_count):
				var candidate_id: int = _near_soldier_ids[candidate_slot]
				var candidate_distance_squared: float = view_camera.global_position.distance_squared_to(
					_simulation.soldier_world_positions[candidate_id]
				)
				if candidate_distance_squared > farthest_distance_squared:
					farthest_distance_squared = candidate_distance_squared
					farthest_slot = candidate_slot
			if distance_squared < farthest_distance_squared:
				_near_flags[_near_soldier_ids[farthest_slot]] = 0
				_near_soldier_ids[farthest_slot] = soldier_index
				_near_flags[soldier_index] = 1
	for index: int in range(active_count):
		if _near_flags[index] != _previous_near_flags[index]:
			_previous_near_flags[index] = _near_flags[index]
			_set_formation_soldier_active(index)
			layout_changed = true
	for index: int in range(active_count, _previous_near_flags.size()):
		if _previous_near_flags[index] != 0:
			_previous_near_flags[index] = 0
			_set_formation_soldier_active(index)
			layout_changed = true
	return layout_changed

func _rebuild_layout_if_needed(view_camera: Camera3D, near_changed: bool) -> bool:
	var active_count: int = _simulation.active_soldier_count
	if (
		stable_instance_slots_enabled
		and
		_layout_ready
		and active_count == _last_active_soldier_count
		and _last_mode == int(_simulation.mode)
	):
		return _update_layout_incremental(view_camera)
	var needs_rebuild: bool = (
		not _layout_ready
		or (near_changed and not stable_instance_slots_enabled)
		or active_count != _last_active_soldier_count
		or _last_mode != int(_simulation.mode)
	)
	if not needs_rebuild:
		for soldier_index: int in range(active_count):
			var next_lod: int = _render_lod_for(soldier_index, view_camera)
			var next_archetype: int = _simulation.soldier_visual_archetype[soldier_index]
			var next_chunk: int = _chunk_id_for(_simulation.soldier_world_positions[soldier_index])
			if (
				_render_lod[soldier_index] != next_lod
				or _render_archetype[soldier_index] != next_archetype
				or _render_chunk[soldier_index] != next_chunk
			):
				needs_rebuild = true
				break
	if not needs_rebuild:
		return false

	var per_group: Array[Array] = []
	var structural_changes: int = 0
	var chunk_migrations: int = 0
	for _group_index: int in range(CHUNK_COUNT * CrowdChunk3D.GROUP_COUNT):
		per_group.append([])
	for chunk_id: int in range(CHUNK_COUNT):
		_chunk_total_counts[chunk_id] = 0
		_chunk_crowd_counts[chunk_id] = 0

	near_actor_count = _near_count
	mid_soldier_count = 0
	far_soldier_count = 0
	placeholder_soldier_count = 0
	for soldier_index: int in range(active_count):
		var render_lod: int = _render_lod_for(soldier_index, view_camera)
		var archetype_id: int = _simulation.soldier_visual_archetype[soldier_index]
		var chunk_id: int = _chunk_id_for(_simulation.soldier_world_positions[soldier_index])
		if (
			_render_lod[soldier_index] != render_lod
			or _render_archetype[soldier_index] != archetype_id
			or _render_chunk[soldier_index] != chunk_id
		):
			structural_changes += 1
			if _render_chunk[soldier_index] >= 0 and _render_chunk[soldier_index] != chunk_id:
				chunk_migrations += 1
		_render_lod[soldier_index] = render_lod
		_render_archetype[soldier_index] = archetype_id
		_render_chunk[soldier_index] = chunk_id
		_chunk_total_counts[chunk_id] += 1
		if render_lod == RenderLod.NEAR:
			continue
		var group_id: int = _group_id_for(render_lod, archetype_id)
		per_group[chunk_id * CrowdChunk3D.GROUP_COUNT + group_id].append(soldier_index)
		_chunk_crowd_counts[chunk_id] += 1
		match render_lod:
			RenderLod.MID:
				mid_soldier_count += 1
			RenderLod.FAR:
				far_soldier_count += 1
			RenderLod.PLACEHOLDER:
				placeholder_soldier_count += 1

	multimesh_group_count = 0
	multimesh_instance_count = 0
	var next_group_soldiers: Array[PackedInt32Array] = []
	var next_group_for_soldier := PackedInt32Array()
	next_group_for_soldier.resize(_render_lod.size())
	next_group_for_soldier.fill(-1)
	var next_slot_for_soldier := PackedInt32Array()
	next_slot_for_soldier.resize(_render_lod.size())
	next_slot_for_soldier.fill(-1)
	var next_slot_dirty := PackedByteArray()
	next_slot_dirty.resize(_render_lod.size())
	next_slot_dirty.fill(0)
	for chunk_id: int in range(CHUNK_COUNT):
		for group_id: int in range(CrowdChunk3D.GROUP_COUNT):
			var group_index: int = chunk_id * CrowdChunk3D.GROUP_COUNT + group_id
			var source: Array = per_group[group_index]
			var packed: PackedInt32Array = PackedInt32Array()
			packed.resize(source.size())
			packed.fill(-1)
			var assigned_slots := PackedByteArray()
			assigned_slots.resize(source.size())
			assigned_slots.fill(0)
			for source_value: Variant in source:
				var soldier_index: int = int(source_value)
				var old_group: int = _soldier_group_index[soldier_index]
				var old_slot: int = _soldier_group_slot[soldier_index]
				if old_group == group_index and old_slot >= 0 and old_slot < packed.size() and assigned_slots[old_slot] == 0:
					packed[old_slot] = soldier_index
					assigned_slots[old_slot] = 1
					next_group_for_soldier[soldier_index] = group_index
					next_slot_for_soldier[soldier_index] = old_slot
			var next_free_slot: int = 0
			for source_value: Variant in source:
				var soldier_index: int = int(source_value)
				if next_slot_for_soldier[soldier_index] >= 0:
					continue
				while next_free_slot < packed.size() and assigned_slots[next_free_slot] != 0:
					next_free_slot += 1
				if next_free_slot >= packed.size():
					break
				packed[next_free_slot] = soldier_index
				assigned_slots[next_free_slot] = 1
				next_group_for_soldier[soldier_index] = group_index
				next_slot_for_soldier[soldier_index] = next_free_slot
				next_free_slot += 1
			for source_value: Variant in source:
				var soldier_index: int = int(source_value)
				var next_slot: int = next_slot_for_soldier[soldier_index]
				if _soldier_group_index[soldier_index] != group_index or _soldier_group_slot[soldier_index] != next_slot:
					next_slot_dirty[soldier_index] = 1
			next_group_soldiers.append(packed)
			var required_buffer_size: int = packed.size() * 16
			var group_buffer: PackedFloat32Array = _group_buffers[group_index]
			if group_buffer.size() != required_buffer_size:
				group_buffer.resize(required_buffer_size)
				_group_buffers[group_index] = group_buffer
			chunks[chunk_id].resize_group(group_id, packed.size())
			if packed.size() > 0:
				multimesh_group_count += 1
				multimesh_instance_count += packed.size()
	_group_soldiers = next_group_soldiers
	_soldier_group_index = next_group_for_soldier
	_soldier_group_slot = next_slot_for_soldier
	_slot_dirty = next_slot_dirty
	_layout_ready = true
	_last_active_soldier_count = active_count
	_last_mode = int(_simulation.mode)
	last_structural_change_count = structural_changes
	last_chunk_migration_count = chunk_migrations
	return true

func _update_layout_incremental(view_camera: Camera3D) -> bool:
	var changed_count: int = 0
	var chunk_migrations: int = 0
	_structural_group_dirty.fill(0)
	for soldier_index: int in range(_simulation.active_soldier_count):
		var next_lod: int = _render_lod_for(soldier_index, view_camera)
		var next_archetype: int = _simulation.soldier_visual_archetype[soldier_index]
		var next_chunk: int = _chunk_id_for(_simulation.soldier_world_positions[soldier_index])
		var old_lod: int = _render_lod[soldier_index]
		var old_archetype: int = _render_archetype[soldier_index]
		var old_chunk: int = _render_chunk[soldier_index]
		if old_lod == next_lod and old_archetype == next_archetype and old_chunk == next_chunk:
			continue
		changed_count += 1
		if old_chunk != next_chunk:
			chunk_migrations += 1
		if old_lod != RenderLod.NEAR:
			_remove_soldier_from_group(soldier_index)
			_chunk_crowd_counts[old_chunk] -= 1
			_adjust_lod_count(old_lod, -1)
		if old_chunk != next_chunk:
			_chunk_total_counts[old_chunk] -= 1
			_chunk_total_counts[next_chunk] += 1
		_render_lod[soldier_index] = next_lod
		_render_archetype[soldier_index] = next_archetype
		_render_chunk[soldier_index] = next_chunk
		if next_lod != RenderLod.NEAR:
			_add_soldier_to_group(soldier_index)
			_chunk_crowd_counts[next_chunk] += 1
			_adjust_lod_count(next_lod, 1)
	for group_index: int in range(_structural_group_dirty.size()):
		if _structural_group_dirty[group_index] != 0:
			_resize_group_storage(group_index, _group_soldiers[group_index].size())
	near_actor_count = _near_count
	if changed_count > 0:
		_recompute_multimesh_counts()
	last_structural_change_count = changed_count
	last_chunk_migration_count = chunk_migrations
	return changed_count > 0

func _remove_soldier_from_group(soldier_index: int) -> void:
	var group_index: int = _soldier_group_index[soldier_index]
	if group_index < 0:
		return
	var slot: int = _soldier_group_slot[soldier_index]
	var indices: PackedInt32Array = _group_soldiers[group_index]
	var last_slot: int = indices.size() - 1
	if slot >= 0 and slot < indices.size() and slot != last_slot:
		var moved_soldier: int = indices[last_slot]
		indices[slot] = moved_soldier
		_soldier_group_slot[moved_soldier] = slot
		_slot_dirty[moved_soldier] = 1
	indices.resize(last_slot)
	_group_soldiers[group_index] = indices
	_structural_group_dirty[group_index] = 1
	_soldier_group_index[soldier_index] = -1
	_soldier_group_slot[soldier_index] = -1
	_slot_dirty[soldier_index] = 1

func _add_soldier_to_group(soldier_index: int) -> void:
	var chunk_id: int = _render_chunk[soldier_index]
	var group_id: int = _group_id_for(_render_lod[soldier_index], _render_archetype[soldier_index])
	var group_index: int = chunk_id * CrowdChunk3D.GROUP_COUNT + group_id
	var indices: PackedInt32Array = _group_soldiers[group_index]
	var slot: int = indices.size()
	indices.append(soldier_index)
	_group_soldiers[group_index] = indices
	_structural_group_dirty[group_index] = 1
	_soldier_group_index[soldier_index] = group_index
	_soldier_group_slot[soldier_index] = slot
	_slot_dirty[soldier_index] = 1

func _resize_group_storage(group_index: int, instance_count: int) -> void:
	var chunk_id: int = floori(float(group_index) / float(CrowdChunk3D.GROUP_COUNT))
	var group_id: int = posmod(group_index, CrowdChunk3D.GROUP_COUNT)
	chunks[chunk_id].resize_group(group_id, instance_count)
	var required_buffer_size: int = instance_count * 16
	var group_buffer: PackedFloat32Array = _group_buffers[group_index]
	if group_buffer.size() != required_buffer_size:
		group_buffer.resize(required_buffer_size)
		_group_buffers[group_index] = group_buffer

func _adjust_lod_count(render_lod: int, delta: int) -> void:
	match render_lod:
		RenderLod.MID:
			mid_soldier_count += delta
		RenderLod.FAR:
			far_soldier_count += delta
		RenderLod.PLACEHOLDER:
			placeholder_soldier_count += delta

func _recompute_multimesh_counts() -> void:
	multimesh_group_count = 0
	multimesh_instance_count = 0
	for group_indices: PackedInt32Array in _group_soldiers:
		if group_indices.is_empty():
			continue
		multimesh_group_count += 1
		multimesh_instance_count += group_indices.size()

func _render_lod_for(soldier_index: int, view_camera: Camera3D) -> int:
	if _simulation.mode == BattleCrowdSimulationType.BenchmarkMode.PLACEHOLDER:
		return RenderLod.PLACEHOLDER
	if _simulation.mode != BattleCrowdSimulationType.BenchmarkMode.HUMANOID_LOD:
		return RenderLod.MID
	if _external_near_flags[soldier_index] != 0:
		return RenderLod.NEAR
	if _near_flags[soldier_index] != 0:
		return RenderLod.NEAR
	if view_camera == null:
		return RenderLod.MID
	var distance: float = view_camera.global_position.distance_to(
		_simulation.soldier_world_positions[soldier_index]
	)
	return RenderLod.MID if distance <= lod_interface.mid_distance else RenderLod.FAR

func _group_id_for(render_lod: int, archetype_id: int) -> int:
	match render_lod:
		RenderLod.MID:
			return CrowdChunk3D.MID_GROUP_BASE + archetype_id
		RenderLod.FAR:
			return CrowdChunk3D.FAR_GROUP_BASE + archetype_id
		_:
			return CrowdChunk3D.PLACEHOLDER_GROUP

func _sync_crowd_groups(layout_rebuilt: bool) -> void:
	last_updated_chunk_count = 0
	last_updated_transform_instances = 0
	last_updated_custom_instances = 0
	last_dirty_chunk_count = 0
	last_dirty_visible_chunk_count = 0
	last_transform_dirty_instances = 0
	last_animation_dirty_instances = 0
	last_visual_dirty_instances = 0
	last_multimesh_upload_calls = 0
	last_transform_upload_calls = 0
	last_custom_upload_calls = 0
	last_bulk_upload_calls = 0
	last_instances_uploaded = 0
	last_bytes_uploaded = 0
	last_transform_preparation_cpu_ms = -1.0
	last_custom_preparation_cpu_ms = -1.0
	last_multimesh_upload_cpu_ms = 0.0
	if not layout_rebuilt:
		last_structural_change_count = 0
		last_chunk_migration_count = 0
	for chunk: CrowdChunk3D in chunks:
		chunk.clear_dirty_state()
	var update_all: bool = layout_rebuilt
	var update_custom: bool = (
		layout_rebuilt
		or _simulation.mode == BattleCrowdSimulationType.BenchmarkMode.HUMANOID_ANIMATED
		or _simulation.mode == BattleCrowdSimulationType.BenchmarkMode.HUMANOID_LOD
	)
	for chunk_id: int in range(CHUNK_COUNT):
		# ponytail: upload only visible chunks; hidden data is refreshed when the chunk returns on screen.
		if not chunks[chunk_id].visible:
			continue
		var chunk_updated: bool = false
		for group_id: int in range(CrowdChunk3D.GROUP_COUNT):
			var group_indices: PackedInt32Array = _group_soldiers[chunk_id * CrowdChunk3D.GROUP_COUNT + group_id]
			if group_indices.is_empty():
				continue
			var render_lod: int = RenderLod.PLACEHOLDER
			if group_id < CrowdChunk3D.FAR_GROUP_BASE:
				render_lod = RenderLod.MID
			elif group_id < CrowdChunk3D.PLACEHOLDER_GROUP:
				render_lod = RenderLod.FAR
			var update_transform: bool = update_all
			if not update_transform:
				if _simulation.mode == BattleCrowdSimulationType.BenchmarkMode.PLACEHOLDER:
					update_transform = true
				elif _simulation.mode == BattleCrowdSimulationType.BenchmarkMode.HUMANOID_STATIC:
					update_transform = false
				elif render_lod == RenderLod.FAR:
					update_transform = _frame_index % FAR_UPDATE_INTERVAL == 0
				else:
					update_transform = true
			var update_group_custom: bool = update_custom
			if render_lod == RenderLod.FAR and _simulation.mode == BattleCrowdSimulationType.BenchmarkMode.HUMANOID_LOD:
				update_group_custom = _frame_index % FAR_UPDATE_INTERVAL == 0
			var group_updated: bool = _write_group_data(
				chunk_id,
				group_id,
				update_transform,
				update_group_custom,
				dirty_buffer_enabled,
				layout_rebuilt
			)
			if group_updated:
				chunk_updated = true
		if chunk_updated:
			last_updated_chunk_count += 1
			last_dirty_chunk_count += 1 if chunk_updated else 0
			last_dirty_visible_chunk_count += 1 if chunk_updated else 0
			chunks[chunk_id].last_update_frame = _frame_index if chunk_updated else chunks[chunk_id].last_update_frame

func _write_group_data(
	chunk_id: int,
	group_id: int,
	update_transform: bool,
	update_custom: bool,
	dirty_enabled: bool,
	force_layout_write: bool
) -> bool:
	var indices: PackedInt32Array = _group_soldiers[chunk_id * CrowdChunk3D.GROUP_COUNT + group_id]
	if indices.is_empty():
		return false
	var multimesh: MultiMesh = chunks[chunk_id].group_instance(group_id).multimesh
	var allow_update: bool = true
	if render_lod_for_group(group_id) == RenderLod.FAR and not force_layout_write:
		allow_update = _frame_index % FAR_UPDATE_INTERVAL == 0
	if dirty_enabled and not update_transform and not update_custom:
		return false
	var transform_dirty_count: int = 0
	var animation_dirty_count: int = 0
	var visual_dirty_count: int = 0
	var all_formations_dirty: bool = (
		dirty_enabled
		and update_transform
		and allow_update
		and last_formation_dirty_count >= _simulation.active_formation_count
	)
	if not dirty_enabled:
		transform_dirty_count = indices.size() if update_transform and allow_update else 0
		animation_dirty_count = indices.size() if update_custom and allow_update else 0
		visual_dirty_count = indices.size() if update_custom and allow_update else 0
	elif all_formations_dirty:
		transform_dirty_count = 0
	if bulk_buffer_upload_enabled and dirty_enabled and all_formations_dirty:
		return _write_group_buffer(
			chunk_id,
			group_id,
			indices,
			multimesh,
			update_transform,
			update_custom,
			allow_update,
			force_layout_write,
			indices.size(),
			0,
			0
		)
	var upload_started_usec: int = Time.get_ticks_usec()
	var group_updated: bool = false
	for slot: int in range(indices.size()):
		var soldier_index: int = indices[slot]
		var formation_id: int = _simulation.soldier_formation_id[soldier_index]
		var should_update_transform: bool = update_transform
		var should_update_custom: bool = update_custom
		var state_changed: bool = false
		var visual_changed: bool = false
		if dirty_enabled:
			should_update_transform = update_transform and (
				_slot_dirty[soldier_index] != 0 or _formation_transform_dirty[formation_id] != 0
			) and allow_update
			var packed_variant_id: int = _packed_variant_id(soldier_index)
			state_changed = _uploaded_animation_state[soldier_index] != _simulation.soldier_animation_state[soldier_index]
			visual_changed = _uploaded_packed_variant[soldier_index] != packed_variant_id
			should_update_custom = update_custom and (
				_slot_dirty[soldier_index] != 0 or (event_driven_custom_data_enabled and (state_changed or visual_changed)) or (
					not event_driven_custom_data_enabled
				)
			) and allow_update
		if should_update_transform:
			group_updated = true
			transform_dirty_count += 1 if dirty_enabled else 0
			last_instance_transform_constructions += 1
			last_instance_basis_constructions += 1
			var local_position: Vector3 = _simulation.soldier_world_positions[soldier_index] - chunks[chunk_id].global_position
			multimesh.set_instance_transform(
				slot,
				Transform3D(Basis(Vector3.UP, _simulation.soldier_facing[soldier_index]), local_position)
			)
			last_updated_transform_instances += 1
			last_transform_upload_calls += 1
			last_multimesh_upload_calls += 1
			last_instances_uploaded += 1
			last_bytes_uploaded += 48
		if should_update_custom:
			group_updated = true
			if dirty_enabled:
				animation_dirty_count += 1 if state_changed or _slot_dirty[soldier_index] != 0 else 0
				visual_dirty_count += 1 if visual_changed or _slot_dirty[soldier_index] != 0 else 0
			var packed_variant: float = float(_packed_variant_id(soldier_index)) / 11.0
			multimesh.set_instance_custom_data(
				slot,
				Color(
					_simulation.soldier_animation_phase[soldier_index],
					float(_simulation.soldier_animation_state[soldier_index]),
					_simulation.soldier_animation_time[soldier_index] if not event_driven_custom_data_enabled else 0.0,
					packed_variant
				)
			)
			_uploaded_animation_state[soldier_index] = _simulation.soldier_animation_state[soldier_index]
			_uploaded_packed_variant[soldier_index] = _packed_variant_id(soldier_index)
			last_updated_custom_instances += 1
			last_custom_upload_calls += 1
			last_multimesh_upload_calls += 1
			last_instances_uploaded += 1
			last_bytes_uploaded += 16
		if should_update_transform or should_update_custom:
			_slot_dirty[soldier_index] = 0
	last_multimesh_upload_cpu_ms += float(Time.get_ticks_usec() - upload_started_usec) / 1000.0
	if group_updated:
		last_transform_dirty_instances += transform_dirty_count
		last_animation_dirty_instances += animation_dirty_count
		last_visual_dirty_instances += visual_dirty_count
		chunks[chunk_id].mark_dirty(
			transform_dirty_count > 0,
			animation_dirty_count > 0,
			visual_dirty_count > 0,
			transform_dirty_count + animation_dirty_count + visual_dirty_count
		)
	return group_updated

func _write_group_buffer(
	chunk_id: int,
	group_id: int,
	indices: PackedInt32Array,
	multimesh: MultiMesh,
	update_transform: bool,
	update_custom: bool,
	allow_update: bool,
	force_layout_write: bool,
	transform_dirty_count: int,
	animation_dirty_count: int,
	visual_dirty_count: int
) -> bool:
	var group_index: int = chunk_id * CrowdChunk3D.GROUP_COUNT + group_id
	var buffer: PackedFloat32Array = _group_buffers[group_index]
	var custom_dirty_count: int = 0
	animation_dirty_count = 0
	visual_dirty_count = 0
	var prepare_started_usec: int = Time.get_ticks_usec()
	for slot: int in range(indices.size()):
		var soldier_index: int = indices[slot]
		var offset: int = slot * 16
		var formation_id: int = _simulation.soldier_formation_id[soldier_index]
		var should_update_transform: bool = update_transform and (
		_slot_dirty[soldier_index] != 0 or _formation_transform_dirty[formation_id] != 0
		) and allow_update
		var packed_variant_id: int = _packed_variant_id(soldier_index)
		var state_changed: bool = _uploaded_animation_state[soldier_index] != _simulation.soldier_animation_state[soldier_index]
		var visual_changed: bool = _uploaded_packed_variant[soldier_index] != packed_variant_id
		var should_update_custom: bool = update_custom and (
		_slot_dirty[soldier_index] != 0 or (event_driven_custom_data_enabled and (state_changed or visual_changed)) or (
				not event_driven_custom_data_enabled
			)
		) and allow_update
		if should_update_transform:
			var basis := Basis(Vector3.UP, _simulation.soldier_facing[soldier_index])
			var local_position: Vector3 = _simulation.soldier_world_positions[soldier_index] - chunks[chunk_id].global_position
			buffer[offset + 0] = basis.x.x
			buffer[offset + 1] = basis.y.x
			buffer[offset + 2] = basis.z.x
			buffer[offset + 3] = local_position.x
			buffer[offset + 4] = basis.x.y
			buffer[offset + 5] = basis.y.y
			buffer[offset + 6] = basis.z.y
			buffer[offset + 7] = local_position.y
			buffer[offset + 8] = basis.x.z
			buffer[offset + 9] = basis.y.z
			buffer[offset + 10] = basis.z.z
			buffer[offset + 11] = local_position.z
		if should_update_custom:
			custom_dirty_count += 1
			animation_dirty_count += 1 if state_changed or _slot_dirty[soldier_index] != 0 else 0
			visual_dirty_count += 1 if visual_changed or _slot_dirty[soldier_index] != 0 else 0
			buffer[offset + 12] = _simulation.soldier_animation_phase[soldier_index]
			buffer[offset + 13] = float(_simulation.soldier_animation_state[soldier_index])
			buffer[offset + 14] = _simulation.soldier_animation_time[soldier_index] if not event_driven_custom_data_enabled else 0.0
			buffer[offset + 15] = float(packed_variant_id) / 11.0
			_uploaded_animation_state[soldier_index] = _simulation.soldier_animation_state[soldier_index]
			_uploaded_packed_variant[soldier_index] = packed_variant_id
		if should_update_transform or should_update_custom:
			_slot_dirty[soldier_index] = 0
	if last_transform_preparation_cpu_ms < 0.0:
		last_transform_preparation_cpu_ms = 0.0
	last_transform_preparation_cpu_ms += float(Time.get_ticks_usec() - prepare_started_usec) / 1000.0
	var upload_started_usec: int = Time.get_ticks_usec()
	multimesh.set_buffer(buffer)
	last_multimesh_upload_cpu_ms += float(Time.get_ticks_usec() - upload_started_usec) / 1000.0
	last_bulk_upload_calls += 1
	last_multimesh_upload_calls += 1
	last_instances_uploaded += indices.size()
	last_bytes_uploaded += buffer.size() * 4
	last_updated_transform_instances += transform_dirty_count
	last_updated_custom_instances += custom_dirty_count
	last_transform_dirty_instances += transform_dirty_count
	last_transform_upload_calls += 1 if transform_dirty_count > 0 else 0
	last_custom_upload_calls += 1 if custom_dirty_count > 0 else 0
	last_animation_dirty_instances += animation_dirty_count
	last_visual_dirty_instances += visual_dirty_count
	chunks[chunk_id].mark_dirty(
		transform_dirty_count > 0,
		animation_dirty_count > 0,
		visual_dirty_count > 0,
		transform_dirty_count + custom_dirty_count
	)
	return true

func _packed_variant_id(soldier_index: int) -> int:
	return _simulation.soldier_color_variant[soldier_index] * 3 + _simulation.soldier_equipment_variant[soldier_index]

func render_lod_for_group(group_id: int) -> int:
	if group_id < CrowdChunk3D.FAR_GROUP_BASE:
		return RenderLod.MID
	if group_id < CrowdChunk3D.PLACEHOLDER_GROUP:
		return RenderLod.FAR
	return RenderLod.PLACEHOLDER

func _update_visibility(view_camera: Camera3D) -> void:
	visible_chunk_count = 0
	visible_crowd_instance_count = 0
	visible_external_near_count = 0
	visible_soldier_count = 0
	if view_camera == null:
		for chunk_id: int in range(CHUNK_COUNT):
			var has_soldiers: bool = _chunk_total_counts[chunk_id] > 0
			chunks[chunk_id].visible = has_soldiers
			if has_soldiers:
				visible_chunk_count += 1
				visible_crowd_instance_count += _chunk_crowd_counts[chunk_id]
				visible_soldier_count += _chunk_crowd_counts[chunk_id]
		for slot: int in range(_near_count):
			near_actor_pool.set_actor_visible(slot, true)
		visible_soldier_count += _near_count
		visible_external_near_count = _external_near_count
		visible_soldier_count += _external_near_count
		return

	var viewport_size: Vector2 = view_camera.get_viewport().get_visible_rect().size
	var aspect: float = maxf(viewport_size.x / maxf(viewport_size.y, 1.0), 0.1)
	var half_height: float = view_camera.size * 0.5
	var half_width: float = half_height * aspect
	for chunk_id: int in range(CHUNK_COUNT):
		var has_soldiers: bool = _chunk_total_counts[chunk_id] > 0
		var chunk_visible: bool = has_soldiers and _is_world_position_visible(
			view_camera,
			chunks[chunk_id].global_position,
			aspect,
			half_width,
			half_height,
			sqrt(2.0) * CROWD_CHUNK_SIZE * 0.5 + 4.0
		)
		chunks[chunk_id].visible = chunk_visible
		if chunk_visible:
			visible_chunk_count += 1
			visible_crowd_instance_count += _chunk_crowd_counts[chunk_id]
			visible_soldier_count += _chunk_crowd_counts[chunk_id]
		for group_id: int in range(CrowdChunk3D.GROUP_COUNT):
			chunks[chunk_id].set_group_visible(group_id, chunk_visible)
	for slot: int in range(_near_count):
		var soldier_index: int = _near_soldier_ids[slot]
		var is_visible: bool = _is_world_position_visible(
			view_camera,
			_simulation.soldier_world_positions[soldier_index],
			aspect,
			half_width,
			half_height,
			2.0
		)
		near_actor_pool.set_actor_visible(slot, is_visible)
		if is_visible:
			visible_soldier_count += 1
	for slot: int in range(_external_near_count):
		var soldier_index: int = _external_near_slot_ids[slot]
		if soldier_index < 0 or soldier_index >= _simulation.active_soldier_count:
			continue
		var is_visible: bool = _is_world_position_visible(
			view_camera,
			_simulation.soldier_world_positions[soldier_index],
			aspect,
			half_width,
			half_height,
			2.0
		)
		if is_visible:
			visible_external_near_count += 1
			visible_soldier_count += 1

func _is_world_position_visible(
	view_camera: Camera3D,
	world_position: Vector3,
	aspect: float,
	half_width: float,
	half_height: float,
	radius: float
) -> bool:
	var local_position: Vector3 = view_camera.global_transform.affine_inverse() * world_position
	var depth: float = -local_position.z
	if depth + radius < view_camera.near or depth - radius > view_camera.far:
		return false
	if view_camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return absf(local_position.x) <= half_width + radius and absf(local_position.y) <= half_height + radius
	var vertical_limit: float = maxf(depth, 0.1) * tan(deg_to_rad(view_camera.fov * 0.5))
	var horizontal_limit: float = vertical_limit * aspect
	return absf(local_position.x) <= horizontal_limit + radius and absf(local_position.y) <= vertical_limit + radius

func _chunk_id_for(world_position: Vector3) -> int:
	var column: int = clampi(
		floori((world_position.x - BATTLEFIELD_MIN) / CROWD_CHUNK_SIZE),
		0,
		CHUNK_COLUMNS - 1
	)
	var row: int = clampi(
		floori((world_position.z - BATTLEFIELD_MIN) / CROWD_CHUNK_SIZE),
		0,
		CHUNK_ROWS - 1
	)
	return row * CHUNK_COLUMNS + column
