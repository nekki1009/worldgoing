extends SceneTree
## R5 S4 (pure): vacancy contest timer driven only by G0 proven political days (plan line 475).
## The contest opens after one proven day of continuous vacancy and reaches its deadline after two further proven
## days. Refusals leave the timer byte-identical; the JSON round trip keeps the counters as integers.

const Contest = preload("res://scripts/terrain_lab/site_succession_contest.gd")

func _initialize() -> void:
	call_deferred("run")

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func run() -> void:
	var onset := 10 # the vacancy began during political day 10
	var timer: Dictionary = Contest.empty_timer(onset)
	if not _check(Contest.valid_timer(timer) and str(timer.status) == "waiting" and int(timer.proven_days) == 0, "a new vacancy timer starts waiting with no proven day"): return

	# The onset day started before the vacancy, so it never counts.
	var same_day: Dictionary = Contest.tick(timer, onset)
	if not _check(bool(same_day.ok) and int(same_day.timer.proven_days) == 0 and str(same_day.timer.status) == "waiting", "the onset day does not count as a proven day"): return

	# One proven day after the onset opens the contest.
	var opened: Dictionary = Contest.tick(timer, onset + 1)
	if not _check(bool(opened.ok) and int(opened.timer.proven_days) == 1 and str(opened.timer.status) == "open", "one proven day after the onset opens the contest"): return
	timer = opened.timer

	# The same proven day observed again changes nothing.
	var before_repeat: PackedByteArray = var_to_bytes(timer)
	var repeated: Dictionary = Contest.tick(timer, onset + 1)
	if not _check(bool(repeated.ok) and var_to_bytes(repeated.timer) == before_repeat, "a repeated proven day changes nothing"): return

	# One further proven day is still short of the deadline.
	var second: Dictionary = Contest.tick(timer, onset + 2)
	if not _check(bool(second.ok) and int(second.timer.proven_days) == 2 and str(second.timer.status) == "open", "two proven days (one short of the deadline) keep the contest open"): return
	timer = second.timer

	# A skipped political day is not proven and does not count; the next proven day counts once.
	var deadline: Dictionary = Contest.tick(timer, onset + 4)
	if not _check(bool(deadline.ok) and int(deadline.timer.proven_days) == 3 and str(deadline.timer.status) == "deadline_reached", "two further proven days after opening reach the deadline; a skipped day counts once"): return
	timer = deadline.timer

	# Proven days never move backwards; the refusal leaves the timer byte-identical.
	var before_regress: PackedByteArray = var_to_bytes(timer)
	var regressed: Dictionary = Contest.tick(timer, onset + 3)
	if not _check(not bool(regressed.ok) and str(regressed.code) == "REGRESSED" and var_to_bytes(timer) == before_regress, "an earlier proven day is refused and leaves the timer unchanged"): return

	# Corrupt shapes are refused: an extra field, and a status that disagrees with the counter.
	var extra: Dictionary = timer.duplicate(true)
	extra["wall_clock"] = 0
	if not _check(not Contest.valid_timer(extra) and str(Contest.tick(extra, onset + 5).code) == "CORRUPT_STATE", "a timer with an extra field is refused"): return
	var mismatch: Dictionary = timer.duplicate(true)
	mismatch.status = "open"
	if not _check(not Contest.valid_timer(mismatch), "a status that disagrees with the proven-day counter is refused"): return

	# JSON round trip: floats restore to exact integers and the deadline status survives.
	var parsed: Variant = JSON.parse_string(JSON.stringify(timer))
	if not _check(parsed is Dictionary, "the timer survives a JSON round trip"): return
	Contest.normalize_numbers(parsed)
	if not _check(Contest.valid_timer(parsed) and typeof(parsed.proven_days) == TYPE_INT and int(parsed.proven_days) == 3 and str(parsed.status) == "deadline_reached", "the round-tripped timer validates with integer counters"): return

	print("SITE R5 S4 CONTEST TIMER PASS: the contest opens after one proven day of vacancy, stays open after two, reaches its deadline after three, skips unproven days, refuses regression and corrupt shapes byte-identically, and keeps integer counters through JSON.")
	quit(0)
