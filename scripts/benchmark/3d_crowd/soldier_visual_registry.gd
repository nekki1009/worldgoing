class_name SoldierVisualRegistry
extends RefCounted

const ArchetypeType = preload("res://scripts/benchmark/3d_crowd/soldier_visual_archetype.gd")
const MeshBuilderType = preload("res://scripts/benchmark/3d_crowd/crowd_soldier_mesh_builder.gd")

const LIGHT_INFANTRY: int = 0
const HEAVY_INFANTRY: int = 1
const SPEARMAN: int = 2
const SWORD_SHIELD: int = 3
const ARCHETYPE_COUNT: int = 4

var entries: Array[SoldierVisualArchetype] = []
var placeholder_mesh: ArrayMesh

func _init() -> void:
	entries = [
		ArchetypeType.new(
			LIGHT_INFANTRY, &"LIGHT_INFANTRY", "Light Infantry",
			Color("4f9b68"), Color("c5d2a5")
		),
		ArchetypeType.new(
			HEAVY_INFANTRY, &"HEAVY_INFANTRY", "Heavy Infantry",
			Color("65707b"), Color("bdc4c8")
		),
		ArchetypeType.new(
			SPEARMAN, &"SPEARMAN", "Spearman",
			Color("b47a45"), Color("e1c185")
		),
		ArchetypeType.new(
			SWORD_SHIELD, &"SWORD_SHIELD", "Sword & Shield",
			Color("4d6fa9"), Color("d4d9e4")
		)
	]
	entries[LIGHT_INFANTRY].body_width = 0.42
	entries[LIGHT_INFANTRY].body_height = 0.72
	entries[LIGHT_INFANTRY].body_depth = 0.27
	entries[LIGHT_INFANTRY].head_size = 0.28
	entries[LIGHT_INFANTRY].weapon_length = 0.70
	entries[LIGHT_INFANTRY].equipment_variant_count = 3

	entries[HEAVY_INFANTRY].body_width = 0.58
	entries[HEAVY_INFANTRY].body_height = 0.92
	entries[HEAVY_INFANTRY].body_depth = 0.38
	entries[HEAVY_INFANTRY].head_size = 0.36
	entries[HEAVY_INFANTRY].weapon_length = 0.82
	entries[HEAVY_INFANTRY].equipment_variant_count = 3

	entries[SPEARMAN].body_width = 0.46
	entries[SPEARMAN].body_height = 0.80
	entries[SPEARMAN].body_depth = 0.30
	entries[SPEARMAN].head_size = 0.30
	entries[SPEARMAN].weapon_kind = &"spear"
	entries[SPEARMAN].weapon_length = 2.05
	entries[SPEARMAN].equipment_variant_count = 2

	entries[SWORD_SHIELD].body_width = 0.49
	entries[SWORD_SHIELD].body_height = 0.82
	entries[SWORD_SHIELD].body_depth = 0.32
	entries[SWORD_SHIELD].head_size = 0.31
	entries[SWORD_SHIELD].weapon_length = 0.78
	entries[SWORD_SHIELD].has_shield = true
	entries[SWORD_SHIELD].shield_width = 0.44
	entries[SWORD_SHIELD].shield_height = 0.58
	entries[SWORD_SHIELD].equipment_variant_count = 3

	for entry: SoldierVisualArchetype in entries:
		entry.mid_mesh = MeshBuilderType.build_mid(entry)
		entry.far_mesh = MeshBuilderType.build_far(entry)
	placeholder_mesh = MeshBuilderType.build()

func get_archetype(archetype_id: int) -> SoldierVisualArchetype:
	return entries[clampi(archetype_id, 0, entries.size() - 1)]

func mid_meshes() -> Array[Mesh]:
	var result: Array[Mesh] = []
	for entry: SoldierVisualArchetype in entries:
		result.append(entry.mid_mesh)
	return result

func far_meshes() -> Array[Mesh]:
	var result: Array[Mesh] = []
	for entry: SoldierVisualArchetype in entries:
		result.append(entry.far_mesh)
	return result
