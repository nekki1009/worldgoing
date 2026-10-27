extends SceneTree
## The siege snapshot's persisted number domain is idempotent: a body value and
## its Store JSON read-back give the same snapshot field and the same hash.
## Witnesses are the OPUS78 bit patterns the Store's JSON reader moves by one ulp.
const RegionBattle = preload("res://scripts/region_lab/region_gameplay_battle.gd")
var checks := 0
var failures := 0

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("REGION_SIEGE_PERSISTED_NUMBER_FAIL: " + message)

func _initialize() -> void:
	_run.call_deferred()

func _from_bits(bits: int) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_s64(0, bits)
	return bytes.decode_double(0)

func _bits(value: Variant) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, float(value))
	return bytes.hex_encode()

func _same(a: Variant, b: Variant) -> bool:
	return var_to_bytes(a) == var_to_bytes(b)

## The Store's own save and load of one Site number: full-precision writer, JSON reader.
func _store_round_trip(value: float) -> float:
	var parser := JSON.new()
	if parser.parse(JSON.stringify({"value": value}, "", true, true)) != OK: return NAN
	return float(parser.data.value)

func _run() -> void:
	var witnesses: Array[float] = [_from_bits(0x40cc1f7851eb8526), _from_bits(0x40c6d287ae147aa3)]
	var evidence: Array = []
	for value: float in witnesses:
		var saved := _store_round_trip(value)
		var persisted: Variant = RegionBattle._siege_persisted(value)
		var persisted_saved: Variant = RegionBattle._siege_persisted(saved)
		var twice := _store_round_trip(saved)
		evidence.append({"value": _bits(value), "store_read_back": _bits(saved), "persisted": _bits(persisted), "persisted_of_read_back": _bits(persisted_saved), "read_back_twice": _bits(twice)})
		_check(_same(twice, saved), "the Store read-back of %s is a fixed point (reader(writer(reader(writer(x)))) == reader(writer(x)))" % _bits(value))
		_check(_same(persisted, saved), "the persisted form of %s is its Store read-back" % _bits(value))
		_check(_same(persisted, persisted_saved), "the in-memory value %s and its restored value give the same snapshot number" % _bits(value))
		var body := {"person_id": 10, "hp": 96.0, "ko": value, "cell": [98, 50]}
		var restored := {"person_id": 10, "hp": 96.0, "ko": saved, "cell": [98, 50]}
		_check(RegionBattle._siege_persisted_hash(body) == RegionBattle._siege_persisted_hash(restored), "the in-memory and restored body hash identically in the persisted domain for %s" % _bits(value))
		if not _same(saved, value): _check(RegionBattle._siege_hash(body) != RegionBattle._siege_hash(restored), "the ordinary digest still distinguishes one ulp for %s" % _bits(value))
	# A sweep of decaying knockouts and clocks: the persisted form is idempotent and
	# equal for a value and its Store read-back.
	var misses := 0
	var moved := 0
	var ko := 14400.0
	var clock := 11668.0
	for step: int in 3000:
		ko = maxf(0.0, ko - (1.0 / 30.0 if step % 5 != 0 else 0.0216117216117482))
		clock += 1.0 / 30.0 if step % 3 != 0 else 0.0133333333333496
		for value: float in [ko, clock, clock / 60.0]:
			var saved := _store_round_trip(value)
			if not _same(saved, value): moved += 1
			if not _same(RegionBattle._siege_persisted(value), RegionBattle._siege_persisted(saved)) or not _same(_store_round_trip(saved), saved): misses += 1
	_check(misses == 0, "persisted form agrees for every swept value and its Store read-back (%d misses)" % misses)
	# Integral values and non-number fields are untouched.
	_check(_same(RegionBattle._siege_persisted({"a": [1, 2.0, "x", 100.0]}), {"a": [1, 2.0, "x", 100.0]}), "integral numbers, ints and strings keep their values")
	print("REGION_SIEGE_PERSISTED_NUMBER_", "PASS" if failures == 0 else "FAILED", " ", JSON.stringify({"checks": checks, "failures": failures, "witnesses": evidence, "store_reader_moved_in_sweep": moved, "sweep_values": 9000}))
	quit(1 if failures > 0 else 0)
