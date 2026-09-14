extends RefCounted
## Export of the current native Source's exact collision inputs.
## A descriptor is valid for this recipe/held-state/framing, not arbitrary swaps.
## Source owns the bounded bindings and must release each before dropping it.

const Geometry = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")

static func bind(source: RefCounted) -> Dictionary:
	var binding := _view_inputs(source, true)
	if not bool(binding.get("ok", false)):
		return binding
	binding["descriptor"] = capture(source)
	binding["invalidated"] = false
	binding["released"] = false
	# The callback captures only this Source-owned binding, never the Source.
	# Identity checks alone miss in-place Mesh/Skin edits. release() disconnects
	# these original resource signals and breaks the callback's binding reference.
	var changed := func() -> void:
		binding["invalidated"] = true
		binding["reason"] = "resource_changed"
	binding["changed_callback"] = changed
	for resource: Resource in binding.resources:
		if resource.changed.connect(changed) != OK:
			release(binding)
			return _refuse("resource_watch_failed")
	return binding

static func current(source: RefCounted, binding: Dictionary) -> bool:
	if not bool(binding.get("ok", false)) or bool(binding.get("released", true)):
		binding["reason"] = "binding_released_or_invalid"
		return false
	if bool(binding.get("invalidated", true)):
		binding["reason"] = "resource_changed"
		return false
	var inputs := _view_inputs(source)
	if not bool(inputs.get("ok", false)):
		binding["reason"] = inputs.reason
		return false
	if inputs.signature != binding.signature:
		binding["reason"] = "view_changed"
		return false
	binding["reason"] = ""
	return true

static func release(binding: Dictionary) -> void:
	var changed: Callable = binding.get("changed_callback", Callable())
	for resource: Resource in binding.get("resources", []):
		if is_instance_valid(resource) and changed.is_valid() and resource.changed.is_connected(changed):
			resource.changed.disconnect(changed)
	binding["changed_callback"] = Callable()
	binding["resources"] = []
	binding["morph_nodes"] = []
	binding["released"] = true

static func _view_inputs(source: RefCounted, collect_metadata: bool = false) -> Dictionary:
	if not is_instance_valid(source):
		return _refuse("missing_source")
	var editor: HumanCharacter3DEditor = source.editor
	var skeleton: Skeleton3D = source.skeleton
	var sprite: Sprite2D = source.sprite
	if not is_instance_valid(editor) or not is_instance_valid(skeleton) or not is_instance_valid(sprite) or not is_instance_valid(editor.model_root) or not is_instance_valid(editor.camera) or not is_instance_valid(editor.preview_viewport):
		return _refuse("missing_native_view")
	if not editor.model_root.is_ancestor_of(skeleton) or skeleton.get_script() != null or editor.camera.get_script() != null or sprite.get_script() != null:
		return _refuse("unknown_native_view")
	if source._key.size() != 6 or typeof(source._key[4]) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(source._key[4])) or float(source._key[4]) != 0.0:
		return _refuse("aimed_or_unposed")
	var camera: Camera3D = editor.camera
	if camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
		return _refuse("perspective_camera")
	if skeleton.find_bone("J_Bip_R_UpperArm") < 0:
		return _refuse("missing_shoulder")
	var camera_world := camera.get_camera_transform()
	var projection := camera.get_camera_projection()
	if not skeleton.global_transform.is_finite() or not camera_world.is_finite() or not sprite.global_transform.is_finite() or not projection.x.is_finite() or not projection.y.is_finite() or not projection.z.is_finite() or not projection.w.is_finite():
		return _refuse("nonfinite_framing")
	var values: Array = [source.get_instance_id(), source.geometry.get_instance_id(), editor.get_instance_id(),
		editor.model_root.get_instance_id(), skeleton.get_instance_id(), skeleton.get_version(), skeleton.get_bone_count(),
		camera.get_instance_id(), editor.preview_viewport.get_instance_id(), sprite.get_instance_id(),
		skeleton.global_transform, camera_world, camera.global_basis.x, projection,
		editor.preview_viewport.size, sprite.global_transform, source._key[2], source._key[5],
		str(editor.selected_animation), str(editor._resolve_weapon_attack_animation()), PackedVector2Array(Geometry._capsule_ring)]
	var metadata: Dictionary = {}
	if collect_metadata:
		var resources: Array[Resource] = []
		var morph_nodes: Array[MeshInstance3D] = []
		metadata = {"resources": resources, "morph_nodes": morph_nodes}
	var proxy := {"editor": editor}
	var face_state: Array = []
	for node: Node in source.geometry._mesh_nodes(proxy, "Face_Standard*"):
		var face := node as MeshInstance3D
		if not face.is_visible_in_tree() or face.mesh == null:
			continue
		if skeleton.find_bone("J_Bip_C_Head") < 0 or not source.geometry._head_bounds.has(face.get_instance_id()):
			return _refuse("native_head_fit_required")
		var bounds: Variant = source.geometry._head_bounds[face.get_instance_id()]
		if not bounds is AABB or not bounds.is_finite():
			return _refuse("invalid_native_head_fit")
		# Original head geometry consumes the first-fit bounds, not today's face
		# morph weights. Never fit a cold face or invalidate/refit the original map.
		face_state = [face.get_instance_id(), face.mesh.get_instance_id(), bounds]
		if collect_metadata:
			metadata.resources.append(face.mesh)
		break
	values.append(face_state)
	var weapon_state: Array = []
	for node: Node in source.geometry._mesh_nodes(proxy, "Weapon_*"):
		var part := node as MeshInstance3D
		var label := str(part.name)
		if not part.is_visible_in_tree() or part.mesh == null or "Holstered" in label or "Sheathed" in label or "Scabbard" in label:
			continue
		var reason := _part_inputs(part, weapon_state, metadata)
		if not reason.is_empty():
			return _refuse(reason)
	values.append(weapon_state)
	var shield_state: Array = []
	for node: Node in source.geometry._mesh_nodes(proxy, "Shield_*"):
		var part := node as MeshInstance3D
		if not part.is_visible_in_tree() or part.mesh == null:
			continue
		var reason := _part_inputs(part, shield_state, metadata)
		if not reason.is_empty():
			return _refuse(reason)
	values.append(shield_state)
	for slot: StringName in [&"helmet", &"armor", &"outfit", &"boots"]:
		var option := editor.part_options.get(slot) as OptionButton
		if option == null:
			return _refuse("missing_armor_option")
		var item := str(option.get_item_metadata(option.selected)) if option.selected >= 0 else "none"
		var armor_state: Array = [str(slot), item, SiteCombatRules.armor_profile(item) if item != "none" else {}]
		if item != "none":
			for prefix: String in editor._component_definition(slot, StringName(item)).get("prefixes", []):
				for node: Node in source.geometry._mesh_nodes(proxy, prefix + "*"):
					var part := node as MeshInstance3D
					if not part.is_visible_in_tree() or part.mesh == null:
						continue
					var reason := _part_inputs(part, armor_state, metadata)
					if not reason.is_empty():
						return _refuse(reason)
		values.append(armor_state)
	var result := {"ok": true, "reason": "", "signature": var_to_bytes(values)}
	if collect_metadata:
		result.merge(metadata)
	return result

static func _part_inputs(part: MeshInstance3D, values: Array, metadata: Dictionary) -> String:
	if part.get_script() != null or part.mesh.get_script() != null or (part.skin != null and part.skin.get_script() != null):
		return "scripted_collider"
	if not part.global_transform.is_finite():
		return "nonfinite_part_transform"
	var blend_count := part.get_blend_shape_count()
	for shape in range(blend_count):
		var value := part.get_blend_shape_value(shape)
		if not is_finite(value) or absf(value) > 0.0001:
			return "active_collider_morph"
	values.append([part.get_instance_id(), str(part.name), part.mesh.get_instance_id(),
		part.skin.get_instance_id() if part.skin != null else 0, part.global_transform,
		part.mesh.get_surface_count(), blend_count])
	if not metadata.is_empty():
		var resources: Array[Resource] = metadata.resources
		var morph_nodes: Array[MeshInstance3D] = metadata.morph_nodes
		if not resources.has(part.mesh):
			resources.append(part.mesh)
		if part.skin != null and not resources.has(part.skin):
			resources.append(part.skin)
		if blend_count > 0 and not morph_nodes.has(part):
			morph_nodes.append(part)
	return ""

static func _refuse(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func capture(source: RefCounted) -> Dictionary:
	var editor: HumanCharacter3DEditor = source.editor
	var skeleton: Skeleton3D = source.skeleton
	var camera: Camera3D = editor.camera
	assert(camera.projection == Camera3D.PROJECTION_ORTHOGONAL)
	var origin := camera.unproject_position(Vector3.ZERO)
	var axes: Array[Vector3] = []
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		var projected := camera.unproject_position(axis) - origin
		axes.append(Vector3(projected.x, projected.y, 0.0))
	origin -= Vector2(editor.preview_viewport.size) * 0.5
	var limbs: Array = []
	for limb: Array in Geometry.LIMBS:
		limbs.append([skeleton.find_bone(limb[0]), skeleton.find_bone(limb[1]), limb[2]])
	var result := {"schema": 1, "aim_weight": float(source._key[4]) if not source._key.is_empty() else 0.0,
		"skeleton_world": skeleton.global_transform, "camera_world": camera.get_camera_transform(),
		"camera_right": camera.global_basis.x, "projection": camera.get_camera_projection(),
		"viewport": Vector2(editor.preview_viewport.size), "sprite": source.sprite.global_transform,
		"mesh_projection": Transform3D(Basis(axes[0], axes[1], axes[2]), Vector3(origin.x, origin.y, 0.0)),
		"capsule_ring": PackedVector2Array(Geometry._capsule_ring), "limbs": limbs,
		"head": skeleton.find_bone("J_Bip_C_Head"), "has_head": false, "head_bounds": AABB(),
		"shoulder": skeleton.find_bone("J_Bip_R_UpperArm"), "knee": skeleton.find_bone("J_Bip_R_LowerLeg"),
		"foot": skeleton.find_bone("J_Bip_R_Foot"), "weapon_clip": str(editor._resolve_weapon_attack_animation()),
		"parrying": editor.selected_animation in [&"guard", &"guard_weapon", &"guard_polearm"],
		"weapons": [], "shields": [], "parry": [], "armor": [], "used_morph_names": PackedStringArray()}
	for node: Node in source.geometry._mesh_nodes({"editor": editor}, "Face_Standard*"):
		var mesh := node as MeshInstance3D
		if not mesh.is_visible_in_tree() or mesh.mesh == null:
			continue
		# Preserve the original first fit. Do not fit all faces at a new idle time.
		assert(source.geometry._head_bounds.has(mesh.get_instance_id()), "Native first head fit required before descriptor export")
		result.has_head = true
		result.head_bounds = source.geometry._head_bounds[mesh.get_instance_id()]
		break
	for node: Node in source.geometry._mesh_nodes({"editor": editor}, "Weapon_*"):
		var mesh := node as MeshInstance3D
		var label := str(mesh.name)
		if not mesh.is_visible_in_tree() or mesh.mesh == null or "Holstered" in label or "Sheathed" in label or "Scabbard" in label:
			continue
		var part := capture_part(mesh, skeleton, editor.model_root)
		result.parry.append(part)
		if not ("Grip" in label or "Handle" in label or "Guard" in label or "Shaft" in label):
			result.weapons.append(part)
	for node: Node in source.geometry._mesh_nodes({"editor": editor}, "Shield_*"):
		var mesh := node as MeshInstance3D
		if mesh.is_visible_in_tree() and mesh.mesh != null:
			result.shields.append(capture_part(mesh, skeleton, editor.model_root))
	for slot: StringName in [&"helmet", &"armor", &"outfit", &"boots"]:
		var option: OptionButton = editor.part_options[slot]
		if option.selected < 0:
			continue
		var item := str(option.get_item_metadata(option.selected))
		if item == "none":
			continue
		var armor := {"profile": SiteCombatRules.armor_profile(item), "parts": []}
		for prefix: String in editor._component_definition(slot, StringName(item)).get("prefixes", []):
			for node: Node in source.geometry._mesh_nodes({"editor": editor}, prefix + "*"):
				var mesh := node as MeshInstance3D
				if mesh.is_visible_in_tree() and mesh.mesh != null:
					armor.parts.append(capture_part(mesh, skeleton, editor.model_root))
		result.armor.append(armor)
	var all_parts: Array = result.parry + result.shields
	for armor: Dictionary in result.armor:
		all_parts.append_array(armor.parts)
	for part: Dictionary in all_parts:
		for name: String in part.morph_names:
			if not result.used_morph_names.has(name):
				result.used_morph_names.append(name)
	return result

static func capture_part(part: MeshInstance3D, skeleton: Skeleton3D, model_root: Node3D) -> Dictionary:
	var result := {"world": part.global_transform, "bind_bones": PackedInt32Array(), "bind_poses": [], "surfaces": [], "nonzero_morph": false, "morph_names": PackedStringArray()}
	for shape in range(part.get_blend_shape_count()):
		result.nonzero_morph = result.nonzero_morph or absf(part.get_blend_shape_value(shape)) > 0.0001
		result.morph_names.append(str(model_root.get_path_to(part)) + ":" + str(part.mesh.get_blend_shape_name(shape)))
	if part.skin != null:
		for bind_index in range(part.skin.get_bind_count()):
			var bone := part.skin.get_bind_bone(bind_index)
			if bone < 0:
				bone = skeleton.find_bone(part.skin.get_bind_name(bind_index))
			result.bind_bones.append(bone)
			result.bind_poses.append(part.skin.get_bind_pose(bind_index))
	for surface in range(part.mesh.get_surface_count()):
		var arrays := part.mesh.surface_get_arrays(surface)
		result.surfaces.append({"vertices": arrays[Mesh.ARRAY_VERTEX],
			"bones": arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array(),
			"weights": arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array(),
			"indices": arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()})
	return result

static func global_poses(source: RefCounted) -> Array:
	var result: Array = []
	for bone in range(source.skeleton.get_bone_count()):
		result.append(source.skeleton.get_bone_global_pose(bone))
	return result
