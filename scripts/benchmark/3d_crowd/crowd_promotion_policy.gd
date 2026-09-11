class_name CrowdPromotionPolicy
extends RefCounted

const BattleCrowdSimulationType = preload("res://scripts/benchmark/3d_crowd/battle_crowd_simulation.gd")

const MAX_NEAR_ACTORS: int = 128
const PROMOTE_DISTANCE: float = 45.0
const DEMOTE_DISTANCE: float = 52.0
const TIE_EPSILON: float = 0.000001

var max_near_actors: int = MAX_NEAR_ACTORS
var promote_distance: float = PROMOTE_DISTANCE
var demote_distance: float = DEMOTE_DISTANCE

var _resolved_slots: PackedInt32Array = PackedInt32Array()
var _selected_flags: PackedByteArray = PackedByteArray()
var _candidate_formation_flags: PackedByteArray = PackedByteArray()
var _candidate_soldier_flags: PackedByteArray = PackedByteArray()
var _candidate_soldier_ids: PackedInt32Array = PackedInt32Array()
var _candidate_distance_squared: PackedFloat32Array = PackedFloat32Array()
var _candidate_soldier_count: int = 0
var _prepared_soldier_count: int = -1
var _prepared_formation_count: int = -1
var last_candidate_count: int = 0
var last_candidate_formation_count: int = 0
var last_candidate_soldier_count: int = 0
var last_candidate_position_queries: int = 0

func prepare(simulation: BattleCrowdSimulation, requested_max_near_actors: int = MAX_NEAR_ACTORS) -> void:
	max_near_actors = clampi(requested_max_near_actors, 0, MAX_NEAR_ACTORS)
	if _resolved_slots.size() != max_near_actors:
		_resolved_slots.resize(max_near_actors)
		_resolved_slots.fill(-1)
	var soldier_count: int = simulation.soldier_alive.size() if simulation != null else 0
	if _selected_flags.size() != soldier_count:
		_selected_flags.resize(soldier_count)
		_selected_flags.fill(0)
	if _candidate_soldier_flags.size() != soldier_count:
		_candidate_soldier_flags.resize(soldier_count)
		_candidate_soldier_flags.fill(0)
	if _candidate_soldier_ids.size() != soldier_count:
		_candidate_soldier_ids.resize(soldier_count)
	if _candidate_distance_squared.size() != soldier_count:
		_candidate_distance_squared.resize(soldier_count)
	var formation_count: int = simulation.active_formation_count if simulation != null else 0
	if _candidate_formation_flags.size() != BattleCrowdSimulationType.FORMATION_COUNT:
		_candidate_formation_flags.resize(BattleCrowdSimulationType.FORMATION_COUNT)
		_candidate_formation_flags.fill(0)
	_prepared_soldier_count = soldier_count
	_prepared_formation_count = formation_count

func resolve(
	simulation: BattleCrowdSimulation,
	camera_position: Vector3,
	previous_slots: PackedInt32Array
) -> PackedInt32Array:
	if simulation == null:
		return _resolved_slots
	if (
		_prepared_soldier_count != simulation.soldier_alive.size()
		or _resolved_slots.size() != max_near_actors
		or _prepared_formation_count != simulation.active_formation_count
	):
		prepare(simulation, max_near_actors)

	# ponytail: fixed candidate buffers keep the selector allocation-free; each
	# candidate position is resolved once before deterministic slot selection.
	for slot: int in range(_resolved_slots.size()):
		_resolved_slots[slot] = -1
	_selected_flags.fill(0)
	last_candidate_count = 0
	last_candidate_formation_count = 0
	last_candidate_soldier_count = 0
	last_candidate_position_queries = 0
	if max_near_actors == 0:
		return _resolved_slots

	var promote_distance_squared: float = promote_distance * promote_distance
	var demote_distance_squared: float = demote_distance * demote_distance
	var selected_count: int = 0
	var active_count: int = mini(simulation.active_soldier_count, simulation.soldier_alive.size())
	_candidate_formation_flags.fill(0)
	for formation_id: int in range(simulation.active_formation_count):
		var formation: CrowdFormationState = simulation.formations[formation_id]
		var candidate_radius: float = demote_distance + _formation_radius(formation)
		if camera_position.distance_squared_to(formation.center_position) <= candidate_radius * candidate_radius:
			_candidate_formation_flags[formation_id] = 1
			last_candidate_formation_count += 1
	_candidate_soldier_flags.fill(0)
	_candidate_soldier_count = 0
	for formation_id: int in range(simulation.active_formation_count):
		if _candidate_formation_flags[formation_id] == 0:
			continue
		var base_index: int = formation_id * BattleCrowdSimulationType.SOLDIERS_PER_FORMATION
		for slot_index: int in range(BattleCrowdSimulationType.SOLDIERS_PER_FORMATION):
			var soldier_index: int = base_index + slot_index
			if soldier_index >= active_count or simulation.soldier_alive[soldier_index] == 0:
				continue
			last_candidate_position_queries += 1
			var distance_squared: float = camera_position.distance_squared_to(
				simulation.get_soldier_world_position(soldier_index)
			)
			if distance_squared > demote_distance_squared:
				continue
			_candidate_soldier_flags[soldier_index] = 1
			_candidate_soldier_ids[_candidate_soldier_count] = soldier_index
			_candidate_distance_squared[soldier_index] = distance_squared
			_candidate_soldier_count += 1
			if distance_squared <= promote_distance_squared:
				last_candidate_count += 1
	last_candidate_soldier_count = _candidate_soldier_count

	# Retain an existing actor in its slot while it remains inside the wider
	# demotion radius. This makes camera movement deterministic and prevents
	# needless actor churn at the near boundary.
	for slot: int in range(max_near_actors):
		if slot >= previous_slots.size():
			break
		var soldier_index: int = previous_slots[slot]
		if not _is_valid_soldier(simulation, soldier_index, active_count) or _candidate_soldier_flags[soldier_index] == 0:
			continue
		if _selected_flags[soldier_index] != 0:
			continue
		var retained_distance_squared: float = _candidate_distance_squared[soldier_index]
		if retained_distance_squared > demote_distance_squared:
			continue
		_resolved_slots[slot] = soldier_index
		_selected_flags[soldier_index] = 1
		selected_count += 1

	# Fill free pool slots by nearest candidate, then soldier id. The second
	# comparison is the deterministic tie-breaker for equal positions.
	while selected_count < max_near_actors:
		var best_id: int = -1
		var best_distance_squared: float = INF
		for candidate_index: int in range(_candidate_soldier_count):
			var soldier_index: int = _candidate_soldier_ids[candidate_index]
			if _selected_flags[soldier_index] != 0:
				continue
			var distance_squared: float = _candidate_distance_squared[soldier_index]
			if distance_squared > promote_distance_squared:
				continue
			if _is_better_candidate(distance_squared, soldier_index, best_distance_squared, best_id):
				best_id = soldier_index
				best_distance_squared = distance_squared
		if best_id < 0:
			break
		var free_slot: int = _first_free_slot()
		if free_slot < 0:
			break
		_resolved_slots[free_slot] = best_id
		_selected_flags[best_id] = 1
		selected_count += 1

	# If retained actors filled the pool, replace only when a closer candidate
	# exists. Existing slots stay stable unless the replacement is unambiguous.
	var changed_replacement: bool = true
	while selected_count == max_near_actors and changed_replacement:
		changed_replacement = false
		var best_replacement_id: int = -1
		var best_replacement_distance_squared: float = INF
		for candidate_index: int in range(_candidate_soldier_count):
			var soldier_index: int = _candidate_soldier_ids[candidate_index]
			if _selected_flags[soldier_index] != 0:
				continue
			var candidate_distance_squared: float = _candidate_distance_squared[soldier_index]
			if candidate_distance_squared > promote_distance_squared:
				continue
			if _is_better_candidate(
				candidate_distance_squared,
				soldier_index,
				best_replacement_distance_squared,
				best_replacement_id
			):
				best_replacement_id = soldier_index
				best_replacement_distance_squared = candidate_distance_squared
		if best_replacement_id < 0:
			break

		var farthest_slot: int = -1
		var farthest_distance_squared: float = -1.0
		var farthest_id: int = -1
		for slot: int in range(max_near_actors):
			var retained_id: int = _resolved_slots[slot]
			if retained_id < 0:
				continue
			var retained_distance_squared: float = _candidate_distance_squared[retained_id]
			if (
				retained_distance_squared > farthest_distance_squared + TIE_EPSILON
				or (
					is_equal_approx(retained_distance_squared, farthest_distance_squared)
					and retained_id > farthest_id
				)
			):
				farthest_slot = slot
				farthest_distance_squared = retained_distance_squared
				farthest_id = retained_id
		if farthest_slot < 0 or not _is_better_candidate(
			best_replacement_distance_squared,
			best_replacement_id,
			farthest_distance_squared,
			farthest_id
		):
			break
		_selected_flags[farthest_id] = 0
		_selected_flags[best_replacement_id] = 1
		_resolved_slots[farthest_slot] = best_replacement_id
		changed_replacement = true

	return _resolved_slots

func slots_are_unique_and_valid(
	simulation: BattleCrowdSimulation,
	slots: PackedInt32Array
) -> bool:
	if simulation == null:
		return slots.is_empty()
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(simulation.soldier_alive.size())
	seen.fill(0)
	var active_count: int = mini(simulation.active_soldier_count, seen.size())
	for soldier_index: int in slots:
		if soldier_index < 0:
			continue
		if soldier_index >= active_count or seen[soldier_index] != 0:
			return false
		seen[soldier_index] = 1
	return true

func _first_free_slot() -> int:
	for slot: int in range(_resolved_slots.size()):
		if _resolved_slots[slot] < 0:
			return slot
	return -1

func _is_valid_soldier(
	simulation: BattleCrowdSimulation,
	soldier_index: int,
	active_count: int
) -> bool:
	return (
		soldier_index >= 0
		and soldier_index < active_count
		and soldier_index < simulation.soldier_alive.size()
		and simulation.soldier_alive[soldier_index] != 0
	)

func _is_better_candidate(
	distance_squared: float,
	soldier_index: int,
	best_distance_squared: float,
	best_id: int
) -> bool:
	if best_id < 0:
		return true
	if distance_squared < best_distance_squared - TIE_EPSILON:
		return true
	return is_equal_approx(distance_squared, best_distance_squared) and soldier_index < best_id

func _formation_radius(formation: CrowdFormationState) -> float:
	var half_width: float = maxf(formation.formation_width, formation.spacing) * 0.5
	var half_depth: float = maxf(formation.formation_depth, formation.spacing) * 0.5
	return Vector2(half_width, half_depth).length() + formation.spacing
