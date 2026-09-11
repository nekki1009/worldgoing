class_name BattleCrowdSimulation
extends RefCounted

const FORMATION_COUNT: int = 100
const SOLDIERS_PER_FORMATION: int = 100
const SLOT_COLUMNS: int = 10
const SLOT_ROWS: int = 10
const SLOT_SPACING: float = 1.25
const FORMATION_GRID_COLUMNS: int = 10
const FORMATION_GRID_SPACING: float = 34.0
const ARCHETYPE_NAMES: Array[StringName] = [
	&"LIGHT_INFANTRY", &"HEAVY_INFANTRY", &"SPEARMAN", &"SWORD_SHIELD"
]

enum BenchmarkMode { PLACEHOLDER, HUMANOID_STATIC, HUMANOID_ANIMATED, HUMANOID_LOD }
enum AnimationState { IDLE, WALK, ATTACK, DEAD }

var seed: int = 123456789
var mode: int = BenchmarkMode.HUMANOID_LOD
var active_formation_count: int = FORMATION_COUNT
var active_soldier_count: int = FORMATION_COUNT * SOLDIERS_PER_FORMATION
var formations: Array[CrowdFormationState] = []

# SoldierState columns. These are authoritative; renderer state never writes them.
var soldier_id: PackedInt32Array = PackedInt32Array()
var soldier_formation_id: PackedInt32Array = PackedInt32Array()
var soldier_slot_index: PackedInt32Array = PackedInt32Array()
var soldier_local_x: PackedFloat32Array = PackedFloat32Array()
var soldier_local_z: PackedFloat32Array = PackedFloat32Array()
var soldier_world_positions: PackedVector3Array = PackedVector3Array()
var soldier_facing: PackedFloat32Array = PackedFloat32Array()
var soldier_animation_state: PackedInt32Array = PackedInt32Array()
var soldier_animation_time: PackedFloat32Array = PackedFloat32Array()
var soldier_animation_phase: PackedFloat32Array = PackedFloat32Array()
var soldier_visual_archetype: PackedInt32Array = PackedInt32Array()
var soldier_visual_variant: PackedInt32Array = PackedInt32Array()
var soldier_color_variant: PackedInt32Array = PackedInt32Array()
var soldier_equipment_variant: PackedInt32Array = PackedInt32Array()
var soldier_alive: PackedInt32Array = PackedInt32Array()

# Renderer-facing event/measurement columns. FormationState plus the local slot
# columns are authoritative; soldier_world_positions is an optional compatibility
# cache for the legacy per-instance renderer and older contract tests.
var soldier_animation_dirty_ids: PackedInt32Array = PackedInt32Array()
var animation_dirty_count: int = 0
var last_world_position_updates: int = 0
var lazy_world_position_queries: int = 0
var world_position_cache_enabled: bool = true
var last_formation_transform_updates: int = 0
var last_basis_constructions: int = 0

var _random: RandomNumberGenerator = RandomNumberGenerator.new()
var _animation_clock: float = 0.0
var _formation_basis_cache: Array[Basis] = []

func initialize(simulation_seed: int) -> void:
	seed = simulation_seed
	_random.seed = seed
	_animation_clock = 0.0
	world_position_cache_enabled = true
	animation_dirty_count = 0
	last_world_position_updates = 0
	lazy_world_position_queries = 0
	last_formation_transform_updates = 0
	last_basis_constructions = 0
	formations.clear()
	_formation_basis_cache.resize(FORMATION_COUNT)
	var total_soldiers: int = FORMATION_COUNT * SOLDIERS_PER_FORMATION
	_allocate_soldier_columns(total_soldiers)

	for formation_id: int in range(FORMATION_COUNT):
		var formation := CrowdFormationState.new()
		formation.formation_id = formation_id
		var column: int = posmod(formation_id, FORMATION_GRID_COLUMNS)
		var row: int = floori(float(formation_id) / float(FORMATION_GRID_COLUMNS))
		formation.center_position = Vector3(
			(float(column) - 4.5) * FORMATION_GRID_SPACING,
			0.0,
			(float(row) - 4.5) * FORMATION_GRID_SPACING
		)
		formation.facing = _random.randf_range(-PI, PI)
		_formation_basis_cache[formation_id] = Basis(Vector3.UP, formation.facing)
		formation.movement_speed = _random.randf_range(2.5, 4.0)
		formation.spacing = SLOT_SPACING
		formation.formation_width = float(SLOT_COLUMNS) * SLOT_SPACING
		formation.formation_depth = float(SLOT_ROWS) * SLOT_SPACING
		formation.formation_type = ARCHETYPE_NAMES[posmod(formation_id, ARCHETYPE_NAMES.size())]
		formation.destination = _destination_for(formation)
		formation.movement_state = &"MoveToDestination"
		formations.append(formation)

		for slot_index: int in range(SOLDIERS_PER_FORMATION):
			var index: int = formation_id * SOLDIERS_PER_FORMATION + slot_index
			var local_position: Vector3 = CrowdFormationSlotGenerator.local_position(
				slot_index, SLOT_COLUMNS, SLOT_ROWS, SLOT_SPACING
			)
			var archetype_id: int = posmod(formation_id, ARCHETYPE_NAMES.size())
			var color_variant: int = _random.randi_range(0, 3)
			var equipment_variant: int = _random.randi_range(0, 2)
			soldier_id[index] = index
			soldier_formation_id[index] = formation_id
			soldier_slot_index[index] = slot_index
			soldier_local_x[index] = local_position.x
			soldier_local_z[index] = local_position.z
			soldier_world_positions[index] = formation.center_position + local_position
			soldier_facing[index] = formation.facing
			soldier_animation_state[index] = AnimationState.IDLE
			soldier_animation_time[index] = 0.0
			soldier_animation_phase[index] = _random.randf()
			soldier_visual_archetype[index] = archetype_id
			soldier_color_variant[index] = color_variant
			soldier_equipment_variant[index] = equipment_variant
			soldier_visual_variant[index] = color_variant
			soldier_alive[index] = 1

	set_active_soldiers(active_soldier_count)
	set_mode(mode)

func set_active_soldiers(requested_count: int) -> void:
	var requested_formations: int = maxi(1, ceili(float(requested_count) / float(SOLDIERS_PER_FORMATION)))
	active_formation_count = clampi(requested_formations, 1, FORMATION_COUNT)
	active_soldier_count = active_formation_count * SOLDIERS_PER_FORMATION
	for formation_id: int in range(FORMATION_COUNT):
		var is_active: bool = formation_id < active_formation_count
		formations[formation_id].active = is_active
		for slot_index: int in range(SOLDIERS_PER_FORMATION):
			var index: int = formation_id * SOLDIERS_PER_FORMATION + slot_index
			soldier_alive[index] = 1 if is_active else 0

func set_mode(next_mode: int) -> void:
	mode = clampi(next_mode, BenchmarkMode.PLACEHOLDER, BenchmarkMode.HUMANOID_LOD)
	animation_dirty_count = 0
	for index: int in range(active_soldier_count):
		soldier_animation_state[index] = AnimationState.IDLE
		soldier_animation_time[index] = 0.0
		if mode == BenchmarkMode.HUMANOID_STATIC:
			if world_position_cache_enabled:
				soldier_world_positions[index] = _world_position_for(index)
				soldier_facing[index] = _facing_for(index)

func set_world_position_cache_enabled(enabled: bool) -> void:
	if world_position_cache_enabled == enabled:
		return
	world_position_cache_enabled = enabled
	last_world_position_updates = 0
	if world_position_cache_enabled:
		refresh_world_position_cache()

func reset_world_position_query_count() -> void:
	lazy_world_position_queries = 0

func refresh_world_position_cache() -> void:
	last_world_position_updates = 0
	for index: int in range(active_soldier_count):
		soldier_world_positions[index] = _world_position_for(index)
		soldier_facing[index] = _facing_for(index)
		last_world_position_updates += 1

func step(delta: float) -> void:
	animation_dirty_count = 0
	last_world_position_updates = 0
	last_formation_transform_updates = 0
	last_basis_constructions = 0
	if mode == BenchmarkMode.HUMANOID_STATIC or delta <= 0.0:
		return
	_animation_clock = fmod(_animation_clock + delta, 60.0)
	for formation_id: int in range(active_formation_count):
		var formation: CrowdFormationState = formations[formation_id]
		var to_destination: Vector3 = formation.destination - formation.center_position
		to_destination.y = 0.0
		var distance: float = to_destination.length()
		if distance <= 0.8:
			formation.destination_cycle += 1
			formation.destination = _destination_for(formation)
			to_destination = formation.destination - formation.center_position
			to_destination.y = 0.0
			distance = to_destination.length()
		if distance > 0.001:
			var direction: Vector3 = to_destination / distance
			var previous_center: Vector3 = formation.center_position
			var previous_facing: float = formation.facing
			formation.center_position += direction * formation.movement_speed * delta
			formation.facing = lerp_angle(
				formation.facing,
				atan2(direction.x, direction.z),
				minf(1.0, delta * 6.0)
			)
			var facing_changed: bool = absf(angle_difference(previous_facing, formation.facing)) > 0.00001
			if formation.center_position.distance_squared_to(previous_center) > 0.000001 or facing_changed:
				last_formation_transform_updates += 1
			if facing_changed:
				_update_formation_basis_cache(formation.formation_id)
			formation.movement_state = &"MoveToDestination"
		_update_formation_soldiers(formation, delta)

func _allocate_soldier_columns(total_soldiers: int) -> void:
	soldier_id.resize(total_soldiers)
	soldier_formation_id.resize(total_soldiers)
	soldier_slot_index.resize(total_soldiers)
	soldier_local_x.resize(total_soldiers)
	soldier_local_z.resize(total_soldiers)
	soldier_world_positions.resize(total_soldiers)
	soldier_facing.resize(total_soldiers)
	soldier_animation_state.resize(total_soldiers)
	soldier_animation_time.resize(total_soldiers)
	soldier_animation_phase.resize(total_soldiers)
	soldier_visual_archetype.resize(total_soldiers)
	soldier_visual_variant.resize(total_soldiers)
	soldier_color_variant.resize(total_soldiers)
	soldier_equipment_variant.resize(total_soldiers)
	soldier_alive.resize(total_soldiers)
	soldier_animation_dirty_ids.resize(total_soldiers)
	soldier_animation_dirty_ids.fill(-1)

func _world_position_for(index: int) -> Vector3:
	var formation_id: int = soldier_formation_id[index]
	var formation: CrowdFormationState = formations[formation_id]
	return formation.center_position + _formation_basis_cache[formation_id] * Vector3(
		soldier_local_x[index], 0.0, soldier_local_z[index]
	)

func _facing_for(index: int) -> float:
	return formations[soldier_formation_id[index]].facing

func _update_formation_basis_cache(formation_id: int) -> void:
	_formation_basis_cache[formation_id] = Basis(Vector3.UP, formations[formation_id].facing)
	last_basis_constructions += 1

func _update_formation_soldiers(formation: CrowdFormationState, delta: float) -> void:
	var basis: Basis = _formation_basis_cache[formation.formation_id]
	var base_index: int = formation.formation_id * SOLDIERS_PER_FORMATION
	var animated: bool = mode == BenchmarkMode.HUMANOID_ANIMATED or mode == BenchmarkMode.HUMANOID_LOD
	for slot_index: int in range(SOLDIERS_PER_FORMATION):
		var index: int = base_index + slot_index
		if soldier_alive[index] == 0:
			continue
		if world_position_cache_enabled:
			soldier_world_positions[index] = formation.center_position + basis * Vector3(
				soldier_local_x[index], 0.0, soldier_local_z[index]
			)
			last_world_position_updates += 1
			soldier_facing[index] = formation.facing
		if not animated:
			continue
		soldier_animation_time[index] = fmod(soldier_animation_time[index] + delta, 60.0)
		var attack_window: float = fmod(
			_animation_clock + float(formation.formation_id) * 0.23 + float(slot_index) * 0.031,
			7.0
		)
		var next_animation_state: int = (
			AnimationState.ATTACK if slot_index < 8 and attack_window > 5.8 else AnimationState.WALK
		)
		if soldier_animation_state[index] != next_animation_state:
			soldier_animation_state[index] = next_animation_state
			if animation_dirty_count < soldier_animation_dirty_ids.size():
				soldier_animation_dirty_ids[animation_dirty_count] = index
				animation_dirty_count += 1

func get_soldier_world_position(index: int) -> Vector3:
	if index < 0 or index >= soldier_formation_id.size():
		return Vector3.ZERO
	if world_position_cache_enabled:
		return soldier_world_positions[index]
	lazy_world_position_queries += 1
	return _world_position_for(index)

func get_soldier_facing(index: int) -> float:
	if index < 0 or index >= soldier_formation_id.size():
		return 0.0
	if world_position_cache_enabled:
		return soldier_facing[index]
	return _facing_for(index)

func _destination_for(formation: CrowdFormationState) -> Vector3:
	var angle_degrees: float = fmod(
		float(posmod(seed, 360)) + float(formation.formation_id * 41)
		+ float(formation.destination_cycle * 67),
		360.0
	)
	var radius: float = 18.0 + float(posmod(abs(seed) + formation.formation_id * 17
		+ formation.destination_cycle * 29, 90)) * 0.45
	var angle: float = deg_to_rad(angle_degrees)
	return formation.center_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
