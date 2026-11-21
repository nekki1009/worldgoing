extends SceneTree
const Slot = preload("res://scripts/region_lab/region_save_slot.gd")
const Factions = preload("res://scripts/region_lab/region_faction_query.gd")
var failed: bool = false
var checks: int = 0

func _check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failed = true
		push_error("REGION_DEPARTURE_FIRE_ENDPOINT_FAIL: " + label)
	return value

func _valid(clock: Dictionary, game: float, label: String) -> bool:
	var result: Variant = Slot.validate_fire_clock(clock, game)
	return _check(result is Dictionary and result.get("ok", false), "valid fixture: " + label + " " + str(result))

func _reject(result: Variant, label: String) -> void:
	_check(result is Dictionary and result.get("ok") == false and result.get("code") in
		["CORRUPT_FIRE_CLOCK", "CORRUPT_FIRE_JOURNAL", "CORRUPT_FIRE_INDEX", "CORRUPT_FIRE_SETTLEMENT", "MISSING_FIRE_HISTORY"]
		and result.get("message") is String and not str(result.get("message")).is_empty(), "explicit refusal: " + label)

func _clock(exact: float, action: float, epoch: String) -> Dictionary:
	var clock: Dictionary = Slot._new_fire_clock(2012.0000000000575)
	clock["epoch"] = epoch
	clock["base_sequence"] = 1500
	clock["sequence"] = 1500
	clock["base_action_seconds"] = 47.51437945973904
	clock["action_seconds"] = 47.51437945973904
	Slot.append_completed_fire_interval(clock, {"epoch": epoch, "sequence": 1501,
		"action_begin": 47.51437945973904, "action_end": action, "game_begin": 2012.0000000000575,
		"game_end": exact, "scale": 4.0, "tactical_seconds": 0.0})
	return clock

func _initialize() -> void:
	var exact: float = PackedByteArray([0xee, 0x73, 0x52, 0xb9, 0x3e, 0x7d, 0x9f, 0x40]).decode_double(0)
	var future: float = PackedByteArray([0xef, 0x73, 0x52, 0xb9, 0x3e, 0x7d, 0x9f, 0x40]).decode_double(0)
	var action: float = PackedByteArray([0x08, 0x51, 0x5c, 0x48, 0x9b, 0xc3, 0x47, 0x40]).decode_double(0)
	var epoch: String = "fire_17f91bcab5a13f12cd4b163f47511a98"
	var owner: String = "earth_tw_tm2_121_v1:0:0"
	var clock: Dictionary = _clock(exact, action, epoch)
	if not _valid(clock, exact, "complete frozen endpoint with original append helper"): quit(1); return
	var saved: Dictionary = {"version": 1.0, "epoch": epoch, "sequence": 1501.0, "action_seconds": action, "game_seconds": future}
	var before: PackedByteArray = var_to_bytes(saved)
	var result: Variant = Slot._region_departure_fire_endpoint(saved, clock)
	if not _check(result is Dictionary and result.get("ok", false), "original endpoint returns a successful result"): quit(1); return
	_check(result["watermark"]["game_seconds"] == exact and result["watermark"]["action_seconds"] == action, "same journal endpoint survives exact writer representation")
	_check(before == var_to_bytes(saved), "original saved watermark is not mutated")
	clock.index[owner] = {"coordinate": [0, 0], "active": true, "fire_active": false,
		"sequence": 1501, "game_seconds": result["watermark"]["game_seconds"], "action_seconds": action}
	if not _valid(clock, exact, "complete source index row"): quit(1); return
	var summary: Dictionary = {"owner": owner, "at": future, "source_clock": {"fire_epoch": epoch, "fire_sequence": 1501,
		"game_seconds": future, "action_seconds": action}}
	var slot: RegionSaveSlot = Slot.new()
	var receipt: Variant = slot._faction_source_game_seconds(summary, {"fire_clock": clock})
	_check(receipt == exact and Factions._time(receipt, exact), "unchanged faction matcher uses original indexed endpoint")
	var changed: Dictionary = saved.duplicate(true)
	changed["epoch"] = "different-epoch"
	_reject(Slot._region_departure_fire_endpoint(changed, clock), "different epoch")
	changed = saved.duplicate(true)
	changed["sequence"] = 1502
	_reject(Slot._region_departure_fire_endpoint(changed, clock), "future sequence")
	changed = saved.duplicate(true)
	changed["game_seconds"] = exact + 0.000000001
	result = Slot._region_departure_fire_endpoint(changed, clock)
	if not _check(result is Dictionary and result.get("ok", false), "nonmatching future returns its real point"): quit(1); return
	_check(result["watermark"]["game_seconds"] == changed.game_seconds and not Factions._time(result["watermark"]["game_seconds"], exact), "nonmatching future is not clamped")
	var future_clock: Dictionary = clock.duplicate(true)
	future_clock.journal[0].game_end = future
	if not _valid(future_clock, future, "genuine future journal"): quit(1); return
	result = Slot._region_departure_fire_endpoint(saved, future_clock)
	if not _check(result is Dictionary and result.get("ok", false), "future journal result"): quit(1); return
	_check(result["watermark"]["game_seconds"] == future and not Factions._time(result["watermark"]["game_seconds"], exact), "genuine future remains future")
	var base: Dictionary = Slot._new_fire_clock(exact)
	base["epoch"] = epoch
	var base_saved: Dictionary = {"version": 1, "epoch": epoch, "sequence": 0, "game_seconds": future, "action_seconds": 0.0}
	if not _valid(base, exact, "original base"): quit(1); return
	result = Slot._region_departure_fire_endpoint(base_saved, base)
	if not _check(result is Dictionary and result.get("ok", false), "base endpoint result"): quit(1); return
	_check(result["watermark"]["game_seconds"] == exact, "base endpoint remains exact")
	var legacy: Dictionary = base.duplicate(true)
	legacy.erase("base_sequence"); legacy.erase("base_action_seconds")
	if not _valid(legacy, exact, "supported legacy base schema"): quit(1); return
	_check(Slot.validate_fire_settlement({"fire_settlement": base_saved}, legacy).get("ok", false), "legacy settlement remains admitted")
	# append_completed_fire_interval compresses only the original live step widths
	# (_fire_row_width: EXCHANGE_ACTION_STEP or ACTION_STEP, bit-exact chaining).
	# Three real exchange steps at scale 1 pay 2 game seconds each; sequence 1501
	# is the second of three, so the saved watermark is a genuine interior point.
	var width: float = TerrainLab.EXCHANGE_ACTION_STEP
	var interior: Dictionary = Slot._new_fire_clock(exact - 4.0)
	interior["epoch"] = epoch
	interior["base_sequence"] = 1499
	interior["sequence"] = 1499
	interior["base_action_seconds"] = action - 2.0 * width
	interior["action_seconds"] = action - 2.0 * width
	var game: float = exact - 4.0
	for step: int in range(3):
		var interval: Dictionary = Slot.preview_fire_interval(interior, game, width, 1.0, 0.0)
		if not _check(interval.get("ok", false), "valid original compressed step " + str(step)): quit(1); return
		Slot.append_completed_fire_interval(interior, interval)
		game = float(interval.game_end)
	if not _valid(interior, game, "legal uniform compressed interior"): quit(1); return
	if not _check(interior.journal.size() == 1 and int(interior.journal[0].steps) == 3 and int(interior.journal[0].first_sequence) == 1500
		and int(interior.journal[0].last_sequence) == 1502 and int(interior.sequence) == 1502, "three complete original steps really compressed " + str(interior.journal)): quit(1); return
	if not _check(Slot.validate_fire_settlement({"fire_settlement": saved}, interior).get("ok", false), "saved watermark is admitted as the original interior point of the compressed row"): quit(1); return
	result = Slot._region_departure_fire_endpoint(saved, interior)
	if not _check(result is Dictionary and result.get("ok", false), "valid interior result"): quit(1); return
	_check(result["watermark"]["game_seconds"] == future, "interior is preserved without binary interpolation")
	# Malformed controls are separate from every validated positive fixture.
	for field: String in Slot.FIRE_CLOCK_FIELDS:
		var broken: Dictionary = clock.duplicate(true)
		broken.erase(field)
		_reject(Slot.validate_fire_settlement({"fire_settlement": saved}, broken), "missing clock " + field)
	for field: String in Slot.FIRE_CLOCK_BASE_FIELDS:
		var broken: Dictionary = clock.duplicate(true)
		broken.erase(field)
		_reject(Slot.validate_fire_settlement({"fire_settlement": saved}, broken), "unpaired base " + field)
	for field: String in Slot.FIRE_CLOCK_SEGMENT_FIELDS:
		var broken: Dictionary = clock.duplicate(true)
		broken.journal[0].erase(field)
		_reject(Slot.validate_fire_settlement({"fire_settlement": saved}, broken), "missing journal " + field)
	for bad: Variant in [null, 7, [], "bad-row"]:
		var broken: Dictionary = clock.duplicate(true)
		broken["journal"] = [bad]
		_reject(Slot.validate_fire_settlement({"fire_settlement": saved}, broken), "non-dictionary journal row")
	for pair: Array in [["steps", 0], ["steps", 2], ["scale", 3.0], ["tactical_seconds", 1.0], ["action_begin", "bad"]]:
		var broken: Dictionary = clock.duplicate(true)
		broken.journal[0][pair[0]] = pair[1]
		_reject(Slot.validate_fire_settlement({"fire_settlement": saved}, broken), "invalid journal " + str(pair[0]))
	for pair: Array in [["version", 2], ["base_sequence", "bad"], ["base_action_seconds", "bad"], ["journal", null], ["index", []]]:
		var broken: Dictionary = clock.duplicate(true)
		broken[pair[0]] = pair[1]
		_reject(Slot.validate_fire_settlement({"fire_settlement": saved}, broken), "invalid clock " + str(pair[0]))
	var legacy_index: Dictionary = clock.duplicate(true)
	legacy_index.index[owner].erase("fire_active")
	if not _valid(legacy_index, exact, "supported five-field index row"): quit(1); return
	for field: String in ["coordinate", "active", "sequence", "action_seconds", "game_seconds"]:
		var broken: Dictionary = clock.duplicate(true)
		broken.index[owner].erase(field)
		_reject(Slot.validate_fire_settlement({"fire_settlement": saved}, broken), "missing index " + field)
	for bad: Variant in [null, 7, [], {}]:
		var broken: Dictionary = clock.duplicate(true)
		broken.index[owner] = bad
		_reject(Slot.validate_fire_settlement({"fire_settlement": saved}, broken), "malformed index row")
	for field: String in Slot.FIRE_SETTLEMENT_FIELDS:
		var broken: Dictionary = saved.duplicate(true)
		broken.erase(field)
		_reject(Slot.validate_fire_settlement({"fire_settlement": broken}, clock), "missing settlement " + field)
	changed = saved.duplicate(true)
	changed["version"] = 2
	_reject(Slot.validate_fire_settlement({"fire_settlement": changed}, clock), "invalid settlement version")
	_reject(Slot.validate_fire_settlement({"fire_settlement": []}, clock), "non-dictionary settlement")
	if failed: quit(1); return
	print("REGION_DEPARTURE_FIRE_ENDPOINT_PASS checks=", checks)
	quit(0)
