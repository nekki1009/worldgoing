extends SceneTree
# Original Slot clock-journal and active-step checks. This is not cold physical
# replay, atomic-save recovery or full P5 acceptance.
var checks := 0
var failed := false
const H := 1.0 / 30.0

func _check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("FIRE_CLOCK_JOURNAL_FAIL: " + label)

func _clock() -> Dictionary:
	return {"version": 1, "epoch": "test-original-slot-epoch", "action_seconds": 0.0,
		"sequence": 0, "base_sequence": 0, "base_action_seconds": 0.0,
		"base_game_seconds": 120.0, "journal": [], "index": {}}

func _initialize() -> void:
	var clock := _clock()
	var game := 120.0
	for scale: float in [1.0, 2.0, 0.5, 4.0]:
		for slice in range(30):
			var interval := RegionSaveSlot.preview_fire_interval(clock, game, H, scale, H)
			_check(interval.ok, "Original interval accepts current endpoint scale=" + str(scale) + " slice=" + str(slice) + " result=" + str(interval) + " action=" + str(clock.action_seconds))
			if not interval.ok: quit(1); return
			game = float(interval.game_end) # Pure publisher result fixture, not simulation.
			RegionSaveSlot.append_completed_fire_interval(clock, interval)
	_check(absf(float(clock.action_seconds) - 4.0) < 0.000000001 and absf(game - 127.5) < 0.000000001,
		"Four action seconds retain historical scales and total7.5 game seconds")
	_check(clock.journal.size() == 4 and RegionSaveSlot.validate_fire_clock(clock, game).ok,
		"Uniform mapping compresses without losing original step boundaries")
	var state := {"fire_settlement": {"version": 1, "epoch": clock.epoch, "sequence": 60,
		"action_seconds": 2.0, "game_seconds": 123.0}}
	_check(RegionSaveSlot.validate_fire_settlement(state, clock).ok, "A saved watermark lies on the historic multiplier boundary")
	var replay := RegionSaveSlot.fire_replay_segments(state, clock, game)
	_check(replay.ok and replay.segments.size() == 2 and int(replay.from_sequence) == 60 and int(replay.to_sequence) == 120,
		"Cold replay keeps only multiplier segments after the saved Site watermark")
	if replay.ok and replay.segments.size() == 2:
		var replay_first: Dictionary = replay.segments[0]
		var replay_last: Dictionary = replay.segments[1]
		_check(int(replay_first.first_sequence) == 61 and int(replay_first.last_sequence) == 90 and int(replay_first.steps) == 30
			and float(replay_first.scale) == 0.5 and absf(float(replay_first.action_begin) - 2.0) < 0.000000001
			and absf(float(replay_first.game_begin) - 123.0) < 0.000000001,
			"First cold segment begins exactly at the saved action/game watermark")
		_check(int(replay_last.first_sequence) == 91 and int(replay_last.last_sequence) == 120 and int(replay_last.steps) == 30
			and float(replay_last.scale) == 4.0 and absf(float(replay_last.action_end) - 4.0) < 0.000000001
			and absf(float(replay_last.game_end) - 127.5) < 0.000000001,
			"Last cold segment preserves its original multiplier and endpoint")
	var partial := {"fire_settlement": {"version": 1, "epoch": clock.epoch, "sequence": 45,
		"action_seconds": 1.5, "game_seconds": 122.0}}
	var partial_replay := RegionSaveSlot.fire_replay_segments(partial, clock, game)
	_check(partial_replay.ok and partial_replay.segments.size() == 3
		and int(partial_replay.segments[0].first_sequence) == 46 and int(partial_replay.segments[0].steps) == 15
		and absf(float(partial_replay.segments[0].action_begin) - 1.5) < 0.000000001
		and absf(float(partial_replay.segments[0].game_begin) - 122.0) < 0.000000001,
		"Partial historical segment clips at the exact saved Site boundary")
	_check(partial_replay.ok and int(partial_replay.segments.back().last_sequence) == 120
		and absf(float(partial_replay.segments.back().game_end) - game) < 0.000000001,
		"Partial replay remains continuous through every later scale change")
	var bad_watermark := {"fire_settlement": {"version": 1, "epoch": clock.epoch, "sequence": 60,
		"action_seconds": 1.5, "game_seconds": 123.0}}
	_check(not RegionSaveSlot.fire_replay_segments(bad_watermark, clock, game).ok,
		"A settlement that does not lie on the original interval is rejected before replay")
	state.fire_settlement.game_seconds = 122.0
	_check(not RegionSaveSlot.validate_fire_settlement(state, clock).ok, "Reconstructing debt with today's multiplier is rejected")
	var legacy_clock := _clock()
	legacy_clock.erase("base_sequence")
	legacy_clock.erase("base_action_seconds")
	_check(RegionSaveSlot.validate_fire_clock(legacy_clock, 120.0).ok,
		"Untrimmed version-one save clocks remain readable")
	var unindexed_clock := _clock()
	var unindexed_interval: Dictionary = RegionSaveSlot.preview_fire_interval(unindexed_clock, 120.0, H, 1.0, H)
	RegionSaveSlot.append_completed_fire_interval(unindexed_clock, unindexed_interval)
	_check(RegionSaveSlot.prune_fire_clock_prefix(unindexed_clock) == 0
		and int(unindexed_clock.base_sequence) == 0 and unindexed_clock.journal.size() == 1,
		"Prefix history is retained when no saved Site index can prove it is settled")
	var corrupt: Dictionary = clock.duplicate(true)
	corrupt.journal[1].first_sequence += 1
	_check(not RegionSaveSlot.validate_fire_clock(corrupt, game).ok, "A missing original completed interval is rejected")
	corrupt = clock.duplicate(true)
	corrupt.journal[1].scale = 4.0
	_check(not RegionSaveSlot.validate_fire_clock(corrupt, game).ok, "History cannot be silently retimed")
	clock = _clock()
	game = 120.0
	var grace := 0.25
	for slice in range(30):
		var tactical := minf(H, grace)
		var interval := RegionSaveSlot.preview_fire_interval(clock, game, H, 1.0, tactical)
		_check(interval.ok, "Original combat-to-peace boundary retains both mappings")
		if not interval.ok: quit(1); return
		game = float(interval.game_end)
		RegionSaveSlot.append_completed_fire_interval(clock, interval)
		grace = maxf(0.0, grace - H)
	_check(absf(game - 165.25) < 0.000000001 and RegionSaveSlot.validate_fire_clock(clock, game).ok,
		"One original action second spanning .25 tactical+.75peace is45.25game")
	var original := var_to_bytes(clock)
	var last: Dictionary = clock.journal.back()
	RegionSaveSlot.record_completed_fire_replay(state, {"epoch": clock.epoch, "sequence": clock.sequence,
		"action_end": clock.action_seconds, "game_end": last.game_end})
	_check(var_to_bytes(clock) == original and RegionSaveSlot.validate_fire_settlement(state, clock).ok,
		"Recording a completed cold replay stamps only its Site and cannot republish world time")
	var active_slot := RegionSaveSlot.new()
	active_slot.control = {"logical_game_seconds": 50.0, "active_site_id": "fire-clock-test",
		"fire_clock": {"version": 1, "epoch": "active-step-test", "action_seconds": 0.0, "sequence": 0,
			"base_game_seconds": 50.0, "journal": [], "index": {}}}
	var active_state := {"id": "fire-clock-test", "paused": false,
		RegionSaveSlot.SETTLEMENT_FIELD: {"version": 1, "last_settled_game_seconds": 50.0}}
	var active_permit := active_slot.begin_active_step(active_state)
	var active_result := active_slot.record_active_step(active_state, H, active_permit,
		{"action_seconds": H, "tactical_seconds": H, "scale": 1.0, "coordinate": [2, 3], "fire_active": true})
	_check(active_result.ok and absf(float(active_slot.control.logical_game_seconds) - (50.0 + H)) < 0.000000001,
		"Original completed-step publisher advances world time once")
	_check(int(active_slot.control.fire_clock.sequence) == 1 and RegionSaveSlot.validate_fire_clock(active_slot.control.fire_clock,
		active_slot.control.logical_game_seconds).ok and RegionSaveSlot.validate_fire_settlement(active_state, active_slot.control.fire_clock).ok,
		"Same completion records the dual-clock journal, Site watermark, and active index")
	_check(int(active_slot.control.fire_clock.base_sequence) == 1 and active_slot.control.fire_clock.journal.is_empty(),
		"The completed active step prunes history only through its newly settled Site watermark")
	_check(bool(active_slot.control.fire_clock.index["fire-clock-test"].fire_active),
		"Original active index records fire activity for the next cross-Site permit")
	var unchanged_game := float(active_slot.control.logical_game_seconds)
	var bad_permit := active_slot.begin_active_step(active_state)
	var rejected := active_slot.record_active_step(active_state, H, bad_permit,
		{"action_seconds": H, "tactical_seconds": H, "scale": 2.0, "coordinate": [2, 3], "fire_active": true})
	_check(not rejected.ok and float(active_slot.control.logical_game_seconds) == unchanged_game
		and int(active_slot.control.fire_clock.sequence) == 1, "Clock mismatch is rejected before publishing either clock")
	var missing_permit := active_slot.begin_active_step(active_state)
	var missing_interval := active_slot.record_active_step(active_state, H, missing_permit)
	_check(not missing_interval.ok and float(active_slot.control.logical_game_seconds) == unchanged_game
		and int(active_slot.control.fire_clock.sequence) == 1, "A prior fire journal cannot advance without original dual-clock evidence")
	var prune_clock := _clock()
	game = 120.0
	var watermarks: Array[Dictionary] = []
	for slice in range(6):
		var interval := RegionSaveSlot.preview_fire_interval(prune_clock, game, H, 1.0, H)
		_check(interval.ok, "Prefix fixture accepts an original completed interval")
		if not interval.ok: quit(1); return
		game = float(interval.game_end)
		RegionSaveSlot.append_completed_fire_interval(prune_clock, interval)
		watermarks.append({"action_seconds": interval.action_end, "game_seconds": interval.game_end})
	var sequence_by_site := {"slowest": 1, "middle": 3, "latest": 6}
	for identity: String in sequence_by_site:
		var sequence: int = sequence_by_site[identity]
		var watermark: Dictionary = watermarks[sequence - 1]
		prune_clock.index[identity] = {"coordinate": [sequence, 0], "active": identity == "latest",
			"fire_active": false, "sequence": sequence, "action_seconds": watermark.action_seconds,
			"game_seconds": watermark.game_seconds}
	var pruned := RegionSaveSlot.prune_fire_clock_prefix(prune_clock)
	var retained: Dictionary = prune_clock.journal[0] if not prune_clock.journal.is_empty() else {}
	var prefix_valid := RegionSaveSlot.validate_fire_clock(prune_clock, game)
	var prefix_ok: bool = pruned == 1 and int(prune_clock.base_sequence) == 1 and int(retained.get("first_sequence", 0)) == 2 \
		and int(retained.get("steps", 0)) == 5 and prefix_valid.ok
	if not prefix_ok: print("FIRE_CLOCK_PREFIX_DEBUG ", {"pruned": pruned, "base_sequence": prune_clock.base_sequence,
		"base_action_seconds": prune_clock.base_action_seconds, "base_game_seconds": prune_clock.base_game_seconds,
		"journal": prune_clock.journal, "index": prune_clock.index, "validation": prefix_valid})
	_check(prefix_ok,
		"Pruning stops at the oldest Site watermark and clips a compressed interval")
	var oldest_state := {"fire_settlement": {"version": 1, "epoch": prune_clock.epoch, "sequence": 1,
		"action_seconds": watermarks[0].action_seconds, "game_seconds": watermarks[0].game_seconds}}
	var oldest_replay := RegionSaveSlot.fire_replay_segments(oldest_state, prune_clock, game)
	_check(oldest_replay.ok and oldest_replay.segments.size() == 1
		and int(oldest_replay.segments[0].first_sequence) == 2 and int(oldest_replay.segments[0].steps) == 5,
		"The oldest Site resumes exactly after the pruned prefix")
	var wire_commit_value: Variant = JSON.parse_string(JSON.stringify({"logical_game_seconds": game, "fire_clock": prune_clock}))
	var wire_control: Dictionary = wire_commit_value if wire_commit_value is Dictionary else {}
	var wire_clock: Dictionary = wire_control.get("fire_clock", {})
	var wire_game: float = float(wire_control.get("logical_game_seconds", -1.0))
	var wire_replay := RegionSaveSlot.fire_replay_segments(oldest_state, wire_clock, wire_game)
	_check(not wire_clock.is_empty() and int(wire_clock.get("base_sequence", 0)) == 1
		and wire_replay.ok and int(wire_replay.segments[0].first_sequence) == 2,
		"The committed JSON shape preserves the trimmed base and replay suffix: " + str(wire_replay))
	var next_watermark: Dictionary = watermarks[1]
	prune_clock.index.slowest.sequence = 2
	prune_clock.index.slowest.action_seconds = next_watermark.action_seconds
	prune_clock.index.slowest.game_seconds = next_watermark.game_seconds
	pruned = RegionSaveSlot.prune_fire_clock_prefix(prune_clock)
	retained = prune_clock.journal[0]
	var next_state := {"fire_settlement": {"version": 1, "epoch": prune_clock.epoch, "sequence": 2,
		"action_seconds": next_watermark.action_seconds, "game_seconds": next_watermark.game_seconds}}
	var next_replay := RegionSaveSlot.fire_replay_segments(next_state, prune_clock, game)
	var next_steps := int(next_replay.segments[0].steps) if next_replay.ok and not next_replay.segments.is_empty() else 0
	_check(pruned == 1 and int(prune_clock.base_sequence) == 2 and int(retained.first_sequence) == 3
		and int(retained.steps) == 4 and next_replay.ok and next_steps == 4
		and RegionSaveSlot.validate_fire_clock(prune_clock, game).ok,
		"A newly settled oldest Site advances and replays the remaining suffix")
	_check(not RegionSaveSlot.validate_fire_settlement(oldest_state, prune_clock).ok,
		"A Site older than the committed retained prefix is rejected as missing history")
	print("SITE_FIRE_CLOCK_JOURNAL_", "FAIL" if failed else "PASS", ": checks=", checks)
	quit(1 if failed else 0)
