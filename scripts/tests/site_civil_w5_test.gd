extends "res://scripts/tests/site_building_ui_test.gd"
## 文武官 W5 (reports/civil-military-office-plan.md §5.6, §6). Checks:
## - an NPC head raises the most 守法 candidate without a civil role to 文吏, at most once per 30 days;
## - only a qualified person passes the civil check;
## - a settlement reaching 鄉 (level 3) gives the head and the main civil officer +1 prestige each; the first look at a
##   settlement only records its level.
## Output: SITE_CIVIL_W5_PASS on success; quit(1) on failure.

const DutyAI = preload("res://scripts/terrain_lab/site_duty_ai.gd")
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")
const PersonPersonality = preload("res://scripts/terrain_lab/person_personality.gd")

var checks := 0

func _ok(condition: bool, message: String, detail: Variant = null) -> bool:
	checks += 1
	if condition:
		print("SITE_CIVIL_W5 OK ", checks, ": ", message)
		return true
	push_error("SITE_CIVIL_W5_FAIL: %s %s" % [message, str(detail)])
	quit(1)
	return false

func _run() -> void:
	var data := _building_fixture()
	var lab := _building_lab(data)
	var controller: SiteController = lab.site_controller
	var actions: SitePersonActions = controller.person_actions
	var team: TerrainArmy = lab.army
	team.roster_size = 3
	team.faction_id = 1
	if not _ok(team.deploy_at(data, null, null, [Vector2i(30, 26), Vector2i(31, 26), Vector2i(32, 26)]) and team.enable_combat(false), "a three-person team deploys"): return
	team.set_process(false)
	team.settle_combat_command()
	var head := team.combat_identity(0)
	var calm := team.combat_identity(1)
	var lawful := team.combat_identity(2)
	team.combat_units[1]["personality"] = PersonPersonality.normalized(PersonPersonality.neutral().merged({"lawful": 40}, true))
	team.combat_units[2]["personality"] = PersonPersonality.normalized(PersonPersonality.neutral().merged({"lawful": 90}, true))
	DutyAI._raised_day.clear()
	data.site.minute = 40 * 1440
	var candidates: Array[int] = [calm, lawful]
	var raised: Dictionary = DutyAI._raise_clerk(lab, head, candidates)
	if not _ok(raised.get("raised", -1) == lawful and PersonSocial.civil_role(actions._person(lawful).body) == "clerk", "the most 守法 candidate becomes 文吏", raised): return
	if not _ok(DutyAI._raise_clerk(lab, head, candidates).is_empty(), "no second raise within 30 days"): return
	data.site.minute = 71 * 1440
	if not _ok(DutyAI._raise_clerk(lab, head, candidates).get("raised", -1) == calm, "30 days later the next one"): return
	if not _ok(DutyAI._civil_ok(lab, lawful, "civil") and not DutyAI._civil_ok(lab, head, "civil"), "only a 文吏 passes the civil check"): return
	var offices := SiteOffices.default_offices("settlement", head, false)
	SiteOffices.position(offices, str(offices.duties["settlement.registry"])).holder = lawful
	data.site["settlement"] = {"owner_faction": 1, "level": 2, "offices": offices}
	controller._civil_level_prestige()
	var before_head := int(controller.reputation_of(head).prestige)
	var before_civil := int(controller.reputation_of(lawful).prestige)
	data.site.settlement.level = 3
	controller._civil_level_prestige()
	var gained_head := int(controller.reputation_of(head).prestige) - before_head
	var gained_civil := int(controller.reputation_of(lawful).prestige) - before_civil
	if not _ok(gained_head > 0 and gained_head == gained_civil, "reaching 鄉 gives the head and the 戶曹 the same civil prestige", [gained_head, gained_civil]): return
	controller._civil_level_prestige()
	if not _ok(int(controller.reputation_of(head).prestige) - before_head == gained_head, "the same level gives nothing twice"): return
	if not _finish_workflow_body(): return
	print("SITE_CIVIL_W5_PASS checks=", checks)
	for _frame: int in range(3): await process_frame
	lab.free()
	TerrainArmy.release_contact_source()
	quit(0)
