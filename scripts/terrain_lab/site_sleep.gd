extends RefCounted
## Sleep (時間與氣候 TC2, reports/time-and-climate-plan.md §2.1; Nekki 11/16 「TC2照你建議」): the controlled person
## sleeps and the Site stays live, run at ×8 or ×16 (SLEEP_SPEEDS) until the chosen time; no cold catch-up (TC0: a cold
## Site replays 88 game seconds per wall second). Choices: until dawn (the next 06:00), N hours, N days, the next month
## start or the next season start (SiteCalendar). Refused in combat, under threat, while moving or busy, or while not
## free and awake. Waking: the target time, combat on the Site, the sleeper hit, knocked out or captured, an enemy near, or
## the player cancelling. Runtime only (a reload wakes); the speed the player had is restored on waking.
## The record is plain data held by the SiteController: {until, speed, prior_speed, started, hit, reason}.
const Calendar = preload("res://scripts/terrain_lab/site_calendar.gd")
const Runtime = preload("res://scripts/terrain_lab/site_runtime.gd")
const SLEEP_SPEEDS: Array[float] = [8.0, 16.0]
const MODES := ["dawn", "hours", "days", "month", "season"]
const DAWN := 6 * 60
const MAX_DAYS := 120

## The world minute the sleep ends, or -1 when the request is invalid.
static func target_minute(now: int, mode: String, amount: int = 1) -> int:
	match mode:
		"dawn":
			var day := Calendar.day_index(float(now))
			var at := Calendar.day_start_minute(day) + DAWN
			return at if at > now else Calendar.day_start_minute(day + 1) + DAWN
		"hours":
			return now + amount * 60 if amount >= 1 and amount <= 24 * MAX_DAYS else -1
		"days":
			return now + amount * Calendar.DAY_MINUTES if amount >= 1 and amount <= MAX_DAYS else -1
		"month", "season":
			var next := Calendar.next_start(Calendar.day_index(float(now)) + 1, mode == "season")
			return Calendar.day_start_minute(next) + DAWN
	return -1

## Why the controlled person cannot sleep now ("" when he can). `person` is SitePersonActions._person.
static func refusal(lab: Variant, person: Dictionary) -> String:
	if lab == null or lab.terrain == null: return "沒有地點"
	if float(lab.terrain.site.get("combat_left", 0.0)) > 0.0: return "戰鬥中不能睡"
	if person.is_empty() or float(person.get("hp", 0.0)) <= 0.0 or float(person.get("ko", 0.0)) > 0.0 or bool(person.get("captive", false)): return "須存活、清醒且自由"
	if bool(person.get("moving", false)): return "先停下來"
	var actions: Variant = lab.site_controller.person_actions
	if actions.is_busy(int(person.person_id)): return "先完成手上的動作"
	if bool(actions._threat(person, {})): return "附近有敵人"
	return ""

## A new sleep record, or {} when the request is refused (the refusal text is in `error`).
static func begin(lab: Variant, person: Dictionary, mode: String, amount: int, speed: float) -> Dictionary:
	if mode not in MODES or speed not in SLEEP_SPEEDS: return {"error": "睡眠選項無效"}
	var why := refusal(lab, person)
	if not why.is_empty(): return {"error": why}
	var now := int(lab.terrain.site.get("minute", 0))
	var until := target_minute(now, mode, amount)
	if until <= now: return {"error": "睡眠時間無效"}
	return {"until": until, "speed": speed, "prior_speed": float(lab.simulation_speed), "started": now, "hit": int(person.get("hit", 0)), "reason": ""}

## Why the sleep ends now ("" to keep sleeping).
static func wake_reason(lab: Variant, record: Dictionary, person: Dictionary) -> String:
	if int(lab.terrain.site.get("minute", 0)) >= int(record.until): return "睡醒了"
	if float(lab.terrain.site.get("combat_left", 0.0)) > 0.0: return "戰鬥驚醒"
	if person.is_empty() or float(person.get("hp", 0.0)) <= 0.0: return "睡眠中斷"
	if float(person.get("ko", 0.0)) > 0.0 or bool(person.get("captive", false)) or int(person.get("hit", 0)) != int(record.hit): return "被攻擊驚醒"
	if bool(lab.site_controller.person_actions._threat(person, {})): return "敵人接近，驚醒"
	return ""
