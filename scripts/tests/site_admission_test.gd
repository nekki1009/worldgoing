extends SceneTree
## R7 D (pure): the admission rule with the command-center decisions. The personality gate is strict (ambition > 70, lawful < 40);
## the ratio is the exact integer test numerator * 5 >= denominator; disqualified (captive, not in the list), remote and dead members
## leave the denominator; controlled abstainers stay in it; the loser's own ballot counts; the invitation follows each supporter's own
## departure rule and the batch cap.

const Admission = preload("res://scripts/terrain_lab/site_admission.gd")

func _initialize() -> void:
	call_deferred("run")

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func _member(identity: int, ballot: int) -> Dictionary:
	return {"id": identity, "loaded": true, "alive": true, "awake": true, "free": true, "captive": false, "in_list": true, "controlled": false, "ballot": ballot}

func run() -> void:
	var loser := 9
	# Five members: one loser-supporter of five is exactly 20%, admitted; four of five is admitted; one of six is below 20%.
	var five: Array = []
	for identity: int in [1, 2, 3, 4, 5]: five.append(_member(identity, loser if identity == 1 else 0))
	if not _check(bool(Admission.admission(71, 39, five, loser).ok), "exactly 20 percent (1 of 5) is admitted"): return
	if not _check(str(Admission.admission(70, 39, five, loser).code) == "NOT_ADMITTED", "ambition 70 is not above 70"): return
	if not _check(str(Admission.admission(71, 40, five, loser).code) == "NOT_ADMITTED", "lawful 40 is not below 40"): return
	var six: Array = []
	for identity: int in [1, 2, 3, 4, 5, 6]: six.append(_member(identity, loser if identity == 1 else 0))
	if not _check(str(Admission.admission(71, 39, six, loser).code) == "BELOW_RATIO", "1 of 6 is below 20 percent (1*5 < 6)"): return
	var none_loaded: Array = [{"id": 1, "loaded": false, "alive": true, "awake": true, "free": true, "captive": false, "in_list": true, "controlled": false, "ballot": 0}]
	if not _check(str(Admission.admission(71, 39, none_loaded, loser).code) == "NO_RATIO", "a denominator of 0 gives no invitation"): return

	# Exclusions: a captive, a non-member, a remote member and a dead member leave the denominator; a controlled abstainer stays in.
	var mixed: Array = [_member(1, loser), _member(2, 0), _member(3, 0), _member(4, 0), _member(5, 0)]
	mixed[2].captive = true
	mixed[3].in_list = false
	mixed[4].loaded = false
	if not _check(Admission.denominator(mixed) == 2 and Admission.numerator(mixed, loser) == 1, "captive, non-member and remote leave the denominator; the loser's ballot counts"): return
	var abstainer: Array = [_member(1, loser), _member(2, 0)]
	abstainer[1].controlled = true
	if not _check(Admission.denominator(abstainer) == 2, "a controlled abstainer stays in the denominator"): return
	var dead: Array = [_member(1, loser), _member(2, 0)]
	dead[1].alive = false
	if not _check(Admission.denominator(dead) == 1, "a dead member leaves the denominator"): return

	# The invitation: each supporter follows its own departure rule (intent established above H-10 and not blocked departs).
	var supporters: Array = []
	for identity: int in range(1, 13):
		supporters.append({"id": identity, "ambition": 50, "lawful": 50, "g": 65, "intent": true, "observed_days": 0, "blocked": false,
			"controlled": false, "willing": true, "holds_captives": false, "carries_treasury": false})
	var invited: Dictionary = Admission.invitation(supporters)
	if not _check(invited.members == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] and invited.next == [11, 12], "ten invited per batch, the rest to the next batch"): return
	supporters[0].g = 40
	supporters[0].intent = false
	var reduced: Dictionary = Admission.invitation(supporters)
	if not _check(not reduced.members.has(1) and reduced.members == [2, 3, 4, 5, 6, 7, 8, 9, 10, 11] and reduced.next == [12], "a supporter below its own threshold is not invited; the batch refills from the next"): return

	print("SITE R7 D ADMISSION PASS: the personality gate is strict; the 20 percent ratio is the exact integer test; captive, non-member, remote and dead members leave the denominator, the controlled abstainer stays; the loser's own ballot counts; the invitation follows each supporter's own departure rule and the cap of ten.")
	quit(0)
