extends SceneTree

# Test-only proof that the main RD can write the existing 2D MultiMesh layout.
# No gameplay owner, animation clock, or production renderer is changed here.
const OUTPUT := "res://output/site_crowd_gpu_20260924/p1_canvas_probe"
const SIZE := Vector2i(512, 352)
const COLUMNS := 40
const KERNEL := """
#version 450
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Instances { float data[]; } instances;
layout(push_constant, std430) uniform Params { uint count; uint columns; uint unused0; uint unused1; } params;
void main() {
    uint i = gl_GlobalInvocationID.x;
    if (i >= params.count) return;
    uint at = i * 12u;
    instances.data[at + 0u] = 8.0;
    instances.data[at + 1u] = 0.0;
    instances.data[at + 2u] = 0.0;
    instances.data[at + 3u] = 12.0 + float(i % params.columns) * 12.0;
    instances.data[at + 4u] = 0.0;
    instances.data[at + 5u] = 8.0;
    instances.data[at + 6u] = 0.0;
    instances.data[at + 7u] = 12.0 + float(i / params.columns) * 12.0;
    instances.data[at + 8u] = i % 3u == 0u ? 1.0 : 0.0;
    instances.data[at + 9u] = i % 3u == 1u ? 1.0 : 0.0;
    instances.data[at + 10u] = i % 3u == 2u ? 1.0 : 0.0;
    instances.data[at + 11u] = 1.0;
}
"""
const CANVAS_SHADER := """
shader_type canvas_item;
varying flat vec4 instance_color;
void vertex() { instance_color = INSTANCE_CUSTOM; }
void fragment() { COLOR = instance_color; }
"""

var _status_mutex := Mutex.new()
var _status := {"done": false, "ok": false, "error": ""}
var _owned_rd_rids: Array[RID] = [] # Only accessed in render-thread callbacks.
var _finished := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_rendering_device() == null:
		_fail("A GPU-backed main RenderingDevice is required")
		return
	create_timer(60.0).timeout.connect(func() -> void:
		if not _finished: _fail("Probe deadline (60 seconds)"))
	var directory := ProjectSettings.globalize_path(OUTPUT)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		_fail("Cannot create probe output directory")
		return
	var mesh := _make_mesh()
	var shader := Shader.new()
	shader.code = CANVAS_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	var white := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	white.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(white)
	var report := {"engine": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(), "gpu": RenderingServer.get_video_adapter_name(),
		"layout_floats": 12, "main_rd": true, "cpu_readback_in_render_loop_bytes": 0, "cases": []}
	for count in [0, 1, 65, 1000]:
		var cpu := _make_viewport(count, mesh, material, texture, true)
		var gpu := _make_viewport(count, mesh, material, texture, false)
		for frame in 2:
			await process_frame
			await RenderingServer.frame_post_draw
		if count > 0:
			_set_status(false, false, "")
			RenderingServer.call_on_render_thread(_write_gpu.bind((gpu.batch as MultiMeshInstance2D).multimesh.get_rid(), count))
			var completed := false
			var dispatch_deadline := Time.get_ticks_msec() + 15000
			while Time.get_ticks_msec() < dispatch_deadline:
				await process_frame
				var status := _get_status()
				if status.done:
					completed = true
					break
			if not completed or not _get_status().ok:
				report.cases.append({"count": count, "matched": false,
					"buffer_rd_rid_valid": bool(_get_status().get("buffer_rd_rid_valid", false)),
					"dispatch_groups": int(_get_status().get("dispatch_groups", 0)),
					"error": "Render-thread callback timed out" if not completed else str(_get_status().error)})
				_write_report(directory, report)
				_fail("Main RD dispatch failed for %d: %s" % [count, _get_status().error])
				return
		for frame in 3:
			await process_frame
			await RenderingServer.frame_post_draw
		var reference: Image = (cpu.viewport as SubViewport).get_texture().get_image()
		var result: Image = (gpu.viewport as SubViewport).get_texture().get_image()
		reference.convert(Image.FORMAT_RGBA8)
		result.convert(Image.FORMAT_RGBA8)
		var reference_bytes := reference.get_data()
		var result_bytes := result.get_data()
		if reference_bytes.size() != result_bytes.size():
			_fail("Capture byte counts differ at count %d" % count)
			return
		var differing_pixels := 0
		var covered_pixels := 0
		for offset in range(0, reference_bytes.size(), 4):
			if reference_bytes[offset + 3] != 0: covered_pixels += 1
			if reference_bytes[offset] != result_bytes[offset] or reference_bytes[offset + 1] != result_bytes[offset + 1] or reference_bytes[offset + 2] != result_bytes[offset + 2] or reference_bytes[offset + 3] != result_bytes[offset + 3]: differing_pixels += 1
		var matched: bool = differing_pixels == 0 and (covered_pixels > 0) == (count > 0)
		if reference.save_png("%s/cpu_%d.png" % [directory, count]) != OK or result.save_png("%s/gpu_%d.png" % [directory, count]) != OK:
			_fail("Cannot write paired captures for count %d" % count)
			return
		var dispatch_status := _get_status() if count > 0 else {}
		report.cases.append({"count": count, "matched": matched, "differing_pixels": differing_pixels,
			"covered_pixels": covered_pixels, "gpu_dispatches": 1 if count > 0 else 0,
			"dispatch_groups": int(dispatch_status.get("dispatch_groups", 0)),
			"buffer_rd_rid_valid": bool(dispatch_status.get("buffer_rd_rid_valid", false)) if count > 0 else null,
			"gpu_initial_cpu_buffer_bytes": count * 48, "gpu_instance_buffer_readback_bytes": 0,
			"test_screenshot_readback_bytes": reference_bytes.size() + result_bytes.size()})
		if count > 0:
			_set_status(false, false, "")
			RenderingServer.call_on_render_thread(_release_gpu)
			var released := false
			var release_deadline := Time.get_ticks_msec() + 5000
			while Time.get_ticks_msec() < release_deadline:
				await process_frame
				if _get_status().done:
					released = true
					break
			if not released:
				_fail("Main RD resource release timed out")
				return
		(cpu.viewport as SubViewport).queue_free()
		(gpu.viewport as SubViewport).queue_free()
		await process_frame
		if not matched:
			_write_report(directory, report)
			_fail("Canvas pixel mismatch at count %d; see probe captures" % count)
			return
	_write_report(directory, report)
	_finished = true
	print("SITE_CROWD_GPU_CANVAS_PROBE_PASS cases=0,1,65,1000 output=", directory)
	quit(0)


func _make_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2.ZERO, Vector2.DOWN, Vector2.ONE, Vector2.RIGHT])
	arrays[Mesh.ARRAY_TEX_UV] = arrays[Mesh.ARRAY_VERTEX]
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_viewport(count: int, mesh: ArrayMesh, material: ShaderMaterial, texture: Texture2D, cpu: bool) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var batch := MultiMeshInstance2D.new()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = count
	multimesh.custom_aabb = AABB(Vector3.ZERO, Vector3(SIZE.x, SIZE.y, 2))
	if count > 0:
		# A one-time CPU initialization establishes the engine's buffer state.
		# The GPU case receives no CPU instance data after compute dispatch.
		var initial := _expected_buffer(count) if cpu else PackedFloat32Array()
		if not cpu: initial.resize(count * 12)
		multimesh.buffer = initial
	batch.multimesh = multimesh
	batch.texture = texture
	batch.material = material
	viewport.add_child(batch)
	return {"viewport": viewport, "batch": batch}


func _expected_buffer(count: int) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(count * 12)
	for i in count:
		var at := i * 12
		buffer[at] = 8.0
		buffer[at + 3] = 12.0 + float(i % COLUMNS) * 12.0
		buffer[at + 5] = 8.0
		buffer[at + 7] = 12.0 + floor(float(i) / float(COLUMNS)) * 12.0
		buffer[at + 8] = 1.0 if i % 3 == 0 else 0.0
		buffer[at + 9] = 1.0 if i % 3 == 1 else 0.0
		buffer[at + 10] = 1.0 if i % 3 == 2 else 0.0
		buffer[at + 11] = 1.0
	return buffer


func _write_gpu(multimesh_rid: RID, count: int) -> void:
	var rd := RenderingServer.get_rendering_device()
	var buffer := RenderingServer.multimesh_get_buffer_rd_rid(multimesh_rid)
	if rd == null or not buffer.is_valid():
		_set_status(true, false, "MultiMesh RD buffer unavailable")
		return
	var source := RDShaderSource.new()
	source.source_compute = KERNEL
	var spirv := rd.shader_compile_spirv_from_source(source)
	var error := spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not error.is_empty():
		_set_status(true, false, error, true)
		return
	var shader := rd.shader_create_from_spirv(spirv)
	if not shader.is_valid():
		_set_status(true, false, "Shader creation failed", true)
		return
	_owned_rd_rids = [shader]
	var pipeline := rd.compute_pipeline_create(shader)
	if not pipeline.is_valid():
		_free_owned_rd_rids(rd)
		_set_status(true, false, "Pipeline creation failed", true)
		return
	_owned_rd_rids.push_front(pipeline)
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0
	uniform.add_id(buffer)
	var uniform_set := rd.uniform_set_create([uniform], shader, 0)
	if not uniform_set.is_valid():
		_free_owned_rd_rids(rd)
		_set_status(true, false, "MultiMesh buffer could not bind as a storage buffer", true)
		return
	_owned_rd_rids.push_front(uniform_set)
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	var parameters := PackedInt32Array([count, COLUMNS, 0, 0]).to_byte_array()
	rd.compute_list_set_push_constant(list, parameters, parameters.size())
	var groups := ceili(float(count) / 64.0)
	rd.compute_list_dispatch(list, groups, 1, 1)
	rd.compute_list_end()
	# The main RD is submitted by the engine. No local-device submit/sync here.
	_set_status(true, true, "", true, groups)


func _release_gpu() -> void:
	var rd := RenderingServer.get_rendering_device()
	_free_owned_rd_rids(rd)
	_set_status(true, true, "")


func _free_owned_rd_rids(rd: RenderingDevice) -> void:
	if rd != null:
		# Uniform set first, then pipeline and shader; the observed canvas frame
		# has already completed before this callback is queued.
		for rid: RID in _owned_rd_rids:
			if rid.is_valid(): rd.free_rid(rid)
	_owned_rd_rids.clear()


func _set_status(done: bool, ok: bool, error: String, buffer_rd_rid_valid: bool = false, dispatch_groups: int = 0) -> void:
	_status_mutex.lock()
	_status = {"done": done, "ok": ok, "error": error,
		"buffer_rd_rid_valid": buffer_rd_rid_valid, "dispatch_groups": dispatch_groups}
	_status_mutex.unlock()


func _get_status() -> Dictionary:
	_status_mutex.lock()
	var snapshot := _status.duplicate()
	_status_mutex.unlock()
	return snapshot


func _write_report(directory: String, report: Dictionary) -> void:
	var file := FileAccess.open(directory.path_join("report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()


func _fail(reason: String) -> void:
	if _finished: return
	_finished = true
	push_error("SITE_CROWD_GPU_CANVAS_PROBE_FAIL: " + reason)
	quit(1)
