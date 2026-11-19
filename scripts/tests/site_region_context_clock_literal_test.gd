extends SceneTree
## Source candidate only. Exercises the actual reader against immutable literals;
## no world, paid interval, producer, snapshot predicate or deadline is changed.
const Store = preload("res://scripts/terrain_lab/site_store.gd")
const Factions = preload("res://scripts/region_lab/region_faction_query.gd")
const GAME := "2015.3112538226374"
const HIGH := "2015.3112538226376"
const ACTION := "47.528176350666456"
const GAME_BITS := "03000100ee7352b93e7d9f40"
const HIGH_BITS := "03000100ef7352b93e7d9f40"
const ACTION_BITS := "0300010008515c489bc34740"
var failed := false
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		failed = true
		push_error("REGION_CONTEXT_LITERAL_FAIL: " + label)
	return condition

func _fixture(game: String = GAME) -> String:
	return '{"state":{"region_snapshot":{"context":{"game_seconds":%s,"action_seconds":%s}}}}' % [game, ACTION]

func _exercise(label: String, text: String, expected_game: String) -> Dictionary:
	var parse_began: int = Time.get_ticks_usec()
	var parsed: Variant = JSON.parse_string(text)
	var parse_usec: int = Time.get_ticks_usec() - parse_began
	if not _check(parsed is Dictionary and parsed.get("state") is Dictionary, label + ": genuine JSON input"): return {}
	var unrelated: PackedByteArray = var_to_bytes([parsed["state"].get("noise"), parsed["state"].get("unrelated"), parsed["state"]["region_snapshot"]["context"].get("events")])
	var decode_began: int = Time.get_ticks_usec()
	Store._read_exact_region_context_clocks(text, parsed["state"])
	var decode_usec: int = Time.get_ticks_usec() - decode_began
	var context: Dictionary = parsed["state"]["region_snapshot"]["context"]
	_check(var_to_bytes(context["game_seconds"]).hex_encode() == expected_game, label + ": exact original game literal")
	_check(var_to_bytes(context["action_seconds"]).hex_encode() == ACTION_BITS, label + ": exact original action literal")
	_check(unrelated == var_to_bytes([parsed["state"].get("noise"), parsed["state"].get("unrelated"), context.get("events")]), label + ": unrelated body/nested event values unchanged")
	return {"native_parse_usec": parse_usec, "context_decode_usec": decode_usec}

func _run() -> void:
	_exercise("frozen HAIKU35 ee73 literal", _fixture(), GAME_BITS)
	_exercise("genuine ef73 stays ef73", _fixture(HIGH), HIGH_BITS)
	var exact_now: float = PackedByteArray([238, 115, 82, 185, 62, 125, 159, 64]).decode_double(0)
	var genuine_future: Dictionary = JSON.parse_string(_fixture(HIGH))
	Store._read_exact_region_context_clocks(_fixture(HIGH), genuine_future["state"])
	_check(not Factions._time(genuine_future["state"]["region_snapshot"]["context"]["game_seconds"], exact_now), "genuine next-ULP future time still fails original strict faction time guard")
	var genuine_now: Dictionary = JSON.parse_string(_fixture())
	Store._read_exact_region_context_clocks(_fixture(), genuine_now["state"])
	_check(Factions._time(genuine_now["state"]["region_snapshot"]["context"]["game_seconds"], exact_now), "exact stored original endpoint passes the unchanged time guard")
	_exercise("duplicate game last high", '{"state":{"region_snapshot":{"context":{"game_seconds":%s,"game_seconds":%s,"action_seconds":%s}}}}' % [GAME, HIGH, ACTION], HIGH_BITS)
	_exercise("duplicate game last low", '{"state":{"region_snapshot":{"context":{"game_seconds":%s,"game_seconds":%s,"action_seconds":%s}}}}' % [HIGH, GAME, ACTION], GAME_BITS)
	_exercise("duplicate state last wins", '{"state":{"region_snapshot":{"context":{"game_seconds":%s,"action_seconds":%s}}},"state":{"region_snapshot":{"context":{"game_seconds":%s,"action_seconds":%s}}}}' % [HIGH, ACTION, GAME, ACTION], GAME_BITS)
	_exercise("duplicate snapshot last wins", '{"state":{"region_snapshot":{"context":{"game_seconds":%s,"action_seconds":%s}},"region_snapshot":{"context":{"game_seconds":%s,"action_seconds":%s}}}}' % [HIGH, ACTION, GAME, ACTION], GAME_BITS)
	_exercise("duplicate context last wins", '{"state":{"region_snapshot":{"context":{"game_seconds":%s,"action_seconds":%s},"context":{"game_seconds":%s,"action_seconds":%s}}}}' % [HIGH, ACTION, GAME, ACTION], GAME_BITS)
	var noise: String = JSON.stringify('braces } ] { [ and " quotes, \\ slashes; fake "game_seconds":999.0')
	var escaped: String = '{"st\\u0061te":{"noise":%s,"region_snapshot":{"context":{"game_\\u0073econds":%s,"action_seconds":%s,"events":[{"game_seconds":999.0,"nested":[{},[]]}]}}}}' % [noise, GAME, ACTION]
	_exercise("escaped keys / strings / nested decoys", escaped, GAME_BITS)
	var legacy_text: String = _fixture("0.100000000000000000000000000000001")
	var legacy: Dictionary = JSON.parse_string(legacy_text)
	var original_legacy: PackedByteArray = var_to_bytes(legacy["state"]["region_snapshot"]["context"]["game_seconds"])
	Store._read_exact_region_context_clocks(legacy_text, legacy["state"])
	_check(original_legacy == var_to_bytes(legacy["state"]["region_snapshot"]["context"]["game_seconds"]), "legacy noncanonical literal keeps original reader value")
	_exercise("legacy exact finite literal", _fixture("1.25"), var_to_bytes(1.25).hex_encode())
	var mismatch_text: String = _fixture()
	var mismatch: Dictionary = JSON.parse_string(mismatch_text)
	mismatch["state"]["region_snapshot"]["context"]["game_seconds"] = 7.0
	Store._read_exact_region_context_clocks(mismatch_text, mismatch["state"])
	_check(mismatch["state"]["region_snapshot"]["context"]["game_seconds"] == 7.0, "raw locator cannot replace a different existing parsed authority")
	for literal: String in ["-1.0", "1e13"]:
		var invalid_text: String = _fixture(literal)
		var invalid: Dictionary = JSON.parse_string(invalid_text)
		var before: PackedByteArray = var_to_bytes(invalid["state"]["region_snapshot"]["context"]["game_seconds"])
		Store._read_exact_region_context_clocks(invalid_text, invalid["state"])
		_check(before == var_to_bytes(invalid["state"]["region_snapshot"]["context"]["game_seconds"]), "out-of-domain value stays for the unchanged strict validator: " + literal)
	# Optional near-limit string case; neither performance nor its engine result
	# is claimed until run. Structural case always exercises many unrelated nodes.
	var padding_bytes: int = 24 * 1024 * 1024 if OS.get_cmdline_user_args().has("--cc184-large-json") else 2 * 1024 * 1024
	var padding: String = JSON.stringify("x".repeat(padding_bytes))
	var structural: Array = []
	for index: int in range(10000): structural.append({"n": index, "text": "{\"x\":[]}", "nested": [true, null, {}]})
	var large: String = '{"padding":%s,"state":{"unrelated":%s,"region_snapshot":{"context":{"game_seconds":%s,"action_seconds":%s}}}}' % [padding, JSON.stringify(structural), GAME, ACTION]
	var began: int = Time.get_ticks_usec()
	var metrics: Dictionary = _exercise("large unrelated payload", large, GAME_BITS)
	print("REGION_CONTEXT_LITERAL_TIMING bytes=", large.to_utf8_buffer().size(), " total_usec=", Time.get_ticks_usec() - began, " metrics=", metrics)
	print("SITE_REGION_CONTEXT_CLOCK_LITERAL_", "FAIL" if failed else "PASS", " checks=", checks)
	quit(1 if failed else 0)
