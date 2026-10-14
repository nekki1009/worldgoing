extends Logger
## Test-only scope reporting. No catalog, runner or production mutations.
const CATALOG_PATH := "res://scripts/terrain_lab/site_technology_catalog.gd"
const Catalog = preload("res://scripts/terrain_lab/site_technology_catalog.gd")
var profile := "formal_disabled"
var _catalog_sha := ""
var _enabled_ids: Array[String] = []
var _started := false
var _mutex := Mutex.new()
var _first := ""
var _reported := false

func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type == Logger.ERROR_TYPE_WARNING: return
	_mutex.lock()
	if _first.is_empty(): _first = "%s:%d %s: %s %s" % [file, line, function, code, rationale]
	_mutex.unlock()

func poll(tree: SceneTree) -> bool:
	_mutex.lock()
	var first := _first
	var report := not _reported and not first.is_empty()
	if report: _reported = true
	_mutex.unlock()
	if first.is_empty(): return true
	if report: push_error("DISABLED_CATALOG_CONTRACT_FAIL: " + first)
	tree.quit(1)
	return false

func _accept(tree: SceneTree, condition: bool, label: String) -> bool:
	if not condition:
		_mutex.lock()
		if _first.is_empty(): _first = label
		_mutex.unlock()
	return poll(tree)

func begin(tree: SceneTree, required_enabled: Array) -> bool:
	var explicit := false
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--catalog-profile"): continue
		if not _accept(tree, not explicit, "Duplicate catalog profile"): return false
		explicit = true
		if argument == "--catalog-profile=formal_disabled": profile = "formal_disabled"
		elif argument == "--catalog-profile=enabled_isolated": profile = "enabled_isolated"
		else: return _accept(tree, false, "Unknown catalog profile: " + argument)
	var nodes: Array = Catalog.all()
	if not _accept(tree, nodes.size() == 40, "Expected exactly 40 catalog nodes"): return false
	_enabled_ids.clear()
	for node: Dictionary in nodes:
		if not _accept(tree, node.get("enabled") is bool and node.get("id") is String, "Invalid catalog node metadata"): return false
		if bool(node.enabled): _enabled_ids.append(str(node.id))
	_enabled_ids.sort()
	if profile == "formal_disabled":
		if not _accept(tree, _enabled_ids.is_empty(), "Formal disabled profile requires every catalog node disabled"): return false
	else:
		for identity: Variant in required_enabled:
			if not _accept(tree, identity is String and _enabled_ids.has(identity), "Explicit enabled profile is missing a required node"): return false
	_catalog_sha = FileAccess.get_sha256(CATALOG_PATH)
	if not _accept(tree, _catalog_sha.length() == 64, "Catalog raw SHA-256 unavailable"): return false
	_started = true
	return true

func ready(tree: SceneTree) -> bool:
	return _accept(tree, _started and FileAccess.get_sha256(CATALOG_PATH) == _catalog_sha, "Catalog raw source changed during this test")

func emit_disabled(tree: SceneTree, identity: String, serial: int) -> bool:
	if not ready(tree): return false
	if not _accept(tree, profile == "formal_disabled" and _enabled_ids.is_empty(), "Disabled scope cannot describe an enabled profile"): return false
	var result := {"version": 1, "test_id": identity, "serial": serial, "profile": profile,
		"scope": "DISABLED_BOUNDARY", "boundary": "PASS",
		"public_enabled_productive": {"applicability": "NOT_APPLICABLE", "execution": "NOT_RUN", "reason": "CATALOG_DISABLED"},
		"catalog_pin": {"path": CATALOG_PATH, "absolute_path": ProjectSettings.globalize_path(CATALOG_PATH),
			"sha256": _catalog_sha, "node_count": 40, "enabled_ids": _enabled_ids.duplicate()}}
	print("DISABLED_CATALOG_RESULT " + JSON.stringify(result))
	return poll(tree)
