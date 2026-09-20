extends "res://scripts/tests/mounted_heavy_editor_test.gd"
## Test-only native posed geometry; no production collision or balance changes.
var skinning := preload("res://scripts/terrain_lab/terrain_weapon_collision.gd").new()
var rows: Array[Dictionary] = []

func posed_faces(part: MeshInstance3D, skeleton: Skeleton3D) -> PackedVector3Array:
	var vertices: PackedVector3Array = skinning.posed_vertices(part, skeleton)
	var faces := PackedVector3Array()
	var offset := 0
	for surface in part.mesh.get_surface_count():
		var arrays := part.mesh.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			faces.append_array(vertices.slice(offset, offset + positions.size()))
		else:
			for index: int in indices:
				faces.append(vertices[offset + index])
		offset += positions.size()
	return faces

func intersections(skeleton: Skeleton3D) -> Dictionary:
	var horse := TriangleMesh.new()
	check(horse.create_from_faces(posed_faces(editor.mount_horse.body_mesh, editor.mount_horse.skeleton)), "horse posed triangle tree")
	var parts := {}
	var attachments := {}
	var hit_points := {}
	var tested := 0
	for node: Node in editor.model_root.find_children("Weapon_*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if not part.is_visible_in_tree():
			continue
		var faces := posed_faces(part, skeleton)
		var crossings := 0
		for index in range(0, faces.size(), 3):
			for edge in range(3):
				tested += 1
				var hit := horse.intersect_segment(faces[index + edge], faces[index + (edge + 1) % 3])
				if not hit.is_empty():
					crossings += 1
					if not hit_points.has(str(part.name)):
						hit_points[str(part.name)] = []
					if hit_points[str(part.name)].size() < 4:
						hit_points[str(part.name)].append(str(hit.position))
		if crossings > 0:
			if "Scabbard" in str(part.name):
				attachments[str(part.name)] = crossings
			else:
				parts[str(part.name)] = crossings
	return {"crossing_parts": parts, "baseline_attachment_crossings": attachments, "tested_edges": tested, "hit_points": hit_points,
		"right_hand_world": str(skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("J_Bip_R_Hand")).origin)}

func run() -> void:
	var probe := OS.get_cmdline_user_args().has("--probe")
	var scene := load("res://scenes/ui/HumanCharacter3DEditor.tscn") as PackedScene
	editor = scene.instantiate() as HumanCharacter3DEditor
	root.add_child(editor)
	editor.open()
	for candidate in ["before_arm_clearance/", ""]:
		for body in range(2):
			if probe and (candidate != "" or body != 1):
				continue
			var sex := "male" if body == 0 else "female"
			editor.set_mount_enabled(false)
			editor._load_body_model(body, OUT + "/" + candidate + "candidate_" + sex + ".glb")
			await process_frame
			for slot: StringName in [&"armor", &"cape", &"helmet", &"shield"]:
				editor.select_part_by_id(slot, &"none")
			editor.set_mount_enabled(true)
			editor.select_animation_by_id(&"ride_heavy")
			editor.set_playing(false)
			var skeleton := editor.model_root.find_child("Skeleton3D", true, false) as Skeleton3D
			var weapons: Array[StringName] = [&"longsword_01", &"spear_01", &"axe_01", &"bow_01", &"crossbow_01"]
			var fractions: Array[float] = [0.0, .25, .42, .53, .63, .78, 1.0]
			if candidate != "":
				weapons = [&"longsword_01"]
				fractions = [.53]
			if probe:
				weapons = [&"axe_01"]
				fractions = [.53]
			for weapon: StringName in weapons:
				check(editor.select_part_by_id(&"weapon", weapon), "geometry weapon selected")
				check(editor.select_animation_by_id(&"ride_idle"), "unmodified idle attachment baseline")
				sample(0.0)
				var idle_attachments: Dictionary = intersections(skeleton).baseline_attachment_crossings
				check(editor.select_animation_by_id(&"ride_heavy"), "heavy after baseline")
				for fraction: float in fractions:
					sample(70.0 / 24.0 * fraction)
					var result := intersections(skeleton)
					result.merge({"sex": sex, "weapon": str(weapon), "fraction": fraction, "revision": "failed_original" if candidate != "" else "outward_revision"})
					result["unmodified_ride_idle_attachment_crossings"] = idle_attachments
					rows.append(result)
					check(result.tested_edges > 0, "nonempty posed weapon geometry")
					check(result.baseline_attachment_crossings == idle_attachments, "scabbard intersections no worse than preserved idle")
					check(not result.crossing_parts.is_empty() if candidate != "" else result.crossing_parts.is_empty(), "%s %s %.2f %s: %s" % [sex, weapon, fraction, result.revision, str(result.crossing_parts)])
	var report := {"status": "PASS" if errors.is_empty() else "FAIL", "checks": checks, "failures": errors, "samples": rows,
		"boundary": "HANDHELD ONLY. Actual posed weapon triangle-edge / horse-body triangle intersections; original failed sword is a positive control. Existing idle scabbard crossings are separately recorded and required unchanged, NOT claimed clear. Not a continuous sweep, distance margin, rider/cape collision or enclosed disconnected-component proof."}
	var file := FileAccess.open(OUT + ("/weapon_clearance_probe.json" if probe else "/weapon_clearance.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	editor.queue_free()
	await process_frame
	print("MOUNTED_CLEARANCE_", report.status, " ", checks)
	quit(0 if errors.is_empty() else 1)
