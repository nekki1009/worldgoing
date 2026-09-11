extends SceneTree

const AppearanceType = preload("res://scripts/benchmark/3d_special/special_character_appearance.gd")
const RegistryType = preload("res://scripts/benchmark/3d_special/special_character_visual_registry.gd")
const DefinitionType = preload("res://scripts/benchmark/3d_special/special_visual_definition.gd")
const RigidRegistryType = preload("res://scripts/benchmark/3d_special/rigid_equipment_render_registry.gd")
const BatchType = preload("res://scripts/benchmark/3d_special/special_rigid_equipment_batch_renderer.gd")
const VisualType = preload("res://scripts/benchmark/3d_special/special_character_visual_3d.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var registry: SpecialCharacterVisualRegistry = RegistryType.new()
	var rigid_registry: RigidEquipmentRenderRegistry = RigidRegistryType.new()
	rigid_registry.setup(registry)
	var root := Node3D.new()
	get_root().add_child(root)
	var actors: Array[SpecialCharacterVisual3D] = []
	for actor_index: int in range(2):
		var actor: SpecialCharacterVisual3D = VisualType.new()
		root.add_child(actor)
		actor.setup(registry)
		var appearance := AppearanceType.new()
		appearance.armor_id = &"plate_01" if actor_index == 0 else &"leather_01"
		appearance.hair_id = &"hair_short_01" if actor_index == 0 else &"hair_long_01"
		appearance.weapon_id = &"sword_01"
		appearance.shield_id = &"shield_01" if actor_index == 0 else &""
		assert(actor.set_appearance(appearance), "Batch contract appearance was rejected")
		actor.visible = true
		actors.append(actor)
	var batch: SpecialRigidEquipmentBatchRenderer = BatchType.new()
	root.add_child(batch)
	batch.setup(rigid_registry, 4)
	batch.configure(true, true, 0, 24, 1)
	for actor_index: int in range(actors.size()):
		batch.bind_actor(actor_index, actors[actor_index])
	batch.update_transforms()
	var stats: Dictionary = batch.stats()
	assert(stats["active_instances"] == 5, "Stable rigid batch lost an equipment instance")
	assert(stats["nodes"] <= 4, "Rigid batch created one render node per equipment instance")
	assert(batch.last_buffer_upload_calls <= stats["nodes"], "Bulk upload did not batch by render group")
	var sword_descriptor_a: Dictionary = rigid_registry.descriptor(DefinitionType.Slot.WEAPON, &"sword_01")
	var sword_descriptor_b: Dictionary = rigid_registry.descriptor(DefinitionType.Slot.WEAPON, &"sword_01")
	assert(sword_descriptor_a.get("mesh") == sword_descriptor_b.get("mesh"), "Sword mesh resource lookup is not stable")
	assert(sword_descriptor_a.get("material") == sword_descriptor_b.get("material"), "Sword material resource lookup is not stable")
	print("SPECIAL_RIGID_BATCH_CONTRACT_PASS: active_instances=%d batch_nodes=%d buffer_uploads=%d shared_registry=true stable_slots=true" % [
		int(stats["active_instances"]), int(stats["nodes"]), batch.last_buffer_upload_calls
	])
	root.queue_free()
	await process_frame
	quit(0)
