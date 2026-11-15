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
