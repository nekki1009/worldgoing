extends RefCounted
## Pure, once-per-original-Source-lifetime analysis; owns no rig/person/cache.
## Continuous native curves, original skin vertices, not atlas/sample maxima.
## Includes only unaimed native attacks; caller excludes IK and all guard/parry.
## Unsupported conditions retain the existing 256-pixel broad phase.

const FALLBACK := 256.0
const NONATTACK: Array[StringName] = [&"idle", &"walk", &"run", &"hit", &"hit_back", &"knockback",
	&"down", &"unconscious", &"get_up", &"rescue", &"reload_bow", &"reload_crossbow"]
const NATIVE_ATTACKS: Array[StringName] = [&"walk_slash", &"attack_spear", &"attack_axe", &"attack_hammer",
	&"attack_dagger", &"attack_unarmed", &"attack_bow", &"attack_crossbow"]
const CURVES: Array[StringName] = [&"idle", &"walk", &"run", &"walk_slash", &"attack_spear", &"attack_axe",
	&"attack_hammer", &"attack_dagger", &"attack_unarmed", &"attack_bow", &"attack_crossbow", &"guard",
	&"guard_weapon_raise", &"guard_weapon_lower", &"guard_weapon_break", &"guard_polearm_raise", &"guard_polearm_lower",
	&"guard_polearm_break", &"guard_raise", &"guard_lower", &"guard_break", &"hit", &"hit_back", &"knockback", &"down",
	&"unconscious", &"get_up", &"rescue", &"reload_bow", &"reload_crossbow", &"guard_weapon", &"guard_polearm"]

static func build(source: Variant) -> Dictionary:
	var started := Time.get_ticks_usec()
	if source == null or not is_instance_valid(source.editor) or not is_instance_valid(source.skeleton) or not is_instance_valid(source.sprite):
		return _unsupported("MISSING_ORIGINAL_SOURCE")
	var editor: HumanCharacter3DEditor = source.editor
	var skeleton: Skeleton3D = source.skeleton
	var sprite: Sprite2D = source.sprite
	if not editor.has_method("enable_manual_query_playback") or not bool(editor.get("manual_query_playback_enabled")):
		return _unsupported("NOT_PRIVATE_QUERY_OWNER")
	if int(source._baseline.get("body", -1)) != 0 or bool(source._baseline.get("mounted", true)) or editor.is_mounted:
		return _unsupported("NOT_ORIGINAL_ORDINARY_FOOT_MODEL")
	var modifiers: Array[Dictionary] = []
	var unsupported_modifier := false
	var physical_bones := skeleton.find_children("*", "PhysicalBone3D", true, false).size()
	for modifier: Node in skeleton.find_children("*", "SkeletonModifier3D", true, false):
		# Skeleton3D creates an internal native compatibility simulator. Its
		# process loop only writes a skeleton bone if a physical bone exists.
		# Do not disable/remove that original Node or admit general modifiers.
		var simulator := modifier as PhysicalBoneSimulator3D
		var empty_native_simulator: bool = simulator != null and modifier.get_class() == "PhysicalBoneSimulator3D" and modifier.get_script() == null and modifier.get_parent() == skeleton and modifier.get_child_count(true) == 0 and physical_bones == 0 and not simulator.is_simulating_physics() and modifier.get_signal_connection_list(&"modification_processed").is_empty()
		unsupported_modifier = unsupported_modifier or not empty_native_simulator
		modifiers.append({"path": str(skeleton.get_path_to(modifier)), "class": modifier.get_class(),
			"active": modifier.get("active"), "influence": modifier.get("influence"),
			"empty_native_simulator": empty_native_simulator, "children": modifier.get_child_count(true),
			"simulating": simulator.is_simulating_physics() if simulator != null else false})
	if skeleton.get_motion_scale() != 1.0 or skeleton.show_rest_only or unsupported_modifier:
		return _unsupported("SKELETON_MODIFIER_OR_MOTION_SCALE", {"motion_scale": skeleton.get_motion_scale(),
			"show_rest_only": skeleton.show_rest_only, "physical_bones": physical_bones, "modifiers": modifiers})
	if not skeleton.global_transform.is_finite() or not editor.preview_pivot.transform.is_finite() or not sprite.global_transform.is_finite():
		return _unsupported("NONFINITE_MODEL_OR_SPRITE_TRANSFORM")
	if skeleton.global_position != Vector3.ZERO or editor.preview_pivot.position != Vector3.ZERO or editor.preview_pivot.scale != Vector3.ONE:
		return _unsupported("MODEL_ROOT_TRANSFORM")
	var world_gain := _basis_norm(skeleton.global_basis)
	if world_gain > 1.001 or _basis_minimum(skeleton.global_basis) < 0.999:
		return _unsupported("MODEL_ROOT_SCALE")
	var player: AnimationPlayer = editor.animation_player
	if not is_instance_valid(player) or player.get_script() != null or player.get_default_blend_time() != 0.0 or not player.get("blend_times").is_empty() or not player.get_queue().is_empty() or not player.root_motion_track.is_empty():
		return _unsupported("NATIVE_SINGLE_CLIP_CONTRACT")
	var camera: Camera3D = editor.camera
	if not is_instance_valid(camera) or camera.projection != Camera3D.PROJECTION_ORTHOGONAL or editor.preview_viewport.size != Vector2i(1280, 1536):
		return _unsupported("ORTHOGRAPHIC_VIEWPORT_CONTRACT")
	if not camera.global_transform.is_finite() or not is_finite(camera.size) or not is_finite(camera.h_offset) or not is_finite(camera.v_offset):
		return _unsupported("NONFINITE_CAMERA")
	if camera.keep_aspect != Camera3D.KEEP_HEIGHT or camera.h_offset != 0.0 or camera.v_offset != 0.0 or camera.size < 7.0 or camera.size > 9.0 or _norm(camera.global_position) > 6.0 or _basis_norm(camera.global_basis) > 1.001 or _basis_minimum(camera.global_basis) < 0.999:
		return _unsupported("FOOT_CAMERA_CONTRACT")
	if _norm2(sprite.global_transform.x) > 0.2 or _norm2(sprite.global_transform.y) > 0.2 or _norm2(sprite.global_position) > 64.0 or sprite.global_transform.x.y != 0.0 or sprite.global_transform.y.x != 0.0:
		return _unsupported("MAP_SPRITE_CONTRACT")
	var count := skeleton.get_bone_count()
	if count < 1 or count > 128:
		return _unsupported("BONE_COUNT")
	var parents: Array[int] = []
	var translations: Array[float] = []
	var scales: Array[float] = []
	for index in range(count):
		var parent := skeleton.get_bone_parent(index)
		var rest := skeleton.get_bone_rest(index)
		if parent < -1 or parent >= count or parent == index or not rest.is_finite():
			return _unsupported("BONE_REST_OR_PARENT")
		# No external global-pose override belongs to this private owner. Reject
		# a retained nonidentity override even if its deprecated amount is zero.
		if skeleton.get_bone_global_pose_override(index) != Transform3D.IDENTITY:
			return _unsupported("GLOBAL_BONE_OVERRIDE")
		for axis in range(3):
			var length := _norm(rest.basis[axis])
			if length < 0.999 or length > 1.001:
				return _unsupported("REST_SCALE_ENVELOPE")
		parents.append(parent)
		translations.append(_norm(rest.origin))
		scales.append(_basis_norm(rest.basis))
	var root: Node = player.get_node_or_null(player.root_node)
	if root == null:
		return _unsupported("ANIMATION_ROOT")
	# Optional centered enclosure. Keep the old proof/result even if any of
	# these stronger conditions fail; the Hips itself is NOT a fixed point.
	var hips := skeleton.find_bone("J_Bip_C_Hips")
	var root_bone := skeleton.find_bone("Root")
	var centered := skeleton.global_basis.y == Vector3.UP and skeleton.global_basis.x.y == 0.0 and skeleton.global_basis.z.y == 0.0
	var centered_reason := "READY" if centered else "NOT_PURE_WORLD_YAW"
	var root_gain := 0.0
	var root_tilt := 0.0
	if centered:
		centered = hips >= 0 and root_bone >= 0 and parents[hips] == root_bone and parents[root_bone] == -1 and skeleton.is_bone_enabled(hips) and skeleton.is_bone_enabled(root_bone)
		if centered:
			var rest := skeleton.get_bone_rest(root_bone)
			var actual := skeleton.get_bone_pose(root_bone)
			# Original reset_bone_poses reconstructs Basis from these exact native
			# rest fields. Use that actual constant Basis, not rest == identity.
			centered = rest.origin == Vector3.ZERO and actual.is_finite() and actual.origin == Vector3.ZERO and skeleton.get_bone_pose_rotation(root_bone) == rest.basis.get_rotation_quaternion() and skeleton.get_bone_pose_scale(root_bone) == rest.basis.get_scale()
			if centered:
				root_gain = _basis_norm(actual.basis)
				var squared := 0.0
				for column in range(3):
					for row in range(3):
						var difference := float(actual.basis[column][row]) - (1.0 if row == column else 0.0)
						squared += difference * difference
				root_tilt = sqrt(squared) + 1e-10 # Frobenius >= operator norm of R-I.
				centered = root_gain <= 1.001 and root_tilt <= 0.02
		if not centered:
			centered_reason = "ROOT_RECONSTRUCTION_OR_ANCESTRY"
	var hip_curves: Dictionary = {}
	var position_keys := 0
	var maximum_position_extrapolation := 0.0
	for clip: StringName in CURVES:
		if not player.has_animation(clip):
			return _unsupported("MISSING_NATIVE_CLIP:" + str(clip))
		var animation := player.get_animation(clip)
		if not is_finite(animation.length) or animation.length <= 0.0:
			return _unsupported("NATIVE_ANIMATION_LENGTH")
		if not player.animation_get_next(clip).is_empty():
			return _unsupported("NEXT_NATIVE_CLIP")
		hip_curves[clip] = {"track": -1, "extrapolation": 0.0}
		var seen := {}
		for track in range(animation.get_track_count()):
			var kind := animation.track_get_type(track)
			var path := animation.track_get_path(track)
			if path.is_absolute():
				return _unsupported("ABSOLUTE_NATIVE_TRACK")
			var node: Node = root.get_node_or_null(NodePath(path.get_concatenated_names()))
			if kind == Animation.TYPE_BLEND_SHAPE:
				# Original armor/hair/cloth morph tracks remain untouched. Neither
				# a bow string nor any other weapon participates in this bound.
				if not node is MeshInstance3D or path.get_subname_count() != 1 or str(node.name).begins_with("Face_Standard") or str(node.name).begins_with("Shield_"):
					return _unsupported("COLLIDER_OR_UNKNOWN_MORPH")
				continue
			if kind not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D] or node != skeleton or path.get_subname_count() != 1 or animation.track_is_compressed(track) or animation.track_get_interpolation_type(track) not in [Animation.INTERPOLATION_LINEAR, Animation.INTERPOLATION_NEAREST]:
				return _unsupported("UNPROVEN_NATIVE_TRACK")
			var bone := skeleton.find_bone(path.get_subname(0))
			var key := [bone, kind]
			if bone < 0 or seen.has(key):
				return _unsupported("DUPLICATE_OR_MISSING_BONE_TRACK")
			if bone == root_bone:
				centered = false # Even a disabled Root track is outside this proof.
				centered_reason = "ROOT_HAS_NATIVE_TRACK"
			seen[key] = true
			var key_count := animation.track_get_key_count(track)
			var match_time := 1e-5 * maxf(1.0, animation.length)
			if kind == Animation.TYPE_POSITION_3D and (key_count < 1 or (key_count > 1 and (animation.track_get_key_time(track, 0) != 0.0 or animation.track_get_key_time(track, key_count - 1) != animation.length))):
				return _unsupported("NATIVE_POSITION_TIME_ENVELOPE")
			var previous_time := -INF
			var previous_position := Vector3.ZERO
			var position_norm := 0.0
			var position_slope := 0.0
			for key_index in range(key_count):
				var time := animation.track_get_key_time(track, key_index)
				if not is_finite(time) or time < 0.0 or time > animation.length or time < previous_time or animation.track_get_key_transition(track, key_index) != 1.0:
					return _unsupported("NATIVE_KEY_TIME_OR_TRANSITION")
				var value: Variant = animation.track_get_key_value(track, key_index)
				if kind == Animation.TYPE_POSITION_3D:
					if not value is Vector3 or not value.is_finite():
						return _unsupported("POSITION_KEY")
					if key_index > 0:
						var delta := time - previous_time
						if delta <= 0.0 or match_time / delta > 0.01:
							return _unsupported("NATIVE_POSITION_TIME_ENVELOPE")
						position_slope = maxf(position_slope, _distance(value, previous_position) / delta)
					position_norm = maxf(position_norm, _norm(value))
					previous_position = value
					position_keys += 1
				elif not value is Quaternion or not value.is_finite() or absf(float(value.length_squared()) - 1.0) > 0.001:
					return _unsupported("ROTATION_KEY")
				previous_time = time
			if kind == Animation.TYPE_POSITION_3D:
				# Native _find matches time approximately; c=from/delta is not
				# clamped. Include the tiny extrapolated segment, not just keys.
				# Complete 0..length endpoints make the loop seam delta exactly 0.
				var extrapolation := 2.0 * match_time * position_slope
				maximum_position_extrapolation = maxf(maximum_position_extrapolation, extrapolation)
				translations[bone] = maxf(translations[bone], position_norm + extrapolation)
				if bone == hips and animation.track_is_enabled(track):
					hip_curves[clip] = {"track": track, "extrapolation": extrapolation}
	var radii: Array[float] = []
	var gains: Array[float] = []
	var depths: Array[int] = []
	radii.resize(count)
	gains.resize(count)
	depths.resize(count)
	for index in range(count):
		if translations[index] > 1.1 or not _chain(index, parents, translations, scales, radii, gains, depths) or depths[index] + 1 > 16 or radii[index] > 3.0 or gains[index] * world_gain > 1.02:
			return _unsupported("CHAIN_NUMERIC_ENVELOPE")
	var head := skeleton.find_bone("J_Bip_C_Head")
	if head < 0:
		return _unsupported("HEAD_BONE")
	var relative_radii := radii.duplicate()
	var relative_gains := gains.duplicate()
	var relative_depths := depths.duplicate()
	relative_depths.fill(0)
	relative_depths[head] = 1
	relative_radii[head] = 0.0
	relative_gains[head] = 1.0
	var hip_radii: Array[float] = []
	var hip_gains: Array[float] = []
	var hip_depths: Array[int] = []
	hip_radii.resize(count)
	hip_gains.resize(count)
	hip_depths.resize(count)
	if centered:
		hip_depths[hips] = 1
		hip_radii[hips] = 0.0
		hip_gains[hips] = scales[hips] # Retain Hips scale; Root gain is applied outside.
	var proxy := {"editor": editor, "player_sprite": sprite}
	var pixel_origin: Vector2 = source.geometry.project(proxy, Vector3.ZERO)
	var axes: Array[Vector2] = []
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		axes.append(source.geometry.project(proxy, axis) - pixel_origin)
	var pixel_gain := _projection_norm(axes)
	if pixel_gain >= 38.0 or not pixel_origin.is_finite():
		return _unsupported("PROJECTION_NUMERIC_ENVELOPE")
	var maximum := 0.0
	var centered_span := 0.0
	var weight_deficit := 0.0
	for limb: Array in source.geometry.LIMBS:
		var start := skeleton.find_bone(limb[0])
		var end := skeleton.find_bone(limb[1])
		if start < 0 or end < 0:
			return _unsupported("LIMB_BONE")
		maximum = maxf(maximum, _norm2(pixel_origin) + pixel_gain * (world_gain * maxf(radii[start], radii[end]) + _norm(camera.global_basis.x) * float(limb[2])))
		if centered:
			if not _chain(start, parents, translations, scales, hip_radii, hip_gains, hip_depths, hips) or not _chain(end, parents, translations, scales, hip_radii, hip_gains, hip_depths, hips):
				centered = false
				centered_reason = "LIMB_OUTSIDE_HIPS"
			else:
				centered_span = maxf(centered_span, pixel_gain * (world_gain * root_gain * maxf(hip_radii[start], hip_radii[end]) + _norm(camera.global_basis.x) * float(limb[2])))
	var shield_vertices := 0
	var faces := 0
	var shields := 0
	for node: Node in editor.model_root.find_children("*", "MeshInstance3D", true, false):
		var name := str(node.name)
		var face := name.begins_with("Face_Standard")
		if not face and not name.begins_with("Shield_"):
			continue
		var part := node as MeshInstance3D
		if not part.mesh is ArrayMesh or part.mesh.get_surface_count() == 0 or part.skin == null or part.get_blend_shape_count() != 0 or part.get_node_or_null(part.skeleton) != skeleton:
			return _unsupported("ORIGINAL_COLLIDER_MESH_OR_SKIN")
		var binds: Array[Transform3D] = []
		var joints: Array[int] = []
		for binding in range(part.skin.get_bind_count()):
			var joint := part.skin.get_bind_bone(binding)
			if joint < 0:
				joint = skeleton.find_bone(part.skin.get_bind_name(binding))
			var bind := part.skin.get_bind_pose(binding)
			if joint < 0 or joint >= count or not bind.is_finite() or _basis_norm(bind.basis) > 1.01 or _norm(bind.origin) > 2.0:
				return _unsupported("SKIN_BIND_ENVELOPE")
			binds.append(bind)
			joints.append(joint)
		var mesh_radius := 0.0
		var centered_mesh_radius := 0.0
		var vertex_count := 0
		for surface in range(part.mesh.get_surface_count()):
			var arrays: Array = part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if vertices.is_empty() or arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
				return _unsupported("MISSING_SKIN_ARRAYS")
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if indices.size() != weights.size() or indices.size() % vertices.size() != 0:
				return _unsupported("SKIN_ARRAY_SHAPE")
			var influences := int(float(indices.size()) / vertices.size())
			if influences < 1 or influences > 4:
				return _unsupported("SKIN_INFLUENCE_COUNT")
			vertex_count += vertices.size()
			for vertex_index in range(vertices.size()):
				var vertex := vertices[vertex_index]
				if not vertex.is_finite() or _norm(vertex) > 2.0:
					return _unsupported("SKIN_VERTEX_ENVELOPE")
				var extent := 0.0
				var centered_extent := 0.0
				var total_weight := 0.0
				for influence in range(influences):
					var location := vertex_index * influences + influence
					var weight := float(weights[location])
					var binding := indices[location]
					if not is_finite(weight) or weight < 0.0 or binding < 0 or binding >= binds.size():
						return _unsupported("SKIN_WEIGHT_OR_REFERENCE")
					total_weight += weight
					if weight == 0.0:
						continue
					var joint := joints[binding]
					var bind_radius := _bind_radius(binds[binding], vertex)
					if face:
						if not _chain(joint, parents, translations, scales, relative_radii, relative_gains, relative_depths, head):
							return _unsupported("FACE_OUTSIDE_HEAD_DESCENDANTS")
						extent += weight * (relative_radii[joint] + relative_gains[joint] * bind_radius)
					else:
						extent += weight * (radii[joint] + gains[joint] * bind_radius)
					if centered:
						if not _chain(joint, parents, translations, scales, hip_radii, hip_gains, hip_depths, hips):
							centered = false
							centered_reason = "SKIN_OUTSIDE_HIPS"
						else:
							centered_extent += weight * (hip_radii[joint] + hip_gains[joint] * bind_radius)
				if total_weight > 1.0 or (face and total_weight != 1.0):
					return _unsupported("SKIN_WEIGHT_SUM")
				mesh_radius = maxf(mesh_radius, extent)
				centered_mesh_radius = maxf(centered_mesh_radius, centered_extent)
				weight_deficit = maxf(weight_deficit, 1.0 - total_weight)
		if face:
			if vertex_count > 4096 or mesh_radius > 0.25:
				return _unsupported("HEAD_FIT_ENVELOPE")
			var corner_radius := sqrt(3.0) * mesh_radius
			# A real previously fitted head AABB is still owned by Geometry. A
			# full clear can rebuild a bound after asset mutation; never silently
			# forget a larger surviving original head fit from that same face ID.
			if source.geometry._head_bounds.has(part.get_instance_id()):
				var fitted: AABB = source.geometry._head_bounds[part.get_instance_id()]
				for corner in range(8):
					corner_radius = maxf(corner_radius, _norm(fitted.get_endpoint(corner)))
			if corner_radius > sqrt(3.0) * 0.25:
				return _unsupported("RETAINED_HEAD_FIT_ENVELOPE")
			mesh_radius = radii[head] + gains[head] * corner_radius
			if centered:
				centered_mesh_radius = hip_radii[head] + hip_gains[head] * corner_radius
			faces += 1
		else:
			shield_vertices += vertex_count
			shields += 1
		maximum = maxf(maximum, _norm2(pixel_origin) + pixel_gain * world_gain * mesh_radius)
		if centered:
			centered_span = maxf(centered_span, pixel_gain * world_gain * root_gain * centered_mesh_radius)
	if faces < 1 or shields < 1 or shield_vertices + 10 * 24 + 8 > 4096:
		return _unsupported("COLLIDER_COUNT_ENVELOPE")
	# Fixed native float32 proof: < .73 px for original skin/head inverse,
	# 4096 AABB/Rect expands, both camera pipelines, final map |coord|<=16384.
	# The whole pixel is strictly outside half-open Rect2.has_point boundaries.
	var continuous := maximum + 31.5
	if continuous >= 127.0:
		return _unsupported("LOCAL_128_NUMERIC_ENVELOPE")
	var radius := ceilf((continuous + 1.0) / 16.0) * 16.0
	if radius >= FALLBACK:
		return _unsupported("NO_TIGHTER_PROVEN_BOUND")
	var centered_clips: Dictionary = {}
	if centered:
		for clip: StringName in NONATTACK + NATIVE_ATTACKS:
			var curve: Dictionary = hip_curves[clip]
			var animation := player.get_animation(clip)
			# A same-clip seek need not reset bones after a cache clear. Missing
			# or disabled Hips position tracks can retain an earlier pose, so do
			# not substitute rest for this narrower per-clip enclosure.
			if int(curve.track) < 0 or animation.track_get_key_count(int(curve.track)) < 1:
				continue
			var motion := _hips_enclosure(animation, curve)
			var height := float(motion.height)
			# R*p-c = (p-c)+(R-I)*p. Pure world yaw fixes c=(0,h,0),
			# while Hips rotation remains arbitrary in the original below-Hips
			# chain. A skin sum s<=1 adds (1-s)*|c|, not a fictitious unit sum.
			var displacement := float(motion.residual) + root_tilt * float(motion.maximum)
			var local_radius := centered_span + pixel_gain * (world_gain * displacement + weight_deficit * absf(height)) + 1e-8
			var center: Vector2 = source.geometry.project(proxy, Vector3(0.0, height, 0.0))
			var rounded := ceilf(local_radius + 1.0)
			if center.is_finite() and maxf(absf(center.x), absf(center.y)) < 128.0 and rounded < ceilf(continuous - 31.5 + 1.0):
				centered_clips[clip] = {"center": center, "radius": rounded, "height": height,
					"continuous_pixels": local_radius, "hips_residual": motion.residual, "hips_maximum": motion.maximum}
	# All of these attack tracks already contributed to the CURVES envelope.
	# This encloses body/all-shield only, never a weapon used for guard/parry
	# or a custom aimed bone pose. The Army owner must reject possible IK.
	return {"radius": radius, "clips": NONATTACK + NATIVE_ATTACKS, "reason": "NATIVE_CONTINUOUS_UNAIMED_BODY_SHIELD",
		"continuous_pixels": continuous, "float_padding_pixels": 1.0, "world_coordinate_limit": 16384.0,
		"centered_clips": centered_clips, "centered_reason": centered_reason, "centered_root_gain": root_gain,
		"centered_root_tilt": root_tilt, "centered_span_pixels": centered_span, "centered_weight_deficit": weight_deficit,
		"maximum_position_extrapolation_metres": maximum_position_extrapolation,
		"position_keys": position_keys, "faces": faces, "shields": shields, "build_usec": Time.get_ticks_usec() - started}

static func _hips_enclosure(animation: Animation, curve: Dictionary) -> Dictionary:
	# Only a unique enabled, nonempty, already validated Hips position track
	# reaches this helper. Absent/disabled tracks retain the old origin bound.
	var track := int(curve.track)
	var positions: Array[Vector3] = []
	for index in range(animation.track_get_key_count(track)):
		positions.append(animation.track_get_key_value(track, index))
	var minimum := float(positions[0].y)
	var maximum := minimum
	for position: Vector3 in positions:
		minimum = minf(minimum, float(position.y))
		maximum = maxf(maximum, float(position.y))
	# Use the actual float32 center supplied to original projection, avoiding
	# an unaccounted binary64-to-Vector3 difference in the residual itself.
	var center := Vector3(0.0, (minimum + maximum) * 0.5, 0.0)
	var residual := 0.0
	var position_norm := 0.0
	for position: Vector3 in positions:
		residual = maxf(residual, _distance(position, center))
		position_norm = maxf(position_norm, _norm(position))
	return {"height": float(center.y), "residual": residual + float(curve.extrapolation),
		"maximum": position_norm + float(curve.extrapolation)}

static func _unsupported(reason: String, evidence: Dictionary = {}) -> Dictionary:
	var result := {"radius": FALLBACK, "clips": [], "reason": reason}
	if not evidence.is_empty():
		result["evidence"] = evidence
	return result

static func _chain(index: int, parents: Array[int], translations: Array[float], scales: Array[float], radii: Array[float], gains: Array[float], depths: Array[int], stop: int = -1) -> bool:
	if depths[index] > 0:
		return true
	if depths[index] == -1:
		return false
	depths[index] = -1
	var parent := parents[index]
	if parent == -1:
		if stop >= 0:
			return false
		radii[index] = translations[index]
		gains[index] = scales[index]
		depths[index] = 1
	else:
		if not _chain(parent, parents, translations, scales, radii, gains, depths, stop):
			return false
		radii[index] = radii[parent] + gains[parent] * translations[index] + 1e-10
		gains[index] = gains[parent] * scales[index] + 1e-10
		depths[index] = depths[parent] + 1
	return true

static func _norm(value: Vector3) -> float:
	return sqrt(float(value.x) * value.x + float(value.y) * value.y + float(value.z) * value.z) + 1e-10

static func _norm2(value: Vector2) -> float:
	return sqrt(float(value.x) * value.x + float(value.y) * value.y) + 1e-10

static func _distance(a: Vector3, b: Vector3) -> float:
	# Do not round a Vector3 subtraction to float32 before the proof sum.
	var x := float(a.x) - float(b.x)
	var y := float(a.y) - float(b.y)
	var z := float(a.z) - float(b.z)
	return sqrt(x * x + y * y + z * z) + 1e-10

static func _basis_norm(value: Basis) -> float:
	var maximum := 0.0
	for row in range(3):
		var total := 0.0
		for column in range(3):
			var product := 0.0
			for axis in range(3):
				product += float(value[row][axis]) * value[column][axis]
			total += absf(product)
		maximum = maxf(maximum, total)
	return sqrt(maximum) + 1e-10

static func _basis_minimum(value: Basis) -> float:
	var minimum := INF
	for row in range(3):
		var total := 0.0
		for column in range(3):
			var product := 0.0
			for axis in range(3):
				product += float(value[row][axis]) * value[column][axis]
			total += product if row == column else -absf(product)
		minimum = minf(minimum, total)
	return sqrt(maxf(0.0, minimum)) - 1e-10

static func _projection_norm(axes: Array[Vector2]) -> float:
	var xx := 0.0
	var xy := 0.0
	var yy := 0.0
	for axis: Vector2 in axes:
		xx += float(axis.x) * axis.x
		xy += float(axis.x) * axis.y
		yy += float(axis.y) * axis.y
	return sqrt(maxf(xx + absf(xy), yy + absf(xy))) + 1e-10

static func _bind_radius(bind: Transform3D, vertex: Vector3) -> float:
	var squared := 0.0
	for row in range(3):
		var component := float(bind.origin[row])
		for column in range(3):
			component += float(bind.basis[column][row]) * vertex[column]
		squared += component * component
	return sqrt(squared) + 1e-10
