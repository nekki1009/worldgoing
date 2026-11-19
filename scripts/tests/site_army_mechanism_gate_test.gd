extends SceneTree

const Gate = preload("res://scripts/tests/fixtures/site_army_mechanism_gate.gd")


func _initialize() -> void:
	var formal := load("res://scripts/tests/site_army_scale_realtime_test.gd")
	var oracle_stream := load("res://scripts/tests/site_army_oracle_stream_test.gd")
	var generator := load("res://scripts/tests/site_army_mechanism_test.gd")
	if formal == null or oracle_stream == null or generator == null:
		push_error("Formal 5k harness, mechanism generator or exact oracle stream did not parse")
		quit(1)
		return
	var nested := Gate.validate(Gate.EVIDENCE_ROOT + "gate_selftest_missing/mechanism_result.json")
	if bool(nested.passed) or "evidence_path" not in nested.failures:
		push_error("Noncanonical mechanism evidence was admitted: " + str(nested))
		quit(1)
		return
	var outside := Gate.validate("res://output/site_army_5k_close_20260926/mechanism_result.json")
	if bool(outside.passed) or "evidence_path" not in outside.failures:
		push_error("Evidence from the wrong experiment was admitted: " + str(outside))
		quit(1)
		return
	print("SITE_ARMY_MECHANISM_GATE_REJECTION_PASS")
	quit(0)
