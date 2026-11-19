extends RefCounted
## 土匪 B4 source E (bandit spec §4 E): famine makes refugees. The spec counts a Site's supply coverage at or below 50%
## for 10 days; the live (and long-absence catch-up) day reads it from the teams' own sustain: a member is starving when
## his sustain cohort is HUNGRY_HOURS or more behind on meals, and a team is in famine on a day when at least half its
## members starve. After FAMINE_DAYS such days in a row, and every FAMINE_DAYS days while it lasts, a tenth (at least one)
## of the starving members leave the team as unaffiliated people standing alone (never the controlled person, the
## captain, a post holder or a captive); they are refugees the drifter watch then gathers (SiteBanditDrifters). People are
## not created: the refugees are the starving people themselves. The watch is the Site section `famine_watch`
## {team_id: first famine day}; a day without famine clears a team's entry.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Desertion = preload("res://scripts/terrain_lab/site_desertion.gd")

const SECTION := "famine_watch"
const HUNGRY_HOURS := 12.0
const FAMINE_DAYS := 10
const SHARE := 0.1

## The starving members of a team (sorted ids), from its sustain cohorts.
static func starving(lab: Variant, team_id: int) -> Array:
	var result: Array = []
	var entry: Variant = lab.terrain.site.get("team_supply", {}).get(str(team_id))
	if not entry is Dictionary or not entry.get("sustain") is Dictionary: return result
	for cohort: Variant in entry.sustain.get("cohorts", []):
		if not cohort is Dictionary or float(cohort.get("hunger", 0.0)) < HUNGRY_HOURS: continue
		for identity: Variant in cohort.get("ids", []): result.append(int(identity))
	result.sort()
	return result

## Today's famine pass. Returns {famine: [team ids], left: [{id, team}]}.
static func day(controller: Variant, today: int) -> Dictionary:
	var result := {"famine": [], "left": []}
	var lab: Variant = controller.lab
	if lab.crowd_site == null or not lab.crowd_site.active: return result
	var watch: Dictionary = lab.terrain.site.get(SECTION, {})
	var player := int(lab.controlled_person_id())
	var captivity: Dictionary = lab.terrain.site.get("captivity", {})
	var seen := {}
	var teams: Array = lab.crowd_site.teams.duplicate()
	teams.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.team_id) < int(b.team_id))
	for team: Dictionary in teams:
		if bool(team.get("departed", false)) or team.get("person_ids", []).size() < 2: continue
		var team_id := int(team.team_id)
		var hungry: Array = starving(lab, team_id).filter(func(p: int) -> bool: return team.person_ids.has(p))
		if hungry.size() * 2 < team.person_ids.size(): continue
		seen[str(team_id)] = true
		result.famine.append(team_id)
		if not watch.has(str(team_id)): watch[str(team_id)] = today
		var days := today - int(watch[str(team_id)])
		if days < FAMINE_DAYS or days % FAMINE_DAYS != 0: continue
		var captain := int(controller.team_captain_of_team(team_id))
		var holder: Variant = lab.crowd_site.team_holder(team_id)
		var offices: Dictionary = holder.team_offices(true) if holder != null else {}
		var leaving := maxi(1, ceili(float(hungry.size()) * SHARE))
		for identity: int in hungry:
			if leaving <= 0 or team.get("person_ids", []).size() < 2: break
			if identity == player or identity == captain or captivity.has(str(identity)): continue
			if not offices.is_empty() and not SiteOffices.position_of(offices, identity).is_empty(): continue
			var owner: Variant = lab.crowd_site.person_owner(identity)
			if owner == null or not lab.crowd_site._split_exit_ready(owner, int(lab.crowd_site._index_by_id.get(identity, -1))): continue
			var left: Dictionary = lab.crowd_site.detach_to_new_team(identity, RegionFactionQuery.NEUTRAL_FACTION_ID)
			if not left.ok: continue
			leaving -= 1
			result.left.append({"id": identity, "team": team_id})
		if not result.left.is_empty() and lab.terrain.site.get("notices") is Array:
			lab.terrain.site.notices.append("饑荒：%d 人離隊流亡" % result.left.filter(func(r: Dictionary) -> bool: return int(r.team) == team_id).size())
	for key: Variant in watch.keys():
		if not seen.has(str(key)): watch.erase(key)
	if watch.is_empty(): lab.terrain.site.erase(SECTION)
	else: lab.terrain.site[SECTION] = watch
	return result

static func validate(state: Dictionary) -> Dictionary:
	var raw: Variant = state.get(SECTION, {})
	if not raw is Dictionary or raw.size() > 4096: return Runtime.fail("CORRUPT_SAVE", "饑荒紀錄")
	for key: Variant in raw:
		var value: Variant = raw[key]
		if not key is String or not str(key).is_valid_int() or not (value is int or value is float) or float(value) != floorf(float(value)) or float(value) < 0.0:
			return Runtime.fail("CORRUPT_SAVE", "饑荒紀錄")
	return Runtime.ok()

static func normalize(state: Dictionary) -> void:
	var raw: Variant = state.get(SECTION, {})
	if not raw is Dictionary: return
	for key: Variant in raw.keys():
		if raw[key] is float: raw[key] = int(raw[key])
