class_name CrowdChunk3D
extends Node3D

const ARCHETYPE_COUNT: int = 4
const MID_GROUP_BASE: int = 0
const FAR_GROUP_BASE: int = 4
const PLACEHOLDER_GROUP: int = 8
const GROUP_COUNT: int = 9

var chunk_size: float = 32.0
var mid_instances: Array[MultiMeshInstance3D] = []
var far_instances: Array[MultiMeshInstance3D] = []
var placeholder_instance: MultiMeshInstance3D
var transform_dirty: bool = false
var animation_dirty: bool = false
var visual_dirty: bool = false
var dirty_instance_count: int = 0
var last_update_frame: int = -1

func setup(
	mid_meshes: Array[Mesh],
	far_meshes: Array[Mesh],
	mid_materials: Array,
	far_materials: Array,
	placeholder_mesh: Mesh,
	placeholder_material: Material,
	chunk_center: Vector3,
	new_chunk_size: float
) -> void:
	chunk_size = new_chunk_size
	position = chunk_center
	for archetype_id: int in range(ARCHETYPE_COUNT):
		var mid_instance := _create_instance(
			"MidMultiMesh_%d" % archetype_id,
			mid_meshes[archetype_id],
			mid_materials[archetype_id],
			Vector3(-chunk_size * 0.5, -0.2, -chunk_size * 0.5),
			Vector3(chunk_size, 3.4, chunk_size)
		)
		add_child(mid_instance)
		mid_instances.append(mid_instance)
		var far_instance := _create_instance(
			"FarMultiMesh_%d" % archetype_id,
			far_meshes[archetype_id],
			far_materials[archetype_id],
			Vector3(-chunk_size * 0.5, -0.2, -chunk_size * 0.5),
			Vector3(chunk_size, 3.0, chunk_size)
		)
		add_child(far_instance)
		far_instances.append(far_instance)
	placeholder_instance = _create_instance(
		"PlaceholderMultiMesh",
		placeholder_mesh,
		placeholder_material,
		Vector3(-chunk_size * 0.5, -0.2, -chunk_size * 0.5),
		Vector3(chunk_size, 4.0, chunk_size)
	)
	add_child(placeholder_instance)
	for group_id: int in range(GROUP_COUNT):
		set_group_visible(group_id, false)

func resize_group(group_id: int, instance_count: int) -> void:
	var instance: MultiMeshInstance3D = group_instance(group_id)
	if instance == null or instance.multimesh == null:
		return
	instance.multimesh.instance_count = instance_count
	instance.visible = instance_count > 0

func clear_dirty_state() -> void:
	transform_dirty = false
	animation_dirty = false
	visual_dirty = false
	dirty_instance_count = 0

func mark_dirty(transform: bool, animation: bool, visual: bool, instance_count: int) -> void:
	transform_dirty = transform_dirty or transform
	animation_dirty = animation_dirty or animation
	visual_dirty = visual_dirty or visual
	dirty_instance_count += instance_count

func set_group_visible(group_id: int, is_visible: bool) -> void:
	var instance: MultiMeshInstance3D = group_instance(group_id)
	if instance != null:
		instance.visible = is_visible and instance.multimesh != null and instance.multimesh.instance_count > 0

func group_instance(group_id: int) -> MultiMeshInstance3D:
	if group_id >= MID_GROUP_BASE and group_id < FAR_GROUP_BASE:
		return mid_instances[group_id - MID_GROUP_BASE]
	if group_id >= FAR_GROUP_BASE and group_id < PLACEHOLDER_GROUP:
		return far_instances[group_id - FAR_GROUP_BASE]
	if group_id == PLACEHOLDER_GROUP:
		return placeholder_instance
	return null

func group_instance_count(group_id: int) -> int:
	var instance: MultiMeshInstance3D = group_instance(group_id)
	if instance == null or instance.multimesh == null:
		return 0
	return instance.multimesh.instance_count

func _create_instance(
	instance_name: String,
	mesh: Mesh,
	material: Material,
	custom_aabb_position: Vector3,
	custom_aabb_size: Vector3
) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	instance.name = instance_name
	instance.material_override = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.custom_aabb = AABB(custom_aabb_position, custom_aabb_size)
	instance.multimesh = multimesh
	return instance
