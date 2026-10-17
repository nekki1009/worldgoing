extends RefCounted
## R2 social state (v2 plan §6.2, §8): per person, per real organization,
## discontent G (0–100) and loyalty L (0–10000, shown /100), settled once per
## completed game day from the common Site clock (pause stops it; slow frames
## catch up to completed time, never per frame or per panel). Events are
## recorded by their original owner after a successful commit and consumed by
## the next day settlement; nothing changes nationality or makes anyone leave
## here (R2 only shows the visible omen).
##
## Data lives in the person's own social_state (PersonSocial v2) on the Army
## row / Actor and travels with that person.

const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")
const PersonPersonality = preload("res://scripts/terrain_lab/person_personality.gd")

const DAY_MINUTES := 1440
const DAY_SECONDS := 86400.0
const BASE_LOYALTY := 6000
const OMEN_DAYS := 3

static func org_key(ref: Dictionary) -> String:
	return "%s:%s:%s" % [str(ref.kind), str(ref.site_id), str(ref.org_id)]

static func team_ref(site_id: String, team_id: int) -> Dictionary:
	return {"kind": "team", "site_id": site_id, "org_id": str(team_id)}

static func _axis(body: Variant, axis: String) -> int:
	var packet: Variant = body.get("personality", {}) if body is Dictionary else (body.get("personality") if body is Object else {})
	return int(PersonPersonality.read(packet).get(axis, 50)) if packet is Dictionary else 50

## §6.2 willingness threshold T (萬分位).
static func surrender_threshold(body: Variant) -> int:
	return clampi(3000 + 20 * (_axis(body, "ambition") - 50) - 20 * (_axis(body, "lawful") - 50) - 10 * (_axis(body, "risk") - 50), 1000, 6000)

## §8.1 natural decay per day.
static func decay(body: Variant) -> int:
	return 1 + floori(maxf(0.0, 50.0 - _axis(body, "ambition")) / 25.0) + floori(maxf(0.0, _axis(body, "lawful") - 50.0) / 25.0)

## §8.4 leave threshold H.
static func leave_threshold(body: Variant) -> int:
	return clampi(70 - floori(2.0 * (_axis(body, "ambition") - 50) / 5.0) + floori(2.0 * (_axis(body, "lawful") - 50) / 5.0), 30, 95)

## Returns the person's v3 packet (upgrading v1 / empty / v2 in place).
static func state_of(body: Variant) -> Dictionary:
	var packet := PersonSocial.read(body)
	if packet.is_empty() or int(packet.get("version", 0)) < 2:
		packet = PersonSocial.upgraded(packet)
	elif int(packet.get("version", 0)) == 2:
		packet = PersonSocial.migrated_v2(packet)
	else:
		return packet
	if body is Dictionary: body.social_state = packet
	elif body is Object: body.set("social_state", packet)
	return packet

static func relation(packet: Dictionary, ref: Dictionary) -> Dictionary:
	var key := org_key(ref)
	if not packet.orgs.has(key):
		packet.orgs[key] = {"ref": ref.duplicate(), "G": 0, "L": BASE_LOYALTY, "obs": 0, "obs_from": -1, "intent": false}
	return packet.orgs[key]

## An original owner records one event after its commit. `event_id` deduplicates
## (episode, plan revision...); the next settlement of `day` consumes it.
static func record(body: Variant, ref: Dictionary, kind: String, amount: int, event_id: String, minute: int, loyalty: int = 0) -> bool:
	if not PersonSocial.valid_org_ref(ref): return false
	var packet := state_of(body)
	if packet.seen.has(event_id) or packet.pending.any(func(entry: Dictionary) -> bool: return str(entry.id) == event_id): return false
	if packet.pending.size() >= PersonSocial.MAX_PENDING: return false
	relation(packet, ref)
	packet.pending.append({"day": floori(float(minute) / DAY_MINUTES), "org": org_key(ref), "kind": kind, "amount": amount, "l": loyalty, "id": event_id})
	return true

## Settles completed days for one person from its own observation evidence (G0 F10).
## A day D is proven only when the person was observed on D (its start-of-day
## evidence is recorded then) and again on D+1 (the end stamp). Only a proven day is
## evaluated, and only from its own recorded evidence, never from the current state.
## Any other completed day since the last settlement is recorded as not executed
## (the unexecuted counter): no G/L/obs change, and its pending events are dropped
## and counted. `context`:
## {minute, controlled (bool), affiliations: [refs], captive_relation (Dictionary or {}),
##  holds_post (bool), eligible_for_post (bool), team_ref (ref or null)}.
static func settle_person(body: Variant, context: Dictionary) -> void:
	var packet := state_of(body)
	var today := floori(float(context.minute) / DAY_MINUTES)
	for ref: Dictionary in context.get("affiliations", []): relation(packet, ref)
	if int(packet.settled_day) == -2: # -2 = not started (PersonSocial.upgraded)
		packet.settled_day = today - 1 # A new record starts now; no past days are invented.
	var evidence: Dictionary = packet.evidence
	if int(evidence.get("day", -1)) != today:
		if not evidence.is_empty() and int(evidence.day) == today - 1:
			if int(packet.settled_day) < today - 1:
				_settle_day(body, packet, today - 1, evidence, int(context.minute))
				packet.proven = {"day": today - 1, "start": int(evidence.start), "end": int(context.minute)}
				packet.settled_day = today - 1
		else:
			_mark_unexecuted(packet, today - 1)
		packet.evidence = _evidence(context, today)
	_settle_captivity_days(packet, context)

## The start-of-day evidence of `day`, recorded at its first observation.
static func _evidence(context: Dictionary, day: int) -> Dictionary:
	var team_value: Variant = context.get("team_ref")
	return {"day": day, "start": int(context.minute), "affiliations": (context.get("affiliations", []) as Array).duplicate(true),
		"captive": not (context.get("captive_relation", {}) as Dictionary).is_empty(), "controlled": bool(context.get("controlled", false)),
		"holds_post": bool(context.get("holds_post", false)), "eligible_for_post": bool(context.get("eligible_for_post", false)),
		"team_ref": (team_value as Dictionary).duplicate(true) if team_value is Dictionary else {}}

## Completed days up to `through` that were not observed on both ends: recorded, not executed.
static func _mark_unexecuted(packet: Dictionary, through: int) -> void:
	var count := through - int(packet.settled_day)
	if count <= 0: return
	var kept: Array = []
	var dropped := 0
	for entry: Dictionary in packet.pending:
		if int(entry.day) > through: kept.append(entry)
		else: dropped += 1
	packet.pending = kept
	var record: Dictionary = packet.unexecuted
	record.days = int(record.days) + count
	record.events = int(record.events) + dropped
	packet.settled_day = through

static func _settle_day(body: Variant, packet: Dictionary, day: int, evidence: Dictionary, end_minute: int) -> void:
	var positive := {}
	var negative := {}
	var bonus := {}
	var kept: Array = []
	for entry: Dictionary in packet.pending:
		if int(entry.day) > day:
			kept.append(entry)
			continue
		var key := str(entry.org)
		if int(entry.amount) >= 0: positive[key] = int(positive.get(key, 0)) + int(entry.amount)
		else: negative[key] = int(negative.get(key, 0)) + int(entry.amount)
		bonus[key] = int(bonus.get(key, 0)) + int(entry.l)
		packet.seen.append(str(entry.id))
	packet.pending = kept
	while packet.seen.size() > PersonSocial.MAX_SEEN: packet.seen.pop_front()
	# 野心≥70, qualified, seven straight days without a post: +2/day from day 8.
	var team_ref_value: Variant = evidence.get("team_ref")
	var has_team: bool = team_ref_value is Dictionary and not (team_ref_value as Dictionary).is_empty()
	if bool(evidence.get("eligible_for_post", false)) and not bool(evidence.get("holds_post", false)) and _axis(body, "ambition") >= 70:
		packet.no_post_days = int(packet.no_post_days) + 1
		if int(packet.no_post_days) > 7 and has_team:
			var key := org_key(team_ref_value)
			positive[key] = int(positive.get(key, 0)) + 2
	else:
		packet.no_post_days = 0
	var captive := bool(evidence.get("captive", false))
	for key: String in packet.orgs:
		var entry: Dictionary = packet.orgs[key]
		var p := mini(20, int(positive.get(key, 0)))
		var n := int(negative.get(key, 0))
		entry.G = clampi(int(entry.G) + p + n - decay(body), 0, 100)
		var loyalty := int(entry.L) - 50 * p + int(bonus.get(key, 0))
		if p == 0 and not captive and _affiliated(evidence, entry.ref): loyalty += 50 # Free, serving, no grievance.
		entry.L = clampi(loyalty, 0, 10000)
		_omen(body, entry, bool(evidence.get("controlled", false)), end_minute)

static func _affiliated(context: Dictionary, ref: Dictionary) -> bool:
	for other: Dictionary in context.get("affiliations", []):
		if org_key(other) == org_key(ref): return true
	return false

## §8.4: G>=H on proven days for three observed days forms an intent; before that,
## dropping below H clears progress; after, only dropping below H−10 clears it.
## F11: the count starts at the first proven settlement with G>=H (obs_from = its
## end stamp). A controlled day pauses the automatic omen: progress, intent and the
## start are kept, and no intent is formed for the controlled person.
static func _omen(body: Variant, entry: Dictionary, controlled: bool, end_minute: int) -> void:
	if controlled: return
	var threshold := leave_threshold(body)
	if bool(entry.intent):
		if int(entry.G) < threshold - 10:
			entry.intent = false
			entry.obs = 0
			entry.obs_from = -1
	elif int(entry.G) >= threshold:
		if int(entry.obs) == 0: entry.obs_from = end_minute
		entry.obs = mini(int(entry.obs) + int(DAY_SECONDS), OMEN_DAYS * int(DAY_SECONDS))
		if int(entry.obs) >= OMEN_DAYS * int(DAY_SECONDS): entry.intent = true
	else:
		entry.obs = 0
		entry.obs_from = -1

## §8.2/8.3: each complete 24 h in enemy custody costs 100 loyalty to the
## organization saved at capture; counted from the capture time, never twice.
static func _settle_captivity_days(packet: Dictionary, context: Dictionary) -> void:
	var relation_value: Dictionary = context.get("captive_relation", {})
	if relation_value.is_empty() or int(relation_value.get("version", 0)) < 3 or not relation_value.get("loyal_org") is Dictionary: return
	var elapsed := float(context.minute) * 60.0 - float(relation_value.captured_at_game_seconds)
	var complete := floori(maxf(0.0, elapsed) / DAY_SECONDS)
	var delta := complete - int(relation_value.settled_days)
	if delta <= 0: return
	var entry := relation(packet, relation_value.loyal_org)
	entry.L = clampi(int(entry.L) - 100 * delta, 0, 10000)
	relation_value.settled_days = complete

## R3 §6.2: is this captive willing to surrender? Pure: the candidate loyalty
## includes the complete custody days not yet settled (settled only on commit).
## No loyal organization ("無原效忠組織") never auto-qualifies.
static func surrender_willingness(body: Variant, relation_value: Dictionary, minute: int) -> Dictionary:
	if relation_value.is_empty() or int(relation_value.get("version", 0)) < 3: return {"willing": false, "reason": "NO_RELATION"}
	if not relation_value.get("loyal_org") is Dictionary: return {"willing": false, "reason": "NO_LOYAL_ORG"}
	var packet := PersonSocial.read(body)
	var key := org_key(relation_value.loyal_org)
	var loyalty := BASE_LOYALTY
	if int(packet.get("version", 0)) >= 2 and packet.orgs.has(key): loyalty = int(packet.orgs[key].L)
	var elapsed := float(minute) * 60.0 - float(relation_value.captured_at_game_seconds)
	var unsettled := maxi(0, floori(maxf(0.0, elapsed) / DAY_SECONDS) - int(relation_value.settled_days))
	var candidate := clampi(loyalty - 100 * unsettled, 0, 10000)
	var threshold := surrender_threshold(body)
	return {"willing": candidate <= threshold, "L": candidate, "T": threshold, "reason": "" if candidate <= threshold else "LOYAL"}

## Visible status for UI (§8.4): grievance labels and remaining observation.
static func status(body: Variant, ref: Dictionary) -> Dictionary:
	var packet := PersonSocial.read(body)
	if int(packet.get("version", 0)) < 2 or not packet.orgs.has(org_key(ref)): return {}
	var entry: Dictionary = packet.orgs[org_key(ref)]
	var threshold := leave_threshold(body)
	var label := ""
	if bool(entry.intent): label = "已提出離開意向"
	elif int(entry.G) >= maxi(30, threshold - 10): label = "可能離開"
	elif int(entry.G) >= 30: label = "不滿"
	return {"G": int(entry.G), "L": int(entry.L), "threshold": threshold, "label": label, "intent": bool(entry.intent),
		"days_left": maxi(0, OMEN_DAYS - floori(float(entry.obs) / DAY_SECONDS)) if int(entry.G) >= threshold and not bool(entry.intent) else -1,
		"settled_day": int(packet.settled_day), "obs_from": int(entry.get("obs_from", -1))}

# Last fully settled Site day, per live lab (instance id → day). One process
# can hold several labs (Region cold replay, tests); a shared latch made the
# second lab skip its own first full pass that day. Cleared on every successful
# Site bind through SiteDutyAI.reset_site_state; a full pass is idempotent, so a
# clear only costs one extra pass.
static var _last_full_day := {}

static func reset_site_state() -> void:
	_last_full_day.clear()

## Called from the duty-AI tick (every 60 game seconds). A full pass runs once
## per new game day; captives' complete custody days are checked every tick.
## Crowd mode is out of scope (plan §11: new political entries are CROWD_UNSUPPORTED).
static func settle_site(lab: Variant) -> void:
	if lab == null or lab.terrain == null or (lab.crowd_site != null and lab.crowd_site.active): return
	var site: Dictionary = lab.terrain.site
	var minute := int(site.get("minute", 0))
	var today := floori(float(minute) / DAY_MINUTES)
	var lab_key: int = lab.get_instance_id()
	var full := today != int(_last_full_day.get(lab_key, -1))
	var site_id := str(site.get("id", ""))
	var controlled := int(lab.controlled_person_id())
	var captivity: Dictionary = site.get("captivity", {})
	if full:
		for team: TerrainArmy in lab.combat_armies:
			if is_instance_valid(team) and team.combat_enabled: _settle_cohort(team, site_id, today)
	for team: TerrainArmy in lab.combat_armies:
		if not is_instance_valid(team) or not team.combat_enabled: continue
		var offices := team.team_offices()
		for index in range(team.combat_units.size()):
			if team.member_gone(index): continue
			var identity := team.combat_identity(index)
			var relation_value: Dictionary = captivity.get(str(identity), {})
			if not full and relation_value.is_empty(): continue
			var member := team.is_member(index)
			var team_r: Variant = team_ref(site_id, team.team_id) if member else null
			var affiliations: Array = [team_r] if member else []
			_add_nation_refs(site, identity, site_id, affiliations)
			var label_before := str(status(team.combat_units[index], team_r).get("label", "")) if member else ""
			settle_person(team.combat_units[index], {"minute": minute, "controlled": identity == controlled, "affiliations": affiliations,
				"captive_relation": relation_value, "team_ref": team_r,
				"holds_post": index == team.formal_commander or not SiteOffices.position_of(offices, identity).is_empty(),
				"eligible_for_post": member and team.combat_can_act(index) and identity != controlled})
			if member and int(lab.controlled_member_index(team)) >= 0:
				_notify_change(lab, identity, team, label_before, str(status(team.combat_units[index], team_r).get("label", "")))
	for actor: TerrainTestCharacter in lab.combat_actors:
		if not is_instance_valid(actor) or actor.person_id <= 0 or actor.hp <= 0.0: continue
		var relation_value: Dictionary = captivity.get(str(actor.person_id), {})
		if not full and relation_value.is_empty(): continue
		var affiliations: Array = []
		var team_r: Variant = null
		for team: TerrainArmy in lab.combat_armies:
			if is_instance_valid(team) and team.player_member == actor:
				team_r = team_ref(site_id, team.team_id)
				affiliations.append(team_r)
		_add_nation_refs(site, actor.person_id, site_id, affiliations)
		settle_person(actor, {"minute": minute, "controlled": actor.person_id == controlled, "affiliations": affiliations,
			"captive_relation": relation_value, "team_ref": team_r, "holds_post": false, "eligible_for_post": false})
	if full: _last_full_day[lab_key] = today

## §8.1 battle casualties: the cohort is who was alive at the day's start (or
## at the team's formation that day). Battle deaths are rows of this team killed
## by a real hit during that day (combat_death_minute; hunger/fire excluded).
## ≥25% → +10, 10–25% → +5 for each living cohort member still in the team,
## once per team-day. A zero base makes no ratio event. Then today's cohort starts.
static func _settle_cohort(team: TerrainArmy, site_id: String, today: int) -> void:
	var cohort := team.social_cohort
	if not cohort.is_empty() and int(cohort.day) < today and not (cohort.base as Array).is_empty():
		var day := int(cohort.day)
		var dead := 0
		var survivors: Array[int] = []
		for identity: Variant in cohort.base:
			var index := team.index_for_identity(int(identity))
			if index < 0 or index == TerrainArmy.PLAYER_MEMBER: continue
			var minute := int(team.combat_units[index].get("combat_death_minute", -1))
			if float(team.combat_hot_get(index, &"hp")) <= 0.0:
				if minute >= day * DAY_MINUTES and minute < (day + 1) * DAY_MINUTES: dead += 1
			elif team.is_member(index): survivors.append(index)
		var ratio := float(dead) / float((cohort.base as Array).size())
		var amount := 10 if ratio >= 0.25 else (5 if ratio >= 0.10 else 0)
		if amount > 0:
			for index: int in survivors:
				record(team.combat_units[index], team_ref(site_id, team.team_id), "casualties", amount, "battle:%d:%d" % [team.team_id, day], day * DAY_MINUTES)
	if cohort.is_empty() or int(cohort.day) != today:
		var base: Array = []
		for index in range(team.combat_units.size()):
			if team.is_member(index) and not team.member_gone(index): base.append(team.combat_identity(index))
		team.social_cohort = {"day": today, "base": base}

## §8.4: for the player's own team, each first warning, formed intent and
## cleared intent is announced once (a label change happens once per transition).
static func _notify_change(lab: Variant, identity: int, team: TerrainArmy, before: String, after: String) -> void:
	if before == after or lab.site_controller == null: return
	var text := ""
	if after == "可能離開" and before in ["", "不滿"]: text = "隊員 #%d 可能離開本隊（不滿持續偏高）" % identity
	elif after == "已提出離開意向": text = "隊員 #%d 已提出離開意向" % identity
	elif before == "已提出離開意向": text = "隊員 #%d 已取消離開意向" % identity
	if not text.is_empty(): lab.site_controller.show_result(SiteRuntime.ok(text))

static func _add_nation_refs(site: Dictionary, identity: int, site_id: String, into: Array) -> void:
	var nations: Dictionary = site.get("equipment_nations", {})
	for nation_id: String in nations:
		if nations[nation_id].get("members", []).has(identity):
			into.append({"kind": "nation", "site_id": site_id, "org_id": nation_id})

## §8.2: before any release / ransom / change commits, complete custody days up
## to now are settled on the saved loyal organization (never lost by erase).
static func settle_before_release(body: Variant, relation_value: Dictionary, minute: int) -> void:
	if body == null or relation_value.is_empty(): return
	_settle_captivity_days(state_of(body), {"minute": minute, "captive_relation": relation_value})
