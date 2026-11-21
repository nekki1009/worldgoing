extends "res://scripts/tests/site_tactical_ai_formal_visual_test.gd"
## Diagnostic wrapper: same formal fixture and gates; profile only early MOVE.
## This adds debugger overhead and is not another comparable FPS baseline.
var function_profile_started := false
var function_profile_finished := false

func _process(delta: float) -> bool:
	var result := super._process(delta)
	if measured_us <= 0 or finished:
		return result
	var at := float(Time.get_ticks_usec() - measured_us) / 1000000.0
	if at >= 10.0 and not function_profile_started:
		assert(EngineDebugger.is_active() and EngineDebugger.has_profiler(&"scripts"))
		function_profile_started = true
		print("MOVE_FUNCTION_PROFILE_BEGIN ", JSON.stringify({"wall_at": at, "action": report.get("action_seconds_before", 0.0), "scope": "native script profiler; formal 300-person MOVE"}))
		EngineDebugger.profiler_enable(&"scripts", true)
	if at >= 25.0 and function_profile_started and not function_profile_finished:
		function_profile_finished = true
		print("MOVE_FUNCTION_PROFILE_ACCUMULATED_BEGIN ", at)
		EngineDebugger.profiler_enable(&"scripts", false)
		print("MOVE_FUNCTION_PROFILE_ACCUMULATED_END")
	return result
