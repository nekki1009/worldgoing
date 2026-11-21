extends SceneTree
## R5 S2 (pure): the vacancy take-office core. Authority is controlled-only; a commit moves a stale seat of the same
## person (no duplicate), adds one revision step, and a refusal leaves the source byte-identical.

const Take = preload("res://scripts/terrain_lab/site_take_office.gd")

func _initialize() -> void:
	call_deferred("run")

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func run() -> void:
	var controlled := 7
	var other := 9
	var controlled_auth := {"kind": "controlled"}
	if not _check(str(Take.authority_refusal("controlled", controlled, controlled).code) == "NO_AUTHORITY", "a bare string is not authority"): return
	if not _check(str(Take.authority_refusal({"kind": "vacancy_contest", "episode_id": "e1"}, controlled, controlled).code) == "NO_AUTHORITY", "contest authority is not accepted in S2"): return
	if not _check(str(Take.authority_refusal(controlled_auth, other, controlled).code) == "NO_AUTHORITY", "a non-controlled requester is refused"): return
	if not _check(str(Take.authority_refusal({"kind": "controlled", "seat": "deputy"}, controlled, controlled).code) == "UNSUPPORTED", "a deputy seat is UNSUPPORTED"): return
	if not _check(bool(Take.authority_refusal(controlled_auth, controlled, controlled).ok), "controlled head authority is accepted"): return

	# A vacant head and a stale seat of the same person elsewhere in the same owner.
	var offices: Dictionary = SiteOffices.default_offices("settlement", -1, false)
	var stale_seat: Dictionary = {}
	for entry: Dictionary in offices.positions:
		if not bool(entry.head):
			stale_seat = entry
			break
	if not _check(not stale_seat.is_empty(), "the catalog has a non-head seat"): return
	stale_seat.holder = other
	var before: PackedByteArray = var_to_bytes(offices)
	var revision: int = int(offices.revision)
	var committed: Dictionary = Take.commit_head(offices, other)
	if not _check(bool(committed.ok), "a vacant head takes a person who holds another seat: %s" % str(committed)): return
	var taken: Dictionary = committed.offices
	if not _check(int(SiteOffices.head_position(taken).holder) == other, "the head seat holds the person"): return
	if not _check(_holders_of(taken, other) == 1, "the stale seat is moved, not duplicated"): return
	if not _check(int(taken.revision) == revision + 1, "one revision step on success"): return
	if not _check(var_to_bytes(offices) == before, "the source offices are not written by commit_head"): return

	# Refusals leave the source byte-identical.
	var refused_zero: Dictionary = Take.commit_head(offices, 0)
	if not _check(str(refused_zero.code) == "NO_TARGET" and var_to_bytes(offices) == before, "a zero person is refused and the source is unchanged"): return
	var refused_empty: Dictionary = Take.commit_head({}, other)
	if not _check(str(refused_empty.code) == "NO_TARGET", "offices without a head seat are refused"): return

	# A second take of the same person into the already-filled head is still one seat for that person.
	var repeated: Dictionary = Take.commit_head(taken, other)
	if not _check(bool(repeated.ok) and _holders_of(repeated.offices, other) == 1, "the same person never holds two seats"): return

	print("SITE R5 S2 TAKE-OFFICE CORE PASS: controlled authority only (contest, bare string, non-controlled and deputy refused); a commit moves a stale seat without duplicating it, adds one revision step, and a refusal leaves the source byte-identical.")
	quit(0)

func _holders_of(offices: Dictionary, person_id: int) -> int:
	var count := 0
	for entry: Dictionary in offices.positions:
		if int(entry.holder) == person_id: count += 1
	return count
