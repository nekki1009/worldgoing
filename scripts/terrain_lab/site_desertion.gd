extends RefCounted
## 土匪 B4 source C (bandit spec §4 C; v2 plan §10.1–10.2 退隊): people whose leave intent toward their team stands act on
## it. SiteSocial already settles G, the three-day omen and the intent every day on the crowd Site and moves nobody; this
## daily pass carries out the 退隊 for members who can leave now: not the controlled person, not the team's formal captain
## or another post holder, not a captive, able and out of any fight or action (the native exit gate). The person leaves
## the team's roster and supply and stands alone as a neutral (unaffiliated) person on the same Site; nation membership is
## untouched (no nationality change). Each departure writes a notice. Loners later gather into a band (SiteBanditDrifters).
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")

const MAX_PER_DAY := 10 # v2 plan §10.3: at most 10 people per batch

## The members who leave today: [{id, team}], in team then person order.
static func leavers(controller: Variant) -> Array:
	var lab: Variant = controller.lab
	var result: Array = []
	if lab.crowd_site == null or not lab.crowd_site.active: return result
	var site_id := str(lab.terrain.site.get("id", ""))
	var player := int(lab.controlled_person_id())
	var captivity: Dictionary = lab.terrain.site.get("captivity", {})
	var teams: Array = lab.crowd_site.teams.duplicate()
	teams.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.team_id) < int(b.team_id))
	for team: Dictionary in teams:
		if bool(team.get("departed", false)) or bool(team.get("solo", false)) or team.get("person_ids", []).size() < 2: continue
		if int(team.get("faction", -1)) == RegionFactionQuery.NEUTRAL_FACTION_ID: continue
		var roster: Dictionary = lab.crowd_site.native_roster(int(team.team_id))
		var captain := int(controller.team_captain_of_team(int(team.team_id)))
		var holder: Variant = lab.crowd_site.team_holder(int(team.team_id))
		var offices: Dictionary = holder.team_offices(true) if holder != null else {}
		var ref := SiteSocial.team_ref(site_id, int(team.team_id))
		var ids: Array = team.person_ids.duplicate()
		ids.sort()
		for raw: Variant in ids:
			var identity := int(raw)
			if identity == player or identity == captain or captivity.has(str(identity)): continue
			if not offices.is_empty() and not SiteOffices.position_of(offices, identity).is_empty(): continue
			var found: Dictionary = controller.person_actions._person(identity, false)
			if found.is_empty() or float(found.get("hp", 0.0)) <= 0.0: continue
			if not bool(SiteSocial.status(found.body, ref).get("intent", false)): continue
			var owner: Variant = lab.crowd_site.person_owner(identity)
			if owner == null or not lab.crowd_site._split_exit_ready(owner, int(lab.crowd_site._index_by_id.get(identity, -1))): continue
			result.append({"id": identity, "team": int(team.team_id)})
			if result.size() >= MAX_PER_DAY: return result
	return result

## Carries out today's departures. Returns {left: [{id, team}], failed: [{id, code}]}.
static func day(controller: Variant) -> Dictionary:
	var result := {"left": [], "failed": []}
	if controller == null or controller.lab == null: return result
	var lab: Variant = controller.lab
	var player := int(lab.controlled_person_id())
	for leaver: Dictionary in leavers(controller):
		# A team can shrink below two people during the pass: its last member never leaves himself.
		var team: Dictionary = {}
		for candidate: Dictionary in lab.crowd_site.teams:
			if int(candidate.team_id) == int(leaver.team) and not bool(candidate.get("departed", false)): team = candidate
		if team.get("person_ids", []).size() < 2: continue
		var left: Dictionary = lab.crowd_site.detach_to_new_team(int(leaver.id), RegionFactionQuery.NEUTRAL_FACTION_ID)
		if not left.ok:
			result.failed.append({"id": int(leaver.id), "code": str(left.get("code", ""))})
			continue
		result.left.append(leaver)
		var name := str(controller.person_actions._person(int(leaver.id), false).get("body", {}).get("name", "#%d" % int(leaver.id)))
		var mine: bool = team.get("person_ids", []).has(player)
		if lab.terrain.site.get("notices") is Array:
			lab.terrain.site.notices.append(("本隊 %s 心懷不滿，離隊而去" if mine else "%s 離開所屬隊伍") % name)
	return result
