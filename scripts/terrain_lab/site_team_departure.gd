extends RefCounted
## R6 S4 (pure, plan 10.1 退隊): the officer-seat part of a team departure. The roster leave is the existing
## terrain_army.leave_row (roster row, vacancy assignment and combat plan entries). This vacates the seats the departing
## person holds in the team's offices and adds one revision step. Original supply owners are not changed here (leave_row
## leaves them untouched); a supply transfer is a later slice.

## Returns a candidate; the source offices are never written.
static func vacate_seats(offices: Dictionary, person_id: int) -> Dictionary:
	if person_id <= 0 or not offices.get("positions") is Array:
		return {"ok": false, "code": "NO_TARGET", "message": "沒有此隊職位"}
	var candidate: Dictionary = offices.duplicate(true)
	var seat_vacated := false
	var changed := false
	for entry: Dictionary in candidate.positions:
		if int(entry.holder) == person_id:
			entry.holder = -1
			changed = true
			if bool(entry.head): seat_vacated = true
	if changed: candidate.revision = mini(SiteOffices.MAX_SEQ, int(candidate.revision) + 1)
	return {"ok": true, "code": "", "message": "", "offices": candidate, "seat_vacated": seat_vacated, "changed": changed}
