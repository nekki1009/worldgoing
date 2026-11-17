extends "res://scripts/tests/site_building_ui_test.gd"
## 平民 C4a (reports/civilian-site-behavior-plan.md §4.6): residents' discontent sources and the slow-work effect. A level 2
## settlement of faction 1 (an NPC soldier head) with two civilian residents registered to one house. Checks:
## - the day records hunger +3 for a hungry resident and content -1 for a fed, housed, calm one, once a day;
## - a resident whose house is gone records homeless +2 the next day;
## - a resident killed grieves every other resident +5, once per victim; a draft records +5 once;
## - a resident at G >= 40 works at 80%; one below, and anyone not registered, at full speed;
## - C6: the long-absence catch-up's household work uses the same speeds (one slow and one full member: 1.8 shares).
## Output: SITE_RESIDENT_MOOD_PASS on success; quit(1) on failure.

const Mood = preload("res://scripts/terrain_lab/site_resident_mood.gd")
const ProduceTax = preload("res://scripts/terrain_lab/site_produce_tax.gd")
const ResidentWork = preload("res://scripts/terrain_lab/site_resident_work.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_RESIDENT_MOOD OK ", checks, ": ", message)
		return true
	push_error("SITE_RESIDENT_MOOD_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _pending(body: Variant, kind: String) -> Array:
	return SiteSocial.state_of(body).pending.filter(func(entry: Dictionary) -> bool: return str(entry.kind) == kind)

func _season(data: TerrainData) -> float:
	return (load("res://scripts/terrain_lab/site_season.gd") as Script).call("farm_factor_of_state", data.site)

func _run() -> void:
	var data := _building_fixture()
	var center := _formal_feature(data, "warehouse", Vector2i(14, 14))
	var house := _formal_feature(data, "house", Vector2i(28, 20), Vector2i.ONE, {"variant": "long"})
	var layout: Dictionary = Runtime.house_layout(data, house)
	var lab := _building_lab(data)
	var actions: SitePersonActions = lab.site_controller.person_actions
	var team: TerrainArmy = lab.army
	team.roster_size = 3
	team.faction_id = 1
	if not _ok(layout.ok and team.deploy_at(data, null, null, [Vector2i(34, 26), Vector2i(35, 26), Vector2i(36, 26)]) and team.enable_combat(false), "a three-person team deploys"): return
	team.set_process(false)
	var head := team.combat_identity(0)
	var hungry := team.combat_identity(1)
	var fed := team.combat_identity(2)
	team.combat_units[1]["military_role"] = "civilian"
	team.combat_units[2]["military_role"] = "civilian"
	data.site["settlement"] = {"settlement_id": "s1", "owner_faction": 1, "level": 2, "center_id": center, "offices": SiteOffices.default_offices("settlement", head, false)}
	data.site["housing"] = {str(hungry): {"version": 1, "house_id": house, "cell": int(layout.slots[0])}, str(fed): {"version": 1, "house_id": house, "cell": int(layout.slots[1])}}
	data.site["team_supply"] = {"t": {"sustain": {"cohorts": [{"ids": [hungry], "hunger": 2.0}, {"ids": [fed, head], "hunger": 0.0}]}}}
	var hungry_body: Dictionary = actions._person(hungry, false).body
	var fed_body: Dictionary = actions._person(fed, false).body
	if not _ok(not ProduceTax.settlement_ref(data).is_empty(), "the settlement has an organization ref"): return

	data.site.minute = 3 * 1440 + 30
	var first := Mood.day(lab)
	if not _ok(int(first.get("hungry", -1)) == 1 and int(first.content) == 1 and int(first.homeless) == 0, "day 3: one hungry, one content", first): return
	if not _ok(_pending(hungry_body, "hunger").size() == 1 and int(_pending(hungry_body, "hunger")[0].amount) == Mood.HUNGER_G and _pending(fed_body, "content").size() == 1 and int(_pending(fed_body, "content")[0].amount) == Mood.CONTENT_G, "the events carry +3 and -1"): return
	if not _ok(Mood.day(lab).is_empty(), "the day runs once"): return

	data.site.housing[str(fed)]["house_id"] = "gone"
	data.site.minute = 4 * 1440 + 30
	var second := Mood.day(lab)
	if not _ok(int(second.homeless) == 1 and _pending(fed_body, "homeless").size() == 1 and int(_pending(fed_body, "homeless")[0].amount) == Mood.HOMELESS_G, "day 4: the resident whose house is gone records +2", second): return
	data.site.housing[str(fed)]["house_id"] = house

	if not _ok(Mood.resident_killed(lab, hungry) == 1 and Mood.resident_killed(lab, hungry) == 0 and _pending(fed_body, "resident_killed").size() == 1 and _pending(hungry_body, "resident_killed").is_empty(), "a resident killed grieves the other one, once"): return
	if not _ok(Mood.resident_killed(lab, head) == 0, "a non-resident's death grieves nobody"): return
	if not _ok(Mood.drafted(lab, [fed], 100) == 1 and Mood.drafted(lab, [fed], 100) == 0 and int(_pending(fed_body, "drafted")[0].amount) == Mood.DRAFT_G, "a draft records +5 once"): return

	var ref := ProduceTax.settlement_ref(data)
	SiteSocial.relation(SiteSocial.state_of(fed_body), ref).G = 45
	var head_body: Dictionary = actions._person(head, false).body
	if not _ok(is_equal_approx(Mood.work_factor(lab, fed, fed_body), Mood.SLOW_FACTOR) and is_equal_approx(Mood.work_factor(lab, hungry, hungry_body), 1.0) and is_equal_approx(Mood.work_factor(lab, head, head_body), 1.0), "G >= 40 works at 80%; others at full speed"): return
	# C6: offline household work follows the same speeds.
	var farm := _formal_feature(data, "farm", Vector2i(46, 14), Vector2i(6, 6))
	data.site["households"] = {house: {"job": {"feature": farm}}}
	var factor := func(identity: int) -> float: return Mood.work_factor(lab, identity, actions._person(identity, false).body)
	var slow := {}
	var full := {}
	ResidentWork.daily_production(data.site, slow, data, factor)
	ResidentWork.daily_production(data.site, full, data)
	var cycle := float(Runtime.feature_recipe(data.site.features[farm]).get("cycle", 1.0))
	if not _ok(slow.has(house) and full.has(house), "both runs put work into the household's farm", [slow, full]): return
	var slow_total := float(slow[house])
	var full_total := float(full[house])
	if not _ok(is_equal_approx(fposmod(slow_total, cycle), fposmod(1.8 * ResidentWork.WORK_HOURS * 60.0 * _season(data), cycle)) and is_equal_approx(fposmod(full_total, cycle), fposmod(2.0 * ResidentWork.WORK_HOURS * 60.0 * _season(data), cycle)), "offline work: 1.8 shares with one slow member, 2 without", [slow_total, full_total, cycle]): return
	data.site.erase("households")
	data.site.erase("team_supply")
	print("SITE_RESIDENT_MOOD_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
