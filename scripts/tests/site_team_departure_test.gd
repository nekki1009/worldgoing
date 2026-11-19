extends SceneTree
## R6 S4 (pure): the team departure's officer seats. A departing person's held seats are vacated (a head seat reported), the
## revision steps once when a seat changes and not otherwise, and the source offices are never written.

const Team = preload("res://scripts/terrain_lab/site_team_departure.gd")

func _initialize() -> void:
	call_deferred("run")

func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func run() -> void:
	var offices: Dictionary = SiteOffices.default_offices("team", 1, false)
	var other_seat: Dictionary = {}
	for entry: Dictionary in offices.positions:
		if not bool(entry.head):
			other_seat = entry
			break
	if not _check(not other_seat.is_empty(), "the team catalog has a non-head seat"): return
	other_seat.holder = 9
	var before: PackedByteArray = var_to_bytes(offices)
	var revision: int = int(offices.revision)

	var head_left: Dictionary = Team.vacate_seats(offices, 1)
	if not _check(bool(head_left.ok) and bool(head_left.seat_vacated) and int(SiteOffices.head_position(head_left.offices).holder) == -1, "the departing head vacates the head seat and reports it"): return
	if not _check(int(head_left.offices.revision) == revision + 1, "one revision step when a seat changes"): return
	if not _check(var_to_bytes(offices) == before, "the source offices are not written"): return

	var seat_left: Dictionary = Team.vacate_seats(offices, 9)
	if not _check(bool(seat_left.ok) and not bool(seat_left.seat_vacated) and bool(seat_left.changed), "a non-head seat is vacated without reporting a head"): return

	var nobody: Dictionary = Team.vacate_seats(offices, 77)
	if not _check(bool(nobody.ok) and not bool(nobody.changed) and int(nobody.offices.revision) == revision, "a person holding no seat changes nothing and keeps the revision"): return

	if not _check(str(Team.vacate_seats(offices, 0).code) == "NO_TARGET", "a non-person is refused"): return

	print("SITE R6 S4 TEAM OFFICE SEATS PASS: the departing team person's seats are vacated (a head reported), the revision steps once only when a seat changes, and the source offices are never written.")
	quit(0)
