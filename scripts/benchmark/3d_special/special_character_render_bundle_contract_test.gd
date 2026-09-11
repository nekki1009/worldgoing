extends SceneTree

const AppearanceType = preload("res://scripts/benchmark/3d_special/special_character_appearance.gd")
const DefinitionType = preload("res://scripts/benchmark/3d_special/special_visual_definition.gd")
const RegistryType = preload("res://scripts/benchmark/3d_special/special_character_visual_registry.gd")
const CacheType = preload("res://scripts/benchmark/3d_special/special_character_render_bundle_cache.gd")
const BundleType = preload("res://scripts/benchmark/3d_special/special_character_render_bundle.gd")
const VisualType = preload("res://scripts/benchmark/3d_special/special_character_visual_3d.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var registry: SpecialCharacterVisualRegistry = RegistryType.new()
	var cache: SpecialCharacterRenderBundleCache = CacheType.new()
	cache.setup(registry)
	var appearance := AppearanceType.new()
	appearance.armor_id = &"plate_01"
	appearance.helmet_id = &"helmet_01"
	appearance.weapon_id = &"sword_01"
	appearance.shield_id = &"shield_01"
	var same_key := appearance.duplicate_data()
	var different_key := appearance.duplicate_data()
	different_key.material_variant = 1
	cache.prewarm([appearance, same_key, different_key])
	var full: SpecialCharacterRenderBundle = cache.lookup(appearance, BundleType.Lod.LOD0_FULL)
	var same_bundle: SpecialCharacterRenderBundle = cache.lookup(same_key, BundleType.Lod.LOD0_FULL)
	var variant_bundle: SpecialCharacterRenderBundle = cache.lookup(different_key, BundleType.Lod.LOD0_FULL)
	assert(full != null and same_bundle == full, "AppearanceKey did not reuse the cached bundle")
	assert(variant_bundle != null and variant_bundle != full, "material_variant did not participate in AppearanceKey")
	assert(full.skinned_mesh.get_surface_count() == 1, "Skinned bundle did not compile to one surface")
	assert(full.skinned_mesh.surface_get_arrays(0)[Mesh.ARRAY_BONES] is PackedInt32Array, "Merged skin weights are missing")
	assert(full.skinned_mesh.surface_get_arrays(0)[Mesh.ARRAY_WEIGHTS] is PackedFloat32Array, "Merged skin weights are missing")
	assert(full.skinned_material == variant_bundle.skinned_material, "Skinned bundles did not share the compiled material")
	var sword_definition: SpecialVisualDefinition = registry.resolve(DefinitionType.Slot.WEAPON, &"sword_01")
	assert(full.rigid_definitions[DefinitionType.Slot.WEAPON].mesh == sword_definition.mesh, "Rigid sword mesh was duplicated")
	var long_hair := AppearanceType.new()
	long_hair.armor_id = &"leather_01"
	long_hair.hair_id = &"hair_long_01"
	long_hair.weapon_id = &"sword_01"
	var reduced: SpecialCharacterRenderBundle = cache.get_or_build(long_hair, BundleType.Lod.LOD1_REDUCED)
	assert(not bool(reduced.rigid_visible.get(DefinitionType.Slot.HAIR, true)), "LOD1 kept expensive long hair")
	assert(not bool(reduced.rigid_cast_shadow.get(DefinitionType.Slot.WEAPON, true)), "LOD1 kept weapon shadow")

	var actor: SpecialCharacterVisual3D = VisualType.new()
	get_root().add_child(actor)
	actor.setup(registry)
	assert(actor.set_appearance(appearance), "Bundle test appearance was rejected")
	assert(actor.apply_render_bundle(full), "Actor rejected a compatible RenderBundle")
	await process_frame
	var stats: Dictionary = actor.get_render_stats(true)
	assert(stats["skinned_meshes"] == 1, "Runtime bundle did not expose one skinned MeshInstance")
	assert(actor.get_socket_bone_name(&"weapon_socket_r") == &"weapon_socket_r", "Bundle changed weapon socket contract")
	assert(actor.get_socket_bone_name(&"shield_socket_l") == &"shield_socket_l", "Bundle changed shield socket contract")
	var result_format: String = (
		"SPECIAL_RENDER_BUNDLE_CONTRACT_PASS: bundles=%d surfaces=%d skinned_meshes=%d shared_material=true "
		+ "socket_contract=true lod1_long_hair_hidden=true"
	)
	print(result_format % [cache.bundle_count(), full.skinned_mesh.get_surface_count(), stats["skinned_meshes"]])
	actor.queue_free()
	await process_frame
	quit(0)
