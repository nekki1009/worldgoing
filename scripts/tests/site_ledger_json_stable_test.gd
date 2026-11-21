extends SceneTree
## Saved batch-ledger seconds survive the Store's own JSON round trip exactly.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
var checks := 0
var failures := 0

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("SITE_LEDGER_JSON_STABLE_FAIL: " + message)

func _initialize() -> void:
	_run.call_deferred()

# Same as SiteStore: full-precision stringify, then JSON.parse.
func _store_round_trip(value: Variant) -> Variant:
	var parser := JSON.new()
	if parser.parse(JSON.stringify({"value": value}, "", true, true)) != OK: return null
	return parser.data.value

func _same_bits(a: Variant, b: Variant) -> bool:
	return var_to_bytes(a) == var_to_bytes(b)

func _run() -> void:
	var raw_unstable := 0
	var samples := 0
	var total := 0.0
	var stable_total := 0.0
	for step: int in 4000:
		# Realistic step factors: 1/120 s action steps, 30/60 s intervals, grade and water ratios.
		var minutes := (1.0 / 120.0 + float(step % 7) * 0.5) / 60.0
		var factor: float = [1.0, 1.25, 1.5][step % 3] * [1.0, 0.75, 0.3333333333333333, 0.9][step % 4]
		total += minutes * 60.0 * factor
		stable_total = Runtime.json_stable_seconds(stable_total + minutes * 60.0 * factor)
		samples += 1
		if not _same_bits(float(_store_round_trip(total)), total): raw_unstable += 1
		var once := Runtime.json_stable_seconds(stable_total)
		if not _same_bits(once, stable_total):
			_check(false, "Stabilizing is idempotent at sample %d" % step)
			break
		if not _same_bits(float(_store_round_trip(stable_total)), stable_total):
			_check(false, "A stabilized second survives the Store round trip bit-exactly at sample %d" % step)
			break
	_check(true, "Stabilized ledger seconds are idempotent and Store-exact over %d samples" % samples)
	print("SITE_LEDGER_JSON_STABLE_EVIDENCE raw_unstable=%d of %d unstabilized running sums" % [raw_unstable, samples])
	_check(absf(stable_total - total) < 0.001, "Stabilizing never drifts the accumulated work materially (%.9f vs %.9f)" % [stable_total, total])
	# The real recorder: odd steps at grade 3 with a water shortage.
	var feature := {"kind": "smithy", "stage": "complete", "technology_order": {"nation_id": "n1", "order_id": "public_1"},
		"tech_batch": {"operator_id": 4, "work_seconds": 0.0}}
	for step: int in 97:
		var minutes := (1.0 / 120.0) * float(1 + step % 5) + 0.0123
		Runtime.technology_record_work(feature, minutes, 4, Runtime.feature_production_minutes(minutes, 0.7333333333333333, 1.5))
	var ledger: Dictionary = feature.tech_batch
	_check(_same_bits(float(_store_round_trip(ledger.work_seconds)), float(ledger.work_seconds)), "Recorded work_seconds survives a cold save/load bit-exactly")
	_check(_same_bits(float(_store_round_trip(ledger.effective_seconds)), float(ledger.effective_seconds)), "Recorded effective_seconds survives a cold save/load bit-exactly")
	var cold: Variant = _store_round_trip(ledger)
	_check(cold is Dictionary and _same_bits(float(cold.work_seconds), float(ledger.work_seconds)) and _same_bits(float(cold.effective_seconds), float(ledger.effective_seconds)), "The whole ledger round-trips its seconds exactly")
	print("SITE_LEDGER_JSON_STABLE_%s: checks=%d failures=%d" % ["PASS" if failures == 0 else "FAIL", checks, failures])
	quit(0 if failures == 0 else 1)
