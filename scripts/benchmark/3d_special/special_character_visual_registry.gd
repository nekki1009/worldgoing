class_name SpecialCharacterVisualRegistry
extends RefCounted

const DefinitionType = preload("res://scripts/benchmark/3d_special/special_visual_definition.gd")
const MeshBuilderType = preload("res://scripts/benchmark/3d_special/special_character_mesh_builder.gd")

var definitions: Array[SpecialVisualDefinition] = []

func _init() -> void:
	_build_default_registry()

func resolve(slot: int, visual_id: StringName) -> SpecialVisualDefinition:
	for definition: SpecialVisualDefinition in definitions:
		if definition.slot == slot and definition.visual_id == visual_id:
			return definition
	return null

func ids_for_slot(slot: int) -> Array[StringName]:
	var result: Array[StringName] = []
	for definition: SpecialVisualDefinition in definitions:
		if definition.slot == slot:
			result.append(definition.visual_id)
	return result

func validate_appearance(appearance: SpecialCharacterAppearance) -> bool:
	return (
		_resolve_required(DefinitionType.Slot.BODY, appearance.body_id) != null
		and _resolve_required(DefinitionType.Slot.HEAD, appearance.head_id) != null
		and (appearance.hair_id.is_empty() or _resolve_required(DefinitionType.Slot.HAIR, appearance.hair_id) != null)
		and (appearance.armor_id.is_empty() or _resolve_required(DefinitionType.Slot.ARMOR, appearance.armor_id) != null)
		and (appearance.helmet_id.is_empty() or _resolve_required(DefinitionType.Slot.HELMET, appearance.helmet_id) != null)
		and (appearance.weapon_id.is_empty() or _resolve_required(DefinitionType.Slot.WEAPON, appearance.weapon_id) != null)
		and (appearance.shield_id.is_empty() or _resolve_required(DefinitionType.Slot.SHIELD, appearance.shield_id) != null)
	)

func material_count() -> int:
	var unique_materials: Array[Material] = []
	for definition: SpecialVisualDefinition in definitions:
		if definition.material != null and not unique_materials.has(definition.material):
			unique_materials.append(definition.material)
	return unique_materials.size()

func _resolve_required(slot: int, visual_id: StringName) -> SpecialVisualDefinition:
	return resolve(slot, visual_id)

func _build_default_registry() -> void:
	var body_material := _material(Color("d2a17e"), 0.88)
	var skin_definition := DefinitionType.new()
	skin_definition.slot = DefinitionType.Slot.BODY
	skin_definition.visual_id = &"human_body_01"
	skin_definition.region_meshes = MeshBuilderType.build_body_region_meshes()
	skin_definition.material = body_material
	_register(skin_definition)

	var head_definition := DefinitionType.new()
	head_definition.slot = DefinitionType.Slot.HEAD
	head_definition.visual_id = &"head_01"
	head_definition.mesh = MeshBuilderType.build_head_mesh()
	head_definition.material = body_material
	_register(head_definition)

	var short_hair := DefinitionType.new()
	short_hair.slot = DefinitionType.Slot.HAIR
	short_hair.visual_id = &"hair_short_01"
	short_hair.mesh = MeshBuilderType.build_hair_mesh(short_hair.visual_id)
	short_hair.material = _material(Color("35241f"), 0.92)
	_register(short_hair)
	var long_hair := DefinitionType.new()
	long_hair.slot = DefinitionType.Slot.HAIR
	long_hair.visual_id = &"hair_long_01"
	long_hair.mesh = MeshBuilderType.build_hair_mesh(long_hair.visual_id)
	long_hair.material = _material(Color("7c4b2d"), 0.92)
	_register(long_hair)

	_register(_armor(&"cloth_01", Color("5e8964"), PackedInt32Array([DefinitionType.BodyRegion.TORSO])))
	_register(_armor(&"leather_01", Color("7b4c2f"), PackedInt32Array([
		DefinitionType.BodyRegion.TORSO, DefinitionType.BodyRegion.ARMS
	])))
	_register(_armor(&"plate_01", Color("77828f"), PackedInt32Array([
		DefinitionType.BodyRegion.TORSO, DefinitionType.BodyRegion.ARMS, DefinitionType.BodyRegion.LEGS
	])))

	var helmet := DefinitionType.new()
	helmet.slot = DefinitionType.Slot.HELMET
	helmet.visual_id = &"helmet_01"
	helmet.mesh = MeshBuilderType.build_helmet_mesh()
	helmet.material = _material(Color("4c5663"), 0.76)
	helmet.attachment_socket = &"head_socket"
	helmet.hides_hair = true
	_register(helmet)

	var sword := DefinitionType.new()
	sword.slot = DefinitionType.Slot.WEAPON
	sword.visual_id = &"sword_01"
	sword.mesh = MeshBuilderType.build_sword_mesh()
	sword.material = _material(Color("c8d0d4"), 0.60)
	sword.attachment_socket = &"weapon_socket_r"
	sword.equipment_kind = &"sword"
	_register(sword)

	var shield := DefinitionType.new()
	shield.slot = DefinitionType.Slot.SHIELD
	shield.visual_id = &"shield_01"
	shield.mesh = MeshBuilderType.build_shield_mesh()
	shield.material = _material(Color("415d87"), 0.72)
	shield.attachment_socket = &"shield_socket_l"
	shield.equipment_kind = &"shield"
	_register(shield)

func _armor(visual_id: StringName, color: Color, hidden_regions: PackedInt32Array) -> SpecialVisualDefinition:
	var definition := DefinitionType.new()
	definition.slot = DefinitionType.Slot.ARMOR
	definition.visual_id = visual_id
	definition.mesh = MeshBuilderType.build_armor_mesh(visual_id)
	definition.material = _material(color, 0.82)
	definition.hide_body_regions = hidden_regions
	return definition

func _material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _register(definition: SpecialVisualDefinition) -> void:
	definitions.append(definition)
