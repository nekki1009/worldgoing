extends RefCounted
## R5 S4 (pure): the vacancy contest timer. Its only clock is the proven political day stamp that G0 reports
## (PersonSocial v3 proven.day, recorded only when a day is observed that day and the next). No wall clock,
## no lab state. A contest opens after one proven day of continuous vacancy and reaches its deadline after two
## further proven days (plan line 475). The caller passes the vacancy onset day and each proven day it observes.

const VERSION := 1
const OPEN_DAYS := 1 # the first proven day after the onset opens the contest
const DEADLINE_DAYS := 3 # the open day plus two further proven days

## `onset_day`: the political day the vacancy began. A proven day counts only when it is strictly later than
## the onset day, so the onset day itself (which started before the vacancy) never counts.
static func empty_timer(onset_day: int) -> Dictionary:
	return {"version": VERSION, "start_day": onset_day, "last_day": onset_day, "proven_days": 0, "status": "waiting"}

static func status_for(proven_days: int) -> String:
	if proven_days >= DEADLINE_DAYS: return "deadline_reached"
	if proven_days >= OPEN_DAYS: return "open"
	return "waiting"

static func _whole(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) \
		and float(value) >= float(low) and float(value) <= float(high)

## Strict shape: exactly the five fields; days are whole and ordered; the counter and status agree.
static func valid_timer(raw: Variant) -> bool:
	if not raw is Dictionary or raw.size() != 5: return false
	for field: String in ["version", "start_day", "last_day", "proven_days", "status"]:
		if not raw.has(field): return false
	if not _whole(raw.version, VERSION, VERSION): return false
	if not _whole(raw.start_day, -1, 2147483646) or not _whole(raw.last_day, -1, 2147483646): return false
	if not _whole(raw.proven_days, 0, 2147483646): return false
	if int(raw.last_day) < int(raw.start_day): return false
	if int(raw.proven_days) == 0 and int(raw.last_day) != int(raw.start_day): return false
	return raw.status is String and str(raw.status) == status_for(int(raw.proven_days))

## Observe the proven political day G0 reports. Only a strictly later proven day counts, once, and never backwards.
## Repeating the same proven day changes nothing; an earlier day is refused and the timer is left as it was.
static func tick(raw: Variant, proven_day: int) -> Dictionary:
	if not valid_timer(raw): return {"ok": false, "code": "CORRUPT_STATE"}
	var timer: Dictionary = raw.duplicate(true)
	if proven_day < int(timer.last_day): return {"ok": false, "code": "REGRESSED"}
	if proven_day > int(timer.last_day):
		timer.proven_days = int(timer.proven_days) + 1
		timer.last_day = proven_day
		timer.status = status_for(int(timer.proven_days))
	return {"ok": true, "code": "", "timer": timer}

## JSON numbers load as floats; restore exact integers after validation.
static func normalize_numbers(timer: Dictionary) -> void:
	for field: String in ["version", "start_day", "last_day", "proven_days"]:
		if timer.has(field): timer[field] = int(timer[field])
