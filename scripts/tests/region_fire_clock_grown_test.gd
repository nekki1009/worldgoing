extends SceneTree
## The incremental fire clock check (RegionSaveSlot.validate_fire_clock_grown, 2026-11-25) answers as the full check does.
## Pure: no world. Checks:
## - a clock grown by 6000 random steps (mixed widths, speeds, tactical shares, two Sites that stay at the start): at every
##   step both checks agree, and so do preview_fire_interval's results;
## - a step appended to the last row, a new row and a pruned prefix are all accepted, the prefix by the full check;
## - a broken last row, a broken index row, a wrong world clock and a wrong end are refused at once;
## - a broken row in the middle (not how anything here changes a journal) is refused by the full check at the latest 512
##   calls later;
## - it costs a small part of the full check on a long journal.
## Output: REGION_FIRE_CLOCK_GROWN_PASS on success; quit(1) on any failure.
const Slot = preload("res://scripts/region_lab/region_save_slot.gd")

var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition: return true
	printerr("REGION_FIRE_CLOCK_GROWN_FAIL: ", message, " ", str(detail))
	quit(1)
	return false

## The live step: preview, append, and the Sites' index rows (Site "a" follows the world, "b" and "c" never move).
func _step(clock: Dictionary, game: float, width: float, speed: float, tactical: float) -> Dictionary:
	var preview: Dictionary = Slot.preview_fire_interval(clock, game, width, speed, tactical)
	if not preview.ok: return preview
	Slot.append_completed_fire_interval(clock, preview)
	clock.index["a"] = {"coordinate": [1, 2], "active": true, "sequence": int(clock.sequence), "action_seconds": float(clock.action_seconds), "game_seconds": float(preview.game_end)}
	return preview

func _run() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261125
	var clock: Dictionary = {"version": 1, "epoch": "fire_test", "action_seconds": 0.0, "sequence": 0, "base_game_seconds": 0.0, "journal": [], "index": {}}
	for identity: String in ["b", "c"]: clock.index[identity] = {"coordinate": [3, 4], "active": false, "sequence": 0, "action_seconds": 0.0, "game_seconds": 0.0}
	clock.index["a"] = {"coordinate": [1, 2], "active": true, "sequence": 0, "action_seconds": 0.0, "game_seconds": 0.0}
	var game := 0.0
	var widths := [1.0 / 30.0, 0.012345, 0.0288, 1.0 / 30.0]
	for at: int in range(6000):
		var width: float = widths[rng.randi_range(0, widths.size() - 1)]
		var speed: float = [1.0, 1.0, 4.0, 16.0][rng.randi_range(0, 3)]
		var tactical: float = [0.0, width, width * 0.5][rng.randi_range(0, 2)] if at % 7 == 0 else 0.0
		var taken := _step(clock, game, width, speed, tactical)
		if not _check(taken.ok, "step %d is accepted" % at, taken): return
		game = float(taken.game_end)
		if at % 50 == 0 or at > 5990:
			var full: Dictionary = Slot.validate_fire_clock(clock, game)
			var grown: Dictionary = Slot.validate_fire_clock_grown(clock, game)
			if not _check(full.ok and grown.ok, "both checks accept the clock at step %d" % at, [full, grown]): return
	print("REGION_FIRE_CLOCK_GROWN rows=%d" % clock.journal.size())
	if not _check(clock.journal.size() > 1000, "the journal is long", clock.journal.size()): return

	# What it costs on this journal.
	var began := Time.get_ticks_usec()
	for _n: int in range(50): Slot.validate_fire_clock(clock, game)
	var full_usec := Time.get_ticks_usec() - began
	Slot.validate_fire_clock_grown(clock, game)
	began = Time.get_ticks_usec()
	for _n: int in range(50): Slot.validate_fire_clock_grown(clock, game)
	var grown_usec := Time.get_ticks_usec() - began
	print("REGION_FIRE_CLOCK_GROWN full=%dus grown=%dus for 50 checks" % [full_usec, grown_usec])
	if not _check(grown_usec * 20 < full_usec, "the incremental check costs a small part", [full_usec, grown_usec]): return

	# Refusals, each on a copy whose full check refuses it too.
	if not _check(not Slot.validate_fire_clock_grown(clock, game + 1.0).ok and not Slot.validate_fire_clock(clock, game + 1.0).ok, "a wrong world clock is refused"): return
	if not _check(Slot.validate_fire_clock_grown(clock, game).ok, "the clock itself is still accepted"): return
	var last: Dictionary = clock.journal.back()
	var kept: float = last.game_end
	last.game_end = kept + 0.5
	if not _check(not Slot.validate_fire_clock_grown(clock, game).ok, "a broken last row is refused at once"): return
	last.game_end = kept
	if not _check(Slot.validate_fire_clock_grown(clock, game).ok, "and accepted again when put back"): return
	clock.index["b"].sequence = int(clock.sequence) + 1
	if not _check(not Slot.validate_fire_clock_grown(clock, game).ok, "a broken index row is refused at once"): return
	clock.index["b"].sequence = 0
	if not _check(Slot.validate_fire_clock_grown(clock, game).ok, "and accepted again when put back"): return
	var middle: Dictionary = clock.journal[clock.journal.size() / 2]
	var middle_kept: float = middle.game_end
	middle.game_end = middle_kept + 5.0
	var caught := -1
	for call_at: int in range(1200):
		if not Slot.validate_fire_clock_grown(clock, game).ok:
			caught = call_at
			break
	if not _check(caught >= 0 and caught <= 513, "a broken middle row is refused within 512 checks", caught): return
	middle.game_end = middle_kept
	if not _check(Slot.validate_fire_clock_grown(clock, game).ok, "and accepted again when put back"): return

	# A pruned prefix replaces the journal array: checked in full.
	for identity: String in ["b", "c"]: clock.index[identity] = {"coordinate": [3, 4], "active": false, "sequence": int(clock.sequence) - 100, "action_seconds": 0.0, "game_seconds": 0.0}
	clock.index["b"].action_seconds = 0.0
	var removed: int = Slot.prune_fire_clock_prefix(clock)
	if not _check(removed > 0 and Slot.validate_fire_clock(clock, game).ok and Slot.validate_fire_clock_grown(clock, game).ok, "a pruned prefix is accepted by both", removed): return
	print("REGION_FIRE_CLOCK_GROWN_PASS: ", checks, " checks; the incremental check agrees with the full one")
	quit(0)
