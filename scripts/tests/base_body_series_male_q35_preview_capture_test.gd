extends SceneTree

const OutputDir: String = ".visual_captures/base_body_series_male_q35"
const Outputs: Dictionary = {
	&"base_sheet": OutputDir + "/01_male_q35_base_three_view.png",
	&"dressed_sheet": OutputDir + "/02_male_q35_dressed_three_view.png",
	&"three_quarter": OutputDir + "/03_male_q35_dressed_three_quarter.png",
	&"pixelated": OutputDir + "/04_male_q35_dressed_pixelated.png"
}
const PixelViewportSize := Vector2i(320, 180)
const OutlineColor := Color("34261f")
const HumanRigType = preload("res://scripts/benchmark/3d_crowd/human_rig_v1.gd")

var _materials: Dictionary = {}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var output_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OutputDir)
	)
	assert(output_error == OK or output_error == ERR_ALREADY_EXISTS, "Output directory failed")
	_materials = _build_materials()

	await _capture_sheet(false, Outputs[&"base_sheet"])
	await _capture_sheet(true, Outputs[&"dressed_sheet"])
	await _capture_single(true, false, Outputs[&"three_quarter"])
	await _capture_single(true, true, Outputs[&"pixelated"])

	for output_path: String in Outputs.values():
		assert(FileAccess.file_exists(output_path), "Q35 preview missing: %s" % output_path)
	print(
		"BASE_BODY_SERIES_MALE_Q35_PREVIEW_PASS: ratio=3.5 heads height=1.78 "
		+ "base_three_view=dressed_three_view=three_quarter=pixelated output_dir=%s" % OutputDir
	)
	quit(0)

func _capture_sheet(dressed: bool, output_path: String) -> void:
	var world := _new_world()
	var sheet := Node3D.new()
	sheet.name = "Q35ThreeViewSheet"
	world.add_child(sheet)
	for view_index: int in range(3):
		var model := _build_model(dressed)
		model.position = Vector3(float(view_index - 1) * 0.92, 0.0, 0.0)
		# Match the specification sheet: front, side, back.
		model.rotation_degrees.y = [180.0, 90.0, 0.0][view_index]
		sheet.add_child(model)
	var camera := world.get_node("PreviewCamera") as Camera3D
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(0.0, 0.90, -6.0)
	camera.size = 2.12
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.86, 0.0), Vector3.UP)
	await _capture_world(world, output_path, false)

func _capture_single(dressed: bool, pixelated: bool, output_path: String) -> void:
	var world := _new_world()
	var model := _build_model(dressed)
	world.add_child(model)
	var camera := world.get_node("PreviewCamera") as Camera3D
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	if pixelated:
		camera.position = Vector3(3.20, 2.55, -3.20)
		camera.size = 2.70
		camera.look_at_from_position(camera.position, Vector3(0.0, 0.88, 0.0), Vector3.UP)
	else:
		camera.position = Vector3(3.30, 2.32, -3.30)
		camera.size = 2.18
		camera.look_at_from_position(camera.position, Vector3(0.0, 0.91, 0.0), Vector3.UP)
	await _capture_world(world, output_path, pixelated)

func _capture_world(world: Node3D, output_path: String, pixelated: bool) -> void:
	root.add_child(world)
	await process_frame
	await process_frame
	await process_frame
	if not pixelated:
		var image: Image = root.get_texture().get_image()
		assert(image != null and not image.is_empty(), "Q35 viewport is empty")
		assert(image.save_png(output_path) == OK, "Failed to save Q35 preview")
	else:
		var full_size: Vector2i = root.size
		root.size = PixelViewportSize
		await process_frame
		await process_frame
		await process_frame
		var pixel_image: Image = root.get_texture().get_image()
		assert(pixel_image != null and not pixel_image.is_empty(), "Q35 pixel viewport is empty")
		pixel_image.resize(full_size.x, full_size.y, Image.INTERPOLATE_NEAREST)
		assert(pixel_image.save_png(output_path) == OK, "Failed to save Q35 pixel preview")
		root.size = full_size
		await process_frame
	world.queue_free()
	await process_frame

func _build_model(dressed: bool) -> Node3D:
	var model := Node3D.new()
	model.name = "BaseBodySeries_Male_Q35_v1"
	var skeleton := _build_q35_skeleton()
	skeleton.name = "HumanRig_v1_Q35"
	model.add_child(skeleton)
	_add_socket_contract(skeleton)

	var body_layer := _new_layer(model, &"BaseBody")
	_build_body(body_layer)
	if dressed:
		var hair_layer := _new_layer(model, &"HairLayer")
		var face_layer := _new_layer(model, &"FaceLayer")
		var clothing_layer := _new_layer(model, &"ClothingLayer")
		_build_hair(hair_layer)
		_build_face(face_layer)
		_build_clothing(clothing_layer)
	else:
		var base_face_layer := _new_layer(model, &"BaseFace")
		_build_face(base_face_layer)
	return model

func _build_q35_skeleton() -> Skeleton3D:
	var skeleton := HumanRigType.build_skeleton()
	var q35_positions: Array[Vector3] = [
		Vector3(0.0, 0.00, 0.0),
		Vector3(0.0, 0.72, 0.0),
		Vector3(0.0, 0.16, 0.0),
		Vector3(0.0, 0.15, 0.0),
		Vector3(0.0, 0.12, 0.0),
		Vector3(0.0, 0.37, 0.0),
		Vector3(-0.21, 0.00, 0.0),
		Vector3(-0.17, -0.22, 0.0),
		Vector3(-0.08, -0.18, 0.0),
		Vector3(0.21, 0.00, 0.0),
		Vector3(0.17, -0.22, 0.0),
		Vector3(0.08, -0.18, 0.0),
		Vector3(-0.105, -0.20, 0.0),
		Vector3(0.00, -0.23, 0.0),
		Vector3(0.00, -0.29, 0.0),
		Vector3(0.105, -0.20, 0.0),
		Vector3(0.00, -0.23, 0.0),
		Vector3(0.00, -0.29, 0.0),
		Vector3(0.07, -0.02, 0.11),
		Vector3(-0.07, -0.02, 0.11),
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.0, -0.05, 0.16)
	]
	for bone_index: int in range(q35_positions.size()):
		skeleton.set_bone_rest(bone_index, Transform3D(Basis.IDENTITY, q35_positions[bone_index]))
	skeleton.reset_bone_poses()
	return skeleton

func _add_socket_contract(skeleton: Skeleton3D) -> void:
	_add_attachment(skeleton, &"HEAD_SOCKET", &"head")
	_add_attachment(skeleton, &"HAND_R_SOCKET", &"hand_r")
	_add_attachment(skeleton, &"HAND_L_SOCKET", &"hand_l")
	_add_attachment(skeleton, &"CHEST_SOCKET", &"chest")
	_add_attachment(skeleton, &"PELVIS_SOCKET", &"pelvis")
	_add_attachment(skeleton, &"FOOT_SOCKET_L", &"foot_l")
	_add_attachment(skeleton, &"FOOT_SOCKET_R", &"foot_r")

func _add_attachment(skeleton: Skeleton3D, attachment_name: StringName, bone_name: StringName) -> BoneAttachment3D:
	var attachment := BoneAttachment3D.new()
	attachment.name = attachment_name
	attachment.bone_name = bone_name
	attachment.visible = false
	skeleton.add_child(attachment)
	return attachment

func _build_body(layer: Node3D) -> void:
	var skin: Material = _materials[&"skin"]
	var skin_light: Material = _materials[&"skin_light"]
	# One continuous torso loft: pelvis -> waist -> chest -> neck base.
	var torso_centers: Array[Vector3] = [
		Vector3(0.0, 0.56, 0.000), Vector3(0.0, 0.63, 0.000),
		Vector3(0.0, 0.76, 0.000), Vector3(0.0, 0.88, -0.008),
		Vector3(0.0, 1.01, -0.025), Vector3(0.0, 1.10, -0.015),
		Vector3(0.0, 1.17, 0.000)
	]
	var torso_rx: Array[float] = [0.18, 0.235, 0.225, 0.175, 0.215, 0.275, 0.115]
	var torso_rz: Array[float] = [0.115, 0.145, 0.140, 0.115, 0.145, 0.155, 0.090]
	_add_mesh(layer, &"TorsoContinuous", _revolved_mesh(torso_centers, torso_rx, torso_rz, 14), Vector3.ZERO, skin)

	var neck_centers: Array[Vector3] = [
		Vector3(0.0, 1.15, 0.0), Vector3(0.0, 1.23, 0.0), Vector3(0.0, 1.32, 0.0)
	]
	_add_mesh(layer, &"NeckContinuous", _revolved_mesh(neck_centers, [0.105, 0.082, 0.095], [0.085, 0.075, 0.085], 12), Vector3.ZERO, skin)

	var head_centers: Array[Vector3] = [
		Vector3(0.0, 1.29, 0.005), Vector3(0.0, 1.34, 0.000),
		Vector3(0.0, 1.46, -0.008), Vector3(0.0, 1.59, -0.005),
		Vector3(0.0, 1.71, 0.008), Vector3(0.0, 1.78, 0.018)
	]
	_add_mesh(layer, &"HeadContinuous", _revolved_mesh(head_centers, [0.105, 0.180, 0.235, 0.255, 0.220, 0.125], [0.095, 0.145, 0.180, 0.195, 0.175, 0.110], 14), Vector3.ZERO, skin)
	_add_low_poly_sphere(layer, &"EarL", Vector3(-0.245, 1.53, 0.005), 0.048, Vector3(0.55, 1.0, 0.65), skin_light, 10, 5)
	_add_low_poly_sphere(layer, &"EarR", Vector3(0.245, 1.53, 0.005), 0.048, Vector3(0.55, 1.0, 0.65), skin_light, 10, 5)

	var left_arm: Array[Vector3] = [
		Vector3(-0.235, 1.09, 0.000), Vector3(-0.275, 0.98, -0.005),
		Vector3(-0.290, 0.84, -0.012), Vector3(-0.292, 0.715, -0.025), Vector3(-0.292, 0.665, -0.040)
	]
	var right_arm: Array[Vector3] = [
		Vector3(0.235, 1.09, 0.000), Vector3(0.275, 0.98, -0.005),
		Vector3(0.290, 0.84, -0.012), Vector3(0.292, 0.715, -0.025), Vector3(0.292, 0.665, -0.040)
	]
	_add_mesh(layer, &"ArmLContinuous", _tube_polyline_mesh(left_arm, [0.078, 0.070, 0.061, 0.053, 0.060], 10), Vector3.ZERO, skin)
	_add_mesh(layer, &"ArmRContinuous", _tube_polyline_mesh(right_arm, [0.078, 0.070, 0.061, 0.053, 0.060], 10), Vector3.ZERO, skin)
	_add_low_poly_sphere(layer, &"HandL", Vector3(-0.292, 0.655, -0.042), 0.064, Vector3(0.82, 1.0, 0.78), skin_light, 10, 5)
	_add_low_poly_sphere(layer, &"HandR", Vector3(0.292, 0.655, -0.042), 0.064, Vector3(0.82, 1.0, 0.78), skin_light, 10, 5)

	var left_leg: Array[Vector3] = [
		Vector3(-0.115, 0.68, 0.000), Vector3(-0.130, 0.53, 0.000),
		Vector3(-0.125, 0.36, -0.005), Vector3(-0.105, 0.17, -0.005), Vector3(-0.105, 0.065, -0.005)
	]
	var right_leg: Array[Vector3] = [
		Vector3(0.115, 0.68, 0.000), Vector3(0.130, 0.53, 0.000),
		Vector3(0.125, 0.36, -0.005), Vector3(0.105, 0.17, -0.005), Vector3(0.105, 0.065, -0.005)
	]
	_add_mesh(layer, &"LegLContinuous", _tube_polyline_mesh(left_leg, [0.115, 0.105, 0.088, 0.068, 0.055], 10), Vector3.ZERO, skin)
	_add_mesh(layer, &"LegRContinuous", _tube_polyline_mesh(right_leg, [0.115, 0.105, 0.088, 0.068, 0.055], 10), Vector3.ZERO, skin)
	_add_foot(layer, &"FootL", Vector3(-0.105, 0.045, -0.040), skin_light)
	_add_foot(layer, &"FootR", Vector3(0.105, 0.045, -0.040), skin_light)

	# The specification's base garment is simple; keep it as one fitted volume.
	for side: float in [-1.0, 1.0]:
		var side_name: String = "L" if side < 0.0 else "R"
		var shorts_centers: Array[Vector3] = [
			Vector3(side * 0.115, 0.55, 0.000), Vector3(side * 0.120, 0.63, -0.005), Vector3(side * 0.120, 0.76, 0.000)
		]
		_add_mesh(layer, StringName("BaseShorts%s" % side_name), _revolved_mesh(shorts_centers, [0.105, 0.125, 0.115], [0.125, 0.145, 0.135], 12), Vector3.ZERO, _materials[&"shorts"])
	_add_prism(layer, &"ShortsFrontSeam", Vector3(0.0, 0.625, -0.157), PackedVector2Array([
		Vector2(-0.010, 0.090), Vector2(0.010, 0.090), Vector2(0.010, -0.070), Vector2(0.0, -0.100), Vector2(-0.010, -0.070)
	]), 0.012, _materials[&"shorts_light"])

	# Low-poly volume accents make the silhouette read like the reference without adding new body parts.
	_add_low_poly_sphere(layer, &"ChestL", Vector3(-0.090, 1.045, -0.125), 0.095, Vector3(0.95, 0.58, 0.30), skin_light, 10, 5)
	_add_low_poly_sphere(layer, &"ChestR", Vector3(0.090, 1.045, -0.125), 0.095, Vector3(0.95, 0.58, 0.30), skin_light, 10, 5)
	_add_low_poly_sphere(layer, &"ShoulderL", Vector3(-0.245, 1.075, -0.005), 0.075, Vector3(1.0, 0.92, 0.82), skin_light, 10, 5)
	_add_low_poly_sphere(layer, &"ShoulderR", Vector3(0.245, 1.075, -0.005), 0.075, Vector3(1.0, 0.92, 0.82), skin_light, 10, 5)

func _build_hair(layer: Node3D) -> void:
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 0.265
	crown_mesh.height = 0.530
	crown_mesh.radial_segments = 16
	crown_mesh.rings = 8
	var crown := _add_mesh(layer, &"HairCrown", crown_mesh, Vector3(0.0, 1.605, 0.035), _materials[&"hair"])
	crown.scale = Vector3(1.0, 0.84, 0.90)
	_add_prism(layer, &"HairFringe", Vector3(0.0, 1.690, -0.205), PackedVector2Array([
		Vector2(-0.220, 0.035), Vector2(-0.135, 0.105), Vector2(-0.035, 0.075),
		Vector2(0.055, 0.105), Vector2(0.220, 0.030), Vector2(0.165, -0.030),
		Vector2(0.055, 0.010), Vector2(-0.045, -0.035), Vector2(-0.155, -0.015)
	]), 0.040, _materials[&"hair"])
	_add_low_poly_sphere(layer, &"HairSideL", Vector3(-0.238, 1.545, 0.020), 0.070, Vector3(0.42, 1.25, 0.72), _materials[&"hair"], 10, 5)
	_add_low_poly_sphere(layer, &"HairSideR", Vector3(0.238, 1.545, 0.020), 0.070, Vector3(0.42, 1.25, 0.72), _materials[&"hair"], 10, 5)
	_add_prism(layer, &"BackTuft", Vector3(0.0, 1.465, 0.205), PackedVector2Array([
		Vector2(-0.090, 0.060), Vector2(0.090, 0.060), Vector2(0.055, -0.105), Vector2(-0.060, -0.105)
	]), 0.050, _materials[&"hair"])

func _build_face(layer: Node3D) -> void:
	for side: float in [-1.0, 1.0]:
		var side_name: String = "L" if side < 0.0 else "R"
		_add_low_poly_sphere(layer, StringName("Eye%s" % side_name), Vector3(side * 0.086, 1.575, -0.205), 0.041, Vector3(0.95, 0.76, 0.28), _materials[&"face_dark"], 10, 5)
		_add_low_poly_sphere(layer, StringName("Iris%s" % side_name), Vector3(side * 0.086, 1.574, -0.222), 0.015, Vector3(0.80, 1.0, 0.25), _materials[&"eye"], 8, 4)
		_add_low_poly_sphere(layer, StringName("EyeHighlight%s" % side_name), Vector3(side * 0.074, 1.590, -0.230), 0.006, Vector3(1.0, 1.0, 0.35), _materials[&"eye_white"], 6, 3)
		_add_prism(layer, StringName("Brow%s" % side_name), Vector3(side * 0.086, 1.635, -0.207), PackedVector2Array([
			Vector2(-0.055, 0.006), Vector2(0.055, 0.010), Vector2(0.045, -0.010), Vector2(-0.055, -0.006)
		]), 0.014, _materials[&"face_dark"], Vector3(0.0, 0.0, side * 5.0))
	_add_low_poly_sphere(layer, &"Nose", Vector3(0.0, 1.515, -0.208), 0.020, Vector3(0.60, 0.90, 0.35), _materials[&"skin_light"], 8, 4)
	_add_prism(layer, &"Mouth", Vector3(0.0, 1.445, -0.207), PackedVector2Array([
		Vector2(-0.040, 0.006), Vector2(0.040, 0.006), Vector2(0.028, -0.010), Vector2(-0.028, -0.010)
	]), 0.012, _materials[&"mouth"])

func _build_clothing(layer: Node3D) -> void:
	var tunic_centers: Array[Vector3] = [
		Vector3(0.0, 0.72, 0.000), Vector3(0.0, 0.84, -0.005),
		Vector3(0.0, 1.00, -0.010), Vector3(0.0, 1.13, 0.000)
	]
	_add_mesh(layer, &"TunicContinuous", _revolved_mesh(tunic_centers, [0.225, 0.245, 0.240, 0.255], [0.145, 0.160, 0.165, 0.145], 14), Vector3.ZERO, _materials[&"navy"])
	_add_prism(layer, &"TunicHem", Vector3(0.0, 0.78, -0.165), PackedVector2Array([
		Vector2(-0.210, 0.055), Vector2(0.210, 0.055), Vector2(0.205, -0.055), Vector2(-0.205, -0.055)
	]), 0.024, _materials[&"teal"])
	_add_prism(layer, &"TunicFront", Vector3(0.0, 0.96, -0.212), PackedVector2Array([
		Vector2(-0.170, 0.140), Vector2(0.170, 0.140), Vector2(0.145, -0.145), Vector2(0.0, -0.185), Vector2(-0.145, -0.145)
	]), 0.025, _materials[&"teal"])
	_add_prism(layer, &"Collar", Vector3(0.0, 1.135, -0.160), PackedVector2Array([
		Vector2(-0.085, 0.035), Vector2(0.0, -0.040), Vector2(0.085, 0.035), Vector2(0.055, 0.075), Vector2(-0.055, 0.075)
	]), 0.026, _materials[&"cream"])
	_add_prism(layer, &"Sash", Vector3(0.0, 0.96, -0.225), PackedVector2Array([
		Vector2(-0.035, 0.205), Vector2(0.035, 0.205), Vector2(0.070, -0.175), Vector2(0.0, -0.225), Vector2(-0.070, -0.175)
	]), 0.022, _materials[&"burgundy"], Vector3(0.0, 0.0, -8.0))
	_add_mesh(layer, &"BeltContinuous", _revolved_mesh([
		Vector3(0.0, 0.695, 0.0), Vector3(0.0, 0.735, 0.0)
	], [0.245, 0.245], [0.155, 0.155], 14), Vector3.ZERO, _materials[&"leather"])
	_add_box(layer, &"Buckle", Vector3(0.0, 0.705, -0.202), Vector3(0.065, 0.050, 0.024), _materials[&"gold"], Vector3.ZERO)

	var sleeve_l: Array[Vector3] = [Vector3(-0.235, 1.09, 0.0), Vector3(-0.295, 0.98, -0.005), Vector3(-0.325, 0.84, -0.012), Vector3(-0.290, 0.72, -0.025)]
	var sleeve_r: Array[Vector3] = [Vector3(0.235, 1.09, 0.0), Vector3(0.295, 0.98, -0.005), Vector3(0.325, 0.84, -0.012), Vector3(0.290, 0.72, -0.025)]
	_add_mesh(layer, &"SleeveLContinuous", _tube_polyline_mesh(sleeve_l, [0.102, 0.092, 0.078, 0.068], 10), Vector3.ZERO, _materials[&"navy"])
	_add_mesh(layer, &"SleeveRContinuous", _tube_polyline_mesh(sleeve_r, [0.102, 0.092, 0.078, 0.068], 10), Vector3.ZERO, _materials[&"navy"])
	_add_low_poly_sphere(layer, &"CuffL", Vector3(-0.285, 0.705, -0.028), 0.063, Vector3(0.90, 0.72, 0.85), _materials[&"gold"], 10, 5)
	_add_low_poly_sphere(layer, &"CuffR", Vector3(0.285, 0.705, -0.028), 0.063, Vector3(0.90, 0.72, 0.85), _materials[&"gold"], 10, 5)

	for side: float in [-1.0, 1.0]:
		var side_name: String = "L" if side < 0.0 else "R"
		var hip := Vector3(side * 0.115, 0.68, 0.0)
		var knee := Vector3(side * 0.130, 0.36, 0.0)
		var ankle := Vector3(side * 0.105, 0.085, 0.0)
		_add_mesh(layer, StringName("Trouser%s" % side_name), _tube_polyline_mesh([hip, knee], [0.125, 0.095], 10), Vector3.ZERO, _materials[&"pants"])
		_add_mesh(layer, StringName("BootLeg%s" % side_name), _tube_polyline_mesh([knee, ankle], [0.090, 0.068], 10), Vector3.ZERO, _materials[&"leather"])
		_add_low_poly_sphere(layer, StringName("BootCuff%s" % side_name), Vector3(side * 0.105, 0.36, 0.0), 0.090, Vector3(1.0, 0.32, 0.95), _materials[&"gold"], 10, 5)
		_add_foot(layer, StringName("BootFoot%s" % side_name), Vector3(side * 0.105, 0.045, -0.040), _materials[&"leather"], Vector3(1.12, 1.0, 1.12))

	_add_prism(layer, &"Cape", Vector3(0.075, 0.92, 0.180), PackedVector2Array([
		Vector2(-0.250, 0.230), Vector2(0.215, 0.200), Vector2(0.190, -0.250), Vector2(0.020, -0.340), Vector2(-0.190, -0.190)
	]), 0.035, _materials[&"burgundy"])

func _build_materials() -> Dictionary:
	return {
		&"skin": _toon_material(Color("e8a565")),
		&"skin_light": _toon_material(Color("f8c27e")),
		&"shorts": _toon_material(Color("4b4d52")),
		&"shorts_light": _toon_material(Color("747477")),
		&"hair": _toon_material(Color("2b202e")),
		&"hair_light": _toon_material(Color("6c4050")),
		&"eye_white": _toon_material(Color("f6e9d5")),
		&"eye": _toon_material(Color("325f67")),
		&"face_dark": _toon_material(Color("3a2530")),
		&"mouth": _toon_material(Color("a45b62")),
		&"navy": _toon_material(Color("273b58")),
		&"teal": _toon_material(Color("3e7a78")),
		&"cream": _toon_material(Color("e1dac4")),
		&"burgundy": _toon_material(Color("78394d")),
		&"gold": _toon_material(Color("d7a743")),
		&"pants": _toon_material(Color("29323d")),
		&"leather": _toon_material(Color("4b302d")),
		&"platform": _toon_material(Color("537f88")),
		&"platform_edge": _toon_material(Color("263846"))
	}

func _new_world() -> Node3D:
	var world := Node3D.new()
	world.name = "BaseBodySeriesQ35PreviewWorld"
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("f4f0e7")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("f0eee4")
	environment.ambient_light_energy = 0.92
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment_node.environment = environment
	world.add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_color = Color("fff0d3")
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25.0, 145.0, 0.0)
	fill.light_color = Color("9dc9dd")
	fill.light_energy = 0.35
	world.add_child(fill)
	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.near = 0.03
	camera.far = 100.0
	camera.current = true
	world.add_child(camera)
	return world

func _new_layer(parent: Node3D, layer_name: StringName) -> Node3D:
	var layer := Node3D.new()
	layer.name = layer_name
	parent.add_child(layer)
	return layer

func _add_box(parent: Node3D, node_name: StringName, center: Vector3, size: Vector3, material: Material, rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := _add_mesh(parent, node_name, mesh, center, material)
	node.rotation_degrees = rotation
	return node

func _add_cylinder(parent: Node3D, node_name: StringName, center: Vector3, height: float, top_radius: float, bottom_radius: float, depth_scale: float, material: Material, radial_segments: int = 8) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.height = height
	mesh.top_radius = top_radius
	mesh.bottom_radius = bottom_radius
	mesh.radial_segments = radial_segments
	mesh.rings = 1
	var node := _add_mesh(parent, node_name, mesh, center, material)
	node.scale = Vector3(1.0, 1.0, depth_scale)
	return node

func _add_cylinder_between(parent: Node3D, node_name: StringName, start: Vector3, end: Vector3, start_radius: float, end_radius: float, depth_scale: float, material: Material, radial_segments: int = 8) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.height = (end - start).length()
	mesh.bottom_radius = start_radius
	mesh.top_radius = end_radius
	mesh.radial_segments = radial_segments
	mesh.rings = 1
	var node := _add_mesh(parent, node_name, mesh, (start + end) * 0.5, material)
	node.basis = _basis_for_y(end - start)
	node.scale = Vector3(1.0, 1.0, depth_scale)
	return node

func _add_foot(parent: Node3D, node_name: StringName, center: Vector3, material: Material, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var node := _add_mesh(parent, node_name, _foot_mesh(), center, material)
	node.scale = scale
	return node

func _foot_mesh() -> ArrayMesh:
	var footprint: Array[Vector2] = [
		Vector2(-0.120, 0.105), Vector2(0.120, 0.105), Vector2(0.140, -0.015),
		Vector2(0.110, -0.130), Vector2(0.055, -0.185), Vector2(-0.055, -0.185),
		Vector2(-0.110, -0.130), Vector2(-0.140, -0.015)
	]
	var vertices := PackedVector3Array()
	for point: Vector2 in footprint:
		vertices.append(Vector3(point.x, -0.045, point.y))
	for point: Vector2 in footprint:
		vertices.append(Vector3(point.x * 0.88, 0.045, point.y * 0.88))
	var bottom_center: int = vertices.size()
	vertices.append(Vector3(0.0, -0.045, -0.015))
	var top_center: int = vertices.size()
	vertices.append(Vector3(0.0, 0.045, -0.015))
	var triangles: Array = []
	for side_index: int in range(footprint.size()):
		var next_side: int = (side_index + 1) % footprint.size()
		triangles.append([side_index, next_side, footprint.size() + next_side])
		triangles.append([side_index, footprint.size() + next_side, footprint.size() + side_index])
		triangles.append([bottom_center, next_side, side_index])
		triangles.append([top_center, footprint.size() + side_index, footprint.size() + next_side])
	return _mesh_from_triangles(vertices, triangles)

func _add_low_poly_sphere(parent: Node3D, node_name: StringName, center: Vector3, radius: float, shape_scale: Vector3, material: Material, radial_segments: int = 8, rings: int = 4) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = radial_segments
	mesh.rings = rings
	var node := _add_mesh(parent, node_name, mesh, center, material)
	node.scale = shape_scale
	return node

func _add_prism(parent: Node3D, node_name: StringName, center: Vector3, points: PackedVector2Array, depth: float, material: Material, rotation: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var node := _add_mesh(parent, node_name, _prism_mesh(points, depth), center, material)
	node.rotation_degrees = rotation
	return node

func _add_mesh(parent: Node3D, node_name: StringName, mesh: Mesh, center: Vector3, material: Material) -> MeshInstance3D:
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
		for vertex_index: int in [0, point_index + 1, point_index]:
			var point: Vector2 = points[vertex_index]
			vertices.append(Vector3(point.x, point.y, -half_depth))
			normals.append(Vector3.FORWARD)
		for vertex_index: int in [0, point_index, point_index + 1]:
			var point: Vector2 = points[vertex_index]
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

func _revolved_mesh(section_centers: Array, radii_x: Array, radii_z: Array, radial_segments: int = 12) -> ArrayMesh:
	assert(section_centers.size() >= 2, "Revolved mesh needs two sections")
	assert(section_centers.size() == radii_x.size() and section_centers.size() == radii_z.size(), "Revolved section data mismatch")
	var vertices := PackedVector3Array()
	for section_index: int in range(section_centers.size()):
		var center: Vector3 = section_centers[section_index]
		var radius_x: float = float(radii_x[section_index])
		var radius_z: float = float(radii_z[section_index])
		for side_index: int in range(radial_segments):
			var angle: float = TAU * float(side_index) / float(radial_segments)
			vertices.append(Vector3(
				center.x + cos(angle) * radius_x,
				center.y,
				center.z - sin(angle) * radius_z
			))
	var triangles: Array = []
	for section_index: int in range(section_centers.size() - 1):
		for side_index: int in range(radial_segments):
			var next_side: int = (side_index + 1) % radial_segments
			var a: int = section_index * radial_segments + side_index
			var b: int = section_index * radial_segments + next_side
			var c: int = (section_index + 1) * radial_segments + next_side
			var d: int = (section_index + 1) * radial_segments + side_index
			triangles.append([a, c, b])
			triangles.append([a, d, c])
	var bottom_center: int = vertices.size()
	vertices.append(section_centers[0])
	var top_center: int = vertices.size()
	vertices.append(section_centers[section_centers.size() - 1])
	for side_index: int in range(radial_segments):
		var next_side: int = (side_index + 1) % radial_segments
		triangles.append([bottom_center, next_side, side_index])
		var top_start: int = (section_centers.size() - 1) * radial_segments
		triangles.append([top_center, top_start + side_index, top_start + next_side])
	return _mesh_from_triangles(vertices, triangles)

func _tube_polyline_mesh(points: Array, radii: Array, radial_segments: int = 10) -> ArrayMesh:
	assert(points.size() >= 2, "Tube needs two points")
	assert(points.size() == radii.size(), "Tube point data mismatch")
	var vertices := PackedVector3Array()
	for point_index: int in range(points.size()):
		var point: Vector3 = points[point_index]
		var tangent: Vector3
		if point_index == 0:
			tangent = (points[1] - points[0]).normalized()
		elif point_index == points.size() - 1:
			tangent = (points[point_index] - points[point_index - 1]).normalized()
		else:
			tangent = (points[point_index + 1] - points[point_index - 1]).normalized()
		var reference := Vector3.FORWARD
		if absf(tangent.dot(reference)) > 0.92:
			reference = Vector3.RIGHT
		var ring_x := tangent.cross(reference).normalized()
		var ring_z := tangent.cross(ring_x).normalized()
		var radius: float = float(radii[point_index])
		for side_index: int in range(radial_segments):
			var angle: float = TAU * float(side_index) / float(radial_segments)
			vertices.append(point + ring_x * cos(angle) * radius + ring_z * sin(angle) * radius * 0.86)
	var triangles: Array = []
	for point_index: int in range(points.size() - 1):
		for side_index: int in range(radial_segments):
			var next_side: int = (side_index + 1) % radial_segments
			var a: int = point_index * radial_segments + side_index
			var b: int = point_index * radial_segments + next_side
			var c: int = (point_index + 1) * radial_segments + next_side
			var d: int = (point_index + 1) * radial_segments + side_index
			triangles.append([a, c, b])
			triangles.append([a, d, c])
	var bottom_center: int = vertices.size()
	vertices.append(points[0])
	var top_center: int = vertices.size()
	vertices.append(points[points.size() - 1])
	for side_index: int in range(radial_segments):
		var next_side: int = (side_index + 1) % radial_segments
		triangles.append([bottom_center, next_side, side_index])
		var top_start: int = (points.size() - 1) * radial_segments
		triangles.append([top_center, top_start + side_index, top_start + next_side])
	return _mesh_from_triangles(vertices, triangles)

func _mesh_from_triangles(vertices: PackedVector3Array, triangles: Array) -> ArrayMesh:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	var indices := PackedInt32Array()
	for vertex_index: int in range(vertices.size()):
		normals[vertex_index] = Vector3.ZERO
	for triangle: Array in triangles:
		var i0: int = triangle[0]
		var i1: int = triangle[1]
		var i2: int = triangle[2]
		indices.append(i0)
		indices.append(i1)
		indices.append(i2)
		var normal := (vertices[i1] - vertices[i0]).cross(vertices[i2] - vertices[i0])
		if normal.length_squared() > 0.000001:
			normal = normal.normalized()
			normals[i0] += normal
			normals[i1] += normal
			normals[i2] += normal
	for vertex_index: int in range(normals.size()):
		if normals[vertex_index].length_squared() > 0.000001:
			normals[vertex_index] = normals[vertex_index].normalized()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _toon_material(base_color: Color) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform vec4 tint : source_color = vec4(1.0);
uniform vec4 outline_color : source_color = vec4(0.09, 0.09, 0.14, 1.0);

void fragment() {
	vec3 normal = normalize(NORMAL);
	vec3 light_direction = normalize(vec3(-0.45, 0.78, 0.55));
	float light_amount = abs(dot(normal, light_direction));
	float shade = 0.62 + step(0.30, light_amount) * 0.16 + step(0.70, light_amount) * 0.18;
	float facing = abs(dot(normal, normalize(VIEW)));
	float edge = 1.0 - smoothstep(0.10, 0.30, facing);
	ALBEDO = mix(tint.rgb * shade, outline_color.rgb, edge);
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("tint", base_color)
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
