extends SceneTree

const ScenePath: String = "res://scenes/tests/HumanBaseV1Test.tscn"
const OutputDir: String = ".visual_captures/human_base_v1_dressed_preview"
const Outputs: Dictionary = {
	&"front": OutputDir + "/01_front_toon_outline.png",
	&"three_quarter": OutputDir + "/02_three_quarter_toon_outline.png",
	&"front_pixel": OutputDir + "/03_front_pixelated.png",
	&"gameplay_pixel": OutputDir + "/04_gameplay_pixelated.png"
}
const PixelViewportSize := Vector2i(320, 180)
const OutlineColor := Color("171723")

var _materials: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load(ScenePath) as PackedScene
	assert(packed != null, "HumanBaseV1Test scene missing")
	var instance: HumanBaseV1Test = packed.instantiate() as HumanBaseV1Test
	assert(instance != null, "HumanBaseV1Test root script missing")
	root.add_child(instance)
	await process_frame
	await process_frame

	instance.set_playback_enabled(false)
	instance.set_animation_state(0)
	instance.set_debug_mode(0)
	instance.set_hud_visible(false)
	_configure_showcase_world(instance)

	var human: HumanBaseV1 = instance.get_human()
	assert(human != null and human.mesh_instance != null, "HumanBase_v1 mesh missing")
	human.mesh_instance.material_override = _toon_material(Color.WHITE, true)
	var layer_counts: Dictionary = _dress_character(human)
	assert(int(layer_counts.get(&"hair", 0)) >= 5, "Hair layer is incomplete")
	assert(int(layer_counts.get(&"face", 0)) >= 9, "Face layer is incomplete")
	assert(int(layer_counts.get(&"outfit", 0)) >= 20, "Outfit layer is incomplete")

	var output_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OutputDir)
	)
	assert(output_error == OK or output_error == ERR_ALREADY_EXISTS, "Output directory failed")

	await _prepare_view(instance, &"front", 2.15)
	await _capture(Outputs[&"front"])
	await _capture_pixelated(Outputs[&"front_pixel"])

	await _prepare_view(instance, &"three_quarter", 2.28)
	await _capture(Outputs[&"three_quarter"])

	await _prepare_view(instance, &"gameplay_isometric", 2.75)
	await _capture_pixelated(Outputs[&"gameplay_pixel"])

	for output_path: String in Outputs.values():
		assert(FileAccess.file_exists(output_path), "Dressed preview capture missing: %s" % output_path)

	print((
		"HUMAN_BASE_V1_DRESSED_PREVIEW_PASS: hair=%d face=%d outfit=%d "
		+ "views=front,three_quarter,front_pixel,gameplay_pixel output_dir=%s"
	) % [
			int(layer_counts[&"hair"]), int(layer_counts[&"face"]),
			int(layer_counts[&"outfit"]), OutputDir
		])
	instance.queue_free()
	await process_frame
	quit(0)

func _dress_character(human: HumanBaseV1) -> Dictionary:
	_materials = {
		&"hair": _toon_material(Color("2b202e")),
		&"hair_light": _toon_material(Color("664052")),
		&"eye_white": _toon_material(Color("f5ead7")),
		&"eye": _toon_material(Color("335f67")),
		&"face_dark": _toon_material(Color("38232d")),
		&"mouth": _toon_material(Color("a65c63")),
		&"navy": _toon_material(Color("263c59")),
		&"teal": _toon_material(Color("3c7475")),
		&"cream": _toon_material(Color("ded8c4")),
		&"burgundy": _toon_material(Color("76384b")),
		&"gold": _toon_material(Color("d9a84b")),
		&"pants": _toon_material(Color("27313d")),
		&"leather": _toon_material(Color("4b302d")),
		&"platform": _toon_material(Color("537f88")),
		&"platform_edge": _toon_material(Color("263846"))
	}

	var hair := _new_layer(human, &"PreviewHair")
	var face := _new_layer(human, &"PreviewFace")
	var outfit := _new_layer(human, &"PreviewOutfit")
	_build_hair(hair)
	_build_face(face)
	_build_outfit(outfit)
	_build_platform(outfit)
	return {
		&"hair": hair.get_child_count(),
		&"face": face.get_child_count(),
		&"outfit": outfit.get_child_count()
	}

func _build_hair(layer: Node3D) -> void:
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 0.195
	crown_mesh.height = 0.390
	crown_mesh.radial_segments = 10
	crown_mesh.rings = 5
	var crown := _add_mesh(layer, &"AngularHairCrown", crown_mesh, Vector3(0.0, 1.690, 0.028), _materials[&"hair"])
	crown.scale = Vector3(1.0, 0.80, 0.88)

	_add_prism(
		layer, &"SweptFringeL", Vector3(-0.045, 1.730, -0.174),
		PackedVector2Array([
			Vector2(-0.115, 0.070), Vector2(0.080, 0.065),
			Vector2(0.020, -0.030), Vector2(-0.065, -0.082)
		]), 0.022, _materials[&"hair"]
	)
	_add_prism(
		layer, &"SweptFringeR", Vector3(0.072, 1.720, -0.172),
		PackedVector2Array([
			Vector2(-0.052, 0.060), Vector2(0.080, 0.042),
			Vector2(0.046, -0.076), Vector2(-0.018, -0.030)
		]), 0.020, _materials[&"hair_light"]
	)
	_add_prism(
		layer, &"SideLockL", Vector3(-0.176, 1.625, -0.070),
		PackedVector2Array([
			Vector2(-0.022, 0.082), Vector2(0.030, 0.070),
			Vector2(0.020, -0.082), Vector2(-0.030, -0.055)
		]), 0.040, _materials[&"hair"]
	)
	_add_prism(
		layer, &"SideLockR", Vector3(0.176, 1.625, -0.070),
		PackedVector2Array([
			Vector2(-0.030, 0.070), Vector2(0.022, 0.082),
			Vector2(0.030, -0.055), Vector2(-0.020, -0.082)
		]), 0.040, _materials[&"hair"]
	)
	_add_prism(
		layer, &"BackHairTail", Vector3(0.105, 1.560, 0.175),
		PackedVector2Array([
			Vector2(-0.065, 0.090), Vector2(0.060, 0.055),
			Vector2(0.025, -0.115), Vector2(-0.045, -0.070)
		]), 0.075, _materials[&"hair_light"], Vector3(4.0, 12.0, -12.0)
	)
	_add_box(
		layer, &"HairHighlight", Vector3(-0.055, 1.795, -0.115),
		Vector3(0.070, 0.018, 0.022), _materials[&"hair_light"], Vector3(0.0, 0.0, -18.0)
	)

func _build_face(layer: Node3D) -> void:
	for side: float in [-1.0, 1.0]:
		var side_name: String = "L" if side < 0.0 else "R"
		_add_prism(
			layer, StringName("EyeWhite%s" % side_name), Vector3(side * 0.061, 1.644, -0.174),
			PackedVector2Array([
				Vector2(-0.030, 0.0), Vector2(0.0, 0.016),
				Vector2(0.030, 0.0), Vector2(0.0, -0.016)
			]), 0.008, _materials[&"eye_white"]
		)
		_add_prism(
			layer, StringName("Iris%s" % side_name), Vector3(side * 0.061, 1.643, -0.180),
			PackedVector2Array([
				Vector2(-0.010, 0.0), Vector2(0.0, 0.014),
				Vector2(0.010, 0.0), Vector2(0.0, -0.014)
			]), 0.006, _materials[&"eye"]
		)
		_add_box(
			layer, StringName("Brow%s" % side_name), Vector3(side * 0.061, 1.681, -0.171),
			Vector3(0.062, 0.010, 0.008), _materials[&"face_dark"],
			Vector3(0.0, 0.0, side * 7.0)
		)
	_add_box(layer, &"NoseBridge", Vector3(0.0, 1.610, -0.181), Vector3(0.010, 0.030, 0.009), _materials[&"face_dark"])
	_add_box(layer, &"Mouth", Vector3(0.0, 1.562, -0.174), Vector3(0.050, 0.008, 0.008), _materials[&"mouth"])
	_add_box(layer, &"LowerLip", Vector3(0.0, 1.550, -0.171), Vector3(0.025, 0.006, 0.006), _materials[&"eye_white"])

func _build_outfit(layer: Node3D) -> void:
	# Fitted two-part tunic keeps the silhouette narrow while adding layered color.
	_add_cylinder(layer, &"UpperTunic", Vector3(0.0, 1.235, 0.0), 0.370, 0.238, 0.182, 0.68, _materials[&"navy"])
	_add_cylinder(layer, &"LowerTunic", Vector3(0.0, 0.965, 0.0), 0.300, 0.182, 0.218, 0.64, _materials[&"teal"])
	_add_cylinder(layer, &"Belt", Vector3(0.0, 0.835, 0.0), 0.052, 0.198, 0.198, 0.68, _materials[&"leather"])
	_add_cylinder(layer, &"HemTrim", Vector3(0.0, 0.812, 0.0), 0.022, 0.220, 0.220, 0.65, _materials[&"gold"])
	_add_box(layer, &"BeltBuckle", Vector3(0.0, 0.835, -0.143), Vector3(0.058, 0.045, 0.020), _materials[&"gold"])

	_add_box(layer, &"CollarL", Vector3(-0.042, 1.390, -0.151), Vector3(0.020, 0.150, 0.018), _materials[&"cream"], Vector3(0.0, 0.0, 28.0))
	_add_box(layer, &"CollarR", Vector3(0.042, 1.390, -0.151), Vector3(0.020, 0.150, 0.018), _materials[&"cream"], Vector3(0.0, 0.0, -28.0))
	_add_box(layer, &"FrontSash", Vector3(0.0, 1.185, -0.161), Vector3(0.060, 0.500, 0.022), _materials[&"burgundy"], Vector3(0.0, 0.0, -18.0))
	_add_box(layer, &"SashClasp", Vector3(0.086, 1.408, -0.165), Vector3(0.050, 0.050, 0.025), _materials[&"gold"], Vector3(0.0, 0.0, 45.0))

	_add_prism(
		layer, &"ShortCape", Vector3(0.060, 1.105, 0.158),
		PackedVector2Array([
			Vector2(-0.225, 0.300), Vector2(0.180, 0.255),
			Vector2(0.185, -0.350), Vector2(0.010, -0.445), Vector2(-0.165, -0.245)
		]), 0.030, _materials[&"burgundy"], Vector3(2.0, 0.0, -4.0)
	)

	var upper_arm_points: Array[Array] = [
		[Vector3(-0.240, 1.340, 0.0), Vector3(-0.430, 1.070, 0.0)],
		[Vector3(0.240, 1.340, 0.0), Vector3(0.430, 1.070, 0.0)]
	]
	var forearm_points: Array[Array] = [
		[Vector3(-0.430, 1.070, 0.0), Vector3(-0.520, 0.850, 0.0)],
		[Vector3(0.430, 1.070, 0.0), Vector3(0.520, 0.850, 0.0)]
	]
	for side_index: int in range(2):
		var side_name: String = "L" if side_index == 0 else "R"
		var upper: Array = upper_arm_points[side_index]
		var lower: Array = forearm_points[side_index]
		_add_low_poly_sphere(
			layer, StringName("ShoulderCap%s" % side_name), upper[0],
			0.084, Vector3(1.0, 0.80, 0.86), _materials[&"teal"]
		)
		_add_cylinder_between(
			layer, StringName("UpperSleeve%s" % side_name), upper[0], upper[1],
			0.073, 0.061, 0.84, _materials[&"navy"]
		)
		_add_cylinder_between(
			layer, StringName("ForearmSleeve%s" % side_name), lower[0], lower[1],
			0.061, 0.053, 0.86, _materials[&"cream"]
		)
		var cuff_start: Vector3 = Vector3(lower[0]).lerp(Vector3(lower[1]), 0.78)
		_add_cylinder_between(
			layer, StringName("Cuff%s" % side_name), cuff_start, Vector3(lower[1]),
			0.058, 0.057, 0.88, _materials[&"gold"]
		)

	for side: float in [-1.0, 1.0]:
		var side_name: String = "L" if side < 0.0 else "R"
		var hip := Vector3(side * 0.115, 0.690, 0.0)
		var knee := Vector3(side * 0.115, 0.340, 0.0)
		var ankle := Vector3(side * 0.115, 0.055, 0.0)
		_add_cylinder_between(
			layer, StringName("Trouser%s" % side_name), hip, knee,
			0.087, 0.072, 0.84, _materials[&"pants"]
		)
		_add_cylinder_between(
			layer, StringName("BootLeg%s" % side_name), knee, ankle,
			0.077, 0.065, 0.86, _materials[&"leather"]
		)
		_add_cylinder(
			layer, StringName("BootCuff%s" % side_name), Vector3(side * 0.115, 0.330, 0.0),
			0.055, 0.084, 0.084, 0.86, _materials[&"gold"]
		)
		_add_box(
			layer, StringName("BootFoot%s" % side_name), Vector3(side * 0.115, 0.060, -0.060),
			Vector3(0.175, 0.115, 0.275), _materials[&"leather"]
		)

func _build_platform(layer: Node3D) -> void:
	_add_cylinder(layer, &"PlatformEdge", Vector3(0.0, -0.034, 0.0), 0.020, 0.430, 0.430, 0.78, _materials[&"platform_edge"], 16)
	_add_cylinder(layer, &"PlatformTop", Vector3(0.0, -0.020, 0.0), 0.026, 0.390, 0.390, 0.78, _materials[&"platform"], 16)

func _new_layer(parent: Node3D, layer_name: StringName) -> Node3D:
	var layer := Node3D.new()
	layer.name = layer_name
	parent.add_child(layer)
	return layer

func _add_box(
	parent: Node3D,
	node_name: StringName,
	center: Vector3,
	size: Vector3,
	material: Material,
	rotation: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := _add_mesh(parent, node_name, mesh, center, material)
	node.rotation_degrees = rotation
	return node

func _add_cylinder(
	parent: Node3D,
	node_name: StringName,
	center: Vector3,
	height: float,
	top_radius: float,
	bottom_radius: float,
	depth_scale: float,
	material: Material,
	radial_segments: int = 8
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.height = height
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.radial_segments = radial_segments
	mesh.rings = 1
	var node := _add_mesh(parent, node_name, mesh, center, material)
	node.scale = Vector3(1.0, 1.0, depth_scale)
	return node

func _add_cylinder_between(
	parent: Node3D,
	node_name: StringName,
	start: Vector3,
	end: Vector3,
	start_radius: float,
	end_radius: float,
	depth_scale: float,
	material: Material
) -> MeshInstance3D:
	var direction := end - start
	var mesh := CylinderMesh.new()
	mesh.height = direction.length()
	mesh.bottom_radius = start_radius
	mesh.top_radius = end_radius
	mesh.radial_segments = 8
	mesh.rings = 1
	var node := _add_mesh(parent, node_name, mesh, (start + end) * 0.5, material)
	node.basis = _basis_for_y(direction)
	node.scale = Vector3(1.0, 1.0, depth_scale)
	return node

func _add_low_poly_sphere(
	parent: Node3D,
	node_name: StringName,
	center: Vector3,
	radius: float,
	shape_scale: Vector3,
	material: Material
) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var node := _add_mesh(parent, node_name, mesh, center, material)
	node.scale = shape_scale
	return node

func _add_prism(
	parent: Node3D,
	node_name: StringName,
	center: Vector3,
	points: PackedVector2Array,
	depth: float,
	material: Material,
	rotation: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var node := _add_mesh(parent, node_name, _prism_mesh(points, depth), center, material)
	node.rotation_degrees = rotation
	return node

func _add_mesh(
	parent: Node3D,
	node_name: StringName,
	mesh: Mesh,
	center: Vector3,
	material: Material
) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.position = center
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(node)
	return node

func _prism_mesh(points: PackedVector2Array, depth: float) -> ArrayMesh:
	assert(points.size() >= 3, "Prism needs at least three points")
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var half_depth: float = depth * 0.5
	for point_index: int in range(1, points.size() - 1):
		for point: Vector2 in [points[0], points[point_index + 1], points[point_index]]:
			vertices.append(Vector3(point.x, point.y, -half_depth))
			normals.append(Vector3.FORWARD)
		for point: Vector2 in [points[0], points[point_index], points[point_index + 1]]:
			vertices.append(Vector3(point.x, point.y, half_depth))
			normals.append(Vector3.BACK)
	for point_index: int in range(points.size()):
		var next_index: int = (point_index + 1) % points.size()
		var current := Vector3(points[point_index].x, points[point_index].y, 0.0)
		var next := Vector3(points[next_index].x, points[next_index].y, 0.0)
		var edge := next - current
		var normal := Vector3(edge.y, -edge.x, 0.0).normalized()
		var a := current + Vector3(0.0, 0.0, -half_depth)
		var b := next + Vector3(0.0, 0.0, -half_depth)
		var c := next + Vector3(0.0, 0.0, half_depth)
		var d := current + Vector3(0.0, 0.0, half_depth)
		for vertex: Vector3 in [a, b, c, a, c, d]:
			vertices.append(vertex)
			normals.append(normal)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _toon_material(base_color: Color, use_vertex_color: bool = false) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 base_color : source_color = vec4(1.0);
uniform float use_vertex_color = 0.0;
uniform vec4 outline_color : source_color = vec4(0.09, 0.09, 0.14, 1.0);

void fragment() {
	vec3 normal = normalize(NORMAL);
	vec3 light_direction = normalize(vec3(-0.45, 0.78, 0.55));
	float light_amount = abs(dot(normal, light_direction));
	float shade = 0.62 + step(0.30, light_amount) * 0.16 + step(0.70, light_amount) * 0.18;
	vec3 tint_color = mix(base_color.rgb, COLOR.rgb, use_vertex_color);
	float facing = abs(dot(normal, normalize(VIEW)));
	float edge = 1.0 - smoothstep(0.10, 0.30, facing);
	ALBEDO = mix(tint_color * shade, outline_color.rgb, edge);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("base_color", base_color)
	material.set_shader_parameter("use_vertex_color", 1.0 if use_vertex_color else 0.0)
	material.set_shader_parameter("outline_color", OutlineColor)
	return material

func _basis_for_y(direction: Vector3) -> Basis:
	var y := direction.normalized()
	var reference := Vector3.FORWARD
	if absf(y.dot(reference)) > 0.90:
		reference = Vector3.RIGHT
	var x := reference.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

func _configure_showcase_world(instance: HumanBaseV1Test) -> void:
	var environment_node := instance.get_node_or_null("HumanBaseEnvironment") as WorldEnvironment
	if environment_node != null and environment_node.environment != null:
		environment_node.environment.background_color = Color("a9d7d8")
		environment_node.environment.ambient_light_color = Color("f0eee4")
		environment_node.environment.ambient_light_energy = 0.90
	if instance.ground != null:
		var ground_material := StandardMaterial3D.new()
		ground_material.albedo_color = Color("73b7b7")
		ground_material.roughness = 1.0
		instance.ground.material_override = ground_material

func _prepare_view(instance: HumanBaseV1Test, view_name: StringName, camera_size: float) -> void:
	instance.set_view(view_name)
	instance.camera.size = camera_size
	await process_frame
	await process_frame
	await process_frame

func _capture(output_path: String) -> void:
	await process_frame
	await process_frame
	var image: Image = root.get_texture().get_image()
	assert(image != null and not image.is_empty(), "Dressed preview viewport is empty")
	assert(image.save_png(output_path) == OK, "Failed to save dressed preview: %s" % output_path)

func _capture_pixelated(output_path: String) -> void:
	var full_size: Vector2i = root.size
	root.size = PixelViewportSize
	await process_frame
	await process_frame
	await process_frame
	var image: Image = root.get_texture().get_image()
	assert(image != null and not image.is_empty(), "Dressed pixel viewport is empty")
	image.resize(full_size.x, full_size.y, Image.INTERPOLATE_NEAREST)
	assert(image.save_png(output_path) == OK, "Failed to save dressed pixel preview")
	root.size = full_size
	await process_frame
