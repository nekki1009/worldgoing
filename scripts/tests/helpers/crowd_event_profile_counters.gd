extends RefCounted
## Test-only nested timers. Residual includes local work and timer bookkeeping.
var enabled := false
var methods := {}
var paths := {}
var stack: Array[Dictionary] = []
var batches: Array[Dictionary] = []

func begin(stage: String) -> Dictionary:
	if not enabled: return {}
	var token := {"stage": stage, "path": stage if stack.is_empty() else str(stack.back().path) + " -> " + stage,
		"started": Time.get_ticks_usec(), "children_us": 0}
	stack.append(token)
	return token

func end(token: Dictionary) -> int:
	if token.is_empty(): return 0
	var elapsed := Time.get_ticks_usec() - int(token.started)
	assert(not stack.is_empty() and is_same(stack.back(), token))
	stack.pop_back()
	if not stack.is_empty(): stack.back().children_us += elapsed
	var residual := maxi(0, elapsed - int(token.children_us))
	_record(methods, str(token.stage), elapsed, residual)
	_record(paths, str(token.path), elapsed, residual)
	return elapsed

func _record(target: Dictionary, key: String, elapsed: int, residual: int) -> void:
	if not target.has(key): target[key] = {"calls": 0, "inclusive_us": 0, "max_inclusive_us": 0, "residual_us": 0, "max_residual_us": 0}
	var metric: Dictionary = target[key]
	metric.calls += 1
	metric.inclusive_us += elapsed
	metric.max_inclusive_us = maxi(int(metric.max_inclusive_us), elapsed)
	metric.residual_us += residual
	metric.max_residual_us = maxi(int(metric.max_residual_us), residual)

func snapshot() -> Dictionary:
	assert(stack.is_empty())
	return {"methods": methods.duplicate(true), "call_paths": paths.duplicate(true), "nonempty_batches": batches.duplicate(true)}
