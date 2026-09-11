class_name RigidEquipmentRenderRegistry
extends RefCounted

const DefinitionType = preload("res://scripts/benchmark/3d_special/special_visual_definition.gd")

enum Category { HAIR, HELMET, WEAPON, SHIELD, OTHER }
enum ShadowClass { SMALL, MAJOR }

var source_registry: SpecialCharacterVisualRegistry
var _family_materials: Dictionary = {}

func setup(target_registry: SpecialCharacterVisualRegistry) -> void:
	source_registry = target_registry
	_family_materials.clear()

func resolve(slot: int, equipment_id: StringName) -> SpecialVisualDefinition:
	return source_registry.resolve(slot, equipment_id) if source_registry != null else null

func descriptor(slot: int, equipment_id: StringName) -> Dictionary:
	var definition: SpecialVisualDefinition = resolve(slot, equipment_id)
	if definition == null or definition.mesh == null:
		return {}
	return {
		"equipment_id": equipment_id,
		"slot": slot,
		"mesh": definition.mesh,
		"material": definition.material,
		"shared_material": shared_material_for(slot, equipment_id),
		"category": category_for(slot),
		"shadow_class": shadow_class_for(slot),
		"socket": definition.attachment_socket
	}

func category_for(slot: int) -> StringName:
	match slot:
		DefinitionType.Slot.HAIR:
			return &"HAIR"
		DefinitionType.Slot.HELMET:
			return &"HELMET"
		DefinitionType.Slot.WEAPON:
			return &"WEAPON"
		DefinitionType.Slot.SHIELD:
			return &"SHIELD"
		_:
			return &"OTHER"

func shadow_class_for(slot: int) -> int:
	return ShadowClass.MAJOR if slot in [DefinitionType.Slot.HELMET, DefinitionType.Slot.SHIELD] else ShadowClass.SMALL

func shared_material_for(slot: int, equipment_id: StringName) -> Material:
	var family: StringName = material_family_for(slot)
	if _family_materials.has(family):
		return _family_materials[family]
	var source: SpecialVisualDefinition = resolve(slot, equipment_id)
	var material := StandardMaterial3D.new()
	if source != null and source.material is BaseMaterial3D:
		var source_material := source.material as BaseMaterial3D
		material.albedo_color = source_material.albedo_color
		material.metallic = source_material.metallic
		material.roughness = source_material.roughness
	else:
		material.albedo_color = Color.WHITE
	material.resource_name = "SpecialRigid_%s" % str(family)
	_family_materials[family] = material
	return material

func material_family_for(slot: int) -> StringName:
	match slot:
		DefinitionType.Slot.HAIR:
			return &"HAIR"
		DefinitionType.Slot.HELMET, DefinitionType.Slot.WEAPON:
			return &"METAL"
		DefinitionType.Slot.SHIELD:
			return &"SHIELD"
		_:
			return &"OTHER"

func family_material_count() -> int:
	return _family_materials.size()

func shared_materials() -> Array[Material]:
	var result: Array[Material] = []
	for material: Material in _family_materials.values():
		result.append(material)
	return result

func audit(appearance: SpecialCharacterAppearance) -> Dictionary:
	var result: Dictionary = {}
	if appearance == null:
		return result
	for slot_and_id: Array in [
		[DefinitionType.Slot.HAIR, appearance.hair_id],
		[DefinitionType.Slot.HELMET, appearance.helmet_id],
		[DefinitionType.Slot.WEAPON, appearance.weapon_id],
		[DefinitionType.Slot.SHIELD, appearance.shield_id]
	]:
		var slot: int = slot_and_id[0]
		var equipment_id: StringName = slot_and_id[1]
		if equipment_id.is_empty():
			continue
		var item: Dictionary = descriptor(slot, equipment_id)
		if not item.is_empty():
			result[String(category_for(slot))] = item
	return result
