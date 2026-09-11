class_name CrowdSoldierMeshBuilder
extends RefCounted

static func build() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_box(surface, Vector3(0.0, 0.95, 0.0), Vector3(0.48, 0.9, 0.32))
	_add_box(surface, Vector3(0.0, 1.65, 0.0), Vector3(0.34, 0.34, 0.34))
	_add_box(surface, Vector3(-0.13, 0.35, 0.0), Vector3(0.16, 0.7, 0.2))
	_add_box(surface, Vector3(0.13, 0.35, 0.0), Vector3(0.16, 0.7, 0.2))
	surface.generate_normals()
	return surface.commit()

static func build_mid(spec: SoldierVisualArchetype) -> ArrayMesh:
	return _build_humanoid(spec, false)

static func build_far(spec: SoldierVisualArchetype) -> ArrayMesh:
	return _build_humanoid(spec, true)

static func _build_humanoid(spec: SoldierVisualArchetype, far_detail: bool) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var detail_scale: float = 0.74 if far_detail else 1.0
	_add_box(
		surface,
		Vector3(0.0, 0.92, 0.0),
		Vector3(spec.body_width, spec.body_height, spec.body_depth) * detail_scale
	)
	_add_box(
		surface,
		Vector3(0.0, 1.65, 0.0),
		Vector3(spec.head_size, spec.head_size, spec.head_size) * detail_scale
	)
	_add_box(surface, Vector3(-0.13, 0.35, 0.0), Vector3(0.16, 0.7, 0.20) * detail_scale)
	_add_box(surface, Vector3(0.13, 0.35, 0.0), Vector3(0.16, 0.7, 0.20) * detail_scale)
	_add_box(surface, Vector3(-0.34, 1.0, 0.0), Vector3(0.14, 0.64, 0.16) * detail_scale)
	_add_box(surface, Vector3(0.34, 1.0, 0.0), Vector3(0.14, 0.64, 0.16) * detail_scale)

	if not far_detail and spec.id == 1:
		_add_box(surface, Vector3(-0.28, 1.26, 0.0), Vector3(0.18, 0.18, 0.42))
		_add_box(surface, Vector3(0.28, 1.26, 0.0), Vector3(0.18, 0.18, 0.42))
	_add_equipment(surface, spec, detail_scale)
	surface.generate_normals()
	return surface.commit()

static func _add_equipment(surface: SurfaceTool, spec: SoldierVisualArchetype, detail_scale: float) -> void:
	if spec.weapon_kind == &"spear":
		_add_box(
			surface,
			Vector3(0.42, 1.52, 0.0),
			Vector3(0.055, spec.weapon_length, 0.055) * detail_scale
		)
	else:
		_add_box(
			surface,
			Vector3(0.40, 1.15, 0.0),
			Vector3(0.075, spec.weapon_length, 0.075) * detail_scale
		)
	if spec.has_shield:
		_add_box(
			surface,
			Vector3(-0.38, 1.04, -0.06),
			Vector3(spec.shield_width, spec.shield_height, 0.10) * detail_scale
		)
	if spec.id == 1:
		_add_box(surface, Vector3(0.0, 1.90, 0.0), Vector3(0.42, 0.16, 0.42) * detail_scale)

static func _add_box(surface: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var half: Vector3 = size * 0.5
	var faces: Array[Array] = [
		[Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
		[Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)],
		[Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(-1, 1, -1)],
		[Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1)],
		[Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1)],
		[Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)]
	]
	for face: Array in faces:
		var a: Vector3 = center + Vector3(face[0]) * half
		var b: Vector3 = center + Vector3(face[1]) * half
		var c: Vector3 = center + Vector3(face[2]) * half
		var d: Vector3 = center + Vector3(face[3]) * half
		surface.add_vertex(a)
		surface.add_vertex(b)
		surface.add_vertex(c)
		surface.add_vertex(a)
		surface.add_vertex(c)
		surface.add_vertex(d)
