extends RefCounted
## Test-only native descriptor. No JSON, replacement assets, or sampled curves.
## Original Nodes stay outside descriptor; only original Animation resources and
## typed value arrays cross into the experimental compiled sampler.

static func build(source: Variant, clip_names: Array[StringName] = [&"idle", &"walk_slash"]) -> Dictionary:
	if not source is Object or not is_instance_valid(source):
		return _reject("SOURCE", "An initialized original contact Source is required")
	var editor: Variant = source.get("editor")
	var skeleton: Skeleton3D = source.get("skeleton")
	if not is_instance_valid(editor) or not is_instance_valid(skeleton) or editor.model_root == null:
		return _reject("SOURCE", "Original editor/model/skeleton is missing")
	var player: AnimationPlayer = editor.animation_player
	if player == null or player.get_script() != null or player.callback_mode_process != AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL or player.is_playing():
		return _reject("PLAYBACK", "Only the original paused manual native player is admitted")
	if player.get_default_blend_time() != 0.0 or not player.get("blend_times").is_empty() or not player.get_queue().is_empty() or not player.root_motion_track.is_empty():
		return _reject("BLENDING", "Blends, queues and root motion are outside this slice")
	if skeleton.show_rest_only or skeleton.get_motion_scale() != 1.0 or skeleton.get_script() != null:
		return _reject("SKELETON", "Rest-only, motion scaling and scripted skeletons are unsupported")
	var physical_bones: int = skeleton.find_children("*", "PhysicalBone3D", true, false).size()
	for modifier: Node in skeleton.find_children("*", "SkeletonModifier3D", true, false):
		# Same narrow native compatibility-node admission as SourceBounds. Native
		# incoming skeleton signals are not authored pose modifiers; outgoing
		# modification callbacks, children, physical bones or scripts are rejected.
		var simulator := modifier as PhysicalBoneSimulator3D
		var empty_native_simulator: bool = simulator != null and modifier.get_class() == "PhysicalBoneSimulator3D" and modifier.get_script() == null and modifier.get_parent() == skeleton and modifier.get_child_count(true) == 0 and physical_bones == 0 and not simulator.is_simulating_physics() and modifier.get_signal_connection_list(&"modification_processed").is_empty()
		if not empty_native_simulator:
			return _reject("MODIFIER", "Only the original empty physical-bone simulator is admitted", {
				"path": str(skeleton.get_path_to(modifier)), "class": modifier.get_class(), "scripted": modifier.get_script() != null,
				"parent_is_skeleton": modifier.get_parent() == skeleton, "children": modifier.get_child_count(true), "physical_bones": physical_bones,
				"active": modifier.get("active"), "influence": modifier.get("influence"),
				"simulating": simulator.is_simulating_physics() if simulator != null else false,
				"modification_callbacks": modifier.get_signal_connection_list(&"modification_processed").size()})
	var animation_root: Node = player.get_node_or_null(player.root_node)
	if animation_root == null or skeleton != editor.model_root.find_child("Skeleton3D", true, false):
		return _reject("ROOT", "Native animation paths must resolve to this original skeleton")
	var count: int = skeleton.get_bone_count()
	if count <= 0 or count > 512 or clip_names.is_empty():
		return _reject("SIZE", "Empty or oversized native descriptor")
	var descriptor := {"schema_version": 1, "bone_names": PackedStringArray(), "parents": PackedInt32Array(),
		"rest": [], "initial_positions": PackedVector3Array(), "initial_rotations": [], "initial_scales": PackedVector3Array(),
		"morph_names": PackedStringArray(), "initial_morphs": PackedFloat32Array(), "clips": {},
		"initial_clip": StringName(editor.selected_animation), "reset_morphs": PackedInt32Array(),
		"motion_scale": skeleton.get_motion_scale(), "mixer_deterministic": player.deterministic,
		"mixer_positions": PackedVector3Array(), "mixer_rotations": [], "mixer_scales": PackedVector3Array(),
		"mixer_morphs": PackedFloat32Array(), "mixer_channels": PackedInt32Array(), "mixer_morph_channels": PackedInt32Array()}
	descriptor.mixer_channels.resize(count)
	descriptor.mixer_channels.fill(0)
	for bone in range(count):
		var parent: int = skeleton.get_bone_parent(bone)
		var rest: Transform3D = skeleton.get_bone_rest(bone)
		if parent < -1 or parent >= count or not rest.is_finite() or skeleton.get_bone_global_pose_override(bone) != Transform3D.IDENTITY or not skeleton.is_bone_enabled(bone):
			return _reject("BONE", "Invalid, disabled or overridden original bone", {"bone": bone})
		var cursor: int = parent
		var seen := {bone: true}
		while cursor >= 0:
			if cursor >= count or seen.has(cursor):
				return _reject("PARENT_CYCLE", "Original bone ancestry is cyclic")
			seen[cursor] = true
			cursor = skeleton.get_bone_parent(cursor)
		var position := skeleton.get_bone_pose_position(bone)
		var rotation := skeleton.get_bone_pose_rotation(bone)
		var scale := skeleton.get_bone_pose_scale(bone)
		if not position.is_finite() or not rotation.is_finite() or not scale.is_finite():
			return _reject("POSE", "Nonfinite initial original pose")
		descriptor.bone_names.append(skeleton.get_bone_name(bone))
		descriptor.parents.append(parent)
		descriptor.rest.append(rest)
		descriptor.initial_positions.append(position)
		descriptor.initial_rotations.append(rotation)
		descriptor.initial_scales.append(scale)
		descriptor.mixer_positions.append(rest.origin)
		descriptor.mixer_rotations.append(rest.basis.get_rotation_quaternion())
		descriptor.mixer_scales.append(rest.basis.get_scale())
	var morph_nodes: Array[MeshInstance3D] = []
	var morph_slots := PackedInt32Array()
	var morph_lookup := {}
	var reset_nodes := {}
	for node: Node in editor.model_root.find_children("Armor_Mingguang_01_*", "MeshInstance3D", true, false):
		reset_nodes[node.get_instance_id()] = true
	for record: Dictionary in editor._combat_cloth:
		if is_instance_valid(record.node):
			reset_nodes[record.node.get_instance_id()] = true
	for node: Node in editor.model_root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for shape in range(mesh.get_blend_shape_count()):
			var value: float = mesh.get_blend_shape_value(shape)
			if not is_finite(value):
				return _reject("MORPH", "Nonfinite original morph")
			var index: int = morph_nodes.size()
			morph_lookup[[mesh.get_instance_id(), shape]] = index
			morph_nodes.append(mesh)
			morph_slots.append(shape)
			descriptor.morph_names.append(str(editor.model_root.get_path_to(mesh)) + ":" + str(mesh.mesh.get_blend_shape_name(shape)))
			descriptor.initial_morphs.append(value)
			descriptor.mixer_morphs.append(0.0)
			if reset_nodes.has(mesh.get_instance_id()):
				descriptor.reset_morphs.append(index)
	# Native mixer channel availability is built from the whole original library,
	# not just the two requested clips. It affects missing-channel initialization.
	var mixer_morph_channels := {}
	for name: StringName in player.get_animation_list():
		var animation: Animation = player.get_animation(name)
		for track in range(animation.get_track_count()):
			var kind: int = animation.track_get_type(track)
			var path: NodePath = animation.track_get_path(track)
			if path.is_absolute() or path.get_subname_count() != 1:
				continue
			var node: Node = animation_root.get_node_or_null(NodePath(path.get_concatenated_names()))
			if animation.track_is_enabled(track) and node == skeleton and kind in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
				var bone: int = skeleton.find_bone(path.get_subname(0))
				if bone >= 0:
					descriptor.mixer_channels[bone] |= {Animation.TYPE_POSITION_3D: 1, Animation.TYPE_ROTATION_3D: 2, Animation.TYPE_SCALE_3D: 4}[kind]
			if animation.track_is_enabled(track) and kind == Animation.TYPE_BLEND_SHAPE and node is MeshInstance3D and animation.track_get_key_count(track) > 0:
				var shape: int = node.find_blend_shape_by_name(path.get_subname(0))
				var key := [node.get_instance_id(), shape]
				if morph_lookup.has(key):
					var index: int = int(morph_lookup[key])
					if not mixer_morph_channels.has(index):
						mixer_morph_channels[index] = true
						descriptor.mixer_morph_channels.append(index)
					if name == &"RESET":
						var value: float = animation.track_get_key_value(track, 0)
						if not is_finite(value):
							return _reject("RESET_MORPH", "Nonfinite original RESET morph")
						descriptor.mixer_morphs[index] = value
	var tracks := 0
	var keys := 0
	for name: StringName in clip_names:
		if descriptor.clips.has(name) or not player.has_animation(name):
			return _reject("CLIP", "Missing or duplicate requested native clip", {"clip": str(name)})
		var animation: Animation = player.get_animation(name)
		if not is_finite(animation.length) or animation.length <= 0.0 or not player.animation_get_next(name).is_empty():
			return _reject("CLIP_TIME", "Invalid clip length or next-animation transition")
		var mapping := {"animation": animation, "track_bones": PackedInt32Array(), "track_morphs": PackedInt32Array(), "ignore_tracks": PackedInt32Array()}
		mapping.track_bones.resize(animation.get_track_count())
		mapping.track_bones.fill(-1)
		mapping.track_morphs.resize(animation.get_track_count())
		mapping.track_morphs.fill(-1)
		var seen_tracks := {}
		for track in range(animation.get_track_count()):
			tracks += 1
			if not animation.track_is_enabled(track):
				mapping.ignore_tracks.append(track)
				continue
			var kind: int = animation.track_get_type(track)
			var path: NodePath = animation.track_get_path(track)
			if kind not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D, Animation.TYPE_BLEND_SHAPE] or animation.track_is_compressed(track) or animation.track_get_interpolation_type(track) not in [Animation.INTERPOLATION_LINEAR, Animation.INTERPOLATION_NEAREST]:
				return _reject("TRACK", "Unsupported enabled native track/interpolation/compression", {"clip": str(name), "track": track})
			if path.is_absolute() or path.get_subname_count() != 1:
				return _reject("PATH", "Unsupported native track path")
			var node: Node = animation_root.get_node_or_null(NodePath(path.get_concatenated_names()))
			if kind == Animation.TYPE_BLEND_SHAPE:
				if not node is MeshInstance3D:
					return _reject("MORPH_TARGET", "Native morph path does not resolve to an original mesh")
				var shape: int = node.find_blend_shape_by_name(path.get_subname(0))
				var key := [node.get_instance_id(), shape]
				if not morph_lookup.has(key):
					return _reject("MORPH_TARGET", "Missing original morph target")
				mapping.track_morphs[track] = int(morph_lookup[key])
			else:
				if node != skeleton:
					return _reject("BONE_TARGET", "Track resolves outside the original skeleton")
				var bone: int = skeleton.find_bone(path.get_subname(0))
				if bone < 0:
					return _reject("BONE_TARGET", "Missing original bone target")
				mapping.track_bones[track] = bone
			var target_key := [kind, mapping.track_bones[track], mapping.track_morphs[track]]
			if seen_tracks.has(target_key):
				return _reject("DUPLICATE_TRACK", "Multiple enabled writers for one channel")
			seen_tracks[target_key] = true
			var previous_time := -INF
			if animation.track_get_key_count(track) <= 0:
				return _reject("EMPTY_TRACK", "Enabled native track has no keys")
			for key in range(animation.track_get_key_count(track)):
				keys += 1
				var time: float = animation.track_get_key_time(track, key)
				var value: Variant = animation.track_get_key_value(track, key)
				if not is_finite(time) or time < 0.0 or time > animation.length or time <= previous_time or not is_finite(animation.track_get_key_transition(track, key)):
					return _reject("KEY_TIME", "Nonfinite/out-of-range/non-increasing original key")
				if (kind == Animation.TYPE_BLEND_SHAPE and (typeof(value) != TYPE_FLOAT or not is_finite(value))) or (kind == Animation.TYPE_ROTATION_3D and (not value is Quaternion or not value.is_finite())) or (kind in [Animation.TYPE_POSITION_3D, Animation.TYPE_SCALE_3D] and (not value is Vector3 or not value.is_finite())):
					return _reject("KEY_VALUE", "Invalid original native key value")
				previous_time = time
		descriptor.clips[name] = mapping
	return {"ok": true, "code": "OK", "descriptor": descriptor, "morph_nodes": morph_nodes, "morph_slots": morph_slots,
		"counts": {"bones": count, "morphs": morph_nodes.size(), "clips": clip_names.size(), "tracks": tracks, "enabled_keys": keys}}

static func morph_values(binding: Dictionary) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	var nodes: Array = binding.morph_nodes
	var slots: PackedInt32Array = binding.morph_slots
	for index in range(nodes.size()):
		values.append((nodes[index] as MeshInstance3D).get_blend_shape_value(slots[index]))
	return values

static func _reject(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "details": details}
