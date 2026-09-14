extends RefCounted
## Experimental pure geometry worker. No clock, person, HP, pose or save state.
## Callers supply the original CPU bone palettes and consume results in order.
## One submit/readback per batch, never one dispatch per vertex or a later step.
## The injecting caller owns initialize/dispose; no script method calls during
## engine shutdown's PREDELETE (the GDScript instance can already be detached).
const MAX_VERTICES := 1048576
const MAX_MATRICES := 65536
const MAX_SURFACES := 16
const KERNEL := """
#version 450
layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;
layout(set=0,binding=0,std430) restrict readonly buffer Vertices { float v[]; };
layout(set=0,binding=1,std430) restrict readonly buffer Bones { int b[]; };
layout(set=0,binding=2,std430) restrict readonly buffer Weights { float w[]; };
layout(set=0,binding=3,std430) restrict readonly buffer Matrices { float m[]; };
layout(set=0,binding=4,std430) restrict writeonly buffer Output { float out_v[]; };
layout(push_constant,std430) uniform Params { uint count; uint influences; uint bones; uint jobs; } p;
// Match Transform3D::xform and the scalar Vector3 accumulation, including zero
// weights. 'precise' prevents contraction/reassociation; it is NOT an admission
// proof across different GPUs. Native bit comparisons are a separate gate.
vec3 transform_point(uint index, vec3 vertex) {
    uint k=index*12;
    precise float x=((m[k]*vertex.x+m[k+1]*vertex.y)+m[k+2]*vertex.z)+m[k+3];
    precise float y=((m[k+4]*vertex.x+m[k+5]*vertex.y)+m[k+6]*vertex.z)+m[k+7];
    precise float z=((m[k+8]*vertex.x+m[k+9]*vertex.y)+m[k+10]*vertex.z)+m[k+11];
    return vec3(x,y,z);
}
void main() {
    uint vertex=gl_GlobalInvocationID.x;
    uint job=gl_GlobalInvocationID.y;
    if(vertex>=p.count || job>=p.jobs) return;
    vec3 input_v=vec3(v[vertex*3],v[vertex*3+1],v[vertex*3+2]);
    precise vec3 point=vec3(0.0);
    for(uint slot=0;slot<p.influences;slot++) {
        uint i=vertex*p.influences+slot;
        precise vec3 term=transform_point(job*p.bones+uint(b[i]),input_v)*w[i];
        point=point+term;
    }
    uint target=(job*p.count+vertex)*3;
    out_v[target]=point.x; out_v[target+1]=point.y; out_v[target+2]=point.z;
}
"""

var rd: RenderingDevice
var shader := RID()
var pipeline := RID()
var matrix_buffer := RID()
var output_buffer := RID()
var surfaces: Dictionary = {}
var last_error := ""
var profile := {"batches": 0, "vertices": 0, "surface_upload_bytes": 0,
	"palette_upload_bytes": 0, "readback_bytes": 0, "pack_usec": 0,
	"submit_sync_usec": 0, "readback_usec": 0, "total_usec": 0}

func initialize() -> bool:
	if rd != null:
		return pipeline.is_valid()
	# Dummy/headless and double-real builds retain the original CPU path.
	if DisplayServer.get_name() == "headless" or PackedVector3Array([Vector3.ZERO]).to_byte_array().size() != 12:
		last_error = "GPU skinning requires a RenderingDevice and float32 Vector3 build"
		return false
	rd = RenderingServer.create_local_rendering_device()
	if rd == null:
		last_error = "RenderingDevice unavailable"
		return false
	var source := RDShaderSource.new()
	source.source_compute = KERNEL
	var spirv := rd.shader_compile_spirv_from_source(source)
	last_error = spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not last_error.is_empty():
		dispose()
		return false
	shader = rd.shader_create_from_spirv(spirv)
	if shader.is_valid():
		pipeline = rd.compute_pipeline_create(shader)
	if not pipeline.is_valid():
		last_error = "GPU skinning pipeline creation failed"
		dispose()
		return false
	matrix_buffer = rd.storage_buffer_create(MAX_MATRICES * 48)
	output_buffer = rd.storage_buffer_create(MAX_VERTICES * 12)
	if not matrix_buffer.is_valid() or not output_buffer.is_valid():
		last_error = "GPU skinning buffer allocation failed"
		dispose()
		return false
	return true

func register_surface(key: String, vertices: PackedVector3Array, bones: PackedInt32Array, weights: PackedFloat32Array) -> bool:
	if rd == null or vertices.is_empty() or vertices.size() > MAX_VERTICES or bones.is_empty() or bones.size() != weights.size() or bones.size() % vertices.size() != 0:
		return false
	var entry: Dictionary = surfaces.get(key, {})
	if not entry.is_empty() and entry.vertices == vertices and entry.bones == bones and entry.weights == weights:
		return true
	# Validate every referenced binding, including zero-weight ones as on CPU.
	var maximum_bone := -1
	for vertex: Vector3 in vertices:
		if not vertex.is_finite():
			return false
	for weight: float in weights:
		if not is_finite(weight):
			return false
	for bone: int in bones:
		if bone < 0:
			return false
		maximum_bone = maxi(maximum_bone, bone)
	if not entry.is_empty():
		_free_surface(entry)
		surfaces.erase(key)
	if surfaces.size() >= MAX_SURFACES:
		clear_surfaces() # ponytail: bounded resident arrays, no eviction framework.
	var buffers: Array[RID] = []
	for bytes: PackedByteArray in [vertices.to_byte_array(), bones.to_byte_array(), weights.to_byte_array()]:
		var buffer := rd.storage_buffer_create(bytes.size(), bytes)
		if not buffer.is_valid():
			for allocated: RID in buffers:
				rd.free_rid(allocated)
			return false
		buffers.append(buffer)
		profile.surface_upload_bytes += bytes.size()
	var bindings: Array[RDUniform] = []
	var bound_buffers := buffers + [matrix_buffer, output_buffer]
	for index in bound_buffers.size():
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = index
		uniform.add_id(bound_buffers[index])
		bindings.append(uniform)
	var uniform_set := rd.uniform_set_create(bindings, shader, 0)
	if not uniform_set.is_valid():
		for allocated: RID in buffers:
			rd.free_rid(allocated)
		return false
	# Packed arrays are reference types in GDScript. Keep independent snapshots
	# of the uploaded bytes so caller edits cannot disguise a required re-upload
	# or change dispatch lengths while the resident buffers still contain A.
	surfaces[key] = {"vertices": vertices.duplicate(), "bones": bones.duplicate(), "weights": weights.duplicate(),
		"maximum_bone": maximum_bone, "buffers": buffers, "uniform_set": uniform_set}
	return true

func skin_batch(key: String, palettes: Array) -> PackedVector3Array:
	var started := Time.get_ticks_usec()
	if rd == null or not surfaces.has(key) or palettes.is_empty():
		return PackedVector3Array()
	var entry: Dictionary = surfaces[key]
	var count: int = entry.vertices.size()
	var bone_count: int = palettes[0].size()
	if bone_count <= int(entry.maximum_bone) or bone_count * palettes.size() > MAX_MATRICES or count * palettes.size() > MAX_VERTICES or palettes.size() > 256:
		return PackedVector3Array()
	var matrices := PackedFloat32Array()
	for palette: Array in palettes:
		if palette.size() != bone_count:
			return PackedVector3Array()
		for transform: Transform3D in palette:
			if not transform.is_finite():
				return PackedVector3Array()
			matrices.append_array(PackedFloat32Array([
				transform.basis.x.x, transform.basis.y.x, transform.basis.z.x, transform.origin.x,
				transform.basis.x.y, transform.basis.y.y, transform.basis.z.y, transform.origin.y,
				transform.basis.x.z, transform.basis.y.z, transform.basis.z.z, transform.origin.z]))
	var bytes := matrices.to_byte_array()
	profile.pack_usec += Time.get_ticks_usec() - started
	var dispatch_started := Time.get_ticks_usec()
	if rd.buffer_update(matrix_buffer, 0, bytes.size(), bytes) != OK:
		return PackedVector3Array()
	var parameters := PackedInt32Array([count, int(float(entry.bones.size()) / count), bone_count, palettes.size()]).to_byte_array()
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, entry.uniform_set, 0)
	rd.compute_list_set_push_constant(list, parameters, parameters.size())
	rd.compute_list_dispatch(list, (count + 63) >> 6, palettes.size(), 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync() # Same original action step, no stale/next-frame collision result.
	var readback_started := Time.get_ticks_usec()
	var result := rd.buffer_get_data(output_buffer, 0, count * palettes.size() * 12).to_vector3_array()
	profile.submit_sync_usec += readback_started - dispatch_started
	profile.readback_usec += Time.get_ticks_usec() - readback_started
	profile.palette_upload_bytes += bytes.size()
	profile.readback_bytes += result.size() * 12
	profile.batches += 1
	profile.vertices += result.size()
	profile.total_usec += Time.get_ticks_usec() - started
	return result

func _free_surface(entry: Dictionary) -> void:
	rd.free_rid(entry.uniform_set)
	for buffer: RID in entry.buffers:
		rd.free_rid(buffer)

func clear_surfaces() -> void:
	for entry: Dictionary in surfaces.values():
		_free_surface(entry)
	surfaces.clear()

func dispose() -> void:
	if rd == null:
		return
	clear_surfaces()
	for resource: RID in [matrix_buffer, output_buffer, pipeline, shader]:
		if resource.is_valid():
			rd.free_rid(resource)
	matrix_buffer = RID()
	output_buffer = RID()
	pipeline = RID()
	shader = RID()
	rd.free()
	rd = null
