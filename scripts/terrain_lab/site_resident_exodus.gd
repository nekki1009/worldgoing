extends RefCounted
## 平民 C4b (reports/civilian-site-behavior-plan.md §4.6, §4.7): a discontented household leaves, or goes outlaw.
## Every 30th game day, on the active Site only (a cold Site decides nothing it did not see, §4.9 is C6), each household
## of the settlement is judged by the mean discontent G of its living members against the settlement:
##   mean G >= 60: the household leaves with chance (G − 50) / 50, rolled from the world seed, the house and the day,
##     so a reload never re-rolls. At mean G >= 80 half of those leaving go outlaw instead.
## Leaving: the members' housing registrations end, they gather into one neutral team under the household head (the
## head leaves the residents team into his own team, the others join it) and the head takes them onto the Region map
## toward the first land neighbour Site (RegionAI.prepare_captain_dispatch, reason emigrate). Going outlaw: the same team
## becomes a new band (origin refugee) led by the head, its lair at his cell; the band stays on this Site.
## Members who are not free here (dead, captive, busy, controlled, the settlement's head) stay behind and keep their registration.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Households = preload("res://scripts/terrain_lab/site_households.gd")
const Mood = preload("res://scripts/terrain_lab/site_resident_mood.gd")
const JoinFaction = preload("res://scripts/terrain_lab/site_join_faction.gd")

const EVERY_DAYS := 30
const LEAVE_AT := 60
const OUTLAW_AT := 80
const NEIGHBOURS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]

## Chance that a household of mean G `mean` leaves this time.
static func leave_chance(mean: float) -> float:
	return 0.0 if mean < LEAVE_AT else clampf((mean - 50.0) / 50.0, 0.0, 1.0)

static func roll(world_seed: int, house_id: String, day: int, what: String) -> float:
	return float(posmod(hash([world_seed, house_id, day, what]), 1000000)) / 1000000.0

## The households that leave today: [{house_id, members, mean, outlaw}]. Pure over the Site state and the bodies.
static func judge(controller: Variant, day: int, world_seed: int) -> Array:
	var result: Array = []
	var lab: Variant = controller.lab
	if day % EVERY_DAYS != 0: return result
	var houses: Dictionary = Households.membership(lab.terrain.site)
	var ids: Array = houses.keys()
	ids.sort()
	for house_id: String in ids:
		var members: Array = []
		var total := 0
		for identity: Variant in houses[house_id]:
			var person: Dictionary = controller.person_actions._person(int(identity), false)
			if person.is_empty() or float(person.get("hp", 0.0)) <= 0.0 or person.get("body") == null: continue
			members.append(int(identity))
			total += Mood.g_of(lab.terrain, person.body)
		if members.is_empty(): continue
		var mean := float(total) / float(members.size())
		if roll(world_seed, house_id, day, "leave") >= leave_chance(mean): continue
		result.append({"house_id": house_id, "members": members, "mean": mean,
			"outlaw": mean >= OUTLAW_AT and roll(world_seed, house_id, day, "outlaw") < 0.5})
	return result

## Runs the 30-day judgement once on day `day` for the active Site. Returns {left: [...], outlaw: [...], failed: [...]}.
static func day(controller: Variant, day: int, world_seed: int) -> Dictionary:
	var result := {"left": [], "outlaw": [], "failed": []}
	if controller == null or controller.region_slot == null or controller.lab.crowd_site == null or not controller.lab.crowd_site.active: return result
	if controller.lab.terrain.site.get("settlement", {}).is_empty(): return result
	for verdict: Dictionary in judge(controller, day, world_seed):
		var done := depart(controller, verdict.members, bool(verdict.outlaw))
		if done.ok: (result.outlaw if bool(verdict.outlaw) else result.left).append({"house_id": verdict.house_id, "team_id": int(done.team_id)})
		else: result.failed.append({"house_id": verdict.house_id, "code": str(done.get("code", ""))})
	return result

## Gathers `people` (the first free one leads) into one team and sends it away or makes it a band.
static func depart(controller: Variant, people: Array, outlaw: bool) -> Dictionary:
	var lab: Variant = controller.lab
	var crowd: Variant = lab.crowd_site
	var player := int(lab.controlled_person_id())
	var free: Array[int] = []
	# The settlement's head stays (2026-11-25): without a head of its own faction the Site could not be saved any more.
	var head_holder := int(SiteOffices.head_position(lab.terrain.site.get("settlement", {}).get("offices", {})).get("holder", 0))
	for raw: Variant in people:
		var identity := int(raw)
		if identity == head_holder and head_holder > 0: continue
		var person: Dictionary = controller.person_actions._person(identity, false)
		if identity == player or person.is_empty() or float(person.get("hp", 0.0)) <= 0.0 or bool(person.get("captive", false)) or controller.person_actions.is_busy(identity): continue
		free.append(identity)
	if free.is_empty(): return Runtime.fail("NO_TARGET", "沒有可離開的成員")
	# Who leaves stops his work for the settlement; the step he is in ends first (NOT_READY until then).
	for identity: int in free:
		if controller.work_team.is_assigned(identity): controller.work_team.cancel(identity)
	var head := free[0]
	# Gather: the head leaves into his own neutral team, the others join him.
	# A head who already stands alone (his own one-person team) keeps it; otherwise he leaves into his own neutral team.
	var own_team: Dictionary = _team_of_crowd(crowd, head)
	var team_id := -1
	if own_team.get("person_ids", []).size() == 1: team_id = int(own_team.team_id)
	else:
		var left: Dictionary = crowd.detach_to_new_team(head, RegionFactionQuery.NEUTRAL_FACTION_ID)
		if not left.ok: return left
		team_id = int(left.team_id)
	for identity: int in free.slice(1):
		# Straight across into the head's neutral team (no new native formation).
		var joined: Dictionary = crowd.join_team(identity, team_id, true)
		if not joined.ok: return joined
	# Seat the head as the native World would at its next step: formal captain, present and able.
	var formation := -1
	for team: Dictionary in crowd.teams:
		if int(team.team_id) == team_id: formation = int(team.formation)
	if formation >= 0: crowd.set_formation_fields(formation, {"current_person": head, "commander_present": 1.0})
	for identity: int in free: lab.terrain.site.get("housing", {}).erase(str(identity))
	Households.reconcile(lab.terrain.site)
	if outlaw: return _outlaw(controller, head, team_id)
	return _emigrate(controller, head, team_id)

static func _team_of_crowd(crowd: Variant, identity: int) -> Dictionary:
	for team: Dictionary in crowd.teams:
		if not bool(team.get("departed", false)) and team.get("person_ids", []).has(identity): return team
	return {}

static func _outlaw(controller: Variant, head: int, team_id: int) -> Dictionary:
	var lab: Variant = controller.lab
	var slot: Variant = controller.region_slot
	var head_ref: Dictionary = JoinFaction._world_ref(controller, head)
	if head_ref.is_empty(): return Runtime.fail("NO_PERSON_REF")
	var cell: Vector2i = lab.crowd_site.combat_target(head).cell
	var named := "%s寨" % str(controller.person_actions._person(head, false).get("name", "無名"))
	var prepared: Dictionary = slot.prepare_faction_creation(lab.terrain, int(slot.control.faction_registry.revision), [],
		{"name": named.left(32), "kind": "bandit", "leader_ref": head_ref, "founded_at": float(slot.control.logical_game_seconds),
		"bandit": {"origin": "refugee", "lair": {"site_id": str(lab.terrain.site.get("id", "")), "cell": [cell.x, cell.y]}}})
	if not prepared.ok: return prepared
	var founded: Dictionary = controller.commit_registry(prepared)
	if not founded.ok: return founded
	var moved: Dictionary = lab.relabel_team_faction(team_id, int(prepared.faction_id))
	if not moved.ok: return moved
	var saved: Dictionary = controller.commit_registry({"ok": true, "registry": slot.control.faction_registry})
	if not saved.ok: return saved
	if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("不滿的居民一戶落草：%s" % named.left(32))
	return Runtime.ok("", {"team_id": team_id, "band": int(prepared.faction_id)})

## The gathered team waits for the native World to seat its captain (it does so at its next step), then leaves; the
## controller's schedule check calls dispatch_pending. The wait is runtime only: after a reload the gathered, unregistered
## neutral team simply stays on the Site.
const PENDING := &"resident_emigrants"
const MAX_TRIES := 30

static func _emigrate(controller: Variant, head: int, team_id: int) -> Dictionary:
	var sent := _send(controller, head, team_id)
	if sent.ok or str(sent.get("code", "")) != "WAITING": return sent
	var pending: Array = controller.get_meta(PENDING, [])
	pending.append({"team_id": team_id, "head": head, "tries": 0})
	controller.set_meta(PENDING, pending)
	return Runtime.ok("", {"team_id": team_id, "pending": true})

## Sends every gathered household whose captain is seated. Returns [{team_id, token, target} or {team_id, code}].
static func dispatch_pending(controller: Variant) -> Array:
	var results: Array = []
	if not controller.has_meta(PENDING): return results
	var kept: Array = []
	for entry: Dictionary in controller.get_meta(PENDING, []):
		var sent := _send(controller, int(entry.head), int(entry.team_id))
		if sent.ok:
			results.append(sent)
			continue
		entry.tries = int(entry.tries) + 1
		if str(sent.get("code", "")) == "WAITING" and int(entry.tries) < MAX_TRIES: kept.append(entry)
		else: results.append({"team_id": int(entry.team_id), "code": str(sent.get("code", ""))})
	if kept.is_empty(): controller.remove_meta(PENDING)
	else: controller.set_meta(PENDING, kept)
	return results

static func _send(controller: Variant, head: int, team_id: int) -> Dictionary:
	var lab: Variant = controller.lab
	var slot: Variant = controller.region_slot
	var here: Dictionary = slot._coordinate(lab.terrain)
	if not here.ok: return here
	var person: Dictionary = lab.crowd_site.combat_target(head)
	var component: int = RegionTravelSite.start_component(slot, here.site, person.cell, lab.terrain)
	var refusals: Array = []
	for step: Vector2i in NEIGHBOURS:
		var next: Vector2i = here.site + step
		var summary: Dictionary = slot.source.get_site_summary(next.x, next.y) if slot.source != null else {}
		if not summary.get("ok", false) or str(summary.get("status", "")) not in ["land", "mixed"]:
			refusals.append([next.x, next.y, str(summary.get("status", summary.get("code", "")))])
			continue
		var token := "emigrate_%s" % Crypto.new().generate_random_bytes(12).hex_encode()
		var prepared: Dictionary = slot.prepare_npc_region_dispatch(lab, "captain:emigrate", team_id, next, component, [], token)
		if not prepared.ok:
			if str(prepared.get("code", "")) == "NO_COMMANDER": return Runtime.fail("WAITING", "隊長尚未就位")
			refusals.append([next.x, next.y, str(prepared.get("code", "")), str(prepared.get("message", ""))])
			continue
		var committed: Dictionary = slot.commit_npc_region_dispatch(prepared)
		if not committed.ok: return committed
		if lab.terrain.site.get("notices") is Array: lab.terrain.site.notices.append("不滿的居民一戶出走")
		return Runtime.ok("", {"ok": true, "team_id": team_id, "token": token, "target": [next.x, next.y]})
	return Runtime.fail("NO_ROUTE", "附近沒有可去的地方；這戶留在原地").merged({"refusals": refusals, "component": component}, true)
