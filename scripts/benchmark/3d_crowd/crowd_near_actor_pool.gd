class_name CrowdNearActorPool
extends Node3D

const ActorType = preload("res://scripts/benchmark/3d_crowd/crowd_near_actor_3d.gd")
const AnimationLibraryType = preload("res://scripts/benchmark/3d_crowd/human_animation_library.gd")

const MAX_FULL_ACTORS: int = 256

var allocated_actors: Array[CrowdNearActor3D] = []
var active_actor_count: int = 0
var last_update_cpu_ms: float = 0.0
var _previous_active_actor_count: int = 0

var _registry: SoldierVisualRegistry
var _box_mesh: BoxMesh
var _animation_library: AnimationLibrary
var _body_materials: Array[StandardMaterial3D] = []
var _equipment_materials: Array[StandardMaterial3D] = []

func initialize(registry: SoldierVisualRegistry) -> void:
	_registry = registry
	_box_mesh = BoxMesh.new()
	_box_mesh.size = Vector3.ONE
	_animation_library = AnimationLibraryType.build_library()
	for spec: SoldierVisualArchetype in registry.entries:
		var body_material := StandardMaterial3D.new()
		body_material.albedo_color = spec.base_color
		body_material.roughness = 0.84
		_body_materials.append(body_material)
		var equipment_material := StandardMaterial3D.new()
		equipment_material.albedo_color = spec.equipment_color
		equipment_material.roughness = 0.70
		_equipment_materials.append(equipment_material)

func ensure_capacity(requested_count: int) -> void:
	var bounded_count: int = clampi(requested_count, 0, MAX_FULL_ACTORS)
	while allocated_actors.size() < bounded_count:
		var actor := ActorType.new()
		actor.name = "NearActor_%03d" % allocated_actors.size()
		add_child(actor)
		actor.setup(_box_mesh, _animation_library)
		allocated_actors.append(actor)

func update_near_soldiers(
	near_soldier_ids: PackedInt32Array,
	near_count: int,
	simulation: BattleCrowdSimulation
) -> void:
	var started_usec: int = Time.get_ticks_usec()
	var previous_count: int = active_actor_count
	active_actor_count = clampi(near_count, 0, MAX_FULL_ACTORS)
	ensure_capacity(active_actor_count)
	var update_slot_count: int = maxi(previous_count, active_actor_count)
	for slot: int in range(update_slot_count):
		var actor: CrowdNearActor3D = allocated_actors[slot]
		if slot < active_actor_count:
			var soldier_id: int = near_soldier_ids[slot]
			promote_to_near_actor(slot, soldier_id, simulation)
		elif actor.current_soldier_id >= 0:
			demote_to_crowd(slot)
	_previous_active_actor_count = active_actor_count
	last_update_cpu_ms = float(Time.get_ticks_usec() - started_usec) / 1000.0

func promote_to_near_actor(slot: int, soldier_id: int, simulation: BattleCrowdSimulation) -> void:
	if slot < 0 or slot >= allocated_actors.size():
		return
	var actor: CrowdNearActor3D = allocated_actors[slot]
	var archetype_id: int = simulation.soldier_visual_archetype[soldier_id]
	var spec: SoldierVisualArchetype = _registry.get_archetype(archetype_id)
	actor.activate(
		soldier_id,
		simulation,
		spec,
		_body_materials[spec.id],
		_equipment_materials[spec.id]
	)

func demote_to_crowd(slot: int) -> void:
	if slot < 0 or slot >= allocated_actors.size():
		return
	allocated_actors[slot].deactivate()

func allocated_skeleton_count() -> int:
	return allocated_actors.size()

func allocated_animation_player_count() -> int:
	return allocated_actors.size()

func set_actor_visible(slot: int, is_visible: bool) -> void:
	if slot < 0 or slot >= allocated_actors.size():
		return
	var actor: CrowdNearActor3D = allocated_actors[slot]
	if actor.current_soldier_id >= 0:
		actor.visible = is_visible
