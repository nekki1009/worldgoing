extends "res://scripts/tests/site_building_ui_test.gd"
## Private C36 error boundary; retains the original fixture and deadline owners.
class TerminalFirstError extends Logger:
	var tree: SceneTree
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
		if first: tree.call_deferred("_stop_on_first_error")
	func has_failed() -> bool:
		mutex.lock()
		var value: bool = failed
		mutex.unlock()
		return value

var _terminal_error: TerminalFirstError
func _install_terminal_guard() -> void:
	_terminal_error = TerminalFirstError.new()
	_terminal_error.tree = self
	OS.add_logger(_terminal_error)
func _finalize() -> void:
	if _terminal_error == null: return
	OS.remove_logger(_terminal_error)
	_terminal_error.tree = null
	_terminal_error = null

func _stop_on_first_error() -> void:
	quit(1)
func _guard() -> bool:
	if _terminal_error != null and _terminal_error.has_failed():
		quit(1)
		return false
	return true
func _must(condition: bool, message: String) -> bool:
	if not _guard(): return false
	if condition: return true
	push_error(message)
	quit(1)
	return false
func _process(delta: float) -> bool:
	if not _guard(): return false
	var value: bool = super._process(delta)
	if not _guard(): return false
	return value
func _finish_terminal_pass(message: String) -> void:
	if not _guard(): return
	if Time.get_ticks_msec() > deadline:
		super._process(0.0)
		return
	await process_frame
	if not _guard(): return
	if Time.get_ticks_msec() > deadline:
		super._process(0.0)
		return
	print(message)
	if not _guard(): return
	quit(0)
