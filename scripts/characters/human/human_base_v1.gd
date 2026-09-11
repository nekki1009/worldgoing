class_name HumanBaseV1
extends Node3D

const HumanRigType = preload("res://scripts/benchmark/3d_crowd/human_rig_v1.gd")
const AnimationStateType = preload("res://scripts/benchmark/3d_special/special_character_animation_state.gd")
const AnimationLibraryType = preload("res://scripts/benchmark/3d_special/special_human_animation_library.gd")

const MATERIAL_PATH: String = "res://assets/characters/human/v1/human_base_v1_material.tres"
const HEIGHT_M: float = 1.78
const TRIANGLE_MIN: int = 3000
const TRIANGLE_MAX: int = 8000
const FORWARD_AXIS: StringName = &"-Z"

# HumanBase_v1 uses the supplied pixel-art body as a proportion and palette
# reference. These are deliberately a small, warm palette so the silhouette
# reads before lighting does, while the mesh remains one skinned surface.
# Color values are authored in linear space because Godot converts vertex
# colors to the display color space on the unshaded production material.
const SKIN_BASE: Color = Color(0.88, 0.45, 0.16)
const SKIN_LIGHT: Color = Color(1.0, 0.62, 0.24)
const SKIN_SHADOW: Color = Color(0.47, 0.115, 0.043)

const BODY_REGION_NAMES: Array[StringName] = [
	&"HEAD", &"TORSO",
	&"UPPER_ARM_L", &"UPPER_ARM_R", &"FOREARM_L", &"FOREARM_R",
	&"HAND_L", &"HAND_R", &"PELVIS", &"THIGH_L", &"THIGH_R",
	&"LOWER_LEG_L", &"LOWER_LEG_R", &"FOOT_L", &"FOOT_R"
]

const SOCKET_NAMES: Array[StringName] = [
	&"weapon_socket_r", &"shield_socket_l", &"head_socket", &"back_socket"
]

enum DebugMode { MESH, SKELETON, WIREFRAME, BODY_REGIONS, SOCKETS }

var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var mesh_instance: MeshInstance3D
var wireframe_instance: MeshInstance3D
var region_debug_instance: MeshInstance3D
var skeleton_gizmo_instance: MeshInstance3D
var skeleton_gizmo: ImmediateMesh
var body_mesh: ArrayMesh
var region_debug_mesh: ArrayMesh
var body_material: StandardMaterial3D
var skin: Skin
var socket_attachments: Dictionary = {}
var region_vertex_ranges: Dictionary = {}
var animation_state: int = AnimationStateType.State.IDLE
var animation_time: float = 0.0
var animation_phase: float = 0.0
var debug_mode: int = DebugMode.MESH

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _colors := PackedColorArray()
var _region_colors := PackedColorArray()
var _bones := PackedInt32Array()
var _weights := PackedFloat32Array()
var _indices := PackedInt32Array()
var _active_region: StringName = &""
var _active_debug_color: Color = Color.WHITE
var _active_region_vertex_start: int = 0
var _active_region_index_start: int = 0
var _built: bool = false

func _ready() -> void:
	build()

func _process(_delta: float) -> void:
	if debug_mode == DebugMode.SKELETON and skeleton_gizmo_instance != null:
		_rebuild_skeleton_gizmo()

func build() -> void:
	if _built:
		return
	_built = true
	skeleton = HumanRigType.build_skeleton()
	skeleton.name = "HumanRig_v1"
	add_child(skeleton)
	skeleton.reset_bone_poses()

	_build_mesh_arrays()
	body_material = load(MATERIAL_PATH) as StandardMaterial3D
	if body_material == null:
		body_material = StandardMaterial3D.new()
		body_material.albedo_color = Color.WHITE
		body_material.vertex_color_use_as_albedo = true
		body_material.roughness = 0.88
	body_mesh = _make_mesh(_colors, body_material)
	region_debug_mesh = _make_mesh(_region_colors, _debug_material(true, false))

	skin = Skin.new()
	for bone_index: int in range(skeleton.get_bone_count()):
		skin.add_bind(bone_index, skeleton.get_bone_global_rest(bone_index).affine_inverse())

	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "HumanBase_v1_SkinnedBody"
	mesh_instance.mesh = body_mesh
	add_child(mesh_instance)
	mesh_instance.skin = skin
	mesh_instance.skeleton = mesh_instance.get_path_to(skeleton)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	wireframe_instance = MeshInstance3D.new()
	wireframe_instance.name = "HumanBase_v1_WireframeDebug"
	wireframe_instance.mesh = _make_wireframe_mesh()
	add_child(wireframe_instance)
	wireframe_instance.material_override = _debug_material(false, true)
	wireframe_instance.visible = false

	region_debug_instance = MeshInstance3D.new()
	region_debug_instance.name = "HumanBase_v1_BodyRegionDebug"
	region_debug_instance.mesh = region_debug_mesh
	add_child(region_debug_instance)
	region_debug_instance.skin = skin
	region_debug_instance.skeleton = region_debug_instance.get_path_to(skeleton)
	region_debug_instance.visible = false

	animation_player = AnimationPlayer.new()
	animation_player.name = "HumanRig_v1_AnimationPlayer"
	animation_player.add_animation_library(&"", AnimationLibraryType.build_library())
	animation_player.active = false
	add_child(animation_player)

	_build_socket_attachments()
	_build_skeleton_gizmo()
	set_debug_mode(DebugMode.MESH)
	set_animation_state(AnimationStateType.State.IDLE, 0.0, 0.0)

func set_animation_state(next_state: int, next_time: float, next_phase: float = 0.0) -> void:
	if not _built or skeleton == null:
		return
	animation_state = clampi(next_state, AnimationStateType.State.IDLE, AnimationStateType.State.BLOCK)
	animation_time = next_time
	animation_phase = next_phase
	var clip_name: StringName = AnimationLibraryType.clip_for(animation_state)
	if animation_player != null and animation_player.current_animation != clip_name:
		animation_player.play(clip_name)
		animation_player.active = false
	AnimationLibraryType.sample(
		skeleton, HumanRigType.bone_indices(), animation_state, animation_time, animation_phase
	)
	skeleton.force_update_all_bone_transforms()
	if debug_mode == DebugMode.SKELETON:
		_rebuild_skeleton_gizmo()

func advance_animation(delta: float, phase: float = 0.0) -> void:
	animation_time += delta
	animation_phase = phase
	set_animation_state(animation_state, animation_time, animation_phase)

func set_debug_mode(next_mode: int) -> void:
	debug_mode = clampi(next_mode, DebugMode.MESH, DebugMode.SOCKETS)
	if mesh_instance == null:
		return
	mesh_instance.visible = debug_mode in [DebugMode.MESH, DebugMode.SKELETON, DebugMode.SOCKETS]
	wireframe_instance.visible = debug_mode == DebugMode.WIREFRAME
	region_debug_instance.visible = debug_mode == DebugMode.BODY_REGIONS
	skeleton_gizmo_instance.visible = debug_mode == DebugMode.SKELETON
	for socket_name: StringName in SOCKET_NAMES:
		var attachment: BoneAttachment3D = socket_attachments.get(socket_name)
		if attachment != null:
			attachment.visible = debug_mode == DebugMode.SOCKETS
	if debug_mode == DebugMode.SKELETON:
		_rebuild_skeleton_gizmo()

func get_socket_transform(socket_name: StringName) -> Transform3D:
	if skeleton != null:
		var bone_index: int = skeleton.find_bone(socket_name)
		if bone_index >= 0:
			return skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)
	return Transform3D.IDENTITY

func get_socket_bone_name(socket_name: StringName) -> StringName:
	var attachment: BoneAttachment3D = socket_attachments.get(socket_name)
	return attachment.bone_name if attachment != null else &""

func get_body_region_names() -> Array[StringName]:
	return BODY_REGION_NAMES.duplicate()

func get_stats() -> Dictionary:
	if body_mesh == null:
		return {}
	var arrays: Array = body_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index_data: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	return {
		"height": body_mesh.get_aabb().size.y,
		"aabb_min_y": body_mesh.get_aabb().position.y,
		"vertices": vertices.size(),
		"triangles": index_data.size() / 3,
		"surfaces": body_mesh.get_surface_count(),
		"materials": 1,
		"skinned_meshes": 1,
		"bones": skeleton.get_bone_count(),
		"regions": BODY_REGION_NAMES.size(),
		"sockets": SOCKET_NAMES.size(),
		"forward_axis": FORWARD_AXIS,
		"root_origin": global_position,
		"root_scale": scale
	}

func validate_weights() -> bool:
	if body_mesh == null or body_mesh.get_surface_count() != 1:
		return false
	var arrays: Array = body_mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if bones.size() != weights.size() or bones.size() % 4 != 0:
		return false
	for vertex_index: int in range(bones.size() / 4):
		var total: float = 0.0
		for slot: int in range(4):
			var bone_index: int = bones[vertex_index * 4 + slot]
			var weight: float = weights[vertex_index * 4 + slot]
			if bone_index < 0 or bone_index >= skeleton.get_bone_count() or weight < -0.001:
				return false
			total += weight
		if absf(total - 1.0) > 0.001:
			return false
	return true

func validate_topology() -> bool:
	if body_mesh == null or body_mesh.get_surface_count() != 1:
		return false
	var arrays: Array = body_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index_data: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if vertices.is_empty() or index_data.is_empty() or index_data.size() % 3 != 0:
		return false
	var edge_counts: Dictionary = {}
	for triangle_start: int in range(0, index_data.size(), 3):
		var a: int = index_data[triangle_start]
		var b: int = index_data[triangle_start + 1]
		var c: int = index_data[triangle_start + 2]
		if a == b or b == c or c == a:
			return false
		for edge: Array in [[a, b], [b, c], [c, a]]:
			var low: int = mini(edge[0], edge[1])
			var high: int = maxi(edge[0], edge[1])
			var key: String = "%d:%d" % [low, high]
			edge_counts[key] = int(edge_counts.get(key, 0)) + 1
	for count: int in edge_counts.values():
		if count != 2:
			return false
	return true

func populate_render_bundle(bundle: Object) -> bool:
	if bundle == null or body_mesh == null:
		return false
	bundle.set("skinned_mesh", body_mesh)
	bundle.set("skinned_material", body_material)
	bundle.set("source_skinned_parts", [&"HumanBase_v1"])
	bundle.set("skinned_triangles", int(get_stats().triangles))
	return true

func _build_mesh_arrays() -> void:
	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_uvs = PackedVector2Array()
	_colors = PackedColorArray()
	_region_colors = PackedColorArray()
	_bones = PackedInt32Array()
	_weights = PackedFloat32Array()
	_indices = PackedInt32Array()

	_begin_region(&"HEAD", Color("#d7a486"))
	var head_position := _bone_position(HumanRigType.Bone.HEAD)
	# Compact Q proportions with broad planar cheeks, a flatter crown, and a
	# tapered jaw instead of a spherical doll head.
	_append_ellipsoid(
		head_position, Vector3(0.180, 0.170, 0.160), HumanRigType.Bone.HEAD,
		SKIN_BASE, Rect2(0.32, 0.74, 0.18, 0.25), 8, 12, 0.68, 0.62
	)
	_append_ellipsoid(
		head_position + Vector3(0.0, -0.018, -0.158),
		Vector3(0.024, 0.030, 0.020), HumanRigType.Bone.HEAD,
		SKIN_BASE.lerp(SKIN_SHADOW, 0.35), Rect2(0.32, 0.74, 0.18, 0.25), 5, 8, 1.0, 0.52
	)
	_append_ellipsoid(head_position + Vector3(-0.176, 0.0, 0.0), Vector3(0.024, 0.040, 0.026), HumanRigType.Bone.HEAD, SKIN_BASE, Rect2(0.32, 0.74, 0.18, 0.25), 6, 10, 1.0, 0.58)
	_append_ellipsoid(head_position + Vector3(0.176, 0.0, 0.0), Vector3(0.024, 0.040, 0.026), HumanRigType.Bone.HEAD, SKIN_BASE, Rect2(0.32, 0.74, 0.18, 0.25), 6, 10, 1.0, 0.58)
	_end_region()

	_begin_region(&"TORSO", Color("#6d8f98"))
	_build_body_shell()
	var neck := _bone_position(HumanRigType.Bone.NECK)
	_append_capsule_between(
		neck + Vector3(0.0, -0.09, 0.0), head_position + Vector3(0.0, -0.09, 0.0),
		0.058, HumanRigType.Bone.NECK, HumanRigType.Bone.HEAD, SKIN_BASE, Rect2(0.32, 0.50, 0.18, 0.20)
	)
	_end_region()

	_begin_region(&"UPPER_ARM_L", Color("#e2a65f"))
	_append_capsule_between(
		_bone_position(HumanRigType.Bone.UPPER_ARM_L), _bone_position(HumanRigType.Bone.LOWER_ARM_L),
		0.060, HumanRigType.Bone.UPPER_ARM_L, HumanRigType.Bone.LOWER_ARM_L, SKIN_BASE, Rect2(0.52, 0.00, 0.12, 0.44), 10, 1.08, 0.88
	)
	_append_ellipsoid(_bone_position(HumanRigType.Bone.UPPER_ARM_L), Vector3(0.072, 0.060, 0.074), HumanRigType.Bone.UPPER_ARM_L, SKIN_BASE, Rect2(0.52, 0.00, 0.12, 0.44), 7, 12, 1.0, 0.48)
	_end_region()

	_begin_region(&"UPPER_ARM_R", Color("#e2a65f"))
	_append_capsule_between(
		_bone_position(HumanRigType.Bone.UPPER_ARM_R), _bone_position(HumanRigType.Bone.LOWER_ARM_R),
		0.060, HumanRigType.Bone.UPPER_ARM_R, HumanRigType.Bone.LOWER_ARM_R, SKIN_BASE, Rect2(0.66, 0.00, 0.12, 0.44), 10, 1.08, 0.88
	)
	_append_ellipsoid(_bone_position(HumanRigType.Bone.UPPER_ARM_R), Vector3(0.072, 0.060, 0.074), HumanRigType.Bone.UPPER_ARM_R, SKIN_BASE, Rect2(0.66, 0.00, 0.12, 0.44), 7, 12, 1.0, 0.48)
	_end_region()

	_begin_region(&"FOREARM_L", Color("#efbd66"))
	_append_capsule_between(
		_bone_position(HumanRigType.Bone.LOWER_ARM_L), _bone_position(HumanRigType.Bone.HAND_L),
		0.050, HumanRigType.Bone.LOWER_ARM_L, HumanRigType.Bone.HAND_L, SKIN_BASE, Rect2(0.52, 0.45, 0.12, 0.38), 10, 1.04, 0.82
	)
	_end_region()

	_begin_region(&"FOREARM_R", Color("#efbd66"))
	_append_capsule_between(
		_bone_position(HumanRigType.Bone.LOWER_ARM_R), _bone_position(HumanRigType.Bone.HAND_R),
		0.050, HumanRigType.Bone.LOWER_ARM_R, HumanRigType.Bone.HAND_R, SKIN_BASE, Rect2(0.66, 0.45, 0.12, 0.38), 10, 1.04, 0.82
	)
	_end_region()

	_begin_region(&"HAND_L", Color("#c56f9a"))
	_append_hand(HumanRigType.Bone.HAND_L, -1.0, Rect2(0.80, 0.00, 0.08, 0.25))
	_end_region()

	_begin_region(&"HAND_R", Color("#c56f9a"))
	_append_hand(HumanRigType.Bone.HAND_R, 1.0, Rect2(0.89, 0.00, 0.08, 0.25))
	_end_region()

	_begin_region(&"PELVIS", Color("#5f6d79"))
	# Keep the region anchor beneath the continuous body shell; underwear and
	# other garments belong to later replaceable clothing layers.
	_append_ellipsoid(Vector3(0.0, 0.790, 0.0), Vector3(0.150, 0.095, 0.105), HumanRigType.Bone.PELVIS, SKIN_BASE, Rect2(0.00, 0.00, 0.30, 0.48), 8, 12)
	_end_region()

	_begin_region(&"THIGH_L", Color("#7a8790"))
	_append_capsule_between(
		_bone_position(HumanRigType.Bone.UPPER_LEG_L), _bone_position(HumanRigType.Bone.LOWER_LEG_L),
		0.078, HumanRigType.Bone.UPPER_LEG_L, HumanRigType.Bone.LOWER_LEG_L, SKIN_BASE, Rect2(0.52, 0.52, 0.12, 0.46), 10, 1.06, 0.80
	)
	_append_ellipsoid(_bone_position(HumanRigType.Bone.UPPER_LEG_L), Vector3(0.080, 0.065, 0.080), HumanRigType.Bone.UPPER_LEG_L, SKIN_BASE, Rect2(0.52, 0.52, 0.12, 0.46), 7, 12, 1.0, 0.50)
	_end_region()

	_begin_region(&"THIGH_R", Color("#7a8790"))
	_append_capsule_between(
		_bone_position(HumanRigType.Bone.UPPER_LEG_R), _bone_position(HumanRigType.Bone.LOWER_LEG_R),
		0.078, HumanRigType.Bone.UPPER_LEG_R, HumanRigType.Bone.LOWER_LEG_R, SKIN_BASE, Rect2(0.66, 0.52, 0.12, 0.46), 10, 1.06, 0.80
	)
	_append_ellipsoid(_bone_position(HumanRigType.Bone.UPPER_LEG_R), Vector3(0.080, 0.065, 0.080), HumanRigType.Bone.UPPER_LEG_R, SKIN_BASE, Rect2(0.66, 0.52, 0.12, 0.46), 7, 12, 1.0, 0.50)
	_end_region()

	_begin_region(&"LOWER_LEG_L", Color("#8d9ca4"))
	_append_capsule_between(
		_bone_position(HumanRigType.Bone.LOWER_LEG_L), _bone_position(HumanRigType.Bone.FOOT_L) + Vector3(0.0, 0.025, 0.0),
		0.058, HumanRigType.Bone.LOWER_LEG_L, HumanRigType.Bone.FOOT_L, SKIN_BASE, Rect2(0.52, 0.00, 0.12, 0.38), 10, 0.96, 0.70
	)
	_append_ellipsoid((_bone_position(HumanRigType.Bone.LOWER_LEG_L) + _bone_position(HumanRigType.Bone.FOOT_L)) * 0.5 + Vector3(0.0, 0.020, 0.0), Vector3(0.055, 0.110, 0.052), HumanRigType.Bone.LOWER_LEG_L, SKIN_BASE, Rect2(0.52, 0.00, 0.12, 0.38), 7, 12, 1.0, 0.50)
	_end_region()

	_begin_region(&"LOWER_LEG_R", Color("#8d9ca4"))
	_append_capsule_between(
		_bone_position(HumanRigType.Bone.LOWER_LEG_R), _bone_position(HumanRigType.Bone.FOOT_R) + Vector3(0.0, 0.025, 0.0),
		0.058, HumanRigType.Bone.LOWER_LEG_R, HumanRigType.Bone.FOOT_R, SKIN_BASE, Rect2(0.66, 0.00, 0.12, 0.38), 10, 0.96, 0.70
	)
	_append_ellipsoid((_bone_position(HumanRigType.Bone.LOWER_LEG_R) + _bone_position(HumanRigType.Bone.FOOT_R)) * 0.5 + Vector3(0.0, 0.020, 0.0), Vector3(0.055, 0.110, 0.052), HumanRigType.Bone.LOWER_LEG_R, SKIN_BASE, Rect2(0.66, 0.00, 0.12, 0.38), 7, 12, 1.0, 0.50)
	_end_region()

	_begin_region(&"FOOT_L", Color("#b7c2c8"))
	_append_ellipsoid(
		_bone_position(HumanRigType.Bone.FOOT_L) + Vector3(0.0, 0.048, -0.055),
		Vector3(0.080, 0.048, 0.145), HumanRigType.Bone.FOOT_L, SKIN_BASE,
		Rect2(0.80, 0.28, 0.08, 0.22), 7, 12, 1.0, 0.58
	)
	_end_region()

	_begin_region(&"FOOT_R", Color("#b7c2c8"))
	_append_ellipsoid(
		_bone_position(HumanRigType.Bone.FOOT_R) + Vector3(0.0, 0.048, -0.055),
		Vector3(0.080, 0.048, 0.145), HumanRigType.Bone.FOOT_R, SKIN_BASE,
		Rect2(0.89, 0.28, 0.08, 0.22), 7, 12, 1.0, 0.58
	)
	_end_region()

func _build_body_shell() -> void:
	var rings: Array[Array] = [
		[0.67, 0.14, 0.10, HumanRigType.Bone.PELVIS, HumanRigType.Bone.UPPER_LEG_L, 0.0],
		[0.78, 0.17, 0.125, HumanRigType.Bone.PELVIS, HumanRigType.Bone.SPINE, 0.15],
		[0.94, 0.16, 0.115, HumanRigType.Bone.PELVIS, HumanRigType.Bone.SPINE, 0.55],
		[1.08, 0.18, 0.13, HumanRigType.Bone.SPINE, HumanRigType.Bone.CHEST, 0.35],
		[1.20, 0.205, 0.145, HumanRigType.Bone.CHEST, HumanRigType.Bone.NECK, 0.20],
		[1.33, 0.235, 0.16, HumanRigType.Bone.CHEST, HumanRigType.Bone.NECK, 0.20],
		[1.43, 0.16, 0.11, HumanRigType.Bone.CHEST, HumanRigType.Bone.NECK, 0.75]
	]
	var segments: int = 12
	var ring_indices: Array[PackedInt32Array] = []
	for ring: Array in rings:
		var ring_index := PackedInt32Array()
		for segment: int in range(segments):
			var angle: float = TAU * (float(segment) + 0.5) / float(segments)
			var angle_x: float = signf(cos(angle)) * pow(absf(cos(angle)), 0.65)
			var angle_z: float = signf(sin(angle)) * pow(absf(sin(angle)), 0.65)
			var position := Vector3(angle_x * ring[1], ring[0], angle_z * ring[2])
			var normal := Vector3(angle_x, 0.0, angle_z).normalized()
			var blend: float = float(ring[5])
			var frontness: float = maxf(0.0, -sin(angle))
			var surface_color: Color = SKIN_BASE.lerp(SKIN_LIGHT, 0.06 + frontness * 0.28)
			if absf(cos(angle)) > 0.78:
				surface_color = surface_color.lerp(SKIN_SHADOW, 0.20)
			_append_vertex(
				position, normal, _uv(Rect2(0.00, 0.00, 0.30, 0.48), float(segment) / float(segments), (ring[0] - 0.67) / 0.76),
				int(ring[3]), int(ring[4]), blend, _shade_surface_color(surface_color, normal)
			)
			ring_index.append(_vertices.size() - 1)
		ring_indices.append(ring_index)
	for ring_index: int in range(ring_indices.size() - 1):
		var lower: PackedInt32Array = ring_indices[ring_index]
		var upper: PackedInt32Array = ring_indices[ring_index + 1]
		for segment: int in range(segments):
			var next: int = (segment + 1) % segments
			_append_triangle(lower[segment], upper[segment], lower[next])
			_append_triangle(lower[next], upper[segment], upper[next])
	var bottom_center := _append_vertex(
		Vector3(0.0, 0.67, 0.0), Vector3.DOWN, Vector2(0.15, 0.0),
		HumanRigType.Bone.PELVIS, HumanRigType.Bone.PELVIS, 0.0, SKIN_SHADOW
	)
	var top_center := _append_vertex(
		Vector3(0.0, 1.43, 0.0), Vector3.UP, Vector2(0.15, 1.0),
		HumanRigType.Bone.CHEST, HumanRigType.Bone.NECK, 0.75, SKIN_LIGHT
	)
	for segment: int in range(segments):
		var next: int = (segment + 1) % segments
		_append_triangle(bottom_center, ring_indices[0][next], ring_indices[0][segment])
		_append_triangle(top_center, ring_indices[ring_indices.size() - 1][segment], ring_indices[ring_indices.size() - 1][next])

func _append_hand(bone_index: int, side: float, uv_rect: Rect2) -> void:
	var palm := _bone_position(bone_index) + Vector3(0.0, -0.030, 0.0)
	_append_ellipsoid(palm, Vector3(0.060, 0.075, 0.055), bone_index, SKIN_BASE, uv_rect, 7, 12, 0.82, 0.62)
	var thumb_start := palm + Vector3(side * 0.038, -0.004, 0.0)
	_append_capsule_between(
		thumb_start, thumb_start + Vector3(side * 0.038, -0.035, -0.015),
		0.018, bone_index, bone_index, SKIN_LIGHT, uv_rect
	)

func _append_ellipsoid(
	center: Vector3,
	radii: Vector3,
	bone_a: int,
	color: Color,
	uv_rect: Rect2,
	latitudes: int = 7,
	longitudes: int = 12,
	lower_taper: float = 1.0,
	shape_power: float = 0.72
) -> void:
	var top := _append_vertex(
		center + Vector3(0.0, radii.y, 0.0), Vector3.UP,
		_uv(uv_rect, 0.5, 1.0), bone_a, bone_a, 0.0, _shade_surface_color(color, Vector3.UP)
	)
	var rings: Array[PackedInt32Array] = []
	for latitude: int in range(1, latitudes):
		var theta: float = PI * float(latitude) / float(latitudes)
		var lower_blend: float = clampf(-cos(theta), 0.0, 1.0)
		var taper: float = lerpf(1.0, clampf(lower_taper, 0.5, 1.0), lower_blend * lower_blend)
		var shaped_radius: float = pow(absf(sin(theta)), shape_power)
		var shaped_y: float = signf(cos(theta)) * pow(absf(cos(theta)), shape_power)
		var ring := PackedInt32Array()
		for longitude: int in range(longitudes):
			var phi: float = TAU * (float(longitude) + 0.5) / float(longitudes)
			var shaped_x: float = signf(cos(phi)) * pow(absf(cos(phi)), shape_power)
			var shaped_z: float = signf(sin(phi)) * pow(absf(sin(phi)), shape_power)
			var local := Vector3(
				shaped_x * shaped_radius * radii.x * taper,
				shaped_y * radii.y,
				shaped_z * shaped_radius * radii.z * lerpf(1.0, maxf(lower_taper, 0.82), lower_blend * lower_blend)
			)
			var normal := Vector3(
				shaped_x * shaped_radius / maxf(radii.x, 0.0001),
				shaped_y / maxf(radii.y, 0.0001),
				shaped_z * shaped_radius / maxf(radii.z, 0.0001)
			).normalized()
			ring.append(_append_vertex(
				center + local, normal,
				_uv(uv_rect, float(longitude) / float(longitudes), 1.0 - float(latitude) / float(latitudes)),
				bone_a, bone_a, 0.0, _shade_surface_color(color, normal)
			))
		rings.append(ring)
	var bottom := _append_vertex(
		center - Vector3(0.0, radii.y, 0.0), Vector3.DOWN,
		_uv(uv_rect, 0.5, 0.0), bone_a, bone_a, 0.0, _shade_surface_color(color, Vector3.DOWN)
	)
	for longitude: int in range(longitudes):
		var next: int = (longitude + 1) % longitudes
		_append_triangle(top, rings[0][next], rings[0][longitude])
	for ring_index: int in range(rings.size() - 1):
		var upper: PackedInt32Array = rings[ring_index]
		var lower: PackedInt32Array = rings[ring_index + 1]
		for longitude: int in range(longitudes):
			var next: int = (longitude + 1) % longitudes
			_append_triangle(upper[longitude], lower[longitude], upper[next])
			_append_triangle(upper[next], lower[longitude], lower[next])
	for longitude: int in range(longitudes):
		var next: int = (longitude + 1) % longitudes
		_append_triangle(bottom, rings[rings.size() - 1][longitude], rings[rings.size() - 1][next])

func _append_capsule_between(
	start: Vector3,
	end: Vector3,
	radius: float,
	bone_a: int,
	bone_b: int,
	color: Color,
	uv_rect: Rect2,
	segments: int = 10,
	start_radius_scale: float = 1.0,
	end_radius_scale: float = 1.0
) -> void:
	var direction := end - start
	var length: float = maxf(direction.length(), 0.001)
	var basis := _basis_for_y(direction)
	var center := (start + end) * 0.5
	var axial: Array[float] = [
		-length * 0.5 - radius * 0.16,
		-length * 0.5,
		length * 0.5,
		length * 0.5 + radius * 0.16
	]
	var radial: Array[float] = [
		radius * 0.28 * start_radius_scale,
		radius * start_radius_scale,
		radius * end_radius_scale,
		radius * 0.28 * end_radius_scale
	]
	var rings: Array[PackedInt32Array] = []
	for ring_index: int in range(axial.size()):
		var ring := PackedInt32Array()
		var t: float = float(ring_index) / float(axial.size() - 1)
		var blend: float = 0.0 if bone_a == bone_b else smoothstep(0.65, 1.0, t)
		for segment: int in range(segments):
			var angle: float = TAU * (float(segment) + 0.5) / float(segments)
			var local := Vector3(cos(angle) * radial[ring_index], axial[ring_index], sin(angle) * radial[ring_index])
			var normal := (basis * Vector3(cos(angle), 0.0, sin(angle))).normalized()
			ring.append(_append_vertex(
				center + basis * local, normal,
				_uv(uv_rect, float(segment) / float(segments), t), bone_a, bone_b, blend, _shade_surface_color(color, normal)
			))
		rings.append(ring)
	var start_pole := _append_vertex(
		center + basis * Vector3(0.0, axial[0] - radius * 0.11, 0.0), -basis.y,
		_uv(uv_rect, 0.5, 0.0), bone_a, bone_b, 0.0, _shade_surface_color(color, -basis.y)
	)
	var end_pole := _append_vertex(
		center + basis * Vector3(0.0, axial[axial.size() - 1] + radius * 0.11, 0.0), basis.y,
		_uv(uv_rect, 0.5, 1.0), bone_a, bone_b, 1.0, _shade_surface_color(color, basis.y)
	)
	for segment: int in range(segments):
		var next: int = (segment + 1) % segments
		_append_triangle(start_pole, rings[0][next], rings[0][segment])
		_append_triangle(end_pole, rings[rings.size() - 1][segment], rings[rings.size() - 1][next])
	for ring_index: int in range(rings.size() - 1):
		var current: PackedInt32Array = rings[ring_index]
		var next_ring: PackedInt32Array = rings[ring_index + 1]
		for segment: int in range(segments):
			var next: int = (segment + 1) % segments
			_append_triangle(current[segment], next_ring[segment], current[next])
			_append_triangle(current[next], next_ring[segment], next_ring[next])

func _shade_surface_color(color: Color, normal: Vector3) -> Color:
	var light_factor: float = 0.82 + normal.y * 0.12 + (-normal.z) * 0.12 + (-normal.x) * 0.04
	light_factor = clampf(light_factor, 0.62, 1.10)
	return Color(color.r * light_factor, color.g * light_factor, color.b * light_factor, color.a)

func _append_vertex(
	position: Vector3,
	normal: Vector3,
	uv: Vector2,
	bone_a: int,
	bone_b: int,
	blend: float,
	color: Color
) -> int:
	var index: int = _vertices.size()
	_vertices.append(position)
	_normals.append(normal.normalized())
	_uvs.append(uv)
	_colors.append(color)
	_region_colors.append(_active_debug_color)
	_bones.append(bone_a)
	_bones.append(bone_b if bone_b >= 0 else bone_a)
	_bones.append(0)
	_bones.append(0)
	var clamped_blend: float = clampf(blend, 0.0, 1.0) if bone_a != bone_b else 0.0
	_weights.append(1.0 - clamped_blend)
	_weights.append(clamped_blend)
	_weights.append(0.0)
	_weights.append(0.0)
	return index

func _append_triangle(a: int, b: int, c: int) -> void:
	_indices.append(a)
	_indices.append(b)
	_indices.append(c)

func _begin_region(region_name: StringName, debug_color: Color) -> void:
	_active_region = region_name
	_active_debug_color = debug_color
	_active_region_vertex_start = _vertices.size()
	_active_region_index_start = _indices.size()

func _end_region() -> void:
	region_vertex_ranges[_active_region] = {
		"vertex_start": _active_region_vertex_start,
		"vertex_count": _vertices.size() - _active_region_vertex_start,
		"index_start": _active_region_index_start,
		"index_count": _indices.size() - _active_region_index_start,
		"triangles": (_indices.size() - _active_region_index_start) / 3
	}
	_active_region = &""

func _make_mesh(colors: PackedColorArray, material: Material) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_BONES] = _bones
	arrays[Mesh.ARRAY_WEIGHTS] = _weights
	arrays[Mesh.ARRAY_INDEX] = _indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh

func _make_wireframe_mesh() -> ArrayMesh:
	var line_vertices := PackedVector3Array()
	var seen_edges: Dictionary = {}
	for triangle_start: int in range(0, _indices.size(), 3):
		var triangle: Array[int] = [
			_indices[triangle_start], _indices[triangle_start + 1], _indices[triangle_start + 2]
		]
		for edge_index: int in range(3):
			var a: int = triangle[edge_index]
			var b: int = triangle[(edge_index + 1) % 3]
			var low: int = mini(a, b)
			var high: int = maxi(a, b)
			var key: String = "%d:%d" % [low, high]
			if seen_edges.has(key):
				continue
			seen_edges[key] = true
			line_vertices.append(_vertices[a])
			line_vertices.append(_vertices[b])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = line_vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh

func _build_socket_attachments() -> void:
	for socket_name: StringName in SOCKET_NAMES:
		var attachment := BoneAttachment3D.new()
		attachment.name = socket_name
		attachment.bone_name = socket_name
		skeleton.add_child(attachment)
		attachment.add_child(_socket_marker(socket_name))
		attachment.visible = false
		socket_attachments[socket_name] = attachment

func _socket_marker(socket_name: StringName) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = "%s_Gizmo" % socket_name
	var sphere := SphereMesh.new()
	sphere.radius = 0.035
	sphere.height = 0.070
	marker.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("#ffd166")
	material.emission_enabled = true
	material.emission = Color("#ffd166")
	material.emission_energy_multiplier = 1.8
	marker.material_override = material
	return marker

func _build_skeleton_gizmo() -> void:
	skeleton_gizmo = ImmediateMesh.new()
	skeleton_gizmo_instance = MeshInstance3D.new()
	skeleton_gizmo_instance.name = "HumanBase_v1_SkeletonGizmo"
	skeleton_gizmo_instance.mesh = skeleton_gizmo
	skeleton_gizmo_instance.material_override = _debug_material(false, false)
	skeleton_gizmo_instance.visible = false
	add_child(skeleton_gizmo_instance)
	_rebuild_skeleton_gizmo()

func _rebuild_skeleton_gizmo() -> void:
	if skeleton_gizmo == null or skeleton == null:
		return
	skeleton_gizmo.clear_surfaces()
	var material := _debug_material(false, false)
	skeleton_gizmo.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for bone_index: int in range(skeleton.get_bone_count()):
		var parent_index: int = skeleton.get_bone_parent(bone_index)
		if parent_index < 0:
			continue
		var parent_position: Vector3 = skeleton.get_bone_global_pose(parent_index).origin
		var position: Vector3 = skeleton.get_bone_global_pose(bone_index).origin
		skeleton_gizmo.surface_add_vertex(parent_position)
		skeleton_gizmo.surface_add_vertex(position)
	skeleton_gizmo.surface_end()

func _debug_material(vertex_colors: bool, wireframe: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.WHITE
	material.vertex_color_use_as_albedo = vertex_colors
	if wireframe:
		material.albedo_color = Color("#b8e1ff")
	material.no_depth_test = wireframe
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _bone_position(bone_index: int) -> Vector3:
	return skeleton.get_bone_global_rest(bone_index).origin

func _basis_for_y(direction: Vector3) -> Basis:
	var y := direction.normalized()
	var reference := Vector3.FORWARD
	if absf(y.dot(reference)) > 0.90:
		reference = Vector3.RIGHT
	var x := reference.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

func _uv(rect: Rect2, u: float, v: float) -> Vector2:
	return rect.position + Vector2(clampf(u, 0.0, 1.0), clampf(v, 0.0, 1.0)) * rect.size
