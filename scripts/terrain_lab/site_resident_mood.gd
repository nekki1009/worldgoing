extends RefCounted
## 平民 C4a (reports/civilian-site-behavior-plan.md §4.6): residents' discontent G against their settlement. It rides the
## existing day settlement (SiteSocial: events recorded by their owner, consumed by the next day's settlement; the
## responsible organization is the settlement, the same ref the P2 tax grievance uses). Daily sources here:
##   hunger (the resident's supply cohort has gone hungry) +3, homeless (the registered house is gone or unusable) +2,
##   content (fed, housed, tax at most 10%, no alarm that day) -1.
## Event sources: a resident killed +5 to every other resident (once per victim), drafted as militia +5 (once).
## Effect here: G >= 40 works at 80% speed (SiteWorkTeam). Leaving (G >= 60) and banditry (G >= 80) are C4b.
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const ProduceTax = preload("res://scripts/terrain_lab/site_produce_tax.gd")
const Settlement = preload("res://scripts/terrain_lab/site_settlement.gd")
const PersonSocial = preload("res://scripts/terrain_lab/person_social.gd")
const SiteSocial = preload("res://scripts/terrain_lab/site_social.gd")

const HUNGER_G := 3
const HOMELESS_G := 2
const KILLED_G := 5
const DRAFT_G := 5
const CONTENT_G := -1
const CALM_TAX_MAX := 10
const SLOW_AT := 40
const SLOW_FACTOR := 0.8

static var _done := {}

static func reset() -> void:
	_done.clear()

## The resident's discontent against this Site's settlement (0 when there is none or no record).
static func g_of(data: TerrainData, body: Variant) -> int:
	var ref := ProduceTax.settlement_ref(data)
	if ref.is_empty() or body == null: return 0
	var packet: Dictionary = PersonSocial.read(body)
	if int(packet.get("version", 0)) < 2: return 0
	return int(packet.get("orgs", {}).get(SiteSocial.org_key(ref), {}).get("G", 0))

## Work speed of a registered resident: SLOW_FACTOR at G >= SLOW_AT, else 1. Anyone else works at full speed.
static func work_factor(lab: Variant, identity: int, body: Variant) -> float:
	if lab == null or lab.terrain == null or not lab.terrain.site.get("housing", {}).has(str(identity)): return 1.0
	return SLOW_FACTOR if g_of(lab.terrain, body) >= SLOW_AT else 1.0

## Hungry: a supply cohort holding this person carries hunger.
static func hungry(state: Dictionary, identity: int) -> bool:
	for entry: Variant in state.get("team_supply", {}).values():
		if not entry is Dictionary: continue
		for cohort: Variant in entry.get("sustain", {}).get("cohorts", []):
			if cohort is Dictionary and cohort.get("ids", []).has(identity) and float(cohort.get("hunger", 0.0)) > 0.0: return true
	return false

## Homeless: the registered house is missing, unusable for lodging, or no longer the settlement faction's.
static func homeless(data: TerrainData, identity: int) -> bool:
	var registration: Variant = data.site.get("housing", {}).get(str(identity))
	if not registration is Dictionary: return false
	var house: Dictionary = data.site.get("features", {}).get(str(registration.get("house_id", "")), {})
	var owner := int(Settlement.record(data).get("owner_faction", -1))
	return house.is_empty() or not Runtime.feature_usable(house, "lodging") or int(house.get("owner_faction", -2)) != owner

## Once a calendar day. Returns {hungry, homeless, content} counts, or {} when already run today / no settlement.
static func day(lab: Variant) -> Dictionary:
	if lab == null or lab.terrain == null or lab.site_controller == null: return {}
	var ref := ProduceTax.settlement_ref(lab.terrain)
	if ref.is_empty(): return {}
	var minute := int(lab.terrain.site.get("minute", 0))
	var today := Calendar.day_index(float(minute))
	var key: int = lab.get_instance_id()
	if int(_done.get(key, -1)) == today: return {}
	_done[key] = today
	var tax := int(ProduceTax.record_of(lab.terrain).get("tax_rate", 0))
	var calm := float(lab.site_controller.get("resident_alarm_until")) < float(Calendar.day_start_minute(today)) - 1440.0 or float(lab.site_controller.get("resident_alarm_until")) < 0.0
	var result := {"hungry": 0, "homeless": 0, "content": 0}
	var keys: Array = lab.terrain.site.get("housing", {}).keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for raw: String in keys:
		var identity := int(raw)
		var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
		if person.is_empty() or person.get("body") == null or float(person.get("hp", 0.0)) <= 0.0: continue
		var starving := hungry(lab.terrain.site, identity)
		var lost := homeless(lab.terrain, identity)
		var tag := "%s:%d:%d" % [SiteSocial.org_key(ref), today, identity]
		if starving and SiteSocial.record(person.body, ref, "hunger", HUNGER_G, "hunger:" + tag, minute): result.hungry = int(result.hungry) + 1
		if lost and SiteSocial.record(person.body, ref, "homeless", HOMELESS_G, "homeless:" + tag, minute): result.homeless = int(result.homeless) + 1
		if not starving and not lost and tax <= CALM_TAX_MAX and calm and SiteSocial.record(person.body, ref, "content", CONTENT_G, "content:" + tag, minute):
			result.content = int(result.content) + 1
	return result

## A registered resident was killed: every other living resident records +5 once for this victim.
static func resident_killed(lab: Variant, victim: int) -> int:
	if lab == null or lab.terrain == null or not lab.terrain.site.get("housing", {}).has(str(victim)): return 0
	var ref := ProduceTax.settlement_ref(lab.terrain)
	if ref.is_empty(): return 0
	var minute := int(lab.terrain.site.get("minute", 0))
	var count := 0
	for raw: Variant in lab.terrain.site.housing:
		var identity := int(raw)
		if identity == victim: continue
		var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
		if person.is_empty() or person.get("body") == null or float(person.get("hp", 0.0)) <= 0.0: continue
		if SiteSocial.record(person.body, ref, "resident_killed", KILLED_G, "killed:%s:%d" % [SiteSocial.org_key(ref), victim], minute): count += 1
	return count

## Residents drafted as militia record +5 once (per draft).
static func drafted(lab: Variant, people: Array, at: int) -> int:
	var ref := ProduceTax.settlement_ref(lab.terrain)
	if ref.is_empty(): return 0
	var minute := int(lab.terrain.site.get("minute", 0))
	var count := 0
	for raw: Variant in people:
		var person: Dictionary = lab.site_controller.person_actions._person(int(raw), false)
		if person.is_empty() or person.get("body") == null: continue
		if SiteSocial.record(person.body, ref, "drafted", DRAFT_G, "draft:%s:%d:%d" % [SiteSocial.org_key(ref), at, int(raw)], minute): count += 1
	return count
