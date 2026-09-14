extends RefCounted
## Collision lives in the same 2D space as the rendered characters. Weapon
## convex parts follow CPU-skinned mesh vertices; body capsules follow bones.
## No viewport rectangle, tile radius, cape or holstered weapon is a hitbox.

var _surfaces: Dictionary = {}
var _head_bounds: Dictionary = {}
var _rigid_surfaces: Dictionary = {}
# A/B fallback for original full synchronization; queried native bone getters
# update their dirty ancestor chains without changing pose precision or timing.
var lazy_bone_queries_enabled := true
var rigid_hull_dedup_enabled := false # Exact A/B candidate; warmed male/female timing has no clear gain.
var weapon_mesh_filter_enabled := true # Native ordered Weapon_* candidates; exact male/female A/B retains live visibility.
var gpu_skinner: RefCounted # Explicit test injection only until exactness and end-to-end gates pass.
var skinning_profile_enabled := false
var skinning_profile := {"posed_calls": 0, "posed_usec": 0, "morph_calls": 0, "morph_usec": 0,
	"rigid_surfaces": 0, "rigid_vertices": 0, "scalar_surfaces": 0, "scalar_vertices": 0,
	"scalar_usec": 0, "gpu_surfaces": 0, "gpu_vertices": 0, "gpu_fallbacks": 0,
	"projection_calls": 0, "projection_vertices": 0, "projection_usec": 0}
static var _capsule_ring: Array[Vector2] = _make_capsule_ring()
const LIMBS := [
	["J_Bip_C_Hips", "J_Bip_C_Chest", 0.16],
	["J_Bip_C_Neck", "J_Bip_C_Head", 0.13],
	["J_Bip_L_UpperArm", "J_Bip_L_LowerArm", 0.065],
	["J_Bip_L_LowerArm", "J_Bip_L_Hand", 0.055],
	["J_Bip_R_UpperArm", "J_Bip_R_LowerArm", 0.065],
	["J_Bip_R_LowerArm", "J_Bip_R_Hand", 0.055],
	["J_Bip_L_UpperLeg", "J_Bip_L_LowerLeg", 0.09],
	["J_Bip_L_LowerLeg", "J_Bip_L_Foot", 0.065],
	["J_Bip_R_UpperLeg", "J_Bip_R_LowerLeg", 0.09],
	["J_Bip_R_LowerLeg", "J_Bip_R_Foot", 0.065],
]

func project(actor: Variant, point: Vector3) -> Vector2:
	var viewport_point: Vector2 = actor.editor.camera.unproject_position(point)
	return actor.player_sprite.to_global(viewport_point - Vector2(actor.editor.preview_viewport.size) * 0.5)

func _mesh_nodes(actor: Variant, pattern: String) -> Array:
	# Only the original private Source has a fixed-hierarchy lookup owner.
	# Retain the native traversal for normal actors and every mutable editor.
	if actor.editor.has_method("_combat_mesh_nodes"):
		return actor.editor._combat_mesh_nodes(pattern)
	return actor.editor.model_root.find_children(pattern, "MeshInstance3D", true, false)

func body_shapes(actor: Variant) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if actor.editor == null or actor.editor.model_root == null:
		return result
	var skeleton := actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return result
	if not lazy_bone_queries_enabled:
		skeleton.force_update_all_bone_transforms()
	for limb: Array in LIMBS:
		var a := skeleton.find_bone(limb[0])
		var b := skeleton.find_bone(limb[1])
		if a < 0 or b < 0:
			continue
		var start := skeleton.global_transform * skeleton.get_bone_global_pose(a).origin
		var end := skeleton.global_transform * skeleton.get_bone_global_pose(b).origin
		var centre := project(actor, start)
		var radius := centre.distance_to(project(actor, start + actor.editor.camera.global_basis.x * float(limb[2])))
		result.append(capsule(centre, project(actor, end), radius))
	var head_shape := head_shape_from_mesh(actor, skeleton)
	if not head_shape.is_empty() and result.size() > 1:
		result[1] = head_shape
	return result

func head_shape_from_mesh(actor: Variant, skeleton: Skeleton3D) -> PackedVector2Array:
	var head := skeleton.find_bone("J_Bip_C_Head")
	if head < 0:
		return PackedVector2Array()
	var head_world := skeleton.global_transform * skeleton.get_bone_global_pose(head)
	for node: Node in _mesh_nodes(actor, "Face_Standard*"):
		var face := node as MeshInstance3D
		if not face.is_visible_in_tree() or face.mesh == null:
			continue
		var key := face.get_instance_id()
		if not _head_bounds.has(key):
			if _head_bounds.size() > 16:
				_head_bounds.clear()
			var vertices := posed_vertices(face, skeleton)
			if vertices.is_empty():
				continue
			var inverse := head_world.affine_inverse()
			var local_bounds := AABB(inverse * vertices[0], Vector3.ZERO)
			for vertex: Vector3 in vertices:
				local_bounds = local_bounds.expand(inverse * vertex)
			_head_bounds[key] = local_bounds
		# The head bone sits at the neck, not at the skull centre. Fit the
		# actual face mesh once; hair/helmets never enlarge this hurtbox.
		var head_bounds: AABB = _head_bounds[key]
		var points := PackedVector2Array()
		for corner in range(8):
			points.append(project(actor, head_world * head_bounds.get_endpoint(corner)))
		return Geometry2D.convex_hull(points)
	return PackedVector2Array()

static func _make_capsule_ring() -> Array[Vector2]:
	var ring: Array[Vector2] = []
	for i in range(12):
		ring.append(Vector2.from_angle(TAU * i / 12.0))
	ring.make_read_only()
	return ring

static func capsule(start: Vector2, end: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for direction: Vector2 in _capsule_ring:
		var offset := direction * radius
		points.append(start + offset)
		points.append(end + offset)
	return Geometry2D.convex_hull(points)

func weapon_shapes(actor: Variant, clip: StringName, parrying: bool = false) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if actor.editor == null or actor.editor.model_root == null:
		return result
	var skeleton := actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return result
	if not lazy_bone_queries_enabled:
		skeleton.force_update_all_bone_transforms()
	if clip == &"attack_unarmed":
		var knee := skeleton.find_bone("J_Bip_R_LowerLeg")
		var foot := skeleton.find_bone("J_Bip_R_Foot")
		if knee >= 0 and foot >= 0:
			result.append(capsule(project(actor, skeleton.global_transform * skeleton.get_bone_global_pose(knee).origin), project(actor, skeleton.global_transform * skeleton.get_bone_global_pose(foot).origin), 3.0))
		return result
	if clip in [&"attack_bow", &"attack_crossbow"]:
		return result # Projectiles, never the bow mesh, deal ranged damage.
	for node: Node in _mesh_nodes(actor, "Weapon_*" if weapon_mesh_filter_enabled else "*"):
		var part := node as MeshInstance3D
		var label := str(part.name)
		if not part.is_visible_in_tree() or not label.begins_with("Weapon_") or part.mesh == null:
			continue
		if "Holstered" in label or "Sheathed" in label or "Scabbard" in label:
			continue
		# A haft/hilt can block a blade without becoming a damaging edge.
		if not parrying and ("Grip" in label or "Handle" in label or "Guard" in label or "Shaft" in label):
			continue
		var points := _posed_points(actor, part, skeleton, true) if rigid_hull_dedup_enabled else posed_points(actor, part, skeleton)
		if points.size() >= 3:
			result.append(Geometry2D.convex_hull(points))
	return result

func shield_shapes(actor: Variant) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if actor.editor == null or actor.editor.model_root == null:
		return result
	var skeleton := actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return result
	if not lazy_bone_queries_enabled:
		skeleton.force_update_all_bone_transforms()
	for node: Node in _mesh_nodes(actor, "Shield_*"):
		var mesh := node as MeshInstance3D
		if not mesh.is_visible_in_tree() or mesh.mesh == null:
			continue
		# A visible holstered shield protects only its actual silhouette too.
		var points := _posed_points(actor, mesh, skeleton, true) if rigid_hull_dedup_enabled else posed_points(actor, mesh, skeleton)
		if points.size() >= 3:
			result.append(Geometry2D.convex_hull(points))
	return result

func armor_at(actor: Variant, point: Vector2, kind: String) -> Vector2:
	var protection := Vector2.ZERO
	if actor.editor == null or actor.editor.model_root == null:
		return protection
	var skeleton := actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return protection
	for slot: StringName in [&"helmet", &"armor", &"outfit", &"boots"]:
		var option := actor.editor.part_options.get(slot) as OptionButton
		if option == null or option.selected < 0:
			continue
		var item := StringName(str(option.get_item_metadata(option.selected)))
		if item == &"none":
			continue
		var component: Dictionary = actor.editor._component_definition(slot, item)
		var covered := false
		for prefix: String in component.get("prefixes", []):
			for node: Node in _mesh_nodes(actor, prefix + "*"):
				var part := node as MeshInstance3D
				if part.is_visible_in_tree() and part.mesh != null and mesh_covers_point(actor, part, skeleton, point):
					covered = true
					break
			if covered:
				break
		if covered:
			var profile := SiteCombatRules.armor_profile(str(item))
			protection += Vector2(float(profile.get(kind, 0.0)), float(profile.cushion))
	return protection

func pose_snapshot(actor: TerrainTestCharacter, clip: StringName) -> Dictionary:
	# Offline only. Keep the exact projected triangles: convex armor hulls would
	# fill exposed gaps and grant protection the live character does not have.
	var snapshot := {"body": body_shapes(actor), "weapon": weapon_shapes(actor, clip), "parry": weapon_shapes(actor, clip, true),
		"shield": shield_shapes(actor), "armor": []}
	var skeleton := actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	for slot: StringName in [&"helmet", &"armor", &"outfit", &"boots"]:
		var option := actor.editor.part_options[slot] as OptionButton
		var item := StringName(str(option.get_item_metadata(option.selected)))
		if item == &"none":
			continue
		var surfaces: Array[Dictionary] = []
		var component: Dictionary = actor.editor._component_definition(slot, item)
		for prefix: String in component.get("prefixes", []):
			for node: Node in _mesh_nodes(actor, prefix + "*"):
				var part := node as MeshInstance3D
				if not part.is_visible_in_tree() or part.mesh == null:
					continue
				var vertices := posed_points(actor, part, skeleton)
				var offset := 0
				for surface in range(part.mesh.get_surface_count()):
					var arrays := part.mesh.surface_get_arrays(surface)
					var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
					var count := indices.size() if not indices.is_empty() else positions.size()
					if count > 0:
						surfaces.append({"vertices": vertices.slice(offset, offset + positions.size()), "indices": indices})
					offset += positions.size()
		snapshot.armor.append({"item": str(item), "surfaces": surfaces})
	return snapshot

static func snapshot_armor_at(snapshot: Dictionary, point: Vector2, kind: String) -> Vector2:
	var protection := Vector2.ZERO
	for item: Dictionary in snapshot.get("armor", []):
		var covered := false
		for surface: Dictionary in item.surfaces:
			var vertices: PackedVector2Array = surface.vertices
			var indices: PackedInt32Array = surface.indices
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for index in range(0, count - 2, 3):
				var triangle := PackedVector2Array()
				for corner in range(3):
					triangle.append(vertices[indices[index + corner] if not indices.is_empty() else index + corner])
				if Geometry2D.is_point_in_polygon(point, triangle):
					covered = true
					break
			if covered:
				break
		if covered:
			var profile := SiteCombatRules.armor_profile(str(item.item))
			protection += Vector2(float(profile.get(kind, 0.0)), float(profile.cushion))
	return protection

func mesh_covers_point(actor: Variant, part: MeshInstance3D, skeleton: Skeleton3D, point: Vector2) -> bool:
	var vertices := posed_points(actor, part, skeleton)
	var vertex_offset := 0
	var polygon := PackedVector2Array()
	polygon.resize(3)
	for surface in range(part.mesh.get_surface_count()):
		var key := "%d:%d" % [part.mesh.get_instance_id(), surface]
		var arrays: Array = _surfaces[key] if _surfaces.has(key) else part.mesh.surface_get_arrays(surface)
		var surface_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else surface_vertices.size()
		for triangle in range(0, count - 2, 3):
			for corner in range(3):
				polygon[corner] = vertices[vertex_offset + (indices[triangle + corner] if not indices.is_empty() else triangle + corner)]
			if Geometry2D.is_point_in_polygon(point, polygon):
				return true
		vertex_offset += surface_vertices.size()
	return false

static func prepare_sweeps(previous: Array[PackedVector2Array], current: Array[PackedVector2Array]) -> Array[Dictionary]:
	# Private to one immutable previous/current collection, never a cross-step cache.
	# The original eight binary refinements visit at most 255 distinct midpoints.
	var result: Array[Dictionary] = []
	for shape_index in range(current.size()):
		var shape := current[shape_index]
		var before := previous[shape_index] if shape_index < previous.size() else shape
		var full_sweep := before.duplicate()
		full_sweep.append_array(shape)
		full_sweep = Geometry2D.convex_hull(full_sweep)
		result.append({"before": before, "shape": shape, "full_sweep": full_sweep,
			"bounds": polygon_bounds(full_sweep).grow(0.001), "partials": {}})
	return result

static func contact(previous: Array[PackedVector2Array], current: Array[PackedVector2Array], bodies: Array[PackedVector2Array], prepared: Array = []) -> Dictionary:
	if bodies.is_empty() or current.is_empty():
		return {}
	var sweeps: Array = prepare_sweeps(previous, current) if prepared.is_empty() else prepared
	var best: Dictionary = {}
	for shape_index in range(current.size()):
		var entry: Dictionary = sweeps[shape_index]
		var shape: PackedVector2Array = entry.shape
		var before: PackedVector2Array = entry.before
		var full_sweep: PackedVector2Array = entry.full_sweep
		# Conservative rejection only. Keep touching/rounding boundaries in the
		# original exact intersection path, including the entire motion sweep.
		var sweep_bounds: Rect2 = entry.bounds
		var partials: Dictionary = entry.partials
		for body_index in range(bodies.size()):
			if not sweep_bounds.intersects(polygon_bounds(bodies[body_index]), true):
				continue
			var intersections := Geometry2D.intersect_polygons(full_sweep, bodies[body_index])
			if intersections.is_empty():
				continue
			var fraction := 0.0
			# Recover sub-sample contact order, not array/scene iteration order.
			if before.size() == shape.size() and Geometry2D.intersect_polygons(before, bodies[body_index]).is_empty():
				var low := 0.0
				var high := 1.0
				for refinement in range(8):
					var middle := (low + high) * 0.5
					if not partials.has(middle):
						var sweep := before.duplicate()
						for vertex in range(shape.size()):
							sweep.append(before[vertex].lerp(shape[vertex], middle))
						partials[middle] = Geometry2D.convex_hull(sweep)
					var partial := Geometry2D.intersect_polygons(partials[middle], bodies[body_index])
					if partial.is_empty():
						low = middle
					else:
						high = middle
						intersections = partial
				fraction = high
			if not best.is_empty() and fraction >= float(best.fraction):
				continue
			var point := Vector2.ZERO
			for vertex: Vector2 in intersections[0]:
				point += vertex
			point /= intersections[0].size()
			best = {"fraction": fraction, "body": body_index, "point": point}
			if fraction == 0.0:
				return best # Later equal fractions were already rejected above.
	return best

static func polygon_bounds(shape: PackedVector2Array) -> Rect2:
	var bounds := Rect2()
	if not shape.is_empty():
		bounds.position = shape[0]
		for vertex: Vector2 in shape:
			bounds = bounds.expand(vertex)
	return bounds

static func shifted(shapes: Array, offset: Vector2) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for shape: PackedVector2Array in shapes:
		result.append(Transform2D(0.0, offset) * shape)
	return result

static func person_contact(previous: Array[PackedVector2Array], current: Array[PackedVector2Array], bodies: Array[PackedVector2Array], shields: Array[PackedVector2Array], prepared: Array = []) -> Dictionary:
	if current.is_empty() or (bodies.is_empty() and shields.is_empty()):
		return {}
	var sweeps: Array = prepare_sweeps(previous, current) if prepared.is_empty() else prepared
	var body := contact(previous, current, bodies, sweeps)
	var shield := contact(previous, current, shields, sweeps)
	var blocked := not shield.is_empty() and (body.is_empty() or float(shield.fraction) <= float(body.fraction))
	var hit := shield if blocked else body
	if not hit.is_empty():
		hit["shield"] = blocked
		hit["block_kind"] = "shield" if blocked else "body"
	return hit

func posed_points(actor: Variant, part: MeshInstance3D, skeleton: Skeleton3D) -> PackedVector2Array:
	# Preserve this three-argument public/override contract and indexed output.
	return _posed_points(actor, part, skeleton, false)

func _posed_points(actor: Variant, part: MeshInstance3D, skeleton: Skeleton3D, hull_only: bool) -> PackedVector2Array:
	var points := PackedVector2Array()
	var vertices := posed_vertices(part, skeleton, true, hull_only)
	var projection_started := Time.get_ticks_usec() if skinning_profile_enabled else 0
	if actor.editor.camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		# Orthographic projection plus Sprite2D transforms is affine. Apply it
		# natively to the packed vertices instead of querying both nodes per point.
		var camera: Camera3D = actor.editor.camera
		var origin := camera.unproject_position(Vector3.ZERO)
		var axes: Array[Vector3] = []
		for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			var projected := camera.unproject_position(axis) - origin
			axes.append(Vector3(projected.x, projected.y, 0.0))
		origin -= Vector2(actor.editor.preview_viewport.size) * 0.5
		vertices = Transform3D(Basis(axes[0], axes[1], axes[2]), Vector3(origin.x, origin.y, 0.0)) * vertices
		for vertex: Vector3 in vertices:
			points.append(Vector2(vertex.x, vertex.y))
		points = actor.player_sprite.global_transform * points
	else:
		for vertex: Vector3 in vertices:
			points.append(project(actor, vertex))
	if skinning_profile_enabled:
		skinning_profile.projection_calls += 1
		skinning_profile.projection_vertices += vertices.size()
		skinning_profile.projection_usec += Time.get_ticks_usec() - projection_started
	if hull_only:
		for point: Vector2 in points:
			# Hull sort compares numeric coordinates, not zero sign bits. Removing
			# duplicates must not change a +/-0 tie representative. Also keep the
			# hull's duplicate cross products finite; this is fallback, not a clamp.
			if not point.is_finite() or point.x == 0.0 or point.y == 0.0 or absf(point.x) > 100000000.0 or absf(point.y) > 100000000.0:
				return _posed_points(actor, part, skeleton, false)
	return points

func posed_vertices(part: MeshInstance3D, skeleton: Skeleton3D, native_rigid: bool = true, hull_only: bool = false) -> PackedVector3Array:
	var posed_started := Time.get_ticks_usec() if skinning_profile_enabled else 0
	var points := PackedVector3Array()
	# Use the engine's own morph mixer before skinning. Armor corrections must
	# affect both the visible surface and its projected protection triangles.
	var morphed: ArrayMesh
	for shape in part.get_blend_shape_count():
		if absf(part.get_blend_shape_value(shape)) > 0.0001:
			var morph_started := Time.get_ticks_usec() if skinning_profile_enabled else 0
			morphed = part.bake_mesh_from_current_blend_shape_mix()
			if skinning_profile_enabled:
				skinning_profile.morph_calls += 1
				skinning_profile.morph_usec += Time.get_ticks_usec() - morph_started
			break
	var palette: Array[Transform3D] = []
	# Keep the complete original scalar/morph path. A rigid native surface only
	# needs its one original binding; do not prepare unused bones for that case.
	if part.skin != null and (not native_rigid or morphed != null):
		for i in range(part.skin.get_bind_count()):
			var bone := part.skin.get_bind_bone(i)
			if bone < 0:
				bone = skeleton.find_bone(part.skin.get_bind_name(i))
			palette.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * part.skin.get_bind_pose(i) if bone >= 0 else part.global_transform)
	for surface in range(part.mesh.get_surface_count()):
		var key := "%d:%d" % [part.mesh.get_instance_id(), surface]
		if not _surfaces.has(key):
			# Cache arrays only while the selected model exists; resources can be
			# swapped in the editor. Bounded two-character LAB, not crowd rendering.
			if _surfaces.size() > 128:
				_surfaces.clear()
			_surfaces[key] = part.mesh.surface_get_arrays(surface)
		var arrays: Array = _surfaces[key]
		if morphed != null:
			arrays = morphed.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var influences := int(float(bones.size()) / maxf(1.0, vertices.size()))
		if native_rigid and morphed == null:
			if part.skin == null or part.skin.get_bind_count() == 0 or influences == 0:
				if skinning_profile_enabled:
					skinning_profile.rigid_surfaces += 1
					skinning_profile.rigid_vertices += vertices.size()
				points.append_array(part.global_transform * vertices)
				continue
			if not _rigid_surfaces.has(key):
				var rigid_binding := -1
				for vertex in range(vertices.size()):
					var assigned := -1
					for slot in range(influences):
						var influence := vertex * influences + slot
						if weights[influence] == 0.0:
							continue
						if weights[influence] != 1.0 or assigned >= 0:
							assigned = -2
							break
						assigned = bones[influence]
					if assigned < 0 or (rigid_binding >= 0 and assigned != rigid_binding):
						rigid_binding = -2
						break
					rigid_binding = assigned
				if _rigid_surfaces.size() > 128:
					_rigid_surfaces.clear()
				_rigid_surfaces[key] = {"binding": rigid_binding}
			var rigid_surface: Dictionary = _rigid_surfaces[key]
			var rigid: int = rigid_surface.binding
			if rigid >= 0:
				if skinning_profile_enabled:
					skinning_profile.rigid_surfaces += 1
					skinning_profile.rigid_vertices += vertices.size()
				if hull_only and rigid_hull_dedup_enabled and part.get_blend_shape_count() == 0:
					if not rigid_surface.has("hull_vertices"):
						rigid_surface.hull_vertices = _unique_rigid_vertices(vertices)
					vertices = rigid_surface.hull_vertices
				var binding: Transform3D
				if palette.is_empty():
					var bone := part.skin.get_bind_bone(rigid)
					if bone < 0:
						bone = skeleton.find_bone(part.skin.get_bind_name(rigid))
					binding = skeleton.global_transform * skeleton.get_bone_global_pose(bone) * part.skin.get_bind_pose(rigid) if bone >= 0 else part.global_transform
				else:
					binding = palette[rigid]
				points.append_array(binding * vertices)
				continue
		# Mixed/nonrigid surfaces retain the original full palette and per-vertex
		# accumulation. Build it once, then reuse it for this part's later surfaces.
		if palette.is_empty() and part.skin != null:
			for i in range(part.skin.get_bind_count()):
				var bone := part.skin.get_bind_bone(i)
				if bone < 0:
					bone = skeleton.find_bone(part.skin.get_bind_name(i))
				palette.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * part.skin.get_bind_pose(i) if bone >= 0 else part.global_transform)
		if gpu_skinner != null and not palette.is_empty() and influences > 0:
			if gpu_skinner.register_surface(key, vertices, bones, weights):
				var gpu_points: PackedVector3Array = gpu_skinner.skin_batch(key, [palette])
				if gpu_points.size() == vertices.size():
					if skinning_profile_enabled:
						skinning_profile.gpu_surfaces += 1
						skinning_profile.gpu_vertices += gpu_points.size()
					points.append_array(gpu_points)
					continue
			if skinning_profile_enabled:
				skinning_profile.gpu_fallbacks += 1
		var scalar_started := Time.get_ticks_usec() if skinning_profile_enabled else 0
		for v in range(vertices.size()):
			var point := part.global_transform * vertices[v]
			if not palette.is_empty() and influences > 0:
				point = Vector3.ZERO
				for slot in range(influences):
					var index := v * influences + slot
					point += (palette[bones[index]] * vertices[v]) * weights[index]
			points.append(point)
		if skinning_profile_enabled:
			skinning_profile.scalar_surfaces += 1
			skinning_profile.scalar_vertices += vertices.size()
			skinning_profile.scalar_usec += Time.get_ticks_usec() - scalar_started
	if skinning_profile_enabled:
		skinning_profile.posed_calls += 1
		skinning_profile.posed_usec += Time.get_ticks_usec() - posed_started
	return points

static func _unique_rigid_vertices(vertices: PackedVector3Array) -> PackedVector3Array:
	# Called once inside the existing per-mesh/surface rigid cache. The binding
	# and exact weight-one test already passed; never merge across surfaces.
	var seen := {}
	var unique := PackedVector3Array()
	for vertex: Vector3 in vertices:
		if not vertex.is_finite():
			return vertices
		var bits := var_to_bytes(vertex) # Preserve +/-0; Vector3 has no NodePath padding.
		if not seen.has(bits):
			seen[bits] = true
			unique.append(vertex)
	# Preserve the original >=3 input gate and degenerate closed-hull length.
	return vertices if unique.size() < 3 else unique

static func attack_aim_point(bodies: Array, fallback: Vector2, shoulder: Vector2 = Vector2.INF, head: bool = false) -> Vector2:
	if bodies.is_empty():
		return fallback
	var selected: PackedVector2Array = bodies[1] if head and bodies.size() > 1 else bodies[0]
	var aim := Vector2.ZERO
	for point: Vector2 in selected:
		aim += point
	aim /= selected.size()
	if shoulder.is_finite():
		var nearest := INF
		for body: PackedVector2Array in bodies:
			var centre := Vector2.ZERO
			for point: Vector2 in body:
				centre += point
			centre /= body.size()
			for point: Vector2 in body:
				var inset := point.move_toward(centre, 0.5)
				if shoulder.distance_squared_to(inset) < nearest:
					nearest = shoulder.distance_squared_to(inset)
					aim = inset
	return aim

func aim_weapon_attack(actor: Variant, aim_point: Vector2, weight: float) -> void:
	if weight <= 0.0:
		return
	var skeleton := actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var arm := skeleton.find_bone("J_Bip_R_UpperArm")
	var hand := skeleton.find_bone("J_Bip_R_Hand")
	if arm < 0 or hand < 0:
		return
	skeleton.force_update_all_bone_transforms()
	var arm_world := skeleton.global_transform * skeleton.get_bone_global_pose(arm)
	var hand_world := skeleton.global_transform * skeleton.get_bone_global_pose(hand).origin
	var tip := hand_world
	var furthest := 0.0
	var spear := false
	for node: Node in actor.editor.model_root.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		var label := str(part.name)
		if not part.is_visible_in_tree() or not label.begins_with("Weapon_") or part.mesh == null:
			continue
		if not ("Blade" in label or "Head" in label or "Tip" in label) or "Holstered" in label or "Sheathed" in label:
			continue
		for vertex: Vector3 in posed_vertices(part, skeleton):
			var distance := vertex.distance_squared_to(hand_world)
			if distance > furthest:
				furthest = distance
				tip = vertex
				spear = label.begins_with("Weapon_Spear_01_")
	if furthest <= 0.0:
		return
	# Solve the hand/elbow/shoulder chain toward a fixed attack aim point.
	# Root, saddle, limb lengths and weapon geometry are never translated/scaled.
	var camera: Camera3D = actor.editor.camera
	var pixel: Vector2 = actor.player_sprite.to_local(aim_point) + Vector2(actor.editor.preview_viewport.size) * 0.5
	var ray_start := camera.project_ray_origin(pixel)
	var ray := camera.project_ray_normal(pixel)
	var destination := ray_start + ray * (arm_world.origin - ray_start).dot(ray)
	if spear and not actor.editor.is_mounted:
		# A long rigid shaft cannot converge to the shoulder-depth target without
		# folding the chain. Intersect the aim ray with the tip's reach sphere at
		# the authored hand, choosing the solution nearest its authored direction.
		# This changes only wrist orientation, never the grip, length or hit mesh.
		var offset := ray_start - hand_world
		var along := offset.dot(ray)
		var discriminant := along * along - offset.length_squared() + furthest
		if discriminant >= 0.0:
			var near_tip := ray_start + ray * (-along - sqrt(discriminant))
			var far_tip := ray_start + ray * (-along + sqrt(discriminant))
			destination = near_tip if near_tip.distance_squared_to(tip) < far_tip.distance_squared_to(tip) else far_tip
		else:
			# Unreachable targets stay misses; the real shaft is never extended.
			destination = ray_start - ray * along
		var from := tip - hand_world
		var to := destination - hand_world
		if from.length_squared() < .00001 or to.length_squared() < .00001:
			return
		var wrist_world := skeleton.global_transform * skeleton.get_bone_global_pose(hand)
		var desired := Transform3D(Basis(Quaternion(from.normalized(), to.normalized())) * wrist_world.basis, hand_world)
		var parent_world := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.get_bone_parent(hand))
		var rotation := (parent_world.affine_inverse() * desired).basis.get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(hand, skeleton.get_bone_pose_rotation(hand).slerp(rotation, weight))
		skeleton.force_update_all_bone_transforms()
		return
	var hand_transform := skeleton.global_transform * skeleton.get_bone_global_pose(hand)
	var tip_in_hand := hand_transform.affine_inverse() * tip
	var elbow := skeleton.find_bone("J_Bip_R_LowerArm")
	if elbow < 0:
		return
	var chain: Array[int] = [hand, elbow, arm]
	if actor.editor.is_mounted:
		# A rider must lean from the waist to strike a standing target below.
		# Keep hips/legs attached to the saddle and preserve all bone lengths.
		var ancestor := skeleton.get_bone_parent(arm)
		while ancestor >= 0 and skeleton.get_bone_name(ancestor) != "J_Bip_C_Hips":
			chain.append(ancestor)
			ancestor = skeleton.get_bone_parent(ancestor)
	var original: Array[Quaternion] = []
	for joint: int in chain:
		original.append(skeleton.get_bone_pose_rotation(joint))
	for iteration in range(64):
		for joint: int in chain:
			var joint_world := skeleton.global_transform * skeleton.get_bone_global_pose(joint)
			var current_endpoint := skeleton.global_transform * skeleton.get_bone_global_pose(hand) * tip_in_hand
			var from := current_endpoint - joint_world.origin
			var to := destination - joint_world.origin
			if from.length_squared() < 0.00001 or to.length_squared() < 0.00001:
				continue
			var turn := Quaternion(from.normalized(), to.normalized())
			var desired := Transform3D(Basis(turn) * joint_world.basis, joint_world.origin)
			var parent_world := skeleton.global_transform
			var parent := skeleton.get_bone_parent(joint)
			if parent >= 0:
				parent_world *= skeleton.get_bone_global_pose(parent)
			# Godot 4 bone pose is already parent-local (including rest).
			# Removing rest again twists imported joints and breaks convergence.
			var pose := parent_world.affine_inverse() * desired
			skeleton.set_bone_pose_rotation(joint, pose.basis.get_rotation_quaternion())
			# The next global-pose getter updates the dirty ancestor chain itself.
			# Publish the finished pose once below, not after every IK joint.
		var final_endpoint := skeleton.global_transform * skeleton.get_bone_global_pose(hand) * tip_in_hand
		if final_endpoint.distance_squared_to(destination) < 0.0001:
			break
	for i in range(chain.size()):
		var solved := skeleton.get_bone_pose_rotation(chain[i])
		skeleton.set_bone_pose_rotation(chain[i], original[i].slerp(solved, weight))
	skeleton.force_update_all_bone_transforms()

static func swept_contact(previous: Array[PackedVector2Array], current: Array[PackedVector2Array], bodies: Array[PackedVector2Array]) -> bool:
	for i in range(current.size()):
		var sweep := current[i].duplicate()
		if i < previous.size():
			sweep.append_array(previous[i])
		sweep = Geometry2D.convex_hull(sweep)
		for body: PackedVector2Array in bodies:
			if not Geometry2D.intersect_polygons(sweep, body).is_empty():
				return true
	return false

# Candidate switches: strict ordering is an intentional correction of the old
# non-transitive approximate tie rule. Early culling is valid only with it.
static var strict_contact_order_enabled := false
static var melee_hit_cull_enabled := false

static func contact_precedes(a: Dictionary, b: Dictionary) -> bool:
	var a_fraction := float(a.fraction)
	var b_fraction := float(b.fraction)
	var a_distance := float(a.distance)
	var b_distance := float(b.distance)
	if not strict_contact_order_enabled:
		if not is_equal_approx(a_fraction, b_fraction):
			return a_fraction < b_fraction
		if not is_equal_approx(a_distance, b_distance):
			return a_distance < b_distance
	else:
		# Valid collision values retain their exact native numeric order. NaN
		# cannot originate in a valid projection; keep malformed contacts rather
		# than dropping a target, deterministically placing NaN after numbers.
		if is_nan(a_fraction) != is_nan(b_fraction):
			return not is_nan(a_fraction)
		if not is_nan(a_fraction) and a_fraction != b_fraction:
			return a_fraction < b_fraction
		if is_nan(a_distance) != is_nan(b_distance):
			return not is_nan(a_distance)
		if not is_nan(a_distance) and a_distance != b_distance:
			return a_distance < b_distance
	return int(a.identity) < int(b.identity)
