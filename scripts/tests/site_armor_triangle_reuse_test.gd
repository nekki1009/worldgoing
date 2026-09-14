extends SceneTree
## GPU exact A/B, --body=0 and --body=1. Not a crowd/FPS benchmark.
const Collision = preload("res://scripts/terrain_lab/terrain_weapon_collision.gd")

class FrozenGeometry extends Collision:
	# Complete pre-reuse function: do not replace this with a call to super.
	func mesh_covers_point(actor: Variant, part: MeshInstance3D, skeleton: Skeleton3D, point: Vector2) -> bool:
		var vertices := posed_points(actor, part, skeleton)
		var vertex_offset := 0
		for surface in range(part.mesh.get_surface_count()):
			var arrays := part.mesh.surface_get_arrays(surface)
			var surface_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() if not indices.is_empty() else surface_vertices.size()
			for triangle in range(0, count - 2, 3):
				var polygon := PackedVector2Array()
				for corner in range(3):
					polygon.append(vertices[vertex_offset + (indices[triangle + corner] if not indices.is_empty() else triangle + corner)])
				if Geometry2D.is_point_in_polygon(point, polygon):
					return true
			vertex_offset += surface_vertices.size()
		return false

class ClearedSurfaceGeometry extends Collision:
	func posed_points(actor: Variant, part: MeshInstance3D, skeleton: Skeleton3D) -> PackedVector2Array:
		var result := super.posed_points(actor, part, skeleton)
		_surfaces.clear() # Exercise the original-array fallback after projection.
		return result

var body := 0
var deadline := 0
var mesh_checks := 0
var armor_checks := 0
var old_usec := 0
var new_usec := 0
var positive_checks := 0
var frozen := FrozenGeometry.new()
var current := Collision.new()

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--body="):
			body = argument.trim_prefix("--body=").to_int()
	call_deferred("run")

func run() -> void:
	assert(DisplayServer.get_name() != "headless", "Original blend-shape baking needs the GPU verifier")
	assert(body in [0, 1])
	deadline = Time.get_ticks_usec() + 23000000
	create_timer(23.0).timeout.connect(func() -> void: quit(1))
	var actor := TerrainTestCharacter.new()
	actor.visual_state.body_index = body
	root.add_child(actor)
	actor.set_process(false)
	actor.initialize_visual()
	assert(actor.editor != null)
	actor.editor.set_process(false)
	actor.editor.set_playing(false)
	actor.editor.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	actor.editor.combat_ready = true
	actor.editor.visual_state.combat_ready = true
	var leather := HumanCharacter3DEditor.default_appearance(body)
	var metal := leather.duplicate(true)
	metal.parts.armor = "armor_mingguang_01"
	metal.parts.helmet = "helmet_mingguang_01"
	metal.parts.outfit = "outfit_chinese_lining_01"
	metal.parts.boots = "boots_mingguang_01"
	for pose: Array in [[leather, &"guard", 0.073, Vector2i.DOWN], [metal, &"down", 1.137, Vector2i.RIGHT], [metal, &"get_up", 0.337, Vector2i.RIGHT]]:
		pose_actor(actor, pose[0], pose[1], pose[2], pose[3])
		check_actor(actor)
		await process_frame
	pose_actor(actor, leather, &"guard", 0.073, Vector2i.DOWN)
	check_topology(actor)
	assert(positive_checks > 0 and armor_checks > 0 and mesh_checks > 0)
	actor.queue_free()
	await process_frame
	print("SITE ARMOR TRIANGLE REUSE PASS: body=", body, " mesh=", mesh_checks, " armor=", armor_checks,
		" positive=", positive_checks, " frozen_us=", old_usec, " reuse_us=", new_usec,
		"; exact original predicate/order, real armor/shield/low poses, tiny edge offsets, world+5000, mixed topology/cache miss; not FPS acceptance")
	quit(0)

func pose_actor(actor: TerrainTestCharacter, appearance: Dictionary, clip: StringName, time: float, direction: Vector2i) -> void:
	assert(Time.get_ticks_usec() < deadline)
	assert(actor.editor.restore_appearance(appearance))
	actor.facing = direction
	actor.editor.set_preview_yaw_degrees(0.0 if direction == Vector2i.DOWN else 90.0)
	actor.play_pose(clip)
	actor.editor.animation_player.seek(time, true)
	actor.editor.animation_player.advance(0.0)
	actor.editor._update_combat_props()
	actor.editor._update_scabbard_pose()
	actor.editor._update_combat_cloth()
	actor._sync_render_projection()
	actor.guarding = actor.editor.selected_animation == &"guard"
	actor.guard_transition_left = 0.0
	actor.guard_break_left = 0.0

func check_actor(actor: TerrainTestCharacter) -> void:
	var skeleton := actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	assert(skeleton != null)
	skeleton.force_update_all_bone_transforms()
	var bodies := current.body_shapes(actor)
	var shields := current.shield_shapes(actor)
	assert(bodies.size() > 3 and not shields.is_empty())
	var points := PackedVector2Array([centre(bodies[0]), centre(bodies[3]), centre(shields[0])])
	for point: Vector2 in points:
		compare_armor(actor, point)
	var armor := first_part(actor, &"armor")
	var shield := first_part(actor, &"shield")
	assert(armor != null and shield != null)
	var edges := triangle_points(current, actor, armor, skeleton)
	for point: Vector2 in edges:
		compare_mesh(actor, armor, skeleton, point)
	compare_mesh(actor, shield, skeleton, centre(shields[0]))
	# Compare both algorithms at the translated coordinates, not with an
	# assumed translation-invariant epsilon (the engine's epsilon is relative).
	actor.position = Vector2(5000.0, 5000.0)
	compare_armor(actor, points[0] + actor.position)
	for point: Vector2 in [edges[1], edges[3], edges[4]]:
		compare_mesh(actor, armor, skeleton, point + actor.position)
	actor.position = Vector2.ZERO

func first_part(actor: TerrainTestCharacter, slot: StringName) -> MeshInstance3D:
	var option := actor.editor.part_options[slot] as OptionButton
	var item := StringName(str(option.get_item_metadata(option.selected)))
	var definition: Dictionary = actor.editor._component_definition(slot, item)
	for prefix: String in definition.get("prefixes", []):
		for node: Node in actor.editor.model_root.find_children(prefix + "*", "MeshInstance3D", true, false):
			var part := node as MeshInstance3D
			if part.is_visible_in_tree() and part.mesh != null:
				return part
	return null

func triangle_points(geometry: Variant, actor: TerrainTestCharacter, part: MeshInstance3D, skeleton: Skeleton3D) -> PackedVector2Array:
	var vertices: PackedVector2Array = geometry.posed_points(actor, part, skeleton)
	var offset := 0
	for surface in range(part.mesh.get_surface_count()):
		var arrays := part.mesh.surface_get_arrays(surface)
		var surface_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else surface_vertices.size()
		for triangle in range(0, count - 2, 3):
			var a := vertices[offset + (indices[triangle] if not indices.is_empty() else triangle)]
			var b := vertices[offset + (indices[triangle + 1] if not indices.is_empty() else triangle + 1)]
			var c := vertices[offset + (indices[triangle + 2] if not indices.is_empty() else triangle + 2)]
			if absf((b - a).cross(c - a)) < 0.000001:
				continue
			var middle := (a + b) * 0.5
			var normal := Vector2(-(b - a).y, (b - a).x).normalized()
			return PackedVector2Array([(a + b + c) / 3.0, a, middle, middle + normal * 0.000001,
				middle - normal * 0.000001, middle + normal * 0.001, middle - normal * 0.001])
		offset += surface_vertices.size()
	assert(false, "Need one real nondegenerate projected triangle")
	return PackedVector2Array()

func compare_mesh(actor: TerrainTestCharacter, part: MeshInstance3D, skeleton: Skeleton3D, point: Vector2, query: Variant = null) -> void:
	assert(Time.get_ticks_usec() < deadline)
	if query == null:
		query = current
	var started := Time.get_ticks_usec()
	var expected := frozen.mesh_covers_point(actor, part, skeleton, point)
	old_usec += Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var actual: bool = query.mesh_covers_point(actor, part, skeleton, point)
	new_usec += Time.get_ticks_usec() - started
	assert(actual == expected, "Mesh %s at %s changed coverage" % [str(part.name), str(point)])
	positive_checks += int(expected)
	mesh_checks += 1

func compare_armor(actor: TerrainTestCharacter, point: Vector2) -> void:
	assert(Time.get_ticks_usec() < deadline)
	var started := Time.get_ticks_usec()
	var expected := frozen.armor_at(actor, point, "slash")
	old_usec += Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	var actual := current.armor_at(actor, point, "slash")
	new_usec += Time.get_ticks_usec() - started
	assert(actual == expected, "Full armor protection changed at %s" % str(point))
	armor_checks += 1

func check_topology(actor: TerrainTestCharacter) -> void:
	# Small topology fixture uses the same original camera/projection function;
	# it is not substituted for a real person's collision or performance result.
	var part := MeshInstance3D.new()
	actor.editor.preview_world.add_child(part)
	part.hide()
	var mesh := ArrayMesh.new()
	var right: Vector3 = actor.editor.camera.global_basis.x
	var up: Vector3 = actor.editor.camera.global_basis.y
	for surface in range(3):
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		if surface == 0:
			arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, right, up])
			arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
		elif surface == 1:
			arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([right * 2.0, right * 2.0, right * 3.0,
				right * 2.0 + up, right * 3.0 + up, right * 2.0 + up * 2.0])
		else:
			arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([up * 3.0, up * 3.0, up * 3.0])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	part.mesh = mesh
	var skeleton := actor.editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	var fallback := ClearedSurfaceGeometry.new()
	for displacement: Vector2 in [Vector2.ZERO, Vector2(5000.0, 5000.0)]:
		actor.position = displacement
		var vertices := current.posed_points(actor, part, skeleton)
		var points := triangle_points(current, actor, part, skeleton)
		points.append((vertices[6] + vertices[7] + vertices[8]) / 3.0)
		points.append(vertices[3])
		points.append(vertices[9])
		points.append(vertices[0] + Vector2(1000.0, 1000.0))
		for point: Vector2 in points:
			compare_mesh(actor, part, skeleton, point)
			compare_mesh(actor, part, skeleton, point, fallback)
		assert(fallback._surfaces.is_empty())
	actor.position = Vector2.ZERO
	part.queue_free()

func centre(polygon: PackedVector2Array) -> Vector2:
	var result := Vector2.ZERO
	for point: Vector2 in polygon:
		result += point
	return result / polygon.size()
