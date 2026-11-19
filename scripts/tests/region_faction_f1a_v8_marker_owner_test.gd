extends "res://scripts/tests/region_faction_f1a_v2_test.gd"
## Original v2 complete writer/recovery/phase tests run first without warmup.
var marker_fixture: ObservedSlot
func _slot() -> ObservedSlot:
	var original: ObservedSlot = super._slot()
	marker_fixture = original
	return original
func _run() -> void:
	super._run()
	if failed: return
	# A fresh original reader and genuine writer exercise the cold-completion
	# repair and then the unchanged merged fast algorithm, with no warmup of v2:128.
	var peer: ObservedSlot = ObservedSlot.new()
	peer.folder = marker_fixture.folder; peer.source = marker_fixture.source; peer.pin = marker_fixture.pin.duplicate(true)
	if not check(peer._recover_control().ok, "V8 fresh original reader validates the actual latest record"): return
	var published: Dictionary = peer._publish({}, peer.control, "", peer.region_travel_journey())
	if not check(published.ok, "V8 original writer creates a genuine next marker"): return
	marker_fixture = peer
	var original: Dictionary = marker_fixture._marker
	var original_control: Dictionary = marker_fixture.control
	var typed_before: PackedByteArray = var_to_bytes([original_control, original])
	if not check(marker_fixture._recover_control().ok and is_same(marker_fixture._marker, original) and is_same(marker_fixture.control, original_control)
		and typed_before == var_to_bytes([marker_fixture.control, marker_fixture._marker]), "V8 first validated recovery retains exact typed original owners"): return
	var cached_snapshot: Dictionary = marker_fixture._recover_known_commit[marker_fixture.folder].recorded
	if not check(not is_same(cached_snapshot, original), "V8 validated memo never aliases mutable RAM marker"): return
	for repeat: int in 8:
		if not check(marker_fixture._recover_control().ok and is_same(marker_fixture._marker, original)
			and is_same(marker_fixture._recover_known_commit[marker_fixture.folder].recorded, cached_snapshot), "V8 repeated warm recovery keeps original owners and the same independent memo"): return
	var before: PackedByteArray = var_to_bytes([marker_fixture.control, original])
	var path: String = marker_fixture.folder.path_join("commits/%020d.json" % int(original.generation))
	var document: Dictionary = marker_fixture._read_document(path)
	if not check(document.ok, "V8 comparison reads an actual original immutable marker"): return
	var recorded: Dictionary = document.payload
	var clock: Dictionary = marker_fixture._faction_decode_clock(str(recorded.control.value))
	if not check(clock.ok, "V8 original no-object typed clock decoder retains validation"): return
	recorded.control = clock.clock
	if not check(marker_fixture._faction_marker_same_wire(original, recorded), "V8 validated JSON outer numbers retain the exact original logical marker"): return
	var invalid: Dictionary = recorded.duplicate(true)
	invalid.control.logical_game_seconds = int(invalid.control.logical_game_seconds) if typeof(invalid.control.logical_game_seconds) == TYPE_FLOAT else float(invalid.control.logical_game_seconds)
	if not check(not marker_fixture._faction_marker_same_wire(original, invalid), "V8 int/float mutation inside typed control is never normalized"): return
	invalid = recorded.duplicate(true); invalid.transfer_token = "uncommitted-v8-poison"
	if not check(not marker_fixture._faction_marker_same_wire(original, invalid), "V8 contaminated marker never acquires validated ownership"): return
	invalid = recorded.duplicate(true); invalid.transfer_token = StringName(str(invalid.transfer_token))
	if not check(not marker_fixture._faction_marker_same_wire(original, invalid), "V8 StringName is not admitted as an original JSON String"): return
	invalid = recorded.duplicate(true); invalid["unknown"] = true
	if not check(not marker_fixture._faction_marker_same_wire(original, invalid), "V8 unknown outer fields cannot be normalized away"): return
	var large_left: Dictionary = original.duplicate(true)
	var large_right: Dictionary = recorded.duplicate(true)
	large_left.generation = 9007199254740993; large_right.generation = 9007199254740992.0
	if not check(not marker_fixture._faction_marker_same_wire(large_left, large_right), "V8 lossy JSON integer coercion never compares equal"): return
	if not check(before == var_to_bytes([marker_fixture.control, marker_fixture._marker]), "V8 detached comparisons preserve typed owner bytes"): return
	print("REGION_FACTION_F1A_V8_MARKER_OWNER_PASS ", checks, " original v2 plus detached representation contracts; performance excluded")
	quit(0)
