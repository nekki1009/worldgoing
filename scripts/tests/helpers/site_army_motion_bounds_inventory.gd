extends RefCounted
## Test-only derivative inventory, NOT admitted as a collision rejection.
## Reads native keys; never samples a grid and calls its maximum a proof.
const Bounds = preload("res://scripts/terrain_lab/terrain_army_source_bounds.gd")
const Geometry = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")

static func inspect(source: Variant, clip: StringName = &"idle") -> Dictionary:
	var envelope := Bounds.build(source)
	if envelope.get("centered_reason", "") != "READY" or float(envelope.radius) >= 256.0:
		return {"supported": false, "reason": "ORIGINAL_ENVELOPE", "envelope": envelope}
	var skeleton: Skeleton3D = source.skeleton
	var animation: Animation = source.editor.animation_player.get_animation(clip)
	if animation == null:
		return {"supported": false, "reason": "MISSING_CLIP"}
	var animation_root: Node = source.editor.animation_player.get_node(source.editor.animation_player.root_node)
	var local: Array[Dictionary] = []
	for bone in skeleton.get_bone_count():
		var rest := skeleton.get_bone_rest(bone)
		local.append({"parent": skeleton.get_bone_parent(bone), "length": Bounds._norm(rest.origin),
			"gain": Bounds._basis_norm(rest.basis), "position_rate": 0.0, "basis_rate": 0.0,
			"rotation_written": false, "position_written": false, "done": false})
	var seen := {}
	var max_time_slack := 0.0
	for track in animation.get_track_count():
		if not animation.track_is_enabled(track) or animation.track_get_type(track) == Animation.TYPE_BLEND_SHAPE:
			continue
		var path := animation.track_get_path(track)
		var kind := animation.track_get_type(track)
		if kind not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D] or path.get_subname_count() != 1 or animation_root.get_node_or_null(NodePath(path.get_concatenated_names())) != skeleton:
			return {"supported": false, "reason": "NON_BONE_TRACK"}
		var bone := skeleton.find_bone(path.get_subname(0))
		if bone < 0 or seen.has([bone, kind]) or animation.track_is_compressed(track) or animation.track_get_interpolation_type(track) != Animation.INTERPOLATION_LINEAR:
			return {"supported": false, "reason": "TRACK_CONTRACT", "path": str(path)}
		seen[[bone, kind]] = true
		var count := animation.track_get_key_count(track)
		if count < 2 or animation.track_get_key_time(track, 0) != 0.0 or animation.track_get_key_time(track, count - 1) != animation.length:
			return {"supported": false, "reason": "INCOMPLETE_ENDPOINTS", "path": str(path), "count": count,
				"last": animation.track_get_key_time(track, count - 1) if count > 0 else -1.0, "length": animation.length}
		var previous: Variant = animation.track_get_key_value(track, 0)
		var previous_time := 0.0
		for index in count:
			var time := animation.track_get_key_time(track, index)
			var value: Variant = animation.track_get_key_value(track, index)
			if not is_finite(time) or animation.track_get_key_transition(track, index) != 1.0:
				return {"supported": false, "reason": "KEY_CONTRACT"}
			var dt := time - previous_time
			if index > 0 and (dt <= 0.0 or 1e-5 * maxf(1.0, animation.length) / dt > 0.01):
				return {"supported": false, "reason": "DENSE_KEYS"}
			if kind == Animation.TYPE_POSITION_3D:
				if not value is Vector3 or not value.is_finite():
					return {"supported": false, "reason": "POSITION_VALUE"}
				local[bone].position_written = true
				local[bone].length = maxf(float(local[bone].length), Bounds._norm(value))
				if index > 0:
					local[bone].position_rate = maxf(float(local[bone].position_rate), Bounds._distance(previous, value) / dt)
			else:
				if not value is Quaternion or not value.is_finite() or absf(float(value.length_squared()) - 1.0) > 0.00001:
					return {"supported": false, "reason": "QUATERNION_NORM"}
				local[bone].rotation_written = true
				if index > 0:
					var derivative := _quaternion_rate(previous, value) / dt
					if not is_finite(derivative):
						return {"supported": false, "reason": "AMBIGUOUS_SHORTEST_ARC"}
					# Conservative candidate for normalized quaternion -> rotation
					# operator derivative. Still requires an independent proof audit.
					local[bone].basis_rate = maxf(float(local[bone].basis_rate), 4.0 * derivative * float(local[bone].gain))
			previous = value
			previous_time = time
		max_time_slack = maxf(max_time_slack, 4e-5 * maxf(1.0, animation.length))
	var required := {}
	for limb: Array in Geometry.LIMBS:
		for endpoint in 2:
			_mark_chain(skeleton.find_bone(limb[endpoint]), local, required)
	var head := skeleton.find_bone("J_Bip_C_Head")
	_mark_chain(head, local, required)
	var shield_radii := {}
	for part: MeshInstance3D in source.editor.model_root.find_children("Shield_*", "MeshInstance3D", true, false):
		for surface in part.mesh.get_surface_count():
			var arrays: Array = part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var stride := int(float(bones.size()) / vertices.size())
			for index in vertices.size():
				for influence in stride:
					var address := index * stride + influence
					if weights[address] == 0.0:
						continue
					var binding := bones[address]
					var bone := part.skin.get_bind_bone(binding)
					if bone < 0:
						bone = skeleton.find_bone(part.skin.get_bind_name(binding))
					_mark_chain(bone, local, required)
					shield_radii[bone] = maxf(float(shield_radii.get(bone, 0.0)), Bounds._bind_radius(part.skin.get_bind_pose(binding), vertices[index]))
	var root := skeleton.find_bone("Root")
	for bone: int in required:
		if bone != root and not bool(local[bone].rotation_written):
			return {"supported": false, "reason": "UNWRITTEN_COLLIDER_ANCESTOR", "bone": skeleton.get_bone_name(bone)}
		_rate_chain(bone, local)
	var velocity := 0.0
	for limb: Array in Geometry.LIMBS:
		for endpoint in 2:
			velocity = maxf(velocity, float(local[skeleton.find_bone(limb[endpoint])].global_position_rate))
	velocity = maxf(velocity, float(local[head].global_position_rate) + float(local[head].global_basis_rate) * sqrt(3.0) * 0.25)
	for bone: int in shield_radii:
		velocity = maxf(velocity, float(local[bone].global_position_rate) + float(local[bone].global_basis_rate) * float(shield_radii[bone]))
	var pixels := velocity * Bounds._basis_norm(skeleton.global_basis) * 38.0
	return {"supported": true, "admitted": false, "reason": "DERIVATIVE_CANDIDATE_REQUIRES_PROOF_AND_REPLAY",
		"clip": str(clip), "length": animation.length, "pixels_per_second_candidate": pixels,
		"approx_find_time_slack": max_time_slack, "margin_one_120hz_step_candidate": pixels * (1.0 / 120.0 + max_time_slack) + 2.0,
		"required_bones": required.size(), "local_rates": local}

static func _quaternion_rate(a: Quaternion, b: Quaternion) -> float:
	var dot := float(a.x) * b.x + float(a.y) * b.y + float(a.z) * b.z + float(a.w) * b.w
	if absf(dot) < 0.0001:
		return INF # Do not guess the float32 shortest-arc sign at 180 degrees.
	if dot < 0.0:
		b = -b
		dot = -dot
	var difference := sqrt(pow(float(b.x) - a.x, 2) + pow(float(b.y) - a.y, 2) + pow(float(b.z) - a.z, 2) + pow(float(b.w) - a.w, 2))
	# Bound both native branches near the float32 dot threshold. The centered
	# form preserves cancellation for nearly stationary keys; summing the two
	# original coefficient derivatives would produce a useless huge idle rate.
	var theta := acos(clampf(dot - 0.000002, 0.0, 1.0))
	if theta <= 0.0000001:
		return difference + 0.000001
	var rate := float(a.length()) * theta * sin(0.51 * theta) / cos(0.5 * theta) + difference * theta / sin(theta)
	return maxf(difference, rate) + 0.000001

static func _mark_chain(bone: int, local: Array[Dictionary], required: Dictionary) -> void:
	while bone >= 0 and not required.has(bone):
		required[bone] = true
		bone = int(local[bone].parent)

static func _rate_chain(bone: int, local: Array[Dictionary]) -> void:
	var row := local[bone]
	if row.done:
		return
	var parent := int(row.parent)
	if parent < 0:
		row.global_gain = row.gain
		row.global_position_rate = row.position_rate
		row.global_basis_rate = row.basis_rate
	else:
		_rate_chain(parent, local)
		var ancestor := local[parent]
		row.global_gain = float(ancestor.global_gain) * float(row.gain)
		row.global_basis_rate = float(ancestor.global_basis_rate) * float(row.gain) + float(ancestor.global_gain) * float(row.basis_rate)
		row.global_position_rate = float(ancestor.global_position_rate) + float(ancestor.global_basis_rate) * float(row.length) + float(ancestor.global_gain) * float(row.position_rate)
	row.done = true
