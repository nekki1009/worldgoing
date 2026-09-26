class_name SiteRouteBudget
extends RefCounted
## Route search budget and epoch round-robin fair scheduler.
## Enforces per-formation and site-wide search and node expansion limits.

const LOCAL_ROUTE_MAX_EXPANSIONS := 256
const MAX_LOCAL_ROUTE_CALLS_PER_FORMATION_TICK := 8
const MAX_LOCAL_EXPANSIONS_PER_FORMATION_TICK := 1024
const SITE_MAX_EXPANSIONS_PER_TICK := 8192
const BASE_FORMATION_QUANTUM_EXPANSIONS := 128
const BASE_FORMATION_QUANTUM_CALLS := 2

var site_expansions_used: int = 0
var site_calls_used: int = 0
var epoch_cursor: int = 0

## Per-tick allocations: formation_id (int) -> Dictionary
var _formation_allocations: Dictionary = {}

func begin_tick(active_formations: Array) -> void:
	site_expansions_used = 0
	site_calls_used = 0
	_formation_allocations.clear()

	if active_formations.is_empty():
		return

	var eligible: Array = []
	for f in active_formations:
		if f != null and is_instance_valid(f):
			eligible.append(f)

	if eligible.is_empty():
		return

	var count: int = eligible.size()
	var site_remaining := SITE_MAX_EXPANSIONS_PER_TICK

	# Pass 1: Allocate base quantum using round-robin from epoch_cursor
	var served_count: int = 0
	for i in range(count):
		var idx := (epoch_cursor + i) % count
		var formation = eligible[idx]
		var fid: int = _extract_formation_id(formation)

		if site_remaining >= BASE_FORMATION_QUANTUM_EXPANSIONS:
			_formation_allocations[fid] = {
				"remaining_expansions": BASE_FORMATION_QUANTUM_EXPANSIONS,
				"remaining_calls": BASE_FORMATION_QUANTUM_CALLS,
				"expansions_used": 0,
				"calls_used": 0,
				"deferred": false
			}
			site_remaining -= BASE_FORMATION_QUANTUM_EXPANSIONS
			served_count += 1
		else:
			_formation_allocations[fid] = {
				"remaining_expansions": 0,
				"remaining_calls": 0,
				"expansions_used": 0,
				"calls_used": 0,
				"deferred": true
			}

	# Advance epoch_cursor by served_count
	epoch_cursor = (epoch_cursor + served_count) % count

	# Pass 2: If all formations were served base quantum and site has remaining budget,
	# distribute extra budget up to MAX_LOCAL_EXPANSIONS_PER_FORMATION_TICK
	if served_count == count and site_remaining > 0:
		var extra_per_formation: int = mini(
			MAX_LOCAL_EXPANSIONS_PER_FORMATION_TICK - BASE_FORMATION_QUANTUM_EXPANSIONS,
			int(site_remaining / count)
		)
		if extra_per_formation > 0:
			for fid in _formation_allocations.keys():
				var alloc: Dictionary = _formation_allocations[fid]
				if not alloc.deferred:
					alloc.remaining_expansions += extra_per_formation
					alloc.remaining_calls = MAX_LOCAL_ROUTE_CALLS_PER_FORMATION_TICK

func _extract_formation_id(formation: Object) -> int:
	if formation == null:
		return 0
	if formation.has_method("try_get_formation_id"):
		var fid: int = int(formation.call("try_get_formation_id"))
		if fid <= 0:
			push_error("Formation has non-positive runtime ID: " + str(fid))
			return 0
		return fid
	if formation.has_method("get_formation_id"):
		return int(formation.call("get_formation_id"))
	if "formation_runtime_id" in formation and int(formation.get("formation_runtime_id")) > 0:
		return int(formation.get("formation_runtime_id"))
	if "team_id" in formation:
		return int(formation.get("team_id"))
	return formation.get_instance_id()

func can_search(formation_id: int) -> bool:
	if not _formation_allocations.has(formation_id):
		return false
	var alloc: Dictionary = _formation_allocations[formation_id]
	if alloc.deferred or alloc.remaining_calls <= 0 or alloc.remaining_expansions <= 0:
		return false
	return site_expansions_used < SITE_MAX_EXPANSIONS_PER_TICK

func get_call_budget(formation_id: int) -> int:
	if not can_search(formation_id):
		return 0
	var alloc: Dictionary = _formation_allocations[formation_id]
	var site_remaining := maxi(0, SITE_MAX_EXPANSIONS_PER_TICK - site_expansions_used)
	return mini(LOCAL_ROUTE_MAX_EXPANSIONS, mini(int(alloc.remaining_expansions), site_remaining))

func record_search(formation_id: int, expansions: int) -> void:
	if not _formation_allocations.has(formation_id):
		return
	var alloc: Dictionary = _formation_allocations[formation_id]
	alloc.remaining_calls = maxi(0, int(alloc.remaining_calls) - 1)
	alloc.remaining_expansions = maxi(0, int(alloc.remaining_expansions) - expansions)
	alloc.calls_used = int(alloc.calls_used) + 1
	alloc.expansions_used = int(alloc.expansions_used) + expansions
	site_expansions_used += expansions
	site_calls_used += 1

func is_scheduler_deferred(formation_id: int) -> bool:
	if not _formation_allocations.has(formation_id):
		return true
	return bool(_formation_allocations[formation_id].deferred)

func get_allocation(formation_id: int) -> Dictionary:
	return _formation_allocations.get(formation_id, {
		"remaining_expansions": 0,
		"remaining_calls": 0,
		"expansions_used": 0,
		"calls_used": 0,
		"deferred": true
	})

func can_request_route(formation_id: int) -> bool:
	return can_search(formation_id)

func request_route_budget(formation_id: int) -> int:
	return get_call_budget(formation_id)

func record_route_result(formation_id: int, _calls: int, expansions: int) -> void:
	record_search(formation_id, expansions)
