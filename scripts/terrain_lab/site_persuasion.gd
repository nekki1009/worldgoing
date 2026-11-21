extends RefCounted
## Post-battle persuasion (勸降), Nekki decision 2026-10-30
## (output/project_command_center/NEKKI_DECISION_20261030_persuasion_rules.md) and the command center v2 decisions.
##
## Window: only after the battle (site combat_left == 0), not paused, and only by the captor
## commander of that captive. One attempt per captive per post-battle window; the attempt is
## saved on the captivity relation as "persuasion" and cleared when a new battle starts
## (SiteRuntime.start_combat, which every combat start goes through). Decisions:
##  - head (rank_snapshot "head"): NEVER.
##  - officer: NEVER when loyalty before the defeat was >= 8000 (current L >= NEVER_LOYALTY_AFTER_DROP) or
##    lawful raw axis >= 80. Otherwise willing when L <= T (SiteSocial.surrender_threshold). The ten axes are
##    generated once, deterministically, from map seed + person id when the person has no valid packet.
##  - commoner / unknown: no personality and no loyalty NEVER. A deterministic 50% roll seeded by map seed,
##    captive id and captor id.
## On PERSUADED the captive joins the captor's team. Grid: the political adoption path
## (SitePoliticalAdoption.prepare with persuaded=true, which skips only the willingness check). Crowd: join_crowd
## (native transfer_member, then the captivity ends as a release ends it).

const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")
const PersonPersonality = preload("res://scripts/terrain_lab/person_personality.gd")
const PoliticalAdoption = preload("res://scripts/terrain_lab/site_political_adoption.gd")

## Loyalty to the own organization before the defeat, at or above which an officer never surrenders.
const NEVER_LOYALTY_BEFORE_DEFEAT := 8000
## The same test on the loyalty the captive has after the capture drop (SiteSocial.CAPTURE_LOYALTY_DROP = 2500): 5500.
const NEVER_LOYALTY_AFTER_DROP := NEVER_LOYALTY_BEFORE_DEFEAT - SiteSocial.CAPTURE_LOYALTY_DROP
## Officers with lawful (raw 0..100 axis, neutral 50) at or above this value never surrender.
const NEVER_LAWFUL := 80
## Commoner / unknown roll: out of 10000 (5000 = 50%).
const COMMONER_CHANCE := 5000

## Returns {ok, code, message, ...}. Codes: PERSUADED, REFUSED, NEVER, NOT_AFTER_BATTLE,
## ALREADY_TRIED, NO_AUTHORITY, NOT_CAPTIVE (plus NO_SITE for a missing lab).
static func persuade(lab: Variant, captor_commander_id: int, captive_id: int) -> Dictionary:
	if lab == null or lab.terrain == null or lab.site_controller == null:
		return _result(false, "NO_SITE", {})
	var site: Dictionary = lab.terrain.site
	if bool(site.get("paused", false)) or float(site.get("combat_left", 0.0)) > 0.0:
		return _result(false, "NOT_AFTER_BATTLE", {})
	var relation: Dictionary = site.get("captivity", {}).get(str(captive_id), {})
	if relation.is_empty() or int(relation.get("version", 0)) != 3:
		return _result(false, "NOT_CAPTIVE", {})
	# Captive belongs to the captor commander's team: the commander is the captor of record, of the captor faction.
	var actions: Variant = lab.site_controller.person_actions
	var captor: Dictionary = actions._person(captor_commander_id, false)
	if int(relation.get("captor_id", -1)) != captor_commander_id or captor.is_empty() or int(captor.get("faction", -2)) != int(relation.get("captor_faction", -1)):
		return _result(false, "NO_AUTHORITY", {})
	if relation.has("persuasion"):
		return _result(false, "ALREADY_TRIED", {})
	var person: Dictionary = actions._person(captive_id, false)
	if person.is_empty() or not person.get("body") is Dictionary:
		return _result(false, "NOT_CAPTIVE", {})
	var body: Dictionary = person.body
	var rank := str(relation.get("rank_snapshot", "unknown"))
	if rank == "officer" and not PersonPersonality.valid(body.get("personality")):
		body["personality"] = generated_personality(int(lab.terrain.seed_value), captive_id)
	var minute := int(site.get("minute", 0))
	var loyal_left := _loyalty_left(body, relation, minute)
	var decision := ""
	var message := ""
	if rank == "head":
		decision = "NEVER"
		message = "首領不向敵人勸降"
	elif rank == "officer" and loyal_left >= NEVER_LOYALTY_AFTER_DROP:
		decision = "NEVER"
		message = "效忠極高，不可勸降（忠誠 %.2f）" % (float(loyal_left) / 100.0)
	elif rank == "officer" and int(PersonPersonality.read(body.get("personality")).get("lawful", 50)) >= NEVER_LAWFUL:
		decision = "NEVER"
		message = "守法之人不可勸降"
	elif rank == "officer":
		var threshold := SiteSocial.surrender_threshold(body)
		decision = "PERSUADED" if loyal_left <= threshold else "REFUSED"
		message = "軍官依個性判定（忠誠 %.2f／門檻 %.2f）" % [float(loyal_left) / 100.0, float(threshold) / 100.0]
	else:
		decision = "PERSUADED" if roll(int(lab.terrain.seed_value), captive_id, captor_commander_id) < COMMONER_CHANCE else "REFUSED"
		message = "士兵隨機判定"
	relation["persuasion"] = {"outcome": decision}
	var result := _result(decision == "PERSUADED", decision, {"captive_id": captive_id, "captor_id": captor_commander_id, "L": loyal_left, "rank": rank})
	result["message"] = message
	if decision != "PERSUADED":
		return result
	result["adopted"] = false
	var crowd_active: bool = lab.crowd_site != null and lab.crowd_site.active
	var joined: Dictionary = join_crowd(lab, captive_id, captor_commander_id) if crowd_active else _join_grid(lab, captive_id, captor_commander_id, relation)
	result["adopted"] = bool(joined.ok)
	result["adoption_code"] = str(joined.code)
	return result

## Grid: the existing political adoption path (standing offer, then prepare / commit with persuaded=true).
static func _join_grid(lab: Variant, captive_id: int, captor_id: int, relation: Dictionary) -> Dictionary:
	var offer: Dictionary = PoliticalAdoption.standing_offer(lab, relation)
	if offer.is_empty(): return {"ok": false, "code": "NO_OFFER"}
	var prepared: Dictionary = PoliticalAdoption.prepare(lab, captive_id, {"nation_id": str(offer.nation_id), "destination_team_id": int(offer.destination_team_id), "consent": false, "persuaded": true},
		captor_id, int(offer.admission_decider))
	if not prepared.ok: return prepared
	return PoliticalAdoption.commit(lab, prepared)

## Crowd (NEKKI 2026-10-30 v2): the captive joins the captor's formation as a normal member. Order: the captor's
## nation (a head present, admission by the head acting) is checked first; then the native transfer and the captivity
## end, national posts vacated, nationality moved and corps ended (CrowdSite.transfer_captive, which refuses without
## change and commits in the grid adoption order). Nothing is changed before every check passed.
static func join_crowd(lab: Variant, captive_id: int, captor_id: int) -> Dictionary:
	var host: Variant = lab.crowd_site
	var actions: Variant = lab.site_controller.person_actions
	var site: Dictionary = lab.terrain.site
	var relation: Dictionary = site.get("captivity", {}).get(str(captive_id), {})
	if relation.is_empty(): return {"ok": false, "code": "NOT_CAPTIVE"}
	if not str(relation.get("prison_id", "")).is_empty(): return {"ok": false, "code": "BUSY"}
	if actions.is_busy(captive_id) or actions.is_busy(captor_id): return {"ok": false, "code": "BUSY"}
	var captor_owner: Variant = host.person_owner(captor_id)
	if captor_owner == null: return {"ok": false, "code": "NO_AUTHORITY"}
	# A formal nation of the captor's faction (head present, admission office acting) receives the captive; a faction
	# without one keeps the captive's nationality unchanged (no nation admission to satisfy). Both are checked first.
	var offer := _nation_for_faction(lab, int(relation.get("captor_faction", -1)))
	var nations: Dictionary = site.get("equipment_nations", {})
	var nation_id := str(offer.get("nation_id", ""))
	# Grid order (SitePoliticalAdoption.prepare): the target nation refuses a person it already has, then the plan is read.
	if not nation_id.is_empty() and nations[nation_id].get("members", []).has(captive_id): return {"ok": false, "code": "NO_CHANGE"}
	var adoption: Dictionary = {"nation_id": nation_id, "old_nations": PoliticalAdoption.nations_containing(nations, captive_id),
		"corps": PoliticalAdoption.corps_commanded_by(site, captive_id)}
	var joined: Dictionary = host.transfer_captive(captive_id, captor_id, int(captor_owner.formation_index), adoption)
	if not joined.ok: return {"ok": false, "code": str(joined.code)}
	return {"ok": true, "code": "OK", "nation_id": nation_id, "formation": int(captor_owner.formation_index)}

## The first nation (sorted id) of `faction` whose head is present and whose admission office acts; {} when none.
static func _nation_for_faction(lab: Variant, faction: int) -> Dictionary:
	var orders: Variant = lab.site_controller.equipment_orders
	var actions: Variant = lab.site_controller.person_actions
	var nations: Dictionary = lab.terrain.site.get("equipment_nations", {})
	var keys := nations.keys()
	keys.sort()
	for nation_id: String in keys:
		var nation: Dictionary = nations[nation_id]
		if not nation.has("offices") or orders.nation_head_executor(nation) <= 0: continue
		var head: Dictionary = actions._person(orders.nation_head_executor(nation))
		if head.is_empty() or int(head.faction) != faction: continue
		var admission: Dictionary = orders.nation_duty_resolve(nation, "nation.admission")
		if not bool(admission.ok): continue
		return {"nation_id": nation_id, "admission_decider": int(admission.decider)}
	return {}

## Deterministic 50% roll for ordinary soldiers. Pure: the same inputs give the same roll after save and load.
static func roll(map_seed: int, captive_id: int, captor_id: int) -> int:
	return _mix([map_seed, 101, captive_id, captor_id]) % 10000

## Ten axes, generated once per person from map seed + person id (0..100 each). Pure.
static func generated_personality(map_seed: int, person_id: int) -> Dictionary:
	var packet: Dictionary = {"version": PersonPersonality.VERSION}
	for index in range(PersonPersonality.AXES.size()):
		packet[PersonPersonality.AXES[index]] = _mix([map_seed, 202, person_id, index]) % 101
	return packet

## Loyalty to the saved organization after the custody days not yet settled (surrender_willingness rule).
static func _loyalty_left(body: Dictionary, relation: Dictionary, minute: int) -> int:
	if not relation.get("loyal_org") is Dictionary: return 0
	var willing: Dictionary = SiteSocial.surrender_willingness(body, relation, minute)
	return int(willing.get("L", 0))

static func _result(ok: bool, code: String, values: Dictionary) -> Dictionary:
	var result: Dictionary = {"ok": ok, "code": code, "message": ""}
	result.merge(values, true)
	return result

## Integer mix (FNV-style, 31-bit, no global RNG). Every multiplication stays inside 64 bits.
static func _mix(parts: Array) -> int:
	var h := 2166136261 & 0x7FFFFFFF
	for part: Variant in parts:
		h = ((h ^ (int(part) & 0x7FFFFFFF)) * 16777619) & 0x7FFFFFFF
	h = h ^ (h >> 13)
	return h & 0x7FFFFFFF
