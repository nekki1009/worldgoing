extends RefCounted
## R7 E (live trigger, plan 10.3): after a contest closes through the live settle path, evaluate each loser's companion invitation with
## the pure admission rule (site_admission.gd, R7D), then run the invited supporters' departures through SiteDefectionExecutor (R7B/R7C).
## Reads only: the stored person records, the personality packet on the body, the social packet (SiteSocial.status, site_social.gd:216),
## the members of the owner and the closed episode's ballots (site_vacancy_episode.gd). Nothing is derived from the clock.
## Limitations, stated: blocked, holds_captives and carries_treasury are not read here (blocked = not awake or not free; the two others
## are false); a supporter's observed days come from SiteSocial.status (days_left, OMEN_DAYS = 3). Only the nation owner is executed.

const Admission = preload("res://scripts/terrain_lab/site_admission.gd")
const PersonPersonality = preload("res://scripts/terrain_lab/person_personality.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const Executor = preload("res://scripts/terrain_lab/site_defection_executor.gd")
const FamilyContinuity = preload("res://scripts/terrain_lab/site_family_continuity.gd") # R7 G: the family rows of a defector (listed, not executed).
const TerrainArmyType = preload("res://scripts/terrain_lab/terrain_army.gd") # R7 G: team owner check.

## The summary of the last evaluation (losers, admission codes, invited ids, execution result). Read by the tests.
static var last_summary: Dictionary = {}

static func invite_losers(lab: Variant, owner_kind: String, owner_id: String, owner_ref: Dictionary, members: Array, episode: Dictionary) -> Dictionary:
	var summary := {"owner": owner_kind, "episode": str(episode.get("episode_id", "")), "losers": []}
	var winner := int(episode.get("winner", 0))
	var roster := _roster(lab, members, episode)
	for candidate: Variant in episode.candidates:
		var loser := int(candidate)
		if loser == winner: continue
		var ambition := 50
		var lawful := 50
		var loser_body: Variant = lab.site_controller.person_actions._person(loser, false).get("body")
		if loser_body != null:
			var axes: Dictionary = PersonPersonality.read(loser_body.get("personality"))
			ambition = int(axes.ambition)
			lawful = int(axes.lawful)
		var admitted: Dictionary = Admission.admission(ambition, lawful, roster, loser)
		var entry := {"loser": loser, "admitted": bool(admitted.get("ok", false)), "code": str(admitted.get("code", "")), "invited": [], "executed": {}, "other_organisations": []}
		if bool(admitted.get("ok", false)):
			var supporters: Array = []
			for member: Dictionary in roster:
				if int(member.ballot) == loser and Admission.voter_eligible(member):
					supporters.append(_supporter(lab, member, owner_ref, ambition, lawful))
			var plan: Dictionary = Admission.invitation(supporters)
			entry["invited"] = plan.members
			entry["other_organisations"] = _other_organisations(lab, plan.members)
			if not plan.members.is_empty() and owner_kind == "nation":
				var requests: Array = []
				for identity: Variant in plan.members:
					requests.append({"person_id": int(identity), "owner_kind": "nation", "nation_id": owner_id})
				entry["executed"] = Executor.execute(lab, requests)
		summary.losers.append(entry)
	last_summary = summary
	return summary

## R7 G (plan 10.2): a defector is judged separately in each organisation ("跨組織另各自判定，不一鍵全清"), so the family and
## team rows of an invited supporter are only listed here, with executed false. The nation batch does not move them.
static func _other_organisations(lab: Variant, identities: Array) -> Array:
	var rows: Array = []
	var site: Dictionary = lab.terrain.site
	var family_ids: Array[int] = []
	if site.get("family") is Dictionary: family_ids = FamilyContinuity.member_ids(site.family, str(site.id))
	for identity: Variant in identities:
		var person_id := int(identity)
		var target: Dictionary = lab._original_person_target(person_id)
		var team_id := -1
		if not target.is_empty() and target.owner is TerrainArmyType: team_id = int(target.owner.team_id)
		rows.append({"id": person_id, "team_id": team_id, "family_member": family_ids.has(person_id), "executed": false})
	return rows

static func _roster(lab: Variant, members: Array, episode: Dictionary) -> Array:
	var roster: Array = []
	var ballots: Dictionary = episode.get("ballots", {})
	var controlled := int(lab.controlled_person_id())
	for identity: Variant in members:
		var id := int(identity)
		var person: Dictionary = lab.site_controller.person_actions._person(id, false)
		var loaded := not person.is_empty()
		roster.append({"id": id, "loaded": loaded, "alive": loaded and float(person.get("hp", 0.0)) > 0.0,
			"awake": loaded and float(person.get("ko", 0.0)) <= 0.0, "free": loaded and not bool(person.get("captive", false)) and not bool(person.get("surrender_pending", false)),
			"captive": loaded and bool(person.get("captive", false)), "in_list": true, "controlled": id == controlled, "ballot": int(ballots.get(str(id), 0))})
	return roster

static func _supporter(lab: Variant, member: Dictionary, owner_ref: Dictionary, loser_ambition: int, loser_lawful: int) -> Dictionary:
	var body: Variant = lab.site_controller.person_actions._person(int(member.id), false).get("body")
	var ambition := 50
	var lawful := 50
	var g := 0
	var intent := false
	var observed := 0
	if body != null:
		var axes: Dictionary = PersonPersonality.read(body.get("personality"))
		ambition = int(axes.ambition)
		lawful = int(axes.lawful)
		var status: Dictionary = SiteSocial.status(body, owner_ref)
		if not status.is_empty():
			g = int(status.G)
			intent = bool(status.intent)
			var days_left := int(status.days_left)
			observed = 3 if intent else (3 - days_left if days_left >= 0 else 0)
	return {"id": int(member.id), "ambition": ambition, "lawful": lawful, "g": g, "intent": intent, "observed_days": observed,
		"blocked": not bool(member.awake) or not bool(member.free), "controlled": bool(member.controlled), "willing": true,
		"holds_captives": _holds_captives(lab, int(member.id)), "carries_treasury": _carries_treasury(lab, int(member.id))}

## R7 F: the live captivity and carried-coin state of a supporter (plan 10.2/10.3): a captor of any captive holds captives; a person carrying
## coin in its own cargo (the coin withdrawn from the nation treasury, site_person_actions.gd:996) carries treasury.
static func _holds_captives(lab: Variant, identity: int) -> bool:
	for relation: Variant in lab.terrain.site.get("captivity", {}).values():
		if relation is Dictionary and int(relation.get("captor_id", -1)) == identity: return true
	return false

static func _carries_treasury(lab: Variant, identity: int) -> bool:
	var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
	var cargo: Variant = person.get("cargo", {})
	return cargo is Dictionary and int(cargo.get("coin", 0)) > 0
