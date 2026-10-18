extends SceneTree
## R7 S1 (pure): the group defection batch. Each supporter follows its own threshold (no automatic follow); ten per batch with
## the eleventh in the next batch; captive holders and treasury carriers are not taken along; a duplicate id or a departed id is
## refused; a batch with one invalid member commits nothing.

const Batch = preload("res://scripts/terrain_lab/site_defection_batch.gd")

func _initialize() -> void:
	call_deferred("run")

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func _person(identity: int, g: int, intent: bool) -> Dictionary:
	return {"id": identity, "ambition": 50, "lawfulness": 50, "g": g, "intent": intent, "observed_days": 0, "blocked": false,
		"controlled": false, "willing": true, "holds_captives": false, "carries_treasury": false}

func run() -> void:
	# Twelve people, all past their own threshold (H 70, depart above 60 with an established intent), given in reverse order.
	var people: Array = []
	for identity: int in range(12, 0, -1):
		people.append(_person(identity, 65, true))
	var batch: Dictionary = Batch.select(people, [])
	if not _check(bool(batch.ok) and batch.members == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] and batch.next == [11, 12], "ten join in stable id order; the eleventh and twelfth go to the next batch"): return

	# No automatic follow: a supporter below its own threshold stays, whatever the others do.
	var mixed: Array = [_person(1, 65, true), _person(2, 40, false), _person(3, 65, true)]
	var mixed_batch: Dictionary = Batch.select(mixed, [])
	if not _check(mixed_batch.members == [1, 3] and mixed_batch.excluded.has({"id": 2, "code": "NOT_DECIDED"}), "a supporter below its own threshold does not follow"): return

	# Captive holders and treasury carriers are not taken along; an unwilling person is not taken either.
	var guarded: Array = [_person(1, 65, true), _person(2, 65, true), _person(3, 65, true), _person(4, 65, true)]
	guarded[1].holds_captives = true
	guarded[2].carries_treasury = true
	guarded[3].willing = false
	var guarded_batch: Dictionary = Batch.select(guarded, [])
	if not _check(guarded_batch.members == [1] and guarded_batch.excluded.has({"id": 2, "code": "CAPTIVES_HELD"}) and guarded_batch.excluded.has({"id": 3, "code": "TREASURY_CARRIED"}) and guarded_batch.excluded.has({"id": 4, "code": "NOT_WILLING"}), "captive holders, treasury carriers and unwilling people are excluded"): return

	# A departed id is not reused; a duplicate id refuses the whole selection (no clone).
	var reuse: Dictionary = Batch.select([_person(1, 65, true), _person(2, 65, true)], [1])
	if not _check(reuse.members == [2] and reuse.excluded.has({"id": 1, "code": "ALREADY_DEPARTED"}), "a departed id is not reused"): return
	var cloned: Dictionary = Batch.select([_person(1, 65, true), _person(1, 65, true)], [])
	if not _check(str(cloned.code) == "DUPLICATE_ID" and cloned.members.is_empty(), "a duplicate id refuses the whole selection"): return

	# All-or-nothing commit: one invalid member commits nothing; all valid commit the whole batch.
	var valid: Dictionary = {}
	for identity: int in range(1, 11): valid[identity] = true
	var committed: Dictionary = Batch.commit(batch, valid)
	if not _check(bool(committed.ok) and committed.committed.size() == 10, "a fully valid batch commits all ten"): return
	var one_bad: Dictionary = valid.duplicate()
	one_bad[5] = false
	var refused: Dictionary = Batch.commit(batch, one_bad)
	if not _check(str(refused.code) == "BATCH_INVALID" and refused.committed.is_empty() and int(refused.failed) == 5, "one invalid member refuses the batch with nothing committed"): return

	print("SITE R7 S1 DEFECTION BATCH PASS: supporters follow only on their own threshold; ten per batch in stable order with the eleventh to the next batch; captive holders, treasury carriers and unwilling people are not taken; departed and duplicate ids are refused; a batch with one invalid member commits nothing.")
	quit(0)
