extends "res://scripts/tests/crowd_sustain_query_parity_test.gd"
## Reuses every existing fixture/oracle, plus direct same-input production parity.
const ControllerSource = preload("res://scripts/terrain_lab/site_controller.gd")
const SubphaseController = preload("res://scripts/tests/helpers/crowd_supply_subphase_controller.gd")
const Counters = preload("res://scripts/tests/helpers/crowd_event_profile_counters.gd")
var profiler := Counters.new()
var installed_controller := false
var direct_comparisons := 0

func _initialize() -> void:
	var pin: Dictionary = SubphaseController.source_pin()
	if not _check(bool(pin.ok), "timer-stripped test transcription exactly matches the pinned production function", pin):
		quit(2)
		return
	node_added.connect(_install_fresh_controller)
	super._initialize()

func _install_fresh_controller(node: Node) -> void:
	if installed_controller or node.get_parent() != lab or node.get_script() != ControllerSource: return
	assert(node.lab == null and node._pending_deaths.is_empty() and node.captivity_supply._prepared.is_empty())
	var identity := node.get_instance_id()
	node.set_script(SubphaseController)
	node.profiler = profiler
	installed_controller = identity == node.get_instance_id() and node.lab == null

func _sources() -> Dictionary:
	var hashes: Dictionary = super._sources()
	for path: String in ["res://scripts/tests/crowd_supply_subphase_parity_test.gd", "res://scripts/tests/helpers/crowd_supply_subphase_controller.gd",
		"res://scripts/tests/helpers/crowd_host_profile_controller.gd", "res://scripts/tests/helpers/crowd_event_profile_counters.gd"]:
		hashes[path] = FileAccess.get_sha256(path)
	return hashes

func _advance(seconds: float, legacy: bool = false) -> Dictionary:
	if not _check(installed_controller and lab.site_controller.get_script() == SubphaseController,
		"same original controller executes instrumented and original supply functions"):
		return {"bulk_queries": -1, "reads": {}, "pre_damage_reads": {}}
	var before := _snapshot()
	var callback_before := {"mutated": callback_mutated, "failed": callback_failed}
	profiler.enabled = true
	lab.site_controller.use_original_sustain = false
	var candidate_trace: Dictionary = super._advance(seconds, legacy)
	var candidate := _snapshot()
	var callback_after := {"mutated": callback_mutated, "failed": callback_failed}
	if not _restore(before): return candidate_trace
	callback_mutated = bool(callback_before.mutated)
	callback_failed = bool(callback_before.failed)
	lab.site_controller.use_original_sustain = true
	var original_trace: Dictionary = super._advance(seconds, legacy)
	lab.site_controller.use_original_sustain = false
	profiler.enabled = false
	direct_comparisons += 1
	_check(candidate == _snapshot() and candidate_trace == original_trace
		and callback_after == {"mutated": callback_mutated, "failed": callback_failed},
		"source-pinned phases match the actual production function on identical input " + str(direct_comparisons),
		{"seconds": seconds, "legacy_query_mode": legacy, "snapshot_equal": candidate == _snapshot(),
			"query_trace_equal": candidate_trace == original_trace, "callback_equal": callback_after == {"mutated": callback_mutated, "failed": callback_failed}})
	return candidate_trace

func _finish() -> void:
	if finished: return
	_check(direct_comparisons > 0 and profiler.stack.is_empty(), "direct production comparisons ran and every phase timer closed", direct_comparisons)
	var pin: Dictionary = SubphaseController.source_pin()
	_check(bool(pin.ok), "pinned production function still matches after all existing parity fixtures", pin)
	super._finish()
