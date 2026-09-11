extends SceneTree

const PATHS: Array[String] = [
	"res://assets/characters/human/q35/standard_anime_male_character_pack.glb",
	"res://assets/characters/human/q35/standard_anime_female_character_pack.glb",
	"res://assets/mounts/horse/standard_horse_pack.glb",
]

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	create_timer(10.0).timeout.connect(_on_timeout)
	for path in PATHS:
		var options := ConfigFile.new()
		assert(options.load(path + ".import") == OK)
		assert(options.get_value("params", "meshes/ensure_tangents") == true)
		var packed := load(path) as PackedScene
		assert(packed != null, "Native import cache must load: " + path)
		var instance := packed.instantiate()
		var normal_surfaces := 0
		var fixed_surfaces := 0
		var morph_targets := 0
		for node in instance.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = node.mesh
			var needs_uv := str(node.name) in ["Cape_Travel_01_Main", "Helmet_Mingguang_01_WhitePlume_Fittings", "Weapon_Bow_01_String", "Mount_Stirrups_01_L", "Mount_Stirrups_01_R"]
			for surface in mesh.get_surface_count():
				var material := mesh.surface_get_material(surface) as BaseMaterial3D
				var normal_mapped := material != null and material.normal_enabled
				if not needs_uv and not normal_mapped:
					continue
				var arrays := mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
				assert(uv.size() == vertices.size(), str(node.name) + " UVs missing")
				assert(tangents.size() == vertices.size() * 4, str(node.name) + " tangents missing")
				for value in tangents:
					assert(is_finite(value), str(node.name) + " invalid tangent")
				if normal_mapped:
					assert(material.normal_texture != null)
					for i in vertices.size():
						var tangent := Vector3(tangents[i * 4], tangents[i * 4 + 1], tangents[i * 4 + 2])
						assert(absf(tangent.length() - 1.0) < .002)
					normal_surfaces += 1
				if needs_uv:
					fixed_surfaces += 1
					var shapes: Array = mesh.surface_get_blend_shape_arrays(surface)
					assert(shapes.size() == mesh.get_blend_shape_count() and not shapes.is_empty())
					for shape in shapes:
						var positions: PackedVector3Array = shape[Mesh.ARRAY_VERTEX]
						assert(positions.size() == vertices.size())
						var morph_tangents: PackedFloat32Array = shape[Mesh.ARRAY_TANGENT]
						assert(morph_tangents.size() == tangents.size())
						for value in morph_tangents:
							assert(is_finite(value))
					morph_targets += shapes.size()
		var horse: bool = "horse" in path
		assert(fixed_surfaces == (4 if horse else 7))
		assert(morph_targets == (12 if horse else 613))
		assert(normal_surfaces == (0 if horse else 75 if "female" in path else 78))
		print("MORPH_UV_NATIVE_IMPORT_PASS ", path, " surfaces=", fixed_surfaces, " morphs=", morph_targets, " normal_mapped=", normal_surfaces)
		instance.free()
	quit(0)

func _on_timeout() -> void:
	push_error("Morph UV import assertions did not complete")
	quit(1)
