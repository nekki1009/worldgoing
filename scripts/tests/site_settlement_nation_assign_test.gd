extends SceneTree
## P4 S3: the settlement's formal nation (head-only setter, v4 candidate, validated as a whole).
## A bare TerrainData carries the settlement record and its center feature; no Site fixture.

const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")

const SITE := "p4s3_site"
const HEAD_ID := 7

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("SITE_SETTLEMENT_NATION_ASSIGN_FAIL: " + message)
	quit(1)
	return false

func _v1(head_holder: int) -> Dictionary:
	var offices: Dictionary = SiteOffices.default_offices("settlement")
	for entry: Dictionary in offices.positions:
		if bool(entry.head): entry.holder = head_holder
	return {"version": 1, "settlement_id": "settlement_p4s3", "center_id": "c1", "level": 0, "name": "甲",
		"owner_faction": 1, "offices": offices, "fall_record": Settlement.empty_fall_record()}

func _site(record: Dictionary) -> TerrainData:
	var data := TerrainData.new()
	data.site = {"id": SITE, "features": {"c1": {"kind": "settlement_center", "stage": "pending", "owner_faction": 1}},
		"equipment_nations": {"n1": {"members": []}, "trial_team_x": {"members": []}}, "settlement": record, "minute": 0}
	return data

func _run() -> void:
	create_timer(30.0).timeout.connect(func() -> void: push_error("SITE_SETTLEMENT_NATION_ASSIGN_TIMEOUT"); quit(1))

	# A non-head and a vacant head are refused; nothing changes.
	var guarded := _site(_v1(HEAD_ID))
	var guarded_before: String = JSON.stringify(guarded.site)
	var by_other: Dictionary = Settlement.set_nation(guarded, 3, "n1")
	if not _check(by_other.code == "NO_AUTHORITY" and JSON.stringify(guarded.site) == guarded_before, "non-head refused, unchanged"): return
	var vacant := _site(_v1(-1))
	var vacant_before: String = JSON.stringify(vacant.site)
	var no_head: Dictionary = Settlement.set_nation(vacant, HEAD_ID, "n1")
	if not _check(no_head.code == "NO_AUTHORITY" and JSON.stringify(vacant.site) == vacant_before, "vacant head refused, unchanged"): return

	# Unknown, trial, empty and non-String nations are refused; nothing changes.
	for bad: Variant in ["n2", "trial_team_x", "", 3]:
		var attempt := _site(_v1(HEAD_ID))
		var attempt_before: String = JSON.stringify(attempt.site)
		var refused: Dictionary = Settlement.set_nation(attempt, HEAD_ID, bad)
		if not _check(not refused.ok and refused.code == "NATION_UNKNOWN" and JSON.stringify(attempt.site) == attempt_before, "nation %s refused, unchanged" % str(bad)): return

	# The head assigns a real nation: v1 upgraded to v4 in one candidate; faction and center untouched.
	var site := _site(_v1(HEAD_ID))
	var features_before: String = JSON.stringify(site.site.features)
	var assigned: Dictionary = Settlement.set_nation(site, HEAD_ID, "n1")
	if not _check(assigned.ok, "head assigns n1: " + str(assigned)): return
	var record: Dictionary = site.site.settlement
	if not _check(int(record.version) == 4 and record.nation_id == "n1" and int(record.trade_tax_percent) == 0, "record upgraded to v4 with n1 and tax 0"): return
	if not _check(int(record.owner_faction) == 1 and JSON.stringify(site.site.features) == features_before, "owner faction and center features unchanged"): return
	if not _check(record.technology.holder_site_id == SITE, "technology scope belongs to this Site"): return

	# Validation reads the head as a person of the owner faction (`people`); a vacant or unknown head is refused.
	var people: Dictionary = {HEAD_ID: {"faction_id": 1}}
	var before_trip: Dictionary = Settlement.validate(site, site.site, people)
	if not _check(before_trip.ok, "assigned record validates before the round trip: " + str(before_trip)): return
	# Round trip, normalized exactly as the loader does for settlements (SiteStore calls Settlement.normalize).
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(site.site))
	Settlement.normalize(parsed)
	var after_trip: Dictionary = Settlement.validate(site, parsed, people)
	if not _check(after_trip.ok, "assigned record validates after a JSON round trip: " + str(after_trip)): return
	if not _check(str(parsed.settlement.nation_id) == "n1", "nation n1 survives the round trip"): return

	# Clearing keeps the rate; a non-head cannot clear.
	record.trade_tax_percent = 30
	var cleared: Dictionary = Settlement.set_nation(site, HEAD_ID, null)
	if not _check(cleared.ok and site.site.settlement.nation_id == null and int(site.site.settlement.trade_tax_percent) == 30, "clearing to no nation keeps the rate"): return
	var cleared_before: String = JSON.stringify(site.site)
	if not _check(Settlement.set_nation(site, 3, "n1").code == "NO_AUTHORITY" and JSON.stringify(site.site) == cleared_before, "non-head cannot assign after clearing"): return

	print("SITE_SETTLEMENT_NATION_ASSIGN_PASS: head-only assignment, v4 upgrade, unknown and trial nations refused, faction and center untouched, JSON round trip validates")
	quit(0)
