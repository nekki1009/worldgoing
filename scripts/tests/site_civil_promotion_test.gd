extends "res://scripts/tests/site_building_ui_test.gd"
## 文武官 W3 (reports/civil-military-office-plan.md §5.3). Checks:
## - the PersonSocial `civil_service` field: valid on v1/v3, kept by upgraded(), refused when malformed;
## - a 文吏 in a civil settlement seat with a duty is promoted to 文官 after 60 consecutive days, counted once a day;
## - a gap or a different seat starts the count over; a person with no civil role is not counted;
## - research_finished makes a researcher without a civil role a 文吏 and leaves a 文官 alone.
## Output: SITE_CIVIL_PROMOTION_PASS on success; quit(1) on failure.

const CivilPromotion = preload("res://scripts/terrain_lab/site_civil_promotion.gd")
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_CIVIL_PROMOTION OK ", checks, ": ", message)
		return true
	push_error("SITE_CIVIL_PROMOTION_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _day(data: TerrainData, lab: Variant, day: int) -> Dictionary:
	data.site.minute = day * 1440 + 600
	return CivilPromotion.daily(lab)

func _run() -> void:
	var service := {"seat": "settlement:x/pos_3", "since": 4, "seen": 9}
	var v1 := {"version": 1, "capture_seq": 0, "civil_role": "clerk", "civil_service": service}
	if not _ok(PersonSocial.valid(v1) and PersonSocial.valid(PersonSocial.upgraded(v1)) and PersonSocial.upgraded(v1).civil_service == service, "civil_service is valid on v1 and v3 and kept by upgraded"): return
	for bad: Variant in [{"seat": "", "since": 1, "seen": 1}, {"seat": "a", "since": 5, "seen": 4}, {"seat": "a", "since": 1}, {"seat": "a", "since": 1, "seen": 1, "x": 0}]:
		var copy := v1.duplicate(true)
		copy["civil_service"] = bad
		if not _ok(not PersonSocial.valid(copy), "malformed civil_service refused", bad): return
	var data := _building_fixture()
	var lab := _building_lab(data)
	var actions: SitePersonActions = lab.site_controller.person_actions
	var team: TerrainArmy = lab.army
	team.roster_size = 3
	team.faction_id = 1
	var deployed := team.deploy_at(data, null, null, [Vector2i(30, 26), Vector2i(31, 26), Vector2i(32, 26)]) and team.enable_combat(false)
	if not _ok(deployed, "a three-person team deploys"): return
	team.set_process(false)
	team.settle_combat_command()
	var head := team.combat_identity(0)
	var clerk := team.combat_identity(1)
	var plain := team.combat_identity(2)
	var offices := SiteOffices.default_offices("settlement", head, false)
	data.site["settlement"] = {"owner_faction": 1, "offices": offices}
	var registry := str(offices.duties["settlement.registry"])
	var prison := str(offices.duties["settlement.prison"])
	SiteOffices.position(offices, registry).holder = clerk
	SiteOffices.position(offices, prison).holder = plain
	PersonSocial.set_civil_role(actions._person(clerk).body, "clerk")
	PersonSocial.set_learning(actions._person(clerk).body, 0) # 考試學校 E3: an illiterate clerk keeps the 60-day rule (literate: 45)
	var first := _day(data, lab, 10)
	if not _ok(int(first.counting) == 1 and PersonSocial.civil_service(actions._person(clerk).body).since == 10 and PersonSocial.civil_service(actions._person(plain).body).is_empty(), "the clerk starts counting; a person with no civil role does not", first): return
	if not _ok(int(_day(data, lab, 10).counting) == 1 and PersonSocial.civil_service(actions._person(clerk).body).seen == 10, "the same day counts once"): return
	for day: int in range(11, 40): _day(data, lab, day)
	_day(data, lab, 42)
	if not _ok(PersonSocial.civil_service(actions._person(clerk).body).since == 42, "a day without the scan (a gap) starts the count over", PersonSocial.civil_service(actions._person(clerk).body)): return
	SiteOffices.position(offices, registry).holder = -1
	SiteOffices.position(offices, prison).holder = clerk
	_day(data, lab, 43)
	if not _ok(PersonSocial.civil_service(actions._person(clerk).body).since == 43, "a different seat starts the count over"): return
	var promoted := {}
	var started := Time.get_ticks_msec()
	for day: int in range(44, 104):
		promoted = _day(data, lab, day)
		if not promoted.promoted.is_empty(): break
	if not _ok(promoted.promoted == [clerk] and int(data.site.minute) / 1440 == 103 and PersonSocial.civil_role(actions._person(clerk).body) == "official" and PersonSocial.civil_service(actions._person(clerk).body).is_empty(), "sixty days in one seat make him a 文官", [promoted, int(data.site.minute) / 1440]): return
	print("SITE_CIVIL_PROMOTION scan_ms_per_day=", float(Time.get_ticks_msec() - started) / 60.0)
	if not _ok(PersonSocial.valid(PersonSocial.read(actions._person(clerk).body)), "his packet stays valid"): return
	var granted := CivilPromotion.research_finished(actions, [plain, clerk])
	if not _ok(granted == [plain] and PersonSocial.civil_role(actions._person(plain).body) == "clerk" and PersonSocial.civil_role(actions._person(clerk).body) == "official", "research makes the plain researcher a 文吏 and leaves the 文官", granted): return
	if not _finish_workflow_body(): return
	print("SITE_CIVIL_PROMOTION_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
