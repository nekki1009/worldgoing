extends RefCounted
## 土匪 B4d-2 (reports/bandit-faction-spec.md §4 B, §5.2, §12): routed survivors form a band.
## When a battle on a crowd Site closes, every team that routed in it is remembered in the Site section
## `bandit_rout_watch` {team id: {faction, day, members}} (never the controlled person). Once a game day the watch is
## judged with RegionBandit.rout_band: the survivors are the remembered people still on this Site, alive, free and not
## in a team of their old faction (those went home). When their faction has ended or their team no longer exists, and
## 7 days have passed, at least 3 of them form a band: a new bandit faction (origin rout) led by the most prestigious,
## its lair at the chief's cell. A team made only of survivors takes the band's faction; a survivor in a mixed team
## leaves into a new team of the band; everyone standing alone then joins the chief's team. Any other outcome (too few, has a home, a team that cannot change) drops the watch.
## Survivors elsewhere (another Site, a road) are not followed: nothing is decided without the people (§11).
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")

const SECTION := "bandit_rout_watch"
const MAX_WATCHES := 64
const MAX_MEMBERS := 512

static func day_of(controller: Variant) -> int:
	return int(float(controller.region_slot.control.logical_game_seconds) / Bandit.DAY)

## Called by SiteController.close_battle with the closed tracker: remembers every routed team's people.
static func remember(controller: Variant, routed_teams: Dictionary) -> void:
	if controller == null or controller.region_slot == null or routed_teams.is_empty(): return
	var lab: Variant = controller.lab
	if lab.crowd_site == null or not lab.crowd_site.active: return
	var watch: Dictionary = lab.terrain.site.get(SECTION, {})
	var player := int(lab.controlled_person_id())
	var keys: Array = routed_teams.keys()
	keys.sort()
	for team_id: Variant in keys:
		if watch.size() >= MAX_WATCHES: break
		var members: Array = []
		for team: Dictionary in lab.crowd_site.teams:
			if int(team.team_id) != int(team_id) or bool(team.get("departed", false)): continue
			for person: Variant in team.get("person_ids", []):
				if int(person) != player and members.size() < MAX_MEMBERS: members.append(int(person))
		if members.is_empty(): continue
		members.sort()
		watch[str(int(team_id))] = {"faction": int(routed_teams[team_id]), "day": day_of(controller), "members": members}
	if not watch.is_empty(): lab.terrain.site[SECTION] = watch

## The people of a watch who still count as routed survivors here.
static func survivors(controller: Variant, record: Dictionary) -> Array:
	var lab: Variant = controller.lab
	var player := int(lab.controlled_person_id())
	var result: Array = []
	for person: Variant in record.members:
		var identity := int(person)
		if identity == player: continue
		var target: Dictionary = lab.crowd_site.combat_target(identity)
		if target.is_empty() or float(target.get("hp", 0.0)) <= 0.0: continue
		var team := _team_of(lab, identity)
		if team.is_empty() or int(team.faction) == int(record.faction): continue
		if bool(target.owner.combat_hot_get(int(target.unit), &"captive", false)): continue
		result.append({"id": identity, "prestige": int(controller.reputation_of(identity).prestige), "controlled": false})
	return result

static func _team_of(lab: Variant, identity: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(identity): return team
	return {}

static func _team_exists(lab: Variant, team_id: int) -> bool:
	for team: Dictionary in lab.crowd_site.teams:
		if int(team.team_id) == team_id and not bool(team.get("departed", false)): return true
	return false

## Judges every watch for `today`. Returns {formed: [{band, chief, members}], dropped: [{team, reason}]}.
static func day(controller: Variant, today: int) -> Dictionary:
	var result := {"formed": [], "dropped": []}
	if controller == null or controller.region_slot == null: return result
	var lab: Variant = controller.lab
	if lab.crowd_site == null or not lab.crowd_site.active: return result
	var watch: Dictionary = lab.terrain.site.get(SECTION, {})
	if watch.is_empty(): return result
	var keys: Array = watch.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	for key: Variant in keys:
		var record: Dictionary = watch[key]
		var registry: Dictionary = controller.region_slot.control.get("faction_registry", {})
		var faction := int(record.faction)
		var faction_gone := faction != RegionFactionQuery.NEUTRAL_FACTION_ID and str(registry.get("entries", {}).get(str(faction), {}).get("status", "")) != "active"
		var team_gone := not _team_exists(lab, int(key))
		var people := survivors(controller, record)
		var judged := Bandit.rout_band(people, int(record.day), today, faction_gone, team_gone, false)
		if not judged.ok and str(judged.reason) == "waiting": continue
		watch.erase(key)
		if not judged.ok:
			result.dropped.append({"team": int(key), "reason": str(judged.reason)})
			continue
		var formed := form(controller, judged.chief, judged.members)
		if formed.ok: result.formed.append({"band": int(formed.band), "chief": int(judged.chief), "members": judged.members})
		else: result.dropped.append({"team": int(key), "reason": str(formed.get("code", "FORM_FAILED"))})
	if watch.is_empty(): lab.terrain.site.erase(SECTION)
	else: lab.terrain.site[SECTION] = watch
	return result

## Founds the band and moves its people in. Every team change is checked before anything commits; a team that cannot
## change faction alone refuses the whole formation.
static func form(controller: Variant, chief: int, members: Array) -> Dictionary:
	var lab: Variant = controller.lab
	var slot: Variant = controller.region_slot
	var chief_ref: Dictionary = JoinFaction._world_ref(controller, chief)
	if chief_ref.is_empty(): return Runtime.fail("NO_CHIEF", "頭目沒有世界人物參照")
	# Plan: whole survivor teams change faction; survivors in mixed teams leave into new teams.
	var whole: Array[int] = []
	var leavers: Array[int] = []
	var seen := {}
	for person: Variant in members:
		var team := _team_of(lab, int(person))
		if team.is_empty(): return Runtime.fail("NO_TARGET", "#%d 不在群眾隊伍" % int(person))
		var team_id := int(team.team_id)
		if seen.has(team_id): continue
		seen[team_id] = true
		var all_survivors := true
		for other: Variant in team.get("person_ids", []):
			if not members.has(int(other)): all_survivors = false
		if all_survivors:
			for other_team: Dictionary in lab.crowd_site.teams:
				if other_team != team and not bool(other_team.get("departed", false)) and lab.crowd_site.native_faction_of(other_team) == lab.crowd_site.native_faction_of(team):
					return Runtime.fail("BUSY", "#%d 的隊伍與其他隊伍共用原生陣營槽" % int(person))
			whole.append(team_id)
		else:
			for other: Variant in team.get("person_ids", []):
				if members.has(int(other)): leavers.append(int(other))
	var site_id := str(lab.terrain.site.get("id", ""))
	var cell: Vector2i = lab.crowd_site.combat_target(chief).cell
	var named := "%s寨" % str(controller.person_actions._person(chief, false).get("name", "無名"))
	var prepared: Dictionary = slot.prepare_faction_creation(lab.terrain, int(slot.control.faction_registry.revision), [],
		{"name": named.left(32), "kind": "bandit", "leader_ref": chief_ref, "founded_at": float(slot.control.logical_game_seconds),
		"bandit": {"origin": "rout", "lair": {"site_id": site_id, "cell": [cell.x, cell.y]}}})
	if not prepared.ok: return prepared
	var band := int(prepared.faction_id)
	# The band is saved first (the native hostility table reads it), then its people move and the Site saves again.
	var founded: Dictionary = controller.commit_registry(prepared)
	if not founded.ok: return founded
	for team_id: int in whole:
		var moved: Dictionary = lab.relabel_team_faction(team_id, band)
		if not moved.ok: return moved
	for person: int in leavers:
		var left: Dictionary = lab.crowd_site.detach_to_new_team(person, band)
		if not left.ok: return left
	# One band, one team: every survivor standing alone joins the chief's team (CrowdSite.join_team).
	var chief_team := int(_team_of(lab, chief).get("team_id", -1))
	for person: Variant in members:
		var team := _team_of(lab, int(person))
		if int(person) == chief or int(team.get("team_id", -1)) == chief_team or team.get("person_ids", []).size() != 1: continue
		var joined: Dictionary = lab.crowd_site.join_team(int(person), chief_team)
		if not joined.ok: return joined
	var committed: Dictionary = controller.commit_registry({"ok": true, "registry": slot.control.faction_registry})
	if not committed.ok: return committed
	if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("潰兵 %d 人落草成伙：%s" % [members.size(), named.left(32)])
	return Runtime.ok("", {"band": band})

## Save rules for the section (SiteStore): at most 64 watches of at most 512 people, whole numbers.
static func validate(state: Dictionary) -> Dictionary:
	var raw: Variant = state.get(SECTION, {})
	if not raw is Dictionary or raw.size() > MAX_WATCHES: return Runtime.fail("CORRUPT_SAVE", "潰兵紀錄")
	for key: Variant in raw:
		var record: Variant = raw[key]
		if not key is String or not str(key).is_valid_int() or not record is Dictionary or record.keys().size() != 3 \
				or not record.has("faction") or not record.has("day") or not record.get("members") is Array or record.members.size() > MAX_MEMBERS:
			return Runtime.fail("CORRUPT_SAVE", "潰兵紀錄")
		for value: Variant in [record.faction, record.day] + record.members:
			if not (value is int or value is float) or float(value) != floorf(float(value)) or float(value) < 0.0: return Runtime.fail("CORRUPT_SAVE", "潰兵紀錄")
	return Runtime.ok()

static func normalize(state: Dictionary) -> void:
	var raw: Variant = state.get(SECTION, {})
	if not raw is Dictionary: return
	for record: Variant in raw.values():
		if not record is Dictionary: continue
		for field: String in ["faction", "day"]:
			if record.get(field) is float: record[field] = int(record[field])
		if record.get("members") is Array:
			for index: int in record.members.size():
				if record.members[index] is float: record.members[index] = int(record.members[index])
