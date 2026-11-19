extends SceneTree

# GPU readback and pixel capture are test-only; the timed Crowd path does neither.
const WriterType = preload("res://scripts/benchmark/3d_crowd/crowd_gpu_formation_writer.gd")
const SlotType = preload("res://scripts/benchmark/3d_crowd/formation_slot_generator.gd")
const CAPACITY := 100
const KEY := 7
const CAPTURE_DIR := "res://.visual_captures/crowd_gpu_formation"
const FACING := 0.37
const SPACING := 1.25
const CENTER := Vector3(3.0, 0.0, -2.0)
const MATERIAL_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled;
varying float slot_active;
void vertex() { slot_active = INSTANCE_CUSTOM.z; }
void fragment() {
    if (slot_active < 0.5) discard;
    ALBEDO = vec3(1.0, 0.75, 0.2);
}
"""

var _writer: CrowdGpuFormationWriter
var _snapshot: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_rendering_device() == null:
		_fail("GPU-backed Forward+ viewport required")
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR)) != OK:
		_fail("Could not create GPU contract capture directory")
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 640)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 26.0
	camera.position = Vector3(0.0, 24.0, 0.0)
	camera.look_at(Vector3.ZERO, Vector3.FORWARD)
	camera.current = true
	await process_frame
	var world: World3D = viewport.find_world_3d()
	if world == null or not world.scenario.is_valid():
		_fail("GPU contract SubViewport has no effective World3D scenario")
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.55, 0.55, 0.55)
	var shader := Shader.new()
	shader.code = MATERIAL_CODE
	var material := ShaderMaterial.new()
	material.shader = shader
	_writer = WriterType.new()
	_writer.start()
	if not _writer.create_batch(
		KEY, world.scenario, Transform3D.IDENTITY, mesh, material,
		CAPACITY, AABB(Vector3(-20.0, -2.0, -20.0), Vector3(40.0, 6.0, 40.0))
	):
		_fail("Could not create one-surface 3D indirect MultiMesh")
		return
	_writer.set_batch_visual(KEY, mesh, material, true, Transform3D.IDENTITY)
	if not await _wait_ready():
		_fail("GPU batch did not become ready: %s" % _writer.status())
		return
	var events: Array[Dictionary] = []
	for slot: int in range(CAPACITY):
		events.append({"key": KEY, "slot": slot, "phase": 0.25, "state": 1, "active": true, "variant": 2})
	var pixels := {}
	var lit_pixels := {}
	for count: int in [0, 1, 65, 100]:
		var snapshot: Dictionary = await _submit_and_snapshot(count, 10, 10, events)
		if snapshot.is_empty():
			return
		if not _check_snapshot(snapshot, count, 10, 10):
			return
		var case_pixels: PackedByteArray = _capture(viewport, "count_%d" % count)
		if case_pixels.is_empty():
			return
		pixels[count] = case_pixels
		lit_pixels[count] = _lit_pixels(case_pixels)
		events.clear()
	if pixels[0] == pixels[1] or pixels[1] == pixels[65] or pixels[65] == pixels[100]:
		_fail("Indirect instance count did not change rendered pixels for 0/1/65/100")
		return
	if lit_pixels[0] != 0 or lit_pixels[1] <= 0 or (
		lit_pixels[65] < lit_pixels[1] * 50 or lit_pixels[65] > lit_pixels[1] * 80
	) or (
		lit_pixels[100] < lit_pixels[1] * 80 or lit_pixels[100] > lit_pixels[1] * 120
	):
		_fail("Indirect draw produced wrong lit-pixel scale for 0/1/65/100: %s" % lit_pixels)
		return

	var hole: Dictionary = await _submit_and_snapshot(100, 10, 10, [
		{"key": KEY, "slot": 3, "phase": 0.25, "state": 1, "active": false, "variant": 2}
	])
	if hole.is_empty():
		return
	var hole_output: PackedByteArray = hole["output"]
	var hole_command: PackedByteArray = hole["command"]
	var hole_descriptor: PackedByteArray = hole.get("descriptor", PackedByteArray())
	if hole_command.decode_u32(4) != 100:
		_fail("Promotion hole incorrectly shortened draw span or left proxy active")
		return
	if hole_descriptor.size() < CAPACITY * 16:
		_fail("Promotion hole descriptor snapshot missing or too short: %d" % hole_descriptor.size())
		return
	for slot: int in range(CAPACITY):
		var expected_active: float = 0.0 if slot == 3 else 1.0
		if not _near(hole_descriptor.decode_float(slot * 16 + 8), expected_active):
			_fail("Promotion hole corrupted descriptor active flag at slot %d: actual=%f expected=%f" % [
				slot, hole_descriptor.decode_float(slot * 16 + 8), expected_active
			])
			return
		if not _near(hole_output.decode_float(slot * 64 + 14 * 4), expected_active):
			_fail("Promotion hole corrupted output active flag at slot %d: actual=%f expected=%f" % [
				slot, hole_output.decode_float(slot * 64 + 14 * 4), expected_active
			])
			return
	var hole_pixels: PackedByteArray = _capture(viewport, "hole_100")
	if hole_pixels.is_empty():
		return
	if hole_pixels == pixels[100]:
		_fail("Promotion hole did not change rendered pixels")
		return
	var hole_lit: int = _lit_pixels(hole_pixels)
	if hole_lit < int(float(lit_pixels[100]) * 0.90) or hole_lit >= lit_pixels[100]:
		_fail("Promotion hole should leave 99 of 100 visible slots: lit_before=%d lit_after=%d" % [
			lit_pixels[100], hole_lit
		])
		return
	for toggle: int in range(8):
		var slot_active: bool = toggle % 2 == 1
		var stress: Dictionary = await _submit_and_snapshot(100, 10, 10, [{
			"key": KEY, "slot": 3, "phase": 0.25, "state": 1,
			"active": slot_active, "variant": 2
		}])
		if stress.is_empty():
			return
		var stress_pixels: PackedByteArray = _capture(viewport, "stress_%02d_%s" % [
			toggle, "on" if slot_active else "off"
		])
		if stress_pixels.is_empty():
			return
		var stress_output: PackedByteArray = stress["output"]
		var stress_descriptor: PackedByteArray = stress["descriptor"]
		for slot: int in range(CAPACITY):
			var expected_active: float = 1.0 if slot != 3 or slot_active else 0.0
			if not _near(stress_descriptor.decode_float(slot * 16 + 8), expected_active) or not _near(stress_output.decode_float(slot * 64 + 56), expected_active):
				_fail("Stress toggle %d corrupted active flag at slot %d" % [toggle, slot])
				return
		var stress_lit: int = _lit_pixels(stress_pixels)
		if (slot_active and abs(stress_lit - lit_pixels[100]) > int(float(lit_pixels[100]) * 0.02)) or (
			not slot_active and (stress_lit < int(float(lit_pixels[100]) * 0.90) or stress_lit >= lit_pixels[100])
		):
			_capture(viewport, "failure_toggle_%d_%d" % [Time.get_ticks_msec(), toggle])
			_fail("Stress toggle %d visual population mismatch: active=%s lit=%d full=%d" % [
				toggle, slot_active, stress_lit, lit_pixels[100]
			])
			return

	var reflow: Dictionary = await _submit_and_snapshot(100, 3, 34, [
		{"key": KEY, "slot": 3, "phase": 0.25, "state": 1, "active": true, "variant": 2}
	])
	if reflow.is_empty() or not _check_snapshot(reflow, 100, 3, 34):
		return
	var reflow_pixels: PackedByteArray = _capture(viewport, "reflow_3x34")
	if reflow_pixels.is_empty():
		return
	if reflow_pixels == pixels[100]:
		_fail("10x10 to 3x34 reflow did not move rendered slots")
		return
	_writer.set_batch_visual(
		KEY, mesh, material, true,
		Transform3D(Basis(Vector3.UP, -0.53), Vector3(4.0, 0.0, 5.0))
	)
	for frame: int in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var parent_pixels: PackedByteArray = _capture(viewport, "nonidentity_parent")
	if parent_pixels.is_empty():
		return
	if parent_pixels == reflow_pixels:
		_fail("Nonidentity RS parent transform did not move rendered slots")
		return
	_snapshot.clear()
	_writer.request_snapshot(KEY, _receive_snapshot)
	var parent_deadline: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < parent_deadline and _snapshot.is_empty():
		await process_frame
	if _snapshot.is_empty() or _snapshot.get("output", PackedByteArray()) != reflow.get("output", PackedByteArray()):
		_fail("RS parent transform unexpectedly changed renderer-local GPU output")
		return
	var replacement_mesh := BoxMesh.new()
	replacement_mesh.size = Vector3(0.85, 0.85, 0.85)
	var replacement_shader := Shader.new()
	replacement_shader.code = MATERIAL_CODE.replace("vec3(1.0, 0.75, 0.2)", "vec3(0.1, 0.65, 1.0)")
	var replacement_material := ShaderMaterial.new()
	replacement_material.shader = replacement_shader
	_writer.set_batch_visual(
		KEY, replacement_mesh, replacement_material, true,
		Transform3D(Basis(Vector3.UP, -0.53), Vector3(4.0, 0.0, 5.0))
	)
	var replacement: Dictionary = await _submit_and_snapshot(100, 3, 34, [])
	if replacement.is_empty() or not _check_snapshot(replacement, 100, 3, 34):
		return
	var replacement_pixels: PackedByteArray = _capture(viewport, "mesh_material_replacement")
	if replacement_pixels.is_empty():
		return
	if replacement_pixels == parent_pixels or _blue_pixels(replacement_pixels) < 100:
		_fail("Fresh mesh/material LOD replacement did not render blue instances")
		return
	var before_dispose: Dictionary = _writer.status()
	_writer.dispose()
	for frame: int in range(3):
		await process_frame
	viewport.queue_free()
	await process_frame
	var fingerprints := {}
	for count: int in pixels:
		fingerprints[count] = hash(pixels[count])
	print("CROWD_GPU_FORMATION_CONTRACT_PASS counts=0,1,65,100 hole=1 stress_toggles=8 reflow=3x34 lod_replacement=1 stride=64 dispatches=%d lit_pixels=%s hole_lit=%d rendered_hashes=%s" % [
		int(before_dispose.get("last_dispatches", 0)), lit_pixels, hole_lit, fingerprints
	])
	quit(0)

func _submit_and_snapshot(span: int, columns: int, rows: int, events: Array) -> Dictionary:
	var completed_before: int = int(_writer.status().get("completed_frames", 0))
	_writer.submit_frame([{
		"key": KEY, "center": CENTER, "facing": FACING, "spacing": SPACING,
		"columns": columns, "rows": rows, "span": span
	}], events)
	var deadline: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var status: Dictionary = _writer.status()
		if not str(status.get("error", "")).is_empty():
			_fail("GPU dispatch failed: %s" % status["error"])
			return {}
		if int(status.get("completed_frames", 0)) > completed_before:
			break
	if int(_writer.status().get("completed_frames", 0)) <= completed_before:
		_fail("Timed out waiting for GPU dispatch")
		return {}
	for frame: int in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	_snapshot.clear()
	_writer.request_snapshot(KEY, _receive_snapshot)
	deadline = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline and _snapshot.is_empty():
		await process_frame
	if _snapshot.is_empty():
		_fail("Timed out waiting for offline GPU readback")
	return _snapshot.duplicate()

func _receive_snapshot(result: Dictionary) -> void:
	_snapshot = result

func _wait_ready() -> bool:
	var deadline: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var status: Dictionary = _writer.status()
		if not str(status.get("error", "")).is_empty():
			return false
		if bool(status.get("ready", false)) and int(status.get("ready_batches", 0)) == 1:
			return true
	return false

func _check_snapshot(snapshot: Dictionary, count: int, columns: int, rows: int) -> bool:
	var output: PackedByteArray = snapshot.get("output", PackedByteArray())
	var command: PackedByteArray = snapshot.get("command", PackedByteArray())
	if output.size() < CAPACITY * 64 or command.size() < 20 or command.decode_u32(4) != count:
		_fail("3D buffer or GPU indirect count mismatch at %d: output=%d command=%d" % [count, output.size(), command.size()])
		return false
	if count == 0:
		return true
	for slot: int in range(count):
		if not _near(output.decode_float(slot * 64 + 14 * 4), 1.0):
			_fail("GPU output active flag missing at count=%d slot=%d" % [count, slot])
			return false
	for slot: int in [0, count - 1]:
		var local: Vector3 = SlotType.local_position(slot, columns, rows, SPACING)
		var expected: Vector3 = CENTER + Basis(Vector3.UP, FACING) * local
		var at: int = slot * 64
		var actual := Vector3(output.decode_float(at + 12), output.decode_float(at + 28), output.decode_float(at + 44))
		if actual.distance_to(expected) > 0.0001 or not _near(output.decode_float(at + 14 * 4), 1.0):
			_fail("3D transform/custom mismatch count=%d slot=%d actual=%s expected=%s" % [count, slot, actual, expected])
			return false
		var basis := Basis(Vector3.UP, FACING)
		var basis_indices := [0, 1, 2, 4, 5, 6, 8, 9, 10]
		var basis_expected := [
			basis.x.x, basis.y.x, basis.z.x,
			basis.x.y, basis.y.y, basis.z.y,
			basis.x.z, basis.y.z, basis.z.z
		]
		for component: int in range(basis_indices.size()):
			if absf(output.decode_float(at + basis_indices[component] * 4) - basis_expected[component]) > 0.0001:
				_fail("3D basis row mismatch count=%d slot=%d component=%d" % [count, slot, component])
				return false
	return true

func _near(value: float, expected: float) -> bool:
	return absf(value - expected) <= 0.001

func _capture(viewport: SubViewport, label: String) -> PackedByteArray:
	var image: Image = viewport.get_texture().get_image()
	if image == null or image.is_empty():
		_fail("GPU contract viewport produced no image: " + label)
		return PackedByteArray()
	image.convert(Image.FORMAT_RGBA8)
	if image.save_png(CAPTURE_DIR + "/" + label + ".png") != OK:
		_fail("Could not save GPU contract capture: " + label)
		return PackedByteArray()
	return image.get_data()

func _lit_pixels(bytes: PackedByteArray) -> int:
	var lit: int = 0
	for offset: int in range(0, bytes.size(), 4):
		if bytes[offset + 3] > 128 and bytes[offset] > 128 and bytes[offset + 1] > 70 and bytes[offset + 2] < 200:
			lit += 1
	return lit

func _blue_pixels(bytes: PackedByteArray) -> int:
	var blue: int = 0
	for offset: int in range(0, bytes.size(), 4):
		if bytes[offset + 3] > 128 and bytes[offset] < 100 and bytes[offset + 1] > 90 and bytes[offset + 2] > 180:
			blue += 1
	return blue

func _fail(message: String) -> void:
	push_error(message)
	print("CROWD_GPU_FORMATION_CONTRACT_FAIL " + message)
	if _writer != null:
		_writer.dispose()
	quit(1)
