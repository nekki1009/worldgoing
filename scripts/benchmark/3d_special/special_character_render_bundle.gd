class_name SpecialCharacterRenderBundle
extends RefCounted

const DefinitionType = preload("res://scripts/benchmark/3d_special/special_visual_definition.gd")

enum Lod { LOD0_FULL, LOD1_REDUCED }

var appearance_key: String = ""
var lod: int = Lod.LOD0_FULL
var skinned_mesh: Mesh
var skinned_material: Material
var rigid_definitions: Dictionary = {}
var rigid_visible: Dictionary = {}
var rigid_cast_shadow: Dictionary = {}
var source_skinned_parts: Array[StringName] = []
var hidden_body_regions: PackedInt32Array = PackedInt32Array()
var skinned_triangles: int = 0
var rigid_triangles: int = 0

func cache_key() -> String:
	return "%s|lod=%d" % [appearance_key, lod]

func render_stats() -> Dictionary:
	var rigid_count: int = 0
	var rigid_surface_count: int = 0
	for slot: int in rigid_definitions.keys():
		if not bool(rigid_visible.get(slot, false)):
			continue
		var definition: SpecialVisualDefinition = rigid_definitions[slot]
		if definition == null or definition.mesh == null:
			continue
		rigid_count += 1
		rigid_surface_count += definition.mesh.get_surface_count()
	return {
		"mesh_instances": (1 if skinned_mesh != null else 0) + rigid_count,
		"surfaces": (1 if skinned_mesh != null else 0) + rigid_surface_count,
		"skinned_meshes": 1 if skinned_mesh != null else 0,
		"rigid_meshes": rigid_count,
		"skinned_triangles": skinned_triangles,
		"rigid_triangles": rigid_triangles,
		"triangles": skinned_triangles + rigid_triangles,
		"lod": lod,
		"source_skinned_parts": source_skinned_parts.duplicate()
	}
