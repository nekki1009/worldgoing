class_name FormationRenderBatch
extends MultiMeshInstance3D

const FormationSlotGeneratorType = preload("res://scripts/benchmark/3d_crowd/formation_slot_generator.gd")

var formation_id: int = -1
var visual_archetype: int = -1
var lod: int = -1
var instance_count: int = 0
var local_slot_cache: PackedVector3Array = PackedVector3Array()
var current_world_transform: Transform3D = Transform3D.IDENTITY

var formation_transform_updates: int = 0
var local_slot_transform_writes: int = 0
var custom_data_updates: int = 0
var structural_changes: int = 0

var _mid_mesh: Mesh
var _far_mesh: Mesh
var _placeholder_mesh: Mesh
var _mid_material: Material
var _far_material: Material
var _placeholder_material: Material
var _slot_spacing: float = -1.0
var _culling_radius: float = 12.0
var _slot_phase: PackedFloat32Array = PackedFloat32Array()
var _slot_state: PackedInt32Array = PackedInt32Array()
var _slot_variant: PackedInt32Array = PackedInt32Array()
var _slot_active: PackedByteArray = PackedByteArray()
var _active_instance_count: int = 0

func setup(
	next_formation_id: int,
	next_visual_archetype: int,
	next_mid_mesh: Mesh,
	next_far_mesh: Mesh,
	next_placeholder_mesh: Mesh,
	next_mid_material: Material,
	next_far_material: Material,
	next_placeholder_material: Material,
	next_instance_count: int = 100
) -> void:
	formation_id = next_formation_id
	visual_archetype = next_visual_archetype
	_mid_mesh = next_mid_mesh
	_far_mesh = next_far_mesh
	_placeholder_mesh = next_placeholder_mesh
	_mid_material = next_mid_material
	_far_material = next_far_material
	_placeholder_material = next_placeholder_material
	instance_count = next_instance_count
	name = "FormationRenderBatch_%d" % formation_id

	var next_multimesh := MultiMesh.new()
	next_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	next_multimesh.use_custom_data = true
	next_multimesh.mesh = _mid_mesh
	next_multimesh.instance_count = instance_count
	next_multimesh.custom_aabb = AABB(Vector3(-9.0, -1.0, -9.0), Vector3(18.0, 5.0, 18.0))
	multimesh = next_multimesh
	material_override = _mid_material

	_slot_phase.resize(instance_count)
	_slot_state.resize(instance_count)
	_slot_variant.resize(instance_count)
	_slot_active.resize(instance_count)
	_slot_active.fill(1)
	_active_instance_count = instance_count
	rebuild_local_slots(1.25)

func begin_frame() -> void:
	formation_transform_updates = 0
	local_slot_transform_writes = 0
	custom_data_updates = 0
	structural_changes = 0

func rebuild_local_slots(spacing: float) -> bool:
	if local_slot_cache.size() == instance_count and is_equal_approx(_slot_spacing, spacing):
		return false
	_slot_spacing = spacing
	local_slot_cache.resize(instance_count)
	for slot_index: int in range(instance_count):
		var local_position: Vector3 = FormationSlotGeneratorType.local_position(
			slot_index, 10, ceili(float(instance_count) / 10.0), spacing
		)
		local_slot_cache[slot_index] = local_position
		multimesh.set_instance_transform(slot_index, Transform3D(Basis.IDENTITY, local_position))
		local_slot_transform_writes += 1
	var max_distance_squared: float = 0.0
	for local_position: Vector3 in local_slot_cache:
		max_distance_squared = maxf(max_distance_squared, Vector2(local_position.x, local_position.z).length_squared())
	_culling_radius = sqrt(max_distance_squared) + maxf(spacing, 0.5)
	multimesh.custom_aabb = AABB(
		Vector3(-_culling_radius, -1.0, -_culling_radius),
		Vector3(_culling_radius * 2.0, 5.0, _culling_radius * 2.0)
	)
	return true

func culling_radius() -> float:
	return _culling_radius

func set_formation_transform(center: Vector3, facing: float) -> bool:
	var next_transform := Transform3D(Basis(Vector3.UP, facing), center)
	var changed: bool = (
		current_world_transform.origin.distance_squared_to(center) > 0.000001
		or absf(angle_difference(rotation.y, facing)) > 0.00001
	)
	if not changed:
		return false
	current_world_transform = next_transform
	position = center
	rotation = Vector3(0.0, facing, 0.0)
	formation_transform_updates += 1
	return true

func set_lod(next_lod: int) -> bool:
	if lod == next_lod:
		return false
	lod = next_lod
	match lod:
		2:
			multimesh.mesh = _far_mesh
			material_override = _far_material
		3:
			multimesh.mesh = _placeholder_mesh
			material_override = _placeholder_material
		_:
			multimesh.mesh = _mid_mesh
			material_override = _mid_material
	structural_changes += 1
	return true

func set_formation_active(active: bool) -> void:
	visible = active

func set_slot_data(
	slot_index: int,
	phase: float,
	state: int,
	variant: int,
	active: bool
) -> bool:
	if slot_index < 0 or slot_index >= instance_count:
		return false
	_slot_phase[slot_index] = phase
	_slot_state[slot_index] = state
	_slot_variant[slot_index] = variant
	var next_active: int = 1 if active else 0
	if _slot_active[slot_index] != next_active:
		_active_instance_count += 1 if next_active != 0 else -1
	_slot_active[slot_index] = next_active
	_write_slot_custom_data(slot_index)
	return true

func set_slot_active(slot_index: int, active: bool) -> bool:
	if slot_index < 0 or slot_index >= instance_count:
		return false
	var next_value: int = 1 if active else 0
	if _slot_active[slot_index] == next_value:
		return false
	_active_instance_count += 1 if next_value != 0 else -1
	_slot_active[slot_index] = next_value
	_write_slot_custom_data(slot_index)
	return true

func set_slot_animation_state(slot_index: int, state: int) -> bool:
	if slot_index < 0 or slot_index >= instance_count or _slot_state[slot_index] == state:
		return false
	_slot_state[slot_index] = state
	_write_slot_custom_data(slot_index)
	return true

func is_slot_active(slot_index: int) -> bool:
	return slot_index >= 0 and slot_index < instance_count and _slot_active[slot_index] != 0

func active_instance_count() -> int:
	return _active_instance_count

func _write_slot_custom_data(slot_index: int) -> void:
	var packed_variant: float = float(_slot_variant[slot_index]) / 11.0
	multimesh.set_instance_custom_data(
		slot_index,
		Color(_slot_phase[slot_index], float(_slot_state[slot_index]), float(_slot_active[slot_index]), packed_variant)
	)
	custom_data_updates += 1
