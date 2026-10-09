extends SceneTree
## A versioned nation record made before a later duty existed (here: no
## nation.procurement, nation.fleet or nation.admission) gains each missing
## duty's vacant seat through SiteEquipmentOrders.nation_offices on every path,
## not only the Region ones: stored with exactly one revision step on a write
## path, on a copy (stored record untouched) when read-only. The head then acts
## for the vacant seat instead of the duty being orphaned; holders and the
## existing duty bindings never move; a complete record is never bumped again.

func _initialize() -> void:
	call_deferred("run")

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

func _seat(offices: Dictionary, duty_id: String) -> Dictionary:
	return SiteOffices.position(offices, str(offices.duties.get(duty_id, "")))

func run() -> void:
	var head := 7
	var keeper := 8
	var offices := SiteOffices.default_offices("nation", head)
	SiteOffices.position(offices, str(offices.duties["nation.equip_standard"])).holder = keeper
	for late: String in ["nation.procurement", "nation.fleet", "nation.admission"]:
		var seat_id := str(offices.duties[late])
		offices.duties.erase(late)
		var kept: Array = []
		for entry: Dictionary in offices.positions:
			if str(entry.id) != seat_id: kept.append(entry)
		offices.positions = kept
	offices.revision = 4
	if not SiteOffices.validate(offices, "nation"): return _fail("fixture: a pre-catalog record is still valid")
	var nation := {"members": [head, keeper], "standards": {}, "offices": offices}
	var before: Dictionary = offices.duplicate(true)
	var everyone := func(person_id: int) -> bool: return person_id == head or person_id == keeper
	var orphan := SiteOffices.resolve(offices, "nation.procurement", head, everyone)
	if bool(orphan.ok) or str(orphan.code) != "DUTY_ORPHAN": return _fail("fixture: procurement starts orphaned: %s" % str(orphan))
	# Read-only: a complete copy; the stored record is untouched.
	var preview := SiteEquipmentOrders.nation_offices(nation, true)
	if nation.offices != before: return _fail("Read-only path never writes the stored record")
	var read := SiteOffices.resolve(preview, "nation.procurement", head, everyone)
	if not bool(read.ok) or int(read.decider) != head: return _fail("Read-only: the head acts for vacant 採購: %s" % str(read))
	# Write path: stored once, one revision step.
	var stored := SiteEquipmentOrders.nation_offices(nation)
	if not is_same(stored, nation.offices) or int(stored.revision) != 5: return _fail("Write path stores the seats with one revision step: %s" % str(stored.revision))
	if not SiteOffices.validate(stored, "nation"): return _fail("Completed record validates")
	for late: String in ["nation.procurement", "nation.fleet", "nation.admission"]:
		var seat := _seat(stored, late)
		if seat.is_empty() or bool(seat.head) or int(seat.holder) != -1: return _fail("%s: own vacant non-head seat: %s" % [late, str(seat)])
		if str(seat.office_class) != SiteOffices.default_class(late): return _fail("%s: default class" % late)
	if str(_seat(stored, "nation.fleet").office_class) != "military" or str(_seat(stored, "nation.procurement").office_class) != "civil":
		return _fail("船隊編入 is a 武官 seat, 採購 a 文官 seat")
	var acted := SiteOffices.resolve(stored, "nation.procurement", head, everyone)
	if not bool(acted.ok) or int(acted.decider) != head: return _fail("Write path: the head acts for vacant 採購: %s" % str(acted))
	if int(SiteOffices.head_position(stored).holder) != head or int(_seat(stored, "nation.equip_standard").holder) != keeper \
		or str(stored.duties["nation.culture"]) != str(before.duties["nation.culture"]):
		return _fail("Holders and existing bindings never move")
	var again := SiteEquipmentOrders.nation_offices(nation)
	if int(again.revision) != 5 or again.positions.size() != stored.positions.size(): return _fail("A complete record is never bumped again")
	var preview_again := SiteEquipmentOrders.nation_offices(nation, true)
	if not is_same(preview_again, nation.offices): return _fail("A complete current record is read in place (no copy)")
	print("SITE NATION LATER DUTY CATALOG PASS: pre-catalog record gains vacant 採購/船隊編入/戶籍官 seats (civil/military by default), read-only on a copy, write path stored with one revision step, head acts, holders and bindings unchanged, no second bump")
	quit(0)
