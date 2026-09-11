class_name SpecialCharacterRenderBundleCache
extends RefCounted

const AppearanceType = preload("res://scripts/benchmark/3d_special/special_character_appearance.gd")
const DefinitionType = preload("res://scripts/benchmark/3d_special/special_visual_definition.gd")
const BundleType = preload("res://scripts/benchmark/3d_special/special_character_render_bundle.gd")

var registry: SpecialCharacterVisualRegistry
var build_count: int = 0
var cache_hits: int = 0
var cache_misses: int = 0
var _bundles: Dictionary = {}
var _shared_skinned_material: StandardMaterial3D

func setup(target_registry: SpecialCharacterVisualRegistry) -> void:
	registry = target_registry
	if _shared_skinned_material != null:
		return
	_shared_skinned_material = StandardMaterial3D.new()
	_shared_skinned_material.albedo_color = Color.WHITE
	_shared_skinned_material.vertex_color_use_as_albedo = true
	_shared_skinned_material.roughness = 0.82

func prewarm(appearances: Array[SpecialCharacterAppearance]) -> void:
	for appearance: SpecialCharacterAppearance in appearances:
		for lod: int in [BundleType.Lod.LOD0_FULL, BundleType.Lod.LOD1_REDUCED]:
			get_or_build(appearance, lod)

func get_or_build(appearance: SpecialCharacterAppearance, lod: int) -> SpecialCharacterRenderBundle:
	var key: String = _key_for(appearance, lod)
	var existing: SpecialCharacterRenderBundle = _bundles.get(key)
	if existing != null:
		cache_hits += 1
		return existing
	cache_misses += 1
	var built: SpecialCharacterRenderBundle = _build_bundle(appearance, lod)
	if built != null:
		_bundles[key] = built
		build_count += 1
	return built

func lookup(appearance: SpecialCharacterAppearance, lod: int) -> SpecialCharacterRenderBundle:
	var bundle: SpecialCharacterRenderBundle = _bundles.get(_key_for(appearance, lod))
	if bundle != null:
		cache_hits += 1
	else:
		cache_misses += 1
	return bundle

func has(appearance: SpecialCharacterAppearance, lod: int) -> bool:
	return _bundles.has(_key_for(appearance, lod))

func bundle_count() -> int:
	return _bundles.size()

func shared_material_count() -> int:
	return 1 if _shared_skinned_material != null else 0

func _key_for(appearance: SpecialCharacterAppearance, lod: int) -> String:
	return "%s|lod=%d" % [appearance.key(), lod]

func _build_bundle(
	appearance: SpecialCharacterAppearance,
	lod: int
) -> SpecialCharacterRenderBundle:
	if registry == null or appearance == null or not registry.validate_appearance(appearance):
		return null
	var body: SpecialVisualDefinition = registry.resolve(DefinitionType.Slot.BODY, appearance.body_id)
	var head: SpecialVisualDefinition = registry.resolve(DefinitionType.Slot.HEAD, appearance.head_id)
	var hair: SpecialVisualDefinition = registry.resolve(DefinitionType.Slot.HAIR, appearance.hair_id)
	var armor: SpecialVisualDefinition = registry.resolve(DefinitionType.Slot.ARMOR, appearance.armor_id)
	var helmet: SpecialVisualDefinition = registry.resolve(DefinitionType.Slot.HELMET, appearance.helmet_id)
	var weapon: SpecialVisualDefinition = registry.resolve(DefinitionType.Slot.WEAPON, appearance.weapon_id)
	var shield: SpecialVisualDefinition = registry.resolve(DefinitionType.Slot.SHIELD, appearance.shield_id)
	var bundle := BundleType.new()
	bundle.appearance_key = appearance.key()
	bundle.lod = lod
	bundle.skinned_material = _shared_skinned_material
	bundle.hidden_body_regions = armor.hide_body_regions if armor != null else PackedInt32Array()
	var skinned_meshes: Array[Mesh] = []
	var skinned_materials: Array[Material] = []
	var skinned_names: Array[StringName] = []
	if body != null:
		for region_index: int in range(body.region_meshes.size()):
			if region_index == DefinitionType.BodyRegion.HEAD:
				continue
			if armor != null and armor.hide_body_regions.has(region_index):
				continue
			var region_mesh: Mesh = body.region_meshes[region_index]
			if region_mesh != null:
				skinned_meshes.append(region_mesh)
				skinned_materials.append(body.material)
				skinned_names.append(_body_region_name(region_index))
	if head != null and head.mesh != null:
		skinned_meshes.append(head.mesh)
		skinned_materials.append(head.material)
		skinned_names.append(&"HEAD")
	if armor != null and armor.mesh != null:
		skinned_meshes.append(armor.mesh)
		skinned_materials.append(armor.material)
	skinned_names.append(&"ARMOR")
	bundle.source_skinned_parts = skinned_names
	bundle.skinned_mesh = _merge_skinned_meshes(skinned_meshes, skinned_materials)
	bundle.skinned_triangles = _triangle_count(bundle.skinned_mesh)

	_register_rigid(bundle, DefinitionType.Slot.HAIR, hair, not appearance.hair_id.is_empty())
	_register_rigid(bundle, DefinitionType.Slot.HELMET, helmet, not appearance.helmet_id.is_empty())
	_register_rigid(bundle, DefinitionType.Slot.WEAPON, weapon, not appearance.weapon_id.is_empty())
	_register_rigid(bundle, DefinitionType.Slot.SHIELD, shield, not appearance.shield_id.is_empty())
	if helmet != null and helmet.hides_hair:
		bundle.rigid_visible[DefinitionType.Slot.HAIR] = false
	if lod == BundleType.Lod.LOD1_REDUCED and appearance.hair_id == &"hair_long_01":
		# LOD1 keeps the socket contract but removes the expensive optional hair.
		bundle.rigid_visible[DefinitionType.Slot.HAIR] = false
	for slot: int in bundle.rigid_definitions.keys():
		bundle.rigid_cast_shadow[slot] = lod == BundleType.Lod.LOD0_FULL
	bundle.rigid_triangles = _rigid_triangle_count(bundle)
	return bundle

func _register_rigid(
	bundle: SpecialCharacterRenderBundle,
	slot: int,
	definition: SpecialVisualDefinition,
	requested: bool
) -> void:
	bundle.rigid_definitions[slot] = definition
	bundle.rigid_visible[slot] = requested and definition != null

func _merge_skinned_meshes(meshes: Array[Mesh], materials: Array[Material]) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	for mesh_index: int in range(meshes.size()):
		var mesh: Mesh = meshes[mesh_index]
		if mesh == null:
			continue
		var source_color := Color.WHITE
		if mesh_index < materials.size() and materials[mesh_index] is BaseMaterial3D:
			source_color = (materials[mesh_index] as BaseMaterial3D).albedo_color
		for surface_index: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface_index)
			var source_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if source_vertices.is_empty():
				continue
			var vertex_offset: int = vertices.size()
			for vertex: Vector3 in source_vertices:
				vertices.append(vertex)
				colors.append(source_color)
			var source_normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for normal: Vector3 in source_normals:
				normals.append(normal)
			var source_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			for uv: Vector2 in source_uvs:
				uvs.append(uv)
			var source_bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			for bone: int in source_bones:
				bones.append(bone)
			var source_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			for weight: float in source_weights:
				weights.append(weight)
			var source_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if source_indices.is_empty():
				for vertex_index: int in range(source_vertices.size()):
					indices.append(vertex_offset + vertex_index)
			else:
				for index_value: int in source_indices:
					indices.append(vertex_offset + index_value)
	if vertices.is_empty() or bones.size() != vertices.size() * 4 or weights.size() != vertices.size() * 4:
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = indices
	var merged := ArrayMesh.new()
	merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return merged

func _rigid_triangle_count(bundle: SpecialCharacterRenderBundle) -> int:
	var total := 0
	for slot: int in bundle.rigid_definitions.keys():
		if not bool(bundle.rigid_visible.get(slot, false)):
			continue
		var definition: SpecialVisualDefinition = bundle.rigid_definitions[slot]
		if definition != null:
			total += _triangle_count(definition.mesh)
	return total

func _triangle_count(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for surface_index: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		var index_data: Variant = arrays[Mesh.ARRAY_INDEX]
		if index_data is PackedInt32Array and not (index_data as PackedInt32Array).is_empty():
			total += (index_data as PackedInt32Array).size() / 3
		else:
			var vertices: Variant = arrays[Mesh.ARRAY_VERTEX]
			if vertices is PackedVector3Array:
				total += (vertices as PackedVector3Array).size() / 3
	return total

func _body_region_name(region: int) -> StringName:
	match region:
		DefinitionType.BodyRegion.TORSO:
			return &"TORSO"
		DefinitionType.BodyRegion.ARMS:
			return &"ARMS"
		DefinitionType.BodyRegion.HANDS:
			return &"HANDS"
		DefinitionType.BodyRegion.LEGS:
			return &"LEGS"
		_:
			return &"FEET"
