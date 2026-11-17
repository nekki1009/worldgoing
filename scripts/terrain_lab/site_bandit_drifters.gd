extends RefCounted
## 土匪 B4e (bandit spec §4 C/D/E): drifters gather into a band. Deserters, escaped captives and refugees all end as
## unaffiliated (neutral) people standing alone; on the live crowd Site the day watches every able, armed (non-civilian), unregistered
## (not a resident) neutral person who is not the player and not a captive, from the first day he is seen so. When at
## least FORM_MIN of them have been unaffiliated for FORM_WAIT_DAYS here, they found one band: the one with the highest
## prestige is chief (BanditRout.form: the band's lair is here). A person who joins a faction or leaves drops from the
## watch. The watch is the Site section `bandit_drift_watch` {person_id: first_day}.
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")
const BanditRout = preload("res://scripts/terrain_lab/site_bandit_rout.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")

const SECTION := "bandit_drift_watch"
const MAX_WATCH := 512

## The neutral drifters standing here now: [{id, prestige}], sorted by id.
static func drifters(controller: Variant) -> Array:
	var lab: Variant = controller.lab
	var player := int(lab.controlled_person_id())
	var housing: Dictionary = lab.terrain.site.get("housing", {})
	var result: Array = []
	for team: Dictionary in lab.crowd_site.teams:
		if bool(team.get("departed", false)) or int(team.get("faction", -1)) != RegionFactionQuery.NEUTRAL_FACTION_ID: continue
		# A neutral party under a captain (the player's own start, a trader's team) is not adrift: only people standing
		# alone count.
		if team.get("person_ids", []).size() != 1: continue
		for person: Variant in team.get("person_ids", []):
			var identity := int(person)
			if identity == player or housing.has(str(identity)): continue
			var target: Dictionary = lab.crowd_site.combat_target(identity)
			if target.is_empty() or float(target.get("hp", 0.0)) <= 0.0: continue
			if bool(target.owner.combat_hot_get(int(target.unit), &"captive", false)): continue
			var found: Dictionary = controller.person_actions._person(identity, false)
			if found.is_empty() or str(found.get("body", {}).get("military_role", "")) == "civilian": continue
			result.append({"id": identity, "prestige": int(controller.reputation_of(identity).prestige)})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	return result

## Updates the watch for `today` and forms a band when enough have waited. Returns {watched, formed: {band, chief,
## members} or {}, code}.
static func day(controller: Variant, today: int) -> Dictionary:
	var result := {"watched": 0, "formed": {}, "code": ""}
	if controller == null or controller.region_slot == null: return result
	var lab: Variant = controller.lab
	if lab.crowd_site == null or not lab.crowd_site.active: return result
	var watch: Dictionary = lab.terrain.site.get(SECTION, {})
	var now := drifters(controller)
	var present := {}
	for person: Dictionary in now: present[str(int(person.id))] = person
	for key: Variant in watch.keys():
		if not present.has(str(key)): watch.erase(key)
	for key: String in present:
		if not watch.has(key) and watch.size() < MAX_WATCH: watch[key] = today
	result.watched = watch.size()
	var ready: Array = []
	for person: Dictionary in now:
		var key := str(int(person.id))
		if watch.has(key) and today - int(watch[key]) >= Bandit.FORM_WAIT_DAYS: ready.append({"id": int(person.id), "prestige": int(person.prestige), "controlled": false})
	if ready.size() >= Bandit.FORM_MIN:
		ready.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.prestige) > int(b.prestige) or int(a.prestige) == int(b.prestige) and int(a.id) < int(b.id))
		var members: Array = []
		for person: Dictionary in ready: members.append(int(person.id))
		var chief := int(ready[0].id)
		var formed: Dictionary = gather(controller, chief, members)
		if formed.ok:
			for person: Variant in members: watch.erase(str(int(person)))
			result.formed = {"band": int(formed.band), "chief": chief, "members": members}
		else: result.code = str(formed.get("code", "FORM_FAILED"))
	if watch.is_empty(): lab.terrain.site.erase(SECTION)
	else: lab.terrain.site[SECTION] = watch
	return result

## Founds the band (origin refugee, lair here) and brings the loners into one team under the chief. Loners share the
## neutral native side slot, so no lone team can be relabelled: the second loner joins the chief's team, then leaves it
## as the band's first team (detach_to_new_team), the chief joins him and takes the captaincy, and every other loner
## joins (CrowdSite.join_team, changing faction). Returns {ok, band}.
static func gather(controller: Variant, chief: int, members: Array) -> Dictionary:
	var lab: Variant = controller.lab
	var slot: Variant = controller.region_slot
	if members.size() < 2 or int(members[0]) != chief: return Runtime.fail("INVALID", "成伙至少兩人，頭目在前")
	var chief_ref: Dictionary = JoinFaction._world_ref(controller, chief)
	if chief_ref.is_empty(): return Runtime.fail("NO_CHIEF", "頭目沒有世界人物參照")
	# Nothing is founded unless every move can happen now (a loner in a fight or mid-action waits for a later day).
	for person: Variant in members:
		var owner: Variant = lab.crowd_site.person_owner(int(person))
		if owner == null or not lab.crowd_site._split_exit_ready(owner, int(lab.crowd_site._index_by_id.get(int(person), -1))): return Runtime.fail("NOT_READY", "#%d 尚不能移動" % int(person))
	var cell: Vector2i = lab.crowd_site.combat_target(chief).cell
	var named := "%s寨" % str(controller.person_actions._person(chief, false).get("name", "無名"))
	var prepared: Dictionary = slot.prepare_faction_creation(lab.terrain, int(slot.control.faction_registry.revision), [],
		{"name": named.left(32), "kind": "bandit", "leader_ref": chief_ref, "founded_at": float(slot.control.logical_game_seconds),
		"bandit": {"origin": "refugee", "lair": {"site_id": str(lab.terrain.site.get("id", "")), "cell": [cell.x, cell.y]}}})
	if not prepared.ok: return prepared
	var band := int(prepared.faction_id)
	var founded: Dictionary = controller._commit_diplomacy(prepared, "")
	if not founded.ok: return founded
	var second := int(members[1])
	var chief_team := int(BanditRout._team_of(lab, chief).get("team_id", -1))
	var steps: Array = [
		func() -> Dictionary: return lab.crowd_site.join_team(second, chief_team),
		func() -> Dictionary: return lab.crowd_site.detach_to_new_team(second, band),
		func() -> Dictionary: return lab.crowd_site.join_team(chief, int(BanditRout._team_of(lab, second).get("team_id", -1)), true),
		func() -> Dictionary: return lab.crowd_site.hand_over_captain(int(BanditRout._team_of(lab, second).get("team_id", -1)), chief),
	]
	for step: Callable in steps:
		var done: Dictionary = step.call()
		if not done.ok: return done
	var band_team := int(BanditRout._team_of(lab, chief).get("team_id", -1))
	for person: Variant in members.slice(2):
		var joined: Dictionary = lab.crowd_site.join_team(int(person), band_team, true)
		if not joined.ok: return joined
	var committed: Dictionary = controller._commit_diplomacy({"ok": true, "registry": slot.control.faction_registry}, "")
	if not committed.ok: return committed
	if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("無所屬者 %d 人落草成伙：%s" % [members.size(), named.left(32)])
	return Runtime.ok("", {"band": band})

## Save rules (SiteStore): at most MAX_WATCH entries {person id string: whole day >= 0}.
static func validate(state: Dictionary) -> Dictionary:
	var raw: Variant = state.get(SECTION, {})
	if not raw is Dictionary or raw.size() > MAX_WATCH: return Runtime.fail("CORRUPT_SAVE", "無所屬者紀錄")
	for key: Variant in raw:
		var value: Variant = raw[key]
		if not key is String or not str(key).is_valid_int() or int(key) <= 0 or not (value is int or value is float) or float(value) != floorf(float(value)) or float(value) < 0.0:
			return Runtime.fail("CORRUPT_SAVE", "無所屬者紀錄")
	return Runtime.ok()

static func normalize(state: Dictionary) -> void:
	var raw: Variant = state.get(SECTION, {})
	if not raw is Dictionary: return
	for key: Variant in raw.keys():
		if raw[key] is float: raw[key] = int(raw[key])
