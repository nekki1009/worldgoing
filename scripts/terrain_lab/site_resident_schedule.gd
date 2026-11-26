extends RefCounted
## Resident daily schedule (平民行為 C1, reports/civilian-site-behavior-plan.md §4.2; Q3 A: a fixed timetable checked every
## ten game minutes, not need-driven). Pure rules over the Site clock (minutes); the controller applies them.
## Phases of a day (minute of day):
##   22:00–05:00 sleep (home)   05:00–06:00 wake (out: well / centre)   06:00–11:00 work
##   11:00–13:00 meal (home)    13:00–18:00 work                        18:00–22:00 evening (home)
## A diligent person (diligence above DILIGENT) starts the morning work 30 minutes early and ends the afternoon work 30
## minutes late. Rain, night and winter differences are not modelled yet.
## Household meals: two a day, at 11:00 and 18:00 (the two home phases after work); each living member eats one ration.
const DAY := 1440
const CHECK_MINUTES := 10
const DILIGENT := 60
const DILIGENT_SHIFT := 30
const SLEEP_FROM := 22 * 60
const WAKE := 5 * 60
const WORK_AM := 6 * 60
const NOON := 11 * 60
const WORK_PM := 13 * 60
const EVENING := 18 * 60
const MEAL_MINUTES := [NOON, EVENING]
const MEALS_PER_DAY := 2
## Where a phase sends the resident.
const PLACE := {"sleep": "home", "wake": "out", "work": "work", "meal": "home", "evening": "home"}
const Housing = preload("res://scripts/terrain_lab/site_housing.gd")
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const PersonPersonality = preload("res://scripts/terrain_lab/person_personality.gd")
const ResidentWork = preload("res://scripts/terrain_lab/site_resident_work.gd")
const Climate = preload("res://scripts/terrain_lab/site_climate.gd")
## 時間與氣候 TC8 (§4.7): heavy rain and storms send residents home (drizzle does not).
const SHELTER_WEATHER := ["rain", "storm"]

## 時間與氣候 TC1: the schedule reads the one calendar (SiteCalendar), not its own minute arithmetic.
static func minute_of_day(minute: float) -> int:
	return Calendar.minute_of_day(minute)

static func day_of(minute: float) -> int:
	return Calendar.day_index(minute)

## The phase at a minute of the day for a person of `diligence` (0..100).
static func phase_at(minute_in_day: int, diligence: int = 50) -> String:
	var shift := DILIGENT_SHIFT if diligence > DILIGENT else 0
	if minute_in_day >= SLEEP_FROM or minute_in_day < WAKE: return "sleep"
	if minute_in_day < WORK_AM - shift: return "wake"
	if minute_in_day < NOON: return "work"
	if minute_in_day < WORK_PM: return "meal"
	if minute_in_day < EVENING + shift: return "work"
	return "evening"

static func place_at(minute_in_day: int, diligence: int = 50) -> String:
	return str(PLACE[phase_at(minute_in_day, diligence)])

## The ten-minute check a clock minute falls in; the schedule acts once per check.
static func check_index(minute: float) -> int:
	return int(floorf(minute / float(CHECK_MINUTES)))

## Meals that fall due in the half-open clock interval (from_minute, to_minute]: [{day, meal}] in order, meal 0 = noon,
## 1 = evening. A long interval (a cold replay) returns every meal it covers.
static func meals_between(from_minute: float, to_minute: float) -> Array:
	var result: Array = []
	if to_minute <= from_minute: return result
	for day: int in range(day_of(from_minute), day_of(to_minute) + 1):
		for meal: int in range(MEAL_MINUTES.size()):
			var at := float(Calendar.day_start_minute(day) + int(MEAL_MINUTES[meal]))
			if at > from_minute and at <= to_minute: result.append({"day": day, "meal": meal})
	return result

## The diligence axis of a person dictionary (SitePersonActions._person); neutral 50 when it has no packet.
static func diligence_of(person: Dictionary) -> int:
	var body: Variant = person.get("body")
	var packet: Variant = body.get("personality") if body is Dictionary else (body.personality if body is Object and "personality" in body else null)
	return int(PersonPersonality.read(packet).diligence)

## C1a driver, run once per ten-minute check by SiteController.resident_schedule_tick. Every registered resident under
## the schedule's authority (Housing.schedule_authority) whose phase is a home phase and who is not home and not busy
## starts the normal step-by-step housing return; one still on scheduled work is taken off it first (C2). In a work phase
## a resident whose household has a job (SiteResidentWork) is handed to SiteWorkTeam, which walks him to the job's zone.
## Refusals (threat, combat, a moving person) are counted, never forced. Returns {started, refused, home, working, sent}.
## `alarm` (平民 C3): danger in the settlement sends every civilian home at once, through a fight; work stops.
static func drive(controller: Variant, minute: float, alarm: bool = false) -> Dictionary:
	var lab: Variant = controller.lab
	var actions: RefCounted = controller.person_actions
	var result := {"started": 0, "refused": 0, "home": 0, "working": 0, "sent": 0}
	var work_team: Variant = controller.work_team
	var shelter := str(Climate.for_site(lab.terrain).get("weather", "")) in SHELTER_WEATHER
	var ids: Array = lab.terrain.site.get("housing", {}).keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in ids:
		var identity := int(key)
		var person: Dictionary = actions._person(identity, false)
		if person.is_empty() or float(person.hp) <= 0.0 or not Housing.schedule_authority(lab, person): continue
		var place := place_at(minute_of_day(minute), diligence_of(person))
		if (shelter or alarm) and place in ["work", "out"]: place = "home"
		# 平民 C1c: inside the house (native absent "at home") he stays in for home phases and while sheltering; he comes
		# out at his door when the timetable sends him out, or when his house can no longer lodge him.
		var crowd_site: Variant = lab.crowd_site if lab.get("crowd_site") != null and bool(lab.crowd_site.active) else null
		if crowd_site != null and crowd_site.is_at_home(identity):
			var lodges := house_lodges(lab, identity, person)
			var at_centre: Variant = centre_cell(lab, person)
			# Sheltering at the settlement centre (no usable house) lasts while the alarm or the storm does.
			if (place == "home" and lodges) or ((alarm or shelter) and not lodges and at_centre != null and person.cell == at_centre):
				result.home = int(result.home) + 1
				continue
			if not crowd_site.home_leave(identity):
				result.refused = int(result.refused) + 1
				continue
			person = actions._person(identity, false)
			result["left_home"] = int(result.get("left_home", 0)) + 1
		if place == "work":
			if work_team.is_assigned(identity):
				result.working = int(result.working) + 1
				continue
			if ResidentWork.job_of(lab.terrain.site, identity).is_empty() or actions.is_busy(identity) or bool(person.moving) and not Housing.drifting(person): continue
			var one: Array[int] = [identity]
			if bool(work_team.assign(person.owner, one, Housing.SCHEDULE_REQUESTER).get("ok", false)): result.sent = int(result.sent) + 1
			else: result.refused = int(result.refused) + 1
			continue
		if place != "home": continue
		if work_team.is_assigned(identity):
			work_team.cancel(identity)
			continue # the housing return starts at the next check, after the work step settles
		if Housing._attends(lab, identity):
			result.home = int(result.home) + 1
			if crowd_site != null and crowd_site.home_enter(identity): result["entered"] = int(result.get("entered", 0)) + 1
			continue
		if actions.is_busy(identity) or bool(person.moving) and not Housing.drifting(person): continue
		# 平民 C1c / C3a: no house that can lodge him (burned, overrun, none) while the alarm or the storm is on: he
		# shelters at the settlement centre, walking to its entrance and going inside there.
		if (alarm or shelter) and crowd_site != null and not house_lodges(lab, identity, person):
			var centre: Variant = centre_cell(lab, person)
			if centre != null:
				if person.cell == centre:
					if crowd_site.home_enter(identity): result["sheltered"] = int(result.get("sheltered", 0)) + 1
					continue
				if bool(actions.begin_cart_walk(identity, centre, Housing.SCHEDULE_REQUESTER).get("ok", false)):
					result.started = int(result.started) + 1
					continue
		var begun: Dictionary = actions.begin_housing_return(identity, Housing.SCHEDULE_REQUESTER, alarm)
		if begun.ok: result.started = int(result.started) + 1
		else: result.refused = int(result.refused) + 1
	return result

## 平民 C1c: the settlement centre's entrance cell, when the centre stands complete and the settlement is the
## resident's faction's; null otherwise.
static func centre_cell(lab: Variant, person: Dictionary) -> Variant:
	var settlement: Dictionary = lab.terrain.site.get("settlement", {})
	if settlement.is_empty() or int(settlement.get("owner_faction", -1)) != int(person.get("faction", -2)): return null
	var feature: Dictionary = lab.terrain.site.get("features", {}).get(str(settlement.get("center_id", "")), {})
	if feature.is_empty() or str(feature.get("stage", "")) != "complete" or not feature.has("entrance"): return null
	var cell: Vector2i = lab.terrain.cell_from_index(int(feature.entrance))
	return cell if lab.terrain.contains(cell) and lab.terrain.is_walkable(cell) else null

## 平民 C1c: the house a resident is registered to can still lodge him (complete, usable, still his faction's).
static func house_lodges(lab: Variant, identity: int, person: Dictionary) -> bool:
	var registered := Housing.relation(lab, identity)
	if registered.is_empty(): return false
	var layout: Dictionary = Housing.Runtime.house_layout(lab.terrain, str(registered.house_id))
	var feature: Dictionary = lab.terrain.site.features.get(str(registered.house_id), {})
	return layout.ok and bool(layout.complete) and Housing.Runtime.feature_usable(feature, "lodging") and int(feature.get("owner_faction", -1)) == int(person.faction)

# --- 平民 C3a: danger (reports/civilian-site-behavior-plan.md §4.5) -------------------------------------------------
## Residents stay home ALARM_HOLD_MINUTES after the danger has passed.
const ALARM_HOLD_MINUTES := 30

## Danger now: the Site is fighting, or an armed person (anyone not a civilian) hostile to the settlement's owner stands
## on the Site. Without a settlement the residents' own faction is the one threatened.
static func danger(lab: Variant) -> bool:
	if float(lab.terrain.site.get("combat_left", 0.0)) > 0.0: return true
	var owner := int(lab.terrain.site.get("settlement", {}).get("owner_faction", -1)) if lab.terrain.site.get("settlement") is Dictionary else -1
	if owner < 0:
		for key: Variant in lab.terrain.site.get("housing", {}):
			var resident: Dictionary = lab.site_controller.person_actions._person(int(key), false)
			if not resident.is_empty():
				owner = int(resident.faction)
				break
	if owner < 0: return false
	var registry: Dictionary = {}
	var now := 0.0
	var slot: Variant = lab.site_controller.region_slot
	if slot != null:
		registry = slot.control.get("faction_registry", {})
		now = float(slot.control.logical_game_seconds)
	var hostile := func(faction: int) -> bool: return faction >= 0 and RegionDiplomacy.hostile(registry, owner, faction, now)
	if lab.crowd_site != null and lab.crowd_site.active:
		for team: Dictionary in lab.crowd_site.teams:
			if bool(team.get("departed", false)) or not hostile.call(int(team.get("faction", -1))): continue
			for person: Variant in team.get("person_ids", []):
				if _armed(lab, int(person)): return true
		return false
	for army: TerrainArmy in lab.combat_armies:
		if not army.combat_enabled or not hostile.call(int(army.faction_id)): continue
		for index: int in army.combat_units.size():
			if _armed(lab, army.combat_identity(index)): return true
	for actor: Variant in lab.combat_actors:
		if is_instance_valid(actor) and lab.actor_present(actor) and hostile.call(int(actor.faction_id)) and _armed(lab, int(actor.person_id)): return true
	return false

static func _armed(lab: Variant, identity: int) -> bool:
	var person: Dictionary = lab.site_controller.person_actions._person(identity, false)
	if person.is_empty() or float(person.hp) <= 0.0 or bool(person.get("captive", false)): return false
	var body: Variant = person.get("body")
	var role: String = str(body.get("military_role", "soldier")) if body is Dictionary else (str(body.military_role) if body is Object and "military_role" in body else "soldier")
	return role != "civilian"
