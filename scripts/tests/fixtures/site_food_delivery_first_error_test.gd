extends "res://scripts/tests/site_workflow_test.gd"
## Local delivery-test failure boundary. Original workflow deadline is unchanged.

class FirstErrorLogger extends Logger:
	var owner: SceneTree
	var mutex: Mutex = Mutex.new()
	var failed := false

	func _log_error(_function: String, _file: String, _line: int, _code: String,
			_rationale: String, _editor_notify: bool, error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING: return
		mutex.lock()
		var first: bool = not failed
		failed = true
		mutex.unlock()
		# No logging from the logger callback; preserve the engine's first backtrace.
		if first: owner.call_deferred("_stop_on_first_error")

	func has_failed() -> bool:
		mutex.lock()
		var result: bool = failed
		mutex.unlock()
		return result

var _first_error_logger: FirstErrorLogger
var _done := false
var _last_check := "initialization"

func _install_first_error_guard() -> void:
	_first_error_logger = FirstErrorLogger.new()
	_first_error_logger.owner = self
	OS.add_logger(_first_error_logger)

func _initialize() -> void:
	_install_first_error_guard()
	super._initialize()

func _finalize() -> void:
	if _first_error_logger == null: return
	OS.remove_logger(_first_error_logger)
	_first_error_logger.owner = null
	_first_error_logger = null

func _stop_on_first_error() -> void:
	quit(1)

func _guard() -> bool:
	if _first_error_logger != null and _first_error_logger.has_failed():
		quit(1)
		return false
	return true

func _require(condition: bool, message: String) -> bool:
	if not _guard(): return false
	if not condition:
		push_error(message)
		quit(1)
		return false
	_last_check = message
	print("FOOD_WORKFLOW_CHECKPOINT: ", message, " now_ms=", Time.get_ticks_msec(), " deadline_ms=", deadline)
	return true

func _near(actual: float, expected: float, label: String = "") -> bool:
	var matches: bool = absf(actual - expected) < 0.000001
	if not _require(matches, "%s: %.12f != %.12f" % [label, actual, expected]): return false
	assert(matches)
	return true

func _process(delta: float) -> bool:
	if not _guard(): return false
	if _done: return false # All assertions finished; cleanup still uses the first-error guard.
	if Time.get_ticks_msec() > deadline:
		print("FOOD_WORKFLOW_LAST_COMPLETED_CHECK: ", _last_check, " now_ms=", Time.get_ticks_msec(), " deadline_ms=", deadline)
	var result: bool = super._process(delta)
	if not _guard(): return false
	return result

func _finish_pass(message: String) -> void:
	if not _guard(): return
	if Time.get_ticks_msec() > deadline:
		_process(0.0) # Preserve the parent deadline error/exit; never admit an expired body.
		return
	await process_frame # The same deadline and first-error guard remain active during cleanup.
	if not _guard(): return
	if Time.get_ticks_msec() > deadline:
		_process(0.0)
		return
	_done = true # Only publish after cleanup and the original absolute deadline both pass.
	print(message)
	if not _guard(): return
	quit(0)

func _fixture() -> TerrainData:
	var data: TerrainData = TerrainGenerator.generate(TerrainPreset.Kind.PLAINS, 12345)
	if not _guard(): return null
	Env.initialize(data, "workflow")
	if not _guard(): return null
	var _delivery_check_1: bool = Runtime.initialize_item_storage(data.site).ok
	if not _require(_delivery_check_1, "scripts/tests/fixtures/site_food_delivery_first_error_test.gd:_fixture:4 assertion"): return null
	assert(_delivery_check_1, "scripts/tests/fixtures/site_food_delivery_first_error_test.gd:_fixture:4 assertion")
	# A controlled accessible plot isolates building/production from distribution.
	for y: int in range(15, 55):
		if not _guard(): return null
		for x: int in range(15, 55):
			if not _guard(): return null
			var i: int = data.index(Vector2i(x, y))
			if not _guard(): return null
			data.height_levels[i] = 0
			data.flags[i] = TerrainData.Flag.WALKABLE
			data.ramp_edges[i] = 0
			data.surface_types[i] = TerrainData.Surface.GRASS
			data.groundwater[i] = 80
			data.foundation[i] = 80
			data.fertility[i] = 60
			data.drainage[i] = 70
			data.moisture[i] = 70
			for key: String in data.resources_at.get(i, []):
				if not _guard(): return null
				Env.change(data, key, {"cleared": true, "remaining": 0})
				if not _guard(): return null
	data.site.depot_cell = data.index(Vector2i(20, 20))
	if not _guard(): return null
	data.site.worker.cell = data.index(Vector2i(19, 20))
	if not _guard(): return null
	for item: String in Env.ITEM_NAMES:
		if not _guard(): return null
		data.site.inventory[item] = 100
	data.site.capacity = 10000
	Env.rebuild_indexes(data)
	if not _guard(): return null
	Runtime.rebuild_terrain_edges(data)
	if not _guard(): return null
	return data
