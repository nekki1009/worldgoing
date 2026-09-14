extends SceneTree
## GPU diagnostic only: one original private Source; no Actor, seek or sample.
## Internal 23 seconds / unchanged canonical visual helper 25 seconds.
## Export success is not a proven conservative bound or an FPS result.

const Source = preload("res://scripts/terrain_lab/terrain_army_contact_source.gd")
const MANIFEST := "res://assets/characters/terrain_lab_army/standard_soldier/standard_soldier_atlas.json"
const SOURCE_PATH := "res://scripts/terrain_lab/terrain_army_contact_source.gd"
const TEST_PATH := "res://scripts/tests/site_army_native_bound_export_test.gd"
const TRACK_TYPES := {Animation.TYPE_POSITION_3D: "position", Animation.TYPE_ROTATION_3D: "rotation",
	Animation.TYPE_SCALE_3D: "scale", Animation.TYPE_BLEND_SHAPE: "blend_shape"}
var started := 0
var unsupported: Array[String] = []
var key_count := 0

func _initialize() -> void:
	started = Time.get_ticks_usec()
	_run.call_deferred()

func _run() -> void:
	create_timer(23.0).timeout.connect(func() -> void: push_error("Native-bound export deadline"); quit(1))
	assert(DisplayServer.get_name() != "headless", "Native original model initialization requires GPU")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	var hashes := _hashes()
	var source := Source.new()
	# No reference Actor is constructed: initialize's existing raw-model path
	# owns the one private original skeleton used by this standalone diagnostic.
	assert(source.initialize(root, manifest.appearance))
	var editor: HumanCharacter3DEditor = source.editor
	var skeleton: Skeleton3D = source.skeleton
	var player: AnimationPlayer = editor.animation_player
	var animation_root: Node = player.get_node_or_null(player.root_node)
	assert(animation_root != null and skeleton != null and _within_deadline())
	var initial_player := [player.assigned_animation, player.current_animation_position, player.is_playing()]
	var report := {"schema": 1, "source_hashes": hashes, "engine": Engine.get_version_info(),
		"scope": "Read native curve definitions and original rest/skin/mesh/projection only; no seek/sample or extra person/rig; no bound or FPS claim",
		"appearance": manifest.appearance, "available_parts": source._available_parts.duplicate(true),
		"available_animations": Array(player.get_animation_list()), "animations": [], "bones": [], "meshes": [], "skins": {},
		"model_path": str(editor.model_root.get_path()), "skeleton_path": str(skeleton.get_path()),
		"model_transform": _transform(editor.model_root.global_transform), "skeleton_transform": _transform(skeleton.global_transform),
		"animation_root": str(animation_root.get_path()), "animation_root_node": str(player.root_node),
		"default_blend": player.get_default_blend_time(), "blend_times": player.get("blend_times"),
		"queue": Array(player.get_queue()), "root_motion": str(player.root_motion_track), "conservative_bound_computed": false}
	if player.get_default_blend_time() != 0.0 or not player.get("blend_times").is_empty() or not player.get_queue().is_empty() or not player.root_motion_track.is_empty():
		unsupported.append("Live blend/queue/root-motion contract")
	for bone in range(skeleton.get_bone_count()):
		var parent := skeleton.get_bone_parent(bone)
		var seen: Array[int] = [bone]
		var ancestor := parent
		while ancestor >= 0 and ancestor < skeleton.get_bone_count() and ancestor not in seen:
			seen.append(ancestor)
			ancestor = skeleton.get_bone_parent(ancestor)
		if ancestor != -1:
			unsupported.append("Non-tree bone ancestry: %d" % bone)
		report.bones.append({"index": bone, "name": str(skeleton.get_bone_name(bone)), "parent": parent,
			"rest": _transform(skeleton.get_bone_rest(bone)), "enabled": skeleton.is_bone_enabled(bone)})
	var required: Array[StringName] = []
	for descriptor: Dictionary in manifest.clips:
		var clip := StringName(str(descriptor.get("pose", descriptor.id)))
		if clip not in required:
			required.append(clip)
	# Original normalization can select these native guard poses from equipment.
	for clip: StringName in [&"guard_weapon", &"guard_polearm"]:
		if clip not in required:
			required.append(clip)
	report["required_animations"] = required
	for clip: StringName in required:
		assert(_within_deadline())
		if not player.has_animation(clip):
			unsupported.append("Missing required native clip: " + str(clip))
			continue
		var animation := player.get_animation(clip)
		var record := {"name": str(clip), "length": animation.length, "loop_mode": animation.loop_mode,
			"next": str(player.animation_get_next(clip)), "tracks": []}
		if not str(record.next).is_empty():
			unsupported.append("Native queued next animation: " + str(clip))
		for track in range(animation.get_track_count()):
			record.tracks.append(_track(animation, track, clip, animation_root, skeleton))
		report.animations.append(record)
	for node: Node in editor.model_root.find_children("*", "MeshInstance3D", true, false):
		var name_text := str(node.name)
		if not name_text.begins_with("Face_Standard") and not name_text.begins_with("Shield_") and not name_text.begins_with("Weapon_"):
			continue
		assert(_within_deadline())
		var part := node as MeshInstance3D
		var mesh := part.mesh as ArrayMesh
		if mesh == null:
			unsupported.append("Relevant original ArrayMesh missing: " + name_text)
			continue
		var skin_id := str(part.skin.get_instance_id()) if part.skin != null else ""
		if part.skin != null and not report.skins.has(skin_id):
			var binds: Array = []
			for binding in range(part.skin.get_bind_count()):
				var bone := part.skin.get_bind_bone(binding)
				if bone < 0:
					bone = skeleton.find_bone(part.skin.get_bind_name(binding))
				if bone < 0 or bone >= skeleton.get_bone_count():
					unsupported.append("Unknown binding: %s/%d" % [name_text, binding])
				binds.append({"index": binding, "bone": bone, "name": str(part.skin.get_bind_name(binding)),
					"pose": _transform(part.skin.get_bind_pose(binding))})
			report.skins[skin_id] = binds
		var surfaces: Array = []
		for surface in range(mesh.get_surface_count()):
			var arrays := mesh.surface_get_arrays(surface)
			var vertices: Array = []
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				vertices.append(_vector(vertex))
			surfaces.append({"vertices": vertices, "bones": [] if arrays[Mesh.ARRAY_BONES] == null else Array(arrays[Mesh.ARRAY_BONES]),
				"weights": [] if arrays[Mesh.ARRAY_WEIGHTS] == null else Array(arrays[Mesh.ARRAY_WEIGHTS]),
				"indices": [] if arrays[Mesh.ARRAY_INDEX] == null else Array(arrays[Mesh.ARRAY_INDEX]),
				"primitive": mesh.surface_get_primitive_type(surface)})
		if part.get_blend_shape_count() != 0:
			unsupported.append("Relevant mesh has morphs; no bound assumed: " + name_text)
		report.meshes.append({"path": str(editor.model_root.get_path_to(part)), "name": name_text,
			"visible": part.is_visible_in_tree(), "transform": _transform(part.global_transform),
			"skeleton_path": str(part.skeleton), "skin_id": skin_id, "blend_shapes": part.get_blend_shape_count(), "surfaces": surfaces})
	var proxy := {"editor": editor, "player_sprite": source.sprite}
	var origin: Vector2 = source.geometry.project(proxy, Vector3.ZERO)
	var axes: Array = []
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		axes.append(_vector(source.geometry.project(proxy, axis) - origin))
	report["projection"] = {"type": editor.camera.projection, "camera_transform": _transform(editor.camera.global_transform),
		"camera_size": editor.camera.size, "keep_aspect": editor.camera.keep_aspect,
		"viewport": _vector(Vector2(editor.preview_viewport.size)), "map_origin": _vector(origin), "map_axes": axes,
		"sprite_transform": [_vector(source.sprite.global_transform.x), _vector(source.sprite.global_transform.y), _vector(source.sprite.global_transform.origin)],
		"limbs": Source.Geometry.LIMBS, "head_fit": "Original head-local AABB; must bound its corners, not only raw face vertices",
		"maximum_combat_offset_pixels": 31.5}
	if editor.camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
		unsupported.append("Non-orthographic projection")
	assert(initial_player == [player.assigned_animation, player.current_animation_position, player.is_playing()])
	assert(source.query_profile.sample_calls == 0 and source.query_profile.true_pose_evaluations == 0 and source._key.is_empty())
	assert(_within_deadline() and _hashes() == hashes, "Source must remain frozen throughout export")
	report["unsupported"] = unsupported
	report["curve_contract"] = "SUPPORTED_INPUTS_ONLY_NOT_A_BOUND" if unsupported.is_empty() else "UNSUPPORTED"
	report["native_key_count"] = key_count
	var directory := "res://output/site_combat_performance_20260913/native_bounds/%d_%d" % [int(Time.get_unix_time_from_system()), started]
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK)
	var path := directory + "/native.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "", true, true)) # Preserve every native floating-point bit representable in JSON.
	file.close()
	assert(_within_deadline())
	print("SITE_ARMY_NATIVE_BOUND_EXPORT_PASS ", JSON.stringify({"path": path, "sha256": FileAccess.get_sha256(path),
		"animations": report.animations.size(), "keys": key_count, "meshes": report.meshes.size(),
		"curve_contract": report.curve_contract, "unsupported": unsupported, "elapsed_usec": Time.get_ticks_usec() - started,
		"bound_proven": false, "sample_calls": 0}))
	source.dispose()
	quit(0)

func _track(animation: Animation, track: int, clip: StringName, animation_root: Node, skeleton: Skeleton3D) -> Dictionary:
	var type := animation.track_get_type(track)
	var path := animation.track_get_path(track)
	var interpolation := animation.track_get_interpolation_type(track)
	var label := "%s/%d:%s" % [clip, track, path]
	var result := {"index": track, "type": type, "type_name": TRACK_TYPES.get(type, "UNKNOWN"), "path": str(path),
		"interpolation": interpolation, "loop_wrap": animation.track_get_interpolation_loop_wrap(track),
		"enabled": animation.track_is_enabled(track), "compressed": animation.track_is_compressed(track), "bone": -1, "keys": []}
	if type not in TRACK_TYPES or interpolation not in [Animation.INTERPOLATION_LINEAR, Animation.INTERPOLATION_NEAREST] or result.compressed:
		unsupported.append("Track type/interpolation/compression: " + label)
	var target: Node = animation_root.get_node_or_null(NodePath(path.get_concatenated_names())) if not path.is_absolute() else null
	if type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
		if target == skeleton and path.get_subname_count() == 1:
			result.bone = skeleton.find_bone(path.get_subname(0))
		if int(result.bone) < 0:
			unsupported.append("Transform outside fixed original bone chain: " + label)
	elif type == Animation.TYPE_BLEND_SHAPE and (not target is MeshInstance3D or path.get_subname_count() != 1):
		unsupported.append("Unresolved original morph path: " + label)
	for key in range(animation.track_get_key_count(track)):
		var time := animation.track_get_key_time(track, key)
		var transition := animation.track_get_key_transition(track, key)
		var value: Variant = animation.track_get_key_value(track, key)
		if not is_finite(time) or transition != 1.0:
			unsupported.append("Key time/transition: %s/%d" % [label, key])
		result.keys.append([time, transition, _vector(value)])
		key_count += 1
	return result

func _vector(value: Variant) -> Variant:
	if value is Vector3:
		assert(value.is_finite())
		return [value.x, value.y, value.z]
	if value is Quaternion:
		assert(value.is_finite())
		return [value.x, value.y, value.z, value.w]
	if value is Vector2:
		assert(value.is_finite())
		return [value.x, value.y]
	if value is float or value is int:
		assert(is_finite(float(value)))
		return value
	unsupported.append("Unknown native key value type: " + type_string(typeof(value)))
	return {"unsupported_type": type_string(typeof(value)), "native_text": var_to_str(value)}

func _transform(value: Transform3D) -> Array:
	return [_vector(value.basis.x), _vector(value.basis.y), _vector(value.basis.z), _vector(value.origin)]

func _within_deadline() -> bool:
	return Time.get_ticks_usec() - started < 23000000

func _hashes() -> Dictionary:
	var result := {}
	for path: String in [SOURCE_PATH, TEST_PATH, MANIFEST, HumanCharacter3DEditor.MALE_MODEL_PATH,
		"res://scripts/ui/human_character_3d_editor.gd", "res://scripts/terrain_lab/terrain_weapon_collision.gd", "res://scripts/ui/character_render_contract.gd"]:
		result[path] = FileAccess.get_sha256(path)
	return result
