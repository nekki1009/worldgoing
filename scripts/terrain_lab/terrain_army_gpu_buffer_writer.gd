extends RefCounted

# Private P1 Canvas writer. All RenderingDevice resources live on the render thread.
const KERNEL := """
#version 450
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Instances { float data[]; } instances;
layout(set = 0, binding = 1, std430) readonly buffer Compact { float data[]; } compact;
layout(push_constant, std430) uniform Params { uint count; float scale; uint unused0; uint unused1; } params;
void main() {
    uint i = gl_GlobalInvocationID.x;
    if (i >= params.count) return;
    uint at = i * 12u;
    uint source = i * 5u;
    instances.data[at + 0u] = params.scale;
    instances.data[at + 1u] = 0.0;
    instances.data[at + 2u] = 0.0;
    instances.data[at + 3u] = compact.data[source + 0u];
    instances.data[at + 4u] = 0.0;
    instances.data[at + 5u] = params.scale;
    instances.data[at + 6u] = 0.0;
    instances.data[at + 7u] = compact.data[source + 1u];
    instances.data[at + 8u] = compact.data[source + 2u];
    instances.data[at + 9u] = compact.data[source + 3u];
    instances.data[at + 10u] = compact.data[source + 4u];
    instances.data[at + 11u] = 0.0;
}
"""

var _mutex := Mutex.new()
var _ready := false
var _error := ""
var _completed := 0
var _failure_callback: Callable
var _shader: RID # Render thread only from here down.
var _pipeline: RID
var _entries := {}

func start(failure_callback: Callable) -> void:
	_failure_callback = failure_callback
	RenderingServer.call_on_render_thread(_start_render)

func ready() -> bool:
	_mutex.lock()
	var result: bool = _ready and _error.is_empty()
	_mutex.unlock()
	return result

func completed_count() -> int:
	_mutex.lock()
	var result := _completed
	_mutex.unlock()
	return result

func last_error() -> String:
	_mutex.lock()
	var result := _error
	_mutex.unlock()
	return result

func write(key: Vector2i, multimesh_rid: RID, compact: PackedFloat32Array, count: int, scale: float) -> void:
	RenderingServer.call_on_render_thread(_write_render.bind(key, multimesh_rid, compact.to_byte_array(), count, scale))

func dispose() -> void:
	RenderingServer.call_on_render_thread(_dispose_render)

func retain_keys(keys: Array[Vector2i]) -> void:
	RenderingServer.call_on_render_thread(_retain_keys_render.bind(keys))

func _start_render() -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		_fail("Main RenderingDevice unavailable")
		return
	var source := RDShaderSource.new()
	source.source_compute = KERNEL
	var spirv := rd.shader_compile_spirv_from_source(source)
	var error := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not error.is_empty():
		_fail(error)
		return
	_shader = rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid():
		_fail("Compute shader creation failed")
		return
	_pipeline = rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid():
		rd.free_rid(_shader)
		_shader = RID()
		_fail("Compute pipeline creation failed")
		return
	_mutex.lock()
	_ready = true
	_mutex.unlock()

func _write_render(key: Vector2i, multimesh_rid: RID, bytes: PackedByteArray, count: int, scale: float) -> void:
	if not ready(): return
	var rd := RenderingServer.get_rendering_device()
	if rd == null or not _pipeline.is_valid():
		_fail("Main compute pipeline unavailable")
		return
	var output := RenderingServer.multimesh_get_buffer_rd_rid(multimesh_rid)
	if not output.is_valid():
		_fail("MultiMesh RD buffer unavailable")
		return
	var entry: Dictionary = _entries.get(key, {})
	if entry.is_empty() or entry.output != output or entry.size != bytes.size():
		_free_entry(rd, entry)
		_entries.erase(key)
		var input := rd.storage_buffer_create(bytes.size(), bytes)
		if not input.is_valid():
			_fail("Compact input buffer creation failed")
			return
		var output_uniform := RDUniform.new()
		output_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		output_uniform.binding = 0
		output_uniform.add_id(output)
		var input_uniform := RDUniform.new()
		input_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		input_uniform.binding = 1
		input_uniform.add_id(input)
		var uniform_set := rd.uniform_set_create([output_uniform, input_uniform], _shader, 0)
		if not uniform_set.is_valid():
			rd.free_rid(input)
			_fail("Compute uniform set creation failed")
			return
		entry = {"output": output, "input": input, "uniform_set": uniform_set, "size": bytes.size()}
		_entries[key] = entry
	elif rd.buffer_update(entry.input, 0, bytes.size(), bytes) != OK:
		_fail("Compact input upload failed")
		return
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, _pipeline)
	rd.compute_list_bind_uniform_set(list, entry.uniform_set, 0)
	var parameters := PackedByteArray()
	parameters.resize(16)
	parameters.encode_u32(0, count)
	parameters.encode_float(4, scale)
	rd.compute_list_set_push_constant(list, parameters, parameters.size())
	rd.compute_list_dispatch(list, (count + 63) >> 6, 1, 1)
	rd.compute_list_end()
	_mutex.lock()
	_completed += 1
	_mutex.unlock()

func _retain_keys_render(keys: Array[Vector2i]) -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd == null: return
	var retained := {}
	for key: Vector2i in keys: retained[key] = true
	for key: Vector2i in _entries.keys():
		if retained.has(key): continue
		_free_entry(rd, _entries[key])
		_entries.erase(key)

func _free_entry(rd: RenderingDevice, entry: Dictionary) -> void:
	if entry.is_empty(): return
	# The engine invalidates a set when the MultiMesh output buffer is resized.
	# RID.is_valid() only checks that the handle is nonzero, not that RD owns it.
	if entry.uniform_set.is_valid() and rd.uniform_set_is_valid(entry.uniform_set): rd.free_rid(entry.uniform_set)
	if entry.input.is_valid(): rd.free_rid(entry.input)

func _dispose_render() -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd == null: return
	for entry: Dictionary in _entries.values(): _free_entry(rd, entry)
	_entries.clear()
	if _pipeline.is_valid(): rd.free_rid(_pipeline)
	if _shader.is_valid(): rd.free_rid(_shader)
	_pipeline = RID()
	_shader = RID()
	_mutex.lock()
	_ready = false
	_mutex.unlock()

func _fail(message: String) -> void:
	_mutex.lock()
	_error = message
	_ready = false
	_mutex.unlock()
	if _failure_callback.is_valid(): _failure_callback.call_deferred(message)
