extends RefCounted
## Bandit amnesty, chief succession and dispersal in a live crowd Site (reports/bandit-faction-spec.md §5.3, §6, §8; B3).
## Amnesty (招安) is in person only: the band's chief and an official of a lawful faction (its head, or viscount and above)
## stand in this Site, free and out of any fight. Either side may be the player. The official decides by the faction
## acceptance score; an NPC chief by the officer follow score plus heat / 5 (the player chief decides by asking); every
## member decides by the follow score towards the official. Followers become the official's faction; the chief swears to
## the official untitled (no title is granted). Of those who stay, 3 or more keep the band under the most prestigious of
## them; fewer disperse into one-person neutral teams; nobody left merges the band into the official's faction.
## Not a submission (FQ5): no treaty, no admission check, one transaction saved with a Region checkpoint.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const DutyAI = preload("res://scripts/terrain_lab/site_duty_ai.gd")
const CrowdSite = preload("res://scripts/terrain_lab/crowd_site.gd")
const Reputation = preload("res://scripts/terrain_lab/person_reputation.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")
const Bandit = preload("res://scripts/region_lab/region_bandit.gd")

static func _teams_of(lab: Variant, faction: int) -> Array:
	var result: Array = []
	for team: Dictionary in lab.crowd_site.teams:
		if int(team.get("faction", -1)) == faction and not bool(team.get("departed", false)) and not bool(team.get("solo", false)): result.append(team)
	return result

static func _members(lab: Variant, faction: int) -> Array[int]:
	var people: Array[int] = []
	for team: Dictionary in _teams_of(lab, faction):
		for person: Variant in team.get("person_ids", []): people.append(int(person))
	people.sort()
	return people

static func _free(lab: Variant, person: int) -> bool:
	var target: Dictionary = lab.crowd_site.combat_target(person)
	return not target.is_empty() and float(target.get("hp", 0.0)) > 0.0

## The present member with the highest prestige (ties: lowest id), or -1.
static func _heir(controller: Variant, people: Array) -> int:
	var best := -1
	var best_prestige := -1
	for person: Variant in people:
		var prestige := int(controller.reputation_of(int(person)).prestige)
		if prestige > best_prestige or prestige == best_prestige and int(person) < best:
			best = int(person)
			best_prestige = prestige
	return best

## Read-only preview: {accepted, score, chief_willing, chief_score, members: [{id, score, follows}], ...}, or a refusal.
static func preview(controller: Variant, chief_id: int, official_id: int) -> Dictionary:
	var lab: Variant = controller.lab
	if controller.region_slot == null: return Runtime.fail("NO_REGION_SLOT", "須在台灣地圖世界中才能招安")
	if lab.crowd_site == null or not lab.crowd_site.active: return Runtime.fail("UNSUPPORTED", "此地點不是群眾 Site")
	if chief_id == official_id: return Runtime.fail("INVALID", "頭目和官員不能是同一人")
	var chief: Dictionary = lab._original_person_target(chief_id)
	var official: Dictionary = lab._original_person_target(official_id)
	if chief.is_empty() or official.is_empty() or int(chief.get("unit", -1)) < 0 or int(official.get("unit", -1)) < 0: return Runtime.fail("NO_TARGET", "招安須頭目與官員當面同在此地")
	if not lab.crowd_site.contains_person(chief_id) or not lab.crowd_site.contains_person(official_id): return Runtime.fail("UNSUPPORTED", "雙方須在群眾名冊")
	var registry: Dictionary = controller.region_slot.control.get("faction_registry", {})
	var now := float(controller.region_slot.control.logical_game_seconds)
	var band := int(chief.owner.faction_id)
	var faction := int(official.owner.faction_id)
	if not RegionFactionQuery.is_bandit(registry, band) or not RegionFactionQuery.active(registry, band).ok: return Runtime.fail("NOT_BANDIT", "對方不是現存的土匪")
	if RegionFactionQuery.is_bandit(registry, faction) or faction == RegionFactionQuery.NEUTRAL_FACTION_ID or not RegionFactionQuery.active(registry, faction).ok: return Runtime.fail("NO_FACTION", "招安方須是有效的正式勢力")
	var chief_ref: Dictionary = JoinFaction._world_ref(controller, chief_id)
	var official_ref: Dictionary = JoinFaction._world_ref(controller, official_id)
	if chief_ref.is_empty() or official_ref.is_empty(): return Runtime.fail("NO_PERSON_REF", "人物沒有世界身分，無法記錄招安")
	if not RegionPeerage.same_ref(registry.entries[str(band)].leader_ref, chief_ref): return Runtime.fail("NOT_CHIEF", "只有頭目本人能談招安")
	var titled: Dictionary = JoinFaction._official_registry(registry, faction, official_ref, now)
	if not titled.ok: return titled
	if not RegionPeerage.may_hold(RegionPeerage.record_of(titled.registry, official_ref), "none"): return Runtime.fail("NOT_ACCEPTOR", "只有首長或子爵以上的貴族能招安")
	if not _free(lab, chief_id) or not _free(lab, official_id): return Runtime.fail("NOT_FREE", "雙方都須清醒自由")
	if JoinFaction._fight_nearby(lab, Vector2(chief.position)) or JoinFaction._fight_nearby(lab, Vector2(official.position)): return Runtime.fail("IN_COMBAT", "附近正在交戰，不能談招安")
	if bool(lab.crowd_site.team_morale_of(int(chief.owner.formation_index)).get("routed", false)): return Runtime.fail("ROUTED", "土匪潰逃中，不能談招安")
	var members := _members(lab, band)
	var chief_mind: Dictionary = DutyAI.personality(chief_id, null, lab)
	var official_mind: Dictionary = DutyAI.personality(official_id, null, lab)
	var chief_rep: Dictionary = controller.reputation_of(chief_id)
	var official_rep: Dictionary = controller.reputation_of(official_id)
	var score := RegionPeerage.accept_score(official_mind, chief_mind, members.size(), JoinFaction._faction_people(lab, faction)) + Reputation.accept_bonus(int(chief_rep.prestige), int(chief_rep.credit))
	var heat := int(RegionFactionQuery.bandit_of(registry, band).heat)
	var player := int(lab.controlled_person_id())
	var willing_score := Bandit.chief_score(chief_mind, official_mind, heat)
	var rows: Array = []
	for person: int in members:
		if person == chief_id: continue
		var follow := RegionPeerage.follow_score(DutyAI.personality(person, null, lab), official_mind, chief_mind) + Reputation.follow_bonus(int(chief_rep.credit), int(official_rep.credit))
		rows.append({"id": person, "score": follow, "follows": follow >= RegionPeerage.FOLLOW_THRESHOLD})
	return Runtime.ok("", {"accepted": score >= RegionPeerage.ACCEPT_THRESHOLD, "score": score,
		"chief_willing": chief_id == player or willing_score >= RegionPeerage.FOLLOW_THRESHOLD, "chief_score": willing_score,
		"members": rows, "band": band, "faction_id": faction, "chief_ref": chief_ref, "official_ref": official_ref,
		"registry": titled.registry, "now": now})

## Moves `people` (one team's members) out to their own one-person teams of `faction`; the captain cannot leave and is skipped.
static func _detach_all(lab: Variant, team: Dictionary, people: Array, faction: int) -> Dictionary:
	var roster: Dictionary = lab.crowd_site.native_roster(int(team.team_id))
	var captain := -1
	if not roster.is_empty() and int(roster.get("formal_commander", -1)) >= 0: captain = int(roster.units[int(roster.formal_commander)].person_id)
	for person: Variant in people:
		if int(person) == captain: continue
		var left: Dictionary = lab.crowd_site.detach_to_new_team(int(person), faction)
		if not left.ok: return Runtime.fail(str(left.get("code", "DETACH_FAILED")), "#%d 離隊失敗：%s" % [int(person), str(left.get("message", ""))])
	return Runtime.ok("", {"captain": captain})

## Re-sorts every team of `band`: people in `goers` end in `go_faction`, everyone else in `stay_faction`. With `solo_stay`
## every stayer ends in his own one-person team (a dispersal). Teams of one faction share a native slot and a shared slot
## cannot change faction, so a team never changes faction while people of its old faction are split off into it:
## - the captain stays: goers leave into their own teams of `go_faction`, the team keeps or takes `stay_faction`;
## - the captain goes and the band goes on: the captaincy passes to the most prestigious stayer of the team, then the goers
##   leave; - the captain goes and the band ends: the team takes `go_faction` first, then the stayers leave.
static func _resort(controller: Variant, band: int, goers: Dictionary, go_faction: int, stay_faction: int, solo_stay: bool) -> Dictionary:
	var lab: Variant = controller.lab
	for team: Dictionary in _teams_of(lab, band):
		var team_id := int(team.team_id)
		var people: Array = team.get("person_ids", []).duplicate()
		var roster: Dictionary = lab.crowd_site.native_roster(team_id)
		var captain := int(roster.units[int(roster.formal_commander)].person_id) if not roster.is_empty() and int(roster.get("formal_commander", -1)) >= 0 else int(people[0])
		var going: Array = []
		var staying: Array = []
		for person: Variant in people:
			if goers.has(int(person)): going.append(int(person))
			else: staying.append(int(person))
		var detached: Dictionary
		if goers.has(captain) and not staying.is_empty() and stay_faction == band:
			var handed: Dictionary = lab.crowd_site.hand_over_captain(team_id, _heir(controller, staying))
			if not handed.ok: return handed
			detached = _detach_all(lab, team, going, go_faction)
			if not detached.ok: return detached
		elif goers.has(captain):
			var moved: Dictionary = lab.relabel_team_faction(team_id, go_faction)
			if not moved.ok: return moved
			detached = _detach_all(lab, team, staying, stay_faction)
			if not detached.ok: return detached
		else:
			detached = _detach_all(lab, team, going, go_faction)
			if not detached.ok: return detached
			if solo_stay:
				detached = _detach_all(lab, team, staying, stay_faction)
				if not detached.ok: return detached
			var kept: Dictionary = lab.relabel_team_faction(team_id, stay_faction)
			if not kept.ok: return kept
	return Runtime.ok()

static func _commit(controller: Variant, registry: Dictionary) -> Dictionary:
	var captured: Dictionary = controller.capture_region_checkpoint("region_checkpoint", true)
	return controller.region_slot.checkpoint_region_site(controller.lab.terrain, captured.context, captured.owners, registry, false, captured) if captured.ok else captured

## Bandit spec §6. Nothing changes on a refusal.
static func amnesty(controller: Variant, chief_id: int, official_id: int) -> Dictionary:
	var seen: Dictionary = preview(controller, chief_id, official_id)
	if not seen.ok: return seen
	if not seen.accepted: return Runtime.fail("REFUSED", "官員不肯招安（接受分 %.1f，需 %.0f）" % [seen.score, RegionPeerage.ACCEPT_THRESHOLD])
	if not seen.chief_willing: return Runtime.fail("CHIEF_REFUSED", "頭目不願受招安（意願 %.1f，需 %.0f）" % [seen.chief_score, RegionPeerage.FOLLOW_THRESHOLD])
	var lab: Variant = controller.lab
	var band := int(seen.band)
	var faction := int(seen.faction_id)
	var now := float(seen.now)
	var goers := {chief_id: true}
	var stayers: Array = []
	for row: Dictionary in seen.members:
		if row.follows: goers[int(row.id)] = true
		else: stayers.append(int(row.id))
	var heir := _heir(controller, stayers) if stayers.size() >= Bandit.MIN_BAND else -1
	var heir_ref: Variant = JoinFaction._world_ref(controller, heir) if heir > 0 else null
	if heir > 0 and (heir_ref == null or heir_ref.is_empty()): return Runtime.fail("NO_PERSON_REF", "接任頭目沒有世界身分")
	var ended: Dictionary = Bandit.amnesty_end(seen.registry, band, faction, stayers.size(), heir_ref, now)
	if not ended.ok: return ended
	var sworn: Dictionary = RegionPeerage.swear(ended.registry, seen.official_ref, seen.chief_ref, now)
	if not sworn.ok: return sworn
	var stay_faction := band if stayers.size() >= Bandit.MIN_BAND else RegionFactionQuery.NEUTRAL_FACTION_ID
	var sorted: Dictionary = _resort(controller, band, goers, faction, stay_faction, stay_faction == RegionFactionQuery.NEUTRAL_FACTION_ID)
	if not sorted.ok: return sorted
	var committed: Dictionary = _commit(controller, sworn.registry)
	if not committed.ok: return committed
	controller.adjust_reputation(official_id, float(Bandit.AMNESTY_PRESTIGE), 0.0)
	var outcome := "全伙受撫" if stayers.is_empty() else ("%d 人留山，由 #%d 接任頭目" % [stayers.size(), heir] if heir > 0 else "%d 人不願受撫，各自散去" % stayers.size())
	return Runtime.ok("招安成功：%d 人改投；%s" % [goers.size(), outcome], {"goers": goers.keys(), "stayers": stayers, "heir": heir, "band": band, "faction_id": faction})

## Bandit spec §5.3 / §8: the chief is gone (dead or permanently out). The present free member with the highest prestige
## takes over; with fewer than MIN_BAND present free members the band disperses into one-person neutral teams.
## Members held captive elsewhere are not seen here and never disperse the band on their own.
static func replace_chief(controller: Variant, band: int) -> Dictionary:
	var lab: Variant = controller.lab
	if controller.region_slot == null or lab.crowd_site == null or not lab.crowd_site.active: return Runtime.fail("UNSUPPORTED", "須在群眾 Site")
	var registry: Dictionary = controller.region_slot.control.get("faction_registry", {})
	var now := float(controller.region_slot.control.logical_game_seconds)
	var free: Array = []
	for person: int in _members(lab, band):
		if _free(lab, person): free.append(person)
	if free.is_empty(): return Runtime.fail("NO_MEMBERS", "此地沒有這伙土匪的自由成員")
	if free.size() < Bandit.MIN_BAND: return disperse(controller, band)
	var heir := _heir(controller, free)
	var heir_ref: Dictionary = JoinFaction._world_ref(controller, heir)
	if heir_ref.is_empty(): return Runtime.fail("NO_PERSON_REF", "接任頭目沒有世界身分")
	var next: Dictionary = Bandit.succeed(registry, band, heir_ref, now)
	if not next.ok: return next
	var committed: Dictionary = _commit(controller, next.registry)
	if not committed.ok: return committed
	return Runtime.ok("#%d 接任頭目" % heir, {"heir": heir})

static func disperse(controller: Variant, band: int) -> Dictionary:
	var registry: Dictionary = controller.region_slot.control.get("faction_registry", {})
	var ended: Dictionary = Bandit.disperse(registry, band, float(controller.region_slot.control.logical_game_seconds))
	if not ended.ok: return ended
	var sorted: Dictionary = _resort(controller, band, {}, RegionFactionQuery.NEUTRAL_FACTION_ID, RegionFactionQuery.NEUTRAL_FACTION_ID, true)
	if not sorted.ok: return sorted
	var committed: Dictionary = _commit(controller, ended.registry)
	if not committed.ok: return committed
	return Runtime.ok("土匪潰散，成員各自成為中立單人隊", {"band": band})
