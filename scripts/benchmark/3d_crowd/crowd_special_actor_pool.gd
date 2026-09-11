class_name CrowdSpecialActorPool
extends Node3D

const BattleCrowdSimulationType = preload("res://scripts/benchmark/3d_crowd/battle_crowd_simulation.gd")
const AppearanceType = preload("res://scripts/benchmark/3d_special/special_character_appearance.gd")
const AnimationStateType = preload("res://scripts/benchmark/3d_special/special_character_animation_state.gd")
const RegistryType = preload("res://scripts/benchmark/3d_special/special_character_visual_registry.gd")
const VisualType = preload("res://scripts/benchmark/3d_special/special_character_visual_3d.gd")
const AnimationLibraryType = preload("res://scripts/benchmark/3d_special/special_human_animation_library.gd")
const RenderBundleCacheType = preload("res://scripts/benchmark/3d_special/special_character_render_bundle_cache.gd")
const RenderBundleType = preload("res://scripts/benchmark/3d_special/special_character_render_bundle.gd")
const RenderModeType = preload("res://scripts/benchmark/3d_special/special_character_render_mode.gd")
const RigidRegistryType = preload("res://scripts/benchmark/3d_special/rigid_equipment_render_registry.gd")
const RigidBatchType = preload("res://scripts/benchmark/3d_special/special_rigid_equipment_batch_renderer.gd")
const ShadowBudgetType = preload("res://scripts/benchmark/3d_special/special_shadow_budget.gd")

const MAX_NEAR_ACTORS: int = 128

var registry: SpecialCharacterVisualRegistry
var shared_animation_library: AnimationLibrary
var render_bundle_cache: SpecialCharacterRenderBundleCache
var rigid_equipment_registry: RigidEquipmentRenderRegistry
var rigid_batch_renderer: SpecialRigidEquipmentBatchRenderer
var allocated_actors: Array[SpecialCharacterVisual3D] = []
var capacity: int = 0
var active_actor_count: int = 0
var last_update_cpu_ms: float = 0.0
var last_animation_cpu_ms: float = 0.0
var last_transition_cpu_ms: float = 0.0
var initialization_cpu_ms: float = 0.0
var promotions_this_frame: int = 0
var demotions_this_frame: int = 0
var total_promotions: int = 0
var total_demotions: int = 0
var allocation_count: int = 0
var animation_enabled: bool = true
var animation_update_stride: int = 1
var equipment_visible: bool = true
var shadows_enabled: bool = true
var render_mode: int = RenderModeType.Mode.MODULAR
var special_lod0_distance: float = 42.0
var max_special_lod0: int = 24
var bundle_lod0_active: int = 0
var bundle_lod1_active: int = 0
var bundle_cache_misses: int = 0
var rigid_batch_enabled: bool = false
var rigid_material_consolidation_enabled: bool = false
var shadow_budget_mode: int = ShadowBudgetType.Mode.ALL
var max_full_shadow_actors: int = 24
var rigid_socket_update_stride: int = 1
var allow_runtime_bundle_build: bool = false
var last_rigid_batch_cpu_ms: float = 0.0
var last_rigid_transform_updates: int = 0
var last_rigid_upload_calls: int = 0
var last_rigid_buffer_upload_calls: int = 0
var last_rigid_bytes_uploaded: int = 0
var rigid_structural_changes_this_frame: int = 0
var total_rigid_structural_changes: int = 0
var lod_transitions_this_frame: int = 0
var shadow_transitions_this_frame: int = 0

var _slot_soldier_ids: PackedInt32Array = PackedInt32Array()
var _last_promoted_ids: PackedInt32Array = PackedInt32Array()
var _last_demoted_ids: PackedInt32Array = PackedInt32Array()
var _initialized: bool = false
var _sync_frame_index: int = 0

func initialize(
	target_registry: SpecialCharacterVisualRegistry = null,
	target_animation_library: AnimationLibrary = null,
	requested_capacity: int = MAX_NEAR_ACTORS,
	prewarm_bundles: bool = true,
	allow_cold_bundle_build: bool = false
) -> void:
	if _initialized:
		return
	var started_usec: int = Time.get_ticks_usec()
	registry = target_registry if target_registry != null else RegistryType.new()
	shared_animation_library = (
		target_animation_library
		if target_animation_library != null
		else AnimationLibraryType.build_library()
	)
	render_bundle_cache = RenderBundleCacheType.new()
	render_bundle_cache.setup(registry)
	allow_runtime_bundle_build = allow_cold_bundle_build
	if prewarm_bundles:
		render_bundle_cache.prewarm(_prewarm_appearances())
	rigid_equipment_registry = RigidRegistryType.new()
	rigid_equipment_registry.setup(registry)
	rigid_batch_renderer = RigidBatchType.new()
	rigid_batch_renderer.name = "SpecialRigidEquipmentBatchRenderer"
	add_child(rigid_batch_renderer)
	capacity = clampi(requested_capacity, 0, MAX_NEAR_ACTORS)
	rigid_batch_renderer.setup(rigid_equipment_registry, capacity)
	_slot_soldier_ids.resize(capacity)
	_slot_soldier_ids.fill(-1)
	# ponytail: allocate the fixed Near budget once; promotions only rebind
	# existing views and never add/remove Nodes in the hot path.
	for slot: int in range(capacity):
		var actor: SpecialCharacterVisual3D = VisualType.new()
		actor.name = "NearSpecialActor_%02d" % slot
		add_child(actor)
		actor.setup(registry, shared_animation_library)
		actor.set_equipment_visible(equipment_visible)
		actor.set_shadows_enabled(shadows_enabled)
		actor.visible = false
		allocated_actors.append(actor)
	allocation_count = allocated_actors.size()
	_initialized = true
	initialization_cpu_ms = float(Time.get_ticks_usec() - started_usec) / 1000.0

func sync_from_simulation(
	desired_slots: PackedInt32Array,
	simulation: BattleCrowdSimulation,
	camera_position: Vector3 = Vector3.ZERO
) -> void:
	var started_usec: int = Time.get_ticks_usec()
	if not _initialized or simulation == null:
		return
	_sync_frame_index += 1
	last_animation_cpu_ms = 0.0
	last_transition_cpu_ms = 0.0
	rigid_structural_changes_this_frame = 0
	lod_transitions_this_frame = 0
	shadow_transitions_this_frame = 0
	promotions_this_frame = 0
	demotions_this_frame = 0
	_last_promoted_ids.resize(0)
	_last_demoted_ids.resize(0)
	bundle_lod0_active = 0
	bundle_lod1_active = 0
	bundle_cache_misses = 0
	var next_active_count: int = 0
	for slot: int in range(capacity):
		var next_soldier_id: int = -1
		if slot < desired_slots.size():
			var requested_id: int = desired_slots[slot]
			if _is_active_soldier(simulation, requested_id):
				next_soldier_id = requested_id
		var previous_soldier_id: int = _slot_soldier_ids[slot]
		if previous_soldier_id != next_soldier_id:
			var transition_started_usec: int = Time.get_ticks_usec()
			if previous_soldier_id >= 0:
				_demote_actor(slot, previous_soldier_id)
				_last_demoted_ids.append(previous_soldier_id)
				demotions_this_frame += 1
				total_demotions += 1
			_slot_soldier_ids[slot] = next_soldier_id
			if next_soldier_id >= 0:
				_promote_actor(slot, next_soldier_id, simulation, camera_position)
				_last_promoted_ids.append(next_soldier_id)
				promotions_this_frame += 1
				total_promotions += 1
			last_transition_cpu_ms += float(Time.get_ticks_usec() - transition_started_usec) / 1000.0
		elif next_soldier_id >= 0:
			last_animation_cpu_ms += _sync_actor(slot, next_soldier_id, simulation, camera_position)
		if next_soldier_id >= 0:
			next_active_count += 1
	active_actor_count = next_active_count
	if rigid_batch_renderer != null:
		rigid_batch_renderer.update_transforms()
		last_rigid_batch_cpu_ms = rigid_batch_renderer.last_update_cpu_ms
		last_rigid_transform_updates = rigid_batch_renderer.last_transform_updates
		last_rigid_upload_calls = rigid_batch_renderer.last_upload_calls
		last_rigid_buffer_upload_calls = rigid_batch_renderer.last_buffer_upload_calls
		last_rigid_bytes_uploaded = rigid_batch_renderer.last_bytes_uploaded
		rigid_structural_changes_this_frame = rigid_batch_renderer.structural_changes_this_frame
		total_rigid_structural_changes = rigid_batch_renderer.total_structural_changes
	last_update_cpu_ms = float(Time.get_ticks_usec() - started_usec) / 1000.0

func set_animation_enabled(is_enabled: bool) -> void:
	animation_enabled = is_enabled

func set_animation_update_stride(stride: int) -> void:
	animation_update_stride = clampi(stride, 0, 4)

func set_render_mode(next_mode: int) -> void:
	render_mode = clampi(next_mode, RenderModeType.Mode.MODULAR, RenderModeType.Mode.BUNDLE_LOD)

func set_render_lod_parameters(lod0_distance: float, max_lod0: int) -> void:
	special_lod0_distance = maxf(lod0_distance, 0.0)
	max_special_lod0 = maxi(max_lod0, 0)

func set_equipment_visible(is_visible: bool) -> void:
	equipment_visible = is_visible
	for actor: SpecialCharacterVisual3D in allocated_actors:
		actor.set_equipment_visible(is_visible)

func set_shadows_enabled(is_enabled: bool) -> void:
	shadows_enabled = is_enabled
	for actor: SpecialCharacterVisual3D in allocated_actors:
		actor.set_shadows_enabled(is_enabled)

func set_rigid_render_options(
	use_batch: bool,
	use_material_consolidation: bool,
	next_shadow_mode: int = ShadowBudgetType.Mode.ALL,
	next_max_full_shadow_actors: int = 24,
	next_socket_update_stride: int = 1
) -> void:
	rigid_batch_enabled = use_batch
	rigid_material_consolidation_enabled = use_material_consolidation
	shadow_budget_mode = next_shadow_mode
	max_full_shadow_actors = maxi(next_max_full_shadow_actors, 0)
	rigid_socket_update_stride = clampi(next_socket_update_stride, 1, 4)
	if rigid_batch_renderer != null:
		rigid_batch_renderer.configure(
			rigid_batch_enabled,
			rigid_material_consolidation_enabled,
		shadow_budget_mode,
		max_full_shadow_actors,
		rigid_socket_update_stride
	)
	for slot: int in range(capacity):
		if _slot_soldier_ids[slot] < 0:
			continue
		var actor: SpecialCharacterVisual3D = allocated_actors[slot]
		_apply_actor_render_options(slot, actor)
		if rigid_batch_enabled:
			rigid_batch_renderer.bind_actor(slot, actor)

func rigid_shadow_mode_name() -> StringName:
	return ShadowBudgetType.name_for(shadow_budget_mode)

func render_stats() -> Dictionary:
	var stats := {
		"mesh_instances": 0,
		"surfaces": 0,
		"skinned_meshes": 0,
		"materials": 0,
		"unique_materials": 0,
		"triangles": 0,
		"shadow_meshes": 0,
		"unique_meshes": 0,
		"rigid_equipment_draw_calls": 0,
		"render_mode": RenderModeType.name_for(render_mode),
		"bundle_lod0_active": bundle_lod0_active,
		"bundle_lod1_active": bundle_lod1_active,
		"bundle_cache_builds": render_bundle_cache.build_count if render_bundle_cache != null else 0,
		"bundle_cache_entries": render_bundle_cache.bundle_count() if render_bundle_cache != null else 0,
		"bundle_cache_misses": bundle_cache_misses
	}
	var unique_materials: Array[Material] = []
	var unique_meshes: Array[Mesh] = []
	for slot: int in range(capacity):
		if _slot_soldier_ids[slot] < 0:
			continue
		var actor: SpecialCharacterVisual3D = allocated_actors[slot]
		var actor_stats: Dictionary = actor.get_render_stats(true)
		var actor_breakdown: Dictionary = actor.get_render_breakdown(true)
		stats["mesh_instances"] += int(actor_stats["mesh_instances"])
		stats["surfaces"] += int(actor_stats["surfaces"])
		stats["skinned_meshes"] += int(actor_stats["skinned_meshes"])
		for component: StringName in actor_breakdown.keys():
			stats["triangles"] += int(actor_breakdown[component].get("triangles", 0))
			stats["shadow_meshes"] += int(actor_breakdown[component].get("shadow_meshes", 0))
		for material: Material in actor.get_unique_materials(true):
			if not unique_materials.has(material):
				unique_materials.append(material)
		for mesh: Mesh in actor.get_unique_meshes(true):
			if not unique_meshes.has(mesh):
				unique_meshes.append(mesh)
		for component: StringName in ["Hair", "Helmet", "Weapon", "Shield"]:
			stats["rigid_equipment_draw_calls"] += int(actor_breakdown.get(component, {}).get("draw_calls", 0))
	if rigid_batch_enabled and rigid_batch_renderer != null:
		var batch_stats: Dictionary = rigid_batch_renderer.stats()
		stats["mesh_instances"] += int(batch_stats["nodes"])
		stats["surfaces"] += int(batch_stats["draw_calls"])
		stats["triangles"] += int(batch_stats["triangles"])
		stats["shadow_meshes"] += int(batch_stats["shadow_instances"])
		for material: Material in rigid_batch_renderer.unique_materials():
			if not unique_materials.has(material):
				unique_materials.append(material)
		for group_mesh: Mesh in rigid_batch_renderer.unique_meshes():
			if not unique_meshes.has(group_mesh):
				unique_meshes.append(group_mesh)
	stats["materials"] = unique_materials.size()
	stats["unique_materials"] = unique_materials.size()
	stats["unique_meshes"] = unique_meshes.size()
	if rigid_batch_renderer != null:
		var batch_stats: Dictionary = rigid_batch_renderer.stats()
		stats["rigid_batch_nodes"] = int(batch_stats["nodes"])
		stats["rigid_batch_instances"] = int(batch_stats["active_instances"])
		stats["rigid_equipment_draw_calls"] = int(batch_stats["draw_calls"]) if rigid_batch_enabled else int(stats["rigid_equipment_draw_calls"])
		stats["shadow_submissions"] = int(stats["shadow_meshes"])
	stats["rigid_batch_enabled"] = rigid_batch_enabled
	stats["rigid_material_consolidated"] = rigid_material_consolidation_enabled
	stats["shadow_budget"] = rigid_shadow_mode_name()
	return stats

func component_breakdown() -> Dictionary:
	var result: Dictionary = {}
	for slot: int in range(capacity):
		if _slot_soldier_ids[slot] < 0:
			continue
		var actor_breakdown: Dictionary = allocated_actors[slot].get_render_breakdown(true)
		for component: StringName in actor_breakdown.keys():
			if not result.has(component):
				result[component] = {
					"mesh_instances": 0, "surfaces": 0, "draw_calls": 0,
					"triangles": 0, "skinned_meshes": 0, "shadow_meshes": 0
				}
			var entry: Dictionary = result[component]
			for metric: String in ["mesh_instances", "surfaces", "draw_calls", "triangles", "skinned_meshes", "shadow_meshes"]:
				entry[metric] += int(actor_breakdown[component].get(metric, 0))
			result[component] = entry
	if rigid_batch_enabled and rigid_batch_renderer != null:
		var batch_breakdown: Dictionary = rigid_batch_renderer.component_breakdown()
		for component: StringName in batch_breakdown.keys():
			result[component] = batch_breakdown[component]
	return result

func rigid_equipment_audit() -> Dictionary:
	var result: Dictionary = {}
	for slot: int in range(capacity):
		if _slot_soldier_ids[slot] < 0:
			continue
		var actor_audit: Dictionary = allocated_actors[slot].get_rigid_equipment_audit(true)
		for equipment_slot: String in actor_audit.keys():
			var entry: Dictionary = actor_audit[equipment_slot]
			var equipment_id: String = String(entry["equipment_id"])
			if not result.has(equipment_id):
				result[equipment_id] = {
					"mesh_instances": 0, "surfaces": 0, "materials": 0,
					"mesh_resource_ids": [], "material_resource_ids": [],
					"shadow_instances": 0, "triangles": 0
				}
			var total: Dictionary = result[equipment_id]
			total["mesh_instances"] += int(entry["mesh_instances"])
			total["surfaces"] += int(entry["surfaces"])
			total["materials"] += int(entry["materials"])
			if not total["mesh_resource_ids"].has(entry["mesh_resource_id"]):
				total["mesh_resource_ids"].append(entry["mesh_resource_id"])
			if not total["material_resource_ids"].has(entry["material_resource_id"]):
				total["material_resource_ids"].append(entry["material_resource_id"])
			total["shadow_instances"] += 1 if bool(entry["shadow"]) else 0
			total["triangles"] += int(entry["triangles"])
			result[equipment_id] = total
	if rigid_batch_enabled and rigid_batch_renderer != null:
		result["_batch"] = rigid_batch_renderer.audit()
	return result

func clear_all() -> void:
	if not _initialized:
		return
	for slot: int in range(capacity):
		if _slot_soldier_ids[slot] >= 0:
			_demote_actor(slot, _slot_soldier_ids[slot])
		_slot_soldier_ids[slot] = -1
	active_actor_count = 0
	promotions_this_frame = 0
	demotions_this_frame = 0
	total_promotions = 0
	total_demotions = 0
	_last_promoted_ids.resize(0)
	_last_demoted_ids.resize(0)

func get_slot_soldier_ids() -> PackedInt32Array:
	return _slot_soldier_ids

func get_last_promoted_ids() -> PackedInt32Array:
	return _last_promoted_ids

func get_last_demoted_ids() -> PackedInt32Array:
	return _last_demoted_ids

func get_actor_for_slot(slot: int) -> SpecialCharacterVisual3D:
	if slot < 0 or slot >= allocated_actors.size():
		return null
	return allocated_actors[slot]

func slot_for_soldier(soldier_id: int) -> int:
	for slot: int in range(_slot_soldier_ids.size()):
		if _slot_soldier_ids[slot] == soldier_id:
			return slot
	return -1

func is_promoted(soldier_id: int) -> bool:
	return slot_for_soldier(soldier_id) >= 0

func allocated_skeleton_count() -> int:
	return allocated_actors.size()

func active_skeleton_count() -> int:
	return active_actor_count

func allocated_animation_player_count() -> int:
	return allocated_actors.size()

func _promote_actor(
	slot: int,
	soldier_id: int,
	simulation: BattleCrowdSimulation,
	camera_position: Vector3
) -> void:
	var actor: SpecialCharacterVisual3D = allocated_actors[slot]
	var transform: Transform3D = _transform_for(simulation, soldier_id)
	var appearance: SpecialCharacterAppearance = _appearance_for(simulation, soldier_id)
	var applied: bool = false
	if animation_enabled:
		applied = actor.apply_view_state(
			soldier_id,
			transform,
			appearance,
			_special_animation_state(simulation.soldier_animation_state[soldier_id]),
			simulation.soldier_animation_time[soldier_id],
			simulation.soldier_animation_phase[soldier_id]
		)
	else:
		actor.soldier_id = soldier_id
		actor.global_transform = transform
		applied = actor.set_appearance(appearance)
	if applied:
		actor.visible = true
		_apply_render_mode(actor, camera_position)
		if _apply_actor_render_options(slot, actor):
			shadow_transitions_this_frame += 1
		if rigid_batch_enabled:
			rigid_batch_renderer.bind_actor(slot, actor)
	actor.visible = applied

func _sync_actor(
	slot: int,
	soldier_id: int,
	simulation: BattleCrowdSimulation,
	camera_position: Vector3
) -> float:
	var actor: SpecialCharacterVisual3D = allocated_actors[slot]
	actor.global_transform = _transform_for(simulation, soldier_id)
	_apply_render_mode(actor, camera_position)
	if _apply_actor_render_options(slot, actor):
		shadow_transitions_this_frame += 1
	if rigid_batch_enabled and rigid_batch_renderer != null:
		rigid_batch_renderer.refresh_actor_binding(slot, actor)
	else:
		actor.set_rigid_equipment_batched(false)
	var should_update_animation: bool = (
		animation_enabled
		and animation_update_stride > 0
		and posmod(_sync_frame_index, animation_update_stride) == 0
	)
	var animation_started_usec: int = 0
	if should_update_animation:
		animation_started_usec = Time.get_ticks_usec()
		actor.apply_animation_state(
			_special_animation_state(simulation.soldier_animation_state[soldier_id]),
			simulation.soldier_animation_time[soldier_id],
			simulation.soldier_animation_phase[soldier_id]
		)
	actor.visible = true
	if should_update_animation:
		return float(Time.get_ticks_usec() - animation_started_usec) / 1000.0
	return 0.0

func _apply_render_mode(actor: SpecialCharacterVisual3D, camera_position: Vector3) -> void:
	if render_mode == RenderModeType.Mode.MODULAR or render_mode == RenderModeType.Mode.SHARED_RESOURCES:
		if actor.active_render_bundle != null:
			actor.set_render_bundle(null)
		return
	var lod: int = RenderBundleType.Lod.LOD0_FULL
	if render_mode == RenderModeType.Mode.BUNDLE_REDUCED_SHADOW:
		lod = RenderBundleType.Lod.LOD1_REDUCED
	elif render_mode == RenderModeType.Mode.BUNDLE_LOD:
		var is_lod0: bool = (
			bundle_lod0_active < max_special_lod0
			and actor.global_position.distance_to(camera_position) <= special_lod0_distance
		)
		lod = RenderBundleType.Lod.LOD0_FULL if is_lod0 else RenderBundleType.Lod.LOD1_REDUCED
	if actor.active_render_bundle != null and actor.active_render_bundle.lod == lod:
		if lod == RenderBundleType.Lod.LOD0_FULL:
			bundle_lod0_active += 1
		else:
			bundle_lod1_active += 1
		return
	if actor.active_render_bundle != null:
		lod_transitions_this_frame += 1
	var bundle: SpecialCharacterRenderBundle = render_bundle_cache.lookup(actor.current_appearance, lod)
	if bundle == null:
		bundle_cache_misses += 1
		if allow_runtime_bundle_build:
			bundle = render_bundle_cache.get_or_build(actor.current_appearance, lod)
		else:
			# Bundles are prewarmed before the pool is exposed. A miss falls back to
			# the modular view instead of compiling during Promotion.
			if actor.active_render_bundle != null:
				actor.set_render_bundle(null)
			return
	if actor.active_render_bundle != bundle:
		actor.apply_render_bundle(bundle)
	if lod == RenderBundleType.Lod.LOD0_FULL:
		bundle_lod0_active += 1
	else:
		bundle_lod1_active += 1

func _demote_actor(slot: int, _soldier_id: int) -> void:
	if rigid_batch_renderer != null and rigid_batch_enabled:
		rigid_batch_renderer.release_actor(slot)
	var actor: SpecialCharacterVisual3D = allocated_actors[slot]
	actor.visible = false
	actor.soldier_id = -1

func _apply_actor_render_options(slot: int, actor: SpecialCharacterVisual3D) -> bool:
	actor.set_rigid_material_consolidation(rigid_material_consolidation_enabled, rigid_equipment_registry)
	return actor.set_shadow_budget_policy(shadow_budget_mode, slot, max_full_shadow_actors)

func _transform_for(simulation: BattleCrowdSimulation, soldier_id: int) -> Transform3D:
	return Transform3D(
		Basis(Vector3.UP, simulation.get_soldier_facing(soldier_id)),
		simulation.get_soldier_world_position(soldier_id)
	)

func _appearance_for(
	simulation: BattleCrowdSimulation,
	soldier_id: int
) -> SpecialCharacterAppearance:
	var appearance := AppearanceType.new()
	var archetype: int = posmod(simulation.soldier_visual_archetype[soldier_id], 4)
	var equipment_variant: int = simulation.soldier_equipment_variant[soldier_id]
	var color_variant: int = simulation.soldier_color_variant[soldier_id]
	match archetype:
		0:
			appearance.armor_id = &"cloth_01"
			appearance.hair_id = &"hair_short_01"
			appearance.weapon_id = &"sword_01"
		1:
			appearance.armor_id = &"plate_01"
			appearance.helmet_id = &"helmet_01"
			appearance.weapon_id = &"sword_01"
			appearance.shield_id = &"shield_01"
		2:
			appearance.armor_id = &"leather_01"
			appearance.hair_id = &"hair_long_01"
			appearance.weapon_id = &"sword_01"
		3:
			appearance.armor_id = &"leather_01"
			appearance.hair_id = &"hair_short_01"
			appearance.weapon_id = &"sword_01"
			appearance.shield_id = &"shield_01"
	if appearance.helmet_id.is_empty() and ((color_variant + equipment_variant) % 3 == 0):
		appearance.hair_id = &"hair_long_01"
	return appearance

func _prewarm_appearances() -> Array[SpecialCharacterAppearance]:
	var appearances: Array[SpecialCharacterAppearance] = []
	for archetype: int in range(4):
		var appearance := AppearanceType.new()
		match archetype:
			0:
				appearance.armor_id = &"cloth_01"
				appearance.hair_id = &"hair_short_01"
				appearance.weapon_id = &"sword_01"
			1:
				appearance.armor_id = &"plate_01"
				appearance.helmet_id = &"helmet_01"
				appearance.weapon_id = &"sword_01"
				appearance.shield_id = &"shield_01"
			2:
				appearance.armor_id = &"leather_01"
				appearance.hair_id = &"hair_long_01"
				appearance.weapon_id = &"sword_01"
			_:
				appearance.armor_id = &"leather_01"
				appearance.hair_id = &"hair_short_01"
				appearance.weapon_id = &"sword_01"
				appearance.shield_id = &"shield_01"
		appearances.append(appearance)
		if appearance.helmet_id.is_empty():
			var long_hair := appearance.duplicate_data()
			long_hair.hair_id = &"hair_long_01"
			appearances.append(long_hair)
	return appearances

func _special_animation_state(crowd_state: int) -> int:
	match crowd_state:
		BattleCrowdSimulationType.AnimationState.WALK:
			return AnimationStateType.State.WALK
		BattleCrowdSimulationType.AnimationState.ATTACK:
			return AnimationStateType.State.ATTACK_SWORD
		BattleCrowdSimulationType.AnimationState.DEAD:
			# ponytail: the crowd prototype has no SPECIAL dead clip yet; keep the
			# view valid and idle until the shared semantic is extended.
			return AnimationStateType.State.IDLE
		_:
			return AnimationStateType.State.IDLE

func _is_active_soldier(simulation: BattleCrowdSimulation, soldier_id: int) -> bool:
	return (
		soldier_id >= 0
		and soldier_id < simulation.active_soldier_count
		and soldier_id < simulation.soldier_alive.size()
		and simulation.soldier_alive[soldier_id] != 0
	)
