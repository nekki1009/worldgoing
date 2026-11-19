extends Logger
## CC048: retain the first engine/contract fault; callers propagate false.
var _mutex: Mutex = Mutex.new()
var _first := ""
var _reported := false

func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == Logger.ERROR_TYPE_WARNING: return
	_mutex.lock()
	if _first.is_empty(): _first = "%s:%d %s: %s %s" % [file, line, function, code, rationale]
	_mutex.unlock()

func accepts(tree: SceneTree, condition: bool, label: String) -> bool:
	_mutex.lock()
	if not condition and _first.is_empty(): _first = label
	var first: String = _first
	var report: bool = not _reported and not first.is_empty()
	if report: _reported = true
	_mutex.unlock()
	if first.is_empty(): return true
	if report: push_error("TECH_RETURNS_FIRST_ERROR: " + first)
	tree.quit(1)
	return false
