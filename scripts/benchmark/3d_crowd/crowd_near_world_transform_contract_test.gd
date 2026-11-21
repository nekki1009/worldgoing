extends SceneTree

# Internal Near selection and external Near visibility must use the renderer's
# world transform even though simulation soldier positions stay renderer-local.
const RendererType = preload("res://scripts/benchmark/3d_crowd/crowd_renderer_3d.gd")
const SimulationType = preload("res://scripts/benchmark/3d_crowd/battle_crowd_simulation.gd")
const SCENE_PATH := "res://scenes/benchmark/3d_crowd/CrowdBenchmark3D.tscn"
const NEAR_BUDGET := 64

var _scene: CrowdBenchmarkController

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed_scene: PackedScene = load(SCENE_PATH)
	if packed_scene == null:
		_fail("CrowdBenchmark3D scene did not load")
		return
	_scene = packed_scene.instantiate() as CrowdBenchmarkController
	if _scene == null:
		_fail("CrowdBenchmark3D controller type mismatch")
		return
	get_root().add_child(_scene)
	_scene.set_process(false)
	_scene.hud.visible = false
	_scene.set_soldier_count(1000)
	_scene.set_benchmark_mode(SimulationType.BenchmarkMode.HUMANOID_LOD)
	_scene.set_near_actor_budget(NEAR_BUDGET)
	_scene.crowd_renderer.set_render_path(RendererType.RenderPath.FORMATION_PARENT_TRANSFORM)
	await process_frame
	var cases: Array[Dictionary] = [
		{
			"name": "translated_rotated",
			"transform": Transform3D(Basis(Vector3.UP, 0.37), Vector3(240.0, 0.0, 180.0))
		},
		{
			"name": "translated_rotated_nonuniform",
			"transform": Transform3D(
				Basis(Vector3.UP, -0.51).scaled(Vector3(1.35, 1.0, 0.72)),
				Vector3(220.0, 0.0, 170.0)
			)
		}
	]
	for test_case: Dictionary in cases:
		if not _check_case(test_case):
			return
	print("CROWD_NEAR_WORLD_TRANSFORM_CONTRACT_PASS cases=2 internal_near=64 external_visible=1 active=1000")
	_scene.queue_free()
	await process_frame
	quit(0)

func _check_case(test_case: Dictionary) -> bool:
	var renderer: CrowdRenderer3D = _scene.crowd_renderer
	var simulation: BattleCrowdSimulation = _scene.simulation
	var camera: Camera3D = _scene.camera
	var name: String = String(test_case["name"])
	var parent_transform: Transform3D = test_case["transform"]
	# Clear external masks left by the previous case before selecting Near.
	renderer.set_external_near_soldiers(PackedInt32Array(), 0)
	renderer.transform = parent_transform
	var local_center: Vector3 = simulation.formations[0].center_position
	var world_center: Vector3 = renderer.to_global(local_center)
	if world_center.distance_to(local_center) < 100.0:
		_fail("Fixture does not separate local and world spaces: " + name)
		return false
	_scene.set_camera_state(world_center + Vector3(3.217, 15.143, 7.623), world_center, 30.0)
	renderer.invalidate_layout()
	renderer.sync_from_simulation(camera)
	var expected: PackedInt32Array = _world_nearest_64(renderer, simulation, camera)
	if expected.size() != NEAR_BUDGET:
		_fail("World-space oracle found %d Near candidates in %s" % [expected.size(), name])
		return false
	var actual := PackedInt32Array()
	var selected_count: int = int(renderer.get("_near_count"))
	var selected_ids: PackedInt32Array = renderer.get("_near_soldier_ids")
	for slot: int in range(selected_count):
		actual.append(selected_ids[slot])
	actual.sort()
	if actual != expected or renderer.near_actor_count != NEAR_BUDGET:
		_fail("Internal Near64 differs from world-space oracle in %s: expected=%s actual=%s" % [name, expected, actual])
		return false

	var visible_external: int = -1
	var hidden_external: int = -1
	for soldier_id: int in range(simulation.active_soldier_count):
		if expected.has(soldier_id):
			continue
		var world_position: Vector3 = parent_transform * simulation.get_soldier_world_position(soldier_id)
		if _visible_to_camera(world_position, camera, renderer) and visible_external < 0:
			visible_external = soldier_id
		elif not _visible_to_camera(world_position, camera, renderer) and hidden_external < 0:
			hidden_external = soldier_id
		if visible_external >= 0 and hidden_external >= 0:
			break
	if visible_external < 0 or hidden_external < 0:
		_fail("Could not find visible/offscreen external Near fixtures in " + name)
		return false
	var external_ids := PackedInt32Array([visible_external, hidden_external])
	renderer.set_external_near_soldiers(external_ids, 2)
	renderer.sync_from_simulation(camera)
	if (
		renderer.visible_external_near_count != 1
		or renderer.external_near_count() != 2
		or not renderer.is_external_near_soldier(visible_external)
		or not renderer.is_external_near_soldier(hidden_external)
		or renderer.near_actor_count != NEAR_BUDGET
		or renderer.multimesh_instance_count != simulation.active_soldier_count - NEAR_BUDGET - 2
	):
		_fail("External Near world visibility or proxy conservation failed in %s: visible=%d external=%d internal=%d proxies=%d" % [
			name, renderer.visible_external_near_count, renderer.external_near_count(),
			renderer.near_actor_count, renderer.multimesh_instance_count
		])
		return false
	print("CROWD_NEAR_WORLD_CASE_PASS name=%s internal=%d visible_external=%d ids=%d,%d" % [
		name, renderer.near_actor_count, renderer.visible_external_near_count,
		visible_external, hidden_external
	])
	return true

func _world_nearest_64(renderer: CrowdRenderer3D, simulation: BattleCrowdSimulation, camera: Camera3D) -> PackedInt32Array:
	var candidates: Array[Dictionary] = []
	var maximum_squared: float = renderer.lod_interface.near_distance * renderer.lod_interface.near_distance
	for soldier_id: int in range(simulation.active_soldier_count):
		var world_position: Vector3 = renderer.to_global(simulation.get_soldier_world_position(soldier_id))
		var distance_squared: float = world_position.distance_squared_to(camera.global_position)
		if distance_squared <= maximum_squared:
			candidates.append({"id": soldier_id, "distance_squared": distance_squared})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["distance_squared"] == b["distance_squared"]:
			return a["id"] < b["id"]
		return a["distance_squared"] < b["distance_squared"]
	)
	var selected := PackedInt32Array()
	for index: int in range(mini(NEAR_BUDGET, candidates.size())):
		selected.append(int(candidates[index]["id"]))
	selected.sort()
	return selected

func _visible_to_camera(world_position: Vector3, camera: Camera3D, renderer: CrowdRenderer3D) -> bool:
	var viewport_size: Vector2 = camera.get_viewport().get_visible_rect().size
	var half_height: float = camera.size * 0.5
	var half_width: float = half_height * maxf(viewport_size.x / maxf(viewport_size.y, 1.0), 0.1)
	var radius: float = 2.0 * maxf(renderer.global_transform.basis.x.length(), renderer.global_transform.basis.z.length())
	var local_position: Vector3 = camera.global_transform.affine_inverse() * world_position
	var depth: float = -local_position.z
	return (
		depth + radius >= camera.near
		and depth - radius <= camera.far
		and absf(local_position.x) <= half_width + radius
		and absf(local_position.y) <= half_height + radius
	)

func _fail(message: String) -> void:
	push_error(message)
	print("CROWD_NEAR_WORLD_TRANSFORM_CONTRACT_FAIL " + message)
	if _scene != null:
		_scene.queue_free()
	quit(1)
