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
const PersonPersonality = preload("res://scripts/terrain_lab/person_personality.gd")

static func minute_of_day(minute: float) -> int:
	return int(floorf(fposmod(minute, float(DAY))))

static func day_of(minute: float) -> int:
	return int(floorf(minute / float(DAY)))

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
			var at := float(day * DAY + int(MEAL_MINUTES[meal]))
			if at > from_minute and at <= to_minute: result.append({"day": day, "meal": meal})
	return result

## The diligence axis of a person dictionary (SitePersonActions._person); neutral 50 when it has no packet.
static func diligence_of(person: Dictionary) -> int:
	var body: Variant = person.get("body")
	var packet: Variant = body.get("personality") if body is Dictionary else (body.personality if body is Object and "personality" in body else null)
	return int(PersonPersonality.read(packet).diligence)

## C1a driver, run once per ten-minute check by SiteController.resident_schedule_tick. Every registered resident under
## the schedule's authority (Housing.schedule_authority) whose phase is a home phase and who is not home and not busy
## starts the normal step-by-step housing return. Work and wake phases change nothing yet (C2 hands residents to work).
## Refusals (threat, combat, a moving person) are counted, never forced. Returns {started, refused, home}.
static func drive(controller: Variant, minute: float) -> Dictionary:
	var lab: Variant = controller.lab
	var actions: RefCounted = controller.person_actions
	var result := {"started": 0, "refused": 0, "home": 0}
	var ids: Array = lab.terrain.site.get("housing", {}).keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in ids:
		var identity := int(key)
		var person: Dictionary = actions._person(identity, false)
		if person.is_empty() or float(person.hp) <= 0.0 or not Housing.schedule_authority(lab, person): continue
		if place_at(minute_of_day(minute), diligence_of(person)) != "home": continue
		if Housing._attends(lab, identity):
			result.home = int(result.home) + 1
			continue
		if actions.is_busy(identity) or bool(person.moving): continue
		var begun: Dictionary = actions.begin_housing_return(identity, Housing.SCHEDULE_REQUESTER)
		if begun.ok: result.started = int(result.started) + 1
		else: result.refused = int(result.refused) + 1
	return result
