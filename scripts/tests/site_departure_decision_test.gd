extends SceneTree
## R6 S2 (pure): the NPC departure decision (plan 8.4, 10.2). H is clamped to 30..95; G>=H on three consecutive observed days
## forms the intent; G below H resets the observation; the established intent clears only below H-10 (hysteresis); blocked and
## controlled people do not depart automatically; the visible status bands follow plan 8.4.

const Decision = preload("res://scripts/terrain_lab/site_departure_decision.gd")

func _initialize() -> void:
	call_deferred("run")

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func run() -> void:
	if not _check(Decision.threshold(50, 50) == 70, "neutral ambition and lawfulness give H 70"): return
	if not _check(Decision.threshold(90, 50) == 54 and Decision.threshold(50, 90) == 86, "ambition lowers and lawfulness raises H by 2 per 5 points"): return
	if not _check(Decision.threshold(100, 0) == 30 and Decision.threshold(0, 100) == 95, "H is clamped to 30..95"): return

	var h: int = 70
	if not _check(Decision.decide(50, 50, 100, false, 9, false, true).action == "stay", "a controlled person never departs automatically"): return
	if not _check(Decision.decide(50, 50, 80, false, 0, true, false).action == "observe", "a blocked NPC still observes and cannot depart before an intent exists"): return
	if not _check(Decision.decide(50, 50, h - 1, false, 2, false, false).action == "reset", "G below H resets the observation"): return
	var first: Dictionary = Decision.decide(50, 50, h, false, 0, false, false)
	if not _check(first.action == "observe" and int(first.days_left) == 2, "the first day at H observes with two days left"): return
	var second: Dictionary = Decision.decide(50, 50, h, false, 1, false, false)
	if not _check(second.action == "observe" and int(second.days_left) == 1, "the second day observes with one day left"): return
	if not _check(Decision.decide(50, 50, h, false, 2, false, false).action == "intent", "the third observed day at H forms the intent"): return

	if not _check(Decision.decide(50, 50, h - 9, true, 0, false, false).action == "depart", "an established intent above H-10 departs when not blocked (G 61)"): return
	if not _check(Decision.decide(50, 50, h - 10, true, 0, false, false).action == "depart", "an established intent is retained at H-10"): return
	if not _check(Decision.decide(50, 50, h - 9, true, 0, true, false).action == "wait", "a blocked established intent waits rather than departs"): return
	if not _check(Decision.decide(50, 50, h - 11, true, 0, false, false).action == "clear_intent", "an established intent clears strictly below H-10"): return
	if not _check(Decision.decide(50, 50, h - 10, true, 0, true, false).action == "wait", "at H-10 a blocked intent is retained and waits"): return
	if not _check(Decision.decide(50, 50, h - 11, true, 0, true, false).action == "clear_intent", "blocked does not prevent clearing below H-10"): return

	var blocked_first: Dictionary = Decision.decide(50, 50, h, false, 0, true, false)
	if not _check(blocked_first.action == "observe" and int(blocked_first.days_left) == 2, "blocked high G still starts observation"): return
	var blocked_second: Dictionary = Decision.decide(50, 50, h, false, 1, true, false)
	if not _check(blocked_second.action == "observe" and int(blocked_second.days_left) == 1, "blocked high G still advances observation"): return
	var blocked_third: Dictionary = Decision.decide(50, 50, h, false, 2, true, false)
	if not _check(blocked_third.action == "intent", "blocked high G still forms the intent on the third observed day"): return
	if not _check(Decision.decide(50, 50, h - 1, false, 2, true, false).action == "reset", "blocked low G resets an unestablished observation"): return
	if not _check(Decision.decide(50, 50, h, true, 3, true, false).action == "wait", "a newly established intent waits while blocked"): return
	if not _check(Decision.decide(50, 50, h, true, 3, false, false).action == "depart", "removing blocked permits the established intent to depart"): return

	if not _check(Decision.status(50, 50, 20) == "none" and Decision.status(50, 50, 40) == "unhappy", "the visible bands start at 30 for unhappy"): return
	if not _check(Decision.status(50, 50, 60) == "likely" and Decision.status(50, 50, 70) == "threshold", "the visible bands: likely at H-10, threshold at H"): return

	print("SITE R6 S2 DEPARTURE DECISION PASS: H follows ambition and lawfulness and is clamped; G at H forms the intent on the third observed day; G below H resets; the intent clears only below H-10; blocked preserves observation and only delays departure; controlled people do not depart; the visible status bands follow plan 8.4.")
	quit(0)
