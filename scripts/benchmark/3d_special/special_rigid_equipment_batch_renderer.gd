class_name SpecialRigidEquipmentBatchRenderer
extends Node3D

const DefinitionType = preload("res://scripts/benchmark/3d_special/special_visual_definition.gd")
const RegistryType = preload("res://scripts/benchmark/3d_special/rigid_equipment_render_registry.gd")
const ShadowBudgetType = preload("res://scripts/benchmark/3d_special/special_shadow_budget.gd")

const EQUIPMENT_SLOTS: Array[int] = [
	DefinitionType.Slot.HAIR,
	DefinitionType.Slot.HELMET,
	DefinitionType.Slot.WEAPON,
	DefinitionType.Slot.SHIELD
]

var registry: RigidEquipmentRenderRegistry
var capacity: int = 0
var enabled: bool = false
var material_consolidation_enabled: bool = false
var shadow_mode: int = ShadowBudgetType.Mode.ALL
var max_full_shadow_actors: int = 24
var socket_update_stride: int = 1

var last_update_cpu_ms: float = 0.0
var last_transform_updates: int = 0
var last_upload_calls: int = 0
var last_buffer_upload_calls: int = 0
var last_bytes_uploaded: int = 0
var structural_changes_this_frame: int = 0
var total_structural_changes: int = 0

var _groups: Dictionary = {}
var _actor_bindings: Array = []
var _actor_refs: Array = []
var _frame_index: int = 0

func setup(target_registry: RigidEquipmentRenderRegistry, requested_capacity: int) -> void:
	registry = target_registry
	capacity = maxi(requested_capacity, 0)
	_actor_bindings.resize(capacity)
	_actor_refs.resize(capacity)
	for index: int in range(capacity):
		_actor_bindings[index] = []
		_actor_refs[index] = null
	visible = false

func configure(
	should_enable: bool,
	use_material_consolidation: bool,
	next_shadow_mode: int,
	next_max_full_shadow_actors: int,
	next_socket_update_stride: int = 1
) -> void:
	var changed: bool = (
		enabled != should_enable
		or material_consolidation_enabled != use_material_consolidation
		or shadow_mode != next_shadow_mode
		or max_full_shadow_actors != next_max_full_shadow_actors
		or socket_update_stride != next_socket_update_stride
	)
	enabled = should_enable
	material_consolidation_enabled = use_material_consolidation
	shadow_mode = next_shadow_mode
	max_full_shadow_actors = maxi(next_max_full_shadow_actors, 0)
	socket_update_stride = clampi(next_socket_update_stride, 1, 4)
	if not enabled:
		clear_all()
		visible = false
	elif changed:
		_rebuild_bindings()

func clear_all() -> void:
	for actor_slot: int in range(_actor_bindings.size()):
		_release_actor(actor_slot)
	for group: Dictionary in _groups.values():
		(group["node"] as MultiMeshInstance3D).visible = false
	visible = false

func bind_actor(actor_slot: int, actor: SpecialCharacterVisual3D) -> void:
	if actor_slot < 0 or actor_slot >= capacity:
		return
	_release_actor(actor_slot)
	_actor_refs[actor_slot] = actor
	if not enabled or actor == null or not actor.visible:
		return
	var bindings: Array = []
	for equipment_slot: int in EQUIPMENT_SLOTS:
		var mesh_instance: MeshInstance3D = actor.rigid_equipment_instance_for_slot(equipment_slot)
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		if not actor.rigid_equipment_requested_for_slot(equipment_slot):
			continue
		var equipment_id: StringName = actor.rigid_equipment_id_for_slot(equipment_slot)
		if equipment_id.is_empty() or registry == null:
			continue
		var descriptor: Dictionary = registry.descriptor(equipment_slot, equipment_id)
		if descriptor.is_empty():
			continue
		var shadow_bucket: int = 1 if ShadowBudgetType.rigid_casts(
			int(descriptor["shadow_class"]), shadow_mode, actor_slot, max_full_shadow_actors
		) else 0
		var material: Material = (
			descriptor["shared_material"] if material_consolidation_enabled else descriptor["material"]
		)
		var group_key: String = _group_key(mesh_instance.mesh, material, shadow_bucket)
		var group: Dictionary = _ensure_group(group_key, descriptor, material, shadow_bucket)
		var free_slots: Array = group["free_slots"]
		if free_slots.is_empty():
			continue
		var instance_slot: int = int(free_slots.pop_back())
		group["active_count"] = int(group["active_count"]) + 1
		group["node"].visible = true
		bindings.append({
			"group_key": group_key,
			"instance_slot": instance_slot,
			"equipment_slot": equipment_slot,
			"actor": actor
		})
		var initial_buffer: PackedFloat32Array = group["buffer"]
		_write_transform(
			initial_buffer,
			instance_slot,
			global_transform.affine_inverse() * actor.get_rigid_equipment_transform(equipment_slot)
		)
		group["buffer"] = initial_buffer
		structural_changes_this_frame += 1
		total_structural_changes += 1
		_groups[group_key] = group
	_actor_bindings[actor_slot] = bindings
	if not bindings.is_empty():
		actor.set_rigid_equipment_batched(true)

func refresh_actor_binding(actor_slot: int, actor: SpecialCharacterVisual3D) -> void:
	if not enabled:
		return
	if not _binding_matches(actor_slot, actor):
		bind_actor(actor_slot, actor)

func release_actor(actor_slot: int) -> void:
	_release_actor(actor_slot)

func unique_materials() -> Array[Material]:
	var result: Array[Material] = []
	for group: Dictionary in _groups.values():
		if int(group["active_count"]) <= 0:
			continue
		var material: Material = group["material"]
		if material != null and not result.has(material):
			result.append(material)
	return result

func unique_meshes() -> Array[Mesh]:
	var result: Array[Mesh] = []
	for group: Dictionary in _groups.values():
		if int(group["active_count"]) <= 0:
			continue
		var mesh: Mesh = group["mesh"]
		if mesh != null and not result.has(mesh):
			result.append(mesh)
	return result

func update_transforms() -> void:
	var started_usec: int = Time.get_ticks_usec()
	_frame_index += 1
	last_transform_updates = 0
	last_upload_calls = 0
	last_buffer_upload_calls = 0
	last_bytes_uploaded = 0
	if socket_update_stride > 1 and posmod(_frame_index, socket_update_stride) != 0:
		last_update_cpu_ms = float(Time.get_ticks_usec() - started_usec) / 1000.0
		return
	if not enabled:
		last_update_cpu_ms = float(Time.get_ticks_usec() - started_usec) / 1000.0
		return
	var dirty_groups: Dictionary = {}
	for actor_slot: int in range(_actor_bindings.size()):
		var bindings: Array = _actor_bindings[actor_slot]
		for binding: Dictionary in bindings:
			var group: Dictionary = _groups.get(binding["group_key"], {})
			if group.is_empty():
				continue
			var actor: SpecialCharacterVisual3D = binding["actor"]
			var transform: Transform3D = global_transform.affine_inverse() * actor.get_rigid_equipment_transform(
				int(binding["equipment_slot"])
			)
			var buffer: PackedFloat32Array = group["buffer"]
			_write_transform(buffer, int(binding["instance_slot"]), transform)
			group["buffer"] = buffer
			_groups[binding["group_key"]] = group
			dirty_groups[binding["group_key"]] = group
			last_transform_updates += 1
	for group: Dictionary in dirty_groups.values():
		(group["multimesh"] as MultiMesh).buffer = group["buffer"]
		last_buffer_upload_calls += 1
		last_bytes_uploaded += (group["buffer"] as PackedFloat32Array).size() * 4
	last_upload_calls = last_buffer_upload_calls
	last_update_cpu_ms = float(Time.get_ticks_usec() - started_usec) / 1000.0
	visible = last_transform_updates > 0

func stats() -> Dictionary:
	var result: Dictionary = {
		"nodes": 0,
		"active_instances": 0,
		"draw_calls": 0,
		"triangles": 0,
		"shadow_instances": 0,
		"unique_meshes": 0,
		"unique_materials": 0,
		"groups": 0,
		"transform_updates": last_transform_updates,
		"upload_calls": last_upload_calls,
		"buffer_upload_calls": last_buffer_upload_calls,
		"bytes_uploaded": last_bytes_uploaded,
		"structural_changes": structural_changes_this_frame
	}
	var meshes: Array[Mesh] = []
	var materials: Array[Material] = []
	for group: Dictionary in _groups.values():
		var active_count: int = int(group["active_count"])
		if active_count <= 0:
			continue
		result["nodes"] += 1
		result["groups"] += 1
		result["active_instances"] += active_count
		var mesh: Mesh = group["mesh"]
		var material: Material = group["material"]
		if mesh != null and not meshes.has(mesh):
			meshes.append(mesh)
		if material != null and not materials.has(material):
			materials.append(material)
		var surfaces: int = mesh.get_surface_count() if mesh != null else 0
		result["draw_calls"] += surfaces
		result["triangles"] += _mesh_triangle_count(mesh) * active_count
		if bool(group["casts_shadow"]):
			result["shadow_instances"] += active_count
	result["unique_meshes"] = meshes.size()
	result["unique_materials"] = materials.size()
	return result

func component_breakdown() -> Dictionary:
	var result: Dictionary = {}
	for group: Dictionary in _groups.values():
		var active_count: int = int(group["active_count"])
		if active_count <= 0:
			continue
		var category: StringName = group["category"]
		var component: StringName = StringName("RigidBatch_%s" % str(category))
		if not result.has(component):
			result[component] = {
				"mesh_instances": 0, "instances": 0, "surfaces": 0, "draw_calls": 0,
				"triangles": 0, "skinned_meshes": 0, "shadow_meshes": 0
			}
		var entry: Dictionary = result[component]
		var mesh: Mesh = group["mesh"]
		var surfaces: int = mesh.get_surface_count() if mesh != null else 0
		entry["mesh_instances"] += 1
		entry["instances"] += active_count
		entry["surfaces"] += surfaces
		entry["draw_calls"] += surfaces
		entry["triangles"] += _mesh_triangle_count(mesh) * active_count
		entry["shadow_meshes"] += active_count if bool(group["casts_shadow"]) else 0
		result[component] = entry
	return result

func audit() -> Dictionary:
	var result: Dictionary = {}
	for group: Dictionary in _groups.values():
		var key: String = group["group_key"]
		result[key] = {
			"equipment_id": group["equipment_id"],
			"category": group["category"],
			"instances": group["active_count"],
			"mesh_resource_id": group["mesh"].get_instance_id() if group["mesh"] != null else 0,
			"material_resource_id": group["material"].get_instance_id() if group["material"] != null else 0,
			"casts_shadow": group["casts_shadow"]
		}
	return result

func _ensure_group(
	group_key: String,
	descriptor: Dictionary,
	material: Material,
	shadow_bucket: int
) -> Dictionary:
	if _groups.has(group_key):
		return _groups[group_key]
	var mesh: Mesh = descriptor["mesh"]
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = capacity
	var buffer := PackedFloat32Array()
	buffer.resize(capacity * 12)
	for instance_slot: int in range(capacity):
		_write_transform(buffer, instance_slot, _hidden_transform())
	var node := MultiMeshInstance3D.new()
	node.name = "RigidBatch_%s" % group_key.replace("|", "_")
	node.multimesh = multimesh
	node.material_override = material
	node.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if shadow_bucket != 0 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	node.visible = false
	add_child(node)
	var free_slots: Array[int] = []
	for instance_slot: int in range(capacity - 1, -1, -1):
		free_slots.append(instance_slot)
	var group: Dictionary = {
		"group_key": group_key,
		"node": node,
		"multimesh": multimesh,
		"buffer": buffer,
		"mesh": mesh,
		"material": material,
		"category": descriptor["category"],
		"equipment_id": descriptor["equipment_id"],
		"casts_shadow": shadow_bucket != 0,
		"free_slots": free_slots,
		"active_count": 0
	}
	_groups[group_key] = group
	return group

func _release_actor(actor_slot: int) -> void:
	if actor_slot < 0 or actor_slot >= _actor_bindings.size():
		return
	var bindings: Array = _actor_bindings[actor_slot]
	if bindings.is_empty():
		return
	for binding: Dictionary in bindings:
		var group: Dictionary = _groups.get(binding["group_key"], {})
		if group.is_empty():
			continue
		var instance_slot: int = int(binding["instance_slot"])
		var hidden_buffer: PackedFloat32Array = group["buffer"]
		_write_transform(hidden_buffer, instance_slot, _hidden_transform())
		group["buffer"] = hidden_buffer
		(group["free_slots"] as Array).append(instance_slot)
		group["active_count"] = maxi(int(group["active_count"]) - 1, 0)
		(group["node"] as MultiMeshInstance3D).visible = int(group["active_count"]) > 0
		_groups[binding["group_key"]] = group
		structural_changes_this_frame += 1
		total_structural_changes += 1
	var actor: SpecialCharacterVisual3D = _actor_refs[actor_slot]
	if actor != null:
		actor.set_rigid_equipment_batched(false)
	_actor_bindings[actor_slot] = []

func _binding_matches(actor_slot: int, actor: SpecialCharacterVisual3D) -> bool:
	if actor_slot < 0 or actor_slot >= _actor_bindings.size() or actor == null:
		return false
	var expected: Array = []
	for equipment_slot: int in EQUIPMENT_SLOTS:
		var mesh_instance: MeshInstance3D = actor.rigid_equipment_instance_for_slot(equipment_slot)
		if mesh_instance == null or mesh_instance.mesh == null or not actor.rigid_equipment_requested_for_slot(equipment_slot):
			continue
		var equipment_id: StringName = actor.rigid_equipment_id_for_slot(equipment_slot)
		var descriptor: Dictionary = registry.descriptor(equipment_slot, equipment_id) if registry != null else {}
		if descriptor.is_empty():
			continue
		var shadow_bucket: int = 1 if ShadowBudgetType.rigid_casts(
			int(descriptor["shadow_class"]), shadow_mode, actor_slot, max_full_shadow_actors
		) else 0
		var material: Material = descriptor["shared_material"] if material_consolidation_enabled else descriptor["material"]
		expected.append({
			"equipment_slot": equipment_slot,
			"group_key": _group_key(mesh_instance.mesh, material, shadow_bucket)
		})
	var bindings: Array = _actor_bindings[actor_slot]
	if bindings.size() != expected.size():
		return false
	for expected_item: Dictionary in expected:
		var found: bool = false
		for binding: Dictionary in bindings:
			if binding["equipment_slot"] == expected_item["equipment_slot"] and binding["group_key"] == expected_item["group_key"]:
				found = true
				break
		if not found:
			return false
	return true

func _rebuild_bindings() -> void:
	var actors: Array = _actor_refs.duplicate()
	clear_all()
	for actor_slot: int in range(actors.size()):
		var actor: SpecialCharacterVisual3D = actors[actor_slot]
		if actor != null and actor.visible:
			bind_actor(actor_slot, actor)

func _group_key(mesh: Mesh, material: Material, shadow_bucket: int) -> String:
	return "mesh=%d|mat=%d|shadow=%d" % [
		mesh.get_instance_id() if mesh != null else 0,
		material.get_instance_id() if material != null else 0,
		shadow_bucket
	]

func _hidden_transform() -> Transform3D:
	return Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0.0, -10000.0, 0.0))

func _write_transform(buffer: PackedFloat32Array, instance_slot: int, transform: Transform3D) -> void:
	var base: int = instance_slot * 12
	var basis: Basis = transform.basis
	var origin: Vector3 = transform.origin
	buffer[base + 0] = basis.x.x
	buffer[base + 1] = basis.y.x
	buffer[base + 2] = basis.z.x
	buffer[base + 3] = origin.x
	buffer[base + 4] = basis.x.y
	buffer[base + 5] = basis.y.y
	buffer[base + 6] = basis.z.y
	buffer[base + 7] = origin.y
	buffer[base + 8] = basis.x.z
	buffer[base + 9] = basis.y.z
	buffer[base + 10] = basis.z.z
	buffer[base + 11] = origin.z

func _mesh_triangle_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total: int = 0
	for surface_index: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var index_data: Variant = arrays[Mesh.ARRAY_INDEX]
		if index_data is PackedInt32Array and not (index_data as PackedInt32Array).is_empty():
			total += (index_data as PackedInt32Array).size() / 3
		elif arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array:
			total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total
