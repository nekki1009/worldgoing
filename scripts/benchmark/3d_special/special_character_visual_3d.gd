class_name SpecialCharacterVisual3D
extends Node3D

const HumanRigType = preload("res://scripts/benchmark/3d_crowd/human_rig_v1.gd")
const AppearanceType = preload("res://scripts/benchmark/3d_special/special_character_appearance.gd")
const DefinitionType = preload("res://scripts/benchmark/3d_special/special_visual_definition.gd")
const RegistryType = preload("res://scripts/benchmark/3d_special/special_character_visual_registry.gd")
const AnimationLibraryType = preload("res://scripts/benchmark/3d_special/special_human_animation_library.gd")
const AnimatorType = preload("res://scripts/benchmark/3d_special/special_character_animator.gd")
const RenderBundleType = preload("res://scripts/benchmark/3d_special/special_character_render_bundle.gd")
const RigidRegistryType = preload("res://scripts/benchmark/3d_special/rigid_equipment_render_registry.gd")
const ShadowBudgetType = preload("res://scripts/benchmark/3d_special/special_shadow_budget.gd")

var registry: SpecialCharacterVisualRegistry
var shared_animation_library: AnimationLibrary
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var animator: SpecialCharacterAnimator
var skin: Skin

var body_module: Node3D
var head_module: Node3D
var hair_module: Node3D
var armor_module: Node3D
var helmet_module: Node3D
var cape_module: Node3D
var weapon_module: Node3D
var shield_module: Node3D
var body_regions: Array[MeshInstance3D] = []
var head_mesh_instance: MeshInstance3D
var armor_mesh_instance: MeshInstance3D
var hair_mesh_instance: MeshInstance3D
var helmet_mesh_instance: MeshInstance3D
var weapon_mesh_instance: MeshInstance3D
var shield_mesh_instance: MeshInstance3D
var render_bundle_module: Node3D
var render_bundle_mesh_instance: MeshInstance3D
var socket_attachments: Dictionary = {}
var active_render_bundle: SpecialCharacterRenderBundle

var current_appearance: SpecialCharacterAppearance = AppearanceType.new()
var soldier_id: int = -1
var current_animation_state: int = 0
var current_animation_time: float = 0.0
var current_animation_phase: float = 0.0
var is_ready_for_visuals: bool = false
var shadows_enabled: bool = true
var equipment_visible: bool = true
var rigid_equipment_batched: bool = false
var rigid_material_consolidated: bool = false
var _rigid_material_appearance_key: String = ""
var shadow_budget_mode: int = ShadowBudgetType.Mode.ALL
var shadow_budget_rank: int = 0
var max_full_shadow_actors: int = 24

func setup(
	target_registry: SpecialCharacterVisualRegistry = null,
	target_animation_library: AnimationLibrary = null
) -> void:
	registry = target_registry if target_registry != null else RegistryType.new()
	shared_animation_library = (
		target_animation_library
		if target_animation_library != null
		else AnimationLibraryType.build_library()
	)
	_build_character_nodes()
	set_appearance(current_appearance)
	is_ready_for_visuals = true

func set_appearance(appearance: SpecialCharacterAppearance) -> bool:
	if appearance == null or registry == null or not registry.validate_appearance(appearance):
		return false
	if active_render_bundle != null:
		set_render_bundle(null)
	current_appearance = appearance.duplicate_data()
	_rigid_material_appearance_key = ""
	if skeleton == null:
		return true

	var body_definition := registry.resolve(DefinitionType.Slot.BODY, current_appearance.body_id)
	var head_definition := registry.resolve(DefinitionType.Slot.HEAD, current_appearance.head_id)
	var hair_definition := registry.resolve(DefinitionType.Slot.HAIR, current_appearance.hair_id)
	var armor_definition := registry.resolve(DefinitionType.Slot.ARMOR, current_appearance.armor_id)
	var helmet_definition := registry.resolve(DefinitionType.Slot.HELMET, current_appearance.helmet_id)
	var weapon_definition := registry.resolve(DefinitionType.Slot.WEAPON, current_appearance.weapon_id)
	var shield_definition := registry.resolve(DefinitionType.Slot.SHIELD, current_appearance.shield_id)
	if not _definitions_are_compatible([
		body_definition, head_definition, hair_definition, armor_definition,
		helmet_definition, weapon_definition, shield_definition
	]):
		return false

	_apply_body(body_definition)
	_apply_head(head_definition)
	_apply_armor(armor_definition)
	_apply_rigid(hair_mesh_instance, hair_definition, not current_appearance.hair_id.is_empty())
	_apply_rigid(helmet_mesh_instance, helmet_definition, not current_appearance.helmet_id.is_empty())
	_apply_rigid(weapon_mesh_instance, weapon_definition, not current_appearance.weapon_id.is_empty())
	_apply_rigid(shield_mesh_instance, shield_definition, not current_appearance.shield_id.is_empty())
	var helmet_hides_hair: bool = (
		current_appearance.helmet_id != &""
	) or current_appearance.hair_visibility_mode == AppearanceType.HairVisibilityMode.HIDDEN_BY_HELMET
	hair_mesh_instance.visible = hair_mesh_instance.visible and not helmet_hides_hair
	return true

func apply_render_bundle(bundle: SpecialCharacterRenderBundle) -> bool:
	if bundle == null or bundle.skinned_mesh == null or skeleton == null:
		return false
	active_render_bundle = bundle
	_rigid_material_appearance_key = ""
	render_bundle_mesh_instance.mesh = bundle.skinned_mesh
	render_bundle_mesh_instance.material_override = bundle.skinned_material
	render_bundle_module.visible = true
	render_bundle_mesh_instance.visible = true
	body_module.visible = false
	head_module.visible = false
	armor_module.visible = false
	_apply_rigid(
		hair_mesh_instance,
		bundle.rigid_definitions.get(DefinitionType.Slot.HAIR),
		bool(bundle.rigid_visible.get(DefinitionType.Slot.HAIR, false))
	)
	_apply_rigid(
		get("helmet_mesh_instance") as MeshInstance3D,
		bundle.rigid_definitions.get(DefinitionType.Slot.HELMET),
		bool(bundle.rigid_visible.get(DefinitionType.Slot.HELMET, false))
	)
	_apply_rigid(
		weapon_mesh_instance,
		bundle.rigid_definitions.get(DefinitionType.Slot.WEAPON),
		bool(bundle.rigid_visible.get(DefinitionType.Slot.WEAPON, false))
	)
	_apply_rigid(
		shield_mesh_instance,
		bundle.rigid_definitions.get(DefinitionType.Slot.SHIELD),
		bool(bundle.rigid_visible.get(DefinitionType.Slot.SHIELD, false))
	)
	_apply_bundle_shadow_state()
	return true

func set_render_bundle(bundle: SpecialCharacterRenderBundle) -> void:
	active_render_bundle = bundle
	if bundle == null:
		render_bundle_module.visible = false
		render_bundle_mesh_instance.visible = false
		body_module.visible = true
		head_module.visible = true
		armor_module.visible = true
		return
	apply_render_bundle(bundle)

func apply_animation_state(next_state: int, animation_time: float, animation_phase: float = 0.0) -> void:
	current_animation_state = next_state
	current_animation_time = animation_time
	current_animation_phase = animation_phase
	if animator != null:
		animator.apply_state(next_state, animation_time, animation_phase)

func apply_view_state(
	next_soldier_id: int,
	world_transform: Transform3D,
	appearance: SpecialCharacterAppearance,
	next_state: int,
	next_animation_time: float,
	next_animation_phase: float = 0.0
) -> bool:
	soldier_id = next_soldier_id
	global_transform = world_transform
	if not set_appearance(appearance):
		return false
	apply_animation_state(next_state, next_animation_time, next_animation_phase)
	return true

func get_character_node_count() -> int:
	return _count_nodes(self)

func get_skeleton_count() -> int:
	return 1 if skeleton != null else 0

func get_skinned_mesh_count() -> int:
	return _count_skinned_meshes(self)

func get_socket_transform(socket_name: StringName) -> Transform3D:
	var attachment: BoneAttachment3D = socket_attachments.get(socket_name)
	if attachment == null:
		return Transform3D.IDENTITY
	return attachment.global_transform

func get_socket_bone_name(socket_name: StringName) -> StringName:
	var attachment: BoneAttachment3D = socket_attachments.get(socket_name)
	return attachment.bone_name if attachment != null else &""

func rigid_equipment_instance_for_slot(slot: int) -> MeshInstance3D:
	match slot:
		DefinitionType.Slot.HAIR:
			return hair_mesh_instance
		DefinitionType.Slot.HELMET:
			return helmet_mesh_instance
		DefinitionType.Slot.WEAPON:
			return weapon_mesh_instance
		DefinitionType.Slot.SHIELD:
			return shield_mesh_instance
		_:
			return null

func rigid_equipment_id_for_slot(slot: int) -> StringName:
	match slot:
		DefinitionType.Slot.HAIR:
			return current_appearance.hair_id
		DefinitionType.Slot.HELMET:
			return current_appearance.helmet_id
		DefinitionType.Slot.WEAPON:
			return current_appearance.weapon_id
		DefinitionType.Slot.SHIELD:
			return current_appearance.shield_id
		_:
			return &""

func rigid_equipment_requested_for_slot(slot: int) -> bool:
	if not equipment_visible or rigid_equipment_id_for_slot(slot).is_empty():
		return false
	if active_render_bundle != null:
		return bool(active_render_bundle.rigid_visible.get(slot, false))
	if slot == DefinitionType.Slot.HAIR and not current_appearance.helmet_id.is_empty():
		return false
	var mesh_instance: MeshInstance3D = rigid_equipment_instance_for_slot(slot)
	return mesh_instance != null and mesh_instance.mesh != null

func get_rigid_equipment_transform(slot: int) -> Transform3D:
	var mesh_instance: MeshInstance3D = rigid_equipment_instance_for_slot(slot)
	if mesh_instance == null:
		return global_transform
	var socket_name: StringName = &""
	match slot:
		DefinitionType.Slot.HAIR, DefinitionType.Slot.HELMET:
			socket_name = &"head_socket"
		DefinitionType.Slot.WEAPON:
			socket_name = &"weapon_socket_r"
		DefinitionType.Slot.SHIELD:
			socket_name = &"shield_socket_l"
	var attachment: BoneAttachment3D = socket_attachments.get(socket_name)
	return attachment.global_transform * mesh_instance.transform if attachment != null else mesh_instance.global_transform

func set_rigid_equipment_batched(is_batched: bool) -> void:
	rigid_equipment_batched = is_batched
	for slot: int in [
		DefinitionType.Slot.HAIR, DefinitionType.Slot.HELMET,
		DefinitionType.Slot.WEAPON, DefinitionType.Slot.SHIELD
	]:
		var mesh_instance: MeshInstance3D = rigid_equipment_instance_for_slot(slot)
		if mesh_instance == null:
			continue
		mesh_instance.visible = false if is_batched else rigid_equipment_requested_for_slot(slot)

func set_rigid_material_consolidation(
	enabled: bool,
	target_registry: RigidEquipmentRenderRegistry
) -> void:
	var appearance_key: String = current_appearance.key()
	if rigid_material_consolidated == enabled and _rigid_material_appearance_key == appearance_key:
		return
	rigid_material_consolidated = enabled
	_rigid_material_appearance_key = appearance_key
	for slot: int in [
		DefinitionType.Slot.HAIR, DefinitionType.Slot.HELMET,
		DefinitionType.Slot.WEAPON, DefinitionType.Slot.SHIELD
	]:
		var mesh_instance: MeshInstance3D = rigid_equipment_instance_for_slot(slot)
		if mesh_instance == null:
			continue
		var equipment_id: StringName = rigid_equipment_id_for_slot(slot)
		var definition: SpecialVisualDefinition = registry.resolve(slot, equipment_id) if registry != null else null
		if definition == null:
			continue
		mesh_instance.material_override = (
			target_registry.shared_material_for(slot, equipment_id)
			if enabled and target_registry != null else definition.material
		)


func set_shadow_budget_policy(next_mode: int, actor_rank: int, next_max_full_shadow_actors: int) -> bool:
	var changed: bool = (
		shadow_budget_mode != next_mode
		or shadow_budget_rank != actor_rank
		or max_full_shadow_actors != next_max_full_shadow_actors
	)
	if not changed:
		return false
	shadow_budget_mode = next_mode
	shadow_budget_rank = actor_rank
	max_full_shadow_actors = maxi(next_max_full_shadow_actors, 0)
	if active_render_bundle != null:
		_apply_bundle_shadow_state()
	else:
		_apply_rigid_shadow_state()
	return changed

func get_rigid_equipment_audit(visible_only: bool = true) -> Dictionary:
	var result: Dictionary = {}
	for slot: int in [
		DefinitionType.Slot.HAIR, DefinitionType.Slot.HELMET,
		DefinitionType.Slot.WEAPON, DefinitionType.Slot.SHIELD
	]:
		var mesh_instance: MeshInstance3D = rigid_equipment_instance_for_slot(slot)
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		if visible_only and not rigid_equipment_requested_for_slot(slot):
			continue
		var equipment_id: StringName = rigid_equipment_id_for_slot(slot)
		var material: Material = mesh_instance.material_override
		if material == null:
			material = mesh_instance.mesh.surface_get_material(0)
		result[str(slot)] = {
			"slot": slot,
			"equipment_id": equipment_id,
			"mesh_instances": 1,
			"surfaces": mesh_instance.mesh.get_surface_count(),
			"materials": 1 if material != null else 0,
			"mesh_resource_id": mesh_instance.mesh.get_instance_id(),
			"material_resource_id": material.get_instance_id() if material != null else 0,
			"shadow": mesh_instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"triangles": _mesh_triangle_count(mesh_instance.mesh)
		}
	return result

func body_region_visible(region: int) -> bool:
	if region < 0 or region >= body_regions.size():
		return false
	return body_regions[region].visible

func set_equipment_visible(is_visible: bool) -> void:
	equipment_visible = is_visible
	for module: Node3D in [armor_module, hair_module, helmet_module, cape_module, weapon_module, shield_module]:
		if module != null:
			module.visible = is_visible
	if active_render_bundle != null:
		render_bundle_mesh_instance.visible = true
		body_module.visible = false
		head_module.visible = false
		armor_module.visible = false
	if rigid_equipment_batched:
		set_rigid_equipment_batched(true)

func set_shadows_enabled(is_enabled: bool) -> void:
	shadows_enabled = is_enabled
	_set_shadows_recursive(self, is_enabled)
	if active_render_bundle != null:
		_apply_bundle_shadow_state()
	else:
		_apply_rigid_shadow_state()

func get_render_stats(visible_only: bool = true) -> Dictionary:
	var stats := {
		"mesh_instances": 0,
		"surfaces": 0,
		"skinned_meshes": 0,
		"materials": 0
	}
	var materials: Array[Material] = []
	_collect_render_stats(self, visible_only, stats, materials)
	stats["materials"] = materials.size()
	return stats

func get_unique_materials(visible_only: bool = true) -> Array[Material]:
	var materials: Array[Material] = []
	_collect_materials(self, visible_only, materials)
	return materials

func get_unique_meshes(visible_only: bool = true) -> Array[Mesh]:
	var meshes: Array[Mesh] = []
	_collect_meshes(self, visible_only, meshes)
	return meshes

func get_render_breakdown(visible_only: bool = true) -> Dictionary:
	var breakdown: Dictionary = {}
	_collect_render_breakdown(self, visible_only, breakdown)
	return breakdown

func _build_character_nodes() -> void:
	if skeleton != null:
		return
	skeleton = HumanRigType.build_skeleton()
	skeleton.reset_bone_poses()
	add_child(skeleton)
	skin = Skin.new()
	for bone_index: int in range(skeleton.get_bone_count()):
		skin.add_bind(bone_index, skeleton.get_bone_global_rest(bone_index).affine_inverse())

	animation_player = AnimationPlayer.new()
	animation_player.name = "SharedAnimationPlayer"
	add_child(animation_player)
	animator = AnimatorType.new()
	animator.name = "SpecialCharacterAnimator"
	add_child(animator)
	animator.setup(skeleton, animation_player, shared_animation_library)

	body_module = _add_module("Body")
	head_module = _add_module("Head")
	armor_module = _add_module("Armor")
	render_bundle_module = _add_module("RenderBundle")
	render_bundle_module.visible = false
	render_bundle_mesh_instance = MeshInstance3D.new()
	render_bundle_mesh_instance.name = "SkinnedRenderBundle"
	render_bundle_module.add_child(render_bundle_mesh_instance)
	_configure_skinned_mesh(render_bundle_mesh_instance)
	hair_module = _new_module("Hair")
	helmet_module = _new_module("Helmet")
	cape_module = _new_module("Cape")
	weapon_module = _new_module("Weapon")
	shield_module = _new_module("Shield")

	var body_definition := registry.resolve(DefinitionType.Slot.BODY, &"human_body_01")
	for region_index: int in range(DefinitionType.BodyRegion.FEET + 1):
		var region_mesh := MeshInstance3D.new()
		region_mesh.name = "BodyRegion_%s" % _body_region_name(region_index)
		body_module.add_child(region_mesh)
		body_regions.append(region_mesh)
		if body_definition != null and region_index < body_definition.region_meshes.size():
			region_mesh.mesh = body_definition.region_meshes[region_index]
			region_mesh.material_override = body_definition.material
		_configure_skinned_mesh(region_mesh)

	head_mesh_instance = MeshInstance3D.new()
	head_mesh_instance.name = "HeadMesh"
	head_module.add_child(head_mesh_instance)
	_configure_skinned_mesh(head_mesh_instance)

	armor_mesh_instance = MeshInstance3D.new()
	armor_mesh_instance.name = "ArmorMesh"
	armor_module.add_child(armor_mesh_instance)
	_configure_skinned_mesh(armor_mesh_instance)

	var head_socket := _add_socket(&"head_socket", hair_module, helmet_module)
	hair_mesh_instance = _add_rigid_mesh("HairMesh", head_socket, hair_module)
	helmet_mesh_instance = _add_rigid_mesh("HelmetMesh", head_socket, helmet_module)
	var weapon_socket := _add_socket(&"weapon_socket_r", weapon_module, null)
	weapon_mesh_instance = _add_rigid_mesh("SwordMesh", weapon_socket, weapon_module)
	var shield_socket := _add_socket(&"shield_socket_l", shield_module, null)
	shield_mesh_instance = _add_rigid_mesh("ShieldMesh", shield_socket, shield_module)
	_add_socket(&"back_socket", cape_module, null)

func _apply_body(definition: SpecialVisualDefinition) -> void:
	if definition == null:
		return
	for region_index: int in range(body_regions.size()):
		body_regions[region_index].visible = true
		if region_index < definition.region_meshes.size():
			body_regions[region_index].mesh = definition.region_meshes[region_index]
			body_regions[region_index].material_override = definition.material

func _apply_head(definition: SpecialVisualDefinition) -> void:
	if definition == null:
		return
	head_mesh_instance.mesh = definition.mesh
	head_mesh_instance.material_override = definition.material
	head_mesh_instance.visible = true
	if body_regions.size() > DefinitionType.BodyRegion.HEAD:
		body_regions[DefinitionType.BodyRegion.HEAD].visible = false

func _apply_armor(definition: SpecialVisualDefinition) -> void:
	armor_mesh_instance.visible = definition != null
	if definition == null:
		return
	armor_mesh_instance.mesh = definition.mesh
	armor_mesh_instance.material_override = definition.material
	for region_index: int in range(body_regions.size()):
		body_regions[region_index].visible = not definition.hide_body_regions.has(region_index)
	if body_regions.size() > DefinitionType.BodyRegion.HEAD:
		body_regions[DefinitionType.BodyRegion.HEAD].visible = false

func _apply_rigid(
	mesh_instance: MeshInstance3D,
	definition: SpecialVisualDefinition,
	requested: bool
) -> void:
	mesh_instance.visible = requested and definition != null and not rigid_equipment_batched
	if not mesh_instance.visible:
		return
	mesh_instance.mesh = definition.mesh
	mesh_instance.material_override = definition.material

func _apply_bundle_shadow_state() -> void:
	if active_render_bundle == null:
		return
	render_bundle_mesh_instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if shadows_enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	for slot_and_mesh: Array in [
		[DefinitionType.Slot.HAIR, hair_mesh_instance],
		[DefinitionType.Slot.HELMET, helmet_mesh_instance],
		[DefinitionType.Slot.WEAPON, weapon_mesh_instance],
		[DefinitionType.Slot.SHIELD, shield_mesh_instance]
	]:
		var slot: int = slot_and_mesh[0]
		var mesh_instance: MeshInstance3D = slot_and_mesh[1]
		var should_cast: bool = (
			shadows_enabled
			and bool(active_render_bundle.rigid_cast_shadow.get(slot, false))
			and ShadowBudgetType.rigid_casts(
				RigidRegistryType.ShadowClass.MAJOR if slot in [DefinitionType.Slot.HELMET, DefinitionType.Slot.SHIELD]
				else RigidRegistryType.ShadowClass.SMALL,
				shadow_budget_mode, shadow_budget_rank, max_full_shadow_actors
			)
		)
		mesh_instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if should_cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)

func _apply_rigid_shadow_state() -> void:
	for slot: int in [
		DefinitionType.Slot.HAIR, DefinitionType.Slot.HELMET,
		DefinitionType.Slot.WEAPON, DefinitionType.Slot.SHIELD
	]:
		var mesh_instance: MeshInstance3D = rigid_equipment_instance_for_slot(slot)
		if mesh_instance == null:
			continue
		var shadow_class: int = (
			RigidRegistryType.ShadowClass.MAJOR
			if slot in [DefinitionType.Slot.HELMET, DefinitionType.Slot.SHIELD]
			else RigidRegistryType.ShadowClass.SMALL
		)
		var should_cast: bool = shadows_enabled and rigid_equipment_requested_for_slot(slot) and ShadowBudgetType.rigid_casts(
			shadow_class, shadow_budget_mode, shadow_budget_rank, max_full_shadow_actors
		)
		mesh_instance.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if should_cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)

func _definitions_are_compatible(definitions_to_check: Array) -> bool:
	for definition: SpecialVisualDefinition in definitions_to_check:
		if definition != null and not definition.is_compatible():
			return false
	return true

func _add_module(module_name: StringName) -> Node3D:
	var module := _new_module(module_name)
	add_child(module)
	return module

func _new_module(module_name: StringName) -> Node3D:
	var module := Node3D.new()
	module.name = module_name
	return module

func _add_socket(
	socket_name: StringName,
	primary_module: Node3D,
	secondary_module: Node3D
) -> BoneAttachment3D:
	var attachment := BoneAttachment3D.new()
	attachment.name = socket_name
	attachment.bone_name = socket_name
	skeleton.add_child(attachment)
	socket_attachments[socket_name] = attachment
	if primary_module != null:
		attachment.add_child(primary_module)
	if secondary_module != null:
		attachment.add_child(secondary_module)
	return attachment

func _add_rigid_mesh(
	mesh_name: StringName,
	attachment: BoneAttachment3D,
	module: Node3D
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	if module.get_parent() != attachment:
		attachment.add_child(module)
	module.add_child(mesh_instance)
	return mesh_instance

func _configure_skinned_mesh(mesh_instance: MeshInstance3D) -> void:
	mesh_instance.skin = skin
	mesh_instance.skeleton = mesh_instance.get_path_to(skeleton)

func _body_region_name(region: int) -> StringName:
	match region:
		DefinitionType.BodyRegion.HEAD:
			return &"HEAD"
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

func _count_nodes(node: Node) -> int:
	var count := 1
	for child: Node in node.get_children():
		count += _count_nodes(child)
	return count

func _count_skinned_meshes(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D and (node as MeshInstance3D).skin != null:
		count += 1
	for child: Node in node.get_children():
		count += _count_skinned_meshes(child)
	return count

func _set_shadows_recursive(node: Node, is_enabled: bool) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).cast_shadow = 1 if is_enabled else 0
	for child: Node in node.get_children():
		_set_shadows_recursive(child, is_enabled)

func _collect_render_stats(
	node: Node,
	visible_only: bool,
	stats: Dictionary,
	materials: Array[Material]
) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if not visible_only or mesh_instance.is_visible_in_tree():
			stats["mesh_instances"] += 1
			if mesh_instance.skin != null:
				stats["skinned_meshes"] += 1
			if mesh_instance.mesh != null:
				stats["surfaces"] += mesh_instance.mesh.get_surface_count()
				for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
					var material: Material = mesh_instance.material_override
					if material == null:
						material = mesh_instance.mesh.surface_get_material(surface_index)
					if material != null and not materials.has(material):
						materials.append(material)
	for child: Node in node.get_children():
		_collect_render_stats(child, visible_only, stats, materials)

func _collect_materials(node: Node, visible_only: bool, materials: Array[Material]) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if not visible_only or mesh_instance.is_visible_in_tree():
			if mesh_instance.mesh != null:
				for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
					var material: Material = mesh_instance.material_override
					if material == null:
						material = mesh_instance.mesh.surface_get_material(surface_index)
					if material != null and not materials.has(material):
						materials.append(material)
	for child: Node in node.get_children():
		_collect_materials(child, visible_only, materials)

func _collect_meshes(node: Node, visible_only: bool, meshes: Array[Mesh]) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if (not visible_only or mesh_instance.is_visible_in_tree()) and mesh_instance.mesh != null and not meshes.has(mesh_instance.mesh):
			meshes.append(mesh_instance.mesh)
	for child: Node in node.get_children():
		_collect_meshes(child, visible_only, meshes)

func _collect_render_breakdown(node: Node, visible_only: bool, breakdown: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if not visible_only or mesh_instance.is_visible_in_tree():
			var component: StringName = _component_for_mesh(mesh_instance)
			if not breakdown.has(component):
				breakdown[component] = {
					"mesh_instances": 0, "surfaces": 0, "draw_calls": 0,
					"triangles": 0, "skinned_meshes": 0, "shadow_meshes": 0
				}
			var entry: Dictionary = breakdown[component]
			entry["mesh_instances"] += 1
			entry["skinned_meshes"] += 1 if mesh_instance.skin != null else 0
			entry["shadow_meshes"] += 1 if mesh_instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else 0
			if mesh_instance.mesh != null:
				var surface_count: int = mesh_instance.mesh.get_surface_count()
				entry["surfaces"] += surface_count
				entry["draw_calls"] += surface_count
				entry["triangles"] += _mesh_triangle_count(mesh_instance.mesh)
			breakdown[component] = entry
	for child: Node in node.get_children():
		_collect_render_breakdown(child, visible_only, breakdown)

func _component_for_mesh(mesh_instance: MeshInstance3D) -> StringName:
	var current: Node = mesh_instance
	while current != null and current != self:
		match StringName(current.name):
			&"Body": return &"Body"
			&"Head": return &"Head"
			&"Armor": return &"Armor"
			&"Hair": return &"Hair"
			&"Helmet": return &"Helmet"
			&"Weapon": return &"Weapon"
			&"Shield": return &"Shield"
			&"Cape": return &"Cape"
			&"RenderBundle": return &"SkinnedBundle"
		current = current.get_parent()
	return &"Other"

func _mesh_triangle_count(mesh: Mesh) -> int:
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
