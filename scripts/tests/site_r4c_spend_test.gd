extends SceneTree
## R4c-1 pure spend contract: payer authority liveness (D4), authorization gate, per-person, daily and reserve
## ceilings (D7), and that every refusal leaves the record and the warehouse coin byte-identical.
## No coin moves here: the candidate reports coin_after and the new record for one atomic publish (not yet built).
const Ransom = preload("res://scripts/terrain_lab/site_ransom_data.gd")

func _initialize() -> void:
	call_deferred("run")

var _failed := false

func _fail(message: String) -> void:
	_failed = true
	push_error(message)
	quit(1)

func _site(coin: int) -> Dictionary:
	return {"id": "s", "minute": 1440 * 5, "features": {"w": {"kind": "warehouse", "stage": "complete", "owner_faction": 1}},
		"stockpiles": {"w": {"version": 1, "cargo": {"coin": coin}, "nation_id": "n1"}}}

func _nation(authorized: bool, spent_day: int, spent: int) -> Dictionary:
	var record: Dictionary = Ransom.empty_record()
	record.treasury = {"site_id": "s", "feature_id": "w", "holder": "feature:w"}
	record.policy = {"authorized": authorized, "per_person": 10, "daily": 50, "reserve": 20}
	if authorized: record.policy.authorized_by = 7
	record.spent_day = spent_day
	record.spent = spent
	return {"offices": {}, "members": [7], "ransom_data": record}

func run() -> void:
	var site := _site(60)
	var nation := _nation(true, 5, 0)
	var before: PackedByteArray = var_to_bytes([site, nation])
	var refused: Dictionary = Ransom.spend_candidate(site, "n1", nation, 10, 5, false)
	if str(refused.code) != "STALE_AUTHORITY": _fail("D4: a non-current authorizer is refused: %s" % str(refused))
	if str(Ransom.spend_candidate(site, "n1", _nation(false, 5, 0), 10, 5, true).code) != "NOT_AUTHORIZED": _fail("unauthorized payer is refused")
	if str(Ransom.spend_candidate(site, "n1", nation, 36, 5, true).code) != "INVALID_PRICE": _fail("price above the quote band is refused")
	if str(Ransom.spend_candidate(site, "n1", nation, 4, 5, true).code) != "INVALID_PRICE": _fail("price below the quote band is refused")
	var per_person_nation := _nation(true, 5, 0)
	per_person_nation.ransom_data.policy.per_person = 9
	if str(Ransom.spend_candidate(site, "n1", per_person_nation, 10, 5, true).code) != "PER_PERSON_CEILING": _fail("per-person ceiling refuses the price")
	var daily_nation := _nation(true, 5, 45)
	if str(Ransom.spend_candidate(site, "n1", daily_nation, 10, 5, true).code) != "DAILY_CEILING": _fail("daily ceiling counts the same day")
	var next_day: Dictionary = Ransom.spend_candidate(site, "n1", daily_nation, 10, 6, true)
	if not bool(next_day.ok) or int(next_day.record.spent) != 10 or int(next_day.record.spent_day) != 6: _fail("daily count restarts on a new day: %s" % str(next_day))
	if str(Ransom.spend_candidate(_site(29), "n1", nation, 10, 5, true).code) != "RESERVE": _fail("reserve keeps 20 coin in the warehouse")
	var paid: Dictionary = Ransom.spend_candidate(site, "n1", nation, 10, 5, true)
	if not bool(paid.ok) or int(paid.coin_after) != 50 or int(paid.record.spent) != 10: _fail("a valid payment reports the coin left and the new daily count: %s" % str(paid))
	if var_to_bytes([site, nation]) != before: _fail("refusals and candidates never mutate the live state")
	if _failed: return
	print("SITE R4C SPEND CONTRACT PASS: pure ceilings (per-person, daily by day, reserve) and D4 authority gate refuse without mutation; a valid candidate reports coin_after and the new record. Custody publish is NOT yet built.")
	quit(0)
