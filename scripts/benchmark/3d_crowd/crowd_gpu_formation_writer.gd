class_name CrowdGpuFormationWriter
extends RefCounted

# Owns only the experimental 3D Formation display resources. The MultiMesh
# output and its indirect argument buffer belong to RenderingServer.
const SHADER_PATH := "res://scripts/benchmark/3d_crowd/crowd_gpu_formation.glsl"
const WORKGROUP_SIZE := 64
const INSTANCE_STRIDE_BYTES := 64
const DESCRIPTOR_STRIDE_BYTES := 16

var _mutex := Mutex.new()
var _ready := false
var _error := ""
var _ready_batches := 0
var _completed_frames := 0
var _last_dispatches := 0
var _last_draw_span := 0
var _generation := 0
var _started := false
var _disposed := false

var _main_batches := {} # Main thread: keeps Mesh and Material resources alive.
var _render_batches := {} # Render thread only from here down.
var _shader: RID
var _pipeline: RID


func start() -> bool:
	if _started or _disposed:
		return false
	_started = true
	var source := FileAccess.get_file_as_string(SHADER_PATH)
	if source.is_empty():
		_fail("Formation compute shader source unavailable: " + SHADER_PATH)
		return false
	RenderingServer.call_on_render_thread(_start_render.bind(source))
	return true


func create_batch(
	key: int,
	scenario: RID,
	world_transform: Transform3D,
	mesh: Mesh,
	material: Material,
	capacity: int,
	bounds: AABB
) -> bool:
	if not _started or _disposed or _main_batches.has(key):
		return false
	if not scenario.is_valid() or mesh == null or material == null or capacity <= 0:
		return false
	if mesh.get_surface_count() != 1 or bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or bounds.size.z <= 0.0:
		return false
	_main_batches[key] = {
		"mesh": mesh, "material": material, "capacity": capacity,
		"visible": false, "world_transform": world_transform, "bounds": bounds
	}
	RenderingServer.call_on_render_thread(
		_create_batch_render.bind(key, scenario, world_transform, mesh.get_rid(), material.get_rid(), capacity, bounds)
	)
	return true


func set_batch_visual(
	key: int,
	mesh: Mesh,
	material: Material,
	visible: bool,
	world_transform: Transform3D
) -> void:
	if _disposed or not _main_batches.has(key) or mesh == null or material == null:
		return
	if mesh.get_surface_count() != 1:
		_fail("GPU Formation batch requires one mesh surface")
		return
	var batch: Dictionary = _main_batches[key]
	var mesh_changed: bool = batch["mesh"] != mesh
	var material_changed: bool = batch["material"] != material
	var visibility_changed: bool = batch["visible"] != visible
	var transform_changed: bool = batch["world_transform"] != world_transform
	if not (mesh_changed or material_changed or visibility_changed or transform_changed):
		return
	batch["mesh"] = mesh
	batch["material"] = material
	batch["visible"] = visible
	batch["world_transform"] = world_transform
	_main_batches[key] = batch
	RenderingServer.call_on_render_thread(
		_set_visual_render.bind(key, mesh.get_rid(), material.get_rid(), visible, world_transform, mesh_changed)
	)


func set_batch_scenario(key: int, scenario: RID) -> void:
	if _disposed or not _main_batches.has(key) or not scenario.is_valid():
		return
	RenderingServer.call_on_render_thread(_set_scenario_render.bind(key, scenario))


func set_batch_bounds(key: int, bounds: AABB) -> void:
	if _disposed or not _main_batches.has(key):
		return
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or bounds.size.z <= 0.0:
		_fail("GPU Formation bounds must have positive size")
		return
	var batch: Dictionary = _main_batches[key]
	if batch["bounds"] == bounds:
		return
	batch["bounds"] = bounds
	_main_batches[key] = batch
	RenderingServer.call_on_render_thread(_set_bounds_render.bind(key, bounds))


# Each command: key, center, facing, spacing, columns, rows, span.
# Optional right/forward override facing for renderer-local parent transforms.
# Optional bounds updates this batch's local culling AABB in the same callback.
# Each event: key, slot, phase, state, active, variant (integer 0..11).
# The packet is deep-copied before crossing the thread boundary.
func submit_frame(commands: Array, events: Array, handoff_instances: Array = []) -> void:
	if _disposed or not _started:
		return
	var immutable_commands := commands.duplicate(true)
	var immutable_events := events.duplicate(true)
	var immutable_handoff := handoff_instances.duplicate()
	RenderingServer.call_on_render_thread(
		_submit_frame_render.bind(immutable_commands, immutable_events, immutable_handoff, _current_generation())
	)


func request_snapshot(key: int, callback: Callable) -> void:
	if _disposed or not callback.is_valid():
		return
	RenderingServer.call_on_render_thread(_snapshot_render.bind(key, callback, _current_generation()))


func status() -> Dictionary:
	_mutex.lock()
	var result := {
		"ready": _ready,
		"error": _error,
		"batch_count": _main_batches.size(),
		"ready_batches": _ready_batches,
		"completed_frames": _completed_frames,
		"last_dispatches": _last_dispatches,
		"last_draw_span": _last_draw_span,
		"instance_stride_bytes": INSTANCE_STRIDE_BYTES,
		"descriptor_stride_bytes": DESCRIPTOR_STRIDE_BYTES
	}
	_mutex.unlock()
	return result


func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	_mutex.lock()
	_generation += 1
	_mutex.unlock()
	RenderingServer.call_on_render_thread(_dispose_render)


func _current_generation() -> int:
	_mutex.lock()
	var result := _generation
	_mutex.unlock()
	return result


func _start_render(source_text: String) -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		_fail("Main RenderingDevice unavailable; Forward+ is required")
		return
	var source := RDShaderSource.new()
	source.source_compute = source_text
	var spirv := rd.shader_compile_spirv_from_source(source)
	var compile_error := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not compile_error.is_empty():
		_fail("Formation compute compilation failed: " + compile_error)
		return
	_shader = rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		_fail("Formation compute shader creation failed")
		return
	_pipeline = rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():
		_fail("Formation compute pipeline creation failed")
		return
	_mutex.lock()
	_ready = true
	_mutex.unlock()


func _create_batch_render(
	key: int, scenario: RID, world_transform: Transform3D,
	mesh: RID, material: RID, capacity: int, bounds: AABB
) -> void:
	if not _render_is_ready():
		return
	var rd := RenderingServer.get_rendering_device()
	var multimesh := RenderingServer.multimesh_create()
	RenderingServer.multimesh_allocate_data(
		multimesh, capacity, RenderingServer.MULTIMESH_TRANSFORM_3D, false, true, true
	)
	RenderingServer.multimesh_set_mesh(multimesh, mesh)
	RenderingServer.multimesh_set_custom_aabb(multimesh, bounds)
	var visual_instance := RenderingServer.instance_create()
	RenderingServer.instance_set_base(visual_instance, multimesh)
	RenderingServer.instance_set_scenario(visual_instance, scenario)
	RenderingServer.instance_set_transform(visual_instance, world_transform)
	RenderingServer.instance_set_layer_mask(visual_instance, 1)
	RenderingServer.instance_geometry_set_cast_shadows_setting(
		visual_instance, RenderingServer.SHADOW_CASTING_SETTING_ON
	)
	RenderingServer.instance_geometry_set_material_override(visual_instance, material)
	RenderingServer.instance_set_visible(visual_instance, false)
	var descriptor_data := PackedFloat32Array()
	descriptor_data.resize(capacity * 4)
	var descriptor_buffer := rd.storage_buffer_create(capacity * DESCRIPTOR_STRIDE_BYTES, descriptor_data.to_byte_array())
	var entry := {
		"multimesh": multimesh, "visual_instance": visual_instance,
		"capacity": capacity, "descriptor": descriptor_buffer,
		"descriptor_data": descriptor_data, "output": RID(), "command": RID(),
		"uniform_set": RID(), "mesh": mesh, "material": material,
		"want_visible": false, "has_output": false, "bounds": bounds
	}
	if not descriptor_buffer.is_valid() or not _refresh_bindings_render(rd, entry):
		_free_batch_render(rd, entry)
		_fail("GPU Formation batch %d could not bind 3D output and indirect command" % key)
		return
	_render_batches[key] = entry
	_mutex.lock()
	_ready_batches += 1
	_mutex.unlock()


func _set_visual_render(
	key: int, mesh: RID, material: RID, visible: bool,
	world_transform: Transform3D, mesh_changed: bool
) -> void:
	if not _render_batches.has(key):
		return
	var entry: Dictionary = _render_batches[key]
	var visual_instance: RID = entry["visual_instance"]
	entry["want_visible"] = visible
	RenderingServer.instance_set_transform(visual_instance, world_transform)
	if mesh_changed:
		RenderingServer.instance_set_visible(visual_instance, false)
		entry["has_output"] = false
		RenderingServer.multimesh_set_mesh(entry["multimesh"], mesh)
		if not _refresh_bindings_render(RenderingServer.get_rendering_device(), entry):
			_fail("GPU Formation command buffer invalid after mesh change")
			return
		entry["mesh"] = mesh
	if entry["material"] != material:
		RenderingServer.instance_geometry_set_material_override(visual_instance, material)
		entry["material"] = material
	if not visible:
		RenderingServer.instance_set_visible(visual_instance, false)
	elif entry["has_output"]:
		RenderingServer.instance_set_visible(visual_instance, true)
	_render_batches[key] = entry


func _set_scenario_render(key: int, scenario: RID) -> void:
	if _render_batches.has(key):
		RenderingServer.instance_set_scenario(_render_batches[key]["visual_instance"], scenario)


func _set_bounds_render(key: int, bounds: AABB) -> void:
	if _render_batches.has(key):
		var entry: Dictionary = _render_batches[key]
		RenderingServer.multimesh_set_custom_aabb(entry["multimesh"], bounds)
		entry["bounds"] = bounds
		_render_batches[key] = entry


func _submit_frame_render(commands: Array, events: Array, handoff_instances: Array, generation: int) -> void:
	if generation != _current_generation() or not _render_is_ready():
		return
	var rd := RenderingServer.get_rendering_device()
	var changed_by_key := {}
	for event: Dictionary in events:
		var key: int = int(event.get("key", -1))
		if not _render_batches.has(key):
			continue
		if not changed_by_key.has(key):
			changed_by_key[key] = []
		changed_by_key[key].append(event)
	for key: int in changed_by_key:
		var entry: Dictionary = _render_batches[key]
		var descriptor_data: PackedFloat32Array = entry["descriptor_data"]
		var changed_slots := {}
		for event: Dictionary in changed_by_key[key]:
			var slot: int = int(event.get("slot", -1))
			if slot < 0 or slot >= int(entry["capacity"]):
				_fail("GPU Formation descriptor slot outside capacity")
				return
			var at: int = slot * 4
			descriptor_data[at] = float(event.get("phase", 0.0))
			descriptor_data[at + 1] = float(event.get("state", 0))
			descriptor_data[at + 2] = 1.0 if bool(event.get("active", true)) else 0.0
			descriptor_data[at + 3] = float(event.get("variant", 0)) / 11.0
			changed_slots[slot] = true
		entry["descriptor_data"] = descriptor_data
		_render_batches[key] = entry
		if changed_slots.size() > int(entry["capacity"]) / 2:
			var all_bytes := descriptor_data.to_byte_array()
			if rd.buffer_update(entry["descriptor"], 0, all_bytes.size(), all_bytes) != OK:
				_fail("GPU Formation descriptor upload failed")
				return
		else:
			for slot: int in changed_slots:
				var slot_bytes := descriptor_data.slice(slot * 4, slot * 4 + 4).to_byte_array()
				if rd.buffer_update(entry["descriptor"], slot * DESCRIPTOR_STRIDE_BYTES, DESCRIPTOR_STRIDE_BYTES, slot_bytes) != OK:
					_fail("GPU Formation descriptor event upload failed")
					return
	var prepared: Array[Dictionary] = []
	var seen_keys := {}
	var total_span := 0
	for command: Dictionary in commands:
		var key: int = int(command.get("key", -1))
		if not _render_batches.has(key):
			continue
		if seen_keys.has(key):
			_fail("GPU Formation packet contains duplicate batch key")
			return
		seen_keys[key] = true
		var entry: Dictionary = _render_batches[key]
		var capacity: int = int(entry["capacity"])
		var columns: int = int(command.get("columns", 10))
		var rows: int = int(command.get("rows", 10))
		var span: int = int(command.get("span", capacity))
		if columns <= 0 or rows <= 0 or span < 0 or span > capacity or span > columns * rows:
			_fail("GPU Formation shape/span exceeds batch capacity")
			return
		if command.has("bounds"):
			var bounds: AABB = command["bounds"]
			if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or bounds.size.z <= 0.0:
				_fail("GPU Formation command bounds must have positive size")
				return
			if entry["bounds"] != bounds:
				RenderingServer.multimesh_set_custom_aabb(entry["multimesh"], bounds)
				entry["bounds"] = bounds
		if not rd.uniform_set_is_valid(entry["uniform_set"]):
			if not _refresh_bindings_render(rd, entry):
				_fail("GPU Formation output bindings invalid")
				return
		var facing: float = float(command.get("facing", 0.0))
		var right: Vector3 = command.get("right", Vector3(cos(facing), 0.0, -sin(facing)))
		var forward: Vector3 = command.get("forward", Vector3(sin(facing), 0.0, cos(facing)))
		var packed := _pack_command(
			command.get("center", Vector3.ZERO), right, forward,
			float(command.get("spacing", 1.25)), columns, rows, span, capacity
		)
		_render_batches[key] = entry
		prepared.append({"key": key, "span": span, "uniform_set": entry["uniform_set"], "packed": packed})
		total_span += span
	if not prepared.is_empty():
		var list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list, _pipeline)
		for item: Dictionary in prepared:
			rd.compute_list_bind_uniform_set(list, item["uniform_set"], 0)
			var packed: PackedByteArray = item["packed"]
			rd.compute_list_set_push_constant(list, packed, packed.size())
			var span: int = item["span"]
			# One group is needed even for span 0 so lane 0 clears the indirect count.
			rd.compute_list_dispatch(list, maxi(1, (span + WORKGROUP_SIZE - 1) >> 6), 1, 1)
		rd.compute_list_end()
	for item: Dictionary in prepared:
		var key: int = item["key"]
		var entry: Dictionary = _render_batches[key]
		entry["has_output"] = true
		if entry["want_visible"]:
			RenderingServer.instance_set_visible(entry["visual_instance"], true)
		_render_batches[key] = entry
	if not prepared.is_empty():
		# The old Formation instances remain owned by their Nodes until the
		# main thread observes this committed render callback and frees them.
		for old_instance: RID in handoff_instances:
			if old_instance.is_valid():
				RenderingServer.instance_set_visible(old_instance, false)
	_mutex.lock()
	_completed_frames += 1
	_last_dispatches = prepared.size()
	_last_draw_span = total_span
	_mutex.unlock()


func _pack_command(
	center: Vector3, right: Vector3, forward: Vector3, spacing: float,
	columns: int, rows: int, span: int, capacity: int
) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(64)
	var floats := [center.x, center.y, center.z, spacing,
		right.x, right.y, right.z, 0.0,
		forward.x, forward.y, forward.z, 0.0]
	for index: int in range(floats.size()):
		bytes.encode_float(index * 4, floats[index])
	bytes.encode_u32(48, columns)
	bytes.encode_u32(52, rows)
	bytes.encode_u32(56, span)
	bytes.encode_u32(60, capacity)
	return bytes


func _refresh_bindings_render(rd: RenderingDevice, entry: Dictionary) -> bool:
	if rd == null:
		return false
	if entry["uniform_set"].is_valid() and rd.uniform_set_is_valid(entry["uniform_set"]):
		rd.free_rid(entry["uniform_set"])
	entry["uniform_set"] = RID()
	var output: RID = RenderingServer.multimesh_get_buffer_rd_rid(entry["multimesh"])
	var indirect: RID = RenderingServer.multimesh_get_command_buffer_rd_rid(entry["multimesh"])
	if not output.is_valid() or not indirect.is_valid() or not entry["descriptor"].is_valid():
		return false
	var output_uniform := RDUniform.new()
	output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	output_uniform.binding = 0
	output_uniform.add_id(output)
	var descriptor_uniform := RDUniform.new()
	descriptor_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	descriptor_uniform.binding = 1
	descriptor_uniform.add_id(entry["descriptor"])
	var command_uniform := RDUniform.new()
	command_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	command_uniform.binding = 2
	command_uniform.add_id(indirect)
	var uniform_set := rd.uniform_set_create([output_uniform, descriptor_uniform, command_uniform], _shader, 0)
	if not uniform_set.is_valid():
		return false
	entry["output"] = output
	entry["command"] = indirect
	entry["uniform_set"] = uniform_set
	return true


func _snapshot_render(key: int, callback: Callable, generation: int) -> void:
	if generation != _current_generation() or not _render_batches.has(key):
		return
	var entry: Dictionary = _render_batches[key]
	var rd := RenderingServer.get_rendering_device()
	var snapshot := {
		"key": key,
		"capacity": entry["capacity"],
		"output": rd.buffer_get_data(entry["output"]),
		"command": rd.buffer_get_data(entry["command"]),
		"descriptor": rd.buffer_get_data(entry["descriptor"])
	}
	callback.call_deferred(snapshot)


func _render_is_ready() -> bool:
	_mutex.lock()
	var result: bool = _ready and _error.is_empty()
	_mutex.unlock()
	return result


func _free_batch_render(rd: RenderingDevice, entry: Dictionary) -> void:
	if rd != null:
		var uniform_set: RID = entry.get("uniform_set", RID())
		if uniform_set.is_valid() and rd.uniform_set_is_valid(uniform_set):
			rd.free_rid(uniform_set)
		var descriptor: RID = entry.get("descriptor", RID())
		if descriptor.is_valid():
			rd.free_rid(descriptor)
	# The output RID always belongs to RenderingServer.
	var visual_instance: RID = entry.get("visual_instance", RID())
	if visual_instance.is_valid():
		RenderingServer.free_rid(visual_instance)
	var multimesh: RID = entry.get("multimesh", RID())
	if multimesh.is_valid():
		# Godot 4.7.2's _multimesh_free resets command_buffer without freeing
		# its RD storage buffer. LOD mesh changes free the prior command buffer.
		# Fetch the current RID after detaching the visual and free it exactly
		# once before RS discards its handle. Do not apply to other versions.
		var version: Dictionary = Engine.get_version_info()
		var affected_version: bool = (
			int(version.get("major", -1)) == 4
			and int(version.get("minor", -1)) == 7
			and int(version.get("patch", -1)) == 2
			and String(version.get("status", "")) == "stable"
		)
		if rd != null and affected_version:
			var current_command: RID = RenderingServer.multimesh_get_command_buffer_rd_rid(multimesh)
			if current_command.is_valid():
				rd.free_rid(current_command)
		RenderingServer.free_rid(multimesh)


func _dispose_render() -> void:
	var rd := RenderingServer.get_rendering_device()
	for entry: Dictionary in _render_batches.values():
		_free_batch_render(rd, entry)
	_render_batches.clear()
	if rd != null:
		if _pipeline.is_valid():
			rd.free_rid(_pipeline)
		if _shader.is_valid():
			rd.free_rid(_shader)
	_pipeline = RID()
	_shader = RID()
	_mutex.lock()
	_ready = false
	_ready_batches = 0
	_mutex.unlock()
	_finish_dispose_main.call_deferred()


func _finish_dispose_main() -> void:
	_main_batches.clear()


func _fail(message: String) -> void:
	_mutex.lock()
	_error = message
	_ready = false
	_mutex.unlock()
	push_error(message)
