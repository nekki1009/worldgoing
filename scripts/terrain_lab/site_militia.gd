extends RefCounted
## 平民 C3b 鄉勇 (reports/civilian-site-behavior-plan.md §4.5; command centre 11/17: option A — the draft is allowed
## only while danger is on the Site and no fight has started, so the existing "軍職變更須脫戰" rule stays). The
## settlement's 營務 duty (settlement.garrison; the head acts while the seat is vacant) turns the settlement's resident
## civilians into soldiers and, once the danger is gone and no fight is on, back into civilians. Drafted residents keep
## their team, house and items; the schedule no longer sends them home while they are soldiers. Everyone without an age
## record counts as an adult (there are no children yet).
## The Site section `militia` {drafted: [person id], at: Site minute} remembers who was drafted, so the release turns back
## exactly them (save rules below). An NPC decider drafts at the start of an alarm and releases after it (SiteController);
## a controlled decider uses draft / release.
## The draft costs each drafted resident +5 discontent once (SiteResidentMood, C4a).
## On a crowd Site the drafted also leave the residents' team for the defenders' team (the settlement faction's largest
## captained, ungarrisoned team other than theirs) and go back on release (CrowdSite.detach_to_new_team + join_team);
## the record keeps both team ids (`home`, `into`). Without such a team they stay in the residents' team.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const Schedule = preload("res://scripts/terrain_lab/site_resident_schedule.gd")
const Mood = preload("res://scripts/terrain_lab/site_resident_mood.gd")

const SECTION := "militia"
const MAX_DRAFTED := 512

## The 營務 decider, or a refusal.
static func authority(lab: Variant, requester_id: int) -> Dictionary:
	var settlement: Dictionary = Settlement.record(lab.terrain)
	if settlement.is_empty(): return Runtime.fail("UNESTABLISHED", "尚未建制聚落")
	var resolved: Dictionary = Settlement.duty_resolve(lab, "settlement.garrison", true)
	if not bool(resolved.get("ok", false)): return resolved
	if requester_id >= 0 and int(resolved.decider) != requester_id: return Runtime.fail("NO_AUTHORITY", "只有營務官（空缺時聚落長）能徵召鄉勇")
	return Runtime.ok("", {"decider": int(resolved.decider), "owner": int(settlement.owner_faction)})

static func _role(person: Dictionary) -> String:
	var body: Variant = person.get("body")
	return str(body.get("military_role", "soldier")) if body is Dictionary else (str(body.military_role) if body is Object and "military_role" in body else "soldier")

static func _set_role(lab: Variant, identity: int, role: String) -> Dictionary:
	if lab.crowd_site != null and lab.crowd_site.active and lab.crowd_site.contains_person(identity):
		var changed: Dictionary = lab.crowd_site.native_set_military_role(identity, role)
		if not changed.ok: return changed
		return lab.crowd_site.sync_to_site()
	for team: TerrainArmy in lab.combat_armies:
		if team.index_for_identity(identity) >= 0: return team.set_military_role(identity, role)
	return Runtime.fail("NO_TARGET")

## Drafts every free, living civilian resident of the settlement's faction. Refused without danger or during a fight.
static func draft(lab: Variant, requester_id: int) -> Dictionary:
	var allowed := authority(lab, requester_id)
	if not allowed.ok: return allowed
	if float(lab.terrain.site.get("combat_left", 0.0)) > 0.0: return Runtime.fail("BUSY", "已開戰；鄉勇須在敵人進入、開戰之前徵召")
	if not Schedule.danger(lab): return Runtime.fail("NO_THREAT", "沒有敵情，不能徵召鄉勇")
	var actions: Variant = lab.site_controller.person_actions
	var record: Dictionary = lab.terrain.site.get(SECTION, {"drafted": [], "at": int(lab.terrain.site.get("minute", 0))})
	var drafted: Array = record.get("drafted", []).duplicate()
	var keys: Array = lab.terrain.site.get("housing", {}).keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	var changed: Array[int] = []
	for key: String in keys:
		var identity := int(key)
		if identity == int(lab.controlled_person_id()) or drafted.has(identity) or drafted.size() >= MAX_DRAFTED: continue
		var person: Dictionary = actions._person(identity, false)
		if person.is_empty() or float(person.hp) <= 0.0 or bool(person.get("captive", false)) or int(person.faction) != int(allowed.owner) or _role(person) != "civilian": continue
		var walking: Dictionary = actions._jobs.get(str(identity), {}) # the live job (job_for returns a copy)
		if str(walking.get("kind", "")) == "housing_return" and not bool(walking.get("cancelled", false)): actions._cancel_housing_job(walking, "徵召鄉勇")
		if lab.site_controller.work_team.is_assigned(identity): lab.site_controller.work_team.cancel(identity)
		# 平民 C1c: a resident inside his house comes out at his door to be drafted.
		if lab.get("crowd_site") != null and bool(lab.crowd_site.active) and lab.crowd_site.is_at_home(identity) and not lab.crowd_site.home_leave(identity): continue
		var done := _set_role(lab, identity, "soldier")
		if not done.ok: continue
		drafted.append(identity)
		changed.append(identity)
	if changed.is_empty(): return Runtime.fail("NO_TARGET", "沒有可徵召的居民")
	drafted.sort()
	var stored := {"drafted": drafted, "at": int(record.get("at", int(lab.terrain.site.get("minute", 0))))}
	var moved := _into_defenders(lab, changed, int(allowed.owner))
	if moved.ok:
		stored["home"] = int(moved.home)
		stored["into"] = int(moved.into)
	elif record.has("home"):
		stored["home"] = int(record.home)
		stored["into"] = int(record.into)
	lab.terrain.site[SECTION] = stored
	Mood.drafted(lab, changed, int(lab.terrain.site[SECTION].at)) # 平民 C4a: +5 discontent, once.
	if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("營務徵召鄉勇 %d 人" % changed.size())
	return Runtime.ok("已徵召鄉勇 %d 人" % changed.size(), {"drafted": changed})

## Turns the drafted back into civilians once the danger is gone and no fight is on.
static func release(lab: Variant, requester_id: int) -> Dictionary:
	var allowed := authority(lab, requester_id)
	if not allowed.ok: return allowed
	var record: Dictionary = lab.terrain.site.get(SECTION, {})
	if record.get("drafted", []).is_empty(): return Runtime.fail("NO_TARGET", "沒有在役鄉勇")
	if float(lab.terrain.site.get("combat_left", 0.0)) > 0.0 or Schedule.danger(lab): return Runtime.fail("BUSY", "敵情未解除，鄉勇不能解編")
	var actions: Variant = lab.site_controller.person_actions
	var kept: Array = []
	var released: Array[int] = []
	for raw: Variant in record.drafted:
		var identity := int(raw)
		var person: Dictionary = actions._person(identity, false)
		if person.is_empty(): continue # gone (dead, left): nothing to turn back
		if _role(person) != "soldier": continue # promoted or changed by hand since: not ours any more
		var done := _set_role(lab, identity, "civilian")
		if done.ok: released.append(identity)
		else: kept.append(identity)
	if record.has("home"): _back_home(lab, released, int(record.home), int(record.into))
	if kept.is_empty(): lab.terrain.site.erase(SECTION)
	else:
		var stored := {"drafted": kept, "at": int(record.get("at", 0))}
		if record.has("home"):
			stored["home"] = int(record.home)
			stored["into"] = int(record.into)
		lab.terrain.site[SECTION] = stored
	if lab.terrain.site.get("notices") is Array and not released.is_empty(): lab.terrain.site.notices.append("鄉勇 %d 人解編歸鄉" % released.size())
	return Runtime.ok("鄉勇 %d 人解編" % released.size(), {"released": released, "kept": kept})

## The team of `identity` on the crowd Site ({} when none).
static func _team_of(lab: Variant, identity: int) -> Dictionary:
	for team: Dictionary in lab.crowd_site.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(identity): return team
	return {}

## Moves the drafted from their residents' team into the defenders' team. {ok, home, into} or a refusal (nothing moved
## for the person refused; the others already moved stay moved and are released through the record).
static func _into_defenders(lab: Variant, people: Array, owner: int) -> Dictionary:
	if lab.crowd_site == null or not lab.crowd_site.active or people.is_empty(): return Runtime.fail("UNSUPPORTED")
	var home := int(_team_of(lab, int(people[0])).get("team_id", -1))
	var into := -1
	var best := -1
	for team: Dictionary in lab.crowd_site.teams:
		if bool(team.get("departed", false)) or int(team.get("faction", -1)) != owner or int(team.team_id) == home: continue
		var roster: Dictionary = lab.crowd_site.native_roster(int(team.team_id))
		if roster.is_empty() or int(roster.get("formal_commander", -1)) < 0 or not str(roster.get("garrison_feature_id", "")).is_empty(): continue
		if team.get("person_ids", []).size() > best:
			best = team.person_ids.size()
			into = int(team.team_id)
	if home < 0 or into < 0: return Runtime.fail("NO_TARGET", "沒有守軍隊伍")
	for raw: Variant in people:
		var identity := int(raw)
		if int(_team_of(lab, identity).get("team_id", -1)) != home: continue
		lab.crowd_site.join_team(identity, into) # same faction: straight across, no new formation
	return Runtime.ok("", {"home": home, "into": into})

## The released go back from the defenders' team to the residents' team.
static func _back_home(lab: Variant, people: Array, home: int, into: int) -> void:
	if lab.crowd_site == null or not lab.crowd_site.active: return
	for raw: Variant in people:
		var identity := int(raw)
		if int(_team_of(lab, identity).get("team_id", -1)) != into: continue
		lab.crowd_site.join_team(identity, home)

## Save rules (SiteStore): {drafted: [whole person ids], at: whole minute[, home: team id, into: team id]}.
static func validate(state: Dictionary) -> Dictionary:
	if not state.has(SECTION): return Runtime.ok()
	var raw: Variant = state[SECTION]
	var extra: Array = []
	if raw is Dictionary and raw.has("home") != raw.has("into"): return Runtime.fail("CORRUPT_SAVE", "鄉勇紀錄")
	if raw is Dictionary and raw.has("home"): extra = [raw.home, raw.into]
	if not raw is Dictionary or raw.keys().size() != 2 + extra.size() or not raw.get("drafted") is Array or raw.drafted.size() > MAX_DRAFTED or not raw.has("at"): return Runtime.fail("CORRUPT_SAVE", "鄉勇紀錄")
	for value: Variant in raw.drafted + [raw.at] + extra:
		if not (value is int or value is float) or float(value) != floorf(float(value)) or float(value) < 0.0: return Runtime.fail("CORRUPT_SAVE", "鄉勇紀錄")
	return Runtime.ok()

static func normalize(state: Dictionary) -> void:
	var raw: Variant = state.get(SECTION)
	if not raw is Dictionary: return
	for field: String in ["at", "home", "into"]:
		if raw.get(field) is float: raw[field] = int(raw[field])
	if raw.get("drafted") is Array:
		for index: int in raw.drafted.size():
			if raw.drafted[index] is float: raw.drafted[index] = int(raw.drafted[index])
