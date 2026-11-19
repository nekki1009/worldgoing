extends "res://scripts/terrain_lab/site_captivity_supply.gd"
## Preserve all original validation, copies, event order and commit semantics.
var profiler: RefCounted

func _event_members() -> Dictionary:
	var token: Dictionary = profiler.begin("supply.event_members")
	var result: Dictionary = super._event_members()
	profiler.end(token)
	return result

func _all_members() -> Dictionary:
	var token: Dictionary = profiler.begin("supply.all_members")
	var result: Dictionary = super._all_members()
	profiler.end(token)
	return result

func _states(copy_state: bool = true) -> Dictionary:
	var token: Dictionary = profiler.begin("supply.states")
	var result: Dictionary = super._states(copy_state)
	profiler.end(token)
	return result

func event_change_guard(target_id: int, captor_id: int, capturing: bool, event_context: Dictionary = {}) -> Dictionary:
	var token: Dictionary = profiler.begin("supply.event_change_guard")
	var result: Dictionary = super.event_change_guard(target_id, captor_id, capturing, event_context)
	profiler.end(token)
	return result

func _prepare_change(target_id: int, captor_id: int, capturing: bool, event_context: Dictionary = {}) -> Dictionary:
	var token: Dictionary = profiler.begin("supply.prepare_change")
	var result: Dictionary = super._prepare_change(target_id, captor_id, capturing, event_context)
	profiler.end(token)
	return result

func _ensure(home: Dictionary, states: Dictionary, members: Dictionary, moves: Array, at_seconds: float, target_id: int, feeding: Variant = null) -> bool:
	var token: Dictionary = profiler.begin("supply.ensure_owner")
	var result: bool = super._ensure(home, states, members, moves, at_seconds, target_id, feeding)
	profiler.end(token)
	return result

func _move(identity: int, source: String, target: String, states: Dictionary, members: Dictionary, moves: Array, at_seconds: float, feeding: Variant = null) -> bool:
	var token: Dictionary = profiler.begin("supply.move_member")
	var result: bool = super._move(identity, source, target, states, members, moves, at_seconds, feeding)
	profiler.end(token)
	return result

func _align(owner: Dictionary, at_seconds: float) -> bool:
	var token: Dictionary = profiler.begin("supply.align_clock")
	var result: bool = super._align(owner, at_seconds)
	profiler.end(token)
	return result

func _add(state: Dictionary, members: Dictionary, ids: Array) -> bool:
	var token: Dictionary = profiler.begin("supply.add_members")
	var result: bool = super._add(state, members, ids)
	profiler.end(token)
	return result

func _commit_states(plan: Dictionary) -> void:
	var token: Dictionary = profiler.begin("supply.commit_states")
	super._commit_states(plan)
	profiler.end(token)
